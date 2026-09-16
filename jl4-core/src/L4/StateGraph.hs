{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE LambdaCase #-}
-- | State Graph extraction for L4 regulative rules
--
-- This module extracts state transition graphs from L4 regulative rules
-- (obligations with HENCE/LEST chains). Rendering them as GraphViz DOT is
-- "L4.StateGraph.Dot"'s job, and the dominator query over them is
-- "L4.StateGraph.Dominators"'s; this module is the IR they both read.
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
--   - IF/THEN/ELSE over regulative arms → a @OneOf@ junction whose branch
--     edges carry the guard that selects them (see 'guardedIfBranches')
--   - a @HENCE@ \/ @LEST@ into a named rule → an edge into that rule's own
--     entry state, drawn once per path however many arms on that path point
--     at it (the sibling branches of a @RAND@ \/ @ROR@ each draw their own
--     copy, see 'extractFan'); back into the rule being extracted, that is
--     the initial state, so a renewing duty is a cycle rather than a
--     dangling stub (see 'wireTarget')
--   - every obligation edge carries the source range of its @RAction@
--     ('labelSite'): the static half of the correlation key that lines a
--     drawn edge up with the step the evaluator logs for it
--   - EVERY … → ONE transition labelled with the quantifier (the cast is a
--     run-time fact, R-T6), whose join line — @ONCE …@ barrier or @UPON EACH@
--     fork — travels structurally in 'labelQuantifier' and is drawn on the edge
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
  , BranchGuard(..)
  , GuardAtom(..)
  , branchGuardAtoms
  , renderBranchGuard
  , Quantifier(..)
  , JoinLabel(..)
  , JoinLabelKind(..)
  , memberDeadline
  , thresholdText
    -- * Extraction
  , extractStateGraph
  , extractStateGraphs
    -- * Arm vocabulary
  , lestArmWording
  , noTriggerWording
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Text as Text
import Control.Applicative ((<|>))
import qualified Control.Monad.State.Strict as St

import L4.Annotation (HasSrcRange (..))
import L4.Parser.SrcSpan (SrcRange)
import L4.Syntax
  ( Expr(..)
  , Resolved
  , Module(..)
  , Section(..)
  , TopDecl(..)
  , Decide(..)
  , Deonton(..)
  , Deadline(..)
  , Subject(..)
  , Join(..)
  , Threshold(..)
  , RAction(..)
  , DeonticModal(..)
  , Pattern(..)
  , AppForm(..)
  , Unique
  , unqualifiedNameToText
  , getOriginal
  , getUnique
  )
import L4.Print (LayoutPrinter (..), docText, prettyLayout)

-- | Convert a Resolved name to Text.
--
-- Section qualification is dropped: an @Action@ constructor declared under
-- @§§ Parties and acts@ would otherwise draw as
-- @SEC Regulation Crowdfunding — 17 CFR Part 227.Parties and acts.file a Form
-- C-AR annual report@ on every node and every edge, which is a heading, a
-- subheading and then — eventually — the act. See 'unqualifiedNameToText'.
resolvedToText :: Resolved -> Text
resolvedToText = unqualifiedNameToText . getOriginal

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
  , labelOpening  :: Maybe Text
    -- ^ The window's OPENING edge, the body of the @AFTER@ as written
    -- (@3@, @3 OF THE JOIN@, a date) — EVERY-EACH-QUANTIFIER-SPEC §5.1.2,
    -- 2026-09-16. Carried so no consumer can drop it silently; the BPMN
    -- lowering reports it as not drawn ('L4.Bpmn.Lower.openingFindings').
  , labelDeadline :: Maybe Text
    -- ^ Temporal constraint, the window's CLOSING edge: the body of the
    -- @WITHIN@ as written (e.g., "30", "5 OF THE JOIN"), or the whole
    -- @BEFORE date@ clause, keyword and all, so that a consumer reading it
    -- as a duration sees at once that it is not one.
  , labelGuard    :: Maybe Text    -- ^ PROVIDED condition
  , labelBranch   :: Maybe BranchGuard
    -- ^ The @IF@-chain arm this edge came from, kept in pieces rather than only
    -- as the flattened 'labelGuard' text.
    --
    -- __Only an @IF@ junction sets it__; a @RAND@ \/ @ROR@ branch edge and an
    -- obligation's own @PROVIDED@ both leave it 'Nothing'. When it is set,
    -- @'renderBranchGuard' == 'labelGuard'@ by construction, so nothing here
    -- is a second, drift-prone spelling of the text — see 'guardedIfBranches'.
    --
    -- It exists because a consumer that has to /resolve/ a guard cannot work
    -- from the flattened string: @PROCESS-TRACK.md@ §8.3's BPMN→DMN wiring has
    -- to know which conjuncts are negations of the arms above, and which
    -- @DECIDE@ each conjunct applies, and both facts are destroyed by
    -- @intercalate " AND "@.
  , labelQuantifier :: Maybe Quantifier
    -- ^ Set on the @HENCE@ edge of an @EVERY@ obligation and nowhere else: a
    -- @PARTY@ rule, a @LEST@ caption and a junction's branch edge all leave it
    -- 'Nothing'. It is what makes a barrier and a fork different graphs; see
    -- 'JoinLabelKind'.
  , labelSite :: Maybe SrcRange
    -- ^ @rangeOf@ the 'RAction' this edge was extracted from — the same
    -- range the evaluator stamps on the step it logs for that obligation
    -- (@nkSite@ in "L4.EvaluateLazy.DeonticStep", set by @armNormKey@ in
    -- "L4.EvaluateLazy.Machine" from the very same @rangeOf act@). It is
    -- the static half of the correlation key of
    -- @specs\/todo\/lexipedia-superset\/LTS-VISUALISER.md@ §3.4 (B1); the
    -- runtime half is the activation ordinal, which only a run can count.
    --
    -- Both arms of an obligation carry it — the @HENCE@ edge and the @LEST@
    -- edge are the two outcomes of ONE obligation, and the step logged for
    -- its expiry carries the same site as the step logged for its
    -- performance; 'transType' says which outcome an edge is. A junction's
    -- branch edge has no obligation behind it and leaves this 'Nothing', as
    -- does a hand-built fixture.
  } deriving (Eq, Show)

