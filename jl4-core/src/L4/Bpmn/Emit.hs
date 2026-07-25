-- | Render a 'BpmnExport' to BPMN 2.0 XML.
--
-- Hand-rolled over 'Text' rather than built on an XML library: the document
-- shape is fixed and small, the emitted bytes have to be golden-stable, and
-- @jl4-core@ builds with @-Wunused-packages@, so a dependency earning its place
-- would have to do more than this does. The one thing a hand-rolled emitter
-- must get right is escaping, which 'xmlEscape' does for both attribute values
-- and element content.
--
-- Two choices worth stating, because they are not forced by the IR:
--
-- * @isExecutable=\"false\"@. This is a description of a rule, not a deployable
--   workflow. Saying so keeps Camunda from applying executable-process
--   validations to a diagram that was never going to be executed.
-- * The @\<BPMNDiagram\>@ is not optional. A BPMN file without diagram
--   interchange opens as an empty canvas, and the point of this exporter is that
--   someone can open the result in Camunda Modeler.
module L4.Bpmn.Emit
  ( renderBpmn
  ) where

import Base
import qualified Base.Text as Text

import L4.Bpmn.IR

-- | The whole document, newline-terminated.
renderBpmn :: BpmnExport -> Text
renderBpmn bx =
  Text.unlines $
    ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>"]
      <> definitionsOpen bx
      <> errorDecl bx
      <> collaborationLines bx
      <> processLines bx
      <> diagramLines bx
      <> ["</bpmn:definitions>"]

--------------------------------------------------------------------------------
-- Document scaffolding
--------------------------------------------------------------------------------

sharedErrorId :: Text
sharedErrorId = "Error_breach"

definitionsOpen :: BpmnExport -> [Text]
definitionsOpen bx =
  [ "<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\""
  , "                  xmlns:bpmndi=\"http://www.omg.org/spec/BPMN/20100524/DI\""
  , "                  xmlns:dc=\"http://www.omg.org/spec/DD/20100524/DC\""
  , "                  xmlns:di=\"http://www.omg.org/spec/DD/20100524/DI\""
  , "                  xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\""
  , "                  id=\"" <> xmlEscape bx.bxDefinitionsId <> "\""
  , "                  targetNamespace=\"https://l4.legalese.com/bpmn\""
  , "                  exporter=\"jl4 (L4.Bpmn)\""
  , "                  exporterVersion=\"1\">"
  ]

-- | One shared @\<error\>@ for every breach terminal. BPMN would let each end
-- event carry an anonymous error; naming it once means Camunda Modeler shows
-- \"Breach\" on the shape instead of nothing.
errorDecl :: BpmnExport -> [Text]
errorDecl bx
  | bx.bxHasError =
      [ selfClose
          1
          "bpmn:error"
          [("id", sharedErrorId), ("name", "Breach"), ("errorCode", "BREACH")]
      ]
  | otherwise = []

collaborationLines :: BpmnExport -> [Text]
collaborationLines bx = case bx.bxCollaboration of
  Nothing -> []
  Just c ->
    [ openTag 1 "bpmn:collaboration" [("id", c.collabId)]
    , selfClose
        2
        "bpmn:participant"
        [ ("id", c.participantId)
        , ("name", c.participantName)
        , ("processRef", bx.bxProcess.procId)
        ]
    , closeTag 1 "bpmn:collaboration"
    ]

--------------------------------------------------------------------------------
-- Process
--------------------------------------------------------------------------------

processLines :: BpmnExport -> [Text]
processLines bx =
  [ openTag
      1
      "bpmn:process"
      [ ("id", p.procId)
      , ("name", p.procName)
      , ("isExecutable", "false")
      ]
  ]
    <> laneSetLines p
    <> concatMap (nodeLines 2) p.procNodes
    <> concatMap (flowLines 2) p.procFlows
    <> [closeTag 1 "bpmn:process"]
 where
  p = bx.bxProcess

