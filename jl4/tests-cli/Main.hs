-- | Black-box test suite for the @l4@ CLI.
--
-- Each test spawns the @l4@ binary as a subprocess (via cabal's
-- @build-tool-depends@ wiring) and asserts on exit code, stdout, stderr,
-- and — for JSON modes — the shape of the parsed envelope.
--
-- The goal is coverage of /observable behavior/: does @l4 run FILE@ do
-- what the user expects when the file is clean, has eval directives,
-- fails typechecking, or is empty?  Golden-text tests would be brittle
-- against small wording changes; this suite checks *structure* instead.
module Main where

import Control.Monad (forM_, unless)
import Data.List (isInfixOf, isSuffixOf)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy.Char8 as BSL8
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Aeson (Value(..), eitherDecode)
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Key as Key
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , findExecutable
  , getTemporaryDirectory
  , makeAbsolute
  , removeFile
  , removePathForcibly
  )
import System.Environment (lookupEnv)
import System.Exit (ExitCode(..), exitFailure)
import System.FilePath ((</>))
import System.IO (hClose, hSetBinaryMode)
import System.Process
  ( CreateProcess(..)
  , StdStream(..)
  , createProcess
  , proc
  , readCreateProcessWithExitCode
  , waitForProcess
  )
import Test.Hspec

----------------------------------------------------------------------------
-- Locating the l4 binary
----------------------------------------------------------------------------

-- | Find the @l4@ binary to test against.
--
-- Priority:
--
-- 1. @L4_BIN@ environment variable (useful in CI and for manual runs).
-- 2. @cabal list-bin exe:l4@ output (when running under cabal).
-- 3. Walk up from the test binary's path to @dist-newstyle/.../l4@.
locateL4Binary :: IO FilePath
locateL4Binary = do
  fromEnv <- lookupEnv "L4_BIN"
  case fromEnv of
    Just p -> do
      ok <- doesFileExist p
      if ok then pure p else failWith ("L4_BIN set but not a file: " ++ p)
    Nothing -> do
      tryCabal <- cabalListBin
      case tryCabal of
        Just p -> pure p
        Nothing -> failWith
          "Could not find the l4 binary. Set L4_BIN or run via 'cabal test'."
  where
    failWith msg = do
      putStrLn ("ERROR: " ++ msg)
      exitFailure

    -- Best-effort: try `cabal list-bin exe:l4` from cwd.
    cabalListBin :: IO (Maybe FilePath)
    cabalListBin = do
      (code, out, _err) <- readCreateProcessWithExitCode
        (proc "cabal" ["list-bin", "exe:l4"]) ""
      case code of
        ExitSuccess ->
          let path = trim out
          in do
            ok <- doesFileExist path
            pure (if ok then Just path else Nothing)
        _ -> pure Nothing

    trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace
    isSpace c = c == ' ' || c == '\n' || c == '\r' || c == '\t'

----------------------------------------------------------------------------
-- Helpers for running the CLI
----------------------------------------------------------------------------

data Output = Output
  { outExit   :: ExitCode
  , outStdout :: String
  , outStderr :: String
  } deriving (Eq, Show)

-- | Run the l4 binary and capture its stdout + stderr.
--
-- Reads both streams as raw bytes and decodes them as UTF-8 leniently,
-- bypassing @readCreateProcessWithExitCode@'s reliance on the system
-- locale encoding. On Windows CI runners the locale is typically CP1252,
-- which rejects the UTF-8 lead bytes (0xC2, 0xE2, …) that @l4.exe@
-- writes for section markers (§) and en/em-dashes in help text — that
-- is the @hGetContents: cannot decode byte sequence starting from 194@
-- failure we saw on the first Windows build.
runL4 :: FilePath -> [String] -> IO Output
runL4 = runL4In Nothing Nothing

-- | Like 'runL4', but lets a test choose the child's working directory
-- and, with @Just env@, replace its environment wholesale.
runL4In :: Maybe FilePath -> Maybe [(String, String)] -> FilePath -> [String] -> IO Output
runL4In mCwd mEnv bin args = do
  let cp = (proc bin args)
        { std_in  = CreatePipe
        , std_out = CreatePipe
        , std_err = CreatePipe
        , env     = mEnv
        , cwd     = mCwd
        }
  (Just hin, Just hout, Just herr, ph) <- createProcess cp
  hClose hin
  hSetBinaryMode hout True
  hSetBinaryMode herr True
  soutBytes <- BS.hGetContents hout
  serrBytes <- BS.hGetContents herr
  code <- waitForProcess ph
  pure Output
    { outExit   = code
    , outStdout = T.unpack (TE.decodeUtf8Lenient soutBytes)
    , outStderr = T.unpack (TE.decodeUtf8Lenient serrBytes)
    }

-- | Assert the CLI exited 0 with a given substring on stdout.
expectOk :: FilePath -> [String] -> String -> IO ()
expectOk bin args expectedSubstring = do
  Output code sout serr <- runL4 bin args
  case code of
    ExitSuccess ->
      unless (expectedSubstring `isInfixOf` sout) $
        expectationFailure $
          "Expected stdout to contain " ++ show expectedSubstring
          ++ "\n--- stdout ---\n" ++ sout
          ++ "\n--- stderr ---\n" ++ serr
    ExitFailure n -> expectationFailure $
      "Expected success but exited " ++ show n
      ++ "\n--- stdout ---\n" ++ sout
      ++ "\n--- stderr ---\n" ++ serr

-- | Assert the CLI exited non-zero.
expectFail :: FilePath -> [String] -> IO ()
expectFail bin args = do
  Output code _ _ <- runL4 bin args
  case code of
    ExitFailure _ -> pure ()
    ExitSuccess   -> expectationFailure "Expected non-zero exit; got success"

-- | Parse the stdout of a --json run as a JSON envelope.
jsonEnvelope :: FilePath -> [String] -> IO Value
jsonEnvelope bin args = do
  Output _ sout _ <- runL4 bin args
  case eitherDecode (BSL8.pack sout) of
    Right v  -> pure v
    Left err -> do
      expectationFailure ("JSON parse failed: " ++ err ++ "\nstdout:\n" ++ sout)
      error "unreachable"

objField :: Value -> String -> Maybe Value
objField (Object km) k = KeyMap.lookup (Key.fromString k) km
objField _ _ = Nothing

----------------------------------------------------------------------------
-- Fixtures
----------------------------------------------------------------------------

fixtureDir :: FilePath
fixtureDir = "tests-cli/fixtures"

cleanFixture, evalFixture, errorFixture, garbageFixture :: FilePath
cleanFixture   = fixtureDir </> "clean.l4"
evalFixture    = fixtureDir </> "eval.l4"
errorFixture   = fixtureDir </> "typecheck-error.l4"
garbageFixture = fixtureDir </> "garbage.l4"

evalTraceFixture, evalTraceLineBreakFixture :: FilePath
evalTraceFixture = fixtureDir </> "evaltrace.l4"
evalTraceLineBreakFixture = fixtureDir </> "evaltrace-line-break.l4"

batchEligFixture, batchDataJson, batchDataCsv, batchMixedJson :: FilePath
batchEligFixture = fixtureDir </> "batch-elig.l4"
batchDataJson    = fixtureDir </> "batch-data.json"
batchDataCsv     = fixtureDir </> "batch-data.csv"
batchMixedJson   = fixtureDir </> "batch-mixed.json"