-- | One conjunct of a 'BranchGuard': the condition as the reader sees it, plus
-- the @DECIDE@ it applies when it is a bare application of one.
--
-- 'gaDecide' is a 'Unique' and not a name on purpose. The DMN backend resolves
-- element names through its own @uniquifyIn@ scopes, so two decides whose names
-- differ only in a way the sanitiser erases still get distinct ids; matching by
-- text would silently pick the wrong one, and matching by 'Unique' cannot.
data GuardAtom = MkGuardAtom
  { gaText   :: Text          -- ^ @prettyLayout@ of the condition, un-negated
  , gaDecide :: Maybe Unique  -- ^ the applied @DECIDE@, when the atom is one
  } deriving (Eq, Show)

-- | An @IF@-chain arm's guard, before it is flattened to text.
--
-- The n-th arm of @IF p THEN x ELSE IF q THEN y ELSE z@ is guarded by its own
-- condition conjoined with the negation of every condition above it. 'bgPriors'
-- is that list of conditions-above (each to be read /negated/) and 'bgOwn' is
-- the arm's own condition — absent on the trailing @ELSE@, which is guarded by
-- the accumulated negations alone.
data BranchGuard = MkBranchGuard
  { bgPriors :: [GuardAtom]
  , bgOwn    :: Maybe GuardAtom
  } deriving (Eq, Show)

-- | Every conjunct of a branch guard, paired with whether it is negated.
-- Priors first, own condition last — the order 'renderBranchGuard' prints them.
branchGuardAtoms :: BranchGuard -> [(Bool, GuardAtom)]
branchGuardAtoms bg =
  [(True, a) | a <- bg.bgPriors] <> [(False, a) | Just a <- [bg.bgOwn]]

-- | The flattened guard text — the single source of 'labelGuard'.
renderBranchGuard :: BranchGuard -> Maybe Text
renderBranchGuard bg = case branchGuardAtoms bg of
  [] -> Nothing
  as -> Just (Text.intercalate " AND " [render neg a | (neg, a) <- as])
 where
  render neg a = if neg then "NOT (" <> a.gaText <> ")" else a.gaText

-- | An @EVERY@ subject. The obligation is one per member of a cast that is
-- only known at run time (R-T6), so the graph draws it as ONE transition and
-- records here that it stands for many.
data Quantifier = MkQuantifier
  { quantVar  :: Text
    -- ^ the member variable — @t@ in @EVERY Tenant t@
  , quantRoll :: Maybe Text
    -- ^ the roll the cast is drawn from — @tenants@ in @EVERY Tenant t IN
    -- tenants@ — as written. Its /members/ are a run-time fact (R-T6); its
    -- name is not, and a projection that needs a collection to point at
    -- (BPMN's @loopDataInputRef@) should be told what the source called it.
  , quantJoin :: Maybe JoinLabel
    -- ^ the join line. Absent only when the rule has no @HENCE@ and no @LEST@;
    -- the type checker makes it mandatory otherwise.
  } deriving (Eq, Show)

-- | The join line of an @EVERY@: its kind, and its own @WITHIN@ if any.
data JoinLabel = MkJoinLabel
  { joinKind     :: JoinLabelKind
  , joinDeadline :: Maybe Text
    -- ^ The @WITHIN@ on the join line. It bounds the joined /state/ — one
    -- deadline on the whole, not re-armed by each performance (R-T2) — where
    -- 'labelDeadline' bounds each act. When the act has no @WITHIN@ of its
    -- own, this one bounds the acts as well: see 'memberDeadline'.
  } deriving (Eq, Show)

-- | How a quantified obligation's continuation fires ('L4.Syntax.Join'),
-- carried structurally so that a projection can tell the two apart.
--
-- They are different contracts. Under a barrier the @HENCE@ fires once, when
-- the threshold is met — for @ALL HAVE@, when the last member has performed.
-- Under a fork it fires once per member, as that member performs. Until
-- 2026-09-15 'extractDeonton' did not read the join at all, so the two lowered
-- to byte-identical BPMN, and the fidelity report — whose job is to list what
-- an export dropped — was silent about it. See
-- @specs\/todo\/EVERY-EACH-QUANTIFIER-SPEC.md@ §2.5 and
-- @specs\/todo\/lexipedia-superset\/LTS-VISUALISER.md@ §4.9.
--
-- Named for the label it sits on, not @JoinKind@: that name belongs to
-- 'L4.EvaluateLazy.DeonticStep.JoinKind', the machine's own join (which
-- carries the resolved 'L4.Syntax.Threshold' and a third, 'Distributive',
-- case), and a module drawing the norm plane over this graph imports both.
data JoinLabelKind
  = Barrier Text
    -- ^ @ONCE threshold@, level-triggered. The text is the threshold as the
    -- source spells it — see 'thresholdText'.
  | Fork
    -- ^ @UPON EACH@, edge-triggered.
  deriving (Eq, Show)

