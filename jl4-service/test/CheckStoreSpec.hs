{-# LANGUAGE OverloadedStrings #-}

-- | @jl4-service --check-store DIR@ ("CheckStore"): compile what a store holds,
-- the way a restart does, and say which deployments compile, before a rollout
-- switches the binary that serves the store.
--
-- What is pinned here is what an operator relies on: the report names every
-- deployment that does not compile, with its error; the exit status separates
-- "all compile" (0), "one does not" (1) and "could not check" (2); the limits a
-- restart compiles under apply; and the store is not written, byte for byte,
-- down to an old @bundle.cbor@ and the staging directory of an interrupted
-- deploy.
module CheckStoreSpec (spec) where

import Test.Hspec

import BundleStore (StoredMetadata (..), initStore, saveBundle)
import CheckStore
import Compiler (computeVersion)
import DeploymentLoader (loadAllAndRegister)
import IntegrationSpec (testOptions)
import Logging (Logger, newLoggerTo)
import Options (Options (..), buildOpts, parseOptionsPure)
import qualified BundleStore
import TestData (nameClashJL4, qualifiesJL4)
import TestStoreDir (withStoreDir)
import Types (DeploymentId (..), DeploymentState (..))

import Control.Concurrent.STM (newTVarIO, readTVarIO)
import Control.Monad (forM, forM_)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString as BS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , listDirectory
  )
import System.Exit (ExitCode (..))
import System.FilePath ((</>), makeRelative)
import System.IO (IOMode (WriteMode), withFile)

-- | A source that type-checks.
good :: [(FilePath, Text)]
good = [("qualifies.l4", qualifiesJL4)]

-- | A source that does not type-check, and one that does not parse.
illTyped, unparseable :: [(FilePath, Text)]
illTyped = [("qualifies.l4", Text.replace "walks AND eats AND drinks" "walks AND eats AND 5" qualifiesJL4)]
unparseable = [("qualifies.l4", qualifiesJL4 <> "\nDECIDE ( IS\n")]

-- | A source whose inputs collide once their names are sanitised, so that the
-- compiler raises an error instead of refusing it.
colliding :: [(FilePath, Text)]
colliding = [("clash.l4", nameClashJL4)]

-- | A store holding the given deployments as a deploy leaves them, with
-- @metadata.json@ as a deploy writes it. The directory is made, and given to
-- the action.
withStore :: [(Text, [(FilePath, Text)])] -> (FilePath -> IO a) -> IO a
withStore deployments act = withStoreDir "check-store" \dir -> do
  store <- initStore dir
  forM_ deployments \(deployId, sources) -> do
    let sourceMap = Map.fromList sources
    saveBundle store deployId sourceMap StoredMetadata
      { smVersion = computeVersion sourceMap
      , smCreatedAt = "2026-01-01T00:00:00Z"
      , smDescription = Nothing
      , smServiceVersion = Nothing
      , smDeploymentVersion = Nothing
      }
  act dir

-- | Every file and directory under a path, with the bytes of each file.
snapshot :: FilePath -> IO (Map FilePath (Maybe BS.ByteString))
snapshot root = Map.fromList <$> go root
  where
    go dir = do
      entries <- listDirectory dir
      fmap concat $ forM entries \entry -> do
        let path = dir </> entry
            rel = makeRelative root path
        isDirectory <- doesDirectoryExist path
        if isDirectory
          then ((rel, Nothing) :) <$> go path
          else do
            bytes <- BS.readFile path
            pure [(rel, Just bytes)]

-- | The check, as the command runs it, with the log thrown away.
check :: Options -> FilePath -> IO (Either Text CheckReport)
check options dir = withFile "/dev/null" WriteMode \h -> do
  logger <- newLoggerTo h False :: IO Logger
  checkStoreReport logger options dir

-- | The report of a store that can be checked.
report :: Options -> FilePath -> IO CheckReport
report options dir = check options dir >>= either (\why -> fail ("the check could not be made: " <> Text.unpack why)) pure

-- | The entries of a JSON report's @deployments@, and its @summary@.
deploymentsOf :: Aeson.Value -> [Aeson.Object]
deploymentsOf doc =
  [ o
  | Aeson.Object d <- [doc]
  , Just (Aeson.Array ds) <- [KeyMap.lookup "deployments" d]
  , Aeson.Object o <- foldr (:) [] ds
  ]

