{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE PatternSynonyms #-}
-- | Path imports through the real rules (specs/proposals/RELATIVE-IMPORTS-SPEC.md
-- §4.3, §6): the same files, checked under the two 'LibraryScope's.
--
-- The property worth a test of its own is that confinement is a property of the
-- scope and nothing else. A file planted ABOVE the directory the check runs in
-- is found by 'AmbientLibraries' (the CLI, the editor: a person's own machine,
-- where @..@ may leave the entry file's folder) and is never looked for by
-- 'EmbeddedStdlibOnly' (jl4-service), which refuses the path before it probes
-- anything. The first run is the positive control for the second: without it,
-- "the import was not found" could mean the plant was never findable.
--
-- The root-relative form (a leading slash) is tested the same way. It has one
-- more thing to find, the project root, and one more way to fail, with none
-- (RELATIVE-IMPORTS-SPEC §4.7, proposed for Meng and not ruled).
--
-- Every check runs in a fresh directory and changes the working directory into
-- it, so the entry file is a RELATIVE path, as every file of a service bundle
-- is (@Backend.Jl4@ registers @./path@). hspec runs items one after another, so
-- the working directory is not shared.
module RelativeImportSpec (spec) where

import Control.Exception (bracket)
import Control.Monad (forM_)
import Data.List (isInfixOf)
import Data.Maybe (listToMaybe)
import qualified Data.Text as Text
import System.Directory
  ( createDirectoryIfMissing
  , getCurrentDirectory
  , getTemporaryDirectory
  , removePathForcibly
  , setCurrentDirectory
  )
import System.FilePath (takeDirectory, (</>))

import Language.LSP.Protocol.Types (Diagnostic (..), DiagnosticSeverity (..), Uri (..), normalizedFilePathToUri, toNormalizedFilePath, toNormalizedUri)

import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.TracePolicy (lspDefaultPolicy)
import qualified LSP.Core.Shake as Shake
import LSP.Core.Types.Diagnostics (FileDiagnostic (..))
import LSP.L4.Oneshot (oneshotL4ActionAndDiagnosticsIn)
import LSP.L4.Rules (LibraryScope (..), PathResolution (..), pathFailureMessage, pattern TypeCheck)

import Test.Hspec

-- | A directory tree under a fresh temporary root; the check runs in
-- @\<root\>\/work@, so @..\/planted@ names a file in @\<root\>@ itself, above
-- the place the check starts.
withTree :: [(FilePath, String)] -> IO a -> IO a
withTree files act = bracket setup teardown (const act)
  where
    setup = do
      tmp <- getTemporaryDirectory
      let root = tmp </> "jl4-lsp-relative-import-spec"
      removePathForcibly root
      forM_ files \(rel, body) -> do
        createDirectoryIfMissing True (takeDirectory (root </> rel))
        writeFile (root </> rel) body
      createDirectoryIfMissing True (root </> "work")
      here <- getCurrentDirectory
      setCurrentDirectory (root </> "work")
      pure (here, root)
    teardown (here, root) = do
      setCurrentDirectory here
      removePathForcibly root

-- | Check @entry@ under a scope. @inBundle@ are files handed to the session as
-- virtual files, the way jl4-service hands it a bundle. Returns the diagnostics'
-- severities and messages, and whether the entry module type-checked.
checkUnder :: LibraryScope -> [(FilePath, Text.Text)] -> FilePath -> IO ([(Maybe DiagnosticSeverity, String)], Bool)
checkUnder scope inBundle entry = do
  evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
  (_log, diags, mTc) <- oneshotL4ActionAndDiagnosticsIn scope evalConfig entry \nfp -> do
    forM_ inBundle \(path, body) ->
      Shake.addVirtualFile (toNormalizedFilePath ("./" <> path)) body
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use TypeCheck (normalizedFilePathToUri nfp)
  pure
    ( [ (d._severity, Text.unpack d._message) | FileDiagnostic { fdLspDiagnostic = d } <- diags ]
    , maybe False (const True) mTc
    )

hasMessage :: String -> [(Maybe DiagnosticSeverity, String)] -> Bool
hasMessage needle = any (\(_, m) -> needle `isInfixOf` m)

errors :: [(Maybe DiagnosticSeverity, String)] -> [String]
errors ds = [ m | (Just DiagnosticSeverity_Error, m) <- ds ]

-- | Something that can be told apart from "no such module": a name only the
-- planted file defines.
plantedFile :: String
plantedFile = "plantedmarker MEANS 99\n"

mainImporting :: String -> String
mainImporting name = "IMPORT `" <> name <> "`\n\nprobe MEANS plantedmarker\n"

spec :: Spec
spec = describe "path imports through the rules" $ do

  describe "a path that stays inside the tree" $ do
    let files =
          [ ("work/main.l4", "IMPORT `sub/../mod`\n\nprobe MEANS modmarker\n")
          , ("work/mod.l4", "modmarker MEANS 5\n")
          ]

    it "resolves from the filesystem under AmbientLibraries" $
      withTree files do
        (diags, ok) <- checkUnder AmbientLibraries [] "main.l4"
        errors diags `shouldBe` []
        ok `shouldBe` True

    it "does not read the filesystem under EmbeddedStdlibOnly, only files it was handed" $
      withTree files do
        (diags, _) <- checkUnder EmbeddedStdlibOnly [] "main.l4"
        diags `shouldSatisfy` hasMessage "I could not find a module at this path: sub/../mod"

    it "resolves a file it was handed, under EmbeddedStdlibOnly" $
      withTree [("work/main.l4", "IMPORT `sub/../mod`\n\nprobe MEANS modmarker\n")] do
        (diags, ok) <- checkUnder EmbeddedStdlibOnly [("mod.l4", "modmarker MEANS 5\n")] "main.l4"
        errors diags `shouldBe` []
        ok `shouldBe` True

  describe "a path that climbs above where the check starts" $ do
    let files =
          [ ("work/main.l4", mainImporting "../planted")
          , ("planted.l4", plantedFile)
          ]

    it "finds the planted file under AmbientLibraries (the positive control)" $
      withTree files do
        (diags, ok) <- checkUnder AmbientLibraries [] "main.l4"
        errors diags `shouldBe` []
        ok `shouldBe` True

    it "refuses it under EmbeddedStdlibOnly, naming the import, though the file is there" $
      withTree files do
        (diags, _) <- checkUnder EmbeddedStdlibOnly [] "main.l4"
        diags `shouldSatisfy` hasMessage "This import leaves the root of this deployment: ../planted"

    it "refuses it under EmbeddedStdlibOnly even when the same name was handed over as a file" $
      -- A bundle cannot carry a ".." entry (the upload refuses it), and a
      -- virtual file at the collapsed path would not be reached either: the
      -- refusal comes before any probe.
      withTree files do
        (diags, _) <- checkUnder EmbeddedStdlibOnly [("../planted.l4", Text.pack plantedFile)] "main.l4"
        diags `shouldSatisfy` hasMessage "This import leaves the root of this deployment: ../planted"

  describe "a root-relative import (a leading slash)" $ do
    -- RELATIVE-IMPORTS-SPEC §4.7, PROPOSED, FOR MENG, not ruled. Where the
    -- project root is: the folder of the nearest l4-project.json at or above the
    -- importing file on a person's machine, and the root of the files it was
    -- handed in a deployment.
    let marker = ("work/l4-project.json", "{}\n")
        defs = ("work/shared/defs.l4", "defmarker MEANS 5\n")
        importing names = unlines (map (\n -> "IMPORT `" <> n <> "`") names) <> "\nprobe MEANS defmarker\n"

    describe "under AmbientLibraries" $ do
      it "resolves from the folder of the l4-project.json above the importing file" $
        withTree [marker, defs, ("work/rules/main.l4", importing ["/shared/defs"])] do
          (diags, ok) <- checkUnder AmbientLibraries [] ("rules" </> "main.l4")
          errors diags `shouldBe` []
          ok `shouldBe` True

      it "does the same when the entry file is named by an absolute path" $
        withTree [marker, defs, ("work/rules/main.l4", importing ["/shared/defs"])] do
          here <- getCurrentDirectory
          (diags, ok) <- checkUnder AmbientLibraries [] (here </> "rules" </> "main.l4")
          errors diags `shouldBe` []
          ok `shouldBe` True

      it "finds a project root above the folder the check started in" $
        withTree
          [ ("l4-project.json", "{}\n")
          , ("work/main.l4", importing ["/work/shared/defs"])
          , defs
          ] do
          (diags, ok) <- checkUnder AmbientLibraries [] "main.l4"
          errors diags `shouldBe` []
          ok `shouldBe` True

      it "counts a l4-project.json the session holds in memory, before the disk is asked" $
        withTree [defs, ("work/main.l4", importing ["/shared/defs"])] do
          (diags, ok) <- checkUnder AmbientLibraries [("l4-project.json", "{}\n")] "main.l4"
          errors diags `shouldBe` []
          ok `shouldBe` True

      it "is an error, naming the importer, when no l4-project.json is above it" $
        -- The file IS there, beside the importer and in the working directory,
        -- so a fallback to either would succeed and say nothing.
        withTree [defs, ("work/main.l4", importing ["/shared/defs"])] do
          (diags, _) <- checkUnder AmbientLibraries [] "main.l4"
          diags `shouldSatisfy` hasMessage "This import is relative to the project root, but no project root was found above"
          diags `shouldSatisfy` hasMessage "Add a file named l4-project.json at the top of your project; it may contain just {}."
          diags `shouldSatisfy` hasMessage "main.l4"

      it "uses the nearest l4-project.json, so a project inside a project has its own root" $ do
        -- The outer project's shared/value.l4 is a NUMBER and the inner one's is
        -- a BOOLEAN, so the wrong file is a type error and not a silent pick.
        let files =
              [ marker
              , ("work/shared/value.l4", "valuemarker MEANS 1\n")
              , ("work/inner/l4-project.json", "{}\n")
              , ("work/inner/shared/value.l4", "valuemarker MEANS TRUE\n")
              , ("work/inner/main.l4", "IMPORT `/shared/value`\n\nprobe MEANS valuemarker AND TRUE\n")
              , ("work/top.l4", "IMPORT `/shared/value`\n\nprobe MEANS valuemarker + 1\n")
              ]
        withTree files do
          (innerDiags, _) <- checkUnder AmbientLibraries [] ("inner" </> "main.l4")
          errors innerDiags `shouldBe` []
          (outerDiags, _) <- checkUnder AmbientLibraries [] "top.l4"
          errors outerDiags `shouldBe` []

      it "reaches one file as one module however it is written" $
        forM_ ["relative", "absolute"] \entryKind ->
          withTree
            [ marker, defs
            , ("work/rules/main.l4"
              , unlines
                  [ "IMPORT `/shared/defs`"
                  , "IMPORT `../shared/defs`"
                  , "IMPORT `./../shared/./defs`"
                  , ""
                  , "probe MEANS defmarker + defmarker"
                  ])
            ] do
            here <- getCurrentDirectory
            let entry = if entryKind == ("absolute" :: String) then here </> "rules" </> "main.l4" else "rules" </> "main.l4"
            (diags, ok) <- checkUnder AmbientLibraries [] entry
            errors diags `shouldBe` []
            diags `shouldNotSatisfy` hasMessage "multiple definitions"
            ok `shouldBe` True

      describe "a path that climbs above the project root" $ do
        let files =
              [ marker
              , defs
              , ("work/main.l4", mainImporting "/../planted")
              , ("work/control.l4", mainImporting "../planted")
              , ("work/inside.l4", importing ["/shared/defs"])
              , ("planted.l4", plantedFile)
              ]

        it "is told apart from one that stays inside the project, which is found" $
          withTree files do
            (diags, ok) <- checkUnder AmbientLibraries [] "inside.l4"
            errors diags `shouldBe` []
            ok `shouldBe` True

        it "can be reached by a relative path (the positive control)" $
          withTree files do
            (diags, ok) <- checkUnder AmbientLibraries [] "control.l4"
            errors diags `shouldBe` []
            ok `shouldBe` True

        it "is refused, naming the import, though the file is there" $
          withTree files do
            (diags, _) <- checkUnder AmbientLibraries [] "main.l4"
            diags `shouldSatisfy` hasMessage "This import leaves the root of this deployment: /../planted"

    describe "under EmbeddedStdlibOnly" $ do
      it "resolves from the root of the files it was handed, whatever folder the importer is in" $
        -- rules/shared/defs.l4 is a NUMBER and shared/defs.l4 a BOOLEAN, so the
        -- importer's own folder is a type error and not a silent pick.
        withTree [("work/rules/main.l4", "IMPORT `/shared/defs`\n\nprobe MEANS defmarker AND TRUE\n")] do
          (diags, ok) <- checkUnder EmbeddedStdlibOnly
            [ ("shared/defs.l4", "defmarker MEANS TRUE\n")
            , ("rules/shared/defs.l4", "defmarker MEANS 5\n")
            ] ("rules" </> "main.l4")
          errors diags `shouldBe` []
          ok `shouldBe` True

      it "does not look for an l4-project.json: the root is the root of the files it was handed" $
        withTree [("work/rules/main.l4", "IMPORT `/shared/defs`\n\nprobe MEANS defmarker AND TRUE\n")] do
          (diags, ok) <- checkUnder EmbeddedStdlibOnly
            [ ("rules/l4-project.json", "{}\n")
            , ("shared/defs.l4", "defmarker MEANS TRUE\n")
            , ("rules/shared/defs.l4", "defmarker MEANS 5\n")
            ] ("rules" </> "main.l4")
          errors diags `shouldBe` []
          ok `shouldBe` True

      it "does not read the filesystem, only files it was handed" $
        withTree [defs, ("work/main.l4", importing ["/shared/defs"])] do
          (diags, _) <- checkUnder EmbeddedStdlibOnly [] "main.l4"
          diags `shouldSatisfy` hasMessage "I could not find a module at this path: /shared/defs"

      it "is told apart from a path that climbs above the root, which is refused though the file is there" $
        withTree [("work/main.l4", mainImporting "/../planted"), ("work/inside.l4", importing ["/shared/defs"]), ("planted.l4", plantedFile)] do
          (insideDiags, insideOk) <- checkUnder EmbeddedStdlibOnly [("shared/defs.l4", "defmarker MEANS 5\n")] "inside.l4"
          errors insideDiags `shouldBe` []
          insideOk `shouldBe` True
          (diags, _) <- checkUnder EmbeddedStdlibOnly [] "main.l4"
          diags `shouldSatisfy` hasMessage "This import leaves the root of this deployment: /../planted"

      it "refuses it even when the same name was handed over as a file" $
        withTree [("work/main.l4", mainImporting "/../planted"), ("planted.l4", plantedFile)] do
          (diags, _) <- checkUnder EmbeddedStdlibOnly [("../planted.l4", Text.pack plantedFile)] "main.l4"
          diags `shouldSatisfy` hasMessage "This import leaves the root of this deployment: /../planted"

      it "reaches one file as one module however it is written" $
        withTree
          [ ( "work/rules/main.l4"
            , unlines
                [ "IMPORT `/shared/defs`"
                , "IMPORT `../shared/defs`"
                , ""
                , "probe MEANS defmarker + defmarker"
                ])
          ] do
          (diags, ok) <- checkUnder EmbeddedStdlibOnly [("shared/defs.l4", "defmarker MEANS 5\n")] ("rules" </> "main.l4")
          errors diags `shouldBe` []
          ok `shouldBe` True

  describe "a bare name that is not a module name" $ do
    it "still resolves, and says what it resolved to, as a warning" $
      withTree [("work/main.l4", "IMPORT foo.l4\n\nprobe MEANS foomarker\n"), ("work/foo.l4", "foomarker MEANS 1\n")] do
        (diags, ok) <- checkUnder AmbientLibraries [] "main.l4"
        errors diags `shouldBe` []
        ok `shouldBe` True
        [ s | (s, m) <- diags, "resolved to module `foo`" `isInfixOf` m ]
          `shouldBe` [Just DiagnosticSeverity_Warning]

  describe "the first line of each path-import message" $ do
    -- Pinned here because no file-based session reaches the importer-with-no-
    -- directory case (a browser document keeps its text under a project: key).
    let importer = toNormalizedUri (Uri "jl4-embedded:/prelude.l4")
        firstLine r = Text.unpack <$> (listToMaybe . Text.lines =<< pathFailureMessage importer "../b/mod" r)

    it "says a path was not found" $
      firstLine (PathNotFound "rows/a/main.l4" "rows/b/mod.l4")
        `shouldBe` Just "I could not find a module at this path: ../b/mod"

    it "says an import leaves the root" $
      firstLine (PathEscapesRoot "main.l4" "../b/mod.l4")
        `shouldBe` Just "This import leaves the root of this deployment: ../b/mod"

    it "says an importer has no directory to be relative to" $
      firstLine PathNoImportingDirectory
        `shouldBe` Just "This import is relative, but jl4-embedded:/prelude.l4 has no directory to be relative to."

    it "says nothing about an import that was found" $
      pathFailureMessage importer "../b/mod" (PathFound importer) `shouldBe` Nothing

  -- BEGIN constructors that only exist with the root-relative form
  describe "the text of each root-relative message" $ do
    let importer = toNormalizedUri (Uri "jl4-embedded:/prelude.l4")
        linesOf written r = maybe [] (map Text.unpack . Text.lines) (pathFailureMessage importer written r)

    it "says no project root was found, and what to add" $
      linesOf "/shared/defs" (PathNoProjectRoot "rules/main.l4")
        `shouldBe`
          [ "This import is relative to the project root, but no project root was found above rules/main.l4"
          , "Add a file named l4-project.json at the top of your project; it may contain just {}."
          ]

    it "says an import leaves the root, in the words of the other escape" $
      take 1 (linesOf "/../planted" (PathEscapesProjectRoot "../planted.l4"))
        `shouldBe` ["This import leaves the root of this deployment: /../planted"]

    it "says a root-relative path was not found, relative to the project root" $
      linesOf "/shared/defs" (PathRootNotFound (Just "/proj") "/proj/shared/defs.l4")
        `shouldBe`
          [ "I could not find a module at this path: /shared/defs"
          , "Nothing it defines is in scope here; names you expected from it are reported as undefined."
          , "Relative to the project root /proj that is /proj/shared/defs.l4, which does not exist."
          ]

    it "says so of a deployment without naming a folder on the host" $
      drop 2 (linesOf "/shared/defs" (PathRootNotFound Nothing "shared/defs.l4"))
        `shouldBe` ["Relative to the root of this deployment that is shared/defs.l4, which does not exist."]
  -- END constructors that only exist with the root-relative form
