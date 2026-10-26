{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | The API the browser build calls, with the files a document can import
-- (specs/proposals/RELATIVE-IMPORTS-SPEC.md §6 "wasm", §8): the same programs as
-- the CLI's "l4 relative imports" group (@jl4\/tests-cli\/Main.hs@), given the
-- same answers: 1036 for @rows@, 42 for @identity@ and @parent@, 21 for @back@.
--
-- The foreign exports themselves exist only in a WebAssembly build. What they do
-- is to read the context 'currentImportContext' and call the @...In@ functions
-- of "L4.API" with it, and both halves of that are exercised here.
module ApiImportContextSpec (spec) where

import Control.Monad (forM_, void)
import qualified Data.Text as Text
import Data.Text (Text)
import Test.Hspec

import L4.API
  ( l4CheckIn, l4Eval, l4EvalDirectiveIn, l4EvalIn, l4SetDocumentPath, l4SetFiles )
import L4.API.ImportContext (ImportContext (..), currentImportContext, defaultImportContext)
import L4.API.VirtualFS (VFS, embeddedLibraryNames, emptyVFS, vfsFromList, vfsKeys, vfsLookup)

import PathImportFixtures

contextOf :: VFS -> Text -> ImportContext
contextOf vfs path = ImportContext { icFiles = vfs, icDocumentPath = path }

evalIn :: VFS -> Text -> Text -> IO Text
evalIn files path = l4EvalIn (contextOf files path)

-- | The evaluation said this was the value of a directive.
hasResult :: Text -> Text -> Bool
hasResult value = Text.isInfixOf ("\"result\":\"" <> value <> "\"")

spec :: Spec
spec = describe "The API with the files a document can import" $ do

  describe "gives the CLI's answers on the CLI's fixtures" $ do
    it "evaluates the rows fixture to 1036" $ do
      out <- evalIn rowsFiles "rows/a/main.l4" rowsMain
      out `shouldSatisfy` hasResult "1036"

    it "evaluates the identity fixture to 42, with no clash between the two spellings" $ do
      out <- evalIn (vfsFromList [("core.l4", identityCore)]) "top.l4" identityTop
      out `shouldSatisfy` hasResult "42"
      out `shouldSatisfy` (not . Text.isInfixOf "multiple definitions")

    it "evaluates the climb-out-and-back fixture to 21" $ do
      out <- evalIn backFiles "a/main.l4" backMain
      out `shouldSatisfy` hasResult "21"

    it "evaluates the parent-folder fixture to 42" $ do
      let vfs = vfsFromList [("domain.l4", "domainmarker MEANS 7\n")]
      out <- evalIn vfs "cases/main.l4" "IMPORT `../domain`\n\ncasevalue MEANS domainmarker * 6\n\n#EVAL casevalue\n"
      out `shouldSatisfy` hasResult "42"

    it "evaluates through a module that imports another by name, as a bare chain always should" $ do
      -- Not about paths: a module's own imports have to be in scope when it is
      -- evaluated, whichever way they were written.
      let vfs = vfsFromList [("mid", "IMPORT low\n\nmidvalue MEANS lowvalue + 1\n"), ("low", "lowvalue MEANS 1000\n")]
      out <- l4EvalIn (contextOf vfs "main") "IMPORT mid\n\n#EVAL midvalue\n"
      out `shouldSatisfy` hasResult "1001"

    it "evaluates a diamond's bottom module for both of its importers" $ do
      let vfs = vfsFromList
            [ ("left", "IMPORT bottom\n\nleftvalue MEANS bottomvalue + 1\n")
            , ("right", "IMPORT bottom\n\nrightvalue MEANS bottomvalue + 2\n")
            , ("bottom", "bottomvalue MEANS 10\n")
            ]
      out <- l4EvalIn (contextOf vfs "main") "IMPORT left\nIMPORT right\n\n#EVAL leftvalue + rightvalue\n"
      out `shouldSatisfy` hasResult "23"

  describe "evaluates a module that imports out of its own folder" $ do
    -- Each import of a module is looked at from the folder of the module that
    -- writes it. Looked at from the top of the files, `../shared/core` written in
    -- a/x.l4 would leave the order blind to the edge, and x would be evaluated
    -- before the module it needs.
    it "gives the value of a module in a folder that uses a module in a sibling folder" $ do
      let vfs = vfsFromList
            [ ("shared/core.l4", "corev MEANS 10\n")
            , ("a/x.l4", "IMPORT `../shared/core`\n\nxv MEANS corev + 1\n")
            ]
      out <- evalIn vfs "main" "IMPORT `a/x`\n\n#EVAL xv\n"
      out `shouldSatisfy` hasResult "11"

    it "evaluates a diamond over one type that its two importers reach by different spellings" $ do
      let vfs = vfsFromList
            [ ("shared/core.l4", "DECLARE Colour IS ONE OF red, blue\n\nfavourite MEANS red\n")
            , ("a/x.l4", "IMPORT `../shared/core`\n\nGIVEN c IS A Colour\nDECIDE xok c IF c EQUALS red\n")
            , ("b/y.l4", "IMPORT `../shared/../shared/core`\n\nGIVEN c IS A Colour\nDECIDE yok c IF c EQUALS red\n")
            ]
      out <- evalIn vfs "main" "IMPORT `a/x`\nIMPORT `b/y`\n\n#EVAL yok favourite\n#EVAL xok favourite\n"
      Text.count "\"result\":\"TRUE\"" out `shouldBe` 2

  describe "an imported module that has an error of its own" $ do
    -- shared/core.l4 of the diamond fixture says `1 PLUS TRUE`. The document's
    -- own errors are none, so the check has to say so by another route.
    let broken = "The imported module shared/core has errors"

    it "is reported by the check, once, at the top of the document" $ do
      let out = l4CheckIn (contextOf diamondFiles "main") diamondTop
      Text.count broken out `shouldBe` 1
      out `shouldSatisfy` Text.isInfixOf "\"severity\":1"

    it "is not evaluated, and is not an internal error" $ do
      out <- l4EvalIn (contextOf diamondFiles "main") diamondTop
      out `shouldSatisfy` Text.isInfixOf "\"success\":false"
      out `shouldSatisfy` Text.isInfixOf broken
      out `shouldSatisfy` (not . Text.isInfixOf "Internal error")

    it "is not evaluated for a directive either" $ do
      out <- l4EvalDirectiveIn (contextOf diamondFiles "main") diamondTop 6 1 "#EVAL"
      out `shouldSatisfy` Text.isInfixOf "\"error\""
      out `shouldSatisfy` Text.isInfixOf broken
      out `shouldSatisfy` (not . Text.isInfixOf "Internal error")

    it "is not evaluated whether or not the document uses what is wrong in it" $ do
      let ctx = contextOf diamondFiles "main"
      out <- l4EvalIn ctx "IMPORT `shared/core`\n\nunrelated MEANS 1\n\n#EVAL unrelated\n"
      out `shouldSatisfy` Text.isInfixOf broken
      out `shouldSatisfy` (not . Text.isInfixOf "\"success\":true")

    it "still reports a parse error in an imported file at the top of the document, with the parser's message" $ do
      -- The other thing an imported file's errors leave in the browser (resolution.md,
      -- "In the browser"): a file that cannot be parsed stops the import.
      let vfs = vfsFromList [("rows/b/mod.l4", "DECIDE `the answer` IS\n")]
          out = l4CheckIn (contextOf vfs "rows/a/main.l4") "IMPORT `../b/mod`\n\nx MEANS 1\n"
      out `shouldSatisfy` Text.isInfixOf "Parse error in rows/b/mod:"
      out `shouldSatisfy` Text.isInfixOf "\"severity\":1"
      out `shouldSatisfy` (not . Text.isInfixOf "The imported module")

    it "does not touch a document whose imports all check" $ do
      out <- evalIn rowsFiles "rows/a/main.l4" rowsMain
      out `shouldSatisfy` hasResult "1036"
      l4CheckIn (contextOf rowsFiles "rows/a/main.l4") rowsMain `shouldSatisfy` (not . Text.isInfixOf "The imported module")

    it "never fires for an embedded library, which would take evaluation away from every document that imports one" $
      forM_ embeddedLibraryNames \name ->
        l4CheckIn defaultImportContext ("IMPORT `" <> name <> "`\n") `shouldSatisfy` (not . Text.isInfixOf "The imported module")

  describe "reports what it refused" $ do
    it "as a diagnostic, not a crash" $ do
      let out = l4CheckIn (contextOf emptyVFS "main") "IMPORT `../x`\n\nx MEANS 1\n"
      out `shouldSatisfy` Text.isInfixOf "This import leaves the root of this deployment: ../x"

    it "and gives the default context the answers it gave before there was one" $ do
      -- An import that resolves nowhere, as `IMPORT nonexistent` did.
      let plain = l4CheckIn defaultImportContext "IMPORT nonexistent\n\nx MEANS 1\n"
      plain `shouldSatisfy` Text.isInfixOf "Module not found: nonexistent (searched: embedded libraries, project VFS)"
      out <- l4Eval "IMPORT prelude\n\n#EVAL sum (LIST 1, 2, 3)\n"
      out `shouldSatisfy` hasResult "6"

  describe "what the host sets" $ do
    it "starts with no files and the document at \"main\"" $ do
      ctx <- currentImportContext
      ctx.icFiles `shouldBe` emptyVFS
      ctx.icDocumentPath `shouldBe` "main"
      defaultImportContext.icDocumentPath `shouldBe` "main"

    it "answers a document path with the text it was given, not the path it came to" $ do
      reply <- l4SetDocumentPath "rows/a/"
      reply `shouldSatisfy` Text.isInfixOf "\"documentPath\":\"rows/a/\""
      void (l4SetDocumentPath "")

    it "takes the files as a JSON object from path to source, and the document's path" $ do
      reply <- l4SetFiles "{\"rows/b/mod.l4\": \"modmarker MEANS 1\"}"
      reply `shouldSatisfy` Text.isInfixOf "\"files\":1"
      path <- l4SetDocumentPath "rows/a/main.l4"
      path `shouldSatisfy` Text.isInfixOf "rows/a/main.l4"
      ctx <- currentImportContext
      vfsKeys ctx.icFiles `shouldBe` ["rows/b/mod.l4"]
      ctx.icDocumentPath `shouldBe` "rows/a/main.l4"
      -- and back to the defaults
      _ <- l4SetFiles "{}"
      _ <- l4SetDocumentPath ""
      ctx' <- currentImportContext
      ctx'.icFiles `shouldBe` emptyVFS
      ctx'.icDocumentPath `shouldBe` "main"

    it "keeps the path when the files change, and the files when the path changes" $ do
      _ <- l4SetFiles "{\"a.l4\": \"x MEANS 1\"}"
      _ <- l4SetDocumentPath "d/main.l4"
      _ <- l4SetFiles "{\"b.l4\": \"y MEANS 2\"}"
      ctx <- currentImportContext
      vfsKeys ctx.icFiles `shouldBe` ["b.l4"]
      ctx.icDocumentPath `shouldBe` "d/main.l4"
      _ <- l4SetDocumentPath "e/main.l4"
      ctx' <- currentImportContext
      vfsKeys ctx'.icFiles `shouldBe` ["b.l4"]
      void (l4SetFiles "{}")
      void (l4SetDocumentPath "")

    it "leaves what was set when it is handed something that is not an object of strings" $ do
      _ <- l4SetFiles "{\"keep.l4\": \"x MEANS 1\"}"
      bad <- l4SetFiles "[1, 2]"
      bad `shouldSatisfy` Text.isInfixOf "error"
      worse <- l4SetFiles "{\"k.l4\": 3}"
      worse `shouldSatisfy` Text.isInfixOf "error"
      ctx <- currentImportContext
      vfsKeys ctx.icFiles `shouldBe` ["keep.l4"]
      void (l4SetFiles "{}")

  describe "what the host may hand over" $ do
    it "refuses a key with a leading slash, names it, and keeps the files it had" $ do
      _ <- l4SetFiles "{\"keep.l4\": \"x MEANS 1\"}"
      reply <- l4SetFiles "{\"/core.l4\": \"corev MEANS 7\"}"
      reply `shouldSatisfy` Text.isInfixOf "\"error\""
      reply `shouldSatisfy` Text.isInfixOf "/core.l4"
      reply `shouldSatisfy` Text.isInfixOf "no leading /"
      ctx <- currentImportContext
      vfsKeys ctx.icFiles `shouldBe` ["keep.l4"]
      void (l4SetFiles "{}")

    it "refuses two keys that are one path, names both, and keeps the files it had" $ do
      _ <- l4SetFiles "{\"keep.l4\": \"x MEANS 1\"}"
      forM_ [("core.l4", "./core.l4"), ("core", "core.l4"), ("rows/b/mod.l4", "./rows/a/../b/mod")] \(one, other) -> do
        reply <- l4SetFiles ("{\"" <> one <> "\": \"x MEANS 1\", \"" <> other <> "\": \"x MEANS 2\"}")
        reply `shouldSatisfy` Text.isInfixOf "\"error\""
        reply `shouldSatisfy` Text.isInfixOf "are one path"
        reply `shouldSatisfy` Text.isInfixOf one
        reply `shouldSatisfy` Text.isInfixOf other
      ctx <- currentImportContext
      vfsKeys ctx.icFiles `shouldBe` ["keep.l4"]
      void (l4SetFiles "{}")

    it "takes keys that differ as paths, and a key that climbs out of the files without a word" $ do
      reply <- l4SetFiles "{\"core.l4\": \"x MEANS 1\", \"sub/core.l4\": \"x MEANS 2\", \"../out.l4\": \"x MEANS 3\"}"
      reply `shouldSatisfy` Text.isInfixOf "\"files\":3"
      void (l4SetFiles "{}")

    it "takes a key that appears twice in the text once, with the value of the first" $ do
      -- Measured, not designed: the first one wins with the aeson this tree pins.
      reply <- l4SetFiles "{\"a.l4\": \"first MEANS 1\", \"a.l4\": \"second MEANS 2\"}"
      reply `shouldSatisfy` Text.isInfixOf "\"files\":1"
      ctx <- currentImportContext
      vfsLookup "a" ctx.icFiles `shouldBe` Just "first MEANS 1"
      void (l4SetFiles "{}")
