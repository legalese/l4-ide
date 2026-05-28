{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
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
  it "produces parseable L4 source for a LIST OF Trade with primitive columns" $ do
    let csvSrc = Text.unlines
          [ "notional,settled"
          , "100.5,true"
          , "200,false"
          ]
        moduleSrc = Text.unlines
          [ "DECLARE Trade HAS"
          , "    notional IS A NUMBER,"
          , "    settled  IS A BOOLEAN"
          , ""
          , "IMPORT `trades.csv` IS A LIST OF Trade"
          ]
    csv <- expectRight (parseCsv csvSrc)
    (ty, env) <- expectRight (extractTypeAndEnv moduleSrc)
    out <- expectRight (synthesizeFromCsv "trades.csv" Nothing ty env csv)
    let uri = toNormalizedUri (Uri "file:///synth-test")
    case execProgramParserWithHintPass uri (moduleSrc <> "\n" <> out) of
      Right _ -> pure ()
      Left errs ->
        expectationFailure $
          "Combined source failed to parse:\n" <> Text.unpack out
            <> "\n\nParse errors:\n" <> show errs

  it "produces a single-record binding when the type is just Config (no LIST)" $ do
    let csvSrc = Text.unlines
          [ "key,value"
          , "secret,123"
          ]
        moduleSrc = Text.unlines
          [ "DECLARE Config HAS"
          , "    key   IS A STRING,"
          , "    value IS A NUMBER"
          , ""
          , "IMPORT `config.csv` IS A Config"
          ]
    csv <- expectRight (parseCsv csvSrc)
    (ty, env) <- expectRight (extractTypeAndEnv moduleSrc)
    out <- expectRight (synthesizeFromCsv "config.csv" Nothing ty env csv)
    out `shouldSatisfy` Text.isInfixOf "Config WITH"
    out `shouldNotSatisfy` Text.isInfixOf "LIST"

  it "encodes DATE columns via DATE_FROM_DMY" $ do
    let csvSrc = Text.unlines [ "trade date", "2026-04-03" ]
        moduleSrc = Text.unlines
          [ "DECLARE Trade HAS `trade date` IS A DATE"
          , "IMPORT `trades.csv` IS A LIST OF Trade"
          ]
    csv <- expectRight (parseCsv csvSrc)
    (ty, env) <- expectRight (extractTypeAndEnv moduleSrc)
    out <- expectRight (synthesizeFromCsv "trades.csv" Nothing ty env csv)
    out `shouldSatisfy` Text.isInfixOf "DATE_FROM_DMY 3 4 2026"

  it "encodes MAYBE NUMBER empty cell as NOTHING and full as JUST" $ do
    let csvSrc = Text.unlines [ "match price", "", "42" ]
        moduleSrc = Text.unlines
          [ "DECLARE Trade HAS `match price` IS A MAYBE NUMBER"
          , "IMPORT `trades.csv` IS A LIST OF Trade"
          ]
    csv <- expectRight (parseCsv csvSrc)
    (ty, env) <- expectRight (extractTypeAndEnv moduleSrc)
    out <- expectRight (synthesizeFromCsv "trades.csv" Nothing ty env csv)
    out `shouldSatisfy` Text.isInfixOf "NOTHING"
    out `shouldSatisfy` Text.isInfixOf "JUST (42)"

  it "validates enum columns against the declared enum type" $ do
    let csvSrc = Text.unlines [ "side", "buy", "sell" ]
        moduleSrc = Text.unlines
          [ "DECLARE Side IS ONE OF buy, sell"
          , "DECLARE Trade HAS side IS A Side"
          , "IMPORT `trades.csv` IS A LIST OF Trade"
          ]
    csv <- expectRight (parseCsv csvSrc)
    (ty, env) <- expectRight (extractTypeAndEnv moduleSrc)
    out <- expectRight (synthesizeFromCsv "trades.csv" Nothing ty env csv)
    out `shouldSatisfy` Text.isInfixOf "side IS buy"
    out `shouldSatisfy` Text.isInfixOf "side IS sell"

  it "rejects an enum cell that's outside the declared set" $ do
    let csvSrc = Text.unlines [ "side", "hold" ]
        moduleSrc = Text.unlines
          [ "DECLARE Side IS ONE OF buy, sell"
          , "DECLARE Trade HAS side IS A Side"
          , "IMPORT `trades.csv` IS A LIST OF Trade"
          ]
    csv <- expectRight (parseCsv csvSrc)
    (ty, env) <- expectRight (extractTypeAndEnv moduleSrc)
    case synthesizeFromCsv "trades.csv" Nothing ty env csv of
      Left EnumCellNotInSet { ceValue = "hold" } -> pure ()
      other -> expectationFailure $ "expected EnumCellNotInSet, got: " <> show other

  it "rejects a CSV with extra columns" $ do
    let csvSrc = Text.unlines [ "a,b", "1,2" ]
        moduleSrc = Text.unlines
          [ "DECLARE Row HAS a IS A NUMBER"
          , "IMPORT `x.csv` IS A LIST OF Row"
          ]
    csv <- expectRight (parseCsv csvSrc)
    (ty, env) <- expectRight (extractTypeAndEnv moduleSrc)
    case synthesizeFromCsv "x.csv" Nothing ty env csv of
      Left HeaderMismatch { ceUnknownColumns = ["b"] } -> pure ()
      other -> expectationFailure $ "expected HeaderMismatch, got: " <> show other

  it "rejects a CSV missing a declared column" $ do
    let csvSrc = Text.unlines [ "a", "1" ]
        moduleSrc = Text.unlines
          [ "DECLARE Row HAS a IS A NUMBER, b IS A NUMBER"
          , "IMPORT `x.csv` IS A LIST OF Row"
          ]
    csv <- expectRight (parseCsv csvSrc)
    (ty, env) <- expectRight (extractTypeAndEnv moduleSrc)
    case synthesizeFromCsv "x.csv" Nothing ty env csv of
      Left HeaderMismatch { ceMissingColumns = ["b"] } -> pure ()
      other -> expectationFailure $ "expected HeaderMismatch, got: " <> show other

  it "rejects a non-numeric cell in a NUMBER column" $ do
    let csvSrc = Text.unlines [ "n", "oops" ]
        moduleSrc = Text.unlines
          [ "DECLARE Row HAS n IS A NUMBER"
          , "IMPORT `x.csv` IS A LIST OF Row"
          ]
    csv <- expectRight (parseCsv csvSrc)
    (ty, env) <- expectRight (extractTypeAndEnv moduleSrc)
    case synthesizeFromCsv "x.csv" Nothing ty env csv of
      Left CellCoercionFailed { ceType = "NUMBER", ceValue = "oops" } -> pure ()
      other -> expectationFailure $ "expected CellCoercionFailed, got: " <> show other

  it "errors when the IMPORT references a row type that isn't DECLAREd" $ do
    let csvSrc = Text.unlines [ "n", "1" ]
        moduleSrc = "IMPORT `x.csv` IS A LIST OF Row"
    csv <- expectRight (parseCsv csvSrc)
    (ty, env) <- expectRight (extractTypeAndEnv moduleSrc)
    case synthesizeFromCsv "x.csv" Nothing ty env csv of
      Left RowTypeNotDeclared { ceTypeName = "Row" } -> pure ()
      other -> expectationFailure $ "expected RowTypeNotDeclared, got: " <> show other

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

expectRight :: Show e => Either e a -> IO a
expectRight = either (\e -> expectationFailure (show e) >> error "unreachable") pure

-- | Parse an L4 source string and pull out:
--
--   * the user-written type expression from the first 'MkDataImport';
--   * a 'DeclareEnv' built from the module's existing DECLAREs.
extractTypeAndEnv :: Text -> Either String (Type' Name, DeclareEnv)
extractTypeAndEnv src = do
  let uri = toNormalizedUri (Uri "file:///schema-extract")
  case execProgramParserWithHintPass uri src of
    Left errs -> Left ("parse failed: " <> show errs)
    Right (m@(MkModule _ _ (MkSection _ _ _ decls)), _, _) ->
      case [ty | Import _ (MkDataImport _ _ _ ty _) <- decls] of
        (ty : _) -> Right (ty, buildDeclareEnv m)
        []       -> Left "no MkDataImport found"
