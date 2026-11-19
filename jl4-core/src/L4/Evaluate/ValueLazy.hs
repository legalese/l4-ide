module L4.Evaluate.ValueLazy where

import Base
import Control.Concurrent (ThreadId)
import Data.Time (Day, UTCTime)
import Data.Time.LocalTime (TimeOfDay)
import L4.Syntax
import L4.Evaluate.Operators (BinOp)

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
  deriving stock (Eq, Show)

instance NFData RBinOp where
  rnf ValROr = ()
  rnf ValRAnd = ()

-- | One failed obligation, as a breach records it (R-T3, EVERY-EACH-QUANTIFIER-SPEC
-- §6.1 on @unstable@, RULED 2026-09-15: _"let's not bother deduping the
-- ReasonForBreach — maybe we need to be able to say, 'well, Alice screwed the
-- pooch two different ways'"_). Ported from @unstable@ with SEESAW (§6.1.2
-- there); @specs/as-built/eval-breach.md@ says what was left behind.
--
-- A breach names every obligation that failed, ONE ENTRY EACH, with what was
-- failed: a missed deadline carries the party, the action it owed and the
-- deadline it missed; a declared breach carries whom @BREACH BY@ named (if
-- anyone) and its @BECAUSE@ (if any). Nothing is deduplicated — the same party
-- twice is two entries, and the two ways are visible in them. The same breach
-- on both sides of a @RAND@\/@ROR@ is one breach, not two, and is named once
-- (NOTE [The same breach on both sides is named once] in
-- 'L4.EvaluateLazy.Machine').
--
-- Each entry also carries its 'Timing' (SEESAW, spec §6.1.2): when it took
-- effect and when it came to light. A missed deadline has one from the moment
-- it is built; a declared breach gets its own where it meets the clock of the
-- hand-off that reached it ('L4.EvaluateLazy.Machine', the 'App1' frame), and
-- has none when it is evaluated outside any run.
data Failure a
  = MissedDeadline a (RAction Resolved) Rational (Timing a)
    -- ^ the party, the action it owed, the deadline it missed (a violated
    -- prohibition's own stamp), and when it took effect and came to light
  | DeclaredBreach (Maybe a) (Maybe a) (Maybe (Timing a))
    -- ^ @BREACH [BY p] [BECAUSE r]@: the party named, if any; the reason, if
    -- any; and its timing, once a run has given it one
  deriving stock (Generic, Show, Functor, Foldable, Traversable)
  deriving anyclass NFData

-- | When a failure took effect, and when the machine saw it (SEESAW, spec
-- §6.1.2; the two instants of NORM-LOG-SPEC N3 on @unstable@, applied to
-- every failure).
--
-- The two differ whenever a miss comes to light late: a deadline of 5 that an
-- event at 10 reveals took effect at 5 and was observed at 10. A compound is
-- breached at its operands' EFFECTIVE instants (the earliest for @RAND@, the
-- latest for @ROR@), never at the order its operands were evaluated in.
data Timing a = Timing
  { effective  :: Rational
    -- ^ a missed deadline, but never earlier than the obligation's own
    -- arming (an obligation armed after its deadline fails when it is
    -- armed); a violating act's stamp; a declared breach's hand-off clock
  , observed   :: Rational
    -- ^ the stamp of the event on which the machine saw the failure — for
    -- a declared breach with no such event, its hand-off clock
  , revealedBy :: Maybe (a, a)
    -- ^ that event's party and action, when an event revealed it
  }
  deriving stock (Generic, Show, Functor, Foldable, Traversable)
  deriving anyclass NFData

-- | The failures a breach names, in operand order — the drafter's, never
-- re-sorted — with the DECISIVE ones marked: the entries that fix the
-- compound's effective instant (SEESAW, spec §6.1.2). For @RAND@ that is the
-- earliest effective instant, for @ROR@ the latest,
-- worked out along the operand tree ('combineBlame'), so it does not depend
-- on which operand is written first. Several entries are decisive when they
-- took effect at the same instant.
--
-- One decisive entry is the 'anchor', marked by position so it is always one
-- of the entries: a missed deadline in preference to a declared breach, then
-- the one observed first, then the first in order. The scalars a breach
-- prints and serialises describe it; 'alsoDecisive' holds the positions (in
-- 'blameList') of the others. 'blameList' is @before ++ [anchor] ++ after@.
-- A single obligation's breach is @Blame [] f [] []@.
data Blame a = Blame
  { before       :: [Failure a]
  , anchor       :: Failure a
  , after        :: [Failure a]
  , alsoDecisive :: [Int]
  }
  deriving stock (Generic, Show, Functor, Foldable, Traversable)
  deriving anyclass NFData

