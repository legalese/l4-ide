{-# LANGUAGE CPP #-}
-- | The instance ledger's Postgres store (OPERATIONAL-LOWERING-SPEC §3.7,
-- R-O5): the store for a service that runs as more than one process, as
-- the hosted one does (D-O12).
--
-- The statements are "Ledger.Store.Sql"'s, the same ones the sqlite
-- default runs: an insert that goes in only at head plus one, with
-- @PRIMARY KEY (deployment, instance, seq)@ as the backstop. Under
-- Postgres's default isolation two transactions can both read head
-- @n - 1@; the second insert at @n@ should then wait on the first's key
-- and, once it commits, do nothing, and so be @Left@ the new head. That is
-- reasoned from how Postgres documents @ON CONFLICT DO NOTHING@, not run.
--
-- The driver is built only with the cabal flag @postgres@ (see
-- @jl4-service.cabal@ for why), and without it 'openPostgresStore' says
-- so. The DDL and the error classification here are compiled either way.
--
-- What has and has not been run, as of the commit that added this module:
-- no Postgres server was available, so this adapter's DDL and statements
-- have run only on sqlite standing in for a server, and its driver, built
-- with the flag, has been run only against a port with no server, where
-- opening the store is a 'Left' (a refused connection is libpq's
-- 'IOException', which the first such run found escaping). It has never
-- reached a server. One connection, no pool, no reconnect: a lost
-- connection is a loud 'LedgerStoreError' on every call after it.
module Ledger.Store.Postgres
  ( postgresDdl
  , classifySqlState
  , postgresBuilt
  , openPostgresStore
  ) where

import Data.Text (Text)
import qualified Data.Text as Text

import L4.Ledger.Store (LedgerStore)
import Ledger.Store.Sql

#ifdef LEDGER_POSTGRES
import Control.Exception (Handler (..), IOException, catches, try)
import Control.Concurrent.MVar (newMVar, withMVar, modifyMVar_)
import qualified Data.Text.Encoding as Text.Encoding
import qualified Database.PostgreSQL.Simple as PG
import qualified Database.PostgreSQL.Simple.FromField as PG.FromField
import qualified Database.PostgreSQL.Simple.ToField as PG.ToField
import qualified Database.PostgreSQL.Simple.TypeInfo.Static as PG.Types
import qualified Database.PostgreSQL.Simple.Types as PG.Values
#endif

-- | Postgres's own DDL: the sqlite table with Postgres's integer type.
-- The times are TEXT, an exact number each ('encodeTime'), for the same
-- reason as there.
postgresDdl :: [Text]
postgresDdl =
  [ Text.unlines
      [ "CREATE TABLE IF NOT EXISTS " <> tableName <> " ("
      , "  deployment      TEXT   NOT NULL,"
      , "  instance        TEXT   NOT NULL,"
      , "  seq             BIGINT NOT NULL CHECK (seq >= 1),"
      , "  event_kind      TEXT   NOT NULL CHECK (event_kind IN ('opening', 'act', 'tick')),"
      , "  party           TEXT,"
      , "  action          TEXT,"
      , "  at              TEXT   NOT NULL,"
      , "  tx_time         TEXT   NOT NULL,"
      , "  verdict_kind    TEXT   NOT NULL CHECK (verdict_kind IN ('discharging', 'breaching', 'advancing', 'passed over')),"
      , "  verdict_detail  TEXT,"
      , "  decided_against BIGINT,"
      , "  idempotency_key TEXT,"
      , "  rule_version    TEXT   NOT NULL,"
      , "  PRIMARY KEY (deployment, instance, seq),"
      , "  UNIQUE (deployment, instance, idempotency_key),"
      , "  CHECK ((event_kind = 'act'     AND party IS NOT NULL AND action IS NOT NULL)"
      , "      OR (event_kind = 'opening' AND party IS NULL     AND action IS NOT NULL)"
      , "      OR (event_kind = 'tick'    AND party IS NULL     AND action IS NULL))"
      , ")" ]
  ]

