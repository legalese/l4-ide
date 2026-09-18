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
-- why they are carried alongside the XML as first-class values rather than as
-- warnings printed and forgotten.
--
-- The type is 'L4.Interchange.Fidelity.FidelityReport', shared with every other
-- interchange backend so that the CLI has one report shape to render rather
-- than one per target. Codes @F1@–@F5@ are the notation losses enumerated in
-- @specs\/todo\/lexipedia-superset\/PROCESS-TRACK.md@ §5. Codes @P-…@ are a
-- different animal: places where /this exporter/ had to approximate. They are
-- prefixed so that in a combined report a BPMN approximation can never be
-- mistaken for a DMN one (@D-…@), nor either for a loss of the notation.
module L4.Bpmn.IR
  ( -- * The export
    BpmnExport (..)
  , Collaboration (..)
  , BpmnProcess (..)
  , BpmnLane (..)

    -- * Flow nodes and sequence flows
  , FlowNode (..)
  , NodeKind (..)
  , EndKind (..)
  , MultiInstance (..)
  , LoopCollection (..)
  , GatewayKind (..)
  , GatewayFlow (..)
  , BoundaryTrigger (..)
  , boundaryInterrupts
  , SequenceFlow (..)
  , nodeWidth
  , nodeHeight

    -- * The DMN linkage
  , DmnCall (..)
  , DmnWiring (..)
  , WiredDecision (..)
  , VerdictRow (..)
  , droolsDmnLanguage

    -- * Diagram interchange
  , Diagram (..)
  , Shape (..)
  , ShapeKind (..)
  , EdgeGeom (..)
  , Bounds (..)
  , Point (..)

    -- * Options
  , BpmnOptions (..)
  , defaultBpmnOptions
  , DeadlineUnitPolicy (..)
  ) where

import Base

import L4.Interchange.Fidelity (FidelityReport)
import L4.Syntax (Unique)

--------------------------------------------------------------------------------
-- The DMN linkage
--------------------------------------------------------------------------------

-- | The rule language a @\<businessRuleTask\>@ declares when it delegates to
-- DMN.
--
-- __This is a plain BPMN 2.0 @implementation@ attribute, not a vendor
-- extension__, and that is the point of choosing it. Its value is a URI naming
-- a rule language; everything else the task needs — namespace, model, decision
-- — travels in a standard @\<ioSpecification\>@. So the emitted file contains
-- exactly one vendor-specific /string/ and zero vendor namespaces.
--
-- Measured 2026-08-02 against jbpm-bpmn2 7.74.1.Final on seven probe files
-- (@specs\/todo\/lexipedia-superset\/PROCESS-TRACK.md@ §8.3): a bare
-- @businessRuleTask@, a @camunda:decisionRef@, a @zeebe:calledDecision@ and a
-- DMN @implementation@ URI + @\<import\>@ are each REJECTED, and this URI
-- /with/ the three @dataInput@s is the only form accepted. @bpmn-moddle@
-- accepts all seven, so it does not discriminate; jBPM does, and this is what
-- it asks for.
droolsDmnLanguage :: Text
droolsDmnLanguage = "http://www.jboss.org/drools/dmn"

-- | A resolved call from a @\<businessRuleTask\>@ to one decision in the
-- sibling DMN model.
--
-- Every field is __copied from the emitted DRG__, never re-derived from the L4
-- source. That is what makes a dangling reference unrepresentable rather than
-- merely unlikely: 'L4.Bpmn.Wiring.wiringFromDrg' builds its table from
-- 'L4.Dmn.IR.drgDecisions', so a decide the DMN population filter dropped is
-- absent from the table and its gateway simply does not get wired.
data DmnCall = MkDmnCall
  { dmcNamespace :: !Text
    -- ^ the DMN @\<definitions\>@ @\@namespace@
  , dmcModel :: !Text
    -- ^ the DMN @\<definitions\>@ @\@name@
  , dmcDecision :: !Text
    -- ^ the decision element's @\@name@ — its FEEL name, which is also what its
    -- @\<variable\>@ is called and therefore what a gateway condition reads
  , dmcLabel :: !Text
    -- ^ the verbatim L4 name, for the task's own @\@name@
  , dmcElementId :: !Text
    -- ^ the decision element's @\@id@. Not part of the engine's
    -- @(namespace, model, decision)@ lookup key; carried so the task's
    -- @\<documentation\>@ can name the element a reader should open.
  }
  deriving stock (Eq, Show)

