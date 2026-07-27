{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE LambdaCase #-}
-- | State Graph extraction and visualization for L4 regulative rules
--
-- This module extracts state transition graphs from L4 regulative rules
-- (obligations with HENCE/LEST chains) and renders them as GraphViz DOT.
--
-- Inspired by Flood & Goodenough's "Contract as Automaton" model.
--
-- The extraction follows these mappings:
--   - Each obligation chain creates states and transitions
--   - PARTY X MUST/MAY action → transition label
--   - HENCE → success transition (green)
--   - LEST → reparation transition (red, dashed); what reaches it depends on
--     the modal, so its caption does too — see 'lestArmWording'
--   - Fulfilled → terminal success state
--   - Breach → terminal failure state
--   - WITHIN deadline → temporal guard on transition
--   - RAND → an @AllOf@ junction: every branch runs
--   - ROR  → a @OneOf@ junction: exactly one branch runs
module L4.StateGraph
  ( -- * Types
    StateGraph(..)
  , ContractState(..)
  , StateId
  , StateType(..)
  , FanKind(..)
  , Transition(..)
  , TransitionLabel(..)
  , TransitionType(..)
    -- * Options
  , StateGraphOptions(..)
  , defaultStateGraphOptions
    -- * Extraction
  , extractStateGraph
  , extractStateGraphs
    -- * Rendering
  , stateGraphToDot
    -- * Arm vocabulary
  , lestArmWording
  , noTriggerWording
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Text.Lazy as Text.Lazy
import qualified Control.Monad.State.Strict as St

import L4.Syntax
  ( Expr(..)
  , Resolved
  , Module(..)
  , Section(..)
  , TopDecl(..)
  , Decide(..)
  , Deonton(..)
  , RAction(..)
  , DeonticModal(..)
  , Pattern(..)
  , AppForm(..)
  , nameToText
  , getOriginal
  )
import L4.Print (prettyLayout)

-- GraphViz imports
import qualified Data.GraphViz as GV
import qualified Data.GraphViz.Attributes.Complete as GV
import Data.Graph.Inductive.Graph (Node, LNode, LEdge)
import qualified Data.Graph.Inductive.Graph as FGL
import qualified Data.Graph.Inductive.PatriciaTree as FGL

-- | Convert a Resolved name to Text
resolvedToText :: Resolved -> Text
resolvedToText = nameToText . getOriginal

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

-- | Unique identifier for states in the graph
type StateId = Int

-- | A state in the contract automaton
data ContractState = ContractState
  { stateId   :: StateId
  , stateName :: Text      -- ^ Human-readable name (e.g., "purchase template", "Fulfilled")
  , stateType :: StateType
  , stateFan  :: FanKind   -- ^ How this state's outgoing transitions relate
  } deriving (Eq, Show)

-- | Classification of states for rendering
data StateType
  = InitialState           -- ^ Entry point of the contract
  | IntermediateState      -- ^ Normal intermediate state
  | TerminalFulfilled      -- ^ Success terminal (double circle, green)
  | TerminalBreach         -- ^ Failure terminal (double circle, red)
  deriving (Eq, Show)

-- | How the transitions leaving a state relate to one another.
--
-- A 'Linear' state is an ordinary automaton state: its outgoing transitions
-- are the HENCE\/LEST alternatives of a single obligation, and exactly one of
-- them fires depending on what the party does.
--
-- A junction ('AllOf' or 'OneOf') is not an obligation at all but a control
-- point introduced by regulative @RAND@ \/ @ROR@. Its outgoing transitions are
-- unlabelled and each leads to the /entry state of one branch/, so the branch
-- set is exactly the junction's out-edges — which is what a downstream
-- exporter needs in order to choose a parallel versus an exclusive gateway.
--
-- Without this the two operators are indistinguishable in the IR: both simply
-- fan transitions out of one state, and a reader has to supply the intent.
data FanKind
  = Linear   -- ^ Ordinary state; not a junction
  | AllOf    -- ^ @RAND@: every branch is entered (concurrent obligations)
  | OneOf    -- ^ @ROR@: exactly one branch is entered (choice)
  deriving (Eq, Show)

-- | A transition between states
data Transition = Transition
  { transFrom  :: StateId
  , transTo    :: StateId
  , transLabel :: TransitionLabel
  , transType  :: TransitionType
  } deriving (Eq, Show)

-- | Label information for a transition
data TransitionLabel = TransitionLabel
  { labelParty    :: Maybe Text    -- ^ Party responsible (e.g., "buyer", "seller")
  , labelModal    :: Maybe DeonticModal  -- ^ Deontic modal (MUST, MAY, etc.)
  , labelAction   :: Text          -- ^ Action description
  , labelDeadline :: Maybe Text    -- ^ Temporal constraint (e.g., "30 days")
  , labelGuard    :: Maybe Text    -- ^ PROVIDED condition
  } deriving (Eq, Show)

-- | Classification of transitions for rendering
data TransitionType
  = HenceTransition        -- ^ Success path (solid, green)
  | LestTransition         -- ^ Reparation\/failure path (dashed, red). What
                           --   /reaches/ it depends on the modal — see
                           --   'lestArmWording'.
  | DefaultTransition      -- ^ Neutral transition
  deriving (Eq, Show)

-- | The caption for an arm that /nothing can take/.
--
-- Three of the four modals reach their @LEST@ arm by the deadline running out
-- (see 'lestArmWording'), so a rule with no @WITHIN@ leaves that arm with no
-- trigger at all. The spec says so — the LEST table in
-- @doc\/reference\/regulative\/README.md@ defines every non-@SHANT@ trigger as
-- the deadline passing — and the evaluator agrees: @Contract4@ takes the
-- @Left Nothing@ branch on a missing @WITHIN@ and skips the timing step
-- entirely, so @Contract5@, the only frame that consults @lest@ on expiry,
-- never runs. Measured, on @jl4:exe:l4 run@:
--
-- @
-- PARTY Alice MUST pay LEST (PARTY Bob MUST refund WITHIN 5)
-- \#TRACE ... AT 0 WITH (\`WAIT UNTIL\` 1000)
--   ==> PARTY Alice MUST pay HENCE FULFILLED LEST ...   -- residual, not Bob's refund
-- @
--
-- with the same rule plus @WITHIN 30@ yielding @PARTY Bob MUST refund WITHIN 5@,
-- i.e. the arm taken. The same holds for @MAY@ and for @DO@; @SHANT@ is the
-- exception, because its trigger is the act, not the clock.
--
-- The edge is still drawn, because the drafter wrote a @LEST@ body and dropping
-- the edge would orphan every state extracted from it. What it must not do is
-- name an event: @\"timeout\"@ asserts a deadline the rule never set, and
-- @\"not performed\"@ asserts a transition the runtime never makes. Naming the
-- absence is the only caption here that survives being checked.
noTriggerWording :: Text
noTriggerWording = "unreachable: no WITHIN"

-- | What reaching an obligation's @LEST@ arm /means/, in the fewest words that
-- are true. This is the caption on the @LEST@ edge.
--
-- It is __not__ the whole vocabulary of the pipeline, and claiming so would be
-- the kind of tidy overstatement this function exists to remove.
-- 'L4.Bpmn.Lower' has words of its own for a prohibition — @triggerName@,
-- @boundaryDoc@, @taskArmNote@ — and it needs them, because @raceArms@ puts a
-- @SHANT@'s boundary event on the /HENCE/ arm, which is a different arm from
-- the one captioned here. What this function owns is the @LEST@ arm's own
-- words, everywhere they appear: @Lower@ imports it for the synthesised
-- @MAY@-lapse timer and shares 'noTriggerWording' with it, rather than
-- respelling either.
--
-- Both arguments are load-bearing.
--
-- The __modal__ decides which event takes the arm at all
-- (@L4.EvaluateLazy.Machine@, and the LEST table in
-- @doc\/reference\/regulative\/README.md@):
--
-- * @MUST@ \/ @DO@: the deadline passes without the act — a missed deadline;
-- * @MAY@: the deadline passes without the permission being exercised, which
--   is not a failure at all (its default consequence is @FULFILLED@);
-- * @SHANT@: __the prohibited act is performed__. Nothing to do with time.
--   Calling this a timeout says the opposite of what the rule says, since for
--   a prohibition it is the deadline running out that means /compliance/.
--
-- The __deadline__ decides whether there is an arm to caption at all. Only
-- @SHANT@ short-circuits it, and only because @SHANT@ is the one modal whose
-- trigger is not temporal: measured, a prohibition with no @WITHIN@ still
-- reaches @LEST@ the moment the act is performed. For the other three, no
-- @WITHIN@ means no trigger — see 'noTriggerWording' for the measurement.
lestArmWording ::
  DeonticModal ->
  -- | the obligation's @WITHIN@, if it has one. Only its presence is read, so
  -- this is deliberately polymorphic: callers pass the deadline expression
  -- itself and nobody has to pre-render it just to be asked a yes\/no question.
  Maybe deadline ->
  Text
lestArmWording DMustNot _        = "violation"
lestArmWording DMay     (Just _) = "lapses"
lestArmWording _        (Just _) = "timeout"
lestArmWording _        Nothing  = noTriggerWording

-- | The complete state graph for a contract
data StateGraph = StateGraph
  { sgName         :: Text           -- ^ Name of the contract/rule
  , sgStates       :: [ContractState]
  , sgTransitions  :: [Transition]
  , sgInitialState :: StateId
  } deriving (Eq, Show)

-- | Options for state graph rendering
data StateGraphOptions = StateGraphOptions
  { showDeadlines   :: Bool   -- ^ Include temporal constraints on edges
  , showGuards      :: Bool   -- ^ Include PROVIDED conditions
  , compactLabels   :: Bool   -- ^ Use shorter labels
  , showModal       :: Bool   -- ^ Show deontic modal in labels
  } deriving (Eq, Show)

-- | Default options with all information shown
defaultStateGraphOptions :: StateGraphOptions
defaultStateGraphOptions = StateGraphOptions
  { showDeadlines = True
  , showGuards    = True
  , compactLabels = False
  , showModal     = True
  }

--------------------------------------------------------------------------------
-- Extraction State Monad
--------------------------------------------------------------------------------

-- | State for graph extraction
data ExtractState = ExtractState
  { esNextId      :: StateId
  , esStates      :: [ContractState]
  , esTransitions :: [Transition]
  } deriving (Show)

type ExtractM = St.State ExtractState

-- | Create a new state and return its ID. States start out 'Linear'; a state
-- becomes a junction only when 'markFan' is applied to it.
newState :: Text -> StateType -> ExtractM StateId
newState name stype = do
  st <- St.get
  let sid = st.esNextId
      s = ContractState sid name stype Linear
  St.put st { esNextId = sid + 1, esStates = s : st.esStates }
  pure sid

-- | Turn an existing state into a junction of the given kind.
markFan :: StateId -> FanKind -> ExtractM ()
markFan sid kind = St.modify $ \st ->
  st { esStates = map retag st.esStates }
  where
    retag s
      | s.stateId == sid = s { stateFan = kind }
      | otherwise        = s

-- | Add a transition
addTransition :: StateId -> StateId -> TransitionLabel -> TransitionType -> ExtractM ()
addTransition fromId toId label ttype = St.modify $ \st ->
  st { esTransitions = Transition fromId toId label ttype : st.esTransitions }

-- | Find or create a terminal state
getTerminalState :: Text -> StateType -> ExtractM StateId
getTerminalState name stype = do
  st <- St.get
  case find (\s -> s.stateName == name && s.stateType == stype) st.esStates of
    Just s  -> pure s.stateId
    Nothing -> newState name stype

--------------------------------------------------------------------------------
-- AST Extraction
--------------------------------------------------------------------------------

-- | Extract all state graphs from a module
extractStateGraphs :: Module Resolved -> [StateGraph]
extractStateGraphs (MkModule _ _ section) =
  extractFromSection section

-- | Extract the first state graph from a module (convenience function)
extractStateGraph :: Module Resolved -> Maybe StateGraph
extractStateGraph m = case extractStateGraphs m of
  (sg:_) -> Just sg
  []     -> Nothing

-- | Extract state graphs from a section
extractFromSection :: Section Resolved -> [StateGraph]
extractFromSection (MkSection _ mName _ decls) =
  let sectionName = maybe "contract" resolvedToText mName
  in concatMap (extractFromTopDecl sectionName) decls

-- | Extract from a top-level declaration
extractFromTopDecl :: Text -> TopDecl Resolved -> [StateGraph]
extractFromTopDecl _contextName = \case
  Decide _ (MkDecide _ _ (MkAppForm _ name _ _) body) ->
    case findRegulativeExpr body of
      Just regExpr -> [runExtraction (resolvedToText name) regExpr]
      Nothing      -> []
  Section _ sec -> extractFromSection sec
  _ -> []

-- | Find a regulative expression in an expression tree
findRegulativeExpr :: Expr Resolved -> Maybe (Expr Resolved)
findRegulativeExpr expr = case expr of
  Regulative{} -> Just expr
  RAnd{}       -> Just expr
  ROr{}        -> Just expr
  Where _ e _  -> findRegulativeExpr e
  LetIn _ _ e  -> findRegulativeExpr e
  _            -> Nothing

-- | Run the extraction monad and build a StateGraph
runExtraction :: Text -> Expr Resolved -> StateGraph
runExtraction name expr =
  let initialState = ExtractState
        { esNextId = 0
        , esStates = []
        , esTransitions = []
        }
      finalState = St.execState (extractExpr Nothing expr) initialState
  in StateGraph
       { sgName = name
       , sgStates = reverse finalState.esStates
       , sgTransitions = reverse finalState.esTransitions
       , sgInitialState = 0  -- First created state is initial
       }

-- | Extract states and transitions from an expression
-- The Maybe StateId is the "current" state we're transitioning from
extractExpr :: Maybe StateId -> Expr Resolved -> ExtractM ()
extractExpr mFromState expr = case expr of
  Regulative _ obl -> extractDeonton mFromState obl

  -- Parallel composition: every branch must be fulfilled.
  RAnd{} -> extractFan AllOf mFromState (flattenRAnd expr)

  -- Choice: exactly one branch is taken.
  ROr{}  -> extractFan OneOf mFromState (flattenROr expr)

  Where _ e _ -> extractExpr mFromState e
  LetIn _ _ e -> extractExpr mFromState e

  -- Terminal states referenced by name
  App _ name [] | isFulfilled name -> do
    _ <- getTerminalState "Fulfilled" TerminalFulfilled
    pure ()

  Breach _ _ _ -> do
    _ <- getTerminalState "Breach" TerminalBreach
    pure ()

  _ -> pure ()  -- Skip other expressions

-- | Check if a name refers to the FULFILLED terminal.
--
-- The keyword is spelled @FULFILLED@ in source; the builtin behind it is
-- @fulfil@, renamed for presentation (see 'L4.TypeCheck.Environment'). Neither
-- spelling is @\"Fulfilled\"@, which is what this predicate used to compare
-- against — so an explicit @HENCE FULFILLED@ never matched, fell through to
-- the \"unknown target\" case, and produced a dangling intermediate state
-- called @next@ instead of an edge to the shared terminal. The mixed-case
-- spelling is kept only because it costs nothing.
isFulfilled :: Resolved -> Bool
isFulfilled name = resolvedToText name `elem` ["FULFILLED", "fulfil", "Fulfilled"]

--------------------------------------------------------------------------------
-- Junctions (RAND / ROR)
--------------------------------------------------------------------------------

-- | Flatten an associative chain of @RAND@ into its branches, so that
-- @a RAND b RAND c@ yields one three-way junction rather than two nested
-- two-way ones. Works for either associativity.
flattenRAnd :: Expr Resolved -> [Expr Resolved]
flattenRAnd = \case
  RAnd _ e1 e2 -> flattenRAnd e1 <> flattenRAnd e2
  e            -> [e]

-- | As 'flattenRAnd', for @ROR@.
flattenROr :: Expr Resolved -> [Expr Resolved]
flattenROr = \case
  ROr _ e1 e2 -> flattenROr e1 <> flattenROr e2
  e           -> [e]

-- | Extract a regulative @RAND@ \/ @ROR@ as an explicit junction.
--
-- The state we arrive in /becomes/ the junction — arriving somewhere and then
-- splitting is one event, not two — and each branch gets its own entry state
-- hanging off it. That keeps the branch set recoverable: the junction's
-- out-edges are exactly the branches, one apiece, and nothing else.
extractFan :: FanKind -> Maybe StateId -> [Expr Resolved] -> ExtractM ()
extractFan kind mFromState branches = do
  junction <- case mFromState of
    Just sid -> pure sid
    Nothing  -> newState "initial" InitialState
  markFan junction kind
  traverse_ (extractBranch junction) branches

-- | Extract one branch of a junction, wiring the junction to its entry state.
extractBranch :: StateId -> Expr Resolved -> ExtractM ()
extractBranch junction branch = case classifyTarget branch of
  -- A branch that is just FULFILLED or BREACH has no work in it, so it needs
  -- no entry state: the junction points straight at the terminal.
  TargetFulfilled -> do
    fulfilledId <- getTerminalState "Fulfilled" TerminalFulfilled
    addTransition junction fulfilledId fanLabel DefaultTransition

  TargetBreach -> do
    breachId <- getTerminalState "Breach" TerminalBreach
    addTransition junction breachId fanLabel DefaultTransition

  TargetDeonton obl -> do
    entryId <- newState (describeDeonton obl) IntermediateState
    addTransition junction entryId fanLabel DefaultTransition
    extractDeonton (Just entryId) obl

  TargetOther -> do
    entryId <- newState (branchStateName branch) IntermediateState
    addTransition junction entryId fanLabel DefaultTransition
    -- A nested RAND/ROR marks this very state as the inner junction.
    extractExpr (Just entryId) branch

-- | Name for the entry state of a branch that is neither a bare obligation
-- nor a terminal.
branchStateName :: Expr Resolved -> Text
branchStateName expr = case expr of
  RAnd{}      -> "all of"
  ROr{}       -> "one of"
  App _ n _   -> resolvedToText n
  Where _ e _ -> branchStateName e
  LetIn _ _ e -> branchStateName e
  _           -> "branch"

-- | The edge from a junction to a branch entry carries no action of its own:
-- a junction is a control point, not a task.
fanLabel :: TransitionLabel
fanLabel = TransitionLabel
  { labelParty    = Nothing
  , labelModal    = Nothing
  , labelAction   = ""
  , labelDeadline = Nothing
  , labelGuard    = Nothing
  }

-- | Extract an obligation as a state transition
extractDeonton :: Maybe StateId -> Deonton Resolved -> ExtractM ()
extractDeonton mFromState MkDeonton{..} = do
  -- Create or get the source state
  fromState <- case mFromState of
    Just sid -> pure sid
    Nothing  -> newState "initial" InitialState

  -- Build the transition label
  let partyText = Just $ prettyLayout party
      modalVal  = Just (action.modal)
      actionText = prettyPattern action.action
      deadlineText = fmap prettyLayout due
      guardText = fmap prettyLayout action.provided

      label = TransitionLabel
        { labelParty    = partyText
        , labelModal    = modalVal
        , labelAction   = actionText
        , labelDeadline = deadlineText
        , labelGuard    = guardText
        }

      -- The caption for whichever LEST arm this obligation turns out to have.
      -- It carries the modal too: without it a consumer holding only this edge
      -- cannot tell a missed deadline from a prohibition that was breached,
      -- which is the whole of smucclaw/l4-ide#927. The party, deadline and
      -- guard are deliberately absent — they belong to the obligation, which
      -- the HENCE edge already restates, and repeating them here would read as
      -- a second, contradictory copy of the rule.
      lestLabel = TransitionLabel
        { labelParty    = Nothing
        , labelModal    = modalVal
        , labelAction   = lestArmWording action.modal due
        , labelDeadline = Nothing
        , labelGuard    = Nothing
        }

      defaultToBreach = do
        breachId <- getTerminalState "Breach" TerminalBreach
        addTransition fromState breachId lestLabel LestTransition

  -- Handle HENCE (success path)
  case hence of
    Just henceExpr -> do
      case classifyTarget henceExpr of
        TargetFulfilled -> do
          fulfilledId <- getTerminalState "Fulfilled" TerminalFulfilled
          addTransition fromState fulfilledId label HenceTransition

        TargetBreach -> do
          breachId <- getTerminalState "Breach" TerminalBreach
          addTransition fromState breachId label HenceTransition

        TargetDeonton nextObl -> do
          -- Create intermediate state for the next obligation
          let nextStateName = describeDeonton nextObl
          nextStateId <- newState nextStateName IntermediateState
          addTransition fromState nextStateId label HenceTransition
          -- Recursively extract the next obligation
          extractDeonton (Just nextStateId) nextObl

        TargetOther -> do
          -- Unknown target - create generic next state
          nextStateId <- newState "next" IntermediateState
          addTransition fromState nextStateId label HenceTransition
          extractExpr (Just nextStateId) henceExpr

    -- No HENCE specified. Every modal defaults it to FULFILLED — see the HENCE
    -- table in doc/reference/regulative/README.md and @fromMaybe fulfilExpr@ in
    -- L4.EvaluateLazy.Machine — so there is one branch, not four. (This used to
    -- be a @case@ on the modal with two byte-identical arms, split MAY from the
    -- rest, and differing only in a comment.)
    --
    -- The seam a reader might come looking for is not here. For a prohibition
    -- this edge is taken by the deadline /expiring/ with the act not performed,
    -- so its caption reads backwards — but the caption is 'label', which is the
    -- obligation restated, and downstream that is the record BPMN builds its
    -- task name and lane from ("SHANT notify"). Rewording it here would rename
    -- elements in another exporter. L4.Bpmn.Lower names the prohibition's
    -- compliance arm itself; see 'L4.Bpmn.Lower.raceArms'.
    Nothing -> do
      fulfilledId <- getTerminalState "Fulfilled" TerminalFulfilled
      addTransition fromState fulfilledId label HenceTransition

  -- Handle LEST (the reparation path). Which of these four targets it points at
  -- is orthogonal to what takes the arm, so all four share one caption, derived
  -- from the modal by 'lestArmWording'. They used to share the literal word
  -- "timeout" instead, which on a prohibition asserted the exact opposite of
  -- the rule.
  case lest of
    Just lestExpr -> do
      case classifyTarget lestExpr of
        TargetFulfilled -> do
          fulfilledId <- getTerminalState "Fulfilled" TerminalFulfilled
          addTransition fromState fulfilledId lestLabel LestTransition

        TargetBreach -> do
          breachId <- getTerminalState "Breach" TerminalBreach
          addTransition fromState breachId lestLabel LestTransition

        TargetDeonton nextObl -> do
          let nextStateName = describeDeonton nextObl
          nextStateId <- newState nextStateName IntermediateState
          addTransition fromState nextStateId lestLabel LestTransition
          extractDeonton (Just nextStateId) nextObl

        TargetOther -> do
          nextStateId <- newState "failure" IntermediateState
          addTransition fromState nextStateId lestLabel LestTransition
          extractExpr (Just nextStateId) lestExpr

    Nothing -> do
      -- No LEST specified - use default based on modal
      case action.modal of
        -- MAY without LEST: the permission lapses to FULFILLED, and for the
        -- common shape — no HENCE, or HENCE FULFILLED — that is where the HENCE
        -- edge already goes, so there is no second arrow to draw.
        --
        -- NOTE (not fixed here): when a bare MAY's HENCE points at another
        -- OBLIGATION the two arms genuinely part company, and this draws only
        -- one of them. Measured:
        --
        --   PARTY Alice MAY pay WITHIN 5 HENCE (PARTY Bob MUST deliver WITHIN 10)
        --     (`WAIT UNTIL` 100)          ==> FULFILLED
        --     PARTY Alice DOES pay AT 3   ==> PARTY Bob MUST deliver WITHIN 10
        --
        -- so expiry reaches FULFILLED (@fromMaybe fulfilExpr lest@) while HENCE
        -- reaches Bob's obligation, and the graph shows no route to FULFILLED at
        -- all. L4.Bpmn.Lower inherits the gap and makes it worse, sending its
        -- synthesised lapse timer "wherever HENCE lands" — which in this shape
        -- is the wrong place. Fixing it means emitting a real lapse edge here
        -- and retiring that synthesis, which moves BPMN output for every
        -- permission; it is a separate change from smucclaw/l4-ide#927.
        DMay -> pure ()
        -- MUST/SHANT without LEST default to Breach; only the way in differs,
        -- and 'lestArmWording' is where that difference is spelled.
        DMust -> defaultToBreach
        DMustNot -> defaultToBreach
        -- DO is documented as requiring an explicit LEST, and this used to take
        -- the documentation at its word and draw nothing. The evaluator does not
        -- require it: @Contract5@'s @_ -> case lest of Nothing -> ValBreached@
        -- covers DDo alongside DMust, and measured,
        --
        --   PARTY Alice DO pay WITHIN 5    (`WAIT UNTIL` 100)  ==> DEONTIC BREACHED
        --
        -- so the graph drew a rule whose only outcome was Fulfilled for a rule
        -- that breaches. It is the same defect as the caption bug one level up —
        -- the picture contradicting the runtime — so it is fixed the same way,
        -- and 'lestArmWording' gives DO the MUST wording it shares.
        DDo -> defaultToBreach

-- | Classification of HENCE/LEST targets
data Target
  = TargetFulfilled
  | TargetBreach
  | TargetDeonton (Deonton Resolved)
  | TargetOther

-- | Classify what a HENCE/LEST expression points to
classifyTarget :: Expr Resolved -> Target
classifyTarget = \case
  App _ name [] | isFulfilled name -> TargetFulfilled
  Breach{} -> TargetBreach
  Regulative _ obl -> TargetDeonton obl
  Where _ e _ -> classifyTarget e
  LetIn _ _ e -> classifyTarget e
  _ -> TargetOther

-- | Generate a descriptive name for an obligation (for intermediate states)
describeDeonton :: Deonton Resolved -> Text
describeDeonton MkDeonton{..} =
  let partyT = prettyLayout party
      modalT = case action.modal of
        DMust    -> "must"
        DMay     -> "may"
        DMustNot -> "must not"
        DDo      -> "do"
      actionT = prettyPattern action.action
  in partyT <> " " <> modalT <> " " <> actionT

-- | Pretty-print a pattern to text
prettyPattern :: Pattern Resolved -> Text
prettyPattern = \case
  PatVar _ n      -> resolvedToText n
  PatApp _ n args -> resolvedToText n <> if null args then "" else " ..."
  PatCons _ h _   -> prettyPattern h <> " ..."
  PatExpr _ e     -> prettyLayout e
  PatLit _ lit    -> prettyLayout lit

--------------------------------------------------------------------------------
-- GraphViz DOT Generation
--------------------------------------------------------------------------------

-- | Node attributes for FGL graph
data NodeAttrs = NodeAttrs
  { naLabel     :: Text
  , naFillColor :: Text
  , naShape     :: Text
  , naStyle     :: Text
  } deriving (Eq, Show)

-- | Edge attributes for FGL graph
data EdgeAttrs = EdgeAttrs
  { eaLabel :: Text
  , eaColor :: Text
  , eaStyle :: Text
  } deriving (Eq, Show)

type ContractGraph = FGL.Gr NodeAttrs EdgeAttrs

-- | Convert a StateGraph to GraphViz DOT format
stateGraphToDot :: StateGraphOptions -> StateGraph -> Text
stateGraphToDot opts sg =
  let graph = buildFGLGraph opts sg
      dotGraph = graphToDot opts sg graph
  in Text.Lazy.toStrict $ GV.printDotGraph dotGraph

-- | Build an FGL graph from a StateGraph
buildFGLGraph :: StateGraphOptions -> StateGraph -> ContractGraph
buildFGLGraph opts StateGraph{..} =
  let fanOf sid = maybe Linear (.stateFan) (find (\s -> s.stateId == sid) sgStates)
      nodes = map (stateToNode opts) sgStates
      edges = map (\t -> transitionToEdge opts (fanOf t.transFrom) t) sgTransitions
  in FGL.mkGraph nodes edges

-- | Convert a ContractState to an FGL node
stateToNode :: StateGraphOptions -> ContractState -> LNode NodeAttrs
stateToNode _ ContractState{..} =
  let (fillColor, shape, style) = case (stateFan, stateType) of
        -- Junctions are drawn as diamonds and say outright which kind they
        -- are; the fan-out is the whole point of the node.
        (AllOf, _)                    -> (allOfColor, "diamond", "filled")
        (OneOf, _)                    -> (oneOfColor, "diamond", "filled")
        (Linear, InitialState)        -> ("#e8f4fd", "ellipse", "filled")
        (Linear, IntermediateState)   -> ("#ffffff", "ellipse", "filled")
        (Linear, TerminalFulfilled)   -> ("#d4edda", "doublecircle", "filled")
        (Linear, TerminalBreach)      -> ("#f8d7da", "doublecircle", "filled")
      attrs = NodeAttrs
        { naLabel     = stateName <> fanSuffix stateFan
        , naFillColor = fillColor
        , naShape     = shape
        , naStyle     = style
        }
  in (stateId, attrs)

-- | Fill colour for an @RAND@ junction (violet).
allOfColor :: Text
allOfColor = "#e6dcf5"

-- | Fill colour for an @ROR@ junction (amber).
oneOfColor :: Text
oneOfColor = "#fde8cc"

-- | The junction kind, spelled out on the node label so no reader has to
-- infer it from the shape alone.
fanSuffix :: FanKind -> Text
fanSuffix = \case
  Linear -> ""
  AllOf  -> "\nALL OF"
  OneOf  -> "\nONE OF"

-- | Convert a Transition to an FGL edge. The 'FanKind' is that of the
-- transition's source state: edges leaving a junction are branch selections,
-- not obligations, and are drawn to match the junction.
transitionToEdge :: StateGraphOptions -> FanKind -> Transition -> LEdge EdgeAttrs
transitionToEdge opts fromFan Transition{..} =
  let label = formatTransitionLabel opts transLabel
      (color, style) = case (transType, fromFan) of
        (DefaultTransition, AllOf) -> (allOfEdgeColor, "solid")  -- Violet: every branch
        (DefaultTransition, OneOf) -> (oneOfEdgeColor, "dotted") -- Amber: one branch
        (HenceTransition, _)       -> ("#28a745", "solid")       -- Green for success
        (LestTransition, _)        -> ("#dc3545", "dashed")      -- Red dashed for failure
        (DefaultTransition, _)     -> ("#6c757d", "solid")       -- Gray for neutral
      attrs = EdgeAttrs
        { eaLabel = label
        , eaColor = color
        , eaStyle = style
        }
  in (transFrom, transTo, attrs)

-- | Edge colour out of an @RAND@ junction.
allOfEdgeColor :: Text
allOfEdgeColor = "#6f42c1"

-- | Edge colour out of an @ROR@ junction.
oneOfEdgeColor :: Text
oneOfEdgeColor = "#e8850c"

-- | Format a transition label for display
formatTransitionLabel :: StateGraphOptions -> TransitionLabel -> Text
formatTransitionLabel opts TransitionLabel{..} =
  let -- The modal is a qualifier on a party's action — "Alice MUST pay" — so it
      -- is drawn only where there is a party to qualify. A LEST edge carries the
      -- modal for consumers that hold only that edge, but its caption is not a
      -- restatement of the rule; it names what became of it. "SHANT violation"
      -- would read as a second and contradictory copy of the obligation.
      modalPart
        | not opts.showModal = Nothing
        | isNothing labelParty = Nothing
        | otherwise = fmap formatModal labelModal
      parts = catMaybes
        [ labelParty
        , modalPart
        , Just labelAction
        , if opts.showDeadlines then fmap (\d -> "[" <> d <> "]") labelDeadline else Nothing
        , if opts.showGuards then fmap (\g -> "IF " <> g) labelGuard else Nothing
        ]
  in Text.intercalate " " parts

-- | Format a deontic modal for display
formatModal :: DeonticModal -> Text
formatModal = \case
  DMust    -> "MUST"
  DMay     -> "MAY"
  DMustNot -> "SHANT"
  DDo      -> "DO"

-- | Convert FGL graph to GraphViz DotGraph
graphToDot :: StateGraphOptions -> StateGraph -> ContractGraph -> GV.DotGraph Node
graphToDot _opts StateGraph{..} graph =
  GV.graphToDot params graph
  where
    params = GV.nonClusteredParams
      { GV.globalAttributes =
          [ GV.GraphAttrs
              [ GV.RankDir GV.FromTop
              , GV.Label (GV.StrLabel (Text.Lazy.fromStrict sgName))
              , GV.LabelLoc GV.VTop
              , GV.FontName "Helvetica"
              , GV.FontSize 14
              ]
          , GV.NodeAttrs
              [ GV.FontName "Helvetica"
              , GV.FontSize 11
              ]
          , GV.EdgeAttrs
              [ GV.FontName "Helvetica"
              , GV.FontSize 10
              ]
          ]
      , GV.fmtNode = \(_, attrs) ->
          [ GV.toLabel attrs.naLabel
          , GV.FillColor [GV.toWC (GV.X11Color GV.White)]
          , GV.style (parseStyle attrs.naStyle)
          , GV.Shape (parseShape attrs.naShape)
          , GV.FillColor [GV.toWC (parseColor attrs.naFillColor)]
          ]
      , GV.fmtEdge = \(_, _, attrs) ->
          [ GV.toLabel attrs.eaLabel
          , GV.Color [GV.toWC (parseColor attrs.eaColor)]
          , GV.style (parseEdgeStyle attrs.eaStyle)
          ]
      }

-- | Parse a style string
parseStyle :: Text -> GV.Style
parseStyle "filled" = GV.filled
parseStyle _        = GV.filled

-- | Parse an edge style string
parseEdgeStyle :: Text -> GV.Style
parseEdgeStyle "dashed" = GV.dashed
parseEdgeStyle "dotted" = GV.dotted
parseEdgeStyle _        = GV.solid

-- | Parse a shape string
parseShape :: Text -> GV.Shape
parseShape "doublecircle" = GV.DoubleCircle
parseShape "box"          = GV.BoxShape
parseShape "diamond"      = GV.DiamondShape
parseShape _              = GV.Ellipse

-- | Parse a hex color to GraphViz color
parseColor :: Text -> GV.Color
parseColor hex = case Text.unpack hex of
  ('#':r1:r2:g1:g2:b1:b2:[]) ->
    let r = read ("0x" ++ [r1, r2]) :: Int
        g = read ("0x" ++ [g1, g2]) :: Int
        b = read ("0x" ++ [b1, b2]) :: Int
    in GV.RGB (fromIntegral r) (fromIntegral g) (fromIntegral b)
  _ -> GV.X11Color GV.Gray
