-- | The instance ledger's operations (OPERATIONAL-LOWERING-SPEC §3.2-§3.4):
-- create an instance, propose an act to it ('appendIf'), let the clock
-- pass its deadlines ('appendDueTicks'), and ask what may be done now
-- ('positionOf').
--
-- An instance's step is a compare-and-append loop, not a held lock: read
-- the rows, evaluate with nothing locked, append at head plus one, and on a
-- lost race re-run from the read. Every act and every tick goes through it,
-- so the step recording Bob's purchase and the step accepting Alice's buy
-- share one serialization point, which is design D3 by construction.
--
-- What each 'Result' means, sorted as a caller meets them:
--
-- * __Loud__: 'Refused' (the proposal cannot be an event of this contract:
--   not of its action type, a party it does not know, a text that cannot
--   stand in a @#TRACE@ line, no idempotency key) and 'Conflict' (a strict
--   proposal whose versioned cell moved since the head it decided against).
--   Nothing is appended, and the caller is told.
-- * __Silent, if ignored__: 'Unknown' (the evaluator could not decide, or
--   the time bound passed). Nothing is appended either, but a proposer
--   that reads it as permission and acts anyway is design D1, unguarded.
-- * 'Appended' covers every act that evaluates, breaching and passed-over
--   ones included (R-O2): the verdict is on the row, and an act the rule
--   blocked is auditable because it is there.
module L4.Ledger.Append
  ( Ledger (..)
  , Instance (..)
  , instanceKey
  , Proposed (..)
  , Result (..)
  , createInstance
  , appendIf
  , appendDueTicks
  , LedgerPosition (..)
  , positionOf
  ) where

import Base
import qualified Base.Text as Text
import Data.Functor ((<&>))

import L4.EvaluateLazy (EvalConfig)
import L4.EvaluateLazy.DeonticStep (DeonticStep)
import L4.Ledger.Replay
import L4.Ledger.Row
import L4.Ledger.Store
import L4.Lts.List (TraceReport)
import L4.Lts.WhatIf (EnabledSet)

-- | The ledger: a store, the clock it stamps rows by, and the evaluator's
-- configuration and bounds.
data Ledger = MkLedger
  { store      :: !LedgerStore
  , clock      :: !(IO Rational)
    -- ^ the ledger clock, on the contract's time axis (§3.4); what one unit
    -- of it is, and where an instance's start sits against wall time, is
    -- D-O8 and not decided here
  , evalConfig :: !EvalConfig
  , timeBound  :: !Int
    -- ^ microseconds one evaluation may take before its answer is 'Unknown'
  , retryCap   :: !Int
    -- ^ how many lost compare-and-append races before 'Unknown'
  }

-- | One instance of a deployment.
data Instance = MkInstance
  { deploymentOf :: !Deployment
  , instanceId   :: !Text
  }

instanceKey :: Instance -> InstanceKey
instanceKey i = MkInstanceKey {deployment = i.deploymentOf.deploymentId, instanceName = i.instanceId}

