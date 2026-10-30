-- | Black-box tests for @l4 lint@ (SUBJECT-TO-NOTWITHSTANDING-SPEC.md §12.1,
-- ruling D2): the derivation lint that reads the override phrases a decision's
-- prose carries and checks them against the call graph.
--
-- The shapes of the text it reads, and each verdict of the call-graph half, are
-- pinned in @jl4-core/test/OverrideLintSpec.hs@. What only the binary can show
-- is the contract a reader of the output depends on: a finding names the file,
-- the line and the decision; a satisfied prose says nothing unless asked; and
-- the exit status is 0 for a lint that ran, whatever it found, until @--strict@.
module CliTest.Lint (spec, fixtures) where

import Data.List (isInfixOf)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import Test.Hspec

import CliTest.Common

subjectToMissing, subjectToWired, notwithstandingUnwired, notwithstandingDefeat, plainEnglish :: FilePath
subjectToMissing       = fixtureDir </> "lint-subject-to-missing.l4"
subjectToWired         = fixtureDir </> "lint-subject-to-wired.l4"
notwithstandingUnwired = fixtureDir </> "lint-notwithstanding-unwired.l4"
notwithstandingDefeat  = fixtureDir </> "lint-notwithstanding-defeat.l4"
plainEnglish           = fixtureDir </> "lint-plain-english.l4"

fixtures :: [FilePath]
fixtures = [subjectToMissing, subjectToWired, notwithstandingUnwired, notwithstandingDefeat, plainEnglish]

spec :: FilePath -> Spec
spec bin = do
  describe "l4 lint" $ do
    it "flags a \"Subject to section 6\" whose body calls no section 6 decision" $ do
      Output code sout _ <- runL4 bin ["lint", subjectToMissing]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` (("lint-subject-to-missing.l4:11: missing-conjunct: `s 8(3) — probate may be granted`") `isInfixOf`)
      sout `shouldSatisfy` ("says \"subject to section 6\" (read in @ref, text)" `isInfixOf`)
      sout `shouldSatisfy` ("but its body reaches none of: `s 6(1) — granted to more than 4 persons`" `isInfixOf`)
      sout `shouldSatisfy` ("findings: 1 missing-conjunct" `isInfixOf`)

    it "does not flag the same prose when the body calls the section 6 decision" $ do
      Output code sout _ <- runL4 bin ["lint", subjectToWired]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` (not . ("missing-conjunct:" `isInfixOf`))
      sout `shouldSatisfy` ("findings: none; set aside: 1 wired (direct call)" `isInfixOf`)

    it "lists what it set aside only with --all" $ do
      Output _ quiet _ <- runL4 bin ["lint", subjectToWired]
      Output _ loud _ <- runL4 bin ["lint", "--all", subjectToWired]
      quiet `shouldSatisfy` (not . ("wired (direct call): `s 8(3)" `isInfixOf`))
      loud `shouldSatisfy` ("lint-subject-to-wired.l4:11: wired (direct call): `s 8(3) — probate may be granted`" `isInfixOf`)

    it "flags a \"Notwithstanding section 7\" that no call joins to section 7" $ do
      Output code sout _ <- runL4 bin ["lint", notwithstandingUnwired]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("override-unwired: `s 9 — extensions may be granted`" `isInfixOf`)
      sout `shouldSatisfy` ("says \"notwithstanding section 7\"" `isInfixOf`)

    it "accepts the defeat idiom, where section 7 calls the prevailing section 9" $ do
      Output code sout _ <- runL4 bin ["lint", "--all", notwithstandingDefeat]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` (not . ("override-unwired:" `isInfixOf`))
      sout `shouldSatisfy` ("wired (the provision's decision calls this one): `s 9 — extensions may be granted`" `isInfixOf`)

    it "reports nothing at all for \"subject to\" and \"despite\" with no provision behind them" $ do
      Output code sout _ <- runL4 bin ["lint", "--all", plainEnglish]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("findings: none; set aside: none" `isInfixOf`)

    it "exits 1 on a finding only with --strict" $ do
      Output plain _ _ <- runL4 bin ["lint", subjectToMissing]
      Output strict _ _ <- runL4 bin ["lint", "--strict", subjectToMissing]
      plain `shouldBe` ExitSuccess
      strict `shouldBe` ExitFailure 1

    it "lints several files in one run and totals them" $ do
      Output code sout _ <- runL4 bin ["lint", subjectToMissing, subjectToWired]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("l4 lint: 2 files; findings: 1 missing-conjunct" `isInfixOf`)

    it "emits every mention as JSON with --json" $ do
      env <- jsonEnvelope bin ["lint", "--json", subjectToMissing]
      show env `shouldSatisfy` ("\"outcome\",String \"missing-conjunct\"" `isInfixOf`)
      show env `shouldSatisfy` ("\"finding\",Bool True" `isInfixOf`)

    it "fails on a file that does not typecheck" $
      expectFail bin ["lint", errorFixture]
