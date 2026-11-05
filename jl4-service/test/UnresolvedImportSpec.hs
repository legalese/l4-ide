{-# LANGUAGE OverloadedStrings #-}

-- | A bundle that imports a module it does not carry is deployed all the same,
-- and the service has to say so.
--
-- A deployment resolves its @IMPORT@s against its own files and the stdlib built
-- into the service, and nothing from the host (see "StdlibResolutionSpec"). So a
-- module that is in neither is not there for any caller, yet the bundle still
-- compiles: the file typechecks, the deploy reports "applied", and only a call
-- that reaches something the missing module should have defined fails. Nothing
-- in the service said so, on a compile or on a restart. Ruled 2026-10-12 (bench "Main Wave Rulings",
-- card R5): a @WARN@ naming the deployment and the module, on both paths. A
-- refusal at deploy time is not part of it.
--
-- The assertions are on the log line, which is what an operator reads.
module UnresolvedImportSpec (spec, withLog, unresolvedLines, hasField) where

import Test.Hspec

import BundleStore (StoredMetadata (..), initStore, saveBundle)
import Compiler (compileBundle, computeVersion)
import DeploymentLoader (loadAndRegister)
import IntegrationSpec (testOptions)
import Logging (Logger, newLoggerTo)
import TestStoreDir (withStoreDir)
import Types (DeploymentId (..), DeploymentState (..))

import Control.Concurrent.STM (newTVarIO, readTVarIO)
import Control.Exception (finally)
import qualified Data.ByteString.Char8 as BS8
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import System.Directory (removePathForcibly)
import System.FilePath ((</>))
import System.IO (IOMode (WriteMode), hClose, openFile)
import System.IO.Temp (createTempDirectory, getCanonicalTemporaryDirectory)

-- | An exported rule beside an @IMPORT@ of a module nobody supplies. The rule
-- reads nothing from the missing module, so the file typechecks and compiles.
importing :: [Text] -> Text
importing modules = Text.unlines $
  [ "IMPORT " <> m | m <- modules ] <>
  [ ""
  , "@export Twice a number"
  , "GIVEN x IS A NUMBER"
  , "GIVETH A NUMBER"
  , "DECIDE doubled x IS x TIMES 2"
  ]

-- | Run something with a logger on a file that is new on every call, and
-- return what it wrote, one JSON object per line.
withLog :: (Logger -> IO a) -> IO (a, [BS8.ByteString])
withLog act = do
  tmp <- getCanonicalTemporaryDirectory
  dir <- createTempDirectory tmp "jl4-service-unresolved-import-spec"
  let path = dir </> "service.jsonl"
  (do h <- openFile path WriteMode
      logger <- newLoggerTo h False
      r <- act logger `finally` hClose h
      logLines <- BS8.lines <$> BS8.readFile path
      pure (r, logLines))
    `finally` removePathForcibly dir

-- | The log lines that report an IMPORT resolving to nothing.
unresolvedLines :: [BS8.ByteString] -> [BS8.ByteString]
unresolvedLines = filter (BS8.isInfixOf "resolves to nothing")

hasField :: BS8.ByteString -> BS8.ByteString -> BS8.ByteString -> Bool
hasField key value = BS8.isInfixOf ("\"" <> key <> "\":\"" <> value <> "\"")

-- | Compile, then bring the same deployment back the way a restart does: from
-- the sources in a store, through 'loadAndRegister'. Each half gets its own
-- log, so a line is attributed to the path that wrote it.
compileThenRestart
  :: Map FilePath Text
  -> IO (Either Text (), [BS8.ByteString], Either Text (), [BS8.ByteString])
compileThenRestart sources = do
  (compiled, compileLog) <- withLog \logger -> compileBundle logger "spec" sources
  case compiled of
    Left err -> pure (Left err, compileLog, Left "not attempted", [])
    Right _ -> do
      (restarted, restartLog) <- withLog \logger -> withStoreDir "unresolved-import" \storeDir -> do
        store <- initStore storeDir
        saveBundle store "spec" sources
          (StoredMetadata (computeVersion sources) "2025-01-01T00:00:00Z" Nothing Nothing Nothing)
        registry <- newTVarIO Map.empty
        loadAndRegister logger testOptions registry store "spec"
        state <- Map.lookup (DeploymentId "spec") <$> readTVarIO registry
        pure $ case state of
          Just (DeploymentReady _ _) -> Right ()
          Just (DeploymentFailed err) -> Left err
          _ -> Left "the deployment was not registered"
      pure (Right (), compileLog, restarted, restartLog)

spec :: Spec
spec = describe "a bundle IMPORT that resolves to nothing is logged at WARN" do
  describe "when the bundle is compiled" do
    it "names the deployment, the importing file and the module" do
      (result, logLines) <- withLog \logger ->
        compileBundle logger "spec" (Map.singleton "main.l4" (importing ["zznope"]))
      (() <$ result) `shouldBe` Right ()
      case unresolvedLines logLines of
        [line] -> do
          line `shouldSatisfy` hasField "level" "warn"
          line `shouldSatisfy` hasField "deploymentId" "spec"
          line `shouldSatisfy` hasField "file" "main.l4"
          line `shouldSatisfy` hasField "module" "zznope"
        other -> expectationFailure ("expected exactly one such line, got " <> show (length other))

    it "names each missing module, and only the missing ones" do
      let sources = Map.fromList
            [ ("main.l4", importing ["prelude", "daydate", "helper", "zzone", "zztwo"])
            , ("helper.l4", Text.unlines ["GIVEN n IS A NUMBER", "GIVETH A NUMBER", "`plus one` n MEANS n PLUS 1"])
            ]
      (_, logLines) <- withLog \logger -> compileBundle logger "spec" sources
      let named = [ m | m <- ["prelude", "daydate", "helper", "zzone", "zztwo"]
                      , any (\l -> hasField "module" (BS8.pack m) l) (unresolvedLines logLines) ]
      named `shouldBe` ["zzone", "zztwo"]

  describe "when the deployment is loaded after a restart" do
    it "says it again, on the restart path's own log" do
      (compiled, compileLog, restarted, restartLog) <-
        compileThenRestart (Map.singleton "main.l4" (importing ["zznope"]))
      compiled `shouldBe` Right ()
      restarted `shouldBe` Right ()
      length (unresolvedLines compileLog) `shouldBe` 1
      case unresolvedLines restartLog of
        [line] -> do
          line `shouldSatisfy` hasField "level" "warn"
          line `shouldSatisfy` hasField "deploymentId" "spec"
          line `shouldSatisfy` hasField "file" "main.l4"
          line `shouldSatisfy` hasField "module" "zznope"
        other -> expectationFailure ("expected exactly one such line on restart, got " <> show (length other))

  describe "when every IMPORT resolves (positive control: passes on the unfixed tree too)" do
    it "logs nothing about IMPORTs, on a compile or on a restart" do
      let sources = Map.fromList
            [ ("main.l4", importing ["prelude", "daydate", "helper"])
            , ("helper.l4", Text.unlines ["GIVEN n IS A NUMBER", "GIVETH A NUMBER", "`plus one` n MEANS n PLUS 1"])
            ]
      (compiled, compileLog, restarted, restartLog) <- compileThenRestart sources
      compiled `shouldBe` Right ()
      restarted `shouldBe` Right ()
      unresolvedLines compileLog `shouldBe` []
      unresolvedLines restartLog `shouldBe` []
