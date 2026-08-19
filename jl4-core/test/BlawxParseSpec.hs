{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Specs for the __import__ layers (BLAWX-EXPORT-SPEC §8.14 R14, §10 P5):
-- the Blockly-subset XML recogniser, the block-tree shaping, and the
-- classification back into the block IR.
--
-- __What the corpus goldens cannot cover, and why this file exists.__ The
-- four P1\/P3 seeds do round-trip end to end — @jl4\/tests-cli@ runs
-- @l4 blawx --roundtrip@ over each of them, through the YAML layer as well —
-- but "L4.Blawx.Lower" constructs NONE of the P5 extension constructors, so
-- no seed exercises @object_declaration@, @overrules@, @unattributed_rule@,
-- @applies@, @holds@, @according_to@, @new_object_category@ or the
-- @inapplicable@ checkbox. Those are built here by hand and round-tripped.
--
-- The XML specs are the layer under that property: @parseXml . renderNode ≡
-- Right@ localises a whole class of failure to one module, and each tolerance
-- and each refusal is stated separately because they are the measured
-- boundary of the subset, not a matter of taste.
module BlawxParseSpec (spec) where

import Test.Hspec

import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as Text

import L4.Blawx.Blocks
import L4.Blawx.Emit (renderRuleText, renderTestScasp, renderWorkspaceScasp)
import L4.Blawx.EmitXml (BlawxXml (..), renderDocXml)
import L4.Blawx.IR
import L4.Blawx.Parse
import L4.Blawx.Xml

spec :: Spec
spec = do
  describe "parseXml" $ do
    -- XML1, the property under `lift . emit = id`.
    it "is the inverse of renderNode on every row EmitXml emits" $
      mapM_ reparses (rowTexts extensionDoc)

    it "skips inter-tag whitespace without treating it as text" $ do
      let t = "<xml xmlns=\"u\">\n<block type=\"a\"></block>\n<block type=\"b\"></block>\n</xml>"
      fmap kidCount (parseXml t) `shouldBe` Right 2

    -- Our own escapers emit these; the wild corpus never does, which is
    -- exactly why they need a test rather than a corpus row.
    it "decodes the numeric character references escapeText and escapeAttr emit" $ do
      fieldText "<xml xmlns=\"u\"><field name=\"f\">a&#13;b&#x41;</field></xml>"
        `shouldBe` Right "a\rbA"
      attrOf "k" "<xml xmlns=\"u\" k=\"a&#10;b&#9;c\"></xml>" `shouldBe` Right "a\nb\tc"
    it "decodes the five named entities" $
      fieldText "<xml xmlns=\"u\"><field name=\"f\">&amp;&lt;&gt;&quot;&apos;</field></xml>"
        `shouldBe` Right "&<>\"'"

    -- XML 1.0 attribute-value normalisation: a LITERAL tab or newline becomes
    -- a space, a character reference does not. EmitXml escapes precisely those
    -- characters because of this rule.
    it "normalises literal whitespace in an attribute value but not a reference" $
      attrOf "k" "<xml xmlns=\"u\" k=\"a\tb\nc\"></xml>" `shouldBe` Right "a b c"
    it "end-of-line normalises CRLF and a lone CR" $
      fieldText "<xml xmlns=\"u\"><field name=\"f\">a\r\nb\rc</field></xml>"
        `shouldBe` Right "a\nb\nc"

    -- A tolerant-subset reader is only safe if it refuses what it does not
    -- model. Each of these would otherwise be a silent mis-parse of a rule.
    it "refuses everything outside the Blockly subset, by name" $
      mapM_
        (\(what, t) -> case parseXml t of
            Left _ -> pure ()
            Right _ -> expectationFailure ("expected a refusal for " <> what))
        [ ("XML declaration" :: String, "<?xml version=\"1.0\"?><xml xmlns=\"u\"></xml>")
        , ("DOCTYPE", "<!DOCTYPE xml><xml xmlns=\"u\"></xml>")
        , ("CDATA", "<xml xmlns=\"u\"><field name=\"f\"><![CDATA[x]]></field></xml>")
        , ("single-quoted attribute", "<xml xmlns='u'></xml>")
        , ("unknown entity", "<xml xmlns=\"u\"><field name=\"f\">&nbsp;</field></xml>")
        , ("mismatched close tag", "<xml xmlns=\"u\"><block type=\"a\"></value></xml>")
        , ("unclosed tag", "<xml xmlns=\"u\"><block type=\"a\">")
        , ("text outside field/comment", "<xml xmlns=\"u\">hello</xml>")
        , ("trailing content", "<xml xmlns=\"u\"></xml><xml xmlns=\"u\"></xml>")
        ]
    it "reports an offset and both tag names on a mismatch" $
      case parseXml "<xml xmlns=\"u\"><block type=\"a\"></value></xml>" of
        Left e -> do
          renderXmlError e `shouldSatisfy` Text.isInfixOf "</value>"
          renderXmlError e `shouldSatisfy` Text.isInfixOf "</block>"
        Right _ -> expectationFailure "expected a refusal"

  describe "toBlockTrees" $ do
    it "flattens a <next> chain into the enclosing statement list" $
      fmap (map (\b -> b.btType) . stmtOf "statements") (firstBlock chainXml)
        `shouldBe` Right ["new_category_declaration", "new_category_declaration"]

    -- Ruling P5-3, and Blockly's own Generator.blockToCode: the disabled block
    -- goes, its successors stay.
    it "skips a disabled block, splices its next chain, and says which" $ do
      fmap (map (\b -> b.btType) . fst) (blocks disabledXml) `shouldBe` Right ["b"]
      fmap (map renderBlockWarning . snd) (blocks disabledXml)
        `shouldBe` Right ["skipped disabled <a> at (5,-7)"]

    it "drops the menu caches and the namespace re-declaration at the boundary" $
      fmap (\b -> b.btMutation) (firstBlock menuCacheXml)
        `shouldBe` Right [("category_name", "person")]

    it "reads x/y only where they occur, and accepts negatives" $ do
      fmap (\b -> b.btPos) (firstBlock disabledXml) `shouldBe` Right (Just (40, 3))
      fmap (\b -> b.btPos) (firstBlock chainXml) `shouldBe` Right Nothing

    it "keeps a <comment>'s newlines (P5-4)" $
      fmap (\b -> b.btComment) (firstBlock commentXml) `shouldBe` Right (Just "one\ntwo")

  describe "the inverse pairs" $ do
    it "parseSectionName inverts renderSectionRef" $
      mapM_
        (\r -> parseSectionName (renderSectionRef r) `shouldBe` Just r)
        [BRoot, bSec 1, bSec 42, spanRef, deepRef]
    it "refuses a workspace name that is not AKN-shaped" $
      mapM_
        (\n -> parseSectionName n `shouldBe` Nothing)
        ["sec1_section", "root", "sec_1", "", "_section"]

    it "parseTermText inverts renderTerm" $
      mapM_
        (\t -> parseTermText (renderTerm t) `shouldBe` Just t)
        [ BTAtom (bn "pingu")
        , BTVar (MkBVar "X")
        , BTVar (MkBVar "_")
        , BTNum 5
        , BTNum (-3)
        , BTNil
        , BTCons (BTNum 1) (BTCons (BTNum 0) BTNil)
        , BTCons (BTVar (MkBVar "X")) (BTVar (MkBVar "Rest"))
        ]
    it "refuses a label that is not a term" $
      mapM_ (\t -> parseTermText t `shouldBe` Nothing) ["NBA 5", "[1 | ", "1 2", ""]

    it "parseRuleText inverts renderRuleText" $
      mapM_
        (\rt -> renderRuleText (parseRuleText (renderRuleText rt)) `shouldBe` renderRuleText rt)
        [ MkBRuleText {brTitle = "Mortality", brSections = []}
        , MkBRuleText
            { brTitle = "Mortality"
            , brSections =
                [ MkBSection {bsNumber = 1, bsText = "Definition of is mortal."}
                , MkBSection {bsNumber = 2, bsText = "Another."}
                ]
            }
        ]
    -- Prose a human edited is not our business to refuse: an un-numbered
    -- remainder stays in the title, which re-renders byte-identically.
    it "keeps prose it cannot parse rather than refusing the document" $
      renderRuleText (parseRuleText wildProse) `shouldBe` wildProse

  describe "emit -> parse over the P5 extension constructors" $ do
    -- The property R14 states, on the half of the IR that Mode-A export
    -- cannot reach and therefore that no golden covers.
    it "reproduces the document structurally" $
      case fst (parseBlawx (sourceOf extensionDoc)) of
        Nothing -> expectationFailure "the extension document did not parse"
        Just doc' -> norm doc' `shouldBe` norm extensionDoc
    it "reproduces it with no diagnostics at all" $
      map renderParseDiag (snd (parseBlawx (sourceOf extensionDoc))) `shouldBe` []
    it "re-emits byte-identical XML" $
      rowTexts (fromMaybe (error "no doc") (fst (parseBlawx (sourceOf extensionDoc))))
        `shouldBe` rowTexts extensionDoc

  describe "refusals at classification" $ do
    it "names the date layer and its owning spec" $
      diagsFor dateWs `shouldSatisfy` any (Text.isInfixOf "blawx-parse/unsupported-block")
    it "refuses a section slot that is not a doc_selector" $
      diagsFor variableRuleWs `shouldSatisfy` any (Text.isInfixOf "blawx-parse/section-slot")
    it "names a section reference that no workspace defines" $
      diagsFor danglingWs `shouldSatisfy` any (Text.isInfixOf "blawx-parse/dangling-section-ref")

  describe "the stale-encoding cross-check (P5-2)" $ do
    it "warns, never fails, and names the first diverging line" $ do
      let src = (sourceOf extensionDoc) {bsWorkspaces = staleRows}
          (doc, ds) = parseBlawx src
      doc `shouldSatisfy` isJustDoc
      map (\d -> d.pdCode) ds `shouldBe` ["blawx-parse/stale-encoding"]
      map (\d -> d.pdMessage) ds `shouldSatisfy` any (Text.isInfixOf "at line 1")
 where
  -- Only the span row's stored encoding is falsified; every other row (and
  -- every cross-link) stays intact, so the ONLY diagnostic can be the
  -- staleness warning.
  staleRows =
    [ if r.brwName == "sec_5__span_pingu_section" then r {brwScasp = "penguin(nobody)."} else r
    | r <- (sourceOf extensionDoc).bsWorkspaces
    ]

