{-# LANGUAGE BangPatterns #-}

-- | @l4 batch FILE --inputs data.{json,yaml,csv} [--entrypoint fn]@
--
-- Evaluates a single @\@export@ function against many input rows.
--
-- By default the results stream out one NDJSON object per line as each row
-- completes ('FmtNdjson'), so large CSV batches can be piped through @jq@
-- without running the evaluator dry on memory. @--format@ additionally
-- offers a single pretty JSON array ('FmtJson'), a flattened CSV table
-- ('FmtCsv'), or a YAML document ('FmtYaml'). @--output FILE@ redirects the
-- results to a file.
--
-- Each result row is an envelope
-- @{ input, output, status, diagnostics }@ (validate-only mode emits
-- @{ input, status, errors }@ instead).
--
-- Error handling follows the spec: batch processing stops at the first
-- failing row by default; pass @--continue-on-error@ to process every row
-- and aggregate failures. Either way the process exits non-zero if any row
-- failed.
module L4.Cli.Batch
  ( BatchOptions(..)
  , OutputFormat(..)
  , batchOptionsParser
  , batchCmd
  ) where

import Base.Text (Text)
import qualified Base.Text as Text
import qualified Data.Text.IO as TIO
import qualified Data.Text.Lazy as Text.Lazy
import qualified Data.Text.Lazy.Encoding as Text.Lazy.Encoding
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Lazy.Char8 as BSL8
import qualified Data.Attoparsec.ByteString as A
import qualified Data.Attoparsec.ByteString.Lazy as AL
import qualified Data.Csv as Csv
import qualified Data.Csv.Parser as CsvParser
import qualified Data.HashMap.Strict as HashMap
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Vector as Vector
import qualified Data.Yaml as Yaml
import Control.Monad (void)
import Data.Char (isAlpha, isAlphaNum)
import Data.Maybe (fromMaybe)
import Data.Text.Encoding (decodeUtf8, decodeUtf8With, encodeUtf8)
import Data.Text.Encoding.Error (lenientDecode)
import Data.Word (Word8)
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)
import System.IO
  ( Handle
  , IOMode(WriteMode)
  , hFlush
  , stdin
  , stdout
  , withFile
  )

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri, toNormalizedFilePath)

import L4.Export (ExportedFunction(..), ExportedParam(..), getDefaultFunction, getExportedFunctions)
import L4.DirectiveFilter (filterIdeDirectives)
import L4.EvaluateLazy
  ( EvalConfig
  , EvalDirectiveResult(..)
  , EvalDirectiveValue(..)
  , ReductionOutcome(..)
  , prettyEvalException
  )
import L4.Lexer (showStringLit)
import L4.Print (prettyLayout)
import L4.Syntax
  ( AppForm(..), Declare(..), Module(..), Resolved, Section(..), TopDecl(Declare, Section)
  , Type'(..), TypeDecl(..), Unique, getUnique
  )
import L4.TypeCheck.Environment (maybeUnique)

import L4.Cli.Common

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

-- | How to serialise the batch result rows.
data OutputFormat
  = FmtNdjson  -- ^ One JSON object per line (default; streams).
  | FmtJson    -- ^ A single JSON array of the row envelopes.
  | FmtCsv     -- ^ A flattened CSV table (input_* columns + output/status).
  | FmtYaml    -- ^ A YAML sequence of the row envelopes.
  deriving (Eq, Show)

data BatchOptions = BatchOptions
  { batchFile           :: FilePath
  , batchInputs         :: FilePath      -- path or "-" for stdin
  , batchInputFormat    :: Maybe Text    -- inferred from extension if omitted
  , batchEntrypoint     :: Maybe Text
  , batchOutputFormat   :: OutputFormat
  , batchOutput         :: Maybe FilePath -- Nothing = stdout
  , batchContinueOnErr  :: Bool
  , batchValidateOnly   :: Bool
  , batchFixedNow       :: FixedNowOpt
  }

outputFormatReader :: ReadM OutputFormat
outputFormatReader = eitherReader \input ->
  case Text.toLower (Text.pack input) of
    "ndjson"   -> Right FmtNdjson
    "jsonl"    -> Right FmtNdjson
    "json"     -> Right FmtJson
    "csv"      -> Right FmtCsv
    "yaml"     -> Right FmtYaml
    "yml"      -> Right FmtYaml
    other      -> Left $ "Invalid output format: " <> Text.unpack other
                       <> " (expected ndjson|json|csv|yaml)"

batchOptionsParser :: Parser BatchOptions
batchOptionsParser = BatchOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file containing the @export function")
  <*> strOption
        ( long "inputs"
        <> short 'i'
        <> metavar "PATH"
        <> help "Input rows file (.json/.yaml/.csv); '-' reads from stdin (requires --input-format)"
        )
  <*> optional (strOption
        ( long "input-format"
        <> metavar "FORMAT"
        <> help "Override input format (json|yaml|csv); inferred from extension by default"
        ))
  <*> optional (strOption
        ( long "entrypoint"
        <> short 'e'
        <> metavar "FUNCTION"
        <> help "Name of the @export function to call (defaults to @export default or the first one)"
        ))
  <*> option outputFormatReader
        ( long "format"
        <> long "output-format"
        <> short 'f'
        <> metavar "FORMAT"
        <> value FmtNdjson
        <> showDefaultWith (const "ndjson")
        <> help "Output format: ndjson (default, streams) | json | csv | yaml"
        )
  <*> optional (strOption
        ( long "output"
        <> short 'o'
        <> metavar "FILE"
        <> help "Write results to FILE instead of stdout"
        ))
  <*> switch
        ( long "continue-on-error"
        <> short 'c'
        <> help "Process every row and aggregate failures (default: stop at the first failing row)"
        )
  <*> switch
        ( long "validate-only"
        <> help "Validate each row against the @export parameter schema without evaluating"
        )
  <*> fixedNowParser

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

