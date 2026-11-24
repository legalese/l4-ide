-- | The norm log: what the machine writes down about a norm's fate.
--
-- This is the vocabulary of @specs/todo/NORM-LOG-SPEC.md@ (rulings N1, N2,
-- N3, N5, N7 and N8). One 'NormEntry' records one fate of one norm instance:
-- the machine decided that a norm was armed, performed, failed and so on,
-- and wrote it down, at the point where it decided. Nothing here is a
-- /drafter's/ assertion (that is @RECORD@/@COMMIT@, an 'L4.Evaluate.Ledger.Assign');
-- the entries live in a ledger of their own, which @RECALL@ cannot see (N5).
--
-- The types are plain data with no dependency on the evaluator, so that a
-- reader (a later phase), a printer and a bridge to another system can all
-- use them.
--
-- == Loud and silent
--
-- Where an entry says less than the machine knew, the cause is a field that
-- is a 'Maybe' or a constructor that says so, never an absent entry: an
-- unforced party is 'WrittenBearer' or 'NotYetKnown' (N7 rule 4), and a fate
-- with no instant has 'Nothing' in 'neEffective' and 'neObserved' (N3). A
-- reader that windows on such an entry must fail loudly; a count that quietly
-- skips it would be a number with exit code 0.
module L4.Evaluate.NormLog
  ( NormEntry (..)
  , Fate (..)
  , FailedTo (..)
  , JoinOp (..)
  , NormBearer (..)
  , NormRef (..)
  , NormOrigin (..)
  , OriginBranch (..)
  , NormMember (..)
  , normLogVerb
  , prettyNormEntry
  , fateText
  , originCarrierAddress
  , originCarrierLimit
  , instantCarrierAddress
  , instantCarrierLimit
  ) where

import Base
import qualified Data.Text as Text
import Data.Ratio (denominator, numerator)
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.Syntax (DeonticModal (..))

