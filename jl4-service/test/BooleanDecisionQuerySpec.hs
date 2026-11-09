module BooleanDecisionQuerySpec (spec) where

import L4.Decision.BooleanDecisionQuery
import Control.Monad (replicateM)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Test.Hspec
import qualified Test.Hspec.QuickCheck as Hspec
import qualified Test.QuickCheck as Q

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

  -- A refusing leaf (R7): a throw at force, never a value. The plan reads an
  -- expression that holds one as evaluation does, left to right, stopping as soon
  -- as the answer is known (Machine.connectiveLeft), so that the plan and
  -- @/evaluation@ give the same answer, in the order the rule is written.
  describe "BRefuse — the plan reaches a refusal where evaluation does" do
    let x = "x" :: String
        y = "y"
        r = "r"
        plan expr bs = queryDecision (compileDecisionQuery [x, y, r] expr) Map.empty (Map.fromList bs)

    it "x AND r: FALSE where x is, refused where x is TRUE" do
      let e = BAnd [BVar x, BRefuse r]
      (plan e [(x, False)]).verdict `shouldBe` Fails
      (plan e [(x, False)]).determined `shouldBe` Just False
      (plan e [(x, True)]).verdict `shouldBe` Refused
      (plan e [(x, True)]).determined `shouldBe` Nothing
      (plan e [(x, True)]).refusedAt `shouldBe` Set.fromList [r]
      (plan e [(x, True)]).support `shouldBe` Set.empty

    it "x AND r, nothing answered: x is the one question, and r is never asked" do
      let res = plan (BAnd [BVar x, BRefuse r]) []
      res.verdict `shouldBe` Undetermined
      res.support `shouldBe` Set.fromList [x]
      res.ranked `shouldBe` [x]

    it "r AND x: refused before x is read, whatever x is" do
      let e = BAnd [BRefuse r, BVar x]
      (plan e []).verdict `shouldBe` Refused
      (plan e [(x, False)]).verdict `shouldBe` Refused
      (plan e []).support `shouldBe` Set.empty

    it "x OR r: TRUE where x is, refused where x is FALSE" do
      let e = BOr [BVar x, BRefuse r]
      (plan e [(x, True)]).verdict `shouldBe` Holds
      (plan e [(x, False)]).verdict `shouldBe` Refused

    it "NOT r refuses" do
      (plan (BNot (BRefuse r)) []).verdict `shouldBe` Refused

    it "an answer for a refusing leaf changes nothing: evaluation takes none" do
      let e = BAnd [BVar x, BRefuse r]
      (plan e [(x, True), (r, True)]).verdict `shouldBe` Refused
      (plan e [(x, True), (r, False)]).verdict `shouldBe` Refused

    it "the impact of answering x says which answer leads to the refusal" do
      let res = plan (BAnd [BVar x, BRefuse r]) []
      fmap (.ifTrue.verdict) (Map.lookup x res.impact) `shouldBe` Just Refused
      fmap (.ifFalse.verdict) (Map.lookup x res.impact) `shouldBe` Just Fails

    it "a seam: a scope that refuses is a refusal; one that is FALSE is not applicable" do
      let e = BImplies (BAnd [BVar x, BRefuse r]) (BVar y)
      (plan e [(x, False)]).verdict `shouldBe` NotApplicable
      (plan e [(x, True)]).verdict `shouldBe` Refused
      (plan e [(x, True), (y, True)]).verdict `shouldBe` Refused

    it "a seam: a requirement that refuses is a refusal once the scope holds" do
      let e = BImplies (BVar x) (BOr [BVar y, BRefuse r])
      (plan e [(x, False)]).verdict `shouldBe` NotApplicable
      (plan e [(x, True), (y, True)]).verdict `shouldBe` Complies
      (plan e [(x, True), (y, False)]).verdict `shouldBe` Refused

    it "a seam whose scope is still open can be sure to refuse: nothing is asked" do
      let r2 = "r2"
          e = BImplies (BOr [BVar x, BRefuse r]) (BRefuse r2)
          res = queryDecision (compileDecisionQuery [x, r, r2] e) Map.empty Map.empty
      res.verdict `shouldBe` Refused
      res.support `shouldBe` Set.empty
      res.refusedAt `shouldBe` Set.fromList [r, r2]

    it "which refusal is reached depends on the answers" do
      let r2 = "r2"
          e = BOr [BAnd [BVar x, BRefuse r], BAnd [BNot (BVar x), BRefuse r2]]
          res bs = queryDecision (compileDecisionQuery [x, r, r2] e) Map.empty (Map.fromList bs)
      (res []).verdict `shouldBe` Refused
      (res []).refusedAt `shouldBe` Set.fromList [r, r2]
      (res [(x, True)]).refusedAt `shouldBe` Set.fromList [r]
      (res [(x, False)]).refusedAt `shouldBe` Set.fromList [r2]

    -- Against a three-valued evaluator written straight from the evaluator's
    -- rules, on every complete set of answers: the plan's outcome for each is
    -- evaluation's. And with no refusing leaf in it, an expression is planned
    -- exactly as it always was.
    Hspec.prop "agrees with left-to-right evaluation on every complete set of answers" $
      Q.forAll genExpr \e ->
        let vars = ["a", "b", "c"] :: [String]
            c = compileDecisionQuery (vars <> ["r1", "r2"]) e
         in Q.conjoin
              [ Q.counterexample (show (e, bs)) $
                  let res = queryDecision c Map.empty (Map.fromList bs)
                   in (res.verdict, res.determined, res.refusedAt) Q.=== outcomeOfEval (evalLazy (Map.fromList bs) e)
              | vals <- replicateM (length vars) [False, True]
              , let bs = zip vars vals
              ]

    -- And where the plan settles a case before every question is answered, every
    -- way of answering the rest agrees: the same truth value, or a refusal at one
    -- of the leaves the plan names, each of which some way of answering reaches.
    Hspec.prop "where the plan settles a case early, every completion agrees" $
      Q.forAll genExpr \e ->
        let vars = ["a", "b", "c"] :: [String]
            c = compileDecisionQuery (vars <> ["r1", "r2"]) e
            completions bs =
              [ Map.fromList (bs <> zip rest vals)
              | let rest = [v | v <- vars, v `notElem` map fst bs]
              , vals <- replicateM (length rest) [False, True]
              ]
         in Q.conjoin
              [ Q.counterexample (show (e, bs, res.determined, res.refusedAt)) $
                  case res.determined of
                    Just b -> Q.conjoin [evalLazy env e Q.=== (if b then OTrue else OFalse) | env <- completions bs]
                    Nothing ->
                      let reached = [evalLazy env e | env <- completions bs]
                       in Set.fromList [v | ORefused v <- reached] Q.=== res.refusedAt
                            Q..&&. length [() | ORefused _ <- reached] Q.=== length reached
              | answers <- traverse (\v -> [Nothing, Just (v, False), Just (v, True)]) vars
              , let bs = [a | Just a <- answers]
                    res = queryDecision c Map.empty (Map.fromList bs)
              , res.determined /= Nothing || not (Set.null res.refusedAt)
              ]

