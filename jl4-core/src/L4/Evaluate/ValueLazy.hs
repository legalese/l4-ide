module L4.Evaluate.ValueLazy where

import Base
import Control.Concurrent (ThreadId)
import Data.Time (Day, UTCTime)
import Data.Time.LocalTime (TimeOfDay)
import L4.Syntax
import L4.Evaluate.Operators (BinOp)
import L4.TemporalContext (CtxReads)

-- | Public addresses. These must be globally unique, therefore
-- we for now include the URI.
--
data Address = MkAddress !NormalizedUri !Int
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass NFData

-- | A reference pairs a public address with a pointer to a thunk.
--
data Reference =
  MkReference
    { address :: !Address
    , pointer :: !(IORef Thunk)
    }
  deriving stock Generic
  deriving anyclass NFData

instance Show Reference where
  show reference = show reference.address

data Thunk =
    Unevaluated !(Set ThreadId) (Expr Resolved) !Environment
  | WHNF WHNF
    -- ^ context-independent result: final and monotone (never overwritten)
  | WHNFWhen !CtxReads WHNF (Expr Resolved) !Environment
    -- ^ context-DEPENDENT cached result (T6): the force that produced the
    -- value read the temporal context as recorded in the 'CtxReads'
    -- fingerprint. Served only while 'L4.TemporalContext.validFor' holds for
    -- the current context; the expr\/env are retained so the thunk can be
    -- re-forced under a different context.
  deriving stock Show

type Environment = Map Unique Reference

type WHNF = Value Reference

data NF = MkNF (Value NF) | Omitted
  deriving stock (Generic, Show)
  deriving anyclass NFData

data Value a =
    ValNumber Rational
  | ValString Text
  | ValDate Day
  | ValTime !TimeOfDay                 -- ^ Wall-clock time (local, no date/tz)
  | ValDateTime !UTCTime !Text         -- ^ UTC instant + IANA timezone name
  | ValNil
  | ValCons a a
  | ValClosure (GivenSig Resolved) (Expr Resolved) Environment
  | ValObligation Environment (Either RExpr (Value a)) (RAction Resolved) (Either (Maybe RExpr) (Value a)) RExpr (Maybe RExpr)
  | ValROp Environment RBinOp (Either RExpr (Value a)) (Either RExpr (Value a))
  | ValQuantified Environment (Deonton Resolved)
    -- ^ An ARMED but not yet run quantified obligation: @EVERY [Cast] v [WHO …]
    -- … [ONCE ALL HAVE | UPON EACH] …@ (EVERY-EACH-QUANTIFIER-SPEC §2.4).
    --
    -- Unlike 'ValObligation', which already knows its one party, a quantified
    -- obligation does not know its cast until it is applied to a time and an
    -- event stream: the roll (§2.2.7.5 point 5, the list the @WHO@ filter
    -- tests membership in) is read at that point — once, for the whole family
    -- (R-Q6\/R-T6, "the cast is evaluated once at arming"). Until then this
    -- value carries the whole 'Deonton' unchanged, so a residual prints back
    -- as the source form.
    --
    -- The 'Subject' inside is always an 'Every'; a 'Party' deonton becomes a
    -- 'ValObligation' directly.
  | ValNullaryBuiltinFun NullaryBuiltinFun
  | ValUnaryBuiltinFun UnaryBuiltinFun
  | ValBinaryBuiltinFun BinOp
  | ValTernaryBuiltinFun TernaryBuiltinFun
  | ValPartialTernary TernaryBuiltinFun a             -- Ternary with 1 arg applied
  | ValPartialTernary2 TernaryBuiltinFun a a          -- Ternary with 2 args applied
  | ValUnappliedConstructor Resolved
  | ValConstructor Resolved [a]
  | ValAssumed Resolved
  | ValEnvironment Environment
  | ValBreached (ReasonForBreach a)
  deriving stock (Show, Functor, Foldable, Traversable)

data RBinOp = ValROr | ValRAnd
  deriving stock Show

instance NFData RBinOp where
  rnf ValROr = ()
  rnf ValRAnd = ()

