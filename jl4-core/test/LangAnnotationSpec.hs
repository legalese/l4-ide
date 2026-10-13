{-# LANGUAGE OverloadedStrings #-}

-- | @\@lang en@: a module's language declaration.
--
-- A module whose first line is @\@lang en@ (which is how the L4 skills now open
-- every encoding) used to stop in the lexer with "unexpected '@'", and a lexer
-- failure leaves an editor with no tokens at all. This version has no
-- language-dependent rendering for the declaration to change, so the contract
-- is only that the declaration is read, is kept where it was written, and the
-- file prints back unchanged.
module LangAnnotationSpec (spec) where

import Base

import qualified Data.Text as T
import L4.ExactPrint (exactprint)
import L4.Lexer (PosToken (..), TAnnotations (..), TokenType (..), execLexer)
import L4.Parser (execProgramParserWithHintPass)
import Test.Hspec

uri :: NormalizedUri
uri = toNormalizedUri (Uri "file:///lang-annotation-spec")

body :: T.Text
body = T.unlines
  [ "GIVEN age IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "DECIDE `is adult` IF age GREATER THAN 17"
  ]

-- | The subtags of the @\@lang@ tokens the lexer finds.
declared :: T.Text -> Either String [T.Text]
declared src = case execLexer uri src of
  Left errs -> Left (show errs)
  Right toks -> Right [tag | MkPosToken {payload = TAnnotations (TLang tag _)} <- toks]

-- | Each source parses, and prints back byte for byte.
parsesAndPrintsBack :: String -> T.Text -> Spec
parsesAndPrintsBack name src =
  it (name <> " parses and exactprints unchanged") $
    case execProgramParserWithHintPass uri src of
      Left errs -> expectationFailure ("did not parse: " <> show errs)
      Right (modul, _hints, _warnings) ->
        case exactprint modul of
          Left err -> expectationFailure ("did not print: " <> show err)
          Right printed -> printed `shouldBe` src

spec :: Spec
spec = describe "@lang, a module's language declaration" $ do
  describe "lexer" $ do
    it "reads @lang en" $
      declared ("@lang en\n" <> body) `shouldBe` Right ["en"]
    it "reads @lang he with a trailing comment" $
      declared ("@lang he   -- עברית\n" <> body) `shouldBe` Right ["he"]
    it "reads a subtag with a hyphen" $
      declared ("@lang pt-BR\n" <> body) `shouldBe` Right ["pt-BR"]
    it "reads a declaration at the foot of the file" $
      declared (body <> "\n@lang en\n") `shouldBe` Right ["en"]
    it "still refuses a herald that merely starts with @lang" $
      declared ("@langx en\n" <> body) `shouldSatisfy` either (const True) (const False)
    it "still refuses @lang with no subtag" $
      declared ("@lang\n" <> body) `shouldSatisfy` either (const True) (const False)

  describe "parser and exactprint" $ do
    parsesAndPrintsBack "@lang en at line 1" ("@lang en\n\n" <> body)
    parsesAndPrintsBack "@lang he with a trailing comment at line 1"
      ("@lang he   -- עברית\n\n" <> body)
    parsesAndPrintsBack "@lang en at the foot" (body <> "\n@lang en\n")
    parsesAndPrintsBack "@lang he with a trailing comment at the foot"
      (body <> "\n@lang he -- עברית\n")
    parsesAndPrintsBack "two @lang declarations in one file"
      ("@lang en\n\n" <> body <> "\n@lang he\n")
    parsesAndPrintsBack "@lang en between two declarations"
      ("GIVEN age IS A NUMBER\nGIVETH A BOOLEAN\nDECIDE `is adult` IF age GREATER THAN 17\n\n@lang en\n\nGIVEN n IS A NUMBER\nGIVETH A NUMBER\nDECIDE `twice` n IS n PLUS n\n")
