-- | The measure that the timing tests use to ask whether some work takes time
-- linear in its size: the CPU time of a large case over that of a small one,
-- which is near the ratio of the sizes when the cost is linear and near its
-- square when the cost is quadratic. See Note [Measuring a ratio on a busy
-- machine].
--
-- How it fails, sorted by whether anyone would notice:
--
-- * Loud: work reused from one run to the next (a value computed once and
--   shared) makes the later small runs take no time, so the ratio is
--   enormous and the guard fails; or makes the later large runs take no
--   time, so the ratio is under 0.1, which 'cpuRatio' fails outright. That
--   is why each run gets its input from @prepare@ afresh.
--
-- * Loud: a control whose small runs were reused would pass with an enormous
--   ratio, so 'quadraticControl' also fails a ratio far beyond the square of
--   the sizes' ratio.
module LinearTime
  ( cpuRatio
  , quadraticControl
  , quadraticWork
  ) where

import Control.Exception (evaluate)
import Control.Monad (void)
import Data.List (sort)
import System.CPUTime (getCPUTime)
import System.Mem (performGC)
import Test.Hspec

{- Note [Measuring a ratio on a busy machine]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
A guard runs a small case and a large case and compares their CPU times. CI
runs several test suites side by side on one runner, so the machine can slow
down at any point while a guard runs, and stay slow. Run 44788713422 of
legalese/l4-ide#843 failed UnifySpec's nested-type guard at 8.16 against its
limit of 8, on a cost that measures about 4.5 on a quiet aarch64 Mac (CI
prints no ratio when the guard passes); jl4-test was checking corpus files on
the same runner in the same second. The guard then timed the small case three
times and only afterwards the large one, two or three times, and every large
time it took was over the limit. That is the pattern a slowdown that began
after the small case was timed, and lasted, would leave; the log shows no
more than that.

So 'cpuRatio' times three (small, large) pairs, each pair back to back so that
both halves see the same machine, and takes the median of the three pair
ratios:

* a slowdown that starts, or one that stops, spoils at most one pair, since
  the pairs after it see the same slowdown in both halves;
* one slow run, small or large, spoils at most one pair;
* a burst that starts and then stops spoils one pair upwards (a slow large
  run) and one downwards (a slow small run), and the median lies between;
* a quadratic cost is over the limit in every pair that is not spoiled, so
  the median still catches it while at most one pair is spoiled. The smallest
  pair ratio would not: one slow small run makes its pair's ratio small
  enough to pass.

Every run starts after a major collection ('performGC'), outside the timed
span, so that no run pays for garbage an earlier one left. Time is CPU time,
so that time spent waiting for a busy machine is not counted.

The measures compared. Made-up work: a sum of 200,000 times k numbers for a
linear cost, of 2,000 times k^2 numbers for a quadratic one; sizes 100 and
400 and a limit of 8, so the true ratio is 4 for the linear cost and 16 for
the quadratic. A slowdown was injected by making the chosen runs do that much
more work, counting runs in the order each measure makes them. Five runs of
each measure per row, every one with the same outcome; the number is a
typical ratio. Measured 2026-11-21 on an aarch64 Mac, GHC 9.10.3, -O1, by a
standalone program that is not in the tree.

* "before": the measure UnifySpec, ConsiderScaleSpec and PrintLayoutSpec used
  until then. The small case is the fastest of three runs; the large is timed
  once, and again, up to three times in all, only while the ratio is between
  the limit and twice it.
* "fastest of three": both cases the fastest of three runs, the large
  stopping at the first under the limit; performGC first.
* "pairs": three back-to-back (small, large) pairs; performGC first.

  cost       slowdown injected              before    fastest   pairs,    pairs,
                                                      of three  smallest  median
  ---------  -----------------------------  --------  --------  --------  ------
  linear     none                           pass      pass      pass      pass
  linear     the 4th run 5 times slower     FAIL 20   pass      pass      pass
  linear     2.2 times slower from the 4th  FAIL 8.8  FAIL 8.8  pass      pass
             run on
  linear     2.2 times slower throughout    pass      pass      pass      pass
  quadratic  none                           caught    caught    caught    caught
  quadratic  the 1st run 2.5 times slower   caught    caught    MISSED    caught
                                                                6.4

For "before" and "fastest of three" the 4th run is the first large one, so
the third row is the shape of #843's failure: a slowdown that began after the
small case was timed.
-}

-- | @cpuRatio prepare run small large@: the median, over three back-to-back
-- pairs of runs, of the CPU time of @run@ on the input @prepare large@ makes
-- over its time on the input @prepare small@ makes; see Note [Measuring a
-- ratio on a busy machine]. @prepare@ runs before each timed run, outside the
-- timed span, so that building the input is not timed and no run reuses
-- another's input. A small run that reads as less than 1 ms counts as 1 ms.
--
-- It fails the test when the ratio is under 0.1. No large case takes a tenth
-- of the time of its small one, so that means the large runs reused a result
-- computed earlier, which would otherwise pass any guard unnoticed.
cpuRatio :: (k -> IO a) -> (a -> IO ()) -> k -> k -> IO Double
cpuRatio prepare run small large = do
  rs <- traverse (const pair) [1 .. 3 :: Int]
  let r = sort rs !! 1
  r `shouldSatisfy` (> 0.1)
  pure r
  where
    pair = do
      s <- timed small
      l <- timed large
      pure (l / max s 1.0e9)
    timed k = do
      input <- prepare k
      performGC
      t0 <- getCPUTime
      run input
      t1 <- getCPUTime
      pure (fromIntegral (t1 - t0) :: Double)

-- | @quadraticWork small large k@: work that takes time quadratic in @k@,
-- 8·10^7 additions times @k^2 / (small * large)@. For sizes 4 times apart
-- that is 2·10^7 additions at the small size and 3.2·10^8 at the large; for
-- sizes 16 times apart, 5·10^6 and 1.28·10^9. It is made up, so that a
-- control built on it does not depend on the code its guard times. The number
-- of additions is read back out of 'evaluate' before the sum is taken, so
-- that the sum is computed afresh on every call.
quadraticWork :: Int -> Int -> Int -> IO ()
quadraticWork small large k = do
  n <- evaluate (80000000 * k * k `div` (small * large))
  void (evaluate (foldl' (+) 0 [1 .. n]))
{-# NOINLINE quadraticWork #-}

-- | The control for a guard: on the guard's sizes and limit, 'cpuRatio' judges
-- 'quadraticWork' to be over the limit. It also checks that the ratio is
-- under four times the square of the sizes' ratio, which a quadratic cost
-- comes nowhere near, so that it cannot pass by the accident the module
-- header describes.
quadraticControl :: Int -> Int -> Double -> Expectation
quadraticControl small large limit = do
  r <- cpuRatio pure (quadraticWork small large) small large
  r `shouldSatisfy` (>= limit)
  r `shouldSatisfy` (< 4 * square)
  where
    square = (fromIntegral large / fromIntegral small) ^ (2 :: Int) :: Double
