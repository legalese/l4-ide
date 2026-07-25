-- | Target intermediate representation for the BPMN 2.0 backend.
--
-- A BPMN process is a set of /flow nodes/ (events, activities, gateways) joined
-- by /sequence flows/, optionally partitioned into /lanes/, and — separately —
-- a /diagram/ that says where each of those things is drawn. The two halves are
-- independent in BPMN and they are independent here: 'BpmnProcess' is the
-- semantics, 'Diagram' is the picture, and nothing in the first refers to the
-- second.
--
-- The IR is deliberately small: 'L4.Bpmn.Lower' produces it from an
-- 'L4.StateGraph.StateGraph', and 'L4.Bpmn.Emit' renders it to BPMN 2.0 XML.
--
-- == On the fidelity report
--
-- Lowering a regulative rule to BPMN loses information, and the losses are
-- properties of the /target notation/, not defects of this exporter. BPMN has
-- no way to say that skipping this activity is a breach while skipping that one
-- is permitted; it has no as-of date; it cannot distinguish an obligation that
-- never became applicable from one that was discharged. Naming those losses is
-- therefore a feature of the exporter rather than an apology for it, which is
-- why they are first-class values ('Fidelity') carried alongside the XML rather
-- than warnings printed and forgotten.
--
-- Codes @F1@–@F5@ are the notation losses enumerated in
-- @specs\/todo\/lexipedia-superset\/PROCESS-TRACK.md@ §5. Codes @X1@–@X4@ are a
-- different animal: they are places where /this exporter/ had to approximate,
-- and are kept in a separate numbering so the two are never confused.
module L4.Bpmn.IR
  ( -- * The export
    BpmnExport (..)
  , Collaboration (..)
  , BpmnProcess (..)
  , BpmnLane (..)

    -- * Flow nodes and sequence flows
  , FlowNode (..)
  , NodeKind (..)
  , GatewayKind (..)
  , GatewayFlow (..)
  , BoundaryTrigger (..)
  , SequenceFlow (..)
  , nodeWidth
  , nodeHeight

    -- * Diagram interchange
  , Diagram (..)
  , Shape (..)
  , ShapeKind (..)
  , EdgeGeom (..)
  , Bounds (..)
  , Point (..)

    -- * The fidelity report
  , Fidelity (..)
  , FidelityCode (..)
  , FidelitySeverity (..)
  , fidelityTag
  , fidelityTitle
  , renderFidelityReport

    -- * Options
  , BpmnOptions (..)
  , defaultBpmnOptions
  , DeadlineUnitPolicy (..)
  ) where

import Base
import qualified Base.Text as Text

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