-- | The deadline that actually expires a member's obligation: the act's own
-- @WITHIN@, else the join line's.
--
-- This is the evaluator's rule, not this module's: @memberDue@ in
-- @L4.EvaluateLazy.Machine@ reads the act's deadline and falls back to the
-- join's, because a rule whose only @WITHIN@ is on the @ONCE@ line would
-- otherwise never expire a member and could never fail. So the @LEST@ arm of
-- such a rule IS reachable, and captioning it 'noTriggerWording' — which is
-- what reading 'labelDeadline' alone did — contradicted the runtime. Consumers
-- that draw the expiry (the @LEST@ caption here, the boundary timer in
-- @L4.Bpmn.Lower@) read this; 'labelDeadline' stays the act's own text, so the
-- edge shows what the source wrote where it wrote it.
memberDeadline :: TransitionLabel -> Maybe Text
memberDeadline l =
  l.labelDeadline <|> (l.labelQuantifier >>= (.quantJoin) >>= (.joinDeadline))

-- | A threshold as the source spells it.
--
-- Exhaustive, with no wildcard, on purpose: phase 3 of the quantifier spec
-- adds count and measure forms (@SOME 2 OF … HAVE@, @sum OF amount AT LEAST
-- rent@) as further constructors, and each must say how it is drawn. Under
-- @-Wall -Werror@ a new constructor fails this build rather than drawing as
-- nothing.
thresholdText :: Threshold Resolved -> Text
thresholdText = \case
  AllHave _ -> "ALL HAVE"

-- | A window edge's body as re-parseable source: the duration bracketed when
-- it is an application or an operator expression — @(period OF 2) OF THE
-- ARMING@, @(2 TIMES 7) OF THE JOIN@ — exactly as 'L4.Print.closingClause'
-- and 'L4.Print.openingClause' print it, and a bare number or name as itself.
--
-- Unbracketed, @period OF 2 OF THE ARMING@ is not the source form at all: in
-- the @WITHIN@ slot the first @OF@ is the anchor ('L4.Parser.deadline'), so
-- it re-parses as @period@ anchored at @2@ and fails on the second @OF@ —
-- loudly, but the label and the BPMN @\<documentation\>@ that restates it
-- claimed to be the source (adversarial pass of 2026-09-16, R1-6). It also
-- left the anchor unreadable off the text: @f OF x@ could be an application
-- or a duration @f@ anchored at @x@, and 'L4.Bpmn.Lower.deadlineAnchor' has
-- only the text to go on. Bracketed, an @OF@ outside every bracket is the
-- anchor and nothing else is.
edgeText :: LayoutPrinter a => a -> Text
edgeText = docText . parensIfNeeded

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
  , sgDecide       :: Maybe Unique
    -- ^ The @DECIDE@ this graph was extracted from. 'Nothing' only on a graph
    -- built by hand (test fixtures); extraction always knows it, because
    -- 'runExtraction' already needs it to recognise a self-recursive @HENCE@.
    --
    -- Kept so a consumer can ask the DMN backend what /this rule/ lowered to.
    -- The name cannot answer that question: whether a decide survives into the
    -- DRG at all depends on the population filter, and its emitted id depends
    -- on collisions with its siblings.
  , sgStates       :: [ContractState]
  , sgTransitions  :: [Transition]
  , sgInitialState :: StateId
  } deriving (Eq, Show)

--------------------------------------------------------------------------------
-- Extraction State Monad
--------------------------------------------------------------------------------

-- | State for graph extraction
data ExtractState = ExtractState
  { esNextId      :: StateId
  , esStates      :: [ContractState]
  , esTransitions :: [Transition]
  , esRules       :: Rules
    -- ^ Every regulative rule of the module, so that an arm naming one can
    -- be followed into it rather than stopping at a state called @next@.
  , esMemo        :: Map Unique StateId
    -- ^ The entry state of each named rule drawn on the path being
    -- extracted. Seeded with the rule being extracted at 'initialStateId',
    -- so a @HENCE@ back into it is a back-edge to the start, and a second
    -- arm into a rule already on the path reuses its state: this is what
    -- closes the loop (LTS-VISUALISER §3.4, B2), and it is what makes the
    -- graph a transition system rather than a tree. The scope is the path,
    -- not the graph: a @RAND@ \/ @ROR@ branch inherits the memo and gives
    -- back what it added ('perBranch'), so a rule that two branches both
    -- name is two states, one per instance the evaluator runs.
    --
    -- Keyed by the rule's 'Unique', not by a source range. The memo answers
    -- "has this /rule/ been given a state?", and a rule's identity is its
    -- @DECIDE@; two arms written at two different ranges that both name it
    -- must land on one state. A range identifies an /arm/ — that is what
    -- 'labelSite' carries on the edge — not the rule the arm points at.
  }

