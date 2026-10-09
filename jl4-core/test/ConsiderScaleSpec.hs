{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | How the check of a CONSIDER scales with its arms.
module ConsiderScaleSpec (spec) where

import Control.Exception (evaluate)
import Data.Text (Text)
import qualified Data.Text as Text
import System.CPUTime (getCPUTime)
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.TypeCheck (prettyCheckErrorWithContext)

spec :: Spec
spec = describe "CONSIDER over many numbers" $ do
  -- A CONSIDER with an arm for each of n numbers, as a fee table has, is
  -- checked in time near-linear in n. Each arm used to be checked against
  -- every constraint the arms above it left ('L4.TypeCheck.addConstraint'),
  -- and 4,000 arms took 18 s of CPU time where 250 took 0.26 s.
  --
  -- Timed by the ratio of two sizes, not by a bound in seconds, so that a
  -- slow machine does not fail it; and in the process's CPU time, not
  -- wall-clock time, so that time spent waiting for a busy machine is not
  -- counted. The sizes are 16 times apart, so linear time gives a ratio of
  -- about 16 and quadratic time about 256; the test fails at three times
  -- linear, and a ratio short of clearly quadratic is measured again, so
  -- that one pause does not fail it. Sizes 4 times apart would not do:
  -- checking each arm costs enough that the old cost only came to a ratio
  -- of 11 between 1,000 and 4,000 arms. Measured on the change that made it
  -- near-linear: 17 with it, 67 to 69 without it.
  it "is checked in time near-linear in its arms" $ do
    let timeCheck k = do
          src <- evaluate (considerOfNumbers k)
          _ <- evaluate (Text.length src)
          t0 <- getCPUTime
          ws <- case checkWithImports emptyVFS src of
            Left errs -> fail ("the module failed to check: " <> show errs)
            Right r -> pure r.tcdErrors
          rendered <- evaluate (sum (map (sum . map Text.length . prettyCheckErrorWithContext) ws))
          t1 <- getCPUTime
          -- The one warning, asking for an OTHERWISE, so the check of the
          -- arms ran to its end.
          (length ws, rendered > 0) `shouldBe` (1, True)
          pure (fromIntegral (t1 - t0) :: Double)
        fastest k tries = minimum <$> traverse (const (timeCheck k)) [1 .. tries :: Int]
    small <- fastest 250 3
    let ratio large = large / max small 1.0e9
        settle tries = do
          r <- ratio <$> timeCheck 4000
          if r < 48 || r >= 96 || tries <= (1 :: Int) then pure r else min r <$> settle (tries - 1)
    r <- settle 3
    r `shouldSatisfy` (< 48)

-- | A rule whose CONSIDER has an arm for each of the numbers 1 to @k@, and no
-- OTHERWISE.
considerOfNumbers :: Int -> Text
considerOfNumbers k =
  Text.unlines $
    [ "GIVEN n IS A NUMBER"
    , "GIVETH A STRING"
    , "f n MEANS"
    , "  CONSIDER n"
    ]
      <> [ "    WHEN " <> Text.pack (show i) <> " THEN \"a\"" | i <- [1 .. k] ]