batchCmd :: BatchOptions -> IO ()
batchCmd opts = do
  evalConfig <- makeEvalConfig opts.batchFixedNow

  -- Step 1: read & parse the input rows.
  let inferredFormat = case opts.batchInputs of
        "-"  -> Nothing
        path | ".json" `List.isSuffixOf` path -> Just "json"
             | ".yaml" `List.isSuffixOf` path -> Just "yaml"
             | ".yml"  `List.isSuffixOf` path -> Just "yaml"
             | ".csv"  `List.isSuffixOf` path -> Just "csv"
             | otherwise -> Nothing
      format = opts.batchInputFormat <|> inferredFormat
  fmt <- case format of
    Just f  -> pure f
    Nothing -> do
      TIO.putStrLn "Error: --input-format is required when the extension can't be inferred (e.g. reading from stdin)"
      exitFailure
  rowsBytes <- if opts.batchInputs == "-"
    then BSL.hGetContents stdin
    else BSL.readFile opts.batchInputs
  inputs <- case parseBatchInput fmt rowsBytes of
    Right rs -> pure rs
    Left err -> do
      TIO.putStrLn $ "Error: failed to parse inputs: " <> Text.pack err
      exitFailure

  -- Step 2: typecheck the source file, find the target @export function.
  (initErrs, mTc) <- runOneshot evalConfig opts.batchFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri
  tcRes <- case mTc of
    Just tc | tc.success -> pure tc
    _ -> do
      putDiagnostics initErrs
      TIO.putStrLn "Error: type checking failed"
      exitFailure
  exportFn <- case findExportFunction opts.batchEntrypoint tcRes.module' of
    Right ef -> pure ef
    Left err -> do
      TIO.putStrLn $ "Error: " <> err
      exitFailure
  let filteredModule = filterIdeDirectives tcRes.module'
      filteredSource = prettyLayout filteredModule
      params         = extractParamsFromExport exportFn
      schema         = exportFn.exportParams
      -- what each input declares, for reading a case against it; a synonym
      -- (@DECLARE Year IS A NUMBER@) is this module's or an import's
      declares       = concatMap (moduleDeclares . (.module')) (tcRes : allDependencies tcRes)
      synonyms       = typeSynonyms declares
      declared       = declaredInputs synonyms schema

  -- Step 3: process each row into an envelope, honoring stop-on-error, and
  -- write the results in the requested format.
  let process = processRow opts evalConfig filteredSource exportFn params schema synonyms declared
  withOutputHandle opts.batchOutput \h ->
    case opts.batchOutputFormat of
      -- NDJSON streams line-by-line so huge batches stay memory-flat: we emit
      -- each envelope, let it become garbage, and never build the row list.
      FmtNdjson -> do
        anyFail <- streamRows opts.batchContinueOnErr inputs process
          (\env -> BSL8.hPutStrLn h (Aeson.encode env) >> hFlush h)
        finish anyFail
      -- The buffered formats must see every row before they can render, so
      -- here (and only here) we retain the whole list of envelopes.
      _ -> do
        (envs, anyFail) <- bufferRows opts.batchContinueOnErr inputs process
        writeBuffered h opts.batchOutputFormat envs
        finish anyFail
  where
    finish anyFail = if anyFail then exitFailure else exitSuccess

-- | Open the requested output sink (a file, or stdout) and run an action
-- against its handle.
withOutputHandle :: Maybe FilePath -> (Handle -> IO a) -> IO a
withOutputHandle Nothing     act = act stdout
withOutputHandle (Just path) act = withFile path WriteMode \h -> do
  r <- act h
  hFlush h
  pure r

----------------------------------------------------------------------------
-- Row processing
----------------------------------------------------------------------------

-- | Fold over the input rows for the streaming (NDJSON) path. Each envelope
-- is handed to @emit@ as soon as it is produced and then dropped, so the fold
-- carries only a strict 'Bool' (any-row-failed) accumulator — never the list
-- of envelopes. This is what keeps NDJSON output memory-flat for huge batches.
-- Stops at the first failing row unless @continueOnErr@ is set.
streamRows
  :: Bool
  -> [BatchRow]
  -> (Int -> BatchRow -> IO (Aeson.Value, Bool))
  -> (Aeson.Value -> IO ())
  -> IO Bool
streamRows continueOnErr inputs process emit = go (zip [1 :: Int ..] inputs) False
  where
    go [] !anyFail = pure anyFail
    go ((idx, input) : rest) !anyFail = do
      (env, isErr) <- process idx input
      emit env
      let !anyFail' = anyFail || isErr
      if isErr && not continueOnErr
        then pure True                   -- stop-on-error (the default)
        else go rest anyFail'

-- | Fold over the input rows for the buffered formats (json/yaml/csv), which
-- genuinely need every row in hand before they can render. Returns the
-- collected envelopes (in input order) and whether any row failed. Stops at
-- the first failing row unless @continueOnErr@ is set.
bufferRows
  :: Bool
  -> [BatchRow]
  -> (Int -> BatchRow -> IO (Aeson.Value, Bool))
  -> IO ([Aeson.Value], Bool)
bufferRows continueOnErr inputs process = go (zip [1 :: Int ..] inputs) [] False
  where
    go [] acc anyFail = pure (reverse acc, anyFail)
    go ((idx, input) : rest) acc anyFail = do
      (env, isErr) <- process idx input
      let acc'     = env : acc
          anyFail' = anyFail || isErr
      if isErr && not continueOnErr
        then pure (reverse acc', True)   -- stop-on-error (the default)
        else go rest acc' anyFail'

-- | Process a single input row into a result envelope, returning the
-- envelope and whether the row failed.
processRow
  :: BatchOptions
  -> EvalConfig
  -> Text                                    -- ^ filtered source
  -> ExportedFunction
  -> [(Text, Maybe (Type' Resolved))]        -- ^ params for wrapper gen
  -> [ExportedParam]                         -- ^ full schema for validation
  -> Map.Map Unique (Type' Resolved)         -- ^ the type synonyms, for validation
  -> DeclaredInputs                          -- ^ what each input declares, for reading a case
  -> Int
  -> BatchRow
  -> IO (Aeson.Value, Bool)
processRow opts _ _ _ _ _ _ _ _ (RefusedRow input reason)
  -- refused while reading the file: an error in either mode
  | opts.batchValidateOnly = pure
      ( Aeson.object
          [ Key.fromString "input"  Aeson..= input
          , Key.fromString "status" Aeson..= ("invalid" :: Text)
          , Key.fromString "errors" Aeson..= [reason]
          ]
      , True )
  | otherwise = pure
      ( Aeson.object
          [ Key.fromString "input"       Aeson..= input
          , Key.fromString "output"      Aeson..= Aeson.Null
          , Key.fromString "status"      Aeson..= ("error" :: Text)
          , Key.fromString "diagnostics" Aeson..= [reason]
          ]
      , True )
processRow opts evalConfig filteredSource exportFn params schema synonyms declared idx (BatchRow source cells)
  | opts.batchValidateOnly =
      let errs = validateRow synonyms schema input
          ok   = null errs
          env  = Aeson.object
            [ Key.fromString "input"  Aeson..= input
            , Key.fromString "status" Aeson..= (if ok then "valid" else "invalid" :: Text)
            , Key.fromString "errors" Aeson..= errs
            ]
      in pure (env, not ok)
  | otherwise = do
      let wrapperCode     = generateBatchWrapper exportFn.exportName params input
          combinedProgram = filteredSource <> wrapperCode
          virtualPath     = opts.batchFile ++ ".batch" ++ show idx ++ ".l4"
      (evalErrs, mEval) <- runOneshot evalConfig virtualPath \nfp -> do
        let uri = normalizedFilePathToUri nfp
        _ <- Shake.addVirtualFile (toNormalizedFilePath virtualPath) combinedProgram
        Shake.use Rules.EvaluateLazy uri
      let (status, outputJson, diags) = case mEval of
            Nothing ->
              -- The wrapper failed to typecheck/parse (e.g. a schema mismatch).
              ("error" :: Text, Aeson.Null, Aeson.toJSON evalErrs)
            Just evalResults ->
              -- The wrapper evaluated; a row still "fails" if evaluation raised
              -- an exception (e.g. JSONDECODE could not coerce a cell to the
              -- declared type). Those surface as `Reduction (ReducedErrored …)`.
              let excMsgs = concatMap resultExceptionMsgs evalResults
              in if null excMsgs
                   then ("success", Aeson.toJSON evalResults, Aeson.Array mempty)
                   else ("error",   Aeson.toJSON evalResults, Aeson.toJSON excMsgs)
          env = Aeson.object
            [ Key.fromString "input"       Aeson..= input
            , Key.fromString "output"      Aeson..= outputJson
            , Key.fromString "status"      Aeson..= status
            , Key.fromString "diagnostics" Aeson..= diags
            ]
      pure (env, status == "error")
  where
    -- the case as the export's inputs declare it: what validation, the
    -- wrapper and the echoed @input@ all see
    input = declareInputs declared source cells

-- | Pretty-printed exception messages for any @#EVAL@ result that reduced
-- to an evaluation exception. An empty list means the row evaluated cleanly.
resultExceptionMsgs :: EvalDirectiveResult -> [Text]
resultExceptionMsgs (MkEvalDirectiveResult _ res _) = case res of
  Reduction (ReducedErrored exc) -> prettyEvalException exc
  _                              -> []

----------------------------------------------------------------------------
-- Row validation (for --validate-only)
----------------------------------------------------------------------------

-- | Best-effort validation of one input row against the export schema.
-- Checks that required (non-@MAYBE@) params are present and non-null, and
-- that primitive-typed values have the right JSON kind. Lenient on
-- compound/unknown types (never rejects what it cannot judge).
validateRow :: Map.Map Unique (Type' Resolved) -> [ExportedParam] -> Aeson.Value -> [Text]
validateRow synonyms schema (Aeson.Object o) = concatMap checkParam schema
  where
    -- a synonym for @MAYBE@ is a @MAYBE@ (@DECLARE MaybeYear IS A MAYBE NUMBER@),
    -- as evaluation reads it, though the export's own flag does not see that
    isOptional p = maybe False (isMaybeType . expandSynonyms synonyms) p.paramType
    required p = p.paramRequired && not (isOptional p)
    checkParam p =
      case KeyMap.lookup (Key.fromText p.paramName) o of
        Nothing ->
          [ "Missing required field: '" <> p.paramName <> "'" <> descSuffix p
          | required p ]
        Just Aeson.Null ->
          [ "Field '" <> p.paramName <> "' is null but required" <> descSuffix p
          | required p ]
        Just v -> case primKind (throughMaybe synonyms <$> p.paramType) of
          Just k | not (jsonMatchesKind k v) ->
            [ "Type mismatch for field '" <> p.paramName <> "': expected "
              <> kindName k <> ", got " <> jsonKindName v <> descSuffix p ]
          _ -> []
    descSuffix p = case p.paramDescription of
      Just d | not (Text.null d) -> " (" <> d <> ")"
      _ -> ""
validateRow _ _ other =
  [ "Input record is not a JSON object: " <> jsonKindName other ]

data PrimKind = KNum | KBool | KStr

kindName :: PrimKind -> Text
kindName = \case KNum -> "NUMBER"; KBool -> "BOOLEAN"; KStr -> "STRING"

-- | Classify a param's declared type as a primitive kind we can check,
-- unwrapping @MAYBE@ wrappers on the AST (a @MAYBE NUMBER@ is checked as a
-- @NUMBER@; presence/nullability is handled separately by 'validateRow').
-- Returns Nothing for compound or unknown types (which we then treat
-- leniently). Unwrapping on the AST (rather than string-matching the
-- pretty-printed form, which renders as @MAYBE OF NUMBER@) is what makes
-- @--validate-only@ actually type-check optional primitives.
primKind :: Maybe (Type' Resolved) -> Maybe PrimKind
primKind mty = do
  ty <- mty
  case Text.toUpper (Text.strip (prettyLayout (unwrapMaybe ty))) of
    "NUMBER"  -> Just KNum
    "BOOLEAN" -> Just KBool
    "STRING"  -> Just KStr
    _         -> Nothing

-- | Strip any leading @MAYBE OF _@ wrappers, returning the inner type. Matches
-- the wrapper structurally by unique, mirroring @Export.hs@'s @isMaybeType@.
unwrapMaybe :: Type' Resolved -> Type' Resolved
unwrapMaybe (TyApp _ name [inner]) | getUnique name == maybeUnique = unwrapMaybe inner
unwrapMaybe ty = ty

jsonMatchesKind :: PrimKind -> Aeson.Value -> Bool
jsonMatchesKind KNum  (Aeson.Number _) = True
jsonMatchesKind KBool (Aeson.Bool _)   = True
jsonMatchesKind KStr  (Aeson.String _) = True
jsonMatchesKind _     _                = False

jsonKindName :: Aeson.Value -> Text
jsonKindName = \case
  Aeson.Number _ -> "NUMBER"
  Aeson.Bool _   -> "BOOLEAN"
  Aeson.String _ -> "STRING"
  Aeson.Null     -> "null"
  Aeson.Array _  -> "array"
  Aeson.Object _ -> "object"

----------------------------------------------------------------------------
-- Input parsing
----------------------------------------------------------------------------

-- | One case read from the input, or a CSV record refused while reading it,
-- with the cells it had (named against the header as far as they go) and why.
data BatchRow
  = BatchRow RowSource Aeson.Value
  | RefusedRow Aeson.Value Text

-- | Where a case came from, which decides how much its values already say.
data RowSource
  = FromStructured
    -- ^ JSON or YAML, which carry their own types: a number is a number and a
    -- string is a string
  | FromCsv
    -- ^ CSV, which has none: every value is the text of its cell, and it is
    -- the input's declared type that says what the text means ('declareInputs')

parseBatchInput :: Text -> BSL.ByteString -> Either String [BatchRow]
parseBatchInput fmt bytes = case Text.toLower fmt of
  "json" -> case Aeson.eitherDecode' bytes of
    Left err -> Left err
    Right (Aeson.Array arr) -> Right (map (BatchRow FromStructured) (Vector.toList arr))
    Right single            -> Right [BatchRow FromStructured single]
  "yaml" -> case Yaml.decodeEither' (BSL.toStrict bytes) of
    Left err -> Left (Yaml.prettyPrintParseException err)
    Right val -> case val of
      Aeson.Array arr -> Right (map (BatchRow FromStructured) (Vector.toList arr))
      single          -> Right [BatchRow FromStructured single]
  "csv" -> case csvRows bytes of
    Left err -> Left err
    Right rows -> Right
      [ case r of
          CsvRecord record         -> BatchRow FromCsv (rowToJson Aeson.String record)
          CsvRagged record reason  -> RefusedRow (rowToJson inferCsvCell record) reason
      | r <- rows ]
      where
        -- A BLANK cell (empty, spaces only, or a quoted @""@) is left out of
        -- the case, exactly as if its column were missing from the file. CSV has
        -- no spelling of null, and a blank cell is not text (T3c, ruled in
        -- @specs/todo/TYPICALLY-ONE-BEHAVIOUR-SPEC.md@ on unstable): an input
        -- that has to be given is then reported as missing, and a @MAYBE@ input
        -- is @NOTHING@, as a missing JSON key is.
        --
        -- A case that will be evaluated keeps each non-blank cell as the text
        -- written: only the export's declared input types can say whether
        -- @123456@ is a number or a code ('declareInputs'). A refused record
        -- is not evaluated, and is shown with the cells typed by what they
        -- look like.
        rowToJson :: (Text -> Aeson.Value) -> Csv.NamedRecord -> Aeson.Value
        rowToJson cell record = Aeson.Object $ KeyMap.fromList
          [ (Key.fromText (decodeUtf8 k), cell (decodeUtf8 v))
          | (k, v) <- HashMap.toList record
          , not (Text.null (Text.strip (decodeUtf8 v)))
          ]
  other -> Left ("Unsupported format: " ++ Text.unpack other)

-- | A case with each value typed by what the export declares for that input.
--
-- A NUMBER or BOOLEAN input (a @MAYBE@ one too, or one declared through a
-- synonym) given as text is read as the number or boolean the text spells,
-- from any format: a spreadsheet cell is text, and so is @"25"@ in a
-- hand-written JSON or YAML file. Text that does not read as one is left
-- alone, so that the decode error names the value it could not read.
--
-- Every other declared input keeps a CSV cell as the text written (a blank
-- cell is not text: 'parseBatchInput' leaves it out). A cell is never a number
-- or a boolean just because it looks like one: @123456@, @1.50@ and @018956@
-- are codes to a STRING input, @True@ is a choice of @Answer@ and @20261013@
-- is a DATE, and a decoder that wants a string or a name must be given one.
-- JSON and YAML already say what a string is, so a number sent for a STRING
-- input stays the error it was.
--
-- Only a column that no input declares, and an input whose type the export
-- does not give, is typed by what the cell looks like ('inferCsvCell').
declareInputs :: DeclaredInputs -> RowSource -> Aeson.Value -> Aeson.Value
declareInputs declared source (Aeson.Object o) = Aeson.Object (KeyMap.mapWithKey declare o)
  where
    declare key v = case (Map.lookup (Key.toText key) declared, v) of
      (Just DeclaredNumber,  Aeson.String s) -> fromMaybe v (jsonNumber s)
      (Just DeclaredBoolean, Aeson.String s) -> fromMaybe v (jsonBool s)
      (Just DeclaredText,    _)              -> v
      (_,                    Aeson.String s) | FromCsv <- source -> inferCsvCell s
      _                                      -> v
declareInputs _ _ v = v

-- | What the export declares an input to be, so far as reading a case goes:
-- the inputs by name.
type DeclaredInputs = Map.Map Text DeclaredInput

data DeclaredInput
  = DeclaredNumber   -- ^ a NUMBER
  | DeclaredBoolean  -- ^ a BOOLEAN
  | DeclaredText     -- ^ any other type, whose JSON is a string, a name or a structure
  | DeclaredUnknown  -- ^ the export gives no type for it

declaredInputs :: Map.Map Unique (Type' Resolved) -> [ExportedParam] -> DeclaredInputs
declaredInputs synonyms schema = Map.fromList
  [ (p.paramName, maybe DeclaredUnknown declared p.paramType) | p <- schema ]
  where
    declared ty = case primKind (Just (throughMaybe synonyms ty)) of
      Just KNum  -> DeclaredNumber
      Just KBool -> DeclaredBoolean
      _          -> DeclaredText

-- | A type with its synonyms expanded at the head (@DECLARE Year IS A NUMBER@
-- makes @Year@ a @NUMBER@). A synonym cannot name itself, but the walk does
-- not rely on that.
expandSynonyms :: Map.Map Unique (Type' Resolved) -> Type' Resolved -> Type' Resolved
expandSynonyms synonyms = go Set.empty
  where
    go seen ty = case ty of
      TyApp _ name []
        | Just expansion <- Map.lookup (getUnique name) synonyms
        , getUnique name `Set.notMember` seen -> go (Set.insert (getUnique name) seen) expansion
      _ -> ty

-- | A type as the primitive it comes to: through @MAYBE@, and through the
-- synonyms, at any depth (@MAYBE Year@, or a synonym for @MAYBE NUMBER@).
throughMaybe :: Map.Map Unique (Type' Resolved) -> Type' Resolved -> Type' Resolved
throughMaybe synonyms ty = case expandSynonyms synonyms ty of
  TyApp _ name [inner] | getUnique name == maybeUnique -> throughMaybe synonyms inner
  other -> other

-- | Whether a type is @MAYBE α@ itself.
isMaybeType :: Type' Resolved -> Bool
isMaybeType (TyApp _ name [_]) = getUnique name == maybeUnique
isMaybeType _ = False

-- | The type each synonym stands for (@DECLARE Year IS A NUMBER@), by the
-- synonym's 'Unique'.
typeSynonyms :: [Declare Resolved] -> Map.Map Unique (Type' Resolved)
typeSynonyms decls = Map.fromList
  [ (getUnique name, ty)
  | MkDeclare _ _ (MkAppForm _ name _ _) (SynonymDecl _ ty) <- decls ]

-- | Every @DECLARE@ in a module, in any section.
moduleDeclares :: Module Resolved -> [Declare Resolved]
moduleDeclares (MkModule _ _ sect) = goSection sect
 where
  goSection (MkSection _ _ _ decls) = decls >>= goDecl
  goDecl = \ case
    Declare _ d -> [d]
    Section _ s -> goSection s
    _ -> []

-- | A module's imports, transitively, each once.
allDependencies :: Rules.TypeCheckResult -> [Rules.TypeCheckResult]
allDependencies = go Set.empty . (.dependencies)
  where
    go _ [] = []
    go seen (d : ds)
      | key `Set.member` seen = go seen ds
      | otherwise = d : go (Set.insert key seen) (d.dependencies <> ds)
      where key = moduleKey d.module'
    moduleKey (MkModule _ uri _) = uri

-- | The number a text spells, in JSON's grammar (so @1.50@ and @1e3@ are
-- numbers, and @007@, @1,000@ and @+5@ are not).
jsonNumber :: Text -> Maybe Aeson.Value
jsonNumber s = case Aeson.decodeStrict (encodeUtf8 (Text.strip s)) of
  Just n@(Aeson.Number _) -> Just n
  _                       -> Nothing

jsonBool :: Text -> Maybe Aeson.Value
jsonBool s = case Text.toLower (Text.strip s) of
  "true"  -> Just (Aeson.Bool True)
  "false" -> Just (Aeson.Bool False)
  _       -> Nothing

-- | One record of a CSV file, named against the header the way cassava names
-- it, or refused because its cell count is not the header's.
data CsvRow
  = CsvRecord Csv.NamedRecord
  | CsvRagged Csv.NamedRecord Text

-- | The records of a CSV file with a header, in file order.
--
-- Not 'Csv.decodeByName': cassava drops every record that parses to a single
-- empty field (@removeBlankLines@), and a blank line and a line holding only
-- @""@ both parse to that. Under T3c the second is a row whose one cell is
-- empty, so absent, and it must be evaluated like any other row: dropping it
-- turned two rows in into one row out, with exit 0.
--
-- A blank line is not a row, and neither is an unquoted line holding only
-- spaces or tabs; a quoted @"   "@ is a row whose cell is absent. A record
-- with fewer or more cells than the header is refused, naming its line: a
-- short one used to be run with its missing inputs left out, and a long one
-- lost its extra cells and ran as a success. Both ruled by Meng on 2026-10-13
-- (legalese/l4-ide#653): the refusal stands, and in a one-column file a line
-- of only spaces or tabs is a blank line and not a case; to give an empty
-- value, write @""@, which is a row whose cell is absent.
csvRows :: BSL.ByteString -> Either String [CsvRow]
csvRows bytes
  | Just opened <- unclosedQuote (dropByteOrderMark bytes) =
      Left $ "line " <> show (1 + lineEnds (BSL.toStrict (BSL.take (fromIntegral opened) (dropByteOrderMark bytes))))
        <> " of the CSV file is not valid CSV: a quote that opens a cell there is never closed"
  | otherwise = case AL.parse file bytes of
  AL.Done _ parsed -> Right parsed
  -- Attoparsec's own message is the name of the parser that gave up
  -- (@endOfInput@, @13: not enough input@), which says neither where nor why.
  -- What it does know is the input left at the point it stopped, and with the
  -- input before that we can name the line.
  AL.Fail unconsumed _ _
    | BSL.null (dropByteOrderMark bytes) ->
        Left "the CSV file is empty: its first line has to name the inputs"
    | otherwise ->
        let consumed = BSL.take (BSL.length bytes - BSL.length unconsumed) bytes
            line     = 1 + lineEnds (BSL.toStrict consumed)
            near     = BSL.takeWhile (\w -> w /= 10 && w /= 13) (BSL.take 30 unconsumed)
            excerpt  = Text.unpack (decodeUtf8With lenientDecode (BSL.toStrict near))
        in Left $ "line " <> show line <> " of the CSV file is not valid CSV"
             <> (if null excerpt then ", where it ends" else ", near `" <> excerpt <> "`")
  where
    dropByteOrderMark b
      | BSL.take 3 b == BSL.pack [0xEF, 0xBB, 0xBF] = BSL.drop 3 b
      | otherwise = b
    comma = 44
    file = do
      -- A UTF-8 byte-order mark is not part of the first column's name. Excel's
      -- "CSV UTF-8" export writes one, and left in place it renamed the first
      -- input, so that input was missing from every row.
      _ <- optional (A.string "\xEF\xBB\xBF")
      (hdrRaw, hdr) <- A.match (CsvParser.header comma)
      rows hdr (1 + lineEnds hdrRaw)
    rows hdr line = do
      done <- A.atEnd
      if done
        then pure []
        else do
          blank <- (True <$ (A.skipWhile isBlankByte *> endOfLine)) <|> pure False
          trailing <- if blank then pure False
                      else (True <$ (A.takeWhile1 isBlankByte *> A.endOfInput)) <|> pure False
          if blank || trailing
            then rows hdr (line + 1)
            else do
              (raw, r) <- A.match (CsvParser.record comma <* (endOfLine <|> A.endOfInput))
              let named = HashMap.fromList (zip (Vector.toList hdr) (Vector.toList r))
                  width = Vector.length hdr
                  cells = Vector.length r
                  this
                    | cells == width = CsvRecord named
                    | otherwise = CsvRagged named $
                        "Line " <> Text.pack (show line) <> " has " <> Text.pack (show cells)
                        <> " cell" <> (if cells == 1 then "" else "s") <> ", but the header has "
                        <> Text.pack (show width) <> ", so the row is refused: a cell missing from a"
                        <> " short row would otherwise be read as left out (NOTHING for a MAYBE input,"
                        <> " a missing field for any other), and a long row's extra cells would be dropped"
              (this :) <$> rows hdr (line + max 1 (lineEnds raw))
    endOfLine = void (A.string "\r\n") <|> void (A.word8 10) <|> void (A.word8 13)
    isBlankByte w = w == 32 || w == 9
    -- the line ends in some consumed input, since a quoted cell may hold one:
    -- CRLF, LF and a lone CR count one each
    lineEnds :: BS.ByteString -> Int
    lineEnds = go 0 . BS.unpack
      where
        go :: Int -> [Word8] -> Int
        go n (13 : 10 : rest) = go (n + 1) rest
        go n (13 : rest)      = go (n + 1) rest
        go n (10 : rest)      = go (n + 1) rest
        go n (_ : rest)       = go n rest
        go n []               = n

-- | The offset of a quote that opens a cell and is never closed, in a CSV file.
--
-- cassava reads a quoted cell as everything to the end of the input when no
-- closing quote follows, and then drops its last byte, taking it for the
-- closing quote. So @"abc@ at the end of a file is the text @ab@, and a quote
-- in the middle of a file takes every row after it into one cell, both read
-- without complaint. This reads the file's quotes itself, ahead of the parser: a
-- quote opens a cell where a cell begins, @""@ inside one is a quote, and any
-- other quote closes it. A quote anywhere else is the parser's to refuse.
unclosedQuote :: BSL.ByteString -> Maybe Int
unclosedQuote = finish . BSL.foldl' step (0, Fresh)
  where
    finish (_, In opened) = Just opened
    finish _              = Nothing
    step :: (Int, QuoteState) -> Word8 -> (Int, QuoteState)
    step (!i, st) w = let !st' = next st in (i + 1, st')
      where
        isQuote = w == 34
        isBreak = w == 44 || w == 10 || w == 13
        -- outside a quoted cell, after a byte that did not open one
        outside | isBreak   = Fresh
                | otherwise = Plain
        next = \case
          Fresh | isQuote   -> In i
                | otherwise -> outside
          Plain             -> outside
          In opened | isQuote   -> Closing opened
                    | otherwise -> In opened
          -- a quote seen inside a cell: the second of @""@, or the closing one
          Closing opened | isQuote   -> In opened
                         | otherwise -> outside

-- | Where 'unclosedQuote' is in a file.
data QuoteState
  = Fresh            -- ^ where a cell begins
  | Plain            -- ^ inside a cell that is not quoted, or after a quoted one
  | In !Int          -- ^ inside the quoted cell that opened at this offset
  | Closing !Int     -- ^ just after a quote inside that cell

-- | Infer a JSON value for the text of a non-empty CSV cell, when no declared
-- input type says what it is ('declareInputs'):
--
--   * @true@/@false@ (ci)   -> boolean
--   * a plain integer or simple decimal literal -> number
--   * everything else       -> string  (dates included: JSON has no date
--                              type, and JSONDECODE parses date strings)
--
-- Numbers are recognised by aeson's own JSON grammar, which rejects
-- ambiguous forms (leading zeros, thousands separators, leading @+@), so
-- identifiers like @007@ that merely look numeric survive as strings.
--
-- We additionally refuse any cell containing @e@ or @E@: JSON's number
-- grammar accepts exponent notation, which would otherwise silently turn
-- product/lot codes like @1E5@ or @3e2@ into @100000@ / @300@. Exponent-form
-- identifiers therefore always stay STRING.
inferCsvCell :: Text -> Aeson.Value
inferCsvCell rawText =
  let s = Text.strip rawText
  in case Text.toLower s of
       "true"  -> Aeson.Bool True
       "false" -> Aeson.Bool False
       _ | Text.any (\c -> c == 'e' || c == 'E') s -> Aeson.String rawText
         | otherwise -> fromMaybe (Aeson.String rawText) (jsonNumber s)

----------------------------------------------------------------------------
-- Output writers (buffered formats)
----------------------------------------------------------------------------

writeBuffered :: Handle -> OutputFormat -> [Aeson.Value] -> IO ()
writeBuffered h fmt envs = case fmt of
  FmtNdjson -> mapM_ (BSL8.hPutStrLn h . Aeson.encode) envs
  FmtJson   -> BSL8.hPutStrLn h (encodeJsonArray envs)
  FmtYaml   -> BS.hPutStr h (Yaml.encode (Aeson.Array (Vector.fromList envs)))
  FmtCsv    -> BSL.hPutStr h (encodeCsv envs)

-- | A readable (one-envelope-per-line) JSON array. We avoid a dependency on
-- aeson-pretty by laying the array out ourselves; each element is compact.
encodeJsonArray :: [Aeson.Value] -> BSL.ByteString
encodeJsonArray [] = BSL8.pack "[]"
encodeJsonArray envs =
  BSL8.pack "[\n"
    <> BSL8.intercalate (BSL8.pack ",\n")
         (map (\e -> BSL8.pack "  " <> Aeson.encode e) envs)
    <> BSL8.pack "\n]"

----------------------------------------------------------------------------
-- CSV output
----------------------------------------------------------------------------

-- | Flatten the row envelopes to a CSV table. Input object fields become
-- @input_<field>@ columns (union across all rows, sorted for determinism);
-- the envelope's other scalar fields (@output@, @status@, @errors@, …)
-- follow. Compound cell values are rendered as compact JSON.
encodeCsv :: [Aeson.Value] -> BSL.ByteString
encodeCsv envs =
  let rows       = map flattenEnvelope envs
      inputCols  = List.sort (List.nub (concatMap (map fst . fst) rows))
      envCols    = orderedEnvCols (concatMap (map fst . snd) rows)
      colNames   = map ("input_" <>) inputCols ++ envCols
      headerBs   = Vector.fromList (map encodeUtf8 colNames)
      toRecord (inputFields, envFields) =
        let m = HashMap.fromList
                  (  [ (encodeUtf8 ("input_" <> k), encodeUtf8 v) | (k, v) <- inputFields ]
                  ++ [ (encodeUtf8 k, encodeUtf8 v)               | (k, v) <- envFields ] )
        in HashMap.union m (HashMap.fromList [ (encodeUtf8 c, BS.empty) | c <- colNames ])
  in Csv.encodeByName headerBs (map toRecord rows)

-- | Preserve the canonical envelope-column order (output/status/errors/…)
-- while only emitting columns that actually appear.
orderedEnvCols :: [Text] -> [Text]
orderedEnvCols present =
  let canonical = ["output", "status", "errors", "diagnostics"]
      seen c    = c `elem` present
  in filter seen canonical ++ List.sort (List.nub (filter (`notElem` canonical) present))

-- | Split an envelope into (input-object fields, other scalar fields), each
-- as an association list of Text cells.
flattenEnvelope :: Aeson.Value -> ([(Text, Text)], [(Text, Text)])
flattenEnvelope (Aeson.Object o) =
  let inputFields = case KeyMap.lookup (Key.fromText "input") o of
        Just (Aeson.Object inp) -> [ (Key.toText k, cellText v) | (k, v) <- KeyMap.toList inp ]
        Just other              -> [ ("value", cellText other) ]
        Nothing                 -> []
      envFields =
        [ (Key.toText k, cellText v)
        | (k, v) <- KeyMap.toList o
        , Key.toText k /= "input"
        ]
  in (inputFields, envFields)
flattenEnvelope other = ([], [("value", cellText other)])

-- | Render a JSON value as a single CSV cell. Scalars go in verbatim;
-- arrays/objects are re-encoded as compact JSON.
cellText :: Aeson.Value -> Text
cellText = \case
  Aeson.String s -> s
  Aeson.Bool b   -> if b then "true" else "false"
  Aeson.Null     -> ""
  Aeson.Number n -> Text.Lazy.toStrict (Text.Lazy.Encoding.decodeUtf8 (Aeson.encode (Aeson.Number n)))
  other          -> Text.Lazy.toStrict (Text.Lazy.Encoding.decodeUtf8 (Aeson.encode other))

----------------------------------------------------------------------------
-- Wrapper code generation
----------------------------------------------------------------------------

generateBatchWrapper
  :: Text
  -> [(Text, Maybe (Type' Resolved))]
  -> Aeson.Value
  -> Text
generateBatchWrapper funName params inputJson
  | null params =
      Text.unlines
        [ ""
        , "-- ========== GENERATED WRAPPER =========="
        , ""
        , "#EVAL " <> quoteIdent funName
        ]
  | otherwise =
      Text.unlines
        [ ""
        , "-- ========== GENERATED WRAPPER =========="
        , ""
        , generateInputRecord params
        , ""
        , generateDecoder
        , ""
        , generateJsonPayload inputJson
        , ""
        , generateEvalDirective funName params
        ]

generateInputRecord :: [(Text, Maybe (Type' Resolved))] -> Text
generateInputRecord params = Text.unlines $
  ["DECLARE InputArgs HAS"] ++
  map formatField (zip [0 :: Int ..] params)
  where
    formatField (idx, (name, mty)) =
      let fieldIndent = if idx == 0 then "  " else ", "
          tyText      = maybe "A NUMBER" prettyLayout mty
      in fieldIndent <> quoteIdent name <> " IS " <> tyText

generateDecoder :: Text
generateDecoder = Text.unlines
  [ "GIVEN jsn IS A STRING"
  , "GIVETH AN EITHER STRING InputArgs"
  , "decodeArgs jsn MEANS JSONDECODE jsn"
  ]

generateJsonPayload :: Aeson.Value -> Text
generateJsonPayload json =
  "DECIDE inputJson IS " <> escapeAsL4String json

-- | Render a JSON value as an L4 string literal.
--
-- Delegates to the lexer's own 'showStringLit', which emits the Haskell
-- escapes that @Lexer.charLiteral@ reads back when the parser reads a string
-- literal. 'showStringLit' says of itself that it "isn't truly precise", so
-- the round trip is pinned by a test and not assumed: see "hands every payload
-- to the rule and back unchanged" in @jl4/tests-cli/Main.hs@.
--
-- A hand-rolled @"@-only replacement does not survive a payload that holds a
-- backslash, a tab or a line break. The lexer reads the backslash of each JSON
-- escape as the start of an escape of its own, so the rule decodes JSON that
-- is not the JSON that was sent, and the row still says success: @\\u0041@ (a
-- backslash and the text u0041) comes back as @A@, and a Windows path, a tab
-- or a line break comes back as null. Only a payload that holds @"@, or a
-- control character that JSON writes as @\\u0001@, which is no Haskell
-- escape, is loud: the wrapper fails to lex.
escapeAsL4String :: Aeson.Value -> Text
escapeAsL4String val =
  let jsonText = Text.Lazy.toStrict $ Text.Lazy.Encoding.decodeUtf8 $ Aeson.encode val
  in showStringLit jsonText

generateEvalDirective :: Text -> [(Text, Maybe (Type' Resolved))] -> Text
generateEvalDirective funName params = Text.unlines
  [ "#EVAL"
  , "  CONSIDER decodeArgs inputJson"
  , "    WHEN RIGHT args THEN JUST (" <> functionCall <> ")"
  , "    WHEN LEFT error THEN NOTHING"
  ]
  where
    functionCall = quoteIdent funName <> " " <> Text.unwords (map mkArgAccess params)
    mkArgAccess (name, _) = "(args's " <> quoteIdent name <> ")"

-- | Quote an identifier in backticks when it isn't a plain identifier
-- (e.g. exported names and parameters written in natural language with
-- spaces), so the generated wrapper parses.
quoteIdent :: Text -> Text
quoteIdent name
  | isPlain   = name
  | otherwise = "`" <> name <> "`"
  where
    isPlain = case Text.uncons name of
      Just (c, _) -> isAlpha c && Text.all (\x -> isAlphaNum x || x == '_') name
      Nothing     -> False

extractParamsFromExport :: ExportedFunction -> [(Text, Maybe (Type' Resolved))]
extractParamsFromExport ef =
  [(p.paramName, p.paramType) | p <- ef.exportParams]

findExportFunction :: Maybe Text -> Module Resolved -> Either Text ExportedFunction
findExportFunction mName m =
  let exports = getExportedFunctions m
  in case mName of
       Just name ->
         case List.find (\e -> e.exportName == name) exports of
           Just ef -> Right ef
           Nothing -> Left $ "no @export function named '" <> name <> "' found"
       Nothing ->
         case getDefaultFunction m of
           Just ef -> Right ef
           Nothing -> case exports of
             (ef:_) -> Right ef
             []     -> Left "no @export functions found in module"
