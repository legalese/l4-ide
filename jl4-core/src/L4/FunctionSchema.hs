{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module L4.FunctionSchema (
  Parameters (..),
  Parameter (..),
  emptyParameter,
  declaresFromModule,
  typeToParameter,
  returnSchemaOf,
  parametersFromDecide,
  parametersFromDecideWithErrors,
) where

import Base
import Data.Aeson (FromJSON, ToJSON, (.:), (.:?), (.=), (.!=))
import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.Set as Set
import qualified Data.Text as Text

import L4.Export (extractAssumeParamTypes, extractImplicitAssumeParams)
import L4.Syntax
import L4.TypeCheck.Environment (contractUnique, eventCName, eventUnique, maybeUnique, neverMatchesActName, neverMatchesPartyName)
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
  , parameterPrefixItems :: !(Maybe [Parameter]) -- Item schemas of a fixed-length array, by position; serialised as "prefixItems", with "minItems" and "maxItems" equal to their number
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
        ++ case p.parameterPrefixItems of
          Nothing -> []
          Just parts -> ["prefixItems" .= parts, "minItems" .= length parts, "maxItems" .= length parts]
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
      <*> p .:? "prefixItems"
      <*> p .:? "required"
      <*> p .:? "x-l4-type"

-- | A schema node of the given JSON type, with nothing else set.
emptyParameter :: Text -> Parameter
emptyParameter t =
  Parameter
    { parameterType = t
    , parameterAlias = Nothing
    , parameterFormat = Nothing
    , parameterEnum = []
    , parameterDescription = ""
    , parameterProperties = Nothing
    , parameterPropertyOrder = Nothing
    , parameterItems = Nothing
    , parameterPrefixItems = Nothing
    , parameterRequired = Nothing
    , parameterL4Type = Nothing
    }

declaresFromModule :: Module Resolved -> Map Text (Declare Resolved)
declaresFromModule (MkModule _ _ section) =
  Map.fromList (collectSection section)
 where
  collectSection (MkSection _ _ _ decls) =
    decls >>= collectDecl

  collectDecl = \case
    Declare _ decl@(MkDeclare _ _ (MkAppForm _ name _ _) _) ->
      [(resolvedNameText name, decl)]
    Section _ sub ->
      collectSection sub
    _ ->
      []

typeToParameter ::
  Map Text (Declare Resolved) ->
  Set.Set Text ->
  Type' Resolved ->
  Parameter
typeToParameter declares visited ty =
  case ty of
    Type _ -> emptyParameter "object"
    TyApp _ name [] ->
      typeNameToParameter name
    TyApp _ name [inner] ->
      let lowered = Text.toLower (resolvedNameText name)
       in
        if lowered `elem` ["list", "listof"]
          then
            (emptyParameter "array")
              { parameterItems = Just (typeToParameter declares visited inner)
              }
          else
            if lowered `elem` ["maybe", "optional"]
              then typeToParameter declares visited inner
              else typeNameToParameter name
    TyApp _ name [partyTy, actionTy]
      | getUnique name == eventUnique ->
          eventParameter
            (typeToParameter declares visited partyTy)
            (typeToParameter declares visited actionTy)
    TyApp _ name _ ->
      typeNameToParameter name
    Fun{} -> emptyParameter "object"
    Forall _ _ inner -> typeToParameter declares visited inner
    InfVar{} -> emptyParameter "object"
 where
  typeNameToParameter :: Resolved -> Parameter
  typeNameToParameter name =
    case primitiveJsonType name of
      Just (t, fmt) -> (emptyParameter t) { parameterFormat = fmt }
      Nothing ->
        case Map.lookup (resolvedNameText name) declares of
          Nothing -> emptyParameter "object"
          Just decl -> declareToParameter (resolvedNameText name) decl

  -- | Map L4 primitive type names to JSON Schema type and optional format.
  primitiveJsonType :: Resolved -> Maybe (Text, Maybe Text)
  primitiveJsonType name =
    case Text.toLower (resolvedNameText name) of
      "number" -> Just ("number", Nothing)
      "int" -> Just ("number", Nothing)
      "integer" -> Just ("number", Nothing)
      "float" -> Just ("number", Nothing)
      "double" -> Just ("number", Nothing)
      "boolean" -> Just ("boolean", Nothing)
      "bool" -> Just ("boolean", Nothing)
      "string" -> Just ("string", Nothing)
      "text" -> Just ("string", Nothing)
      "date" -> Just ("string", Just "date")
      "time" -> Just ("string", Just "time")
      "datetime" -> Just ("string", Just "date-time")
      _ -> Nothing

  declareToParameter :: Text -> Declare Resolved -> Parameter
  declareToParameter typeName (MkDeclare declAnn _ _ typeDecl)
    | typeName `Set.member` visited =
        -- Recursive type (e.g. a record whose field is a LIST OF itself):
        -- we must stop expanding to keep the schema finite, but we still
        -- carry the L4 type name so chat clients can render the value as
        -- `TypeName WITH …` rather than raw JSON.
        (emptyParameter "object") { parameterL4Type = Just typeName }
    | otherwise =
        case typeDecl of
          RecordDecl _ _ fields ->
            let
              visited' = Set.insert typeName visited
              fieldOrder = [resolvedNameText fieldName | MkTypedName _ fieldName _ _ <- fields]
              props =
                Map.fromList
                  [ (resolvedNameText fieldName, addDesc fieldDesc (typeToParameter declares visited' fieldTy))
                  | MkTypedName fieldAnn fieldName fieldTy _ <- fields
                  , let fieldDesc = fmap getDesc (fieldAnn Optics.^. annDesc)
                  ]
              requiredFields =
                [ resolvedNameText fieldName
                | MkTypedName _ fieldName fieldTy _ <- fields
                , not (isMaybeFieldType fieldTy)
                ]
             in
              (emptyParameter "object")
                { parameterDescription = Maybe.fromMaybe "" (fmap getDesc (declAnn Optics.^. annDesc))
                , parameterProperties = Just props
                , parameterPropertyOrder = Just fieldOrder
                , parameterRequired = Just requiredFields
                , parameterL4Type = Just typeName
                }
          EnumDecl _ constructors ->
            (emptyParameter "string")
              { parameterDescription = Maybe.fromMaybe "" (fmap getDesc (declAnn Optics.^. annDesc))
              , parameterEnum = [resolvedNameText c | MkConDecl _ c _ <- constructors]
              , parameterL4Type = Just typeName
              }
          SynonymDecl _ inner ->
            typeToParameter declares (Set.insert typeName visited) inner
   where
    addDesc :: Maybe Text -> Parameter -> Parameter
    addDesc Nothing p = p
    addDesc (Just d) p = p {parameterDescription = d}

-- | The schema of an event, as jl4-service answers one: an object whose one
-- key, @EVENT@, holds the party, the action and the time, in that order. The
-- built-in EVENT constructor has no field names, so its parts go by position,
-- and the schema lists them by position too. The party and the action carry
-- the descriptions of the events input of a rule whose answer is written
-- @DEONTIC@.
--
-- @WAITUNTIL@ builds an event whose party and action are the evaluator's two
-- placeholders, which match nothing, and an answer holds their names. A
-- position that lists the constructors of its type therefore lists the
-- placeholder too, so that the answer of a rule that returns a waiting event
-- is valid against the schema. A position of another type is unchanged: see
-- the README of jl4-service for the events it does not describe.
eventParameter :: Parameter -> Parameter -> Parameter
eventParameter party action =
  (emptyParameter "object")
    { parameterProperties = Just (Map.singleton eventKey parts)
    , parameterPropertyOrder = Just [eventKey]
    , parameterRequired = Just [eventKey]
    }
 where
  eventKey = rawNameToText (rawName eventCName)
  parts =
    (emptyParameter "array")
      { parameterDescription = "The party, the action and the time of the event"
      , parameterPrefixItems =
          Just
            [ (listsWaiting neverMatchesPartyName party) {parameterDescription = "The party performing the action"}
            , (listsWaiting neverMatchesActName action) {parameterDescription = "The action performed"}
            , (emptyParameter "number") {parameterDescription = "The time of the event"}
            ]
      }
  listsWaiting :: Name -> Parameter -> Parameter
  listsWaiting placeholder p
    | null p.parameterEnum = p
    | otherwise = p {parameterEnum = p.parameterEnum <> [rawNameToText (rawName placeholder)]}

-- | The @returnSchema@ that jl4-service and the editor publish for an exported
-- rule that gives back a value of this type. A rule whose answer is written
-- @DEONTIC@ or @PROVISION@ has none. A synonym of @DEONTIC@ is not expanded
-- here, so a rule whose answer type is one gets the schema of a value.
returnSchemaOf :: Map Text (Declare Resolved) -> Type' Resolved -> Maybe Parameter
returnSchemaOf declares ty =
  case ty of
    TyApp _ name [_, _] | getUnique name == contractUnique -> Nothing
    _ -> Just (typeToParameter declares Set.empty ty)

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
    mkOne (MkOptionallyTypedName ann resolved mType) =
      let
        base =
          Maybe.fromMaybe (emptyParameter "object") (typeToParameter declares Set.empty <$> mType)
        desc = Maybe.fromMaybe "" (fmap getDesc (ann Optics.^. annDesc))
       in
        (resolvedNameText resolved, base {parameterDescription = desc, parameterAlias = Nothing})

    -- Extract explicit ASSUME params that this function references
    assumeParams = extractAssumeParamTypes resolvedModule decide

    -- Extract implicit ASSUME params from OutOfScopeError with resolved types
    implicitParams = extractImplicitAssumeParams errors

    mkAssumeParam (name, ty) =
      let base = typeToParameter declares Set.empty ty
      in (name, base {parameterDescription = "", parameterAlias = Nothing})

    givenParamList = map mkOne names
    -- Track which GIVEN params have MAYBE/Optional types (these are not required)
    requiredGivenParams =
      [ resolvedNameText resolved
      | MkOptionallyTypedName _ resolved mType <- names
      , not (isMaybeType mType)
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

-- | Check if a field type is MAYBE or Optional (for record field required tracking).
isMaybeFieldType :: Type' Resolved -> Bool
isMaybeFieldType (TyApp _ name [_]) =
  let lowered = Text.toLower (resolvedNameText name)
   in lowered `elem` ["maybe", "optional"]
isMaybeFieldType _ = False

resolvedNameText :: Resolved -> Text
resolvedNameText =
  rawNameToText . rawName . getActual