-- | What happened to a norm (N1), keyed on the modal: @MUST@ and @DO@ are
-- armed, performed, failed; @SHANT@ is armed, violated, kept; @MAY@ is armed,
-- exercised, lapsed. 'Breached' is an explicit @BREACH@, and the join
-- outcomes belong to a compound or an @EVERY@.
data Fate
  = FateArmed
    -- ^ the norm met its event stream; nothing has happened to it yet. N13
    -- reads "outstanding" through this entry: an armed norm with no later
    -- fate is the only trace of one that is still owed
  | FatePerformed
    -- ^ a @MUST@ or @DO@ whose action was done in time
  | FateFailed !FailedTo
    -- ^ a @MUST@ or @DO@ whose deadline passed without the action
  | FateViolated
    -- ^ a @SHANT@ whose forbidden action was done
  | FateKept
    -- ^ a @SHANT@ whose window closed without the forbidden action
  | FateExercised
    -- ^ a @MAY@ whose permitted action was done
  | FateLapsed
    -- ^ a @MAY@ whose window closed unexercised; never a failure (N1)
  | FateBreached
    -- ^ a declared @BREACH@, logged each time a continuation reaches it (N7
    -- rule 1), not once when the thunk that holds it is first built
  | FateJoinedFulfilled !JoinOp
    -- ^ an @AND@/@OR@ compound reduced to a fulfilment (N1's join outcome)
  | FateJoinedBreached !JoinOp
    -- ^ an @AND@/@OR@ compound reduced to a breach. A compound still
    -- pending has no outcome and writes nothing
  | FateJoinReleased
    -- ^ an @EVERY@ barrier: every arm satisfied, the shared @HENCE@ runs
  | FateJoinExpired
    -- ^ an @EVERY@ barrier met, but after its @ONCE … WITHIN@ deadline
  | FateJoinFailed
    -- ^ an @EVERY@ barrier: a member definitively did not complete
  | FateJoinStalled
    -- ^ an @EVERY@ barrier with no @LEST@ whose @MAY@ member lapsed
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | N8's detail on a failure: whether the failure armed a reparation.
-- Whether a reparation then /cured/ it is read later, over the parent
-- links; it is not an entry.
data FailedTo
  = FailedToLest
    -- ^ a @LEST@ continuation ran. It need not be a reparation: a @LEST
    -- BREACH@ is a @LEST@ too, and what it armed is told by the entries it
    -- wrote (N8), not by this
  | FailedToBreach
    -- ^ no continuation: a breach followed at once
  | FailedToJoin
    -- ^ the norm is a member of an @EVERY@ barrier, whose own @LEST@ is a
    -- sentinel: the failure was reported to the join, and the join's own
    -- entry says what followed (N1: a member's fate is its own failure, not
    -- its report to the barrier)
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | Which connective a compound's join outcome is for.
data JoinOp = JoinAnd | JoinOr
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | Whose norm it is (N2, N7 rules 3 and 4). The machine never forces a
-- party for the log, so what it knows when it writes depends on the run; the
-- four cases are kept apart because a reader treats them differently:
-- 'UnknownBearer' must make a read that filters by bearer fail, and 'NobodyBearer'
-- must not.
data NormBearer
  = KnownBearer !Text
    -- ^ the party, keyed exactly as the ledger keys it
  | WrittenBearer !Text
    -- ^ the party as the rule WROTE it, because nothing had forced it: a
    -- name, not a resolved party (@theLandlord@ and @Landlord OF "Ms Ng"@ do
    -- not compare by equality)
  | NobodyBearer
    -- ^ the drafter named no party: a bare @BREACH@, or a join
  | UnknownBearer
    -- ^ the party exists but the machine had not forced it, and no written
    -- form is known either
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | The address of a norm instance: where it was written, and the /n/-th
-- time the trace entered that site. The same pair as the step log's key.
data NormRef = MkNormRef
  { nrSite       :: !(Maybe SrcRange)
  , nrActivation :: !Int
  }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass NFData

-- | Which continuation of its parent armed a norm (N8).
data OriginBranch = ViaHence | ViaLest
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | N8: the norm whose @HENCE@ or @LEST@ armed this one, and which of the two.
-- A norm armed from the top level has none. Both are known at arming time
-- and cannot be reconstructed afterwards.
data NormOrigin = MkNormOrigin
  { noParent       :: !NormRef
  , noParentModal  :: !DeonticModal
  , noParentBearer :: !NormBearer
    -- ^ the parent's, as known when the hand-off was made; this is what a
    -- bare @BREACH@ on a @LEST@ path takes (N7 rule 2)
  , noBranch       :: !OriginBranch
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | Membership of an @EVERY@, as known when the norm was armed.
data NormMember = MkNormMember
  { nmJoinSite :: !(Maybe SrcRange)
  , nmIndex    :: !Int  -- ^ position in the roll, from 1
  , nmTotal    :: !Int
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | One fate of one norm instance, on the contract clock.
--
-- Entries are ordered by log position, and log position is not time. Things
-- a reader that windows on time must know (review of P1, S4):
--
--   * the 'neObserved' of the fate of a norm (performed, failed, violated,
--     kept, exercised, lapsed) is non-decreasing in log position on a stream
--     whose stamps never go backwards, except under an @ROR@, which still runs
--     its left operand over the whole trace before its right (N17 is not
--     built);
--   * an 'FateArmed' entry is written when the machine first forces the clock
--     the norm was armed at, which can be after a fate of another norm with a
--     later stamp (a barrier's second member is armed at the start and written
--     when its own first event is looked at);
--   * a compound's entry and a declared @BREACH@'s carry SEESAW's instants,
--     which are the earliest moment the breach could be known, so they can be
--     earlier than the entries written before them;
--   * several entries can share one stamp.
--
-- So a consumer that needs a total order uses (observed, log position), and
-- must not read position as time. Where both instants are present,
-- @neEffective <= neObserved@ (N3's invariant; 'NormLogSpec' pins it on every
-- entry of every directive of every fixture).
data NormEntry = MkNormEntry
  { neFate      :: !Fate
  , neNorm      :: !(Maybe NormRef)
    -- ^ the norm instance the fate belongs to; 'Nothing' for a declared
    -- @BREACH@ (a terminal, not an obligation). For an @AND@/@OR@ compound,
    -- which is not a norm instance, it names the application of the compound:
    -- its site is the place of its first operand that was still an expression
    -- (the one the machine keeps for the compound, and none when both were
    -- values), and its activation counts the times that site was entered, so
    -- two compounds in one trace are told apart
  , neModal     :: !(Maybe DeonticModal)
  , neBearer    :: !NormBearer
  , neAction    :: !(Maybe Text)
    -- ^ the action the norm owed or permitted, printed; 'Nothing' where
    -- there is none (a declared @BREACH@, a join)
  , neActionHead :: !(Maybe Text)
    -- ^ N2 (P2): the constructor the norm's action pattern names, from the
    -- syntax, which is what a read's action pattern matches on. 'Nothing'
    -- where 'neAction' is, and for an action pattern with no constructor
  , neEnclosing :: ![NormRef]
    -- ^ N13 (P2): the compounds (@AND@\/@OR@ applications, each named by the
    -- 'NormRef' of its own join entry) and the @EVERY ... ONCE@ barrier whose
    -- operand or member this norm was armed inside, innermost first. A
    -- compound or barrier that has decided leaves its other operands armed
    -- with no fate, and this is how a read tells such a norm from one that is
    -- still owed. The whole chain is here and not only the innermost, because
    -- a compound that has not reduced writes no entry, so a read could not
    -- climb from it to the one outside. A compound's own entry carries the
    -- same field for the compounds it sits in. Empty outside every compound
  , neOrigin    :: !(Maybe NormOrigin)
  , neMember    :: !(Maybe NormMember)
  , neEffective :: !(Maybe Rational)
    -- ^ N3: when the fate took effect. For a failure, the missed deadline,
    -- no earlier than the obligation's own arming. For a norm armed by a
    -- hand-off, the hand-off's clock. For a breached compound, SEESAW's rule
    -- 2: a @RAND@ at the earlier of its operands' effective instants, an @ROR@
    -- at the later. 'Nothing' for a fulfilled compound (@FULFILLED@ carries no
    -- time) and for a lapsed @MAY@ under a barrier
  , neObserved  :: !(Maybe Rational)
    -- ^ N3: the stamp of the event on which the machine saw it. For a norm
    -- armed by a hand-off, the event that revealed the hand-off
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | The verb a norm entry prints with: its own, so that an audit listing
-- never shows the machine asserting a fact as though a party had (N5).
normLogVerb :: Text
normLogVerb = "FATE"

-- | One audit-listing row for a norm entry, in the shape of the ledger's own
-- rows but with its own verb and @bearer=@ where a party's entry has
-- @party=@ (N5):
--
-- > FATE failed (to reparation) MUST pay   [bearer=Alice, effective=5, observed=7, origin=LEST of #1]
prettyNormEntry :: NormEntry -> Text
prettyNormEntry = oneLine . prettyNormEntry'
  where
    -- a party or an action can print over several lines (a string with a
    -- newline in it, a CONSIDER); a row is one line, because a reader of the
    -- listing and the test that strips it both take it as one (review of P1, L1)
    oneLine = Text.replace "\r" "\\r" . Text.replace "\n" "\\n"

prettyNormEntry' :: NormEntry -> Text
prettyNormEntry' e =
  "  " <> normLogVerb <> " " <> fateText e.neFate
    <> maybe "" (\m -> " " <> modalText m) e.neModal
    <> maybe "" (" " <>) e.neAction
    <> "   [bearer=" <> bearerText e.neBearer
    <> ", effective=" <> instantText e.neEffective
    <> ", observed=" <> instantText e.neObserved
    <> maybe "" (\o -> ", origin=" <> originText o) e.neOrigin
    <> ", activation=" <> maybe "-" (Text.pack . show . (.nrActivation)) e.neNorm
    <> "]"
  where
    instantText = maybe "-" showInstant

showInstant :: Rational -> Text
showInstant r
  | denominator r == 1 = Text.pack (show (numerator r))
  | otherwise          = Text.pack (show (numerator r)) <> "/" <> Text.pack (show (denominator r))

modalText :: DeonticModal -> Text
modalText = \case
  DMust    -> "MUST"
  DMustNot -> "SHANT"
  DMay     -> "MAY"
  DDo      -> "DO"

fateText :: Fate -> Text
fateText = \case
  FateArmed             -> "armed"
  FatePerformed         -> "performed"
  FateFailed FailedToLest -> "failed (to LEST)"
  FateFailed FailedToBreach     -> "failed (to breach)"
  FateFailed FailedToJoin       -> "failed (to the join)"
  FateViolated          -> "violated"
  FateKept              -> "kept"
  FateExercised         -> "exercised"
  FateLapsed            -> "lapsed"
  FateBreached          -> "breached"
  FateJoinedFulfilled op -> "joined (" <> joinOpText op <> ", fulfilled)"
  FateJoinedBreached op  -> "joined (" <> joinOpText op <> ", breached)"
  FateJoinReleased      -> "join released"
  FateJoinExpired       -> "join expired"
  FateJoinFailed        -> "join failed"
  FateJoinStalled       -> "join stalled"

joinOpText :: JoinOp -> Text
joinOpText = \case
  JoinAnd -> "AND"
  JoinOr  -> "OR"

bearerText :: NormBearer -> Text
bearerText = \case
  KnownBearer t   -> t
  WrittenBearer t -> t <> " (as written)"
  NobodyBearer    -> "nobody named"
  UnknownBearer   -> "not yet known"

originText :: NormOrigin -> Text
originText o =
  (case o.noBranch of { ViaHence -> "HENCE"; ViaLest -> "LEST" })
    <> " of activation " <> Text.pack (show o.noParent.nrActivation)
    -- where the parent was written, so a link that points at the wrong norm
    -- can be seen to (review of P1, L2)
    <> maybe "" (\ r -> " (line " <> Text.pack (show r.start.line) <> ")") o.noParent.nrSite

-- | The addresses of the references the norm log makes for itself, which take
-- no address from the evaluation's supply (NORM-LOG-SPEC N8 and N4, P1 and
-- P2). Every printed party key that holds an unforced field names its
-- address, so a writer that allocated from the supply would change what a
-- ledger listing prints; the carriers sit at negative addresses instead, which
-- the supply (counting up from zero) never reaches.
--
-- The plan for all of them is here, in one place, and it fits a 32-bit 'Int',
-- because that is what an @Int@ is on the WASM target: the first half of P2
-- wrote @negate (2^40 + ...)@ and did not compile there. Neither the native
-- build nor the gate builds WASM; CI's WASM job found it.
--
-- The negative 32-bit range is split in two, 2^30 addresses each, and every
-- carrier takes the next free address of its own half from a counter, so the
-- halves cannot meet:
--
-- > supply:            0, 1, 2, ...                     (non-negative)
-- > origin carriers:   -1 down to -(2^30 - 1)           ('originCarrierAddress')
-- > instant carriers:  -2^30 down to -(2^31 - 1)        ('instantCarrierAddress')
--
-- The origin carriers are numbered by the log of one directive, as P1 numbered
-- them (its entries, one log per directive), so two directives of a module may
-- hand out the same address; the instant carriers are numbered by the
-- evaluation (one counter in the evaluation's state, shared by its
-- directives), so within an evaluation no two of them share an address.
--
-- Running out of a half is a loud error at the call site (the functions
-- return 'Nothing'), never a wrap into the other half. 2^30 of either is more
-- than an evaluation can hold in memory.
--
-- A counter that belonged to the process (@Data.Unique@'s, which the first
-- half of P2 used) would not do: the service is long-lived, the counter keeps
-- growing across requests, and a wrap into a window could land two live
-- carriers on one address. The counters here start at zero for each
-- evaluation, and two evaluations may reuse an address freely: an address
-- also names its module's URI, and every table keyed by it belongs to one
-- evaluation.

-- | The address of the @n@th parent-link carrier of a directive's log, @n@
-- counting from zero.
originCarrierAddress :: Int -> Maybe Int
originCarrierAddress n
  | n < 0 || n >= originCarrierLimit = Nothing
  | otherwise                        = Just (negate (n + 1))

-- | How many parent-link carriers one log may make: 2^30 - 1, so the
-- last one is at @-(2^30 - 1)@ and the instant carriers' half starts below.
originCarrierLimit :: Int
originCarrierLimit = 1073741823

-- | The address of the @k@th instant carrier of an evaluation, @k@ counting
-- from zero: one per guard evaluation (@THE INSTANT@).
instantCarrierAddress :: Int -> Maybe Int
instantCarrierAddress k
  | k < 0 || k >= instantCarrierLimit = Nothing
  | otherwise                         = Just (negate (1073741824 + k))

-- | How many instant carriers an evaluation may make: 2^30, the last one at
-- @-(2^31 - 1)@, which is inside a 32-bit 'Int'.
instantCarrierLimit :: Int
instantCarrierLimit = 1073741824