-- | The regulative rules of a module, by the 'Unique' of their @DECIDE@:
-- the rule's name as drawn, and its body with any @WHERE@ \/ @LET@ peeled
-- (what 'findRegulativeExpr' returns). Only rules /in this module/ are
-- here; an arm naming an imported rule is still an unknown target.
type Rules = Map Unique (Text, Expr Resolved)

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

-- | Extract all state graphs from a module: one per regulative rule, in
-- declaration order. Every graph is extracted against the whole module's
-- 'Rules', so a rule whose arm names another rule draws that rule's states
-- inside its own graph (and the named rule still gets a graph of its own).
extractStateGraphs :: Module Resolved -> [StateGraph]
extractStateGraphs (MkModule _ _ section) =
  let rules = regulativeRules section
  in [ runExtraction rules u name body | (u, (name, body)) <- regulativeRulesInOrder section ]
  where
    regulativeRules = Map.fromList . regulativeRulesInOrder

-- | Extract the first state graph from a module (convenience function)
extractStateGraph :: Module Resolved -> Maybe StateGraph
extractStateGraph m = case extractStateGraphs m of
  (sg:_) -> Just sg
  []     -> Nothing

-- | Every @DECIDE@ of a section (subsections included) whose body is
-- regulative, in declaration order, with its drawn name and peeled body.
regulativeRulesInOrder :: Section Resolved -> [(Unique, (Text, Expr Resolved))]
regulativeRulesInOrder (MkSection _ _ _ _ decls) = concatMap ofDecl decls
  where
    ofDecl = \case
      Decide _ (MkDecide _ _ (MkAppForm _ name _ _) body) ->
        case findRegulativeExpr body of
          Just regExpr -> [(getUnique name, (resolvedToText name, regExpr))]
          Nothing      -> []
      Section _ sec -> regulativeRulesInOrder sec
      _ -> []

-- | Find a regulative expression in an expression tree.
--
-- @IF … THEN … ELSE …@ counts when at least one arm is regulative, because
-- that is how legislation actually writes a conditional duty: the CFR puts its
-- guard /outside/ the deontic head — "An issuer must continue to comply with
-- the ongoing reporting requirements until one of the following occurs",
-- "unless such securities are transferred: …" — so an isomorphic
-- formalisation puts the @IF@ above the @PARTY … MUST …@ rather than folding
-- it into a @PROVIDED@.
--
-- Peeling only @Where@ and @LetIn@ (which is what this did until 2026-07-27)
-- meant every such rule was invisible: @extractStateGraphs@ returned @[]@ and
-- @l4 export --to=bpmn@ refused with "No regulative rules found in module" on
-- a module full of obligations. All three regulative rules in
-- @jl4\/examples\/legal\/regcf\/regcf.l4@ were in that position.
--
-- A conditional whose arms are all non-regulative is still not a regulative
-- rule, and still yields 'Nothing': the test is on the arms, not on the shape.
findRegulativeExpr :: Expr Resolved -> Maybe (Expr Resolved)
findRegulativeExpr expr = case expr of
  Regulative{} -> Just expr
  RAnd{}       -> Just expr
  ROr{}        -> Just expr
  Where _ e _  -> findRegulativeExpr e
  LetIn _ _ e  -> findRegulativeExpr e
  IfThenElse{}
    | any (isJust . findRegulativeExpr . snd) (guardedIfBranches expr) -> Just expr
  _            -> Nothing

-- | Peel a chain of @IF c THEN a ELSE b@ into guarded branches.
--
-- The guard on the n-th arm is its own condition conjoined with the negation
-- of every condition above it — that is what @ELSE@ means — and the final arm
-- carries the accumulated negation alone. So
--
-- > IF   p THEN x
-- > ELSE IF q THEN y
-- >           ELSE z
--
-- yields @[(p, x), (NOT (p) AND q, y), (NOT (p) AND NOT (q), z)]@. Keeping the
-- arms' guards means the branch set stays exhaustive and mutually exclusive by
-- construction, which is the property that separates a fact-driven branch from
-- a @ROR@ choice.
--
-- Rewriting such a rule as @ROR@ of @PROVIDED@-guarded obligations — the
-- workaround this replaces — is /not/ the same construct. @ROR@ is a choice
-- the obliged party makes; @IF@ is a branch the facts make. Worse, the
-- rewriting loses any arm that imposes no duty (a bare @FULFILLED@ base case),
-- because there is no obligation to hang a @PROVIDED@ on.
guardedIfBranches :: Expr Resolved -> [(BranchGuard, Expr Resolved)]
guardedIfBranches = go []
 where
  go priors = \case
    IfThenElse _ c t e ->
      let a = atomOf c
       in (MkBranchGuard {bgPriors = priors, bgOwn = Just a}, t)
            : go (priors <> [a]) e
    other -> [(MkBranchGuard {bgPriors = priors, bgOwn = Nothing}, other)]

  atomOf c = MkGuardAtom {gaText = prettyLayout c, gaDecide = guardHeadDecide c}

