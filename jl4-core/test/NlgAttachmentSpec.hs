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
import qualified Base.Text as Text

import L4.Annotation (getAnno)
import L4.Nlg (simpleLinearizer)
import L4.Parser (execProgramParserWithHintPass)
import L4.Parser.ResolveAnnotation (Warning (..))
import L4.Syntax (AppForm (..), Decide (..), Module, Name, annDesc, annNlg, getDesc, nameToText)
import qualified Optics
import Test.Hspec

-- | Every name carrying an annotation, as @(name, what it says)@.
attachments :: Module Name -> [(Text, Text)]
attachments m =
  [ (nameToText n, simpleLinearizer nlg)
  | n <- Optics.toListOf (Optics.gplate @Name) m
  , Just nlg <- [view annNlg (getAnno n)]
  ]

-- | Every definition carrying a @\@desc@, as @(name, what it says)@: the
-- definitions inside a definition (a @WHERE@'s) included, which 'Optics.gplate'
-- does not reach, as it stops at the first definition on each path.
descriptions :: Module Name -> [(Text, Text)]
descriptions m =
  [ (nameToText n, getDesc d)
  | MkDecide ann _ (MkAppForm _ n _ _) _ <- concatMap withinDecide (Optics.toListOf (Optics.gplate @(Decide Name)) m)
  , Just d <- [view annDesc ann]
  ]
 where
  withinDecide :: Decide Name -> [Decide Name]
  withinDecide d = d : concatMap withinDecide (Optics.toListOf (Optics.gplate @(Decide Name)) d)

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
      -- A default that is a name — here an enum constructor, which
      -- type-checks — claims. Unclamped, it would take the rule's sentence the
      -- input left alone.
      (m, _) <- parsed
        "DECLARE Colour IS ONE OF Red, Green\n\
        \\n\
        \GIVEN colour IS A Colour TYPICALLY Red\n\
        \@nlg the colour %colour% is warm\n\
        \DECIDE `is warm` IF colour EQUALS Red\n"
      attachments m `shouldBe` [("is warm", "the colour `colour` is warm")]

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

    it "measures from the GIVEN keyword, not from the inputs' column" $ do
      -- Column 3 is past GIVEN (column 1) but left of the input (column 7).
      (m, _) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \  @nlg the sum of money\n\
        \DECIDE `is large` IF amount GREATER THAN 100\n"
      attachments m `shouldBe` [("amount", "the sum of money")]

    it "gives an annotation under an input before the last to that input, at any column" $ do
      -- Only the last input has a column test; the next input bounds the rest.
      (m, _) <- parsed
        "GIVEN floor   IS A NUMBER\n\
        \      @nlg the floor\n\
        \      ceiling IS A NUMBER\n\
        \@nlg the ceiling\n\
        \      amount  IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `in range` IF amount GREATER THAN floor\n"
      attachments m `shouldBe` [("floor", "the floor"), ("ceiling", "the ceiling")]

    it "gives a gloss trailing a literal default to the input" $ do
      -- A literal claims nothing, so the gloss would otherwise go past the
      -- input: onto the next input, or onto the rule after the last one.
      (m, ws) <- parsed
        "GIVEN floor  IS A NUMBER TYPICALLY 100 @nlg the floor\n\
        \      amount IS A NUMBER TYPICALLY 5 @nlg the sum of money\n\
        \DECIDE `is large` IF amount GREATER THAN floor\n"
      attachments m `shouldBe` [("floor", "the floor"), ("amount", "the sum of money")]
      [ () | Ambiguous{} <- ws ] `shouldBe` []

    it "attaches to the last input whatever follows the list" $ do
      -- A MEANS rule, a section heading, a DECLARE and a directive each follow
      -- a GIVEN list here; the indented annotation is the input's every time.
      (means, _) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \      @nlg the sum of money\n\
        \`is large` MEANS amount GREATER THAN 100\n"
      attachments means `shouldBe` [("amount", "the sum of money")]
      (heading, _) <- parsed
        "§ `Rates`\n\
        \    GIVEN rate IS A NUMBER\n\
        \          @nlg the applicable rate\n\
        \§ `Floors`\n\
        \DECIDE `twice the floor` IS 10\n"
      attachments heading `shouldBe` [("rate", "the applicable rate")]
      (declare, _) <- parsed
        "§ `Rates`\n\
        \    GIVEN rate IS A NUMBER\n\
        \          @nlg the applicable rate\n\
        \DECLARE Thing HAS a IS A NUMBER\n"
      attachments declare `shouldBe` [("rate", "the applicable rate")]
      (directive, _) <- parsed
        "§ `Rates`\n\
        \    GIVEN rate IS A NUMBER\n\
        \          @nlg the applicable rate\n\
        \#EVAL 1 PLUS 1\n"
      attachments directive `shouldBe` [("rate", "the applicable rate")]

    it "attaches tagged renderings, and reaches past a type written over two lines" $ do
      (tagged, ws) <- parsed
        "GIVEN amount IS A NUMBER\n\
        \      @nlg:he הסכום\n\
        \      @nlg:en the sum of money\n\
        \DECIDE `is large` IF amount GREATER THAN 100\n"
      attachments tagged `shouldBe` [("amount", "the sum of money")]
      [ () | Ambiguous{} <- ws ] `shouldBe` []
      (twoLines, _) <- parsed
        "GIVEN amounts IS A LIST OF (\n\
        \                  NUMBER)\n\
        \      @nlg the amounts\n\
        \DECIDE `same` IF amounts EQUALS amounts\n"
      attachments twoLines `shouldBe` [("amounts", "the amounts")]

    it "does not give the first input an annotation written ABOVE the GIVEN" $ do
      (m, ws) <- parsed
        "@nlg written above the GIVEN\n\
        \GIVEN amount IS A NUMBER\n\
        \GIVETH A BOOLEAN\n\
        \DECIDE `is large` IF amount GREATER THAN 100\n"
      attachments m `shouldBe` []
      [ () | NotAttached{} <- ws ] `shouldSatisfy` (not . null)

  describe "in a rule written as clauses" $ do
    -- The clauses are lowered to one tree in which the later clauses are bound
    -- by a LET, so that the tree is visited last clause first. A definition in
    -- the WHERE of a clause found its annotation taken, or dropped, unless the
    -- clause was the last (refutation of legalese/l4-ide#545's review, round 4).
    let clauses ann =
          "GIVEN n IS A NUMBER\n\
          \GIVETH A NUMBER\n\
          \DECIDE f 0 IS g 1\n\
          \  WHERE\n\
          \    " <> ann <> " the helper of the first clause\n\
          \    g x MEANS x + 1\n\
          \DECIDE f 1 IS h 2\n\
          \  WHERE\n\
          \    " <> ann <> " the helper of the second clause\n\
          \    h y MEANS y + 2\n\
          \DECIDE f other IS k 3\n\
          \  WHERE\n\
          \    " <> ann <> " the helper of the last clause\n\
          \    k z MEANS z + 3\n"

    it "gives a definition in the WHERE of a clause its @nlg, whichever clause it is in" $ do
      (m, ws) <- parsed (clauses "@nlg")
      sortOn fst (attachments m) `shouldBe`
        [ ("g", "the helper of the first clause")
        , ("h", "the helper of the second clause")
        , ("k", "the helper of the last clause")
        ]
      [ () | NotAttached{} <- ws ] `shouldBe` []

    it "gives a definition in the WHERE of a clause its @desc, whichever clause it is in" $ do
      (m, _) <- parsed (clauses "@desc")
      sortOn fst (descriptions m) `shouldBe`
        [ ("g", "the helper of the first clause")
        , ("h", "the helper of the second clause")
        , ("k", "the helper of the last clause")
        ]

    it "still leaves an @nlg written between two clauses to the clause below" $ do
      -- No name of the clause below, a pattern say, may take it first.
      (m, ws) <- parsed
        "GIVEN n IS A NUMBER\n\
        \GIVETH A NUMBER\n\
        \DECIDE f 0 IS 1\n\
        \DECIDE f 1 IS 2\n\
        \@nlg between the second and the third\n\
        \DECIDE f other IS 3\n"
      attachments m `shouldBe` []
      [ () | NotAttached{} <- ws ] `shouldBe` []

  -- A TYPICALLY default is a value the author supplies, not a thing the author
  -- describes, and nothing reads an annotation on it. It used to be traversed
  -- like any other child, so it advertised a span (cutting the field's name off
  -- from the line below) and, when it was a name, claimed what trailed it. The
  -- annotation then attached to a node nothing renders, or to the NEXT field,
  -- and nothing was reported (smucclaw/l4-ide#994, #997).
  --
  -- The property is metamorphic and does not depend on the shape: adding or
  -- removing the TYPICALLY clause must not change where any annotation lands,
  -- or what is reported.
  --
  -- Cases marked (a guard) were already right before the default stopped being
  -- traversed, and pass on the old binary too. They stay because they pin what
  -- must not move. The others fail there, some only behind one kind of default
  -- (a gloss trailing a name default), which is what shows the property is not
  -- vacuous.
  --
  -- The herald-at-the-margin cases under the LAST field are the third kind:
  -- the old traversal got them right by accident (the default's span cut the
  -- field's name off from the line below), so the fix owed them a column test
  -- (smucclaw/l4-ide#976) instead.
  describe "a TYPICALLY default takes no annotation" $ do
    let defaults =
          [ ("a number",   "NUMBER",  "100")
          , ("a string",   "STRING",  "\"x\"")
          , ("TRUE",       "BOOLEAN", "TRUE")
          , ("an enum constructor", "Colour", "Red")
          ]
        enums = "DECLARE Colour IS ONE OF Red, Green\n\n"
        -- {T} is the type, {D} the default clause, present or absent.
        fill ty clause template =
          enums <> Text.replace "{T}" ty (Text.replace "{D}" clause template)
        unreported ws = length [ () | NotAttached{} <- ws ] + length [ () | Ambiguous{} <- ws ]

        sameWithAndWithout label template expected =
          forM_ defaults $ \(kind, ty, dflt) ->
            it (label <> ", behind " <> Text.unpack kind) $ do
              (withDefault, wsWith) <- parsed (fill ty (" TYPICALLY " <> dflt) template)
              (bare, wsWithout) <- parsed (fill ty "" template)
              attachments withDefault `shouldBe` attachments bare
              unreported wsWith `shouldBe` unreported wsWithout
              -- The control is not vacuous: the shape lands where it says.
              expected (attachments bare) ty

    describe "on a record field" $ do
      sameWithAndWithout "an own-line gloss under it, another field after it"
        "DECLARE Rec HAS\n    base IS A {T}{D}\n    @nlg the base\n    other IS A {T}\n"
        (\ got _ -> got `shouldBe` [("base", "the base")])
      sameWithAndWithout "an own-line gloss under the last field"
        "DECLARE Rec HAS\n    other IS A {T}\n    base IS A {T}{D}\n    @nlg the base\n"
        (\ got _ -> got `shouldBe` [("base", "the base")])
      sameWithAndWithout "a gloss trailing it (the TYPE's, as for a field with no default)"
        "DECLARE Rec HAS\n    base IS A {T}{D} @nlg the base\n    other IS A {T}\n"
        (\ got ty -> got `shouldBe` [(ty, "the base")])
      sameWithAndWithout "a gloss before the type (a guard)"
        "DECLARE Rec HAS\n    base [the base] IS A {T}{D}\n    other IS A {T}\n"
        (\ got _ -> got `shouldBe` [("base", "the base")])
      sameWithAndWithout "an own-line gloss under a constructor's field"
        "DECLARE Shape IS ONE OF\n    Dot\n    Disc HAS\n        base IS A {T}{D}\n        @nlg the base\n        other IS A {T}\n"
        (\ got _ -> got `shouldBe` [("base", "the base")])
      -- The last field takes only what is indented past the DECLARE keyword,
      -- as the last input of a GIVEN list does. A herald at the margin is the
      -- NEXT declaration's.
      sameWithAndWithout "a herald at the margin under the last field, for the rule after it"
        "DECLARE Rec HAS\n    base IS A {T}{D}\n\n@nlg the answer\nDECIDE `answer` IS 42\n"
        (\ got _ -> got `shouldBe` [("answer", "the answer")])
      sameWithAndWithout "a herald at the margin under the last field, for the DECLARE after it"
        "DECLARE Rec HAS\n    base IS A {T}{D}\n\n@nlg an employee\nDECLARE Emp HAS\n    salary IS A NUMBER\n"
        (\ got _ -> got `shouldBe` [("Emp", "an employee")])
      sameWithAndWithout "a herald at the margin under a constructor's last field, for the rule after it"
        "DECLARE Shape IS ONE OF\n    Dot\n    Disc HAS\n        base IS A {T}{D}\n\n@nlg the answer\nDECIDE `answer` IS 42\n"
        (\ got _ -> got `shouldBe` [("answer", "the answer")])
      sameWithAndWithout "an indented gloss under the last field AND a herald at the margin for the rule"
        "DECLARE Rec HAS\n    base IS A {T}{D}\n    @nlg the base\n\n@nlg the answer\nDECIDE `answer` IS 42\n"
        (\ got _ -> got `shouldBe` [("base", "the base"), ("answer", "the answer")])

    describe "on a GIVEN input" $ do
      sameWithAndWithout "a gloss trailing it, another input after it"
        "GIVEN base IS A {T}{D} @nlg the base\n      other IS A {T}\nGIVETH A BOOLEAN\nDECIDE `r` IF TRUE\n"
        (\ got _ -> got `shouldBe` [("base", "the base")])
      sameWithAndWithout "an own-line gloss under it, another input after it (a guard)"
        "GIVEN base IS A {T}{D}\n      @nlg the base\n      other IS A {T}\nGIVETH A BOOLEAN\nDECIDE `r` IF TRUE\n"
        (\ got _ -> got `shouldBe` [("base", "the base")])
      sameWithAndWithout "an indented own-line gloss under the last input (a guard)"
        "GIVEN other IS A {T}\n      base IS A {T}{D}\n      @nlg the base\nGIVETH A BOOLEAN\nDECIDE `r` IF TRUE\n"
        (\ got _ -> got `shouldBe` [("base", "the base")])
      sameWithAndWithout "a rule's gloss at the GIVEN column, which is the rule's (a guard)"
        "GIVEN base IS A {T}{D}\n@nlg the rule\nDECIDE `r` IF TRUE\n"
        (\ got _ -> got `shouldBe` [("r", "the rule")])

    -- The one shape where a default still matters. A gloss at the GIVEN column
    -- written between an input's type and a TYPICALLY on the next line is
    -- INSIDE the input, so the rule below cannot have it and neither can the
    -- input. With no default the same line is after the list, and the rule's.
    -- It is reported, not guessed at.
    it "reports a rule's gloss written between an input's type and its default on the next line" $ do
      (m, ws) <- parsed
        "GIVEN other IS A NUMBER\n\
        \      base IS A NUMBER\n\
        \@nlg the rule\n\
        \      TYPICALLY 5\n\
        \DECIDE `r` IF TRUE\n"
      attachments m `shouldBe` []
      length [ () | NotAttached{} <- ws ] `shouldBe` 1
      (m', _) <- parsed
        "GIVEN other IS A NUMBER\n\
        \      base IS A NUMBER\n\
        \@nlg the rule\n\
        \DECIDE `r` IF TRUE\n"
      attachments m' `shouldBe` [("r", "the rule")]

    -- ASSUME is one declaration, so a herald at the margin under it is the NEXT
    -- declaration's and one indented past it is its own, the column test of
    -- the other two lists; and its default takes nothing.
    describe "on an ASSUME" $ do
      sameWithAndWithout "a gloss trailing it"
        "ASSUME `the input` IS A {T}{D} @nlg the assumed input\n"
        (\ got _ -> got `shouldBe` [("the input", "the assumed input")])
      sameWithAndWithout "an own-line herald at the margin under it, which is the rule's"
        "ASSUME `the input` IS A {T}{D}\n@nlg the output rule\nDECIDE `out` IS `the input`\n"
        (\ got _ -> got `shouldBe` [("out", "the output rule")])
      sameWithAndWithout "an indented own-line gloss under it, which is the assumption's"
        "ASSUME `the input` IS A {T}{D}\n    @nlg the assumed input\nDECIDE `out` IS `the input`\n"
        (\ got _ -> got `shouldBe` [("the input", "the assumed input")])
      sameWithAndWithout "a gloss trailing a default on the line below"
        "ASSUME base IS A {T}\n       {D} @nlg the base\n\nDECIDE `r` IS 1\n"
        (\ got _ -> got `shouldBe` [("base", "the base")])

  -- A constructor's field list is a column like a record's, so a herald below
  -- the last field is that FIELD's. The constructor's own herald therefore goes
  -- between its name and `HAS`, and the one written above a constructor is
  -- the previous constructor's (`gotchas.md`, "A constructor that has fields").
  describe "a constructor that has fields" $ do
    it "takes the herald written between its name and HAS" $ do
      (m, ws) <- parsed
        "DECLARE Penalty IS ONE OF\n\
        \    NoPenalty\n\
        \    Custodial\n\
        \        @nlg a custodial penalty\n\
        \        HAS years IS A NUMBER\n\
        \        @nlg the term in years\n"
      attachments m
        `shouldBe` [("Custodial", "a custodial penalty"), ("years", "the term in years")]
      [ () | NotAttached{} <- ws ] `shouldBe` []

    it "leaves a herald below its field list to the last field" $ do
      (m, _) <- parsed
        "DECLARE Penalty IS ONE OF\n\
        \    NoPenalty\n\
        \    Custodial\n\
        \        HAS years IS A NUMBER\n\
        \        @nlg the term in years\n"
      attachments m `shouldBe` [("years", "the term in years")]

    it "leaves a herald above it to the constructor before" $ do
      (m, _) <- parsed
        "DECLARE Penalty IS ONE OF\n\
        \    NoPenalty\n\
        \    @nlg a custodial penalty\n\
        \    Custodial\n\
        \        HAS years IS A NUMBER\n"
      attachments m `shouldBe` [("NoPenalty", "a custodial penalty")]
