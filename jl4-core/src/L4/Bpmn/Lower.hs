-- | Lower an 'L4.StateGraph.StateGraph' to the BPMN IR, with layout.
--
-- == The shape of the mapping
--
-- The load-bearing observation is that __a transition is the task, and the
-- states are its endpoints__. A state in the extracted automaton is a moment
-- between obligations, not a thing anyone does; the obligation is the edge. So
-- an ordinary intermediate state contributes no BPMN element at all — it is
-- just the point where one task's outgoing flow meets the next task.
--
-- Concretely, for each state:
--
-- * 'L4.StateGraph.InitialState' contributes a @\<startEvent\>@;
-- * a junction ('L4.StateGraph.AllOf' \/ 'L4.StateGraph.OneOf') contributes a
--   diverging @\<parallelGateway\>@ or @\<exclusiveGateway\>@;
-- * its @HENCE@ transition contributes a @\<task\>@ and that task's normal
--   outgoing @\<sequenceFlow\>@;
-- * its @LEST@ transition contributes an /interrupting/ @\<boundaryEvent\>@ on
--   that task, plus the flow out of it — which is the one line of the mapping
--   table that is genuinely satisfying, because \"if the obligation is not
--   discharged, go here instead\" is exactly what boundary events are for;
-- * 'L4.StateGraph.TerminalFulfilled' contributes a plain @\<endEvent\>@ and
--   'L4.StateGraph.TerminalBreach' one carrying an @\<errorEventDefinition\>@.
--
-- Those elements form a small chain per state (start → gateway → task → end,
-- taking only the parts that exist), wired together internally; everything else
-- is a flow from one state's chain to another's.
--
-- == Where we refuse to guess
--
-- Three places, all reported rather than silent:
--
-- 1. A deadline that is not an ISO 8601 duration and has no unit we can read
--    becomes a /conditional/ boundary event carrying the raw text, never a
--    timer carrying a duration we made up (@P-DEADLINE@). A bare number is
--    read as days only because 'AssumeDays' says so, and says so out loud
--    (@P-DEADLINE-UNIT@).
-- 2. An @RAND@ gets a converging @\<parallelGateway\>@ only when every branch
--    is /proved/ to deliver exactly one token, unconditionally. Reachability is
--    not that proof and asserting it is how this exporter used to emit
--    deadlocks; see 'addJoin'. Where the proof fails we leave the branches
--    unjoined and say so (@P-NOJOIN@).
--
--    Whether that costs the reader anything depends on the graph, so the note
--    does not pretend otherwise. Where no branch can breach, a BPMN instance
--    does end only once every token is consumed, so \"all of\" still holds
--    implicitly. Where one can, it does not: @BREACH@ is an error end event,
--    and an uncaught top-level error terminates the instance rather than
--    consuming one token and waiting for the siblings. @P-NOJOIN@ says which
--    case applies.
-- 3. A prohibition is not an activity. It is still drawn as a task, because
--    BPMN has no other shape for it, and the loss is reported as @F1@ at
--    'Blocking' severity. Its /deadline/, by contrast, is drawn faithfully:
--    BPMN's interrupting boundary event is exactly the race @SHANT@ needs,
--    provided the two arms are wired the way the L4 runtime resolves them and
--    not the way they look. See 'raceArms'.
-- 4. Three shapes the 'L4.StateGraph' types permit and today's extractor never
--    produces — several @HENCE@ arms from one state (@P-MULTI-HENCE@), a
--    junction that is also an obligation (@P-JUNCTION-OBLIGATION@), and a cycle
--    (@P-CYCLE@) — are detected and reported without being drawn, because
--    there is no honest shape to draw instead. See 'multiHenceFindings'.
module L4.Bpmn.Lower
  ( stateGraphToBpmn
  ) where

import Base
import qualified Base.Text as Text
import Control.Applicative ((<|>))
import Data.Char (isAlpha, isAlphaNum, isAscii, isDigit)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import L4.Bpmn.IR
import L4.Interchange.Fidelity
import L4.StateGraph
import L4.Syntax (DeonticModal (..))

--------------------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------------------

