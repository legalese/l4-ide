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

import Control.Exception (evaluate)
import Control.Monad (void)
import Data.Text (Text)
import qualified Data.Text as Text
import System.CPUTime (getCPUTime)
import System.Timeout (timeout)
import Test.Hspec

import L4.API.VirtualFS (TypeCheckWithDepsResult (..), checkWithImports, emptyVFS)
import L4.TypeCheck.Types (CheckError (..), CheckErrorWithContext (..), CheckWarning (..), Severity (..), severity)

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
    -- fails above 'growthLimit'. A check that has not finished in 30 s fails
    -- the test, rather than the suite waiting for it.
    it "checks an OR of 20 operands ending in a partial CONSIDER in time linear in the operands" $
      chainGrowsLinearly "OR" partialArms

    it "checks an AND of 20 operands ending in a partial CONSIDER in time linear in the operands" $
      chainGrowsLinearly "AND" partialArms

    it "checks an OR of 20 operands ending in a CONSIDER with a redundant arm in time linear in the operands" $
      chainGrowsLinearly "OR" redundantArms

    it "checks an OR of 20 operands ending in an exhaustive CONSIDER in time linear in the operands (the control)" $
      chainGrowsLinearly "OR" exhaustiveArms

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

-- | The watchdog on one check, in microseconds.
checkSeconds :: Int
checkSeconds = 30 * 1000000

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
        Nothing -> expectationFailure ("the check of " <> show n <> " operands did not finish within 30 s")
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
