-- | Type synonyms expanded for the schema generators the way the JSON decoder
-- expands them ('L4.EvaluateLazy.Machine.expandTypeSynonyms'): a synonym at
-- the head of a type is replaced by its body, its arguments substituted for its
-- parameters, as far as that goes. The decoder reads the type checker's entity
-- table; the generators have only declarations, so this reads those.
module L4.TypeSynonym
  ( declaresFromModule
  , expandSynonyms
  , substituteTypeParams
  ) where

import Base
import qualified Data.Map.Strict as Map

import L4.Syntax

-- | The module's own declarations, by name.
declaresFromModule :: Module Resolved -> Map Text (Declare Resolved)
declaresFromModule (MkModule _ _ section) =
  Map.fromList (collectSection section)
 where
  collectSection (MkSection _ _ _ decls) =
    decls >>= collectDecl

  collectDecl = \case
    Declare _ decl@(MkDeclare _ _ (MkAppForm _ name _ _) _) ->
      [(rawNameToText (rawName (getActual name)), decl)]
    Section _ sub ->
      collectSection sub
    _ ->
      []

-- | Expand the synonyms at the head of a type. A declaration is used only when
-- it is the very type referred to, by unique, not one that shares its name;
-- and, as in the decoder, for at most 16 steps.
expandSynonyms :: Map Text (Declare Resolved) -> Type' Resolved -> Type' Resolved
expandSynonyms declares = go (16 :: Int)
 where
  go 0 ty = ty
  go n ty@(TyApp _ ref args) =
    case Map.lookup (rawNameToText (rawName (getActual ref))) declares of
      Just (MkDeclare _ _ (MkAppForm _ declared params _) (SynonymDecl _ body))
        | getUnique declared == getUnique ref
        , length params == length args ->
            go (n - 1) (substituteTypeParams (Map.fromList (zip (map getUnique params) args)) body)
      _ -> ty
  go _ ty = ty

substituteTypeParams :: Map Unique (Type' Resolved) -> Type' Resolved -> Type' Resolved
substituteTypeParams sub = \ case
  TyApp ann r []
    | Just t <- Map.lookup (getUnique r) sub -> t
    | otherwise -> TyApp ann r []
  TyApp ann r ts -> TyApp ann r (map (substituteTypeParams sub) ts)
  Fun ann args res ->
    Fun ann [ MkOptionallyNamedType a n (substituteTypeParams sub t) | MkOptionallyNamedType a n t <- args ]
      (substituteTypeParams sub res)
  Forall ann vs t -> Forall ann vs (substituteTypeParams sub t)
  other -> other
