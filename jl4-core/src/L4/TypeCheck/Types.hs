-- | Types needed during the scope and type checking phase.
{-# LANGUAGE CPP #-}
{-# LANGUAGE UndecidableInstances #-}
module L4.TypeCheck.Types where

import Base
#if defined(SERIALISE_ENABLED)
import Codec.Serialise (Serialise)
#endif
import qualified Optics
import L4.Annotation (HasSrcRange(..), HasAnno(..), AnnoExtra, AnnoToken, annoExtra, emptyAnno)
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
  | ClausePatternCountMismatch (Maybe SrcRange) Name Int Int
    -- ^ The clauses of a multi-clause group have a different number of
    -- patterns than its GIVEN names inputs ('L4.TypeCheck.clauseInputsAgainstGiven').
    -- Carries the first clause's head range, the group's name, the number of
    -- patterns in each clause, and the number of inputs the GIVEN names.
  | ExportedClausesWithoutGiven (Maybe SrcRange) Name
    -- ^ An @\@export@ed definition written as clauses with patterns, one
    -- clause or several, with no GIVEN to name its inputs
    -- ('L4.TypeCheck.refuseExportedClausesWithoutGiven'). Carries the range of
    -- the @\@export@ and the definition's name.
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
  | SynonymExpansionLimit Int Resolved
    -- ^ Comparing two types followed this many type synonyms in a row and
    -- stopped at the one given, which still stands for another type. The
    -- types are not known to differ, so this is not a 'TypeMismatch'. See
    -- 'L4.TypeCheck.Unify.synonymExpansionFuel'.
  | SuppliedComputedField Name
    -- ^ Tried to supply a computed field in a record constructor (field name)
  | ExportFunctionTypeInput Resolved Resolved
    -- ^ An @export-decorated DECIDE has a function-typed input (GIVEN or
    -- referenced ASSUME). Arguments: exported-function name, offending
    -- parameter/assume name.
  | ExportEventType (Maybe SrcRange) Resolved (Maybe Resolved)
    -- ^ An @export-decorated DECIDE takes or returns an EVENT (see
    -- 'L4.Export.mentionsEvent'). Arguments: the range of the @\@export@,
    -- the exported function's name, and the input's name (Nothing when it is
    -- the result).
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

-- | Why a clause of a multi-clause group is never tried.
--
-- Unstable also has @CoveredByClausesAbove@ (every input the clause matches
-- is matched by a clause above it), found from the redundant rows of its
-- coverage analysis. Main's analysis ('L4.TypeCheck.uncoveredRows') does not
-- compute redundant rows, so that form is not reported here; see
-- 'L4.TypeCheck.warnUnreachableClauses'.
data UnreachableClause
  = AfterClauseMatchingAnything Int
    -- ^ a clause above it matches every input; carries how many further
    -- clauses after this one are unreachable for the same reason
  | AfterClauseBindingNewName [Name] Int
    -- ^ a clause above it matches every input because its patterns are
    -- new names (the first argument, as written), such as a misspelled
    -- value; carries how many further clauses are unreachable for the same
    -- reason
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

data CheckWarning
  = PatternMatchRedundant [Branch Resolved]
  | PatternMatchesMissing [BranchLhs Resolved]
  | PatternClausesMissing SrcRange Name Int [[Pattern Resolved]]
    -- ^ A multi-clause DECIDE\/MEANS pattern-matching group does not cover
    -- all cases ('L4.TypeCheck.checkClauseMatrix'). Carries the hull of the
    -- clause-head ranges (the warning anchor — never @\<no location\>@), the
    -- group's head name for display, how many clauses it has, and one row per
    -- missing clause: one pattern per argument column, wildcard columns
    -- pre-substituted with the column's GIVEN name so the renderer is dumb.
  | PatternClauseUnreachable SrcRange Name UnreachableClause
    -- ^ A clause of a multi-clause DECIDE\/MEANS group can never be tried
    -- ('L4.TypeCheck.warnUnreachableClauses'). Carries the clause head's
    -- range, the group's head name for display, and why.
  | ClauseAnnotationUnused SrcRange Name Int Text Bool
    -- ^ An @\@desc@, @\@export@ or @\@nlg@ written between two clauses of a
    -- multi-clause group, which takes its annotations from above its first
    -- clause only ('L4.TypeCheck.checkClauseMatrix'). Carries the
    -- annotation's range, the group's head name, the later clause's number
    -- (counting from 1), the annotation as written (@\@export@, say), and
    -- whether the group has a GIVEN, which is where its @\@desc@ and
    -- @\@export@ go.
  | ClauseArityChanged SrcRange Name Int [Name]
    -- ^ A definition with no GIVEN of its own, right after a multi-clause
    -- group of the same name, that has another number of inputs than the
    -- group has patterns ('L4.TypeCheck.warnClauseArityChange'). It is not a
    -- clause of the group: it is a rule of its own, and the names after its
    -- head are its inputs. Carries the head's range, the name, the number of
    -- patterns each clause above has, and the definition's input names.
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
  | ExpectClauseInputContext RawName Int Bool
    -- ^ a clause pattern of a multi-clause group must match the type of the
    -- input it stands in for: the group's name, the input's 1-based
    -- position, and whether the GIVEN declares its type. See
    -- 'L4.TypeCheck.checkConsider'.
  | ExpectOperatorArgContext Text (Maybe Int)
    -- ^ an operand of an operator: the operator as written in the source
    -- ('L4.TypeCheck.operatorAsWritten'), and the operand's 1-based position
    -- ('Nothing' for the only operand of a prefix operator such as NOT)
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
  | ExpectAssertContext -- assertions should be Boolean
  | ExpectPostUrlContext -- URL argument of POST
  | ExpectPostHeadersContext -- headers argument of POST
  | ExpectPostBodyContext -- body argument of POST
  | ExpectConcatArgumentContext -- argument of CONCAT
  | ExpectAsStringArgumentContext -- argument of AS STRING
  | ExpectBreachReasonContext -- reason argument of BREACH
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

-- | THE canonical severity mapping for checker diagnostics — the one place
-- that decides what blocks ('SError'), what warns ('SWarn'), and what is
-- informational only ('SInfo'). Candidate viability during type-directed
-- disambiguation ('viableCandidate', used by 'prune'\/'orElse'\/'softprune')
-- and the diagnostic renderers all key off this single definition.
severity :: CheckErrorWithContext -> Severity
severity (MkCheckErrorWithContext e _) =
  case e of
    CheckInfo {}    -> SInfo
    CheckWarning {} -> SWarn
    _               -> SError

-- | Is this candidate still viable? Only 'SError'-severity diagnostics fail
-- a candidate. A warning attached along the way must NOT influence name
-- resolution: with a purely structural test (any diagnostic = failure), a
-- mere exhaustiveness warning inside one branch of a type-directed
-- disambiguation knocks out the correct candidate, and resolution collapses
-- into a spurious "multiple definitions" error.
--
-- The walk stops at the first fatal diagnostic, so rejected candidates cost
-- no more than under the old structural test whenever their first
-- diagnostic is already fatal (the common case).
viableCandidate :: With CheckErrorWithContext a -> Bool
viableCandidate = \ case
  Plain _  -> True
  With e w -> severity e /= SError && viableCandidate w

-- | The answers to @#CHECK@ directives among a module's diagnostics.
-- A @#CHECK@ is answered with a 'CheckInfo', the only 'SInfo' diagnostic.
-- The warnings beside it ('SWarn', such as a @CONSIDER@ that misses a case)
-- do not block a check either, but they answer no directive, so whatever lists
-- @#CHECK@ results, the editor's Inspector panel and its directive listing
-- among them, must leave them out.
checkDirectiveResults :: [CheckErrorWithContext] -> [CheckErrorWithContext]
checkDirectiveResults = filter isCheckResult
  where
    isCheckResult (MkCheckErrorWithContext CheckInfo {} _) = True
    isCheckResult _                                        = False

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
  rangeOf (ClausePatternCountMismatch r _ _ _) = r
  rangeOf (ExportedClausesWithoutGiven r _) = r
  rangeOf (ExportEventType r _ _)           = r
  rangeOf (CheckInfo _ mr)                  = mr
  -- The clause-head hull anchors the warning; it wins over the enclosing
  -- WhileCheckingDecide context range via @rangeOf e <|> rangeOf ctx@ above.
  rangeOf (CheckWarning (PatternClausesMissing r _ _ _)) = Just r
  rangeOf (CheckWarning (PatternClauseUnreachable r _ _)) = Just r
  rangeOf (CheckWarning (ClauseAnnotationUnused r _ _ _ _)) = Just r
  rangeOf (CheckWarning (ClauseArityChanged r _ _ _)) = Just r
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
--
-- Entries are merged with 'List.union', which keeps the first copy of an entry
-- and drops later copies equal to it. A module's registry already holds every
-- entry of its imports' registries, so merging with @++@ kept one copy per
-- import PATH: with n modules that each import every earlier one, the last
-- held 2^(n-1) copies of the first module's one mixfix function, all
-- deep-forced with the rest of its 'TypeCheckResult', and
-- 'lookupByFirstKeyword' returned the product of two such lists
-- (smucclaw\/l4-ide#1008). A 'FunTypeSig' holds its name's 'Unique', which
-- embeds the defining module, so two definitions are never equal and only a
-- copy of the same definition is dropped; 'byFirstKeyword' lists canonical
-- names, which 'lookupByFirstKeyword' resolves through 'byCanonicalName'.
-- That changes no reader:
-- 'L4.TypeCheck.tryMatchAnyPattern' (which keeps the first error),
-- 'L4.TypeCheck.tryMatchFlattenedPattern' and
-- 'L4.TypeCheck.tryMatchParamPositions' stop at the first candidate that
-- matches, a copy of an earlier candidate would have matched or failed as that
-- one did, the rest test for any candidate, and
-- 'L4.Export.Document.mixfixHeadingsFromRegistry' builds a 'Map.fromList'
-- keyed by 'Unique'.
unionMixfixRegistry :: MixfixRegistry -> MixfixRegistry -> MixfixRegistry
unionMixfixRegistry r1 r2 = MkMixfixRegistry
  { byCanonicalName = Map.unionWith List.union r1.byCanonicalName r2.byCanonicalName
  , byFirstKeyword  = Map.unionWith List.union r1.byFirstKeyword r2.byFirstKeyword
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
    , errorContext         :: !CheckErrorContext
    , sectionStack         :: ![NonEmpty Text]
    , unlessOperand        :: !(Maybe SrcRange)
    -- ^ The source range of @r@ while @l UNLESS r@ is checked. The checker
    -- reads it as @l AND (NOT r)@ ('L4.Parser.infixUnless'), so that a type
    -- error in @r@ names UNLESS rather than a NOT the author never wrote.
    }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (NFData)

-- | Extend a module's accumulated 'CheckEnv' with the public surface of one
-- imported (already type-checked) module. This is THE import-boundary merge:
-- both the batch import resolution (@L4.Import.Resolution@) and the LSP
-- build rule (@LSP.L4.Rules@) go through it, so their semantics cannot
-- drift apart again. (They once did: one site silently left-biased
-- conflicting 'entityInfo' entries, the other @assert@ed equality — an
-- assert GHC compiles out at @-O@, so the two sites merely LOOKED
-- different. The by-equality variant also paid a deep structural 'Eq' per
-- colliding key, and collisions are the norm: every dependency's
-- 'entityInfo' embeds the builtins and its own transitive imports.)
--
-- Colliding 'entityInfo' keys are unioned left-biased. This is safe
-- because a 'Unique' embeds its defining module and each module is
-- type-checked once per session, so a key arriving via two import paths
-- (builtins, diamond dependencies) always carries identical copies of the
-- same entry.
--
-- Precondition: the imported 'EntityInfo' has already been zonked (had its
-- module's final substitution applied), so no inference variables leak
-- across the boundary.
--
-- The by-'SrcRange' frame-local maps ('functionTypeSigs', 'declTypeSigs',
-- 'declareDeclarations', 'assumeDeclarations') are deliberately reset:
-- their readers only ever look up syntax nodes of the module currently
-- being checked. 'computedFields' is reset too because it is keyed by
-- 'RawName' and unioning it across modules could conflate same-named
-- record types; the cost is error-message quality only (see the notes in
-- specs/as-built/checkenv-import-merge.md).
unionImportedCheckEnv :: CheckEnv -> Environment -> EntityInfo -> MixfixRegistry -> CheckEnv
unionImportedCheckEnv accEnv depEnvironment depEntityInfo depMixfixRegistry =
  MkCheckEnv
    { moduleUri = accEnv.moduleUri
    , environment = Map.unionWith List.union accEnv.environment depEnvironment
    , entityInfo = Map.union accEnv.entityInfo depEntityInfo
    , functionTypeSigs = Map.empty
    , declTypeSigs = Map.empty
    , declareDeclarations = Map.empty
    , assumeDeclarations = Map.empty
    , mixfixRegistry = unionMixfixRegistry accEnv.mixfixRegistry depMixfixRegistry
    , computedFields = Map.empty
    , errorContext = None
    , sectionStack = []
    , unlessOperand = Nothing
    }

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

-- | Is this 'Resolved' the sentinel that 'outOfScope', 'ambiguousTerm' and
-- 'ambiguousType' mint to make progress after a name-resolution failure?
--
-- Such a sentinel is only ever created *after* the corresponding
-- 'OutOfScopeError' \/ 'AmbiguousTermError' \/ 'AmbiguousTypeError' has been
-- reported, and its 'Unique' is deliberately never registered in the
-- 'EntityInfo'. Anything we subsequently derive from it is therefore known
-- garbage, and diagnostics about that garbage are cascade, not news.
isOutOfScope :: Resolved -> Bool
isOutOfScope OutOfScope{} = True
isOutOfScope _            = False

-- | Every 'Resolved' occurring in head (type constructor \/ type variable)
-- position within a type, outermost first.
--
-- Deliberately hand-written rather than derived via @gplate@: we want exactly
-- the names the type is *built from*, not whatever 'Resolved's may additionally
-- be squirrelled away inside 'Anno' payloads.
typeHeads :: Type' Resolved -> [Resolved]
typeHeads (Type _)        = []
typeHeads (TyApp _ n ts)  = n : concatMap typeHeads ts
typeHeads (Fun _ onts t)  =
  concatMap (typeHeads . optionallyNamedTypeType) onts ++ typeHeads t
typeHeads (Forall _ _ t)  = typeHeads t
typeHeads (InfVar _ _ _)  = []

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
  case mapMaybe proc options of
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
    proc :: (Unique, Name, CheckEntity) -> Maybe (Check (Resolved, Type' Resolved))
    proc (u, o, KnownTerm t tk) | p tk = Just $ do
      n' <-  setAnnResolvedType t (Just tk) n
      pure (Ref n' u o, t)
    proc _                             = Nothing

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
setAnnResolvedType t k a = case rangeOf (getAnno a) of
  Just r -> do
    let info = TypeInfo t k
    addInfoForSrcRange r info
    pure $ a & annoOf % annInfo ?~ info
  -- A node the clause desugarer generated has no range, on purpose: it has no
  -- source to point at, and a range would put it in the position index that
  -- hover and go-to-definition search. Its type is still a fact about the
  -- node, and the ladder reads a DECIDE body's type off the node
  -- ('L4.Viz.Ladder.hasBooleanType'), so it is recorded ON the node and
  -- nowhere else: the position index and every diagnostic are as they were.
  Nothing
    | isJust (Optics.view annPmSynthetic (getAnno a)) -> do
        -- With the substitution so far applied: a group with no GIVETH is
        -- checked against a fresh type that its clauses have already fixed.
        t' <- applySubst t
        pure $ a & annoOf % annInfo ?~ TypeInfo t' k
    | otherwise -> pure a

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

-- | Look up the entity a 'Resolved' refers to.
--
-- Returns 'Nothing' for an 'OutOfScope' sentinel *without* complaining: those
-- 'Unique's are minted fresh by 'outOfScope' \/ 'ambiguousTerm' \/
-- 'ambiguousType' and are deliberately never registered in the 'EntityInfo', so
-- a miss is expected error recovery after an already-reported name-resolution
-- failure — not an invariant violation. Reporting 'MissingEntityInfo' for them
-- turned every unresolved or ambiguous name into a spurious "this is an error
-- in this system and should be reported as a bug" (issue #920).
--
-- For every other 'Resolved' a miss really is an internal invariant violation
-- ('extendEnv' registers 'environment' and 'entityInfo' together, so every
-- 'Ref' \/ 'Def' unique has an entry), and we keep reporting it. After this
-- change, 'MissingEntityInfo' means what its message claims.
getEntityInfo :: Resolved -> Check (Maybe CheckEntity)
getEntityInfo r = do
  ei <- asks (.entityInfo)
  case Map.lookup (getUnique r) ei of
    Just (_n, ce) -> pure (Just ce)
    Nothing
      | isOutOfScope r -> pure Nothing
      | otherwise      -> do
          addError (MissingEntityInfo r)
          pure Nothing

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

-- | The type 'applySubst' makes of a type, read off a snapshot of the
-- substitution. Only the path compression 'applySubst' writes back is left
-- out, and that changes no answer: it saves later lookups, and every reader
-- of the substitution chases it to the end.
--
-- For a structure that is only read, this is the cheap way to resolve the
-- types in it. 'applySubst' through 'gplate' rebuilds every node of the
-- structure inside 'Check', annotations and tokens included, and holds the
-- rebuilt nodes as closures until they are read; @'Optics.over' ('gplate'
-- \@('Type'' 'Resolved')) ('substituteInfVars' s)@ rebuilds a node when it
-- is read.
substituteInfVars :: Substitution -> Type' Resolved -> Type' Resolved
substituteInfVars s = go
  where
    go = \ case
      Type ann       -> Type ann
      TyApp ann n ts -> TyApp ann n (map go ts)
      Fun ann onts t -> Fun ann (map goNamed onts) (go t)
      Forall ann ns t -> Forall ann ns (go t)
      InfVar ann rn i -> maybe (InfVar ann rn i) go (Map.lookup i s)
    goNamed (MkOptionallyNamedType ann mn t) = MkOptionallyNamedType ann mn (go t)

instance ApplySubst CheckError where
  applySubst = traverseOf (gplate @(Type' Resolved) @CheckError) applySubst

instance ApplySubst CheckErrorContext where
  applySubst = traverseOf (gplate @(Type' Resolved) @CheckErrorContext) applySubst

-- | The context is resolved lazily ('substituteInfVars'), and only when it
-- holds a type the substitution changes ('contextChanges'); otherwise it is
-- kept as it is. It is the syntax that was being checked when the
-- diagnostic was raised, as written, so it can be a whole definition, such
-- as a CONSIDER of thousands of arms for a warning about that CONSIDER, and
-- each level of it holds the levels inside it. 'applySubst' rebuilt all of
-- it, for each diagnostic raised inside it, whether anything read it or
-- not; rebuilt lazily, it is still rebuilt in full where the diagnostics
-- are forced, as the language server's rules force them, and a copy per
-- level made a CONSIDER nested 600 deep, warned about at the innermost
-- level, peak at 520 MB. Kept, it is shared.
instance ApplySubst CheckErrorWithContext where
  applySubst (MkCheckErrorWithContext e ctx) = do
    e' <- applySubst e
    s <- use #substitution
    let ctx'
          | contextChanges s ctx = Optics.over (gplate @(Type' Resolved)) (substituteInfVars s) ctx
          | otherwise = ctx
    pure (MkCheckErrorWithContext e' ctx')

-- | Whether 'substituteInfVars' changes a type in this context. A context is
-- syntax as written, over 'Name's, so a 'Type'' 'Resolved' can only sit in
-- an annotation's extras (its 'resolvedInfo', or the names of a resolved
-- annotation); each annotation's extras are searched, and the syntax around
-- them is walked only as far as its annotations, never into their tokens,
-- which are most of it.
contextChanges :: Substitution -> CheckErrorContext -> Bool
contextChanges s =
  Optics.anyOf (gplate @Anno) \ (a :: Anno) ->
    Optics.anyOf (gplate @(Type' Resolved) @Extension) (substitutionChanges s) (Optics.view annoExtra a)

-- | Whether 'substituteInfVars' changes this type: whether it mentions an
-- inference variable the substitution binds.
substitutionChanges :: Substitution -> Type' Resolved -> Bool
substitutionChanges s = go
  where
    go = \ case
      Type _         -> False
      TyApp _ _ ts   -> any go ts
      Fun _ onts t   -> any (go . optionallyNamedTypeType) onts || go t
      Forall _ _ t   -> go t
      InfVar _ _ i   -> Map.member i s

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
    in
      case filter (viableCandidate . fst) candidates of
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

      proc []       = [] -- should never occur
      proc [a]      = [a]
      proc (a : cs)
        | viableCandidate (fst a) = procViable a cs
        | otherwise               = procFailed a cs

      -- We have a (possibly warning-carrying) success, we don't want a second one
      procViable a []       = [a]
      procViable a (c : cs)
        | viableCandidate (fst c) =
            if all (viableCandidate . fst) cs
              then [first (With (MkCheckErrorWithContext InternalAmbiguityError ctx)) a]
              -- NOTE: in the case of ambiguity errors, the ambiguity error will always occur as
              -- the last element in the list
              else [last (c : cs)]
        | otherwise = procViable a cs

      -- We have a failure, we're still looking for a success, and prefer the last failure
      procFailed a []       = [a]
      procFailed _ (c : cs)
        | viableCandidate (fst c) = procViable c cs
        | otherwise               = procFailed c cs

    in
      proc candidates

-- | Prune to one result if there's a clearly best one at this point,
-- but don't force it.
--
softprune :: forall a. Check a -> Check a
softprune m = do
  MkCheck $ \ s env ->
    let
      candidates :: [(With CheckErrorWithContext a, CheckState)]
      candidates = runCheck m s env

      proc []       = [] -- should never occur
      proc [a]      = [a]
      proc (a : cs)
        | viableCandidate (fst a) = procViable a cs
        | otherwise               = procFailed a cs

      -- We have a success, we don't want a second one
      procViable a []       = [a]
      procViable a (c : cs)
        | viableCandidate (fst c) = candidates
        | otherwise               = procViable a cs

      -- We have a failure, we're still looking for a success, and prefer the last failure
      procFailed a []       = [a]
      procFailed _ (c : cs)
        | viableCandidate (fst c) = procViable c cs
        | otherwise               = procFailed c cs

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

-- | Make many 'CheckInfo's known for the given scope.
extendKnownMany :: [CheckInfo] -> Check a -> Check a
extendKnownMany cis = do
  local (extendEnv cis)

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
    , sectionStack = e.sectionStack
    , unlessOperand = e.unlessOperand
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
