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
  saleContractJL4,
  deonticExportJL4,
  deonticRecordPartyJL4,
  spacedFieldsJL4,
  assumeParamJL4,
  assumeHelperJL4,
  refuseJL4,
  importedRecordDeclJL4,
  importedRecordMainJL4,
  dnfBlowupJL4,
  twinLeavesJL4,
  missingBooleanJL4,
  sectionBooleanJL4,
  deonticBooleanJL4,
  considerBooleanJL4,
  decidedAnywayJL4,
  bareInputJL4,
  deonticConsiderJL4,
  maybeInputsJL4,
  timeInputsJL4,
  wireProbeJL4,
  declineLabelsJL4,
  twoDatesJL4,
  ruleDefaultJL4,
  namedSiteDefaultJL4,
  expressionDefaultJL4,
  expressionAllDefaultJL4,
  expressionSiteDefaultJL4,
  constructorNamedDefaultJL4,
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
  deonticFieldDefaultJL4,
  deonticNestedFieldDefaultJL4,
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
-- occurrence. The two occurrences share a label and an input-ref closure, so
-- 'L4.Viz.Ladder.generateAtomId' gives them one atomId between them: one
-- question, two BDD variables.
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

-- | A rule that takes a @TYPICALLY@ default at a NAMED site of its own, for a
-- rule's input and for a record's field (W4, W5). The exported rule has an input
-- called @rate@, the spelling of the input @scaled@ leaves out: @presumed@ must
-- name the default @scaled@ took, under @scaled@, and not the request's @rate@.
namedSiteDefaultJL4 :: Text
namedSiteDefaultJL4 =
  [i|
DECLARE Config HAS
  timeout IS A NUMBER TYPICALLY 30
  retries IS A NUMBER

GIVEN rate IS A NUMBER TYPICALLY 3
      base IS A NUMBER
GIVETH A NUMBER
scaled MEANS rate TIMES base

@export default combine
GIVEN n IS A NUMBER
      rate IS A NUMBER
      use IS A BOOLEAN
      `unused flag` IS A BOOLEAN
GIVETH A NUMBER
combine MEANS
  IF use
  THEN (scaled WITH base IS n) PLUS (Config WITH retries IS rate)'s timeout
  ELSE 0
|]

-- | A section input whose @TYPICALLY@ is an expression that reads another section
-- input (R8 rule 3, W7). A request that leaves @discount@ out has it worked out
-- from the @list price@ the same request supplies, which the rule itself never
-- names: only the default reads it.
expressionDefaultJL4 :: Text
expressionDefaultJL4 =
  [i|
§ `Pricing`
    GIVEN `list price` IS A NUMBER
          discount IS A NUMBER TYPICALLY (`list price` DIVIDED BY 10)

@export default final price
GIVEN `unused flag` IS A BOOLEAN
GIVETH A NUMBER
`final price` MEANS discount TIMES 2
|]

-- | A @TYPICALLY@ that is an expression on a rule's input, on a section input
-- that reads another and on a record's field, together.
expressionAllDefaultJL4 :: Text
expressionAllDefaultJL4 =
  [i|
GIVETH A NUMBER
phi MEANS 8

§ `Pricing`
    GIVEN `list price` IS A NUMBER
          discount IS A NUMBER TYPICALLY (`list price` DIVIDED BY 10)

DECLARE Config HAS
  timeout IS A NUMBER TYPICALLY (phi TIMES 2)
  retries IS A NUMBER

@export default final price
GIVEN rate IS A NUMBER TYPICALLY (phi PLUS 1)
      cfg IS A Config
      `unused flag` IS A BOOLEAN
GIVETH A NUMBER
`final price` MEANS ((`list price` MINUS discount) TIMES rate) PLUS cfg's timeout
|]

-- | Expression defaults taken at a NAMED site inside the rules, each naming a
-- section input the request supplies.
expressionSiteDefaultJL4 :: Text
expressionSiteDefaultJL4 =
  [i|
GIVETH A NUMBER
phi MEANS 8

§ `Rates`
    GIVEN alpha IS A NUMBER

DECLARE Config HAS
  timeout IS A NUMBER TYPICALLY (phi TIMES alpha)
  retries IS A NUMBER

GIVEN rate IS A NUMBER TYPICALLY (phi PLUS alpha)
      base IS A NUMBER
GIVETH A NUMBER
scaled MEANS rate TIMES base

@export default combine
GIVEN n IS A NUMBER
      use IS A BOOLEAN
      `unused flag` IS A BOOLEAN
GIVETH A NUMBER
combine MEANS
  IF use
  THEN (scaled WITH base IS n) PLUS (Config WITH retries IS 1)'s timeout
  ELSE 0
|]

