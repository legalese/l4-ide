{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | The pure half of path imports (specs/proposals/RELATIVE-IMPORTS-SPEC.md
-- §4.2, §4.3): which written names are paths, and how a path is collapsed.
--
-- Nothing here touches the filesystem. Paths are POSIX-shaped; the written
-- names of a path import use @/@ on every platform (§4.2 rule 4), and
-- 'collapsePath' is given and returns native paths, so the expected values
-- below are built with 'joinPath' where a separator matters.
module RelativeImportSpec (spec) where

import System.FilePath (joinPath)
import Test.Hspec

import L4.Import.Resolution
  ( CollapsedPath (..)
  , ImportForm (..)
  , classifyImport
  , collapsePath
  , pathImportFile
  )

collapsed :: FilePath -> Bool -> CollapsedPath
collapsed p esc = CollapsedPath { cpPath = p, cpEscaped = esc }

spec :: Spec
spec = describe "Relative imports (pure helpers)" $ do

  describe "classifyImport" $ do
    it "treats a name without a slash as a bare import" $ do
      classifyImport "prelude" `shouldBe` BareImport
      classifyImport "sg-succession-domain" `shouldBe` BareImport

    it "keeps the dotted and suffixed spellings bare, as they resolve today" $ do
      classifyImport "foo.l4" `shouldBe` BareImport
      classifyImport "a.b" `shouldBe` BareImport

    it "treats a name with a slash as a path import" $ do
      classifyImport "../other-row/mod" `shouldBe` PathImport
      classifyImport "./helper/x" `shouldBe` PathImport
      classifyImport "sub/core" `shouldBe` PathImport

    it "refuses a leading slash as the reserved root-relative form" $
      classifyImport "/abs/mod" `shouldBe` RootedImport

    it "does not take a backslash for a separator" $
      classifyImport "sub\\core" `shouldBe` BareImport

  describe "pathImportFile" $ do
    it "appends .l4" $
      pathImportFile "../b/mod" `shouldBe` joinPath ["..", "b", "mod.l4"]

    it "does not double an .l4 suffix" $
      pathImportFile "../b/mod.l4" `shouldBe` joinPath ["..", "b", "mod.l4"]

    it "drops empty segments" $
      pathImportFile "a//b" `shouldBe` joinPath ["a", "b.l4"]

  describe "collapsePath" $ do
    it "removes . segments" $
      collapsePath (joinPath [".", "a", ".", "b.l4"])
        `shouldBe` collapsed (joinPath ["a", "b.l4"]) False

    it "removes x/.. pairs" $
      collapsePath (joinPath ["sub", "..", "core.l4"])
        `shouldBe` collapsed "core.l4" False

    it "collapses a path that comes back through a sibling" $
      collapsePath (joinPath ["rows", "a", "..", "b", "mod.l4"])
        `shouldBe` collapsed (joinPath ["rows", "b", "mod.l4"]) False

    it "gives one spelling to two routes to one file" $
      collapsePath (joinPath ["a", "..", "shared", "core.l4"])
        `shouldBe` collapsePath (joinPath ["b", "..", "shared", "core.l4"])

    it "reports a relative path that climbs above its start as escaped" $
      collapsePath (joinPath ["..", "x.l4"])
        `shouldBe` collapsed (joinPath ["..", "x.l4"]) True

    it "keeps a surviving leading .. visible after popping what it can" $
      collapsePath (joinPath ["a", "..", "..", "..", "etc", "passwd.l4"])
        `shouldBe` collapsed (joinPath ["..", "..", "etc", "passwd.l4"]) True

    it "reports an absolute path that climbs above the root as escaped" $
      collapsePath "/a/../../etc/passwd.l4"
        `shouldBe` collapsed "/etc/passwd.l4" True

    it "does not call a path that stays inside its start escaped" $
      (collapsePath (joinPath ["a", "b", "..", "..", "c.l4"])).cpEscaped
        `shouldBe` False

    it "returns . for a path that collapses to nothing" $
      collapsePath (joinPath ["a", ".."]) `shouldBe` collapsed "." False
