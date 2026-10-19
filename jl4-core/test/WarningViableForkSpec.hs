{-# LANGUAGE OverloadedStrings #-}

-- | A candidate that succeeds with only a warning is a success.
--
-- The checker forks over the candidates for a name or for an application, and
-- decides what to do with the branches it did not take by counting the
-- successes. 'prune', 'softprune' and 'orElse' have judged a candidate by its
-- severity since a warning must not influence name resolution
-- ('L4.TypeCheck.Types.viableCandidate'); 'forkWithLazyFallback' and
-- 'orElseKeepAll' still counted only the candidates that carried no
-- diagnostic at all. A CONSIDER that does not cover every constructor, or
-- covers one twice, carries a warning, so each fork it sat under kept its
-- expensive fallback branch, and a chain of n operands one of which was such
-- a CONSIDER cost 2^n (an OR of 20 took 66 s to check, against 0.7 s with an
-- exhaustive CONSIDER); and in one shape the success was set aside for the
-- fallback altogether, and a function and a constructor of one name were
-- reported as ambiguous.
module WarningViableForkSpec (spec) where

import Control.Exception (AllocationLimitExceeded (..), evaluate, finally, try)
import Control.Monad (forM_, void)
import Data.Int (Int64)
import Data.List (isInfixOf, sort)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import System.CPUTime (getCPUTime)
import System.Mem (disableAllocationLimit, enableAllocationLimit, getAllocationCounter, setAllocationCounter)
import System.Timeout (timeout)
import Test.Hspec

import Base (Uri (..), modify', toNormalizedUri)
import L4.API.VirtualFS (TypeCheckWithDepsResult (..), checkWithImports, emptyVFS)
import L4.Annotation (emptyAnno)
import L4.Syntax (Expr (..), Lit (..), Name (MkName), RawName (NormalName), Resolved (Def), Type' (..), Unique (MkUnique), rawName, rawNameToText)
import L4.TypeCheck (headKey, initialCheckEnv, initialCheckState, quietly, runWith, settleOneClause, speculatively)
import L4.TypeCheck.With (With)
import L4.TypeCheck.Types
  ( Check, CheckError (..), CheckState (constBodies, plural), CheckErrorWithContext (..)
  , CheckWarning (..), Severity (..)
  , addError, addWarning, bindInfVar, choose, forkWithLazyFallback, fresh, newUnique, orElse, outcomeWeight, prune
  , recordSectionPath, runCheck, severity, softprune, softpruneAlike, viableCandidate
  )

spec :: Spec
spec = describe "A success that carries only a warning" $ do
  describe "is not set aside for the fallback of a fork" $ do
    -- A function and a constructor of one name (the constructor of a record
    -- with exactly one LIST field, which takes its elements as a list), called
    -- with two arguments, one of which raises a warning, in a rule with no
    -- GIVETH, so that nothing says what type the call has. The application is
    -- checked directly and, failing that, with the arguments collected into a
    -- list ('orElseKeepAll'); the direct reading succeeds, with a warning, and
    -- was thrown away for the other, and the name reported as ambiguous.
    it "checks a function named like a one-LIST-field constructor, with a partial CONSIDER as an argument" $ do
      r <- warnings (bagSource "WHEN Red THEN 1, WHEN Green THEN 2")
      r `shouldBe` Right ["missing"]

    it "checks it with a redundant arm in the CONSIDER, and reports the arm once" $ do
      r <- warnings (bagSource "WHEN Red THEN 1, WHEN Green THEN 2, WHEN Blue THEN 2, WHEN Red THEN 2")
      r `shouldBe` Right ["redundant"]

    it "checks it with an exhaustive CONSIDER, and reports nothing (the control)" $ do
      r <- warnings (bagSource "WHEN Red THEN 1, WHEN Green THEN 2, WHEN Blue THEN 2")
      r `shouldBe` Right []

  describe "keeps the warning, once" $ do
    -- The fallback that is skipped when one branch succeeds produces no
    -- diagnostic of its own that a user sees, so skipping it must leave the
    -- warning of the branch that was taken, neither lost nor repeated.
    it "reports a partial CONSIDER at the end of an OR chain once" $ do
      r <- warnings (chainSource "OR" partialArms 10)
      r `shouldBe` Right ["missing"]

    it "reports a partial CONSIDER at the end of an AND chain once" $ do
      r <- warnings (chainSource "AND" partialArms 10)
      r `shouldBe` Right ["missing"]

    it "reports a redundant arm at the end of an OR chain once" $ do
      r <- warnings (chainSource "OR" redundantArms 10)
      r `shouldBe` Right ["redundant"]

  describe "does not make a chain of operands exponential" $ do
    -- Timed by the ratio of the check of 20 operands to the check of 10, not
    -- by a bound in seconds, so that a slow machine does not fail it; and in
    -- CPU time, so that time spent waiting for a busy machine is not counted.
    -- Twice the operands take about as long again when the cost is linear, and
    -- a thousand times as long when it doubles with each operand; the guard
    -- fails above 'growthLimit'. A check that has not finished in 120 s fails
    -- the test, rather than the suite waiting for it.
    it "checks an OR of 20 operands ending in a partial CONSIDER in time linear in the operands" $
      chainGrowsLinearly "OR" partialArms

    it "checks an AND of 20 operands ending in a partial CONSIDER in time linear in the operands" $
      chainGrowsLinearly "AND" partialArms

    it "checks an OR of 20 operands ending in a CONSIDER with a redundant arm in time linear in the operands" $
      chainGrowsLinearly "OR" redundantArms

    it "checks an OR of 20 operands ending in an exhaustive CONSIDER in time linear in the operands (the control)" $
      chainGrowsLinearly "OR" exhaustiveArms

  describe "a name with two meanings that both check" $ do
    -- Resolution keeps every meaning that checks, so that something later can
    -- choose between them, and each one ran the rest of the enclosing
    -- expression: n uses of such a name cost 2^n, and every one of those
    -- paths was thrown away, because the module is then rejected as ambiguous
    -- and only the last outcome is shown. Outcomes that leave the substitution
    -- as it was, and so cannot be told apart by anything that follows, are
    -- now run as one ('L4.TypeCheck.Types.mergeAlike'), whether either carries
    -- a warning or neither does.
    forM_ meanings \ (label, m) -> describe label do
      it "is reported once for each use, as it was" $ do
        (kinds, _) <- checkedWithin 3 (forkSource m 3)
        sort kinds `shouldBe` sort (expectedKinds m 3)

      it "is reported the same however many uses there are" $ do
        (kinds, _) <- checkedWithin 12 (forkSource m 12)
        sort kinds `shouldBe` sort (expectedKinds m 12)

      it "is checked in an amount of work linear in the uses" $ do
        -- Counted in the bytes this thread allocates, which nothing else
        -- running changes. A check that allocates more than 'allocationLimit'
        -- is stopped, so that the cost of 2^n is a failure and not a hang or
        -- an exhausted machine: on the checker that kept every outcome, 10
        -- uses are stopped, and 5 take 1 s.
        (_, small) <- checkedWithin 10 (forkSource m 10)
        (_, large) <- checkedWithin 20 (forkSource m 20)
        fromIntegral large / fromIntegral small `shouldSatisfy` (< growthLimit)

  describe "a name with two meanings where the checker treats the body as local" $ do
    -- A WHERE constant is recorded for the reader of deontic actions, and the
    -- clauses of a group after the first are compiled into a local definition,
    -- so a merge there has to leave alone what that reader can see. It still
    -- has to merge what it cannot: the chain is as cheap here as at the top.
    forM_ placements \ (placeLabel, place) -> describe placeLabel do
      forM_ meanings \ (label, m) -> describe label do
        it "is reported once for each use" $ do
          (kinds, _) <- checkedWithin 12 (placedSource place m 12)
          sort kinds `shouldBe` sort (expectedKinds m 12)

        it "is checked in an amount of work linear in the uses" $ do
          (_, small) <- checkedWithin 10 (placedSource place m 10)
          (_, large) <- checkedWithin 20 (placedSource place m 20)
          fromIntegral large / fromIntegral small `shouldSatisfy` (< growthLimit)

  describe "a plural outcome" $ do
    -- The search itself, without the language: outcomes that nothing after
    -- them can tell apart are merged into one that counts as two.
    let valueKey a = (a :: Int)
        warned = addWarning (PatternMatchesMissing [] False)
        failed = addError InternalAmbiguityError >> pure (0 :: Int)
        -- Two outcomes with the same value, one with a warning, and a failure
        -- after them: what a fork with two viable outcomes ends with.
        twoAlike = choose [pure (1 :: Int), warned >> pure 1, failed]

    it "is made of outcomes with the same value and the same substitution, one of them with a warning" $ do
      weightsOf (softpruneAlike valueKey twoAlike) `shouldBe` [2, 0]

    it "is not made by softprune, which keeps both" $ do
      weightsOf (softprune twoAlike) `shouldBe` [1, 1, 0]

    it "is not made of outcomes with different values" $ do
      weightsOf (softpruneAlike valueKey (choose [pure 1, pure 2, failed])) `shouldBe` [1, 1, 0]

    it "runs failures that nothing after them can tell apart as the last of them" $ do
      -- A failure is counted by nothing, and the last outcome is the one shown.
      let failing n = addError InternalAmbiguityError >> pure (n :: Int)
          valuesOf m = [ x | (w, _) <- outcomesOf m, let (_, x) = runWith w ]
      -- (two viable outcomes: with one, softprune keeps it and no failure)
      valuesOf (softpruneAlike (const ()) (choose [pure 1, pure 1, failing 7, failing 8])) `shouldBe` [1, 8]
      -- and failures with different values are not alike
      valuesOf (softpruneAlike valueKey (choose [pure 1, pure 1, failing 7, failing 8])) `shouldBe` [1, 7, 8]

    it "shows the last of failures that look alike and say different things, as it did" $ do
      -- Two failures that nothing after them can tell apart, with different
      -- messages: run as one, and the one is the last, which is the one prune
      -- shows. The first one's message was never shown either.
      let failing msg = addError (TypicallyRequiresType (MkName emptyAnno (NormalName msg))) >> pure (0 :: Int)
          apart = choose [pure 1, pure 1, failing "failure-one", failing "failure-two"]
          errorsOf (w, _) = show (fst (runWith w))
          surfaced m = map errorsOf (outcomesOf (prune m))
      length (outcomesOf (softpruneAlike (const ()) apart)) `shouldBe` 2
      surfaced (softpruneAlike (const ()) apart) `shouldBe` surfaced apart
      surfaced apart `shouldSatisfy` all ("failure-two" `isInfixOf`)
      surfaced apart `shouldSatisfy` all (not . ("failure-one" `isInfixOf`))

    it "is not made when the last outcome is viable, which prune would then show" $ do
      weightsOf (softpruneAlike valueKey (choose [pure 1, pure (1 :: Int)])) `shouldBe` [1, 1]

    it "counts as two for prune, which reads two viable outcomes as an ambiguity" $ do
      -- Merged, [plural, failure] is read as [viable, viable, failure]: two
      -- viable outcomes, so not one answer, and the last outcome is shown.
      case outcomesOf (prune (softpruneAlike valueKey twoAlike)) of
        [(w, _)] -> viableCandidate w `shouldBe` False
        other -> expectationFailure ("expected one outcome, got " <> show (length other))
      -- the control: a plural outcome alone, with nothing after it, is the same two
      case outcomesOf (prune (orElse (softpruneAlike valueKey twoAlike) (pure 0))) of
        [(w, _)] -> do
          viableCandidate w `shouldBe` False
          show (fst (runWith w)) `shouldContain` "InternalAmbiguityError"
        other -> expectationFailure ("expected one outcome, got " <> show (length other))

    it "counts as two for the fork, which then keeps its fallback" $ do
      -- One success keeps no fallback; a plural one is two.
      let fallback = addError InternalAmbiguityError >> pure (0 :: Int)
      length (outcomesOf (forkWithLazyFallback False [pure (1 :: Int)] fallback pure)) `shouldBe` 1
      length (outcomesOf (forkWithLazyFallback False [softpruneAlike valueKey (choose [pure 1, warned >> pure 1, failed])] fallback pure)) `shouldBe` 3

    it "is made of outcomes that bound the same variable the same way" $ do
      let bound a b = do
            v <- fresh (NormalName "v")
            x <- fresh (NormalName "x")
            y <- fresh (NormalName "y")
            let i = varOf v
            softpruneAlike valueKey $ choose
              [ bindInfVar i (pick a x y) >> pure 1
              , bindInfVar i (pick b x y) >> warned >> pure 1
              , failed
              ]
      weightsOf (bound 'x' 'x') `shouldBe` [2, 0]
      weightsOf (bound 'x' 'y') `shouldBe` [1, 1, 0]

    it "is not made of outcomes that bound a variable to a variable they made" $ do
      -- Nothing says the two made the same one.
      let made = do
            v <- fresh (NormalName "v")
            let i = varOf v
            softpruneAlike valueKey $ choose
              [ fresh (NormalName "w") >>= bindInfVar i >> pure 1
              , fresh (NormalName "w") >>= bindInfVar i >> pure 1
              , failed
              ]
      weightsOf made `shouldBe` [1, 1, 0]

    it "is not made of outcomes that recorded a body, which a later reader follows by name" $ do
      -- The body of a nullary definition is recorded in 'constBodies' and read
      -- back by name; two outcomes that each recorded one leave the map the
      -- same size and cannot be told apart by that.
      let records n = do
            u <- newUnique
            modify' (\ s -> s { constBodies = Map.insert u (Lit emptyAnno (NumericLit emptyAnno n)) s.constBodies })
            pure (1 :: Int)
      weightsOf (softpruneAlike valueKey (choose [records 1, records 1, failed])) `shouldBe` [1, 1, 0]
      weightsOf (softpruneAlike valueKey (choose [records 1, records 2, failed])) `shouldBe` [1, 1, 0]
      -- the control: with nothing recorded, the same shape merges
      weightsOf (softpruneAlike valueKey (choose [pure 1, pure 1, failed])) `shouldBe` [2, 0]

    it "is not made of outcomes that registered a name in a section, whose paths a later lookup reads" $ do
      let registers = do
            u <- newUnique
            recordSectionPath ["a" :| []] [u]
            pure (1 :: Int)
      weightsOf (softpruneAlike valueKey (choose [registers, registers, failed])) `shouldBe` [1, 1, 0]

    it "is not made of a viable outcome and a failure that look alike" $ do
      let failing = addError InternalAmbiguityError >> pure (1 :: Int)
      weightsOf (softpruneAlike valueKey (choose [pure 1, pure 1, failing])) `shouldBe` [2, 0]

    it "is made of no outcome when a prune has to return one, so the flag never reaches the next declaration" $ do
      -- A plural outcome is read as the two it stands for, and when no failure
      -- follows, prune returns it marked as the ambiguity. Its state goes on
      -- to the next declaration, and must not carry the flag there.
      let plurally = modify' (\ s -> s { plural = True }) >> pure (1 :: Int)
      weightsOf plurally `shouldBe` [2]
      case outcomesOf (prune plurally) of
        [(w, st)] -> do
          viableCandidate w `shouldBe` False
          st.plural `shouldBe` False
        other -> expectationFailure ("expected one outcome, got " <> show (length other))

  describe "the key of a value" $ do
    -- What a reader of the body of a nullary definition can tell values apart
    -- by: 'L4.TypeCheck.headKey' is made of what it reads, and nothing else.
    let uri = toNormalizedUri (Uri "file:///head-key-spec")
        name n = Def (MkUnique 'c' n uri) (MkName emptyAnno (NormalName "thing"))
        bare n = App emptyAnno (name n) []
        applied f args = App emptyAnno (name f) args
        number n = Lit emptyAnno (NumericLit emptyAnno n)

    it "tells two names apart by what they name, which the reader follows" $ do
      headKey (bare 1) `shouldNotBe` headKey (bare 2)
      headKey (bare 1) `shouldBe` headKey (bare 1)

    it "tells two applications apart by the head of an argument, which the reader looks at" $ do
      headKey (applied 9 [bare 1, number 1]) `shouldNotBe` headKey (applied 9 [bare 2, number 1])
      headKey (applied 9 [number 1, bare 1]) `shouldNotBe` headKey (applied 9 [bare 1, number 1])

    it "does not tell apart what the reader does not look at" $ do
      -- not the function applied, not an argument that is not a name
      headKey (applied 9 [bare 1, number 1]) `shouldBe` headKey (applied 8 [bare 1, number 2])
      headKey (Or emptyAnno (bare 1) (bare 2)) `shouldBe` headKey (Or emptyAnno (bare 2) (bare 1))

    it "keeps a literal apart from anything else" $ do
      headKey (number 1) `shouldBe` headKey (number 2)
      headKey (number 1) `shouldNotBe` headKey (Or emptyAnno (bare 1) (bare 2))

  describe "a plural outcome through the combinators that put the state back" $ do
    -- If a combinator restored the state it was started in, the flag would drop,
    -- a count of two would read as one, and the module would silently take
    -- one meaning of a name that has two. Each of them keeps it.
    let valueKey a = (a :: Int)
        warned = addWarning (PatternMatchesMissing [] False)
        failed = addError InternalAmbiguityError >> pure (0 :: Int)
        twoAlike = choose [pure (1 :: Int), warned >> pure 1, failed]
        merged = softpruneAlike valueKey twoAlike
        ambiguous m = case outcomesOf (prune m) of
          [(w, _)] -> not (viableCandidate w) && "InternalAmbiguityError" `isInfixOfShown` fst (runWith w)
          _        -> False
        isInfixOfShown needle xs = needle `Text.isInfixOf` Text.pack (show xs)

    it "survives speculatively, which keeps what a check reports and drops what it learned" $ do
      weightsOf (speculatively merged) `shouldBe` [2, 0]
      -- the control: unmerged, speculatively reports two outcomes, as it did
      weightsOf (speculatively twoAlike) `shouldBe` [1, 1, 0]
      ambiguous (speculatively merged >> pure (0 :: Int)) `shouldBe` True

    it "survives settleOneClause, which drops some warnings" $ do
      weightsOf (settleOneClause ((\ x -> (x, True)) <$> merged)) `shouldBe` [2, 0]
      ambiguous (settleOneClause ((\ x -> (x, True)) <$> merged) >> pure (0 :: Int)) `shouldBe` True

    it "is read by quietly as the first of the two it stands for, as quietly read the first of two" $ do
      -- quietly takes one viable outcome and returns only that, so there is no count to keep.
      let values m = [ x | (w, _) <- outcomesOf m, (_, Just x) <- [runWith w] ]
      values (quietly merged) `shouldBe` [1]
      values (quietly twoAlike) `shouldBe` [1]
      weightsOf (quietly merged) `shouldBe` weightsOf (quietly twoAlike)

  describe "counting a plural outcome as two" $ do
    -- Replacing the group by the fallback alone, "reporting it locally", leaves
    -- the same last outcome, and was rejected: it changes the COUNT. If another
    -- branch has exactly one viable outcome, the total is two or more, and the
    -- module is ambiguous; without the pair it would be one, and the module
    -- would pick that branch.
    let valueKey a = (a :: Int)
        warned = addWarning (PatternMatchesMissing [] False)
        redundant = addWarning (PatternMatchRedundant [])
        failed = addError InternalAmbiguityError >> pure (0 :: Int)
        errorsOf (w, _) = show (fst (runWith w))

    it "keeps a module ambiguous when an alike pair sits beside one other viable outcome" $ do
      -- a fork with three viable outcomes ends with its fallback
      let pair = softpruneAlike valueKey (choose [pure (1 :: Int), warned >> pure 1, failed])
      case outcomesOf (prune (choose [pair, pure 2, failed])) of
        [(w, _)] -> viableCandidate w `shouldBe` False
        other -> expectationFailure ("expected one outcome, got " <> show (length other))
      -- the control: with no pair, the other branch alone is the answer
      case outcomesOf (prune (choose [pure (2 :: Int), failed])) of
        [(w, _)] -> viableCandidate w `shouldBe` True
        other -> expectationFailure ("expected one outcome, got " <> show (length other))
      -- and the rejected alternative, the pair dropped, would have been that answer
      case outcomesOf (prune (choose [failed, pure 2, failed])) of
        [(w, _)] -> viableCandidate w `shouldBe` True
        other -> expectationFailure ("expected one outcome, got " <> show (length other))

    it "keeps the ambiguity on the first viable outcome, as it was" $ do
      -- Two outcomes with different warnings and nothing after them (what
      -- 'orElse' makes of a fork): the error is attached to the first,
      -- whether they are merged or not.
      let apart = choose [warned >> pure (1 :: Int), redundant >> pure 1, failed]
          surfaced m = map errorsOf (outcomesOf (prune (orElse m (pure 0))))
      surfaced (softpruneAlike valueKey apart) `shouldBe` surfaced apart
      surfaced (softpruneAlike valueKey apart) `shouldSatisfy` all (not . null)
      surfaced (softpruneAlike valueKey apart) `shouldSatisfy` all ("PatternMatchesMissing" `isInfixOf`)

    it "shows the last outcome when a failure follows, as it did" $ do
      let withFailure = choose [warned >> pure (1 :: Int), redundant >> pure 1, addError InternalAmbiguityError >> pure 3]
          surfaced m = map errorsOf (outcomesOf (prune m))
      surfaced (softpruneAlike valueKey withFailure) `shouldBe` surfaced withFailure

  describe "a name with two meanings in a group of clauses" $ do
    -- The CONSIDER a clause group compiles to is checked under 'quietly',
    -- 'speculatively' and 'settleOneClause'; an ambiguous name in a clause
    -- body is still reported.
    it "is reported in the body of a clause that is never used" $ do
      kinds <- fst <$> checkedWithin 1 clauseGroupUnreachable
      sort kinds `shouldBe` sort ["other", "missing warning", "ambiguous thing"]

    it "is reported in the body of a clause in a group of three" $ do
      kinds <- fst <$> checkedWithin 1 clauseGroupThree
      sort kinds `shouldBe` sort ["missing warning", "ambiguous thing"]

  describe "a name with two meanings in the body of a WHERE-bound constant" $ do
    -- The body of a nullary definition is recorded, and a deontic action that
    -- names the constant has its performer read from it: the actor of the
    -- meaning the name was read as. Two readings of the name that return the
    -- same head still differ there, and only one agrees with the party, so the
    -- module has one reading that checks and is accepted. Merging the two
    -- readings as alike made it ambiguous.
    it "is accepted when only the reading whose actor is the party agrees with it" $ do
      diagnosticKinds (actionSource "Eater" ["act MEANS thing"]) `shouldReturn` []

    it "is accepted for the other party as well" $ do
      diagnosticKinds (actionSource "Drinker" ["act MEANS thing"]) `shouldReturn` []

    it "is accepted when the constant is named through another constant" $ do
      diagnosticKinds (actionSource "Eater" ["act MEANS next", "next MEANS thing"]) `shouldReturn` []

    it "is accepted when the name is used directly, with no constant (the control)" $ do
      diagnosticKinds (actionSource "Eater" []) `shouldReturn` []

    it "is reported ambiguous when both readings agree with the party" $ do
      diagnosticKinds (actionSourceWith "Eater" "Eater" ["act MEANS thing"]) `shouldReturn` ["ambiguous thing"]

  describe "the growth guard" $ do
    -- The controls for the guards above: the one that is made to look at a
    -- cost that doubles with each step still fails it, and one whose clock
    -- never ticks gives no ratio, within seconds, so that the test goes
    -- pending and not wrong.
    it "still fails a cost that doubles with each operand" $ do
      ratio <- growthRatioOn getCPUTime exponentialWork 10 20 growthLimit
      case ratio of
        Nothing -> pendingWith "the CPU clock did not tick, so there is no ratio to judge"
        Just r -> r `shouldSatisfy` (>= growthLimit)

    it "gives no ratio on a clock that never ticks" $ do
      ratio <- growthRatioOn (pure 0) (const (pure ())) 10 20 growthLimit
      ratio `shouldBe` Nothing

-- ----------------------------------------------------------------------------
-- Programs

-- | The arms of the CONSIDER that ends a chain, covering Red and Green but not
-- Blue.
partialArms :: Text
partialArms = "WHEN Red THEN TRUE, WHEN Green THEN FALSE"

-- | The arms covering every constructor, and Red again.
redundantArms :: Text
redundantArms = "WHEN Red THEN TRUE, WHEN Green THEN FALSE, WHEN Blue THEN FALSE, WHEN Red THEN FALSE"

-- | The arms covering every constructor once.
exhaustiveArms :: Text
exhaustiveArms = "WHEN Red THEN TRUE, WHEN Green THEN FALSE, WHEN Blue THEN FALSE"

-- | A rule that combines @n@ BOOLEAN inputs with @op@ and ends in a CONSIDER
-- with the given arms: @p0 OR p1 OR ... OR (CONSIDER c ...)@.
chainSource :: Text -> Text -> Int -> Text
chainSource op arms n =
  Text.unlines $
    [ "IMPORT prelude"
    , ""
    , "DECLARE Colour IS ONE OF Red, Green, Blue"
    , ""
    , "GIVEN c IS A Colour"
    ]
      <> [ "      p" <> tshow i <> " IS A BOOLEAN" | i <- [0 .. n - 1] ]
      <> [ "GIVETH A BOOLEAN"
         , "DECIDE big c " <> Text.unwords operands <> " IS"
         , "  " <> Text.intercalate (" " <> op <> " ") operands <> " " <> op <> " (CONSIDER c " <> arms <> ")"
         ]
  where
    operands = [ "p" <> tshow i | i <- [0 .. n - 1] ]

-- | A function named like the constructor of a record with one LIST field,
-- called with a CONSIDER with the given arms as its first argument, by a rule
-- that does not say what it gives.
bagSource :: Text -> Text
bagSource arms =
  Text.unlines
    [ "DECLARE Colour IS ONE OF Red, Green, Blue"
    , ""
    , "DECLARE Bag HAS items IS A LIST OF NUMBER"
    , ""
    , "GIVEN a IS A NUMBER"
    , "      b IS A NUMBER"
    , "GIVETH A NUMBER"
    , "DECIDE Bag a b IS a PLUS b"
    , ""
    , "GIVEN c IS A Colour"
    , "DECIDE test c IS Bag (CONSIDER c " <> arms <> ") 3"
    ]

-- ----------------------------------------------------------------------------
-- Checking

-- | The kinds of warning a program is reported with, in order, or the number
-- of hard errors if it is rejected. Under a watchdog, since a regression here
-- is a check that does not finish.
warnings :: Text -> IO (Either Int [Text])
warnings source = do
  mb <- timeout checkSeconds $ case checkWithImports emptyVFS source of
    Left errs -> fail ("unexpected pipeline failure: " <> show errs)
    Right r -> do
      ok <- evaluate r.tcdSuccess
      let kinds = [ kindOf w | MkCheckErrorWithContext (CheckWarning w) _ <- r.tcdErrors ]
          hard = length [ () | e <- r.tcdErrors, severity e == SError ]
      _ <- evaluate (sum (Text.length <$> kinds) + hard)
      pure (if ok then Right kinds else Left hard)
  maybe (fail "the check did not finish within the watchdog") pure mb
  where
    kindOf = \ case
      PatternMatchesMissing {}  -> "missing"
      PatternMatchRedundant {}  -> "redundant"
      _                         -> "other"

-- | The watchdog on one check, in microseconds. It is wall-clock time
-- ('System.Timeout.timeout' has no other), so it has to leave room for a busy
-- machine: at a load of 55 a check that took 0.1 s of CPU time stalled for 61 s.
checkSeconds :: Int
checkSeconds = 120 * 1000000

-- | The check of a chain of 20 operands takes less than 'growthLimit' times
-- the check of 10, and both are accepted. The test is pending if the clock
-- gave no ratio.
chainGrowsLinearly :: Text -> Text -> Expectation
chainGrowsLinearly op arms = do
  ratio <- growthRatioOn getCPUTime check 10 20 growthLimit
  case ratio of
    Nothing -> pendingWith "the CPU clock did not tick while the smaller chain was checked, so there is no ratio to judge"
    Just r -> r `shouldSatisfy` (< growthLimit)
  where
    check n = do
      mb <- timeout checkSeconds $ case checkWithImports emptyVFS (chainSource op arms n) of
        Left errs -> fail ("unexpected pipeline failure: " <> show errs)
        Right r -> evaluate r.tcdSuccess
      case mb of
        Nothing -> expectationFailure ("the check of " <> show n <> " operands did not finish within 120 s")
        Just ok -> ok `shouldBe` True

-- | How many times longer the larger program may take. Linear growth is about
-- 2 (and less, beside the cost of loading the prelude, which the smaller check
-- already pays); doubling at every operand is about 1,000.
growthLimit :: Double
growthLimit = 8

-- ----------------------------------------------------------------------------
-- The guard

-- | A CPU clock, in picoseconds, as 'getCPUTime' reads it.
type Clock = IO Integer

-- | @growthRatioOn clock work small large limit@: the time @work large@ takes
-- over the time @work small@ takes, both as the clock reads them; or 'Nothing'
-- if the clock read no time for the smaller (the fastest of three runs). A
-- ratio short of twice the limit is measured again, up to twice, so that one
-- pause does not fail it.
growthRatioOn :: Clock -> (Int -> IO ()) -> Int -> Int -> Double -> IO (Maybe Double)
growthRatioOn clock work small large limit = do
  smalls <- traverse (const (timed small)) [1 .. 3 :: Int]
  let smallest = minimum smalls
  if smallest <= 0
    then pure Nothing
    else do
      let settle tries = do
            r <- (/ smallest) <$> timed large
            if r < limit || r >= 2 * limit || tries <= (1 :: Int) then pure r else min r <$> settle (tries - 1)
      Just <$> settle 3
  where
    timed k = do
      t0 <- clock
      work k
      t1 <- clock
      pure (fromIntegral (t1 - t0) :: Double)

-- | Work whose cost doubles with each step: a sum of 2^(n+8) numbers. It is not
-- the checker, so that the control does not depend on it.
exponentialWork :: Int -> IO ()
exponentialWork n = void (evaluate (foldl' (+) 0 [1 .. 2 ^ (n + 8) :: Int]))

tshow :: Int -> Text
tshow = Text.pack . show

-- ----------------------------------------------------------------------------
-- A name with two meanings

-- | Which of a name's two meanings carry a warning where the name is used, in
-- a CONSIDER over them.
data Meanings
  = OneWarns   -- ^ one meaning's CONSIDER misses a case, the other's is complete
  | BothWarn   -- ^ each meaning's CONSIDER misses a case
  | BothClean  -- ^ each meaning's CONSIDER is complete
  deriving stock (Eq)

meanings :: [(String, Meanings)]
meanings =
  [ ("when one meaning would warn", OneWarns)
  , ("when each meaning would warn", BothWarn)
  , ("when neither meaning would warn", BothClean)
  ]

-- | @thing@ is a Colour and a Light, and a rule adds up @k@ CONSIDERs over it.
forkSource :: Meanings -> Int -> Text
forkSource m k =
  Text.unlines $
    forkHeader m
      <> [ "GIVETH A NUMBER"
         , "DECIDE score IS"
         ]
      <> [ (if i == 1 then "       " else "  PLUS ") <> arm m i | i <- [1 .. k] ]

forkHeader :: Meanings -> [Text]
forkHeader m =
  [ "DECLARE Colour IS ONE OF Red, Green, Blue"
  , "DECLARE Light IS ONE OF Red, Green" <> if m == OneWarns then "" else ", Amber"
  , ""
  , "GIVETH A Colour"
  , "DECIDE thing IS Blue"
  , ""
  , "GIVETH A Light"
  , "DECIDE thing IS Green"
  , ""
  ]

arm :: Meanings -> Int -> Text
arm m i =
  "(CONSIDER thing WHEN Red THEN " <> tshow i
    <> (if m == BothClean then ", OTHERWISE 2)" else ", WHEN Green THEN 2)")

-- | Where the chain of CONSIDERs sits, other than the body of a top-level
-- definition. Both are bodies that the checker treats as local: a @WHERE@
-- constant, and the clauses of a group after the first, which are compiled
-- into a local definition of their own.
data Placement
  = InWhereConstant
  | InSecondClause

placements :: [(String, Placement)]
placements =
  [ ("in the body of a WHERE constant", InWhereConstant)
  , ("in the second clause of a group", InSecondClause)
  ]

placedSource :: Placement -> Meanings -> Int -> Text
placedSource place m k =
  Text.unlines $ forkHeader m <> case place of
    InWhereConstant ->
      [ "GIVETH A NUMBER"
      , "DECIDE score IS total"
      , "  WHERE total MEANS " <> chain
      ]
    InSecondClause ->
      [ "GIVEN c IS A Colour"
      , "GIVETH A NUMBER"
      , "DECIDE score Red IS 1"
      , "DECIDE score Green IS " <> chain
      , "DECIDE score Blue IS 4"
      ]
  where
    chain = Text.intercalate " PLUS " [ arm m i | i <- [1 .. k] ]

-- | What a program of 'forkSource' is reported with: the name is ambiguous at
-- each use, and a meaning that would have warned has its warning shown.
expectedKinds :: Meanings -> Int -> [Text]
expectedKinds m k = concat (replicate k (warning <> ["ambiguous thing"]))
  where
    warning = if m == BothClean then [] else ["missing warning"]

-- | The kinds of the diagnostics of a program.
diagnosticKinds :: Text -> IO [Text]
diagnosticKinds source = case checkWithImports emptyVFS source of
  Left errs -> fail ("unexpected pipeline failure: " <> show errs)
  Right r -> do
    let kinds = map kindOf r.tcdErrors
    _ <- evaluate (sum (Text.length <$> kinds))
    pure kinds
  where
    kindOf (MkCheckErrorWithContext e _) = case e of
      CheckWarning PatternMatchesMissing {} -> "missing warning"
      CheckWarning PatternMatchRedundant {} -> "redundant warning"
      AmbiguousTermError n _                -> "ambiguous " <> rawNameToText (rawName n)
      _                                     -> "other"

-- | How much a check may allocate, in bytes, before it is stopped.
allocationLimit :: Int64
allocationLimit = 2 * 1024 * 1024 * 1024

-- | The kinds of the diagnostics of a program and the bytes it took to check
-- it in this thread, or a failure if it takes more than 'allocationLimit'
-- (exponential work).
checkedWithin :: Int -> Text -> IO ([Text], Integer)
checkedWithin uses source = do
  setAllocationCounter allocationLimit
  enableAllocationLimit
  r <- try (timeout checkSeconds (diagnosticKinds source) `finally` disableAllocationLimit)
  case r of
    Left AllocationLimitExceeded ->
      fail (show uses <> " uses allocated more than " <> show (allocationLimit `div` (1024 * 1024)) <> " MiB")
    Right Nothing ->
      fail (show uses <> " uses did not finish within the watchdog")
    Right (Just kinds) -> do
      left <- getAllocationCounter
      pure (kinds, fromIntegral (allocationLimit - left))

-- | The index of an inference variable.
varOf :: Type' r -> Int
varOf = \ case
  InfVar _ _ i -> i
  _            -> error "varOf: not an inference variable"

pick :: Char -> Type' r -> Type' r -> Type' r
pick c x y = if c == 'x' then x else y

-- | @thing@ as in 'forkSource', and a group of clauses whose second clause is
-- never used, with the CONSIDER over @thing@ in its body.
clauseGroupUnreachable :: Text
clauseGroupUnreachable = clauseGroupWith ["DECIDE score c IS 1", "DECIDE score Red IS " <> considerThing]

-- | The same CONSIDER in the first of three clauses.
clauseGroupThree :: Text
clauseGroupThree = clauseGroupWith ["DECIDE score Red IS " <> considerThing, "DECIDE score Green IS 3", "DECIDE score Blue IS 4"]

-- | A contract whose one action is the name @thing@, defined twice at one
-- type, one with the actor Eater and one with the actor Drinker; the name is
-- read directly if there are no locals, and otherwise through the first of
-- them, which is named @act@.
actionSource :: Text -> [Text] -> Text
actionSource party = actionSourceWith "Drinker" party

-- | 'actionSource' with the actor of the second @thing@.
actionSourceWith :: Text -> Text -> [Text] -> Text
actionSourceWith secondActor party locals =
  Text.unlines $
    [ "DECLARE Actor IS ONE OF Eater, Drinker"
    , ""
    , "DECLARE Action HAS"
    , "  actor IS AN Actor"
    , "  verb  IS A STRING"
    , ""
    , "GIVETH AN Action"
    , "DECIDE thing IS Action OF Eater, \"eat\""
    , ""
    , "GIVETH AN Action"
    , "DECIDE thing IS Action OF " <> secondActor <> ", \"drink\""
    , ""
    , "GIVETH DEONTIC Actor Action"
    , "contract MEANS PARTY " <> party <> " MUST " <> (if null locals then "thing" else "act") <> " WITHIN 30"
    ]
      <> [ (if i == 0 then "  WHERE " else "        ") <> l | (i, l) <- zip [0 :: Int ..] locals ]

considerThing :: Text
considerThing = "(CONSIDER thing WHEN Red THEN 1, WHEN Green THEN 2)"

clauseGroupWith :: [Text] -> Text
clauseGroupWith clauses =
  Text.unlines $
    [ "DECLARE Colour IS ONE OF Red, Green, Blue"
    , "DECLARE Light IS ONE OF Red, Green"
    , ""
    , "GIVETH A Colour"
    , "DECIDE thing IS Blue"
    , ""
    , "GIVETH A Light"
    , "DECIDE thing IS Green"
    , ""
    , "GIVEN c IS A Colour"
    , "GIVETH A NUMBER"
    ]
      <> clauses

-- | The outcomes of a computation of the checker, run from the initial state,
-- and how many viable outcomes each stands for.
outcomesOf :: Check a -> [(With CheckErrorWithContext a, CheckState)]
outcomesOf m = runCheck m (initialCheckEnv (toNormalizedUri (Uri "file:///warning-viable-fork-spec"))) initialCheckState

weightsOf :: Check a -> [Int]
weightsOf = map outcomeWeight . outcomesOf
