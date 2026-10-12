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
import Data.Aeson (Value (..), decodeStrict)
import qualified Data.Aeson.KeyMap as KeyMap
import Data.IORef (newIORef)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.Vector as Vector
import Test.Hspec

import L4.API (l4Eval)
import L4.EvaluateLazy (defaultNotes, postprocessTrace, safePostprocessTrace, tracePostprocessFailed)
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
  , valueText = Nothing
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

  it "hangs an event that is the first thing in a list on the main expression, rather than drop it or fail" $ do
    r <- numberRef 1 3
    let t = postprocessTrace
              [ TookDefault theRate r, Enter (number 2), Exit (Right (ValNumber 2)), Pop ]
    eventsOf t `shouldBe` [(["the rate"], 0)]

  it "hangs a default first used while the result is written out on the expression that built it" $ do
    -- after the main expression has finished, with no frame open: the usual
    -- shape is a defaulted field of the returned record that nothing else read
    r <- numberRef 1 3
    let main = [ Enter (number 2), Exit (Right (ValNumber 2)), Pop ]
        late = [ TookDefault theRate r, SetRef r, Exit (Right (ValNumber 3)), Pop ]
    t <- safePostprocessTrace (main <> late)
    eventsOf t `shouldBe` [(["the rate"], 0)]
    -- it is the trace of the main expression and not the fallback, and the
    -- value is the default's
    case t of
      Trace _ [(_, [TraceDefault _ [] (Right (MkNF (ValNumber 3)))])] (Right (MkNF (ValNumber 2))) -> pure ()
      other -> expectationFailure ("unexpected trace: " <> show other)

  it "hangs two such defaults in the order they were read" $ do
    r1 <- numberRef 1 3
    r2 <- numberRef 2 4
    let other = theRate { path = ["the limit"] }
        main = [ Enter (number 2), Exit (Right (ValNumber 2)), Pop ]
        late = [ TookDefault theRate r1, SetRef r1, Exit (Right (ValNumber 3)), Pop
               , TookDefault other r2, SetRef r2, Exit (Right (ValNumber 4)), Pop ]
    t <- safePostprocessTrace (main <> late)
    map fst (eventsOf t) `shouldBe` [["the rate"], ["the limit"]]

  -- A rule that runs while the result is written out, as in @JUST (rule ...)@:
  -- the thunk it is run from is a placeholder in the main trace, so the trace
  -- of that run is shown, and the event belongs in it, under the step that
  -- read the value. The actions are those of the machine: the thunk is forced
  -- from an empty stack ('SetRef', its update frame's 'Push', the read, the
  -- 'Pop' of that frame, then the 'Exit' and 'Pop' that end the force).
  let lateThunk r d =
        [ SetRef r, Push, Enter (number 6), TookDefault theRate d, SetRef d
        , Exit (Right (ValNumber 3)), Pop, Exit (Right (ValNumber 3)), Pop ]

  it "keeps an event in the trace of the run that read it, when that run came late (review F1)" $ do
    thunk <- numberRef 1 6
    dflt <- numberRef 2 3
    let main = [ Enter (number 2), Alloc (number 6) thunk, Exit (Right (ValNumber 2)), Pop ]
    t <- safePostprocessTrace (main <> lateThunk thunk dflt)
    eventsOf t `shouldBe` [(["the rate"], 0)]
    -- under the thunk's own step, not beside the main expression's
    case t of
      Trace _ [(_, [Trace _ [(_, [TraceDefault p [] _])] _])] _ -> p `shouldBe` theRate
      other -> expectationFailure ("the event is not in the trace of the run: " <> show other)

  it "hangs on the main expression an event whose run the trace does not show" $ do
    -- the same late run, with nothing in the main trace that stands for it: a
    -- read inside a definition with no inputs looks like this
    thunk <- numberRef 1 6
    dflt <- numberRef 2 3
    let main = [ Enter (number 2), Exit (Right (ValNumber 2)), Pop ]
    t <- safePostprocessTrace (main <> lateThunk thunk dflt)
    case t of
      Trace _ [(_, [TraceDefault p [] (Right (MkNF (ValNumber 3)))])] _ -> p `shouldBe` theRate
      other -> expectationFailure ("unexpected trace: " <> show other)

  it "shows the event at each place that shows the run, and hangs no further copy" $ do
    -- one placeholder referenced from two places: zonking inlines the run at
    -- both, as for any shared thunk, so the event is in both and none is
    -- hung on the main expression as well
    thunk <- numberRef 1 6
    dflt <- numberRef 2 3
    let main = [ Enter (number 2), Alloc (number 6) thunk, Alloc (number 6) thunk, Exit (Right (ValNumber 2)), Pop ]
    t <- safePostprocessTrace (main <> lateThunk thunk dflt)
    map fst (eventsOf t) `shouldBe` [["the rate"], ["the rate"]]
    case t of
      Trace _ [(_, [Trace _ [(_, [TraceDefault {}])] _, Trace _ [(_, [TraceDefault {}])] _])] _ -> pure ()
      other -> expectationFailure ("unexpected trace: " <> show other)

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

  -- W11: the line beside a directive's answer says what the trace would say, with
  -- the value R8's example has, and is not said twice
  it "says a default beside the answer when there is no trace, with its value, and not again when the trace shows it" $ do
    r <- numberRef 1 3
    let valued = theRate { valueText = Just "3" }
        said = "the rate took its default 3 (declared at rates.l4:4:30-31)"
        shown = postprocessTrace
          [ Enter (number 2), TookDefault theRate r, SetRef r, Exit (Right (ValNumber 3)), Pop ]
    defaultNotes Nothing [valued] `shouldBe` [said]
    -- the trace has the event; the entry of the list carries a value the event
    -- does not, and is still the same default
    defaultNotes (Just shown) [valued] `shouldBe` []
    -- a trace that does not show it (post-processing failed) leaves the line
    defaultNotes (Just tracePostprocessFailed) [valued] `shouldBe` [said]
    defaultNotes Nothing [] `shouldBe` []

  it "says the sentence of the event when there is no value, and a MAYBE left out as what it is" $ do
    defaultNotes Nothing [theRate] `shouldBe` ["the rate took its default (declared at rates.l4:4:30-31)"]
    -- no TYPICALLY behind it, so no line to quote; the value is NOTHING by definition
    defaultNotes Nothing [theRate { declaredAt = Nothing, valueText = Just "NOTHING" }]
      `shouldBe` ["the rate took its default (a MAYBE left out is NOTHING)"]

  -- review N2: a trace cut off at its display limit is still complete
  describe "a trace cut off before it reached the step that read a default" $ do
    let three = MkNF (ValNumber 3)
        bare  = Trace Nothing [(number 2, [])] (Right (MkNF (ValNumber 2)))

    it "shows the default on the main expression's last step, with its value" $
      case completeDefaults [(theRate, Just three)] bare of
        Trace _ [(_, [TraceDefault p [] (Right (MkNF (ValNumber 3)))])] _ -> p `shouldBe` theRate
        other -> expectationFailure ("unexpected trace: " <> show other)

    it "shows a default whose value could not be read as an omitted one, and does not drop it" $
      case completeDefaults [(theRate, Nothing)] bare of
        Trace _ [(_, [TraceDefault _ [] (Right Omitted)])] _ -> pure ()
        other -> expectationFailure ("unexpected trace: " <> show other)

    it "adds nothing to a trace that shows the default already" $ do
      r <- numberRef 1 3
      let shown = postprocessTrace
            [ Enter (number 2), TookDefault theRate r, SetRef r, Exit (Right (ValNumber 3)), Pop ]
      eventsOf (completeDefaults [(theRate, Just three)] shown) `shouldBe` [(["the rate"], 0)]
      eventsOf (completeDefaults [] bare) `shouldBe` []

    it "adds only the defaults that are missing, after the last step's own" $ do
      r <- numberRef 1 3
      let other   = theRate { path = ["the cap"] }
          shown   = postprocessTrace
            [ Enter (number 2), TookDefault theRate r, SetRef r, Exit (Right (ValNumber 3)), Pop ]
          done    = completeDefaults [(theRate, Just three), (other, Just three)] shown
      map fst (eventsOf done) `shouldBe` [["the rate"], ["the cap"]]

    it "leaves a trace that has no step of its own, which a plain directive's line then covers" $
      eventsOf (completeDefaults [(theRate, Just three)] tracePostprocessFailed) `shouldBe` []

  -- review N4: the JSON the browser's engine returns carries the lines, under the
  -- key `l4 run --json` uses, so that a page that shows notes could show them
  describe "the notes of the WASM API's JSON (W11)" $
    it "carries the default a plain directive took with its value, and none for one that supplied it" $ do
      out <- l4Eval (Text.unlines
        [ "§ `Rates`"
        , "    GIVEN `the rate` IS A NUMBER TYPICALLY 3"
        , ""
        , "GIVETH A NUMBER"
        , "doubled MEANS `the rate` TIMES 2"
        , ""
        , "#EVAL doubled"
        , "#EVAL doubled WITH `the rate` IS 5"
        ])
      let notesOf = \ case
            Object o | Just (Array rs) <- KeyMap.lookup "results" o ->
              [ case KeyMap.lookup "notes" r of
                  Just (Array ns) -> Just [ n | String n <- Vector.toList ns ]
                  _               -> Nothing
              | Object r <- Vector.toList rs ]
            _ -> []
      case notesOf <$> decodeStrict (Text.encodeUtf8 out) of
        Just [Just [said], Nothing] -> do
          said `shouldSatisfy` Text.isPrefixOf "the rate took its default 3 (declared at "
          said `shouldSatisfy` Text.isSuffixOf ":2:44-45)"
        other -> expectationFailure ("unexpected notes: " <> show other <> " in " <> Text.unpack out)
