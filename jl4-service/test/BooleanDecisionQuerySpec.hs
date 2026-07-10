module BooleanDecisionQuerySpec (spec) where

import L4.Decision.BooleanDecisionQuery
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Test.Hspec

spec :: Spec
spec = do
  describe "compileDecisionQuery" do
    it "supports absorption: x ∨ (x ∧ y) has support {x}" do
      let expr = BOr [BVar ("x" :: String), BAnd [BVar "x", BVar "y"]]
          c = compileDecisionQuery ["x", "y"] expr
          r = queryDecision c Map.empty Map.empty
      r.determined `shouldBe` Nothing
      r.support `shouldBe` Set.fromList ["x"]
      r.ranked `shouldBe` ["x"]

    it "restriction makes support shrink: (x ∨ y) with x=true is determined" do
      let expr = BOr [BVar ("x" :: String), BVar "y"]
          c = compileDecisionQuery ["x", "y"] expr
          rTrue = queryDecision c Map.empty (Map.fromList [("x", True)])
          rFalse = queryDecision c Map.empty (Map.fromList [("x", False)])
      rTrue.determined `shouldBe` Just True
      rTrue.support `shouldBe` Set.empty
      rFalse.determined `shouldBe` Nothing
      rFalse.support `shouldBe` Set.fromList ["y"]

  -- Shared cross-runtime parity fixture (question-ordering spec §7). The SAME
  -- structure, var order, priors and expected scores are asserted in the TS
  -- suite (ts-shared/boolean-analysis/src/tests/decision-query.test.ts,
  -- "TYPICALLY priors — cross-runtime parity fixture"). If the two hand-rolled
  -- ROBDDs ever drift, one of these tests breaks.
  describe "TYPICALLY priors — cross-runtime parity fixture" do
    -- `may purchase alcohol` IF capacity AND (ofage OR parental OR spousal)
    let capacity = 1 :: Int
        ofage = 2 :: Int
        parental = 3 :: Int
        spousal = 4 :: Int
        expr = BAnd [BVar capacity, BOr [BVar ofage, BVar parental, BVar spousal]]
        order = [capacity, ofage, parental, spousal]
        c = compileDecisionQuery order expr
        -- capacity/ofage TYPICALLY TRUE -> 0.9 ; parental/spousal TYPICALLY FALSE -> 0.1
        priorsV2 = Map.fromList [(capacity, 0.9), (ofage, 0.9), (parental, 0.1), (spousal, 0.1)]
        approx expected actual = abs (expected - actual) < 1e-3
        scoreOf r v = Map.findWithDefault (-1) v r.scores

    it "prior-free: OR siblings tie, capacity leads" do
      let r = queryDecision c Map.empty Map.empty
      r.ranked `shouldBe` [capacity, ofage, parental, spousal]
      scoreOf r capacity `shouldSatisfy` approx 0.7169
      scoreOf r ofage `shouldSatisfy` approx 0.0115
      scoreOf r parental `shouldSatisfy` approx 0.0115
      scoreOf r spousal `shouldSatisfy` approx 0.0115

    it "v2 priors: presumed-FALSE OR atoms sink to the end" do
      let r = queryDecision c priorsV2 Map.empty
      r.ranked `shouldBe` [capacity, ofage, parental, spousal]
      scoreOf r capacity `shouldSatisfy` approx 0.2992
      scoreOf r ofage `shouldSatisfy` approx 0.1762
      scoreOf r parental `shouldSatisfy` approx 0.0034
      scoreOf r spousal `shouldSatisfy` approx 0.0034
      -- the informative OR atom outranks its presumed-FALSE siblings
      scoreOf r ofage `shouldSatisfy` (> scoreOf r parental)