-- ---------------------------------------------------------------------------
-- The extension document
-- ---------------------------------------------------------------------------

-- | Every P5-1 constructor in one document, in the shapes bird uses: an
-- object declaration, a priority edge, the closed-world applicability
-- default, an @inapplicable@ rule whose condition is a
-- @new_object_category@, a section-attributed @holds@ assertion over a
-- doubly-negated @applies@, and a test with a NAF query.
extensionDoc :: BlawxDoc
extensionDoc =
  MkBlawxDoc
    { bdName = "New Bird Act"
    , bdRuleText =
        MkBRuleText
          { brTitle = "New Bird Act"
          , brSections = [MkBSection {bsNumber = 5, bsText = "Cartoon penguins with jetpacks can fly."}]
          }
    , bdWorkspaces = [declWs, sec3Ws, sec5Ws, spanWs]
    , bdTests = [birdTest]
    , -- The one datum a computed label cannot invent.
      bdDocPartNames = Map.fromList [(spanRef, "NBA 5pingu")]
    }

declWs :: BWorkspace
declWs =
  ws
    BRoot
    [ [ BDeclareCategory
          MkBCategoryDecl
            { bcName = bn "penguin"
            , bcPrefix = ""
            , bcPostfix = "is a penguin"
            , bcProv = Nothing
            }
      , BDeclareAttribute (boolAttr "thing" "flies" "can fly")
      , BDeclareAttribute (boolAttr "penguin" "cartoon_jetpack" "is a cartoon with a jetpack")
      ]
    ]

