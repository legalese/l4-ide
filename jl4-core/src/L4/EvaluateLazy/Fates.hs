-- | The projection from the deontic step log to the norm log
-- (NORM-LOG-SPEC N1, N3, N6, N8).
--
-- The machine already decides every fate and writes it down, as a
-- 'DeonticStep', at the point where it decides. The norm log writer is not a
-- second set of call sites: it is this function, applied to each step as it
-- is logged. A step that is only a /look/ (a party or action mismatch, a
-- failed guard, an early act, a norm still waiting when the events run out)
-- is not a fate and writes nothing (N1).
--
-- Two fates are not steps and are written elsewhere in "L4.EvaluateLazy.Machine":
-- 'Armed' ('armedEntry', where the machine arms a norm) and a declared
-- 'Breached' ('breachedEntry', each time a continuation reaches the @BREACH@,
-- N7 rule 1).
--
-- == Loud and silent
--
-- A step this module does not map is silent: nothing errors, and the norm
-- log is merely shorter than the run. @NormLogSpec@ pins every shape.
module L4.EvaluateLazy.Fates
  ( fatesOfStep
  , armedEntry
  , breachedEntry
  , normBearerOf
  , normRefOf
  ) where

import Control.Monad (mplus)
import L4.Evaluate.NormLog
import L4.Evaluate.ValueLazy (RBinOp (..))
import L4.EvaluateLazy.DeonticStep
import L4.Syntax (DeonticModal (..))

-- | The party a norm key knows, as far as the machine has forced it.
normBearerOf :: NormKey -> NormBearer
normBearerOf k = case (k.nkBearer, k.nkBearerSource) of
  (Just b, _)        -> KnownBearer b
  (Nothing, Just src) -> WrittenBearer src
  (Nothing, Nothing) -> UnknownBearer

normRefOf :: NormKey -> NormRef
normRefOf k = MkNormRef {nrSite = k.nkSite, nrActivation = k.nkActivation}

memberOfKey :: NormKey -> Maybe NormMember
memberOfKey k = fmap (\ m -> MkNormMember {nmJoinSite = m.moJoinSite, nmIndex = m.moIndex, nmTotal = m.moTotal}) k.nkMember

-- | An entry for a norm, with the fields every norm entry shares.
entryFor :: NormKey -> Fate -> Maybe Rational -> Maybe Rational -> NormEntry
entryFor k fate effective observed = MkNormEntry
  { neFate = fate
  , neNorm = Just (normRefOf k)
  , neModal = Just k.nkModal
  , neBearer = normBearerOf k
  , neAction = k.nkAction
  , neActionHead = k.nkActionHead
  , neEnclosing = k.nkEnclosing
  , neOrigin = k.nkOrigin
  , neMember = memberOfKey k
  , neEffective = effective
  , neObserved = observed
  }

-- | The entry written when a norm is armed: it has met its event stream and
-- nothing has happened to it. The clock is the arming instant, peeked by the
-- caller ('Nothing' while it is still a thunk).
--
-- A norm that a @HENCE@ or @LEST@ armed took effect at the hand-off's clock
-- and was seen on the event that revealed the hand-off, which for a @LEST@ is
-- later (N3, review of P1 W2): @handoff@ is that event's stamp. A root norm
-- has no hand-off, and is seen when it is armed.
armedEntry :: NormKey -> Maybe Rational -> Maybe Rational -> NormEntry
armedEntry k clock handoff = entryFor k FateArmed clock (handoff `mplus` clock)

-- | The entry for a declared @BREACH@ that a continuation has just reached.
-- It names no norm (a terminal is not an obligation); its bearer is whom
-- @BREACH BY@ named, or, for a bare @BREACH@ on a @LEST@ path, the party of the
-- obligation whose failure reached it (N7 rule 2); and its origin is the
-- hand-off that reached it, so a reader can find that failure by the parent
-- link.
breachedEntry :: Maybe NormOrigin -> NamedParty -> Maybe Rational -> Maybe Rational -> NormEntry
breachedEntry origin named effective observed = MkNormEntry
  { neFate = FateBreached
  , neNorm = Nothing
  , neModal = Nothing
  , neBearer = bearer
  , neAction = Nothing
  , neActionHead = Nothing
  , neEnclosing = []
  , neOrigin = origin
  , neMember = Nothing
  , neEffective = effective
  , neObserved = observed
  }
  where
    bearer = case named of
      PartyNamed (Just p) -> KnownBearer p
      PartyNamed Nothing  -> UnknownBearer
      NobodyNamed -> case origin of
        -- a bare BREACH on the LEST path of a failed norm takes that norm's
        -- party; on a HENCE path, or after a lapsed MAY (which is no
        -- failure), it names nobody
        Just o | o.noBranch == ViaLest, o.noParentModal /= DMay -> o.noParentBearer
        _ -> NobodyBearer