laneSetLines :: BpmnProcess -> [Text]
laneSetLines p
  | null p.procLanes = []
  | otherwise =
      [openTag 2 "bpmn:laneSet" [("id", "LaneSet_1")]]
        <> concatMap laneLines p.procLanes
        <> [closeTag 2 "bpmn:laneSet"]
 where
  laneLines lane =
    [openTag 3 "bpmn:lane" [("id", lane.laneId), ("name", lane.laneName)]]
      <> [textEl 4 "bpmn:flowNodeRef" [] nid | nid <- lane.laneNodes]
      <> [closeTag 3 "bpmn:lane"]

nodeLines :: Int -> FlowNode -> [Text]
nodeLines depth node = case node.nodeKind of
  StartEvent -> element "bpmn:startEvent" [] []
  EndEvent isError ->
    element
      "bpmn:endEvent"
      []
      [ selfClose
          (depth + 1)
          "bpmn:errorEventDefinition"
          [("id", "ErrorDef_" <> node.nodeId), ("errorRef", sharedErrorId)]
      | isError
      ]
  Task -> element "bpmn:task" [] []
  Gateway kind flow ->
    element (gatewayTag kind) [("gatewayDirection", flowDirection flow)] []
  Boundary host trigger ->
    element
      "bpmn:boundaryEvent"
      [("attachedToRef", host), ("cancelActivity", "true")]
      (triggerLines (depth + 1) node.nodeId trigger)
 where
  element tag extra children =
    let as = [("id", node.nodeId)] <> nameAttr <> extra
        body = docLines (depth + 1) node.nodeDoc <> children
     in if null body
          then [selfClose depth tag as]
          else [openTag depth tag as] <> body <> [closeTag depth tag]
  nameAttr = [("name", node.nodeName) | not (Text.null node.nodeName)]

gatewayTag :: GatewayKind -> Text
gatewayTag = \case
  ExclusiveGateway -> "bpmn:exclusiveGateway"
  ParallelGateway -> "bpmn:parallelGateway"

flowDirection :: GatewayFlow -> Text
flowDirection = \case
  Diverging -> "Diverging"
  Converging -> "Converging"

triggerLines :: Int -> Text -> BoundaryTrigger -> [Text]
triggerLines depth nid = \case
  TimerAfter iso ->
    [ openTag depth "bpmn:timerEventDefinition" [("id", "Timer_" <> nid)]
    , textEl (depth + 1) "bpmn:timeDuration" [("xsi:type", "bpmn:tFormalExpression")] iso
    , closeTag depth "bpmn:timerEventDefinition"
    ]
  WhenCondition cond ->
    [ openTag depth "bpmn:conditionalEventDefinition" [("id", "Cond_" <> nid)]
    , textEl (depth + 1) "bpmn:condition" [("xsi:type", "bpmn:tFormalExpression")] cond
    , closeTag depth "bpmn:conditionalEventDefinition"
    ]

docLines :: Int -> Maybe Text -> [Text]
docLines depth = \case
  Nothing -> []
  Just d | Text.null (Text.strip d) -> []
  Just d -> [textEl depth "bpmn:documentation" [] d]

flowLines :: Int -> SequenceFlow -> [Text]
flowLines depth f = case f.flowCondition of
  Nothing -> [selfClose depth "bpmn:sequenceFlow" as]
  Just cond ->
    [ openTag depth "bpmn:sequenceFlow" as
    , textEl (depth + 1) "bpmn:conditionExpression" [("xsi:type", "bpmn:tFormalExpression")] cond
    , closeTag depth "bpmn:sequenceFlow"
    ]
 where
  as =
    [("id", f.flowId)]
      <> [("name", f.flowName) | not (Text.null f.flowName)]
      <> [("sourceRef", f.flowFrom), ("targetRef", f.flowTo)]

