{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Path imports in a deployed bundle (specs/proposals/RELATIVE-IMPORTS-SPEC.md
-- §6, §7): the same source, unchanged, as it runs from a folder on a person's
-- machine, and the one thing a service must not do with it.
--
-- A bundle is a tree of files that were uploaded, so a path import between two
-- of its folders resolves against the bundle and nowhere else. A path that
-- climbs above the bundle is refused before anything is read: the host's
-- filesystem is not part of a deployment (ruled 2026-10-12, see
-- "StdlibResolutionSpec"). The test plants a real file at the place such a path
-- would reach and checks the service does not take it. That the plant IS
-- reachable by an unconfined run is the positive control, and it is in
-- jl4-lsp-test's @RelativeImportSpec@, where both library scopes can be run on
-- the same files.
module RelativeImportSpec (spec) where

import Test.Hspec

import Backend.Api
import Compiler (compileBundle)
import IntegrationSpec (assertSuccess, evalFunction, withServiceFromSources)
import UnresolvedImportSpec (hasField, unresolvedLines, withLog)

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Char8 as BS8
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map
import System.Directory
  ( createDirectoryIfMissing
  , removePathForcibly
  , withCurrentDirectory
  )
import System.FilePath ((</>))
import System.IO.Temp (createTempDirectory, getCanonicalTemporaryDirectory)
import Control.Exception (finally)

-- | A rule that adds the value of a module it reaches by path to its input.
adding :: Text -> Text -> Text
adding importName marker = Text.unlines
  [ "IMPORT `" <> importName <> "`"
  , ""
  , "@export Add the marker"
  , "GIVEN x IS A NUMBER"
  , "GIVETH A NUMBER"
  , "DECIDE addmark x IS x PLUS " <> marker
  ]

constant :: Text -> Integer -> Text
constant name n = name <> " MEANS " <> Text.pack (show n) <> "\n"

addmark :: Integer -> Aeson.Value
addmark x = Aeson.object [ "arguments" Aeson..= Aeson.object [ "x" Aeson..= x ] ]

spec :: Spec
spec = describe "path imports in a deployed bundle" do

  it "resolves `../b/mod` between two folders of the bundle, and evaluates through it" do
    withServiceFromSources "rel-import"
      [ ("rows/a/main.l4", adding "../b/mod" "modmarker")
      , ("rows/b/mod.l4", constant "modmarker" 100)
      ] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "rel-import" "addmark" (addmark 5)
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt 105)

  it "tells two modules with one file name apart by their folders" do
    -- Both `a/rates.l4` and `b/rates.l4` are in the bundle and define the same
    -- name; the importer asks for one of them by path. A basename would have
    -- picked whichever came first.
    withServiceFromSources "rel-import-same-name"
      [ ("main.l4", adding "b/rates" "ratemarker")
      , ("a/rates.l4", constant "ratemarker" 1)
      , ("b/rates.l4", constant "ratemarker" 2)
      ] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "rel-import-same-name" "addmark" (addmark 10)
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt 12)

  it "does not take a file planted where a path climbing out of the bundle would reach" do
    tmp <- getCanonicalTemporaryDirectory
    root <- createTempDirectory tmp "jl4-service-relative-import-spec"
    (do
        createDirectoryIfMissing True (root </> "work")
        writeFile (root </> "planted.l4") "plantedmarker MEANS 99\n"
        -- The bundle's files are registered relative to the service's working
        -- directory, so `../planted` from `main.l4` would reach `<root>/planted.l4`.
        (compiled, logLines) <- withCurrentDirectory (root </> "work") $
          withLog \logger ->
            compileBundle logger "spec" (Map.singleton "main.l4" (adding "../planted" "1"))
        (() <$ compiled) `shouldBe` Right ()
        case unresolvedLines logLines of
          [line] -> do
            line `shouldSatisfy` hasField "file" "main.l4"
            line `shouldSatisfy` hasField "module" "../planted"
            -- the text for a bare name ("no built-in standard library module has
            -- this name") would be false of a path, which never consults it
            line `shouldSatisfy` (not . BS8.isInfixOf "standard library")
            line `shouldSatisfy` BS8.isInfixOf "leaves the bundle"
          other -> expectationFailure
            ("expected the import to be reported as resolving to nothing, got " <> show (length other) <> " lines"))
      `finally` removePathForcibly root
