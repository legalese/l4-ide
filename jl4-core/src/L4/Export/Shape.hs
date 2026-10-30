{-# LANGUAGE OverloadedStrings #-}

-- | What can cross the boundary of an @\@export@: the one place that decides
-- whether a type of an exported rule's input or result has a JSON form.
--
-- 'jsonShape' answers it for one type. Every other question about the
-- boundary (is this @\@export@ allowed, what does its schema say, what does
-- the editor list) is meant to be asked of it, instead of being answered a
-- second time by a check of its own.
--
-- The table, one row for each kind of type. The shape a type has is what a
-- request carries for it and what an answer carries back.
--
-- > NUMBER                         JNumber
-- > BOOLEAN                        JBool
-- > STRING                         JString
-- > DATE, TIME, DATETIME           JDate, JTime, JDateTime   (ISO 8601 strings)
-- > LIST OF a                      JArray (shape a)
-- > MAYBE a                        JOptional (shape a)       (may be left out or null)
-- > DECLARE T HAS ...              JRecord                   (fields in declaration order)
-- > DECLARE T IS ONE OF a, b       JEnum                     (the constructors' names)
-- > DECLARE T IS ONE OF a, b HAS … JEnum                     (the constructors' names; the fields are not part of
--  >                                                          the shape: how they are written is not decided)
-- > DECLARE T IS A type            the shape of that type
-- > a type with parameters         the shape of its body, parameters replaced
-- > a record that contains itself  JRecursive               (expansion stops there)
-- > DEONTIC party action           no shape yet: UDeontic
-- > EVENT party action             no shape yet: UEvent
-- > FUNCTION FROM a TO b           no shape yet: UFunction
-- > a type variable                no shape: UPolymorphic
-- > EITHER, and any built-in type not listed above, or a type not found
--                                  no shape yet: UUnknownType
--
-- A new built-in type has no shape until someone adds a row here.
module L4.Export.Shape (
  JsonShape (..),
  JsonField (..),
  Unsendable (..),
  ShapeEnv (..),
  moduleDeclares,
  shapeEnvFromDeclares,
  jsonShape,
  unsendableWhat,
  unsendableHint,
) where

import Base
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import L4.Syntax
import L4.TypeCheck.Environment (
  booleanUnique,
  contractUnique,
  dateUnique,
  datetimeUnique,
  eventUnique,
  listUnique,
  maybeUnique,
  numberUnique,
  stringUnique,
  timeUnique,
 )
import L4.TypeCheck.Types (CheckEntity (..), EntityInfo)

-- | The form a value of a type has in JSON.
data JsonShape
  = JNumber
  | JString
  | JBool
  | JDate
  | JTime
  | JDateTime
  | -- | The type's name and its constructors' names.
    JEnum Text [Text]
  | -- | The type's name and its fields.
    JRecord Text [JsonField]
  | -- | A record that is being expanded already: its name only.
    JRecursive Text
  | JArray JsonShape
  | JOptional JsonShape
  deriving stock (Eq, Show)

data JsonField = JsonField
  { fieldName :: !Text
  , fieldShape :: !JsonShape
  , fieldRequired :: !Bool
  }
  deriving stock (Eq, Show)

-- | Why a type has no shape.
data Unsendable
  = UFunction
  | UDeontic
  | UEvent
  | -- | A type variable, by name.
    UPolymorphic Text
  | -- | A type that is not known, or a built-in type that has no shape yet, by name.
    UUnknownType Text
  | -- | The record, the field, and why the field's type has no shape.
    UInField Text Text Unsendable
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | What 'jsonShape' looks types up in: the declarations of the module and of
-- everything it imports, by the unique of the type they declare, and the type
-- checker's own information, which says what a name that is not declared is.
data ShapeEnv = MkShapeEnv
  { declared :: !(Map.Map Unique (Declare Resolved))
  , entities :: !EntityInfo
  }

-- | Every DECLARE of a module, in sections too. Not the ones it imports.
moduleDeclares :: Module Resolved -> [Declare Resolved]
moduleDeclares (MkModule _ _ section) = inSection section
 where
  inSection (MkSection _ _ _ decls) = decls >>= inDecl
  inDecl = \case
    Declare _ d -> [d]
    Section _ sub -> inSection sub
    _ -> []

shapeEnvFromDeclares :: [Declare Resolved] -> EntityInfo -> ShapeEnv
shapeEnvFromDeclares decls ei =
  MkShapeEnv
    { declared = Map.fromList [(getUnique name, d) | d@(MkDeclare _ _ (MkAppForm _ name _ _) _) <- decls]
    , entities = ei
    }

-- | The shape of a type, or why it has none.
jsonShape :: ShapeEnv -> Type' Resolved -> Either Unsendable JsonShape
jsonShape env = go Set.empty
 where
  go :: Set.Set Unique -> Type' Resolved -> Either Unsendable JsonShape
  go seen = \case
    Fun{} -> Left UFunction
    Forall _ _ inner -> go seen inner
    Type{} -> Left (UUnknownType "TYPE")
    InfVar _ n _ -> Left (UUnknownType (rawNameToText n))
    TyApp _ name args -> typeApp seen name args

  typeApp :: Set.Set Unique -> Resolved -> [Type' Resolved] -> Either Unsendable JsonShape
  typeApp seen name args
    | u == numberUnique, null args = Right JNumber
    | u == booleanUnique, null args = Right JBool
    | u == stringUnique, null args = Right JString
    | u == dateUnique, null args = Right JDate
    | u == timeUnique, null args = Right JTime
    | u == datetimeUnique, null args = Right JDateTime
    | u == listUnique, [a] <- args = JArray <$> go seen a
    | u == maybeUnique, [a] <- args = JOptional <$> go seen a
    | u == contractUnique = Left UDeontic
    | u == eventUnique = Left UEvent
    | Just d <- Map.lookup u env.declared = declaredType seen u d args
    | Just (_, KnownTypeVariable) <- Map.lookup u env.entities = Left (UPolymorphic text)
    | otherwise = Left (UUnknownType text)
   where
    u = getUnique name
    text = nameText name

  declaredType :: Set.Set Unique -> Unique -> Declare Resolved -> [Type' Resolved] -> Either Unsendable JsonShape
  declaredType seen u (MkDeclare _ _ (MkAppForm _ name params _) body) args
    | length params /= length args = Left (UUnknownType (nameText name))
    | u `Set.member` seen = Right (JRecursive (nameText name))
    | otherwise =
        let
          seen' = Set.insert u seen
          sub = Map.fromList (zip (map getUnique params) args)
         in
          case body of
            SynonymDecl _ inner -> go seen' (substitute sub inner)
            -- A constructor that carries fields is shaped by its name alone, as
            -- the schema has published it until now; how its fields are
            -- written is open (the wire form of sums), so not refused here.
            EnumDecl _ cons -> Right (JEnum (nameText name) [nameText c | MkConDecl _ c _ <- cons])
            RecordDecl _ _ fields -> do
              shaped <- traverse (field seen' sub name) fields
              Right (JRecord (nameText name) shaped)

  field :: Set.Set Unique -> Map.Map Unique (Type' Resolved) -> Resolved -> TypedName Resolved -> Either Unsendable JsonField
  field seen sub recordName (MkTypedName _ fieldName ty _) =
    case go seen (substitute sub ty) of
      Left why -> Left (UInField (nameText recordName) (nameText fieldName) why)
      Right shape ->
        Right
          JsonField
            { fieldName = nameText fieldName
            , fieldShape = shape
            , fieldRequired = case shape of JOptional _ -> False; _ -> True
            }

-- | A type with the parameters of its declaration replaced by the arguments it
-- is used with.
substitute :: Map.Map Unique (Type' Resolved) -> Type' Resolved -> Type' Resolved
substitute sub
  | Map.null sub = id
  | otherwise = go
 where
  go = \case
    TyApp ann r []
      | Just t <- Map.lookup (getUnique r) sub -> t
      | otherwise -> TyApp ann r []
    TyApp ann r ts -> TyApp ann r (map go ts)
    Fun ann args res -> Fun ann [MkOptionallyNamedType a n (go t) | MkOptionallyNamedType a n t <- args] (go res)
    Forall ann vs t -> Forall ann vs (go t)
    other -> other

nameText :: Resolved -> Text
nameText = rawNameToText . rawName . getActual

-- | What is not supported, in a few words, for the error to say "its input
-- `e` is <what>".
unsendableWhat :: Unsendable -> Text
unsendableWhat = \case
  UFunction -> "a function"
  UDeontic -> "a DEONTIC, a contract rule"
  UEvent -> "an EVENT"
  UPolymorphic v -> "of the type variable " <> v
  UUnknownType t -> "of the type " <> t
  UInField r f why -> "of a record type " <> r <> " whose field " <> f <> " is " <> unsendableWhat why

-- | One line on what to do about it.
unsendableHint :: Unsendable -> Text
unsendableHint = \case
  UFunction -> "Pass the values the function would work on, and apply the function inside the rule."
  UDeontic -> "A contract can't be an @export input or result yet. Remove the @export; the rule still evaluates in the editor, with its #EVAL and #EVALTRACE."
  UEvent -> "Take the party, the action and the time as separate inputs, and build the event inside the rule."
  UPolymorphic _ -> "Write the type the rule is used at in its GIVEN or GIVETH."
  UUnknownType _ -> "Use a NUMBER, BOOLEAN, STRING, DATE, TIME, DATETIME, a LIST or MAYBE of those, or a record or enumeration of them."
  UInField _ _ why -> unsendableHint why
