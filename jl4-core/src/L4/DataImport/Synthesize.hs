{-# LANGUAGE OverloadedStrings #-}
-- | Convert a parsed CSV document plus a user-supplied 'DataImportSchema'
-- into the L4 source text that the rewrite pass splices into the
-- importing module in place of the @IMPORT \`file.csv\` AS …@ statement.
--
-- The synthesised text is plain L4 source, so it flows through the
-- existing parser and type-checker without any new AST surface.
-- Producing source text (rather than constructing the AST directly)
-- keeps the responsibility for source ranges, annotations, and mixfix
-- registry interactions firmly on the side of the parser.
--
-- This module implements the /fast path/ only: every column in the
-- schema must be declared and the parser coerces each cell strictly
-- according to its declared type, failing on the first non-compliant
-- row. The auto-sense path (whole-file type inference) lives in a
-- sibling module that has not been written yet.
module L4.DataImport.Synthesize
  ( synthesizeFromCsv
  , bindingNameFromFilename
  , CoerceError(..)
  ) where

import Base
import qualified Base.Text as Text
import Control.Applicative ((<|>))
import qualified Data.Text as T
import qualified Data.Text.Read as TR

import L4.DataImport.Csv (CsvDoc(..))
import L4.Syntax

-- ----------------------------------------------------------------------------
-- Error type
-- ----------------------------------------------------------------------------

-- | Errors that can occur while coercing a CSV document into L4 source.
data CoerceError
  = HeaderMismatch
      { ceMissingColumns  :: ![Text]  -- ^ declared in schema but not in CSV
      , ceUnknownColumns  :: ![Text]  -- ^ present in CSV but not in schema
      }
  | UnsupportedPrimType
      { ceTypeName :: !Text
      , ceField    :: !Text
      }
  | CellCoercionFailed
      { ceRow      :: !Int    -- ^ 1-based row number within data rows
      , ceColumn   :: !Text   -- ^ column header
      , ceType     :: !Text   -- ^ declared L4 type
      , ceValue    :: !Text   -- ^ raw cell text
      , ceReason   :: !Text   -- ^ short human explanation
      }
  | EmptyCellInRequiredColumn
      { ceRow    :: !Int
      , ceColumn :: !Text
      , ceType   :: !Text
      }
  | EnumCellNotInSet
      { ceRow      :: !Int
      , ceColumn   :: !Text
      , ceValue    :: !Text
      , ceAllowed  :: ![Text]
      }
  deriving stock (Eq, Show)

-- ----------------------------------------------------------------------------
-- Top-level synthesis
-- ----------------------------------------------------------------------------

-- | Derive the binding name from the filename token by stripping the
-- @.csv@ or @.tsv@ extension. The result is wrapped in backticks so
-- that filenames containing punctuation or spaces (which the lexer
-- already accepts inside backticks at the IMPORT site) remain
-- well-formed identifiers in the synthesised source.
bindingNameFromFilename :: Text -> Text
bindingNameFromFilename t =
  let stripped = fromMaybe t $
        Text.stripSuffix ".csv" t <|> Text.stripSuffix ".tsv" t
  in renderQuotedIfNeeded stripped

-- | Synthesise the L4 source text that declares the row type and binds
-- the parsed list of records to a top-level value.
--
-- The output is a snippet (not a complete module) that the rewrite
-- pass splices into the importing module's top-level declarations.
-- It always contains exactly one 'Declare' and one 'Decide'.
synthesizeFromCsv
  :: Text          -- ^ filename text (e.g. @\"trades.csv\"@), used to derive the binding name
  -> DataImportSchema
  -> CsvDoc
  -> Either CoerceError Text
synthesizeFromCsv filename (MkDataImportSchema _ rowN fields) doc = do
  -- Column-name validation: every declared field must appear in the header.
  let declaredCols = [ rawNameToText (rawName fn) | MkDataImportField _ fn _ <- fields ]
      headerCols   = doc.csvHeader
      missing      = filter (`notElem` headerCols) declaredCols
      unknown      = filter (`notElem` declaredCols) headerCols
  unless (null missing && null unknown) $
    Left HeaderMismatch { ceMissingColumns = missing, ceUnknownColumns = unknown }

  -- Build a header→index map so we can pluck declared fields from each row
  -- regardless of CSV column order.
  let columnIndex :: Text -> Maybe Int
      columnIndex name' = lookup name' (zip headerCols [0 :: Int ..])

      rowTypeRaw = rawNameToText (rawName rowN)

  -- Coerce every row according to the declared schema. A row is a list of
  -- (field-name, expression-text) pairs.
  rowBodies <- traverse (coerceRow rowTypeRaw fields columnIndex) (zip [1 :: Int ..] doc.csvRows)

  let rowTypeText = renderQuotedIfNeeded rowTypeRaw
      fieldsText  = renderFieldDecls rowTypeRaw fields
      listText    = renderList rowTypeText rowBodies
      bindingText = bindingNameFromFilename filename
      enumDecls   = renderEnumDecls rowTypeRaw fields
  pure $ T.unlines $
    enumDecls <>
    [ "DECLARE " <> rowTypeText <> " HAS"
    , indent 4 fieldsText
    , ""
    , "GIVETH A LIST OF " <> rowTypeText
    , bindingText <> " MEANS"
    , indent 4 listText
    ]

-- | Synthetic enum type name for an inline @ONE OF@ column. Uses
-- @<RowType>_<colName>@ so that two CSV imports defining a column
-- with the same name but different value sets don't clash. The
-- @<RowType>@ prefix is the user-written row type name (NOT
-- back-tick-rewritten), so the user can refer to the enum type from
-- their own code by guessing the name from the row + column.
enumTypeName :: Text -> Text -> Text
enumTypeName rowTypeRaw colName = rowTypeRaw <> "_" <> colName

-- | Emit a top-level @DECLARE EnumName IS ONE OF v1, v2, …@ for every
-- inline enum column in the schema.
renderEnumDecls :: Text -> [DataImportField] -> [Text]
renderEnumDecls rowTypeRaw fs =
  concat
    [ [ "DECLARE "
        <> renderQuotedIfNeeded (enumTypeName rowTypeRaw (rawNameToText (rawName fn)))
        <> " IS ONE OF "
        <> T.intercalate ", " (map (rawNameToText . rawName) ctors)
      , ""
      ]
    | MkDataImportField _ fn (DataImportEnum _ ctors) <- fs
    ]

-- ----------------------------------------------------------------------------
-- Row-level coercion
-- ----------------------------------------------------------------------------

-- | Coerce one CSV row into a list of (field-name, expression-text) pairs.
coerceRow
  :: Text                       -- ^ row type name (for enum naming)
  -> [DataImportField]
  -> (Text -> Maybe Int)
  -> (Int, [Text])
  -> Either CoerceError [(Text, Text)]
coerceRow rowTypeRaw fields colIdx (rn, cells) =
  traverse (oneField rowTypeRaw rn cells colIdx) fields

oneField
  :: Text
  -> Int
  -> [Text]
  -> (Text -> Maybe Int)
  -> DataImportField
  -> Either CoerceError (Text, Text)
oneField _rowTypeRaw rowNo cells colIdx (MkDataImportField _ fn ty) = do
  let colName = rawNameToText (rawName fn)
      cell    = fromMaybe "" (colIdx colName >>= safeIndex cells)
  exprText <- coerceCell rowNo colName ty cell
  pure (colName, exprText)

safeIndex :: [a] -> Int -> Maybe a
safeIndex xs i
  | i >= 0, i < length xs = Just (xs !! i)
  | otherwise             = Nothing

-- | Coerce one cell into its L4 expression text, given the declared
-- column type. Returns either the L4 expression text or an explanation
-- of why the cell could not be interpreted as that type.
coerceCell :: Int -> Text -> DataImportType -> Text -> Either CoerceError Text
coerceCell rowNo colName ty raw =
  let trimmed = T.strip raw
  in case ty of
    DataImportPrim _ tyN ->
      coercePrim rowNo colName (rawNameToText (rawName tyN)) trimmed
    DataImportMaybe _ tyN ->
      -- MAYBE has two constructors in L4: NOTHING and JUST. There is no
      -- implicit lift from @T@ to @MAYBE T@, so we must explicitly wrap
      -- non-empty cells in JUST.
      if T.null trimmed
        then Right "NOTHING"
        else do
          inner <- coercePrim rowNo colName (rawNameToText (rawName tyN)) trimmed
          pure $ "JUST (" <> inner <> ")"
    DataImportEnum _ ctors -> coerceEnum rowNo colName ctors trimmed

coerceEnum :: Int -> Text -> [Name] -> Text -> Either CoerceError Text
coerceEnum rowNo colName ctors raw
  | T.null raw =
      Left EmptyCellInRequiredColumn { ceRow = rowNo, ceColumn = colName, ceType = "ONE OF …" }
  | raw `elem` ctorTexts = Right (renderQuotedIfNeeded raw)
  | otherwise = Left EnumCellNotInSet
      { ceRow = rowNo, ceColumn = colName, ceValue = raw, ceAllowed = ctorTexts }
  where
    ctorTexts = map (rawNameToText . rawName) ctors

coercePrim :: Int -> Text -> Text -> Text -> Either CoerceError Text
coercePrim rowNo colName tyName raw
  | T.null raw =
      Left EmptyCellInRequiredColumn { ceRow = rowNo, ceColumn = colName, ceType = tyName }
  | otherwise = case tyName of
      "NUMBER"  -> coerceNumber  rowNo colName raw
      "STRING"  -> Right (renderStringLit raw)
      "BOOLEAN" -> coerceBoolean rowNo colName raw
      "DATE"    -> coerceDate    rowNo colName raw
      other -> Left UnsupportedPrimType { ceTypeName = other, ceField = colName }

coerceNumber :: Int -> Text -> Text -> Either CoerceError Text
coerceNumber rowNo colName raw =
  case TR.signed TR.rational raw of
    Right (n, rest) | T.null (T.strip rest) ->
      Right (T.pack (showNumber (n :: Double)))
    _ -> Left CellCoercionFailed
      { ceRow = rowNo, ceColumn = colName, ceType = "NUMBER", ceValue = raw
      , ceReason = "expected a numeric literal"
      }
  where
    -- Render without trailing zeros or scientific notation when reasonable.
    showNumber d
      | d == fromIntegral (round d :: Integer) = show (round d :: Integer)
      | otherwise = show d

coerceBoolean :: Int -> Text -> Text -> Either CoerceError Text
coerceBoolean rowNo colName raw =
  case T.toLower raw of
    "true"  -> Right "TRUE"
    "false" -> Right "FALSE"
    "1"     -> Right "TRUE"
    "0"     -> Right "FALSE"
    "yes"   -> Right "TRUE"
    "no"    -> Right "FALSE"
    "y"     -> Right "TRUE"
    "n"     -> Right "FALSE"
    _ -> Left CellCoercionFailed
      { ceRow = rowNo, ceColumn = colName, ceType = "BOOLEAN", ceValue = raw
      , ceReason = "expected TRUE/FALSE (also accepted: 1/0, yes/no, y/n)"
      }

coerceDate :: Int -> Text -> Text -> Either CoerceError Text
coerceDate rowNo colName raw =
  -- ISO 8601 only: YYYY-MM-DD. Anything else is rejected — the user can
  -- always override with a custom converter once we ship one, but
  -- silent format guessing is the right thing to disallow for a
  -- law-as-code language.
  case T.splitOn "-" raw of
    [yearT, monthT, dayT]
      | T.length yearT == 4
      , T.length monthT == 2 || T.length monthT == 1
      , T.length dayT   == 2 || T.length dayT   == 1
      , Right (y, "") <- TR.decimal yearT
      , Right (m, "") <- TR.decimal monthT
      , Right (d, "") <- TR.decimal dayT
      , (m :: Int) >= 1, m <= 12
      , (d :: Int) >= 1, d <= 31
      , (y :: Int) >= 1
      -> Right $ "DATE_FROM_DMY " <> T.pack (show d)
                              <> " " <> T.pack (show m)
                              <> " " <> T.pack (show y)
    _ -> Left CellCoercionFailed
      { ceRow = rowNo, ceColumn = colName, ceType = "DATE", ceValue = raw
      , ceReason = "expected ISO 8601 date (YYYY-MM-DD)"
      }

-- ----------------------------------------------------------------------------
-- Source rendering
-- ----------------------------------------------------------------------------

-- | A name needs backtick quoting if it contains characters that the
-- L4 lexer would not accept as part of a bare identifier. We err on
-- the safe side and quote whenever the name has anything other than
-- alphanumerics and underscores.
needsBackticks :: Text -> Bool
needsBackticks t =
  T.null t || not (T.all goodChar t)
  where
    goodChar c = (c >= 'a' && c <= 'z')
              || (c >= 'A' && c <= 'Z')
              || (c >= '0' && c <= '9')
              || c == '_'

renderQuotedIfNeeded :: Text -> Text
renderQuotedIfNeeded t
  | needsBackticks t = "`" <> t <> "`"
  | otherwise        = t

renderFieldDecls :: Text -> [DataImportField] -> Text
renderFieldDecls rowTypeRaw fs = T.intercalate ",\n" (map renderOne fs)
  where
    renderOne (MkDataImportField _ fn ty) =
      let colName = rawNameToText (rawName fn)
      in renderQuotedIfNeeded colName
           <> " IS A "
           <> renderColumnType rowTypeRaw colName ty

renderColumnType :: Text -> Text -> DataImportType -> Text
renderColumnType _ _ (DataImportPrim  _ tyN) = rawNameToText (rawName tyN)
renderColumnType _ _ (DataImportMaybe _ tyN) = "MAYBE " <> rawNameToText (rawName tyN)
renderColumnType rowTypeRaw colName (DataImportEnum _ _) =
  renderQuotedIfNeeded (enumTypeName rowTypeRaw colName)

-- | Render the list of row constructors. Produces:
--
-- @
-- LIST
--     Trade WITH f1 IS v1, f2 IS v2,
--     Trade WITH f1 IS v1, f2 IS v2
-- @
renderList :: Text -> [[(Text, Text)]] -> Text
renderList _ [] = "LIST EMPTY"
renderList rowTypeText rows =
  "LIST\n" <> T.intercalate ",\n" (map (("    " <>) . renderRowConstructor rowTypeText) rows)

renderRowConstructor :: Text -> [(Text, Text)] -> Text
renderRowConstructor rowTypeText pairs =
  -- Each row is parenthesised so the trailing comma between rows is
  -- read as a list separator instead of being attached to the previous
  -- row's WITH-clause (which the parser would otherwise treat as
  -- another field assignment and fail on).
  "(" <> rowTypeText <> " WITH "
    <> T.intercalate ", "
        [ renderQuotedIfNeeded k <> " IS " <> v | (k, v) <- pairs ]
    <> ")"

renderStringLit :: Text -> Text
renderStringLit s = "\"" <> T.replace "\"" "\\\"" (T.replace "\\" "\\\\" s) <> "\""

indent :: Int -> Text -> Text
indent n t =
  let pad = T.replicate n " "
  in T.intercalate "\n" (map (pad <>) (T.lines t))
