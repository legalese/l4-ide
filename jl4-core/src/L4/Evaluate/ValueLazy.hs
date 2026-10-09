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
  | ValObligation Environment (Either RExpr (Value a)) (RAction Resolved) (Either (Maybe (Opening Resolved)) (Maybe (Value a))) (Either (Maybe (Deadline Resolved)) (Value a)) RExpr (Maybe RExpr)
    -- ^ The fourth field is the window's OPENING edge (EVERY-EACH-QUANTIFIER-SPEC
    -- §5.1.2, R-X5, built 2026-09-16): before the first event, the source
    -- @AFTER d [OF anchor]@ \/ @AFTER date@ (or nothing); after it, the time
    -- still to run until the window opens, as a number relative to the
    -- obligation's current clock — @Just@ while the window has not opened,
    -- @Nothing@ once it has (or when there never was an @AFTER@). The fifth
    -- is the CLOSING edge: before the first event, the source @WITHIN d [OF
    -- anchor]@ \/ @BEFORE date@ (or nothing); after it, the REMAINING due as
    -- a number relative to the same clock — or, while the window has still
    -- to open, relative to the OPENING instant, so that the two numbers read
    -- together as the bare re-anchored window they are (@AFTER 1 WITHIN 30@
    -- is @[clock+1, clock+1+30]@). An anchor, and the re-anchoring of a bare
    -- @WITHIN@ on its @AFTER@, are spent by that first evaluation
    -- ('L4.EvaluateLazy.Machine', @Contract4@).
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
  | ValConnective Connective
    -- ^ The built-in @AND@, @OR@, @IMPLIES@ or @NOT@ as a function value
    -- (UNKNOWN-EVALUATION-SPEC §4.4, U2, U2b). Not a closure: applying one
    -- evaluates its operands in the connective's own frames, the left first
    -- and the right only if the left does not decide. Being a value of its
    -- own, it keeps those frames when it is called through a variable.
  | ValTernaryBuiltinFun TernaryBuiltinFun
  | ValPartialTernary TernaryBuiltinFun a             -- Ternary with 1 arg applied
  | ValPartialTernary2 TernaryBuiltinFun a a          -- Ternary with 2 args applied
  | ValUnappliedConstructor Resolved
  | ValConstructor Resolved [a]
  | ValAssumed Resolved (Maybe (Type' Resolved))
    -- ^ An input nobody supplied, with the type it was declared at, if it
    -- was (UNKNOWN-EVALUATION-SPEC §4.6, U6b).
  | ValTerm Term
    -- ^ A value the evaluator could not determine because it depends on an
    -- input nobody supplied: a field of an unknown record, a built-in
    -- operation or a comparison over an unknown, an assumed function applied,
    -- or a connective whose operands did not decide it (§4.2, build step 3).
    -- A bare unknown input stays a 'ValAssumed'; a 'ValTerm' is never one.
  | ValEnvironment Environment
  | ValBreached (ReasonForBreach a)
  deriving stock (Show, Functor, Foldable, Traversable)

-- | Which built-in connective a 'ValConnective' is.
data Connective = ConnAnd | ConnOr | ConnImplies | ConnNot
  deriving stock (Eq, Show)

-- | A term (UNKNOWN-EVALUATION-SPEC §4.2): what the evaluator builds where it
-- needs the value of an input nobody supplied and can say what the value
-- would be in terms of that input. It is a closed, strict tree: a determined
-- operand is held as its normal form, so two terms are the same unknown
-- exactly when they are equal ('Eq', which compares names by 'Unique'), and
-- that equality is an atom's key (§4.6).
data Term
  = TInput Resolved (Maybe (Type' Resolved))
    -- ^ an unsupplied input, with its declared type
  | TNumber Rational
  | TString Text
  | TDate Day
  | TTime TimeOfDay
  | TDateTime UTCTime Text
  | TNil
  | TCons Term Term
  | TCon Resolved [Term]
    -- ^ a constructor applied; @TRUE@ and @FALSE@ are nullary ones
  | TField Term Resolved (Maybe (Type' Resolved))
    -- ^ @t's f@: a field of an unknown record, with the field's type
  | TCall Term [Term]
    -- ^ an assumed function applied
  | TBin BinOp Term Term
    -- ^ a built-in operation or comparison, at least one operand unknown
  | TNot Term
  | TConn Connective Term Term
    -- ^ @AND@, @OR@ or @IMPLIES@, the left operand unknown
  deriving stock (Show, Generic)
  deriving anyclass NFData

instance Eq Term where
  TInput a _      == TInput b _      = getUnique a == getUnique b
  TNumber a       == TNumber b       = a == b
  TString a       == TString b       = a == b
  TDate a         == TDate b         = a == b
  TTime a         == TTime b         = a == b
  TDateTime a _   == TDateTime b _   = a == b
  TNil            == TNil            = True
  TCons a as      == TCons b bs      = a == b && as == bs
  TCon a as       == TCon b bs       = getUnique a == getUnique b && as == bs
  TField t f _    == TField u g _    = getUnique f == getUnique g && t == u
  TCall f as      == TCall g bs      = f == g && as == bs
  TBin o a b      == TBin p c d      = o == p && a == c && b == d
  TNot a          == TNot b          = a == b
  TConn c a b     == TConn d e f     = c == d && a == e && b == f
  _               == _               = False

-- | The names a term waits on, in evaluation order, each once: every input
-- it reads, except that a field read on an input, or on a field of one,
-- names the whole path (@d's age@), since that is what is needed (§4.12 row
-- 35).
termNames :: Term -> [Term]
termNames = nubOrdered . go
  where
    go = \ case
      t@TInput{} -> [t]
      t@(TField b _ _)
        | isPath b  -> [t]
        | otherwise -> go b
      TCons a b   -> go a <> go b
      TCon _ ts   -> concatMap go ts
      TCall f as  -> go f <> concatMap go as
      TBin _ a b  -> go a <> go b
      TNot a      -> go a
      TConn _ a b -> go a <> go b
      TNumber{}   -> []
      TString{}   -> []
      TDate{}     -> []
      TTime{}     -> []
      TDateTime{} -> []
      TNil        -> []
    isPath = \ case
      TInput{}       -> True
      TField b _ _   -> isPath b
      _              -> False
    nubOrdered = foldr (\ x acc -> x : filter (/= x) acc) []

instance NFData Connective where
  rnf c = c `seq` ()

data RBinOp = ValROr | ValRAnd
  deriving stock (Eq, Show)

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
-- §6.1.2; NORM-LOG-SPEC N3's two instants, applied to every failure).
--
-- The two differ whenever a miss comes to light late: a deadline of 5 that an
-- event at 10 reveals took effect at 5 and was observed at 10. A compound is
-- breached at its operands' EFFECTIVE instants (the earliest for @RAND@, the
-- latest for @ROR@), never at the order its operands were evaluated in.
data Timing a = Timing
  { effective  :: Rational
    -- ^ a missed deadline, but never earlier than the obligation's own
    -- arming (an obligation armed after its deadline fails when it is
    -- armed, and the run says so in a note); a violating act's stamp; a
    -- declared breach's hand-off clock
  , observed   :: Rational
    -- ^ the stamp of the event on which the machine saw the failure — for
    -- a declared breach with no such event, its hand-off clock
  , revealedBy :: Maybe (a, a)
    -- ^ that event's party and action, when an event revealed it
  }
  deriving stock (Generic, Show, Functor, Foldable, Traversable)
  deriving anyclass NFData

-- | The failures a breach names, in operand \/ roll order — the drafter's,
-- never re-sorted — with the DECISIVE ones marked: the entries that fix the
-- compound's effective instant (SEESAW, spec §6.1.2). For @RAND@ and a
-- barrier that is the earliest effective instant, for @ROR@ the latest,
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
-- or several members of a barrier — concatenates both sides' failures and is
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
-- tree (SEESAW, spec §6.1.2): a @RAND@ (and a barrier) is lost at the
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

-- | Several breaches' blames, concatenated in order, combined as a @RAND@: the
-- barrier's verdict over the members that failed (SEESAW, spec §6.1.2).
combineAll :: NonEmpty (Blame a) -> Blame a
combineAll (b :| bs) = foldl' (\ acc x -> snd (combineBlame ValRAnd acc x)) b bs

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
  rnf (ValConnective c)           = rnf c
  rnf (ValTernaryBuiltinFun r)    = rnf r
  rnf (ValPartialTernary r a)     = rnf r `seq` rnf a
  rnf (ValPartialTernary2 r a b)  = rnf r `seq` rnf a `seq` rnf b
  rnf (ValUnappliedConstructor r) = rnf r
  rnf (ValConstructor r vs)       = rnf r `seq` rnf vs
  rnf (ValAssumed r t)            = rnf r `seq` rnf t
  rnf (ValTerm t)                 = rnf t
  rnf (ValEnvironment env)        = env `seq` ()
  rnf (ValBreached ev)            = rnf ev `seq` ()
  rnf (ValObligation env p a o t f l) = env `seq` p `deepseq` a `deepseq` o `deepseq` t `deepseq` f `deepseq` l `deepseq` ()
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
