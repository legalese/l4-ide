{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | A literal percent sign in @\@nlg@ prose must not act as a reference delimiter.
--
-- @%@ opens and closes a natural-language reference, and annotation prose is full
-- of written-out percentages. Until the delimiters were made tight, the @%@ in
-- @5%@ would pair with the @%@ opening the next real reference, capture the word
-- between them as an identifier, and demote the intended reference to plain text.
-- See smucclaw\/l4-ide#957.
--
-- __Why here and not only in the corpus golden.__ @jl4\/examples\/ok\/nlg-percent.l4@
-- witnesses the loud half: when the captured word is not in scope the module stops
-- type-checking, so the golden moves. It cannot witness the quiet half. When the
-- captured word /is/ in scope the module type-checks either way, and no golden
-- records which name a reference binds to — the file would keep passing with the
-- annotation silently pointing at the wrong parameter. These tests read the parsed
-- fragments directly, so they pin the binding itself.
module NlgPercentSpec (spec) where

import Base

import L4.Nlg (unescapeNlgText)
import L4.Parser (PState (..), execParser, module')
import L4.Syntax (Nlg (..), NlgFragment (..), nameToText)
import Test.Hspec

-- | Every @\@nlg@ annotation in the source, in source order, reduced to the list
-- of names it references.
nlgRefs :: Text -> IO [[Text]]
nlgRefs src = do
  let uri = toNormalizedUri (Uri "file:///nlg-percent-spec")
  case execParser (module' uri) uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (_module, _warnings, pstate) ->
      -- 'addNlg' prepends, so the accumulated list is in reverse source order.
      pure (map refsOf (reverse pstate.nlgs))
 where
  -- The parser only ever mints 'MkParsedNlg' or 'MkInvalidNlg'; 'MkResolvedNlg'
  -- arrives later, from the type checker.
  refsOf :: Nlg -> [Text]
  refsOf = \ case
    MkParsedNlg _ frags -> [nameToText n | MkNlgRef _ n <- frags]
    MkResolvedNlg{}     -> []
    MkInvalidNlg{}      -> []

spec :: Spec
spec = describe "a literal % in @nlg prose is not a reference delimiter" $ do
  it "does not capture the following word when that word is not in scope" $ do
    refs <-
      nlgRefs
        "GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \@nlg 5% with %amount%\n\
        \DECIDE `over threshold` IF amount > 100\n"
    refs `shouldBe` [["amount"]]

  it "does not capture the following word when that word IS in scope" $ do
    -- The quiet case: before the fix this bound `rate`, type-checked clean, and
    -- left the author's `%amount%` as literal text.
    refs <-
      nlgRefs
        "GIVEN rate IS A NUMBER\n\
        \      amount IS A NUMBER\n\
        \GIVETH A NUMBER\n\
        \@nlg a 5% rate %amount%\n\
        \DECIDE `scaled amount` IS amount TIMES rate\n"
    refs `shouldBe` [["amount"]]

  it "does not capture a dotted word as a qualified name" $ do
    -- "5% p.a" is ordinary legal prose, and `p.a` parses as a qualified name.
    refs <-
      nlgRefs
        "GIVEN amount IS A NUMBER\n\
        \GIVETH A NUMBER\n\
        \@nlg interest at 5% p.a %amount%\n\
        \DECIDE accrued IS amount TIMES 2\n"
    refs `shouldBe` [["amount"]]

  it "treats spaces inside the delimiters as prose, not as a reference" $ do
    refs <-
      nlgRefs
        "GIVEN amount IS A NUMBER\n\
        \GIVETH A NUMBER\n\
        \@nlg % amount %\n\
        \DECIDE doubled IS amount TIMES 2\n"
    refs `shouldBe` [[]]

  it "still resolves a tight reference" $ do
    refs <-
      nlgRefs
        "GIVEN amount IS A NUMBER\n\
        \GIVETH A NUMBER\n\
        \@nlg %amount% doubled\n\
        \DECIDE doubled IS amount TIMES 2\n"
    refs `shouldBe` [["amount"]]

  it "still resolves two references in one annotation" $ do
    refs <-
      nlgRefs
        "GIVEN x IS A NUMBER\n\
        \      y IS A NUMBER\n\
        \GIVETH A NUMBER\n\
        \@nlg the greater of %x% and %y%\n\
        \DECIDE `the greater of` IS IF x >= y THEN x ELSE y\n"
    refs `shouldBe` [["x", "y"]]

  -- The residue the tightness rule above cannot reach: it keys on WHITESPACE,
  -- so a percent pair with none still captures. `10%and%20` is the shape.
  describe "a backslash escapes what tightness cannot" $ do
    it "does not capture a word between two ESCAPED percent signs" $ do
      refs <-
        nlgRefs
          "GIVEN n IS A NUMBER\n\
          \GIVETH A NUMBER\n\
          \@nlg between 10\\%and\\%20 for %n%\n\
          \DECIDE `the levy on` IS n TIMES 2\n"
      refs `shouldBe` [["n"]]

    it "shows the unescaped shape really does capture, so the test above bites" $ do
      -- The positive control. Without it, the previous test passes even if the
      -- escape did nothing and tightness had covered this all along.
      refs <-
        nlgRefs
          "GIVEN n IS A NUMBER\n\
          \GIVETH A NUMBER\n\
          \@nlg between 10%and%20 for %n%\n\
          \DECIDE `the levy on` IS n TIMES 2\n"
      refs `shouldBe` [["and", "n"]]

  describe "escapes decode once, at render time" $ do
    -- The lexer keeps `\%` and `\]` VERBATIM because that text is what
    -- 'displayTokenType' re-emits for exactprint. Decoding in the lexer made
    -- `l4 format` strip the backslash, which either broke the parse (`\]`) or
    -- silently changed the meaning (`\%`). So the decode lives here, and these
    -- pin it.
    it "decodes an escaped percent" $
      unescapeNlgText "10\\%and\\%20" `shouldBe` "10%and%20"

    it "decodes an escaped close bracket" $
      unescapeNlgText "a \\] literal" `shouldBe` "a ] literal"

    it "decodes an escaped backslash" $
      unescapeNlgText "a \\\\ backslash" `shouldBe` "a \\ backslash"

    it "leaves an unknown escape alone, so no existing annotation changes" $
      unescapeNlgText "unknown \\q kept" `shouldBe` "unknown \\q kept"

    it "leaves text with no backslash untouched" $
      unescapeNlgText "5% with nothing to decode"
        `shouldBe` "5% with nothing to decode"

    it "does not consume a trailing lone backslash" $
      unescapeNlgText "trailing \\" `shouldBe` "trailing \\"
