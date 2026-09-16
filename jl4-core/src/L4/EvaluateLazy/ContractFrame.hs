module L4.EvaluateLazy.ContractFrame where

import Base (Text)
import L4.Evaluate.ValueLazy
import L4.EvaluateLazy.DeonticStep (DeonticStep, NormKey)
import L4.Syntax

data ContractFrame
  = Contract1 ScrutinizeEvents
  -- ^ if elements are left in the list of the events
  -- - continue by evaluating that event else
  -- - abort with a contract breach
  | Contract2 ScrutinizeEvent
  -- ^ scrutinizes the event to extract references for
  -- party, action and timestamp of the event, continue
  -- by evaluting the time of the event
  | Contract3 CurrentTimeWHNF
  -- ^ continue by evaluating the current time
  | Contract4 ScrutinizeDue
  -- ^ checks if there's a due time, if that's the case, continue by checking
  -- timing constraints, if not, then skip the timing and go straight to checking
  -- the party
  | Contract4b ScrutinizeAnchor
  -- ^ the deadline is anchored (@WITHIN d OF …@, R-Q7): the anchor's instant
  -- has just been forced; lower it to the trace's clock (a DATE via its
  -- serial), then evaluate the duration for 'Contract5'
  | Contract4o ScrutinizeOpening
  -- ^ the window has an opening edge (@AFTER …@, EVERY-EACH-QUANTIFIER-SPEC
  -- §5.1.2, R-X5): its offset has just been forced — a NUMBER to add to the
  -- opening's anchor (or to the obligation's own clock), or a DATE, the
  -- instant itself, lowered by its serial. The opening instant is then
  -- known, and the closing edge is scrutinised as 'Contract4' would have
  -- ('L4.EvaluateLazy.Machine.scrutinizeDue').
  | Contract4oa ScrutinizeOpeningAnchor
  -- ^ the opening edge is anchored (@AFTER d OF …@): the anchor's instant
  -- has just been forced; lower it, then evaluate the offset for
  -- 'Contract4o'
  | Contract5 CheckTiming
  -- ^ scrutinizes the current time, the timestamp of the event and the due time
  -- We check if the event happens within the due time, if that's the case, we continue
  -- by checking the party and evaluting the obligation's party argument.
  -- If that's not the case, then there are two options
  -- 1. If there's a lest clause, then go on by evaluting the lest clause
  -- 2. If there's no lest clause, we attach all the information we have
  --    to a breach and return that instead
  | Contract6 PartyWHNF
  -- ^ continue by evaluating the event's party
  | Contract7 PartyEqual
  -- ^ evaluates the equality between parties
  | Contract8 ScrutinizeParty
  -- ^ checks if the party of the event matches
  -- - if yes, continue by evaluating the action of the contract
  -- - if no, continue with the next event
  | Contract9 ScrutinizeEnvironment
  -- ^ saves the environment introduced by the pattern match, extends
  -- the env of the provided clause and then goes on to evaluate that
  | Contract10 ScrutinizeActions
  -- ^ checks if the actions of the event matches the one of the obligation
  -- - if no, continue with the next event
  | Contract11 ActionDoesn'tmatch
  -- ^ if an action doesn't match, we unwind the stack via pattern match failure.
  -- - if we encounter this frame upon normal evalation, we just return the value
  --   that we are currently looking at
  -- - if we encounter this frame while unwinding, we push a frame for continuing
  --   with the next event and evaluate the remaining evnets
  | RBinOp1 RBinOp1
  -- ^ Regulative BinOp frame while evaluating a regulative expression
  | RBinOp2 RBinOp2
  -- ^ Regulative BinOp frame while evaluating the second expression of a bin op
  | QuantRoll QuantRollFrame
  -- ^ EVERY, the roll call (EVERY-EACH-QUANTIFIER-SPEC §2.2.7.5 point 5): walks
  -- the list the @WHO@ filter tests membership in, one cons cell per step,
  -- accumulating the members that pass the cast test and the filter.
  | QuantCast QuantCastFrame
  -- ^ EVERY: one candidate, forced to WHNF. Checks the cast constructor
  -- (@EVERY Tenant t@ admits only values built by @Tenant@) and then either
  -- evaluates the filter or moves on.
  | QuantFilter QuantFilterFrame
  -- ^ EVERY: the @WHO@ filter's BOOLEAN for one candidate.
  | Barrier1 BarrierStepFrame
  -- ^ EVERY, the barrier (@ONCE ALL HAVE@): the result of running ONE member
  -- of the cast over the event stream. See the @Barrier1@ NOTE in Machine.hs.
  | Barrier2 BarrierStampFrame
  -- ^ EVERY, the barrier: a completing member's timestamp, forced, so the
  -- last completion (@t_last@, spec §3.4) can be picked out.
  | Barrier2b BarrierDueFrame
  -- ^ EVERY, the barrier: a completing member's absolute act deadline,
  -- forced, so the LATEST of them — the instant by which all performance
  -- fell due — can be kept for @OF THE DEADLINE@ in the @HENCE@ (R-Q7B).
  | BarrierEmpty BarrierEmptyFrame
  -- ^ EVERY, the barrier over an EMPTY cast: the arming time, forced, which
  -- is when "all zero of them" have acted, so the join fires there — through
  -- the @ONCE@ line's @WITHIN@ when it has one, like any other join.
  | Barrier3 BarrierStateDueFrame
  -- ^ EVERY, the barrier: the @WITHIN@ on the @ONCE@ line (R-T2), evaluated
  -- after every member has completed, to bound the whole (spec §2.2.7.5 pt 3).
  | Barrier4 BarrierArmingFrame
  -- ^ EVERY, the barrier: the arming time, forced, to compare against the
  -- state deadline computed by 'Barrier3'.
  | BarrierTrim BarrierTrimFrame
  -- ^ EVERY, the barrier, the state layer's @LEST@: one cons cell of the
  -- barrier's stream, forced, on the walk to the first event stamped after
  -- the @ONCE@ line's deadline ('L4.EvaluateLazy.Machine.barrierStateMissed',
  -- spec §5.2 / R-Q5's state layer, built 2026-09-16). @ValNil@ ends the walk
  -- with the empty stream; @ValCons@ goes on to the event.
  | BarrierTrimEvent BarrierTrimCellFrame
  -- ^ EVERY, the barrier, the same walk: the cell's event, forced, so its
  -- stamp can be read.
  | BarrierTrimStamp BarrierTrimCellFrame
  -- ^ EVERY, the barrier, the same walk: the event's stamp, forced. Past the
  -- deadline, the @LEST@ is applied to the stream from THIS cell on; not
  -- yet, the walk moves to the next cell.
  | Barrier5 BarrierFailStampFrame
  -- ^ EVERY, the barrier: a FAILING member's anchor, forced, so the earliest
  -- failure can be picked out once every member has run (R-T3, spec §6.1).
  | Barrier5c BarrierFailPosFrame
  -- ^ EVERY, the barrier: the same failing member's stream position — how
  -- far into the stream the event that revealed (or, for @SHANT@, WAS) the
  -- failure stands — forced, so that two failures at the same stamp are
  -- ordered by the stream before anything else: two @SHANT@ members violated
  -- by two events at one stamp are two failures with two residuals, and the
  -- @LEST@ must be handed the residual of the one the stream reached first
  -- (spec §11.0.1 "Stacking B on C", round 1).
  | Barrier5b BarrierFailDueFrame
  -- ^ EVERY, the barrier: the same failing member's absolute deadline,
  -- forced, so that two failures the same event revealed can be ordered by
  -- the deadline missed — which is what @OF THE DEADLINE@ in the @LEST@
  -- names, so the tie must not fall to roll order (R-Q7B on R-T3, spec
  -- §11.0.1 "Stacking B on C").
  | BreachBy BreachByFrame
  -- ^ @BREACH BY e@: the party expression, forced. A LIST is walked one cons
  -- cell per step (R-T3: @BY@ takes a party or a list of parties), one
  -- declared failure per element, duplicates kept; anything else is the one
  -- party.
  | ResolveParty ResolvePartyFrame
  -- ^ STATE-AS-LEDGER: on the deadline-passed / LEST path the obligation party is
  --   still an unevaluated expression; this frame forces it to a WHNF (via
  --   'maybeEvaluate') so it can be keyed and the followup (e.g. a RECORD in a
  --   breach reparation) attributed to the real acting party, not the anonymous
  --   ledger. Mirrors how 'Contract6 PartyWHNF' forces the party on the match path.
  | Handoff Lifecycle
  -- ^ R-Q7B: the value a @HENCE@ or @LEST@ evaluated to, about to be applied
  -- to @[time, events]@. Rebinds the hand-off's 'Lifecycle' into that value's
  -- own environment ('L4.EvaluateLazy.Machine.rebindLifecycle'), so that an
  -- anchored @WITHIN@ inside it names the obligation the continuation is
  -- ATTACHED to when it runs — also when the continuation arrived as a value
  -- (a @GIVEN k IS A DEONTIC …@ parameter, a @WHERE@ local) whose closure
  -- captured some other obligation's bindings, or none. Pushed at every
  -- hand-off, and again before each operand of a compound is evaluated
  -- ('L4.EvaluateLazy.Machine.operandHandoff'), because a compound's value
  -- holds its operands as expressions and a value one of them evaluates to
  -- is not reached by rebinding the compound.
  deriving stock Show

