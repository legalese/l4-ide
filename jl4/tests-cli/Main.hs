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
import Data.List (findIndex, isInfixOf, isPrefixOf, sort)
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
  , copyFile
  , createDirectoryIfMissing
  , createFileLink
  , doesDirectoryExist
  , doesFileExist
  , getTemporaryDirectory
  , listDirectory
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

import qualified L4.Docassemble.Emit as DAEmit

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

-- | Assert @l4 verify@ exits 1 on a fixture AND names the expected finding
-- kind. Both halves are needed: exit 1 alone would be satisfied by a fixture
-- that fails to typecheck, which would make the negative control a control over
-- nothing.
expectVerifyFinding :: FilePath -> FilePath -> String -> IO ()
expectVerifyFinding bin fixture kind = do
  Output code sout serr <- runL4 bin ["verify", fixture, "--format", "json"]
  case code of
    ExitFailure 1 -> pure ()
    other -> expectationFailure $
      "Expected exit 1 (findings present) but got " ++ show other
      ++ "\n--- stdout ---\n" ++ sout ++ "\n--- stderr ---\n" ++ serr
  unless (("\"" ++ kind ++ "\"") `isInfixOf` sout) $
    expectationFailure $
      "Expected a " ++ show kind ++ " finding in the JSON envelope"
      ++ "\n--- stdout ---\n" ++ sout

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

-- | R12's sharpest failure mode: a @.blawx@ row whose @xml_content@ is empty
-- while its @scasp_encoding@ is not.
--
-- Blawx draws a workspace only @if (output_object.xml_content)@
-- (@buttons.js:444@; a falsy value leaves the canvas cleared by @:441@) and
-- its Save writes @sCASP.workspaceToCode(demoWorkspace)@ straight back
-- (@:22-24@) — so opening such a row and saving DELETES the rule. The
-- headless fixpoint harness (@etc\/blawx-fixpoint-harness.mjs@) fails on the
-- same condition, but it is optional-when-present; this is the copy that runs
-- in CI on every event.
--
-- Both halves are asserted: the pairing in the emitted stream, and the
-- absence of the emitter's own stderr diagnostic for it.
noBlankedBlawxRow :: FilePath -> String -> IO ()
noBlankedBlawxRow bin stem = do
  Output code sout serr <- runL4 bin ["blawx", "examples/blawx/" ++ stem ++ ".l4"]
  code `shouldBe` ExitSuccess
  (stem, "no Blockly image" `isInfixOf` serr) `shouldBe` (stem, False)
  let fields = [f | l <- lines sout, Just f <- [blawxStoredField l]]
      traps =
        [ stem
        | (("xml_content", "''"), ("scasp_encoding", v)) <- zip fields (drop 1 fields)
        , v /= "''"
        ]
  traps `shouldBe` []

-- | An @ASSUME@-shaped seed and its record-spelled semantic twin must emit the
-- SAME s(CASP): same ontology, same rule stack, byte for byte, apart from the
-- first line — the generator's provenance comment, which names the source file
-- and is expected to differ.
--
-- This is the load-bearing property behind the tier-1 oracle for an
-- @ASSUME@-shaped module. Such a module has no evaluable directive at all
-- (@ASSUME@ is uninterpreted, and @lowerQuery@ builds a scenario only out of a
-- record-literal query argument), so the harness takes its expectations from the
-- twin, whose @#EVAL@s DO run under @l4 run@, and replays the twin's fact rows
-- against the @ASSUME@ seed's own workspaces. That replay only means anything
-- while the two spellings share their atoms — otherwise every replayed query
-- finds no model and every FALSE expectation "passes". Asserting it here makes
-- a drifting field name a red test rather than a quietly weaker harness.
twinsAgree :: FilePath -> (String, String) -> IO ()
twinsAgree bin (seed, twin) = do
  Output codeA soutA _ <- runL4 bin ["blawx", "examples/blawx/" ++ seed ++ ".l4", "--scasp"]
  Output codeB soutB _ <- runL4 bin ["blawx", "examples/blawx/" ++ twin ++ ".l4", "--scasp"]
  codeA `shouldBe` ExitSuccess
  codeB `shouldBe` ExitSuccess
  let body = drop 1 . lines
  (seed, body soutA) `shouldBe` (seed, body soutB)

