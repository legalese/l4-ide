{-# LANGUAGE OverloadedStrings #-}

module BundleStoreSpec (spec) where

import Test.Hspec

import BundleStore
import Control.Exception (SomeException, finally, try)
import Control.Monad (forM_)
import Data.Aeson (encodeFile)
import qualified Data.ByteString as BS
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import System.Directory (removeDirectoryRecursive, doesDirectoryExist, doesFileExist, createDirectoryIfMissing, listDirectory, removePathForcibly)
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

    describe "isSafeDeploymentId" do
      it "accepts a plain name, as the API's own ids are" \_ -> do
        mapM_ (\p -> (p, isSafeDeploymentId p) `shouldBe` (p, True))
          ["a", "my-deploy_1", "0b1d5c7e-2f4a-4a8e-9c3d-6e7f8a9b0c1d", "a.b"]

      it "refuses an id that is not one plain path component" \_ -> do
        mapM_ (\p -> (p, isSafeDeploymentId p) `shouldBe` (p, False))
          ["", ".", "..", "../x", "a/b", "a/", "/abs", "//abs", "\\rooted", "a\\b", "C:", "c:x", "a\0b"]

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

  idsOutsideTheStore

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

-- | Deployment ids that are not plain names, in a layout this test owns: the
-- store is @base/store@, and each of @base@, @base/outside@ and the store's own
-- root holds files a deployment would hold, so that a join that was not refused
-- would find them (an id that points at nothing would make a test pass for the
-- wrong reason).
idsOutsideTheStore :: Spec
idsOutsideTheStore = describe "a deployment id that is not a plain name" do
  around withIdLayout do
    it "loadSingleFile reads nothing for it" \(store, base) -> do
      saveBundle store "real" (Map.singleton "main.l4" "DECIDE f IS TRUE") meta
      loadSingleFile store "real" "main.l4" `shouldReturn` Just "DECIDE f IS TRUE"
      forM_ (badIds base) \b ->
        loadSingleFile store b "planted.l4" >>= \r -> (b, r) `shouldBe` (b, Nothing)

    it "listSourceFiles lists nothing for it" \(store, base) -> do
      saveBundle store "real" (Map.singleton "main.l4" "DECIDE f IS TRUE") meta
      listSourceFiles store "real" `shouldReturn` ["main.l4"]
      forM_ (badIds base) \b ->
        listSourceFiles store b >>= \r -> (b, r) `shouldBe` (b, [])

    it "loadMetadataCache finds nothing for it" \(store, base) -> do
      saveBundle store "real" (Map.singleton "main.l4" "DECIDE f IS TRUE") meta
      saveMetadataCache store "real" "{}"
      loadMetadataCache store "real" `shouldReturn` Just "{}"
      forM_ (badIds base) \b ->
        loadMetadataCache store b >>= \r -> (b, r) `shouldBe` (b, Nothing)

    it "loadBundle fails for it, as for a missing deployment" \(store, base) -> do
      saveBundle store "real" (Map.singleton "main.l4" "DECIDE f IS TRUE") meta
      (srcs, _) <- loadBundle store "real"
      Map.keys srcs `shouldBe` ["main.l4"]
      forM_ (badIds base) \b -> do
        r <- try (loadBundle store b)
        (b, either (const "refused") (const "loaded") (r :: Either SomeException (Map.Map FilePath Text, StoredMetadata)))
          `shouldBe` (b, "refused" :: String)

    it "saveBundle refuses it, and writes and removes nothing" \(store, base) -> do
      saveBundle store "real" (Map.singleton "main.l4" "DECIDE f IS TRUE") meta
      atStart <- snapshot base
      forM_ (badIds base) \b -> do
        r <- try (saveBundle store b (Map.singleton "main.l4" "DECIDE g IS TRUE") meta)
        (b, refused r) `shouldBe` (b, True)
      snapshot base `shouldReturn` atStart

    it "saveStoredMetadata refuses it, and writes nothing" \(store, base) -> do
      saveBundle store "real" (Map.singleton "main.l4" "DECIDE f IS TRUE") meta
      saveStoredMetadata store "real" meta { smVersion = "v2" }
      atStart <- snapshot base
      forM_ (badIds base) \b -> do
        r <- try (saveStoredMetadata store b meta { smVersion = "v3" })
        (b, refused r) `shouldBe` (b, True)
      snapshot base `shouldReturn` atStart

    it "saveMetadataCache refuses it, and writes nothing" \(store, base) -> do
      saveBundle store "real" (Map.singleton "main.l4" "DECIDE f IS TRUE") meta
      atStart <- snapshot base
      forM_ (badIds base) \b -> do
        r <- try (saveMetadataCache store b "NEW")
        (b, refused r) `shouldBe` (b, True)
      snapshot base `shouldReturn` atStart

    it "deleteBundle deletes nothing for it" \(store, base) -> do
      saveBundle store "real" (Map.singleton "main.l4" "DECIDE f IS TRUE") meta
      atStart <- snapshot base
      forM_ (badIds base) \b ->
        deleteBundle store b >>= \r -> (b, r) `shouldBe` (b, True)
      snapshot base `shouldReturn` atStart
      -- the control: a real deployment is deleted
      deleteBundle store "real" `shouldReturn` True
      doesDirectoryExist (store.storePath </> "real") `shouldReturn` False
 where
  meta = StoredMetadata "v" "2025-01-01T00:00:00Z" Nothing Nothing Nothing
  planted = "PLANTED-CONTENT-FOR-THE-DEPLOYMENT-ID-SPEC"
  -- an absolute path, one that climbs out of the store, the parent, and the
  -- store's own root by two spellings
  badIds :: FilePath -> [Text]
  badIds base = [Text.pack (base </> "outside"), "../outside", "..", ".", ""]
  refused :: Either SomeException () -> Bool
  refused = either (const True) (const False)
  withIdLayout act = do
    tmp <- getCanonicalTemporaryDirectory
    base <- createTempDirectory tmp "jl4-bundle-store-spec-ids"
    (do store <- initStore (base </> "store")
        createDirectoryIfMissing True (base </> "outside")
        forM_ [base, base </> "outside", base </> "store"] \dir -> do
          createDirectoryIfMissing True (dir </> "sources")
          writeFile (dir </> "sources" </> "planted.l4") planted
          writeFile (dir </> "metadata-cache.json") planted
          encodeFile (dir </> "metadata.json") meta
        act (store, base))
      `finally` removePathForcibly base

-- | Every file and directory under a directory, with file contents, to compare
-- before and after.
snapshot :: FilePath -> IO [(FilePath, Maybe BS.ByteString)]
snapshot dir = do
  names <- List.sort <$> listDirectory dir
  concat <$> mapM entry names
 where
  entry name = do
    let path = dir </> name
    isDir <- doesDirectoryExist path
    if isDir
      then ((path, Nothing) :) <$> snapshot path
      else (\content -> [(path, Just content)]) <$> BS.readFile path
