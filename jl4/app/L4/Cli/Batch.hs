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
-- @{ input, output, status, presumed, diagnostics }@ (validate-only mode emits
-- @{ input, status, errors }@ instead). @presumed@ lists the inputs whose
-- @TYPICALLY@ default the row's answer rests on: those the row left out, that
-- took their default (or, for a MAYBE input with none, NOTHING), and that the
-- evaluation actually read (T6 of @specs\/todo\/TYPICALLY-ONE-BEHAVIOUR-SPEC.md@).
--
-- An input the row leaves out takes its default while presumption is on
-- (@--presumption soft@, the default); with @--presumption hard@ it is a
-- missing input, and the row is an error naming it (T4). @null@ never takes a
-- default (T3). In CSV input an empty cell is a left-out input, not @null@
-- (T3c).
--
-- Error handling follows the spec: batch processing stops at the first
-- failing row by default; pass @--continue-on-error@ to process every row
-- and aggregate failures. Either way the process exits non-zero if any row
-- failed.
module L4.Cli.Batch
  ( BatchOptions(..)
  , OutputFormat(..)
  , Presumption(..)
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
import Data.Maybe (isJust)
import Data.Word (Word8)
import Data.Char (isAlpha, isAlphaNum)
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

import L4.Export
  ( AssumeRewrite(..)
  , ExportedFunction(..)
  , ExportedParam(..)
  , extractAssumeParamResolveds
  , getDefaultFunction
  , getExportedFunctions
  , honouredDefault
  , isRequiredInput
  , rewriteModuleAssumes
  )
import L4.DirectiveFilter (filterIdeDirectives)
import L4.EvaluateLazy
  ( EvalConfig(..)
  , EvalDirectiveResult(..)
  , requestPresumed
  , renderPresumedPath
  , moduleDeclares
  , EvalDirectiveValue(..)
  , AssertionOutcome(..)
  , ReductionOutcome(..)
  , prettyEvalException
  , prettyRefusal
  , prettyUndetermined
  )
import L4.Lexer (showStringLit)
import L4.Presumption (nearestName, requestRecordName, unrecognisedMessage)
import L4.Print (prettyLayout, restoreMixfixPatterns)
import L4.Syntax
  ( AppForm(..), Assume(..), Declare(..), Decide(..), Expr, GivenSig(..), Module(..), Resolved
  , Type'(..), TypeDecl(..), TypedName(..), TypeSig(..), Unique, getActual, getUnique, rawName
  , rawNameToText
  )
import L4.TypeCheck.Environment (listUnique, maybeUnique)

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

-- | T4's presumption switch, under the names Meng's original Default design
-- gave its two modes (T3c): soft uses @TYPICALLY@ defaults, hard does not.
data Presumption
  = PresumeSoft  -- ^ an input the row leaves out takes its default (the default)
  | PresumeHard  -- ^ an input the row leaves out is missing, default or no
  deriving (Eq, Show)

presumptionReader :: ReadM Presumption
presumptionReader = eitherReader \input ->
  case Text.toLower (Text.pack input) of
    "soft" -> Right PresumeSoft
    "hard" -> Right PresumeHard
    other  -> Left $ "Invalid presumption: " <> Text.unpack other <> " (expected soft|hard)"

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
  , batchPresumption    :: Presumption
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
  <*> option presumptionReader
        ( long "presumption"
        <> metavar "MODE"
        <> value PresumeSoft
        <> showDefaultWith (const "soft")
        <> help "soft (default): an input a row leaves out takes its TYPICALLY default; hard: it is a missing input, and the row is an error naming it"
        )

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

batchCmd :: BatchOptions -> IO ()
batchCmd opts = do
  evalConfig0 <- makeEvalConfig opts.batchFixedNow
  -- T4: one switch for the whole evaluation. The JSON decoder reads it for
  -- every input and record field it fills; discharge reads it for a section
  -- binder (which batch supplies through the decoder anyway, see below).
  -- The wrapper decodes each row into 'requestRecordName'; that decode is the
  -- request's, the one the switch reaches (T4b).
  let evalConfig = evalConfig0
        { presumeDefaults = opts.batchPresumption == PresumeSoft
        , requestRecord   = Just requestRecordName
        }

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
  -- 'getExportedFunctions' lists the GIVEN parameters first and then the
  -- ASSUMEs the export reads (directly or through any helper it reaches).
  -- Only the GIVENs are call arguments; each read ASSUME is bound by
  -- redefining it over the decoded row in the wrapper (see
  -- 'generateBatchWrapper'), and dropped from the printed module so the
  -- wrapper's definition takes its place. Redefining at the ASSUME's own
  -- name is what lets a helper see the value: a LET around the call
  -- would only be visible to the call expression, not to the closures
  -- the module's definitions captured.
  let MkDecide _ (MkTypeSig _ (MkGivenSig _ givenNames) _) _ _ = exportFn.exportDecide
      (givenParams, assumeParams) =
        List.splitAt (length givenNames) (extractParamsFromExport exportFn)
      readAssumes    = Set.fromList
        [ getUnique r | (r, _) <- extractAssumeParamResolveds tcRes.module' exportFn.exportDecide ]
      unbindRead (MkAssume _ _ (MkAppForm _ r _ _) _ _)
        | getUnique r `Set.member` readAssumes = DropAssume
        | otherwise                            = KeepAssume
      -- restoreMixfixPatterns BEFORE filtering and printing: the printer can
      -- otherwise emit only a mixfix name's head keyword, and a module with two
      -- operators sharing one comes back resolving to the wrong operator
      -- (smucclaw/l4-ide#967). `l4 batch` re-runs what it prints, so this is a
      -- correctness path and not a cosmetic one.
      filteredModule = rewriteModuleAssumes unbindRead (filterIdeDirectives (restoreMixfixPatterns tcRes.mixfixRegistry tcRes.module'))
      filteredSource = prettyLayout filteredModule
      schema         = exportFn.exportParams
      -- Every input the export reads is a field of the wrapper's InputArgs
      -- record, so a default the row may take is that field's TYPICALLY, and
      -- the JSON decoder fills it (W3; T1b). That is one fill site for rule
      -- GIVENs, section GIVENs and record fields alike, it survives the
      -- re-print (the wrapper is source text), and the decoder reports each
      -- default it filled when the evaluation forces it.
      defaults       = Map.fromList
        [ (p.paramName, d) | p <- schema, Just d <- [honouredDefault p] ]

  -- Step 3: process each row into an envelope, honoring stop-on-error, and
  -- write the results in the requested format.
      -- every record an input may hold, this module's and its imports', for
      -- --validate-only's check of an unknown key (review M1)
      shapes         = recordShapes (concatMap (moduleDeclares . (.module')) (tcRes : allDependencies tcRes))

  let process = processRow opts evalConfig filteredSource exportFn givenParams assumeParams defaults schema shapes
  withOutputHandle opts.batchOutput \h ->
    case opts.batchOutputFormat of
      -- NDJSON streams line-by-line so huge batches stay memory-flat: we emit
      -- each envelope, let it become garbage, and never build the row list.
      FmtNdjson -> do
        outcome <- streamRows opts.batchContinueOnErr inputs process
          (\env -> BSL8.hPutStrLn h (Aeson.encode env) >> hFlush h)
        finish outcome
      -- The buffered formats must see every row before they can render, so
      -- here (and only here) we retain the whole list of envelopes.
      _ -> do
        (envs, outcome) <- bufferRows opts.batchContinueOnErr inputs process
        writeBuffered h opts.batchOutputFormat envs
        finish outcome
  where
    -- A batch exits 1 if any row failed, and also if any row was
    -- undetermined, once every row has run: an undetermined row never stops
    -- the batch, but the batch has not answered every case
    -- (UNKNOWN-EVALUATION-SPEC §4.7.4, U7b, build step 3).
    finish outcome = case outcome of
      RowFine         -> exitSuccess
      RowUndetermined -> exitFailure
      RowFailed       -> exitFailure

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
  -> [row]
  -> (Int -> row -> IO (Aeson.Value, RowOutcome))
  -> (Aeson.Value -> IO ())
  -> IO RowOutcome
streamRows continueOnErr inputs process emit = go (zip [1 :: Int ..] inputs) RowFine
  where
    go [] !worst = pure worst
    go ((idx, input) : rest) !worst = do
      (env, outcome) <- process idx input
      emit env
      let !worst' = max worst outcome
      if outcome == RowFailed && not continueOnErr
        then pure RowFailed              -- stop-on-error (the default)
        else go rest worst'

-- | What a row came to, for the batch's exit code, worst last. Only a failed
-- row trips stop-on-error; an undetermined one does not (U7b).
data RowOutcome = RowFine | RowUndetermined | RowFailed
  deriving stock (Eq, Ord, Show)

-- | Fold over the input rows for the buffered formats (json/yaml/csv), which
-- genuinely need every row in hand before they can render. Returns the
-- collected envelopes (in input order) and whether any row failed. Stops at
-- the first failing row unless @continueOnErr@ is set.
bufferRows
  :: Bool
  -> [row]
  -> (Int -> row -> IO (Aeson.Value, RowOutcome))
  -> IO ([Aeson.Value], RowOutcome)
bufferRows continueOnErr inputs process = go (zip [1 :: Int ..] inputs) [] RowFine
  where
    go [] acc worst = pure (reverse acc, worst)
    go ((idx, input) : rest) acc worst = do
      (env, outcome) <- process idx input
      let acc'   = env : acc
          worst' = max worst outcome
      if outcome == RowFailed && not continueOnErr
        then pure (reverse acc', RowFailed)  -- stop-on-error (the default)
        else go rest acc' worst'

-- | Process a single input row into a result envelope, returning the
-- envelope and whether the row failed.
processRow
  :: BatchOptions
  -> EvalConfig
  -> Text                                    -- ^ filtered source
  -> ExportedFunction
  -> [(Text, Maybe (Type' Resolved))]        -- ^ GIVEN params (call arguments)
  -> [(Text, Maybe (Type' Resolved))]        -- ^ read ASSUMEs (bound by name)
  -> Map.Map Text (Expr Resolved)            -- ^ the defaults a row may take, by input
  -> [ExportedParam]                         -- ^ full schema for validation
  -> RecordShapes                            -- ^ the records an input may hold, for validation
  -> Int
  -> BatchRow
  -> IO (Aeson.Value, RowOutcome)
processRow opts _ _ _ _ _ _ _ _ _ (RefusedRow input reason)
  -- refused while reading the file: an error in either mode
  | opts.batchValidateOnly = pure
      ( Aeson.object
          [ Key.fromString "input"  Aeson..= input
          , Key.fromString "status" Aeson..= ("invalid" :: Text)
          , Key.fromString "errors" Aeson..= [reason]
          ]
      , RowFailed )
  | otherwise = pure
      ( Aeson.object
          [ Key.fromString "input"       Aeson..= input
          , Key.fromString "output"      Aeson..= Aeson.Null
          , Key.fromString "status"      Aeson..= ("error" :: Text)
          , Key.fromString "presumed"    Aeson..= ([] :: [Text])
          , Key.fromString "diagnostics" Aeson..= [reason]
          ]
      , RowFailed )
processRow opts evalConfig filteredSource exportFn givenParams assumeParams defaults schema shapes idx (BatchRow input)
  | opts.batchValidateOnly =
      let errs = validateRow opts.batchPresumption schema shapes input
          ok   = null errs
          env  = Aeson.object
            [ Key.fromString "input"  Aeson..= input
            , Key.fromString "status" Aeson..= (if ok then "valid" else "invalid" :: Text)
            , Key.fromString "errors" Aeson..= errs
            ]
      in pure (env, if ok then RowFine else RowFailed)
  | otherwise = do
      let wrapperCode     = generateBatchWrapper exportFn.exportName givenParams assumeParams defaults input
          combinedProgram = filteredSource <> wrapperCode
          virtualPath     = opts.batchFile ++ ".batch" ++ show idx ++ ".l4"
      (evalErrs, mEval) <- runOneshot evalConfig virtualPath \nfp -> do
        let uri = normalizedFilePathToUri nfp
        _ <- Shake.addVirtualFile (toNormalizedFilePath virtualPath) combinedProgram
        Shake.use Rules.EvaluateLazy uri
      let presumed = case mEval of
            Nothing          -> []
            Just evalResults -> rowPresumed opts.batchPresumption schema evalResults
          (status, outputJson, diags) = case mEval of
            Nothing ->
              -- The wrapper failed to typecheck/parse (e.g. a schema mismatch).
              ("error" :: Text, Aeson.Null, Aeson.toJSON evalErrs)
            Just evalResults ->
              -- The wrapper evaluated; a row still "fails" if evaluation raised
              -- an exception (e.g. JSONDECODE could not coerce a cell to the
              -- declared type). Those surface as `Reduction (Left …)`.
              let excMsgs = concatMap resultExceptionMsgs evalResults
                  undMsgs = concatMap resultUndeterminedMsgs evalResults
                  refMsgs = concatMap resultRefusalMsgs evalResults
              in if not (null excMsgs)
                   then ("error",   Aeson.toJSON evalResults, Aeson.toJSON excMsgs)
                   -- An UNDETERMINED row is not a failure either: the row did
                   -- not supply something the rule needs, and the messages
                   -- name it. It never stops the batch, but the batch exits 1
                   -- once every row has run (UNKNOWN-EVALUATION-SPEC §4.7.4,
                   -- U7b, build step 3).
                   else if not (null undMsgs)
                   then ("undetermined", Aeson.toJSON evalResults, Aeson.toJSON undMsgs)
                   -- A REFUSED row is a determinate answer, not a failure: the
                   -- model declined to answer this input and said why. It gets
                   -- its own terminal status and, crucially, does NOT stop the
                   -- batch (see the 'status == "error"' test below).
                   else if not (null refMsgs)
                   then ("refused", Aeson.toJSON evalResults, Aeson.toJSON refMsgs)
                   else ("success", Aeson.toJSON evalResults, Aeson.Array mempty)
          env = Aeson.object
            [ Key.fromString "input"       Aeson..= input
            , Key.fromString "output"      Aeson..= outputJson
            , Key.fromString "status"      Aeson..= status
            , Key.fromString "presumed"    Aeson..= presumed
            , Key.fromString "diagnostics" Aeson..= diags
            ]
      pure (env, case status of
        "error"        -> RowFailed
        "undetermined" -> RowUndetermined
        _              -> RowFine)

-- | The inputs whose default this row's answer rests on (T6): every default
-- the evaluation forced that belongs to the request, as the input's name or,
-- for a field inside an input, the path to it (@config.timeout@). The wrapper
-- decodes the row as the request record ('requestRecordName'), so the
-- request's own events are the ones that decode raised. The filter is the
-- service's too ('requestPresumed').
rowPresumed :: Presumption -> [ExportedParam] -> [EvalDirectiveResult] -> [Text]
rowPresumed presumption schema results =
  requestPresumed (presumption == PresumeSoft) id inputs (concatMap (.presumed) results)
  where
    inputs = Set.fromList [ x.paramName | x <- schema ]

-- | Pretty-printed exception messages for any @#EVAL@ result that reduced
-- to an evaluation exception. An empty list means the row evaluated cleanly.
resultExceptionMsgs :: EvalDirectiveResult -> [Text]
resultExceptionMsgs (MkEvalDirectiveResult _ res _ _ _ _) = case res of
  Reduction (ReducedErrored exc) -> prettyEvalException exc
  Assertion (Errored exc)        -> prettyEvalException exc
  -- A refusal is deliberately NOT counted here: it is not an exception, and
  -- counting it would both mark the row an error and stop the batch. Nor is
  -- an undetermined result, for the same reason ('resultUndeterminedMsgs').
  Reduction (ReducedRefused _)      -> []
  Assertion (Refused _)             -> []
  Reduction (ReducedUndetermined _) -> []
  Assertion (Undetermined _)        -> []
  Reduction (Reduced _)             -> []
  Assertion Holds                   -> []
  Assertion Fails                   -> []
  Assertion (FailsBecause _)        -> []

-- | What an undetermined result waits on, as the default report says it, for
-- any directive in the row that could not be decided. An empty list means
-- every directive in the row was decided.
resultUndeterminedMsgs :: EvalDirectiveResult -> [Text]
resultUndeterminedMsgs (MkEvalDirectiveResult _ res _ _ _ _) = case res of
  Reduction (ReducedUndetermined ns) -> prettyUndetermined ns
  Assertion (Undetermined ns)        -> prettyUndetermined ns
  Reduction (ReducedErrored _)       -> []
  Assertion (Errored _)              -> []
  Reduction (ReducedRefused _)       -> []
  Assertion (Refused _)              -> []
  Reduction (Reduced _)              -> []
  Assertion Holds                    -> []
  Assertion Fails                    -> []
  Assertion (FailsBecause _)         -> []

-- | Refusal reasons for any directive in the row that REFUSED. An empty list
-- means nothing in the row declined to answer.
resultRefusalMsgs :: EvalDirectiveResult -> [Text]
resultRefusalMsgs (MkEvalDirectiveResult _ res _ _ _ _) = case res of
  Reduction (ReducedRefused r) -> prettyRefusal r
  Assertion (Refused r)        -> prettyRefusal r
  Reduction (ReducedErrored _)       -> []
  Assertion (Errored _)              -> []
  Reduction (ReducedUndetermined _)  -> []
  Assertion (Undetermined _)         -> []
  Reduction (Reduced _)              -> []
  Assertion Holds                    -> []
  Assertion Fails                    -> []
  Assertion (FailsBecause _)         -> []

----------------------------------------------------------------------------
-- Row validation (for --validate-only)
----------------------------------------------------------------------------

-- | Best-effort validation of one input row against the export schema.
-- Checks that required params are present, that non-@MAYBE@ params are
-- non-null, and that primitive-typed values have the right JSON kind. Lenient
-- on compound/unknown types (never rejects what it cannot judge).
--
-- \"Required\" is what evaluation will demand, so that a row validates exactly
-- when its inputs would decode (R3): with presumption soft, an input with a
-- default or a @MAYBE@ type may be left out; with it hard, nothing may (T4,
-- T1b). @null@ is a value, not an omission, and never takes a default (T3), so
-- a non-@MAYBE@ input sent as @null@ is invalid in either mode.
--
-- Where an input left out takes its default, a key that matches no input is
-- refused, naming it and the nearest input, as evaluation refuses it (review
-- M1), and likewise inside a record an input holds, where a field left out
-- takes its default.
validateRow :: Presumption -> [ExportedParam] -> RecordShapes -> Aeson.Value -> [Text]
validateRow presumption schema shapes (Aeson.Object o) =
  unknownAtRoot <> concatMap checkParam schema
    <> concat [ unknownIn presumption shapes [p.paramName] ty v
              | p <- schema, Just ty <- [p.paramType], Just v <- [KeyMap.lookup (Key.fromText p.paramName) o] ]
  where
    names = map (.paramName) schema
    tookDefault = presumption == PresumeSoft &&
      or [ True | p <- schema, isJust (honouredDefault p), not (KeyMap.member (Key.fromText p.paramName) o) ]
    unknownAtRoot =
      [ unrecognisedMessage "field" [ (k, nearestName k names) | k <- unknown ]
      | tookDefault
      , let unknown = [ Key.toText k | k <- KeyMap.keys o, Key.toText k `notElem` names ]
      , not (null unknown) ]
    mustSupply p = case presumption of
      PresumeSoft -> isRequiredInput p
      PresumeHard -> True
    checkParam p =
      case KeyMap.lookup (Key.fromText p.paramName) o of
        Nothing ->
          [ "Missing required field: '" <> p.paramName <> "'" <> descSuffix p
          | mustSupply p ]
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
validateRow _ _ _ other =
  [ "Input record is not a JSON object: " <> jsonKindName other ]

-- | Each record type's fields, with whether each has a @TYPICALLY@, keyed by
-- the type's 'Unique'.
type RecordShapes = Map.Map Unique [(Text, Type' Resolved, Bool)]

recordShapes :: [Declare Resolved] -> RecordShapes
recordShapes decls = Map.fromList
  [ (getUnique tyName, [ (rawNameToText (rawName (getActual fn)), fty, isJust d) | MkTypedName _ fn fty d _ <- fields ])
  | MkDeclare _ _ (MkAppForm _ tyName _ _) (RecordDecl _ _ fields) <- decls ]

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

-- | The unknown-key refusals inside one value of an input, at @path@: in a
-- record object where a field left out takes its default (with presumption
-- soft), a key that matches no field; then the same inside its fields, and
-- inside the elements of a list. A type it cannot see into is left alone.
unknownIn :: Presumption -> RecordShapes -> [Text] -> Type' Resolved -> Aeson.Value -> [Text]
unknownIn presumption shapes path ty v = case (ty, v) of
  (TyApp _ name [inner], _) | getUnique name == maybeUnique -> unknownIn presumption shapes path inner v
  (TyApp _ name [inner], Aeson.Array xs) | getUnique name == listUnique ->
    concat [ unknownIn presumption shapes (path <> ["[" <> Text.pack (show i) <> "]"]) inner x
           | (i, x) <- zip [0 :: Int ..] (Vector.toList xs) ]
  (TyApp _ name [], Aeson.Object o)
    | Just fields <- Map.lookup (getUnique name) shapes, not (KeyMap.null o) ->
        let fieldNames = [ f | (f, _, _) <- fields ]
            pathTo k   = renderPresumedPath (path <> [k])
            took       = presumption == PresumeSoft &&
              or [ True | (f, _, True) <- fields, not (KeyMap.member (Key.fromText f) o) ]
            unknown    = [ Key.toText k | k <- KeyMap.keys o, Key.toText k `notElem` fieldNames ]
        in [ unrecognisedMessage "field" [ (pathTo k, pathTo <$> nearestName k fieldNames) | k <- unknown ]
           | took, not (null unknown) ]
           <> concat [ unknownIn presumption shapes (path <> [f]) fty x
                     | (f, fty, _) <- fields, Just x <- [KeyMap.lookup (Key.fromText f) o] ]
  _ -> []

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
  = BatchRow Aeson.Value
  | RefusedRow Aeson.Value Text

parseBatchInput :: Text -> BSL.ByteString -> Either String [BatchRow]
parseBatchInput fmt bytes = case Text.toLower fmt of
  "json" -> case Aeson.eitherDecode' bytes of
    Left err -> Left err
    Right (Aeson.Array arr) -> Right (map BatchRow (Vector.toList arr))
    Right single            -> Right [BatchRow single]
  "yaml" -> case Yaml.decodeEither' (BSL.toStrict bytes) of
    Left err -> Left (Yaml.prettyPrintParseException err)
    Right val -> case val of
      Aeson.Array arr -> Right (map BatchRow (Vector.toList arr))
      single          -> Right [BatchRow single]
  "csv" -> case csvRows bytes of
    Left err -> Left err
    Right rows -> Right
      [ case r of
          CsvRecord record         -> BatchRow (rowToJson record)
          CsvRagged record reason  -> RefusedRow (rowToJson record) reason
      | r <- rows ]
      where
        -- An EMPTY cell is left out of the row, exactly as if its column were
        -- not there (T3c): the input is absent, so with presumption soft it
        -- takes its TYPICALLY default (or, for a MAYBE input with none,
        -- NOTHING), and with presumption hard it is missing. CSV has no
        -- spelling of null; T3c adds one only when a user needs it.
        rowToJson :: Csv.NamedRecord -> Aeson.Value
        rowToJson record = Aeson.Object $ KeyMap.fromList
          [ (Key.fromText (decodeUtf8 k), inferCsvCell v)
          | (k, v) <- HashMap.toList record
          , not (Text.null (Text.strip (decodeUtf8 v)))
          ]
  other -> Left ("Unsupported format: " ++ Text.unpack other)

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
-- short one used to take the defaults of its missing cells, and a long one
-- lost its extra cells, both with status success (review M4; decided
-- overnight 2026-10-02, pending Meng's review, spec §4.1).
csvRows :: BSL.ByteString -> Either String [CsvRow]
csvRows = AL.eitherResult . AL.parse file
  where
    comma = 44
    file = do
      -- A UTF-8 byte-order mark is not part of the first column's name. Excel's
      -- "CSV UTF-8" export writes one, and left in place it renamed the first
      -- input, so every row took that input's default instead of its value
      -- (review B1).
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
                        <> " short row would otherwise take its default, and a long row's extra cells"
                        <> " would be dropped"
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

-- | Infer a JSON value for a raw, non-empty CSV cell (an empty one never gets
-- here: it is left out of the row, see 'parseBatchInput'):
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
inferCsvCell :: BS.ByteString -> Aeson.Value
inferCsvCell raw =
  let rawText = decodeUtf8 raw
      s       = Text.strip rawText
  in case Text.toLower s of
       "true"  -> Aeson.Bool True
       "false" -> Aeson.Bool False
       _ | Text.any (\c -> c == 'e' || c == 'E') s -> Aeson.String rawText
         | otherwise -> case Aeson.decodeStrict (encodeUtf8 s) :: Maybe Aeson.Value of
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
  let canonical = ["output", "status", "presumed", "errors", "diagnostics"]
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
      -- @presumed@ is a list, so its cell is the same list as compact JSON,
      -- @[]@ when nothing was presumed: an input's name may contain a comma or
      -- a semicolon, so no separator could be read back.
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

-- | The wrapper decodes the row into an @InputArgs@ record holding every
-- schema field (GIVENs and read ASSUMEs alike), applies the export to the
-- GIVEN fields, and redefines each read ASSUME as a definition over the
-- decoded row ('generateAssumeBinding') — the ASSUME itself having been
-- dropped from the printed module by 'batchCmd', so the module's other
-- definitions now resolve the name to this binding.
generateBatchWrapper
  :: Text
  -> [(Text, Maybe (Type' Resolved))]        -- ^ GIVEN params (call arguments)
  -> [(Text, Maybe (Type' Resolved))]        -- ^ read ASSUMEs (bound by name)
  -> Map.Map Text (Expr Resolved)            -- ^ the defaults a row may take, by input
  -> Aeson.Value
  -> Text
generateBatchWrapper funName givenParams assumeParams defaults inputJson
  | null givenParams && null assumeParams =
      Text.unlines
        [ ""
        , "-- ========== GENERATED WRAPPER =========="
        , ""
        , "#EVAL " <> quoteIdent funName
        ]
  | otherwise =
      Text.unlines $
        [ ""
        , "-- ========== GENERATED WRAPPER =========="
        , ""
        , generateInputRecord defaults (givenParams <> assumeParams)
        , ""
        , generateDecoder
        , ""
        , generateJsonPayload inputJson
        , ""
        ]
        ++ map generateAssumeBinding assumeParams
        ++ [ generateEvalDirective funName givenParams ]

-- | Bind one read ASSUME to its field of the decoded row. Only the
-- @RIGHT@ branch is needed: the @#EVAL@ directive decodes the row first
-- and returns @NOTHING@ on a decode failure without ever forcing this
-- binding, so the missing @LEFT@ branch is unreachable — @\@nonexhaustive@
-- records that and keeps the checker quiet about it.
generateAssumeBinding :: (Text, Maybe (Type' Resolved)) -> Text
generateAssumeBinding (name, _) = Text.unlines
  [ "@nonexhaustive ASSUME " <> name <> ", bound from the input row"
  , quoteIdent name <> " MEANS"
  , "  CONSIDER decodeArgs inputJson"
  , "    WHEN RIGHT args THEN args's " <> quoteIdent name
  ]

-- | The record each row decodes into, one field per input. An input with a
-- default carries it as the field's TYPICALLY, which is what the decoder fills
-- an absent field from (and, with presumption hard, does not).
--
-- One field per line, each indented, with no separating commas. A leading
-- @, @ at column 1 after a field whose type is an application (@MAYBE
-- NUMBER@) does not parse ("incorrect indentation"), so a row for an export
-- with a @MAYBE@ input before another input used to fail every time.
generateInputRecord :: Map.Map Text (Expr Resolved) -> [(Text, Maybe (Type' Resolved))] -> Text
generateInputRecord defaults params = Text.unlines $
  ["DECLARE " <> requestRecordName <> " HAS"] ++
  map formatField params
  where
    formatField (name, mty) =
      let tyText      = maybe "A NUMBER" prettyLayout mty
          typically   = maybe "" ((" TYPICALLY " <>) . prettyLayout) (Map.lookup name defaults)
      in "  " <> quoteIdent name <> " IS " <> tyText <> typically

generateDecoder :: Text
generateDecoder = Text.unlines
  [ "GIVEN jsn IS A STRING"
  , "GIVETH AN EITHER STRING " <> requestRecordName
  , "decodeArgs jsn MEANS JSONDECODE jsn"
  ]

generateJsonPayload :: Aeson.Value -> Text
generateJsonPayload json =
  "DECIDE inputJson IS " <> escapeAsL4String json

-- | Render a JSON value as an L4 string literal.
--
-- Delegates to the lexer's own 'showStringLit', which emits Haskell-style
-- escapes — the exact inverse of the @Lexer.charLiteral@ the parser uses to
-- read string literals back in. A hand-rolled @"@-only replacement corrupts
-- any payload containing a backslash (e.g. a Windows path @C:\\Users@) or a
-- control character, producing a wrapper that fails to lex.
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
