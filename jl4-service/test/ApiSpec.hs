{-# LANGUAGE OverloadedStrings #-}

module ApiSpec (spec) where

import Backend.Api
import Data.Aeson (decode)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as Aeson
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Test.Hspec
import L4.FunctionSchema (Parameters (..))
import Types (FunctionSummary (..))

spec :: Spec
spec = do
  -- The metadata cache holds a rule's summary, and a deployment that is not
  -- compiled yet is listed from it. An entry written before the cache held
  -- isDeontic reads it from the display name of the return type, and one that
  -- holds it is believed.
  describe "FunctionSummary from the metadata cache" $ do
    let cached returnType fields =
          Aeson.eitherDecode $ Aeson.encode $ Aeson.object $
            [ "name" Aeson..= ("f" :: Text)
            , "description" Aeson..= ("" :: Text)
            , "parameters" Aeson..= Aeson.object
                [ "type" Aeson..= ("object" :: Text)
                , "properties" Aeson..= Aeson.object []
                , "required" Aeson..= ([] :: [Text]) ]
            , "returnType" Aeson..= (returnType :: Text)
            ] <> fields
        flagOf :: Either String FunctionSummary -> Either String Bool
        flagOf = fmap (.fsIsDeontic)

    it "takes an entry with no isDeontic for a DEONTIC when it is displayed as one" $ do
      flagOf (cached "DEONTIC Party Action" []) `shouldBe` Right True

    it "takes an entry with no isDeontic for a DEONTIC when it is displayed as PROVISION OF" $ do
      flagOf (cached "PROVISION OF Driver, Driver Action" []) `shouldBe` Right True

    it "takes an entry with no isDeontic for an ordinary function otherwise" $ do
      flagOf (cached "BOOLEAN" []) `shouldBe` Right False

    -- the flag is written to the cache; the display name does not stand in for it
    it "writes isDeontic to the cache, whatever the return type is displayed as" $ do
      let summary flag = FunctionSummary
            { fsName = "f", fsDescription = "", fsParameters = MkParameters Map.empty []
            , fsReturnType = "BOOLEAN", fsReturnSchema = Nothing, fsSection = Nothing
            , fsIsDeontic = flag, fsSourceFile = Nothing }
          roundTrip flag = flagOf (Aeson.eitherDecode (Aeson.encode (summary flag)))
      (roundTrip True, roundTrip False) `shouldBe` (Right True, Right False)

    it "believes the isDeontic an entry holds over the name" $ do
      flagOf (cached "BOOLEAN" ["isDeontic" Aeson..= True]) `shouldBe` Right True
      flagOf (cached "PROVISION OF Driver, Driver Action" ["isDeontic" Aeson..= False]) `shouldBe` Right False

  describe "FnLiteral JSON parsing" $ do
    it "should preserve JSON String type (not coerce to number)" $ do
      let jsonString = "{\"value\": \"5\"}"
      let parsed = decode jsonString :: Maybe Aeson.Object
      case parsed of
        Nothing -> expectationFailure "Failed to parse JSON"
        Just obj -> do
          case KeyMap.lookup "value" obj of
            Nothing -> expectationFailure "Missing 'value' field"
            Just val -> do
              let literal = Aeson.parseMaybe Aeson.parseJSON val :: Maybe FnLiteral
              literal `shouldBe` Just (FnLitString "5")

    it "should parse JSON Number as FnLitInt" $ do
      let jsonNumber = "{\"value\": 5}"
      let parsed = decode jsonNumber :: Maybe Aeson.Object
      case parsed of
        Nothing -> expectationFailure "Failed to parse JSON"
        Just obj -> do
          case KeyMap.lookup "value" obj of
            Nothing -> expectationFailure "Missing 'value' field"
            Just val -> do
              let literal = Aeson.parseMaybe Aeson.parseJSON val :: Maybe FnLiteral
              literal `shouldBe` Just (FnLitInt 5)

    it "should keep 'five' as FnLitString" $ do
      let jsonString = "{\"value\": \"five\"}"
      let parsed = decode jsonString :: Maybe Aeson.Object
      case parsed of
        Nothing -> expectationFailure "Failed to parse JSON"
        Just obj -> do
          case KeyMap.lookup "value" obj of
            Nothing -> expectationFailure "Missing 'value' field"
            Just val -> do
              let literal = Aeson.parseMaybe Aeson.parseJSON val :: Maybe FnLiteral
              literal `shouldBe` Just (FnLitString "five")

    it "should parse JSON Number with decimal as FnLitDouble" $ do
      let jsonNumber = "{\"value\": 5.5}"
      let parsed = decode jsonNumber :: Maybe Aeson.Object
      case parsed of
        Nothing -> expectationFailure "Failed to parse JSON"
        Just obj -> do
          case KeyMap.lookup "value" obj of
            Nothing -> expectationFailure "Missing 'value' field"
            Just val -> do
              let literal = Aeson.parseMaybe Aeson.parseJSON val :: Maybe FnLiteral
              literal `shouldBe` Just (FnLitDouble 5.5)

    it "should keep '5.5' string as FnLitString (not convert to double)" $ do
      let jsonString = "{\"value\": \"5.5\"}"
      let parsed = decode jsonString :: Maybe Aeson.Object
      case parsed of
        Nothing -> expectationFailure "Failed to parse JSON"
        Just obj -> do
          case KeyMap.lookup "value" obj of
            Nothing -> expectationFailure "Missing 'value' field"
            Just val -> do
              let literal = Aeson.parseMaybe Aeson.parseJSON val :: Maybe FnLiteral
              literal `shouldBe` Just (FnLitString "5.5")

    it "should preserve large integers beyond Int bounds" $ do
      let largeInt = 9999999999999999999 :: Integer
      let jsonNumber = "{\"value\": 9999999999999999999}"
      let parsed = decode jsonNumber :: Maybe Aeson.Object
      case parsed of
        Nothing -> expectationFailure "Failed to parse JSON"
        Just obj -> do
          case KeyMap.lookup "value" obj of
            Nothing -> expectationFailure "Missing 'value' field"
            Just val -> do
              let literal = Aeson.parseMaybe Aeson.parseJSON val :: Maybe FnLiteral
              literal `shouldBe` Just (FnLitInt largeInt)

  describe "FnLiteral FromHttpApiData (query parameters)" $ do
    it "should infer type from query parameter string" $ do
      parseTextAsFnLiteral "5" `shouldBe` FnLitInt 5
      parseTextAsFnLiteral "5.5" `shouldBe` FnLitDouble 5.5
      parseTextAsFnLiteral "true" `shouldBe` FnLitBool True
      parseTextAsFnLiteral "false" `shouldBe` FnLitBool False
      parseTextAsFnLiteral "five" `shouldBe` FnLitString "five"

    it "should parse quoted strings as FnLitString" $ do
      parseTextAsFnLiteral "\"five\"" `shouldBe` FnLitString "five"
      parseTextAsFnLiteral "\"5\"" `shouldBe` FnLitString "5"

  describe "FnArguments JSON parsing" $ do
    it "parses arguments wrapper format" $ do
      let json = "{\"arguments\": {\"x\": 42}}"
      case decode json :: Maybe FnArguments of
        Nothing -> expectationFailure "Failed to parse FnArguments"
        Just fa -> do
          fa.fnArguments `shouldBe` Map.fromList [("x", Just (FnLitInt 42))]
          fa.startTime `shouldBe` Nothing
          fa.events `shouldBe` Nothing

    it "parses deontic format with arguments, startTime, and events" $ do
      let json = "{\"arguments\": {\"state\": true}, \"startTime\": 0, \"events\": []}"
      case decode json :: Maybe FnArguments of
        Nothing -> expectationFailure "Failed to parse FnArguments"
        Just fa -> do
          fa.fnArguments `shouldBe` Map.fromList [("state", Just (FnLitBool True))]
          fa.startTime `shouldBe` Just 0
          fa.events `shouldBe` Just []

    it "rejects missing arguments key" $ do
      let json = "{\"x\": 42}"
      (decode json :: Maybe FnArguments) `shouldBe` Nothing

    it "handles null argument values as Nothing" $ do
      let json = "{\"arguments\": {\"x\": null, \"y\": 5}}"
      case decode json :: Maybe FnArguments of
        Nothing -> expectationFailure "Failed to parse FnArguments"
        Just fa ->
          fa.fnArguments `shouldBe` Map.fromList [("x", Nothing), ("y", Just (FnLitInt 5))]
