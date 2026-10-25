{-# LANGUAGE OverloadedStrings #-}
-- | The instance ledger's stores, OPERATIONAL-LOWERING-SPEC WPO2: the
-- sqlite default, the in-memory store for tests, the Postgres adapter's
-- SQL, and the choice between them.
--
-- §8 acceptance items run here, once per store:
--
-- * __Concurrency__: Bob's purchase and Alice's buy proposed at once
--   against one instance, round after round, through 'appendIf' on the
--   brief's @d3-atomic.l4@; no history commits a dinner after a row
--   recording Bob's purchase, and none ends with more than one dinner.
-- * __Idempotency__: the same proposal under the same key, twice in a row
--   and from several threads at once, is one row.
-- * __Restart__ (sqlite): the store reopened on the same file holds every
--   instance, a retried key reads done, and an unknown instance is
--   not-found.
--
-- No Postgres server was available where this was written, so the
-- Postgres adapter's DDL and statements run here on sqlite standing in for
-- the server, and its error classification and the retry on a scripted
-- session; the live item is not run.
module LedgerStoreSpec (spec) where

import Control.Concurrent (getNumCapabilities, setNumCapabilities, threadDelay)
import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (bracket)
import Control.Monad (forM, forM_, when)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef, writeIORef)
import Data.List (sort)
import Data.Ratio ((%))
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Options.Applicative (defaultPrefs, execParserPure, getParseResult)
import System.Directory (createDirectoryIfMissing, doesFileExist, getCurrentDirectory)
import System.FilePath (takeDirectory, (</>))
import Test.Hspec
import Test.QuickCheck hiding (Result, replay)

import BundleStore (cleanupStore, initStore, listDeployments)
import Ledger.Store.Config
import Ledger.Store.Postgres (classifySqlState, postgresBuilt, postgresDdl)
import Ledger.Store.Sql
import Ledger.Store.Sqlite (ledgerFileName, openSqliteSession, openSqliteStore)
import Logging (newLogger)
import Options (Options (..), buildOpts)
import TestStoreDir (withStoreDir)

import L4.EvaluateLazy (resolveEvalConfig)
import L4.Ledger.Append
import L4.Ledger.Replay (Deployment (..), Replayed (..), officialCount, replay)
import L4.Ledger.Row
import L4.Ledger.Store (LedgerStore (..), newMemoryStore)
import L4.TracePolicy (apiDefaultPolicy)

spec :: Spec
spec = do
  dinner <- runIO loadDinner
  describe "the ledger's sqlite store, the default (WPO2)" do
    around withSqlite do
      storeContract
      sqlStoreContract
      concurrencyItem 16 dinner
      idempotencyItem dinner
    restartItems dinner
  describe "the ledger's in-memory store, for tests (WPO2)" do
    around withMemory do
      storeContract
      concurrencyItem 8 dinner
      idempotencyItem dinner
    it "forgets every instance on restart, which is why it is for tests only" do
      first <- newMemoryStore
      l1 <- newLedger first
      _ <- atClock l1 64800 (createInstance l1.ledger (MkInstance dinner "kept?") "`the arrangement`") >>= appended
      second <- newMemoryStore
      l2 <- newLedger second
      atClock l2 65100 (appendIf l2.ledger (MkInstance dinner "kept?") (proposal "k" check)) >>= \ case
        NotFound -> pure ()
        other -> expectationFailure ("expected NotFound, got " <> show other)
  describe "the ledger's Postgres adapter: its DDL and statements, on sqlite standing in for the server (WPO2)" do
    around withPostgresSqlOnSqlite do
      storeContract
      sqlStoreContract
      concurrencyItem 8 dinner
      idempotencyItem dinner
  scriptedSpec
  configSpec

----------------------------------------------------------------------------
-- Stores
----------------------------------------------------------------------------

withSqlite :: (LedgerStore -> IO ()) -> IO ()
withSqlite act = withStoreDir "ledger-sqlite" \ dir ->
  bracket (openSqliteStore dir) snd (act . fst)

withMemory :: (LedgerStore -> IO ()) -> IO ()
withMemory act = newMemoryStore >>= act

