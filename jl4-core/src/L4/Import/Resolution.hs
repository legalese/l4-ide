{-# LANGUAGE OverloadedStrings #-}
-- | Shared import resolution logic for L4.
--
-- This module provides the core import resolution algorithm that can be used
-- by both the LSP (with Shake) and WASM (pure) backends. The resolution logic
-- is parameterized over a monad and an 'ImportLookup', allowing different
-- backends to provide their own implementations.
--
-- == Architecture
--
-- @
--                     L4.Import.Resolution
--                     (this module - pure logic)
--                              │
--              ┌───────────────┴───────────────┐
--              │                               │
--         LSP Backend                    WASM Backend
--    (Shake + filesystem)            (VFS + embedded libs)
-- @
--
-- The LSP backend resolves a path import itself, over the Shake rules, and uses
-- from this module the pure helpers ('classifyImport', 'pathImportFile',
-- 'collapsePath') and the one text of its refusals ('pathResolutionMessage').
-- The pure backend resolves both kinds of name with 'resolveImports'.
--
-- == Usage
--
-- Backends implement 'ImportLookup' to specify how to find module sources:
--
-- @
-- -- Pure implementation with VFS
-- pureResolver :: VFS -> ImportLookup Identity
-- pureResolver vfs = ImportLookup
--   { ilBare = \\name -> Identity (fmap (\\src -> BareHit src (Just ".")) (vfsLookup name vfs))
--   , ilPath = \\path -> Identity (vfsLookupPath path vfs)
--   }
-- @
--
-- @since 0.1
module L4.Import.Resolution
  ( -- * Module Lookup
    ImportLookup(..)
  , BareHit(..)
  , Importer(..)
    -- * URI Generation
  , moduleNameToProjectUri
  , pathModuleUri
  , moduleNameToCandidateUris
  , CandidateUri(..)
    -- * Written import names: bare or path
  , ImportForm(..)
  , classifyImport
  , pathImportFile
  , CollapsedPath(..)
  , collapsePath
    -- * Why a path import was refused
  , PathResolution(..)
  , pathResolutionMessage
    -- * Import Extraction
  , extractImportNames
    -- * Resolution
  , resolveImports
  , ResolvedImport(..)
  , ImportResolutionError(..)
  , renderImportError
  , dependenciesFirst
    -- * Type Checking with Dependencies
  , typecheckWithDependencies
  , TypeCheckWithDepsResult(..)
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import System.FilePath (isAbsolute, joinPath, splitDirectories, takeDirectory, (</>))

import L4.API.EmbeddedLibraries (lookupEmbeddedLibrary)
import L4.Lexer (PError(..))
import L4.Syntax
import L4.Parser (execProgramParserWithHintPass)
import L4.TypeCheck (doCheckProgramWithDependencies, initialCheckState, initialCheckEnv, applyFinalSubstitution)
import L4.TypeCheck.Types (CheckResult(..), CheckErrorWithContext, Substitution, Environment, EntityInfo, MixfixRegistry, InfoMap, ScopeMap, NlgMap, DescMap, SectionPaths)
import qualified L4.TypeCheck as TypeCheck
import qualified Data.List as List
import qualified L4.Utils.IntervalMap as IV

-- ----------------------------------------------------------------------------
-- Module Lookup Abstraction
-- ----------------------------------------------------------------------------

-- | How a backend finds the source of a module that an @IMPORT@ names.
--
-- A bare name and a path are two questions, because they have two answers: a bare
-- name may be an embedded library, and a path never is.
data ImportLookup m = ImportLookup
  { ilBare :: Text -> m (Maybe BareHit)
    -- ^ By module name, without the @.l4@ (@"prelude"@, @"helper"@).
  , ilPath :: FilePath -> m (Maybe Text)
    -- ^ By path among the supplied files, already collapsed and with its @.l4@
    -- (@"rows\/b\/mod.l4"@). Never asked for a path that leaves the files, or for
    -- one that came from a leading @\/@.
  }

-- | A module found by name, and where it lives.
data BareHit = BareHit
  { bhSource :: Text
  , bhDirectory :: Maybe FilePath
    -- ^ The folder of the module among the supplied files, which its own path
    -- imports start from. 'Nothing' for a module that is not one of them, such as
    -- an embedded library: it has no folder, and cannot import by path.
  }
  deriving stock (Eq, Show)

-- | The module that writes a list of @IMPORT@s, as far as resolving them goes.
data Importer = Importer
  { impLabel :: Text
    -- ^ How a message names it: its path among the supplied files, or its URI when
    -- it has none.
  , impDirectory :: Maybe FilePath
    -- ^ Its folder among the supplied files, which a path import starts from.
    -- 'Nothing' if it has none.
  }
  deriving stock (Eq, Show)

-- ----------------------------------------------------------------------------
-- URI Generation
-- ----------------------------------------------------------------------------

-- | A candidate URI for module resolution, with its source.
data CandidateUri = CandidateUri
  { cuUri :: NormalizedUri
  , cuSource :: Text  -- ^ Description of where this URI comes from (for error messages)
  }
  deriving stock (Eq, Show)

-- | Convert a module name to a @project:/@ URI.
--
-- This is the canonical URI scheme for VFS files:
-- @
-- moduleNameToProjectUri "helper" == "project:/helper.l4"
-- @
moduleNameToProjectUri :: Text -> NormalizedUri
moduleNameToProjectUri modName =
  toNormalizedUri $ Uri $ "project:/" <> modName <> ".l4"

-- | The @project:/@ URI of the file a collapsed path names.
--
-- A file at the top of the files gets the URI the module of its name gets
-- ('moduleNameToProjectUri'), so ``IMPORT `sub/../core` `` and @IMPORT core@ are
-- one module. A file in a folder has a URI no module name can have.
--
-- @
-- pathModuleUri "core.l4"          == "project:/core.l4"
-- pathModuleUri "rows/b/mod.l4"    == "project:/rows/b/mod.l4"
-- @
pathModuleUri :: FilePath -> NormalizedUri
pathModuleUri collapsed =
  toNormalizedUri $ Uri $ "project:/" <> Text.pack (dropWhile (== '/') collapsed)

-- | Generate candidate URIs for a module name.
--
-- Returns URIs in priority order:
-- 1. @project:/modName.l4@ - VFS lookup
-- 2. Relative to importing file (if base URI provided)
-- 3. Relative to root directory (if root provided)
moduleNameToCandidateUris
  :: Maybe NormalizedUri  -- ^ URI of the importing file (for relative resolution)
  -> Maybe FilePath       -- ^ Root directory (for absolute resolution)
  -> Text                 -- ^ Module name
  -> [CandidateUri]
moduleNameToCandidateUris mBaseUri mRoot modName =
  [ CandidateUri (moduleNameToProjectUri modName) "project VFS"
  ] 
  <> maybe [] relativeCandidate mBaseUri
  <> maybe [] rootCandidate mRoot
  where
    relativeCandidate _baseUri =
      -- TODO: compute relative URI from base
      []
    rootCandidate _root =
      -- TODO: compute file:// URI from root
      []

-- ----------------------------------------------------------------------------
-- Written import names: bare or path
-- ----------------------------------------------------------------------------

-- | How the text of a written @IMPORT@ name is resolved
-- (specs\/proposals\/RELATIVE-IMPORTS-SPEC.md §4.2).
--
-- The class is decided by the text alone, and only by whether it contains a
-- @\/@: a name without one is resolved by the bare-name ladder, exactly as it
-- was before path imports existed.
data ImportForm
  = BareImport
    -- ^ No @\/@: @IMPORT prelude@, @IMPORT \`sg-succession-domain\`@, and also
    -- @IMPORT foo.l4@ and @IMPORT a.b@, which the bare-name ladder reduces to
    -- @foo@ and @a@.
  | PathImport
    -- ^ A relative path with at least one @\/@: @IMPORT \`..\/other-row\/mod\`@.
  | RootedImport
    -- ^ A path with a leading @\/@. Reserved for a root-relative form that is
    -- not specified yet, and refused until it is.
  deriving stock (Eq, Show)

-- | Classify the text of a written import name. A backslash is not a path
-- separator on any platform: it is an ordinary character of a name.
classifyImport :: Text -> ImportForm
classifyImport t
  | not (Text.isInfixOf "/" t) = BareImport
  | Text.isPrefixOf "/" t      = RootedImport
  | otherwise                  = PathImport

-- | The file a path import names, relative to the importing file's directory:
-- one trailing @.l4@ is dropped if present and @.l4@ appended, so
-- @..\/b\/mod@ and @..\/b\/mod.l4@ name the same file.
pathImportFile :: Text -> FilePath
pathImportFile t =
  joinPath (filter (not . null) (map Text.unpack (Text.splitOn "/" bare)))
    <> ".l4"
  where
    bare = fromMaybe t (Text.stripSuffix ".l4" t)

-- | A path with its @.@ and @x\/..@ segments removed by a lexical walk that
-- never consults the filesystem.
data CollapsedPath = CollapsedPath
  { cpPath    :: FilePath
  , cpEscaped :: Bool
    -- ^ The walk stepped above the start of a relative path (so @cpPath@ begins
    -- with @..@), or above the root of an absolute one. A runtime that serves
    -- somebody else's files refuses such a path before it reads anything.
  }
  deriving stock (Eq, Show)

-- | Collapse @.@ and @..@ segments lexically.
--
-- 'System.FilePath.normalise' alone is not enough: it removes @.@ segments and
-- leaves @sub\/..\/core.l4@ as it is (RELATIVE-IMPORTS-SPEC §0 #11), so the
-- same file reached by two spellings would be two modules.
collapsePath :: FilePath -> CollapsedPath
collapsePath fp =
  CollapsedPath
    { cpPath = case joinPath (rootSegment <> reverse kept) of
        "" -> "."
        p  -> p
    , cpEscaped = escaped
    }
  where
    (rootSegment, segments) = case splitDirectories fp of
      (r : rest) | isAbsolute r -> ([r], rest)
      ss                        -> ([], ss)

    (kept, escaped) = foldl' step ([], False) segments

    step (ks, esc) = \ case
      "."  -> (ks, esc)
      ".." -> case ks of
        (k : ks') | k /= ".." -> (ks', esc)
        _ | null rootSegment  -> (".." : ks, True)
          | otherwise         -> (ks, True)
      seg  -> (seg : ks, esc)

-- | What resolving one path import came to.
--
-- The backends differ in how they look for the file and agree on what can go
-- wrong, so this is the one type for it, and 'pathResolutionMessage' the one
-- text.
data PathResolution
  = PathFound !NormalizedUri
  | PathNotFound !FilePath !FilePath
    -- ^ the importing file, and the collapsed path that was looked for
  | PathEscapesRoot !FilePath !FilePath
    -- ^ the importing file, and the collapsed path, which leaves the root of a
    -- confined runtime
  | PathNoImportingDirectory
    -- ^ the importer is not a file with a directory: an embedded library, or a
    -- browser document
  | PathRootRefused
    -- ^ a leading @\/@, which is reserved
  deriving stock (Eq, Show)

-- | The diagnostic text for a path import that did not resolve, or 'Nothing' for
-- one that did. The first line of each is stable text a test can match
-- (RELATIVE-IMPORTS-SPEC §4.5).
--
-- The runtimes that resolve a path import (the Shake rules for the CLI, the
-- language server and the service; 'resolveImports' for the browser build) all
-- say it with this function, so a person gets the same words wherever the file
-- is checked. The first argument is how the importing file is named in the one
-- message that names it: its URI, or its path among the supplied files.
pathResolutionMessage :: Text -> Text -> PathResolution -> Maybe Text
pathResolutionMessage importerUri written = \ case
  PathFound _ -> Nothing
  PathNotFound importer collapsed -> Just $ Text.unlines
    [ "I could not find a module at this path: " <> written
    , "Nothing it defines is in scope here; names you expected from it are reported as undefined."
    , "Relative to " <> Text.pack importer <> " that is " <> Text.pack collapsed <> ", which does not exist."
    ]
  PathEscapesRoot importer collapsed -> Just $ Text.unlines
    [ "This import leaves the root of this deployment: " <> written
    , "Relative to " <> Text.pack importer <> " that would be " <> Text.pack collapsed
        <> ", which is outside the root of this deployment."
    , "A relative import may reach any file inside the deployment and nothing outside it."
    ]
  PathNoImportingDirectory -> Just $ Text.unlines
    [ "This import is relative, but " <> importerUri <> " has no directory to be relative to."
    , "Write a bare module name, or open the file from disk so that it has a folder to start from."
    ]
  PathRootRefused -> Just $ Text.unlines
    [ "This import leaves the root of this deployment: " <> written
    , "A path import is written relative to the file that imports it. A leading / is reserved for a root-relative form that does not exist yet."
    ]

-- ----------------------------------------------------------------------------
-- Import Extraction
-- ----------------------------------------------------------------------------

-- | Extract import names from a parsed module.
--
-- Returns module names without the .l4 extension.
extractImportNames :: Module Name -> [Text]
extractImportNames = foldTopDecls extractImport
  where
    extractImport :: TopDecl Name -> [Text]
    extractImport = \case
      Import _ (MkImport _ n _) -> [rawNameToText (rawName n)]
      _ -> []

-- ----------------------------------------------------------------------------
-- Import Resolution
-- ----------------------------------------------------------------------------

-- | Errors that can occur during import resolution.
data ImportResolutionError
  = ModuleNotFound Text [Text]  -- ^ Module name, list of places searched
  | ParseError Text [Text]      -- ^ Module name, parse error messages
  | CyclicImport [Text]         -- ^ Cycle of module names
  | PathImportFailed Text Text PathResolution
    -- ^ A path import that could not be resolved: the name as written, the
    -- importing file as a message names it, and why
  | ConflictingModules Text
    -- ^ Two different sources have one module address (a module name, or the
    -- path of a file at the top of the files)
  deriving stock (Eq, Show, Generic)

-- | The messages for a failed resolution, as 'typecheckWithDependencies' returns
-- them.
renderImportError :: ImportResolutionError -> [Text]
renderImportError = \ case
  ModuleNotFound modName searched ->
    ["Module not found: " <> modName <> " (searched: " <> Text.intercalate ", " searched <> ")"]
  ParseError modName errs ->
    ("Parse error in " <> modName <> ":") : errs
  CyclicImport cycleModules ->
    ["Cyclic import detected: " <> Text.intercalate " -> " cycleModules]
  PathImportFailed written importer why ->
    [Text.stripEnd (fromMaybe "" (pathResolutionMessage importer written why))]
  ConflictingModules name | Just _ <- lookupEmbeddedLibrary name ->
    [ "Two different modules are both called " <> name <> ", so one would stand in for the other. "
        <> "A file at the top of the files that has the name of a standard library module "
        <> "cannot be imported by path in a program that also uses the library module. "
        <> "Put the file in a folder, or give it another name."
    ]
  ConflictingModules name ->
    [ "Two different modules are both called " <> name <> ", so one would stand in for the other. "
        <> "Two of the files you supplied have the address " <> name <> ".l4 and different contents. "
        <> "Key each file once, under one spelling of its path."
    ]

-- | A module found for an @IMPORT@: what it is, and where its own imports start.
data Located = Located
  { locKey :: Text
    -- ^ Its identity: the text of its URI. One module is one key, however it was
    -- reached, and no two modules share one.
  , locUri :: NormalizedUri
  , locName :: Text
    -- ^ What a message calls it: the module name, or its path without the @.l4@.
  , locSource :: Text
  , locImporter :: Importer
  }

-- | Find the module an @IMPORT@ names, as written in a module that is 'Importer'.
--
-- A bare name asks the lookup by name, exactly as it always did. A path import
-- never asks by name: it is joined to the importer's folder, collapsed, refused
-- if it leaves the supplied files or has no folder to start from, and only then
-- looked up, by its collapsed path (RELATIVE-IMPORTS-SPEC §4.3).
locate
  :: forall m. Monad m
  => ImportLookup m -> Importer -> Text -> m (Either ImportResolutionError Located)
locate lookups importer written = case classifyImport written of
  BareImport -> do
    found <- lookups.ilBare written
    pure $ case found of
      Nothing -> Left (ModuleNotFound written ["embedded libraries", "project VFS"])
      Just hit ->
        let uri = moduleNameToProjectUri written
         in Right Located
              { locKey = uriKey uri
              , locUri = uri
              , locName = written
              , locSource = hit.bhSource
              , locImporter = Importer
                  { impLabel = case hit.bhDirectory of
                      Just _  -> written <> ".l4"
                      Nothing -> (fromNormalizedUri uri).getUri
                  , impDirectory = hit.bhDirectory
                  }
              }
  RootedImport -> pure (refuse PathRootRefused)
  PathImport -> case importer.impDirectory of
    Nothing -> pure (refuse PathNoImportingDirectory)
    Just dir ->
      let target = collapsePath (dir </> pathImportFile written)
       in if target.cpEscaped
            then pure (refuse (PathEscapesRoot (Text.unpack importer.impLabel) target.cpPath))
            else do
              found <- lookups.ilPath target.cpPath
              pure $ case found of
                Nothing -> refuse (PathNotFound (Text.unpack importer.impLabel) target.cpPath)
                Just source ->
                  let uri = pathModuleUri target.cpPath
                   in Right Located
                        { locKey = uriKey uri
                        , locUri = uri
                        , locName = Text.pack (dropL4 target.cpPath)
                        , locSource = source
                        , locImporter = Importer
                            { impLabel = Text.pack target.cpPath
                            , impDirectory = Just (takeDirectory target.cpPath)
                            }
                        }
  where
    refuse :: PathResolution -> Either ImportResolutionError a
    refuse = Left . PathImportFailed written importer.impLabel

-- | The URI an @IMPORT@ resolves to, from the folder of the module that writes
-- it. This is what 'resolveImports' found the module under, worked out again so
-- that each @IMPORT@ of a module can be stamped with it.
importTargetUri :: Maybe FilePath -> Text -> Maybe NormalizedUri
importTargetUri dir written = case classifyImport written of
  BareImport   -> Just (moduleNameToProjectUri written)
  RootedImport -> Nothing
  PathImport   -> do
    d <- dir
    let target = collapsePath (d </> pathImportFile written)
    guard (not target.cpEscaped)
    pure (pathModuleUri target.cpPath)

uriKey :: NormalizedUri -> Text
uriKey = (.getUri) . fromNormalizedUri

-- | What a message calls the document: its path among the supplied files, without
-- the @.l4@, as it calls a module reached by path.
documentName :: Importer -> Text
documentName importer = fromMaybe importer.impLabel (Text.stripSuffix ".l4" importer.impLabel)

dropL4 :: FilePath -> FilePath
dropL4 p = maybe p reverse (List.stripPrefix (reverse ".l4") (reverse p))

-- | A successfully resolved import.
data ResolvedImport = ResolvedImport
  { riModuleName :: Text
    -- ^ The module name for a bare import, and for a path import the collapsed
    -- path without its @.l4@ (@"rows\/b\/mod"@).
  , riUri :: NormalizedUri
  , riSource :: Text
  , riParsed :: Module Name
  , riTypeChecked :: CheckResult
  }
  deriving stock (Generic)

-- | Resolve all imports for a module, recursively.
--
-- This function:
-- 1. Finds each import with the provided lookup ('locate'): by name for a bare
--    import, by collapsed path for a path import
-- 2. Recursively resolves transitive imports, each from its own module's folder
-- 3. Type-checks imports in dependency order
-- 4. Returns all resolved imports (including transitive)
--
-- Modules are known by their URI: a bare name and a path that name the same
-- file are one module, and so are two spellings of one path.
--
-- Cycle detection prevents infinite loops. We track two collections:
-- - @inProgress@: modules currently being resolved (detecting these = cycle)
-- - @resolved@: modules already fully resolved, keyed to their resolved records
--
-- The @resolved@ map holds the actual 'ResolvedImport' records (not just names)
-- so that when a module is re-encountered we can hand back its already-computed,
-- fully-type-checked record. This matters for /diamond/ imports: in
-- @A -> {B, C} -> D@, once B has resolved D, C must still receive D's exported
-- environment. Returning @[]@ here (the old, name-set behaviour) type-checked C
-- against an empty dependency environment, silently degrading the types and
-- entities of the second sibling that A then consumes. See smucclaw/l4-ide#904.
--
-- The document being checked is the module at its own address. An @IMPORT@ that
-- reaches that address is the document, so it is a cycle, and the lookup is not
-- asked for it: a file it holds there is a copy, and the live text is what is
-- being checked.
resolveImports
  :: forall m. Monad m
  => ImportLookup m                      -- ^ How to find module sources
  -> Importer                            -- ^ The module that writes these imports
  -> Maybe (Text, Text)                  -- ^ The document being checked: the key of its address, and what a message calls it
  -> Map.Map Text Text                   -- ^ Modules currently being resolved, key to name (for cycle detection)
  -> Map.Map Text ResolvedImport         -- ^ Modules already fully resolved, keyed to their records
  -> [Text]                              -- ^ Import names to resolve
  -> m (Either ImportResolutionError [ResolvedImport])
resolveImports _lookups _importer _document _inProgress _resolved [] = pure $ Right []
resolveImports _lookups importer (Just (ownKey, ownName)) inProgress _resolved (written : _rest)
  | (uriKey <$> importTargetUri importer.impDirectory written) == Just ownKey =
      -- The cycle is the modules being resolved and the document they all hang
      -- from; a cycle that does not come back to the document does not name it
      pure $ Left $ CyclicImport $ Set.toList (Set.fromList (ownName : Map.elems inProgress)) <> [ownName]
resolveImports lookups importer document inProgress resolved (written : rest) = do
  located <- locate lookups importer written
  case located of
    Left err -> pure $ Left err
    Right loc
      -- Already resolved - reuse its record so *siblings* inherit its environment
      | Just cached <- Map.lookup loc.locKey resolved ->
          if cached.riSource == loc.locSource
            then (fmap . fmap) (cached :) $ resolveImports lookups importer document inProgress resolved rest
            else pure $ Left $ ConflictingModules loc.locName
      -- Currently being resolved - cycle detected!
      | loc.locKey `Map.member` inProgress ->
          pure $ Left $ CyclicImport $ Set.toList (Set.fromList (Map.elems inProgress)) <> [loc.locName]
      | otherwise -> do
          let uri = loc.locUri

          -- Parse the module
          case execProgramParserWithHintPass uri loc.locSource of
            Left parseErrors ->
              pure $ Left $ ParseError loc.locName $ map (\(PError msg _ _ _) -> msg) (toList parseErrors)

            Right (parsed, _hints, _warnings) -> do
              -- Extract and resolve transitive imports first
              -- Add this module to inProgress while resolving its imports
              let transitiveImports = extractImportNames parsed
                  newInProgress = Map.insert loc.locKey loc.locName inProgress

              transitiveResult <- resolveImports lookups loc.locImporter document newInProgress resolved transitiveImports

              case transitiveResult of
                Left err -> pure $ Left err
                Right transitiveResolved -> do
                  -- Type-check this module with its dependencies
                  let (depState, depEnv) = combineResolvedImports uri transitiveResolved
                      updatedParsed = stampImports loc.locImporter.impDirectory parsed
                      tcResult = doCheckProgramWithDependencies depState depEnv updatedParsed

                  let thisResolved = ResolvedImport
                        { riModuleName = loc.locName
                        , riUri = uri
                        , riSource = loc.locSource
                        , riParsed = parsed
                        , riTypeChecked = tcResult
                        }

                  -- This module is now fully resolved.
                  -- Register this module and everything its subtree resolved,
                  -- keyed to their records, so that later siblings inherit the
                  -- records (not just the names) via the already-resolved branch.
                  let transitiveCache = Map.fromList [ (uriKey ri.riUri, ri) | ri <- transitiveResolved ]
                      newResolved = Map.insert loc.locKey thisResolved (Map.union resolved transitiveCache)

                  -- Continue with remaining imports (back to original inProgress)
                  restResult <- resolveImports lookups importer document inProgress newResolved rest

                  case restResult of
                    Left err -> pure $ Left err
                    Right restResolved ->
                      -- Return this module + transitive + rest
                      -- Deduplicate by module (keep first occurrence)
                      let allResolved = thisResolved : transitiveResolved <> restResolved
                          seen = Set.empty :: Set.Set Text
                          deduped = deduplicateResolved seen allResolved
                      in pure $ Right deduped
  where
    deduplicateResolved :: Set.Set Text -> [ResolvedImport] -> [ResolvedImport]
    deduplicateResolved _ [] = []
    deduplicateResolved seen (ri : ris)
      | uriKey ri.riUri `Set.member` seen = deduplicateResolved seen ris
      | otherwise = ri : deduplicateResolved (Set.insert (uriKey ri.riUri) seen) ris

-- | The resolved imports in an order in which every module comes after the modules
-- it imports, so that a caller that evaluates them one by one can give each the
-- environment of its own imports.
--
-- 'resolveImports' lists a module before what it imports, and lists a module
-- reached twice where it was first reached, so its order is neither this one nor
-- its reverse: in @A -> {B, C} -> D@ it is @B, D, C@, with @C@ before the @D@ it
-- needs once reversed.
dependenciesFirst :: [ResolvedImport] -> [ResolvedImport]
dependenciesFirst imports = reverse (snd (List.foldl' visit (Set.empty, []) imports))
  where
    byKey :: Map.Map Text ResolvedImport
    byKey = Map.fromList [ (uriKey ri.riUri, ri) | ri <- imports ]

    visit :: (Set.Set Text, [ResolvedImport]) -> ResolvedImport -> (Set.Set Text, [ResolvedImport])
    visit (seen, done) ri
      | key `Set.member` seen = (seen, done)
      | otherwise =
          let (seen', done') = List.foldl' visit (Set.insert key seen, done) (importedBy ri)
           in (seen', ri : done')
      where
        key = uriKey ri.riUri

    -- The modules among 'imports' that this one imports, by the URI each of its
    -- @IMPORT@s was stamped with.
    importedBy :: ResolvedImport -> [ResolvedImport]
    importedBy ri =
      mapMaybe (\u -> Map.lookup (uriKey u) byKey)
        (foldTopDecls importUri ri.riTypeChecked.program)

    importUri :: TopDecl Resolved -> [NormalizedUri]
    importUri = \ case
      Import _ (MkImport _ _ (Just u)) -> [u]
      _ -> []

-- ----------------------------------------------------------------------------
-- Type Checking with Dependencies
-- ----------------------------------------------------------------------------

-- | Result of type-checking with resolved dependencies.
data TypeCheckWithDepsResult = TypeCheckWithDepsResult
  { tcdModule :: Module Resolved
  , tcdErrors :: [CheckErrorWithContext]
  , tcdSubstitution :: Substitution
  , tcdEnvironment :: Environment
  , tcdEntityInfo :: EntityInfo
  , tcdMixfixRegistry :: MixfixRegistry
  , tcdInfoMap :: InfoMap
  , tcdScopeMap :: ScopeMap
  , tcdNlgMap :: NlgMap
  , tcdDescMap :: DescMap
  , tcdSuccess :: Bool
  , tcdResolvedImports :: [ResolvedImport]
  , tcdUri :: NormalizedUri  -- ^ URI of the main module
  , tcdSectionPaths :: SectionPaths
    -- ^ Where each visible binding was defined, section-wise, including those
    -- reached through imports. See 'L4.TypeCheck.Types.SectionPaths'.
  , tcdImplicitReaders :: Set Unique
    -- ^ Definitions with a non-empty read-set, this module's and its imports'.
    -- See 'L4.TypeCheck.Types.CheckResult.implicitReaders'.
  }
  deriving stock (Generic)

-- | Type-check a module with its dependencies.
--
-- This is the main entry point for type-checking with import resolution.
typecheckWithDependencies
  :: forall m. Monad m
  => ImportLookup m     -- ^ How to find module sources
  -> Importer           -- ^ The main module, as the imports it writes are resolved from it
  -> NormalizedUri      -- ^ URI of the main module
  -> Text               -- ^ Source code of the main module
  -> m (Either [Text] TypeCheckWithDepsResult)
typecheckWithDependencies lookups importer uri source = do
  -- Parse the main module
  case execProgramParserWithHintPass uri source of
    Left parseErrors ->
      pure $ Left $ map (\(PError msg _ _ _) -> msg) (toList parseErrors)

    Right (parsed, _hints, _warnings) -> do
      -- Extract and resolve imports
      let importNames = extractImportNames parsed

      -- The document is the module at its own address while its imports are
      -- resolved: an import that reaches that address is the document, and a file
      -- the lookup holds there is never read in its place. That makes a file that
      -- imports the document back a cycle, as it is under the Shake rules.
      importResult <- resolveImports lookups importer (Just (uriKey uri, documentName importer)) Map.empty Map.empty importNames

      case importResult of
        Left err -> pure $ Left (renderImportError err)

        Right resolvedImports -> do
          -- Combine environments from imports
          let (initState, initEnv) = combineResolvedImports uri resolvedImports
              updatedParsed = stampImports importer.impDirectory parsed
              result = doCheckProgramWithDependencies initState initEnv updatedParsed

          pure $ Right TypeCheckWithDepsResult
            { tcdModule = result.program
            , tcdErrors = result.errors
            , tcdSubstitution = result.substitution
            , tcdEnvironment = result.environment
            -- Zonk so callers see resolved types (e.g. a return type of DATE,
            -- not the raw inference variable it was unified through). The Shake
            -- typecheck rule and per-import resolution already do this; doing it
            -- here keeps the public checkWithImports result consistent.
            , tcdEntityInfo = applyFinalSubstitution result.substitution uri result.entityInfo
            , tcdMixfixRegistry = result.mixfixRegistry
            , tcdInfoMap = result.infoMap
            , tcdScopeMap = result.scopeMap
            , tcdNlgMap = result.nlgMap
            , tcdDescMap = result.descMap
            -- Success is decided by severity, as the Shake typecheck rule
            -- decides it: only an SError blocks. Infos (#CHECK) and warnings
            -- (exhaustiveness, the ASSUME deprecation) leave the module
            -- successful. Keying this on "no diagnostics at all" made a
            -- warning-bearing module unsuccessful through this API alone.
            , tcdSuccess = not (any ((== TypeCheck.SError) . TypeCheck.severity) result.errors)
            , tcdResolvedImports = resolvedImports
            , tcdUri = uri
            , tcdSectionPaths = result.sectionPaths
            , tcdImplicitReaders = result.implicitReaders
            }

-- ----------------------------------------------------------------------------
-- Internal Helpers
-- ----------------------------------------------------------------------------

-- | Combine resolved imports into initial CheckState and CheckEnv.
combineResolvedImports :: NormalizedUri -> [ResolvedImport] -> (TypeCheck.CheckState, TypeCheck.CheckEnv)
combineResolvedImports uri imports =
  let
    baseState = initialCheckState
    baseEnv = initialCheckEnv uri
    
    (finalState, finalEnv) = List.foldl' combineOne (baseState, baseEnv) imports
  in
    -- Clear substitution to avoid leaking inference variables
    ( TypeCheck.MkCheckState
        { TypeCheck.substitution = Map.empty
        , TypeCheck.supply = finalState.supply
        , TypeCheck.infoMap = finalState.infoMap
        , TypeCheck.nlgMap = finalState.nlgMap
        , TypeCheck.scopeMap = finalState.scopeMap
        , TypeCheck.descMap = finalState.descMap
        , TypeCheck.constBodies = finalState.constBodies
        , TypeCheck.sectionPaths = finalState.sectionPaths
        , TypeCheck.deferredChoices = 0
        , TypeCheck.plural = False
        , TypeCheck.bindLog = []
        , TypeCheck.bindLogLen = 0
        }
    , finalEnv
    )
  where
    combineOne 
      :: (TypeCheck.CheckState, TypeCheck.CheckEnv) 
      -> ResolvedImport 
      -> (TypeCheck.CheckState, TypeCheck.CheckEnv)
    combineOne (accState, accEnv) ri =
      let r = ri.riTypeChecked
          -- IMPORTANT: Apply the substitution to entityInfo to resolve type variables
          -- BEFORE merging ('unionImportedCheckEnv' requires zonked input). Without
          -- this, types like 'r25' would leak instead of being resolved to their
          -- actual types (e.g., NUMBER). This matches what the native LSP does in
          -- LSP.L4.Rules when combining TypeCheckResult dependencies (there the
          -- entityInfo is already zonked when stored into the TypeCheckResult).
          resolvedEntityInfo = applyFinalSubstitution r.substitution ri.riUri r.entityInfo
      in ( TypeCheck.MkCheckState
             { TypeCheck.substitution = r.substitution
             , TypeCheck.supply = accState.supply
             , TypeCheck.infoMap = IV.empty
             , TypeCheck.nlgMap = IV.empty
             , TypeCheck.scopeMap = IV.empty
             , TypeCheck.descMap = IV.empty
             , TypeCheck.constBodies = accState.constBodies
               -- Carry the dependency's section paths across the boundary, so
               -- that an imported name can be named under the section that
               -- defines it. 'Unique' embeds its module, so the two maps have
               -- disjoint keys and the union is order-independent. This does
               -- NOT reopen cross-module overload resolution: both proximity
               -- readers check the module URI before consulting the map, so an
               -- imported 'Unique' is still never ranked (spec §5.5, FIX C).
             , TypeCheck.sectionPaths = Map.union accState.sectionPaths r.sectionPaths
             , TypeCheck.deferredChoices = 0
             , TypeCheck.plural = False
             , TypeCheck.bindLog = []
             , TypeCheck.bindLogLen = 0
             }
         , TypeCheck.unionImportedCheckEnv accEnv r.environment resolvedEntityInfo r.mixfixRegistry r.implicitReaders
         )

-- | Give each import declaration of a module the URI its import resolved to.
--
-- Each @IMPORT@ is looked at on its own, with the folder of the module that writes
-- it, because the same written path names a different file in a different
-- folder: matching the written name against the modules that were resolved, as
-- this once did, cannot tell them apart.
stampImports :: Maybe FilePath -> Module Name -> Module Name
stampImports dir = overImports stamp
  where
    stamp :: Import Name -> Import Name
    stamp i@(MkImport ann n _) =
      case importTargetUri dir (rawNameToText (rawName n)) of
        Just u  -> MkImport ann n (Just u)
        Nothing -> i
