module L4.EvaluateLazy.ContractFrame where

import Data.Text (Text)
import System.Mem.StableName (StableName, hashStableName)

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
  | ROperand [Reference]
  -- ^ an operand of a RAND or ROR has been evaluated to a rule: apply it to
  -- the clock and events in the list, or answer from the memo of rules already
  -- applied to the same (see 'AppliedKey'). It always sits directly on the
  -- 'RBinOp1' or 'RBinOp2' frame of its compound.
  | StampBreach StampBreachFrame
  -- ^ SEESAW (EVERY-EACH-QUANTIFIER-SPEC §6.1.2 on @unstable@): a breach that
  -- names a declared failure with no timing yet has met the @[time, events]@
  -- of the hand-off that reached it; the clock is being forced, so the
  -- failure can take it as its effective instant ('L4.EvaluateLazy.Machine',
  -- the @App1@ frame). A breach already timed is never re-stamped.
  | BreachBy BreachByFrame
  -- ^ @BREACH BY e@, with @e@ under evaluation: a party, or a LIST of parties
  -- walked one cell per step (R-T3, §6.1 on @unstable@).
  deriving stock Show

-- | What the application of a RAND or ROR operand to a clock and events is
-- remembered under: which rule, read through every name it uses, at which
-- clock, on which events. Two applications under equal keys reach the same
-- result, because the evaluator is pure: the rule is the same piece of syntax
-- ('RuleSyntax'), every name it uses denotes the same value ('ruleNames'), and
-- the clock and the events are the same.
--
-- A key only ever claims sameness it can see without evaluating anything, so
-- two applications that would agree may still get different keys (a miss,
-- which costs a second evaluation), but two that could disagree never get the
-- same one.
data AppliedKey = MkAppliedKey
  { ruleSyntax :: !RuleSyntax
  , ruleNames  :: ![(Unique, ValueKey)]
    -- ^ each name occurring in the rule that the rule's environment binds,
    -- with what it denotes
  , clock      :: !ValueKey
  , events     :: !EventsKey
  }
  deriving stock (Eq, Show)

-- | The syntax of a rule, by identity: the party, action, deadline, @HENCE@ and
-- @LEST@ of one 'Regulative' node. These are the very objects of the
-- program's syntax tree, which every evaluation of that node shares, so the
-- same node gives equal names and two different nodes never do.
data RuleSyntax = MkRuleSyntax
  !(StableName RExpr) !(StableName (RAction Resolved)) !(StableName (Maybe RExpr))
  !(StableName RExpr) !(StableName (Maybe RExpr))
  deriving stock Eq

instance Show RuleSyntax where
  show (MkRuleSyntax a b c d e) =
    "RuleSyntax " <> show [hashStableName a, hashStableName b, hashStableName c, hashStableName d, hashStableName e]

-- | What a reference denotes, as far as can be told without evaluating it: a
-- number or a string by its value, anything else by a reference known to
-- denote the same (see 'L4.EvaluateLazy.Machine.referenceKey').
data ValueKey
  = KNumber !Rational
  | KString !Text
  | KAddress !Address
  deriving stock (Eq, Show)

-- | A list of events, as far as can be told without evaluating it.
data EventsKey
  = KNoEvents
    -- ^ the empty list
  | KEvent !ValueKey !ValueKey !ValueKey !(Maybe (Rational, Int)) !Address
    -- ^ an event's party, action and time, the 'Reoffered' mark of the event
    -- copy, and the reference to the rest of the list. A copy an expiring
    -- rule re-offers is a fresh value at a fresh address on a fresh list, so
    -- the copies two expiring rules make of one event compare equal only by
    -- their content.
  | KEventsAt !Address
    -- ^ a list not yet evaluated, or not of this shape, by its reference
  deriving stock (Eq, Show)

-- | An obligation scrutinising its events. Every record from here to
-- 'ActionDoesn'tmatch' also carries @armed@: the clock the obligation was
-- entered at, the @time@ it met its events with at 'App1', kept while @time@
-- moves on to each event it sees. The expiry step floors a missed deadline's
-- effective instant and the hand-off clock at it (SEESAW, EVERY-EACH-QUANTIFIER-SPEC
-- §6.1.2 on @unstable@, its card A2), as @unstable@ does.
data ScrutinizeEvents = ScrutinizeEvents
  { party :: MaybeEvaluated, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , time :: Reference, armed :: Reference
  , env :: Environment
  }
  deriving stock Show

