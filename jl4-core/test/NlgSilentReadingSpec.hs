{-# LANGUAGE OverloadedStrings #-}

-- | Two ways an @\@nlg@ annotation could be read differently from how it was
-- written, with no message: a percent pair with spaces inside it
-- (@% amount %@, which is plain text and not a slot), and a language tag that
-- is really the first word of a sentence (@\@nlg:the employee pays@).
--
-- Both are now warnings. These pin what draws one and, just as much, what does
-- not: a translation added one rule at a time, a module that declares its
-- language, and a literal percent sign in prose are all the feature in use.
module NlgSilentReadingSpec (spec) where

import Base

import L4.Lexer (LangTag (..))
import L4.Parser (execProgramParserWithHintPass, spacedSlotsIn)
import L4.Parser.ResolveAnnotation (Warning (..), WithSpan (..))
import L4.Syntax (nameToText, nlgLangTag)
import Test.Hspec

warningsOf :: Text -> IO [Warning]
warningsOf src =
  case execProgramParserWithHintPass (toNormalizedUri (Uri "file:///nlg-silent-reading-spec")) src of
    Left errs -> do
      expectationFailure ("fixture source failed to parse: " <> show errs)
      error "unreachable"
    Right (_, _, ws) -> pure ws

-- | The lone tags a parse reports, each as @(the name it is on, the tag)@.
lone :: [Warning] -> [(Text, Text)]
lone ws =
  [ (nameToText name, tag)
  | LoneLangTag name nlg <- ws
  , Just (MkLangTag tag) <- [nlgLangTag nlg.payload]
  ]

-- | The spaced percent pairs a parse reports, each as @(the pair, the name)@.
spaced :: [Warning] -> [(Text, Text)]
spaced ws = [ (written.payload, name) | SpacedSlot written name <- ws ]

-- | A rule with one wording, and the line that wording is written on.
withHerald :: Text -> Text
withHerald herald =
  "GIVEN amount IS A NUMBER\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE `over limit` " <> herald <> "\n\
  \  IF amount GREATER THAN 100\n"

spec :: Spec
spec = describe "an annotation read differently from how it was written" $ do
  describe "a percent pair with spaces inside it" $ do
    describe "spacedSlotsIn" $ do
      it "finds a pair with a space on each side of the name" $
        spacedSlotsIn "the claim of % amount % is large" `shouldBe` [("% amount %", "amount")]

      it "finds a pair with a space on one side only" $ do
        spacedSlotsIn "of %amount % x" `shouldBe` [("%amount %", "amount")]
        spacedSlotsIn "of % amount% x" `shouldBe` [("% amount%", "amount")]

      it "does not report a pair whose closing sign runs into a word" $
        spacedSlotsIn "of % amount%x" `shouldBe` []

      it "finds a pair around a quoted name" $
        spacedSlotsIn "of % `full name` % x" `shouldBe` [("% `full name` %", "`full name`")]

      it "leaves a tight slot alone" $
        spacedSlotsIn "the claim of %amount% is large" `shouldBe` []

      it "leaves a literal percent sign beside a slot alone" $ do
        spacedSlotsIn "a 5% levy on %amount%" `shouldBe` []
        spacedSlotsIn "5% with %amount%" `shouldBe` []
        spacedSlotsIn "a 5% rate %amount%" `shouldBe` []

      it "does not pair a tight slot's signs with a neighbour" $
        spacedSlotsIn "%a% x % b %" `shouldBe` [("% b %", "b")]

      it "skips an escaped percent sign" $ do
        spacedSlotsIn "5\\% amount \\%" `shouldBe` []
        spacedSlotsIn "5\\% of % amount %" `shouldBe` [("% amount %", "amount")]

      it "finds nothing in plain prose" $ do
        spacedSlotsIn "" `shouldBe` []
        spacedSlotsIn "no signs here" `shouldBe` []
        spacedSlotsIn "100 % of the total" `shouldBe` []

    it "warns on a trailing annotation, naming the pair and the slot to write" $ do
      ws <- warningsOf (withHerald "@nlg the claim of % amount % is over the limit")
      spaced ws `shouldBe` [("% amount %", "amount")]

    it "warns on the bracket form" $ do
      ws <- warningsOf (withHerald "[the claim of % amount % is over the limit]")
      spaced ws `shouldBe` [("% amount %", "amount")]

    it "warns even when the word is not in scope" $ do
      ws <- warningsOf (withHerald "@nlg the claim of % nosuchname % is over the limit")
      spaced ws `shouldBe` [("% nosuchname %", "nosuchname")]

    it "is silent on a tight slot" $ do
      ws <- warningsOf (withHerald "@nlg the claim of %amount% is over the limit")
      spaced ws `shouldBe` []

    it "is silent on a literal percent sign before a slot" $ do
      ws <- warningsOf (withHerald "@nlg a 5% levy on %amount%")
      spaced ws `shouldBe` []

  describe "a language tag that nothing else in the module backs" $ do
    describe "is reported" $ do
      it "for a lone tag that is the first word of a sentence" $ do
        ws <- warningsOf (withHerald "@nlg:the claim of %amount% is over the limit")
        lone ws `shouldBe` [("over limit", "the")]

      it "for a lone tag that is not a language at all" $ do
        ws <- warningsOf (withHerald "@nlg:xyz the claim of %amount% is over the limit")
        lone ws `shouldBe` [("over limit", "xyz")]

      it "for a lone tag in a module that declares a different language" $ do
        ws <- warningsOf ("@lang he\n" <> withHerald "@nlg:the claim of %amount% is over the limit")
        lone ws `shouldBe` [("over limit", "the")]

      it "for a tag that opens like English or Hebrew but is another language" $ do
        ws <- warningsOf (withHerald "@nlg:hei the claim is over the limit")
        lone ws `shouldBe` [("over limit", "hei")]
        ws' <- warningsOf (withHerald "@nlg:zh-Hant the claim is over the limit")
        lone ws' `shouldBe` [("over limit", "zh-Hant")]
        forM_ ["english", "enx", "heb"] $ \ tag -> do
          ws'' <- warningsOf (withHerald ("@nlg:" <> tag <> " the claim is over the limit"))
          lone ws'' `shouldBe` [("over limit", tag)]

      it "for a tag that differs from the declared one only in case" $ do
        ws <- warningsOf ("@lang fr\n" <> withHerald "@nlg:FR le montant")
        lone ws `shouldBe` [("over limit", "FR")]

      it "per name: an input's lone wording draws one even when the rule has others" $ do
        ws <- warningsOf
          "GIVEN amount IS A NUMBER @nlg:the amount\n\
          \GIVETH A BOOLEAN\n\
          \DECIDE `over limit` @nlg the claim is over the limit\n\
          \  IF amount GREATER THAN 100\n"
        lone ws `shouldBe` [("amount", "the")]

    describe "is not reported" $ do
      it "when the rule has a wording in another language too" $ do
        ws <- warningsOf
          "GIVEN amount IS A NUMBER\n\
          \GIVETH A BOOLEAN\n\
          \DECIDE `over limit` @nlg the claim is over the limit\n\
          \                    @nlg:fr la demande dépasse la limite\n\
          \  IF amount GREATER THAN 100\n"
        lone ws `shouldBe` []

      it "when the module declares the language" $ do
        ws <- warningsOf ("@lang fr\n" <> withHerald "@nlg:fr la demande dépasse la limite")
        lone ws `shouldBe` []

      it "when another rule carries the same tag" $ do
        ws <- warningsOf
          "GIVEN amount IS A NUMBER\n\
          \GIVETH A BOOLEAN\n\
          \DECIDE `over limit` @nlg:fr la demande dépasse la limite\n\
          \  IF amount GREATER THAN 100\n\
          \\n\
          \GIVEN amount IS A NUMBER\n\
          \GIVETH A BOOLEAN\n\
          \DECIDE `under limit` @nlg:fr la demande reste sous la limite\n\
          \  IF amount LESS THAN 100\n"
        lone ws `shouldBe` []

      it "for Hebrew, which L4 gives meaning to" $ do
        ws <- warningsOf (withHerald "@nlg:he %amount% עולה על הסף")
        lone ws `shouldBe` []

      it "for English, in any case" $ do
        ws <- warningsOf (withHerald "@nlg:en the claim is over the limit")
        lone ws `shouldBe` []
        ws' <- warningsOf (withHerald "@nlg:EN the claim is over the limit")
        lone ws' `shouldBe` []

      it "for English or Hebrew with a region or script, such as en-GB or he-IL" $ do
        forM_ ["en-GB", "EN-gb", "he-IL", "he-Latn"] $ \ tag -> do
          ws <- warningsOf (withHerald ("@nlg:" <> tag <> " the claim is over the limit"))
          lone ws `shouldBe` []

      it "for a colon with a space after it, which is not a tag" $ do
        ws <- warningsOf (withHerald "@nlg: see below %amount%")
        lone ws `shouldBe` []

      it "for an untagged annotation" $ do
        ws <- warningsOf (withHerald "@nlg the claim of %amount% is over the limit")
        lone ws `shouldBe` []
