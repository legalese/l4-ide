{-# LANGUAGE OverloadedStrings #-}
module CsvImportSpec (spec) where

import Base
import qualified Data.Text as Text
import L4.Parser (execProgramParserWithHintPass)
import L4.Syntax
import Test.Hspec

-- | Parse a source snippet and return the first IMPORT declaration.
-- Fails the assertion if the source contains no IMPORT at the top level.
firstImport :: Text -> IO (Import Name)
firstImport src = do
  let uri = toNormalizedUri (Uri "file:///csv-import-spec")
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (MkModule _ _ (MkSection _ _ _ decls), _, _) ->
      case [imp | Import _ imp <- decls] of
        (imp : _) -> pure imp
        [] -> do
          expectationFailure $
            "Expected an IMPORT at the top level, got: " <> show decls
          error "unreachable"

importNameText :: Import Name -> Text
importNameText = rawNameToText . rawName . importName

spec :: Spec
spec = describe "IMPORT parsing" $ do
  describe "Regular module imports (existing behavior preserved)" $ do
    it "parses bare IMPORT name as MkImport" $ do
      imp <- firstImport "IMPORT prelude"
      case imp of
        MkImport _ n _ -> rawNameToText (rawName n) `shouldBe` "prelude"
        MkDataImport {} -> expectationFailure "Expected MkImport, got MkDataImport"

    it "parses IMPORT of a quoted-identifier filename as MkImport (no AS clause)" $ do
      imp <- firstImport "IMPORT `trades.csv`"
      case imp of
        MkImport _ n _ -> rawNameToText (rawName n) `shouldBe` "trades.csv"
        MkDataImport {} -> expectationFailure "Expected MkImport, got MkDataImport"

  describe "Tabular data imports (new MkDataImport)" $ do
    it "parses IMPORT `file.csv` AS Trade as MkDataImport with empty fields" $ do
      imp <- firstImport "IMPORT `trades.csv` AS Trade"
      importNameText imp `shouldBe` "trades.csv"
      case imp of
        MkDataImport _ _ (MkDataImportSchema _ rowN fields) _ -> do
          rawNameToText (rawName rowN) `shouldBe` "Trade"
          fields `shouldBe` []
        MkImport {} -> expectationFailure "Expected MkDataImport, got MkImport"

    it "parses IMPORT … AS Trade HAS one field" $ do
      imp <- firstImport "IMPORT `trades.csv` AS Trade HAS notional IS A NUMBER"
      case imp of
        MkDataImport _ _ (MkDataImportSchema _ rowN [field]) _ -> do
          rawNameToText (rawName rowN) `shouldBe` "Trade"
          case field of
            MkDataImportField _ fn (DataImportPrim _ tyN) -> do
              rawNameToText (rawName fn) `shouldBe` "notional"
              rawNameToText (rawName tyN) `shouldBe` "NUMBER"
            _ -> expectationFailure $ "Unexpected field shape: " <> show field
        _ -> expectationFailure $ "Expected MkDataImport with 1 field, got: " <> show imp

    it "parses IMPORT … AS Trade HAS multiple fields" $ do
      imp <- firstImport $ Text.unlines
        [ "IMPORT `trades.csv` AS Trade HAS"
        , "    `trade date` IS A DATE,"
        , "    notional     IS A NUMBER,"
        , "    settled      IS A BOOLEAN"
        ]
      case imp of
        MkDataImport _ _ (MkDataImportSchema _ rowN fields) _ -> do
          rawNameToText (rawName rowN) `shouldBe` "Trade"
          length fields `shouldBe` 3
          [ fieldName f | f <- fields ] `shouldBe` ["trade date", "notional", "settled"]
          [ fieldTypeName f | f <- fields ] `shouldBe` ["DATE", "NUMBER", "BOOLEAN"]
        _ -> expectationFailure $ "Expected MkDataImport, got: " <> show imp

    it "parses MAYBE T as a column type" $ do
      imp <- firstImport "IMPORT `trades.csv` AS Trade HAS `match price` IS A MAYBE NUMBER"
      case imp of
        MkDataImport _ _ (MkDataImportSchema _ _ [field]) _ ->
          case field of
            MkDataImportField _ _ (DataImportMaybe _ tyN) ->
              rawNameToText (rawName tyN) `shouldBe` "NUMBER"
            _ -> expectationFailure $ "Expected MAYBE field, got: " <> show field
        _ -> expectationFailure $ "Expected MkDataImport, got: " <> show imp
  where
    fieldName (MkDataImportField _ fn _) = rawNameToText (rawName fn)
    fieldTypeName (MkDataImportField _ _ (DataImportPrim  _ tyN)) = rawNameToText (rawName tyN)
    fieldTypeName (MkDataImportField _ _ (DataImportMaybe _ tyN)) = rawNameToText (rawName tyN)
