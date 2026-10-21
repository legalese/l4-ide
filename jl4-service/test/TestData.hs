{-# LANGUAGE QuasiQuotes #-}

module TestData (
  rodentAndVerminFunctionSpec,
  rodentAndVerminFunction,
  rodentAndVerminJL4,
  constantFunctionSpec,
  constantFunction,
  constantJL4,
  qualifiesJL4,
  recordJL4,
  maybeParamJL4,
  maybeSynonymJL4,
  synonymWrapperJL4,
  saleContractJL4,
  deonticExportJL4,
  deonticDeadlineJL4,
  deonticShapesJL4,
  deonticLineBreakJL4,
  deonticRecordPartyJL4,
  spacedFieldsJL4,
  assumeParamJL4,
  assumeHelperJL4,
  refuseJL4,
  importedRecordDeclJL4,
  importedRecordMainJL4,
  dnfBlowupJL4,
  considerPlanJL4,
  twinLeavesJL4,
  missingBooleanJL4,
  sectionBooleanJL4,
  deonticBooleanJL4,
  considerBooleanJL4,
  decidedAnywayJL4,
  bareInputJL4,
  refusingConditionJL4,
  refusingDeepJL4,
  refusingOrJL4,
  refusingFirstJL4,
  refusingArmJL4,
  answeredConditionJL4,
  refusingDistributedJL4,
  refusingNotJL4,
  refusingImpliesJL4,
  refusingImpliesNestedJL4,
  refusingSeamOpenJL4,
  refusingBothArmsJL4,
  conditionalRefuserJL4,
  deonticConsiderJL4,
  maybeInputsJL4,
  timeInputsJL4,
  wireProbeJL4,
  declineLabelsJL4,
  twoDatesJL4,
  clauseGroupEnumJL4,
  handEnumJL4,
  letEnumJL4,
  clauseGroupMixedJL4,
  handMixedJL4,
  clauseGroupSingleJL4,
  handSingleJL4,
  clauseGroupCallJL4,
  handCallJL4,
  clauseTableJL4,
  handTableJL4,
  clauseTable2JL4,
  handTable2JL4,
  clauseNewNameJL4,
  handNewNameJL4,
  clauseGroupNoGivethJL4,
  clauseGroupLetResultJL4,
  rowsClauseGroupJL4,
  letChainJL4,
  inputThenInputJL4,
  longClausesJL4,
  longNumberClausesJL4,
  catchAllHugeJL4,
  handCatchAllHugeJL4,
  newNameHugeJL4,
  newNameDnfJL4,
  maybeTableJL4,
  exactlyNameDnfJL4,
  exactlyHugeJL4,
  dnfClauseJL4,
  handDnfJL4,
  ruleDefaultJL4,
  recordDefaultJL4,
  maybeHardJL4,
  sectionSecondJL4,
  twoDefaultsJL4,
  refuseDefaultJL4,
  exactDecimalJL4,
  enumSchemaJL4,
  wrapperNullJL4,
  enumNullJL4,
  recordWrapJL4,
  ownDecodeJL4,
  deonticDefaultJL4,
  spinJL4,
  spinOrRefuseJL4,
  spinWrapperJL4,
  powerJL4,
  heavyLibJL4,
  heavyMainJL4,
  deepJL4,
  partialClausesJL4,
  jsonDecodePersonJL4,
  taxpayerJL4,
  implicitFlagJL4,
  nameClashJL4,
  lineBreakJL4,
) where

import Backend.Jl4 as Jl4
import Backend.Api
import Compiler (toDecl)
import Types
import L4.FunctionSchema (Parameters (..), Parameter (..))

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except
import qualified Data.Map.Strict as Map
import Data.String.Interpolate
import Data.Text (Text)
import qualified Data.Text as Text

rodentAndVerminFunctionSpec :: IO ValidatedFunction
rodentAndVerminFunctionSpec = either (error . show) id <$> runExceptT rodentAndVerminFunction

rodentAndVerminFunction :: ExceptT EvaluatorError IO ValidatedFunction
rodentAndVerminFunction = do
  let
    fnDecl =
      Function
        { name = "vermin_and_rodent"
        , description = "Example description"
        , parameters =
            let
              params =
                Map.fromList
                  [ ("Loss or Damage.caused by insects", Parameter "string" Nothing Nothing ["true", "false"] "Was the damage caused by insects?" Nothing Nothing Nothing Nothing Nothing Nothing)
                  , ("Loss or Damage.caused by birds", Parameter "string" Nothing Nothing ["true", "false"] "Was the damage caused by birds?" Nothing Nothing Nothing Nothing Nothing Nothing)
                  , ("Loss or Damage.caused by vermin", Parameter "string" Nothing Nothing ["true", "false"] "Was the damage caused by vermin?" Nothing Nothing Nothing Nothing Nothing Nothing)
                  , ("Loss or Damage.caused by rodents", Parameter "string" Nothing Nothing ["true", "false"] "Was the damage caused by rodents?" Nothing Nothing Nothing Nothing Nothing Nothing)
                  , ("Loss or Damage.to Contents", Parameter "string" Nothing Nothing ["true", "false"] "Is the damage to your contents?" Nothing Nothing Nothing Nothing Nothing Nothing)
                  , ("Loss or Damage.ensuing covered loss", Parameter "string" Nothing Nothing ["true", "false"] "Is the damage ensuing covered loss" Nothing Nothing Nothing Nothing Nothing Nothing)
                  , ("any other exclusion applies", Parameter "string" Nothing Nothing ["true", "false"] "Are any other exclusions besides mentioned ones?" Nothing Nothing Nothing Nothing Nothing Nothing)
                  , ("a household appliance", Parameter "string" Nothing Nothing ["true", "false"] "Did water escape from a household appliance due to an animal?" Nothing Nothing Nothing Nothing Nothing Nothing)
                  , ("a swimming pool", Parameter "string" Nothing Nothing ["true", "false"] "Did water escape from a swimming pool due to an animal?" Nothing Nothing Nothing Nothing Nothing Nothing)
                  , ("a plumbing, heating, or air conditioning system", Parameter "string" Nothing Nothing ["true", "false"] "Did water escape from a plumbing, heating or conditioning system due to an animal?" Nothing Nothing Nothing Nothing Nothing Nothing)
                  ]
            in
              MkParameters
                { parameterMap = params
                , required = Map.keys params
                }
        , supportedEvalBackend = [JL4]
        , deonticPartyType = Nothing
        , deonticActionType = Nothing
        , returnType = "BOOLEAN"
        , returnSchema = Nothing
        , isDeontic = False
        }
  (runFn, mCompiled) <- liftIO $ Jl4.createFunction "vermin_and_rodent.l4" (toDecl fnDecl) rodentAndVerminJL4 Map.empty
  pure $
    ValidatedFunction
      { fnImpl = fnDecl
      , fnEvaluator = Map.fromList [(JL4, runFn)]
      , fnCompiled = mCompiled
      , fnSourceText = rodentAndVerminJL4
      , fnModuleContext = Map.empty
      , fnDecisionQueryCache = Nothing
      }

rodentAndVerminJL4 :: Text
rodentAndVerminJL4 =
  [i|
GIVEN
  `Loss or Damage.caused by rodents` IS A BOOLEAN
  `Loss or Damage.caused by insects` IS A BOOLEAN
  `Loss or Damage.caused by vermin` IS A BOOLEAN
  `Loss or Damage.caused by birds` IS A BOOLEAN
  `Loss or Damage.to Contents` IS A BOOLEAN
  `any other exclusion applies` IS A BOOLEAN
  `a household appliance` IS A BOOLEAN
  `a swimming pool` IS A BOOLEAN
  `a plumbing, heating, or air conditioning system` IS A BOOLEAN
  `Loss or Damage.ensuing covered loss` IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `vermin_and_rodent` IF
    `not covered if`
         `loss or damage by animals`
     AND NOT               `damage to contents and caused by birds`
                OR         `ensuing covered loss`
                    AND NOT `exclusion apply`
 WHERE
    `not covered if` MEANS GIVEN x YIELD x

    `loss or damage by animals` MEANS
        `Loss or Damage.caused by rodents`
     OR `Loss or Damage.caused by insects`
     OR `Loss or Damage.caused by vermin`
     OR `Loss or Damage.caused by birds`

    `damage to contents and caused by birds` MEANS
         `Loss or Damage.to Contents`
     AND `Loss or Damage.caused by birds`

    `ensuing covered loss` MEANS
        `Loss or Damage.ensuing covered loss`

    `exclusion apply` MEANS
        `any other exclusion applies`
     OR `a household appliance`
     OR `a swimming pool`
     OR `a plumbing, heating, or air conditioning system`
|]

constantFunctionSpec :: IO ValidatedFunction
constantFunctionSpec = either (error . show) id <$> runExceptT constantFunction

constantFunction :: ExceptT EvaluatorError IO ValidatedFunction
constantFunction = do
  let
    fnDecl =
      Function
        { name = "the_answer"
        , description = "A constant function with no parameters that returns 42"
        , parameters =
            MkParameters
              { parameterMap = Map.empty
              , required = []
              }
        , supportedEvalBackend = [JL4]
        , deonticPartyType = Nothing
        , deonticActionType = Nothing
        , returnType = "NUMBER"
        , returnSchema = Nothing
        , isDeontic = False
        }
  (runFn, mCompiled) <- liftIO $ Jl4.createFunction "the_answer.l4" (toDecl fnDecl) constantJL4 Map.empty
  pure $
    ValidatedFunction
      { fnImpl = fnDecl
      , fnEvaluator = Map.fromList [(JL4, runFn)]
      , fnCompiled = mCompiled
      , fnSourceText = constantJL4
      , fnModuleContext = Map.empty
      , fnDecisionQueryCache = Nothing
      }

constantJL4 :: Text
constantJL4 =
  [i|
GIVETH A NUMBER
DECIDE the_answer IS 42
|]

-- | A function whose answer is a string holding a line break or a tab.
--
-- The reasoning tree prints each step as source code, so the literal reaches
-- @exampleCode@ spelled the way the source spells it (@"line\nnext"@, a
-- backslash and an n), while @explanation@ prints the VALUE and keeps the
-- break. Written as plain lines, not through the interpolating quasi-quoter,
-- which would turn the backslash pairs into the characters they spell.
lineBreakJL4 :: Text
lineBreakJL4 =
  Text.unlines
    [ "@export default the text"
    , "GIVEN x IS A NUMBER"
    , "GIVETH A STRING"
    , "DECIDE s x IS"
    , "    IF x > 0"
    , "    THEN \"line\\nnext\""
    , "    ELSE \"tab\\there\""
    ]

-- | L4 source for the "compute_qualifies" function used in integration tests.
qualifiesJL4 :: Text
qualifiesJL4 =
  [i|
@export default person qualifies
GIVEN walks IS A BOOLEAN
      eats  IS A BOOLEAN
      drinks IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE compute_qualifies IF walks AND eats AND drinks
|]

-- | A decision with TWIN atoms: one compound leaf written twice.
--
-- @n GREATER THAN 5@ is not a bare boolean binder, so each occurrence goes
-- through 'L4.Viz.Ladder.leafFromExpr', which mints a fresh @unique@ per
-- occurrence. The two occurrences are one term, so they share one C1 key and
-- one atomId between them ("L4.Viz.AtomKey"): one question, two BDD variables.
--
-- Answering that question FALSE refutes both disjuncts and settles the whole
-- decision — but only if the binding reaches both variables. That makes "did
-- the answer land" observable on the wire as a change in @determined@, rather
-- than as a property of a map. Used by the atomId tests in 'IntegrationSpec'.
twinLeavesJL4 :: Text
twinLeavesJL4 =
  [i|
@export twins
GIVEN n IS A NUMBER
      p IS A BOOLEAN
      q IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE twins IF (n GREATER THAN 5 AND p) OR (n GREATER THAN 5 AND q)
|]

-- | @(x0 AND x1) OR (x2 AND x3) OR …@ over @n@ boolean parameters, as an
-- @\@export@.
--
-- Small in the source and enormous in the ladder: reaching the AND/OR normal
-- form a ladder draws distributes OR over AND, so this expands to 2^(n/2)
-- clauses. Used to pin the @maxLadderNodes@ refusal on the HTTP surface, where
-- it matters most — @\/ladder@ is an unauthenticated, CORS-open GET.
dnfBlowupJL4 :: Int -> Text
dnfBlowupJL4 n =
  Text.unlines
    [ "@export blowup"
    , "GIVEN " <> Text.intercalate "\n      " [param k <> " IS A BOOLEAN" | k <- [0 .. n - 1]]
    , "GIVETH A BOOLEAN"
    , "DECIDE blowup IF "
        <> Text.intercalate " OR "
             [ "(" <> param k <> " AND " <> param (k + 1) <> ")" | k <- [0, 2 .. n - 2] ]
    ]
 where
  param k = "x" <> Text.pack (show (k :: Int))

-- | A boolean function that @CONSIDER@s an enumeration of @n@ kinds, each
-- branch an @OR@ of three string tests, as an @\@export@.
--
-- Cheap to build the cached decision structure of, and out of reach for a
-- query plan: the plan is read off a normal form in which each branch
-- carries its own tests together with the choice of its kind. Used to pin
-- that computing a plan is held to @--eval-timeout@, which the build of the
-- cache has its own limit for and the plan itself did not. The shape is that
-- of a classifier in the public miles-card encoding, whose plan the service
-- could not finish within its limit.
considerPlanJL4 :: Int -> Text
considerPlanJL4 n =
  Text.unlines $
    [ "DECLARE Kind IS ONE OF " <> Text.intercalate ", " [kind k | k <- [0 .. n - 1]]
    , ""
    , "GIVEN d IS A STRING"
    , "      s IS A STRING"
    , "GIVETH A BOOLEAN"
    , "`has` d s MEANS d EQUALS s"
    , ""
    , "@export carries"
    , "GIVEN d IS A STRING"
    , "      p IS A Kind"
    , "GIVETH A BOOLEAN"
    , "carries d p MEANS"
    , "    CONSIDER p"
    ]
      <> [ "    WHEN " <> kind k <> " THEN " <> Text.intercalate " OR " [ "`has` d \"" <> lit <> Text.pack (show k) <> "\"" | lit <- ["a", "b", "c"] ]
         | k <- [0 .. n - 1] ]
 where
  kind k = "kind" <> Text.pack (show (k :: Int))

-- | L4 source with a module-level ASSUME referenced by an @export.
-- Exercises the ASSUME→parameter promotion path in the direct-AST
-- evaluator: the caller supplies both the GIVEN and the ASSUME value.
assumeParamJL4 :: Text
assumeParamJL4 =
  [i|
ASSUME age IS A NUMBER

@export Check adult status
GIVEN threshold IS A NUMBER
GIVETH A BOOLEAN
DECIDE is_adult IF age >= threshold
|]

-- | L4 source whose @export REFUSES for one input and answers for another.
-- Exercises the refusal path in the direct-AST evaluator: a refusal must reach
-- the caller as its own error kind, not as an 'InterpreterError' (which reads
-- as a server fault).
refuseJL4 :: Text
refuseJL4 =
  [i|
GIVETH A NUMBER
`this schedule is not encoded for years before 2000` MEANS
    REFUSE "this schedule is not encoded for years before 2000"

@export The fee for a rule year
GIVEN y IS A NUMBER
GIVETH A NUMBER
fee y MEANS
    IF y >= 2000
    THEN 100
    ELSE `this schedule is not encoded for years before 2000`
|]

-- | L4 source whose @export reads a module-level ASSUME only through a
-- helper. The read-set is transitive, so @age@ is a parameter of
-- @may_drive@ (in the schema, and bound for the helper at evaluation).
assumeHelperJL4 :: Text
assumeHelperJL4 =
  [i|
ASSUME age IS A NUMBER

GIVETH A BOOLEAN
DECIDE is_adult IF age >= 18

@export May drive: adult and licensed
GIVEN licensed IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE may_drive IF is_adult AND licensed
|]

-- | L4 source returning a record type, for testing named fields in JSON output.
recordJL4 :: Text
recordJL4 =
  [i|
DECLARE Person HAS
    name IS A STRING
    age IS A NUMBER

@export
GIVEN n IS A STRING
      a IS A NUMBER
GIVETH A Person
DECIDE make_person IS Person WITH name IS n, age IS a
|]

-- | L4 source with a MAYBE parameter, for testing null/NOTHING handling.
maybeParamJL4 :: Text
maybeParamJL4 =
  [i|
IMPORT prelude

DECLARE Result HAS
    label IS A STRING
    extra_provided IS A BOOLEAN

@export
GIVEN label IS A STRING
      extra IS A MAYBE STRING
GIVETH A Result
DECIDE with_maybe IS Result WITH
    label IS label
    extra_provided IS
        CONSIDER extra
            WHEN JUST x THEN TRUE
            WHEN NOTHING THEN FALSE
|]

-- | Inputs declared through a synonym for a record, an enum, a DATE, a LIST, a
-- BOOLEAN, a TIME and a DATETIME, each with a spare MAYBE input, pad, that the
-- rule never reads: sending pad as @null@ or @{}@ sends the request through the
-- generated wrapper. 'Backend.Jl4.wrapperPlan' decodes an input that is not a
-- MAYBE, a BOOLEAN or a DATE/TIME/DATETIME as its own type, and the JSON
-- decoder expands a synonym, so all of these answer. The two @plain@ functions
-- take a record and a DATE written out, and are the control. @nested hue@ is a
-- synonym below the head of the type (@MAYBE Hue@), as the last input, with a
-- @null@ inside a record forcing the wrapper; @nested colour plain@ is its control.
synonymWrapperJL4 :: Text
synonymWrapperJL4 =
  [i|
DECLARE Pt HAS x IS A NUMBER

DECLARE Point IS A Pt

DECLARE Colour IS ONE OF Red, Green

DECLARE Hue IS A Colour

DECLARE Deadline IS A DATE

DECLARE Year IS A NUMBER

DECLARE Years IS A LIST OF Year

DECLARE Flag IS A BOOLEAN

DECLARE Clock IS A TIME

DECLARE Stamp IS A DATETIME

@export the x of a record, through a synonym
GIVEN p IS A Point
      pad IS A MAYBE NUMBER
GIVETH A NUMBER
`point x` p pad MEANS p's x

@export a code for an enum, through a synonym
GIVEN h IS A Hue
      pad IS A MAYBE NUMBER
GIVETH A NUMBER
`hue code` h pad MEANS IF h EQUALS Red THEN 1 ELSE 2

@export the year of a DATE, through a synonym
GIVEN d IS A Deadline
      pad IS A MAYBE NUMBER
GIVETH A NUMBER
`deadline year` d pad MEANS DATE_YEAR d

@export the x of a record written out, the control
GIVEN p IS A Pt
      pad IS A MAYBE NUMBER
GIVETH A NUMBER
`plain point x` p pad MEANS p's x

@export the year of a DATE written out, the control
GIVEN d IS A DATE
      pad IS A MAYBE NUMBER
GIVETH A NUMBER
`plain deadline year` d pad MEANS DATE_YEAR d

@export the first of a list, through a synonym
GIVEN ys IS A Years
      pad IS A MAYBE NUMBER
GIVETH A NUMBER
`first year` ys pad MEANS
  CONSIDER ys
    WHEN EMPTY THEN 0
    WHEN y FOLLOWED BY rest THEN y

@export a code for a BOOLEAN, through a synonym
GIVEN b IS A Flag
      pad IS A MAYBE NUMBER
GIVETH A NUMBER
`flag code` b pad MEANS IF b THEN 1 ELSE 0

@export an answer that does not read a TIME, through a synonym
GIVEN t IS A Clock
      pad IS A MAYBE NUMBER
GIVETH A NUMBER
`clock code` t pad MEANS 5

@export an answer that does not read a DATETIME, through a synonym
GIVEN dt IS A Stamp
      pad IS A MAYBE NUMBER
GIVETH A NUMBER
`stamp code` dt pad MEANS 6

DECLARE Rec HAS f IS A MAYBE NUMBER

GIVEN c IS A Colour
GIVETH A NUMBER
`colour number` c MEANS IF c EQUALS Red THEN 1 ELSE 2

@export a synonym below the head of an input's type
GIVEN r IS A Rec
      h IS A MAYBE Hue
GIVETH A NUMBER
`nested hue` r h MEANS
  CONSIDER h
    WHEN NOTHING THEN 0
    WHEN JUST c THEN `colour number` c

@export the same with the enum written out, the control
GIVEN r IS A Rec
      h IS A MAYBE Colour
GIVETH A NUMBER
`nested colour plain` r h MEANS
  CONSIDER h
    WHEN NOTHING THEN 0
    WHEN JUST c THEN `colour number` c
|]

-- | Inputs declared through a type synonym for a MAYBE: one without a type
-- parameter, and one that takes a type (@Optional OF NUMBER@). Each answers
-- NOTHING for a null, a @{}@ or a left-out input, as @MAYBE NUMBER@ itself
-- does, which is the control.
maybeSynonymJL4 :: Text
maybeSynonymJL4 =
  [i|
DECLARE MaybeYear IS A MAYBE NUMBER

DECLARE Optional OF a IS A MAYBE a

@export a year that may be left out, through a synonym
GIVEN y IS A MaybeYear
GIVETH A NUMBER
`year maybe` y MEANS
  CONSIDER y
    WHEN JUST n THEN n PLUS 1
    WHEN NOTHING THEN 0

@export a number that may be left out, through a synonym that takes a type
GIVEN y IS AN Optional OF NUMBER
GIVETH A NUMBER
`optional number` y MEANS
  CONSIDER y
    WHEN JUST n THEN n PLUS 1
    WHEN NOTHING THEN 0

@export a plain MAYBE, the control
GIVEN y IS A MAYBE NUMBER
GIVETH A NUMBER
`plain maybe` y MEANS
  CONSIDER y
    WHEN JUST n THEN n PLUS 1
    WHEN NOTHING THEN 0
|]

-- | L4 source with an exported boolean function and a regulative (sale contract) rule.
-- Used for testing state graph extraction and DOT output.
saleContractJL4 :: Text
saleContractJL4 =
  [i|
DECLARE Party IS ONE OF `the seller`, `the buyer`
DECLARE `Contract Action` IS ONE OF `deliver the goods`, `pay the invoice`

@export default test function
GIVEN walks IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE test_fn IF walks

GIVETH A DEONTIC Party `Contract Action`
`the sale contract` MEANS
    PARTY `the seller`
    MUST `deliver the goods`
    WITHIN 14
    HENCE
        PARTY `the buyer`
        MUST `pay the invoice`
        WITHIN 30
        HENCE FULFILLED
        LEST BREACH
    LEST BREACH
|]

-- | L4 source with an exported deontic function for testing contract simulation.
-- The sale contract has no GIVEN parameters — it's a standalone deontic rule.
deonticExportJL4 :: Text
deonticExportJL4 =
  [i|
DECLARE Party IS ONE OF `the seller`, `the buyer`
DECLARE `Contract Action` IS ONE OF `deliver the goods`, `pay the invoice`

@export default sale contract
GIVETH A DEONTIC Party `Contract Action`
`the sale contract` MEANS
    PARTY `the seller`
    MUST `deliver the goods`
    WITHIN 14
    HENCE
        PARTY `the buyer`
        MUST `pay the invoice`
        WITHIN 30
        HENCE FULFILLED
        LEST BREACH
    LEST BREACH
|]

-- | As 'deonticExportJL4', but the seller's obligation has no @LEST@: missing
-- its deadline is a breach the evaluator reports as @deadline_missed@, naming
-- the event that revealed it, the obligation that was missed, and the failure.
deonticDeadlineJL4 :: Text
deonticDeadlineJL4 =
  [i|
DECLARE Party IS ONE OF `the seller`, `the buyer`
DECLARE `Contract Action` IS ONE OF `deliver the goods`, `pay the invoice`

@export default sale contract
GIVETH A DEONTIC Party `Contract Action`
`the sale contract` MEANS
    PARTY `the seller`
    MUST `deliver the goods`
    WITHIN 14
|]

-- | Four shapes of party and action, each with a space in a name: the operands
-- of a @ROR@ and of a @RAND@, an action the rule does not declare (a binder),
-- and a party that is a @GIVEN@ input.
deonticShapesJL4 :: Text
deonticShapesJL4 =
  [i|
DECLARE Party IS ONE OF `the seller`, `the buyer`
DECLARE `Contract Action` IS ONE OF `deliver the goods`, `pay the invoice`, `inspect the goods`

@export default alternative
GIVETH A DEONTIC Party `Contract Action`
`the alternative` MEANS
    (PARTY `the seller` MUST `deliver the goods` WITHIN 14)
    ROR
    (PARTY `the buyer` MUST `pay the invoice` WITHIN 30)

@export default conjunction
GIVETH A DEONTIC Party `Contract Action`
`the conjunction` MEANS
    (PARTY `the seller` MUST `deliver the goods` WITHIN 14)
    RAND
    (PARTY `the buyer` MUST `pay the invoice` WITHIN 30)

@export default binder
GIVETH A DEONTIC Party `Contract Action`
`the binder` MEANS
    PARTY `the seller`
    MUST `some act`
    WITHIN 10

@export default given party
GIVEN `the payer` IS A Party
GIVETH A DEONTIC Party `Contract Action`
`the given party` MEANS
    PARTY `the payer`
    MUST `deliver the goods`
    WITHIN 10
    HENCE FULFILLED
    LEST BREACH
|]

-- | A contract whose one action carries a string with a line break in it. The
-- action is rule source, not a name, so the answer prints it escaped (R2,
-- 2026-10-12). Written as plain lines, like 'lineBreakJL4', for the same reason.
deonticLineBreakJL4 :: Text
deonticLineBreakJL4 =
  Text.unlines
    [ "DECLARE Party IS ONE OF Alice"
    , "DECLARE Act IS ONE OF"
    , "  say HAS text IS A STRING"
    , ""
    , "@export default the contract"
    , "GIVETH A DEONTIC Party Act"
    , "`the contract` MEANS"
    , "  PARTY Alice"
    , "  MUST say \"pay\\nnow\""
    , "  WITHIN 10"
    , "  HENCE FULFILLED"
    , "  LEST BREACH"
    ]

-- | L4 source with a deontic function that uses record-typed parties.
-- Tests that events with JSON object parties (e.g. {"name": "Alice"})
-- are correctly formatted as L4 record construction (Driver WITH name IS "Alice")
-- rather than backtick-quoted identifiers.
-- | L4 source with spaced field names, for testing hyphenated key remapping.
-- Parameters use backtick identifiers with spaces that get sanitized to hyphens
-- in the API/MCP schema.
spacedFieldsJL4 :: Text
spacedFieldsJL4 =
  [i|
@export default person check
GIVEN `first name` IS A STRING
      `is a citizen` IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `check person` IF `is a citizen`
|]

-- | Two-file fixture: a DECLARE'd record lives in the imported file and
-- the @export'd function in the main file takes it as a parameter. Used
-- to check that cross-file record parameters are resolvable on
-- /evaluation — a regression site for the direct-AST fast path that
-- only walks the entry module's own section for DECLAREs.
importedRecordDeclJL4 :: Text
importedRecordDeclJL4 =
  [i|
DECLARE Applicant HAS
    name IS A STRING
    age  IS A NUMBER
|]

importedRecordMainJL4 :: Text
importedRecordMainJL4 =
  [i|
IMPORT imported_record_decl.l4

@export
GIVEN applicant IS A Applicant
GIVETH A BOOLEAN
DECIDE `applicant is an adult` IS applicant's age >= 18
|]

deonticRecordPartyJL4 :: Text
deonticRecordPartyJL4 =
  [i|
DECLARE Car HAS
    `number of wheels` IS A NUMBER

DECLARE Driver HAS
    name IS A STRING

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

@export default seatbelt requirement
GIVEN car    IS A Car
      driver IS A Driver
GIVETH A PROVISION OF Driver, `Driver Action`
`Seatbelt Requirement` MEANS
    IF      car's `number of wheels` EQUALS 4
    THEN    PARTY driver
            MUST `wear seatbelt`
            WITHIN 1
            HENCE
                PARTY driver
                MAY `drive`
    ELSE    PARTY driver
            MAY `drive`
|]

-- | Three BOOLEAN inputs, one of which the rule never reads. A @{}@ on any of
-- them sends the request through the generated wrapper, which read every
-- missing BOOLEAN as FALSE until smucclaw/l4-ide#992.
missingBooleanJL4 :: Text
missingBooleanJL4 =
  [i|
@export default eligible
GIVEN `has criminal record` IS A BOOLEAN
      `is resident`         IS A BOOLEAN
      `unused flag`         IS A BOOLEAN
GIVETH A BOOLEAN
eligible MEANS `is resident` AND NOT `has criminal record`
|]

-- | A section GIVEN BOOLEAN with a default, beside two rule GIVEN BOOLEANs,
-- one of them unread. On the wrapper path this used to fail with "could not
-- find a definition for the identifier fromMaybe", which hid that the wrapper
-- never delivered a section GIVEN's value: the rule read its default instead.
sectionBooleanJL4 :: Text
sectionBooleanJL4 =
  [i|
§ `Capacity`
    GIVEN `has capacity` IS A BOOLEAN TYPICALLY TRUE

@export default may contract
GIVEN `is adult`    IS A BOOLEAN
      `unused flag` IS A BOOLEAN
GIVETH A BOOLEAN
`may contract` MEANS `has capacity` AND `is adult`
|]

-- | A deontic rule that branches on a BOOLEAN input. Deontic functions always
-- take the wrapper path, so a missing input used to take the ELSE branch.
deonticBooleanJL4 :: Text
deonticBooleanJL4 =
  [i|
DECLARE Driver HAS
    name IS A STRING

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

@export default seatbelt requirement
GIVEN driver        IS A Driver
      `is motorway` IS A BOOLEAN
GIVETH A PROVISION OF Driver, `Driver Action`
`seatbelt requirement` MEANS
    IF      `is motorway`
    THEN    PARTY driver
            MUST `wear seatbelt`
            WITHIN 1
    ELSE    PARTY driver
            MAY `drive`
|]

-- | A BOOLEAN input read by a CONSIDER with an OTHERWISE. Until
-- UNKNOWN-EVALUATION-SPEC §8 step 1, a missing one on the wrapper path failed
-- the WHEN TRUE pattern and the OTHERWISE took it, so the answer was the
-- OTHERWISE's value, with a 200.
considerBooleanJL4 :: Text
considerBooleanJL4 =
  [i|
@export default fee
GIVEN `is member`   IS A BOOLEAN
      amount        IS A NUMBER
      `unused flag` IS A BOOLEAN
GIVETH A NUMBER
fee MEANS
    CONSIDER `is member`
    WHEN TRUE THEN 0
    OTHERWISE amount
|]

-- | A rule that reads a BOOLEAN input whose value cannot change its answer:
-- from UNKNOWN-EVALUATION-SPEC §8 step 3, a missing one is no reason to stop.
decidedAnywayJL4 :: Text
decidedAnywayJL4 =
  [i|
@export default eligible
GIVEN `has criminal record` IS A BOOLEAN
      `unused flag`         IS A BOOLEAN
GIVETH A BOOLEAN
eligible MEANS `has criminal record` OR TRUE
|]

-- | 'deonticBooleanJL4' with the branch written as a CONSIDER and an
-- OTHERWISE, which a missing input used to take.
deonticConsiderJL4 :: Text
deonticConsiderJL4 =
  [i|
DECLARE Driver HAS
    name IS A STRING

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

@export default seatbelt requirement
GIVEN driver        IS A Driver
      `is motorway` IS A BOOLEAN
GIVETH A PROVISION OF Driver, `Driver Action`
`seatbelt requirement` MEANS
    CONSIDER `is motorway`
    WHEN TRUE THEN
        PARTY driver
        MUST `wear seatbelt`
        WITHIN 1
    OTHERWISE
        PARTY driver
        MAY `drive`
|]

-- | A MAYBE DATE and a MAYBE NUMBER input, each followed by another input. On
-- the wrapper path the generated record printed their types as `MAYBE OF …`,
-- whose OF read the next field's line as another argument.
maybeInputsJL4 :: Text
maybeInputsJL4 =
  [i|
@export default dated
GIVEN `start date` IS A MAYBE DATE
      count        IS A MAYBE NUMBER
      flag         IS A BOOLEAN
      unused       IS A BOOLEAN
GIVETH A BOOLEAN
dated MEANS
      flag
  AND NOT `start date` EQUALS NOTHING
  AND NOT count EQUALS NOTHING
|]

-- | A TIME and a DATETIME input. The wrapper decodes each from a JSON string and
-- parses it with TOTIME or TODATETIME; it used to declare the record field as
-- TIME or DATETIME, so the parse was applied to a value that was not a string.
timeInputsJL4 :: Text
timeInputsJL4 =
  [i|
@export default timed
GIVEN flag   IS A BOOLEAN
      unused IS A BOOLEAN
      t      IS A TIME
      dt     IS A DATETIME
GIVETH A BOOLEAN
timed MEANS flag
|]

-- | One function per shape of answer. Every one but @pass@ has a spare MAYBE
-- input, pad, that the rule never reads: sending pad as 1 keeps a request on
-- the direct path, and sending it as {} sends the request through the
-- generated wrapper, which answers @JUST (f args)@. A superset of the repro in
-- smucclaw/l4-ide#1003, covering the 28 requests measured for it, and two
-- constructors a rule may call Nothing and Just.
wireProbeJL4 :: Text
wireProbeJL4 =
  [i|
DECLARE Outcome IS ONE OF `fully covered`, `not covered`

DECLARE Pair HAS
  left  IS A NUMBER
  right IS A NUMBER

DECLARE Solo HAS
  only IS A NUMBER

DECLARE Penalty IS ONE OF Nothing, Fine

DECLARE Verdict IS ONE OF
  Just HAS reason IS A STRING
  Unjust

@export cap at ten
GIVEN n IS A NUMBER
      pad IS A MAYBE NUMBER
GIVETH A MAYBE NUMBER
DECIDE `cap` IS IF n > 10 THEN JUST n ELSE NOTHING

@export pass through
GIVEN x IS A MAYBE NUMBER
GIVETH A MAYBE NUMBER
DECIDE `pass` IS x

@export one element list
GIVEN n IS A NUMBER
      pad IS A MAYBE NUMBER
GIVETH A LIST OF NUMBER
DECIDE `single` IS LIST n

@export two element list
GIVEN n IS A NUMBER
      pad IS A MAYBE NUMBER
GIVETH A LIST OF NUMBER
DECIDE `double list` IS LIST n, n

@export empty list
GIVEN n IS A NUMBER
      pad IS A MAYBE NUMBER
GIVETH A LIST OF NUMBER
DECIDE `none` IS EMPTY

@export maybe a one element list
GIVEN n IS A NUMBER
      pad IS A MAYBE NUMBER
GIVETH A MAYBE (LIST OF NUMBER)
DECIDE `maybe single` IS JUST (LIST n)

@export enum with spaces
GIVEN n IS A NUMBER
      pad IS A MAYBE NUMBER
GIVETH AN Outcome
DECIDE `outcome` IS IF n > 10 THEN `fully covered` ELSE `not covered`

@export two-field record
GIVEN n IS A NUMBER
      pad IS A MAYBE NUMBER
GIVETH A Pair
DECIDE `pair` IS Pair WITH left IS n, right IS n PLUS 1

@export one-field record
GIVEN n IS A NUMBER
      pad IS A MAYBE NUMBER
GIVETH A Solo
DECIDE `solo` IS Solo WITH only IS n

@export boolean
GIVEN n IS A NUMBER
      pad IS A MAYBE NUMBER
GIVETH A BOOLEAN
DECIDE `big` IF n > 10

@export plain number
GIVEN n IS A NUMBER
      pad IS A MAYBE NUMBER
GIVETH A NUMBER
DECIDE `twice` IS n TIMES 2

@export an enum with a constructor called Nothing
GIVEN n IS A NUMBER
      pad IS A MAYBE NUMBER
GIVETH A Penalty
DECIDE `penalty` IS IF n > 10 THEN Fine ELSE Nothing

@export a constructor called Just
GIVEN n IS A NUMBER
      pad IS A MAYBE NUMBER
GIVETH A Verdict
DECIDE `verdict` IS IF n > 10 THEN Unjust ELSE Just "lawful"
|]

-- | A DATE as a written ASSUME and as a section GIVEN, with no default, read
-- by the rule. The wrapper reads a DATE from a string and unwraps it, so a
-- missing one makes it answer NOTHING; the service then names the input.
declineLabelsJL4 :: Text
declineLabelsJL4 =
  [i|
ASSUME `start date` IS A DATE

§ `Term`
    GIVEN `end date` IS A DATE

@export dated
GIVEN flag   IS A BOOLEAN
      unused IS A BOOLEAN
GIVETH A DATE
dated MEANS IF flag THEN `start date` ELSE `end date`
|]

-- | Two DATE inputs. TODATE reads "2026/01/31" although the direct path's ISO
-- parser does not, so when the other one is not a date at all, the service
-- must name that one.
twoDatesJL4 :: Text
twoDatesJL4 =
  [i|
@export two dates
GIVEN `d one` IS A DATE
      `d two` IS A DATE
      pad     IS A MAYBE NUMBER
GIVETH A NUMBER
DECIDE `later` IS 1
|]

-- | A rule GIVEN with a TYPICALLY default, beside an unread input that lets a
-- test send the request down the wrapper path with a @{}@ (W3 of
-- specs/todo/TYPICALLY-ONE-BEHAVIOUR-SPEC.md).
ruleDefaultJL4 :: Text
ruleDefaultJL4 =
  [i|
@export default may contract
GIVEN `has capacity` IS A BOOLEAN TYPICALLY TRUE
      `is adult`     IS A BOOLEAN
      `unused flag`  IS A BOOLEAN
GIVETH A BOOLEAN
`may contract` MEANS `is adult` AND `has capacity`
|]

-- | Record-field defaults, one of them an enum constructor, and an enum
-- default on a rule GIVEN (W3, T1b). A request that leaves @timeout@ out of
-- @cfg@ gets 30, and @presumed@ names it @cfg.timeout@.
recordDefaultJL4 :: Text
recordDefaultJL4 =
  [i|
DECLARE Colour IS ONE OF Red, Green

DECLARE Config HAS
  timeout IS A NUMBER TYPICALLY 30
  retries IS A NUMBER
  colour  IS A Colour TYPICALLY Red

@export default budget
GIVEN cfg   IS A Config
      shade IS A Colour TYPICALLY Green
GIVETH A NUMBER
budget MEANS
  IF cfg's colour EQUALS Red AND shade EQUALS Green
  THEN cfg's timeout PLUS cfg's retries
  ELSE 0
|]

-- | A MAYBE input with no default (T1b, T3c's MAYBE paragraph): left out, it
-- is NOTHING while presumption is soft, and missing while it is hard. A @{}@
-- on the unread BOOLEAN sends a request to the wrapper path.
maybeHardJL4 :: Text
maybeHardJL4 =
  [i|
@export default premium due
GIVEN `unused flag` IS A BOOLEAN
      premium       IS A MAYBE NUMBER
GIVETH A NUMBER
`premium due` MEANS
  CONSIDER premium
    WHEN JUST p THEN p
    WHEN NOTHING THEN 0
|]

-- | A section GIVEN with a default that the rule reads SECOND, so that
-- @is adult@ FALSE never forces it: the test that @presumed@ lists a default
-- only when it is read, not when discharge binds it at the root (T6).
sectionSecondJL4 :: Text
sectionSecondJL4 =
  [i|
§ `Capacity`
    GIVEN `has capacity` IS A BOOLEAN TYPICALLY TRUE

@export default may contract
GIVEN `is adult`    IS A BOOLEAN
      `unused flag` IS A BOOLEAN
GIVETH A BOOLEAN
`may contract` MEANS `is adult` AND `has capacity`
|]

-- | Two defaulted inputs, a section GIVEN and a rule GIVEN, for the test that
-- presumption hard names every one a request leaves out.
twoDefaultsJL4 :: Text
twoDefaultsJL4 =
  [i|
§ `Capacity`
    GIVEN `has capacity` IS A BOOLEAN TYPICALLY TRUE

@export default may contract
GIVEN `is adult`     IS A BOOLEAN
      `of sound mind` IS A BOOLEAN TYPICALLY TRUE
GIVETH A BOOLEAN
`may contract` MEANS `is adult` AND `has capacity` AND `of sound mind`
|]

-- | A refusal that rests on a default: @is resident@ left out is FALSE, and
-- FALSE refuses (review M5). The refusal must say it rests on the default.
refuseDefaultJL4 :: Text
refuseDefaultJL4 =
  [i|
@export default eligible
GIVEN `is resident` IS A BOOLEAN TYPICALLY FALSE
      age IS A NUMBER
GIVETH A BOOLEAN
DECIDE eligible IF
  IF `is resident` THEN age >= 18
  ELSE REFUSE "cannot decide for a non-resident"
|]

-- | A decimal default that a Double cannot hold (review m1).
exactDecimalJL4 :: Text
exactDecimalJL4 =
  [i|
§ `R`
    GIVEN r IS A NUMBER TYPICALLY 0.10000000000000000001

@export default is exact
GIVEN u IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `is exact` IF r EQUALS 0.10000000000000000001
|]

-- | Defaults as the schema publishes them: an enum constructor named through
-- its section (review m2), NOTHING on a MAYBE, and a number on a rule GIVEN.
enumSchemaJL4 :: Text
enumSchemaJL4 =
  [i|
§ `Light`
DECLARE Signal IS ONE OF Red, Amber

§ `Main`
@export default which
GIVEN s IS A `Light`.Signal TYPICALLY `Light`.Red
      m IS A MAYBE NUMBER TYPICALLY NOTHING
      k IS A NUMBER TYPICALLY 5
GIVETH A NUMBER
DECIDE which s m k IS
  CONSIDER s
    WHEN `Light`.Red THEN k
    WHEN Amber THEN 2
|]

-- | Defaulted inputs of several kinds beside an unread MAYBE BOOLEAN that lets
-- a test reach the wrapper path (review m4, m8).
wrapperNullJL4 :: Text
wrapperNullJL4 =
  [i|
GIVEN m IS A MAYBE NUMBER
GIVETH A NUMBER
orZero m MEANS
  CONSIDER m
    WHEN JUST x THEN x
    WHEN NOTHING THEN 0

@export default wrapper probe
GIVEN
  m    IS A MAYBE NUMBER TYPICALLY NOTHING
  k    IS A NUMBER TYPICALLY 5
  flag IS A BOOLEAN TYPICALLY TRUE
  u    IS A MAYBE BOOLEAN
GIVETH A NUMBER
DECIDE wp m k flag u IS
  orZero m
  + k * 10
  + (IF flag THEN 1000 ELSE 0)
|]

-- | An enum input with no default (T3, report item 5), and one typed by a
-- synonym for MAYBE.
enumNullJL4 :: Text
enumNullJL4 =
  [i|
DECLARE Colour IS ONE OF Red, Green
DECLARE `optional colour` IS MAYBE Colour

@export default is red
GIVEN shade IS A Colour
      second IS AN `optional colour`
      `unused flag` IS A BOOLEAN
GIVETH A BOOLEAN
`is red` MEANS
      (shade EQUALS Red)
  AND (CONSIDER second
         WHEN JUST Green THEN FALSE
         OTHERWISE TRUE)
|]

-- | A record field default on the wrapper path, reached with a @{}@ on the
-- unread flag: the only place a nested path passes through the wrapper's own
-- field names.
recordWrapJL4 :: Text
recordWrapJL4 =
  [i|
DECLARE Config HAS
  timeout IS A NUMBER TYPICALLY 30
  retries IS A NUMBER

@export default budget
GIVEN cfg IS A Config
      `unused flag` IS A BOOLEAN
GIVETH A NUMBER
budget MEANS cfg's timeout PLUS cfg's retries
|]

-- | A rule that decodes JSON of its own (review M3): the switch must not
-- reach it, and under hard the answer says it rests on its default.
ownDecodeJL4 :: Text
ownDecodeJL4 =
  [i|
DECLARE Settings HAS
  limit IS A NUMBER TYPICALLY 10

GIVEN s IS A STRING
GIVETH AN EITHER STRING Settings
parseSettings s MEANS JSONDECODE s

@export default within limit
GIVEN amount IS A NUMBER
GIVETH A BOOLEAN
DECIDE `within limit` amount IF
  CONSIDER parseSettings "{}"
    WHEN RIGHT st THEN amount <= st's limit
    WHEN LEFT e THEN FALSE
|]

-- | A deontic rule with a defaulted BOOLEAN input, which takes the deontic
-- wrapper path.
deonticDefaultJL4 :: Text
deonticDefaultJL4 =
  [i|
DECLARE Driver HAS
    name IS A STRING

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

@export default seatbelt requirement
GIVEN driver        IS A Driver
      `is motorway` IS A BOOLEAN TYPICALLY FALSE
GIVETH A PROVISION OF Driver, `Driver Action`
`seatbelt requirement` MEANS
    IF      `is motorway`
    THEN    PARTY driver
            MUST `wear seatbelt`
            WITHIN 1
    ELSE    PARTY driver
            MAY `drive`
|]

-- | A rule whose cost is set by its input: it counts @n@ down to zero, so one
-- batch can hold fast cases and a slow one without a second deployment. Each
-- step allocates about 6.6 KB and the live heap stays constant (measured with
-- @l4 run +RTS -s@ on 2026-10-02: 1,000,000 steps allocate 6.6 GB in 1.2 s,
-- with 6 MiB in use).
spinJL4 :: Text
spinJL4 =
  [i|
GIVEN n IS A NUMBER
GIVETH A NUMBER
`count down` n MEANS
  IF n AT MOST 0 THEN 0 ELSE `count down` (n - 1)

@export default spins for n steps and then answers TRUE
GIVEN n IS A NUMBER
GIVETH A BOOLEAN
DECIDE spin IF `count down` n EQUALS 0
|]

-- | 'spinJL4', except that a negative @n@ is refused: one deployment whose
-- cases can be answered, refused, errored (no @n@) or stopped by a limit.
spinOrRefuseJL4 :: Text
spinOrRefuseJL4 =
  [i|
GIVEN n IS A NUMBER
GIVETH A NUMBER
`count down` n MEANS
  IF n AT MOST 0 THEN 0 ELSE `count down` (n - 1)

@export default spins for n steps and then answers TRUE, refusing a negative n
GIVEN n IS A NUMBER
GIVETH A BOOLEAN
DECIDE spin IF
  IF n < 0 THEN REFUSE "n is negative"
  ELSE `count down` n EQUALS 0
|]

-- | 'spinJL4' with an input that makes it take the generated-wrapper path: a
-- MAYBE input sent as @{}@ (uncertain) is one the direct path cannot take
-- (smucclaw/l4-ide#1018). The input is not read.
spinWrapperJL4 :: Text
spinWrapperJL4 =
  [i|
GIVEN n IS A NUMBER
GIVETH A NUMBER
`count down` n MEANS
  IF n AT MOST 0 THEN 0 ELSE `count down` (n - 1)

@export default spins for n steps and then answers TRUE
GIVEN
  n IS A NUMBER
  u IS A MAYBE BOOLEAN
GIVETH A BOOLEAN
DECIDE spin IF `count down` n EQUALS 0
|]

-- | A number the evaluator leaves unfinished: @(10 TO THE POWER 40) TO THE
-- POWER n@, built by repeated multiplication. The evaluation returns while
-- the multiplications are still thunks, and they are done when the answer is
-- forced (smucclaw/l4-ide#1019).
powerJL4 :: Text
powerJL4 =
  [i|
GIVEN n IS A NUMBER
GIVETH A NUMBER
`power of a big base` n MEANS
  IF n AT MOST 0 THEN 1 ELSE 10000000000000000000000000000000000000000 * `power of a big base` (n - 1)

@export default (10 to the power 40) to the power n
GIVEN n IS A NUMBER
GIVETH A NUMBER
DECIDE power IS `power of a big base` n
|]

-- | An imported value that costs about 33 MB to compute: more than a case has
-- left after 'heavyMainJL4' has spent 47 MB of a 64 MB limit on its own
-- steps, and less than the whole limit (smucclaw/l4-ide#1020).
heavyLibJL4 :: Text
heavyLibJL4 =
  [i|
GIVEN n IS A NUMBER
GIVETH A NUMBER
`count down` n MEANS
  IF n AT MOST 0 THEN 0 ELSE `count down` (n - 1)

heavy MEANS `count down` 5000
|]

heavyMainJL4 :: Text
heavyMainJL4 =
  [i|
IMPORT heavy_lib

@export default spends n steps of its own, then reads the imported value
GIVEN n IS A NUMBER
GIVETH A BOOLEAN
DECIDE `use heavy` IF `count down` n EQUALS 0 AND heavy EQUALS 0
|]

-- | A recursion that is not a tail call: each level waits for the next, so the
-- frame stack grows with n and a limit hit has frames to unwind. A tail
-- call such as 'spinJL4' has almost none, and hides what the unwinding does
-- after an allocation limit.
deepJL4 :: Text
deepJL4 =
  [i|
GIVEN n IS A NUMBER
GIVETH A NUMBER
`sum to` n MEANS
  IF n AT MOST 0 THEN 0 ELSE n + `sum to` (n - 1)

@export default sums 1 to n by non-tail recursion
GIVEN n IS A NUMBER
GIVETH A NUMBER
DECIDE deep IS `sum to` n
|]

-- | A rule written as clauses, with no clause for Blue. The error for Blue is
-- worded from the clauses ("No clause of `price` matches these inputs"), and
-- the evaluator reads that from a mark on the CONSIDERs the clauses compile
-- to, which the bundle has to keep (review of legalese/l4-ide#545).
partialClausesJL4 :: Text
partialClausesJL4 =
  [i|
DECLARE Colour IS ONE OF Red, Green, Blue

@export default The price of a colour
GIVEN c IS A Colour
GIVETH A NUMBER
DECIDE price Red   IS 1
DECIDE price Green IS 2
|]

-- | A rule whose answer, when its second input is TRUE, is its first input
-- itself: @p AND TRUE@ is @p@. On the wrapper path (a @{}@ in the request) that
-- answer sits inside the wrapper's JUST.
bareInputJL4 :: Text
bareInputJL4 =
  [i|
@export default gate
GIVEN p IS A BOOLEAN
      q IS A BOOLEAN
GIVETH A BOOLEAN
gate MEANS p AND q
|]

-- | BOOLEAN rules written as multi-clause DECIDE groups, each beside the
-- CONSIDER a drafter would write by hand for the same rule. All are called
-- @rule@, so that the two forms of a pair get the same atom ids and their
-- query plans can be compared whole.
--
-- The desugarer compiles clauses to a CONSIDER (and a LET for the clauses not
-- yet tried) that carry no source range. The checker used to record a result
-- type only on a node that has one, so the ladder refused the rule as "not a
-- boolean"; then the ladder drew the generated LET as one leaf, and the plan
-- asked nothing.
clauseGroupEnumJL4 :: Text
clauseGroupEnumJL4 =
  [i|
DECLARE Colour IS ONE OF Red, Green, Blue

@export Whether a colour is warm
GIVEN c IS A Colour
GIVETH A BOOLEAN
DECIDE rule Red IS TRUE
DECIDE rule Green IS FALSE
DECIDE rule Blue IS FALSE
|]

handEnumJL4 :: Text
handEnumJL4 =
  [i|
DECLARE Colour IS ONE OF Red, Green, Blue

@export Whether a colour is warm
GIVEN c IS A Colour
GIVETH A BOOLEAN
DECIDE rule c IS
  CONSIDER c
    WHEN Red THEN TRUE
    WHEN Green THEN FALSE
    WHEN Blue THEN FALSE
|]

-- | The same rule with the later clauses named in a LET the drafter wrote (not
-- clauses, so read as written).
letEnumJL4 :: Text
letEnumJL4 =
  [i|
DECLARE Colour IS ONE OF Red, Green, Blue

@export Whether a colour is warm
GIVEN c IS A Colour
GIVETH A BOOLEAN
DECIDE rule c IS
  LET rest BE CONSIDER c
                WHEN Green THEN FALSE
                WHEN Blue THEN TRUE
  IN CONSIDER c
       WHEN Red THEN TRUE
       OTHERWISE rest
|]

-- | Two inputs, a literal pattern in the first clause, a bare name in the second.
clauseGroupMixedJL4 :: Text
clauseGroupMixedJL4 =
  [i|
@export Whether the case is made out
GIVEN n IS A NUMBER
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE rule 0 b IS FALSE
DECIDE rule n b IS b AND n GREATER THAN 5
|]

handMixedJL4 :: Text
handMixedJL4 =
  [i|
@export Whether the case is made out
GIVEN n IS A NUMBER
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE rule n b IS
  CONSIDER n
    WHEN 0 THEN FALSE
    OTHERWISE b AND n GREATER THAN 5
|]

-- | A group of ONE clause: no LET, just the generated CONSIDER.
clauseGroupSingleJL4 :: Text
clauseGroupSingleJL4 =
  [i|
@export Whether the optional flag is set
GIVEN m IS A MAYBE BOOLEAN
GIVETH A BOOLEAN
DECIDE rule (JUST b) IS b
|]

handSingleJL4 :: Text
handSingleJL4 =
  [i|
@export Whether the optional flag is set
GIVEN m IS A MAYBE BOOLEAN
GIVETH A BOOLEAN
DECIDE rule m IS
  CONSIDER m
    WHEN JUST b THEN b
|]

-- | A clause that calls another rule. The call is a box over its two BOOLEAN
-- arguments, and its atomId is the hash of the call's term (R3), so the group
-- and its hand-written CONSIDER must name it alike.
clauseGroupCallJL4 :: Text
clauseGroupCallJL4 =
  [i|
DECLARE Colour IS ONE OF Red, Green, Blue

GIVEN x IS A BOOLEAN
      y IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `both hold` x y IS x AND y

@export Whether the case is made out
GIVEN c IS A Colour
      a IS A BOOLEAN
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE rule Red a b IS `both hold` a b
DECIDE rule c a b IS a OR b
|]

handCallJL4 :: Text
handCallJL4 =
  [i|
DECLARE Colour IS ONE OF Red, Green, Blue

GIVEN x IS A BOOLEAN
      y IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `both hold` x y IS x AND y

@export Whether the case is made out
GIVEN c IS A Colour
      a IS A BOOLEAN
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE rule c a b IS
  CONSIDER c
    WHEN Red THEN `both hold` a b
    OTHERWISE a OR b
|]

-- | A table of two columns whose rows share the first column and differ in the
-- second. The desugarer tests the colour again in every later clause; the
-- ladder reads each test with what the branches around it already decided.
clauseTableJL4 :: Text
clauseTableJL4 =
  [i|
DECLARE Colour IS ONE OF Red, Green, Blue

@export Whether the case is made out
GIVEN c IS A Colour
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE rule Red TRUE IS TRUE
DECIDE rule Red FALSE IS FALSE
DECIDE rule Green b IS b
DECIDE rule Blue b IS NOT b
|]

handTableJL4 :: Text
handTableJL4 =
  [i|
DECLARE Colour IS ONE OF Red, Green, Blue

@export Whether the case is made out
GIVEN c IS A Colour
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE rule c b IS
  CONSIDER c
    WHEN Red THEN
      CONSIDER b
        WHEN TRUE THEN TRUE
        WHEN FALSE THEN FALSE
    WHEN Green THEN b
    WHEN Blue THEN NOT b
|]

-- | Two BOOLEAN columns, the input's own name standing for "any value".
clauseTable2JL4 :: Text
clauseTable2JL4 =
  [i|
@export Whether the case is made out
GIVEN p IS A BOOLEAN
      q IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE rule TRUE TRUE IS TRUE
DECIDE rule TRUE q IS q
DECIDE rule p TRUE IS p
DECIDE rule p q IS FALSE
|]

handTable2JL4 :: Text
handTable2JL4 =
  [i|
@export Whether the case is made out
GIVEN p IS A BOOLEAN
      q IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE rule p q IS
  CONSIDER p
    WHEN TRUE THEN
      CONSIDER q
        WHEN TRUE THEN TRUE
        OTHERWISE q
    OTHERWISE
      CONSIDER q
        WHEN TRUE THEN p
        OTHERWISE FALSE
|]

-- | A last clause whose pattern is a new name, not the input's own: it always
-- matches, so it is the OTHERWISE.
clauseNewNameJL4 :: Text
clauseNewNameJL4 =
  [i|
DECLARE Colour IS ONE OF Red, Green, Blue

@export Whether the case is made out
GIVEN c IS A Colour
      a IS A BOOLEAN
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE rule Red a b IS a
DECIDE rule Green a b IS b
DECIDE rule other a b IS a AND b
|]

handNewNameJL4 :: Text
handNewNameJL4 =
  [i|
DECLARE Colour IS ONE OF Red, Green, Blue

@export Whether the case is made out
GIVEN c IS A Colour
      a IS A BOOLEAN
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE rule c a b IS
  CONSIDER c
    WHEN Red THEN a
    WHEN Green THEN b
    OTHERWISE a AND b
|]

-- | A BOOLEAN group with no GIVETH: the type is inferred, not declared.
clauseGroupNoGivethJL4 :: Text
clauseGroupNoGivethJL4 =
  [i|
DECLARE Colour IS ONE OF Red, Green, Blue

@export Whether a colour is warm
GIVEN c IS A Colour
DECIDE rule Red IS TRUE
DECIDE rule Green IS FALSE
DECIDE rule Blue IS FALSE
|]

-- | A BOOLEAN group whose first clause's result is a LET the drafter wrote.
clauseGroupLetResultJL4 :: Text
clauseGroupLetResultJL4 =
  [i|
DECLARE Colour IS ONE OF Red, Green, Blue

@export Whether a colour is warm and the flag is set
GIVEN c IS A Colour
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE rule Red b IS LET both BE b AND b IN both
DECIDE rule c b IS FALSE
|]

-- | A numeric rule of @k@ clauses, each TRUE or FALSE by turns, then a
-- fall-through. It draws one ladder node per TRUE row, plus one: 598 rows draw
-- 300 nodes, the most a rule written as clauses may draw, and 600 draw 301.
rowsClauseGroupJL4 :: Int -> Text
rowsClauseGroupJL4 k =
  "@export Rows\nGIVEN n IS A NUMBER\nGIVETH A BOOLEAN\n"
    <> Text.unlines [ "DECIDE rule " <> Text.pack (show row) <> " IS " <> (if even row then "TRUE" else "FALSE") | row <- [0 .. k - 1] ]
    <> "DECIDE rule n IS FALSE\n"

-- | A drafter's chain of @n@ LETs that each use the one before twice. Written
-- out it doubles for each LET, and its conjunctive normal form, which is what
-- the ladder draws, grows faster than that.
letChainJL4 :: Int -> Text
letChainJL4 n =
  "@export doubling let chain\nGIVEN x IS A BOOLEAN\n      y IS A BOOLEAN\nGIVETH A BOOLEAN\nDECIDE rule IS\n"
    <> "  LET a0 BE x\n  IN\n"
    <> Text.concat
         [ Text.replicate (3 + level) " " <> "LET a" <> Text.pack (show level) <> " BE a" <> Text.pack (show (level - 1)) <> " AND y OR a" <> Text.pack (show (level - 1)) <> "\n"
             <> Text.replicate (3 + level) " " <> "IN\n"
         | level <- [1 .. n - 1] ]
    <> Text.replicate (3 + n) " " <> "a" <> Text.pack (show (n - 1)) <> "\n"

-- | A record read from a JSON string by JSONDECODE, as written in
-- smucclaw/l4-ide#1040. What the decoder builds depends on the type the type
-- checker recorded on the call, so a service that serves a program without
-- that type answers differently: JSON that is not a Person is accepted as one,
-- and a Person comes back as NOTHING.
jsonDecodePersonJL4 :: Text
jsonDecodePersonJL4 =
  [i|
DECLARE Person HAS
    name IS A STRING
    age  IS A NUMBER

GIVEN json IS A STRING
GIVETH AN EITHER STRING Person
`decode person` json MEANS JSONDECODE json

@export default The age next year of the person in a JSON string, or -1 if it does not decode
GIVEN json IS A STRING
GIVETH A NUMBER
`age next year` json MEANS
  CONSIDER `decode person` json
    WHEN RIGHT p THEN p's age + 1
    WHEN LEFT msg THEN -1

@export default Whether a JSON string decodes as a person
GIVEN json IS A STRING
GIVETH A BOOLEAN
`is a person` json MEANS
  CONSIDER `decode person` json
    WHEN RIGHT p THEN TRUE
    WHEN LEFT msg THEN FALSE
|]

-- | A record input whose fields carry @desc text. The text is on the
-- annotations of the DECLARE, which a cache of the checked module did not
-- keep, so a schema built from the cached DECLAREs had no field descriptions;
-- and the record input has to be found by its type, whose numbering shifts
-- when a DECLARE is added above it.
taxpayerJL4 :: Text
taxpayerJL4 =
  [i|
DECLARE Taxpayer HAS
    name   IS A STRING @desc The taxpayer's full name
    income IS A MAYBE NUMBER @desc Income earned abroad, if any

@export Whether the taxpayer must file a foreign income disclosure
GIVEN tp IS A Taxpayer @desc The taxpayer's full profile
GIVETH A BOOLEAN
DECIDE disclosure IS
    CONSIDER tp's income
    WHEN NOTHING THEN FALSE
    WHEN JUST amt THEN amt > 10000
|]

-- | An @export that reads a name nothing declares. The type checker reports it
-- as out of scope, and the deploy turns it into an input, `flag`, of the type
-- the use implies. Only the listing is of interest: calling `above` answers
-- "flag is not in scope" on a fresh deploy too.
implicitFlagJL4 :: Text
implicitFlagJL4 =
  [i|
@export Whether a threshold is passed while a standing flag holds
GIVEN threshold IS A NUMBER
GIVETH A BOOLEAN
DECIDE above IF threshold > 1 AND flag
|]

-- | Two inputs whose names are different in L4 and the same once the service
-- turns spaces and hyphens into one character for its schemas (@a b@, @a-b@).
-- The compiler does not refuse this module, it raises an error.
nameClashJL4 :: Text
nameClashJL4 =
  [i|
@export Two inputs that sanitise to one name
GIVEN `a b` IS A NUMBER
      `a-b` IS A NUMBER
GIVETH A NUMBER
DECIDE clash IS `a b` PLUS `a-b`
|]

-- | REFUSE (R7) reached through a rule of no inputs: house style names each
-- refusal once, with its reason. The query plan once asked about
-- @`the other conditions are not modelled`@ as if it were a yes/no question,
-- and answered @eligible@ from that answer, where evaluation refuses.
refusingConditionJL4 :: Text
refusingConditionJL4 =
  [i|
GIVETH A BOOLEAN
`the other conditions are not modelled` MEANS
    REFUSE "the other conditions are not modelled"

@export Whether the person is eligible
GIVEN adult IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult MEANS adult AND `the other conditions are not modelled`
|]

-- | The refusal three definitions deep, through rules of no inputs only, one of
-- them under a WHERE. A call with arguments is not followed (a gap the
-- documentation names).
refusingDeepJL4 :: Text
refusingDeepJL4 =
  [i|
GIVETH A BOOLEAN
`the innermost condition` MEANS REFUSE "the deep condition is not modelled"

GIVETH A BOOLEAN
`the inner condition` MEANS `the innermost condition`
    WHERE `an unused aside` MEANS TRUE

GIVETH A BOOLEAN
`the outer condition` MEANS `the inner condition`

@export Whether the person is eligible
GIVEN adult IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult MEANS adult AND `the outer condition`
|]

-- | 'refusingConditionJL4' with OR: TRUE where @adult@ is, refused otherwise.
refusingOrJL4 :: Text
refusingOrJL4 =
  [i|
GIVETH A BOOLEAN
`the other conditions are not modelled` MEANS
    REFUSE "the other conditions are not modelled"

@export Whether the person is eligible
GIVEN adult IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult MEANS adult OR `the other conditions are not modelled`
|]

-- | 'refusingConditionJL4' the other way round. Evaluation reads the refusing
-- rule first, so it refuses whatever @adult@ is (R7 records this order
-- dependence; it does not remove it).
refusingFirstJL4 :: Text
refusingFirstJL4 =
  [i|
GIVETH A BOOLEAN
`the other conditions are not modelled` MEANS
    REFUSE "the other conditions are not modelled"

@export Whether the person is eligible
GIVEN adult IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult MEANS `the other conditions are not modelled` AND adult
|]

-- | A REFUSE written in the rule, on one arm of an IF.
refusingArmJL4 :: Text
refusingArmJL4 =
  [i|
@export Whether the person is eligible
GIVEN resident IS A BOOLEAN
      adult IS A BOOLEAN
GIVETH A BOOLEAN
eligible resident adult MEANS
    IF resident THEN adult
    ELSE REFUSE "the rules for non-residents are not modelled"
|]

-- | A rule of no inputs that cannot refuse: still a question, as before.
answeredConditionJL4 :: Text
answeredConditionJL4 =
  [i|
GIVETH A BOOLEAN
`the fee is paid` MEANS TRUE

@export Whether the person is eligible
GIVEN adult IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult MEANS adult AND `the fee is paid`
|]

-- | A refusal inside a disjunction of conjunctions. Evaluation of
-- @(adult AND r) OR resident@ with adult FALSE never reaches @r@; simplified,
-- as the service draws a ladder, it is @(adult OR resident) AND (r OR resident)@,
-- which does. So a ladder with a refusing leaf is drawn again unsimplified.
refusingDistributedJL4 :: Text
refusingDistributedJL4 =
  [i|
GIVETH A BOOLEAN
`the other conditions are not modelled` MEANS
    REFUSE "the other conditions are not modelled"

@export Whether the person is eligible
GIVEN adult IS A BOOLEAN
      resident IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult resident MEANS (adult AND `the other conditions are not modelled`) OR resident
|]

-- | NOT: TRUE where adult is FALSE, refused where adult is TRUE, both only once
-- resident is TRUE.
refusingNotJL4 :: Text
refusingNotJL4 =
  [i|
GIVETH A BOOLEAN
`the other conditions are not modelled` MEANS
    REFUSE "the other conditions are not modelled"

@export Whether the person is eligible
GIVEN adult IS A BOOLEAN
      resident IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult resident MEANS resident AND NOT (adult AND `the other conditions are not modelled`)
|]

-- | IMPLIES at the top, which the ladder draws as a seam: a scope that refuses
-- where adult is FALSE.
refusingImpliesJL4 :: Text
refusingImpliesJL4 =
  [i|
GIVETH A BOOLEAN
`the other conditions are not modelled` MEANS
    REFUSE "the other conditions are not modelled"

@export Whether the person is eligible
GIVEN adult IS A BOOLEAN
      resident IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult resident MEANS (adult OR `the other conditions are not modelled`) IMPLIES resident
|]

-- | IMPLIES inside an OR: refused only where resident is FALSE and adult TRUE.
refusingImpliesNestedJL4 :: Text
refusingImpliesNestedJL4 =
  [i|
GIVETH A BOOLEAN
`the other conditions are not modelled` MEANS
    REFUSE "the other conditions are not modelled"

@export Whether the person is eligible
GIVEN adult IS A BOOLEAN
      resident IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult resident MEANS resident OR (adult IMPLIES `the other conditions are not modelled`)
|]

-- | A seam sure to refuse while its scope is still open: the scope refuses where
-- adult is FALSE, and the requirement wherever the scope holds. Nothing is asked.
refusingSeamOpenJL4 :: Text
refusingSeamOpenJL4 =
  [i|
GIVETH A BOOLEAN
`the scope is not modelled` MEANS REFUSE "the scope is not modelled"

GIVETH A BOOLEAN
`the requirement is not modelled` MEANS REFUSE "the requirement is not modelled"

@export Whether the person is eligible
GIVEN adult IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult MEANS (adult OR `the scope is not modelled`) IMPLIES `the requirement is not modelled`
|]

-- | Both arms of an IF refuse, for different reasons: refused before resident is
-- answered, with both reasons until it is.
refusingBothArmsJL4 :: Text
refusingBothArmsJL4 =
  [i|
@export Whether the person is eligible
GIVEN resident IS A BOOLEAN
GIVETH A BOOLEAN
eligible resident MEANS
    IF resident THEN REFUSE "the rules for residents are not modelled"
    ELSE REFUSE "the rules for non-residents are not modelled"
|]

-- | A rule of no inputs that refuses on only one path. It is not marked, so it is
-- still a question, as before: whether it refuses can turn on what the plan does
-- not see.
conditionalRefuserJL4 :: Text
conditionalRefuserJL4 =
  [i|
GIVETH A BOOLEAN
`the fee is paid` MEANS TRUE

GIVETH A BOOLEAN
`the cap applies` MEANS
    IF `the fee is paid` THEN TRUE
    ELSE REFUSE "the cap is not modelled for unpaid fees"

@export Whether the person is eligible
GIVEN adult IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult MEANS adult AND `the cap applies`
|]

-- | A MAYBE input followed by another input, on the wrapper path: a synonym for a
-- MAYBE and a MAYBE NUMBER written out, each first, with a NUMBER after it, and
-- the synonym last as the control; and three DEONTIC functions of the same
-- shapes. The generated wrapper once wrote the input record with a leading comma
-- on every field after the first, which does not parse after a field whose type
-- is an application (@MAYBE OF NUMBER@), so each of these failed with a parser
-- error. Every function takes @y@ and @z@, so one request fits them all.
inputThenInputJL4 :: Text
inputThenInputJL4 =
  [i|
DECLARE MaybeYear IS A MAYBE NUMBER

DECLARE Party IS ONE OF `the seller`, `the buyer`

DECLARE `Contract Action` IS ONE OF `deliver the goods`, `pay the invoice`

@export a synonym for a MAYBE, then a NUMBER
GIVEN y IS A MaybeYear
      z IS A NUMBER
GIVETH A NUMBER
`syn then number` y z MEANS
  z PLUS (CONSIDER y
            WHEN JUST n THEN n
            WHEN NOTHING THEN 0)

@export a synonym for a MAYBE, then a MAYBE NUMBER
GIVEN y IS A MaybeYear
      z IS A MAYBE NUMBER
GIVETH A NUMBER
`syn then maybe` y z MEANS
  (CONSIDER y
     WHEN JUST n THEN n
     WHEN NOTHING THEN 0)
  PLUS (CONSIDER z
          WHEN JUST m THEN m
          WHEN NOTHING THEN 0)

@export a MAYBE NUMBER written out, then a NUMBER
GIVEN y IS A MAYBE NUMBER
      z IS A NUMBER
GIVETH A NUMBER
`plain maybe then number` y z MEANS
  z PLUS (CONSIDER y
            WHEN JUST n THEN n
            WHEN NOTHING THEN 0)

@export a NUMBER, then a synonym for a MAYBE: the control
GIVEN z IS A NUMBER
      y IS A MaybeYear
GIVETH A NUMBER
`number then syn` z y MEANS
  z PLUS (CONSIDER y
            WHEN JUST n THEN n
            WHEN NOTHING THEN 0)

@export a contract with a synonym for a MAYBE first
GIVEN y IS A MaybeYear
      z IS A NUMBER
GIVETH A DEONTIC Party `Contract Action`
`syn contract` MEANS
    PARTY `the seller`
    MUST `deliver the goods`
    WITHIN 14
    HENCE FULFILLED
    LEST BREACH

@export a contract with a MAYBE NUMBER written out first
GIVEN y IS A MAYBE NUMBER
      z IS A NUMBER
GIVETH A DEONTIC Party `Contract Action`
`plain contract` MEANS
    PARTY `the seller`
    MUST `deliver the goods`
    WITHIN 14
    HENCE FULFILLED
    LEST BREACH

@export a contract with the synonym last: the control
GIVEN z IS A NUMBER
      y IS A MaybeYear
GIVETH A DEONTIC Party `Contract Action`
`control contract` MEANS
    PARTY `the seller`
    MUST `deliver the goods`
    WITHIN 14
    HENCE FULFILLED
    LEST BREACH
|]

-- | A BOOLEAN group of @k@ rows on one NUMBER input, each row's result a sum of
-- @width@ ones compared with zero, then a fall-through. It is long, not
-- branching: 60 rows of width 200 come to 24,301 parts written out.
longClausesJL4 :: Int -> Int -> Text
longClausesJL4 k width =
  "@export Long rows\nGIVEN n IS A NUMBER\nGIVETH A BOOLEAN\n"
    <> Text.unlines [ "DECIDE rule " <> Text.pack (show row) <> " IS n" <> Text.concat (replicate width " + 1") <> " GREATER THAN 0" | row <- [0 .. k - 1] ]
    <> "DECIDE rule n IS FALSE\n"

-- | A group of @k@ rows on one NUMBER input, each row's result a sum of
-- @width@ ones, then a fall-through. It returns a NUMBER, so it is not a
-- ladder at all, which is what the answer must say, not that it is too long
-- (60 rows of width 200 come to more than 20,000 parts written out).
longNumberClausesJL4 :: Int -> Int -> Text
longNumberClausesJL4 k width =
  "@export Long numeric rows\nGIVEN n IS A NUMBER\nGIVETH A NUMBER\n"
    <> Text.unlines [ "DECIDE rule " <> Text.pack (show row) <> " IS n" <> Text.concat (replicate width " + 1") | row <- [0 .. k - 1] ]
    <> "DECIDE rule n IS 0\n"

-- | A group whose first clause names every input as the @GIVEN@ does, so it
-- matches every input and the group is that clause's body: a disjunction of @k@
-- conjunctions of two inputs. (The second clause is never used, and the
-- checker says so.) The service simplifies the ladder into conjunctive normal
-- form, which has @2^k@ disjunctions of @k@ inputs: 193 boxes for 5, and 449
-- for 6.
dnfClauseJL4 :: Int -> Text
dnfClauseJL4 k = dnfRule k True

-- | A first clause that names its input as the @GIVEN@ does and whose result is
-- 22,000 parts or so: more than the 20,000 that clauses are limited to when
-- they are read through. The clause after it is never reached.
catchAllHugeJL4 :: Text
catchAllHugeJL4 = hugeRule "n" "n" True

-- | 'catchAllHugeJL4' without the clause after the first: a rule written without
-- clauses, which is what the group is answered as.
handCatchAllHugeJL4 :: Text
handCatchAllHugeJL4 = hugeRule "n" "n" False

-- | 'catchAllHugeJL4' with the first clause's input given a new name, @m@. That
-- clause matches every input, but not as the @GIVEN@ names it, so it is a test
-- the desugarer generates, and the group is read through and limited.
newNameHugeJL4 :: Text
newNameHugeJL4 = hugeRule "m" "m" True

-- | 'catchAllHugeJL4' with the first clause's input written @(EXACTLY n)@.
exactlyHugeJL4 :: Text
exactlyHugeJL4 = hugeRule "(EXACTLY n)" "n" True

-- | The first clause's pattern for the @GIVEN@'s @n@, the name its result uses
-- for it, and whether the clause after it is written.
hugeRule :: Text -> Text -> Bool -> Text
hugeRule pat var clauses =
  "@export Huge\nGIVEN n IS A NUMBER\nGIVETH A BOOLEAN\n"
    <> "DECIDE rule " <> pat <> " IS " <> var <> Text.concat (replicate 11000 " + 1") <> " GREATER THAN 0\n"
    <> (if clauses then "DECIDE rule 0 IS FALSE\n" else "")

-- | 'dnfClauseJL4' with the first clause's @n@ given a new name, @m@: read
-- through and limited, where 'dnfClauseJL4' is not.
newNameDnfJL4 :: Int -> Text
newNameDnfJL4 k = Text.replace "DECIDE rule n " "DECIDE rule m " (dnfClauseJL4 k)

-- | A table of @k@ clauses over five @MAYBE BOOLEAN@ inputs, each clause taking
-- three of them apart with @(JUST x)@ (inputs @i@, @i+1@, @i+2@, going round) and
-- returning the @AND@ of what it took apart. The other two inputs are given new
-- names, or, when @own@, are written as the @GIVEN@ names them. The last clause
-- names every input and is @IS FALSE@.
maybeTableJL4 :: Bool -> Int -> Text
maybeTableJL4 own k =
  Text.unlines $
    ["@export Maybes"]
      <> [ (if c == 1 then "GIVEN " else "      ") <> "a" <> Text.pack (show c) <> " IS A MAYBE BOOLEAN" | c <- [1 .. inputsN] ]
      <> ["GIVETH A BOOLEAN"]
      <> [ "DECIDE rule " <> Text.unwords [ patOf row c | c <- [1 .. inputsN] ] <> " IS " <> Text.intercalate " AND " [ boundName row c | c <- takenApart row ] | row <- [1 .. k - 1] ]
      <> [ "DECIDE rule " <> Text.unwords [ otherOf k c | c <- [1 .. inputsN] ] <> " IS FALSE" ]
  where
    inputsN = 5 :: Int
    takenApart row = [ ((row + d - 1) `mod` inputsN) + 1 | d <- [0 .. 2] ]
    boundName row c = "p" <> Text.pack (show row) <> "c" <> Text.pack (show c)
    otherOf row c = if own then "a" <> Text.pack (show c) else boundName row c
    patOf row c = if c `elem` takenApart row then "(JUST " <> boundName row c <> ")" else otherOf row c

-- | 'dnfClauseJL4' with the first clause's @n@ written @(EXACTLY n)@. The
-- missing-case check counts that as the input's own name, but the desugarer
-- tests it (only the bare name and @_@ are exempt), so the group is read
-- through. Six pairs are planned (probably because it reads through to one
-- CONSIDER, which is one box; not drawn); 'exactlyHugeJL4' is refused as too
-- long.
exactlyNameDnfJL4 :: Int -> Text
exactlyNameDnfJL4 k = Text.replace "DECIDE rule n " "DECIDE rule (EXACTLY n) " (dnfClauseJL4 k)

-- | 'dnfClauseJL4' without clauses.
handDnfJL4 :: Int -> Text
handDnfJL4 k = dnfRule k False

dnfRule :: Int -> Bool -> Text
dnfRule k clauses =
  "@export Dnf\nGIVEN n IS A NUMBER\n"
    <> Text.concat [ "      a" <> Text.pack (show j) <> " IS A BOOLEAN\n      b" <> Text.pack (show j) <> " IS A BOOLEAN\n" | j <- [1 .. k] ]
    <> "GIVETH A BOOLEAN\n"
    <> "DECIDE rule n " <> inputs <> " IS " <> Text.intercalate " OR " [ "(a" <> Text.pack (show j) <> " AND b" <> Text.pack (show j) <> ")" | j <- [1 .. k] ] <> "\n"
    <> (if clauses then "DECIDE rule 0 " <> inputs <> " IS FALSE\n" else "")
  where
    inputs = Text.unwords (concat [ ["a" <> Text.pack (show j), "b" <> Text.pack (show j)] | j <- [1 .. k] ])
