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
import Data.List (isInfixOf, isPrefixOf, nub, sort)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy.Char8 as BSL8
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Aeson (Value(..), eitherDecode)
import Data.Foldable (toList)
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
import System.Exit (ExitCode(..), exitFailure)
import System.FilePath ((</>), isAbsolute, normalise)
import Test.Hspec

import CliTest.Common
import qualified CliTest.Blawx as Blawx
import qualified CliTest.Catala as Catala
import qualified CliTest.DmnBpmn as DmnBpmn
import qualified CliTest.Docassemble as Docassemble
import qualified CliTest.OpenFisca as OpenFisca
import qualified CliTest.Yscript as Yscript

----------------------------------------------------------------------------
-- Fixtures
----------------------------------------------------------------------------

bilingualFixture :: FilePath
bilingualFixture = fixtureDir </> "bilingual.l4"

-- | Eight shapes whose @l4 state-graph@ caption said something false in
-- September 2026, each cut down to the four or five lines that draw it.
--
-- It is a CLI fixture and not a corpus example because NO golden captures
-- state-graph DOT output — measured 2026-09-22,
-- @grep -rl digraph jl4\/examples --include=*.golden@ is empty — so a corpus
-- file would pin the type checker on these rules and nothing about the
-- drawing. @tests-cli\/fixtures@ is also in no goldened glob
-- (@jl4\/tests\/Main.hs@\'s list, kept in step by
-- @etc\/check-corpus-goldens.mjs@), so it ships no @tests\/@ directory.
captionFixture :: FilePath
captionFixture = fixtureDir </> "state-graph-captions.l4"

-- | Typechecks cleanly, then THROWS when its @#EVAL@ is evaluated.
evalCrashFixture :: FilePath
evalCrashFixture = fixtureDir </> "eval-crash.l4"

-- | A @#TRACE@ whose act lands before its @AFTER@ window opens: a nullity the
-- run REPORTS (EVERY-EACH-QUANTIFIER-SPEC §5.1.2, R-X6) beside a live residual.
earlyActFixture :: FilePath
earlyActFixture = fixtureDir </> "early-act.l4"

-- | Typechecks cleanly; every @#ASSERT@ in it RAISES instead of deciding.
assertRaisesFixture :: FilePath
assertRaisesFixture = fixtureDir </> "assert-raises.l4"

-- | REFUSE: a determinate non-answer. @l4 run@ exits 0 on it, and @--json@
-- gives it its own kind rather than folding it into a value or an error.
refuseRunFixture :: FilePath
refuseRunFixture = fixtureDir </> "refuse-run.l4"

-- | An @export whose helper refuses for one row and answers for the next.
refuseBatchFixture, refuseBatchJson :: FilePath
refuseBatchFixture = fixtureDir </> "refuse-batch.l4"
refuseBatchJson    = fixtureDir </> "refuse-batch.json"

-- | Typechecks cleanly; both @#ASSERT@s are on a bare assumed BOOLEAN — one
-- polarity raises, the other reduces to the symbolic term without raising.
assertAssumedFixture :: FilePath
assertAssumedFixture = fixtureDir </> "assert-assumed.l4"

breachTraceFixture, breachInputsFixture :: FilePath
breachTraceFixture  = fixtureDir </> "breach-trace.l4"
breachInputsFixture = fixtureDir </> "breach-inputs.json"

batchEligFixture, batchDataJson, batchDataCsv, batchMixedJson :: FilePath
batchEligFixture = fixtureDir </> "batch-elig.l4"
batchDataJson    = fixtureDir </> "batch-data.json"
batchDataCsv     = fixtureDir </> "batch-data.csv"
batchMixedJson   = fixtureDir </> "batch-mixed.json"

batchMixfixSharedHead, batchMixfixSharedHeadJson :: FilePath
batchMixfixSharedHead     = fixtureDir </> "batch-mixfix-shared-head.l4"
batchMixfixSharedHeadJson = fixtureDir </> "batch-mixfix-shared-head.json"

batchCodeFixture, batchExponentCsv, batchMaybeFixture, batchMaybeBadJson :: FilePath
batchCodeFixture  = fixtureDir </> "batch-code.l4"
batchExponentCsv  = fixtureDir </> "batch-exponent.csv"
batchMaybeFixture = fixtureDir </> "batch-maybe.l4"
batchMaybeBadJson = fixtureDir </> "batch-maybe-bad.json"

-- | An @export reading a module-level ASSUME: directly, or only through a
-- helper it calls. The rows either supply the ASSUME (@x@) or omit it.
batchAssumeDirectFixture, batchAssumeHelperFixture, batchAssumeFullJson, batchAssumeMissingJson :: FilePath
batchAssumeDirectFixture = fixtureDir </> "batch-assume-direct.l4"
batchAssumeHelperFixture = fixtureDir </> "batch-assume-helper.l4"
batchAssumeFullJson      = fixtureDir </> "batch-assume-full.json"
batchAssumeMissingJson   = fixtureDir </> "batch-assume-missing.json"

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

-- The fixture for the "@desc attachment to WHERE/LET bindings" describe.
descAttachmentFixture :: FilePath
descAttachmentFixture    = fixtureDir </> "desc-attachment.l4"

-- | How many (possibly overlapping) times a needle occurs in a haystack.
countInfix :: String -> String -> Int
countInfix needle = go
 where
  go [] = 0
  go s@(_ : rest) = (if needle `isPrefixOf` s then 1 else 0) + go rest

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

-- Referential transparency (specs/todo/WHERE-INLINING-SPEC.md): a zero-arity
-- WHERE/LET binding is inlined before analysis, so a rule means the same thing
-- however its limbs are named. The recursive file is the termination control.
verifyWhereTransparencyFixture, verifyWhereRecursiveFixture :: FilePath
verifyWhereTransparencyFixture = fixtureDir </> "verify-where-transparency.l4"
verifyWhereRecursiveFixture    = fixtureDir </> "verify-where-recursive.l4"

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

