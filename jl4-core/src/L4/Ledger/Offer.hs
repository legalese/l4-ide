-- | The acts a party may perform, read off a deployment's source
-- (OPERATIONAL-LOWERING-SPEC §9 WPO6, D-O13): what the ledger's MCP write
-- tools are generated from.
--
-- The list is static, and belongs to the deployment and not to an instance.
-- An instance names its contract expression when it is created, so no
-- instance is in scope when an MCP client lists its tools, and the position
-- an instance is at (WPO4's @what-may-I-do-now@ answers that) is not what a
-- tool list can track. So the offered acts are those the source's @PARTY@
-- clauses can admit, at any position:
--
-- * a clause whose action pattern is a whole-action variable
--   (@PARTY World MAY act@) admits every constructor of the contract's action
--   type, the second argument of its @DEONTIC@;
-- * a clause whose pattern names a constructor (@PARTY Alice MUST Pay …@)
--   admits that constructor;
-- * a clause whose subject is an @EVERY@, or whose party is not written as a
--   constructor name, or whose pattern is another form, admits nothing here
--   and is listed in 'unoffered' with its reason.
--
-- That is assumed, not ruled. A pattern's literal arguments do not narrow
-- the offer: an act that no live obligation then takes is appended as
-- passed over (R-O2), as on the events route. A constructor whose fields
-- are not all @BOOLEAN@, @NUMBER@ or @STRING@ is not offered, and is listed
-- with the field that stopped it.
--
-- On the dinner fixtures every clause is @PARTY World MAY act@ (option C),
-- so this offers every act to @World@ and none to @Alice@ or @Bob@. The
-- party scoping separates parties only once a clause names its actor,
-- which is the party binder (D-L9).
module L4.Ledger.Offer
  ( Offers (..)
  , Offered (..)
  , Field (..)
  , FieldType (..)
  , Unoffered (..)
  , Arg (..)
  , offersFor
  , actSource
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Set as Set
import qualified Base.Text as Text
import qualified Optics

import L4.API.VirtualFS (checkWithImports, vfsFromList)
import L4.Annotation (getAnno)
import L4.EvaluateLazy (EntityInfo)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Ledger.Replay (Deployment (..))
import L4.Print (prettyLayout)
import L4.Syntax
import qualified L4.TypeCheck as TypeCheck
import L4.Utils.Ratio (prettyRatioExact)

data FieldType = FieldBoolean | FieldNumber | FieldString
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass NFData

data Field = MkField
  { name :: !Text
  , kind :: !FieldType
  }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass NFData

-- | An act a party may perform: a constructor of the action type, with its
-- fields in order.
data Offered = MkOffered
  { party       :: !Text
  , constructor :: !Text
  , fields      :: ![Field]
  }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass NFData

-- | A clause, or a constructor of one, that was not offered, and why. The
-- party and the constructor are empty when the clause did not get as far as
-- naming them.
data Unoffered = MkUnoffered
  { party       :: !Text
  , constructor :: !Text
  , reason      :: !Text
  }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass NFData

data Offers = MkOffers
  { offered   :: ![Offered]
    -- ^ ordered by party, then constructor, without repeats
  , unoffered :: ![Unoffered]
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | An argument of an act, as a caller gave it.
data Arg
  = ArgBool !Bool
  | ArgNumber !Rational
  | ArgText !Text
  deriving stock (Eq, Show)

-- | The acts the deployment's source offers, by party. 'Left' says why
-- not: the source does not type-check.
offersFor :: Deployment -> Either Text Offers
offersFor dep = do
  r <- first Text.unlines (checkWithImports (vfsFromList dep.deploymentImports) dep.deploymentSource)
  if r.tcdSuccess
    then Right (offersOf r.tcdEntityInfo r.tcdModule)
    else Left (Text.unlines
      [ l | e <- r.tcdErrors, TypeCheck.severity e == TypeCheck.SError, l <- TypeCheck.prettyCheckErrorWithContext e ])

offersOf :: EntityInfo -> Module Resolved -> Offers
offersOf info m = MkOffers
  { offered = Set.toAscList (Set.fromList [ o | Right o <- results ])
  , unoffered = Set.toAscList (Set.fromList [ u | Left u <- results ])
  }
  where
    exprs = Optics.toListOf (Optics.gplate @(Expr Resolved) Optics.% Optics.cosmosOf (Optics.gplate @(Expr Resolved))) m
    results = concat [ clauseOffers info (actionTypeOf e) d | e@(Regulative _ d) <- exprs ]

-- | The type of the actions of a clause: the second argument of the
-- @DEONTIC@ the type checker recorded for it. Taken from the clause itself
-- and not from the module, whose imports may declare other contracts.
actionTypeOf :: Expr Resolved -> Maybe Unique
actionTypeOf e = case Optics.view annInfo (getAnno e) of
  Just (TypeInfo ty _) -> deonticAction ty >>= tyHead
  _ -> Nothing

clauseOffers :: EntityInfo -> Maybe Unique -> Deonton Resolved -> [Either Unoffered Offered]
clauseOffers info mActionType d = case d.subject of
  Every {} -> [Left (MkUnoffered "" "" "an EVERY clause binds its party by a variable, which is the party binder (D-L9)")]
  Party _ e -> case partyName e of
    Nothing -> [Left (MkUnoffered "" "" "a PARTY that is not written as a constructor name")]
    Just p -> case d.action.action of
      PatVar _ n
        | Just fs <- constructorFields info n -> [classify p (nameText n, fs)]
      PatVar {} -> case mActionType of
        Just ty -> map (classify p) (constructorsOf info ty)
        Nothing -> [Left (MkUnoffered p "" "the type checker recorded no DEONTIC type for the clause, so a whole-action pattern cannot be expanded")]
      PatApp _ n _ -> case constructorFields info n of
        Just fs -> [classify p (nameText n, fs)]
        Nothing -> [Left (MkUnoffered p (nameText n) "its constructor is not one the type checker recorded")]
      _ -> [Left (MkUnoffered p "" "an action pattern of a form other than a variable or a constructor")]
  where
    classify p (con, fs) = case traverse field fs of
      Right fields -> Right (MkOffered {party = p, constructor = con, fields})
      Left why -> Left (MkUnoffered p con why)
    field (n, t) = case t of
      TyApp _ r []
        | getUnique r == TypeCheck.booleanUnique -> Right (MkField n FieldBoolean)
        | getUnique r == TypeCheck.numberUnique  -> Right (MkField n FieldNumber)
        | getUnique r == TypeCheck.stringUnique  -> Right (MkField n FieldString)
      _ -> Left ("its field `" <> n <> "` is of type " <> prettyLayout t <> ", and only BOOLEAN, NUMBER and STRING fields are offered")

-- | A party written as a constructor name.
partyName :: Expr Resolved -> Maybe Text
partyName = \ case
  Var _ r -> Just (nameText r)
  App _ r [] -> Just (nameText r)
  _ -> Nothing

-- | The constructors of a declared type, with their fields, from the type
-- checker's own record of them.
constructorsOf :: EntityInfo -> Unique -> [(Text, [(Text, Type' Resolved)])]
constructorsOf info ty =
  [ (nameText (Def u n), fieldsOfType cty)
  | (u, (n, TypeCheck.KnownTerm cty Constructor)) <- Map.toList info
  , resultHead cty == Just ty
  ]
  where
    resultHead = \ case
      Fun _ _ res  -> resultHead res
      TyApp _ r [] -> Just (getUnique r)
      _            -> Nothing

-- | The fields of a name, if the type checker recorded it as a constructor.
constructorFields :: EntityInfo -> Resolved -> Maybe [(Text, Type' Resolved)]
constructorFields info n = case Map.lookup (getUnique n) info of
  Just (_, TypeCheck.KnownTerm cty Constructor) -> Just (fieldsOfType cty)
  _ -> Nothing

-- | The fields of a constructor, from its function type.
fieldsOfType :: Type' Resolved -> [(Text, Type' Resolved)]
fieldsOfType = \ case
  Fun _ args _ ->
    [ (maybe ("field " <> Text.pack (show i)) nameText mn, t)
    | (i, MkOptionallyNamedType _ mn t) <- zip [1 :: Int ..] args ]
  _ -> []

deonticAction :: Type' Resolved -> Maybe (Type' Resolved)
deonticAction = \ case
  TyApp _ c [_, a] | getUnique c == TypeCheck.contractUnique -> Just a
  _ -> Nothing

tyHead :: Type' Resolved -> Maybe Unique
tyHead = \ case
  TyApp _ r [] -> Just (getUnique r)
  _ -> Nothing

nameText :: Resolved -> Text
nameText = unqualifiedNameToText . getOriginal

-- | The L4 source of an act, from the arguments a caller gave, one for each
-- field in order. 'Left' says which one does not fit; a string with a
-- quote, a backslash or a control character is refused here, loudly, and
-- not escaped.
actSource :: Offered -> [Arg] -> Either Text Text
actSource o args
  | length args /= length o.fields =
      Left ("the act `" <> o.constructor <> "` takes " <> Text.pack (show (length o.fields)) <> " argument(s), and " <> Text.pack (show (length args)) <> " were given")
  | otherwise = do
      rendered <- traverse (uncurry render) (zip o.fields args)
      pure (Text.unwords (("`" <> o.constructor <> "`") : rendered))
  where
    render f a = case (f.kind, a) of
      (FieldBoolean, ArgBool b) -> Right (if b then "TRUE" else "FALSE")
      -- a negative is parenthesised: after another argument, @5 -3@ reads as a subtraction
      (FieldNumber, ArgNumber n) -> Right (if n < 0 then "(" <> prettyRatioExact n <> ")" else prettyRatioExact n)
      (FieldString, ArgText t)
        | Text.any (\ c -> c == '"' || c == '\\' || c < ' ') t ->
            Left ("the argument `" <> f.name <> "` has a quote, a backslash or a control character, which is not accepted")
        | otherwise -> Right ("\"" <> t <> "\"")
      (k, _) -> Left ("the argument `" <> f.name <> "` is a " <> kindName k)
    kindName = \ case
      FieldBoolean -> "BOOLEAN (true or false)"
      FieldNumber -> "NUMBER"
      FieldString -> "STRING"
