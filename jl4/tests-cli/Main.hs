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

import Control.Monad (unless, when)
import Data.List (isInfixOf)
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
  , getTemporaryDirectory
  , removeFile
  , removePathForcibly
  )
import System.Environment (getEnvironment, lookupEnv)
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
runL4 = runL4WithEnv Nothing

-- | Like 'runL4', but run the child process with an explicit environment.
--
-- @Nothing@ inherits the parent environment (the default). @Just env@ replaces
-- it wholesale, which lets a test force a particular library-resolution regime
-- (e.g. dropping @JL4_LIBRARY_PATH@ to exercise the embedded-library fallback)
-- regardless of what CI happens to export into the parent process.
runL4WithEnv :: Maybe [(String, String)] -> FilePath -> [String] -> IO Output
runL4WithEnv mEnv bin args = do
  let cp = (proc bin args)
        { std_in  = CreatePipe
        , std_out = CreatePipe
        , std_err = CreatePipe
        , env     = mEnv
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

-- | Run l4 with library resolution forced onto the embedded-library fallback.
--
-- We drop @JL4_LIBRARY_PATH@ (so 'resolveLibraryFromFilesystem' reports
-- @hasExplicitPath = False@ and the resolver is *allowed* to fall back to the
-- built-in embedded libraries) and point @XDG_DATA_HOME@ at a fresh empty
-- directory (so no user-level @~/.local/share/jl4/libraries@ store on the
-- runner masks the embedded path). This is the exact regime issue #906 is
-- about — CI normally exports @JL4_LIBRARY_PATH@, which hides it.
runL4EmbeddedOnly :: FilePath -> [String] -> IO Output
runL4EmbeddedOnly bin args = do
  parentEnv <- getEnvironment
  tmp <- getTemporaryDirectory
  let emptyXdg = tmp </> "l4-embedded-only-xdg"
  createDirectoryIfMissing True emptyXdg
  let childEnv =
        ("XDG_DATA_HOME", emptyXdg)
          : filter (\(k, _) -> k /= "JL4_LIBRARY_PATH" && k /= "XDG_DATA_HOME")
                   parentEnv
  runL4WithEnv (Just childEnv) bin args

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

-- | Assert the CLI exits 0 and its stdout exactly matches a committed golden
-- file. Used for the OpenFisca backend, whose emit is fully deterministic.
expectGolden :: FilePath -> [String] -> FilePath -> IO ()
expectGolden bin args goldenPath = do
  Output code sout serr <- runL4 bin args
  goldenBytes <- BS.readFile goldenPath
  let golden = T.unpack (TE.decodeUtf8Lenient goldenBytes)
  case code of
    ExitSuccess ->
      unless (sout == golden) $
        expectationFailure $
          "Generated output does not match golden " ++ goldenPath
          ++ "\n(to update: l4 " ++ unwords args ++ " -o " ++ goldenPath ++ ")"
          ++ "\n--- got ---\n" ++ sout
          ++ "\n--- golden ---\n" ++ golden
    ExitFailure n -> expectationFailure $
      "Expected success but exited " ++ show n ++ "\n--- stderr ---\n" ++ serr

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

breachTraceFixture, breachInputsFixture :: FilePath
breachTraceFixture  = fixtureDir </> "breach-trace.l4"
breachInputsFixture = fixtureDir </> "breach-inputs.json"

batchEligFixture, batchDataJson, batchDataCsv, batchMixedJson :: FilePath
batchEligFixture = fixtureDir </> "batch-elig.l4"
batchDataJson    = fixtureDir </> "batch-data.json"
batchDataCsv     = fixtureDir </> "batch-data.csv"
batchMixedJson   = fixtureDir </> "batch-mixed.json"

batchCodeFixture, batchExponentCsv, batchMaybeFixture, batchMaybeBadJson :: FilePath
batchCodeFixture  = fixtureDir </> "batch-code.l4"
batchExponentCsv  = fixtureDir </> "batch-exponent.csv"
batchMaybeFixture = fixtureDir </> "batch-maybe.l4"
batchMaybeBadJson = fixtureDir </> "batch-maybe-bad.json"

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

batchEscapeFixture, batchEscapeInput, evalTraceFixture :: FilePath
batchEscapeFixture = fixtureDir </> "batch-escape.l4"
batchEscapeInput   = fixtureDir </> "batch-escape-input.json"
evalTraceFixture   = fixtureDir </> "evaltrace.l4"

-- Import-cycle fixtures (entry points of small multi-file rings) and a clean
-- multi-file import used as a guard against the cycle check over-firing.
cycle3Entry, cycle2Entry, selfImportEntry, cleanImportEntry :: FilePath
cycle3Entry      = fixtureDir </> "cycle3"     </> "cyca.l4"
cycle2Entry      = fixtureDir </> "cycle2"     </> "dua.l4"
selfImportEntry  = fixtureDir </> "selfimport" </> "solo.l4"
cleanImportEntry = fixtureDir </> "imports-ok" </> "main.l4"

-- Diamond over the embedded-library fallback (issue #906): main imports two
-- embedded siblings that share the embedded 'daydate' bottom.
embeddedDiamondEntry :: FilePath
embeddedDiamondEntry = fixtureDir </> "embedded-diamond" </> "main.l4"

----------------------------------------------------------------------------
-- Tests
----------------------------------------------------------------------------

main :: IO ()
main = do
  bin <- locateL4Binary
  putStrLn ("Using l4 binary: " ++ bin)
  -- Sanity check fixtures exist (test suite must be run from repo root).
  for_ [ cleanFixture, evalFixture, errorFixture, garbageFixture
       , breachTraceFixture, breachInputsFixture
       , batchEligFixture, batchDataJson, batchDataCsv, batchMixedJson
       , batchCodeFixture, batchExponentCsv, batchMaybeFixture, batchMaybeBadJson
       , batchEscapeFixture, batchEscapeInput, evalTraceFixture
       , cycle3Entry, cycle2Entry, selfImportEntry, cleanImportEntry
       , embeddedDiamondEntry ] \fp -> do
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
      sout `shouldSatisfy` ("openfisca" `isInfixOf`)

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
    it "serializes a #TRACE breach with correctly-labeled fields" $ do
      -- exit 0 proves the #TRACE AT/WITH pretty-printer round-trip: batch
      -- re-prints the module and re-parses it once per input row.
      Output code sout serr <- runL4 bin
        ["batch", breachTraceFixture, "--inputs", breachInputsFixture]
      code `shouldBe` ExitSuccess
      -- DeadlineMissed labels must follow the constructor slots:
      --   event party/action/timestamp, obligated party, obligation action,
      --   deadline (see L4.Evaluate.ValueLazyJSON).
      let expectedFragments =
            [ "\"type\":\"deadline_missed\""
            , "\"eventParty\":\"Bob\""
            , "\"eventAction\":\"ping\""
            , "\"timestamp\":15"
            , "\"obligatedParty\":\"Alice\""
            , "\"obligationAction\":\"MUST pay 100\""
            , "\"deadline\":10"
            ]
      for_ expectedFragments \frag ->
        unless (frag `isInfixOf` sout) $
          expectationFailure $
            "Expected batch stdout to contain " ++ show frag
            ++ "\n--- stdout ---\n" ++ sout
            ++ "\n--- stderr ---\n" ++ serr
      -- The old mislabeled fields and the derived-Show AST blob must be gone.
      let forbiddenFragments = ["\"now\":", "\"elapsed\":", "\"limit\":", "MkAction"]
      for_ forbiddenFragments \frag ->
        unless (not (frag `isInfixOf` sout)) $
          expectationFailure $
            "Expected batch stdout NOT to contain " ++ show frag
            ++ "\n--- stdout ---\n" ++ sout

    it "streams one NDJSON row per input (default format)" $ do
      Output code sout _ <- runL4 bin ["batch", batchEligFixture, "--inputs", batchDataJson]
      code `shouldBe` ExitSuccess
      nonBlankLines sout `shouldBe` 2
      sout `shouldSatisfy` ("\"status\":\"success\"" `isInfixOf`)

    it "infers CSV cell types so numeric params typecheck" $ do
      -- If age/income stayed strings, JSONDECODE into NUMBER would fail and
      -- the rows would come back status=error; success proves inference works.
      Output code sout _ <-
        runL4 bin ["batch", batchEligFixture, "--inputs", batchDataCsv, "--format", "json"]
      code `shouldBe` ExitSuccess
      rows <- decodeArray sout
      length rows `shouldBe` 2
      let statuses = [ s | Object o <- rows
                         , Just (String s) <- [KeyMap.lookup (Key.fromString "status") o] ]
      statuses `shouldBe` ["success", "success"]

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

    it "keeps exponent-form CSV cells (1E5) as STRING, not numbers" $ do
      -- A product/lot code like 1E5 is a valid JSON number (1e5 = 100000),
      -- but must survive as the string "1E5" against a STRING param rather
      -- than being coerced to 100000.
      Output code sout _ <-
        runL4 bin ["batch", batchCodeFixture, "--inputs", batchExponentCsv]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("\"code\":\"1E5\"" `isInfixOf`)
      sout `shouldSatisfy` (not . ("100000" `isInfixOf`))

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

    -- Regression tests for target T11 (CLI injection / corruption).
    it "escapes payloads with backslashes, quotes and control chars (no lexer break)" $ do
      -- The input row's payload contains backslashes (Windows path), embedded
      -- quotes, newline/tab, and shell metacharacters. A naive quote-only
      -- escaper produced an unparseable generated wrapper; a correct one
      -- round-trips every byte as an L4 string literal.
      env <- jsonEnvelope bin ["batch", batchEscapeFixture, "--inputs", batchEscapeInput]
      objField env "status" `shouldBe` Just (String "success")

  describe "l4 trace (output path safety)" $ do
    it "never runs a shell for the output path, so metacharacters can't inject" $ do
      -- Render into a directory whose *name* would execute `touch <sentinel>`
      -- if the path were ever handed to a shell. With a direct `proc` call it
      -- is just a literal (if unusual) directory name. The sentinel must not
      -- appear regardless of whether Graphviz's `dot` is installed.
      tmp <- getTemporaryDirectory
      let sentinel = tmp </> "l4-trace-injection-sentinel"
          evilDir  = tmp </> ("l4trace$(touch " ++ sentinel ++ ").d")
      removePathForcibly sentinel
      removePathForcibly evilDir
      createDirectoryIfMissing True evilDir
      _ <- runL4 bin ["trace", evalTraceFixture, "--format", "png", "--output-dir", evilDir]
      ranShell <- doesFileExist sentinel
      removePathForcibly evilDir
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

  -- Regression tests for the import-cycle false-success bug: `l4 check`/`run`
  -- previously exited 0 on a 2-/3-module import ring because the engine's cycle
  -- error attaches to a transitively-imported file, not the entry file, and the
  -- verdict only inspected the entry file's own typecheck result.
  describe "l4 import cycles" $ do
    it "fails check on a 3-module import ring" $
      expectFail bin ["check", cycle3Entry]

    it "fails run on a 3-module import ring" $
      expectFail bin ["run", cycle3Entry]

    it "fails check on a 2-module import ring" $
      expectFail bin ["check", cycle2Entry]

    it "fails check on a self-import" $
      expectFail bin ["check", selfImportEntry]

    it "reports ok=false in JSON on a cyclic import" $ do
      env <- jsonEnvelope bin ["check", cycle3Entry, "--json"]
      objField env "ok" `shouldBe` Just (Bool False)

    it "still succeeds on a clean multi-file import" $
      -- Guard: the broadened 'any non-eval Error diagnostic fails the run'
      -- rule must NOT over-fire on a legitimate clean import.
      expectOk bin ["check", cleanImportEntry] "Check succeeded."

  -- Regression test for smucclaw/l4-ide#906: a diamond import over the
  -- embedded-library fallback used to starve the second sibling of the shared
  -- bottom's environment. `main.l4` imports two embedded siblings
  -- (actus-daycount, actus-schedule) that both IMPORT the embedded `daydate`;
  -- `actus-schedule` uses `Days in month`, defined in `daydate`. Run under the
  -- embedded-only regime (no JL4_LIBRARY_PATH, empty XDG) so the whole closure
  -- is served by the LSP/Shake embedded fallback — exactly the path CI's
  -- JL4_LIBRARY_PATH normally hides. Before the fix this exited non-zero with
  -- "I could not find a definition for the identifier `Days in month`".
  describe "l4 embedded-library diamond imports (#906)" $ do
    it "threads a transitive re-export into both diamond siblings" $ do
      Output code sout serr <- runL4EmbeddedOnly bin ["check", embeddedDiamondEntry]
      let combined = sout ++ "\n" ++ serr
      -- The starvation surfaces as an out-of-scope error on daydate's exports.
      when ("could not find a definition" `isInfixOf` combined) $
        expectationFailure $
          "Diamond sibling was starved of the embedded `daydate` environment:\n"
          ++ "--- stdout ---\n" ++ sout
          ++ "\n--- stderr ---\n" ++ serr
      case code of
        ExitSuccess -> pure ()
        ExitFailure n -> expectationFailure $
          "Expected the embedded-fallback diamond to check clean, but l4 exited "
          ++ show n ++ "\n--- stdout ---\n" ++ sout
          ++ "\n--- stderr ---\n" ++ serr

  describe "l4 openfisca" $ do
    it "compiles the flat-tax example to its golden OpenFisca module" $
      expectGolden bin ["openfisca", "examples/openfisca/flat-tax.l4"]
                       "examples/openfisca/expected/flat-tax.py"

    it "compiles the means-tested benefit example to its golden module" $
      expectGolden bin ["openfisca", "examples/openfisca/benefit.l4"]
                       "examples/openfisca/expected/benefit.py"

    it "compiles a group entity with LIST OF aggregation (household)" $
      expectGolden bin ["openfisca", "examples/openfisca/household.l4"]
                       "examples/openfisca/expected/household.py"

    it "compiles a time-varying marginal-rate scale + parameter store (scale)" $
      expectGolden bin ["openfisca", "examples/openfisca/scale.l4"]
                       "examples/openfisca/expected/scale.py"

    it "compiles roles + count/any/all aggregation (roles)" $
      expectGolden bin ["openfisca", "examples/openfisca/roles.l4"]
                       "examples/openfisca/expected/roles.py"

    it "compiles an enum + CONSIDER (housing)" $
      expectGolden bin ["openfisca", "examples/openfisca/housing.l4"]
                       "examples/openfisca/expected/housing.py"

    it "compiles dated formulas (BRANCH IF period reaches → formula_YYYY_MM)" $
      expectGolden bin ["openfisca", "examples/openfisca/dated.l4"]
                       "examples/openfisca/expected/dated.py"

    it "compiles a member decision-call inside an aggregation (agecheck)" $
      expectGolden bin ["openfisca", "examples/openfisca/agecheck.l4"]
                       "examples/openfisca/expected/agecheck.py"

    it "compiles a scalar legislation-parameter store (incometax)" $
      expectGolden bin ["openfisca", "examples/openfisca/incometax.l4"]
                       "examples/openfisca/expected/incometax.py"

    it "compiles the country-template basic_income (dated formulas + scalar params)" $
      expectGolden bin ["openfisca", "examples/openfisca/basic-income.l4"]
                       "examples/openfisca/expected/basic-income.py"

    it "rejects a name collision (distinct L4 names → same Python identifier)" $
      expectFail bin ["openfisca", "examples/openfisca/not-ok/name-collision.l4"]

    it "rejects a mis-ordered dated BRANCH (ascending arms)" $
      expectFail bin ["openfisca", "examples/openfisca/not-ok/branch-misordered.l4"]

    it "emits a Variable subclass and a TaxBenefitSystem" $ do
      Output code sout _ <- runL4 bin ["openfisca", "examples/openfisca/flat-tax.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("class flat_tax_on_salary(Variable):" `isInfixOf`)
      sout `shouldSatisfy` ("class L4TaxBenefitSystem(TaxBenefitSystem):" `isInfixOf`)

    it "fails on a file that does not typecheck" $
      expectFail bin ["openfisca", errorFixture]
  where
    for_ xs f = mapM_ f xs
