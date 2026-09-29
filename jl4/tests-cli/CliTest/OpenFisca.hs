-- | Black-box tests for @l4 export openfisca@. Split out of @Main.hs@ so a
-- release can be sliced per backend.
--
-- Four kinds of case, each answering a different question:
--
-- * __Goldens__ (examples and positive fixtures): is the emitted Python
--   byte-for-byte what was reviewed?
-- * __Refusals__ (@examples/openfisca/not-ok/@): does each construct the
--   lowering cannot compile faithfully fail with a message saying so? Every
--   refusal here once exported with exit 0 and either computed a different
--   number from L4 or crashed inside OpenFisca (PR #473 review).
-- * __Assertions__: do the L4 sources themselves still say what the goldens
--   and the round-trip assume? @jl4/examples/openfisca/@ is in no @jl4-test@
--   glob, so nothing else runs their @#ASSERT@s.
-- * __Round-trip__ (opt-in): does real OpenFisca compute what L4 computes?
module CliTest.OpenFisca (spec, fixtures) where

import Control.Exception (IOException, try)
import Control.Monad (forM_, unless, when)
import Data.List (isInfixOf, isPrefixOf)
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory)
import System.Environment (lookupEnv)
import System.Exit (ExitCode(..))
import System.FilePath ((</>), (<.>))
import Test.Hspec

import CliTest.Common

exampleDir, notOkDir, fxDir :: FilePath
exampleDir = "examples/openfisca"
notOkDir   = exampleDir </> "not-ok"
fxDir      = fixtureDir </> "openfisca"

-- | The ten examples, each with a golden under @expected/@ and a case of the
-- same name in @roundtrip_check.py@.
examples :: [String]
examples =
  [ "flat-tax", "benefit", "household", "scale", "roles", "housing", "dated"
  , "agecheck", "incometax", "basic-income" ]

-- | Constructs the export used to get wrong and now compiles correctly. Each
-- has a golden under @fixtures/openfisca/expected/@ and a round-trip case.
positiveFixtures :: [(String, String)]
positiveFixtures =
  [ ("gt-guard",        "dates a `y GREATER THAN 2015` parameter guard 2016, not 2015")
  , ("scalar-formula",  "fills a scalar-only formula to the entity's size (two persons)")
  , ("role-status",     "keeps the role key `status` (it used to become `statu`)")
  , ("carriage-return", "escapes a carriage return in a string literal")
  , ("python-keywords", "makes a record `class` and an enum `None` keyword-safe")
  , ("not-scalar",      "compiles NOT and IMPLIES over a year, a parameter or a literal with np.logical_not, not `~`")
  , ("scalar-arithmetic", "gives `scale tax` a constant income as an array, and survives a zero divisor in a branch the guard excludes")
  ]

