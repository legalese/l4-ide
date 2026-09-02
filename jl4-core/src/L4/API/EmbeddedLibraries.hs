{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}
-- | Embedded L4 core libraries.
--
-- This module uses Template Haskell to embed the contents of L4 library files
-- at compile time. This allows the API to resolve IMPORT statements
-- for core libraries without needing filesystem access.
--
-- The libraries are read from the @data-files@ specified in @jl4-core.cabal@
-- (i.e., @libraries/*.l4@) during compilation.
--
-- @since 0.1
module L4.API.EmbeddedLibraries
  ( embeddedLibraries
  , embeddedLibraryNames
  , lookupEmbeddedLibrary
  ) where

import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import System.Directory (doesFileExist, getCurrentDirectory)
import System.FilePath ((</>))
import Language.Haskell.TH.Syntax (runIO)

import qualified Paths_jl4_core

-- Import TH helpers from separate module (GHC stage restriction)
import L4.API.EmbeddedLibraries.TH (embedLibrariesFromDir)

-- | List of embedded library names (without .l4 extension).
embeddedLibraryNames :: [Text]
embeddedLibraryNames = Map.keys embeddedLibraries

-- | Look up an embedded library by name.
-- The name should be without the .l4 extension (e.g., "prelude", "math").
lookupEmbeddedLibrary :: Text -> Maybe Text
lookupEmbeddedLibrary = flip Map.lookup embeddedLibraries

-- | Embedded libraries as a Map from name to source code.
-- The name is without the .l4 extension.
-- This is computed at compile time using Template Haskell.
embeddedLibraries :: Map Text Text
embeddedLibraries = Map.fromList $ map (\(n, c) -> (Text.pack n, Text.pack c)) $(do
  -- Get the data directory at compile time
  dataDir <- runIO Paths_jl4_core.getDataDir
  let libDir = dataDir </> "libraries"
  
  -- Check if directory exists by looking for prelude.l4
  libDirExists <- runIO $ doesFileExist (libDir </> "prelude.l4")
  
  if libDirExists
    then embedLibrariesFromDir libDir
    else do
      -- Fallback: try relative path for development
      let devLibDir = "libraries"
      devExists <- runIO $ doesFileExist (devLibDir </> "prelude.l4")
      if devExists
        then embedLibrariesFromDir devLibDir
        else do
          -- Try jl4-core/libraries for building from repo root
          let repoLibDir = "jl4-core" </> "libraries"
          repoExists <- runIO $ doesFileExist (repoLibDir </> "prelude.l4")
          if repoExists
            then embedLibrariesFromDir repoLibDir
            -- FAIL. This used to be `[| [] |]`, which turned "I cannot find the
            -- standard library" at BUILD time into a binary that ships without
            -- one and only fails when a user writes `IMPORT prelude`. A
            -- stdlib-less build is never intentional, so it is a build error.
            --
            -- If you are seeing this: the usual cause is that `data-files` in
            -- jl4-core.cabal has been silently disabled by a section inserted
            -- above it, so the sdist carries no .l4 files and a store build
            -- (`cabal install`) has nothing to embed. Check with
            -- `cabal check` and `cabal sdist jl4-core --list-only | grep '\.l4$'`.
            else do
              cwd <- runIO getCurrentDirectory
              fail $ unlines
                [ "L4.API.EmbeddedLibraries: found no standard library to embed."
                , "Probed, in order:"
                , "  1. " ++ (dataDir </> "libraries") ++ "   (Cabal datadir)"
                , "  2. " ++ devLibDir  ++ "   (relative to cwd)"
                , "  3. " ++ repoLibDir ++ "   (relative to cwd)"
                , "cwd was: " ++ cwd
                , ""
                , "A binary built from this would answer \"Module not found: prelude\""
                , "for every IMPORT. Refusing to build it."
                , "Most likely cause: jl4-core.cabal's `data-files` field has been"
                , "disabled by a section appearing above it, so the sdist ships no"
                , "libraries. Verify with:"
                , "  cabal check"
                , "  cabal sdist jl4-core --list-only | grep '\\.l4$'"
                ]
  )
