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
  enrichParamTypes,
  buildTypeDescMap,
  assumesFromModule,
  assumesReadBy,
  collectReferencedUniques,
  decideBodiesFromModule,
  transitiveReferencedUniques,
  transitiveReferencedUniquesWith,
  AssumeRewrite (..),
  rewriteModuleAssumes,
  extractAssumeParamTypes,
  extractAssumeParamsWithDefaults,
  extractAssumeParamResolveds,
  extractImplicitAssumeParams,
  hasTypeInferenceVars,
  validateExportInputs,
  isExportedDecide,
  isNonexhaustiveDecide,
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
import qualified Data.Set as Set
import L4.Annotation (getAnno)
import L4.Syntax
import L4.Names (filterGivenSigTo, getName, isSectionBinderElaboration, sectionGivenNames)
import L4.TypeCheck.Environment (maybeUnique)
import L4.TypeCheck.Types (CheckErrorWithContext(..), CheckError(..), CheckEntity(..), CheckErrorContext(..), EntityInfo)
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
  , paramDefault :: !(Maybe (Expr Resolved)) -- ^ TYPICALLY default value, if declared
  }
  deriving stock (Eq, Show, Generic)
#if defined(SERIALISE_ENABLED)
  deriving anyclass (Serialise)
#endif

data DescFlags = DescFlags
  { isDefault :: !Bool
  , isExport :: !Bool
  , isNonexhaustive :: !Bool
  -- ^ @\@nonexhaustive@: the author declares this definition deliberately partial
  -- (not defined for all inputs; evaluation fails outside its domain), which
  -- silences the non-exhaustive-CONSIDER warning for its body. Redundancy
  -- warnings stay active.
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
      , isNonexhaustive = False
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
          "nonexhaustive" ->
            consumeKeywords restStripped flagsAcc{isNonexhaustive = True}
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
  collectSection tdm assumes' (MkSection _ _ _ _ decls) =
    decls >>= collectDecl tdm assumes'

  collectDecl tdm assumes' = \ case
    Decide _ dec -> maybeToList (buildExportedFunction mod' tdm assumes' dec)
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

-- | Fill in missing parameter types using type-checker entity info — the
-- parameter-side sibling of 'enrichReturnTypes'. A bare-head DECIDE
-- (@DECIDE factorial x IS …@ with no GIVEN) carries no annotated type for
-- its params, but the typechecker still infers one; we look up the
-- function's inferred 'Fun' type and pair its argument types with the
-- params positionally. Only the leading GIVEN\/head params are paired —
-- ASSUME-derived params (appended after them by 'buildExportedFunction')
-- carry their own type signature and the argument list has run out by the
-- time the zip reaches them. Params that already have a type are never
-- overwritten.
enrichParamTypes :: EntityInfo -> [ExportedFunction] -> [ExportedFunction]
enrichParamTypes entInfo = map enrich
 where
  enrich ef
    | all (isJust . (.paramType)) ef.exportParams = ef
    | otherwise =
        let MkDecide _ _ (MkAppForm _ name _ _) _ = ef.exportDecide
        in ef { exportParams = zipFill ef.exportParams (inferArgTypes name) }

  inferArgTypes :: Resolved -> [Type' Resolved]
  inferArgTypes name =
    case Map.lookup (getUnique name) entInfo of
      Just (_, KnownTerm (Fun _ args _) _) ->
        [ty | MkOptionallyNamedType _ _ ty <- args]
      _ -> []

  zipFill ps tys = zipWith fill ps (map Just tys ++ repeat Nothing)

  fill p mty
    | isJust p.paramType = p
    -- An inference variable means the typechecker never pinned the type
    -- down; @{"type":"object"}@ is wrong for a scalar, but an InfVar-derived
    -- schema entry would be a differently-shaped lie. Leave it untyped.
    | Just ty <- mty, not (hasInfVar ty) =
        p { paramType = Just ty
          , paramRequired = not (isMaybeType (Just ty))
          }
    | otherwise = p

  hasInfVar :: Type' Resolved -> Bool
  hasInfVar = \ case
    InfVar {} -> True
    TyApp _ _ tys -> any hasInfVar tys
    Fun _ args ret -> any hasInfVar [ty | MkOptionallyNamedType _ _ ty <- args] || hasInfVar ret
    Forall _ _ ty -> hasInfVar ty
    Type {} -> False

buildExportedFunction
  :: Module Resolved
  -> TypeDescMap
  -> Map.Map Unique (Assume Resolved)
  -> Decide Resolved
  -> Maybe ExportedFunction
buildExportedFunction mod' typeDescMap assumes decide@(MkDecide _ tySig appForm _) = do
  desc <- getAnno decide ^. annDesc
  let parsed = parseDescText (getDesc desc)
  guard (parsed.flags.isExport)
  let givenParams = extractParams typeDescMap tySig
      assumedParams = extractAssumedDependencies mod' typeDescMap assumes decide
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
  toParam (MkOptionallyTypedName ann resolved mType mTypically) =
    let paramDesc = fmap getDesc (ann ^. annDesc)
        fallbackDesc = mType >>= getTypeDesc typeDescMap
    in ExportedParam
      { paramName = resolvedToText resolved
      , paramType = mType
      , paramDescription = paramDesc <|> fallbackDesc
      , paramRequired = not (isMaybeType mType)
      , paramDefault = mTypically
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
  collectSection (MkSection _ _ _ _ decls) =
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

  collectSection (MkSection _ _ _ _ decls) =
    decls >>= collectDecl

  collectDecl = \case
    Assume _ assume@(MkAssume _ _ (MkAppForm _ name _ _) mType _mTypically) ->
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
  goSection (MkSection _ _ _ _ decls) =
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

-- | Collect the 'Unique' of every identifier the expression references
-- /directly/ — as a plain variable (@App _ ref []@), a function applied to
-- positional arguments (@App _ ref [arg, ...]@) or to named arguments
-- ('AppNamed'), or the field head of a projection (a computed @MEANS@
-- record field desugars to a top-level selector DECIDE, which must be
-- walked like any other callee). WHERE-locals and lambdas are part of the
-- body expression, so their references are collected too.
--
-- This is one body deep: it does not follow references into the bodies of
-- the definitions they name. For the read-set of an export — what an
-- evaluation of it will actually demand — use 'transitiveReferencedUniques'.
--
-- Upstream callers intersect this set with a pre-filtered map (e.g.
-- 'assumesFromModule' drops function-typed ASSUMEs), so semantic
-- specialization happens at the filter step rather than in the collector.
collectReferencedUniques :: Expr Resolved -> Set.Set Unique
collectReferencedUniques =
  foldMapOf (cosmosOf (gplate @(Expr Resolved))) $ \case
    App _ r _        -> Set.singleton (getUnique r)
    AppNamed _ r _ _ -> Set.singleton (getUnique r)
    Proj _ _ f       -> Set.singleton (getUnique f)
    _ -> Set.empty

-- | The body of every module-level DECIDE (in any section), keyed by the
-- 'Unique' of the name it defines. This is the call graph's edge table:
-- 'transitiveReferencedUniques' follows a reference into its body.
decideBodiesFromModule :: Module Resolved -> Map.Map Unique (Expr Resolved)
decideBodiesFromModule (MkModule _ _ section) =
  Map.fromList (goSection section)
 where
  goSection (MkSection _ _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Decide _ (MkDecide _ _ (MkAppForm _ name _ _) body) -> [(getUnique name, body)]
    Section _ sub -> goSection sub
    _ -> []

-- | The transitive read-set of an expression: every 'Unique' it references
-- directly ('collectReferencedUniques'), plus everything referenced by the
-- body of any module-level definition reachable from it through the call
-- graph — so an @\@export@ whose helper reads an ASSUME is charged with
-- that ASSUME. Cycle-safe: recursive and mutually recursive definitions
-- are visited once.
--
-- Callers that want the ASSUMEs an export depends on should go through
-- 'assumesReadBy'; this is the one place that closure is computed, so the
-- schema, the direct evaluator, the batch wrapper and the WASM ABI all
-- agree on what a request must supply.
transitiveReferencedUniques :: Module Resolved -> Expr Resolved -> Set.Set Unique
transitiveReferencedUniques mod' =
  transitiveReferencedUniquesWith (decideBodiesFromModule mod')

-- | 'transitiveReferencedUniques' against an already-built edge table.
--
-- Same closure, same answer; the only difference is that the caller keeps the
-- table. 'L4.Discharge' asks for the read-set of every definition in a module
-- at once, and rebuilding 'decideBodiesFromModule' per definition would make
-- that quadratic in the size of the module.
transitiveReferencedUniquesWith
  :: Map.Map Unique (Expr Resolved) -> Expr Resolved -> Set.Set Unique
transitiveReferencedUniquesWith defs =
  go Set.empty . Set.toList . collectReferencedUniques
 where
  go seen [] = seen
  go seen (u : us)
    | Set.member u seen = go seen us
    | otherwise =
        let next = maybe [] (Set.toList . collectReferencedUniques) (Map.lookup u defs)
        in go (Set.insert u seen) (next <> us)

-- | The ASSUMEs (drawn from a pre-filtered map such as 'assumesFromModule')
-- that a DECIDE reads — directly, or through any definition it reaches.
-- Returned in the map's key order (declaration order of the 'Unique's),
-- which is the order every consumer presents them in.
assumesReadBy
  :: Module Resolved
  -> Map.Map Unique (Assume Resolved)
  -> Decide Resolved
  -> [Assume Resolved]
assumesReadBy mod' assumes (MkDecide _ _ _ body) =
  let referencedUniques = transitiveReferencedUniques mod' body
  in [ assume
     | (uniq, assume) <- Map.toList assumes
     , Set.member uniq referencedUniques
     ]

-- | What 'rewriteModuleAssumes' should do with one module-level ASSUME.
data AssumeRewrite
  = KeepAssume
  | DropAssume
  | ReplaceAssume (TopDecl Resolved)

-- | Rewrite every module-level ASSUME (in any section). Used to bind
-- supplied values for ASSUMEs at evaluation time: the evaluator keeps an
-- ASSUME as 'ValAssumed' at its own address in the module environment,
-- which every closure in the module captures, so a @LET@ around a call
-- cannot reach a helper that reads it — but a definition installed at the
-- ASSUME's own address (same 'Resolved', hence same 'Unique') can.
rewriteModuleAssumes
  :: (Assume Resolved -> AssumeRewrite)
  -> Module Resolved
  -> Module Resolved
rewriteModuleAssumes rewrite (MkModule ann uri section) =
  MkModule ann uri (goSection section)
 where
  -- Hold a section's own GIVEN and its elaborations in step (see the invariant
  -- on 'L4.Desugar.desugarSectionGivens'): a parameter whose elaboration was
  -- dropped or replaced is no longer a section binder, and leaving it on the
  -- heading would make 'L4.Print.prettyLayout' re-introduce a binder the caller
  -- has just bound -- which is exactly what @l4 batch@ does, so the wrapper's
  -- definition would then collide with it.
  goSection (MkSection sann name aka mgiven decls) =
    let binders = sectionGivenNames mgiven
        decls'  = mapMaybe goDecl decls
        kept    = [ rawName (getName r)
                  | d@(Assume _ (MkAssume _ _ (MkAppForm _ r [] _) _ _)) <- decls'
                  , isSectionBinderElaboration binders d
                  ]
    in MkSection sann name aka (filterGivenSigTo kept mgiven) decls'
  goDecl = \case
    decl@(Assume _ assume) -> case rewrite assume of
      KeepAssume          -> Just decl
      DropAssume          -> Nothing
      ReplaceAssume decl' -> Just decl'
    Section sann sub -> Just (Section sann (goSection sub))
    other -> Just other

-- | Extract ASSUME declarations that are referenced by a DECIDE body, or by
-- anything it reaches ('assumesReadBy').
-- Returns ExportedParams for each ASSUME that the function depends on.
extractAssumedDependencies
  :: Module Resolved
  -> TypeDescMap
  -> Map.Map Unique (Assume Resolved)
  -> Decide Resolved
  -> [ExportedParam]
extractAssumedDependencies mod' typeDescMap assumes decide =
  map (assumeToParam typeDescMap) (assumesReadBy mod' assumes decide)

-- | Convert an ASSUME declaration to an ExportedParam
assumeToParam :: TypeDescMap -> Assume Resolved -> ExportedParam
assumeToParam typeDescMap (MkAssume ann _ (MkAppForm _ name _ _) mType mTypically) =
  let
    paramDesc = fmap getDesc (ann ^. annDesc)
    fallbackDesc = mType >>= getTypeDesc typeDescMap
  in
    ExportedParam
      { paramName = resolvedToText name
      , paramType = mType
      , paramDescription = paramDesc <|> fallbackDesc
      , paramRequired = not (isMaybeType mType)
      , paramDefault = mTypically
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

-- | Like 'extractAssumeParamTypes' but also returns the TYPICALLY default
-- value (if any) declared on each ASSUME, and the ASSUME's own @\@desc@
-- text (if any). Used by the function schema to expose defaults and
-- descriptions to API consumers.
extractAssumeParamsWithDefaults
  :: Module Resolved
  -> Decide Resolved
  -> [(Text, Type' Resolved, Maybe (Expr Resolved), Maybe Text)]
extractAssumeParamsWithDefaults mod' decide =
  mapMaybe assumeInfo (assumesReadBy mod' (assumesFromModule mod') decide)
 where
  assumeInfo :: Assume Resolved -> Maybe (Text, Type' Resolved, Maybe (Expr Resolved), Maybe Text)
  assumeInfo (MkAssume ann _ (MkAppForm _ name _ _) (Just ty) mTypically) =
    Just (resolvedToText name, ty, mTypically, getDesc <$> ann ^. annDesc)
  assumeInfo _ = Nothing

-- | Like 'extractAssumeParamTypes' but returns the 'Resolved' name instead of
-- its textual form. Consumers that need to bind the ASSUME in a local scope
-- (e.g. MLIR lowering) need the Resolved so subsequent in-scope references
-- resolve to the local binding.
extractAssumeParamResolveds
  :: Module Resolved
  -> Decide Resolved
  -> [(Resolved, Type' Resolved)]
extractAssumeParamResolveds mod' decide =
  mapMaybe assumeToResolvedInfo (assumesReadBy mod' (assumesFromModule mod') decide)
 where
  assumeToResolvedInfo :: Assume Resolved -> Maybe (Resolved, Type' Resolved)
  assumeToResolvedInfo (MkAssume _ _ (MkAppForm _ name _ _) (Just ty) _mTypically) =
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

-- | Validate that no @export-decorated DECIDE has a function-typed input —
-- either a GIVEN parameter, or a module-level ASSUME the body calls.
-- Function-typed inputs can't be evaluated end-to-end: GIVENs can't be
-- passed over JSON, and function-typed ASSUMEs stay 'ValAssumed' at
-- runtime, causing a stuck "assumed term" error when the body invokes them.
validateExportInputs :: Module Resolved -> [CheckErrorWithContext]
validateExportInputs mod' =
  let synonyms = collectTypeSynonyms mod'
      assumes  = allAssumesFromModule mod'
  in concatMap (checkOneExport mod' synonyms assumes) (collectExportedDecides mod')

-- | Collect every DECIDE whose description carries the @export flag.
collectExportedDecides :: Module Resolved -> [Decide Resolved]
collectExportedDecides (MkModule _ _ section) = goSection section
 where
  goSection (MkSection _ _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Decide _ d | isExportedDecide d -> [d]
    Section _ sub -> goSection sub
    _ -> []

isExportedDecide :: Decide Resolved -> Bool
isExportedDecide decide =
  case getAnno decide ^. annDesc of
    Just desc -> (parseDescText (getDesc desc)).flags.isExport
    Nothing   -> False

-- | Was this definition marked @\@nonexhaustive@ by its author? See 'DescFlags'.
-- Polymorphic in the pass so the type checker can consult it before
-- resolution.
isNonexhaustiveDecide :: Decide n -> Bool
isNonexhaustiveDecide decide =
  case getAnno decide ^. annDesc of
    Just desc -> (parseDescText (getDesc desc)).flags.isNonexhaustive
    Nothing   -> False

-- | Like 'assumesFromModule' but WITHOUT the function-type filter —
-- so the validator sees every ASSUME and can flag function-typed ones.
allAssumesFromModule :: Module Resolved -> Map.Map Unique (Assume Resolved)
allAssumesFromModule (MkModule _ _ section) =
  Map.fromList (collectSection section)
 where
  collectSection (MkSection _ _ _ _ decls) = decls >>= collectDecl
  collectDecl = \case
    Assume _ assume@(MkAssume _ _ (MkAppForm _ name _ _) _ _) ->
      [(getUnique name, assume)]
    Section _ sub -> collectSection sub
    _ -> []

checkOneExport
  :: Module Resolved
  -> Map.Map Unique (Type' Resolved)
  -> Map.Map Unique (Assume Resolved)
  -> Decide Resolved
  -> [CheckErrorWithContext]
checkOneExport mod' synonyms assumes decide@(MkDecide _ tySig (MkAppForm _ fnName _ _) _) =
  checkGivenFunctionInputs synonyms fnName tySig
  ++ checkAssumeFunctionInputs synonyms readAssumes fnName
  ++ checkAssumeNameClash readAssumes fnName tySig
 where
  readAssumes = assumesReadBy mod' assumes decide

checkGivenFunctionInputs
  :: Map.Map Unique (Type' Resolved)
  -> Resolved
  -> TypeSig Resolved
  -> [CheckErrorWithContext]
checkGivenFunctionInputs synonyms fnName (MkTypeSig _ (MkGivenSig _ names) _) =
  [ mkExportFunErr fnName paramName
  | MkOptionallyTypedName _ paramName (Just ty) _ <- names
  , isFunctionTypeExpanded synonyms ty
  ]

checkAssumeFunctionInputs
  :: Map.Map Unique (Type' Resolved)
  -> [Assume Resolved]
  -> Resolved
  -> [CheckErrorWithContext]
checkAssumeFunctionInputs synonyms readAssumes fnName =
  [ mkExportFunErr fnName paramName
  | MkAssume _ _ (MkAppForm _ paramName _ _) (Just ty) _mTypically <- readAssumes
  , isFunctionTypeExpanded synonyms ty
  ]

-- | A GIVEN parameter and a read ASSUME that share a name would collapse
-- into one input field of the export's schema (the GIVEN shadows the
-- ASSUME inside the export's own body, but a helper it reaches still reads
-- the module-level ASSUME), so a request could never supply both. Report
-- it rather than let the schema silently merge them.
checkAssumeNameClash
  :: [Assume Resolved]
  -> Resolved
  -> TypeSig Resolved
  -> [CheckErrorWithContext]
checkAssumeNameClash readAssumes fnName (MkTypeSig _ (MkGivenSig _ names) _) =
  [ MkCheckErrorWithContext
      { kind    = ExportAssumeNameClash fnName paramName
      , context = WhileCheckingDecide (getActual fnName) None
      }
  | MkOptionallyTypedName _ paramName _ _ <- names
  , resolvedToText paramName `Set.member` assumeNames
  ]
 where
  assumeNames = Set.fromList
    [ resolvedToText name | MkAssume _ _ (MkAppForm _ name _ _) _ _ <- readAssumes ]

mkExportFunErr :: Resolved -> Resolved -> CheckErrorWithContext
mkExportFunErr fnName paramName =
  MkCheckErrorWithContext
    { kind    = ExportFunctionTypeInput fnName paramName
    , context = WhileCheckingDecide (getActual fnName) None
    }