-- | The @ev'reoffered@ field threaded through 'ScrutinizeEvent',
-- 'CurrentTimeWHNF', 'ScrutinizeDue' and 'CheckTiming' records whether the
-- event under scrutiny is a copy an expiring obligation re-offered in a stalled
-- hand-off, and if so its mark (looked up at Contract1 via @isReoffered@). The
-- mark never withholds an event from a layer: it only lets the Contract5 expiry
-- step refuse a chain whose deadlines have stopped advancing. See the Contract5
-- NOTE in Machine.hs.
--
-- Only a stalled hand-off marks its copy. An unmarked event stands for a mark
-- whose 'highWater' is the clock of the layer reading it, and whose count is 0.
data Reoffered = MkReoffered
  { highWater :: !Rational
    -- ^ the time no deadline since has passed: the clock of the layer
    -- whose hand-off first stalled
  , stalled :: !Int
    -- ^ how many hand-offs in a row the deadline has failed to pass
    -- 'highWater'
  }
  deriving stock Show

data ScrutinizeEvent = ScrutinizeEvent
  { party :: MaybeEvaluated, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , events :: Reference, time :: Reference, ev'reoffered :: Maybe Reoffered, armed :: Reference
  , env :: Environment
  }
  deriving stock Show

data CurrentTimeWHNF = CurrentTimeWHNF
  { party :: MaybeEvaluated, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference, ev'time :: Reference
  , events :: Reference, time :: Reference, ev'reoffered :: Maybe Reoffered, armed :: Reference
  , env :: Environment
  }
  deriving stock Show

data ScrutinizeDue = ScrutinizeDue
  { party :: MaybeEvaluated, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference, ev'time :: WHNF
  , events :: Reference, time :: Reference, ev'reoffered :: Maybe Reoffered, armed :: Reference
  , env :: Environment
  }
  deriving stock Show

data CheckTiming = CheckTiming
  { party :: MaybeEvaluated, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference, ev'time :: WHNF
  , events :: Reference, time :: WHNF, ev'reoffered :: Maybe Reoffered, armed :: Reference
  , env :: Environment
  }
  deriving stock Show

data PartyWHNF = PartyWHNF
  { act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference
  , events :: Reference, time :: WHNF, armed :: Reference
  , env :: Environment
  }
  deriving stock Show

data PartyEqual = PartyEqual
  { party :: WHNF, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: Reference, ev'act :: Reference
  , events :: Reference, time :: WHNF, armed :: Reference
  , env :: Environment
  }
  deriving stock Show

data ScrutinizeParty = ScrutinizeParty
  { party :: WHNF, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: WHNF, ev'act :: Reference
  , events :: Reference, time :: WHNF, armed :: Reference
  , env :: Environment
  }
  deriving stock Show

data ScrutinizeEnvironment = ScrutinizeEnvironment
  { party :: WHNF, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: WHNF, ev'act :: Reference
  , events :: Reference, time :: WHNF, armed :: Reference
  , env :: Environment
  }
  deriving stock Show

data ScrutinizeActions = ScrutinizeActions
  { party :: WHNF, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: WHNF, ev'act :: Reference
  , events :: Reference, time :: WHNF, armed :: Reference
  , env :: Environment, henceEnv :: Environment -- ^ the environment to extend by when evaluating the hence clause
  }
  deriving stock Show

data ActionDoesn'tmatch = ActionDoesn'tmatch
  { party :: WHNF, act :: RAction Resolved, due :: MaybeEvaluated' (Maybe RExpr), followup :: RExpr, lest :: Maybe RExpr
  , ev'party :: WHNF, ev'act :: Reference
  , events :: Reference, time :: WHNF, armed :: Reference
  , env :: Environment
  }
  deriving stock Show

data RBinOp1 = MkRBinOp1
  { op :: RBinOp
  , rexpr2 :: MaybeEvaluated
  , args :: [Reference] -- ^ the arguments to the remaining contract expr
  , env :: Environment
  , record1 :: Maybe AppliedKey
    -- ^ the key the left operand's result is recorded under in the memo when
    -- it returns here, if it was keyed and not answered from the memo. Kept
    -- in this frame rather than in one of its own, so that a chain of RANDs,
    -- one per window, holds no more frames than it did without the memo.
  }
  deriving stock Show

data RBinOp2 = MkRBinOp2
  { op :: RBinOp
  , rval1 :: WHNF
  , env :: Environment
  , record2 :: Maybe AppliedKey
    -- ^ the same, for the right operand
  }
  deriving stock Show

-- | A breach whose declared failures are waiting for their hand-off clock
-- ('StampBreach').
data StampBreachFrame = StampBreachFrame
  { reason    :: ReasonForBreach Reference -- ^ the breach as it arrived
  , eventsRef :: Reference                 -- ^ the stream it was handed: a re-offered event at its head revealed it
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
