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
  checkExports,
  ExportError (..),
  ExportSite (..),
  exportErrorRange,
  exportErrorFunction,
  exportErrorSeverity,
  withoutRefused,
  prettyExportError,
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
import L4.Annotation (getAnno, rangeOf)
import L4.Parser.SrcSpan (SrcRange)
import L4.Syntax
import L4.TypeCheck.Environment (maybeUnique)
import L4.Export.Shape (ShapeEnv (..), Unsendable, jsonShape, unsendableHint, unsendableWhat)
import L4.TypeCheck.Types (CheckErrorWithContext(..), CheckError(..), CheckEntity(..), EntityInfo, Severity (..))
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
        in ef { exportReturnType = inferredReturnType entInfo name }

-- | The return type the type checker inferred for a definition.
inferredReturnType :: EntityInfo -> Resolved -> Maybe (Type' Resolved)
inferredReturnType entInfo name =
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

-- | Where in an exported rule a type that cannot cross the boundary was found.
data ExportSite
  = -- | An input: a GIVEN, or an ASSUME the body reads.
    ExportInput Resolved
  | ExportResult
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | A problem with an @\@export@, found by 'checkExports'. These are not type
-- errors: the file still type-checks, so its @#EVAL@s still run.
data ExportError
  = -- | The range of the @\@export@, the exported rule, where, and why that type
    -- has no JSON form (see "L4.Export.Shape").
    ExportUnsendable (Maybe SrcRange) Resolved ExportSite Unsendable
  | -- | A GIVEN of an exported rule with no written type: the range of the
    -- @\@export@, the rule, and the input.
    ExportUntypedGiven (Maybe SrcRange) Resolved Resolved
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

exportErrorRange :: ExportError -> Maybe SrcRange
exportErrorRange = \case
  ExportUnsendable r _ _ _ -> r
  ExportUntypedGiven r _ _ -> r

-- | The exported rule the error is about.
exportErrorFunction :: ExportError -> Resolved
exportErrorFunction = \case
  ExportUnsendable _ f _ _ -> f
  ExportUntypedGiven _ f _ -> f

-- | A missing type is a warning for now; anything else that cannot be sent is
-- an error.
exportErrorSeverity :: ExportError -> Severity
exportErrorSeverity = \case
  ExportUnsendable{} -> SError
  ExportUntypedGiven{} -> SWarn

prettyExportError :: ExportError -> [Text]
prettyExportError = \case
  ExportUnsendable _ fn site why ->
    [ quoted fn <> " is published with @export, but its " <> siteText site <> " is " <> unsendableWhat why <> ", and @export does not support that yet."
    , unsendableHint why
    ]
  ExportUntypedGiven _ fn input ->
    [ quoted fn <> " is published with @export, but its input " <> quoted input <> " has no written type."
    , "Write one in the GIVEN, so that the schema says what to send."
    ]
 where
  quoted r = "`" <> resolvedToText r <> "`"
  siteText = \case
    ExportInput n -> "input " <> quoted n
    ExportResult -> "result"

-- | Check every @\@export@ of a module against what can cross the boundary:
-- each of its inputs (a GIVEN, or an ASSUME of the module that the body reads)
-- and its result must have a JSON form ('jsonShape'). A function, an EVENT, a
-- DEONTIC (a contract rule), a type variable and a type with no shape yet do
-- not, so an @\@export@ of a rule with one is refused, at the @\@export@. A
-- GIVEN with no written type is a warning.
--
-- This is its own pass, not a part of type checking: the errors of a type check
-- stop the file from evaluating, and a refused @\@export@ is no reason to stop
-- evaluating the contract rules in the same file. The result of a definition
-- with no GIVETH comes from the entity info of the 'ShapeEnv', which must have
-- the final substitution applied.
checkExports :: ShapeEnv -> Module Resolved -> [ExportError]
checkExports env mod' =
  concatMap (checkOneExport env assumes) (collectExportedDecides mod')
 where
  assumes = allAssumesFromModule mod'

-- | The exported rules that 'checkExports' does not refuse (a warning does not
-- refuse): the ones that can be published.
withoutRefused :: [ExportError] -> [ExportedFunction] -> [ExportedFunction]
withoutRefused errs = filter \ef ->
  let MkDecide _ _ (MkAppForm _ name _ _) _ = ef.exportDecide
  in getUnique name `Set.notMember` refused
 where
  refused = Set.fromList [getUnique (exportErrorFunction e) | e <- errs, exportErrorSeverity e == SError]

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

-- | Like 'assumesFromModule' but WITHOUT the function-type filter, so that
-- 'checkExports' sees every ASSUME.
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
  :: ShapeEnv
  -> Map.Map Unique (Assume Resolved)
  -> Decide Resolved
  -> [ExportError]
checkOneExport env assumes decide@(MkDecide _ tySig@(MkTypeSig _ (MkGivenSig _ names) _) (MkAppForm _ fnName _ _) body) =
  concat
    [ case mty of
        Nothing -> [ExportUntypedGiven exportAt fnName paramName]
        Just ty -> unsendable (ExportInput paramName) ty
    | MkOptionallyTypedName _ paramName mty <- names
    ]
  ++ concat
    [ unsendable (ExportInput paramName) ty
    | (uniq, MkAssume _ _ (MkAppForm _ paramName _ _) (Just ty)) <- Map.toList assumes
    , Set.member uniq (collectReferencedUniques body)
    ]
  ++ concat
    [ unsendable ExportResult ty
    | Just ty <- [extractReturnType tySig <|> inferredReturnType env.entities fnName]
    ]
 where
  exportAt = getAnno decide ^. annDesc >>= rangeOf
  unsendable site ty = either (\why -> [ExportUnsendable exportAt fnName site why]) (const []) (jsonShape env ty)
