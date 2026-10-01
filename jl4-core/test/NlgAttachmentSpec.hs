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
    -- An annotation at the GIVEN keyword's column is not the last input's.
    -- Without that, the last parameter claims everything up to the next node
    -- with a span, and with no GIVETH present that is the rule's own name — so
    -- the annotation landed on a parameter instead. Indented past the keyword,
    -- it IS the parameter's; see the GIVEN-list cases below.
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

  -- The first exception to "own line describes what follows", ruled 2026-09-19.
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
      -- The exception is scoped to field lists and GIVEN lists. Stated as a
      -- test because the two conventions point in opposite directions and a
      -- later edit that "unified" them would silently break one of the two.
      (m, _) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \@nlg 5% with %amount%\n\
        \DECIDE `over threshold` IF amount GREATER THAN 100\n"
      attachments m `shouldBe` [("over threshold", "5% with `amount`")]

  -- The second exception, ruled 2026-10-02 (Meng): a GIVEN list is a column
  -- too, so an annotation on its own line under an input describes that input
  -- — the LAST input included. The slot under the last input is also the slot
  -- above the rule when no GIVETH intervenes, so the tie-break is the GIVEN
  -- keyword's column: indented further, the input; at it or left of it, what
  -- follows. The keyword's column rather than column 1, so that a GIVEN under a
  -- section heading or inside a WHERE reads the same way.
  describe "inside a GIVEN list, an annotation on its own line describes the input ABOVE" $ do
    it "attaches to the last input when a GIVETH follows" $ do
      (m, ws) <- parsed
        "GIVEN floor  IS A NUMBER\n\
        \      amount IS A NUMBER\n\
        \      @nlg the sum of money\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` IF amount GREATER THAN floor\n"
      attachments m `shouldBe` [("amount", "the sum of money")]
      [ () | NotAttached{} <- ws ] `shouldBe` []

    it "leaves one at the GIVEN keyword's column unattached when a GIVETH follows, as before" $ do
      -- The column test decides between the input and what follows; with a
      -- GIVETH in between, what follows takes nothing, so it warns.
      (m, ws) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \@nlg at the margin\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` IF amount GREATER THAN 100\n"
      attachments m `shouldBe` []
      [ () | NotAttached{} <- ws ] `shouldSatisfy` (not . null)

    it "attaches to the last input, not the rule, when no GIVETH follows" $ do
      (m, _) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \      @nlg the sum of money\n\
        \DECIDE `is large` IF amount GREATER THAN 100\n"
      attachments m `shouldBe` [("amount", "the sum of money")]

    it "splits an indented and an unindented annotation between the input and the rule" $ do
      (m, ws) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \      @nlg the sum of money\n\
        \@nlg the claim of %amount% is large\n\
        \DECIDE `is large` IF amount GREATER THAN 100\n"
      attachments m
        `shouldBe` [ ("amount", "the sum of money")
                   , ("is large", "the claim of `amount` is large")
                   ]
      [ () | Ambiguous{} <- ws ] `shouldBe` []

    it "measures the column from a section GIVEN's keyword, not from column 1" $ do
      -- The section's keyword is at column 5. Past it: the section's input.
      -- At it: the rule below, as before — although column 5 is indented.
      (m, _) <- parsed
        "§ `Rates`\n\
        \    GIVEN rate IS A NUMBER\n\
        \          @nlg the applicable rate\n\
        \DECIDE `twice the rate` IS rate TIMES 2\n\
        \§ `Floors`\n\
        \    GIVEN floor IS A NUMBER\n\
        \    @nlg the doubled floor\n\
        \DECIDE `twice the floor` IS floor TIMES 2\n"
      attachments m
        `shouldBe` [ ("rate", "the applicable rate")
                   , ("twice the floor", "the doubled floor")
                   ]

    it "measures the column from a GIVEN inside a WHERE" $ do
      (m, _) <- parsed
        "DECIDE `outer` IS `helper` 5 PLUS `other` 7\n\
        \  WHERE\n\
        \    GIVEN n IS A NUMBER\n\
        \          @nlg the helper's input\n\
        \    `helper` MEANS n TIMES 2\n\
        \\n\
        \    GIVEN m IS A NUMBER\n\
        \    @nlg the other one\n\
        \    `other` MEANS m TIMES 3\n"
      attachments m
        `shouldBe` [("n", "the helper's input"), ("other", "the other one")]

    it "attaches past a TYPICALLY default to the input above, not the next one" $ do
      (m, ws) <- parsed
        "GIVEN floor  IS A NUMBER TYPICALLY 100\n\
        \      @nlg the floor\n\
        \      amount IS A NUMBER TYPICALLY 0\n\
        \      @nlg the sum of money\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` IF amount GREATER THAN floor\n"
      attachments m `shouldBe` [("floor", "the floor"), ("amount", "the sum of money")]
      [ () | NotAttached{} <- ws ] `shouldBe` []

    it "does not give a last input's default an annotation the input declined" $ do
      -- A default that names something has a name that claims. Unclamped, it
      -- would take the rule's sentence the input left alone.
      (m, _) <- parsed
        "DECIDE `usual amount` IS 50\n\
        \\n\
        \GIVEN amount IS A NUMBER TYPICALLY `usual amount`\n\
        \@nlg the claim of %amount% is large\n\
        \DECIDE `is large` IF amount GREATER THAN 100\n"
      attachments m `shouldBe` [("is large", "the claim of `amount` is large")]

    it "stops at a DECIDE, ASSUME, DECLARE or YIELD written on a line of its own" $ do
      -- Those keywords are tokens of the declaration, not nodes with a span,
      -- so they do not bound the last input by themselves. Past one of them,
      -- an annotation is no longer inside the GIVEN list.
      (decide, _) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \DECIDE\n\
        \  @nlg after the DECIDE keyword\n\
        \  `is large` IF amount GREATER THAN 100\n"
      attachments decide `shouldBe` [("is large", "after the DECIDE keyword")]
      (assume, _) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \ASSUME\n\
        \  @nlg after the ASSUME keyword\n\
        \  `is large` IS A BOOLEAN\n"
      attachments assume `shouldBe` [("is large", "after the ASSUME keyword")]
      (declare, _) <- parsed
        "GIVEN a IS A TYPE\n\
        \DECLARE\n\
        \  @nlg after the DECLARE keyword\n\
        \  Box HAS content IS AN a\n"
      attachments declare `shouldBe` [("Box", "after the DECLARE keyword")]
      (lambda, _) <- parsed
        "DECIDE `doubled` IS\n\
        \  map\n\
        \    (GIVEN x YIELD\n\
        \        @nlg after the YIELD keyword\n\
        \        `twice` x)\n\
        \    xs\n"
      attachments lambda `shouldBe` [("twice", "after the YIELD keyword")]

    it "does not give the first input an annotation written ABOVE the GIVEN" $ do
      (m, ws) <- parsed
        "@nlg written above the GIVEN\n\
        \GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` IF amount GREATER THAN 100\n"
      attachments m `shouldBe` []
      [ () | NotAttached{} <- ws ] `shouldSatisfy` (not . null)