-- | The @DECIDE@ a guard condition applies, when the condition /is/ one
-- application and nothing more.
--
-- Deliberately shallow. @\`notice complies with Rule 204(b)\` OF notice@ is an
-- 'App' whose head is the decide, and that is the whole of what a downstream
-- resolver can honestly claim to have identified. A conjunction, a comparison,
-- an explicit @NOT@ or a record projection all yield 'Nothing' — not because
-- they could not be decomposed, but because the answer would then be "several
-- decisions, combined somehow", which is not a thing a caller can invoke.
guardHeadDecide :: Expr Resolved -> Maybe Unique
guardHeadDecide = \case
  App _ n _        -> Just (getUnique n)
  AppNamed _ n _ _ -> Just (getUnique n)
  _                -> Nothing

-- | The id of the state every graph starts in.
--
-- Extraction numbers states from zero and the first state it creates is always
-- the entry — either the @initial@ state of a lone obligation or the junction
-- a fan arrives at — so this is a fact about 'newState', not a convention.
-- Named because a self-recursive @HENCE@ needs to point at it.
initialStateId :: StateId
initialStateId = 0

-- | Run the extraction monad and build a StateGraph
runExtraction :: Rules -> Unique -> Text -> Expr Resolved -> StateGraph
runExtraction rules self name expr =
  let initialState = ExtractState
        { esNextId = 0
        , esStates = []
        , esTransitions = []
        , esRules = rules
        , esMemo = Map.singleton self initialStateId
        }
      finalState = St.execState (extractExpr Nothing expr) initialState
  in StateGraph
       { sgName = name
       , sgDecide = Just self
       , sgStates = reverse finalState.esStates
       , sgTransitions = reverse finalState.esTransitions
       , sgInitialState = initialStateId
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

  -- A conditional over regulative arms. Also a @OneOf@ junction — exactly one
  -- arm applies — but unlike @ROr@ the arms are selected by the facts, and the
  -- condition that selects each one travels with it as the branch edge's
  -- guard. Downstream that is the difference between an exclusive gateway a
  -- reader can evaluate and one that reads as a free choice.
  IfThenElse{} -> extractIf mFromState expr

  Where _ e _ -> extractExpr mFromState e
  LetIn _ _ e -> extractExpr mFromState e

  -- Terminal states referenced by name
  App _ name [] | isFulfilled name -> do
    _ <- getTerminalState "Fulfilled" TerminalFulfilled
    pure ()

  Breach _ _ _ -> do
    _ <- getTerminalState "Breach" TerminalBreach
    pure ()

  -- A refusal is not a deontic terminal: it is the model declining to answer,
  -- which has no state in the lifecycle graph. Deliberately no state is
  -- created (the wildcard below would do the same; the arm is explicit so
  -- that the decision is recorded rather than inherited).
  Refuse _ _ -> pure ()

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
--
-- Each branch is extracted with the memo ('esMemo') it found on entry, and
-- what a branch adds to the memo is forgotten when it ends: a named rule
-- that two branches of one @RAND@ \/ @ROR@ both reach is drawn once per
-- branch, not shared. That is the evaluator's shape — @RBinOp1@ \/ @RBinOp2@
-- in @L4.EvaluateLazy.Machine@ run /both/ operands, so @z RAND z@ is two
-- instances of @z@ — and it is what the dominator views need: they run a
-- junction's branches in sequence, and a state shared between two branches
-- would be sequenced with itself (a self-loop in place of the edge to the
-- sink, and \"No path reaches FULFILLED\" for a rule that plainly does;
-- @ok/contracts.l4@'s @a@, until 2026-09-16). A loop still closes: a rule
-- on the path /above/ the junction is in the memo each branch inherits, so
-- an arm back into it is a back-edge. An @IF@'s arms are exclusive — the
-- facts run one — and keep sharing ('extractIfFan'), as do an obligation's
-- @HENCE@ and @LEST@, which are two outcomes of which exactly one occurs.
extractFan :: FanKind -> Maybe StateId -> [Expr Resolved] -> ExtractM ()
extractFan kind mFromState branches =
  extractGuardedFanWith perBranch kind mFromState [(Nothing, b) | b <- branches]

-- | Run one branch's extraction and restore the memo afterwards, so what the
-- branch memoised is visible below it and nowhere else.
perBranch :: ExtractM () -> ExtractM ()
perBranch act = do
  memo <- St.gets (.esMemo)
  act
  St.modify $ \st -> st { esMemo = memo }

-- | 'extractGuardedFan' over @IF@ arms, whose guards are structured.
extractIfFan :: Maybe StateId -> [(BranchGuard, Expr Resolved)] -> ExtractM ()
extractIfFan mFromState branches =
  extractGuardedFan OneOf mFromState [(Just g, b) | (g, b) <- branches]

-- | Extract an @IF@ chain whose arms are regulative as a guarded @OneOf@
-- junction. A chain none of whose arms is regulative is not a rule and
-- produces nothing, so that an ordinary boolean conditional reached through a
-- @HENCE@ target does not manufacture a spurious gateway.
extractIf :: Maybe StateId -> Expr Resolved -> ExtractM ()
extractIf mFromState expr
  | any (isJust . findRegulativeExpr . snd) branches =
      extractIfFan mFromState branches
  | otherwise = pure ()
 where
  branches = guardedIfBranches expr

-- | As 'extractFan', with a guard attached to each branch edge.
extractGuardedFan
  :: FanKind -> Maybe StateId -> [(Maybe BranchGuard, Expr Resolved)] -> ExtractM ()
extractGuardedFan = extractGuardedFanWith id

-- | 'extractGuardedFan' with each branch's extraction wrapped: 'perBranch'
-- for a @RAND@ \/ @ROR@, whose branches all run, and 'id' for an @IF@, whose
-- arms are exclusive (see 'extractFan').
extractGuardedFanWith
  :: (ExtractM () -> ExtractM ())
  -> FanKind -> Maybe StateId -> [(Maybe BranchGuard, Expr Resolved)] -> ExtractM ()
extractGuardedFanWith wrap kind mFromState branches = do
  junction <- case mFromState of
    Just sid -> pure sid
    Nothing  -> newState "initial" InitialState
  markFan junction kind
  traverse_ (wrap . uncurry (extractBranch junction)) branches

-- | Extract one branch of a junction, wiring the junction to its entry state.
-- A branch that is just @FULFILLED@ or @BREACH@ has no work in it, so it
-- needs no entry state: the junction points straight at the terminal — and
-- likewise a branch naming a rule points straight at that rule's state.
extractBranch :: StateId -> Maybe BranchGuard -> Expr Resolved -> ExtractM ()
extractBranch junction mGuard branch =
  wireTarget junction (fanLabel mGuard) DefaultTransition (branchStateName branch) branch

-- | Wire an arm — a @HENCE@, a @LEST@, or a junction's branch — from a state
-- to whatever its expression denotes, creating the target's state when the
-- target needs one and does not have one yet.
--
-- The five targets, and where each lands:
--
-- * @FULFILLED@ \/ @BREACH@: the shared terminal ('getTerminalState').
-- * an inline obligation: a fresh state named for it, extracted below.
-- * a __named rule__ (this one included): its entry state from 'esMemo' if
--   it has one, else a fresh state named after the rule, memoised, with the
--   rule's body extracted from it. So the second arm into a rule lands on
--   the first arm's state when both arms are on one path (an obligation's
--   @HENCE@ and @LEST@, an @IF@'s arms) — but not when they are sibling
--   branches of a @RAND@ \/ @ROR@, see 'extractFan' — and an arm back into
--   the rule being extracted lands on the start — a loop, closed. Until
--   2026-09-16 only the last of those was done, and by a special case; an
--   arm into any /other/ rule made a dead-end state called @next@ or
--   @failure@, which is why every graph was a tree (LTS-VISUALISER §3.3,
--   gap 3).
-- * anything else: a fresh state under the caller's fallback name, with
--   whatever structure 'extractExpr' can find in the expression below it.
--
-- The named rule's arguments are deliberately ignored, exactly as a
-- renewing rule's were. A state graph is a control-flow abstraction: it can
-- say the contract continues into that rule, and it cannot say it does so
-- with one fewer cycle remaining. What is lost is the /termination
-- argument/, and that loss is real — see the BPMN fidelity report's
-- @P-CYCLE@.
wireTarget
  :: StateId          -- ^ the state the arm leaves
  -> TransitionLabel  -- ^ the arm's caption
  -> TransitionType
  -> Text             -- ^ the state name to use for an unrecognised target
  -> Expr Resolved    -- ^ the arm's expression
  -> ExtractM ()
wireTarget from label ttype otherName expr = do
  rules <- St.gets (.esRules)
  case classifyTarget rules expr of
    TargetFulfilled -> terminal "Fulfilled" TerminalFulfilled
    TargetBreach    -> terminal "Breach" TerminalBreach

    TargetDeonton obl -> do
      entryId <- newState (describeDeonton obl) IntermediateState
      addTransition from entryId label ttype
      extractDeonton (Just entryId) obl

    TargetNamed u name body -> do
      memo <- St.gets (.esMemo)
      case Map.lookup u memo of
        Just sid -> addTransition from sid label ttype
        Nothing -> do
          entryId <- newState name IntermediateState
          -- Memoise BEFORE extracting the body, or a rule that names itself
          -- from inside that body would be entered again.
          St.modify $ \st -> st { esMemo = Map.insert u entryId st.esMemo }
          addTransition from entryId label ttype
          -- A rule whose body is RAND/ROR/IF marks this very state as the
          -- junction.
          extractExpr (Just entryId) body

    TargetOther -> do
      entryId <- newState otherName IntermediateState
      addTransition from entryId label ttype
      extractExpr (Just entryId) expr
  where
    terminal nm ty = do
      sid <- getTerminalState nm ty
      addTransition from sid label ttype

-- | Name for the entry state of a branch that is neither a bare obligation
-- nor a terminal.
branchStateName :: Expr Resolved -> Text
branchStateName expr = case expr of
  RAnd{}       -> "all of"
  ROr{}        -> "one of"
  IfThenElse{} -> "one of"
  App _ n _    -> resolvedToText n
  Where _ e _  -> branchStateName e
  LetIn _ _ e  -> branchStateName e
  _            -> "branch"

-- | The edge from a junction to a branch entry carries no action of its own —
-- a junction is a control point, not a task — but it may carry the condition
-- that selects the branch, when the junction came from an @IF@ rather than
-- from a @RAND@ \/ @ROR@.
fanLabel :: Maybe BranchGuard -> TransitionLabel
fanLabel mGuard = TransitionLabel
  { labelParty    = Nothing
  , labelModal    = Nothing
  , labelAction   = ""
  , labelOpening  = Nothing
  , labelDeadline = Nothing
  -- One source, not two: the text IS the rendering of the structure, so a
  -- consumer reading either gets the same guard.
  , labelGuard    = mGuard >>= renderBranchGuard
  , labelBranch   = mGuard
  , labelQuantifier = Nothing
  , labelSite     = Nothing
  }

-- | Extract an obligation as a state transition.
--
-- The pattern is positional, not @MkDeonton{..}@ by field name, and that is
-- deliberate. A record pattern keeps compiling when the constructor grows a
-- field, which is exactly how @join@ went unread from the day it was added
-- until 2026-09-15: the barrier and the fork lowered to byte-identical output,
-- and nothing warned. A positional pattern makes the next new field a type
-- error on this line.
extractDeonton :: Maybe StateId -> Deonton Resolved -> ExtractM ()
extractDeonton mFromState (MkDeonton _anno subject action opens due mJoin hence lest) = do
  -- Create or get the source state
  fromState <- case mFromState of
    Just sid -> pure sid
    Nothing  -> newState "initial" InitialState

  -- Build the transition label
  let partyText = Just (subjectText subject)
      modalVal  = Just (action.modal)
      actionText = prettyPattern action.action
      -- An anchored deadline (R-Q7, §5.1.1) prints as its source form,
      -- @5 OF THE JOIN@, the duration bracketed where the source needs it
      -- ('edgeText'); 'L4.Bpmn.Lower.parseDuration' cannot read an anchor and
      -- the lowering reports it as anchored, which is the stated limit. A
      -- @BEFORE@ (R-X5, §5.1.2) keeps its keyword in the label for the same
      -- reason: it is a date, not a duration, and the lowering must be able
      -- to see that.
      deadlineText = fmap closingText due
      closingText = \ case
        d@MkDeadline{} -> edgeText d
        d@MkBefore{}   -> "BEFORE " <> edgeText d
      -- The opening edge (§5.1.2), as its source form; the BPMN lowering
      -- does not draw it and says so ('L4.Bpmn.Lower.openingFindings').
      openingText = fmap edgeText opens
      guardText = fmap prettyLayout action.provided

      -- Exhaustive on the join and on the threshold, with no wildcard arm, so
      -- a new form of either is a compile error here and not a silent drawing.
      quantifier = case subject of
        Party{} -> Nothing
        Every _ _ v mRoll _ ->
          Just MkQuantifier
            { quantVar  = prettyLayout v
            , quantRoll = prettyLayout <$> mRoll
            , quantJoin = joinLabel <$> mJoin
            }
      joinLabel = \case
        JoinOnce _ th d ->
          MkJoinLabel { joinKind = Barrier (thresholdText th), joinDeadline = closingText <$> d }
        JoinUpon _ _ d ->
          MkJoinLabel { joinKind = Fork, joinDeadline = closingText <$> d }

      -- The key's static half (B1): the same @rangeOf@ of the same
      -- 'RAction' that @armNormKey@ stamps on the runtime step.
      site = rangeOf action

      label = TransitionLabel
        { labelParty    = partyText
        , labelModal    = modalVal
        , labelAction   = actionText
        , labelOpening  = openingText
        , labelDeadline = deadlineText
        , labelGuard    = guardText
        , labelBranch   = Nothing
        , labelQuantifier = quantifier
        , labelSite     = site
        }

      -- The caption for whichever LEST arm this obligation turns out to have.
      -- It carries the modal too: without it a consumer holding only this edge
      -- cannot tell a missed deadline from a prohibition that was breached,
      -- which is the whole of smucclaw/l4-ide#927. The party, deadline and
      -- guard are deliberately absent — they belong to the obligation, which
      -- the HENCE edge already restates, and repeating them here would read as
      -- a second, contradictory copy of the rule.
      -- The caption reads the deadline that expires a MEMBER, which for a
      -- quantified rule may sit on the join line rather than on the act; see
      -- 'memberDeadline'. Passing @due@ here said "unreachable: no WITHIN" of
      -- a rule the evaluator does expire.
      lestLabel = TransitionLabel
        { labelParty    = Nothing
        , labelModal    = modalVal
        , labelAction   = lestArmWording action.modal (memberDeadline label)
        , labelOpening  = Nothing
        , labelDeadline = Nothing
        , labelGuard    = Nothing
        , labelBranch   = Nothing
        , labelQuantifier = Nothing
        , labelSite     = site
        }

      defaultToBreach = do
        breachId <- getTerminalState "Breach" TerminalBreach
        addTransition fromState breachId lestLabel LestTransition

  -- Handle HENCE (success path)
  case hence of
    Just henceExpr -> wireTarget fromState label HenceTransition "next" henceExpr

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
  --
  -- A @LEST@ back into the rule's own name used to be the one arm captioned
  -- with a literal @\"timeout\"@ and no modal, left over from before #927;
  -- it now goes through 'wireTarget' with the same caption as its siblings.
  case lest of
    Just lestExpr -> wireTarget fromState lestLabel LestTransition "failure" lestExpr

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
        DMay -> case quantifier >>= (.quantJoin) of
          -- Under EITHER join a lapsed member's arm goes to Fulfilled, never
          -- to where HENCE goes. Barrier: a lapsed member means the join can
          -- never fire, the HENCE is skipped and the member's own FULFILLED is
          -- returned as the barrier's (Machine.hs, Barrier1's last arm and the
          -- note on 'barrierFail'). Fork: the HENCE arises only from a
          -- member's ACT; a member whose permission expires unexercised
          -- spawns nothing. Both measured, 2026-09-15/16, on the corporate
          -- resolution (spec §2.2.1 Pattern B): nobody approves and the chair
          -- publishes anyway → FULFILLED under both joins; one approval with
          -- no publication → BREACHED (the chair), fork and barrier alike
          -- (ok/every/tests/run-modals.golden). Drawing the arm here is what
          -- stops L4.Bpmn.Lower's synthesised lapse timer from routing
          -- "wherever HENCE lands", which manufactured the chair's duty to
          -- publish a resolution that did not pass.
          --
          -- A first version of this arm drew it for the barrier only, on the
          -- concurrency review's reading that a fork "carries the real HENCE"
          -- per member. That reading was wrong at runtime and was caught by
          -- re-measurement the next day. The single-party PARTY MAY keeps the
          -- pre-existing gap noted above; it is the same defect and the same
          -- fix, and moves the handover goldens, so it is its own change.
          Just _ -> do
            fulfilledId <- getTerminalState "Fulfilled" TerminalFulfilled
            addTransition fromState fulfilledId lestLabel LestTransition
          Nothing -> pure ()
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
  | TargetNamed Unique Text (Expr Resolved)
    -- ^ A regulative rule of this module, applied to whatever arguments: its
    -- 'Unique', its drawn name, and its peeled body. The rule being
    -- extracted is one of these — a renewing duty is written
    -- @HENCE \<this rule\> \<updated state\>@, an 'App' /with arguments/ —
    -- and lands on the start state through 'esMemo'.
  | TargetOther

-- | Classify what a HENCE/LEST expression points to, given the module's
-- regulative rules.
--
-- A named rule's arguments are ignored; see 'wireTarget' for why. Until
-- 2026-07-27 a renewing duty fell through to 'TargetOther', which
-- manufactured an intermediate state literally named after the rule and left
-- it with no outgoing transition — so the loop was reported as a dangling
-- path rather than as a loop, and @P-CYCLE@ could never fire because the
-- cycle never reached the graph. Reg CF's annual Form C-AR cycle
-- (@jl4\/examples\/legal\/regcf\/regcf.l4@) is exactly this shape. Until
-- 2026-09-16 an arm into any /other/ rule still did.
classifyTarget :: Rules -> Expr Resolved -> Target
classifyTarget rules = \case
  App _ name [] | isFulfilled name -> TargetFulfilled
  App _ name _ | Just (nm, body) <- Map.lookup (getUnique name) rules -> TargetNamed (getUnique name) nm body
  Breach{} -> TargetBreach
  -- Not a breach: a refusal is not a deontic outcome at all.
  Refuse{} -> TargetOther
  Regulative _ obl -> TargetDeonton obl
  Where _ e _ -> classifyTarget rules e
  LetIn _ _ e -> classifyTarget rules e
  _ -> TargetOther

-- | Generate a descriptive name for an obligation (for intermediate states)
describeDeonton :: Deonton Resolved -> Text
describeDeonton MkDeonton{subject, action} =
  let partyT = subjectText subject
      modalT = case action.modal of
        DMust    -> "must"
        DMay     -> "may"
        DMustNot -> "must not"
        DDo      -> "do"
      actionT = prettyPattern action.action
  in partyT <> " " <> modalT <> " " <> actionT

-- | The subject of a deonton as label text.
--
-- An @EVERY@ is rendered as ONE node labelled with the quantifier. The cast is
-- only known at run time, once evaluated (R-T6), so the state graph does not
-- fan it out into per-member transitions, and the BPMN lowered from it shows a
-- single multi-instance task for the whole cast. The join line is NOT part of
-- this text: it travels structurally in 'labelQuantifier' and is drawn by
-- 'formatTransitionLabel', so a barrier and a fork stay distinguishable to
-- every consumer of the graph.
subjectText :: Subject Resolved -> Text
subjectText = \case
  Party _ p -> prettyLayout p
  Every _ mCast v mRoll mFilter -> Text.unwords $
    [ "EVERY" ]
    <> maybe [] (\c -> [prettyLayout c]) mCast
    <> [ prettyLayout v ]
    <> maybe [] (\r -> [ "IN", prettyLayout r ]) mRoll
    <> maybe [] (\f -> [ "WHO", prettyLayout f ]) mFilter

-- | Pretty-print a pattern to text
prettyPattern :: Pattern Resolved -> Text
prettyPattern = \case
  PatVar _ n      -> resolvedToText n
  PatApp _ n args -> resolvedToText n <> if null args then "" else " ..."
  PatCons _ h _   -> prettyPattern h <> " ..."
  PatExpr _ e     -> prettyLayout e
  PatLit _ lit    -> prettyLayout lit
