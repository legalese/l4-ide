{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | Dominators over the state graph (LTS-VISUALISER §1.1c, P2f): for a
-- target state, the acts every path from the start must traverse.
--
-- Each fixture is a shape with a known answer — a chain, a choice, a
-- conjunction (two-way and three-way), the two nestings, a guarded @IF@, a
-- cycle, and a hand-built graph with a state nothing reaches — and the
-- assertions name the acts by their action text, which is what a reader of
-- @l4 state-graph --dominators@ sees. The @RAND@ and @ROR@ cases are the
-- ones that would go wrong first: the IR has no join (ruling R2), so a
-- naive walk of the drawn graph says neither branch of a conjunction is
-- needed to fulfil, and neither alternative of a choice is needed to
-- breach. See 'fulfilmentView' and 'breachView'; the breach half is checked
-- against the evaluator in the @ROR@ breach test below.
module DominatorsSpec (spec) where

import Test.Hspec
import Data.Bifunctor (bimap)
import Data.Maybe (mapMaybe)
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

-- | Every graph of a fixture, for the shapes that span two rules.
withGraphs :: [Text] -> ([StateGraph] -> Expectation) -> Expectation
withGraphs body k =
  case checkWithImports emptyVFS (Text.unlines (preamble <> body)) of
    Left errs -> expectationFailure ("fixture failed to check: " <> show errs)
    Right r   -> k (extractStateGraphs r.tcdModule)

-- | The action text of each dominating transition a reader would see, in
-- order. Which transitions count is decided by 'renderTransition' itself —
-- the production path — so a bare @RAND@ \/ @ROR@ branch edge is dropped
-- as the CLI drops it, and an @IF@ arm, which has no action text of its
-- own, is named by its rendering (@the arm IF …@).
acts :: StateGraph -> Dominance -> Maybe [Text]
acts sg = \case
  Unreachable  -> Nothing
  Dominated ts -> Just [ if Text.null a then r else a
                       | t <- ts, Just r <- [renderTransition sg t], let a = t.transLabel.labelAction ]

terminal :: StateType -> StateGraph -> StateId
terminal ty sg = case [ s.stateId | s <- sg.sgStates, s.stateType == ty ] of
  (sid:_) -> sid
  []      -> error ("fixture has no " <> show ty)

fulfilled, breach :: StateGraph -> StateId
fulfilled = terminal TerminalFulfilled
breach    = terminal TerminalBreach

chainSrc, randSrc, rand3Src, rorSrc, prefixRorSrc, rorInRandSrc, randInRorSrc, ifSrc, renewSrc :: [Text]

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

rand3Src =
  [ "`all three` MEANS"
  , "      (PARTY Alice MUST pay WITHIN 3)"
  , "  RAND (PARTY Bob MUST deliver WITHIN 5)"
  , "  RAND (PARTY Carol MUST notify WITHIN 7)"
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

-- | An @IF@ over regulative arms after an act: a @OneOf@ junction whose
-- branch edges carry a guard, which 'renderTransition' names and which the
-- breach view must NOT sequentialise (the arms are exclusive).
ifSrc =
  [ "`sign then choose` MEANS"
  , "  PARTY Carol MUST sign WITHIN 1"
  , "  HENCE (IF 1 EQUALS 1 THEN (PARTY Alice MUST pay WITHIN 3)"
  , "                       ELSE (PARTY Bob MUST deliver WITHIN 5))"
  ]

renewSrc =
  [ "`renew` MEANS"
  , "  PARTY Alice MUST pay WITHIN 3"
  , "  HENCE `renew`"
  ]

-- | Two rules that continue into each other. Only extractable as a loop
-- since B2 (2026-09-16); before that `pong` was a dead-end state.
mutualSrc :: [Text]
mutualSrc =
  [ "`ping` MEANS"
  , "  PARTY Alice MUST pay WITHIN 3"
  , "  HENCE `pong`"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "`pong` MEANS"
  , "  PARTY Bob MUST deliver WITHIN 5"
  , "  HENCE `ping`"
  ]

-- | @ok/contracts.l4@'s shape: a @ROR@ of two named rules, and a @RAND@ of
-- that rule with itself. The evaluator runs two instances of @z@; until
-- 2026-09-16 the extractor drew one, and the fulfilment view sequenced it
-- with itself.
twiceSrc :: [Text]
twiceSrc =
  [ "`x` MEANS"
  , "  PARTY Alice MUST pay WITHIN 3"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "`y` MEANS"
  , "  PARTY Bob MUST deliver WITHIN 5"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "`z` MEANS"
  , "  `x` ROR `y`"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "`a` MEANS"
  , "  `z` RAND `z`"
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
      [ ContractState 0 "initial" InitialState Linear Nothing Nothing
      , ContractState 1 "Bob must deliver" IntermediateState Linear Nothing Nothing
      , ContractState 2 "Fulfilled" TerminalFulfilled Linear Nothing Nothing
      , ContractState 3 "Breach" TerminalBreach Linear Nothing Nothing
      , ContractState 4 "nobody comes here" IntermediateState Linear Nothing Nothing
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
  -- the fourth field is the window's opening edge (AFTER, EVERY-EACH-QUANTIFIER-SPEC §5.1.2);
  -- the ninth is the site the edge was drawn from (P2g, LTS-VISUALISER §4.8)
  act p a = TransitionLabel (Just p) (Just DMust) a Nothing Nothing Nothing Nothing Nothing Nothing Nothing
  timeout = TransitionLabel Nothing (Just DMust) "timeout" Nothing Nothing Nothing Nothing Nothing Nothing Nothing

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "dominators" $ do
    it "a chain: every act dominates the fulfilled sink" $
      withGraph chainSrc \sg ->
        acts sg (dominators sg (fulfilled sg)) `shouldBe` Just ["pay", "deliver", "notify"]

    it "a chain: nothing dominates the breach sink, because every link can time out" $
      withGraph chainSrc \sg ->
        acts sg (dominators sg (breach sg)) `shouldBe` Just []

    it "a chain: an intermediate state is dominated by the acts before it" $
      withGraph chainSrc \sg -> do
        -- The state name carries the obligation's window since 2026-09-22
        -- ('L4.StateGraph.describeDeonton'): without it the promissory note
        -- drew three of its six states under one string.
        case [ s.stateId | s <- sg.sgStates, s.stateName == "Carol must notify WITHIN 7" ] of
          [carol] -> acts sg (dominators sg carol) `shouldBe` Just ["pay", "deliver"]
          other   -> expectationFailure ("expected one Carol state, got " <> show other)

    it "the entry state is dominated by nothing" $
      withGraph chainSrc \sg ->
        dominators sg sg.sgInitialState `shouldBe` Dominated []

    it "ROR: neither alternative dominates the fulfilled sink" $
      withGraph rorSrc \sg ->
        acts sg (dominators sg (fulfilled sg)) `shouldBe` Just []

    -- Cross-checked against the evaluator (Machine.hs, RBinOp2: a compound
    -- is breached only when both operands are). `l4 run` on this rule with
    -- a stray event AT 4 — Alice's deadline passed, Bob's open — reports a
    -- residual `… OR PARTY Bob MUST deliver WITHIN 1`, not a breach; AT 6
    -- it reports the breach. So every run that reaches Breach passes both
    -- deadlines.
    it "ROR: both timeouts dominate the breach sink, because every alternative must be lost" $
      withGraph rorSrc \sg ->
        acts sg (dominators sg (breach sg)) `shouldBe` Just ["timeout", "timeout"]

    it "ROR after an act: the act before the split dominates, the alternatives do not" $
      withGraph prefixRorSrc \sg ->
        acts sg (dominators sg (fulfilled sg)) `shouldBe` Just ["sign"]

    it "RAND: both branches dominate the fulfilled sink" $
      withGraph randSrc \sg ->
        acts sg (dominators sg (fulfilled sg)) `shouldBe` Just ["pay", "deliver"]

    it "RAND: neither branch dominates the breach sink, because either can fail" $
      withGraph randSrc \sg ->
        acts sg (dominators sg (breach sg)) `shouldBe` Just []

    it "a RAND b RAND c: one three-way junction, and all three branches dominate the fulfilled sink" $
      withGraph rand3Src \sg -> do
        length [ t | t <- sg.sgTransitions, t.transFrom == sg.sgInitialState ] `shouldBe` 3
        acts sg (dominators sg (fulfilled sg)) `shouldBe` Just ["pay", "deliver", "notify"]
        acts sg (dominators sg (breach sg)) `shouldBe` Just []

    it "(a ROR b) RAND c: only c dominates the fulfilled sink, and nothing the breach sink" $
      withGraph rorInRandSrc \sg -> do
        acts sg (dominators sg (fulfilled sg)) `shouldBe` Just ["notify"]
        -- Breach if both a and b are lost, or if c is: two routes.
        acts sg (dominators sg (breach sg)) `shouldBe` Just []

    it "(a RAND b) ROR c: nothing dominates the fulfilled sink, and only c's timeout the breach sink" $
      withGraph randInRorSrc \sg -> do
        acts sg (dominators sg (fulfilled sg)) `shouldBe` Just []
        -- Breach needs c lost AND (a or b) lost: c's deadline is on every
        -- route, a's and b's are alternatives.
        case dominators sg (breach sg) of
          Dominated ts -> mapMaybe (renderTransition sg) ts `shouldBe`
            [ "the deadline passing on PARTY Carol notify (MUST, WITHIN 7)" ]
          other -> expectationFailure ("unexpected " <> show other)

    it "an IF between arms: the arm taken dominates the state inside it, and either arm can breach" $
      withGraph ifSrc \sg -> do
        case [ s.stateId | s <- sg.sgStates, s.stateName == "Alice must pay WITHIN 3" ] of
          [alice] -> acts sg (dominators sg alice) `shouldBe` Just ["sign", "the arm IF 1 EQUALS 1"]
          other   -> expectationFailure ("expected one Alice state, got " <> show other)
        acts sg (dominators sg (fulfilled sg)) `shouldBe` Just ["sign"]
        -- Breach is reachable from sign's own deadline, and the IF's OneOf
        -- is exclusive, so the breach view leaves it alone: no single edge
        -- is on every route to Breach.
        acts sg (dominators sg (breach sg)) `shouldBe` Just []

    it "a renewing duty: the cycle terminates, and only the timeout reaches breach" $
      withGraph renewSrc \sg -> do
        -- HENCE back to the start draws no Fulfilled state at all.
        [ s.stateType | s <- sg.sgStates ] `shouldNotContain` [TerminalFulfilled]
        acts sg (dominators sg (breach sg)) `shouldBe` Just ["timeout"]

    it "a loop through another rule (B2): the fixpoint terminates, and the acts on the way in dominate" $
      -- `ping` continues into `pong`, which continues back into `ping`; the
      -- only exit is a timeout. Every path to Breach goes through the loop
      -- some number of times, so no act dominates it — a cycle is exactly
      -- where "greatest fixpoint" and "every path" have to agree, and this
      -- is the graph that would loop the solver if they did not. `pong`'s
      -- state, by contrast, is reached only through Alice's act.
      withGraphs mutualSrc \gs -> case [ g | g <- gs, g.sgName == "ping" ] of
        [sg] -> do
          [ s.stateType | s <- sg.sgStates ] `shouldNotContain` [TerminalFulfilled]
          acts sg (dominators sg (breach sg)) `shouldBe` Just []
          case [ s.stateId | s <- sg.sgStates, s.stateName == "pong" ] of
            [pong] -> acts sg (dominators sg pong) `shouldBe` Just ["pay"]
            other  -> expectationFailure ("expected one pong state, got " <> show other)
        other -> expectationFailure ("expected one ping graph, got " <> show (length other))

    it "a rule RANDed with itself (B2): both instances fulfil, so nothing dominates FULFILLED" $
      -- `a MEANS z RAND z` with `z MEANS x ROR y`. Each instance of `z`
      -- fulfils by either of its arms, so no act is on every path to
      -- FULFILLED — and there IS a path, which is what the sequential view
      -- lost when both branches landed on one `z`: branch 1's arrival at
      -- FULFILLED was re-pointed at branch 2's entry, which was itself. To
      -- BREACH either instance suffices, and each needs both its arms
      -- lost: two routes, disjoint edge sets, and the answer is per edge
      -- (module header), so nothing dominates BREACH either. Within one
      -- instance both timeouts do — the `z` graph of the same file.
      withGraphs twiceSrc \gs -> case ([ g | g <- gs, g.sgName == "a" ], [ g | g <- gs, g.sgName == "z" ]) of
        ([sg], [zg]) -> do
          length [ s | s <- sg.sgStates, s.stateName == "z" ] `shouldBe` 2
          acts sg (dominators sg (fulfilled sg)) `shouldBe` Just []
          acts sg (dominators sg (breach sg)) `shouldBe` Just []
          acts zg (dominators zg (fulfilled zg)) `shouldBe` Just []
          acts zg (dominators zg (breach zg)) `shouldBe` Just ["timeout", "timeout"]
        other -> expectationFailure ("expected one graph each for a and z, got " <> show (bimap length length other))

    it "an unreachable state has no dominators, and says so" $ do
      dominators orphanGraph 4 `shouldBe` Unreachable
      -- The orphan's edge to Fulfilled is not a route from the start, so it
      -- does not spoil the dominance of the real route.
      acts orphanGraph (dominators orphanGraph 2) `shouldBe` Just ["pay", "deliver"]

    it "a state id the graph does not have is reported as unreachable" $
      dominators orphanGraph 99 `shouldBe` Unreachable

  describe "fulfilmentView" $ do
    it "leaves a graph without RAND untouched" $
      withGraph chainSrc \sg ->
        fulfilmentView sg `shouldBe` sg

    it "leaves an ROR untouched: the choice's join is breachView's business" $
      withGraph rorSrc \sg ->
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

  describe "breachView" $ do
    it "leaves a graph without ROR untouched, RAND included" $ do
      withGraph chainSrc \sg -> breachView sg `shouldBe` sg
      withGraph randSrc \sg -> breachView sg `shouldBe` sg

    it "leaves an IF-derived OneOf untouched: its arms are exclusive" $
      withGraph ifSrc \sg -> breachView sg `shouldBe` sg

    it "runs ROR branches in sequence: the first branch's timeout exits into the second" $
      withGraph rorSrc \sg -> do
        let view = breachView sg
            junction = sg.sgInitialState
            entries = [ t.transTo | t <- sg.sgTransitions, t.transFrom == junction ]
        case entries of
          [aliceEntry, bobEntry] -> do
            [ t.transTo | t <- view.sgTransitions, t.transFrom == junction ] `shouldBe` [aliceEntry]
            -- Alice's LEST goes to Bob's entry instead of Breach …
            [ t.transTo | t <- view.sgTransitions, t.transFrom == aliceEntry, t.transType == LestTransition ]
              `shouldBe` [bobEntry]
            -- … while Bob's still reaches the sink, and Alice's HENCE still fulfils.
            [ t.transTo | t <- view.sgTransitions, t.transFrom == bobEntry, t.transType == LestTransition ]
              `shouldBe` [breach sg]
            [ t.transTo | t <- view.sgTransitions, t.transFrom == aliceEntry, t.transType == HenceTransition ]
              `shouldBe` [fulfilled sg]
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

    it "reports the terminal states of an ROR for a reader: the dual of the RAND" $
      withGraph rorSrc \sg ->
        renderGraphDominators False sg `shouldBe`
          [ "either"
          , "  Every path to FULFILLED passes through: nothing in particular (there is more than one route)."
          , "  Every path to BREACH passes through:"
          , "    - the deadline passing on PARTY Alice pay (MUST, WITHIN 3)"
          , "    - the deadline passing on PARTY Bob deliver (MUST, WITHIN 5)"
          ]

    it "says when a target cannot be reached" $
      renderDominance orphanGraph (orphanGraph.sgStates !! 4) Unreachable
        `shouldBe` [ "No path reaches \"nobody comes here\" from the start state." ]
