-- | Black-box tests for @l4 export openfisca@. Split out of @Main.hs@ so a
-- release can be sliced per backend.
module CliTest.OpenFisca (spec, fixtures) where

import Data.List (isInfixOf)
import System.Exit (ExitCode(..))
import Test.Hspec

import CliTest.Common

-- | Files this module's tests need to exist. 'Main.main' checks every
-- module's list before hspec runs anything; nothing here is checked up front
-- today, because the files these tests read are named inline in the tests.
fixtures :: [FilePath]
fixtures = []

spec :: FilePath -> Spec
spec bin = do
  describe "l4 export openfisca" $ do
    it "compiles the flat-tax example to its golden OpenFisca module" $
      expectGolden bin ["export", "openfisca", "examples/openfisca/flat-tax.l4"]
                       "examples/openfisca/expected/flat-tax.py"

    it "compiles the means-tested benefit example to its golden module" $
      expectGolden bin ["export", "openfisca", "examples/openfisca/benefit.l4"]
                       "examples/openfisca/expected/benefit.py"

    it "compiles a group entity with LIST OF aggregation (household)" $
      expectGolden bin ["export", "openfisca", "examples/openfisca/household.l4"]
                       "examples/openfisca/expected/household.py"

    it "compiles a time-varying marginal-rate scale + parameter store (scale)" $
      expectGolden bin ["export", "openfisca", "examples/openfisca/scale.l4"]
                       "examples/openfisca/expected/scale.py"

    it "compiles roles + count/any/all aggregation (roles)" $
      expectGolden bin ["export", "openfisca", "examples/openfisca/roles.l4"]
                       "examples/openfisca/expected/roles.py"

    it "compiles an enum + CONSIDER (housing)" $
      expectGolden bin ["export", "openfisca", "examples/openfisca/housing.l4"]
                       "examples/openfisca/expected/housing.py"

    it "compiles dated formulas (BRANCH IF period reaches → formula_YYYY_MM)" $
      expectGolden bin ["export", "openfisca", "examples/openfisca/dated.l4"]
                       "examples/openfisca/expected/dated.py"

    it "compiles a member decision-call inside an aggregation (agecheck)" $
      expectGolden bin ["export", "openfisca", "examples/openfisca/agecheck.l4"]
                       "examples/openfisca/expected/agecheck.py"

    it "compiles a scalar legislation-parameter store (incometax)" $
      expectGolden bin ["export", "openfisca", "examples/openfisca/incometax.l4"]
                       "examples/openfisca/expected/incometax.py"

    it "compiles the country-template basic_income (dated formulas + scalar params)" $
      expectGolden bin ["export", "openfisca", "examples/openfisca/basic-income.l4"]
                       "examples/openfisca/expected/basic-income.py"

    -- TYPICALLY-ONE-BEHAVIOUR-SPEC T5: OpenFisca gives every variable a default
    -- of its own, so a TYPICALLY that is not written as `default_value` is
    -- replaced by 0.0 / False / the first enum member. Mapping is mandatory.
    it "writes a TYPICALLY as the input variable's default_value (defaults)" $
      expectGolden bin ["export", "openfisca", "examples/openfisca/defaults.l4"]
                       "examples/openfisca/expected/defaults.py"

    it "maps a number and a boolean on a field and on a GIVEN, and an enum member on a GIVEN" $ do
      Output code sout _ <- runL4 bin ["export", "openfisca", "examples/openfisca/defaults.l4"]
      code `shouldBe` ExitSuccess
      -- record fields
      sout `shouldSatisfy` ("default_value = 40.0" `isInfixOf`)
      sout `shouldSatisfy` ("default_value = True" `isInfixOf`)
      -- rule GIVENs
      sout `shouldSatisfy` ("default_value = 3.0" `isInfixOf`)
      -- an enum default is the member the source wrote, not the first declared
      sout `shouldSatisfy` ("default_value = Status.married" `isInfixOf`)
      sout `shouldSatisfy` (not . ("default_value = Status.single" `isInfixOf`))

    -- A defaulted field used to be read as a computed one, so it never became an
    -- input variable and the formula that read it named a variable the module did
    -- not define (OpenFisca: VariableNotFoundError at the first simulation).
    it "still defines an input variable for a field that carries a TYPICALLY" $ do
      Output code sout _ <- runL4 bin ["export", "openfisca", "examples/openfisca/defaults.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("class hours_a_week(Variable):" `isInfixOf`)
      sout `shouldSatisfy` ("class is_resident(Variable):" `isInfixOf`)

    it "leaves a module with no TYPICALLY exactly as it was (no default_value on a float input)" $ do
      Output code sout _ <- runL4 bin ["export", "openfisca", "examples/openfisca/flat-tax.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` (not . ("default_value" `isInfixOf`))

    it "refuses two exported decisions that give one input different defaults, and names both" $ do
      Output code _ serr <- runL4 bin ["export", "openfisca", "examples/openfisca/not-ok/defaults-conflict.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("different TYPICALLY defaults (3 and 5)" `isInfixOf`)

    it "refuses a default against none, and says what none means" $ do
      Output code _ serr <- runL4 bin ["export", "openfisca", "examples/openfisca/not-ok/defaults-vs-none.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("different TYPICALLY defaults (3 and none" `isInfixOf`)
      serr `shouldSatisfy` ("OpenFisca then gives the input its own default for its type" `isInfixOf`)

    it "rejects a name collision (distinct L4 names → same Python identifier)" $
      expectFail bin ["export", "openfisca", "examples/openfisca/not-ok/name-collision.l4"]

    it "rejects a mis-ordered dated BRANCH (ascending arms)" $
      expectFail bin ["export", "openfisca", "examples/openfisca/not-ok/branch-misordered.l4"]

    it "emits a Variable subclass and a TaxBenefitSystem" $ do
      Output code sout _ <- runL4 bin ["export", "openfisca", "examples/openfisca/flat-tax.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("class flat_tax_on_salary(Variable):" `isInfixOf`)
      sout `shouldSatisfy` ("class L4TaxBenefitSystem(TaxBenefitSystem):" `isInfixOf`)

    it "fails on a file that does not typecheck" $
      expectFail bin ["export", "openfisca", errorFixture]
