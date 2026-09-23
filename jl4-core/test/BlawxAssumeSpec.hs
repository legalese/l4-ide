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

    -- BLAWX-EXPORT-SPEC §11 W1, measured 2026-09-02. The corpus twin is
    -- `jl4/examples/blawx/not-ok/record-identity.l4` — Jason Morris's own
    -- wording of RPS s.4, which lowered CLEAN and then answered differently
    -- (L4 TRUE, tier-1 no model), because the R11 flattening gives one object
    -- per occurrence of a record value. The refusal is what makes that loud.
    it "refuses EQUALS on record-typed operands, saying why AND what to do" $
      case blawxYaml recordEqModule of
        Right _  -> expectationFailure "expected a Blawx rejection for record equality"
        Left err -> do
          err `shouldSatisfy` Text.isInfixOf "record identity (Blawx)"
          err `shouldSatisfy` Text.isInfixOf "record type `Player`"
          -- the two halves of the divergence, both named
          err `shouldSatisfy` Text.isInfixOf "L4 compares records by value"
          err `shouldSatisfy` Text.isInfixOf "Blawx compares objects by atom"
          err `shouldSatisfy` Text.isInfixOf "one object per occurrence"
          -- and a reachable edit: a diagnostic that only names the defect
          -- leaves the author with a module and no next move (the lesson of
          -- the arity-two wording above)
          err `shouldSatisfy` Text.isInfixOf "once per slot"
          err `shouldSatisfy` Text.isInfixOf "FIELD"

    it "refuses the disequality half of the same rule (the ELSE arm)" $
      -- IF/THEN/ELSE in value position becomes two clauses, the second
      -- guarded by the complement, so one source `EQUALS` on records reaches
      -- the emitter as both an REq and an RNeq. Both must be refused: leaving
      -- either open would let half the rule through.
      case blawxYaml recordEqModule of
        Right _  -> expectationFailure "expected a Blawx rejection for record equality"
        Left err -> err `shouldSatisfy`
          Text.isInfixOf "a disequality on operands of record type `Player`"

    -- The verifier's counterexample to the first cut of this refusal (2026-09-02):
    -- the check tested the operand's sort for `RSRecord` at the TOP only, so a
    -- container of records walked straight through. Measured before the fix, on
    -- exactly this module: `l4 blawx` exited 0 and emitted
    -- `members(A,Members), members(B,Members2), Members = Members2.` — the same
    -- by-value/by-atom divergence the bare-record case has, with a green exit
    -- code. The corpus twin is `jl4/examples/blawx/not-ok/record-identity-list.l4`.
    it "refuses EQUALS on a LIST OF records, and says which container it is in" $
      case blawxYaml recordListEqModule of
        Right _  -> expectationFailure "expected a Blawx rejection for LIST OF record equality"
        Left err -> do
          err `shouldSatisfy` Text.isInfixOf "record identity (Blawx)"
          -- naming the operand's OWN sort matters: "of record type `Player`"
          -- would be a false description of a `LIST OF Player` operand.
          err `shouldSatisfy` Text.isInfixOf
            "type `LIST OF Player`, which contains the record type `Player`"

    it "refuses it under LIST OF MAYBE too, which is the only reachable MAYBE" $
      -- A bare `MAYBE Player` field never reaches this check: `blawxValueType`
      -- refuses it first ("sort with no Blawx value type"). `LIST OF MAYBE
      -- Player` does reach it, because that same function types any RSList as
      -- BVList without looking inside — so this is the case that exercises the
      -- `RSMaybe` descent, and without it that arm would be dead code.
      case blawxYaml recordListMaybeEqModule of
        Right _  -> expectationFailure "expected a Blawx rejection for LIST OF MAYBE record equality"
        Left err -> err `shouldSatisfy` Text.isInfixOf
          "type `LIST OF MAYBE Player`, which contains the record type `Player`"

    it "still admits equality on two ASSUMEd abstract-type operands" $ do
      -- The other half of the verifier's counterexample, in the opposite
      -- direction. `RSRecord` carries an `ASSUME T IS A TYPE` as well as a
      -- `DECLARE … HAS` record (L4.Relational.IR says so and says to
      -- discriminate by looking the name up among the declared records), so the
      -- first cut refused this too — removing an emission the parent commit
      -- had, and recommending an edit ("compare a FIELD") that an abstract
      -- category has nothing to satisfy. An ASSUMEd category's values ARE atoms
      -- on both sides; `=` on atoms is the faithful image.
      out <- emitted abstractEqModule
      hasLine out "person(A),"
      hasLine out "A = B."

    it "admits it inside a container as well" $ do
      -- The descent must not over-fire either: a LIST OF an ASSUMEd category is
      -- a list of atoms, and unification is still the faithful image.
      out <- emitted abstractListEqModule
      hasLine out "Members = Members2."

    it "still admits equality on an ENUM-valued FIELD of the same records" $ do
      -- The check is on the operand SORT, not on the operator: an enum
      -- constructor IS an atom in Blawx and does survive the flattening,
      -- which is exactly the edit the diagnostic recommends. If this ever
      -- goes red the refusal has over-fired and taken the fix with it.
      out <- emitted recordFieldEqModule
      hasLine out "throws(P,Throws),"
      hasLine out "Throws = Throws2."

    -- BLAWX-EXPORT-SPEC §11 W2, measured 2026-09-02. Blawx's attribute-type
    -- dropdown is a closed list -- boolean, number, date, time, datetime,
    -- duration, list, plus the declared categories
    -- (@blawx-blocks.js:5376@ and @:5577-5583@ on the stock v1.6.22-alpha
    -- checkout) -- and @scasp_generator.js@ has no per-type branch that could
    -- add one. So a string sort in a SIGNATURE is refused, while a string
    -- LITERAL in a rule body is not: the two halves are pinned separately
    -- below, because §4.7 used to state the surviving half as though it
    -- covered both.
    it "refuses a STRING-sorted field, and says what to write instead" $
      case blawxYaml stringFieldModule of
        Right _  -> expectationFailure "expected a Blawx rejection for a STRING field"
        Left err -> do
          err `shouldSatisfy` Text.isInfixOf "STRING-sorted field or argument (Blawx)"
          err `shouldSatisfy` Text.isInfixOf "no string attribute type"
          -- the message names all three positions, because as of 2026-09-02
          -- all three are refused (see the two cases below)
          err `shouldSatisfy` Text.isInfixOf "STRING-sorted field, parameter or result"
          -- the advice, which is the point of the message: an enum for a fixed
          -- vocabulary, a category for identity
          err `shouldSatisfy` Text.isInfixOf "DECLARE ... IS ONE OF ..."
          err `shouldSatisfy` Text.isInfixOf "category for identity"
          -- and it must not send the author looking for a spelling that works:
          -- literals in a rule body are fine, so the message says so
          err `shouldSatisfy` Text.isInfixOf "String literals inside a rule body are fine"

    it "accepts the enum the diagnostic recommends, in the same shape" $ do
      out <- emitted enumFieldModule
      hasLine out "blawx_category(player_name)."
      hasLine out "blawx_attribute(player,name,player_name)."

    -- The hole the first cut of this work left open, found by review and
    -- pinned here. 'classifyPred' only reaches 'valueType' from the arms that
    -- build a DECLARATION BLOCK; a predicate of total arity <= 2 that is not
    -- attribute-shaped is 'PCUndeclared' and used to skip the check entirely,
    -- so this module emitted cleanly (exit 0, @S = zebra.@ in the s(CASP))
    -- while its arity-3 spelling was refused. The corpus twin is
    -- `jl4/examples/blawx/not-ok/string-param.l4`.
    it "refuses a STRING PARAMETER even where the predicate gets no declaration block" $
      case blawxYaml stringParamModule of
        Right _  -> expectationFailure "expected a Blawx rejection for a STRING parameter"
        Left err -> do
          err `shouldSatisfy` Text.isInfixOf "STRING-sorted field or argument (Blawx)"
          err `shouldSatisfy` Text.isInfixOf "STRING-sorted field, parameter or result"
          -- and it is the DERIVED predicate that is named, not a field
          err `shouldSatisfy` Text.isInfixOf "`throws named`"

    -- The third position, and the one §4.7's own "Admitted" bullet used to be
    -- an instance of: a nullary constant whose RESULT is a STRING.
    it "refuses a STRING RESULT on a nullary constant" $
      case blawxYaml stringResultModule of
        Right _  -> expectationFailure "expected a Blawx rejection for a STRING result"
        Left err -> do
          err `shouldSatisfy` Text.isInfixOf "STRING-sorted field or argument (Blawx)"
          err `shouldSatisfy` Text.isInfixOf "`the house sign`"

    it "still admits a string LITERAL in a rule body, as an atom" $ do
      -- The half of §4.7 that survives the narrowing. No signature in this
      -- module is STRING-sorted: `aliases` is a LIST, which Blawx declares as
      -- its untyped `list` value type without inspecting the element sort, and
      -- the literal reaches the s(CASP) through the program-global string-atom
      -- table, compared by unification.
      out <- emitted stringLiteralModule
      hasLine out "blawx_attribute(player,aliases,list)."
      hasLine out "Aliases = [zebra | []]."

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

  -- The §11 W1 shape, reduced to the one rule that carries it: "the other
  -- player is whichever of the two is not the one in question", which can
  -- only be said by comparing two Player RECORDS.
  recordEqModule = Text.unlines
    [ "DECLARE Sign IS ONE OF Rock, Paper, Scissors"
    , ""
    , "DECLARE Player HAS"
    , "    throws IS A Sign"
    , ""
    , "DECLARE Game HAS"
    , "    `first player`  IS A Player"
    , "    `second player` IS A Player"
    , ""
    , "@export"
    , "GIVEN g IS A Game"
    , "      p IS A Player"
    , "GIVETH A Player"
    , "DECIDE `other player` g p IS"
    , "  IF p EQUALS g's `first player` THEN g's `second player` \
      \ELSE g's `first player`"
    ]

  -- The same defect smuggled inside a container: no bare Player appears on
  -- either side of the EQUALS.
  recordListEqModule = Text.unlines
    [ "DECLARE Player HAS"
    , "    number IS A NUMBER"
    , ""
    , "DECLARE Team HAS"
    , "    members IS A LIST OF Player"
    , ""
    , "@export"
    , "GIVEN a IS A Team"
    , "      b IS A Team"
    , "GIVETH A BOOLEAN"
    , "DECIDE `same roster` a b IF a's members EQUALS b's members"
    ]

  recordListMaybeEqModule = Text.unlines
    [ "DECLARE Player HAS"
    , "    number IS A NUMBER"
    , ""
    , "DECLARE Team HAS"
    , "    reserves IS A LIST OF MAYBE Player"
    , ""
    , "@export"
    , "GIVEN a IS A Team"
    , "      b IS A Team"
    , "GIVETH A BOOLEAN"
    , "DECIDE `same reserves` a b IF a's reserves EQUALS b's reserves"
    ]

  -- Not a record: an ASSUMEd abstract category, whose values are atoms.
  abstractEqModule = Text.unlines
    [ "ASSUME Person IS A TYPE"
    , ""
    , "GIVEN a IS A Person"
    , "ASSUME `is a claimant` a IS A BOOLEAN"
    , ""
    , "GIVEN b IS A Person"
    , "ASSUME `is an assessor` b IS A BOOLEAN"
    , ""
    , "@export"
    , "GIVEN a IS A Person"
    , "      b IS A Person"
    , "GIVETH A BOOLEAN"
    , "DECIDE `self assessed` a b IF"
    , "  `is a claimant` a AND `is an assessor` b AND a EQUALS b"
    ]

  abstractListEqModule = Text.unlines
    [ "ASSUME Person IS A TYPE"
    , ""
    , "GIVEN p IS A Person"
    , "ASSUME `is a claimant` p IS A BOOLEAN"
    , ""
    , "DECLARE Panel HAS"
    , "    members IS A LIST OF Person"
    , ""
    , "@export"
    , "GIVEN a IS A Panel"
    , "      b IS A Panel"
    , "GIVETH A BOOLEAN"
    , "DECIDE `same panel` a b IF a's members EQUALS b's members"
    ]

  -- The recommended edit, kept green: same EQUALS, enum-sorted operands.
  recordFieldEqModule = Text.unlines
    [ "DECLARE Sign IS ONE OF Rock, Paper, Scissors"
    , ""
    , "DECLARE Player HAS"
    , "    throws IS A Sign"
    , ""
    , "@export"
    , "GIVEN p IS A Player"
    , "      q IS A Player"
    , "GIVETH A BOOLEAN"
    , "DECIDE `tied` p q IF p's throws EQUALS q's throws"
    ]

  -- A STRING-sorted stored field: refused, because there is no attribute value
  -- type it could be declared under. The corpus twin is
  -- `jl4/examples/blawx/not-ok/string-field.l4`.
  stringFieldModule = Text.unlines
    [ "DECLARE Sign IS ONE OF Rock, Paper, Scissors"
    , ""
    , "DECLARE Player HAS"
    , "    name   IS A STRING"
    , "    throws IS A Sign"
    , ""
    , "@export"
    , "GIVEN p IS A Player"
    , "GIVETH A BOOLEAN"
    , "DECIDE `throws rock` p IF p's throws EQUALS Rock"
    ]

  -- The same module with the field's sort changed to the enum the diagnostic
  -- recommends. Not `Name`: that and `name` both mangle to `name` and the
  -- injectivity check refuses the module for an unrelated-looking reason.
  enumFieldModule = Text.unlines
    [ "DECLARE PlayerName IS ONE OF Jane, Bob"
    , "DECLARE Sign IS ONE OF Rock, Paper, Scissors"
    , ""
    , "DECLARE Player HAS"
    , "    name   IS A PlayerName"
    , "    throws IS A Sign"
    , ""
    , "@export"
    , "GIVEN p IS A Player"
    , "GIVETH A BOOLEAN"
    , "DECIDE `throws rock` p IF p's throws EQUALS Rock"
    ]

  -- A STRING PARAMETER on a derived predicate of total arity 2, which gets no
  -- declaration block at all. Refused since 2026-09-02.
  stringParamModule = Text.unlines
    [ "DECLARE Sign IS ONE OF Rock, Paper, Scissors"
    , ""
    , "DECLARE Player HAS"
    , "    throws IS A Sign"
    , ""
    , "@export"
    , "GIVEN p IS A Player"
    , "      s IS A STRING"
    , "GIVETH A BOOLEAN"
    , "DECIDE `throws named` p s IF s EQUALS \"zebra\""
    ]

  -- A STRING RESULT on a nullary constant. Also `PCUndeclared`, also refused
  -- since 2026-09-02 -- this is the module §4.7 used to cite as its ADMITTED
  -- example, which is why the section's two bullets contradicted each other.
  stringResultModule = Text.unlines
    [ "ASSUME Player IS A TYPE"
    , ""
    , "GIVEN p IS A Player"
    , "ASSUME `is registered` p IS A BOOLEAN"
    , ""
    , "GIVETH A STRING"
    , "DECIDE `the house sign` IS \"rock\""
    , ""
    , "@export"
    , "GIVEN p IS A Player"
    , "GIVETH A BOOLEAN"
    , "DECIDE `qualifies` p IF"
    , "      `is registered` p"
    , "  AND `the house sign` EQUALS \"rock\""
    ]

  -- A string LITERAL in a rule body, with no STRING anywhere in a signature.
  -- `LIST OF STRING` is admitted as Blawx's untyped `list` (RSList does not
  -- inspect its element sort), so this is what a surviving literal looks like
  -- now that the three signature positions are all closed.
  stringLiteralModule = Text.unlines
    [ "DECLARE Player HAS"
    , "    aliases IS A LIST OF STRING"
    , ""
    , "@export"
    , "GIVEN p IS A Player"
    , "GIVETH A BOOLEAN"
    , "DECIDE `known as zebra` p IF p's aliases EQUALS LIST \"zebra\""
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
