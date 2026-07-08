-- | Regression tests for T7: trace post-processing must never let an
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

import L4.EvaluateLazy (postprocessTrace, safePostprocessTrace)
import L4.EvaluateLazy.Trace (EvalTraceAction(..), EvalTrace(..))
import L4.Evaluate.ValueLazy (NF(..), Value(..))

-- | The imbalanced sequence a StackOverflow used to produce (more Pushes than
-- the split expects), which drives @splitEvalTraceActions@ into its catch-all
-- @error@.
malformed :: [EvalTraceAction]
malformed = [Push, Push, Pop, Pop]

spec :: Spec
spec = describe "trace post-processing (T7 regression)" $ do
  it "the raw postprocessTrace really does crash on a malformed action list" $
    -- Guards the test's own premise: if this stops throwing, the guard test
    -- below would pass vacuously.
    evaluate (force (postprocessTrace malformed)) `shouldThrow` anyErrorCall

  it "safePostprocessTrace degrades that crash to a fallback node" $ do
    t <- safePostprocessTrace malformed
    case t of
      Trace Nothing [] (Right (MkNF (ValString msg))) ->
        msg `shouldSatisfy` ("trace unavailable" `Text.isInfixOf`)
      _ -> expectationFailure "expected the trace-post-process fallback node"