-- | Why a contract is in breach.
--
-- The two constructors say what KIND of failure the breach is anchored at:
-- 'DeadlineMissed' carries the event that revealed the anchoring miss (its
-- party, action and stamp) beside the blame; 'ExplicitBreach' is anchored at a
-- declared breach. A compound breach — both operands of a @RAND@\/@ROR@ lost,
-- as two different breaches — concatenates both sides' failures and is
-- a 'DeadlineMissed' unless EVERY decisive entry is a declared breach
-- ('breachOf'), so which constructor it gets does not depend on the order of
-- the operands (SEESAW, spec §6.1.2). A single obligation's breach is the
-- singleton, which prints and serializes exactly as the one-party form did.
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

-- | The breach a blame describes: a 'DeadlineMissed' revealed by the anchor's
-- own revealing event when the anchor is a missed deadline (which 'combineBlame'
-- prefers whenever any decisive entry is one), else an 'ExplicitBreach'.
breachOf :: Blame a -> ReasonForBreach a
breachOf b = case b.anchor of
  MissedDeadline _ _ _ t | Just (p, act) <- t.revealedBy -> DeadlineMissed p act t.observed b
  _ -> ExplicitBreach b

-- | A single failure, its own anchor.
singleBlame :: Failure a -> Blame a
singleBlame f = Blame [] f [] []

-- | Every failure, in order: @before ++ [anchor] ++ after@.
blameList :: Blame a -> NonEmpty (Failure a)
blameList b = case b.before of
  []       -> b.anchor :| b.after
  (f : fs) -> f :| (fs ++ [b.anchor] ++ b.after)

-- | The anchor's position in 'blameList' (0-based) — what the wire reports.
anchorIndex :: Blame a -> Int
anchorIndex b = length b.before

-- | The positions (in 'blameList', 0-based, ascending) of every decisive
-- entry, the anchor's included.
decisiveIndices :: Blame a -> [Int]
decisiveIndices b = sort (anchorIndex b : b.alsoDecisive)

-- | A failure's timing, if it has one yet.
failureTiming :: Failure a -> Maybe (Timing a)
failureTiming = \ case
  MissedDeadline _ _ _ t -> Just t
  DeclaredBreach _ _ mt  -> mt

-- | When the breach took effect: its decisive entries' shared instant, if
-- they have one.
breachEffective :: Blame a -> Maybe Rational
breachEffective b = (.effective) <$> failureTiming b.anchor

-- | When the breach came to light: the earliest observation among its
-- decisive entries — the first moment a reader of the trace could know the
-- compound was lost.
breachObserved :: Blame a -> Maybe Rational
breachObserved b =
  case mapMaybe (fmap (.observed) . failureTiming . (entries !!)) (decisiveIndices b) of
    [] -> Nothing
    ts -> Just (minimum ts)
  where entries = toList (blameList b)

-- | Fill in a declared breach's timing where it has none (SEESAW, spec
-- §6.1.2). A timing already given is kept, so the instant a breach was first
-- reached is not overwritten by an enclosing hand-off.
fillDeclaredTiming :: Timing a -> Blame a -> Blame a
fillDeclaredTiming t b = b
  { before = map fill b.before, anchor = fill b.anchor, after = map fill b.after }
  where
    fill = \ case
      DeclaredBreach mp mr Nothing -> DeclaredBreach mp mr (Just t)
      f                            -> f

-- | Does any declared breach in the blame still lack a timing?
hasUntimed :: Blame a -> Bool
hasUntimed = any untimed . blameList
  where
    untimed = \ case
      DeclaredBreach _ _ Nothing -> True
      _                          -> False

-- | The party a failure names, if it names one.
failureParty :: Failure a -> Maybe a
failureParty = \ case
  MissedDeadline p _ _ _ -> Just p
  DeclaredBreach mp _ _  -> mp

