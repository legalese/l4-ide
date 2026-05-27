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
  it "type-checks a module that imports a CSV with a fully declared schema" $ do
    let csv = Text.unlines
          [ "notional,settled"
          , "100.5,true"
          , "200,false"
          ]
        dataVfs = vfsFromList [("trades.csv", csv)]
        source = Text.unlines
          [ "IMPORT `trades.csv` AS Trade HAS"
          , "    notional IS A NUMBER,"
          , "    settled  IS A BOOLEAN"
          ]
    case checkWithImportsAndData emptyVFS dataVfs source of
      Left errs -> expectationFailure $ "Type check failed: " <> show errs
      Right r -> r.tcdSuccess `shouldBe` True

  it "brings the row type and binding into scope for the importing module" $ do
    let csv = Text.unlines
          [ "n,b"
          , "1,true"
          , "2,false"
          ]
        dataVfs = vfsFromList [("rows.csv", csv)]
        source = Text.unlines
          [ "IMPORT `rows.csv` AS Row HAS"
          , "    n IS A NUMBER,"
          , "    b IS A BOOLEAN"
          , ""
          , "GIVETH A LIST OF Row"
          , "myRows MEANS rows"
          ]
    case checkWithImportsAndData emptyVFS dataVfs source of
      Left errs -> expectationFailure $ "Type check failed: " <> show errs
      Right r -> r.tcdSuccess `shouldBe` True

  it "reports an error when the CSV file is missing" $ do
    let source = "IMPORT `missing.csv` AS Row HAS x IS A NUMBER"
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
          [ "IMPORT `x.csv` AS Row HAS"
          , "    a IS A NUMBER,"
          , "    b IS A NUMBER"
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
        source = "IMPORT `x.csv` AS Row HAS n IS A NUMBER"
    case checkWithImportsAndData emptyVFS dataVfs source of
      Right _ -> expectationFailure "Expected a 'coercion failed' error"
      Left errs ->
        errs `shouldSatisfy` any (Text.isInfixOf "CellCoercionFailed")

  it "handles MAYBE NUMBER columns including empty cells" $ do
    let csv = Text.unlines
          [ "score"
          , ""
          , "42"
          ]
        dataVfs = vfsFromList [("scores.csv", csv)]
        source = Text.unlines
          [ "IMPORT `scores.csv` AS Score HAS score IS A MAYBE NUMBER"
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
          [ "IMPORT `trades.csv` AS Trade HAS"
          , "    `trade date` IS A DATE,"
          , "    notional     IS A NUMBER"
          ]
    case checkWithImportsAndData emptyVFS dataVfs source of
      Left errs -> expectationFailure $ "Type check failed: " <> show errs
      Right r -> r.tcdSuccess `shouldBe` True

  it "still resolves a regular IMPORT alongside data imports" $ do
    let csv = Text.unlines
          [ "n"
          , "1"
          ]
        dataVfs = vfsFromList [("x.csv", csv)]
        source = Text.unlines
          [ "IMPORT prelude"
          , "IMPORT `x.csv` AS Row HAS n IS A NUMBER"
          ]
    case checkWithImportsAndData emptyVFS dataVfs source of
      Left errs -> expectationFailure $ "Type check failed: " <> show errs
      Right r -> do
        r.tcdSuccess `shouldBe` True
        length r.tcdResolvedImports `shouldBe` 1   -- prelude only; the CSV is inlined
