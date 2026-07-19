-- | Table-driven unit tests for 'LSP.L4.Rules.resolveLibrary' — the ordered
-- candidate walk behind bare-module-name @IMPORT@ resolution.
--
-- These pin the LIBRARY-RESOLUTION-SHADOW-SPEC Option B′ ordering:
--
--   $JL4_LIBRARY_PATH > project root > importer-relative > EMBEDDED > XDG > bundle
--
-- i.e. project-scoped sources outrank the binary's own embedded stdlib, and
-- ambient machine-global sources (XDG data dir, VSCode bundle) rank below it.
--
-- The tests steer the resolver through environment variables only
-- (@JL4_LIBRARY_PATH@, @XDG_DATA_HOME@), saved and restored around each case;
-- hspec runs items sequentially so this does not race.
module LibraryResolutionSpec (spec) where

import Control.Exception (bracket)
import Control.Monad (forM_)
import Data.Maybe (isNothing)
import System.Directory
  ( canonicalizePath
  , createDirectoryIfMissing
  , createFileLink
  , getTemporaryDirectory
  , removePathForcibly
  )
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>), (<.>))

import Language.LSP.Protocol.Types (toNormalizedFilePath)
import LSP.L4.Rules
  ( LibraryCandidate (..)
  , LibraryResolution (..)
  , resolveLibrary
  )

import Test.Hspec

