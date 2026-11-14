{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module L4.FunctionSchema (
  Parameters (..),
  Parameter (..),
  declaresFromModule,
  typeToParameter,
  shapeToParameter,
  uncheckedParameter,
  parametersFromDecide,
  parametersFromDecideWithErrors,
) where

import Base
import Data.Aeson (FromJSON, ToJSON, (.:), (.:?), (.=), (.!=))
import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.Text as Text

import L4.Export (extractAssumeParamTypes, extractImplicitAssumeParams)
import L4.Export.Shape (JsonField (..), JsonShape (..), ShapeEnv, ShapeName (..), Unsendable, jsonShape, moduleDeclares, shapeEnvFromDeclares)
import L4.TypeSynonym (declaresFromModule, expandSynonyms)
import L4.Syntax
import L4.TypeCheck.Environment (maybeUnique)
import L4.TypeCheck.Types (CheckErrorWithContext)
import qualified Optics

data Parameters = MkParameters
  { parameterMap :: Map Text Parameter
  , required :: [Text]
  }
  deriving stock (Show, Read, Ord, Eq, Generic)

data Parameter = Parameter
  { parameterType :: !Text
  , parameterAlias :: !(Maybe Text)
  , parameterFormat :: !(Maybe Text) -- Format hint (e.g., "date" for YYYY-MM-DD, "date-time" for ISO 8601)
  , parameterEnum :: ![Text]
  , parameterDescription :: !Text
  , parameterProperties :: !(Maybe (Map Text Parameter)) -- Nested properties for object types
  , parameterPropertyOrder :: !(Maybe [Text]) -- Field order for object types (declaration order when available)
  , parameterItems :: !(Maybe Parameter) -- Array items schema for array types
  , parameterRequired :: !(Maybe [Text]) -- Required field names for nested object types
  , parameterL4Type :: !(Maybe Text) -- L4 user-declared type name (record/enum) when this node came from a DECLARE; serialised as "x-l4-type"
  }
  deriving stock (Show, Read, Ord, Eq, Generic)

instance ToJSON Parameters where
  toJSON (MkParameters props reqProps) =
    Aeson.object
      [ "type" .= Aeson.String "object"
      , "properties" .= props
      , "required" .= reqProps
      ]

instance FromJSON Parameters where
  parseJSON = Aeson.withObject "Parameters" $ \o -> do
    _ :: Text <- o .: "type"
    props <- o .: "properties"
    reqProps <- o .: "required"
    pure $ MkParameters props reqProps

instance ToJSON Parameter where
  toJSON p =
    Aeson.object $
      [ "type" .= p.parameterType ]
        ++ (if Text.null p.parameterDescription then [] else ["description" .= p.parameterDescription])
        ++ case p.parameterAlias of
          Nothing -> []
          Just alias -> ["alias" .= alias]
        ++ case p.parameterEnum of
          [] -> []
          enums -> ["enum" .= enums]
        ++ case p.parameterFormat of
          Nothing -> []
          Just fmt -> ["format" .= fmt]
        ++ case p.parameterProperties of
          Nothing -> []
          Just props -> ["properties" .= props]
        ++ case p.parameterPropertyOrder of
          Nothing -> []
          Just ord -> ["propertyOrder" .= ord]
        ++ case p.parameterItems of
          Nothing -> []
          Just items -> ["items" .= items]
        ++ case p.parameterRequired of
          Nothing -> []
          Just req -> ["required" .= req]
        ++ case p.parameterL4Type of
          Nothing -> []
          Just l4ty -> ["x-l4-type" .= l4ty]

instance FromJSON Parameter where
  parseJSON = Aeson.withObject "Parameter" $ \p ->
    Parameter
      <$> p .: "type"
      <*> p .:? "alias"
      <*> p .:? "format"
      <*> p .:? "enum" .!= []
      <*> p .:? "description" .!= ""
      <*> p .:? "properties"
      <*> p .:? "propertyOrder"
      <*> p .:? "items"
      <*> p .:? "required"
      <*> p .:? "x-l4-type"

-- | The schema of an input or a result: the shape the export check gives its
-- type ('jsonShape'), written out as a 'Parameter'. So an @\@export@ that the
-- check accepts is described as the check sees it, and a type the check gives
-- no shape has no schema: 'Left' says why.
typeToParameter :: ShapeEnv -> Type' Resolved -> Either Unsendable Parameter
typeToParameter env ty = shapeToParameter <$> jsonShape env ty

-- | What a 'Parameter' is for an input the export check did not look at, and
-- that 'typeToParameter' has no schema for: an untyped GIVEN, an input read
-- from a name the module never declared, or a rule that is not exported.
uncheckedParameter :: Parameter
uncheckedParameter = emptyParam "object"

-- | A shape, written out as a 'Parameter'. A 'Parameter' cannot say @null@, so a
-- MAYBE is its inner type, and a record's field that is a MAYBE is not in its
-- @required@. A record is written out on every path to it, and one that is
-- being written out already is its name only.
shapeToParameter :: JsonShape -> Parameter
shapeToParameter = \case
  JNumber -> emptyParam "number"
  JString -> emptyParam "string"
  JBool -> emptyParam "boolean"
  JDate -> (emptyParam "string") {parameterFormat = Just "date"}
  JTime -> (emptyParam "string") {parameterFormat = Just "time"}
  JDateTime -> (emptyParam "string") {parameterFormat = Just "date-time"}
  JEnum named constructors ->
    (emptyParam "string")
      { parameterDescription = Maybe.fromMaybe "" named.shapeTypeDescription
      , parameterEnum = constructors
      , parameterL4Type = Just named.shapeTypeName
      }
  JRecord named fields ->
    (emptyParam "object")
      { parameterDescription = Maybe.fromMaybe "" named.shapeTypeDescription
      , parameterProperties =
          Just $ Map.fromList
            [ (f.fieldName, addDesc f.fieldDescription (shapeToParameter f.fieldShape))
            | f <- fields
            ]
      , parameterPropertyOrder = Just [f.fieldName | f <- fields]
      , parameterRequired = Just [f.fieldName | f <- fields, f.fieldRequired]
      , parameterL4Type = Just named.shapeTypeName
      }
  -- Expansion stops here, to keep the schema finite; the name still lets a
  -- client render the value as @TypeName WITH …@.
  JRecursive named -> (emptyParam "object") {parameterL4Type = Just named.shapeTypeName}
  JArray inner -> (emptyParam "array") {parameterItems = Just (shapeToParameter inner)}
  JOptional inner -> shapeToParameter inner
  JEither _ _ -> eitherParameter
 where
  addDesc :: Maybe Text -> Parameter -> Parameter
  addDesc Nothing p = p
  addDesc (Just d) p = p {parameterDescription = d}

-- | An EITHER, as the service has published it: an object, with nothing said of
-- its two sides. How an EITHER is written is not decided (assumed, not ruled).
eitherParameter :: Parameter
eitherParameter = emptyParam "object"

emptyParam :: Text -> Parameter
emptyParam t =
  Parameter
    { parameterType = t
    , parameterAlias = Nothing
    , parameterFormat = Nothing
    , parameterEnum = []
    , parameterDescription = ""
    , parameterProperties = Nothing
    , parameterPropertyOrder = Nothing
    , parameterItems = Nothing
    , parameterRequired = Nothing
    , parameterL4Type = Nothing
    }

parametersFromDecide :: Module Resolved -> Decide Resolved -> Parameters
parametersFromDecide resolvedModule decide =
  parametersFromDecideWithErrors resolvedModule decide []

-- | Extract parameters from a DECIDE, including implicit ASSUMEs from type errors.
-- When a variable is used without an explicit ASSUME declaration, but its type
-- can be inferred (e.g., from usage like `temperature + 0`), the type checker
-- records an OutOfScopeError with the inferred type. If that type is fully
-- resolved (no inference variables), we treat it as an implicit ASSUME.
parametersFromDecideWithErrors
  :: Module Resolved
  -> Decide Resolved
  -> [CheckErrorWithContext]
  -> Parameters
parametersFromDecideWithErrors resolvedModule decide@(MkDecide _ (MkTypeSig _ (MkGivenSig _ names) _) _ _) errors =
  let
    declares = declaresFromModule resolvedModule
    env = shapeEnvFromDeclares (moduleDeclares resolvedModule) Map.empty
    -- Any DECIDE, exported or not, so one the export check never looked at.
    schemaOf ty = either (const uncheckedParameter) id (typeToParameter env ty)
    mkOne (MkOptionallyTypedName ann resolved mType) =
      let
        base =
          maybe uncheckedParameter schemaOf mType
        desc = Maybe.fromMaybe "" (fmap getDesc (ann Optics.^. annDesc))
       in
        (resolvedNameText resolved, base {parameterDescription = desc, parameterAlias = Nothing})

    -- Extract explicit ASSUME params that this function references
    assumeParams = extractAssumeParamTypes resolvedModule decide

    -- Extract implicit ASSUME params from OutOfScopeError with resolved types
    implicitParams = extractImplicitAssumeParams errors

    mkAssumeParam (name, ty) =
      let base = schemaOf ty
      in (name, base {parameterDescription = "", parameterAlias = Nothing})

    givenParamList = map mkOne names
    -- Track which GIVEN params have MAYBE/Optional types (these are not required)
    requiredGivenParams =
      [ resolvedNameText resolved
      | MkOptionallyTypedName _ resolved mType <- names
      , not (isMaybeType (expandSynonyms declares <$> mType))
      ]
    assumeParamList = map mkAssumeParam assumeParams
    implicitParamList = map mkAssumeParam implicitParams

    -- Combine all params, avoiding duplicates (explicit ASSUMEs take precedence)
    allAssumeParams = assumeParamList <> filter (\(n, _) -> n `notElem` map fst assumeParamList) implicitParamList
   in
    MkParameters
      { parameterMap = Map.fromList (givenParamList <> allAssumeParams)
      , required = requiredGivenParams <> map fst allAssumeParams
      }

-- | Check if a type annotation is MAYBE (i.e., the parameter is optional).
isMaybeType :: Maybe (Type' Resolved) -> Bool
isMaybeType (Just (TyApp _ name [_inner])) = getUnique name == maybeUnique
isMaybeType _ = False

resolvedNameText :: Resolved -> Text
resolvedNameText =
  rawNameToText . rawName . getActual