-- | One row of a verdict decision's table, as the wiring needs to read it.
--
-- 'vrGuard' is the row's L4 source guard (@Just "OTHERWISE"@ on the catch-all)
-- and exists so the arm↔row correspondence can be __checked__ rather than
-- assumed positional. 'vrOutput' is the row's output entry as FEEL — already
-- quoted, so it drops straight into a comparison.
data VerdictRow = MkVerdictRow
  { vrGuard :: !(Maybe Text)
  , vrOutput :: !Text
  }
  deriving stock (Eq, Show)

-- | What the DMN backend emitted for one @DECIDE@.
data WiredDecision = MkWiredDecision
  { wdId :: !Text
  , wdName :: !Text
  , wdFeelName :: !Text
  , wdBoolean :: !Bool
    -- ^ the decision's output is @boolean@, so a gateway may test it directly
  , wdVerdict :: !(Maybe [VerdictRow])
    -- ^ the rows of an enumerated-string decision table — the R13 verdict
    -- shape. 'Nothing' for every other decision, including a string-typed one
    -- with no enumerated domain, because without the domain there is no set of
    -- values a gateway could exhaust.
  }
  deriving stock (Eq, Show)

-- | Everything the process side needs to know about the decision side.
--
-- Keyed by 'Unique' rather than by name: see 'L4.StateGraph.GuardAtom'.
data DmnWiring = MkDmnWiring
  { dwNamespace :: !Text
  , dwModel :: !Text
  , dwDecisions :: !(Map Unique WiredDecision)
  }
  deriving stock (Eq, Show)

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
data BpmnOptions = BpmnOptions
  { optDeadlineUnit :: DeadlineUnitPolicy
  , optWiring :: Maybe DmnWiring
    -- ^ What the DMN backend emitted for the same module, if it was run.
    --
    -- 'Nothing' is not a degraded mode, it is the honest one: with no DRG in
    -- hand there is nothing a @businessRuleTask@ could point at, so every
    -- gateway keeps its opaque @conditionExpression@ and @P-BRANCHGUARD@ keeps
    -- reporting the loss. Supplying it is what discharges the loss, per
    -- @specs\/todo\/lexipedia-superset\/PROCESS-TRACK.md@ §8.3.
  }
  deriving stock (Eq, Show)

defaultBpmnOptions :: BpmnOptions
defaultBpmnOptions = BpmnOptions {optDeadlineUnit = AssumeDays, optWiring = Nothing}

--------------------------------------------------------------------------------
-- Process structure
--------------------------------------------------------------------------------

