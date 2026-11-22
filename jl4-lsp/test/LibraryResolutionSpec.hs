-- | Table-driven unit tests for 'LSP.L4.Rules.resolveLibrary' — the ordered
-- candidate walk behind bare-module-name @IMPORT@ resolution.
--
-- These pin the Option B′ ordering (specs/as-built/import-resolution.md):
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

import Control.Exception (IOException, bracket, finally, throwIO, try)
import Control.Monad (forM_)
import Data.Char (toLower)
import Data.Maybe (isNothing)
import Data.Text (Text)
import System.Directory
  ( canonicalizePath
  , createDirectoryIfMissing
  , createFileLink
  , emptyPermissions
  , getTemporaryDirectory
  , listDirectory
  , removePathForcibly
  , setOwnerReadable
  , setOwnerSearchable
  , setOwnerWritable
  , setPermissions
  )
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>), (<.>), takeDirectory, takeFileName)
import System.IO.Error (isPermissionError)

import Language.LSP.Protocol.Types (toNormalizedFilePath)
import LSP.L4.Rules
  ( LibraryCandidate (..)
  , LibraryProbe (..)
  , LibraryResolution (..)
  , LibraryScope (..)
  , distinctCopies
  , realLibraryProbe
  , resolveLibrary
  , resolveLibraryWith
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
resolveIn = resolveInScope AmbientLibraries

resolveInScope :: LibraryScope -> Sandbox -> String -> IO LibraryResolution
resolveInScope scope sb modName =
  resolveLibrary scope sb.rootDir (Just (toNormalizedFilePath (sb.siblingDir </> "importer.l4"))) modName

-- | Try to create a symbolic link; 'Left' says why it could not be made. On
-- Windows an account without the symlink privilege gets "permission denied".
-- Any other failure is a real one and is rethrown.
tryLink :: FilePath -> FilePath -> IO (Either String ())
tryLink target link = do
  r <- try (createFileLink target link) :: IO (Either IOException ())
  case r of
    Right () -> pure (Right ())
    Left e
      | isPermissionError e -> pure (Left ("cannot create a symbolic link here (" <> show e <> ")"))
      | otherwise -> throwIO e

-- | Create a symbolic link, or mark the example pending where this account may
-- not: the example is about what the resolver does with a link, not about
-- whether the platform lets a test make one.
linkOrPending :: FilePath -> FilePath -> IO ()
linkOrPending target link = tryLink target link >>= either pendingWith pure

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

-- | The near misses as (tier label, entry names), for assertions that should
-- not depend on the tier's index.
variantsByTier :: LibraryResolution -> [(Text, [FilePath])]
variantsByTier res = [ (lbl, es) | (_, FileCandidate lbl _, es) <- res.caseVariantsFound ]

-- | A case-INSENSITIVE disk, on any disk: a file "exists" when its folder has
-- an entry equal to it ignoring ASCII capitals, which is how the macOS and
-- Windows defaults answer. The listing is the real one. PR CI runs this suite
-- on Linux only, where the real disk is case-sensitive and so already refuses
-- what the case rule refuses; with this stand-in, the examples that use it
-- fail on Linux too when the rule is broken.
caseInsensitiveDisk :: LibraryProbe
caseInsensitiveDisk = realLibraryProbe { probeExists = exists }
  where
    exists p = do
      entries <- entriesOf (takeDirectory p)
      pure (any (\ e -> map toLower e == map toLower (takeFileName p)) entries)

-- | A case-SENSITIVE disk, on any disk: a file exists only when its folder has
-- an entry spelled exactly so, which is how Linux answers. On a Mac this is
-- what shows that a near miss does not depend on the disk's yes: there the
-- real disk says yes for every variant, so an example on the real disk cannot
-- tell a listing taken whatever the disk said from one taken only after a yes.
caseSensitiveDisk :: LibraryProbe
caseSensitiveDisk = realLibraryProbe { probeExists = exists }
  where
    exists p = elem (takeFileName p) <$> entriesOf (takeDirectory p)

entriesOf :: FilePath -> IO [FilePath]
entriesOf dir = either (const []) id <$> (try (listDirectory dir) :: IO (Either IOException [FilePath]))

spec :: Spec
spec = around withSandbox $
  describe "resolveLibrary (Option B′, specs/as-built/import-resolution.md)" $ do

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
      linkOrPending target link
      res <- resolveIn sb strayMod
      winnerFile res `shouldBe` Just link
      realWinner <- traverse canonicalizePath (winnerFile res)
      realTarget <- canonicalizePath target
      realWinner `shouldBe` Just realTarget

    -- The examples that need a symbolic link are marked pending where the account
    -- may not make one (Windows without the symlink privilege), instead of
    -- failing. This pins the path they take: a link made in a folder the account
    -- may not write to is reported, not thrown.
    it "reports a link it may not create, instead of throwing" $ \sb -> do
      target <- plant sb.elsewhere strayMod
      let locked = sb.elsewhere </> "locked"
          open' = setOwnerWritable True (setOwnerSearchable True (setOwnerReadable True emptyPermissions))
      createDirectoryIfMissing True locked
      setPermissions locked emptyPermissions
      r <- tryLink target (locked </> strayMod <.> "l4") `finally` setPermissions locked open'
      case r of
        Left why -> why `shouldContain` "cannot create a symbolic link"
        Right () -> pendingWith "this account can make a link in a read-only folder (root, or a platform that ignores the mode)"

    -- smucclaw/l4-ide#1080: capitals count in a module name, on every tier and
    -- every disk. Each example says whether it is evidence on Linux, where PR
    -- CI runs this suite: a real case-sensitive disk already refuses
    -- `dayDate.l4` beside `daydate.l4`, so an example that only checks the
    -- refusal against the real disk proves nothing there.
    describe "the case rule (#1080)" $ do
      let resolveWith probe sb modName =
            resolveLibraryWith probe AmbientLibraries sb.rootDir
              (Just (toNormalizedFilePath (sb.siblingDir </> "importer.l4"))) modName

      -- Linux evidence: the stand-in disk answers yes, as a Mac does.
      it "refuses a file the disk reports under other capitals, and names it as a near miss" $ \sb -> do
        _ <- plant sb.rootDir "zzcase"
        res <- resolveWith caseInsensitiveDisk sb "zzCase"
        res.winner `shouldSatisfy` isNothing
        res.existing `shouldBe` []
        variantsByTier res `shouldBe` [("project root", ["zzcase.l4"])]

      -- Linux evidence: the same stand-in, for the folder JL4_LIBRARY_PATH
      -- names, which is how `IMPORT dayDate` reached `daydate.l4` on a Mac.
      it "refuses it in the JL4_LIBRARY_PATH folder too" $ \sb -> do
        _ <- plant sb.envLibs "zzcase"
        setEnv "JL4_LIBRARY_PATH" sb.envLibs
        res <- resolveWith caseInsensitiveDisk sb "zzCase"
        res.winner `shouldSatisfy` isNothing
        variantsByTier res `shouldBe` [("$JL4_LIBRARY_PATH", ["zzcase.l4"])]

      -- Linux evidence: the stand-in, for a resolved import. The refused file
      -- is in neither the winner nor the copies the shadow warning compares.
      it "lets a lower tier win, and records the refused file above it" $ \sb -> do
        _ <- plant sb.siblingDir "Zzmod"
        xdgCopy <- plant sb.xdgLibs "zzmod"
        res <- resolveWith caseInsensitiveDisk sb "zzmod"
        winnerFile res `shouldBe` Just xdgCopy
        [ p | (_, FileCandidate _ p) <- res.existing ] `shouldBe` [xdgCopy]
        variantsByTier res `shouldBe` [("importer-relative", ["Zzmod.l4"])]

      -- Linux evidence: fully stubbed. HFS+ lists `café.l4` decomposed while
      -- the source spells it composed (design probe P11); that is the right
      -- file, correctly named, and must not be refused as a case variant.
      it "keeps a file whose listing spells the name in another Unicode normal form" $ \sb -> do
        let probe = LibraryProbe
              { probeExists  = \ _ -> pure True
              , probeListing = \ _ -> pure (Just ["cafe\x301.l4"])
              }
        res <- resolveWith probe sb "caf\xe9"
        winnerFile res `shouldBe` Just (sb.rootDir </> "caf\xe9.l4")
        res.caseVariantsFound `shouldBe` []

      -- Linux evidence: fully stubbed.
      it "keeps the disk's answer where the folder cannot be listed, and says so" $ \sb -> do
        let probe = LibraryProbe
              { probeExists  = \ p -> pure (takeDirectory p == sb.rootDir)
              , probeListing = \ _ -> pure Nothing
              }
        res <- resolveWith probe sb "zzCase"
        winnerFile res `shouldBe` Just (sb.rootDir </> "zzCase.l4")
        res.unlistedFolders `shouldBe` [sb.rootDir]

      -- Linux evidence: the real disk. The near miss comes from the listing,
      -- whatever the existence probe said (no on Linux, yes on a Mac), so the
      -- hint is the same on both.
      it "finds a near miss in the XDG store on any disk" $ \sb -> do
        _ <- plant sb.xdgLibs "zzcase"
        res <- resolveIn sb "zzCase"
        res.winner `shouldSatisfy` isNothing
        variantsByTier res `shouldBe` [("XDG data dir", ["zzcase.l4"])]

      -- Evidence on every OS: the case-sensitive stand-in says no for
      -- `zzCase.l4`, as Linux does, so the near miss must come from a listing
      -- taken whatever the disk said. Taken only after a yes, it would appear
      -- on a Mac and not on Linux, and so would the hint.
      it "finds the near miss on a disk that says no (as Linux does)" $ \sb -> do
        _ <- plant sb.xdgLibs "zzcase"
        res <- resolveWith caseSensitiveDisk sb "zzCase"
        res.winner `shouldSatisfy` isNothing
        variantsByTier res `shouldBe` [("XDG data dir", ["zzcase.l4"])]

      it "records the skipped variant above the winner on a disk that says no" $ \sb -> do
        _ <- plant sb.siblingDir "Zzmod"
        xdgCopy <- plant sb.xdgLibs "zzmod"
        res <- resolveWith caseSensitiveDisk sb "zzmod"
        winnerFile res `shouldBe` Just xdgCopy
        variantsByTier res `shouldBe` [("importer-relative", ["Zzmod.l4"])]

      -- Linux evidence: the real disk, and P12's shape: on a Mac the
      -- importer-relative `Zzmod.l4` used to win `IMPORT zzmod`; on Linux the
      -- XDG copy won silently. Both now record the skipped file.
      it "records a variant beside the importer above an exact XDG copy, on any disk" $ \sb -> do
        _ <- plant sb.siblingDir "Zzmod"
        xdgCopy <- plant sb.xdgLibs "zzmod"
        res <- resolveIn sb "zzmod"
        winnerFile res `shouldBe` Just xdgCopy
        variantsByTier res `shouldBe` [("importer-relative", ["Zzmod.l4"])]

      -- Linux evidence: no disk at all (the embedded names).
      it "names the embedded daydate for dayDate when the embedded tier is consulted" $ \sb -> do
        res <- resolveIn sb "dayDate"
        res.winner `shouldSatisfy` isNothing
        res.embeddedCaseVariants `shouldBe` ["daydate"]

      it "does not suggest an embedded module when JL4_LIBRARY_PATH hides the embedded tier" $ \sb -> do
        setEnv "JL4_LIBRARY_PATH" sb.envLibs
        res <- resolveIn sb "dayDate"
        res.embeddedCaseVariants `shouldBe` []

      it "names the embedded daydate under EmbeddedStdlibOnly too" $ \sb -> do
        res <- resolveInScope EmbeddedStdlibOnly sb "dayDate"
        res.winner `shouldSatisfy` isNothing
        res.embeddedCaseVariants `shouldBe` ["daydate"]

      -- Linux evidence: the real disk. A variant ranked below the winner could
      -- not have won under any rule, so it is not a near miss.
      it "ignores a variant below the winner" $ \sb -> do
        rootCopy <- plant sb.rootDir "zzmod"
        _ <- plant sb.xdgLibs "Zzmod"
        res <- resolveIn sb "zzmod"
        winnerFile res `shouldBe` Just rootCopy
        res.caseVariantsFound `shouldBe` []

      -- macOS and Windows evidence only: on Linux the real disk never reports
      -- the XDG `Zzmod.l4` for `zzmod`, so this passes there with or without
      -- the rule. On a Mac it is the shadow warning's input: a variant must not
      -- be listed as a copy of the module.
      it "does not count a variant below the winner as a copy (case-insensitive disks)" $ \sb -> do
        rootCopy <- plant sb.rootDir "zzmod"
        _ <- plant sb.xdgLibs "Zzmod"
        res <- resolveIn sb "zzmod"
        [ p | (_, FileCandidate _ p) <- res.existing ] `shouldBe` [rootCopy]

      -- Review finding A, as revised by GM (2026-11-21). `Zzself.l4` that
      -- writes `IMPORT zzself` must not be offered itself, since either
      -- suggested fix would make it import itself; it is set apart, so that
      -- the messages can say that a module cannot import itself. Linux
      -- evidence: the stand-in says yes, as a Mac does, and the file is still
      -- refused, still not a near miss, and still recognised as the importer.
      it "refuses the importing file under other capitals, and sets it apart from the near misses" $ \sb -> do
        self <- plant sb.siblingDir "Zzself"
        let resolveFrom probe = resolveLibraryWith probe AmbientLibraries sb.rootDir
              (Just (toNormalizedFilePath self)) "zzself"
        insensitive <- resolveFrom caseInsensitiveDisk
        insensitive.winner `shouldSatisfy` isNothing
        insensitive.caseVariantsFound `shouldBe` []
        insensitive.importerCaseVariant `shouldBe` Just "Zzself.l4"
        sensitive <- resolveFrom caseSensitiveDisk
        sensitive.caseVariantsFound `shouldBe` []
        sensitive.importerCaseVariant `shouldBe` Just "Zzself.l4"

      -- The same, where another file beside it IS a near miss: only the
      -- importer is left out. Linux evidence: the listing is stubbed and
      -- nothing is planted, because a case-insensitive disk cannot hold
      -- `Zzself.l4` and `ZZSELF.l4` side by side.
      it "still names another variant beside the importing file" $ \sb -> do
        let probe = LibraryProbe
              { probeExists  = \ _ -> pure False
              , probeListing = \ dir -> pure (Just (if dir == sb.siblingDir then ["Zzself.l4", "ZZSELF.l4"] else []))
              }
        res <- resolveLibraryWith probe AmbientLibraries sb.rootDir
          (Just (toNormalizedFilePath (sb.siblingDir </> "Zzself.l4"))) "zzself"
        variantsByTier res `shouldBe` [("importer-relative", ["ZZSELF.l4"])]
        res.importerCaseVariant `shouldBe` Just "Zzself.l4"

    -- A host that serves uploaded bundles must not let its own files or
    -- environment replace the stdlib (jl4-service). Every tier but the embedded
    -- copy is switched off, whatever is planted where.
    describe "EmbeddedStdlibOnly" $ do
      it "ignores JL4_LIBRARY_PATH, the project root, the importer's directory and the XDG store" $ \sb -> do
        _ <- plant sb.envLibs embeddedMod
        _ <- plant sb.rootDir embeddedMod
        _ <- plant sb.siblingDir embeddedMod
        _ <- plant sb.xdgLibs embeddedMod
        setEnv "JL4_LIBRARY_PATH" sb.envLibs
        res <- resolveInScope EmbeddedStdlibOnly sb embeddedMod
        winnerIsEmbedded res `shouldBe` True
        res.candidates `shouldBe` [EmbeddedCandidate]
        res.searchedPaths `shouldBe` []
        res.tiersInOrder `shouldBe` [EmbeddedCandidate]
        -- the variable is set but this scope does not read it, so the embed
        -- is consulted and the logs take the ordinary (unpinned) form
        res.hasExplicitPath `shouldBe` False

      it "does not find a module the embed lacks, even where the ambient tiers hold one" $ \sb -> do
        _ <- plant sb.rootDir strayMod
        _ <- plant sb.xdgLibs strayMod
        res <- resolveInScope EmbeddedStdlibOnly sb strayMod
        res.winner `shouldSatisfy` isNothing
        res.existing `shouldBe` []

    describe "distinctCopies" $ do
      it "keeps a file once when two tiers name it, at the rank of the first" $ \sb -> do
        p <- plant sb.rootDir embeddedMod
        let existing = [(1, FileCandidate "project root" p), (2, FileCandidate "importer-relative" p), (3, EmbeddedCandidate)]
        distinctCopies existing `shouldReturn` [(1, FileCandidate "project root" p), (3, EmbeddedCandidate)]

      it "merges a symlink with its target" $ \sb -> do
        target <- plant sb.elsewhere strayMod
        let link = sb.xdgLibs </> strayMod <.> "l4"
        linkOrPending target link
        let existing = [(1, FileCandidate "project root" target), (2, FileCandidate "XDG data dir" link)]
        distinctCopies existing `shouldReturn` [(1, FileCandidate "project root" target)]

      it "keeps two different files, and never merges the embed with a file" $ \sb -> do
        a <- plant sb.rootDir strayMod
        b <- plant sb.siblingDir strayMod
        let existing = [(1, FileCandidate "project root" a), (2, FileCandidate "importer-relative" b), (3, EmbeddedCandidate)]
        distinctCopies existing `shouldReturn` existing
