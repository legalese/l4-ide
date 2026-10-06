{-# LANGUAGE OverloadedStrings #-}

module CodeGenSpec (spec) where

import Test.Hspec

import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Backend.Api (TraceLevel (..))
import Backend.CodeGen (inputFieldName, transformJsonKeys, escapeAsL4String, generateEvalWrapper, generateDeonticEvalWrapper, GeneratedCode (..), AnswerShape (..), RequiredInput (..))
import L4.TypeCheck.Environment (boolean, date, maybeType, number)

spec :: SpecWith ()
spec = describe "CodeGen" $ do
  -- A function with no inputs has nothing to decode, so its wrapper is a bare
  -- #EVAL, and handleEvalResult must not look for a JUST around the answer.
  describe "answerShape of a function with no inputs" $ do
    it "is Bare for an ordinary function" $
      fmap (.answerShape) (generateEvalWrapper "f" [] [] (Aeson.object []) TraceNone)
        `shouldBe` Right Bare

    it "is Bare for a deontic function" $
      fmap (.answerShape) (generateDeonticEvalWrapper "f" [] [] (Aeson.object []) 0 [] Nothing Nothing TraceNone)
        `shouldBe` Right Bare

  -- The wrapper unwraps every input that is neither a BOOLEAN nor a MAYBE,
  -- GIVENs before ASSUMEs, and reads a DATE from a string.
  describe "requiredInputs" $
    it "lists the inputs the wrapper cannot go on without, in its order" $
      fmap (.requiredInputs)
        (generateEvalWrapper "f"
          [("a", number), ("b", boolean), ("c", maybeType number), ("d", date)]
          [("e", number), ("f", date), ("g", maybeType date)]
          (Aeson.object []) TraceNone)
        `shouldBe` Right
          [ RequiredInput "a" True Nothing
          , RequiredInput "d" True (Just "DATE")
          , RequiredInput "e" False Nothing
          , RequiredInput "f" False (Just "DATE")
          ]

  describe "inputFieldName" $ do
    it "adds (input) suffix to simple names" $ do
      inputFieldName "x" `shouldBe` "x (input)"
      inputFieldName "value" `shouldBe` "value (input)"

    it "adds (input) suffix to names with spaces" $ do
      inputFieldName "musk service role" `shouldBe` "musk service role (input)"
      inputFieldName "first value" `shouldBe` "first value (input)"

    it "handles empty string" $ do
      inputFieldName "" `shouldBe` " (input)"

  describe "transformJsonKeys" $ do
    it "transforms top-level object keys" $ do
      let input = Aeson.object
            [ ("x", Aeson.Number 1)
            , ("y", Aeson.Number 2)
            ]
          expected = Aeson.object
            [ ("x (input)", Aeson.Number 1)
            , ("y (input)", Aeson.Number 2)
            ]
      transformJsonKeys input `shouldBe` expected

    it "transforms keys with spaces" $ do
      let input = Aeson.object
            [ ("musk service role", Aeson.String "CEO")
            , ("board approved", Aeson.Bool True)
            ]
          expected = Aeson.object
            [ ("musk service role (input)", Aeson.String "CEO")
            , ("board approved (input)", Aeson.Bool True)
            ]
      transformJsonKeys input `shouldBe` expected

    it "does not transform nested object keys" $ do
      let input = Aeson.object
            [ ("person", Aeson.object
                [ ("name", Aeson.String "Alice")
                , ("age", Aeson.Number 30)
                ])
            ]
          expected = Aeson.object
            [ ("person (input)", Aeson.object
                [ ("name", Aeson.String "Alice")
                , ("age", Aeson.Number 30)
                ])
            ]
      transformJsonKeys input `shouldBe` expected

    it "passes through non-object values unchanged" $ do
      transformJsonKeys (Aeson.String "test") `shouldBe` Aeson.String "test"
      transformJsonKeys (Aeson.Number 42) `shouldBe` Aeson.Number 42
      transformJsonKeys (Aeson.Bool True) `shouldBe` Aeson.Bool True
      transformJsonKeys Aeson.Null `shouldBe` Aeson.Null

    it "passes through arrays unchanged" $ do
      let input = Aeson.toJSON [1 :: Int, 2, 3]
      transformJsonKeys input `shouldBe` input

  describe "escapeAsL4String" $ do
    it "wraps JSON in quotes" $ do
      let result = escapeAsL4String (Aeson.object [("x", Aeson.Number 1)])
      Text.head result `shouldBe` '"'
      Text.last result `shouldBe` '"'

    it "handles nested objects (the original bug)" $ do
      -- This was the actual failing case: nested record type parameters
      let input = Aeson.object
            [ ("applicant", Aeson.object
                [ ("age", Aeson.Number 43)
                , ("risk-score", Aeson.Number 0.5)
                , ("is-existing-customer", Aeson.Bool False)
                ])
            ]
          result = escapeAsL4String input
          -- Strip outer quotes to get the string content as L4 would see it
          inner = Text.drop 1 $ Text.dropEnd 1 result
      -- The inner content should NOT contain \\ (escaped backslash)
      -- because the JSON for this input has no backslashes at all.
      -- The old bug: naive quote replacement turned Aeson's \" into \\"
      Text.isInfixOf "\\\\" inner `shouldBe` False

    it "escapes backslashes in string values" $ do
      -- String value with a backslash: JSON encodes \ as \\
      -- L4 string must then escape those backslashes too, so \\\\ in L4
      let input = Aeson.object [("path", Aeson.String "C:\\Users")]
          result = escapeAsL4String input
          inner = Text.drop 1 $ Text.dropEnd 1 result
      -- Must contain \\\\ (two escaped backslashes = one literal \\ in JSON)
      Text.isInfixOf "\\\\\\\\" inner `shouldBe` True

    it "escapes quotes in string values" $ do
      -- String value containing quotes: JSON encodes " as \"
      -- L4 string must escape both the backslash and the quote
      let input = Aeson.object [("name", Aeson.String "John \"Doe\"")]
          result = escapeAsL4String input
          inner = Text.drop 1 $ Text.dropEnd 1 result
      -- Must contain \\\" (escaped backslash + escaped quote)
      Text.isInfixOf "\\\\\\\"" inner `shouldBe` True
