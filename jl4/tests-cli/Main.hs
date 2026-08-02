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
import Data.List (findIndex, isInfixOf, sort)
import Data.Maybe (fromMaybe)
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
  , getTemporaryDirectory
  , makeAbsolute
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
-- never covered — which is how the embedded stdlib came to outrank
-- project-local libraries for a whole release without a red test.
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
-- the ambient tiers). This is the dev regime the LIBRARY-RESOLUTION-SHADOW
-- tests exercise — CI normally exports @JL4_LIBRARY_PATH@, which hides it.
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
-- regime issue #906 is about.
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

----------------------------------------------------------------------------
-- The DMN engine harnesses
----------------------------------------------------------------------------

-- | Run one of the committed engine checkers over the shipped DMN golden.
--
-- __Why this is opt-in.__ @cabal test all@ must stay hermetic and network-free:
-- these harnesses need a JDK and Maven, and on a cold cache Maven reaches the
-- network. So the block runs only under @L4_DMN_ENGINE_CHECK=1@, which makes it
-- a deliberate choice rather than an accident of what happens to be installed.
--
-- __Why the assertion is on the banner and not on the exit code.__ A checker
-- that cannot run exits 0 — that is the skip contract, and it is the right
-- behaviour on a laptop without Java. But "exit 0" is then ambiguous between
-- \"the engine looked at the file and was happy\" and \"nothing happened\". The
-- harnesses print a @VERDICT@ line only when they actually ran, so asserting the
-- banner closes that gap. A skip is reported through 'pendingWith', which hspec
-- renders as @# PENDING@ and counts separately from a pass.
--
-- __Why an unset @*_CHECK_REQUIRED@ still cannot pass silently.__ Setting
-- @KIE_CHECK_REQUIRED=1@ / @CAMUNDA_CHECK_REQUIRED=1@ turns every skip path
-- inside the scripts into exit 1. When they are /not/ set — which is the case
-- for anyone running @cabal test l4-cli-test@ by hand — a skip lands in the
-- @pendingWith@ branch below and is reported as @UNEXERCISED@, naming the
-- variable that would make it fatal.
--
-- __What CI actually does, which is not this function.__ The @dmn-engines@ job
-- in @.github\/workflows\/pr-checks.yml@ runs the two scripts /directly/, with
-- both @*_CHECK_REQUIRED@ variables set, and greps their banners. It does not
-- invoke @l4-cli-test@, and the Haskell job does not set
-- @L4_DMN_ENGINE_CHECK@ — so in CI this function always takes the outer
-- @pendingWith@. It is the developer-facing entry point (one command, the same
-- harnesses, the same assertions); the gate is the job. Neither pretends to be
-- the other. (An earlier version of this comment claimed CI reached the inner
-- branch. It does not, and saying so was the same class of error as a check
-- that reports a version it never loaded.)
--
-- __Why a missing script is a failure even locally.__ Absent /tooling/ is a fact
-- about the machine; an absent /harness/ is a fact about the repo, and would
-- mean this test has silently stopped testing anything.
dmnEngineCheck :: String -> FilePath -> String -> (String -> Expectation) -> Expectation
dmnEngineCheck label script requiredVar =
  dmnEngineCheckOn label script requiredVar HarnessMustPass
    dmnGolden [dmnGolden, "--cases", dmnEngineCases]

-- | Which way round the harness's own exit code is being asserted.
--
-- 'HarnessMustFail' exists for the negative fixtures: a file that the gate is
-- supposed to REJECT. Without it the suite could only ever show the gate
-- staying green, which is not evidence that it is connected to anything —
-- see 'dmnXsdOrderNegative' and DMN-EXPORT-PROGRAM-MODEL-SPEC.md §9.
data HarnessOutcome = HarnessMustPass | HarnessMustFail
  deriving (Eq, Show)

-- | For probe leg titles.
outcomeWord :: HarnessOutcome -> String
outcomeWord = \case
  HarnessMustPass -> "MustPass"
  HarnessMustFail -> "MustFail"

-- | The general form: run one committed engine harness over one file and
-- assert its VERDICT banner, under the same opt-in/skip contract as
-- 'dmnEngineCheck'.
--
-- The banner is still the liveness signal in BOTH directions. A harness that
-- died before running also exits non-zero, so \"exited 1\" on its own would let
-- a broken harness masquerade as a caught defect — exactly the confusion the
-- banner was introduced to prevent, only mirrored.
dmnEngineCheckOn
  :: String -> FilePath -> String -> HarnessOutcome
  -> FilePath -> [String] -> (String -> Expectation) -> Expectation
dmnEngineCheckOn label script requiredVar outcome subject args assertBanner = do
  enabled <- lookupEnv "L4_DMN_ENGINE_CHECK"
  case enabled of
    Just "1" -> do
      haveScript <- doesFileExist script
      unless haveScript $
        expectationFailure (label ++ " harness missing from the repo: " ++ script)
      Output code sout serr <- runL4In Nothing Nothing script args
      let banner = "VERDICT:"
      if banner `isInfixOf` sout
        then do
          case outcome of
            HarnessMustPass ->
              unless (code == ExitSuccess) $
                expectationFailure
                  (label ++ " reported a problem in " ++ subject
                     ++ "\n--- stdout ---\n" ++ sout ++ "\n--- stderr ---\n" ++ serr)
            HarnessMustFail ->
              when (code == ExitSuccess) $
                expectationFailure
                  (label ++ " ACCEPTED " ++ subject
                     ++ ", which is committed precisely because it must be rejected."
                     ++ "\n--- stdout ---\n" ++ sout ++ "\n--- stderr ---\n" ++ serr)
          assertBanner sout
        else
          -- No banner: the harness skipped, or died before running.
          pendingWith
            (label ++ " UNEXERCISED: the checker did not run (set " ++ requiredVar
               ++ "=1 to make this a failure). " ++ oneLineOf serr)
    _ ->
      pendingWith
        (label ++ " UNEXERCISED: set L4_DMN_ENGINE_CHECK=1 to run the engine checks")
 where
  oneLineOf = unwords . words

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

-- | Read a file as UTF-8 regardless of the ambient locale — same reasoning as
-- 'runL4': the fidelity goldens are full of em-dashes and typographic quotes,
-- which a CP1252 Windows runner cannot decode through 'readFile'.
readUtf8 :: FilePath -> IO String
readUtf8 fp = T.unpack . TE.decodeUtf8Lenient <$> BS.readFile fp

-- | Index of the first line containing a needle.
--
-- An ABSENT needle yields 'maxBound' rather than a negative sentinel, so it
-- sorts LAST: a fixture that lost its @\<itemDefinition\>@ altogether then
-- fails the \"before\" assertion instead of vacuously satisfying it.
firstLineWith :: String -> String -> Int
firstLineWith needle = fromMaybe maxBound . findIndex (needle `isInfixOf`) . lines

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

-- | Typechecks cleanly, then THROWS when its @#EVAL@ is evaluated.
evalCrashFixture :: FilePath
evalCrashFixture = fixtureDir </> "eval-crash.l4"

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

-- `l4 export` (track S0). The two golden-bearing exhibits live under
-- examples/, alongside the openfisca ones; the refusal and severity fixtures
-- are local.
--
-- The two --fail-on fixtures are a matched pair, and both are needed: the
-- `export-blocking-only` DMN report is blocking-ONLY and the
-- `export-advisory-only` DMN report is advisory-ONLY, so between them every
-- @FidelityGate@ value has both a case that must trip and a case that must
-- not. (`export-two-rules` used to play the blocking-only role, until Phase
-- 4's population filter correctly routed its two uncalled regulative bodies
-- out of the DRG — it keeps its BPMN rule-selection role, and its DMN export
-- now refuses with an EMPTY model, which its own test below pins.)
exportTwoRulesFixture, exportNothingFixture :: FilePath
exportBlockingOnlyFixture, exportAdvisoryOnlyFixture :: FilePath
exportTwoRulesFixture     = fixtureDir </> "export-two-rules.l4"
exportNothingFixture      = fixtureDir </> "export-nothing.l4"
exportBlockingOnlyFixture = fixtureDir </> "export-blocking-only.l4"
exportAdvisoryOnlyFixture = fixtureDir </> "export-advisory-only.l4"

-- The FIXTURE(d) backticked-import pair: a HYPHENATED module beside a sibling
-- that imports it backticked (the only legal spelling for a hyphenated name)
-- and references `statute`.
importViewFixture :: FilePath
importViewFixture = fixtureDir </> "import-view" </> "interp-common.l4"

bpmnOfferingSource, bpmnOfferingGolden, bpmnOfferingFidelity :: FilePath
bpmnOfferingSource   = "examples/bpmn/offering.l4"
bpmnOfferingGolden   = "examples/bpmn/expected/offering.bpmn"
bpmnOfferingFidelity = "examples/bpmn/expected/offering.fidelity.txt"

dmnSource, dmnGolden, dmnMarkdownGolden :: FilePath
dmnSource         = "examples/dmn/reg-cf.l4"
dmnGolden         = "examples/dmn/expected/reg-cf.dmn"
dmnMarkdownGolden = "examples/dmn/expected/reg-cf.dmn.md"

-- The model name the DMN goldens were generated under. `lowerModule` takes it
-- as a parameter precisely so the emitted bytes do not depend on where the file
-- lives, so passing it here reproduces the suite's output exactly.
dmnModelName :: String
dmnModelName = "Regulation Crowdfunding"

