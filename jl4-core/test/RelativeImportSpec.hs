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

import qualified Data.Map.Strict as Map
import System.FilePath (joinPath)
import Test.Hspec

import L4.Import.ProjectManifest
  ( AliasProblem (..)
  , ManifestProblem (..)
  , ProjectManifest (..)
  , aliasFolder
  , parseProjectManifest
  , renderManifestProblem
  )
import L4.Import.Resolution
  ( CollapsedPath (..)
  , ImportForm (..)
  , classifyImport
  , collapsePath
  , pathImportFile
  , projectMarkerFile
  , splitAlias
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

    it "treats a leading slash as a root-relative import" $ do
      classifyImport "/subjects/vn/nouns" `shouldBe` RootRelativeImport
      classifyImport "/x" `shouldBe` RootRelativeImport
      classifyImport "//x" `shouldBe` RootRelativeImport

    it "does not take a slash that is not leading for a root" $
      classifyImport "a/b/" `shouldBe` PathImport

    it "does not take a backslash for a separator" $
      classifyImport "sub\\core" `shouldBe` BareImport

    -- Aliases (§4.7 C6, PROPOSED, FOR MENG, not ruled).
    it "treats an @ and a slash as an alias import, tested before the relative path" $ do
      classifyImport "@vn10/nouns" `shouldBe` AliasImport
      classifyImport "@vn10/a/b" `shouldBe` AliasImport
      classifyImport "@/x" `shouldBe` AliasImport

    it "keeps an @ without a slash a bare name, as it is today" $
      classifyImport "@vn10" `shouldBe` BareImport

    it "does not take an @ that is not leading for an alias" $ do
      classifyImport "./@vn10/nouns" `shouldBe` PathImport
      classifyImport "sub/@vn10/nouns" `shouldBe` PathImport
      classifyImport "/@vn10/nouns" `shouldBe` RootRelativeImport

  describe "splitAlias" $ do
    it "splits the alias from the path under it at the first slash" $ do
      splitAlias "@vn10/nouns" `shouldBe` Just ("vn10", "nouns")
      splitAlias "@vn10/a/b" `shouldBe` Just ("vn10", "a/b")

    it "keeps an empty alias and an empty path, which then fail where they are looked up" $ do
      splitAlias "@/x" `shouldBe` Just ("", "x")
      splitAlias "@vn10/" `shouldBe` Just ("vn10", "")

    it "is Nothing for a name that is not an alias" $ do
      splitAlias "vn10/x" `shouldBe` Nothing
      splitAlias "@vn10" `shouldBe` Nothing

  describe "pathImportFile" $ do
    it "appends .l4" $
      pathImportFile "../b/mod" `shouldBe` joinPath ["..", "b", "mod.l4"]

    it "does not double an .l4 suffix" $
      pathImportFile "../b/mod.l4" `shouldBe` joinPath ["..", "b", "mod.l4"]

    it "drops empty segments" $
      pathImportFile "a//b" `shouldBe` joinPath ["a", "b.l4"]

    it "reads a root-relative name from the root, without its leading slash" $
      pathImportFile "/subjects/vn/nouns" `shouldBe` joinPath ["subjects", "vn", "nouns.l4"]

    it "reads //x as /x, since empty segments are dropped" $
      pathImportFile "//subjects/nouns.l4" `shouldBe` pathImportFile "/subjects/nouns"

    it "keeps a climbing root-relative name visible to collapsePath" $
      collapsePath (pathImportFile "/../planted")
        `shouldBe` collapsed (joinPath ["..", "planted.l4"]) True

  describe "projectMarkerFile" $
    it "is the file name that marks a project root" $
      projectMarkerFile `shouldBe` "l4-project.json"

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

  -- The project file (§4.7 C6, PROPOSED, FOR MENG, not ruled).
  describe "parseProjectManifest" $ do
    let aliasesOf = fmap (.aliases) . parseProjectManifest

    it "reads the smallest file, {}, as a project with no aliases" $
      aliasesOf "{}" `shouldBe` Right Map.empty

    it "reads the aliases of a project" $
      aliasesOf "{\"aliases\": {\"vn10\": \"subjects/vn/nd67\", \"sg\": \"subjects/sg\"}}"
        `shouldBe` Right (Map.fromList [("vn10", "subjects/vn/nd67"), ("sg", "subjects/sg")])

    it "ignores keys it does not know, at the top and beside the aliases" $
      aliasesOf "{\"name\": \"vn\", \"aliases\": {\"a\": \"x\"}, \"later\": [1, 2]}"
        `shouldBe` Right (Map.fromList [("a", "x")])

    -- Another reader of the same file (a deploy tool or an editor written in
    -- TypeScript) would keep the last, as JSON.parse does; the docs say so.
    it "keeps the first of an alias written twice" $
      aliasesOf "{\"aliases\": {\"a\": \"first\", \"a\": \"second\"}}"
        `shouldBe` Right (Map.fromList [("a", "first")])

    it "ignores a byte-order mark" $
      aliasesOf "\xFEFF{}" `shouldBe` Right Map.empty

    describe "a file that is not JSON" $ do
      let notJson t = either (Just . renderManifestProblem) (const Nothing) (parseProjectManifest t)

      it "names the line and column of the first character that cannot be there: a trailing comma" $
        notJson "{\n  \"aliases\": {\n    \"vn10\": \"subjects/vn\",\n  }\n}\n"
          `shouldBe` Just "It is not valid JSON: line 4, column 3, unexpected `}`."

      it "names it for a missing colon" $
        parseProjectManifest "{\"aliases\": {\"a\" \"x\"}}"
          `shouldBe` Left (ManifestNotJson 1 18 (Just '"'))

      it "names the text after a complete value" $
        parseProjectManifest "{} x" `shouldBe` Left (ManifestNotJson 1 4 (Just 'x'))

      it "counts a column in characters, not bytes" $
        parseProjectManifest "{\"caf\233\": }" `shouldBe` Left (ManifestNotJson 1 10 (Just '}'))

      it "says the file ends too soon, at the end of the file, when nothing is wrong until then" $ do
        parseProjectManifest "{\"aliases\": {\"a\": \"x\"" `shouldBe` Left (ManifestNotJson 1 22 Nothing)
        notJson "{\n" `shouldBe` Just "It is not valid JSON: the file ends before the JSON is complete (line 2, column 1)."

      it "does not take an empty file for {}" $
        parseProjectManifest "" `shouldBe` Left (ManifestNotJson 1 1 Nothing)

    describe "a file that is JSON but not a project file" $ do
      it "wants an object at the top" $
        parseProjectManifest "[]" `shouldBe` Left (ManifestShape "the top level" "must be an object, like {}")

      it "wants the aliases to be an object" $
        fmap renderManifestProblem (either Just (const Nothing) (parseProjectManifest "{\"aliases\": [\"a\"]}"))
          `shouldBe` Just "It is valid JSON, but aliases must be an object that gives each alias a folder, like {\"vn10\": \"subjects/vn\"}."

      it "wants each folder to be text, and names the alias" $
        parseProjectManifest "{\"aliases\": {\"vn10\": 4}}"
          `shouldBe` Left (ManifestShape "aliases.vn10" "must be the folder the alias stands for, written as text")

  describe "aliasFolder" $ do
    it "is the folder, with its . and x/.. worked through" $ do
      aliasFolder "subjects/vn/nd67" `shouldBe` Right (joinPath ["subjects", "vn", "nd67"])
      aliasFolder "./subjects/../shared" `shouldBe` Right "shared"

    it "takes a leading slash and doubled slashes as nothing, as every path import does" $ do
      aliasFolder "/subjects//vn" `shouldBe` Right (joinPath ["subjects", "vn"])

    it "lets the empty folder and . stand for the root itself" $ do
      aliasFolder "" `shouldBe` Right "."
      aliasFolder "." `shouldBe` Right "."

    it "refuses a folder that climbs above the root, and says where it came out" $ do
      aliasFolder "../x" `shouldBe` Left (AliasLeavesRoot (joinPath ["..", "x"]))
      aliasFolder "a/../../x" `shouldBe` Left (AliasLeavesRoot (joinPath ["..", "x"]))

    it "refuses a folder that starts with @, because that would be another alias" $
      aliasFolder "@other/x" `shouldBe` Left (AliasIsAlias "@other/x")

    it "reads ./@x as the folder called @x" $
      aliasFolder "./@x" `shouldBe` Right "@x"

    it "names the alias problem before the escape" $
      aliasFolder "@../" `shouldBe` Left (AliasIsAlias "@../")
