{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | The return schema the editor shows for an exported rule
-- ('LSP.L4.Inspector.exportedFunctionToSummary'). It comes from the same
-- function as the one jl4-service publishes, so it describes the same answer.
module InspectorReturnSchemaSpec (spec) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text

import L4.Export (enrichReturnTypes, getExportedFunctions)
import L4.FunctionSchema (declaresFromModule)
import LSP.L4.Inspector (ExportedFunctionSummary (..), exportedFunctionToSummary)
import LSP.L4.Rules (TypeCheckResult (..))

import CheckSource (checkSource)
import Test.Hspec

source :: Text
source = Text.unlines
  [ "DECLARE Person IS ONE OF Seller, Buyer"
  , "DECLARE Action IS ONE OF delivery, payment"
  , ""
  , "@export The delivery event"
  , "GIVEN who IS A Person"
  , "GIVETH AN EVENT Person Action"
  , "`the delivery` who MEANS EVENT who delivery 2"
  , ""
  , "@export The duty to deliver"
  , "GIVEN who IS A Person"
  , "GIVETH A DEONTIC Person Action"
  , "`the duty` who MEANS PARTY who MUST delivery WITHIN 3"
  , ""
  , "@export The duty, written PROVISION"
  , "GIVEN who IS A Person"
  , "GIVETH A PROVISION Person Action"
  , "`the provision` who MEANS PARTY who MUST delivery WITHIN 3"
  ]

-- | Each exported rule's return schema, as the JSON the editor receives
-- (@null@ when there is none).
returnSchemas :: IO (Map.Map Text Aeson.Value)
returnSchemas = do
  (_, tc) <- checkSource "inspector-return-schema" source
  let declares = declaresFromModule tc.module'
      summaries = map (exportedFunctionToSummary declares)
        (enrichReturnTypes tc.entityInfo (getExportedFunctions tc.module'))
  pure (Map.fromList [ (s.name, Aeson.toJSON s.returnSchema) | s <- summaries ])

at :: [Text] -> Aeson.Value -> Maybe Aeson.Value
at [] v = Just v
at (k : ks) (Aeson.Object o) = Aeson.KeyMap.lookup (Aeson.Key.fromText k) o >>= at ks
at _ _ = Nothing

spec :: Spec
spec = describe "the return schema the editor shows for an @export" do
  it "describes an EVENT answer by its EVENT key and the three parts it holds" do
    schemas <- returnSchemas
    let event = Map.lookup "the delivery" schemas
    (event >>= at ["required"]) `shouldBe` Just (Aeson.toJSON ["EVENT" :: Text])
    (event >>= at ["properties", "EVENT", "type"]) `shouldBe` Just (Aeson.String "array")
    (event >>= at ["properties", "EVENT", "minItems"]) `shouldBe` Just (Aeson.Number 3)
    (event >>= at ["properties", "EVENT", "maxItems"]) `shouldBe` Just (Aeson.Number 3)
    (event >>= at ["properties", "EVENT", "prefixItems"]) `shouldSatisfy` \case
      Just (Aeson.Array parts) -> length parts == 3
      _ -> False

  it "shows no return schema for a rule whose duty is written DEONTIC" do
    schemas <- returnSchemas
    Map.lookup "the duty" schemas `shouldBe` Just Aeson.Null

  -- PROVISION is another name for the DEONTIC type.
  it "shows no return schema for a rule whose duty is written PROVISION" do
    schemas <- returnSchemas
    Map.lookup "the provision" schemas `shouldBe` Just Aeson.Null
