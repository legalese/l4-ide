-- | L4's typed functional core → the relational normal form of
-- "L4.Relational.IR".
--
-- The pipeline, in the order it runs (@m1-design\/lower-plan.md@ §2):
--
-- > Module Resolved
-- >   ├─ buildCtx        ── ontology: records, payload-free enums, ASSUMEd types,
-- >   │                     top-level DECIDEs, and the ASSUMEd names that are callable
-- >   ├─ selectRoots     ── getExportedFunctions + enrichReturnTypes + enrichParamTypes
-- >   ├─ reachable       ── transitive closure over called DECIDEs (helpers)
-- >   ├─ per definition:  lowerSpec
-- >   │     ├─ carameliseExpr    ── undo the typechecker's operator desugaring
-- >   │     ├─ peelLocals        ── WHERE\/LET lambda-lifted, NOT inlined
-- >   │     ├─ expandRows        ── normaliseGuarded → rows + materialised prefixes
-- >   │     ├─ toBForm\/dnf       ── NOT pushed to literals, then DNF (+ aux factoring)
-- >   │     └─ anfTerm\/anfAtom   ── goals in bind-before-use order
-- >   ├─ lowerQueries    ── #EVAL \/ #ASSERT → RQuery + flattened RFacts
-- >   ├─ inputPreds      ── the stored fields a projection reached  ─┐ both RInput,
-- >   ├─ assumedInputPreds ── the ASSUMEs a clause called           ─┘ see 'RInput'
-- >   ├─ buildDepGraph   ── signed edges
-- >   └─ stratify        ── Apt–Blair–Walker, RECORDED not enforced
--
-- Four API notes that are decisions rather than details:
--
-- * __'lowerModule' takes an 'EntityInfo', which the sibling backends do not.__
--   @L4.OpenFisca.Lower.lowerModule@ and @L4.Docassemble.Lower.lowerModule@ both
--   have the shape @Module Resolved -> Either [LowerError] a@ and therefore
--   cannot call @L4.Export.enrichReturnTypes@ \/ @enrichParamTypes@, which need
--   type-checker output ('EntityInfo' is reachable only as
--   @TypeCheckWithDepsResult.tcdEntityInfo@). OpenFisca papers over the gap by
--   defaulting an unknown numeric type. The relational leg cannot: the Blawx
--   emitter declares an attribute's value type in its ontology and has nothing
--   to infer it from, so a @MEANS@-style definition with no @GIVETH@ would ship
--   a guessed sort. It is not 'Maybe' — a caller with nothing to supply passes
--   'mempty' and gets 'RSOpaque' plus a fidelity note, which is visible.
--
-- * __'LowerError' lives in "L4.Relational.IR", not here__, unlike both
--   precedents. The emitters are second consumers that must pattern-match on
--   'LowerErrorKind' for their own diagnostics, and an emitter importing this
--   module purely for an error type would drag the whole lowering into its
--   dependency cone.
--
-- * __Operators are caramelised first.__ The typechecker desugars every infix
--   operator into an application of a builtin (@a + b@ → @App __PLUS__ [a,b]@);
--   @L4.Desugar.carameliseExpr@ undoes that, so this module matches 'Plus',
--   'Geq', 'And' … as constructors and keeps no second copy of
--   @L4.Desugar.builtinBinFunctions@. (A residual @App@ of an unsaturated
--   builtin is left to the ordinary call path, where it is rejected by name.)
--
-- * __Boolean-valued predicates drop their output argument.__ @eligible(A)@,
--   not @eligible(A, true)@ — which is what makes 'RNotCall' expressible at
--   all, since a goal that binds an output cannot be negated. 'rpResult' is
--   'Nothing' for exactly those predicates.
module L4.Relational.Lower
  ( lowerModule
  , LowerOptions (..)
  , defaultLowerOptions
    -- * Reusable pieces
    --
    -- | Exported for @jl4-core-test@\'s @RelationalSpec@, which checks the
    -- signed-edge and stratification laws directly. A spec that restated those
    -- algorithms would test its own copy and drift silently, so the real
    -- functions are exposed instead.
  , buildDepGraph
  , stratify
  ) where

import Base
import Control.Applicative ((<|>))
import Data.Graph (SCC (..), stronglyConnComp)
import qualified Base.Map as Map
import qualified Base.Set as Set
import qualified Base.Text as Text

import Optics ((%), (^.), cosmosOf, foldMapOf, gplate)

import L4.Annotation (emptyAnno, getAnno, rangeOf)
import L4.Desugar (carameliseExpr)
import L4.Export
  ( ExportedFunction (..)
  , ExportedParam (..)
  , enrichParamTypes
  , enrichReturnTypes
  , getExportedFunctions
  )
import L4.Interchange.Fidelity
  (FidelityNote (..), FidelityReport (..), FidelitySeverity (..), emptyReport)
import L4.Nlg (simpleLinearizer)
import L4.Parser.SrcSpan (SrcRange)
import L4.Relational.IR
import L4.Syntax
import L4.TypeCheck.Environment
  ( booleanUnique
  , dateUnique
  , emptyUnique
  , listUnique
  , maybeUnique
  , numberUnique
  , stringUnique
  )
import L4.TypeCheck.Types (CheckEntity (..), EntityInfo)
import L4.Viz.GuardedRows (GuardedRows (..), hasEffectfulNode, literalBool, normaliseGuarded)

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------

-- | The knobs an emitter may legitimately vary. Everything else about the
-- lowering is fixed, because a target-specific lowering is how one IR stops
-- serving four targets.
data LowerOptions = MkLowerOptions
  { loDnfThreshold :: !Int
    -- ^ Above this many disjuncts, factor a nested disjunction into an
    -- 'RAuxiliary' predicate instead of distributing (IR constraint 4). The
    -- anti-blowup valve; BLAWX-EXPORT-SPEC leaves the number's home undecided,
    -- so it lives here.
  , loMaxArity :: !(Maybe Int)
    -- ^ An arity ceiling, above which a predicate is 'LEArity'. __Off by
    -- default, and that is a ruling rather than an oversight.__ The only leg
    -- with a ceiling is Blawx (its relationship arity); swipl, ASP, Logical
    -- English and PROLEG have none. A middle-end that batch-rejected a module
    -- for one target's limit would refuse programs the other three could emit
    -- perfectly well — the same mistake 'RStratification' exists not to make
    -- (recorded here, rejected in each emitter, "L4.Relational.IR"). Blawx's
    -- emitter sets it, or checks the arity itself; nothing else pays.
    --
    -- Counted arity is the head's, plus one for a non-'Nothing' 'rpResult'. Note
    -- that @L4.Export.buildExportedFunction@ appends @ASSUME@-derived parameters
    -- to an /export's/ parameter list, which is not the same list as the
    -- definition's own binders — a lowered decision's head is its binders alone,
    -- and a referenced @ASSUME@ becomes its own 'RInput' predicate ('RInput',
    -- 'assumedInputPreds') rather than an extra argument, so those never reach
    -- the count. An 'RInput' predicate is not checked against the ceiling at
    -- all — neither the field-derived nor the @ASSUME@-derived kind goes
    -- through 'lowerSpec', which is where the check lives. The only leg with a
    -- ceiling counts arity itself, over every predicate including the inputs
    -- (@L4.Blawx.Lower.classifyPred@), so nothing is unchecked in practice.
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

defaultLowerOptions :: LowerOptions
defaultLowerOptions = MkLowerOptions
  { loDnfThreshold = 8
  , loMaxArity     = Nothing
  }

-- ---------------------------------------------------------------------------
-- The lowering monad
-- ---------------------------------------------------------------------------

-- | Errors accumulate ACROSS definitions and abort WITHIN one: a module with
-- four out-of-fragment definitions reports four diagnostics, in source order.
-- That is OpenFisca's batch shape (@partitionEithers@ over per-decision
-- results), expressed as 'ExceptT' over 'State' so that the fresh-variable
-- counter and the auxiliary-predicate list survive a definition that failed.
type L a = ExceptT LowerError (State LState) a

data LState = MkLState
  { lsFresh  :: !Int
  , lsErrs   :: ![LowerError]
  , lsNotes  :: ![FidelityNote]
  , lsAux    :: ![RPred]
  , lsUri    :: !NormalizedUri
  , lsMember :: !(Maybe RName)
    -- ^ the synthesised list-membership generator, minted at most once per
    -- module (see 'memberPred').
  }

-- | Run one definition; on failure record the diagnostic and carry on.
attempt :: L a -> State LState (Maybe a)
attempt act = do
  r <- runExceptT act
  case r of
    Left e  -> do modify' (\s -> s { lsErrs = s.lsErrs <> [e] }); pure Nothing
    Right a -> pure (Just a)

freshVar :: Text -> L RVar
freshVar hint = do
  n <- gets (.lsFresh)
  modify' (\s -> s { lsFresh = n + 1 })
  pure MkRVar { rvId = n, rvHint = hint }

-- | A 'Unique' for a predicate this module synthesises (a DNF factoring). The
-- @sort@ character is the collision-avoidance mechanism 'Unique' was given for
-- this purpose: @\'b\'@ is the builtin environment, @\'c\'@ the type checker,
-- @\'e\'@ the evaluator, and @\'x\'@ is ours.
freshUnique :: L Unique
freshUnique = do
  n <- gets (.lsFresh)
  uri <- gets (.lsUri)
  modify' (\s -> s { lsFresh = n + 1 })
  pure MkUnique { sort = 'x', unique = n, moduleUri = uri }

note :: FidelityNote -> L ()
note n = modify' (\s -> s { lsNotes = s.lsNotes <> [n] })

emitAux :: RPred -> L ()
emitAux p = modify' (\s -> s { lsAux = s.lsAux <> [p] })

-- ---------------------------------------------------------------------------
-- Names
-- ---------------------------------------------------------------------------

rName :: Resolved -> RName
rName r = MkRName
  { rnText   = rawNameToText (rawName (getOriginal r))
  , rnBase   = unqualifiedNameToText (getOriginal r)
  , rnUnique = getUnique r
  }

-- ---------------------------------------------------------------------------
-- Context: the module's ontology and its callable signatures
-- ---------------------------------------------------------------------------

-- | What a call site needs to know about its callee.
data CallSig = MkCallSig
  { csName :: !RName
  , csPre  :: ![Unique]
    -- ^ The enclosing binders a lambda-lifted helper takes as leading
    -- arguments, __as binders and not as terms__, resolved through 'leVars' at
    -- each call site by 'preArgs'.
    --
    -- Storing the parent's /variables/ here instead was wrong in one place and
    -- right everywhere else, which is why it survived: a call from the parent's
    -- own body does want the parent's variables, but a call from INSIDE the
    -- helper — a sibling call, or the helper's own recursion — is being lowered
    -- under the helper's head, whose outer parameters are fresh variables. Those
    -- clauses came out passing variables their head never bound:
    -- @go(Xs_13, Floor_14, [Y|Rest], T) :- go(Xs_11, Floor_12, Rest, G)@, which
    -- is well-typed, prints plausibly, and is a different program.
  , csBool :: !Bool     -- ^ boolean-valued: the output argument is dropped
  }

