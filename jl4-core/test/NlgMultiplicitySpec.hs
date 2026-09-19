{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

-- | More than one @\@nlg@ rendering per name, partitioned by language.
--
-- Before this, ANY two annotations on one name were an ambiguity and neither
-- attached. That is the right answer when both are renderings of the same
-- node in the same language; it is the wrong answer the moment one of them
-- says @\@nlg:he@, because a bilingual document is exactly a document with two
-- renderings per name — so every annotated name in one lost BOTH. The tag was
-- recognised, round-tripped, and then had nowhere to go.
--
-- These pin the four cases that decide whether a bilingual document is
-- representable at all, plus the backward-compatibility one that lets the ~28
-- existing readers of 'annNlg' go on not knowing tags exist.
module NlgMultiplicitySpec (spec) where

import Base

import L4.Annotation (getAnno)
import L4.Lexer (LangTag (..))
import L4.Nlg (simpleLinearizer)
import L4.Parser (execProgramParserWithHintPass)
import L4.Parser.ResolveAnnotation (Warning (..))
import L4.Syntax
  ( Module
  , Name
  , annNlg
  , annNlgAlts
  , nameToText
  , nlgFor
  , nlgLangTag
  )
import qualified Optics
import Test.Hspec

-- | The renderings attached to one named node: the default first, then the
-- alternatives, each as @(language, what it says)@ with @\"-\"@ for untagged.
renderingsOf :: Text -> Module Name -> [(Text, Text)]
renderingsOf wanted m =
  [ row r
  | n <- Optics.toListOf (Optics.gplate @Name) m
  , nameToText n == wanted
  , r <- toList (view annNlg (getAnno n)) <> view annNlgAlts (getAnno n)
  ]
 where
  row r = (maybe "-" (\ (MkLangTag t) -> t) (nlgLangTag r), simpleLinearizer r)

-- | What a caller asking for a particular language gets for one named node.
selectedFor :: Text -> Maybe Text -> Module Name -> Maybe Text
selectedFor wanted lang m =
  listToMaybe
    [ simpleLinearizer r
    | n <- Optics.toListOf (Optics.gplate @Name) m
    , nameToText n == wanted
    , Just r <- [nlgFor (MkLangTag <$> lang) (getAnno n)]
    ]

parsed :: Text -> IO (Module Name, [Warning])
parsed src = do
  let uri = toNormalizedUri (Uri "file:///nlg-multiplicity-spec")
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure ("fixture source failed to parse: " <> show errs)
      error "unreachable"
    Right (m, _hints, ws) -> pure (m, ws)

ambiguities :: [Warning] -> [Maybe Text]
ambiguities ws = [ fmap (\ (MkLangTag t) -> t) mtag | Ambiguous _ mtag _ <- ws ]

-- | Two renderings of one rule, written the way an author writes them: the
-- second herald on the continuation line under the first.
bilingual :: Text
bilingual =
  "GIVEN amount IS A NUMBER\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE `is large` @nlg:en the amount is large\n\
  \                  @nlg:he ha-sechum gadol\n\
  \  IF amount > 100\n"

spec :: Spec
spec = describe "two @nlg renderings on one name, partitioned by language" $ do
  it "attaches BOTH when their languages differ" $ do
    (m, ws) <- parsed bilingual
    renderingsOf "is large" m
      `shouldBe` [("en", "the amount is large"), ("he", "ha-sechum gadol")]
    ambiguities ws `shouldBe` []

  it "selects by language, and falls back to the default for one it lacks" $ do
    (m, _) <- parsed bilingual
    selectedFor "is large" (Just "he") m `shouldBe` Just "ha-sechum gadol"
    selectedFor "is large" (Just "en") m `shouldBe` Just "the amount is large"
    -- Falling back rather than returning nothing is deliberate: a partial
    -- translation should render the document's own wording for the rules it
    -- has not reached yet, not a hole.
    selectedFor "is large" (Just "fr") m `shouldBe` Just "the amount is large"
    selectedFor "is large" Nothing m `shouldBe` Just "the amount is large"

  -- Which one is the DEFAULT. An untagged rendering carries the MODULE's
  -- language — its `@lang`, or `en` when it declares none (R-M2) — so in a
  -- module with no declaration the untagged one is the `en` one, and that is
  -- what a caller who named no language gets, whichever side of the tagged
  -- one it was written on.
  describe "the untagged rendering is the default wherever it is written" $ do
    it "when it comes first" $ do
      (m, ws) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` @nlg the plain wording\n\
        \                  @nlg:he ha-sechum gadol\n\
        \  IF amount > 100\n"
      -- "en", not "-": the untagged annotation was stamped with the
      -- module's language, which is `en` here because nothing declared one.
      renderingsOf "is large" m
        `shouldBe` [("en", "the plain wording"), ("he", "ha-sechum gadol")]
      ambiguities ws `shouldBe` []

    it "when it comes second" $ do
      (m, ws) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` @nlg:he ha-sechum gadol\n\
        \                  @nlg the plain wording\n\
        \  IF amount > 100\n"
      -- "en", not "-": the untagged annotation was stamped with the
      -- module's language, which is `en` here because nothing declared one.
      renderingsOf "is large" m
        `shouldBe` [("en", "the plain wording"), ("he", "ha-sechum gadol")]
      ambiguities ws `shouldBe` []

  -- The behaviour that must NOT change, and the reason the tag is not simply
  -- ignored: two renderings that both claim the same language really are
  -- ambiguous, and picking one would silently discard an author's sentence.
  describe "a genuine same-language collision still warns and attaches neither" $ do
    it "two untagged annotations — the only shape that existed before" $ do
      (m, ws) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` @nlg one wording\n\
        \                  @nlg another wording\n\
        \  IF amount > 100\n"
      renderingsOf "is large" m `shouldBe` []
      -- Reported against `en`, because that is what an untagged annotation
      -- means in a module that declares no `@lang`. Two untagged annotations
      -- are two `en` ones, which is why they still collide.
      ambiguities ws `shouldBe` [Just "en"]

    it "two annotations sharing a tag" $ do
      (m, ws) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` @nlg:he one wording\n\
        \                  @nlg:he another wording\n\
        \  IF amount > 100\n"
      renderingsOf "is large" m `shouldBe` []
      ambiguities ws `shouldBe` [Just "he"]

  it "a collision in one language does not poison the others" $ do
    (m, ws) <- parsed
      "GIVEN amount IS A NUMBER\n\
      \GIVETH A BOOLEAN\n\
      \DECIDE `is large` @nlg:he one wording\n\
      \                  @nlg:he another wording\n\
      \                  @nlg:en the amount is large\n\
      \  IF amount > 100\n"
    renderingsOf "is large" m `shouldBe` [("en", "the amount is large")]
    ambiguities ws `shouldBe` [Just "he"]

  -- The compatibility hinge. Every existing reader asks 'annNlg' and knows
  -- nothing about tags; if a lone tagged annotation went to the alternatives
  -- list, a monolingual Hebrew document would render as nothing at all.
  it "a lone TAGGED annotation is the default, so old readers still find it" $ do
    (m, ws) <- parsed
      "GIVEN amount IS A NUMBER\n\
      \GIVETH A BOOLEAN\n\
      \DECIDE `is large` @nlg:he ha-sechum gadol\n\
      \  IF amount > 100\n"
    renderingsOf "is large" m `shouldBe` [("he", "ha-sechum gadol")]
    selectedFor "is large" Nothing m `shouldBe` Just "ha-sechum gadol"
    ambiguities ws `shouldBe` []

  -- This used to assert the OPPOSITE, and the change is the point. A herald on
  -- its own line above a DECIDE went to the last name before it — the GIVETH's
  -- `BOOLEAN` — so it rendered nowhere at all. With attachment fixed the two
  -- renderings meet on the rule, and a bilingual pair can be written either
  -- way round: one above the DECIDE and one trailing its name, or both on
  -- continuation lines as the fixtures above do.
  it "a herald above the DECIDE now reaches the rule, and pairs with a trailing one" $ do
    (m, ws) <- parsed
      "GIVEN amount IS A NUMBER\n\
      \GIVETH A BOOLEAN\n\
      \@nlg:he ha-sechum gadol\n\
      \DECIDE `is large` @nlg:en the amount is large\n\
      \  IF amount > 100\n"
    -- `en` first because it is the DEFAULT: the module declares no `@lang`, so
    -- its language is `en` (R-M2) and `pickDefault` prefers the module's own
    -- language over source order. The `he` rendering is the alternative.
    renderingsOf "is large" m
      `shouldBe` [("en", "the amount is large"), ("he", "ha-sechum gadol")]
    renderingsOf "BOOLEAN" m `shouldBe` []
    ambiguities ws `shouldBe` []

  ----------------------------------------------------------------------------
  -- `@lang he` — the module's own language (R-M2, Meng 2026-09-17).
  --
  -- The rule it encodes is "an untagged @nlg in this module is written in
  -- THIS language", so `@lang he` means exactly what tagging every herald
  -- `:he` would mean. Meng's stated preference is one declaration per module
  -- over a tag per herald, which only holds if the two are genuinely the same
  -- thing — so that equivalence is what these test, rather than the
  -- declaration merely being recorded somewhere.
  ----------------------------------------------------------------------------
  describe "@lang declares what an untagged @nlg means" $ do
    it "makes an untagged rendering the module's language" $ do
      (m, ws) <- parsed
        "@lang he\n\
        \GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` @nlg ha-sechum gadol\n\
        \  IF amount GREATER THAN 100\n"
      renderingsOf "is large" m `shouldBe` [("he", "ha-sechum gadol")]
      selectedFor "is large" (Just "he") m `shouldBe` Just "ha-sechum gadol"
      ambiguities ws `shouldBe` []

    it "is equivalent to tagging the herald" $ do
      -- The claim that justifies preferring one declaration to 56 tags.
      (declared, _) <- parsed
        "@lang he\n\
        \GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` @nlg ha-sechum gadol\n\
        \  IF amount GREATER THAN 100\n"
      (tagged, _) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` @nlg:he ha-sechum gadol\n\
        \  IF amount GREATER THAN 100\n"
      renderingsOf "is large" declared `shouldBe` renderingsOf "is large" tagged

    it "lets an explicitly tagged herald differ, and that herald wins for its language" $ do
      (m, ws) <- parsed
        "@lang he\n\
        \GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` @nlg ha-sechum gadol\n\
        \                  @nlg:en the amount is large\n\
        \  IF amount GREATER THAN 100\n"
      ambiguities ws `shouldBe` []
      selectedFor "is large" (Just "en") m `shouldBe` Just "the amount is large"
      selectedFor "is large" (Just "he") m `shouldBe` Just "ha-sechum gadol"
      -- The default is the MODULE's language, not the first line.
      selectedFor "is large" Nothing m `shouldBe` Just "ha-sechum gadol"

    it "applies to annotations written ABOVE the declaration" $ do
      -- Order-independence is a design choice, not an accident: the stamping
      -- happens after parsing, over the whole module, so a declaration at the
      -- bottom of a long file still governs the top of it. A parse-time
      -- implementation would silently leave earlier annotations untagged.
      (m, _) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` @nlg ha-sechum gadol\n\
        \  IF amount GREATER THAN 100\n\
        \@lang he\n"
      renderingsOf "is large" m `shouldBe` [("he", "ha-sechum gadol")]

    it "defaults to en when the module declares nothing" $ do
      (m, _) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` @nlg the amount is large\n\
        \  IF amount GREATER THAN 100\n"
      renderingsOf "is large" m `shouldBe` [("en", "the amount is large")]

    it "collides when a herald repeats the module's own language" $ do
      -- `@lang he` plus an explicit `@nlg:he` on the same name is two Hebrew
      -- renderings, which is the ambiguity the per-language rule exists to
      -- keep catching. Nothing about the declaration should smuggle a second
      -- one past it.
      (m, ws) <- parsed
        "@lang he\n\
        \GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` @nlg ha-sechum gadol\n\
        \                  @nlg:he nusach acher\n\
        \  IF amount GREATER THAN 100\n"
      renderingsOf "is large" m `shouldBe` []
      ambiguities ws `shouldBe` [Just "he"]