-- | Defaults whose value is a bare constructor (FALSE, an enum value), taken at
-- a NAMED site inside the rules (W4, W5). A constructor is a name, and every use
-- of it in a run used to share one cell, so a default that was never read was
-- listed in @presumed@ as soon as the same constructor was evaluated later
-- (review F1, 2026-10-03). With @x@ FALSE the AND stops at @a@, so @b@ is never
-- read, although the rule goes on to evaluate FALSE; the second rule's @d@ is
-- never read while the first's @b@ is, and they are the same constructor.
constructorNamedDefaultJL4 :: Text
constructorNamedDefaultJL4 =
  [i|
DECLARE Colour IS ONE OF Red, Green

GIVEN a IS A BOOLEAN
      b IS A BOOLEAN TYPICALLY FALSE
GIVETH A BOOLEAN
both MEANS a AND b

GIVEN a IS A BOOLEAN
      d IS A BOOLEAN TYPICALLY FALSE
GIVETH A NUMBER
ignoreD MEANS 0

GIVEN a IS A BOOLEAN
      c IS A Colour TYPICALLY Red
GIVETH A NUMBER
ignoreC MEANS 0

@export default short circuits
GIVEN x IS A BOOLEAN
      `unused flag` IS A BOOLEAN
GIVETH A NUMBER
`short circuits` MEANS IF (both WITH a IS x) THEN 1 ELSE 0

@export default two of one constructor
GIVEN x IS A BOOLEAN
      `unused flag` IS A BOOLEAN
GIVETH A BOOLEAN
`two of one constructor` MEANS
  IF (ignoreD WITH a IS x) EQUALS 0 THEN (both WITH a IS TRUE) ELSE TRUE

@export default enum never mentioned
GIVEN x IS A BOOLEAN
      `unused flag` IS A BOOLEAN
GIVETH A Colour
`enum never mentioned` MEANS IF (ignoreC WITH a IS x) EQUALS 0 THEN Red ELSE Green
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

-- | A deontic rule whose party record has a field with a @TYPICALLY@. The
-- generated wrapper builds each event's party as SOURCE, which since W5 would
-- fill an omitted field from its default (review silent F2, 2026-10-03).
deonticFieldDefaultJL4 :: Text
deonticFieldDefaultJL4 =
  [i|
DECLARE Driver HAS
    name IS A STRING
    licence IS A STRING TYPICALLY "full"

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

@export default seatbelt requirement
GIVEN driver IS A Driver
GIVETH A PROVISION OF Driver, `Driver Action`
`seatbelt requirement` MEANS
    PARTY driver
    MUST `wear seatbelt`
    WITHIN 1
    HENCE
        PARTY driver
        MAY `drive`
|]

-- | As 'deonticFieldDefaultJL4', with the defaulted field one level down: the
-- party's @zhome@ is an @Address@ whose @floor@ has a @TYPICALLY@ (review
-- rulings R2-2). The nested record is sent constructor-keyed, the shape the
-- service's own answers use, and it is generated as source like the party. It
-- is the party's alphabetically last field on purpose, because a field after
-- it would be attached to the nested record by the generated @WITH@ (an older
-- defect of the wrapper, not this fixture's business).
deonticNestedFieldDefaultJL4 :: Text
deonticNestedFieldDefaultJL4 =
  [i|
DECLARE Address HAS
    zip IS A NUMBER
    floor IS A NUMBER TYPICALLY 1

DECLARE Driver HAS
    name IS A STRING
    zhome IS AN Address

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

@export default seatbelt requirement
GIVEN driver IS A Driver
GIVETH A PROVISION OF Driver, `Driver Action`
`seatbelt requirement` MEANS
    PARTY driver
    MUST `wear seatbelt`
    WITHIN 1
    HENCE
        PARTY driver
        MAY `drive`
|]