batchCodeFixture, batchExponentCsv, batchMaybeFixture, batchMaybeBadJson, batchMaybeTextJson :: FilePath
batchCodeFixture  = fixtureDir </> "batch-code.l4"
batchExponentCsv  = fixtureDir </> "batch-exponent.csv"
batchMaybeFixture = fixtureDir </> "batch-maybe.l4"
batchMaybeBadJson = fixtureDir </> "batch-maybe-bad.json"
batchMaybeTextJson = fixtureDir </> "batch-maybe-text.json"

-- | A CSV with columns no input declares, run against 'batchEligFixture'.
batchUndeclaredColumnCsv :: FilePath
batchUndeclaredColumnCsv = fixtureDir </> "batch-undeclared-column.csv"

-- | Blank CSV cells (T3c): one STRING input that has to be given and one MAYBE
-- STRING input that need not be, and an income column left blank.
batchBlankFixture, batchBlankCsv, batchBlankIncomeCsv, batchSingleObjectJson :: FilePath
batchBlankFixture   = fixtureDir </> "batch-blank.l4"
batchBlankCsv       = fixtureDir </> "batch-blank.csv"
batchBlankIncomeCsv = fixtureDir </> "batch-blank-income.csv"

-- | A cases file that holds one object, not an array.
batchSingleObjectJson = fixtureDir </> "batch-single-object.json"

-- | CSV cells for inputs that are neither a NUMBER nor a BOOLEAN: a choice
-- (@DECLARE Answer IS ONE OF True, False, Unknown@), a @MAYBE@ choice, a DATE,
-- and synonyms of a NUMBER and a BOOLEAN, which are still read as those.
batchDeclaredText, batchDeclaredTextAnswers, batchDeclaredTextOptional, batchDeclaredTextDates, batchDeclaredTextSynonyms :: FilePath
batchDeclaredText         = fixtureDir </> "batch-declared-text.l4"
batchDeclaredTextAnswers  = fixtureDir </> "batch-declared-text-answers.csv"
batchDeclaredTextOptional = fixtureDir </> "batch-declared-text-optional.csv"
batchDeclaredTextDates    = fixtureDir </> "batch-declared-text-dates.csv"
batchDeclaredTextSynonyms = fixtureDir </> "batch-declared-text-synonyms.csv"

-- | Inputs declared through a type synonym (@DECLARE Year IS A NUMBER@, a
-- BOOLEAN, a MAYBE), with the plain types beside them as the control, and the
-- cases for each.
batchSynonym, batchSynonymYearJson, batchSynonymFlagJson, batchSynonymYearCsv, batchSynonymFlagCsv :: FilePath
batchSynonym         = fixtureDir </> "batch-synonym.l4"
batchSynonymYearJson = fixtureDir </> "batch-synonym-year.json"
batchSynonymFlagJson = fixtureDir </> "batch-synonym-flag.json"
batchSynonymYearCsv  = fixtureDir </> "batch-synonym-year.csv"
batchSynonymFlagCsv  = fixtureDir </> "batch-synonym-flag.csv"

-- | CSV files that cannot be read: a stray quote, an empty file, and a quote
-- that opens a cell and is never closed (at the end of the file, in the middle
-- of it, with Windows line ends, as half of a doubled quote, in the header),
-- with the control of a cell that closes at the very end of the file.
batchCsvBadQuote, batchCsvEmpty, batchCsvOpenQuoteEof, batchCsvOpenQuoteMid, batchCsvOpenQuoteCrlf
  , batchCsvOpenQuoteDoubled, batchCsvOpenQuoteHeader, batchCsvQuoteClosesAtEof :: FilePath
batchCsvBadQuote     = fixtureDir </> "batch-csv-bad-quote.csv"
batchCsvEmpty        = fixtureDir </> "batch-csv-empty.csv"
batchCsvOpenQuoteEof     = fixtureDir </> "batch-csv-open-quote-eof.csv"
batchCsvOpenQuoteMid     = fixtureDir </> "batch-csv-open-quote-mid.csv"
batchCsvOpenQuoteCrlf    = fixtureDir </> "batch-csv-open-quote-crlf.csv"
batchCsvOpenQuoteDoubled = fixtureDir </> "batch-csv-open-quote-doubled.csv"
batchCsvOpenQuoteHeader  = fixtureDir </> "batch-csv-open-quote-header.csv"
batchCsvQuoteClosesAtEof = fixtureDir </> "batch-csv-quote-closes-at-eof.csv"

-- | CSV files whose shape the reader has to get right: a file with one column
-- (where a row of one empty cell and a blank line look alike), a UTF-8
-- byte-order mark before the header, records with too few or too many cells,
-- and CRLF line ends with a quoted cell that holds a line break.
batchOneColFixture, batchOneColCsv, batchOneColSpacesCsv, batchBomCsv, batchRaggedCsv, batchCrlfCsv :: FilePath
batchOneColFixture   = fixtureDir </> "batch-onecol.l4"
batchOneColCsv       = fixtureDir </> "batch-onecol.csv"
batchOneColSpacesCsv = fixtureDir </> "batch-onecol-spaces.csv"
batchBomCsv          = fixtureDir </> "batch-bom.csv"
batchRaggedCsv       = fixtureDir </> "batch-ragged.csv"
batchCrlfCsv         = fixtureDir </> "batch-crlf.csv"

