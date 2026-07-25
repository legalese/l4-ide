-- | BPMN 2.0 export from the regulative layer (PROCESS-TRACK.md).
--
-- The tests that matter here are the ones that would still pass if the
-- exporter were wrong in the interesting way. Two in particular:
--
-- * @RAND@ and @ROR@ must produce /different/ gateways. Before P0 gave the
--   state graph explicit junctions the two operators were indistinguishable in
--   the IR, and a test that merely asserted \"a gateway appears\" would have
--   passed for both while the diagram said the opposite of the rule.
-- * A deadline we cannot express as an ISO 8601 duration must produce /no/
--   duration. Inventing @P30D@ from an expression nobody can evaluate is the
--   failure mode that makes an exported model worse than no model.
module BpmnExport (spec) where

import Base
import qualified Base.Text as Text
import qualified Data.Set as Set
import System.FilePath ((</>))
import Test.Hspec
import Test.Hspec.Golden

import L4.API.VirtualFS (checkWithImports, emptyVFS, TypeCheckWithDepsResult (..))
import L4.Bpmn.Emit (renderBpmn)
import L4.Bpmn.IR
import L4.Bpmn.Lower (stateGraphToBpmn)
import L4.Interchange.Fidelity
import L4.StateGraph
import L4.Syntax (DeonticModal (..))

import qualified Paths_jl4

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
  , "  gamble HAS amount IS A NUMBER"
  , ""
  ]

-- | A plain HENCE chain across two parties. No RAND, no ROR, so no gateway may
-- appear anywhere in the output.
linearSrc :: [Text]
linearSrc =
  [ "`chain` MEANS"
  , "  PARTY Alice"
  , "  MUST pay"
  , "  WITHIN 3"
  , "  HENCE"
  , "    PARTY Bob"
  , "    MUST deliver"
  , "    WITHIN 5"
  ]

-- | An explicit LEST continuation: the reparation is another obligation, not a
-- terminal, so the boundary event has somewhere interesting to go.
lestSrc :: [Text]
lestSrc =
  [ "`late` MEANS"
  , "  PARTY Alice"
  , "  MUST pay"
  , "  WITHIN 3"
  , "  HENCE FULFILLED"
  , "  LEST"
  , "    PARTY Alice"
  , "    MUST notify"
  , "    WITHIN 1"
  ]

randSrc, rorSrc :: [Text]
randSrc =
  [ "`split` MEANS"
  , "      (PARTY Alice MUST pay WITHIN 3)"
  , "  RAND (PARTY Bob MUST deliver WITHIN 5)"
  ]
rorSrc =
  [ "`split` MEANS"
  , "      (PARTY Alice MUST pay WITHIN 3)"
  , "  ROR  (PARTY Bob MUST deliver WITHIN 5)"
  ]

-- | Both branches are permissions with no deadline, so each contributes
-- exactly one token by exactly one route: no LEST arm, no lapse timer, no
-- guard. That is the only shape for which a converging parallel gateway is
-- sound, and it is deliberately a narrow one.
randJoinSrc :: [Text]
randJoinSrc =
  [ "`both` MEANS"
  , "      (PARTY Alice MAY pay)"
  , "  RAND (PARTY Bob MAY deliver)"
  ]

-- | The same, but each branch carries a deadline. The lapse timer gives every
-- branch a SECOND route to the join point, and the two are mutually exclusive,
-- so a parallel join would wait for four tokens where two arrive.
randDeadlockSrc :: [Text]
randDeadlockSrc =
  [ "`both` MEANS"
  , "      (PARTY Alice MAY pay WITHIN 3)"
  , "  RAND (PARTY Bob MAY deliver WITHIN 5)"
  ]

-- | A ROR inside a RAND branch: the exclusive gateway sends one token down one
-- of two edges, and both edges arrive at the join.
rorInRandSrc :: [Text]
rorInRandSrc =
  [ "`mixed` MEANS"
  , "      (PARTY Alice MAY pay)"
  , "  RAND ((PARTY Bob MAY deliver) ROR (PARTY Carol MAY notify))"
  ]

-- | A PROVIDED guard inside a RAND branch: that branch reaches the join by a
-- CONDITIONAL flow, which may never fire at all.
guardInRandSrc :: [Text]
guardInRandSrc =
  [ "`mixed` MEANS"
  , "      (PARTY Alice MAY gamble amt PROVIDED amt > 100)"
  , "  RAND (PARTY Bob MAY deliver)"
  ]

-- | A RAND inside the HENCE of a branch of another RAND — nested for real,
-- since an associative @a RAND b RAND c@ is flattened into one junction. Both
-- are joinable and both want the same terminal, but only the outer one can have
-- the join: by the time the inner is considered, its branches' edges already
-- point at the outer gateway. The hazard this guards against is a converging
-- gateway with nothing flowing into it.
nestedJoinSrc :: [Text]
nestedJoinSrc =
  [ "`nested` MEANS"
  , "      (PARTY Alice MAY pay WITHIN 3"
  , "         HENCE ((PARTY Bob MAY deliver WITHIN 5) RAND (PARTY Carol MAY notify WITHIN 7)))"
  , "  RAND (PARTY Alice MAY notify WITHIN 9)"
  ]

-- | A prohibition with a deadline, and the same shape as a MUST. Deliberately
-- named identically so that the two sources differ in exactly one token: any
-- difference in the output is attributable to the modal and nothing else.
shantSrc, mustSrc :: [Text]
shantSrc =
  [ "`rule` MEANS"
  , "  PARTY Alice"
  , "  SHANT notify"
  , "  WITHIN 30"
  ]
mustSrc =
  [ "`rule` MEANS"
  , "  PARTY Alice"
  , "  MUST notify"
  , "  WITHIN 30"
  ]

-- | The same pair again, but with a deadline that is a /name/, so no ISO
-- duration can be built and the boundary event falls back to naming itself
-- after the LEST edge's own label. That label is the extractor's bare
-- \"timeout\" (or \"violation\") for every modal alike, which is where the
-- wrong word leaks onto a prohibition's compliance arm.
shantOpaqueSrc, mustOpaqueSrc :: [Text]
shantOpaqueSrc =
  [ "`grace` MEANS 30"
  , ""
  , "`rule` MEANS"
  , "  PARTY Alice"
  , "  SHANT notify"
  , "  WITHIN grace"
  ]
mustOpaqueSrc =
  [ "`grace` MEANS 30"
  , ""
  , "`rule` MEANS"
  , "  PARTY Alice"
  , "  MUST notify"
  , "  WITHIN grace"
  ]

-- | A permission with a deadline and no LEST: nothing to hang a LEST boundary
-- on, but the lapse still has a knowable destination.
mayNoLestSrc :: [Text]
mayNoLestSrc =
  [ "`optional` MEANS"
  , "  PARTY Alice"
  , "  MAY notify"
  , "  WITHIN 30"
  ]