-- | One failed obligation, as a breach records it (R-T3, EVERY-EACH-QUANTIFIER-SPEC
-- §6.1, RULED 2026-09-15: _"let's not bother deduping the ReasonForBreach — maybe
-- we need to be able to say, 'well, Alice screwed the pooch two different ways'"_).
--
-- A breach names every obligation that failed, ONE ENTRY EACH, with what was
-- failed: a missed deadline carries the party, the action it owed and the
-- deadline it missed; a declared breach carries whom @BREACH BY@ named (if
-- anyone) and its @BECAUSE@ (if any). Nothing is deduplicated — the same party
-- twice is two entries, and the two ways are visible in them.
data Failure a
  = MissedDeadline a (RAction Resolved) Rational
    -- ^ the party, the action it owed, the deadline it missed
  | DeclaredBreach (Maybe a) (Maybe a)
    -- ^ @BREACH [BY p] [BECAUSE r]@: the party named, if any; the reason, if any
  deriving stock (Generic, Show, Functor, Foldable, Traversable)
  deriving anyclass NFData

-- | The failures a breach names, in operand \/ roll order, with ONE of them
-- marked as the ANCHOR — the failure the breach's time comes from (the
-- earliest for @RAND@ and for a barrier, the latest for @ROR@; see the
-- @RBinOp2@ clause and 'barrierFinish' in the machine). The anchor is marked
-- by position rather than by an index, so it is always one of the entries and
-- the order is the drafter's: 'blameList' is @before ++ [anchor] ++ after@.
-- A single obligation's breach is @Blame [] f []@.
data Blame a = Blame
  { before :: [Failure a]
  , anchor :: Failure a
  , after  :: [Failure a]
  }
  deriving stock (Generic, Show, Functor, Foldable, Traversable)
  deriving anyclass NFData

-- | Why a contract is in breach.
--
-- The two constructors say what KIND of failure the breach is anchored at:
-- 'DeadlineMissed' carries the event that revealed the anchoring miss (its
-- party, action and stamp) beside the blame; 'ExplicitBreach' is anchored at a
-- declared breach and carries no time. A compound breach — both operands of a
-- @RAND@\/@ROR@ lost, or several members of a barrier — keeps the anchor's
-- constructor and concatenates both sides' failures. A single obligation's
-- breach is the singleton, which prints and serializes exactly as the
-- one-party form did.
data ReasonForBreach a
  = DeadlineMissed a a Rational (Blame a)
    -- ^ revealing event's party, action and stamp; the failures, anchored at a
    -- 'MissedDeadline'
  | ExplicitBreach (Blame a)
    -- ^ the failures, anchored at a 'DeclaredBreach'
  deriving stock (Generic, Show, Functor, Foldable, Traversable)
  deriving anyclass NFData

-- | The blame of a breach, whichever kind it is anchored at.
breachBlame :: ReasonForBreach a -> Blame a
breachBlame = \ case
  DeadlineMissed _ _ _ b -> b
  ExplicitBreach b       -> b

-- | A single failure, its own anchor.
singleBlame :: Failure a -> Blame a
singleBlame f = Blame [] f []

-- | Every failure, in order: @before ++ [anchor] ++ after@.
blameList :: Blame a -> NonEmpty (Failure a)
blameList b = case b.before of
  []       -> b.anchor :| b.after
  (f : fs) -> f :| (fs ++ [b.anchor] ++ b.after)

-- | The anchor's position in 'blameList' (0-based) — what the wire reports.
anchorIndex :: Blame a -> Int
anchorIndex b = length b.before

-- | The party a failure names, if it names one.
failureParty :: Failure a -> Maybe a
failureParty = \ case
  MissedDeadline p _ _ -> Just p
  DeclaredBreach mp _  -> mp

-- | Every party the breach names, in order, WITH duplicates (no dedup, by
-- ruling); entries that name nobody contribute nothing.
blameParties :: Blame a -> [a]
blameParties = mapMaybe failureParty . toList . blameList

-- | Two blames concatenated (left first), anchored at the LEFT's anchor.
anchorLeft :: Blame a -> Blame a -> Blame a
anchorLeft l r = l { after = l.after ++ toList (blameList r) }

-- | Two blames concatenated (left first), anchored at the RIGHT's anchor.
anchorRight :: Blame a -> Blame a -> Blame a
anchorRight l r = r { before = toList (blameList l) ++ r.before }