data Outcome = OTrue | OFalse | ORefused String
  deriving stock (Eq, Show)

-- | Evaluation's rules: left to right, stopping as soon as the answer is known.
evalLazy :: Map.Map String Bool -> BoolExpr String -> Outcome
evalLazy env = \case
  BTrue -> OTrue
  BFalse -> OFalse
  BVar v -> if Map.findWithDefault False v env then OTrue else OFalse
  BRefuse v -> ORefused v
  BNot e -> case evalLazy env e of
    OTrue -> OFalse
    OFalse -> OTrue
    o -> o
  BAnd es -> foldr (\e k -> case evalLazy env e of OTrue -> k; o -> o) OTrue es
  BOr es -> foldr (\e k -> case evalLazy env e of OFalse -> k; o -> o) OFalse es
  BImplies p q -> case evalLazy env p of
    OTrue -> evalLazy env q
    OFalse -> OTrue
    o -> o

outcomeOfEval :: Outcome -> (Verdict, Maybe Bool, Set.Set String)
outcomeOfEval = \case
  OTrue -> (Holds, Just True, Set.empty)
  OFalse -> (Fails, Just False, Set.empty)
  ORefused v -> (Refused, Nothing, Set.singleton v)

-- | Expressions over three variables and two refusing leaves, with at least one
-- refusing leaf (so that they are planned lazily), and no top-level seam (whose
-- verdict is not a truth value).
genExpr :: Q.Gen (BoolExpr String)
genExpr = (\e -> BOr [BAnd [BFalse, BRefuse "r1"], e]) <$> Q.sized (go . min 4)
 where
  go :: Int -> Q.Gen (BoolExpr String)
  go 0 = Q.elements [BTrue, BFalse, BVar "a", BVar "b", BVar "c", BRefuse "r1", BRefuse "r2"]
  go n =
    Q.oneof
      [ go 0
      , BNot <$> go (n - 1)
      , BAnd <$> Q.listOf1 (go (n `div` 2)) `suchThatShort` 3
      , BOr <$> Q.listOf1 (go (n `div` 2)) `suchThatShort` 3
      , BImplies <$> go (n `div` 2) <*> go (n `div` 2)
      ]
  suchThatShort g k = take k <$> g
