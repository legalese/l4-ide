{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | Dominators over the state graph (LTS-VISUALISER §1.1c, P2f): for a
-- target state, the acts every path from the start must traverse.
--
-- Each fixture is a shape with a known answer — a chain, a choice, a
-- conjunction, the two nestings, a cycle, and a hand-built graph with a
-- state nothing reaches — and the assertions name the acts by their
-- action text, which is what a reader of @l4 state-graph --dominators@
-- sees. The @RAND@ cases are the ones that would go wrong first: the IR
-- has no join (ruling R2), so a naive walk of the drawn graph says neither
-- branch of a conjunction is necessary. See 'fulfilmentView'.
module DominatorsSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Import.Resolution (TypeCheckWithDepsResult(..))
import L4.StateGraph
import L4.StateGraph.Dominators
import L4.Syntax (DeonticModal(..))

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

preamble :: [Text]
preamble =
  [ "DECLARE Person IS ONE OF Alice, Bob, Carol"
  , "DECLARE Action IS ONE OF"
  , "  pay"
  , "  deliver"
  , "  notify"
  , "  sign"
  , ""
  , "GIVETH DEONTIC Person Action"
  ]

-- | Type-check a rule body and extract its graph.
graphFor :: [Text] -> Either [Text] StateGraph
graphFor body =
  case checkWithImports emptyVFS (Text.unlines (preamble <> body)) of
    Left errs -> Left errs
    Right r   -> case extractStateGraphs r.tcdModule of
      (sg:_) -> Right sg
      []     -> Left ["no state graph was extracted"]

withGraph :: [Text] -> (StateGraph -> Expectation) -> Expectation
withGraph body k = case graphFor body of
  Left errs -> expectationFailure ("fixture failed to check: " <> show errs)
  Right sg  -> k sg

-- | The action text of each dominating transition, in order. A junction's
-- branch edge carries no action (it is the fan-out, not something a party
-- does) and is dropped here, as 'renderTransition' drops it; an @RAND@'s
-- first branch edge is otherwise on every path and would show up as @""@.
acts :: Dominance -> Maybe [Text]
acts = \case
  Unreachable  -> Nothing
  Dominated ts -> Just [ a | t <- ts, let a = t.transLabel.labelAction, not (Text.null a) ]

terminal :: StateType -> StateGraph -> StateId
terminal ty sg = case [ s.stateId | s <- sg.sgStates, s.stateType == ty ] of
  (sid:_) -> sid
  []      -> error ("fixture has no " <> show ty)

fulfilled, breach :: StateGraph -> StateId
fulfilled = terminal TerminalFulfilled
breach    = terminal TerminalBreach

chainSrc, randSrc, rorSrc, prefixRorSrc, rorInRandSrc, randInRorSrc, renewSrc :: [Text]

chainSrc =
  [ "`chain` MEANS"
  , "  PARTY Alice MUST pay WITHIN 3"
  , "  HENCE (PARTY Bob MUST deliver WITHIN 5"
  , "         HENCE (PARTY Carol MUST notify WITHIN 7))"
  ]

randSrc =
  [ "`both` MEANS"
  , "      (PARTY Alice MUST pay WITHIN 3)"
  , "  RAND (PARTY Bob MUST deliver WITHIN 5)"
  ]

rorSrc =
  [ "`either` MEANS"
  , "      (PARTY Alice MUST pay WITHIN 3)"
  , "  ROR  (PARTY Bob MUST deliver WITHIN 5)"
  ]

prefixRorSrc =
  [ "`sign then either` MEANS"
  , "  PARTY Carol MUST sign WITHIN 1"
  , "  HENCE (     (PARTY Alice MUST pay WITHIN 3)"
  , "         ROR  (PARTY Bob MUST deliver WITHIN 5))"
  ]

rorInRandSrc =
  [ "`either then both` MEANS"
  , "      ((PARTY Alice MUST pay WITHIN 3) ROR (PARTY Bob MUST deliver WITHIN 5))"
  , "  RAND (PARTY Carol MUST notify WITHIN 7)"
  ]

randInRorSrc =
  [ "`both or one` MEANS"
  , "      ((PARTY Alice MUST pay WITHIN 3) RAND (PARTY Bob MUST deliver WITHIN 5))"
  , "  ROR  (PARTY Carol MUST notify WITHIN 7)"
  ]

renewSrc =
  [ "`renew` MEANS"
  , "  PARTY Alice MUST pay WITHIN 3"
  , "  HENCE `renew`"
  ]

-- | A graph built by hand: @0 -a-> 1 -b-> 2 (Fulfilled)@, @0 -t-> 3 (Breach)@,
-- and a state 4 that nothing points at, with its own edge to Fulfilled.
-- Extraction never produces an unreachable state, so the case has to be
-- constructed.
orphanGraph :: StateGraph
orphanGraph = StateGraph
  { sgName = "orphan"
  , sgDecide = Nothing
  , sgStates =
      [ ContractState 0 "initial" InitialState Linear
      , ContractState 1 "Bob must deliver" IntermediateState Linear
      , ContractState 2 "Fulfilled" TerminalFulfilled Linear
      , ContractState 3 "Breach" TerminalBreach Linear
      , ContractState 4 "nobody comes here" IntermediateState Linear
      ]
  , sgTransitions =
      [ Transition 0 1 (act "Alice" "pay") HenceTransition
      , Transition 0 3 timeout LestTransition
      , Transition 1 2 (act "Bob" "deliver") HenceTransition
      , Transition 4 2 (act "Carol" "notify") HenceTransition
      ]
  , sgInitialState = 0
  }
 where
  act p a = TransitionLabel (Just p) (Just DMust) a Nothing Nothing Nothing Nothing
  timeout = TransitionLabel Nothing (Just DMust) "timeout" Nothing Nothing Nothing Nothing

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "dominators" $ do
    it "a chain: every act dominates the fulfilled sink" $
      withGraph chainSrc \sg ->
        acts (dominators sg (fulfilled sg)) `shouldBe` Just ["pay", "deliver", "notify"]

    it "a chain: nothing dominates the breach sink, because every link can time out" $
      withGraph chainSrc \sg ->
        acts (dominators sg (breach sg)) `shouldBe` Just []

    it "a chain: an intermediate state is dominated by the acts before it" $
      withGraph chainSrc \sg -> do
        case [ s.stateId | s <- sg.sgStates, s.stateName == "Carol must notify" ] of
          [carol] -> acts (dominators sg carol) `shouldBe` Just ["pay", "deliver"]
          other   -> expectationFailure ("expected one Carol state, got " <> show other)

    it "the entry state is dominated by nothing" $
      withGraph chainSrc \sg ->
        dominators sg sg.sgInitialState `shouldBe` Dominated []

    it "ROR: neither alternative dominates" $
      withGraph rorSrc \sg ->
        acts (dominators sg (fulfilled sg)) `shouldBe` Just []

    it "ROR after an act: the act before the split dominates, the alternatives do not" $
      withGraph prefixRorSrc \sg ->
        acts (dominators sg (fulfilled sg)) `shouldBe` Just ["sign"]

    it "RAND: both branches dominate the fulfilled sink" $
      withGraph randSrc \sg ->
        acts (dominators sg (fulfilled sg)) `shouldBe` Just ["pay", "deliver"]

    it "RAND: neither branch dominates the breach sink, because either can fail" $
      withGraph randSrc \sg ->
        acts (dominators sg (breach sg)) `shouldBe` Just []

    it "(a ROR b) RAND c: only c dominates" $
      withGraph rorInRandSrc \sg ->
        acts (dominators sg (fulfilled sg)) `shouldBe` Just ["notify"]

    it "(a RAND b) ROR c: nothing dominates" $
      withGraph randInRorSrc \sg ->
        acts (dominators sg (fulfilled sg)) `shouldBe` Just []

    it "a renewing duty: the cycle terminates, and only the timeout reaches breach" $
      withGraph renewSrc \sg -> do
        -- HENCE back to the start draws no Fulfilled state at all.
        [ s.stateType | s <- sg.sgStates ] `shouldNotContain` [TerminalFulfilled]
        acts (dominators sg (breach sg)) `shouldBe` Just ["timeout"]

    it "an unreachable state has no dominators, and says so" $ do
      dominators orphanGraph 4 `shouldBe` Unreachable
      -- The orphan's edge to Fulfilled is not a route from the start, so it
      -- does not spoil the dominance of the real route.
      acts (dominators orphanGraph 2) `shouldBe` Just ["pay", "deliver"]

    it "a state id the graph does not have is reported as unreachable" $
      dominators orphanGraph 99 `shouldBe` Unreachable

  describe "fulfilmentView" $ do
    it "leaves a graph without RAND untouched" $
      withGraph chainSrc \sg ->
        fulfilmentView sg `shouldBe` sg

    it "runs RAND branches in sequence: the first branch exits into the second" $
      withGraph randSrc \sg -> do
        let view = fulfilmentView sg
            junction = sg.sgInitialState
            entries = [ t.transTo | t <- sg.sgTransitions, t.transFrom == junction ]
        case entries of
          [aliceEntry, bobEntry] -> do
            -- The junction now has one branch edge, not two.
            [ t.transTo | t <- view.sgTransitions, t.transFrom == junction ] `shouldBe` [aliceEntry]
            -- Alice's HENCE goes to Bob's entry instead of Fulfilled …
            [ t.transTo | t <- view.sgTransitions, t.transFrom == aliceEntry, t.transType == HenceTransition ]
              `shouldBe` [bobEntry]
            -- … while Bob's still reaches the sink, and Alice's LEST still breaches.
            [ t.transTo | t <- view.sgTransitions, t.transFrom == bobEntry, t.transType == HenceTransition ]
              `shouldBe` [fulfilled sg]
            [ t.transTo | t <- view.sgTransitions, t.transFrom == aliceEntry, t.transType == LestTransition ]
              `shouldBe` [breach sg]
          other -> expectationFailure ("expected two branches, got " <> show other)

  describe "rendering" $ do
    it "phrases an obligation with its party, modal and deadline" $
      withGraph chainSrc \sg -> do
        case dominators sg (fulfilled sg) of
          Dominated (first:_) -> renderTransition sg first `shouldBe` Just "PARTY Alice pay (MUST, WITHIN 3)"
          other -> expectationFailure ("unexpected " <> show other)

    it "names a LEST arm by the obligation it belongs to" $
      withGraph renewSrc \sg -> do
        case dominators sg (breach sg) of
          Dominated [lest] -> renderTransition sg lest `shouldBe` Just "the deadline passing on PARTY Alice pay (MUST, WITHIN 3)"
          other -> expectationFailure ("unexpected " <> show other)

    it "reports the terminal states of a RAND for a reader" $
      withGraph randSrc \sg ->
        renderGraphDominators False sg `shouldBe`
          [ "both"
          , "  Every path to FULFILLED passes through:"
          , "    - PARTY Alice pay (MUST, WITHIN 3)"
          , "    - PARTY Bob deliver (MUST, WITHIN 5)"
          , "  Every path to BREACH passes through: nothing in particular (there is more than one route)."
          ]

    it "says when a target cannot be reached" $
      renderDominance orphanGraph (orphanGraph.sgStates !! 4) Unreachable
        `shouldBe` [ "No path reaches \"nobody comes here\" from the start state." ]
