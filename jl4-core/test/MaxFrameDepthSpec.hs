-- | @JL4_MAX_FRAME_DEPTH@ takes a whole number from 1 to the largest 'Int';
-- anything else leaves the default limit.
module MaxFrameDepthSpec (spec) where

import Data.Foldable (for_)
import Test.Hspec

import L4.EvaluateLazy (parseMaxFrameDepth)

spec :: Spec
spec = describe "JL4_MAX_FRAME_DEPTH" $ do
  it "takes a whole number from 1 to the largest Int" $ do
    parseMaxFrameDepth "1" `shouldBe` Just 1
    parseMaxFrameDepth "300" `shouldBe` Just 300
    parseMaxFrameDepth (show (maxBound :: Int)) `shouldBe` Just maxBound

  -- Read as an Int, 2^64 + 1 wraps to 1 and 2^64 + 300 to 300.
  it "treats a number past the largest Int as unset, not as what it wraps to" $ do
    parseMaxFrameDepth "18446744073709551617" `shouldBe` Nothing
    parseMaxFrameDepth "18446744073709551916" `shouldBe` Nothing
    parseMaxFrameDepth "9223372036854775808" `shouldBe` Nothing

  -- `readMaybe` reads Haskell syntax, so all of these used to be 300.
  it "takes only ASCII decimal digits, with no leading zero" $ do
    for_ ["0x12C", "0o454", "(300)", " 300", "300\n", "0300", "+300", "3_00", "\x0663\x0660\x0660"] $ \v ->
      (v, parseMaxFrameDepth v) `shouldBe` (v, Nothing)

  it "treats 0, a negative number and text as unset" $ do
    parseMaxFrameDepth "0" `shouldBe` Nothing
    parseMaxFrameDepth "-5" `shouldBe` Nothing
    parseMaxFrameDepth "abc" `shouldBe` Nothing
    parseMaxFrameDepth "" `shouldBe` Nothing
