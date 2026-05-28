{-# LANGUAGE OverloadedStrings #-}
-- | Convert a parsed CSV document plus an L4 type annotation from the
-- user's @IMPORT \`file.csv\` IS A …@ statement into the L4 source
-- text that the rewrite pass splices into the importing module in
-- place of that statement.
--
-- The synthesised text is plain L4 source, so it flows through the
-- existing parser and type-checker without any new AST surface.
-- Producing source text (rather than constructing the AST directly)
-- keeps the responsibility for source ranges, annotations, and
-- mixfix registry interactions firmly on the side of the parser.
--
-- The row type is whatever the user wrote after @IS A@. Two cardinality
-- shapes are recognised:
--
--   * @LIST OF Trade@   — multi-row file → list of records.
--   * @Trade@           — single-row file → exactly one record.
--
-- The row type itself must be 'DECLARE'd elsewhere in the module
-- (currently the rewriter only scans the local module — looking
-- through imported modules is a separate follow-up).
module L4.DataImport.Synthesize
  ( synthesizeFromCsv
  , bindingNameFromFilename
  , buildDeclareEnv
  , buildDeclareEnvs
  , mergeDeclareEnvs
  , DeclareEnv
  , CoerceError(..)
  ) where

import Base
import qualified Base.Text as Text
import Control.Applicative ((<|>))
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import qualified Data.Text.Read as TR

import L4.DataImport.Csv (CsvDoc(..))
import L4.Syntax

-- ----------------------------------------------------------------------------
-- DECLARE environment
-- ----------------------------------------------------------------------------

-- | Everything the synthesizer needs to know about the user's
-- previously-DECLAREd types: record types contribute their fields
-- (used as the per-column coercion schema); enum types contribute
-- their constructor names (used to validate enum-typed cells).
data DeclareEnv = MkDeclareEnv
  { deRecords :: !(Map Text [(Text, Type' Name)])
    -- ^ row-type-name → ordered list of (field name, field type)
  , deEnums   :: !(Map Text [Text])
    -- ^ enum-type-name → constructor names
  }
  deriving stock (Eq, Show)

emptyDeclareEnv :: DeclareEnv
emptyDeclareEnv = MkDeclareEnv Map.empty Map.empty

-- | Combine two 'DeclareEnv's. The /left/ argument's entries win on
-- duplicate names — used to give the importing module's local
-- DECLAREs priority over re-exports from imported modules. (In
-- practice TDNR handles ambiguity later; this is just a sensible
-- default for picking one for cell coercion.)
mergeDeclareEnvs :: DeclareEnv -> DeclareEnv -> DeclareEnv
mergeDeclareEnvs a b = MkDeclareEnv
  { deRecords = Map.union a.deRecords b.deRecords
  , deEnums   = Map.union a.deEnums   b.deEnums
  }

-- | 'buildDeclareEnv' applied across a list of modules and merged
-- with @mergeDeclareEnvs@. The earlier modules in the list shadow
-- later ones on duplicate names.
buildDeclareEnvs :: [Module Name] -> DeclareEnv
buildDeclareEnvs = foldr (mergeDeclareEnvs . buildDeclareEnv) emptyDeclareEnv

-- | Walk a parsed module (including nested sections) and collect every
-- record and enum @DECLARE@ into a 'DeclareEnv'.
--
-- Parameterised type DECLAREs and type synonyms are ignored — the
-- data-import surface restricts row types to ground records.
buildDeclareEnv :: Module Name -> DeclareEnv
buildDeclareEnv (MkModule _ _ s) = goSection emptyDeclareEnv s
  where
    goSection env (MkSection _ _ _ tds) = foldl' goTopDecl env tds

    goTopDecl env = \case
      Section _ s'    -> goSection env s'
      Declare _ d     -> addDeclare env d
      _               -> env

    addDeclare env (MkDeclare _ _ appForm tyDecl) =
      case appForm of
        MkAppForm _ rowN [] _ ->
          let nameText = rawNameToText (rawName rowN) in
          case tyDecl of
            RecordDecl _ _ fields ->
              env { deRecords =
                      Map.insert nameText
                        [ (rawNameToText (rawName fn), ty)
                        | MkTypedName _ fn ty _ <- fields
                        ]
                        env.deRecords
                  }
            EnumDecl _ conDecls ->
              env { deEnums =
                      Map.insert nameText
                        [ rawNameToText (rawName cn)
                        | MkConDecl _ cn _ <- conDecls
                        ]
                        env.deEnums
                  }
            SynonymDecl{} -> env
        _ -> env

-- ----------------------------------------------------------------------------
-- Error type
-- ----------------------------------------------------------------------------

data CoerceError
  = HeaderMismatch
      { ceMissingColumns :: ![Text]   -- ^ declared in schema but not in CSV
      , ceUnknownColumns :: ![Text]   -- ^ present in CSV but not in schema
      }
  | RowTypeNotDeclared { ceTypeName :: !Text }
    -- ^ The row type referenced by the IMPORT is not DECLAREd as a
    -- record in the current module.
  | UnsupportedFieldType
      { ceField   :: !Text
      , ceTypeDoc :: !Text   -- ^ a short description of the offending type
      }
    -- ^ A field of the row type has a Type' Name we can't coerce
    -- a CSV cell against.
  | UnsupportedPrimType
      { ceTypeName :: !Text
      , ceField    :: !Text
      }
  | CellCoercionFailed
      { ceRow    :: !Int
      , ceColumn :: !Text
      , ceType   :: !Text
      , ceValue  :: !Text
      , ceReason :: !Text
      }
  | EmptyCellInRequiredColumn
      { ceRow    :: !Int
      , ceColumn :: !Text
      , ceType   :: !Text
      }
  | EnumCellNotInSet
      { ceRow     :: !Int
      , ceColumn  :: !Text
      , ceValue   :: !Text
      , ceAllowed :: ![Text]
      }
  | WrongRowCount
      { ceExpected :: !Text   -- ^ \"exactly one row\"
      , ceActual   :: !Int
      }
  deriving stock (Eq, Show)

-- ----------------------------------------------------------------------------
-- Top-level synthesis
-- ----------------------------------------------------------------------------

-- | Derive the binding name from the filename token by stripping the
-- @.csv@ or @.tsv@ extension. The result is wrapped in backticks
-- when necessary so that filenames containing punctuation or spaces
-- remain well-formed identifiers in the synthesised source.
bindingNameFromFilename :: Text -> Text
bindingNameFromFilename t =
  let stripped = fromMaybe t $
        Text.stripSuffix ".csv" t <|> Text.stripSuffix ".tsv" t
  in renderQuotedIfNeeded stripped

-- | Synthesise the L4 source text that binds the parsed CSV/TSV file
-- to a value of the user-given type.
synthesizeFromCsv
  :: Text          -- ^ filename (e.g. @\"trades.csv\"@), used to derive the binding name if no explicit one given
  -> Maybe Text    -- ^ explicit binding name from the @AS@ clause (when present, used in place of the filename-derived name)
  -> Type' Name    -- ^ the type the user wrote after @IS A@
  -> DeclareEnv    -- ^ records and enums DECLAREd in the importing module
  -> CsvDoc
  -> Either CoerceError Text
synthesizeFromCsv filename mExplicitBinding ty env doc = do
  (cardinality, rowTypeNameTxt) <- analyseType ty
  fields <- case Map.lookup rowTypeNameTxt env.deRecords of
    Nothing -> Left RowTypeNotDeclared { ceTypeName = rowTypeNameTxt }
    Just fs -> pure fs

  -- Column-name validation: every declared field must appear in the header.
  let declaredCols = map fst fields
      headerCols   = doc.csvHeader
      missing      = filter (`notElem` headerCols) declaredCols
      unknown      = filter (`notElem` declaredCols) headerCols
  unless (null missing && null unknown) $
    Left HeaderMismatch { ceMissingColumns = missing, ceUnknownColumns = unknown }

  let columnIndex :: Text -> Maybe Int
      columnIndex name' = lookup name' (zip headerCols [0 :: Int ..])

  -- Coerce every row.
  rowBodies <- traverse (coerceRow env fields columnIndex)
                        (zip [1 :: Int ..] doc.csvRows)

  let rowTypeText = renderQuotedIfNeeded rowTypeNameTxt
      bindingText = case mExplicitBinding of
        Just b  -> renderQuotedIfNeeded b
        Nothing -> bindingNameFromFilename filename
  case cardinality of
    CardList -> pure $ T.unlines
      [ bindingText <> " MEANS"
      , indent 4 (renderList rowTypeText rowBodies)
      ]
    CardSingle ->
      case rowBodies of
        [row] -> pure $ T.unlines
          [ bindingText <> " MEANS"
          , indent 4 (renderRowConstructor rowTypeText row)
          ]
        rows -> Left WrongRowCount
          { ceExpected = "exactly one row", ceActual = length rows }

-- ----------------------------------------------------------------------------
-- Type analysis
-- ----------------------------------------------------------------------------

data Cardinality = CardSingle | CardList

-- | Inspect the user's @IS A …@ type expression and extract:
--
--   * whether the file is a list (@LIST OF T@) or a single record (@T@);
--   * the bare row type name @T@.
analyseType :: Type' Name -> Either CoerceError (Cardinality, Text)
analyseType = \case
  TyApp _ n [TyApp _ inner []]
    | rawNameToText (rawName n) == "LIST"
    -> Right (CardList, rawNameToText (rawName inner))
  TyApp _ n []
    -> Right (CardSingle, rawNameToText (rawName n))
  other -> Left UnsupportedFieldType
    { ceField   = "<the IMPORT's IS A clause>"
    , ceTypeDoc = T.pack (show other)
    }

-- ----------------------------------------------------------------------------
-- Row coercion
-- ----------------------------------------------------------------------------

coerceRow
  :: DeclareEnv
  -> [(Text, Type' Name)]
  -> (Text -> Maybe Int)
  -> (Int, [Text])
  -> Either CoerceError [(Text, Text)]
coerceRow env fields colIdx (rn, cells) =
  traverse (oneField env rn cells colIdx) fields

oneField
  :: DeclareEnv
  -> Int
  -> [Text]
  -> (Text -> Maybe Int)
  -> (Text, Type' Name)
  -> Either CoerceError (Text, Text)
oneField env rowNo cells colIdx (colName, ty) = do
  let cell = fromMaybe "" (colIdx colName >>= safeIndex cells)
  expr <- coerceCell env rowNo colName ty cell
  pure (colName, expr)

safeIndex :: [a] -> Int -> Maybe a
safeIndex xs i
  | i >= 0, i < length xs = Just (xs !! i)
  | otherwise             = Nothing

-- | Coerce one cell against an L4 'Type' Name'. Supports:
--
--   * the primitives @NUMBER@, @STRING@, @BOOLEAN@, @DATE@;
--   * @MAYBE T@ where @T@ is one of those primitives, with empty
--     cell → @NOTHING@ and non-empty cell → @JUST x@;
--   * names that resolve to an enum @DECLARE@ in the 'DeclareEnv',
--     in which case the cell value must be one of the declared
--     constructors;
--   * names that resolve to a record @DECLARE@ in the 'DeclareEnv',
--     in which case the cell is emitted as a /bare identifier/ — the
--     user is expected to have a named value of that type in scope
--     (e.g. cell @\"TSLA\"@ → identifier @TSLA@, which the
--     type-checker resolves to whatever @TSLA MEANS …@ binding is
--     reachable). This lets a CSV column store ticker-style
--     references to top-level value bindings rather than the full
--     record inline.
coerceCell :: DeclareEnv -> Int -> Text -> Type' Name -> Text -> Either CoerceError Text
coerceCell env rowNo colName ty raw =
  let trimmed = T.strip raw
  in case ty of
    TyApp _ tyN [] ->
      let tn = rawNameToText (rawName tyN)
      in case Map.lookup tn env.deEnums of
        Just ctors -> coerceEnum rowNo colName ctors trimmed
        Nothing
          | tn `elem` primitiveTypeNames ->
              coercePrim rowNo colName tn trimmed
          | Map.member tn env.deRecords ->
              coerceRecordRef rowNo colName tn trimmed
          | otherwise ->
              coercePrim rowNo colName tn trimmed   -- falls through to UnsupportedPrimType
    TyApp _ tyN [TyApp _ inner []]
      | rawNameToText (rawName tyN) == "MAYBE" ->
          if T.null trimmed
            then Right "NOTHING"
            else do
              let innerTxt = rawNameToText (rawName inner)
              v <- coercePrim rowNo colName innerTxt trimmed
              pure $ "JUST (" <> v <> ")"
    _ -> Left UnsupportedFieldType
      { ceField   = colName
      , ceTypeDoc = T.pack (show ty)
      }

primitiveTypeNames :: [Text]
primitiveTypeNames = ["NUMBER", "STRING", "BOOLEAN", "DATE"]

-- | Emit a cell as a bare identifier reference to a named value in
-- scope. Used for columns whose declared type is a user-defined
-- record — the typechecker will resolve the identifier and report
-- a clear out-of-scope error if the cell value doesn't match any
-- known binding.
coerceRecordRef :: Int -> Text -> Text -> Text -> Either CoerceError Text
coerceRecordRef rowNo colName tyName raw
  | T.null raw =
      Left EmptyCellInRequiredColumn { ceRow = rowNo, ceColumn = colName, ceType = tyName }
  | otherwise =
      Right (renderQuotedIfNeeded raw)

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

coerceEnum :: Int -> Text -> [Text] -> Text -> Either CoerceError Text
coerceEnum rowNo colName ctors raw
  | T.null raw =
      Left EmptyCellInRequiredColumn { ceRow = rowNo, ceColumn = colName, ceType = "<enum>" }
  | raw `elem` ctors = Right (renderQuotedIfNeeded raw)
  | otherwise = Left EnumCellNotInSet
      { ceRow = rowNo, ceColumn = colName, ceValue = raw, ceAllowed = ctors }

-- ----------------------------------------------------------------------------
-- Source rendering
-- ----------------------------------------------------------------------------

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

renderList :: Text -> [[(Text, Text)]] -> Text
renderList _ [] = "LIST EMPTY"
renderList rowTypeText rows =
  "LIST\n" <> T.intercalate ",\n"
    (map (("    " <>) . renderRowConstructor rowTypeText) rows)

renderRowConstructor :: Text -> [(Text, Text)] -> Text
renderRowConstructor rowTypeText pairs =
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

