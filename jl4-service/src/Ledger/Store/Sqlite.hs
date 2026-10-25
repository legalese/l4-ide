-- | The instance ledger's default store (OPERATIONAL-LOWERING-SPEC §3.7,
-- R-O5): one sqlite file, @ledger.sqlite3@, under the service's store
-- path, beside the deployment directories.
--
-- The file cannot collide with a deployment: a deployment id has no dot
-- ('ControlPlane.deploymentIdError'), 'BundleStore.listDeployments' lists
-- only directories holding a @metadata.json@, and
-- 'BundleStore.cleanupStore' sweeps only @*.tmp@.
--
-- Single process only. sqlite's own locking keeps two connections from
-- interleaving a compare-and-append, but the file must not sit on a network
-- filesystem, where that locking is not to be trusted, and a hosted service
-- that runs several processes configures Postgres (R-O5, D-O12).
module Ledger.Store.Sqlite
  ( ledgerFileName
  , sqliteDdl
  , openSqliteSession
  , openSqliteStore
  ) where

import Control.Concurrent.MVar (newMVar, withMVar, modifyMVar_)
import Control.Exception (Handler (..), catches)
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Database.SQLite.Simple as SQLite
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))

import L4.Ledger.Store (LedgerStore)
import Ledger.Store.Sql

-- | The file's name under the store path.
ledgerFileName :: FilePath
ledgerFileName = "ledger.sqlite3"

-- | sqlite's own DDL. The times are TEXT holding an exact number
-- ('encodeTime'); NUMERIC would give them numeric affinity and store 0.1
-- as a float. The CHECKs make a row that names no event, or the wrong
-- columns for its event, a loud refusal rather than a row that cannot be
-- read back.
sqliteDdl :: [Text]
sqliteDdl =
  [ Text.unlines
      [ "CREATE TABLE IF NOT EXISTS " <> tableName <> " ("
      , "  deployment      TEXT    NOT NULL,"
      , "  instance        TEXT    NOT NULL,"
      , "  seq             INTEGER NOT NULL CHECK (seq >= 1),"
      , "  event_kind      TEXT    NOT NULL CHECK (event_kind IN ('opening', 'act', 'tick')),"
      , "  party           TEXT,"
      , "  action          TEXT,"
      , "  at              TEXT    NOT NULL,"
      , "  tx_time         TEXT    NOT NULL,"
      , "  verdict_kind    TEXT    NOT NULL CHECK (verdict_kind IN ('discharging', 'breaching', 'advancing', 'passed over')),"
      , "  verdict_detail  TEXT,"
      , "  decided_against INTEGER,"
      , "  idempotency_key TEXT,"
      , "  rule_version    TEXT    NOT NULL,"
      , "  PRIMARY KEY (deployment, instance, seq),"
      , "  UNIQUE (deployment, instance, idempotency_key),"
      , "  CHECK ((event_kind = 'act'     AND party IS NOT NULL AND action IS NOT NULL)"
      , "      OR (event_kind = 'opening' AND party IS NULL     AND action IS NOT NULL)"
      , "      OR (event_kind = 'tick'    AND party IS NULL     AND action IS NULL))"
      , ")" ]
  ]

-- | The store in the given directory (the service's store path), created
-- with its table if absent, and how to close it.
openSqliteStore :: FilePath -> IO (LedgerStore, IO ())
openSqliteStore dir = do
  createDirectoryIfMissing True dir
  (session, close) <- openSqliteSession sqliteDdl (dir </> ledgerFileName)
  pure (sqlStore session, close)

-- | A session on one connection to a sqlite file, with the given DDL run
-- first. The connection is used by one statement at a time, so a
-- statement's change count is its own. A second session on the same file
-- waits for the first's write to finish (@busy_timeout@) rather than
-- failing, and if it still cannot write the statement is 'Transient'.
openSqliteSession :: [Text] -> FilePath -> IO (SqlSession, IO ())
openSqliteSession ddl file = do
  conn <- SQLite.open file
  SQLite.execute_ conn "PRAGMA busy_timeout = 5000"
  SQLite.execute_ conn "PRAGMA synchronous = FULL"
  mapM_ (\ statement -> retryTransient "create the ledger table" (classified (SQLite.execute_ conn (SQLite.Query statement)))) ddl
  lock <- newMVar (Just conn)
  let using :: (SQLite.Connection -> IO a) -> IO (Either SqlFailure a)
      using act = withMVar lock \ case
        Nothing -> pure (Left (Fatal "the ledger store is closed"))
        Just c -> classified (act c)
  pure
    ( MkSqlSession
        { execute = \ q ps -> using \ c -> do
            SQLite.execute c (SQLite.Query q) (map toData ps)
            fromIntegral <$> SQLite.changes c
        , query = \ q ps -> using (\ c -> SQLite.query c (SQLite.Query q) (map toData ps)) >>= \ case
            Left f -> pure (Left f)
            Right rows -> pure (traverse (traverse fromData) rows)
        }
    , modifyMVar_ lock \ case
        Nothing -> pure Nothing
        Just c -> SQLite.close c >> pure Nothing
    )

toData :: SqlValue -> SQLite.SQLData
toData = \ case
  SqlText t -> SQLite.SQLText t
  SqlInt i -> SQLite.SQLInteger (i :: Int64)
  SqlNull -> SQLite.SQLNull

fromData :: SQLite.SQLData -> Either SqlFailure SqlValue
fromData = \ case
  SQLite.SQLText t -> Right (SqlText t)
  SQLite.SQLInteger i -> Right (SqlInt i)
  SQLite.SQLNull -> Right SqlNull
  other -> Left (Fatal ("a ledger column held " <> Text.pack (show other)))

-- | sqlite's busy and locked are worth asking again; any other error from
-- the driver is not. Exceptions that are not the driver's, a timeout or a
-- kill aimed at the thread among them, go on up untouched.
classified :: IO a -> IO (Either SqlFailure a)
classified act = (Right <$> act) `catches`
  [ Handler \ (SQLite.SQLError code details context) -> pure
      if code `elem` [SQLite.ErrorBusy, SQLite.ErrorLocked]
        then Left (Transient (Text.pack (show code) <> ": " <> details))
        else Left (Fatal (Text.pack (show code) <> " in " <> context <> ": " <> details))
  , Handler \ (e :: SQLite.FormatError) -> pure (Left (Fatal (Text.pack (show e))))
  , Handler \ (e :: SQLite.ResultError) -> pure (Left (Fatal (Text.pack (show e))))
  ]
