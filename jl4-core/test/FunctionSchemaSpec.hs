{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | The schema that jl4-service and the editor publish for the answer of an
-- exported rule ('L4.FunctionSchema.typeToParameter' on its return type), for
-- a rule that gives back an EVENT, and for one that gives back another type of
-- two arguments, which is not described as an event.
--
-- The service answers an event as an object with one key, @EVENT@, holding the
-- party, the action and the time in that order (the built-in constructor has
-- no field names, so the parts go by position):
-- @{"EVENT": ["Seller", "delivery", 2]}@. The schema says the same.
module FunctionSchemaSpec (spec) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import qualified Data.ByteString.Lazy.Char8 as LBS
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Export (ExportedFunction (..), enrichReturnTypes, getExportedFunctions)
import L4.FunctionSchema (declaresFromModule, typeToParameter)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))

source :: Text
source = Text.unlines
  [ "DECLARE Person IS ONE OF Seller, Buyer"
  , "DECLARE Action IS ONE OF delivery, payment"
  , ""
  , "DECLARE Report HAS"
  , "  label IS A STRING"
  , "  happened IS AN EVENT Person Action"
  , ""
  , "DECLARE Happening IS AN EVENT Person Action"
  , ""
  , "@export The delivery event"
  , "GIVEN who IS A Person"
  , "GIVETH AN EVENT Person Action"
  , "`the delivery` who MEANS EVENT who delivery 2"
  , ""
  , "@export Two events"
  , "GIVEN who IS A Person"
  , "GIVETH A LIST OF EVENT Person Action"
  , "`two events` who MEANS LIST (EVENT who delivery 1), (EVENT Buyer payment 5)"
  , ""
  , "@export Maybe an event"
  , "GIVEN yes IS A BOOLEAN"
  , "GIVETH A MAYBE (EVENT Person Action)"
  , "`maybe an event` yes MEANS IF yes THEN JUST (EVENT Seller delivery 3) ELSE NOTHING"
  , ""
  , "@export A report"
  , "GIVEN who IS A Person"
  , "GIVETH A Report"
  , "`a report` who MEANS Report WITH label IS \"x\", happened IS EVENT who payment 9"
  , ""
  , "@export A happening"
  , "GIVEN who IS A Person"
  , "GIVETH A Happening"
  , "`a happening` who MEANS EVENT who payment 4"
  , ""
  , "DECLARE Box OF a, b HAS"
  , "  left IS AN a"
  , "  right IS A b"
  , ""
  , "@export A box"
  , "GIVEN n IS A NUMBER"
  , "GIVETH A Box OF NUMBER, STRING"
  , "`a box` n MEANS Box n \"x\""
  ]

-- | Each exported rule's return schema, as the JSON a client reads.
returnSchemas :: IO (Map.Map Text Aeson.Value)
returnSchemas =
  case checkWithImports emptyVFS source of
    Left errs -> fail ("the fixture did not check: " <> show errs)
    Right r -> do
      let declares = declaresFromModule r.tcdModule
          exports = enrichReturnTypes r.tcdEntityInfo (getExportedFunctions r.tcdModule)
      pure $ Map.fromList
        [ (ef.exportName, Aeson.toJSON (typeToParameter declares Set.empty ty))
        | ef <- exports
        , Just ty <- [ef.exportReturnType]
        ]

schemaOf :: Text -> IO Aeson.Value
schemaOf fn = do
  schemas <- returnSchemas
  maybe (fail ("no return schema for " <> Text.unpack fn <> " among " <> show (Map.keys schemas))) pure (Map.lookup fn schemas)

json :: LBS.ByteString -> Aeson.Value
json bs = either (error . ("bad expected JSON: " <>)) id (Aeson.eitherDecode bs)

-- | The schema of an @EVENT Person Action@ answer.
eventSchema :: Aeson.Value
eventSchema = json $ LBS.unlines
  [ "{ \"type\": \"object\","
  , "  \"properties\": { \"EVENT\": {"
  , "    \"type\": \"array\","
  , "    \"description\": \"The party, the action and the time of the event\","
  , "    \"prefixItems\": ["
  , "      { \"type\": \"string\", \"description\": \"The party performing the action\","
  , "        \"enum\": [\"Seller\", \"Buyer\", \"NEVERMATCHESPARTY\"], \"x-l4-type\": \"Person\" },"
  , "      { \"type\": \"string\", \"description\": \"The action performed\","
  , "        \"enum\": [\"delivery\", \"payment\", \"NEVERMATCHESACT\"], \"x-l4-type\": \"Action\" },"
  , "      { \"type\": \"number\", \"description\": \"The time of the event\" } ],"
  , "    \"minItems\": 3,"
  , "    \"maxItems\": 3 } },"
  , "  \"propertyOrder\": [\"EVENT\"],"
  , "  \"required\": [\"EVENT\"] }"
  ]

-- | The node at a path of keys.
at :: [Text] -> Aeson.Value -> Maybe Aeson.Value
at [] v = Just v
at (k : ks) (Aeson.Object o) = Aeson.KeyMap.lookup (Aeson.Key.fromText k) o >>= at ks
at _ _ = Nothing

spec :: Spec
spec = do
  eventSpec
  twoArgumentSpec

eventSpec :: Spec
eventSpec = describe "the return schema of an @export that gives back an EVENT" do
  it "describes an EVENT answer as an object whose EVENT key holds the party, the action and the time" do
    schemaOf "the delivery" >>= (`shouldBe` eventSchema)

  it "describes each item of a LIST OF EVENT as an event" do
    schemaOf "two events" >>= (`shouldBe` Aeson.object ["type" Aeson..= ("array" :: Text), "items" Aeson..= eventSchema])

  -- A MAYBE is published as its inner type, without null (smucclaw/l4-ide#1010).
  it "describes the event of a MAYBE (EVENT ...)" do
    schemaOf "maybe an event" >>= (`shouldBe` eventSchema)

  -- A record is published as its fields, without the constructor key the
  -- answer has around them (smucclaw/l4-ide#1010); the event in its field is
  -- described as an event.
  it "describes an EVENT in a field of a record answer" do
    schemaOf "a report" >>= \s -> at ["properties", "happened"] s `shouldBe` Just eventSchema

  it "describes an answer whose type is a synonym of an EVENT" do
    schemaOf "a happening" >>= (`shouldBe` eventSchema)

-- | EVENT is not the only type of two arguments. A record declared with two
-- type parameters is described by its own fields. Only its name and the names
-- of its fields are compared, and not the schemas of its fields, whose types
-- are type parameters.
twoArgumentSpec :: Spec
twoArgumentSpec = describe "the return schema of an @export that gives back another type of two arguments" do
  it "describes a record of two type arguments by its own fields, not as an event" do
    s <- schemaOf "a box"
    at ["x-l4-type"] s `shouldBe` Just (Aeson.String "Box")
    at ["propertyOrder"] s `shouldBe` Just (Aeson.toJSON ["left", "right" :: Text])
    at ["properties", "EVENT"] s `shouldBe` Nothing
