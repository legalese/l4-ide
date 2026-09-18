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

  -- Which one is the DEFAULT. An untagged rendering declined to name a
  -- language, so it is what a caller who did not name one should get —
  -- whichever side of the tagged one it was written on.
  describe "the untagged rendering is the default wherever it is written" $ do
    it "when it comes first" $ do
      (m, ws) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` @nlg the plain wording\n\
        \                  @nlg:he ha-sechum gadol\n\
        \  IF amount > 100\n"
      renderingsOf "is large" m
        `shouldBe` [("-", "the plain wording"), ("he", "ha-sechum gadol")]
      ambiguities ws `shouldBe` []

    it "when it comes second" $ do
      (m, ws) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` @nlg:he ha-sechum gadol\n\
        \                  @nlg the plain wording\n\
        \  IF amount > 100\n"
      renderingsOf "is large" m
        `shouldBe` [("-", "the plain wording"), ("he", "ha-sechum gadol")]
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
      ambiguities ws `shouldBe` [Nothing]

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

  -- Documented because it surprises: a herald on its own line ABOVE a DECIDE
  -- does not reach the rule's name. It attaches to the last name before it —
  -- here the GIVETH's `BOOLEAN` — which is pre-existing range-based
  -- attachment and not something multiplicity changed. Write the second
  -- rendering on the continuation line instead, as the fixtures above do.
  it "a herald above the DECIDE attaches to the preceding name, not the rule" $ do
    (m, _) <- parsed
      "GIVEN amount IS A NUMBER\n\
      \GIVETH A BOOLEAN\n\
      \@nlg:he ha-sechum gadol\n\
      \DECIDE `is large` @nlg:en the amount is large\n\
      \  IF amount > 100\n"
    renderingsOf "is large" m `shouldBe` [("en", "the amount is large")]
    renderingsOf "BOOLEAN" m `shouldBe` [("he", "ha-sechum gadol")]
