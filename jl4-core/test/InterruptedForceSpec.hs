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

spec :: Spec
spec = describe "an interrupted force of an imported thunk" do
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