-- | bird's section 3, which section 5 overrules: the defeasible rule the
-- priority edge names. It is here so the cross-link resolves — Parse enforces
-- that every @section_reference@ names a workspace in the same file, which is
-- an invariant the corpus actually has (158 of 158).
sec3Ws :: BWorkspace
sec3Ws = ws (bSec 3) [[BAttributedRule penguinRule]]

penguinRule :: BRule
penguinRule =
  MkBRule
    { brSection = bSec 3
    , brConclusion = MkBConclusion {bcSign = False, bcPred = bn "flies", bcArgs = [BTVar (MkBVar "A")]}
    , brConditions = [BGCall True (bn "penguin") [BTVar (MkBVar "A")]]
    , brDefeasible = True
    , brInapplicable = False
    , brProvenance = Nothing
    }

sec5Ws :: BWorkspace
sec5Ws =
  ws
    (bSec 5)
    [ [BOverrules birdOverrule]
    , [BUnattributedRule appliesDefault]
    , [BAttributedRule jetpackRule]
    ]

spanWs :: BWorkspace
spanWs =
  ws
    spanRef
    [ [ BDeclareObject
          MkBObjectDecl
            { bodName = bn "pingu"
            , bodCategory = bn "penguin"
            , bodPrefix = ""
            , bodPostfix = "is a penguin"
            , bodMutNlg = Nothing
            , bodProv = Nothing
            }
      , assertGoal (BGHolds spanRef (mkBGNegated BNegClassical appliesPingu))
      ]
    ]

