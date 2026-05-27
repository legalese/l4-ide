{-# LANGUAGE OverloadedStrings #-}
-- | Minimal RFC-4180-style CSV / TSV parser.
--
-- The parser is intentionally small (no streaming, no @cassava@
-- dependency) and is intended to be replaced by a streaming parser
-- once we start exercising the fast path on multi-million-row inputs.
-- For correctness, it does handle the awkward parts of CSV that
-- bite typical hand-rolled parsers: quoted fields, embedded
-- commas/tabs, doubled quotes (@\"\"@) as escaped quotes, and
-- CRLF line endings inside quoted fields.
module L4.DataImport.Csv
  ( parseCsv
  , parseTsv
  , parseDelimited
  , CsvParseError(..)
  , CsvDoc(..)
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Text as T

-- | A parsed CSV/TSV document: the header row (column names) plus
-- the data rows. Each row is guaranteed to have the same number of
-- cells as the header (the parser pads short rows with empty cells
-- and errors on rows that are too long).
data CsvDoc = MkCsvDoc
  { csvHeader :: [Text]
  , csvRows   :: [[Text]]  -- ^ data rows only; each row has @length csvHeader@ cells
  }
  deriving stock (Eq, Show)

data CsvParseError
  = CsvEmpty
    -- ^ The input is empty or has only whitespace.
  | CsvRowTooLong { csvLine :: !Int, csvExpected :: !Int, csvActual :: !Int }
    -- ^ A data row has more cells than the header.
  | CsvUnterminatedQuote { csvLine :: !Int }
    -- ^ A quoted field is missing its closing quote at end of input.
  deriving stock (Eq, Show)

-- | Parse CSV (comma-separated) bytes into a 'CsvDoc'.
parseCsv :: Text -> Either CsvParseError CsvDoc
parseCsv = parseDelimited ','

-- | Parse TSV (tab-separated) bytes into a 'CsvDoc'.
parseTsv :: Text -> Either CsvParseError CsvDoc
parseTsv = parseDelimited '\t'

-- | Parse delimited text with an arbitrary single-character delimiter.
--
-- The parser:
--
--   * treats the first non-blank line as the header row;
--   * tolerates trailing blank lines and skips entirely-blank data lines
--     /only when the header has more than one column/ — for a single-
--     column file an empty data row is a legitimate empty cell, not
--     blank input;
--   * pads short rows with empty cells (matching the spirit of @cassava@'s
--     @decodeWith@ defaults);
--   * rejects rows that contain more cells than the header.
parseDelimited :: Char -> Text -> Either CsvParseError CsvDoc
parseDelimited delim input = do
  rows <- parseRows delim input
  case dropWhile null rows of
    [] -> Left CsvEmpty
    (hdr : rest) -> do
      let n = length hdr
          -- For multi-column files, treat all-empty-cells rows as
          -- accidental blank lines and drop them. For single-column
          -- files, those rows are valid data (the one cell really is
          -- empty), so keep them.
          isBlankRow row = all T.null row && (n > 1 || null row)
          dataRows = filter (not . isBlankRow) rest
      checked <- traverse (checkAndPad n) (zip [2 :: Int ..] dataRows)
      Right MkCsvDoc { csvHeader = hdr, csvRows = checked }
  where
    checkAndPad :: Int -> (Int, [Text]) -> Either CsvParseError [Text]
    checkAndPad n (lineNo, row)
      | length row > n =
          Left CsvRowTooLong { csvLine = lineNo, csvExpected = n, csvActual = length row }
      | length row < n = Right (row <> replicate (n - length row) "")
      | otherwise      = Right row

-- ----------------------------------------------------------------------------
-- Row tokenisation
-- ----------------------------------------------------------------------------

-- | Tokenise the entire input into rows of cells. Handles quoted fields,
-- embedded delimiters/newlines, and doubled-quote escapes. The returned
-- rows are in source order; empty trailing rows are preserved (and
-- filtered out later by 'parseDelimited').
parseRows :: Char -> Text -> Either CsvParseError [[Text]]
parseRows delim t0 = go 1 t0 [] []
  where
    -- Args: current 1-based line number, remaining input,
    --       cells of the in-progress row (reversed), all completed rows (reversed).
    go :: Int -> Text -> [Text] -> [[Text]] -> Either CsvParseError [[Text]]
    go _ "" curRow rows =
      Right $ reverse (reverse curRow : rows)
    go ln rest curRow rows =
      case T.uncons rest of
        Nothing -> Right $ reverse (reverse curRow : rows)
        Just (c, rest')
          | c == '"' -> do
              (cell, rest'', linesConsumed) <- readQuoted ln rest'
              case T.uncons rest'' of
                Just (c2, rest''') | c2 == delim ->
                  go (ln + linesConsumed) rest''' (cell : curRow) rows
                Just (c2, rest''') | c2 == '\n' ->
                  go (ln + linesConsumed + 1) rest''' [] (reverse (cell : curRow) : rows)
                Just (c2, rest''') | c2 == '\r' ->
                  -- handle CRLF; consume a following \n if present
                  let rest4 = case T.uncons rest''' of
                        Just ('\n', r) -> r
                        _              -> rest'''
                  in go (ln + linesConsumed + 1) rest4 [] (reverse (cell : curRow) : rows)
                Nothing ->
                  Right $ reverse (reverse (cell : curRow) : rows)
                _ ->
                  -- garbage after closing quote: treat as end of cell
                  go (ln + linesConsumed) rest'' (cell : curRow) rows
          | c == delim ->
              go ln rest' ("" : curRow) rows
          | c == '\n' ->
              go (ln + 1) rest' [] (reverse ("" : curRow) : rows)
          | c == '\r' ->
              let rest'' = case T.uncons rest' of
                    Just ('\n', r) -> r
                    _              -> rest'
              in go (ln + 1) rest'' [] (reverse ("" : curRow) : rows)
          | otherwise -> do
              let (cell, rest'') = readUnquoted delim rest
              case T.uncons rest'' of
                Nothing ->
                  Right $ reverse (reverse (cell : curRow) : rows)
                Just (c2, rest''') | c2 == delim ->
                  go ln rest''' (cell : curRow) rows
                Just (c2, rest''') | c2 == '\n' ->
                  go (ln + 1) rest''' [] (reverse (cell : curRow) : rows)
                Just (c2, rest''') | c2 == '\r' ->
                  let rest4 = case T.uncons rest''' of
                        Just ('\n', r) -> r
                        _              -> rest'''
                  in go (ln + 1) rest4 [] (reverse (cell : curRow) : rows)
                _ ->
                  go ln rest'' (cell : curRow) rows

-- | Read an unquoted cell: characters up to but not including the next
-- delimiter, CR, or LF.
readUnquoted :: Char -> Text -> (Text, Text)
readUnquoted delim = T.span (\c -> c /= delim && c /= '\n' && c /= '\r')

-- | Read the body of a quoted cell. The leading @\"@ has already been
-- consumed by the caller; this reads up to and including the closing
-- @\"@ that is not part of a doubled-quote escape. Returns the unescaped
-- cell text, the input remaining after the closing quote, and the
-- number of embedded newlines that were consumed (so the line counter
-- stays accurate for diagnostics).
readQuoted :: Int -> Text -> Either CsvParseError (Text, Text, Int)
readQuoted startLine = goq 0 mempty
  where
    goq :: Int -> Text -> Text -> Either CsvParseError (Text, Text, Int)
    goq linesConsumed acc t =
      case T.uncons t of
        Nothing -> Left CsvUnterminatedQuote { csvLine = startLine }
        Just ('"', rest) ->
          case T.uncons rest of
            Just ('"', rest') ->
              -- doubled quote = literal quote
              goq linesConsumed (acc <> "\"") rest'
            _ ->
              Right (acc, rest, linesConsumed)
        Just ('\n', rest) ->
          goq (linesConsumed + 1) (acc <> "\n") rest
        Just (c, rest) ->
          -- batch up the run of non-special characters for speed
          let (chunk, after) = Text.break (\ch -> ch == '"' || ch == '\n') rest
              consumed = chunk
          in goq linesConsumed (acc <> T.singleton c <> consumed) after
