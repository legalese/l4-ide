-- | Black-box tests for @l4 export yscript@. Split out of @Main.hs@ so a
-- release can be sliced per backend.
module CliTest.Yscript (spec, fixtures) where

import Data.List (isInfixOf)
import System.Exit (ExitCode(..))
import System.FilePath ((</>))
import Test.Hspec

import CliTest.Common

-- | Files this module's tests need to exist. 'Main.main' checks every
-- module's list before hspec runs anything; nothing here is checked up front
-- today, because the files these tests read are named inline in the tests.
fixtures :: [FilePath]
fixtures = []

spec :: FilePath -> Spec
spec bin = do
  describe "l4 export yscript" $ do
    it "compiles the Foreign Relations Act s10 example to its golden yscript" $
      expectGolden bin ["export", "yscript", "examples/yscript/foreign-relations-s10.l4"]
                       "examples/yscript/expected/foreign-relations-s10.ys"

    it "compiles the Hairdressers Act s4(1) example to its golden yscript" $
      expectGolden bin ["export", "yscript", "examples/yscript/hairdressers-s4-1.l4"]
                       "examples/yscript/expected/hairdressers-s4-1.ys"

    it "emits one RULE per in-fragment Decide, PROVIDES text verbatim" $ do
      Output code sout _ <- runL4 bin ["export", "yscript", "examples/yscript/foreign-relations-s10.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("RULE Section 10 - Core foreign arrangements PROVIDES" `isInfixOf`)
      sout `shouldSatisfy` ("RULE Section 10(3) PROVIDES" `isInfixOf`)
      sout `shouldSatisfy` ("ONLY IF" `isInfixOf`)

    it "fails on a file that does not typecheck" $
      expectFail bin ["export", "yscript", errorFixture]

    it "rejects a call (with arguments) to a parameterised Decide reached from the \
       \@export closure (R1)" $ do
      Output code _ serr <- runL4 bin ["export", "yscript", fixtureDir </> "yscript-parameterized-decide.l4"]
      code `shouldNotBe` ExitSuccess
      shouldContain' "stderr" serr "argument"

    it "rejects a parameterised @export entry point itself (R1)" $ do
      Output code _ serr <- runL4 bin ["export", "yscript", fixtureDir </> "yscript-parameterized-export.l4"]
      code `shouldNotBe` ExitSuccess
      shouldContain' "stderr" serr "has parameters"

    it "rejects NOT (R2: yscript's negation spelling is unverified)" $ do
      Output code _ serr <- runL4 bin ["export", "yscript", fixtureDir </> "yscript-not.l4"]
      code `shouldNotBe` ExitSuccess
      shouldContain' "stderr" serr "NOT"

    it "rejects a non-boolean ASSUME reached from the @export closure (R1/R3)" $ do
      Output code _ serr <- runL4 bin ["export", "yscript", fixtureDir </> "yscript-non-boolean-assume.l4"]
      code `shouldNotBe` ExitSuccess
      shouldContain' "stderr" serr "not BOOLEAN"

    -- TYPICALLY-ONE-BEHAVIOUR-SPEC T5b: "yscript refuses a module whose exported
    -- rule reads an input with a TYPICALLY default, as R5 requires; it gets no
    -- channel." A consultation asks the user for every fact, so the default would
    -- be dropped and the user asked a question the source had already answered.
    it "refuses an ASSUME that carries a TYPICALLY and is read by the exported rule (R5)" $ do
      Output code sout serr <- runL4 bin ["export", "yscript", fixtureDir </> "yscript-typically-assume.l4"]
      code `shouldNotBe` ExitSuccess
      shouldContain' "stderr" serr "`has capacity`: carries TYPICALLY TRUE"
      shouldContain' "stderr" serr "yscript has no default"
      -- all-or-nothing: no rules are written
      sout `shouldBe` ""

    it "refuses a section GIVEN that carries a TYPICALLY the same way" $ do
      Output code sout serr <- runL4 bin ["export", "yscript", fixtureDir </> "yscript-typically-section.l4"]
      code `shouldNotBe` ExitSuccess
      shouldContain' "stderr" serr "`has capacity`: carries TYPICALLY TRUE"
      sout `shouldBe` ""

    it "compiles the same module once the TYPICALLY is gone (the control)" $ do
      Output code sout _ <- runL4 bin ["export", "yscript", fixtureDir </> "yscript-typically-control.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("RULE" `isInfixOf`)

    it "does not refuse a TYPICALLY on a fact the exported rule never reads" $ do
      Output code sout _ <- runL4 bin ["export", "yscript", fixtureDir </> "yscript-typically-unread.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("RULE" `isInfixOf`)

    it "batches every offender into one refusal (R5), not first-error-wins" $ do
      Output code _ serr <- runL4 bin ["export", "yscript", fixtureDir </> "yscript-multiple-offenders.l4"]
      code `shouldNotBe` ExitSuccess
      shouldContain' "stderr" serr "NOT"
      shouldContain' "stderr" serr "not BOOLEAN"
