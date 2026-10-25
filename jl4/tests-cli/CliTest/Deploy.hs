-- | Tests for what @l4 deploy@ uploads and what each file is called in the zip.
--
-- Two kinds. The first calls 'planBundle' and 'readBundle' directly, with
-- made-up paths, because most of the cases (two files of one name in different
-- folders, a file in a folder that no import of today's language leads to)
-- cannot be set up with the import forms the typechecker has today. The second
-- runs the real @l4@
-- against a service that only records what it is sent, so that the zip it
-- reads is the one @l4 deploy@ built: a unit test of the plan cannot tell that
-- @bundle@ forgot to use it.
module CliTest.Deploy (spec, fixtures) where

import qualified Codec.Archive.Zip as Zip
import Control.Concurrent (forkIO, killThread)
import Control.Concurrent.MVar (MVar, modifyMVar_, newMVar, readMVar)
import Control.Exception (IOException, bracket, catch, finally, throwIO, try)
import Control.Monad (forever, void)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as BSL
import Data.Char (toLower)
import Data.List (find, isInfixOf)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.Socket
  ( Family(AF_INET)
  , SockAddr(SockAddrInet)
  , Socket
  , SocketType(Stream)
  , accept
  , bind
  , close
  , defaultProtocol
  , listen
  , socket
  , socketPort
  , tupleToHostAddress
  , withSocketsDo
  )
import Network.Socket.ByteString (recv, sendAll)
import System.Directory (canonicalizePath, createDirectory, createDirectoryIfMissing, createDirectoryLink)
import System.Environment (getEnvironment)
import System.Exit (ExitCode(..))
import System.FilePath (pathSeparator, takeDirectory, takeDrive, (</>))
import System.IO.Error (isPermissionError)
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

import CliTest.Common
import qualified L4.API.EmbeddedLibraries as Embedded
import L4.Cli.DeployPlan

-- | Files this module's tests need to exist. 'Main.main' checks them before
-- hspec runs anything.
fixtures :: [FilePath]
fixtures =
  [ flatDir </> "main.l4"
  , flatDir </> "helper.l4"
  , libpathDir </> "project" </> "main.l4"
  , libpathDir </> "project" </> "lib" </> "shared.l4"
  , libpathDir </> "outside" </> "shared.l4"
  , topDir </> "defs.l4"
  , topDir </> "a" </> "main.l4"
  , xdgDir </> "project" </> "main.l4"
  , xdgDir </> "project" </> "data" </> "jl4" </> "libraries" </> "shared.l4"
  , xdgDir </> "outside" </> "data" </> "jl4" </> "libraries" </> "shared.l4"
  ]

flatDir, libpathDir, topDir, xdgDir :: FilePath
flatDir = fixtureDir </> "deploy-bundle" </> "flat"
libpathDir = fixtureDir </> "deploy-bundle" </> "libpath"
-- A project with a library at its top and the main file in a folder below it.
topDir = fixtureDir </> "deploy-bundle" </> "top"
-- A library in the per-user library folder, inside the project and outside it.
xdgDir = fixtureDir </> "deploy-bundle" </> "xdg"

spec :: FilePath -> Spec
spec bin = do
  planSpec
  serviceSpec bin

----------------------------------------------------------------------------
-- The plan, with made-up paths
----------------------------------------------------------------------------

planSpec :: Spec
planSpec = describe "l4 deploy: which files are uploaded, and under what name" $ do
  let -- An absolute path, on whichever platform this runs on.
      at :: [FilePath] -> FilePath
      at = foldl (</>) (if pathSeparator == '\\' then "C:\\" else "/")
      names = fmap (map fst)
      -- The advice depends on whether JL4_LIBRARY_PATH is set in the run.
      messageWith hints = either (T.unpack . renderPlanError hints) (const "")
      message = messageWith (Hints { libraryPathSet = True })
      messageUnset = messageWith (Hints { libraryPathSet = False })
      -- A plan with no IMPORT lines: the cases that are not about where the
      -- service looks for a bare name.
      plan root entry imports = planBundle root entry imports []

  it "names files of one folder by their plain file names, in the order given" $ do
    let r = plan (at ["p"]) (at ["p", "main.l4"])
              [ ("helper", Just (at ["p", "helper.l4"])), ("daydate", Just (at ["p", "daydate.l4"])) ]
    r `shouldBe` Right
      [ ("main.l4", at ["p", "main.l4"])
      , ("helper.l4", at ["p", "helper.l4"])
      , ("daydate.l4", at ["p", "daydate.l4"])
      ]

  it "keeps the folders of a main file in rows/a and a file in rows/b" $ do
    -- The names are relative to the folder the COLLECTED files share (rows),
    -- not to the project root (w) or to the main file's own folder (a).
    -- (No IMPORT of today's language leads from a to ../b; the plan is a
    -- function of paths, and this pins how it names them.)
    let entry = at ["w", "rows", "a", "main.l4"]
        r = plan (at ["w"]) entry [("mod", Just (at ["w", "rows", "a", "..", "b", "mod.l4"]))]
    r `shouldBe` Right
      [ ("a/main.l4", entry)
      , ("b/mod.l4", at ["w", "rows", "b", "mod.l4"])
      ]

  it "keeps two modules of one name in different folders apart" $ do
    let entry = at ["p", "main.l4"]
    names (plan (at ["p"]) entry
            [ ("x/mod", Just (at ["p", "x", "mod.l4"])), ("y/mod", Just (at ["p", "y", "mod.l4"])) ])
      `shouldBe` Right ["main.l4", "x/mod.l4", "y/mod.l4"]
    -- With the main file in a folder of its own, that folder is part of every name.
    names (plan (at ["p"]) (at ["p", "a", "main.l4"])
            [ ("mod", Just (at ["p", "a", "mod.l4"])), ("b/mod", Just (at ["p", "b", "mod.l4"])) ])
      `shouldBe` Right ["a/main.l4", "a/mod.l4", "b/mod.l4"]

  it "stops, naming the file and the project folder, at an import outside the root" $ do
    let root = at ["w", "rows", "a"]
        outside = at ["w", "rows", "b", "mod.l4"]
        r = plan root (at ["w", "rows", "a", "main.l4"]) [("mod", Just (at ["w", "rows", "a", "..", "b", "mod.l4"]))]
    r `shouldBe` Left (OutsideRoot root [outside])
    message r `shouldSatisfy` (outside `isInfixOf`)
    message r `shouldSatisfy` (root `isInfixOf`)

  it "advises putting a library in the project beside its importer, never running from a higher folder or only copying" $ do
    let root = at ["w", "rows", "a"]
        r = plan root (at ["w", "rows", "a", "main.l4"]) [("mod", Just (at ["w", "rows", "b", "mod.l4"]))]
        advice = message r
    -- What to do: the library goes into the project, beside the file that imports it.
    advice `shouldSatisfy` ("inside the project folder, beside the file that imports it" `isInfixOf`)
    -- Both places l4 finds a library that the service does not read are named,
    -- with what differs between them: a copy is enough for one and not the other.
    advice `shouldSatisfy` ("JL4_LIBRARY_PATH" `isInfixOf`)
    advice `shouldSatisfy` ("per-user library folder" `isInfixOf`)
    advice `shouldSatisfy` ("move the file instead of copying it" `isInfixOf`)
    -- Advice that led to a deployment that compiles and cannot run.
    advice `shouldNotSatisfy` ("Run this from a folder" `isInfixOf`)
    advice `shouldNotSatisfy` ("contains every file" `isInfixOf`)

  it "does not mention JL4_LIBRARY_PATH when it is not set, and still names the per-user library folder" $ do
    let root = at ["w", "rows", "a"]
        r = plan root (at ["w", "rows", "a", "main.l4"]) [("mod", Just (at ["w", "rows", "b", "mod.l4"]))]
        advice = messageUnset r
    advice `shouldSatisfy` ("inside the project folder, beside the file that imports it" `isInfixOf`)
    advice `shouldSatisfy` ("per-user library folder" `isInfixOf`)
    advice `shouldNotSatisfy` ("JL4_LIBRARY_PATH" `isInfixOf`)
    advice `shouldNotSatisfy` ("instead of copying it" `isInfixOf`)
    -- Set, the same refusal says which copy is ignored.
    message r `shouldSatisfy` ("JL4_LIBRARY_PATH is set" `isInfixOf`)

  it "says what the project folder is without claiming that the current folder always is" $ do
    let root = at ["w", "rows", "a"]
        r = plan root (at ["w", "rows", "a", "main.l4"]) [("mod", Just (at ["w", "rows", "b", "mod.l4"]))]
    -- True of every working folder, the top of a drive included.
    message r `shouldSatisfy` ("and that folder is not the top of a drive; otherwise it is the file's own folder" `isInfixOf`)
    message r `shouldNotSatisfy` ("is the current folder when" `isInfixOf`)

  it "counts a folder as outside unless the root is a whole-name ancestor of it" $ do
    -- /w/rows/ab is not inside /w/rows/a, though the name starts the same way.
    let root = at ["w", "rows", "a"]
    plan root (at ["w", "rows", "a", "main.l4"]) [("x", Just (at ["w", "rows", "ab", "x.l4"]))]
      `shouldBe` Left (OutsideRoot root [at ["w", "rows", "ab", "x.l4"]])

  it "names every file that is outside the root, not only the first" $ do
    let root = at ["p"]
    plan root (at ["p", "main.l4"]) [("a", Just (at ["q", "a.l4"])), ("b", Just (at ["p", "b.l4"])), ("c", Just (at ["r", "c.l4"]))]
      `shouldBe` Left (OutsideRoot root [at ["q", "a.l4"], at ["r", "c.l4"]])

  it "leaves out a module that has no file, such as the built-in standard library" $
    plan (at ["p"]) (at ["p", "main.l4"]) [("jl4-embedded:/prelude.l4", Nothing), ("helper", Just (at ["p", "helper.l4"]))]
      `shouldBe` Right [("main.l4", at ["p", "main.l4"]), ("helper.l4", at ["p", "helper.l4"])]

  it "lists a file once, however many imports reach it and however the path is spelled" $
    names (plan (at ["p"]) (at ["p", "main.l4"])
            [ ("h", Just (at ["p", "h.l4"])), ("h again", Just (at ["p", "sub", "..", "h.l4"])) ])
      `shouldBe` Right ["main.l4", "h.l4"]

  it "refuses an import whose file path is not absolute, naming the module" $ do
    let r = plan (at ["p"]) (at ["p", "main.l4"]) [("odd module", Just ("rel" </> "odd.l4"))]
    r `shouldBe` Left (NotAFile "odd module" ("rel" </> "odd.l4"))
    message r `shouldSatisfy` ("odd module" `isInfixOf`)

  it "compares a drive letter without regard to case" $
    if pathSeparator == '\\'
      then names (plan "C:\\p" "C:\\p\\main.l4" [("mod", Just "c:\\p\\sub\\mod.l4")])
             `shouldBe` Right ["main.l4", "sub/mod.l4"]
      else pendingWith "drive letters exist only on Windows (written, not run, on this platform)"

  it "refuses two files that would be stored under one name" $
    distinctNames [("mod.l4", at ["x", "mod.l4"]), ("main.l4", at ["p", "main.l4"]), ("mod.l4", at ["y", "mod.l4"])]
      `shouldBe` Left (SameName "mod.l4" (at ["x", "mod.l4"]) (at ["y", "mod.l4"]))

  describe "an IMPORT must resolve to a file the service looks in" $ do
    -- The service looks a name up beside the importing file and at the top of
    -- the upload, and nowhere else.
    let main_ = at ["p", "main.l4"]
        imp from written to = ImportEdge from written to
        refused r = either (\case UnreachableImport us -> Just us; _ -> Nothing) (const Nothing) r

    it "refuses a library that would be uploaded in a folder of its own, naming the importer, the module and the folder" $ do
      let shared = at ["p", "lib", "shared.l4"]
          r = planBundle (at ["p"]) main_ [("shared", Just shared)] [imp main_ "shared" shared]
      r `shouldBe` Left (UnreachableImport
        [ Unreachable { importerName = "main.l4", written = "shared", importedName = "lib/shared.l4", importedFile = shared } ])
      let said = message r
      said `shouldSatisfy` ("main.l4 imports shared" `isInfixOf`)
      said `shouldSatisfy` ("lib/shared.l4" `isInfixOf`)
      said `shouldSatisfy` ("in the folder lib" `isInfixOf`)
      said `shouldSatisfy` ("only beside the file that imports it and at the top of the upload" `isInfixOf`)
      said `shouldSatisfy` ("JL4_LIBRARY_PATH" `isInfixOf`)
      said `shouldSatisfy` ("per-user library folder" `isInfixOf`)
      said `shouldSatisfy` ("move the file instead of copying it" `isInfixOf`)
      -- The one thing to do is one that works from the importer's folder: a
      -- library at the top of the project is not found by l4 itself (its root
      -- is the main file's folder) unless JL4_LIBRARY_PATH names that folder.
      said `shouldSatisfy` ("Put each library beside the file that imports it, and deploy again." `isInfixOf`)
      said `shouldNotSatisfy` ("or at the top of the project" `isInfixOf`)

    it "says nothing of JL4_LIBRARY_PATH in that refusal when the variable is not set" $ do
      let shared = at ["p", "lib", "shared.l4"]
          r = planBundle (at ["p"]) main_ [("shared", Just shared)] [imp main_ "shared" shared]
      messageUnset r `shouldSatisfy` ("main.l4 imports shared" `isInfixOf`)
      messageUnset r `shouldSatisfy` ("per-user library folder" `isInfixOf`)
      messageUnset r `shouldNotSatisfy` ("JL4_LIBRARY_PATH" `isInfixOf`)

    it "allows a library beside the file that imports it, in a folder or not" $ do
      let entry = at ["p", "a", "main.l4"]
          beside = at ["p", "a", "helper.l4"]
          other = at ["p", "b", "other.l4"]
      names (planBundle (at ["p"]) entry [("helper", Just beside), ("other", Just other)] [imp entry "helper" beside])
        `shouldBe` Right ["a/main.l4", "a/helper.l4", "b/other.l4"]
      names (planBundle (at ["p"]) main_ [("helper", Just (at ["p", "helper.l4"]))] [imp main_ "helper" (at ["p", "helper.l4"])])
        `shouldBe` Right ["main.l4", "helper.l4"]

    it "allows a library at the top of the upload, from a file in a folder" $ do
      let entry = at ["p", "a", "main.l4"]
          top = at ["p", "defs.l4"]
      names (planBundle (at ["p"]) entry [("defs", Just top)] [imp entry "defs" top])
        `shouldBe` Right ["a/main.l4", "defs.l4"]

    it "judges the top of the upload, not the project root: files that all sit in one folder have no folder below it" $ do
      -- The project root is p, but every file is in p/a, so the names are
      -- plain and a library beside the main file is at the top.
      let entry = at ["p", "a", "main.l4"]
          beside = at ["p", "a", "helper.l4"]
      names (planBundle (at ["p"]) entry [("helper", Just beside)] [imp entry "helper" beside])
        `shouldBe` Right ["main.l4", "helper.l4"]

    it "refuses a library in a folder that is neither the importer's nor the top, for an importer that is not the main file" $ do
      -- main.l4 imports mid.l4 at the top, which is fine; mid.l4 then imports
      -- deep/leaf.l4, which is neither beside mid.l4 nor at the top.
      let mid = at ["p", "mid.l4"]
          leaf = at ["p", "deep", "leaf.l4"]
          r = planBundle (at ["p"]) main_ [("mid", Just mid), ("leaf", Just leaf)] [imp main_ "mid" mid, imp mid "leaf" leaf]
      fmap (map (\u -> (u.importerName, u.importedName))) (refused r) `shouldBe` Just [("mid.l4", "deep/leaf.l4")]

    it "names only the lines that fail when other lines are fine" $ do
      let ok = at ["p", "ok.l4"]
          bad = at ["p", "lib", "bad.l4"]
          r = planBundle (at ["p"]) main_ [("ok", Just ok), ("bad", Just bad)] [imp main_ "ok" ok, imp main_ "bad" bad]
      fmap (map (.importedName)) (refused r) `shouldBe` Just ["lib/bad.l4"]

    it "names every line that fails, once each" $ do
      let a = at ["p", "x", "a.l4"]
          b = at ["p", "y", "b.l4"]
          r = planBundle (at ["p"]) main_ [("a", Just a), ("b", Just b)]
                [imp main_ "a" a, imp main_ "b" b, imp main_ "a" a]
      fmap (map (.importedName)) (refused r) `shouldBe` Just ["x/a.l4", "y/b.l4"]

    -- This version of the language reads a name written with a slash as the
    -- bare name of its last part (IMPORT `lib/shared` is `shared`), in l4 and in
    -- the service alike, so such a line is as unreachable for the service as a
    -- bare one and is judged the same way.
    it "judges a name written with a slash as it judges a bare one" $ do
      let shared = at ["p", "lib", "shared.l4"]
          r = planBundle (at ["p"]) main_ [("shared", Just shared)] [imp main_ "lib/shared" shared]
      refused r `shouldBe` Just
        [ Unreachable { importerName = "main.l4", written = "lib/shared", importedName = "lib/shared.l4", importedFile = shared } ]
      message r `shouldSatisfy` ("main.l4 imports lib/shared" `isInfixOf`)
      let entry = at ["w", "rows", "a", "main.l4"]
          modl = at ["w", "rows", "b", "mod.l4"]
      fmap (map (.importedName)) (refused (planBundle (at ["w"]) entry [("mod", Just modl)] [imp entry "../b/mod" modl]))
        `shouldBe` Just ["b/mod.l4"]

    it "allows a name written with a slash when its file is where the service looks" $ do
      let entry = at ["p", "a", "main.l4"]
          beside = at ["p", "a", "helper.l4"]
          top = at ["p", "defs.l4"]
      names (planBundle (at ["p"]) entry [("helper", Just beside), ("defs", Just top)]
              [imp entry "sub/helper" beside, imp entry "lib/defs" top])
        `shouldBe` Right ["a/main.l4", "a/helper.l4", "defs.l4"]

    it "leaves a standard library alone, whether it is built in or read from a file at the top" $ do
      -- Built in: no file, so no line to judge.
      planBundle (at ["p"]) main_ [("jl4-embedded:/prelude.l4", Nothing), ("helper", Just (at ["p", "helper.l4"]))]
          [imp main_ "helper" (at ["p", "helper.l4"])]
        `shouldBe` Right [("main.l4", main_), ("helper.l4", at ["p", "helper.l4"])]
      -- Read from a file at the top of the project: uploaded like any file there.
      names (planBundle (at ["p"]) (at ["p", "a", "main.l4"]) [("prelude", Just (at ["p", "prelude.l4"]))]
              [imp (at ["p", "a", "main.l4"]) "prelude" (at ["p", "prelude.l4"])])
        `shouldBe` Right ["a/main.l4", "prelude.l4"]

    it "does not judge a line whose file the plan does not upload" $
      -- A line that resolved to a file that is not among the imports can only
      -- be a module left out of the upload; there is nothing to place.
      names (planBundle (at ["p"]) main_ [] [imp main_ "gone" (at ["p", "lib", "gone.l4"])])
        `shouldBe` Right ["main.l4"]

  -- The service does not find a file beside its importer when the first folder
  -- of the path has a space, a letter outside A to Z, or one of
  -- # ' + ( ) % , = @ & ! $ ; [ ] in its name (relative file: URIs cannot carry
  -- escapes; a residual of the fix for smucclaw/l4-ide#971, which is closed, and
  -- tracked by no issue yet), though it finds one at the top of the upload.
  -- The plan is stricter: it stops at any character other than ASCII letters,
  -- digits, '.', '-' and '_' in any folder of the path. Only the folder part of
  -- a file's name in the zip counts: files that all sit in one folder are
  -- uploaded by their plain names.
  describe "an imported file's folder must have a name the service can look into" $ do
    let top = at ["p", "defs.l4"]
        imp from written to = ImportEdge from written to
        -- A main file in the folder @folder@ (below p) that imports a library
        -- beside it and one at the top of the project: the shape in which the
        -- folder survives into the zip.
        beside folder =
          let entry = at (["p"] <> folder <> ["main.l4"])
              helper = at (["p"] <> folder <> ["helper.l4"])
          in planBundle (at ["p"]) entry [("helper", Just helper), ("defs", Just top)]
               [imp entry "helper" helper, imp entry "defs" top]
        unfindable r = either (\case UnsafeFolder us -> Just (map (\u -> (u.fileName, u.folderName)) us); _ -> Nothing) (const Nothing) r

    it "refuses a library beside its importer in a folder with a space in its name" $ do
      let r = beside ["my dir"]
      unfindable r `shouldBe` Just [("my dir/helper.l4", "my dir")]
      let said = message r
      said `shouldSatisfy` ("my dir/helper.l4" `isInfixOf`)
      said `shouldSatisfy` (at ["p", "my dir", "helper.l4"] `isInfixOf`)
      said `shouldSatisfy` ("in the folder my dir" `isInfixOf`)
      said `shouldSatisfy` ("The deployed service may not find a file that is imported, because of the name of the folder it is in:" `isInfixOf`)
      said `shouldSatisfy` ("does not find a file beside the file that imports it when the first folder of the file's path in the upload has a space, a letter outside A to Z, or one of # ' + ( ) % , = @ & ! $ ; [ ] in its name" `isInfixOf`)
      said `shouldSatisfy` ("in any folder of the path, not only the first, so it also stops a few names the service would find, for example ok/my dir and a~b" `isInfixOf`)
      said `shouldSatisfy` ("every call would then fail" `isInfixOf`)
      said `shouldSatisfy` ("Rename the folder to use only letters, digits, '.', '-' and '_', and deploy again." `isInfixOf`)
      said `shouldSatisfy` (not . ("so that the check does not depend on how the service reads a path" `isInfixOf`))

    it "refuses a folder named with Hebrew letters, and one with an accented letter" $ do
      -- A folder called "תיקייה" (folder), and "dossier é".
      unfindable (beside ["\1514\1497\1511\1497\1497\1492"]) `shouldBe`
        Just [("\1514\1497\1511\1497\1497\1492/helper.l4", "\1514\1497\1511\1497\1497\1492")]
      unfindable (beside ["dossier \233"]) `shouldBe` Just [("dossier \233/helper.l4", "dossier \233")]

    it "refuses a character outside letters, digits, '.', '-' and '_' wherever it is in the folder's path" $ do
      unfindable (beside ["ok", "no~pe"]) `shouldBe` Just [("ok/no~pe/helper.l4", "ok/no~pe")]
      unfindable (beside ["50%"]) `shouldBe` Just [("50%/helper.l4", "50%")]
      unfindable (beside ["a b", "c"]) `shouldBe` Just [("a b/c/helper.l4", "a b/c")]

    it "refuses each character that the service was measured to fail on" $
      -- A space, and # ' + ( ) % , = @ & ! $ ; [ ] (2026-10-26, specs/as-built/import-resolution.md).
      mapM_ (\c -> let f = "a" <> [c] <> "b" in unfindable (beside [f]) `shouldBe` Just [(f <> "/helper.l4", f)])
        (" #'+()%,=@&!$;[]" :: String)

    it "also refuses names that the service finds, which the plan does not try to tell apart" $ do
      -- The service looks into 'a~b', and into 'ok/my dir' and 'ok/dossier é'
      -- (only the first folder of the path decides there); the plan stops at
      -- all three.
      unfindable (beside ["a~b"]) `shouldBe` Just [("a~b/helper.l4", "a~b")]
      unfindable (beside ["ok", "my dir"]) `shouldBe` Just [("ok/my dir/helper.l4", "ok/my dir")]
      unfindable (beside ["ok", "dossier \233"]) `shouldBe` Just [("ok/dossier \233/helper.l4", "ok/dossier \233")]

    it "allows a folder named with letters, digits, '.', '-' and '_'" $ do
      names (beside ["a"]) `shouldBe` Right ["a/main.l4", "a/helper.l4", "defs.l4"]
      names (beside ["my-dir_2.x"]) `shouldBe` Right ["my-dir_2.x/main.l4", "my-dir_2.x/helper.l4", "defs.l4"]
      names (beside ["Rules", "v1.2"]) `shouldBe` Right ["Rules/v1.2/main.l4", "Rules/v1.2/helper.l4", "defs.l4"]

    it "does not judge the folder of the main file, which the service does not look up" $ do
      let entry = at ["p", "my dir", "main.l4"]
      names (planBundle (at ["p"]) entry [("defs", Just top)] [imp entry "defs" top])
        `shouldBe` Right ["my dir/main.l4", "defs.l4"]

    it "does not judge a library at the top of the project, which has no folder" $ do
      let entry = at ["p", "a b", "main.l4"]
      names (planBundle (at ["p"]) entry [("defs", Just top)] [imp entry "defs" top])
        `shouldBe` Right ["a b/main.l4", "defs.l4"]

    it "does not judge files that all sit in one folder, which are uploaded by their plain names" $ do
      -- {my dir/main.l4, my dir/helper.l4}: the zip holds main.l4 and helper.l4.
      let entry = at ["p", "my dir", "main.l4"]
          helper = at ["p", "my dir", "helper.l4"]
      names (planBundle (at ["p"]) entry [("helper", Just helper)] [imp entry "helper" helper])
        `shouldBe` Right ["main.l4", "helper.l4"]

    it "names a file once, however many lines import it" $ do
      let entry = at ["p", "my dir", "main.l4"]
          helper = at ["p", "my dir", "helper.l4"]
          r = planBundle (at ["p"]) entry [("helper", Just helper), ("defs", Just top)]
                [imp entry "helper" helper, imp entry "helper again" helper, imp entry "defs" top]
      unfindable r `shouldBe` Just [("my dir/helper.l4", "my dir")]

    it "names every file that is refused" $ do
      let entry = at ["p", "my dir", "main.l4"]
          one = at ["p", "my dir", "one.l4"]
          two = at ["p", "my dir", "two.l4"]
          r = planBundle (at ["p"]) entry [("one", Just one), ("two", Just two), ("defs", Just top)]
                [imp entry "one" one, imp entry "two" two, imp entry "defs" top]
      unfindable r `shouldBe` Just [("my dir/one.l4", "my dir"), ("my dir/two.l4", "my dir")]
      message r `shouldSatisfy` ("may not find files that are imported, because of the names of the folders they are in" `isInfixOf`)

    it "reports a library in the wrong folder as that, and not as a folder name" $ do
      -- lib x is neither beside main.l4 nor the top: the advice about the
      -- importer's folder is the one that is true of it.
      let lib = at ["p", "lib x", "shared.l4"]
          r = planBundle (at ["p"]) (at ["p", "main.l4"]) [("shared", Just lib)] [imp (at ["p", "main.l4"]) "shared" lib]
      r `shouldSatisfy` either (\case UnreachableImport _ -> True; _ -> False) (const False)

  -- A standard library file that is exactly the built-in copy adds nothing to
  -- the upload: the service has it. It is not uploaded, not judged for where it
  -- sits, and does not count as outside the project folder.
  describe "a file that is exactly the standard library module built into the service" $ do
    let daydate = "daydate text\n"
        compat = "date-compat text\n"
        builtIn n = lookup n [("daydate", daydate), ("date-compat", compat)]
        contentsOf files f = lookup f files
        main_ = at ["p", "main.l4"]
        libs f = at ["p", "libs", f]
        imp from written to = ImportEdge from written to
        -- Leave out the built-in copies, then plan what is left.
        planned root files imports edges =
          let (kept, left) = leaveOutBuiltIn builtIn (contentsOf files) imports
          in (planBundle root main_ kept edges, left)

    it "is left out, and named, whatever folder it is in" $
      leaveOutBuiltIn builtIn (contentsOf [(libs "daydate.l4", daydate), (libs "date-compat.l4", compat)])
          [("daydate", Just (libs "daydate.l4")), ("date-compat", Just (libs "date-compat.l4"))]
        `shouldBe`
          ([("daydate", Nothing), ("date-compat", Nothing)], ["daydate", "date-compat"])

    it "is kept when its bytes differ by even one character" $
      leaveOutBuiltIn builtIn (contentsOf [(libs "daydate.l4", daydate <> "-- local\n")])
          [("daydate", Just (libs "daydate.l4"))]
        `shouldBe` ([("daydate", Just (libs "daydate.l4"))], [])

    it "is kept when no built-in module has its name, though its text is a built-in module's" $
      leaveOutBuiltIn builtIn (contentsOf [(libs "mine.l4", daydate)]) [("mine", Just (libs "mine.l4"))]
        `shouldBe` ([("mine", Just (libs "mine.l4"))], [])

    it "is kept when it could not be read, so that reading the upload says so" $
      leaveOutBuiltIn builtIn (contentsOf []) [("daydate", Just (libs "daydate.l4"))]
        `shouldBe` ([("daydate", Just (libs "daydate.l4"))], [])

    it "is named once when two imports reach copies of one name" $
      leaveOutBuiltIn builtIn (contentsOf [(libs "daydate.l4", daydate), (at ["p", "daydate.l4"], daydate)])
          [("daydate", Just (libs "daydate.l4")), ("daydate", Just (at ["p", "daydate.l4"]))]
        `shouldBe` ([("daydate", Nothing), ("daydate", Nothing)], ["daydate"])

    it "leaves a module that has no file alone" $
      leaveOutBuiltIn builtIn (contentsOf []) [("jl4-embedded:/prelude.l4", Nothing)]
        `shouldBe` ([("jl4-embedded:/prelude.l4", Nothing)], [])

    it "is not judged for where it sits: a copy in a folder of the project is not an unreachable import" $ do
      let files = [(libs "daydate.l4", daydate)]
          imports = [("daydate", Just (libs "daydate.l4"))]
          edges = [imp main_ "daydate" (libs "daydate.l4")]
      planned (at ["p"]) files imports edges `shouldBe` (Right [("main.l4", main_)], ["daydate"])
      -- The same copy with one more line of text is a project file in a folder
      -- the service does not look in.
      let unreachableNames = either (\case UnreachableImport us -> map (.importedName) us; _ -> []) (const [])
      unreachableNames (fst (planned (at ["p"]) [(libs "daydate.l4", daydate <> "-- local\n")] imports edges))
        `shouldBe` ["libs/daydate.l4"]

    it "does not count as outside the project folder" $ do
      let outside = at ["elsewhere", "daydate.l4"]
          imports = [("daydate", Just outside)]
          edges = [imp main_ "daydate" outside]
      planned (at ["p"]) [(outside, daydate)] imports edges `shouldBe` (Right [("main.l4", main_)], ["daydate"])
      -- A copy that differs is outside, and stops the deploy.
      fst (planned (at ["p"]) [(outside, daydate <> "-- local\n")] imports edges)
        `shouldBe` Left (OutsideRoot (at ["p"]) [outside])

    it "takes the edges that start in it with it" $ do
      -- daydate imports date-compat; neither is uploaded, so neither line is judged.
      let files = [(libs "daydate.l4", daydate), (libs "date-compat.l4", compat)]
          imports = [("daydate", Just (libs "daydate.l4")), ("date-compat", Just (libs "date-compat.l4"))]
          edges = [imp main_ "daydate" (libs "daydate.l4"), imp (libs "daydate.l4") "date-compat" (libs "date-compat.l4")]
      planned (at ["p"]) files imports edges `shouldBe` (Right [("main.l4", main_)], ["daydate", "date-compat"])

  describe "the project root" $ do
    it "is the current folder when the file is inside it" $ do
      projectRoot (at ["w", "rows"]) (at ["w", "rows", "a", "main.l4"]) `shouldBe` at ["w", "rows"]
      projectRoot (at ["w", "rows"]) (at ["w", "rows", "main.l4"]) `shouldBe` at ["w", "rows"]
    it "is the file's own folder when the file is outside the current folder" $ do
      projectRoot (at ["elsewhere"]) (at ["w", "rows", "a", "main.l4"]) `shouldBe` at ["w", "rows", "a"]
      projectRoot (at ["w", "rows", "a"]) (at ["w", "rows", "ab", "main.l4"]) `shouldBe` at ["w", "rows", "ab"]
    it "reads .. in a path by its letters" $
      projectRoot (at ["w", "rows"]) (at ["w", "rows", "a", "..", "main.l4"]) `shouldBe` at ["w", "rows"]
    it "is the file's own folder when the current folder is the top of the drive, which every file is inside" $ do
      projectRoot (at []) (at ["w", "rows", "a", "main.l4"]) `shouldBe` at ["w", "rows", "a"]
      projectRoot (at []) (at ["main.l4"]) `shouldBe` at []

  describe "reading the files" $ do
    it "reads each file under its name in the zip" $
      withSystemTempDirectory "l4-deploy-read" \dir -> do
        BS.writeFile (dir </> "main.l4") "main\n"
        BS.writeFile (dir </> "helper.l4") "helper\n"
        r <- readBundle [("a/main.l4", dir </> "main.l4"), ("a/helper.l4", dir </> "helper.l4")]
        r `shouldBe` Right [("a/main.l4", "main\n"), ("a/helper.l4", "helper\n")]

    it "stops at a file that is missing, naming it" $
      withSystemTempDirectory "l4-deploy-read" \dir -> do
        BS.writeFile (dir </> "main.l4") "main\n"
        r <- readBundle [("main.l4", dir </> "main.l4"), ("gone.l4", dir </> "gone.l4")]
        either T.unpack (const "") r `shouldSatisfy` ((dir </> "gone.l4") `isInfixOf`)

    it "stops at a file that cannot be read as a file, naming it" $
      withSystemTempDirectory "l4-deploy-read" \dir -> do
        createDirectory (dir </> "folder.l4")
        r <- readBundle [("folder.l4", dir </> "folder.l4")]
        either T.unpack (const "") r `shouldSatisfy` ((dir </> "folder.l4") `isInfixOf`)

----------------------------------------------------------------------------
-- The real l4, against a service that records what it is sent
----------------------------------------------------------------------------

serviceSpec :: FilePath -> Spec
serviceSpec bin = describe "l4 deploy: the zip it sends" $ do
  it "keeps a flat project's plain file names and does not upload the standard library" $
    withFakeService \url requests -> do
      flat <- canonicalizePath flatDir
      Output code _ serr <- runL4EmbeddedOnlyIn (Just flat) bin
        ["deploy", "main.l4", "--no-wait", "--server", url]
      expectSuccess code serr
      posted <- uploads <$> requests
      map (fmap (map fst)) posted `shouldBe` [Just ["main.l4", "helper.l4"]]
      -- The note says what is being sent, by the names it is sent under.
      serr `shouldSatisfy` ("main.l4, helper.l4" `isInfixOf`)

  -- The main file is in a folder and its library is at the top of the project:
  -- the folders are kept, and the service finds `defs` at the top of the upload.
  it "keeps the folder of the main file when its library is at the top of the project, and the file's bytes" $
    withFakeService \url requests -> do
      top <- canonicalizePath topDir
      env <- withLibraryPath top
      Output code _ serr <- runL4In (Just top) (Just env) bin
        ["deploy", "a" </> "main.l4", "--no-wait", "--server", url]
      expectSuccess code serr
      posted <- uploads <$> requests
      map (fmap (map fst)) posted `shouldBe` [Just ["a/main.l4", "defs.l4"]]
      defs <- BS.readFile (top </> "defs.l4")
      [ c | Just es <- posted, Just c <- [lookup "defs.l4" es] ] `shouldBe` [BSL.fromStrict defs]
      serr `shouldSatisfy` ("a/main.l4, defs.l4" `isInfixOf`)

  -- The service looks for the file an import names, so a link to a module must
  -- go up under the link's name and not under its target's.
  it "names a linked module by the link, which is the name its importer used" $
    withSystemTempDirectory "l4-deploy-alias" \dir -> withFakeService \url requests -> do
      writeFile (dir </> "main.l4") "IMPORT alias\n\n`use it` MEANS 1\n"
      writeFile (dir </> "real.l4") "`the real one` MEANS 1\n"
      linkOrPending (dir </> "real.l4") (dir </> "alias.l4")
      project <- canonicalizePath dir
      Output code _ serr <- runL4EmbeddedOnlyIn (Just project) bin
        ["deploy", "main.l4", "--no-wait", "--server", url]
      expectSuccess code serr
      posted <- uploads <$> requests
      map (fmap (map fst)) posted `shouldBe` [Just ["main.l4", "alias.l4"]]

  -- The same folder spelled two ways must be one folder. The working folder is
  -- what the operating system reports (links followed); JL4_LIBRARY_PATH is
  -- whatever the user typed, here a path through a link, as on a Mac where
  -- /tmp is a link to /private/tmp.
  it "treats a folder spelled through a link as the folder it is" $
    withDirectoryLink topDir \link -> withFakeService \url requests -> do
      top <- canonicalizePath topDir
      env <- withLibraryPath link
      Output code _ serr <- runL4In (Just top) (Just env) bin
        ["deploy", "a" </> "main.l4", "--no-wait", "--server", url]
      expectSuccess code serr
      posted <- uploads <$> requests
      map (fmap (map fst)) posted `shouldBe` [Just ["a/main.l4", "defs.l4"]]

  mapM_ (\verb ->
    it ("sends nothing, and names the file and the folder, when an import is outside the project folder (" <> verb <> ")") $
      withFakeService \url requests -> do
        project <- canonicalizePath (libpathDir </> "project")
        outside <- canonicalizePath (libpathDir </> "outside")
        env <- withLibraryPath outside
        Output code _ serr <- runL4In (Just project) (Just env) bin
          [verb, "main.l4", "--no-wait", "--server", url]
        code `shouldNotBe` ExitSuccess
        -- Compared without regard to case: on Windows the typechecker spells a
        -- drive letter in lower case and the test in upper.
        map toLower serr `shouldSatisfy` (map toLower (outside </> "shared.l4") `isInfixOf`)
        map toLower serr `shouldSatisfy` (map toLower ("project folder " <> project) `isInfixOf`)
        -- The advice does not send the user to run from a higher folder, and
        -- it says what to do about a library that was found through the
        -- variable this run set, and where else l4 finds one.
        serr `shouldNotSatisfy` ("Run this from a folder" `isInfixOf`)
        serr `shouldSatisfy` ("inside the project folder, beside the file that imports it" `isInfixOf`)
        serr `shouldSatisfy` ("JL4_LIBRARY_PATH is set" `isInfixOf`)
        serr `shouldSatisfy` ("unset JL4_LIBRARY_PATH" `isInfixOf`)
        serr `shouldSatisfy` ("move the file instead of copying it" `isInfixOf`)
        serr `shouldSatisfy` ("per-user library folder" `isInfixOf`)
        sent <- requests
        sent `shouldBe` []) ["deploy", "redeploy"]

  -- The defect this guards: a library found through JL4_LIBRARY_PATH in a folder
  -- of the project that is neither the importer's nor the top used to be
  -- uploaded as lib/shared.l4. The service said "ready", then failed every call
  -- ("shared" was not in scope), and `redeploy` of the same project was refused
  -- as adding a required input.
  mapM_ (\verb ->
    it ("sends nothing when a library would be uploaded where the service does not look for it (" <> verb <> ")") $
      withFakeService \url requests -> do
        project <- canonicalizePath (libpathDir </> "project")
        env <- withLibraryPath (project </> "lib")
        Output code _ serr <- runL4In (Just project) (Just env) bin
          [verb, "main.l4", "--no-wait", "--server", url]
        code `shouldNotBe` ExitSuccess
        serr `shouldSatisfy` ("main.l4 imports shared" `isInfixOf`)
        serr `shouldSatisfy` ("lib/shared.l4" `isInfixOf`)
        serr `shouldSatisfy` ("in the folder lib" `isInfixOf`)
        serr `shouldSatisfy` ("only beside the file that imports it and at the top of the upload" `isInfixOf`)
        serr `shouldSatisfy` ("move the file instead of copying it" `isInfixOf`)
        sent <- requests
        sent `shouldBe` []) ["deploy", "redeploy"]

  -- A library from the per-user library folder is a file like any other once it
  -- is inside the project.
  it "refuses a library from the per-user library folder that would be uploaded in a folder of its own" $
    withFakeService \url requests -> do
      project <- canonicalizePath (xdgDir </> "project")
      Output code _ serr <- runL4WithXdgHomeIn (Just project) (project </> "data") bin
        ["deploy", "main.l4", "--no-wait", "--server", url]
      code `shouldNotBe` ExitSuccess
      serr `shouldSatisfy` ("main.l4 imports shared" `isInfixOf`)
      serr `shouldSatisfy` ("data/jl4/libraries/shared.l4" `isInfixOf`)
      sent <- requests
      sent `shouldBe` []

  it "names the per-user library folder, and not an unset JL4_LIBRARY_PATH, when a library from there is outside the project" $
    withFakeService \url requests -> do
      project <- canonicalizePath (xdgDir </> "project")
      outside <- canonicalizePath (xdgDir </> "outside")
      Output code _ serr <- runL4WithXdgHomeIn (Just project) (outside </> "data") bin
        ["deploy", "main.l4", "--no-wait", "--server", url]
      code `shouldNotBe` ExitSuccess
      map toLower serr `shouldSatisfy` (map toLower (outside </> "data" </> "jl4" </> "libraries" </> "shared.l4") `isInfixOf`)
      serr `shouldSatisfy` ("per-user library folder" `isInfixOf`)
      serr `shouldSatisfy` ("inside the project folder, beside the file that imports it" `isInfixOf`)
      -- The variable is not set in this run, so nothing is said of it, in the
      -- advice or anywhere else on the screen.
      serr `shouldNotSatisfy` ("JL4_LIBRARY_PATH" `isInfixOf`)
      sent <- requests
      sent `shouldBe` []

  -- Run from the top of the drive, the current folder contains every file, so it
  -- would bound nothing: the project folder is the main file's own, and the
  -- upload does not carry the names of the folders above the project.
  it "does not take the top of the drive for the project folder" $
    withFakeService \url requests -> do
      project <- canonicalizePath (libpathDir </> "project")
      outside <- canonicalizePath (libpathDir </> "outside")
      env <- withLibraryPath outside
      Output code _ serr <- runL4In (Just (takeDrive project)) (Just env) bin
        ["deploy", project </> "main.l4", "--no-wait", "--server", url]
      code `shouldNotBe` ExitSuccess
      map toLower serr `shouldSatisfy` (map toLower ("lies outside the project folder " <> project) `isInfixOf`)
      sent <- requests
      sent `shouldBe` []

  -- A name written with a slash is read as its last part (IMPORT `lib/shared` is
  -- `shared`) by l4 and by the service, so the line is judged like a bare one.
  it "judges IMPORT `lib/shared` as it judges IMPORT shared, and sends nothing" $
    withFakeService \url requests -> withProject
      [ ("main.l4", "IMPORT `lib/shared`\n\nGIVEN n IS A NUMBER\n`double it` MEANS n * 2\n")
      , ("lib" </> "shared.l4", "`the shared one` MEANS 1\n") ] \project -> do
        env <- withLibraryPath (project </> "lib")
        Output code _ serr <- runL4In (Just project) (Just env) bin
          ["deploy", "main.l4", "--no-wait", "--server", url]
        code `shouldNotBe` ExitSuccess
        serr `shouldSatisfy` ("main.l4 imports lib/shared" `isInfixOf`)
        serr `shouldSatisfy` ("lib/shared.l4" `isInfixOf`)
        sent <- requests
        sent `shouldBe` []

  -- The service does not find a file beside its importer when the folder's name
  -- has a space (a residual of the fix for smucclaw/l4-ide#971, which is closed;
  -- no issue tracks it yet), so the deploy stops before any request.
  -- The same project with the folder renamed is the positive control: it is
  -- uploaded with its folders, so the refusal is about the name.
  let folderProject folderName =
        [ (folderName </> "main.l4", "IMPORT helper\nIMPORT defs\n\nGIVEN n IS A NUMBER\n`double it` MEANS n * 2\n")
        , (folderName </> "helper.l4", "`the helper` MEANS 1\n")
        , ("defs.l4", "`the shared one` MEANS 1\n") ]
  mapM_ (\verb ->
    it ("sends nothing when an imported file is in a folder with a space in its name (" <> verb <> ")") $
      withFakeService \url requests -> withProject (folderProject "my dir") \dir -> do
        env <- withLibraryPath dir
        Output code _ serr <- runL4In (Just dir) (Just env) bin
          [verb, "my dir" </> "main.l4", "--no-wait", "--server", url]
        code `shouldNotBe` ExitSuccess
        serr `shouldSatisfy` ("my dir/helper.l4" `isInfixOf`)
        serr `shouldSatisfy` ("in the folder my dir" `isInfixOf`)
        serr `shouldSatisfy` ("does not find a file beside the file that imports it" `isInfixOf`)
        serr `shouldSatisfy` ("Rename the folder" `isInfixOf`)
        sent <- requests
        sent `shouldBe` []) ["deploy", "redeploy"]

  it "uploads the same project, folders kept, when the folder is called \"my-dir\"" $
    withFakeService \url requests -> withProject (folderProject "my-dir") \dir -> do
      env <- withLibraryPath dir
      Output code _ serr <- runL4In (Just dir) (Just env) bin
        ["deploy", "my-dir" </> "main.l4", "--no-wait", "--server", url]
      expectSuccess code serr
      posted <- uploads <$> requests
      map (fmap (map fst)) posted `shouldBe` [Just ["my-dir/main.l4", "my-dir/helper.l4", "defs.l4"]]

  -- A project whose standard library is vendored, or pinned by JL4_LIBRARY_PATH:
  -- the service has that library built in, so a file that is exactly the
  -- built-in copy is not uploaded, wherever it is, and says so.
  -- The copies are written from the built-in text of this very build, so that
  -- they are identical to it whatever the checkout's libraries hold.
  it "does not upload a copy of the standard library kept in a folder of the project, and names it" $
    withFakeService \url requests -> withProject
      [ ("main.l4", "IMPORT daydate\nIMPORT `date-compat`\n\nGIVEN n IS A NUMBER\n`double it` MEANS n * 2\n")
      , ("libs" </> "daydate.l4", builtInText "daydate")
      , ("libs" </> "date-compat.l4", builtInText "date-compat") ] \project -> do
        env <- withLibraryPath (project </> "libs")
        Output code _ serr <- runL4In (Just project) (Just env) bin
          ["deploy", "main.l4", "--no-wait", "--server", url]
        expectSuccess code serr
        posted <- uploads <$> requests
        map (fmap (map fst)) posted `shouldBe` [Just ["main.l4"]]
        serr `shouldSatisfy` ("Not uploaded, the deployed service has it built in: daydate" `isInfixOf`)
        serr `shouldSatisfy` ("Not uploaded, the deployed service has it built in: date-compat" `isInfixOf`)

  it "does not upload a copy of the standard library pinned outside the project, and does not call it outside the root" $
    withFakeService \url requests -> withProject
      [ ("project" </> "main.l4", "IMPORT daydate\nIMPORT `date-compat`\n\nGIVEN n IS A NUMBER\n`double it` MEANS n * 2\n")
      , ("libraries" </> "daydate.l4", builtInText "daydate")
      , ("libraries" </> "date-compat.l4", builtInText "date-compat") ] \root -> do
        env <- withLibraryPath (root </> "libraries")
        Output code _ serr <- runL4In (Just (root </> "project")) (Just env) bin
          ["deploy", "main.l4", "--no-wait", "--server", url]
        expectSuccess code serr
        posted <- uploads <$> requests
        map (fmap (map fst)) posted `shouldBe` [Just ["main.l4"]]
        serr `shouldNotSatisfy` ("lies outside the project folder" `isInfixOf`)

  -- One more character in the copy and it is a project file like any other:
  -- here in a folder the service does not look in.
  mapM_ (\verb ->
    it ("refuses a copy of the standard library that differs from the built-in one, kept in a folder of the project (" <> verb <> ")") $
      withFakeService \url requests -> withProject
        [ ("main.l4", "IMPORT daydate\nIMPORT `date-compat`\n\nGIVEN n IS A NUMBER\n`double it` MEANS n * 2\n")
        , ("libs" </> "daydate.l4", builtInText "daydate" <> "\n-- changed in this project\n")
        , ("libs" </> "date-compat.l4", builtInText "date-compat") ] \project -> do
          env <- withLibraryPath (project </> "libs")
          Output code _ serr <- runL4In (Just project) (Just env) bin
            [verb, "main.l4", "--no-wait", "--server", url]
          code `shouldNotBe` ExitSuccess
          serr `shouldSatisfy` ("main.l4 imports daydate" `isInfixOf`)
          serr `shouldSatisfy` ("libs/daydate.l4" `isInfixOf`)
          sent <- requests
          sent `shouldBe` []) ["deploy", "redeploy"]

  it "refuses a copy of the standard library that differs from the built-in one, pinned outside the project" $
    withFakeService \url requests -> withProject
      [ ("project" </> "main.l4", "IMPORT daydate\nIMPORT `date-compat`\n\nGIVEN n IS A NUMBER\n`double it` MEANS n * 2\n")
      , ("libraries" </> "daydate.l4", builtInText "daydate" <> "\n-- a newer checkout\n")
      , ("libraries" </> "date-compat.l4", builtInText "date-compat") ] \root -> do
        project <- canonicalizePath (root </> "project")
        env <- withLibraryPath (root </> "libraries")
        Output code _ serr <- runL4In (Just project) (Just env) bin
          ["deploy", "main.l4", "--no-wait", "--server", url]
        code `shouldNotBe` ExitSuccess
        serr `shouldSatisfy` ("lies outside the project folder" `isInfixOf`)
        serr `shouldSatisfy` ("daydate.l4" `isInfixOf`)
        serr `shouldSatisfy` ("exactly the copy built into l4 is left out of the upload and stops nothing" `isInfixOf`)
        sent <- requests
        sent `shouldBe` []

  where
    expectSuccess code serr = case code of
      ExitSuccess -> pure ()
      ExitFailure n -> expectationFailure ("Expected success, but l4 exited " <> show n <> "\n--- stderr ---\n" <> serr)

    withLibraryPath dir = do
      parent <- getEnvironment
      pure (("JL4_LIBRARY_PATH", dir) : filter ((/= "JL4_LIBRARY_PATH") . fst) parent)

-- | The standard library module built into this build, as the bytes a file
-- holding exactly that text has. The test binary and @l4@ are built from the
-- same @jl4-core@, so it is the text @l4 deploy@ compares a file against.
builtInText :: String -> BS.ByteString
builtInText name = maybe (error ("no built-in library module " <> name)) TE.encodeUtf8 (Embedded.lookupEmbeddedLibrary (T.pack name))

-- | Run an action in a new folder that holds the given files (named below it,
-- folders made as needed), given the folder with links followed so that the
-- paths it prints are the ones @l4@ prints.
withProject :: [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withProject files act = withSystemTempDirectory "l4-deploy-project" \tmp -> do
  dir <- canonicalizePath tmp
  mapM_ (\(name, content) -> do
           createDirectoryIfMissing True (takeDirectory (dir </> name))
           BS.writeFile (dir </> name) content) files
  act dir

-- | Run an action with a link to a folder, or mark the example pending where
-- this account may not make one (Windows without the symlink privilege).
withDirectoryLink :: FilePath -> (FilePath -> IO ()) -> IO ()
withDirectoryLink target act = withSystemTempDirectory "l4-deploy-link" \tmp -> do
  absTarget <- canonicalizePath target
  let link = tmp </> "link"
  made <- try (createDirectoryLink absTarget link)
  case made of
    Right () -> act link
    Left e
      | isPermissionError e -> pendingWith ("cannot create a symbolic link here (" <> show (e :: IOException) <> ")")
      | otherwise -> throwIO e

-- | The files in the zip of each upload (POST or PUT) the service was sent, by
-- name; Nothing for an upload whose form holds no readable zip.
uploads :: [Request] -> [Maybe [(FilePath, BSL.ByteString)]]
uploads rs = [ zipOf body | (m, _, body) <- rs, m `elem` ["POST", "PUT"] ]

-- | The zip in the @sources@ part of a multipart form.
zipOf :: BS.ByteString -> Maybe [(FilePath, BSL.ByteString)]
zipOf body = do
  let boundary = BS8.takeWhile (/= '\r') (BS.drop 2 body)
      parts = splitOnBS ("\r\n--" <> boundary) ("\r\n" <> body)
  part <- find (\p -> "name=\"sources\"" `BS.isInfixOf` fst (BS.breakSubstring "\r\n\r\n" p)) parts
  let content = BS.drop 4 (snd (BS.breakSubstring "\r\n\r\n" part))
  archive <- either (const Nothing) Just (Zip.toArchiveOrFail (BSL.fromStrict content))
  pure [ (Zip.eRelativePath e, Zip.fromEntry e) | e <- Zip.zEntries archive ]

splitOnBS :: BS.ByteString -> BS.ByteString -> [BS.ByteString]
splitOnBS delim s = case BS.breakSubstring delim s of
  (a, rest)
    | BS.null rest -> [a]
    | otherwise -> a : splitOnBS delim (BS.drop (BS.length delim) rest)

----------------------------------------------------------------------------
-- A service that records its requests
----------------------------------------------------------------------------

-- | Method, path and body of a request.
type Request = (BS.ByteString, BS.ByteString, BS.ByteString)

-- | Run an action against a service on the loopback interface. It knows no
-- deployments (every lookup is a 404) and accepts every upload; the action
-- gets its URL and a way to read what it was sent, oldest first.
withFakeService :: (String -> IO [Request] -> IO a) -> IO a
withFakeService act = withSocketsDo $ bracket listenOnLoopback close \sock -> do
  port <- socketPort sock
  seen <- newMVar []
  acceptor <- forkIO $ forever do
    (conn, _) <- accept sock
    void (forkIO (serve seen conn `catch` \(_ :: IOException) -> pure ()))
  act ("http://127.0.0.1:" <> show port) (reverse <$> readMVar seen) `finally` killThread acceptor

listenOnLoopback :: IO Socket
listenOnLoopback = do
  sock <- socket AF_INET Stream defaultProtocol
  bind sock (SockAddrInet 0 (tupleToHostAddress (127, 0, 0, 1)))
  listen sock 8
  pure sock

-- | Answer one request. Only a body with a @Content-Length@ is understood,
-- which is what @l4@'s multipart upload sends.
serve :: MVar [Request] -> Socket -> IO ()
serve seen conn = (`finally` close conn) do
  (headerBytes, bodyStart) <- readHead BS.empty
  case BS8.lines headerBytes of
    requestLine : headerLines | [method, path, _] <- BS8.words requestLine -> do
      let contentLength = case [ n | l <- headerLines, Just v <- [dropPrefixCI "content-length:" l], Just (n, _) <- [BS8.readInt (BS8.dropWhile (== ' ') v)] ] of
            n : _ -> n
            [] -> 0
      body <- readBody contentLength bodyStart
      modifyMVar_ seen (pure . ((method, path, body) :))
      sendAll conn (reply method)
    _ -> pure ()
  where
    readHead acc = case BS.breakSubstring "\r\n\r\n" acc of
      (h, rest) | not (BS.null rest) -> pure (h, BS.drop 4 rest)
      _ -> do
        chunk <- recv conn 4096
        if BS.null chunk then pure (acc, BS.empty) else readHead (acc <> chunk)
    readBody n acc
      | BS.length acc >= n = pure (BS.take n acc)
      | otherwise = do
          chunk <- recv conn 65536
          if BS.null chunk then pure acc else readBody n (acc <> chunk)
    dropPrefixCI prefix l =
      let (a, b) = BS8.splitAt (BS8.length prefix) l
      in if BS8.map toLower a == prefix then Just b else Nothing
    reply method
      | method `elem` ["POST", "PUT"] =
          "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"
      | otherwise =
          "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