-- | @    xml_content: |-@ → @Just ("xml_content","|-")@. Four-space indent
-- exactly, so the six-space block-scalar content lines (which are full of
-- colons — @xmlns=\"http:\/\/…\"@) cannot masquerade as fields.
blawxStoredField :: String -> Maybe (String, String)
blawxStoredField l
  | not ("    " `isPrefixOf` l) || "     " `isPrefixOf` l = Nothing
  | otherwise = case break (== ':') (drop 4 l) of
      (k, ':' : v) | k `elem` ["xml_content", "scasp_encoding"] ->
        Just (k, dropWhile (== ' ') v)
      _ -> Nothing

-- | Index of the first line containing a needle.
--
-- An ABSENT needle yields 'maxBound' rather than a negative sentinel, so it
-- sorts LAST: a fixture that lost its @\<itemDefinition\>@ altogether then
-- fails the \"before\" assertion instead of vacuously satisfying it.
firstLineWith :: String -> String -> Int
firstLineWith needle = fromMaybe maxBound . findIndex (needle `isInfixOf`) . lines

-- | Parse the stdout of a --json run as a JSON envelope.
--
-- Re-encodes as UTF-8 rather than using @BSL8.pack@, which truncates each Char
-- to eight bits: an em-dash in a decision name (regcf is full of them) came back
-- as byte 0x14 and aeson rejected it as a control character inside a string
-- literal. Every envelope this suite parsed before was ASCII, so the bug was
-- latent until a JSON mode started echoing corpus identifiers.
jsonEnvelope :: FilePath -> [String] -> IO Value
jsonEnvelope bin args = do
  Output _ sout _ <- runL4 bin args
  case eitherDecode (BSL8.fromStrict (TE.encodeUtf8 (T.pack sout))) of
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

-- | Three zero-arity DECIDEs (mainline -> baseline; deadwood unreachable) and
-- one #EVAL, so slices and surplusage are both observable; and a module with
-- no definitions at all, for the degenerate-graph exit-code pin.
graphFixture, graphEmptyFixture :: FilePath
graphFixture      = fixtureDir </> "graph.l4"
graphEmptyFixture = fixtureDir </> "graph-empty.l4"

----------------------------------------------------------------------------
-- `l4 docassemble` (M2): the package tree, citations and the glossary
--
-- Everything in this section pins DOCASSEMBLE-EXPORT-SPEC.md §10 (M2) and the
-- two rulings it leans on, R11 (§8.11, artifact shape) and R9 (§8.9, emission
-- hygiene). The M1 surface — six byte-golden examples plus the not-ok/
-- refusals — is pinned separately, in `describe "l4 docassemble"`, and must
-- stay green through M2: packaging is an ADDITIONAL artifact shape, not a
-- change to the bare one.
----------------------------------------------------------------------------

daExampleDir :: FilePath
daExampleDir = "examples/docassemble"

-- | The M2 example: three sub-decisions, each with a statutory @\@ref@,
-- conjoined by AND so a FALSE first conjunct short-circuits the other two
-- away. Its second citation uses the inline @\<\< \>\>@ ref form and its third
-- is deliberately Mako-hostile.
daCitationsSource :: FilePath
daCitationsSource = daExampleDir </> "citations.l4"

-- | Every example with a committed @.yml@ and @.fidelity.txt@ golden under
-- @examples/docassemble/expected/@: the six from M1, @citations@ from M2, and
-- the six M4 examples. Each RED phase deliberately left its own goldens
-- unwritten (\"writing a golden before the feature exists would force the
-- implementer to match formatting choices I have no basis to decide\") and each
-- GREEN phase supplied them once the shape was settled.
daBareExamples :: [String]
daBareExamples =
  [ "rodents-and-vermin", "seam", "enum-triage"
  , "defaults", "computed-and-shadow", "assume-via-fn", "citations"
  , "tenant-list", "payload-enum", "maybe-scalars", "statutory-age"
  , "review-checklist", "notice-letter"
  ]

-- | The M4 examples (spec §10: breadth). The assertions below are about SHAPE
-- (which keys, which guards, which idiom) or about BEHAVIOUR (through the R10
-- harness); the byte goldens the GREEN phase added pin the FORMATTING, which
-- shape assertions cannot.
--
-- Each file typechecks and evaluates in L4 (its @#EVAL@s are the oracle).
daListSource, daPayloadSource, daMaybeSource, daDateSource,
  daReviewSource, daLetterSource, daLetterTemplate :: FilePath
daListSource     = daExampleDir </> "tenant-list.l4"
daPayloadSource  = daExampleDir </> "payload-enum.l4"
daMaybeSource    = daExampleDir </> "maybe-scalars.l4"
daDateSource     = daExampleDir </> "statutory-age.l4"
daReviewSource   = daExampleDir </> "review-checklist.l4"
daLetterSource   = daExampleDir </> "notice-letter.l4"
daLetterTemplate = daExampleDir </> "notice-letter.letter.md"

-- | The @not-ok/@ fixtures M4 does NOT own, paired with the diagnostic each
-- must keep. M4 flips exactly two refusals (@maybe-number@ and
-- @just-payload-pattern@, both folded into @maybe-scalars.l4@); these four are
-- out of its scope and a change to any of them is a regression, not progress.
daStillRefused :: [(FilePath, String)]
daStillRefused =
  [ ( "deontic-body.l4"
    , "deontic/regulative rule (PARTY MUST/MAY/SHANT) has no docassemble form" )
  , ( "name-collision.l4"
    , "name collision: `t.notice_period`" )
  , ( "higher-order.l4"
    , "higher-order use of function `is positive`" )
  , ( "seam-ref-via-fn.l4"
    , "seam-shaped export (top-level IMPLIES) is referenced by another decision" )
  ]

-- | The @not-ok/@ fixtures the 2026-08-17 repair pass ADDED, each pinning a
-- refusal that replaced a silently wrong emission. Kept apart from
-- 'daStillRefused', which is the out-of-scope set: these two are M4's own, and
-- both are required to be reported in L4 terms rather than as an internal id
-- collision.
daM4Refused :: [(FilePath, String)]
daM4Refused =
  [ ( "maybe-empty-string.l4"
    , "`WHEN JUST \"\"` on a MAYBE STRING is refused" )
  , ( "payload-name-collision.l4"
    , "name collision: `d.the_reason` is produced by two different question blocks" )
  ]

-- | Emit an M4 example, reporting the refusal VERBATIM when it is still
-- refused. Written fail-first, when every one of these exited 1 with prose
-- naming the milestone that owed the answer; they all emit now, and the
-- verbatim stderr is what makes a REGRESSION legible rather than merely red.
daEmit :: FilePath -> FilePath -> IO String
daEmit bin src = do
  Output code sout serr <- runL4 bin ["docassemble", src]
  case code of
    ExitSuccess   -> pure sout
    ExitFailure n -> do
      expectationFailure $
        "`l4 docassemble " ++ src ++ "` exited " ++ show n
        ++ ": the M4 construct this example exists for is still refused."
        ++ "\n--- stderr ---\n" ++ serr
      pure ""

-- | Assert at least one of several spellings is present. Used where more than
-- one emission is defensible and the RED phase declines to pick — the gather
-- control questions, for instance, where a @target_number@ shape and a
-- @there_are_any@ + @there_is_another@ shape were both probed working.
shouldContainAny :: String -> String -> [String] -> IO ()
shouldContainAny what haystack needles =
  unless (any (`isInfixOf` haystack) needles) $
    expectationFailure $
      what ++ " contains none of " ++ show needles
      ++ "\n--- got ---\n" ++ haystack

-- | Fixtures for the docassemble repair cases, which are CLI shape probes
-- rather than corpus exhibits and so live beside the other @tests-cli@
-- fixtures, not in @examples/docassemble/@.
daGlossLossSource, daRuntimeCollisionSource, descAttachmentFixture :: FilePath
daGlobalShadowSource, daGatheredMaybeSource :: FilePath
daGlossLossSource        = fixtureDir </> "docassemble-glossary-losses.l4"
daRuntimeCollisionSource = fixtureDir </> "docassemble-runtime-collision.l4"
-- The other two thirds of the same namespace hazard (repair pass, 2026-08-17):
-- Python's builtins and `docassemble.base.util`'s star-import.
daGlobalShadowSource     = fixtureDir </> "docassemble-global-shadow.l4"
-- A paired `MAYBE NUMBER` inside a gathered element: the one place the
-- changed-answer repair does NOT reach, declared rather than silent.
daGatheredMaybeSource    = fixtureDir </> "docassemble-gathered-maybe.l4"
descAttachmentFixture    = fixtureDir </> "desc-attachment.l4"

-- | The four citations carried by @citations.l4@, herald-stripped: L4's own
-- @\@ref @ prefix and the inline @\<\< \>\>@ delimiters are L4 syntax and must
-- never reach a user-facing docassemble screen.
daCite1, daCite2, daCite3Tail, daCiteGoal :: String
daCite1 = "17 CFR 227.100(a)(1) — offering maximum"
daCite2 = "17 CFR 227.100(a)(3) — sales through one intermediary only"
-- The third citation begins with @%@ and contains a literal @${ … }@, so its
-- emitted spelling depends on which escape the emitter applies; only its
-- stable tail is asserted verbatim, and the hostile halves get their own
-- assertions (see the R9 escaping example).
daCite3Tail = "17 CFR 227.300(a)"
-- The fourth rides on the EXPORTED decide, and therefore on the goal @code:@
-- block. It is what makes the emitted ORDER observable: the emitter puts
-- @explain()@ after the assignment, and the goal's assignment is what pulls on
-- the sub-rules, so the goal completes last and its citation prints last. On
-- the three sub-rules alone the placement is unobservable — moving every
-- @explain()@ above its assignment left the round-trip harness fully green
-- until this citation existed.
daCiteGoal = "17 CFR 227.100 — the crowdfunding exemption"

-- | The generated Python package directory inside a @--package@ tree for
-- @citations.l4@: @docassemble/l4citations@ (R11: @docassemble.l4\<slug\>@).
daPkgInner :: FilePath
daPkgInner = "docassemble" </> "l4citations"

-- | Every regular file under @root@, as sorted paths relative to @root@.
treeFiles :: FilePath -> IO [FilePath]
treeFiles root = sort <$> go ""
 where
  go rel = do
    entries <- sort <$> listDirectory (root </> rel)
    concat <$> mapM (child rel) entries
  child rel e = do
    let r = if null rel then e else rel </> e
    isDir <- doesDirectoryExist (root </> r)
    if isDir then go r else pure [r]

-- | Directories under @root@ (relative paths) holding nothing at all. R11:
-- \"every emitted @data/@ subdirectory carries at least one real file (empty
-- directories survive neither git nor zip)\".
emptyTreeDirs :: FilePath -> IO [FilePath]
emptyTreeDirs root = sort <$> go ""
 where
  go rel = do
    entries <- sort <$> listDirectory (root </> rel)
    let here = [rel | null entries, not (null rel)]
    subs <- concat <$> mapM (child rel) entries
    pure (here ++ subs)
  child rel e = do
    let r = if null rel then e else rel </> e
    isDir <- doesDirectoryExist (root </> r)
    if isDir then go r else pure []

-- | Run @l4 docassemble FILE --package DIR@ into a FRESH directory and return
-- the written tree's sorted file list.
--
-- The failure message names the milestone deliberately: until M2 lands the
-- option does not exist, and an \"Invalid option\" exit is the honest RED
-- signal, not a broken test.
expectPackage :: FilePath -> FilePath -> FilePath -> IO [FilePath]
expectPackage bin src outDir = do
  removePathForcibly outDir
  Output code sout serr <- runL4 bin ["docassemble", src, "--package", outDir]
  unless (code == ExitSuccess) $
    expectationFailure $
      "`l4 docassemble " ++ src ++ " --package " ++ outDir ++ "` did not succeed: exited "
      ++ show code
      ++ "\n(M2/R11: --package DIR must write an installable PEP 420 package tree)"
      ++ "\n--- stdout ---\n" ++ sout
      ++ "\n--- stderr ---\n" ++ serr
  isDir <- doesDirectoryExist outDir
  unless isDir $
    expectationFailure ("no package tree was written at " ++ outDir)
  treeFiles outDir

-- | Split an emitted docassemble interview into its @---@-separated blocks.
-- docassemble itself splits on the whole-line regex @^--- *$@ before YAML ever
-- sees the file (@parse.py:138@), so this is the same unit the engine reasons
-- about.
yamlBlocks :: String -> [String]
yamlBlocks = map unlines . splitBlocks . lines
 where
  splitBlocks ls = case break isSep ls of
    (chunk, [])       -> [chunk]
    (chunk, _ : rest) -> chunk : splitBlocks rest
  isSep ln = "---" `isPrefixOf` ln && all (== ' ') (drop 3 ln)

-- | The single emitted block whose @id:@ is exactly @wanted@.
blockWithId :: String -> String -> IO String
blockWithId sout wanted =
  case [ b | b <- yamlBlocks sout, ("id: " ++ wanted) `elem` lines b ] of
    [b] -> pure b
    []  -> do
      expectationFailure $
        "no emitted block carries `id: " ++ wanted ++ "`"
        ++ "\n--- emitted interview ---\n" ++ sout
      pure ""
    bs  -> do
      expectationFailure $
        "expected exactly one block with `id: " ++ wanted
        ++ "`, found " ++ show (length bs)
      pure ""

-- | Assert a needle occurs in a haystack, reporting the haystack on failure.
shouldContain' :: String -> String -> String -> IO ()
shouldContain' what haystack needle =
  unless (needle `isInfixOf` haystack) $
    expectationFailure $
      what ++ " does not contain " ++ show needle ++ "\n--- got ---\n" ++ haystack

-- | Assert a needle does NOT occur — the half that catches a citation
-- attributed to the wrong rule.
shouldNotContain' :: String -> String -> String -> IO ()
shouldNotContain' what haystack needle =
  when (needle `isInfixOf` haystack) $
    expectationFailure $
      what ++ " unexpectedly contains " ++ show needle ++ "\n--- got ---\n" ++ haystack

-- | How many (possibly overlapping) times a needle occurs in a haystack.
countInfix :: String -> String -> Int
countInfix needle = go
 where
  go [] = 0
  go s@(_ : rest) = (if needle `isPrefixOf` s then 1 else 0) + go rest

-- | Assert that @a@ occurs before @b@ inside @haystack@, and that both occur.
-- The half of an ordering claim a pair of @shouldContain'@s cannot make.
shouldPrecede :: String -> String -> String -> String -> IO ()
shouldPrecede what haystack a b =
  case (findSub a, findSub b) of
    (Just i, Just j)
      | i < j     -> pure ()
      | otherwise -> expectationFailure $
          what ++ ": expected " ++ show a ++ " to come before " ++ show b
              ++ ", but it does not\n--- got ---\n" ++ haystack
    _ -> expectationFailure $
      what ++ ": expected both " ++ show a ++ " and " ++ show b
          ++ " to occur\n--- got ---\n" ++ haystack
 where
  findSub n = findIndex (n `isPrefixOf`) (tails' haystack)
  tails' s = s : case s of { [] -> []; (_ : r) -> tails' r }

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
-- the statute corpus, 70 decisions, evaluated end to end. The cases
-- file's own header records how each pin was anchored (L4 + the documented
-- transform, never the engine's own output).
corpusGolden, corpusEngineCases :: FilePath
corpusGolden      = "examples/dmn/expected/regcf-corpus.dmn"
corpusEngineCases = "examples/dmn/regcf-corpus.cases.json"

dmnDateProbeDir :: FilePath
dmnDateProbeDir = fixtureDir </> "dmn-date-probe"

-- The DATE ARITHMETIC axis, added 2026-08-05. `dmn-date-probe` above settled
-- date LITERALS and date COMPARISONS; this pair settles date ARITHMETIC, which
-- is what an anniversary needs and what the corpus's Rule 501(a) now uses.
--
-- Hand-written and never regenerated, same rule as its sibling. The load-bearing
-- claim is an EQUIVALENCE the emitter cannot state about itself: `daydate`'s
-- `add months`\/`add years` CLAMP to the target month's last day, the exporter
-- lowers them to FEEL's @date + duration(...)@, and that is sound only if FEEL
-- clamps identically. DMN 1.3's own formula does NOT clamp -- it preserves the
-- day component -- so the spec and the engines had to be assumed to disagree
-- until measured. They clamp. All six cases agree with L4.
--
-- `dateArithNegative` is the NEGATIVE CONTROL and is driven 'HarnessMustFail':
-- the same anniversary written by reconstructing components, @date(y + 1, m,
-- d)@, which is null on both engines for a 29 February issuance. Without it the
-- positive would show only that one idiom works, not that the other cannot --
-- and "cannot" is the whole reason `add years` exists.
dateArithModel, dateArithCases, dateArithNegative, dateArithNegativeCases :: FilePath
dateArithModel         = dmnDateArithDir </> "clamp.dmn"
dateArithCases         = dmnDateArithDir </> "clamp.cases.json"
dateArithNegative      = dmnDateArithDir </> "reconstruct-refused.dmn"
dateArithNegativeCases = dmnDateArithDir </> "reconstruct-refused.cases.json"

dmnDateArithDir :: FilePath
dmnDateArithDir = fixtureDir </> "dmn-date-arith"

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
-- The `l4 verify` controls. One positive (a module with real boolean structure
-- and nothing wrong with it) and four negatives, one per finding family.
--
-- The negatives are the load-bearing half. A consistency checker that never
-- fires passes every corpus, so "regcf is clean" only means something if these
-- five files prove the checker is capable of going red — and going red for the
-- REASON claimed, which is why each test asserts the finding KIND and not just
-- the exit code.
verifyCleanFixture, verifyUnsatFixture, verifyDeadBranchFixture :: FilePath
verifyVacuousGuardFixture, verifySeamFixture, verifyNestedFixture :: FilePath
verifyCleanFixture        = fixtureDir </> "verify-clean.l4"
verifyUnsatFixture        = fixtureDir </> "verify-unsat.l4"
verifyDeadBranchFixture   = fixtureDir </> "verify-dead-branch.l4"
verifyVacuousGuardFixture = fixtureDir </> "verify-vacuous-guard.l4"
verifySeamFixture         = fixtureDir </> "verify-seam.l4"
verifyNestedFixture       = fixtureDir </> "verify-nested.l4"

-- The `l4 nlg` differential pair. These goldens are written by
-- jl4-test's `jl4NlgAnnotationsGolden`, and `l4 nlg` must reproduce them BYTE
-- FOR BYTE — that equality is the whole reason the orchestrator's p7-tnr leg
-- can carry a `differential` oracle instead of reporting NOT-REGENERATED.
-- If this pair ever diverges, p7-tnr silently stops measuring what it says.
nlgRegcfSource, nlgRegcfGolden, nlgWizardSource, nlgWizardGolden :: FilePath
nlgRegcfSource  = "examples/legal/regcf/regcf.l4"
nlgRegcfGolden  = "examples/legal/regcf/tests/regcf.nlg.golden"
nlgWizardSource = "examples/legal/regcf/regcf-wizard.l4"
nlgWizardGolden = "examples/legal/regcf/tests/regcf-wizard.nlg.golden"

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
       , graphFixture, graphEmptyFixture
       , cycle3Entry, cycle2Entry, selfImportEntry, cleanImportEntry
       , embeddedDiamondEntry, shadowEmbeddedEntry, shadowSiblingEntry
       , shadowExtraEntry, shadowImporterEntry
       , verifyCleanFixture, verifyUnsatFixture, verifyDeadBranchFixture
       , verifyVacuousGuardFixture, verifySeamFixture, verifyNestedFixture
       , nlgRegcfSource, nlgRegcfGolden, nlgWizardSource, nlgWizardGolden
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
       , svcSource, svcGolden, svcKieDmnGolden, svcEngineCases
       , daCitationsSource ] \fp -> do
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
      sout `shouldSatisfy` ("blawx" `isInfixOf`)
      sout `shouldSatisfy` ("nlg" `isInfixOf`)
      sout `shouldSatisfy` ("verify" `isInfixOf`)
      -- "graph" is a substring of "state-graph" (asserted above), so pin the
      -- graph entry by a word unique to its own description instead.
      sout `shouldSatisfy` ("Mermaid" `isInfixOf`)

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

  ----------------------------------------------------------------------------
  -- @desc attachment (L4.Parser.ResolveAnnotation)
  --
  -- `instance HasDesc (Expr n)` was `pure`, so a @desc written above a WHERE
  -- binding reached no node at all; its first repair descended only into a
  -- WHERE/LET at the top of a body, so one nested inside another expression
  -- still vanished. In EVERY failing case `l4 check` reported success and the
  -- annotation was simply gone, which is why these are asserted rather than
  -- assumed. Neither property is visible in a jl4-test corpus golden — none of
  -- evaluation, exactprint, nlg or schema shows which node owns a desc — so
  -- the oracles here are the two surfaces that do show it.
  ----------------------------------------------------------------------------
  describe "@desc attachment to WHERE/LET bindings" $ do
    it "gives a WHERE binding's @desc to that binding, not to a later top-level decl" $ do
      -- The glossary is the ownership oracle: `auto terms:` keys every entry by
      -- the name of the definition that owns the gloss. `descPrecedesNode`
      -- admits any preceding desc within 8 columns of slack, so "the NEXT
      -- top-level declaration claims it" is the behaviour this replaced, not a
      -- hypothetical — and the fixture's next declaration deliberately carries
      -- no @desc of its own, so a mis-attachment would show up as its key.
      Output code sout serr <- runL4 bin ["docassemble", descAttachmentFixture]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)
      case [ b | b <- yamlBlocks sout, "auto terms:" `isInfixOf` b ] of
        [glossary] -> do
          shouldContain'    "the glossary" glossary
            "\"title is clean\": \"BINDINGGLOSS the title is free of encumbrance\""
          shouldNotContain' "the glossary" glossary "claim window in days"
        other -> expectationFailure $
          "expected exactly one `auto terms:` block, found " ++ show (length other)

    it "gives a LET binding nested inside another expression its own @desc" $ do
      -- `l4 ast` is the oracle here, because the glossary cannot see this one:
      -- `collectGlossary` walks only a WHERE/LET at the TOP of a decide body.
      -- The AST prints an annotation's desc payload once per node that owns it
      -- and once per raw `TDesc` token, so "owned" is exactly "occurs somewhere
      -- other than inside a TDesc". Unattached, that count is 0 — which is the
      -- state this fixture was written against.
      Output code sout _ <- runL4 bin ["ast", descAttachmentFixture]
      code `shouldBe` ExitSuccess
      for_ ["NESTEDGLOSS", "BINDINGGLOSS"] \gloss -> do
        let owned = countInfix gloss sout - countInfix ("TDesc \" " ++ gloss) sout
        unless (owned >= 1) $
          expectationFailure $
            show gloss ++ " reaches no node's `desc`: it occurs "
            ++ show (countInfix gloss sout) ++ " times in the AST, all of them as a "
            ++ "raw TDesc token, so the annotation was dropped silently"

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

  describe "l4 graph" $ do
    it "emits DOT on stdout by default and exits 0" $ do
      Output code sout _ <- runL4 bin ["graph", graphFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("digraph" `isInfixOf`)
      sout `shouldSatisfy` ("mainline" `isInfixOf`)
      sout `shouldSatisfy` ("deadwood" `isInfixOf`)   -- unsliced: dead code still drawn

    it "emits Mermaid under --format mermaid, starting with the frozen header" $ do
      Output code sout _ <- runL4 bin ["graph", graphFixture, "--format", "mermaid"]
      code `shouldBe` ExitSuccess
      take 1 (lines sout) `shouldBe` ["flowchart TD"]
      sout `shouldSatisfy` ("-->" `isInfixOf`)

    it "fails on a typecheck error, with diagnostics on stderr" $ do
      Output code _ serr <- runL4 bin ["graph", errorFixture]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("Type checking failed" `isInfixOf`)

    it "writes to a file with -o instead of stdout" $ do
      tmp <- getTemporaryDirectory
      let outFile = tmp </> "l4-graph-out.dot"
      Output code sout _ <- runL4 bin ["graph", graphFixture, "-o", outFile]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` null
      exists <- doesFileExist outFile
      exists `shouldBe` True
      contents <- readFile outFile
      contents `shouldSatisfy` ("digraph" `isInfixOf`)
      removeFile outFile

    it "rejects an unknown --format" $ do
      Output code _ serr <- runL4 bin ["graph", graphFixture, "--format", "bogus"]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("Invalid format" `isInfixOf`)

    it "slices forward from --root: callees in, unrelated definitions out" $ do
      Output code sout _ <- runL4 bin ["graph", graphFixture, "--root", "mainline"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("mainline" `isInfixOf`)
      sout `shouldSatisfy` ("baseline" `isInfixOf`)
      sout `shouldSatisfy` (not . ("deadwood" `isInfixOf`))

    it "slices against the arrows under --reverse: consumers in" $ do
      Output code sout _ <- runL4 bin ["graph", graphFixture, "--root", "baseline", "--reverse"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("baseline" `isInfixOf`)
      sout `shouldSatisfy` ("mainline" `isInfixOf`)
      sout `shouldSatisfy` (not . ("deadwood" `isInfixOf`))

    it "cuts the slice at --depth (0 = the roots alone)" $ do
      Output code sout _ <- runL4 bin ["graph", graphFixture, "--root", "mainline", "--depth", "0"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("mainline" `isInfixOf`)
      sout `shouldSatisfy` (not . ("baseline" `isInfixOf`))

    it "fails loudly on a --root that names no definition" $ do
      Output code _ serr <- runL4 bin ["graph", graphFixture, "--root", "nonesuch"]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("nonesuch" `isInfixOf`)

    it "refuses --reverse and --depth without a --root to measure from" $ do
      Output code _ serr <- runL4 bin ["graph", graphFixture, "--reverse"]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("--root" `isInfixOf`)

    -- Pinned deliberately (the precedents split: state-graph exits 1 when it
    -- finds no regulative rules, verify exits 0 when clean): an empty diagram
    -- is an answer about the module, not a failure of the command.
    it "exits 0 and emits the empty graph for a module with no definitions" $ do
      Output code sout _ <- runL4 bin ["graph", graphEmptyFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("digraph" `isInfixOf`)

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

    -- The CORPUS leg (R12/R13, spec §15.12/§16): the whole 70-decision Reg CF
    -- corpus builds and answers on both engines, over TWENTY-TWO cases — the
    -- base world, the 15 dated cases that relocate the rule-date-rebinding
    -- fixtures R12 dropped (ruling R-C, spec §15.12.1: "the model owns the law
    -- under a date; the harness owns the dates"), the 4 seed cases that close
    -- the total-assets and restricted-period leaves the §8 diff oracle reported
    -- structurally inert, THE LEAP CASE, and THE ESCHEAT CASE. 22 x 70 = 1540.
    -- All counts below are MEASURED (2026-08-09, this machine, both harnesses),
    -- not aspirational: before R12/R13 KIE refused with 16 build errors and
    -- Camunda refused the file at parse() on the raw-L4 deontic body.
    --
    -- 67 decisions became 69, and 20 cases became 21, on 2026-08-05, when Rule
    -- 501(a)'s "one year" stopped being the constant 365. The two added
    -- decisions are the anniversary and the deadline computed from it; the added
    -- case is the one that constant got WRONG — a transfer on day 365 of a
    -- holding spanning 29 February 2024, which the flat count PERMITTED and the
    -- calendar refuses. It is pinned here rather than only in the L4 #ASSERTs
    -- because R0 says the execution is the exhibit: an engine we do not control
    -- has to be the one that refuses it.
    --
    -- 69 became 70, and 21 cases became 22, on 2026-08-09, when Rule 501(a)(4)
    -- stopped being one ~300-character boolean and became six. The added
    -- decision is the limb itself; the added case is the ESCHEAT case — a
    -- transfer in connection with the purchaser's death to a transferee who is
    -- nobody in particular — which is the fact pattern the decomposition's
    -- nexus ruling turns on, and which no case could express while the limb was
    -- a single self-assessed fact.
    it "KIE builds and answers the whole Reg CF corpus (R12/R13)" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustPass
        corpusGolden [corpusGolden, "--cases", corpusEngineCases] \out -> do
          out `shouldSatisfy` ("KIE 8.44.0.Final VERDICT" `isInfixOf`)
          out `shouldSatisfy` ("22 case(s)" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("0 warning(s)" `isInfixOf`)
          out `shouldSatisfy` ("1540/1540 decision(s) SUCCEEDED" `isInfixOf`)
          out `shouldSatisfy` ("1540/1540 value(s) as expected" `isInfixOf`)
          -- the SVC leg is a value check since 2026-08-02 (each service fed
          -- its inputDecisions' computed values, each outputDecision compared
          -- against the same expect entry): 7 services, 15 declared outputs,
          -- per case
          out `shouldSatisfy` ("330/330 service output value(s) as expected" `isInfixOf`)

    it "Camunda parses and answers the whole Reg CF corpus (R12/R13)" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustPass
        corpusGolden [corpusGolden, "--cases", corpusEngineCases] \out -> do
          out `shouldSatisfy` ("Camunda 8.7.6 (zeebe-dmn) VERDICT" `isInfixOf`)
          out `shouldSatisfy` ("22 case(s)" `isInfixOf`)
          out `shouldSatisfy` ("1 parsed" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("1540/1540 decision(s) evaluated" `isInfixOf`)
          out `shouldSatisfy` ("1540/1540 value(s) as expected" `isInfixOf`)

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
    -- The DATE ARITHMETIC pair. What this asserts that nothing else does: the
    -- CLAMP that `daydate`'s `add months`/`add years` perform is the same clamp
    -- FEEL performs, so an L4 module that computes an anniversary and the DMN it
    -- exports to cannot answer differently. That equivalence is the licence for
    -- the two lowering arms in "L4.Dmn.Lower"; if this goes red they are unsound
    -- and the Reg CF corpus's exported resale restriction has silently drifted
    -- from its own #ASSERTs.
    it "both engines CLAMP date arithmetic, agreeing with daydate on all six" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustPass
        dateArithModel [dateArithModel, "--cases", dateArithCases] \out -> do
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("6/6 value(s) as expected" `isInfixOf`)

    it "both engines CLAMP date arithmetic, agreeing with daydate on all six (Camunda)" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustPass
        dateArithModel [dateArithModel, "--cases", dateArithCases] \out -> do
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("6/6 value(s) as expected" `isInfixOf`)

    -- The negative half, and it is not decoration: it is the reason the corpus
    -- writes `add years` instead of rebuilding the date from its components.
    -- `date(2025, 2, 29)` is not a date, and neither engine clamps or rolls it.
    it "reconstructing an anniversary from components is REFUSED for 29 February" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustFail
        dateArithNegative [dateArithNegative, "--cases", dateArithNegativeCases] \out -> do
          -- the control in the same file DOES clamp, so the failure isolates to
          -- the reconstruction rather than to anything about the fixture
          out `shouldSatisfy` ("anniv_duration" `isInfixOf`)
          out `shouldSatisfy` ("anniv_reconstruct" `isInfixOf`)

    it "reconstructing an anniversary from components is REFUSED for 29 February (Camunda)" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustFail
        dateArithNegative [dateArithNegative, "--cases", dateArithNegativeCases] \out -> do
          out `shouldSatisfy` ("anniv_duration" `isInfixOf`)
          out `shouldSatisfy` ("anniv_reconstruct" `isInfixOf`)

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

  -- The NLG footing. Two assertions, and the second is the one that matters:
  -- `l4 nlg` must be byte-identical to what jl4-test writes into the committed
  -- `.nlg.golden`. Only that equality lets the orchestrator's p7-tnr leg
  -- regenerate-and-diff instead of hashing a file it did not produce.
  describe "l4 nlg" $ do
    it "linearizes a clean module and exits 0" $ do
      Output code sout _ <- runL4 bin ["nlg", cleanFixture]
      code `shouldBe` ExitSuccess
      -- clean.l4 has no directives, so the payload is empty. That is the
      -- correct answer and not a failure: `nlg` linearizes DIRECTIVES.
      sout `shouldBe` ""

    it "refuses to emit prose for a module that does not typecheck" $
      expectFail bin ["nlg", errorFixture]

    it "reproduces the committed regcf NLG golden byte for byte" $
      expectGolden bin ["nlg", nlgRegcfSource] nlgRegcfGolden

    it "reproduces the committed regcf-wizard NLG golden byte for byte" $
      expectGolden bin ["nlg", nlgWizardSource] nlgWizardGolden

  -- The verifier footing. Every negative control asserts the finding KIND, not
  -- merely a red exit: a checker that goes red for the wrong reason is a
  -- checker whose green runs mean nothing either.
  describe "l4 verify" $ do
    it "reports no findings on a clean module and exits 0" $ do
      Output code sout serr <- runL4 bin ["verify", verifyCleanFixture]
      code `shouldBe` ExitSuccess
      unless ("0 finding(s)." `isInfixOf` sout) $
        expectationFailure ("expected a zero-finding summary\n" ++ sout ++ serr)

    it "states its propositional bound in the report, not only in the source" $ do
      Output _ sout _ <- runL4 bin ["verify", verifyCleanFixture]
      sout `shouldSatisfy` ("PROPOSITIONAL" `isInfixOf`)
      sout `shouldSatisfy` ("SOUND, not COMPLETE" `isInfixOf`)

    -- Reachability, not prose. Every other subcommand answers
    -- `Invalid option '--help'`, so without the `helper` wired into this one
    -- the footer would exist and be unreadable.
    it "states the same bound in --help, where a caller reads it first" $ do
      Output _ sout _ <- runL4 bin ["verify", "--help"]
      sout `shouldSatisfy` ("PROPOSITIONAL" `isInfixOf`)
      sout `shouldSatisfy` ("--no-coalesce-atoms" `isInfixOf`)

    -- The run receipt sends a reader to `--help` for the FULL statement of the
    -- bound, so `--help` has to render it the way it was written. Plain
    -- `footer` does not: it is `fillSep . words`, which eats every newline and
    -- delivers five separately-quotable paragraphs as one 30-line wall. The
    -- heading is the cheapest discriminator — under reflow it runs straight
    -- into the sentence after it.
    it "renders that bound as paragraphs, not as one reflowed wall" $ do
      Output _ sout _ <- runL4 bin ["verify", "--help"]
      let heading = "WHAT A CLEAN RUN PROVES, AND WHAT IT DOES NOT"
      unless (any ((== heading) . dropWhile (== ' ')) (lines sout)) $
        expectationFailure
          ( "the bound's heading should stand on its own line; optparse's\n\
            \`footer` reflows it into the following sentence. Got:\n"
              ++ sout
          )

    it "emits a well-shaped JSON envelope with ok=true on a clean module" $ do
      env <- jsonEnvelope bin ["verify", verifyCleanFixture, "--format", "json"]
      objField env "ok" `shouldBe` Just (Bool True)
      objField env "decisions" `shouldSatisfy` (/= Nothing)
      objField env "bound" `shouldSatisfy` (/= Nothing)
      case objField env "summary" >>= (`objField` "findings") of
        Just (Number n) -> n `shouldBe` 0
        other -> expectationFailure ("expected summary.findings, got " ++ show other)

    it "goes RED on a decision no assignment can satisfy" $
      expectVerifyFinding bin verifyUnsatFixture "unsat"

    it "goes RED on an OR limb that cannot hold where it sits" $
      expectVerifyFinding bin verifyDeadBranchFixture "dead-branch"

    it "goes RED on a conjunct its own siblings already entail" $
      expectVerifyFinding bin verifyVacuousGuardFixture "vacuous-guard"

    it "goes RED on an unsatisfiable rule scope" $ do
      Output code sout _ <-
        runL4 bin ["verify", verifySeamFixture, "--format", "json"
                  , "--decision", "`a rule that reaches nobody`"]
      code `shouldBe` ExitFailure 1
      sout `shouldSatisfy` ("\"vacuous-guard\"" `isInfixOf`)

    it "goes RED when a rule's Complies verdict is unreachable" $ do
      Output code sout _ <-
        runL4 bin ["verify", verifySeamFixture, "--format", "json"
                  , "--decision", "`everyone in scope is in breach`"]
      code `shouldBe` ExitFailure 1
      sout `shouldSatisfy` ("\"unreachable-outcome\"" `isInfixOf`)

    it "goes RED when a rule's InBreach verdict is unreachable" $ do
      Output code sout _ <-
        runL4 bin ["verify", verifySeamFixture, "--format", "json"
                  , "--decision", "`a requirement that adds nothing`"]
      code `shouldBe` ExitFailure 1
      sout `shouldSatisfy` ("\"unreachable-outcome\"" `isInfixOf`)

    -- The suppression that keeps the checker usable. `x XOR y` normalises into
    -- a CNF containing `x OR NOT x`; reporting that clause as a vacuous guard
    -- would fire on ordinary drafting and teach the reader to ignore the tool.
    -- verify-clean.l4's first decision IS an xor, so this is measured, not
    -- asserted.
    it "does not report the tautological clauses CNF distribution manufactures" $ do
      Output code sout _ <- runL4 bin ["verify", verifyCleanFixture, "--format", "json"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` (not . ("vacuous-guard" `isInfixOf`))

    -- The weaker mode is documented as weaker; pin that it is not SILENTLY
    -- weaker. `x` here is a nullary reference to a GIVEN binder, so the two
    -- occurrences share a unique with or without coalescing and the finding
    -- survives. What --no-coalesce-atoms drops is compound leaves, which this
    -- fixture deliberately does not have.
    it "still finds a binder-level contradiction with --no-coalesce-atoms" $ do
      Output code _ _ <- runL4 bin ["verify", verifyUnsatFixture, "--no-coalesce-atoms"]
      code `shouldBe` ExitFailure 1

    it "records a non-boolean DECIDE as skipped, never as clean" $ do
      env <- jsonEnvelope bin ["verify", nlgRegcfSource, "--format", "json"]
      case objField env "summary" >>= (`objField` "skipped") of
        Just (Number n) -> n `shouldSatisfy` (> 0)
        other -> expectationFailure ("expected summary.skipped, got " ++ show other)

    -- The third category, and the reason it is a NUMBER. `analysed + skipped`
    -- does not total the file: a WHERE-local definition is a DECIDE and the
    -- ladder's entry point does not descend into one, so neither does this. An
    -- exclusion nobody can size is an exclusion nobody believes — and a
    -- hand-count of the Reg CF source got it wrong in exactly that way (5 and
    -- 0 by grep, against the AST's 5 and 2).
    it "counts the WHERE-nested decisions it did not visit" $ do
      env <- jsonEnvelope bin ["verify", verifyNestedFixture, "--format", "json"]
      case objField env "summary" >>= (`objField` "nestedNotVisited") of
        Just (Number n) -> n `shouldBe` 1
        other -> expectationFailure ("expected summary.nestedNotVisited, got " ++ show other)

    -- The nested body is `y AND NOT y`. It stays invisible, and this test
    -- exists so that a future change which starts descending announces itself
    -- here rather than by silently altering what a clean run means.
    it "does not report a contradiction that lives only in a WHERE clause" $ do
      Output code sout _ <- runL4 bin ["verify", verifyNestedFixture, "--format", "json"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` (not . ("unsat" `isInfixOf`))

    -- The corpus figure the p8-verify receipt now carries.
    it "reports the Reg CF corpus's own nested count" $ do
      env <- jsonEnvelope bin ["verify", nlgRegcfSource, "--format", "json"]
      case objField env "summary" >>= (`objField` "nestedNotVisited") of
        Just (Number n) -> n `shouldBe` 5
        other -> expectationFailure ("expected summary.nestedNotVisited, got " ++ show other)

    it "fails on a module that does not typecheck" $
      expectFail bin ["verify", errorFixture]

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

  describe "l4 blawx" $ do
    it "compiles the Appendix-A benefit example to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/benefit.l4"]
                       "examples/blawx/expected/benefit.blawx"

    it "dumps benefit's concatenated s(CASP) (--scasp) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/benefit.l4", "--scasp"]
                       "examples/blawx/expected/benefit.pl"

    it "compiles the minimal mortality example to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/mortality.l4"]
                       "examples/blawx/expected/mortality.blawx"

    it "dumps mortality's s(CASP) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/mortality.l4", "--scasp"]
                       "examples/blawx/expected/mortality.pl"

    it "compiles the aggregates example (findall + *_blawx_list) to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/scores.l4"]
                       "examples/blawx/expected/scores.blawx"

    it "dumps scores' s(CASP) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/scores.l4", "--scasp"]
                       "examples/blawx/expected/scores.pl"

    it "compiles the structural-recursion example to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/sumlist.l4"]
                       "examples/blawx/expected/sumlist.blawx"

    it "dumps sumlist's s(CASP) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/sumlist.l4", "--scasp"]
                       "examples/blawx/expected/sumlist.pl"

    it "compiles the rodents-and-vermin exclusion to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/rodents.l4"]
                       "examples/blawx/expected/rodents.blawx"

    it "dumps rodents' s(CASP) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/rodents.l4", "--scasp"]
                       "examples/blawx/expected/rodents.pl"

    it "compiles the ASSUME-shaped anti-social example to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/antisocial.l4"]
                       "examples/blawx/expected/antisocial.blawx"

    it "dumps antisocial's s(CASP) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/antisocial.l4", "--scasp"]
                       "examples/blawx/expected/antisocial.pl"

    it "compiles antisocial's record-spelled semantic twin to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/antisocial-twin.l4"]
                       "examples/blawx/expected/antisocial-twin.blawx"

    it "dumps the antisocial twin's s(CASP) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/antisocial-twin.l4", "--scasp"]
                       "examples/blawx/expected/antisocial-twin.pl"

    it "compiles the ASSUME-shaped alcohol act to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/alcohol.l4"]
                       "examples/blawx/expected/alcohol.blawx"

    it "dumps alcohol's s(CASP) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/alcohol.l4", "--scasp"]
                       "examples/blawx/expected/alcohol.pl"

    it "compiles alcohol's record-spelled semantic twin to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/alcohol-twin.l4"]
                       "examples/blawx/expected/alcohol-twin.blawx"

    it "dumps the alcohol twin's s(CASP) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/alcohol-twin.l4", "--scasp"]
                       "examples/blawx/expected/alcohol-twin.pl"

    -- P4c, the statute showcase: Housing Act 1988 Sch 2 grounds 8, 13, 15 and
    -- 17 inlined into ONE module (`buildCtx` is module-scoped, so an aggregator
    -- that IMPORTed them would emit queries against an ontology that does not
    -- exist). Four records in one Blawx namespace, 49 oracle-anchored
    -- directives, and the corpus's only arity-2 computed predicate.
    it "compiles the four Housing Act grounds to their golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/housing-grounds.l4"]
                       "examples/blawx/expected/housing-grounds.blawx"

    it "compiles the four Housing Act grounds to their golden s(CASP) dump" $
      expectGolden bin ["blawx", "examples/blawx/housing-grounds.l4", "--scasp"]
                       "examples/blawx/expected/housing-grounds.pl"

    -- The arity-2 gap, pinned rather than assumed. `per-period threshold met`
    -- is (Ground8Claim, NUMBER) -> BOOLEAN: total arity 2 with the boolean
    -- output dropped, and its second parameter is neither record- nor
    -- enum-sorted, so it is not attribute-shaped and does not reach the arity-3
    -- relationship form either. It therefore gets NO `blawx_attribute`
    -- declaration (`L4.Blawx.Lower`, the recorded relationships-start-at-arity-3
    -- gap) while its rules and its four query rows DO emit. This asserts both
    -- halves: the declaration is absent, and nothing downstream blanks — the
    -- `noBlankedBlawxRow` row below covers the images, and the headless fixpoint
    -- harness re-saves every one of them. If a later change starts declaring
    -- arity-2 predicates, this test is the one to delete.
    it "emits an undeclared but imaged arity-2 predicate (the recorded gap)" $ do
      Output code sout _ <- runL4 bin ["blawx", "examples/blawx/housing-grounds.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("per_period_threshold_met(Claim,Arrears)" `isInfixOf`)
      sout `shouldSatisfy` ("?- per_period_threshold_met(g1,1300)." `isInfixOf`)
      sout `shouldSatisfy`
        (not . ("blawx_attribute(ground8_claim,per_period_threshold_met" `isInfixOf`))
      -- and the four records really did land in one namespace, un-collided
      mapM_ (\c -> sout `shouldSatisfy` (("blawx_category(" ++ c ++ ")") `isInfixOf`))
        ["ground8_claim", "ground13_claim", "ground15_claim", "ground17_claim"]
      -- the rename that made that possible: the enum keeps `rent_period`, the
      -- field became `the basis on which rent is payable`
      sout `shouldSatisfy` ("blawx_category(rent_period)" `isInfixOf`)
      sout `shouldSatisfy`
        ("blawx_attribute(ground8_claim,the_basis_on_which_rent_is_payable" `isInfixOf`)
      -- the interview follows the FIRST @export: the mandatory ground
      sout `shouldSatisfy` ("?- ground_8_made_out(X)." `isInfixOf`)

    -- The twin discipline, as a property rather than a comment. An
    -- `ASSUME`-shaped seed has no evaluable directive, so `etc/blawx-tier1-harness.py`
    -- takes its expectations from a record-spelled twin and replays the twin's
    -- fact rows against the ASSUME seed's own workspaces. That is only sound if
    -- the two spellings share their atoms, and this is the assertion that they
    -- do: the emitted s(CASP) is identical apart from the first line, which is
    -- the provenance comment naming the source file. If someone renames a field
    -- in a twin "for readability", this fails here rather than degrading the
    -- tier-1 run into a comparison of two unrelated programs.
    it "emits byte-identical s(CASP) for an ASSUME seed and its record twin" $
      mapM_ (twinsAgree bin)
        [("antisocial", "antisocial-twin"), ("alcohol", "alcohol-twin")]

    it "never blanks a row's xml_content while its scasp_encoding is non-empty (R12)" $
      mapM_ (noBlankedBlawxRow bin)
        [ "benefit", "mortality", "scores", "sumlist", "rodents"
        , "antisocial", "antisocial-twin", "alcohol", "alcohol-twin"
        , "housing-grounds" ]

    it "carries the @export prose into rule_text, and falls back to @ref (structural)" $ do
      Output code sout _ <- runL4 bin ["blawx", "examples/blawx/antisocial.l4"]
      code `shouldBe` ExitSuccess
      -- arm A: a decision carrying BOTH @export prose and @ref shows the prose
      sout `shouldSatisfy`
        ("1. Anti-social Behaviour, Crime and Policing Act 2014 s.43(1): an authorised person"
           `isInfixOf`)
      -- arm B: a bare @export with only a @ref shows the citation, not the stub
      sout `shouldSatisfy`
        ("5. Anti-social Behaviour, Crime and Policing Act 2014, s.43(1)(b)" `isInfixOf`)
      sout `shouldSatisfy`
        (not . ("Definition of the conduct is unreasonable." `isInfixOf`))
      -- the P1 earmark discharged: an interview on a module with no DECLARE
      sout `shouldSatisfy` ("#abducible person(X)." `isInfixOf`)
      sout `shouldSatisfy` ("#abducible conduct(X,Y)." `isInfixOf`)
      sout `shouldSatisfy` ("?- may_issue_a_community_protection_notice(X,Y)." `isInfixOf`)
      -- the reachability gate: an ASSUME no clause reaches contributes nothing
      sout `shouldSatisfy` (not . ("effect_target" `isInfixOf`))

    it "gives NOT over an ASSUMEd input classical negation, not NAF (R5)" $ do
      Output code sout _ <- runL4 bin ["blawx", "examples/blawx/alcohol.l4", "--scasp"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("-the_proprietor_corrects_the_price_list(Pr)." `isInfixOf`)
      sout `shouldSatisfy` (not . ("not the_proprietor_corrects_the_price_list" `isInfixOf`))

    it "rejects a subjectless ASSUMEd input rather than blanking its row" $ do
      Output code _ serr <- runL4 bin ["blawx", "examples/blawx/not-ok/zero-arity.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("no category subject" `isInfixOf`)
      -- the refused band is an ARITY band; the message must say so, because
      -- `arity-two.l4` below satisfies "first parameter is a category" and is
      -- refused anyway
      serr `shouldSatisfy` ("total arity 0" `isInfixOf`)
      serr `shouldSatisfy` ("start at total arity 3" `isInfixOf`)

    it "rejects a two-place ASSUMEd input EVEN WITH a category first parameter" $ do
      -- The other half of the refused band. `classifyPred` places an input as
      -- an attribute only at (category) or (category) -> value; relationship
      -- blocks start at total arity 3; a two-place input falls between them.
      Output code _ serr <- runL4 bin ["blawx", "examples/blawx/not-ok/arity-two.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("no category subject" `isInfixOf`)
      serr `shouldSatisfy` ("`severity exceeds` is an input of total arity 2" `isInfixOf`)
      -- and it must NOT tell an author who already has a category subject to
      -- add one: that was the old wording, and it named no reachable fix
      serr `shouldSatisfy` (not . ("first parameter is not a category" `isInfixOf`))

    it "emits the ruledoc first, then workspaces with the dedup-marked triple (structural smoke)" $ do
      Output code sout _ <- runL4 bin ["blawx", "examples/blawx/benefit.l4"]
      code `shouldBe` ExitSuccess
      -- R1: exactly one ruledoc row, FIRST — before any workspace row
      firstLineWith "- model: blawx.ruledoc" sout
        `shouldSatisfy` (< firstLineWith "- model: blawx.workspace" sout)
      sout `shouldSatisfy` ("workspace_name: root_section" `isInfixOf`)
      sout `shouldSatisfy` ("workspace_name: sec_1_section" `isInfixOf`)
      sout `shouldSatisfy` (":- dynamic applicant/1." `isInfixOf`)
      sout `shouldSatisfy` ("% BLAWX CHECK DUPLICATES" `isInfixOf`)
      sout `shouldSatisfy` ("?- benefit_amount(a1,Benefitamount)." `isInfixOf`)
      -- R11: the #ASSERT-as-constraint emission and the #abducible interview test
      sout `shouldSatisfy` ("false :- not eligible_for_benefit(a1)." `isInfixOf`)
      sout `shouldSatisfy` ("false :- not benefit_amount(a1,1250)." `isInfixOf`)
      sout `shouldSatisfy` ("test_name: interview" `isInfixOf`)
      sout `shouldSatisfy` ("#abducible applicant(X)." `isInfixOf`)
      sout `shouldSatisfy` ("#abducible age(X,Y)." `isInfixOf`)
      sout `shouldSatisfy` ("#abducible is_veteran(X)." `isInfixOf`)
      sout `shouldSatisfy` ("?- eligible_for_benefit(X)." `isInfixOf`)

    it "refuses -o FILE.pl without --scasp (the dump would clobber its own YAML)" $ do
      Output code _ serr <- runL4 bin ["blawx", "examples/blawx/benefit.l4",
                                       "-o", "examples/blawx/refused.pl"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("--scasp" `isInfixOf`)

    it "rejects a DATE-sorted field by name (Blawx v1)" $ do
      Output code _ serr <- runL4 bin ["blawx", "examples/blawx/not-ok/dates.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("dates (Blawx v1)" `isInfixOf`)

    it "rejects an unstratified module (the middle-end records, this leg refuses)" $ do
      Output code _ serr <- runL4 bin ["blawx", "examples/blawx/not-ok/unstratified.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("unstratified negation (Blawx v1)" `isInfixOf`)

    it "rejects a relationship above the arity-10 block ceiling" $ do
      Output code _ serr <- runL4 bin ["blawx", "examples/blawx/not-ok/arity.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("above the block ceiling of 10" `isInfixOf`)

    it "fails on a file that does not typecheck" $
      expectFail bin ["blawx", errorFixture]

  -- The import direction (R14, spec §10 P5). `lift . emit = id` has two
  -- halves; this is the parse half, and it is checked in the only way that
  -- needs no foreign toolchain and no external corpus: emit a real document,
  -- read it back through every layer, and compare both the IR and the bytes.
  describe "l4 blawx --import" $ do
    it "round-trips each P1/P3 seed: emit -> parse -> the same block IR and the same bytes" $
      mapM_
        (\stem -> do
            Output code sout serr <- runL4 bin ["blawx", "examples/blawx/" ++ stem ++ ".l4", "--roundtrip"]
            unless (code == ExitSuccess) $
              expectationFailure (stem ++ ": --roundtrip failed\n--- stderr ---\n" ++ serr)
            sout `shouldSatisfy` ("IR and bytes unchanged" `isInfixOf`))
        ["benefit", "mortality", "scores", "sumlist"]

    it "parses an emitted .blawx back and reports a clean census" $ do
      Output code sout serr <- runL4 bin
        ["blawx", "--import", "--parse-only", "examples/blawx/expected/mortality.blawx"]
      unless (code == ExitSuccess) $
        expectationFailure ("--import --parse-only failed\n--- stderr ---\n" ++ serr)
      -- One machine-readable line, so the census harness need not scrape prose.
      sout `shouldSatisfy` ("CENSUS mortality clean" `isInfixOf`)
      sout `shouldSatisfy` ("workspaces=2 tests=3" `isInfixOf`)
      -- Our own emission is by construction not stale, so nothing warns.
      serr `shouldSatisfy` (not . ("stale-encoding" `isInfixOf`))

    it "names the row and the block when a document is outside the liftable fragment" $ do
      Output code _ serr <- runL4 bin
        ["blawx", "--import", "--parse-only", "tests-cli/fixtures/blawx-import/unsupported.blawx"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("blawx-parse/unsupported-block" `isInfixOf`)
      serr `shouldSatisfy` ("sec_1_section" `isInfixOf`)
      serr `shouldSatisfy` ("date_value" `isInfixOf`)

    it "warns per skipped disabled block rather than silently dropping it (P5-3)" $ do
      Output code _ serr <- runL4 bin
        ["blawx", "--import", "--parse-only", "tests-cli/fixtures/blawx-import/disabled.blawx"]
      code `shouldBe` ExitSuccess
      serr `shouldSatisfy` ("blawx-parse/disabled-block-skipped" `isInfixOf`)
      serr `shouldSatisfy` ("skipped disabled <query>" `isInfixOf`)

    it "refuses a stream whose first row is not the ruledoc" $ do
      Output code _ serr <- runL4 bin
        ["blawx", "--import", "--parse-only", "tests-cli/fixtures/blawx-import/no-ruledoc.blawx"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("blawx-parse/row-order" `isInfixOf`)

    it "refuses XML outside the Blockly subset by name and offset" $ do
      Output code _ serr <- runL4 bin
        ["blawx", "--import", "--parse-only", "tests-cli/fixtures/blawx-import/bad-xml.blawx"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("blawx-parse/xml-malformed" `isInfixOf`)
      serr `shouldSatisfy` ("mismatched close tag" `isInfixOf`)

    -- `l4 blawx` has no --help of its own (the subcommand parsers carry no
    -- helper), so the usage banner optparse prints on a bad option is where
    -- the surface is documented. Asserting on it keeps the new flags from
    -- being added to the parser and forgotten in the spec.
    it "documents the new flags in the usage banner" $ do
      Output code _ serr <- runL4 bin ["blawx", "--help"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("--import" `isInfixOf`)
      serr `shouldSatisfy` ("--parse-only" `isInfixOf`)
      serr `shouldSatisfy` ("--reemit" `isInfixOf`)

  -- The lift (R14's other half). Its evidence is `jl4/examples/blawx/imported/`,
  -- both halves of which the pipeline produced: `bird.l4` is what the lift
  -- emitted from upstream's own bird.yaml, and `bird.blawx` is what the
  -- renderers re-emitted from the same parsed blocks. The reference checkout
  -- is NOT a test dependency -- these tests read only what is committed.
  describe "l4 blawx --import (the lift)" $ do
    it "the committed bird artifact evaluates to the oracles recorded in it" $ do
      Output code sout serr <- runL4 bin ["run", "--trace", "none", "examples/blawx/imported/bird.l4"]
      unless (code == ExitSuccess) $
        expectationFailure ("l4 run on the lifted bird failed\n--- stderr ---\n" ++ serr)
      -- The four blawxtests, in document order: an unbound query filtered over
      -- the declared universe, then the three defeat-layer booleans. The last
      -- is the one the whole example exists for -- the [pingu] span makes NBA 5
      -- inapplicable, so NBA 3 survives and pingu cannot fly.
      let ls = lines sout
          results = [dropWhile (== ' ') l | (prev, l) <- zip ls (drop 1 ls), prev == "Result:"]
      results `shouldBe` ["LIST \"pingu\"", "TRUE", "TRUE", "TRUE"]

    it "re-lifting the re-emitted .blawx reproduces the same rules and the same oracles" $ do
      Output code sout serr <- runL4 bin ["blawx", "--import", "examples/blawx/imported/bird.blawx"]
      unless (code == ExitSuccess) $
        expectationFailure ("--import on the re-emitted bird failed\n--- stderr ---\n" ++ serr)
      -- The applies-idiom, the unfolded defeat layer, and the recorded answers.
      sout `shouldSatisfy` ("DECIDE `NBA 5 applies to x` x" `isInfixOf`)
      sout `shouldSatisfy` ("IF naf (`it is not the case that NBA 5 applies to x` x)" `isInfixOf`)
      sout `shouldSatisfy` ("AND NOT `the conclusion in NBA 2 that x can fly is defeated` x" `isInfixOf`)
      sout `shouldSatisfy` ("-- L4 oracle ==> LIST \"pingu\"" `isInfixOf`)
      length (filter ("-- L4 oracle ==> " `isPrefixOf`) (lines sout)) `shouldBe` 4

    it "refuses a document outside the liftable fragment, naming every construct" $ do
      Output code _ serr <- runL4 bin ["blawx", "--import", "examples/blawx/expected/sumlist.blawx"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("cannot lift this document to L4" `isInfixOf`)
      -- an n-ary relation is not a unary predicate over the object universe
      serr `shouldSatisfy` ("blawx-lift/relationship" `isInfixOf`)
      serr `shouldSatisfy` ("total_from/3" `isInfixOf`)
      -- and the refusal is BATCHED: one run names them all, so a caller does
      -- not have to fix them one at a time.
      serr `shouldSatisfy` ("go/4" `isInfixOf`)

    it "refuses a non-boolean attribute by name and value type" $ do
      Output code _ serr <- runL4 bin ["blawx", "--import", "examples/blawx/expected/benefit.blawx"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("blawx-lift/attribute-type" `isInfixOf`)
      serr `shouldSatisfy` ("has value type number" `isInfixOf`)

    it "--reemit writes the .blawx regenerated from the parsed blocks" $ do
      Output code sout serr <- runL4 bin
        ["blawx", "--import", "--reemit", "examples/blawx/expected/mortality.blawx"]
      unless (code == ExitSuccess) $
        expectationFailure ("--reemit failed\n--- stderr ---\n" ++ serr)
      -- Our own emission parsed and re-emitted is byte-identical to itself;
      -- that is the byte half of `lift . emit = id`, reached through the CLI
      -- rather than through --roundtrip's in-process comparison.
      original <- readFile "examples/blawx/expected/mortality.blawx"
      sout `shouldBe` original

  describe "l4 docassemble" $ do
    it "compiles the WHERE-heavy rodents example to its golden interview (R3 survival)" $
      expectGolden bin ["docassemble", "examples/docassemble/rodents-and-vermin.l4"]
                       "examples/docassemble/expected/rodents-and-vermin.yml"

    it "compiles the top-level IMPLIES seam example (R4 verdict driver)" $
      expectGolden bin ["docassemble", "examples/docassemble/seam.l4"]
                       "examples/docassemble/expected/seam.yml"

    it "compiles a 3-way enum CONSIDER to a radio question + elif chain (R6)" $
      expectGolden bin ["docassemble", "examples/docassemble/enum-triage.l4"]
                       "examples/docassemble/expected/enum-triage.yml"

    it "compiles TYPICALLY prefills + MAYBE optionality with Mako-hostile @desc (R7/R8/R9)" $
      expectGolden bin ["docassemble", "examples/docassemble/defaults.l4"]
                       "examples/docassemble/expected/defaults.yml"

    it "keeps attributes out of the DAObject namespace + inlines a computed field (R2)" $
      expectGolden bin ["docassemble", "examples/docassemble/computed-and-shadow.l4"]
                       "examples/docassemble/expected/computed-and-shadow.yml"

    it "emits a question for an ASSUME referenced only through an inlined function (R3)" $
      expectGolden bin ["docassemble", "examples/docassemble/assume-via-fn.l4"]
                       "examples/docassemble/expected/assume-via-fn.yml"

    it "drives the seam scope-first, never as the classical short-circuit (R4)" $ do
      Output code sout _ <- runL4 bin ["docassemble", "examples/docassemble/seam.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("if notice_rule_satisfied_scope:" `isInfixOf`)
      sout `shouldSatisfy` (not . ("not notice_rule_satisfied_scope or" `isInfixOf`))

    it "refuses a deontic body by name (Regulative, Blocking)" $ do
      Output code _ serr <- runL4 bin ["docassemble", "examples/docassemble/not-ok/deontic-body.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("deontic/regulative rule (PARTY MUST/MAY/SHANT) has no docassemble form" `isInfixOf`)

    -- M4 flips the two R8 refusals M1 shipped: `not-ok/maybe-number.l4` and
    -- `not-ok/just-payload-pattern.l4` are now `../maybe-scalars.l4`, a
    -- SUPPORTED example, and their assertions moved to the M4 describe block
    -- below. What is left refusing is `MAYBE <enum>` — see
    -- "still refuses MAYBE of an enum" there, which also pins the diagnostic
    -- against the false claim M4 would otherwise leave behind.

    it "refuses a post-sanitisation name collision, naming both originals" $ do
      Output code _ serr <- runL4 bin ["docassemble", "examples/docassemble/not-ok/name-collision.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("name collision: `t.notice_period`" `isInfixOf`)
      serr `shouldSatisfy` ("L4 `notice period`" `isInfixOf`)
      serr `shouldSatisfy` ("L4 `notice_period`" `isInfixOf`)

    it "refuses a function value passed as data, by the function's own name (R3)" $ do
      Output code _ serr <- runL4 bin ["docassemble", "examples/docassemble/not-ok/higher-order.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("higher-order use of function `is positive`" `isInfixOf`)

    it "refuses a seam-goal reference that travels through an inlined function (R4 guard)" $ do
      Output code _ serr <- runL4 bin ["docassemble", "examples/docassemble/not-ok/seam-ref-via-fn.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("seam-shaped export (top-level IMPLIES) is referenced by another decision" `isInfixOf`)

    it "gates on advisory fidelity notes with --fail-on=advisory" $
      expectFail bin ["docassemble", "examples/docassemble/defaults.l4", "--fail-on=advisory"]

    it "emits only block keys docassemble 1.10.7 recognises (R9.5 vocabulary)" $
      DAEmit.emitterVocabularyViolations `shouldBe` []

    it "fails on a file that does not typecheck" $
      expectFail bin ["docassemble", errorFixture]

    -- M1 regression, tightened for M2: the six goldens above pin STDOUT.
    -- `-o` is a different code path (it also drops the fidelity report into a
    -- sibling .fidelity.txt), and the six committed .fidelity.txt files were
    -- pinned by no test at all. Both are pinned here so that M2's --package
    -- work cannot quietly change the bare artifact.
    it "writes to --output exactly the stdout bytes, plus the committed fidelity sidecar" $
      for_ daBareExamples \stem -> do
        tmp <- getTemporaryDirectory
        let outFile = tmp </> ("l4-da-out-" ++ stem ++ ".yml")
            sidecar = tmp </> ("l4-da-out-" ++ stem ++ ".fidelity.txt")
        removePathForcibly outFile
        removePathForcibly sidecar
        Output code sout serr <-
          runL4 bin ["docassemble", daExampleDir </> (stem ++ ".l4"), "-o", outFile]
        unless (code == ExitSuccess) $
          expectationFailure (stem ++ ": -o run failed\n--- stderr ---\n" ++ serr)
        sout `shouldBe` ""
        written   <- readUtf8 outFile
        goldenYml <- readUtf8 (daExampleDir </> "expected" </> (stem ++ ".yml"))
        unless (written == goldenYml) $
          expectationFailure (stem ++ ": -o bytes differ from the committed golden")
        haveSidecar <- doesFileExist sidecar
        unless haveSidecar $
          expectationFailure (stem ++ ": -o wrote no .fidelity.txt sibling")
        gotReport  <- readUtf8 sidecar
        wantReport <- readUtf8 (daExampleDir </> "expected" </> (stem ++ ".fidelity.txt"))
        unless (gotReport == wantReport) $
          expectationFailure $
            stem ++ ": fidelity sidecar differs from its committed golden"
            ++ "\n--- got ---\n" ++ gotReport ++ "\n--- golden ---\n" ++ wantReport
        removePathForcibly outFile
        removePathForcibly sidecar

  ----------------------------------------------------------------------------
  -- M2 (spec §10): the installable package tree (R11 §8.11)
  --
  -- R11 is explicit that this artifact gets "a shape test, not byte goldens",
  -- so every assertion below is about the SHAPE of the written tree: which
  -- files exist, which must NOT exist, what they say, and that two runs agree.
  ----------------------------------------------------------------------------
  describe "l4 docassemble --package (M2/R11: the installable package tree)" $ do
    it "writes the PEP 420 shape, including the namespace __init__.py that must be ABSENT" $ do
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-shape"
      files <- expectPackage bin daCitationsSource dir
      let wanted =
            [ "pyproject.toml"
            , "MANIFEST.in"
            -- R11 decision 4: the fidelity report is part of the shape, at the
            -- package root under the same-stem convention `-o FILE` uses.
            , "citations.fidelity.txt"
            , daPkgInner </> "__init__.py"
            , daPkgInner </> "l4runtime.py"
            , daPkgInner </> "data" </> "questions" </> "citations.yml"
            , daPkgInner </> "data" </> "sources"   </> "citations.l4"
            ]
      for_ wanted \want ->
        unless (want `elem` files) $
          expectationFailure $
            "package tree is missing " ++ show want
            ++ "\n--- tree ---\n" ++ unlines files
      -- The absence is a REQUIREMENT, not a detail: setuptools' pyproject path
      -- defaults to PEP 420 namespace finding, and a namespace __init__.py
      -- turns `docassemble` into a regular package that shadows the installed
      -- `docassemble.base`. The 1.10.7 exemplar has no such file — verified by
      -- `git ls-tree -r 1b6678384 docassemble_demo/ | grep -c
      -- 'docassemble_demo/docassemble/__init__.py'` => 0.
      let nsInit = "docassemble" </> "__init__.py"
      when (nsInit `elem` files) $
        expectationFailure $
          "package tree contains " ++ show nsInit
          ++ ", which breaks PEP 420 namespace finding (R11)"
      removePathForcibly dir

    it "writes a pyproject.toml naming the package, an SPDX licence, and the Python floor" $ do
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-toml"
      _ <- expectPackage bin daCitationsSource dir
      toml <- readUtf8 (dir </> "pyproject.toml")
      let has = shouldContain' "pyproject.toml" toml
      has "docassemble.l4citations"
      has "license = \""            -- PEP 639 SPDX expression, string form
      -- R11: `requires-python >= 3.12` (docassemble_base/pyproject.toml:14 at
      -- 1b6678384). Asserted as ONE substring: `has "requires-python"` and
      -- `has "3.12"` as two independent whole-file checks would be satisfied by
      -- a floor of ">= 3.9" beside any other mention of 3.12 — a comment, a
      -- classifier, a dependency pin — which is not the claim R11 makes.
      has "requires-python = \">= 3.12\""
      has "[tool.setuptools.packages.find]"
      has "where = [\".\"]"
      has "docassemble.base"        -- an installable package depends on the runtime
      removePathForcibly dir

    it "writes a MANIFEST.in grafting the data directory and shipping the report" $ do
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-manifest"
      _ <- expectPackage bin daCitationsSource dir
      manifest <- readUtf8 (dir </> "MANIFEST.in")
      shouldContain' "MANIFEST.in" manifest ("graft " ++ (daPkgInner </> "data"))
      -- MANIFEST.in governs the sdist, and a root-level file is not package
      -- data, so without this line R11 decision 4's "and MANIFEST.in includes
      -- it so it ships" is false and nothing would notice.
      shouldContain' "MANIFEST.in" manifest "include citations.fidelity.txt"
      removePathForcibly dir

    it "writes the same fidelity report the bare -o run writes, at the package root" $ do
      -- R11 decision 4 places the report at the package root rather than under
      -- data/. Its CONTENT is pinned for the bare `-o` path by the
      -- daBareExamples golden loop above; this asserts the --package copy is
      -- the same bytes, so the two placements cannot drift.
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-fidelity"
      _ <- expectPackage bin daCitationsSource dir
      got  <- readUtf8 (dir </> "citations.fidelity.txt")
      want <- readUtf8 (daExampleDir </> "expected" </> "citations.fidelity.txt")
      unless (got == want) $
        expectationFailure $
          "the packaged fidelity report differs from the committed golden"
          ++ "\n--- got ---\n" ++ got ++ "\n--- golden ---\n" ++ want
      removePathForcibly dir

    it "writes an l4runtime.py carrying the provenance API its __all__ promises" $ do
      -- Existence was asserted; content was not, and the module is the whole
      -- reason `modules:` exists in the packaged interview (R11 decision 6).
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-runtime"
      _ <- expectPackage bin daCitationsSource dir
      rt <- readUtf8 (dir </> daPkgInner </> "l4runtime.py")
      let has = shouldContain' "l4runtime.py" rt
      has "__all__"
      -- The author's spelling of the source file survives here even though the
      -- on-disk copy is renamed to <slug>.l4 (R11 decision 3).
      has "L4_SOURCE_NAME = 'citations.l4'"
      has "L4_PACKAGE_NAME = 'docassemble.l4citations'"
      has "def l4_source_path():"
      has "def l4_source_text():"
      -- It must define nothing the interview CALLS: the bare and packaged
      -- artifacts have to mean the same thing, so anything the interview needed
      -- would have to work bare too, where there is no runtime module at all.
      yml <- readUtf8 (dir </> daPkgInner </> "data" </> "questions" </> "citations.yml")
      for_ ["l4_source_path(", "l4_source_text(", "L4_SOURCE_NAME"] \name ->
        shouldNotContain' "the packaged interview" yml name
      removePathForcibly dir

    it "writes an __init__.py that opts the package out of docassemble's pre-load scan" $ do
      -- `# do not pre-load` is not decoration: docassemble's package scanner
      -- breaks out of the file on exactly that prefix
      -- (docassemble_webapp/.../packages/helpers.py:63 at 1b6678384), which is
      -- what keeps a generated package from being imported at server start.
      -- It is also byte-for-byte the shape of docassemble_demo's own __init__.
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-init"
      _ <- expectPackage bin daCitationsSource dir
      ini <- readUtf8 (dir </> daPkgInner </> "__init__.py")
      unless ("# do not pre-load" `isPrefixOf` ini) $
        expectationFailure $
          "the generated __init__.py does not open with `# do not pre-load`, so "
          ++ "docassemble's pre-load scan would keep reading it\n--- got ---\n" ++ ini
      removePathForcibly dir

    it "replaces a previous run rather than accumulating beside it" $ do
      -- Writing without deleting meant that regenerating after the .l4 was
      -- RENAMED left the whole previous inner package in the tree, and
      -- `[tool.setuptools.packages.find] where = ["."]` then found both: a
      -- wheel declaring itself docassemble.l4beta shipped an importable
      -- docassemble.l4alpha whose l4_source_text() had no data file behind it.
      -- The slug follows the source basename by design, so a rename is the
      -- designed trigger, and the command reported success throughout.
      tmp <- getTemporaryDirectory
      let srcDir = tmp </> "l4-da-regen-src"
          dir    = tmp </> "l4-da-regen"
          alpha  = srcDir </> "alpha.l4"
          beta   = srcDir </> "beta.l4"
      removePathForcibly srcDir
      removePathForcibly dir
      createDirectoryIfMissing True srcDir
      copyFile daCitationsSource alpha
      copyFile daCitationsSource beta
      _ <- expectPackage bin alpha dir
      -- expectPackage clears the directory first, so regenerate by hand.
      Output code _ serr <- runL4 bin ["docassemble", beta, "--package", dir]
      unless (code == ExitSuccess) $
        expectationFailure ("regeneration failed\n--- stderr ---\n" ++ serr)
      files <- treeFiles dir
      let stale = [ f | f <- files, "l4alpha" `isInfixOf` f ]
      unless (null stale) $
        expectationFailure $
          "regenerating after a rename left the previous package in the tree: "
          ++ show stale ++ "\n--- tree ---\n" ++ unlines files
      unless ((("docassemble" </> "l4beta") </> "l4runtime.py") `elem` files) $
        expectationFailure $
          "the regenerated package is missing\n--- tree ---\n" ++ unlines files
      unless ("beta.fidelity.txt" `elem` files) $
        expectationFailure $
          "the regenerated fidelity report is missing\n--- tree ---\n" ++ unlines files
      unless ("alpha.fidelity.txt" `notElem` files) $
        expectationFailure $
          "the previous run's fidelity report survived regeneration\n--- tree ---\n"
          ++ unlines files
      removePathForcibly srcDir
      removePathForcibly dir

    it "leaves a file the user put in their own package directory alone" $ do
      -- The prune above must not become a licence to delete: guardClobber
      -- establishes that we WROTE this tree, not that we own every file in it.
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-regen-keep"
      _ <- expectPackage bin daCitationsSource dir
      writeFile (dir </> "NOTES.md") "hand-written, not ours\n"
      Output code _ serr <- runL4 bin ["docassemble", daCitationsSource, "--package", dir]
      unless (code == ExitSuccess) $
        expectationFailure ("regeneration failed\n--- stderr ---\n" ++ serr)
      kept <- readUtf8 (dir </> "NOTES.md")
      kept `shouldBe` "hand-written, not ours\n"
      removePathForcibly dir

    it "embeds the .l4 source byte-identically under data/sources (that is what provenance means)" $ do
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-provenance"
      _ <- expectPackage bin daCitationsSource dir
      orig   <- BS.readFile daCitationsSource
      copied <- BS.readFile (dir </> daPkgInner </> "data" </> "sources" </> "citations.l4")
      unless (copied == orig) $
        expectationFailure
          "data/sources/citations.l4 is not byte-identical to the input .l4"
      removePathForcibly dir

    it "puts the interview under data/questions and wires the runtime module via modules:" $ do
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-questions"
      _ <- expectPackage bin daCitationsSource dir
      yml <- readUtf8 (dir </> daPkgInner </> "data" </> "questions" </> "citations.yml")
      -- It is the interview, not a stub: the driver and the goal block are in it.
      shouldContain' "data/questions/citations.yml" yml "id: driver_offering_exempt"
      shouldContain' "data/questions/citations.yml" yml "id: c_offering_exempt"
      -- R11: the runtime module is a SIBLING of data/, loaded as `.l4runtime`.
      -- The leading dot is package-name concatenation: docassemble execs
      -- `from <question.package><name> import *` (parse.py:8569-8573 at
      -- 1b6678384), so `.l4runtime` resolves to
      -- docassemble.l4citations.l4runtime.
      shouldContain' "data/questions/citations.yml" yml "modules:"
      shouldContain' "data/questions/citations.yml" yml ".l4runtime"
      removePathForcibly dir

    it "leaves no empty directory anywhere in the tree" $ do
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-empties"
      _ <- expectPackage bin daCitationsSource dir
      empties <- emptyTreeDirs dir
      unless (null empties) $
        expectationFailure $
          "empty directories in the package tree (they survive neither git nor "
          ++ "zip, R11): " ++ show empties
      removePathForcibly dir

    it "is deterministic: two runs write identical trees" $ do
      tmp <- getTemporaryDirectory
      let dirA = tmp </> "l4-da-pkg-detA"
          dirB = tmp </> "l4-da-pkg-detB"
      filesA <- expectPackage bin daCitationsSource dirA
      filesB <- expectPackage bin daCitationsSource dirB
      unless (filesA == filesB) $
        expectationFailure $
          "two --package runs wrote different file sets:\n" ++ show filesA
          ++ "\nvs\n" ++ show filesB
      for_ filesA \f -> do
        a <- BS.readFile (dirA </> f)
        b <- BS.readFile (dirB </> f)
        unless (a == b) $
          expectationFailure ("--package is non-deterministic in " ++ show f)
      removePathForcibly dirA
      removePathForcibly dirB

    -- RULING TAKEN BY THIS TEST: --package and --output are two different
    -- artifact shapes (a directory vs a file), and `-o` is already overloaded
    -- house-wide (FILE in eight verbs, DIR in `l4 trace`). Honouring one and
    -- silently ignoring the other is the failure mode with no precedent to
    -- lean on, so the combination is REFUSED by name. The exact phrase is
    -- pinned because optparse's own "Invalid option" message happens to
    -- contain both option names via the usage line, which would let a
    -- generic assertion pass for the wrong reason.
    it "refuses --package together with --output, by name" $ do
      tmp <- getTemporaryDirectory
      let dir  = tmp </> "l4-da-pkg-conflict"
          file = tmp </> "l4-da-pkg-conflict.yml"
      removePathForcibly dir
      removePathForcibly file
      Output code _ serr <-
        runL4 bin ["docassemble", daCitationsSource, "-o", file, "--package", dir]
      code `shouldBe` ExitFailure 1
      shouldContain' "stderr" serr "--package cannot be combined with --output"
      wroteFile <- doesFileExist file
      wroteDir  <- doesDirectoryExist dir
      unless (not wroteFile && not wroteDir) $
        expectationFailure "a refused invocation still wrote an artifact"
      removePathForcibly dir
      removePathForcibly file

    it "derives an ASCII package slug from a hostile filename" $ do
      -- `moduleSource` is a PERCENT-ENCODED URI segment and `pyIdent` keeps
      -- non-ASCII letters, so a slug taken from either inherits `%20`/`%C3%A9`
      -- or a bare `é` — neither is usable as an on-disk Python package name.
      tmp <- getTemporaryDirectory
      let srcDir = tmp </> "l4-da-hostile-src"
          src    = srcDir </> "2024 Café Rules v2.1.l4"
          dir    = tmp </> "l4-da-pkg-hostile"
      removePathForcibly srcDir
      createDirectoryIfMissing True srcDir
      copyFile daCitationsSource src
      _ <- expectPackage bin src dir
      inner <- listDirectory (dir </> "docassemble")
      case filter (/= "__init__.py") inner of
        [pkgName] -> do
          unless ("l4" `isPrefixOf` pkgName) $
            expectationFailure $
              "generated package " ++ show pkgName ++ " is not `l4<slug>` (R11)"
          let ok c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
          unless (all ok pkgName) $
            expectationFailure $
              "generated package name " ++ show pkgName
              ++ " is not lowercase ASCII alphanumeric; a percent-encoded or "
              ++ "non-ASCII slug is not a usable Python package name"
          toml <- readUtf8 (dir </> "pyproject.toml")
          shouldContain' "pyproject.toml" toml ("docassemble." ++ pkgName)
          -- provenance survives the rename: whatever the source file is called
          -- inside the package, its bytes are the input's bytes
          let srcsDir = dir </> "docassemble" </> pkgName </> "data" </> "sources"
          srcs <- listDirectory srcsDir
          case srcs of
            [one] -> do
              orig   <- BS.readFile src
              copied <- BS.readFile (srcsDir </> one)
              unless (copied == orig) $
                expectationFailure "data/sources copy is not byte-identical"
            other -> expectationFailure $
              "expected exactly one file under data/sources, got " ++ show other
        other -> expectationFailure $
          "expected exactly one generated package under docassemble/, got "
          ++ show other
      removePathForcibly srcDir
      removePathForcibly dir

  ----------------------------------------------------------------------------
  -- M2 (spec §10): @ref citations on the verdict screen, and the glossary
  --
  -- The claim this milestone is worth having for: the verdict screen cites the
  -- law that ACTUALLY decided the case. Short-circuited rules did not decide
  -- anything, so citing them would be citing law that never fired.
  ----------------------------------------------------------------------------
  describe "l4 docassemble citations (M2: @ref citations and the glossary)" $ do
    it "attaches each rule's own @ref to that rule's own code block, via explain()" $ do
      Output code sout serr <- runL4 bin ["docassemble", daCitationsSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)

      -- Rule 1: the plain `@ref` form.
      cap <- blockWithId sout "c_offering_exempt_within_the_annual_cap"
      shouldContain'    "the `within the annual cap` code block" cap "explain("
      shouldContain'    "the `within the annual cap` code block" cap daCite1
      -- A node's Anno carries at most one Ref and the NEAREST preceding ref
      -- wins (`attachRef` in ResolveAnnotation.hs), so "picked up the
      -- neighbour's citation" is a real failure mode and gets its own
      -- assertion.
      shouldNotContain' "the `within the annual cap` code block" cap daCite2
      shouldNotContain' "the `within the annual cap` code block" cap daCite3Tail
      shouldNotContain' "the `within the annual cap` code block" cap daCiteGoal

      -- Rule 2: the inline `<< >>` ref form.
      via <- blockWithId sout "c_offering_exempt_sold_through_a_single_intermediary"
      shouldContain'    "the `sold through a single intermediary` code block" via "explain("
      shouldContain'    "the `sold through a single intermediary` code block" via daCite2
      shouldNotContain' "the `sold through a single intermediary` code block" via daCite1
      shouldNotContain' "the `sold through a single intermediary` code block" via daCite3Tail
      shouldNotContain' "the `sold through a single intermediary` code block" via daCiteGoal

      -- Rule 3: the Mako-hostile ref.
      reg <- blockWithId sout "c_offering_exempt_the_intermediary_is_registered"
      shouldContain'    "the `the intermediary is registered` code block" reg "explain("
      shouldContain'    "the `the intermediary is registered` code block" reg daCite3Tail
      shouldNotContain' "the `the intermediary is registered` code block" reg daCite1
      shouldNotContain' "the `the intermediary is registered` code block" reg daCite2
      shouldNotContain' "the `the intermediary is registered` code block" reg daCiteGoal

      -- The exported DECIDE carries a @ref of its own, which attaches to the
      -- TopDecl node rather than the inner MkDecide and rides onto the GOAL
      -- code block. That path was implemented but exercised by no fixture
      -- until this one; it is also the only place the emitted ORDER is
      -- observable (see `daCiteGoal`).
      goal <- blockWithId sout "c_offering_exempt"
      shouldContain'    "the `offering exempt` goal code block" goal "explain("
      shouldContain'    "the `offering exempt` goal code block" goal daCiteGoal
      shouldNotContain' "the `offering exempt` goal code block" goal daCite1
      shouldNotContain' "the `offering exempt` goal code block" goal daCite2
      shouldNotContain' "the `offering exempt` goal code block" goal daCite3Tail
      -- The design rule the citation list depends on, asserted as a claim: the
      -- explain() call sits AFTER the assignment, because a block whose
      -- assignment raises on an undefined input has decided nothing and
      -- docassemble re-runs it once the input arrives. Cite first and the goal
      -- records itself before the rules it pulls on — measured, and caught by
      -- the round-trip harness's ordered citation list only because the goal
      -- carries a @ref at all.
      for_ [ ("c_offering_exempt_within_the_annual_cap", daCite1)
           , ("c_offering_exempt_sold_through_a_single_intermediary", daCite2)
           , ("c_offering_exempt_the_intermediary_is_registered", daCite3Tail)
           , ("c_offering_exempt", daCiteGoal)
           ] \(bid, cite) -> do
        blk <- blockWithId sout bid
        shouldPrecede ("the " ++ bid ++ " code block") blk " = " "explain('"
        shouldContain' ("the " ++ bid ++ " code block") blk cite

    it "renders logic_explanation() on every verdict screen" $ do
      Output code sout serr <- runL4 bin ["docassemble", daCitationsSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)
      for_ ["ev_offering_exempt_screen_holds", "ev_offering_exempt_screen_fails"] \sid -> do
        blk <- blockWithId sout sid
        shouldContain' ("the " ++ sid ++ " screen") blk "logic_explanation()"

    it "emits one `auto terms:` glossary block, keyed on the L4 defined terms" $ do
      Output code sout serr <- runL4 bin ["docassemble", daCitationsSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)
      case [ b | b <- yamlBlocks sout, "auto terms:" `isInfixOf` b ] of
        [glossary] -> do
          for_
            [ ( "Offering"
              , "A securities offering made in reliance on the crowdfunding exemption" )
            , ( "within the annual cap"
              , "The amount sold in reliance on the exemption in the preceding 12 months does not exceed $5,000,000" )
            , ( "sold through a single intermediary"
              , "The offering is conducted exclusively through a single intermediary" )
            , ( "the intermediary is registered"
              , "The intermediary is registered with the Commission as a funding portal" )
            ] \(term, defn) -> do
              shouldContain' "the `auto terms:` glossary" glossary term
              shouldContain' "the `auto terms:` glossary" glossary defn
          -- docassemble only reads `auto terms` from a block that has no
          -- `question` key: `if 'auto terms' in data and 'question' not in
          -- data` (parse.py:2878 at 1b6678384). A glossary emitted inside a
          -- question block is silently ignored.
          shouldNotContain' "the `auto terms:` glossary block" glossary "question:"
        other -> expectationFailure $
          "expected exactly one `auto terms:` block, found " ++ show (length other)
          ++ "\n--- emitted interview ---\n" ++ sout

    it "strips L4's own `@ref ` herald and the inline `<< >>` delimiters" $ do
      Output code sout serr <- runL4 bin ["docassemble", daCitationsSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)
      -- The inline form's text must ARRIVE …
      shouldContain' "the emitted interview" sout daCite2
      -- … but neither ref spelling may reach a user-facing screen as syntax.
      -- `getRef` does NOT strip the herald (unlike `getDesc`): the payload of
      -- `@ref X` is the text "@ref X", verbatim.
      shouldNotContain' "the emitted interview" sout "@ref "
      shouldNotContain' "the emitted interview" sout "<<17 CFR"
      shouldNotContain' "the emitted interview" sout "intermediary only>>"

    it "escapes Mako-hostile citation text (R9.1, the `defaults` discipline applied to @ref)" $ do
      Output code sout serr <- runL4 bin ["docassemble", daCitationsSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)
      -- carried at all
      shouldContain' "the emitted interview" sout daCite3Tail
      -- never as a line Mako would read as a control line: the citation begins
      -- with `%`, and a line-leading `%` makes the whole line vanish.
      let hostileControlLine ln =
            "%" `isPrefixOf` dropWhile (`elem` (" \t" :: String)) ln
              && "of the proceeds retained" `isInfixOf` ln
      case filter hostileControlLine (lines sout) of
        [] -> pure ()
        bad -> expectationFailure $
          "citation emitted as a Mako control line (it would vanish from the "
          ++ "screen): " ++ show bad
      -- and never as a LIVE `${ … }` inside a Mako-rendered screen: either the
      -- text is escaped in place (escapeL4) or interpolated at render time.
      for_ ["ev_offering_exempt_screen_holds", "ev_offering_exempt_screen_fails"] \sid -> do
        blk <- blockWithId sout sid
        shouldNotContain' ("the " ++ sid ++ " screen") blk "${ fee_schedule }"

    -- Added by the GREEN phase, which the RED phase asked for by name: the
    -- shape assertions above say what must be true of the M2 emission, and
    -- this pins the exact bytes so a later change to the citation or glossary
    -- rendering has to be deliberate. It is the same `expectGolden` contract
    -- the six M1 examples ride on.
    it "compiles the @ref citations + glossary example to its golden interview" $
      expectGolden bin ["docassemble", daCitationsSource]
                       "examples/docassemble/expected/citations.yml"

    it "declares the M2 block keys in its own emitter vocabulary (R9.5)" $ do
      -- `modules` and `auto terms` are already in the vendored 1.10.7
      -- whitelist; they are NOT yet in the emitter's declaration of what it
      -- writes, so `emitterVocabularyViolations == []` would keep passing
      -- while silently stopping to describe the emitter.
      let declared = map T.unpack DAEmit.emitterKeyVocabulary
          missing  = [k | k <- ["auto terms", "modules"], k `notElem` declared]
      missing `shouldBe` []

    it "keeps block keys and field modifiers in separate vocabularies (R9.5)" $ do
      -- `daRecognisedKeys` is parse.py:1947, the whitelist docassemble applies
      -- to TOP-LEVEL BLOCK KEYS only (parse.py:1946-1948 iterates the block
      -- dict under `if self.interview.debug`); field modifiers are read in a
      -- different place entirely. Checking the two lists together against one
      -- whitelist gave false assurance in both directions: `mandatory` and
      -- `subquestion` are members and yet break a field
      -- (`Syntax error: field label 'mandatory' overwrites previous label`,
      -- measured against 1.10.7), while real modifiers like `show if` are not
      -- members at all. Docassemble has no field-modifier whitelist to vendor,
      -- so the repair is to stop pretending it does.
      let blockKeys = map T.unpack DAEmit.emitterBlockKeys
          modifiers = map T.unpack DAEmit.emitterFieldModifiers
      DAEmit.emitterVocabularyViolations `shouldBe` []
      [k | k <- modifiers, k `elem` blockKeys] `shouldBe` []
      sort (blockKeys ++ modifiers) `shouldBe` sort (map T.unpack DAEmit.emitterKeyVocabulary)

  ----------------------------------------------------------------------------
  -- M2 repair cases: losses that used to be silent, and one that used to
  -- change the answer.
  ----------------------------------------------------------------------------
  describe "l4 docassemble (M2 repairs: declared losses and reserved names)" $ do
    it "declares both ways an `auto terms:` entry cannot survive, and drops them" $ do
      Output code sout serr <- runL4 bin ["docassemble", daGlossLossSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)

      -- (1) A regex metacharacter in the term. Docassemble interpolates an
      -- `auto terms` key straight into a regex with no re.escape
      -- (parse.py:2908 at 1b6678384): a balanced `(...)` becomes a capture
      -- group whose pattern no longer matches its own term, and an unbalanced
      -- one raises re.error while the Interview is constructed, so the emitted
      -- interview cannot be LOADED at all — while `l4 check` and
      -- `l4 docassemble` both report success and the report said
      -- "(nothing lost)".
      shouldContain'    "stderr" serr "DA-GLOSS-REGEX"
      shouldContain'    "stderr" serr "s 12(1)"
      shouldNotContain' "the emitted interview" sout "REGEXDROPPEDGLOSS"

      -- (2) Two terms folding onto one key. What that costs is not a duplicate
      -- key but the loser's whole definition.
      shouldContain'    "stderr" serr "DA-GLOSS-COLLIDE"
      shouldContain'    "stderr" serr "folds onto"
      shouldNotContain' "the emitted interview" sout "COLLIDEDROPPEDGLOSS"

      -- What survives: the winner, deterministically the first spelling.
      case [ b | b <- yamlBlocks sout, "auto terms:" `isInfixOf` b ] of
        [glossary] -> do
          shouldContain'    "the glossary" glossary
            "\"Notice\": \"A formal notice served under the Act\""
          shouldNotContain' "the glossary" glossary "s 12(1)"
        other -> expectationFailure $
          "expected exactly one `auto terms:` block, found " ++ show (length other)

    it "reserves the generated runtime module's names, in both artifact shapes" $ do
      -- `modules: [.l4runtime]` is exec'd as `from <pkg>.l4runtime import *`
      -- (parse.py:8572 at 1b6678384) into the interview dict on every assemble
      -- pass. `__all__` bounds WHICH names arrive; it does nothing to stop an
      -- interview variable from being one of them, and the loser is the
      -- interview's — so the packaged artifact asked no question and returned
      -- the opposite verdict to the bare one (R11 decision 6 says the two
      -- shapes must mean the same thing). The bare artifact reserves the name
      -- too, so the shapes cannot disagree about a variable's NAME either.
      Output code sout serr <- runL4 bin ["docassemble", daRuntimeCollisionSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)
      shouldContain' "the emitted interview" sout "l4_source_text_ = d.filed_on_time"
      case [ ln | ln <- lines sout, "l4_source_text " `isInfixOf` (ln ++ " ") ] of
        [] -> pure ()
        bad -> expectationFailure $
          "an interview variable is spelled exactly like a name the runtime "
          ++ "module star-imports: " ++ show bad

      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-reserved"
      _ <- expectPackage bin daRuntimeCollisionSource dir
      files <- treeFiles dir
      case [ f | f <- files, ("data" </> "questions") `isInfixOf` f ] of
        [ymlPath] -> do
          yml <- readUtf8 (dir </> ymlPath)
          shouldContain' "the packaged interview" yml "l4_source_text_ = d.filed_on_time"
          shouldContain' "the packaged interview" yml ".l4runtime"
        other -> expectationFailure $
          "expected exactly one interview under data/questions, got " ++ show other
      removePathForcibly dir

  ----------------------------------------------------------------------------
  -- M4 (spec §10): breadth. ACCEPTANCE TESTS, WRITTEN FAIL-FIRST.
  --
  -- Every test in this block was RED at the commit that introduced it, and each
  -- was red for a reason the tool stated in words: M1 refused each of these
  -- constructs BY NAME, so the failure was `l4 docassemble` exiting 1 with
  -- prose naming the milestone that owed the answer — not a missing symbol,
  -- not a typo, not a compile error. `daEmit` still prints that stderr verbatim,
  -- which is what makes a regression legible. The block is GREEN as of
  -- 2026-08-17, together with `m4_acceptance.sh`, its behavioural half.
  --
  -- Three of these tests would still have been red after a naive
  -- implementation, and that is deliberate; they are the ones worth having:
  --
  --   * the leap-day case in "computes statutory age calendar-exactly", where
  --     dateutil's `relativedelta` CLAMPS and L4's `Date` ROLLS FORWARD.
  --     Measured over 27,028 comparisons (every birth date 1970-01-01 to
  --     2006-12-31, tested on the L4 majority date and the day before):
  --     `date_difference(...).years >= 18` disagrees with L4 on 6,629;
  --     `born.plus(years=18) <= assessed` disagrees on 9, all of them
  --     leap-day births; `born <= assessed.minus(years=18)` disagrees on
  --     NONE. The forward form is the wrong one against this oracle.
  --   * "still refuses MAYBE of an enum", which was red not because the
  --     refusal was missing but because the refusal's PROSE became a false
  --     claim the moment MAYBE NUMBER and MAYBE DATE landed.
  --   * the `show if:` spelling, where the `{variable:, is:}` form parses,
  --     renders, and is browser-side JavaScript only — it defines every field
  --     under an API drive and cannot encode a constructor payload at all.
  --
  -- No M4 example carries a byte golden here. See `daListSource` for why.
  ----------------------------------------------------------------------------
  describe "l4 docassemble (M4: breadth — acceptance)" $ do

    ------------------------------------------------------------------------
    -- A. `LIST OF` via DAList gathering
    ------------------------------------------------------------------------
    it "gathers a LIST OF input as a DAList with a per-element question (A)" $ do
      out <- daEmit bin daListSource

      -- The list must ride as a DAList with an element class. `object_type`
      -- is not decoration: a `DAList.using(complete_attribute=…)` with no
      -- object_type fails on the first element access (ablation-probed
      -- against 1.10.7, variant G).
      shouldContain' "the emitted interview" out "DAList"
      shouldContain' "the emitted interview" out "object_type"

      -- Gather control. Two shapes were probed working and the RED phase
      -- declines to choose: `there_are_any` + `there_is_another` (dropping
      -- EITHER raises DAErrorMissingVariable), or `ask_number` +
      -- `target_number`, which replaces both with a single count question.
      shouldContainAny "the emitted interview" out
        ["there_is_another", "target_number"]

      -- A per-element question. Element attributes are reached either through
      -- a `generic object:` block or through explicitly indexed assignments;
      -- a bare `tenants.age` raises DAAttributeError (probed).
      shouldContainAny "the emitted interview" out
        ["generic object:", "[i]", "for _i in"]

      -- The goal quantifies over the gathered list rather than over a fixed
      -- number of fields. `all` and `any` are the whole list-consumption
      -- surface the docassemble-relevant corpus uses.
      shouldContainAny "the goal code" out ["all(", "any("]

    it "asks a list element's later attribute only when the earlier one leaves it open (A)" $ do
      -- The property the backend sells, at the level where it is provable
      -- from the emission: `the tenant qualifies` is `age AT LEAST 18 AND
      -- signed`, so the signing test must be guarded by the age test WITHIN
      -- one element. Docassemble prunes per element inside a gather (probed:
      -- element 0 aged 17 never had its `has_lease` asked), so a lowering
      -- that evaluates both attributes eagerly — say by building a list of
      -- booleans first — throws that away silently.
      out <- daEmit bin daListSource
      shouldContainAny "the per-element predicate" out
        [ "age >= 18 and", "(x.age >= 18) and", "age >= 18) and" ]
      -- and it must not have been flattened into an eager per-element list
      shouldNotContain' "the emitted interview" out "complete_elements()"

    ------------------------------------------------------------------------
    -- B. constructor payloads via `show if`
    ------------------------------------------------------------------------
    it "emits a payload follow-up gated by a SERVER-SIDE `show if` (B)" $ do
      out <- daEmit bin daPayloadSource

      -- The enum still rides as a radio over constructor-name strings (R6),
      -- with the payload-bearing constructors among the choices.
      shouldContain' "the emitted interview" out "datatype: radio"
      shouldContain' "the emitted interview" out "granted subject to conditions"
      shouldContain' "the emitted interview" out "refused"

      -- Each payload becomes its own follow-up field of its own datatype.
      shouldContain' "the emitted interview" out "the_number_of_conditions"
      shouldContain' "the emitted interview" out "the_stated_ground_of_refusal"

      -- THE CORRECTNESS PIVOT. `show if:` must carry a `code:` sub-key. The
      -- `{variable:, is:}` spelling sets show_if_var/show_if_val and no
      -- showif_code (parse.py:3998-4002 at 1b6678384): it is browser-side
      -- JavaScript, the engine shows every field, and a headless or API drive
      -- DEFINES them all. Only the code form leaves a hidden field genuinely
      -- undefined (parse.py:6316-6325 evals showif_code and sets
      -- extras['ok'][n] = False at 6320/6324).
      shouldContain' "the emitted interview" out "show if:"
      case [ b | b <- yamlBlocks out, "show if:" `isInfixOf` b ] of
        [] -> expectationFailure "no block carries a `show if:` at all"
        blocks -> for_ blocks \b -> do
          shouldContain'    "the `show if:` block" b "code:"
          shouldNotContain' "the `show if:` block" b "is: "

      -- `show if` is FIELD-level only. It is not among the 169 block keys at
      -- parse.py:1947, and an unknown block key is silently ignored — only a
      -- logmessage, and only under debug (parse.py:1945-1948). A block-level
      -- `show if` therefore does nothing AND says nothing.
      for_ (yamlBlocks out) \b ->
        shouldNotContain' "a block" b "\nshow if:"

    it "keeps the constructor radio in its own, earlier question (B)" $ do
      -- HAZARD H1, probed: a `show if: {code: …}` reading a variable that a
      -- field in the SAME question defines is fatal —
      -- `DASourceError: Infinite loop: <var> already looked for`, on every
      -- choice. The radio must be a separate, earlier block.
      out <- daEmit bin daPayloadSource
      for_ (yamlBlocks out) \b ->
        when ("show if:" `isInfixOf` b && "the_outcome" `isInfixOf` b) $
          shouldNotContain' "the payload follow-up block" b "datatype: radio"

    ------------------------------------------------------------------------
    -- C. MAYBE NUMBER / MAYBE DATE via paired is-known questions
    ------------------------------------------------------------------------
    it "pairs each MAYBE NUMBER/DATE with an is-known question (C)" $ do
      out <- daEmit bin daMaybeSource

      -- One L4 field, two docassemble questions: the flag and the value.
      shouldContain' "the emitted interview" out "declared_income"
      shouldContain' "the emitted interview" out "date_last_worked"
      shouldContainAny "the emitted interview" out
        ["declared_income_known", "declared_income_is_known", "has_declared_income"]
      shouldContainAny "the emitted interview" out
        ["date_last_worked_known", "date_last_worked_is_known", "has_date_last_worked"]

      -- The value questions keep their own datatypes.
      shouldContain' "the emitted interview" out "datatype: number"
      shouldContain' "the emitted interview" out "datatype: date"

      -- And each MAYBE value field is guarded, server-side, by its flag.
      -- Without the guard a second consumer reading the value on the absence
      -- path makes docassemble ask the value question anyway, and a blank
      -- submission arrives as 0.0 — a fabricated answer, silently (probed).
      --
      -- Scoped to the two MAYBE fields on purpose. `the qualifying date` is a
      -- PLAIN `DATE` in the same record and must NOT be guarded; requiring a
      -- `show if:` on every date question would demand a defect.
      for_ ["declared_income", "date_last_worked"] \field ->
        case [ b | b <- yamlBlocks out
                 , field `isInfixOf` b
                 , "datatype: number" `isInfixOf` b || "datatype: date" `isInfixOf` b ] of
          [] -> expectationFailure $
            "no value question was emitted for the MAYBE field " ++ show field
          blocks -> for_ blocks \b -> do
            shouldContain' ("the " ++ field ++ " value question") b "show if:"
            shouldContain' ("the " ++ field ++ " value question") b "code:"
      -- and the plain DATE in the same record keeps its unguarded question
      case [ b | b <- yamlBlocks out, "the_qualifying_date" `isInfixOf` b
               , "datatype: date" `isInfixOf` b ] of
        [] -> expectationFailure "the plain DATE field lost its question"
        (b : _) -> shouldNotContain' "the plain DATE question" b "show if:"

    it "reads absence as absence, never as 0 or '' (C)" $ do
      -- What R8 was afraid of, asserted on the emitted code rather than on
      -- the widget: the goal must consult the is-known flag, not merely the
      -- value. `#EVAL` 2 (a real declared income of ZERO) and `#EVAL` 3 (no
      -- declaration at all) disagree in L4; any lowering that reads only the
      -- number cannot tell them apart.
      out <- daEmit bin daMaybeSource
      let goalBlocks = [ b | b <- yamlBlocks out, "the_claim_must_be_referred" `isInfixOf` b ]
      when (null goalBlocks) $
        expectationFailure "no code block sets the goal"
      shouldContainAny "the emitted rule code" (concat goalBlocks)
        ["_known", "_is_known", "has_declared_income"]

    it "lowers `WHEN JUST FALSE` as a payload-VALUE match, not a presence test (C)" $ do
      -- Scope ruling: a match on a MAYBE's payload value is IN M4, under R8.
      -- M1 refused it by name, and before that repair it compiled to
      -- `is None`, reporting TRUE for the unanswered case — which is the
      -- opposite answer. The emitted code must compare the VALUE.
      out <- daEmit bin daMaybeSource
      shouldContainAny "the disclaimer rule" out
        [ "declaration_confirmed is False"
        , "declaration_confirmed == False"
        , "declaration_confirmed) is False" ]

    it "still refuses MAYBE of an enum, and names the enum (C)" $ do
      -- The refusal survives M4 (see the fixture's own header for why). What
      -- must NOT survive is M1's wording: "v1: MAYBE BOOLEAN and MAYBE STRING
      -- only" becomes a false claim in user-facing prose the moment NUMBER
      -- and DATE land, which is precisely the drift CLAUDE.md warns about. So
      -- the diagnostic is required to name what it is refusing.
      Output code _ serr <-
        runL4 bin ["docassemble", "examples/docassemble/not-ok/maybe-enum.l4"]
      code `shouldBe` ExitFailure 1
      shouldContain' "the refusal" serr "MAYBE"
      shouldContain' "the refusal" serr "Severity"
      shouldNotContain' "the refusal" serr "MAYBE BOOLEAN and MAYBE STRING only"

    ------------------------------------------------------------------------
    -- D. date literals and calendar-exact date arithmetic
    ------------------------------------------------------------------------
    it "routes every date literal through as_datetime() (D)" $ do
      -- A `datatype: date` answer enters the interview as
      -- `as_datetime(<submitted string>)` (webapp interview/views.py:1372 at
      -- 1b6678384), i.e. a tz-aware DADateTime. A bare string literal
      -- compared against one raises TypeError — executed:
      -- `as_datetime('2016-05-16') >= '2015-01-01'` is a TypeError, not a
      -- comparison. The failure is loud; it is also certain.
      out <- daEmit bin daDateSource
      shouldContain' "the emitted interview" out "as_datetime("
      shouldContain' "the emitted interview" out "2015-04-01"
      case [ ln | ln <- lines out, "2015-04-01" `isInfixOf` ln ] of
        [] -> expectationFailure "the commencement literal is not emitted at all"
        lns -> for_ lns \ln ->
          shouldContain' "the line carrying the date literal" ln "as_datetime("

    it "computes statutory age calendar-exactly, never via date_difference (D)" $ do
      -- `date_difference(...).years` is
      -- `(delta.days + delta.seconds/86400.0) / 365.2425` — elapsed days over
      -- the MEAN GREGORIAN YEAR, as a float (dates.py:482 at 1b6678384). It
      -- reports 17.99900 on the applicant's own eighteenth birthday. Measured
      -- over every birth date from 1970-01-01 to 2006-12-31 it disagrees with
      -- the L4 oracle on 6,629 of 27,028 comparisons. It must not appear.
      out <- daEmit bin daDateSource
      shouldNotContain' "the emitted interview" out "date_difference"
      shouldNotContain' "the emitted interview" out "365.2425"
      -- and the calendar-exact idiom must be there instead
      shouldContainAny "the emitted interview" out
        [".minus(years=", ".plus(years=", "relativedelta(years="]

    ------------------------------------------------------------------------
    -- E. the `review:` block as a compliance checklist
    ------------------------------------------------------------------------
    it "emits a review block listing every input, answered or not (E)" $ do
      out <- daEmit bin daReviewSource
      shouldContain' "the emitted interview" out "review:"
      -- A review block is only reachable by firing its `event:`
      -- (current_info['action'] = '<event>'); without one the interview simply
      -- ends. Probed.
      case [ b | b <- yamlBlocks out, "review:" `isInfixOf` b ] of
        [] -> expectationFailure "no review block was emitted"
        [rv] -> do
          shouldContain' "the review block" rv "event:"
          -- every L4 input gets a row, including the three that this rule's
          -- short-circuit means are never asked
          for_ [ "the_return_was_filed", "the_return_was_on_time"
               , "the_fee_was_paid", "a_waiver_was_granted" ] $
            shouldContain' "the review block" rv
          -- The recipe that actually renders an unanswered row: a `note:`
          -- carrying showifdef(). A note row has no saveas to evaluate, so it
          -- renders whether or not the variable exists.
          shouldContain' "the review block" rv "note:"
          shouldContain' "the review block" rv "showifdef("
        other -> expectationFailure $
          "expected exactly one review block, found " ++ show (length other)

    it "does NOT reach for `skip undefined: False`, which force-asks (E)" $ do
      -- SPEC CORRECTION, measured. §10 called for a review block "with
      -- `skip undefined: False`". That flag does not make a passive
      -- checklist: it makes the review block FORCE-ASK every undefined
      -- variable it lists — with the flag the row's eval is no longer wrapped
      -- in try/except (parse.py:5876-5904 at 1b6678384), and the probe landed
      -- on the field screen for the unasked variable instead of on a review
      -- screen. The default (absent) is the opposite failure: an undefined row
      -- is silently dropped into a debug log line. Neither is a checklist.
      --
      -- The review block is required to EXIST here as well as to lack the
      -- flag, so this cannot pass vacuously on an interview that emits no
      -- review block at all.
      out <- daEmit bin daReviewSource
      shouldContain'    "the emitted interview" out "review:"
      shouldNotContain' "the emitted interview" out "skip undefined: False"

    ------------------------------------------------------------------------
    -- F. document assembly
    ------------------------------------------------------------------------
    it "assembles a letter from the verdict screen, under a `variable name:` (F)" $ do
      out <- daEmit bin daLetterSource
      shouldContain' "the emitted interview" out "attachment:"
      -- WITHOUT `variable name:` docassemble files the document under
      -- `_internal['docvar'][n]` (parse.py:4997-5003 at 1b6678384) and there
      -- is nothing to assert about afterwards. The hazard this defends
      -- against is not an exception — a raising body propagates and an
      -- unaskable reference propagates, both probed — it is a SUCCESSFUL
      -- EMPTY RENDER: interview completes, variable is a healthy
      -- DAFileCollection, letter is blank, nothing raises and nothing logs.
      shouldContain' "the emitted interview" out "variable name:"
      -- Headless assembly is DOCX- and HTML-capable in the harness venv
      -- (docx and docxtpl present) but there is no LibreOffice/soffice, so a
      -- PDF format would fail at assemble time — and per parse.py:9521-9526
      -- that failure inside a question block is swallowed into a log line.
      -- Scoped to the attachment block: `pdf` is a broad needle and a bare
      -- whole-file negative would be brittle rather than meaningful.
      case [ b | b <- yamlBlocks out, "attachment:" `isInfixOf` b ] of
        [] -> expectationFailure "no attachment block was emitted at all"
        blocks -> for_ blocks \b -> do
          shouldContain'    "the attachment block" b "valid formats:"
          shouldNotContain' "the attachment block" b "pdf"

      -- The verdict screen must actually reference the document, or it is
      -- never assembled. Asserted on an `event:` block specifically: the
      -- attachment block names the variable itself, so looking for the name
      -- anywhere in the file would be satisfied by the declaration alone.
      let verdictScreens = [ b | b <- yamlBlocks out, "event:" `isInfixOf` b ]
      when (null verdictScreens) $
        expectationFailure "no verdict screen (`event:` block) was emitted"
      shouldContainAny "the verdict screens" (concat verdictScreens)
        ["${ notice_letter }", "${notice_letter}", "notice_letter"]

    it "keeps attachment sub-keys out of the BLOCK-key vocabulary (F/R9.5)" $ do
      -- A third vocabulary. `variable name`, `filename`, `content`,
      -- `valid formats` and `content file` are ATTACHMENT sub-keys, read by
      -- process_attachment (parse.py:4914-5230 at 1b6678384); `name`,
      -- `filename`, `docx template file` and `valid formats` are NOT among
      -- the 169 block keys at parse.py:1947. Adding them to the emitter's
      -- block-key list would break `emitterVocabularyViolations == []`, so
      -- they need their own list with its own oracle — exactly the split M2
      -- already made between block keys and field modifiers.
      out <- daEmit bin daLetterSource
      let known = [ "name", "filename", "description", "variable name"
                  , "valid formats", "content", "content file", "raw"
                  , "docx template file", "pdf template file", "fields"
                  , "metadata", "editable", "skip undefined", "language"
                  , "redact", "template file", "rtf template file"
                  , "docx reference file", "update references", "usedefs"
                  , "initial yaml", "additional yaml", "checkbox export value"
                  , "decimal places" ]
          subKeys b = [ takeWhile (/= ':') (drop 2 ln)
                      | ln <- lines b, "  " `isPrefixOf` ln
                      , not ("   " `isPrefixOf` ln), ':' `elem` ln ]
      -- Required to EXIST as well as to be well-formed, so this cannot pass
      -- vacuously on an interview that emits no attachment at all.
      case [ b | b <- yamlBlocks out, "attachment:" `isInfixOf` b ] of
        [] -> expectationFailure "no attachment block was emitted at all"
        blocks -> for_ blocks \b ->
          for_ (subKeys b) \k ->
            unless (null k || k `elem` known) $
              expectationFailure $
                "the attachment block uses sub-key " ++ show k
                ++ ", which process_attachment does not read (parse.py:4914-5230 "
                ++ "at 1b6678384). It is not a block key either, so nothing will "
                ++ "warn: an unrecognised attachment sub-key is silently ignored."
                ++ "\n--- block ---\n" ++ b

    it "ships the letter template in the package under data/templates (F/R11)" $ do
      -- The `--package` tree already grafts `<inner>/data` in MANIFEST.in, so
      -- a template dropped under data/templates ships automatically. Note for
      -- the implementer: if the interview references it with `content file:`,
      -- the BARE artifact stops parsing, because content file resolves
      -- through package_template_filename and raises DASourceError when the
      -- file is not found (parse.py:5059-5064 at 1b6678384) — at parse time,
      -- before any question is asked.
      haveTemplate <- doesFileExist daLetterTemplate
      unless haveTemplate $
        expectationFailure (daLetterTemplate ++ " is missing from the corpus")
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-letter"
      files <- expectPackage bin daLetterSource dir
      case [ f | f <- files, ("data" </> "templates") `isInfixOf` f ] of
        [] -> expectationFailure $
          "the --package tree ships no data/templates entry; files were "
          ++ show files
        _  -> pure ()
      removePathForcibly dir

    ------------------------------------------------------------------------
    -- G. regression: the boundary of what M4 owns
    --
    -- GREEN today, and it must stay green. This block pre-authorises nothing:
    -- the seven M1/M2 byte goldens are pinned where they already were
    -- (stdout, and again through `-o` with its fidelity sidecar), and the four
    -- refusals below are the ones M4 does not own.
    ------------------------------------------------------------------------
    ------------------------------------------------------------------------
    -- H. added by the GREEN phase, which the RED phase asked for by name
    ------------------------------------------------------------------------
    it "declares the attachment sub-keys it writes, as a THIRD vocabulary (F/R9.5)" $ do
      -- The RED phase could only hard-code the oracle inside its own test,
      -- because `emitterAttachmentKeys` did not exist and adding it would have
      -- been a compile error rather than a red assertion. It exists now, so the
      -- emitter's declaration of what it writes inside an `attachment:` is
      -- checked in both directions: every declared key is one
      -- `process_attachment` reads (parse.py:4914-5230 at 1b6678384), and every
      -- key the emitter actually emits is declared.
      let readByProcessAttachment =
            [ "name", "filename", "description", "variable name"
            , "valid formats", "content", "content file", "raw"
            , "docx template file", "pdf template file", "fields"
            , "metadata", "editable", "skip undefined", "language"
            , "redact", "template file", "rtf template file"
            , "docx reference file", "update references", "usedefs"
            , "initial yaml", "additional yaml", "checkbox export value"
            , "decimal places" ]
          declared = map T.unpack DAEmit.emitterAttachmentKeys
      [k | k <- declared, k `notElem` readByProcessAttachment] `shouldBe` []
      -- and it is NOT folded into the block-key/field-modifier split, because
      -- an attachment sub-key is neither.
      [ k | k <- declared
          , k `elem` map T.unpack DAEmit.emitterKeyVocabulary ] `shouldBe` []

      out <- daEmit bin daLetterSource
      let subKeys b = [ takeWhile (/= ':') (drop 2 ln)
                      | ln <- lines b, "  " `isPrefixOf` ln
                      , not ("   " `isPrefixOf` ln), ':' `elem` ln ]
      case [ b | b <- yamlBlocks out, "attachment:" `isInfixOf` b ] of
        [] -> expectationFailure "no attachment block was emitted at all"
        blocks -> for_ blocks \b ->
          [ k | k <- subKeys b, not (null k), k `notElem` declared ] `shouldBe` []

    it "unlocks the REAL corpus file that motivated `LIST OF` (A)" $ do
      -- The RED phase listed this as untested and said why it matters: "a green
      -- M4 could pass every test I wrote and still leave both files locked
      -- out", because ONE `LIST OF` field anywhere in a reachable record used
      -- to refuse the whole module. `charity-test.l4` is a 700-line Jersey
      -- charities encoding whose `Entity.purposes` is a `LIST OF Purpose`, and
      -- it is not a fixture written for this backend — which is the point.
      --
      -- It also pins the ETA-REDUCED predicate: the corpus writes
      -- `any \`the purpose is a charitable purpose\` (entity's purposes)`, a
      -- one-parameter decision passed by name rather than a lambda written out
      -- at the call site. No example under examples/docassemble/ does that.
      out <- daEmit bin "examples/legal/charities-cleanroom/charity-test.l4"
      shouldContain' "the charities interview" out "DAList"
      shouldContain' "the charities interview" out "object_type"
      shouldContain' "the charities interview" out "for _purpose in entity.purposes"
      -- Nested quantifiers must not share a generator variable: Python scopes
      -- one to its own comprehension, so an inner binder that sanitised onto an
      -- outer one would make the outer's element unreachable from the inner
      -- body. This file nests `any` inside `all` over the same list.
      shouldContain' "the charities interview" out "for _purpose_2 in entity.purposes"

    it "compiles each M4 example to its golden interview" $
      for_ [ daListSource, daPayloadSource, daMaybeSource, daDateSource
           , daReviewSource, daLetterSource ] \src -> do
        let stem = takeWhile (/= '.') (drop (length daExampleDir + 1) src)
        expectGolden bin ["docassemble", src]
          (daExampleDir </> "expected" </> (stem ++ ".yml"))

    it "leaves the four refusals M4 does not own refusing, by their own names (G)" $
      for_ daStillRefused \(fixture, diagnostic) -> do
        Output code _ serr <-
          runL4 bin ["docassemble", "examples/docassemble/not-ok" </> fixture]
        unless (code == ExitFailure 1) $
          expectationFailure $
            fixture ++ " no longer refuses (exit " ++ show code
            ++ "); M4 does not own this refusal"
        shouldContain' (fixture ++ " refusal") serr diagnostic

    ------------------------------------------------------------------------
    -- I. the repair pass (2026-08-17). Five adversarial lenses attacked M4
    -- and an independent skeptic tried to refute each finding; these pin the
    -- five that survived AND changed behaviour. Each one names the measured
    -- failure, not just the shape it wants.
    ------------------------------------------------------------------------
    it "splices the letter template under an explicit indentation indicator (I/F)" $ do
      -- A YAML block scalar with no indentation indicator takes its
      -- indentation from its own FIRST non-empty line. The emitter indents
      -- every template line by a flat four spaces, so a template opening on any
      -- leading whitespace — ONE space is enough, and so is a whitespace-only
      -- first line — set the block indent above four, and the first following
      -- line at exactly four TERMINATED the scalar. The parser then met
      -- template prose where an `attachment:` sub-key must be. Measured against
      -- real docassemble 1.10.7: `parse.Interview` raises `DASourceError` from
      -- parse.py:8352-8360, so the whole interview is unloadable — every
      -- question, in BOTH artifact shapes — while `l4 docassemble` exits 0.
      --
      -- `|2`, not `|4`: the indicator is an offset from the PARENT node's
      -- indentation and the `attachment:` mapping sits at two.
      --
      -- `notice-letter.letter.md` opens on an indented address block precisely
      -- so the shipped corpus carries the trigger; strip the `2` from the
      -- emitted YAML and the harness cannot even load the interview.
      out <- daEmit bin daLetterSource
      case [ b | b <- yamlBlocks out, "attachment:" `isInfixOf` b ] of
        [] -> expectationFailure "no attachment block was emitted at all"
        blocks -> for_ blocks \b -> do
          shouldContain'    "the attachment block" b "content: |2"
          shouldNotContain' "the attachment block" b "content: |\n"
      -- and the template really does open indented, or the assertion above is
      -- pinning a shape nothing exercises.
      tpl <- readUtf8 daLetterTemplate
      case dropWhile null (lines tpl) of
        (firstLine : _) | " " `isPrefixOf` firstLine -> pure ()
        other -> expectationFailure $
          daLetterTemplate ++ " no longer opens on an indented line, so the "
          ++ "block-scalar indicator above is no longer exercised by anything: "
          ++ show (take 1 other)

    it "re-assembles the letter when an earlier answer changes (I/F, §8.4)" $ do
      -- §8.4's repair put `reconsider: True` on the derived CODE blocks and
      -- stopped there. An attachment is derived too, and docassemble assembles
      -- one only when the variable it names is SOUGHT (parse.py:9513-9530 at
      -- 1b6678384) — a variable that is already defined is never sought. So the
      -- letter was computed once and outlived every later answer: measured on
      -- this example, changing the notice period from three months to one left
      -- the verdict screen reading `..._screen_fails` above a letter still
      -- saying "Notice period served: 3 month(s)" and "the notice is valid".
      -- A non-flipping edit was stale the same way.
      out <- daEmit bin daLetterSource
      case [ b | b <- yamlBlocks out, "attachment:" `isInfixOf` b ] of
        [] -> expectationFailure "no attachment block was emitted at all"
        blocks -> for_ blocks \b ->
          shouldContain' "the attachment block" b "reconsider: True"

    it "clears a gated answer when the answer that gates it is re-asked (I/B/C, §8.4)" $ do
      -- `show if:` decides whether a gated question is ASKED. It does not
      -- decide whether an answer already given SURVIVES its gate being
      -- withdrawn, and `reconsider:` deletes derived variables only — so after
      -- a review-block Edit the compliance checklist reported, on one screen,
      -- "the outcome: refused" beside "the number of conditions: 9", and
      -- `refused` carries no `the number of conditions` in L4 at all. The
      -- paired MAYBE had the same shape: "is there an answer?: False" beside
      -- "declared income: 2500". `undefine:` fires in `ask` (parse.py:5389) and
      -- is a documented no-op on a variable that is not defined, so it costs
      -- nothing forward and clears exactly the stale answers on a re-ask.
      payload <- daEmit bin daPayloadSource
      case [ b | b <- yamlBlocks payload, "q_d.the_outcome" `isInfixOf` b ] of
        [] -> expectationFailure "no question block for the enum discriminator"
        blocks -> for_ blocks \b -> do
          shouldContain' "the discriminator question" b "undefine:"
          shouldContain' "the discriminator question" b "d.the_number_of_conditions"
          shouldContain' "the discriminator question" b "d.the_stated_ground_of_refusal"
      -- and the payload follow-ups must NOT undefine anything: they gate
      -- nothing, and clearing on every ask would erase the answer being given.
      case [ b | b <- yamlBlocks payload
               , "q_d.the_number_of_conditions" `isInfixOf` b ] of
        [] -> expectationFailure "no question block for the payload follow-up"
        blocks -> for_ blocks \b ->
          shouldNotContain' "the payload follow-up question" b "undefine:"

      maybes <- daEmit bin daMaybeSource
      case [ b | b <- yamlBlocks maybes
               , "q_c.declared_income_known" `isInfixOf` b ] of
        [] -> expectationFailure "no question block for the is-known flag"
        blocks -> for_ blocks \b -> do
          shouldContain' "the is-known question" b "undefine:"
          shouldContain' "the is-known question" b "c.declared_income"

    it "reserves the interview's builtin and util namespaces too (I/R11)" $ do
      -- M2 closed ONE THIRD of this hazard — the `l4runtime` star-import — and
      -- left the two larger thirds open. A goal variable whose name already
      -- resolves is never sought, because docassemble backchains only on
      -- NameError; it resolves to a function object, which is truthy, so the
      -- driver takes the "holds" branch, NO QUESTION IS ASKED, and the fidelity
      -- report says `(nothing lost)`. Measured against real 1.10.7 on an
      -- `@export` named `All`: `screen='All: Holds'`, `questions asked=[]`,
      -- against an L4 `#EVAL` of FALSE. `Today` is worse — it is in the
      -- user_dict for real, via `from docassemble.base.util import *`
      -- (parse.py:131, exec'd at :8523-8524), which the emitter deliberately
      -- does not suppress.
      Output code sout serr <- runL4 bin ["docassemble", daGlobalShadowSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)
      shouldContain' "the emitted interview" sout "all_ = f.the_box_was_ticked"
      shouldContain' "the emitted interview" sout "today_ = f.the_box_was_ticked"
      let bare = [ ln | ln <- lines sout
                 , any (`isInfixOf` (ln ++ " "))
                       ["all = f.", "today = f.", "if all:", "if today:"] ]
      unless (null bare) $
        expectationFailure $
          "an interview variable is spelled exactly like a name already bound "
          ++ "in the interview's top-level namespace: " ++ show bare

    it "declares, rather than mis-emits, the gather it cannot clear (I/§8.4)" $ do
      -- `ask` runs `substitute_vars` over `reconsider:` and NOT over `undefine:`
      -- (parse.py:5389 beside :5392 at 1b6678384), so an element question's
      -- `<list>[i].<attr>` spelling would reach `undefine()` with the iterator
      -- unresolved. The emitter therefore emits none there — and says so, which
      -- is the difference between a bounded repair and a silent one.
      Output code sout serr <- runL4 bin ["docassemble", daGatheredMaybeSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)
      -- the guard IS emitted on the element's value question …
      shouldContain'    "the emitted interview" sout
        "h.claimants[i].declared_income_known"
      -- … and no `undefine:` reaches it.
      shouldNotContain' "the emitted interview" sout "undefine:"
      -- The omission is declared, per module, naming the gated variable.
      tmp <- getTemporaryDirectory
      let ymlPath = tmp </> "l4-da-gathered-maybe.yml"
          repPath = tmp </> "l4-da-gathered-maybe.fidelity.txt"
      Output code2 _ serr2 <-
        runL4 bin ["docassemble", daGatheredMaybeSource, "-o", ymlPath]
      unless (code2 == ExitSuccess) $
        expectationFailure ("emit -o failed\n--- stderr ---\n" ++ serr2)
      report <- readUtf8 repPath
      shouldContain' "the fidelity report" report "DA-UNDEFINE-LIST"
      shouldContain' "the fidelity report" report "h.claimants[i].declared_income"
      removePathForcibly ymlPath
      removePathForcibly repPath

    it "refuses M4's own two new collisions, by their own names (I)" $
      for_ daM4Refused \(fixture, diagnostic) -> do
        Output code _ serr <-
          runL4 bin ["docassemble", "examples/docassemble/not-ok" </> fixture]
        unless (code == ExitFailure 1) $
          expectationFailure $
            fixture ++ " no longer refuses (exit " ++ show code ++ ")"
        shouldContain' (fixture ++ " refusal") serr diagnostic
        -- Not the internal-error message: a user-authored condition must be
        -- reported in L4 terms, naming what to rename.
        shouldNotContain' (fixture ++ " refusal") serr "internal id collision"
  -- `l4 catala` (specs/todo/CATALA-EXPORT-SPEC.md). Each golden below has been
  -- run through the real toolchain — `catala typecheck` and `clerk test`
  -- against catala 1.2.1 — so the goldens are not merely "what the emitter
  -- currently prints"; see examples/catala/README.md.
  describe "l4 catala" $ do
    it "compiles the spec's Appendix A example to its golden Catala module" $
      expectGolden bin ["catala", "examples/catala/benefit.l4"]
                       "examples/catala/expected/benefit.catala_en"

    it "compiles a nested-guard rate table (the ladder-direction exhibit)" $
      expectGolden bin ["catala", "examples/catala/bands.l4"]
                       "examples/catala/expected/bands.catala_en"

    it "compiles the literate weave: § headings, inert law text, @ref, enums" $
      expectGolden bin ["catala", "examples/catala/statute.l4"]
                       "examples/catala/expected/statute.catala_en"

    -- The two OpenFisca seed-corpus ports named in the spec's P1 exit
    -- criterion (§10). Both compile unchanged from their OpenFisca originals;
    -- what makes them Catala-clean is R11's elision of the `period` plumbing
    -- string (and, in household, of `Person.name`).
    it "compiles the flat-tax port, eliding the OpenFisca period string (R11)" $
      expectGolden bin ["catala", "examples/catala/flat-tax.l4"]
                       "examples/catala/expected/flat-tax.catala_en"

    it "compiles the household port: group entity, LIST OF, absorbed sum (R5)" $
      expectGolden bin ["catala", "examples/catala/household.l4"]
                       "examples/catala/expected/household.catala_en"

    it "compiles CONSIDER-on-enum plus TYPICALLY → context (R10)" $
      expectGolden bin ["catala", "examples/catala/tariff.l4"]
                       "examples/catala/expected/tariff.catala_en"

    -- The coverage exhibit. An adversarial review found the other six goldens
    -- between them exercised two of the emitter's expression forms, so a
    -- regression in `match`, dates, `optional of`, `combine all`, `number of`,
    -- `contains`, `impossible`, a private toplevel or the R3 date helper would
    -- have been caught by nothing in the tree.
    it "compiles the coverage exhibit: dates, MAYBE, folds, a private toplevel" $
      expectGolden bin ["catala", "examples/catala/registry.l4"]
                       "examples/catala/expected/registry.catala_en"

    -- R11's disclosure obligation is the point of these two, not the text: a
    -- narrower emitted record than its L4 source is a shape divergence a
    -- reader must be told about, so it goes in the notes block, not just on
    -- stderr.
    it "discloses every R11 elision in the emitted document's notes block" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/household.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("field `name` of `Person` is a STRING" `isInfixOf`)
      sout `shouldSatisfy` ("parameter `period` of `household income` is a STRING" `isInfixOf`)

    -- R10's cost, disclosed: the emitted scope is MORE PERMISSIVE than its
    -- source, because Catala lets a caller omit a `context` variable and L4
    -- does not let a caller omit anything.
    it "emits TYPICALLY as `context` + an in-scope default, and says so" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/tariff.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("context cap content decimal" `isInfixOf`)
      sout `shouldSatisfy` ("A Catala caller may omit it; an L4 caller may not." `isInfixOf`)
      sout `shouldSatisfy`
        ("match a.class with pattern -- Domestic : 0.2" `isInfixOf`)

    -- L4 has no way to omit an argument, so every ordinary test scope supplies
    -- the cap and the emitted `definition cap equals 500.0` is dead: change it
    -- and nothing fails. The twin scope omits it, over a directive whose cap
    -- actually binds, which is what makes the default observable.
    it "pins the R10 default with a twin test scope that omits the argument" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/tariff.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("#[test] declaration scope Test3Default:" `isInfixOf`)
      sout `shouldSatisfy`
        ("(output of TariffPayable with { -- a: Account { -- class: Industrial \
         \-- units_used: 2000.0 } }).tariff_payable" `isInfixOf`)

    -- R2 (§8.2) promised a lowering note at each coercion; R7 (§8.7) promised a
    -- human-legible companion to the exact-rational JSON block.
    it "emits R2's per-coercion note and R7's human-format companion line" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/registry.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("# R2 coercion: `decimal of` was inserted" `isInfixOf`)
      sout `shouldSatisfy` ("is ROUNDED here rather than refused" `isInfixOf`)
      sout `shouldSatisfy` ("{\"result\":\"2025-03-01\"}" `isInfixOf`)
      sout `shouldSatisfy` ("L4 computes that as: `DATE OF 1, 3, 2025`." `isInfixOf`)

    -- §6.1: L4's connectives short-circuit and Catala's `and`/`or` do not, so
    -- the emitter writes the conditional form. `benefit.l4`'s disjunction is
    -- the one the spec's Appendix A example turns on.
    it "emits AND/OR as short-circuiting conditionals, never Catala `and`/`or`" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/benefit.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy`
        ("(if (a.age >= 65.0) then true else a.is_veteran)" `isInfixOf`)
      sout `shouldNotSatisfy` (" or " `isInfixOf`)

    -- R4: the exception ladder is the PRIMARY emission, and it never ships
    -- without the apparatus that re-checks it.
    it "emits Mode B ladders together with their equivalence grid" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/bands.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("label rate_band_r1 exception rate_band_r2" `isInfixOf`)
      sout `shouldSatisfy` ("#[test] declaration scope RateBandEqvGrid:" `isInfixOf`)
      sout `shouldSatisfy` ("{\"all_agree\":true}" `isInfixOf`)

    -- R7: the expected values come from L4's evaluator, not from
    -- `clerk test --reset`. 0.25 is L4's answer for a 60000 income, and Catala
    -- prints exact rationals in JSON, so it has to appear as 1/4.
    it "fills test blocks with values L4 computed, as exact rationals" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/bands.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("$ catala test-scope Test1 --disable-warnings -F json" `isInfixOf`)
      sout `shouldSatisfy` ("{\"result\":\"1/4\"}" `isInfixOf`)
      sout `shouldSatisfy` ("{\"result\":\"2/5\"}" `isInfixOf`)

    it "--boolean-only drops the ladders and the grids that check them" $ do
      Output code sout _ <- runL4 bin ["catala", "--boolean-only", "examples/catala/bands.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldNotSatisfy` ("EqvGrid" `isInfixOf`)
      sout `shouldNotSatisfy` ("label rate_band_r1" `isInfixOf`)
      sout `shouldSatisfy` ("--boolean-only" `isInfixOf`)

    -- R4's escape flag had one test of three substring checks and no golden, so
    -- nothing re-ran its output through the toolchain. It has one now, and
    -- etc/validate-catala.mjs walks `expected/`, so the flag's output is under
    -- `catala typecheck`, `catala proof` and `clerk test` like everything else.
    it "pins the --boolean-only rendering as a golden the R9 harness checks" $
      expectGolden bin ["catala", "--boolean-only", "examples/catala/bands.l4"]
                       "examples/catala/expected/bands-boolean-only.catala_en"

    -- Catala wants the module name to be the file's basename with its first
    -- letter capitalised, so a basename it cannot spell is rejected here rather
    -- than by the toolchain after the file has been written.
    it "rejects an -o basename that cannot be a Catala module name" $ do
      Output code _ serr <- runL4 bin
        ["catala", "examples/catala/flat-tax.l4", "-o", "ft-out.catala_en"]
      code `shouldNotBe` ExitSuccess
      serr `shouldSatisfy` ("cannot be a Catala module name" `isInfixOf`)

    -- Two field names that mangle to one Catala identifier would silently
    -- conflate in Catala's flat per-structure namespace; the OpenFisca fixture
    -- has the same shape and serves both backends.
    it "rejects a name collision (distinct L4 names → same Catala identifier)" $
      expectFail bin ["catala", "examples/openfisca/not-ok/name-collision.l4"]

    -- Five shapes that used to compile to Catala saying something other than
    -- what the L4 says. Each fixture's header names the divergence; the point
    -- of the group is that `l4 catala` refuses rather than emitting quietly.
    for_ [ "otherwise-not-last"
         , "otherwise-not-last-enum"
         , "local-name-shadow"
         , "elided-string-compared"
         , "enum-constructor-collision"
         ] $ \name ->
      it ("rejects " ++ name ++ " rather than changing its denotation") $
        expectFail bin ["catala", "examples/catala/not-ok/" ++ name ++ ".l4"]

    it "fails on a file that does not typecheck" $
      expectFail bin ["catala", errorFixture]
  where
    for_ xs f = mapM_ f xs
