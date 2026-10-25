{-# LANGUAGE OverloadedStrings #-}
-- | Virtual File System and import resolution for the L4 API.
--
-- This module provides import resolution using:
--
-- * Embedded core libraries (bundled at compile time from @libraries/*.l4@)
-- * VFS (Virtual File System) provided by the caller
--
-- A bare name (@IMPORT helper@) is resolved embedded libraries first, then the
-- VFS, by name. A path import (@IMPORT \`..\/b\/mod\`@) is resolved among the VFS's
-- files only, from the folder of the importing document, and never finds an
-- embedded library (specs\/proposals\/RELATIVE-IMPORTS-SPEC.md, §6 "wasm").
--
-- == Usage
--
-- @
-- -- Provide files via VFS
-- let vfs = vfsFromList [("helper", helperSource), ("rows/b/mod.l4", modSource)]
-- result <- checkWithImports vfs mainSource
-- -- ...or say where the document is, so its path imports start from its folder
-- result' <- checkWithImportsAt vfs "rows/a/main.l4" mainSource
-- @
--
-- @since 0.1
module L4.API.VirtualFS
  ( -- * Virtual File System
    VFS
  , emptyVFS
  , vfsLookup
  , vfsLookupPath
  , vfsKeyPath
  , vfsInsert
  , vfsFromList
  , vfsKeys
    -- * Embedded Libraries (re-exported)
  , embeddedLibraries
  , embeddedLibraryNames
  , lookupEmbeddedLibrary
    -- * Type Checking with Imports
  , checkWithImports
  , checkWithImportsAt
  , checkWithImportsAndUri
    -- * Re-exports from shared resolution
  , TypeCheckWithDepsResult(..)
  , ResolvedImport(..)
  , extractImportNames
  , moduleNameToProjectUri
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Map.Strict as Map
import Control.Applicative ((<|>))
import System.FilePath (takeDirectory)

-- Re-export embedded libraries
import L4.API.EmbeddedLibraries (embeddedLibraries, embeddedLibraryNames, lookupEmbeddedLibrary)

-- Use shared resolution logic
import L4.Import.Resolution
  ( BareHit(..)
  , CollapsedPath(..)
  , ImportLookup(..)
  , Importer(..)
  , collapsePath
  , extractImportNames
  , moduleNameToProjectUri
  , pathImportFile
  , pathModuleUri
  , typecheckWithDependencies
  , TypeCheckWithDepsResult(..)
  , ResolvedImport(..)
  )

-- ----------------------------------------------------------------------------
-- Virtual File System
-- ----------------------------------------------------------------------------

-- | Virtual File System for storing project files.
-- Files are indexed by the key the caller gave them. A bare name finds a file by
-- its module name (e.g., "helper" not "helper.l4"); a path import finds it by its
-- path (e.g., "rows/b/mod.l4"). A key serves both: "helper.l4" is where
-- @IMPORT helper@ and ``IMPORT `.\/helper` `` look.
newtype VFS = VFS { unVFS :: Map Text Text }
  deriving stock (Eq, Show)

-- | Empty VFS.
emptyVFS :: VFS
emptyVFS = VFS Map.empty

-- | Look up a file in the VFS by module name.
--
-- The key has to be the name itself, with or without @.l4@: a bare name is never
-- looked for beside the file that writes it, or in a folder.
vfsLookup :: Text -> VFS -> Maybe Text
vfsLookup moduleName (VFS m) =
  -- Try both with and without .l4 extension
  Map.lookup moduleName m
  <|> Map.lookup (moduleName <> ".l4") m
  <|> Map.lookup (fromMaybe moduleName (Text.stripSuffix ".l4" moduleName)) m

-- | Look up a file in the VFS by its path, as a path import names it.
--
-- The path is compared with every key after both are collapsed ('collapsePath'),
-- with or without the @.l4@, so @rows\/b\/mod.l4@ is found by @rows\/b\/mod.l4@, by
-- @rows\/a\/..\/b\/mod.l4@ and by a key that was stored as @.\/rows\/b\/mod@. A
-- path that climbs above the start of the files finds nothing, and so does a
-- key that does: neither is ever looked at.
vfsLookupPath :: FilePath -> VFS -> Maybe Text
vfsLookupPath path (VFS m)
  | wanted.cpEscaped = Nothing
  | otherwise = listToMaybe
      [ contents
      | (key, contents) <- Map.toAscList m
      , vfsKeyPath key == Just (dropL4 wanted.cpPath)
      ]
  where
    wanted = collapsePath path

-- | The path a key stands for, as 'vfsLookupPath' compares it: collapsed, and
-- without the @.l4@, so that @.\/rows\/b\/mod.l4@ and @rows\/b\/mod@ are one path.
-- 'Nothing' for a key that climbs above the start of the files, which is never
-- looked at. A key with a leading @\/@ keeps it, and so is never the same path as
-- one without.
--
-- Whoever asks whether two keys are one file uses this function, so that the
-- question has one answer.
vfsKeyPath :: Text -> Maybe FilePath
vfsKeyPath key
  | have.cpEscaped = Nothing
  | otherwise = Just (dropL4 have.cpPath)
  where
    have = collapsePath (Text.unpack key)

dropL4 :: FilePath -> FilePath
dropL4 p = maybe p reverse (stripPrefix (reverse ".l4") (reverse p))

-- | Insert or update a file in the VFS.
vfsInsert :: Text -> Text -> VFS -> VFS
vfsInsert moduleName contents (VFS m) = VFS (Map.insert moduleName contents m)

-- | Create a VFS from a list of (moduleName, contents) pairs.
vfsFromList :: [(Text, Text)] -> VFS
vfsFromList = VFS . Map.fromList

-- | Get all module names in the VFS.
vfsKeys :: VFS -> [Text]
vfsKeys (VFS m) = Map.keys m

-- ----------------------------------------------------------------------------
-- Module Lookup for API
-- ----------------------------------------------------------------------------

-- | Create the lookup the API resolves imports with.
--
-- A bare name checks embedded libraries first, then the VFS; one that is found in
-- the VFS is at the top of the files, so its own path imports start there. A path
-- is looked for in the VFS alone: it is a file the caller supplied, and an
-- embedded library of the same name is not it.
apiImportLookup :: VFS -> ImportLookup Identity
apiImportLookup vfs = ImportLookup
  { ilBare = \modName -> Identity $
      fmap (\src -> BareHit { bhSource = src, bhDirectory = Nothing }) (lookupEmbeddedLibrary modName)
      `mplus` fmap (\src -> BareHit { bhSource = src, bhDirectory = Just "." }) (vfsLookup modName vfs)
  , ilPath = \path -> Identity (vfsLookupPath path vfs)
  }

-- ----------------------------------------------------------------------------
-- Type Checking with Imports
-- ----------------------------------------------------------------------------

-- | Type-check a module with import resolution.
--
-- This function:
-- 1. Parses the main source
-- 2. Extracts IMPORT statements
-- 3. Recursively resolves imports (from embedded libs + VFS)
-- 4. Type-checks all modules in dependency order
--
-- The document is at the top of the VFS, as a file called @main@: its path
-- imports start there. Use 'checkWithImportsAt' to say it is somewhere else.
--
-- Returns 'Left' with error messages if resolution/parsing fails,
-- 'Right' with the type-check result otherwise.
checkWithImports :: VFS -> Text -> Either [Text] TypeCheckWithDepsResult
checkWithImports vfs source =
  checkWithImportsAndUri vfs "main" source

-- | Type-check a module with a specific module name.
--
-- The document is a module of that name at the top of the VFS.
checkWithImportsAndUri :: VFS -> Text -> Text -> Either [Text] TypeCheckWithDepsResult
checkWithImportsAndUri vfs moduleName source =
  checkAs vfs
    (Importer { impLabel = moduleName <> ".l4", impDirectory = Just "." })
    (moduleNameToProjectUri moduleName)
    source

-- | Type-check a document that lives at a path among the VFS's files, such as
-- @rows\/a\/main.l4@, so that ``IMPORT `..\/b\/mod` `` in it starts from @rows\/a@.
--
-- The path is read like the written name of a path import: with or without the
-- @.l4@, any @.@ and @..@ collapsed, and a leading @\/@ ignored. The document is
-- known by it: it is the module at that address, whatever the files hold there, so
-- a file that imports it back makes a cycle, and a copy of the document among the
-- files is never read in its place. @checkWithImportsAt vfs "main"@ is
-- 'checkWithImports'.
checkWithImportsAt :: VFS -> Text -> Text -> Either [Text] TypeCheckWithDepsResult
checkWithImportsAt vfs documentPath source =
  checkAs vfs
    (Importer { impLabel = Text.pack here.cpPath, impDirectory = Just (takeDirectory here.cpPath) })
    (pathModuleUri here.cpPath)
    source
  where
    here = collapsePath (pathImportFile documentPath)

checkAs :: VFS -> Importer -> NormalizedUri -> Text -> Either [Text] TypeCheckWithDepsResult
checkAs vfs importer uri source =
  let Identity result = typecheckWithDependencies (apiImportLookup vfs) importer uri source
   in result
