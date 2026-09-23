{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | "L4.SmartPunctuation" — the confusables table, the dash heuristic, and
-- 'L4.Lexer.straightenDocument's fixed-point repair, exercised with the
-- REAL lexer as oracle (never a stub), per CLAUDE.md's own instruction for
-- that function.
--
-- The probe module below is the one quoted in the smart-punctuation design
-- (DUMBWAITER): a Word-smartified copy of a tiny L4 module whose ASCII
-- original evaluates. It carries all four confusable families the design
-- distinguishes — a genitive apostrophe, a comment-starting dash, and a pair
-- of curly double quotes — in one file, so 'straightenDocument' has to walk
-- its fixed point more than once, which a single-character fixture would
-- not exercise.
module SmartPunctuationSpec (spec) where

import Base
import qualified Base.Text as Text

import L4.Lexer (straightenDocument)
import L4.Parser.SrcSpan
import L4.SmartPunctuation

import Test.Hspec

specUri :: NormalizedUri
specUri = toNormalizedUri (Uri "file:///smart-punctuation-spec")

-- | The Word-smartified probe (the one quoted in the design): a genitive
-- apostrophe as U+2019, a comment dash as U+2013 (preceded by three spaces,
-- so it is comment-shaped), and a curly-quoted string as U+201C/U+201D.
probeSmart :: Text
probeSmart = Text.unlines
  [ "DECLARE Person"
  , "  HAS name IS A STRING"
  , "      age  IS A NUMBER"
  , ""
  , "GIVEN p IS A Person"
  , "DECIDE `is adult` IF p\x2019s age >= 18   \x2013 plain comment"
  , ""
  , "#EVAL `is adult` (Person WITH name IS \x201C\&Alice\x201D, age IS 30)"
  ]

-- | The ASCII original 'probeSmart' straightens to.
probeAscii :: Text
probeAscii = Text.unlines
  [ "DECLARE Person"
  , "  HAS name IS A STRING"
  , "      age  IS A NUMBER"
  , ""
  , "GIVEN p IS A Person"
  , "DECIDE `is adult` IF p's age >= 18   -- plain comment"
  , ""
  , "#EVAL `is adult` (Person WITH name IS \"Alice\", age IS 30)"
  ]

spec :: Spec
spec = do
  describe "the confusables table" $ do
    it "maps every curly single quote to a straight apostrophe" $ do
      for_ ['\x2018', '\x2019', '\x201A', '\x201B'] $ \c ->
        fmap (.replacement) (lookupConfusable c) `shouldBe` Just "'"

    it "maps every curly double quote to a straight double quote" $ do
      for_ ['\x201C', '\x201D', '\x201E', '\x201F'] $ \c ->
        fmap (.replacement) (lookupConfusable c) `shouldBe` Just "\""

    it "maps en dash, em dash and non-breaking hyphen to a hyphen-minus" $ do
      for_ ['\x2013', '\x2014', '\x2011'] $ \c ->
        fmap (.replacement) (lookupConfusable c) `shouldBe` Just "-"

    it "offers `--` as the alternative spelling for en and em dash only" $ do
      fmap (.altReplacement) (lookupConfusable '\x2013') `shouldSatisfy` \case
        Just (Just (alt, _)) -> alt == "--"
        _ -> False
      fmap (.altReplacement) (lookupConfusable '\x2011') `shouldBe` Just Nothing

    it "maps horizontal ellipsis to three dots" $
      fmap (.replacement) (lookupConfusable '\x2026') `shouldBe` Just "..."

    it "maps no-break space to an ordinary space" $
      fmap (.replacement) (lookupConfusable '\x00A0') `shouldBe` Just " "

    it "recognises no other character as a confusable" $
      for_ ['a', '\'', '"', '-', '.', ' ', '\n'] $ \c ->
        lookupConfusable c `shouldBe` Nothing

    it "names the Unicode code point the way rustc/swiftc do (U+XXXX, upper case)" $
      codePointText '\x2019' `shouldBe` "U+2019"

    it "names the glyph in its message, along with the ASCII character it looks like" $ do
      Just c <- pure (lookupConfusable '\x2019')
      let msg = confusableMessage c
      msg `shouldSatisfy` Text.isInfixOf "Right Single Quotation Mark"
      msg `shouldSatisfy` Text.isInfixOf "U+2019"
      msg `shouldSatisfy` Text.isInfixOf "word processor"
      msg `shouldNotSatisfy` Text.isInfixOf "expecting"

  describe "the dash heuristic (dashReplacementFor)" $ do
    let enDash = fromMaybe (error "U+2013 must be a confusable") (lookupConfusable '\x2013')

    it "is comment-shaped at the start of a line" $
      dashReplacementFor "" enDash `shouldBe` "--"

    it "is comment-shaped after two or more spaces" $
      dashReplacementFor "foo  " enDash `shouldBe` "--"

    it "is arithmetic-shaped after a single space (a normal ` - ` subtraction)" $
      dashReplacementFor "3 " enDash `shouldBe` "-"

    it "is arithmetic-shaped with no space at all before it" $
      dashReplacementFor "3" enDash `shouldBe` "-"

    it "a non-dash confusable ignores the line context entirely" $ do
      Just curly <- pure (lookupConfusable '\x2019')
      dashReplacementFor "anything at all" curly `shouldBe` "'"

  describe "straightenChars (used both directions by the did-you-mean fix)" $ do
    it "leaves an already-ASCII identifier untouched" $
      straightenChars "testator's estate" `shouldBe` "testator's estate"

    it "straightens a curly apostrophe to match the straight spelling" $
      straightenChars "testator\x2019s estate" `shouldBe` "testator's estate"

  describe "straightenDocument (real lexer as oracle)" $ do
    it "is a positive control: an ASCII-clean document is returned unchanged, with count 0" $ do
      straightenDocument specUri probeAscii `shouldBe` (0, probeAscii)

    it "straightens the Word-smartified probe back to its ASCII original" $ do
      let (n, final) = straightenDocument specUri probeSmart
      final `shouldBe` probeAscii
      n `shouldBe` 4  -- the genitive apostrophe, the comment dash, and the two curly quotes

    it "replaces a no-break space used as ordinary whitespace" $ do
      let src = "GIVEN\x00A0p IS A Person\n"
          expected = "GIVEN p IS A Person\n"
      straightenDocument specUri src `shouldBe` (1, expected)

  describe "nbspHitsInToken (the NBSP lint's pure scan)" $ do
    it "finds nothing in ordinary whitespace" $
      nbspHitsInToken specUri (MkSrcPos 1 1) "   " `shouldBe` []

    it "reports each no-break space at its own length-1 range" $ do
      let hits = nbspHitsInToken specUri (MkSrcPos 3 5) "\x00A0\x00A0"
      length hits `shouldBe` 2
      map (\r -> (r.start.column, r.end.column)) hits `shouldBe` [(5, 6), (6, 7)]
