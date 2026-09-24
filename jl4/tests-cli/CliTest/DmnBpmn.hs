-- | Black-box tests for @l4 export dmn@, @dmn-md@ and @bpmn@, and the
-- opt-in DMN engine checks, with the fixtures and engine-harness machinery
-- only they use. Split out of @Main.hs@ so a release can be sliced per
-- backend; 'Main.spec' calls 'spec' where these describes always ran.
module CliTest.DmnBpmn (spec, fixtures) where

import Control.Monad (unless, when)
import Data.List (isInfixOf, sort)
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , getTemporaryDirectory
  , removePathForcibly
  )
import System.Environment (lookupEnv)
import System.Exit (ExitCode(..))
import System.FilePath ((</>))
import Test.Hspec

import CliTest.Common

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

-- | Files this module's tests need to exist. 'Main.main' checks every
-- module's list before hspec runs anything.
fixtures :: [FilePath]
fixtures =
  [ exportTwoRulesFixture, exportNothingFixture
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
  ]

spec :: FilePath -> Spec
spec bin = do
  -- Track S0: `l4 export dmn|dmn-md|bpmn [--fidelity-report]`.
  --
  -- The interesting property of these goldens is that they are not new files.
  -- `jl4/tests/BpmnExport.hs` and `jl4/tests/DmnExport.hs` build the same
  -- artifacts through the library API (`checkWithImports`), and the CLI reaches
  -- them through a completely different front end (the LSP one-shot Shake
  -- pipeline). Byte equality across those two paths is the actual claim.
  describe "l4 export" $ do
    it "reproduces the BPMN golden byte-for-byte on stdout" $
      expectGolden bin ["export", "bpmn", bpmnOfferingSource] bpmnOfferingGolden

    it "reproduces the DMN 1.3 XML golden byte-for-byte on stdout" $
      expectGolden bin ["export", "dmn", dmnSource, "--model-name", dmnModelName]
                       dmnGolden

    it "reproduces the dmnmd markdown golden byte-for-byte on stdout" $
      expectGolden bin ["export", "dmn-md", dmnSource, "--model-name", dmnModelName]
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
        ["export", "bpmn", bpmnOfferingSource, "-o", outFile, "--fidelity-report"]
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
      -- `l4 export bpmn f.l4 --fidelity-report > f.bpmn` must still
      -- produce an importable file.
      Output code sout serr <- runL4 bin
        ["export", "bpmn", bpmnOfferingSource, "--fidelity-report"]
      code `shouldBe` ExitSuccess
      goldenXml <- readUtf8 bpmnOfferingGolden
      sout `shouldBe` goldenXml
      serr `shouldSatisfy` ("fidelity report — BPMN 2.0" `isInfixOf`)
      serr `shouldSatisfy` ("[F1]" `isInfixOf`)

    it "tallies what was lost on stderr even without --fidelity-report" $ do
      -- The report is not optional in spirit: an export never silently drops
      -- what the source said just because the caller did not know to ask.
      Output code _ serr <- runL4 bin ["export", "bpmn", bpmnOfferingSource]
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
      Output code _ _ <- runL4 bin ["export", "bpmn", bpmnOfferingSource]
      code `shouldBe` ExitSuccess

    it "exits non-zero on a Blocking note under --fail-on=blocking" $
      expectFail bin ["export", "bpmn", bpmnOfferingSource, "--fail-on=blocking"]

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
      let dmnGate fixture gate = runL4 bin (["export", "dmn", fixture] <> gate)
          exitsNonZero fixture gate = do
            Output code _ _ <- dmnGate fixture gate
            code `shouldSatisfy` (/= ExitSuccess)
          exitsZero fixture gate = do
            Output code _ _ <- dmnGate fixture gate
            code `shouldBe` ExitSuccess

      it "a blocking-only report is caught by every threshold" $ do
        -- `l4 export dmn export-blocking-only.l4` reports 2 blocking,
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
        -- `l4 export dmn export-advisory-only.l4` reports 1 advisory and
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
        expectFail bin ["export", "dmn", exportTwoRulesFixture]

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
      Output code sout _ <- runL4 bin ["export", "dmn", importViewFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("decision_statute" `isInfixOf`)
      sout `shouldSatisfy` (not . ("local sample" `isInfixOf`))

    it "still writes the document when --fail-on trips" $ do
      Output code sout _ <- runL4 bin
        ["export", "bpmn", bpmnOfferingSource, "--fail-on=blocking"]
      code `shouldSatisfy` (/= ExitSuccess)
      goldenXml <- readUtf8 bpmnOfferingGolden
      sout `shouldBe` goldenXml

    it "honours --deadline-unit=refuse (no invented ISO duration)" $ do
      Output code _ serr <- runL4 bin
        ["export", "bpmn", bpmnOfferingSource, "--deadline-unit=refuse"]
      code `shouldBe` ExitSuccess
      -- Under the default the unitless WITHINs are read as days and reported as
      -- P-DEADLINE-UNIT advisories; under `refuse` they become P-DEADLINE.
      serr `shouldSatisfy` ("P-DEADLINE" `isInfixOf`)
      Output _ soutDefault _ <- runL4 bin ["export", "bpmn", bpmnOfferingSource]
      Output _ soutRefuse  _ <- runL4 bin
        ["export", "bpmn", bpmnOfferingSource, "--deadline-unit=refuse"]
      soutDefault `shouldSatisfy` ("timerEventDefinition" `isInfixOf`)
      soutRefuse `shouldSatisfy` (not . ("timerEventDefinition" `isInfixOf`))

    it "rejects an unknown format" $ do
      Output code _ serr <- runL4 bin ["export", "xml", dmnSource]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("Invalid argument `xml'" `isInfixOf`)

    it "requires a format before the file" $
      expectFail bin ["export", dmnSource]

    it "refuses BPMN when the module has no regulative rules" $ do
      Output code _ serr <- runL4 bin ["export", "bpmn", exportNothingFixture]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("regulative" `isInfixOf`)

    it "refuses DMN when the module has no decisions" $ do
      Output code _ serr <- runL4 bin ["export", "dmn", exportNothingFixture]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("No decisions found" `isInfixOf`)

    it "refuses to guess which process to draw, and names the candidates" $ do
      -- renderBpmn writes its own XML prolog, so two processes concatenated is
      -- not a document. Refusing beats emitting something no tool can read.
      Output code _ serr <- runL4 bin ["export", "bpmn", exportTwoRulesFixture]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("--rule" `isInfixOf`)
      serr `shouldSatisfy` ("the filing" `isInfixOf`)
      serr `shouldSatisfy` ("the fee" `isInfixOf`)

    it "selects one process with --rule" $ do
      Output code sout _ <- runL4 bin
        ["export", "bpmn", exportTwoRulesFixture, "--rule", "the fee"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("<?xml" `isInfixOf`)
      sout `shouldSatisfy` ("the fee" `isInfixOf`)
      sout `shouldSatisfy` (not . ("the filing" `isInfixOf`))

    it "fails on an unknown --rule and lists what is available" $ do
      Output code _ serr <- runL4 bin
        ["export", "bpmn", exportTwoRulesFixture, "--rule", "no such rule"]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("no such rule" `isInfixOf`)
      serr `shouldSatisfy` ("the filing" `isInfixOf`)

    it "rejects --rule on a DMN export instead of ignoring it" $ do
      Output code _ serr <- runL4 bin ["export", "dmn", dmnSource, "--rule", "x"]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("Invalid option `--rule'" `isInfixOf`)

    it "rejects --model-name on a BPMN export instead of ignoring it" $ do
      Output code _ serr <- runL4 bin
        ["export", "bpmn", bpmnOfferingSource, "--model-name", "X"]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("--model-name" `isInfixOf`)

    it "fails on a file that does not typecheck" $
      expectFail bin ["export", "dmn", errorFixture]

    -- --flavor (R7). The two flavors differ on exactly one construct, and that
    -- construct is not emitted until Phase 5, so today the flag is observable
    -- only in the fidelity report's target line. That is deliberate: the seam
    -- and its goldens land before the divergence does, so that when the
    -- divergence arrives it has somewhere to be checked.
    describe "--flavor" $ do
      it "defaults to camunda, and says so in the report rather than just 'DMN'" $ do
        Output code _ serr <- runL4 bin
          ["export", "dmn", dmnSource, "--model-name", dmnModelName, "--fidelity-report"]
        code `shouldBe` ExitSuccess
        serr `shouldSatisfy` ("DMN 1.3 (XML), camunda flavor" `isInfixOf`)

      it "accepts kie, and drools as a synonym for it" $
        for_ ["kie", "drools"] \flavor -> do
          Output code _ serr <- runL4 bin
            [ "export", "dmn", dmnSource, "--model-name", dmnModelName
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
        Output _ svcCam _ <- runL4 bin ["export", "dmn", svcSource]
        Output _ svcKie _ <- runL4 bin ["export", "dmn", svcSource, "--flavor=kie"]
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
          ["export", "dmn", dmnSource, "--model-name", dmnModelName, "--flavor=camunda"]
        Output _ kie _ <- runL4 bin
          ["export", "dmn", dmnSource, "--model-name", dmnModelName, "--flavor=kie"]
        kie `shouldBe` camunda
        golden <- readUtf8 dmnGolden
        camunda `shouldBe` golden

      it "rejects --flavor on dmn-md, because nothing on that path reads it" $ do
        -- It was admitted here at first, on the theory that "the flavor lives
        -- in the Drg, which both emitters read". It does not: emitMarkdown
        -- mentions no field of it and markdownReport hard-codes the target
        -- "dmnmd", so --flavor=kie produced a byte-identical document AND a
        -- byte-identical fidelity report. That is the silent ignore the
        -- per-format parsers now refuse by not offering the flag at all.
        Output code _ serr <- runL4 bin
          ["export", "dmn-md", dmnSource, "--model-name", dmnModelName, "--flavor=kie"]
        code `shouldSatisfy` (/= ExitSuccess)
        serr `shouldSatisfy` ("Invalid option `--flavor=kie'" `isInfixOf`)

      it "still accepts --model-name on dmn-md, which does belong to both" $ do
        Output code sout _ <- runL4 bin
          ["export", "dmn-md", dmnSource, "--model-name", dmnModelName]
        code `shouldBe` ExitSuccess
        golden <- readUtf8 dmnMarkdownGolden
        sout `shouldBe` golden

      it "rejects --flavor on a BPMN export instead of ignoring it" $ do
        Output code _ serr <- runL4 bin
          ["export", "bpmn", bpmnOfferingSource, "--flavor=kie"]
        code `shouldSatisfy` (/= ExitSuccess)
        serr `shouldSatisfy` ("Invalid option `--flavor=kie'" `isInfixOf`)

      it "rejects an unknown flavor, naming the accepted ones" $ do
        Output code _ serr <- runL4 bin
          ["export", "dmn", dmnSource, "--flavor=camunda7"]
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
    -- structurally inert, THE LEAP CASE, THE ESCHEAT CASE, and (2026-09-05,
    -- ruling D1) THE PRE-COMMENCEMENT CASE, which is the first here to ask a
    -- rule date below Reg CF's 2016-05-16 commencement AND the first to supply
    -- NEITHER refusal -- both are explicit JSON nulls rather than the -1 and the
    -- invented assurance level every other case hands the model. 23 x 70 = 1610.
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
          out `shouldSatisfy` ("23 case(s)" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("0 warning(s)" `isInfixOf`)
          out `shouldSatisfy` ("1610/1610 decision(s) SUCCEEDED" `isInfixOf`)
          out `shouldSatisfy` ("1610/1610 value(s) as expected" `isInfixOf`)
          -- the SVC leg is a value check since 2026-08-02 (each service fed
          -- its inputDecisions' computed values, each outputDecision compared
          -- against the same expect entry): 7 services, 15 declared outputs,
          -- per case
          out `shouldSatisfy` ("345/345 service output value(s) as expected" `isInfixOf`)

    it "Camunda parses and answers the whole Reg CF corpus (R12/R13)" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustPass
        corpusGolden [corpusGolden, "--cases", corpusEngineCases] \out -> do
          out `shouldSatisfy` ("Camunda 8.7.6 (zeebe-dmn) VERDICT" `isInfixOf`)
          out `shouldSatisfy` ("23 case(s)" `isInfixOf`)
          out `shouldSatisfy` ("1 parsed" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("1610/1610 decision(s) evaluated" `isInfixOf`)
          out `shouldSatisfy` ("1610/1610 value(s) as expected" `isInfixOf`)

  -- The LAW-TIME legs (spec §15). What is being asserted here that nothing
  -- else asserts: the SAME model answers DIFFERENTLY for different rule dates,
  -- in a real engine, driven only by half-open date intervals on a UNIQUE
  -- table. `77/77 value(s) as expected` over ELEVEN cases is the claim -- eleven
  -- rule dates x seven decisions (Phase 5 moved `the rules in force include`
  -- to a businessKnowledgeModel, which the cases schema cannot assert -- its
  -- logic is exercised through the interval endpoints D2 inlined it into; and
  -- since 2026-09-06 the pre-commencement floor is a REFUSE, so it is a
  -- decision answering null in every case rather than an input handed in as
  -- -1: 66 became 77) -- and seven of those cases exist purely to pin the
  -- interval convention: a day-of/day-before pair on each of the three seams,
  -- plus a rule date well before commencement. F, J and K all reach the floor
  -- now; until the migration F and J handed the model -1 and expected -1 back,
  -- so only K (2026-09-05, ruling D1) reached the bottom the floor arm names.
  describe "law time on a date axis (opt-in: L4_DMN_ENGINE_CHECK=1)" $ do
    it "KIE answers the dated-regime exhibit correctly for eleven rule dates" $
      dmnEngineCheckOn "KIE" kieCheckScript "KIE_CHECK_REQUIRED" HarnessMustPass
        gstGolden [gstGolden, "--cases", gstEngineCases] \out -> do
          out `shouldSatisfy` ("KIE 8.44.0.Final VERDICT" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          -- zero warnings is load-bearing: the emitted BKM must carry its
          -- DMNShape, or KIE raises WARN [DMNDI_MISSING_DIAGRAM] (measured
          -- 2026-08-01; the shape row above the decisions exists for this).
          out `shouldSatisfy` ("0 warning(s)" `isInfixOf`)
          out `shouldSatisfy` ("77/77 decision(s) SUCCEEDED" `isInfixOf`)
          out `shouldSatisfy` ("77/77 value(s) as expected" `isInfixOf`)

    it "Camunda answers the dated-regime exhibit correctly for eleven rule dates" $
      dmnEngineCheckOn "Camunda" camundaCheckScript "CAMUNDA_CHECK_REQUIRED" HarnessMustPass
        gstGolden [gstGolden, "--cases", gstEngineCases] \out -> do
          out `shouldSatisfy` ("Camunda 8.7.6 (zeebe-dmn) VERDICT" `isInfixOf`)
          out `shouldSatisfy` ("1 parsed" `isInfixOf`)
          out `shouldSatisfy` ("0 error(s)" `isInfixOf`)
          out `shouldSatisfy` ("77/77 decision(s) evaluated" `isInfixOf`)
          out `shouldSatisfy` ("77/77 value(s) as expected" `isInfixOf`)

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
  where
    for_ xs f = mapM_ f xs
