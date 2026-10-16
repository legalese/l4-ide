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
  synonymParamJL4,
  synonymKindsJL4,
  synonymWrapperJL4,
  inputThenInputJL4,
  saleContractJL4,
  deonticExportJL4,
  deonticRecordPartyJL4,
  spacedFieldsJL4,
  assumeParamJL4,
  refuseJL4,
  importedRecordDeclJL4,
  importedRecordMainJL4,
  partialClausesJL4,
  wireProbeJL4,
  declineLabelsJL4,
  twoDatesJL4,
  lineBreakJL4,
  jsonDecodePersonJL4,
  taxpayerJL4,
  implicitFlagJL4,
  nameClashJL4,
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
                  [ ("Loss or Damage.caused by insects", Parameter "string" Nothing Nothing ["true", "false"] "Was the damage caused by insects?" Nothing Nothing Nothing Nothing Nothing)
                  , ("Loss or Damage.caused by birds", Parameter "string" Nothing Nothing ["true", "false"] "Was the damage caused by birds?" Nothing Nothing Nothing Nothing Nothing)
                  , ("Loss or Damage.caused by vermin", Parameter "string" Nothing Nothing ["true", "false"] "Was the damage caused by vermin?" Nothing Nothing Nothing Nothing Nothing)
                  , ("Loss or Damage.caused by rodents", Parameter "string" Nothing Nothing ["true", "false"] "Was the damage caused by rodents?" Nothing Nothing Nothing Nothing Nothing)
                  , ("Loss or Damage.to Contents", Parameter "string" Nothing Nothing ["true", "false"] "Is the damage to your contents?" Nothing Nothing Nothing Nothing Nothing)
                  , ("Loss or Damage.ensuing covered loss", Parameter "string" Nothing Nothing ["true", "false"] "Is the damage ensuing covered loss" Nothing Nothing Nothing Nothing Nothing)
                  , ("any other exclusion applies", Parameter "string" Nothing Nothing ["true", "false"] "Are any other exclusions besides mentioned ones?" Nothing Nothing Nothing Nothing Nothing)
                  , ("a household appliance", Parameter "string" Nothing Nothing ["true", "false"] "Did water escape from a household appliance due to an animal?" Nothing Nothing Nothing Nothing Nothing)
                  , ("a swimming pool", Parameter "string" Nothing Nothing ["true", "false"] "Did water escape from a swimming pool due to an animal?" Nothing Nothing Nothing Nothing Nothing)
                  , ("a plumbing, heating, or air conditioning system", Parameter "string" Nothing Nothing ["true", "false"] "Did water escape from a plumbing, heating or conditioning system due to an animal?" Nothing Nothing Nothing Nothing Nothing)
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

-- | Inputs declared through a type synonym for a MAYBE: one without a type
-- parameter, and one that takes a type (@Optional OF NUMBER@). Each must be a
-- MAYBE to the service, so a value is a JUST and a null or a missing one is a
-- NOTHING, as for @MAYBE NUMBER@ itself, which is the control.
synonymParamJL4 :: Text
synonymParamJL4 =
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

-- | Inputs declared through a synonym for a record, an enum and a list. The
-- service looked for a record, an enum or a LIST by the synonym's own name, so
-- each was refused, and each now reads as the type the synonym stands for.
synonymKindsJL4 :: Text
synonymKindsJL4 =
  [i|
DECLARE Year IS A NUMBER

DECLARE Pt HAS x IS A NUMBER

DECLARE Point IS A Pt

DECLARE Colour IS ONE OF Red, Green

DECLARE Hue IS A Colour

DECLARE Years IS A LIST OF Year

@export the x of a record, through a synonym
GIVEN p IS A Point
GIVETH A NUMBER
`point x` p MEANS p's x

@export a code for an enum, through a synonym
GIVEN h IS A Hue
GIVETH A NUMBER
`hue code` h MEANS IF h EQUALS Red THEN 1 ELSE 2

@export the first of a list, through a synonym
GIVEN ys IS A Years
GIVETH A NUMBER
`first year` ys MEANS
  CONSIDER ys
    WHEN EMPTY THEN 0
    WHEN y FOLLOWED BY rest THEN y
|]

-- | Inputs declared through a synonym for a record, an enum, a DATE, a LIST, a
-- BOOLEAN, a TIME and a DATETIME, each with a spare MAYBE input, pad, that the
-- rule never reads: sending pad as @null@ or @{}@ sends the request through the
-- generated wrapper. The JSON decoder expands a synonym for a record, an enum or
-- a DATE, which is why those are answered; a LIST, a TIME, a DATETIME or a
-- BOOLEAN synonym is answered because the wrapper leaves its name alone. A
-- synonym for a MAYBE is the one the wrapper expands itself
-- ('Backend.Jl4.maybeSynonymHeads'; 'synonymParamJL4' pins it). These pin the
-- rest, so that expanding every head, which breaks a LIST, a TIME and a DATETIME,
-- is caught. The two @plain@ functions take a record and a DATE written out, and
-- are the control for the first group.
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

-- | Inputs the wrapper must unwrap, so a missing one makes it answer NOTHING
-- and the service names the input: an ASSUME, and a DATE, which the wrapper
-- reads from a string. The optional input comes last, as it had to when the
-- wrapper's generated input record did not parse an optional input followed by
-- another; it parses now ('inputThenInputJL4').
declineLabelsJL4 :: Text
declineLabelsJL4 =
  [i|
ASSUME rate IS A NUMBER

@export a number plus an assumed rate
GIVEN n IS A NUMBER
GIVETH A NUMBER
`plus rate` MEANS n PLUS rate

@export a date read from a string
GIVEN `end date` IS A DATE
      pad        IS A MAYBE NUMBER
GIVETH A DATE
`date first` MEANS `end date`
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
