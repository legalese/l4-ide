{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

-- | Unit tests for Phase 1 pattern matching in function definitions: multiple
-- DECIDE/MEANS clauses sharing a head name are grouped into a single 'MkDecide'
-- whose body is a nested CONSIDER, while ordinary single-clause definitions are
-- left untouched. See specs/todo/PATTERN-MATCHING-SPEC.md.
module PatternMatchParserSpec (spec) where

import Base
import Control.Exception (evaluate)
import qualified Data.List.NonEmpty as NE
import qualified Data.Text as T
import System.CPUTime (getCPUTime)
import L4.Parser (execProgramParser)
import L4.Syntax
import Test.Hspec

spec :: Spec
spec = describe "Pattern-matching DECIDE desugaring (parser)" $ do
  it "groups multiple literal/variable clauses into one CONSIDER-bodied Decide" $ do
    let src = T.unlines
          [ "GIVEN n IS A NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE factorial 0 IS 1"
          , "DECIDE factorial n IS n * factorial (n - 1)"
          ]
    decides <- parseDecides src
    -- A single merged Decide, not two.
    map decideHeadText decides `shouldBe` ["factorial"]
    map decideBodyIsConsider decides `shouldBe` [True]

  it "groups constructor-pattern clauses (EMPTY / FOLLOWED BY) into one Decide" $ do
    let src = T.unlines
          [ "GIVEN list IS A LIST OF NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE len EMPTY IS 0"
          , "DECIDE len (x FOLLOWED BY xs) IS 1 + len xs"
          ]
    decides <- parseDecides src
    map decideHeadText decides `shouldBe` ["len"]
    map decideBodyIsConsider decides `shouldBe` [True]

  it "desugars a single clause that uses a literal pattern" $ do
    let src = T.unlines
          [ "GIVEN n IS A NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE isZero 0 IS 1"
          ]
    decides <- parseDecides src
    map decideHeadText decides `shouldBe` ["isZero"]
    map decideBodyIsConsider decides `shouldBe` [True]

  it "leaves an ordinary single variable-clause definition untouched" $ do
    let src = T.unlines
          [ "GIVEN x IS A NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE double x IS x * 2"
          ]
    decides <- parseDecides src
    map decideHeadText decides `shouldBe` ["double"]
    -- Not desugared to a CONSIDER: the body is the ordinary arithmetic expr.
    map decideBodyIsConsider decides `shouldBe` [False]

  it "keeps two differently-named functions as two separate Decides" $ do
    let src = T.unlines
          [ "GIVEN n IS A NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE inc 0 IS 1"
          , "DECIDE inc n IS n + 1"
          , ""
          , "GIVEN n IS A NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE dec 0 IS 0"
          , "DECIDE dec n IS n - 1"
          ]
    decides <- parseDecides src
    map decideHeadText decides `shouldBe` ["inc", "dec"]

  -- A run of clauses that starts no group is read once, not once for each of
  -- its clauses: a file of n lines @f x MEANS i@ was read about n * n / 2
  -- times, and 4,000 lines took minutes to check (review of
  -- legalese/l4-ide#545, round 2). Timed by the ratio of two sizes, not by a
  -- bound in seconds, so that a slow machine does not fail it; and in the
  -- process's CPU time, not wall-clock time, so that time spent waiting for a
  -- busy machine is not counted. Eight times the lines take about eight times
  -- as long when parsing is linear, and sixty-four times as long when it is
  -- quadratic; the test fails above three times linear. A ratio short of
  -- clearly quadratic is measured again, so that one pause does not fail it.
  it "parses a run of same-headed definitions in time linear in its length" $
    parsesInLinearTime 250 2000 24 \ i -> "f x MEANS " <> T.pack (show i)

  -- Every definition is tried as a clause group first, and every one that is
  -- not a group fails that attempt, so what a failed attempt costs must not
  -- grow with the definitions above it. Recording one once walked every
  -- position recorded so far, and a file of n lines @f1 x MEANS 1@,
  -- @f2 x MEANS 2@, ... took time quadratic in n (refutation of
  -- legalese/l4-ide#545's review, round 3). That cost was small beside the
  -- parse's own below a few thousand lines: measured with it, 2,000 lines took
  -- 8.4 times as long as 250, and 12,000 lines 40 to 68 times as long as
  -- 1,000, where without it they take about 14 times as long. So this times
  -- 1,000 and 12,000 lines, and fails above twice linear.
  it "parses definitions with different names in time linear in their number" $
    parsesInLinearTime 1000 12000 24 \ i -> "f" <> T.pack (show i) <> " x MEANS " <> T.pack (show i)

  -- Not about clauses: it is here for the timing helper below, which is
  -- private to this module (assumed, not ruled).
  --
  -- An @\@ref@ goes to the first node that starts at or after its end, and
  -- every node visited used to scan every ref not yet claimed, so a file with
  -- a citation on each of n definitions took time quadratic in n: 16,000 of
  -- them took 38 s to check, where the same definitions without citations
  -- took 4 s. The warnings are forced as well as the definitions, so that the
  -- whole pass has run when the clock stops. Measured with the scan, 8,000
  -- definitions took 34 to 35 times as long as 1,000; without it, 8.4 to 8.7
  -- times, which is what the same definitions with no citations take (8.1 to
  -- 8.7). So this times 1,000 and 8,000 lines and fails above twice linear.
  it "attaches @ref citations in time linear in their number" $
    parsesInLinearTimeWith parseDecidesForcingWarnings 1000 8000 16 \ i ->
      "@ref https://example.com/s" <> T.pack (show i) <> "\nf" <> T.pack (show i) <> " x MEANS " <> T.pack (show i)

  -- The guards above read the CPU clock. On Windows it ticks every 15.625 ms,
  -- and 250 lines parse in less than that: the small sample read 0, and the
  -- 1 ms floor under it turned the ratio into nonsense (review of
  -- legalese/l4-ide#545, round 4). This runs the first guard on a clock that
  -- reads as Windows' does; the guard now times enough parses of the small file
  -- to span ten steps.
  it "judges a linear parse linear on a clock that ticks every 15.625 ms" $
    parsesInLinearTimeOn (steppedClock windowsClockStep getCPUTime) parseDecides 250 2000 24 \ i ->
      "f x MEANS " <> T.pack (show i)

  -- The control for the one above: on the same clock, a parse that takes time
  -- quadratic in the lines is still failed (the work is made up, so that the
  -- test does not depend on the parser).
  it "still fails a quadratic parse on that clock" $
    parsesInLinearTimeOn (steppedClock windowsClockStep getCPUTime) quadraticParse 250 2000 24 (const "x")
      `shouldThrow` anyException

-- ----------------------------------------------------------------------------
-- Helpers

-- ----------------------------------------------------------------------------

-- | @parsesInLinearTime small large limit line@: parsing @large@ lines made
-- by @line@ (one definition each) takes less than @limit@ times the CPU time
-- of parsing @small@ lines. A ratio short of twice the limit is measured
-- again, up to twice, so that one pause does not fail it. See the comments
-- at its uses.
parsesInLinearTime :: Int -> Int -> Double -> (Int -> T.Text) -> Expectation
parsesInLinearTime = parsesInLinearTimeWith parseDecides

-- | 'parsesInLinearTime', with the parse it times given by the caller.
parsesInLinearTimeWith :: (T.Text -> IO [a]) -> Int -> Int -> Double -> (Int -> T.Text) -> Expectation
parsesInLinearTimeWith = parsesInLinearTimeOn getCPUTime

-- | A CPU clock, in picoseconds, as 'getCPUTime' reads it.
type Clock = IO Integer

-- | One step of the CPU clock on Windows, 15.625 ms in picoseconds: every
-- reading there is a multiple of it, so a parse that takes less than a step
-- reads as 0 or as a whole step.
windowsClockStep :: Integer
windowsClockStep = 15625000000

-- | A clock that reads in whole steps, rounding down, as Windows' does.
steppedClock :: Integer -> Clock -> Clock
steppedClock step clock = (\ t -> t `div` step * step) <$> clock

-- | 'parsesInLinearTimeWith' on a given clock.
--
-- The small file is parsed over and over in one timed stretch, until the
-- stretch spans ten steps of the Windows clock, and its time is the stretch's
-- divided by the number of parses: a single parse of 250 lines is shorter
-- than a step there, reads as 0, and the ratio of the large time to it was
-- nonsense (review of legalese\/l4-ide#545, round 4). The large file is parsed
-- once, since it is at least several times longer. The verdict is a ratio
-- of two non-zero times; if the clock never ticks within the longest stretch
-- tried, there is no ratio to judge and the test is pending, not failed.
parsesInLinearTimeOn :: Clock -> (T.Text -> IO [a]) -> Int -> Int -> Double -> (Int -> T.Text) -> Expectation
parsesInLinearTimeOn clock parse smallSize largeSize limit line = do
  let file k = T.unlines (map line [1 .. k])
      -- The CPU time of @reps@ parses of a file of @k@ lines, in picoseconds.
      timeParses k reps = do
        src <- evaluate (file k)
        _ <- evaluate (T.length src)
        t0 <- clock
        replicateM_ reps do
          n <- length <$> parse src
          n `shouldBe` k
        t1 <- clock
        pure (fromIntegral (t1 - t0) :: Double)
      measurable = fromIntegral (10 * windowsClockStep) :: Double
      maxReps = 4096 :: Int
      -- The number of parses of the small file that fills a measurable stretch.
      repsFor reps = do
        t <- timeParses smallSize reps
        if t >= measurable || reps >= maxReps then pure (reps, t) else repsFor (reps * 2)
  (reps, firstStretch) <- repsFor 1
  moreStretches <- traverse (const (timeParses smallSize reps)) [2 .. 3 :: Int]
  let small = minimum (firstStretch : moreStretches) / fromIntegral reps
  if small <= 0
    then pendingWith "the CPU clock did not tick while the small file was parsed, so there is no ratio to judge"
    else do
      let settle tries = do
            r <- (/ small) <$> timeParses largeSize 1
            if r < limit || r >= 2 * limit || tries <= (1 :: Int) then pure r else min r <$> settle (tries - 1)
      r <- settle 3
      r `shouldSatisfy` (< limit)

-- | A parse of no real file: it takes time quadratic in the number of lines
-- and finds one "definition" for each.
quadraticParse :: T.Text -> IO [()]
quadraticParse src = do
  let k = length (T.lines src)
  _ <- evaluate (foldl' (+) 0 [1 .. k * k * 50])
  pure (replicate k ())

parseDecides :: T.Text -> IO [Decide Name]
parseDecides src = fst <$> parseDecidesAndWarningCount src

-- | 'parseDecides', having also forced the warnings, which depend on the last
-- state of every pass that attaches annotations to the tree: so each of them
-- has run to the end.
parseDecidesForcingWarnings :: T.Text -> IO [Decide Name]
parseDecidesForcingWarnings src = do
  (decides, warningCount) <- parseDecidesAndWarningCount src
  _ <- evaluate warningCount
  pure decides

-- | The definitions, and a count of the warnings that is not yet evaluated.
parseDecidesAndWarningCount :: T.Text -> IO ([Decide Name], Int)
parseDecidesAndWarningCount src =
  case execProgramParser (toNormalizedUri (Uri "file:///pattern-match-spec")) src of
    Left errs ->
      fail ("Parser failed with: " <> show (NE.toList errs))
    Right (MkModule _ _ (MkSection _ _ _ _ decls), warnings) ->
      pure ([ d | Decide _ d <- decls ], length warnings)

decideHeadText :: Decide Name -> T.Text
decideHeadText (MkDecide _ _ (MkAppForm _ n _ _) _) = rawNameToText (rawName n)

-- | Is the desugared body a CONSIDER-based decision tree? We look through any
-- leading @LET ... IN@: to keep the emitted tree linear (rather than
-- exponential) in the number of clauses, each non-final clause binds the
-- desugaring of the remaining clauses to a fresh nullary local via @LET ... IN@,
-- and the decision CONSIDER is that LET's body. A single-clause desugar has no
-- fall-through and so is a bare CONSIDER.
decideBodyIsConsider :: Decide Name -> Bool
decideBodyIsConsider (MkDecide _ _ _ body) = go body
  where
    go = \ case
      Consider {}  -> True
      LetIn _ _ e  -> go e
      _            -> False
