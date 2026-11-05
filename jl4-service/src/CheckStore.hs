{-# LANGUAGE OverloadedStrings #-}

-- | @jl4-service --check-store DIR@: compile every deployment stored in a
-- directory the way a restart does, say for each whether it compiles, and exit.
--
-- A rollout switches the binary that a store is served by. A restart compiles
-- every stored deployment afresh ("DeploymentLoader.loadAllAndRegister"), so a
-- deployment that the new binary refuses (it type-checks differently, a library
-- it imported has changed, it no longer fits the compile limits) is failed only
-- once the new binary is serving. This runs that same compile first, with the
-- new binary and the store it is about to serve, and reports it.
--
-- It reads the store and writes nothing to it: no directory is created, no
-- stale @.tmp@ directory is cleaned up, no @metadata.json@ is backfilled, no
-- metadata cache is saved. It starts no server. The logs go to stderr, so
-- stdout holds the report alone.
--
-- Exit status: 0 if every deployment compiles (including a store with none),
-- 1 if any does not, 2 if the check could not be made (the directory is not
-- there, or cannot be read) or the command line is wrong.
module CheckStore (
  runCheckStore,
  checkStoreReport,
  Check (..),
  CheckReport (..),
  renderText,
  renderJson,
  reportExitCode,
) where

import qualified BundleStore
import DeploymentLoader (checkDeployments)
import Logging (Logger, newLoggerTo)
import Options (Options (..))

import Control.Exception (IOException, try)
import Data.Aeson (Value, encode, object, (.=))
import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.List (sort)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import System.Directory (doesDirectoryExist, doesFileExist)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (stderr, hPutStrLn)

-- | What the check found for one deployment.
data Check = Check
  { checkId :: !Text
  , checkResult :: !(Either Text Int)
  -- ^ The number of functions it publishes, or why it does not compile.
  , checkBundleCbor :: !Bool
  -- ^ Whether a @bundle.cbor@ lies beside its sources. An older build left one
  -- after every compile. This build does not read it, and the check does not
  -- touch it.
  }
  deriving stock (Eq, Show)

data CheckReport = CheckReport
  { reportStore :: !FilePath
  , reportChecks :: ![Check]
  -- ^ In the order of the deployments' ids.
  }
  deriving stock (Eq, Show)

-- | Check the store at a directory. 'Left' says why the check could not be
-- made at all.
--
-- The store is opened as a path, not with 'BundleStore.initStore', which would
-- create the directory, and 'BundleStore.cleanupStore' is not run, which would
-- delete the @.tmp@ directories of an interrupted deploy.
checkStoreReport :: Logger -> Options -> FilePath -> IO (Either Text CheckReport)
checkStoreReport logger options dir = do
  isDirectory <- doesDirectoryExist dir
  if not isDirectory
    then pure (Left ("not a directory: " <> Text.pack dir))
    else do
      let store = BundleStore.BundleStore dir
      listed <- try (BundleStore.listDeployments store)
      case listed of
        Left (e :: IOException) -> pure (Left ("cannot read " <> Text.pack dir <> ": " <> Text.pack (show e)))
        Right deployIds -> do
          let ids = sort deployIds
          results <- checkDeployments logger options store ids
          checks <- mapM (withBundleCbor dir) results
          pure (Right (CheckReport dir checks))
  where
    withBundleCbor root (deployId, result) = do
      present <- doesFileExist (root </> Text.unpack deployId </> "bundle.cbor")
      pure (Check deployId result present)

-- | The report, one line for each deployment and then a summary.
--
-- A line is its id, @ok@ or @failed@, and the number of functions or the error,
-- separated by tabs. An error can span lines; it is joined onto one here, and
-- the JSON report keeps it as it is.
renderText :: CheckReport -> [Text]
renderText report = map line report.reportChecks <> [summary]
  where
    line c = Text.intercalate "\t" [c.checkId, status c, detail c <> cborNote c]
    status c = either (const "failed") (const "ok") c.checkResult
    detail c = case c.checkResult of
      Right n -> Text.pack (show n) <> (if n == 1 then " function" else " functions")
      Left err -> Text.unwords (Text.words err)
    cborNote c
      | c.checkBundleCbor = " (bundle.cbor present, written by an unknown build)"
      | otherwise = ""
    total = length report.reportChecks
    failed = length [() | c <- report.reportChecks, Left _ <- [c.checkResult]]
    summary
      | total == 0 = "0 deployments"
      | otherwise =
          Text.pack (show total) <> (if total == 1 then " deployment: " else " deployments: ")
            <> Text.pack (show (total - failed)) <> " ok, " <> Text.pack (show failed) <> " failed"

-- | The report as one JSON document.
--
-- @bundleCbor.writtenBy@ is @null@ whenever a file is present: nothing in the
-- file says which build wrote it yet.
renderJson :: CheckReport -> Value
renderJson report = object
  [ "store" .= report.reportStore
  , "deployments" .= map entry report.reportChecks
  , "summary" .= object
      [ "total" .= total
      , "ok" .= (total - failed)
      , "failed" .= failed
      ]
  ]
  where
    total = length report.reportChecks
    failed = length [() | c <- report.reportChecks, Left _ <- [c.checkResult]]
    entry c = object
      [ "id" .= c.checkId
      , "status" .= (either (const "failed") (const "ok") c.checkResult :: Text)
      , "functions" .= either (const Nothing) Just c.checkResult
      , "error" .= either Just (const Nothing) c.checkResult
      , "bundleCbor" .= object
          [ "present" .= c.checkBundleCbor
          , "writtenBy" .= (Nothing :: Maybe Text)
          ]
      ]

-- | 0 if every deployment compiles, 1 if any does not.
reportExitCode :: CheckReport -> ExitCode
reportExitCode report
  | any failedCheck report.reportChecks = ExitFailure 1
  | otherwise = ExitSuccess
  where
    failedCheck c = either (const True) (const False) c.checkResult

-- | Run the check for @--check-store DIR@, print the report, and give the exit
-- status. The caller exits with it.
runCheckStore :: Options -> FilePath -> IO ExitCode
runCheckStore options dir = do
  logger <- newLoggerTo stderr options.debug
  result <- checkStoreReport logger options dir
  case result of
    Left why -> do
      hPutStrLn stderr ("jl4-service --check-store: " <> Text.unpack why)
      pure (ExitFailure 2)
    Right report -> do
      if options.checkJson
        then LBS.putStrLn (encode (renderJson report))
        else mapM_ Text.IO.putStrLn (renderText report)
      pure (reportExitCode report)
