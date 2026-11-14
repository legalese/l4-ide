module L4.JsonSchema (
  generateJsonSchema,
  shapeToJsonSchema,
  JsonSchema (..),
  SchemaType (..),
) where

import Base
import qualified Base.Text as Text
import Data.Aeson (ToJSON (..), (.=))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Map.Strict as Map

import L4.Export (ExportedFunction (..), ExportedParam (..))
import L4.Export.Shape (JsonField (..), JsonShape (..), ShapeEnv, ShapeName (..), Unsendable, jsonShape)

data JsonSchema = JsonSchema
  { schemaVersion :: !Text
  , schemaTitle :: !Text
  , schemaDescription :: !(Maybe Text)
  , schemaType :: !SchemaType
  , schemaDefs :: !(Map Text SchemaType)
  }
  deriving stock (Eq, Show)

data SchemaType
  = SString !(Maybe Text)
  | SNumber !(Maybe Text)
  | SInteger !(Maybe Text)
  | SBoolean !(Maybe Text)
  | SNull
  | SArray !SchemaType !(Maybe Text)
  | SObject ![(Text, SchemaType, Bool)] !(Maybe Text)
  | SRef !Text !(Maybe Text)
  | SOneOf ![SchemaType] !(Maybe Text)
  | SEnum ![Text] !(Maybe Text)
  | SConst !Text !(Maybe Text)
  | SAnyOf ![SchemaType] !(Maybe Text)
  | SStringFormat !Text !(Maybe Text)
  deriving stock (Eq, Show)

instance ToJSON JsonSchema where
  toJSON schema =
    Aeson.object $
      [ "$schema" .= schema.schemaVersion
      , "title" .= schema.schemaTitle
      ]
        <> maybe [] (\d -> ["description" .= d]) schema.schemaDescription
        <> schemaTypeToFields schema.schemaType
        <> ( if Map.null schema.schemaDefs
              then []
              else ["$defs" .= Map.mapWithKey (\_ v -> schemaTypeToValue v) schema.schemaDefs]
           )

schemaTypeToValue :: SchemaType -> Aeson.Value
schemaTypeToValue st =
  Aeson.object $ schemaTypeToFields st

schemaTypeToFields :: SchemaType -> [(Aeson.Key, Aeson.Value)]
schemaTypeToFields = \case
  SString desc -> typeField "string" <> descField desc
  SNumber desc -> typeField "number" <> descField desc
  SInteger desc -> typeField "integer" <> descField desc
  SBoolean desc -> typeField "boolean" <> descField desc
  SNull -> typeField "null"
  SArray items desc ->
    typeField "array"
      <> ["items" .= schemaTypeToValue items]
      <> descField desc
  SObject props desc ->
    let (propFields, reqFields) =
          foldr
            ( \(name, ty, req) (ps, rs) ->
                ( (Key.fromText name, schemaTypeToValue ty) : ps
                , if req then name : rs else rs
                )
            )
            ([], [])
            props
     in typeField "object"
          <> ["properties" .= Aeson.Object (KeyMap.fromList propFields)]
          <> (if null reqFields then [] else ["required" .= reqFields])
          <> descField desc
  SRef refName desc ->
    ["$ref" .= ("#/$defs/" <> refName)]
      <> descField desc
  SOneOf options desc ->
    ["oneOf" .= map schemaTypeToValue options]
      <> descField desc
  SEnum values desc ->
    typeField "string"
      <> ["enum" .= values]
      <> descField desc
  SConst value desc ->
    ["const" .= value]
      <> descField desc
  SAnyOf options desc ->
    ["anyOf" .= map schemaTypeToValue options]
      <> descField desc
  SStringFormat fmt desc ->
    typeField "string"
      <> ["format" .= fmt]
      <> descField desc
 where
  typeField :: Text -> [(Aeson.Key, Aeson.Value)]
  typeField t = ["type" .= (t :: Text)]

  descField :: Maybe Text -> [(Aeson.Key, Aeson.Value)]
  descField = maybe [] (\d -> ["description" .= d])

