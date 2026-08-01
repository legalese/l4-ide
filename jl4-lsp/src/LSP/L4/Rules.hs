{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecordWildCards #-}

module LSP.L4.Rules where

import Base hiding (use)
import L4.Annotation
import L4.Citations
import qualified L4.Evaluate.ValueLazy as EvaluateLazy
import qualified L4.EvaluateLazy as EvaluateLazy
import qualified L4.ExactPrint as ExactPrint
import L4.FindReferences (ReferenceMapping(..), singletonReferenceMapping)
import L4.Lexer (PError, PosToken)
import qualified L4.Lexer as Lexer
import qualified L4.Parser as Parser
import qualified L4.Parser.ResolveAnnotation as Resolve
import L4.Parser.SrcSpan
import qualified L4.Print as Print
import L4.Syntax
import L4.TypeCheck (CheckErrorWithContext (..), CheckResult (..), Substitution, applyFinalSubstitution, toResolved)
import qualified L4.TypeCheck as TypeCheck
import qualified L4.Lint.AndOrDepth as Lint

import Control.Applicative
import Control.Monad.Trans.Maybe
import Data.Hashable (Hashable)
import Data.Monoid (Ap (..))
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Base.Text as Text
import qualified Data.Text.Mixed.Rope as Rope
import System.FilePath
import L4.Utils.IntervalMap (IntervalMap)
import Development.IDE.Graph
import LSP.Core.PositionMapping
import LSP.Core.RuleTypes
import LSP.Core.Shake hiding (Log)
import qualified LSP.Core.Shake as Shake
import LSP.Core.Types.Diagnostics
import LSP.L4.SemanticTokens
import LSP.Logger
import LSP.SemanticTokens
import Language.LSP.Protocol.Types
import qualified Language.LSP.Protocol.Types as LSP

import qualified Data.ByteString as BS
import qualified Data.List as List
import UnliftIO
import qualified Data.Set as Set
import qualified Data.Text.Encoding as TextEncoding
import System.Directory
import System.Environment (getExecutablePath, lookupEnv)
import qualified L4.API.EmbeddedLibraries as EmbeddedLibraries
import qualified L4.Utils.IntervalMap as IV

type instance RuleResult GetLexTokens = ([PosToken], Text)
data GetLexTokens = GetLexTokens
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

type instance RuleResult GetParsedAst = Module Name
data GetParsedAst = GetParsedAst
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

type instance RuleResult GetReverseDependencies = [NormalizedUri]
data GetReverseDependencies = GetReverseDependenciesNoCallStack
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

pattern GetReverseDependencies :: WithCallStack GetReverseDependencies
pattern GetReverseDependencies = AttachCallStack [] GetReverseDependenciesNoCallStack

type instance RuleResult ListRootDirectory = [NormalizedUri]
data ListRootDirectory = ListRootDirectory
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

type instance RuleResult ListOwnDirectory = [NormalizedUri]
data ListOwnDirectory = ListOwnDirectory
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

data ImportResult
  = MkImportResult
  { importName :: Name
  , importRange :: Maybe SrcRange
  , moduleUri :: NormalizedUri
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

type instance RuleResult GetImports = [ImportResult]
data GetImports = GetImports
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

type instance RuleResult GetMixfixRegistry = Parser.MixfixHintRegistry
data GetMixfixRegistry = GetMixfixRegistry
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

type instance RuleResult GetTypeCheckDependencies = [(ImportResult, TypeCheckResult)]
data GetTypeCheckDependencies = GetTypeCheckDependencies
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

type instance RuleResult TypeCheck = TypeCheckResult
data TypeCheck = TypeCheckNoCallstack
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

pattern TypeCheck :: WithCallStack TypeCheck
pattern TypeCheck = AttachCallStack [] TypeCheckNoCallstack

type instance RuleResult SuccessfulTypeCheck = TypeCheckResult
data SuccessfulTypeCheck = SuccessfulTypeCheck
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

data TypeCheckResult = TypeCheckResult
  { module' :: Module  Resolved
  , substitution :: Substitution
  , infoMap :: TypeCheck.InfoMap
  , nlgMap :: TypeCheck.NlgMap
  , scopeMap :: TypeCheck.ScopeMap
  , descMap :: TypeCheck.DescMap
  , success :: Bool
  , environment :: TypeCheck.Environment
  , entityInfo :: TypeCheck.EntityInfo
  , infos :: [TypeCheck.CheckErrorWithContext]  -- ^ Non-fatal diagnostics ('SInfo' and 'SWarn'); don't block 'success'
  , errors :: [TypeCheck.CheckErrorWithContext]  -- ^ Actual errors ('SError' only, e.g. OutOfScopeError) for implicit ASSUME extraction
  , dependencies :: [TypeCheckResult]
  , mixfixRegistry :: TypeCheck.MixfixRegistry
  }
  deriving stock (Generic)

-- | instance that doesn't force the intervalmaps because they're very large and their values are sometimes expensive
instance NFData TypeCheckResult where
  rnf TypeCheckResult {..} =
    rnf module'
    `seq` rnf substitution
    `seq` infoMap
    `seq` nlgMap
    `seq` scopeMap
    `seq` descMap
    `seq` rnf success
    `seq` rnf environment
    `seq` rnf entityInfo
    `seq` rnf infos
    `seq` rnf errors
    `seq` rnf dependencies
    `seq` rnf mixfixRegistry

type instance RuleResult EvaluateLazy = [EvaluateLazy.EvalDirectiveResult]
data EvaluateLazy = EvaluateLazy
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

type instance RuleResult GetLazyEvaluationDependencies = (EvaluateLazy.Environment, [EvaluateLazy.EvalDirectiveResult])
data GetLazyEvaluationDependencies = GetLazyEvaluationDependencies
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

type instance RuleResult LexerSemanticTokens = [SemanticToken]
data LexerSemanticTokens = LexerSemanticTokens
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

type instance RuleResult ParserSemanticTokens = [SemanticToken]
data ParserSemanticTokens = ParserSemanticTokens
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

type instance RuleResult TypeCheckedSemanticTokens = [SemanticToken]
data TypeCheckedSemanticTokens = TypeCheckedSemanticTokens
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

type instance RuleResult GetSemanticTokens = [SemanticToken]
data GetSemanticTokens = GetSemanticTokens
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

type instance RuleResult GetRelSemanticTokens = [UInt]
data GetRelSemanticTokens = GetRelSemanticTokens
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

-- TODO:
-- in future we want to have SrcPos |-> Uri s.t. we can resolve
-- relative locations based on the scope, i.e. if we have
-- DECLARE foo <<british nationality act>>
--   IF bar <<sec. 3>>
-- then this should assemble the uri into one link based on
-- an uri scheme described in the original file
type instance RuleResult ResolveReferenceAnnotations = IntervalMap SrcPos (NormalizedUri, Int, Maybe Text)
data ResolveReferenceAnnotations = ResolveReferenceAnnotations
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

type instance RuleResult GetReferences = ReferenceMapping
data GetReferences = GetReferences
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

type instance RuleResult ExactPrint = Text
data ExactPrint = ExactPrint
  deriving stock (Generic, Show, Eq)
  deriving anyclass (NFData, Hashable)

-- Note: ReferenceMapping, singletonReferenceMapping, and lookupReference
-- are imported from L4.FindReferences (shared with WASM mode)

data Log
  = ShakeLog Shake.Log
  | LogTraverseAnnoError !Text !TraverseAnnoError
  | LogRelSemanticTokenError !Text
  | LogSemanticTokens !Text [SemanticToken]
  | LogImportResolution !Text

instance Pretty Log where
  pretty = \ case
    ShakeLog msg -> pretty msg
    LogTraverseAnnoError herald msg -> pretty herald <> ":" <+> pretty (prettyTraverseAnnoError msg)
    LogRelSemanticTokenError msg -> "Semantic Token " <+> pretty msg
    LogSemanticTokens herald toks ->
      "Semantic Tokens of" <+> pretty herald <> line <> indent 2 (vcat (fmap prettyToken toks))
      where
        prettyToken :: SemanticToken -> Doc ann
        prettyToken s =
          pretty s.start._line <> ":" <> pretty s.start._character <> "-"
            <> pretty (s.start._character + s.length)
            <+> pretty s.category
    LogImportResolution msg -> "[Import Resolution]" <+> pretty msg

-- | One candidate source for a bare-module-name import.
data LibraryCandidate
  = FileCandidate !Text !FilePath
    -- ^ label (for logs) and filesystem path to probe
  | EmbeddedCandidate
    -- ^ the stdlib copy compiled into this binary ('L4.API.EmbeddedLibraries').
    -- NOTE: the embed is frozen at /build/ time from the Cabal datadir the TH
    -- splice resolved then (often @~/.cabal/share@) — editing a checkout's
    -- @jl4-core/libraries/*.l4@ does NOT refresh it on a plain @cabal build@.
    -- When developing the stdlib itself, pin @JL4_LIBRARY_PATH@ at your
    -- worktree's @jl4-core/libraries@ (see @jl4-core/libraries/README.md@).
  deriving stock (Eq, Show)

candidateDisplay :: LibraryCandidate -> Text
candidateDisplay = \case
  FileCandidate lbl p -> lbl <> ": " <> Text.pack p
  EmbeddedCandidate   -> "embedded stdlib (compiled into this binary)"

-- | Result of library resolution over the filesystem + embedded tiers.
data LibraryResolution = LibraryResolution
  { winner          :: !(Maybe (Int, LibraryCandidate))
    -- ^ first existing candidate (1-based index into 'candidates'), if any
  , existing        :: ![(Int, LibraryCandidate)]
    -- ^ /every/ candidate that exists, in precedence order — kept so callers
    -- can detect when a lower-priority copy is being shadowed (spec Option E)
  , candidates      :: ![LibraryCandidate]  -- ^ full ordered list probed
  , searchedPaths   :: ![FilePath]          -- ^ filesystem paths probed (for the not-found diagnostic)
  , hasExplicitPath :: !Bool                -- ^ True if JL4_LIBRARY_PATH is set (embedded copy not consulted)
  }

-- | Resolve a library module across the filesystem and the embedded stdlib.
-- Candidates are probed in order of priority (first existing wins):
--
--   1. JL4_LIBRARY_PATH environment variable (user/operator override)
--   2. Root directory (project-local)
--   3. Relative to importing file
--   4. Embedded stdlib compiled into this binary
--   5. XDG data directory (~/.local/share/jl4/libraries/)
--   6. Bundled with VSCode extension (../../libraries from executable)
--
-- The project-scoped tiers (1–3) rank above the embedded copy so intentional
-- overrides keep working; the ambient machine-global tiers (5–6) rank /below/
-- it so a stray XDG symlink or stale bundle can no longer silently shadow the
-- stdlib the binary was built with (LIBRARY-RESOLUTION-SHADOW-SPEC, Option B′).
-- The ambient tiers still matter for modules the embed does not carry — e.g. a
-- bundle shipping extra libraries.
--
-- When JL4_LIBRARY_PATH is set, the embedded copy is not consulted at all —
-- the operator has taken explicit control of the library store.
resolveLibrary :: FilePath -> Maybe NormalizedFilePath -> String -> IO LibraryResolution
resolveLibrary rootDirectory mImportingFile modName = do
  mEnvPath <- lookupEnv "JL4_LIBRARY_PATH"
  xdgDataDir <- getXdgDirectory XdgData "jl4"
  exePath <- getExecutablePath

  let hasExplicit = Maybe.isJust mEnvPath
      libFile dir = dir </> modName <.> "l4"
      exeDir = takeDirectory exePath
      extensionRoot = exeDir </> ".." </> ".."

      envCands     = [ FileCandidate "$JL4_LIBRARY_PATH" (libFile p) | Just p <- [mEnvPath] ]
      rootCand     = FileCandidate "project root" (libFile rootDirectory)
      siblingCands = [ FileCandidate "importer-relative" (libFile (takeDirectory (fromNormalizedFilePath nfp)))
                     | Just nfp <- [mImportingFile] ]
      xdgCand      = FileCandidate "XDG data dir" (xdgDataDir </> "libraries" </> modName <.> "l4")
      bundledCand  = FileCandidate "VSCode bundle" (extensionRoot </> "libraries" </> modName <.> "l4")

      cands = envCands <> [rootCand] <> siblingCands
           <> [ EmbeddedCandidate | not hasExplicit ]
           <> [xdgCand, bundledCand]

      probe (i, c) = case c of
        FileCandidate _ p -> do
          ok <- doesFileExist p
          pure $ if ok then Just (i, c) else Nothing
        EmbeddedCandidate ->
          pure $ if Maybe.isJust (EmbeddedLibraries.lookupEmbeddedLibrary (Text.pack modName))
                   then Just (i, c) else Nothing

  present <- catMaybes <$> traverse probe (zip [1 :: Int ..] cands)

  pure LibraryResolution
    { winner = Maybe.listToMaybe present
    , existing = present
    , candidates = cands
    , searchedPaths = [ p | FileCandidate _ p <- cands ]
    , hasExplicitPath = hasExplicit
    }

-- | Fetch a candidate's content for the shadow check ('warnOnLibraryShadow').
-- File reads are byte-level so the comparison is not locale-sensitive.
candidateContent :: String -> LibraryCandidate -> IO (Maybe BS.ByteString)
candidateContent modName = \case
  FileCandidate _ p -> either (\(_ :: SomeException) -> Nothing) Just <$> tryAny (BS.readFile p)
  EmbeddedCandidate -> pure $ TextEncoding.encodeUtf8 <$> EmbeddedLibraries.lookupEmbeddedLibrary (Text.pack modName)

-- | Canonicalized display of a candidate: when the probed path is a symlink
-- (or otherwise not canonical), append its real target, so a log reader can
-- see /which checkout/ a machine-global entry actually points at.
candidateDisplayCanonical :: LibraryCandidate -> IO Text
candidateDisplayCanonical c = case c of
  EmbeddedCandidate -> pure (candidateDisplay c)
  FileCandidate _ p -> do
    real <- either (\(_ :: SomeException) -> p) id <$> tryAny (canonicalizePath p)
    pure $ candidateDisplay c <> if real == p then "" else " -> " <> Text.pack real

-- | What one import resolved to, plus everything that was tried (for the
-- not-found diagnostic).
data ImportOutcome = ImportOutcome
  { importUri  :: !(Maybe NormalizedUri)
  , vfsTried   :: ![NormalizedUri]
  , pathsTried :: ![FilePath]
  , embedTried :: !EmbedStatus
    -- ^ What happened at the embedded tier. Kept SEPARATE from 'pathsTried'
    -- because the embed has no path, and the not-found diagnostic listed only
    -- paths — so the one tier that can silently be empty was the one tier the
    -- error could not mention. See 'renderEmbedStatus'.
  }

-- | The embedded-stdlib tier, as the not-found diagnostic needs to describe it.
data EmbedStatus
  = EmbedSkipped
    -- ^ @JL4_LIBRARY_PATH@ is set, so the embed was deliberately not consulted.
  | EmbedEmpty
    -- ^ Consulted, and this binary carries NO embedded libraries at all.
    --
    -- __Unreachable in a binary built from this tree__, because the @fail@ in
    -- "L4.API.EmbeddedLibraries" now stops such a binary from being produced.
    -- Kept anyway: it costs three lines, it explains the failure for the many
    -- already-installed binaries that predate that @fail@, and if the guard is
    -- ever weakened this is the message that says what went wrong.
  | EmbedMissing !Int
    -- ^ Consulted, carries @n@ modules, and this one is not among them.
  deriving stock (Eq, Show)

-- | One entry for the not-found diagnostic's list of tried locations.
renderEmbedStatus :: EmbedStatus -> Text
renderEmbedStatus = \ case
  EmbedSkipped   -> "the stdlib embedded in this binary (skipped: JL4_LIBRARY_PATH is set)"
  EmbedMissing n -> "the stdlib embedded in this binary (" <> Text.pack (show n) <> " modules, not among them)"
  EmbedEmpty     -> Text.unlines
    [ "the stdlib embedded in this binary -- WHICH IS EMPTY."
    , "  That is a BUILD DEFECT, not a problem with your file: this binary carries no"
    , "  standard libraries at all, so no IMPORT of one can ever succeed. If it came"
    , "  from `cabal install`, check that jl4-core.cabal's `data-files` field still"
    , "  precedes every section (`cabal check` reports it if not) and rebuild."
    ]

-- | Resolve one bare-module-name import. This is the /single/ resolution code
-- path shared by 'GetMixfixRegistry' (parser-hint resolution) and 'GetImports'
-- (typecheck-dependency resolution), so the two rules can never load different
-- sources for the same import (LIBRARY-RESOLUTION-SHADOW-SPEC §3.3): a module
-- must not parse against source A while typechecking against source B.
--
-- VFS candidates (web/editor in-memory overlays) are checked first, then the
-- filesystem + embedded tiers via 'resolveLibrary'. An embedded winner is
-- registered as a Shake virtual file, exactly as a VFS hit would be.
resolveImportShared
  :: Recorder (WithPriority Log)
  -> IORef (Set.Set (String, [Text]))
     -- ^ shadow configurations already warned about this session (warn-once)
  -> FilePath          -- ^ root directory
  -> NormalizedUri     -- ^ importing module
  -> String            -- ^ bare module name
  -> Action ImportOutcome
resolveImportShared recorder shadowWarnedRef rootDirectory importerUri modName = do
  logWith recorder Info $ LogImportResolution $
    "Resolving import: " <> Text.pack modName <> " from " <> (fromNormalizedUri importerUri).getUri

  -- VFS tier: project:/ scheme (Monaco), importer-relative, root-relative.
  --
  -- These candidates are /speculative/: they are probed before anything is
  -- known to exist there. So the URIs they can name are exactly the URIs a
  -- module can be hijacked at, and nothing that must rank below the filesystem
  -- tier may be reachable from here. That is why the embedded stdlib lives
  -- outside the @file:@ scheme ('Shake.embeddedLibraryUri') rather than at
  -- @./<name>.l4@, which both @rootDirectory == "."@ and a bare embedded
  -- importer URI used to forge.
  let projectUri = toNormalizedUri $ Uri $ Text.pack $ "project:/" <> modName <.> "l4"
      -- 'Nothing' for a non-file importer — notably an embedded library, which
      -- has no directory and so contributes no sibling candidate. Its imports
      -- are then ranked by 'resolveLibrary' alone (project root above embedded,
      -- per Option B′), the same ranking every other importer gets: one module
      -- name stays bound to one source across the whole build.
      relativeUri = do
        nfp <- uriToNormalizedFilePath importerUri
        let dir = takeDirectory $ fromNormalizedFilePath nfp
        pure $ toNormalizedUri $ filePathToUri $ dir </> modName <.> "l4"
      rootUri = toNormalizedUri $ filePathToUri $ rootDirectory </> modName <.> "l4"
      vfsUris = [projectUri] <> Maybe.maybeToList relativeUri <> [rootUri]

  logWith recorder Debug $ LogImportResolution $
    "Checking VFS URIs: " <> Text.intercalate ", " (map ((.getUri) . fromNormalizedUri) vfsUris)

  let checkVfsUri candidateUri = do
        mContent <- use GetFileContents candidateUri
        case mContent of
          Just (_, Just _rope) -> do
            logWith recorder Info $ LogImportResolution $
              "VFS HIT: " <> (fromNormalizedUri candidateUri).getUri
            pure $ Just candidateUri
          _ -> do
            logWith recorder Debug $ LogImportResolution $
              "VFS MISS: " <> (fromNormalizedUri candidateUri).getUri
            pure Nothing

  vfsResult <- runMaybeT $ asum $ map (MaybeT . checkVfsUri) vfsUris

  case vfsResult of
    Just vfsUri -> do
      logWith recorder Info $ LogImportResolution $
        "Found in VFS: " <> (fromNormalizedUri vfsUri).getUri
      -- Resolved above the library tiers entirely, so the embed was never reached.
      pure ImportOutcome { importUri = Just vfsUri, vfsTried = vfsUris, pathsTried = []
                         , embedTried = EmbedSkipped }
    Nothing -> do
      let mImportingNfp = uriToNormalizedFilePath importerUri
      res <- liftIO $ resolveLibrary rootDirectory mImportingNfp modName

      -- Detailed candidate accounting + the shadow warning run only when
      -- JL4_LIBRARY_PATH is unset: with the env var set the operator has
      -- already taken explicit control (and the golden suites pin it — their
      -- captured logs must stay machine-independent, while the ambient XDG /
      -- bundle state that this reporting exists to expose is exactly the
      -- machine-dependent part).
      unless res.hasExplicitPath $ do
        statuses <- traverse
          (\(i, c) -> do
            shown <- liftIO $ candidateDisplayCanonical c
            let hit = i `elem` map fst res.existing
            pure $ "[" <> Text.pack (show i) <> "] " <> shown <> (if hit then " (hit)" else " (miss)"))
          (zip [1 :: Int ..] res.candidates)
        logWith recorder Debug $ LogImportResolution $
          "Candidate order for " <> Text.pack modName <> ": " <> Text.intercalate "; " statuses
        warnOnLibraryShadow res

      let embedStatus
            | res.hasExplicitPath = EmbedSkipped
            | n == 0              = EmbedEmpty
            | otherwise           = EmbedMissing n
            where n = Map.size EmbeddedLibraries.embeddedLibraries
          outcome mUri = ImportOutcome
            { importUri = mUri, vfsTried = vfsUris, pathsTried = res.searchedPaths
            , embedTried = embedStatus }

      case res.winner of
        Just (ix, FileCandidate _ fp) -> do
          msg <-
            if res.hasExplicitPath
              then -- Historical wording, captured verbatim by the golden suite
                   -- (which always pins JL4_LIBRARY_PATH); keep it stable.
                   pure $ "Found on filesystem: " <> Text.pack fp
              else do
                real <- liftIO $ either (\(_ :: SomeException) -> fp) id <$> tryAny (canonicalizePath fp)
                pure $ "Found on filesystem (candidate " <> Text.pack (show ix) <> " of "
                     <> Text.pack (show (length res.candidates)) <> "): " <> Text.pack fp
                     <> (if real == fp then "" else " -> " <> Text.pack real)
          logWith recorder Info $ LogImportResolution msg
          pure $ outcome $ Just $ toNormalizedUri $ filePathToUri fp
        Just (ix, EmbeddedCandidate) -> do
          logWith recorder Info $ LogImportResolution $
            "Found in embedded libraries (candidate " <> Text.pack (show ix) <> " of "
            <> Text.pack (show (length res.candidates)) <> "): " <> Text.pack modName
          case EmbeddedLibraries.lookupEmbeddedLibrary (Text.pack modName) of
            Just _ ->
              -- No VFS write: the embedded copy is already readable at its
              -- canonical URI via 'Shake.embeddedLibraryVfs'. Registering it
              -- here would only re-introduce the mid-rule VFS mutation whose
              -- ordering-dependence caused #906 in the first place.
              pure $ outcome $ Just $ Shake.embeddedLibraryUri (Text.pack modName)
            Nothing ->
              -- Cannot happen: 'resolveLibrary' only lists 'EmbeddedCandidate'
              -- as existing when the lookup succeeds. Fail soft regardless.
              pure $ outcome Nothing
        Nothing
          | res.hasExplicitPath -> do
              logWith recorder Warning $ LogImportResolution $
                "Module not found (JL4_LIBRARY_PATH is set, embedded libs skipped): " <> Text.pack modName
              pure $ outcome Nothing
          | otherwise -> do
              logWith recorder Warning $ LogImportResolution $
                "Module not found: " <> Text.pack modName
              pure $ outcome Nothing
  where
    -- Option E of LIBRARY-RESOLUTION-SHADOW-SPEC: when several copies of the
    -- same module are visible AND their contents differ, name them all (with
    -- symlinks dereferenced) and say which one wins. Identical copies (e.g. an
    -- XDG symlink pointing at the very sources the embed was built from) stay
    -- silent. Warned once per distinct configuration per session.
    warnOnLibraryShadow res =
      when (length res.existing >= 2) $ do
        contents <- liftIO $ traverse (\(_, c) -> candidateContent modName c) res.existing
        let distinct = List.nub (catMaybes contents)
        when (length distinct >= 2) $ do
          shownAll <- liftIO $ traverse (candidateDisplayCanonical . snd) res.existing
          let key = (modName, shownAll)
          fresh <- UnliftIO.atomicModifyIORef' shadowWarnedRef $ \s ->
            if Set.member key s then (s, False) else (Set.insert key s, True)
          when fresh $ do
            let mark i = if Just i == fmap fst res.winner then "[chosen]   " else "[shadowed] "
                rows = zipWith (\(i, _) shown -> "  " <> mark i <> shown) res.existing shownAll
            logWith recorder Warning $ LogImportResolution $ Text.unlines $
              [ "Multiple differing copies of module `" <> Text.pack modName <> "` are visible:" ]
              <> rows
              <> [ "The [chosen] copy is used wherever this module is imported. To use a"
                 , "different copy, set JL4_LIBRARY_PATH or place " <> Text.pack modName
                   <> ".l4 in the project root or beside the importing file."
                 ]

jl4Rules :: EvaluateLazy.EvalConfig -> FilePath -> Recorder (WithPriority Log) -> Rules ()
jl4Rules evalConfig rootDirectory recorder = do
  -- Session-scoped memory for 'resolveImportShared''s shadow warning, so a
  -- given shadow configuration is reported once, not on every re-resolution.
  shadowWarnedRef <- UnliftIO.newIORef Set.empty
  let resolveImport :: NormalizedUri -> String -> Action ImportOutcome
      resolveImport = resolveImportShared recorder shadowWarnedRef rootDirectory

  define shakeRecorder $ \GetLexTokens uri -> do
    mRope <- runMaybeT $
      MaybeT (snd <$> use_ GetFileContents uri)
      <|> do
        -- TODO: how do we actually invalidate this VFS file
        -- (except by opening in the same editor session)
        -- do we check the last modified time or smth like that?
        -- I think basically as it is now we don't do anything like
        -- that and the current time check is basically redundant
        file <- hoistMaybe $ uriToNormalizedFilePath uri
        lift $ addVirtualFileFromFS file

    case mRope of
      Nothing -> pure ([mkSimpleFileDiagnostic uri (mkSimpleDiagnostic (fromNormalizedUri uri).getUri "could not obtain file contents" Nothing)], Nothing)
      Just rope -> do
        let contents = Rope.toText rope
        case Lexer.execLexer uri contents of
          Left errs -> do
            let diags = toList $ fmap mkParseErrorDiagnostic errs
            pure (fmap (mkSimpleFileDiagnostic uri) diags, Nothing)
          Right ts ->
            pure ([], Just (ts, contents))

  -- | GetMixfixRegistry collects mixfix hints from the current module AND all imports.
  -- This enables cross-module mixfix resolution.
  define shakeRecorder $ \GetMixfixRegistry uri -> do
    (tokens, contents) <- use_ GetLexTokens uri
    case Parser.execProgramParserForTokens uri contents tokens of
      Left _errs ->
        -- If we can't parse at all, return empty registry
        pure ([], Just Parser.emptyMixfixHintRegistry)
      Right (firstProg, _) -> do
        -- Get local mixfix hints from this module
        let localHints = Parser.buildMixfixHintRegistry firstProg

        -- Extract imports from first-pass parse (import syntax doesn't need mixfix)
        let extractImport :: TopDecl Name -> [Name]
            extractImport = \case
              Import _ (MkImport _ n _) -> [n]
              _ -> []
            importNames = foldTopDecls extractImport firstProg

        -- Resolve import URIs via the exact code path GetImports uses
        -- ('resolveImportShared'), so parser-hint resolution can never pick a
        -- different source than typecheck resolution (spec §3.3).
        let resolveImportUri :: Name -> Action (Maybe NormalizedUri)
            resolveImportUri n = do
              let modName = takeBaseName $ Text.unpack $ rawNameToText $ rawName n
              outcome <- resolveImport uri modName
              pure outcome.importUri

        -- Resolve all import URIs
        resolvedUris <- catMaybes <$> traverse resolveImportUri importNames

        -- Recursively get mixfix hints from imported modules
        importedHints <- mconcat . catMaybes <$> uses GetMixfixRegistry resolvedUris

        -- Combine local + imported hints
        let combinedHints = localHints <> importedHints
        pure ([], Just combinedHints)

  define shakeRecorder $ \GetParsedAst uri -> do
    (tokens, contents) <- use_ GetLexTokens uri
    -- Get combined mixfix hints (local + all imports)
    combinedHints <- use_ GetMixfixRegistry uri
    -- Parse with full mixfix knowledge
    case Parser.execProgramParserForTokensWithHints combinedHints uri contents tokens of
      Left errs -> do
        let diags = toList $ fmap mkParseErrorDiagnostic errs
        pure (fmap (mkSimpleFileDiagnostic uri) diags , Nothing)
      Right (finalProg, warns) -> do
        let nlgDiags = fmap mkNlgWarning warns
            lintDiags = fmap mkAndOrLintWarning $ Lint.checkAndOrDepth finalProg
            allDiags = nlgDiags <> lintDiags
        pure (fmap (mkSimpleFileDiagnostic uri) allDiags, Just finalProg)

  define shakeRecorder $ \GetImports uri -> do
    let -- NOTE: we curently don't allow any relative or absolute file paths, just bare module names
        mkImportPath :: Import Name -> Action (Maybe SrcRange, String, ImportOutcome)
        mkImportPath (MkImport a n _mr) = do
          let modName = takeBaseName $ Text.unpack $ rawNameToText $ rawName n
          outcome <- resolveImport uri modName
          pure (rangeOf a, modName, outcome)

        mkImportUri (range, modName, outcome) = case outcome.importUri of
          Just u ->
            pure ([], range, u)
          Nothing ->
            -- nub: the CLI sets the project root to the importing file's own
            -- directory, so the root and importer-relative tiers coincide and
            -- the list used to repeat every path twice.
            let allPaths = List.nub
                  ( map ((.getUri) . fromNormalizedUri) outcome.vfsTried
                 <> map Text.pack outcome.pathsTried )
                 <> [renderEmbedStatus outcome.embedTried]
                diag = mkSimpleFileDiagnostic uri
                  $ mkSimpleDiagnostic
                    (fromNormalizedUri uri).getUri
                    (Text.unlines
                      [ "I could not find a module with this name: " <> Text.pack modName
                      , "I have tried the following locations:"
                      , Text.intercalate ",\n" allPaths
                      ])
                    (fromSrcRange <$> range)
             in pure ([diag], range, uri)

        mkDiagsAndImports :: TopDecl Name -> Ap Action [([FileDiagnostic], ImportResult)]
        mkDiagsAndImports = \ case
          Import _a i@(MkImport _ n _) -> Ap do
            (diag, r, u) <- mkImportUri =<< mkImportPath i
            pure [(diag, MkImportResult n r u)]
          _ -> pure []


    prog <- use_ GetParsedAst uri
    (diags, imports) <- fmap unzip $ getAp $ foldTopDecls mkDiagsAndImports prog
    pure (concat diags, Just imports)

  defineWithCallStack shakeRecorder $ \GetTypeCheckDependencies cs uri -> do
    imports <- use_  GetImports uri
    ress    <- fmap catMaybes $ zipWith (\res mres -> (res,) <$> mres) imports <$> uses (AttachCallStack cs TypeCheckNoCallstack) (map (.moduleUri) imports)
    pure ([], Just ress)

  defineWithCallStack shakeRecorder $ \TypeCheckNoCallstack cs uri -> do
    parsed       <- use_ GetParsedAst uri
    (imported, dependencies) <- unzip <$> use_ (AttachCallStack (uri : cs) GetTypeCheckDependencies) uri

    let parsedAndAnnotated = overImports (updateImport $ map (\res -> (res.importName, res.moduleUri)) imported) parsed

    let unionCheckStates :: TypeCheck.CheckState -> TypeCheckResult -> TypeCheck.CheckState
        unionCheckStates cState tcRes =
          TypeCheck.MkCheckState
          { substitution = tcRes.substitution
          , supply = cState.supply
          , infoMap = IV.empty
          , nlgMap = IV.empty
          , scopeMap = IV.empty
          , descMap = IV.empty
          , constBodies = cState.constBodies
          , sectionPaths = cState.sectionPaths
          }
        -- NOTE: tcRes.entityInfo is already zonked (the final substitution is
        -- applied when the TypeCheckResult is built below), as
        -- 'unionImportedCheckEnv' requires.
        unionCheckEnv cEnv tcRes =
          TypeCheck.unionImportedCheckEnv cEnv tcRes.environment tcRes.entityInfo tcRes.mixfixRegistry
        -- NOTE: we don't want to leak the inference variables from the substitution
        initCheckState = set #substitution Map.empty $ foldl' unionCheckStates TypeCheck.initialCheckState dependencies
        initCheckEnv = foldl' unionCheckEnv (TypeCheck.initialCheckEnv uri) dependencies
        result = TypeCheck.doCheckProgramWithDependencies initCheckState initCheckEnv parsedAndAnnotated
        -- NOTE: only 'SError' diagnostics count against 'success'; 'SInfo' and
        -- 'SWarn' (e.g. exhaustiveness/redundancy warnings) are non-fatal.
        -- All diagnostics are still published to the editor below regardless
        -- of this partition — it only decides what blocks 'SuccessfulTypeCheck'.
        (infos, errors) = partition ((/= TypeCheck.SError) . TypeCheck.severity) result.errors
    pure
      ( fmap (checkErrorToDiagnostic >>= mkFileDiagnosticWithSource uri) result.errors
      , Just TypeCheckResult
        { module' = result.program
        , substitution = result.substitution
        , environment = result.environment
        , entityInfo = applyFinalSubstitution result.substitution uri result.entityInfo
        , success = null errors
        , infos
        , errors  -- Include actual errors (OutOfScopeError etc.) for implicit ASSUME extraction
        , infoMap = result.infoMap
        , nlgMap = result.nlgMap
        , scopeMap = result.scopeMap
        , descMap = result.descMap
        , dependencies = dependencies <> foldMap (.dependencies) dependencies
        , mixfixRegistry = result.mixfixRegistry
        }
      )

  define shakeRecorder \ListRootDirectory _emptyUri -> do
    cts <- liftIO $ listL4Files rootDirectory
    pure ([], Just cts)

  define shakeRecorder \ListOwnDirectory uri -> do
    case fromNormalizedFilePath <$> uriToNormalizedFilePath uri of
      Nothing -> pure ([], Just [])
      Just fp -> liftIO do
        uris <- listL4Files $ takeDirectory fp
        pure ([], Just uris)

  -- NOTE: currently it's not possible to get references coming from the original reference
  defineWithCallStack shakeRecorder $ \GetReverseDependenciesNoCallStack cs uri -> do
    potentialDependencies <-
      (<>)
        <$> useNoFile_ ListRootDirectory
        <*> use_ ListOwnDirectory uri
    importers <-
      mapMaybe
        (\(importerUri, imports) -> if uri `elem` map (.moduleUri) imports then Just importerUri else Nothing)
       . zip potentialDependencies
       <$> uses_ GetImports potentialDependencies
    transitiveImporters <- concat <$> uses_ (AttachCallStack (uri : cs) GetReverseDependenciesNoCallStack) importers
    pure ([], Just $ importers <> transitiveImporters)

  define shakeRecorder $ \SuccessfulTypeCheck f -> do
    typeCheckResult <- use_ TypeCheck f
    if typeCheckResult.success
      then pure ([], Just typeCheckResult)
      else pure ([], Nothing)

  defineWithCallStack shakeRecorder $ \GetLazyEvaluationDependencies cs f -> do
    imports <- use_  GetImports f
    tcRes   <- use_  SuccessfulTypeCheck f
    -- TODO: when checking for cycles, we should check which one is the
    -- first element in the cycle that is, i.e. which IMPORT, then scan
    -- for the IMPORT again and
    -- put the diagnostic on that IMPORT
    deps    <- fmap catMaybes $ uses (AttachCallStack (f : cs) GetLazyEvaluationDependencies) $ map (.moduleUri) imports
    let environment = mconcat (fst <$> deps)
    (ownEnv, ownDirectives) <- liftIO (EvaluateLazy.execEvalModuleWithEnv evalConfig tcRes.entityInfo environment tcRes.module')
    pure ([], Just (ownEnv <> environment, ownDirectives))

  define shakeRecorder $ \EvaluateLazy uri -> do
    res  <- use_ (AttachCallStack [uri] GetLazyEvaluationDependencies) uri
    let results = snd res
    pure (mkSimpleFileDiagnostic uri . evalLazyResultToDiagnostic <$> results, Just results)

  define shakeRecorder $ \LexerSemanticTokens f -> do
    (tokens, _) <- use_ GetLexTokens f
    case runSemanticTokensM (defaultSemanticTokenCtx ()) tokens of
      Left err -> do
        logWith recorder Error $ LogTraverseAnnoError "Lexer" err
        pure ([], Nothing)
      Right tokenized -> do
        pure ([], Just tokenized)

  define shakeRecorder $ \ParserSemanticTokens f -> do
    prog <- use_ GetParsedAst f
    case runSemanticTokensM (defaultSemanticTokenCtx CValue) prog of
      Left err -> do
        logWith recorder Error $ LogTraverseAnnoError "Parser" err
        pure ([], Nothing)
      Right tokenized -> do
        pure ([], Just tokenized)

  define shakeRecorder $ \TypeCheckedSemanticTokens f -> do
    tcRes <- use_ SuccessfulTypeCheck f
    case runSemanticTokensM (defaultSemanticTokenCtx ()) tcRes.module' of
      Left err -> do
        logWith recorder Error $ LogTraverseAnnoError "TypeCheck" err
        pure ([], Nothing)
      Right tokenized -> do
        pure ([], Just tokenized)

  define shakeRecorder $ \GetSemanticTokens f -> do
    toks <-
      semanticTokensUsing
        -- Order matters, 'SemanticTokens' earlier in the list are preferred over later ones.
        [ useWithOptionalStale TypeCheckedSemanticTokens
        , useWithOptionalStale ParserSemanticTokens
        , useWithOptionalStale LexerSemanticTokens
        ]
        f
    pure ([], Just toks)

  define shakeRecorder $ \GetRelSemanticTokens f -> do
    tokens <- use_ GetSemanticTokens f
    -- Sort tokens by position before relativizing. The type-checked semantic tokens
    -- may be returned in a different order than their source positions, which breaks
    -- relativizeTokens (it computes relative positions assuming sorted input).
    let sortedTokens = List.sortOn (.start) tokens
    let semanticTokens = relativizeTokens $ fmap toSemanticTokenAbsolute sortedTokens
    case encodeTokens defaultSemanticTokensLegend semanticTokens of
      Left err -> do
        logWith recorder Error $ LogRelSemanticTokenError err
        pure ([], Nothing)
      Right relSemTokens ->
          pure ([], Just relSemTokens)
  define shakeRecorder $ \ResolveReferenceAnnotations uri -> do
      (tokens, _) <- use_ GetLexTokens uri

      -- Collect @ref-map annotations from tokens
      -- Note: @ref-src (CSV file loading) has been removed for WASM compatibility
      let references = foldMap withRefMap tokens

          mps = if null references
            then Nothing
            else Just $ mkReferences tokens references

      pure ([], mps)

  define shakeRecorder $ \GetReferences uri -> do
    tcRes <- use_ TypeCheck uri

    let spanOf resolved
          = maybe
              mempty
              (singletonReferenceMapping $ getUnique resolved)
              -- NOTE: the source range of the actual Name
              (rangeOf resolved)

        refMapping :: ReferenceMapping
          = foldMap spanOf
          $ toResolved tcRes.module'
            <> foldMap (toResolved . (.module')) tcRes.dependencies

    pure ([], Just refMapping)

  define shakeRecorder $ \ExactPrint f -> do
    parsed <- use_ GetParsedAst f
    let pfp = (fromNormalizedUri f).getUri
    pure case ExactPrint.exactprint parsed of
      Left trErr -> ([mkSimpleFileDiagnostic f $ mkSimpleDiagnostic pfp (prettyTraverseAnnoError trErr) Nothing], Nothing)
      Right ep'd -> ([], Just ep'd)

  where
    shakeRecorder = cmapWithPrio ShakeLog recorder
    mkSimpleFileDiagnostic nfp diag =
      FileDiagnostic
        { fdFilePath = nfp
        , fdShouldShowDiagnostic = ShowDiag
        , fdLspDiagnostic = diag
        , fdOriginalSource = NoMessage
        }

    mkFileDiagnosticWithSource nfp diag orig =
      FileDiagnostic
        { fdFilePath = nfp
        , fdShouldShowDiagnostic = ShowDiag
        , fdLspDiagnostic = diag
        , fdOriginalSource = MkSomeMessage orig
        }

    mkNlgWarning :: Resolve.Warning -> Diagnostic
    mkNlgWarning warn =
        Diagnostic
          { _range = rangeOfResolveWarning warn
          , _severity = Just LSP.DiagnosticSeverity_Warning
          , _code = Nothing
          , _codeDescription = Nothing
          , _source = Just "parser"
          , _message = prettyNlgResolveWarning warn
          , _tags = Nothing
          , _relatedInformation = Nothing
          , _data_ = Nothing
          }

    mkAndOrLintWarning :: Lint.AndOrWarning -> Diagnostic
    mkAndOrLintWarning warn =
        Diagnostic
          { _range = srcRangeToLspRange warn.warningRange
          , _severity = Just LSP.DiagnosticSeverity_Warning
          , _code = Nothing
          , _codeDescription = Nothing
          , _source = Just "linter"
          , _message = Text.pack $ "AND and OR operators appear at the same indentation level (column " <> show warn.conflictingColumn <> "). This may indicate a precedence error - please use indentation to clarify precedence; in a pinch, parentheses may also be used."
          , _tags = Nothing
          , _relatedInformation = Nothing
          , _data_ = Nothing
          }

    mkParseErrorDiagnostic :: PError -> Diagnostic
    mkParseErrorDiagnostic parseError = mkSimpleDiagnostic parseError.origin parseError.message (Just parseError.range)

    mkSimpleDiagnostic :: Text -> Text -> Maybe SrcSpan -> Diagnostic
    mkSimpleDiagnostic origin _message range =
      Diagnostic
        { _range = srcSpanToLspRange range
        , _severity = Just LSP.DiagnosticSeverity_Error
        , _code = Nothing
        , _codeDescription = Nothing
        , _source = Just origin
        , _message
        , _tags = Nothing
        , _relatedInformation = Nothing
        , _data_ = Nothing
        }

    evalLazyResultToDiagnostic :: EvaluateLazy.EvalDirectiveResult -> Diagnostic
    evalLazyResultToDiagnostic r@(EvaluateLazy.MkEvalDirectiveResult range res _mtrace _ledger) = do
      Diagnostic
        { _range = srcRangeToLspRange range
        , _severity =
            case res of
              EvaluateLazy.Assertion False  -> Just LSP.DiagnosticSeverity_Error
              EvaluateLazy.Reduction (Left _) -> Just LSP.DiagnosticSeverity_Error
              _                             -> Just LSP.DiagnosticSeverity_Information
        , _code = Nothing
        , _codeDescription = Nothing
        , _source = Just "eval"
        , _message = EvaluateLazy.prettyEvalDirectiveResult r
        , _tags = Nothing
        , _relatedInformation = Nothing
        , _data_ = Nothing
        }

    checkErrorToDiagnostic :: CheckErrorWithContext -> Diagnostic
    checkErrorToDiagnostic checkError =
      Diagnostic
        { _range = srcRangeToLspRange (rangeOf checkError)
        , _severity = Just (translateSeverity (TypeCheck.severity checkError))
        , _code = Nothing
        , _codeDescription = Nothing
        , _source = Just "check"
        , _message = Text.unlines (TypeCheck.prettyCheckError checkError.kind)
        , _tags = Nothing
        , _relatedInformation = Nothing
        , _data_ = Nothing
        }

translateSeverity :: TypeCheck.Severity -> DiagnosticSeverity
translateSeverity TypeCheck.SInfo  = LSP.DiagnosticSeverity_Information
translateSeverity TypeCheck.SWarn  = LSP.DiagnosticSeverity_Warning
translateSeverity TypeCheck.SError = LSP.DiagnosticSeverity_Error

srcRangeToLspRange :: Maybe SrcRange -> LSP.Range
srcRangeToLspRange Nothing = LSP.Range (LSP.Position 0 0) (LSP.Position 0 0)
srcRangeToLspRange (Just range) = LSP.Range (srcPosToLspPosition range.start) (srcPosToLspPosition range.end)

pointRange :: Position -> Range
pointRange pos = Range pos pos

srcSpanToLspRange :: Maybe SrcSpan -> LSP.Range
srcSpanToLspRange Nothing = LSP.Range (LSP.Position 0 0) (LSP.Position 0 0)
srcSpanToLspRange (Just range) = LSP.Range (srcPosToLspPosition range.start) (srcPosToLspPosition range.end)

srcPosToLspPosition :: SrcPos -> LSP.Position
srcPosToLspPosition s =
  LSP.Position
    { _character = fromIntegral $ s.column - 1
    , _line = fromIntegral $ s.line - 1
    }

lspPositionToSrcPos :: LSP.Position -> SrcPos
lspPositionToSrcPos (LSP.Position { _character = c, _line = l }) =
  MkSrcPos (fromIntegral $ l + 1) (fromIntegral $ c + 1)

prettyNlgResolveWarning :: Resolve.Warning -> Text
prettyNlgResolveWarning = \ case
  Resolve.NotAttached _ ->
    "Not attached to any valid syntax node."
  Resolve.UnknownLocation nlg -> Text.unlines
    [ "The following NLG Annotation has no source location. This might be an internal compiler error."
    , "```"
    , Print.prettyLayout nlg
    , "```"
    ]
  Resolve.Ambiguous name nlgs -> Text.unlines $
    [ "More than one NLG annotation attached to: " <> Print.prettyLayout name
    , "The following annotations would be attached:"
    , ""
    ] <> [ "* `" <> Print.prettyLayout n.payload <> "`" | n <- nlgs]
  Resolve.RefUnattached r ->
    "@ref `" <> getRef r.payload <> "` could not be attached to any following syntax node."
  Resolve.RefNoLocation ref ->
    "@ref `" <> getRef ref <> "` has no source location. This might be an internal compiler error."
  Resolve.FixityAnnotationMisplaced _ ->
    "This fixity annotation is not on the line directly above a binary operator definition, so it is ignored. Put @infixl / @infixr / @infix immediately above the operator's definition."
  Resolve.FixityAnnotationNoLocation _ ->
    "A fixity annotation has no source location. This might be an internal compiler error."

listL4Files :: FilePath -> IO [NormalizedUri]
listL4Files dir = do
  files <- filterM doesFileExist . map (dir </>) =<< listDirectory dir
  pure $ toNormalizedUri . filePathToUri <$> filter ((== ".l4") . takeExtension) files


rangeOfResolveWarning :: Resolve.Warning -> LSP.Range
rangeOfResolveWarning = \ case
  Resolve.NotAttached nlg ->
    srcSpanToLspRange $ Just nlg.range
  Resolve.UnknownLocation _ ->
    srcSpanToLspRange Nothing
  Resolve.Ambiguous name _ ->
    srcRangeToLspRange $ rangeOf name
  Resolve.RefUnattached r ->
    srcSpanToLspRange $ Just r.range
  Resolve.RefNoLocation _ ->
    srcSpanToLspRange Nothing
  Resolve.FixityAnnotationMisplaced fx ->
    srcSpanToLspRange $ Just fx.range
  Resolve.FixityAnnotationNoLocation _ ->
    srcSpanToLspRange Nothing

-- ----------------------------------------------------------------------------
-- Helpers for implementing syntax highlighting
-- ----------------------------------------------------------------------------

-- | Similar to 'useWithStale', but instead of returning a 'zeroMapping' for 'PositionMapping'
-- when the rule is up-to-date, we return 'Nothing', to indicate that this rule is not stale.
--
-- We use this to implement short-circuting in semantic token generation.
useWithOptionalStale :: IdeRule k v => k -> NormalizedUri ->  Action (Maybe (v, Maybe PositionMapping))
useWithOptionalStale f nuri = do
  r <- use f nuri
  case r of
    Nothing -> do
      toks <- useWithStale f nuri
      pure $ fmap (fmap Just) toks
    Just toks ->
      pure $ Just (toks, Nothing)

applyPositionMapping :: [SemanticToken] -> PositionMapping -> [SemanticToken]
applyPositionMapping semTokens positionMapping =
  Maybe.mapMaybe
    ( \t ->
        case toCurrentPosition positionMapping t.start of
          Nothing -> Nothing
          Just newPos -> Just (t & #start .~ newPos)
    )
    semTokens

-- | @'semanticTokensUsing' phases@
--
-- Helper function for defining multi-phase semantic syntax highlighting.
--
-- Each phase can produce '[SemanticToken]'s and 'PositionMapping' if the result is outdated.
-- Tokens obtained from earlier phases take precedence over tokens from later phases.
--
-- If one of the phases is up-to-date, i.e. 'Maybe PositionMapping' is 'Nothing',
-- then we don't run later phases.
semanticTokensUsing ::
  [NormalizedUri -> Action (Maybe ([SemanticToken], Maybe PositionMapping))] ->
  (NormalizedUri -> Action [SemanticToken])
semanticTokensUsing phases uri = do
  (_, tokens) <- foldM go (False, []) phases
  pure tokens
 where
  -- Just like a fold, but with short circuiting behaviour.
  go (True, earlierTokens) _phase = pure (True, earlierTokens)
  go (False, earlierTokens) phase = do
    tokens <- phase uri
    case tokens of
      Nothing -> do
        pure (False, earlierTokens)
      Just (toks, mpm) -> case mpm of
        Nothing -> pure (True, mergeSameLengthTokens earlierTokens toks)
        Just pm -> pure (False, mergeSameLengthTokens earlierTokens (applyPositionMapping toks pm))

  -- We assume that semantic tokens do *not* change its length, no matter whether they
  -- have been lexed, parsed or typechecked.
  -- A rather bold assumption, tbh. It will almost definitely not hold
  -- up in practice, but let's do one step at a time.
  mergeSameLengthTokens :: [SemanticToken] -> [SemanticToken] -> [SemanticToken]
  mergeSameLengthTokens [] bs = bs
  mergeSameLengthTokens as [] = as
  mergeSameLengthTokens (a : as) (b : bs) = case compare a.start b.start of
    -- a.start == b.start
    -- Same token, only print one
    EQ -> a : mergeSameLengthTokens as bs
    -- a.start < b.start
    LT -> a : mergeSameLengthTokens as (b : bs)
    -- a.start > b.start
    GT -> b : mergeSameLengthTokens (a : as) bs