-- | What a flow node /is/. Every node here is a BPMN shape a state graph can
-- motivate; there is deliberately no @userTask@ and no @serviceTask@, because
-- a 'L4.StateGraph.StateGraph' carries nothing that would justify choosing
-- between them.
--
-- __@subProcess@ was on that list until a fork motivated one.__ The rule has
-- not changed — a shape earns its place by being forced, not by being
-- available — and 'MultiInstanceScope' says what forces it. Do not read its
-- arrival as licence for the other two: what a fork needs is a token SCOPE,
-- which is a control-flow fact the graph does state, where \"is this act
-- performed by a human or a service\" is not.
data NodeKind
  = -- | @\<startEvent\>@
    StartEvent
  | -- | @\<endEvent\>@, of one of three kinds.
    EndEvent !EndKind
  | -- | @\<task\>@ — abstract, because we do not know who or what performs it.
    Task
  | -- | @\<exclusiveGateway\>@ \/ @\<parallelGateway\>@.
    Gateway !GatewayKind !GatewayFlow
  | -- | @\<boundaryEvent\>@, always interrupting, attached to the named node.
    Boundary !Text !BoundaryTrigger
  | -- | @\<businessRuleTask\>@ delegating a gateway's guard to a DMN decision.
    --
    -- The one node kind that is not motivated by the state graph alone: it
    -- exists only where a 'DmnWiring' says the guard has a home in the emitted
    -- DMN. See 'L4.Bpmn.Lower' and PROCESS-TRACK.md §8.3.
    BusinessRule !DmnCall
  | -- | @\<subProcess\>@ carrying
    -- @\<multiInstanceLoopCharacteristics isSequential="false"\>@: one
    -- INSTANCE per member of a fork's cast, each with its own copy of
    -- everything inside it.
    --
    -- __Why a scope and not a marker on the task.__ A barrier (@ONCE ALL
    -- HAVE@) fires its continuation once, when the last member has performed,
    -- which is exactly what a multi-instance /activity/ already means — so a
    -- barrier needs no scope and does not get one. A fork (@UPON EACH@) fires
    -- its continuation once per member, as that member performs, and a
    -- continuation drawn outside the activity cannot do that however the
    -- activity is marked. Putting the continuation INSIDE buys three things
    -- the marker cannot:
    --
    -- * the continuation is per member, which is what @UPON EACH@ says;
    -- * the member's @WITHIN@ lives on the member's own activity, so the
    --   timer cancels that member and not the group (@P-FORK-CANCEL@);
    -- * an EMPTY cast draws correctly. A multi-instance activity over an
    --   empty collection completes at once and its outgoing flow IS taken —
    --   right for a barrier, where \"all zero have acted\" is vacuously true,
    --   and for a fork it MANUFACTURES an obligation nobody owes. With the
    --   continuation inside there is no instance to run it, which is the
    --   answer L4 gives. Measured 2026-09-16: at n=0 the barrier fires its
    --   HENCE and the fork goes to @FULFILLED@.
    --
    -- __It is not free, and the cost is worth stating where it is emitted.__
    -- A multi-instance sub-process synchronises at its own end and a fork does
    -- not. That is invisible until a fork's continuation feeds shared
    -- downstream flow, and then the file says the group waits where L4 says it
    -- does not. See @P-FORK-JOIN@.
    --
    -- Carries no 'MultiInstance': a scope always completes when every instance
    -- does. That is not an omission, it is a guard — see 'MultiInstance', whose
    -- @CompleteOnFirst@ means \"cancel the siblings\" and is false for every
    -- L4 rule when applied to a scope.
    MultiInstanceScope
  deriving stock (Eq, Show)

-- | What an @\<endEvent\>@ terminates.
data EndKind
  = -- | A plain end: this path is over.
    PlainEnd
  | -- | @\<errorEventDefinition\>@ — a breach.
    --
    -- Only ever emitted at TOP LEVEL. An error event is fixed /interrupting/
    -- in BPMN 2.0, so an error thrown inside a multi-instance instance would
    -- cancel its siblings: one tenant's breach would silently end every other
    -- tenant's obligation, which no L4 rule says. Inside a scope the breach
    -- path ends with 'EscalationEnd' instead.
    ErrorEnd
  | -- | @\<escalationEventDefinition\>@ — a breach RAISED FROM INSIDE a
    -- multi-instance instance, to be caught by a non-interrupting boundary on
    -- the scope.
    --
    -- Escalation is the sanctioned non-interrupting throw. Measured 2026-09-16
    -- against jBPM 7.74.1 with three instances all throwing: the inner nodes
    -- fire 3x each, the catch fires 3x, and the scope\'s own end still fires
    -- 1x — so n throws give n tokens and nothing collapses. @cancelActivity=
    -- "false"@ on an /error/ boundary is accepted without complaint by both
    -- bpmn-moddle and jBPM, which settles nothing in its favour: the
    -- divergence would be silent at run time, and this one is not.
    EscalationEnd
  deriving stock (Eq, Show)

data GatewayKind = ExclusiveGateway | ParallelGateway
  deriving stock (Eq, Show)

