{-# LANGUAGE OverloadedStrings #-}
module Backend.CodeGen
  ( generateEvalWrapper
  , generateDeonticEvalWrapper
  , isDeonticType
  , GeneratedCode(..)
  , AnswerShape(..)
  , RequiredInput(..)
  -- Exported for testing
  , inputFieldName
  , transformJsonKeys
  , escapeAsL4String
  , clientName
  , fnLiteralToL4Expr
  , fnLiteralToL4ExprWithType
  -- An event's records, for the service's account of them (card O4)
  , isRecordLit
  , eventRecordsIn
  , eventRecordDefault
  ) where

import Base
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import Data.Char (isPrint)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TL
import L4.Lexer (showStringLit)
import L4.Presumption (requestRecordName)
import L4.Print (prettyLayout)
import L4.Syntax (Type'(..), Resolved, getUnique)
import L4.TypeCheck.Environment (booleanUnique, dateUnique, timeUnique, datetimeUnique, maybeUnique, isContractType)
import Backend.Api (TraceLevel(..), TraceEvent(..), FnLiteral(..))
import qualified Base.Text as BaseText
import Backend.MaybeLift (liftTypeToMaybe)
import qualified Data.Scientific as Scientific

-- | Determine if a type needs string→value conversion from JSON input.
-- Returns the conversion function name (e.g. "TODATE", "TOTIME", "TODATETIME")
-- or Nothing if no conversion is needed.
stringConversionFn :: Type' Resolved -> Maybe Text
stringConversionFn ty = coreConversion (unwrapMaybe ty)
  where
    coreConversion (TyApp _ name [])
      | getUnique name == dateUnique     = Just "TODATE"
      | getUnique name == timeUnique     = Just "TOTIME"
      | getUnique name == datetimeUnique = Just "TODATETIME"
    coreConversion _ = Nothing
    -- Unwrap MAYBE layers to get to the core type
    unwrapMaybe :: Type' Resolved -> Type' Resolved
    unwrapMaybe (TyApp _ _ [inner]) = unwrapMaybe inner
    unwrapMaybe t = t

-- | Check if a type is MAYBE X (one level)
isMaybeType :: Type' Resolved -> Bool
isMaybeType (TyApp _ name [_]) = getUnique name == maybeUnique
isMaybeType _ = False

-- | Quote an identifier with backticks if it contains spaces or special characters
-- L4 requires backticks for identifiers with spaces
--
-- For names that come from the deployed source only. Such a name was read by the
-- lexer, so it already fits inside quotes. A name that comes from a request goes
-- through 'clientName' instead.
quoteIdent :: Text -> Text
quoteIdent name
  | Text.any (== ' ') name = "`" <> name <> "`"
  | otherwise = name

-- | A name taken from a request, written as a quoted L4 name.
--
-- It is always quoted, and it is refused when L4 cannot quote it: the lexer
-- reads a quoted name as one or more printable characters up to the next
-- backtick, with no escape ('L4.Lexer.quoted'), so a name that is empty, holds a
-- backtick, or holds a character that is not printable has no spelling.
clientName :: Text -> Either Text Text
clientName name
  | Text.null name = Left "a name in the request is empty, and L4 cannot write an empty name"
  | Just c <- Text.find unquotable name =
      Left $ "the name " <> excerpt <> " in the request holds the character "
        <> BaseText.textShow c <> ", which L4 cannot write inside a quoted name"
  | otherwise = Right ("`" <> name <> "`")
  where
    unquotable c = c == '`' || not (isPrint c)
    -- The refusal quotes at most the first 40 characters of the name.
    excerpt = BaseText.textShow (Text.take 40 name) <> (if Text.length name > 40 then "..." else "")

-- | Prefix for InputArgs field names to avoid collision with source identifiers.
-- The generated InputArgs record creates accessor functions, which would otherwise
-- collide with GIVEN parameter names in the original source file.
-- We use a suffix approach: "name" -> "name (input)" to keep field names readable
-- while avoiding conflicts.
inputFieldName :: Text -> Text
inputFieldName name = name <> " (input)"

-- | Quote an InputArgs field name (which has been prefixed)
quoteInputField :: Text -> Text
quoteInputField = quoteIdent . inputFieldName

-- | Create a safe unwrapped variable name
-- For names with spaces, creates a backtick-quoted identifier like `unwrapped_tranche number`
unwrappedVar :: Text -> Text
unwrappedVar name
  | Text.any (== ' ') name = "`unwrapped_" <> name <> "`"
  | otherwise = "unwrapped_" <> name

-- | The placeholder for a BOOLEAN input the request did not supply.
-- It is an assumed term, so it costs nothing unless the rule reads it; if the
-- rule does read it, evaluation stops and names it. It used to be FALSE, which
-- answered the question for the caller (smucclaw/l4-ide#992;
-- specs/todo/TYPICALLY-ONE-BEHAVIOUR-SPEC.md §4 W1, §5 T3).
notSuppliedTerm :: Text -> Text
notSuppliedTerm name = quoteIdent (name <> " (not supplied)")

-- | The variable a BOOLEAN input is bound to: its value, or its placeholder.
suppliedVar :: Text -> Text
suppliedVar name
  | Text.any (== ' ') name = "`supplied_" <> name <> "`"
  | otherwise = "supplied_" <> name

-- | One ASSUME per BOOLEAN input, declaring its placeholder.
placeholderAssumes :: [((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool)] -> [Text]
placeholderAssumes paramInfo =
  [ "ASSUME " <> notSuppliedTerm name <> " IS A BOOLEAN"
  | ((name, _), True, _, _, _) <- paramInfo
  ]

-- | The expression passed for one input, once the LET bindings and the
-- nested CONSIDER are in scope.
paramValueExpr :: (Text, Bool, Maybe Text, Bool) -> Text
paramValueExpr (name, isBoolean, convFn, isM)
  | isBoolean = suppliedVar name
  -- Originally MAYBE: pass field value directly (it's already MAYBE X)
  | isM, Just _ <- convFn = maybeConvertedVar name
  | isM       = "(args's " <> quoteInputField name <> ")"
  | Just _ <- convFn = convertedVar name
  | otherwise = unwrappedVar name

-- | The LET bindings an input needs before the call: a BOOLEAN binds its value
-- or its placeholder, and a MAYBE DATE/TIME/DATETIME binds its converted value.
-- Each right-hand side is given relative to its LET.
inputLetBindings :: [((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool)] -> [(Text, [Text])]
inputLetBindings = mapMaybe binding
  where
    binding ((name, _), isB, _, convFn, isM)
      | isB =
          Just ( suppliedVar name
               , [ "CONSIDER args's " <> quoteInputField name
                 , "  WHEN JUST " <> unwrappedVar name <> " THEN " <> unwrappedVar name
                 , "  WHEN NOTHING THEN " <> notSuppliedTerm name
                 ] )
      | isM, Just fn <- convFn =
          Just ( maybeConvertedVar name
               , [ "CONSIDER args's " <> quoteInputField name
                 , "  WHEN JUST " <> unwrappedVar name <> " THEN " <> fn <> " " <> unwrappedVar name
                 , "  WHEN NOTHING THEN NOTHING"
                 ] )
      | otherwise = Nothing

-- | Nest LET bindings around a body, each body one level deeper than its LET.
-- L4's layout rule rejects a body at its LET's own column, so a flat chain does
-- not parse.
nestLets :: Int -> [(Text, [Text])] -> (Int -> [Text]) -> [Text]
nestLets level [] body = body level
nestLets level ((var, rhs) : rest) body =
  let indentStr = Text.replicate level "  "
  in [indentStr <> "LET " <> var <> " ="]
     ++ map ((indentStr <> "  ") <>) rhs
     ++ [indentStr <> "IN"]
     ++ nestLets (level + 1) rest body

-- | The call to the target function. A section GIVEN is supplied at a root
-- only by name, with WITH, and a WITH cannot follow positional arguments, so a
-- function that reads one gets every input by name. A LET of the section's
-- name around the call would never reach the rules that read it.
functionCallExpr
  :: Text
  -> [((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool)]  -- ^ GIVEN params
  -> [((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool)]  -- ^ section GIVEN params
  -> Text
functionCallExpr funName givenParamInfo binderParamInfo
  | null binderParamInfo =
      if null givenParamInfo
        then quotedFunName
        else quotedFunName <> " " <> Text.unwords (map valueOf givenParamInfo)
  | otherwise =
      quotedFunName <> " WITH " <> Text.intercalate ", "
        [ quoteIdent name <> " IS " <> valueOf p
        | p@((name, _), _, _, _, _) <- givenParamInfo <> binderParamInfo
        ]
  where
    quotedFunName = quoteIdent funName
    valueOf ((name, _), isB, _, convFn, isM) = paramValueExpr (name, isB, convFn, isM)

-- | Result of code generation
data GeneratedCode = GeneratedCode
  { generatedWrapper :: Text
    -- ^ The L4 code to append after the filtered source
  , answerShape :: AnswerShape
    -- ^ How the wrapper's #EVAL delivers the function's answer
  , requiredInputs :: [RequiredInput]
    -- ^ The inputs the wrapper cannot go on without, in the order it unwraps
    -- them: see 'isRequiredInput'. When one of them is absent, or is a DATE,
    -- TIME or DATETIME string that does not parse, the wrapper answers NOTHING
    -- without calling the function.
  }
  deriving (Show, Eq)

-- | How a generated wrapper's #EVAL delivers the function's answer.
data AnswerShape
  = WrappedInJust
    -- ^ @JUST answer@; or @NOTHING@, without calling the function, for the
    -- reasons given at 'requiredInputs'
  | Bare
    -- ^ the answer itself: a function with no inputs has nothing to decode
  deriving (Show, Eq)

-- | An input the wrapper cannot go on without.
data RequiredInput = RequiredInput
  { inputName :: Text
  , isWrittenAssume :: Bool
    -- ^ an ASSUME the author wrote; a rule GIVEN or a section GIVEN is a
    -- parameter of the function, as the schema publishes it
  , parsedAs :: Maybe Text
    -- ^ DATE, TIME or DATETIME, when the wrapper parses the input from a string
  }
  deriving (Show, Eq)

-- | Whether the wrapper unwraps an input with a nested CONSIDER, and so answers
-- NOTHING when it is absent: every input that is neither a BOOLEAN nor a MAYBE.
-- An input decoded as its own type ('inputParamInfo') counts as a MAYBE here:
-- it is passed straight through, and JSONDECODE refuses it by name instead.
isRequiredInput :: ((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool) -> Bool
isRequiredInput (_, isB, _, _, isM) = not isB && not isM

-- | The inputs for which 'isRequiredInput' holds.
requiredInputsOf
  :: Bool  -- ^ whether these are ASSUMEs the author wrote
  -> [((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool)]
  -> [RequiredInput]
requiredInputsOf written ps =
  [ RequiredInput name written (Text.drop 2 <$> convFn)  -- "TODATE" parses a DATE
  | p@((name, _), _, _, convFn, _) <- ps, isRequiredInput p ]

-- | Generate L4 wrapper code for JSONDECODE-based evaluation
--
-- Uses deep Maybe lifting: ALL parameters are wrapped in MAYBE types,
-- allowing JSON null/missing values to decode to NOTHING.
--
-- A BOOLEAN parameter that decodes to NOTHING is bound to its placeholder
-- assumed term ('notSuppliedTerm'): a rule that never reads it still
-- short-circuits to an answer, and a rule that does read it stops and names it.
--
-- For non-BOOLEAN parameters, NOTHING propagates as an omitted/unknown value.
--
-- Section GIVENs the function reads are supplied by name with WITH, which is
-- the one way to supply them at a root (see 'functionCallExpr').
--
-- ASSUME params are injected as LET bindings before the function call,
-- shadowing any global ASSUME declarations with the provided values.
--
-- An input in @fields@ is NOT lifted: its InputArgs field has the input's own
-- type, carrying its TYPICALLY (given as source text) if it has one, so the
-- JSON decoder fills it when the request leaves it out and reports it when it
-- is forced, and refuses it by name when it is missing or @null@ (W3, T3 of
-- specs/todo/TYPICALLY-ONE-BEHAVIOUR-SPEC.md). The caller decides which
-- inputs those are ('Backend.Jl4.wrapperPlan'); a section GIVEN that
-- discharge fills is simply not passed in.
generateEvalWrapper
  :: Text                         -- ^ Target function name
  -> [(Text, Type' Resolved)]     -- ^ GIVEN parameter names and types (passed as function args)
  -> [(Text, Type' Resolved)]     -- ^ section GIVEN names and types (supplied with WITH)
  -> [(Text, Type' Resolved)]     -- ^ ASSUME parameter names and types (injected as LET bindings)
  -> Map Text (Maybe Text)        -- ^ inputs decoded as their own type, with their TYPICALLY
  -> Aeson.Value                  -- ^ Input arguments as JSON object
  -> TraceLevel                   -- ^ Whether to generate EVAL or EVALTRACE
  -> Either Text GeneratedCode
generateEvalWrapper funName givenParams binderParams assumeParams fields inputJson traceLevel = do
  let allParams = givenParams <> binderParams <> assumeParams
  -- Handle zero-parameter functions: no wrapper needed, just eval directly
  if null allParams
    then Right GeneratedCode
      { generatedWrapper = Text.unlines
          [ ""
          , "-- ========== GENERATED WRAPPER =========="
          , ""
          , generateSimpleEval funName traceLevel
          ]
      , answerShape = Bare
      , requiredInputs = []
      }
    else
      -- Deep Maybe lifting: all parameters get MAYBE types
      let -- Check if a type is exactly BOOLEAN (not LIST OF BOOLEAN, etc.)
          -- Compare unique symbolically rather than via string comparison
          isBooleanType :: Type' Resolved -> Bool
          isBooleanType (TyApp _ name []) = getUnique name == booleanUnique
          isBooleanType _ = False
          -- Annotate GIVEN params with (type info, isBoolean, isGiven, convFn, isMaybe)
          givenParamInfo = map (inputParamInfo fields isBooleanType True) givenParams
          binderParamInfo = map (inputParamInfo fields isBooleanType False) binderParams
          -- Annotate ASSUME params with (type info, isBoolean, isGiven, convFn, isMaybe)
          assumeParamInfo = map (inputParamInfo fields isBooleanType False) assumeParams
          allParamInfo = givenParamInfo <> binderParamInfo <> assumeParamInfo
      in Right GeneratedCode
      { generatedWrapper = Text.unlines $
          [ ""
          , "-- ========== GENERATED WRAPPER (Deep Maybe Lifting) =========="
          ] ++
          placeholderAssumes allParamInfo ++
          [ ""
          , generateInputRecordLifted fields allParams
          , ""
          , generateDecoder
          , ""
          , generateJsonPayload inputJson
          , ""
          , generateEvalDirectiveLiftedWithAssumes funName givenParamInfo binderParamInfo assumeParamInfo traceLevel
          ]
      , answerShape = WrappedInJust
      , requiredInputs =
          requiredInputsOf False (givenParamInfo <> binderParamInfo)
            <> requiredInputsOf True assumeParamInfo
      }

-- | Generate simple EVAL/EVALTRACE for zero-parameter functions
generateSimpleEval :: Text -> TraceLevel -> Text
generateSimpleEval funName traceLevel =
  case traceLevel of
    TraceNone -> "#EVAL " <> funName
    TraceFull -> "#EVALTRACE " <> funName

-- | The parameter info of an input. One decoded as its own type ('fields')
-- is passed as its field's value directly: there is nothing to unwrap and no
-- placeholder to bind, which is the shape of an originally-MAYBE input.
inputParamInfo
  :: Map Text (Maybe Text)
  -> (Type' Resolved -> Bool)
  -> Bool
  -> (Text, Type' Resolved)
  -> ((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool)
inputParamInfo fields isBooleanType isGiven (name, ty)
  | Map.member name fields = ((name, ty), False, isGiven, Nothing, True)
  | otherwise = ((name, ty), isBooleanType ty, isGiven, stringConversionFn ty, isMaybeType ty)

-- | Generate DECLARE for input record with ALL parameters lifted to MAYBE
-- This enables uniform handling of null/missing JSON values
--
-- Except an input decoded as its own type ('fields'): its field keeps the
-- input's own type and carries its TYPICALLY, which is what the JSON decoder
-- fills an absent field from (T1b), and refuses a missing or @null@ one by
-- name (T3).
--
-- One field per line, each indented, with no separating commas: a leading
-- @, @ after a field whose type is an application (@MAYBE OF NUMBER@) does
-- not parse ("incorrect indentation"), which failed every request to a
-- function with a MAYBE input before another input. @l4 batch@'s record had
-- the same layout and the same failure.
generateInputRecordLifted :: Map Text (Maybe Text) -> [(Text, Type' Resolved)] -> Text
generateInputRecordLifted fields params = Text.unlines $
  ["DECLARE " <> requestRecordName <> " HAS"] ++
  map formatField params
  where
    formatField (name, ty) =
      let -- Lift ALL types to MAYBE, but for one decoded as itself
          tyText = case Map.lookup name fields of
            Just mDefault -> prettyLayout ty <> maybe "" (" TYPICALLY " <>) mDefault
            Nothing       -> liftTypeToMaybe ty
          -- Use prefixed field names to avoid collision with source identifiers
          quotedFieldName = quoteInputField name
      in "  " <> quotedFieldName <> " IS A " <> tyText

-- | Generate typed decoder function
generateDecoder :: Text
generateDecoder = Text.unlines
  [ "GIVEN jsn IS A STRING"
  , "GIVETH AN EITHER STRING " <> requestRecordName
  , "decodeArgs jsn MEANS JSONDECODE jsn"
  ]

-- | Generate JSON payload as L4 string literal
-- Transforms JSON keys to match the renamed InputArgs field names
generateJsonPayload :: Aeson.Value -> Text
generateJsonPayload json =
  "DECIDE inputJson IS " <> escapeAsL4String (transformJsonKeys json)

-- | Transform JSON object keys to match InputArgs field names
-- Adds " (input)" suffix to all top-level keys to match the collision-avoiding
-- field names in the generated InputArgs record.
transformJsonKeys :: Aeson.Value -> Aeson.Value
transformJsonKeys (Aeson.Object obj) =
  Aeson.Object $ AesonKeyMap.fromList $ map transformPair $ AesonKeyMap.toList obj
  where
    transformPair (key, val) =
      (AesonKey.fromText (inputFieldName (AesonKey.toText key)), val)
transformJsonKeys other = other

-- | Escape JSON value as an L4 string literal
-- Uses L4's own showStringLit which handles all escape sequences correctly
-- (backslashes, quotes, control characters, etc.)
escapeAsL4String :: Aeson.Value -> Text
escapeAsL4String val =
  let jsonText = TL.toStrict $ TL.decodeUtf8 $ Aeson.encode val
  in showStringLit jsonText

-- | Generate EVAL or EVALTRACE with deep Maybe lifting, handling both GIVEN and ASSUME params.
--
-- GIVEN params are passed as function arguments.
-- ASSUME params are injected as LET bindings before the function call.
--
-- Type signature: [((name, type), isBoolean, isGiven, convFn, isMaybe)]
-- convFn: Just "TODATE"/"TOTIME"/"TODATETIME" if type needs string->value conversion, Nothing otherwise
-- isMaybe=True means the parameter's original type is already MAYBE X, so we
-- should NOT unwrap the value (pass it directly as MAYBE X to the function).
generateEvalDirectiveLiftedWithAssumes
  :: Text
  -> [((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool)]  -- ^ GIVEN params: ((name, type), isBoolean, isGiven=True, convFn, isMaybe)
  -> [((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool)]  -- ^ section GIVEN params, supplied with WITH
  -> [((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool)]  -- ^ ASSUME params: ((name, type), isBoolean, isGiven=False, convFn, isMaybe)
  -> TraceLevel
  -> Text
generateEvalDirectiveLiftedWithAssumes funName givenParamInfo binderParamInfo assumeParamInfo traceLevel =
  let directive = case traceLevel of
        TraceNone -> "#EVAL"
        TraceFull -> "#EVALTRACE"

      -- All params for unwrapping
      allParams = givenParamInfo <> binderParamInfo <> assumeParamInfo

      -- Params that need CONSIDER unwrapping:
      -- non-boolean AND not originally-MAYBE (isMaybe=False)
      nonBoolNonMaybeParams = filter isRequiredInput allParams

      functionCall = functionCallExpr funName givenParamInfo binderParamInfo

      -- Wrap function call with LET bindings for ASSUME params
      wrapWithAssumes :: Text -> Text
      wrapWithAssumes innerExpr = foldr wrapOne innerExpr assumeParamInfo
        where
          wrapOne ((name, _), isB, _, convFn, isM) expr =
            let quotedName = quoteIdent name
                valueExpr = paramValueExpr (name, isB, convFn, isM)
            in "LET " <> quotedName <> " = " <> valueExpr <> " IN " <> expr

      -- The innermost expression (wrapped function call in JUST)
      innerCall = "JUST (" <> wrapWithAssumes functionCall <> ")"

      -- After the decode: LET bindings for BOOLEAN and MAYBE DATE/TIME/DATETIME
      -- params, then a nested CONSIDER for params that need unwrapping, then the call.
      body level
        | null nonBoolNonMaybeParams = [Text.replicate level "  " <> innerCall]
        | otherwise = generateNestedConsiderWithAssumes nonBoolNonMaybeParams functionCall assumeParamInfo level

  in Text.unlines $
       [ directive
       , "  CONSIDER decodeArgs inputJson"
       , "    WHEN RIGHT args THEN"
       ] ++
       nestLets 3 (inputLetBindings allParams) body ++
       [ "    WHEN LEFT error THEN NOTHING"
       ]

-- | Generate nested CONSIDER for unwrapping non-boolean, non-MAYBE values,
-- with LET bindings for ASSUME params at the innermost level.
-- For types needing conversion (DATE/TIME/DATETIME), adds an additional CONSIDER
-- to convert string -> typed value via TODATE/TOTIME/TODATETIME.
generateNestedConsiderWithAssumes
  :: [((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool)]  -- ^ Params to unwrap (non-boolean, non-MAYBE)
  -> Text                                                       -- ^ Function call (GIVEN args only)
  -> [((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool)]  -- ^ ASSUME params for LET bindings
  -> Int                                                        -- ^ Indentation level
  -> [Text]
generateNestedConsiderWithAssumes [] functionCall assumeParamInfo indent =
  let indentStr = Text.replicate indent "  "
      -- Wrap function call with LET bindings for ASSUME params
      wrapWithAssumes :: Text -> Text
      wrapWithAssumes innerExpr = foldr wrapOne innerExpr assumeParamInfo
        where
          wrapOne ((name, _), isB, _, convFn, isM) expr =
            let quotedName = quoteIdent name
                valueExpr = paramValueExpr (name, isB, convFn, isM)
            in "LET " <> quotedName <> " = " <> valueExpr <> " IN " <> expr
  in [indentStr <> "JUST (" <> wrapWithAssumes functionCall <> ")"]
generateNestedConsiderWithAssumes (((name, _), _, _, convFn, _):rest) functionCall assumeParamInfo indent =
  let indentStr = Text.replicate indent "  "
      quotedFieldName = quoteInputField name
  in case convFn of
     Just fn ->
       -- Type needs string->value conversion: unwrap MAYBE STRING, then convert
       [ indentStr <> "CONSIDER args's " <> quotedFieldName
       , indentStr <> "  WHEN JUST " <> unwrappedVar name <> " THEN"
       , indentStr <> "    CONSIDER " <> fn <> " " <> unwrappedVar name
       , indentStr <> "      WHEN JUST " <> convertedVar name <> " THEN"
       ] ++
       generateNestedConsiderWithAssumes rest functionCall assumeParamInfo (indent + 4) ++
       [ indentStr <> "      WHEN NOTHING THEN NOTHING  -- parse failed"
       , indentStr <> "  WHEN NOTHING THEN NOTHING"
       ]
     Nothing ->
       -- No conversion needed: just unwrap the MAYBE
       [ indentStr <> "CONSIDER args's " <> quotedFieldName
       , indentStr <> "  WHEN JUST " <> unwrappedVar name <> " THEN"
       ] ++
       generateNestedConsiderWithAssumes rest functionCall assumeParamInfo (indent + 2) ++
       [ indentStr <> "  WHEN NOTHING THEN NOTHING"
       ]

-- | Create a variable name for converted values (DATE/TIME/DATETIME from string)
convertedVar :: Text -> Text
convertedVar name
  | Text.any (== ' ') name = "`converted_" <> name <> "`"
  | otherwise = "converted_" <> name

-- | Create a variable name for MAYBE converted values
-- Used when the original type is MAYBE DATE/TIME/DATETIME (string->value conversion preserving MAYBE)
maybeConvertedVar :: Text -> Text
maybeConvertedVar name
  | Text.any (== ' ') name = "`maybeConverted_" <> name <> "`"
  | otherwise = "maybeConverted_" <> name

-- ----------------------------------------------------------------------------
-- Deontic evaluation support
-- ----------------------------------------------------------------------------

-- | Check if a type is DEONTIC a b (contract type with two type parameters).
-- 'isContractType', so that the service and the editor ask the same question.
isDeonticType :: Type' Resolved -> Bool
isDeonticType = isContractType

-- | Convert an FnLiteral to inline L4 source text.
-- Used for generating EVENT expressions in deontic wrappers.
--
-- Every name taken from the request, a string standing for a constructor, a
-- constructor name, a record key, goes through 'clientName': it is always
-- quoted, and a name L4 cannot quote is refused.
fnLiteralToL4Expr :: FnLiteral -> Either Text Text
fnLiteralToL4Expr = \case
  FnLitString s -> clientName s
  FnLitInt i -> Right (BaseText.textShow i)
  FnLitDouble d -> Right (BaseText.textShow d)
  FnLitBool True -> Right "TRUE"
  FnLitBool False -> Right "FALSE"
  FnArray xs -> do
    elems <- traverse fnLiteralToL4Expr xs
    Right ("(LIST " <> Text.intercalate ", " elems <> ")")
  FnObject [(conName, FnObject fields)] -> do
    -- Record constructor: `Constructor` WITH field1 IS val1, field2 IS val2
    con <- clientName conName
    assignments <- traverse (\(k, v) -> assignment k =<< fnLiteralToL4Expr v) fields
    Right (con <> " WITH " <> Text.intercalate ", " assignments)
  FnObject [(conName, FnArray [])] ->
    -- Nullary constructor
    clientName conName
  FnObject [(conName, FnArray [singleVal])] -> do
    -- Unary constructor with positional arg
    con <- clientName conName
    arg <- fnLiteralToL4Expr singleVal
    Right (con <> " " <> arg)
  FnObject [("tag", val)] ->
    -- Tagged union encoding: {"tag": "ConstructorName"} → just the value
    fnLiteralToL4Expr val
  FnObject [(conName, val)] -> do
    -- Single-key object: constructor applied to argument
    con <- clientName conName
    arg <- fnLiteralToL4Expr val
    Right (con <> " " <> arg)
  FnObject _ -> Right "NOTHING"  -- Fallback for unexpected shapes
  FnUncertain -> Right "NOTHING"
  FnUnknown -> Right "NOTHING"

-- | One @key IS value@ assignment of a record. The key is from the request;
-- the value is already rendered.
assignment :: Text -> Text -> Either Text Text
assignment key value = do
  k <- clientName key
  Right (k <> " IS " <> value)

-- | Convert FnLiteral to L4 source, using the type name to wrap record values.
-- The type name is only needed for record types (bare FnObject with multiple fields).
-- For enums (FnLitString) and tagged unions (FnObject with single key), the existing
-- fnLiteralToL4Expr already produces correct L4 because the constructor info is in the value.
fnLiteralToL4ExprWithType :: Maybe Text -> FnLiteral -> Either Text Text
fnLiteralToL4ExprWithType Nothing lit = fnLiteralToL4Expr lit
fnLiteralToL4ExprWithType (Just typeName) lit = case lit of
  -- FnObject with any fields → record type, needs constructor wrapper
  -- {"name": "Alice"} → Driver WITH name IS "Alice"
  -- {"name": "Alice", "age": 30} → Driver WITH name IS "Alice", age IS 30
  -- Note: field VALUES use fnLiteralToL4Value (strings as "quoted literals")
  -- rather than fnLiteralToL4Expr (strings as `backtick identifiers`).
  -- This is critical because record field values are data, not constructor references.
  FnObject fields@(_:_) -> do
    -- The type name comes from the deployed source, the keys from the request.
    assignments <- traverse (\(k, v) -> assignment k =<< fnLiteralToL4Value v) fields
    Right (quoteIdent typeName <> " WITH " <> Text.intercalate ", " assignments)
  -- FnLitString → enum constructor (existing logic handles this)
  -- Everything else → delegate to existing function
  other -> fnLiteralToL4Expr other

-- | Convert FnLiteral to L4 source text as a data value.
-- Unlike fnLiteralToL4Expr (which treats strings as constructor references
-- using backtick quoting), this formats strings as double-quoted string literals.
-- Used for record field values where strings represent data, not constructors.
--
-- A string is written by the lexer's own 'showStringLit', the function that
-- writes the request payload ('escapeAsL4String'), so both are read back by the
-- lexer as the text they were written from.
fnLiteralToL4Value :: FnLiteral -> Either Text Text
fnLiteralToL4Value = \case
  FnLitString s -> Right (showStringLit s)
  FnArray xs -> do
    elems <- traverse fnLiteralToL4Value xs
    Right ("(LIST " <> Text.intercalate ", " elems <> ")")
  other -> fnLiteralToL4Expr other

-- | Prepare events for EVALTRACE: the definitions the events' party and action
-- records are written as, and the event list expression.
--
-- A record can't be written inline in an EVENT expression, because L4's
-- parser doesn't read a WITH inside a parenthesized argument, so it is written
-- as a top-level MEANS definition and the EVENT refers to it by name
-- ('eventDefinitions').
--
-- Example: {"name": "Alice"} with party type "Driver" generates:
--   `event 0 party` MEANS Driver WITH `name` IS "Alice"
--   ... EVENT (`event 0 party`) (`wear seatbelt`) 1
prepareEvents
  :: Maybe Text -> Maybe Text -> [TraceEvent]
  -> Either Text ([Text], Text)  -- ^ (MEANS definitions, event list expression)
prepareEvents mPartyType mActionType events = do
  rendered <- traverse (renderEvent mPartyType mActionType) (zip [0 ..] events)
  Right
    ( [ definitionLine d | (_, ds) <- rendered, d <- ds ]
    , "(LIST " <> Text.intercalate ", " (map fst rendered) <> ")" )

-- | Whether an event's party or action value is an object, which the wrapper
-- writes as a definition of its own when it is a record ('eventDefinitions').
-- Any other value is written inline, inside the @EVENT@, with each record in it
-- a definition of its own.
isRecordLit :: FnLiteral -> Bool
isRecordLit (FnObject (_:_)) = True
isRecordLit _ = False

-- | A record that an event's party or action writes, as the wrapper defines it
-- (card O4, ruled 2026-10-11, option B; its review of 2026-11-18).
--
-- Every record construction in an event's value is a top-level definition of
-- its own, and a record nested in another is referred to by its name. Written
-- inline, as a field's value, it would take every field written after it:
-- @home IS Address WITH zip IS 5, note IS 3@ gives the Address a note of 3 and
-- leaves the outer record's note to its default (review F1).
--
-- And every event has its own definitions, numbered by the event's position,
-- so a default a construction leaves out is a cell of that event's alone, and
-- is named by that event's path (review F4). Two events that write the same
-- record no longer share one.
--
-- The name is ASCII, so the construction starts at the same column on its
-- line whatever unit a column is counted in ('eventRecordDefault').
data EventDefinition = EventDefinition
  { name         :: Text    -- ^ @event 0 party@ for the event's own record, @event 0 party 1@, ... for the records in it
  , construction :: Text    -- ^ @Con WITH field IS value, ...@
  , path         :: Text    -- ^ where the request wrote the record: @events[0].party@, @events[0].party.zhome.Address@
  , constructor  :: Text    -- ^ the constructor the request named, or the type of an event's own record
  , given        :: [Text]  -- ^ the fields the request wrote
  }

definitionLine :: EventDefinition -> Text
definitionLine d = definitionHead d <> d.construction

-- | What the line of a definition holds before its construction.
definitionHead :: EventDefinition -> Text
definitionHead d = "`" <> d.name <> "` MEANS "

-- | Every definition the wrapper writes for the events' records, in the order
-- of the events, the party before the action, and within one value a record
-- before the records inside it.
eventDefinitions :: Maybe Text -> Maybe Text -> [TraceEvent] -> Either Text [EventDefinition]
eventDefinitions mPartyType mActionType events =
  concatMap snd <$> traverse (renderEvent mPartyType mActionType) (zip [0 ..] events)

-- | One event as the @EVENT@ writes it, and the definitions it refers to.
renderEvent :: Maybe Text -> Maybe Text -> (Int, TraceEvent) -> Either Text (Text, [EventDefinition])
renderEvent mPartyType mActionType (n, ev) = do
  (partyExpr, partyDefs) <- eventValue ("event " <> k <> " party") ("events[" <> k <> "].party") mPartyType ev.party
  (actionExpr, actionDefs) <- eventValue ("event " <> k <> " action") ("events[" <> k <> "].action") mActionType ev.action
  Right ("EVENT (" <> partyExpr <> ") (" <> actionExpr <> ") " <> formatScientific ev.at, partyDefs <> actionDefs)
  where
    k = BaseText.textShow n

-- | The next number for a record inside a value, and the definitions so far,
-- each with its number (the value's own record 0, the others in the order
-- their constructions start).
type EventRender = StateT (Int, [(Int, EventDefinition)]) (Either Text)

-- | An event's party or action value: the expression the @EVENT@ writes, and a
-- definition for each record construction in it.
--
-- It writes what 'fnLiteralToL4ExprWithType' and 'fnLiteralToL4Expr' write,
-- case for case, except that each record is a name. With the type name known,
-- an object at the top is a record of that type, whose strings are data
-- ('fnLiteralToL4Value'); below the top, and at the top without the type name,
-- a record is keyed by its constructor (@{"Address": {"zip": 5}}@), and every
-- name taken from the request goes through 'clientName'.
--
-- The path of a record is where the request wrote it, the constructor key
-- included: @events[0].party.zhome.Address@.
eventValue :: Text -> Text -> Maybe Text -> FnLiteral -> Either Text (Text, [EventDefinition])
eventValue base valuePath mType lit = do
  (expr, (_, defs)) <- runStateT top (1, [])
  Right (expr, map snd (sortOn fst defs))
  where
    top :: EventRender Text
    top = case (mType, lit) of
      (Just t, FnObject fs@(_ : _)) -> record (Just 0) valuePath (quoteIdent t) t fs valueOf
      (Nothing, FnObject [(c, FnObject fs)]) -> do
        con <- liftEither (clientName c)
        record (Just 0) (valuePath <> "." <> c) con c fs exprOf
      _ -> exprOf valuePath lit

    record :: Maybe Int -> Text -> Text -> Text -> [(Text, FnLiteral)] -> (Text -> FnLiteral -> EventRender Text) -> EventRender Text
    record mNumber recordPath conText conName fields render = do
      number <- maybe reserve pure mNumber
      assignments <- for fields \(f, v) -> do
        value <- render (recordPath <> "." <> f) v
        liftEither (assignment f value)
      let defName = if number == 0 then base else base <> " " <> BaseText.textShow number
          def = EventDefinition
            { name = defName
            , construction = conText <> " WITH " <> Text.intercalate ", " assignments
            , path = recordPath
            , constructor = conName
            , given = map fst fields
            }
      modify' \(next, ds) -> (next, (number, def) : ds)
      pure ("`" <> defName <> "`")

    reserve :: EventRender Int
    reserve = do
      (next, ds) <- get
      put (next + 1, ds)
      pure next

    -- 'fnLiteralToL4Expr'
    exprOf :: Text -> FnLiteral -> EventRender Text
    exprOf here = \case
      FnLitString s -> liftEither (clientName s)
      FnLitInt x -> pure (BaseText.textShow x)
      FnLitDouble x -> pure (BaseText.textShow x)
      FnLitBool True -> pure "TRUE"
      FnLitBool False -> pure "FALSE"
      FnArray xs -> listOf exprOf here xs
      FnObject [(c, FnObject fields)] -> do
        con <- liftEither (clientName c)
        record Nothing (here <> "." <> c) con c fields exprOf
      FnObject [(c, FnArray [])] -> liftEither (clientName c)
      FnObject [(c, FnArray [single])] -> do
        con <- liftEither (clientName c)
        arg <- exprOf (here <> "." <> c <> "[0]") single
        pure (con <> " " <> arg)
      FnObject [("tag", val)] -> exprOf (here <> ".tag") val
      FnObject [(c, val)] -> do
        con <- liftEither (clientName c)
        arg <- exprOf (here <> "." <> c) val
        pure (con <> " " <> arg)
      FnObject _ -> pure "NOTHING"
      FnUncertain -> pure "NOTHING"
      FnUnknown -> pure "NOTHING"

    -- 'fnLiteralToL4Value'
    valueOf :: Text -> FnLiteral -> EventRender Text
    valueOf here = \case
      FnLitString s -> pure (showStringLit s)
      FnArray xs -> listOf valueOf here xs
      other -> exprOf here other

    listOf :: (Text -> FnLiteral -> EventRender Text) -> Text -> [FnLiteral] -> EventRender Text
    listOf render here xs = do
      elems <- for (zip [0 :: Int ..] xs) \(ix, x) -> render (here <> "[" <> BaseText.textShow ix <> "]") x
      pure ("(LIST " <> Text.intercalate ", " elems <> ")")

-- | Every record construction an event's party or action value writes
-- ('eventValue'), with the path the request wrote it at, its constructor, and
-- the fields it gives. Hard refuses a field one leaves out by this path, and
-- soft lists it by the same path ('eventRecordDefault'), since both come from
-- the one walk. A value with a name L4 cannot write has none: the wrapper
-- refuses it.
eventRecordsIn :: Text -> Maybe Text -> FnLiteral -> [(Text, Text, [Text])]
eventRecordsIn valuePath mType lit =
  [ (d.path, d.constructor, d.given) | Right (_, ds) <- [eventValue "event" valuePath mType lit], d <- ds ]

-- | The path the request wrote a field at, for a default the checker took in an
-- event's party or action record (card O4, ruled 2026-10-11, option B):
-- @events[0].party.licence@, @events[0].action.mode@,
-- @events[0].party.zhome.Address.floor@.
--
-- The evaluator reports such a default as the construction's own
-- ('L4.EvaluateLazy.Machine.FromNamedApp'), with the construction's site. The
-- wrapper is the end of the program the evaluator ran, so the site's line,
-- counted from the end, is a line of the wrapper; and a line of the wrapper
-- that is one of the definitions 'eventDefinitions' writes names exactly one
-- record, whose construction starts right after @`name` MEANS @.
--
-- 'Nothing' when the site is not on such a line: a construction of the rules,
-- or of the rest of the wrapper. @Just (Left ...)@ when it is on one but is not
-- that construction, or names a field the construction writes, or the program
-- does not end with the wrapper: a disagreement between this account and the
-- codegen, which the caller refuses loudly rather than list the default under
-- a wrong name. A line of the rules is never taken for a definition, even one
-- that reads the same, since only the wrapper's lines are looked at.
eventRecordDefault
  :: Maybe Text      -- ^ the party type name
  -> Maybe Text      -- ^ the action type name
  -> [TraceEvent]
  -> Text            -- ^ the program the evaluator ran
  -> Text            -- ^ the generated wrapper, which ends it
  -> Int             -- ^ the line the construction starts on (1-based)
  -> Int             -- ^ the column it starts at (1-based)
  -> Text            -- ^ the field that took its default
  -> Maybe (Either Text Text)
eventRecordDefault mPartyType mActionType events program wrapper siteLine siteColumn field = do
  -- the first line of the wrapper is empty, and may have joined the last line
  -- of the rules, so it is never one of the definitions
  guard (wrapperIndex >= 1 && wrapperIndex < length wrapperLines)
  defs <- either (const Nothing) Just (eventDefinitions mPartyType mActionType events)
  let lineText = wrapperLines !! wrapperIndex
  d <- find (\ def -> definitionLine def == lineText) defs
  pure $
    if not (wrapper `Text.isSuffixOf` program) then Left (defect d "the program does not end with the wrapper")
    else if siteColumn /= Text.length (definitionHead d) + 1 then Left (defect d "it is not the record's own construction")
    else if field `elem` d.given then Left (defect d "the record writes that field")
    else Right (d.path <> "." <> field)
  where
    programLines = Text.lines program
    wrapperLines = Text.lines wrapper
    wrapperIndex = siteLine - (length programLines - length wrapperLines) - 1
    defect d why =
      "the default of field '" <> field <> "' taken on the line of `" <> d.name
      <> "` (column " <> BaseText.textShow siteColumn <> ") could not be named by the path the request wrote it at: "
      <> why <> "; this is a defect in the service"

-- | Format a Scientific number as L4 source: in decimal notation and never with
-- an exponent, which L4's lexer does not read, and as the digits the client
-- sent, not as the Double nearest to them.
--
-- A number the client writes with trailing zeros (@0.0@, @1.0@, @2.00@) arrives
-- as a coefficient and a negative exponent that are not normalised. 'floor' of
-- an integral number is its value; multiplying the coefficient by @10 ^ exponent@
-- throws "Negative exponent" for it, and printing the Double of a fraction below
-- @0.1@ or of a number from @1e7@ up (@5.0e-2@, @1.23456785e7@) gives text the
-- lexer cannot read.
formatScientific :: Scientific.Scientific -> Text
formatScientific n
  | Scientific.isInteger n = BaseText.textShow (floor n :: Integer)
  | otherwise = Text.pack (Scientific.formatScientific Scientific.Fixed Nothing n)

-- | Generate L4 wrapper code for deontic evaluation with EVALTRACE.
-- Extends generateEvalWrapper by wrapping the function call in EVALTRACE.
generateDeonticEvalWrapper
  :: Text                         -- ^ Target function name
  -> [(Text, Type' Resolved)]     -- ^ GIVEN parameter names and types
  -> [(Text, Type' Resolved)]     -- ^ section GIVEN names and types (supplied with WITH)
  -> [(Text, Type' Resolved)]     -- ^ ASSUME parameter names and types
  -> Map Text (Maybe Text)        -- ^ inputs decoded as their own type, with their TYPICALLY
  -> Aeson.Value                  -- ^ Input arguments as JSON object
  -> Scientific.Scientific        -- ^ Start time
  -> [TraceEvent]                 -- ^ Events (may be empty for initial state)
  -> Maybe Text                   -- ^ Party type name (for formatting events)
  -> Maybe Text                   -- ^ Action type name (for formatting events)
  -> TraceLevel                   -- ^ Whether to generate EVAL or EVALTRACE
  -> Either Text GeneratedCode
generateDeonticEvalWrapper funName givenParams binderParams assumeParams fields inputJson startTime events mPartyType mActionType traceLevel = do
  let allParams = givenParams <> binderParams <> assumeParams

  -- Build event list expression with MEANS bindings for record-typed values.
  -- A name in the events that L4 cannot quote is refused here, before any
  -- source is written.
  (recordMeansDefns, eventListExpr) <- prepareEvents mPartyType mActionType events
  let startTimeExpr = formatScientific startTime

  -- Handle zero-parameter functions: wrap direct call in EVALTRACE
  if null allParams
    then Right GeneratedCode
      { generatedWrapper = Text.unlines $
          [ ""
          , "-- ========== GENERATED DEONTIC WRAPPER =========="
          ] ++
          recordMeansDefns ++
          [ ""
          , generateSimpleDeonticEval funName startTimeExpr eventListExpr traceLevel
          ]
      , answerShape = Bare
      , requiredInputs = []
      }
    else
      -- Deep Maybe lifting: all parameters get MAYBE types (same as generateEvalWrapper)
      let isBooleanType :: Type' Resolved -> Bool
          isBooleanType (TyApp _ name []) = getUnique name == booleanUnique
          isBooleanType _ = False
          givenParamInfo = map (inputParamInfo fields isBooleanType True) givenParams
          binderParamInfo = map (inputParamInfo fields isBooleanType False) binderParams
          assumeParamInfo = map (inputParamInfo fields isBooleanType False) assumeParams
          allParamInfo = givenParamInfo <> binderParamInfo <> assumeParamInfo
      in Right GeneratedCode
      { generatedWrapper = Text.unlines $
          [ ""
          , "-- ========== GENERATED DEONTIC WRAPPER (Deep Maybe Lifting) =========="
          ] ++
          placeholderAssumes allParamInfo ++
          [ ""
          , generateInputRecordLifted fields allParams
          , ""
          , generateDecoder
          , ""
          , generateJsonPayload inputJson
          ] ++
          (if null recordMeansDefns then [] else "" : recordMeansDefns) ++
          [ ""
          , generateDeonticEvalDirectiveLifted funName givenParamInfo binderParamInfo assumeParamInfo startTimeExpr eventListExpr traceLevel
          ]
      , answerShape = WrappedInJust
      , requiredInputs =
          requiredInputsOf False (givenParamInfo <> binderParamInfo)
            <> requiredInputsOf True assumeParamInfo
      }

-- | Generate simple EVALTRACE for zero-parameter deontic functions
generateSimpleDeonticEval :: Text -> Text -> Text -> TraceLevel -> Text
generateSimpleDeonticEval funName startTimeExpr eventListExpr traceLevel =
  let directive = case traceLevel of
        TraceNone -> "#EVAL"
        TraceFull -> "#EVALTRACE"
  in directive <> " EVALTRACE (" <> quoteIdent funName <> ") " <> startTimeExpr <> " " <> eventListExpr

-- | Generate EVAL/EVALTRACE with EVALTRACE call wrapping the function, with parameter handling
generateDeonticEvalDirectiveLifted
  :: Text
  -> [((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool)]  -- ^ GIVEN params
  -> [((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool)]  -- ^ section GIVEN params, supplied with WITH
  -> [((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool)]  -- ^ ASSUME params
  -> Text                                                       -- ^ Start time expression
  -> Text                                                       -- ^ Event list expression
  -> TraceLevel
  -> Text
generateDeonticEvalDirectiveLifted funName givenParamInfo binderParamInfo assumeParamInfo startTimeExpr eventListExpr traceLevel =
  let directive = case traceLevel of
        TraceNone -> "#EVAL"
        TraceFull -> "#EVALTRACE"

      allParams = givenParamInfo <> binderParamInfo <> assumeParamInfo

      nonBoolNonMaybeParams = filter isRequiredInput allParams

      functionCall = functionCallExpr funName givenParamInfo binderParamInfo

      -- Wrap function call with LET bindings for ASSUME params
      wrapWithAssumes :: Text -> Text
      wrapWithAssumes innerExpr = foldr wrapOne innerExpr assumeParamInfo
        where
          wrapOne ((name, _), isB, _, convFn, isM) expr =
            let quotedName = quoteIdent name
                valueExpr = paramValueExpr (name, isB, convFn, isM)
            in "LET " <> quotedName <> " = " <> valueExpr <> " IN " <> expr

      -- Wrap the function call in EVALTRACE
      evalTraceCall = "EVALTRACE (" <> wrapWithAssumes functionCall <> ") " <> startTimeExpr <> " " <> eventListExpr
      innerCall = "JUST (" <> evalTraceCall <> ")"

      body level
        | null nonBoolNonMaybeParams = [Text.replicate level "  " <> innerCall]
        | otherwise = generateNestedConsiderDeontic nonBoolNonMaybeParams evalTraceCall assumeParamInfo level

  in Text.unlines $
       [ directive
       , "  CONSIDER decodeArgs inputJson"
       , "    WHEN RIGHT args THEN"
       ] ++
       nestLets 3 (inputLetBindings allParams) body ++
       [ "    WHEN LEFT error THEN NOTHING"
       ]

-- | Generate nested CONSIDER for deontic evaluation (wraps result in EVALTRACE)
generateNestedConsiderDeontic
  :: [((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool)]  -- ^ Params to unwrap
  -> Text                                                       -- ^ EVALTRACE function call
  -> [((Text, Type' Resolved), Bool, Bool, Maybe Text, Bool)]  -- ^ ASSUME params for LET bindings
  -> Int                                                        -- ^ Indentation level
  -> [Text]
generateNestedConsiderDeontic [] evalTraceCall _assumeParamInfo indent =
  let indentStr = Text.replicate indent "  "
  in [indentStr <> "JUST (" <> evalTraceCall <> ")"]
generateNestedConsiderDeontic (((name, _), _, _, convFn, _):rest) evalTraceCall assumeParamInfo indent =
  let indentStr = Text.replicate indent "  "
      quotedFieldName = quoteInputField name
  in case convFn of
     Just fn ->
       [ indentStr <> "CONSIDER args's " <> quotedFieldName
       , indentStr <> "  WHEN JUST " <> unwrappedVar name <> " THEN"
       , indentStr <> "    CONSIDER " <> fn <> " " <> unwrappedVar name
       , indentStr <> "      WHEN JUST " <> convertedVar name <> " THEN"
       ] ++
       generateNestedConsiderDeontic rest evalTraceCall assumeParamInfo (indent + 4) ++
       [ indentStr <> "      WHEN NOTHING THEN NOTHING  -- parse failed"
       , indentStr <> "  WHEN NOTHING THEN NOTHING"
       ]
     Nothing ->
       [ indentStr <> "CONSIDER args's " <> quotedFieldName
       , indentStr <> "  WHEN JUST " <> unwrappedVar name <> " THEN"
       ] ++
       generateNestedConsiderDeontic rest evalTraceCall assumeParamInfo (indent + 2) ++
       [ indentStr <> "  WHEN NOTHING THEN NOTHING"
       ]