-- | A string literal holding a line break and a tab (smucclaw/l4-ide#1028).
batchLineBreakFixture, batchLineBreakJson :: FilePath
batchLineBreakFixture = fixtureDir </> "batch-string-line-break.l4"
batchLineBreakJson    = fixtureDir </> "batch-string-line-break.json"

-- | Cases that send text for a NUMBER or BOOLEAN input (@"25"@, @"false"@) or a
-- CSV cell for a STRING input, run against 'batchEligFixture' and
-- 'batchCodeFixture'.
batchDeclaredStringsJson, batchDeclaredStringsYaml, batchDeclaredStringCellsCsv, batchDeclaredBadNumberJson, batchDeclaredNumberForStringJson :: FilePath
batchDeclaredStringsJson           = fixtureDir </> "batch-declared-strings.json"
batchDeclaredStringsYaml           = fixtureDir </> "batch-declared-strings.yaml"
batchDeclaredStringCellsCsv        = fixtureDir </> "batch-declared-string-cells.csv"
batchDeclaredBadNumberJson         = fixtureDir </> "batch-declared-bad-number.json"
batchDeclaredNumberForStringJson   = fixtureDir </> "batch-declared-number-for-string.json"

-- | Decode stdout as a single JSON array (for @l4 batch --format json@).
decodeArray :: String -> IO [Value]
decodeArray sout =
  case eitherDecode (BSL8.pack sout) of
    Right (Array v)  -> pure (foldr (:) [] v)
    Right other      -> do
      expectationFailure ("Expected a JSON array, got: " ++ show other)
      error "unreachable"
    Left err         -> do
      expectationFailure ("JSON array parse failed: " ++ err ++ "\nstdout:\n" ++ sout)
      error "unreachable"

-- | Count non-blank lines (each NDJSON row is one line).
nonBlankLines :: String -> Int
nonBlankLines = length . filter (not . all (`elem` (" \t\r" :: String))) . lines

batchEscapeFixture, batchEscapeInput, batchEscapeRoundtripJson :: FilePath
batchEscapeFixture = fixtureDir </> "batch-escape.l4"
batchEscapeInput   = fixtureDir </> "batch-escape-input.json"
batchEscapeRoundtripJson = fixtureDir </> "batch-escape-roundtrip.json"

----------------------------------------------------------------------------
-- Tests
----------------------------------------------------------------------------

main :: IO ()
main = do
  bin <- locateL4Binary
  putStrLn ("Using l4 binary: " ++ bin)
  -- Sanity check fixtures exist (test suite must be run from repo root).
  for_ [ cleanFixture, evalFixture, errorFixture, garbageFixture
       , batchEscapeFixture, batchEscapeInput, batchEscapeRoundtripJson
       , evalTraceFixture ] \fp -> do
    ok <- doesFileExist fp
    unless ok $ do
      putStrLn ("Missing fixture: " ++ fp)
      putStrLn "Run this suite from the repository root (jl4/ is the working directory)."
      exitFailure
  hspec (spec bin)
  where
    for_ xs f = mapM_ f xs

spec :: FilePath -> Spec
spec bin = do
  describe "l4 --help" $ do
    it "lists every subcommand" $ do
      Output code sout _ <- runL4 bin ["--help"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("run" `isInfixOf`)
      sout `shouldSatisfy` ("check" `isInfixOf`)
      sout `shouldSatisfy` ("format" `isInfixOf`)
      sout `shouldSatisfy` ("ast" `isInfixOf`)
      sout `shouldSatisfy` ("batch" `isInfixOf`)
      sout `shouldSatisfy` ("trace" `isInfixOf`)
      sout `shouldSatisfy` ("state-graph" `isInfixOf`)

  describe "l4 run" $ do
    it "succeeds on a clean file" $
      expectOk bin ["run", cleanFixture] "Checking succeeded."

    it "emits a well-shaped JSON envelope on a clean file" $ do
      env <- jsonEnvelope bin ["run", cleanFixture, "--json"]
      objField env "ok" `shouldBe` Just (Bool True)
      objField env "diagnostics" `shouldSatisfy` (/= Nothing)
      objField env "results" `shouldSatisfy` (/= Nothing)

    it "prints evaluation results for #EVAL directives" $ do
      Output code sout _ <- runL4 bin ["run", evalFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("Evaluation[1]" `isInfixOf`)
      sout `shouldSatisfy` ("Evaluation[2]" `isInfixOf`)

    it "reports #EVAL results in JSON" $ do
      env <- jsonEnvelope bin ["run", evalFixture, "--json"]
      case objField env "results" of
        Just (Array v) -> length v `shouldBe` 2
        other          -> expectationFailure ("Expected results array, got " ++ show other)

    it "fails on a typecheck error" $
      expectFail bin ["run", errorFixture]

    it "returns ok=false in JSON on a typecheck error" $ do
      env <- jsonEnvelope bin ["run", errorFixture, "--json"]
      objField env "ok" `shouldBe` Just (Bool False)

    it "falls through from a bare positional argument (backward-compat)" $
      expectOk bin [cleanFixture] "Checking succeeded."

  describe "l4 check" $ do
    it "succeeds on a clean file" $
      expectOk bin ["check", cleanFixture] "Check succeeded."

    it "returns ok=true in JSON on a clean file" $ do
      env <- jsonEnvelope bin ["check", cleanFixture, "--json"]
      objField env "ok" `shouldBe` Just (Bool True)

    it "fails on a typecheck error" $
      expectFail bin ["check", errorFixture]

    it "returns ok=false in JSON on a typecheck error" $ do
      env <- jsonEnvelope bin ["check", errorFixture, "--json"]
      objField env "ok" `shouldBe` Just (Bool False)

    it "fails on unparseable garbage input" $ do
      Output code _ _ <- runL4 bin ["check", garbageFixture]
      code `shouldSatisfy` (/= ExitSuccess)

  describe "l4 format" $ do
    it "prints the reformatted source of a clean file to stdout" $ do
      Output code sout _ <- runL4 bin ["format", cleanFixture]
      code `shouldBe` ExitSuccess
      -- Formatter output should contain the DECIDE (exact spelling may
      -- differ from input, so we only look for the identifier).
      sout `shouldSatisfy` ("xor" `isInfixOf`)

    it "writes nothing to stdout and exits non-zero on a broken file" $ do
      Output code _ _ <- runL4 bin ["format", garbageFixture]
      code `shouldSatisfy` (/= ExitSuccess)

  describe "l4 ast" $ do
    it "dumps a parsed AST for a clean file" $ do
      Output code sout _ <- runL4 bin ["ast", cleanFixture]
      code `shouldBe` ExitSuccess
      -- The dumper uses pretty-simple; any module will start with "MkModule".
      sout `shouldSatisfy` ("MkModule" `isInfixOf`)

  describe "l4 trace" $ do
    it "refuses --format png without --output-dir" $ do
      Output code _ serr <- runL4 bin ["trace", cleanFixture, "--format", "png"]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("requires --output-dir" `isInfixOf`)

    it "refuses --format svg without --output-dir" $ do
      Output code _ serr <- runL4 bin ["trace", cleanFixture, "--format", "svg"]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("requires --output-dir" `isInfixOf`)

    it "defaults to DOT on stdout (redirect with >)" $ do
      -- trace on the eval fixture shouldn't error even without #EVALTRACE —
      -- it just produces no output but still exits 0.
      Output code _ _ <- runL4 bin ["trace", evalFixture]
      code `shouldBe` ExitSuccess

  describe "l4 state-graph" $ do
    it "fails on a file without regulative rules" $ do
      Output code _ serr <- runL4 bin ["state-graph", cleanFixture]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("regulative" `isInfixOf`)

  describe "l4 batch" $ do
    it "streams one NDJSON row per input (default format)" $ do
      Output code sout _ <- runL4 bin ["batch", batchEligFixture, "--inputs", batchDataJson]
      code `shouldBe` ExitSuccess
      nonBlankLines sout `shouldBe` 2
      sout `shouldSatisfy` ("\"status\":\"success\"" `isInfixOf`)

    it "reads a CSV cell for a NUMBER or BOOLEAN input as the number or boolean it spells" $ do
      -- If age/income stayed strings, JSONDECODE into NUMBER would fail and
      -- the rows would come back status=error; success proves the declared
      -- types were applied. (Every column here is declared, so this does not
      -- reach 'inferCsvCell'; the undeclared-column test below does.)
      Output code sout _ <-
        runL4 bin ["batch", batchEligFixture, "--inputs", batchDataCsv, "--format", "json"]
      code `shouldBe` ExitSuccess
      rows <- decodeArray sout
      length rows `shouldBe` 2
      let statuses = [ s | Object o <- rows
                         , Just (String s) <- [KeyMap.lookup (Key.fromString "status") o] ]
      statuses `shouldBe` ["success", "success"]

    it "reads a cases file that holds one object as one case" $ do
      -- Plain main answered a JSON object where it expected an array with
      -- "failed to parse inputs: ... expected Array, but encountered Object".
      Output code sout _ <- runL4 bin ["batch", batchEligFixture, "--inputs", batchSingleObjectJson]
      code `shouldBe` ExitSuccess
      nonBlankLines sout `shouldBe` 1
      sout `shouldSatisfy` ("\"status\":\"success\"" `isInfixOf`)

    it "emits a single JSON array with --format json" $ do
      Output code sout _ <-
        runL4 bin ["batch", batchEligFixture, "--inputs", batchDataJson, "--format", "json"]
      code `shouldBe` ExitSuccess
      rows <- decodeArray sout
      length rows `shouldBe` 2

    it "emits a CSV table with flattened input_* columns via --format csv" $ do
      Output code sout _ <-
        runL4 bin ["batch", batchEligFixture, "--inputs", batchDataJson, "--format", "csv"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("input_age" `isInfixOf`)
      sout `shouldSatisfy` ("status" `isInfixOf`)

    it "writes results to a file with --output" $ do
      tmp <- getTemporaryDirectory
      let outFile = tmp </> "l4-batch-out.json"
      Output code sout _ <-
        runL4 bin [ "batch", batchEligFixture, "--inputs", batchDataJson
                  , "--format", "json", "--output", outFile ]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` null                    -- nothing on stdout
      exists <- doesFileExist outFile
      exists `shouldBe` True
      contents <- readFile outFile
      rows <- decodeArray contents
      length rows `shouldBe` 2
      removeFile outFile

    it "stops at the first failing row by default (and exits non-zero)" $ do
      -- Row 2 has a non-numeric income; row 3 must NOT be processed.
      Output code sout _ <- runL4 bin ["batch", batchEligFixture, "--inputs", batchMixedJson]
      code `shouldSatisfy` (/= ExitSuccess)
      nonBlankLines sout `shouldBe` 2
      sout `shouldSatisfy` ("\"status\":\"error\"" `isInfixOf`)

    it "processes every row with --continue-on-error (still exits non-zero)" $ do
      Output code sout _ <-
        runL4 bin ["batch", batchEligFixture, "--inputs", batchMixedJson, "--continue-on-error"]
      code `shouldSatisfy` (/= ExitSuccess)
      nonBlankLines sout `shouldBe` 3

    it "validate-only reports schema mismatches without evaluating" $ do
      Output code sout _ <-
        runL4 bin [ "batch", batchEligFixture, "--inputs", batchMixedJson
                  , "--validate-only", "--continue-on-error" ]
      code `shouldSatisfy` (/= ExitSuccess)
      sout `shouldSatisfy` ("\"status\":\"invalid\"" `isInfixOf`)
      sout `shouldSatisfy` ("Type mismatch" `isInfixOf`)

    it "keeps an exponent-form CSV cell (1E5) for a STRING input as written, not a number" $ do
      -- A product/lot code like 1E5 is a valid JSON number (1e5 = 100000),
      -- but must survive as the string "1E5" against a STRING param rather
      -- than being coerced to 100000. (A STRING input is read by its declared
      -- type, so this does not reach 'inferCsvCell' either.)
      Output code sout _ <-
        runL4 bin ["batch", batchCodeFixture, "--inputs", batchExponentCsv]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("\"code\":\"1E5\"" `isInfixOf`)
      sout `shouldSatisfy` (not . ("100000" `isInfixOf`))

    -- The one place a CSV cell is still typed by how it looks ('inferCsvCell'):
    -- a column that no input declares, which the case echoes under `input`.
    -- The columns are `lot`, `flag` and `serial`; batchEligFixture declares
    -- none of them. The exponent form must stay text here too, because JSON's
    -- number grammar would otherwise turn the lot code 1E5 into 100000.
    it "types a CSV cell by how it looks when no input declares its column, and keeps 1E5 text" $ do
      Output code sout _ <-
        runL4 bin ["batch", batchEligFixture, "--inputs", batchUndeclaredColumnCsv, "--format", "json"]
      code `shouldBe` ExitSuccess
      rows <- decodeArray sout
      let cell k r = objField r "input" >>= (`objField` k)
      map (cell "lot")    rows `shouldBe` [Just (String "1E5"), Just (Number 123456)]
      map (cell "flag")   rows `shouldBe` [Just (Bool True), Just (Bool False)]
      -- 007 is not a JSON number, and a date is text
      map (cell "serial") rows `shouldBe` [Just (String "007"), Just (String "2026-10-13")]

    -- T3c (ruled, specs/todo/TYPICALLY-ONE-BEHAVIOUR-SPEC.md on unstable): a
    -- blank CSV cell is ABSENT, exactly like a column missing from the file, for
    -- every kind of input. Plain main answered an empty STRING cell with "" and
    -- a blank MAYBE STRING cell with JUST "", and an empty NUMBER cell with a
    -- decode error under status "success".
    describe "a blank CSV cell is absent, not null and not an empty string" $ do
      let blankRows args = do
            Output code sout _ <- runL4 bin (["batch"] <> args <> ["--continue-on-error"])
            pure ( code
                 , [ row | l <- map (filter (/= '\r')) (lines sout)
                         , Right row <- [eitherDecode (BSL8.pack l) :: Either String Value] ] )
          diagnosticsOf row = show (objField row "diagnostics")
          resultOfRow row = case objField row "output" of
            Just (Array outs) | (o : _) <- foldr (:) [] outs -> objField o "result"
            _ -> Nothing

      it "makes a required STRING input missing, and a MAYBE STRING input NOTHING" $ do
        (code, rows) <- blankRows [batchBlankFixture, "--inputs", batchBlankCsv]
        code `shouldSatisfy` (/= ExitSuccess)
        map (`objField` "status") rows
          `shouldBe` map (Just . String) ["error", "error", "success", "success", "success"]
        case rows of
          [empty, spaces, noNote, blankNote, note] -> do
            diagnosticsOf empty  `shouldSatisfy` ("Missing required field 'code'" `isInfixOf`)
            diagnosticsOf spaces `shouldSatisfy` ("Missing required field 'code'" `isInfixOf`)
            resultOfRow noNote    `shouldBe` Just (String "nothing")
            resultOfRow blankNote `shouldBe` Just (String "nothing")
            resultOfRow note      `shouldBe` Just (String "hello")
            -- the case as read leaves the blank cell out
            (objField noNote "input" >>= (`objField` "note")) `shouldBe` Nothing
            (objField empty "input" >>= (`objField` "code")) `shouldBe` Nothing
          other -> expectationFailure ("expected 5 rows, got " ++ show (length other))

      it "makes a required NUMBER input missing too" $ do
        (code, rows) <- blankRows [batchEligFixture, "--inputs", batchBlankIncomeCsv]
        code `shouldSatisfy` (/= ExitSuccess)
        map (`objField` "status") rows `shouldBe` map (Just . String) ["error", "error", "success"]
        map diagnosticsOf (take 2 rows) `shouldSatisfy` all ("Missing required field 'income'" `isInfixOf`)

      it "is reported by --validate-only as a missing field" $ do
        Output code sout _ <-
          runL4 bin ["batch", batchEligFixture, "--inputs", batchBlankIncomeCsv, "--validate-only", "--continue-on-error"]
        code `shouldSatisfy` (/= ExitSuccess)
        length (filter ("Missing required field: 'income'" `isInfixOf`) (lines sout)) `shouldBe` 2

    -- Ruled 2026-10-12: a blank CSV cell (empty, spaces only, or a quoted "")
    -- is absent, and `l4 batch` reads a CSV file with the reader that unstable
    -- has, not cassava's `decodeByName`, which drops every record that parses
    -- to one empty field. These are the shapes where the two readers differ.
    -- Each of the first four fails on the `decodeByName` reader.
    describe "the CSV reader" $ do
      let csvRowsOf args = do
            Output code sout _ <- runL4 bin (["batch"] <> args <> ["--continue-on-error"])
            pure ( code
                 , sout
                 , [ row | l <- map (filter (/= '\r')) (lines sout)
                         , Right row <- [eitherDecode (BSL8.pack l) :: Either String Value] ] )
          statusesOf = map (`objField` "status")
          diagnosticsOf row = show (objField row "diagnostics")
          inputOf row k = objField row "input" >>= (`objField` k)

      -- A line holding only `""` and a blank line both parse to one empty
      -- field, and `decodeByName` drops both: three rows in, two rows out, exit
      -- 0. The `""` row is a row whose one cell is empty, so absent (T3c), and
      -- the required input is missing.
      it "reads a one-column row whose only cell is \"\" as a row, with its input missing" $ do
        (code, _, rows) <- csvRowsOf [batchOneColFixture, "--inputs", batchOneColCsv]
        code `shouldSatisfy` (/= ExitSuccess)
        statusesOf rows `shouldBe` map (Just . String) ["success", "error", "success"]
        map (`inputOf` "name") rows `shouldBe` [Just (String "alice"), Nothing, Just (String "bob")]
        diagnosticsOf (rows !! 1) `shouldSatisfy` ("Missing required field 'name'" `isInfixOf`)

      -- An unquoted line of spaces is not a row, any more than a blank line is;
      -- `decodeByName` made it a row of one blank cell, so an error. Decided by
      -- Claude overnight 2026-10-02, pending Meng's review (not ruled); the
      -- alternative named in the spec is that such a line is a row whose cell
      -- is absent.
      it "does not read a line of spaces, or a blank line, as a row" $ do
        (code, _, rows) <- csvRowsOf [batchOneColFixture, "--inputs", batchOneColSpacesCsv]
        code `shouldBe` ExitSuccess
        statusesOf rows `shouldBe` map (Just . String) ["success", "success"]
        map (`inputOf` "name") rows `shouldBe` [Just (String "alice"), Just (String "bob")]

      -- Excel's "CSV UTF-8" export starts with a byte-order mark, which
      -- `decodeByName` left in the first column's name: the input `age` was then
      -- missing from every row.
      it "reads a CSV that starts with a UTF-8 byte-order mark" $ do
        (code, _, rows) <- csvRowsOf [batchEligFixture, "--inputs", batchBomCsv]
        code `shouldBe` ExitSuccess
        statusesOf rows `shouldBe` [Just (String "success")]
        map (`inputOf` "age") rows `shouldBe` [Just (Number 25)]

      -- Decided by Claude overnight 2026-10-02, pending Meng's review
      -- (specs/todo/TYPICALLY-ONE-BEHAVIOUR-SPEC.md on unstable, "Decided by
      -- Claude overnight"): a record with fewer or more cells than the header is
      -- refused, naming its line. A short record used to leave its last input
      -- missing, and a long one lost its extra cells and was a success. The
      -- line of a tab and a space is blank, so it is skipped and still counted.
      it "refuses a record whose cell count is not the header's, naming its line" $ do
        (code, sout, rows) <- csvRowsOf [batchEligFixture, "--inputs", batchRaggedCsv]
        code `shouldSatisfy` (/= ExitSuccess)
        statusesOf rows `shouldBe` map (Just . String) ["success", "error", "error"]
        -- the message says what the reader would otherwise have done, which on
        -- main is to leave the missing cell out (there are no defaults to take)
        let reason = ", so the row is refused: a cell missing from a short row would otherwise"
                     <> " be read as left out (NOTHING for a MAYBE input, a missing field for any"
                     <> " other), and a long row's extra cells would be dropped"
        sout `shouldSatisfy` (("Line 3 has 2 cells, but the header has 3" <> reason) `isInfixOf`)
        sout `shouldSatisfy` (("Line 5 has 4 cells, but the header has 3" <> reason) `isInfixOf`)
        Output vcode vout _ <-
          runL4 bin ["batch", batchEligFixture, "--inputs", batchRaggedCsv, "--validate-only", "--continue-on-error"]
        vcode `shouldSatisfy` (/= ExitSuccess)
        vout `shouldSatisfy` ("Line 3 has 2 cells" `isInfixOf`)

      -- Not a change: the new reader has to keep reading what cassava read. CRLF
      -- line ends are not part of a cell, and a quoted cell may hold a line break.
      -- The rule `echoCode` returns the cell, so the line break must also survive
      -- the generated wrapper, which needs the exact quoting this change adds
      -- (see the round-trip test further down).
      it "reads CRLF line ends, and a quoted cell holding a line break, as one row each" $ do
        (code, _, rows) <- csvRowsOf [batchCodeFixture, "--inputs", batchCrlfCsv]
        code `shouldBe` ExitSuccess
        map (`inputOf` "code") rows
          `shouldBe` [Just (String "plain"), Just (String "line one\nline two")]
        let resultOf row = case objField row "output" of
              Just (Array outs) | (o : _) <- foldr (:) [] outs -> objField o "result"
              _ -> Nothing
        map resultOf rows
          `shouldBe` [Just (String "plain"), Just (String "line one\nline two")]

    -- A CSV file that cannot be read stops the command before any case runs.
    -- It used to say only what the parser was called (`endOfInput`, `13: not
    -- enough input`); cassava's own reader, before `csvRows`, named the input
    -- it stopped at.
    it "names the line of a CSV file it cannot read" $ do
      Output code sout _ <- runL4 bin ["batch", batchCodeFixture, "--inputs", batchCsvBadQuote]
      code `shouldSatisfy` (/= ExitSuccess)
      -- the stray quote is on line 2, after `ab`
      sout `shouldSatisfy` ("line 2 of the CSV file is not valid CSV, near `\"c`" `isInfixOf`)
      sout `shouldNotSatisfy` ("endOfInput" `isInfixOf`)

    it "says that an empty CSV file is empty" $ do
      Output code sout _ <- runL4 bin ["batch", batchCodeFixture, "--inputs", batchCsvEmpty]
      code `shouldSatisfy` (/= ExitSuccess)
      sout `shouldSatisfy` ("the CSV file is empty" `isInfixOf`)
      sout `shouldNotSatisfy` ("not enough input" `isInfixOf`)

    -- A quote that opens a cell and is never closed. cassava's reader of a
    -- quoted cell takes everything to the end of the file and drops the last
    -- byte, taking it for the closing quote: `"abc` was the text `ab` with
    -- status success, and in the middle of a file the cell swallowed every row
    -- after it. Each is refused, at the line where the quote opens.
    describe "a quote that opens a CSV cell and is never closed" $ do
      let refusedAt n file = do
            Output code sout _ <- runL4 bin ["batch", batchCodeFixture, "--inputs", file]
            code `shouldSatisfy` (/= ExitSuccess)
            sout `shouldSatisfy` (("line " <> show (n :: Int) <> " of the CSV file is not valid CSV: a quote that opens a cell there is never closed") `isInfixOf`)
            -- and no row is run
            sout `shouldNotSatisfy` ("\"status\"" `isInfixOf`)

      it "is refused at the end of the file, naming the line" $ refusedAt 2 batchCsvOpenQuoteEof
      it "is refused in the middle of a file, rather than taking the rows after it" $ refusedAt 2 batchCsvOpenQuoteMid
      it "is refused in a file with Windows line ends" $ refusedAt 2 batchCsvOpenQuoteCrlf
      it "is refused when the last quote is half of a doubled one" $ refusedAt 2 batchCsvOpenQuoteDoubled
      it "is refused in the header" $ refusedAt 1 batchCsvOpenQuoteHeader

      -- The control: a cell that closes at the very end of the file, with no
      -- line end after it, is a cell, so the check cannot be refusing every
      -- file that ends in a quote.
      it "does not refuse a cell that closes at the end of the file" $ do
        Output code sout _ <- runL4 bin ["batch", batchCodeFixture, "--inputs", batchCsvQuoteClosesAtEof]
        code `shouldBe` ExitSuccess
        sout `shouldSatisfy` ("\"result\":\"abc\"" `isInfixOf`)

    it "keeps a line break inside a string literal as it is written" $ do
      -- batch runs the re-printed module; before smucclaw/l4-ide#1028 the newline came back
      -- followed by the body's indentation ("line\\n  next"), status success.
      Output code sout _ <- runL4 bin ["batch", batchLineBreakFixture, "--inputs", batchLineBreakJson]
      code `shouldBe` ExitSuccess
      case filter (not . all (`elem` (" \t\r" :: String))) (lines sout) of
        [broken, tabbed] -> do
          broken `shouldSatisfy` ("\"result\":\"line\\nnext\"" `isInfixOf`)
          tabbed `shouldSatisfy` ("\"result\":\"tab\\there\"" `isInfixOf`)
        rows -> expectationFailure ("expected 2 rows, got " ++ show (length rows) ++ ":\n" ++ sout)

    it "validate-only type-checks MAYBE primitive params" $ do
      -- premium is declared `A MAYBE NUMBER`; a BOOLEAN value must be flagged
      -- as a type mismatch. Before unwrapping MAYBE on the AST this silently
      -- passed as valid.
      Output code sout _ <-
        runL4 bin [ "batch", batchMaybeFixture, "--inputs", batchMaybeBadJson
                  , "--validate-only" ]
      code `shouldSatisfy` (/= ExitSuccess)
      sout `shouldSatisfy` ("\"status\":\"invalid\"" `isInfixOf`)
      sout `shouldSatisfy` ("Type mismatch for field 'premium'" `isInfixOf`)
      sout `shouldSatisfy` ("expected NUMBER" `isInfixOf`)

    -- Regression tests for the generated wrapper's string quoting.
    it "escapes payloads with backslashes, quotes and control chars (no lexer break)" $ do
      -- The payload holds a Windows path, embedded quotes, a newline, a tab,
      -- an apostrophe, braces and a percent sign. This pins the LOUD half of
      -- the escaping only: `echoFixed` ignores its payload, so a quote-only
      -- escaper fails here just because an unescaped `"` ends the wrapper's
      -- string literal early and the wrapper no longer lexes. A backslash, a
      -- tab or a line break does not break the lexing, and is pinned by the
      -- next test. (`l4 batch` runs no shell, so no shell metacharacter is
      -- involved.)
      env <- jsonEnvelope bin ["batch", batchEscapeFixture, "--inputs", batchEscapeInput]
      objField env "status" `shouldBe` Just (String "success")

    -- The silent half. With a quote-only escaper a backslash reaches the lexer
    -- unescaped, which reads it as the start of an escape of its own, so the
    -- rule is handed JSON that is not the JSON that was sent, and the row is
    -- still a success. Measured on plain main: `\u0041` (a backslash, then
    -- u0041) comes back as `A`, `\\n` (two backslashes and an n) as a
    -- backslash and an n, and a Windows path, a tab and a line break as null.
    -- `echoCode` returns its input, so a payload the wrapper changed shows as a
    -- result that is not the one sent.
    it "hands every payload to the rule and back unchanged: backslashes, tabs, line breaks, escape-looking text" $ do
      Output code sout _ <-
        runL4 bin ["batch", batchCodeFixture, "--inputs", batchEscapeRoundtripJson, "--continue-on-error"]
      let rows = [ row | l <- map (filter (/= '\r')) (lines sout)
                       , Right row <- [eitherDecode (BSL8.pack l) :: Either String Value] ]
          sent = [ objField r "input" >>= (`objField` "code") | r <- rows ]
          result r = case objField r "output" of
            Just (Array outs) | (o : _) <- foldr (:) [] outs -> objField o "result"
            _ -> Nothing
      code `shouldBe` ExitSuccess
      map (`objField` "status") rows `shouldBe` replicate 6 (Just (String "success"))
      sent `shouldBe` map (Just . String . T.pack)
        [ "C:\\Users\\x", "back\\slash", "tab\there", "line\nbreak", "\\u0041", "\\\\n" ]
      map result rows `shouldBe` sent

    -- A value is read by the type its input declares. Main's `coerceInputTypes`
    -- (f6ebc282e) did that; #47's `inferCsvCell` types a CSV cell by how it
    -- looks and knows nothing of JSON or YAML, so each of these answered with
    -- status "error" without the declared-type step.
    describe "reads a value by the type its input declares" $ do
      let rowsOf args = do
            Output code sout _ <- runL4 bin (["batch"] <> args <> ["--continue-on-error"])
            pure ( code
                 , sout
                 , [ row | l <- map (filter (/= '\r')) (lines sout)
                         , Right row <- [eitherDecode (BSL8.pack l) :: Either String Value] ] )
          resultOf row = case objField row "output" of
            Just (Array outs) | (o : _) <- foldr (:) [] outs -> objField o "result"
            _ -> Nothing
          statusAndResult row = (objField row "status", resultOf row)
          succeeded r = (Just (String "success"), Just r)

      it "reads text for a NUMBER or BOOLEAN input as a number or a boolean, in JSON" $ do
        (code, sout, rows) <- rowsOf [batchEligFixture, "--inputs", batchDeclaredStringsJson]
        code `shouldBe` ExitSuccess
        map statusAndResult rows `shouldBe` [succeeded (Bool True), succeeded (Bool False)]
        -- the line shows the case as the inputs declare it
        sout `shouldSatisfy` ("\"age\":25" `isInfixOf`)

      it "reads text for a NUMBER or BOOLEAN input as a number or a boolean, in YAML" $ do
        (code, _, rows) <- rowsOf [batchEligFixture, "--inputs", batchDeclaredStringsYaml]
        code `shouldBe` ExitSuccess
        map statusAndResult rows `shouldBe` [succeeded (Bool True), succeeded (Bool False)]

      it "validates a case that sends text for a NUMBER or BOOLEAN input" $ do
        Output code sout _ <-
          runL4 bin ["batch", batchEligFixture, "--inputs", batchDeclaredStringsJson, "--validate-only"]
        code `shouldBe` ExitSuccess
        sout `shouldNotSatisfy` ("\"status\":\"invalid\"" `isInfixOf`)

      it "keeps a CSV cell for a STRING input as the text written" $ do
        -- 123456 and 1.50 used to arrive as numbers and be refused; 018956 and
        -- 1e3 already stayed text
        (code, _, rows) <- rowsOf [batchCodeFixture, "--inputs", batchDeclaredStringCellsCsv]
        code `shouldBe` ExitSuccess
        map statusAndResult rows
          `shouldBe` map (succeeded . String) ["123456", "018956", "1.50", "1e3"]

      -- JSON and YAML carry their own types, so a number sent for a STRING
      -- input is an error.
      it "still refuses a JSON number for a STRING input" $ do
        (code, _, rows) <- rowsOf [batchCodeFixture, "--inputs", batchDeclaredNumberForStringJson]
        code `shouldSatisfy` (/= ExitSuccess)
        map (`objField` "status") rows `shouldBe` [Just (String "error")]

      it "leaves text that is not a number alone, so the error names the value" $ do
        -- `age` is readable and `income` is not. The error is about `lots`.
        (code, _, rows) <- rowsOf [batchEligFixture, "--inputs", batchDeclaredBadNumberJson]
        code `shouldSatisfy` (/= ExitSuccess)
        case rows of
          [row] -> do
            objField row "status" `shouldBe` Just (String "error")
            let diagnostics = show (objField row "diagnostics")
            diagnostics `shouldSatisfy` ("lots" `isInfixOf`)
            diagnostics `shouldNotSatisfy` ("25" `isInfixOf`)
          other -> expectationFailure ("expected 1 row, got " ++ show (length other))

      -- Only a NUMBER or a BOOLEAN reads a CSV cell as anything but its text.
      -- A choice named `True`, or a DATE written without dashes, was typed by
      -- how it looks and then refused: `True` became JSON true ("Could not
      -- decode true as Answer"), and 20261013 a number.
      let declaredTextRows entry csv = rowsOf [batchDeclaredText, "-e", entry, "--inputs", csv]
      it "reads a CSV cell for a choice input as the name written" $ do
        (code, _, rows) <- declaredTextRows "echo answer" batchDeclaredTextAnswers
        code `shouldBe` ExitSuccess
        map statusAndResult rows `shouldBe` map (succeeded . String) ["yes", "no", "dunno"]

      it "reads a CSV cell for a MAYBE choice input as the name written, and a blank one as left out" $ do
        -- the second row is a quoted "", a cell that is blank (T3c)
        (code, _, rows) <- declaredTextRows "echo optional answer" batchDeclaredTextOptional
        code `shouldBe` ExitSuccess
        map statusAndResult rows `shouldBe` map (succeeded . String) ["yes", "none", "dunno"]

      it "reads a CSV cell for a DATE input as text, so a bad date is reported as one" $ do
        (code, _, rows) <- declaredTextRows "echo date" batchDeclaredTextDates
        code `shouldSatisfy` (/= ExitSuccess)
        case rows of
          [good, bad] -> do
            statusAndResult good `shouldBe` succeeded (String "2026-10-13")
            objField bad "status" `shouldBe` Just (String "error")
            show (objField bad "diagnostics") `shouldSatisfy` ("Could not parse date string '20261013'" `isInfixOf`)
          other -> expectationFailure ("expected 2 rows, got " ++ show (length other))

      -- Not a regression test: it passes on a build that types every cell by
      -- its look. It pins the way a synonym is still read as what it stands for.
      it "still reads a CSV cell for a synonym of NUMBER or BOOLEAN as one" $ do
        (code, _, rows) <- declaredTextRows "echo year" batchDeclaredTextSynonyms
        code `shouldBe` ExitSuccess
        map statusAndResult rows `shouldBe` [succeeded (Number 2026)]

      -- A MAYBE input is read by the type it wraps, so "25" is 25 for a MAYBE
      -- NUMBER. Plain main answered it with a decode error (an object holding
      -- the message) under status "success"; nothing tested the new reading.
      it "reads text for a MAYBE NUMBER input as the number it spells, and refuses text that is not one" $ do
        (code, _, rows) <- rowsOf [batchMaybeFixture, "--inputs", batchMaybeTextJson]
        code `shouldSatisfy` (/= ExitSuccess)
        map (`objField` "status") rows `shouldBe` map (Just . String) ["success", "error", "success"]
        case rows of
          [text, notANumber, number] -> do
            resultOf text   `shouldBe` Just (Number 25)
            resultOf number `shouldBe` Just (Number 25)
            show (objField notANumber "diagnostics") `shouldSatisfy` ("abc" `isInfixOf`)
          other -> expectationFailure ("expected 3 rows, got " ++ show (length other))

      -- An input declared through a synonym is the type the synonym stands for
      -- (DECLARE Year IS A NUMBER), and --validate-only has to judge it so:
      -- it used to look at the name `Year` and judge nothing, so text that is
      -- no number, or a number for a flag, was `valid` and then refused when
      -- the case was run. The plain exports in the fixture are the control.
      describe "an input declared through a synonym" $ do
        let run extra entry file = rowsOf ([batchSynonym, "-e", entry, "--inputs", file] <> extra)
            -- one word for how a case went, run or validated
            outcome row = case objField row "status" of
              Just (String st) | st `elem` ["success", "valid"] -> "accepted"
              _                                                  -> "refused" :: String
            shape row = (outcome row, objField row "diagnostics", objField row "errors")

        it "refuses text that is no number, as for a NUMBER, in JSON and in CSV" $ do
          forM_ [batchSynonymYearJson, batchSynonymYearCsv] \file -> do
            (_, _, plain)   <- run [] "plain number" file
            (_, _, through) <- run [] "next year" file
            map shape through `shouldBe` map shape plain
            -- and the first row, the text `abc`, is the one refused, with the
            -- message the plain NUMBER gets
            take 1 (map outcome through) `shouldBe` ["refused"]
            show (map (`objField` "diagnostics") (take 1 through)) `shouldSatisfy` ("Expected JSON number but got: String" `isInfixOf`)

        it "refuses text that is no boolean, and a number, as for a BOOLEAN, in JSON and in CSV" $ do
          forM_ [batchSynonymFlagJson, batchSynonymFlagCsv] \file -> do
            (_, _, plain)   <- run [] "plain flag" file
            (_, _, through) <- run [] "flip flag" file
            map shape through `shouldBe` map shape plain
            take 1 (map outcome through) `shouldBe` ["refused"]

        it "judges a synonym's value under --validate-only as it judges the plain type's" $ do
          forM_ [ ("next year", "plain number", batchSynonymYearJson)
                , ("flip flag", "plain flag", batchSynonymFlagJson) ] \(entry, control, file) -> do
            (_, _, plain)   <- run ["--validate-only"] control file
            (_, _, through) <- run ["--validate-only"] entry file
            map shape through `shouldBe` map shape plain
            -- the mismatch is named, as for the plain type
            show (map (`objField` "errors") through) `shouldSatisfy` ("Type mismatch for field" `isInfixOf`)

        it "validates what it would run: a case is valid exactly when it is accepted" $ do
          forM_ [ ("next year", batchSynonymYearJson), ("flip flag", batchSynonymFlagJson)
                , ("maybe year", batchSynonymYearJson), ("year maybe", batchSynonymYearJson) ]
            \(entry, file) -> do
              (_, _, validated) <- run ["--validate-only"] entry file
              (_, _, ran)       <- run [] entry file
              (entry, map outcome validated) `shouldBe` (entry, map outcome ran)

  -- A step of a trace is printed as source, and a string literal in source is
  -- spelled with escapes: a line break as \n, a tab as \t. #595 made the printer
  -- do that so that `l4 batch` keeps a string that holds a line break; it also
  -- changed every other surface that prints a step: the trace `l4 trace`
  -- reports, and the `exampleCode` of the jl4-service reasoning tree (pinned in
  -- jl4-service-test). Before it, a step broke across lines inside the literal.
  -- The VALUE a trace ends in is not source and keeps its line break. `l4 run`
  -- prints no trace steps on main ("no trace captured"), so it is not pinned.
  -- Ruled 2026-10-12: printed string literals stay escaped on every surface,
  -- and every surface it reaches is listed in the PR body.
  describe "a string literal in a trace step" $ do
    it "is spelled as source in the trace `l4 trace` reports" $ do
      Output code _ serr <- runL4 bin ["trace", evalTraceLineBreakFixture]
      code `shouldBe` ExitSuccess
      let err = map (filter (/= '\r')) (lines serr)
          escapedStep = "IF (x GREATER THAN 0) THEN \"line\\nnext\" ELSE \"tab\\there\""
      err `shouldSatisfy` any (escapedStep `isInfixOf`)
      -- no step ends inside a literal
      err `shouldNotSatisfy` any ("THEN \"line" `isSuffixOf`)

  describe "l4 trace (output path safety)" $ do
    it "never runs a shell for the output path, so metacharacters can't inject" $ do
      -- Render into a directory whose *name* would execute `touch <sentinel>`
      -- if the path were ever handed to a shell. With a direct `proc` call it
      -- is just a literal (if unusual) directory name. The sentinel must not
      -- appear regardless of whether Graphviz's `dot` is installed.
      -- The sentinel is relative, run from a scratch directory: an absolute
      -- Windows path would put a drive colon into the directory name.
      tmp <- getTemporaryDirectory
      let work     = tmp </> "l4-trace-injection"
          sentinel = "l4-trace-injection-sentinel"
          evilDir  = "l4trace$(touch " ++ sentinel ++ ").d"
      removePathForcibly work
      createDirectoryIfMissing True (work </> evilDir)
      fixture <- makeAbsolute evalTraceFixture
      _ <- runL4In (Just work) Nothing bin
        ["trace", fixture, "--format", "png", "--output-dir", evilDir]
      ranShell <- doesFileExist (work </> sentinel)
      removePathForcibly work
      ranShell `shouldBe` False

    it "writes trace output into a directory whose path contains a space" $ do
      -- The `.dot` branch needs no external tools; it exercises the same
      -- outDir path-join the png/svg branches feed to `dot`, proving spaces
      -- survive instead of being word-split.
      tmp <- getTemporaryDirectory
      let outDir = tmp </> "l4 trace out"   -- note the space
      removePathForcibly outDir
      Output code _ _ <- runL4 bin ["trace", evalTraceFixture, "--format", "dot", "--output-dir", outDir]
      code `shouldBe` ExitSuccess
      wrote <- doesFileExist (outDir </> "evaltrace-eval1.dot")
      removePathForcibly outDir
      wrote `shouldBe` True

    it "runs no shell for --output-dir, and renders or fails with a diagnostic" $ do
      -- `;` ends a shell command, so this name, handed to a shell, runs
      -- `touch PWNED` in the working directory. The marker is relative, so
      -- unlike the case above the name has no drive colon and no separator,
      -- and is a legal directory on Windows as well.
      tmp <- getTemporaryDirectory
      let work    = tmp </> "l4-trace-metachar"
          evilDir = "o;touch PWNED;x"
      removePathForcibly work
      createDirectoryIfMissing True work
      fixture <- makeAbsolute evalTraceFixture
      Output code _ serr <- runL4In (Just work) Nothing bin
        ["trace", fixture, "--format", "png", "--output-dir", evilDir]
      ranShell <- doesFileExist (work </> "PWNED")
      rendered <- doesFileExist (work </> evilDir </> "evaltrace-eval1.png")
      removePathForcibly work
      ranShell `shouldBe` False
      case code of
        ExitSuccess   -> rendered `shouldBe` True
        ExitFailure _ -> serr `shouldSatisfy` ("Error: " `isInfixOf`)

    it "hands dot an output dir beginning with '-' as a path, not an option" $ do
      -- dot reads any argument starting with `-` as an option, and has no
      -- `--` to stop that. Given `-out/evaltrace-eval1.dot` it reads
      -- `-o ut/...`, takes the graph from stdin instead, and exits 0 having
      -- written nothing, so `l4 trace` reported an empty SVG as generated.
      -- Only a real `dot` shows this, so without one the test is pending.
      mDot <- findExecutable "dot"
      case mDot of
        Nothing -> pendingWith "Graphviz `dot` is not on PATH"
        Just _ -> do
          tmp <- getTemporaryDirectory
          let work    = tmp </> "l4-trace-dash-path"
              svgFile = work </> "-out" </> "evaltrace-eval1.svg"
          removePathForcibly work
          createDirectoryIfMissing True work
          fixture <- makeAbsolute evalTraceFixture
          Output code _ _ <- runL4In (Just work) Nothing bin
            ["trace", fixture, "--format", "svg", "--output-dir=-out"]
          wrote <- doesFileExist svgFile
          svg <- if wrote
            then T.unpack . TE.decodeUtf8Lenient <$> BS.readFile svgFile
            else pure ""
          removePathForcibly work
          code `shouldBe` ExitSuccess
          svg `shouldSatisfy` ("<svg" `isInfixOf`)

  -- `l4 batch` re-prints the module and evaluates the printed text, so these
  -- check the printer's brackets as much as batch. Each operand nests inside an
  -- AND, and each expected answer is the fixture's own #EVAL under `l4 run`.
  -- With the printer as it was, batch answered `true` to every one of them,
  -- with "status":"success" and no diagnostic.
  describe "l4 batch keeps the grouping the rule wrote" $ do
    let bracket = fixtureDir </> "batch-bracket.l4"
        rows f  = fixtureDir </> ("batch-bracket-" ++ f ++ ".json")
    it "brackets an OR inside an AND" $
      batchAnswer bin bracket (rows "tff") "or under and" `shouldReturn` Bool False
    it "brackets a NOT inside an AND" $
      batchAnswer bin bracket (rows "tff") "not under and" `shouldReturn` Bool False
    it "brackets an IMPLIES inside an AND" $
      batchAnswer bin bracket (rows "fff") "implies under and" `shouldReturn` Bool False
    it "brackets an IF inside an AND" $
      batchAnswer bin bracket (rows "ttf") "if under and" `shouldReturn` Bool False
    it "brackets a function call inside an AND" $
      batchAnswer bin bracket (rows "fff") "call under and" `shouldReturn` Bool False

  -- `l4 batch` re-prints the module and evaluates the printed text, so these
  -- check the printer as much as batch. Each expected value is what `l4 run`
  -- gives on the fixture's own #EVAL. On build 90 the first three returned the
  -- opposite answer with "status":"success", and the division failed to
  -- re-parse (`a DIVIDED b`).
  describe "l4 batch agrees with l4 run" $ do
    let grouping = fixtureDir </> "batch-grouping.l4"
        rows f   = fixtureDir </> ("batch-grouping-" ++ f ++ ".json")
    it "keeps the brackets on an OR inside an AND" $
      batchAnswer bin grouping (rows "tff") "or under and" `shouldReturn` Bool False
    it "keeps the brackets on a NOT inside an OR" $
      batchAnswer bin grouping (rows "ttf") "not under or" `shouldReturn` Bool True
    it "keeps the brackets on an IMPLIES inside an AND" $
      batchAnswer bin grouping (rows "fff") "implies under and" `shouldReturn` Bool False
    it "evaluates an exported division" $
      batchAnswer bin (fixtureDir </> "batch-division.l4") (fixtureDir </> "batch-division.json") "divided"
        `shouldReturn` Number 2

-- | Run one row through @l4 batch@ and return its result, failing the test
-- unless the row's status is @success@.
batchAnswer :: FilePath -> FilePath -> FilePath -> String -> IO Value
batchAnswer bin file inputs entry = do
  Output code sout serr <- runL4 bin ["batch", file, "-i", inputs, "-e", entry]
  unless (code == ExitSuccess) $
    expectationFailure ("l4 batch exited " ++ show code ++ "\nstdout:\n" ++ sout ++ "\nstderr:\n" ++ serr)
  row <- case lines sout of
    (l : _) -> either (\err -> expectationFailure ("NDJSON parse failed: " ++ err ++ "\n" ++ l) >> error "unreachable")
                      pure (eitherDecode (BSL8.pack l))
    []      -> expectationFailure "l4 batch printed no rows" >> error "unreachable"
  objField row "status" `shouldBe` Just (String "success")
  case objField row "output" of
    Just (Array outs) | (o : _) <- foldr (:) [] outs, Just r <- objField o "result" -> pure r
    other -> expectationFailure ("no result in batch output: " ++ show other) >> error "unreachable"