-- | @\<multiInstanceLoopCharacteristics isSequential="false"\>@ on a task: one
-- instance per member of an @EVERY@'s cast, all live at once.
--
-- Deliberately without a @loopCardinality@ and without a @loopDataInputRef@.
-- L4 fixes the cast only when the rule runs (EVERY-EACH-QUANTIFIER-SPEC R-T6),
-- so the file can say "many, in parallel" and cannot say how many; inventing
-- either attribute would be a claim the source does not make. @P-CAST@ tells
-- the reader an engine will need one supplied.
--
-- The completion rule of a parallel multi-instance activity — the outgoing
-- flow fires once, when the last instance has completed — is exactly the
-- barrier (@ONCE ALL HAVE@) for an obligation, which is why a @MUST@ barrier
-- needs no further shape. It is the WRONG rule for a prohibition: under
-- @SHANT@ one member's act is the breach (EVERY-EACH-QUANTIFIER-SPEC R-Q5,
-- §3.4), and "completes when every director has sublet" would exonerate the
-- first one — measured 2026-09-15 on @ok\/every\/run-modals.l4@'s
-- @no subletting@, whose golden says BREACH with one act. So a prohibition's
-- activity completes on the FIRST instance to complete, via a
-- @\<completionCondition\>@ that is derived from the source, not invented.
-- The fork (@UPON EACH@) is the shape BPMN cannot draw this way; see @P-FORK@
-- and 'MultiInstanceScope', which draws it as a scope instead.
--
-- __This type describes a multi-instance TASK and cannot reach a scope.__
-- 'MultiInstanceScope' takes no 'MultiInstance' argument, so @CompleteOnFirst@
-- has nowhere to go and the wrong thing is unrepresentable rather than merely
-- unwritten. What it would have meant is worth saying, because it reads
-- plausible: \"the scope completes as soon as one instance does\" cancels every
-- other instance, so one member\'s breach would end every other member\'s
-- obligation. A prohibition does complete on the first act — that is R-Q5 —
-- but it completes the GROUP\'s activity, and a fork\'s instances are not the
-- group.
data MultiInstance
  = -- | completes when every instance has: the barrier, for @MUST@\/@MAY@\/@DO@
    CompleteWhenAll
  | -- | completes on the first instance to: a prohibition, where one act breaches
    CompleteOnFirst
  deriving stock (Eq, Show)

-- | BPMN 2.0 §10.5.1 Table 10.100 makes @gatewayDirection@ a /claim about the
-- edges/, not a caption: @Diverging@ MUST NOT have multiple incoming flows,
-- @Converging@ MUST NOT have multiple outgoing, @Mixed@ has both, and
-- @Unspecified@ (the XSD default) constrains nothing.
--
-- It is the one attribute in an emitted file that is a statement /about the
-- rest of the file/, so it is never chosen by the pass that creates the node —
-- which runs before any edge exists — but recomputed from the flows actually
-- drawn. See 'L4.Bpmn.Lower.gatewayFlowFor'.
data GatewayFlow = Unspecified | Diverging | Converging | Mixed
  deriving stock (Eq, Show)

-- | The trigger on a boundary event.
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
  | -- | @\<escalationEventDefinition\>@, catching an 'EscalationEnd' thrown
    -- inside a 'MultiInstanceScope'.
    CatchEscalation
  deriving stock (Eq, Show)

-- | Whether a boundary event cancels the activity it is attached to.
--
-- Derived from the trigger rather than carried alongside it, because in this
-- IR the two are not independent: a deadline expiring ends the obligation it
-- bounds, and an escalation caught from one instance of a scope must NOT end
-- the other instances. BPMN would allow either flag on either trigger; we emit
-- one combination each, and this function is where that is stated once.
boundaryInterrupts :: BoundaryTrigger -> Bool
boundaryInterrupts = \case
  TimerAfter _ -> True
  WhenCondition _ -> True
  CatchEscalation -> False

