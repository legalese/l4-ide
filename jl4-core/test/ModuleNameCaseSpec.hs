-- | The case rule for module names, without a resolver or a disk
-- (smucclaw/l4-ide#1080).
--
-- Everything here is pure: a directory listing is a list of names, so these
-- examples give the same answer on a case-sensitive disk (Linux CI) and a
-- case-insensitive one (macOS, Windows), and they fail on any of them if the
-- rule in "L4.Import.ModuleNameCase" changes. That matters because a test that
-- asks a real disk for @dayDate.l4@ beside @daydate.l4@ passes on Linux whether
-- or not the rule exists: Linux already refuses it.
module ModuleNameCaseSpec (spec) where

import Test.Hspec

import L4.API.EmbeddedLibraries (embeddedLibraryNames)
import L4.Import.ModuleNameCase

spec :: Spec
spec = describe "L4.Import.ModuleNameCase (the case rule, #1080)" $ do
  describe "classifyEntry" $ do
    it "finds the exact entry" $
      classifyEntry ["daydate.l4", "prelude.l4"] "daydate.l4" `shouldBe` ExactEntry

    it "names an entry that differs only in capitals, and does not count it as the file" $
      classifyEntry ["daydate.l4", "prelude.l4"] "dayDate.l4"
        `shouldBe` CaseVariantEntries ["daydate.l4"]

    it "counts a different capitalisation of the extension as a variant too" $
      -- `IMPORT daydate` looks for `daydate.l4`; a case-insensitive disk would
      -- also answer yes for `daydate.L4`, and a case-sensitive one would not.
      classifyEntry ["daydate.L4"] "daydate.l4" `shouldBe` CaseVariantEntries ["daydate.L4"]

    it "prefers the exact entry when variants sit beside it (possible on Linux)" $
      classifyEntry ["Helper.l4", "helper.l4"] "helper.l4" `shouldBe` ExactEntry

    it "lists several variants sorted, each once" $
      classifyEntry ["DAYDATE.l4", "daydate.l4", "Daydate.l4", "daydate.l4"] "dayDate.l4"
        `shouldBe` CaseVariantEntries ["DAYDATE.l4", "Daydate.l4", "daydate.l4"]

    it "says nothing about an unrelated name" $
      classifyEntry ["prelude.l4", "math.l4"] "dayDate.l4" `shouldBe` NoEntry

    it "does not count a name stored in another Unicode normal form as a variant" $
      -- HFS+ lists a file created as `café.l4` (é = U+00E9) decomposed, as
      -- "cafe" plus U+0301. The source spells it composed. That is the same
      -- name, correctly written, so it must not be refused as a case variant
      -- (measured, design probe P11): the resolver keeps the disk's answer.
      classifyEntry ["cafe\x301.l4"] "caf\xe9.l4" `shouldBe` NoEntry

    it "lets a name that differs in both normal form and capitals through (the accepted limit)" $
      -- Pins the residual that the ruling accepted rather than add a
      -- normalisation library: on HFS+ the disk would answer yes, and this
      -- answer leaves that yes standing.
      classifyEntry ["cafe\x301.l4"] "CAF\xc9.l4" `shouldBe` NoEntry

  describe "caseVariants" $ do
    it "finds daydate among the embedded stdlib's names for dayDate" $
      caseVariants "dayDate" embeddedLibraryNames `shouldBe` ["daydate"]

    it "never offers the asked name itself" $
      caseVariants "daydate" embeddedLibraryNames `shouldBe` []

    it "finds nothing for a name with no near twin" $
      caseVariants "zz-no-such-module" embeddedLibraryNames `shouldBe` []

  describe "caseVariantHint" $ do
    it "says what to type, for one variant" $
      caseVariantHint "dayDate" ["prelude", "daydate"] `shouldBe` Just
        "Capital letters count in a module name: `dayDate` and `daydate` are different names. Did you mean `daydate`?"

    it "lists several variants" $
      caseVariantHint "dayDate" ["daydate", "DayDate", "prelude"] `shouldBe` Just
        "Capital letters count in a module name: `dayDate` is a different name from each of these. Did you mean one of: `DayDate`, `daydate`?"

    it "is silent when no variant exists" $
      caseVariantHint "zz-no-such-module" embeddedLibraryNames `shouldBe` Nothing

    -- Review finding D: full case folding equates `strasse` with `straße`,
    -- which do not differ in capitals, so the sentence must not say they do.
    it "does not blame capitals for a name that differs by ß and ss" $
      caseVariantHint "strasse" ["stra\xdf\&e"] `shouldBe` Just
        "Module names must match exactly, letter for letter: `strasse` and `stra\xdf\&e` are different names. Did you mean `stra\xdf\&e`?"

    it "does not blame capitals for two small sigmas" $
      caseVariantHint "\x3bf\x3b4\x3bf\x3c3" ["\x3bf\x3b4\x3bf\x3c2"] `shouldBe` Just
        "Module names must match exactly, letter for letter: `\x3bf\x3b4\x3bf\x3c3` and `\x3bf\x3b4\x3bf\x3c2` are different names. Did you mean `\x3bf\x3b4\x3bf\x3c2`?"

    it "does blame capitals when the only difference is a capital sigma" $
      caseVariantHint "\x39f\x394\x39f\x3a3" ["\x3bf\x3b4\x3bf\x3c2"] `shouldBe` Just
        "Capital letters count in a module name: `\x39f\x394\x39f\x3a3` and `\x3bf\x3b4\x3bf\x3c2` are different names. Did you mean `\x3bf\x3b4\x3bf\x3c2`?"

    it "uses the letter-for-letter wording when any one of several names needs it" $
      caseVariantHint "strasse" ["STRASSE", "stra\xdf\&e"] `shouldBe` Just
        "Module names must match exactly, letter for letter: `strasse` is a different name from each of these. Did you mean one of: `STRASSE`, `stra\xdf\&e`?"

  describe "differsOnlyInCapitals" $ do
    it "holds for a change of capitals" $
      differsOnlyInCapitals "dayDate" "daydate" `shouldBe` True

    it "fails for ß against ss, and for the two small sigmas" $ do
      differsOnlyInCapitals "strasse" "stra\xdf\&e" `shouldBe` False
      differsOnlyInCapitals "\x3bf\x3b4\x3bf\x3c3" "\x3bf\x3b4\x3bf\x3c2" `shouldBe` False

  -- Review finding A, as revised by GM (2026-11-21): @Foo.l4@ that writes
  -- @IMPORT foo@ is told what is true, not to import itself.
  describe "selfImportHint" $ do
    it "says the name is this file's own, and that a module cannot import itself" $
      selfImportHint "foo" "Foo" `shouldBe` Just
        "`foo` differs from `Foo`, the name of this file's own module, only in its capitals. If you meant this file, remove the IMPORT: a module cannot import itself, and a file's own definitions need no IMPORT."

    it "does not blame capitals for ß against ss" $
      selfImportHint "strasse" "Stra\xdf\&e" `shouldBe` Just
        "`strasse` differs from `Stra\xdf\&e`, the name of this file's own module, only in how its letters are written. If you meant this file, remove the IMPORT: a module cannot import itself, and a file's own definitions need no IMPORT."

    it "says nothing when the file's own name is not a near match, or is the name itself" $ do
      selfImportHint "foo" "Bar" `shouldBe` Nothing
      selfImportHint "foo" "foo" `shouldBe` Nothing
