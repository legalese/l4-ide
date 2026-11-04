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
-- > TYPE, in GIVEN a IS A TYPE      no shape: UTypeAsInput
-- > EITHER a b                     JEither (shape a) (shape b) (the service writes it as it does today; the
-- >                                                          form is open)
-- > any built-in type not listed above, or a type not found
-- >                                no shape yet: UUnknownType
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
import qualified Data.IntSet as IntSet
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import L4.Syntax
import L4.TypeCheck.Environment (
  booleanUnique,
  contractUnique,
  dateUnique,
  datetimeUnique,
  eitherUnique,
  eventUnique,
  listUnique,
  maybeUnique,
  numberUnique,
  stringUnique,
  timeUnique,
 )
import L4.TypeCheck.Types (EntityInfo)

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
  | -- | The shapes of the two sides. How an EITHER is written is not decided.
    JEither JsonShape JsonShape
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
  | -- | A type variable, by name: the rule is generic.
    UPolymorphic Text
  | -- | An input that is itself a type (@GIVEN a IS A TYPE@): the rule is generic.
    UTypeAsInput
  | -- | A type that is not known, or a built-in type that has no shape yet, by name.
    UUnknownType Text
  | -- | The record, the field, and why the field's type has no shape.
    UInField Text Text Unsendable
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | What 'jsonShape' looks types up in: the declarations of the module and of
-- everything it imports, by the unique of the type they declare. The type
-- checker's own information goes with them, for the result of a definition with
-- no GIVETH.
data ShapeEnv = MkShapeEnv
  { declared :: !(Map.Map Unique (Declare Resolved))
  , entities :: !EntityInfo
  , typeVariables :: !(Set.Set Unique)
  -- ^ The type variables in scope: the inputs of a generic rule that are types
  -- (@GIVEN a IS A TYPE@). The type checker keeps these in its local scope and
  -- not in 'entities'.
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
    , typeVariables = Set.empty
    }

-- | The shape of a type, or why it has none.
--
-- Whether it has one is worked out once for each type that is reached, however
-- many paths lead to it ('firstUnsendable'), so the answer costs what the
-- declarations cost to read. The shape itself is a tree with a declared type
-- written out on every path to it, which can be far larger than that (a record
-- whose two fields share a record type, nested, doubles at each level), so it
-- is built only as far as it is looked at. Walking all of it costs its size.
jsonShape :: ShapeEnv -> Type' Resolved -> Either Unsendable JsonShape
jsonShape env ty = case firstUnsendable env ty of
  Just why -> Left why
  Nothing -> Right (expand env ty)

-- | What a type with this name and these arguments is: the table at the top of
-- this module, as code. The arguments are a type's own or stand for them.
data TypeHead t
  = HasShape JsonShape
  | HasNoShape Unsendable
  | ArrayOf t
  | OptionalOf t
  | EitherOf t t
  | -- | Its name, each of its parameters with the argument it is used with, and
    -- what it is declared to be.
    Declared Text [(Unique, t)] (TypeDecl Resolved)

typeHead :: ShapeEnv -> Resolved -> [t] -> TypeHead t
typeHead env name args
  | u == numberUnique, null args = HasShape JNumber
  | u == booleanUnique, null args = HasShape JBool
  | u == stringUnique, null args = HasShape JString
  | u == dateUnique, null args = HasShape JDate
  | u == timeUnique, null args = HasShape JTime
  | u == datetimeUnique, null args = HasShape JDateTime
  | u == listUnique, [a] <- args = ArrayOf a
  | u == maybeUnique, [a] <- args = OptionalOf a
  | u == eitherUnique, [a, b] <- args = EitherOf a b
  | u == contractUnique = HasNoShape UDeontic
  | u == eventUnique = HasNoShape UEvent
  | Just (MkDeclare _ _ (MkAppForm _ declared params _) body) <- Map.lookup u env.declared =
      if length params == length args
        then Declared (nameText declared) (zip (map getUnique params) args) body
        else HasNoShape (UUnknownType (nameText declared))
  | u `Set.member` env.typeVariables = HasNoShape (UPolymorphic text)
  | otherwise = HasNoShape (UUnknownType text)
 where
  u = getUnique name
  text = nameText name

