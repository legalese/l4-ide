-- | The instance ledger's store over a SQL table (OPERATIONAL-LOWERING-SPEC
-- §3.7, WPO2): what the sqlite default and the Postgres adapter share.
--
-- The store is the two-function interface of "L4.Ledger.Store", and only
-- 'appendRow' has to be careful. It is one statement: insert the row as
-- @seq = n@ only if the instance's head is @n - 1@, with the primary key
-- @(deployment, instance, seq)@ as the backstop, so two appenders that both
-- saw head @n - 1@ cannot both land at @n@, and none can leave a gap. A row
-- that did not go in is @Left@ the head as it now is, and the ledger's step
-- re-runs from its read ("L4.Ledger.Append"). No lock is held while L4
-- evaluates: the evaluator runs between 'readRows' and 'appendRow'.
--
-- Each engine binds its own driver to a 'SqlSession' and carries its own
-- DDL; the statements, the row's columns and the retry live here, once.
--
-- How it fails, sorted by whether anyone hears:
--
-- * __Loud__: a row that does not decode, a history with a gap, a
--   statement the engine refuses, or a busy database that stays busy
--   through every retry, all throw 'LedgerStoreError'.
-- * __Quiet, by design__: a row that did not go in because another
--   appender won, or because its idempotency key is already in the
--   instance, is @Left@ the head. In the second case the head can be the
--   very @n - 1@ the caller named; the ledger's re-read then finds the key
--   and returns the original row, which is what a retry should read.
module Ledger.Store.Sql
  ( -- * Sessions
    SqlValue (..)
  , SqlFailure (..)
  , SqlSession (..)
  , LedgerStoreError (..)
    -- * The store
  , sqlStore
  , sqlInstances
  , retryTransient
    -- * The statements
  , tableName
  , columnNames
  , insertIfHeadSql
  , selectRowsSql
  , selectHeadSql
  , selectInstancesSql
    -- * The row's columns
  , rowValues
  , rowFromValues
  , encodeTime
  , decodeTime
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (Exception, throwIO)
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Read as Text.Read
import Data.Ratio (denominator, numerator, (%))

import L4.Ledger.Row
  ( InstanceKey (..)
  , Row (..)
  , RowEvent (..)
  , RowVerdict (..)
  , SeqNo
  , parseStamp
  , renderStamp
  )
import L4.Ledger.Store (LedgerStore (..))

-- | A value a statement takes or a row gives back. Three kinds are enough
-- for the ledger's columns, and every engine has all three.
data SqlValue
  = SqlText !Text
  | SqlInt !Int64
  | SqlNull
  deriving stock (Eq, Show)

-- | Why a statement did not run.
data SqlFailure
  = Transient !Text
    -- ^ the engine asks to be asked again: sqlite busy or locked, a
    -- Postgres serialization failure or deadlock
  | Fatal !Text
    -- ^ anything else
  deriving stock (Eq, Show)

-- | One engine's driver, reduced to what the store needs.
data SqlSession = MkSqlSession
  { execute :: Text -> [SqlValue] -> IO (Either SqlFailure Int64)
    -- ^ run a statement; the number of rows it changed
  , query   :: Text -> [SqlValue] -> IO (Either SqlFailure [[SqlValue]])
    -- ^ run a query; its rows
  }

-- | The store could not do what it was asked, and the ledger cannot go on
-- as if it had.
newtype LedgerStoreError = LedgerStoreError Text
  deriving stock (Show)

instance Exception LedgerStoreError

-- | The store over a session whose engine already has the table.
sqlStore :: SqlSession -> LedgerStore
sqlStore s = MkLedgerStore
  { readRows = \ k -> do
      rows <- retryTransient "read the rows" (s.query selectRowsSql (keyValues k))
      decoded <- either (throwIO . LedgerStoreError) pure (traverse rowFromValues rows)
      let seqs = map (.seqNo) decoded
      if seqs == [1 .. length decoded]
        then pure decoded
        else throwIO (LedgerStoreError ("the history of " <> describeKey k <> " is not gapless from 1: " <> Text.pack (show seqs)))
  , appendRow = \ k n row -> do
      changed <- retryTransient "append a row" (s.execute insertIfHeadSql (rowValues k n row <> keyValues k <> [SqlInt (fromIntegral (n - 1))]))
      case changed of
        1 -> pure (Right ())
        0 -> Left <$> headOf k
        other -> throwIO (LedgerStoreError ("one append changed " <> Text.pack (show other) <> " rows"))
  }
  where
    headOf k = retryTransient "read the head" (s.query selectHeadSql (keyValues k)) >>= \ case
      [[SqlInt h]] -> pure (fromIntegral h)
      other -> throwIO (LedgerStoreError ("the head of " <> describeKey k <> " read as " <> Text.pack (show other)))

-- | Run a statement, and while the engine says to ask again, ask again, a
-- few times with a growing pause, then give up loudly.
retryTransient :: Text -> IO (Either SqlFailure a) -> IO a
retryTransient what act = go (0 :: Int)
  where
    attempts = 8
    go n = act >>= \ case
      Right a -> pure a
      Left (Transient why)
        | n + 1 < attempts -> threadDelay (2000 * 2 ^ n) >> go (n + 1)
        | otherwise -> throwIO (LedgerStoreError ("could not " <> what <> " after " <> Text.pack (show attempts) <> " tries: " <> why))
      Left (Fatal why) -> throwIO (LedgerStoreError ("could not " <> what <> ": " <> why))

----------------------------------------------------------------------------
-- Statements
----------------------------------------------------------------------------

tableName :: Text
tableName = "ledger_rows"

-- | The columns, in the order 'rowValues' gives them.
columnNames :: [Text]
columnNames =
  [ "deployment", "instance", "seq"
  , "event_kind", "party", "action"
  , "at", "tx_time"
  , "verdict_kind", "verdict_detail"
  , "decided_against", "idempotency_key", "rule_version" ]

-- | Insert the row as @seq@ iff the head is the given one, and do nothing on
-- a key the table already holds: the primary key, or the instance's
-- idempotency key. Every value is cast to its column's type so that
-- Postgres need not infer one; sqlite reads the same casts as no-ops.
-- Parameters: 'rowValues', then the key, then the head.
insertIfHeadSql :: Text
insertIfHeadSql = Text.unlines
  [ "INSERT INTO " <> tableName <> " (" <> Text.intercalate ", " columnNames <> ")"
  , "SELECT " <> Text.intercalate ", " (zipWith cast columnTypes columnNames)
  , "WHERE (SELECT COALESCE(MAX(seq), 0) FROM " <> tableName <> " WHERE deployment = ? AND instance = ?) = ?"
  , "ON CONFLICT DO NOTHING" ]
  where
    cast ty _ = "CAST(? AS " <> ty <> ")"
    columnTypes = [ if c `elem` ["seq", "decided_against"] then "BIGINT" else "TEXT" | c <- columnNames ]

-- | The instance's rows, in seq order. Parameters: the key.
selectRowsSql :: Text
selectRowsSql = Text.unlines
  [ "SELECT " <> Text.intercalate ", " (drop 2 columnNames)
  , "FROM " <> tableName
  , "WHERE deployment = ? AND instance = ?"
  , "ORDER BY seq" ]

-- | The instance's head, 0 if it has no rows. Parameters: the key.
selectHeadSql :: Text
selectHeadSql = "SELECT COALESCE(MAX(seq), 0) FROM " <> tableName <> " WHERE deployment = ? AND instance = ?"

-- | The names of a deployment's instances, in order. Parameters: the
-- deployment.
selectInstancesSql :: Text
selectInstancesSql = "SELECT DISTINCT instance FROM " <> tableName <> " WHERE deployment = ? ORDER BY instance"

-- | The instances the table holds for a deployment.
--
-- This is not part of the store: 'LedgerStore' is the two functions an
-- append needs and nothing else (§3.7). It is what the service asks before
-- it deletes or overwrites a deployment (R-O5: a deployment with live
-- instances refuses a silent delete or overwrite), and a read like any
-- other, so it takes no lock and holds none.
sqlInstances :: SqlSession -> Text -> IO [Text]
sqlInstances s deployment =
  retryTransient "list the instances" (s.query selectInstancesSql [SqlText deployment]) >>=
    traverse \ case
      [SqlText name] -> pure name
      other -> throwIO (LedgerStoreError ("an instance name read as " <> showT other))

keyValues :: InstanceKey -> [SqlValue]
keyValues k = [SqlText k.deployment, SqlText k.instanceName]

describeKey :: InstanceKey -> Text
describeKey k = k.deployment <> "/" <> k.instanceName

----------------------------------------------------------------------------
-- The row's columns
----------------------------------------------------------------------------

-- | The row as the insert's values, stored at @seq = n@.
rowValues :: InstanceKey -> SeqNo -> Row -> [SqlValue]
rowValues k n r =
  keyValues k
    <> [SqlInt (fromIntegral n)]
    <> eventValues r.event
    <> [SqlText (encodeTime r.at), SqlText (encodeTime r.txTime)]
    <> verdictValues r.verdict
    <> [ maybe SqlNull (SqlInt . fromIntegral) r.decidedAgainst
       , maybe SqlNull SqlText r.idempotencyKey
       , SqlText r.ruleVersion ]
  where
    eventValues = \ case
      OpeningEvent c -> [SqlText "opening", SqlNull, SqlText c]
      ActEvent p a   -> [SqlText "act", SqlText p, SqlText a]
      TickEvent      -> [SqlText "tick", SqlNull, SqlNull]
    verdictValues = \ case
      VDischarging   -> [SqlText "discharging", SqlNull]
      VBreaching who -> [SqlText "breaching", maybe SqlNull SqlText who]
      VAdvancing     -> [SqlText "advancing", SqlNull]
      VPassedOver w  -> [SqlText "passed over", SqlText w]

-- | A row from 'selectRowsSql''s columns, or why it is not one.
rowFromValues :: [SqlValue] -> Either Text Row
rowFromValues vs = case vs of
  [SqlInt n, kind, party, action, SqlText at', SqlText tx, SqlText vKind, vDetail, decided, key, SqlText rv] -> do
    ev <- event kind party action
    atTime <- decodeTime at'
    txTime' <- decodeTime tx
    v <- verdict vKind vDetail
    decided' <- case decided of
      SqlNull -> Right Nothing
      SqlInt d -> Right (Just (fromIntegral d))
      other -> Left ("decided_against is " <> showT other)
    key' <- case key of
      SqlNull -> Right Nothing
      SqlText t -> Right (Just t)
      other -> Left ("idempotency_key is " <> showT other)
    Right MkRow
      { seqNo = fromIntegral n
      , event = ev
      , at = atTime
      , txTime = txTime'
      , verdict = v
      , decidedAgainst = decided'
      , idempotencyKey = key'
      , ruleVersion = rv
      }
  _ -> Left ("not a ledger row: " <> showT vs)
  where
    event (SqlText "opening") SqlNull (SqlText c) = Right (OpeningEvent c)
    event (SqlText "act") (SqlText p) (SqlText a) = Right (ActEvent p a)
    event (SqlText "tick") SqlNull SqlNull = Right TickEvent
    event k p a = Left ("not an event: " <> showT (k, p, a))
    verdict "discharging" SqlNull = Right VDischarging
    verdict "breaching" SqlNull = Right (VBreaching Nothing)
    verdict "breaching" (SqlText who) = Right (VBreaching (Just who))
    verdict "advancing" SqlNull = Right VAdvancing
    verdict "passed over" (SqlText why) = Right (VPassedOver why)
    verdict k d = Left ("not a verdict: " <> showT (k, d))

-- | A time as exact text: the decimal a @#TRACE@ line spells it with when
-- it has one, else @numerator/denominator@. Never a float, because a
-- stamp such as 0.1 has no binary form, and a replay that read back
-- another number would disagree with the ledger with no error.
encodeTime :: Rational -> Text
encodeTime r = case renderStamp r of
  Right t -> t
  Left _ -> showT (numerator r) <> "/" <> showT (denominator r)

decodeTime :: Text -> Either Text Rational
decodeTime t = case Text.splitOn "/" t of
  [n, d] -> do
    n' <- integer n
    d' <- integer d
    if d' > 0 then Right (n' % d') else Left ("not a time: " <> t)
  [_] -> parseStamp t
  _ -> Left ("not a time: " <> t)
  where
    integer s = case Text.Read.signed Text.Read.decimal s of
      Right (i, "") -> Right i
      _ -> Left ("not a time: " <> t)

showT :: Show a => a -> Text
showT = Text.pack . show
