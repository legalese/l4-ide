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

  describe "a leading slash" $
    forM_ [AmbientLibraries, EmbeddedStdlibOnly] \scope ->
      it ("is refused under " <> show scope) $
        withTree [("work/main.l4", mainImporting "/planted"), ("planted.l4", plantedFile)] do
          (diags, _) <- checkUnder scope [] "main.l4"
          diags `shouldSatisfy` hasMessage "This import leaves the root of this deployment: /planted"

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

    it "says a leading slash is refused in the same words" $
      firstLine PathRootRefused
        `shouldBe` Just "This import leaves the root of this deployment: ../b/mod"

    it "says an importer has no directory to be relative to" $
      firstLine PathNoImportingDirectory
        `shouldBe` Just "This import is relative, but jl4-embedded:/prelude.l4 has no directory to be relative to."

    it "says nothing about an import that was found" $
      pathFailureMessage importer "../b/mod" (PathFound importer) `shouldBe` Nothing
