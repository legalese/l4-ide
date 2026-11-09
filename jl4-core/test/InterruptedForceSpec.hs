{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | A force that an asynchronous exception interrupts must leave its thunk
-- forcible again (smucclaw\/l4-ide#1020).
--
-- The evaluator marks a thunk with the thread that is forcing it, and reports
-- an infinite loop when that same thread meets the mark again. Only
-- 'raiseException' unwound the frame stack, so a time or allocation limit, or
-- a cancelled thread, left the mark behind. A thunk of an imported module
-- outlives the request, and the next request on the same thread then met its
-- own stale mark: "Infinite loop detected", as the answer.
module InterruptedForceSpec (spec) where

import Control.Exception (try)
import Control.Monad (forM)
import Data.IORef (newIORef, readIORef)
import GHC.Conc (getAllocationCounter, setAllocationCounter)
import GHC.IO.Exception (AllocationLimitExceeded (..))
import qualified Data.Text as Text
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, vfsFromList)
import L4.Import.Resolution (ResolvedImport (..), TypeCheckWithDepsResult (..))
import L4.Evaluate.ValueLazy (Environment)
import L4.EvaluateLazy
  ( AllocationLimit (..)
  , EvalConfig (..)
  , EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , ReductionOutcome (..)
  , execEvalModuleWithEnv
  , resolveEvalConfig
  )
import L4.Print (prettyLayout)
import L4.TypeCheck.Types (CheckResult (..))
import L4.TracePolicy (apiDefaultPolicy)

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

-- | An imported value that takes a few tenths of a second to compute.
libSrc :: Text.Text
libSrc = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "`count down` n MEANS"
  , "  IF n AT MOST 0 THEN 0 ELSE `count down` (n - 1)"
  , ""
  , "heavy MEANS `count down` 400000"
  ]

mainSrc :: Text.Text
mainSrc = Text.unlines
  [ "IMPORT heavy_lib"
  , ""
  , "#EVAL heavy + 1"
  ]

-- | Two hundred cheap thunks, each forced from the next: a force that starts,
-- and so a mark that is set and a frame that is pushed, two hundred times in
-- one run.
chainLibSrc :: Text.Text
chainLibSrc = Text.unlines $
  "t0 MEANS 1" : [ "t" <> n <> " MEANS t" <> prev <> " + 1" | i <- [1 .. 200 :: Int], let n = Text.pack (show i), let prev = Text.pack (show (i - 1)) ]

chainMainSrc :: Text.Text
chainMainSrc = Text.unlines [ "IMPORT chain_lib", "", "#EVAL t200" ]

-- | The same chain, but its bottom raises a user error, so that every one of
-- the two hundred forces is unwound by 'raiseException' rather than by
-- 'runEval'.
failingChainLibSrc :: Text.Text
failingChainLibSrc = Text.unlines $
  "t0 MEANS 1 / 0" : [ "t" <> n <> " MEANS t" <> prev <> " + 1" | i <- [1 .. 200 :: Int], let n = Text.pack (show i), let prev = Text.pack (show (i - 1)) ]

failingChainMainSrc :: Text.Text
failingChainMainSrc = Text.unlines [ "IMPORT failing_chain_lib", "", "#EVAL t200" ]