-- The eleven-plus-two placement rows for an @nlg on a rule's head. Its
-- `.nlg.golden` pins the `l4 nlg` columns; `l4 render` has no golden anywhere in
-- the tree, so the tests below are the only thing pinning that the two
-- projections agree (smucclaw/l4-ide#972).
nlgHeadPlacementSource :: FilePath
nlgHeadPlacementSource = "examples/ok/nlg-head-placement.l4"

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
  for_ (concat
         [ coreFixtures
         , DmnBpmn.fixtures
         , OpenFisca.fixtures
         , Yscript.fixtures
         , Blawx.fixtures
         , Docassemble.fixtures
         , Catala.fixtures
         ]) \fp -> do
    ok <- doesFileExist fp
    unless ok $ do
      putStrLn ("Missing fixture: " ++ fp)
      putStrLn "Run this suite from the repository root (jl4/ is the working directory)."
      exitFailure
  hspec (spec bin)
  where
    for_ xs f = mapM_ f xs

-- | The files the core tests need. Each backend module exports its own
-- 'fixtures' list, and 'main' checks all of them before hspec runs anything.
coreFixtures :: [FilePath]
coreFixtures =
  [ cleanFixture, evalFixture, errorFixture, garbageFixture
  , evalCrashFixture
  , breachTraceFixture, breachInputsFixture
  , batchEligFixture, batchDataJson, batchDataCsv, batchMixedJson
  , batchCodeFixture, batchExponentCsv, batchMaybeFixture, batchMaybeBadJson
  , batchEscapeFixture, batchEscapeInput, evalTraceFixture
  , cycle3Entry, cycle2Entry, selfImportEntry, cleanImportEntry
  , embeddedDiamondEntry, shadowEmbeddedEntry, shadowSiblingEntry
  , shadowExtraEntry, shadowImporterEntry
  , verifyCleanFixture, verifyUnsatFixture, verifyDeadBranchFixture
  , verifyVacuousGuardFixture, verifySeamFixture, verifyNestedFixture
  , verifyWhereTransparencyFixture, verifyWhereRecursiveFixture
  , nlgRegcfSource, nlgRegcfGolden, nlgWizardSource, nlgWizardGolden
  , nlgHeadPlacementSource
  , assertRaisesFixture, assertAssumedFixture
  ]

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

    -- The R-X6 note must reach the machine-readable surface too: a consumer
    -- reading only "value" would be handed the silent nullity the ruling
    -- forbids (adversarial pass of 2026-09-16, G1/R1-2 — the first envelope
    -- dropped it). The key is present only on a directive that raised one.
    it "carries the run's notes in JSON, only where there are any" $ do
      env <- jsonEnvelope bin ["run", earlyActFixture, "--json"]
      case objField env "results" of
        Just (Array v) -> do
          length v `shouldBe` 2
          let notesOf r = case r of
                Object o -> KeyMap.lookup (Key.fromString "notes") o
                _        -> Nothing
          case notesOf (toList v !! 0) of
            Just (Array ns) -> do
              length ns `shouldBe` 1
              case toList ns of
                [String n] -> T.unpack n `shouldSatisfy` ("before the window opened at 3" `isInfixOf`)
                other      -> expectationFailure ("Expected one note string, got " ++ show other)
            other -> expectationFailure ("Expected a notes array on the early act, got " ++ show other)
          notesOf (toList v !! 1) `shouldBe` Nothing
        other -> expectationFailure ("Expected results array, got " ++ show other)

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

    -- An #ASSERT whose expression RAISES is a distinct outcome from one that
    -- evaluates to FALSE. Before this was pinned, `#ASSERT P` and
    -- `#ASSERT NOT P` both reported "assertion failed" whenever P raised
    -- (division by zero, an assumed term, …), so a test suite could not tell
    -- a wrong answer from an error.
    it "reports an #ASSERT that raises as unevaluable, with the reason, never as failed" $ do
      Output _ sout _ <- runL4 bin ["run", assertRaisesFixture]
      sout `shouldSatisfy` ("assertion could not be evaluated" `isInfixOf`)
      sout `shouldSatisfy` ("Division by zero" `isInfixOf`)
      sout `shouldSatisfy` ("assumed term" `isInfixOf`)
      sout `shouldNotSatisfy` ("assertion failed" `isInfixOf`)

    -- It did not evaluate cleanly, so it is the crash the 2026-08-01 ruling
    -- covers — unlike a clean FALSE, which stays exit 0.
    it "fails the run when an #ASSERT raises" $
      expectFail bin ["run", assertRaisesFixture]

    it "keeps kind \"assertion\", a null value and the reason in JSON when an #ASSERT raises" $ do
      env <- jsonEnvelope bin ["run", assertRaisesFixture, "--json"]
      objField env "ok" `shouldBe` Just (Bool False)
      case objField env "results" of
        Just (Array v) -> do
          length v `shouldBe` 2
          mapM_ (\r -> do
                   objField r "kind"  `shouldBe` Just (String "assertion")
                   objField r "value" `shouldBe` Just Null
                   case objField r "error" of
                     Just (String s) -> s `shouldSatisfy` ("assertion could not be evaluated" `T.isInfixOf`)
                     other -> expectationFailure ("Expected an error string, got " ++ show other))
                (toList v)
        other -> expectationFailure ("Expected results array, got " ++ show other)

    it "still typechecks the raising fixture — l4 check succeeds on it" $
      expectOk bin ["check", assertRaisesFixture] "Check succeeded."

    -- REFUSE (R7). A refusal is neither a value, nor an evaluation error, nor
    -- an unknown fact: it is the model declining to answer, with a reason. The
    -- three tests below pin the three ways that distinction could be lost.

    -- (1) A refusal must not be treated as a crash. `l4 run` exits 0.
    it "exits 0 when a directive REFUSES — a refusal is an answer, not a crash" $
      expectOk bin ["run", refuseRunFixture] "The model refuses to answer"

    -- (2) --json gives a refusing #EVAL its own kind, and a refused #ASSERT its
    -- reason under "refused" rather than "error". A consumer that reads every
    -- non-boolean assertion out of "error" would otherwise report a designed
    -- outcome as a defect.
    it "emits kind \"refused\" for a refusing #EVAL and a refused field for a refused #ASSERT" $ do
      env <- jsonEnvelope bin ["run", refuseRunFixture, "--json"]
      objField env "ok" `shouldBe` Just (Bool True)
      case objField env "results" of
        Just (Array v) -> case toList v of
          [ev, assertRefused, assertPlain] -> do
            objField ev "kind"   `shouldBe` Just (String "refused")
            objField ev "value"  `shouldBe` Just Null
            objField ev "reason" `shouldBe` Just (String "this case is not modelled")
            -- #ASSERT REFUSED holds: it is an ordinary satisfied assertion.
            objField assertRefused "kind"  `shouldBe` Just (String "assertion")
            objField assertRefused "value" `shouldBe` Just (Bool True)
            -- A PLAIN #ASSERT whose expression refuses is neither true nor
            -- false, and its reason is NOT under "error".
            objField assertPlain "kind"  `shouldBe` Just (String "assertion")
            objField assertPlain "value" `shouldBe` Just Null
            objField assertPlain "error" `shouldBe` Nothing
            case objField assertPlain "refused" of
              Just r  -> objField r "reason" `shouldBe` Just (String "this case is not modelled")
              other   -> expectationFailure ("Expected a refused object, got " ++ show other)
          other -> expectationFailure ("Expected 3 results, got " ++ show (length other))
        other -> expectationFailure ("Expected results array, got " ++ show other)

    -- (3) A refused BATCH row is a third terminal status, and it does NOT stop
    -- the batch: the row after it is still processed. Folding it into "error"
    -- would both mislabel it and truncate the run.
    it "gives a refusing batch row status \"refused\" and does not stop the batch" $ do
      Output code sout _ <-
        runL4 bin ["batch", refuseBatchFixture, "--inputs", refuseBatchJson]
      code `shouldBe` ExitSuccess
      nonBlankLines sout `shouldBe` 2
      sout `shouldSatisfy` ("\"status\":\"refused\"" `isInfixOf`)
      sout `shouldSatisfy` ("\"status\":\"success\"" `isInfixOf`)
      sout `shouldSatisfy` ("this schedule is not encoded for years before 2000" `isInfixOf`)

    -- A bare assumed BOOLEAN is neither TRUE nor FALSE. `#ASSERT NOT b`
    -- forces b and raises; `#ASSERT b` reduces to the symbolic b WITHOUT
    -- raising, and used to fall through to "assertion failed" — so the two
    -- polarities disagreed about the same undecidable term.
    it "reports both polarities of an #ASSERT on a bare assumed BOOLEAN as undecided" $ do
      Output _ sout _ <- runL4 bin ["run", assertAssumedFixture]
      length (filter ("assertion could not be evaluated" `isInfixOf`) (lines sout)) `shouldBe` 2
      sout `shouldSatisfy` ("assumed term" `isInfixOf`)
      sout `shouldNotSatisfy` ("assertion failed" `isInfixOf`)
      sout `shouldNotSatisfy` ("assertion satisfied" `isInfixOf`)

    it "fails the run when an #ASSERT is stuck on a bare assumed BOOLEAN" $
      expectFail bin ["run", assertAssumedFixture]

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

  ----------------------------------------------------------------------------
  -- One encoding, several languages.
  --
  -- The property that matters is not just "--lang he prints Hebrew" but the
  -- pair with it: a rule that has NO rendering in the requested language falls
  -- back to its default, so a half-finished translation produces a whole
  -- document rather than one with holes in it. The fixture carries one rule
  -- with both renderings and one with only English, so a single run shows
  -- both halves.
  --
  -- Asserted at the CLI rather than only in `NlgMultiplicitySpec` because the
  -- flag is the user surface, and because `l4 render` reaches the annotation
  -- through a completely different path from `l4 nlg` — the exporter in
  -- `L4.Export.Document`, not the linearizer. Both are language-aware for the
  -- same reason (`L4.Nlg.selectLanguage` moves the chosen rendering into the
  -- slot each already reads), and that shared reason is exactly the kind that
  -- looks fine until one of the two paths is changed.
  ----------------------------------------------------------------------------
  describe "l4 --lang (one encoding, several languages)" $ do
    it "l4 nlg selects the requested language" $ do
      Output code sout _ <- runL4 bin ["nlg", "--lang", "he", bilingualFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("עולה על הסף" `isInfixOf`)

    it "l4 nlg falls back for a rule with no rendering in that language" $ do
      Output code sout _ <- runL4 bin ["nlg", "--lang", "he", bilingualFixture]
      code `shouldBe` ExitSuccess
      -- `is small` is English-only; asking for Hebrew must still render it.
      sout `shouldSatisfy` ("is under the threshold" `isInfixOf`)

    it "l4 nlg with no --lang uses the default rendering" $ do
      Output code sout _ <- runL4 bin ["nlg", bilingualFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("exceeds the threshold" `isInfixOf`)
      sout `shouldNotSatisfy` ("עולה על הסף" `isInfixOf`)

    it "l4 render reaches the same annotations, through the exporter" $ do
      Output code sout _ <- runL4 bin ["render", "--format", "text", "--lang", "he", bilingualFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("עולה על הסף" `isInfixOf`)
      sout `shouldSatisfy` ("is under the threshold" `isInfixOf`)

    it "a language the file does not carry leaves the output unchanged" $ do
      -- The safety property for every existing caller: selection can only ever
      -- swap in a rendering that is actually there. `zz` is carried by nothing,
      -- so this must equal the no-flag output byte for byte.
      Output _ plain _ <- runL4 bin ["render", "--format", "text", bilingualFixture]
      Output _ asked _ <- runL4 bin ["render", "--format", "text", "--lang", "zz", bilingualFixture]
      asked `shouldBe` plain

  ----------------------------------------------------------------------------
  -- The HTML wrapper's own language (smucclaw/l4-ide#970).
  --
  -- `<html lang=...>` used to be the literal "en" whatever was rendered, so a
  -- Hebrew document arrived labelled English and with no `dir`, leaving the
  -- browser to guess direction from the characters. The label is what a screen
  -- reader picks a voice from and what `dir` hangs off, so it is not cosmetic.
  --
  -- Asserted here rather than as a golden because NO golden captures
  -- `renderHtml` at all (measured 2026-09-21: its only callers are this CLI
  -- verb and the LSP export handler), so a black-box CLI assertion is the only
  -- guard this wrapper has.
  ----------------------------------------------------------------------------
  describe "l4 render --format html (document language)" $ do
    let langModule = "examples/ok/nlg-module-lang.l4"   -- carries `@lang he`
        -- The `<html>` wrapper ALONE, not the whole document. Asserting "no
        -- `dir=` anywhere" would also forbid a per-element `dir="auto"` on a
        -- prose span, which is the natural remedy for a MIXED document and is
        -- not what any of these cases is about.
        htmlTag s = unwords [ l | l <- lines s, "<html" `isPrefixOf` l ]

    it "labels a Hebrew rendering he and marks it right-to-left" $ do
      Output code sout _ <- runL4 bin ["render", "--format", "html", "--lang", "he", langModule]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"he\" dir=\"rtl\">"

    it "labels the document en when English is asked for, and puts no dir on the wrapper" $ do
      -- NOT "an English rendering", which is what this case used to be called:
      -- the fixture's own comment says `is small` has no English herald, so
      -- asking for English still renders that clause in Hebrew. The document is
      -- MIXED and the label follows the REQUEST — ruled 2026-09-21 and written
      -- up on doc/tutorials/natural-language-functions/optimising-natural-language-generation.md.
      Output code sout _ <- runL4 bin ["render", "--format", "html", "--lang", "en", langModule]
      code `shouldBe` ExitSuccess
      -- The absence of `dir` is half the assertion: `ltr` is the HTML default,
      -- so the attribute appearing at all is what means "this runs the other way".
      htmlTag sout `shouldBe` "<html lang=\"en\">"
      -- … and this is the mixture the label is being honest about.
      sout `shouldSatisfy` ("קטן מן הסף" `isInfixOf`)

    it "falls back to the module's own @lang when no --lang is given" $ do
      Output code sout _ <- runL4 bin ["render", "--format", "html", langModule]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"he\" dir=\"rtl\">"

    it "falls back to en for a module that declares no language" $ do
      -- bilingual.l4 tags its heralds individually and declares no `@lang`.
      Output code sout _ <- runL4 bin ["render", "--format", "html", bilingualFixture]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"en\">"

    ------------------------------------------------------------------------
    -- A label the document cannot support.
    --
    -- `--lang he` on an all-English encoding used to emit
    -- `<html lang="he" dir="rtl">`: not merely a wrong label but a layout
    -- instruction, which moves an English full stop to the left end of its
    -- line. Measured with fribidi on regcf.l4, which has 0 Hebrew codepoints.
    -- Ruled 2026-09-21: when NOTHING in the module renders in the asked-for
    -- language, the document keeps the language it declares and stderr says so.
    ------------------------------------------------------------------------
    it "does not relabel a document for a language nothing in it renders" $ do
      -- clean.l4 carries no @nlg at all and declares no @lang.
      Output code sout serr <- runL4 bin ["render", "--format", "html", "--lang", "he", cleanFixture]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"en\">"
      serr `shouldSatisfy` ("no renderings in \"he\"" `isInfixOf`)
      serr `shouldSatisfy` ("labelled \"en\"" `isInfixOf`)

    it "keeps the module's declared language when the asked-for one is carried by nothing" $ do
      Output code sout serr <- runL4 bin ["render", "--format", "html", "--lang", "zz", langModule]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"he\" dir=\"rtl\">"
      serr `shouldSatisfy` ("no renderings in \"zz\"" `isInfixOf`)

    it "says nothing on stderr for a format that does not label its language" $ do
      -- `text`, `json` and `plan` carry the chosen WORDINGS and say nothing
      -- about which language they are, so the note would be noise — and this
      -- keeps `--format text --lang zz` byte-identical on both streams.
      Output code _ serr <- runL4 bin ["render", "--format", "text", "--lang", "zz", langModule]
      code `shouldBe` ExitSuccess
      serr `shouldNotSatisfy` ("no renderings" `isInfixOf`)

    ------------------------------------------------------------------------
    -- The flag's own hygiene. Before this, `--lang` was echoed verbatim into
    -- the attribute: `--lang 'he '` labelled the document `he ` AND silently
    -- lost `dir="rtl"`, because the direction lookup compared `"he "` against
    -- the table and missed. Exit 0, no diagnostic — a trailing space out of a
    -- shell variable is how it arrives.
    ------------------------------------------------------------------------
    it "trims a --lang value, so a trailing space does not cost the direction" $ do
      Output code sout _ <- runL4 bin ["render", "--format", "html", "--lang", "he ", langModule]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"he\" dir=\"rtl\">"

    it "lowercases the primary subtag, which also makes --lang HE select the Hebrew heralds" $ do
      Output code sout _ <- runL4 bin ["render", "--format", "html", "--lang", "HE", langModule]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"he\" dir=\"rtl\">"
      sout `shouldSatisfy` ("עולה על הסף" `isInfixOf`)

    it "passes a region subtag through unmangled, and falls back because nothing carries it" $ do
      -- Two things at once, and the name says both because the label alone would
      -- mislead: the reader keeps `he-IL` as typed (the stderr note quotes it
      -- back verbatim), and the LABEL is still the module's `he`, because no
      -- herald in the module is tagged `he-IL`.
      Output code sout serr <- runL4 bin ["render", "--format", "html", "--lang", "he-IL", langModule]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"he\" dir=\"rtl\">"
      serr `shouldSatisfy` ("no renderings in \"he-IL\"" `isInfixOf`)

    it "rejects an empty or malformed --lang instead of putting it in the markup" $ do
      -- `he-`, `he--IL` and the over-long subtag are the SHAPE cases: every
      -- character is legal and the tag is still not one, so a character-class
      -- check alone would have let them into the attribute.
      for_ ["", "  ", "-he", "he-", "he--IL", "abcdefghij", "he_IL", "en\"><script>"] \bad -> do
        Output code _ serr <- runL4 bin ["render", "--format", "html", "--lang", bad, langModule]
        code `shouldNotBe` ExitSuccess
        serr `shouldSatisfy` ("Invalid --lang value" `isInfixOf`)

  ----------------------------------------------------------------------------
  -- The AKN document's own language.
  --
  -- Akoma Ntoso identifies an EXPRESSION by `/akn/doc/main/<lang>@<version>`,
  -- where `<lang>` is an ISO 639-2 code. That literal was `eng` whatever was
  -- rendered, so a Hebrew act was identified as an English expression — the same
  -- defect as `<html lang="en">` (smucclaw/l4-ide#970), in the neighbouring
  -- writer, and equally silent: the XML is well formed either way.
  ----------------------------------------------------------------------------
  describe "l4 render --format akn (expression language)" $ do
    let langModule = "examples/ok/nlg-module-lang.l4"   -- carries `@lang he`
        frbrOf s = unwords [ l | l <- lines s, "FRBRExpression" `isInfixOf` l ]

    it "identifies a Hebrew expression as heb, from the module's own @lang" $ do
      Output code sout _ <- runL4 bin ["render", "--format", "akn", langModule]
      code `shouldBe` ExitSuccess
      frbrOf sout `shouldSatisfy` ("/akn/doc/main/heb@" `isInfixOf`)
      frbrOf sout `shouldNotSatisfy` ("/akn/doc/main/eng@" `isInfixOf`)

    it "follows --lang, translating the subtag to the ISO 639-2 code" $ do
      Output _ he _ <- runL4 bin ["render", "--format", "akn", "--lang", "he", langModule]
      Output _ en _ <- runL4 bin ["render", "--format", "akn", "--lang", "en", langModule]
      frbrOf he `shouldSatisfy` ("/akn/doc/main/heb@" `isInfixOf`)
      frbrOf en `shouldSatisfy` ("/akn/doc/main/eng@" `isInfixOf`)

    it "says eng for a module that declares nothing" $ do
      Output code sout _ <- runL4 bin ["render", "--format", "akn", bilingualFixture]
      code `shouldBe` ExitSuccess
      frbrOf sout `shouldSatisfy` ("/akn/doc/main/eng@" `isInfixOf`)

    it "puts the same language in the Manifestation URIs" $ do
      Output _ sout _ <- runL4 bin ["render", "--format", "akn", langModule]
      sout `shouldSatisfy` ("/akn/doc/main/heb@.xml" `isInfixOf`)
      sout `shouldNotSatisfy` ("eng@" `isInfixOf`)

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

    -- P2f (LTS-VISUALISER §1.1c): the acts every path to a terminal state
    -- must traverse, as a reader sees them. @aContract@ in contracts.l4 is
    -- S delivers, then B pays, then one of three continuations, and breach
    -- is reachable from the very first deadline — so delivery dominates
    -- FULFILLED and nothing dominates BREACH.
    it "--dominators lists the acts on every path to each terminal state" $ do
      Output code sout _ <- runL4 bin ["state-graph", "--dominators", "examples/ok/contracts.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("digraph" `notInfixOf`)
      let expected = unlines
            [ "aContract"
            , "  Every path to FULFILLED passes through:"
            , "    - PARTY S delivery (MUST, WITHIN 3)"
            , "  Every path to BREACH passes through: nothing in particular (there is more than one route)."
            ]
      sout `shouldSatisfy` (expected `isPrefixOf`)
      -- A single obligation: its act reaches FULFILLED, its deadline BREACH.
      sout `shouldSatisfy` (unlines
        [ "x"
        , "  Every path to FULFILLED passes through:"
        , "    - PARTY S delivery (MUST, WITHIN 3)"
        , "  Every path to BREACH passes through:"
        , "    - the deadline passing on PARTY S delivery (MUST, WITHIN 3)"
        ] `isInfixOf`)

    -- `z MEANS x ROR y` and `a MEANS z RAND z`: two instances of `z`, each
    -- fulfilled by either arm and breached by both timeouts, so `a` has more
    -- than one route to each ending. Until 2026-09-16 both branches were
    -- drawn onto one `z`, the fulfilment view sequenced it with itself, and
    -- the CLI answered "No path reaches FULFILLED" — exit 0, for a rule
    -- whose own #TRACE fixtures reach it.
    it "--dominators answers for a rule RANDed with itself, and never says No path reaches" $ do
      Output code sout _ <- runL4 bin ["state-graph", "--dominators", "examples/ok/contracts.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("No path reaches" `notInfixOf`)
      sout `shouldSatisfy` (unlines
        [ "z"
        , "  Every path to FULFILLED passes through: nothing in particular (there is more than one route)."
        , "  Every path to BREACH passes through:"
        , "    - the deadline passing on PARTY S delivery (MUST, WITHIN 3)"
        , "    - the deadline passing on PARTY B payment n (MUST, WITHIN 5)"
        , "a"
        , "  Every path to FULFILLED passes through: nothing in particular (there is more than one route)."
        , "  Every path to BREACH passes through: nothing in particular (there is more than one route)."
        ] `isInfixOf`)

    it "--dominators --all-states answers for the intermediate states too" $ do
      Output code sout _ <- runL4 bin
        ["state-graph", "--dominators", "--all-states", "examples/ok/contracts.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("\"initial\" is the start state" `isInfixOf`)
      -- Two things moved in this block on 2026-09-22 and neither is a change
      -- to what dominates what. The state NAME carries the obligation\'s
      -- @WITHIN@ ('L4.StateGraph.describeDeonton'), because without it the
      -- promissory note drew three of its six states under one string. And
      -- the act is printed by 'L4.Print.printActionPattern' now, which spells
      -- a binder bare: @price@ was @`price`@ here for one day, under a
      -- back-quote mark of the picture\'s own that also reached the BPMN task
      -- names. Which of @price@ and @n@ BINDS is said in the DOT, in a clause
      -- beside the act ('L4.StateGraph.labelBinds'); this view has no such
      -- clause and does not claim one.
      sout `shouldSatisfy` (unlines
        [ "  Every path to \"B must return WITHIN 10\" passes through:"
        , "    - PARTY S delivery (MUST, WITHIN 3)"
        , "    - PARTY B payment price (MUST, WITHIN 3, PROVIDED price AT LEAST 20)"
        , "    - the arm IF NOT (price EQUALS 20)"
        ] `isInfixOf`)

    it "without --dominators the DOT output is unchanged" $ do
      Output code sout _ <- runL4 bin ["state-graph", "examples/ok/contracts.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("digraph" `isPrefixOf`)
      sout `shouldSatisfy` ("Every path" `notInfixOf`)

    -- The flag has no meaning for the DOT; taking it silently would print
    -- the graph as if it had been read.
    it "--all-states without --dominators is refused, not ignored" $ do
      Output code sout serr <- runL4 bin ["state-graph", "--all-states", "examples/ok/contracts.l4"]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("requires --dominators" `isInfixOf`)
      sout `shouldSatisfy` ("digraph" `notInfixOf`)

    -- The same answer, drawn: the DOT with the dominating edges heavy and
    -- captioned. S's delivery dominates aContract's FULFILLED (above), so
    -- its edge says so and nothing else about the drawing moves.
    it "--dominators --dot keeps the DOT and marks the acts on every path to a terminal" $ do
      Output code sout _ <- runL4 bin
        ["state-graph", "--dominators", "--dot", "examples/ok/contracts.l4"]
      Output _ plain _ <- runL4 bin ["state-graph", "examples/ok/contracts.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("digraph" `isPrefixOf`)
      sout `shouldSatisfy` ("Every path" `notInfixOf`)
      sout `shouldSatisfy` ("S MUST delivery [3]\\non every path to FULFILLED" `isInfixOf`)
      sout `shouldSatisfy` ("penwidth=3" `isInfixOf`)
      plain `shouldSatisfy` ("penwidth" `notInfixOf`)
      -- A bare RAND / ROR branch edge (label "") is never marked: the list
      -- does not name it, so the picture does not either (the `z` and `a`
      -- graphs of this file have four such edges).
      sout `shouldSatisfy` ("[label=\"on every path" `notInfixOf`)
      sout `shouldSatisfy` ("[label=\"\\non every path" `notInfixOf`)
      -- Same graphs, same order: only the marked edges' lines differ.
      length (lines sout) `shouldSatisfy` (> length (lines plain))
      filter ("digraph" `isPrefixOf`) (lines sout) `shouldBe` filter ("digraph" `isPrefixOf`) (lines plain)

    it "--dot without --dominators is refused, and so is --dot with --all-states" $ do
      Output code1 sout1 serr1 <- runL4 bin ["state-graph", "--dot", "examples/ok/contracts.l4"]
      code1 `shouldSatisfy` (/= ExitSuccess)
      serr1 `shouldSatisfy` ("requires --dominators" `isInfixOf`)
      sout1 `shouldSatisfy` ("digraph" `notInfixOf`)
      Output code2 sout2 serr2 <- runL4 bin
        ["state-graph", "--dominators", "--dot", "--all-states", "examples/ok/contracts.l4"]
      code2 `shouldSatisfy` (/= ExitSuccess)
      serr2 `shouldSatisfy` ("cannot be combined" `isInfixOf`)
      sout2 `shouldSatisfy` ("digraph" `notInfixOf`)

    -- The caption defects of 2026-09-21\/22, one shape each, over
    -- 'captionFixture'. These are asserted HERE and could not be asserted
    -- anywhere else: no golden in the tree captures state-graph DOT output,
    -- and the review that found them ran the renderer by hand.
    --
    -- Each assertion names what it catches. A reader who moves one of these
    -- deliberately should be able to tell from the line above which claim
    -- about the picture they are giving up.
    it "draws an act, a binder, a deadline and a wrap the way the reader has to read them" $ do
      Output code sout _ <- runL4 bin ["state-graph", captionFixture]
      code `shouldBe` ExitSuccess

      -- Shape 1 — a suppressed caption never leaves a BLANK arrow. The inner
      -- obligation has no window, no guard, no opening, no binder and no join
      -- line, so there is nothing left once the node\'s copy is dropped and
      -- the restatement stands. A blank green arrow reads "it just goes
      -- there" where the arrow MEANS the act being performed, and it is
      -- indistinguishable from a junction\'s branch edge but for colour.
      -- This fixture has no junction, so no caption here may be empty at all.
      sout `shouldSatisfy` ("1 -> 2 [label=\"a MUST deliver (EXACTLY theChair)\"" `isInfixOf`)
      sout `shouldSatisfy` ("label=\"\"" `notInfixOf`)

      -- Shape 2 — the act is 'L4.Print.printActionPattern' and not a second
      -- printer. A hand-written one dropped the @EXACTLY@ the author wrote
      -- and the brackets round a compound pinned expression, so this read
      -- @pay base PLUS 1@ — which is @pay@ applied to three arguments.
      sout `shouldSatisfy` ("pay (EXACTLY (base" `isInfixOf`)
      sout `shouldSatisfy` ("pay base PLUS 1" `notInfixOf`)

      -- Shape 3 — a caption may name a deadline only when it is THE deadline
      -- that takes that arm. Here the act says @WITHIN 30@ and the barrier
      -- says @ONCE ALL HAVE WITHIN 10@: two clocks, one red arm, so naming
      -- either one is a precise claim that is wrong half the time. The bare
      -- word is vague and true. Both windows are still drawn, on the green
      -- edge, where they are not a claim about which fires.
      sout `shouldSatisfy` ("[label=timeout\n" `isInfixOf`)
      sout `shouldSatisfy` ("timeout [30]" `notInfixOf`)
      sout `shouldSatisfy` ("ONCE ALL HAVE WITHIN 10" `isInfixOf`)

      -- Shape 4 — the wrap breaks between tokens and never inside a
      -- back-quoted L4 name, which is ONE name that happens to contain
      -- spaces; breaking it makes the page assert a name the source has not
      -- got. Beside it, the binder clause: @sum@ is a 'L4.Syntax.PatVar' and
      -- any number discharges the act.
      sout `shouldSatisfy` ("`settle the account with` (EXACTLY" `isInfixOf`)
      sout `shouldSatisfy` ("the rule binds `sum`" `isInfixOf`)

      -- Shape 5 — the state NAME carries the obligation\'s window. Two
      -- obligations over one act pattern are told apart by nothing else, and
      -- the promissory note writes that shape three times.
      sout `shouldSatisfy` ("[label=\"theChair must pay 1 WITHIN 9\"" `isInfixOf`)

      -- Shape 6 — the binder clause is not the node\'s, so it survives the
      -- suppression that drops party, modal, act and window. It is the whole
      -- of what this arrow has left, and it says the one thing the act text
      -- cannot.
      sout `shouldSatisfy` ("1 -> 2 [label=\"the rule binds `amount`\"" `isInfixOf`)

      -- Shape 7 — and the counterpart, which is why the clause exists.
      -- @pay base@ and shape 6\'s @pay amount@ print identically, because
      -- 'L4.Print.printActionPattern' is re-emitting source and the source
      -- says a bare name in both. Only shape 6 binds; only shape 6 says so.
      sout `shouldSatisfy` ("MUST pay base [3]" `isInfixOf`)
      sout `shouldSatisfy` ("the rule binds `base`" `notInfixOf`)

      -- Shape 8 — an UNTERMINATED back-quoted run is not a name. It used to
      -- be glued into one token to the end of the line, so a single stray
      -- back quote in a string literal silently defeated the wrap for
      -- everything after it and the box grew with no diagnostic.
      sout `shouldSatisfy` ("after\\nit" `isInfixOf`)

  describe "l4 batch" $ do
    -- `batch` re-prints the module through 'prettyLayout' and re-runs it per
    -- row, so the printer is on the correctness path here, not a cosmetic one.
    --
    -- Two mixfix operators sharing a head keyword used to collapse into the
    -- same printed text, because only the head keyword survived: this rule's
    -- `P AND NOT Q` became `P AND NOT P`. On unstable's binary this exact
    -- fixture returns `"status":"error"` with "multiple definitions for the
    -- identifier `the will`"; measured 2026-09-21.
    --
    -- Asserted HERE rather than in a corpus golden because no golden captures
    -- 'prettyLayout' output at all — which is precisely how the defect
    -- survived in `canon/sg/succession/sg-wills.l4`, whose printed form
    -- stack-overflowed while every golden stayed green (smucclaw/l4-ide#967).
    it "keeps two mixfix operators that share a head keyword apart when it re-prints" $ do
      Output code sout _ <- runL4 bin
        ["batch", batchMixfixSharedHead, "--inputs", batchMixfixSharedHeadJson]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("\"status\":\"success\"" `isInfixOf`)
      sout `shouldSatisfy` ("\"result\":true" `isInfixOf`)
      sout `shouldNotSatisfy` ("multiple definitions" `isInfixOf`)

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
            -- the blame set (R-T3): the scalars describe the anchoring
            -- failure, the arrays every failure; a single obligation's breach
            -- names one party once, and it is the anchor
            , "\"obligatedParties\":[\"Alice\"]"
            , "\"obligationAction\":\"MUST pay 100\""
            , "\"deadline\":10"
            , "\"anchor\":0"
            , "\"failures\":[{"
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

    -- An ASSUME the export reads is a schema field, not a call argument.
    -- Before: the batch wrapper applied the export to every schema field
    -- positionally ("f expects 1 argument, but you are applying it to 2").
    it "binds a directly-read ASSUME by name, not as a positional argument" $ do
      env <- jsonEnvelope bin ["batch", batchAssumeDirectFixture, "--inputs", batchAssumeFullJson]
      objField env "status" `shouldBe` Just (String "success")
      Output _ sout _ <- runL4 bin ["batch", batchAssumeDirectFixture, "--inputs", batchAssumeFullJson]
      sout `shouldSatisfy` ("\"result\":21" `isInfixOf`)

    -- The read-set is transitive: an ASSUME read only by a helper the
    -- export calls is still a required field. Before: the schema was one
    -- body deep, so --validate-only accepted a row without it and
    -- evaluation then got stuck on "an assumed term".
    it "validate-only rejects a row missing an ASSUME read only by a helper" $ do
      Output code sout _ <-
        runL4 bin [ "batch", batchAssumeHelperFixture, "--inputs", batchAssumeMissingJson
                  , "--validate-only" ]
      code `shouldSatisfy` (/= ExitSuccess)
      sout `shouldSatisfy` ("\"status\":\"invalid\"" `isInfixOf`)
      sout `shouldSatisfy` ("Missing required field: 'x'" `isInfixOf`)

    it "evaluates through a helper that reads a supplied ASSUME" $ do
      env <- jsonEnvelope bin ["batch", batchAssumeHelperFixture, "--inputs", batchAssumeFullJson]
      objField env "status" `shouldBe` Just (String "success")
      Output _ sout _ <- runL4 bin ["batch", batchAssumeHelperFixture, "--inputs", batchAssumeFullJson]
      sout `shouldSatisfy` ("\"result\":22" `isInfixOf`)

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

  -- smucclaw/l4-ide#971: an IMPORT that resolves to nothing has to say so, and a
  -- candidate URI has to read back as the path it was built from.
  --
  -- Every fixture here is written at run time and run with a RELATIVE entry path,
  -- because that is the only regime the URI defect lives in. The CLI takes its
  -- root directory from `takeDirectory` of the entry path, so `l4 run
  -- importer.l4` from inside the project makes every candidate path relative --
  -- and a relative `file:` URI cannot carry a percent-escape without losing it
  -- (see `roundTrippingFileUri` in LSP.L4.Rules). Handed the very same files by
  -- an ABSOLUTE path, the bug does not reproduce at all, which is why a suite
  -- whose fixture paths all carry a directory component could not see it.
  --
  -- The basename that triggers it here is ASCII, with a SPACE in it. The defect
  -- was found with Hebrew module names, but Hebrew is not the cause: any basename
  -- that percent-escapes is lost the same way, and a space keeps a non-ASCII
  -- FILENAME out of this suite, where it would depend on the runner's filesystem
  -- encoding rather than on the code under test. jl4-lsp-test's ImportUriSpec
  -- covers the non-ASCII spelling directly, at the string level, where no locale
  -- is involved.
  describe "l4 IMPORT resolution failures (#971)" $ do
    let sandbox name files act = do
          tmp <- getTemporaryDirectory
          let dir = tmp </> name
          removePathForcibly dir
          createDirectoryIfMissing True dir
          mapM_ (\(nm, body) -> BS.writeFile (dir </> nm) (TE.encodeUtf8 (T.pack body))) files
          act dir
        -- A library whose basename percent-escapes. It is ordinary L4 otherwise.
        doubler = unlines
          [ "GIVEN n IS A NUMBER"
          , "GIVETH A NUMBER"
          , "`double it` n MEANS n TIMES 2"
          ]
        runIn dir args = do
          absDir <- makeAbsolute dir
          runL4EmbeddedOnlyIn (Just absDir) bin args

    it "resolves an import whose basename needs percent-escaping" $
      sandbox "l4-971-escaping"
        [ ("my mod.l4", doubler)
        , ("importer.l4", "IMPORT `my mod`\n#ASSERT `double it` 3 EQUALS 6\n")
        ] \dir -> do
          Output code sout serr <- runIn dir ["run", "importer.l4"]
          -- Before the fix this exited 1 with "I could not find a definition for
          -- the identifier `double it`": the file WAS found on disk, and the URI
          -- handed downstream read back as the literal name "my%20mod.l4".
          case code of
            ExitSuccess -> pure ()
            ExitFailure n -> expectationFailure $
              "Expected `my mod` to resolve, but l4 exited " ++ show n
              ++ "\n--- stdout ---\n" ++ sout
              ++ "\n--- stderr ---\n" ++ serr
          sout `shouldSatisfy` ("assertion satisfied" `isInfixOf`)

    it "reports an import of such a module that is genuinely broken" $
      sandbox "l4-971-escaping-broken"
        [ ("bad mod.l4", "THIS IS NOT L4 @@@\n")
        , ("importer.l4", "IMPORT `bad mod`\n")
        ] \dir -> do
          -- The sharper half of the same defect: the import "resolved", the
          -- imported module was never read, and nothing complained. Exit 0.
          Output code sout serr <- runIn dir ["run", "importer.l4"]
          code `shouldSatisfy` (/= ExitSuccess)
          -- and the error must name the module that is actually broken
          (sout ++ serr) `shouldSatisfy` ("bad mod.l4" `isInfixOf`)

    it "fails, naming the module and where it looked, when an import resolves to nothing" $
      sandbox "l4-971-missing"
        [ ("importer.l4", "IMPORT `zz no such module 971`\n#ASSERT `double it` 3 EQUALS 6\n") ]
        \dir -> do
          Output code _sout serr <- runIn dir ["run", "importer.l4"]
          code `shouldSatisfy` (/= ExitSuccess)
          serr `shouldSatisfy`
            ("could not find a module with this name: zz no such module 971" `isInfixOf`)
          serr `shouldSatisfy` ("I have tried the following locations" `isInfixOf`)
          -- The message has to be reachable. Until #971 an unresolved import was
          -- reported as the importing module's own URI, so this run also said
          -- "Your module depends on itself" -- TWICE on this fixture, against one
          -- copy of the message that says what is wrong. (Measured 2026-09-21 on
          -- a binary built at 57286d988: this fixture 2 under both `run` and
          -- `check`; the unreferenced fixture below 3 under `run` and 1 under
          -- `check`. The count is a function of how many rules ask for the
          -- import, so it is a symptom to read rather than a constant: what is
          -- asserted is that it is now zero.)
          serr `shouldSatisfy` (not . ("depends on itself" `isInfixOf`))

    it "fails even when nothing in the module reads the unresolved import" $
      sandbox "l4-971-missing-unreferenced"
        [ ("importer.l4", "IMPORT `zz no such module 971`\n") ]
        \dir -> do
          -- This is the case the issue is named for: with no reference to the
          -- import there is no undefined-identifier error to notice, so the exit
          -- code is the whole signal. It has always been 1 here; the golden suite
          -- is the harness that could not see it (jl4/tests/Main.hs, checkFile).
          Output code sout serr <- runIn dir ["run", "importer.l4"]
          case code of
            ExitFailure _ -> pure ()
            ExitSuccess -> expectationFailure $
              "An IMPORT that resolves to nothing left the module green."
              ++ "\n--- stdout ---\n" ++ sout
              ++ "\n--- stderr ---\n" ++ serr
          serr `shouldSatisfy`
            ("could not find a module with this name: zz no such module 971" `isInfixOf`)

    it "lists each location it looked in once, not once per tier" $
      sandbox "l4-971-duplicate-locations"
        [ ("importer.l4", "IMPORT `zz no such module 971`\n") ]
        \dir -> do
          -- The message is a list of places to go and look, so a place listed
          -- twice is a reader sent somewhere they have already been. It happened
          -- because the in-memory tier keys a candidate by URI and the
          -- filesystem tiers key it by path: with the project root at the
          -- importing file's own directory -- which is what the CLI sets it to,
          -- from `takeDirectory` of the entry path -- those name one file, and
          -- the list printed `file://zz no such module 971.l4` above
          -- `zz no such module 971.l4`. A text-level `nub` cannot see that.
          --
          -- So this compares the entries as FILES, not as strings.
          absDir <- makeAbsolute dir
          Output _code _sout serr <- runIn dir ["check", "importer.l4"]
          let listed = locationsTried serr
              -- `project:` is the web IDE's own scheme and names no path.
              paths = filter (not . ("project:" `isPrefixOf`)) listed
              asFile e = normalise (if isAbsolute e then e else absDir </> e)
          listed `shouldSatisfy` (not . null)
          -- Every place looked in is named as a PATH. That is the property that
          -- rules out the same file appearing once as a VFS URI and once as a
          -- path: there is no URI left for it to appear as. Comparing the two
          -- spellings instead would mean percent-decoding a `file:` URI and
          -- resolving /var -> /private/var inside a test, to reach the same
          -- conclusion.
          filter ("file:" `isPrefixOf`) paths `shouldBe` []
          -- ...and no location is listed twice.
          nub (map asFile paths) `shouldBe` map asFile paths

  -- `l4 export` and the DMN engine checks. Called here rather than with the
  -- other backends below because this is where those describes have always
  -- run, so the suite's output order is unchanged.
  DmnBpmn.spec bin

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

  -- An @nlg on a rule head's INPUT, which is the one placement the two
  -- projections used to disagree about (smucclaw/l4-ide#972). `l4 render` read it
  -- as the rule's sentence and `l4 nlg` as the input's gloss, so a positional
  -- call printed the rule's bare name. These assert the AGREEMENT, from both
  -- sides, because only one side has a golden: the `.nlg.golden` beside the
  -- fixture pins the `l4 nlg` column and nothing anywhere pins `l4 render`'s.
  --
  -- Rows 5, 7, 8 and 12 of the fixture are the repaired ones; row 13 and the
  -- `AKA` rows are the controls, and they are the assertions that fail if the
  -- repair is widened into an unconditional promotion.
  describe "an @nlg on a rule head's input" $ do
    let nlgOf   = runL4 bin ["nlg", nlgHeadPlacementSource]
        renderOf = runL4 bin ["render", "--format", "text", nlgHeadPlacementSource]

    it "reaches l4 nlg at a POSITIONAL call site, whichever side of the input it sits" $ do
      Output code sout _ <- nlgOf
      code `shouldBe` ExitSuccess
      -- Trailing the head (row 5), under the input (row 7), the DECIDE spelling
      -- (row 8) and the two-input case (row 12). The argument sits in the
      -- sentence's slot — a heralded call in a directive reads as its sentence
      -- (`L4.Nlg.substituteNlgDirective`) — so these pin the sentence as the
      -- whole line, with nothing appended.
      sout `shouldSatisfy` ("row five saw 200\n" `isInfixOf`)
      sout `shouldSatisfy` ("row seven saw 200\n" `isInfixOf`)
      sout `shouldSatisfy` ("row eight saw 200\n" `isInfixOf`)
      sout `shouldSatisfy` ("row twelve saw 200 over 100\n" `isInfixOf`)

    it "reaches l4 nlg at a NAMED-argument call site without printing twice" $ do
      Output _ sout _ <- nlgOf
      -- The sentence MOVES rather than being copied: leaving it on the input as
      -- well printed it once as the heading and again as the input's gloss.
      sout `shouldSatisfy` ("row five saw `amount` where `amount` is 200" `isInfixOf`)
      sout `shouldSatisfy` ("row seven saw `amount` where `amount` is 200" `isInfixOf`)

    it "renders the same sentences through l4 render, which is the point" $ do
      Output code sout _ <- renderOf
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("row five saw amount" `isInfixOf`)
      sout `shouldSatisfy` ("row seven saw amount" `isInfixOf`)
      sout `shouldSatisfy` ("row eight saw amount" `isInfixOf`)
      sout `shouldSatisfy` ("row twelve saw amount over floor" `isInfixOf`)

    it "reads the placements that already worked the same way, argument in the slot" $ do
      Output _ sout _ <- nlgOf
      sout `shouldSatisfy` ("row one saw 200\n" `isInfixOf`)
      sout `shouldSatisfy` ("row four saw 200\n" `isInfixOf`)
      sout `shouldSatisfy` ("row six saw 200\n" `isInfixOf`)
      sout `shouldSatisfy` ("row nine saw 200\n" `isInfixOf`)

    it "keeps a rule's OWN sentence when it also heralds itself (row 13)" $ do
      Output _ sout _ <- nlgOf
      -- The rule's own annotation is found first, so nothing is moved and the
      -- inner herald stays the input's gloss. An unconditional promotion would
      -- overwrite the outer one with the inner.
      sout `shouldSatisfy` ("row thirteen the rule saw 200\n" `isInfixOf`)
      sout `shouldSatisfy` ("row thirteen the input" `isInfixOf`)

    it "does not touch an AKA head, where the disagreement is a different one" $ do
      Output _ nlgOut _ <- nlgOf
      Output _ renOut _ <- renderOf
      -- Row 10: the AKA's name claims the herald, so `l4 nlg` prints it — as
      -- the bare linearizer does, slot unfilled and the argument appended,
      -- because the herald is on no position `decideNlg` searches — and
      -- `l4 render` prints its own paraphrase. Row 11: the herald above the
      -- head IS found by `decideNlg`, so the splice reads it and the two
      -- projections now agree on this row; the AKA residue is row 10 alone.
      nlgOut `shouldSatisfy` ("row ten saw `amount` with 200" `isInfixOf`)
      nlgOut `shouldSatisfy` ("row eleven saw 200\n" `isInfixOf`)
      renOut `shouldSatisfy` ("row eleven saw amount" `isInfixOf`)

    it "reads a GIVEN gloss as the input's label, never as the rule's sentence (row 14)" $ do
      Output _ nlgOut _ <- nlgOf
      Output _ renOut _ <- renderOf
      -- The head names no input, so the type checker hoists the GIVEN name
      -- into it; the gloss must not be taken for the rule's herald on that
      -- account (smucclaw/l4-ide#977). Positional: the bare name. WITH: the
      -- gloss labels the input. Render: the rule's own body.
      nlgOut `shouldSatisfy` ("`row fourteen` with 200\n" `isInfixOf`)
      nlgOut `shouldSatisfy` ("`row fourteen` where the sum of money is 200" `isInfixOf`)
      nlgOut `shouldNotSatisfy` ("the sum of money with 200" `isInfixOf`)
      renOut `shouldNotSatisfy` ("holds if the sum of money" `isInfixOf`)
      renOut `shouldSatisfy` ("Row fourteen holds if amount is more than 100" `isInfixOf`)

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

    -- This test used to assert the OPPOSITE, as a tripwire: "a future change
    -- which starts descending announces itself here rather than by silently
    -- altering what a clean run means". It announced itself, and the change was
    -- the right one (specs/todo/WHERE-INLINING-SPEC.md), so the assertion is
    -- inverted rather than deleted — the tripwire did its job and the new
    -- behaviour deserves the same guard the old one had.
    --
    -- The nested body is `y AND NOT y`, and `the outer one` is `x AND` it. The
    -- pass substitutes the zero-arity binding before analysis, so the whole
    -- decision is unsatisfiable and says so. Note this is NOT descent: the
    -- inner definition is still not analysed as a decision of its own, which is
    -- why the count above is unchanged.
    it "reports a contradiction that a WHERE clause used to hide" $ do
      Output code sout _ <- runL4 bin ["verify", verifyNestedFixture, "--format", "json"]
      code `shouldBe` ExitFailure 1
      sout `shouldSatisfy` ("unsat" `isInfixOf`)

    -- Referential transparency. Four spellings of `m AND NOT m`, three of which
    -- put a limb behind a local name; all four must report the contradiction,
    -- because they are the same rule. `parameterised` is the control: a binding
    -- that takes arguments is NOT inlined, so it stays two atoms and clean.
    it "analyses a rule the same however its limbs are named" $ do
      env <- jsonEnvelope bin ["verify", verifyWhereTransparencyFixture, "--format", "json"]
      let unsats =
            [ nm
            | Just (Array ds) <- [objField env "decisions"]
            , d <- toList ds
            , Just (String nm) <- [objField d "name"]
            , Just (Array fs) <- [objField d "findings"]
            , any (\ f -> objField f "kind" == Just (String "unsat")) (toList fs)
            ]
      sort unsats `shouldBe`
        sort ["flat", "`behind a where`", "`behind a let`", "`behind two hops`"]

    -- Termination, not correctness: a cycle among local bindings must be
    -- detected rather than substituted. A regression here hangs the suite.
    it "terminates on recursive and mutually recursive local bindings" $ do
      Output code _ _ <- runL4 bin ["verify", verifyWhereRecursiveFixture, "--format", "json"]
      code `shouldBe` ExitSuccess

    -- The corpus figure the p8-verify receipt now carries.
    it "reports the Reg CF corpus's own nested count" $ do
      env <- jsonEnvelope bin ["verify", nlgRegcfSource, "--format", "json"]
      case objField env "summary" >>= (`objField` "nestedNotVisited") of
        Just (Number n) -> n `shouldBe` 5
        other -> expectationFailure ("expected summary.nestedNotVisited, got " ++ show other)

    it "fails on a module that does not typecheck" $
      expectFail bin ["verify", errorFixture]

  OpenFisca.spec bin
  Yscript.spec bin
  Blawx.spec bin
  Docassemble.spec bin
  Catala.spec bin
  where
    for_ xs f = mapM_ f xs


-- | The locations an unresolved-IMPORT diagnostic says it tried, one per entry,
-- as they appear in @l4@'s stderr. Entries are indented under the message and
-- separated by a trailing comma; the embedded-stdlib entry is not a path and is
-- dropped, which is also why a caller cannot just stop reading at it -- it sits
-- at its own rank in the middle of the list.
locationsTried :: String -> [String]
locationsTried serr =
  case break ("I have tried the following locations" `isInfixOf`) (lines serr) of
    (_, [])          -> []
    (_, _hdr : rest) ->
      [ e
      | l <- takeWhile ("    " `isPrefixOf`) rest
      , let e = dropTrailingComma (dropWhile (== ' ') l)
      , not ("the stdlib embedded" `isPrefixOf` e)
      ]
  where
    dropTrailingComma e
      | not (null e), last e == ',' = init e
      | otherwise                   = e
