{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | The Blawx leg's half of the @ASSUME@ → 'RInput' widening, and the
-- @rule_text@ citation fallback beside it.
--
-- __Why here and not in a @.blawx@ golden.__ The file-based Blawx goldens
-- (@jl4\/examples\/blawx\/@) are the right home for a corpus seed, and one is
-- owed; what they cannot cheaply give is a battery of small modules that differ
-- in ONE annotation each, which is exactly what the @\@desc@ → @\@ref@ → stub
-- fallback needs to be pinned by. Each source below is a few lines, runs the
-- REAL pipeline end to end (type check → 'lowerModule' → 'lowerBlawx' →
-- 'renderBlawxYaml'), and asserts on the emitted text — so nothing here can
-- drift from what @l4 blawx@ writes.
--
-- The relational half is pinned by @jl4\/examples\/relational\/expected\/@
-- (@assumed@, @assumed-nullary@, @not-ok-assumed-signatures@,
-- @not-ok-local-assume@); this file deliberately does not restate it.
module BlawxAssumeSpec (spec) where

import Test.Hspec

import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (TypeCheckWithDepsResult (..), checkWithImports, emptyVFS)
import L4.Blawx.Emit (renderBlawxYaml)
import L4.Blawx.Lower (lowerBlawx)
import L4.Relational.IR (renderLowerError)
import L4.Relational.Lower (defaultLowerOptions, lowerModule)
import qualified L4.TypeCheck as TC
import L4.TypeCheck.Types (Severity (..))

-- | Source → the @.blawx@ YAML, or the first stage's diagnostics as text.
--
-- Type-check errors are surfaced as a 'Left' rather than ignored: a module that
-- L4 rejects would otherwise be asserted on anyway, and the assertion would be
-- pinning the exporter's treatment of a broken module. That matters more than
-- usual here — the @ASSUME@ corpus shape is exactly where
-- @L4.Export.validateExportInputs@ fires (a function-typed @ASSUME@ referenced
-- by an @\@export@ is a type error), and a spec that swallowed it would claim
-- support for a spelling no user can compile.
blawxYaml :: Text -> Either Text Text
blawxYaml src = case checkWithImports emptyVFS src of
  Left errs -> Left ("parse/import: " <> Text.unlines errs)
  Right r
    | errs@(_ : _) <- filter ((== SError) . TC.severity) r.tcdErrors ->
        Left ("typecheck: " <> Text.unlines (concatMap TC.prettyCheckErrorWithContext errs))
    | otherwise -> case lowerModule defaultLowerOptions r.tcdEntityInfo r.tcdModule of
        Left es -> Left ("lowering: " <> Text.unlines (map renderLowerError es))
        Right prog -> case lowerBlawx prog of
          Left es -> Left ("blawx: " <> Text.unlines (map renderLowerError es))
          Right doc -> Right (renderBlawxYaml doc)

-- | Assert on a module that must compile all the way through.
emitted :: Text -> IO Text
emitted src = case blawxYaml src of
  Left err  -> do expectationFailure (Text.unpack err); pure ""
  Right out -> pure out

hasLine :: Text -> Text -> Expectation
hasLine out needle = (needle, needle `Text.isInfixOf` out) `shouldBe` (needle, True)

lacksLine :: Text -> Text -> Expectation
lacksLine out needle = (needle, needle `Text.isInfixOf` out) `shouldBe` (needle, False)

-- | An ASSUME-shaped module: two ASSUMEd TYPEs as categories, boolean ASSUMEs
-- over each (one used negatively, one not used at all), a value ASSUME bridging
-- them, and one exported decision carrying both a @\@desc@ and a @\@ref@.
--
-- Every ASSUME is spelled @GIVEN p … ASSUME f p IS A T@ rather than
-- @FUNCTION FROM …@: see 'blawxYaml' on why the other spelling cannot appear in
-- an exported module.
assumeModule :: Text
assumeModule = Text.unlines
  [ "ASSUME Person IS A TYPE"
  , "ASSUME Behaviour IS A TYPE"
  , ""
  , "@desc an authorised person"
  , "@ref s 53(1)"
  , "GIVEN p IS A Person"
  , "ASSUME `is authorised` p IS A BOOLEAN"
  , ""
  , "GIVEN p IS A Person"
  , "ASSUME `has been warned` p IS A BOOLEAN"
  , ""
  , "GIVEN p IS A Person"
  , "ASSUME conduct p IS A Behaviour"
  , ""
  , "GIVEN b IS A Behaviour"
  , "ASSUME `is unreasonable` b IS A BOOLEAN"
  , ""
  , "GIVEN b IS A Behaviour"
  , "ASSUME `is persistent` b IS A BOOLEAN"
  , ""
  , "@export whether a notice may be issued"
  , "@ref s 43(1)"
  , "GIVEN p IS A Person"
  , "GIVETH A BOOLEAN"
  , "DECIDE `may issue` p IF"
  , "      `is authorised` p"
  , "  AND NOT `has been warned` p"
  , "  AND `is unreasonable` (conduct p)"
  ]

spec :: Spec
spec = do
  describe "ASSUME-derived inputs reach the Blawx ontology" $ do
    it "declares an ASSUMEd TYPE as a category" $ do
      out <- emitted assumeModule
      hasLine out "blawx_category(person)."
      hasLine out "blawx_category_nlg(person,\"\",\"is a person\")."
      hasLine out ":- dynamic person/1."

    it "declares a boolean ASSUME as a unary attribute of its subject's category" $ do
      out <- emitted assumeModule
      hasLine out "blawx_attribute(person,is_authorised,boolean)."
      -- the same block a boolean FIELD gets: truth rides the sign, so the
      -- postfix carries the phrase and the infix is not_applicable
      hasLine out "blawx_attribute_nlg(is_authorised,not_applicable,\"\",not_applicable,\"is authorised\")."
      hasLine out ":- dynamic is_authorised/1."

    it "declares a value ASSUME as a binary attribute, typed by its result" $ do
      out <- emitted assumeModule
      hasLine out "blawx_attribute(person,conduct,behaviour)."
      hasLine out ":- dynamic conduct/2."

    it "gives NOT over an ASSUMEd input CLASSICAL negation (R5), not NAF" $ do
      -- The whole reason 'RPredKind' is in the IR: an input that was never
      -- stated must fail loudly. `not has_been_warned(P)` would silently
      -- succeed for a person nobody said anything about.
      out <- emitted assumeModule
      hasLine out "-has_been_warned(P)"
      lacksLine out "not has_been_warned("

    it "omits an ASSUME no clause calls, and the category that only it mentions" $ do
      -- The reachability gate, which is what makes the widening additive.
      out <- emitted assumeModule
      lacksLine out "is_persistent"

  describe "the #abducible interview test (R11), on a module with no DECLARE at all" $ do
    it "declares every input abducible, plus their categories, and queries the first export" $ do
      -- P1 deferred this: `interviewTest` recovered an input's category and
      -- arity from the FIELD tables, so a module with no records got no
      -- interview. Both are now read off the predicate's own signature.
      out <- emitted assumeModule
      hasLine out "test_name: interview"
      hasLine out "#abducible person(X)."
      hasLine out "#abducible behaviour(X)."
      hasLine out "#abducible is_authorised(X)."
      hasLine out "#abducible has_been_warned(X)."
      hasLine out "#abducible conduct(X,Y)."
      hasLine out "?- may_issue(X)."

    it "still emits exactly one attribute declaration per stored field" $ do
      -- The declarations filter changed from "not an input" to "not a FIELD
      -- input". A field input reaching the classifier as well would be declared
      -- twice — valid Prolog, and a duplicated block in the workspace.
      out <- emitted recordModule
      Text.count "blawx_attribute(applicant,age,number)." out `shouldBe` 1
      Text.count "blawx_attribute(applicant,is_veteran,boolean)." out `shouldBe` 1
      hasLine out "#abducible age(X,Y)."
      hasLine out "#abducible is_veteran(X)."

  describe "rule_text falls back @desc -> @ref -> stub" $ do
    it "A: prefers the @desc prose when both are present" $ do
      out <- emitted assumeModule
      hasLine out "1. whether a notice may be issued"
      lacksLine out "1. s 43(1)"

    it "B: uses the @ref citation when there is no @desc" $ do
      out <- emitted (refOnly "@ref Sch 2 Ground 8")
      hasLine out "1. Sch 2 Ground 8"

    it "B: squashes the citation's whitespace, as it does the prose's" $ do
      out <- emitted (refOnly "@ref   Sch 2   Ground 8,  Housing Act 1988")
      hasLine out "1. Sch 2 Ground 8, Housing Act 1988"

    it "C: falls back to the stub when there is neither" $ do
      out <- emitted (refOnly "")
      hasLine out "1. Definition of is in arrears."

  -- The CLEAN section number is the author's to write (spec §11 W3, 2026-09-02).
  -- clean-law 0.0.4 builds the eId from the LITERAL numeral it reads, not from
  -- the section's position (@clean/clean.py:193@, @generate_section@), so a
  -- pinned number is the whole of what makes @according_to(sec_4_section, ...)@
  -- agree with the source. Everything below is asserted on the emitted YAML,
  -- so it cannot drift from what @l4 blawx@ writes.
  describe "the author pins the CLEAN section number (§11 W3)" $ do
    it "a leading CLEAN index picks the section, and is written only once" $ do
      out <- emitted pinnedModule
      hasLine out "1. The tenant may be given notice.\\n4. The tenant is in arrears."
      hasLine out "workspace_name: sec_4_section"
      hasLine out "according_to(sec_4_section,is_in_arrears,T)"
      -- the numeral clean-law re-emits as the section's <num> is NOT repeated
      lacksLine out "4. 4. The tenant"
      lacksLine out "workspace_name: sec_2_section"

    it "an unpinned decision takes the lowest number no pin claims" $ do
      -- export order is (pinned 4, unpinned); the unpinned one is section 1,
      -- not section 2, and the rule_text is written in ascending order.
      out <- emitted pinnedModule
      hasLine out "workspace_name: sec_1_section"
      hasLine out "according_to(sec_1_section,may_be_given_notice,T)"

    it "two decisions may pin one section, and then they share it" $ do
      out <- emitted sharedPinModule
      -- one numbered workspace, holding both rules
      Text.count "workspace_name: sec_" out `shouldBe` 1
      hasLine out "workspace_name: sec_1_section"
      hasLine out "according_to(sec_1_section,is_in_arrears,T)"
      hasLine out "according_to(sec_1_section,is_notified,T)"
      -- and its rule_text is their prose joined in export order
      hasLine out "1. In this Act, arrears means any amount unpaid, and (a) notified means notified in writing."

    it "a helper follows the pinned section of the decision that reaches it" $ do
      out <- emitted pinnedHelperModule
      hasLine out "according_to(sec_7_section,qualifies,T)"
      hasLine out "according_to(sec_7_section,deeply_in_arrears,T)"

    -- The recogniser is deliberately narrow. Each of these is a real spelling
    -- from the corpus or from an earlier draft of the two Blawx seeds, and each
    -- falls through to R4's flat numbering.
    --
    -- Their text is QUOTED on the way out, and asserting only "does not pin"
    -- was the defect in the first cut of this ruling: every one of them opens on
    -- a DIGIT, we write "1. " in front of it, and clean-law reads our period
    -- plus that digit as one insert index — so the emitted eIds stop matching
    -- the emitted workspace names and every canvas in the document is orphaned.
    -- Measured with etc/blawx-eid-harness.py on 2026-09-02: unquoted,
    -- `1(a): ...`, `43(1)(a): ...` and `4, ...` yield NO sections at all, `0. `
    -- yields sec_1_ 0 and `2.1. ` yields sec_1_ 2_1, all against sec_1_section;
    -- quoted, all five yield sec_1_section. The escaped \" below is the YAML
    -- escape, so these assertions see exactly the bytes the fixture carries.
    it "does not pin on a paragraph index with no dot (1(a): ...), and quotes it" $ do
      out <- emitted (descOnly "1(a): facial hair that occurs on or below the chin.")
      hasLine out "1. \\\"1(a): facial hair that occurs on or below the chin.\\\""

    it "does not pin on a sub-provision citation (43(1)(a): ...), and quotes it" $ do
      out <- emitted (descOnly "43(1)(a): the conduct is unreasonable.")
      hasLine out "1. \\\"43(1)(a): the conduct is unreasonable.\\\""

    it "does not pin on a comma (4, the other seat.), and quotes it" $ do
      out <- emitted (descOnly "4, the other seat.")
      hasLine out "1. \\\"4, the other seat.\\\""

    it "does not pin on 0, which no Act has, and quotes it" $ do
      out <- emitted (descOnly "0. a section number no Act has.")
      hasLine out "1. \\\"0. a section number no Act has.\\\""

    it "does not pin on clean-law's insert index (2.1.), which W3(b) leaves open" $ do
      out <- emitted (descOnly "2.1. a sub-provision index.")
      hasLine out "1. \\\"2.1. a sub-provision index.\\\""

    it "quotes any text opening on a digit, index-shaped or not" $ do
      -- `5 apples ...` is not an index by anyone's grammar, but clean-law's
      -- insert_index is DOT + number and OUR separator supplies the DOT, so
      -- `1. 5 apples ...` fails to parse as a section just the same.
      out <- emitted (descOnly "5 apples are enough.")
      hasLine out "1. \\\"5 apples are enough.\\\""

    it "leaves a text that does not open on a digit alone" $ do
      out <- emitted (descOnly "The tenant is in arrears.")
      hasLine out "1. The tenant is in arrears."
      lacksLine out "\\\"The tenant"

    -- W3's second spelling: `@ref ... s 4`. The numeral is NOT consumed here —
    -- it is part of the citation, and it sits at the END of the text where
    -- clean-law's index grammar cannot reach it.
    it "a citation ending in `, s N` pins the section" $ do
      out <- emitted (refOnly "@ref Mortality Act 2026, s 4")
      hasLine out "4. Mortality Act 2026, s 4"
      hasLine out "workspace_name: sec_4_section"
      hasLine out "according_to(sec_4_section,is_in_arrears,T)"

    it "`, section N` pins too" $ do
      out <- emitted (refOnly "@ref Mortality Act 2026, section 12")
      hasLine out "12. Mortality Act 2026, section 12"
      hasLine out "workspace_name: sec_12_section"

    it "a citation naming a sub-provision does not pin" $ do
      -- the spelling antisocial.l4 actually uses: pinning s.43(1)(b) to sec_43
      -- would anchor the rule one level up from where the author cited it.
      out <- emitted (refOnly "@ref Anti-social Behaviour, Crime and Policing Act 2014, s.43(1)(b)")
      hasLine out "1. Anti-social Behaviour, Crime and Policing Act 2014, s.43(1)(b)"
      hasLine out "workspace_name: sec_1_section"

    it "a URL ending in digits does not pin" $ do
      -- the other spelling in the corpus; the herald is `section/`, not `, section`
      out <- emitted (refOnly "@ref https://www.legislation.gov.uk/ukpga/2014/12/section/43")
      hasLine out "workspace_name: sec_1_section"
      lacksLine out "workspace_name: sec_43_section"

    it "refuses a pinned section whose remainder opens on another index" $
      -- `4. 5. ...` is a sub-provision, which W3(b) leaves open; emitting it
      -- would give clean-law the insert index `4. 5` and orphan sec_4_section.
      case blawxYaml (descOnly "4. 5. A human is mortal.") of
        Right _  -> expectationFailure "expected a Blawx rejection for a doubly-indexed section"
        Left err -> err `shouldSatisfy` Text.isInfixOf "sub-provision index"

  -- CLEAN's title grammar is @Word(string.ascii_uppercase, printables)@: the
  -- FIRST character must be A-Z, and RuleDoc.save()'s pre_save signal runs the
  -- same parse, so a title it refuses makes the whole .blawx unimportable -- a
  -- worse outcome than the orphaned canvas §11 W3 is about, because the document
  -- then has no sections at all. Re-casing (P1) handles `housing Act`; it cannot
  -- handle `1988 Housing Act`, which is why there is a herald as well.
  describe "the CLEAN title guard" $ do
    it "heralds a title whose first character cannot be an ASCII capital" $ do
      out <- emitted (titledModule "1988 Housing Act")
      hasLine out "rule_text: \"The 1988 Housing Act"

    it "still only re-cases a letter-initial title" $ do
      out <- emitted (titledModule "housing Act")
      hasLine out "rule_text: \"Housing Act"
      lacksLine out "The Housing Act"

  describe "what the Blawx leg refuses, and the middle end does not" $ do
    it "rejects a subjectless input by name, rather than emitting a blank row" $ do
      -- `input p/0` is a fine Horn predicate and the relational golden
      -- (assumed-nullary) says so. Blawx has no block for a proposition with no
      -- subject, and an XmlGap here is the R12 data loss the fixpoint harness
      -- exists to catch — so it is a named rejection at this layer.
      case blawxYaml nullaryModule of
        Right _  -> expectationFailure "expected a Blawx rejection for a subjectless input"
        Left err -> err `shouldSatisfy` Text.isInfixOf "no category subject"

    it "still rejects a LOCAL ASSUME, which has no name to declare" $
      case blawxYaml localAssumeModule of
        Right _  -> expectationFailure "expected a rejection for a local ASSUME"
        Left err -> err `shouldSatisfy` Text.isInfixOf "local ASSUME"

    -- The two boundary cases below exist because the diagnostic and
    -- BLAWX-EXPORT-SPEC §6.1 both used to state the rule as "an input's first
    -- parameter must be a category". 'classifyPred' does not implement that
    -- rule and never did: it tests 'categoryOf' only in its two arity-1 arms,
    -- so the refused band is total arity ≤ 2 that is not attribute-shaped, and
    -- arity 3–10 is admitted with no sort condition on any argument. Each half
    -- of that is pinned here, so a later reader who trusts the prose over the
    -- code gets a red test rather than a working program newly rejected.
    it "refuses an arity-2 input EVEN WITH a category first parameter" $
      -- The corpus twin of this is `jl4/examples/blawx/not-ok/arity-two.l4`.
      case blawxYaml arityTwoModule of
        Right _  -> expectationFailure "expected a Blawx rejection for a two-place input"
        Left err -> do
          err `shouldSatisfy` Text.isInfixOf "no category subject"
          -- the message must name the ARITY band, not the first parameter:
          -- this module's first parameter IS a category, so the old wording
          -- gave advice the author had already taken
          err `shouldSatisfy` Text.isInfixOf "total arity 2"
          err `shouldSatisfy` Text.isInfixOf "ATTRIBUTE-shaped"
          err `shouldSatisfy` Text.isInfixOf "start at total arity 3"

    it "admits an arity-3 input with no category parameter at all" $ do
      -- Not a defect: Blawx relationship blocks are n-ary over any declared
      -- value type. It is only the SPEC that claimed otherwise.
      out <- emitted arityThreeModule
      hasLine out "blawx_relationship(scaled_by,number,number,number)."
      hasLine out ":- dynamic scaled_by/3."
      hasLine out "#abducible scaled_by(A,B,C)."
 where
  -- One exported decision over a record, annotated by the caller: the
  -- @rule_text@ arms differ in nothing else.
  refOnly ann = Text.unlines
    [ "DECLARE Tenant HAS"
    , "    arrears IS A NUMBER"
    , ""
    , "@export"
    , ann
    , "GIVEN t IS A Tenant"
    , "GIVETH A BOOLEAN"
    , "DECIDE `is in arrears` t IF t's arrears AT LEAST 1"
    ]

  -- One exported decision over a record, its @\@export@ prose supplied by the
  -- caller: the section-pin arms differ in nothing else.
  descOnly d = Text.unlines
    [ "DECLARE Tenant HAS"
    , "    arrears IS A NUMBER"
    , ""
    , "@export " <> d
    , "GIVEN t IS A Tenant"
    , "GIVETH A BOOLEAN"
    , "DECIDE `is in arrears` t IF t's arrears AT LEAST 1"
    ]

  -- One pinned decision, one unpinned, in that export order.
  pinnedModule = Text.unlines
    [ "DECLARE Tenant HAS"
    , "    arrears IS A NUMBER"
    , "    warned  IS A BOOLEAN"
    , ""
    , "@export 4. The tenant is in arrears."
    , "GIVEN t IS A Tenant"
    , "GIVETH A BOOLEAN"
    , "DECIDE `is in arrears` t IF t's arrears AT LEAST 1"
    , ""
    , "@export The tenant may be given notice."
    , "GIVEN t IS A Tenant"
    , "GIVETH A BOOLEAN"
    , "DECIDE `may be given notice` t IF t's warned"
    ]

  -- A chapeau and a limb, both pinned to s.1 -- the beard.l4 shape, and what
  -- Jason Morris's own beard_tax.yaml does with sec_1_section.
  sharedPinModule = Text.unlines
    [ "DECLARE Tenant HAS"
    , "    arrears  IS A NUMBER"
    , "    notified IS A BOOLEAN"
    , ""
    , "@export 1. In this Act, arrears means any amount unpaid, and"
    , "GIVEN t IS A Tenant"
    , "GIVETH A BOOLEAN"
    , "DECIDE `is in arrears` t IF t's arrears AT LEAST 1"
    , ""
    , "@export 1. (a) notified means notified in writing."
    , "GIVEN t IS A Tenant"
    , "GIVETH A BOOLEAN"
    , "DECIDE `is notified` t IF t's notified"
    ]

  -- A non-exported helper is filed with the exported decision that reaches it,
  -- which now means the section that decision PINNED, not its export position.
  pinnedHelperModule = Text.unlines
    [ "DECLARE Tenant HAS"
    , "    arrears IS A NUMBER"
    , ""
    , "@export 7. The tenant qualifies."
    , "GIVEN t IS A Tenant"
    , "GIVETH A BOOLEAN"
    , "DECIDE `qualifies` t IF `deeply in arrears` t"
    , ""
    , "GIVEN t IS A Tenant"
    , "GIVETH A BOOLEAN"
    , "DECIDE `deeply in arrears` t IF t's arrears AT LEAST 100"
    ]

  -- One exported decision under a § heading supplied by the caller: the title
  -- arms differ in nothing else.
  titledModule h = Text.unlines
    [ "§ `" <> h <> "`"
    , ""
    , "DECLARE Tenant HAS"
    , "    arrears IS A NUMBER"
    , ""
    , "@export The tenant is in arrears."
    , "GIVEN t IS A Tenant"
    , "GIVETH A BOOLEAN"
    , "DECIDE `is in arrears` t IF t's arrears AT LEAST 1"
    ]

  recordModule = Text.unlines
    [ "DECLARE Applicant HAS"
    , "    age IS A NUMBER"
    , "    isVeteran IS A BOOLEAN"
    , ""
    , "@export"
    , "GIVEN a IS A Applicant"
    , "GIVETH A BOOLEAN"
    , "DECIDE `eligible` a IF a's age AT LEAST 65 OR a's isVeteran"
    ]

  nullaryModule = Text.unlines
    [ "ASSUME `the notice was served` IS A BOOLEAN"
    , ""
    , "@export"
    , "GIVEN n IS A NUMBER"
    , "GIVETH A BOOLEAN"
    , "DECIDE `is in time` n IF `the notice was served` AND n AT MOST 28"
    ]

  localAssumeModule = Text.unlines
    [ "@export"
    , "GIVEN n IS A NUMBER"
    , "GIVETH A BOOLEAN"
    , "DECIDE `above the threshold` n IF n AT LEAST threshold"
    , "  WHERE"
    , "    ASSUME threshold IS A NUMBER"
    ]

  -- Total arity 2, first parameter an ASSUMEd TYPE: the shape the old
  -- diagnostic's advice produces, and which it then refuses anyway.
  arityTwoModule = Text.unlines
    [ "ASSUME Consequence IS A TYPE"
    , ""
    , "GIVEN c IS A Consequence"
    , "ASSUME `is severe` c IS A BOOLEAN"
    , ""
    , "GIVEN c IS A Consequence"
    , "      n IS A NUMBER"
    , "ASSUME `severity exceeds` c n IS A BOOLEAN"
    , ""
    , "@export"
    , "GIVEN c IS A Consequence"
    , "GIVETH A BOOLEAN"
    , "DECIDE `qualifies` c IF `is severe` c AND `severity exceeds` c 10"
    ]

  -- Total arity 3, and not one argument is a category.
  arityThreeModule = Text.unlines
    [ "ASSUME Person IS A TYPE"
    , ""
    , "GIVEN p IS A Person"
    , "ASSUME `base rate` p IS A NUMBER"
    , ""
    , "GIVEN a IS A NUMBER"
    , "      b IS A NUMBER"
    , "ASSUME `scaled by` a b IS A NUMBER"
    , ""
    , "@export"
    , "GIVEN p IS A Person"
    , "GIVETH A BOOLEAN"
    , "DECIDE `qualifies` p IF `scaled by` (`base rate` p) 2 AT LEAST 10"
    ]
