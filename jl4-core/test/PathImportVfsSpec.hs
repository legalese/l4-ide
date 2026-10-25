{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | Path imports in the pure resolver, the one the browser build uses
-- (specs/proposals/RELATIVE-IMPORTS-SPEC.md §4.2 to §4.5, §6 "wasm" row).
--
-- The files are a map from path to source, and nothing else is reachable: there
-- is no file system. The fixtures ("PathImportFixtures") are the ones in
-- @jl4\/tests-cli\/fixtures\/relative-import\/@, written out as sources.
--
-- One difference from the CLI is on purpose and is checked below: a bare name
-- inside a supplied file is looked up by name among the supplied files (as it
-- always was), not beside the file that writes it. The CLI finds @neighbour@
-- beside @rows\/b\/mod.l4@; here it has to be supplied as @neighbour.l4@.
--
-- What the same programs evaluate to is in "ApiImportContextSpec".
module PathImportVfsSpec (spec) where

import Control.Monad (forM_, void)
import Data.IORef (modifyIORef', newIORef, readIORef)
import qualified Data.Text as Text
import Data.Text (Text)
import Test.Hspec

import L4.API.VirtualFS
import L4.Import.Resolution
  ( BareHit (..)
  , ImportLookup (..)
  , Importer (..)
  , dependenciesFirst
  , typecheckWithDependencies
  )
import L4.TypeCheck (severity)
import L4.TypeCheck.Types (CheckResult (errors), Severity (SError))

import PathImportFixtures

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

-- | The resolver's result, or a failed example that shows what it said.
resolved :: Either [Text] TypeCheckWithDepsResult -> IO TypeCheckWithDepsResult
resolved = \ case
  Left errs -> expectationFailure ("expected the imports to resolve, got: " <> show errs) >> fail "unreachable"
  Right r -> pure r

-- | What the resolver said when it refused, as one text.
refusal :: Either [Text] TypeCheckWithDepsResult -> IO Text
refusal = \ case
  Left errs -> pure (Text.intercalate "\n" errs)
  Right _ -> expectationFailure "expected the resolver to refuse" >> fail "unreachable"

firstLine :: Text -> Text
firstLine = Text.takeWhile (/= '\n')

-- | The modules a program resolved, by the name the resolver shows for them.
moduleNames :: TypeCheckWithDepsResult -> [Text]
moduleNames r = map (.riModuleName) r.tcdResolvedImports

-- | How many errors a resolved module carries.
errorCount :: ResolvedImport -> Int
errorCount ri = length [ () | e <- ri.riTypeChecked.errors, severity e == SError ]

-- | A lookup that serves the supplied files and the embedded libraries, as the
-- API does, and writes down every path it is asked for.
spyingLookup :: (Text -> Maybe BareHit) -> VFS -> IO (ImportLookup IO, IO [FilePath])
spyingLookup bare vfs = do
  asked <- newIORef []
  let byPath p = do
        modifyIORef' asked (p :)
        pure (vfsLookupPath p vfs)
  pure (ImportLookup { ilBare = pure . bare, ilPath = byPath }, reverse <$> readIORef asked)

-- ----------------------------------------------------------------------------

spec :: Spec
spec = describe "Path imports in the pure resolver (browser build)" $ do

  describe "the files, keyed by path" $ do
    let vfs = vfsFromList
          [ ("rows/b/mod.l4", "a")
          , ("rows/b/bare-key", "b")
          , ("./rows/c/../c/dot.l4", "c")
          ]

    it "finds a file by its collapsed path, with the extension" $
      vfsLookupPath "rows/b/mod.l4" vfs `shouldBe` Just "a"

    it "finds a file stored without the extension" $
      vfsLookupPath "rows/b/bare-key.l4" vfs `shouldBe` Just "b"

    it "finds a file whose key is spelt with . and .. segments" $
      vfsLookupPath "rows/c/dot.l4" vfs `shouldBe` Just "c"

    it "does not find a path that is not there" $
      vfsLookupPath "rows/b/other.l4" vfs `shouldBe` Nothing

    it "leaves bare lookups alone: a nested key is not a module name" $ do
      vfsLookup "mod" vfs `shouldBe` Nothing
      vfsLookup "rows/b/mod" vfs `shouldBe` Just "a"

    it "never looks up a path that climbs above the start of the map" $
      -- Even a key that is spelt the same way is not found by it.
      vfsLookupPath "../planted.l4" (vfsFromList [("../planted.l4", "x"), ("planted.l4", "y")])
        `shouldBe` Nothing

  describe "a path import resolves from the supplied files" $ do
    it "imports a file in a folder, from a document at the top" $ do
      let vfs = vfsFromList [("lib/defs.l4", "defmarker MEANS 5\n")]
      r <- resolved (checkWithImports vfs "IMPORT `lib/defs`\n\nprobe MEANS defmarker\n")
      r.tcdSuccess `shouldBe` True
      moduleNames r `shouldBe` ["lib/defs"]

    it "accepts the .l4 in the written path" $ do
      let vfs = vfsFromList [("lib/defs.l4", "defmarker MEANS 5\n")]
      r <- resolved (checkWithImports vfs "IMPORT `lib/defs.l4`\n\nprobe MEANS defmarker\n")
      r.tcdSuccess `shouldBe` True

    it "imports a sibling folder's module and a ./ neighbour, as the rows fixture does" $ do
      r <- resolved (checkWithImportsAt rowsFiles "rows/a/main.l4" rowsMain)
      r.tcdSuccess `shouldBe` True
      -- helper, mod, and the prelude that both of them import, and neighbour
      moduleNames r `shouldMatchList` ["rows/b/mod", "rows/a/helper", "prelude", "neighbour"]

    it "reads the document's path like a written one: a leading slash, a missing .l4 and a . do not matter" $
      forM_ ["rows/a/main.l4", "/rows/a/main.l4", "rows/a/main", "rows/./a/main.l4"] \path -> do
        r <- resolved (checkWithImportsAt rowsFiles path rowsMain)
        r.tcdSuccess `shouldBe` True
        moduleNames r `shouldMatchList` ["rows/b/mod", "rows/a/helper", "prelude", "neighbour"]

    it "lets a module that was reached by name import by path, from the top of the map" $ do
      let vfs = vfsFromList
            [ ("top.l4", "IMPORT `sub/x`\n\ntopmarker MEANS xmarker + 1\n")
            , ("sub/x.l4", "xmarker MEANS 4\n")
            ]
      r <- resolved (checkWithImports vfs "IMPORT top\n\nprobe MEANS topmarker\n")
      r.tcdSuccess `shouldBe` True
      moduleNames r `shouldMatchList` ["top", "sub/x"]

  describe "one file is one module however it was reached" $ do
    it "loads the module two siblings share once, and its error once" $ do
      r <- resolved (checkWithImports diamondFiles diamondTop)
      moduleNames r `shouldMatchList` ["a/x", "b/y", "shared/core"]
      [ errorCount ri | ri <- r.tcdResolvedImports, ri.riModuleName == "shared/core" ]
        `shouldBe` [1]
      -- and no other module has an error of its own
      sum (map errorCount r.tcdResolvedImports) `shouldBe` 1

    it "loads it once when it is also reached by a different spelling" $ do
      -- The two importers write `../shared/core`; the document writes `shared/core`.
      let top = "IMPORT `a/x`\nIMPORT `shared/core`\n\ntopvalue MEANS xvalue\n"
      r <- resolved (checkWithImports diamondFiles top)
      moduleNames r `shouldMatchList` ["a/x", "shared/core"]

    it "treats `sub/../core` and the bare `core` as one module, in either order" $ do
      let vfs = vfsFromList [("core.l4", identityCore)]
          flipped = "IMPORT core\nIMPORT `sub/../core`\n\ntwice MEANS coremarker + coremarker\n"
      forM_ [identityTop, flipped] \src -> do
        r <- resolved (checkWithImports vfs src)
        moduleNames r `shouldBe` ["core"]
        r.tcdSuccess `shouldBe` True

    it "treats a file reached by climbing out of a folder and back in as the one already loaded" $ do
      let vfs = vfsFromList [("a/helper.l4", backHelper), ("b/mod.l4", backMod)]
      r <- resolved (checkWithImportsAt vfs "a/main.l4" backMain)
      moduleNames r `shouldMatchList` ["a/helper", "b/mod"]

    it "says so when two different sources claim one address" $ do
      -- A file at the top of the map is at the address of the library module of
      -- its name. Reaching both in one program is refused, not merged.
      let vfs = vfsFromList [("prelude.l4", "mine MEANS 1\n")]
      msg <- refusal (checkWithImports vfs "IMPORT `./prelude`\nIMPORT math\n\nprobe MEANS mine\n")
      msg `shouldSatisfy` Text.isPrefixOf "Two different modules are both called prelude"

    it "serves such a file when the library module of its name is not reached" $ do
      let vfs = vfsFromList [("prelude.l4", "mine MEANS 1\n")]
      r <- resolved (checkWithImports vfs "IMPORT `./prelude`\n\nprobe MEANS mine\n")
      r.tcdSuccess `shouldBe` True

  describe "the order the modules are evaluated in" $ do
    it "puts every module after the modules it imports, on a diamond" $ do
      let vfs = vfsFromList
            [ ("left", "IMPORT bottom\n\nleftvalue MEANS bottomvalue + 1\n")
            , ("right", "IMPORT bottom\n\nrightvalue MEANS bottomvalue + 2\n")
            , ("bottom", "bottomvalue MEANS 10\n")
            ]
      r <- resolved (checkWithImports vfs "IMPORT left\nIMPORT right\n\nx MEANS 1\n")
      -- as resolved, `right` is listed before the `bottom` it needs only once reversed
      map (.riModuleName) r.tcdResolvedImports `shouldBe` ["left", "bottom", "right"]
      map (.riModuleName) (dependenciesFirst r.tcdResolvedImports) `shouldBe` ["bottom", "left", "right"]

    it "does the same for modules that import one another by path" $ do
      r <- resolved (checkWithImportsAt backFiles "a/main.l4" backMain)
      let order = map (.riModuleName) (dependenciesFirst r.tcdResolvedImports)
      order `shouldBe` ["a/helper", "b/mod"]

  describe "a path import never finds an embedded library" $ do
    let vfs = vfsFromList [("lib/prelude.l4", "libmarker MEANS 77\n")]

    it "gives the supplied file for ``lib/prelude``" $ do
      r <- resolved (checkWithImports vfs "IMPORT `lib/prelude`\n\nprobe MEANS libmarker\n")
      r.tcdSuccess `shouldBe` True
      map (.riSource) r.tcdResolvedImports `shouldBe` ["libmarker MEANS 77\n"]

    it "still gives the embedded one for the bare ``prelude``, in the same program" $ do
      r <- resolved (checkWithImports vfs "IMPORT prelude\nIMPORT `lib/prelude`\n\nprobe MEANS libmarker + sum (LIST 1, 2)\n")
      r.tcdSuccess `shouldBe` True
      let sources = [ (ri.riModuleName, Just ri.riSource) | ri <- r.tcdResolvedImports ]
      lookup "prelude" sources `shouldBe` Just (lookupEmbeddedLibrary "prelude")
      lookup "lib/prelude" sources `shouldBe` Just (Just "libmarker MEANS 77\n")

    it "does not find a library that no file of that path supplies" $ do
      msg <- refusal (checkWithImports emptyVFS "IMPORT `lib/prelude`\n\nprobe MEANS 1\n")
      firstLine msg `shouldBe` "I could not find a module at this path: lib/prelude"

  describe "a bare name resolves as it always did" $ do
    it "prefers the embedded library over a supplied file of the same name (smucclaw/l4-ide#989)" $ do
      -- Kept as it is in this change, and said so in the documentation.
      let vfs = vfsFromList [("prelude.l4", "bogusmarker MEANS 1\n")]
      r <- resolved (checkWithImports vfs "IMPORT prelude\n\nprobe MEANS sum (LIST 1, 2)\n")
      r.tcdSuccess `shouldBe` True
      map (.riSource) r.tcdResolvedImports `shouldBe` [maybe "" id (lookupEmbeddedLibrary "prelude")]

    it "finds a supplied file by its bare key, with or without the extension" $
      forM_ ["helper", "helper.l4"] \key -> do
        let vfs = vfsFromList [(key, "helpmarker MEANS 3\n")]
        r <- resolved (checkWithImports vfs "IMPORT helper\n\nprobe MEANS helpmarker\n")
        r.tcdSuccess `shouldBe` True

    it "does not look beside the importing file: a nested key is not a bare module" $ do
      -- The CLI finds `neighbour` beside rows/b/mod.l4. Here it has to be at the top.
      let vfs = vfsFromList [("rows/b/mod.l4", rowsMod), ("rows/b/neighbour.l4", rowsNeighbour)]
      msg <- refusal (checkWithImports vfs "IMPORT `rows/b/mod`\n\nprobe MEANS modmarker\n")
      msg `shouldBe` "Module not found: neighbour (searched: embedded libraries, project VFS)"

    it "reports a missing module in the words it always used" $ do
      msg <- refusal (checkWithImports emptyVFS "IMPORT nonexistent\n\nx MEANS 1\n")
      msg `shouldBe` "Module not found: nonexistent (searched: embedded libraries, project VFS)"

    it "reports a cycle in the words it always used" $ do
      let vfs = vfsFromList [("ca", "IMPORT cb\n"), ("cb", "IMPORT ca\n")]
      msg <- refusal (checkWithImports vfs "IMPORT ca\n\nx MEANS 1\n")
      msg `shouldBe` "Cyclic import detected: ca -> cb -> ca"

    it "gives the default document the address and the folder it had" $ do
      let vfs = vfsFromList [("helper.l4", "helpmarker MEANS 3\n")]
          src = "IMPORT helper\n\nprobe MEANS helpmarker\n"
      plain <- resolved (checkWithImports vfs src)
      named <- resolved (checkWithImportsAt vfs "main" src)
      named.tcdUri `shouldBe` plain.tcdUri
      map (.riUri) named.tcdResolvedImports `shouldBe` map (.riUri) plain.tcdResolvedImports
      plain.tcdUri `shouldBe` moduleNameToProjectUri "main"

  describe "what a path import refuses" $ do
    it "names the path it looked for when the file is not there" $ do
      msg <- refusal (checkWithImportsAt emptyVFS "rows/a/main.l4" "IMPORT `../nowhere/mod`\n\nx MEANS 1\n")
      firstLine msg `shouldBe` "I could not find a module at this path: ../nowhere/mod"
      msg `shouldSatisfy` Text.isInfixOf "Relative to rows/a/main.l4 that is rows/nowhere/mod.l4, which does not exist."

    it "refuses a path that climbs above the start of the map, and a planted file is not taken" $ do
      -- A document at the top of the map importing `../planted`. The planted
      -- file is in the map twice: at the escaped key, and at the key it would
      -- have to be at if it were inside.
      let planted = vfsFromList [("../planted.l4", "plantedmarker MEANS 99\n"), ("planted.l4", "plantedmarker MEANS 99\n")]
      msg <- refusal (checkWithImports planted "IMPORT `../planted`\n\nprobe MEANS plantedmarker\n")
      firstLine msg `shouldBe` "This import leaves the root of this deployment: ../planted"

    it "takes the same file when the document is deep enough for the path to stay inside (the positive control)" $ do
      let planted = vfsFromList [("planted.l4", "plantedmarker MEANS 99\n")]
      r <- resolved (checkWithImportsAt planted "work/main.l4" "IMPORT `../planted`\n\nprobe MEANS plantedmarker\n")
      r.tcdSuccess `shouldBe` True

    it "makes no lookup at all before refusing" $ do
      let planted = vfsFromList [("../planted.l4", "x MEANS 1\n"), ("planted.l4", "x MEANS 1\n")]
      (lookups, asked) <- spyingLookup (const Nothing) planted
      let importer = Importer { impLabel = "main.l4", impDirectory = Just "." }
      result <- typecheckWithDependencies lookups importer (moduleNameToProjectUri "main") "IMPORT `../planted`\n\nprobe MEANS x\n"
      void (refusal result)
      asked >>= (`shouldBe` [])

    it "refuses a path that climbs out of a folder past the top, naming where it would land" $ do
      msg <- refusal (checkWithImportsAt emptyVFS "a/main.l4" "IMPORT `../../x`\n\nx MEANS 1\n")
      firstLine msg `shouldBe` "This import leaves the root of this deployment: ../../x"
      msg `shouldSatisfy` Text.isInfixOf "Relative to a/main.l4 that would be ../x.l4"

    it "refuses a leading slash, whatever the map holds, with the same words" $ do
      let vfs = vfsFromList [("abs/mod.l4", "x MEANS 1\n"), ("/abs/mod.l4", "x MEANS 1\n")]
      (lookups, asked) <- spyingLookup (const Nothing) vfs
      let importer = Importer { impLabel = "main.l4", impDirectory = Just "." }
      result <- typecheckWithDependencies lookups importer (moduleNameToProjectUri "main") "IMPORT `/abs/mod`\n\nx MEANS 1\n"
      msg <- refusal result
      firstLine msg `shouldBe` "This import leaves the root of this deployment: /abs/mod"
      asked >>= (`shouldBe` [])

    it "says an importer with no folder cannot import by path, as an embedded library cannot" $ do
      -- No shipped library imports by path, so one is made up: a lookup that
      -- serves a module of its own, the way the embedded libraries are served,
      -- with no folder.
      let embedded name
            | name == "fakelib" = Just BareHit { bhSource = "IMPORT `../x`\n\nfake MEANS 1\n", bhDirectory = Nothing }
            | otherwise = Nothing
          vfs = vfsFromList [("x.l4", "x MEANS 1\n"), ("../x.l4", "x MEANS 1\n")]
      (lookups, asked) <- spyingLookup embedded vfs
      let importer = Importer { impLabel = "main.l4", impDirectory = Just "." }
      result <- typecheckWithDependencies lookups importer (moduleNameToProjectUri "main") "IMPORT fakelib\n\nprobe MEANS fake\n"
      msg <- refusal result
      firstLine msg `shouldBe` "This import is relative, but project:/fakelib.l4 has no directory to be relative to."
      asked >>= (`shouldBe` [])

    it "uses the words the other runtimes use" $ do
      -- jl4-lsp/test/RelativeImportSpec.hs pins these first lines for the rules.
      notFound <- refusal (checkWithImports emptyVFS "IMPORT `sub/x`\n\nx MEANS 1\n")
      firstLine notFound `shouldBe` "I could not find a module at this path: sub/x"

  describe "the open document is the module at its own address" $ do
    -- A file the document imports may import the document back. The document is
    -- the live text, and a copy of it among the files is never read in its place,
    -- so this is a cycle, as it is for `l4` on the same tree.
    let docLive = "IMPORT `../b/y`\n\nxv MEANS 1\n\n#EVAL yv\n"
        backImporter = ("b/y.l4", "IMPORT `../a/x`\n\nyv MEANS xv + 1\n")
        expectedCycle = "Cyclic import detected: a/x -> b/y -> a/x"

    it "refuses a back-import when the files hold no copy of the document" $ do
      msg <- refusal (checkWithImportsAt (vfsFromList [backImporter]) "a/x.l4" docLive)
      msg `shouldBe` expectedCycle

    it "refuses it when the files hold an identical copy" $ do
      msg <- refusal (checkWithImportsAt (vfsFromList [backImporter, ("a/x.l4", "xv MEANS 1\n")]) "a/x.l4" docLive)
      msg `shouldBe` expectedCycle

    it "refuses it when the files hold a stale copy, and does not run on the copy's text" $ do
      msg <- refusal (checkWithImportsAt (vfsFromList [backImporter, ("a/x.l4", "xv MEANS 41\n")]) "a/x.l4" docLive)
      msg `shouldBe` expectedCycle

    it "refuses a document that imports itself by path" $ do
      msg <- refusal (checkWithImportsAt emptyVFS "a/main.l4" "IMPORT `./main`\n\nx MEANS 1\n")
      msg `shouldBe` "Cyclic import detected: a/main -> a/main"

    it "refuses a back-import by bare name, with the default document at \"main\" and a main.l4 among the files" $ do
      let vfs = vfsFromList [("y.l4", "IMPORT main\n\nyv MEANS xv + 1\n"), ("main.l4", "xv MEANS 41\n")]
      msg <- refusal (checkWithImports vfs "IMPORT y\n\nxv MEANS 1\n\n#EVAL yv\n")
      msg `shouldBe` "Cyclic import detected: main -> y -> main"

    it "refuses it by bare name when the document has a path of its own, with a stale copy among the files" $ do
      let vfs = vfsFromList [("y.l4", "IMPORT helper\n\nyv MEANS 1\n"), ("helper.l4", "helpermarker MEANS 41\n")]
      msg <- refusal (checkWithImportsAt vfs "helper.l4" "IMPORT y\n\nhelpermarker MEANS 1\n")
      msg `shouldBe` "Cyclic import detected: helper -> y -> helper"

    it "does not mind a copy of the document among the files when nothing imports it back (the positive control)" $ do
      let vfs = vfsFromList [("b/y.l4", "yv MEANS 1\n"), ("a/x.l4", "xv MEANS 41\n")]
      r <- resolved (checkWithImportsAt vfs "a/x.l4" "IMPORT `../b/y`\n\nxv MEANS yv + 1\n")
      r.tcdSuccess `shouldBe` True
      moduleNames r `shouldBe` ["b/y"]

  describe "two files of the page at one address, which only the Haskell functions can build" $ do
    -- l4_set_files refuses a table in which two keys are one path, so the exports
    -- cannot reach this; vfsFromList can.
    it "says two of the supplied files are at one address, and does not blame a standard library module" $ do
      let vfs = vfsFromList [("core.l4", "corev MEANS 7\n"), ("./core.l4", "corev MEANS 8\n")]
      msg <- refusal (checkWithImports vfs "IMPORT core\nIMPORT `./core`\n\nprobe MEANS corev\n")
      msg `shouldSatisfy` Text.isPrefixOf "Two different modules are both called core"
      msg `shouldSatisfy` Text.isInfixOf "Two of the files you supplied have the address core.l4"
      msg `shouldSatisfy` (not . Text.isInfixOf "standard library")

    it "keeps the sentence about the standard library for the name of a library module" $ do
      let vfs = vfsFromList [("./prelude.l4", "mine MEANS 1\n")]
      msg <- refusal (checkWithImports vfs "IMPORT `./prelude`\nIMPORT math\n\nprobe MEANS mine\n")
      msg `shouldSatisfy` Text.isInfixOf "has the name of a standard library module"
      msg `shouldSatisfy` (not . Text.isInfixOf "Two of the files you supplied")

  describe "a bare name is not shortened at its last dot (a limit, stated in the docs)" $ do
    it "reads IMPORT a.b as a module called a.b, and does not find a.l4" $ do
      msg <- refusal (checkWithImports (vfsFromList [("a.l4", "av MEANS 1\n")]) "IMPORT a.b\n\nx MEANS 1\n")
      msg `shouldBe` "Module not found: a.b (searched: embedded libraries, project VFS)"

    it "makes IMPORT foo.l4 a module of its own, beside the path to the same file" $ do
      let vfs = vfsFromList [("foo.l4", "foov MEANS 3\n")]
      r <- resolved (checkWithImports vfs "IMPORT foo.l4\nIMPORT `./foo`\n\nprobe MEANS foov\n")
      moduleNames r `shouldMatchList` ["foo.l4", "foo"]
      r.tcdSuccess `shouldBe` False

  describe "a module that imports out of its own folder" $ do
    -- The imports of a module are stamped with the file each resolved to, from the
    -- folder of the module that writes them; the stamps are what orders the
    -- modules for evaluation. Stamped from the top of the files, ../shared/core
    -- written in a/x.l4 would leave the stamp off and the order blind to the edge.
    it "comes after the module it imports, whatever folder the document is in" $ do
      let vfs = vfsFromList [("shared/core.l4", "corev MEANS 10\n"), ("a/x.l4", "IMPORT `../shared/core`\n\nxv MEANS corev + 1\n")]
      r <- resolved (checkWithImports vfs "IMPORT `a/x`\n\n#EVAL xv\n")
      map (.riModuleName) r.tcdResolvedImports `shouldBe` ["a/x", "shared/core"]
      map (.riModuleName) (dependenciesFirst r.tcdResolvedImports) `shouldBe` ["shared/core", "a/x"]

    it "keeps a diamond over one file in order when the two importers spell its path differently" $ do
      let core = "DECLARE Colour IS ONE OF red, blue\n\nfavourite MEANS red\n"
          vfs = vfsFromList
            [ ("shared/core.l4", core)
            , ("a/x.l4", "IMPORT `../shared/core`\n\nGIVEN c IS A Colour\nDECIDE xok c IF c EQUALS red\n")
            , ("b/y.l4", "IMPORT `../shared/../shared/core`\n\nGIVEN c IS A Colour\nDECIDE yok c IF c EQUALS red\n")
            ]
      r <- resolved (checkWithImports vfs "IMPORT `a/x`\nIMPORT `b/y`\n\n#EVAL yok favourite\n")
      moduleNames r `shouldMatchList` ["a/x", "b/y", "shared/core"]
      case map (.riModuleName) (dependenciesFirst r.tcdResolvedImports) of
        "shared/core" : _ -> pure ()
        other -> expectationFailure ("the shared module should come first, got " <> show other)

  describe "a document path is read as written (the jl4-wasm README says how)" $ do
    let vfs = vfsFromList [("b/mod.l4", "modmarker MEANS 1\n"), ("rows/b/mod.l4", "modmarker MEANS 2\n")]
        doc = "IMPORT `../b/mod`\n\nprobe MEANS modmarker\n"

    it "makes the document the file rows/a.l4 when the path ends in a slash" $ do
      -- rows/a.l4 is in rows, so ../b/mod is b/mod.l4; the folder rows/a would give rows/b/mod.l4
      r <- resolved (checkWithImportsAt vfs "rows/a/" doc)
      [ ri.riSource | ri <- r.tcdResolvedImports ] `shouldBe` ["modmarker MEANS 1\n"]

    it "takes a backslash as part of a file's name, not as a separator" $ do
      msg <- refusal (checkWithImportsAt vfs "rows\\a\\main.l4" doc)
      firstLine msg `shouldBe` "This import leaves the root of this deployment: ../b/mod"

    it "accepts a path that climbs above the top, and then refuses every path import from the document" $ do
      msg <- refusal (checkWithImportsAt vfs "../outside/main.l4" "IMPORT `./x`\n\nprobe MEANS 1\n")
      firstLine msg `shouldBe` "This import leaves the root of this deployment: ./x"
