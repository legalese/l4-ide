{-# LANGUAGE OverloadedStrings #-}

-- | What the deployed schema says about a TYPICALLY value: the number exactly
-- as written, in the published JSON and after the metadata cache reads it back.
module TypicallyPublishedSpec (spec) where

import Test.Hspec

import Compiler (compileBundle)
import UnresolvedImportSpec (withLog)

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text

import L4.FunctionSchema (Parameter (..), Parameters (..))
import Types (DeploymentMetadata (..), FunctionSummary (..))

source :: Text
source = Text.unlines
  [ "DECLARE Account HAS"
  , "  balance IS A NUMBER TYPICALLY 12345678901234567891"
  , "  rate    IS A NUMBER TYPICALLY 1.0000000000000000001"
  , ""
  , "@export The balance of an account"
  , "GIVEN account IS AN Account"
  , "GIVETH A NUMBER"
  , "`balance of` account MEANS account's balance * account's rate"
  ]

-- | The published parameters of the one exported function.
published :: IO Parameters
published = do
  compiled <- withLog \logger -> compileBundle logger "typically" (Map.singleton "account.l4" source)
  case fst compiled of
    Left why -> fail (Text.unpack why)
    Right (_, meta) -> case meta.metaFunctions of
      [f] -> pure f.fsParameters
      fs -> fail ("expected one function, got " <> show (length fs))

-- | The JSON text of the default at a path of property names.
defaultAt :: [Text] -> Parameters -> Maybe String
defaultAt [] _ = Nothing
defaultAt (k : ks) ps = go ks =<< Map.lookup k ps.parameterMap
 where
  go [] p = BL.unpack . Aeson.encode <$> p.parameterDefault
  go (k' : ks') p = go ks' =<< Map.lookup k' =<< p.parameterProperties

spec :: Spec
spec = describe "TYPICALLY in the deployed schema" do
  it "publishes a record field's number exactly as written" do
    ps <- published
    (defaultAt ["account", "balance"] ps, defaultAt ["account", "rate"] ps)
      `shouldBe` (Just "12345678901234567891", Just "1.0000000000000000001")
  it "keeps the number exact through the metadata cache" do
    ps <- published
    reread <- either fail pure (Aeson.eitherDecode (Aeson.encode ps))
    defaultAt ["account", "rate"] reread `shouldBe` Just "1.0000000000000000001"