-- | The window's opening edge as the act frames carry it (EVERY-EACH-QUANTIFIER-SPEC
-- §5.1.2, R-X5, built 2026-09-16): the source @AFTER …@ before the first
-- event ('Left'; 'Nothing' when the act has none), and after it the time
-- still to run until the window opens, relative to the frame's @time@ —
-- @Right (Just n)@ while the window has not opened, @Right Nothing@ once it
-- has. Mirrors the fourth field of 'L4.Evaluate.ValueLazy.ValObligation',
-- which is what a residual is rebuilt from. An act met while this is
-- @Right (Just _)@ is EARLY: a nullity, reported (R-X6, @Contract10@).
type MaybeOpened = Either (Maybe (Opening Resolved)) (Maybe WHNF)

data ScrutinizeEvents = ScrutinizeEvents
  { party :: MaybeEvaluated, act :: RAction Resolved, opens :: MaybeOpened, due :: MaybeEvaluated' (Maybe (Deadline Resolved)), followup :: RExpr, lest :: Maybe RExpr
  , time :: Reference
  , env :: Environment
  , norm :: NormKey  -- ^ the step log's key for this obligation (P2b); lazy, and never forced when the log is off
  , seen :: Int
    -- ^ how many events this scan has taken from its stream: the position
    -- of the event under scrutiny, counted from the stream the obligation
    -- was armed on (R-T3 on R-Q7B, spec §11.0.1 "Stacking B on C" round 1)
  , armed :: Reference
    -- ^ when this obligation was entered: what @THE ARMING@ names in its continuation (R-Q7B)
  }
  deriving stock Show

