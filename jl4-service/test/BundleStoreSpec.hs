{-# LANGUAGE OverloadedStrings #-}

module BundleStoreSpec (spec) where

import Test.Hspec

import BundleStore
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import System.Directory (removeDirectoryRecursive, doesDirectoryExist, createDirectoryIfMissing)
import System.FilePath ((</>))

spec :: Spec
spec = describe "BundleStore" do
  around withTempStore do
    describe "initStore" do
      it "creates the store directory" \store -> do
        exists <- doesDirectoryExist store.storePath
        exists `shouldBe` True

    describe "saveBundle and loadBundle" do
      it "round-trips sources and metadata" \store -> do
        let sources = Map.fromList
              [ ("main.l4", "DECIDE f IS TRUE")
              , ("helper.l4", "DECIDE g IS FALSE")
              ]
            meta = StoredMetadata
              { smVersion = "abc123"
              , smCreatedAt = "2025-01-01T00:00:00Z"
              , smDescription = Nothing
              , smServiceVersion = Nothing
              , smDeploymentVersion = Nothing
              }
        saveBundle store "test-deploy" sources meta
        (loadedSources, loadedMeta) <- loadBundle store "test-deploy"
        loadedSources `shouldBe` sources
        loadedMeta.smVersion `shouldBe` "abc123"
        loadedMeta.smCreatedAt `shouldBe` "2025-01-01T00:00:00Z"

      it "saveStoredMetadata overwrites only metadata.json, preserving sources" \store -> do
        let sources = Map.singleton "main.l4" "DECIDE f IS TRUE"
            meta0 = StoredMetadata
              { smVersion = "v1"
              , smCreatedAt = "2025-01-01T00:00:00Z"
              , smDescription = Just "intended use"
              , smServiceVersion = Nothing
              , smDeploymentVersion = Nothing
              }
        saveBundle store "bf" sources meta0
        -- Backfill the version fields without touching sources.
        saveStoredMetadata store "bf" meta0
          { smServiceVersion = Just "1.5.81"
          , smDeploymentVersion = Just "1.0.0"
          }
        (loadedSources, loadedMeta) <- loadBundle store "bf"
        loadedSources `shouldBe` sources -- untouched
        loadedMeta.smServiceVersion `shouldBe` Just "1.5.81"
        loadedMeta.smDeploymentVersion `shouldBe` Just "1.0.0"
        loadedMeta.smDescription `shouldBe` Just "intended use"

      it "overwrites existing deployment atomically" \store -> do
        let sources1 = Map.singleton "main.l4" "DECIDE f IS TRUE"
            sources2 = Map.singleton "main.l4" "DECIDE f IS FALSE"
            meta1 = StoredMetadata "v1" "2025-01-01T00:00:00Z" Nothing Nothing Nothing
            meta2 = StoredMetadata "v2" "2025-01-02T00:00:00Z" Nothing Nothing Nothing
        saveBundle store "deploy-overwrite" sources1 meta1
        saveBundle store "deploy-overwrite" sources2 meta2
        (loadedSources, loadedMeta) <- loadBundle store "deploy-overwrite"
        loadedSources `shouldBe` sources2
        loadedMeta.smVersion `shouldBe` "v2"

      -- Regression for smucclaw/l4-ide#850. The tmp staging dir name is
      -- deterministic (@<id>.tmp@), so an interrupted deploy can leave a stale
      -- staging dir behind — the nginx `requires` restart cascade during
      -- `nixos-rebuild switch` is exactly such an interruption. If the next
      -- deploy does not clean that dir first, it writes the NEW sources on top
      -- of the stale ones and the atomic swap installs the MERGED result; a
      -- recompile then picks up the stale src/l4 copy and fails import
      -- resolution while still reporting the deployment as "ready".
      it "cleans a leftover tmp staging dir so a redeploy replaces, not merges (smucclaw/l4-ide#850)" \store -> do
        let deployId = "ifema-cross-defaults"
            staleTmpSources =
              store.storePath </> (Text.unpack deployId <> ".tmp") </> "sources"
            newSources = Map.fromList
              [ ("ifema/find-cross-defaults.l4", "IMPORT ifema-definitions\nDECIDE f IS TRUE")
              , ("ifema/ifema-definitions.l4", "DECIDE g IS FALSE")
              ]
            meta = StoredMetadata "v1" "2025-01-01T00:00:00Z" Nothing Nothing Nothing
        -- Simulate the leftover from an interrupted previous deploy: an old
        -- src/l4 file staged in the reused tmp dir that was never swapped in.
        createDirectoryIfMissing True (staleTmpSources </> "src" </> "l4")
        writeFile (staleTmpSources </> "src" </> "l4" </> "find-cross-defaults.l4")
          "IMPORT ifema-definitions\nDECIDE f IS TRUE"
        saveBundle store deployId newSources meta
        (loadedSources, _) <- loadBundle store deployId
        -- Only the new sources survive; the stale src/l4 copy must be gone.
        loadedSources `shouldBe` newSources
        Map.keys loadedSources `shouldNotContain` ["src/l4/find-cross-defaults.l4"]
        -- listSourceFiles agrees: no stale path lingering on disk.
        files <- listSourceFiles store deployId
        files `shouldNotContain` ["src/l4/find-cross-defaults.l4"]

    describe "listDeployments" do
      it "lists saved deployments" \store -> do
        let meta = StoredMetadata "v1" "2025-01-01T00:00:00Z" Nothing Nothing Nothing
        saveBundle store "deploy-a" (Map.singleton "a.l4" "DECIDE a IS TRUE") meta
        saveBundle store "deploy-b" (Map.singleton "b.l4" "DECIDE b IS TRUE") meta
        deployIds <- listDeployments store
        length deployIds `shouldBe` 2
        deployIds `shouldContain` ["deploy-a"]
        deployIds `shouldContain` ["deploy-b"]

      it "returns empty list for fresh store" \store -> do
        deployIds <- listDeployments store
        deployIds `shouldBe` []

    describe "deleteBundle" do
      it "removes a deployment from disk" \store -> do
        let meta = StoredMetadata "v1" "2025-01-01T00:00:00Z" Nothing Nothing Nothing
        saveBundle store "to-delete" (Map.singleton "main.l4" "DECIDE f IS TRUE") meta
        ok <- deleteBundle store "to-delete"
        ok `shouldBe` True
        deployIds <- listDeployments store
        deployIds `shouldNotContain` ["to-delete"]

      it "is idempotent for non-existent deployments" \store -> do
        -- Should not throw
        ok <- deleteBundle store "nonexistent"
        ok `shouldBe` True

-- | Create a temp store, run the test, then clean up.
withTempStore :: (BundleStore -> IO ()) -> IO ()
withTempStore action = do
  let tmpPath = "/tmp/jl4-service-test-store"
  -- Clean up any previous test run
  exists <- doesDirectoryExist tmpPath
  if exists then removeDirectoryRecursive tmpPath else pure ()
  store <- initStore tmpPath
  action store
  -- Clean up after test
  removeDirectoryRecursive tmpPath
