{-# LANGUAGE OverloadedStrings #-}

module CodeGenSpec (spec) where

import Test.Hspec
import Test.QuickCheck (property)
import Test.QuickCheck.Instances ()

import Control.Monad (forM_)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import Data.Either (isLeft, isRight)
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import Backend.Api (FnLiteral (..), TraceEvent (..), TraceLevel (..))
import Backend.CodeGen (inputFieldName, transformJsonKeys, escapeAsL4String, clientName, fnLiteralToL4Expr, fnLiteralToL4ExprWithType, generateEvalWrapper, generateDeonticEvalWrapper, GeneratedCode (..), AnswerShape (..), RequiredInput (..))
import Language.LSP.Protocol.Types (Uri (..), toNormalizedUri)
import L4.Lexer (TIdentifiers (..), TLiterals (..), TokenType (..), computedPayload, execLexer, showStringLit)
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

  -- A name that comes from a request is always written quoted, and refused when
  -- L4 cannot quote it. The lexer is the judge: what is written must read back
  -- as one quoted name holding the same text.
  describe "names from a request" $ do
    describe "clientName" $ do
      it "refuses exactly the names the lexer cannot read back from inside quotes" $
        forM_ (awkwardTexts <> ["", "`", " ", "  two  spaces  "]) $ \n ->
          (n, isRight (clientName n)) `shouldBe` (n, readsBackAsQuotedName n)

      it "agrees with the lexer on arbitrary text" $
        property $ \n -> isRight (clientName n) == readsBackAsQuotedName n

      it "writes a name it accepts as one quoted name" $
        forM_ (awkwardTexts <> ["plain", "with space"]) $ \n ->
          case clientName n of
            Left _ -> pure ()
            Right written -> significant written `shouldBe` Right [quotedName n]

      it "writes names that look like keywords or comment marks as plain names" $
        forM_ ["--", "{-", "-}", "IF", "TRUE", "'s", "a\"b", "back\\slash"] $ \n ->
          fmap significant (clientName n) `shouldBe` Right (Right [quotedName n])

      it "quotes at most 40 characters of a name it refuses" $
        case clientName (Text.replicate 100 "a" <> "`") of
          Left refusal -> refusal `shouldSatisfy` (not . Text.isInfixOf (Text.replicate 41 "a"))
          Right written -> expectationFailure ("accepted: " <> Text.unpack written)

    describe "each place a name is written" $ do
      forM_ namePositions $ \(label, render) ->
        it ("writes " <> label <> " as one quoted name, or refuses it") $
          forM_ (awkwardTexts <> ["", "`"]) $ \n ->
            case render n of
              Left _ -> (n, isLeft (clientName n)) `shouldBe` (n, True)
              Right written -> do
                isRight (clientName n) `shouldBe` True
                observed written `shouldBe` expectedFrom (render "x") n

    describe "each place a string is written" $ do
      forM_ stringPositions $ \(label, render) ->
        it ("writes " <> label <> " as a string the lexer reads back unchanged") $
          forM_ awkwardTexts $ \s ->
            case render s of
              Left refusal -> expectationFailure ("refused: " <> Text.unpack refusal)
              Right written -> observed written `shouldBe` expectedFrom (render "x") s

  -- The lexer's own writer of string literals is what writes the request payload
  -- and every string value, so it has to read back as the text it was given.
  describe "showStringLit" $ do
    it "reads back unchanged for awkward text" $
      forM_ awkwardTexts $ \s ->
        (s, decodedString (showStringLit s)) `shouldBe` (s, Just s)

    it "reads back unchanged for arbitrary text" $
      property $ \s -> decodedString (showStringLit s) == Just s

    it "hands a request payload to the decoder unchanged" $
      forM_ awkwardTexts $ \s -> do
        let payload = Aeson.object [("a key", Aeson.String s), (AesonKey.fromText s, Aeson.Bool True)]
        fmap (Aeson.eitherDecode . LBS.fromStrict . Text.Encoding.encodeUtf8) (decodedString (escapeAsL4String payload))
          `shouldBe` Just (Right payload)

  -- Whatever the events carry, the wrapper is made of the same tokens in the same
  -- order: the text of a name or a string changes the name or the string, and
  -- nothing else.
  describe "the deontic wrapper" $ do
    it "has the same shape whatever strings the events carry" $
      forM_ awkwardTexts $ \s ->
        (s, fmap shapeOf (wrapperTokens [event (recordOf "name" s) (recordOf "label" s)]))
          `shouldBe` (s, fmap shapeOf (wrapperTokens [event (recordOf "name" "x") (recordOf "label" "x")]))

    it "refuses an event whose name L4 cannot quote, and writes no wrapper" $
      forM_ ["", "`", "a`b", "two\nlines", "tab\there"] $ \n -> do
        wrapperTokens [event (FnLitString n) (FnLitString "x")] `shouldSatisfy` isLeft
        wrapperTokens [event (FnLitString "x") (FnObject [(n, FnArray [])])] `shouldSatisfy` isLeft
        wrapperTokens [event (recordOf n "x") (FnLitString "x")] `shouldSatisfy` isLeft

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

-- | Text with the characters that are awkward to write: quotes, backslashes, a
-- backtick, line breaks, other control characters, and text that looks like an
-- escape.
awkwardTexts :: [Text]
awkwardTexts =
  [ "\"", "\\", "\\\"", "\"\"", "a\"b", "a\\b", "\\\"x\\", "`", "a`b", "`a`"
  , "line\nbreak", "tab\tstop", "nul\0char", "cr\rhere", "bell\a", "\DEL", "\1", "\US"
  , "a\x2028 b", "a\x2029 b", "\xa0", "caf\xe9\&5", "\xe9" <> "5", "\x1F600" <> "7", "\x1F600"
  , "\\u0001", "\\n", "\\1234", "\\&", "{-", "-}", "--", "a b"
  , Text.replicate 3000 "ab\"\\" <> "`"
  ]

-- | The tokens of a text that are not spaces or comments, or the reason it does not lex.
significant :: Text -> Either String [TokenType]
significant src =
  case execLexer (toNormalizedUri (Uri "file:///codegen-spec")) src of
    Left errs -> Left (show errs)
    Right toks -> Right [ p | t <- toks, let p = computedPayload t, not (isSpace p) ]
  where
    isSpace = \case
      TSpaces _ -> True
      _ -> False

quotedName :: Text -> TokenType
quotedName = TIdentifiers . TQuoted

-- | Whether the lexer reads a text, put between backticks, as one quoted name holding it.
readsBackAsQuotedName :: Text -> Bool
readsBackAsQuotedName n = significant ("`" <> n <> "`") == Right [quotedName n]

-- | The value of a text that lexes as exactly one string literal.
decodedString :: Text -> Maybe Text
decodedString src = case significant src of
  Right [TLiterals (TStringLit _ decoded)] -> Just decoded
  _ -> Nothing

-- | The tokens of a rendering with the text of each name and string taken out.
shapeOf :: [TokenType] -> [TokenType]
shapeOf = map $ \case
  TIdentifiers (TQuoted _) -> TIdentifiers (TQuoted "")
  TIdentifiers (TIdentifier _) -> TIdentifiers (TIdentifier "")
  TLiterals (TStringLit _ _) -> TLiterals (TStringLit "" "")
  other -> other

-- | A rendering as the lexer reads it: the shape of its tokens, and the text of
-- each name and string in it, in order.
observed :: Text -> Either String ([TokenType], [Text])
observed written = do
  toks <- significant written
  Right (shapeOf toks, concatMap texts toks)
  where
    texts = \case
      TIdentifiers (TQuoted t) -> [t]
      TLiterals (TStringLit _ t) -> [t]
      _ -> []

-- | What 'observed' gives for a rendering made with some text in place of the
-- placeholder @x@ that the baseline rendering was made with.
expectedFrom :: Either Text Text -> Text -> Either String ([TokenType], [Text])
expectedFrom baseline replacement = do
  (shape, texts) <- either (Left . Text.unpack) observed baseline
  Right (shape, [ if t == "x" then replacement else t | t <- texts ])

-- | Each place in an event where a name from the request is written, with the
-- rendering of that name. The other names in a rendering are fixed, and none is @x@.
namePositions :: [(String, Text -> Either Text Text)]
namePositions =
  [ ("a string standing for a constructor", \n -> fnLiteralToL4Expr (FnLitString n))
  , ("a constructor name", \n -> fnLiteralToL4Expr (FnObject [(n, FnArray [])]))
  , ("a constructor name with an argument", \n -> fnLiteralToL4Expr (FnObject [(n, FnArray [FnLitInt 1])]))
  , ("a constructor name with a single value", \n -> fnLiteralToL4Expr (FnObject [(n, FnLitInt 1)]))
  , ("a record constructor name", \n -> fnLiteralToL4Expr (FnObject [(n, FnObject [("k", FnLitInt 1)])]))
  , ("a string nested under a constructor", \n -> fnLiteralToL4Expr (FnObject [("C", FnArray [FnLitString n])]))
  , ("a record key", \n -> fnLiteralToL4Expr (FnObject [("Con", FnObject [(n, FnLitInt 1)])]))
  , ("a typed record key", \n -> fnLiteralToL4ExprWithType (Just "Typ") (FnObject [(n, FnLitInt 1)]))
  , ("a name inside a list", \n -> fnLiteralToL4Expr (FnArray [FnLitString n, FnLitInt 1]))
  ]

-- | Each place in an event where a string from the request is written as data.
stringPositions :: [(String, Text -> Either Text Text)]
stringPositions =
  [ ("a record value", \s -> fnLiteralToL4ExprWithType (Just "Typ") (FnObject [("key", FnLitString s)]))
  , ("a record value in a list", \s -> fnLiteralToL4ExprWithType (Just "Typ") (FnObject [("key", FnArray [FnLitString s, FnLitString s])]))
  ]

event :: FnLiteral -> FnLiteral -> TraceEvent
event p a = TraceEvent p a 1

-- | A record-typed party or action: one field, with a string value.
recordOf :: Text -> Text -> FnLiteral
recordOf key value = FnObject [(key, FnLitString value)]

-- | The tokens of the wrapper the service writes for a deontic function without inputs.
wrapperTokens :: [TraceEvent] -> Either String [TokenType]
wrapperTokens events =
  case generateDeonticEvalWrapper "f" [] [] (Aeson.object []) 0 events (Just "Party") (Just "Action") TraceNone of
    Left refusal -> Left (Text.unpack refusal)
    Right generated -> significant generated.generatedWrapper
