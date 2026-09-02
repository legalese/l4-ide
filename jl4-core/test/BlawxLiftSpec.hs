{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Specs for "L4.Blawx.Lift" — the import back end (BLAWX-EXPORT-SPEC §8.14
-- R14, §10 P5).
--
-- __Why these and not more.__ The end-to-end evidence for the lift is
-- @jl4\/examples\/blawx\/imported\/bird.l4@ plus the two harnesses, and that
-- is the right shape for evidence: a real document, both engines, no mocks.
-- What a corpus of one cannot do is exhibit the cases bird happens not to
-- have — and each spec below is one of those, every one a defect measured on
-- this tree rather than a hypothetical:
--
-- * a defeat __cycle__: bird's @overrules@ edges form a DAG, so the
--   stratification guard was never exercised by it — and was in fact inert,
--   because the negation it must find is introduced by the lift itself and
--   appears in no rule body;
-- * a __test canvas__ holding anything but a positive ground fact and a
--   query: bird's four tests hold exactly those, while 11 tests elsewhere in
--   the shipped corpus declare their own objects and 2 assert a NEGATIVE
--   fact;
-- * an atom introduced by a __fact__ rather than an @object_declaration@:
--   bird's only atom is declared;
-- * a scenario fact about a __concluded__ predicate: bird has none.
module BlawxLiftSpec (spec) where

import Test.Hspec

import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as Text

import L4.Blawx.IR
import L4.Blawx.Lift

spec :: Spec
spec = do
  describe "the stratification guard" $ do
    it "accepts bird's own acyclic defeat layer" $
      lifts (baseDoc [sec1Ws, sec2Ws, sec3Ws defeatsOnly, sec4Ws]) `shouldBe` Right ()

    -- The regression the guard exists for: two `overrules` making sections 3
    -- and 4 defeat each other. Every edge a rule BODY carries is positive —
    -- the negation is introduced by the lift's own `AND NOT <defeated>`
    -- conjunct — so a scan over `attributed_rule` conditions alone reports
    -- nothing and the emitted module is a mutual recursion through NOT that
    -- type-checks and diverges.
    it "refuses a mutual defeat cycle, which no rule body makes visible" $
      refusalsOf (baseDoc [sec1Ws, sec2Ws, sec3Ws mutualDefeat, sec4Ws])
        `shouldSatisfy` anyMentioning "blawx-lift/unstratified"

    it "refuses a section whose own conclusion defeats itself" $
      refusalsOf (baseDoc [sec1Ws, sec2Ws, sec3Ws selfDefeat, sec4Ws])
        `shouldSatisfy` anyMentioning "blawx-lift/unstratified"

  describe "test canvases are vetted, not silently trimmed" $ do
    it "accepts a positive unary ground fact beside the query" $
      lifts (docWithTest [BFact True (bn "penguin") [BTAtom (bn "pingu")], q])
        `shouldBe` Right ()

    -- W5, 2026-09-02: an `object_declaration` on a test canvas is no longer
    -- refused. It is a TEST-LOCAL object — Blawx loads a test's declarations
    -- beside the rules — so it lands in that test's own world, which is why
    -- the world became a parameter rather than a module-level constant.
    it "lifts an `object_declaration` on a test canvas into that test's own world" $
      textOf (docWithTest [BDeclareObject (objDecl "socrates" "penguin"), q])
        `shouldSatisfy` Text.isInfixOf "`t world` MEANS LIST `t socrates`"

    -- The three below are still refused BY NAME; what changed with W5 is the
    -- severity. A test is an oracle, not a rule: dropping it loses a check but
    -- cannot make an emitted rule wrong, so the document still lifts and the
    -- reason is written into the artifact where the `#EVAL` would have been.
    -- That is strictly stronger than what the 2026-08-19 review replaced
    -- (ignore the block, emit the `#EVAL` anyway): there is no `#EVAL` left to
    -- answer the wrong question.
    it "drops a test carrying a NEGATIVE scenario fact, by name, and emits no #EVAL" $ do
      let d = docWithTest [BFact False (bn "penguin") [BTAtom (bn "pingu")], q]
      warningsOf d `shouldSatisfy` anyMentioning "blawx-lift/test-block"
      textOf d `shouldSatisfy` Text.isInfixOf "-- NOT LIFTED (blawx-lift/test-block)"
      textOf d `shouldNotSatisfy` hasDirective

    it "drops a test carrying an `assume` (an abducible), by name" $ do
      let d = docWithTest [BAbducible (bn "penguin") [BTVar (MkBVar "A")], q]
      warningsOf d `shouldSatisfy` anyMentioning "blawx-lift/test-block"
      textOf d `shouldNotSatisfy` hasDirective

    it "drops a test whose scenario names an undeclared predicate, by name" $ do
      let d = docWithTest [BFact True (bn "nosuch") [BTAtom (bn "pingu")], q]
      warningsOf d `shouldSatisfy` anyMentioning "blawx-lift/scenario-undeclared"
      textOf d `shouldNotSatisfy` hasDirective

  describe "the object universe" $
    -- `membersOf` always counted both sources; `all objects` did not, so an
    -- existential #EVAL ranged over a strictly smaller universe than the
    -- s(CASP) it is compared against.
    it "includes an atom introduced by a fact, not only a declared object" $
      textOf docWithFactAtom
        `shouldSatisfy` Text.isInfixOf "`all objects` MEANS LIST pingu, tweety"

  describe "input channels" $
    -- Before the fix a CONCLUDED category got no `<p> fact` field, so a test
    -- asserting `bird(pingu).` produced a record with nowhere to put it and
    -- the fact vanished into a right-looking answer.
    it "gives a concluded category a fact field, so a scenario fact survives" $
      textOf (docWithTest [BFact True (bn "bird") [BTAtom (bn "pingu")], q])
        `shouldSatisfy` \t -> lineWith t "`bird fact`" "IS JUST TRUE"

  -- BLAWX-EXPORT-SPEC §11 W5: the beard_tax increment. bird has neither a
  -- non-boolean attribute nor a comparison nor two rules concluding one
  -- literal in one section nor a paragraph workspace, so none of these
  -- shapes had a spec before.
  describe "value-typed attributes (§11 W5)" $ do
    it "lifts a number attribute, a binding goal and a comparison" $
      lifts (valueDoc BVNumber [attrGoal, cmpGoal BGte (BTNum 5)]) `shouldBe` Right ()

    it "declares the number attribute as a MAYBE NUMBER field" $
      textOf (valueDoc BVNumber [attrGoal, cmpGoal BGte (BTNum 5)])
        `shouldSatisfy` \t -> lineWith t "hair" "IS A MAYBE NUMBER"

    it "renders `gte` as AT LEAST over the accessor" $
      textOf (valueDoc BVNumber [attrGoal, cmpGoal BGte (BTNum 5)])
        `shouldSatisfy` Text.isInfixOf "`the hair of` x AT LEAST 5"

    -- The binding goal itself must still say the attribute is DEFINED: with
    -- the accessor's `fromMaybe 0` and no such conjunct, an absent attribute
    -- would answer `0 AT LEAST 5` — FALSE here, but TRUE for `AT MOST`.
    --
    -- The condition order here is beard_tax's own: the comparison is drawn
    -- ABOVE the binding goal, which s(CASP) is happy with (the constraint
    -- delays) and which forces the substitution environment to be computed
    -- over the whole rule before any single condition is lifted.
    it "keeps the definedness conjunct, wherever the binding goal is drawn" $
      textOf (valueDoc BVNumber [cmpGoal BGte (BTNum 5), attrGoal])
        `shouldSatisfy` \t ->
          Text.isInfixOf "IF  `the hair of` x AT LEAST 5" t && Text.isInfixOf "AND hair x" t

    it "declares a category-valued attribute as a MAYBE STRING field" $
      textOf (valueDoc (BVCategory (bn "person")) [attrGoal, cmpGoal BEq (BTAtom (bn "pingu"))])
        `shouldSatisfy` \t -> lineWith t "hair" "IS A MAYBE STRING"

    it "still refuses a date-valued attribute by name" $
      refusalsOf (valueDoc BVDate [attrGoal, cmpGoal BGte (BTNum 5)])
        `shouldSatisfy` anyMentioning "blawx-lift/attribute-type"

    it "refuses a bound VALUE variable used as an OBJECT" $
      refusalsOf (valueDoc BVNumber [attrGoal, BGCall True (bn "person") [BTVar (MkBVar "L")]])
        `shouldSatisfy` anyMentioning "blawx-lift/value-variable-in-object-position"

    it "refuses a comparison on a variable no binding goal binds" $
      refusalsOf (valueDoc BVNumber [cmpGoal BGte (BTNum 5)])
        `shouldSatisfy` anyMentioning "blawx-lift/unbound-value"

    -- Every object position lifts to the single GIVEN `x`, so a second object
    -- variable would be silently identified with the first.
    it "refuses a second object variable rather than collapsing it" $
      refusalsOf (valueDoc BVNumber [BGCall True (bn "person") [BTVar (MkBVar "B")]])
        `shouldSatisfy` anyMentioning "blawx-lift/multi-object-variable"

  describe "several rules concluding one literal in one section" $ do
    it "lifts, rather than emitting the same decision name twice" $
      lifts twoClauseDoc `shouldBe` Right ()

    it "names each Blawx rule its own clause and ORs them" $
      textOf twoClauseDoc
        `shouldSatisfy` \t ->
          Text.isInfixOf "`according to sec_1_section, x is a bird (clause 1)` x" t
            && Text.isInfixOf "`according to sec_1_section, x is a bird (clause 2)` x" t

  describe "a value-typed attribute goal under default negation" $ do
    -- Found in review of the first W5a commit.
    -- `not attr(A,V)` binds nothing: V has to be bound already, and the goal
    -- is then a TEST of the attribute's value against it. Reusing the
    -- positive image — which is only the definedness conjunct, because the
    -- binding is discharged by substitution — turned the test into
    -- \"the attribute is undefined\" and dropped the comparison.
    it "under `not`, tests the bound value rather than asserting absence" $
      textOf (twoValueDoc [attrGoal, BGNegated BNegDefault nailsGoal])
        `shouldSatisfy` Text.isInfixOf "NOT (nails x AND `the nails of` x EQUALS `the hair of` x)"

    it "under `not`, still reads an anonymous value slot as `absent`" $
      textOf (twoValueDoc [attrGoal, BGNegated BNegDefault (BGCall True (bn "nails") [va, anon])])
        `shouldSatisfy` Text.isInfixOf "NOT (nails x)"

    -- `valueBindings` scans POSITIVE goals only, so a variable that only a
    -- negated goal mentions is bound by nothing and must be refused, not
    -- quietly read as an anonymous slot.
    it "refuses a value variable only a negated goal mentions" $
      refusalsOf (twoValueDoc [BGNegated BNegDefault nailsGoal])
        `shouldSatisfy` anyMentioning "blawx-lift/unbound-value"

  describe "paragraph sections (§11 W3 is still open)" $ do
    it "files a paragraph's rules under its parent section" $
      lifts paragraphDoc `shouldBe` Right ()

    it "warns that the paragraph survives only in the @ref line" $
      warningsOf paragraphDoc `shouldSatisfy` anyMentioning "blawx-lift/rule-section-flattened"

    -- __The defect the paragraph fold shipped with__, found in review and
    -- reproduced end to end by the two fixtures under
    -- `jl4/tests-cli/fixtures/blawx-import/paragraph-defeat*.blawx`. The rule
    -- was filed under the FOLDED section while the `overrules` was keyed on
    -- the RAW paragraph, so `isDefeated` was False: the `AND NOT <defeated>`
    -- conjunct was never emitted, the `… is defeated` decision was defined
    -- and never used, and the module type-checked with exit code 0 and no
    -- diagnostic. Both halves are asserted, because the dangling decision
    -- alone satisfied the first.
    it "keeps a defeat both of whose sections are paragraphs" $
      textOf paragraphDefeatDoc
        `shouldSatisfy` \t ->
          Text.isInfixOf
            "AND NOT `the conclusion in sec_1_section that x is a bird is defeated` x"
            t
            && Text.isInfixOf
              "IF `the conclusion in sec_1_section that x is an ostrich holds` x"
              t
            && not (Text.isInfixOf "no overrules names" t)

    it "warns that the defeat, too, only survives the fold" $
      warningsOf paragraphDefeatDoc
        `shouldSatisfy` anyMentioning "blawx-lift/defeat-section-flattened"

    -- __And what the fold may NOT do.__ Folding the keys makes the defeat
    -- survive, but it also makes section identity coarser than s(CASP)'s, and
    -- measurement says that changes answers in two directions. Both are
    -- refused by name rather than folded quietly.
    --
    -- (a) A sibling paragraph concluding the same literal folds into the same
    -- §§, so a defeat aimed at one paragraph would cover the other.
    it "refuses a fold that would widen a defeat over a sibling paragraph" $
      refusalsOf paragraphDefeatWideDoc
        `shouldSatisfy` anyMentioning "blawx-lift/defeat-fold-unsound"

    -- (b) The mirror, and the shape the review counterexample actually had:
    -- an `overrules` whose DEFEATING pair is the flat parent while the rule
    -- concluding it sits in a paragraph. s(CASP) keys `holds/3` on the exact
    -- section, so `holds(sec_1_section, ostrich, X)` has no clause at all and
    -- the defeat never fires in Blawx — while the fold would give it a body.
    -- Measured on `paragraph-defeat.blawx`: swipl answers MODEL for
    -- `qualifies_s1a(p)` in every scenario, i.e. never defeated.
    it "refuses an `overrules` whose defeating conclusion is inert in Blawx" $
      refusalsOf paragraphDefeatInertDoc
        `shouldSatisfy` anyMentioning "blawx-lift/defeat-target"

    it "refuses an `overrules` naming an unplaceable DEFEATED section" $
      refusalsOf (paragraphDefeatDocIn (BPath (mkStep "art" "II" :| [])))
        `shouldSatisfy` anyMentioning "blawx-lift/defeat-section"

  -- ------------------------------------------------------------------
  -- W5 (2026-09-02): arities above one, and what they force
  -- ------------------------------------------------------------------
  describe "predicates above arity one" $ do
    it "keeps a document of unary predicates free of the world parameter" $
      textOf (baseDoc [sec1Ws, sec2Ws, sec3Ws defeatsOnly, sec4Ws])
        `shouldNotSatisfy` Text.isInfixOf "IS A LIST OF Object"

    -- Blawx overloads on arity: rps declares BOTH the category `player/1` and
    -- the attribute `player/2`, and s(CASP) tells them apart. L4 cannot, so
    -- the lowest arity keeps the bare name and the rest are spelled
    -- Prolog-style. Without this the two collapse into one L4 decision.
    it "disambiguates a name declared at two arities, Prolog-style" $ do
      textOf rpsShaped `shouldSatisfy` Text.isInfixOf "DECIDE `player/2` x1 x2"
      textOf rpsShaped `shouldSatisfy` Text.isInfixOf "DECIDE player x "

    it "carries an n-ary predicate's fact channel as a list of argument tuples" $
      textOf rpsShaped
        `shouldSatisfy` \t -> lineWith t "`player/2 fact`" "IS A LIST OF (LIST OF STRING)"

    -- The rule's body binds `Player2`, which its head does not. s(CASP) reads
    -- that existentially; an L4 decision's parameters are universal, so the
    -- rule splits into a witness decision plus an `any` over the world.
    it "closes a body-only variable with `any` over the world" $ do
      textOf rpsShaped `shouldSatisfy` Text.isInfixOf ", witnessed by player2` x1 x2 player2"
      textOf rpsShaped `shouldSatisfy` Text.isInfixOf "any (GIVEN player2 YIELD"

    -- The witness decision is the one derived decision nothing else calls, so
    -- its world parameter is not forced by an arity agreement: it takes the
    -- world only when its own body reads it. rps s.4's body is all INPUT
    -- predicates, so the witness there declares no `w` at all — an unused
    -- `w IS A LIST OF Object` is a parameter a reader looks for the use of.
    it "gives the witness decision no world parameter when its body reads none" $ do
      textOf rpsShaped `shouldSatisfy` not . Text.isInfixOf ", witnessed by player2` w"
      -- but the QUANTIFIER decision keeps it: `w` is the domain it ranges over
      textOf rpsShaped
        `shouldSatisfy` \t -> lineWith t "DECIDE" "the winner of x1 is x2` w x1 x2"

    -- ... and it does take the world when a body conjunct is a predicate some
    -- rule concludes, which is the branch the other case cannot reach.
    it "gives the witness decision a world parameter when its body reads one" $
      textOf rpsChained
        `shouldSatisfy` Text.isInfixOf ", witnessed by player2` w x1 x2 player2"

    -- Blawx compares objects by ATOM; L4 compares records by value. The atom
    -- is the `name` field, so that is what the two agree on — the same finding
    -- W1 records from the export side.
    it "renders `blawx_diseq` as a comparison of atoms, never of records" $
      textOf rpsShaped `shouldSatisfy` Text.isInfixOf "NOT (x2's name EQUALS player2's name)"

  describe "comments (ruling P5-4)" $ do
    it "lifts a workspace comment under the § of its section" $
      commentBlock (textOf (commentDoc (bSec 1) "drafter's note"))
        `shouldBe` ["-- <comment> on sec_1_section:", "-- drafter's note"]

    it "lifts a root_section comment into the ontology" $
      commentBlock (textOf (commentDoc BRoot "ontology note"))
        `shouldBe` ["-- <comment> on root_section:", "-- ontology note"]

    -- A blank line inside a Blawx <comment> used to become `"-- "` — a line
    -- with trailing whitespace, in a file no formatter in this repo touches.
    it "renders a blank line as a bare `--`, never `-- `" $
      commentBlock (textOf (commentDoc (bSec 1) "one\n\ntwo"))
        `shouldBe` ["-- <comment> on sec_1_section:", "-- one", "--", "-- two"]

    it "warns rather than dropping a comment with no § to sit under" $
      warningsOf (baseDoc [sec1Ws, sec2Ws, sec3Ws defeatsOnly, sec4Ws, orphanCommentWs])
        `shouldSatisfy` anyMentioning "blawx-lift/comment-unplaced"

-- ---------------------------------------------------------------------------
-- Running the lift
-- ---------------------------------------------------------------------------

lifts :: BlawxDoc -> Either [Text] ()
lifts d = case liftBlawx emptyLiftContext d of
  Left ds -> Left (map renderLiftDiag ds)
  Right _ -> Right ()

refusalsOf :: BlawxDoc -> [Text]
refusalsOf d = case liftBlawx emptyLiftContext d of
  Left ds -> map renderLiftDiag ds
  Right _ -> []

warningsOf :: BlawxDoc -> [Text]
warningsOf d = case liftBlawx emptyLiftContext d of
  Left ds -> map renderLiftDiag ds
  Right (_, ws') -> map renderLiftDiag ws'

-- | The emitted source. Fails loudly rather than returning @\"\"@, so a spec
-- that asserts on the text cannot pass because the lift refused.
textOf :: BlawxDoc -> Text
textOf d = case liftBlawx emptyLiftContext d of
  Left ds -> error (Text.unpack ("lift refused: " <> Text.intercalate "; " (map renderLiftDiag ds)))
  Right (t, _) -> t

-- | Is there an actual @#EVAL@ DIRECTIVE? Not merely the token, which also
-- occurs inside the refusal message the artifact carries ("has no #EVAL image
-- this phase") — the first spelling of these specs matched that and passed on
-- a file with no directive in it at all.
hasDirective :: Text -> Bool
hasDirective = any ("#EVAL" `Text.isPrefixOf`) . Text.lines

anyMentioning :: Text -> [Text] -> Bool
anyMentioning needle = any (Text.isInfixOf needle)

-- | The one line carrying both fragments — enough to say WHICH field is set,
-- without pinning the column padding.
lineWith :: Text -> Text -> Text -> Bool
lineWith t a b = any (\l -> a `Text.isInfixOf` l && b `Text.isInfixOf` l) (Text.lines t)

-- | The @\<comment\>@ header line and every @--@ line under it.
commentBlock :: Text -> [Text]
commentBlock t = case break ("-- <comment> on " `Text.isPrefixOf`) (Text.lines t) of
  (_, hdr : rest) -> hdr : takeWhile (\l -> l == "--" || "-- " `Text.isPrefixOf` l) rest
  _ -> []

-- ---------------------------------------------------------------------------
-- Fixtures — bird's shape, small enough to read whole
-- ---------------------------------------------------------------------------

baseDoc :: [BWorkspace] -> BlawxDoc
baseDoc wss =
  MkBlawxDoc
    { bdName = "New Bird Act"
    , bdRuleText =
        MkBRuleText
          { brTitle = "New Bird Act"
          , brSections = [MkBSection {bsNumber = i, bsText = "s" <> Text.pack (show i)} | i <- [1 .. 4 :: Int]]
          }
    , bdWorkspaces = wss
    , bdTests = []
    , bdDocPartNames = Map.empty
    }

-- | The ontology plus the rule that CONCLUDES @bird@ — the split the old
-- channel rule turned on (@bird@ concluded, @penguin@ not).
sec1Ws, sec2Ws, sec4Ws :: BWorkspace
sec1Ws =
  ws
    (bSec 1)
    [ [ BDeclareCategory
          MkBCategoryDecl {bcName = bn "penguin", bcPrefix = "", bcPostfix = "is a penguin", bcProv = Nothing}
      , BDeclareCategory
          MkBCategoryDecl {bcName = bn "bird", bcPrefix = "", bcPostfix = "is a bird", bcProv = Nothing}
      , BDeclareAttribute (boolAttr "thing" "flies" "can fly")
      ]
    , [BAttributedRule (rule 1 True "bird" [BGCall True (bn "penguin") [va]] False)]
    ]
sec2Ws = ws (bSec 2) [[BAttributedRule (rule 2 True "flies" [BGCall True (bn "bird") [va]] True)]]
sec4Ws = ws (bSec 4) [[BAttributedRule (rule 4 True "flies" [BGCall True (bn "penguin") [va]] True)]]

-- | Section 3 concludes @-flies@ and carries whatever priority edges are given.
sec3Ws :: [BOverrule] -> BWorkspace
sec3Ws os =
  ws
    (bSec 3)
    ( [[BOverrules o] | o <- os]
        <> [[BAttributedRule (rule 3 False "flies" [BGCall True (bn "penguin") [va]] True)]]
    )

-- | bird's own shape: 3 defeats 2, 4 defeats 3. A DAG.
defeatsOnly :: [BOverrule]
defeatsOnly = [overrule 3 False 2 True, overrule 4 True 3 False]

-- | …plus the mirror edge, so 3 and 4 defeat each other.
mutualDefeat :: [BOverrule]
mutualDefeat = defeatsOnly <> [overrule 3 False 4 True]

-- | A section whose own conclusion defeats itself: an odd loop.
selfDefeat :: [BOverrule]
selfDefeat = defeatsOnly <> [overrule 3 False 3 False]

overrule :: Int -> Bool -> Int -> Bool -> BOverrule
overrule dg dgSign dd ddSign =
  MkBOverrule
    { bovDefeating = bSec dg
    , bovDefeatingStmt = MkBConclusion {bcSign = dgSign, bcPred = bn "flies", bcArgs = [va]}
    , bovDefeated = bSec dd
    , bovDefeatedStmt = MkBConclusion {bcSign = ddSign, bcPred = bn "flies", bcArgs = [va]}
    , bovProv = Nothing
    }

rule :: Int -> Bool -> Text -> [BGoal] -> Bool -> BRule
rule s sign p conds defeasible =
  MkBRule
    { brSection = bSec s
    , brConclusion = MkBConclusion {bcSign = sign, bcPred = bn p, bcArgs = [va]}
    , brConditions = conds
    , brDefeasible = defeasible
    , brInapplicable = False
    , brProvenance = Nothing
    }

-- | The acyclic document plus one declared object and one test whose canvas
-- is the caller's.
docWithTest :: [BBlock] -> BlawxDoc
docWithTest stack =
  (baseDoc [sec1Ws, sec2Ws, sec3Ws defeatsOnly, sec4WsWithObject])
    { bdTests = [MkBTest {btName = "t", btStacks = [stack], btComment = Nothing, btProv = Nothing}]
    }

sec4WsWithObject :: BWorkspace
sec4WsWithObject =
  ws (bSec 4) (sec4Ws.bwStacks <> [[BDeclareObject (objDecl "pingu" "penguin")]])

-- | One declared atom and one that only a ground fact mentions.
docWithFactAtom :: BlawxDoc
docWithFactAtom =
  baseDoc
    [ sec1Ws
    , sec2Ws
    , sec3Ws defeatsOnly
    , ws
        (bSec 4)
        ( sec4Ws.bwStacks
            <> [ [BDeclareObject (objDecl "pingu" "penguin")]
               , [BFact True (bn "penguin") [BTAtom (bn "tweety")]]
               ]
        )
    ]

commentDoc :: BSectionRef -> Text -> BlawxDoc
commentDoc BRoot c =
  baseDoc
    [ sec1Ws
    , sec2Ws
    , sec3Ws defeatsOnly
    , sec4Ws
    , MkBWorkspace {bwName = BRoot, bwStacks = [], bwComment = Just c}
    ]
commentDoc _ c = baseDoc [sec1Ws {bwComment = Just c}, sec2Ws, sec3Ws defeatsOnly, sec4Ws]

-- | A comment on a workspace whose path is not rooted at a numbered section:
-- there is no § for it, so it must warn rather than vanish.
orphanCommentWs :: BWorkspace
orphanCommentWs =
  MkBWorkspace
    { bwName = BPath (mkStep "art" "II" :| [])
    , bwStacks = []
    , bwComment = Just "no § for this"
    }

-- | One section, one category, one boolean attribute the rule concludes, and
-- one attribute of the caller's value type.
valueDoc :: BValueType -> [BGoal] -> BlawxDoc
valueDoc ty conds =
  baseDoc
    [ ws
        (bSec 1)
        [ [ BDeclareCategory
              MkBCategoryDecl {bcName = bn "person", bcPrefix = "", bcPostfix = "is a person", bcProv = Nothing}
          , BDeclareAttribute (boolAttr "person" "bearded" "is bearded")
          , BDeclareAttribute (valueAttr "person" "hair" ty)
          ]
        , [BAttributedRule (rule 1 True "bearded" conds False)]
        ]
    ]

-- | @hair(A, L)@ — the binding goal.
attrGoal :: BGoal
attrGoal = BGCall True (bn "hair") [va, BTVar (MkBVar "L")]

-- | @blawx_comparison(L, op, rhs)@.
cmpGoal :: BCmpOp -> BTerm -> BGoal
cmpGoal op rhs = BGCompare op (BTVar (MkBVar "L")) rhs

-- | Two `attributed_rule`s in ONE section concluding ONE literal: separate
-- clauses of `according_to/3`, whose meaning is the disjunction.
twoClauseDoc :: BlawxDoc
twoClauseDoc =
  baseDoc
    [ ws
        (bSec 1)
        [ [ BDeclareCategory
              MkBCategoryDecl {bcName = bn "penguin", bcPrefix = "", bcPostfix = "is a penguin", bcProv = Nothing}
          , BDeclareCategory
              MkBCategoryDecl {bcName = bn "ostrich", bcPrefix = "", bcPostfix = "is an ostrich", bcProv = Nothing}
          , BDeclareCategory
              MkBCategoryDecl {bcName = bn "bird", bcPrefix = "", bcPostfix = "is a bird", bcProv = Nothing}
          ]
        , [BAttributedRule (rule 1 True "bird" [BGCall True (bn "penguin") [va]] False)]
        , [BAttributedRule (rule 1 True "bird" [BGCall True (bn "ostrich") [va]] False)]
        ]
    ]

-- | A rule attributed to @sec_1__para_a_section@, which R4's flat numbering
-- has no § for.
paragraphDoc :: BlawxDoc
paragraphDoc =
  baseDoc
    [ ws
        (bSec 1)
        [ [ BDeclareCategory
              MkBCategoryDecl {bcName = bn "penguin", bcPrefix = "", bcPostfix = "is a penguin", bcProv = Nothing}
          , BDeclareCategory
              MkBCategoryDecl {bcName = bn "bird", bcPrefix = "", bcPostfix = "is a bird", bcProv = Nothing}
          ]
        , [ BAttributedRule
              (rule 1 True "bird" [BGCall True (bn "penguin") [va]] False)
                {brSection = BPath (mkStep "sec" "1" :| [mkStep "para" "a"])}
          ]
        ]
    ]

-- | Two rules attributed to PARAGRAPHS of section 1 and drawn on their own
-- paragraph canvases, the way Blawx files them, plus an @overrules@ naming a
-- paragraph on the given side. The defeated conclusion is @sec_1__para_a@'s
-- @bird@; the defeater is @sec_1__para_b@'s @ostrich@.
paragraphDefeatWith :: BSectionRef -> BSectionRef -> BSectionRef -> [BWorkspace] -> BlawxDoc
paragraphDefeatWith drawnIn defeating defeated extra =
  baseDoc
    ( [ ws
          (bSec 1)
          [ [ BDeclareCategory
                MkBCategoryDecl {bcName = bn "penguin", bcPrefix = "", bcPostfix = "is a penguin", bcProv = Nothing}
            , BDeclareCategory
                MkBCategoryDecl {bcName = bn "ostrich", bcPrefix = "", bcPostfix = "is an ostrich", bcProv = Nothing}
            , BDeclareCategory
                MkBCategoryDecl {bcName = bn "bird", bcPrefix = "", bcPostfix = "is a bird", bcProv = Nothing}
            ]
          ]
      , paraRuleWs "a" True "bird"
      , paraRuleWs "b" False "ostrich"
      ]
        <> extra
        <> [ ws
               drawnIn
               [ [ BOverrules
                     MkBOverrule
                       { bovDefeating = defeating
                       , bovDefeatingStmt = MkBConclusion {bcSign = True, bcPred = bn "ostrich", bcArgs = [va]}
                       , bovDefeated = defeated
                       , bovDefeatedStmt = MkBConclusion {bcSign = True, bcPred = bn "bird", bcArgs = [va]}
                       , bovProv = Nothing
                       }
                 ]
               ]
           ]
    )

-- | One paragraph canvas carrying one rule attributed to that paragraph.
paraRuleWs :: Text -> Bool -> Text -> BWorkspace
paraRuleWs l defeasible concl =
  ws
    (para l)
    [ [ BAttributedRule
          (rule 1 True concl [BGCall True (bn "penguin") [va]] defeasible)
            {brSection = para l}
      ]
    ]

para :: Text -> BSectionRef
para l = BPath (mkStep "sec" "1" :| [mkStep "para" l])

-- | The sound shape: the `overrules` is drawn in the flat parent and names,
-- on both sides, the paragraph that actually carries the rule. The fold is
-- extension-preserving, so the defeat survives it.
paragraphDefeatDoc :: BlawxDoc
paragraphDefeatDoc = paragraphDefeatWith (bSec 1) (para "b") (para "a") []

-- | …plus a SIBLING paragraph concluding the same literal, which the fold
-- would sweep into the same defeat.
paragraphDefeatWideDoc :: BlawxDoc
paragraphDefeatWideDoc =
  paragraphDefeatWith (bSec 1) (para "b") (para "a") [paraRuleWs "c" True "bird"]

-- | The review counterexample's own shape: the DEFEATING pair is the flat
-- parent, which no rule is attributed to, so Blawx never fires the defeat.
paragraphDefeatInertDoc :: BlawxDoc
paragraphDefeatInertDoc = paragraphDefeatWith (bSec 1) (bSec 1) (para "a") []

-- | The `overrules` names a section the fold cannot place.
paragraphDefeatDocIn :: BSectionRef -> BlawxDoc
paragraphDefeatDocIn s' = paragraphDefeatWith (bSec 1) (para "b") s' []

-- | Two number-valued attributes, so a goal can test one against the other.
twoValueDoc :: [BGoal] -> BlawxDoc
twoValueDoc conds =
  baseDoc
    [ ws
        (bSec 1)
        [ [ BDeclareCategory
              MkBCategoryDecl {bcName = bn "person", bcPrefix = "", bcPostfix = "is a person", bcProv = Nothing}
          , BDeclareAttribute (boolAttr "person" "bearded" "is bearded")
          , BDeclareAttribute (valueAttr "person" "hair" BVNumber)
          , BDeclareAttribute (valueAttr "person" "nails" BVNumber)
          ]
        , [BAttributedRule (rule 1 True "bearded" conds False)]
        ]
    ]

-- | @nails(A, L)@ — the same value variable @attrGoal@ binds.
nailsGoal :: BGoal
nailsGoal = BGCall True (bn "nails") [va, BTVar (MkBVar "L")]

anon :: BTerm
anon = BTVar (MkBVar "_")

-- | A miniature of Jason Morris's Rock Paper Scissors Act s.4 — the shape W5
-- was sized on, and the smallest document carrying all four of its novelties:
-- a name declared at two arities (@player@ the category and @player@ the
-- attribute), a conclusion of arity two, a body-only variable, and a
-- @blawx_diseq@.
rpsShaped :: BlawxDoc
rpsShaped =
  (baseDoc [rpsWs])
    { bdName = "Rock Paper Scissors Act"
    , bdRuleText = MkBRuleText {brTitle = "Rock Paper Scissors Act", brSections = []}
    }

-- | 'rpsShaped' plus a second section whose rule has the same witness shape but
-- reads a DERIVED predicate (`winner`, which s.1 concludes) rather than only
-- input ones. That is the other side of the witness world parameter: here it
-- is read, so it is declared.
rpsChained :: BlawxDoc
rpsChained =
  (baseDoc [rpsWs, chainWs])
    { bdName = "Rock Paper Scissors Act"
    , bdRuleText = MkBRuleText {brTitle = "Rock Paper Scissors Act", brSections = []}
    }

chainWs :: BWorkspace
chainWs =
  ws
    (bSec 2)
    [ [catAttr "game" "champion" "player" BOrderOV "the champion of" "is" ""]
    , [ BAttributedRule
          MkBRule
            { brSection = bSec 2
            , brConclusion =
                MkBConclusion
                  { bcSign = True
                  , bcPred = bn "champion"
                  , bcArgs = [BTVar (MkBVar "Game"), BTVar (MkBVar "Player1")]
                  }
            , brConditions =
                [ BGCall True (bn "winner") [BTVar (MkBVar "Game"), BTVar (MkBVar "Player1")]
                , BGCall True (bn "player") [BTVar (MkBVar "Game"), BTVar (MkBVar "Player2")]
                , BGDiseq (BTVar (MkBVar "Player1")) (BTVar (MkBVar "Player2"))
                ]
            , brDefeasible = False
            , brInapplicable = False
            , brProvenance = Nothing
            }
      ]
    ]

rpsWs :: BWorkspace
rpsWs =
  ws
    (bSec 1)
    [ [ BDeclareCategory
          MkBCategoryDecl {bcName = bn "game", bcPrefix = "", bcPostfix = "is a game", bcProv = Nothing}
      , BDeclareCategory
          MkBCategoryDecl {bcName = bn "player", bcPrefix = "", bcPostfix = "is a player", bcProv = Nothing}
      , catAttr "game" "player" "player" BOrderVO "" "played in" ""
      , catAttr "game" "winner" "player" BOrderOV "the winner of" "is" ""
      ]
    , [ BAttributedRule
          MkBRule
            { brSection = bSec 1
            , brConclusion =
                MkBConclusion
                  { bcSign = True
                  , bcPred = bn "winner"
                  , bcArgs = [BTVar (MkBVar "Game"), BTVar (MkBVar "Player1")]
                  }
            , brConditions =
                [ BGCall True (bn "player") [BTVar (MkBVar "Game"), BTVar (MkBVar "Player1")]
                , BGCall True (bn "player") [BTVar (MkBVar "Game"), BTVar (MkBVar "Player2")]
                , BGDiseq (BTVar (MkBVar "Player1")) (BTVar (MkBVar "Player2"))
                ]
            , brDefeasible = False
            , brInapplicable = False
            , brProvenance = Nothing
            }
      ]
    ]

catAttr :: Text -> Text -> Text -> BNlgOrder -> Text -> Text -> Text -> BBlock
catAttr cat nm val order pre inf post =
  BDeclareAttribute
    MkBAttributeDecl
      { baCategory = bn cat
      , baName = bn nm
      , baType = BVCategory (bn val)
      , baOrder = order
      , baPrefix = pre
      , baInfix = inf
      , baPostfix = post
      , baProv = Nothing
      }

objDecl :: Text -> Text -> BObjectDecl
objDecl n cat =
  MkBObjectDecl
    { bodName = bn n
    , bodCategory = bn cat
    , bodPrefix = ""
    , bodPostfix = ""
    , bodMutNlg = Nothing
    , bodProv = Nothing
    }

q :: BBlock
q = BQuery [BGCall True (bn "flies") [BTAtom (bn "pingu")]]

va :: BTerm
va = BTVar (MkBVar "A")

ws :: BSectionRef -> [[BBlock]] -> BWorkspace
ws n stacks = MkBWorkspace {bwName = n, bwStacks = stacks, bwComment = Nothing}

boolAttr :: Text -> Text -> Text -> BAttributeDecl
boolAttr cat nm post =
  MkBAttributeDecl
    { baCategory = bn cat
    , baName = bn nm
    , baType = BVBoolean
    , baOrder = BOrderOV
    , baPrefix = ""
    , baInfix = ""
    , baPostfix = post
    , baProv = Nothing
    }

valueAttr :: Text -> Text -> BValueType -> BAttributeDecl
valueAttr cat nm ty =
  (boolAttr cat nm "mm in length") {baType = ty, baInfix = "'s facial hair is"}

bn :: Text -> BName
bn t = fromMaybe (error ("not a Blawx atom: " <> Text.unpack t)) (mkBName Nothing t)

mkStep :: Text -> Text -> BStep
mkStep k l = fromMaybe (error "bad BStep") (mkBStep k l)