-- | Which SQLSTATEs are worth asking again: a serialization failure, a
-- deadlock, a lock not available. A unique violation is not here because
-- the insert says @ON CONFLICT DO NOTHING@; a lost connection is not,
-- because asking again on it cannot help.
classifySqlState :: Text -> Text -> SqlFailure
classifySqlState state message
  | state `elem` ["40001", "40P01", "55P03"] = Transient (state <> ": " <> message)
  | otherwise = Fatal (state <> ": " <> message)

-- | Whether this binary has the driver.
postgresBuilt :: Bool
#ifdef LEDGER_POSTGRES
postgresBuilt = True
#else
postgresBuilt = False
#endif

-- | Connect, create the table if absent, and give the store, the
-- deployment's instances ('sqlInstances') and how to close it; or say why
-- not.
openPostgresStore :: Text -> IO (Either Text (LedgerStore, Text -> IO [Text], IO ()))
#ifdef LEDGER_POSTGRES
openPostgresStore url = classified (PG.connectPostgreSQL (Text.Encoding.encodeUtf8 url)) >>= \ case
  Left f -> pure (Left ("could not connect to the ledger's Postgres: " <> failureText f))
  Right conn -> do
    setup <- try (prepare conn)
    case setup of
      Left (LedgerStoreError why) -> PG.close conn >> pure (Left why)
      Right opened -> pure (Right opened)
  where
    pgQuery = PG.Values.Query . Text.Encoding.encodeUtf8
    failureText = \ case
      Transient t -> t
      Fatal t -> t
    prepare conn = do
      lock <- newMVar (Just conn)
      let using :: (PG.Connection -> IO a) -> IO (Either SqlFailure a)
          using act = withMVar lock \ case
            Nothing -> pure (Left (Fatal "the ledger store is closed"))
            Just c -> classified (act c)
          session = MkSqlSession
            { execute = \ q ps -> using \ c -> PG.execute c (pgQuery q) (map PgValue ps)
            , query = \ q ps -> using \ c -> map (map (\ (PgValue v) -> v)) <$> PG.query c (pgQuery q) (map PgValue ps)
            }
      mapM_ (\ statement -> retryTransient "create the ledger table" (session.execute statement [])) postgresDdl
      pure
        ( sqlStore session
        , sqlInstances session
        , modifyMVar_ lock \ case
            Nothing -> pure Nothing
            Just c -> PG.close c >> pure Nothing
        )

newtype PgValue = PgValue SqlValue

instance PG.ToField.ToField PgValue where
  toField (PgValue v) = case v of
    SqlText t -> PG.ToField.toField t
    SqlInt i -> PG.ToField.toField i
    SqlNull -> PG.ToField.toField PG.Values.Null

instance PG.FromField.FromField PgValue where
  fromField f mdata = case mdata of
    Nothing -> pure (PgValue SqlNull)
    Just _
      | PG.FromField.typeOid f `elem` [PG.Types.int2Oid, PG.Types.int4Oid, PG.Types.int8Oid] -> PgValue . SqlInt <$> PG.FromField.fromField f mdata
      | otherwise -> PgValue . SqlText <$> PG.FromField.fromField f mdata

classified :: IO a -> IO (Either SqlFailure a)
classified act = (Right <$> act) `catches`
  [ Handler \ (e :: PG.SqlError) -> pure (Left (classifySqlState (decode e.sqlState) (decode e.sqlErrorMsg)))
  , Handler \ (e :: PG.FormatError) -> pure (Left (Fatal (Text.pack (show e))))
  , Handler \ (e :: PG.QueryError) -> pure (Left (Fatal (Text.pack (show e))))
  , Handler \ (e :: PG.ResultError) -> pure (Left (Fatal (Text.pack (show e))))
    -- libpq's own failures, a refused connection among them (measured: no
    -- server on the port is an IOException, not an SqlError)
  , Handler \ (e :: IOException) -> pure (Left (Fatal (Text.strip (Text.pack (show e)))))
  ]
  where
    decode = Text.Encoding.decodeUtf8Lenient
#else
openPostgresStore _ = pure (Left notBuilt)

notBuilt :: Text
notBuilt = "this jl4-service was built without the Postgres adapter of the ledger store; rebuild it with the cabal flag postgres (cabal build -f postgres jl4-service), which needs libpq"
#endif
