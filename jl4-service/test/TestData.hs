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
  deonticDeadlineJL4,
  deonticShapesJL4,
  deonticValueActionJL4,
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
  letChainJL4,
  longNumberClausesJL4,
  longClausesJL4,
  catchAllHugeJL4,
  handCatchAllHugeJL4,
  newNameHugeJL4,
  newNameDnfJL4,
  maybeTableJL4,
  exactlyNameDnfJL4,
  exactlyHugeJL4,
  dnfClauseJL4,
  handDnfJL4,
  jsonDecodePersonJL4,
  taxpayerJL4,
  implicitFlagJL4,
  nameClashJL4,
  refusingConditionJL4,
  refusingDeepJL4,
  refusingOrJL4,
  refusingFirstJL4,
  refusingArmJL4,
  answeredConditionJL4,
  refusingDistributedJL4,
  refusingNotJL4,
  conditionalRefuserJL4,
  refusingWithInputsJL4,
  refusingDirectJL4,
  refusingImpliesJL4,
  refusingEitherJL4,
  leafCollisionJL4,
  impliesBesideRefusalJL4,
  ifBesideRefusalJL4,
  unreadableRefusalsJL4,
  coveredWithInputsJL4,
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

-- | As 'deonticExportJL4', but the seller's obligation has no @LEST@: missing
-- its deadline is a breach the evaluator reports as @deadline_missed@, naming
-- the event that revealed it and the obligation that was missed.
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

-- | Shapes of party and action, each with a space in a name: the operands of a
-- @ROR@ and of a @RAND@, an action the rule does not declare (a binder), and a
-- party that is a @GIVEN@ input.
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

