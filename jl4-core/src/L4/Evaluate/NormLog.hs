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
  ) where

import Base
import qualified Data.Text as Text
import Data.Ratio (denominator, numerator)
import L4.Parser.SrcSpan (SrcRange)
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
  deriving stock (Eq, Show, Generic)
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
-- Entries are ordered by log position. 'neObserved' is non-decreasing in log
-- position on a stream whose stamps never go backwards, and several entries
-- can share one stamp, so a consumer that needs a total order uses
-- (observed, log position). Where both instants are present,
-- @neEffective <= neObserved@ (N3's invariant).
data NormEntry = MkNormEntry
  { neFate      :: !Fate
  , neNorm      :: !(Maybe NormRef)
    -- ^ the norm instance the fate belongs to; 'Nothing' for a declared
    -- @BREACH@ (a terminal, not an obligation) and for an @AND@/@OR@
    -- compound, which are not norm instances
  , neModal     :: !(Maybe DeonticModal)
  , neBearer    :: !NormBearer
  , neAction    :: !(Maybe Text)
    -- ^ the action the norm owed or permitted, printed; 'Nothing' where
    -- there is none (a declared @BREACH@, a join)
  , neOrigin    :: !(Maybe NormOrigin)
  , neMember    :: !(Maybe NormMember)
  , neEffective :: !(Maybe Rational)
    -- ^ N3: when the fate took effect. For a failure, the missed deadline,
    -- no earlier than the obligation's own arming
  , neObserved  :: !(Maybe Rational)
    -- ^ N3: the stamp of the event on which the machine saw it
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
prettyNormEntry e =
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
