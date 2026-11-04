{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | How the check of nested calls to a name with two meanings scales with
-- the nesting.
--
-- Overload resolution forks the checker once per meaning of the name, and
-- each branch, and the ambiguity fallback after them, checks every argument
-- again. A call nested in the argument of another is therefore checked three
-- times as often for every level it sits below the top: on main before the
-- port of legalese/l4-ide#169 (smucclaw/l4-ide#929), the prelude's @max@
-- nested 13 deep took 6 s of CPU and 14 deep 17 s, and a user's own @mx@ of
-- two meanings the same. The candidate pre-filter ('L4.TypeCheck.appCandidateFilter')
-- drops the meaning whose parameters cannot take the arguments, and the lazy
-- fallback ('L4.TypeCheck.Types.forkWithLazyFallback') skips the ambiguity
-- branch when exactly one meaning succeeds, so each call is checked once.
module OverloadScaleSpec (spec) where

import Control.DeepSeq (force)
import Control.Exception (evaluate)
import Control.Monad (replicateM_, void)
import Data.Text (Text)
import qualified Data.Text as Text
import GHC.Clock (getMonotonicTime)
import System.CPUTime (getCPUTime)
import System.Timeout (timeout)
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))

spec :: Spec
spec = describe "nested calls of a name with two meanings" $ do
  -- Both meanings are reachable through the chain, so neither is pruned
  -- where it is the one that fits.
  it "check without an error, whichever meaning the arguments fit" $ do
    errorsIn (nestedCalls "NUMBER" 20) `shouldReturn` 0
    errorsIn (nestedCalls "BOOLEAN" 20) `shouldReturn` 0

  -- 10 and 20 levels: linear growth is about 2, base 3 is about 59,000.
  -- Without the port, the 20-level check would run for hours, so it is
  -- stopped by the watchdog and the test fails.
  it "are checked in CPU time linear in the nesting" $ do
    ratio <- growthRatio (checkNested "NUMBER") 10 20 growthLimit
    case ratio of
      Nothing -> pendingWith "the CPU clock did not tick enough while the smaller chain was checked, so there is no ratio to judge"
      Just r -> r `shouldSatisfy` (< growthLimit)

  -- The positive control for the guard above: on the same harness and the
  -- same sizes, work that doubles at every step is failed. The work is made
  -- up, so that the control does not depend on the checker.
  it "still fails work that doubles at every step" $ do
    ratio <- growthRatio exponentialWork 10 20 growthLimit
    case ratio of
      Nothing -> pendingWith "the CPU clock did not tick enough while the smaller work ran, so there is no ratio to judge"
      Just r -> r `shouldSatisfy` (>= growthLimit)

-- | How many times longer the larger chain may take. Linear growth is about
-- 2 (and less, beside the fixed cost of a check, which the smaller check
-- already pays); doubling at every level is about 1,000.
growthLimit :: Double
growthLimit = 8

-- | How long one check may run before the guard gives up on it.
watchdogSeconds :: Int
watchdogSeconds = 60

-- | A module with two meanings of @mx@, at NUMBER and at BOOLEAN, and a rule
-- over @k@ inputs of the given type that nests @k - 1@ calls of @mx@:
-- @mx (mx (x1) (x2)) (x3)@ for @k = 3@.
nestedCalls :: Text -> Int -> Text
nestedCalls ty k =
  Text.unlines $
    [ "GIVEN a IS A NUMBER"
    , "      b IS A NUMBER"
    , "GIVETH A NUMBER"
    , "mx a b MEANS IF a >= b THEN a ELSE b"
    , ""
    , "GIVEN a IS A BOOLEAN"
    , "      b IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "mx a b MEANS a OR b"
    , ""
    , "GIVEN " <> x 1 <> " IS A " <> ty
    ]
      <> [ "      " <> x i <> " IS A " <> ty | i <- [2 .. k] ]
      <> [ "GIVETH A " <> ty
         , "`the chain` " <> Text.unwords (map x [1 .. k]) <> " MEANS"
         , "    " <> foldl' (\ e i -> "mx (" <> e <> ") (" <> x i <> ")") (x 1) [2 .. k]
         ]
  where
    x :: Int -> Text
    x i = "x" <> Text.pack (show i)

-- | The number of diagnostics the check of a module reports.
errorsIn :: Text -> IO Int
errorsIn src = case checkWithImports emptyVFS src of
  Left errs -> fail ("the module failed to check: " <> show errs)
  Right r -> length <$> evaluate (force r.tcdErrors)

-- | Check the chain of @k@ inputs, failing if it reports anything or does not
-- finish within the watchdog.
checkNested :: Text -> Int -> IO ()
checkNested ty k = do
  r <- timeout (watchdogSeconds * 1000000) (errorsIn (nestedCalls ty k))
  case r of
    Nothing -> expectationFailure (show k <> " inputs did not finish checking within " <> show watchdogSeconds <> " s")
    Just n -> n `shouldBe` 0

-- | Work whose cost doubles with each step: a sum of 2^(n+8) numbers.
exponentialWork :: Int -> IO ()
exponentialWork n = void (evaluate (foldl' (+) 0 [1 .. 2 ^ (n + 8) :: Int]))

-- | One step of the CPU clock on Windows, 15.625 ms in picoseconds.
windowsClockStep :: Integer
windowsClockStep = 15625000000

-- | @growthRatio work small large limit@: the CPU time of @work large@ over
-- the CPU time of @work small@, or 'Nothing' if the clock could not measure
-- the smaller.
--
-- As in "PatternMatchParserSpec" ('linearTimeRatioOn'): the smaller is run
-- over and over in one timed stretch until the stretch spans ten steps of the
-- Windows clock, and its time is the stretch's divided by the number of runs,
-- the fastest of three stretches; the larger is run once. If no stretch spans
-- ten steps within 2 s of wall-clock time or 4,096 runs, there is no ratio. A
-- ratio short of twice the limit is measured again, up to twice, so that one
-- pause does not fail it.
growthRatio :: (Int -> IO ()) -> Int -> Int -> Double -> IO (Maybe Double)
growthRatio work small large limit = do
  let timed k reps = do
        t0 <- getCPUTime
        replicateM_ reps (work k)
        t1 <- getCPUTime
        pure (fromIntegral (t1 - t0) :: Double)
      measurable = fromIntegral (10 * windowsClockStep) :: Double
      maxReps = 4096 :: Int
  start <- getMonotonicTime
  let repsFor reps = do
        t <- timed small reps
        now <- getMonotonicTime
        if t >= measurable
          then pure (Just (reps, t))
          else if reps >= maxReps || now - start >= 2
            then pure Nothing
            else repsFor (reps * 2)
  found <- repsFor 1
  case found of
    Nothing -> pure Nothing
    Just (reps, firstStretch) -> do
      more <- traverse (const (timed small reps)) [2 .. 3 :: Int]
      let smallest = minimum (firstStretch : more) / fromIntegral reps
          settle tries = do
            r <- (/ smallest) <$> timed large 1
            if r < limit || r >= 2 * limit || tries <= (1 :: Int) then pure r else min r <$> settle (tries - 1)
      if smallest <= 0 then pure Nothing else Just <$> settle 3
