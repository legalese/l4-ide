{-# LANGUAGE OverloadedStrings #-}

-- | A name with two meanings that both check, used many times, costs work
-- linear in its uses.
--
-- Resolution keeps every meaning of a name that checks, so that something
-- later can choose between them, and each one runs the rest of the enclosing
-- expression; so do the failures that come with them (the name's fallback, and
-- the candidates that did not fit). A rule that adds k CONSIDERs over such a
-- name cost (outcomes of one use)^k, and every one of those paths but one was
-- thrown away, because the module is then rejected as ambiguous. Main became
-- exposed when a warning stopped failing a candidate (legalese/l4-ide#698):
-- a name where one meaning would warn went from one viable outcome to two.
-- Outcomes that nothing after them can tell apart now run as one
-- ('L4.TypeCheck.Types.mergeAlike', ported from legalese/l4-ide#683, whose
-- unstable copy of this file holds the tests of #674 as well; only #683's are
-- here, adapted to main).
module WarningViableForkSpec (spec) where

import Control.Exception (AllocationLimitExceeded (..), evaluate, finally, try)
import Control.Monad (forM_)
import Data.Int (Int64)
import Data.List (isInfixOf, sort)
import Data.Text (Text)
import qualified Data.Text as Text
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
  ( Check, CheckError (..), CheckState (plural), CheckErrorWithContext (..)
  , CheckWarning (..)
  , addError, addWarning, bindInfVar, choose, forkWithLazyFallback, fresh, orElse, outcomeWeight, prune
  , runCheck, softprune, softpruneAlike, viableCandidate
  )

spec :: Spec
spec = describe "A name with two meanings" $ do
  describe "a name with two meanings that both check" $ do
    -- Outcomes that leave the substitution as it was, and so cannot be told
    -- apart by anything that follows, are run as one, whether either carries
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
        -- is stopped, so that the exponential cost is a failure and not a hang
        -- or an exhausted machine.
        (_, small) <- checkedWithin 10 (forkSource m 10)
        (_, large) <- checkedWithin 20 (forkSource m 20)
        fromIntegral large / fromIntegral small `shouldSatisfy` (< growthLimit)

  describe "a name with two meanings where the checker treats the body as local" $ do
    -- A WHERE constant, and the clauses of a group after the first, which are
    -- compiled into a local definition: the chain is as cheap here as at the
    -- top.
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
        warned = addWarning (PatternMatchesMissing [])
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
      let failing msg = addError (OutOfScopeError (MkName emptyAnno (NormalName msg)) (Type emptyAnno)) >> pure (0 :: Int)
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
      -- One success keeps no fallback; a plural one is two
      -- ('forkWithLazyFallback', which main has from the port of #169).
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
    -- 'L4.TypeCheck.headKey' is what unstable's reader of a definition's body
    -- reads, and nothing else; main keeps it as it is there.
    let uri = toNormalizedUri (Uri "file:///head-key-spec")
        name n = Def (MkUnique 'c' n uri) (MkName emptyAnno (NormalName "thing"))
        bare n = App emptyAnno (name n) []
        applied f args = App emptyAnno (name f) args
        number n = Lit emptyAnno (NumericLit emptyAnno n)

    it "tells two names apart by what they name" $ do
      headKey (bare 1) `shouldNotBe` headKey (bare 2)
      headKey (bare 1) `shouldBe` headKey (bare 1)

    it "tells two applications apart by the head of an argument" $ do
      headKey (applied 9 [bare 1, number 1]) `shouldNotBe` headKey (applied 9 [bare 2, number 1])
      headKey (applied 9 [number 1, bare 1]) `shouldNotBe` headKey (applied 9 [bare 1, number 1])

    it "does not tell apart what that reader does not look at" $ do
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
        warned = addWarning (PatternMatchesMissing [])
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
        warned = addWarning (PatternMatchesMissing [])
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

  describe "a name with two meanings in the argument of a name with two meanings" $ do
    -- The CONSIDER over @thing@ is merged into one plural outcome, and it is
    -- the only viable outcome of the call of @f@ ('forkWithLazyFallback').
    -- Read as one success, the fork drops its fallback, and with it the
    -- report that names @f@; read as the two it stands for, the report is
    -- what it was before the merge.
    forM_ meanings \ (label, m) -> describe label do
      it "is reported as it was, with the fallback of the call kept" $ do
        (kinds, _) <- checkedWithin 1 (forkArgSource m)
        sort kinds `shouldBe` sort (forkArgKinds m)

  describe "a name with two meanings before a WHERE constant" $ do
    -- The WHERE constant's declaration is checked under a prune of its own,
    -- inside the path of the operand before it. That prune counts its own
    -- outcomes only: read with the merged operand's flag, its one outcome
    -- was two, an ambiguity, the path died, and the module took the reading
    -- that was left ('L4.TypeCheck.Types.fromEntry').
    it "is reported in the argument of an overloaded call, as main reports it" $ do
      kinds <- fst <$> checkedWithin 1 (whereAfterSource sizeOperand)
      sort kinds `shouldBe` sort ["ambiguous size", "ambiguous thing"]

    it "is reported in both branches of an IF, as main reports it" $ do
      kinds <- fst <$> checkedWithin 1 ifThenWhereSource
      sort kinds `shouldBe` sort ["ambiguous thing", "ambiguous thing"]

    it "is reported the same with a plain operand in place of the WHERE (the control)" $ do
      kinds <- fst <$> checkedWithin 1 (Text.replace "(z WHERE z MEANS 5)" "5" (whereAfterSource sizeOperand))
      sort kinds `shouldBe` sort ["ambiguous size", "ambiguous thing"]

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

-- ----------------------------------------------------------------------------
-- Programs

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

-- | @thing@ as in 'forkSource', and @f@ defined at NUMBER and at STRING,
-- called on one CONSIDER over @thing@.
forkArgSource :: Meanings -> Text
forkArgSource m =
  Text.unlines $
    forkHeader m
      <> [ "GIVEN n IS A NUMBER"
         , "GIVETH A NUMBER"
         , "DECIDE f n IS n"
         , ""
         , "GIVEN s IS A STRING"
         , "GIVETH A NUMBER"
         , "DECIDE f s IS 0"
         , ""
         , "GIVETH A NUMBER"
         , "DECIDE score IS f " <> arm m 1
         ]

-- | What 'forkArgSource' is reported with, as main reports it without the
-- merge (the port of #169 alone, d4102165d).
forkArgKinds :: Meanings -> [Text]
forkArgKinds m =
  ["ambiguous f"] <> (if m == BothClean then [] else ["missing warning"]) <> ["ambiguous thing"]

-- | @thing@ at Colour and at Light, @size@ at Colour and at every type, and
-- a rule that adds @size thing@ to a WHERE constant (the refuter's c3).
whereAfterSource :: Text -> Text
whereAfterSource operand =
  Text.unlines
    [ "DECLARE Colour IS ONE OF Red, Green, Blue"
    , "DECLARE Light IS ONE OF Red, Green"
    , ""
    , "GIVETH A Colour"
    , "DECIDE thing IS Blue"
    , ""
    , "GIVETH A Light"
    , "DECIDE thing IS Green"
    , ""
    , "GIVEN x IS A Colour"
    , "GIVETH A NUMBER"
    , "DECIDE size x IS 2"
    , ""
    , "GIVEN a IS A TYPE"
    , "      x IS AN a"
    , "GIVETH A NUMBER"
    , "DECIDE size x IS 1"
    , ""
    , "GIVETH A NUMBER"
    , "DECIDE score IS " <> operand <> " PLUS (z WHERE z MEANS 5)"
    ]

sizeOperand :: Text
sizeOperand = "(size thing)"

-- | @thing@ twice at Colour and once at Light, read in both branches of an
-- IF passed to a polymorphic function with a WHERE constant as its second
-- argument (the refuter's c2).
ifThenWhereSource :: Text
ifThenWhereSource =
  Text.unlines
    [ "DECLARE Colour IS ONE OF Red, Green, Blue"
    , "DECLARE Light IS ONE OF Red, Green"
    , ""
    , "GIVETH A Colour"
    , "DECIDE thing IS Blue"
    , ""
    , "GIVETH A Colour"
    , "DECIDE thing IS Red"
    , ""
    , "GIVETH A Light"
    , "DECIDE thing IS Green"
    , ""
    , "GIVEN a IS A TYPE"
    , "      x IS AN a"
    , "      y IS A NUMBER"
    , "GIVETH AN a"
    , "DECIDE first2 x y IS x"
    , ""
    , "DECIDE score IS first2 (IF TRUE THEN thing ELSE thing) (z WHERE z MEANS 5)"
    ]

-- | @thing@ as in 'forkSource', and a group of clauses whose second clause is
-- never used, with the CONSIDER over @thing@ in its body.
clauseGroupUnreachable :: Text
clauseGroupUnreachable = clauseGroupWith ["DECIDE score c IS 1", "DECIDE score Red IS " <> considerThing]

-- | The same CONSIDER in the first of three clauses.
clauseGroupThree :: Text
clauseGroupThree = clauseGroupWith ["DECIDE score Red IS " <> considerThing, "DECIDE score Green IS 3", "DECIDE score Blue IS 4"]

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

tshow :: Int -> Text
tshow = Text.pack . show

-- ----------------------------------------------------------------------------
-- Checking

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

-- | The watchdog on one check, in microseconds. It is wall-clock time
-- ('System.Timeout.timeout' has no other), so it has to leave room for a busy
-- machine: at a load of 55 a check that took 0.1 s of CPU time stalled for 61 s.
checkSeconds :: Int
checkSeconds = 120 * 1000000

-- | How many times more the larger program may take. Linear growth is about
-- 2; doubling at every use is about 1,000.
growthLimit :: Double
growthLimit = 8

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

-- | The outcomes of a computation of the checker, run from the initial state,
-- and how many viable outcomes each stands for.
outcomesOf :: Check a -> [(With CheckErrorWithContext a, CheckState)]
outcomesOf m = runCheck m (initialCheckEnv (toNormalizedUri (Uri "file:///warning-viable-fork-spec"))) initialCheckState

weightsOf :: Check a -> [Int]
weightsOf = map outcomeWeight . outcomesOf