-- | The Postgres adapter's DDL, run on a sqlite file, under the same
-- statements: what can be checked of that adapter with no server.
withPostgresSqlOnSqlite :: (LedgerStore -> IO ()) -> IO ()
withPostgresSqlOnSqlite act = withStoreDir "ledger-pg-sql" \ dir -> do
  createDirectoryIfMissing True dir
  bracket (openSqliteSession postgresDdl (dir </> "postgres-sql.sqlite3")) snd (act . sqlStore . fst)

----------------------------------------------------------------------------
-- Fixtures
----------------------------------------------------------------------------

-- | The brief's d3-atomic.l4, read from the tree. `cabal test` runs in the
-- package directory, so the repository is found by walking up to it.
loadDinner :: IO Deployment
loadDinner = do
  root <- getCurrentDirectory >>= findRoot
  d3 <- Text.IO.readFile (root </> "jl4/examples/explore/brief/d3-atomic.l4")
  props <- Text.IO.readFile (root </> "jl4/examples/explore/brief/properties.l4")
  pure MkDeployment
    { deploymentId = "d3-atomic"
    , deploymentVersion = "d3-atomic-v1"
    , deploymentSource = d3
    , deploymentImports = [("properties", props)]
    , versionedCells = ["dinner status record"]
    }
  where
    findRoot d = do
      found <- doesFileExist (d </> "jl4/examples/explore/brief/d3-atomic.l4")
      if found then pure d
      else if takeDirectory d == d then fail "LedgerStoreSpec: the repository root (jl4/examples/explore/brief/d3-atomic.l4) was not found above the working directory"
      else findRoot (takeDirectory d)

-- | A ledger over a store, with a clock the test sets.
data Env = MkEnv
  { ledger   :: Ledger
  , clockRef :: IORef Rational
  }

newLedger :: LedgerStore -> IO Env
newLedger st = do
  ref <- newIORef 0
  cfg <- resolveEvalConfig (Just (UTCTime (fromGregorian 2026 10 25) (secondsToDiffTime 0))) apiDefaultPolicy
  pure MkEnv
    { ledger = MkLedger {store = st, clock = readIORef ref, evalConfig = cfg, timeBound = 120000000, retryCap = 8}
    , clockRef = ref
    }

-- | Set the clock, then do something. Never called from two threads at once.
atClock :: Env -> Rational -> IO a -> IO a
atClock env t act = writeIORef env.clockRef t >> act

check, bobBuys, buy, buyUnanswered, deliver :: Text
check = "`Alice checks whether dinner is bought`"
bobBuys = "`ledger records Bob's purchase`"
buy = "`Alice buys dinner` TRUE"
buyUnanswered = "`Alice buys dinner` FALSE"
deliver = "`Messages delivers the message`"

proposal :: Text -> Text -> Proposed
proposal key a = MkProposed
  { party = "World", action = a, claimedAt = Nothing, decidedAgainst = Nothing
  , idempotencyKey = key, strict = False }

appended :: HasCallStack => Result -> IO Result
appended r = case r of
  Appended {} -> pure r
  other -> do
    expectationFailure ("expected Appended, got " <> show other)
    pure other

commitsDinner :: Result -> Bool
commitsDinner r = any (Text.isPrefixOf "COMMIT `dinners bought`") r.wrote

recordsTaken :: Result -> Bool
recordsTaken r = "COMMIT `dinner status record` IS taken" `elem` r.wrote

-- | The store, counting the appends it refused.
counting :: IORef Int -> LedgerStore -> LedgerStore
counting ref st = MkLedgerStore
  { readRows = st.readRows
  , appendRow = \ k n r -> do
      res <- st.appendRow k n r
      case res of
        Left _ -> atomicModifyIORef' ref \ c -> (c + 1, ())
        Right () -> pure ()
      pure res
  }

----------------------------------------------------------------------------
-- The store's contract, for every store
----------------------------------------------------------------------------

