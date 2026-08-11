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

  -- The seam, at the level of the engine (DESIGN §25.3, §25.7). The verdict table here
  -- is the SAME table `lampsFor` implements in ladder-core — deliberately, because a
  -- wizard and a diagram that disagreed about a case would be lying to the same user.
  --
  --   scope ✗              → NotApplicable   (the rule never bit)
  --   scope ✓, req ✓       → Complies
  --   scope ✓, req ✗       → InBreach
  --   scope ✓, req ?       → Undetermined
  --   scope ?              → Undetermined    (even when the FUNCTION is settled)
  describe "BImplies — verdict, not truth value" do
    let scope = "scope" :: String
        req = "req"
        impl = BImplies (BVar scope) (BVar req)
        c = compileDecisionQuery [scope, req] impl
        run bs = queryDecision c Map.empty (Map.fromList bs)

    it "vacuous: the function is TRUE and the verdict is NotApplicable" do
      let r = run [(scope, False)]
      -- Both of these hold at once, and that is the entire problem in two lines: a
      -- caller reading `determined` sees the same TRUE it sees for a compliant case.
      r.determined `shouldBe` Just True
      r.verdict `shouldBe` NotApplicable
      r.support `shouldBe` Set.empty

    it "complies" do
      let r = run [(scope, True), (req, True)]
      r.determined `shouldBe` Just True
      r.verdict `shouldBe` Complies

    it "in breach" do
      let r = run [(scope, True), (req, False)]
      r.determined `shouldBe` Just False
      r.verdict `shouldBe` InBreach

    it "an unasked requirement is not a breach" do
      let r = run [(scope, True)]
      r.verdict `shouldBe` Undetermined
      r.support `shouldBe` Set.fromList [req]

    it "requirement met, scope unknown: the value short-circuits and the VERDICT does not" do
      -- The classical planner stops here: `NOT scope OR req` restricts to TRUE, support
      -- is empty, nothing left to ask. But we still do not know whether the rule reached
      -- this case — and N/A and compliance are different answers. So the interview goes
      -- on, and it goes on about the SCOPE.
      let r = run [(req, True)]
      r.determined `shouldBe` Just True
      r.verdict `shouldBe` Undetermined
      r.support `shouldBe` Set.fromList [scope]

    it "no seam, no vacuity: a plain function still reports Holds/Fails" do
      let plain = compileDecisionQuery [scope, req] (BOr [BNot (BVar scope), BVar req])
          -- Note this is the SAME boolean function as `impl` — same BDD, same
          -- `determined` for every binding. Only the shape differs, and only the shape
          -- can tell you what the TRUE means.
          r = queryDecision plain Map.empty (Map.fromList [(scope, False)])
      r.determined `shouldBe` Just True
      r.verdict `shouldBe` Holds
      r.support `shouldBe` Set.empty

    it "impact previews carry verdicts too, so a preview cannot lie either" do
      let r = run []
          scopeImpact = Map.lookup scope r.impact
      (fmap (.ifFalse.verdict) scopeImpact) `shouldBe` Just NotApplicable
      (fmap (.ifFalse.determined) scopeImpact) `shouldBe` Just (Just True)
      (fmap (.ifTrue.verdict) scopeImpact) `shouldBe` Just Undetermined

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