-- | Lower a state graph to a BPMN 2.0 process, its diagram, and its fidelity
-- report. Pure and deterministic: every identifier is derived from state and
-- transition ids, so the same graph always yields byte-identical XML.
stateGraphToBpmn :: BpmnOptions -> StateGraph -> BpmnExport
stateGraphToBpmn opts sg =
  BpmnExport
    { bxDefinitionsId = "Definitions_" <> slug
    , bxCollaboration = collab
    , bxProcess =
        BpmnProcess
          { procId = processId
          , procName = sg.sgName
          , procLanes = lanes
          , procNodes = allNodes
          , procFlows = allFlows
          }
    , bxDiagram = diagram
    , bxHasError = any isErrorEnd allNodes
    , bxFidelity = foldl' (flip addNote) (emptyReport "BPMN 2.0") findings
    }
 where
  slug = ncName sg.sgName
  processId = "Process_" <> slug

  ------------------------------------------------------------------
  -- Indexes over the source graph
  ------------------------------------------------------------------

  outs :: Map StateId [Transition]
  outs =
    Map.fromListWith
      (flip (<>))
      [(t.transFrom, [t]) | t <- sg.sgTransitions]

  outOf :: StateId -> [Transition]
  outOf sid = Map.findWithDefault [] sid outs

  pickType :: TransitionType -> StateId -> Maybe Transition
  pickType ty sid = listToMaybe [t | t <- outOf sid, t.transType == ty]

  henceOf, lestOf :: StateId -> Maybe Transition
  henceOf = pickType HenceTransition
  lestOf = pickType LestTransition

  defaultsOf :: StateId -> [Transition]
  defaultsOf sid = [t | t <- outOf sid, t.transType == DefaultTransition]

  succsOf :: Map StateId [StateId]
  succsOf = Map.map (map (.transTo)) outs

  ------------------------------------------------------------------
  -- Pass 1: one chain of nodes per state
  ------------------------------------------------------------------

  chains :: [(StateId, StateChain)]
  chains = [(s.stateId, chainFor s) | s <- sg.sgStates]

  chainOf :: StateId -> Maybe StateChain
  chainOf sid = lookup sid chains

  chainFor :: ContractState -> StateChain
  chainFor s =
    StateChain
      { scNodes = nodes
      , scBoundary = boundary
      , scLapse = lapse
      , scFindings =
          taskFindings
            <> branchGuardFindings
            <> boundaryFindings
            <> lapseFindings
            <> undrawnDeadlineFindings
            <> danglingFindings
      }
   where
    sid = s.stateId
    tag = Text.pack (show sid)
    obligation = henceOf sid <|> lestOf sid

    startNodes =
      [ FlowNode
        { nodeId = "Start_" <> tag
        , nodeName = ""
        , nodeKind = StartEvent
        , nodeDoc = Nothing
        , nodeLane = Nothing
        }
      | s.stateType == InitialState
      ]

    gatewayNodes =
      [ FlowNode
        { nodeId = "Split_" <> tag
        , nodeName = fanName s.stateFan
        , nodeKind = Gateway (fanGateway s.stateFan) Diverging
        , nodeDoc = Just (fanDoc s.stateFan)
        , nodeLane = Nothing
        }
      | s.stateFan /= Linear
      ]

    taskNodes = case obligation of
      Nothing -> []
      Just t ->
        [ FlowNode
            { nodeId = "Task_" <> tag
            , nodeName = taskName t.transLabel
            , nodeKind = Task
            , nodeDoc = Just (restateRule t.transLabel <> taskArmNote t.transLabel.labelModal)
            , nodeLane = t.transLabel.labelParty
            }
        ]

    endNodes =
      [ FlowNode
        { nodeId = "End_" <> tag
        , nodeName = s.stateName
        , nodeKind = EndEvent (s.stateType == TerminalBreach)
        , nodeDoc = Nothing
        , nodeLane = Nothing
        }
      | s.stateType == TerminalFulfilled || s.stateType == TerminalBreach
      ]

    -- A state with nothing to contribute and nowhere to go: the extractor met
    -- an expression it could not classify. Draw the path as ending rather than
    -- leaving a node the emitter would have to invent a shape for.
    danglingNodes =
      [ FlowNode
        { nodeId = "End_" <> tag
        , nodeName = s.stateName
        , nodeKind = EndEvent False
        , nodeDoc = Just "no outgoing transition in the source state graph"
        , nodeLane = Nothing
        }
      | null startNodes && null gatewayNodes && null taskNodes && null endNodes
      ]

    nodes = startNodes <> gatewayNodes <> taskNodes <> endNodes <> danglingNodes

    modal = obligation >>= (.transLabel.labelModal)
    deadline = obligation >>= (.transLabel.labelDeadline)

    -- The deadline hangs off the task as an interrupting boundary event. The
    -- trigger is the same for every modal — the WITHIN running out — because
    -- that is the event BPMN is being asked to draw. What differs by modal is
    -- /which arm the timer leads to/, and that is settled in 'transitionFlows',
    -- not here. See 'raceArms'.
    --
    -- Note the deadline comes from the obligation's own label (WITHIN lives on
    -- the HENCE edge), not from the LEST edge, whose label is the one-word
    -- caption L4.StateGraph.lestArmWording derives for that arm.
    (boundary, boundaryFindings) = case (lestOf sid, taskNodes) of
      (Just lestT, host : _) ->
        let bid = "Boundary_" <> tag
            (trigger, finds) = boundaryTrigger opts modal bid lestT.transLabel.labelAction deadline
         in ( Just
                FlowNode
                  { nodeId = bid
                  , nodeName = triggerName modal deadline trigger lestT.transLabel.labelAction
                  , nodeKind = Boundary host.nodeId trigger
                  , nodeDoc = Just (boundaryDoc modal deadline)
                  , nodeLane = host.nodeLane
                  }
            , finds
            )
      _ -> (Nothing, [])

    -- A permission with a deadline and no LEST still has somewhere for its
    -- timer to go: expiry of an unexercised MAY routes to FULFILLED, the same
    -- place HENCE goes. So synthesise the boundary event and draw the lapse
    -- rather than dropping the WITHIN and filing a note about it. Confessing a
    -- loss you could have avoided is not honesty.
    --
    -- The word for it comes from 'lestArmWording', not from a literal here:
    -- this node draws the very arm that function names, and two spellings of
    -- one vocabulary is the shape smucclaw/l4-ide#927 was about. The guard
    -- below only fires with a deadline in hand, which is the case in which
    -- 'lestArmWording' says @lapses@.
    (lapse, lapseFindings) = case (modal, lestOf sid, deadline, taskNodes) of
      (Just DMay, Nothing, Just d, host : _) ->
        let lid = "Lapse_" <> tag
            lapseWord = lestArmWording DMay (Just d)
            (trigger, finds) = boundaryTrigger opts modal lid lapseWord deadline
         in ( Just
                FlowNode
                  { nodeId = lid
                  , nodeName = triggerName modal deadline trigger lapseWord
                  , nodeKind = Boundary host.nodeId trigger
                  , nodeDoc =
                      Just
                        "the permission lapses: the deadline passes without it \
                        \being exercised, which routes where HENCE routes"
                  , nodeLane = host.nodeLane
                  }
            , finds
            )
      _ -> (Nothing, [])

    -- What is left is DO, which requires an explicit HENCE/LEST and so offers
    -- no target to infer. Its WITHIN is drawn nowhere, and a temporal
    -- constraint disappearing in silence is what this report exists to prevent.
    undrawnDeadlineFindings =
      [ MkFidelityNote
        { code = "P-DEADLINE-UNDRAWN"
        , severity = Lossy
        , element = tn.nodeId
        , range = Nothing
        , message =
            "The deadline \8216"
              <> d
              <> "\8217 is not drawn anywhere: this obligation has no LEST and \
                 \no inferable target for its expiry, so there is no boundary \
                 \event to carry it."
        , lost =
            "the deadline as a drawn constraint; it survives only in the \
            \element's <documentation>"
        }
      | isNothing boundary
      , isNothing lapse
      , Just d <- [deadline]
      , tn <- take 1 taskNodes
      ]

    taskFindings = case (obligation, taskNodes) of
      (Just t, tn : _) -> modalityFinding tn t.transLabel <> guardFindings tn t.transLabel
      _ -> []

    -- The @IF@ that chose between arms. This is the branch-edge counterpart of
    -- @F4@: @F4@ accounts for a @PROVIDED@ on one obligation, this accounts
    -- for the condition on a gateway's outgoing flow. Both end as opaque text
    -- in a @conditionExpression@ and both are reported, because a guard that
    -- an engine cannot evaluate is exactly the loss a reader needs to be told
    -- about — and until the extractor could see an @IF@-headed rule at all,
    -- there was no shape here to report on.
    branchGuardFindings =
      [ MkFidelityNote
        { code = "P-BRANCHGUARD"
        , severity = Lossy
        , element = gw.nodeId
        , range = Nothing
        , message =
            "The gateway's arms are selected by \8216"
              <> Text.intercalate "\8217, \8216" guards
              <> "\8217, written into each outgoing flow as an opaque \
                 \conditionExpression: BPMN has no way to say that these \
                 \exhaust the cases and cannot overlap, which is what the L4 \
                 \IF/ELSE chain they came from does say."
        , lost =
            "exhaustiveness and mutual exclusion as properties of the \
            \gateway — and whatever decision structure backed each condition, \
            \for which DMN, not BPMN, is the right home"
        }
      | gw <- take 1 gatewayNodes
      , guards@(_ : _) <- [mapMaybe (.transLabel.labelGuard) (defaultsOf sid)]
      ]

    danglingFindings =
      [ MkFidelityNote
        { code = "P-DANGLING"
        , severity = Advisory
        , element = n.nodeId
        , range = Nothing
        , message =
            "The state \8216"
              <> s.stateName
              <> "\8217 has no outgoing transition in the source graph, so the \
                 \path is drawn as ending here rather than left dangling."
        , lost = "nothing the source said; this is an artefact of extraction"
        }
      | n <- danglingNodes
      ]

  ------------------------------------------------------------------
  -- Node bookkeeping
  ------------------------------------------------------------------

  baseNodes :: [FlowNode]
  baseNodes =
    concat [c.scNodes <> maybeToList c.scBoundary <> maybeToList c.scLapse | (_, c) <- chains]

  -- Which state each node came from; needed to tell a flow that leaves a
  -- parallel branch from one that merely happens to end at the same place.
  nodeState :: Map Text StateId
  nodeState =
    Map.fromList
      [ (n.nodeId, sid)
      | (sid, c) <- chains
      , n <- c.scNodes <> maybeToList c.scBoundary <> maybeToList c.scLapse
      ]

  -- Where an edge from ANOTHER state lands when it arrives here.
  --
  -- A @\<startEvent\>@ is instance creation, not a re-entry point, and BPMN
  -- gives it no incoming sequence flow. So an arrival skips it and lands on the
  -- node it flows to — which for the initial state is the gateway or task
  -- 'chainFor' already put after it, and which is where the loop belongs
  -- anyway: the renewal re-tests the guards, it does not re-start the process.
  --
  -- This is not a stylistic preference. @HENCE \<this rule\>@ (see
  -- 'L4.StateGraph.TargetSelf') is the shape that first pointed an edge back at
  -- the initial state, and drawing it at @Start_0@ produced a file that
  -- @etc\/check-bpmn-soundness.mjs@ refuses to play ("no start event to put a
  -- token on") and that jBPM refuses to parse outright: /A start node
  -- [Start_0, null] may not have an incoming connection!/ Two independent
  -- engines, one defect.
  --
  -- The fallback keeps the start node when the chain has nothing else in it, so
  -- that an arrival is still drawn rather than silently dropped. An edge the
  -- reader cannot see is worse than one a checker will complain about; today no
  -- such chain exists, because a state anything can point back at has an
  -- obligation or a fan, and either adds a node after the start event.
  entryOf :: StateId -> Maybe Text
  entryOf sid =
    chainOf sid >>= \c ->
      (.nodeId)
        <$> (listToMaybe (dropWhile ((== StartEvent) . (.nodeKind)) c.scNodes)
               <|> listToMaybe c.scNodes)

  nodeOfKind :: (NodeKind -> Bool) -> StateId -> Maybe Text
  nodeOfKind p sid =
    chainOf sid >>= \c -> listToMaybe [n.nodeId | n <- c.scNodes, p n.nodeKind]

  taskOf, gatewayOf :: StateId -> Maybe Text
  taskOf = nodeOfKind (== Task)
  gatewayOf = nodeOfKind \case Gateway _ _ -> True; _ -> False

  boundaryOf :: StateId -> Maybe Text
  boundaryOf sid = chainOf sid >>= \c -> (.nodeId) <$> c.scBoundary

  lapseOf :: StateId -> Maybe Text
  lapseOf sid = chainOf sid >>= \c -> (.nodeId) <$> c.scLapse

  ------------------------------------------------------------------
  -- Pass 2: flows
  ------------------------------------------------------------------

  -- Inside one state's chain: start → gateway → task → end, for whichever
  -- parts exist.
  chainFlows :: [Edge]
  chainFlows =
    [ (a.nodeId, b.nodeId, Nothing)
    | (_, c) <- chains
    , (a, b) <- zip c.scNodes (drop 1 c.scNodes)
    ]

  transitionFlows :: [Edge]
  transitionFlows = concatMap perState sg.sgStates
   where
    -- Every transition gets a flow, not just the one whose label named the
    -- task. Today's extractor emits at most one HENCE and one LEST per state,
    -- so the difference is invisible; taking only the first would silently drop
    -- an edge if that ever changed, and a lost edge is a lie the reader cannot
    -- see.
    perState s =
      let sid = s.stateId
          (henceSrc, lestSrc) = raceArms (modalAt sid) (taskOf sid) (boundaryOf sid)
          hence =
            [ (src, tgt, t.transLabel.labelGuard)
            | t <- outOf sid
            , t.transType == HenceTransition
            , Just src <- [henceSrc]
            , Just tgt <- [entryOf t.transTo]
            ]
          lest =
            [ (src, tgt, Nothing)
            | t <- outOf sid
            , t.transType == LestTransition
            , Just src <- [lestSrc]
            , Just tgt <- [entryOf t.transTo]
            ]
          -- A branch edge out of a junction carries a guard when the junction
          -- came from an @IF@ rather than from @RAND@ \/ @ROR@, and that guard
          -- is the whole reason the gateway is readable: without it the
          -- diagram says "pick an arm", then does the work, and only then
          -- tests the condition that decided which arm applied. Dropping it
          -- (which is what this did until 2026-07-27) turns a fact-driven
          -- exclusive gateway into a free choice.
          branches =
            [ (src, tgt, t.transLabel.labelGuard)
            | t <- defaultsOf sid
            , Just src <- [gatewayOf sid <|> lastChainNode sid]
            , Just tgt <- [entryOf t.transTo]
            ]
          -- The lapse timer lands wherever HENCE lands.
          --
          -- KNOWN WRONG in one shape, and not fixed here. The evaluator routes
          -- an unexercised MAY's expiry through @fromMaybe fulfilExpr lest@,
          -- i.e. to FULFILLED — which is where HENCE goes only when HENCE is
          -- absent or is FULFILLED. Give a bare MAY a HENCE that points at
          -- another obligation and the two part company. Measured:
          --
          --   PARTY Alice MAY pay WITHIN 5 HENCE (PARTY Bob MUST deliver WITHIN 10)
          --     (`WAIT UNTIL` 100)          ==> FULFILLED
          --     PARTY Alice DOES pay AT 3   ==> PARTY Bob MUST deliver WITHIN 10
          --
          -- so in that shape this flow draws the lapse arriving at Bob's
          -- obligation, which it never does. The root cause is upstream —
          -- 'L4.StateGraph.extractDeonton' emits no LEST edge for a bare MAY, so
          -- there is nothing here to follow and this synthesis is guessing. See
          -- the NOTE at that site; fixing it retires this whole branch.
          lapses =
            [ (src, tgt, Nothing)
            | t <- outOf sid
            , t.transType == HenceTransition
            , Just src <- [lapseOf sid]
            , Just tgt <- [entryOf t.transTo]
            ]
       in hence <> lest <> branches <> lapses

    lastChainNode sid = chainOf sid >>= \c -> (.nodeId) <$> listToMaybe (reverse c.scNodes)

    modalAt sid = (henceOf sid <|> lestOf sid) >>= (.transLabel.labelModal)

  -- Ids are assigned only after the join pass, so that a flow the join
  -- rewrote is not left carrying the id of the node it used to point at.
  numberFlows :: [Edge] -> [SequenceFlow]
  numberFlows = go Set.empty
   where
    go _ [] = []
    go used ((src, tgt, cond) : rest) =
      let wanted = "Flow_" <> src <> "__" <> tgt
          fid = disambiguate used wanted (1 :: Int)
       in SequenceFlow
            { flowId = fid
            , flowName = ""
            , flowFrom = src
            , flowTo = tgt
            , flowCondition = cond
            }
            : go (Set.insert fid used) rest
    disambiguate used wanted n
      | not (Set.member wanted used) = wanted
      | otherwise = disambiguate used (wanted <> "_" <> Text.pack (show n)) (n + 1)

  ------------------------------------------------------------------
  -- Joins for RAND
  ------------------------------------------------------------------

  allFlows = numberFlows joinedEdges

  (allNodes, joinedEdges, joinFindings) =
    foldl' addJoin (baseNodes, chainFlows <> transitionFlows, []) allOfJunctions

  allOfJunctions :: [StateId]
  allOfJunctions = [s.stateId | s <- sg.sgStates, s.stateFan == AllOf]

  -- The id a junction's converging gateway gets, if it gets one.
  joinIdFor :: StateId -> Text
  joinIdFor j = "Join_" <> Text.pack (show j)

  reachFrom :: StateId -> Set StateId
  reachFrom = go Set.empty . pure
   where
    go seen [] = seen
    go seen (s : rest)
      | Set.member s seen = go seen rest
      | otherwise = go (Set.insert s seen) (Map.findWithDefault [] s succsOf <> rest)

  -- A converging parallel gateway waits for one token on __every__ incoming
  -- flow. So the thing that has to be proved before drawing one is not that the
  -- branches /reach/ a common point — reachability is far too weak — but that
  -- each branch delivers __exactly one token, unconditionally__.
  --
  -- The distinction is the whole bug. An earlier version counted rewired edges
  -- and required two or more, which passes happily for a branch containing an
  -- interrupting boundary event (@cancelActivity="true"@ makes its two arms
  -- mutually exclusive: two edges, one token), a @ROR@ (an exclusive gateway:
  -- n edges, one token), or a lapse timer (same shape again). Each of those
  -- emits a join that waits forever for a token nothing will ever send, and the
  -- emitted BPMN deadlocks — a strictly worse failure than not drawing the
  -- gateway at all, because a reader can see a missing gateway and cannot see a
  -- token that never arrives.
  --
  -- So: one unconditional edge per branch, or decline. Declining costs little,
  -- and 'P-NOJOIN' says so.
  --
  -- __A failed proof has exactly one honest outcome, and it is 'P-NOJOIN'.__
  -- There was once a second: under the edge-counting join this replaced, an
  -- enclosing junction could draw its gateway first and rewrite this one's
  -- arrivals to it, leaving nothing here to join — a benign outcome, reported
  -- as folded, at 'Advisory', saying nothing was lost.
  --
  -- That cannot happen under a token proof, and the reason is worth keeping
  -- rather than rediscovering. Folding needs the enclosing junction to have
  -- drawn its join /while sharing this one's join target/ — and sharing the
  -- target is precisely what gives the enclosing junction's branch two arrivals
  -- and makes its own proof fail first. The two conditions exclude each other.
  -- So do not reintroduce a \"nothing was lost\" note here on the strength of an
  -- arrival that points at some gateway: an arrival redirected to a join is
  -- equally consistent with a junction this one /contains/ having claimed it,
  -- and in that direction the conjunction here really is undrawn and really is
  -- a loss. 'P-NOJOIN' at 'Lossy' is safe in every case; an Advisory that
  -- misfires is the one note a reader stops reading after.
  addJoin ::
    ([FlowNode], [Edge], [FidelityNote]) ->
    StateId ->
    ([FlowNode], [Edge], [FidelityNote])
  addJoin (nodes, edges, finds) junction =
    case (joinTarget, joinTarget >>= entryOf) of
      (Just r, Just tgt)
        | not disjointBranches -> declineWith overlapReason
        | otherwise -> case tokenProof r tgt of
            Left reason -> declineWith reason
            Right proven ->
              let jid = joinIdFor junction
                  claimed = Set.fromList [(a, b) | (a, b, _) <- proven]
                  redirect (edgeFrom, edgeTo, cond)
                    | Set.member (edgeFrom, edgeTo) claimed = (edgeFrom, jid, cond)
                    | otherwise = (edgeFrom, edgeTo, cond)
                  joinNode =
                    FlowNode
                      { nodeId = jid
                      , nodeName = ""
                      , nodeKind = Gateway ParallelGateway Converging
                      , nodeDoc =
                          Just
                            "every branch of the RAND must complete; each \
                            \delivers exactly one token"
                      , nodeLane = Nothing
                      }
               in ( nodes <> [joinNode]
                  , map redirect edges <> [(jid, tgt, Nothing)]
                  , finds
                  )
      _ -> declineWith cannotReason
   where
    branches = map (.transTo) (defaultsOf junction)

    declineWith reason = (nodes, edges, finds <> [noJoinFinding reason])

    interiorOf r b = Set.delete r (reachFrom b)

    nodesInside interior nid =
      maybe False (`Set.member` interior) (Map.lookup nid nodeState)

    -- Edges by which one branch arrives at the join point.
    arrivalsOf r tgt b =
      let interior = interiorOf r b
       in [e | e@(eFrom, eTo, _) <- edges, eTo == tgt, nodesInside interior eFrom]

    -- Exactly one unconditional arrival per branch, or the reason it failed.
    tokenProof r tgt = traverse (check . arrivalsOf r tgt) branches
     where
      check = \case
        [e@(_, _, Nothing)] -> Right e
        [(_, _, Just _)] ->
          Left
            "one of its branches reaches the join through a conditional flow, \
            \which may never fire, so a parallel join could wait for a token \
            \that is never sent"
        [] -> Left "one of its branches never reaches the join point at all"
        several ->
          Left
            ( "one of its branches reaches the join by "
                <> Text.pack (show (length several))
                <> " different routes — an interrupting boundary event, a ROR, \
                   \or a lapse timer — of which at most one will fire, whereas \
                   \a parallel join would wait for every one of them"
            )

    exitsOf b = Set.filter (\s -> null (Map.findWithDefault [] s succsOf)) (reachFrom b)

    joinTarget = case map exitsOf branches of
      exits@(e : _)
        | length branches >= 2
        , all (== e) exits
        , [r] <- Set.toList e ->
            Just r
      _ -> Nothing

    -- Branch subgraphs that overlap anywhere but the join point would make the
    -- rewrite ambiguous; refuse rather than draw something we cannot justify.
    disjointBranches =
      let interiors = [interiorOf r b | b <- branches, r <- maybeToList joinTarget]
       in and
            [ Set.null (Set.intersection a b)
            | (i, a) <- zip [0 :: Int ..] interiors
            , (j, b) <- zip [0 :: Int ..] interiors
            , i < j
            ]

    overlapReason =
      "two of its branches share intermediate states, so which arrival belongs \
      \to which branch is ambiguous"

    cannotReason
      | length branches < 2 = "it has fewer than two branches"
      | otherwise =
          "its branches do not all stop at one common state — at least one can \
          \reach an outcome the others cannot, typically BREACH"

    -- Whether declining actually costs the reader anything depends on whether a
    -- branch can breach, so the note must not assert the same thing either way.
    someBranchBreaches =
      or
        [ s.stateType == TerminalBreach
        | b <- branches
        , sid <- Set.toList (reachFrom b)
        , s <- sg.sgStates
        , s.stateId == sid
        ]

    noJoinFinding reason =
      MkFidelityNote
        { code = "P-NOJOIN"
        , severity = Lossy
        , element = fromMaybe ("state " <> Text.pack (show junction)) (gatewayOf junction)
        , range = Nothing
        , message =
            "No converging parallel gateway was drawn for this RAND because "
              <> reason
              <> ". A join that waits for a token nothing will send is a \
                 \deadlock, which is worse than an undrawn conjunction."
        , lost =
            "the conjunction as a drawn gateway"
              <> if someBranchBreaches
                then
                  " — and do not assume it survives implicitly. An instance does \
                  \end only once every token is consumed, but a branch here can \
                  \reach BREACH, whose error end abandons its siblings rather \
                  \than waiting for them."
                else
                  ". No branch here can breach, so every token is still \
                  \consumed before the instance ends and the conjunction does \
                  \hold — it is simply not drawn."
        }

  ------------------------------------------------------------------
  -- Lanes
  ------------------------------------------------------------------

  -- 'nubOrd' keeps first occurrences, so lane order is source order.
  parties :: [Text]
  parties = nubOrd [p | n <- allNodes, Just p <- [n.nodeLane]]

  unassigned :: [Text]
  unassigned = [n.nodeId | n <- allNodes, isNothing n.nodeLane]

  lanes :: [BpmnLane]
  lanes
    | null parties = []
    | otherwise = partyLanes <> defaultLane
   where
    partyLanes =
      [ BpmnLane
        { laneId = "Lane_" <> Text.pack (show i) <> "_" <> ncName p
        , laneName = p
        , laneNodes = [n.nodeId | n <- allNodes, n.nodeLane == Just p]
        }
      | (i, p) <- zip [1 :: Int ..] parties
      ]
    defaultLane =
      [ BpmnLane
        { laneId = "Lane_unassigned"
        , laneName = "(unassigned)"
        , laneNodes = unassigned
        }
      | not (null unassigned)
      ]

  collab
    | null lanes = Nothing
    | otherwise =
        Just
          Collaboration
            { collabId = "Collaboration_" <> slug
            , participantId = "Participant_" <> slug
            , participantName = sg.sgName
            }

  ------------------------------------------------------------------
  -- Layout
  ------------------------------------------------------------------

  diagram =
    layoutDiagram
      LayoutInput
        { liPlaneOf = maybe processId (.collabId) collab
        , liPool = fmap (.participantId) collab
        , liLanes = lanes
        , liNodes = allNodes
        , liFlows = allFlows
        }

  ------------------------------------------------------------------
  -- Findings
  ------------------------------------------------------------------

  findings =
    concat [c.scFindings | (_, c) <- chains]
      <> joinFindings
      <> multiHenceFindings
      <> junctionObligationFindings
      <> cycleFindings
      <> [bearerFinding | not (null parties)]
      <> [ruleVersionFinding]

  ------------------------------------------------------------------
  -- Shapes the types permit that today's extractor cannot reach
  ------------------------------------------------------------------

  -- 'L4.StateGraph' currently emits at most one @HENCE@ and one @LEST@ per
  -- state, never a junction that is also an obligation, and never a back edge.
  -- The /types/ permit all three, and this module is written against the types,
  -- not against one afternoon's extractor. Each of the three lowers to
  -- something that reads as a claim the source does not make, so each is
  -- detected here and named.
  --
  -- __Detected, not rendered.__ There is no honest shape to draw instead — the
  -- whole difficulty is that BPMN's notation already spends its unconditional
  -- outgoing flows on \"and\" — so inventing one is exactly how this exporter
  -- would start lying. The note is the deliverable. It is also cheap insurance:
  -- the day someone teaches the extractor a new shape, the report says what
  -- happened instead of the diagram quietly saying something else.

  -- Two @HENCE@ arms leave the /same/ task, both unconditional. BPMN reads
  -- several unconditional outgoing sequence flows as an implicit parallel split
  -- — the AND-split you get for free by drawing nothing — so a choice between
  -- continuations is drawn as \"both happen\". That is the AllOf\/OneOf
  -- confusion this whole track exists to fix, reappearing one level down where
  -- no gateway marks it.
  multiHenceFindings =
    [ MkFidelityNote
      { code = "P-MULTI-HENCE"
      , severity = Blocking
      , element = fromMaybe ("state " <> Text.pack (show s.stateId)) (taskOf s.stateId)
      , range = Nothing
      , message =
          "This state has "
            <> Text.pack (show (length hs))
            <> " HENCE transitions. All of them leave the same task with no \
               \condition on any of them, and BPMN reads several unconditional \
               \outgoing flows as an implicit parallel split — so the diagram \
               \says every continuation happens, where the source offered a \
               \choice. Only the first HENCE named the task, so the others also \
               \lost their party, action and deadline."
      , lost =
          "the choice between the continuations, and every label but the \
          \first's; an exclusive gateway would draw the choice, but nothing in \
          \the source says which arm wins, so drawing one would invent the \
          \answer"
      }
    | s <- sg.sgStates
    , let hs = [t | t <- outOf s.stateId, t.transType == HenceTransition]
    , length hs > 1
    ]

  -- A junction state contributes a diverging gateway; an obligation state
  -- contributes a task; and 'chainFlows' wires a state's own nodes in order, so
  -- a state that is both hangs the task off the gateway. The gateway then has
  -- one more outgoing arm than the junction has branches, and that extra arm is
  -- the obligation — drawn as a sibling of the branches rather than as their
  -- precondition.
  junctionObligationFindings =
    [ MkFidelityNote
      { code = "P-JUNCTION-OBLIGATION"
      , severity = Blocking
      , element = fromMaybe ("state " <> Text.pack (show s.stateId)) (gatewayOf s.stateId)
      , range = Nothing
      , message =
          "This state is both a "
            <> fanName s.stateFan
            <> " junction and an obligation, so it draws a diverging gateway \
               \and a task, and the task hangs off the gateway. The gateway \
               \therefore has one arm more than the junction has branches: \
               \under \8216all of\8217 the obligation is drawn as one more \
               \concurrent branch, under \8216one of\8217 as one more \
               \alternative. Neither is what the source says."
      , lost =
          "the obligation's place in the order — that it governs the junction \
          \rather than racing it"
      }
    | s <- sg.sgStates
    , s.stateFan /= Linear
    , any
        (\t -> t.transType == HenceTransition || t.transType == LestTransition)
        (outOf s.stateId)
    ]

  -- Some state can get back to itself. BPMN draws loops perfectly well; this
  -- LAYOUT does not, because it ranks a node by its longest path from the start
  -- and a node on a cycle has no such thing.
  cycleFindings =
    [ MkFidelityNote
      { code = "P-CYCLE"
      , severity = Lossy
      , element = processId
      , range = Nothing
      , message =
          "The state graph has a cycle ("
            <> Text.intercalate ", " (map stateNameOf onACycle)
            <> "). BPMN can draw a loop, but this layout places a node by its \
               \longest path from the start and a node on a cycle has none, so \
               \inside the loop a node further right no longer means a moment \
               \further on: the positions are wherever the relaxation ran out \
               \of fuel."
      , lost =
          "the reading that left-to-right is time, which is the only thing the \
          \horizontal axis was carrying"
      }
    | not (null onACycle)
    ]

  -- A state is on a cycle when one of its successors can get back to it.
  onACycle :: [StateId]
  onACycle =
    [ s.stateId
    | s <- sg.sgStates
    , any (Set.member s.stateId . reachFrom) (Map.findWithDefault [] s.stateId succsOf)
    ]

  stateNameOf sid =
    fromMaybe
      (Text.pack (show sid))
      (listToMaybe [s.stateName | s <- sg.sgStates, s.stateId == sid])

  bearerFinding =
    MkFidelityNote
      { code = "F2"
      , severity = Lossy
      , element = processId
      , range = Nothing
      , message =
          "A lane says who performs the work, where L4's PARTY says who owes \
          \the obligation, and this diagram can only show the first (lanes \
          \here: "
            <> Text.intercalate ", " parties
            <> ")."
      , lost =
          "the bearer, as distinct from the performer — the two come apart \
          \whenever an agent acts for a principal"
      }

  ruleVersionFinding =
    MkFidelityNote
      { code = "F5"
      , severity = Advisory
      , element = processId
      , range = Nothing
      , message =
          "BPMN has no as-of date, so any threshold or deadline that does \
          \appear in this diagram is a value someone must remember to edit when \
          \the rule changes."
      , lost =
          "asking the same question as of a different rule date, which the L4 \
          \source can still answer"
      }

isErrorEnd :: FlowNode -> Bool
isErrorEnd n = case n.nodeKind of
  EndEvent isError -> isError
  _ -> False

-- | A sequence flow before it has an id: source node, target node, and the
-- condition (if any) from a @PROVIDED@ guard. Ids are assigned last, after the
-- join pass has finished moving targets around.
type Edge = (Text, Text, Maybe Text)

-- | The nodes one state contributes, in drawing order.
data StateChain = StateChain
  { scNodes :: [FlowNode]
  , scBoundary :: Maybe FlowNode
  , -- | A synthesised timer for a permission that lapses; see 'chainFor'. It
    -- is a boundary event like 'scBoundary', but its outflow goes to the HENCE
    -- target rather than the LEST one.
    scLapse :: Maybe FlowNode
  , scFindings :: [FidelityNote]
  }

--------------------------------------------------------------------------------
-- Labels
--------------------------------------------------------------------------------

fanGateway :: FanKind -> GatewayKind
fanGateway = \case
  AllOf -> ParallelGateway
  _ -> ExclusiveGateway

fanName :: FanKind -> Text
fanName = \case
  AllOf -> "all of"
  OneOf -> "one of"
  Linear -> ""

fanDoc :: FanKind -> Text
fanDoc = \case
  AllOf -> "RAND: every branch is entered"
  OneOf -> "ROR: exactly one branch is entered"
  Linear -> ""

modalWord :: DeonticModal -> Text
modalWord = \case
  DMust -> "MUST"
  DMay -> "MAY"
  DMustNot -> "SHANT"
  DDo -> "DO"

-- | The task's label. The modal keyword is kept in the /name/ deliberately:
-- BPMN cannot draw the difference between an obligation and a permission, so
-- the only place the distinction can survive at all is the text. See
-- @F1@ — this mitigates the loss, it does not repair it.
taskName :: TransitionLabel -> Text
taskName l = case l.labelModal of
  Nothing -> nonEmpty' l.labelAction
  Just m -> modalWord m <> " " <> nonEmpty' l.labelAction
 where
  nonEmpty' t = if Text.null (Text.strip t) then "(unnamed action)" else t

-- | For a prohibition, completing the task /is/ the violation, which is the
-- opposite of what an activity normally means. Say so on the element, since the
-- notation cannot.
taskArmNote :: Maybe DeonticModal -> Text
taskArmNote (Just DMustNot) =
  " \8212 completing this activity means the prohibited act was performed, which is the LEST arm"
taskArmNote _ = ""

-- | The source rule, restated for @\<documentation\>@.
restateRule :: TransitionLabel -> Text
restateRule l =
  Text.intercalate " " $
    catMaybes
      [ fmap ("PARTY " <>) l.labelParty
      , fmap modalWord l.labelModal
      , Just l.labelAction
      , fmap ("WITHIN " <>) l.labelDeadline
      , fmap ("PROVIDED " <>) l.labelGuard
      ]

-- | The boundary event's name — the words a reader sees on the diagram, with no
-- @\<documentation\>@ open.
--
-- The fallback is the @LEST@ edge's own label, which
-- 'L4.StateGraph.lestArmWording' derives from the modal and the deadline. For
-- every modal but one that is exactly the right caption, and this function
-- simply uses it.
--
-- __The prohibition clause below is not a correction of that label.__ It is
-- there because on a @SHANT@ this boundary event is a /different arm/ from the
-- @LEST@ edge it was built out of: 'raceArms' sends the timer to __HENCE__,
-- because for a prohibition the deadline expiring with the act not performed is
-- compliance. So the boundary is named after an event the state graph gives no
-- caption to — the @LEST@ edge's caption belongs to the task, not to this node.
-- Borrowing it here would draw the compliance arm labelled \"violation\", which
-- is the same falsehood in a smaller font.
--
-- This was checked rather than argued: deleting the clause leaves
-- @offering.bpmn@'s two prohibition boundaries reading \"after P30D\" and
-- \"after P365D\", dropping the \", not performed\" that says which arm they
-- are, and renames the untimed one to \"violation\". See smucclaw\/l4-ide#927,
-- which proposed the deletion on the theory that it was compensating for a
-- modal-blind label; it was not.
--
-- The deadline is passed separately from the trigger because a boundary event
-- has one either way: with no @WITHIN@ at all, 'boundaryTrigger' still emits a
-- conditional trigger, and naming that one \"deadline passes\" would assert a
-- deadline the rule does not have — the same rule 'L4.StateGraph.lestArmWording'
-- follows on the other arm. With no @WITHIN@ this arm has no trigger at all,
-- which is what 'L4.StateGraph.noTriggerWording' says; the name and the
-- condition ('fallbackCondition') must agree on that, because they sit on the
-- same element and a reader who opens one has already read the other.
triggerName :: Maybe DeonticModal -> Maybe Text -> BoundaryTrigger -> Text -> Text
triggerName (Just DMustNot) mDue trigger _ = case trigger of
  TimerAfter iso -> "after " <> iso <> ", not performed"
  WhenCondition _
    | isJust mDue -> "deadline passes, not performed"
    -- No WITHIN: the compliance arm this node draws is reached by the deadline
    -- passing, and there is no deadline. Measured — @SHANT smoke LEST …@ with
    -- no WITHIN, run to @WAIT UNTIL 1000@, leaves the prohibition standing as a
    -- residual and never reaches HENCE. This used to read "the act is not
    -- performed", naming an event that never fires.
    | otherwise -> noTriggerWording
triggerName _ _ trigger fallback = case trigger of
  TimerAfter iso -> "after " <> iso
  WhenCondition _ -> if Text.null (Text.strip fallback) then "otherwise" else fallback

-- | Which node each arm of the obligation leaves from: @(HENCE source, LEST
-- source)@, given the task and the deadline's boundary event.
--
-- __For a prohibition the two arms are raced the other way round.__ An
-- interrupting boundary event is a race between \"the activity completed\" and
-- \"the trigger fired\", and for @SHANT@ the L4 runtime races them like this
-- (@L4.EvaluateLazy.Machine@):
--
-- * the deadline expires with the act not performed ⇒ /\"Prohibition was
--   RESPECTED\"/ ⇒ __HENCE__;
-- * the act is performed ⇒ /\"Prohibition violated\"/ ⇒ __LEST__.
--
-- So the timer leads to the fulfilment arm and the task's own completion —
-- which is what performing the forbidden act /is/ — leads to the breach arm.
-- Wiring it the obvious way round, as this exporter originally did, draws a
-- diagram that says \"wait long enough and you are in breach\" when the rule
-- says the opposite. Nothing about this needs a fidelity note: BPMN expresses
-- the race natively, and confessing a loss that did not occur would be its own
-- kind of inaccuracy.
--
-- Every other modal reaches LEST by the deadline running out, so for them the
-- obvious wiring is the correct one.
raceArms ::
  Maybe DeonticModal ->
  -- | the task
  Maybe Text ->
  -- | the deadline's boundary event, if any
  Maybe Text ->
  (Maybe Text, Maybe Text)
raceArms (Just DMustNot) task bnd = (bnd <|> task, task)
raceArms _ task bnd = (task, bnd)

-- | Documentation for the deadline's boundary event, which for a prohibition
-- marks compliance rather than failure.
--
-- The no-@WITHIN@ rows do not describe a deadline, because there is not one.
-- Three of the four modals reach this node only by the clock running out, so
-- with no @WITHIN@ the node is drawn (BPMN needs somewhere for the arm to leave
-- from) but nothing can ever trigger it — see 'L4.StateGraph.noTriggerWording'
-- for the trace. Saying \"the deadline passes\" there was a straightforward
-- falsehood; a @\<documentation\>@ string is the one place with room to say why
-- the node is inert instead.
boundaryDoc :: Maybe DeonticModal -> Maybe Text -> Text
boundaryDoc (Just DMustNot) (Just d) =
  "the deadline passes ("
    <> d
    <> ") with the prohibited act not performed: the prohibition is respected, so this is the HENCE arm"
boundaryDoc (Just DMustNot) Nothing =
  "the prohibition is respected once its deadline passes with the act not \
  \performed, so this is the HENCE arm — but the rule sets no WITHIN, so \
  \nothing reaches it: a prohibition with no deadline is discharged by neither \
  \the clock nor the act"
boundaryDoc _ (Just d) = "LEST: the obligation is not discharged within " <> d
boundaryDoc _ Nothing =
  "LEST: the obligation is not discharged — but the rule sets no WITHIN, and \
  \for every modal but SHANT this arm is reached only by the deadline passing, \
  \so nothing reaches it"

--------------------------------------------------------------------------------
-- Deadlines
--------------------------------------------------------------------------------

-- | Choose the boundary event's trigger, and say what it cost.
boundaryTrigger ::
  BpmnOptions ->
  -- | the obligation's modal, which decides /which arm/ this node is: for a
  -- @SHANT@ 'raceArms' puts it on HENCE, so it must not be given the LEST
  -- edge's caption. See 'fallbackCondition'.
  Maybe DeonticModal ->
  Text ->
  -- | the LEST edge's own label — 'L4.StateGraph.lestArmWording', e.g.
  -- @timeout@, @violation@, @lapses@
  Text ->
  -- | the obligation's @WITHIN@ text, if any
  Maybe Text ->
  (BoundaryTrigger, [FidelityNote])
boundaryTrigger opts modal elemId lestLabel = \case
  Nothing ->
    ( WhenCondition (fallbackCondition modal lestLabel)
    , [ note
          "P-DEADLINE"
          Blocking
          "This LEST has no deadline, and BPMN has no untriggered boundary \
          \event, so it is drawn as a conditional boundary event rather than a \
          \timer. Nothing can fire it: for every modal but SHANT this arm is \
          \reached only by the deadline passing, and for SHANT this node is the \
          \compliance arm, which is likewise reached only by the deadline \
          \passing."
          "the trigger as something an engine could evaluate"
      ]
    )
  Just raw -> case parseDuration opts.optDeadlineUnit raw of
    Parsed iso -> (TimerAfter iso, [])
    ParsedAsDays iso ->
      ( TimerAfter iso
      , [ note
            "P-DEADLINE-UNIT"
            Advisory
            ( "Deadline "
                <> quoted raw
                <> " carries no unit, because nothing in L4 fixes one — WITHIN \
                   \is typed as a bare NUMBER (TypeCheck.hs) and the evaluator \
                   \only ever adds it to an event timestamp. It is read here as \
                   \days ("
                <> iso
                <> "), following the commonest convention in the corpus, where \
                   \event clocks are day counts (libraries/daydate.l4, `Day` \
                   \AKA `Date to days`). A model stamping events in abstract \
                   \ticks will need this edited."
            )
            "certainty about the unit — if this model's clock is not days, the \
            \duration needs editing"
        ]
      )
    Unparsed ->
      ( WhenCondition raw
      , [ note
            "P-DEADLINE"
            Blocking
            ( "Deadline "
                <> quoted raw
                <> " is not an ISO 8601 duration and no unit could be read from \
                   \it, so the boundary event carries the text verbatim as a \
                   \condition rather than a timer carrying a duration we \
                   \invented."
            )
            "the deadline as a machine-checkable timer"
        ]
      )
 where
  note c sev msg what =
    MkFidelityNote
      { code = c
      , severity = sev
      , element = elemId
      , range = Nothing
      , message = msg
      , lost = what
      }
  quoted t = "\8216" <> t <> "\8217"

-- | The @\<condition\>@ on a boundary event that has no deadline to time on.
--
-- For every modal but one this is the @LEST@ edge's own caption, because that is
-- the arm this node draws. A prohibition is the exception, for the same reason
-- 'triggerName' has one: 'raceArms' puts a @SHANT@'s boundary on the __HENCE__
-- arm, so the @LEST@ caption belongs to the task, not to this node. It used to
-- land here anyway, and the result was a single element whose @name@ read \"the
-- act is not performed\" and whose @condition@ read \"violation\" — the two
-- halves of one node asserting opposite arms.
--
-- The word both halves now use is 'L4.StateGraph.noTriggerWording', which is
-- also true of this node in a way \"violation\" never was: with no @WITHIN@ the
-- prohibition's compliance arm has nothing to fire it.
fallbackCondition :: Maybe DeonticModal -> Text -> Text
fallbackCondition (Just DMustNot) _ = noTriggerWording
fallbackCondition _ lestLabel
  | Text.null (Text.strip lestLabel) = "the obligation is not discharged"
  | otherwise = lestLabel

data DurationResult
  = -- | An ISO 8601 duration we could read off the text.
    Parsed Text
  | -- | A bare number, read as days under 'AssumeDays'.
    ParsedAsDays Text
  | Unparsed

-- | Turn L4 deadline text into an ISO 8601 duration.
--
-- L4's @WITHIN@ takes an expression, and 'L4.StateGraph.labelDeadline' is that
-- expression pretty-printed — usually a bare number, sometimes a whole
-- expression like @terms's defaultAfterDays@ that no amount of parsing will
-- turn into a duration.
parseDuration :: DeadlineUnitPolicy -> Text -> DurationResult
parseDuration policy raw
  | Text.null t = Unparsed
  | isIso t = Parsed t
  | isNat t = case policy of
      AssumeDays -> ParsedAsDays ("P" <> t <> "D")
      RefuseToGuess -> Unparsed
  | Just iso <- numberWithUnit t = Parsed iso
  | otherwise = Unparsed
 where
  t = Text.strip raw

isNat :: Text -> Bool
isNat t = not (Text.null t) && Text.all isDigit t

-- | Already a duration: @P30D@, @PT2H@, @P1M@ …
--
-- Deliberately conservative rather than a full ISO 8601 grammar: it must start
-- with @P@, end with a unit designator, contain a digit, and contain nothing
-- else. @P30@ (no designator) is rejected, which is the point — accepting it
-- would put a string Camunda cannot parse into a @\<timeDuration\>@.
isIso :: Text -> Bool
isIso t =
  Text.isPrefixOf "P" t
    && Text.length t >= 3
    && Text.all (\c -> isDigit c || c `elem` ("PYMWDTHS" :: String)) t
    && Text.any isDigit t
    && Text.last t `elem` ("YMWDHS" :: String)

-- | @\"30 days\"@, @\"2 weeks\"@, @\"1 month\"@, @\"3 hours\"@ …
numberWithUnit :: Text -> Maybe Text
numberWithUnit t = do
  let (digits, rest) = Text.span isDigit t
  guard (not (Text.null digits))
  let unit = Text.toLower (Text.strip rest)
  designator <- lookup (Text.dropWhileEnd (== 's') unit) unitTable
  pure $ case designator of
    (True, d) -> "PT" <> digits <> d
    (False, d) -> "P" <> digits <> d
 where
  unitTable =
    [ ("second", (True, "S"))
    , ("minute", (True, "M"))
    , ("hour", (True, "H"))
    , ("day", (False, "D"))
    , ("week", (False, "W"))
    , ("month", (False, "M"))
    , ("year", (False, "Y"))
    ]

--------------------------------------------------------------------------------
-- Findings raised while building nodes
--------------------------------------------------------------------------------

modalityFinding :: FlowNode -> TransitionLabel -> [FidelityNote]
modalityFinding n l =
  [ MkFidelityNote
      { code = "F1"
      , severity = Blocking
      , element = n.nodeId
      , range = Nothing
      , message = message
      , lost = what
      }
  ]
 where
  (message, what) = case l.labelModal of
    Just DMustNot ->
      ( "A prohibition is not an activity at all and BPMN has no negative \
        \shape for one, so read literally this diagram instructs the reader \
        \to perform the very act the rule forbids."
      , "the difference between a required act and a forbidden one; only the \
        \SHANT in the label and the <documentation> say otherwise, and neither \
        \has any notational force"
      )
    Just DMay ->
      ( "A permission is drawn as a task, so the diagram reads as an \
        \instruction to perform it."
      , "the difference between what a party may do and what it must do; BPMN \
        \cannot mark an activity optional"
      )
    _ ->
      ( "MUST, MAY and SHANT all draw as a task, so nothing here makes \
        \skipping this one a breach and skipping another one fine."
      , "the deontic modality, which survives in the label and the \
        \<documentation> but has no notational force"
      )

guardFindings :: FlowNode -> TransitionLabel -> [FidelityNote]
guardFindings n l = case l.labelGuard of
  Nothing -> []
  Just g ->
    [ MkFidelityNote
        { code = "F4"
        , severity = Lossy
        , element = n.nodeId
        , range = Nothing
        , message =
            "The PROVIDED condition \8216"
              <> g
              <> "\8217 becomes an opaque conditionExpression on the task's \
                 \outgoing flow, because BPMN has no activity precondition."
        , lost =
            "whatever decision structure backed the guard — DMN would be its \
            \right home, and the DMN/BPMN link is an association, not a \
            \semantics"
        }
    , MkFidelityNote
        { code = "F3"
        , severity = Blocking
        , element = n.nodeId
        , range = Nothing
        , message =
            "This obligation can fail to become applicable at all, and BPMN \
            \has only one kind of \8216did not happen\8217."
        , lost =
            "the difference between an obligation that was never reached and \
            \one that was discharged"
        }
    ]

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

-- | Everything the layout pass needs, so it can be read on its own.
data LayoutInput = LayoutInput
  { liPlaneOf :: Text
  , liPool :: Maybe Text
  , liLanes :: [BpmnLane]
  , liNodes :: [FlowNode]
  , liFlows :: [SequenceFlow]
  }

taskSlotWidth, rowHeight, lanePadTop, lanePadBottom, minLaneHeight :: Int
taskSlotWidth = 100
rowHeight = 120
lanePadTop = 20
lanePadBottom = 20
minLaneHeight = 140

-- | The gutter is the empty strip to the right of each rank's column, and every
-- vertical run in the drawing happens in one. Its width is /derived/, not
-- fixed: it has to hold one channel per flow that turns in it, and below
-- thirteen channels the minimum already does, which is why @layerWidth@ comes
-- out at its historical 180 for every graph anyone has drawn so far.
--
-- Fixing the width instead and clamping the channels into it is the same bug
-- one level down: past the point where they fit, flows land on the same x and
-- draw as a single line, which is exactly what per-flow channels exist to
-- prevent. A wider drawing is the only honest alternative.
minGutterWidth, minChannelGap, gutterInset :: Int
minGutterWidth = 80
minChannelGap = 4
gutterInset = 14

poolX, poolY, laneLabelWidth, laneLeftPad, poolRightPad :: Int
poolX = 130
poolY = 80
laneLabelWidth = 30
laneLeftPad = 40
poolRightPad = 60

-- | A layered left-to-right assignment from the longest-path ranking, banded by
-- lane. State graphs are small, so this is enough; nothing here is trying to be
-- a graph-drawing engine.
layoutDiagram :: LayoutInput -> Diagram
layoutDiagram li =
  Diagram
    { diagPlaneOf = li.liPlaneOf
    , diagShapes = poolShape <> laneShapes <> nodeShapes
    , diagEdges = edges
    }
 where
  nodes = li.liNodes
  byId = Map.fromList [(n.nodeId, n) | n <- nodes]

  ------------------------------------------------------------------
  -- ranking
  ------------------------------------------------------------------

  preds :: Map Text [Text]
  preds =
    Map.fromListWith (flip (<>)) $
      [(f.flowTo, [f.flowFrom]) | f <- li.liFlows]
        <> [(n.nodeId, [host]) | n <- nodes, Boundary host _ <- [n.nodeKind]]

  -- Relaxation rather than a topological sort: it reaches the longest-path
  -- ranking on a DAG and merely produces a squashed drawing on a cycle, where
  -- a topological sort would have to fail.
  ranks :: Map Text Int
  ranks = go (length nodes) (Map.fromList [(n.nodeId, 0) | n <- nodes])
   where
    go 0 acc = acc
    go fuel acc =
      let next = Map.mapWithKey (\k _ -> rankOf acc k) acc
       in if next == acc then acc else go (fuel - 1 :: Int) next
    rankOf acc k = case Map.lookup k byId of
      Just n | Boundary host _ <- n.nodeKind -> Map.findWithDefault 0 host acc
      _ -> case Map.findWithDefault [] k preds of
        [] -> 0
        ps -> 1 + maximum [Map.findWithDefault 0 p acc | p <- ps]

  rankOfNode n = Map.findWithDefault 0 n.nodeId ranks
  maxRank = maximum (0 : map rankOfNode nodes)

  ------------------------------------------------------------------
  -- lanes and rows
  ------------------------------------------------------------------

  laneIndex :: Map Text Int
  laneIndex =
    Map.fromList
      [ (nid, i)
      | (i, lane) <- zip [0 ..] li.liLanes
      , nid <- lane.laneNodes
      ]

  laneOf n = Map.findWithDefault 0 n.nodeId laneIndex
  laneCount = max 1 (length li.liLanes)

  isBoundary n = case n.nodeKind of Boundary _ _ -> True; _ -> False

  -- Boundary events sit on their host's border and so take no row of their own.
  placed = filter (not . isBoundary) nodes

  rowOf :: Map Text Int
  rowOf =
    Map.fromList
      [ (n.nodeId, r)
      | lane <- [0 .. laneCount - 1]
      , rank <- [0 .. maxRank]
      , (r, n) <- zip [0 ..] [n | n <- placed, laneOf n == lane, rankOfNode n == rank]
      ]

  -- Both of these are memoised into maps, and that is not premature.
  --
  -- Written as plain recursive functions they compose into a cubic: 'laneTop'
  -- sums 'laneHeight' over every preceding lane, 'laneHeight' scans every
  -- placed node once per rank, and the bounds pass calls 'laneTop' afresh for
  -- every node. It is invisible in a three-lane fixture and it is invisible at
  -- one lane — @laneTop 0@ sums an empty list and never calls 'laneHeight' at
  -- all — so a golden suite of small many-ranked graphs cannot see it. At 400
  -- nodes across 5 lanes it was ~11 seconds; memoised, ~0.15.
  -- One pass over the nodes: how many share each (lane, rank) cell, then the
  -- busiest cell in each lane. The old form rescanned every node once per
  -- (lane, rank) pair.
  laneRowsOf :: Map Int Int
  laneRowsOf =
    Map.fromListWith
      max
      ([(l, 1) | l <- [0 .. laneCount - 1]] <> [(lane, n) | ((lane, _), n) <- Map.toList perCell])
   where
    perCell :: Map (Int, Int) Int
    perCell = Map.fromListWith (+) [((laneOf n, rankOfNode n), 1) | n <- placed]

  laneRows lane = Map.findWithDefault 1 lane laneRowsOf

  laneHeightOf :: Map Int Int
  laneHeightOf =
    Map.fromList
      [ (l, max minLaneHeight (lanePadTop + laneRows l * rowHeight + lanePadBottom))
      | l <- [0 .. laneCount - 1]
      ]

  laneHeight lane = Map.findWithDefault minLaneHeight lane laneHeightOf

  -- Running totals, computed once, rather than a fresh prefix sum per node.
  laneTopOf :: Map Int Int
  laneTopOf =
    Map.fromList (zip [0 ..] (scanl (+) poolY [laneHeight l | l <- [0 .. laneCount - 1]]))

  laneTop lane = Map.findWithDefault poolY lane laneTopOf

  contentX0 = poolX + laneLabelWidth + laneLeftPad
  poolWidth =
    laneLabelWidth + laneLeftPad + maxRank * layerWidth + taskSlotWidth + poolRightPad
  poolHeight = sum [laneHeight l | l <- [0 .. laneCount - 1]]

  ------------------------------------------------------------------
  -- bounds
  ------------------------------------------------------------------

  boundsOf :: Map Text Bounds
  boundsOf = Map.fromList (map plain placed <> map onBorder (filter isBoundary nodes))
   where
    plain n =
      let w = nodeWidth n.nodeKind
          h = nodeHeight n.nodeKind
          row = Map.findWithDefault 0 n.nodeId rowOf
          slotTop = laneTop (laneOf n) + lanePadTop + row * rowHeight
       in ( n.nodeId
          , Bounds
              { bx = contentX0 + rankOfNode n * layerWidth + (taskSlotWidth - w) `div` 2
              , by = slotTop + (nodeHeight Task - h) `div` 2
              , bw = w
              , bh = h
              }
          )
    -- Hung on the bottom edge of the host, towards its right.
    onBorder n =
      let w = nodeWidth n.nodeKind
          h = nodeHeight n.nodeKind
          host = case n.nodeKind of Boundary hid _ -> hid; _ -> n.nodeId
          hb =
            fromMaybe (Bounds contentX0 poolY taskSlotWidth (nodeHeight Task)) $
              lookup host (map plain placed)
       in ( n.nodeId
          , Bounds
              { bx = hb.bx + hb.bw - w - 10
              , by = hb.by + hb.bh - (h `div` 2)
              , bw = w
              , bh = h
              }
          )

  nodeShapes =
    [ Shape
      { shapeId = "Shape_" <> n.nodeId
      , shapeOf = n.nodeId
      , shapeKind = PlainShape
      , shapeBounds = b
      }
    | n <- nodes
    , Just b <- [Map.lookup n.nodeId boundsOf]
    ]

  poolShape =
    [ Shape
      { shapeId = "Shape_" <> pid
      , shapeOf = pid
      , shapeKind = PoolShape
      , shapeBounds = Bounds {bx = poolX, by = poolY, bw = poolWidth, bh = poolHeight}
      }
    | Just pid <- [li.liPool]
    ]

  laneShapes =
    [ Shape
      { shapeId = "Shape_" <> lane.laneId
      , shapeOf = lane.laneId
      , shapeKind = LaneShape
      , shapeBounds =
          Bounds
            { bx = poolX + laneLabelWidth
            , by = laneTop i
            , bw = poolWidth - laneLabelWidth
            , bh = laneHeight i
            }
      }
    | not (null li.liPool)
    , (i, lane) <- zip [0 ..] li.liLanes
    ]

  ------------------------------------------------------------------
  -- edges
  ------------------------------------------------------------------

  edges =
    [ EdgeGeom
      { edgeId = "Edge_" <> f.flowId
      , edgeOf = f.flowId
      , edgeWaypoints = waypoints f
      }
    | f <- li.liFlows
    ]

  -- Every vertical run happens in the gutter BETWEEN two rank columns, never
  -- inside one.
  --
  -- Nodes occupy @[contentX0 + rank*layerWidth, +taskSlotWidth]@, so the
  -- @layerWidth - taskSlotWidth@ strip to the right of each column is
  -- guaranteed empty. Routing every turn into that strip makes a
  -- segment-through-node crossing impossible by construction rather than by
  -- luck — which matters, because the previous router dropped a boundary
  -- event's outflow straight down at @task.bx + 72@, inside the very column
  -- every task at that rank occupies, and ran it the full height of the pool.
  --
  -- Each flow gets its own channel within the gutter so that parallel flows do
  -- not land on the same x and draw as a single merged line. That is only a
  -- claim about collisions if the channels fit, so the gutter is sized to hold
  -- them — see 'minGutterWidth' — and 'layerWidth' follows from it rather than
  -- the other way round.
  gutterWidth =
    max minGutterWidth (2 * gutterInset + widestChannel * minChannelGap + 4)
  layerWidth = taskSlotWidth + gutterWidth

  -- The vertical run goes in the gutter immediately BEFORE the target's
  -- column, so the horizontal approach into a shared node is as short as
  -- possible. Several flows converging on one end event will still meet, but
  -- they meet at its doorstep rather than sharing a long merged line.
  gutterRankOf f =
    let sr = maybe 0 rankOfNode (Map.lookup f.flowFrom byId)
        tr = maybe 0 rankOfNode (Map.lookup f.flowTo byId)
     in max sr (tr - 1)

  -- A flow occupies up to two gutters — the one it leaves through and the one
  -- it arrives through — so grouping by either alone lets two flows collide in
  -- the gutter they happen to share. Assign greedily instead: each flow takes
  -- the lowest channel index unused in /every/ gutter it touches. That is a
  -- two-line graph colouring, deterministic in flow order, and collision-free
  -- by construction rather than by choosing a big enough step.
  channelIndexOf :: Map Text Int
  channelIndexOf = snd (foldl' claim (Map.empty :: Map Int (Set Int), Map.empty) li.liFlows)
   where
    claim (used, acc) f =
      let gs = nubOrd [rankOfFlowSource f, gutterRankOf f]
          taken = Set.unions [Map.findWithDefault Set.empty g used | g <- gs]
          -- the list is infinite and 'taken' is finite, so this always yields
          i = fromMaybe 0 (listToMaybe [k | k <- [0 :: Int ..], not (Set.member k taken)])
          used' = foldl' (\m g -> Map.insertWith Set.union g (Set.singleton i) m) used gs
       in (used', Map.insert f.flowId i acc)

  rankOfFlowSource f = maybe 0 rankOfNode (Map.lookup f.flowFrom byId)

  -- How many channels the busiest gutter turned out to need. 'gutterWidth' is
  -- derived from this, so a wide fan widens the drawing instead of stacking
  -- flows on one x.
  widestChannel = maximum (0 : Map.elems channelIndexOf)

  -- Spread whatever indices were needed across the gutter's usable width, but
  -- never closer together than 'minChannelGap' — which is the case the gutter
  -- was widened for, so the two together mean the last channel always lands
  -- inside the gutter and no clamp is needed. Deliberately no clamp: if this
  -- arithmetic is ever wrong the tests see a crossing, where a clamp would have
  -- turned it into two flows silently sharing a line.
  channelStep =
    max minChannelGap ((gutterWidth - 2 * gutterInset) `div` max 1 widestChannel)

  channelOf :: Map Text Int
  channelOf = Map.map (\i -> gutterInset + i * channelStep) channelIndexOf

  -- x of the free strip immediately right of a rank's column. Nodes never live
  -- here, so a vertical run in it cannot cross one.
  gutterX rank channel = contentX0 + rank * layerWidth + taskSlotWidth + channel

  -- The free HORIZONTAL band, for the same reason the gutter is the free
  -- vertical one. Every node is centred in an 80px slot inside a 120px row, so
  -- the remainder of the row is empty across the whole width of the pool. A
  -- long horizontal run at some node's centre line, by contrast, will sooner or
  -- later meet a node that shares that centre line — which is how a flow ended
  -- up drawn straight through the task two columns along.
  corridorBelow n =
    let lane = laneOf n
        row = Map.findWithDefault 0 n.nodeId rowOf
        slotTop = laneTop lane + lanePadTop + row * rowHeight
     in slotTop + nodeHeight Task + (rowHeight - nodeHeight Task) `div` 2

  waypoints f =
    let sb = Map.lookup f.flowFrom boundsOf
        tb = Map.lookup f.flowTo boundsOf
        src = Map.lookup f.flowFrom byId
        tgt = Map.lookup f.flowTo byId
        channel = Map.findWithDefault gutterInset f.flowId channelOf
        sRank = maybe 0 rankOfNode src
        gxOut = gutterX sRank channel
        gxIn = gutterX (gutterRankOf f) channel
        -- the corridor below whichever of the two sits higher up the page
        corridor = case (src, tgt) of
          (Just a, Just b) ->
            Just (corridorBelow (if fromMaybe 0 (fmap (.by) sb) <= fromMaybe 0 (fmap (.by) tb) then a else b))
          _ -> Nothing
     in case (sb, tb) of
          (Just s, Just t) ->
            let depart =
                  if maybe False isBoundary src
                    then -- a boundary event sits on its host's bottom border,
                    -- so it steps clear downwards before turning
                      Point (s.bx + s.bw `div` 2) (s.by + s.bh)
                    else Point (s.bx + s.bw) (centreY s)
                arrive = Point t.bx (centreY t)
             in ensureTwo s t . dedupe $
                  [depart] <> viaCorridor corridor gxOut gxIn depart arrive <> [arrive]
          _ -> [Point 0 0, Point 0 0]

  centreY b = b.by + b.bh `div` 2

  -- Out into the gutter, along the free corridor when the two columns are not
  -- adjacent, then into the gutter beside the target. Every turn happens where
  -- nothing is drawn, so a crossing is impossible by construction rather than
  -- unlikely in practice.
  viaCorridor corridor gxOut gxIn depart arrive
    | gxOut == gxIn = [Point gxOut depart.ptY, Point gxOut arrive.ptY]
    | otherwise = case corridor of
        Nothing -> [Point gxOut depart.ptY, Point gxOut arrive.ptY, Point gxIn arrive.ptY]
        Just cy ->
          [ Point gxOut depart.ptY
          , Point gxOut cy
          , Point gxIn cy
          , Point gxIn arrive.ptY
          ]

  dedupe (p : q : rest) | p == q = dedupe (q : rest)
  dedupe (p : rest) = p : dedupe rest
  dedupe [] = []

  ensureTwo s t ps
    | length ps >= 2 = ps
    | otherwise =
        [ Point (s.bx + s.bw `div` 2) (s.by + s.bh `div` 2)
        , Point (t.bx + t.bw `div` 2) (t.by + t.bh `div` 2)
        ]

--------------------------------------------------------------------------------
-- Identifiers
--------------------------------------------------------------------------------

-- | Coerce arbitrary text into an XML @NCName@, which is what a BPMN id has to
-- be. Deterministic and total; collisions are avoided by the caller, which
-- always prefixes a state id or an index.
ncName :: Text -> Text
ncName raw =
  case Text.uncons cleaned of
    Nothing -> "_"
    Just (c, _)
      | isAlpha c || c == '_' -> cleaned
      | otherwise -> "_" <> cleaned
 where
  cleaned = Text.take 40 (Text.map keep raw)
  keep c
    | isAscii c && (isAlphaNum c || c == '-' || c == '_' || c == '.') = c
    | otherwise = '_'