summaryOf :: Aeson.Value -> Maybe Aeson.Value
summaryOf doc = case doc of
  Aeson.Object d -> KeyMap.lookup "summary" d
  _ -> Nothing

failureOf :: CheckReport -> Text -> Maybe Text
failureOf r deployId = case [res | c <- r.reportChecks, c.checkId == deployId, Left res <- [c.checkResult]] of
  [err] -> Just err
  _ -> Nothing

spec :: Spec
spec = describe "jl4-service --check-store" do
  describe "a store that holds deployments that do not compile" do
    let deployments =
          [ ("good", good)
          , ("ill-typed", illTyped)
          , ("unparseable", unparseable)
          , ("colliding", colliding)
          , ("bad-metadata", good)
          ]
        broken dir = BS.writeFile (dir </> "bad-metadata" </> "metadata.json") "{ this is not metadata"

    it "reports each of them with its error, and the good one as ok" do
      withStore deployments \dir -> do
        broken dir
        r <- report testOptions dir
        map (.checkId) r.reportChecks `shouldBe` ["bad-metadata", "colliding", "good", "ill-typed", "unparseable"]
        [c.checkId | c <- r.reportChecks, Right _ <- [c.checkResult]] `shouldBe` ["good"]
        failureOf r "ill-typed" `shouldSatisfy` maybe False ("is expected to be of type" `Text.isInfixOf`)
        failureOf r "unparseable" `shouldSatisfy` maybe False ("unexpected (" `Text.isInfixOf`)
        failureOf r "colliding" `shouldSatisfy` maybe False ("collision after sanitization" `Text.isInfixOf`)
        failureOf r "bad-metadata" `shouldSatisfy` maybe False ("Failed to decode metadata" `Text.isInfixOf`)

    it "puts each failure on one line of the text report, with its id, and ends with a summary" do
      withStore deployments \dir -> do
        broken dir
        r <- report testOptions dir
        let ls = renderText r
        length ls `shouldBe` 6
        forM_ (init ls) \l -> length (Text.splitOn "\t" l) `shouldBe` 3
        [Text.splitOn "\t" l !! 1 | l <- init ls] `shouldBe` ["failed", "failed", "ok", "failed", "failed"]
        last ls `shouldBe` "5 deployments: 1 ok, 4 failed"
        ls !! 3 `shouldSatisfy` ("ill-typed\tfailed\t" `Text.isPrefixOf`)
        ls !! 3 `shouldSatisfy` ("is expected to be of type" `Text.isInfixOf`)
        -- an error that spans lines is joined onto one
        forM_ ls \l -> Text.any (== '\n') l `shouldBe` False

    it "exits 1" do
      withStore deployments \dir -> do
        r <- report testOptions dir
        reportExitCode r `shouldBe` ExitFailure 1

    it "gives the report as one JSON document, with each error as it is" do
      withStore deployments \dir -> do
        broken dir
        r <- report testOptions dir
        let doc = renderJson r
            ds = deploymentsOf doc
            entry n = case drop n ds of
              o : _ -> o
              [] -> KeyMap.empty
            field k o = KeyMap.lookup (Key.fromText k) o
        length ds `shouldBe` 5
        field "id" (entry 2) `shouldBe` Just (Aeson.String "good")
        field "status" (entry 2) `shouldBe` Just (Aeson.String "ok")
        field "error" (entry 2) `shouldBe` Just Aeson.Null
        field "functions" (entry 2) `shouldBe` Just (Aeson.Number 1)
        field "status" (entry 3) `shouldBe` Just (Aeson.String "failed")
        field "functions" (entry 3) `shouldBe` Just Aeson.Null
        field "error" (entry 3) `shouldSatisfy` \case
          Just (Aeson.String err) -> "is expected to be of type" `Text.isInfixOf` err
          _ -> False
        summaryOf doc `shouldBe`
          Just (Aeson.object ["total" Aeson..= (5 :: Int), "ok" Aeson..= (1 :: Int), "failed" Aeson..= (4 :: Int)])

  describe "a store in which every deployment compiles" do
    it "exits 0, and says how many functions each publishes" do
      withStore [("first", good), ("second", good)] \dir -> do
        r <- report testOptions dir
        reportExitCode r `shouldBe` ExitSuccess
        [c.checkResult | c <- r.reportChecks] `shouldBe` [Right 1, Right 1]
        renderText r `shouldBe`
          [ "first\tok\t1 function"
          , "second\tok\t1 function"
          , "2 deployments: 2 ok, 0 failed"
          ]

  describe "an empty store" do
    it "exits 0 and says there are no deployments" do
      withStore [] \dir -> do
        r <- report testOptions dir
        reportExitCode r `shouldBe` ExitSuccess
        renderText r `shouldBe` ["0 deployments"]

  describe "a store that cannot be checked" do
    it "is an error, not a failed deployment, and the missing directory is not created" do
      withStoreDir "check-store-missing" \missing -> do
        r <- check testOptions missing
        r `shouldSatisfy` either ("not a directory" `Text.isInfixOf`) (const False)
        doesDirectoryExist missing `shouldReturn` False

  describe "the limits of a restart" do
    it "fails a deployment that does not compile within --compile-timeout" do
      -- A timeout of zero is over before the compile starts.
      withStore [("slow", good)] \dir -> do
        r <- report testOptions {compileTimeout = 0} dir
        failureOf r "slow" `shouldSatisfy` maybe False ("timed out or exceeded memory limit" `Text.isInfixOf`)
        reportExitCode r `shouldBe` ExitFailure 1

  describe "the store" do
    let leftOver dir = do
          -- what an older build left beside the sources, and what an interrupted
          -- deploy leaves, in a store whose metadata.json predates versioning
          BS.writeFile (dir </> "good" </> "bundle.cbor") "what an older build wrote"
          createDirectoryIfMissing True (dir </> "interrupted.tmp" </> "sources")
          BS.writeFile (dir </> "interrupted.tmp" </> "sources" </> "half.l4") "DECIDE half"

    it "is byte for byte what it was, a bundle.cbor and a staging directory included" do
      withStore [("good", good), ("ill-typed", illTyped)] \dir -> do
        leftOver dir
        snapBefore <- snapshot dir
        _ <- report testOptions dir
        snapAfter <- snapshot dir
        snapAfter `shouldBe` snapBefore
        -- the check can tell: loading the same store, as a restart does, writes
        -- the backfilled version into metadata.json and a metadata cache
        loaded <- newTVarIO Map.empty
        withFile "/dev/null" WriteMode \h -> do
          logger <- newLoggerTo h False
          loadAllAndRegister logger testOptions loaded (BundleStore.BundleStore dir) ["good"]
        state <- readTVarIO loaded
        (case Map.lookup (DeploymentId "good") state of
           Just (DeploymentReady _ _) -> True
           _ -> False)
          `shouldBe` True
        loadedSnapshot <- snapshot dir
        loadedSnapshot `shouldNotBe` snapBefore

    it "says that a bundle.cbor is there, and not which build wrote it" do
      withStore [("good", good), ("plain", good)] \dir -> do
        leftOver dir
        r <- report testOptions dir
        let ls = renderText r
        ls !! 0 `shouldSatisfy` ("(bundle.cbor present, written by an unknown build)" `Text.isInfixOf`)
        ls !! 1 `shouldSatisfy` (not . Text.isInfixOf "bundle.cbor")
        let cbor = [KeyMap.lookup "bundleCbor" o | o <- deploymentsOf (renderJson r)]
        cbor `shouldBe`
          [ Just (Aeson.object ["present" Aeson..= True, "writtenBy" Aeson..= Aeson.Null])
          , Just (Aeson.object ["present" Aeson..= False, "writtenBy" Aeson..= Aeson.Null])
          ]
        -- and the file is still there, still saying what it said
        BS.readFile (dir </> "good" </> "bundle.cbor") `shouldReturn` "what an older build wrote"

  describe "the command line" do
    it "gives a usage error status 2 with --check-store, where the server's stays 1" do
      info <- buildOpts
      let status args = case parseOptionsPure "jl4-service" info args of
            Left (Right (_, code)) -> Just code
            _ -> Nothing
      status ["--check-store", "d", "--no-such-option"] `shouldBe` Just (ExitFailure 2)
      status ["--no-such-option"] `shouldBe` Just (ExitFailure 1)
      status ["--help"] `shouldBe` Just ExitSuccess
      -- --json is a way of printing the check, and means nothing without it
      status ["--json"] `shouldBe` Just (ExitFailure 2)
      status ["--check-store", "d", "--json"] `shouldBe` Nothing
