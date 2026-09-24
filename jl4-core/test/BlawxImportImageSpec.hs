{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Byte-exactness specs for the __P5 import extension__ of the Blawx block IR
-- (BLAWX-EXPORT-SPEC §10 P5, ruling P5-1): the constructors that carry the
-- defeat\/applicability layer, and the two images each one owes.
--
-- The corpus goldens cannot cover any of this. Every new constructor is
-- unreachable from "L4.Blawx.Lower" — that unreachability is precisely what
-- keeps the P1\/P3 goldens byte-identical — so the only way to hold the new
-- renderer arms to evidence is to build the IR values by hand and assert the
-- bytes.
--
-- __Where the expected bytes come from.__ Not from this file's opinion: the
-- two large fixtures are Blawx's own shipped @bird.yaml@
-- (@blawx\/static\/blawx\/examples\/bird.yaml@ at checkout @02eded1@) — its
-- @sec_5__span_pingu_section@ and @sec_5_section@ workspaces, reproduced as IR
-- and asserted against the @scasp_encoding@ and @xml_content@ that file
-- stores. Everything else is transcribed from @scasp_generator.js@ with the
-- line cited at the assertion.
--
-- __One deliberate divergence from bird's stored bytes__, asserted here so it
-- is a recorded decision rather than a surprise: the applicability guard of an
-- @inapplicable@ rule goes AFTER the condition it belongs to. It went before
-- all of them until Blawx commit @c9195be@ (\"change order of applies
-- clauses\", 2023-09-21), and bird's stored @sec_5@ encoding predates that
-- commit. R10 pins us to the generator source, so we follow the generator and
-- bird's stored text is one of the stale encodings ruling P5-2 warns about.
-- The XML — which the editor regenerates FROM — matches exactly.
module BlawxImportImageSpec (spec) where

import Test.Hspec

import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as Text

import L4.Blawx.Emit (renderBlock, renderGoal, renderWorkspaceScasp)
import L4.Blawx.EmitXml (BlawxXml (..), renderDocXml)
import L4.Blawx.IR

spec :: Spec
spec = do
  describe "BSectionRef" $ do
    -- The P1/P3 byte gate, stated rather than believed: the path form must
    -- render the flat case exactly as the retired @BSec Int@ did.
    it "renders bSec byte-identically to the retired BSec constructor" $
      mapM_
        (\i -> renderSectionRef (bSec i) `shouldBe` "sec_" <> tshow i <> "_section")
        [1 :: Int, 2, 7, 42, 110]
    it "renders the root" $
      renderSectionRef BRoot `shouldBe` "root_section"
    it "renders a span path (bird's own workspace name)" $
      renderSectionRef spanRef `shouldBe` "sec_5__span_pingu_section"
    it "renders a four-deep hierarchical path" $
      renderSectionRef deepRef `shouldBe` "sec_34__subsec_1__para_b__subpara_i_section"

    -- renderDocAtom is the s(CASP)-side spelling (doc_selector lowercases,
    -- scasp_generator.js:264-270). It must be the IDENTITY on everything
    -- Mode-A export builds, or a golden moves.
    it "renderDocAtom is the identity on every Mode-A reference" $
      mapM_
        (\r -> renderDocAtom r `shouldBe` renderSectionRef r)
        (BRoot : map bSec [1 :: Int .. 20])
    it "renderDocAtom lowercases an imported span whose label carries a capital" $
      renderDocAtom (BPath (step "sec" "5" :| [step "span" "Pingu"]))
        `shouldBe` "sec_5__span_pingu_section"

  describe "mkBStep" $ do
    it "accepts the measured kinds" $
      mapM_
        (\(k, l) -> mkBStep k l `shouldSatisfy` isJust')
        [("sec", "5"), ("span", "pingu"), ("subpara", "i"), ("sched", "2a")]
    -- Each rejection is a name that would NOT survive the round trip: the
    -- rendered form re-splits into different components.
    it "rejects a label containing __" $ mkBStep "span" "a__b" `shouldSatisfy` isNothing'
    it "rejects a label bounded by _" $ do
      mkBStep "span" "_a" `shouldSatisfy` isNothing'
      mkBStep "span" "a_" `shouldSatisfy` isNothing'
    it "rejects a kind containing _" $ mkBStep "sub_sec" "1" `shouldSatisfy` isNothing'
    it "rejects empties" $ do
      mkBStep "" "1" `shouldSatisfy` isNothing'
      mkBStep "sec" "" `shouldSatisfy` isNothing'

  describe "deconstructTerm" $ do
    -- scasp_generator.js:1542-1554, arm by arm.
    it "splits a unary application" $
      deconstructTerm "flies(pingu)" `shouldBe` ["flies", "pingu"]
    it "keeps the Blockly statement indent in the functor (the caller trims)" $
      deconstructTerm "  -flies(A)" `shouldBe` ["  -flies", "A"]
    it "splits bird's negated applies goal" $
      deconstructTerm "-blawx_applies(sec_5_section,pingu)"
        `shouldBe` ["-blawx_applies", "sec_5_section", "pingu"]
    -- The limit that makes holds/1 possible: no parens, no elements.
    it "returns nothing at all for a paren-free term" $
      deconstructTerm "penguin" `shouldBe` []
    it "recovers exactly one level of nesting" $
      deconstructTerm "f(g(1),2)" `shouldBe` ["f", "g(1)", "2"]
    it "is greedy to the last close paren" $
      deconstructTerm "f(a,b)" `shouldBe` ["f", "a", "b"]
    -- The cross-check the plan asks for: the regex mirror and the STRUCTURAL
    -- flattener that L4.Blawx.Emit.ruleTriple uses (and that four goldens
    -- freeze) must agree on every conclusion shape Lower can reach. They are
    -- separate code on purpose — a golden must not depend on a regex mirror —
    -- so the agreement is asserted instead of assumed.
    it "agrees with the structural flattener on every Lower-reachable shape" $
      mapM_ agreesWithStructural
        [ (True, "flies", [BTVar (MkBVar "A")])
        , (False, "flies", [BTVar (MkBVar "A")])
        , (True, "benefit_amount", [BTVar (MkBVar "P"), BTNum 1000])
        , (False, "eligible", [BTAtom (bn "pingu")])
        , (True, "rel", [BTVar (MkBVar "A"), BTVar (MkBVar "B"), BTAtom (bn "c")])
        , (True, "holds_list", [BTNil])
        ]

  describe "mkBGNegated" $ do
    -- Without the normalisation the P3 seeds would emit one form and Parse
    -- would rebuild the other, and lift . emit = id would fail on documents
    -- that are byte-identical.
    it "normalises classical negation of a plain call to BGCall False" $
      mkBGNegated BNegClassical (BGCall True (bn "flies") [v "A"])
        `shouldBe` BGCall False (bn "flies") [v "A"]
    it "normalises default negation of a plain call to BGNaf" $
      mkBGNegated BNegDefault (BGCall True (bn "flies") [v "A"])
        `shouldBe` BGNaf (bn "flies") [v "A"]
    it "keeps the general wrapper when the payload has no other spelling" $
      mkBGNegated BNegDefault (mkBGNegated BNegClassical appliesA)
        `shouldBe` BGNegated BNegDefault (BGNegated BNegClassical appliesA)
    it "never yields a wrapper around a plain positive call" $
      mapM_
        (\k -> mkBGNegated k (BGCall True (bn "p") [v "X"]) `shouldSatisfy` notWrapped)
        [BNegClassical, BNegDefault]

  describe "mkBAssertGoal" $ do
    it "admits the fact-position defeat goals" $
      mapM_
        (\g -> mkBAssertGoal g `shouldSatisfy` isJustBlock)
        [ BGHolds spanRef appliesA
        , BGAccordingTo (bSec 5) appliesA
        , appliesA
        , BGNegated BNegClassical appliesA
        ]
    -- BGCall's fact spelling is BFact; admitting it here would give one
    -- byte-image two IR spellings.
    it "rejects a goal that already has a block spelling" $ do
      mkBAssertGoal (BGCall True (bn "p") [v "X"]) `shouldSatisfy` isNothingBlock
      mkBAssertGoal (BGCall False (bn "p") [v "X"]) `shouldSatisfy` isNothingBlock
    it "rejects a condition-position goal" $
      mkBAssertGoal (BGUnify (v "X") (v "Y")) `shouldSatisfy` isNothingBlock

  describe "chainKind and blockRuns" $ do
    -- The byte gate again: on the pre-extension constructors the three-valued
    -- kind must reproduce the retired two-valued predicate exactly, because
    -- the run partition decides blank lines in renderScasp and root <block>
    -- boundaries in renderDocXml.
    it "reproduces the retired chains predicate on the pre-P5 constructors" $
      mapM_
        (\(b, k) -> chainKind b `shouldBe` k)
        [ (BFact True (bn "p") [v "X"], BChainMid)
        , (BConstraint [], BChainNone)
        , (BAbducible (bn "p") [v "X"], BChainNone)
        , (BQuery [], BChainNone)
        ]
    -- overrules declares previousStatement "OUTER" and NO nextStatement
    -- (blawx-blocks.js:386-425); a run may therefore END with one and must
    -- not continue past it.
    it "terminates a run at an overrules block" $
      blockRuns [aFact, anOverrules, aFact]
        `shouldBe` [BRunMembers [aFact, anOverrules], BRunMembers [aFact]]
    it "makes a lone overrules its own single-member run" $
      blockRuns [anOverrules] `shouldBe` [BRunMembers [anOverrules]]

  describe "the unattributed_rule join" $ do
    -- Two separate facts, kept separately testable on purpose.
    it "renderBlock keeps the generator's literal \" :- \\n\" (trailing space)" $
      renderBlock (BUnattributedRule appliesDefault)
        `shouldBe` "blawx_applies(sec_5_section,A) :- \nnot -blawx_applies(sec_5_section,A)."
    it "the workspace-level render scrubs it, as Blockly's workspaceToCode does" $
      renderWorkspaceScasp (ws (bSec 5) [[BUnattributedRule appliesDefault]])
        `shouldBe` "blawx_applies(sec_5_section,A) :-\nnot -blawx_applies(sec_5_section,A)."

  describe "the fact-position arms" $ do
    it "images object_declaration as category(object)" $
      renderBlock (BDeclareObject pinguDecl) `shouldBe` "penguin(pingu)."
    -- overrules writes the comma after the section ref UNCONDITIONALLY, before
    -- its loop (generator :272-295) — unlike holds/according_to, which build
    -- one list and join it. Both quirks are reproduced, not repaired.
    it "images an overrules edge" $
      renderBlock (BOverrules birdOverrule)
        `shouldBe` "blawx_defeated(sec_3_section,-flies,A) :- holds(sec_5_section,flies,A)."
    it "flattens a holds payload into the argument list, one level" $
      renderGoal (BGHolds spanRef (BGNegated BNegClassical appliesPingu))
        `shouldBe` "holds(sec_5__span_pingu_section,-blawx_applies,sec_5_section,pingu)"
    it "flattens an according_to payload the same way" $
      renderGoal (BGAccordingTo (bSec 5) (BGCall True (bn "flies") [v "A"]))
        `shouldBe` "according_to(sec_5_section,flies,A)"
    it "images applies" $
      renderGoal appliesPingu `shouldBe` "blawx_applies(sec_5_section,pingu)"
    it "images new_object_category identically to a plain call" $
      renderGoal (BGNewObjectCategory (bn "penguin") (v "A"))
        `shouldBe` renderGoal (BGCall True (bn "penguin") [v "A"])
    it "images the query separator as \", \", not \",\\n\"" $
      renderBlock (BQuery [BGNaf (bn "flies") [BTAtom (bn "pingu")], appliesPingu])
        `shouldBe` "?- not flies(pingu), blawx_applies(sec_5_section,pingu)."

  -- -------------------------------------------------------------------------
  -- The two whole-workspace fixtures, straight out of bird.yaml
  -- -------------------------------------------------------------------------

  describe "bird sec_5__span_pingu_section" $ do
    it "regenerates the stored scasp_encoding byte for byte" $
      renderWorkspaceScasp spanWs
        `shouldBe` "penguin(pingu).\nholds(sec_5__span_pingu_section,-blawx_applies,sec_5_section,pingu)."
    -- Modulo block ids and canvas coordinates, which the P5 brief names as the
    -- round-trip tolerances: bird's ids are 20-char Blockly gensyms and ours
    -- are the deterministic l4b counter.
    it "regenerates the stored xml_content modulo ids and layout" $
      normXml (row0 spanDoc) `shouldBe` normXml "<xml xmlns=\"https://developers.google.com/blockly/xml\"><block type=\"unattributed_fact\"><statement name=\"statements\"><block type=\"object_declaration\"><mutation xmlns=\"http://www.w3.org/1999/xhtml\" category_name=\"penguin\" prefix=\"null\" postfix=\"null\"></mutation><field name=\"prefix\"></field><field name=\"object_name\">pingu</field><field name=\"postfix\">is a penguin</field><next><block type=\"holds\"><value name=\"section\"><block type=\"doc_selector\"><mutation xmlns=\"http://www.w3.org/1999/xhtml\" section_reference=\"sec_5__span_pingu_section\"></mutation><field name=\"doc_part_name\">NBA 5pingu</field></block></value><statement name=\"statement\"><block type=\"logical_negation\"><statement name=\"negated_statement\"><block type=\"applies\"><value name=\"applicable_rule\"><block type=\"doc_selector\"><mutation xmlns=\"http://www.w3.org/1999/xhtml\" section_reference=\"sec_5_section\"></mutation><field name=\"doc_part_name\">NBA 5</field></block></value><value name=\"object\"><block type=\"object_selector\"><mutation xmlns=\"http://www.w3.org/1999/xhtml\" objectname=\"pingu\"></mutation><field name=\"object_name\">pingu</field></block></value></block></statement></block></statement></block></next></block></statement></block></xml>"

  describe "bird sec_5_section (its three non-declaration roots)" $ do
    it "regenerates the stored scasp_encoding, bar the c9195be reordering" $
      renderWorkspaceScasp (sec5Ws) `shouldBe` sec5Scasp
    it "regenerates the stored xml_content modulo ids and layout" $
      normXml (rowN 1 sec5Doc) `shouldBe` normXml "<xml xmlns=\"https://developers.google.com/blockly/xml\"><block type=\"unattributed_fact\"><statement name=\"statements\"><block type=\"overrules\"><value name=\"defeating_rule\"><block type=\"doc_selector\"><mutation xmlns=\"http://www.w3.org/1999/xhtml\" section_reference=\"sec_5_section\"></mutation><field name=\"doc_part_name\">NBA 5</field></block></value><statement name=\"defeating_statement\"><block type=\"unary_attribute_selector\"><mutation xmlns=\"http://www.w3.org/1999/xhtml\" attributename=\"flies\" attributetype=\"boolean\"></mutation><field name=\"prefix\"></field><field name=\"postfix\">can fly</field><value name=\"first_element\"><block type=\"variable\"><field name=\"variable_name\">A</field></block></value></block></statement><value name=\"defeated_rule\"><block type=\"doc_selector\"><mutation xmlns=\"http://www.w3.org/1999/xhtml\" section_reference=\"sec_3_section\"></mutation><field name=\"doc_part_name\">NBA 3</field></block></value><statement name=\"defeated_statement\"><block type=\"logical_negation\"><statement name=\"negated_statement\"><block type=\"unary_attribute_selector\"><mutation xmlns=\"http://www.w3.org/1999/xhtml\" attributename=\"flies\" attributetype=\"boolean\"></mutation><field name=\"prefix\"></field><field name=\"postfix\">can fly</field><value name=\"first_element\"><block type=\"variable\"><field name=\"variable_name\">A</field></block></value></block></statement></block></statement></block></statement></block><block type=\"unattributed_rule\"><statement name=\"conditions\"><block type=\"default_negation\"><statement name=\"default_negated_statement\"><block type=\"logical_negation\"><statement name=\"negated_statement\"><block type=\"applies\"><value name=\"applicable_rule\"><block type=\"doc_selector\"><mutation xmlns=\"http://www.w3.org/1999/xhtml\" section_reference=\"sec_5_section\"></mutation><field name=\"doc_part_name\">NBA 5</field></block></value><value name=\"object\"><block type=\"variable\"><field name=\"variable_name\">A</field></block></value></block></statement></block></statement></block></statement><statement name=\"conclusion\"><block type=\"applies\"><value name=\"applicable_rule\"><block type=\"doc_selector\"><mutation xmlns=\"http://www.w3.org/1999/xhtml\" section_reference=\"sec_5_section\"></mutation><field name=\"doc_part_name\">NBA 5</field></block></value><value name=\"object\"><block type=\"variable\"><field name=\"variable_name\">A</field></block></value></block></statement></block><block type=\"attributed_rule\"><field name=\"defeasible\">FALSE</field><field name=\"inapplicable\">TRUE</field><statement name=\"conditions\"><block type=\"new_object_category\"><mutation xmlns=\"http://www.w3.org/1999/xhtml\" category_name=\"penguin\"></mutation><field name=\"category_name\">penguin</field><value name=\"object\"><block type=\"variable\"><field name=\"variable_name\">A</field></block></value><next><block type=\"unary_attribute_selector\"><mutation xmlns=\"http://www.w3.org/1999/xhtml\" attributename=\"cartoon_jetpack\" attributetype=\"boolean\"></mutation><field name=\"prefix\"></field><field name=\"postfix\">is a cartoon with a jetpack</field><value name=\"first_element\"><block type=\"variable\"><field name=\"variable_name\">A</field></block></value></block></next></block></statement><value name=\"source\"><block type=\"doc_selector\"><mutation xmlns=\"http://www.w3.org/1999/xhtml\" section_reference=\"sec_5_section\"></mutation><field name=\"doc_part_name\">NBA 5</field></block></value><statement name=\"conclusion\"><block type=\"unary_attribute_selector\"><mutation xmlns=\"http://www.w3.org/1999/xhtml\" attributename=\"flies\" attributetype=\"boolean\"></mutation><field name=\"prefix\"></field><field name=\"postfix\">can fly</field><value name=\"first_element\"><block type=\"variable\"><field name=\"variable_name\">A</field></block></value></block></statement></block></xml>"

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

-- | bird's own document, in the two shapes the assertions need.
spanDoc :: BlawxDoc
spanDoc =
  emptyDoc
    { bdWorkspaces = [spanWs]
    , -- The one datum a computed label cannot invent: bird wrote "NBA 5pingu",
      -- not "NBA 5 pingu". This is what bdDocPartNames exists for.
      bdDocPartNames = Map.fromList [(spanRef, "NBA 5pingu")]
    }

spanWs :: BWorkspace
spanWs = ws spanRef [[BDeclareObject pinguDecl, BAssertGoal spanHolds]]

spanHolds :: BGoal
spanHolds = BGHolds spanRef (mkBGNegated BNegClassical appliesPingu)

pinguDecl :: BObjectDecl
pinguDecl =
  MkBObjectDecl
    { bodName = bn "pingu"
    , bodCategory = bn "penguin"
    , bodPrefix = ""
    , bodPostfix = "is a penguin"
    , -- bird stores the literal string "null" for both, which is what an
      -- absent mutation attribute round-trips to.
      bodMutNlg = Nothing
    , bodProv = Nothing
    }

-- | The declarations exist only so the symbol table gives @flies@ and
-- @cartoon_jetpack@ the prefix\/postfix bird's selectors carry; they sit in
-- @root_section@, which no assertion looks at.
sec5Doc :: BlawxDoc
sec5Doc = emptyDoc {bdWorkspaces = [declWs, sec5Ws]}

declWs :: BWorkspace
declWs =
  ws BRoot [[BDeclareAttribute (boolAttr "thing" "flies" "can fly")
            , BDeclareAttribute (boolAttr "penguin" "cartoon_jetpack" "is a cartoon with a jetpack")]]

sec5Ws :: BWorkspace
sec5Ws =
  ws
    (bSec 5)
    [ [BOverrules birdOverrule]
    , [BUnattributedRule appliesDefault]
    , [BAttributedRule jetpackRule]
    ]

-- | @Despite 3, cartoon penguins with jetpacks can fly@ — bird's section 5,
-- @inapplicable@ ticked, which is the whole point of the fixture.
jetpackRule :: BRule
jetpackRule =
  MkBRule
    { brSection = bSec 5
    , brConclusion = MkBConclusion {bcSign = True, bcPred = bn "flies", bcArgs = [v "A"]}
    , brConditions =
        [ BGNewObjectCategory (bn "penguin") (v "A")
        , BGCall True (bn "cartoon_jetpack") [v "A"]
        ]
    , brDefeasible = False
    , brInapplicable = True
    , brProvenance = Nothing
    }

birdOverrule :: BOverrule
birdOverrule =
  MkBOverrule
    { bovDefeating = bSec 5
    , bovDefeatingStmt = MkBConclusion {bcSign = True, bcPred = bn "flies", bcArgs = [v "A"]}
    , bovDefeated = bSec 3
    , bovDefeatedStmt = MkBConclusion {bcSign = False, bcPred = bn "flies", bcArgs = [v "A"]}
    , bovProv = Nothing
    }

-- | The closed-world applicability default: @applies unless it does not@.
appliesDefault :: BURule
appliesDefault =
  MkBURule
    { burConclusion = [appliesA]
    , burConditions = [mkBGNegated BNegDefault (mkBGNegated BNegClassical appliesA)]
    , burProv = Nothing
    }

appliesA, appliesPingu :: BGoal
appliesA = BGApplies (bSec 5) (v "A")
appliesPingu = BGApplies (bSec 5) (BTAtom (bn "pingu"))

sec5Scasp :: Text
sec5Scasp =
  Text.intercalate
    "\n"
    [ "blawx_defeated(sec_3_section,-flies,A) :- holds(sec_5_section,flies,A)."
    , ""
    , "blawx_applies(sec_5_section,A) :-"
    , "not -blawx_applies(sec_5_section,A)."
    , ""
    , -- POST-c9195be: the guard follows its condition. bird's stored text has
      -- it first; see the module header.
      "according_to(sec_5_section,flies,A) :- penguin(A),"
    , "blawx_applies(sec_5_section,A),"
    , "cartoon_jetpack(A)."
    , ""
    , "% BLAWX CHECK DUPLICATES"
    , "holds(sec_5_section,flies,A) :- according_to(sec_5_section,flies,A)."
    , ""
    , "% BLAWX CHECK DUPLICATES"
    , "  flies(A) :- holds(sec_5_section,flies,A)."
    ]

spanRef, deepRef :: BSectionRef
spanRef = BPath (step "sec" "5" :| [step "span" "pingu"])
deepRef =
  BPath (step "sec" "34" :| [step "subsec" "1", step "para" "b", step "subpara" "i"])

aFact, anOverrules :: BBlock
aFact = BFact True (bn "penguin") [BTAtom (bn "pingu")]
anOverrules = BOverrules birdOverrule

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

emptyDoc :: BlawxDoc
emptyDoc =
  MkBlawxDoc
    { bdName = "New Bird Act"
    , bdRuleText = MkBRuleText {brTitle = "New Bird Act", brSections = []}
    , bdWorkspaces = []
    , bdTests = []
    , bdDocPartNames = mempty
    }

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
    , baInfix = "'s attribute name is"
    , baPostfix = post
    , baProv = Nothing
    }

bn :: Text -> BName
bn t = fromMaybe (error ("not a Blawx atom: " <> Text.unpack t)) (mkBName Nothing t)

v :: Text -> BTerm
v = BTVar . MkBVar

step :: Text -> Text -> BStep
step k l = fromMaybe (error "bad BStep") (mkBStep k l)

tshow :: Int -> Text
tshow = Text.pack . show

isJust', isNothing' :: Maybe BStep -> Bool
isJust' = maybe False (const True)
isNothing' = maybe True (const False)

isJustBlock, isNothingBlock :: Maybe BBlock -> Bool
isJustBlock = maybe False (const True)
isNothingBlock = maybe True (const False)

notWrapped :: BGoal -> Bool
notWrapped = \case
  BGNegated _ (BGCall True _ _) -> False
  _ -> True

-- | The structural flattener L4.Blawx.Emit.ruleTriple uses, restated here only
-- to compare against; @renderGoal (BGCall …)@ produces exactly the text the
-- generator hands to @deconstruct_term@.
agreesWithStructural :: (Bool, Text, [BTerm]) -> Expectation
agreesWithStructural (sign, p, args) =
  deconstructTerm (renderGoal (BGCall sign (bn p) args))
    `shouldBe` ((if sign then "" else "-") <> p) : map renderTerm args

-- | Compare emitted XML against bird's stored XML modulo the two documented
-- round-trip tolerances — block ids (bird's are 20-char Blockly gensyms, ours
-- a deterministic counter) and canvas coordinates — plus our inter-root
-- newlines, which @domToWorkspace@ skips as non-element children of @\<xml\>@.
normXml :: Text -> Text
normXml = Text.filter (/= '\n') . dropAttr "id" . dropAttr "x" . dropAttr "y"
 where
  dropAttr name t = case Text.breakOn (" " <> name <> "=\"") t of
    (pre, rest)
      | Text.null rest -> pre
      | otherwise ->
          let afterOpen = Text.drop (Text.length name + 3) rest
          in  pre <> dropAttr name (Text.drop 1 (Text.dropWhile (/= '"') afterOpen))

row0 :: BlawxDoc -> Text
row0 = rowN 0

rowN :: Int -> BlawxDoc -> Text
rowN i doc = case drop i (renderDocXml doc).bxWorkspaces of
  r : _ -> r
  [] -> error "no such workspace row"