-- | A top-level @DECIDE@, normalised to the shape the lowering wants.
data TopDef = MkTopDef
  { tdRes      :: !Resolved
  , tdParams   :: ![Resolved]
  , tdParamTys :: ![Maybe (Type' Resolved)]
  , tdResultTy :: !(Maybe (Type' Resolved))
  , tdBody     :: !(Expr Resolved)
  , tdExported :: !Bool
  , tdDesc     :: !(Maybe Text)
  , tdNlg      :: !(Maybe Text)
  , tdRef      :: !(Maybe Text)
  , tdRange    :: !(Maybe SrcRange)
  }

-- | A top-level @ASSUME@ of a /term/, normalised to the predicate it becomes.
--
-- @ASSUME T IS A TYPE@ does not produce one of these: a type is a sort, not a
-- callable name, and it lives in 'ctxAbstract' \/ 'seAbstract' instead.
--
-- __The admit\/refuse judgement is made here, at the declaration__ ('adRefusal'
-- carries it), not at the first use. That is the same discipline
-- 'checkFragmentSorts' follows for a @DECIDE@ and for the same reason: the
-- range a reader needs is the signature's, and the same @ASSUME@ may be
-- referenced from four places.
data AssumeDef = MkAssumeDef
  { adName    :: !RName
  , adParams  :: ![RSort]
  , adResult  :: !(Maybe RSort)   -- ^ 'Nothing' = boolean, output arg dropped
  , adDesc    :: !(Maybe Text)
  , adNlg     :: !(Maybe Text)
  , adRef     :: !(Maybe Text)
  , adRange   :: !(Maybe SrcRange)
  , adTypically :: !Bool
    -- ^ whether a @TYPICALLY@ default was written. The value itself is
    -- deliberately not read (BLAWX-EXPORT-SPEC §5.1 puts @TYPICALLY@ OUT,
    -- dropped with a note): an input predicate is a fact the target asks about,
    -- and silently seeding it with a default would answer a question the
    -- interview was supposed to ask. Recorded so 'assemble' can emit the note.
  , adRefusal :: !(Maybe (LowerErrorKind, Text))
    -- ^ 'Nothing' = admitted (it gets a 'CallSig' and may become an 'RInput');
    -- 'Just' = out of fragment, and a reference to it fails with exactly this.
  }

-- | The /only/ thing 'sortOfType' needs from the module: which type uniques
-- name a record, which name a payload-free enum, and which name an @ASSUME@d
-- (abstract) type.
--
-- __It is a separate type so that it can be built without 'Ctx', and that is
-- load-bearing.__ Every field of 'Ctx' is strict, so forcing a 'Ctx' to WHNF
-- forces all of them; a 'sortOfType' that reached into @ctx.ctxRecords@ while
-- @ctx.ctxFields@ was still being built forced the very 'Ctx' under
-- construction, and the thread blocked on its own blackhole — no exception, no
-- CPU, just a hang. It fired only for a record field whose type is another
-- record (@items IS A LIST OF Item@), because every other field type short-
-- circuits on a builtin unique before the lookup. Do not re-thread 'Ctx' through
-- 'sortOfType'.
data SortEnv = MkSortEnv
  { seRecords  :: !(Map Unique RName)
  , seEnums    :: !(Map Unique RName)
  , seAbstract :: !(Map Unique RName)
    -- ^ @ASSUME T IS A TYPE@. Sorted as 'RSRecord' (see its haddock: the
    -- constructor means \"a category named /n/\", not \"a declared record\"),
    -- so no downstream consumer gains a case — the alternative, a new 'RSort'
    -- constructor, would add an arm to every match in Lower, Debug and both
    -- Blawx modules, and would be silently wrong in any that carries a
    -- catch-all.
  }

data Ctx = MkCtx
  { ctxSorts   :: !SortEnv
  , ctxRecords :: !(Map Unique RRecordDef)
  , ctxEnums   :: !(Map Unique REnumDef)
  , ctxRecOrder :: ![Unique]
    -- ^ record type uniques in SOURCE DECLARATION order, and 'ctxEnumOrder' the
    -- same for enums.
    --
    -- Every list a golden prints has to be ordered by something the source
    -- fixes. @Map.elems@ over a 'Unique'-keyed map is ordered by the type
    -- checker's counter instead: reproducible for a fixed tree, so no golden
    -- flaps today, but not source order — inserting a declaration earlier in a
    -- file could permute the @records:@ and @input@ blocks of an unrelated
    -- golden, and the diff would look like a lowering change. Keeping the
    -- declaration order explicitly is cheaper than explaining that later.
  , ctxEnumOrder :: ![Unique]
  , ctxFields  :: !(Map Unique RFieldDef)      -- ^ field unique → its declaration
  , ctxRecCon  :: !(Map Unique Unique)         -- ^ record CONSTRUCTOR unique → record type unique
  , ctxCons    :: !(Map Unique (RName, Int))   -- ^ enum constructor unique → (enum type, arity)
  , ctxTop     :: ![TopDef]                    -- ^ declaration order
  , ctxTopByU  :: !(Map Unique TopDef)
  , ctxAssumeDefs :: !(Map Unique AssumeDef)
    -- ^ Top-level @ASSUME@d terms, admitted or refused ('AssumeDef'). An
    -- admitted one has a 'ctxSigs' entry and is reached as an ordinary call; a
    -- refused one is reached only by 'anfTerm' \'s residue arm, which reports
    -- 'adRefusal' — so a narrowing never surfaces as \"unbound reference\",
    -- which would send the reader looking for a typo, an import or a recursion,
    -- three places the answer is not.
  , ctxAssumeOrder :: ![Unique]
    -- ^ source declaration order for 'ctxAssumeDefs' and 'ctxAbstract'
    -- respectively — see 'ctxRecOrder' for why a 'Unique'-keyed iteration must
    -- not reach a golden.
  , ctxAbstract :: !(Map Unique RAbstractDef)   -- ^ @ASSUME T IS A TYPE@
  , ctxAbstractOrder :: ![Unique]
  , ctxSigs    :: !(Map Unique CallSig)
  , ctxEnt     :: !EntityInfo
  }

-- | The per-definition lowering environment.
--
-- Named 'LEnv' rather than @Env@ on purpose: @Env@ is an 'Expr' constructor
-- (an environment-variable lookup), and @-Wall@ + @-Werror@ turns the shadow
-- into a build failure rather than a warning.
data LEnv = MkLEnv
  { leVars   :: !(Map Unique RVar)
  , leSubst  :: !(Map Unique RTerm)
    -- ^ Binders that stand for a /term/ rather than a variable, which is what a
    -- structurally decomposed head argument is: in the base clause of
    -- @CONSIDER l WHEN EMPTY … WHEN x FOLLOWED BY xs …@ the scrutinee @l@ /is/
    -- @[]@, and in the step clause it /is/ @[X|Xs]@ — both are the head term, not
    -- a variable the head binds. Consulted before 'leVars', which is where an
    -- ordinary parameter lives.
    --
    -- A name in here cannot be threaded into a lambda-lifted @WHERE@ helper (a
    -- helper takes variables), so it is deliberately absent from 'leParams' and a
    -- local that references the decomposed scrutinee is reported as unbound
    -- rather than silently passed an unbound variable.
  , leParams :: ![(Unique, Text, RSort)]  -- ^ this definition's full parameter list
  , leCalls  :: !(Map Unique CallSig)     -- ^ lambda-lifted locals in scope
  , leFn     :: !Text                     -- ^ for 'errFn'
  , leOpts   :: !LowerOptions
    -- ^ carried rather than passed, because 'anfTerm' can reach a @WHERE@ that
    -- 'expandRows' did not peel (one nested inside an operand) and must lift it
    -- under the SAME options; a default reinstated at that one call site would
    -- honour a caller\'s threshold everywhere except the deepest position.
  }

bailIn :: LEnv -> Maybe SrcRange -> LowerErrorKind -> Text -> L a
bailIn env r k m = throwError MkLowerError
  { errFn = env.leFn, errRange = r, errKind = k, errMsg = m }

-- | The record a 'Unique' denotes, whether it is the type's or its
-- constructor's.
recordOf :: Ctx -> Unique -> Maybe RRecordDef
recordOf ctx u =
  Map.lookup u ctx.ctxRecords
    <|> (Map.lookup u ctx.ctxRecCon >>= \ru -> Map.lookup ru ctx.ctxRecords)

lookupCall :: Ctx -> LEnv -> Unique -> Maybe CallSig
lookupCall ctx env u = Map.lookup u env.leCalls <|> Map.lookup u ctx.ctxSigs

-- | The leading arguments of a call to a lambda-lifted helper, resolved __in the
-- calling environment__ (see 'csPre').
--
-- A binder that is not a variable here is one the caller cannot pass: the only
-- way to reach that is a structurally decomposed scrutinee, which stands for a
-- head TERM and is deliberately kept out of 'leParams' ('leSubst'), so it is
-- also kept out of 'csPre'. Reporting it beats passing something unbound.
preArgs :: LEnv -> Maybe SrcRange -> CallSig -> L [RTerm]
preArgs env rng sig = traverse look sig.csPre
 where
  look u = case Map.lookup u env.leVars of
    Just v  -> pure (RTVar v)
    Nothing ->
      bailIn env rng LEUnbound
        ( "`" <> sig.csName.rnBase <> "` is a local helper that needs an enclosing binder"
            <> " which is not a variable at this call site" )

-- ---------------------------------------------------------------------------
-- Sorts
-- ---------------------------------------------------------------------------

entType :: EntityInfo -> Unique -> Maybe (Type' Resolved)
entType ei u = case Map.lookup u ei of
  Just (_, KnownTerm ty _) -> Just ty
  _                        -> Nothing

-- | The result type of a definition, from its @GIVETH@ or from the checker's
-- inferred function type.
entResultType :: EntityInfo -> Unique -> Maybe (Type' Resolved)
entResultType ei u = case entType ei u of
  Just (Fun _ _ ret) -> Just ret
  other              -> other

sortOfType :: SortEnv -> Maybe (Type' Resolved) -> RSort
sortOfType _  Nothing   = RSOpaque "no declared or inferred type"
sortOfType se (Just ty) = case ty of
  TyApp _ n []
    | u == booleanUnique -> RSBool
    | u == numberUnique  -> RSNum
    | u == stringUnique  -> RSString
    | u == dateUnique    -> dateSort
    | Just r <- Map.lookup u se.seRecords -> RSRecord r
    | Just e <- Map.lookup u se.seEnums   -> RSEnum e
    -- LAST among the lookups, and after every builtin guard above: a module
    -- that ASSUMEs a name a DECLARE also binds must resolve to the declaration,
    -- and an ASSUMEd name spelled like a builtin must resolve to the builtin.
    | Just a <- Map.lookup u se.seAbstract -> RSRecord a
    | otherwise          -> RSOpaque (nameText n)
   where u = getUnique n
  TyApp _ n [t]
    | getUnique n == listUnique  -> RSList (sortOfType se (Just t))
    | getUnique n == maybeUnique -> RSMaybe (sortOfType se (Just t))
  TyApp _ n args -> RSOpaque (nameText n <> (if null args then "" else " OF …"))
  Fun{}    -> RSOpaque "FUNCTION"
  Forall{} -> RSOpaque "∀"
  InfVar{} -> RSOpaque "unsolved inference variable"
  Type{}   -> RSOpaque "TYPE"
 where
  nameText = rawNameToText . rawName . getOriginal

-- | Dates are M2 (see @DATE-LIBRARY-SPEC.md@), so there is no 'RSort' for one.
-- They are carried as this specific opaque marker and rejected on the way in by
-- 'checkFragmentSorts', which is why the two must agree — hence one constant.
dateSort :: RSort
dateSort = RSOpaque "DATE"

isBoolSort :: RSort -> Bool
isBoolSort = \case RSBool -> True; _ -> False

-- | Reject a signature the M1 fragment does not admit. Runs on the way IN, so
-- the diagnostic names the type rather than whatever the first date-shaped
-- expression happened to be.
checkFragmentSorts :: LEnv -> Maybe SrcRange -> [RSort] -> L ()
checkFragmentSorts env rng = mapM_ go
 where
  go s = forM_ (fragmentSortError s) \(k, m) -> bailIn env rng k m

-- | The table behind 'checkFragmentSorts', as a pure function, because the
-- @ASSUME@ admission pass ('assumeDefs') has to make the same judgement outside
-- the lowering monad. One table, so the two cannot disagree about what the
-- fragment admits — and an @ASSUME@ rejected here is rejected with its own
-- range, not the first use's.
fragmentSortError :: RSort -> Maybe (LowerErrorKind, Text)
fragmentSortError s
  | s == dateSort =
      Just ( LEDate
           , "date-valued parameters and results are M2 (see specs/todo/DATE-LIBRARY-SPEC.md)" )
fragmentSortError (RSMaybe _) =
  Just ( LEMaybe
       , "a MAYBE-valued parameter or result is outside the M1 fragment" )
fragmentSortError (RSList inner) = fragmentSortError inner
fragmentSortError _ = Nothing

-- ---------------------------------------------------------------------------
-- Scanning the module
-- ---------------------------------------------------------------------------

topDecls :: Module Resolved -> [TopDecl Resolved]
topDecls (MkModule _ _ sec) = goSection sec
 where
  goSection (MkSection _ _ _ decls) = concatMap goDecl decls
  goDecl d = case d of
    Section _ sub -> d : goSection sub
    _             -> [d]

moduleTitleOf :: Module Resolved -> Maybe Text
moduleTitleOf (MkModule _ _ (MkSection _ mName _ decls)) =
  listToMaybe
    ( [ nm n | Just n <- [mName] ]
        <> [ nm n | Section _ (MkSection _ (Just n) _ _) <- decls ]
    )
 where nm = rawNameToText . rawName . getOriginal

moduleSourceOf :: Module Resolved -> Text
moduleSourceOf (MkModule _ uri _) =
  let t = getUri (fromNormalizedUri uri)
  in case reverse (Text.splitOn "/" t) of
       (base : _) | not (Text.null base) -> base
       _                                 -> t

-- | A decision's parameters and its effective body. The @GIVEN@ signature is
-- authoritative when present (the app-form arguments refer to the same
-- bindings); a parameterless definition whose body is a @GIVEN … YIELD@ lambda
-- is unwrapped into a function. Same shape as
-- @L4.Docassemble.Lower.decideFunShape@, which is private to that module.
decideFunShape :: Decide Resolved -> ([Resolved], Expr Resolved)
decideFunShape (MkDecide _ (MkTypeSig _ (MkGivenSig _ givens) _) (MkAppForm _ _ appArgs _) body0) =
  let ps0 = if null givens then appArgs else map givenName givens
  in case (ps0, body0) of
       ([], Lam _ (MkGivenSig _ lps) lbody) -> (map givenName lps, lbody)
       _                                    -> (ps0, body0)

givenName :: OptionallyTypedName Resolved -> Resolved
givenName (MkOptionallyTypedName _ r _ _) = r

givenType :: OptionallyTypedName Resolved -> Maybe (Type' Resolved)
givenType (MkOptionallyTypedName _ _ mty _) = mty

decideRes :: Decide Resolved -> Resolved
decideRes (MkDecide _ _ (MkAppForm _ r _ _) _) = r

decideGiveth :: Decide Resolved -> Maybe (Type' Resolved)
decideGiveth (MkDecide _ (MkTypeSig _ _ mg) _ _) = (\(MkGivethSig _ t) -> t) <$> mg

decideGivens :: Decide Resolved -> [OptionallyTypedName Resolved]
decideGivens (MkDecide _ (MkTypeSig _ (MkGivenSig _ gs) _) _ _) = gs

descOf :: Decide Resolved -> Maybe Text
descOf d = descFromAnno (getAnno d)

descFromAnno :: Anno -> Maybe Text
descFromAnno ann = do
  desc <- ann ^. annDesc
  let t = Text.strip (stripKeywords (getDesc desc))
  if Text.null t then Nothing else Just t
 where
  -- @export / @default / @nonexhaustive are flags, not prose; L4.Export
  -- consumes them the same way (parseDescText) but does not expose the result
  -- for a non-exported definition.
  stripKeywords t =
    let cur = Text.stripStart t
        (tok, rest) = Text.break (== ' ') cur
    in if Text.toLower tok `elem` (["export", "default", "nonexhaustive"] :: [Text])
         then stripKeywords rest
         else cur

-- | An @\@nlg@ annotation as one line of text, with each @%parameter%@ slot
-- rendered as the bare parameter name.
--
-- __A resolved annotation is NOT put through @simpleLinearizer@__, and the
-- reason is a measured one rather than a preference: that function linearises a
-- @MkNlgRef@ by linearising the /name/, which re-expands that name's own
-- @\@nlg@ — and an @\@nlg@ commonly lands on a parameter it also mentions
-- (@\`loyalty bonus\` m \@nlg the bonus earned by %m%@ attaches to @m@), so the
-- sentence came out containing itself: \"the bonus earned by the bonus earned by
-- \`m\`\". @L4.Export.Document.renderNlgWith@ (@Document.hs:331-343@) avoids it
-- the same way and records the same reason.
--
-- Only whitespace is normalised beyond that. The sentence is the author's, and
-- an emitter that wants it re-cased or re-punctuated for its own @#pred@ syntax
-- is the layer that knows how; @Document.hs@'s larger prose cleanup is not
-- borrowed, because borrowing it would make two unrelated outputs move together.
linearNlg :: Nlg -> Text
linearNlg = \case
  MkResolvedNlg _ frags -> squash (Text.concat (map frag frags))
  other                 -> squash (simpleLinearizer other)
 where
  squash = Text.unwords . Text.words
  frag = \case
    MkNlgText _ t -> t
    MkNlgRef  _ r -> rawNameToText (rawName (getActual r))

-- | The @\@nlg@ attached to a @DECIDE@, __wherever it landed__.
--
-- Authors place it differently for @MEANS@ (where it attaches to an appform
-- argument) and for @DECIDE … IF@ (where it attaches to the head name), so all
-- of the declaration's annotation-bearing positions are searched. Same positions
-- and same order as @L4.Export.Document.decideNlg@ (@Document.hs:301-310@),
-- which is private to that module and whose comment records that the list was
-- arrived at by measurement rather than by reading the grammar — plus the
-- enclosing @TopDecl@\'s own annotation, where an annotation written above the
-- declaration lands and where @L4.Dmn.Lower@ looks first (@Dmn\/Lower.hs:3754@).
-- Measured on @jl4\/examples\/relational\/tiers.l4@: a @\@ref@ written on the
-- line above @GIVEN@ is found /only/ there.
decideNlg :: Anno -> Decide Resolved -> Maybe Nlg
decideNlg outer (MkDecide decAnno (MkTypeSig _ (MkGivenSig _ names) _) (MkAppForm afAnno headName appArgs _) body) =
  foldr (<|>) Nothing $
       [ outer ^. annNlg
       , decAnno ^. annNlg
       , afAnno ^. annNlg
       , body ^. annoOf % annNlg
       , getOriginal headName ^. annoOf % annNlg
       ]
    <> [ getOriginal a ^. annoOf % annNlg | a <- appArgs ]
    <> [ getOriginal r ^. annoOf % annNlg | MkOptionallyTypedName _ r _ _ <- names ]

-- | The citation itself, without its herald.
--
-- @getRef@ returns the annotation's line as the lexer kept it — @\@ref@ included
-- — because the exact printer has to reprint it byte for byte. Every /reader/
-- wants the citation, and the same trap has already been paid for once on the
-- @\@desc@ side (@L4.Syntax.getDesc@'s comment: the untrimmed separator reached
-- JSON Schema descriptions, the deployed function schema and hovers before
-- anyone noticed). Strip it here, once.
refText :: Ref -> Text
refText r =
  let t = Text.strip (getRef r)
  in Text.strip (fromMaybe t (Text.stripPrefix "@ref" t))

-- | The @\@ref@ citation attached to a @DECIDE@, searched in the same positions
-- as 'decideNlg' for the same reason.
decideRef :: Anno -> Decide Resolved -> Maybe Ref
decideRef outer (MkDecide decAnno (MkTypeSig _ (MkGivenSig _ names) _) (MkAppForm afAnno headName _ _) body) =
  foldr (<|>) Nothing $
       [ outer ^. annRef
       , decAnno ^. annRef
       , afAnno ^. annRef
       , body ^. annoOf % annRef
       , getOriginal headName ^. annoOf % annRef
       ]
    <> [ getOriginal r ^. annoOf % annRef | MkOptionallyTypedName _ r _ _ <- names ]

mkTopDef :: EntityInfo -> Map Unique ExportedFunction -> Anno -> Decide Resolved -> TopDef
mkTopDef ei exps outer d =
  let res       = decideRes d
      u         = getUnique res
      (ps, body) = decideFunShape d
      givens    = decideGivens d
      mEf       = Map.lookup u exps
      -- the enriched types L4.Export computed for an @export decision, by
      -- position. NOTE: exportParams has ASSUME-derived parameters appended
      -- after the GIVEN ones (Export.hs buildExportedFunction), so only the
      -- leading @length ps@ entries line up with our binders.
      efTys     = maybe [] (map (.paramType) . (.exportParams)) mEf
      byGiven r = listToMaybe [ t | g <- givens, getUnique (givenName g) == getUnique r
                                  , Just t <- [givenType g] ]
      paramTy i r = byGiven r <|> join (efTys !!? i) <|> entType ei (getUnique r)
  in MkTopDef
       { tdRes      = res
       , tdParams   = ps
       , tdParamTys = zipWith paramTy [0 ..] ps
       , tdResultTy = decideGiveth d <|> (mEf >>= (.exportReturnType)) <|> entResultType ei u
       , tdBody     = carameliseExpr body
       , tdExported = isJust mEf
       , tdDesc     = descOf d
       , tdNlg      = linearNlg <$> decideNlg outer d
       , tdRef      = refText <$> decideRef outer d
       , tdRange    = rangeOf d
       }

(!!?) :: [a] -> Int -> Maybe a
xs !!? i = case drop i xs of (a : _) -> Just a; [] -> Nothing

-- | Every annotation-bearing position of an @ASSUME@, in the order a lookup
-- should try them — the outer 'TopDecl' anno first (where an annotation written
-- above the declaration lands), then the declaration's own, then its app form's,
-- then the head name's. Same list and same reason as 'decideNlg': arrived at by
-- measurement, not by reading the grammar.
assumeAnnos :: Anno -> Assume Resolved -> [Anno]
assumeAnnos outer (MkAssume aAnno _ (MkAppForm afAnno hd _ _) _ _) =
  [ outer, aAnno, afAnno, getOriginal hd ^. annoOf ]

-- | An @ASSUME@d term, normalised — including the judgement about whether the
-- M1 fragment admits it ('adRefusal').
--
-- __Both spellings of an @ASSUME@d predicate are admitted, and they are not
-- interchangeable upstream.__
--
-- > ASSUME `is authorised` IS A FUNCTION FROM Person TO BOOLEAN   -- (1)
-- >
-- > GIVEN p IS A Person                                           -- (2)
-- > ASSUME `is authorised` p IS A BOOLEAN
--
-- (1) declares the arrow, which this function flattens along its spine:
-- @FUNCTION FROM A AND B TO BOOLEAN@ and @FUNCTION FROM A TO FUNCTION FROM B TO
-- BOOLEAN@ both give @[A, B]@ parameters and a boolean result. (2) binds the
-- parameters in the app form and types them in the @GIVEN@ signature, which is
-- authoritative; the declared type is then the /result/ alone. Both reach the
-- same 'AssumeDef', and a mixture (app-form binders plus an arrow result) is
-- flattened in that order.
--
-- __Spelling (2) is the one an @\@export@ed module can use__, and that is worth
-- knowing before writing a corpus: @L4.Export.validateExportInputs@ makes a
-- /function-typed/ @ASSUME@ referenced by an @\@export@ed @DECIDE@ a type
-- error (@ExportFunctionTypeInput@ — a function cannot cross the web app's
-- JSON boundary), and the relational lowering is export-rooted, so a module
-- written entirely in spelling (1) has no root to lower from. Spelling (2)'s
-- declared type is @BOOLEAN@, not an arrow, so it passes.
--
-- The 'LEHigherOrder' refusal below is deliberately the complement of
-- @L4.Export.assumesFromModule@\'s filter, which __drops__ function-typed
-- @ASSUME@s: an @ASSUME@ of a function is a /predicate/ here and a
-- non-representable form field there. A reader who finds only one of the two
-- will otherwise conclude the other is a bug.
assumeDef :: SortEnv -> EntityInfo -> Anno -> Assume Resolved -> AssumeDef
assumeDef se ei outer a@(MkAssume _ (MkTypeSig _ (MkGivenSig _ givens) _) (MkAppForm _ res args _) mty mDefault) =
  MkAssumeDef
    { adName    = rName res
    , adParams  = paramSorts
    , adResult  = if isBoolSort resultSort then Nothing else Just resultSort
    , adDesc    = listToMaybe (mapMaybe descFromAnno annos)
    , adNlg     = linearNlg <$> listToMaybe (mapMaybe (^. annNlg) annos)
    , adRef     = refText <$> listToMaybe (mapMaybe (^. annRef) annos)
    , adRange   = rangeOf a
    , adTypically = isJust mDefault
    , adRefusal = refusal
    }
 where
  annos = assumeAnnos outer a

  -- With app-form binders the declared type is the RESULT, so the checker's
  -- inferred type must not be consulted as a fallback: it is the whole arrow,
  -- and its spine would count every binder twice.
  declared
    | null args = mty <|> entType ei (getUnique res)
    | otherwise = mty

  -- The GIVEN signature types the binders, as it does for a DECIDE ('mkTopDef').
  bndrTy r = listToMaybe [ t | g <- givens, getUnique (givenName g) == getUnique r
                             , Just t <- [givenType g] ]
               <|> entType ei (getUnique r)
  bndrTys = map bndrTy args

  (spineTys, resultTy) = maybe ([], Nothing) (second Just . spine) declared
  spine = \case
    Fun _ onts ret -> let (ps, r) = spine ret in ([ t | MkOptionallyNamedType _ _ t <- onts ] <> ps, r)
    t              -> ([], t)
  paramSorts = map (sortOfType se) bndrTys <> map (sortOfType se . Just) spineTys
  resultSort = sortOfType se resultTy

  refusal = listToMaybe $ concat
    [ [ ( LEUnsupported "ASSUME without a declared signature"
        , "`" <> (rName res).rnBase <> "` has no declared or inferred type, so there is no\
          \ signature to give the input predicate it would become" )
      | isNothing declared ]
      -- `ASSUME T x IS A TYPE` — a type CONSTRUCTOR. Its nullary sibling is a
      -- category ('assumesCategory'); this one sorts nothing, because
      -- 'sortOfType' has no application form for it.
    , [ ( LEUnsupported "ASSUMEd TYPE constructor"
        , "`" <> (rName res).rnBase <> "` is an ASSUMEd type constructor; only a nullary\
          \ ASSUMEd TYPE becomes a category, and neither is a term" )
      | resultSort == RSOpaque "TYPE" ]
    , [ ( LEHigherOrder
        , "`" <> (rName res).rnBase <> "` takes a function-typed parameter; the relational\
          \ middle end is first-order Horn, so an ASSUMEd predicate's parameters must be\
          \ values" )
      | any isFunTy (catMaybes bndrTys <> spineTys) ]
    , [ e | Just e <- [listToMaybe (mapMaybe fragmentSortError (paramSorts <> [resultSort]))] ]
    ]
  isFunTy = \case Fun{} -> True; Forall _ _ t -> isFunTy t; _ -> False

-- | Whether an @ASSUME@ declares a category rather than a term: @ASSUME T IS A
-- TYPE@, and only in its nullary spelling. @ASSUME T x IS A TYPE@ is a
-- parameterised type constructor, which has no category image (Blawx categories
-- take no arguments) and is left to the ordinary refusal path.
assumesCategory :: Assume Resolved -> Bool
assumesCategory (MkAssume _ _ (MkAppForm _ _ args _) mty _) =
  null args && case mty of Just Type{} -> True; _ -> False

buildCtx :: EntityInfo -> Map Unique ExportedFunction -> Module Resolved -> Ctx
buildCtx ei exps m = ctx
 where
  decls = topDecls m

  recPairs =
    [ (getUnique recRes, (recRes, mcon, fields, rangeOf dc))
    | Declare _ dc@(MkDeclare _ _ (MkAppForm _ recRes _ _) (RecordDecl _ mcon fields)) <- decls
    ]

  enumPairs =
    [ (getUnique tyRes, (tyRes, cons, rangeOf dc))
    | Declare _ dc@(MkDeclare _ _ (MkAppForm _ tyRes _ _) (EnumDecl _ cons)) <- decls
    ]

  -- Only STORED fields survive: L4.Desugar.desugarComputedFields strips a
  -- @MEANS@ field out of the RecordDecl before type checking and synthesises a
  -- top-level selector, so a projection onto a computed field is an ordinary
  -- call and a "record has no such field" branch for one is dead code.
  storedFields fields = [ (fAnn, fRes, fTy) | MkTypedName fAnn fRes fTy _ Nothing <- fields ]

  assumeDecls = [ (ann, a) | Assume ann a <- decls ]

  -- ASSUME T IS A TYPE: a category with no fields ('RAbstractDef').
  abstractPairs =
    [ (getUnique r, rName r, rangeOf a)
    | (_, a@(MkAssume _ _ (MkAppForm _ r _ _) _ _)) <- assumeDecls
    , assumesCategory a
    ]

  -- Everything else an ASSUME can be: a term, admitted or refused.
  assumeDefPairs =
    [ (getUnique r, assumeDef sortEnv ei ann a)
    | (ann, a@(MkAssume _ _ (MkAppForm _ r _ _) _ _)) <- assumeDecls
    , not (assumesCategory a)
    ]

  -- Built from the declaration lists ALONE, with no reference to 'ctx'. See the
  -- 'SortEnv' haddock: routing this through 'ctx' deadlocks the moment a record
  -- field's type is another record. ('assumeDefPairs' reads it, and is in 'ctx'
  -- — the dependency runs one way only.)
  sortEnv = MkSortEnv
    { seRecords  = Map.fromList [ (u, rName recRes) | (u, (recRes, _, _, _)) <- recPairs ]
    , seEnums    = Map.fromList [ (u, rName tyRes)  | (u, (tyRes, _, _)) <- enumPairs ]
    , seAbstract = Map.fromList [ (u, n) | (u, n, _) <- abstractPairs ]
    }

  ctx = MkCtx
    { ctxSorts   = sortEnv
    , ctxRecords = Map.fromList
        [ ( u
          , MkRRecordDef
              { rrName   = rName recRes
              , rrFields = [ fieldDef fAnn fRes fTy | (fAnn, fRes, fTy) <- storedFields fields ]
              , rrProv   = MkRProv { rpvUnique = u, rpvRange = rng }
              }
          )
        | (u, (recRes, _, fields, rng)) <- recPairs
        ]
    , ctxEnums = Map.fromList
        [ ( u
          , MkREnumDef
              { reName = rName tyRes
              , reCons = [ rName c | MkConDecl _ c _ <- cons ]
              , reProv = MkRProv { rpvUnique = u, rpvRange = rng }
              }
          )
        | (u, (tyRes, cons, rng)) <- enumPairs
        ]
    , ctxRecOrder = map fst recPairs
    , ctxEnumOrder = map fst enumPairs
    , ctxFields = Map.fromList
        [ (getUnique fRes, fieldDef fAnn fRes fTy)
        | (_, (_, _, fields, _)) <- recPairs
        , (fAnn, fRes, fTy) <- storedFields fields
        ]
    , ctxRecCon = Map.fromList
        -- After type checking a RecordDecl carries its CONSTRUCTOR name, whose
        -- Unique differs from the type's: a record literal in a query
        -- (@Applicant WITH age IS 70@) resolves to the constructor, so a lookup
        -- keyed only by the type unique silently fails to recognise it.
        [ (getUnique con, u) | (u, (_, Just con, _, _)) <- recPairs ]
    , ctxCons = Map.fromList
        [ (getUnique c, (rName tyRes, length cargs))
        | (_, (tyRes, cons, _)) <- enumPairs
        , MkConDecl _ c cargs <- cons
        ]
    , ctxTop    = tops
    , ctxTopByU = Map.fromList [ (getUnique td.tdRes, td) | td <- tops ]
    , ctxAssumeDefs = Map.fromList assumeDefPairs
    , ctxAssumeOrder = map fst assumeDefPairs
    , ctxAbstract = Map.fromList
        [ ( u
          , MkRAbstractDef { raName = n, raProv = MkRProv { rpvUnique = u, rpvRange = rng } }
          )
        | (u, n, rng) <- abstractPairs
        ]
    , ctxAbstractOrder = [ u | (u, _, _) <- abstractPairs ]
    , ctxSigs   = Map.fromList
        (  [ ( getUnique td.tdRes
             , MkCallSig
                 { csName = rName td.tdRes
                 , csPre  = []
                 , csBool = isBoolSort (sortOfType sortEnv td.tdResultTy)
                 }
             )
           | td <- tops
           ]
        -- An admitted ASSUME is callable, which is the whole widening: with an
        -- entry here 'lookupCall' resolves a reference to it and 'anfPred' /
        -- 'anfTerm' emit an ordinary call, exactly as for a DECIDE. The map is
        -- keyed by 'Unique', so a DECIDE and an ASSUME spelled alike cannot
        -- collide here — the reference's own resolution already picked one.
        <> [ ( u
             , MkCallSig { csName = ad.adName, csPre = [], csBool = isNothing ad.adResult }
             )
           | (u, ad) <- assumeDefPairs
           , isNothing ad.adRefusal
           ]
        )
    , ctxEnt = ei
    }

  fieldDef fAnn fRes fTy = MkRFieldDef
    { rfName = rName fRes
    , rfSort = sortOfType sortEnv (Just fTy)
    , rfDesc = getDesc <$> (fAnn ^. annDesc)
    , rfNlg  = linearNlg <$> ((fAnn ^. annNlg) <|> (getOriginal fRes ^. annoOf % annNlg))
    }

  tops = [ mkTopDef ei exps ann d | Decide ann d <- decls ]

-- ---------------------------------------------------------------------------
-- Reachability
-- ---------------------------------------------------------------------------

-- | Every identifier an expression references, as a plain variable, an applied
-- function, or a projected field. Projection heads matter because a computed
-- (@MEANS@) record field arrives as a 'Proj' whose field name resolves to the
-- desugar-synthesised selector decide — a top-level function that must be
-- walked like any other callee.
collectRefs :: Expr Resolved -> Set Unique
collectRefs =
  foldMapOf (cosmosOf (gplate @(Expr Resolved))) \case
    App _ r _  -> Set.singleton (getUnique r)
    Proj _ _ f -> Set.singleton (getUnique f)
    _          -> Set.empty

-- | The transitive closure of 'collectRefs' over top-level definitions.
--
-- __Transitive is the point.__ A decide referenced only from inside another
-- helper's body is still reachable; a direct-bodies-only walk drops it, which is
-- a confirmed defect in a sibling bridge.
closureRefs :: Ctx -> Set Unique -> Set Unique
closureRefs ctx = go Set.empty . Set.toList
 where
  go seen [] = seen
  go seen (u : us)
    | u `Set.member` seen = go seen us
    | Just td <- Map.lookup u ctx.ctxTopByU =
        go (Set.insert u seen) (Set.toList (collectRefs td.tdBody) <> us)
    | otherwise = go seen us

-- ---------------------------------------------------------------------------
-- Boolean normal form
-- ---------------------------------------------------------------------------

-- | An atom of the boolean structure, after @NOT@ has been pushed all the way
-- down. There is no negation constructor above this level: a negated comparison
-- was complemented ('complementCmp'), a negated conjunction was De Morgan'd, and
-- what is left is a polarity flag on a predicate-shaped atom.
data BAtomP
  = APCmp !RCmpOp !(Expr Resolved) !(Expr Resolved)
    -- ^ the operator is already the one to emit
  | APMatch !(Expr Resolved) !Resolved
    -- ^ @CONSIDER@ discrimination against a payload-free constructor
  | APExpr !Bool !(Expr Resolved)
    -- ^ polarity + a predicate-shaped atom (a call, a projected boolean, a
    -- boolean parameter)
  | APGoals ![RGoal]
    -- ^ already lowered — how DNF factoring re-enters the pipeline

-- | Boolean structure with negation eliminated. 'BTrue' \/ 'BFalse' exist so
-- that @literalBool@ collapses and inert scaffolding can be erased without a
-- separate simplification pass.
data BForm = BTrue | BFalse | BAtom !BAtomP | BAnd !BForm !BForm | BOr !BForm !BForm

bAnd :: BForm -> BForm -> BForm
bAnd BFalse _ = BFalse
bAnd _ BFalse = BFalse
bAnd BTrue b  = b
bAnd a BTrue  = a
bAnd a b      = BAnd a b

bOr :: BForm -> BForm -> BForm
bOr BTrue _  = BTrue
bOr _ BTrue  = BTrue
bOr BFalse b = b
bOr a BFalse = a
bOr a b      = BOr a b

bBool :: Bool -> BForm
bBool True  = BTrue
bBool False = BFalse

-- | Push @NOT@ to the literals. The first argument is \"we want the negation of
-- this expression\".
--
-- __Boolean structure is the ONLY thing normalised here.__ Arithmetic operand
-- order and association are never touched: date addition is neither commutative
-- nor associative (portfolio invariant I9), so a reassociating pass built here
-- would be silently unusable the moment M2 admits dates — and its output would
-- still typecheck.
toBForm :: Ctx -> LEnv -> Bool -> Expr Resolved -> L BForm
toBForm ctx _env = go
 where
  go neg e
    | Just b <- literalBool e = pure (bBool (if neg then not b else b))
  go neg e = case e of
    And _ a b     -> (if neg then liftA2 bOr else liftA2 bAnd) (go neg a) (go neg b)
    Or  _ a b     -> (if neg then liftA2 bAnd else liftA2 bOr) (go neg a) (go neg b)
    Not _ a       -> go (not neg) a
    -- a ⇒ b ≡ ¬a ∨ b; ¬(a ⇒ b) ≡ a ∧ ¬b
    Implies _ a b ->
      if neg then liftA2 bAnd (go False a) (go True b)
             else liftA2 bOr  (go True a)  (go False b)
    Lt  _ a b -> cmp neg RLt  a b
    Leq _ a b -> cmp neg RLeq a b
    Gt  _ a b -> cmp neg RGt  a b
    Geq _ a b -> cmp neg RGeq a b
    Equals _ a b
      -- @normaliseGuarded@ renders a CONSIDER row as an equality against a
      -- constructor application; recognising that shape here is what produces
      -- 'RMatch' without reimplementing the normaliser (risks.md §8).
      | not neg
      , App _ c [] <- b
      , Just (_, 0) <- Map.lookup (getUnique c) ctx.ctxCons ->
          pure (BAtom (APMatch a c))
      | otherwise -> cmp neg REq a b
    -- Inert scaffolding evaluates to its containing operator's identity; the
    -- context was annotated by carameliseExprWithContext. Without this the
    -- whole inert-style corpus is out of fragment.
    Inert _ _ ictx -> pure (bBool (applyNeg neg (inertIdentity ictx)))
    -- A guarded chain nested inside boolean structure. The top-level case is
    -- split into clauses by 'expandRows'; here the chain has to become a
    -- formula, by the same law (GuardedRows.hs:229-240).
    _ | Just gr <- normaliseGuarded e -> guardedForm neg gr
    _ -> pure (BAtom (APExpr (not neg) e))

  cmp neg op a b = pure (BAtom (APCmp (if neg then complementCmp op else op) a b))

  applyNeg neg b = if neg then not b else b

  inertIdentity = \case
    InertCtxAnd  -> True
    InertCtxOr   -> False
    InertCtxNone -> True

  -- ⋁ᵢ ( ⋀_{j<i} ¬gⱼ ∧ gᵢ ∧ bᵢ )  ⋁  ( ⋀_{j≤n} ¬gⱼ ∧ b₀ ).
  -- Note the asymmetry: grDisjoint removes the negated PREFIX from a row, but
  -- NEVER the OTHERWISE branch's ⋀ ¬gⱼ.
  guardedForm neg gr = do
    let gs = map fst gr.grRows
    rows <- forM (zip [0 :: Int ..] gr.grRows) \(i, (g, b)) -> do
      pfx <- if gr.grDisjoint then pure BTrue
                              else foldM (\acc j -> bAnd acc <$> go True (gs !! j)) BTrue [0 .. i - 1]
      gf <- go False g
      bf <- go False b
      pure (pfx `bAnd` gf `bAnd` bf)
    oth <- case gr.grOtherwise of
      Nothing -> pure BFalse
      Just b0 -> do
        allNeg <- foldM (\acc g -> bAnd acc <$> go True g) BTrue gs
        bf <- go False b0
        pure (allNeg `bAnd` bf)
    let positive = foldr bOr BFalse (rows <> [oth])
    if neg then negForm positive else pure positive

  -- Negating an already-built formula: only reachable for a nested guarded
  -- chain under a NOT, where re-walking the source is not possible.
  negForm = \case
    BTrue    -> pure BFalse
    BFalse   -> pure BTrue
    BAnd a b -> bOr <$> negForm a <*> negForm b
    BOr a b  -> bAnd <$> negForm a <*> negForm b
    BAtom a  -> pure (BAtom (negAtom a))

  negAtom = \case
    APCmp op x y  -> APCmp (complementCmp op) x y
    APMatch x c   -> APCmp RNeq x (App emptyAnno c [])
    APExpr p x    -> APExpr (not p) x
    APGoals gs    -> APGoals gs  -- unreachable: factoring runs after negation

-- | Disjunctive normal form. Deliberately naive: the anti-blowup valve is
-- 'factorDnf', not a cleverer distribution.
dnf :: BForm -> [[BAtomP]]
dnf = \case
  BTrue    -> [[]]
  BFalse   -> []
  BAtom a  -> [[a]]
  BAnd a b -> [ x <> y | x <- dnf a, y <- dnf b ]
  BOr a b  -> dnf a <> dnf b

-- | Find a disjunction sitting under a conjunction, with a rebuilder. Hoisting
-- one such subterm turns a multiplication of disjuncts into an addition.
findFactor :: BForm -> Maybe (BForm, BForm -> BForm)
findFactor = \case
  BAnd a b -> case a of
    BOr{} -> Just (a, \r -> BAnd r b)
    _ -> case findFactor a of
      Just (s, rb) -> Just (s, \r -> BAnd (rb r) b)
      Nothing -> case b of
        BOr{} -> Just (b, \r -> BAnd a r)
        _     -> (\(s, rb) -> (s, \r -> BAnd a (rb r))) <$> findFactor b
  BOr a b -> case findFactor a of
    Just (s, rb) -> Just (s, \r -> BOr (rb r) b)
    Nothing      -> (\(s, rb) -> (s, \r -> BOr a (rb r))) <$> findFactor b
  _ -> Nothing

-- | Every source binder an atom mentions.
atomRefs :: BAtomP -> Set Unique
atomRefs = \case
  APCmp _ a b -> collectRefs a <> collectRefs b
  APMatch a _ -> collectRefs a
  APExpr _ a  -> collectRefs a
  APGoals _   -> Set.empty

formRefs :: BForm -> Set Unique
formRefs = \case
  BTrue    -> Set.empty
  BFalse   -> Set.empty
  BAtom a  -> atomRefs a
  BAnd a b -> formRefs a <> formRefs b
  BOr a b  -> formRefs b <> formRefs a

-- | DNF with the anti-blowup valve. Above 'loDnfThreshold' disjuncts, hoist a
-- nested disjunction into a fresh 'RAuxiliary' predicate — one clause per
-- disjunct of the hoisted subterm — and re-run.
factorDnf :: Ctx -> LowerOptions -> LEnv -> BForm -> L [[BAtomP]]
factorDnf ctx opts env = loop (0 :: Int)
 where
  loop depth f
    | length (dnf f) <= opts.loDnfThreshold || depth > 16 = pure (dnf f)
    | otherwise = case findFactor f of
        -- An already-hoisted subterm is never hoisted again. 'atomRefs' reports
        -- no free binders for 'APGoals' (its goals are lowered, and mention
        -- 'RVar's rather than 'Unique's), so a second hoist would build an
        -- auxiliary whose head does not bind the variables its body needs and
        -- 'anfAtom' would re-emit them verbatim. No formula in the corpus
        -- selects such a subterm — 'findFactor' takes the outermost 'BOr' — but
        -- the pair of definitions is what would have to stay true, so the
        -- invariant is enforced here instead of assumed.
        Just (sub, rebuild) | not (hasGoals sub) -> do
          g <- hoist sub
          loop (depth + 1) (rebuild (BAtom (APGoals [g])))
        _ -> pure (dnf f)

  hasGoals = \case
    BAtom (APGoals _) -> True
    BAnd a b          -> hasGoals a || hasGoals b
    BOr a b           -> hasGoals a || hasGoals b
    _                 -> False

  hoist sub = do
    let free = formRefs sub
        args = [ (u, v, s) | (u, _, s) <- env.leParams
                           , u `Set.member` free
                           , Just v <- [Map.lookup u env.leVars] ]
    u <- freshUnique
    let nm = MkRName { rnText = env.leFn <> " (disjunction)", rnBase = "disjunction", rnUnique = u }
    -- The auxiliary gets its OWN head variables; the call site passes the
    -- parent's.
    inner <- traverse (\(pu, _, s) -> (\v -> (pu, v, s)) <$> freshVar "Arg") args
    let auxEnv = env
          { leVars   = Map.fromList [ (pu, v) | (pu, v, _) <- inner ]
          -- Deliberately dropped: a structurally decomposed scrutinee is a head
          -- TERM, and only variables can be passed to the auxiliary. Carrying
          -- the substitution across would render a term whose variables the
          -- auxiliary's head never binds; dropping it reports the reference as
          -- unbound instead.
          , leSubst  = mempty
          , leParams = [ (pu, "Arg", s) | (pu, _, s) <- inner ]
          }
    alts <- factorDnf ctx opts auxEnv sub
    clauses <- forM alts \as -> do
      goals <- concat <$> traverse (anfAtom ctx auxEnv) as
      pure MkRClause
        { rcHead        = [ RTVar v | (_, v, _) <- inner ]
        , rcBody        = goals
        , rcGuardPrefix = 0
        , rcProv        = MkRProv { rpvUnique = u, rpvRange = Nothing }
        }
    emitAux MkRPred
      { rpName      = nm
      , rpKind      = RAuxiliary
      , rpParams    = [ s | (_, _, s) <- inner ]
      , rpResult    = Nothing
      , rpRecursion = RNonRecursive
      , rpClauses   = clauses
      , rpExported  = False
      , rpDesc      = Just "factored out of a disjunction above the DNF threshold"
      , rpNlg       = Nothing
      , rpRef       = Nothing
      , rpProv      = MkRProv { rpvUnique = u, rpvRange = Nothing }
      }
    note MkFidelityNote
      { code     = "R-DNF"
      , severity = Advisory
      , element  = env.leFn
      , range    = Nothing
      , message  = "a disjunction was factored into an auxiliary predicate to keep the clause count bounded"
      , lost     = "the one-clause-per-source-disjunct correspondence for this subterm"
      }
    pure (RCall nm [ RTVar v | (_, v, _) <- args ])

-- ---------------------------------------------------------------------------
-- Rows: guarded chains, expanded with materialised prefixes
-- ---------------------------------------------------------------------------

-- | One row of the definition, before DNF and ANF. The 'Bool' on a condition is
-- its polarity: 'False' means the condition is the /negation/ of a source guard,
-- which is what a materialised prefix is made of.
data Row = MkRow
  { rowPrefix :: ![(Bool, Expr Resolved)]
  , rowGuards :: ![(Bool, Expr Resolved)]
  , rowValue  :: !(Expr Resolved)
  , rowEnv    :: !LEnv
  , rowProv   :: !RProv
  }

-- | Expand a definition body into rows.
--
-- @BRANCH@ arm /i/ carries the negations of guards 1../i−1/ (materialised, not
-- implied by clause position — clause order is not semantics across four
-- targets, and in ASP it is nothing at all), and the @OTHERWISE@ arm carries the
-- negations of /all/ of them regardless of disjointness. That asymmetry is the
-- one thing in this function to test directly.
expandRows :: Ctx -> LowerOptions -> LEnv -> RProv -> Expr Resolved -> L [Row]
expandRows ctx opts env0 prov0 e0 = do
  (env, e) <- peelLocals ctx opts env0 e0
  when (hasEffectfulNode e) $
    bailIn env (rangeOf e) LEEffect
      "a guard performs I/O (FETCH/POST); expanding it into clauses would change how often the effect runs"
  case normaliseGuarded e of
    Nothing -> pure [ MkRow [] [] e env (provAt prov0 e) ]
    Just gr -> do
      let gs = map fst gr.grRows
      rows <- forM (zip [0 :: Int ..] gr.grRows) \(i, (g, b)) -> do
        let pfx = if gr.grDisjoint then [] else [ (False, gs !! j) | j <- [0 .. i - 1] ]
        sub <- expandRows ctx opts env (provAt prov0 b) b
        pure [ r { rowPrefix = pfx <> r.rowPrefix
                 , rowGuards = (True, g) : r.rowGuards
                 } | r <- sub ]
      oth <- case gr.grOtherwise of
        Nothing -> pure []
        Just b0 -> do
          sub <- expandRows ctx opts env (provAt prov0 b0) b0
          pure [ r { rowPrefix = [ (False, g) | g <- gs ] <> r.rowPrefix } | r <- sub ]
      pure (concat rows <> oth)
 where
  -- Provenance comes from the ARM, never from the guard: a guard synthesised by
  -- GuardedRows.considerRows carries emptyAnno and has no range at all, so a
  -- range taken from it would be Nothing for the whole CONSIDER family — and a
  -- Nothing range reads as a legitimate absence, which makes the loss invisible.
  provAt p ex = p { rpvRange = rangeOf ex <|> p.rpvRange }

-- | @WHERE@ \/ @LET@ bindings are __lambda-lifted, not inlined__: one predicate
-- per helper, under its source name and 'Unique', with the enclosing parameters
-- threaded as leading arguments.
--
-- The DMN exporter inlines them, and says why (its decisions are globally named
-- where L4's locals are lexically scoped, so hoisting invites collisions).
-- Hoisting is right here only because 'RName' identity is the 'Unique' and not
-- the text: two @WHERE bonus@ helpers in two decisions become two predicates
-- with one spelling, and each emitter disambiguates in its own lexical class.
-- Never inline a named local — the name is the citation hook.
peelLocals :: Ctx -> LowerOptions -> LEnv -> Expr Resolved -> L (LEnv, Expr Resolved)
peelLocals ctx opts env = \case
  Where _ body decls -> do env' <- liftAll decls; peelLocals ctx opts env' body
  LetIn _ decls body -> do env' <- liftAll decls; peelLocals ctx opts env' body
  e                  -> pure (env, e)
 where
  liftAll decls = do
    ds <- traverse localDecide decls
    -- Two passes: register every sibling's signature first, so a local may
    -- reference a later one in the same block.
    let sigs = Map.fromList
          [ ( getUnique (decideRes d)
            , MkCallSig
                { csName = rName (decideRes d)
                , csPre  = [ u | (u, _, _) <- env.leParams ]
                , csBool = isBoolSort (localResultSort d)
                }
            )
          | (_, d) <- ds
          ]
        env' = env { leCalls = env.leCalls <> sigs }
    forM_ ds \(lann, d) -> do
      let (ps, body) = decideFunShape d
          givens = decideGivens d
          ownTy r = listToMaybe [ t | g <- givens, getUnique (givenName g) == getUnique r
                                    , Just t <- [givenType g] ]
                      <|> entType ctx.ctxEnt (getUnique r)
          rs = localResultSort d
      aux <- lowerSpec ctx opts MkDefSpec
        { dsName     = rName (decideRes d)
        , dsKind     = RAuxiliary
        , dsOuter    = [ (u, h, s) | (u, h, s) <- env.leParams ]
        , dsParams   = [ (getUnique r, hintOf r, sortOfType ctx.ctxSorts (ownTy r)) | r <- ps ]
        , dsResult   = if isBoolSort rs then Nothing else Just rs
        , dsBody     = carameliseExpr body
        , dsCalls    = env'.leCalls
        , dsExported = False
        , dsDesc     = descOf d
        , dsNlg      = linearNlg <$> decideNlg lann d
        , dsRef      = refText <$> decideRef lann d
        , dsProv     = MkRProv { rpvUnique = getUnique (decideRes d), rpvRange = rangeOf d }
        }
      emitAux aux
    pure env'

  localResultSort d =
    sortOfType ctx.ctxSorts (decideGiveth d <|> entResultType ctx.ctxEnt (getUnique (decideRes d)))

  localDecide = \case
    LocalDecide lann d -> pure (lann, d)
    LocalAssume _ a ->
      bailIn env (rangeOf a) (LEUnsupported "local ASSUME")
        "a local ASSUME has no relational image: unlike a top-level one — which \
        \becomes an input predicate a target can declare and abduce — it is scoped \
        \to a single definition, so there is no module-level name to declare and \
        \nothing for an interview to ask about"

hintOf :: Resolved -> Text
hintOf = unqualifiedNameToText . getOriginal

-- ---------------------------------------------------------------------------
-- ANF
-- ---------------------------------------------------------------------------

-- | Lower an expression to a term, plus the goals that must precede it.
-- Bind-before-use holds by construction, because every caller concatenates the
-- goals in the order returned.
anfTerm :: Ctx -> LEnv -> Expr Resolved -> L ([RGoal], RTerm)
anfTerm ctx env e0 = case e0 of
  Lit _ (NumericLit _ r) -> pure ([], RTNum r)
  Lit _ (StringLit _ t)  -> pure ([], RTStr t)
  Percent{}   -> arith
  Plus{}      -> arith
  Minus{}     -> arith
  Times{}     -> arith
  DividedBy{} -> arith
  Modulo{}    -> arith
  List _ es -> do
    parts <- traverse (anfTerm ctx env) es
    pure (concatMap fst parts, rTermList (map snd parts))
  Cons _ h t -> do
    (gh, th) <- anfTerm ctx env h
    (gt, tt) <- anfTerm ctx env t
    pure (gh <> gt, RTCons th tt)
  Proj _ inner f -> do
    (gs, ti) <- anfTerm ctx env inner
    let fu = getUnique f
    case Map.lookup fu ctx.ctxFields of
      Just fd -> do
        v <- freshVar (hintOf f)
        pure (gs <> [RProj ti fd.rfName v], RTVar v)
      Nothing
        -- A computed (@MEANS@) field is not a field any more: the desugarer
        -- replaced it with a top-level selector before type checking, so this
        -- is an ordinary predicate call — including the boolean output-argument
        -- drop, which makes a BOOLEAN selector unrepresentable in value
        -- position, exactly as for a named call below. Appending an output
        -- variable here instead would emit an arity that the selector's
        -- declaration (rpResult = Nothing) does not have.
        | Just sig <- lookupCall ctx env fu ->
            if sig.csBool
              then bailIn env (rangeOf e0) (LEUnsupported "boolean-valued call in value position")
                     ( "`" <> sig.csName.rnBase
                         <> "` is a computed BOOLEAN field; its selector's output argument is"
                         <> " dropped, so it cannot denote a value here" )
              else do
                pre <- preArgs env (rangeOf e0) sig
                v <- freshVar (hintOf f)
                pure (gs <> [RCall sig.csName (pre <> [ti, RTVar v])], RTVar v)
        | otherwise ->
            bailIn env (rangeOf e0) LEUnbound
              ("no field or selector for `" <> hintOf f <> "`")
  Where{}  -> peelThen
  LetIn{}  -> peelThen
  App _ r args
    | Just b <- boolConst r -> pure ([], RTBool b)
    | Just v <- Map.lookup (getUnique r) env.leVars, null args -> pure ([], RTVar v)
    -- A structurally decomposed scrutinee stands for the HEAD term, not for a
    -- variable the head binds: in the base clause @l@ is @[]@ and in the step
    -- clause it is @[X|Xs]@.
    | Just t <- Map.lookup (getUnique r) env.leSubst, null args -> pure ([], t)
    -- EMPTY is a builtin list constructor, not one of the module's own enum
    -- constructors, so it reaches none of the ctxCons cases below. Without this
    -- it lowers as an unbound reference, and an `#EVAL f EMPTY` is silently
    -- dropped from the differential harness.
    | getUnique r == emptyUnique, null args -> pure ([], RTNil)
    | Just (_, 0) <- Map.lookup (getUnique r) ctx.ctxCons, null args ->
        pure ([], RTAtom (rName r))
    | Just (_, n) <- Map.lookup (getUnique r) ctx.ctxCons, n > 0 ->
        bailIn env (rangeOf e0) LEEnumPayload
          ( "`" <> hintOf r <> "` carries a payload; M1 admits payload-free constructors only" )
    | Just sig <- lookupCall ctx env (getUnique r) ->
        if sig.csBool
          then bailIn env (rangeOf e0) (LEUnsupported "boolean-valued call in value position")
                 ( "`" <> sig.csName.rnBase
                     <> "` is a boolean predicate whose output argument is dropped, so it cannot"
                     <> " denote a value here" )
          else do
            pre <- preArgs env (rangeOf e0) sig
            parts <- traverse (anfTerm ctx env) args
            v <- freshVar (sig.csName.rnBase)
            pure ( concatMap fst parts
                     <> [RCall sig.csName (pre <> map snd parts <> [RTVar v])]
                 , RTVar v )
    -- Recognised AFTER the ordinary call path, so a module that defines its own
    -- `sum` shadows the prelude's rather than being silently re-interpreted.
    | Just op <- aggHead r, [lst] <- args -> do
        rejectMaybeOverload ctx env r (rangeOf e0)
        lowerAggregate ctx env op lst
    | nafEliminator (hintOf r) ->
        bailIn env (rangeOf e0) LEMaybe
          ( "`" <> hintOf r
              <> "` is a negation-as-failure eliminator; its relational encoding is #258 LP-R3, still open" )
    | mapCombinator (hintOf r) ->
        bailIn env (rangeOf e0) LEHigherOrder
          ( "`" <> hintOf r
              <> "` is admitted only directly inside a recognised aggregate, where its lambda"
              <> " becomes the findall template" )
    | higherOrderCombinator (hintOf r) ->
        bailIn env (rangeOf e0) LEHigherOrder
          ( "`" <> hintOf r
              <> "` takes a function argument; M1 recognises no combinator beyond the aggregates"
              <> " (sum/count/minimum/maximum) and `map` directly inside one" )
    | firstOrderCombinator (hintOf r) ->
        bailIn env (rangeOf e0) (LEUnsupported "prelude list combinator")
          ( "`" <> hintOf r <> "` is a prelude list combinator with no relational image in M1" )
    -- The RESIDUE of the ASSUME widening. An admitted ASSUME never arrives
    -- here: it has a 'ctxSigs' entry, so 'lookupCall' above resolved it into an
    -- ordinary call. What is left is the ASSUMEs the fragment refused, each
    -- reported with the reason recorded at the DECLARATION and that
    -- declaration's range — one @ASSUME@ may be referenced from four places,
    -- and the range a reader needs is the signature's.
    | Just ad <- Map.lookup (getUnique r) ctx.ctxAssumeDefs
    , Just (kind, msg) <- ad.adRefusal ->
        bailIn env (ad.adRange <|> rangeOf e0) kind msg
    | Just ab <- Map.lookup (getUnique r) ctx.ctxAbstract ->
        bailIn env (rangeOf e0) (LEUnsupported "ASSUMEd TYPE in value position")
          ( "`" <> ab.raName.rnBase <> "` is an ASSUMEd TYPE — a category, which sorts values"
              <> " but is not one; it can be a parameter's type, never a term" )
    | otherwise -> bailIn env (rangeOf e0) LEUnbound (unboundMsg r)
  AppNamed _ r _ _
    | isJust (recordOf ctx (getUnique r)) ->
        bailIn env (rangeOf e0) (LEUnsupported "record literal in a rule body")
          "a record literal is admitted only as a query input, where it flattens to facts"
  _ -> bailIn env (rangeOf e0) (kindOfExpr e0) (msgOfExpr e0)
 where
  arith = do
    (gs, a) <- anfArith ctx env e0
    case a of
      -- The whole expression already reduced to a bound variable — which is what
      -- the composite average idiom does, since 'RAggregate' binds its own
      -- output. Emitting `Tmp is Average` on top of that would add a goal that
      -- says nothing and a variable a reader has to chase.
      RAVar v -> pure (gs, RTVar v)
      RANum r -> pure (gs, RTNum r)
      _ -> do
        v <- freshVar "Tmp"
        pure (gs <> [REval v a], RTVar v)

  peelThen = do
    (env', e') <- peelLocals ctx env.leOpts env e0
    anfTerm ctx env' e'

  boolConst r = literalBool (App emptyAnno r [])

  unboundMsg r =
    "unbound reference `" <> hintOf r
      <> "` (prelude combinators, imported definitions and recursion are outside the M1 fragment)"

-- ---------------------------------------------------------------------------
-- Aggregates
-- ---------------------------------------------------------------------------

-- | The list aggregations the middle-end recognises, __by prelude name__.
--
-- Spelled after what @jl4-core\/libraries\/prelude.l4@ actually defines, which is
-- not what a Haskell or SQL reader expects and not what the M1 brief's IR
-- constraint 6 says: the prelude has @sum@ (@:265@), @count@ (@:119@ — there is
-- no @length@), @maximum@ (@:336@) and @minimum@ (@:345@); @max@\/@min@
-- (@:302,309@) are the BINARY combinators and lower to 'REval', not to an
-- aggregate; and no @average@ exists at all, which is why 'RAvg' is produced
-- only from the composite idiom (see 'avgPattern').
--
-- Recognition is by name because that is the only handle a call site has —
-- OpenFisca does the same (@resolvedToText ref == \"map\"@) — but it is reached
-- only after 'lookupCall' has declined, so a module-local definition of the same
-- name wins.
aggHead :: Resolved -> Maybe RAggOp
aggHead r = case hintOf r of
  "sum"     -> Just RSum
  "count"   -> Just RCount
  "maximum" -> Just RMaximum
  "minimum" -> Just RMinimum
  _         -> Nothing

-- | @map@\/@filter@ are recognised by name only so that they can be REJECTED
-- outside an aggregate position with a diagnostic that names the construct,
-- rather than falling through to \"unbound reference\" — which would be a
-- scope-resolution diagnosis for a fragment decision.
mapCombinator :: Text -> Bool
mapCombinator t = t `elem` (["map", "filter"] :: [Text])

-- | The other prelude list combinators, rejected __by name__ for the same
-- reason 'mapCombinator' is: the M1 fragment is narrower than
-- LOGIC-PROGRAMMING-BACKENDS-SPEC §2.4's v1 fragment here, and a narrowing that
-- surfaces as \"unbound reference\" is a narrowing nobody can count. #258 §6.1's
-- rejection census counts by KIND, so these have to have one that says what
-- happened.
--
-- Split by why they are refused. 'higherOrderCombinator' takes a function and is
-- 'LEHigherOrder'; 'firstOrderCombinator' does not, and is refused only because
-- no recogniser has been written — @elem@ in particular has an obvious image in
-- the synthesised @member\/2@ ('memberPred'), which is a widening, not a
-- discovery. Both are reached only after 'lookupCall' declines, so a module's
-- own definition of any of these names wins.
higherOrderCombinator :: Text -> Bool
higherOrderCombinator t = t `elem` (["all", "any", "foldr", "foldl"] :: [Text])

firstOrderCombinator :: Text -> Bool
firstOrderCombinator t = t `elem` (["elem", "nub", "reverse", "concat"] :: [Text])

-- | @minimum@ and @maximum@ are __overloaded__ in the prelude: once over
-- @LIST OF NUMBER@ (@:336,345@) and again over @LIST OF MAYBE NUMBER@
-- (@:353,385@). A name-keyed recogniser matches both, so the overloads are
-- separated __by sort__ — the resolved callee's own result type — and the
-- @MAYBE@ one is rejected as out of fragment rather than lowered to an
-- aggregate that would silently drop the @NOTHING@s.
rejectMaybeOverload :: Ctx -> LEnv -> Resolved -> Maybe SrcRange -> L ()
rejectMaybeOverload ctx env r rng =
  case sortOfType ctx.ctxSorts (entResultType ctx.ctxEnt (getUnique r)) of
    RSMaybe _ ->
      bailIn env rng LEMaybe
        ( "`" <> hintOf r <> "` here is the MAYBE-valued overload, which is outside the M1 fragment" )
    _ -> pure ()

-- | An aggregate application: collect the list, then reduce it.
--
-- The collection half is 'collectList'; the reduction half is one
-- 'RAggregate' goal. Nothing is re-associated and no operand order is touched
-- (portfolio invariant I9) — an aggregate is a single goal over a list that was
-- built in source order.
lowerAggregate :: Ctx -> LEnv -> RAggOp -> Expr Resolved -> L ([RGoal], RTerm)
lowerAggregate ctx env op lst = do
  (gs, lv) <- collectList ctx env lst
  out <- freshVar (aggHint op)
  pure (gs <> [RAggregate op lv out], RTVar out)

aggHint :: RAggOp -> Text
aggHint = \case
  RSum     -> "Sum"
  RCount   -> "Count"
  RMinimum -> "Minimum"
  RMaximum -> "Maximum"
  RAvg     -> "Average"

-- | The collection half of an aggregate: goals that bind a variable to the list
-- being reduced.
--
-- Two shapes, and only two:
--
-- * a plain list expression (a projected @LIST OF NUMBER@ field, a @GIVEN@
--   parameter, a literal) — already a term, so there is nothing to collect and
--   no @findall@ is emitted. An L4 list is /data/, not an open predicate;
--   generating over it would be a fiction.
--
-- * @map (GIVEN x YIELD \<body\>) \<list\>@ — the one higher-order position M1
--   admits (brief IR constraint 6, \"possibly @map@-projected\"). This does need
--   a generator, so it becomes @findall(Tmpl, (member(X, Xs), \<body goals\>),
--   L)@ over the synthesised 'memberPred'.
--
-- The @map@ arm is where the extraction OpenFisca's @aggSum@ open-codes
-- (@Lower.hs:296-299@) reappears. It is __not shared__: BLAWX-EXPORT-SPEC R9
-- says share only where it does not contort either side, and OpenFisca's version
-- is fused into a guard with @resolveMembers@ — a group-entity\/role resolver
-- with no relational meaning — so the genuinely common part is a three-line
-- pattern match with no home that is not a new module. See the stage-C findings.
collectList :: Ctx -> LEnv -> Expr Resolved -> L ([RGoal], RVar)
collectList ctx env = \case
  -- Recognised by name, but only AFTER 'lookupCall' has declined — the same
  -- discipline the aggregate head follows ('aggHead'), and for the same reason:
  -- a module that defines its own two-argument `map` must shadow the prelude's
  -- rather than have its clauses silently ignored in favour of a findall.
  App _ mref [Lam _ (MkGivenSig _ [mp]) lbody, src]
    | hintOf mref == "map"
    , isNothing (lookupCall ctx env (getUnique mref)) -> do
        (sgs, sv) <- collectList ctx env src
        let mpRes = givenName mp
        elemV <- freshVar (hintOf mpRes)
        -- The binder goes into 'leParams' as well as 'leVars': a WHERE inside
        -- the lambda's body is lambda-lifted through 'leParams', so a binder
        -- missing from it would be reported unbound in a helper that plainly
        -- references it. Its sort is the list's element type where the source
        -- annotated one, and opaque otherwise — the element sort is not
        -- reconstructible from the collection expression here.
        let elemSort = sortOfType ctx.ctxSorts (givenType mp)
            env' = env
              { leVars   = Map.insert (getUnique mpRes) elemV env.leVars
              , leParams = env.leParams <> [(getUnique mpRes, hintOf mpRes, elemSort)]
              }
        (bgs, bt) <- anfTerm ctx env' lbody
        (tgs, tmpl) <- asVar env' "Tmpl" bt
        mem <- memberPred
        out <- freshVar "L"
        pure ( sgs <> [RFindAll tmpl (RCall mem [RTVar elemV, RTVar sv] : (bgs <> tgs)) out]
             , out )
  e -> do
    (gs, t) <- anfTerm ctx env e
    (bg, v) <- asVar env "List" t
    pure (gs <> bg, v)

-- | Force a term into a variable, emitting a binding goal when it is not one
-- already. A literal list @[1, 2, 3]@ reduced by @sum@ is the reason this
-- exists: 'RAggregate' takes variables, and @L = [1, 2, 3]@ binds one in
-- bind-before-use order.
asVar :: LEnv -> Text -> RTerm -> L ([RGoal], RVar)
asVar _env _hint (RTVar v) = pure ([], v)
asVar _env hint t = do
  v <- freshVar hint
  pure ([RUnify v t], v)

-- | The list-membership generator, __synthesised once per module__ and only
-- when a @map@-projected aggregate actually needs one.
--
-- @findall@ needs a goal to backtrack over, and an L4 list is data: nothing in
-- the source enumerates its elements. So the enumeration is written down
-- explicitly, as the two structurally recursive clauses every logic-programming
-- target already has under some name — rather than being left implicit in a
-- @findall@ body that each emitter would have to invent a generator for.
--
-- It is 'RAuxiliary' and carries 'RStructural' on argument 1, so the recursion
-- marker means the same thing here as it does for a user's own list recursion.
memberPred :: L RName
memberPred = do
  existing <- gets (.lsMember)
  case existing of
    Just n  -> pure n
    Nothing -> do
      u <- freshUnique
      let nm = MkRName { rnText = "member", rnBase = "member", rnUnique = u }
          prov = MkRProv { rpvUnique = u, rpvRange = Nothing }
      x  <- freshVar "X"
      w  <- freshVar "Rest"
      x2 <- freshVar "X"
      h2 <- freshVar "Head"
      t2 <- freshVar "Rest"
      emitAux MkRPred
        { rpName      = nm
        , rpKind      = RAuxiliary
        , rpParams    = [RSOpaque "polymorphic element", RSList (RSOpaque "polymorphic element")]
        , rpResult    = Nothing
        , rpRecursion = RStructural 1
        , rpClauses   =
            [ MkRClause
                { rcHead = [RTVar x, RTCons (RTVar x) (RTVar w)]
                , rcBody = [], rcGuardPrefix = 0, rcProv = prov }
            , MkRClause
                { rcHead = [RTVar x2, RTCons (RTVar h2) (RTVar t2)]
                , rcBody = [RCall nm [RTVar x2, RTVar t2]]
                , rcGuardPrefix = 0, rcProv = prov }
            ]
        , rpExported  = False
        , rpDesc      = Just "list membership, synthesised as the generator a findall needs"
        , rpNlg       = Nothing
        , rpRef       = Nothing
        , rpProv      = prov
        }
      -- 'RSOpaque' is never emitted silently ("L4.Relational.IR"), and this
      -- predicate is the one place the middle-end mints one for a reason other
      -- than a type it could not name: the generator is polymorphic, and its
      -- element sort is whatever the aggregate's list held. Nothing of the
      -- author's is lost, so the note is Advisory — but it is a note, because a
      -- program carrying a predicate with no value type is exactly what an
      -- ontology-bearing target (Blawx) must be told about rather than discover.
      note MkFidelityNote
        { code     = "R-SORT"
        , severity = Advisory
        , element  = "member"
        , range    = Nothing
        , message  = "the synthesised list-membership generator is polymorphic; its element sort is carried as opaque"
        , lost     = "nothing of the source; the sort is recoverable from the call site's list"
        }
      modify' (\s -> s { lsMember = Just nm })
      pure nm

-- | @sum xs \/ count xs@ — the /only/ way 'RAvg' is produced, because the
-- prelude has no @average@ (@risks.md@ §5).
--
-- Both operands must reduce the __same__ list expression, compared structurally
-- ('sameExpr') because 'Expr' 's derived 'Eq' includes annotations and two
-- occurrences of one expression have different source ranges. When they are not
-- the same, this declines and the division lowers as an ordinary 'RDiv' over two
-- aggregates — which is still correct, merely less recognisable.
avgPattern :: Expr Resolved -> Expr Resolved -> Maybe (Expr Resolved)
avgPattern a b = case (a, b) of
  (App _ s [l1], App _ c [l2])
    | aggHead s == Just RSum
    , aggHead c == Just RCount
    , sameExpr l1 l2 -> Just l1
  _ -> Nothing

-- | Structural equality that ignores annotations, over the expression shapes a
-- collection can take in the M1 fragment. Deliberately conservative: an
-- unrecognised shape answers 'False', which costs a recognition and never
-- creates a false one.
sameExpr :: Expr Resolved -> Expr Resolved -> Bool
sameExpr a b = case (a, b) of
  (App _ x xs, App _ y ys) ->
    getUnique x == getUnique y && length xs == length ys && and (zipWith sameExpr xs ys)
  (Proj _ x f, Proj _ y g) -> getUnique f == getUnique g && sameExpr x y
  (Lit _ (NumericLit _ x), Lit _ (NumericLit _ y)) -> x == y
  (Lit _ (StringLit _ x), Lit _ (StringLit _ y))   -> x == y
  (List _ xs, List _ ys) -> length xs == length ys && and (zipWith sameExpr xs ys)
  (Cons _ x xs, Cons _ y ys) -> sameExpr x y && sameExpr xs ys
  _ -> False

-- | The @negation-as-failure@ library\'s eliminators, rejected __by name__.
--
-- They are ordinary library applications, so the general call path would lower
-- @holds p@ to a predicate call named @holds@ — semantically inert and silently
-- wrong for every target. #258 calls them the semantic hinge and its LP-R3
-- (eliminator-directed erasure vs. a uniform three-valued encoding) is still
-- OPEN, so M1 refuses rather than guesses.
nafEliminator :: Text -> Bool
nafEliminator t = t `elem` (["holds", "naf", "presumed"] :: [Text])

-- | Arithmetic stays as a small expression tree over already-bound atoms.
-- Flattening @a + b * c@ into three goals would buy nothing and cost every
-- emitter a reassembly pass.
anfArith :: Ctx -> LEnv -> Expr Resolved -> L ([RGoal], RArith)
anfArith ctx env e0 = case e0 of
  Plus _ a b      -> bin RAdd a b
  Minus _ a b     -> bin RSub a b
  Times _ a b     -> bin RMul a b
  -- The composite average idiom is recognised HERE and not in 'anfTerm', because
  -- an average can appear inside a larger arithmetic expression
  -- (@sum xs / count xs + 1@) and 'anfTerm' only sees the outermost operator.
  DividedBy _ a b
    | Just lst <- avgPattern a b -> do
        (gs, lv) <- collectList ctx env lst
        out <- freshVar (aggHint RAvg)
        pure (gs <> [RAggregate RAvg lv out], RAVar out)
    | otherwise -> bin RDiv a b
  Modulo _ a b    -> bin RMod a b
  Percent _ a     -> do
    (g, x) <- anfArith ctx env a
    pure (g, RABin RDiv x (RANum 100))
  Lit _ (NumericLit _ r) -> pure ([], RANum r)
  _ -> do
    (g, t) <- anfTerm ctx env e0
    case t of
      RTNum r -> pure (g, RANum r)
      RTVar v -> pure (g, RAVar v)
      _       -> bailIn env (rangeOf e0) (LEUnsupported "non-numeric operand")
                   "an arithmetic operand did not reduce to a number or a bound variable"
 where
  bin op a b = do
    (ga, x) <- anfArith ctx env a
    (gb, y) <- anfArith ctx env b
    pure (ga <> gb, RABin op x y)

-- | Lower one DNF atom to goals.
anfAtom :: Ctx -> LEnv -> BAtomP -> L [RGoal]
anfAtom ctx env = \case
  APGoals gs -> pure gs
  APCmp op a b -> do
    (ga, ta) <- anfTerm ctx env a
    (gb, tb) <- anfTerm ctx env b
    pure (ga <> gb <> [RCmp op ta tb])
  APMatch scrut c -> do
    (gs, t) <- anfTerm ctx env scrut
    case t of
      RTVar v -> pure (gs <> [RMatch v (rName c)])
      _       -> pure (gs <> [RCmp REq t (RTAtom (rName c))])
  APExpr pol e -> anfPred ctx env pol e

-- | Lower a boolean-position expression to goals. This is the only place
-- 'RNotCall' is produced, and the only negation form the IR has.
anfPred :: Ctx -> LEnv -> Bool -> Expr Resolved -> L [RGoal]
anfPred ctx env pol e0 = case e0 of
  App _ r args
    | Nothing <- Map.lookup (getUnique r) env.leVars
    , Just sig <- lookupCall ctx env (getUnique r) -> do
        pre <- preArgs env (rangeOf e0) sig
        parts <- traverse (anfTerm ctx env) args
        let gs = concatMap fst parts
            ts = pre <> map snd parts
        if sig.csBool
          then pure (gs <> [ (if pol then RCall else RNotCall) sig.csName ts ])
          else do
            v <- freshVar (sig.csName.rnBase)
            pure (gs <> [RCall sig.csName (ts <> [RTVar v]), RUnify v (RTBool pol)])
  -- A computed (@MEANS@) BOOLEAN field used as a guard. Its desugared selector
  -- is a boolean predicate, so it takes the call form directly, with polarity;
  -- routing it through 'anfTerm' would append an output argument that the
  -- selector's declaration dropped. Stored boolean fields do not match here
  -- (they are in ctxFields) and still lower via RProj + RUnify below.
  Proj _ inner f
    | Nothing <- Map.lookup (getUnique f) ctx.ctxFields
    , Just sig <- lookupCall ctx env (getUnique f)
    , sig.csBool -> do
        (gs, ti) <- anfTerm ctx env inner
        pre <- preArgs env (rangeOf e0) sig
        pure (gs <> [ (if pol then RCall else RNotCall) sig.csName (pre <> [ti]) ])
  _ -> do
    (gs, t) <- anfTerm ctx env e0
    case t of
      RTVar v            -> pure (gs <> [RUnify v (RTBool pol)])
      RTBool b | b == pol -> pure gs
      _ ->
        bailIn env (rangeOf e0) (LEUnsupported "non-boolean atom in a guard")
          "a guard did not reduce to a predicate call, a projected boolean, or a bound variable"

-- ---------------------------------------------------------------------------
-- Lowering one definition
-- ---------------------------------------------------------------------------

data DefSpec = MkDefSpec
  { dsName     :: !RName
  , dsKind     :: !RPredKind
  , dsOuter    :: ![(Unique, Text, RSort)]  -- ^ lambda-lifted enclosing parameters
  , dsParams   :: ![(Unique, Text, RSort)]
  , dsResult   :: !(Maybe RSort)            -- ^ 'Nothing' = boolean, output dropped
  , dsBody     :: !(Expr Resolved)
  , dsCalls    :: !(Map Unique CallSig)
  , dsExported :: !Bool
  , dsDesc     :: !(Maybe Text)
  , dsNlg      :: !(Maybe Text)
  , dsRef      :: !(Maybe Text)
  , dsProv     :: !RProv
  }

lowerSpec :: Ctx -> LowerOptions -> DefSpec -> L RPred
lowerSpec ctx opts ds = do
  headVs <- traverse (\(u, h, s) -> (\v -> (u, v, s)) <$> freshVar h) (ds.dsOuter <> ds.dsParams)
  let env = MkLEnv
        { leVars   = Map.fromList [ (u, v) | (u, v, _) <- headVs ]
        , leSubst  = mempty
        , leParams = [ (u, h, s) | ((u, _, s), h) <- zip headVs (map snd3 (ds.dsOuter <> ds.dsParams)) ]
        , leCalls  = ds.dsCalls
        , leFn     = ds.dsName.rnText
        , leOpts   = opts
        }
      arity = length headVs + (if isJust ds.dsResult then 1 else 0)
  checkFragmentSorts env ds.dsProv.rpvRange ([ s | (_, _, s) <- headVs ] <> maybeToList ds.dsResult)
  forM_ opts.loMaxArity \cap ->
    when (arity > cap) $
      bailIn env ds.dsProv.rpvRange LEArity
        ( "predicate arity " <> Text.textShow arity <> " exceeds the ceiling of "
            <> Text.textShow cap )
  -- Locals are peeled HERE rather than being left to 'expandRows', so that the
  -- structural-recursion recogniser sees the CONSIDER a `WHERE` would otherwise
  -- hide. 'expandRows' peels again and finds nothing left to peel.
  (envP, bodyP) <- peelLocals ctx opts env ds.dsBody
  (clauses, recursion) <- case recogniseStructural headVs bodyP of
    -- A binding-pattern CONSIDER we cannot admit. The diagnostic must name the
    -- RECURSION decision, which is why this runs before 'normaliseGuarded':
    -- 'considerRows' returns Nothing for every FOLLOWED BY row (GuardedRows.hs
    -- :105,148), so the generic path would report "CONSIDER with a binding
    -- pattern" — a table-shape diagnosis for a termination decision.
    Just (Left (k, why)) -> bailIn envP (rangeOf bodyP <|> ds.dsProv.rpvRange) k why
    Just (Right sr0) -> do
      (sr, cs) <- structuralClauses ctx opts ds envP headVs sr0
      pure (cs, if sr.srRecursive then RStructural sr.srPos else RNonRecursive)
    Nothing -> do
      rows <- expandRows ctx opts envP ds.dsProv bodyP
      cs <- concat <$> traverse (rowClauses ctx opts ds [ RTVar v | (_, v, _) <- headVs ]) rows
      -- Outside the structural shape M1 admits no self-reference. The promise
      -- "emitted programs terminate" stays checkable only while that is true;
      -- widening it tracks #258's LP-R7.
      let selfCalls = [ () | c <- cs, g <- c.rcBody, callee g == Just ds.dsName ]
      unless (null selfCalls) $
        bailIn envP ds.dsProv.rpvRange LEUncheckedRecursion
          "self-reference with no structurally decreasing argument"
      pure (cs, RNonRecursive)
  result <- resolveResult ds clauses
  forM_ [ () | RSOpaque _ <- [ s | (_, _, s) <- headVs ] ] \_ ->
    note MkFidelityNote
      { code     = "R-SORT"
      , severity = Lossy
      , element  = ds.dsName.rnText
      , range    = ds.dsProv.rpvRange
      , message  = "a parameter has no sort the M1 fragment can name; it is carried as opaque"
      , lost     = "the declared value type an ontology-bearing target (Blawx) needs"
      }
  pure MkRPred
    { rpName      = ds.dsName
    , rpKind      = ds.dsKind
    , rpParams    = [ s | (_, _, s) <- headVs ]
    , rpResult    = result
    , rpRecursion = recursion
    , rpClauses   = clauses
    , rpExported  = ds.dsExported
    , rpDesc      = ds.dsDesc
    , rpNlg       = ds.dsNlg
    , rpRef       = ds.dsRef
    , rpProv      = ds.dsProv
    }
 where
  snd3 (_, b, _) = b

-- | One row → one clause per DNF disjunct.
--
-- Takes the head argument TERMS rather than the head variables, because a
-- structurally decomposed clause carries @[]@ or @[X|Xs]@ at one position
-- instead of the variable the ordinary path binds there.
rowClauses
  :: Ctx -> LowerOptions -> DefSpec -> [RTerm] -> Row -> L [RClause]
rowClauses ctx opts ds headArgs row = do
  let env = row.rowEnv
  -- For a boolean predicate the row's VALUE is another guard; a literal TRUE
  -- drops out of the conjunction and a literal FALSE deletes the clause.
  mValueGuards <- case ds.dsResult of
    Just _  -> pure (Just [])
    Nothing -> pure $ case literalBool row.rowValue of
      Just True  -> Just []
      Just False -> Nothing
      Nothing    -> Just [(True, row.rowValue)]
  case mValueGuards of
    Nothing -> pure []
    Just vg -> do
      pfxForm <- conjForm ctx env row.rowPrefix
      gForm   <- conjForm ctx env (row.rowGuards <> vg)
      pfxAlts <- factorDnf ctx opts env pfxForm
      gAlts   <- factorDnf ctx opts env gForm
      fmap concat $ forM pfxAlts \pa -> forM gAlts \ga -> do
        pGoals <- concat <$> traverse (anfAtom ctx env) pa
        gGoals <- concat <$> traverse (anfAtom ctx env) ga
        (vGoals, hd) <- case ds.dsResult of
          Nothing -> pure ([], headArgs)
          Just _  -> do
            (g, t) <- anfTerm ctx env row.rowValue
            pure (g, headArgs <> [t])
        pure MkRClause
          { rcHead        = hd
          , rcBody        = pGoals <> gGoals <> vGoals
          , rcGuardPrefix = length pGoals
          , rcProv        = row.rowProv
          }

-- ---------------------------------------------------------------------------
-- Structural recursion
-- ---------------------------------------------------------------------------

-- | The one recursion warrant M1 admits, recognised in the source.
data StructRec = MkStructRec
  { srPos       :: !Int               -- ^ 0-based head position of the list argument
  , srParam     :: !Unique            -- ^ the scrutinised parameter's binder
  , srElemSort  :: !RSort
  , srListSort  :: !RSort
  , srBase      :: !(Expr Resolved)   -- ^ the @WHEN EMPTY@ arm
  , srHeadBndr  :: !Resolved          -- ^ @x@ in @WHEN x FOLLOWED BY xs@
  , srTailBndr  :: !Resolved          -- ^ @xs@
  , srStep      :: !(Expr Resolved)   -- ^ the @FOLLOWED BY@ arm
  , srRecursive :: !Bool              -- ^ whether the step arm actually calls back
  }

-- | Recognise @CONSIDER \<param\> WHEN EMPTY … WHEN x FOLLOWED BY xs …@.
--
-- __This must run before 'normaliseGuarded' and cannot go through it__
-- (@risks.md@ §6). @L4.Viz.GuardedRows.patternGuard@ answers @(Nothing, Nothing)@
-- for @PatVar@ and @PatCons@ (@GuardedRows.hs:148@) — a binding pattern has no
-- closed boolean guard — and @considerRows@ then requires every such row to have
-- a literal-@FALSE@ body (@:105@) and declines otherwise. So a @FOLLOWED BY@
-- CONSIDER always yields @Nothing@ from the normaliser, and a recursion check
-- placed after it would report a table-shape problem for a termination decision.
-- @L4.Dmn.Lower@ records the same ordering rule at @Dmn\/Lower.hs:6049-6053@.
--
-- Three answers, and the middle one is the point:
--
-- * @Nothing@ — not a binding-pattern CONSIDER at all; the generic guarded-rows
--   path takes it.
-- * @Just (Left …)@ — it IS one, and cannot be admitted. The caller raises this
--   as the batch diagnostic, with the kind naming the actual decision.
-- * @Just (Right …)@ — admitted; two clauses over @[]@ and @[X|Xs]@ heads.
--
-- A shape with no self-call is still admitted (list destructuring is not
-- recursion), and then carries 'RNonRecursive' rather than a marker it has not
-- earned.
recogniseStructural
  :: [(Unique, RVar, RSort)] -> Expr Resolved
  -> Maybe (Either (LowerErrorKind, Text) StructRec)
recogniseStructural headVs = \case
  Consider _ scrut branches
    | any isBindingBranch branches ->
        Just (admit scrut branches)
  _ -> Nothing
 where
  isBindingBranch (MkBranch _ lhs _) = case lhs of
    When _ PatCons{} -> True
    When _ PatVar{}  -> True
    _                -> False

  reject k m = Left (k, m)

  hasConsBranch = any \(MkBranch _ lhs _) -> case lhs of
    When _ PatCons{} -> True
    _                -> False

  admit scrut branches = do
    -- Said before anything about lists, because it is a different objection:
    -- with no FOLLOWED BY row this is not a list decomposition that failed a
    -- sort check, it is a variable catch-all — @CONSIDER c WHEN Red THEN …
    -- WHEN other THEN …@ — and naming the LIST sort would send the reader to
    -- look at a type that is not the problem. ('msgOfExpr' says the same thing
    -- about the same construct: M1 admits payload-free discrimination, and a
    -- catch-all is spelled OTHERWISE.)
    unless (hasConsBranch branches) $
      reject (LEUnsupported "CONSIDER with a binding pattern")
        ( "a variable catch-all pattern binds a name, so the row has no closed guard;"
            <> " M1 admits payload-free discrimination with OTHERWISE as the catch-all" )
    (pos, pu, psort) <- case scrut of
      App _ p [] | Just i <- indexOfParam (getUnique p) -> Right (i, getUnique p, sortAt i)
      _ -> reject (LEUnsupported "CONSIDER with a binding pattern")
             "a structural CONSIDER must scrutinise one of the definition's own parameters"
    (esort, lsort) <- case psort of
      RSList inner -> Right (inner, psort)
      _ -> reject (LEUnsupported "CONSIDER with a binding pattern")
             "a binding pattern is admitted only over a LIST-sorted argument"
    base <- case [ b | MkBranch _ (When _ (PatApp _ c [])) b <- branches
                     , getUnique c == emptyUnique ] of
      (b : _) -> Right b
      [] -> reject LEUncheckedRecursion
             ( "the EMPTY arm is missing, so nothing bounds the recursion"
                 <> " (a `@nonexhaustive` list CONSIDER has no base case to terminate on)" )
    (hb, tb, step) <- case [ (h, t, b)
                           | MkBranch _ (When _ (PatCons _ (PatVar _ h) (PatVar _ t))) b <- branches
                           ] of
      (r : _) -> Right r
      [] -> reject (LEUnsupported "CONSIDER with a binding pattern")
             "M1 admits the two-arm list shape (WHEN EMPTY / WHEN x FOLLOWED BY xs) only"
    pure MkStructRec
      { srPos       = pos
      , srParam     = pu
      , srElemSort  = esort
      , srListSort  = lsort
      , srBase      = base
      , srHeadBndr  = hb
      , srTailBndr  = tb
      , srStep      = step
      , srRecursive = False   -- filled in by 'structuralClauses', which knows the callee
      }

  indexOfParam u = listToMaybe [ i | (i, (u', _, _)) <- zip [0 ..] headVs, u' == u ]
  sortAt i = maybe (RSOpaque "?") (\(_, _, s) -> s) (headVs !!? i)

-- | Build the two clauses of a structurally decomposed definition.
--
-- The head argument at 'srPos' is @[]@ in the base clause and @[X|Xs]@ in the
-- step clause — /materialised in the head/, which is what makes the decrease
-- visible to every target rather than asserted by a marker. The scrutinee's own
-- binder is rebound through 'leSubst' to exactly that term, so an arm that
-- mentions the list it destructured says @[X|Xs]@ and not an unbound variable.
--
-- The decrease check is positional and syntactic, and covers BOTH arms: the base
-- arm may not call back at all, and every self-application in the step arm must
-- pass the TAIL binder in the scrutinised slot. Anything else is
-- 'LEUncheckedRecursion' — the promise "emitted programs terminate" is only
-- worth making while it is checkable (BLAWX-EXPORT-SPEC R9).
structuralClauses
  :: Ctx -> LowerOptions -> DefSpec -> LEnv -> [(Unique, RVar, RSort)] -> StructRec
  -> L (StructRec, [RClause])
structuralClauses ctx opts ds env headVs sr = do
  let selfApps  = selfOccurrences ds.dsName.rnUnique sr.srStep
      baseApps  = selfOccurrences ds.dsName.rnUnique sr.srBase
      -- 'srPos' is a position in the HEAD, which for a lambda-lifted helper
      -- begins with the enclosing definition's parameters ('dsOuter'); a source
      -- call site writes only the helper's own arguments, since 'csPre' is
      -- prepended later, at the call site in 'anfPred'\/'anfTerm'. Reading the
      -- head position out of a source argument list therefore reads the wrong
      -- slot — or falls off the end and reports a correct recursive call as
      -- undecreasing — for every recursive list helper written inside a
      -- parameterised decision.
      srcPos    = sr.srPos - length ds.dsOuter
      decreasing args = case args !!? srcPos of
        Just (App _ t []) -> getUnique t == getUnique sr.srTailBndr
        _                 -> False
      recursive = not (null selfApps)
  -- The BASE arm is checked too, and admits no self-call at all. Its scrutinee
  -- is @[]@, so a call back into this predicate passes the same @[]@ it matched
  -- on and the clause is `f([], V) :- f([], V).` — directly left-recursive, and
  -- non-terminating in every target. Checking only the step arm let exactly that
  -- through, in the one arm no fixture covered.
  unless (null baseApps) $
    bailIn env (rangeOf sr.srBase) LEUncheckedRecursion
      ( "the EMPTY arm calls `" <> ds.dsName.rnBase
          <> "` again on the same empty list, so the recursion never decreases" )
  unless (all decreasing selfApps) $
    bailIn env (rangeOf sr.srStep) LEUncheckedRecursion
      ( "the recursive call does not pass `" <> hintOf sr.srTailBndr
          <> "` in the scrutinised argument position, so nothing shows the recursion decreases" )
  hv <- freshVar (hintOf sr.srHeadBndr)
  tv <- freshVar (hintOf sr.srTailBndr)
  let headArgs = [ RTVar v | (_, v, _) <- headVs ]
      -- The scrutinised parameter leaves 'leVars'/'leParams' in both clauses: it
      -- is no longer a variable the head binds, so threading it into a
      -- lambda-lifted helper would pass something unbound.
      dropParam e = e { leVars   = Map.delete sr.srParam e.leVars
                      , leParams = [ p | p@(u, _, _) <- e.leParams, u /= sr.srParam ]
                      }
      baseEnv = (dropParam env) { leSubst = Map.insert sr.srParam RTNil env.leSubst }
      consTerm = RTCons (RTVar hv) (RTVar tv)
      stepEnv = (dropParam env)
        { leVars   = Map.insert (getUnique sr.srHeadBndr) hv
                       (Map.insert (getUnique sr.srTailBndr) tv (Map.delete sr.srParam env.leVars))
        , leSubst  = Map.insert sr.srParam consTerm env.leSubst
        , leParams = [ p | p@(u, _, _) <- env.leParams, u /= sr.srParam ]
                       <> [ (getUnique sr.srHeadBndr, hintOf sr.srHeadBndr, sr.srElemSort)
                          , (getUnique sr.srTailBndr, hintOf sr.srTailBndr, sr.srListSort)
                          ]
        }
      at i t = [ if j == i then t else a | (j, a) <- zip [0 ..] headArgs ]
  baseRows <- expandRows ctx opts baseEnv ds.dsProv sr.srBase
  baseCs   <- concat <$> traverse (rowClauses ctx opts ds (at sr.srPos RTNil)) baseRows
  stepRows <- expandRows ctx opts stepEnv ds.dsProv sr.srStep
  stepCs   <- concat <$> traverse (rowClauses ctx opts ds (at sr.srPos consTerm)) stepRows
  pure (sr { srRecursive = recursive }, baseCs <> stepCs)

-- | The argument list of every application of the definition's own name inside
-- an expression. A bare reference (@App _ r []@) counts too, and fails the
-- decrease check for want of an argument in the scrutinised slot — which is the
-- right answer: passing the function itself along is not a recursion this
-- fragment can certify.
selfOccurrences :: Unique -> Expr Resolved -> [[Expr Resolved]]
selfOccurrences self =
  foldMapOf (cosmosOf (gplate @(Expr Resolved))) \case
    App _ r args | getUnique r == self -> [args]
    _ -> []

-- | The result sort, with a last-resort recovery from the lowered clauses.
--
-- A @WHERE@\/@LET@ helper is __not in 'EntityInfo'__ (it holds top-level
-- entities), so a local with no @GIVETH@ arrives here with no type at all. Since
-- the clause heads are already built, their output terms answer the question
-- directly — and an ontology-bearing target (Blawx declares an attribute's value
-- type and cannot infer it) needs an answer rather than an apology. Recovery is
-- recorded as an 'Advisory' note so the golden shows where a sort came from
-- something other than the source.
resolveResult :: DefSpec -> [RClause] -> L (Maybe RSort)
resolveResult ds clauses = case ds.dsResult of
  Just (RSOpaque why)
    | Just s <- recovered ->
        do note MkFidelityNote
             { code     = "R-SORT"
             , severity = Advisory
             , element  = ds.dsName.rnText
             , range    = ds.dsProv.rpvRange
             , message  = "result sort recovered from the lowered clauses (" <> why <> ")"
             , lost     = "nothing; the sort is inferred, not declared"
             }
           pure (Just s)
    | otherwise ->
        do note MkFidelityNote
             { code     = "R-SORT"
             , severity = Lossy
             , element  = ds.dsName.rnText
             , range    = ds.dsProv.rpvRange
             , message  = "no result sort could be determined (" <> why <> ")"
             , lost     = "the declared value type an ontology-bearing target (Blawx) needs"
             }
           pure ds.dsResult
  other -> pure other
 where
  recovered = case mapM outSort clauses of
    Just (s : rest) | all (== s) rest -> Just s
    _                                 -> Nothing

  outSort c = case reverse c.rcHead of
    []      -> Nothing
    (t : _) -> case t of
      RTNum _  -> Just RSNum
      RTStr _  -> Just RSString
      RTBool _ -> Just RSBool
      RTAtom n -> Just (RSEnum n)
      RTVar v | any (isEvalOf v) c.rcBody -> Just RSNum
      _        -> Nothing

  isEvalOf v = \case
    REval w _        -> w == v
    RAggregate _ _ w -> w == v
    _                -> False

conjForm :: Ctx -> LEnv -> [(Bool, Expr Resolved)] -> L BForm
conjForm ctx env =
  foldM (\acc (pol, e) -> bAnd acc <$> toBForm ctx env (not pol) e) BTrue

callee :: RGoal -> Maybe RName
callee = \case
  RCall n _    -> Just n
  RNotCall n _ -> Just n
  _            -> Nothing

-- ---------------------------------------------------------------------------
-- Diagnostics for out-of-fragment constructs
-- ---------------------------------------------------------------------------

-- | The rejection catalogue, keyed by constructor. #258 §6.1's rejection census
-- counts BY CONSTRUCTOR precisely so it cannot be polluted by a reworded
-- sentence; 'errMsg' carries the prose.
kindOfExpr :: Expr Resolved -> LowerErrorKind
kindOfExpr = \case
  Regulative{} -> LEDeontic
  RAnd{}       -> LEDeontic
  ROr{}        -> LEDeontic
  Event{}      -> LEEvent
  Fetch{}      -> LEEffect
  Post{}       -> LEEffect
  Env{}        -> LEEffect
  Record{}     -> LELedger
  ReadCell{}   -> LELedger
  Breach{}     -> LEBreach
  Concat{}     -> LEString
  AsString{}   -> LEString
  Lam{}        -> LEHigherOrder
  AppNamed{}   -> LEUnsupported "named-argument application"
  Consider{}   -> LEUnsupported "CONSIDER with a binding pattern"
  IfThenElse{} -> LEUnsupported "IF in a nested value position"
  MultiWayIf{} -> LEUnsupported "BRANCH in a nested value position"
  Implies{}    -> LEUnsupported "IMPLIES in a value position"
  other        -> LEUnsupported (constructorName other)

-- | Why the construct has no image, in the author's vocabulary. Deliberately
-- does NOT restate 'kindOfExpr' — the kind is the stable, greppable half and is
-- already printed beside this.
msgOfExpr :: Expr Resolved -> Text
msgOfExpr = \case
  Regulative{} ->
    "a Horn clause says what HOLDS; it has no vocabulary for what a party must do, by when, or what a breach is"
  RAnd{} -> "regulative composition has no image in a clause body"
  ROr{}  -> "regulative composition has no image in a clause body"
  Event{}    -> "an event has no image in a clause body"
  Fetch{}    -> "a rule body must be pure; an HTTP fetch is not"
  Post{}     -> "a rule body must be pure; an HTTP post is not"
  Env{}      -> "a rule body must be pure; an environment lookup is not"
  Record{}   -> "a ledger write has no image in a clause body"
  ReadCell{} -> "a ledger read has no image in a clause body"
  Breach{}   -> "BREACH is a deontic outcome, not a proposition"
  Concat{}   -> "M1 admits strings only as literal-equality atoms"
  AsString{} -> "M1 admits strings only as literal-equality atoms"
  Lam{}      -> "first-order Horn clauses cannot carry a function as a value; M1 admits a lambda only inside a recognised aggregate"
  AppNamed{} -> "a named-argument application is admitted only as a query input, where it flattens to facts"
  Consider{} -> "a binding pattern must be decided before normalisation; M1 admits only payload-free discrimination"
  IfThenElse{} -> "a guarded chain is split into clauses at the top of a definition, not inside an operand"
  MultiWayIf{} -> "a guarded chain is split into clauses at the top of a definition, not inside an operand"
  Implies{}    -> "IMPLIES survives only in a guard, where it becomes a disjunction"
  other        -> constructorName other <> " is outside the M1 relational fragment"

-- | A short human label for a rejected node, in the shape of
-- @L4.OpenFisca.Lower.constructorName@.
constructorName :: Expr Resolved -> Text
constructorName = \case
  Regulative{} -> "deontic/regulative rule (PARTY/MUST/MAY)"
  RAnd{}       -> "regulative AND"
  ROr{}        -> "regulative OR"
  Event{}      -> "EVENT"
  Fetch{}      -> "FETCH"
  Post{}       -> "POST"
  Env{}        -> "environment lookup"
  Record{}     -> "RECORD/COMMIT/ATTEST"
  ReadCell{}   -> "RECALL"
  Breach{}     -> "BREACH"
  Concat{}     -> "string concatenation"
  AsString{}   -> "string coercion"
  Lam{}        -> "lambda"
  AppNamed{}   -> "named-argument application"
  Consider{}   -> "CONSIDER with a binding pattern"
  IfThenElse{} -> "nested IF in a value position"
  MultiWayIf{} -> "nested BRANCH in a value position"
  Implies{}    -> "IMPLIES in a value position"
  Inert{}      -> "inert scaffolding"
  List{}       -> "list literal"
  Cons{}       -> "list cons"
  Proj{}       -> "projection"
  App{}        -> "application"
  Lit{}        -> "literal"
  _            -> "expression"

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------

-- | @#EVAL@ \/ @#ASSERT@ → 'RQuery'. An out-of-fragment directive is __skipped
-- with a fidelity note, not rejected__: a module may carry an @#EVAL@ over a
-- deontic rule and still export a perfectly good constitutive decision.
lowerQueries :: Ctx -> Module Resolved -> State LState [RQuery]
lowerQueries ctx m = do
  let directives =
        [ (k, ex, rangeOf d)
        | Directive _ d <- topDecls m
        , Just (k, ex) <- [directiveOf d]
        ]
  qs <- forM (zip [1 :: Int ..] directives) \(i, (k, ex, rng)) -> do
    r <- runExceptT (lowerQuery ctx i k ex rng)
    case r of
      Right q -> pure (Just q)
      Left e  -> do
        note' MkFidelityNote
          { code     = "R-DIRECTIVE"
          , severity = Advisory
          , element  = "#" <> (case k of RQEval -> "EVAL"; RQAssert -> "ASSERT")
          , range    = rng
          , message  = "this directive is outside the M1 fragment and was not captured as a query: "
                         <> e.errMsg
          , lost     = "one differential-harness seed"
          }
        pure Nothing
  pure (catMaybes qs)
 where
  note' n = modify' (\s -> s { lsNotes = s.lsNotes <> [n] })
  directiveOf = \case
    LazyEval _ ex      -> Just (RQEval, ex)
    LazyEvalTrace _ ex -> Just (RQEval, ex)
    Assert _ ex        -> Just (RQAssert, ex)
    Check{}            -> Nothing
    Contract{}         -> Nothing

lowerQuery :: Ctx -> Int -> RQueryKind -> Expr Resolved -> Maybe SrcRange -> L RQuery
lowerQuery ctx i k ex0 rng = do
  let env = MkLEnv { leVars = mempty, leSubst = mempty, leParams = [], leCalls = mempty
                   , leFn = "#" <> (case k of RQEval -> "EVAL"; RQAssert -> "ASSERT")
                   , leOpts = defaultLowerOptions }
      ex = carameliseExpr ex0
  -- @#ASSERT f x EQUALS 42@ carries its own expectation; anything else leaves
  -- 'rqExpected' empty, and the harness must obtain it by running the L4
  -- evaluator (BLAWX-EXPORT-SPEC R11 puts the oracle OUTSIDE the artifact).
  let (callExpr, expectedExpr) = case (k, ex) of
        (RQAssert, Equals _ a b) -> (a, Just b)
        _                        -> (ex, Nothing)
  case callExpr of
    App _ r args | Just sig <- lookupCall ctx env (getUnique r) -> do
      (facts, terms) <- foldM (\(fs, ts) a -> do
                                  (f, t) <- queryArg ctx env a
                                  pure (fs <> f, ts <> [t]))
                              ([], []) args
      out <- if sig.csBool then pure Nothing else Just <$> freshVar (sig.csName.rnBase)
      expected <- case (expectedExpr, sig.csBool) of
        (Just b, _) -> do
          (gs, t) <- anfTerm ctx env b
          if null gs
            then pure (Just t)
            else do
              -- A computed expectation (@#ASSERT f x EQUALS g y@) has no ground
              -- term, so it cannot be recorded. Dropping it silently would print
              -- as "(expectation from the L4 evaluator)" — byte-identical to a
              -- directive that never carried one, which is exactly the state
              -- R11's ruling exists to make impossible: an expectation nobody
              -- can see is missing is an expectation the harness compares
              -- against nothing.
              note MkFidelityNote
                { code     = "R-DIRECTIVE"
                , severity = Advisory
                , element  = env.leFn
                , range    = rng
                , message  = "this directive's expected value is computed rather than literal, so it"
                               <> " was not captured; the harness must obtain it from the L4 evaluator"
                , lost     = "one statically-known differential expectation"
                }
              pure Nothing
        (Nothing, True) | k == RQAssert -> pure (Just (RTBool True))
        _ -> pure Nothing
      pure MkRQuery
        { rqId       = "q" <> Text.textShow i
        , rqKind     = k
        , rqGoal     = sig.csName
        , rqArgs     = terms
        , rqOut      = out
        , rqFacts    = facts
        , rqExpected = expected
        , rqProv     = MkRProv { rpvUnique = getUnique r, rpvRange = rng }
        }
    _ -> bailIn env rng (LEUnsupported "directive shape")
           "expected an application of a lowered decision to literal arguments"

-- | A query argument. A record literal is __flattened to one fact per stored
-- field__ — the only representation that does not choose between the
-- functor-term and the attribute-predicate encodings (IR constraint 1).
queryArg :: Ctx -> LEnv -> Expr Resolved -> L ([RFact], RTerm)
queryArg ctx env = \case
  -- Applicant WITH age IS 70, …
  AppNamed _ r nes _ | Just rd <- recordOf ctx (getUnique r) -> do
    subj <- freshVar (Text.take 1 rd.rrName.rnBase <> "0")
    parts <- forM nes \(MkNamedExpr _ f v) -> do
      -- RECURSIVE, not 'anfTerm': a field value may itself be a record literal
      -- or a list of them (@Basket WITH items IS LIST (Item WITH price IS 10)@),
      -- and each nested literal needs its own subject and its own facts. Calling
      -- 'anfTerm' here rejected the whole directive and cost the differential
      -- harness a seed for the one export whose input is a list of records.
      (inner, t) <- queryArg ctx env v
      pure (inner <> [MkRFact { rfaPred = fieldName ctx f, rfaArgs = [RTVar subj, t] }])
    pure (concat parts, RTVar subj)
  -- Applicant OF 70, 50000, FALSE
  App _ r args | Just rd <- recordOf ctx (getUnique r), not (null args) -> do
    -- zip would silently truncate, which would drop an input fact and leave the
    -- query with a model the L4 evaluator never had.
    unless (length args == length rd.rrFields) $
      bailIn env (rangeOf (App emptyAnno r args)) (LEUnsupported "record literal arity")
        ( "the record literal supplies " <> Text.textShow (length args)
            <> " argument(s) for " <> Text.textShow (length rd.rrFields) <> " stored field(s)" )
    subj <- freshVar (Text.take 1 rd.rrName.rnBase <> "0")
    parts <- forM (zip rd.rrFields args) \(fd, v) -> do
      (inner, t) <- queryArg ctx env v
      pure (inner <> [MkRFact { rfaPred = fd.rfName, rfaArgs = [RTVar subj, t] }])
    pure (concat parts, RTVar subj)
  -- A list of record literals flattens elementwise: each element gets its own
  -- subject variable and its own facts, and the list term is built from those
  -- subjects. Falling through to 'anfTerm' instead would reject the whole
  -- directive ("record literal in a rule body") and silently cost the
  -- differential harness a seed.
  List _ es -> do
    parts <- traverse (queryArg ctx env) es
    pure (concatMap fst parts, rTermList (map snd parts))
  e -> do
    (gs, t) <- anfTerm ctx env e
    unless (null gs) $
      bailIn env (rangeOf e) (LEUnsupported "computed query input")
        "a query input must be a literal or a record literal"
    pure ([], t)
 where
  fieldName c f = maybe (rName f) (.rfName) (Map.lookup (getUnique f) c.ctxFields)

-- ---------------------------------------------------------------------------
-- Signed dependency graph and stratification
-- ---------------------------------------------------------------------------

-- | One edge per @(caller, callee, sign)@ triple.
--
-- __Deviation from @m1-design\/lower-plan.md@ §3.11__, which says one edge per
-- /occurrence/: multiplicity carries no information the clause list does not
-- already carry, and it makes the Debug golden restate the same edge once per
-- projection. Order is first-occurrence order.
--
-- __A sign comes from the goal, never from its position.__ An earlier version
-- signed every goal inside 'rcGuardPrefix' negative, on the reasoning that a
-- materialised prefix is a negation. It is — but the negation was already
-- pushed into the literals before the prefix was built (see 'toBForm'), so what
-- the prefix contains is the /lowering/ of ¬g, and a call or projection
-- surviving in it is a positive occurrence: @NOT (q x AT LEAST 5)@ lowers to
-- @q(X, V), V \< 5@, which needs @q@'s value, positively. Signing by position
-- therefore invented negative edges the source never had, which can only push a
-- predicate up a stratum or report a stratified program as unstratified — and
-- Blawx rejects a non-stratified program in v1.
--
-- Two goal shapes carry a negation: an 'RNotCall', and a call or projection
-- whose OUTPUT variable a later 'RUnify' falsifies. The second is how @NOT@ over
-- a projected or computed boolean lowers (@'RProj' a isVeteran V, 'RUnify' V
-- 'False'@ — the shape a Blawx emitter peepholes to @-is_veteran(A)@), and
-- catching it is what keeps a negated boolean /decision/ from looking like a
-- positive dependency wherever it is written, prefix or not.
buildDepGraph :: [RPred] -> [RDepEdge]
buildDepGraph preds = nubOrdOn key (concatMap fromPred preds)
 where
  key e = (e.redFrom.rnUnique, e.redTo.rnUnique, e.redSign)
  -- Which predicates carry an output argument, so that the last term of a call
  -- can be told from an ordinary input. A callee absent here (there is none in a
  -- well-formed program) is treated as having none, which signs positive — the
  -- conservative direction for a graph whose consumer rejects on negative edges.
  hasOut = Map.fromList [ (p.rpName.rnUnique, isJust p.rpResult) | p <- preds ]
  fromPred p = concatMap (fromClause p) p.rpClauses
  fromClause p c =
    [ MkRDepEdge { redFrom = p.rpName, redTo = tgt, redSign = sgn }
    | g <- flat
    , (tgt, neg) <- goalTargets g
    , let sgn = if neg || falsifiedOut g then RNegative else RPositive
    ]
   where
    -- A findall body's goals are goals of this clause for dependency purposes;
    -- flattening them here (rather than recursing in 'goalTargets') is what lets
    -- the falsification set see a @V = FALSE@ that sits beside them.
    flat = concatMap flatten c.rcBody
    falsified = Set.fromList [ v.rvId | RUnify v (RTBool False) <- flat ]
    falsifiedOut g = maybe False (\v -> Set.member v.rvId falsified) (outVar g)

  flatten g = case g of
    RFindAll _ gs _ -> g : concatMap flatten gs
    _               -> [g]

  -- The variable a goal binds as its result, if it has one.
  outVar = \case
    RProj _ _ v -> Just v
    RCall n ts
      | Map.findWithDefault False n.rnUnique hasOut
      , Just (RTVar v) <- listToMaybe (reverse ts) -> Just v
    _ -> Nothing

  goalTargets = \case
    RCall n _        -> [(n, False)]
    RNotCall n _     -> [(n, True)]
    RProj _ f _      -> [(f, False)]
    RFindAll{}       -> []
    RUnify{}         -> []
    RMatch{}         -> []
    RCmp{}           -> []
    REval{}          -> []
    RAggregate{}     -> []

-- | The dependency graph's strongly-connected components, in reverse
-- topological order (what 'stronglyConnComp' guarantees, and what
-- 'assignStratum' relies on).
--
-- Shared by 'stratify' and 'uncheckedCycles' so that the two cannot disagree
-- about what a component is: 'uncheckedCycles' decides what to report by
-- checking whether 'stratify' already reported it, which is only sound while
-- both see the same decomposition.
sccsOf :: [RPred] -> [RDepEdge] -> [SCC RName]
sccsOf preds edges = stronglyConnComp
    [ (n, n, [ e.redTo | e <- Map.findWithDefault [] n outEdges ]) | n <- names ]
 where
  names = nubOrd ([ p.rpName | p <- preds ] <> concatMap (\e -> [e.redFrom, e.redTo]) edges)
  outEdges = Map.fromListWith (<>) [ (e.redFrom, [e]) | e <- edges ]

-- | Apt–Blair–Walker, __recorded and not enforced__.
--
-- A non-stratified module lowers SUCCESSFULLY, carrying 'RUnstratified'. Turning
-- it into a 'LowerError' here would break the ASP leg before it exists: swipl
-- rejects a non-stratified program, Blawx rejects it in v1, and ASP treats it as
-- the source of the multiple stable models that are the entire point of that
-- leg. The rejection belongs in each emitter.
stratify :: [RPred] -> [RDepEdge] -> RStratification
stratify preds edges
  | not (null bad) = RUnstratified bad
  | otherwise      = RStratified strata
 where
  outEdges = Map.fromListWith (<>) [ (e.redFrom, [e]) | e <- edges ]
  sccs = sccsOf preds edges

  members = \case
    AcyclicSCC n -> [n]
    CyclicSCC ns -> ns

  -- A component is unstratified when a negative edge is INTERNAL to it.
  bad =
    [ ms
    | scc <- sccs
    , let ms = members scc
    , let s = Set.fromList ms
    , any (\e -> e.redSign == RNegative && Set.member e.redFrom s && Set.member e.redTo s) edges
    ]

  -- 'stronglyConnComp' returns components in reverse topological order, so every
  -- callee's stratum is already known when a caller is processed.
  compOf = Map.fromList [ (n, i) | (i, scc) <- zip [(0 :: Int) ..] sccs, n <- members scc ]

  strata = foldl' assignStratum mempty (zip [(0 :: Int) ..] sccs)

  assignStratum acc (i, scc) =
    let ms = members scc
        lvl = maximum (0 : [ lvlOf acc e | n <- ms, e <- Map.findWithDefault [] n outEdges
                           , Map.lookup e.redTo compOf /= Just i ])
    in foldl' (\a n -> Map.insert n lvl a) acc ms

  lvlOf acc e =
    Map.findWithDefault 0 e.redTo acc + (if e.redSign == RNegative then 1 else 0)

-- ---------------------------------------------------------------------------
-- The entry point
-- ---------------------------------------------------------------------------

-- | Lower a resolved module to the relational normal form.
--
-- Errors accumulate: a module with four out-of-fragment definitions reports four
-- diagnostics, in source order (which is the order this walks them, so no
-- re-sort is applied and a golden keeps witnessing the walk order).
lowerModule :: LowerOptions -> EntityInfo -> Module Resolved -> Either [LowerError] RelProgram
lowerModule opts ei m@(MkModule _ uri _) =
  case getExportedFunctions m of
    [] ->
      Left [ MkLowerError
               { errFn = "", errRange = Nothing, errKind = LENoExport
               , errMsg = "no @export-annotated DECIDE found to lower" } ]
    efs0 ->
      let efs = enrichParamTypes ei (enrichReturnTypes ei efs0)
          exps = Map.fromList [ (getUnique (decideRes ef.exportDecide), ef) | ef <- efs ]
          ctx = buildCtx ei exps m
          st0 = MkLState
                  { lsFresh = 0, lsErrs = [], lsNotes = [], lsAux = []
                  , lsUri = uri, lsMember = Nothing }
          (prog, st) = runState (assemble ctx opts m) st0
      in case st.lsErrs of
           []   -> Right prog
           errs -> Left errs

assemble :: Ctx -> LowerOptions -> Module Resolved -> State LState RelProgram
assemble ctx opts m = do
  let exported = [ td | td <- ctx.ctxTop, td.tdExported ]
      reach    = closureRefs ctx (foldMap (collectRefs . (.tdBody)) exported)
      helpers  = [ td | td <- ctx.ctxTop
                      , not td.tdExported
                      , getUnique td.tdRes `Set.member` reach ]
  computed <- catMaybes <$> traverse (attempt . lowerTop ctx opts) (exported <> helpers)
  queries  <- lowerQueries ctx m
  aux      <- gets (.lsAux)
  notes    <- gets (.lsNotes)
  let assumed = assumedInputPreds ctx (computed <> aux)
      inputs = inputPreds ctx (computed <> aux) <> assumed
      preds  = inputs <> computed <> aux
      abstract = reachableAbstract ctx preds
      deps   = buildDepGraph preds
      strata = stratify preds deps
  -- Recursion the structural check cannot see, because it is not SELF-reference:
  -- two definitions that call each other. Reported here, after the whole program
  -- is assembled, since no per-definition pass has the other definition.
  forM_ (uncheckedCycles preds deps strata) \e ->
    modify' (\s -> s { lsErrs = s.lsErrs <> [e] })
  pure MkRelProgram
    { rpgSource   = moduleSourceOf m
    , rpgTitle    = moduleTitleOf m
    , rpgRecords  = orderedRecords ctx
    , rpgAbstract = abstract
    , rpgEnums    = [ e | u <- ctx.ctxEnumOrder, Just e <- [Map.lookup u ctx.ctxEnums] ]
    , rpgPreds    = preds
    , rpgQueries  = queries
    , rpgDeps     = deps
    , rpgStrata   = strata
    , rpgFidelity = (emptyReport "relational") { notes = notes <> assumedNotes ctx assumed }
    }

-- | The module's records in source declaration order ('ctxRecOrder').
orderedRecords :: Ctx -> [RRecordDef]
orderedRecords ctx = [ r | u <- ctx.ctxRecOrder, Just r <- [Map.lookup u ctx.ctxRecords] ]

-- | Recursive cycles spanning two or more predicates, which M1 does not admit
-- and no per-definition check can see.
--
-- The self-reference checks are local: 'structuralClauses' certifies a
-- decreasing list argument, and 'lowerSpec' rejects any other call to the
-- definition's own name. Neither looks at a SECOND definition, so
-- @DECIDE p IF q x@ beside @DECIDE q IF p x@ lowered cleanly, reported
-- @stratified@, and looped forever in every Prolog-family target — an
-- out-of-fragment construct that lowers, which the M1 brief calls a bug in the
-- same breath as an in-fragment one that does not.
--
-- __A cycle that 'stratify' already reports is left alone.__ Non-stratification
-- is recorded and not enforced (IR constraint 8): a cycle through a negation is
-- the ASP leg's whole point, swipl and Blawx reject it themselves, and turning
-- it into a 'LowerError' here would break that leg before it exists — the
-- @unstratified.l4@ fixture exists to pin exactly that. What is left is the
-- purely positive cycle, which no leg is told about by anything else.
uncheckedCycles :: [RPred] -> [RDepEdge] -> RStratification -> [LowerError]
uncheckedCycles preds edges strata =
  [ MkLowerError
      { errFn    = lead.rnText
      , errRange = listToMaybe [ r | n <- ms, Just r <- [Map.lookup n.rnUnique ranges] ]
      , errKind  = LEUncheckedRecursion
      , errMsg   =
          "mutual recursion between " <> Text.intercalate " and " [ "`" <> n.rnBase <> "`" | n <- ms ]
            <> "; M1's one recursion warrant is a structurally decreasing list argument in a"
            <> " definition's own body"
      }
  | CyclicSCC ms <- sccsOf preds edges
  , not (recordedByStratification ms)
  , not (structuralSelfLoop ms)
  , Just lead <- [listToMaybe ms]
  ]
 where
  ranges = Map.fromList [ (p.rpName.rnUnique, r) | p <- preds, Just r <- [p.rpProv.rpvRange] ]
  recursions = Map.fromList [ (p.rpName.rnUnique, p.rpRecursion) | p <- preds ]

  -- The shape every admitted structural recursion has: one predicate, a positive
  -- edge to itself, and a warrant recorded on the predicate.
  structuralSelfLoop = \case
    [n] -> case Map.lookup n.rnUnique recursions of
             Just (RStructural _) -> True
             _                    -> False
    _   -> False

  recordedByStratification ms = case strata of
    RStratified _       -> False
    RUnstratified comps -> any (\c -> Set.fromList c == Set.fromList ms) comps

lowerTop :: Ctx -> LowerOptions -> TopDef -> L RPred
lowerTop ctx opts td = do
  let rs = sortOfType ctx.ctxSorts td.tdResultTy
  lowerSpec ctx opts MkDefSpec
    { dsName     = rName td.tdRes
    , dsKind     = RComputed
    , dsOuter    = []
    , dsParams   = [ (getUnique r, hintOf r, sortOfType ctx.ctxSorts t)
                   | (r, t) <- zip td.tdParams (td.tdParamTys <> repeat Nothing) ]
    , dsResult   = if isBoolSort rs then Nothing else Just rs
    , dsBody     = td.tdBody
    , dsCalls    = mempty
    , dsExported = td.tdExported
    , dsDesc     = td.tdDesc
    , dsNlg      = td.tdNlg
    , dsRef      = td.tdRef
    , dsProv     = MkRProv { rpvUnique = getUnique td.tdRes, rpvRange = td.tdRange }
    }

-- | The stored record fields the lowered program actually reads, as 'RInput'
-- predicates.
--
-- Only fields that a projection reached: a record declared but never projected
-- contributes an ontology entry ('rpgRecords') and no predicate, which keeps a
-- module's dead types out of the emitted signature.
--
-- Walked record by record in declaration order, and field by field within each,
-- rather than over the field map: see 'ctxRecOrder' for why a 'Unique'-keyed
-- iteration must not reach a golden.
inputPreds :: Ctx -> [RPred] -> [RPred]
inputPreds ctx preds =
  [ MkRPred
      { rpName      = fd.rfName
      , rpKind      = RInput
      , rpParams    = [RSRecord rd.rrName]
      , rpResult    = Just fd.rfSort
      , rpRecursion = RNonRecursive
      , rpClauses   = []
      , rpExported  = False
      , rpDesc      = fd.rfDesc
      , rpNlg       = fd.rfNlg
      , rpRef       = Nothing
      , rpProv      = MkRProv { rpvUnique = fd.rfName.rnUnique, rpvRange = Nothing }
      }
  | rd <- orderedRecords ctx
  , fd <- rd.rrFields
  , fd.rfName.rnUnique `Set.member` used
  ]
 where
  used = Set.fromList (concatMap fromPred preds)
  fromPred p = concatMap (concatMap fromGoal . (.rcBody)) p.rpClauses
  fromGoal = \case
    RProj _ f _     -> [f.rnUnique]
    RFindAll _ gs _ -> concatMap fromGoal gs
    _               -> []

-- | The top-level @ASSUME@s the lowered program actually calls, as 'RInput'
-- predicates — the second source of that kind (see 'RInput').
--
-- Same shape and same discipline as 'inputPreds': only the names a lowered
-- clause reached, walked in source declaration order rather than over a
-- 'Unique'-keyed map ('ctxRecOrder' says why). An @ASSUME@ nothing calls
-- contributes nothing and is not an error, exactly as an unprojected field is
-- not — that reachability gate is what makes the widening additive, since a
-- module with no @ASSUME@s cannot gain a predicate.
--
-- A refused @ASSUME@ ('adRefusal') can never be reached, because it has no
-- 'ctxSigs' entry, so no clause can carry a call to it: the filter here is
-- belt-and-braces against a future edit that adds one.
assumedInputPreds :: Ctx -> [RPred] -> [RPred]
assumedInputPreds ctx preds =
  [ MkRPred
      { rpName      = ad.adName
      , rpKind      = RInput
      , rpParams    = ad.adParams
      , rpResult    = ad.adResult
      , rpRecursion = RNonRecursive
      , rpClauses   = []
      , rpExported  = False
      , rpDesc      = ad.adDesc
      , rpNlg       = ad.adNlg
      , rpRef       = ad.adRef
      , rpProv      = MkRProv { rpvUnique = u, rpvRange = ad.adRange }
      }
  | u <- ctx.ctxAssumeOrder
  , Just ad <- [Map.lookup u ctx.ctxAssumeDefs]
  , isNothing ad.adRefusal
  , u `Set.member` called
  ]
 where
  called = Set.fromList (concatMap fromPred preds)
  fromPred p = concatMap (concatMap fromGoal . (.rcBody)) p.rpClauses
  fromGoal = \case
    RCall n _       -> [n.rnUnique]
    RNotCall n _    -> [n.rnUnique]
    RFindAll _ gs _ -> concatMap fromGoal gs
    _               -> []

-- | The fidelity notes an admitted @ASSUME@ owes: one for a sort the fragment
-- cannot name (mirroring 'lowerSpec' \'s @R-SORT@, since an input predicate does
-- not go through it) and one for a @TYPICALLY@ default that was dropped.
assumedNotes :: Ctx -> [RPred] -> [FidelityNote]
assumedNotes ctx assumed =
     [ MkFidelityNote
         { code     = "R-SORT"
         , severity = Lossy
         , element  = p.rpName.rnText
         , range    = p.rpProv.rpvRange
         , message  = "an ASSUMEd signature has a sort the M1 fragment cannot name; it is\
                      \ carried as opaque"
         , lost     = "the declared value type an ontology-bearing target (Blawx) needs"
         }
     | p <- assumed
     , RSOpaque _ <- p.rpParams <> maybeToList p.rpResult
     ]
  <> [ MkFidelityNote
         { code     = "R-TYPICALLY"
         , severity = Lossy
         , element  = p.rpName.rnText
         , range    = p.rpProv.rpvRange
         , message  = "a TYPICALLY default on an ASSUME is dropped: the name becomes an input\
                      \ predicate, and seeding it would answer the question the target's\
                      \ interview exists to ask"
         , lost     = "the default value"
         }
     | p <- assumed
     , Just ad <- [Map.lookup p.rpName.rnUnique ctx.ctxAssumeDefs]
     , ad.adTypically
     ]

-- | The @ASSUME@d types some emitted predicate's signature mentions, in source
-- declaration order.
--
-- Reachability again, and for a sharper reason than tidiness: an abstract
-- category that reached no signature has no declaration an emitter could hang
-- anything from, and Blawx's category block would then declare a category no
-- rule, fact or attribute ever names.
reachableAbstract :: Ctx -> [RPred] -> [RAbstractDef]
reachableAbstract ctx preds =
  [ ab
  | u <- ctx.ctxAbstractOrder
  , Just ab <- [Map.lookup u ctx.ctxAbstract]
  , u `Set.member` mentioned
  ]
 where
  mentioned = Set.fromList
    [ n.rnUnique
    | p <- preds
    , s <- p.rpParams <> maybeToList p.rpResult
    , n <- sortRefs s
    ]
  sortRefs = \case
    RSRecord n -> [n]
    RSEnum n   -> [n]
    RSList s   -> sortRefs s
    RSMaybe s  -> sortRefs s
    _          -> []
