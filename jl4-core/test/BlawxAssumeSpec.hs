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

    -- BLAWX-EXPORT-SPEC §11 W2, measured 2026-09-02. Blawx's attribute-type
    -- dropdown is a closed list -- boolean, number, date, time, datetime,
    -- duration, list, plus the declared categories
    -- (@blawx-blocks.js:5376@ and @:5577-5583@ on the stock v1.6.22-alpha
    -- checkout) -- and @scasp_generator.js@ has no per-type branch that could
    -- add one. So a string-sorted FIELD is refused, while a string LITERAL in a
    -- rule body is not: the two halves are pinned separately below, because
    -- §4.7 used to state the surviving half as though it covered both.
    it "refuses a STRING-sorted field, and says what to write instead" $
      case blawxYaml stringFieldModule of
        Right _  -> expectationFailure "expected a Blawx rejection for a STRING field"
        Left err -> do
          err `shouldSatisfy` Text.isInfixOf "STRING-sorted field or argument (Blawx)"
          err `shouldSatisfy` Text.isInfixOf "no string attribute type"
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

    it "still admits a string LITERAL in a rule body, as an atom" $ do
      -- The half of §4.7 that survives the narrowing. The literal reaches
      -- the s(CASP) through the program-global string-atom table and is
      -- compared by unification.
      out <- emitted stringLiteralModule
      hasLine out "Thehousesign = rock."

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

  -- A string LITERAL in a rule body, with no string-sorted field anywhere: the
  -- nullary constant is `PCUndeclared` (rules only, no declaration block), so
  -- the literal is the only string in sight and it survives as an atom.
  stringLiteralModule = Text.unlines
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
