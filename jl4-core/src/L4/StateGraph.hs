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
import L4.Print (LayoutPrinter (..), docText, prettyLayout, printActionPattern)

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
  , stateConstruct :: Maybe Text
    -- ^ The rule construct that made this state a junction — @RAND@, @ROR@ or
    -- @IF@ — set by 'markFan' at the moment the construct is known, and
    -- 'Nothing' on every 'Linear' state and on a hand-built fixture.
    --
    -- 'FanKind' cannot answer this: @ROR@ and a regulative @IF@ are BOTH
    -- 'OneOf', so a junction drawn from either says \"ONE OF\" and a reader
    -- cannot tell a choice the obliged party makes from a branch the facts
    -- make — the distinction 'guardedIfBranches' exists to preserve. It is a
    -- field rather than a third 'FanKind' constructor because the two answer
    -- different questions: 'FanKind' says how many branches fire, which is
    -- what a gateway needs, and this says which keyword wrote them.
  , stateSite :: Maybe SrcRange
    -- ^ @rangeOf@ the 'RAction' of the obligation this state is the ENTRY of,
    -- when it is one — the same range that obligation's own edges carry in
    -- 'labelSite'. Set only where 'wireTarget' names a state after an
    -- obligation ('describeDeonton'), so an edge whose 'labelSite' equals it
    -- is an edge whose caption the state's own name already gives.
    --
    -- That equality is the structural correlation key "L4.StateGraph.Dot"
    -- uses to stop printing the party, the modal and the act twice. Comparing
    -- the rendered texts would do the same job until either spelling drifted,
    -- and then fail silently; the range cannot drift, because both sides read
    -- the same 'RAction'.
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
  , labelBinds    :: Maybe Text
    -- ^ The names the act pattern BINDS, already spelled as a clause —
    -- @the rule binds \`amount\`@ — or 'Nothing' where it binds none
    -- ('bindsClause', 'patternBinders').
    --
    -- It is a field of its own and not part of 'labelAction' because
    -- 'labelAction' is L4\'s own spelling of the act
    -- ('L4.Print.printActionPattern') and has to stay that: the node, this
    -- edge, @l4 lts@ and the BPMN task name all print it, and a mark added
    -- here would reach an XML @name=@ attribute that four external parsers
    -- read. The distinction is real and the drawing has to carry it, so it
    -- travels BESIDE the act.
    --
    -- Read by "L4.StateGraph.Dot" and by nothing else, deliberately. It is a
    -- sentence for a reader, not data: @L4.Bpmn.Lower@ has 'labelAction' for
    -- its task name and the pattern itself for anything finer.
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
  , quantCast :: Maybe Text
    -- ^ the cast word — @Tenant@ in @EVERY Tenant t IN tenants@ — as written.
    -- A /constructor/ of the party type under the value-actor encoding, not a
    -- type ('L4.Syntax.Every').
  , quantFilter :: Maybe Text
    -- ^ the @WHO@ filter, as written.
    --
    -- Together with 'quantCast' this is what a projection needs to know that
    -- __the roll is not the cast__. Both narrow: a roll of four can arm a cast
    -- of three, and @jl4\/examples\/ok\/every\/run-fork.l4@ does exactly that
    -- on purpose. So a projection that points a collection at 'quantRoll' and
    -- says nothing else is not merely declining to state the narrowing — it is
    -- stating an instance count that L4 denies. Until these two fields existed
    -- the extractor discarded both, and no consumer could tell the cases apart
    -- in order to say so.
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
--
-- __What this exhaustiveness does NOT buy, measured 2026-09-17.__ It was
-- claimed here that a new constructor would force every consumer to decide how
-- to handle it. That is false, and the claim was doing harm by reading as a
-- guarantee. This function flattens the threshold to 'Text' at the boundary —
-- 'JoinLabelKind'\'s @Barrier@ carries the rendered string, not the
-- 'Threshold' — so a count or measure form breaks exactly ONE function, this
-- one, whose job is a caption. The author writes @"SOME 2 OF … HAVE"@, the
-- build goes green, and no consumer that must /decide/ ever sees a type
-- change. Two of them then lie at exit 0: @L4.Lts.List@ renders "one of N who
-- must all act before the next step" and @L4.Lts.Marking@ "a barrier of N",
-- both false for a count threshold.
--
-- So when phase 3 lands, the build stops HERE and nowhere else, which makes
-- this comment the only place the next person is known to be standing. What
-- else must change, none of it forced by the compiler:
--
-- * 'JoinLabelKind'\'s @Barrier@ should carry the 'Threshold' and render at
--   each use site, so growth breaks every consumer that must choose. That is
--   the real fix; everything below is what it would have caught.
-- * @L4.Lts.List@ and @L4.Lts.Marking@\'s barrier captions, above.
-- * @L4.Bpmn.Lower@\'s completion condition, which reads @ALL HAVE@ off the
--   string, and its refusal for the measure form — @sum OF amount AT LEAST
--   rent@ is not a P\/T construct and cannot be a @completionCondition@.
-- * @etc\/check-bpmn-soundness.mjs@\'s no-shared-place invariant, and with it
--   the n ∈ {0,2} cutoff: a count threshold needs a shared accumulator, which
--   is not 1-safe, so the expansion MODEL needs revisiting and not just the
--   constant. Its header says this too.
--
-- This is the same shape as the @join@ field one layer down: there a record
-- pattern let a constructor grow invisibly, here flattening to 'Text' at a
-- boundary does.
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
newState = newStateAt Nothing

-- | 'newState', recording the obligation the state is the entry of.
--
-- Only 'wireTarget' passes a site, and only where it names the state after an
-- obligation, so 'stateSite' is 'Just' exactly on the states whose name is a
-- 'describeDeonton'. Everything else — the @initial@ state, a named rule's
-- entry, a junction, a terminal — goes through 'newState' and stays 'Nothing',
-- which is what makes the equality test in "L4.StateGraph.Dot" safe: a
-- 'Nothing' site never matches an edge.
newStateAt :: Maybe SrcRange -> Text -> StateType -> ExtractM StateId
newStateAt site name stype = do
  st <- St.get
  let sid = st.esNextId
      s = ContractState sid name stype Linear Nothing site
  St.put st { esNextId = sid + 1, esStates = s : st.esStates }
  pure sid

-- | Turn an existing state into a junction of the given kind, recording the
-- rule construct that did it. The construct travels with the state because
-- the 'FanKind' alone cannot recover it: see 'stateConstruct'.
markFan :: StateId -> FanKind -> Text -> ExtractM ()
markFan sid kind construct = St.modify $ \st ->
  st { esStates = map retag st.esStates }
  where
    retag s
      | s.stateId == sid = s { stateFan = kind, stateConstruct = Just construct }
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
  RAnd{} -> extractFan AllOf "RAND" mFromState (flattenRAnd expr)

  -- Choice: exactly one branch is taken.
  ROr{}  -> extractFan OneOf "ROR" mFromState (flattenROr expr)

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
extractFan :: FanKind -> Text -> Maybe StateId -> [Expr Resolved] -> ExtractM ()
extractFan kind construct mFromState branches =
  extractGuardedFanWith perBranch kind construct mFromState [(Nothing, b) | b <- branches]

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
  extractGuardedFan OneOf "IF" mFromState [(Just g, b) | (g, b) <- branches]

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
  :: FanKind -> Text -> Maybe StateId -> [(Maybe BranchGuard, Expr Resolved)] -> ExtractM ()
extractGuardedFan = extractGuardedFanWith id

-- | 'extractGuardedFan' with each branch's extraction wrapped: 'perBranch'
-- for a @RAND@ \/ @ROR@, whose branches all run, and 'id' for an @IF@, whose
-- arms are exclusive (see 'extractFan').
extractGuardedFanWith
  :: (ExtractM () -> ExtractM ())
  -> FanKind -> Text -> Maybe StateId -> [(Maybe BranchGuard, Expr Resolved)] -> ExtractM ()
extractGuardedFanWith wrap kind construct mFromState branches = do
  junction <- case mFromState of
    Just sid -> pure sid
    -- Still @initial@, deliberately: this is the graph's ENTRY, and that is
    -- the more useful thing for the node to say. Which construct fanned it is
    -- recorded on 'stateConstruct' and drawn beside the fan kind, so naming
    -- the state after the construct instead would trade the start of the
    -- contract for a fact the page already carries.
    Nothing  -> newState "initial" InitialState
  markFan junction kind construct
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
      -- Named after the obligation, so it is stamped with that obligation's
      -- site: the edges 'extractDeonton' hangs off it carry the same range in
      -- 'labelSite', and that equality is how the renderer knows the caption
      -- would merely repeat the node.
      entryId <- newStateAt (deontonSite obl) (describeDeonton obl) IntermediateState
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
  , labelBinds    = Nothing
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
      -- Which of the act's names are OPEN, beside the act rather than inside
      -- it; see 'labelBinds'.
      bindsText = bindsClause action.action
      -- The window's closing edge, spelled by 'windowText' so the node and
      -- this edge cannot drift apart.
      deadlineText = fmap windowText due
      -- The opening edge (§5.1.2), as its source form; the BPMN lowering
      -- does not draw it and says so ('L4.Bpmn.Lower.openingFindings').
      openingText = fmap edgeText opens
      guardText = fmap prettyLayout action.provided

      -- Exhaustive on the join and on the threshold, with no wildcard arm, so
      -- a new form of either is a compile error here and not a silent drawing.
      --
      -- The 'Every' pattern is POSITIONAL and binds all five fields for the
      -- same reason 'extractDeonton' does: a record pattern let 'MkDeonton'
      -- grow a @join@ field that nothing read, and the two join kinds lowered
      -- to byte-identical BPMN for as long as that lasted. A sixth field on
      -- 'L4.Syntax.Every' now stops this build.
      quantifier = case subject of
        Party{} -> Nothing
        Every _ mCast v mRoll mFilter ->
          Just MkQuantifier
            { quantVar    = prettyLayout v
            , quantCast   = prettyLayout <$> mCast
            , quantFilter = prettyLayout <$> mFilter
            , quantRoll   = prettyLayout <$> mRoll
            , quantJoin   = joinLabel <$> mJoin
            }
      joinLabel = \case
        JoinOnce _ th d ->
          MkJoinLabel { joinKind = Barrier (thresholdText th), joinDeadline = windowText <$> d }
        JoinUpon _ _ d ->
          MkJoinLabel { joinKind = Fork, joinDeadline = windowText <$> d }

      -- The key's static half (B1): the same @rangeOf@ of the same
      -- 'RAction' that @armNormKey@ stamps on the runtime step.
      site = rangeOf action

      -- This obligation as its own entry state is named, so an arm of it that
      -- has to mint a state can say which obligation it is an arm OF.
      selfName = describeAction subject action

      label = TransitionLabel
        { labelParty    = partyText
        , labelModal    = modalVal
        , labelAction   = actionText
        , labelBinds    = bindsText
        , labelOpening  = openingText
        , labelDeadline = deadlineText
        , labelGuard    = guardText
        , labelBranch   = Nothing
        , labelQuantifier = quantifier
        , labelSite     = site
        }

      -- The deadline that TAKES this arm, as against the one that bounds the
      -- act. They are the same clause read from opposite ends: on the HENCE
      -- edge the @WITHIN@ says by when the act still counts, and here it names
      -- the instant the arm fires. 'lestArmWording' says WHAT happens and has
      -- only ever read the deadline's PRESENCE; this says WHEN, so an edge
      -- captioned "timeout" no longer leaves the reader to hunt the sibling
      -- edge for which timeout it was.
      --
      -- 'DMustNot' is 'Nothing', and that is the same short-circuit
      -- lestArmWording makes on its first line: a prohibition's arm is
      -- taken by the ACT being performed, not by the clock, so a deadline here
      -- would name an event that does not fire this arm. For a prohibition the
      -- deadline running out means COMPLIANCE.
      --
      -- A BARRIER with a deadline of its own, distinct from the act's. Two
      -- clocks then take this one arm — a member missing the act's window, and
      -- the barrier not being met by the join's — and a caption can name only
      -- one of them. @jl4\/examples\/bpmn\/modals.l4:57-60@ is the case:
      -- @WITHIN 30@ on the act, @ONCE ALL HAVE WITHIN 10@ on the join, and
      -- @L4.Bpmn.Lower@\'s own P-JOIN-DEADLINE note says of exactly this shape
      -- that "the rule does enforce it: a barrier whose last act lands after
      -- it fails" (@jl4-core\/src\/L4\/Bpmn\/Lower.hs:2940-2946@). Naming the
      -- 30 there is a PRECISE claim about which clock fires, and it is the
      -- wrong one half the time; the bare word "timeout" was vague and
      -- therefore not wrong. So the bracket is dropped and the reader is left
      -- with the sibling HENCE edge, which draws both windows.
      --
      -- A FORK is not this case even when both are written. Lower.hs's Fork
      -- arm of the same note says the join's deadline is dead on a fork — "a
      -- fork has no join event to check it at; only the act's expires a
      -- member" — so there is one clock and 'memberDeadline' names it.
      barrierJoinDeadline = do
        q <- label.labelQuantifier
        j <- q.quantJoin
        case j.joinKind of
          Barrier _ -> j.joinDeadline
          Fork      -> Nothing
      twoClocksTakeThisArm = isJust label.labelDeadline && isJust barrierJoinDeadline

      armTrigger = case action.modal of
        DMustNot -> Nothing
        _ | twoClocksTakeThisArm -> Nothing
          | otherwise            -> memberDeadline label

      -- The caption for whichever LEST arm this obligation turns out to have.
      -- It carries the modal too: without it a consumer holding only this edge
      -- cannot tell a missed deadline from a prohibition that was breached,
      -- which is the whole of smucclaw/l4-ide#927. The party and the guard are
      -- deliberately absent — they belong to the obligation, which the HENCE
      -- edge already restates, and repeating them here would read as a second,
      -- contradictory copy of the rule. The DEADLINE is not in that company:
      -- see 'armTrigger'.
      -- The caption reads the deadline that expires a MEMBER, which for a
      -- quantified rule may sit on the join line rather than on the act; see
      -- 'memberDeadline'. Passing @due@ here said "unreachable: no WITHIN" of
      -- a rule the evaluator does expire.
      lestLabel = TransitionLabel
        { labelParty    = Nothing
        , labelModal    = modalVal
        , labelAction   = lestArmWording action.modal (memberDeadline label)
        -- The arm is not the act, so it binds nothing: its caption is
        -- "timeout", and "the rule binds `amount`" under it would attach the
        -- act's open names to the edge taken when the act did NOT happen.
        , labelBinds    = Nothing
        , labelOpening  = Nothing
        , labelDeadline = armTrigger
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
    -- The fallback name is used only where the target is not already a state
    -- (wireTarget's TargetOther): a bare RAND / ROR / IF below a
    -- HENCE, in practice. It used to be the word @next@, which named neither
    -- the construct that put the node there nor the obligation it continues,
    -- so @ok/contracts.l4@ drew a junction captioned @next@. Naming it after
    -- the arm and its obligation says both, and the junction's own construct
    -- arrives separately on 'stateConstruct'.
    Just henceExpr -> wireTarget fromState label HenceTransition ("HENCE of " <> selfName) henceExpr

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
    Just lestExpr -> wireTarget fromState lestLabel LestTransition ("LEST of " <> selfName) lestExpr

    Nothing -> do
      -- No LEST specified - use default based on modal
      case action.modal of
        -- MAY without LEST: the permission lapses to FULFILLED, and that is a
        -- real edge, drawn here rather than left for a consumer to synthesise.
        --
        -- Where HENCE is absent or is FULFILLED the lapse lands on the same
        -- state the HENCE edge lands on, by a second route and under its own
        -- caption. Where HENCE points at another OBLIGATION the two arms part
        -- company, and this is then the only route to FULFILLED there is.
        -- Measured:
        --
        --   PARTY Alice MAY pay WITHIN 5 HENCE (PARTY Bob MUST deliver WITHIN 10)
        --     (`WAIT UNTIL` 100)          ==> FULFILLED
        --     PARTY Alice DOES pay AT 3   ==> PARTY Bob MUST deliver WITHIN 10
        --
        -- so expiry reaches FULFILLED (@fromMaybe fulfilExpr lest@ in
        -- L4.EvaluateLazy.Machine) while HENCE reaches Bob's obligation. Until
        -- 2026-09-17 this arm was drawn only under a quantifier's join line and
        -- the single-party case drew nothing, so the graph showed no route to
        -- FULFILLED at all; L4.Bpmn.Lower inherited the gap and made it worse,
        -- synthesising a lapse timer that routed "wherever HENCE lands", which
        -- in this shape is the wrong place. Drawing the edge here retires that
        -- synthesis (smucclaw\/l4-ide#927 is a different bug in the same area).
        --
        -- Under a quantifier's join the same arm goes to Fulfilled and never to
        -- where HENCE goes. Barrier: a lapsed member means the join can never
        -- fire, the HENCE is skipped and the member's own FULFILLED is returned
        -- as the barrier's (Machine.hs, Barrier1's last arm and the note on
        -- 'barrierFail'). Fork: the HENCE arises only from a member's ACT; a
        -- member whose permission expires unexercised spawns nothing. Both
        -- measured, 2026-09-15\/16, on the corporate resolution (spec §2.2.1
        -- Pattern B): nobody approves and the chair publishes anyway →
        -- FULFILLED under both joins; one approval with no publication →
        -- BREACHED, the chair, fork and barrier alike
        -- (ok\/every\/tests\/run-modals.golden). A first version of that arm
        -- drew it for the barrier only, on the concurrency review's reading
        -- that a fork "carries the real HENCE" per member; that reading was
        -- wrong at runtime and was caught by re-measurement the next day.
        --
        -- THE DEADLINE DECIDES WHETHER THERE IS AN ARM AT ALL, which is
        -- 'lestArmWording's rule read back: with no @WITHIN@ there is no expiry
        -- event, so nothing can take this edge. An explicit @LEST@ with no
        -- @WITHIN@ is still drawn, captioned 'noTriggerWording', because the
        -- author wrote one and the graph says why it cannot fire; a synthesised
        -- arm has no such author, and inventing an unreachable edge where the
        -- source is silent would be the graph asserting something of its own.
        DMay
          | isJust (memberDeadline label) -> do
              fulfilledId <- getTerminalState "Fulfilled" TerminalFulfilled
              addTransition fromState fulfilledId lestLabel LestTransition
          | otherwise -> pure ()
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

-- | Generate a descriptive name for an obligation (for intermediate states).
--
-- The @WITHIN@ is part of the name, and that is the whole of what tells two
-- states apart when their obligations share an act.
-- @jl4\/examples\/legal\/promissory-note.l4@ writes one @MUST@ three times
-- (@:90@, @:103@, @:111@) — same party, same modal, same act pattern — under
-- an escalating clock, @\`Next Payment Due Date\`@, then
-- @\`Default After Days Beyond Commencement\`@, then none at all. Until
-- 2026-09-22 the node printed @PARTY … MUST …@ and stopped, so three of the
-- note\'s six states carried the identical string and the only difference the
-- picture drew was on their out-edges. @PARTY … MUST … WITHIN …@ is one
-- sentence in the source and the node now says all of it — in the source\'s
-- own keyword, which is not always @WITHIN@ ('windowClause').
--
-- __Usually this MOVES a copy of the deadline rather than adding one__, and
-- the exception is worth stating because it is the common shape. The window
-- prints on the @HENCE@ edge as well, and "L4.StateGraph.Dot" suppresses that
-- copy wherever the source state is this obligation\'s own entry — the same
-- 'stateSite' \/ @labelSite@ test that suppresses the party, the modal and the
-- act. But that suppression is conditional: it is dropped where it would
-- leave the arrow BLANK, so an obligation whose ONLY caption is its window
-- keeps the full restatement and the window is then drawn twice, once on the
-- node and once on the arrow. Measured 2026-09-22 on
-- @jl4\/tests-cli\/fixtures\/state-graph-captions.l4@ shape 5:
-- @[label="theChair must pay 1 WITHIN 9"]@ on the node and
-- @[label="theChair MUST pay 1 [9]"]@ on its arrow. A second copy of a true
-- sentence is the price of not drawing an empty one.
--
-- Where the suppression does hold, the division of labour is clean: the node
-- says the obligation, the green arrow says what is NEW along it, the red
-- arrow says the clock that breaches it.
--
-- The @LEST@ arm keeps its own bracket ('armTrigger'), which is NOT the copy
-- this moved. It can name a different quantity: 'memberDeadline' falls back to
-- the join line\'s @WITHIN@ for a rule whose act has none, so on that shape the
-- node says nothing and the red arm says the join\'s clock.
--
-- Only the obligation's own window travels here, never the join line's: the
-- join is drawn by 'L4.StateGraph.Dot.formatTransitionLabel' on the edge,
-- where a barrier and a fork stay distinguishable.
describeDeonton :: Deonton Resolved -> Text
describeDeonton MkDeonton{subject, action, due} =
  describeAction subject action <> maybe "" (\ d -> " " <> windowClause d) due

-- | The window as a CLAUSE, keyword and all, for a place that is spelling out
-- a rule rather than bracketing a quantity.
--
-- The keyword is not always @WITHIN@, and assuming it was drew
-- @buyer must Order buyer WITHIN BEFORE (YMD OF 2026, 6, 30)@ on the state
-- @jl4\/examples\/lsp\/semantic-tokens\/after.l4:21@ mints — measured 2026-09-22
-- by sweeping @jl4\/examples@, @doc@ and @jl4-core\/libraries@, ONE node in the
-- whole corpus, which is exactly the population that makes a wrong guess
-- survive review. Only a nested obligation is at risk: a top-level @BEFORE@
-- such as @jl4\/examples\/ok\/every\/run-after.l4:409@ enters at @initial@ and
-- mints no node to be wrong on. 'windowText' already carries @BEFORE@ because a
-- consumer reading the bracket as a duration has to see at once that it is not
-- one, so the two keywords have to be told apart here too.
windowClause :: Deadline Resolved -> Text
windowClause d = case d of
  MkDeadline{} -> "WITHIN " <> windowText d
  MkBefore{}   -> windowText d

-- | An act's closing edge as the picture spells it, in ONE place.
--
-- The node ('describeDeonton') and the edge ('extractDeonton'\'s
-- @deadlineText@) print the same @WITHIN@, and "L4.StateGraph.Dot" suppresses
-- the second on the strength of them being the same clause. Two spellings of
-- it would make that suppression a lie the first time either moved — the
-- hazard @L4.StateGraph.Dot.transitionToEdge@ documents for the party and the
-- act, one function away.
--
-- An anchored deadline (R-Q7, §5.1.1) prints as its source form, @5 OF THE
-- JOIN@, the duration bracketed where the source needs it ('edgeText');
-- @L4.Bpmn.Lower.parseDuration@ cannot read an anchor and the lowering reports
-- it as anchored, which is the stated limit. A @BEFORE@ (R-X5, §5.1.2) keeps
-- its keyword for the same reason: it is a date, not a duration, and the
-- lowering must be able to see that.
windowText :: Deadline Resolved -> Text
windowText = \ case
  d@MkDeadline{} -> edgeText d
  d@MkBefore{}   -> "BEFORE " <> edgeText d

-- | 'describeDeonton' for a subject and act held separately, which is how
-- 'extractDeonton' has them: it needs the same words to name the states its
-- own arms land on ('wireTarget'\'s fallback names).
--
-- The @WITHIN@ is deliberately NOT here. This names a state that some ARM of
-- the obligation lands on — @HENCE of …@ — and that state is not the
-- obligation\'s entry, so its window has already expired or been met by the
-- time the contract is there.
describeAction :: Subject Resolved -> RAction Resolved -> Text
describeAction subject action =
  let partyT = subjectText subject
      modalT = case action.modal of
        DMust    -> "must"
        DMay     -> "may"
        DMustNot -> "must not"
        DDo      -> "do"
      actionT = prettyPattern action.action
  in partyT <> " " <> modalT <> " " <> actionT

-- | @rangeOf@ an obligation's act: the key its own edges carry in 'labelSite',
-- stamped on the state that is its entry. One reader, one range — see
-- 'stateSite'.
deontonSite :: Deonton Resolved -> Maybe SrcRange
deontonSite MkDeonton{action} = rangeOf action

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

-- | Pretty-print an act pattern to text, in L4's own spelling.
--
-- __One clause, one spelling.__ This is 'L4.Print.printActionPattern' and
-- nothing else, collapsed onto one line. Until 2026-09-22 it was a second,
-- hand-written printer, and what that cost was one clause reading three ways.
-- @jl4\/examples\/bpmn\/tenancy.l4:56@ is
-- @MUST Pay (EXACTLY t) (EXACTLY theLandlord) amount@ in the source; @l4 lts@
-- said that, because it goes through 'L4.Print.printActionPattern'
-- (@jl4-core\/src\/L4\/Lts\/Marking.hs:419@, importing it at @:106@), while the
-- state-graph node said @Pay t theLandlord \`amount\`@ and the BPMN task name
-- said a third thing again. A reader moving between the three outputs had to
-- take it on the verb alone that they were one obligation.
--
-- Reusing the printer settles three things that had been separate arguments:
--
--   * @EXACTLY@ is re-emitted exactly where 'L4.Syntax.exactlyKeywordRange'
--     says the AUTHOR wrote it (@jl4-core\/src\/L4\/Print.hs:1267-1269@) —
--     \"A pattern whose source said EXACTLY keeps saying it\", in that
--     printer\'s own words. It is NOT added to an R1-synthesised 'PatExpr',
--     which carries no keyword because the source had none. A caption that
--     marked both would spell in the picture something the source does not
--     say, and would disagree with @l4 lts@ again.
--   * A compound pinned expression is BRACKETED ('pinnedNeedsParens',
--     @jl4-core\/src\/L4\/Print.hs:1271-1275@), so @MUST pay (EXACTLY base
--     PLUS 1)@ no longer draws as @pay base PLUS 1@ — which reads as @pay@
--     applied to three arguments.
--   * There is no back-quote mark of our own. A name is back-quoted exactly
--     when L4 would back-quote it, through the same 'L4.Print.quoteIfNeeded'
--     every other printer uses. Between 2026-09-21 and 2026-09-22 a BINDER was
--     back-quoted as a placeholder mark; it meant two things at once on one act
--     (@\`The Lender\`@ quoted for its spaces, @\`Amount Transferred\`@ quoted
--     for binding), and it rode into the BPMN task name and from there into an
--     XML @name=@ attribute that four external parsers read
--     (@etc\/check-bpmn-soundness.mjs@, @etc\/validate-bpmn.mjs@ against
--     bpmn-moddle, @etc\/check-bpmn-kie.sh@ against jBPM, and
--     @etc\/check-bpmn-dmn-refs.mjs@). A placeholder mark, if the picture ever
--     wants one again, belongs where the picture is drawn and nowhere a machine
--     reads.
--
-- __The arguments are PRINTED.__ Until 2026-09-21 a 'PatApp' with arguments
-- drew as @f ...@ and a 'PatCons' as @h ...@, which is not an abbreviation of
-- the act so much as a deletion of it: every obligation over the same verb then
-- drew the SAME label. @jl4\/examples\/ok\/contracts.l4@ has two, @payment price@
-- (@:13@) and @payment fine@ (@:18@), and they drew as the one string
-- @payment ...@.
--
-- WHERE that elision travelled, precisely, because the commit that fixed it
-- said this wrong. This function is read by 'describeAction' (the state NODE
-- names) and by 'extractDeonton' (an edge\'s @labelAction@), and from the
-- second it reaches the BPMN task names and
-- 'L4.StateGraph.Dominators.renderTransition'. It did NOT reach @l4 lts@, which
-- has always gone through 'L4.Print.printActionPattern':
-- @etc\/lts-reader-proxy\/tenancy\/A.txt@, an @l4 lts@ block cut BEFORE the
-- change, already shows the arguments printed. Commit @b12383af5@\'s message
-- says the elision rode into @l4 lts@ as well; that is false.
--
-- __What un-eliding did NOT buy, and what a reader should not expect of it.__
-- Two obligations that share an act pattern still draw the same label, because
-- the label is the act and the act is the same. All three @MUST@s of
-- @jl4\/examples\/legal\/promissory-note.l4@ (@:90@, @:103@, @:111@) are one
-- act written out three times; what tells them apart is the @PROVIDED@ guard
-- and the @WITHIN@, and both of those live on the transition, not on the act.
-- Commit @b12383af5@\'s message claims this function separated those three
-- states. It did not and could not; see 'describeDeonton', which carries the
-- @WITHIN@ onto the node for exactly that reason.
--
-- __What delegating COSTS, and where that is paid.__ The printer is
-- re-emitting source, so it prints a binder and an R1-resolved reference the
-- same way: @MUST payment price@ with no @price@ in scope and
-- @MUST payment n@ with @n MEANS 2@ both draw bare
-- (@jl4\/examples\/ok\/contracts.l4:13@ and @:53@, the second\'s @n@ at @:56@).
-- That is right for re-emitting source and silent about what a reader can
-- tell, and the picture is asking \"what discharges this\" — to which a binder
-- answers ANY payment and a pin answers exactly that one. The distinction is
-- carried by 'patternBinders' and 'labelBinds', beside the act and never
-- inside it, so this function stays one spelling of one clause.
prettyPattern :: Pattern Resolved -> Text
prettyPattern = oneLine . docText . printActionPattern

-- | Collapse a rendering onto one line: a caption must not carry a line break
-- it did not choose.
--
-- 'docText' lays out @Unbounded@ (@jl4-core\/src\/L4\/Print.hs:37-38@), so it
-- inserts no break of its own and this is a guard rather than a repair — but a
-- 'Doc' can still carry a hard break, and nothing in the type says an act
-- pattern will not. A newline would land inside @labelAction@, where
-- 'L4.StateGraph.Dot.wrapLabel' takes it as a hard break mid-caption and where
-- @L4.Bpmn.Lower@ puts it inside an XML @name=@ attribute, whose value
-- normalisation folds it to a space on the way back out — a round trip that
-- changes the name with nothing said.
oneLine :: Text -> Text
oneLine = Text.unwords . Text.words

-- | The names an act pattern BINDS, in source order: its 'PatVar' leaves.
--
-- A 'PatVar' and a 'PatExpr' are different CONSTRUCTORS, which is the whole of
-- why this is decidable here and not a guess about scope. The parser builds
-- neither: it writes @'PatApp' n []@ for a bare name, and the checker then
-- rewrites it to a 'PatVar' when the name is NOT in scope
-- (@jl4-core\/src\/L4\/TypeCheck.hs:4249-4251@) and R1 rewrites it to a
-- 'PatExpr' when it resolves to a non-constructor
-- (@jl4-core\/src\/L4\/TypeCheck.hs:4239-4243@). So a declared nullary act
-- stays a 'PatApp' and binds nothing, which is what keeps this from calling
-- every act in the corpus a binder.
--
-- __A 'PatVar' at the TOP is a different fact and gets a different sentence,
-- corrected 2026-09-23.__ This note used to say it was "reported the same way:
-- the sentence is true of it, and a reader of a caption has no use for the
-- difference". The sentence IS true of it and the conclusion still does not
-- follow. @jl4\/examples\/ok\/contracts.l4:15@ writes @PARTY B MUST return@
-- where @Action IS ONE OF delivery, payment, foo@ (@:1-5@) declares no
-- @return@, so @return@ binds the whole act; the node then draws @B must
-- return WITHIN 10@ and its arrow drew @the rule binds \`return\`@, from which
-- a reader takes @return@ for the act and the clause for a parameter of it.
-- What is true is the opposite and stronger: there is NO act, and any act by B
-- discharges the obligation — which is the picture's own "what discharges it"
-- question, not a detail beside it.
--
-- The what-if already draws this line and it is the half this function had
-- dropped: @L4.Lts.WhatIf@'s @reach@ answers @BoundWholeAction@ with "any act
-- by this party would match this obligation" and @BoundArgument@ with "any
-- value in that place". Matching @bindsClause@ alone therefore did not give
-- the reader ONE sentence across the picture and the what-if, which is what
-- matching it was for; it gave them one sentence where the what-if has two.
--
-- Measured before changing it, because the population is the whole argument:
-- over every @.l4@ under @jl4\/examples@, @doc@ and @jl4-core\/libraries@ the
-- renderer emits __46 binds clauses, of which 45 are argument binders and
-- exactly ONE is a whole act__ — @contracts.l4@'s @return@. One witness in the
-- corpus is the population that lets a wrong guess survive review, not a reason
-- to leave it; a caption is read by whoever meets it, and there is nothing else
-- on that arrow.
--
-- __The spelling matches the what-if on purpose, and the what-if is not
-- importable from here.__ @L4.Lts.WhatIf.patternBinders@ is the same recursion
-- with a @BoundScope@ tag on each binder, and @L4.Lts.WhatIf.bindsClause@
-- renders it with the same words; that module is on branch
-- @lts\/whatif-bound-values@ and NOT on @unstable@ (checked 2026-09-22:
-- @git log origin\/unstable -- jl4-core\/src\/L4\/Lts\/WhatIf.hs@ is empty), so
-- this is a second copy and says so. If that branch lands, one of the two
-- should go.
patternBinders :: Pattern Resolved -> [Text]
patternBinders = \ case
  PatVar _ v    -> [resolvedToText v]
  PatApp _ _ ps -> concatMap patternBinders ps
  PatCons _ a b -> patternBinders a <> patternBinders b
  PatLit _ _    -> []
  PatExpr _ _   -> []

-- | The binders as the picture says them, or 'Nothing' where there are none.
--
-- __The picture and @l4 lts@ carry the same DISTINCTION, not the same
-- sentence, and an earlier version of this note claimed otherwise.__ It said a
-- reader moving between the two "meets ONE sentence". They do not, and the
-- claim was measured false on 2026-09-23 against the merged what-if (#452),
-- which prints, for @jl4\/examples\/ok\/contracts.l4@ and
-- @jl4\/examples\/legal\/promissory-note.l4@ respectively:
--
-- > this obligation's pattern matches any act by B: the rule binds \`return\`
-- >   rather than naming an act
-- > this obligation's pattern matches any \`Amount Transferred\` the condition
-- >   accepts: the rule binds it and tests it only through that condition
--
-- Ninety-seven and one hundred and thirty characters. A caption cannot carry
-- either: it is wrapped at 'L4.StateGraph.Dot.labelWidth' (36 columns) inside a
-- box GraphViz sizes to it, and a 97-character sentence on an arrow is the
-- defect this whole branch exists to remove. So the picture says the short
-- form — @the rule binds \`price\`@, or @any act by this party would match this
-- obligation@ where the act itself is open — and the list says the long one.
--
-- What must NOT drift is the distinction: both surfaces separate an open
-- ARGUMENT from an open ACT, and they must never disagree about which a given
-- obligation is. The shared vocabulary is "binds" and the back-quoted name;
-- the sentences around it are free to differ, because one has a line and the
-- other has a box. Do not "fix" this by lengthening the caption.
--
-- The back quotes are the picture\'s, not the act\'s: they are here, in a
-- clause "L4.StateGraph.Dot" renders and no machine parses, and never inside
-- 'prettyPattern'.
bindsClause :: Pattern Resolved -> Maybe Text
bindsClause = \ case
  -- The whole act is open. Say what that MEANS for the reader's question, not
  -- which name holds the hole; the name is already on the node.
  PatVar _ _ -> Just "any act by this party would match this obligation"
  p          -> case patternBinders p of
    [] -> Nothing
    bs -> Just ("the rule binds " <> Text.intercalate " and " (map quoted bs))
 where
  quoted n = "`" <> n <> "`"
