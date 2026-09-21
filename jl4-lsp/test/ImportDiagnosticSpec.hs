-- | Unit tests for the list of locations the not-found IMPORT diagnostic prints
-- (smucclaw/l4-ide#971 and the review of its fix).
--
-- Two properties, both of which the first version of that message got wrong:
--
--   * __one line per location__. The VFS tier prints URIs and the filesystem
--     tier prints paths, and for an import whose project root is the importing
--     file's own directory — which is what the CLI sets it to — those are the
--     same file. A text-level @nub@ cannot see that, so a CLI run printed
--     @file:\/\/zz-nope.l4@ and @zz-nope.l4@ as two entries, and an LSP session
--     printed four entries for two locations.
--
--   * __in tier order__, the order of the table in
--     doc\/reference\/libraries\/resolution.md. The embedded stdlib is tier 4 of
--     that ladder, and was appended after everything else whatever its rank.
--
-- Nothing here touches the filesystem except 'makeAbsolute', which reads the
-- current directory; no file is created and no module is resolved.
--
-- The path spellings below are POSIX-shaped, and a filesystem candidate's
-- expected text is built with the same 'normalise' the diagnostic applies, so
-- only the dedupe and the ordering are being asserted. @jl4-lsp-test@ is not in
-- any Windows CI job (main-tag.yml's Windows runner builds @exe:l4@ and runs
-- @l4-cli-test@ only), so unlike "ImportUriSpec" this one does not have to hold
-- its assertions at arm's length from the platform.
module ImportDiagnosticSpec (spec) where

import qualified Data.Text as Text

import Language.LSP.Protocol.Types (Uri (..), filePathToUri, toNormalizedUri)
import System.FilePath (normalise)

import LSP.L4.Rules
  ( EmbedStatus (..)
  , ImportOutcome (..)
  , LibraryCandidate (..)
  , TriedLocation (..)
  , dedupeTriedLocations
  , triedLocations
  )

import Test.Hspec

-- | The shape of an unresolved import as the CLI produces it: the project root
-- is the importing file's own directory, so every filesystem candidate is
-- relative and the root and importer-relative tiers name one file.
cliOutcome :: ImportOutcome
cliOutcome = ImportOutcome
  { importUri = Nothing
  , vfsTried =
      [ toNormalizedUri (Uri "project:/zz-nope-971.l4")
      , toNormalizedUri (filePathToUri "zz-nope-971.l4")
      ]
  , libTried =
      [ FileCandidate "project root"      "./zz-nope-971.l4"
      , FileCandidate "importer-relative" "zz-nope-971.l4"
      , EmbeddedCandidate
      , FileCandidate "XDG data dir"      "/home/dev/.local/share/jl4/libraries/zz-nope-971.l4"
      , FileCandidate "VSCode bundle"     "/opt/l4/bin/../../libraries/zz-nope-971.l4"
      ]
  , embedTried = EmbedMissing 22
  }

embedLine :: Text.Text
embedLine = "the stdlib embedded in this binary (22 modules, not among them)"

-- | How the diagnostic spells a filesystem candidate.
asPath :: FilePath -> Text.Text
asPath = Text.pack . normalise

spec :: Spec
spec = do
  describe "the locations an unresolved IMPORT lists" $ do

    it "names each location once, spelled as a path" $ do
      -- The regression this test exists for. Before the dedupe the list was
      --     project:/zz-nope-971.l4, file://zz-nope-971.l4, zz-nope-971.l4, ...
      -- whose middle two entries are one file: `file://zz-nope-971.l4` is a
      -- RELATIVE file: URI, which is a VFS key and not a place a reader can go
      -- and look at, while `zz-nope-971.l4` is the name they typed.
      got <- triedLocations cliOutcome
      got `shouldBe`
        [ "project:/zz-nope-971.l4"
        , asPath "zz-nope-971.l4"
        , embedLine
        , asPath "/home/dev/.local/share/jl4/libraries/zz-nope-971.l4"
        , asPath "/opt/l4/bin/../../libraries/zz-nope-971.l4"
        ]

    it "puts the embedded stdlib at its own rank, not at the end" $ do
      -- It is tier 4 (see `resolveLibrary`'s ladder and the table in
      -- doc/reference/libraries/resolution.md); the message says the list is in
      -- the order the locations were tried, so this is what makes that true.
      got <- triedLocations cliOutcome
      last got `shouldNotBe` embedLine
      let ix x = length (takeWhile (/= x) got)
      ix embedLine `shouldSatisfy` (< ix (asPath "/home/dev/.local/share/jl4/libraries/zz-nope-971.l4"))

    it "collapses an LSP session's four entries for two locations into two" $ do
      -- Each file lands at the rank of the tier that spells it as a path, so the
      -- project root (tier 2) comes out above the importer-relative one (tier 3)
      -- even though the VFS probed them the other way round.
      -- Measured over stdio against jl4-lsp: an absolute-path session listed
      -- each of the two directories once as a URI and once as a path.
      let lspOutcome = ImportOutcome
            { importUri = Nothing
            , vfsTried =
                [ toNormalizedUri (Uri "project:/zz.l4")
                , toNormalizedUri (filePathToUri "/abs/lsp1/zz.l4")
                , toNormalizedUri (filePathToUri "/zz.l4")
                ]
            , libTried =
                [ FileCandidate "project root"      "/zz.l4"
                , FileCandidate "importer-relative" "/abs/lsp1/zz.l4"
                , EmbeddedCandidate
                ]
            , embedTried = EmbedMissing 22
            }
      got <- triedLocations lspOutcome
      got `shouldBe` [ "project:/zz.l4", asPath "/zz.l4", asPath "/abs/lsp1/zz.l4", embedLine ]

    it "keeps a location that only ever appeared as a URI" $ do
      -- `project:` is the Monaco VFS scheme: it names no path, so it can neither
      -- be deduped against one nor be respelled as one, and it must survive.
      got <- triedLocations cliOutcome
      got `shouldSatisfy` elem "project:/zz-nope-971.l4"

  describe "dedupeTriedLocations (the rule, without the resolver)" $ do
    let urlLoc d k = TriedLocation { display = d, sameFileAs = Just k, spelledAsPath = False }
        pathLoc d k = TriedLocation { display = d, sameFileAs = Just k, spelledAsPath = True }
        keyless d = TriedLocation { display = d, sameFileAs = Nothing, spelledAsPath = False }

    it "prefers the path spelling, at that entry's own rank" $ do
      dedupeTriedLocations [urlLoc "file://a.l4" "/w/a.l4", pathLoc "a.l4" "/w/a.l4"]
        `shouldBe` ["a.l4"]
      -- and the surviving entry sits where the path-spelled one sat, which is
      -- what keeps the list in the order of the resolution table
      dedupeTriedLocations
        [ urlLoc "file://a.l4" "/w/a.l4"
        , pathLoc "/lib/a.l4" "/lib/a.l4"
        , pathLoc "a.l4" "/w/a.l4"
        ] `shouldBe` ["/lib/a.l4", "a.l4"]

    it "does not merge two different files" $
      dedupeTriedLocations [pathLoc "a.l4" "/w/a.l4", pathLoc "sub/a.l4" "/w/sub/a.l4"]
        `shouldBe` ["a.l4", "sub/a.l4"]

    it "keys a location with no path on its own text" $
      dedupeTriedLocations [keyless "project:/a.l4", keyless "project:/a.l4", keyless "embedded"]
        `shouldBe` ["project:/a.l4", "embedded"]