-- | An embedded stdlib module ('L4.API.EmbeddedLibraries' always carries the
-- prelude; jl4-core's ImportResolutionSpec asserts this independently).
embeddedMod :: String
embeddedMod = "prelude"

-- | A module name that is certainly not part of the embedded stdlib.
strayMod :: String
strayMod = "zz-l4-libres-spec-not-embedded"

data Sandbox = Sandbox
  { rootDir    :: FilePath  -- ^ pretend project root
  , siblingDir :: FilePath  -- ^ directory of the pretend importing file
  , xdgLibs    :: FilePath  -- ^ the fabricated @$XDG_DATA_HOME/jl4/libraries@
  , envLibs    :: FilePath  -- ^ directory for @JL4_LIBRARY_PATH@ cases
  , elsewhere  :: FilePath  -- ^ symlink targets live here
  }

-- | Build a fresh sandbox, point XDG_DATA_HOME into it, drop
-- JL4_LIBRARY_PATH, and restore the previous environment afterwards.
withSandbox :: (Sandbox -> IO ()) -> IO ()
withSandbox act = bracket acquire release (act . fst)
  where
    acquire = do
      savedEnv <- traverse (\k -> (k,) <$> lookupEnv k) ["JL4_LIBRARY_PATH", "XDG_DATA_HOME"]
      tmp <- getTemporaryDirectory
      let base = tmp </> "jl4-library-resolution-spec"
          sb = Sandbox
            { rootDir    = base </> "root"
            , siblingDir = base </> "root" </> "sub"
            , xdgLibs    = base </> "xdg" </> "jl4" </> "libraries"
            , envLibs    = base </> "envlibs"
            , elsewhere  = base </> "elsewhere"
            }
      removePathForcibly base
      forM_ [sb.rootDir, sb.siblingDir, sb.xdgLibs, sb.envLibs, sb.elsewhere] $
        createDirectoryIfMissing True
      setEnv "XDG_DATA_HOME" (base </> "xdg")
      unsetEnv "JL4_LIBRARY_PATH"
      pure (sb, savedEnv)
    release (_, savedEnv) =
      forM_ savedEnv $ \(k, mv) -> maybe (unsetEnv k) (setEnv k) mv

-- | Resolve @modName@ as if imported by a file in the sandbox's sibling dir.
resolveIn :: Sandbox -> String -> IO LibraryResolution
resolveIn sb modName =
  resolveLibrary sb.rootDir (Just (toNormalizedFilePath (sb.siblingDir </> "importer.l4"))) modName

plant :: FilePath -> String -> IO FilePath
plant dir modName = do
  let p = dir </> modName <.> "l4"
  writeFile p ("-- planted by LibraryResolutionSpec\n`marker " <> modName <> "` MEANS TRUE\n")
  pure p

winnerFile :: LibraryResolution -> Maybe FilePath
winnerFile res = case res.winner of
  Just (_, FileCandidate _ p) -> Just p
  _                           -> Nothing

winnerIsEmbedded :: LibraryResolution -> Bool
winnerIsEmbedded res = case res.winner of
  Just (_, EmbeddedCandidate) -> True
  _                           -> False

spec :: Spec
spec = around withSandbox $
  describe "resolveLibrary (LIBRARY-RESOLUTION-SHADOW-SPEC, Option B′)" $ do

    it "candidate order is env? > root > sibling > embedded > XDG > bundle" $ \sb -> do
      res <- resolveIn sb embeddedMod
      -- env unset: no env candidate, embedded present
      [ c | c@EmbeddedCandidate <- res.candidates ] `shouldSatisfy` (not . null)
      let labels = [ lbl | FileCandidate lbl _ <- res.candidates ]
      labels `shouldBe` ["project root", "importer-relative", "XDG data dir", "VSCode bundle"]
      -- embedded sits after the project-scoped tiers, before the ambient ones
      let tierOf c = case c of
            FileCandidate lbl _ -> lbl
            EmbeddedCandidate   -> "embedded"
      map tierOf res.candidates
        `shouldBe` ["project root", "importer-relative", "embedded", "XDG data dir", "VSCode bundle"]

    it "JL4_LIBRARY_PATH wins over everything and disables the embedded copy" $ \sb -> do
      p <- plant sb.envLibs embeddedMod
      _ <- plant sb.rootDir embeddedMod
      setEnv "JL4_LIBRARY_PATH" sb.envLibs
      res <- resolveIn sb embeddedMod
      res.hasExplicitPath `shouldBe` True
      winnerFile res `shouldBe` Just p
      [ c | c@EmbeddedCandidate <- res.candidates ] `shouldBe` []

    it "with JL4_LIBRARY_PATH set but empty, ambient tiers still resolve (no embedded fallback)" $ \sb -> do
      p <- plant sb.xdgLibs embeddedMod
      setEnv "JL4_LIBRARY_PATH" sb.envLibs  -- exists but has no copy
      res <- resolveIn sb embeddedMod
      winnerFile res `shouldBe` Just p

    it "a project-root copy outranks the embedded stdlib" $ \sb -> do
      p <- plant sb.rootDir embeddedMod
      res <- resolveIn sb embeddedMod
      winnerFile res `shouldBe` Just p

    it "an importer-relative copy outranks the embedded stdlib" $ \sb -> do
      p <- plant sb.siblingDir embeddedMod
      res <- resolveIn sb embeddedMod
      winnerFile res `shouldBe` Just p

    it "the embedded stdlib outranks an XDG copy (the §3.1 incident)" $ \sb -> do
      xdgPath <- plant sb.xdgLibs embeddedMod
      res <- resolveIn sb embeddedMod
      winnerIsEmbedded res `shouldBe` True
      -- the shadowed ambient copy is still reported as existing, so the
      -- shadow warning (Option E) has what it needs
      [ p | (_, FileCandidate _ p) <- res.existing ] `shouldBe` [xdgPath]

    it "an XDG copy still serves modules the embed does not carry" $ \sb -> do
      p <- plant sb.xdgLibs strayMod
      res <- resolveIn sb strayMod
      winnerFile res `shouldBe` Just p

    it "reports nothing found for an unknown module, listing the searched paths" $ \sb -> do
      res <- resolveIn sb strayMod
      res.winner `shouldSatisfy` isNothing
      res.existing `shouldBe` []
      -- root, sibling, XDG, bundle (embedded is not a filesystem path)
      length res.searchedPaths `shouldBe` 4

    it "symlinked XDG entries canonicalize to their real target" $ \sb -> do
      target <- plant sb.elsewhere strayMod
      let link = sb.xdgLibs </> strayMod <.> "l4"
      createFileLink target link
      res <- resolveIn sb strayMod
      winnerFile res `shouldBe` Just link
      realWinner <- traverse canonicalizePath (winnerFile res)
      realTarget <- canonicalizePath target
      realWinner `shouldBe` Just realTarget
