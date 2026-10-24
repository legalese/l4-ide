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
import L4.TypeCheck.Environment (contractUnique, eventUnique, maybeUnique)
import L4.TypeCheck.Types (CheckErrorWithContext(..), CheckError(..), CheckEntity(..), CheckErrorContext(..), EntityInfo, Substitution, optionallyNamedTypeType, substituteInfVars)
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
collectReferencedUniques = Set.fromList . map getUnique . collectReferencedResolveds

-- | The identifier of every reference that 'collectReferencedUniques' counts,
-- as the 'Resolved' that the expression holds, once for each time it is read.
collectReferencedResolveds :: Expr Resolved -> [Resolved]
collectReferencedResolveds =
  foldMapOf (cosmosOf (gplate @(Expr Resolved))) $ \case
    App _ ref@(Ref _ _ _) _ -> [ref]
    _ -> []

-- | Every read of an identifier that is given no arguments (@App ann ref []@),
-- with the type that the checker recorded on the expression that reads it, in
-- the order the reads come. That type is the one the read has, which for a
-- polymorphic identifier is not the declared one: each read of the ASSUME in
-- @GIVEN a IS A TYPE GIVETH AN a ASSUME x@ is given a type of its own. It can
-- still hold inference variables, until the substitution that the check ended
-- with is applied to it, which the caller does. A read that is given arguments
-- has the type of the call, not of the identifier, and is not in the answer, nor
-- is a read that has no recorded type.
collectReadTypes :: Expr Resolved -> [(Resolved, Type' Resolved)]
collectReadTypes =
  foldMapOf (cosmosOf (gplate @(Expr Resolved))) $ \case
    App ann ref@(Ref _ _ _) [] | Just (TypeInfo ty _) <- ann ^. annInfo -> [(ref, ty)]
    _ -> []

-- | The ASSUMEs that a @WHERE@ in the expression declares, wherever in the
-- expression the @WHERE@ stands, also inside a local definition. The parser
-- accepts an ASSUME among local declarations under @WHERE@ and nowhere else: a
-- @LET@ holds definitions only. The checker's table of what a module declares
-- does not hold these, since they are in scope for the expression alone.
collectLocalAssumes :: Expr Resolved -> [Assume Resolved]
collectLocalAssumes =
  foldMapOf (cosmosOf (gplate @(Expr Resolved))) $ \case
    Where _ _ decls -> [ assume | LocalAssume _ assume <- decls ]
    _ -> []

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
--   DEONTIC or an EVENT ('collectReadTypes'). A call of an ASSUME that is given
--   arguments has the type of its result and is not looked at;
--
-- * an ASSUME that the body declares itself, in a @WHERE@, and reads: the
--   'EntityInfo' does not hold it, so it is found in the body
--   ('collectLocalAssumes') and its declared type is the one that the checker
--   recorded on the declaration. The reads of it are looked at as for any other.
--
-- The walk covers the rule's own inputs and the ASSUMEs that its own body
-- reads. It does not look inside a rule that the exported rule calls.
--
-- One input is refused once, however many such types it holds: for the EVENT or
-- the DEONTIC that the walk meets first ('carriedUnsendable').
validateExportInputs :: Substitution -> EntityInfo -> Module Resolved -> [CheckErrorWithContext]
validateExportInputs subst ei mod' =
  let synonyms = collectTypeSynonyms mod'
      assumes  = allAssumesFromModule mod'
      carried  = carriedUnsendable ei
      -- one pass per kind of input a request cannot carry, each with the inputs it looks at
      functionTypes, unsendables :: Decide Resolved -> [CheckErrorWithContext]
      functionTypes decide =
        checkOneExport
          (\ty -> if isFunctionTypeExpanded synonyms ty then Just mkExportFunErr else Nothing)
          decide
          (writtenInputs assumes decide)
      unsendables decide =
        checkOneExport
          (\ty -> mkExportUnsendableErr <$> carried ty)
          decide
          (inferredInputs subst ei decide)
  in [ err
     | decide <- collectExportedDecides mod'
     , pass <- [functionTypes, unsendables]
     , err <- pass decide
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
writtenInputs
  :: Map.Map Unique (Assume Resolved)
  -> Decide Resolved
  -> [ExportInput]
writtenInputs assumes (MkDecide _ (MkTypeSig _ (MkGivenSig _ names) _) _ body) =
  let referencedUniques = collectReferencedUniques body
  in [ (paramName, [ty])
     | MkOptionallyTypedName _ paramName (Just ty) <- names
     ]
     ++
     [ (paramName, [ty])
     | (uniq, MkAssume _ _ (MkAppForm _ paramName _ _) (Just ty)) <- Map.toList assumes
     , Set.member uniq referencedUniques
     ]

-- | Every input that the checker knows a type for: the GIVENs, with the
-- inferred type of one that has no written type, then every ASSUME that the
-- body reads, whichever module declares it, or the body itself in a WHERE. An
-- ASSUME is looked at for the type it is declared with, and then for the type
-- that the checker recorded at each read of it in the body
-- ('collectReadTypes'): the two differ for a polymorphic ASSUME, which is
-- declared with a type variable and read at a type of its own.
inferredInputs
  :: Substitution
  -> EntityInfo
  -> Decide Resolved
  -> [ExportInput]
inferredInputs subst ei (MkDecide _ (MkTypeSig _ (MkGivenSig _ names) _) (MkAppForm _ fnName _ _) body) =
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
      | ref <- collectReferencedResolveds body
      , Just (_, KnownTerm ty AssumedTerm) <- [Map.lookup (getUnique ref) ei]
      ]
      ++
      [ (getUnique name, (name, [ ty | Just (TypeInfo ty _) <- [getAnno assume ^. annInfo] ]))
      | assume@(MkAssume _ _ (MkAppForm _ name _ _) _) <- collectLocalAssumes body
      , Set.member (getUnique name) readUniques
      ]

  readUniques = collectReferencedUniques body

  -- the types recorded at the reads of each identifier, in the order read
  readAs :: Map.Map Unique [Type' Resolved]
  readAs =
    Map.fromListWith (flip (<>))
      [ (getUnique ref, [ty]) | (ref, ty) <- collectReadTypes body ]

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

mkExportEventErr :: Resolved -> Resolved -> CheckErrorWithContext
mkExportEventErr fnName paramName =
  MkCheckErrorWithContext
    { kind    = ExportEventTypeInput fnName paramName
    , context = WhileCheckingDecide (getActual fnName) None
    }

mkExportDeonticErr :: Resolved -> Resolved -> CheckErrorWithContext
mkExportDeonticErr fnName paramName =
  MkCheckErrorWithContext
    { kind    = ExportDeonticTypeInput fnName paramName
    , context = WhileCheckingDecide (getActual fnName) None
    }

mkExportUnsendableErr :: Unsendable -> Resolved -> Resolved -> CheckErrorWithContext
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
-- Each type is looked into once per call, however many fields lead to it: the
-- set of types already looked into is kept for the whole walk and not for one
-- path of it. A type that is met again is either finished, and then it held
-- neither builtin type or the walk would have ended there, or it is still being
-- looked into higher up, and whatever it holds is found there. Without that, a
-- chain of records that each have two fields of the next one is walked once per
-- path, which takes twice as long for every record added.
carriedUnsendable :: EntityInfo -> Type' Resolved -> Maybe Unsendable
carriedUnsendable ei = \ty -> evalState (go ty) Set.empty
 where
  fieldsByType :: Map.Map Unique [Type' Resolved]
  fieldsByType =
    Map.fromListWith (flip (<>))
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
