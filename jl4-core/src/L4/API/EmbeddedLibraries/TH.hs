{-# LANGUAGE TemplateHaskell #-}
-- | Template Haskell helpers for embedding L4 libraries.
--
-- This module is separate from 'L4.API.EmbeddedLibraries' to satisfy
-- GHC's stage restriction (TH helpers must be defined in a separate module
-- from where they're used in splices).
--
-- @since 0.1
module L4.API.EmbeddedLibraries.TH
  ( embedLibrariesFromDir
  , embedOneLibrary
  ) where

import Language.Haskell.TH
import Language.Haskell.TH.Syntax (addDependentFile)
import System.Directory (listDirectory)
import System.FilePath ((</>), takeBaseName, takeExtension)

-- | Template Haskell helper to embed all .l4 files from a directory.
-- Returns an expression of type @[(Text, Text)]@.
embedLibrariesFromDir :: FilePath -> Q Exp
embedLibrariesFromDir libDir = do
  -- List all .l4 files
  files <- runIO $ do
    allFiles <- listDirectory libDir
    pure $ filter ((== ".l4") . takeExtension) allFiles
  
  -- Read each file and create a list expression
  libs <- mapM (embedOneLibrary libDir) files
  listE (map pure libs)

-- | Template Haskell helper to embed a single library file.
-- Returns an expression of type @(Text, Text)@.
embedOneLibrary :: FilePath -> FilePath -> Q Exp
embedOneLibrary libDir fileName = do
  let name = takeBaseName fileName
      path = libDir </> fileName

  -- Register dependency so rebuilds happen when files change.
  --
  -- STALENESS GOTCHA: @path@ is whatever directory the splice in
  -- 'L4.API.EmbeddedLibraries' resolved at /build/ time — typically the Cabal
  -- install datadir (e.g. @~/.cabal/share/.../jl4-core-*/libraries@), NOT your
  -- checkout. So editing a worktree's @jl4-core/libraries/*.l4@ does not
  -- invalidate this splice, and a plain @cabal build@ keeps the old embedded
  -- stdlib. To pick up stdlib edits either force a re-embed (touch
  -- EmbeddedLibraries.hs / clean-rebuild jl4-core) or — the reliable way while
  -- developing — set @JL4_LIBRARY_PATH@ to your worktree's
  -- @jl4-core/libraries@, which outranks the embed in import resolution.
  -- See jl4-core/libraries/README.md and LIBRARY-RESOLUTION-SHADOW-SPEC §3.4.
  addDependentFile path
  
  -- Read file contents at compile time
  contents <- runIO $ readFile path
  
  -- Create the tuple expression: (Text.pack name, Text.pack contents)
  [| (name, contents) |]