-- The two committed engine harnesses, and the CASES they evaluate the golden
-- against. These paths are relative to jl4/, which is this suite's working
-- directory.
--
-- Each case is a context plus the value EVERY decision must produce under it.
-- Checking only that a decision "ran" is not enough, and that is measured
-- rather than assumed: given a model declaring `annual income` = 100000,
-- `annual` = 5 and `come` = [1,2,5], Camunda 8.7.6 answers `true` to the
-- expression `annual income` — identically to `annual in come` — where KIE
-- 8.44 answers 100000. A wrong NON-null value, so a harness reading statuses
-- and nulls alone passes the very file it exists to catch (§13.2).
--
-- The contexts' KEYS ARE FEEL NAMES, not L4 names: `annual_income`, not
-- `annual income`. That is not a detail of the harness, it is the thing being
-- checked — see specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md §5.2 and §13.2.
kieCheckScript, camundaCheckScript, dmnEngineCases :: FilePath
kieCheckScript     = ".." </> "etc" </> "kie-dmn-check" </> "run.sh"
camundaCheckScript = ".." </> "etc" </> "camunda-dmn-check" </> "run.sh"
dmnEngineCases     = "examples/dmn/reg-cf.cases.json"

-- The XSD SEQUENCE-ORDER pair (DMN-EXPORT-PROGRAM-MODEL-SPEC.md §4.3, §9).
--
-- Two hand-written DMN 1.3 files holding the same lines and differing only in
-- where the @\<itemDefinition\>@ block sits. @tDefinitions@ is a sequence, so
-- the one that puts it after @\<inputData\>@ is schema-INVALID; the other is
-- the positive control that says so is the only difference.
--
-- __Why a hand-written file and not a mutated golden.__ The emitter cannot
-- produce the negative case — that is the property under test — so there is
-- nothing to generate it from. These are fixtures, never regenerated.
dmnXsdOrderPositive, dmnXsdOrderNegative, dmnXsdOrderCases :: FilePath
dmnXsdOrderPositive = dmnXsdOrderDir </> "M1-itemdef-before-inputdata.dmn"
dmnXsdOrderNegative = dmnXsdOrderDir </> "M1-itemdef-after-inputdata.dmn"
dmnXsdOrderCases    = dmnXsdOrderDir </> "M1-itemdef.cases.json"

dmnXsdOrderDir :: FilePath
dmnXsdOrderDir = fixtureDir </> "dmn-xsd-order"

-- The LAW-TIME date axis (DMN-EXPORT-PROGRAM-MODEL-SPEC.md §15).
--
-- `gstGolden` is EMITTED (jl4/tests/DmnExport.hs owns the golden); the two
-- chains inside it lower to single-column UNIQUE tables over
-- `RULES_EFFECTIVE_DATE` with half-open date intervals, and `gstEngineCases`
-- FEEDS DATES -- `{"$date": "YYYY-MM-DD"}` -- so both engines are made to
-- answer differently for different rule dates. `GST rate percent` has THREE
-- seams and every one is straddled by a day-of/day-before pair, which is what
-- pins the closed-low/open-high convention; straddling only the newest seam
-- (which an earlier version did) leaves an off-by-one on the middle interval
-- or on the floor row invisible.
--
-- `dateProbe*` is HAND-WRITTEN and never regenerated, for the same reason
-- `dmn-xsd-order` is: it asks the questions the emitter's own output cannot
-- ask -- does Xerces accept <annotation>/<annotationEntry> where DMN13.xsd's
-- sequences put them, and does each engine evaluate a date-interval cell at
-- all. §15.6 records what it returned. `dateProbeNegative` is its NEGATIVE
-- CONTROL, and it is not optional: the positive on its own shows that a valid
-- file validates, which is equally consistent with Xerces ignoring the
-- annotation elements entirely.
gstGolden, gstEngineCases, dateProbeModel, dateProbeCases, dateProbeNegative :: FilePath
gstGolden         = "examples/dmn/expected/gst-rate.dmn"
gstEngineCases    = "examples/dmn/gst-rate.cases.json"
dateProbeModel    = dmnDateProbeDir </> "date-axis.dmn"
dateProbeCases    = dmnDateProbeDir </> "date-axis.cases.json"
dateProbeNegative = dmnDateProbeDir </> "date-axis-badannotation.dmn"

-- The Reg CF CORPUS leg (R12/R13, DMN-EXPORT-PROGRAM-MODEL-SPEC.md §15.12/§16):
-- the 1,236-line statute corpus, 67 decisions, evaluated end to end. The cases
-- file's own header records how each pin was anchored (L4 + the documented
-- transform, never the engine's own output).
corpusGolden, corpusEngineCases :: FilePath
corpusGolden      = "examples/dmn/expected/regcf-corpus.dmn"
corpusEngineCases = "examples/dmn/regcf-corpus.cases.json"

dmnDateProbeDir :: FilePath
dmnDateProbeDir = fixtureDir </> "dmn-date-probe"

-- The ENGINE-INTERSECTION triple (DMN-EXPORT-PROGRAM-MODEL-SPEC.md §6,
-- measured note of 2026-07-30). One statute-shaped predicate — "either spouse
-- earns under $100,000 or is a Qualifying Candidate" — spelled three ways
-- over one shared cases file: inline in the quantifier's @satisfies@, as a
-- decision table bound in a boxed-context entry, and as the same table in a
-- BKM. Hand-written, never regenerated: the emitter produces none of the
-- three shapes today, and the middle one exists precisely because only half
-- the market can read it.
spouseInlineDmn, spouseContextTableDmn, spouseBkmTableDmn, spouseCases :: FilePath
spouseInlineDmn       = dmnIntersectionDir </> "spouse-inline.dmn"
spouseContextTableDmn = dmnIntersectionDir </> "spouse-context-table.dmn"
spouseBkmTableDmn     = dmnIntersectionDir </> "spouse-bkm-table.dmn"
spouseCases           = dmnIntersectionDir </> "spouse.cases.json"

dmnIntersectionDir :: FilePath
dmnIntersectionDir = fixtureDir </> "dmn-engine-intersection"

-- The HYDRATION probe (H4). Hand-written for the same reason `dateProbe*` is:
-- it pins the portability of the boxed-context idiom ITSELF, independently of
-- whether the emitter currently produces it. Unlike the date and xsd-order
-- pairs there is no negative control, and the fixture's own header says why:
-- those two ask whether a gate REJECTS, which needs a negative; this one asks
-- whether an idiom EVALUATES, which the positive answers on its own.
hydrationProbeModel, hydrationProbeCases :: FilePath
hydrationProbeModel = dmnHydrationProbeDir </> "hydration-context.dmn"
hydrationProbeCases = dmnHydrationProbeDir </> "hydration.cases.json"

dmnHydrationProbeDir :: FilePath
dmnHydrationProbeDir = fixtureDir </> "dmn-hydration-probe"