-- | A @PROVIDED@ guard. In L4 this is a precondition on the obligation; BPMN
-- has no activity precondition, so it can only become a condition on the way
-- out.
guardSrc :: [Text]
guardSrc =
  [ "`guarded` MEANS"
  , "  PARTY Alice"
  , "  MUST gamble amt PROVIDED amt > 100"
  , "  WITHIN 3"
  ]

-- | A deadline that is a name, not a number. @prettyLayout@ hands us @grace@,
-- which is not a duration and never will be.
opaqueDeadlineSrc :: [Text]
opaqueDeadlineSrc =
  [ "`grace` MEANS 30"
  , ""
  , "`deferred` MEANS"
  , "  PARTY Alice"
  , "  MUST pay"
  , "  WITHIN grace"
  , "  HENCE FULFILLED"
  , "  LEST BREACH BY Alice BECAUSE \"late\""
  ]

--------------------------------------------------------------------------------
-- Hand-built state graphs
--------------------------------------------------------------------------------

-- Three shapes the 'StateGraph' types permit and no L4 source can currently
-- produce, so they are built by hand. That is not a contrivance: 'L4.Bpmn.Lower'
-- is written against the types, every one of these lowers to a diagram that
-- says something the source did not, and \"the extractor happens not to emit it
-- this month\" is a property of the extractor, not of the exporter.
--
-- Each is deliberately minimal — one anomaly, nothing else — so that a failure
-- names the anomaly rather than a fixture.

node :: StateId -> Text -> StateType -> FanKind -> ContractState
node i nm ty fan =
  ContractState {stateId = i, stateName = nm, stateType = ty, stateFan = fan}

-- | An obligation edge. The label is as plain as the type allows: any
-- difference between two of these is the thing under test.
edge :: StateId -> StateId -> TransitionType -> Text -> Transition
edge src dst ty act =
  Transition
    { transFrom = src
    , transTo = dst
    , transLabel =
        TransitionLabel
          { labelParty = Just "Alice"
          , labelModal = Just DMust
          , labelAction = act
          , labelDeadline = Nothing
          , labelGuard = Nothing
          }
    , transType = ty
    }

byHand :: Text -> [ContractState] -> [Transition] -> StateGraph
byHand nm ss ts =
  StateGraph {sgName = nm, sgStates = ss, sgTransitions = ts, sgInitialState = 0}

-- | Two HENCE arms out of one state. Both leave the same task, neither carries
-- a condition, and BPMN reads that as an implicit AND-split.
multiHenceGraph :: StateGraph
multiHenceGraph =
  byHand
    "two ways on"
    [ node 0 "start" InitialState Linear
    , node 1 "Fulfilled" TerminalFulfilled Linear
    , node 2 "Breach" TerminalBreach Linear
    ]
    [edge 0 1 HenceTransition "pay", edge 0 2 HenceTransition "deliver"]

-- | The control for it: the same graph with one HENCE.
oneHenceGraph :: StateGraph
oneHenceGraph =
  byHand
    "one way on"
    [ node 0 "start" InitialState Linear
    , node 1 "Fulfilled" TerminalFulfilled Linear
    ]
    [edge 0 1 HenceTransition "pay"]

-- | A state that is both an @AllOf@ junction and an obligation.
junctionObligationGraph :: StateGraph
junctionObligationGraph =
  byHand
    "junction that is also a duty"
    [ node 0 "start" InitialState AllOf
    , node 1 "left" IntermediateState Linear
    , node 2 "right" IntermediateState Linear
    , node 3 "Fulfilled" TerminalFulfilled Linear
    ]
    [ edge 0 1 DefaultTransition "left branch"
    , edge 0 2 DefaultTransition "right branch"
    , edge 0 3 HenceTransition "pay"
    , edge 1 3 HenceTransition "do the left thing"
    , edge 2 3 HenceTransition "do the right thing"
    ]

-- | The control: the same junction with no obligation on it.
plainJunctionGraph :: StateGraph
plainJunctionGraph =
  byHand
    "junction that is only a junction"
    [ node 0 "start" InitialState AllOf
    , node 1 "left" IntermediateState Linear
    , node 2 "right" IntermediateState Linear
    , node 3 "Fulfilled" TerminalFulfilled Linear
    ]
    [ edge 0 1 DefaultTransition "left branch"
    , edge 0 2 DefaultTransition "right branch"
    , edge 1 3 HenceTransition "do the left thing"
    , edge 2 3 HenceTransition "do the right thing"
    ]

-- | A back edge: state 2 returns to state 1.
cyclicGraph :: StateGraph
cyclicGraph =
  byHand
    "round and round"
    [ node 0 "start" InitialState Linear
    , node 1 "review" IntermediateState Linear
    , node 2 "revise" IntermediateState Linear
    , node 3 "Breach" TerminalBreach Linear
    ]
    [ edge 0 1 HenceTransition "submit"
    , edge 1 2 HenceTransition "reject"
    , edge 2 1 HenceTransition "resubmit"
    , edge 1 3 LestTransition "timeout"
    ]

-- | The control: the same four states, wired forwards only.
acyclicGraph :: StateGraph
acyclicGraph =
  byHand
    "straight through"
    [ node 0 "start" InitialState Linear
    , node 1 "review" IntermediateState Linear
    , node 2 "revise" IntermediateState Linear
    , node 3 "Breach" TerminalBreach Linear
    ]
    [ edge 0 1 HenceTransition "submit"
    , edge 1 2 HenceTransition "reject"
    , edge 1 3 LestTransition "timeout"
    ]

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

graphsFor :: [Text] -> [StateGraph]
graphsFor body =
  case checkWithImports emptyVFS (Text.unlines (preamble <> body)) of
    Left errs -> error ("fixture failed to typecheck: " <> show errs)
    Right r -> extractStateGraphs r.tcdModule

graphNamed :: Text -> [Text] -> StateGraph
graphNamed nm body = case [g | g <- graphsFor body, g.sgName == nm] of
  (g : _) -> g
  [] -> error ("no state graph named " <> show nm)

exportOf :: BpmnOptions -> Text -> [Text] -> BpmnExport
exportOf opts nm body = stateGraphToBpmn opts (graphNamed nm body)

xmlOf :: Text -> [Text] -> Text
xmlOf nm = renderBpmn . exportOf defaultBpmnOptions nm

nodesWhere :: (FlowNode -> Bool) -> BpmnExport -> [FlowNode]
nodesWhere p bx = filter p bx.bxProcess.procNodes

isKind :: (NodeKind -> Bool) -> FlowNode -> Bool
isKind p n = p n.nodeKind

-- | Ids of converging parallel gateways: the joins.
converging :: BpmnExport -> [Text]
converging bx =
  [n.nodeId | n <- bx.bxProcess.procNodes, Gateway ParallelGateway Converging <- [n.nodeKind]]

gateways :: BpmnExport -> [FlowNode]
gateways = nodesWhere (isKind \case Gateway _ _ -> True; _ -> False)

boundaries :: BpmnExport -> [FlowNode]
boundaries = nodesWhere (isKind \case Boundary _ _ -> True; _ -> False)

