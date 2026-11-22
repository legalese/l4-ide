-- | Which store the instance ledger uses, by configuration
-- (OPERATIONAL-LOWERING-SPEC §3.7, R-O5, card O3).
--
-- * @sqlite@, the default: one file under the service's store path.
--   Durable across restarts, single process.
-- * @postgres@, with a connection string: for more than one process. The
--   binary must have been built with the cabal flag @postgres@.
-- * @memory@: for tests only, and refused unless the test flag
--   @--ledger-allow-nondurable@ is given too. It loses every instance on
--   restart while deployments reload from disk, so a refused act could be
--   accepted and a retried key appended twice; 'nonDurable' carries the
--   sentence every reply from it must carry.
--
-- Redis, Zookeeper and etcd are admitted by the store's interface and not
-- built: Meng's note on card O3 reads "I think we’re requiring SQLite or
-- Postgres." Naming one is refused at startup, saying so.
module Ledger.Store.Config
  ( StoreChoice (..)
  , parseStoreChoice
  , LedgerStoreConfig (..)
  , defaultLedgerStoreConfig
  , ResolvedStore (..)
  , resolveStoreConfig
  , describeResolved
  , OpenedStore (..)
  , openLedgerStore
  , nonDurableWarning
  ) where

import Data.Char (toLower)
import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import System.FilePath ((</>))

import L4.Ledger.Row (InstanceKey (..))
import L4.Ledger.Store (LedgerStore (..), newMemoryStore)
import Ledger.Store.Postgres (openPostgresStore, postgresBuilt)
import Ledger.Store.Sqlite (ledgerFileName, openSqliteLedger)

data StoreChoice
  = ChooseSqlite
  | ChoosePostgres
  | ChooseMemory
  deriving stock (Eq, Show)

-- | The value of @--ledger-store@.
parseStoreChoice :: String -> Either String StoreChoice
parseStoreChoice s = case map toLower s of
  "sqlite" -> Right ChooseSqlite
  "postgres" -> Right ChoosePostgres
  "postgresql" -> Right ChoosePostgres
  "memory" -> Right ChooseMemory
  other
    | other `elem` ["redis", "zookeeper", "etcd"] ->
        Left (other <> " is admitted by the ledger store's interface but not built: card O3 requires sqlite or Postgres (OPERATIONAL-LOWERING-SPEC §3.7)")
    | otherwise -> Left ("unknown ledger store " <> show s <> "; expected sqlite, postgres or memory")

-- | What the operator said.
data LedgerStoreConfig = MkLedgerStoreConfig
  { choice          :: !StoreChoice
  , postgresUrl     :: !(Maybe Text)
  , allowNonDurable :: !Bool
    -- ^ the test flag the in-memory store is behind
  }
  deriving stock (Eq, Show)

defaultLedgerStoreConfig :: LedgerStoreConfig
defaultLedgerStoreConfig = MkLedgerStoreConfig {choice = ChooseSqlite, postgresUrl = Nothing, allowNonDurable = False}

-- | What will be opened.
data ResolvedStore
  = SqliteAt !FilePath
    -- ^ the directory; the file is 'ledgerFileName' in it
  | PostgresAt !Text
  | MemoryForTests
  deriving stock (Eq, Show)

-- | Check what the operator said against the store path and against this
-- binary, before anything is opened.
resolveStoreConfig :: FilePath -> LedgerStoreConfig -> Either Text ResolvedStore
resolveStoreConfig storePath c = case c.choice of
  ChooseSqlite -> Right (SqliteAt storePath)
  ChoosePostgres
    | not postgresBuilt -> Left "--ledger-store postgres: this jl4-service was built without the Postgres adapter; rebuild it with the cabal flag postgres (cabal build -f postgres jl4-service), which needs libpq"
    | otherwise -> case c.postgresUrl of
        Just url | not (Text.null (Text.strip url)) -> Right (PostgresAt url)
        _ -> Left "--ledger-store postgres needs a connection string (--ledger-postgres-url or JL4_LEDGER_POSTGRES_URL)"
  ChooseMemory
    | c.allowNonDurable -> Right MemoryForTests
    | otherwise -> Left "--ledger-store memory is for tests only, and needs --ledger-allow-nondurable (JL4_LEDGER_ALLOW_NONDURABLE=true): it loses every instance on restart while deployments reload"

-- | A line for the log. A Postgres connection string can carry a password,
-- so it is not repeated.
describeResolved :: ResolvedStore -> Text
describeResolved = \ case
  SqliteAt dir -> "sqlite at " <> Text.pack (dir </> ledgerFileName)
  PostgresAt _ -> "postgres"
  MemoryForTests -> "memory (tests only; not durable)"

-- | An open store, and what a reply from the ledger must say about it.
data OpenedStore = MkOpenedStore
  { store       :: !LedgerStore
  , backend     :: !Text
  , nonDurable  :: !(Maybe Text)
    -- ^ 'Just' the sentence every reply from this store carries; 'Nothing'
    -- for a durable store
  , instancesOf :: !(Text -> IO [Text])
    -- ^ the names of the instances the store holds for a deployment. Not a
    -- third operation of the store: an append never asks it. The service
    -- asks it before deleting or overwriting a deployment (R-O5)
  , close       :: !(IO ())
  }

-- | The sentence the in-memory store's replies carry.
nonDurableWarning :: Text
nonDurableWarning = "This ledger store is in memory and is not durable: every instance is lost when the service restarts. It is for tests only."

openLedgerStore :: ResolvedStore -> IO (Either Text OpenedStore)
openLedgerStore = \ case
  SqliteAt dir -> do
    (s, names, close') <- openSqliteLedger dir
    pure (Right MkOpenedStore {store = s, backend = "sqlite", nonDurable = Nothing, instancesOf = names, close = close'})
  PostgresAt url -> openPostgresStore url >>= \ case
    Left why -> pure (Left why)
    Right (s, names, close') -> pure (Right MkOpenedStore {store = s, backend = "postgres", nonDurable = Nothing, instancesOf = names, close = close'})
  MemoryForTests -> do
    s <- newMemoryStore
    -- the in-memory store cannot list what it holds, so the keys it has
    -- appended to are kept beside it
    held <- newIORef (Set.empty :: Set.Set InstanceKey)
    let s' = MkLedgerStore
          { readRows = s.readRows
          , appendRow = \ k n row -> s.appendRow k n row >>= \ case
              Right () -> atomicModifyIORef' held (\ ks -> (Set.insert k ks, Right ()))
              Left current -> pure (Left current)
          }
        names d = (\ ks -> [ k.instanceName | k <- Set.toAscList ks, k.deployment == d ]) <$> readIORef held
    pure (Right MkOpenedStore {store = s', backend = "memory", nonDurable = Just nonDurableWarning, instancesOf = names, close = pure ()})