-- | A test whose query is negated — 3 of bird's 4 are — beside a scenario
-- fact, an abducible and a constraint, so the run partition has work to do.
birdTest :: BTest
birdTest =
  MkBTest
    { btName = "pingu_cant_fly"
    , btStacks =
        [ [BFact True (bn "penguin") [BTAtom (bn "pingu")]]
        , [BAbducible (bn "cartoon_jetpack") [BTVar (MkBVar "X")]]
        , [BConstraint [BGNaf (bn "flies") [BTAtom (bn "pingu")]]]
        , [BQuery [mkBGNegated BNegDefault (BGCall True (bn "flies") [BTAtom (bn "pingu")])]]
        ]
    , btComment = Nothing
    , btProv = Nothing
    }

jetpackRule :: BRule
jetpackRule =
  MkBRule
    { brSection = bSec 5
    , brConclusion = MkBConclusion {bcSign = True, bcPred = bn "flies", bcArgs = [BTVar (MkBVar "A")]}
    , brConditions =
        [ BGNewObjectCategory (bn "penguin") (BTVar (MkBVar "A"))
        , BGCall True (bn "cartoon_jetpack") [BTVar (MkBVar "A")]
        ]
    , brDefeasible = False
    , brInapplicable = True
    , brProvenance = Nothing
    }

birdOverrule :: BOverrule
birdOverrule =
  MkBOverrule
    { bovDefeating = bSec 5
    , bovDefeatingStmt = MkBConclusion {bcSign = True, bcPred = bn "flies", bcArgs = [BTVar (MkBVar "A")]}
    , bovDefeated = bSec 3
    , bovDefeatedStmt = MkBConclusion {bcSign = False, bcPred = bn "flies", bcArgs = [BTVar (MkBVar "A")]}
    , bovProv = Nothing
    }

appliesDefault :: BURule
appliesDefault =
  MkBURule
    { burConclusion = [appliesA]
    , burConditions = [mkBGNegated BNegDefault (mkBGNegated BNegClassical appliesA)]
    , burProv = Nothing
    }

