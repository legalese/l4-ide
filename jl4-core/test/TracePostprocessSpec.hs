-- | Regression tests: trace post-processing must never let an
-- exception escape and abort the surrounding evaluation.
--
-- A 'StackOverflow' used to emit an imbalanced @[Push, Push, Pop, Pop]@
-- action sequence on which 'postprocessTrace' (via @splitEvalTraceActions@)
-- calls @error@ — an 'ErrorCall' that is NOT the evaluator's 'EvalException',
-- so it escaped the eval exception handler and crashed the whole LSP request /
-- CLI run. 'safePostprocessTrace' now degrades such failures to a fallback node.
module TracePostprocessSpec (spec) where

import Control.DeepSeq (force)
import Control.Exception (evaluate)
import qualified Data.Text as Text
import Test.Hspec

import qualified Data.Text as T
import L4.API.VirtualFS (TypeCheckWithDepsResult (..), checkWithImports, emptyVFS)
import L4.EvaluateLazy (postprocessTrace, safePostprocessTrace, traceUnavailable)
import qualified L4.EvaluateLazy as EL
import L4.EvaluateLazy.Trace (EvalTraceAction(..), EvalTrace(..))
import L4.Evaluate.ValueLazy (NF(..), Value(..))
import L4.TracePolicy (apiDefaultPolicy)

-- | Evaluate a module with a trace post-processing that fails, and give each
-- directive's result.
evalWithFailingTrace :: T.Text -> IO [EL.EvalDirectiveResult]
evalWithFailingTrace src = case checkWithImports emptyVFS src of
  Left errs -> error (show errs)
  Right r -> do
    cfg <- EL.resolveEvalConfig Nothing apiDefaultPolicy
    let failing = cfg { EL.tracePostprocessor = const (error "postprocessTrace: failure injected by a test") }
    snd <$> EL.execEvalModuleWithEnv failing r.tcdEntityInfo mempty r.tcdModule

-- | The imbalanced sequence a StackOverflow used to produce (more Pushes than
-- the split expects), which drives @splitEvalTraceActions@ into its catch-all
-- @error@.
malformed :: [EvalTraceAction]
malformed = [Push, Push, Pop, Pop]

spec :: Spec
spec = describe "trace post-processing" $ do
  it "the raw postprocessTrace really does crash on a malformed action list" $
    -- Guards the test's own premise: if this stops throwing, the guard test
    -- below would pass vacuously.
    evaluate (force (postprocessTrace malformed)) `shouldThrow` anyErrorCall

  it "safePostprocessTrace degrades that crash to a fallback node" $ do
    t <- safePostprocessTrace postprocessTrace malformed
    case t of
      Trace Nothing [] (Right (MkNF (ValString msg))) ->
        msg `shouldSatisfy` ("trace unavailable" `Text.isInfixOf`)
      _ -> expectationFailure "expected the trace-post-process fallback node"

  it "traceUnavailable tells the fallback from a trace" $ do
    t <- safePostprocessTrace postprocessTrace malformed
    traceUnavailable t `shouldBe` True
    traceUnavailable (Trace Nothing [] (Right (MkNF (ValString "an answer")))) `shouldBe` False

  -- What `l4 trace` exits 1 on: the directive's trace is the fallback, and its
  -- answer is kept. A directive that raises keeps the fallback too, rather
  -- than having its root rewritten into a node with no label.
  it "a directive whose trace cannot be built keeps its answer, and its trace is the fallback" $ do
    results <- evalWithFailingTrace "GIVEN n IS A NUMBER\nGIVETH A NUMBER\ng n MEANS n + 1\n\n#EVALTRACE g 2\n#EVALTRACE SQRT (-1)\n"
    map (fmap traceUnavailable . (.trace)) results `shouldBe` [Just True, Just True]
    case map (.result) results of
      [EL.Reduction (EL.Reduced (MkNF (ValNumber 3))), EL.Reduction (EL.ReducedErrored _)] -> pure ()
      other -> expectationFailure ("unexpected results: " <> show other)
