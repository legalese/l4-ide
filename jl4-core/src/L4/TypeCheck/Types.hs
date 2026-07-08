-- | Types needed during the scope and type checking phase.
{-# LANGUAGE CPP #-}
{-# LANGUAGE UndecidableInstances #-}
module L4.TypeCheck.Types where

import Base
#if defined(SERIALISE_ENABLED)
import Codec.Serialise (Serialise)
#endif
import qualified Optics
import L4.Annotation (HasSrcRange(..), HasAnno(..), AnnoExtra, AnnoToken, emptyAnno)
import L4.Lexer (PosToken)
import L4.Parser.SrcSpan (SrcRange(..), SrcPos)
import L4.Syntax
import L4.TypeCheck.With
import qualified L4.Utils.IntervalMap as IV
import L4.Mixfix (MixfixInfo(..))
import qualified Base.Set as Set

import Control.Applicative
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Generics.SOP as SOP
import Optics.Core (gplate, traverseOf, (%), (?~))
import Control.Exception (throw, Exception)

type Environment  = Map RawName [Unique]
type EntityInfo   = Map Unique (Name, CheckEntity)
type Substitution = Map Int (Type' Resolved)
type RangeMap     = IV.IntervalMap SrcPos
type InfoMap      = RangeMap Info
type ScopeMap     = RangeMap (Environment, EntityInfo)
type NlgMap       = RangeMap Nlg
type DescMap      = RangeMap Text

-- | Note that 'KnownType' does not imply this is a new generative type on its own,
-- because it includes type synonyms now. For type synonyms primarily, we also store
-- the arguments, so that we can properly substitute when instantiated.
--
data CheckEntity =
    KnownType Kind [Resolved] (Maybe (Type' Resolved))
  | KnownTerm (Type' Resolved) TermKind
  | KnownSection (Section Resolved)
  | KnownTypeVariable
  deriving stock (Eq, Generic, Show)
  deriving anyclass (NFData)

#if defined(SERIALISE_ENABLED)
deriving anyclass instance Serialise CheckEntity
#endif

data CheckState =
  MkCheckState
    { substitution :: !Substitution
    , supply       :: !Int
    , infoMap      :: !InfoMap
    , scopeMap     :: !ScopeMap
    , nlgMap       :: !NlgMap
    , descMap      :: !DescMap
    , constBodies  :: !(Map Unique (Expr Resolved))
      -- ^ Bodies of top-level nullary @DECIDE@/@MEANS@ constants, captured as
      -- they are checked. Used by the rung-3 value-level actor-agreement check
      -- to recover an action constant's actor field from its definition.
    , sectionPaths :: !(Map Unique [NonEmpty Text])
    -- ^ For each defined 'Unique', the section stack (path from the module root
    -- down to the innermost enclosing section) at the point it was registered.
    -- Absence means the binding is top-level (empty section path). Used by
    -- 'resolveTerm'' and 'resolveType' to prefer the nearest enclosing section
    -- when resolving unqualified names (lexical scoping / shadowing).
    }
  deriving stock (Generic)

data CheckErrorWithContext =
  MkCheckErrorWithContext
    { kind    :: !CheckError
    , context :: !CheckErrorContext
    }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (NFData)

data CheckError =
    OutOfScopeError Name (Type' Resolved)
  | KindError Kind [Type' Name]
  | TypeMismatch ExpectationContext (Type' Resolved) (Type' Resolved) -- expected, given
  | InconsistentNameInSignature Name (Maybe Name)
  | InconsistentNameInAppForm Name (Maybe Name)
  | NonDistinctError NonDistinctContext [[Name]]
  | AmbiguousTermError Name [(Resolved, Type' Resolved)]
  | AmbiguousOperatorError Text
  | AmbiguousTypeError Name [(Resolved, Kind)]
  | InternalAmbiguityError
  | IncorrectArgsNumberApp Resolved Int Int -- expected, given
  | IllegalApp Resolved (Type' Resolved) Int
  | IllegalAppNamed Resolved (Type' Resolved)
  | IncompleteAppNamed Resolved [OptionallyNamedType Resolved]
  | CheckInfo (Type' Resolved) (Maybe SrcRange)
  | CheckWarning CheckWarning
  | IllegalTypeInKindSignature (Type' Resolved)
  | MissingEntityInfo Resolved
  | DesugarAnnoRewritingError (Expr Name) HoleInfo
  | MixfixMatchErrorCheck Name MixfixMatchError
    -- ^ Error in mixfix pattern matching (function name, error details)
  | CyclicComputedFields Name [Name]
    -- ^ Circular dependency between computed fields (record name, cycle of field names)
  | CyclicTypeSynonyms [Name]
    -- ^ Circular dependency between type synonym declarations (cycle members)
  | SuppliedComputedField Name
    -- ^ Tried to supply a computed field in a record constructor (field name)
  | ExportFunctionTypeInput Resolved Resolved
    -- ^ An @export-decorated DECIDE has a function-typed input (GIVEN or
    -- referenced ASSUME). Arguments: exported-function name, offending
    -- parameter/assume name.
  | RegulativeActorMismatch Resolved Resolved Resolved
    -- ^ A regulative @PARTY p MUST a@ (or a @PARTY p DOES a@ event) binds a
    -- party to an action belonging to a different actor. In a value-actor
    -- @DEONTIC PartyT ActionT@ contract, an action's actor is the field of its
    -- record whose value is a constructor of @PartyT@. Arguments: the
    -- obligated/acting party, the action's own actor, the action name.
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

data CheckWarning
  = PatternMatchRedundant [Branch Resolved]
  | PatternMatchesMissing [BranchLhs Resolved]
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

-- | When rewriting the 'Anno' of a syntax node, we encountered an internal error.
-- We expected a certain number of 'AnnoHole's, e.g., in a binary operation we expect 2 'AnnoHole's,
-- but we got a different number.
--
-- This is an internal error that shouldn't occur.
data HoleInfo = HoleInfo
  { expected :: !Int
  , got :: !Int
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

data InternalCheckError =
    MissingSrcRangeForDeclaration Anno
  | MissingDeclForSrcRange Anno
  deriving stock Show
  deriving anyclass Exception

data ExpectationContext =
    ExpectAssumeSignatureContext (Maybe SrcRange) -- actual result range from the signature, if it exists
  -- | ExpectProjectionSelectorContext
  | ExpectIfConditionContext -- condition of if-then-else
  | ExpectPatternScrutineeContext (Expr Resolved) -- pattern type must match type of scrutinee
  | ExpectNotArgumentContext -- arg of NOT
  | ExpectPercentArgumentContext -- arg of '%'
  | ExpectConsArgument2Context -- second arg of cons
  | ExpectIfBranchesContext -- all branches of an if-then-else must have the same type
  | ExpectConsiderBranchesContext -- all branches of a consider must have the same type
  | ExpectHomogeneousListContext -- all elements of a list literal must have the same type
  | ExpectNamedArgContext Resolved Resolved -- function, name of arg
  | ExpectAppArgContext Bool Resolved Int -- projection?, function, number of arg
  | ExpectBinOpArgContext Text Int -- opname, number of arg (TODO: it would be better to have the token and its range here!)
  | ExpectDecideSignatureContext (Maybe SrcRange) -- actual result type range from the signature, if it exists
  | ExpectRegulativePartyContext -- party clause of obligation
  | ExpectRegulativeActionContext -- action clause of obligation
  | ExpectRegulativeDeadlineContext -- within clause of obligation
  | ExpectRegulativeTimestampContext -- timestamp of a regulative event
  | ExpectRegulativeFollowupContext -- hence clause of regulative rule
  | ExpectRegulativeContractContext -- when invoking a contract directive
  | ExpectRegulativeEventContext -- check an event expr
  | ExpectRegulativeProvidedContext -- the provided clauses are predicates on the variables bound by the pattern
  | ExpectPartyActionAgreementContext -- a PARTY may only be obligated to perform its own (actor-indexed) actions
  | ExpectAssertContext -- assertions should be Boolean
  | ExpectPostUrlContext -- URL argument of POST
  | ExpectPostHeadersContext -- headers argument of POST
  | ExpectPostBodyContext -- body argument of POST
  | ExpectConcatArgumentContext -- argument of CONCAT
  | ExpectAsStringArgumentContext -- argument of AS STRING
  | ExpectBreachReasonContext -- reason argument of BREACH
  | ExpectRecordCellContext -- cell (path) argument of RECORD/COMMIT/ATTEST
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

data NonDistinctContext =
    NonDistinctConstructors
  | NonDistinctSelectors
  | NonDistinctQuantifiers
  | NonDistinctTypeAppForm
  | NonDistinctTermAppForm
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

data CheckErrorContext =
    WhileCheckingDeclare Name CheckErrorContext
  | WhileCheckingDecide Name CheckErrorContext
  | WhileCheckingAssume Name CheckErrorContext
  | WhileCheckingExpression (Expr Name) CheckErrorContext
  | WhileCheckingPattern (Pattern Name) CheckErrorContext
  | WhileCheckingType (Type' Name) CheckErrorContext
  | None
  deriving stock (Eq, Generic, Show)
  deriving anyclass (NFData)

data Severity = SWarn | SError | SInfo
  deriving stock (Eq, Show)

instance HasSrcRange CheckErrorWithContext where
  rangeOf (MkCheckErrorWithContext e ctx) = rangeOf e <|> rangeOf ctx

instance HasSrcRange CheckErrorContext where
  rangeOf None = Nothing
  rangeOf (WhileCheckingDeclare n _)    = rangeOf n
  rangeOf (WhileCheckingDecide n _)     = rangeOf n
  rangeOf (WhileCheckingAssume n _)     = rangeOf n
  rangeOf (WhileCheckingExpression e _) = rangeOf e
  rangeOf (WhileCheckingPattern p _)    = rangeOf p
  rangeOf (WhileCheckingType t _)       = rangeOf t

instance HasSrcRange CheckError where
  rangeOf (OutOfScopeError n _)             = rangeOf n
  rangeOf (InconsistentNameInSignature n _) = rangeOf n
  rangeOf (InconsistentNameInAppForm n _)   = rangeOf n
  rangeOf (CheckInfo _ mr)                  = mr
  rangeOf (RegulativeActorMismatch p _ _)   = rangeOf p
  rangeOf _                                 = Nothing

-- | A token in a mixfix pattern, representing either a keyword (part of the function name)
-- or a parameter slot.
-- | Errors that can occur during mixfix pattern matching.
-- These provide detailed information for user-friendly error messages.
data MixfixMatchError
  = UnknownMixfixKeyword RawName [RawName]
    -- ^ Unknown keyword encountered. First is the unknown keyword, second is list of suggestions.
  | WrongKeyword RawName RawName
    -- ^ Expected a keyword but found a different one. (expected, actual)
  | MissingKeyword RawName
    -- ^ Expected keyword not found in the expression.
  | ExtraKeyword RawName
    -- ^ Unexpected keyword appeared in arguments.
  | ArityMismatch Int Int
    -- ^ Wrong number of arguments. (expected, actual)
  deriving stock (Show, Eq, Generic)
  deriving anyclass (NFData)

-- | Result of attempting to match a mixfix pattern.
-- This three-way type allows us to distinguish between:
-- 1. Pattern doesn't match at all (try next pattern or fall back)
-- 2. Pattern matches but with errors (report error to user)
-- 3. Pattern matches successfully
data MixfixMatchResult a
  = MixfixNoMatch
    -- ^ Pattern doesn't match; try other patterns or non-mixfix interpretation
  | MixfixError MixfixMatchError
    -- ^ Pattern partially matches but has an error (report to user)
  | MixfixSuccess a
    -- ^ Pattern matches successfully
  deriving stock (Show, Eq, Generic, Functor)
  deriving anyclass (NFData)

-- | Convert MixfixMatchResult to Maybe, discarding error details.
-- Useful for backwards compatibility during transition.
mixfixResultToMaybe :: MixfixMatchResult a -> Maybe a
mixfixResultToMaybe MixfixNoMatch = Nothing
mixfixResultToMaybe (MixfixError _) = Nothing
mixfixResultToMaybe (MixfixSuccess a) = Just a

-- | Result of matching a mixfix argument: either a keyword placeholder that was validated,
-- or a real parameter argument.
data MixfixArgMatch a
  = MixfixKeywordArg RawName
    -- ^ A keyword placeholder that matched. The RawName is the expected keyword.
  | MixfixParamArg a
    -- ^ A real parameter argument.
  deriving stock (Show, Eq, Generic, Functor)
  deriving anyclass (NFData)

-- | Information about a mixfix function pattern.
-- A mixfix function is one where the function name is interspersed with parameters,
-- like @person `is eligible for` program@ instead of @isEligibleFor person program@.
-- | A checked function signature.
data FunTypeSig = MkFunTypeSig
  { anno :: Anno
  , rtysig :: TypeSig Resolved
  -- ^ Already checked 'TypeSig'
  , rappForm :: AppForm Resolved
  -- ^ Already checked 'AppForm'
  , resultType :: Type' Resolved
  -- ^ Result type of the function
  , name :: CheckInfo
  -- ^ Name of this function
  , arguments :: [CheckInfo]
  -- ^ Arguments to the function.
  -- Includes type variables.
  , mixfixInfo :: Maybe MixfixInfo
  -- ^ If this is a mixfix function, its pattern info. Nothing for prefix functions.
  }
  deriving (Show, Eq, Generic)
  deriving anyclass (SOP.Generic, NFData)

-- | A checked declaration signature.
--
-- Contains in particular kind info for the type-level declaration.
--
data DeclTypeSig = MkDeclTypeSig
  { anno :: Anno
  , rtysig :: TypeSig Resolved
  -- ^ Already checked 'TypeSig'
  , rappForm :: AppForm Resolved
  -- ^ Already checked 'AppForm'
  , typeSynonym :: Maybe (Type' Name)
  -- ^ Whether this 'DeclaredHeadCache' is a type synonym.
  -- If yes, what is its *unchecked* type?
  , name :: CheckInfo
  -- ^ Name of this data type.
  , tyVars :: [CheckInfo]
  -- ^ Type variable arguments of this data type.
  }
  deriving (Show, Eq, Generic)
  deriving anyclass (SOP.Generic, NFData)

data DeclChecked a = MkDeclChecked
  { payload :: a
  , publicNames :: [CheckInfo]
  }
  deriving stock (Eq, Functor, Generic, Show)
  deriving anyclass (SOP.Generic, NFData)

type DeclareOrAssume = Either (Declare Resolved) (Assume Resolved)

-- | Registry of mixfix functions, indexed by their canonical name.
-- The canonical name encodes the full mixfix pattern with @_@ for parameter slots,
-- e.g. @"tax on _ item costing _ as GST in _"@.
-- This enables unambiguous lookup even when multiple functions share the same first keyword.
--
-- The registry also maintains a secondary index from first keyword to canonical names,
-- and a set of all keywords, for efficient call-site resolution.
data MixfixRegistry = MkMixfixRegistry
  { byCanonicalName :: !(Map RawName [FunTypeSig])
    -- ^ Primary index: canonical name -> function signatures
  , byFirstKeyword  :: !(Map RawName [RawName])
    -- ^ Secondary index: first keyword -> list of canonical names
  , keywordUniverse :: !(Set RawName)
    -- ^ All keywords appearing in any registered mixfix function
  }
  deriving (Show, Eq, Generic)
  deriving anyclass (NFData)

emptyMixfixRegistry :: MixfixRegistry
emptyMixfixRegistry = MkMixfixRegistry Map.empty Map.empty Set.empty

-- | Merge two registries (used when combining scopes).
unionMixfixRegistry :: MixfixRegistry -> MixfixRegistry -> MixfixRegistry
unionMixfixRegistry r1 r2 = MkMixfixRegistry
  { byCanonicalName = Map.unionWith (++) r1.byCanonicalName r2.byCanonicalName
  , byFirstKeyword  = Map.unionWith (++) r1.byFirstKeyword r2.byFirstKeyword
  , keywordUniverse = Set.union r1.keywordUniverse r2.keywordUniverse
  }

-- | Check if a given raw name is a known mixfix keyword in this registry.
isRegisteredKeyword :: RawName -> MixfixRegistry -> Bool
isRegisteredKeyword kw reg = kw `Set.member` reg.keywordUniverse

-- | Look up candidate function signatures by first keyword.
-- Returns all signatures whose mixfix pattern starts with the given keyword.
lookupByFirstKeyword :: RawName -> MixfixRegistry -> [FunTypeSig]
lookupByFirstKeyword kw reg =
  case Map.lookup kw reg.byFirstKeyword of
    Nothing -> []
    Just canonNames -> concatMap (\cn -> fromMaybe [] $ Map.lookup cn reg.byCanonicalName) canonNames

-- | Look up function signatures by canonical name (direct, unambiguous lookup).
lookupByCanonicalName :: RawName -> MixfixRegistry -> [FunTypeSig]
lookupByCanonicalName cn reg = fromMaybe [] $ Map.lookup cn reg.byCanonicalName

data CheckEnv =
  MkCheckEnv
    { moduleUri            :: !NormalizedUri
    , environment          :: !Environment
    , entityInfo           :: !EntityInfo
    , functionTypeSigs     :: !(Map SrcRange FunTypeSig)
    , declTypeSigs         :: !(Map SrcRange DeclTypeSig)
    , declareDeclarations  :: !(Map SrcRange (DeclChecked (Declare Resolved)))
    , assumeDeclarations   :: !(Map SrcRange (DeclChecked (Assume Resolved)))
    , mixfixRegistry       :: !MixfixRegistry
    -- ^ Registry of mixfix functions indexed by their first keyword
    , computedFields       :: !(Map RawName (Set RawName))
    -- ^ Map from record type RawName to set of computed field RawNames.
    -- Used to produce better error messages when a user tries to supply
    -- a computed field in a record constructor.
    , cyclicSynonyms       :: !(Set RawName)
    -- ^ Primary names of type synonyms found to be cyclic at declaration
    -- time. Their bodies are quarantined (installed as bodyless
    -- 'KnownType's) so that synonym expansion never touches them — a
    -- cyclic synonym has no finite expansion, and expanding one can
    -- blow up exponentially before the expansion fuel runs out.
    , errorContext         :: !CheckErrorContext
    , sectionStack         :: ![NonEmpty Text]
    , localBindings        :: !(Set Unique)
    -- ^ Uniques of the lexical LOCAL bindings currently in scope: function
    -- parameters, WHERE\/LET bindings, pattern variables, and type variables.
    -- These are introduced during body inference (via 'extendKnownMany') as
    -- opposed to section- or top-level module bindings (introduced via
    -- 'extendKnownGlobalMany'). Locals take ABSOLUTE priority over any
    -- section\/top-level\/imported binding of the same name during resolution
    -- (lexical shadowing), so we must track them explicitly: they are absent
    -- from 'sectionPaths', which otherwise conflates them with top-level and
    -- imported bindings.
    }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (NFData)

newtype SectionNames =
  MkSectionNames
    { sectionNames :: [Text]
    }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (NFData)

data CheckInfo = MkCheckInfo
  { names :: [Resolved]
  , checkEntity :: CheckEntity
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (NFData)

newtype Check a =
  MkCheck (CheckEnv -> CheckState -> [(With CheckErrorWithContext a, CheckState)])

runCheck :: Check a -> CheckEnv -> CheckState -> [(With CheckErrorWithContext a, CheckState)]
runCheck (MkCheck f) = f

runCheck' :: CheckEnv -> CheckState -> Check a -> [(With CheckErrorWithContext a, CheckState)]
runCheck' e s (MkCheck f) = f e s


-- NOTES on the Check monad:
--
-- Contrary to my first belief, we cannot
-- afford making the complete CheckState global, because the substitution
-- must be branch-dependent. Unification can create bindings for a
-- previously introduced unification variable (prior to branches) that
-- become invalid if the branch is not selected. So we have to backtrack
-- the current substitution.
--
-- I'm not sure if the environment and supply should be backtracked.
-- The supply would be better / safer to be global? Why? If we ever want
-- to accept / merge the results of several branches, then we'd have to
-- be careful that we don't get inconsistencies. On the other hand, we
-- probably only want to do this if unification variables introduced in
-- the different branches have been unambiguously resolved, so it should
-- probably be fine.

data CheckResult =
  MkCheckResult
    { program        :: !(Module  Resolved)
    , errors         :: ![CheckErrorWithContext]
    , substitution   :: !Substitution
    , environment    :: !Environment
    , entityInfo     :: !EntityInfo
    , infoMap        :: !InfoMap
    , nlgMap         :: !NlgMap
    , scopeMap       :: !ScopeMap
    , descMap        :: !DescMap
    , mixfixRegistry :: !MixfixRegistry
    -- ^ Registry of mixfix functions from this module (to be propagated to importers)
    }

-- -------------------
-- Instances for Check
-- -------------------

instance Functor Check where
  fmap = liftM

instance Applicative Check where
  pure x =
    MkCheck $ \_ s -> [(Plain x, s)]
  (<*>) = ap

instance Monad Check where
  (>>=) :: forall a b. Check a -> (a -> Check b) -> Check b
  m >>= f =
    MkCheck $ \e s ->
      let
        results = runCheck m e s
      in
        concatMap (\ (wea, s') -> distributeWith (fmap (runCheck' e s' . f) wea)) results

instance MonadState CheckState Check where
  get :: Check CheckState
  get = MkCheck $ \_ s -> [(Plain s, s)]

  put :: CheckState -> Check ()
  put s = MkCheck $ \_ _ -> [(Plain (), s)]

instance MonadReader CheckEnv Check where
  ask = MkCheck \e s -> [(Plain e, s)]
  local f c = MkCheck $ runCheck c . f

instance MonadWith CheckErrorWithContext Check where
  with :: CheckErrorWithContext -> Check ()
  with e = MkCheck $ \_ s -> [(With e (Plain ()), s)]

instance Alternative Check where
  empty :: Check a
  empty = MkCheck $ \_ _ -> []

  (<|>) :: Check a -> Check a -> Check a
  (<|>) m1 m2 = MkCheck $ \e s -> runCheck m1 e s ++ runCheck m2 e s

-- ----------------------------------------------------------------------------
-- Primitives for Uniques, Errors and similar.
-- ----------------------------------------------------------------------------

step :: Check Int
step = do
  current <- use #supply
  let next = current + 1
  assign #supply next
  pure current

newUnique :: Check Unique
newUnique = do
  i <- step
  u <- asks (.moduleUri)
  pure (MkUnique 'c' i u)

addError :: CheckError -> Check ()
addError e = do
  ctx <- asks (.errorContext)
  with (MkCheckErrorWithContext e ctx)

addWarning :: CheckWarning -> Check ()
addWarning = addError . CheckWarning

fatalInternalError :: InternalCheckError -> Check a
fatalInternalError e = throw e

choose :: [Check a] -> Check a
choose = asum

anyOf :: [a] -> Check a
anyOf = asum . fmap pure

-- ----------------------------------------------------------------------------
-- JL4 specific primitives
-- ----------------------------------------------------------------------------

fresh :: RawName -> Check (Type' Resolved)
fresh prefix = do
  i <- step
  pure (InfVar emptyAnno prefix i)

outOfScope :: Name -> Type' Resolved -> Check Resolved
outOfScope n t = do
  addError (OutOfScopeError n t)
  u <- newUnique
  pure (OutOfScope u n)

ambiguousTerm :: Name -> [(Resolved, Type' Resolved)] -> Check Resolved
ambiguousTerm n xs = do
  addError (AmbiguousTermError n xs)
  u <- newUnique
  pure (OutOfScope u n)

ambiguousType :: Name -> [(Resolved, Kind)] -> Check Resolved
ambiguousType n xs = do
  addError (AmbiguousTypeError n xs)
  u <- newUnique
  pure (OutOfScope u n)

-- ----------------------------------------------------------------------------
-- Info Map
-- ----------------------------------------------------------------------------


addInfoForSrcRange :: SrcRange -> Info -> Check ()
addInfoForSrcRange srcRange i = do
  env <- asks $ view #environment
  ei <- asks $ view #entityInfo
  modifying' #scopeMap $
    IV.insert (IV.srcRangeToInterval srcRange) (env, ei)
  modifying' #infoMap $
    IV.insert (IV.srcRangeToInterval srcRange) i

addNlgForSrcRange :: SrcRange -> Nlg -> Check ()
addNlgForSrcRange srcRange i =
  modifying' #nlgMap $
    IV.insert (IV.srcRangeToInterval srcRange) i

addDescForSrcRange :: SrcRange -> Text -> Check ()
addDescForSrcRange srcRange t =
  modifying' #descMap $
    IV.insert (IV.srcRangeToInterval srcRange) t

-- ----------------------------------------------------------------------------
-- JL4 specific primitives for resolving names
-- ----------------------------------------------------------------------------

resolvedType :: Resolved -> Check Resolved
resolvedType n = do
  ei <- asks (.entityInfo)
  case Map.lookup (getUnique n) ei of
    Nothing -> do
      -- TODO: there are cases where this situation is a clear bug.
      -- Sometimes, it is fine, e.g. when the 'Resolved' is 'OutOfScope'.
      -- Tricky what to do here.
      -- addError $ MissingEntityInfo n
      pure n
    Just (_, checkEntity) ->
      case checkEntity of
        KnownType kind _resolved _ -> do
          setAnnResolvedKindOfResolved kind n
        KnownTerm ty term -> do
          setAnnResolvedTypeOfResolved ty (Just term) n
        KnownTypeVariable -> do
          setAnnResolvedAsTypeVar n
        KnownSection _ -> pure n -- TODO: this is probably not what we want, maybe some internal error?

lookupRawNameInEnvironment :: RawName -> Check [(Unique, Name, CheckEntity)]
lookupRawNameInEnvironment rn = do
  env <- asks (.environment)
  ei  <- asks (.entityInfo)
  let
      proc :: Unique -> Maybe (Unique, Name, CheckEntity)
      proc u = do
        (o, ce) <- Map.lookup u ei
        pure (u, o, ce)

      candidates :: [(Unique, Name, CheckEntity)]
      candidates = mapMaybe proc (Map.findWithDefault [] rn env)

  pure candidates

-- | Record, for each given 'Unique', the section path (the current
-- 'sectionStack') at which it was registered. This is what enables
-- lexical (nearest-enclosing-section) resolution of unqualified names.
--
-- Top-level bindings (empty section path) are not recorded: their absence
-- from the map is interpreted as the empty path by 'sectionProximity'.
recordSectionPath :: [NonEmpty Text] -> [Unique] -> Check ()
recordSectionPath []    _  = pure ()
recordSectionPath path us =
  modifying' #sectionPaths $ \m ->
    foldl' (\acc u -> Map.insert u path acc) m us

-- | How "close" a candidate binding's section path is to the section in which
-- an unqualified reference occurs.
--
-- Returns @Just 0@ when the candidate is defined in the very same section,
-- @Just 1@ for the immediately enclosing parent section, and so on. Top-level
-- bindings (empty candidate path) are ancestors of every section, at a distance
-- equal to the current nesting depth.
--
-- Returns 'Nothing' when the candidate is not on the current section's ancestry
-- chain (e.g. a sibling section, a cousin, or an imported binding). Such
-- candidates are not brought into lexical scope by this proximity mechanism.
sectionProximity :: [NonEmpty Text] -> [NonEmpty Text] -> Maybe Int
sectionProximity current candidate
  | candidate `List.isPrefixOf` current = Just (length current - length candidate)
  | otherwise                           = Nothing

-- | Filter a set of viable resolution candidates down to those in the nearest
-- enclosing section, implementing lexical scoping with shadowing.
--
-- Given the current module URI, the current section stack, a map of each
-- candidate's defining section path, and the viable candidates (each tagged
-- with its 'Unique'):
--
--   * IMPORTED candidates (whose 'Unique' belongs to another module) are never
--     ranked by proximity and are never eliminated: they remain co-equal
--     viable candidates. This preserves spec §5.5 — a same-typed collision
--     between an import and a local section binding stays ambiguous rather than
--     being silently shadowed — and keeps cross-module overloads (e.g. the
--     builtin comparison operators) available for type-directed resolution.
--   * Among the CURRENT module's candidates: if any lie on the current
--     section's ancestry (same section, parent, ..., top level), keep only
--     those at the /minimum/ proximity (the nearest enclosing section), and
--     drop farther ancestors and off-ancestry siblings. Ties at the same
--     proximity are left for the caller to disambiguate (type-directed
--     'choose', else ambiguity error). Imported candidates are always retained
--     alongside the nearest ancestors.
--   * If no current-module candidate lies on the ancestry, fall back to /all/
--     viable candidates, preserving the pre-existing flat-scope behaviour.
--
-- The 'Unique' of each kept candidate is returned alongside it so that callers
-- can de-duplicate (the same candidate can be surfaced from several type
-- groups; see 'selectByProximityPerType').
selectByProximity
  :: forall a
   . NormalizedUri
  -> [NonEmpty Text]
  -> Map Unique [NonEmpty Text]
  -> [(Unique, a)]
  -> [(Unique, a)]
selectByProximity curUri current paths viable =
  case ancestors of
    [] -> viable
    _  ->
      let nearest = minimum (fmap (\(_, _, d) -> d) ancestors)
      in [ (u, a) | (u, a, d) <- ancestors, d == nearest ] ++ imports
  where
    isImport :: Unique -> Bool
    isImport u = u.moduleUri /= curUri

    -- Candidates from other modules: never filtered out by proximity.
    imports :: [(Unique, a)]
    imports = [ (u, a) | (u, a) <- viable, isImport u ]

    -- Current-module candidates that sit on the current section's ancestry,
    -- tagged with their proximity distance.
    ancestors :: [(Unique, a, Int)]
    ancestors =
      [ (u, a, d)
      | (u, a) <- viable
      , not (isImport u)
      , Just d <- [sectionProximity current (Map.findWithDefault [] u paths)]
      ]

-- | An annotation-insensitive skeleton of a 'Type'' Resolved', used purely as a
-- grouping key when deciding which resolution candidates are "the same type".
--
-- Structural equality on 'Type'' Resolved' cannot be used directly because it
-- includes source annotations, so e.g. two @NUMBER@ occurrences at different
-- locations would compare unequal. This skeleton keys type constructors by the
-- 'Unique' of their head and drops all annotations, so it treats two @NUMBER@s
-- as equal while keeping genuinely different types (@STRING@, @MAYBE NUMBER@,
-- ...) distinct — exactly what overload-preserving shadowing needs.
data TypeKey
  = TyKType
  | TyKApp Unique [TypeKey]
  | TyKFun [TypeKey] TypeKey
  | TyKForall Int TypeKey
  | TyKInfVar Int
  deriving stock (Eq, Show)

typeKey :: Type' Resolved -> TypeKey
typeKey = \ case
  Type _        -> TyKType
  TyApp _ r ts  -> TyKApp (getUnique r) (typeKey <$> ts)
  Fun _ onts t  -> TyKFun (typeKey . optionallyNamedTypeType <$> onts) (typeKey t)
  Forall _ ns t -> TyKForall (length ns) (typeKey t)
  InfVar _ _ i  -> TyKInfVar i

-- | Whether a 'TypeKey' is an unresolved inference variable (a wildcard for
-- the purpose of proximity-first resolution; see 'selectByProximityPerType').
isInfVarKey :: TypeKey -> Bool
isInfVarKey (TyKInfVar _) = True
isInfVarKey _             = False

-- | Stable grouping by an equality key (first-seen order preserved, both for
-- the groups and within each group). Small candidate lists, so the quadratic
-- cost is irrelevant.
groupByKey :: forall k a. Eq k => (a -> k) -> [a] -> [(k, [a])]
groupByKey key = foldl' insertItem []
  where
    insertItem :: [(k, [a])] -> a -> [(k, [a])]
    insertItem acc x =
      let k = key x
      in case List.lookup k acc of
           Just _  -> [ (k', if k' == k then xs <> [x] else xs) | (k', xs) <- acc ]
           Nothing -> acc <> [(k, [x])]

-- | Apply 'selectByProximity' within each group of candidates that share the
-- same type (or, for types, the same kind), then take the union (de-duplicated
-- by 'Unique').
--
-- Grouping by type is what lets genuinely distinct overloads coexist across
-- sections: a concrete-typed binding only ever shadows another binding of the
-- /same/ type. Type-directed resolution ('choose') therefore still ranges over
-- every concrete overload regardless of where it is defined, while same-typed
-- bindings obey lexical scoping and resolve to the nearest enclosing section.
-- This is required by the standard library, whose comparison operators have
-- NUMBER\/STRING\/BOOLEAN\/MAYBE overloads spread across sibling subsections.
--
-- The cross-type proximity interaction needed by forward references (spec §5.3;
-- see 'resolveTerm'') is handled by the caller BEFORE this function, so this is
-- deliberately a straightforward per-type-group application of
-- 'selectByProximity'.
selectByProximityPerType
  :: forall k a. Eq k
  => NormalizedUri
  -> [NonEmpty Text]
  -> Map Unique [NonEmpty Text]
  -> [(k, Unique, a)]
  -> [a]
selectByProximityPerType curUri current paths cands =
  dedupByUnique kept
  where
    kept :: [(Unique, a)]
    kept =
      concatMap (\(_, g) -> selectByProximity curUri current paths [ (u, a) | (_, u, a) <- g ])
                (groupByKey (\(k, _, _) -> k) cands)

    dedupByUnique :: [(Unique, a)] -> [a]
    dedupByUnique = go Set.empty
      where
        go _    []            = []
        go seen ((u, a) : xs)
          | u `Set.member` seen = go seen xs
          | otherwise           = a : go (Set.insert u seen) xs

-- | Section proximity of a CURRENT-MODULE ancestor 'Unique'; 'Nothing' for
-- imports (a different module URI) and for off-ancestry (sibling\/cousin)
-- same-module candidates.
ancestorProximity :: NormalizedUri -> [NonEmpty Text] -> Map Unique [NonEmpty Text] -> Unique -> Maybe Int
ancestorProximity curUri current paths u
  | u.moduleUri /= curUri = Nothing
  | otherwise             = sectionProximity current (Map.findWithDefault [] u paths)

isTopLevelBindingInSection :: Unique -> Section Resolved -> Bool
isTopLevelBindingInSection u (MkSection _a  _mn _maka decls) = any (elem u . map getUnique . relevantResolveds) decls
  where
  relevantResolveds = \ case
    Declare _ (MkDeclare _ _ af _) -> appFormHeads af
    Decide _ (MkDecide _ _ af _) -> appFormHeads af
    Assume _ (MkAssume _ _ af _) -> appFormHeads af
    Directive _ _ -> []
    Import _ _ -> []
    Timezone _ _ -> []
    -- NOTE: Sections are a toplevel binding in the current section but can also contain further
    -- toplevel bindings
    Section _ (MkSection _ mr maka decls') -> toResolved mr <> toResolved maka <> foldMap relevantResolveds decls'

resolveTerm' :: (TermKind -> Bool) -> Name -> Check (Resolved, Type' Resolved)
resolveTerm' p n = do
  options <- lookupRawNameInEnvironment (rawName n)
  -- Lexical scoping: among the viable candidates, prefer those defined in the
  -- nearest enclosing section (see 'selectByProximity'). Only fall through to
  -- type-directed 'choose'/ambiguity once proximity can no longer discriminate.
  current <- asks (.sectionStack)
  curUri  <- asks (.moduleUri)
  locals  <- asks (.localBindings)
  paths <- use #sectionPaths
  viable <- catMaybes <$> traverse proc options
  -- In-scope lexical LOCAL bindings (function parameters, WHERE\/LET bindings,
  -- pattern variables) take ABSOLUTE priority over any section-, top-level- or
  -- import-defined binding of the same name. Without this, a parameter would be
  -- silently shadowed by an enclosing section binding (section proximity 0 wins
  -- over a local, which carries no section path). If any candidate is a local,
  -- restrict resolution to the locals before section-proximity ranking.
  let localCandidates = [ c | c@(_, _, u, _) <- viable, u `Set.member` locals ]
      candidates0 = if null localCandidates then viable else localCandidates
      -- FIX B (spec §5.3: proximity dominates type-direction). A same-module
      -- value binding whose type is still an unresolved 'InfVar' is a forward
      -- reference to a not-yet-inferred un-annotated DECIDE. Because it lands in
      -- a different 'typeKey' group than a same-named concrete ancestor, per-type
      -- grouping alone would never compare the two by proximity, yielding a
      -- spurious order-dependent ambiguity. So, up front: if the nearest
      -- current-module VALUE-binding ancestor is such a wildcard, it lexically
      -- shadows every strictly-farther current-module VALUE-binding ancestor of
      -- the same name, regardless of type.
      --
      -- We restrict this to VALUE bindings (Computable\/Local\/Assumed) on BOTH
      -- ends: record selectors and data constructors live in a separate
      -- (projection\/pattern) namespace and must never be shadowed by, nor act
      -- as, a same-named value forward reference — e.g. a @WHERE@ binding named
      -- like a field it projects. Imports (no ancestry proximity) are never
      -- shadowed here, preserving import\/local ambiguity (spec §5.5). A wildcard
      -- can only be a current-module forward reference (imports are already
      -- fully typed), so this never perturbs cross-module overloads.
      prox u = ancestorProximity curUri current paths u
      wildValueAncestorProx =
        case [ d | (k, isVal, u, _) <- candidates0
                 , isVal, isInfVarKey k, Just d <- [prox u] ] of
          [] -> Nothing
          ds -> Just (minimum ds)
      keepCand (_, isVal, u, _) =
        case (wildValueAncestorProx, prox u) of
          (Just w, Just d) | isVal -> d <= w
          _                        -> True
      candidates = [ (k, u, a) | (k, _isVal, u, a) <- filter keepCand candidates0 ]
  case selectByProximityPerType curUri current paths candidates of
    [] -> do
      v <- fresh (rawName n)
      n' <- setAnnResolvedType v Nothing n
      rn <- outOfScope n' v
      pure (rn, v)
    [x] -> x
    xs -> choose xs <|> do
      v <- fresh (rawName n)
      n' <- setAnnResolvedType v Nothing n
      xs' <- sequenceA xs
      rn <- ambiguousTerm n' xs'
      pure (rn, v)
  where
    -- Group by the declared type (via its annotation-insensitive 'typeKey') so
    -- that same-typed bindings shadow lexically while distinct overloads remain
    -- visible for type-directed resolution. We apply the current substitution
    -- first so that inference variables introduced during signature scanning are
    -- resolved to concrete types before we compare them. The 'Bool' records
    -- whether this is a value binding (as opposed to a selector\/constructor),
    -- which governs forward-reference shadowing (see above).
    proc :: (Unique, Name, CheckEntity) -> Check (Maybe (TypeKey, Bool, Unique, Check (Resolved, Type' Resolved)))
    proc (u, o, KnownTerm t tk) | p tk = do
      t' <- applySubst t
      pure $ Just . (typeKey t', isValueBinding tk, u,) $ do
        n' <-  setAnnResolvedType t (Just tk) n
        pure (Ref n' u o, t)
    proc _                             = pure Nothing

-- | Whether a 'TermKind' names a value in the ordinary term namespace (as
-- opposed to a record selector or data constructor, which are reached through
-- projection\/pattern syntax). Only value bindings participate in
-- forward-reference lexical shadowing (see 'resolveTerm'').
isValueBinding :: TermKind -> Bool
isValueBinding = \ case
  Computable       -> True
  Local            -> True
  Assumed          -> True
  Selector         -> False
  ComputedSelector -> False
  Constructor      -> False

resolveTerm :: Name -> Check (Resolved, Type' Resolved)
resolveTerm = resolveTerm' (const True)

_resolveSelector :: Name -> Check (Resolved, Type' Resolved)
_resolveSelector = resolveTerm' (== Selector)

resolveConstructor :: Name -> Check (Resolved, Type' Resolved)
resolveConstructor = resolveTerm' (== Constructor)

setAnnNlg ::
     (HasAnno a, AnnoToken a ~ PosToken, AnnoExtra a ~ Extension)
  => Nlg -> a -> Check a
setAnnNlg nlg a = withRange a $ \r -> do
  addNlgForSrcRange r nlg
  pure $ a & annoOf % annNlg ?~ nlg

setAnnResolvedType ::
     (HasAnno a, AnnoToken a ~ PosToken, AnnoExtra a ~ Extension)
  => Type' Resolved -> Maybe TermKind -> a -> Check a
setAnnResolvedType t k a = withRange a $ \r -> do
  let info = TypeInfo t k
  addInfoForSrcRange r info
  pure $ a & annoOf % annInfo ?~ info

setAnnResolvedKind ::
     (HasAnno a, AnnoToken a ~ PosToken, AnnoExtra a ~ Extension)
  => Kind -> a -> Check a
setAnnResolvedKind k a = withRange a $ \r -> do
  let info = KindInfo k
  addInfoForSrcRange r info
  pure $ a & annoOf % annInfo ?~ info

setAnnTypeVar ::
     (HasAnno a, AnnoToken a ~ PosToken, AnnoExtra a ~ Extension)
  => a -> Check a
setAnnTypeVar a = withRange a $ \r -> do
  let info = TypeVariable
  addInfoForSrcRange r info
  pure $ a & annoOf % annInfo ?~ info

withRange :: (HasAnno a, Applicative f) => a -> (SrcRange -> f a) -> f a
withRange a f = case rangeOf (getAnno a) of
  Nothing -> pure a
  Just r -> f r

setAnnNlgOfResolved :: Nlg -> Resolved -> Check Resolved
setAnnNlgOfResolved nlg = traverseResolved (setAnnNlg nlg)

setAnnResolvedTypeOfResolved :: Type' Resolved -> Maybe TermKind -> Resolved -> Check Resolved
setAnnResolvedTypeOfResolved t k = traverseResolved (setAnnResolvedType t k)

setAnnResolvedKindOfResolved :: Kind -> Resolved -> Check Resolved
setAnnResolvedKindOfResolved k = traverseResolved (setAnnResolvedKind k)

setAnnResolvedAsTypeVar :: Resolved -> Check Resolved
setAnnResolvedAsTypeVar = traverseResolved setAnnTypeVar

type ToResolved = Optics.GPlate Resolved

toResolved :: ToResolved a => a -> [Resolved]
toResolved = Optics.toListOf Optics.gplate

-- | Should never return 'Nothing' if our system is OK.
getEntityInfo :: Resolved -> Check (Maybe CheckEntity)
getEntityInfo r = do
  ei <- asks (.entityInfo)
  case Map.lookup (getUnique r) ei of
    Nothing       -> do
      addError (MissingEntityInfo r)
      pure Nothing
    Just (_n, ce) -> pure (Just ce)

-- | Given a substitution from uniques to types, substitute
-- all occurrences of the given uniques. There's no scoping
-- going on in this, because uniques are unique!
--
substituteType :: Map Unique (Type' Resolved) -> Type' Resolved -> Type' Resolved
substituteType _ (Type ann)               = Type ann
substituteType s t@(TyApp _ r []) =
  case Map.lookup (getUnique r) s of
    Nothing -> t
    Just t' -> t'
substituteType s (TyApp ann n ts)         =
  TyApp ann n (substituteType s <$> ts)
substituteType s (Fun ann onts t)         =
  Fun ann (substituteOptionallyNamedType s <$> onts) (substituteType s t)
substituteType _ (Forall ann ns t)        =
  Forall ann ns t -- TODO!! Inner Forall needs some form of alpha renaming.
substituteType _ (InfVar ann prefix i)    = InfVar ann prefix i
-- substituteType s (ParenType ann t)        = ParenType ann (substituteType s t)

substituteOptionallyNamedType :: Map Unique (Type' Resolved) -> OptionallyNamedType Resolved -> OptionallyNamedType Resolved
substituteOptionallyNamedType s (MkOptionallyNamedType ann mn t) =
  MkOptionallyNamedType ann mn (substituteType s t)

-- | A class for applying the subsitution on inference variables exhaustively.
--
-- Note that we currently are applying the substitution late, which means we have
-- to recursively apply it.
--
class ApplySubst a where
  applySubst :: a -> Check a

instance ApplySubst (Type' Resolved) where
  applySubst (Type  ann)       = pure (Type ann)
  applySubst (TyApp ann n ts)  = TyApp ann n <$> traverse applySubst ts
  applySubst (Fun ann onts t)  = Fun ann <$> traverse applySubst onts <*> applySubst t
  applySubst (Forall ann ns t) = Forall ann ns <$> applySubst t
  applySubst (InfVar ann rn i) = do
    s <- use #substitution
    case Map.lookup i s of
      Nothing -> pure (InfVar ann rn i)
      Just t  -> do
        -- we actually modify the substitution so that we don't do the same work many times if the same variable occurs often
        -- we are still traversing every time though; we could do better
        t' <- applySubst t
        modifying #substitution (Map.insert i t')
        pure t'

instance ApplySubst (OptionallyNamedType Resolved) where
  applySubst (MkOptionallyNamedType ann mn t) = MkOptionallyNamedType ann mn <$> applySubst t

instance ApplySubst CheckError where
  applySubst = traverseOf (gplate @(Type' Resolved) @CheckError) applySubst

instance ApplySubst CheckErrorContext where
  applySubst = traverseOf (gplate @(Type' Resolved) @CheckErrorContext) applySubst

instance ApplySubst CheckErrorWithContext where
  applySubst = traverseOf (gplate @(Type' Resolved) @CheckErrorWithContext) applySubst

instance ApplySubst EntityInfo where
  applySubst = traverse (\(n, entity) -> (n, ) <$> applySubst entity)

instance ApplySubst CheckEntity where
  applySubst = traverseOf (gplate @(Type' Resolved)) applySubst

-- | Checks that two resolved names refer to the same unique.
ensureSameRef :: Resolved -> Resolved -> Check Bool
ensureSameRef r1 r2 =
  pure (getUnique r1 == getUnique r2)

optionallyNamedTypeType :: OptionallyNamedType n -> Type' n
optionallyNamedTypeType (MkOptionallyNamedType _ _ t) = t

-- | Biased choice. Only takes the second option if the first fails.
--
orElse :: Check a -> Check a -> Check a
orElse m1 m2 = do
  MkCheck $ \ e s ->
    let
      candidates = runCheck m1 e s

      isSuccess (Plain _, _)  = True
      isSuccess (With _ _, _) = False
    in
      case filter isSuccess candidates of
        [] -> runCheck m2 e s
        xs -> xs

-- | Allow the subcomputation to have at most one result.
--
-- NOTE: This backtracking search is type-directed and prunes only after it
-- sees a second success. If surface code leaves obvious disambiguators out
-- (e.g. missing `day/month/year` helpers while overloading `+/-/<` on DATE
-- and NUMBER) the candidate space can balloon and appear to “hang” before we
-- finally report ambiguity/out-of-scope. Keep cheap, unambiguous helpers in
-- libraries to keep this search from going quadratic in practice.
prune :: forall a. Check a -> Check a
prune m = do
  ctx <- asks (.errorContext)
  MkCheck $ \ s env ->
    let
      candidates :: [(With CheckErrorWithContext a, CheckState)]
      candidates = runCheck m s env

      proc []                    = [] -- should never occur
      proc [a]                   = [a]
      proc ((Plain a, s')  : cs) = procPlain (Plain a, s') cs
      proc ((With e x, s') : cs) = procWith (With e x, s') cs

      -- We have a success, we don't want a second one
      procPlain a []                   = [a]
      procPlain a ((With _ _, _) : cs) = procPlain a cs
      procPlain a cs
        | plain = [first (With (MkCheckErrorWithContext InternalAmbiguityError ctx)) a]
        -- NOTE: in the case of ambiguity errors, the ambiguity error will always occurs as
        -- the last element in the list
        | otherwise = [last cs]
        where
          plain = allPlain $ map fst cs

      -- We have a failure, we're still looking for a success, and prefer the last failure
      procWith a []                    = [a]
      procWith _ ((Plain a, s')  : cs) = procPlain (Plain a, s') cs
      procWith _ ((With e x, s') : cs) = procWith (With e x, s') cs

    in
      proc candidates

allPlain :: [With e a] -> Bool
allPlain = all \case
  Plain{} -> True
  With {} -> False

-- | Prune to one result if there's a clearly best one at this point,
-- but don't force it.
--
softprune :: forall a. Check a -> Check a
softprune m = do
  MkCheck $ \ s env ->
    let
      candidates :: [(With CheckErrorWithContext a, CheckState)]
      candidates = runCheck m s env

      proc []                    = [] -- should never occur
      proc [a]                   = [a]
      proc ((Plain a, s')  : cs) = procPlain (Plain a, s') cs
      proc ((With e x, s') : cs) = procWith (With e x, s') cs

      -- We have a success, we don't want a second one
      procPlain a []                    = [a]
      procPlain _ ((Plain _, _)  : _cs) = candidates
      procPlain a ((With _ _, _) :  cs) = procPlain a cs

      -- We have a failure, we're still looking for a success, and prefer the last failure
      procWith a []                     = [a]
      procWith _ ((Plain a, s')  : cs)  = procPlain (Plain a, s') cs
      procWith _ ((With e x, s') : cs)  = procWith (With e x, s') cs

    in
      proc candidates

-- | Set the 'CheckErrorContext' for the given scope.
errorContext :: (CheckErrorContext -> CheckErrorContext) -> Check a -> Check a
errorContext errorCtx =
  local (\env -> env { errorContext = errorCtx env.errorContext })

-- | Push a new 'Section' Name onto the stack.
-- This is used for exposing qualified names during type checking.
pushSection :: NonEmpty Text -> Check a -> Check a
pushSection rawSectionName =
  local (\env -> env { sectionStack = env.sectionStack <> [rawSectionName] })

-- ------------------------------------
-- Scope Manipulation
-- ------------------------------------

-- | Make the given 'CheckInfo' known in the given scope.
extendKnown :: CheckInfo -> Check a -> Check a
extendKnown ci =
  extendKnownMany [ci]

-- | Make many 'CheckInfo's known for the given scope, marking them as lexical
-- LOCAL bindings (parameters, WHERE\/LET, pattern variables, type variables).
-- Locals take absolute priority over section\/top-level\/imported bindings of
-- the same name during resolution. Use 'extendKnownGlobalMany' instead for
-- section- and module-level bindings (which must obey section proximity rather
-- than shadow unconditionally).
extendKnownMany :: [CheckInfo] -> Check a -> Check a
extendKnownMany cis = do
  local (markLocalBindings cis . extendEnv cis)

-- | Like 'extendKnownMany', but does NOT mark the bindings as locals. Used for
-- section- and top-level module bindings, whose relative precedence is governed
-- by section proximity ('selectByProximity'), not by unconditional lexical
-- shadowing.
extendKnownGlobalMany :: [CheckInfo] -> Check a -> Check a
extendKnownGlobalMany cis = do
  local (extendEnv cis)

-- | Record the 'Unique's of the given 'CheckInfo's as in-scope lexical locals.
markLocalBindings :: [CheckInfo] -> CheckEnv -> CheckEnv
markLocalBindings cis env =
  env { localBindings = foldl' insertCi env.localBindings cis }
  where
    insertCi :: Set Unique -> CheckInfo -> Set Unique
    insertCi acc ci = foldl' (\s r -> Set.insert (getUnique r) s) acc ci.names

-- | Extend the scope of the 'CheckEnv' with all '[CheckInfo]'.
extendEnv :: [CheckInfo] -> CheckEnv -> CheckEnv
extendEnv cis env =
  foldl' goCheckInfo env cis
 where
  goCheckInfo :: CheckEnv -> CheckInfo -> CheckEnv
  goCheckInfo e ci =
    foldl' (goResolved ci.checkEntity) e ci.names

  goResolved :: CheckEntity -> CheckEnv -> Resolved -> CheckEnv
  goResolved ce e a = MkCheckEnv
    { environment = Map.alter proc (rawName n) e.environment
    , entityInfo = Map.insert u (n, ce) e.entityInfo
    , moduleUri = e.moduleUri
    , errorContext = e.errorContext
    , functionTypeSigs = e.functionTypeSigs
    , declTypeSigs = e.declTypeSigs
    , declareDeclarations = e.declareDeclarations
    , assumeDeclarations = e.assumeDeclarations
    , mixfixRegistry = e.mixfixRegistry
    , computedFields = e.computedFields
    , cyclicSynonyms = e.cyclicSynonyms
    , sectionStack = e.sectionStack
    , localBindings = e.localBindings
    }
    where
      u :: Unique
      n :: Name
      (u, n) = getUniqueName a

      proc :: Maybe [Unique] -> Maybe [Unique]
      proc Nothing   = Just [u]
      proc (Just xs) = Just (u : xs)

makeKnown :: Resolved -> CheckEntity -> CheckInfo
makeKnown a =
  makeKnownMany [a]

makeKnownMany :: [Resolved] -> CheckEntity -> CheckInfo
makeKnownMany rs ce =
  MkCheckInfo
    { names = rs
    , checkEntity = ce
    }

-- -------------------------------------
-- Smart constructors for Resolved names
-- -------------------------------------

def :: Name -> Check Resolved
def n = do
  u <- newUnique
  pure (Def u n)

-- | Introduce the new name as a defining occurrence of an alias of an already existing name.
defAka :: Resolved -> Name -> Check Resolved
defAka r n = do
  let u = getUnique r
  pure (Def u n)

ref :: Name -> Resolved -> Check Resolved
ref n a =
  let
    (u, o) = getUniqueName a
  in
    pure (Ref n u o)