data NullaryBuiltinFun
  = NullaryTodaySerial
  | NullaryNowSerial
  | NullaryTimezone          -- ^ Returns document IANA timezone name from TemporalContext
  | NullaryCurrentTime       -- ^ Returns current local TIME (requires TIMEZONE IS)
  | NullaryRulesEffectiveDate -- ^ Returns tcRuleValidTime (rule-version axis); falls back to localized today
  deriving stock (Show)

data UnaryBuiltinFun
  = UnaryIsInteger
  | UnaryRound
  | UnaryCeiling
  | UnaryFloor
  | UnaryPercent
  | UnarySqrt            -- NUMBER → NUMBER (square root)
  | UnaryLn              -- NUMBER → NUMBER (natural log, positive domain)
  | UnaryLog10           -- NUMBER → NUMBER (base-10 log, positive domain)
  | UnarySin             -- NUMBER → NUMBER (sine)
  | UnaryCos             -- NUMBER → NUMBER (cosine)
  | UnaryTan             -- NUMBER → NUMBER (tangent)
  | UnaryAsin            -- NUMBER → NUMBER (arcsine, [-1,1] domain)
  | UnaryAcos            -- NUMBER → NUMBER (arccosine, [-1,1] domain)
  | UnaryAtan            -- NUMBER → NUMBER (arctangent)
  -- String unary functions
  | UnaryStringLength    -- STRING → NUMBER
  | UnaryToUpper         -- STRING → STRING
  | UnaryToLower         -- STRING → STRING
  | UnaryTrim            -- STRING → STRING
  -- IO/JSON functions from main
  | UnaryFetch
  | UnaryEnv
  | UnaryJsonEncode
  | UnaryJsonDecode
  | UnaryDateValue
  | UnaryDateSerial
  | UnaryDateFromSerial
  | UnaryDateDay
  | UnaryDateMonth
  | UnaryDateYear
  | UnaryTimeValue
  | UnaryToString        -- α → STRING (runtime-restricted to supported types)
  | UnaryToNumber        -- STRING → MAYBE NUMBER
  | UnaryToDate          -- STRING → MAYBE DATE (uses runtime type info)
  -- TIME builtins
  | UnaryTimeHour         -- TIME → NUMBER
  | UnaryTimeMinute       -- TIME → NUMBER
  | UnaryTimeSecond       -- TIME → NUMBER
  | UnaryTimeToSerial     -- TIME → NUMBER (fraction of day)
  | UnaryTimeFromSerial   -- NUMBER → TIME
  | UnaryToTime           -- STRING → TIME (parse "HH:MM:SS")
  -- DATETIME builtins
  | UnaryDatetimeDate     -- DATETIME → DATE (local date via stored tz)
  | UnaryDatetimeTime     -- DATETIME → TIME (local time via stored tz)
  | UnaryDatetimeSerial   -- DATETIME → NUMBER (UTC-based serial)
  | UnaryDatetimeTzName   -- DATETIME → STRING (IANA timezone name)
  | UnaryToDatetime       -- STRING → DATETIME (parse ISO-8601)
  deriving stock (Show)

data TernaryBuiltinFun
  = TernarySubstring     -- STRING → NUMBER → NUMBER → STRING
  | TernaryReplace       -- STRING → STRING → STRING → STRING
  | TernaryPost          -- from main
  | TernaryDateFromDMY   -- NUMBER → NUMBER → NUMBER → DATE
  | TernaryEverBetween
  | TernaryAlwaysBetween
  -- TIME/DATETIME constructors
  | TernaryTimeFromHMS      -- NUMBER → NUMBER → NUMBER → TIME
  | TernaryDatetimeFromDTZ  -- DATE → TIME → STRING → DATETIME
  deriving stock (Show)

