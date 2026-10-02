-- | Regression tests for T7: trace post-processing must never let an
-- exception escape and abort the surrounding evaluation.
--
-- A 'StackOverflow' used to emit an imbalanced @[Push, Push, Pop, Pop]@
-- action sequence on which 'postprocessTrace' (via @splitEvalTraceActions@)
-- calls @error@ — an 'ErrorCall' that is NOT the evaluator's 'EvalException',
-- so it escaped the eval exception handler and crashed the whole LSP request /
-- CLI run. 'safePostprocessTrace' now degrades such failures to a fallback node.
module TracePostprocessSpec (spec) where

import Base (NormalizedUri, Uri (..), toNormalizedUri)
import Control.DeepSeq (force)
import Control.Exception (evaluate)
import Data.IORef (newIORef)
import qualified Data.Text as Text
import Test.Hspec

import L4.EvaluateLazy (postprocessTrace, safePostprocessTrace)
import L4.EvaluateLazy.Trace
import L4.Evaluate.ValueLazy (Address (..), NF(..), Reference (..), Thunk (..), Value(..))
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.Print (prettyLayout)
import L4.Annotation (emptyAnno)
import L4.Syntax (Expr (..), Lit (..))

-- | The imbalanced sequence a StackOverflow used to produce (more Pushes than
-- the split expects), which drives @splitEvalTraceActions@ into its catch-all
-- @error@.
malformed :: [EvalTraceAction]
malformed = [Push, Push, Pop, Pop]

spec :: Spec
spec = do
  t7Spec
  defaultEventSpec

t7Spec :: Spec
t7Spec = describe "trace post-processing (T7 regression)" $ do
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

-- ---------------------------------------------------------------------------
-- W8: a TYPICALLY default is an event in the trace
-- (TYPICALLY-ONE-BEHAVIOUR-SPEC.md, Note [Defaults in the trace])
-- ---------------------------------------------------------------------------

uriOf :: Text.Text -> NormalizedUri
uriOf = toNormalizedUri . Uri

-- | A reference to an evaluated number, as the JSON decoder makes for a field it
-- filled from its @DECLARE@.
numberRef :: Int -> Rational -> IO Reference
numberRef n v = MkReference (MkAddress (uriOf "file:///w8-spec") n) <$> newIORef (WHNF (ValNumber v))

number :: Rational -> Expr resolved
number = Lit emptyAnno . NumericLit emptyAnno

-- | A default as the evaluator reports it: the rate, declared at line 4.
theRate :: Presumed
theRate = MkPresumed
  { path = ["the rate"]
  , declaredAt = Just (MkSrcRange (MkSrcPos 4 30) (MkSrcPos 4 31) 1 (uriOf "file:///somewhere/rates.l4"))
  , origin = FromSectionBinder
  }

-- | The events in a trace, in order, wherever they hang: the path of each
-- and the steps it holds.
eventsOf :: EvalTrace -> [([Text.Text], Int)]
eventsOf = \ case
  Trace _ steps _        -> foldMap (foldMap eventsOf . snd) steps
  TraceDefault p steps _ -> (p.path, length steps) : foldMap (foldMap eventsOf . snd) steps

defaultEventSpec :: Spec
defaultEventSpec = describe "a TYPICALLY default in the trace (W8)" $ do
  it "hangs the event on the expression that needed the value, with the value" $ do
    r <- numberRef 1 3
    let t = postprocessTrace
              [ Enter (number 2), TookDefault theRate r, SetRef r, Exit (Right (ValNumber 3)), Pop ]
    case t of
      Trace _ [(_, [TraceDefault p [] (Right (MkNF (ValNumber 3)))])] _ -> p `shouldBe` theRate
      other -> expectationFailure ("unexpected trace: " <> show other)

  it "says what happened, where it was declared, and the value" $ do
    r <- numberRef 1 3
    let t = postprocessTrace
              [ Enter (number 2), TookDefault theRate r, SetRef r, Exit (Right (ValNumber 3)), Pop ]
        txt = prettyLayout t
    txt `shouldSatisfy` Text.isInfixOf "│┌ the rate took its default (declared at rates.l4:4:30-31)\n│└ 3"

  it "passes over a frame that has entered no expression, to the application waiting on it" $ do
    -- what a builtin operator does: push a frame, then force its operands
    r <- numberRef 1 3
    let t = postprocessTrace
              [ Enter (number 2)
              , Push, TookDefault theRate r, SetRef r, Exit (Right (ValNumber 3)), Pop
              , Exit (Right (ValNumber 6)), Pop ]
    eventsOf t `shouldBe` [(["the rate"], 0)]

  it "drops an event that is the first thing in a list, rather than fail" $ do
    r <- numberRef 1 3
    let t = postprocessTrace
              [ TookDefault theRate r, Enter (number 2), Exit (Right (ValNumber 2)), Pop ]
    eventsOf t `shouldBe` []

  it "drops a default first used while the result is being normalised, and still answers" $ do
    -- after the main expression has finished, with nothing open to hang it from
    r <- numberRef 1 3
    let main = [ Enter (number 2), Exit (Right (ValNumber 2)), Pop ]
        late = [ TookDefault theRate r, SetRef r, Exit (Right (ValNumber 3)), Pop ]
    t <- safePostprocessTrace (main <> late)
    eventsOf t `shouldBe` []
    -- and the trace is the one the main expression gave, not the fallback
    prettyLayout t `shouldBe` prettyLayout (postprocessTrace main)

  it "keeps what a computed default did, and drops the steps of a plain value" $ do
    r <- numberRef 1 8
    let computed = IfThenElse emptyAnno (number 1) (number 8) (number 9)
        t = postprocessTrace
              [ Enter (number 2)
              , TookDefault theRate r, SetRef r
              , Push, Enter computed, Exit (Right (ValNumber 8)), Pop
              , Exit (Right (ValNumber 8)), Pop ]
    -- the 'Push' to 'Pop' in the middle is the default's own evaluation, in the
    -- list of its address, which the event takes the steps of
    eventsOf t `shouldBe` [(["the rate"], 1)]
