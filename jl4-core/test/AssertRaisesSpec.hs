{-# LANGUAGE OverloadedStrings #-}

-- | An @#ASSERT@ whose expression raises is neither satisfied nor failed: the
-- evaluator could not decide it. It used to be collapsed into "failed", so
-- @#ASSERT P@ and @#ASSERT NOT P@ both reported "assertion failed" whenever
-- @P@ raised, and an editor could not tell a wrong answer from an error.
--
-- These go through the two entry points the browser editor and the Inspector
-- call, 'l4Eval' and 'l4EvalDirective', so they pin what those surfaces say.
module AssertRaisesSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text

import L4.API (l4Eval, l4EvalDirective)

-- | @boom 0@ divides by zero. @boom 1@ is TRUE and @boom 2@ is FALSE, so the
-- clean verdicts sit beside the raising ones as controls.
source :: Text
source = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`boom` n MEANS (1 DIVIDED BY n) EQUALS 1"
  , ""
  , "#ASSERT `boom` 0"
  , "#ASSERT NOT `boom` 0"
  , "#ASSERT `boom` 1"
  , "#ASSERT `boom` 2"
  ]

spec :: Spec
spec = describe "an #ASSERT whose expression raises" $ do
  it "is reported as unevaluable, never as failed, whichever way round it is written" $ do
    out <- l4Eval source
    Text.count "assertion could not be evaluated" out `shouldBe` 2
    Text.count "Division by zero" out `shouldBe` 2
    -- the one clean FALSE (boom 2) is the only "failed"
    Text.count "assertion failed" out `shouldBe` 1
    Text.count "assertion satisfied" out `shouldBe` 1

  it "gives the Inspector the reason, a failure and no value, for P and for NOT P" $ do
    mapM_
      (\line -> do
         out <- l4EvalDirective source line 1 "assert"
         out `shouldSatisfy` Text.isInfixOf "assertion could not be evaluated"
         out `shouldSatisfy` Text.isInfixOf "\"success\":false"
         out `shouldSatisfy` Text.isInfixOf "\"structuredValue\":null"
         out `shouldNotSatisfy` Text.isInfixOf "assertion failed")
      [5, 6]

  it "leaves a clean verdict alone: TRUE is satisfied with value true, FALSE is failed with value false" $ do
    holds <- l4EvalDirective source 7 1 "assert"
    holds `shouldSatisfy` Text.isInfixOf "assertion satisfied"
    holds `shouldSatisfy` Text.isInfixOf "\"structuredValue\":true"
    fails <- l4EvalDirective source 8 1 "assert"
    fails `shouldSatisfy` Text.isInfixOf "assertion failed"
    fails `shouldSatisfy` Text.isInfixOf "\"success\":false"
    fails `shouldSatisfy` Text.isInfixOf "\"structuredValue\":false"