-- | What to do with a deadline that carries no unit.
--
-- L4 spells a deadline as a bare quantity — @WITHIN 30@ — and the language does
-- not fix the unit: the evaluator only ever adds it to an event timestamp
-- (@L4.EvaluateLazy.Machine@, @deadline = time' + due'@). BPMN's
-- @\<timeDuration\>@, by contrast, wants an ISO 8601 duration, which cannot be
-- written without a unit. Something has to give, so the choice is explicit.
data DeadlineUnitPolicy
  = -- | Read a bare number as a number of days, following the day-serial
    -- convention of @libraries\/datetime.l4@ (\"Serial is the UTC datestamp
    -- (number of days since L4 epoch)\"), and record an 'XDeadlineUnit'
    -- finding for every timer that relied on the assumption. Reading is not
    -- guessing only because it is reported.
    AssumeDays
  | -- | Refuse: a bare number produces no timer at all, and an
    -- 'XDeadlineUnparsed' finding instead.
    RefuseToGuess
  deriving stock (Eq, Show)

-- | Knobs for lowering. Kept tiny on purpose; the CLI surface is Track S0's.
newtype BpmnOptions = BpmnOptions
  { optDeadlineUnit :: DeadlineUnitPolicy
  }
  deriving stock (Eq, Show)

defaultBpmnOptions :: BpmnOptions
defaultBpmnOptions = BpmnOptions {optDeadlineUnit = AssumeDays}

--------------------------------------------------------------------------------
-- Process structure
--------------------------------------------------------------------------------

-- | What a flow node /is/. Every node in this IR is one of BPMN's five shapes
-- that a state graph can motivate; there is deliberately no @userTask@,
-- @serviceTask@ or @subProcess@, because a 'L4.StateGraph.StateGraph' carries
-- nothing that would justify choosing one.
data NodeKind
  = -- | @\<startEvent\>@
    StartEvent
  | -- | @\<endEvent\>@; 'True' adds an @\<errorEventDefinition\>@ (a breach).
    EndEvent !Bool
  | -- | @\<task\>@ — abstract, because we do not know who or what performs it.
    Task
  | -- | @\<exclusiveGateway\>@ \/ @\<parallelGateway\>@.
    Gateway !GatewayKind !GatewayFlow
  | -- | @\<boundaryEvent\>@, always interrupting, attached to the named node.
    Boundary !Text !BoundaryTrigger
  deriving stock (Eq, Show)

data GatewayKind = ExclusiveGateway | ParallelGateway
  deriving stock (Eq, Show)

data GatewayFlow = Diverging | Converging
  deriving stock (Eq, Show)

-- | The trigger on an interrupting boundary event.
--
-- BPMN requires a boundary event to carry exactly one trigger — there is no
-- \"none\" boundary event — so a @LEST@ whose deadline we could not turn into an
-- ISO 8601 duration becomes a /conditional/ boundary event carrying the raw
-- text, rather than a timer carrying a duration we invented.
data BoundaryTrigger
  = -- | @\<timerEventDefinition\>@ with an ISO 8601 @\<timeDuration\>@.
    TimerAfter !Text
  | -- | @\<conditionalEventDefinition\>@ with the raw text as its condition.
    WhenCondition !Text
  deriving stock (Eq, Show)

data FlowNode = FlowNode
  { nodeId :: !Text
  , nodeName :: !Text
  , nodeKind :: !NodeKind
  , -- | @\<documentation\>@. Where the notation cannot draw something (the
    -- deontic modality, the guard, the deadline), the XML still says it.
    nodeDoc :: !(Maybe Text)
  , -- | The party this node belongs to; 'Nothing' lands in the default lane.
    nodeLane :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

data SequenceFlow = SequenceFlow
  { flowId :: !Text
  , flowName :: !Text
  , flowFrom :: !Text
  , flowTo :: !Text
  , -- | @\<conditionExpression\>@, from a @PROVIDED@ guard.
    flowCondition :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

-- | One @\<lane\>@: a party, and the ids of the flow nodes assigned to it.
data BpmnLane = BpmnLane
  { laneId :: !Text
  , laneName :: !Text
  , laneNodes :: ![Text]
  }
  deriving stock (Eq, Show)

data BpmnProcess = BpmnProcess
  { procId :: !Text
  , procName :: !Text
  , -- | Empty means no @\<laneSet\>@ at all: a one-party (or party-less) graph
    -- gets a plain process rather than a pool containing a single anonymous band.
    procLanes :: ![BpmnLane]
  , procNodes :: ![FlowNode]
  , procFlows :: ![SequenceFlow]
  }
  deriving stock (Eq, Show)

-- | A @\<collaboration\>@ holding exactly one @\<participant\>@ (one pool).
--
-- Emitted only when there are lanes, because a lane is drawn as a band /inside/
-- a pool and a pool is a participant. It is deliberately never more than one:
-- separate pools communicate by message flow, and a state graph carries no
-- messages, so a second pool would be a claim the source does not make.
data Collaboration = Collaboration
  { collabId :: !Text
  , participantId :: !Text
  , participantName :: !Text
  }
  deriving stock (Eq, Show)

data BpmnExport = BpmnExport
  { bxDefinitionsId :: !Text
  , bxCollaboration :: !(Maybe Collaboration)
  , bxProcess :: !BpmnProcess
  , bxDiagram :: !Diagram
  , -- | 'True' when at least one end event is an error end, so the emitter
    -- knows to declare the shared @\<error\>@ root element.
    bxHasError :: !Bool
  , bxFidelity :: ![Fidelity]
  }
  deriving stock (Eq, Show)

--------------------------------------------------------------------------------
-- Diagram interchange
--------------------------------------------------------------------------------

-- | Integral coordinates throughout: DI attributes are @xsd:double@, but every
-- position we compute is a whole number of pixels, and integers serialise
-- byte-identically on every platform. Determinism is a golden-test requirement.
data Bounds = Bounds
  { bx :: !Int
  , by :: !Int
  , bw :: !Int
  , bh :: !Int
  }
  deriving stock (Eq, Show)

data Point = Point
  { ptX :: !Int
  , ptY :: !Int
  }
  deriving stock (Eq, Show)

data ShapeKind
  = -- | A flow node.
    PlainShape
  | -- | The pool; gets @isHorizontal@ and @isExpanded@.
    PoolShape
  | -- | A lane band; gets @isHorizontal@.
    LaneShape
  deriving stock (Eq, Show)

data Shape = Shape
  { shapeId :: !Text
  , shapeOf :: !Text
  , shapeKind :: !ShapeKind
  , shapeBounds :: !Bounds
  }
  deriving stock (Eq, Show)

data EdgeGeom = EdgeGeom
  { edgeId :: !Text
  , edgeOf :: !Text
  , -- | At least two, always.
    edgeWaypoints :: ![Point]
  }
  deriving stock (Eq, Show)

data Diagram = Diagram
  { -- | What the @\<BPMNPlane\>@ depicts: the collaboration if there is one,
    -- otherwise the process.
    diagPlaneOf :: !Text
  , diagShapes :: ![Shape]
  , diagEdges :: ![EdgeGeom]
  }
  deriving stock (Eq, Show)

-- | BPMN's standard default sizes. Camunda's renderer assumes them; using
-- anything else makes it fight the layout.
nodeWidth :: NodeKind -> Int
nodeWidth = \case
  StartEvent -> 36
  EndEvent _ -> 36
  Boundary _ _ -> 36
  Gateway _ _ -> 50
  Task -> 100

nodeHeight :: NodeKind -> Int
nodeHeight = \case
  StartEvent -> 36
  EndEvent _ -> 36
  Boundary _ _ -> 36
  Gateway _ _ -> 50
  Task -> 80

--------------------------------------------------------------------------------
-- Fidelity
--------------------------------------------------------------------------------

-- | What the export could not carry, and where.
--
-- @F1@–@F5@ are losses of the /notation/ (PROCESS-TRACK.md §5); @X1@–@X4@ are
-- approximations made by /this exporter/. The distinction matters: the first
-- set cannot be fixed by writing more Haskell, and the second can.
data FidelityCode
  = -- | F1 — deontic modality. @MUST@, @MAY@ and @SHANT@ all draw as a task.
    FModality
  | -- | F2 — bearer vs performer. A lane says who acts; a deontic says who owes.
    FBearer
  | -- | F3 — vacuity. \"Never became applicable\" and \"was discharged\" look alike.
    FVacuity
  | -- | F4 — guard bodies. A @PROVIDED@ ladder becomes an opaque string.
    FGuardBody
  | -- | F5 — rule version. BPMN has no as-of date.
    FRuleVersion
  | -- | X1 — a unit-less deadline was read as days.
    XDeadlineUnit
  | -- | X2 — a deadline we could not turn into an ISO 8601 duration.
    XDeadlineUnparsed
  | -- | X3 — an @RAND@ whose branches do not reconverge, so no join was invented.
    XNoParallelJoin
  | -- | X4 — a state the extractor left with nowhere to go.
    XDanglingState
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data FidelitySeverity
  = -- | Something a reader of the diagram will get wrong if not told.
    Loud
  | -- | Worth recording; not misleading on its own.
    Note
  deriving stock (Eq, Ord, Show)

data Fidelity = Fidelity
  { fidCode :: !FidelityCode
  , fidSeverity :: !FidelitySeverity
  , -- | The id of the BPMN element that lost the information.
    fidElement :: !Text
  , -- | A human name for that element.
    fidSubject :: !Text
  , fidMessage :: !Text
  }
  deriving stock (Eq, Show)

fidelityTag :: FidelityCode -> Text
fidelityTag = \case
  FModality -> "F1"
  FBearer -> "F2"
  FVacuity -> "F3"
  FGuardBody -> "F4"
  FRuleVersion -> "F5"
  XDeadlineUnit -> "X1"
  XDeadlineUnparsed -> "X2"
  XNoParallelJoin -> "X3"
  XDanglingState -> "X4"

fidelityTitle :: FidelityCode -> Text
fidelityTitle = \case
  FModality -> "deontic modality"
  FBearer -> "bearer vs performer"
  FVacuity -> "vacuity"
  FGuardBody -> "guard bodies"
  FRuleVersion -> "rule version"
  XDeadlineUnit -> "deadline unit assumed"
  XDeadlineUnparsed -> "deadline not expressible as a duration"
  XNoParallelJoin -> "parallel branches do not reconverge"
  XDanglingState -> "dangling state"

-- | The human-readable rendering, grouped by code and stable in order.
renderFidelityReport :: Text -> [Fidelity] -> Text
renderFidelityReport subject findings =
  Text.unlines (headline : "" : concatMap section [minBound .. maxBound])
 where
  loud = length [() | f <- findings, f.fidSeverity == Loud]
  headline =
    "Fidelity report for "
      <> subject
      <> " — "
      <> plural (length findings) "finding"
      <> ", "
      <> Text.pack (show loud)
      <> " loud"

  section code = case [f | f <- findings, f.fidCode == code] of
    [] -> []
    fs ->
      (fidelityTag code <> "  " <> fidelityTitle code)
        : map entry fs
        <> [""]

  entry f =
    "    "
      <> (if f.fidSeverity == Loud then "! " else "  ")
      <> f.fidElement
      <> " ("
      <> f.fidSubject
      <> ")\n        "
      <> f.fidMessage

  plural n what =
    Text.pack (show n) <> " " <> what <> (if n == 1 then "" else "s")
