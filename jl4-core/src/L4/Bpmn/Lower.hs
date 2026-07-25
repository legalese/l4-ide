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
-- 2. An @RAND@ gets a converging @\<parallelGateway\>@ only when its branches
--    /provably/ reconverge on one state and nowhere else. A join that one
--    branch can escape (to @BREACH@, say) is a deadlock in BPMN, so where the
--    condition fails we leave the branches unjoined and say so
--    (@P-NOJOIN@). Nothing is lost by this: a BPMN instance completes
--    only when every token is consumed, so \"all of\" still holds — it is
--    merely implicit rather than drawn.
-- 3. A prohibition is not an activity. It is still drawn as a task, because
--    BPMN has no other shape for it, and the loss is reported as @F1@ at
--    'Blocking' severity.
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
      , scFindings = taskFindings <> boundaryFindings <> danglingFindings
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
            , nodeDoc = Just (restateRule t.transLabel)
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

    -- The LEST edge hangs off the task as an interrupting boundary event. Its
    -- trigger comes from the OBLIGATION's deadline (WITHIN lives on the HENCE
    -- label), not from the LEST edge's own label, which is a bare "timeout".
    (boundary, boundaryFindings) = case (lestOf sid, taskNodes) of
      (Just lestT, host : _) ->
        let deadline = obligation >>= (.transLabel.labelDeadline)
            bid = "Boundary_" <> tag
            (trigger, finds) = boundaryTrigger opts bid lestT.transLabel.labelAction deadline
         in ( Just
                FlowNode
                  { nodeId = bid
                  , nodeName = triggerName trigger lestT.transLabel.labelAction
                  , nodeKind = Boundary host.nodeId trigger
                  , nodeDoc = fmap ("LEST: the obligation is not discharged within " <>) deadline
                  , nodeLane = host.nodeLane
                  }
            , finds
            )
      _ -> (Nothing, [])

    taskFindings = case (obligation, taskNodes) of
      (Just t, tn : _) -> modalityFinding tn t.transLabel <> guardFindings tn t.transLabel
      _ -> []

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
    concat [c.scNodes <> maybeToList c.scBoundary | (_, c) <- chains]

  -- Which state each node came from; needed to tell a flow that leaves a
  -- parallel branch from one that merely happens to end at the same place.
  nodeState :: Map Text StateId
  nodeState =
    Map.fromList
      [ (n.nodeId, sid)
      | (sid, c) <- chains
      , n <- c.scNodes <> maybeToList c.scBoundary
      ]

  entryOf :: StateId -> Maybe Text
  entryOf sid = chainOf sid >>= \c -> (.nodeId) <$> listToMaybe c.scNodes

  nodeOfKind :: (NodeKind -> Bool) -> StateId -> Maybe Text
  nodeOfKind p sid =
    chainOf sid >>= \c -> listToMaybe [n.nodeId | n <- c.scNodes, p n.nodeKind]

  taskOf, gatewayOf :: StateId -> Maybe Text
  taskOf = nodeOfKind (== Task)
  gatewayOf = nodeOfKind \case Gateway _ _ -> True; _ -> False

  boundaryOf :: StateId -> Maybe Text
  boundaryOf sid = chainOf sid >>= \c -> (.nodeId) <$> c.scBoundary

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
          hence =
            [ (src, tgt, t.transLabel.labelGuard)
            | t <- outOf sid
            , t.transType == HenceTransition
            , Just src <- [taskOf sid]
            , Just tgt <- [entryOf t.transTo]
            ]
          lest =
            [ (src, tgt, Nothing)
            | t <- outOf sid
            , t.transType == LestTransition
            , Just src <- [boundaryOf sid]
            , Just tgt <- [entryOf t.transTo]
            ]
          branches =
            [ (src, tgt, Nothing)
            | t <- defaultsOf sid
            , Just src <- [gatewayOf sid <|> lastChainNode sid]
            , Just tgt <- [entryOf t.transTo]
            ]
       in hence <> lest <> branches

    lastChainNode sid = chainOf sid >>= \c -> (.nodeId) <$> listToMaybe (reverse c.scNodes)

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

  reachFrom :: StateId -> Set StateId
  reachFrom = go Set.empty . pure
   where
    go seen [] = seen
    go seen (s : rest)
      | Set.member s seen = go seen rest
      | otherwise = go (Set.insert s seen) (Map.findWithDefault [] s succsOf <> rest)

  -- A converging parallel gateway is correct only if every branch ends at the
  -- same single state and can reach nothing else that stops. Anything weaker
  -- and the join is a token trap.
  addJoin ::
    ([FlowNode], [Edge], [FidelityNote]) ->
    StateId ->
    ([FlowNode], [Edge], [FidelityNote])
  addJoin (nodes, edges, finds) junction =
    case joinTarget of
      Just r
        | Just tgt <- entryOf r
        , disjointBranches ->
            let jid = "Join_" <> Text.pack (show junction)
                inside = Set.insert junction (Set.delete r (Set.unions (map reachFrom branches)))
                fromFan from =
                  maybe False (`Set.member` inside) (Map.lookup from nodeState)
                redirect (edgeFrom, edgeTo, cond)
                  | edgeTo == tgt && fromFan edgeFrom = (True, (edgeFrom, jid, cond))
                  | otherwise = (False, (edgeFrom, edgeTo, cond))
                marked = map redirect edges
                rewired = map snd marked
                joinNode =
                  FlowNode
                    { nodeId = jid
                    , nodeName = ""
                    , nodeKind = Gateway ParallelGateway Converging
                    , nodeDoc = Just "every branch of the RAND must complete"
                    , nodeLane = Nothing
                    }
             in -- A join needs at least two things to join. Fewer means an outer
                -- junction already claimed these edges (nested RANDs sharing a
                -- terminal), and inserting a gateway with one incoming flow — or
                -- none — would be worse than not drawing one at all.
                if length (filter fst marked) >= 2
                  then (nodes <> [joinNode], rewired <> [(jid, tgt, Nothing)], finds)
                  else (nodes, edges, finds <> [noJoinFinding])
      _ -> (nodes, edges, finds <> [noJoinFinding])
   where
    branches = map (.transTo) (defaultsOf junction)

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
      let interiors = [Set.delete r (reachFrom b) | b <- branches, r <- maybeToList joinTarget]
       in and
            [ Set.null (Set.intersection a b)
            | (i, a) <- zip [0 :: Int ..] interiors
            , (j, b) <- zip [0 :: Int ..] interiors
            , i < j
            ]

    noJoinFinding =
      MkFidelityNote
        { code = "P-NOJOIN"
        , severity = Lossy
        , element = fromMaybe ("state " <> Text.pack (show junction)) (gatewayOf junction)
        , range = Nothing
        , message =
            "The "
              <> Text.pack (show (length branches))
              <> " branches of this RAND do not all end at one common state — a \
                 \branch can reach BREACH, or two branches overlap — so no \
                 \converging parallel gateway was invented, because a join a \
                 \branch can escape is a token trap."
        , lost =
            "the conjunction as a drawn gateway; it still holds, because a BPMN \
            \instance ends only once every token is consumed, but the reader \
            \has to know that"
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
      <> [bearerFinding | not (null parties)]
      <> [ruleVersionFinding]

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
          "BPMN has no as-of date, so every threshold and deadline drawn here \
          \is a value someone must remember to edit when the rule changes."
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

triggerName :: BoundaryTrigger -> Text -> Text
triggerName trigger fallback = case trigger of
  TimerAfter iso -> "after " <> iso
  WhenCondition _ -> if Text.null (Text.strip fallback) then "otherwise" else fallback

--------------------------------------------------------------------------------
-- Deadlines
--------------------------------------------------------------------------------

-- | Choose the boundary event's trigger, and say what it cost.
boundaryTrigger ::
  BpmnOptions ->
  Text ->
  -- | the LEST edge's own label, e.g. @timeout@ or @violation@
  Text ->
  -- | the obligation's @WITHIN@ text, if any
  Maybe Text ->
  (BoundaryTrigger, [FidelityNote])
boundaryTrigger opts elemId lestLabel = \case
  Nothing ->
    ( WhenCondition (fallbackCondition lestLabel)
    , [ note
          "P-DEADLINE"
          Blocking
          "This LEST has no deadline, and BPMN has no untriggered boundary \
          \event, so it is drawn as a conditional boundary event rather than a \
          \timer."
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
                <> " carries no unit, because L4's WITHIN does not fix one; it \
                   \is read here as days ("
                <> iso
                <> "), following the day-serial convention of \
                   \libraries/datetime.l4."
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

fallbackCondition :: Text -> Text
fallbackCondition lestLabel
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

layerWidth, taskSlotWidth, rowHeight, lanePadTop, lanePadBottom, minLaneHeight :: Int
layerWidth = 180
taskSlotWidth = 100
rowHeight = 120
lanePadTop = 20
lanePadBottom = 20
minLaneHeight = 140

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

  laneRows lane =
    max 1 $
      maximum
        ( 0
            : [ length [n | n <- placed, laneOf n == lane, rankOfNode n == rank]
              | rank <- [0 .. maxRank]
              ]
        )

  laneHeight lane =
    max minLaneHeight (lanePadTop + laneRows lane * rowHeight + lanePadBottom)

  laneTop lane = poolY + sum [laneHeight l | l <- [0 .. lane - 1]]

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

  waypoints f =
    let sb = Map.lookup f.flowFrom boundsOf
        tb = Map.lookup f.flowTo boundsOf
        fromBoundary = maybe False isBoundary (Map.lookup f.flowFrom byId)
     in case (sb, tb) of
          (Just s, Just t)
            | fromBoundary -> ensureTwo s t (dedupe (downThenAcross s t))
            | otherwise -> ensureTwo s t (dedupe (acrossThen s t))
          _ -> [Point 0 0, Point 0 0]

  acrossThen s t =
    let sy = s.by + s.bh `div` 2
        ty = t.by + t.bh `div` 2
        sx = s.bx + s.bw
        tx = t.bx
     in if sy == ty
          then [Point sx sy, Point tx ty]
          else
            let mx = (sx + tx) `div` 2
             in [Point sx sy, Point mx sy, Point mx ty, Point tx ty]

  downThenAcross s t =
    let sx = s.bx + s.bw `div` 2
        sy = s.by + s.bh
        ty = t.by + t.bh `div` 2
     in [Point sx sy, Point sx ty, Point t.bx ty]

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
