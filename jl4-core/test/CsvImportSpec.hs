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

spec :: Spec
spec = describe "IMPORT parsing" $ do
  describe "Regular module imports" $ do
    it "parses bare IMPORT name as MkImport" $ do
      imp <- firstImport "IMPORT prelude"
      case imp of
        MkImport _ n _ -> rawNameToText (rawName n) `shouldBe` "prelude"
        MkDataImport {} -> expectationFailure "Expected MkImport, got MkDataImport"

    it "parses IMPORT of a quoted-identifier filename as MkImport (no IS clause)" $ do
      imp <- firstImport "IMPORT `trades.csv`"
      case imp of
        MkImport _ n _ -> rawNameToText (rawName n) `shouldBe` "trades.csv"
        MkDataImport {} -> expectationFailure "Expected MkImport, got MkDataImport"

  describe "Tabular data imports" $ do
    it "parses IMPORT `file.csv` IS A Trade as MkDataImport (single row)" $ do
      imp <- firstImport "IMPORT `trades.csv` IS A Trade"
      case imp of
        MkDataImport _ n ty _ -> do
          rawNameToText (rawName n) `shouldBe` "trades.csv"
          case ty of
            TyApp _ rowN [] -> rawNameToText (rawName rowN) `shouldBe` "Trade"
            _ -> expectationFailure $ "Expected TyApp Trade, got: " <> show ty
        MkImport {} -> expectationFailure "Expected MkDataImport, got MkImport"

    it "parses IMPORT `file.csv` IS A LIST OF Trade as MkDataImport (multi-row)" $ do
      imp <- firstImport "IMPORT `trades.csv` IS A LIST OF Trade"
      case imp of
        MkDataImport _ _ ty _ ->
          case ty of
            TyApp _ listN [TyApp _ rowN []] -> do
              rawNameToText (rawName listN) `shouldBe` "LIST"
              rawNameToText (rawName rowN)  `shouldBe` "Trade"
            _ -> expectationFailure $ "Expected LIST OF Trade, got: " <> show ty
        MkImport {} -> expectationFailure "Expected MkDataImport, got MkImport"

    it "parses IS A type with a quoted row-type name" $ do
      imp <- firstImport "IMPORT `trades.csv` IS A LIST OF `ACTUS Trade`"
      case imp of
        MkDataImport _ _ ty _ ->
          case ty of
            TyApp _ _ [TyApp _ rowN []] ->
              rawNameToText (rawName rowN) `shouldBe` "ACTUS Trade"
            _ -> expectationFailure $ "Unexpected type shape: " <> show ty
        MkImport {} -> expectationFailure "Expected MkDataImport, got MkImport"

    it "preserves the filename in the AST" $ do
      imp <- firstImport $ Text.unlines
        [ "IMPORT `acme-orders.csv` IS A LIST OF Order"
        ]
      case imp of
        MkDataImport _ n _ _ ->
          rawNameToText (rawName n) `shouldBe` "acme-orders.csv"
        _ -> expectationFailure $ "Expected MkDataImport, got: " <> show imp
