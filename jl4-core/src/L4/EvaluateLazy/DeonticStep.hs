-- | The deontic step log: one record per scrutiny of one event by one
-- obligation, on the contract clock.
--
-- This is P2b of @specs/todo/lexipedia-superset/LTS-VISUALISER.md@ (§4.3,
-- amended by §4.9 "What follows for P2"). It is the one piece of back end the
-- LTS visualiser needs from the evaluator, and it defines /no second
-- semantics/ (§2.4): every step is written at the point where
-- 'L4.EvaluateLazy.Machine' has already decided what happens, and records
-- that decision. Nothing here is consulted by the machine.
--
-- The log is OPTIONAL and off by default (ruling R5, §8): it rides an
-- @IORef@ in the reader environment exactly as 'traceEval' does, and every
-- call site checks that @Maybe@ before it computes anything. With the log
-- off, the work the machine does for it is carrying state it never reads:
-- a lazy 'NormKey' through the contract frames (never forced), the
-- re-offer mark @ev'reoffered@ the machine already looked up at @Contract1@
-- (a @Bool@ when P2b was built; the EVERY wave's LEST pass re-typed it, see
-- 'Reoffered') through six more frames past the one that consults it, and
-- a @pending :: Maybe DeonticStep@ (always 'Nothing' when off) on the
-- @ResolveParty@ frame.
--
-- == What a consumer can rely on
--
-- * Steps are newest-last, in the order the machine took them.
-- * 'dsClock' is the CONTRACT clock (the obligation's own time value),
--   never wall time. The ledger's @txTime@ is the wrong axis for this
--   (§4.2).
-- * 'NormKey' is the §3.4 correlation key with §4.9's per-member identity:
--   the source range of the 'L4.Syntax.RAction', the activation ordinal
--   (the /n/-th time this trace entered that site), and the bearer. Under an
--   @EVERY@ the members share a site and differ in bearer and ordinal.
-- * An event can appear more than once: 'WitnessedOnly' by the obligation
--   whose expiry it revealed, then 'Reoffered' by each continuation it was
--   handed to in turn (§4.4; an event past @k@ LEST windows appears @k+1@
--   times, EVERY-EACH-QUANTIFIER-SPEC §5.2.1). The animator must not draw
--   that as several events. A barrier's STATE-layer
--   @LEST@ (@ONCE ALL HAVE WITHIN d@ missed, 'JoinExpired') is handed the
--   members' own stream from the first event past the state deadline on
--   (@BarrierTrim@, 2026-09-16), UNMARKED: an event a member 'Consumed' —
--   the completion that landed after the deadline — appears again under
--   the @LEST@'s obligation as a fresh look ('WitnessedOnly' on a
--   mismatch, 'Consumed' on a match), not as 'Reoffered'. The re-offer
--   mark is the act layer's (@Contract5@); nothing marks the state layer's
--   hand-off. A consumer counting events must pair those looks by stamp,
--   party and action, not by the mark (pinned by DeonticStepSpec case 18).
--
-- == Loud and silent
--
-- A step the machine never logs is silent: nothing errors, the log is merely
-- shorter than the run. The call sites are enumerated in the LANDED block of
-- spec §4.3, and 'test/DeonticStepSpec.hs' pins the exact sequence for each
-- shape of contract; a machine change that skips a site turns those tests
-- red, which is the only guard.
module L4.EvaluateLazy.DeonticStep
  ( -- * The step
    DeonticStep (..)
  , NormKey (..)
  , MemberOf (..)
  , JoinKind (..)
  , isBarrier
  , EventKey (..)
  , Scrutiny (..)
  , StepOutcome (..)
  , Branch (..)
  , JoinProgress (..)
  , JoinNote (..)
  , JoinResult (..)
  , Side (..)
  , BreachSummary (..)
  , FailureSummary (..)
  , NamedParty (..)
    -- * The log
  , DeonticLog (..)
  , newDeonticLog
  ) where

import Base
import qualified Base.Map as Map
import L4.Evaluate.ValueLazy (RBinOp (..))
import L4.Parser.SrcSpan (SrcRange)
import L4.Syntax (DeonticModal (..), Resolved, Threshold (..))

