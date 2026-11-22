{-# LANGUAGE TemplateHaskell #-}
-- Forces this module to be compiled again whenever GHC runs on the package.
-- The splices below read the environment, which neither GHC nor Cabal tracks,
-- so without this a build whose variables changed but whose sources did not
-- would keep the values of the build before. See 'buildInfoLine'.
{-# OPTIONS_GHC -fforce-recomp #-}

-- | Which build of the L4 tools this is, baked in when they are compiled.
--
-- @l4@ and @jl4-lsp@ print it for @--version@, and @jl4-lsp@ also reports it as
-- its LSP @serverInfo@ and logs it at start-up. A release build says which
-- release, branch, commit and day it came from; a build made without a release
-- says @dev@, so a binary built from a working tree can never pass for a
-- release.
--
-- The values come from four environment variables read by Template Haskell
-- splices at compile time, the way "Version" in @jl4-service@ reads
-- @JL4_SERVICE_VERSION@:
--
-- * @L4_BUILD_RELEASE@: the release name, such as @1.6.91@ (a release built by
--   @main-tag.yml@) or @unstable-20261014-8b2f1a0@ (one built by the
--   prereleases shelf);
-- * @L4_BUILD_BRANCH@: the branch it was built from, such as @main@. It is
--   passed in and never worked out from the checkout, which in CI has no
--   branch (@actions/checkout@ leaves a detached HEAD);
-- * @L4_BUILD_COMMIT@: the commit (only its first seven characters are kept);
-- * @L4_BUILD_DATE@: the day of the build, such as @2026-10-14@.
--
-- A build with @L4_BUILD_RELEASE@ unset or empty is a @dev@ build, whatever the
-- other three say. A release build whose @L4_BUILD_BRANCH@ is unset says
-- @unknown@ for the branch.
--
-- The bake follows the environment only when GHC runs on this module, and
-- nothing makes that happen by itself. Cabal does not see an environment
-- variable change, so on a tree that is already built it reports "Up to date"
-- and nothing is compiled; @touch@ does not help either (Cabal compares
-- contents). @-fforce-recomp@ above makes this module compile again every time
-- GHC does run on @jl4-lsp@, which covers a build whose sources changed. It
-- cannot make Cabal run GHC at all, so the variables have to be set before the
-- first thing that compiles @jl4-lsp@: in CI that is @cabal build
-- --only-dependencies@, which compiles the local libraries too, and a library
-- it compiled without the variables stays @dev@ when the build step finds it
-- up to date. On a warm tree where nothing else changed, change a byte of this
-- file, or clean.
module LSP.L4.BuildInfo
  ( buildInfoLine
  , renderBuildInfo
  ) where

import Data.Text (Text)
import qualified Data.Text as Text
import Language.Haskell.TH (runIO, stringE)
import System.Environment (lookupEnv)

-- | The one line that names this build: @dev@, or
-- @\<release\> (\<branch\>, \<commit\>, \<date\>)@. See the module header for
-- where the parts come from.
buildInfoLine :: Text
buildInfoLine =
  renderBuildInfo
    (Text.pack $(runIO (maybe "" id <$> lookupEnv "L4_BUILD_RELEASE") >>= stringE))
    (Text.pack $(runIO (maybe "" id <$> lookupEnv "L4_BUILD_BRANCH") >>= stringE))
    (Text.pack $(runIO (maybe "" id <$> lookupEnv "L4_BUILD_COMMIT") >>= stringE))
    (Text.pack $(runIO (maybe "" id <$> lookupEnv "L4_BUILD_DATE") >>= stringE))

-- | The line for a release, a branch, a commit and a date.
--
-- No release is @dev@, whatever the rest say. Otherwise the release, then in
-- brackets the branch (@unknown@ if empty), the commit cut to its first seven
-- characters, and the date, with the commit and the date left out when empty.
-- Each part loses the white space around it, and a line break inside it becomes
-- a space: a value that came through a Windows shell can end in a carriage
-- return, and the result must stay one line.
renderBuildInfo :: Text -> Text -> Text -> Text -> Text
renderBuildInfo release branch commit date
  | Text.null release' = "dev"
  | otherwise = release' <> " (" <> Text.intercalate ", " details <> ")"
  where
    release' = oneLine release
    branch' = case oneLine branch of
      "" -> "unknown"
      b -> b
    details = branch' : filter (not . Text.null) [Text.take 7 (oneLine commit), oneLine date]
    -- No white space at either end, and any run of it inside (a line break,
    -- for one) a single space.
    oneLine = Text.unwords . Text.words
