{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
module L4.TemporalContext
  ( TemporalContext (..)
  , EvalClause (..)
  , initialTemporalContext
  , applyEvalClauses
  -- * Context-read fingerprints (T6: thunk memoization vs temporal scopes)
  , ReadObs (..)
  , CtxReads (..)
  , noReads
  , hasReads
  , validFor
  )
where

import Base
import qualified Base.Text as Text
import Data.Time (Day, UTCTime (..), secondsToDiffTime)

-- | Multi-axis temporal context carried during evaluation.
-- Currently this is a lightweight container; evaluator wiring will
-- thread it through and update the fields as EVAL clauses are applied.
--
-- READER CONTRACT (T6): any code that lets an axis's value influence a
-- computed result MUST record the observation via the @readTc*@ helpers in
-- "L4.EvaluateLazy.Machine" (never raw @getTemporalContext@ + field access),
-- else stale memoized thunk values leak across temporal scopes (the T6 bug).
-- Raw @getTemporalContext@ is reserved for frame save\/restore plumbing.
-- When adding a reader for a currently-latent axis (e.g. 'tcValidTime'),
-- add the corresponding @crXxx@ field to 'CtxReads', an instrumented reader,
-- and flip the @temporal-under-valid-time-latent@ golden.
data TemporalContext = TemporalContext
  { tcValidTime :: !(Maybe Day)
    -- ^ LATENT axis: no reader exists yet. A future reader must be
    -- instrumented per the READER CONTRACT above.
  , tcSystemTime :: !UTCTime
    -- ^ Read by TODAY\/NOW\/CURRENTTIME. Value-affecting access must go
    -- through @readTcSystemTime@ (see READER CONTRACT).
  , tcRuleVersionTime :: !(Maybe Day)
    -- ^ LATENT axis: no reader exists yet (see READER CONTRACT).
  , tcRuleValidTime :: !(Maybe Day)
    -- ^ Read by RULES EFFECTIVE DATE. Value-affecting access must go
    -- through @readTcRuleValidTime@ (see READER CONTRACT). Stamped by
    -- EVAL UNDER RULES EFFECTIVE AT and the per-day interval iterators.
  , tcRuleEncodingTime :: !(Maybe UTCTime)
    -- ^ LATENT axis: no reader exists yet (see READER CONTRACT).
  , tcRuleCommit :: !(Maybe Text.Text)
    -- ^ LATENT axis: no reader exists yet (see READER CONTRACT).
  , tcDecisionTime :: !(Maybe UTCTime)
    -- ^ LATENT axis: no reader exists yet (see READER CONTRACT).
  , tcDocumentTimezone :: !(Maybe Text.Text)
    -- ^ IANA timezone name (e.g. "Asia/Singapore"). Read by
    -- TODAY\/NOW\/CURRENTTIME\/TIMEZONE\/TODATETIME and JSON DATETIME
    -- decoding. Value-affecting access must go through
    -- @readTcDocumentTimezone@ (see READER CONTRACT).
  }
  deriving stock (Eq, Show, Generic)

-- | Clauses supported by the runtime EVAL construct.
data EvalClause
  = UnderValidTime Day
  | AsOfSystemTime UTCTime
  | UnderRulesEffectiveAt Day
  | UnderRulesEncodedAt UTCTime
  deriving stock (Eq, Show, Generic)

-- | Seed an initial temporal context using the wall-clock time for
-- system/decision defaults. Other axes start unset so callers can opt in.
initialTemporalContext :: UTCTime -> TemporalContext
initialTemporalContext now =
  TemporalContext
    { tcValidTime = Nothing
    , tcSystemTime = now
    , tcRuleVersionTime = Nothing
    , tcRuleValidTime = Nothing
    , tcRuleEncodingTime = Nothing
    , tcRuleCommit = Nothing
    , tcDecisionTime = Just now
    , tcDocumentTimezone = Nothing
    }

-- | Apply a list of clauses to a context, left-to-right.
-- This is pure so it can be reused by different evaluator frontends.
applyEvalClauses :: [EvalClause] -> TemporalContext -> TemporalContext
applyEvalClauses clauses ctx0 =
  foldl' applyClause ctx0 clauses
  where
    applyClause ctx = \case
      UnderValidTime d ->
        ctx { tcValidTime = Just d }
      AsOfSystemTime t ->
        ctx { tcSystemTime = t }
      UnderRulesEffectiveAt d ->
        ctx
          { tcRuleValidTime = Just d
          , tcRuleVersionTime = Just d
          , tcRuleEncodingTime =
              case ctx.tcRuleEncodingTime of
                Just t -> Just t
                Nothing -> Just (coerceDay d)
          }
        where
          -- default encoding snapshot to the target day when unspecified
          coerceDay day = UTCTime day (secondsToDiffTime 0)
      UnderRulesEncodedAt t ->
        ctx { tcRuleEncodingTime = Just t }

-- ----------------------------------------------------------------------------
-- Context-read fingerprints (T6)
--
-- A lazy thunk whose force transitively READS the temporal context must not
-- be served from cache under a different context. We record, per force, an
-- observation for each readable axis; the cached value is tagged with these
-- observations and served only while every observed axis still has the
-- observed value. Axes that were never read ('NotRead') do not constrain
-- reuse — in particular the WHEN LAST / WHEN NEXT / EVER / ALWAYS per-day
-- iterator frames override only latent (unread) axes, so iteration days
-- share caches freely.
-- ----------------------------------------------------------------------------

-- | Observation of one temporal-context axis over the extent of one force.
data ReadObs a
  = NotRead        -- ^ the axis never influenced the result
  | ReadEq !a      -- ^ every read of the axis saw this value
  | ReadMixed      -- ^ reads disagreed (e.g. an internal override); never reusable
  deriving stock (Eq, Show)

instance Eq a => Semigroup (ReadObs a) where
  NotRead <> r = r
  l <> NotRead = l
  ReadMixed <> _ = ReadMixed
  _ <> ReadMixed = ReadMixed
  ReadEq a <> ReadEq b
    | a == b = ReadEq a
    | otherwise = ReadMixed

instance Eq a => Monoid (ReadObs a) where
  mempty = NotRead

-- | The per-force read fingerprint. Only axes with observable readers today
-- are tracked; latent axes (see 'TemporalContext') get a field here when a
-- reader ships.
data CtxReads = MkCtxReads
  { crSystemTime :: !(ReadObs UTCTime)
    -- ^ observations of 'tcSystemTime'
  , crDocumentTimezone :: !(ReadObs (Maybe Text.Text))
    -- ^ observations of 'tcDocumentTimezone' (recorded pre-defaulting:
    -- a NOW under a missing TIMEZONE records @ReadEq Nothing@)
  , crValidTime :: !(ReadObs (Maybe Day))
    -- ^ observations of 'tcValidTime' (the fact/valid-time axis). Read by
    -- RULES EFFECTIVE DATE as its first fallback when the rule-version axis
    -- is unset (option (b): law-time tracks fact-time). Recorded raw.
  , crRuleValidTime :: !(ReadObs (Maybe Day))
    -- ^ observations of 'tcRuleValidTime' (recorded pre-fallback: a
    -- RULES EFFECTIVE DATE under an unset axis records @ReadEq Nothing@
    -- and additionally records the fact-time read and the
    -- system-time/timezone reads its fallback chain performs)
  , crLedgerWrite :: !Bool
    -- ^ STATE-AS-LEDGER write-poison bit: did the force APPEND to the ledger
    -- (a RECORD\/COMMIT\/ATTEST\/NOTIFY)? A re-force would append the write
    -- AGAIN (a double-write visible to @RECALL ALL@\/provenance), so a force
    -- with this bit is cached as a plain 'WHNF' (snapshot at first force:
    -- the write fires exactly once, every later use shares the first-force
    -- value), never as a 'WHNFWhen'. See the cache-install decision in the
    -- @UpdateThunk@ arm of 'L4.EvaluateLazy.Machine.backward'.
  , crLedgerRead :: !Bool
    -- ^ STATE-AS-LEDGER read marker: did the force READ the ledger (a
    -- RECALL)? Unlike a write, re-forcing a pure read is harmless — and
    -- since smucclaw\/l4-ide#914 a RECALL's result DEPENDS on the ambient
    -- temporal axes (recorded into this same fingerprint by @finishRead@),
    -- so a read-only ledger force is cached as a 'WHNFWhen' keyed on those
    -- axes: SNAPSHOT PER TEMPORAL SCOPE. Under an unchanged context the
    -- first-force value is re-served (the fingerprint deliberately does NOT
    -- track the ledger, so later writes stay invisible to the shared thunk
    -- — the pre-bitemporal per-directive snapshot, restricted per scope);
    -- under a different context the thunk re-forces against the CURRENT
    -- ledger, giving each scope its own snapshot. This bit does not veto
    -- 'validFor'; it exists so read-ness propagates through the Semigroup
    -- and future work can key on it (e.g. a ledger version in the
    -- fingerprint).
  }
  deriving stock (Eq, Show)

instance Semigroup CtxReads where
  MkCtxReads a b v rv w r <> MkCtxReads a' b' v' rv' w' r' =
    MkCtxReads (a <> a') (b <> b') (v <> v') (rv <> rv') (w || w') (r || r')

instance Monoid CtxReads where
  mempty = noReads

-- | The empty fingerprint: no axis was read.
noReads :: CtxReads
noReads = MkCtxReads NotRead NotRead NotRead NotRead False False

-- | Did this force observe the temporal context at all?
hasReads :: CtxReads -> Bool
hasReads r = r /= noReads

-- | Is a cached value tagged with these observations still valid under the
-- given context? 'NotRead' axes are ignored; a 'ReadEq' axis must match the
-- current value exactly; 'ReadMixed' never validates. Soundness: if every
-- recorded read reproduces under the current context, re-forcing would
-- deterministically replay to the identical value.
--
-- A fingerprint carrying 'crLedgerWrite' never validates: re-forcing such a
-- force is NOT a deterministic replay (it would re-append the write). The
-- evaluator never installs such a cache in the first place (it installs a
-- plain WHNF instead); this arm is defensive. 'crLedgerRead' deliberately
-- does NOT veto: a read-only ledger force is valid exactly while its
-- recorded temporal axes match (snapshot per temporal scope — see the field
-- doc on 'crLedgerRead').
validFor :: TemporalContext -> CtxReads -> Bool
validFor tc r =
  not r.crLedgerWrite
    && axisValid tc.tcSystemTime r.crSystemTime
    && axisValid tc.tcDocumentTimezone r.crDocumentTimezone
    && axisValid tc.tcValidTime r.crValidTime
    && axisValid tc.tcRuleValidTime r.crRuleValidTime
  where
    axisValid :: Eq a => a -> ReadObs a -> Bool
    axisValid _   NotRead    = True
    axisValid cur (ReadEq v) = v == cur
    axisValid _   ReadMixed  = False
