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

import Control.Monad (unless)
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
  , findExecutable
  , getTemporaryDirectory
  , makeAbsolute
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

evalTraceFixture :: FilePath
evalTraceFixture = fixtureDir </> "evaltrace.l4"

-- | Multi-clause groups whose compiled form, printed back as source for
-- @l4 batch@, met a drafter's name or depended on the source text around it
-- (review of legalese/l4-ide#545 and #581); see the fixtures.
batchClauses, batchClausesCapture, batchClausesCatchAll, batchClausesDitto, batchClausesDittoHead
  , batchClausesTabs, batchClausesString
  , batchClausesColours, batchClausesBooleans, batchClausesB :: FilePath
batchClauses          = fixtureDir </> "batch-multi-clause.l4"
batchClausesCapture   = fixtureDir </> "batch-multi-clause-capture.l4"
batchClausesCatchAll  = fixtureDir </> "batch-multi-clause-catch-all.l4"
batchClausesDitto     = fixtureDir </> "batch-multi-clause-ditto.l4"
batchClausesDittoHead = fixtureDir </> "batch-multi-clause-ditto-head.l4"
batchClausesTabs      = fixtureDir </> "batch-multi-clause-tabs.l4"
batchClausesString    = fixtureDir </> "batch-multi-clause-string.l4"
batchClausesColours   = fixtureDir </> "batch-multi-clause-colours.json"
batchClausesBooleans  = fixtureDir </> "batch-multi-clause-booleans.json"
batchClausesB         = fixtureDir </> "batch-multi-clause-b.json"

-- | Two multi-clause groups, for how @l4 render@ and a trace name their parts.
multiClauseRenderFixture :: FilePath
multiClauseRenderFixture = fixtureDir </> "multi-clause-render.l4"

----------------------------------------------------------------------------
-- Tests
----------------------------------------------------------------------------

main :: IO ()
main = do
  bin <- locateL4Binary
  putStrLn ("Using l4 binary: " ++ bin)
  -- Sanity check fixtures exist (test suite must be run from repo root).
  for_ [ cleanFixture, evalFixture, errorFixture, garbageFixture
       , evalTraceFixture
       , batchClauses, batchClausesCapture, batchClausesCatchAll, batchClausesDitto
       , batchClausesDittoHead, batchClausesTabs, batchClausesString
       , batchClausesColours, batchClausesBooleans, batchClausesB
       , multiClauseRenderFixture ] \fp -> do
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

    it "warns that a multi-clause DECIDE misses a case, and still succeeds" $ do
      let fixture = fixtureDir </> "multi-clause-missing.l4"
      Output code sout serr <- runL4 bin ["check", fixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("Check succeeded." `isInfixOf`)
      serr `shouldSatisfy` ("does not cover all cases" `isInfixOf`)
      serr `shouldSatisfy` ("DECIDE `price` Blue IS" `isInfixOf`)

  -- The names a multi-clause group is compiled to are spelled so that no
  -- source can write them ('L4.Parser.generatedName'), and say what they are.
  describe "multi-clause groups: the names they are compiled to" $ do
    let generatedSpellings = ["_pm_", "__pm_", "pm arg", "pm_fallthrough"]
        mentionsOldName out = any (`isInfixOf` out) generatedSpellings

    it "reads the clauses as one list of cases in l4 render" $ do
      Output code sout _ <- runL4 bin ["render", "--format", "text", multiClauseRenderFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("- if it is Green: 2\n    - otherwise: 3" `isInfixOf`)
      sout `shouldSatisfy` ("depending on input 1:" `isInfixOf`)
      sout `shouldSatisfy` ("- otherwise: the result of clause 2" `isInfixOf`)
      sout `shouldSatisfy` ("The result of clause 2 is determined by:" `isInfixOf`)
      sout `shouldNotSatisfy` mentionsOldName

    it "names no generated input in the HTML rendering either" $ do
      Output code sout _ <- runL4 bin ["render", multiClauseRenderFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("input 1" `isInfixOf`)
      sout `shouldNotSatisfy` mentionsOldName

    it "names the later clauses by the clauses they hold in a trace" $ do
      Output code sout _ <- runL4 bin ["trace", multiClauseRenderFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("`the result of clauses 2 to 3`" `isInfixOf`)
      sout `shouldNotSatisfy` mentionsOldName

  -- `l4 batch` runs a module printed back as source. A multi-clause group
  -- prints as its clauses, from the AST ('L4.Print.writtenClauses'), so that
  -- no name the desugarer made up is written out as source, where a
  -- drafter's name could capture it, and nothing depends on the text around
  -- the clauses in the source (dittos, indentation).
  describe "l4 batch: re-prints a multi-clause group as its clauses" $ do
    let results args = do
          Output code sout _ <- runL4 bin (["batch"] <> args)
          code `shouldBe` ExitSuccess
          pure [ (objField row "status", outResult row)
               | l <- lines sout
               , Right row <- [eitherDecode (BSL8.pack l) :: Either String Value]
               ]
        outResult row = case objField row "output" of
          Just (Array os) | [o] <- foldr (:) [] os -> objField o "result"
          _ -> Nothing
        ok v = (Just (String "success"), Just v)
    it "reads a drafter's definition named like the binding of the later clauses" $
      results [batchClauses, "-e", "later", "--inputs", batchClausesColours]
        >>= (`shouldBe` map ok [Number 7, Number 2, Number 3])
    it "reads a drafter's definition named like the binding of the last clause" $
      results [batchClauses, "-e", "fee", "--inputs", batchClausesColours]
        >>= (`shouldBe` map ok [Number 1, Number 101, Number 3])
    it "reads a drafter's definition named like an input of a group with no GIVEN" $
      results [batchClauses, "-e", "through", "--inputs", batchClausesColours]
        >>= (`shouldBe` map ok [String "Blue", String "Red", String "Green"])
    it "reads a drafter's `input 1` in a group whose only clause left matches anything" $ do
      results [batchClausesCatchAll, "-e", "one", "--inputs", batchClausesColours]
        >>= (`shouldBe` map ok [String "Blue", String "Blue", String "Blue"])
      results [batchClausesCatchAll, "-e", "two", "--inputs", batchClausesColours]
        >>= (`shouldBe` map ok [String "Blue", String "Blue", String "Blue"])
    it "tests the input a pattern variable is named after, not the variable" $
      results [batchClausesCapture, "-e", "capture", "--inputs", batchClausesBooleans]
        >>= (`shouldBe` map ok [Number 1, Number 2, Number 1, Number 2])
    it "keeps what a ditto in a clause body copies" $
      results [batchClausesDitto, "--inputs", batchClausesColours]
        >>= (`shouldBe` map ok [Number 1, Number 0, Number 0])
    it "keeps what a ditto in a clause head copies" $
      results [batchClausesDittoHead, "--inputs", batchClausesB]
        >>= (`shouldBe` map ok [Number 1, Number 2])
    it "reads clauses indented with tabs" $
      results [batchClausesTabs, "--inputs", batchClausesColours]
        >>= (`shouldBe` map ok [Number 1, Number 3, Number 3])
    -- The printer adds its indentation to the later lines of any string
    -- that spans lines, in a rule written as clauses or not. `l4 run` gives
    -- "a\n      b".
    it "keeps a string that spans lines in a clause body" $ do
      pendingWith "the printer indents the later lines of a multi-line string, in every rule"
      results [batchClausesString, "--inputs", batchClausesColours]
        >>= (`shouldBe` map ok [String "a\n      b", String "z", String "z"])

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

    it "reproduces multi-clause DECIDE and MEANS groups byte-for-byte" $ do
      -- The parser fuses a clause group into one definition; formatting must
      -- still print every clause as written. Carriage returns are dropped on
      -- both sides so a CRLF checkout on Windows compares equal.
      let fixture = fixtureDir </> "multi-clause-format.l4"
      src <- readFile fixture
      Output code sout _ <- runL4 bin ["format", fixture]
      code `shouldBe` ExitSuccess
      filter (/= '\r') sout `shouldBe` filter (/= '\r') src

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
