{-# LANGUAGE OverloadedStrings #-}

-- | Which way a document runs, and what language it says it is in.
--
-- __Why a unit spec and not only CLI cases.__ These are pure table lookups over
-- a language tag, and the interesting inputs are tags no corpus file carries
-- (@he-Latn@, @az-Arab@, @zh-yue-Hant-HK@). Reaching them through @l4 render@
-- would need a fixture module per tag, and — since a tag no rendering in the
-- module uses no longer labels the document (see 'L4.Cli.Render') — most of them
-- are not even reachable that way: the CLI would answer with the module's own
-- language instead, and the answer under test would never be asked for. The
-- wiring is asserted end-to-end in @jl4/tests-cli@; the tables are asserted
-- here.
--
-- __The failure these guard is silent.__ A wrong direction is not an error: it
-- is a document that renders, exits 0, and puts the full stop at the wrong end
-- of the line. Same for the AKN language: a Hebrew act identified as an English
-- expression is well-formed XML.
module RenderLangDirSpec (spec) where

import L4.Export.Render (aknLanguage, isRtlLang, scriptSubtag)
import L4.Lexer (LangTag (..))
import Test.Hspec

spec :: Spec
spec = do
  describe "scriptSubtag" $ do
    it "finds a four-letter script subtag wherever BCP 47 allows one to sit" $ do
      scriptSubtag "he-Latn"        `shouldBe` Just "latn"
      scriptSubtag "az-Arab"        `shouldBe` Just "arab"
      scriptSubtag "az-Arab-IR"     `shouldBe` Just "arab"
      -- after an extended language subtag (3 letters), the script still reads
      scriptSubtag "zh-yue-Hant-HK" `shouldBe` Just "hant"
      -- case as typed does not matter; the answer is lowercased
      scriptSubtag "HE-HEBR"        `shouldBe` Just "hebr"

    it "reads no script where there is none" $ do
      scriptSubtag "he"       `shouldBe` Nothing
      scriptSubtag "he-IL"    `shouldBe` Nothing   -- region: two letters
      scriptSubtag "es-419"   `shouldBe` Nothing   -- region: three digits
      scriptSubtag "de-1901"  `shouldBe` Nothing   -- variant: four, starts with a digit
      scriptSubtag "sl-rozaj" `shouldBe` Nothing   -- variant: five to eight

    it "stops at a singleton, so an extension's payload is not read as a script" $ do
      -- `-x-` and `-u-` introduce private use and extensions. `Latn` here is
      -- four letters in the right shape and the wrong place.
      scriptSubtag "he-x-Latn"   `shouldBe` Nothing
      scriptSubtag "he-u-Latn"   `shouldBe` Nothing
      -- a real script BEFORE the singleton is still found
      scriptSubtag "he-Hebr-x-q" `shouldBe` Just "hebr"

  describe "isRtlLang" $ do
    let rtl t = it ("marks " <> show t <> " right-to-left") $
                  isRtlLang (MkLangTag t) `shouldBe` True
        ltr t = it ("leaves " <> show t <> " left-to-right") $
                  isRtlLang (MkLangTag t) `shouldBe` False

    describe "from the language, when the tag names no script" $ do
      mapM_ rtl [ "he", "ar", "fa", "ur", "yi", "ps", "ckb", "dv" ]
      -- the codes a real pipeline hands in: a deprecated alias an older locale
      -- stack still emits, and languages whose default script is Arabic
      mapM_ rtl [ "iw", "ji", "ug", "sd", "ks", "prs", "arc", "syr", "nqo" ]
      mapM_ ltr [ "en", "de", "fr", "ms", "zh", "ja", "ru", "hi", "id", "az", "ku", "pa" ]
      -- region and case are not the direction
      mapM_ rtl [ "he-IL", "HE", "HE-il", "ar-EG", "fa-AF" ]
      mapM_ ltr [ "en-GB", "EN", "zz" ]

    describe "from the script, when the tag names one" $ do
      -- an RTL language romanised runs left to right …
      mapM_ ltr [ "he-Latn", "ar-Latn", "fa-Latn", "yi-Latn", "ur-Latn" ]
      -- … and an LTR language in an RTL script runs right to left
      mapM_ rtl [ "az-Arab", "pa-Arab", "ku-Arab", "sd-Arab", "ms-Arab" ]
      -- the script table is consulted on the script, not on the language
      mapM_ rtl [ "yi-Hebr", "dv-Thaa", "ur-Aran", "ff-Adlm", "rhg-Rohg" ]
      mapM_ ltr [ "sd-Deva", "az-Cyrl", "sr-Cyrl", "zh-Hans", "hi-Deva" ]

    describe "a script neither table knows falls back to the language" $ do
      -- `Zsym`/`Zzzz` are the ISO 15924 codes for symbols and unknown-script.
      -- Falling through is what this code did before scripts were read at all,
      -- so an unrecognised script cannot make an answer WORSE than that.
      mapM_ rtl [ "he-Zzzz", "ar-Zsym" ]
      mapM_ ltr [ "en-Zzzz" ]

  describe "aknLanguage" $ do
    it "translates a BCP 47 primary subtag to the ISO 639-2/T code AKN wants" $ do
      aknLanguage (MkLangTag "he")    `shouldBe` "heb"
      aknLanguage (MkLangTag "en")    `shouldBe` "eng"
      aknLanguage (MkLangTag "ar")    `shouldBe` "ara"
      -- the TERMINOLOGICAL variant where ISO 639-2 has two: deu not ger,
      -- fra not fre, zho not chi
      aknLanguage (MkLangTag "de")    `shouldBe` "deu"
      aknLanguage (MkLangTag "fr")    `shouldBe` "fra"
      aknLanguage (MkLangTag "zh")    `shouldBe` "zho"

    it "answers on the primary subtag: a region or script does not change the expression's language" $ do
      aknLanguage (MkLangTag "he-IL")   `shouldBe` "heb"
      aknLanguage (MkLangTag "HE")      `shouldBe` "heb"
      aknLanguage (MkLangTag "he-Latn") `shouldBe` "heb"

    it "passes a subtag it does not know through, lowercased, rather than guessing" $ do
      -- Already three letters and already its own ISO code:
      aknLanguage (MkLangTag "ckb") `shouldBe` "ckb"
      aknLanguage (MkLangTag "syr") `shouldBe` "syr"
      -- Not in the table at all. Two letters where AKN wants three is wrong,
      -- but it names the language that was asked for, which the hard-coded
      -- `eng` it replaced did not.
      aknLanguage (MkLangTag "zz")  `shouldBe` "zz"
      aknLanguage (MkLangTag "ZZ")  `shouldBe` "zz"