storeContract :: SpecWith LedgerStore
storeContract = describe "the store's contract (§3.7)" do
  let k = MkInstanceKey {deployment = "d", instanceName = "i"}

  it "appends only at head plus one, and says the head when it refuses" \ st -> do
    st.readRows k >>= (`shouldBe` [])
    st.appendRow k 1 (plainRow 1 "a") >>= (`shouldBe` Right ())
    st.appendRow k 1 (plainRow 1 "b") >>= (`shouldBe` Left 1)
    st.appendRow k 3 (plainRow 3 "c") >>= (`shouldBe` Left 1)
    st.appendRow k 2 (plainRow 2 "d") >>= (`shouldBe` Right ())
    map (.seqNo) <$> st.readRows k >>= (`shouldBe` [1, 2])
    st.readRows k {instanceName = "other"} >>= (`shouldBe` [])
    st.readRows k {deployment = "another deployment"} >>= (`shouldBe` [])

  it "leaves a gapless history when appenders race" \ st -> do
    let threads = 8
        each = 20
        appendOne tag = do
          rows <- st.readRows k
          let n = length rows + 1
          st.appendRow k n (plainRow n tag) >>= either (const (appendOne tag)) pure
    _ <- mapConcurrently (\ t -> mapM_ (\ i -> appendOne (Text.pack (show (t, i)))) [1 .. each :: Int]) [1 .. threads :: Int]
    rows <- st.readRows k
    map (.seqNo) rows `shouldBe` [1 .. threads * each]
    length (filter (\ r -> maybe False (Text.isPrefixOf "(3,") r.idempotencyKey) rows) `shouldBe` each

  it "reads back every row exactly as it was appended" \ st -> do
    ref <- newIORef (0 :: Int)
    let roundTrip (RowList rows) = ioProperty do
          i <- atomicModifyIORef' ref \ c -> (c + 1, c)
          let key = k {instanceName = "round trip " <> Text.pack (show i)}
          results <- forM (zip [1 ..] rows) \ (n, r) -> st.appendRow key n r
          back <- st.readRows key
          pure (results === map (const (Right ())) rows .&&. back === rows)
    r <- quickCheckWithResult stdArgs {maxSuccess = 60, chatty = False} roundTrip
    case r of
      Success {} -> pure ()
      other -> expectationFailure (output other)

plainRow :: SeqNo -> Text -> Row
plainRow n tag = MkRow
  { seqNo = n, event = TickEvent, at = 0, txTime = 0, verdict = VAdvancing
  , decidedAgainst = Nothing, idempotencyKey = Just tag, ruleVersion = "t" }

-- | Rows numbered from 1, with distinct idempotency keys, and times that
-- have no exact decimal or no float, or are larger than 64 bits.
newtype RowList = RowList [Row]
  deriving stock (Show)

instance Arbitrary RowList where
  arbitrary = do
    n <- chooseInt (1, 6)
    RowList <$> forM [1 .. n] \ i -> do
      ev <- oneof
        [ OpeningEvent <$> text
        , ActEvent <$> text <*> text
        , pure TickEvent ]
      atTime <- time
      tx <- time
      v <- oneof
        [ pure VDischarging
        , VBreaching <$> oneof [pure Nothing, Just <$> text]
        , pure VAdvancing
        , VPassedOver <$> text ]
      decided <- oneof [pure Nothing, Just <$> chooseInt (1, 100)]
      key <- oneof [pure Nothing, Just . (<> ("#" <> Text.pack (show i))) <$> text]
      rv <- text
      pure MkRow
        { seqNo = i, event = ev, at = atTime, txTime = tx, verdict = v
        , decidedAgainst = decided, idempotencyKey = key, ruleVersion = rv }
    where
      -- Postgres's TEXT holds no NUL, so the ledger's texts never do
      text = Text.pack . filter (/= '\0') <$> arbitrary
      time = oneof
        [ fromInteger <$> arbitrary
        , (\ a b -> a % (10 ^ (b :: Int))) <$> arbitrary <*> chooseInt (0, 6)
        , (%) <$> arbitrary <*> elements [3, 7, 9, 11]
        , (\ a -> a * 2 ^ (70 :: Int) + 1) <$> (fromInteger <$> arbitrary) ]

-- | What only the SQL stores promise.
sqlStoreContract :: SpecWith LedgerStore
sqlStoreContract = describe "the SQL stores' backstops" do
  let k = MkInstanceKey {deployment = "d", instanceName = "keys"}
  it "do not take a second row with an idempotency key the instance already holds: Left at the true head" \ st -> do
    st.appendRow k 1 (plainRow 1 "same") >>= (`shouldBe` Right ())
    st.appendRow k 2 (plainRow 2 "same") >>= (`shouldBe` Left 1)
    st.appendRow k 2 (plainRow 2 "other") >>= (`shouldBe` Right ())
    st.appendRow k {instanceName = "keys elsewhere"} 1 (plainRow 1 "same") >>= (`shouldBe` Right ())

