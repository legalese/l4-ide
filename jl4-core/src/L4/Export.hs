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
import L4.TypeCheck.Environment (eventUnique, maybeUnique)
import L4.TypeCheck.Types (CheckErrorWithContext(..), CheckError(..), CheckEntity(..), CheckErrorContext(..), EntityInfo, optionallyNamedTypeType)
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
collectReferencedUniques =
  foldMapOf (cosmosOf (gplate @(Expr Resolved))) $ \case
    App _ (Ref _ uniq _) _ -> Set.singleton uniq
    _ -> Set.empty

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
-- an EVENT. The input is either a GIVEN parameter, or a module-level ASSUME
-- the body uses.
--
-- Function-typed inputs can't be evaluated end-to-end: GIVENs can't be
-- passed over JSON, and function-typed ASSUMEs stay 'ValAssumed' at
-- runtime, causing a stuck "assumed term" error when the body invokes them.
--
-- An EVENT has no JSON form either. The service's input decoder reads a JSON
-- object only into a declared record, and the EVENT type is builtin and has
-- no declaration, so every evaluation answers 422; the published schema is a
-- bare @object@; and @l4 batch@ decodes the row to NOTHING.
validateExportInputs :: EntityInfo -> Module Resolved -> [CheckErrorWithContext]
validateExportInputs ei mod' =
  let synonyms = collectTypeSynonyms mod'
      assumes  = allAssumesFromModule mod'
      -- one pass per kind of input a request cannot carry
      refusals =
        [ (isFunctionTypeExpanded synonyms, mkExportFunErr)
        , (typeCarriesEvent ei, mkExportEventErr)
        ]
  in [ err
     | decide <- collectExportedDecides mod'
     , (refused, mkErr) <- refusals
     , err <- checkOneExport refused mkErr assumes decide
     ]

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

checkOneExport
  :: (Type' Resolved -> Bool)
  -> (Resolved -> Resolved -> CheckErrorWithContext)
  -> Map.Map Unique (Assume Resolved)
  -> Decide Resolved
  -> [CheckErrorWithContext]
checkOneExport refused mkErr assumes decide@(MkDecide _ tySig (MkAppForm _ fnName _ _) _) =
  checkGivenInputs refused mkErr fnName tySig
  ++ checkAssumeInputs refused mkErr assumes fnName decide

checkGivenInputs
  :: (Type' Resolved -> Bool)
  -> (Resolved -> Resolved -> CheckErrorWithContext)
  -> Resolved
  -> TypeSig Resolved
  -> [CheckErrorWithContext]
checkGivenInputs refused mkErr fnName (MkTypeSig _ (MkGivenSig _ names) _) =
  [ mkErr fnName paramName
  | MkOptionallyTypedName _ paramName (Just ty) <- names
  , refused ty
  ]

checkAssumeInputs
  :: (Type' Resolved -> Bool)
  -> (Resolved -> Resolved -> CheckErrorWithContext)
  -> Map.Map Unique (Assume Resolved)
  -> Resolved
  -> Decide Resolved
  -> [CheckErrorWithContext]
checkAssumeInputs refused mkErr assumes fnName (MkDecide _ _ _ body) =
  let referencedUniques = collectReferencedUniques body
  in [ mkErr fnName paramName
     | (uniq, MkAssume _ _ (MkAppForm _ paramName _ _) (Just ty)) <- Map.toList assumes
     , Set.member uniq referencedUniques
     , refused ty
     ]

mkExportFunErr :: Resolved -> Resolved -> CheckErrorWithContext
mkExportFunErr fnName paramName =
  MkCheckErrorWithContext
    { kind    = ExportFunctionTypeInput fnName paramName
    , context = WhileCheckingDecide (getActual fnName) None
    }

mkExportEventErr :: Resolved -> Resolved -> CheckErrorWithContext
mkExportEventErr fnName paramName =
  MkCheckErrorWithContext
    { kind    = ExportEventTypeInput fnName paramName
    , context = WhileCheckingDecide (getActual fnName) None
    }

-- | Does a value of this type contain an EVENT? True for the builtin @EVENT@
-- type itself, and for a type that holds one anywhere: as a type argument
-- (@LIST OF EVENT …@, @MAYBE (EVENT …)@), behind a synonym, or in a field of a
-- declared record or of a constructor of a declared sum type — also when the
-- synonym or the record is declared in an imported module, because it is read
-- from the checker's 'EntityInfo' and not from this module's declarations.
--
-- A function type is not looked into: an input of that type is refused as a
-- function type already, and one refusal per input is enough.
--
-- The 'EntityInfo' records which type a constructor builds but not the
-- converse, so the fields of every type are gathered by one pass over the
-- constructors, shared by all the calls of the returned predicate.
--
-- Each type is looked into once per call, however many fields lead to it: the
-- set of types already looked into is kept for the whole walk and not for one
-- path of it. A type that is met again is either finished, and then it held no
-- EVENT or the walk would have ended there, or it is still being looked into
-- higher up, and whatever it holds is found there. Without that, a chain of
-- records that each have two fields of the next one is walked once per path,
-- which takes twice as long for every record added.
typeCarriesEvent :: EntityInfo -> Type' Resolved -> Bool
typeCarriesEvent ei = \ty -> evalState (go ty) Set.empty
 where
  fieldsByType :: Map.Map Unique [Type' Resolved]
  fieldsByType =
    Map.fromListWith (<>)
      [ (getUnique builtType, fieldTypes conType)
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

  -- The state is the set of types already looked into.
  go :: Type' Resolved -> State (Set.Set Unique) Bool
  go = \case
    TyApp _ name args
      | u == eventUnique -> pure True
      | otherwise -> do
          inArgs <- anyHit go args
          seen <- get
          if inArgs then pure True
          else if u `Set.member` seen then pure False
          else do
            put (Set.insert u seen)
            behindSynonym <- case Map.lookup u ei of
              Just (_, KnownType _ _ (Just body)) -> go body
              _                                   -> pure False
            if behindSynonym then pure True
            else anyHit go (Map.findWithDefault [] u fieldsByType)
      where
        u = getUnique name
    Forall _ _ inner -> go inner
    _                -> pure False

  -- Stops at the first hit: the rest of the list is not looked into.
  anyHit :: (a -> State (Set.Set Unique) Bool) -> [a] -> State (Set.Set Unique) Bool
  anyHit _ []       = pure False
  anyHit f (x : xs) = f x >>= \hit -> if hit then pure True else anyHit f xs
