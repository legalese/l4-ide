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
  , selfCaseVariantMessage
  , skippedCaseVariantMessage
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
  , caseVariantNames = []
  , ownModuleVariant = Nothing
  , skippedCaseVariantWarning = Nothing
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
            , caseVariantNames = []
            , ownModuleVariant = Nothing
            , skippedCaseVariantWarning = Nothing
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

  -- smucclaw/l4-ide#1080: the warning for a file passed over because its name
  -- differs from the IMPORT in capitals, in its extension's capitals, or by a
  -- difference such as ß for ss that a case-insensitive disk may ignore. Pure
  -- text, so the same on every disk; the CLI suite checks that it is printed,
  -- once.
  describe "skippedCaseVariantMessage (the skipped-variant warning)" $ do
    it "names the file, the reason, the copy used and the two fixes" $
      skippedCaseVariantMessage "math" EmbeddedCandidate [(["project root", "importer-relative"], "/w/Math.l4")]
        `shouldBe` Text.unlines
          [ "`IMPORT math` did not use `Math.l4` beside the importing file, because capital letters count in a module name: `Math` and `math` are different names."
          , "It used the standard library's `math` instead."
          , "To use that file, change the IMPORT to `Math`, or rename the file to `math.l4`."
          ]

    it "describes a file the import used, by its name and tier" $
      skippedCaseVariantMessage "zzmod" (FileCandidate "XDG data dir" "/home/dev/.local/share/jl4/libraries/zzmod.l4")
        [(["project root"], "/w/Zzmod.l4")]
        `shouldBe` Text.unlines
          [ "`IMPORT zzmod` did not use `Zzmod.l4` in the project's root folder, because capital letters count in a module name: `Zzmod` and `zzmod` are different names."
          , "It used `zzmod.l4` in your personal library folder (the XDG data dir) instead."
          , "To use that file, change the IMPORT to `Zzmod`, or rename the file to `zzmod.l4`."
          ]

    it "lists several files passed over, one per line" $
      skippedCaseVariantMessage "math" EmbeddedCandidate
        [ (["$JL4_LIBRARY_PATH"], "/lib/MATH.l4")
        , (["importer-relative"], "/w/Math.l4")
        ]
        `shouldBe` Text.unlines
          [ "`IMPORT math` did not use these files, because capital letters count in a module name and none of them is spelled `math`:"
          , "  `MATH.l4` in the folder JL4_LIBRARY_PATH names"
          , "  `Math.l4` beside the importing file"
          , "It used the standard library's `math` instead."
          , "To use one of them, change the IMPORT to that file's spelling, or rename the file to `math.l4`."
          ]

    it "never prints a folder's path" $ do
      let msg = skippedCaseVariantMessage "zzmod" (FileCandidate "VSCode bundle" "/opt/l4/bin/../../libraries/zzmod.l4")
                  [(["XDG data dir"], "/home/dev/.local/share/jl4/libraries/Zzmod.l4")]
      msg `shouldSatisfy` (not . Text.isInfixOf "/")

    -- Review finding C: an IMPORT names no extension, so when the file ends
    -- in `.L4` no spelling of the IMPORT reaches it; only a rename does.
    it "advises only a rename when just the extension's capitals differ" $
      skippedCaseVariantMessage "prelude" EmbeddedCandidate [(["project root", "importer-relative"], "/w/prelude.L4")]
        `shouldBe` Text.unlines
          [ "`IMPORT prelude` did not use `prelude.L4` beside the importing file, because a module's file name must end in `.l4`, in small letters."
          , "It used the standard library's `prelude` instead."
          , "To use that file, rename it to `prelude.l4`."
          ]

    it "advises only a rename when the name and the extension both differ" $
      skippedCaseVariantMessage "math" EmbeddedCandidate [(["project root", "importer-relative"], "/w/Math.L4")]
        `shouldBe` Text.unlines
          [ "`IMPORT math` did not use `Math.L4` beside the importing file, because a module's file must be named exactly `math.l4`, and capitals count."
          , "It used the standard library's `math` instead."
          , "To use that file, rename it to `math.l4`."
          ]

    -- Review finding D: `straße` and `strasse` do not differ in capitals.
    it "does not blame capitals for a name that differs by ß and ss" $
      skippedCaseVariantMessage "strasse" (FileCandidate "XDG data dir" "/home/dev/.local/share/jl4/libraries/strasse.l4")
        [(["importer-relative"], "/w/stra\xdf\&e.l4")]
        `shouldBe` Text.unlines
          [ "`IMPORT strasse` did not use `stra\xdf\&e.l4` beside the importing file, because module names must match exactly, letter for letter: `stra\xdf\&e` and `strasse` are different names."
          , "It used `strasse.l4` in your personal library folder (the XDG data dir) instead."
          , "To use that file, change the IMPORT to `stra\xdf\&e`, or rename the file to `strasse.l4`."
          ]

    it "words a mixed list so that every fix it offers works" $
      skippedCaseVariantMessage "math" EmbeddedCandidate
        [ (["$JL4_LIBRARY_PATH"], "/lib/MATH.L4")
        , (["importer-relative"], "/w/Math.l4")
        ]
        `shouldBe` Text.unlines
          [ "`IMPORT math` did not use these files, because a module's file must be named exactly `math.l4`, and none of them is:"
          , "  `MATH.L4` in the folder JL4_LIBRARY_PATH names"
          , "  `Math.l4` beside the importing file"
          , "It used the standard library's `math` instead."
          , "To use one of them, rename it to `math.l4`, or, if its name ends in `.l4`, change the IMPORT to its spelling."
          ]

  -- Review finding A, as revised by GM (2026-11-21).
  describe "selfCaseVariantMessage (the importing file passed over)" $ do
    it "says the IMPORT is the file's own name, and offers no fix that imports it" $
      selfCaseVariantMessage "math" EmbeddedCandidate "/w/Math.l4"
        `shouldBe` Text.unlines
          [ "`IMPORT math` did not use `Math.l4`, which is the importing file itself: `math` differs from `Math`, the name of this file's own module, only in its capitals."
          , "It used the standard library's `math` instead."
          , "If you meant this file, remove the IMPORT: a module cannot import itself, and a file's own definitions need no IMPORT. If you meant the standard library's `math`, nothing needs to change."
          ]

    it "names a copy found on disk the way the other warnings do" $
      selfCaseVariantMessage "zzmod" (FileCandidate "XDG data dir" "/home/dev/.local/share/jl4/libraries/zzmod.l4") "/w/Zzmod.l4"
        `shouldBe` Text.unlines
          [ "`IMPORT zzmod` did not use `Zzmod.l4`, which is the importing file itself: `zzmod` differs from `Zzmod`, the name of this file's own module, only in its capitals."
          , "It used `zzmod.l4` in your personal library folder (the XDG data dir) instead."
          , "If you meant this file, remove the IMPORT: a module cannot import itself, and a file's own definitions need no IMPORT. If you meant `zzmod.l4` in your personal library folder (the XDG data dir), nothing needs to change."
          ]