-- | The JSON Schema of an exported rule's inputs, rendered from the shape the
-- export check gives each of their types ('jsonShape'), so an @\@export@ that
-- the check accepts is described as the check sees it. A declared type is
-- written once, under @$defs@, and referred to wherever it is used. An input
-- whose type has no shape has no schema: 'Left' names it and says why.
generateJsonSchema :: ShapeEnv -> ExportedFunction -> Either (Text, Unsendable) JsonSchema
generateJsonSchema env export = do
  shapes <- traverse shapeOf export.exportParams
  let (props, defs) = runState (traverse property shapes) Map.empty
  pure
    JsonSchema
      { schemaVersion = "https://json-schema.org/draft/2020-12/schema"
      , schemaTitle = export.exportName
      , schemaDescription =
          if Text.null export.exportDescription
            then Nothing
            else Just export.exportDescription
      , schemaType = SObject props Nothing
      , schemaDefs = defs
      }
 where
  shapeOf param = case param.paramType of
    Nothing -> Right (param, Nothing)
    Just ty -> case jsonShape env ty of
      Left why -> Left (param.paramName, why)
      Right shape -> Right (param, Just shape)

  -- An input with no written type is described as a string, and is required
  -- as the rule's GIVEN says.
  property (param, Nothing) =
    pure (param.paramName, SString param.paramDescription, param.paramRequired)
  property (param, Just shape) = do
    schema <- shapeToJsonSchema shape
    pure (param.paramName, withDescription param.paramDescription schema, not (isOptional shape))

  isOptional = \case
    JOptional _ -> True
    _ -> False

-- | A shape as JSON Schema, with the declared types it reaches added to the
-- @$defs@ it is given. A MAYBE may be @null@.
shapeToJsonSchema :: JsonShape -> State (Map Text SchemaType) SchemaType
shapeToJsonSchema = \case
  JNumber -> pure (SNumber Nothing)
  JString -> pure (SString Nothing)
  JBool -> pure (SBoolean Nothing)
  JDate -> pure (SStringFormat "date" Nothing)
  JTime -> pure (SStringFormat "time" Nothing)
  JDateTime -> pure (SStringFormat "date-time" Nothing)
  JArray inner -> (`SArray` Nothing) <$> shapeToJsonSchema inner
  JOptional inner -> (\s -> SAnyOf [s, SNull] Nothing) <$> shapeToJsonSchema inner
  JEither _ _ -> pure eitherSchema
  JEnum named constructors -> define named (pure (SEnum constructors named.shapeTypeDescription))
  JRecord named fields ->
    define named do
      props <- for fields \f -> do
        schema <- shapeToJsonSchema f.fieldShape
        pure (f.fieldName, withDescription f.fieldDescription schema, f.fieldRequired)
      pure (SObject props named.shapeTypeDescription)
  JRecursive named -> pure (SRef (defName named) Nothing)
 where
  -- Each declared type is written once. The name is taken before its body is
  -- written, so a type that contains itself refers to itself.
  define named body = do
    let key = defName named
    known <- gets (Map.member key)
    unless known do
      modify' (Map.insert key (SObject [] Nothing))
      schema <- body
      modify' (Map.insert key schema)
    pure (SRef key Nothing)

-- | An EITHER, as the service has published it: an object, with nothing said of
-- its two sides. How an EITHER is written is not decided (assumed, not ruled).
eitherSchema :: SchemaType
eitherSchema = SObject [] Nothing

-- | The name a declared type has under @$defs@: its own, and for a type with
-- parameters the types it is given, as L4 writes them (@Box OF NUMBER@), since
-- each of those has fields of its own.
defName :: ShapeName -> Text
defName named = case named.shapeTypeArgs of
  [] -> named.shapeTypeName
  args -> named.shapeTypeName <> " OF " <> Text.intercalate ", " args

withDescription :: Maybe Text -> SchemaType -> SchemaType
withDescription Nothing st = st
withDescription (Just d) st = case st of
  SRef refName _ -> SRef refName (Just d)
  SString _ -> SString (Just d)
  SNumber _ -> SNumber (Just d)
  SInteger _ -> SInteger (Just d)
  SBoolean _ -> SBoolean (Just d)
  SArray items _ -> SArray items (Just d)
  SObject props _ -> SObject props (Just d)
  SOneOf opts _ -> SOneOf opts (Just d)
  SEnum vals _ -> SEnum vals (Just d)
  SConst val _ -> SConst val (Just d)
  SAnyOf opts _ -> SAnyOf opts (Just d)
  SStringFormat fmt _ -> SStringFormat fmt (Just d)
  SNull -> SNull
