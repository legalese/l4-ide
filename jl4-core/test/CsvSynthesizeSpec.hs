{-# LANGUAGE OverloadedStrings #-}
module CsvSynthesizeSpec (spec) where

import Base
import qualified Data.Text as Text
import L4.DataImport.Csv
import L4.DataImport.Synthesize
import L4.Parser (execProgramParserWithHintPass)
import L4.Syntax
import Test.Hspec

spec :: Spec
spec = do
  csvParserSpec
  synthesizeSpec

-- ----------------------------------------------------------------------------
-- CSV parser
-- ----------------------------------------------------------------------------

csvParserSpec :: Spec
csvParserSpec = describe "CSV parser" $ do
  it "parses header + simple rows" $ do
    let src = "a,b,c\n1,2,3\n4,5,6\n"
    case parseCsv src of
      Right doc -> do
        doc.csvHeader `shouldBe` ["a","b","c"]
        doc.csvRows   `shouldBe` [["1","2","3"], ["4","5","6"]]
      Left e -> expectationFailure (show e)

  it "handles quoted fields with embedded commas" $ do
    let src = "name,note\n\"Alice\",\"hello, world\"\n"
    case parseCsv src of
      Right doc -> doc.csvRows `shouldBe` [["Alice", "hello, world"]]
      Left e -> expectationFailure (show e)

  it "handles doubled quotes as escapes" $ do
    let src = "q\n\"she said \"\"hi\"\"\"\n"
    case parseCsv src of
      Right doc -> doc.csvRows `shouldBe` [["she said \"hi\""]]
      Left e -> expectationFailure (show e)

  it "parses TSV with tab delimiter" $ do
    let src = "a\tb\n1\t2\n"
    case parseTsv src of
      Right doc -> do
        doc.csvHeader `shouldBe` ["a","b"]
        doc.csvRows   `shouldBe` [["1","2"]]
      Left e -> expectationFailure (show e)

  it "rejects empty input" $ do
    parseCsv "" `shouldBe` Left CsvEmpty

-- ----------------------------------------------------------------------------
-- Synthesizer
-- ----------------------------------------------------------------------------

synthesizeSpec :: Spec
synthesizeSpec = describe "CSV → L4 synthesizer" $ do
  it "produces parseable L4 source for a simple typed import" $ do
    let csvSrc = Text.unlines
          [ "notional,settled"
          , "100.5,true"
          , "200,false"
          ]
    csv <- expectRight (parseCsv csvSrc)
    schema <- expectRight (extractSchema "IMPORT `trades.csv` AS Trade HAS notional IS A NUMBER, settled IS A BOOLEAN")
    out <- expectRight (synthesizeFromCsv "trades.csv" schema csv)
    let uri = toNormalizedUri (Uri "file:///synth-test")
    case execProgramParserWithHintPass uri out of
      Right _ -> pure ()
      Left errs ->
        expectationFailure $
          "Synthesised source failed to parse:\n" <> Text.unpack out
            <> "\n\nParse errors:\n" <> show errs

  it "encodes DATE columns via DATE_FROM_DMY" $ do
    let csvSrc = Text.unlines
          [ "trade date"
          , "2026-04-03"
          ]
    csv <- expectRight (parseCsv csvSrc)
    schema <- expectRight (extractSchema "IMPORT `trades.csv` AS Trade HAS `trade date` IS A DATE")
    out <- expectRight (synthesizeFromCsv "trades.csv" schema csv)
    out `shouldSatisfy` Text.isInfixOf "DATE_FROM_DMY 3 4 2026"

  it "encodes MAYBE NUMBER empty cell as NOTHING" $ do
    let csvSrc = Text.unlines
          [ "match price"
          , ""           -- empty cell
          , "42"
          ]
    csv <- expectRight (parseCsv csvSrc)
    schema <- expectRight (extractSchema "IMPORT `trades.csv` AS Trade HAS `match price` IS A MAYBE NUMBER")
    out <- expectRight (synthesizeFromCsv "trades.csv" schema csv)
    out `shouldSatisfy` Text.isInfixOf "NOTHING"
    out `shouldSatisfy` Text.isInfixOf "42"

  it "rejects a CSV with extra columns" $ do
    let csvSrc = Text.unlines
          [ "a,b"
          , "1,2"
          ]
    csv <- expectRight (parseCsv csvSrc)
    schema <- expectRight (extractSchema "IMPORT `x.csv` AS Row HAS a IS A NUMBER")
    case synthesizeFromCsv "x.csv" schema csv of
      Left HeaderMismatch { ceUnknownColumns = ["b"] } -> pure ()
      other -> expectationFailure $ "expected HeaderMismatch, got: " <> show other

  it "rejects a CSV missing a declared column" $ do
    let csvSrc = Text.unlines [ "a", "1" ]
    csv <- expectRight (parseCsv csvSrc)
    schema <- expectRight (extractSchema "IMPORT `x.csv` AS Row HAS a IS A NUMBER, b IS A NUMBER")
    case synthesizeFromCsv "x.csv" schema csv of
      Left HeaderMismatch { ceMissingColumns = ["b"] } -> pure ()
      other -> expectationFailure $ "expected HeaderMismatch, got: " <> show other

  it "rejects a non-numeric cell in a NUMBER column" $ do
    let csvSrc = Text.unlines [ "n", "oops" ]
    csv <- expectRight (parseCsv csvSrc)
    schema <- expectRight (extractSchema "IMPORT `x.csv` AS Row HAS n IS A NUMBER")
    case synthesizeFromCsv "x.csv" schema csv of
      Left CellCoercionFailed { ceType = "NUMBER", ceValue = "oops" } -> pure ()
      other -> expectationFailure $ "expected CellCoercionFailed, got: " <> show other

  it "emits a DECLARE … IS ONE OF for an enum column" $ do
    let csvSrc = Text.unlines [ "side", "buy", "sell" ]
    csv <- expectRight (parseCsv csvSrc)
    schema <- expectRight (extractSchema "IMPORT `trades.csv` AS Trade HAS side IS ONE OF buy, sell")
    out <- expectRight (synthesizeFromCsv "trades.csv" schema csv)
    out `shouldSatisfy` Text.isInfixOf "DECLARE Trade_side IS ONE OF buy, sell"
    out `shouldSatisfy` Text.isInfixOf "side IS A Trade_side"

  it "rejects a cell whose value is not in the enum's set" $ do
    let csvSrc = Text.unlines [ "side", "hold" ]
    csv <- expectRight (parseCsv csvSrc)
    schema <- expectRight (extractSchema "IMPORT `trades.csv` AS Trade HAS side IS ONE OF buy, sell")
    case synthesizeFromCsv "trades.csv" schema csv of
      Left EnumCellNotInSet { ceValue = "hold", ceAllowed = ["buy", "sell"] } -> pure ()
      other -> expectationFailure $ "expected EnumCellNotInSet, got: " <> show other

  it "treats an empty enum cell as a required-column error" $ do
    let csvSrc = Text.unlines [ "side", "" ]
    csv <- expectRight (parseCsv csvSrc)
    schema <- expectRight (extractSchema "IMPORT `trades.csv` AS Trade HAS side IS ONE OF buy, sell")
    case synthesizeFromCsv "trades.csv" schema csv of
      Left EmptyCellInRequiredColumn { ceColumn = "side" } -> pure ()
      other -> expectationFailure $ "expected EmptyCellInRequiredColumn, got: " <> show other

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

expectRight :: Show e => Either e a -> IO a
expectRight = either (\e -> expectationFailure (show e) >> error "unreachable") pure

-- | Parse an IMPORT line and return its DataImportSchema.
extractSchema :: Text -> Either String DataImportSchema
extractSchema src = do
  let uri = toNormalizedUri (Uri "file:///schema-extract")
  case execProgramParserWithHintPass uri src of
    Left errs -> Left ("parse failed: " <> show errs)
    Right (MkModule _ _ (MkSection _ _ _ decls), _, _) ->
      case [s | Import _ (MkDataImport _ _ s _) <- decls] of
        (s : _) -> Right s
        []      -> Left "no MkDataImport found"
