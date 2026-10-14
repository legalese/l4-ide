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

import Control.Exception (IOException, finally, throwIO, try)
import Control.Monad (unless, when)
import Data.List (isInfixOf, isPrefixOf, tails)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy.Char8 as BSL8
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Aeson (Value(..), eitherDecode)
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Key as Key
import System.Directory
  ( canonicalizePath
  , createDirectoryIfMissing
  , createFileLink
  , doesFileExist
  , emptyPermissions
  , findExecutable
  , getTemporaryDirectory
  , makeAbsolute
  , removePathForcibly
  , setOwnerReadable
  , setOwnerSearchable
  , setOwnerWritable
  , setPermissions
  )
import System.Environment (getEnvironment, lookupEnv)
import System.Exit (ExitCode(..), exitFailure)
import System.FilePath ((</>))
import System.IO (hClose, hSetBinaryMode)
import System.IO.Error (isPermissionError)
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
--
-- The result is always absolute: some tests run the binary from a different
-- working directory (to exercise the @l4 check main.l4@ invocation form), and a
-- relative binary path would not survive that.
locateL4Binary :: IO FilePath
locateL4Binary = makeAbsolute =<< locateL4Binary'

locateL4Binary' :: IO FilePath
locateL4Binary' = do
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
runL4WithEnv = runL4In Nothing

-- | Like 'runL4WithEnv', but also lets a test choose the child's working
-- directory.
--
-- This matters for library resolution: the CLI derives its root directory from
-- @takeDirectory@ of the entry path, so @l4 check main.l4@ run from inside the
-- project (root directory @"."@) exercises a different resolution path than
-- @l4 check some/dir/main.l4@ run from the package root. Every fixture path in
-- this suite carries a directory component, so without this the @"."@ case is
-- never covered — which is how a bare @l4 run total.l4@ lost the stdlib's names
-- (measured on plain main) without a red test.
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

-- | Run l4 with @XDG_DATA_HOME@ pointed at a caller-controlled directory and
-- @JL4_LIBRARY_PATH@ dropped (so 'resolveLibrary' reports
-- @hasExplicitPath = False@ and the resolver consults the embedded stdlib and
-- the ambient tiers). This is the dev regime the library-shadow
-- tests exercise — CI normally exports @JL4_LIBRARY_PATH@, which hides it.
-- | Try to create a symbolic link; 'Left' says why it could not be made. On
-- Windows an account without the symlink privilege gets "permission denied".
-- Any other failure is a real one and is rethrown.
tryLink :: FilePath -> FilePath -> IO (Either String ())
tryLink target link = do
  r <- try (createFileLink target link) :: IO (Either IOException ())
  case r of
    Right () -> pure (Right ())
    Left e
      | isPermissionError e -> pure (Left ("cannot create a symbolic link here (" <> show e <> ")"))
      | otherwise -> throwIO e

-- | Create a symbolic link, or mark the example pending where this account may
-- not: the example is about what @l4@ does with a link, not about whether the
-- platform lets a test make one.
linkOrPending :: FilePath -> FilePath -> IO ()
linkOrPending target link = tryLink target link >>= either pendingWith pure

runL4WithXdgHome :: FilePath -> FilePath -> [String] -> IO Output
runL4WithXdgHome = runL4WithXdgHomeIn Nothing

runL4WithXdgHomeIn :: Maybe FilePath -> FilePath -> FilePath -> [String] -> IO Output
runL4WithXdgHomeIn mCwd xdgHome bin args = do
  parentEnv <- getEnvironment
  let childEnv =
        ("XDG_DATA_HOME", xdgHome)
          : filter (\(k, _) -> k /= "JL4_LIBRARY_PATH" && k /= "XDG_DATA_HOME")
                   parentEnv
  runL4In mCwd (Just childEnv) bin args

-- | Run l4 with library resolution forced onto the embedded-library fallback:
-- no @JL4_LIBRARY_PATH@, and an /empty/ XDG store (so no user-level
-- @~/.local/share/jl4/libraries@ on the runner interferes). This is the exact
-- regime smucclaw/l4-ide#906 is about.
runL4EmbeddedOnly :: FilePath -> [String] -> IO Output
runL4EmbeddedOnly = runL4EmbeddedOnlyIn Nothing

-- | 'runL4EmbeddedOnly' from a caller-chosen working directory. Used to run the
-- CLI the way a user does — @l4 check main.l4@ from inside the project — which
-- makes the resolver's root directory @"."@.
runL4EmbeddedOnlyIn :: Maybe FilePath -> FilePath -> [String] -> IO Output
runL4EmbeddedOnlyIn mCwd bin args = do
  tmp <- getTemporaryDirectory
  let emptyXdg = tmp </> "l4-embedded-only-xdg"
  createDirectoryIfMissing True emptyXdg
  runL4WithXdgHomeIn mCwd emptyXdg bin args

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