appliesA, appliesPingu :: BGoal
appliesA = BGApplies (bSec 5) (BTVar (MkBVar "A"))
appliesPingu = BGApplies (bSec 5) (BTAtom (bn "pingu"))

-- ---------------------------------------------------------------------------
-- Single-workspace documents for the refusal specs
-- ---------------------------------------------------------------------------

-- | A row built straight from XML text, so a refusal spec can exhibit exactly
-- the shape it is about — including shapes no emitter of ours can produce.
xmlDoc :: Text -> Text -> BlawxSource
xmlDoc name xml =
  MkBlawxSource
    { bsRuledocName = "T"
    , bsRuleText = "T"
    , bsAkoma = Nothing
    , bsNavtree = Nothing
    , bsWorkspaces = [MkBlawxRow {brwName = name, brwXml = xml, brwScasp = ""}]
    , bsTests = []
    }

dateWs :: BlawxSource
dateWs =
  xmlDoc "sec_1_section" $
    "<xml xmlns=\"u\"><block type=\"unattributed_fact\" x=\"40\" y=\"40\">\
    \<statement name=\"statements\"><block type=\"unary_attribute_selector\">\
    \<mutation attributename=\"p\" attributetype=\"boolean\"></mutation>\
    \<value name=\"first_element\"><block type=\"date_value\"><field name=\"year\">2020</field>\
    \</block></value></block></statement></block></xml>"

variableRuleWs :: BlawxSource
variableRuleWs =
  xmlDoc "sec_1_section" $
    "<xml xmlns=\"u\"><block type=\"query\" x=\"40\" y=\"40\"><statement name=\"query\">\
    \<block type=\"according_to\"><value name=\"rule\"><block type=\"unnamed_variable\">\
    \</block></value><statement name=\"statement\"><block type=\"unary_attribute_selector\">\
    \<mutation attributename=\"flies\" attributetype=\"boolean\"></mutation>\
    \<value name=\"first_element\"><block type=\"variable\"><field name=\"variable_name\">A\
    \</field></block></value></block></statement></block></statement></block></xml>"

danglingWs :: BlawxSource
danglingWs =
  xmlDoc "sec_1_section" $
    "<xml xmlns=\"u\"><block type=\"unattributed_fact\" x=\"40\" y=\"40\">\
    \<statement name=\"statements\"><block type=\"holds\"><value name=\"section\">\
    \<block type=\"doc_selector\"><mutation section_reference=\"sec_9_section\"></mutation>\
    \<field name=\"doc_part_name\">X 9</field></block></value><statement name=\"statement\">\
    \<block type=\"unary_attribute_selector\">\
    \<mutation attributename=\"flies\" attributetype=\"boolean\"></mutation>\
    \<value name=\"first_element\"><block type=\"variable\"><field name=\"variable_name\">A\
    \</field></block></value></block></statement></block></statement></block></xml>"

diagsFor :: BlawxSource -> [Text]
diagsFor = map renderParseDiag . snd . parseBlawx

-- ---------------------------------------------------------------------------
-- XML fixtures for the layer specs
-- ---------------------------------------------------------------------------

chainXml, disabledXml, menuCacheXml, commentXml :: Text
chainXml =
  "<xml xmlns=\"u\"><block type=\"unattributed_fact\"><statement name=\"statements\">\
  \<block type=\"new_category_declaration\"><field name=\"category_name\">a</field>\
  \<next><block type=\"new_category_declaration\"><field name=\"category_name\">b</field>\
  \</block></next></block></statement></block></xml>"
disabledXml =
  "<xml xmlns=\"u\"><block type=\"a\" disabled=\"true\" x=\"5\" y=\"-7\">\
  \<next><block type=\"b\" x=\"40\" y=\"3\"></block></next></block></xml>"
