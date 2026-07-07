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
    -- ^ LATENT axis: no reader exists yet (see READER CONTRACT).
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
  }
  deriving stock (Eq, Show)

instance Semigroup CtxReads where
  MkCtxReads a b <> MkCtxReads a' b' = MkCtxReads (a <> a') (b <> b')

instance Monoid CtxReads where
  mempty = noReads

-- | The empty fingerprint: no axis was read.
noReads :: CtxReads
noReads = MkCtxReads NotRead NotRead

-- | Did this force observe the temporal context at all?
hasReads :: CtxReads -> Bool
hasReads r = r /= noReads

-- | Is a cached value tagged with these observations still valid under the
-- given context? 'NotRead' axes are ignored; a 'ReadEq' axis must match the
-- current value exactly; 'ReadMixed' never validates. Soundness: if every
-- recorded read reproduces under the current context, re-forcing would
-- deterministically replay to the identical value.
validFor :: TemporalContext -> CtxReads -> Bool
validFor tc r =
  axisValid tc.tcSystemTime r.crSystemTime
    && axisValid tc.tcDocumentTimezone r.crDocumentTimezone
  where
    axisValid :: Eq a => a -> ReadObs a -> Bool
    axisValid _   NotRead    = True
    axisValid cur (ReadEq v) = v == cur
    axisValid _   ReadMixed  = False
