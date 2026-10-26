{-# LANGUAGE OverloadedStrings #-}

module BundleStoreSpec (spec) where

import Test.Hspec

import BundleStore
import Control.Exception (SomeException, finally, try)
import qualified Data.Map.Strict as Map
import System.Directory (removeDirectoryRecursive, doesDirectoryExist, doesFileExist, removePathForcibly)
import System.FilePath ((</>))
import System.IO.Temp (createTempDirectory, getCanonicalTemporaryDirectory)

spec :: Spec
spec = describe "BundleStore" do
  around withTempStore do
    describe "initStore" do
      it "creates the store directory" \store -> do
        exists <- doesDirectoryExist store.storePath
        exists `shouldBe` True

    describe "isSafeRelativePath" do
      it "accepts a plain or nested relative path" \_ -> do
        mapM_ (\p -> (p, isSafeRelativePath p) `shouldBe` (p, True))
          ["main.l4", "rules/main.l4", "a/b/c.l4", "./x.l4", "a.b/c..d.l4", "..a/b", "a../b"]

      it "refuses a path that is rooted, whatever the separator" \_ -> do
        mapM_ (\p -> (p, isSafeRelativePath p) `shouldBe` (p, False))
          ["/abs.l4", "//abs.l4", "///abs.l4", "\\rooted.l4", "\\\\share\\x.l4", "C:/drive.l4", "c:\\drive.l4", "C:x.l4"]

      it "refuses a path with a parent component, cut at either separator" \_ -> do
        mapM_ (\p -> (p, isSafeRelativePath p) `shouldBe` (p, False))
          ["..", "../x.l4", "a/../../x.l4", "a/..", "a\\..\\x.l4"]

      it "refuses the empty path and a NUL" \_ -> do
        mapM_ (\p -> (p, isSafeRelativePath p) `shouldBe` (p, False))
          ["", "a\0b.l4"]

    describe "saveBundle with a path that leaves the sources directory" do
      it "refuses it, and writes and removes nothing" \store -> do
        -- an absolute path in a directory this test owns, so that a write that was
        -- not refused would land and be seen (a path under "/" would fail for want
        -- of permission and make the test pass for the wrong reason)
        tmp <- getCanonicalTemporaryDirectory
        outside <- createTempDirectory tmp "jl4-bundle-store-spec-outside"
        let target = outside </> "x.l4"
            meta = StoredMetadata "v" "2025-01-01T00:00:00Z" Nothing Nothing Nothing
        (do saveBundle store "keep" (Map.singleton "main.l4" "DECIDE f IS TRUE") meta
            r <- try (saveBundle store "keep" (Map.singleton target "DECIDE f IS TRUE") meta) :: IO (Either SomeException ())
            r `shouldSatisfy` either (const True) (const False)
            -- the earlier bundle is untouched, and nothing was written outside
            (kept, _) <- loadBundle store "keep"
            Map.keys kept `shouldBe` ["main.l4"]
            doesFileExist target `shouldReturn` False)
          `finally` removePathForcibly outside

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