----------------------------------------------------------------------------
-- §8 Concurrency
----------------------------------------------------------------------------

-- | Bob's purchase and Alice's buy, proposed at once, for many rounds.
-- Each round opens an instance at 18:00, Alice checks at 18:05, and then
-- the two proposals (and sometimes a third act) go in from their own
-- threads with the clock fixed at 18:06:40, so the same-second tie is
-- decided by arrival, as R-O1 rules. In a third of the rounds Bob's
-- proposal goes first and Alice's waits until his row is in the store,
-- in a third the other way round, and in a third both start at once, so
-- both outcomes happen whatever the machine's speed, and the last third
-- races: an append takes two replays, so both read the head before
-- either appends. That both outcomes happened, and that some append lost
-- its race and re-ran, is checked too, or the property would hold of a
-- test that never raced.
concurrencyItem :: Int -> Deployment -> SpecWith LedgerStore
concurrencyItem rounds dep = it ("concurrency (§8), " <> show rounds <> " rounds: Bob's purchase and Alice's buy proposed at once never commit a dinner after Bob's purchase, nor more than one") \ st -> withCapabilities 4 do
  lost <- newIORef 0
  env <- newLedger (counting lost st)
  -- wait until the instance holds the row with this idempotency key, or a
  -- minute has passed
  let waitForKey inst key = go (6000 :: Int)
        where
          go 0 = expectationFailure ("the first racer's row, " <> show key <> ", never arrived")
          go k = do
            rows <- st.readRows (instanceKey inst)
            if any (\ r -> r.idempotencyKey == Just key) rows then pure () else threadDelay 10000 >> go (k - 1)
  outcomes <- forM [1 .. rounds] \ i -> do
    let inst = MkInstance dep ("round " <> Text.pack (show i))
        tag t = Text.pack (show i) <> "-" <> t
    _ <- atClock env 64800 (createInstance env.ledger inst "`the arrangement`") >>= appended
    _ <- atClock env 65100 (appendIf env.ledger inst (proposal (tag "check") check)) >>= appended
    extra <- generate (elements [[], [(tag "buy again", buy)], [(tag "unanswered", buyUnanswered)], [(tag "deliver", deliver)]])
    j0 <- generate (chooseInt (0, 2000))
    j1 <- generate (chooseInt (0, 2000))
    j2 <- generate (chooseInt (0, 2000))
    let jitter d = threadDelay d
        (bobStart, aliceStart) = case i `mod` 3 of
          0 -> (jitter 0, waitForKey inst (tag "bob"))
          1 -> (waitForKey inst (tag "alice"), jitter 0)
          _ -> (jitter j0, jitter j1)
        racers = [(bobStart, tag "bob", bobBuys), (aliceStart, tag "alice", buy)]
              <> [ (jitter j2, key, a) | (key, a) <- extra ]
    writeIORef env.clockRef 65200
    results <- mapConcurrently (\ (start, key, a) -> start >> appendIf env.ledger inst (proposal key a)) racers
    rs <- mapM appended results
    rows <- st.readRows (instanceKey inst)
    -- every reply names the row the store holds, and no two share one
    forM_ rs \ r -> (rows !! (r.row.seqNo - 1)) `shouldBe` r.row
    sort (map (.row.seqNo) rs) `shouldBe` [3 .. 2 + length rs]
    let dinners = [ r.row.seqNo | r <- rs, commitsDinner r ]
        takens = [ r.row.seqNo | r <- rs, recordsTaken r ]
    (i, dinners, takens) `shouldSatisfy` \ (_, ds, ts) -> length ds <= 1 && and [ d < t | d <- ds, t <- ts ]
    -- and the stored history, replayed whole, holds at most one dinner
    final <- replay env.ledger.evalConfig env.ledger.timeBound dep rows Nothing >>= either (fail . show) pure
    officialCount "dinners bought" final.headLedger `shouldSatisfy` (<= 1)
    pure (not (null dinners))
  races <- readIORef lost
  (length (filter id outcomes), length (filter not outcomes), races)
    `shouldSatisfy` \ (aliceWon, bobWon, r) -> aliceWon > 0 && bobWon > 0 && r > 0