-- | A contract whose one action carries a value: it is not a name, so the
-- answer prints it as the rule source it is.
deonticValueActionJL4 :: Text
deonticValueActionJL4 =
  [i|
DECLARE Party IS ONE OF Alice
DECLARE Act IS ONE OF
  say HAS text IS A STRING

@export default the contract
GIVETH A DEONTIC Party Act
`the contract` MEANS
  PARTY Alice
  MUST say "pay now"
  WITHIN 10
  HENCE FULFILLED
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

-- | BOOLEAN rules written as multi-clause DECIDE groups, each beside the
-- CONSIDER a drafter would write by hand for the same rule. All are called
-- @rule@, so that the two forms of a pair get the same atom ids and their
-- query plans can be compared whole.
--
-- The desugarer compiles clauses to a CONSIDER (and a LET for the clauses not
-- yet tried) that carry no source range. The checker recorded a result type
-- only on a node that has one, so the ladder refused the rule as "not a
-- boolean"; with the type recorded, the ladder drew the generated LET as one
-- leaf, and the plan asked nothing.
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

-- | A clause that calls another rule. The call is part of the CONSIDER's one
-- box, so the group and its hand-written CONSIDER must print it alike.
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
-- ladder reads each test with what the branches around it already decided, so
-- the table prints as the nested CONSIDER a drafter writes for it.
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

-- | A REFUSE written in the rule, on one arm of an IF. The plan reads the IF as
-- the choice it is: the condition first, then only the arm it picks.
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

-- | A rule WITH an input whose body is a refusal. A call to it refuses whatever
-- it is given, which the plan cannot read: it answers 400.
refusingWithInputsJL4 :: Text
refusingWithInputsJL4 =
  [i|
GIVEN person IS A BOOLEAN
GIVETH A BOOLEAN
`the person is covered` person MEANS
    REFUSE "coverage is not modelled"

@export Whether the person is eligible
GIVEN adult IS A BOOLEAN
      applicant IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult applicant MEANS adult AND `the person is covered` applicant
|]

-- | A REFUSE written as an operand of AND, with no definition around it.
refusingDirectJL4 :: Text
refusingDirectJL4 =
  [i|
@export Whether the person is eligible
GIVEN adult IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult MEANS adult AND REFUSE "the other conditions are not modelled"
|]

-- | A rule of no inputs that always refuses, on the right of an IMPLIES. It is
-- reached only where the left side is TRUE.
refusingImpliesJL4 :: Text
refusingImpliesJL4 =
  [i|
GIVETH A BOOLEAN
`the other conditions are not modelled` MEANS
    REFUSE "the other conditions are not modelled"

@export Whether the person is eligible
GIVEN adult IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult MEANS adult IMPLIES `the other conditions are not modelled`
|]

-- | Two refusals for different reasons, one on each side of the answer to
-- @adult@: refused before @adult@ is answered, with both reasons until it is.
-- (@NOT adult AND r@ reads as @NOT (adult AND r)@, so the second is bracketed.)
refusingEitherJL4 :: Text
refusingEitherJL4 =
  [i|
GIVETH A BOOLEAN
`the rules for adults are not modelled` MEANS
    REFUSE "the rules for adults are not modelled"

GIVETH A BOOLEAN
`the rules for minors are not modelled` MEANS
    REFUSE "the rules for minors are not modelled"

@export Whether the person is eligible
GIVEN adult IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult MEANS
    (adult AND `the rules for adults are not modelled`)
    OR ((NOT adult) AND `the rules for minors are not modelled`)
|]

-- | @n + 1@ rules of no inputs, @p0@ to @pn@, declared before four rules that
-- each read the last of them (or an input) beside another leaf. A bare name is
-- keyed by its own unique and any other leaf by a fresh counter, so how many
-- rules come first moves the name's unique against the counter's range. The
-- rules are checked at every @n@ in a span, so that no particular numbering is
-- relied on.
leafCollisionJL4 :: Int -> Text
leafCollisionJL4 n =
  Text.unlines
    ( concat [["GIVETH A BOOLEAN", "p" <> Text.pack (show k) <> " MEANS TRUE", ""] | k <- [0 .. n]]
        <> [ "@export"
           , "GIVEN a IS A BOOLEAN"
           , "      b IS A BOOLEAN"
           , "GIVETH A BOOLEAN"
           , "lastOrRefuse a b MEANS " <> lastRule <> " OR (REFUSE \"L1\")"
           , ""
           , "@export"
           , "GIVEN a IS A BOOLEAN"
           , "      b IS A BOOLEAN"
           , "GIVETH A BOOLEAN"
           , "lastAndRefuse a b MEANS " <> lastRule <> " AND (REFUSE \"L1\")"
           , ""
           , "@export"
           , "GIVEN a IS A BOOLEAN"
           , "      b IS A BOOLEAN"
           , "GIVETH A BOOLEAN"
           , "lastAndIf a b MEANS " <> lastRule <> " AND (IF b THEN b ELSE b)"
           , ""
           , "@export"
           , "GIVEN a IS A BOOLEAN"
           , "      b IS A BOOLEAN"
           , "GIVETH A BOOLEAN"
           , "inputOrRefuse a b MEANS a OR (REFUSE \"L1\")"
           ]
    )
 where
  lastRule = "p" <> Text.pack (show n)

-- | @n + 1@ rules of no inputs, @p0@ to @pn@, then @r1@, a rule that always
-- refuses, then rules that read an IMPLIES beside a refusal, in the places a
-- ladder draws as structure. A ladder with a refusing leaf is drawn as written,
-- where an IMPLIES must still be read as the OR it stands for: @a IMPLIES b@
-- reads @a@ first, and reads @b@ only where @a@ is TRUE. The last rule holds no
-- refusal, so it is drawn simplified: the control for the checks on the rest.
impliesBesideRefusalJL4 :: Int -> Text
impliesBesideRefusalJL4 n =
  Text.unlines
    ( concat [["GIVETH A BOOLEAN", "p" <> Text.pack (show k) <> " MEANS TRUE", ""] | k <- [0 .. n]]
        <> [ "GIVETH A BOOLEAN"
           , "r1 MEANS REFUSE \"R1\""
           , ""
           , "@export"
           , "GIVEN b IS A BOOLEAN"
           , "      c IS A BOOLEAN"
           , "GIVETH A BOOLEAN"
           , "orFalseAndR b c MEANS (b IMPLIES (NOT c)) OR (FALSE AND r1)"
           , ""
           , "@export"
           , "GIVEN b IS A BOOLEAN"
           , "      c IS A BOOLEAN"
           , "GIVETH A BOOLEAN"
           , "andTrueOrR b c MEANS ((NOT b) IMPLIES c) AND (TRUE OR r1)"
           , ""
           , "@export"
           , "GIVEN b IS A BOOLEAN"
           , "GIVETH A BOOLEAN"
           , "notImpliesRefuse b MEANS NOT (b IMPLIES (REFUSE \"L2\"))"
           , ""
           , "@export"
           , "GIVEN b IS A BOOLEAN"
           , "GIVETH A BOOLEAN"
           , "notRefuseImplies b MEANS NOT ((REFUSE \"L2\") IMPLIES b)"
           , ""
           , "@export"
           , "GIVEN c IS A BOOLEAN"
           , "GIVETH A BOOLEAN"
           , "viaImplies c MEANS (r1 IMPLIES c) OR r1"
           , ""
           , "@export"
           , "GIVEN b IS A BOOLEAN"
           , "      c IS A BOOLEAN"
           , "GIVETH A BOOLEAN"
           , "plainImplies b c MEANS b IMPLIES (NOT c)"
           ]
    )

-- | 'refusingWithInputsJL4' with the refusal removed: a call to a rule with an
-- input that answers, so the plan reads the call as a question.
coveredWithInputsJL4 :: Text
coveredWithInputsJL4 =
  [i|
GIVEN person IS A BOOLEAN
GIVETH A BOOLEAN
`the person is covered` person MEANS person

@export Whether the person is eligible
GIVEN adult IS A BOOLEAN
      applicant IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult applicant MEANS adult AND `the person is covered` applicant
|]

-- | Refusals in the places the plan cannot read: an arm of a CONSIDER, an
-- operand of a comparison, an operand of EQUALS. Each is exported on its own,
-- beside @clean@, which holds none and is planned as any rule is.
unreadableRefusalsJL4 :: Text
unreadableRefusalsJL4 =
  [i|
GIVETH A BOOLEAN
r1 MEANS REFUSE "R1"

GIVETH A NUMBER
`the fee` MEANS REFUSE "no fee is modelled"

@export
GIVEN adult IS A BOOLEAN
      variant IS A BOOLEAN
GIVETH A BOOLEAN
consideredArm adult variant MEANS
  adult AND
    CONSIDER variant
      WHEN TRUE THEN TRUE
      OTHERWISE REFUSE "the other variant is not modelled"

@export
GIVEN adult IS A BOOLEAN
GIVETH A BOOLEAN
comparison adult MEANS adult AND (`the fee` GREATER THAN 3)

@export
GIVEN adult IS A BOOLEAN
GIVETH A BOOLEAN
equalsRefuse adult MEANS adult AND (r1 EQUALS TRUE)

@export
GIVEN adult IS A BOOLEAN
      variant IS A BOOLEAN
GIVETH A BOOLEAN
clean adult variant MEANS adult AND variant
|]

-- | @n + 1@ rules of no inputs, then @r1@, a rule that always refuses, then
-- rules that hold a refusal on an arm or in the condition of an IF, in the
-- places a ladder draws as structure. The plan reads an IF as the choice it is:
-- the condition first, then only the arm it picks. The last rule holds no
-- refusal, so it is drawn simplified: the control for the checks on the rest.
ifBesideRefusalJL4 :: Int -> Text
ifBesideRefusalJL4 n =
  Text.unlines
    ( concat [["GIVETH A BOOLEAN", "p" <> Text.pack (show k) <> " MEANS TRUE", ""] | k <- [0 .. n]]
        <> [ "GIVETH A BOOLEAN"
           , "r1 MEANS REFUSE \"R1\""
           , ""
           , "@export"
           , "GIVEN a IS A BOOLEAN"
           , "      b IS A BOOLEAN"
           , "      c IS A BOOLEAN"
           , "GIVETH A BOOLEAN"
           , "ifElseRefuses a b c MEANS (IF b THEN c ELSE r1) AND a"
           , ""
           , "@export"
           , "GIVEN a IS A BOOLEAN"
           , "      b IS A BOOLEAN"
           , "      c IS A BOOLEAN"
           , "GIVETH A BOOLEAN"
           , "ifThenRefuses a b c MEANS (IF b THEN r1 ELSE c) OR a"
           , ""
           , "@export"
           , "GIVEN b IS A BOOLEAN"
           , "      c IS A BOOLEAN"
           , "GIVETH A BOOLEAN"
           , "ifConditionRefuses b c MEANS IF r1 THEN b ELSE c"
           , ""
           , "@export"
           , "GIVEN resident IS A BOOLEAN"
           , "GIVETH A BOOLEAN"
           , "houseStyle resident MEANS IF resident THEN TRUE ELSE r1"
           , ""
           , "@export"
           , "GIVEN a IS A BOOLEAN"
           , "      b IS A BOOLEAN"
           , "GIVETH A BOOLEAN"
           , "nestedIf a b MEANS IF a THEN (IF b THEN TRUE ELSE r1) ELSE FALSE"
           , ""
           , "@export"
           , "GIVEN a IS A BOOLEAN"
           , "      b IS A BOOLEAN"
           , "      c IS A BOOLEAN"
           , "GIVETH A BOOLEAN"
           , "plainOr a b c MEANS (b AND c) OR a"
           ]
    )