tasks :: BpmnExport -> [FlowNode]
tasks = nodesWhere (isKind (== Task))

nodeNamed :: BpmnExport -> Text -> Maybe FlowNode
nodeNamed bx nid = find (\n -> n.nodeId == nid) bx.bxProcess.procNodes

-- | Notes carrying a given code, in emission order. @F1@-@F5@ are losses of
-- the notation; @P-…@ are approximations this exporter made.
findingsFor :: Text -> BpmnExport -> [FidelityNote]
findingsFor c bx = [n | n <- bx.bxFidelity.notes, n.code == c]

------------------------------------------------------------------------
-- Reachability, so tests can assert MEANING rather than shape
------------------------------------------------------------------------

-- | Every node reachable from a starting node by following sequence flows.
--
-- This is what lets a test ask \"where does waiting get you?\" instead of \"is
-- there a boundary event?\". The distinction is not academic: the version of
-- this exporter that raced every prohibition backwards had exactly the right
-- /number/ of boundary events, every attribute well-formed, and passed
-- bpmn-moddle with zero warnings.
--
-- A boundary event is /attached/ to its task rather than flowed to, so walking
-- from the task never wanders onto the boundary's arm. That separation is what
-- makes 'raceOutcome' able to see the two arms independently.
reachableFrom :: BpmnExport -> Text -> Set Text
reachableFrom bx = go Set.empty . pure
 where
  go seen [] = seen
  go seen (n : rest)
    | Set.member n seen = go seen rest
    | otherwise =
        go
          (Set.insert n seen)
          ([f.flowTo | f <- bx.bxProcess.procFlows, f.flowFrom == n] <> rest)

-- | Which terminal a path ends at.
data Terminal = ToFulfilled | ToBreach | ToBoth | ToNeither
  deriving stock (Eq, Show)

terminalFrom :: BpmnExport -> Text -> Terminal
terminalFrom bx start =
  case (reachesEnd False, reachesEnd True) of
    (True, True) -> ToBoth
    (True, False) -> ToFulfilled
    (False, True) -> ToBreach
    (False, False) -> ToNeither
 where
  reached = Set.toList (reachableFrom bx start)
  reachesEnd wantError =
    any
      (\nid -> maybe False ((== EndEvent wantError) . (.nodeKind)) (nodeNamed bx nid))
      reached

-- | The two arms of an obligation's race, as terminals:
-- @(where completing the activity gets you, where the deadline expiring gets
-- you)@.
--
-- For @MUST@ that should be @(ToFulfilled, ToBreach)@ and for @SHANT@ exactly
-- the reverse — which is the entire content of the bug this pins.
raceOutcome :: BpmnExport -> (Terminal, Terminal)
raceOutcome bx = (fromNode taskId, fromNode boundaryId)
 where
  fromNode = maybe ToNeither (terminalFrom bx)
  taskId = listToMaybe [n.nodeId | n <- bx.bxProcess.procNodes, n.nodeKind == Task]
  boundaryId =
    listToMaybe [n.nodeId | n <- bx.bxProcess.procNodes, Boundary _ _ <- [n.nodeKind]]

-- | Converging parallel gateways that cannot possibly receive a token on every
-- incoming flow — i.e. every join this exporter should have declined to draw.
--
-- Two ways a join is unsound, both of which the exporter once emitted happily:
-- an incoming flow that is conditional (it may never fire), and two incoming
-- flows whose sources are mutually exclusive (a boundary event and its own
-- host, since @cancelActivity@ makes them alternatives; or two arms of a common
-- exclusive gateway). This is a token argument, not a shape argument, which is
-- the entire point.
unsoundJoins :: BpmnExport -> [(Text, Text)]
unsoundJoins bx =
  [ (g.nodeId, why)
  | g <- bx.bxProcess.procNodes
  , Gateway ParallelGateway Converging <- [g.nodeKind]
  , let ins = [f | f <- bx.bxProcess.procFlows, f.flowTo == g.nodeId]
  , why <- conditionalIn ins <> exclusivePairs (map (.flowFrom) ins)
  ]
 where
  conditionalIn ins =
    ["conditional incoming flow" | any (isJust . (.flowCondition)) ins]

  exclusivePairs srcs =
    [ "mutually exclusive sources: " <> a <> " and " <> b
    | (a, b) <- distinctPairs srcs
    , exclusive a b
    ]

  distinctPairs xs = [(a, b) | (i, a) <- zip [0 :: Int ..] xs, (j, b) <- zip [0 ..] xs, i < j]

  hostOf nid = case nodeNamed bx nid of
    Just n | Boundary h _ <- n.nodeKind -> Just h
    _ -> Nothing

  -- An interrupting boundary and its host are alternatives, never both.
  attached a b = hostOf a == Just b || hostOf b == Just a

  -- Two arms of one exclusive gateway are alternatives too.
  splitApart a b =
    or
      [ any (Set.member a . reachableFrom bx) [f.flowTo | f <- outs, f.flowId == fi]
          && any (Set.member b . reachableFrom bx) [f.flowTo | f <- outs, f.flowId == fj]
      | x <- bx.bxProcess.procNodes
      , Gateway ExclusiveGateway _ <- [x.nodeKind]
      , let outs = [f | f <- bx.bxProcess.procFlows, f.flowFrom == x.nodeId]
      , (fi, fj) <- distinctPairs (map (.flowId) outs)
      ]

  exclusive a b = attached a b || splitApart a b

------------------------------------------------------------------------
-- Geometry, checked by arithmetic rather than by eye
------------------------------------------------------------------------

-- | Node shapes only: the pool and lane bands are containers and every edge is
-- expected to run through them.
flowNodeShapes :: BpmnExport -> [(Text, Bounds)]
flowNodeShapes bx =
  [(sh.shapeOf, sh.shapeBounds) | sh <- bx.bxDiagram.diagShapes, sh.shapeKind == PlainShape]

segments :: EdgeGeom -> [(Point, Point)]
segments e = zip e.edgeWaypoints (drop 1 e.edgeWaypoints)

-- | Edge segments that pass through a node shape that is not one of their own
-- endpoints. Any hit is a line drawn straight over a box.
--
-- The old router dropped a boundary event's outflow vertically at
-- @task.bx + 72@ — inside the column every task at that rank occupies — and ran
-- it the height of the pool: twelve hits in one exhibit. Nothing in the
-- structural tests could see it, and bpmn-moddle reported zero warnings.
crossings :: BpmnExport -> [(Text, Text)]
crossings bx =
  [ (e.edgeOf, nid)
  | e <- bx.bxDiagram.diagEdges
  , (p, q) <- segments e
  , (nid, b) <- flowNodeShapes bx
  , hits p q b
  , not (endpointInside b (p, q))
  ]
 where
  hits p q b
    | p.ptX == q.ptX =
        p.ptX > b.bx && p.ptX < b.bx + b.bw && overlaps (p.ptY, q.ptY) (b.by, b.by + b.bh)
    | p.ptY == q.ptY =
        p.ptY > b.by && p.ptY < b.by + b.bh && overlaps (p.ptX, q.ptX) (b.bx, b.bx + b.bw)
    | otherwise = False
  overlaps (a1, a2) (c1, c2) = max (min a1 a2) c1 < min (max a1 a2) c2
  endpointInside b (p, q) = any inside [p, q]
   where
    inside pt =
      pt.ptX >= b.bx && pt.ptX <= b.bx + b.bw && pt.ptY >= b.by && pt.ptY <= b.by + b.bh