-- | Every refusal fixture, with a fragment of the message it must print.
-- The fragment is what tells the author what is wrong: a refusal for some
-- other, incidental reason would still exit 1, and would not pass here.
refusals :: [(String, String)]
refusals =
  -- review §3: generated code must be what it appears to be
  [ ("desc-parameter-injection",   "is not a valid OpenFisca parameter path: the segment `__class__(__import__('os')`")
  , ("desc-scale-injection",       "the @desc scale path `taxes.__class__.__init__` is not a valid OpenFisca parameter path")
  , ("desc-path-words",            "takes exactly one dotted path")
  , ("non-ascii-name",             "becomes the Python identifier `area_m²`, which is not a valid ASCII Python identifier")
  -- review §1: silent miscompiles
  , ("guard-not-year",             "a year guard must be `y AT LEAST <year>` or `y GREATER THAN <year>`, where y is the value's own year input")
  , ("guard-fractional-year",      "a year guard compares the year with a whole number")
  , ("param-shape",                "A @desc parameter value must be a number literal")
  , ("param-ascending",            "the year-guarded arms must be written newest first")
  , ("param-path-conflict",        "is also the path of `high rate`")
  , ("param-explicit-year",        "the only call the export can compile is `flat amount OF period's year`")
  , ("call-other-period",          "argument 2 of `base` is its period")
  , ("call-other-subject",         "argument 1 of `base` is its subject `p`")
  , ("call-input-argument",        "argument 3 of `scaled` supplies its input `rate`")
  , ("consider-constructor-fields", "an enum whose constructor `Employed` carries fields")
  , ("consider-otherwise-not-last", "CONSIDER: OTHERWISE must be the last arm")
  , ("field-date",                 "field `born on` of `Person` has type DATE")
  , ("field-maybe",                "field `bonus` of `Person` has type MAYBE OF NUMBER")
  , ("field-nested-record",        "field `home` of `Person` has type Address, which the OpenFisca export cannot represent")
  , ("input-record",               "input `r` has type Rates, a record")
  , ("returns-date",               "its result has type DATE")
  , ("computed-field",             "`senior` is a computed field (MEANS) of `Person`")
  , ("period-day",                 "only `period's year` and `period's month` have an OpenFisca meaning")
  , ("dated-mixed-arms",           "this BRANCH mixes `period reaches` arms with other conditions")
  , ("scale-unordered",            "must be listed with strictly increasing thresholds")
  , ("scale-shrinking",            "a later arm of a @desc scale has fewer brackets than an earlier one")
  -- review §2: generated code that crashed in OpenFisca
  , ("list-of-number",             "field `scores` of `Person` has type LIST OF NUMBER")
  , ("two-person-entities",        "OpenFisca allows exactly one person entity, but this module would declare 2: `Person`, `Company`")
  , ("entity-person-and-group",    "the record `Person` would be both a group entity")
  , ("nested-group",               "the member record `Family` of the group `Household` itself has a LIST OF field")
  , ("group-mixed-members",        "has LIST OF fields of different record types (`Person`, `Pet`)")
  , ("cross-entity-call",          "cross-entity call: `person tax` is a variable of the entity `Person`, but this decision is computed on `Household`")
  , ("group-value-in-member",      "`bonus` of the subject is a value of the group")
  , ("member-unused",              "the per-member expression inside the aggregation does not read the member")
  , ("nested-aggregation",         "nested aggregations are not supported")
  , ("role-key-clash",             "two roles of `Household` share the key `adult`")
  , ("role-variable-clash",        "the role `people` of `Household` has the same name as a variable of that entity")
  , ("python-name-clash",          "two definitions would both be bound to the Python name `Person`")
  -- review §4: recognition by identity or canonical form, and messages
  , ("sum-redefined",              "`sum` here resolves to a definition in this module, not to the prelude's `sum`")
  , ("period-reaches-redefined",   "`period reaches` is recognised by name and compiled to OpenFisca's dated formulas")
  , ("scale-tax-redefined",        "`scale tax` is recognised by name and compiled to OpenFisca's marginal-rate `.calc()`")
  , ("members-of-redefined",       "`members of` is recognised by name and compiled to all of the group's members")
  , ("band-swapped",               "`band` is not a bracket builder the export recognises")
  , ("helper-not-exported",        "cannot compile the call to `double`: it is not an @export decision")
  , ("enum-result",                "the result type is the enum `Band`")
  , ("period-mismatch",            "is needed with two definition periods: MONTH and ETERNITY")
  , ("name-collision",             "both compile to the OpenFisca variable `foo_bar`")
  , ("branch-misordered",          "dated-formula BRANCH arms must be in strictly-descending date order")
  ]

exampleFile, notOkFile, fxFile :: String -> FilePath
exampleFile n = exampleDir </> n <.> "l4"
notOkFile n   = notOkDir </> n <.> "l4"
fxFile n      = fxDir </> n <.> "l4"

-- | Files this module's tests need. 'Main.main' checks every module's list
-- before hspec runs anything, so a renamed fixture is a loud failure rather
-- than a case that quietly tests a missing file.
fixtures :: [FilePath]
fixtures =
     concat [ [exampleFile n, exampleDir </> "expected" </> n <.> "py"] | n <- examples ]
  <> concat [ [fxFile n, fxDir </> "expected" </> n <.> "py"] | (n, _) <- positiveFixtures ]
  <> [ notOkFile n | (n, _) <- refusals ]
  <> [roundTripScript]

roundTripScript :: FilePath
roundTripScript = exampleDir </> "roundtrip_check.py"

