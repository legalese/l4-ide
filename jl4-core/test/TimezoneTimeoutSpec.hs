{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | A timezone operation must not swallow the evaluation timeout
-- (smucclaw\/l4-ide#1001).
--
-- @jl4-service@ bounds an evaluation with 'System.Timeout.timeout'. That
-- works by throwing an ASYNCHRONOUS exception at the evaluating thread, once.
-- Loading a timezone ('L4.Print.tryLoadTZ') used to run inside a @catch@ for
-- 'SomeException', which includes that exception: when the timeout landed
-- inside the handler's scope it was taken for "no timezone database on disk",
-- the embedded table was used instead, and the evaluation carried on with the
-- timeout spent. Only an 'IOException' is the failure that handler is for.
--
-- The test drives the real evaluator over an L4 program that does a timezone
-- operation (@DATETIME_DATE@) at every level of a recursion far deeper than
-- fits in the budget, and asserts the timeout cut it short. On the old code the
-- program ran to its natural end instead, so 'timeout' returned the finished
-- result.
--
-- Where the timeout lands is a race, so one attempt can get lucky, and the shape
-- of the program decides how often. Measured on the old code (40 attempts each,
-- GHC 9.10.3, macOS, a busy machine): this recursion overran 39 times, while a
-- tail-recursive loop with the same operation in its guard overran only 3.
-- That loop is therefore not a regression test and is not here. 'attempts'
-- repeats the recursion and requires every run to stop, so that a bad draw is
-- not enough to get the old code past.
module TimezoneTimeoutSpec (spec) where

import Control.Concurrent (forkIO, killThread)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Monad (forM_)
import qualified Data.Text as Text
import Data.Time
  ( NominalDiffTime
  , UTCTime (..)
  , diffUTCTime
  , fromGregorian
  , getCurrentTime
  , secondsToDiffTime
  )
import System.Timeout (timeout)
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, vfsFromList)
import L4.EvaluateLazy
  ( EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , ReductionOutcome (..)
  , execEvalModuleWithEnv
  , resolveEvalConfig
  )
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Print (prettyLayout)
import L4.TracePolicy (apiDefaultPolicy)

spec :: Spec
spec = describe "a timezone operation under System.Timeout (smucclaw/l4-ide#1001)" $ do
  it "the recursion is well formed: a short one finishes with its answer" $ do
    run <- prepare (recursion 100)
    results <- run
    renderedResults results `shouldBe` [Text.pack (show (100 * todaySerial))]

  it "a DATETIME_DATE recursion is stopped by the timeout" $ do
    run <- prepare (recursion recursionDepth)
    forM_ [1 .. attempts] $ \i -> do
      outcome <- attempt run
      case outcome of
        TimedOut _ -> pure ()
        RanToTheEnd took ->
          expectationFailure $
            "attempt " <> show i <> " of " <> show attempts
              <> ": the " <> show budgetMicros <> " us timeout did not stop the evaluation,"
              <> " which ran to its end after " <> show took
        Hung ->
          expectationFailure $
            "attempt " <> show i <> " of " <> show attempts
              <> ": still evaluating after the " <> show hangGuardMicros <> " us outer guard"

-- | How long one attempt may evaluate before the timeout is due.
budgetMicros :: Int
budgetMicros = 200_000

-- | How deep the recursion goes: far more levels than fit in 'budgetMicros'
-- (a level costs tens of microseconds, mostly the system call that opens the
-- timezone file), yet finite and well under the evaluator's limit of a million
-- frames, so the budget is the only thing that can end a run early. The old
-- code ran this to the end, seconds later.
recursionDepth :: Int
recursionDepth = 150_000

-- | Attempts, all of which must stop.
attempts :: Int
attempts = 8

-- | The outer bound for one attempt, enforced from a thread that loads no
-- timezone and so cannot be fooled by the bug it is guarding against: a hung
-- or runaway evaluation fails the test rather than the build.
hangGuardMicros :: Int
hangGuardMicros = 60_000_000

-- | @DATE_SERIAL@ of 2026-01-01, the day @NOW@ falls on in Asia/Singapore once
-- the clock is pinned to 'fixedNow'. L4 counts days from 0000-01-01, less one.
todaySerial :: Integer
todaySerial = 739_981

-- | A recursion that does a timezone operation as each level is entered, so the
-- operation is under way while the stack is growing.
recursion :: Int -> Text.Text
recursion n = Text.unlines
  [ "TIMEZONE IS \"Asia/Singapore\""
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "`dive` n MEANS"
  , "  IF n EQUALS 0"
  , "  THEN 0"
  , "  ELSE (DATE_SERIAL (DATETIME_DATE NOW)) PLUS (`dive` (n MINUS 1))"
  , ""
  , "#EVAL `dive` " <> Text.pack (show n)
  ]

-- | Typecheck a one-module source and return the action that evaluates its
-- directives, with the clock pinned.
prepare :: Text.Text -> IO (IO [EvalDirectiveResult])
prepare src = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports (vfsFromList []) src of
    Left errs -> do
      expectationFailure ("typecheck failed: " <> show errs)
      pure (pure [])
    Right r ->
      pure $ snd <$> execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule

-- | Noon on 2026-01-01, UTC.
fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 43200)

renderedResults :: [EvalDirectiveResult] -> [Text.Text]
renderedResults rs =
  [ case res.result of
      Reduction (Reduced nf) -> prettyLayout nf
      other -> Text.pack (show other)
  | res <- rs
  ]

data Outcome
  = TimedOut NominalDiffTime
    -- ^ the timeout cut the evaluation short, as it should
  | RanToTheEnd NominalDiffTime
    -- ^ the timeout was spent without stopping anything: it was swallowed
  | Hung
    -- ^ the evaluation was still running when the outer guard gave up

-- | One attempt: evaluate under 'timeout' on a worker, watched from outside.
attempt :: IO a -> IO Outcome
attempt act = do
  done <- newEmptyMVar
  started <- getCurrentTime
  worker <- forkIO $ do
    r <- timeout budgetMicros act
    finished <- getCurrentTime
    let took = diffUTCTime finished started
    putMVar done (maybe (TimedOut took) (const (RanToTheEnd took)) r)
  watched <- timeout hangGuardMicros (takeMVar done)
  case watched of
    Just outcome -> pure outcome
    Nothing -> do
      -- If the evaluation has swallowed this too it carries on in the
      -- background; it is finite, and the test run ends with the process.
      killThread worker
      pure Hung