-- | Pairs of edges whose VERTICAL runs lie on the same x and overlap: two flows
-- drawn as one line, which is a lie about how many there are.
--
-- Horizontal overlap is not checked, because several flows converging on one
-- end event genuinely do meet at its edge — that is what convergence looks
-- like in every BPMN tool. A shared vertical run is different: it is the router
-- putting two independent flows in the same channel.
verticalMerges :: BpmnExport -> [(Text, Text)]
verticalMerges bx =
  [ (a.edgeOf, b.edgeOf)
  | (i, a) <- zip [0 :: Int ..] bx.bxDiagram.diagEdges
  , (j, b) <- zip [0 ..] bx.bxDiagram.diagEdges
  , i < j
  , (p, q) <- segments a
  , (r, w) <- segments b
  , p.ptX == q.ptX
  , r.ptX == w.ptX
  , p.ptX == r.ptX
  , overlapLen (p.ptY, q.ptY) (r.ptY, w.ptY) > 5
  ]
 where
  overlapLen (a1, a2) (c1, c2) = min (max a1 a2) (max c1 c2) - max (min a1 a2) (min c1 c2)

-- | Flows whose target is drawn no further right than their source.
--
-- This is what a cycle costs, stated as arithmetic over the emitted DI rather
-- than as a claim about the layout's internals: the layout ranks a node by its
-- longest path from the start, so on an acyclic graph every flow advances and
-- \"further right\" reliably means \"later\". A back edge cannot advance, and
-- once one node's position is arbitrary so is every position it feeds.
nonAdvancingEdges :: BpmnExport -> [Text]
nonAdvancingEdges bx =
  [ f.flowId
  | f <- bx.bxProcess.procFlows
  , Just s <- [boundsFor f.flowFrom]
  , Just t <- [boundsFor f.flowTo]
  , t.bx <= s.bx
  ]
 where
  boundsFor nid = listToMaybe [b | (n, b) <- flowNodeShapes bx, n == nid]

-- | Ids of every timer boundary event from which a breach terminal is
-- reachable — every place the diagram says \"let the clock run out and you are
-- in breach\".
timersLeadingToBreach :: BpmnExport -> [Text]
timersLeadingToBreach bx =
  [ n.nodeId
  | n <- bx.bxProcess.procNodes
  , Boundary _ (TimerAfter _) <- [n.nodeKind]
  , terminalFrom bx n.nodeId `elem` [ToBreach, ToBoth]
  ]

mentions :: Text -> FidelityNote -> Bool
mentions needle n = Text.isInfixOf needle (n.message <> " " <> n.lost)

-- | A one-obligation graph carrying a given deadline text, built directly
-- rather than parsed. L4 cannot currently spell @WITHIN 30 days@ — the
-- deadline is an expression and comes out as a bare number — but the IR can
-- carry any text, and that is precisely where the duration parser's edge cases
-- live. Testing through a fixture would leave them unreachable.
graphWithDeadline :: Text -> StateGraph
graphWithDeadline due =
  StateGraph
    { sgName = "unit"
    , sgStates =
        [ ContractState 0 "initial" InitialState Linear
        , ContractState 1 "Fulfilled" TerminalFulfilled Linear
        , ContractState 2 "Breach" TerminalBreach Linear
        ]
    , sgTransitions =
        [ Transition 0 1 (TransitionLabel (Just "Alice") (Just DMust) "pay" (Just due) Nothing) HenceTransition
        , Transition 0 2 (TransitionLabel Nothing Nothing "timeout" Nothing Nothing) LestTransition
        ]
    , sgInitialState = 0
    }

triggerFor :: Text -> [BoundaryTrigger]
triggerFor due =
  [ t
  | n <- (stateGraphToBpmn defaultBpmnOptions (graphWithDeadline due)).bxProcess.procNodes
  , Boundary _ t <- [n.nodeKind]
  ]

