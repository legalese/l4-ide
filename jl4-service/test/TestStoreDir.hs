-- | Where a test keeps its 'BundleStore'.
--
-- The suite used to put each store at a fixed path under @/tmp@
-- (@/tmp/jl4-service-test-<deployId>@ and friends), deleting it before and
-- after the test. Two gates running this suite at once, in different
-- worktrees, therefore shared those directories, and either could delete a
-- store the other was using. A directory made by 'createTempDirectory' is new
-- on every call, so no other run can reach it.
module TestStoreDir (withStoreDir) where

import Control.Concurrent (threadDelay)
import Control.Exception (IOException, bracket, try)
import System.Directory (removePathForcibly)
import System.FilePath ((</>))
import System.IO.Temp (createTempDirectory, getCanonicalTemporaryDirectory)

-- | Run an action with a path for a store, inside a directory that is unique
-- to this call, and remove that directory afterwards, whether the action
-- returned or threw.
--
-- The path itself does not exist yet, which is what the fixed paths gave
-- their tests after deleting them, so 'BundleStore.initStore' still creates
-- the store directory, as it does in production.
withStoreDir :: String -> (FilePath -> IO a) -> IO a
withStoreDir name act =
  bracket
    (getCanonicalTemporaryDirectory >>= \tmp -> createTempDirectory tmp ("jl4-service-test-" <> name))
    removeStoreDir
    (\dir -> act (dir </> "store"))

-- | Remove a test's directory, and never fail the test doing it.
--
-- A test can end while the service is still writing into its store. A
-- deployment compiled on first use compiles under 'async'
-- ('DeploymentLoader.tryCompileWithTimeout'), so a test that accepts the 202
-- returns while @bundle.cbor@ is still to be written, and even after a 200 the
-- compile goes on to write @metadata.json@ when it backfills a deployment
-- version. A recursive delete that races either write fails with "Directory
-- not empty", and on 2026-10-07 that failed a test whose assertions had all
-- passed ("evaluation on pending deployment returns 200"). So retry for about
-- a second, then stop: the directory belongs to this run alone, so leaving it
-- costs disk space and cannot affect another test.
removeStoreDir :: FilePath -> IO ()
removeStoreDir dir = go (10 :: Int)
 where
  go n = do
    r <- try (removePathForcibly dir)
    case r of
      Right () -> pure ()
      Left (_ :: IOException)
        | n > 1 -> threadDelay 100_000 >> go (n - 1)
        | otherwise -> pure ()