-- | The mark on an EVENT copy that an expiring obligation has re-offered to
-- its HENCE/LEST continuation. The @ev'reoffered@ field threaded through
-- 'ScrutinizeEvent', 'CurrentTimeWHNF', 'ScrutinizeDue', 'ScrutinizeAnchor'
-- and 'CheckTiming' carries it (looked up at Contract1 via @isReoffered@;
-- 'Nothing' for a fresh event). A re-offered copy is ALWAYS handed on to
-- the next layer — the event must reach the first layer whose window it is
-- not past — and the mark exists only to report, loudly, a chain of layers
-- whose deadlines have stopped advancing: 'stalled' counts the hand-offs
-- in a row at which the deadline the copy revealed the expiry of did not
-- pass 'highWater', and Contract5 refuses past @maximumStalledReoffers@
-- instead of walking such a chain forever. See the Contract5 NOTE in
-- Machine.hs.
--
-- It is carried on past 'CheckTiming' too (through 'PartyWHNF' to
-- 'ActionDoesn'tmatch'), for one reader only: the deontic step log (P2b),
-- which reports a re-offered copy's look as 'Reoffered' whatever the mark
-- says. The machine itself consults it at Contract5 alone.
data Reoffered = MkReoffered
  { highWater :: !Rational
    -- ^ the latest absolute deadline whose expiry this event has revealed
    -- on its walk down the chain of continuations
  , stalled :: !Int
    -- ^ how many hand-offs in a row the deadline has failed to pass
    -- 'highWater' (0 after every hand-off that advanced it)
  }
  deriving stock Show

data ScrutinizeEvent = ScrutinizeEvent
  { party :: MaybeEvaluated, act :: RAction Resolved, opens :: MaybeOpened, due :: MaybeEvaluated' (Maybe (Deadline Resolved)), followup :: RExpr, lest :: Maybe RExpr
  , events :: Reference, time :: Reference, ev'reoffered :: Maybe Reoffered
  , env :: Environment
  , norm :: NormKey  -- ^ the step log's key for this obligation (P2b); lazy, and never forced when the log is off
  , seen :: Int
    -- ^ how many events this scan has taken from its stream: the position
    -- of the event under scrutiny, counted from the stream the obligation
    -- was armed on (R-T3 on R-Q7B, spec §11.0.1 "Stacking B on C" round 1)
  , armed :: Reference
    -- ^ when this obligation was entered: what @THE ARMING@ names in its continuation (R-Q7B)
  }
  deriving stock Show

data CurrentTimeWHNF = CurrentTimeWHNF
  { party :: MaybeEvaluated, act :: RAction Resolved, opens :: MaybeOpened, due :: MaybeEvaluated' (Maybe (Deadline Resolved)), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference, ev'time :: Reference
  , events :: Reference, time :: Reference, ev'reoffered :: Maybe Reoffered
  , env :: Environment
  , norm :: NormKey  -- ^ the step log's key for this obligation (P2b); lazy, and never forced when the log is off
  , seen :: Int
    -- ^ how many events this scan has taken from its stream: the position
    -- of the event under scrutiny, counted from the stream the obligation
    -- was armed on (R-T3 on R-Q7B, spec §11.0.1 "Stacking B on C" round 1)
  , armed :: Reference
    -- ^ when this obligation was entered: what @THE ARMING@ names in its continuation (R-Q7B)
  }
  deriving stock Show

data ScrutinizeDue = ScrutinizeDue
  { party :: MaybeEvaluated, act :: RAction Resolved, opens :: MaybeOpened, due :: MaybeEvaluated' (Maybe (Deadline Resolved)), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference, ev'time :: WHNF
  , events :: Reference, time :: Reference, ev'reoffered :: Maybe Reoffered
  , env :: Environment
  , norm :: NormKey  -- ^ the step log's key for this obligation (P2b); lazy, and never forced when the log is off
  , seen :: Int
    -- ^ how many events this scan has taken from its stream: the position
    -- of the event under scrutiny, counted from the stream the obligation
    -- was armed on (R-T3 on R-Q7B, spec §11.0.1 "Stacking B on C" round 1)
  , armed :: Reference
    -- ^ when this obligation was entered: what @THE ARMING@ names in its continuation (R-Q7B)
  }
  deriving stock Show

-- | The anchor of an anchored deadline has been forced ('Contract4b' is what
-- receives it); the duration is still to evaluate.
data ScrutinizeAnchor = ScrutinizeAnchor
  { party :: MaybeEvaluated, act :: RAction Resolved, opens :: MaybeOpened, due :: MaybeEvaluated' (Maybe (Deadline Resolved)), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference, ev'time :: WHNF
  , events :: Reference, time :: WHNF, ev'reoffered :: Maybe Reoffered
  , env :: Environment
  , seen :: Int
    -- ^ how many events this scan has taken from its stream: the position
    -- of the event under scrutiny, counted from the stream the obligation
    -- was armed on (R-T3 on R-Q7B, spec §11.0.1 "Stacking B on C" round 1)
  , armed :: Reference
  , duration :: RExpr        -- ^ the @d@ of @WITHIN d OF …@, evaluated once the anchor is known
  , norm :: NormKey  -- ^ the step log's key for this obligation (P2b); lazy, and never forced when the log is off
  , openT :: Maybe Rational  -- ^ the instant the window opens, when the act has an @AFTER@ (see 'CheckTiming')
  }
  deriving stock Show

-- | The opening edge is anchored (@AFTER d OF …@) and its anchor has been
-- forced ('Contract4oa' receives it); the offset is still to evaluate.
data ScrutinizeOpeningAnchor = ScrutinizeOpeningAnchor
  { party :: MaybeEvaluated, act :: RAction Resolved, opens :: MaybeOpened, due :: MaybeEvaluated' (Maybe (Deadline Resolved)), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference, ev'time :: WHNF
  , events :: Reference, time :: WHNF, ev'reoffered :: Maybe Reoffered
  , env :: Environment
  , norm :: NormKey  -- ^ the step log's key for this obligation (P2b); lazy, and never forced when the log is off
  , seen :: Int
    -- ^ how many events this scan has taken from its stream: the position
    -- of the event under scrutiny, counted from the stream the obligation
    -- was armed on (R-T3 on R-Q7B, spec §11.0.1 "Stacking B on C" round 1)
  , armed :: Reference
  , offset :: RExpr          -- ^ the @d@ of @AFTER d OF …@, evaluated once the anchor is known
  }
  deriving stock Show

-- | The opening edge's offset has been forced ('Contract4o' receives it).
data ScrutinizeOpening = ScrutinizeOpening
  { party :: MaybeEvaluated, act :: RAction Resolved, opens :: MaybeOpened, due :: MaybeEvaluated' (Maybe (Deadline Resolved)), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference, ev'time :: WHNF
  , events :: Reference, time :: WHNF, ev'reoffered :: Maybe Reoffered
  , env :: Environment
  , norm :: NormKey  -- ^ the step log's key for this obligation (P2b); lazy, and never forced when the log is off
  , seen :: Int
    -- ^ how many events this scan has taken from its stream: the position
    -- of the event under scrutiny, counted from the stream the obligation
    -- was armed on (R-T3 on R-Q7B, spec §11.0.1 "Stacking B on C" round 1)
  , armed :: Reference
  , openAnchorT :: Maybe Rational
    -- ^ the opening's anchor on the trace's clock, when the @AFTER@ names
    -- one (@AFTER d OF …@); the window then opens at @openAnchorT + d@
    -- rather than at @time + d@
  }
  deriving stock Show

data CheckTiming = CheckTiming
  { party :: MaybeEvaluated, act :: RAction Resolved, opens :: MaybeOpened, due :: MaybeEvaluated' (Maybe (Deadline Resolved)), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference, ev'time :: WHNF
  , events :: Reference, time :: WHNF, ev'reoffered :: Maybe Reoffered
  , env :: Environment
  , norm :: NormKey  -- ^ the step log's key for this obligation (P2b); lazy, and never forced when the log is off
  , seen :: Int
    -- ^ how many events this scan has taken from its stream: the position
    -- of the event under scrutiny, counted from the stream the obligation
    -- was armed on (R-T3 on R-Q7B, spec §11.0.1 "Stacking B on C" round 1)
  , armed :: Reference
    -- ^ when this obligation was entered: what @THE ARMING@ names in its continuation (R-Q7B)
  , origin :: Maybe Rational
    -- ^ what a DURATION in the closing edge is added to, when it is not
    -- the frame's own clock: the anchor's instant for @WITHIN d OF …@
    -- (R-Q7: the deadline is then @anchor + d@, absolute), or the instant
    -- the window OPENS for a bare @WITHIN d@ beside an @AFTER@ (R-X5 as
    -- amended 2026-09-16, §5.1.2.2: bare @AFTER d1 WITHIN d2@ re-anchors,
    -- the deadline is @open + d2@). @Nothing@ for an unanchored @WITHIN@
    -- with no @AFTER@, for an already-evaluated remaining due, and for a
    -- @BEFORE@ (whose value is a DATE, absolute by itself). Set once, at
    -- the first event, when @time@ is still the arming time; after this
    -- frame the remaining due is relative again ('Right (ValNumber newDue)')
    -- and the anchor is spent.
  , openT :: Maybe Rational
    -- ^ the instant the window opens, absolute, when the act has an
    -- @AFTER@ and the window has not yet opened; what the residual's
    -- opening edge is re-relativised from after this frame, and what the
    -- explicitly anchored empty window is diagnosed against
  }
  deriving stock Show

data PartyWHNF = PartyWHNF
  { act :: RAction Resolved, opens :: MaybeOpened, due :: MaybeEvaluated' (Maybe (Deadline Resolved)), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference
  , events :: Reference, time :: WHNF, ev'reoffered :: Maybe Reoffered
  , env :: Environment
  , norm :: NormKey  -- ^ the step log's key for this obligation (P2b); lazy, and never forced when the log is off
  , seen :: Int
    -- ^ how many events this scan has taken from its stream: the position
    -- of the event under scrutiny, counted from the stream the obligation
    -- was armed on (R-T3 on R-Q7B, spec §11.0.1 "Stacking B on C" round 1)
  , armed :: Reference
    -- ^ when this obligation was entered: what @THE ARMING@ names in its continuation (R-Q7B)
  }
  deriving stock Show

data PartyEqual = PartyEqual
  { party :: WHNF, act :: RAction Resolved, opens :: MaybeOpened, due :: MaybeEvaluated' (Maybe (Deadline Resolved)), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference
  , events :: Reference, time :: WHNF, ev'reoffered :: Maybe Reoffered
  , env :: Environment
  , norm :: NormKey  -- ^ the step log's key for this obligation (P2b); lazy, and never forced when the log is off
  , seen :: Int
    -- ^ how many events this scan has taken from its stream: the position
    -- of the event under scrutiny, counted from the stream the obligation
    -- was armed on (R-T3 on R-Q7B, spec §11.0.1 "Stacking B on C" round 1)
  , armed :: Reference
    -- ^ when this obligation was entered: what @THE ARMING@ names in its continuation (R-Q7B)
  }
  deriving stock Show

data ScrutinizeParty = ScrutinizeParty
  { party :: WHNF, act :: RAction Resolved, opens :: MaybeOpened, due :: MaybeEvaluated' (Maybe (Deadline Resolved)), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: WHNF, ev'act :: Reference
  , events :: Reference, time :: WHNF, ev'reoffered :: Maybe Reoffered
  , env :: Environment
  , norm :: NormKey  -- ^ the step log's key for this obligation (P2b); lazy, and never forced when the log is off
  , seen :: Int
    -- ^ how many events this scan has taken from its stream: the position
    -- of the event under scrutiny, counted from the stream the obligation
    -- was armed on (R-T3 on R-Q7B, spec §11.0.1 "Stacking B on C" round 1)
  , armed :: Reference
    -- ^ when this obligation was entered: what @THE ARMING@ names in its continuation (R-Q7B)
  }
  deriving stock Show

data ScrutinizeEnvironment = ScrutinizeEnvironment
  { party :: WHNF, act :: RAction Resolved, opens :: MaybeOpened, due :: MaybeEvaluated' (Maybe (Deadline Resolved)), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: WHNF, ev'act :: Reference
  , events :: Reference, time :: WHNF, ev'reoffered :: Maybe Reoffered
  , env :: Environment
  , norm :: NormKey  -- ^ the step log's key for this obligation (P2b); lazy, and never forced when the log is off
  , seen :: Int
    -- ^ how many events this scan has taken from its stream: the position
    -- of the event under scrutiny, counted from the stream the obligation
    -- was armed on (R-T3 on R-Q7B, spec §11.0.1 "Stacking B on C" round 1)
  , armed :: Reference
    -- ^ when this obligation was entered: what @THE ARMING@ names in its continuation (R-Q7B)
  }
  deriving stock Show

data ScrutinizeActions = ScrutinizeActions
  { party :: WHNF, act :: RAction Resolved, opens :: MaybeOpened, due :: MaybeEvaluated' (Maybe (Deadline Resolved)), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: WHNF, ev'act :: Reference
  , events :: Reference, time :: WHNF, ev'reoffered :: Maybe Reoffered
  , env :: Environment, henceEnv :: Environment -- ^ the environment to extend by when evaluating the hence clause
  , norm :: NormKey  -- ^ the step log's key for this obligation (P2b); lazy, and never forced when the log is off
  , seen :: Int
    -- ^ how many events this scan has taken from its stream: the position
    -- of the event under scrutiny, counted from the stream the obligation
    -- was armed on (R-T3 on R-Q7B, spec §11.0.1 "Stacking B on C" round 1)
  , armed :: Reference
  }
  deriving stock Show

data ActionDoesn'tmatch = ActionDoesn'tmatch
  { party :: WHNF, act :: RAction Resolved, opens :: MaybeOpened, due :: MaybeEvaluated' (Maybe (Deadline Resolved)), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: WHNF, ev'act :: Reference
  , events :: Reference, time :: WHNF, ev'reoffered :: Maybe Reoffered
  , env :: Environment
  , norm :: NormKey  -- ^ the step log's key for this obligation (P2b); lazy, and never forced when the log is off
  , seen :: Int
    -- ^ how many events this scan has taken from its stream: the position
    -- of the event under scrutiny, counted from the stream the obligation
    -- was armed on (R-T3 on R-Q7B, spec §11.0.1 "Stacking B on C" round 1)
  , armed :: Reference
    -- ^ when this obligation was entered: what @THE ARMING@ names in its continuation (R-Q7B)
  }
  deriving stock Show

data RBinOp1 = MkRBinOp1
  { op :: RBinOp
  , rexpr2 :: MaybeEvaluated
  , args :: [Reference] -- ^ the arguments to the remaining contract expr
  , env :: Environment
  }
  deriving stock Show

data RBinOp2 = MkRBinOp2
  { op :: RBinOp
  , rval1 :: WHNF
  , env :: Environment
  }
  deriving stock Show

-- | What the roll call and the barrier both carry from step to step: the
-- quantified obligation itself, its four destructured pieces (the bound
-- variable, the optional cast constructor, the optional @IN@ roll, the
-- optional @WHO@ filter), the environment the obligation was armed in, and
-- the two arguments every contract is applied to.
data QuantCtx = MkQuantCtx
  { deonton :: Deonton Resolved
  , var     :: Resolved            -- ^ the member variable, bound per member
  , cast    :: Maybe Resolved      -- ^ @EVERY Tenant t@: the constructor, if given
  , roll    :: Maybe RExpr         -- ^ @IN tenants@: the roll, if written outright
  , filt    :: Maybe RExpr         -- ^ the @WHO@ expression, if given
  , env     :: Environment         -- ^ the arming environment
  , time    :: Reference           -- ^ the arming time
  , events  :: Reference           -- ^ the whole event stream
  , norm    :: NormKey
    -- ^ P2b: the JOIN's own key, carried by the barrier's 'JoinReleased' /
    -- 'JoinExpired' / 'JoinFailed' steps; lazy, never forced when the log is off
  }
  deriving stock Show

-- | One member of the cast: the cell it lives in (so the member variable can
-- be bound to it, which is what @Sign (EXACTLY t)@ resolves against) and its
-- forced value (so the obligation's party needs no second evaluation).
type CastMember = (Reference, WHNF)

data QuantRollFrame = QuantRollFrame
  { ctx :: QuantCtx
  , acc :: [CastMember]            -- ^ members accepted so far, most recent first
  }
  deriving stock Show

data QuantCastFrame = QuantCastFrame
  { ctx       :: QuantCtx
  , acc       :: [CastMember]
  , candidate :: Reference         -- ^ the roll entry under scrutiny
  , rest      :: Reference         -- ^ the remaining roll
  }
  deriving stock Show

data QuantFilterFrame = QuantFilterFrame
  { ctx        :: QuantCtx
  , acc        :: [CastMember]
  , candidate  :: Reference
  , candidateV :: WHNF             -- ^ …forced, so the party needs no re-evaluation
  , rest       :: Reference
  }
  deriving stock Show

-- | The barrier's state. Members are run one at a time over the SAME event
-- stream (CSP interleaving: each member's obligation scans the whole stream
-- independently). Each member's result is unambiguous: the 'checkpoint'
-- sentinel (it completed), the 'failpoint' sentinel (it definitively did
-- not), or a residual 'ValObligation' (still waiting). That is why the
-- barrier's own @LEST@ is never handed to a member as an expression — a
-- pending reparation and a pending member would both be a 'ValObligation'.
data BarrierStepFrame = BarrierStepFrame
  { ctx     :: QuantCtx
  , checkpoint :: Resolved
    -- ^ the sentinel constructor each member's HENCE reduces to. Applying it
    -- to the @[time, events]@ every continuation receives yields a
    -- @ValConstructor checkpoint [time, events]@, which is how a member
    -- reports BOTH that it completed and when — a plain 'ValFulfilled' would
    -- have lost the timestamp the join needs (§3.4's @t_last@).
  , failpoint :: Maybe Resolved
    -- ^ the twin sentinel, standing in for the BARRIER's @LEST@ in each
    -- member's own @LEST@ slot, and present only when the barrier has one.
    -- Its job is to make a member's failure carry the anchor and the residual
    -- stream the machine computed for it, so the barrier can run its @LEST@
    -- ONCE, with those, instead of re-running the member to get them. Without
    -- it a member had to be applied to the stream twice, which repeated every
    -- side effect of the first application and could even change the verdict
    -- when a deadline expression wrote to the ledger.
  , current :: WHNF                -- ^ the member obligation just applied
  , queue   :: [WHNF]              -- ^ members not yet run
  , tLast   :: Maybe (Rational, Reference)
    -- ^ the latest completion so far and the event stream that followed it:
    -- the anchor and residual the @HENCE@ is handed (spec §3.4, §5.1).
    --
    -- The TIE is decided by roll order — the first member to reach a given
    -- stamp keeps its stream. That is deterministic but not exact: when two
    -- members complete at the same instant, the stream kept may still contain
    -- the other's completing event, so an act stamped at the join can reach
    -- the continuation. Getting it exactly right means trimming the stream to
    -- events strictly after the join, which needs frames of its own; the
    -- limit is written into spec §11.0.1 and onto the doc page. The tie
    -- decides the STREAM only: the deadline the @HENCE@ may anchor to is
    -- 'dueLatest', which no ordering can change.
  , dueLatest :: Maybe Rational
    -- ^ the latest of the completed members' absolute act deadlines so far —
    -- the instant by which all performance fell due, and what @OF THE
    -- DEADLINE@ in the @HENCE@ names when the @ONCE@ line has no @WITHIN@
    -- of its own (R-Q7B). A maximum, so the roll's order cannot move it;
    -- absent while no completed member had a deadline (the members either
    -- all have one or none does, since they share one act @WITHIN@).
  , pending :: [WHNF]              -- ^ members still awaiting an event, reversed
  , failures :: [BarrierFailure]
    -- ^ members that definitively did not complete, reversed (so roll order
    -- once reversed back). EVERY member runs before the barrier decides —
    -- the first failure does not end the scan — so that the verdict can name
    -- all of them (R-T3, spec §6.1) and the @LEST@ can be anchored at the
    -- EARLIEST failure rather than the first in roll order.
  , lapsed :: Bool
    -- ^ some @MAY@ member's permission expired under a barrier with no
    -- @LEST@: nothing was owed, so nothing is breached, but the join cannot
    -- fire — the verdict is @FULFILLED@, as it was when this ended the scan.
  }
  deriving stock Show

-- | One member's definitive failure, as the barrier records it.
data BarrierFailure
  = BarrierFailedAt
      { failAt      :: Rational    -- ^ the anchor the machine computed for the miss, forced
      , failPos     :: Int
        -- ^ the stream position of the event that revealed the miss (for
        -- @SHANT@, the violating event itself), forced ('Barrier5c'): the
        -- first tie-break when two failures share a 'failAt' — the earlier
        -- in the stream wins, and only the same event ties
      , failDue     :: Maybe Rational
        -- ^ the member's absolute act deadline, forced ('Barrier5b'): the
        -- tie-break when two failures share a 'failAt' AND a 'failPos'
      , failTimeRef :: Reference   -- ^ …and as the reference the @LEST@ is handed
      , failEvsRef  :: Reference   -- ^ the residual stream that followed the miss
      , failDueRef  :: Maybe Reference
        -- ^ the member's absolute act deadline, when it had one (the
        -- sentinel's fourth argument): what @OF THE DEADLINE@ in the @LEST@
        -- names when THIS member's failure is the one the @LEST@ is
        -- anchored at (R-Q7B).
      }
    -- ^ reported through the failpoint sentinel — a barrier WITH a @LEST@.
    -- 'failAt' is the sentinel's anchor forced, and 'failTimeRef' the same
    -- value as the reference the @LEST@ is handed, so the ordering key IS the
    -- anchor — and the anchor is R-Q5's failure time (spec §5.2, built
    -- 2026-09-16): the member's missed deadline for @MUST@\/@DO@\/@MAY@
    -- (so 'failAt' equals 'failDue' there, and 'failTimeRef' and
    -- 'failDueRef' are one reference), its violating event's stamp for
    -- @SHANT@. For @MUST@\/@DO@\/@MAY@ a tie is two members with one
    -- deadline, which the same event reveals; for @SHANT@ the stamp is the
    -- violating event's own, and two members violated at one stamp by two
    -- events are two failures with two residuals. So a tie on 'failAt' is
    -- broken first by 'failPos' — the stream position, which only the same
    -- event ties — then by 'failDue' (a key that mattered while the anchor
    -- was the revealing stamp and one event could reveal two deadlines;
    -- redundant now, kept whole), and only then by roll order, which by then
    -- names the same anchor, residual and deadline either way (see
    -- 'barrierFinish', 'earliestFailure').
  | BarrierBreached
      { failReason :: ReasonForBreach Reference }
    -- ^ the member's own breach — a barrier WITHOUT a @LEST@ mints no
    -- sentinel, so a missed @MUST@ comes back as the 'ValBreached' the
    -- single-party path builds, naming the member.
  deriving stock Show

data BarrierStampFrame = BarrierStampFrame
  { step   :: BarrierStepFrame
  , evsRef :: Reference            -- ^ the stream after the completing event
  , dueRef :: Maybe Reference      -- ^ the completing member's absolute deadline, if it had one
  }
  deriving stock Show

data BarrierFailStampFrame = BarrierFailStampFrame
  { step    :: BarrierStepFrame
  , timeRef :: Reference           -- ^ the failure's anchor, being forced
  , evsRef  :: Reference           -- ^ the stream the failing member handed back
  , posRef  :: Reference           -- ^ the failure's stream position, forced next ('Barrier5c')
  , dueRef  :: Maybe Reference     -- ^ the failing member's absolute deadline, if it had one
  }
  deriving stock Show

-- | The failing member's stream position is being forced ('Barrier5c'), its
-- anchor already known.
data BarrierFailPosFrame = BarrierFailPosFrame
  { step    :: BarrierStepFrame
  , failAt  :: Rational            -- ^ the failure's anchor, forced by 'Barrier5'
  , timeRef :: Reference           -- ^ …and as a reference
  , evsRef  :: Reference           -- ^ the stream the failing member handed back
  , dueRef  :: Maybe Reference     -- ^ the failing member's absolute deadline, if it had one
  }
  deriving stock Show

-- | The failing member's absolute deadline is being forced ('Barrier5b'),
-- its anchor and stream position already known.
data BarrierFailDueFrame = BarrierFailDueFrame
  { step    :: BarrierStepFrame
  , failAt  :: Rational            -- ^ the failure's anchor, forced by 'Barrier5'
  , failPos :: Int                 -- ^ the failure's stream position, forced by 'Barrier5c'
  , timeRef :: Reference           -- ^ …and as a reference
  , evsRef  :: Reference           -- ^ the stream the failing member handed back
  , dueRef  :: Reference           -- ^ the deadline, being forced
  }
  deriving stock Show

-- | @BREACH BY e@, with @e@ under evaluation.
data BreachByFrame = BreachByFrame
  { partyRef :: Reference          -- ^ the whole @BY@ expression, allocated (forced on return)
  , acc      :: [Reference]        -- ^ list elements collected so far, reversed
  , mReason  :: Maybe Reference    -- ^ the @BECAUSE@, allocated
  , clause   :: Text               -- ^ where the @BREACH@ was written, for the empty-list error
  }
  deriving stock Show

-- | The completing member's absolute deadline is being forced ('Barrier2b').
newtype BarrierDueFrame = BarrierDueFrame
  { step :: BarrierStepFrame }
  deriving stock Show

-- | The barrier's cast was empty; its arming time is being forced
-- ('BarrierEmpty'), which is when its join fires.
newtype BarrierEmptyFrame = BarrierEmptyFrame
  { ctx :: QuantCtx }
  deriving stock Show

data BarrierStateDueFrame = BarrierStateDueFrame
  { ctx        :: QuantCtx
  , joinTime   :: Rational      -- ^ when the last member completed (the arming, for an empty cast)
  , joinEvents :: Reference     -- ^ the stream that followed it
  }
  deriving stock Show

data BarrierArmingFrame = BarrierArmingFrame
  { ctx        :: QuantCtx
  , joinTime   :: Rational
  , joinEvents :: Reference
  , stateDue   :: Rational      -- ^ the ONCE line's WITHIN, evaluated
  }
  deriving stock Show

-- | The walk that trims the barrier's stream to the events after its state
-- deadline, before the state-layer @LEST@ is applied ('BarrierTrim').
data BarrierTrimFrame = BarrierTrimFrame
  { ctx       :: QuantCtx
  , lestExpr  :: RExpr          -- ^ the barrier's @LEST@, run once the walk ends
  , cutoff    :: Rational       -- ^ the state deadline: events stamped at or before it are dropped
  , cutoffRef :: Reference      -- ^ …and as the reference the @LEST@ is anchored at
  , cell      :: Reference      -- ^ the cons cell under scrutiny (handed on whole when it is the first past the deadline)
  }
  deriving stock Show

-- | The same walk, one cell opened: its event and then its stamp are being
-- forced ('BarrierTrimEvent', 'BarrierTrimStamp').
data BarrierTrimCellFrame = BarrierTrimCellFrame
  { ctx       :: QuantCtx
  , lestExpr  :: RExpr
  , cutoff    :: Rational
  , cutoffRef :: Reference
  , cell      :: Reference      -- ^ the cell whose event is under scrutiny
  , rest      :: Reference      -- ^ the cells after it
  }
  deriving stock Show

data ResolvePartyFrame = ResolvePartyFrame
  { followup :: RExpr        -- ^ the HENCE / LEST followup to run once the party is keyed
  , env :: Environment       -- ^ environment in which to run the followup
  , events :: Reference      -- ^ remaining event stream (passed on to 'continueWithFollowup')
  , time :: Reference
    -- ^ the continuation's clock, already allocated: under @LEST@ the missed
    -- deadline (spec §5.2, the same reference as 'lifecycle''s @deadline@),
    -- under @HENCE@ the revealing event's stamp
  , pending :: Maybe DeonticStep
    -- ^ P2b: the 'Expired' step this expiry owes the log, logged HERE rather
    -- than at @Contract5@ because this frame is where the party gets forced,
    -- and the step wants the bearer's key. 'Nothing' when the log is off.
  , seen :: Int              -- ^ the stream position of the revealing event (see 'ScrutinizeEvents')
  , lifecycle :: Lifecycle   -- ^ what the followup may anchor to (R-Q7B)
  }
  deriving stock Show

-- | The positions in the life of an obligation that its continuation may
-- anchor a @WITHIN@ to (EVERY-EACH-QUANTIFIER-SPEC §5.1.1, R-Q7B: @OF THE
-- JOIN@, @OF THE DEADLINE@, @OF THE ARMING@). Built by the obligation at the
-- moment it hands off to its @HENCE@ or @LEST@, and bound into the
-- continuation's environment under machine-minted names no program can
-- spell ('L4.EvaluateLazy.Machine.bindLifecycle'): every hand-off REPLACES
-- all three bindings — a position this hand-off does not have is deleted,
-- never inherited from an outer obligation — and the value the continuation
-- evaluated to is rebound the same way before it is applied ('Handoff'), so
-- the obligation an anchor names is the one whose hand-off this is: the
-- NEAREST enclosing one, dynamically, which for a continuation written
-- inline is also the one the type checker assumes.
data Lifecycle = MkLifecycle
  { join     :: Maybe Reference
    -- ^ the instant the join fired — the hand-off clock under @HENCE@. Absent
    -- under @LEST@: the join did not fire (the checker refuses @THE JOIN@
    -- there).
  , deadline :: Maybe Reference
    -- ^ the obligation's ABSOLUTE deadline, when it had one to hand off.
    -- Under @LEST@ it is also the continuation's clock for a missed
    -- @MUST@\/@DO@\/@MAY@ and for the state layer (spec §5.2, 2026-09-16):
    -- the hand-off passes this very reference as the @time@ the
    -- continuation is applied to, so @WITHIN d@ and @WITHIN d OF THE
    -- DEADLINE@ agree there by construction. Under a @SHANT@'s @LEST@ the
    -- clock is the violating stamp and this is the window's end; under
    -- @HENCE@ the clock is 'join'.
    --
    --   * a @PARTY@ obligation's act @WITHIN@;
    --   * a barrier's @HENCE@: the @ONCE@ line's @WITHIN@ when written (the
    --     deadline on the whole, R-T2), otherwise the latest of the members'
    --     act deadlines — the instant by which all performance fell due —
    --     and absent for an empty cast with no @ONCE@-line @WITHIN@;
    --   * a barrier's @LEST@: the deadline that was actually missed — the
    --     act deadline of the member whose failure the @LEST@ is anchored
    --     at, i.e. the EARLIEST failure (R-T3's choice; several members may
    --     have failed, and the deadline follows the anchor:
    --     'L4.EvaluateLazy.Machine.barrierFinish', 'barrierFail'), the
    --     @ONCE@ line's when everyone acted but the last act landed after
    --     it ('L4.EvaluateLazy.Machine.barrierStateMissed');
    --   * under a fork, the member's own.
  , armed    :: Reference
    -- ^ when the obligation was entered.
  }
  deriving stock Show