spec :: Spec
spec = describe "an interrupted force of an imported thunk" do
  -- The allocation limit lands at a heap check, so sweeping it across a run
  -- puts the interruption at many different points of the force: between the
  -- mark of a thunk and its frame, between the pop and the write, and so on
  -- (smucclaw/l4-ide#1020). After each, on a fresh environment, the next run
  -- on the same thread must not meet a stale mark.
  it "leaves no stale mark wherever an allocation limit lands" do
    cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
    case checkWithImports (vfsFromList [("chain_lib.l4", chainLibSrc)]) chainMainSrc of
      Left errs -> expectationFailure ("typecheck failed: " <> show errs)
      Right r -> do
        interruptedAt <- forM [1 .. 400 :: Int] \i -> do
          importEnv <- evaluateImports' cfg r.tcdResolvedImports
          hitFlag <- newIORef False
          let limited = cfg { allocationLimit = Just (MkAllocationLimit (fromIntegral i * 997) hitFlag) }
              run c = execEvalModuleWithEnv c r.tcdEntityInfo importEnv r.tcdModule
          _ <- try (run limited) :: IO (Either AllocationLimitExceeded (Environment, [EvalDirectiveResult]))
          hit <- readIORef hitFlag
          (_, results) <- run cfg
          let rendered = map render results
          rendered `shouldBe` ["201"]
          pure hit
        -- the sweep must have interrupted the run at least once, or it proves nothing
        length (filter id interruptedAt) `shouldSatisfy` (> 20)

  -- A user error unwinds the stack frame by frame in 'raiseException'. A limit
  -- that landed between a frame's pop and its unwind lost the frame, and with
  -- it the restoring of its thunk. The sweep covers the last 60 KB of the run
  -- in steps of 40 bytes (the RTS checks the limit at nursery-block boundaries, about 4 KB apart, so the landing points are only that fine on average), which holds the unwind of all 200 frames; the first
  -- run's baseline, taken with no limit, is the answer every later run must
  -- reproduce.
  it "leaves no stale mark when an allocation limit lands during a user error's unwind" do
    cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
    case checkWithImports (vfsFromList [("failing_chain_lib.l4", failingChainLibSrc)]) failingChainMainSrc of
      Left errs -> expectationFailure ("typecheck failed: " <> show errs)
      Right r -> do
        baselineEnv <- evaluateImports' cfg r.tcdResolvedImports
        (_, baseline) <- execEvalModuleWithEnv cfg r.tcdEntityInfo baselineEnv r.tcdModule
        let expected = map render baseline
        expected `shouldSatisfy` any (Text.isInfixOf "DivisionByZero")
        -- how much a whole run allocates, to aim the sweep at its end
        total <- do
          importEnv <- evaluateImports' cfg r.tcdResolvedImports
          setAllocationCounter maxBound
          _ <- execEvalModuleWithEnv cfg r.tcdEntityInfo importEnv r.tcdModule
          (maxBound -) <$> getAllocationCounter
        interruptedAt <- forM [1 .. 1500 :: Int] \i -> do
          importEnv <- evaluateImports' cfg r.tcdResolvedImports
          hitFlag <- newIORef False
          let limited = cfg { allocationLimit = Just (MkAllocationLimit (max 1 (total - 60000 + fromIntegral i * 40)) hitFlag) }
              run c = execEvalModuleWithEnv c r.tcdEntityInfo importEnv r.tcdModule
          _ <- try (run limited) :: IO (Either AllocationLimitExceeded (Environment, [EvalDirectiveResult]))
          hit <- readIORef hitFlag
          (_, results) <- run cfg
          map render results `shouldBe` expected
          pure hit
        -- most of the sweep lands inside the run, and the tail of it past the end
        length (filter id interruptedAt) `shouldSatisfy` (> 1000)
        length (filter not interruptedAt) `shouldSatisfy` (>= 1)

  it "can be forced again, on the same thread, by the next evaluation" do
    cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
    case checkWithImports (vfsFromList [("heavy_lib.l4", libSrc)]) mainSrc of
      Left errs -> expectationFailure ("typecheck failed: " <> show errs)
      Right r -> do
        -- one environment for both runs, as the service keeps one per deployment
        importEnv <- evaluateImports r.tcdResolvedImports
        -- Interrupted by an allocation limit, not a timer, so that it happens
        -- the same way on a loaded machine: the module does nothing but force
        -- the imported value, which allocates some 2 GB, so the 100 MB limit
        -- can only be hit inside that force.
        hitFlag <- newIORef False
        let limited = cfg { allocationLimit = Just (MkAllocationLimit (100 * 1024 * 1024) hitFlag) }
            run c = execEvalModuleWithEnv c r.tcdEntityInfo importEnv r.tcdModule
        interrupted <- try (run limited)
        case interrupted of
          Left AllocationLimitExceeded -> pure ()
          Right _ -> expectationFailure "the first run finished: the limit was not hit"
        readIORef hitFlag `shouldReturn` True
        -- the same thread, the same environment, no limit
        (_, results) <- run cfg
        map render results `shouldBe` ["1"]
 where
  evaluateImports' :: EvalConfig -> [ResolvedImport] -> IO Environment
  evaluateImports' cfg imports = do
    envs <- forM imports \ri ->
      fst <$> execEvalModuleWithEnv cfg ri.riTypeChecked.entityInfo mempty ri.riTypeChecked.program
    pure (mconcat envs)

  evaluateImports :: [ResolvedImport] -> IO Environment
  evaluateImports imports = do
    cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
    envs <- forM imports \ri ->
      fst <$> execEvalModuleWithEnv cfg ri.riTypeChecked.entityInfo mempty ri.riTypeChecked.program
    pure (mconcat envs)

  render :: EvalDirectiveResult -> Text.Text
  render res = case res.result of
    Reduction (Reduced nf) -> prettyLayout nf
    other                  -> Text.pack (show other)
