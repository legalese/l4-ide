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

  -- The root-relative form (RELATIVE-IMPORTS-SPEC §4.7, PROPOSED, FOR MENG, not
  -- ruled): a leading slash names a file from the root of the bundle. A service
  -- has no folder of its own to search for an l4-project.json in, so the root is
  -- the root of the files it was handed, whatever folder the importer is in.
  describe "a root-relative import in a deployed bundle" do

    it "resolves `/shared/mod` from the bundle root, whatever folder the importer is in" do
      withServiceFromSources "rel-import-root"
        [ ("rows/a/main.l4", adding "/shared/mod" "modmarker")
        , ("shared/mod.l4", constant "modmarker" 100)
        ] \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "rel-import-root" "addmark" (addmark 5)
          assertSuccess resp \r ->
            Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt 105)

    it "needs no l4-project.json, and a bundle that carries one still deploys" do
      -- The marker is the CLI's way of finding a root; here the root is known.
      -- The file travels with the bundle, and this change does not read it.
      withServiceFromSources "rel-import-root-marker"
        [ ("l4-project.json", "{}\n")
        , ("rows/a/main.l4", adding "/shared/mod" "modmarker")
        , ("shared/mod.l4", constant "modmarker" 100)
        ] \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "rel-import-root-marker" "addmark" (addmark 5)
          assertSuccess resp \r ->
            Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt 105)

    it "does not take the importer's folder for the root" do
      -- rows/a/shared/mod.l4 is a decoy with a different value: a root taken
      -- from the importer's folder would add 1 and not 100.
      withServiceFromSources "rel-import-root-decoy"
        [ ("rows/a/main.l4", adding "/shared/mod" "modmarker")
        , ("rows/a/shared/mod.l4", constant "modmarker" 1)
        , ("shared/mod.l4", constant "modmarker" 100)
        ] \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "rel-import-root-decoy" "addmark" (addmark 5)
          assertSuccess resp \r ->
            Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt 105)

    it "reaches one file as one module however it is written" do
      -- Three spellings of rows/b/mod.l4 from rows/a/main.l4. Two modules would
      -- define modmarker twice and the call would not compile.
      let main = Text.unlines
            [ "IMPORT `/rows/b/mod`"
            , "IMPORT `../b/mod`"
            , "IMPORT `./../b/./mod`"
            , ""
            , "@export Add the marker"
            , "GIVEN x IS A NUMBER"
            , "GIVETH A NUMBER"
            , "DECIDE addmark x IS x PLUS modmarker"
            ]
      withServiceFromSources "rel-import-root-identity"
        [ ("rows/a/main.l4", main)
        , ("rows/b/mod.l4", constant "modmarker" 100)
        ] \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "rel-import-root-identity" "addmark" (addmark 5)
          assertSuccess resp \r ->
            Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt 105)

    it "does not take a file planted where a path climbing out of the bundle would reach" do
      -- The plant is reachable by an unconfined run (jl4-lsp-test's
      -- RelativeImportSpec runs the same files under both scopes); here it must
      -- not be, and the log must say the path leaves the bundle, in words that
      -- are true of a path from the root.
      tmp <- getCanonicalTemporaryDirectory
      root <- createTempDirectory tmp "jl4-service-root-relative-import-spec"
      (do
          createDirectoryIfMissing True (root </> "work")
          writeFile (root </> "planted.l4") "plantedmarker MEANS 99\n"
          (compiled, logLines) <- withCurrentDirectory (root </> "work") $
            withLog \logger ->
              compileBundle logger "spec" (Map.singleton "main.l4" (adding "/../planted" "1"))
          (() <$ compiled) `shouldBe` Right ()
          case unresolvedLines logLines of
            [line] -> do
              line `shouldSatisfy` hasField "file" "main.l4"
              line `shouldSatisfy` hasField "module" "/../planted"
              line `shouldSatisfy` (not . BS8.isInfixOf "standard library")
              line `shouldSatisfy` (not . BS8.isInfixOf "importing file")
              line `shouldSatisfy` BS8.isInfixOf "leaves the bundle"
            other -> expectationFailure
              ("expected the import to be reported as resolving to nothing, got " <> show (length other) <> " lines"))
        `finally` removePathForcibly root

    it "does not read the host's disk for a root-relative path inside the bundle either" do
      tmp <- getCanonicalTemporaryDirectory
      root <- createTempDirectory tmp "jl4-service-root-relative-disk-spec"
      (do
          createDirectoryIfMissing True (root </> "shared")
          writeFile (root </> "shared" </> "mod.l4") "modmarker MEANS 99\n"
          (compiled, logLines) <- withCurrentDirectory root $
            withLog \logger ->
              compileBundle logger "spec" (Map.singleton "main.l4" (adding "/shared/mod" "1"))
          (() <$ compiled) `shouldBe` Right ()
          case unresolvedLines logLines of
            [line] -> line `shouldSatisfy` hasField "module" "/shared/mod"
            other -> expectationFailure
              ("expected the import to be reported as resolving to nothing, got " <> show (length other) <> " lines"))
        `finally` removePathForcibly root

  -- Aliases (RELATIVE-IMPORTS-SPEC §4.7 C6, PROPOSED, FOR MENG, not ruled): a name
  -- that starts with @ and has a slash is a folder that the l4-project.json at the
  -- top of the bundle names. The service has no folder of its own to search for
  -- one in, so only the top counts, and it reads the file the store kept.
  describe "an alias import in a deployed bundle" do
    let manifest :: Text -> Text
        manifest pairs = "{\"aliases\": {" <> pairs <> "}}\n"
        sharedAs = manifest "\"common\": \"shared\""

    it "resolves `@common/mod` through the l4-project.json at the top, whatever folder the importer is in" do
      withServiceFromSources "rel-import-alias"
        [ ("l4-project.json", sharedAs)
        , ("rows/a/main.l4", adding "@common/mod" "modmarker")
        , ("shared/mod.l4", constant "modmarker" 100)
        ] \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "rel-import-alias" "addmark" (addmark 5)
          assertSuccess resp \r ->
            Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt 105)

    it "takes the l4-project.json at the top and no other, whatever folder the importer is in" do
      -- rows/a/l4-project.json points `common` at a decoy with another value; a
      -- manifest found by searching upward from the importer, as a person's
      -- machine does, would add 1 and not 100.
      withServiceFromSources "rel-import-alias-top"
        [ ("l4-project.json", sharedAs)
        , ("rows/a/l4-project.json", manifest "\"common\": \"decoy\"")
        , ("rows/a/main.l4", adding "@common/mod" "modmarker")
        , ("shared/mod.l4", constant "modmarker" 100)
        , ("decoy/mod.l4", constant "modmarker" 1)
        ] \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "rel-import-alias-top" "addmark" (addmark 5)
          assertSuccess resp \r ->
            Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt 105)

    it "reaches one file as one module whether it is written with the alias, from the root or from the importer" do
      let main = Text.unlines
            [ "IMPORT `@common/mod`"
            , "IMPORT `/shared/mod`"
            , "IMPORT `../../shared/mod`"
            , ""
            , "@export Add the marker"
            , "GIVEN x IS A NUMBER"
            , "GIVETH A NUMBER"
            , "DECIDE addmark x IS x PLUS modmarker"
            ]
      withServiceFromSources "rel-import-alias-identity"
        [ ("l4-project.json", sharedAs)
        , ("rows/a/main.l4", main)
        , ("shared/mod.l4", constant "modmarker" 100)
        ] \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "rel-import-alias-identity" "addmark" (addmark 5)
          assertSuccess resp \r ->
            Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt 105)

    it "reports an alias the bundle does not define as an import that resolved to nothing, saying so" do
      (compiled, logLines) <- withLog \logger ->
        compileBundle logger "spec" $ Map.fromList
          [ ("l4-project.json", sharedAs)
          , ("main.l4", adding "@nope/mod" "1")
          , ("shared/mod.l4", constant "modmarker" 100)
          ]
      (() <$ compiled) `shouldBe` Right ()
      case unresolvedLines logLines of
        [line] -> do
          line `shouldSatisfy` hasField "module" "@nope/mod"
          line `shouldSatisfy` BS8.isInfixOf "alias is not defined"
          line `shouldSatisfy` (not . BS8.isInfixOf "standard library")
          line `shouldSatisfy` (not . BS8.isInfixOf "importing file")
        other -> expectationFailure
          ("expected the import to be reported as resolving to nothing, got " <> show (length other) <> " lines")

    it "reports an alias used in a bundle with no l4-project.json at its top" do
      (compiled, logLines) <- withLog \logger ->
        compileBundle logger "spec" $ Map.fromList
          [ ("rows/l4-project.json", sharedAs)
          , ("main.l4", adding "@common/mod" "1")
          , ("shared/mod.l4", constant "modmarker" 100)
          ]
      (() <$ compiled) `shouldBe` Right ()
      case unresolvedLines logLines of
        [line] -> line `shouldSatisfy` hasField "module" "@common/mod"
        other -> expectationFailure
          ("expected the import to be reported as resolving to nothing, got " <> show (length other) <> " lines")

    it "does not take a file planted where a path under an alias climbing out of the bundle would reach" do
      tmp <- getCanonicalTemporaryDirectory
      root <- createTempDirectory tmp "jl4-service-alias-import-spec"
      (do
          createDirectoryIfMissing True (root </> "work")
          writeFile (root </> "planted.l4") "plantedmarker MEANS 99\n"
          (compiled, logLines) <- withCurrentDirectory (root </> "work") $
            withLog \logger ->
              compileBundle logger "spec" $ Map.fromList
                [ ("l4-project.json", sharedAs)
                , ("main.l4", adding "@common/../../planted" "1")
                ]
          (() <$ compiled) `shouldBe` Right ()
          case unresolvedLines logLines of
            [line] -> line `shouldSatisfy` hasField "module" "@common/../../planted"
            other -> expectationFailure
              ("expected the import to be reported as resolving to nothing, got " <> show (length other) <> " lines"))
        `finally` removePathForcibly root

    -- The folder an alias stands for is `..`, above the bundle. A file is planted
    -- on the host where that folder would lead, and another is handed to the
    -- compile under the key the climbing path would collapse to, so that the
    -- import would resolve if nothing refused the climb: the disk is never read
    -- under confinement, but the bundle's own files are, and a bundle can hold
    -- any key a map is given. Two checks refuse this path (the alias's folder and
    -- the path under it), and the service sees neither message, only that the
    -- import resolved to nothing, so one of them alone cannot be shown to fail
    -- here; both together can (RELATIVE-IMPORTS-SPEC §4.7.6).
    it "does not resolve an alias whose folder is above the bundle, though a file is planted where it would lead" do
      tmp <- getCanonicalTemporaryDirectory
      root <- createTempDirectory tmp "jl4-service-alias-up-spec"
      (do
          createDirectoryIfMissing True (root </> "work")
          writeFile (root </> "planted.l4") "plantedmarker MEANS 99\n"
          (compiled, logLines) <- withCurrentDirectory (root </> "work") $
            withLog \logger ->
              compileBundle logger "spec" $ Map.fromList
                [ ("l4-project.json", manifest "\"up\": \"..\"")
                , ("main.l4", adding "@up/planted" "1")
                , ("../planted.l4", constant "plantedmarker" 99)
                ]
          (() <$ compiled) `shouldBe` Right ()
          case unresolvedLines logLines of
            [line] -> line `shouldSatisfy` hasField "module" "@up/planted"
            other -> expectationFailure
              ("expected the import to be reported as resolving to nothing, got " <> show (length other) <> " lines"))
        `finally` removePathForcibly root

    it "does not read an l4-project.json from the host's disk, which is where a person's machine would find it" do
      -- The host has the manifest and the bundle has the file it would lead to
      -- but not the manifest: a manifest read from the host's disk would make
      -- the import resolve, so that it is reported as resolving to nothing says
      -- the service resolves aliases from the bundle and nowhere else.
      tmp <- getCanonicalTemporaryDirectory
      root <- createTempDirectory tmp "jl4-service-alias-disk-spec"
      (do
          writeFile (root </> "l4-project.json") (Text.unpack sharedAs)
          (compiled, logLines) <- withCurrentDirectory root $
            withLog \logger ->
              compileBundle logger "spec" $ Map.fromList
                [ ("main.l4", adding "@common/mod" "1")
                , ("shared/mod.l4", constant "modmarker" 99)
                ]
          (() <$ compiled) `shouldBe` Right ()
          case unresolvedLines logLines of
            [line] -> line `shouldSatisfy` hasField "module" "@common/mod"
            other -> expectationFailure
              ("expected the import to be reported as resolving to nothing, got " <> show (length other) <> " lines"))
        `finally` removePathForcibly root
