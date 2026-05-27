{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | End-to-end test for the CSV import pipeline: parse → rewrite →
-- typecheck. Uses an in-memory VFS for both module and data file
-- lookup, so it exercises the full code path without touching the
-- LSP\/Shake or WASM backends.
module CsvIntegrationSpec (spec) where

import qualified Data.Text as Text
import L4.API.VirtualFS
import Test.Hspec

spec :: Spec
spec = describe "CSV IMPORT end-to-end" $ do
  it "type-checks a LIST OF Trade import against an existing DECLARE" $ do
    let csv = Text.unlines
          [ "notional,settled"
          , "100.5,true"
          , "200,false"
          ]
        dataVfs = vfsFromList [("trades.csv", csv)]
        source = Text.unlines
          [ "DECLARE Trade HAS"
          , "    notional IS A NUMBER,"
          , "    settled  IS A BOOLEAN"
          , ""
          , "IMPORT `trades.csv` IS A LIST OF Trade"
          ]
    case checkWithImportsAndData emptyVFS dataVfs source of
      Left errs -> expectationFailure $ "Type check failed: " <> show errs
      Right r -> r.tcdSuccess `shouldBe` True

  it "brings the binding name into scope (filename minus extension)" $ do
    let csv = Text.unlines
          [ "n,b"
          , "1,true"
          , "2,false"
          ]
        dataVfs = vfsFromList [("rows.csv", csv)]
        source = Text.unlines
          [ "DECLARE Row HAS"
          , "    n IS A NUMBER,"
          , "    b IS A BOOLEAN"
          , ""
          , "IMPORT `rows.csv` IS A LIST OF Row"
          , ""
          , "GIVETH A LIST OF Row"
          , "myRows MEANS rows"
          ]
    case checkWithImportsAndData emptyVFS dataVfs source of
      Left errs -> expectationFailure $ "Type check failed: " <> show errs
      Right r -> r.tcdSuccess `shouldBe` True

  it "binds a single record when the type is just T (no LIST)" $ do
    let csv = Text.unlines
          [ "key,value"
          , "secret,123"
          ]
        dataVfs = vfsFromList [("config.csv", csv)]
        source = Text.unlines
          [ "DECLARE Config HAS"
          , "    key   IS A STRING,"
          , "    value IS A NUMBER"
          , ""
          , "IMPORT `config.csv` IS A Config"
          ]
    case checkWithImportsAndData emptyVFS dataVfs source of
      Left errs -> expectationFailure $ "Type check failed: " <> show errs
      Right r -> r.tcdSuccess `shouldBe` True

  it "reports an error when the CSV file is missing" $ do
    let source = Text.unlines
          [ "DECLARE Row HAS x IS A NUMBER"
          , "IMPORT `missing.csv` IS A LIST OF Row"
          ]
    case checkWithImportsAndData emptyVFS emptyVFS source of
      Right _ -> expectationFailure "Expected a 'file not found' error"
      Left errs ->
        errs `shouldSatisfy` any (Text.isInfixOf "DataFileNotFound")

  it "reports an error when a declared column is missing from the CSV" $ do
    let csv = Text.unlines
          [ "a"
          , "1"
          ]
        dataVfs = vfsFromList [("x.csv", csv)]
        source = Text.unlines
          [ "DECLARE Row HAS"
          , "    a IS A NUMBER,"
          , "    b IS A NUMBER"
          , ""
          , "IMPORT `x.csv` IS A LIST OF Row"
          ]
    case checkWithImportsAndData emptyVFS dataVfs source of
      Right _ -> expectationFailure "Expected a 'missing column' error"
      Left errs ->
        errs `shouldSatisfy` any (Text.isInfixOf "HeaderMismatch")

  it "reports an error when a cell can't be coerced to the declared type" $ do
    let csv = Text.unlines
          [ "n"
          , "oops"
          ]
        dataVfs = vfsFromList [("x.csv", csv)]
        source = Text.unlines
          [ "DECLARE Row HAS n IS A NUMBER"
          , "IMPORT `x.csv` IS A LIST OF Row"
          ]
    case checkWithImportsAndData emptyVFS dataVfs source of
      Right _ -> expectationFailure "Expected a 'coercion failed' error"
      Left errs ->
        errs `shouldSatisfy` any (Text.isInfixOf "CellCoercionFailed")

  it "errors when the row type isn't DECLAREd in the module" $ do
    let csv = Text.unlines [ "n", "1" ]
        dataVfs = vfsFromList [("x.csv", csv)]
        source = "IMPORT `x.csv` IS A LIST OF Row"
    case checkWithImportsAndData emptyVFS dataVfs source of
      Right _ -> expectationFailure "Expected a 'row type not declared' error"
      Left errs ->
        errs `shouldSatisfy` any (Text.isInfixOf "RowTypeNotDeclared")

  it "handles MAYBE NUMBER columns including empty cells" $ do
    let csv = Text.unlines
          [ "score"
          , ""
          , "42"
          ]
        dataVfs = vfsFromList [("scores.csv", csv)]
        source = Text.unlines
          [ "DECLARE Score HAS score IS A MAYBE NUMBER"
          , "IMPORT `scores.csv` IS A LIST OF Score"
          ]
    case checkWithImportsAndData emptyVFS dataVfs source of
      Left errs -> expectationFailure $ "Type check failed: " <> show errs
      Right r -> r.tcdSuccess `shouldBe` True

  it "handles DATE columns via ISO 8601 strings" $ do
    let csv = Text.unlines
          [ "trade date,notional"
          , "2026-04-03,100"
          , "2026-04-04,200"
          ]
        dataVfs = vfsFromList [("trades.csv", csv)]
        source = Text.unlines
          [ "DECLARE Trade HAS"
          , "    `trade date` IS A DATE,"
          , "    notional     IS A NUMBER"
          , ""
          , "IMPORT `trades.csv` IS A LIST OF Trade"
          ]
    case checkWithImportsAndData emptyVFS dataVfs source of
      Left errs -> expectationFailure $ "Type check failed: " <> show errs
      Right r -> r.tcdSuccess `shouldBe` True

  it "handles enum-typed columns via separate DECLARE" $ do
    let csv = Text.unlines
          [ "side,notional"
          , "buy,100"
          , "sell,200"
          ]
        dataVfs = vfsFromList [("trades.csv", csv)]
        source = Text.unlines
          [ "DECLARE Side IS ONE OF buy, sell"
          , ""
          , "DECLARE Trade HAS"
          , "    side     IS A Side,"
          , "    notional IS A NUMBER"
          , ""
          , "IMPORT `trades.csv` IS A LIST OF Trade"
          ]
    case checkWithImportsAndData emptyVFS dataVfs source of
      Left errs -> expectationFailure $ "Type check failed: " <> show errs
      Right r -> r.tcdSuccess `shouldBe` True

  it "reports an error when an enum cell is outside the declared set" $ do
    let csv = Text.unlines
          [ "side"
          , "hold"
          ]
        dataVfs = vfsFromList [("trades.csv", csv)]
        source = Text.unlines
          [ "DECLARE Side IS ONE OF buy, sell"
          , "DECLARE Trade HAS side IS A Side"
          , "IMPORT `trades.csv` IS A LIST OF Trade"
          ]
    case checkWithImportsAndData emptyVFS dataVfs source of
      Right _ -> expectationFailure "Expected an 'enum value not in set' error"
      Left errs ->
        errs `shouldSatisfy` any (Text.isInfixOf "EnumCellNotInSet")

  it "lets the same row type back multiple imports" $ do
    let csv1 = Text.unlines [ "n", "1", "2" ]
        csv2 = Text.unlines [ "n", "3", "4" ]
        dataVfs = vfsFromList [("jan.csv", csv1), ("feb.csv", csv2)]
        source = Text.unlines
          [ "DECLARE Row HAS n IS A NUMBER"
          , ""
          , "IMPORT `jan.csv` IS A LIST OF Row"
          , "IMPORT `feb.csv` IS A LIST OF Row"
          ]
    case checkWithImportsAndData emptyVFS dataVfs source of
      Left errs -> expectationFailure $ "Type check failed: " <> show errs
      Right r -> r.tcdSuccess `shouldBe` True

  it "still resolves a regular IMPORT alongside data imports" $ do
    let csv = Text.unlines [ "n", "1" ]
        dataVfs = vfsFromList [("x.csv", csv)]
        source = Text.unlines
          [ "IMPORT prelude"
          , "DECLARE Row HAS n IS A NUMBER"
          , "IMPORT `x.csv` IS A LIST OF Row"
          ]
    case checkWithImportsAndData emptyVFS dataVfs source of
      Left errs -> expectationFailure $ "Type check failed: " <> show errs
      Right r -> do
        r.tcdSuccess `shouldBe` True
        length r.tcdResolvedImports `shouldBe` 1   -- prelude only; the CSV is inlined