spec :: FilePath -> Spec
spec bin = do
  describe "l4 export openfisca" $ do
    forM_ examples \n ->
      it ("compiles the " ++ n ++ " example to its golden OpenFisca module") $
        expectGolden bin ["export", "openfisca", exampleFile n]
                         (exampleDir </> "expected" </> n <.> "py")

    forM_ positiveFixtures \(n, what) ->
      it what $
        expectGolden bin ["export", "openfisca", fxFile n]
                         (fxDir </> "expected" </> n <.> "py")

    it "emits a Variable subclass and a TaxBenefitSystem" $ do
      Output code sout _ <- runL4 bin ["export", "openfisca", exampleFile "flat-tax"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("class flat_tax_on_salary(Variable):" `isInfixOf`)
      sout `shouldSatisfy` ("class L4TaxBenefitSystem(TaxBenefitSystem):" `isInfixOf`)

    it "fails on a file that does not typecheck" $
      expectFail bin ["export", "openfisca", errorFixture]

  describe "l4 export openfisca refuses what it cannot compile faithfully" $
    forM_ refusals \(n, needle) ->
      it n $ expectRefusal bin (notOkFile n) needle

  -- `l4 run` exits 0 even when an assertion fails, so the exit code proves
  -- nothing here: the count of satisfied assertions must equal the number of
  -- #ASSERT lines, which also fails if a file stops being evaluated at all.
  describe "the OpenFisca examples' and fixtures' #ASSERTs hold in L4" $
    forM_ ( map exampleFile examples
         <> map (fxFile . fst) positiveFixtures
         <> map (notOkFile . fst) refusals ) \fp ->
      it fp $ expectAssertionsHold bin fp

  describe "OpenFisca round-trip (opt-in: L4_OPENFISCA_CHECK=1)" $
    forM_ ( [ (n, exampleFile n) | n <- examples ]
         <> [ (n, fxFile n) | (n, _) <- positiveFixtures ] ) \(n, fp) ->
      it ("real OpenFisca computes what L4 computes: " ++ n) $
        openFiscaRoundTrip bin n fp

-- | The export must fail, and its diagnostics must contain the needle.
expectRefusal :: FilePath -> FilePath -> String -> Expectation
expectRefusal bin fp needle = do
  Output code sout serr <- runL4 bin ["export", "openfisca", fp]
  when (code == ExitSuccess) $
    expectationFailure ("Expected the export to refuse " ++ fp ++ ", but it exited 0\n--- stdout ---\n" ++ sout)
  unless (needle `isInfixOf` (sout ++ serr)) $
    expectationFailure $
      "Refused " ++ fp ++ ", but not with the expected message " ++ show needle
      ++ "\n--- stderr ---\n" ++ serr

-- | Every #ASSERT in the file is evaluated and satisfied.
expectAssertionsHold :: FilePath -> FilePath -> Expectation
expectAssertionsHold bin fp = do
  src <- readUtf8 fp
  let asserts = length (filter ("#ASSERT" `isPrefixOf`) (lines src))
  Output code sout serr <- runL4 bin ["run", fp]
  code `shouldBe` ExitSuccess
  let count needle = length (filter (needle `isInfixOf`) (lines sout))
  when (count "assertion failed" > 0 || "assertion failed" `isInfixOf` serr) $
    expectationFailure ("An #ASSERT failed in " ++ fp ++ "\n--- stdout ---\n" ++ sout)
  unless (count "assertion satisfied" == asserts) $
    expectationFailure $
      fp ++ " has " ++ show asserts ++ " #ASSERT line(s) but `l4 run` reported "
      ++ show (count "assertion satisfied") ++ " satisfied\n--- stdout ---\n" ++ sout
      ++ "\n--- stderr ---\n" ++ serr

-- | Export one case and run @roundtrip_check.py@ over it in real OpenFisca.
--
-- __Why this is opt-in.__ @cabal test all@ must stay hermetic: this needs a
-- Python with openfisca-core and numpy, which CI does not install. It runs
-- only under @L4_OPENFISCA_CHECK=1@, with the interpreter named by
-- @L4_OPENFISCA_PYTHON@ (default @python3@). When that interpreter cannot
-- import openfisca_core the case is reported PENDING as UNEXERCISED, and
-- @OPENFISCA_CHECK_REQUIRED=1@ turns that into a failure.
--
-- __Why the assertion is on the banner as well as the exit code.__ The script
-- prints @ROUND-TRIP OK@ only after every check of the case has run, so a
-- script that exits 0 without reaching its checks cannot pass here.
openFiscaRoundTrip :: FilePath -> String -> FilePath -> Expectation
openFiscaRoundTrip bin name fp = do
  enabled <- lookupEnv "L4_OPENFISCA_CHECK"
  case enabled of
    Just "1" -> do
      python   <- maybe "python3" id <$> lookupEnv "L4_OPENFISCA_PYTHON"
      required <- (== Just "1") <$> lookupEnv "OPENFISCA_CHECK_REQUIRED"
      probe <- try (runL4In Nothing Nothing python ["-c", "import openfisca_core, numpy"])
      let unexercised why
            | required  = expectationFailure ("OpenFisca round-trip could not run: " ++ why)
            | otherwise = pendingWith
                ("OpenFisca round-trip UNEXERCISED: " ++ why
                   ++ " (set OPENFISCA_CHECK_REQUIRED=1 to make this a failure)")
      case probe of
        Left (e :: IOException) -> unexercised (python ++ " could not be started: " ++ show e)
        Right (Output (ExitFailure _) _ perr) ->
          unexercised (python ++ " cannot import openfisca_core and numpy: " ++ unwords (words perr))
        Right _ -> do
          tmp <- getTemporaryDirectory
          let dir = tmp </> "l4-openfisca-roundtrip"
              gen = dir </> name <.> "py"
          createDirectoryIfMissing True dir
          Output ecode _ eerr <- runL4 bin ["export", "openfisca", fp, "-o", gen]
          unless (ecode == ExitSuccess) $
            expectationFailure ("export failed for " ++ fp ++ "\n--- stderr ---\n" ++ eerr)
          Output rcode rout rerr <- runL4In Nothing Nothing python [roundTripScript, gen, name]
          unless (rcode == ExitSuccess && "ROUND-TRIP OK" `isInfixOf` rout) $
            expectationFailure $
              "OpenFisca disagrees with L4 on " ++ name
              ++ "\n--- stdout ---\n" ++ rout ++ "\n--- stderr ---\n" ++ rerr
    _ ->
      pendingWith "OpenFisca round-trip UNEXERCISED: set L4_OPENFISCA_CHECK=1 to run it"
