{-# LANGUAGE OverloadedStrings #-}
-- | The instance ledger's routes, OPERATIONAL-LOWERING-SPEC WPO3, over
-- HTTP: the dinner protocol of §6 against the sqlite default, with no
-- configuration beyond the store path.
--
-- The service here is built as 'Application.defaultMain' builds it, from
-- the options @--store-path <dir>@ alone, with one difference: the ledger
-- clock is one the test sets, because §6's times (18:00 is 64800 on the
-- dinner fixture's clock) are not the service's own clock, whole seconds
-- since the Unix epoch, and what one unit of a contract's time is, and
-- where its start sits against wall time, is D-O8 and open.
module LedgerRoutesSpec
  ( spec
    -- * For the MCP tool's spec
  , Service (..)
  , LedgerChoice (..)
  , withService
  , withServiceUsing
  , loadDinnerBundle
  , at
  , request
  , requestWith
  , create
  , propose
  , proposeWith
  , position
  , field
  , texts
  , int
  , str
  , tickRows
  , check
  , bobBuys
  , buy
  , commitsDinner
  , commitsOf
  , dinnersAtHead
  ) where

import Control.Concurrent.MVar (readMVar)
import Control.Concurrent.STM (newTVarIO)
import Control.Monad (forM_)
import qualified Codec.Archive.Zip as Zip
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy as LBS
import Data.Foldable (for_, toList)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import qualified Data.Text.IO as Text.IO
import Network.HTTP.Client
import Network.HTTP.Client.MultipartFormData (formDataBody, partBS, partFileRequestBody)
import Network.HTTP.Types (Header, statusCode)
import Network.Wai.Handler.Warp (testWithApplication)
import Options.Applicative (defaultPrefs, execParserPure, getParseResult)
import System.Directory (doesFileExist, getCurrentDirectory)
import System.FilePath (takeDirectory, (</>))
import Test.Hspec

import Application (app)
import qualified BundleStore
import Compiler (compileBundle, computeVersion)
import Ledger (ledgerDeployment, validInstanceId)
import Ledger.Service
import Ledger.Store.Config (OpenedStore (..), ResolvedStore, resolveStoreConfig)
import Ledger.Store.Sqlite (ledgerFileName)
import Logging (newLogger)
import Options (Options (..), buildOpts)
import TestStoreDir (withStoreDir)
import Types

import L4.Ledger.Replay (Deployment (..))

spec :: Spec
spec = do
  dinner <- runIO loadDinnerBundle
  describe "the instance ledger's routes (WPO3)" do
    contractSpec dinner
    protocolSpec dinner
    guardSpec dinner
    restartSpec dinner
    limitSpec dinner

----------------------------------------------------------------------------
-- The service
----------------------------------------------------------------------------

-- | The dinner bundle as a deployment uploads it: the brief's
-- @d3-atomic.l4@ and the @properties.l4@ it imports.
loadDinnerBundle :: IO (Map FilePath Text)
loadDinnerBundle = do
  root <- getCurrentDirectory >>= findRoot
  d3 <- Text.IO.readFile (root </> "jl4/examples/explore/brief/d3-atomic.l4")
  props <- Text.IO.readFile (root </> "jl4/examples/explore/brief/properties.l4")
  pure (Map.fromList [("d3-atomic.l4", d3), ("properties.l4", props)])
  where
    findRoot d = do
      found <- doesFileExist (d </> "jl4/examples/explore/brief/d3-atomic.l4")
      if found then pure d
      else if takeDirectory d == d then fail "LedgerRoutesSpec: the repository root (jl4/examples/explore/brief/d3-atomic.l4) was not found above the working directory"
      else findRoot (takeDirectory d)

-- | A service in a store directory: these deployments saved and compiled,
-- the options parsed from @--store-path@ alone, the ledger over the store
-- those options choose, and its clock the given one.
data Service = MkService
  { baseUrl  :: String
  , manager  :: Manager
  , options  :: Options
  , clockRef :: IORef Rational
  }

withService :: FilePath -> IORef Rational -> [(Text, Map FilePath Text)] -> (Service -> IO a) -> IO a
withService = withServiceArgs []

-- | Which ledger the service runs: the one its options choose, none, or
-- one over a store of the test's choosing.
data LedgerChoice = DefaultLedger | NoLedger | LedgerAt ResolvedStore

-- | 'withService' with more options than the store path.
withServiceArgs :: [String] -> FilePath -> IORef Rational -> [(Text, Map FilePath Text)] -> (Service -> IO a) -> IO a
withServiceArgs = withServiceUsing DefaultLedger

withServiceUsing :: LedgerChoice -> [String] -> FilePath -> IORef Rational -> [(Text, Map FilePath Text)] -> (Service -> IO a) -> IO a
withServiceUsing choice args dir clockRef deployments act = do
  info <- buildOpts
  opts <- maybe (fail "the options did not parse") pure
    (getParseResult (execParserPure defaultPrefs info (["--store-path", dir] <> args)))
  store <- BundleStore.initStore opts.storePath
  logger <- newLogger False
  states <- traverse (register store logger) deployments
  registry <- newTVarIO (Map.fromList states)
  pendingUpd <- newTVarIO Map.empty
  tasksReg <- newTVarIO Map.empty
  slots <- newBatchSlots
  mLedger <- case choice of
    NoLedger -> pure Nothing
    LedgerAt resolved -> Just <$> newLedgerService opts resolved (readIORef clockRef)
    DefaultLedger -> do
      resolved <- either (fail . Text.unpack) pure (resolveStoreConfig opts.storePath opts.ledgerStore)
      Just <$> newLedgerService opts resolved (readIORef clockRef)
  let env = MkAppEnv registry pendingUpd store Nothing logger opts tasksReg slots mLedger
  mgr <- newManager defaultManagerSettings {managerResponseTimeout = responseTimeoutMicro 300_000_000}
  r <- testWithApplication (pure (app env)) \ port ->
    act MkService {baseUrl = "http://localhost:" <> show port, manager = mgr, options = opts, clockRef = clockRef}
  for_ mLedger \ ldg -> readMVar ldg.opened >>= traverse_' (.close)
  pure r
  where
    traverse_' f = maybe (pure ()) f
    register store logger (did, sources) = do
      -- a deployment already on disk (a restart) keeps its stored version
      existing <- BundleStore.listDeployments store
      if did `elem` existing then pure () else
        BundleStore.saveBundle store did sources BundleStore.StoredMetadata
          { BundleStore.smVersion = computeVersion sources
          , BundleStore.smCreatedAt = "2026-10-26T00:00:00Z"
          , BundleStore.smDescription = Nothing
          , BundleStore.smServiceVersion = Nothing
          , BundleStore.smDeploymentVersion = Just "1.0.0"
          }
      compileBundle logger did sources >>= \ case
        Left err -> fail ("LedgerRoutesSpec: " <> Text.unpack did <> " did not compile: " <> Text.unpack err)
        Right (fns, meta) -> pure (DeploymentId did, DeploymentReady fns meta)

at :: Service -> Rational -> IO a -> IO a
at s t act = writeIORef s.clockRef t >> act

-- | A JSON request, and the status and JSON body of its reply.
request :: Service -> String -> String -> Maybe Aeson.Value -> IO (Int, Aeson.Value)
request s = requestWith s []

-- | 'request' with more headers.
requestWith :: Service -> [Header] -> String -> String -> Maybe Aeson.Value -> IO (Int, Aeson.Value)
requestWith s headers verb path mbody = do
  req0 <- parseRequest (s.baseUrl <> path)
  let req = req0
        { method = Text.Encoding.encodeUtf8 (Text.pack verb)
        , requestBody = maybe mempty (RequestBodyLBS . Aeson.encode) mbody
        , requestHeaders = ("Content-Type", "application/json") : headers
        }
  resp <- httpLbs req s.manager
  pure (statusCode (responseStatus resp), maybe Aeson.Null id (Aeson.decode (responseBody resp)))

create :: Service -> Text -> Text -> IO (Int, Aeson.Value)
create s dep name = request s "POST" ("/deployments/" <> Text.unpack dep <> "/instances") (Just (Aeson.object
  ["instance" Aeson..= name, "contract" Aeson..= ("`the arrangement`" :: Text)]))

propose :: Service -> Text -> Text -> Text -> Text -> IO (Int, Aeson.Value)
propose s dep name key act = proposeWith s dep name [] key act

proposeWith :: Service -> Text -> Text -> [(Aeson.Key, Aeson.Value)] -> Text -> Text -> IO (Int, Aeson.Value)
proposeWith s dep name extra key act = request s "POST" ("/deployments/" <> Text.unpack dep <> "/instances/" <> Text.unpack name <> "/events")
  (Just (Aeson.object ([ "party" Aeson..= ("World" :: Text), "action" Aeson..= act, "idempotencyKey" Aeson..= key ] <> [ k Aeson..= v | (k, v) <- extra ])))

position :: Service -> Text -> Text -> IO (Int, Aeson.Value)
position s dep name = request s "GET" ("/deployments/" <> Text.unpack dep <> "/instances/" <> Text.unpack name <> "/position") Nothing

-- The evening's acts, as the fixture spells them.
check, bobBuys, buy, done :: Text
check = "`Alice checks whether dinner is bought`"
bobBuys = "`ledger records Bob's purchase`"
buy = "`Alice buys dinner` TRUE"
done = "`Alice is done`"

field :: Text -> Aeson.Value -> Maybe Aeson.Value
field k = \ case
  Aeson.Object o -> KeyMap.lookup (Key.fromText k) o
  _ -> Nothing

-- | The tick rows a reply lists: their seq and their time.
tickRows :: Aeson.Value -> [(Maybe Int, Maybe Aeson.Value)]
tickRows v = case field "ticks" v of
  Just (Aeson.Array ts) -> map (\ t -> (int "seq" t, field "at" t)) (toList ts)
  _ -> []

texts :: Text -> Aeson.Value -> [Text]
texts k v = case field k v of
  Just (Aeson.Array xs) -> [ t | Aeson.String t <- toList xs ]
  _ -> []

int :: Text -> Aeson.Value -> Maybe Int
int k v = case field k v of
  Just (Aeson.Number n) -> Just (round n)
  _ -> Nothing

str :: Text -> Aeson.Value -> Maybe Text
str k v = case field k v of
  Just (Aeson.String t) -> Just t
  _ -> Nothing

-- | What a reply says the step committed to the official record, as cells
-- and values; 'Nothing' when the reply has no @commits@ at all.
commitsOf :: Aeson.Value -> Maybe [(Text, Text)]
commitsOf v = case field "commits" v of
  Just (Aeson.Array xs) -> Just [ (c, x) | e <- toList xs, Just c <- [str "cell" e], Just x <- [str "value" e] ]
  _ -> Nothing

commitsDinner :: Aeson.Value -> Bool
commitsDinner v = any (Text.isPrefixOf "COMMIT `dinners bought`") (texts "wrote" v)

dinnersAtHead :: Aeson.Value -> Int
dinnersAtHead v = length (filter (Text.isPrefixOf "COMMIT `dinners bought`") (texts "ledger" v))

-- | The status, and the result and seq of the body.
outcome :: (Int, Aeson.Value) -> (Int, Maybe Text, Maybe Int)
outcome (code, v) = (code, str "result" v, int "seq" v)

----------------------------------------------------------------------------
-- The contract a deployment runs
----------------------------------------------------------------------------

contractSpec :: Map FilePath Text -> Spec
contractSpec dinner = describe "the contract a deployment runs" do
  it "is its one .l4 file no other imports, with the rest as imports by name" do
    case ledgerDeployment "dinner" "1.0.0" dinner of
      Right dep -> do
        Just dep.deploymentSource `shouldBe` Map.lookup "d3-atomic.l4" dinner
        map fst dep.deploymentImports `shouldBe` ["properties"]
        dep.deploymentVersion `shouldBe` "1.0.0"
      Left why -> expectationFailure (Text.unpack why)

  it "is refused, naming them, when two files are imported by no other" do
    let two = Map.insert "d3-again.l4" (dinner Map.! "d3-atomic.l4") dinner
    case ledgerDeployment "two" "1.0.0" two of
      Left why -> why `shouldSatisfy` (\ w -> "d3-again.l4" `Text.isInfixOf` w && "d3-atomic.l4" `Text.isInfixOf` w)
      Right _ -> expectationFailure "a bundle with two root files was given a contract"

  it "takes an instance name that is one path segment, and nothing else" do
    validInstanceId "evening-1_b" `shouldBe` Nothing
    forM_ ["", "a.l4", "a/b", "a b", Text.replicate 129 "x"] \ n ->
      (n, validInstanceId n == Nothing) `shouldBe` (n, False)

----------------------------------------------------------------------------
-- §6 over HTTP
----------------------------------------------------------------------------

protocolSpec :: Map FilePath Text -> Spec
protocolSpec dinner = describe "the dinner protocol of §6, over HTTP, against the sqlite default with no configuration beyond the store path" do
  it "Sequence A: four rows, and the fourth row's step blocks the buy; no dinner is committed" do
    withStoreDir "ledger-routes-a" \ dir -> do
      clk <- newIORef 0
      withService dir clk [("dinner", dinner)] \ s -> do
        (code1, r1) <- at s 64800 (create s "dinner" "evening-a")
        (code1, str "result" r1, int "seq" r1, str "store" r1) `shouldBe` (201, Just "appended", Just 1, Just "sqlite")
        -- the opening commits that dinner is unbought, and says so
        commitsOf r1 `shouldBe` Just [("dinner status record", "opened")]
        outcome <$> at s 65100 (propose s "dinner" "evening-a" "a2" check) `shouldReturn` (200, Just "appended", Just 2)
        (_, r3) <- at s 65160 (propose s "dinner" "evening-a" "a3" bobBuys)
        (int "seq" r3, "COMMIT `dinner status record` IS taken" `elem` texts "wrote" r3) `shouldBe` (Just 3, True)
        (code4, r4) <- at s 65220 (propose s "dinner" "evening-a" "a4" buy)
        (code4, int "seq" r4, texts "wrote" r4) `shouldBe`
          (200, Just 4, ["RECORD Alice's `belief` IS taken", "RECORD Alice's `plan` IS stopped"])
        -- "appended" with no error, and nothing committed: a recorded attempt, not a purchase
        (str "result" r4, field "applied" r4, commitsOf r4) `shouldBe` (Just "appended", Just (Aeson.Bool True), Just [])
        (field "row" r4 >>= field "at") `shouldBe` Just (Aeson.Number 65220)
        (codeP, p) <- position s "dinner" "evening-a"
        (codeP, int "head" p, dinnersAtHead p) `shouldBe` (200, Just 4, 0)
      -- the default store: one sqlite file under the store path
      doesFileExist (dir </> ledgerFileName) `shouldReturn` True

  it "Sequence B: the buy is row 3 and commits the dinner, Bob's purchase is row 4, and the evening closes fulfilled with one dinner" do
    withStoreDir "ledger-routes-b" \ dir -> do
      clk <- newIORef 0
      withService dir clk [("dinner", dinner)] \ s -> do
        _ <- at s 64800 (create s "dinner" "evening-b")
        _ <- at s 65100 (propose s "dinner" "evening-b" "b2" check)
        (code3, r3) <- at s 65130 (propose s "dinner" "evening-b" "b3" buy)
        (code3, int "seq" r3, commitsDinner r3) `shouldBe` (200, Just 3, True)
        commitsOf r3 `shouldBe` Just [("dinners bought", "`dinner for two`"), ("open at acceptance", "TRUE")]
        (_, r4) <- at s 65160 (propose s "dinner" "evening-b" "b4" bobBuys)
        (int "seq" r4, commitsDinner r4) `shouldBe` (Just 4, False)
        -- a retry after a lost reply reads done, at the same seq, replaying nothing
        (codeR, rR) <- at s 65170 (propose s "dinner" "evening-b" "b3" buy)
        (codeR, int "seq" rR, field "replayed" rR) `shouldBe` (200, Just 3, Just (Aeson.Bool False))
        -- the step is not replayed, so what it committed is unknown: the field is absent, not []
        field "commits" rR `shouldBe` Nothing
        (_, mid) <- position s "dinner" "evening-b"
        (int "head" mid, dinnersAtHead mid, field "terminal" mid) `shouldBe` (Just 4, 1, Just (Aeson.Bool False))
        -- past closing, an act is preceded by the tick that is due, and the
        -- evening is over
        (_, late) <- at s 75700 (propose s "dinner" "evening-b" "b5" done)
        case field "ticks" late of
          Just (Aeson.Array ts) -> map (\ t -> (int "seq" t, field "at" t)) (toList ts) `shouldBe` [(Just 5, Just (Aeson.Number 75601))]
          other -> expectationFailure ("no ticks: " <> show other)
        int "seq" late `shouldBe` Just 6
        (_, end) <- position s "dinner" "evening-b"
        (field "terminal" end, dinnersAtHead end) `shouldBe` (Just (Aeson.Bool True), 1)

  it "says not-found for an instance the ledger does not hold, and creates none in its place" do
    withStoreDir "ledger-routes-nf" \ dir -> do
      clk <- newIORef 65100
      withService dir clk [("dinner", dinner)] \ s -> do
        outcome <$> propose s "dinner" "nobody" "n1" check `shouldReturn` (404, Just "not found", Nothing)
        fst <$> position s "dinner" "nobody" `shouldReturn` 404
        outcome <$> propose s "dinner" "nobody" "n2" check `shouldReturn` (404, Just "not found", Nothing)
        fst <$> create s "no-such-deployment" "x" `shouldReturn` 404

  it "refuses to create an instance twice, an act that is not the contract's, and a strict proposal whose cell moved" do
    withStoreDir "ledger-routes-refuse" \ dir -> do
      clk <- newIORef 64800
      withService dir clk [("dinner", dinner)] \ s -> do
        fst <$> create s "dinner" "evening" `shouldReturn` 201
        fst <$> create s "dinner" "evening" `shouldReturn` 409
        outcome <$> at s 65100 (propose s "dinner" "evening" "r1" "`Alice sings`") `shouldReturn` (422, Just "refused", Nothing)
        _ <- at s 65100 (propose s "dinner" "evening" "r2" check)
        _ <- at s 65160 (propose s "dinner" "evening" "r3" bobBuys)
        -- Alice decided against head 2; the dinner status record moved since
        (codeC, c) <- at s 65220 (proposeWith s "dinner" "evening"
          [("decidedAgainst", Aeson.Number 2), ("strict", Aeson.Bool True), ("cells", Aeson.toJSON ["dinner status record" :: Text])] "r4" buy)
        (codeC, str "result" c, field "applied" c) `shouldBe` (409, Just "conflict", Just (Aeson.Bool False))
        (_, p) <- position s "dinner" "evening"
        int "head" p `shouldBe` Just 3

  it "lists the tick that a refused proposal followed: an instance at head 2 past its deadline, given an act that is not the contract's, answers 422 at head 3, and the tick is a row" do
    withStoreDir "ledger-routes-late-refusal" \ dir -> do
      clk <- newIORef 0
      withService dir clk [("dinner", dinner)] \ s -> do
        _ <- at s 64800 (create s "dinner" "evening-late")
        _ <- at s 65100 (propose s "dinner" "evening-late" "l2" check)
        (code, r) <- at s 75700 (propose s "dinner" "evening-late" "l3" "`Alice sings`")
        (code, str "result" r, field "applied" r, int "head" r) `shouldBe` (422, Just "refused", Just (Aeson.Bool False), Just 3)
        tickRows r `shouldBe` [(Just 3, Just (Aeson.Number 75601))]
        (_, p) <- position s "dinner" "evening-late"
        (int "head" p, field "terminal" p) `shouldBe` (Just 3, Just (Aeson.Bool True))

----------------------------------------------------------------------------
-- A deployment with instances (R-O5)
----------------------------------------------------------------------------

guardSpec :: Map FilePath Text -> Spec
guardSpec dinner = describe "a deployment the ledger holds instances of" do
  it "refuses a silent DELETE and an ungated POST overwrite, and still takes an identical upload and deletes a deployment with none" do
    withStoreDir "ledger-routes-guard" \ dir -> do
      clk <- newIORef 64800
      withService dir clk [("dinner", dinner), ("dinner-unused", dinner)] \ s -> do
        fst <$> create s "dinner" "evening" `shouldReturn` 201
        (codeD, d) <- request s "DELETE" "/deployments/dinner" Nothing
        codeD `shouldBe` 409
        str "error" d `shouldSatisfy` maybe False ("1 instance of it (evening)" `Text.isInfixOf`)
        fst <$> request s "GET" "/deployments/dinner" Nothing `shouldReturn` 200
        -- the short route deletes through the same handler
        fst <$> request s "DELETE" "/dinner" Nothing `shouldReturn` 409
        (codeP, p) <- upload s "dinner" (Map.insert "d3-atomic.l4" ((dinner Map.! "d3-atomic.l4") <> "\n-- changed\n") dinner)
        codeP `shouldBe` 409
        str "error" p `shouldSatisfy` maybe False ("ungated POST" `Text.isInfixOf`)
        -- the same bytes again is not an overwrite: no job, no refusal
        (codeSame, same) <- upload s "dinner" dinner
        (codeSame, str "status" same) `shouldBe` (202, Just "ready")
        fst <$> request s "DELETE" "/deployments/dinner-unused" Nothing `shouldReturn` 204

  it "deletes a deployment, and creates no ledger file to say it holds no instances, when no instance route was used" do
    withStoreDir "ledger-routes-nofile" \ dir -> do
      clk <- newIORef 64800
      withService dir clk [("dinner", dinner)] \ s ->
        fst <$> request s "DELETE" "/deployments/dinner" Nothing `shouldReturn` 204
      doesFileExist (dir </> ledgerFileName) `shouldReturn` False

----------------------------------------------------------------------------
-- The ledger's own limits
----------------------------------------------------------------------------

limitSpec :: Map FilePath Text -> Spec
limitSpec dinner = describe "the ledger's own allocation limit" do
  it "is not a decision's: under the 256 MB a decision gets, creating a dinner instance is stopped, applies nothing, and says which limit" do
    withStoreDir "ledger-routes-limit" \ dir -> do
      clk <- newIORef 64800
      withServiceArgs ["--ledger-max-eval-memory-mb", "256"] dir clk [("dinner", dinner)] \ s -> do
        (code, r) <- create s "dinner" "evening"
        (code, field "applied" r) `shouldBe` (503, Just (Aeson.Bool False))
        str "because" r `shouldSatisfy` maybe False ("--ledger-max-eval-memory-mb" `Text.isInfixOf`)
        -- nothing was created, or, had the limit fallen after the row, the
        -- position is stopped by the same limit
        (codeP, _) <- position s "dinner" "evening"
        codeP `shouldSatisfy` (`elem` [404, 503])

-- | POST /deployments with this id and these files, as a zip.
upload :: Service -> Text -> Map FilePath Text -> IO (Int, Aeson.Value)
upload s did files = do
  let archive = foldr Zip.addEntryToArchive Zip.emptyArchive
        [ Zip.toEntry p 0 (LBS.fromStrict (Text.Encoding.encodeUtf8 src)) | (p, src) <- Map.toList files ]
  req0 <- parseRequest (s.baseUrl <> "/deployments")
  req <- formDataBody
    [ partBS "id" (Text.Encoding.encodeUtf8 did)
    , partFileRequestBody "sources" "bundle.zip" (RequestBodyLBS (Zip.fromArchive archive)) ]
    req0 {method = "POST"}
  resp <- httpLbs req s.manager
  pure (statusCode (responseStatus resp), maybe Aeson.Null id (Aeson.decode (responseBody resp)))

----------------------------------------------------------------------------
-- Restart (§8)
----------------------------------------------------------------------------

restartSpec :: Map FilePath Text -> Spec
restartSpec dinner = describe "a restart, with the sqlite default" do
  it "reloads every instance with the deployments; an unknown instance is still not-found" do
    withStoreDir "ledger-routes-restart" \ dir -> do
      clk <- newIORef 64800
      withService dir clk [("dinner", dinner)] \ s -> do
        _ <- create s "dinner" "kept"
        for_ [(65100, "k2", check), (65160, "k3", bobBuys)] \ (t, k, a) -> at s t (propose s "dinner" "kept" k a)
      withService dir clk [("dinner", dinner)] \ s -> do
        (_, p) <- at s 65200 (position s "dinner" "kept")
        int "head" p `shouldBe` Just 3
        outcome <$> at s 65220 (propose s "dinner" "kept" "k4" buy) `shouldReturn` (200, Just "appended", Just 4)
        outcome <$> at s 65230 (propose s "dinner" "kept" "k3" bobBuys) `shouldReturn` (200, Just "appended", Just 3)
        fst <$> position s "dinner" "forgotten" `shouldReturn` 404
