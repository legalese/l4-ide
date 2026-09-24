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
