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

  -- Register dependency so that GHC re-embeds a library that changed.
  --
  -- STALENESS GOTCHA, measured 2026-10-13 (GHC 9.10.3, Cabal 3.16, a checkout
  -- built with @cabal build@): @path@ is the checkout's own
  -- @jl4-core/libraries/<name>.l4@, and GHC records it in
  -- "L4.API.EmbeddedLibraries"'s interface with a content hash, so when GHC
  -- runs it does notice an edited library and re-embeds it. But editing only
  -- @libraries/*.l4@ leaves nothing for Cabal to rebuild: @cabal build@ prints
  -- @Up to date@, never calls GHC, and the binary keeps the old stdlib.
  -- @touch@ does not help either (Cabal compares content). Any real change to
  -- a jl4-core source file makes Cabal call GHC, which then re-embeds. While
  -- developing the stdlib the reliable way is to set @JL4_LIBRARY_PATH@ to your
  -- worktree's @jl4-core/libraries@, which outranks the embed in import
  -- resolution. See jl4-core/libraries/README.md and
  -- LIBRARY-RESOLUTION-SHADOW-SPEC §3.4.
  addDependentFile path
  
  -- Read file contents at compile time
  contents <- runIO $ readFile path
  
  -- Create the tuple expression: (Text.pack name, Text.pack contents)
  [| (name, contents) |]
