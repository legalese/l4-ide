{-# LANGUAGE OverloadedStrings #-}
-- | A TYPICALLY number reaches the JSON schema exactly as it was written, and a
-- value with no exact decimal form is left out rather than rounded.
module TypicallyExactNumberSpec (spec) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Ratio ((%))
import System.Timeout (timeout)
import Test.Hspec

import L4.Annotation (emptyAnno)
import L4.FunctionSchema (typicallyToJson)
import L4.Syntax (Expr (..), Lit (..))

numberDefault :: Rational -> Maybe String
numberDefault r =
  BL.unpack . Aeson.encode <$> typicallyToJson (Lit emptyAnno (NumericLit emptyAnno r))

spec :: Spec
spec = describe "TYPICALLY number defaults in the schema" do
  it "keeps every digit of a 20-digit integer" do
    numberDefault 12345678901234567891 `shouldBe` Just "12345678901234567891"
  it "keeps every place of a long decimal" do
    numberDefault (10000000000000000001 % 10000000000000000000)
      `shouldBe` Just "1.0000000000000000001"
  it "keeps a negative decimal" do
    numberDefault (-125 % 100) `shouldBe` Just "-1.25"
  it "leaves out a value with no exact decimal form, without hanging" do
    let v = numberDefault (1 % 3)
    r <- timeout 5000000 (length (show v) `seq` pure v)
    r `shouldBe` Just Nothing