--------------------------------------------------------------------------------
-- Spec
--------------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "a linear HENCE chain" $ do
    let bx = exportOf defaultBpmnOptions "chain" linearSrc
        xml = renderBpmn bx

    it "draws one task per obligation, one start event, and terminals" $ do
      map (.nodeName) (tasks bx) `shouldBe` ["MUST pay", "MUST deliver"]
      length (nodesWhere (isKind (== StartEvent)) bx) `shouldBe` 1
      length (nodesWhere (isKind \case EndEvent _ -> True; _ -> False) bx)
        `shouldSatisfy` (>= 1)

    it "invents no gateway, because the source has no junction" $ do
      gateways bx `shouldBe` []
      xml `shouldSatisfy` not . Text.isInfixOf "Gateway"

    it "wires the start event into the first task" $
      [f.flowTo | f <- bx.bxProcess.procFlows, f.flowFrom == "Start_0"]
        `shouldBe` ["Task_0"]

  describe "LEST is an interrupting boundary event (the one line that fits)" $ do
    let bx = exportOf defaultBpmnOptions "late" lestSrc
        xml = renderBpmn bx

    -- Two obligations, so two boundary events: the LEST reparation is itself a
    -- MUST and gets its own. Each must hang on ITS OWN task, which is the thing
    -- an off-by-one here would break.
    it "hangs each boundary event on the obligation's own task" $
      map (.nodeKind) (boundaries bx)
        `shouldBe` [ Boundary "Task_0" (TimerAfter "P3D")
                   , Boundary "Task_2" (TimerAfter "P1D")
                   ]

    it "is interrupting, and carries an ISO 8601 duration" $ do
      xml `shouldSatisfy` Text.isInfixOf "cancelActivity=\"true\""
      xml `shouldSatisfy` Text.isInfixOf "attachedToRef=\"Task_0\""
      xml `shouldSatisfy` Text.isInfixOf "<bpmn:timeDuration xsi:type=\"bpmn:tFormalExpression\">P3D</bpmn:timeDuration>"

    it "flows from the boundary event to the LEST continuation, not the HENCE one" $ do
      let outOfBoundary = [f.flowTo | f <- bx.bxProcess.procFlows, f.flowFrom == "Boundary_0"]
          outOfTask = [f.flowTo | f <- bx.bxProcess.procFlows, f.flowFrom == "Task_0"]
      outOfBoundary `shouldSatisfy` all (`notElem` outOfTask)
      -- the LEST continuation is itself an obligation, so it got a task
      map (fmap (.nodeName) . nodeNamed bx) outOfBoundary
        `shouldBe` [Just "MUST notify"]

    it "records the assumed unit for a deadline L4 leaves unit-less" $ do
      let assumed = findingsFor "P-DEADLINE-UNIT" bx
      map (.element) assumed `shouldBe` ["Boundary_0", "Boundary_2"]
      map (.severity) assumed `shouldBe` [Advisory, Advisory]
      -- the raw text and what it was read as both reach the reader
      zipWith mentions ["\8216" <> "3" <> "\8217", "\8216" <> "1" <> "\8217"] assumed
        `shouldBe` [True, True]
      map (mentions "P3D") assumed `shouldBe` [True, False]

    it "refuses the assumption under RefuseToGuess, and says so" $ do
      let strict = exportOf (BpmnOptions {optDeadlineUnit = RefuseToGuess}) "late" lestSrc
      map (.nodeKind) (boundaries strict)
        `shouldBe` [ Boundary "Task_0" (WhenCondition "3")
                   , Boundary "Task_2" (WhenCondition "1")
                   ]
      renderBpmn strict `shouldSatisfy` not . Text.isInfixOf "timeDuration"
      map (.element) (findingsFor "P-DEADLINE" strict)
        `shouldBe` ["Boundary_0", "Boundary_2"]

  describe "RAND and ROR are different gateways (the P0 bug, at the surface)" $ do
    let randBx = exportOf defaultBpmnOptions "split" randSrc
        rorBx = exportOf defaultBpmnOptions "split" rorSrc
        randXml = renderBpmn randBx

    it "RAND is a parallel gateway" $ do
      map (.nodeKind) (gateways randBx)
        `shouldBe` [Gateway ParallelGateway Diverging]
      randXml `shouldSatisfy` Text.isInfixOf "<bpmn:parallelGateway"
      randXml `shouldSatisfy` not . Text.isInfixOf "exclusiveGateway"

    it "ROR is an exclusive gateway" $ do
      map (.nodeKind) (gateways rorBx)
        `shouldBe` [Gateway ExclusiveGateway Diverging]
      renderBpmn rorBx `shouldSatisfy` Text.isInfixOf "<bpmn:exclusiveGateway"
      renderBpmn rorBx `shouldSatisfy` not . Text.isInfixOf "parallelGateway"

    -- The whole point: a test that passed for both would be worthless.
    it "the two documents differ" $
      randXml `shouldNotBe` renderBpmn rorBx

    it "the sources differ in exactly one token" $
      length (filter id (zipWith (/=) randSrc rorSrc)) `shouldBe` 1

    it "does not invent a join when a branch can escape to BREACH" $ do
      map (.nodeKind) (gateways randBx) `shouldBe` [Gateway ParallelGateway Diverging]
      case findingsFor "P-NOJOIN" randBx of
        [f] -> do
          -- the stated reason must be the one that actually applied
          f `shouldSatisfy` mentions "BREACH"
          -- and it must not repeat the false consolation that the conjunction
          -- survives because all tokens get consumed: an error end abandons
          -- its siblings
          f.lost `shouldSatisfy` Text.isInfixOf "abandons"
        other -> expectationFailure ("expected one P-NOJOIN, got " <> show (length other))

    it "does join when every branch delivers exactly one token, one way" $ do
      let joined = exportOf defaultBpmnOptions "both" randJoinSrc
      map (.nodeKind) (gateways joined)
        `shouldBe` [ Gateway ParallelGateway Diverging
                   , Gateway ParallelGateway Converging
                   ]
      findingsFor "P-NOJOIN" joined `shouldBe` []
      -- and the join sits between the branches and the end event
      [f.flowTo | f <- joined.bxProcess.procFlows, f.flowFrom == "Join_0"]
        `shouldSatisfy` all (Text.isPrefixOf "End_")

    -- Reproductions of the three ways a reachability proof draws a deadlock.
    -- Each of these once emitted a converging parallel gateway waiting for more
    -- tokens than can ever arrive, and emitted no fidelity note about it.
    it "declines when a lapse timer gives a branch two exclusive routes" $ do
      let bx = exportOf defaultBpmnOptions "both" randDeadlockSrc
      converging bx `shouldBe` []
      map (.code) (findingsFor "P-NOJOIN" bx) `shouldBe` ["P-NOJOIN"]
      findingsFor "P-NOJOIN" bx `shouldSatisfy` all (mentions "routes")

    it "declines when a ROR inside a branch fires only one of two edges" $ do
      let bx = exportOf defaultBpmnOptions "mixed" rorInRandSrc
      converging bx `shouldBe` []
      findingsFor "P-NOJOIN" bx `shouldSatisfy` ((== 1) . length)

    it "declines when a branch reaches the join by a conditional flow" $ do
      let bx = exportOf defaultBpmnOptions "mixed" guardInRandSrc
      converging bx `shouldBe` []
      findingsFor "P-NOJOIN" bx `shouldSatisfy` all (mentions "conditional")

    it "nested RANDs: the inner one reports a folded join, not a failed one" $ do
      let nested = exportOf defaultBpmnOptions "nested" nestedJoinSrc
      -- whatever it decides, it must never leave an unsound join behind
      unsoundJoins nested `shouldBe` []

  describe "terminals" $ do
    let bx = exportOf defaultBpmnOptions "chain" linearSrc
        xml = renderBpmn bx

    it "a breach terminal is an error end event" $ do
      let breaches = [n | n <- bx.bxProcess.procNodes, n.nodeKind == EndEvent True]
      map (.nodeName) breaches `shouldBe` ["Breach"]
      xml `shouldSatisfy` Text.isInfixOf "<bpmn:errorEventDefinition"
      xml `shouldSatisfy` Text.isInfixOf "<bpmn:error id=\"Error_breach\""

    it "a fulfilled terminal is a plain end event" $
      [n.nodeName | n <- bx.bxProcess.procNodes, n.nodeKind == EndEvent False]
        `shouldBe` ["Fulfilled"]

  describe "lanes" $ do
    let bx = exportOf defaultBpmnOptions "chain" linearSrc

    it "gives each party a lane, in source order, plus one for the unassigned" $
      map (.laneName) bx.bxProcess.procLanes
        `shouldBe` ["Alice", "Bob", "(unassigned)"]

    it "puts each obligation's task in its bearer's lane" $ do
      let laneOf nm = [l.laneNodes | l <- bx.bxProcess.procLanes, l.laneName == nm]
      laneOf "Alice" `shouldBe` [["Task_0", "Boundary_0"]]
      laneOf "Bob" `shouldBe` [["Task_1", "Boundary_1"]]

    it "drops nobody: events with no party land in the default lane" $ do
      let assigned = concatMap (.laneNodes) bx.bxProcess.procLanes
      sort assigned `shouldBe` sort (map (.nodeId) bx.bxProcess.procNodes)

    it "wraps the lanes in exactly one pool" $ do
      fmap (.participantId) bx.bxCollaboration `shouldBe` Just "Participant_chain"
      length (Text.breakOnAll "<bpmn:participant" (renderBpmn bx)) `shouldBe` 1

  describe "a deadline that is not a duration" $ do
    let bx = exportOf defaultBpmnOptions "deferred" opaqueDeadlineSrc
        xml = renderBpmn bx

    it "emits no timer and no invented duration" $ do
      xml `shouldSatisfy` not . Text.isInfixOf "timerEventDefinition"
      xml `shouldSatisfy` not . Text.isInfixOf "timeDuration"

    it "keeps the raw text as a condition instead" $
      map (.nodeKind) (boundaries bx)
        `shouldBe` [Boundary "Task_0" (WhenCondition "grace")]

    it "names the offending deadline in the fidelity report, loudly" $
      case findingsFor "P-DEADLINE" bx of
        [f] -> do
          f `shouldSatisfy` mentions "\8216grace\8217"
          f.severity `shouldBe` Blocking
          f.element `shouldBe` "Boundary_0"
        other -> expectationFailure ("expected one P-DEADLINE note, got " <> show (length other))

  -- An interrupting boundary event is a race between "the activity completed"
  -- and "the trigger fired". For a prohibition the L4 runtime races them the
  -- other way round from every other modal (Machine.hs: deadline expiry =>
  -- "Prohibition was RESPECTED" => HENCE; act performed => "Prohibition
  -- violated" => LEST), and this exporter originally wired it the obvious way,
  -- drawing "wait 30 days and you are in breach" for a rule that says the
  -- opposite.
  --
  -- Every assertion here is about where a path GOES, never about what shapes
  -- exist. The broken version had the right shapes.
  describe "a prohibition races its two arms the other way round" $ do
    let shant = exportOf defaultBpmnOptions "rule" shantSrc
        must = exportOf defaultBpmnOptions "rule" mustSrc

    it "SHANT: performing the act breaches; the deadline passing fulfils" $
      raceOutcome shant `shouldBe` (ToBreach, ToFulfilled)

    -- The control. Without it, an exporter that emitted no timers at all, or
    -- wired both arms to Fulfilled, would satisfy every SHANT assertion above.
    -- Do not delete this as redundant: it is the reason the others mean
    -- anything.
    it "MUST: the mirror image, and it must be the mirror image" $
      raceOutcome must `shouldBe` (ToFulfilled, ToBreach)

    it "no timer leads to breach under a prohibition; under MUST one does" $ do
      timersLeadingToBreach shant `shouldBe` []
      timersLeadingToBreach must `shouldSatisfy` ((== 1) . length)

    it "the sources differ in exactly one token" $
      length (filter id (zipWith (/=) shantSrc mustSrc)) `shouldBe` 1

    -- The WITHIN is drawn, not confessed: BPMN expresses this race natively,
    -- so there is nothing to lose and nothing to report.
    it "keeps the deadline as a real timer rather than dropping it" $ do
      map (.nodeKind) (boundaries shant)
        `shouldBe` [Boundary "Task_0" (TimerAfter "P30D")]
      renderBpmn shant `shouldSatisfy` Text.isInfixOf "<bpmn:timeDuration"

    it "files no fidelity note for a race the notation can express" $
      findingsFor "P-PROHIBITION" shant `shouldBe` []

    it "says on the elements which arm is which, since the shapes cannot" $ do
      map (.nodeDoc) (boundaries shant)
        `shouldSatisfy` all (maybe False (Text.isInfixOf "prohibition is respected"))
      map (.nodeDoc) (tasks shant)
        `shouldSatisfy` all (maybe False (Text.isInfixOf "LEST arm"))

    -- <documentation> is not what a reader sees. The boundary's NAME is drawn
    -- on the diagram, and it used to be whatever the extractor put on the LEST
    -- edge — the bare word "timeout", or "violation" where a SHANT defaulted
    -- its own LEST. On the arm that means the prohibition was RESPECTED, both
    -- of those are false, and no amount of correct wiring underneath fixes a
    -- label that says the opposite of what the arm means.
    --
    -- The opaque-deadline pair is what pins this: with a parseable WITHIN the
    -- name is "after P30D" and the leak never shows.
    describe "and the label a reader actually sees says so too" $ do
      let shantO = exportOf defaultBpmnOptions "rule" shantOpaqueSrc
          mustO = exportOf defaultBpmnOptions "rule" mustOpaqueSrc

      it "never calls the compliance arm a timeout or a violation" $ do
        map (.nodeName) (boundaries shantO)
          `shouldSatisfy` all
            (\n -> not (Text.isInfixOf "timeout" n) && not (Text.isInfixOf "violation" n))
        map (.nodeName) (boundaries shantO)
          `shouldSatisfy` all (Text.isInfixOf "not performed")
        map (.nodeName) (boundaries shant)
          `shouldSatisfy` all (Text.isInfixOf "not performed")

      -- The control, and it is the whole of the evidence: MUST must KEEP the
      -- word. Suppressing "timeout" everywhere would pass the assertion above
      -- while destroying the one place the label is true.
      it "but an obligation keeps it, because for an obligation it is true" $
        map (.nodeName) (boundaries mustO) `shouldBe` ["timeout"]

      it "and the arms are still raced the right way round without a timer" $ do
        raceOutcome shantO `shouldBe` (ToBreach, ToFulfilled)
        raceOutcome mustO `shouldBe` (ToFulfilled, ToBreach)

  describe "a permission that lapses" $ do
    let bx = exportOf defaultBpmnOptions "optional" mayNoLestSrc

    -- Machine.hs routes expiry of an unexercised MAY to FULFILLED, so the
    -- timer has a knowable destination and the deadline can be DRAWN rather
    -- than confessed. This used to emit nothing at all: four real deadlines
    -- vanished from handover.bpmn without a word.
    it "draws the deadline as a timer instead of dropping it" $ do
      map (.nodeKind) (boundaries bx)
        `shouldBe` [Boundary "Task_0" (TimerAfter "P30D")]
      renderBpmn bx `shouldSatisfy` Text.isInfixOf "<bpmn:timeDuration"

    it "sends the lapse where HENCE goes, not to breach" $
      raceOutcome bx `shouldBe` (ToFulfilled, ToFulfilled)

    it "files no undrawn-deadline note, because nothing was undrawn" $
      findingsFor "P-DEADLINE-UNDRAWN" bx `shouldBe` []

    -- F5 used to say "every threshold and deadline drawn here", which asserts
    -- that they all were. When four of them were not, that made F5 itself a
    -- false statement.
    it "and F5 no longer implies every deadline made it into the diagram" $
      map (.message) (findingsFor "F5" bx)
        `shouldSatisfy` all (\m -> Text.isInfixOf "does appear" m && not (Text.isInfixOf "every threshold and deadline drawn" m))

  describe "a PROVIDED guard" $ do
    let bx = exportOf defaultBpmnOptions "guarded" guardSrc
        xml = renderBpmn bx
        conditions = [c | f <- bx.bxProcess.procFlows, Just c <- [f.flowCondition]]

    it "rides on the task's normal outgoing flow, and only that one" $ do
      [(f.flowFrom, f.flowCondition) | f <- bx.bxProcess.procFlows, isJust f.flowCondition]
        `shouldBe` [("Task_0", listToMaybe conditions)]
      length conditions `shouldBe` 1

    it "is emitted as a formal expression" $ do
      xml `shouldSatisfy` Text.isInfixOf "<bpmn:conditionExpression xsi:type=\"bpmn:tFormalExpression\">"
      -- whatever prettyLayout gave us, both operands survive into the XML
      xml `shouldSatisfy` Text.isInfixOf "amt"
      xml `shouldSatisfy` Text.isInfixOf "100"

    it "reports the guard body as opaque (F4) and the vacuity it creates (F3)" $ do
      map (.element) (findingsFor "F4" bx) `shouldBe` ["Task_0"]
      map (.element) (findingsFor "F3" bx) `shouldBe` ["Task_0"]
      map (.severity) (findingsFor "F4" bx) `shouldBe` [Lossy]
      map (.severity) (findingsFor "F3" bx) `shouldBe` [Blocking]

    it "reports neither for an unguarded obligation" $ do
      let plain = exportOf defaultBpmnOptions "chain" linearSrc
      findingsFor "F4" plain `shouldBe` []
      findingsFor "F3" plain `shouldBe` []

  describe "reading a deadline as an ISO 8601 duration" $ do
    let cases =
          [ ("30 days", TimerAfter "P30D")
          , ("1 day", TimerAfter "P1D")
          , ("2 weeks", TimerAfter "P2W")
          , ("6 months", TimerAfter "P6M")
          , ("1 year", TimerAfter "P1Y")
          , ("3 hours", TimerAfter "PT3H")
          , ("45 minutes", TimerAfter "PT45M")
          , -- already a duration: passed through untouched
            ("P30D", TimerAfter "P30D")
          , ("PT2H30M", TimerAfter "PT2H30M")
          , -- a bare number, under the default AssumeDays policy
            ("30", TimerAfter "P30D")
          , -- and everything we will not invent a duration for
            ("P30", WhenCondition "P30")
          , ("later", WhenCondition "later")
          , ("30 fortnights", WhenCondition "30 fortnights")
          , ("1.5 days", WhenCondition "1.5 days")
          , ("`grace period`", WhenCondition "`grace period`")
          ]
    forM_ cases \(due, expected) ->
      it (Text.unpack (due <> " → " <> Text.pack (show expected))) $
        triggerFor due `shouldBe` [expected]

  describe "the fidelity report" $ do
    let bx = exportOf defaultBpmnOptions "chain" linearSrc

    it "reports the modality loss once per task, as blocking" $ do
      map (.element) (findingsFor "F1" bx) `shouldBe` ["Task_0", "Task_1"]
      map (.severity) (findingsFor "F1" bx) `shouldBe` [Blocking, Blocking]

    it "is loud about a prohibition, which is not a task at all" $ do
      let shant =
            exportOf
              defaultBpmnOptions
              "quiet"
              [ "`quiet` MEANS"
              , "  PARTY Alice"
              , "  SHANT notify"
              , "  WITHIN 3"
              ]
      -- every F1 is Blocking, so severity cannot be what marks a prohibition
      -- out; the note has to say it in words
      findingsFor "F1" shant `shouldSatisfy` all (mentions "forbids")
      map (.nodeName) (tasks shant) `shouldBe` ["SHANT notify"]

    it "reports the notation-level losses that no amount of Haskell can fix" $ do
      map (.element) (findingsFor "F2" bx) `shouldBe` ["Process_chain"]
      map (.element) (findingsFor "F5" bx) `shouldBe` ["Process_chain"]
      map (.severity) (findingsFor "F2" bx) `shouldBe` [Lossy]
      map (.severity) (findingsFor "F5" bx) `shouldBe` [Advisory]

    it "renders to something a human can read" $ do
      let report = renderReport bx.bxFidelity
      report `shouldSatisfy` Text.isInfixOf "fidelity report — BPMN 2.0"
      report `shouldSatisfy` Text.isInfixOf "[F1] blocking — Task_0"
      report `shouldSatisfy` Text.isInfixOf "[F5] advisory — Process_chain"
      report `shouldSatisfy` Text.isInfixOf "      lost: "

  -- Three shapes the StateGraph types permit and today's extractor never
  -- builds. Each is detected and named, and none is drawn, because there is no
  -- honest shape to draw instead.
  --
  -- Every assertion below pairs the note with the DEFECT IN THE EMITTED
  -- DIAGRAM that motivates it, and pairs that with a control graph differing in
  -- one edge. Asserting only "the note is present" would pass for an exporter
  -- that filed all three notes unconditionally, which is a different way of
  -- being useless.
  describe "shapes the types permit but nothing can draw" $ do
    describe "several HENCE arms from one state" $ do
      let bx = stateGraphToBpmn defaultBpmnOptions multiHenceGraph
          control = stateGraphToBpmn defaultBpmnOptions oneHenceGraph
          outOfTask e = [f | f <- e.bxProcess.procFlows, f.flowFrom == "Task_0"]

      -- This is the AllOf/OneOf confusion the whole track exists to fix,
      -- one level down: BPMN's implicit AND-split is what you get by drawing
      -- nothing, so the choice reads as a conjunction with no gateway to blame.
      it "leaves the task with two unconditional outgoing flows, which BPMN reads as AND" $ do
        map (.flowCondition) (outOfTask bx) `shouldBe` [Nothing, Nothing]
        map (.flowTo) (outOfTask bx) `shouldSatisfy` ((== 2) . length)

      it "and says so, at blocking, naming the task" $ do
        map (.severity) (findingsFor "P-MULTI-HENCE" bx) `shouldBe` [Blocking]
        map (.element) (findingsFor "P-MULTI-HENCE" bx) `shouldBe` ["Task_0"]
        findingsFor "P-MULTI-HENCE" bx `shouldSatisfy` all (mentions "parallel split")

      it "the control: one HENCE, one flow, no note" $ do
        map (.flowCondition) (outOfTask control) `shouldBe` [Nothing]
        findingsFor "P-MULTI-HENCE" control `shouldBe` []

    describe "a junction that is also an obligation" $ do
      let bx = stateGraphToBpmn defaultBpmnOptions junctionObligationGraph
          control = stateGraphToBpmn defaultBpmnOptions plainJunctionGraph
          outOfSplit e = [f.flowTo | f <- e.bxProcess.procFlows, f.flowFrom == "Split_0"]

      -- The gateway ends up with one arm more than the junction has branches,
      -- and the extra one is the obligation: under "all of" the duty is drawn
      -- as a third concurrent branch rather than as the thing that governs the
      -- other two.
      it "hangs the task off the gateway as one more branch" $ do
        outOfSplit bx `shouldSatisfy` elem "Task_0"
        length (outOfSplit bx) `shouldBe` 3

      it "and says so, at blocking, naming the gateway" $ do
        map (.severity) (findingsFor "P-JUNCTION-OBLIGATION" bx) `shouldBe` [Blocking]
        map (.element) (findingsFor "P-JUNCTION-OBLIGATION" bx) `shouldBe` ["Split_0"]

      it "the control: the same junction with no duty on it has two arms, no note" $ do
        length (outOfSplit control) `shouldBe` 2
        outOfSplit control `shouldSatisfy` all (Text.isPrefixOf "Task_")
        findingsFor "P-JUNCTION-OBLIGATION" control `shouldBe` []

    describe "a cycle" $ do
      let bx = stateGraphToBpmn defaultBpmnOptions cyclicGraph
          control = stateGraphToBpmn defaultBpmnOptions acyclicGraph

      -- Not "a cycle exists" — what a cycle COSTS. The layout ranks by longest
      -- path from the start, which a node on a cycle does not have, so the
      -- horizontal axis stops ordering the diagram in time. Measured off the
      -- emitted DI, not off the layout's internals.
      it "breaks the left-to-right reading, which is what the note is about" $
        nonAdvancingEdges bx `shouldNotBe` []

      it "and says so, at lossy, naming the states in the loop" $ do
        map (.severity) (findingsFor "P-CYCLE" bx) `shouldBe` [Lossy]
        findingsFor "P-CYCLE" bx `shouldSatisfy` all (mentions "review")
        findingsFor "P-CYCLE" bx `shouldSatisfy` all (mentions "revise")

      it "the control: remove the back edge and every flow advances again" $ do
        nonAdvancingEdges control `shouldBe` []
        findingsFor "P-CYCLE" control `shouldBe` []

    -- And the fixtures a real L4 source produces must trip none of the three,
    -- or the notes would be noise that a reader learns to skip.
    it "no real fixture trips any of them" $
      [ (nm, n.code)
      | (nm, body) <- fixtures
      , n <- (exportOf defaultBpmnOptions nm body).bxFidelity.notes
      , n.code `elem` ["P-MULTI-HENCE", "P-JUNCTION-OBLIGATION", "P-CYCLE"]
      ]
        `shouldBe` []

  describe "well-formedness (structural, over every fixture)" $
    forM_ fixtures \(nm, body) -> describe (Text.unpack nm) do
      let bx = exportOf defaultBpmnOptions nm body
          nodeIds = Set.fromList (map (.nodeId) bx.bxProcess.procNodes)

      it "every sequence flow joins two nodes that exist" $
        [ (f.flowId, f.flowFrom, f.flowTo)
        | f <- bx.bxProcess.procFlows
        , not (Set.member f.flowFrom nodeIds && Set.member f.flowTo nodeIds)
        ]
          `shouldBe` []

      it "every boundary event is attached to a node that exists" $
        [ n.nodeId
        | n <- bx.bxProcess.procNodes
        , Boundary host _ <- [n.nodeKind]
        , not (Set.member host nodeIds)
        ]
          `shouldBe` []

      it "every flow node has diagram geometry" $ do
        let shaped = Set.fromList [s.shapeOf | s <- bx.bxDiagram.diagShapes]
        filter (not . (`Set.member` shaped)) (map (.nodeId) bx.bxProcess.procNodes)
          `shouldBe` []

      it "every sequence flow has an edge with at least two waypoints" $ do
        let routed = [(e.edgeOf, length e.edgeWaypoints) | e <- bx.bxDiagram.diagEdges]
        sort (map fst routed) `shouldBe` sort (map (.flowId) bx.bxProcess.procFlows)
        filter ((< 2) . snd) routed `shouldBe` []

      -- A gateway with no incoming flow is the shape a careless join insertion
      -- produces, and it is invisible to a "does it parse" check.
      it "every gateway has both an incoming and an outgoing flow" $ do
        let ins nid = [f | f <- bx.bxProcess.procFlows, f.flowTo == nid]
            outs nid = [f | f <- bx.bxProcess.procFlows, f.flowFrom == nid]
        [ n.nodeId
          | n <- bx.bxProcess.procNodes
          , Gateway _ _ <- [n.nodeKind]
          , null (ins n.nodeId) || null (outs n.nodeId)
          ]
          `shouldBe` []

      -- The property, not the shape: a converging parallel gateway must be
      -- able to receive a token on every incoming flow, or the instance hangs.
      -- Counting gateways would pass on every deadlock this ever emitted.
      it "no converging parallel gateway can deadlock" $
        unsoundJoins bx `shouldBe` []

      it "no edge is drawn through a node" $
        crossings bx `shouldBe` []

      it "no two edges share a vertical channel" $
        verticalMerges bx `shouldBe` []

      it "every id is unique" $ do
        let ids =
              map (.nodeId) bx.bxProcess.procNodes
                <> map (.flowId) bx.bxProcess.procFlows
                <> map (.laneId) bx.bxProcess.procLanes
        length (nubOrd ids) `shouldBe` length ids

      it "lowering twice is byte-identical" $
        xmlOf nm body `shouldBe` xmlOf nm body

  -- The XML and the report are separate files on purpose: the .bpmn has to
  -- stay a file you can hand to Camunda Modeler (and to
  -- `etc/validate-bpmn.mjs`) without editing anything out of it first.
  describe "golden" $ forM_ goldenCases \(stem, ruleName) -> do
    it (stem <> " lowers to stable XML") $
      goldenCase stem ruleName ".bpmn" \_ bx -> renderBpmn bx

    it (stem <> " lowers to a stable fidelity report") $
      goldenCase stem ruleName ".fidelity.txt" \_ bx ->
        renderReport bx.bxFidelity
 where
  goldenCases =
    [ ("offering", "the offering")
    , ("handover", "the handover")
    ]

  goldenCase stem ruleName ext render = do
    dataDir <- Paths_jl4.getDataDir
    let root = dataDir </> "examples" </> "bpmn"
    src <- Text.readFile (root </> stem <> ".l4")
    let sg = case [g | g <- graphsOf src, g.sgName == ruleName] of
          (g : _) -> g
          [] -> error (stem <> ".l4: no state graph named " <> show ruleName)
        bx = stateGraphToBpmn defaultBpmnOptions sg
    pure
      Golden
        { output = render sg bx
        , encodePretty = Text.unpack
        , writeToFile = Text.writeFile
        , readFromFile = Text.readFile
        , goldenFile = root </> "expected" </> (stem <> ext)
        , actualFile = Just (root </> "expected" </> (stem <> ext <> ".actual"))
        , failFirstTime = True
        }

  graphsOf src = case checkWithImports emptyVFS src of
    Left errs -> error ("fixture failed to typecheck: " <> show errs)
    Right r -> extractStateGraphs r.tcdModule

  fixtures =
    [ ("chain" :: Text, linearSrc)
    , ("late", lestSrc)
    , ("split", randSrc)
    , ("both", randJoinSrc)
    , ("nested", nestedJoinSrc)
    , ("guarded", guardSrc)
    , ("rule", shantSrc)
    , ("optional", mayNoLestSrc)
    , ("both", randDeadlockSrc)
    , ("mixed", rorInRandSrc)
    , ("deferred", opaqueDeadlineSrc)
    , ("rule", shantOpaqueSrc)
    ]
