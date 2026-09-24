-- | Unit tests for 'LSP.L4.Rules.roundTrippingFileUri' — the guarantee that a
-- candidate URI the import resolver hands downstream reads back as the path it
-- was built from (smucclaw/l4-ide#971).
--
-- These are string-level: nothing is created on disk, and the only IO is
-- 'makeAbsolute', so nothing here depends on the runner's filesystem encoding.
-- That is what lets this be the place that covers a NON-ASCII module name.
-- @l4-cli-test@'s own #971 group drives the real CLI and so uses an ASCII
-- basename with a space in it — the same defect, with no filename encoding in
-- the way.
module ImportUriSpec (spec) where

import Data.List (isInfixOf)

import Language.LSP.Protocol.Types
  ( filePathToUri
  , fromNormalizedFilePath
  , toNormalizedUri
  , uriToNormalizedFilePath
  )
import System.Directory (makeAbsolute)
import System.FilePath ((</>))

import LSP.L4.Rules (roundTrippingFileUri)

import Test.Hspec

-- | What a URI reads back as, via the same call 'LSP.L4.Rules.GetLexTokens'
-- makes when it has to load a file it was handed a URI for.
readsBackAs :: FilePath -> IO (Maybe FilePath)
readsBackAs fp = do
  nuri <- roundTrippingFileUri fp
  pure (fromNormalizedFilePath <$> uriToNormalizedFilePath nuri)

-- | The same, for a URI built the naive way — what the resolver did before #971.
readsBackNaively :: FilePath -> Maybe FilePath
readsBackNaively fp =
  fromNormalizedFilePath <$> uriToNormalizedFilePath (toNormalizedUri (filePathToUri fp))

spec :: Spec
spec = do
  describe "roundTrippingFileUri (smucclaw/l4-ide#971)" $ do

    it "leaves an ASCII relative path exactly as filePathToUri spells it" $ do
      -- The corpus is ASCII, and its goldens capture candidate URIs verbatim
      -- (jl4/examples/**/tests/*.golden). Nothing may move for those, which is
      -- why the fix is conditional rather than "always make it absolute".
      nuri <- roundTrippingFileUri "helper.l4"
      nuri `shouldBe` toNormalizedUri (filePathToUri "helper.l4")

    it "leaves an ASCII absolute path exactly as filePathToUri spells it" $ do
      nuri <- roundTrippingFileUri ("/tmp" </> "proj" </> "helper.l4")
      nuri `shouldBe` toNormalizedUri (filePathToUri ("/tmp" </> "proj" </> "helper.l4"))

    -- The defect being worked around. It lives in lsp-types, not here:
    -- 'filePathToUri' on a RELATIVE path emits @file://<escaped>@ with no
    -- leading slash, so the escaped path lands in the URI's authority, and
    -- @platformAdjustFromUriPath@ prepends the authority WITHOUT un-escaping it.
    --
    -- If either of these two goes red after a dependency bump, upstream has
    -- fixed it and 'roundTrippingFileUri' can become the identity. Until then
    -- they are the reason it exists.
    -- The marker is @%25@ -- an escaped percent sign -- not @%20@ or @%D7@,
    -- because the escape is applied TWICE. "my mod.l4" comes back as
    -- "my%2520mod.l4" on this machine: the space became %20, and then the % of
    -- that became %25. Only the doubling is asserted, not the whole string: the
    -- path-to-URI mapping is platform-dependent and this suite runs on Windows
    -- too.
    it "documents that lsp-types loses a percent-escape in a relative path" $ do
      readsBackNaively "my mod.l4" `shouldNotBe` Just "my mod.l4"
      case readsBackNaively "my mod.l4" of
        Just recovered -> recovered `shouldSatisfy` ("%25" `isInfixOf`)
        Nothing -> expectationFailure "expected a path back, just the wrong one"

    it "...and does so for a non-ASCII basename too" $ do
      readsBackNaively "קירור.l4" `shouldNotBe` Just "קירור.l4"
      case readsBackNaively "קירור.l4" of
        Just recovered -> recovered `shouldSatisfy` ("%25" `isInfixOf`)
        Nothing -> expectationFailure "expected a path back, just the wrong one"

    it "loses only the FIRST path segment, which is why a bare basename is at risk" $ do
      -- lsp-types puts everything before the first slash into the authority, so
      -- a path with a directory component survives naively while a bare basename
      -- does not. The CLI hits the broken case precisely when a user names the
      -- entry file bare: the root directory is then ".", and "." </> "my mod.l4"
      -- normalises to a single segment. Given the same project by a path with a
      -- directory in it, nothing goes wrong — which is why a suite whose fixture
      -- paths all carry a directory component could not see this.
      readsBackNaively ("sub" </> "my mod.l4") `shouldBe` Just ("sub" </> "my mod.l4")
      readsBackNaively "my mod.l4" `shouldNotBe` Just "my mod.l4"

    -- ...and the repair. Each of these names a file the resolver has already
    -- found on disk by its raw FilePath, so a URI that reads back as a DIFFERENT
    -- file names one that does not exist — silently, because the import counts as
    -- resolved and the load failure lands on the bogus URI.
    --
    -- The property is "the same file", not "the same spelling": the fix leaves a
    -- path alone when it already round-trips, so some of these come back relative
    -- and some absolute, and both are correct.
    let survives label fp =
          it ("reads back as the same file: " <> label) $ do
            expected <- makeAbsolute fp
            got <- readsBackAs fp
            actual <- traverse makeAbsolute got
            actual `shouldBe` Just expected

    survives "a space in the basename"        "my mod.l4"
    survives "a literal percent sign"         "50%.l4"
    survives "Hebrew letters"                 "קירור.l4"
    survives "Hebrew letters with a hyphen"   "חוק-קירור.l4"
    survives "a subdirectory and a space"     ("sub" </> "my mod.l4")