-- | Run with this many capabilities, so that the racers of a round run on
-- cores of their own, as the service's do under @-N@, and put the count
-- back after.
withCapabilities :: Int -> IO a -> IO a
withCapabilities n act = bracket (getNumCapabilities <* setNumCapabilities n) setNumCapabilities (const act)

----------------------------------------------------------------------------
-- §8 Idempotency
----------------------------------------------------------------------------

idempotencyItem :: Deployment -> SpecWith LedgerStore
idempotencyItem dep = describe "idempotency (§8)" do
  it "the same proposal under the same key, twice, is one row and two Appended naming one seq, the second found before any replay" \ st -> do
    env <- newLedger st
    let inst = MkInstance dep "twice"
    _ <- atClock env 64800 (createInstance env.ledger inst "`the arrangement`") >>= appended
    r1 <- atClock env 65100 (appendIf env.ledger inst (proposal "k" check)) >>= appended
    r2 <- atClock env 65110 (appendIf env.ledger inst (proposal "k" check)) >>= appended
    (r1.row.seqNo, r2.row.seqNo) `shouldBe` (2, 2)
    (r1.replayed, r2.replayed) `shouldBe` (True, False)
    r2.row `shouldBe` r1.row
    map (.seqNo) <$> st.readRows (instanceKey inst) >>= (`shouldBe` [1, 2])

  it "the same proposal under the same key from eight threads at once is one row, and every reply names it" \ st -> do
    env <- newLedger st
    let inst = MkInstance dep "at once"
    _ <- atClock env 64800 (createInstance env.ledger inst "`the arrangement`") >>= appended
    writeIORef env.clockRef 65100
    rs <- mapConcurrently (const (appendIf env.ledger inst (proposal "same" check))) [1 .. 8 :: Int] >>= mapM appended
    map (.row.seqNo) rs `shouldBe` replicate 8 2
    length (filter (.replayed) rs) `shouldBe` 1
    rows <- st.readRows (instanceKey inst)
    map (.seqNo) rows `shouldBe` [1, 2]
    when (length rows == 2) $ forM_ rs \ r -> r.row `shouldBe` rows !! 1

----------------------------------------------------------------------------
-- §8 Restart, sqlite
----------------------------------------------------------------------------

restartItems :: Deployment -> Spec
restartItems dep = describe "restart (§8)" do
  it "a store reopened on the same file holds every instance; a retried key reads done, the history goes on, and an unknown instance is not-found" do
    withStoreDir "ledger-restart" \ dir -> do
      let inst = MkInstance dep "A"
          key = instanceKey inst
      -- the first process: Sequence A up to Bob's purchase
      firstRows <- bracket (openSqliteStore dir) snd \ (st, _) -> do
        env <- newLedger st
        _ <- atClock env 64800 (createInstance env.ledger inst "`the arrangement`") >>= appended
        _ <- atClock env 65100 (appendIf env.ledger inst (proposal "A2" check)) >>= appended
        _ <- atClock env 65160 (appendIf env.ledger inst (proposal "A3" bobBuys)) >>= appended
        st.readRows key
      map (.seqNo) firstRows `shouldBe` [1, 2, 3]
      -- the second process
      bracket (openSqliteStore dir) snd \ (st, _) -> do
        st.readRows key >>= (`shouldBe` firstRows)
        env <- newLedger st
        -- the retried key after the restart: the failure the in-memory default was overturned for
        retried <- atClock env 65170 (appendIf env.ledger inst (proposal "A3" bobBuys)) >>= appended
        (retried.row.seqNo, retried.replayed) `shouldBe` (3, False)
        retried.row `shouldBe` firstRows !! 2
        -- Sequence A goes on: Alice's buy is row 4, and it is blocked
        r4 <- atClock env 65220 (appendIf env.ledger inst (proposal "A4" buy)) >>= appended
        r4.row.seqNo `shouldBe` 4
        commitsDinner r4 `shouldBe` False
        r4.wrote `shouldBe` ["RECORD Alice's `belief` IS taken", "RECORD Alice's `plan` IS stopped"]
        -- an instance the store does not hold is not-found, never a fresh one
        atClock env 65230 (appendIf env.ledger (MkInstance dep "never created") (proposal "n" check)) >>= \ case
          NotFound -> pure ()
          other -> expectationFailure ("expected NotFound, got " <> show other)
        atClock env 65240 (createInstance env.ledger inst "`the arrangement`") >>= \ case
          Refused {} -> pure ()
          other -> expectationFailure ("expected Refused, got " <> show other)

  it "an instance outlives a process that never closed its store" do
    withStoreDir "ledger-unclosed" \ dir -> do
      let inst = MkInstance dep "unclosed"
      (st1, close1) <- openSqliteStore dir
      env <- newLedger st1
      _ <- atClock env 64800 (createInstance env.ledger inst "`the arrangement`") >>= appended
      _ <- atClock env 65100 (appendIf env.ledger inst (proposal "u2" check)) >>= appended
      rows <- st1.readRows (instanceKey inst)
      bracket (openSqliteStore dir) snd \ (st2, _) -> st2.readRows (instanceKey inst) >>= (`shouldBe` rows)
      close1

  it "keeps its file under the store path without the file becoming a deployment" do
    withStoreDir "ledger-beside" \ dir -> do
      logger <- newLogger False
      bundles <- initStore dir
      bracket (openSqliteStore dir) snd \ _ -> pure ()
      doesFileExist (dir </> ledgerFileName) `shouldReturn` True
      listDeployments bundles `shouldReturn` []
      cleanupStore logger bundles
      doesFileExist (dir </> ledgerFileName) `shouldReturn` True

