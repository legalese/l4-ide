{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | How the check of a CONSIDER scales with its arms.
module ConsiderScaleSpec (spec) where

import Control.DeepSeq (force)
import Control.Exception (evaluate)
import Data.Text (Text)
import qualified Data.Text as Text
import System.CPUTime (getCPUTime)
import System.Mem (getAllocationCounter)
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

  -- A diagnostic carries in its context the syntax it was raised in, as
  -- written: the warning that asks this CONSIDER for an OTHERWISE carries
  -- the whole CONSIDER. Resolving the types in a diagnostic used to rebuild
  -- all of that inside the checker's monad, whether anything read it or not
  -- ('L4.TypeCheck.Types.substituteInfVars'); for a CONSIDER of 4,000
  -- numbers, the heap peaked at 0.93 GB while it did.
  --
  -- Counted in the bytes this thread allocates, which nothing else running
  -- changes, against the same CONSIDER with an OTHERWISE, which raises no
  -- diagnostic: the two differ by one arm and one warning. Measured on the
  -- change that made the context lazy: 1.00 with it, 2.13 without it.
  it "costs about the same to check with a warning as without" $ do
    let allocated src = do
          _ <- evaluate (Text.length src)
          a0 <- getAllocationCounter
          n <- case checkWithImports emptyVFS src of
            Left errs -> fail ("the module failed to check: " <> show errs)
            Right r -> evaluate (length r.tcdErrors)
          a1 <- getAllocationCounter
          pure (n, fromIntegral (a0 - a1) :: Double)
        arms = considerOfNumbers 2000
    -- Whatever the first check of a module computes once, it computes here.
    _ <- allocated (considerOfNumbers 1)
    (warned, withWarning) <- allocated arms
    (unwarned, withoutWarning) <- allocated (arms <> "    OTHERWISE \"z\"\n")
    (warned, unwarned) `shouldBe` (1, 0)
    withWarning / withoutWarning `shouldSatisfy` (< 1.25)

  -- Each level of nested CONSIDERs is checked under a context that holds
  -- the CONSIDER at that level, and so every level inside it. Resolving
  -- the types in a diagnostic rebuilt each level of its context apart, so
  -- that forcing the warning at the innermost level, as the language
  -- server's rules force every diagnostic, made a copy of the syntax per
  -- level, quadratic in the depth: 600 levels peaked at 390 MB, where the
  -- build before GANDER, which raised no warning there, peaked at 13 MB. A
  -- context with nothing in it to resolve is now kept as it is, and shared
  -- ('L4.TypeCheck.Types.contextChanges').
  --
  -- Counted as above, with the diagnostics forced in full, against the same
  -- nesting with an OTHERWISE at the bottom. Measured on the change that
  -- kept the context: 1.27 with it, 2.26 without it.
  it "costs about the same to check with a warning deep inside nested CONSIDERs as without" $ do
    let allocated src = do
          _ <- evaluate (Text.length src)
          a0 <- getAllocationCounter
          n <- case checkWithImports emptyVFS src of
            Left errs -> fail ("the module failed to check: " <> show errs)
            Right r -> length <$> evaluate (force r.tcdErrors)
          a1 <- getAllocationCounter
          pure (n, fromIntegral (a0 - a1) :: Double)
    _ <- allocated (nestedConsiders 1 True)
    (warned, withWarning) <- allocated (nestedConsiders 300 False)
    (unwarned, withoutWarning) <- allocated (nestedConsiders 300 True)
    (warned, unwarned) `shouldBe` (1, 0)
    withWarning / withoutWarning `shouldSatisfy` (< 1.5)

-- | A rule of @d@ CONSIDERs, each in the OTHERWISE of the one before, the
-- last with an OTHERWISE or not.
nestedConsiders :: Int -> Bool -> Text
nestedConsiders d closed =
  Text.unlines $
    [ "GIVEN n IS A NUMBER"
    , "GIVETH A STRING"
    , "f n MEANS"
    ]
      <> concat
        [ [ pad i <> "CONSIDER n"
          , pad i <> "  WHEN " <> Text.pack (show i) <> " THEN \"a\""
          ]
            <> [ pad i <> "  OTHERWISE" | i < d - 1 ]
        | i <- [0 .. d - 1]
        ]
      <> [ pad (d - 1) <> "  OTHERWISE \"end\"" | closed ]
  where
    pad i = Text.replicate (2 + 4 * i) " "

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