-- Diamond over the embedded-library fallback (smucclaw/l4-ide#906): main imports two
-- embedded siblings that share the embedded 'daydate' bottom.
embeddedDiamondEntry :: FilePath
embeddedDiamondEntry = fixtureDir </> "embedded-diamond" </> "main.l4"

-- Library-shadow fixtures (specs/as-built/import-resolution.md): a bare `IMPORT prelude` with no
-- project-scoped copy (embedded must win over a poisoned XDG store), and a
-- companion with a project-local prelude override (which must win over the
-- embedded stdlib).
shadowEmbeddedEntry, shadowSiblingEntry, shadowExtraEntry :: FilePath
shadowEmbeddedEntry = fixtureDir </> "library-shadow" </> "embedded-wins" </> "main.l4"
shadowSiblingEntry  = fixtureDir </> "library-shadow" </> "sibling-wins"  </> "main.l4"
shadowExtraEntry    = fixtureDir </> "library-shadow" </> "xdg-extra"     </> "main.l4"

-- Directories of the shadow fixtures, for the tests that run the CLI from
-- INSIDE the project (@l4 check main.l4@) rather than naming the fixture by a
-- path with a directory component.
shadowEmbeddedDir, shadowSiblingDir, shadowImporterDir :: FilePath
shadowEmbeddedDir = fixtureDir </> "library-shadow" </> "embedded-wins"
shadowSiblingDir  = fixtureDir </> "library-shadow" </> "sibling-wins"
shadowImporterDir = fixtureDir </> "library-shadow" </> "embedded-importer"

-- A project-local override of a module that an EMBEDDED library imports.
shadowImporterEntry :: FilePath
shadowImporterEntry = shadowImporterDir </> "main.l4"

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

    it "reports an evaluation error in JSON in the drafter's terms, not as Haskell" $ do
      env <- jsonEnvelope bin ["run", fixtureDir </> "multi-clause-no-match.l4", "--json"]
      case objField env "results" of
        Just (Array v) | [Object r] <- foldr (:) [] v -> case KeyMap.lookup (Key.fromString "value") r of
          Just (String msg) -> do
            T.unpack msg `shouldSatisfy` ("No clause of `price` matches" `isInfixOf`)
            T.unpack msg `shouldSatisfy` (not . ("MkPmGroup" `isInfixOf`))
            T.unpack msg `shouldSatisfy` (not . ("NonExhaustivePatterns" `isInfixOf`))
          other -> expectationFailure ("Expected an error string, got " ++ show other)
        other -> expectationFailure ("Expected one result, got " ++ show other)

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
      Output code sout0 _ <- runL4 bin ["render", "--format", "text", multiClauseRenderFixture]
      code `shouldBe` ExitSuccess
      -- Windows ends lines with a carriage return, as in the l4 format test.
      let sout = filter (/= '\r') sout0
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

  -- Regression test for smucclaw/l4-ide#906: a diamond import over the
  -- embedded-library fallback used to starve the second sibling of the shared
  -- bottom's environment. `main.l4` imports two embedded siblings
  -- (actus-daycount, actus-schedule) that both IMPORT the embedded `daydate`;
  -- `actus-schedule` uses `Days in month`, defined in `daydate`. Run under the
  -- embedded-only regime (no JL4_LIBRARY_PATH, empty XDG) so the whole closure
  -- is served by the LSP/Shake embedded fallback — exactly the path CI's
  -- JL4_LIBRARY_PATH normally hides. Before the fix `l4 check` printed
  -- "I could not find a definition for the identifier ..." errors for the
  -- starved sibling (and still exited 0, so the assertion on the text below is
  -- what fails). The same starvation stops an ordinary user file that writes
  -- `IMPORT prelude` and `IMPORT daydate` from finding `sum`; that file exits 1
  -- before the fix.
  describe "l4 embedded-library diamond imports (smucclaw/l4-ide#906)" $ do
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

  -- Regression tests for specs/as-built/import-resolution.md (Option B′ ordering +
  -- Option E shadow warning). All run in the dev regime: JL4_LIBRARY_PATH
  -- unset, XDG_DATA_HOME pointed at a fabricated store. The incident being
  -- guarded against (§3.1 there): a machine-global XDG symlink silently
  -- shadowing the stdlib the binary was built with.
  describe "l4 library resolution shadow (B′)" $ do
    let mkXdgStore name libFileName mkLib = do
          tmp <- getTemporaryDirectory
          let xdgHome = tmp </> name
              store = xdgHome </> "jl4" </> "libraries"
          removePathForcibly xdgHome
          createDirectoryIfMissing True store
          _ <- mkLib (store </> libFileName)
          pure xdgHome
        poison = "this is not L4 at all ("

    it "embedded stdlib outranks a poisoned machine-global XDG copy" $ do
      xdgHome <- mkXdgStore "l4-shadow-xdg-poison" "prelude.l4" \p -> writeFile p poison
      Output code sout serr <- runL4WithXdgHome xdgHome bin ["check", shadowEmbeddedEntry]
      case code of
        ExitSuccess -> pure ()
        ExitFailure n -> expectationFailure $
          "Expected the embedded prelude to outrank the poisoned XDG copy, but l4 exited "
          ++ show n ++ "\n--- stdout ---\n" ++ sout
          ++ "\n--- stderr ---\n" ++ serr
      -- Option E: two differing copies were visible; the warning names them
      -- and the chosen one, at a priority the CLI actually prints. The two rows
      -- are asserted whole, with their markers: that the words "embedded
      -- stdlib" and "XDG data dir" appear somewhere in the output proves
      -- nothing, because the unresolved-import error and the parse error in
      -- the poisoned file name them too. On plain main, which has no warning,
      -- the poisoned file is reported as a parse error and the check still
      -- exits 0.
      serr `shouldSatisfy` ("Multiple differing copies of module `prelude`" `isInfixOf`)
      serr `shouldSatisfy` ("[chosen]   embedded stdlib" `isInfixOf`)
      serr `shouldSatisfy` ("[shadowed] XDG data dir" `isInfixOf`)

    -- The example below makes a symbolic link, and is marked pending where the
    -- account may not make one (Windows without the symlink privilege). This
    -- pins that path: a link made in a folder the account may not write to is
    -- reported, not thrown.
    it "reports a link it may not create, instead of throwing" $ do
      tmp <- getTemporaryDirectory
      let locked = tmp </> "l4-shadow-locked"
          target = tmp </> "l4-shadow-locked-target.l4"
          open' = setOwnerWritable True (setOwnerSearchable True (setOwnerReadable True emptyPermissions))
      removePathForcibly locked
      createDirectoryIfMissing True locked
      writeFile target poison
      setPermissions locked emptyPermissions
      r <- tryLink target (locked </> "prelude.l4") `finally` setPermissions locked open'
      case r of
        Left why -> why `shouldSatisfy` ("cannot create a symbolic link" `isInfixOf`)
        Right () -> pendingWith "this account can make a link in a read-only folder (root, or a platform that ignores the mode)"

    it "dereferences symlinks when naming the shadowed copy" $ do
      tmp <- getTemporaryDirectory
      let target = tmp </> "l4-shadow-poison-target.l4"
      writeFile target poison
      realTarget <- canonicalizePath target
      xdgHome <- mkXdgStore "l4-shadow-xdg-symlink" "prelude.l4" \p -> linkOrPending target p
      Output code _sout serr <- runL4WithXdgHome xdgHome bin ["check", shadowEmbeddedEntry]
      code `shouldBe` ExitSuccess
      -- The warning must print the symlink's real target, so a reader can see
      -- WHICH checkout/file a machine-global entry actually points at.
      serr `shouldSatisfy` (realTarget `isInfixOf`)

    it "a project-local prelude override still outranks the embedded stdlib" $ do
      xdgHome <- mkXdgStore "l4-shadow-xdg-empty" "unused.txt" \_ -> pure ()
      Output code sout serr <- runL4WithXdgHome xdgHome bin ["check", shadowSiblingEntry]
      -- main.l4 uses `shadow marker`, defined only in the fixture's local
      -- prelude.l4 — this checks clean iff the project-scoped copy won.
      case code of
        ExitSuccess -> pure ()
        ExitFailure n -> expectationFailure $
          "Expected the project-local prelude override to win, but l4 exited "
          ++ show n ++ "\n--- stdout ---\n" ++ sout
          ++ "\n--- stderr ---\n" ++ serr

    it "identical copies do not warn (content gate, non-embedded module)" $ do
      -- `shadow-extra` is NOT an embedded module; it exists beside the
      -- importing file AND in the XDG store, byte-identical. Two sources, one
      -- content: the Option E warning must stay silent.
      localCopy <- readFile (fixtureDir </> "library-shadow" </> "xdg-extra" </> "shadow-extra.l4")
      xdgHome <- mkXdgStore "l4-shadow-xdg-identical" "shadow-extra.l4" \p -> writeFile p localCopy
      Output code _sout serr <- runL4WithXdgHome xdgHome bin ["check", shadowExtraEntry]
      code `shouldBe` ExitSuccess
      serr `shouldSatisfy` (not . ("Multiple differing copies" `isInfixOf`))

    it "differing copies of the same non-embedded module do warn" $ do
      xdgHome <- mkXdgStore "l4-shadow-xdg-differing" "shadow-extra.l4" \p ->
        writeFile p "`something else entirely` MEANS TRUE\n"
      Output code _sout serr <- runL4WithXdgHome xdgHome bin ["check", shadowExtraEntry]
      -- The project-scoped copy wins either way; the differing ambient copy
      -- must be called out.
      code `shouldBe` ExitSuccess
      serr `shouldSatisfy` ("Multiple differing copies of module `shadow-extra`" `isInfixOf`)

  -- Precedence has to survive HOW THE ENTRY FILE IS SPELLED, and it has to
  -- reach embedded importers, not just the top-level module. Neither property
  -- was covered: every fixture path above carries a directory component, so
  -- @rootDirectory@ was never "."; and no fixture put a project copy of a module
  -- that an EMBEDDED library imports. Both gaps hid live precedence inversions
  -- on unstable. Plain main shows only the second: the bare-entry cases pass
  -- there too, and the embedded-importer cases are what fail.
  describe "l4 library resolution: entry-path spelling and embedded importers" $ do
    -- `l4 check main.l4`, run from inside the project — the ordinary way a user
    -- invokes the CLI, and the one that makes the resolver's root directory ".".
    let checkFrom dir = do
          absDir <- makeAbsolute dir
          runL4EmbeddedOnlyIn (Just absDir) bin ["check", "main.l4"]

    it "a project-local prelude override wins when the entry file is named bare" $ do
      -- Byte-for-byte the sibling-wins fixture the test above already uses, run
      -- as `l4 check main.l4` instead of `l4 check <dir>/main.l4`. The verdict
      -- must not depend on the spelling: main.l4 uses `shadow marker`, which
      -- only the fixture's own prelude.l4 defines.
      --
      -- Plain main passes this too. It is here because the change makes the
      -- embedded stdlib a candidate URI of its own (`jl4-embedded:`), and a
      -- version of the idea that registered it at a file-shaped key made the
      -- embedded prelude beat the project's when the root directory was ".",
      -- so this exited 1 with "I could not find a definition for the identifier
      -- `shadow marker`".
      Output code sout serr <- checkFrom shadowSiblingDir
      case code of
        ExitSuccess -> pure ()
        ExitFailure n -> expectationFailure $
          "Expected the project-local prelude override to win for a bare entry\
          \ path too, but l4 exited " ++ show n
          ++ "\n--- stdout ---\n" ++ sout
          ++ "\n--- stderr ---\n" ++ serr

    it "the embedded stdlib still wins with a bare entry path when nothing shadows it" $ do
      -- The other direction, so the fix above cannot be "never consult the
      -- embedded stdlib": embedded-wins/main.l4 has no project-local prelude, so
      -- the embedded copy must serve it.
      Output code sout serr <- checkFrom shadowEmbeddedDir
      case code of
        ExitSuccess -> pure ()
        ExitFailure n -> expectationFailure $
          "Expected the embedded prelude to serve a bare entry path, but l4 exited "
          ++ show n ++ "\n--- stdout ---\n" ++ sout
          ++ "\n--- stderr ---\n" ++ serr

    -- The names, not just the import. embedded-wins/main.l4 above only writes
    -- the `IMPORT`, so it cannot tell a prelude that is in scope from one that
    -- is not. With the entry file named bare and nothing on disk to find, plain
    -- main binds none of the prelude's names: `cd project && l4 run total.l4`
    -- answers "I could not find a definition for the identifier `sum`" and
    -- exits 1, while `l4 run project/total.l4` works.
    it "a bare entry path still brings the stdlib's names into scope" $ do
      tmp <- getTemporaryDirectory
      let work = tmp </> "l4-bare-entry-stdlib-names"
      removePathForcibly work
      createDirectoryIfMissing True work
      writeFile (work </> "total.l4") (unlines ["IMPORT prelude", "", "#EVAL sum (LIST 1, 2, 3)"])
      Output code sout serr <- runL4EmbeddedOnlyIn (Just work) bin ["run", "total.l4"]
      removePathForcibly work
      let combined = sout ++ "\n" ++ serr
      when ("could not find a definition" `isInfixOf` combined) $
        expectationFailure ("`sum` was not in scope after IMPORT prelude:\n" ++ combined)
      code `shouldBe` ExitSuccess

    -- One module name, one source, including for importers that are themselves
    -- embedded libraries. embedded-importer/daydate.l4 is a deliberately
    -- narrower override of a module the embedded `actus-schedule` imports and
    -- uses; binding `actus-schedule` to it must surface an arity error against
    -- `actus-schedule` itself. Before the change this checked clean: `main` saw
    -- the project `daydate` while `actus-schedule` quietly kept the embedded one.
    --
    -- The exit code is not asserted. On main an error inside an imported module
    -- is printed as a diagnostic and `l4 check` still exits 0, so the evidence
    -- is the text: the arity error names `actus-schedule`, and the shadow
    -- warning names the chosen project copy.
    --
    -- The positive control is the `embedded-diamond` test above: the same
    -- embedded closure with no project override checks clean.
    let expectEmbeddedImporterSeesOverride label run =
          it label $ do
            Output _code _sout serr <- run
            -- The diagnostic must land on the EMBEDDED importer, which is the
            -- whole point: that is the module that changed source.
            serr `shouldSatisfy` ("actus-schedule" `isInfixOf`)
            -- ...and the shadow warning must be telling the truth when it says
            -- the chosen copy is used wherever the module is imported.
            serr `shouldSatisfy` ("Multiple differing copies of module `daydate`" `isInfixOf`)
            serr `shouldSatisfy` ("[chosen]   project root" `isInfixOf`)

    expectEmbeddedImporterSeesOverride
      "an embedded library sees the project-local override too"
      (runL4EmbeddedOnly bin ["check", shadowImporterEntry])

    expectEmbeddedImporterSeesOverride
      "...and also when the entry file is named bare"
      (checkFrom shadowImporterDir)

    -- With the entry file named bare, the project root and the importing
    -- file's directory are the same directory, so the root tier and the
    -- importer-relative tier probe ONE file. The warning listed it twice, once
    -- as [chosen] and once as [shadowed], which reads as a copy shadowing itself.
    it "the shadow warning lists a copy once when two tiers name the same file" $ do
      Output code sout serr <- checkFrom shadowSiblingDir
      case code of
        ExitSuccess -> pure ()
        ExitFailure n -> expectationFailure $
          "Expected the project-local prelude override to win, but l4 exited "
          ++ show n ++ "\n--- stdout ---\n" ++ sout ++ "\n--- stderr ---\n" ++ serr
      serr `shouldSatisfy` ("Multiple differing copies of module `prelude`" `isInfixOf`)
      -- Two copies are visible, the project's prelude.l4 and the embedded
      -- stdlib: two rows, the first chosen and the second shadowed.
      let rows = [ l | l <- lines serr, "  [chosen]" `isPrefixOf` l || "  [shadowed]" `isPrefixOf` l ]
      map (takeWhile (/= ']')) rows `shouldBe` ["  [chosen", "  [shadowed"]
      length (filter ("prelude.l4" `isInfixOf`) rows) `shouldBe` 1

    -- Two rules resolve every IMPORT: the one that collects parser hints
    -- (GetMixfixRegistry) and the one that collects typecheck dependencies
    -- (GetImports). Each used to log "Module not found" at Warning, so one
    -- mistake printed two warnings, and both landed in `--json` diagnostics.
    it "warns once about an unresolved import, not once per rule that resolves it" $ do
      tmp <- getTemporaryDirectory
      let work    = tmp </> "l4-import-missing-warns-once"
          warning = "Module not found: zz no such module"
          occurrences needle hay = length (filter (needle `isPrefixOf`) (tails hay))
      removePathForcibly work
      createDirectoryIfMissing True work
      writeFile (work </> "importer.l4") "IMPORT `zz no such module`\n"
      let runIn args = runL4EmbeddedOnlyIn (Just work) bin args
      Output _ _ serr <- runIn ["check", "importer.l4"]
      occurrences warning serr `shouldBe` 1
      -- `l4 check --json` and `l4 run --json` carry the Warning lines in
      -- `diagnostics`; each must carry this one once.
      Output _ checkJson _ <- runIn ["check", "--json", "importer.l4"]
      occurrences warning checkJson `shouldBe` 1
      Output _ runJson _ <- runIn ["run", "--json", "importer.l4"]
      occurrences warning runJson `shouldBe` 1
      -- Positive control: `l4 ast` never typechecks, so the rule that collects
      -- dependencies never runs and the parser-hint rule is the only one that
      -- tells you. One warning must not become none.
      Output _ _ astErr <- runIn ["ast", "importer.l4"]
      occurrences warning astErr `shouldBe` 1
      removePathForcibly work

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
