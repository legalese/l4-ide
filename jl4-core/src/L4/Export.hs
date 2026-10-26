{-# LANGUAGE CPP #-}
module L4.Export (
  ExportedFunction (..),
  ExportedParam (..),
  DescFlags (..),
  ParsedDesc (..),
  TypeDescMap,
  parseDescText,
  getExportedFunctions,
  getDefaultFunction,
  enrichReturnTypes,
  buildTypeDescMap,
  assumesFromModule,
  extractAssumeParamTypes,
  extractAssumeParamResolveds,
  extractImplicitAssumeParams,
  hasTypeInferenceVars,
  validateExportInputs,
  isExportedDecide,
  BodyReads (..),
  bodyReads,
) where

import Base

#if defined(SERIALISE_ENABLED)
import Codec.Serialise (Serialise)
#endif
import Control.Applicative ((<|>))
import qualified Base.Text as Text
import Data.Char (isSpace)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Map.Lazy as LazyMap
import qualified Data.Set as Set
import L4.Annotation (getAnno)
import L4.Syntax
import L4.TypeCheck.Environment (contractUnique, eventUnique, maybeUnique)
import L4.TypeCheck.Types (CheckErrorWithContext(..), CheckError(..), CheckEntity(..), CheckErrorContext(..), EntityInfo, Substitution, optionallyNamedTypeType, substituteInfVars, substituteType)
import L4.TypeCheck.Unify (synonymExpansionFuel)
import Optics

type TypeDescMap = Map.Map Unique Text

data ExportedFunction = ExportedFunction
  { exportName :: !Text
  , exportDescription :: !Text
  , exportIsDefault :: !Bool
  , exportParams :: ![ExportedParam]
  , exportReturnType :: !(Maybe (Type' Resolved))
  , exportDecide :: !(Decide Resolved)
  }
  deriving stock (Eq, Show, Generic)
#if defined(SERIALISE_ENABLED)
  deriving anyclass (Serialise)
#endif

data ExportedParam = ExportedParam
  { paramName :: !Text
  , paramType :: !(Maybe (Type' Resolved))
  , paramDescription :: !(Maybe Text)
  , paramRequired :: !Bool
  }
  deriving stock (Eq, Show, Generic)
#if defined(SERIALISE_ENABLED)
  deriving anyclass (Serialise)
#endif

data DescFlags = DescFlags
  { isDefault :: !Bool
  , isExport :: !Bool
  }
  deriving stock (Eq, Show)

data ParsedDesc = ParsedDesc
  { flags :: !DescFlags
  , description :: !Text
  }
  deriving stock (Eq, Show)

parseDescText :: Text -> ParsedDesc
parseDescText txt =
  let
    trimmed = Text.strip txt
    (flags', remainder) = consumeKeywords trimmed initialFlags
  in
    ParsedDesc
      { flags = flags'
      , description = Text.strip remainder
      }
 where
  initialFlags =
    DescFlags
      { isDefault = False
      , isExport = False
      }

  consumeKeywords t flagsAcc =
    let current = Text.stripStart t
    in case Text.uncons current of
      Nothing -> (flagsAcc, current)
      Just _ ->
        let (token, rest) = Text.break isSpace current
            restStripped = Text.stripStart rest
        in case Text.toLower token of
          "default" ->
            consumeKeywords
              restStripped
              flagsAcc
                { isDefault = True
                , isExport = True
                }
          "export" ->
            consumeKeywords restStripped flagsAcc{isExport = True}
          _ -> (flagsAcc, current)

getExportedFunctions :: Module Resolved -> [ExportedFunction]
getExportedFunctions mod'@(MkModule _ _ section) =
  let typeDescMap = buildTypeDescMap mod'
      assumes = assumesFromModule mod'
      explicitExports = collectSection typeDescMap assumes section
  in case explicitExports of
    -- No explicit exports: return nothing (only explicit @export annotations count)
    [] -> []
    -- Has explicit exports but no default: mark the topmost as default
    _ | not (any (\ef -> ef.exportIsDefault) explicitExports) ->
        case explicitExports of
          (firstExport : rest) -> firstExport { exportIsDefault = True } : rest
    -- Has explicit exports with default: use as-is
    _ -> explicitExports
 where
  collectSection tdm assumes' (MkSection _ _ _ decls) =
    decls >>= collectDecl tdm assumes'

  collectDecl tdm assumes' = \ case
    Decide _ dec -> maybeToList (buildExportedFunction tdm assumes' dec)
    Section _ sub -> collectSection tdm assumes' sub
    _ -> []


getDefaultFunction :: Module Resolved -> Maybe ExportedFunction
getDefaultFunction =
  List.find isDefaultExport . getExportedFunctions
 where
  isDefaultExport ExportedFunction{exportIsDefault = flag} = flag

-- | Fill in missing return types using type-checker entity info.
-- When a DECIDE has no explicit GIVETH, we look up the function's inferred
-- type from 'EntityInfo' and extract the return type from it.
enrichReturnTypes :: EntityInfo -> [ExportedFunction] -> [ExportedFunction]
enrichReturnTypes entInfo = map enrich
 where
  enrich ef
    | Just _ <- ef.exportReturnType = ef  -- already has a return type
    | otherwise =
        let MkDecide _ _ (MkAppForm _ name _ _) _ = ef.exportDecide
        in ef { exportReturnType = inferReturnType name }

  inferReturnType :: Resolved -> Maybe (Type' Resolved)
  inferReturnType name =
    case Map.lookup (getUnique name) entInfo of
      Just (_, KnownTerm ty _) ->
        Just $ case ty of
          Fun _ _ ret -> ret
          other       -> other
      _ -> Nothing

buildExportedFunction
  :: TypeDescMap
  -> Map.Map Unique (Assume Resolved)
  -> Decide Resolved
  -> Maybe ExportedFunction
buildExportedFunction typeDescMap assumes decide@(MkDecide _ tySig appForm _) = do
  desc <- getAnno decide ^. annDesc
  let parsed = parseDescText (getDesc desc)
  guard (parsed.flags.isExport)
  let givenParams = extractParams typeDescMap tySig
      assumedParams = extractAssumedDependencies typeDescMap assumes decide
  pure
    ExportedFunction
      { exportName = resolvedToText (extractAppFormName appForm)
      , exportDescription = parsed.description
      , exportIsDefault = parsed.flags.isDefault
      , exportParams = givenParams <> assumedParams
      , exportReturnType = extractReturnType tySig
      , exportDecide = decide
      }

extractAppFormName :: AppForm Resolved -> Resolved
extractAppFormName (MkAppForm _ name _ _) = name

extractParams :: TypeDescMap -> TypeSig Resolved -> [ExportedParam]
extractParams typeDescMap (MkTypeSig _ (MkGivenSig _ names) _) =
  fmap toParam names
 where
  toParam (MkOptionallyTypedName ann resolved mType) =
    let paramDesc = fmap getDesc (ann ^. annDesc)
        fallbackDesc = mType >>= getTypeDesc typeDescMap
    in ExportedParam
      { paramName = resolvedToText resolved
      , paramType = mType
      , paramDescription = paramDesc <|> fallbackDesc
      , paramRequired = not (isMaybeType mType)
      }

extractReturnType :: TypeSig Resolved -> Maybe (Type' Resolved)
extractReturnType (MkTypeSig _ _ giveth) =
  (\(MkGivethSig _ ty) -> ty) <$> giveth

resolvedToText :: Resolved -> Text
resolvedToText =
  rawNameToText . rawName . getActual

buildTypeDescMap :: Module Resolved -> TypeDescMap
buildTypeDescMap (MkModule _ _ section) =
  Map.fromList (collectSection section)
 where
  collectSection (MkSection _ _ _ decls) =
    decls >>= collectDecl

  collectDecl = \ case
    Declare _ (MkDeclare ann _ (MkAppForm _ name _ _) _) ->
      case ann ^. annDesc of
        Just desc -> [(getUnique name, getDesc desc)]
        Nothing -> []
    Section _ sub -> collectSection sub
    _ -> []

getTypeDesc :: TypeDescMap -> Type' Resolved -> Maybe Text
getTypeDesc typeDescMap = \ case
  TyApp _ name _ -> Map.lookup (getUnique name) typeDescMap
  _ -> Nothing

-- | Collect all non-function ASSUME declarations from a module.
-- Function-typed ASSUMEs are filtered out per design decision.
-- This includes types that expand to functions via type synonyms.
assumesFromModule :: Module Resolved -> Map.Map Unique (Assume Resolved)
assumesFromModule mod'@(MkModule _ _ section) =
  Map.fromList (collectSection section)
 where
  synonyms = collectTypeSynonyms mod'

  collectSection (MkSection _ _ _ decls) =
    decls >>= collectDecl

  collectDecl = \case
    Assume _ assume@(MkAssume _ _ (MkAppForm _ name _ _) mType) ->
      case mType of
        Just ty | isFunctionTypeExpanded synonyms ty -> []  -- Skip function-typed ASSUMEs
        _ -> [(getUnique name, assume)]
    Section _ sub -> collectSection sub
    _ -> []

-- | Collect all type synonym declarations from a module.
-- Returns a map from type name Unique to the underlying type.
collectTypeSynonyms :: Module Resolved -> Map.Map Unique (Type' Resolved)
collectTypeSynonyms (MkModule _ _ section) =
  Map.fromList (goSection section)
 where
  goSection (MkSection _ _ _ decls) =
    decls >>= goDecl

  goDecl = \case
    Declare _ (MkDeclare _ _ (MkAppForm _ name _ _) (SynonymDecl _ ty)) ->
      [(getUnique name, ty)]
    Section _ sub -> goSection sub
    _ -> []

-- | Check if a type /contains/ a function type anywhere — expanding type
-- synonyms and recursing into parameterised type constructors
-- (@MAYBE OF (FUNCTION FROM A TO B)@, @LIST OF FUNCTION …@, etc.).
-- @\@export@ cannot accept any such parameter because functions can't be
-- passed over JSON regardless of their wrapper.
isFunctionTypeExpanded :: Map.Map Unique (Type' Resolved) -> Type' Resolved -> Bool
isFunctionTypeExpanded synonyms = go Set.empty
 where
  go visited ty = case ty of
    Fun {} -> True
    Forall _ _ inner -> go visited inner
    TyApp _ name args ->
      let u = getUnique name
          expansion = case Map.lookup u synonyms of
            Just expanded | not (Set.member u visited) ->
              go (Set.insert u visited) expanded
            _ -> False
      in expansion || any (go visited) args
    _ -> False

-- | Collect the 'Unique' of every identifier the expression references —
-- whether it appears as a plain variable (@App _ ref []@) or as a function
-- applied to arguments (@App _ ref [arg, ...]@). This is the single canonical
-- dependency collector for an expression body.
--
-- Upstream callers (e.g. 'extractAssumedDependencies') intersect this set
-- with a pre-filtered map (e.g. 'assumesFromModule' drops function-typed
-- ASSUMEs), so semantic specialization happens at the filter step rather
-- than in the collector itself.
collectReferencedUniques :: Expr Resolved -> Set.Set Unique
collectReferencedUniques = referencedIdentifiers . bodyReads

-- | The 'Unique' of every reference in 'references'.
referencedIdentifiers :: BodyReads -> Set.Set Unique
referencedIdentifiers found = Set.fromList (map getUnique found.references)

-- | What the input check of an exported rule reads from the rule's body.
-- 'bodyReads' finds all three in one walk of the body. Each list is in the
-- order the walk meets what it holds: an expression comes before the
-- expressions inside it, and those come in the order of the fields of the
-- syntax tree that hold them. That is not always the order they are written
-- in: an event written with AT first holds its time in its last field, so the
-- walk meets its time after its party and its action.
data BodyReads = MkBodyReads
  { references :: [Resolved]
    -- ^ The identifier of every reference (@App _ ref args@, where @ref@ is a
    -- 'Ref'), whether it is given arguments or not, and of the name after @'s@
    -- in a genitive (@Proj _ x ref@), as the 'Resolved' that the expression
    -- holds, once for each time it is made.
  , readTypes :: [(Resolved, Type' Resolved)]
    -- ^ Every read of an identifier that is given no arguments (@App ann ref []@),
    -- with the type that the checker recorded on the expression that reads it.
    -- That type is the one the read has, which for a polymorphic identifier is
    -- not the declared one: each read of the ASSUME in
    -- @GIVEN a IS A TYPE GIVETH AN a ASSUME x@ is given a type of its own. It can
    -- still hold inference variables, until the substitution that the check
    -- ended with is applied to it, which the caller does. A read that is given
    -- arguments has the type of the call, not of the identifier, and is not in
    -- the list, nor is a read that has no recorded type.
  , localAssumes :: [Assume Resolved]
    -- ^ The ASSUMEs that a @WHERE@ in the expression declares, wherever in the
    -- expression the @WHERE@ stands, also inside a local definition. The parser
    -- accepts an ASSUME among local declarations under @WHERE@ and nowhere else:
    -- a @LET@ holds definitions only. The checker's table of what a module
    -- declares does not hold these, since they are in scope for the expression
    -- alone.
  }

-- | One thing that the walk of a body ('walkBody') finds, at the expression
-- where it finds it.
data BodyRead
  = Applies Resolved Call
    -- ^ An application whose head is a reference (a 'Ref'), with its arguments.
    -- An identifier that is read is an application that is given no arguments.
    -- A genitive @x's f@ is an application of @f@ to @x@: the checker resolves
    -- it to a call of the rule @f@ with @x@ as its one input, also when @f@ is a
    -- computed field of a record, which 'L4.Desugar.desugarComputedFields' turns
    -- into a top-level rule whose one input is the record.
  | DeclaredHere (Assume Resolved)
    -- ^ An ASSUME that a @WHERE@ declares.
  | Opens (Decide Resolved)
    -- ^ The body of a definition under a @WHERE@ or a @LET@ starts here. What
    -- the walk finds up to the matching 'Closes' stands in that body.
  | Closes
    -- ^ The body that the last 'Opens' without its 'Closes' started ends here.

-- | The arguments of an application as the expression holds them, after the
-- annotation of the application, which holds the type that the checker
-- recorded for the whole application: the type of what it gives back.
data Call
  = Positional Anno [Expr Resolved]
    -- ^ @App _ ref args@: the arguments in the order of the inputs.
  | Named Anno [NamedExpr Resolved] (Maybe [Int])
    -- ^ @AppNamed _ ref args order@ (@f WITH x IS 1@): the arguments by name,
    -- and the position of the input that each of them gives, which the checker
    -- records.

-- | What the input check of an exported rule reads from the rule's body, in
-- the order of 'walkBody'. Only an application that gives its arguments in
-- order ('Positional') is a reference here: the check of the rule's own inputs
-- does not read the head of one that gives them by name.
bodyReads :: Expr Resolved -> BodyReads
bodyReads = readsOf . walkBody

readsOf :: [BodyRead] -> BodyReads
readsOf found =
  MkBodyReads
    { references   = [ ref | Applies ref (Positional _ _) <- found ]
    , readTypes    = [ (ref, ty) | Applies ref (Positional ann []) <- found, Just (TypeInfo ty _) <- [ann ^. annInfo] ]
    , localAssumes = [ assume | DeclaredHere assume <- found ]
    }

-- | Walk the expression once, and list what the walk finds.
--
-- The walk meets every expression of the body: each subexpression of an
-- expression, and each expression that one of its other parts holds — the
-- arguments of a named application, the guards of a multi-way IF, the patterns
-- and branches of a CONSIDER (an @EXACTLY@ pattern holds an expression), the
-- parts of a duty and of an event, and the bodies of the local definitions of a
-- @WHERE@ or a @LET@, each between an 'Opens' and its 'Closes'. It does not look
-- into an annotation, an identifier, a type, a literal, or the signature of a
-- local definition or of a lambda, since none of those holds an expression.
-- Every case below names every field, so a field or a constructor added to one
-- of these types does not compile until the walk says what to do with it.
--
-- Each step puts what it finds in front of the list of what the rest of the walk
-- finds, so the walk builds its answer without appending one list to another:
-- the time it takes grows with the size of the body and not with its depth.
walkBody :: Expr Resolved -> [BodyRead]
walkBody body = walkExpr body []
 where
  walkExpr :: Expr Resolved -> [BodyRead] -> [BodyRead]
  walkExpr e rest = case e of
    And        _ l r       -> walkExpr l (walkExpr r rest)
    Or         _ l r       -> walkExpr l (walkExpr r rest)
    RAnd       _ l r       -> walkExpr l (walkExpr r rest)
    ROr        _ l r       -> walkExpr l (walkExpr r rest)
    Implies    _ l r       -> walkExpr l (walkExpr r rest)
    Equals     _ l r       -> walkExpr l (walkExpr r rest)
    Not        _ x         -> walkExpr x rest
    Plus       _ l r       -> walkExpr l (walkExpr r rest)
    Minus      _ l r       -> walkExpr l (walkExpr r rest)
    Times      _ l r       -> walkExpr l (walkExpr r rest)
    DividedBy  _ l r       -> walkExpr l (walkExpr r rest)
    Modulo     _ l r       -> walkExpr l (walkExpr r rest)
    Cons       _ l r       -> walkExpr l (walkExpr r rest)
    Leq        _ l r       -> walkExpr l (walkExpr r rest)
    Geq        _ l r       -> walkExpr l (walkExpr r rest)
    Lt         _ l r       -> walkExpr l (walkExpr r rest)
    Gt         _ l r       -> walkExpr l (walkExpr r rest)
    Proj     ann x f       -> atReference f (Positional ann [x]) (walkExpr x rest)
    Lam        _ _ x       -> walkExpr x rest
    App ann ref args       -> atReference ref (Positional ann args) (walkExprs args rest)
    AppNamed ann ref nes order ->
                              atReference ref (Named ann nes order) (foldr walkNamed rest nes)
    IfThenElse _ c t f     -> walkExpr c (walkExpr t (walkExpr f rest))
    MultiWayIf _ gs other  -> foldr walkGuarded (walkExpr other rest) gs
    Regulative _ d         -> walkDeonton d rest
    Consider   _ x bs      -> walkExpr x (foldr walkBranch rest bs)
    Lit        _ _         -> rest
    Percent    _ x         -> walkExpr x rest
    List       _ xs        -> walkExprs xs rest
    Where      _ x decls   -> [ DeclaredHere assume | LocalAssume _ assume <- decls ]
                                ++ walkExpr x (foldr walkLocalDecl rest decls)
    LetIn      _ decls x   -> foldr walkLocalDecl (walkExpr x rest) decls
    Event      _ ev        -> walkEvent ev rest
    Fetch      _ x         -> walkExpr x rest
    Env        _ x         -> walkExpr x rest
    Post       _ u h b     -> walkExpr u (walkExpr h (walkExpr b rest))
    Concat     _ xs        -> walkExprs xs rest
    AsString   _ x         -> walkExpr x rest
    Breach     _ by why    -> walkMaybe by (walkMaybe why rest)
    Inert      _ _ _       -> rest

  walkExprs :: [Expr Resolved] -> [BodyRead] -> [BodyRead]
  walkExprs xs rest = foldr walkExpr rest xs

  walkMaybe :: Maybe (Expr Resolved) -> [BodyRead] -> [BodyRead]
  walkMaybe mx rest = maybe rest (`walkExpr` rest) mx

  atReference :: Resolved -> Call -> [BodyRead] -> [BodyRead]
  atReference ref call rest = case ref of
    Ref _ _ _      -> Applies ref call : rest
    Def _ _        -> rest
    OutOfScope _ _ -> rest

  walkNamed :: NamedExpr Resolved -> [BodyRead] -> [BodyRead]
  walkNamed (MkNamedExpr _ _ x) rest = walkExpr x rest

  walkGuarded :: GuardedExpr Resolved -> [BodyRead] -> [BodyRead]
  walkGuarded (MkGuardedExpr _ c x) rest = walkExpr c (walkExpr x rest)

  walkBranch :: Branch Resolved -> [BodyRead] -> [BodyRead]
  walkBranch (MkBranch _ lhs x) rest = case lhs of
    When _ p    -> walkPattern p (walkExpr x rest)
    Otherwise _ -> walkExpr x rest

  walkPattern :: Pattern Resolved -> [BodyRead] -> [BodyRead]
  walkPattern p rest = case p of
    PatVar  _ _    -> rest
    PatApp  _ _ ps -> foldr walkPattern rest ps
    PatCons _ l r  -> walkPattern l (walkPattern r rest)
    PatExpr _ x    -> walkExpr x rest
    PatLit  _ _    -> rest

  walkDeonton :: Deonton Resolved -> [BodyRead] -> [BodyRead]
  walkDeonton (MkDeonton _ who act due hence lest) rest =
    walkExpr who (walkAction act (walkMaybe due (walkMaybe hence (walkMaybe lest rest))))

  walkAction :: RAction Resolved -> [BodyRead] -> [BodyRead]
  walkAction (MkAction _ _ p provided) rest = walkPattern p (walkMaybe provided rest)

  walkEvent :: Event Resolved -> [BodyRead] -> [BodyRead]
  walkEvent (MkEvent _ who act stamp _) rest =
    walkExpr who (walkExpr act (walkExpr stamp rest))

  walkLocalDecl :: LocalDecl Resolved -> [BodyRead] -> [BodyRead]
  walkLocalDecl decl rest = case decl of
    LocalDecide _ d@(MkDecide _ _ _ x) -> Opens d : walkExpr x (Closes : rest)
    LocalAssume _ _                    -> rest

-- | Extract ASSUME declarations that are referenced by a DECIDE body.
-- Returns ExportedParams for each ASSUME that the function depends on.
extractAssumedDependencies
  :: TypeDescMap
  -> Map.Map Unique (Assume Resolved)
  -> Decide Resolved
  -> [ExportedParam]
extractAssumedDependencies typeDescMap assumes (MkDecide _ _ _ body) =
  let
    referencedUniques = collectReferencedUniques body
    matchingAssumes =
      [ assume
      | (uniq, assume) <- Map.toList assumes
      , Set.member uniq referencedUniques
      ]
  in
    map (assumeToParam typeDescMap) matchingAssumes

-- | Convert an ASSUME declaration to an ExportedParam
assumeToParam :: TypeDescMap -> Assume Resolved -> ExportedParam
assumeToParam typeDescMap (MkAssume ann _ (MkAppForm _ name _ _) mType) =
  let
    paramDesc = fmap getDesc (ann ^. annDesc)
    fallbackDesc = mType >>= getTypeDesc typeDescMap
  in
    ExportedParam
      { paramName = resolvedToText name
      , paramType = mType
      , paramDescription = paramDesc <|> fallbackDesc
      , paramRequired = not (isMaybeType mType)
      }

-- | Check if a type annotation is MAYBE (i.e., the parameter is optional).
isMaybeType :: Maybe (Type' Resolved) -> Bool
isMaybeType (Just (TyApp _ name [_inner])) = getUnique name == maybeUnique
isMaybeType _ = False

-- | Extract (name, type) pairs for ASSUME declarations referenced by a DECIDE body.
-- Used by CodeGen to generate LET bindings for ASSUME values.
extractAssumeParamTypes
  :: Module Resolved
  -> Decide Resolved
  -> [(Text, Type' Resolved)]
extractAssumeParamTypes mod' decide =
  [ (resolvedToText r, ty) | (r, ty) <- extractAssumeParamResolveds mod' decide ]

-- | Like 'extractAssumeParamTypes' but returns the 'Resolved' name instead of
-- its textual form. Consumers that need to bind the ASSUME in a local scope
-- (e.g. MLIR lowering) need the Resolved so subsequent in-scope references
-- resolve to the local binding.
extractAssumeParamResolveds
  :: Module Resolved
  -> Decide Resolved
  -> [(Resolved, Type' Resolved)]
extractAssumeParamResolveds mod' (MkDecide _ _ _ body) =
  let
    assumes = assumesFromModule mod'
    referencedUniques = collectReferencedUniques body
    matchingAssumes =
      [ assume
      | (uniq, assume) <- Map.toList assumes
      , Set.member uniq referencedUniques
      ]
  in
    mapMaybe assumeToResolvedInfo matchingAssumes
 where
  assumeToResolvedInfo :: Assume Resolved -> Maybe (Resolved, Type' Resolved)
  assumeToResolvedInfo (MkAssume _ _ (MkAppForm _ name _ _) (Just ty)) =
    Just (name, ty)
  assumeToResolvedInfo _ = Nothing

-- | Check if a type contains any unresolved inference variables.
-- Types with inference variables cannot be used for implicit ASSUMEs
-- because their concrete type is not yet known.
hasTypeInferenceVars :: Type' Resolved -> Bool
hasTypeInferenceVars = \case
  Type   _ -> False
  TyApp  _ _n ns -> any hasTypeInferenceVars ns
  Fun    _ opts ty -> any hasNamedTypeInferenceVars opts || hasTypeInferenceVars ty
  Forall _ _ ty -> hasTypeInferenceVars ty
  InfVar {} -> True
 where
  hasNamedTypeInferenceVars :: OptionallyNamedType Resolved -> Bool
  hasNamedTypeInferenceVars (MkOptionallyNamedType _ _ ty) = hasTypeInferenceVars ty

-- | Extract implicit ASSUME parameters from type check errors.
-- When a variable is used without declaration, the type checker records an
-- OutOfScopeError with the inferred type. If the type is fully resolved
-- (no inference variables), we can treat this as an implicit ASSUME.
--
-- This enables programs to omit explicit ASSUME declarations when the type
-- can be inferred from usage context.
--
-- Example: `temperature + 0` forces `temperature :: NUMBER`
-- The OutOfScopeError for `temperature` will have type NUMBER, which we
-- can extract as an implicit ASSUME.
--
-- Function-typed errors are dropped: they're produced by overload-resolution
-- branches exploring prelude names like `min`/`max` (the Check monad's
-- 'Alternative' runs both branches of `choose <|> ambiguousTerm` and
-- concatenates errors, so failing branches leak), and function values can't
-- be supplied as JSON inputs anyway, so admitting them as implicit assumes
-- would only pollute every export's parameter schema.
extractImplicitAssumeParams
  :: [CheckErrorWithContext]
  -> [(Text, Type' Resolved)]
extractImplicitAssumeParams errors =
  [ (nameToText name, ty)
  | MkCheckErrorWithContext{kind = OutOfScopeError name ty} <- errors
  , not (hasTypeInferenceVars ty)
  , not (isFunctionType ty)
  ]
  where
    isFunctionType Fun{} = True
    isFunctionType _ = False

-- | Validate that no @export-decorated DECIDE has an input that a request
-- cannot carry: a function-typed input, or an input of a type that contains
-- an EVENT or a DEONTIC. The input is either a GIVEN parameter, or an ASSUME
-- that the body uses.
--
-- Function-typed inputs can't be evaluated end-to-end: GIVENs can't be
-- passed over JSON, and function-typed ASSUMEs stay 'ValAssumed' at
-- runtime, causing a stuck "assumed term" error when the body invokes them.
-- That refusal looks at the types that are written, and at the ASSUMEs of
-- this module: a GIVEN that has no written type, and an ASSUME of an imported
-- module, are not looked at for it.
--
-- An EVENT and a DEONTIC have no JSON form either. The service's input decoder
-- reads a JSON object only into a declared record, and both types are builtin
-- and have no declaration, so a request cannot supply either one. Without this
-- check, the published schema of such a rule would be a bare @object@, every
-- evaluation of a rule that takes an EVENT would answer 422, and a rule that
-- takes a DEONTIC would give a wrong answer without a word when the request
-- sent a string or a number for it. That refusal looks at every input, however
-- its type is known:
--
-- * a GIVEN with a written type;
--
-- * a GIVEN with no written type, whose type is the one that the checker
--   inferred for it ('inferredGivenTypes'), once the substitution that the
--   check ended with is applied to it. One whose type is still open holds
--   neither, and is accepted;
--
-- * an ASSUME that the body reads, wherever it is declared, in this module or
--   in an imported one: 'AssumedTerm' is what marks it in the 'EntityInfo',
--   and a definition that has a value, such as a DEONTIC that a MEANS gives, is
--   not marked and is not an input. It is looked at for the type it is declared
--   with, and for the type at each read of it in the body, which is where a
--   polymorphic ASSUME (@GIVEN a IS A TYPE GIVETH AN a ASSUME x@) holds a
--   DEONTIC or an EVENT ('readTypes'). A call of an ASSUME that is given
--   arguments has the type of its result and is not looked at;
--
-- * an ASSUME that the body declares itself, in a @WHERE@, and reads: the
--   'EntityInfo' does not hold it, so it is found in the body
--   ('localAssumes') and its declared type is the one that the checker
--   recorded on the declaration. The reads of it are looked at as for any other;
--
-- * an ASSUME that a rule of this module reads, when the exported rule calls
--   that rule, directly or through other rules of this module, and the read is
--   at a type that holds an EVENT or a DEONTIC under the calls that lead to it
--   ('reachedThroughCalls'). That covers a polymorphic rule, under the
--   exported rule's own @WHERE@ or not, that reads a polymorphic ASSUME at its
--   own type variable, when a call gives the variable such a type. The error
--   names the rule that reads the ASSUME, unless that is the exported rule
--   itself. A rule of an imported module is not followed: the checker's view of
--   an import holds the types of its rules and not their bodies.
--
-- One input is refused once, however many such types it holds: for the EVENT or
-- the DEONTIC that the walk meets first ('carriedUnsendable'). An ASSUME that
-- the exported rule's own body is refused for is not refused again for a rule
-- that it calls.
validateExportInputs :: Substitution -> EntityInfo -> Module Resolved -> [CheckErrorWithContext]
validateExportInputs subst ei mod' =
  let synonyms = collectTypeSynonyms mod'
      assumes  = allAssumesFromModule mod'
      carried  = carriedUnsendable ei
      exported = collectExportedDecides mod'
      -- every top-level rule, walked when the check first needs it, at most
      -- once: an exported rule for its own inputs and for the rules it calls,
      -- and every other rule only if an exported rule reaches it by calls
      walked   = walkTopLevel mod'
      reached  = reachedThroughCalls subst ei carried walked exported
      found decide@(MkDecide _ _ _ body) =
        case LazyMap.lookup (decideUnique decide) walked of
          Just [w] -> w.bodyFound
          _        -> bodyReads body
      -- one pass per kind of input a request cannot carry, each with the inputs
      -- it looks at; both read the one walk of the body
      functionTypes, unsendables :: Decide Resolved -> BodyReads -> [CheckErrorWithContext]
      functionTypes decide bodyFound =
        checkOneExport
          (\ty -> if isFunctionTypeExpanded synonyms ty then Just mkExportFunErr else Nothing)
          decide
          (writtenInputs assumes decide bodyFound)
      unsendables decide@(MkDecide _ _ (MkAppForm _ fnName _ _) _) bodyFound =
        let direct =
              [ (input, holds)
              | (input, tys) <- inferredInputs subst ei decide bodyFound
              , Just holds <- [listToMaybe (mapMaybe carried tys)]
              ]
            refusedHere = Set.fromList [ getUnique input | (input, _) <- direct ]
        in [ mkExportUnsendableErr holds fnName input Nothing | (input, holds) <- direct ]
           ++
           [ mkExportUnsendableErr holds fnName assume readerNamed
           | (assume, holds, readBy) <- Map.findWithDefault [] (getUnique fnName) reached
           , not (getUnique assume `Set.member` refusedHere)
           , let readerNamed = if getUnique readBy == getUnique fnName then Nothing else Just readBy
           ]
  in [ err
     | decide <- exported
     , let bodyFound = found decide
     , pass <- [functionTypes, unsendables]
     , err <- pass decide bodyFound
     ]

-- | A top-level rule of the module, walked: what its own input check reads
-- ('bodyReads'), and the rules that the walk finds in it ('rulesOf').
data Walked = MkWalked
  { bodyFound :: BodyReads
  , rulesIn   :: [Rule]
  }

-- | Every top-level DECIDE of the module, also in a section, by its identifier,
-- walked once when it is first looked up and not before.
walkTopLevel :: Module Resolved -> LazyMap.Map Unique [Walked]
walkTopLevel (MkModule _ _ section) =
  LazyMap.fromListWith (flip (<>)) [ (decideUnique d, [walkDecide d]) | d <- goSection section ]
 where
  goSection (MkSection _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Decide _ d    -> [d]
    Section _ sub -> goSection sub
    _             -> []

walkDecide :: Decide Resolved -> Walked
walkDecide d@(MkDecide _ _ _ body) =
  let events = walkBody body
  in MkWalked { bodyFound = readsOf events, rulesIn = rulesOf d events }

-- | A definition whose body the check follows: a top-level DECIDE, or one under
-- a @WHERE@ or a @LET@ of one, with what its own body holds. A definition under
-- it has a 'Rule' of its own, and is in 'within'.
data Rule = MkRule
  { ruleName :: Resolved
  , topRule  :: Resolved
    -- ^ The top-level DECIDE that it stands in, which is itself for a top-level one.
  , declared :: Maybe (Type' Resolved)
    -- ^ Its type, as the checker recorded it on the definition.
  , own      :: Set.Set Unique
    -- ^ The type variables that its type quantifies (@GIVEN a IS A TYPE@).
  , scope    :: Set.Set Unique
    -- ^ Those and the type variables of the definitions that it stands in,
    -- which are the type variables that a type in its body can name.
  , applies  :: [(Resolved, Call)]
    -- ^ The applications in its body and not in the body of a definition under it.
  , within   :: [Resolved]
    -- ^ The definitions directly under it.
  }

-- | The rules in the body of a top-level DECIDE, from the walk of its body,
-- the DECIDE itself among them.
rulesOf :: Decide Resolved -> [BodyRead] -> [Rule]
rulesOf topDecide = go [open Set.empty topDecide] []
 where
  topName = decideName topDecide
  -- a rule whose body the walk is in: the definition, the type variables in
  -- scope, and what the walk has found in it so far, the last first
  open outer d = (d, outer `Set.union` quantifiedBy d, [], [])
  close (d, inScope, apps, kids) =
    MkRule
      { ruleName = decideName d
      , topRule  = topName
      , declared = decideType d
      , own      = quantifiedBy d
      , scope    = inScope
      , applies  = reverse apps
      , within   = reverse kids
      }
  go stack done events = case (stack, events) of
    ((d, inScope, apps, kids) : outer, Applies ref call : rest) ->
      go ((d, inScope, (ref, call) : apps, kids) : outer) done rest
    ((_, inScope, _, _) : _, Opens d : rest) ->
      go (open inScope d : stack) done rest
    (inner@(d, _, _, _) : (pd, pScope, pApps, pKids) : outer, Closes : rest) ->
      go ((pd, pScope, pApps, decideName d : pKids) : outer) (close inner : done) rest
    (_, _ : rest) -> go stack done rest
    (_, [])       -> map close stack <> done

decideName :: Decide Resolved -> Resolved
decideName (MkDecide _ _ (MkAppForm _ name _ _) _) = name

decideUnique :: Decide Resolved -> Unique
decideUnique = getUnique . decideName

decideType :: Decide Resolved -> Maybe (Type' Resolved)
decideType (MkDecide ann _ _ _) = case ann ^. annInfo of
  Just (TypeInfo ty _) -> Just ty
  _                    -> Nothing

quantifiedBy :: Decide Resolved -> Set.Set Unique
quantifiedBy d = case decideType d of
  Just (Forall _ vars _) -> Set.fromList (map getUnique vars)
  _                      -> Set.empty

-- | What a rule reaches: a read of an ASSUME, by a rule (the top-level DECIDE
-- that the read stands in), at a type that holds an EVENT or a DEONTIC
-- ('Holds'), or at a type that holds one when a type variable of the rule, or
-- of a definition that it stands in, is given a type that holds one
-- ('AtVariable').
data Reach = MkReach
  { at     :: Unique
    -- ^ The rule that reaches the read.
  , assume :: Resolved
  , reader :: Resolved
  , fact   :: Fact
  }

data Fact
  = Holds Unsendable
  | AtVariable Unique

-- | How a rule gets to the rules whose reads it reaches.
data Edge
  = StandsIn
    -- ^ The rule is a definition under the other one, which reaches what it
    -- reads whether or not it calls it.
  | CalledWith (Map.Map Unique [Type' Resolved])
    -- ^ The other rule calls it, and the call gives each of its own type
    -- variables these types ('callBindings'), worked out when first needed.

-- | For each rule of the module that an exported rule reaches by calls, each
-- ASSUME whose read it reaches at a type that holds an EVENT or a DEONTIC, once
-- each, in the order of the identifiers of the ASSUMEs: the ASSUME, which of
-- the two it holds, and the rule that reads it. That is the rule itself when it
-- is one of the readers, and otherwise one of them, the same one on every run.
--
-- What is followed. The rules of the module that the exported rules call,
-- through any number of calls, each with the definitions under its @WHERE@s and
-- @LET@s. A rule that is passed on as a value without being called is followed
-- as though it were called there. A read in a definition under a rule counts
-- for that rule whether or not the definition is called, as it does for the
-- exported rule's own input check.
--
-- How a polymorphic rule is followed. A read of an ASSUME has the type that
-- the checker recorded at the read, which in a rule that quantifies a type
-- variable can be the variable itself. The type of each call of the rule then
-- says what the variable is at that call: matching the rule's declared type,
-- its FORALL taken off, one way against the types that the checker recorded
-- at the call — of each argument, and of the result — gives each variable the
-- types that the call gives it ('callBindings'). 'carriedUnsendable' finds an
-- EVENT or a DEONTIC in every type argument and nowhere inside a function type,
-- which are the places 'typeNamesMet' lists, so a type made by putting types
-- for its variables holds one exactly when the type does, or one of the
-- variables at those places is given a type that holds one. That is what
-- crosses a call: a read at a variable of the callee becomes, in the caller,
-- a read at each type that the call gives the variable, which can itself be a
-- variable of the caller, crossed in turn at the caller's own calls. A read at
-- a variable of a definition that is not called does not cross 'StandsIn':
-- nothing gives the variable a type there. A variable of a definition that the
-- callee stands in crosses a call unchanged, since it names the same type in
-- the caller, which stands in the same definition.
--
-- Why that misses no refusal of a program that type-checks. The checker gives
-- each call of a polymorphic rule its declared type, its variables replaced by
-- types, and makes that equal to the types at the call, up to synonyms, which
-- the match expands on either side. So the match gives each variable that
-- stands in the declared type outside a function type the type that the checker
-- gave it at the call. A variable that the match leaves without a type — the
-- two sides differ in shape, or the synonyms run deeper than
-- 'synonymExpansionFuel' — is treated as given no type, and a read at it is
-- accepted; so is a variable given a type that is still open, as an input whose
-- type is still open is. A variable that stands nowhere in the declared type
-- is not given a type by any call, and the rule's body can use a value of that
-- type only as a value of the variable, never as an EVENT or a DEONTIC.
--
-- The time it takes. Each rule that an exported rule reaches is walked once,
-- and what it reaches is worked out once for the module, not once per exported
-- rule. A fact ('Reach') is kept for a rule once for each ASSUME and each
-- variable, or for holding an EVENT or a DEONTIC, and for each of the two kinds
-- of reader: the top-level rule that the rule stands in, and any other, of
-- which only the first that arrives is kept. So the facts of a rule do not grow
-- with the number of rules that read an ASSUME, and each is passed to each rule
-- that calls it or that it stands in once. A rule that calls itself, or rules
-- that call each other, stop when no new fact arrives. What a call gives the
-- variables is worked out only when a read at a variable crosses it.
reachedThroughCalls
  :: Substitution
  -> EntityInfo
  -> (Type' Resolved -> Maybe Unsendable)
  -> LazyMap.Map Unique [Walked]
  -> [Decide Resolved]
  -> Map.Map Unique [(Resolved, Unsendable, Resolved)]
reachedThroughCalls subst ei carried walked exported =
  Map.mapWithKey chooseReaders (settle Set.empty Map.empty (concatMap ownReaches (Map.elems rules)))
 where
  sub = substituteInfVars subst

  -- the top-level rules that the exported rules reach by calls, themselves too
  reachedTop :: Set.Set Unique
  reachedTop = reach Set.empty (map decideUnique exported)
   where
    reach seen [] = seen
    reach seen (u : us)
      | u `Set.member` seen = reach seen us
      | otherwise = case LazyMap.lookup u walked of
          Nothing -> reach seen us
          Just ws ->
            reach (Set.insert u seen)
              ([ c | w <- ws, r <- w.rulesIn, (ref, _) <- r.applies, let c = getUnique ref, LazyMap.member c walked ] <> us)

  reachedWalks :: [Walked]
  reachedWalks = [ w | u <- Set.toList reachedTop, w <- LazyMap.findWithDefault [] u walked ]

  rules :: Map.Map Unique Rule
  rules = Map.fromList [ (getUnique r.ruleName, r) | w <- reachedWalks, r <- w.rulesIn ]

  -- the ASSUMEs that a WHERE in those rules declares, with the type that the
  -- checker recorded on each declaration
  localAssumeTypes :: Map.Map Unique [Type' Resolved]
  localAssumeTypes =
    Map.fromList
      [ (getUnique name, [ ty | Just (TypeInfo ty _) <- [getAnno a ^. annInfo] ])
      | w <- reachedWalks
      , a@(MkAssume _ _ (MkAppForm _ name _ _) _) <- w.bodyFound.localAssumes
      ]

  assumeTypes :: Unique -> Maybe [Type' Resolved]
  assumeTypes u = case Map.lookup u ei of
    Just (_, KnownTerm ty AssumedTerm) -> Just [ty]
    _                                  -> Map.lookup u localAssumeTypes

  -- for each rule, the rules that call it or that it stands in
  edgesInto :: Map.Map Unique [(Unique, Edge)]
  edgesInto =
    Map.fromListWith (<>) $
      [ (getUnique ref, [(getUnique r.ruleName, CalledWith (callBindings ei sub callee call))])
      | r <- Map.elems rules
      , (ref, call) <- r.applies
      , Just callee <- [Map.lookup (getUnique ref) rules]
      ]
      <>
      [ (getUnique child, [(getUnique r.ruleName, StandsIn)])
      | r <- Map.elems rules
      , child <- r.within
      ]

  -- what a type at a read, or at a call in a rule with these type variables in
  -- scope, comes to
  factsAt :: Set.Set Unique -> Type' Resolved -> [Fact]
  factsAt inScope ty = case carried ty of
    Just holds -> [Holds holds]
    Nothing
      | Set.null inScope -> []
      | otherwise ->
          map AtVariable (Set.toList (Set.fromList (typeNamesMet ty) `Set.intersection` inScope))

  -- the reads of ASSUMEs in a rule's own body: at the type each ASSUME is
  -- declared with, and at the type recorded at the read, as the exported
  -- rule's own input check looks at them
  ownReaches :: Rule -> [Reach]
  ownReaches r =
    [ MkReach (getUnique r.ruleName) ref r.topRule f
    | (ref, Positional ann args) <- r.applies
    , Just declaredAs <- [assumeTypes (getUnique ref)]
    , ty <- declaredAs <> [ readAs | null args, Just (TypeInfo readAs _) <- [ann ^. annInfo] ]
    , f <- factsAt r.scope (sub ty)
    ]

  -- each fact once, by the rule, the ASSUME, whether the reader is the
  -- top-level rule that the rule stands in, and the variable or that it holds
  -- one; the facts that hold one, by rule
  settle _ holding [] = holding
  settle seen holding (x : xs)
    | key `Set.member` seen = settle seen holding xs
    | otherwise = settle (Set.insert key seen) holding' (onward x <> xs)
   where
    key = (x.at, getUnique x.assume, readByOwnTop x, case x.fact of { Holds _ -> Nothing; AtVariable v -> Just v })
    holding' = case x.fact of
      Holds holds  -> Map.insertWith (<>) x.at [(x.assume, holds, x.reader)] holding
      AtVariable _ -> holding

  -- whether the read of a fact stands in the top-level rule that the rule of
  -- the fact stands in, that rule itself for a top-level rule
  readByOwnTop :: Reach -> Bool
  readByOwnTop x = case Map.lookup x.at rules of
    Just r  -> getUnique x.reader == getUnique r.topRule
    Nothing -> False

  -- what a fact of a rule comes to in each rule that calls it or that it
  -- stands in
  onward :: Reach -> [Reach]
  onward x =
    [ MkReach caller x.assume x.reader f
    | Just r <- [Map.lookup x.at rules]
    , (caller, edge) <- Map.findWithDefault [] x.at edgesInto
    , Just callerRule <- [Map.lookup caller rules]
    , f <- case x.fact of
        Holds _ -> [x.fact]
        AtVariable v
          | v `Set.member` r.own -> case edge of
              StandsIn            -> []
              CalledWith bindings -> concatMap (factsAt callerRule.scope) (Map.findWithDefault [] v bindings)
          -- a variable of a definition that the rule stands in; a top-level
          -- rule has none, since its scope is its own variables
          | getUnique r.topRule == x.at -> []
          | otherwise -> [x.fact]
    ]

  chooseReaders :: Unique -> [(Resolved, Unsendable, Resolved)] -> [(Resolved, Unsendable, Resolved)]
  chooseReaders u holding =
    Map.elems (Map.fromListWith preferred [ (getUnique a, hit) | hit@(a, _, _) <- holding ])
   where
    rank (_, _, readBy) = (getUnique readBy /= u, getUnique readBy)
    preferred new old = if rank new < rank old then new else old

-- | What a call of a rule gives each of the rule's own type variables, by a
-- one-way match of the rule's declared type, its FORALL taken off, against the
-- types that the checker recorded at the call: each argument against the input
-- that it gives, and the whole call against the result. A rule that is named
-- without arguments is matched as a whole. The types at the call have the
-- substitution that the check ended with applied to them.
callBindings :: EntityInfo -> (Type' Resolved -> Type' Resolved) -> Rule -> Call -> Map.Map Unique [Type' Resolved]
callBindings ei sub callee call = case callee.declared of
  Just ty | not (Set.null callee.own) ->
    Map.fromListWith (flip (<>)) [ (v, [t]) | (v, t) <- bindings (sub (withoutForall ty)) ]
  _ -> Map.empty
 where
  withoutForall = \case
    Forall _ _ inner -> withoutForall inner
    ty               -> ty

  typeAt :: Anno -> Maybe (Type' Resolved)
  typeAt ann = case ann ^. annInfo of
    Just (TypeInfo ty _) -> Just (sub ty)
    _                    -> Nothing

  against p = maybe [] (matchTypes ei callee.own p)

  bindings ty = case call of
    Positional ann [] -> against ty (typeAt ann)
    Positional ann args -> case ty of
      Fun _ inputs result | length inputs == length args ->
        concat (zipWith (\i a -> against (optionallyNamedTypeType i) (typeAt (getAnno a))) inputs args)
          <> against result (typeAt ann)
      _ -> []
    Named ann args (Just order) -> case ty of
      Fun _ inputs result ->
        concat
          [ against (optionallyNamedTypeType i) (typeAt (getAnno a))
          | (pos, MkNamedExpr _ _ a) <- zip order args
          , i : _ <- [drop pos inputs]
          ]
          <> against result (typeAt ann)
      _ -> []
    Named _ _ Nothing -> []

-- | Match a type that names the given type variables against a type, one way:
-- each variable, where it stands, against what stands there in the other type.
-- A synonym on either side is expanded when the two sides differ there, as the
-- checker does when it makes them equal, up to 'synonymExpansionFuel'
-- expansions along one path. Where the two differ otherwise, nothing is given.
matchTypes :: EntityInfo -> Set.Set Unique -> Type' Resolved -> Type' Resolved -> [(Unique, Type' Resolved)]
matchTypes ei vars = go synonymExpansionFuel
 where
  go :: Int -> Type' Resolved -> Type' Resolved -> [(Unique, Type' Resolved)]
  go fuel pat act = case (pat, act) of
    (TyApp _ v [], _) | getUnique v `Set.member` vars -> [(getUnique v, act)]
    (Forall _ _ inner, _) -> go fuel inner act
    (_, Forall _ _ inner) -> go fuel pat inner
    (TyApp _ n ps, TyApp _ m as)
      | getUnique n == getUnique m, length ps == length as -> concat (zipWith (go fuel) ps as)
    (Fun _ ps r, Fun _ as r')
      | length ps == length as ->
          concat (zipWith (go fuel) (map optionallyNamedTypeType ps) (map optionallyNamedTypeType as))
            <> go fuel r r'
    _ | fuel <= 0                -> []
      | Just pat' <- expand pat -> go (fuel - 1) pat' act
      | Just act' <- expand act -> go (fuel - 1) pat act'
      | otherwise               -> []

  expand = \case
    TyApp _ n args
      | Just (_, KnownType _ params (Just body)) <- Map.lookup (getUnique n) ei
      , length params == length args ->
          Just (substituteType (Map.fromList (zipWith (\p a -> (getUnique p, a)) params args)) body)
    _ -> Nothing

-- | Collect every DECIDE whose description carries the @export flag.
collectExportedDecides :: Module Resolved -> [Decide Resolved]
collectExportedDecides (MkModule _ _ section) = goSection section
 where
  goSection (MkSection _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Decide _ d | isExportedDecide d -> [d]
    Section _ sub -> goSection sub
    _ -> []

-- | Is this definition published with @\@export@ (or @\@export default@,
-- or a @\@desc@ that starts @export@ or @default@)? Polymorphic in the pass
-- so the type checker can consult it before resolution.
isExportedDecide :: Decide n -> Bool
isExportedDecide decide =
  case getAnno decide ^. annDesc of
    Just desc -> (parseDescText (getDesc desc)).flags.isExport
    Nothing   -> False

-- | Like 'assumesFromModule' but WITHOUT the function-type filter —
-- so the validator sees every ASSUME and can flag function-typed ones.
allAssumesFromModule :: Module Resolved -> Map.Map Unique (Assume Resolved)
allAssumesFromModule (MkModule _ _ section) =
  Map.fromList (collectSection section)
 where
  collectSection (MkSection _ _ _ decls) = decls >>= collectDecl
  collectDecl = \case
    Assume _ assume@(MkAssume _ _ (MkAppForm _ name _ _) _) ->
      [(getUnique name, assume)]
    Section _ sub -> collectSection sub
    _ -> []

-- | The decision about one input type: not refused, or refused with the error
-- that names the function and the input.
type ExportRefusal = Type' Resolved -> Maybe (Resolved -> Resolved -> CheckErrorWithContext)

-- | An input of an exported rule: the identifier that an error names, and the
-- types that it is looked at for, in order. The first of them that is refused
-- gives the error, so an input is refused once, however many of its types are.
type ExportInput = (Resolved, [Type' Resolved])

checkOneExport
  :: ExportRefusal
  -> Decide Resolved
  -> [ExportInput]
  -> [CheckErrorWithContext]
checkOneExport refusal (MkDecide _ _ (MkAppForm _ fnName _ _) _) inputs =
  [ mkErr fnName paramName
  | (paramName, tys) <- inputs
  , Just mkErr <- [listToMaybe (mapMaybe refusal tys)]
  ]

-- | The inputs whose type is written: the GIVENs that have one, then the
-- ASSUMEs of this module that the body reads (those that 'assumes' holds).
-- What the body reads is used only when the module has an ASSUME.
writtenInputs
  :: Map.Map Unique (Assume Resolved)
  -> Decide Resolved
  -> BodyReads
  -> [ExportInput]
writtenInputs assumes (MkDecide _ (MkTypeSig _ (MkGivenSig _ names) _) _ _) found =
  let referenced = referencedIdentifiers found
  in [ (paramName, [ty])
     | MkOptionallyTypedName _ paramName (Just ty) <- names
     ]
     ++
     [ (paramName, [ty])
     | (uniq, MkAssume _ _ (MkAppForm _ paramName _ _) (Just ty)) <- Map.toList assumes
     , Set.member uniq referenced
     ]

-- | Every input that the checker knows a type for: the GIVENs, with the
-- inferred type of one that has no written type, then every ASSUME that the
-- body reads, whichever module declares it, or the body itself in a WHERE. An
-- ASSUME is looked at for the type it is declared with, and then for the type
-- that the checker recorded at each read of it in the body
-- ('readTypes'): the two differ for a polymorphic ASSUME, which is
-- declared with a type variable and read at a type of its own.
inferredInputs
  :: Substitution
  -> EntityInfo
  -> Decide Resolved
  -> BodyReads
  -> [ExportInput]
inferredInputs subst ei (MkDecide _ (MkTypeSig _ (MkGivenSig _ names) _) (MkAppForm _ fnName _ _) _) found =
  [ (paramName, [substituteInfVars subst ty])
  | MkOptionallyTypedName _ paramName mType <- names
  , Just ty <- [mType <|> Map.lookup (getUnique paramName) inferredTypes]
  ]
  ++
  [ (ref, substituteInfVars subst <$> declared ++ Map.findWithDefault [] uniq readAs)
  | (uniq, (ref, declared)) <- Map.toList assumedTerms
  ]
 where
  inferredTypes = inferredGivenTypes ei fnName

  -- the ASSUMEs that the body reads, by identifier, one for each, with the
  -- types that they are declared with: those of the module and its imports,
  -- from the entity table, and those that the body declares in a WHERE, from
  -- the type that the checker recorded on the declaration
  assumedTerms :: Map.Map Unique (Resolved, [Type' Resolved])
  assumedTerms =
    Map.fromList $
      [ (getUnique ref, (ref, [ty]))
      | ref <- found.references
      , Just (_, KnownTerm ty AssumedTerm) <- [Map.lookup (getUnique ref) ei]
      ]
      ++
      [ (getUnique name, (name, [ ty | Just (TypeInfo ty _) <- [getAnno assume ^. annInfo] ]))
      | assume@(MkAssume _ _ (MkAppForm _ name _ _) _) <- found.localAssumes
      , Set.member (getUnique name) readUniques
      ]

  readUniques = referencedIdentifiers found

  -- the types recorded at the reads of each of those ASSUMEs, in the order
  -- read; the reads of anything else are not kept. The list is put together
  -- from its last read to its first, so that each read is added at the front.
  readAs :: Map.Map Unique [Type' Resolved]
  readAs =
    Map.fromListWith (<>)
      [ (uniq, [ty])
      | (ref, ty) <- reverse found.readTypes
      , let uniq = getUnique ref
      , Map.member uniq assumedTerms
      ]

-- | The type that the checker inferred for each GIVEN of a function, by the
-- identifier of the GIVEN, read from the function's own type in the 'EntityInfo'.
-- A type that has no written form is an inference variable until the
-- substitution that the check ended with is applied to it, which the caller does.
-- A GIVEN that is a type parameter (@GIVEN a IS A TYPE@) is not an argument of
-- the function type and is not in the answer, which is why the GIVENs are found
-- by identifier and not by position.
inferredGivenTypes :: EntityInfo -> Resolved -> Map.Map Unique (Type' Resolved)
inferredGivenTypes ei fnName =
  case Map.lookup (getUnique fnName) ei of
    Just (_, KnownTerm funType _) ->
      Map.fromList
        [ (getUnique paramName, ty)
        | MkOptionallyNamedType _ (Just paramName) ty <- argumentTypes funType
        ]
    _ -> Map.empty
 where
  argumentTypes = \case
    Forall _ _ inner -> argumentTypes inner
    Fun _ onts _     -> onts
    _                -> []

mkExportFunErr :: Resolved -> Resolved -> CheckErrorWithContext
mkExportFunErr fnName paramName =
  MkCheckErrorWithContext
    { kind    = ExportFunctionTypeInput fnName paramName
    , context = WhileCheckingDecide (getActual fnName) None
    }

-- | The error for an input of an exported rule that holds an EVENT: the
-- exported rule, the input, and the rule that reads the input when that is a
-- rule that the exported rule calls ('reachedThroughCalls').
mkExportEventErr :: Resolved -> Resolved -> Maybe Resolved -> CheckErrorWithContext
mkExportEventErr fnName paramName readBy =
  MkCheckErrorWithContext
    { kind    = ExportEventTypeInput fnName paramName readBy
    , context = WhileCheckingDecide (getActual fnName) None
    }

-- | The same for an input that holds a DEONTIC.
mkExportDeonticErr :: Resolved -> Resolved -> Maybe Resolved -> CheckErrorWithContext
mkExportDeonticErr fnName paramName readBy =
  MkCheckErrorWithContext
    { kind    = ExportDeonticTypeInput fnName paramName readBy
    , context = WhileCheckingDecide (getActual fnName) None
    }

mkExportUnsendableErr :: Unsendable -> Resolved -> Resolved -> Maybe Resolved -> CheckErrorWithContext
mkExportUnsendableErr = \case
  HoldsEvent   -> mkExportEventErr
  HoldsDeontic -> mkExportDeonticErr

-- | A builtin type that has no JSON form, and that a value of some type holds.
data Unsendable
  = HoldsEvent
  | HoldsDeontic

-- | Does a value of this type contain an EVENT or a DEONTIC, and which of them
-- does the walk meet first? Both are builtin types. The answer is the builtin
-- type itself, a type that holds one anywhere: as a type argument
-- (@LIST OF EVENT …@, @MAYBE (DEONTIC …)@), behind a synonym, or in a field of a
-- declared record or of a constructor of a declared sum type — also when the
-- synonym or the record is declared in an imported module, because it is read
-- from the checker's 'EntityInfo' and not from this module's declarations.
-- @PROVISION@, the older spelling of @DEONTIC@, names the same type.
--
-- The walk goes in this order, and an input that holds both an EVENT and a
-- DEONTIC is refused for the first of them that it reaches: the type arguments
-- of a type, then what its synonym stands for, then the fields of the record, or
-- of the constructors of the sum type, that it names. The fields of a record
-- are looked into in the order they are written, and so are the constructors
-- of a sum type, the fields of each constructor before the next constructor.
-- Neither builtin type is looked into any further: what its own type arguments
-- are does not matter once it has been found.
--
-- A function type is not looked into, whether it is the input's own type, a
-- type argument, or what a synonym stands for. Whether the input is refused as
-- a function type is a separate check, and it reads only the types that are
-- written and the synonyms of this module: a function type that sits in a field
-- of a record, or behind a synonym of an imported module, is neither refused as
-- a function type nor looked into here.
--
-- The 'EntityInfo' records which type a constructor builds but not the
-- converse, so the fields of every type are gathered by one pass over the
-- constructors, shared by all the calls of the returned predicate.
--
-- Which types lead to an EVENT or a DEONTIC is found once too, and shared by all
-- the calls ('leadsToUnsendable'): a type leads to one when what its synonym
-- stands for, or the type of one of its fields, names an EVENT, a DEONTIC, or
-- another type that leads to one, where the walk would meet that name. The walk
-- does not look into a type that leads to neither, since it would find nothing
-- there, so the time a call takes does not grow with the fields of such a type.
-- That matters because the check calls the predicate once for each read of an
-- ASSUME ('inferredInputs'): the reads of an ASSUME whose record holds neither
-- builtin type do not each walk the fields of the record. Whether a type leads
-- to one does not depend on the path by which the walk got to it, so skipping
-- such a type changes no answer and not the order in which the rest is met.
--
-- A type that leads to one is looked into once per call, however many fields
-- lead to it: the set of types already looked into is kept for the whole walk
-- and not for one path of it. A type that is met again is either finished, and
-- then it held neither builtin type or the walk would have ended there, or it is
-- still being looked into higher up, and whatever it holds is found there.
-- Without that, a chain of records that each have two fields of the next one,
-- and that lead to an EVENT only through a record that is still being looked
-- into, is walked once per path, which takes twice as long for every record
-- added.
carriedUnsendable :: EntityInfo -> Type' Resolved -> Maybe Unsendable
carriedUnsendable ei = \ty -> evalState (go ty) Set.empty
 where
  -- The fields of each type, those of its constructors in the order of the
  -- entity table. The fields of each constructor are put in front of those of
  -- the constructors before it, and the list is put back in order once, at the
  -- end. Putting them behind those of the constructors before it would copy
  -- what is there once for every constructor, which takes a time that grows
  -- with the square of the constructors of a type.
  fieldsByType :: Map.Map Unique [Type' Resolved]
  fieldsByType =
    Map.map (concat . reverse) $ Map.fromListWith (<>)
      [ (getUnique builtType, [fieldTypes conType])
      | (_, KnownTerm conType Constructor) <- Map.elems ei
      , Just builtType <- [resultTypeName conType]
      ]

  resultTypeName = \case
    Forall _ _ inner -> resultTypeName inner
    Fun _ _ result   -> resultTypeName result
    TyApp _ name _   -> Just name
    _                -> Nothing

  fieldTypes = \case
    Forall _ _ inner -> fieldTypes inner
    Fun _ onts _     -> map optionallyNamedTypeType onts
    _                -> []

  -- The types that lead to an EVENT or a DEONTIC: the two builtin types, and
  -- every type whose synonym or fields name one that does, found backwards
  -- from the two builtin types.
  leadsToUnsendable :: Set.Set Unique
  leadsToUnsendable = close Set.empty [eventUnique, contractUnique]
   where
    close found [] = found
    close found (u : us)
      | u `Set.member` found = close found us
      | otherwise = close (Set.insert u found) (Map.findWithDefault [] u namedBy ++ us)

  -- For each type, the types whose synonym or fields name it, where the walk
  -- would meet the name.
  namedBy :: Map.Map Unique [Unique]
  namedBy =
    Map.fromListWith (<>)
      [ (named, [owner])
      | (owner, tys) <- Map.toList (Map.unionWith (<>) synonymBodies fieldsByType)
      , ty <- tys
      , named <- typeNamesMet ty
      ]

  synonymBodies :: Map.Map Unique [Type' Resolved]
  synonymBodies =
    Map.fromList [ (u, [body]) | (u, (_, KnownType _ _ (Just body))) <- Map.toList ei ]

  -- The state is the set of types already looked into.
  go :: Type' Resolved -> State (Set.Set Unique) (Maybe Unsendable)
  go = \case
    TyApp _ name args
      | u == eventUnique    -> pure (Just HoldsEvent)
      | u == contractUnique -> pure (Just HoldsDeontic)
      | otherwise -> do
          inArgs <- firstHit go args
          seen <- get
          case inArgs of
            Just hit -> pure (Just hit)
            Nothing
              | not (u `Set.member` leadsToUnsendable) -> pure Nothing
              | u `Set.member` seen -> pure Nothing
              | otherwise -> do
                  put (Set.insert u seen)
                  behindSynonym <- case Map.lookup u ei of
                    Just (_, KnownType _ _ (Just body)) -> go body
                    _                                   -> pure Nothing
                  case behindSynonym of
                    Just hit -> pure (Just hit)
                    Nothing  -> firstHit go (Map.findWithDefault [] u fieldsByType)
      where
        u = getUnique name
    Forall _ _ inner -> go inner
    _                -> pure Nothing

  -- Stops at the first hit: the rest of the list is not looked into.
  firstHit :: (a -> State (Set.Set Unique) (Maybe b)) -> [a] -> State (Set.Set Unique) (Maybe b)
  firstHit _ []       = pure Nothing
  firstHit f (x : xs) = f x >>= maybe (firstHit f xs) (pure . Just)

-- | The names that 'carriedUnsendable' meets in a type, without looking behind
-- a synonym or into the fields of a record: the type that it applies and the
-- names in its type arguments, and those of the body of a forall. A function
-- type is not looked into. A type variable is one of these names, and these
-- are all the places where 'carriedUnsendable' meets one.
typeNamesMet :: Type' Resolved -> [Unique]
typeNamesMet = \case
  TyApp _ name args -> getUnique name : concatMap typeNamesMet args
  Forall _ _ inner  -> typeNamesMet inner
  _                 -> []