-- | A type in the walk of 'firstUnsendable', with its arguments filled in. Two
-- uses of a type with the same arguments are one node, so a type that takes a
-- type and passes it on in a larger one is not written out again at each level.
data TypeNode = MkTypeNode !Int (Either Unsendable (Resolved, [TypeNode]))

data Walk = MkWalk
  { nodes :: !(Map.Map (Unique, [Int]) TypeNode)
  , nextNode :: !Int
  , lookedInside :: !IntSet.IntSet
  -- ^ The nodes whose declarations have been read.
  , lookedAtArguments :: !IntSet.IntSet
  -- ^ The nodes met on the way through their own type, whose arguments have been
  -- read.
  }

-- | The first thing in a type that has no shape, field by field, or 'Nothing'.
--
-- This goes through the types in the order the fields are written and looks at
-- each one once. It does not need to look again: what a type reaches has been
-- looked at by the time the walk has finished with the type, or is on the way to
-- it now and will be finished with next. So what it finds, and the fields it
-- names on the way to it, are what looking at every path would give.
--
-- A type met on the way through itself stops there, with one exception. With the
-- same arguments it has nothing new to say. With others (@Box OF (Box OF a)@, or
-- a type that gives itself a larger type, which would never end) what is new is
-- the arguments, so those are looked at.
firstUnsendable :: ShapeEnv -> Type' Resolved -> Maybe Unsendable
firstUnsendable env ty =
  either Just (const Nothing) $
    evalState (runExceptT (intern Map.empty ty >>= visit Set.empty)) (MkWalk Map.empty 0 IntSet.empty IntSet.empty)
 where
  intern :: Map.Map Unique TypeNode -> Type' Resolved -> ExceptT Unsendable (State Walk) TypeNode
  intern vars = \case
    Fun{} -> noShape UFunction
    Type{} -> noShape UTypeAsInput
    InfVar _ n _ -> noShape (UPolymorphic (rawNameToText n))
    Forall _ bound inner -> do
      boundNodes <- traverse (noShape . UPolymorphic . nameText) bound
      intern (Map.union (Map.fromList (zip (map getUnique bound) boundNodes)) vars) inner
    TyApp _ name args
      | [] <- args, Just bound <- Map.lookup (getUnique name) vars -> pure bound
      | otherwise -> do
          argNodes <- traverse (intern vars) args
          let key = (getUnique name, [i | MkTypeNode i _ <- argNodes])
          gets (Map.lookup key . (.nodes)) >>= \case
            Just known -> pure known
            Nothing -> do
              node <- newNode (Right (name, argNodes))
              modify' \w -> w{nodes = Map.insert key node w.nodes}
              pure node

  -- Not shared: nothing is ever looked up by what has no shape, and a walk that
  -- reaches one is over.
  noShape :: Unsendable -> ExceptT Unsendable (State Walk) TypeNode
  noShape why = newNode (Left why)

  newNode :: Either Unsendable (Resolved, [TypeNode]) -> ExceptT Unsendable (State Walk) TypeNode
  newNode what = do
    i <- gets (.nextNode)
    modify' \w -> w{nextNode = i + 1}
    pure (MkTypeNode i what)

  visit :: Set.Set Unique -> TypeNode -> ExceptT Unsendable (State Walk) ()
  visit path (MkTypeNode i what) = case what of
    Left why -> throwError why
    Right (name, args)
      | getUnique name `Set.member` path -> do
          seen <- gets (IntSet.member i . (.lookedAtArguments))
          unless seen do
            modify' \w -> w{lookedAtArguments = IntSet.insert i w.lookedAtArguments}
            traverse_ (visit path) args
      | otherwise -> do
          seen <- gets (IntSet.member i . (.lookedInside))
          unless seen do
            modify' \w -> w{lookedInside = IntSet.insert i w.lookedInside}
            inside path name args

  inside :: Set.Set Unique -> Resolved -> [TypeNode] -> ExceptT Unsendable (State Walk) ()
  inside path name args = case typeHead env name args of
    HasShape _ -> pure ()
    HasNoShape why -> throwError why
    ArrayOf a -> visit path a
    OptionalOf a -> visit path a
    EitherOf a b -> visit path a *> visit path b
    Declared typeName sub body ->
      let
        path' = Set.insert (getUnique name) path
        vars = Map.fromList sub
       in
        case body of
          SynonymDecl _ inner -> intern vars inner >>= visit path'
          EnumDecl{} -> pure ()
          RecordDecl _ _ fields ->
            for_ fields \(MkTypedName _ fieldName fieldTy _) ->
              (intern vars fieldTy >>= visit path')
                `catchError` (throwError . UInField typeName (nameText fieldName))

-- | The shape of a type that 'firstUnsendable' found nothing wrong with. It stops
-- at a declared type that is being expanded already, so what it gives for a type
-- in a cycle depends on where the type is reached from.
expand :: ShapeEnv -> Type' Resolved -> JsonShape
expand env = go Set.empty
 where
  go :: Set.Set Unique -> Type' Resolved -> JsonShape
  go seen = \case
    Forall _ _ inner -> go seen inner
    TyApp _ name args -> case typeHead env name args of
      HasShape shape -> shape
      ArrayOf a -> JArray (go seen a)
      OptionalOf a -> JOptional (go seen a)
      EitherOf a b -> JEither (go seen a) (go seen b)
      Declared typeName sub body
        | getUnique name `Set.member` seen -> JRecursive typeName
        | otherwise ->
            let
              seen' = Set.insert (getUnique name) seen
              inner = go seen' . substitute (Map.fromList sub)
             in
              case body of
                SynonymDecl _ t -> inner t
                -- A constructor that carries fields is shaped by its name alone, as
                -- the schema has published it until now; how its fields are
                -- written is open (the wire form of sums), so not refused here.
                EnumDecl _ cons -> JEnum typeName [nameText c | MkConDecl _ c _ <- cons]
                RecordDecl _ _ fields -> JRecord typeName (map (field inner) fields)
      HasNoShape _ -> checked
    _ -> checked

  field inner (MkTypedName _ fieldName ty _) =
    let shape = inner ty
     in JsonField
          { fieldName = nameText fieldName
          , fieldShape = shape
          , fieldRequired = case shape of JOptional _ -> False; _ -> True
          }

  checked = error "jsonShape: firstUnsendable has looked at everything this reaches"

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
  UPolymorphic v -> "of the type variable `" <> v <> "`, so the rule is generic"
  UTypeAsInput -> "a type, so the rule is generic"
  UUnknownType t -> "of the type " <> t
  UInField r f why -> "of a record type " <> r <> " whose field " <> f <> " is " <> unsendableWhat why

-- | One line on what to do about it.
unsendableHint :: Unsendable -> Text
unsendableHint = \case
  UFunction -> "Pass the values the function would work on, and apply the function inside the rule."
  UDeontic -> "A contract can't be an @export input or result yet. Remove the @export; the rule still evaluates in the editor, with its #EVAL and #EVALTRACE."
  UEvent -> "Take the party, the action and the time as separate inputs, and build the event inside the rule."
  UPolymorphic _ -> genericHint
  UTypeAsInput -> genericHint
  UUnknownType _ -> "Use a NUMBER, BOOLEAN, STRING, DATE, TIME, DATETIME, a LIST or MAYBE of those, or a record or enumeration of them."
  UInField _ _ why -> unsendableHint why
 where
  genericHint = "Write the type it is used at in its GIVEN and GIVETH, or publish a rule that calls it at that type."