----------------------------------------------------------------------------
-- The shared SQL layer, on a scripted session
----------------------------------------------------------------------------

scriptedSpec :: Spec
scriptedSpec = describe "the SQL stores' statements and retries (Ledger.Store.Sql)" do
  let k = MkInstanceKey {deployment = "d", instanceName = "i"}
      row = plainRow 1 "a"

  it "binds one value to every placeholder of the conditional insert" do
    Text.count "?" insertIfHeadSql `shouldBe` length (rowValues k 1 row) + 3
    Text.count "?" selectRowsSql `shouldBe` 2
    Text.count "?" selectHeadSql `shouldBe` 2
    insertIfHeadSql `shouldSatisfy` Text.isInfixOf "ON CONFLICT DO NOTHING"

  it "asks again while the engine says to, then appends" do
    calls <- newIORef (0 :: Int)
    let session = MkSqlSession
          { execute = \ _ _ -> atomicModifyIORef' calls \ c -> (c + 1, if c < 2 then Left (Transient "busy") else Right 1)
          , query = \ _ _ -> pure (Right []) }
    (sqlStore session).appendRow k 1 row `shouldReturn` Right ()
    readIORef calls `shouldReturn` 3

  it "reads the head when nothing went in, and says it" do
    let session = MkSqlSession
          { execute = \ _ _ -> pure (Right 0)
          , query = \ q _ -> pure (Right (if q == selectHeadSql then [[SqlInt 4]] else [])) }
    (sqlStore session).appendRow k 2 row `shouldReturn` Left 4

  it "gives up loudly on an error that asking again cannot mend, and on a busy that does not clear" do
    let failing f = MkSqlSession {execute = \ _ _ -> pure (Left f), query = \ _ _ -> pure (Left f)}
        storeError (LedgerStoreError _) = True
    (sqlStore (failing (Fatal "no such table"))).appendRow k 1 row `shouldThrow` storeError
    (sqlStore (failing (Transient "busy"))).readRows k `shouldThrow` storeError

  it "refuses a history with a gap, loudly" do
    let r n = rowValues k n (plainRow n (Text.pack (show n)))
        session = MkSqlSession
          { execute = \ _ _ -> pure (Right 1)
          , query = \ _ _ -> pure (Right [drop 2 (r 1), drop 2 (r 3)]) }
    (sqlStore session).readRows k `shouldThrow` \ (LedgerStoreError _) -> True

  it "keeps a time exact, whether or not it has a decimal form" do
    forM_ [0, 65130, 1 % 2, 1 % 10, 1 % 3, -7 % 4, 2 ^ (80 :: Int) + 1 % 7] \ t ->
      decodeTime (encodeTime t) `shouldBe` Right t
    encodeTime (1 % 10) `shouldBe` "0.1"
    encodeTime (1 % 3) `shouldBe` "1/3"

  it "classifies Postgres's SQLSTATEs: serialization failure, deadlock and lock-not-available are asked again" do
    forM_ ["40001", "40P01", "55P03"] \ s -> classifySqlState s "m" `shouldBe` Transient (s <> ": m")
    forM_ ["23505", "08006", "42P01"] \ s -> classifySqlState s "m" `shouldBe` Fatal (s <> ": m")