-- The 23 Phase 5 BKM/service probes (spec §6.2, §13.3-§13.5;
-- DMN-PHASE5-BUILD-PLAN.md §1 holds the full matrix). Hand-written, never
-- regenerated: they pin the IDIOMS (BKM invocation, knowledgeRequirement
-- topology, decisionService shapes, name-collision semantics) independently
-- of the emitter — a red run on a probe isolates the ENGINE, a red run on
-- the emitted goldens isolates the LOWERING, exactly the hydration split.
--
-- Each row: (label, fixture stem, KIE outcome, Camunda outcome), the
-- outcomes transcribed from each fixture's own MEASURED header (2026-07-31)
-- and re-run here. THE ASYMMETRY IS THE FLAVOR AXIS: the seven fixtures that
-- fail on KIE and pass on Camunda (C4, D5, E4, E5, E6, and with C3/D3's null
-- degradations beside them) are, without exception, cases where CAMUNDA'S
-- SILENCE IS THE DANGER — KIE refuses at validator/compile where zeebe-dmn
-- parses and answers something. A FLIP on any row means an engine changed
-- its mind across an upgrade: re-read the fixture's header and the spec
-- section it names before touching the row (e.g. C4 going green on KIE
-- would relax §6.2's name==variable invariant; E4 agreeing would demote
-- §5.2's BKM-in-scope-1 requirement).
dmnBkmProbeDir :: FilePath
dmnBkmProbeDir = fixtureDir </> "dmn-bkm-probe"

bkmProbeMatrix :: [(String, String, HarnessOutcome, HarnessOutcome)]
bkmProbeMatrix =
  [ ("A1", "bkm-multiparam",               HarnessMustPass, HarnessMustPass)
  , ("A2", "bkm-named-args",               HarnessMustPass, HarnessMustPass)
  , ("A3", "bkm-table-multiparam",         HarnessMustPass, HarnessMustPass)
  , ("B1", "bkm-in-context",               HarnessMustPass, HarnessMustPass)
  , ("B2", "bkm-in-context-sibling",       HarnessMustPass, HarnessMustPass)
  , ("B3", "bkm-null",                     HarnessMustPass, HarnessMustPass)
  , ("C1", "bkm-chain",                    HarnessMustPass, HarnessMustPass)
  , ("C2", "bkm-chain-flat",               HarnessMustFail, HarnessMustFail)
  , ("C3", "bkm-chain-nokr",               HarnessMustFail, HarnessMustFail)
  , ("C4", "bkm-name-mismatch",            HarnessMustFail, HarnessMustPass)
  , ("D1", "svc-grouping",                 HarnessMustPass, HarnessMustPass)
  , ("D2", "svc-invoked",                  HarnessMustPass, HarnessMustFail)
  , ("D3", "svc-invoked-minus-kr",         HarnessMustFail, HarnessMustFail)
  , ("D4", "svc-plus-bkm",                 HarnessMustPass, HarnessMustPass)
  , ("D5", "svc-no-output",                HarnessMustFail, HarnessMustPass)
  , ("D6", "svc-cycle",                    HarnessMustFail, HarnessMustFail)
  , ("E1", "collide-param-input",          HarnessMustPass, HarnessMustPass)
  , ("E2", "collide-param-param",          HarnessMustPass, HarnessMustPass)
  , ("E3", "collide-param-decision",       HarnessMustFail, HarnessMustFail)
  , ("E4", "collide-bkm-decision",         HarnessMustFail, HarnessMustPass)
  , ("E5", "collide-svc-decision",         HarnessMustFail, HarnessMustPass)
  , ("E6", "collide-svc-svc",              HarnessMustFail, HarnessMustPass)
  , ("E7", "collide-param-shadow-visible", HarnessMustPass, HarnessMustPass)
  ]

-- The EMITTER'S OWN hydration output, and its cases. Strictly stronger than the
-- hand-written probe above: that one pins that the boxed-context idiom
-- evaluates, this one pins that jl4-core/src/L4/Dmn/Lower.hs emits it. A red run
-- there isolates the ENGINE; a red run here isolates the LOWERING.
--
-- It is also the file that carries the two-engine measurement `sumtype.dmn`
-- cannot: sumtype exists to exhibit REFUSALS, and one of them (`stated term`,
-- R4-a) emits L4 source no engine can compile.
hydrationGolden, hydrationEngineCases :: FilePath
hydrationGolden      = "examples/dmn/expected/hydration.dmn"
hydrationEngineCases = "examples/dmn/hydration.cases.json"

-- The data-model exhibit, driven through KIE as a MustFail. There is no cases
-- file: the point is that the model does not BUILD, which is settled before any
-- case runs.
sumtypeGolden :: FilePath
sumtypeGolden = "examples/dmn/expected/sumtype.dmn"

-- The Phase 5 exhibits (spec §6.2, §2.3, §13.5, §13.6). `bkm` is
-- flavor-identical and MustPass on BOTH engines; `svc` is the one subject
-- whose goldens SPLIT by flavor — its kie golden MustPass on KIE (the service
-- invocation executes) and its camunda golden MustFail on Camunda (the §13.5
-- refusal keeps the call site raw L4, which zeebe-dmn rejects at parse).
bkmSource, bkmDmnGolden, bkmEngineCases :: FilePath
bkmSource      = "examples/dmn/bkm.l4"
bkmDmnGolden   = "examples/dmn/expected/bkm.dmn"
bkmEngineCases = "examples/dmn/bkm.cases.json"

svcSource, svcGolden, svcKieDmnGolden, svcEngineCases :: FilePath
svcSource       = "examples/dmn/svc.l4"
svcGolden       = "examples/dmn/expected/svc.dmn"
svcKieDmnGolden = "examples/dmn/expected/svc.kie.dmn"
svcEngineCases  = "examples/dmn/svc.cases.json"

-- The NULL probe (R8-d′). Written and measured BEFORE the MAYBE→null lowering,
-- because the whole ruling rests on FEEL's `=` against null being a proper
-- boolean; if it were not, `if x != null then a else b` would take the else
-- branch on a non-boolean condition and the absence-test half of R8-d′ would
-- have been an ANSWER CHANGE. It is a boolean on both engines, so it shipped.
--
-- `nullAbsent*` is split out because it is the one question the two engines
-- ANSWER DIFFERENTLY: an unbound name is null on zeebe-dmn and a model error on
-- KIE. It is therefore MustPass on one and MustFail on the other, and each leg
-- asserts that engine's own words.
nullProbeModel, nullProbeCases, nullAbsentModel, nullAbsentCases :: FilePath
nullProbeModel  = dmnNullProbeDir </> "null-semantics.dmn"
nullProbeCases  = dmnNullProbeDir </> "null-semantics.cases.json"
nullAbsentModel = dmnNullProbeDir </> "null-absent.dmn"
nullAbsentCases = dmnNullProbeDir </> "null-absent.cases.json"

dmnNullProbeDir :: FilePath
dmnNullProbeDir = fixtureDir </> "dmn-null-probe"

-- LIBRARY-RESOLUTION-SHADOW-SPEC fixtures: a bare `IMPORT prelude` with no
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

----------------------------------------------------------------------------
-- Tests
----------------------------------------------------------------------------

main :: IO ()
main = do
  bin <- locateL4Binary
  putStrLn ("Using l4 binary: " ++ bin)
  -- Sanity check fixtures exist (test suite must be run from repo root).
  for_ [ cleanFixture, evalFixture, errorFixture, garbageFixture
       , evalCrashFixture
       , breachTraceFixture, breachInputsFixture
       , batchEligFixture, batchDataJson, batchDataCsv, batchMixedJson
       , batchCodeFixture, batchExponentCsv, batchMaybeFixture, batchMaybeBadJson
       , batchEscapeFixture, batchEscapeInput, evalTraceFixture
       , cycle3Entry, cycle2Entry, selfImportEntry, cleanImportEntry
       , embeddedDiamondEntry, shadowEmbeddedEntry, shadowSiblingEntry
       , shadowExtraEntry, shadowImporterEntry
       , exportTwoRulesFixture, exportNothingFixture
       , exportBlockingOnlyFixture, exportAdvisoryOnlyFixture
       , bpmnOfferingSource, bpmnOfferingGolden, bpmnOfferingFidelity
       , dmnSource, dmnGolden, dmnMarkdownGolden, dmnEngineCases
       , dmnXsdOrderPositive, dmnXsdOrderNegative, dmnXsdOrderCases
       , gstGolden, gstEngineCases, dateProbeModel, dateProbeCases
       , dateProbeNegative
       , spouseInlineDmn, spouseContextTableDmn, spouseBkmTableDmn, spouseCases
       , hydrationProbeModel, hydrationProbeCases
       , nullProbeModel, nullProbeCases, nullAbsentModel, nullAbsentCases
       , hydrationGolden, hydrationEngineCases, sumtypeGolden
       , bkmSource, bkmDmnGolden, bkmEngineCases
       , svcSource, svcGolden, svcKieDmnGolden, svcEngineCases ] \fp -> do
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
      sout `shouldSatisfy` ("export" `isInfixOf`)
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

    -- Ruled by Meng 2026-08-01: a crashed #EVAL must be loud. Before the
    -- ruling this exited 0 with the crash buried in the output, and nothing
    -- pinned it either way.
    it "fails when a #EVAL crashes during evaluation" $
      expectFail bin ["run", evalCrashFixture]

    it "returns ok=false in JSON when a #EVAL crashes" $ do
      env <- jsonEnvelope bin ["run", evalCrashFixture, "--json"]
      objField env "ok" `shouldBe` Just (Bool False)
      case objField env "results" of
        Just (Array v) -> length v `shouldBe` 1
        other          -> expectationFailure ("Expected results array, got " ++ show other)

    -- Guards the reason as well as the outcome: the fixture must fail because
    -- it CRASHED, not because it failed to typecheck (which would make the two
    -- assertions above pass for the wrong reason). It also pins the asymmetry —
    -- the crash rule belongs to `l4 run`, which evaluates; `l4 check`, which
    -- does not, is unaffected.
    it "still typechecks the crashing fixture — l4 check succeeds on it" $
      expectOk bin ["check", evalCrashFixture] "Check succeeded."

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

  -- Regression tests for LIBRARY-RESOLUTION-SHADOW-SPEC (Option B′ ordering +
  -- Option E shadow warning). All run in the dev regime: JL4_LIBRARY_PATH
  -- unset, XDG_DATA_HOME pointed at a fabricated store. The incident being
  -- guarded against (§3.1 of the spec): a machine-global XDG symlink silently
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
      -- and the chosen one, at a priority the CLI actually prints.
      serr `shouldSatisfy` ("Multiple differing copies of module `prelude`" `isInfixOf`)
      serr `shouldSatisfy` ("[chosen]" `isInfixOf`)
      serr `shouldSatisfy` ("embedded stdlib" `isInfixOf`)
      serr `shouldSatisfy` ("XDG data dir" `isInfixOf`)

    it "dereferences symlinks when naming the shadowed copy" $ do
      tmp <- getTemporaryDirectory
      let target = tmp </> "l4-shadow-poison-target.l4"
      writeFile target poison
      realTarget <- canonicalizePath target
      xdgHome <- mkXdgStore "l4-shadow-xdg-symlink" "prelude.l4" \p -> createFileLink target p
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
  -- that an EMBEDDED library imports. Both gaps hid live precedence inversions.
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
      -- It used to. With rootDirectory ".", the root candidate URI for `prelude`
      -- normalised to exactly the key the embedded stdlib was registered under,
      -- and the VFS tier hit it before library resolution ran — so this exited 1
      -- with "I could not find a definition for the identifier `shadow marker`".
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

    -- One module name, one source — including for importers that are themselves
    -- embedded libraries. embedded-importer/daydate.l4 is a deliberately
    -- narrower override of a module the embedded `actus-schedule` imports and
    -- uses; binding `actus-schedule` to it must surface an arity error against
    -- `actus-schedule` itself. Before the fix this checked CLEAN: `main` saw the
    -- project `daydate` while `actus-schedule` quietly kept the embedded one.
    --
    -- The positive control is the `embedded-diamond` test above: the same
    -- embedded closure with no project override checks clean.
    let expectEmbeddedImporterSeesOverride label run =
          it label $ do
            Output code sout serr <- run
            case code of
              ExitFailure _ -> pure ()
              ExitSuccess -> expectationFailure $
                "Expected the embedded importer to be type-checked against the\
                \ project-local daydate override (and so to report an arity\
                \ error), but l4 exited 0 — one module name resolved to two\
                \ different sources in one build."
                ++ "\n--- stdout ---\n" ++ sout
                ++ "\n--- stderr ---\n" ++ serr
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

  -- Track S0: `l4 export --to=dmn|dmn-md|bpmn [--fidelity-report]`.
  --
  -- The interesting property of these goldens is that they are not new files.
  -- `jl4/tests/BpmnExport.hs` and `jl4/tests/DmnExport.hs` build the same
  -- artifacts through the library API (`checkWithImports`), and the CLI reaches
  -- them through a completely different front end (the LSP one-shot Shake
  -- pipeline). Byte equality across those two paths is the actual claim.
  describe "l4 export" $ do
    it "reproduces the BPMN golden byte-for-byte on stdout" $
      expectGolden bin ["export", "--to=bpmn", bpmnOfferingSource] bpmnOfferingGolden

    it "reproduces the DMN 1.3 XML golden byte-for-byte on stdout" $
      expectGolden bin ["export", "--to=dmn", dmnSource, "--model-name", dmnModelName]
                       dmnGolden

    it "reproduces the dmnmd markdown golden byte-for-byte on stdout" $
      expectGolden bin ["export", "--to=dmn-md", dmnSource, "--model-name", dmnModelName]
                       dmnMarkdownGolden

    it "writes the fidelity report as a sibling file, not into the document" $ do
      -- The goldens under examples/ are pairs (X.bpmn beside X.fidelity.txt),
      -- and that is the shape --output + --fidelity-report reproduces.
      tmp <- getTemporaryDirectory
      let outDir  = tmp </> "l4-export-sidecar"
          outFile = outDir </> "offering.bpmn"
          sidecar = outDir </> "offering.fidelity.txt"
      removePathForcibly outDir
      createDirectoryIfMissing True outDir
      Output code sout serr <- runL4 bin
        ["export", "--to=bpmn", bpmnOfferingSource, "-o", outFile, "--fidelity-report"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` null                       -- the document went to the file
      serr `shouldSatisfy` ("fidelity report written to" `isInfixOf`)
      xml <- readUtf8 outFile
      goldenXml <- readUtf8 bpmnOfferingGolden
      xml `shouldBe` goldenXml
      report <- readUtf8 sidecar
      goldenReport <- readUtf8 bpmnOfferingFidelity
      report `shouldBe` goldenReport
      -- Nothing of the report leaked into the document.
      xml `shouldSatisfy` (not . ("fidelity report" `isInfixOf`))
      removePathForcibly outDir

    it "keeps stdout a pure document when --fidelity-report goes to stderr" $ do
      -- `l4 export --to=bpmn f.l4 --fidelity-report > f.bpmn` must still
      -- produce an importable file.
      Output code sout serr <- runL4 bin
        ["export", "--to=bpmn", bpmnOfferingSource, "--fidelity-report"]
      code `shouldBe` ExitSuccess
      goldenXml <- readUtf8 bpmnOfferingGolden
      sout `shouldBe` goldenXml
      serr `shouldSatisfy` ("fidelity report — BPMN 2.0" `isInfixOf`)
      serr `shouldSatisfy` ("[F1]" `isInfixOf`)

    it "tallies what was lost on stderr even without --fidelity-report" $ do
      -- The report is not optional in spirit: an export never silently drops
      -- what the source said just because the caller did not know to ask.
      Output code _ serr <- runL4 bin ["export", "--to=bpmn", bpmnOfferingSource]
      code `shouldBe` ExitSuccess
      serr `shouldSatisfy` ("could not carry everything" `isInfixOf`)
      serr `shouldSatisfy` ("blocking" `isInfixOf`)
      serr `shouldSatisfy` ("--fidelity-report" `isInfixOf`)
      -- ... but the tally alone is not the located list.
      serr `shouldSatisfy` (not . ("lost:" `isInfixOf`))

    it "exits 0 on a Blocking note by default" $ do
      -- Blocking means "the target notation has no form for this", which is
      -- true of every realistic export (F1 fires for every task in every BPMN
      -- file). A gate that always fires would be no gate at all.
      Output code _ _ <- runL4 bin ["export", "--to=bpmn", bpmnOfferingSource]
      code `shouldBe` ExitSuccess

    it "exits non-zero on a Blocking note under --fail-on=blocking" $
      expectFail bin ["export", "--to=bpmn", bpmnOfferingSource, "--fail-on=blocking"]

    -- --fail-on is a THRESHOLD ("a note this severe or worse"), over a lattice
    -- ordered Blocking < Lossy < Advisory. `expectFail ... --fail-on=blocking`
    -- above cannot see the threshold at all: it is satisfied by any gate that
    -- trips on anything, and by one whose comparison runs backwards. The two
    -- fixtures below are the discriminating inputs — one report that is
    -- blocking-ONLY, one that is advisory-ONLY — so every gate value gets both
    -- a case that must trip and a case that must not.
    --
    -- Concretely: flip `tripsGate`'s `<=` to `>=` and the blocking-only
    -- `--fail-on=lossy`/`=advisory` rows go green→red; make the gate trip on
    -- any note regardless of severity and the advisory-only
    -- `--fail-on=blocking`/`=lossy` rows do.
    describe "--fail-on thresholds" $ do
      let dmnGate fixture gate = runL4 bin (["export", "--to=dmn", fixture] <> gate)
          exitsNonZero fixture gate = do
            Output code _ _ <- dmnGate fixture gate
            code `shouldSatisfy` (/= ExitSuccess)
          exitsZero fixture gate = do
            Output code _ _ <- dmnGate fixture gate
            code `shouldBe` ExitSuccess

      it "a blocking-only report is caught by every threshold" $ do
        -- `l4 export --to=dmn export-blocking-only.l4` reports 2 blocking,
        -- 0 lossy, 0 advisory: the pure-Blocking end of the lattice. Assert
        -- that first, so the rows below cannot go green for the wrong reason
        -- if the fixture's notes ever change severity.
        Output tally _ serr <- dmnGate exportBlockingOnlyFixture []
        tally `shouldBe` ExitSuccess
        serr `shouldSatisfy` ("2 blocking" `isInfixOf`)
        serr `shouldSatisfy` (not . ("lossy" `isInfixOf`))
        serr `shouldSatisfy` (not . ("advisory" `isInfixOf`))
        mapM_ (\g -> exitsNonZero exportBlockingOnlyFixture ["--fail-on=" ++ g])
          ["blocking", "lossy", "advisory"]

      it "an advisory-only report is caught by --fail-on=advisory and nothing stricter" $ do
        -- `l4 export --to=dmn export-advisory-only.l4` reports 1 advisory and
        -- nothing else. Notes ARE present throughout, so "exit 0" here means
        -- "no note reached the threshold", not "no notes".
        Output tally _ serr <- dmnGate exportAdvisoryOnlyFixture []
        tally `shouldBe` ExitSuccess
        serr `shouldSatisfy` ("1 advisory" `isInfixOf`)
        serr `shouldSatisfy` (not . ("blocking" `isInfixOf`))
        mapM_ (\g -> exitsZero exportAdvisoryOnlyFixture ["--fail-on=" ++ g])
          ["blocking", "lossy"]
        exitsNonZero exportAdvisoryOnlyFixture ["--fail-on=advisory"]

      it "--fail-on=none never trips, and is the default" $
        mapM_ (\fixture -> do
                 exitsZero fixture ["--fail-on=none"]
                 exitsZero fixture [])
          [exportBlockingOnlyFixture, exportAdvisoryOnlyFixture]

      -- Phase 4's population filter (§2.5.6 rule 3) routes uncalled
      -- regulative bodies out of the DRG; a module holding ONLY those now
      -- exports an empty model, which the CLI refuses loudly rather than
      -- writing a decision-free document. This is the behaviour change that
      -- retired export-two-rules.l4 from the blocking-only role above.
      it "refuses an all-regulative module as DMN (empty model after the population filter)" $
        expectFail bin ["export", "--to=dmn", exportTwoRulesFixture]

    -- FIXTURE(d)'s importer view must see a BACKTICKED import. A hyphenated
    -- module name can only be imported as IMPORT `interp-common`, and the
    -- textual sibling scan used to match only the bare spelling — so every
    -- hyphenated module (the whole housing-act/charities/reg-cf population)
    -- saw "no importers", returned Just Set.empty ("verified clear") instead
    -- of the fail-safe Nothing, and dropped its externally-called
    -- fixture-shaped decisions: the "delete a statute" case §2.5.7 names.
    -- `local sample` is the in-fixture negative control: same module-local
    -- shape, unreferenced by the importer, so it must still drop — proving
    -- the scan discriminates by name rather than failing open.
    it "keeps a fixture-shaped decision whose importer spells the IMPORT with backticks" $ do
      Output code sout _ <- runL4 bin ["export", "--to=dmn", importViewFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("decision_statute" `isInfixOf`)
      sout `shouldSatisfy` (not . ("local sample" `isInfixOf`))

    it "still writes the document when --fail-on trips" $ do
      Output code sout _ <- runL4 bin
        ["export", "--to=bpmn", bpmnOfferingSource, "--fail-on=blocking"]
      code `shouldSatisfy` (/= ExitSuccess)
      goldenXml <- readUtf8 bpmnOfferingGolden
      sout `shouldBe` goldenXml

    it "honours --deadline-unit=refuse (no invented ISO duration)" $ do
      Output code _ serr <- runL4 bin
        ["export", "--to=bpmn", bpmnOfferingSource, "--deadline-unit=refuse"]
      code `shouldBe` ExitSuccess
      -- Under the default the unitless WITHINs are read as days and reported as
      -- P-DEADLINE-UNIT advisories; under `refuse` they become P-DEADLINE.
      serr `shouldSatisfy` ("P-DEADLINE" `isInfixOf`)
      Output _ soutDefault _ <- runL4 bin ["export", "--to=bpmn", bpmnOfferingSource]
      Output _ soutRefuse  _ <- runL4 bin
        ["export", "--to=bpmn", bpmnOfferingSource, "--deadline-unit=refuse"]
      soutDefault `shouldSatisfy` ("timerEventDefinition" `isInfixOf`)
      soutRefuse `shouldSatisfy` (not . ("timerEventDefinition" `isInfixOf`))

    it "rejects an unknown --to with a message naming the accepted targets" $ do
      Output code _ serr <- runL4 bin ["export", "--to=xml", dmnSource]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("Invalid export target" `isInfixOf`)
      serr `shouldSatisfy` ("dmn|dmn-md|bpmn" `isInfixOf`)

    it "requires --to" $
      expectFail bin ["export", dmnSource]

    it "refuses BPMN when the module has no regulative rules" $ do
      Output code _ serr <- runL4 bin ["export", "--to=bpmn", exportNothingFixture]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("regulative" `isInfixOf`)

    it "refuses DMN when the module has no decisions" $ do
      Output code _ serr <- runL4 bin ["export", "--to=dmn", exportNothingFixture]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("No decisions found" `isInfixOf`)

    it "refuses to guess which process to draw, and names the candidates" $ do
      -- renderBpmn writes its own XML prolog, so two processes concatenated is
      -- not a document. Refusing beats emitting something no tool can read.
      Output code _ serr <- runL4 bin ["export", "--to=bpmn", exportTwoRulesFixture]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("--rule" `isInfixOf`)
      serr `shouldSatisfy` ("the filing" `isInfixOf`)
      serr `shouldSatisfy` ("the fee" `isInfixOf`)

    it "selects one process with --rule" $ do
      Output code sout _ <- runL4 bin
        ["export", "--to=bpmn", exportTwoRulesFixture, "--rule", "the fee"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("<?xml" `isInfixOf`)
      sout `shouldSatisfy` ("the fee" `isInfixOf`)
      sout `shouldSatisfy` (not . ("the filing" `isInfixOf`))

    it "fails on an unknown --rule and lists what is available" $ do
      Output code _ serr <- runL4 bin
        ["export", "--to=bpmn", exportTwoRulesFixture, "--rule", "no such rule"]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("no such rule" `isInfixOf`)
      serr `shouldSatisfy` ("the filing" `isInfixOf`)

    it "rejects --rule on a DMN export instead of ignoring it" $ do
      Output code _ serr <- runL4 bin ["export", "--to=dmn", dmnSource, "--rule", "x"]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("--rule" `isInfixOf`)
      serr `shouldSatisfy` ("--to=bpmn" `isInfixOf`)

    it "rejects --model-name on a BPMN export instead of ignoring it" $ do
      Output code _ serr <- runL4 bin
        ["export", "--to=bpmn", bpmnOfferingSource, "--model-name", "X"]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("--model-name" `isInfixOf`)

    it "fails on a file that does not typecheck" $
      expectFail bin ["export", "--to=dmn", errorFixture]

    -- --flavor (R7). The two flavors differ on exactly one construct, and that
    -- construct is not emitted until Phase 5, so today the flag is observable
    -- only in the fidelity report's target line. That is deliberate: the seam
    -- and its goldens land before the divergence does, so that when the
    -- divergence arrives it has somewhere to be checked.
    describe "--flavor" $ do
      it "defaults to camunda, and says so in the report rather than just 'DMN'" $ do
        Output code _ serr <- runL4 bin
          ["export", "--to=dmn", dmnSource, "--model-name", dmnModelName, "--fidelity-report"]
        code `shouldBe` ExitSuccess
        serr `shouldSatisfy` ("DMN 1.3 (XML), camunda flavor" `isInfixOf`)

      it "accepts kie, and drools as a synonym for it" $
        for_ ["kie", "drools"] \flavor -> do
          Output code _ serr <- runL4 bin
            [ "export", "--to=dmn", dmnSource, "--model-name", dmnModelName
            , "--flavor=" ++ flavor, "--fidelity-report" ]
          code `shouldBe` ExitSuccess
          serr `shouldSatisfy` ("DMN 1.3 (XML), kie flavor" `isInfixOf`)

      it "the flavors diverge on the §-invocation exhibit and nowhere else, through the CLI" $ do
        -- This test used to be the CLI half of the Phase 5 tripwire
        -- ("EXPECTED TO FAIL AT PHASE 5"); it fired on 2026-08-01 and was
        -- flipped as instructed: the goldens split (svc.kie.dmn beside
        -- svc.dmn) and the seam is asserted in both directions.
        --
        -- Positive direction: the kie bytes of the §-invocation exhibit carry
        -- a requiredKnowledge onto a decisionService; the camunda bytes do
        -- not (that one edge is fatal to Camunda 8's parse(), spec §13.4),
        -- and each equals its committed golden.
        Output _ svcCam _ <- runL4 bin ["export", "--to=dmn", svcSource]
        Output _ svcKie _ <- runL4 bin ["export", "--to=dmn", svcSource, "--flavor=kie"]
        svcKie `shouldSatisfy`
          ("<requiredKnowledge href=\"#service_special_assessment\"/>" `isInfixOf`)
        svcCam `shouldSatisfy` (not . ("requiredKnowledge href=\"#service_" `isInfixOf`))
        svcCamGolden <- readUtf8 svcGolden
        svcCam `shouldBe` svcCamGolden
        svcKieGolden <- readUtf8 svcKieDmnGolden
        svcKie `shouldBe` svcKieGolden
        -- Identity direction: reg-cf has no §-invocation, so its flavors stay
        -- byte-identical (measured 2026-08-01 over every golden subject) and
        -- both equal the one unsuffixed golden. A drift here means the flavor
        -- bit grew a second observable, which wants its own golden split.
        Output _ camunda _ <- runL4 bin
          ["export", "--to=dmn", dmnSource, "--model-name", dmnModelName, "--flavor=camunda"]
        Output _ kie _ <- runL4 bin
          ["export", "--to=dmn", dmnSource, "--model-name", dmnModelName, "--flavor=kie"]
        kie `shouldBe` camunda
        golden <- readUtf8 dmnGolden
        camunda `shouldBe` golden

      it "rejects --flavor on --to=dmn-md, because nothing on that path reads it" $ do
        -- It was admitted here at first, on the theory that "the flavor lives
        -- in the Drg, which both emitters read". It does not: emitMarkdown
        -- mentions no field of it and markdownReport hard-codes the target
        -- "dmnmd", so --flavor=kie produced a byte-identical document AND a
        -- byte-identical fidelity report. That is the silent ignore
        -- checkTargetFlags exists to refuse.
        Output code _ serr <- runL4 bin
          ["export", "--to=dmn-md", dmnSource, "--model-name", dmnModelName, "--flavor=kie"]
        code `shouldSatisfy` (/= ExitSuccess)
        serr `shouldSatisfy` ("--flavor" `isInfixOf`)
        serr `shouldSatisfy` ("--to=dmn-md" `isInfixOf`)
        serr `shouldSatisfy` ("--to=dmn" `isInfixOf`)

      it "still accepts --model-name on --to=dmn-md, which does belong to both" $ do
        Output code sout _ <- runL4 bin
          ["export", "--to=dmn-md", dmnSource, "--model-name", dmnModelName]
        code `shouldBe` ExitSuccess
        golden <- readUtf8 dmnMarkdownGolden
        sout `shouldBe` golden

      it "rejects --flavor on a BPMN export instead of ignoring it" $ do
        Output code _ serr <- runL4 bin
          ["export", "--to=bpmn", bpmnOfferingSource, "--flavor=kie"]
        code `shouldSatisfy` (/= ExitSuccess)
        serr `shouldSatisfy` ("--flavor" `isInfixOf`)
        serr `shouldSatisfy` ("--to=bpmn" `isInfixOf`)

      it "rejects an unknown flavor, naming the accepted ones" $ do
        Output code _ serr <- runL4 bin
          ["export", "--to=dmn", dmnSource, "--flavor=camunda7"]
        code `shouldSatisfy` (/= ExitSuccess)
        serr `shouldSatisfy` ("Invalid --flavor" `isInfixOf`)
        serr `shouldSatisfy` ("camunda|kie" `isInfixOf`)

  -- The two real DMN engines, over the shipped golden. See
  -- `dmnEngineCheck` below for the skip contract and why the assertion is on
  -- the harness's VERDICT banner rather than on its exit code.
  describe "DMN engine checks (opt-in: L4_DMN_ENGINE_CHECK=1)" $ do
    it "Drools/KIE 8.44.0.Final validates, builds and answers the golden correctly" $
      dmnEngineCheck "KIE" kieCheckScript "KIE_CHECK_REQUIRED" \out -> do
        -- The VERSION is asserted because the banner reports what the harness
        -- OBSERVED off the classpath (KieServices' implementation version), not
        -- a constant its launcher passed in. Without this the one token in the
        -- banner naming the engine would be unpinned.
        out `shouldSatisfy` ("KIE 8.44.0.Final VERDICT" `isInfixOf`)
        -- Not just "0 errors": the emitted names used to fire six
        -- ILLEGAL_USE_OF_NAME / ILLEGAL_USE_OF_TYPEREF warnings and then two
        -- hard errors, and the file did not build at all. Pinning the warning
        -- count here (rather than inside the harness, whose validator is known
        -- to over-report) means relaxing it takes a visible edit.
        out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
        out `shouldSatisfy` ("0 warning(s)" `isInfixOf`)
        out `shouldSatisfy` ("25/25 decision(s) SUCCEEDED" `isInfixOf`)
        -- ...and the part that is not a liveness claim. SUCCEEDED says every
        -- decision ran. Only this says each answered what reg-cf.cases.json
        -- says it must -- which is the check that catches a wrong NON-NULL
        -- answer, the shape the Camunda name misparse actually takes.
        out `shouldSatisfy` ("25/25 value(s) as expected" `isInfixOf`)

    it "Camunda 8.7.6 parses and answers the golden correctly" $
      dmnEngineCheck "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" \out -> do
        out `shouldSatisfy` ("Camunda 8.7.6 (zeebe-dmn) VERDICT" `isInfixOf`)
        -- Camunda 8 fails whole-file at parse(), so "1 parsed" is the load-bearing
        -- claim; the golden used to be rejected outright.
        out `shouldSatisfy` ("1 parsed" `isInfixOf`)
        out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
        out `shouldSatisfy` ("25/25 decision(s) evaluated" `isInfixOf`)
        out `shouldSatisfy` ("25/25 value(s) as expected" `isInfixOf`)

    -- The CORPUS leg (R12/R13, spec §15.12/§16): the whole 67-decision Reg CF
    -- corpus builds and answers on both engines, over TWENTY cases — the base
    -- world, the 15 dated cases that relocate the rule-date-rebinding fixtures
    -- R12 dropped (ruling R-C, spec §15.12.1: "the model owns the law under a
    -- date; the harness owns the dates"), and the 4 seed cases that close the
    -- total-assets and restricted-period leaves the §8 diff oracle reported
    -- structurally inert. 20 x 67 = 1340. All counts below are MEASURED
    -- (2026-08-03, this machine, both harnesses), not aspirational: before
    -- R12/R13 KIE refused with 16 build errors and Camunda refused the file at
    -- parse() on the raw-L4 deontic body.
    it "KIE builds and answers the whole Reg CF corpus (R12/R13)" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustPass
        corpusGolden [corpusGolden, "--cases", corpusEngineCases] \out -> do
          out `shouldSatisfy` ("KIE 8.44.0.Final VERDICT" `isInfixOf`)
          out `shouldSatisfy` ("20 case(s)" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("0 warning(s)" `isInfixOf`)
          out `shouldSatisfy` ("1340/1340 decision(s) SUCCEEDED" `isInfixOf`)
          out `shouldSatisfy` ("1340/1340 value(s) as expected" `isInfixOf`)
          -- the SVC leg is a value check since 2026-08-02 (each service fed
          -- its inputDecisions' computed values, each outputDecision compared
          -- against the same expect entry): 7 services, 14 declared outputs,
          -- per case
          out `shouldSatisfy` ("280/280 service output value(s) as expected" `isInfixOf`)

    it "Camunda parses and answers the whole Reg CF corpus (R12/R13)" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustPass
        corpusGolden [corpusGolden, "--cases", corpusEngineCases] \out -> do
          out `shouldSatisfy` ("Camunda 8.7.6 (zeebe-dmn) VERDICT" `isInfixOf`)
          out `shouldSatisfy` ("20 case(s)" `isInfixOf`)
          out `shouldSatisfy` ("1 parsed" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("1340/1340 decision(s) evaluated" `isInfixOf`)
          out `shouldSatisfy` ("1340/1340 value(s) as expected" `isInfixOf`)

  -- The LAW-TIME legs (spec §15). What is being asserted here that nothing
  -- else asserts: the SAME model answers DIFFERENTLY for different rule dates,
  -- in a real engine, driven only by half-open date intervals on a UNIQUE
  -- table. `60/60 value(s) as expected` over ten cases is the claim -- ten rule
  -- dates x six decisions (Phase 5 moved the seventh, `the rules in force
  -- include`, to a businessKnowledgeModel, which the cases schema cannot
  -- assert -- its logic is exercised through the interval endpoints D2 inlined
  -- it into) -- and seven of those ten cases exist purely to pin the interval
  -- convention: a day-of/day-before pair on each of the three seams, plus a
  -- rule date well before commencement.
  describe "law time on a date axis (opt-in: L4_DMN_ENGINE_CHECK=1)" $ do
    it "KIE answers the dated-regime exhibit correctly for ten rule dates" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustPass
        gstGolden [gstGolden, "--cases", gstEngineCases] \out -> do
          out `shouldSatisfy` ("KIE 8.44.0.Final VERDICT" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          -- zero warnings is load-bearing: the emitted BKM must carry its
          -- DMNShape, or KIE raises WARN [DMNDI_MISSING_DIAGRAM] (measured
          -- 2026-08-01; the shape row above the decisions exists for this).
          out `shouldSatisfy` ("0 warning(s)" `isInfixOf`)
          out `shouldSatisfy` ("60/60 decision(s) SUCCEEDED" `isInfixOf`)
          out `shouldSatisfy` ("60/60 value(s) as expected" `isInfixOf`)

    it "Camunda answers the dated-regime exhibit correctly for ten rule dates" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustPass
        gstGolden [gstGolden, "--cases", gstEngineCases] \out -> do
          out `shouldSatisfy` ("Camunda 8.7.6 (zeebe-dmn) VERDICT" `isInfixOf`)
          out `shouldSatisfy` ("1 parsed" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("60/60 decision(s) evaluated" `isInfixOf`)
          out `shouldSatisfy` ("60/60 value(s) as expected" `isInfixOf`)

    -- The hand-written probe PAIR. It is NOT redundant with the exhibit above:
    -- the emitter cannot generate an <annotationEntry> carrying an @id, so only
    -- a fixture can ask whether Xerces objects to one -- and only the NEGATIVE
    -- half can show that it does. Same rationale, and the same construction, as
    -- the dmn-xsd-order pair.
    it "the date-axis probe pair differs ONLY in the @id on the annotationEntry" $ do
      pos <- readUtf8 dateProbeModel
      neg <- readUtf8 dateProbeNegative
      -- The headers differ (each says why its own file exists), so compare from
      -- <definitions> down. Without this the negative could drift and a red run
      -- would no longer isolate the @id as the cause.
      -- `<definitions xmlns` and not `<definitions`: each header comment names
      -- the element in prose, and matching the prose made the negative's body
      -- start inside its own comment.
      let body = dropWhile (not . isInfixOf "<definitions xmlns") . lines
          isAE = isInfixOf "<annotationEntry"
      filter (not . isAE) (body pos) `shouldBe` filter (not . isAE) (body neg)
      filter isAE (body pos) `shouldSatisfy` all (not . isInfixOf "id=")
      filter isAE (body neg) `shouldSatisfy` \ls ->
        not (null ls) && all (isInfixOf "id=") ls

    it "KIE (Xerces) accepts the annotation elements and the date-interval cells" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustPass
        dateProbeModel [dateProbeModel, "--cases", dateProbeCases] \out -> do
          out `shouldSatisfy` ("XSD    valid" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("6/6 value(s) as expected" `isInfixOf`)

    it "KIE (Xerces) REJECTS an @id on the annotationEntry, naming the rule" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustFail
        dateProbeNegative [dateProbeNegative, "--cases", dateProbeCases] \out -> do
          out `shouldSatisfy` ("XSD    INVALID" `isInfixOf`)
          out `shouldSatisfy` ("cvc-complex-type.3.2.2" `isInfixOf`)
          out `shouldSatisfy` ("'id' is not allowed to appear in element 'annotationEntry'"
                                 `isInfixOf`)
          -- MEASURED, and the reason the negative earns its keep: KIE 8.44
          -- BUILDS the file anyway and answers all three cases correctly. The
          -- schema leg is the only thing objecting -- exactly as with the
          -- itemDefinition pair.
          out `shouldSatisfy` ("BUILD  clean" `isInfixOf`)
          out `shouldSatisfy` ("6/6 value(s) as expected" `isInfixOf`)

    it "Camunda evaluates the hand-written date axis" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustPass
        dateProbeModel [dateProbeModel, "--cases", dateProbeCases] \out -> do
          out `shouldSatisfy` ("1 parsed" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("6/6 value(s) as expected" `isInfixOf`)

    -- Camunda 8 is stricter than Drools here: it does not merely flag the file,
    -- it refuses to parse it at all.
    it "Camunda 8 REJECTS the same file outright, at parse" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustFail
        dateProbeNegative [dateProbeNegative, "--cases", dateProbeCases] \out -> do
          out `shouldSatisfy` ("PARSE  INVALID" `isInfixOf`)
          out `shouldSatisfy` ("0 parsed, 1 error(s)" `isInfixOf`)

  -- H4. The permanent record that the HYDRATION idiom is portable, and the
  -- tripwire for an engine upgrade that changes the answer. The emitter's own
  -- hydration output is measured separately (the `hydration.l4` golden subject
  -- through both engines); this fixture is the idiom in isolation, so a red run
  -- here isolates the ENGINE and a red run there isolates the EMITTER.
  describe "the hydration idiom (opt-in: L4_DMN_ENGINE_CHECK=1)" $ do
    it "KIE evaluates a boxed context whose entries read earlier siblings" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustPass
        hydrationProbeModel [hydrationProbeModel, "--cases", hydrationProbeCases] \out -> do
          out `shouldSatisfy` ("XSD    valid" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          -- Zero warnings is part of the measurement, not decoration: KIE warns
          -- on plenty it still evaluates, and the claim being pinned is that
          -- this idiom is unremarkable to the engine, not merely tolerated.
          out `shouldSatisfy` ("0 warning(s)" `isInfixOf`)
          out `shouldSatisfy` ("6/6 value(s) as expected" `isInfixOf`)

    it "Camunda (zeebe-dmn) evaluates the same boxed context" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustPass
        hydrationProbeModel [hydrationProbeModel, "--cases", hydrationProbeCases] \out -> do
          out `shouldSatisfy` ("1 parsed" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("6/6 value(s) as expected" `isInfixOf`)

  -- The EMITTER's hydration output through both engines. This is the leg that
  -- turns §4.4 from a design into a measurement: 40 decision values per engine,
  -- over an artifact jl4-core/src/L4/Dmn/Lower.hs produced.
  --
  -- Case D supplies a NULL source record, which is the one input shape under
  -- which D-COMPUTEDFIELD's "nothing an engine needs is lost" could have been
  -- engine-visibly wrong. Both engines agree exactly, and the answer is not the
  -- obvious one -- `band` comes back 1, not null -- so it is measured rather
  -- than reasoned about. See hydration.cases.json's own note and §4.4.6.
  describe "emitted hydration (opt-in: L4_DMN_ENGINE_CHECK=1)" $ do
    it "KIE evaluates the emitted hydrators, their sources and their readers" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustPass
        hydrationGolden [hydrationGolden, "--cases", hydrationEngineCases] \out -> do
          out `shouldSatisfy` ("XSD    valid" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("0 warning(s)" `isInfixOf`)
          out `shouldSatisfy` ("40/40 value(s) as expected" `isInfixOf`)

    it "Camunda evaluates the same emitted model" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustPass
        hydrationGolden [hydrationGolden, "--cases", hydrationEngineCases] \out -> do
          out `shouldSatisfy` ("1 parsed" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("40/40 value(s) as expected" `isInfixOf`)

    -- The COUNTERPART, and it is not a consolation prize. `sumtype.dmn` is the
    -- exhibit of what the exporter REFUSES, and R4-a's refusal emits L4 source
    -- by design -- so an engine must reject it, and until this leg existed
    -- nothing in the repo said so. `grep -n sumtype jl4/tests-cli/Main.hs`
    -- returned nothing before 2026-07-31: no engine had ever looked at this
    -- file. So this is coverage that never existed, not a defect retired.
    --
    -- It goes RED if someone "fixes" `stated term`, which is the point: the
    -- refusal is now a measurement rather than an argument.
    it "KIE REJECTS the refusal exhibit, and names the payload projection" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustFail
        sumtypeGolden [sumtypeGolden] \out -> do
          -- Not a schema failure: the file is valid DMN. It is the FEEL that
          -- cannot compile, which is exactly what a Blocking note claims.
          out `shouldSatisfy` ("XSD    valid" `isInfixOf`)
          -- ★ Assert the CAUSE, not merely that the id appears. Every decision
          -- id shows up in KIE's per-decision listing on any run, pass or fail,
          -- so `"decision_stated_term" isInfixOf out` -- which is all this leg
          -- asserted when it was written -- carries no information about WHY
          -- the run failed, and a change that made the file fail for an
          -- entirely different reason would have kept it green.
          out `shouldSatisfy` ("ERR_COMPILING_FEEL" `isInfixOf`)
          out `shouldSatisfy` ("decision_stated_term_literal" `isInfixOf`)
          out `shouldSatisfy` ("Unknown variable 'disposal.term_in_years'" `isInfixOf`)
          out `shouldSatisfy` ("<<< FAILED" `isInfixOf`)
          -- A SECOND, independent error, measured 2026-07-31 and recorded here
          -- rather than tidied away: KIE resolves itemDefinition typeRefs in
          -- DOCUMENT ORDER, and `itemdef_claim`'s `assessed grade` component
          -- points at `Grade_optional`, which this emitter appends AFTER the
          -- definitions that reference it. Pre-existing (HEAD's sumtype.dmn has
          -- the same ordering) and previously unmeasured, because no engine had
          -- ever looked at this file. It is confined to the `_optional` alias
          -- machinery and `sumtype.dmn` is the only DMN golden that uses it, so
          -- it changes no MustPass leg -- but it is a real portability defect
          -- and pinning it here is what stops it being lost. See §11-R8-a.
          out `shouldSatisfy` ("TYPE_DEF_NOT_FOUND" `isInfixOf`)
          out `shouldSatisfy` ("Grade_optional" `isInfixOf`)

  -- Tier 1 of the Phase 5 evidence: the 23 hand-written BKM/service probes,
  -- exactly per DMN-PHASE5-BUILD-PLAN.md §1's matrix. See 'bkmProbeMatrix'
  -- for what the asymmetry means and what a flip would say. What is asserted
  -- per leg is the VERDICT banner (the harness RAN) and the exit direction
  -- (the measured outcome); the value-level detail lives in each fixture's
  -- own cases file and MEASURED header. NOTE the recorded harness limitation
  -- (spec §13.6): `expect` keys on DECISION names only, so a BKM's or a
  -- service's own return value is never compared directly — every probe
  -- asserts invocables through caller decisions, deliberately.
  describe "the 23 BKM/service probes (opt-in: L4_DMN_ENGINE_CHECK=1)" $
    for_ bkmProbeMatrix \(label, stem, kieOutcome, camOutcome) -> do
      let model = dmnBkmProbeDir </> (stem <> ".dmn")
          cases = dmnBkmProbeDir </> (stem <> ".cases.json")
      it (label <> " " <> stem <> ": KIE " <> outcomeWord kieOutcome) $
        dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" kieOutcome
          model [model, "--cases", cases] \out ->
            out `shouldSatisfy` ("KIE 8.44.0.Final VERDICT" `isInfixOf`)
      it (label <> " " <> stem <> ": Camunda " <> outcomeWord camOutcome) $
        dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" camOutcome
          model [model, "--cases", cases] \out ->
            out `shouldSatisfy` ("Camunda 8.7.6 (zeebe-dmn) VERDICT" `isInfixOf`)

  -- The Phase 5 EMITTED-BKM legs (spec §6.2, §13.6): the emitter's own BKM
  -- output through both engines, the strictly-stronger counterpart of the 23
  -- hand-written dmn-bkm-probe fixtures — a red probe isolates the ENGINE, a
  -- red run here isolates the LOWERING. Each leg names its flavor; an absent
  -- harness reports UNEXERCISED (pendingWith) rather than passing.
  describe "the Phase 5 BKM exhibit (opt-in: L4_DMN_ENGINE_CHECK=1)" $ do
    it "KIE evaluates the emitted BKMs: chain, hydrator call, lifted closure (camunda golden)" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustPass
        bkmDmnGolden [bkmDmnGolden, "--cases", bkmEngineCases] \out -> do
          out `shouldSatisfy` ("XSD    valid" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          -- zero warnings pins the DMNDI contract: every BKM has a DMNShape
          -- and every knowledgeRequirement a DMNEdge (KIE warns
          -- DMNDI_MISSING_DIAGRAM for each omission — measured 2026-08-01).
          out `shouldSatisfy` ("0 warning(s)" `isInfixOf`)
          out `shouldSatisfy` ("14/14 decision(s) SUCCEEDED" `isInfixOf`)
          out `shouldSatisfy` ("14/14 value(s) as expected" `isInfixOf`)

    it "Camunda evaluates the same bytes (the flavors are byte-identical here, by measurement)" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustPass
        bkmDmnGolden [bkmDmnGolden, "--cases", bkmEngineCases] \out -> do
          out `shouldSatisfy` ("1 parsed" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("14/14 decision(s) evaluated" `isInfixOf`)
          out `shouldSatisfy` ("14/14 value(s) as expected" `isInfixOf`)

  -- The §-invocation exhibit: the ONE construct on which the flavors emit
  -- different bytes (§13.5), so each golden meets exactly one engine, in
  -- opposite directions. The asymmetry IS the flavor axis.
  describe "the §-invocation exhibit (opt-in: L4_DMN_ENGINE_CHECK=1)" $ do
    it "KIE executes the kie golden: the service invocation binds per call" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustPass
        svcKieDmnGolden [svcKieDmnGolden, "--cases", svcEngineCases] \out -> do
          out `shouldSatisfy` ("XSD    valid" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("0 warning(s)" `isInfixOf`)
          -- case B is the load-bearing pair: special_rate (standalone,
          -- global-bound) answers 5 while special_case (through the service,
          -- invocation-bound) answers 195 — the invocation carries its OWN
          -- bindings, which is the whole point of an invocable §.
          out `shouldSatisfy` ("8/8 decision(s) SUCCEEDED" `isInfixOf`)
          out `shouldSatisfy` ("8/8 value(s) as expected" `isInfixOf`)

    it "Camunda REJECTS the camunda golden at parse: the refused call site is raw L4, loudly noted" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustFail
        svcGolden [svcGolden, "--cases", svcEngineCases] \out -> do
          -- The camunda flavor cannot emit the KR→service edge (fatal to
          -- parse(), §13.4), so `special case` stays verbatim and zeebe-dmn
          -- refuses the file. The loudness lives in the FIDELITY report
          -- (D-FLAVOR-NOSERVICE, Blocking) — this leg pins that the artifact
          -- itself is not silently degraded into something that half-loads.
          out `shouldSatisfy` ("PARSE  INVALID" `isInfixOf`)
          out `shouldSatisfy` ("0 parsed, 1 error(s)" `isInfixOf`)


  -- R8-d′'s evidence. Written and MEASURED before the MAYBE→null lowering
  -- existed, because the ruling is only safe if `=` against null is a proper
  -- boolean on both engines. It is. See the fixture headers for the fallback
  -- that was pre-declared in case it had not been.
  describe "FEEL null semantics (opt-in: L4_DMN_ENGINE_CHECK=1)" $ do
    it "KIE: comparison against null is boolean, and a table may default to null" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustPass
        nullProbeModel [nullProbeModel, "--cases", nullProbeCases] \out -> do
          out `shouldSatisfy` ("XSD    valid" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          -- The single-output table carries no @name and no @typeRef on its
          -- <output>, matching what Emit.hs emits; carrying them draws two
          -- ILLEGAL_USE_OF_* warnings, so zero here is also a statement that
          -- the probe is written in the emitter's shape.
          out `shouldSatisfy` ("0 warning(s)" `isInfixOf`)
          out `shouldSatisfy` ("15/15 value(s) as expected" `isInfixOf`)

    it "Camunda: same five questions, same five answers" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustPass
        nullProbeModel [nullProbeModel, "--cases", nullProbeCases] \out -> do
          out `shouldSatisfy` ("1 parsed" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("15/15 value(s) as expected" `isInfixOf`)

    -- The ONE null question the engines answer differently, asserted in both
    -- directions. A shared expectation would have had to pick a side and would
    -- then have read as a bug in the other.
    it "Camunda treats a name that was never supplied as null" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustPass
        nullAbsentModel [nullAbsentModel, "--cases", nullAbsentCases] \out -> do
          out `shouldSatisfy` ("1 parsed" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("1/1 value(s) as expected" `isInfixOf`)

    it "KIE calls the same thing a model error and SKIPS the decision" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustFail
        nullAbsentModel [nullAbsentModel, "--cases", nullAbsentCases] \out -> do
          out `shouldSatisfy` ("Required dependency 'r' not found" `isInfixOf`)
          out `shouldSatisfy` ("SKIPPED" `isInfixOf`)
          out `shouldSatisfy` ("0/1 decision(s) SUCCEEDED" `isInfixOf`)
          -- It is a RUNTIME divergence, not a schema or build one: the file is
          -- perfectly valid and KIE builds it without complaint.
          out `shouldSatisfy` ("XSD    valid" `isInfixOf`)
          out `shouldSatisfy` ("BUILD  clean" `isInfixOf`)

  -- The placement rule's NEGATIVE control (spec §4.3, §9). Everything else in
  -- this file asserts that a gate stays green, which on its own says nothing
  -- about whether the gate is connected: an emitter that put
  -- <itemDefinition> after <inputData> passed every check in the tree —
  -- xmllint, dmn-moddle, the goldens — until these two files existed.
  describe "the XSD sequence-order gate (DMN 1.3 tDefinitions is a sequence)" $ do
    it "the committed pair differs ONLY in where the itemDefinition block sits" $ do
      pos <- readUtf8 dmnXsdOrderPositive
      neg <- readUtf8 dmnXsdOrderNegative
      -- Same lines, permuted. Without this the two files could drift apart and
      -- a red negative would no longer isolate placement as the cause.
      sort (lines pos) `shouldBe` sort (lines neg)
      pos `shouldNotBe` neg
      -- The needles carry the @ id=@ so they match the ELEMENTS and not the
      -- files' own header comment, which names both tags in prose. (It did
      -- match the comment at first, and the negative assertion duly failed on
      -- line 5.)
      firstLineWith "<itemDefinition id=" pos
        `shouldSatisfy` (< firstLineWith "<inputData id=" pos)
      firstLineWith "<itemDefinition id=" neg
        `shouldSatisfy` (> firstLineWith "<inputData id=" neg)

    it "Drools/KIE ACCEPTS those lines with the itemDefinition first" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustPass
        dmnXsdOrderPositive [dmnXsdOrderPositive, "--cases", dmnXsdOrderCases] \out -> do
          out `shouldSatisfy` ("XSD    valid" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s), 0 warning(s)" `isInfixOf`)
          out `shouldSatisfy` ("2/2 value(s) as expected" `isInfixOf`)

    it "Drools/KIE REJECTS the misordered file, naming the schema rule" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustFail
        dmnXsdOrderNegative [dmnXsdOrderNegative, "--cases", dmnXsdOrderCases] \out -> do
          out `shouldSatisfy` ("XSD    INVALID" `isInfixOf`)
          out `shouldSatisfy` ("cvc-complex-type.2.4.a" `isInfixOf`)
          -- MEASURED, and the reason the fixture earns its keep: KIE 8.44
          -- BUILDS the misordered file and answers both cases correctly. Only
          -- the schema legs object. So "a misordered emitter fails in the
          -- engine" is NOT true of Drools — the schema check is the only thing
          -- between a misordered emitter and a shipped artifact, which is
          -- precisely why it has to be the gate.
          out `shouldSatisfy` ("BUILD  clean" `isInfixOf`)
          out `shouldSatisfy` ("2/2 value(s) as expected" `isInfixOf`)

    it "Camunda 8 ACCEPTS those lines with the itemDefinition first" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustPass
        dmnXsdOrderPositive [dmnXsdOrderPositive, "--cases", dmnXsdOrderCases] \out -> do
          out `shouldSatisfy` ("1 parsed, 0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("2/2 value(s) as expected" `isInfixOf`)

    it "Camunda 8 REJECTS the misordered file outright, at parse" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustFail
        dmnXsdOrderNegative [dmnXsdOrderNegative, "--cases", dmnXsdOrderCases] \out -> do
          out `shouldSatisfy` ("PARSE  INVALID" `isInfixOf`)
          out `shouldSatisfy` ("0 parsed, 1 error(s)" `isInfixOf`)

  -- The engine-INTERSECTION triple (spec §6 measured note, 2026-07-30). What
  -- it pins: the two-engine-portable spellings of a per-element predicate are
  -- an opaque inline `satisfies` string or a BKM — NOTHING in between. The
  -- boxed-context placement is schema-valid DMN 1.3 (Xerces and KIE's
  -- validator both take it) that zeebe-dmn cannot parse, so "schema-valid"
  -- and "portable" are different properties, measured on the same file.
  describe "the engine-intersection triple (per-element predicate as a table)" $ do
    it "KIE accepts the inline control, warning-free" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustPass
        spouseInlineDmn [spouseInlineDmn, "--cases", spouseCases] \out -> do
          out `shouldSatisfy` ("0 error(s), 0 warning(s)" `isInfixOf`)
          out `shouldSatisfy` ("5/5 value(s) as expected" `isInfixOf`)

    it "Camunda 8 accepts the inline control" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustPass
        spouseInlineDmn [spouseInlineDmn, "--cases", spouseCases] \out -> do
          out `shouldSatisfy` ("1 parsed, 0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("5/5 value(s) as expected" `isInfixOf`)

    -- The one warning is pinned BY NAME because it is a finding, not noise:
    -- MISSING_TYPE_REF asks for the type of `eligible`, and the type it wants
    -- is the function type Spouse -> boolean — which DMN's itemDefinition
    -- language cannot spell. "No function types on the edges", stated by the
    -- vendor's own validator.
    it "KIE accepts the boxed-context table, with exactly the unspellable-type warning" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustPass
        spouseContextTableDmn [spouseContextTableDmn, "--cases", spouseCases] \out -> do
          out `shouldSatisfy` ("0 error(s), 1 warning(s)" `isInfixOf`)
          out `shouldSatisfy` ("MISSING_TYPE_REF" `isInfixOf`)
          out `shouldSatisfy` ("5/5 value(s) as expected" `isInfixOf`)

    -- UPGRADE RISK, wired on purpose. If a future zeebe-dmn bump LEARNS to
    -- parse a decision table inside a context entry, HarnessMustFail turns
    -- this test red — and that red is good news, not a regression: the engine
    -- intersection has widened. Flip this expectation to HarnessMustPass and
    -- update the two write-ups that cite the split (the fixture's own header
    -- and the §6 measured note), then reconsider whether BKM emission is
    -- still the ONLY portable route to an analyzable per-element predicate.
    it "Camunda 8 REJECTS the boxed-context table at parse — the pinned negative" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustFail
        spouseContextTableDmn [spouseContextTableDmn, "--cases", spouseCases] \out -> do
          out `shouldSatisfy` ("PARSE  INVALID" `isInfixOf`)
          out `shouldSatisfy` ("expected literal expression" `isInfixOf`)
          out `shouldSatisfy` ("0 parsed, 1 error(s)" `isInfixOf`)

    it "KIE accepts the BKM table, warning-free" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustPass
        spouseBkmTableDmn [spouseBkmTableDmn, "--cases", spouseCases] \out -> do
          out `shouldSatisfy` ("0 error(s), 0 warning(s)" `isInfixOf`)
          out `shouldSatisfy` ("5/5 value(s) as expected" `isInfixOf`)

    it "Camunda 8 accepts the BKM table — the only portable tabular predicate" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustPass
        spouseBkmTableDmn [spouseBkmTableDmn, "--cases", spouseCases] \out -> do
          out `shouldSatisfy` ("1 parsed, 0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("5/5 value(s) as expected" `isInfixOf`)

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
