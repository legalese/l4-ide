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

    it "refuses a block the #EVAL rendering does not consume, by name" $
      refusalsOf (docWithTest [BDeclareObject (objDecl "socrates" "penguin"), q])
        `shouldSatisfy` anyMentioning "blawx-lift/test-block"

    it "refuses a NEGATIVE scenario fact rather than dropping it" $
      refusalsOf (docWithTest [BFact False (bn "penguin") [BTAtom (bn "pingu")], q])
        `shouldSatisfy` anyMentioning "blawx-lift/test-block"

    it "refuses a scenario fact about an undeclared predicate" $
      refusalsOf (docWithTest [BFact True (bn "nosuch") [BTAtom (bn "pingu")], q])
        `shouldSatisfy` anyMentioning "blawx-lift/scenario-undeclared"

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