----------------------------------------------------------------------------
-- Selection by configuration
----------------------------------------------------------------------------

configSpec :: Spec
configSpec = describe "choosing the ledger's store (Ledger.Store.Config)" do
  it "names sqlite, postgres and memory, and refuses Redis, Zookeeper and etcd, citing card O3" do
    parseStoreChoice "sqlite" `shouldBe` Right ChooseSqlite
    parseStoreChoice "Postgres" `shouldBe` Right ChoosePostgres
    parseStoreChoice "memory" `shouldBe` Right ChooseMemory
    forM_ ["redis", "zookeeper", "etcd"] \ s ->
      either (Text.isInfixOf "card O3" . Text.pack) (const False) (parseStoreChoice s) `shouldBe` True
    either (const True) (const False) (parseStoreChoice "mongo") `shouldBe` True

  it "is sqlite under the store path when nothing is said" do
    info <- buildOpts
    case getParseResult (execParserPure defaultPrefs info []) of
      Just o -> do
        o.ledgerStore `shouldBe` defaultLedgerStoreConfig
        resolveStoreConfig o.storePath o.ledgerStore `shouldBe` Right (SqliteAt o.storePath)
      Nothing -> expectationFailure "the options did not parse with no arguments"
    case getParseResult (execParserPure defaultPrefs info ["--ledger-store", "redis"]) of
      Nothing -> pure ()
      Just _ -> expectationFailure "--ledger-store redis was accepted"

  it "puts the in-memory store behind the test flag" do
    resolveStoreConfig "/s" defaultLedgerStoreConfig {choice = ChooseMemory} `shouldSatisfy` either (Text.isInfixOf "--ledger-allow-nondurable") (const False)
    resolveStoreConfig "/s" defaultLedgerStoreConfig {choice = ChooseMemory, allowNonDurable = True} `shouldBe` Right MemoryForTests

  it "asks Postgres for a connection string, and a binary without the adapter says how to get one" do
    let pg = defaultLedgerStoreConfig {choice = ChoosePostgres}
    if postgresBuilt
      then do
        resolveStoreConfig "/s" pg `shouldSatisfy` either (Text.isInfixOf "connection string") (const False)
        resolveStoreConfig "/s" pg {postgresUrl = Just "postgresql://h/db"} `shouldBe` Right (PostgresAt "postgresql://h/db")
        -- the driver runs: with no server on the port, opening is a Left, not a throw
        openLedgerStore (PostgresAt "postgresql://127.0.0.1:1/ledger?connect_timeout=2") >>= \ case
          Left why -> why `shouldSatisfy` Text.isInfixOf "could not connect to the ledger's Postgres"
          Right o -> o.close >> expectationFailure "opened a Postgres store with no server"
      else
        resolveStoreConfig "/s" pg {postgresUrl = Just "postgresql://h/db"} `shouldSatisfy` either (Text.isInfixOf "cabal flag postgres") (const False)

  it "opens the in-memory store with the sentence every reply from it carries, and sqlite with none" do
    openLedgerStore MemoryForTests >>= \ case
      Right o -> (o.backend, o.nonDurable) `shouldBe` ("memory", Just nonDurableWarning)
      Left why -> expectationFailure (Text.unpack why)
    withStoreDir "ledger-config" \ dir -> openLedgerStore (SqliteAt dir) >>= \ case
      Right o -> do
        (o.backend, o.nonDurable) `shouldBe` ("sqlite", Nothing)
        doesFileExist (dir </> ledgerFileName) `shouldReturn` True
        o.close
      Left why -> expectationFailure (Text.unpack why)
    describeResolved (PostgresAt "postgresql://user:secret@h/db") `shouldBe` "postgres"
