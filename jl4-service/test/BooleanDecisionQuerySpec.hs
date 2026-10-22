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
          r = queryDecision c Map.empty
      r.determined `shouldBe` Nothing
      r.support `shouldBe` Set.fromList ["x"]
      r.ranked `shouldBe` ["x"]

    it "restriction makes support shrink: (x ∨ y) with x=true is determined" do
      let expr = BOr [BVar ("x" :: String), BVar "y"]
          c = compileDecisionQuery ["x", "y"] expr
          rTrue = queryDecision c (Map.fromList [("x", True)])
          rFalse = queryDecision c (Map.fromList [("x", False)])
      rTrue.determined `shouldBe` Just True
      rTrue.support `shouldBe` Set.empty
      rFalse.determined `shouldBe` Nothing
      rFalse.support `shouldBe` Set.fromList ["y"]

  -- A refusing leaf (R7): a throw at force, never a value. The plan reads an
  -- expression that holds one as evaluation does, left to right, stopping as soon
  -- as the answer is known (Machine.connectiveLeft), so that the plan and
  -- @/evaluation@ give the same answer, in the order the rule is written.
  describe "BRefuse: the plan reaches a refusal where evaluation does" do
    let x = "x" :: String
        y = "y"
        r = "r"
        plan expr bs = queryDecision (compileDecisionQuery [x, y, r] expr) (Map.fromList bs)

    it "x AND r: FALSE where x is, refused where x is TRUE" do
      let e = BAnd [BVar x, BRefuse r]
      (plan e [(x, False)]).determined `shouldBe` Just False
      (plan e [(x, False)]).refusedAt `shouldBe` Set.empty
      (plan e [(x, True)]).determined `shouldBe` Nothing
      (plan e [(x, True)]).refusedAt `shouldBe` Set.fromList [r]
      (plan e [(x, True)]).support `shouldBe` Set.empty

    it "x AND r, nothing answered: x is the one question, and r is never asked" do
      let res = plan (BAnd [BVar x, BRefuse r]) []
      res.determined `shouldBe` Nothing
      res.refusedAt `shouldBe` Set.empty
      res.support `shouldBe` Set.fromList [x]
      res.ranked `shouldBe` [x]

    it "r AND x: refused before x is read, whatever x is" do
      let e = BAnd [BRefuse r, BVar x]
      (plan e []).refusedAt `shouldBe` Set.fromList [r]
      (plan e [(x, False)]).refusedAt `shouldBe` Set.fromList [r]
      (plan e []).support `shouldBe` Set.empty

    it "x OR r: TRUE where x is, refused where x is FALSE" do
      let e = BOr [BVar x, BRefuse r]
      (plan e [(x, True)]).determined `shouldBe` Just True
      (plan e [(x, False)]).refusedAt `shouldBe` Set.fromList [r]

    it "NOT r refuses" do
      (plan (BNot (BRefuse r)) []).refusedAt `shouldBe` Set.fromList [r]

    it "an answer for a refusing leaf changes nothing: evaluation takes none" do
      let e = BAnd [BVar x, BRefuse r]
      (plan e [(x, True), (r, True)]).refusedAt `shouldBe` Set.fromList [r]
      (plan e [(x, True), (r, False)]).refusedAt `shouldBe` Set.fromList [r]

    it "the impact of answering x says which answer leads to the refusal" do
      let res = plan (BAnd [BVar x, BRefuse r]) []
      fmap (.ifTrue.refusedAt) (Map.lookup x res.impact) `shouldBe` Just (Set.fromList [r])
      fmap (.ifFalse.determined) (Map.lookup x res.impact) `shouldBe` Just (Just False)

    it "which refusal is reached depends on the answers" do
      let r2 = "r2"
          e = BOr [BAnd [BVar x, BRefuse r], BAnd [BNot (BVar x), BRefuse r2]]
          res bs = queryDecision (compileDecisionQuery [x, r, r2] e) (Map.fromList bs)
      (res []).refusedAt `shouldBe` Set.fromList [r, r2]
      (res [(x, True)]).refusedAt `shouldBe` Set.fromList [r]
      (res [(x, False)]).refusedAt `shouldBe` Set.fromList [r2]

    it "an expression with no refusing leaf is planned as it always was" do
      let e = BOr [BVar x, BAnd [BVar y, BNot (BVar x)]]
          c = compileDecisionQuery [x, y] e
      (queryDecision c Map.empty).refusedAt `shouldBe` Set.empty
      (queryDecision c (Map.fromList [(x, False)])).support `shouldBe` Set.fromList [y]

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
                  let res = queryDecision c (Map.fromList bs)
                   in (res.determined, res.refusedAt) Q.=== outcomeOfEval (evalLazy (Map.fromList bs) e)
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
                    res = queryDecision c (Map.fromList bs)
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

outcomeOfEval :: Outcome -> (Maybe Bool, Set.Set String)
outcomeOfEval = \case
  OTrue -> (Just True, Set.empty)
  OFalse -> (Just False, Set.empty)
  ORefused v -> (Nothing, Set.singleton v)

-- | Expressions over three variables and two refusing leaves, with at least one
-- refusing leaf (so that they are planned lazily).
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
      ]
  suchThatShort g k = take k <$> g
