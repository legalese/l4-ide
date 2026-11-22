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
  , neOrigin = k.nkOrigin
  , neMember = memberOfKey k
  , neEffective = effective
  , neObserved = observed
  }

-- | The entry written when a norm is armed: it has met its event stream and
-- nothing has happened to it. The clock is the arming instant, peeked by the
-- caller ('Nothing' while it is still a thunk).
armedEntry :: NormKey -> Maybe Rational -> NormEntry
armedEntry k clock = entryFor k FateArmed clock clock

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
    JoinReleased -> [joinEntry k FateJoinReleased]
    JoinExpired {} -> [joinEntry k FateJoinExpired]
    JoinFailed {} -> [joinEntry k FateJoinFailed]
    JoinStalled  -> [joinEntry k FateJoinStalled]
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

    joinEntry k fate = entryFor k fate s.dsClock s.dsClock

    joinedEntry op note =
      let jop = case op of { ValRAnd -> JoinAnd; ValROr -> JoinOr }
          mk fate = [MkNormEntry
            { neFate = fate, neNorm = Nothing, neModal = Nothing, neBearer = NobodyBearer
            , neAction = Nothing, neOrigin = Nothing, neMember = Nothing
            , neEffective = s.dsClock, neObserved = s.dsClock }]
      in case note.jnResult of
        JoinFulfilled  -> mk (FateJoinedFulfilled jop)
        JoinBreached _ -> mk (FateJoinedBreached jop)
        JoinPending    -> []