-- | Every party the breach names, in order, WITH duplicates (no dedup, by
-- ruling); entries that name nobody contribute nothing.
blameParties :: Blame a -> [a]
blameParties = mapMaybe failureParty . toList . blameList

-- | Which operands of a compound decide when it was breached.
data Decider = LeftDecides | RightDecides | BothDecide
  deriving stock (Eq, Show)

-- | Two breached operands' blames, concatenated left first (the drafter's
-- order), with the decisive entries the operator picks along the operand
-- tree (SEESAW, spec §6.1.2): a @RAND@ is lost at the
-- EARLIER of its operands' effective instants, an @ROR@ at the LATER, and
-- the entries that fix that instant are the deciding operand's own decisive
-- entries — both operands' when the instants are equal. An operand with no
-- instant (a declared breach evaluated outside any run) neither wins nor
-- loses: both decide.
--
-- Commutative and associative in everything but the order of the list:
-- swapping the operands decides the same entries.
combineBlame :: RBinOp -> Blame a -> Blame a -> (Decider, Blame a)
combineBlame op l r = (decider, rebuild)
  where
    decider = case (breachEffective l, breachEffective r) of
      (Just el, Just er)
        | el == er                 -> BothDecide
        | (op == ValRAnd) == (el < er) -> LeftDecides
        | otherwise                -> RightDecides
      _                            -> BothDecide
    ls = toList (blameList l)
    rs = toList (blameList r)
    entries = ls ++ rs
    shift = length ls
    decisive = case decider of
      LeftDecides  -> decisiveIndices l
      RightDecides -> map (+ shift) (decisiveIndices r)
      BothDecide   -> decisiveIndices l ++ map (+ shift) (decisiveIndices r)
    rebuild = reanchor (representative entries decisive) decisive entries


-- | The decisive entry a breach prints and serialises as its anchor: a missed
-- deadline before a declared breach, then the earliest observed, then the
-- first in order. Only a tie on all three falls to position, and the entries
-- it then chooses between took effect at one instant and came to light at
-- one instant.
representative :: [Failure a] -> [Int] -> Int
representative entries decisive = case sortOn key [ (i, f) | (i, f) <- zip [0 ..] entries, i `elem` decisive ] of
  ((i, _) : _) -> i
  []           -> 0
  where
    -- kind, then whether it has a time at all (an untimed one last), then
    -- when it was observed, then position
    key (i, f) = case f of
      MissedDeadline _ _ _ t -> (0 :: Int, 0 :: Int, t.observed, i)
      DeclaredBreach _ _ mt  -> (1, maybe 1 (const 0) mt, maybe 0 (.observed) mt, i)

-- | The entries as a blame anchored at position @i@ (the first entry, should
-- @i@ be out of range), with the other decisive positions recorded beside it.
reanchor :: Int -> [Int] -> [Failure a] -> Blame a
reanchor i decisive entries = case splitAt i entries of
  (pre, f : post) -> Blame pre f post others
  _ -> case entries of
    f : post -> Blame [] f post (filter (/= 0) (nubOrd (sort decisive)))
    []       -> error "reanchor: a blame names at least one failure"
  where
    others = filter (/= i) (nubOrd (sort decisive))

data NullaryBuiltinFun
  = NullaryTodaySerial
  | NullaryNowSerial
  | NullaryTimezone          -- ^ Returns document IANA timezone name from TemporalContext
  | NullaryCurrentTime       -- ^ Returns current local TIME (requires TIMEZONE IS)
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

type MaybeEvaluated = MaybeEvaluated' RExpr

type MaybeEvaluated' a = Either a WHNF

type RExpr = Expr Resolved

instance NFData NullaryBuiltinFun where
  rnf :: NullaryBuiltinFun -> ()
  rnf NullaryTodaySerial = ()
  rnf NullaryNowSerial = ()
  rnf NullaryTimezone = ()
  rnf NullaryCurrentTime = ()

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
  rnf TernaryTimeFromHMS = ()
  rnf TernaryDatetimeFromDTZ = ()

-- NOTE: the ToJSON instances for 'NF', 'Value' and 'ReasonForBreach' (used by
-- @l4 batch --json@) live in "L4.Evaluate.ValueLazyJSON". They render the
-- obligation action via 'L4.Print.prettyLayout', and "L4.Print" imports this
-- module, so keeping them here would create an import cycle.