-- | This is a non-standard instance because environments can be recursive, hence we must
-- not actually force the environments ...
instance NFData a => NFData (Value a) where
  rnf :: Value a -> ()
  rnf (ValNumber i)               = rnf i
  rnf (ValDate d)                 = rnf d
  rnf (ValTime t)                 = rnf t
  rnf (ValDateTime u tz)          = rnf u `seq` rnf tz
  rnf (ValROp env op a b)     = env `seq` op `deepseq` a `deepseq` b `deepseq` ()
  rnf (ValString t)               = rnf t
  rnf ValNil                      = ()
  rnf (ValCons r1 r2)             = rnf r1 `seq` rnf r2
  rnf (ValClosure given expr env) = env `seq` rnf given `seq` rnf expr
  rnf (ValNullaryBuiltinFun r)    = rnf r
  rnf (ValUnaryBuiltinFun r)      = rnf r
  rnf (ValBinaryBuiltinFun r)     = rnf r
  rnf (ValTernaryBuiltinFun r)    = rnf r
  rnf (ValPartialTernary r a)     = rnf r `seq` rnf a
  rnf (ValPartialTernary2 r a b)  = rnf r `seq` rnf a `seq` rnf b
  rnf (ValUnappliedConstructor r) = rnf r
  rnf (ValConstructor r vs)       = rnf r `seq` rnf vs
  rnf (ValAssumed r)              = rnf r
  rnf (ValEnvironment env)        = env `seq` ()
  rnf (ValBreached ev)            = rnf ev `seq` ()
  rnf (ValObligation env p a t f l) = env `seq` p `deepseq` a `deepseq` t `deepseq` f `deepseq` l `deepseq` ()
  rnf (ValQuantified env d)       = env `seq` d `deepseq` ()

type MaybeEvaluated = MaybeEvaluated' RExpr

type MaybeEvaluated' a = Either a WHNF

type RExpr = Expr Resolved

instance NFData NullaryBuiltinFun where
  rnf :: NullaryBuiltinFun -> ()
  rnf NullaryTodaySerial = ()
  rnf NullaryNowSerial = ()
  rnf NullaryTimezone = ()
  rnf NullaryCurrentTime = ()
  rnf NullaryRulesEffectiveDate = ()

instance NFData UnaryBuiltinFun where
  rnf :: UnaryBuiltinFun -> ()
  rnf UnaryIsInteger = ()
  rnf UnaryRound = ()
  rnf UnaryCeiling = ()
  rnf UnaryFloor = ()
  rnf UnaryPercent = ()
  rnf UnarySqrt = ()
  rnf UnaryLn = ()
  rnf UnaryLog10 = ()
  rnf UnarySin = ()
  rnf UnaryCos = ()
  rnf UnaryTan = ()
  rnf UnaryAsin = ()
  rnf UnaryAcos = ()
  rnf UnaryAtan = ()
  rnf UnaryStringLength = ()
  rnf UnaryToUpper = ()
  rnf UnaryToLower = ()
  rnf UnaryTrim = ()
  rnf UnaryToString = ()
  rnf UnaryToNumber = ()
  rnf UnaryToDate = ()
  rnf UnaryFetch = ()
  rnf UnaryEnv = ()
  rnf UnaryJsonEncode = ()
  rnf UnaryJsonDecode = ()
  rnf UnaryDateValue = ()
  rnf UnaryDateSerial = ()
  rnf UnaryDateFromSerial = ()
  rnf UnaryDateDay = ()
  rnf UnaryDateMonth = ()
  rnf UnaryDateYear = ()
  rnf UnaryTimeValue = ()
  rnf UnaryTimeHour = ()
  rnf UnaryTimeMinute = ()
  rnf UnaryTimeSecond = ()
  rnf UnaryTimeToSerial = ()
  rnf UnaryTimeFromSerial = ()
  rnf UnaryToTime = ()
  rnf UnaryDatetimeDate = ()
  rnf UnaryDatetimeTime = ()
  rnf UnaryDatetimeSerial = ()
  rnf UnaryDatetimeTzName = ()
  rnf UnaryToDatetime = ()

instance NFData TernaryBuiltinFun where
  rnf :: TernaryBuiltinFun -> ()
  rnf TernarySubstring = ()
  rnf TernaryReplace = ()
  rnf TernaryPost = ()
  -- new temporals
  rnf TernaryDateFromDMY = ()
  rnf TernaryEverBetween = ()
  rnf TernaryAlwaysBetween = ()
  rnf TernaryTimeFromHMS = ()
  rnf TernaryDatetimeFromDTZ = ()

-- NOTE: the ToJSON instances for 'NF', 'Value' and 'ReasonForBreach' (used by
-- @l4 batch --json@) live in "L4.Evaluate.ValueLazyJSON". They render the
-- obligation action via 'L4.Print.prettyLayout', and "L4.Print" imports this
-- module, so keeping them here would create an import cycle.