-- | An act, proposed (§3.2).
data Proposed = MkProposed
  { party          :: !Text
  , action         :: !Text
    -- ^ L4 source of a value of the contract's action type
  , claimedAt      :: !(Maybe Rational)
    -- ^ when the party says the act happened in the world. Used only for an
    -- act whose step does not @COMMIT@ to the official record, clamped to
    -- @[previous row's at, txTime]@; an act that does @COMMIT@ is stamped
    -- @txTime@ whatever is claimed (R-O1)
  , decidedAgainst :: !(Maybe SeqNo)
    -- ^ the head the proposer decided against: provenance, and what a
    -- strict proposal is checked against
  , idempotencyKey :: !Text
  , strict         :: !Bool
  }
  deriving stock (Eq, Show)

data Result
  = Appended
      { row      :: !Row
      , steps    :: ![DeonticStep]
        -- ^ what the act caused, past the head; empty for a retry
      , wrote    :: ![Text]
        -- ^ the ledger entries the act's step appended, as @l4 run@ words
        -- them less the provenance stamp; empty for a retry
      , replayed :: !Bool
        -- ^ 'False' when the idempotency key was found: the row is the
        -- original, and nothing was replayed
      , ticks    :: ![Row]
        -- ^ ticks that were due and were appended first
      }
  | Refused  { because :: !Text, headSeq :: !SeqNo }
  | Conflict { because :: !Text, headSeq :: !SeqNo }
  | Unknown  { because :: !Text }
  | NotFound
    -- ^ the store does not hold the instance; never a fresh one (§3.2)
  deriving stock (Show)

-- | Create an instance: its opening, row 1, is the @#TRACE@ header naming
-- the contract expression, stamped with the ledger's clock. Refused if the
-- store already holds the instance, or if the contract expression is not
-- one the deployment can run.
createInstance :: Ledger -> Instance -> Text -> IO Result
createInstance l inst contract = do
  existing <- l.store.readRows key
  if not (null existing)
    then pure (Refused "the instance already exists" (length existing))
    else case canonicalExpr contract of
      Left why -> pure (Refused why 0)
      Right c -> do
        now <- l.clock
        let tx = nextTxTime Nothing now
            provisional = MkRow
              { seqNo = 1
              , event = OpeningEvent c
              , at = tx
              , txTime = tx
              , verdict = VAdvancing
              , decidedAgainst = Nothing
              , idempotencyKey = Nothing
              , ruleVersion = inst.deploymentOf.deploymentVersion
              }
        r <- replay l.evalConfig l.timeBound inst.deploymentOf [provisional] Nothing
        case r of
          Left (Malformed why) -> pure (Refused why 0)
          Left (Undecided why) -> pure (Unknown why)
          Right rep -> do
            let opening = withVerdict rep.headVerdict provisional
            appended <- l.store.appendRow key 1 opening
            pure case appended of
              Left current -> Refused "the instance already exists" current
              Right () -> Appended {row = opening, steps = rep.headSteps, wrote = rep.headLedger, replayed = True, ticks = []}
  where
    key = instanceKey inst

-- | Propose an act (§3.2). In order: the idempotency key is looked up, and
-- a hit returns the original row without replaying anything; the rows are
-- read; the clock is read, and any tick that is due is appended first; the
-- act is stamped (§3.4) and replayed as sent on the rows; a strict proposal
-- is held to its versioned cells; and the row is appended at head plus one,
-- the whole step re-run from the read if another appender won.
appendIf :: Ledger -> Instance -> Proposed -> IO Result
appendIf l inst p = attempt 0
  where
    dep = inst.deploymentOf
    key = instanceKey inst
    attempt :: Int -> IO Result
    attempt n
      | n > l.retryCap = pure (Unknown ("lost the race to append " <> Text.pack (show n) <> " times; nothing was appended"))
      | otherwise = l.store.readRows key >>= \ case
          [] -> pure NotFound
          rows -> case find (\ r -> r.idempotencyKey == Just p.idempotencyKey) rows of
            Just original -> pure Appended {row = original, steps = [], wrote = [], replayed = False, ticks = []}
            Nothing -> fresh n rows

    fresh n rows0
      | Text.null (Text.strip p.idempotencyKey) = pure (Refused "a proposal carries an idempotency key" (length rows0))
      | otherwise = case (,) <$> canonicalExpr p.party <*> canonicalExpr p.action of
          Left why -> pure (Refused why (length rows0))
          Right (party', action') -> do
            now <- l.clock
            due <- dueTicks l inst rows0 now
            case due of
              TicksLost -> attempt (n + 1)
              TicksFailed why -> pure (Unknown why)
              TicksDone rows ticks' -> propose n rows ticks' now (ActEvent party' action')

    propose n rows ticks' now ev = do
      let headNo = length rows
          prev = lastRow rows
          tx = nextTxTime (Just prev.txTime) now
      case spelled ev tx of
        Just why -> pure (Refused why headNo)
        Nothing -> replay l.evalConfig l.timeBound dep rows (Just (ev, tx)) >>= \ case
          Left (Malformed why) -> pure (Refused why headNo)
          Left (Undecided why) -> pure (Unknown why)
          Right rep1 -> case rep1.outcome of
            Nothing -> pure (Unknown "the replay returned no outcome for the act")
            Just o1 -> strictCheck rows rep1 >>= \ case
              Just stop -> pure stop
              Nothing -> do
                let committed = length o1.official > length rep1.headOfficial
                stamped <- case p.claimedAt of
                  Just claimed | not committed ->
                    let reported = clampReported prev.at tx claimed
                    in if reported == tx
                      then pure (Right (tx, o1))
                      else replay l.evalConfig l.timeBound dep rows (Just (ev, reported)) <&> \ case
                        Left f -> Left f
                        Right rep2 -> maybe (Left (Undecided "the replay returned no outcome for the act")) (Right . (reported,)) rep2.outcome
                  _ -> pure (Right (tx, o1))
                case stamped of
                  Left (Malformed why) -> pure (Refused why headNo)
                  Left (Undecided why) -> pure (Unknown why)
                  Right (atTime, o) -> do
                    let newRow = MkRow
                          { seqNo = headNo + 1
                          , event = ev
                          , at = atTime
                          , txTime = tx
                          , verdict = o.verdict
                          , decidedAgainst = p.decidedAgainst
                          , idempotencyKey = Just p.idempotencyKey
                          , ruleVersion = dep.deploymentVersion
                          }
                    l.store.appendRow key newRow.seqNo newRow >>= \ case
                      Left _ -> attempt (n + 1)
                      Right () -> pure Appended {row = newRow, steps = o.steps, wrote = o.wrote, replayed = True, ticks = ticks'}

    -- The act must read back from its own line as itself, or the line
    -- says something the proposal did not.
    spelled ev tx = case eventLine ev tx >>= parseEventLine of
      Right back | back == (ev, tx) -> Nothing
                 | otherwise -> Just "the act does not read back from its #TRACE line as itself"
      Left why -> Just why

    -- R-O4's opt-in (b): the per-cell version, the count of recorded
    -- entries of each versioned cell, must not have moved since the head
    -- the proposer decided against.
    strictCheck rows rep1
      | not p.strict = pure Nothing
      | otherwise = case p.decidedAgainst of
          Nothing -> pure (Just (Refused "a strict proposal names the head it decided against" headNo))
          Just seen
            | seen < 1 || seen > headNo -> pure (Just (Refused ("the head decided against, " <> showT seen <> ", is not one this instance has had") headNo))
            | seen == headNo -> pure Nothing
            | null dep.versionedCells -> pure (Just (Conflict ("the head moved from " <> showT seen <> " to " <> showT headNo) headNo))
            | otherwise -> replay l.evalConfig l.timeBound dep (take seen rows) Nothing <&> \ case
                Left f -> Just (Unknown ("the version at the head decided against could not be read: " <> failureText f))
                Right then' ->
                  let moved = [ (c, before, now')
                              | c <- dep.versionedCells
                              , let before = officialCount c then'.headOfficial
                                    now' = officialCount c rep1.headOfficial
                              , before /= now' ]
                  in case moved of
                    [] -> Nothing
                    _ -> Just (Conflict (Text.intercalate "; "
                           [ "the version of `" <> c <> "` moved from " <> showT b <> " to " <> showT a
                           | (c, b, a) <- moved ]) headNo)
      where headNo = length rows

-- | Append every tick that is due, oldest deadline first (§3.4, WPO1): read
-- the head's marking, and while the clock is past a deadline it can read,
-- append the tick past that deadline through the same compare-and-append
-- as any act. 'Left' is 'NotFound' or 'Unknown'.
appendDueTicks :: Ledger -> Instance -> IO (Either Result [Row])
appendDueTicks l inst = go (0 :: Int)
  where
    go n
      | n > l.retryCap = pure (Left (Unknown "lost the race to append a tick too many times"))
      | otherwise = l.store.readRows (instanceKey inst) >>= \ case
          [] -> pure (Left NotFound)
          rows -> do
            now <- l.clock
            dueTicks l inst rows now >>= \ case
              TicksLost -> go (n + 1)
              TicksFailed why -> pure (Left (Unknown why))
              TicksDone _ ts -> pure (Right ts)

data TickStep
  = TicksDone ![Row] ![Row]
    -- ^ the rows with the ticks appended, and the ticks
  | TicksLost
    -- ^ another appender won; re-read
  | TicksFailed !Text

-- | The tick loop over rows already read. Each tick is stamped just past
-- its deadline, as 'L4.Lts.WhatIf.tickPast' does (the machine expires on a
-- stamp strictly past the deadline), but never past the clock, and held to
-- 'L4.Lts.WhatIf.confirmTick': a tick that reveals no expiry is not
-- appended. Bounded, so a deadline that the tick does not consume cannot
-- loop.
dueTicks :: Ledger -> Instance -> [Row] -> Rational -> IO TickStep
dueTicks l inst rows0 now = go (16 :: Int) rows0 []
  where
    dep = inst.deploymentOf
    go 0 rows acc = pure (TicksDone rows (reverse acc))
    go k rows acc = replay l.evalConfig l.timeBound dep rows Nothing >>= \ case
      Left f -> pure (TicksFailed (failureText f))
      Right rep -> case [ dt | dt@(d, _) <- rep.headDeadlines, d < now ] of
        [] -> pure (TicksDone rows (reverse acc))
        ((_, past) : _) -> do
          let prev = lastRow rows
              stamp = max prev.at (min past now)
              tx = nextTxTime (Just prev.txTime) now
          replay l.evalConfig l.timeBound dep rows (Just (TickEvent, stamp)) >>= \ case
            Left f -> pure (TicksFailed ("the tick at " <> either id id (renderStamp stamp) <> " could not be appended: " <> failureText f))
            Right rep2 -> case rep2.outcome of
              Nothing -> pure (TicksFailed "the replay returned no outcome for the tick")
              Just o -> do
                let tickRow = MkRow
                      { seqNo = length rows + 1
                      , event = TickEvent
                      , at = stamp
                      , txTime = tx
                      , verdict = o.verdict
                      , decidedAgainst = Nothing
                      , idempotencyKey = Nothing
                      , ruleVersion = dep.deploymentVersion
                      }
                l.store.appendRow (instanceKey inst) tickRow.seqNo tickRow >>= \ case
                  Left _ -> pure TicksLost
                  Right () -> go (k - 1) (rows <> [tickRow]) (tickRow : acc)

-- | What may be done now (§3.3): advisory, stamped with the head it was
-- computed at.
data LedgerPosition = MkLedgerPosition
  { headSeq      :: !SeqNo
  , enabled      :: !EnabledSet
  , report       :: !TraceReport
    -- ^ the same position in the words @l4 lts@ prints ("L4.Lts.List")
  , nextDeadline :: !(Maybe Rational)
  , terminal     :: !Bool
  , ledgerAtHead :: ![Text]
  }

-- | The position query over the rows: the enabled set at the head, with the
-- next deadline the marking can read. 'Left' is 'NotFound' or 'Unknown'.
positionOf :: Ledger -> Instance -> IO (Either Result LedgerPosition)
positionOf l inst = l.store.readRows (instanceKey inst) >>= \ case
  [] -> pure (Left NotFound)
  rows -> do
    rep <- replay l.evalConfig l.timeBound inst.deploymentOf rows Nothing
    es <- positionAt l.evalConfig l.timeBound inst.deploymentOf rows
    pure case (rep, es) of
      (Left f, _) -> Left (Unknown (failureText f))
      (_, Left f) -> Left (Unknown (failureText f))
      (Right r, Right (e, rp)) -> Right MkLedgerPosition
        { headSeq = length rows
        , enabled = e
        , report = rp
        , nextDeadline = fst <$> listToMaybe r.headDeadlines
        , terminal = r.headTerminal
        , ledgerAtHead = r.headLedger
        }

lastRow :: [Row] -> Row
lastRow rows = case reverse rows of
  (r : _) -> r
  [] -> error "lastRow: an instance always holds its opening"

showT :: Show a => a -> Text
showT = Text.pack . show