menuCacheXml =
  "<xml xmlns=\"u\"><block type=\"category_selector\"><mutation \
  \xmlns=\"http://www.w3.org/1999/xhtml\" category_name=\"person\" category_list=\"a,b\">\
  \</mutation></block></xml>"
commentXml =
  "<xml xmlns=\"u\"><block type=\"query\"><comment pinned=\"false\" h=\"80\" w=\"160\">one\ntwo\
  \</comment></block></xml>"

wildProse :: Text
wildProse = "Beard Tax Act\n\nIn this Act, beard means any facial hair\n  (a) on the chin."

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | The source a document's own emission would store, minus the YAML layer
-- (which @jl4\/tests-cli@ covers, because @yaml@ is a CLI-side dependency).
sourceOf :: BlawxDoc -> BlawxSource
sourceOf doc =
  MkBlawxSource
    { bsRuledocName = doc.bdName
    , bsRuleText = renderRuleText doc.bdRuleText
    , bsAkoma = Nothing
    , bsNavtree = Nothing
    , bsWorkspaces =
        [ MkBlawxRow
            { brwName = renderSectionRef w.bwName
            , brwXml = x
            , brwScasp = renderWorkspaceScasp w
            }
        | (w, x) <- zip doc.bdWorkspaces (renderDocXml doc).bxWorkspaces
        ]
    , bsTests =
        [ MkBlawxRow {brwName = t.btName, brwXml = x, brwScasp = renderTestScasp t}
        | (t, x) <- zip doc.bdTests (renderDocXml doc).bxTests
        ]
    }

rowTexts :: BlawxDoc -> [Text]
rowTexts doc = let x = renderDocXml doc in x.bxWorkspaces <> x.bxTests

norm :: BlawxDoc -> BlawxDoc
norm = normaliseStacks . stripProvenance

reparses :: Text -> Expectation
reparses t = case parseXml t of
  Left e -> expectationFailure (Text.unpack ("could not parse: " <> renderXmlError e))
  Right n -> parseXml (renderNode n) `shouldBe` Right n

blocks :: Text -> Either Text ([BlockTree], [BlockWarning])
blocks t = case parseXml t of
  Left e -> Left (renderXmlError e)
  Right n -> toBlockTrees n

firstBlock :: Text -> Either Text BlockTree
firstBlock t = do
  (bs, _) <- blocks t
  case bs of
    b : _ -> Right b
    [] -> Left "no blocks"

stmtOf :: Text -> BlockTree -> [BlockTree]
stmtOf = btStmt

kidCount :: XNode -> Int
kidCount = length . childElems

fieldText :: Text -> Either Text Text
fieldText t = case parseXml t of
  Left e -> Left (renderXmlError e)
  Right n -> case childElems n of
    f : _ -> Right (elemText f)
    [] -> Left "no field"

attrOf :: Text -> Text -> Either Text Text
attrOf k t = case parseXml t of
  Left e -> Left (renderXmlError e)
  Right (XElem _ as _) -> maybe (Left "no such attribute") Right (lookup k as)
  Right (XText _) -> Left "not an element"

isJustDoc :: Maybe BlawxDoc -> Bool
isJustDoc = maybe False (const True)

ws :: BSectionRef -> [[BBlock]] -> BWorkspace
ws n stacks = MkBWorkspace {bwName = n, bwStacks = stacks, bwComment = Nothing}

assertGoal :: BGoal -> BBlock
assertGoal g = fromMaybe (error "not a fact-position goal") (mkBAssertGoal g)

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

spanRef, deepRef :: BSectionRef
spanRef = BPath (step "sec" "5" :| [step "span" "pingu"])
deepRef = BPath (step "sec" "34" :| [step "subsec" "1", step "para" "b", step "subpara" "i"])

step :: Text -> Text -> BStep
step k l = fromMaybe (error "bad BStep") (mkBStep k l)

bn :: Text -> BName
bn t = fromMaybe (error ("not a Blawx atom: " <> Text.unpack t)) (mkBName Nothing t)
