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
import qualified Data.Csv as Csv
import qualified Data.HashMap.Strict as HashMap
import qualified Data.List as List
import Data.Maybe (fromMaybe)
import qualified Data.Vector as Vector
import qualified Data.Yaml as Yaml
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
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
  , prettyEvalException
  )
import L4.Print (prettyLayout)
import L4.Syntax (Module, Resolved, Type')

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

  -- Step 3: process each row into an envelope, honoring stop-on-error, and
  -- write the results in the requested format.
  let process = processRow opts evalConfig filteredSource exportFn params schema
  withOutputHandle opts.batchOutput \h ->
    case opts.batchOutputFormat of
      -- NDJSON streams line-by-line so huge batches stay memory-flat.
      FmtNdjson -> do
        (_, anyFail) <- runRows opts.batchContinueOnErr inputs process
          (\env -> BSL8.hPutStrLn h (Aeson.encode env) >> hFlush h)
        finish anyFail
      -- The buffered formats must see every row before they can render.
      _ -> do
        (envs, anyFail) <- runRows opts.batchContinueOnErr inputs process (const (pure ()))
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

-- | Fold over the input rows, producing one result envelope each.
--
-- The @emit@ callback receives each envelope as it is produced (used for
-- NDJSON streaming; a no-op for buffered formats). Stops at the first
-- failing row unless @continueOnErr@ is set. Returns the collected
-- envelopes (in input order) and whether any row failed.
runRows
  :: Bool
  -> [Aeson.Value]
  -> (Int -> Aeson.Value -> IO (Aeson.Value, Bool))
  -> (Aeson.Value -> IO ())
  -> IO ([Aeson.Value], Bool)
runRows continueOnErr inputs process emit = go (zip [1 :: Int ..] inputs) [] False
  where
    go [] acc anyFail = pure (reverse acc, anyFail)
    go ((idx, input) : rest) acc anyFail = do
      (env, isErr) <- process idx input
      emit env
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
  -> Int
  -> Aeson.Value
  -> IO (Aeson.Value, Bool)
processRow opts evalConfig filteredSource exportFn params schema idx input
  | opts.batchValidateOnly =
      let errs = validateRow schema input
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
              -- declared type). Those surface as `Reduction (Left …)`.
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

-- | Pretty-printed exception messages for any @#EVAL@ result that reduced
-- to an evaluation exception. An empty list means the row evaluated cleanly.
resultExceptionMsgs :: EvalDirectiveResult -> [Text]
resultExceptionMsgs (MkEvalDirectiveResult _ res _) = case res of
  Reduction (Left exc) -> prettyEvalException exc
  _                    -> []

----------------------------------------------------------------------------
-- Row validation (for --validate-only)
----------------------------------------------------------------------------

-- | Best-effort validation of one input row against the export schema.
-- Checks that required (non-@MAYBE@) params are present and non-null, and
-- that primitive-typed values have the right JSON kind. Lenient on
-- compound/unknown types (never rejects what it cannot judge).
validateRow :: [ExportedParam] -> Aeson.Value -> [Text]
validateRow schema (Aeson.Object o) = concatMap checkParam schema
  where
    checkParam p =
      case KeyMap.lookup (Key.fromText p.paramName) o of
        Nothing ->
          [ "Missing required field: '" <> p.paramName <> "'" <> descSuffix p
          | p.paramRequired ]
        Just Aeson.Null ->
          [ "Field '" <> p.paramName <> "' is null but required" <> descSuffix p
          | p.paramRequired ]
        Just v -> case primKind p.paramType of
          Just k | not (jsonMatchesKind k v) ->
            [ "Type mismatch for field '" <> p.paramName <> "': expected "
              <> kindName k <> ", got " <> jsonKindName v <> descSuffix p ]
          _ -> []
    descSuffix p = case p.paramDescription of
      Just d | not (Text.null d) -> " (" <> d <> ")"
      _ -> ""
validateRow _ other =
  [ "Input record is not a JSON object: " <> jsonKindName other ]

data PrimKind = KNum | KBool | KStr

kindName :: PrimKind -> Text
kindName = \case KNum -> "NUMBER"; KBool -> "BOOLEAN"; KStr -> "STRING"