data FlowNode = FlowNode
  { nodeId :: !Text
  , nodeName :: !Text
  , nodeKind :: !NodeKind
  , -- | @\<documentation\>@. Where the notation cannot draw something (the
    -- deontic modality, the guard, the deadline), the XML still says it.
    nodeDoc :: !(Maybe Text)
  , -- | The party this node belongs to; 'Nothing' lands in the default lane.
    nodeLane :: !(Maybe Text)
  , -- | Set on the task of an @EVERY@ obligation and on nothing else. A
    -- 'MultiInstanceScope' carries its own multi-instance-ness in its kind and
    -- leaves this 'Nothing'.
    nodeMultiInstance :: !(Maybe MultiInstance)
  , -- | The 'MultiInstanceScope' this node is drawn inside, if any.
    --
    -- The nesting is recorded on the CHILD rather than as a list on the
    -- parent, because the diagram interchange is flat: BPMN DI puts a
    -- sub-process\'s children in the same @\<BPMNPlane\>@ as everything else,
    -- in absolute plane coordinates, with only @isExpanded@ on the parent
    -- shape to say it is a box rather than a marker. A nested IR would have to
    -- be flattened again to lay it out.
    --
    -- A boundary event attached to a scope is NOT its child: it hangs on the
    -- outside of the border and belongs to whatever contains the scope.
    nodeParent :: !(Maybe Text)
  , -- | The cast a multi-instance activity draws its instances from. Meaning­
    -- less on a node that is neither multi-instance nor a scope.
    nodeLoopCollection :: !(Maybe LoopCollection)
  }
  deriving stock (Eq, Show)

-- | What a multi-instance activity loops over: @\<loopDataInputRef\>@ and the
-- @\<inputDataItem\>@ each instance binds.
--
-- __Name the variable for the CAST, never for the roll.__ @loopDataInputRef@
-- names a PROCESS VARIABLE, and the file claims nothing about what is in it —
-- an engine is told to supply one. That stays true only while the name does
-- not imply an answer. @EVERY Tenant t IN everyone@ arms a cast of tenants,
-- not a cast of @everyone@ (see 'L4.StateGraph.quantCast'), so a variable
-- called @everyone@ invites seeding it with the roll and turns an honest
-- \"supply this\" into a false statement of who is bound. Called
-- @\<rule\>_cast@, it does not, and @P-CAST@ says in prose what to put in it —
-- a sentence that cannot be written without 'L4.StateGraph.quantCast' and
-- 'L4.StateGraph.quantFilter'.
data LoopCollection = LoopCollection
  { loopVariable :: !Text
    -- ^ the process variable to loop over — @\<rule\>_cast@
  , loopItem :: !Text
    -- ^ the item each instance binds: the @EVERY@\'s member variable, as the
    -- source spells it (@t@ in @EVERY Tenant t@), so that a reader can match
    -- the BPMN back to the rule.
  }
  deriving stock (Eq, Show)

data SequenceFlow = SequenceFlow
  { flowId :: !Text
  , flowName :: !Text
  , flowFrom :: !Text
  , flowTo :: !Text
  , -- | @\<conditionExpression\>@, from a @PROVIDED@ guard.
    flowCondition :: !(Maybe Text)
  , -- | @\<documentation\>@. Set where 'flowCondition' has been rewritten into
    -- a test over a DMN decision's output, and holds the L4 text the condition
    -- used to be — so the guard the drafter wrote is still in the file, in
    -- prose, where nothing will try to evaluate it.
    flowDoc :: !(Maybe Text)
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
  , -- | 'True' when at least one end event is an 'EscalationEnd', so the
    -- emitter knows to declare the shared @\<escalation\>@ root element.
    --
    -- Separate from 'bxHasError' rather than folded into it: a file can have
    -- both (a fork whose members escalate, inside a process whose own breach
    -- is an error), and a throw with no matching declaration is malformed.
    bxHasEscalation :: !Bool
  , bxFidelity :: !FidelityReport
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
  | -- | An expanded sub-process: a box drawn around its children, which are
    -- siblings of it in the same plane. Gets @isExpanded@.
    ExpandedShape
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
  BusinessRule _ -> 100
  -- A scope is sized from what it contains ('L4.Bpmn.Lower'), never from this
  -- table; the figure is a floor for an empty one.
  MultiInstanceScope -> 200

nodeHeight :: NodeKind -> Int
nodeHeight = \case
  StartEvent -> 36
  EndEvent _ -> 36
  Boundary _ _ -> 36
  Gateway _ _ -> 50
  Task -> 80
  BusinessRule _ -> 80
  MultiInstanceScope -> 160
