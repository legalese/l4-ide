{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

-- | Which node an @\@nlg@ annotation attaches to.
--
-- An annotation attaches to the name it FOLLOWS, and until this was fixed the
-- range algebra cut a name off at the start of its type — so the two shapes
-- authors write most landed on a TYPE and rendered nothing:
--
-- * @GIVEN a IS A STRING \@nlg …@ annotated @STRING@, not @a@;
-- * an @\@nlg@ on its own line above a @DECIDE@ annotated the @GIVETH@ type,
--   not the rule.
--
-- Neither produced a diagnostic, because the annotation HAD attached — to a
-- node nothing reads. The witness that makes the cost concrete is
-- @ok\/nlg-percent.l4@: the file whose entire purpose is to exercise @\@nlg@
-- had a @.nlg.golden@ showing bare names for all seven of its annotations,
-- green for as long as it had existed.
--
-- These pin the attachment TARGET rather than the rendered output, because
-- rendering only shows an annotation that some directive happens to reach — a
-- module can be entirely correct and entirely invisible to @l4 nlg@.
module NlgAttachmentSpec (spec) where

import Base

import L4.Annotation (getAnno)
import L4.Nlg (simpleLinearizer)
import L4.Parser (execProgramParserWithHintPass)
import L4.Parser.ResolveAnnotation (Warning (..))
import L4.Syntax (Module, Name, annNlg, nameToText)
import qualified Optics
import Test.Hspec

-- | Every name carrying an annotation, as @(name, what it says)@.
attachments :: Module Name -> [(Text, Text)]
attachments m =
  [ (nameToText n, simpleLinearizer nlg)
  | n <- Optics.toListOf (Optics.gplate @Name) m
  , Just nlg <- [view annNlg (getAnno n)]
  ]

parsed :: Text -> IO (Module Name, [Warning])
parsed src =
  case execProgramParserWithHintPass (toNormalizedUri (Uri "file:///nlg-attachment-spec")) src of
    Left errs -> do
      expectationFailure ("fixture source failed to parse: " <> show errs)
      error "unreachable"
    Right (m, _, ws) -> pure (m, ws)

spec :: Spec
spec = describe "which node an @nlg attaches to" $ do
  it "gives a trailing annotation to the PARAMETER, not to its type" $ do
    (m, _) <- parsed
      "GIVEN a IS A STRING @nlg the amount\n\
      \GIVETH A STRING\n\
      \DECIDE d IS a\n"
    attachments m `shouldBe` [("a", "the amount")]

  it "gives an annotation on its own line above a DECIDE to the RULE" $ do
    -- Not to the GIVETH type, which is the name it textually follows. This is
    -- the shape `ok/nlg-percent.l4` uses throughout.
    (m, _) <- parsed
      "GIVEN amount IS A NUMBER\n\
      \GIVETH A BOOLEAN\n\
      \@nlg 5% with %amount%\n\
      \DECIDE `over threshold` IF amount GREATER THAN 100\n"
    attachments m `shouldBe` [("over threshold", "5% with `amount`")]

  it "still gives it to the rule when there is no GIVETH to bound the GIVEN" $ do
    -- A GIVEN block's annotations are confined to the block. Without that, the
    -- last parameter claims everything up to the next node with a span, and
    -- with no GIVETH present that is the rule's own name — so the annotation
    -- landed on a parameter instead.
    (m, _) <- parsed
      "GIVEN n IS A NUMBER\n\
      \@nlg its own line\n\
      \DECIDE `twice` n IS n TIMES 2\n"
    attachments m `shouldBe` [("twice", "its own line")]

  it "gives a trailing annotation past a compound type to the parameter" $ do
    -- `ok/sort.l4` in the corpus: `[an already ordered list]` was landing on
    -- the type VARIABLE `a` rather than on the parameter it describes.
    (m, _) <- parsed
      "GIVEN a IS A TYPE\n\
      \      list IS A LIST OF a [an already ordered list]\n\
      \GIVETH A LIST OF a\n\
      \DECIDE `sorted` IS list\n"
    attachments m `shouldBe` [("list", "an already ordered list")]

  -- The narrowing, and the reason for it. A RECORD FIELD may carry two
  -- annotations on one line — one for the field, one for its type — and
  -- `ok/nlg_declare1.l4` does exactly that on purpose. Letting the field's
  -- name claim the whole line makes them collide, and multiplicity then
  -- correctly refuses both, so the "repair" would delete working annotations.
  -- Record fields therefore keep the old behaviour.
  it "leaves a record field's two annotations attached separately" $ do
    (m, ws) <- parsed
      "DECLARE List [The List] OF a [Elements]\n\
      \  IS ONE OF\n\
      \    Nil [Empty Case]\n\
      \    Cons [Followed By] HAS\n\
      \      head [Get First Element] IS AN a [Start Element]\n"
    attachments m
      `shouldBe` [ ("List", "The List")
                 , ("a", "Elements")
                 , ("Nil", "Empty Case")
                 , ("Cons", "Followed By")
                 , ("head", "Get First Element")
                 , ("a", "Start Element")
                 ]
    [ () | Ambiguous{} <- ws ] `shouldBe` []

  -- An annotation with no prose is DROPPED, not attached. A rendering replaces
  -- the thing it annotates, so an empty one erases the name from the output.
  -- Three of these sit in `ok/contract.l4` and were invisible only because
  -- they used to land on the type; repairing the attachment moved them onto
  -- the parameters and blanked all three names.
  it "drops an empty @nlg rather than blanking the name, and says so" $ do
    (m, ws) <- parsed
      "GIVEN `the buyer` IS A STRING @nlg\n\
      \GIVETH A STRING\n\
      \DECIDE who IS `the buyer`\n"
    attachments m `shouldBe` []
    [ nameToText n | EmptyNlg n _ <- ws ] `shouldBe` ["the buyer"]

  -- The one exception to "own line describes what follows", ruled 2026-09-19.
  -- A field list is a column of things rather than a sequence of
  -- declarations, and an annotation written UNDERNEATH a field describes that
  -- field. All three independently generated Hebrew encodings measured in
  -- 2026-09 annotate fields this way — 100 heralds, every one below its field
  -- — so it is the shape authors actually reach for.
  --
  -- These carry the whole ruling on their own: our corpus contains
  -- essentially none of this shape, so no golden moves and nothing else in
  -- the suite would notice if it regressed.
  describe "inside a field list, an annotation on its own line describes the field ABOVE" $ do
    it "attaches to the field above, not to its type and not to the next field" $ do
      (m, ws) <- parsed
        "DECLARE Employee\n\
        \  HAS `full name`  IS A STRING\n\
        \      @nlg the employee's full name\n\
        \      `start date` IS A DATE\n"
      attachments m `shouldBe` [("full name", "the employee's full name")]
      [ () | EmptyNlg{} <- ws ] `shouldBe` []

    it "still gives a field and its TYPE separate trailing glosses" $ do
      -- `ok/nlg_declare1.l4`. This is why the field name claims two disjoint
      -- regions rather than simply everything: before its type (its own
      -- trailing gloss) and below its line. What falls between — trailing the
      -- TYPE on the field's own line — stays with the type. Giving the name
      -- the whole line instead makes these two collide and loses both.
      (m, ws) <- parsed
        "DECLARE List [The List] OF a [Elements]\n\
        \  IS ONE OF\n\
        \    Nil [Empty Case]\n\
        \    Cons [Followed By] HAS\n\
        \      head [Get First Element] IS AN a [Start Element]\n"
      attachments m
        `shouldBe` [ ("List", "The List")
                   , ("a", "Elements")
                   , ("Nil", "Empty Case")
                   , ("Cons", "Followed By")
                   , ("head", "Get First Element")
                   , ("a", "Start Element")
                   ]
      [ () | Ambiguous{} <- ws ] `shouldBe` []

    it "handles both shapes on adjacent fields without either stealing the other" $ do
      (m, ws) <- parsed
        "DECLARE Employee\n\
        \  HAS `full name` [the name] IS A STRING\n\
        \      `start date` IS A DATE\n\
        \      @nlg when they started\n"
      attachments m
        `shouldBe` [("full name", "the name"), ("start date", "when they started")]
      [ () | Ambiguous{} <- ws ] `shouldBe` []

    it "does NOT change the rule case: own line above a DECIDE still means the rule" $ do
      -- The exception is scoped to field lists. Stated as a test because the
      -- two conventions point in opposite directions and a later edit that
      -- "unified" them would silently break one of the two.
      (m, _) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \@nlg 5% with %amount%\n\
        \DECIDE `over threshold` IF amount GREATER THAN 100\n"
      attachments m `shouldBe` [("over threshold", "5% with `amount`")]
