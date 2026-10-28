{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | How the check of a CONSIDER scales with its arms.
module ConsiderScaleSpec (spec) where

import Control.DeepSeq (force)
import Control.Exception (evaluate)
import Data.Text (Text)
import qualified Data.Text as Text
import System.Mem (getAllocationCounter)
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))

spec :: Spec
spec = describe "CONSIDER over many numbers" $ do
  -- A diagnostic carries in its context the syntax it was raised in, as
  -- written: the warning that asks this CONSIDER for an OTHERWISE carries
  -- the whole CONSIDER. Resolving the types in a diagnostic used to rebuild
  -- all of that inside the checker's monad, whether anything read it or not
  -- ('L4.TypeCheck.Types.substituteInfVars'); before M-D of the as-built spec
  -- (specs/as-built/multi-clause-decide.md, "Literal patterns"), a CONSIDER of
  -- 4,000 numbers with one type error in it peaked at 610 MB for it.
  --
  -- Counted in the bytes this thread allocates, which nothing else running
  -- changes, against the same CONSIDER with an OTHERWISE, which raises no
  -- diagnostic: the two differ by one arm and one warning. Measured on the
  -- change that made the context lazy: 1.00 with it, 2.16 without it.
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
  -- level, quadratic in the depth: 600 levels peaked at 520 MB, where the
  -- build before M-D, which raised no warning there, peaked at 13 MB. A
  -- context with nothing in it to resolve is now kept as it is, and shared
  -- ('L4.TypeCheck.Types.contextChanges').
  --
  -- Counted as above, with the diagnostics forced in full, against the same
  -- nesting with an OTHERWISE at the bottom. Measured on the change that
  -- kept the context: 1.17 with it, 2.36 without it.
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
