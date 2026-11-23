{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
module ImportResolutionSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text
import L4.API.VirtualFS
import L4.TypeCheck.Types (CheckResult(errors))
import qualified Data.Map.Strict as Map

spec :: Spec
spec = describe "Import Resolution" $ do
  describe "Embedded Libraries" $ do
    it "has embedded libraries" $ do
      Map.size embeddedLibraries `shouldSatisfy` (> 0)
    
    it "includes prelude" $ do
      lookupEmbeddedLibrary "prelude" `shouldSatisfy` \case
        Just _ -> True
        Nothing -> False
    
    it "includes math" $ do
      lookupEmbeddedLibrary "math" `shouldSatisfy` \case
        Just _ -> True
        Nothing -> False

  describe "Type checking without imports" $ do
    it "type-checks a simple declaration" $ do
      let result = checkWithImports emptyVFS "DECLARE x IS A NUMBER"
      case result of
        Left errs -> fail $ "Type check failed: " ++ show errs
        Right r -> r.tcdSuccess `shouldBe` True

  describe "Type checking with imports" $ do
    it "resolves prelude import" $ do
      let result = checkWithImports emptyVFS "IMPORT prelude\nDECLARE x IS A NUMBER"
      case result of
        Left errs -> fail $ "Type check failed: " ++ show errs
        Right r -> do
          r.tcdSuccess `shouldBe` True
          length r.tcdResolvedImports `shouldBe` 1

    it "uses functions from prelude" $ do
      let source :: Text
          source = Text.unlines
            [ "IMPORT prelude"
            , ""
            , "GIVEN xs IS A LIST OF NUMBER"
            , "GIVETH A NUMBER"
            , "total xs MEANS sum xs"
            ]
      let result = checkWithImports emptyVFS source
      case result of
        Left errs -> fail $ "Type check failed: " ++ show errs
        Right r -> r.tcdSuccess `shouldBe` True

    it "resolves transitive imports (math -> prelude)" $ do
      let source :: Text
          source = Text.unlines
            [ "IMPORT math"
            , ""
            , "DECIDE x IS exp 1"
            ]
      let result = checkWithImports emptyVFS source
      case result of
        Left errs -> fail $ "Type check failed: " ++ show errs
        Right r -> do
          r.tcdSuccess `shouldBe` True
          -- Should have resolved both math and prelude
          length r.tcdResolvedImports `shouldSatisfy` (>= 2)

    it "resolves diamond imports (currency -> jurisdiction, prelude; jurisdiction -> prelude)" $ do
      let source :: Text
          source = Text.unlines
            [ "IMPORT currency"
            , ""
            , "DECIDE x IS 42"
            ]
      let result = checkWithImports emptyVFS source
      case result of
        Left errs -> fail $ "Type check failed: " ++ show errs
        Right r -> do
          r.tcdSuccess `shouldBe` True
          -- Should have resolved currency, jurisdiction, prelude (no duplicates)
          length r.tcdResolvedImports `shouldSatisfy` (>= 3)

    it "type-checks BOTH siblings of a diamond against the shared bottom (smucclaw/l4-ide#904)" $ do
      -- A -> {left, right} -> bottom, where the SECOND sibling (right) also uses
      -- a binding from bottom. Once left has resolved bottom, a name-only
      -- "already resolved, skip" starves right's dependency environment: right
      -- is checked blind, `bottomVal` goes out of scope, and that degradation is
      -- swallowed (only the main module's errors surface in tcdErrors). The fix
      -- threads bottom's resolved record into right, so we assert every resolved
      -- import type-checked clean -- not just that the main module succeeded.
      let vfs = vfsFromList
            [ ("diamond_bottom", "DECIDE bottomVal IS 7")
            , ("diamond_left",   "IMPORT diamond_bottom\nDECIDE leftVal IS bottomVal")
            , ("diamond_right",  "IMPORT diamond_bottom\nDECIDE rightVal IS bottomVal")
            ]
      let source :: Text
          source = Text.unlines
            [ "IMPORT diamond_left"
            , "IMPORT diamond_right"
            , "DECIDE mainVal IS leftVal + rightVal"
            ]
      case checkWithImports vfs source of
        Left errs -> fail $ "Type check failed: " ++ show errs
        Right r -> do
          r.tcdSuccess `shouldBe` True
          -- Neither sibling (nor the bottom) may carry type-check errors.
          let degraded = [ ri.riModuleName
                         | ri <- r.tcdResolvedImports
                         , not (null ri.riTypeChecked.errors)
                         ]
          degraded `shouldBe` []
          -- bottom is shared, so it appears exactly once: left, right, bottom.
          length r.tcdResolvedImports `shouldBe` 3

  describe "VFS lookup" $ do
    it "finds files in VFS" $ do
      let vfs = vfsFromList [("helper", "DECLARE y IS A NUMBER")]
      vfsLookup "helper" vfs `shouldSatisfy` \case
        Just _ -> True
        Nothing -> False

    it "resolves imports from VFS" $ do
      let vfs = vfsFromList [("helper", "DECLARE y IS A NUMBER")]
      let source = "IMPORT helper\nDECLARE x IS A NUMBER"
      let result = checkWithImports vfs source
      case result of
        Left errs -> fail $ "Type check failed: " ++ show errs
        Right r -> do
          r.tcdSuccess `shouldBe` True
          length r.tcdResolvedImports `shouldBe` 1

  describe "Error handling" $ do
    it "reports missing module errors" $ do
      let result = checkWithImports emptyVFS "IMPORT nonexistent\nDECLARE x IS A NUMBER"
      case result of
        Left errs -> errs `shouldSatisfy` \es -> any (Text.isInfixOf "not found") es
        Right _ -> fail "Expected an error for missing module"

    -- smucclaw/l4-ide#1080. This resolver always compared names exactly; what
    -- it lacked was the hint. Pure (no disk), so the same on every OS.
    it "names the stdlib spelling when only the capitals differ" $
      importErrors emptyVFS "IMPORT dayDate\nDECLARE x IS A NUMBER" `shouldBe`
        [ "Module not found: dayDate (searched: embedded libraries, project VFS)\n\
          \Capital letters count in a module name: `dayDate` and `daydate` are different names. Did you mean `daydate`?" ]

    it "names a project file's spelling when only the capitals differ" $ do
      let vfs = vfsFromList [("helper", "DECLARE y IS A NUMBER")]
      importErrors vfs "IMPORT Helper\nDECLARE x IS A NUMBER" `shouldSatisfy` any ("Did you mean `helper`?" `Text.isInfixOf`)

    it "reads a project file's name without its .l4" $ do
      let vfs = vfsFromList [("helper.l4", "DECLARE y IS A NUMBER")]
      importErrors vfs "IMPORT HELPER\nDECLARE x IS A NUMBER" `shouldSatisfy` any ("Did you mean `helper`?" `Text.isInfixOf`)

    it "adds nothing when no module is that close" $
      importErrors emptyVFS "IMPORT nonexistent\nDECLARE x IS A NUMBER" `shouldBe`
        ["Module not found: nonexistent (searched: embedded libraries, project VFS)"]

    -- Review finding A, as revised by GM (2026-11-21): a module is never
    -- offered as a spelling of its own IMPORT, which would make it import
    -- itself; it is told what is true instead.
    it "tells the module being checked that it cannot import itself" $ do
      let vfs = vfsFromList [("Foo", "DECLARE y IS A NUMBER")]
      either id (const ["(no import error)"]) (checkWithImportsAndUri vfs "Foo" "IMPORT foo\nDECLARE x IS A NUMBER")
        `shouldBe` ["Module not found: foo (searched: embedded libraries, project VFS)\n\
          \`foo` differs from `Foo`, the name of this file's own module, only in its capitals. If you meant this file, remove the IMPORT: a module cannot import itself, and a file's own definitions need no IMPORT."]

    -- The same shape one IMPORT down gets no line: the error does not say
    -- which module wrote the IMPORT, so "this file" would be wrong.
    it "does not offer a project file as a spelling of its own IMPORT" $ do
      let vfs = vfsFromList [("Bar", "IMPORT bar\nDECLARE y IS A NUMBER")]
      importErrors vfs "IMPORT Bar\nDECLARE x IS A NUMBER" `shouldBe`
        ["Module not found: bar (searched: embedded libraries, project VFS)"]
  where
    -- The resolver's errors, or one marker line when it checked the file.
    importErrors vfs src = either id (const ["(no import error)"]) (checkWithImports vfs src)