-- | Classify a param's declared type as a primitive kind we can check,
-- unwrapping a single leading @MAYBE@. Returns Nothing for compound or
-- unknown types (which we then treat leniently).
primKind :: Maybe (Type' Resolved) -> Maybe PrimKind
primKind mty = do
  ty <- mty
  let t0 = Text.toUpper (Text.strip (prettyLayout ty))
      t  = fromMaybe t0 (Text.stripPrefix "MAYBE " t0)
  case t of
    "NUMBER"  -> Just KNum
    "BOOLEAN" -> Just KBool
    "STRING"  -> Just KStr
    _         -> Nothing

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

parseBatchInput :: Text -> BSL.ByteString -> Either String [Aeson.Value]
parseBatchInput fmt bytes = case Text.toLower fmt of
  "json" -> case Aeson.eitherDecode' bytes of
    Left err -> Left err
    Right (Aeson.Array arr) -> Right (Vector.toList arr)
    Right single            -> Right [single]
  "yaml" -> case Yaml.decodeEither' (BSL.toStrict bytes) of
    Left err -> Left (Yaml.prettyPrintParseException err)
    Right val -> case val of
      Aeson.Array arr -> Right (Vector.toList arr)
      single          -> Right [single]
  "csv" -> case Csv.decodeByName bytes of
    Left err -> Left err
    Right (_, rows) -> Right (map rowToJson (Vector.toList rows))
      where
        rowToJson :: Csv.NamedRecord -> Aeson.Value
        rowToJson record = Aeson.Object $ KeyMap.fromList $
          map (\(k, v) -> (Key.fromText (decodeUtf8 k), inferCsvCell v)) $
          HashMap.toList record
  other -> Left ("Unsupported format: " ++ Text.unpack other)

-- | Infer a JSON value for a raw CSV cell, per the spec's rules:
--
--   * empty cell            -> @null@ (decodes to @NOTHING@ for MAYBE params)
--   * @true@/@false@ (ci)   -> boolean
--   * a JSON number literal -> number  (leading-zero strings like @007@
--                              are /not/ JSON numbers, so they stay strings)
--   * everything else       -> string  (dates included: JSON has no date
--                              type, and JSONDECODE parses date strings)
--
-- Numbers are recognised by aeson's own JSON grammar, which rejects
-- ambiguous forms (leading zeros, thousands separators, leading @+@), so
-- identifiers that merely look numeric survive as strings.
inferCsvCell :: BS.ByteString -> Aeson.Value
inferCsvCell raw =
  let rawText = decodeUtf8 raw
      s       = Text.strip rawText
  in if Text.null s
       then Aeson.Null
       else case Text.toLower s of
         "true"  -> Aeson.Bool True
         "false" -> Aeson.Bool False
         _ -> case Aeson.decodeStrict (encodeUtf8 s) :: Maybe Aeson.Value of
           Just n@(Aeson.Number _) -> n
           _                       -> Aeson.String rawText

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
        , "#EVAL " <> funName
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
      in fieldIndent <> name <> " IS " <> tyText

generateDecoder :: Text
generateDecoder = Text.unlines
  [ "GIVEN jsn IS A STRING"
  , "GIVETH AN EITHER STRING InputArgs"
  , "decodeArgs jsn MEANS JSONDECODE jsn"
  ]

generateJsonPayload :: Aeson.Value -> Text
generateJsonPayload json =
  "DECIDE inputJson IS " <> escapeAsL4String json

escapeAsL4String :: Aeson.Value -> Text
escapeAsL4String val =
  let jsonText = Text.Lazy.toStrict $ Text.Lazy.Encoding.decodeUtf8 $ Aeson.encode val
      escaped  = Text.replace "\"" "\\\"" jsonText
  in "\"" <> escaped <> "\""

generateEvalDirective :: Text -> [(Text, Maybe (Type' Resolved))] -> Text
generateEvalDirective funName params = Text.unlines
  [ "#EVAL"
  , "  CONSIDER decodeArgs inputJson"
  , "    WHEN RIGHT args THEN JUST (" <> functionCall <> ")"
  , "    WHEN LEFT error THEN NOTHING"
  ]
  where
    functionCall = funName <> " " <> Text.unwords (map mkArgAccess params)
    mkArgAccess (name, _) = "(args's " <> name <> ")"

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