-- | The fates one logged step writes, if any.
fatesOfStep :: DeonticStep -> [NormEntry]
fatesOfStep s = case (s.dsNorm, s.dsOutcome) of
  (Nothing, Joined op note) -> joinedEntry op note
  (Nothing, _)              -> []
  (Just k, outcome)         -> case outcome of
    Matched br  -> matched k br
    Expired br deadline -> expired k br deadline
    JoinReleased -> [joinEntry k FateJoinReleased s.dsClock s.dsClock]
    -- the barrier was lost at its ONCE deadline and seen at the last
    -- completion, which is the step's clock
    JoinExpired _ deadline -> [joinEntry k FateJoinExpired (Just deadline) s.dsClock]
    JoinFailed {} -> [joinEntry k FateJoinFailed (s.dsEffective `mplus` s.dsClock) (s.dsObserved `mplus` s.dsClock)]
    -- a lapsed MAY member's FULFILLED carries no time: not built (spec 6.2, N1)
    JoinStalled  -> [joinEntry k FateJoinStalled s.dsClock s.dsClock]
    -- looks, and the steps that are not a norm's fate
    Waiting -> []
    PartyMismatch -> []
    ActionMismatch -> []
    GuardFailed -> []
    EarlyAct {} -> []
    Breached {} -> []
    Joined {} -> []
  where
    observed = (.ekStamp) <$> s.dsEvent

    -- the event's stamp is both when the act took effect and when it was seen
    matched k _ = case k.nkModal of
      DMust    -> [entryFor k FatePerformed observed observed]
      DDo      -> [entryFor k FatePerformed observed observed]
      DMay     -> [entryFor k FateExercised observed observed]
      DMustNot -> [entryFor k FateViolated observed observed]

    -- the miss took effect at the deadline (no earlier than the arming, which
    -- the step carries as 'dsEffective'), and was seen on the event that
    -- revealed it
    expired k br deadline =
      let effective = maybe (Just deadline) Just s.dsEffective
          fate = case k.nkModal of
            DMust    -> Just (failedFate k br)
            DDo      -> Just (failedFate k br)
            DMustNot -> Just FateKept
            DMay     -> Just FateLapsed
      in [entryFor k f effective observed | Just f <- [fate]]

    failedFate k br = FateFailed case br of
      ToBreach -> FailedToBreach
      _ | Just m <- k.nkMember, isBarrier m.moJoin -> FailedToJoin
        | otherwise -> FailedToLest

    -- a barrier's own entry names nobody: a join is not a party's norm
    -- (review of P1, W3d)
    joinEntry k fate lostAt seenAt = (entryFor k fate lostAt seenAt) {neBearer = NobodyBearer}

    -- a compound's own entry: its identity and parent link, and the two
    -- instants of the breach it reduced to (SEESAW rule 2). A fulfilled
    -- compound has none: FULFILLED carries no time (review of P1, W3a)
    joinedEntry op note =
      let jop = case op of { ValRAnd -> JoinAnd; ValROr -> JoinOr }
          mk fate = [MkNormEntry
            { neFate = fate, neNorm = note.jnRef, neModal = Nothing, neBearer = NobodyBearer
            , neAction = Nothing, neActionHead = Nothing, neEnclosing = note.jnEnclosing
            , neOrigin = note.jnOrigin, neMember = Nothing
            , neEffective = note.jnEffective, neObserved = note.jnObserved }]
      in case note.jnResult of
        JoinFulfilled  -> mk (FateJoinedFulfilled jop)
        JoinBreached _ -> mk (FateJoinedBreached jop)
        JoinPending    -> []
