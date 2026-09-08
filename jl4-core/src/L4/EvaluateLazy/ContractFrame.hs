module L4.EvaluateLazy.ContractFrame where

import L4.Evaluate.ValueLazy
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
  | Barrier3 BarrierStateDueFrame
  -- ^ EVERY, the barrier: the @WITHIN@ on the @ONCE@ line (R-T2), evaluated
  -- after every member has completed, to bound the whole (spec §2.2.7.5 pt 3).
  | Barrier4 BarrierArmingFrame
  -- ^ EVERY, the barrier: the arming time, forced, to compare against the
  -- state deadline computed by 'Barrier3'.
  | ResolveParty ResolvePartyFrame
  -- ^ STATE-AS-LEDGER: on the deadline-passed / LEST path the obligation party is
  --   still an unevaluated expression; this frame forces it to a WHNF (via
  --   'maybeEvaluate') so it can be keyed and the followup (e.g. a RECORD in a
  --   breach reparation) attributed to the real acting party, not the anonymous
  --   ledger. Mirrors how 'Contract6 PartyWHNF' forces the party on the match path.
  deriving stock Show

data ScrutinizeEvents = ScrutinizeEvents
  { party :: MaybeEvaluated, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , time :: Reference
  , env :: Environment
  }
  deriving stock Show

-- | The @ev'reoffered@ field threaded through 'ScrutinizeEvent',
-- 'CurrentTimeWHNF', 'ScrutinizeDue' and 'CheckTiming' records whether the
-- event under scrutiny was itself re-offered by an expiring obligation
-- (looked up at Contract1 via @isReoffered@). It enforces the at-most-once
-- re-offer rule at the Contract5 expiry step: a re-offered event that
-- reveals a second expiry is consumed instead of being re-offered again,
-- which keeps evaluation terminating for recursive HENCE/LEST continuations
-- with non-positive deadlines. See the Contract5 NOTE in Machine.hs.
data ScrutinizeEvent = ScrutinizeEvent
  { party :: MaybeEvaluated, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , events :: Reference, time :: Reference, ev'reoffered :: Bool
  , env :: Environment
  }
  deriving stock Show

data CurrentTimeWHNF = CurrentTimeWHNF
  { party :: MaybeEvaluated, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference, ev'time :: Reference
  , events :: Reference, time :: Reference, ev'reoffered :: Bool
  , env :: Environment
  }
  deriving stock Show

data ScrutinizeDue = ScrutinizeDue
  { party :: MaybeEvaluated, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference, ev'time :: WHNF
  , events :: Reference, time :: Reference, ev'reoffered :: Bool
  , env :: Environment
  }
  deriving stock Show

data CheckTiming = CheckTiming
  { party :: MaybeEvaluated, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference, ev'time :: WHNF
  , events :: Reference, time :: WHNF, ev'reoffered :: Bool
  , env :: Environment
  }
  deriving stock Show

data PartyWHNF = PartyWHNF
  { act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference
  , events :: Reference, time :: WHNF
  , env :: Environment
  }
  deriving stock Show

data PartyEqual = PartyEqual
  { party :: WHNF, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference
  , events :: Reference, time :: WHNF
  , env :: Environment
  }
  deriving stock Show

data ScrutinizeParty = ScrutinizeParty
  { party :: WHNF, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: WHNF, ev'act :: Reference
  , events :: Reference, time :: WHNF
  , env :: Environment
  }
  deriving stock Show

data ScrutinizeEnvironment = ScrutinizeEnvironment
  { party :: WHNF, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: WHNF, ev'act :: Reference
  , events :: Reference, time :: WHNF
  , env :: Environment
  }
  deriving stock Show

data ScrutinizeActions = ScrutinizeActions
  { party :: WHNF, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: WHNF, ev'act :: Reference
  , events :: Reference, time :: WHNF
  , env :: Environment, henceEnv :: Environment -- ^ the environment to extend by when evaluating the hence clause
  }
  deriving stock Show

data ActionDoesn'tmatch = ActionDoesn'tmatch
  { party :: WHNF, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: WHNF, ev'act :: Reference
  , events :: Reference, time :: WHNF
  , env :: Environment
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
    -- ^ the latest completion so far, and the event stream that followed it:
    -- the anchor and residual the @HENCE@ is handed (spec §3.4, §5.1).
    --
    -- The TIE is decided by roll order — the first member to reach a given
    -- stamp keeps its stream. That is deterministic but not exact: when two
    -- members complete at the same instant, the stream kept may still contain
    -- the other's completing event, so an act stamped at the join can reach
    -- the continuation. Getting it exactly right means trimming the stream to
    -- events strictly after the join, which needs frames of its own; the
    -- limit is written into spec §11.0.1 and onto the doc page.
  , pending :: [WHNF]              -- ^ members still awaiting an event, reversed
  }
  deriving stock Show

data BarrierStampFrame = BarrierStampFrame
  { step   :: BarrierStepFrame
  , evsRef :: Reference            -- ^ the stream after the completing event
  }
  deriving stock Show

data BarrierStateDueFrame = BarrierStateDueFrame
  { ctx        :: QuantCtx
  , joinTime   :: Rational      -- ^ when the last member completed
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

data ResolvePartyFrame = ResolvePartyFrame
  { followup :: RExpr        -- ^ the HENCE / LEST followup to run once the party is keyed
  , env :: Environment       -- ^ environment in which to run the followup
  , events :: Reference      -- ^ remaining event stream (passed on to 'continueWithFollowup')
  , time :: Reference        -- ^ the (already-allocated) event time
  }
  deriving stock Show