-- | One scrutiny of one event by one obligation, on the contract clock.
--
-- Spec §4.3 wrote @dsClock :: Rational@. It is a @Maybe@ here because four
-- step shapes genuinely have no clock in hand: a 'Waiting' step logged
-- before the obligation has forced its time (a @#TRACE@ with no events at
-- all — the time is still a thunk, and forcing it for the log would change
-- what the machine evaluates); a 'Joined' step, whose frame holds two
-- values and no time; a 'Breached' step for an explicit @BREACH@
-- terminal, which the expression arm constructs with no time in hand (the
-- 'ExplicitBreach' reason carries none either); and a barrier with no
-- @LEST@ whose member ends in a value that carries no time — a 'JoinStalled'
-- (the member's 'ValFulfilled'), or a 'JoinFailed' whose member's breach was
-- itself an explicit @BREACH@ (a missed deadline carries its stamp, and that
-- 'JoinFailed' is clocked). Every other step carries the clock the machine
-- had.
data DeonticStep = MkDeonticStep
  { dsClock    :: !(Maybe Rational)
    -- ^ the contract clock at this step
  , dsEvent    :: !(Maybe EventKey)
    -- ^ the event under scrutiny; 'Nothing' for a step no event caused
    -- ('Waiting', 'Joined', the @EVERY@ join's own steps)
  , dsScrutiny :: !Scrutiny
    -- ^ how this step related to its event (§4.4)
  , dsNorm     :: !(Maybe NormKey)
    -- ^ which norm instance took the step. Spec §4.3 wrote this as a bare
    -- 'NormKey'; it is a @Maybe@ because a 'Joined' step belongs to an
    -- @AND@\/@OR@ compound, which is not a norm instance (§2.3 gives places
    -- to obligations, not to connectives) and, as 'ValROp' carries no
    -- annotation, has no site either. Every other step has a key.
  , dsOutcome  :: !StepOutcome
  , dsJoin     :: !(Maybe JoinProgress)
    -- ^ §4.9's amendment: what this step did to an @EVERY@ join, when the
    -- norm is a member of one. See 'JoinProgress' for why the join's own
    -- release is NOT recorded here.
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | The correlation key of spec §3.4, with §4.9's per-member identity.
--
-- The runtime has the site in hand because 'L4.Evaluate.ValueLazy.ValObligation'
-- keeps the whole @RAction Resolved@, whose annotation carries the source
-- range. It is the STATIC side (B1) that has to learn to carry it.
data NormKey = MkNormKey
  { nkSite       :: !(Maybe SrcRange)
    -- ^ @rangeOf@ the 'L4.Syntax.RAction'; 'Nothing' for a synthesised
    -- action with no source (none exist today, but the annotation allows it)
  , nkActivation :: !Int
    -- ^ the /n/-th entry into that site in this trace, counting from 1.
    -- A recursive continuation (@x MEANS PARTY p MUST a WITHIN d LEST x@)
    -- re-enters the same site; the ordinal is what tells the entries apart.
    -- Under an @EVERY@, each member's obligation is its own entry, in roll
    -- order. Always @0@ when the log is off.
  , nkBearer     :: !(Maybe Text)
    -- ^ the party, keyed exactly as the ledger keys it
    -- ('L4.EvaluateLazy.Machine.partyKeyWHNF'; for a constructor party that
    -- is its pretty layout, unforced fields and all). 'Nothing' when the
    -- machine has not forced the party expression yet: a @PARTY p@
    -- obligation evaluates @p@ lazily, on the match path at @Contract6@ and
    -- on the expiry path at @ResolveParty@. The log PEEKS and never forces,
    -- so a 'Waiting' step before any event, or an expiry that goes straight
    -- to a breach with a computed party, may not know its bearer (a nullary
    -- constructor party is allocated as a value and is known). Under an
    -- @EVERY@ the roll call forces every member, so members always know
    -- theirs.
    --
    -- This is the key the cast register ('DeonticLog.dlMembers') is looked
    -- up by, which is why it stays beside 'nkBearerName' rather than being
    -- replaced by it: the register is written at the roll call, before any
    -- field has been forced, and only this key exists then.
  , nkBearerName :: !(Maybe Text)
    -- ^ the party as the list writes it: the forced value rendered through
    -- the same printer "L4.Lts.Marking" renders 'lnBearer' with
    -- ('L4.Print.prettyLayout' on a @Value NF@ — @Tenant OF "Alice"@, not
    -- @Tenant OF &161\@main.l4@), so the two compare by equality. Recorded
    -- where the machine has forced the party's FIELDS, not just its head:
    -- the party equality at @Contract7@ forces them (all of them on a
    -- match, up to the first difference on a mismatch), so it is read at
    -- @Contract8@ and carried into every later step of the same scrutiny;
    -- the expiry path reads it at @ResolveParty@. Still a peek, never a
    -- force: 'Nothing' while any field is a thunk, which is the case for a
    -- 'Waiting' step before any event has been compared. Where it is
    -- 'Nothing', 'nkBearer' is what there is.
  , nkModal      :: !DeonticModal
    -- ^ all four, including @DDo@
  , nkMember     :: !(Maybe MemberOf)
    -- ^ §4.9 "Sequencing": which @EVERY@ this obligation is a member of, if
    -- any. The site and bearer alone cannot say whether a join is waiting
    -- on this norm; this can.
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | Membership of an @EVERY@'s cast, as known when the member was armed.
data MemberOf = MkMemberOf
  { moJoin     :: !JoinKind
  , moIndex    :: !Int            -- ^ position in the roll, from 1
  , moTotal    :: !Int            -- ^ size of the cast
  , moJoinSite :: !(Maybe SrcRange)
    -- ^ @rangeOf@ the join line (@ONCE ALL HAVE@ \/ @UPON EACH@) when there
    -- is one, else of the whole @EVERY@ rule; the site the join's own steps
    -- ('JoinReleased', 'JoinExpired', 'JoinFailed') carry
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | The three families an @EVERY@ can assemble (EVERY-EACH-QUANTIFIER-SPEC
-- §2.4, §3.1–§3.3).
--
-- A 'Barrier' carries the 'Threshold' its @ONCE@ line waits for (P2c, spec
-- §4.9: the marking is written against 'Threshold', not against the phase-1
-- barrier alone), so a consumer reading the cast register back out of the
-- steps can say what "released" would take without re-reading the source.
data JoinKind
  = Barrier !(Threshold Resolved)
    -- ^ @ONCE …@: level-triggered, the continuation fires once, when the
    -- threshold is met
  | Fork          -- ^ @UPON EACH@: edge-triggered, each member carries its own copy
  | Distributive  -- ^ no join line and no continuation: one obligation per member
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | Is this the barrier family? The 'Threshold' is what it waits for.
isBarrier :: JoinKind -> Bool
isBarrier = \ case
  Barrier{}    -> True
  Fork         -> False
  Distributive -> False

-- | What identifies the event a step looked at. The stamp is always known
-- (it is what the machine compared against the deadline); party and action
-- are reported when the machine had forced them by the time of the step and
-- left as 'Nothing' otherwise, because forcing them for the log would change
-- evaluation.
data EventKey = MkEventKey
  { ekStamp     :: !Rational
  , ekParty     :: !(Maybe Text)   -- ^ keyed as 'nkBearer' is
  , ekPartyName :: !(Maybe Text)
    -- ^ rendered as 'nkBearerName' is, when the party's fields had been
    -- forced (the equality at @Contract7@ forces the event's party
    -- alongside the obligation's); 'Nothing' otherwise
  , ekAction    :: !(Maybe Text)   -- ^ the action value, pretty-printed
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | How a step related to its event (§4.4, R6).
--
-- 'Reoffered' takes precedence: it marks the SECOND look at an event that an
-- expiring obligation re-offered to its continuation, whatever that look
-- decided. A consumer counting events counts a 'Reoffered' step as zero.
data Scrutiny
  = Consumed
    -- ^ the event was taken off the stream by a match
  | WitnessedOnly
    -- ^ the event was looked at and passed over: it advanced the clock
    -- (a mismatch, a failed guard) or revealed an expiry and was re-offered
    -- to the continuation
  | Reoffered
    -- ^ this is a continuation's look at a re-offered copy of an event —
    -- every layer's look, since a copy is handed on to each expired layer
    -- in turn (EVERY-EACH-QUANTIFIER-SPEC §5.2.1, 2026-09-16: an event past
    -- @k@ LEST windows is looked at @k+1@ times, the last look by the first
    -- layer whose window it is not past), including a look that reveals
    -- another expiry; a chain whose deadlines stop advancing is refused by
    -- the machine, never consumed
  | NoEvent
    -- ^ the step had no event: the stream ran out, or a join reduced
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | What the step decided. The single-obligation outcomes name the
-- @ContractFrame@ constructor that takes them; the join outcomes name the
-- @EVERY@ machinery.
data StepOutcome
  = Waiting
    -- ^ @Contract1@, @ValNil@: no events left; the residual stands
  | PartyMismatch
    -- ^ @Contract8@, the event's party is not the obligation's; next event
  | ActionMismatch
    -- ^ @Contract11@, the action pattern did not match; next event
  | GuardFailed
    -- ^ @Contract10@, the @PROVIDED@ came out false; next event
  | EarlyAct !Rational
    -- ^ @Contract10@, the act by this party, the pattern and the @PROVIDED@
    -- all matched — but before the window's opening edge (@AFTER@,
    -- EVERY-EACH-QUANTIFIER-SPEC §5.1.2, R-X6): a NULLITY, neither
    -- performance nor a violation. The obligation stands unchanged and the
    -- next event is tried; the run's note reports the act. Carries the
    -- instant the window opens, on the contract clock. Logged since
    -- 2026-09-17 (adversarial round 1 of the third rebase, S2): without it
    -- the log had no record of the look, and a what-if read the act as
    -- taken by nobody
  | Matched !Branch
    -- ^ @Contract10@, the action matched and the guard held; routed per modal
    -- (a @SHANT@ routes to @LEST@, or to a breach when it has none)
  | Expired !Branch !Rational
    -- ^ @Contract5@, the event's stamp is past the deadline (carried);
    -- routed per modal: @MUST@\/@DO@ to @LEST@ or a breach, @SHANT@ to
    -- @HENCE@, @MAY@ to @LEST@ (defaulting to @FULFILLED@)
  | Breached !BreachSummary
    -- ^ the @BREACH@ expression (@LEST BREACH@, @BREACH BY p@, a bare
    -- @BREACH@): the machine constructed an explicit breach value here. It
    -- is a terminal, not an obligation, so the step has no norm; the
    -- expression arm holds no clock and no event either. A @DeadlineMissed@
    -- breach is NOT logged this way — it is the 'Expired' \/ 'Matched'
    -- @ToBreach@ step of the obligation that missed
  | Joined !RBinOp !JoinNote
    -- ^ @RBinOp1@ (the @OR@ short-circuit on a fulfilled left operand) or
    -- @RBinOp2@ (both operands are values): what the compound reduced to,
    -- which side decided it, and whether CSL's tie-break was what decided
  | JoinReleased
    -- ^ the @EVERY@ barrier: every arm satisfied and the @ONCE … WITHIN@
    -- (if any) met; the shared @HENCE@ runs. Also logged for an empty cast,
    -- which is vacuously satisfied.
  | JoinExpired !Branch !Rational
    -- ^ the @EVERY@ barrier: every arm satisfied, but the last of them after
    -- the @ONCE … WITHIN@ deadline (carried); the shared @LEST@ runs, or
    -- the compound breaches
  | JoinFailed !Branch
    -- ^ the @EVERY@ barrier: a member definitively did not complete. To
    -- @LEST@ when the barrier has one; to a breach when the member's own
    -- breach stands as the barrier's
  | JoinStalled
    -- ^ the @EVERY@ barrier, with no @LEST@: a @MAY@ member's permission
    -- lapsed. Nothing was owed, so nothing is breached, but the join can
    -- never fire; the member's @FULFILLED@ stands as the barrier's value
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | Where a routed step sends control.
--
-- Under a barrier the member's @HENCE@ and @LEST@ slots hold the join's
-- sentinels rather than anything the drafter wrote, so for a norm whose
-- 'nkMember' is a 'Barrier', 'ToHence' reads "reported satisfied to the
-- join" and 'ToLest' "reported failed to the join"; the join's own step
-- follows.
data Branch
  = ToHence
  | ToLest
  | ToBreach   -- ^ no continuation to run: a 'ValBreached' is the result
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | §4.9's amendment: what a member's step did to its @EVERY@ join.
--
-- The representation chosen is a field on the member's own step, because
-- the fact belongs to that step: it is the match (or the expiry that
-- satisfies a @SHANT@) that satisfies the arm. The join's RELEASE is
-- deliberately not a value here, and is the join's own 'JoinReleased' step
-- instead: the last member's step cannot honestly say "released", because
-- whether the barrier fires is decided after it, by the @ONCE … WITHIN@
-- check ('JoinExpired' is the other answer). So a barrier's log reads
-- @MemberSatisfied 1 3@, @MemberSatisfied 2 3@, @MemberSatisfied 3 3@, and
-- then either 'JoinReleased' or 'JoinExpired'.
data JoinProgress
  = MemberSatisfied { done :: !Int, total :: !Int }
    -- ^ barrier: this member's arm is now satisfied, @done@ of @total@.
    -- The continuation is NOT released by this step, even at @done == total@.
  | ForkContinued { member :: !Int, total :: !Int }
    -- ^ fork: this member's own copy of the continuation runs now (its
    -- @HENCE@ on a match, its @LEST@ on an expiry), independently of the
    -- other members
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | What an @RBinOp2@ reduction did.
data JoinNote = MkJoinNote
  { jnResult   :: !JoinResult
  , jnWinner   :: !(Maybe Side)
    -- ^ the operand whose value became the compound's; 'Nothing' when
    -- 'JoinPending'
  , jnTieBreak :: !Bool
    -- ^ 'True' when both operands had breached and the winner was chosen by
    -- CSL's convention — the left for @AND@, the right for @OR@ — because
    -- their breaches were simultaneous, or one carried no timestamp
    -- (an @ExplicitBreach@)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

data JoinResult
  = JoinFulfilled
  | JoinBreached !BreachSummary
  | JoinPending    -- ^ neither operand reducible: the @ValROp@ stands
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

data Side = LeftSide | RightSide | BothSides
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | The blame a breach carries, as far as the machine has forced it.
--
-- Since R-T3 (EVERY-EACH-QUANTIFIER-SPEC §6.1, built 2026-09-15) a breach
-- names EVERY obligation that failed — one entry each, no dedup — with one
-- of them the ANCHOR, the failure the breach's time comes from. The three
-- scalars here describe the anchor, exactly as the wire's scalars do
-- (@obligatedParty@ \/ @deadline@ in "L4.Evaluate.ValueLazyJSON"): they are
-- the headline, and for a single obligation's breach they are the whole
-- story. 'bsFailures' is the full list, the anchor among it at 'bsAnchor',
-- so a compound's non-anchor failures are never dropped.
data BreachSummary = MkBreachSummary
  { bsBlame     :: !(Maybe Text)     -- ^ the ANCHOR's party, keyed as 'nkBearer'; 'Nothing' if unforced or nobody named
  , bsBlameName :: !(Maybe Text)     -- ^ the anchor's party, rendered as 'nkBearerName' when its fields were forced
  , bsStamp     :: !(Maybe Rational) -- ^ when the breach materialised (the anchor's revealing stamp); 'Nothing' for an @ExplicitBreach@
  , bsDeadline  :: !(Maybe Rational) -- ^ the anchor's deadline missed; equal to 'bsStamp' for a violated prohibition
  , bsFailures  :: ![FailureSummary] -- ^ every failure the breach names, in operand \/ roll \/ list order
  , bsAnchor    :: !Int              -- ^ the anchor's index into 'bsFailures' (0-based)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | One failed obligation of a breach, as far as forced — the log's view of
-- 'L4.Evaluate.ValueLazy.Failure'.
data FailureSummary
  = MissedSummary !(Maybe Text) !Text !Rational
    -- ^ the party (if forced), the action it owed (printed), the deadline it missed
  | DeclaredSummary !NamedParty !(Maybe Text)
    -- ^ @BREACH [BY p] [BECAUSE r]@: whom @BY@ named, the reason (if any, and forced)
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | Whom a @BREACH BY@ named, as far as forced. Whether the drafter named
-- anyone is a fact of the SOURCE, known regardless of forcing; whether the
-- machine has forced that party's cell is a fact of the RUN. The two are
-- kept apart because the log peeks and never forces: a @BREACH BY LIST bob,
-- alice@ leaves @bob@'s cell unforced unless something else shares it, and
-- collapsing "named but not yet known" into "nobody named" made the step
-- log deny a party the drafter had written (found 2026-09-16, review of the
-- PR-A absorb).
data NamedParty
  = NobodyNamed          -- ^ a bare @BREACH@: no @BY@
  | PartyNamed !(Maybe Text)
    -- ^ @BREACH BY p@: the party, if forced; 'Nothing' means named but not yet known
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | The log's mutable state, one per capture. Modelled on 'traceEval''s
-- @IORef (DList EvalTraceAction)@, with the two counters the key needs
-- beside it.
data DeonticLog = MkDeonticLog
  { dlSteps       :: !(IORef (DList DeonticStep))
    -- ^ the steps, newest-last
  , dlActivations :: !(IORef (Map (Maybe SrcRange) Int))
    -- ^ per site, how many times this trace has entered it ('nkActivation')
  , dlMembers     :: !(IORef (Map (Maybe SrcRange, Text) MemberOf))
    -- ^ the cast register: @(action site, bearer) ↦ membership@, written
    -- when an @EVERY@ assembles its family and read when a member's
    -- obligation meets the event stream. Keyed by value because the
    -- 'ValObligation' a member becomes has no slot for its membership.
  , dlJoinDone    :: !(IORef (Map (Maybe SrcRange) Int))
    -- ^ per barrier (join site), how many arms are satisfied so far
  }

newDeonticLog :: IO DeonticLog
newDeonticLog =
  MkDeonticLog <$> newIORef mempty <*> newIORef Map.empty <*> newIORef Map.empty <*> newIORef Map.empty
