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

-- | Both branches are permissions, so neither can reach BREACH and the only
-- state either can end at is FULFILLED. That is the one shape for which a
-- converging parallel gateway is safe.
randJoinSrc :: [Text]
randJoinSrc =
  [ "`both` MEANS"
  , "      (PARTY Alice MAY pay WITHIN 3)"
  , "  RAND (PARTY Bob MAY deliver WITHIN 5)"
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
      length (findingsFor "P-NOJOIN" randBx) `shouldBe` 1

    it "does join when every branch provably ends at the same state" $ do
      let joined = exportOf defaultBpmnOptions "both" randJoinSrc
      map (.nodeKind) (gateways joined)
        `shouldBe` [ Gateway ParallelGateway Diverging
                   , Gateway ParallelGateway Converging
                   ]
      findingsFor "P-NOJOIN" joined `shouldBe` []
      -- and the join sits between the branches and the end event
      [f.flowTo | f <- joined.bxProcess.procFlows, f.flowFrom == "Join_0"]
        `shouldSatisfy` all (Text.isPrefixOf "End_")

    it "joins nested RANDs once, at the outer gateway, not twice" $ do
      let nested = exportOf defaultBpmnOptions "nested" nestedJoinSrc
          converging = [n.nodeId | n <- nested.bxProcess.procNodes, isConverging n]
          isConverging n = case n.nodeKind of
            Gateway _ Converging -> True
            _ -> False
      converging `shouldBe` ["Join_0"]
      -- all three permissions flow into that one join
      length [f | f <- nested.bxProcess.procFlows, f.flowTo == "Join_0"] `shouldBe` 3
      -- and the inner RAND says why it did not get one of its own
      map (.element) (findingsFor "P-NOJOIN" nested)
        `shouldSatisfy` \els -> length els == 1 && all (Text.isPrefixOf "Split_") els

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
    , ("deferred", opaqueDeadlineSrc)
    ]