--------------------------------------------------------------------------------
-- Diagram interchange
--------------------------------------------------------------------------------

diagramLines :: BpmnExport -> [Text]
diagramLines bx =
  [ openTag 1 "bpmndi:BPMNDiagram" [("id", "BPMNDiagram_1")]
  , openTag 2 "bpmndi:BPMNPlane" [("id", "BPMNPlane_1"), ("bpmnElement", d.diagPlaneOf)]
  ]
    <> concatMap shapeLines d.diagShapes
    <> concatMap edgeLines d.diagEdges
    <> [ closeTag 2 "bpmndi:BPMNPlane"
       , closeTag 1 "bpmndi:BPMNDiagram"
       ]
 where
  d = bx.bxDiagram

  shapeLines s =
    [ openTag 3 "bpmndi:BPMNShape" ([("id", s.shapeId), ("bpmnElement", s.shapeOf)] <> horizontal s.shapeKind)
    , boundsLine 4 s.shapeBounds
    , closeTag 3 "bpmndi:BPMNShape"
    ]

  horizontal = \case
    PlainShape -> []
    PoolShape -> [("isHorizontal", "true")]
    LaneShape -> [("isHorizontal", "true")]

  edgeLines e =
    [openTag 3 "bpmndi:BPMNEdge" [("id", e.edgeId), ("bpmnElement", e.edgeOf)]]
      <> [ selfClose 4 "di:waypoint" [("x", num p.ptX), ("y", num p.ptY)]
         | p <- e.edgeWaypoints
         ]
      <> [closeTag 3 "bpmndi:BPMNEdge"]

boundsLine :: Int -> Bounds -> Text
boundsLine depth b =
  selfClose
    depth
    "dc:Bounds"
    [("x", num b.bx), ("y", num b.by), ("width", num b.bw), ("height", num b.bh)]

num :: Int -> Text
num = Text.pack . show

--------------------------------------------------------------------------------
-- XML primitives
--------------------------------------------------------------------------------

indent :: Int -> Text
indent depth = Text.replicate (depth * 2) " "

attrList :: [(Text, Text)] -> Text
attrList = foldMap (\(k, v) -> " " <> k <> "=\"" <> xmlEscape v <> "\"")

selfClose :: Int -> Text -> [(Text, Text)] -> Text
selfClose depth name as = indent depth <> "<" <> name <> attrList as <> " />"

openTag :: Int -> Text -> [(Text, Text)] -> Text
openTag depth name as = indent depth <> "<" <> name <> attrList as <> ">"

closeTag :: Int -> Text -> Text
closeTag depth name = indent depth <> "</" <> name <> ">"

textEl :: Int -> Text -> [(Text, Text)] -> Text -> Text
textEl depth name as body =
  indent depth <> "<" <> name <> attrList as <> ">" <> xmlEscape body <> "</" <> name <> ">"

-- | Escape for both attribute values and element content.
--
-- Attribute-only escapes (@\"@, @'@) are applied everywhere, which is
-- permitted and keeps one function honest instead of two nearly-identical ones.
-- Newlines and tabs become character references so that a multi-line label —
-- and pretty-printed L4 expressions are routinely multi-line — survives inside
-- an attribute, where a literal newline would be normalised to a space by any
-- conforming parser. The remaining C0 controls cannot be represented in XML 1.0
-- at all, by any escape, so they are dropped.
xmlEscape :: Text -> Text
xmlEscape = Text.concatMap esc
 where
  esc = \case
    '&' -> "&amp;"
    '<' -> "&lt;"
    '>' -> "&gt;"
    '"' -> "&quot;"
    '\'' -> "&apos;"
    '\n' -> "&#10;"
    '\r' -> "&#13;"
    '\t' -> "&#9;"
    c
      | c < ' ' -> ""
      | c == '\xFFFE' || c == '\xFFFF' -> ""
      | otherwise -> Text.singleton c
