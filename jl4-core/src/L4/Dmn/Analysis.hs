-- | DMN export Phase 4: the module-level call-graph analysis.
--
-- Everything here is a /measurement/ of the module — no IR, no XML. It answers
-- four questions "L4.Dmn.Lower" asks before it mints a single element
-- (@specs\/todo\/DMN-EXPORT-PROGRAM-MODEL-SPEC.md@ §2.1, §2.4, §2.5):
--
--   1. __Tiering__ (§2.1): is a parameterised @DECIDE@ a real λ (applied to two
--      or more distinct argument expressions — tier 2, Phase 5's
--      @businessKnowledgeModel@), or is every application the same (tier 1, so
--      the decision can be /un-lifted/: its parameters become module-level
--      @inputData@ and its call sites become bare FEEL names)?
--
--   2. __@DMN-SAFE@__ (§2.4.1): can the decision be certified total, pure and
--      deterministic? DMN has no @undefined@, only @null@, and @null@ reads as
--      @false@ in every consuming boolean position — so un-lifting a partial
--      decision turns L4's loud exception into a silent wrong answer.
--
--   3. __The population filter__ (§2.5.6): which decisions are test fixtures
--      (and their fixture-side helper closure), which are uncalled regulative
--      bodies, and which are inert prose carriers.
--
--   4. __Call-site strictness__ (§2.4.2): a @¬DMN-SAFE@ decision consumed only
--      from lazy positions (an @IF@\/@CONSIDER@ arm) is @D-PARTIAL@ at 'Lossy';
--      any strict consumer, or no consumer at all, makes it 'Blocking'.
--
-- __The polarity trap, written down so a later "simplification" can see it__:
-- 'cgCalls' and 'cgDirective' are kept separate because the two consumers want
-- opposite polarities. Tiering and totality (§2.1, §2.4) must EXCLUDE
-- directive (@#EVAL@\/@#ASSERT@\/@#TRACE@\/@#CHECK@) references — counting them
-- flips the measured tier-2 rate from ~4% to ~70% and inverts the analysis
-- (§2.4.3). The fixture criterion (§2.5.7 (b),(c)) must INCLUDE them — they
-- are its load-bearing evidence.
module L4.Dmn.Analysis
  ( -- * The call graph
    CallGraph (..)
  , CallSite (..)
  , Strictness (..)
  , buildCallGraph
    -- * Tiering (§2.1)
  , Tier (..)
  , tierOf
    -- * DMN-SAFE (§2.4.1)
  , SafetyInput (..)
  , SafetyIssue (..)
  , analyzeSafety
    -- * The population filter (§2.5.6, §2.5.7)
  , PopulationInput (..)
  , PopulationVerdict (..)
  , DropReason (..)
  , classifyPopulation
    -- * Shared helpers
  , decideParams
  , nonexhaustiveDecides
  ) where

import Base
import qualified Base.Text as Text
import Data.Graph (SCC (..), stronglyConnComp)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Optics (gplate, toListOf)

import L4.Annotation (Anno_ (..), getAnno)
import L4.Desugar (carameliseExpr)
import qualified L4.Export as Export
import L4.Parser.SrcSpan (SrcRange (..))
import L4.Syntax
import qualified L4.TypeCheck as TC

------------------------------------------------------------------------
-- The call graph
------------------------------------------------------------------------

-- | Whether a reference sits in a position a DMN engine is certain to
-- evaluate ('StrictPos') or one it only evaluates when an enclosing
-- conditional selects it ('LazyPos' — a @THEN@\/@ELSE@ arm of an @IF@ that
-- lowers to a FEEL @if@, or a @CONSIDER@ arm body, which lowers to a
-- single-hit table's output entry, of which exactly one is used). Once lazy,
-- always lazy: a strict sub-position of a lazy arm is still only reached when
-- the arm is.
data Strictness = StrictPos | LazyPos
  deriving stock (Eq, Ord, Show)

-- | One reference to a top-level decide, from a decide body, a non-@Decide@
-- top-level declaration, or a directive.
data CallSite = MkCallSite
  { csCaller  :: !(Maybe Unique)
    -- ^ the enclosing decide; 'Nothing' when the site is in a directive or a
    -- non-@Decide@ top-level declaration.
  , csArgs    :: ![Expr Text]
    -- ^ argument expressions, positional, 'clearAnno'd AND with every
    -- reference collapsed to its raw name. The name-collapse is load-bearing
    -- for tiering: two callers passing their own same-named @issuer@ binder
    -- pass references with DIFFERENT 'Unique's, and comparing by 'Unique'
    -- would flip the whole corpus to tier 2 (measured: D-SCOPE stayed at 8
    -- of 9 on regcf-corpus, where the ruled criterion measures tier 2 at
    -- 4.8%). Comparing by name is what the merge itself licenses — the
    -- same-named parameters become ONE input. For 'AppNamed' the
    -- typechecker's stored order is applied when present.
  , csApplied :: !Bool
    -- ^ 'True' when the reference is the applied head of the application,
    -- 'False' for a bare (higher-order or 0-ary) reference.
  , csStrict  :: !Strictness
  , csRange   :: !(Maybe SrcRange)
  }

data CallGraph = MkCallGraph
  { cgCalls          :: !(Map Unique [CallSite])
    -- ^ non-directive references only, keyed by CALLEE. Feeds tiering,
    -- totality and @FIXTURE(a)@.
  , cgDirective      :: !(Map Unique [CallSite])
    -- ^ @#EVAL@\/@#ASSERT@\/@#TRACE@\/@#CHECK@\/@#CONTRACT@ references only,
    -- keyed by CALLEE. Feeds @FIXTURE(b)@,(c).
  , cgDirectiveHeads :: !(Set Unique)
    -- ^ decides that are the /tested subject/ of some directive — the applied
    -- (or bare) head of the directive's expression, descending through
    -- comparison and boolean connectives. @#ASSERT (Day (f x)) EQUALS d@ has
    -- heads @{Day}@, so @f@ is in argument position there — the
    -- @`relevant date`@ shape §2.5.7 pins.
  }

-- | Build the one call graph every Phase 4 consumer reads. (§2.5.1 measured
-- the binder-shadow and non-@Decide@ sensitivities at zero; references are
-- matched by resolved 'Unique', so lexical shadowing is already accounted for
-- by name resolution itself.)
buildCallGraph
  :: [Decide Resolved]     -- ^ the module's top-level decides
  -> [Directive Resolved]  -- ^ the module's directives
  -> [Expr Resolved]       -- ^ expressions of other top-level declarations
  -> CallGraph
buildCallGraph decides directives otherExprs =
  MkCallGraph
    { cgCalls =
        Map.fromListWith (flip (<>))
          ( [ (callee, [site])
            | d <- decides
            , (callee, site) <- sitesIn (Just (getUnique (decideResolvedA d)))
                                  StrictPos (carameliseExpr (decideBodyA d))
            ]
              <> [ (callee, [site])
                 | e <- otherExprs
                 , (callee, site) <- sitesIn Nothing StrictPos (carameliseExpr e)
                 ]
          )
    , cgDirective =
        Map.fromListWith (flip (<>))
          [ (callee, [site])
          | dir <- directives
          , e <- directiveExprs dir
          , (callee, site) <- sitesIn Nothing StrictPos e
          ]
    , cgDirectiveHeads =
        Set.fromList
          [ getUnique h
          | dir <- directives
          , e <- directiveExprs dir
          , h <- directiveHeads e
          , Set.member (getUnique h) decideUniques
          ]
    }
 where
  decideUniques = Set.fromList (map (getUnique . decideResolvedA) decides)

  sitesIn :: Maybe Unique -> Strictness -> Expr Resolved -> [(Unique, CallSite)]
  sitesIn caller = walk
   where
    walk :: Strictness -> Expr Resolved -> [(Unique, CallSite)]
    walk s e = case e of
      App _ f es ->
        siteFor s f es <> concatMap (walk s) es
      AppNamed _ f nes mOrder ->
        siteFor s f (namedArgsPositional nes mOrder)
          <> concatMap (\(MkNamedExpr _ _ x) -> walk s x) nes
      IfThenElse _ c t f ->
        walk s c <> walk LazyPos t <> walk LazyPos f
      MultiWayIf _ gexprs oth ->
        concat [walk s g <> walk LazyPos b | MkGuardedExpr _ g b <- gexprs]
          <> walk LazyPos oth
      Consider _ scrut brs ->
        walk s scrut
          <> concat
               [ concatMap (walk s) (toListOf (gplate @(Expr Resolved)) lhs)
                   <> walk LazyPos body
               | MkBranch _ lhs body <- brs
               ]
      -- WHERE/LET local bodies are analyzed at the strictness of the
      -- enclosing position, conservatively: 'L4.Dmn.Lower.peelLocals'
      -- inlines them, so their true position is wherever they are used.
      _ -> concatMap (walk s) (toListOf (gplate @(Expr Resolved)) e)

    siteFor s f es
      | Set.member (getUnique f) decideUniques =
          [ ( getUnique f
            , MkCallSite
                { csCaller  = caller
                , csArgs    = map (fmap nameKey . clearAnno) es
                , csApplied = not (null es)
                , csStrict  = s
                , csRange   = rangeOfResolved f
                }
            )
          ]
      | otherwise = []

  -- Caramelised, and this is load-bearing for 'directiveHeads': the checker
  -- desugars @a EQUALS b@ into an application of the builtin @__EQUALS__@, so
  -- on the raw tree the head of @#ASSERT rule x EQUALS 42@ is the builtin and
  -- @rule@ would silently stop being a directive head — which flips its
  -- fixture verdict.
  directiveExprs :: Directive Resolved -> [Expr Resolved]
  directiveExprs = map carameliseExpr . \case
    LazyEval _ e      -> [e]
    LazyEvalTrace _ e -> [e]
    Check _ e         -> [e]
    Assert _ e        -> [e]
    Contract _ a b cs -> a : b : cs

  -- The tested SUBJECT(s) of a directive expression: the applied (or bare)
  -- head, descending through comparisons and boolean connectives — so
  -- @#ASSERT f x EQUALS y@ tests @f@, while @#ASSERT (Day (f x)) EQUALS y@
  -- tests @Day@ and uses @f@ in argument position.
  directiveHeads :: Expr Resolved -> [Resolved]
  directiveHeads = \case
    App _ f _        -> [f]
    AppNamed _ f _ _ -> [f]
    Equals _ a b     -> directiveHeads a <> directiveHeads b
    Leq _ a b        -> directiveHeads a <> directiveHeads b
    Geq _ a b        -> directiveHeads a <> directiveHeads b
    Lt _ a b         -> directiveHeads a <> directiveHeads b
    Gt _ a b         -> directiveHeads a <> directiveHeads b
    And _ a b        -> directiveHeads a <> directiveHeads b
    Or _ a b         -> directiveHeads a <> directiveHeads b
    Not _ a          -> directiveHeads a
    Implies _ a b    -> directiveHeads a <> directiveHeads b
    _                -> []

namedArgsPositional :: [NamedExpr Resolved] -> Maybe [Int] -> [Expr Resolved]
namedArgsPositional nes mOrder = case mOrder of
  Just order | length order == length nes ->
    map snd (sortOn fst (zip order [x | MkNamedExpr _ _ x <- nes]))
  _ -> [x | MkNamedExpr _ _ x <- nes]

rangeOfResolved :: Resolved -> Maybe SrcRange
rangeOfResolved r = (getAnno (TC.getName r)).range

-- | The tiering comparison's name key: the defining occurrence's raw name.
nameKey :: Resolved -> Text
nameKey = rawNameToText . rawName . getOriginal

------------------------------------------------------------------------
-- Tiering (§2.1)
------------------------------------------------------------------------

data Tier = Tier1 | Tier2
  deriving stock (Eq, Show)

-- | Tier 1 iff every non-directive reference carries the same argument
-- expressions (compared modulo annotation, positionally) — vacuously true when
-- there are no such references at all, which is 27% of the measured population
-- (§2.4.3). A bare higher-order reference alongside an applied one is two
-- distinct shapes and therefore tier 2.
tierOf :: CallGraph -> Unique -> Tier
tierOf cg u = case Map.findWithDefault [] u cg.cgCalls of
  []       -> Tier1
  (s : ss)
    | all (\s' -> s'.csArgs == s.csArgs && s'.csApplied == s.csApplied) ss -> Tier1
    | otherwise -> Tier2

------------------------------------------------------------------------
-- DMN-SAFE (§2.4.1)
------------------------------------------------------------------------

-- | What the safety analysis needs from the checker and the module, none of
-- which the @Module Resolved@ alone carries.
data SafetyInput = MkSafetyInput
  { siMissingRanges  :: ![SrcRange]
    -- ^ source ranges of the checker's @PatternMatchesMissing@ warnings (L1's
    -- first disjunct). The exhaustiveness oracle
    -- ('L4.TypeCheck.constructorsInScopeFromEntityInfo') is what makes these
    -- sound for imported enums, @WHERE@-scoped @CONSIDER@s, @MAYBE@,
    -- @BOOLEAN@ and @LIST@ — Phase 0.5, vendored onto this line before
    -- Phase 4 was built.
  , siNonexhaustive  :: !(Set Unique)
    -- ^ decides carrying @\@nonexhaustive@ — the author's own declaration that
    -- the match is incomplete (L2). A REJECT signal, never a remedy.
  , siEnumFields     :: !(Map Unique [(Text, Set Text)])
    -- ^ for each multi-constructor @IS ONE OF@ type: constructor name and the
    -- set of field names it declares (L11).
  , siComponentTypes :: !(Map Unique [Type' Resolved])
    -- ^ for each declared type: its components' types, for L7's TRANSITIVE
    -- function-component test (@runBinOpEquals@ recurses componentwise, so a
    -- plain record with a function field escapes a head-type test).
  , siSubst          :: !TC.Substitution
  , siUri            :: !NormalizedUri
  }

-- | One reason a decision could not be certified @DMN-SAFE@. The wording
-- obligation (§2.4.4): the note built from this must say /not certified
-- total/, never /is partial/ — the don't-know cases (suppressed analyses,
-- non-structural recursion, statically-safe uses of L3–L6) are refusals to
-- certify, not proofs of partiality. And it must never offer
-- @\@nonexhaustive@ as a remedy — that decorator is a reject signal (L2).
data SafetyIssue = MkSafetyIssue
  { safClause :: !Text            -- ^ e.g. @"L3"@, @"PURE"@, @"TERMINATES"@
  , safRange  :: !(Maybe SrcRange)
  , safDetail :: !Text
  }

-- | Certify each decide @DMN-SAFE@ or collect the clauses that refused.
--
-- @TOTAL@ is the GREATEST fixed point over the call graph (§2.4.1: the least
-- solution reads @T(sum) = True ∧ T(sum)@ and rejects @sum@, @map@, @filter@
-- and every list-touching decision; the spec records that "least" was written
-- first and rejected the whole design). It is computed over the call graph's
-- CONDENSATION, callees before callers ('stronglyConnComp' emits SCCs reverse
-- topologically sorted, so every component only calls into components already
-- folded). Source order proves nothing here: forward references are legal L4
-- (@l4 check@ accepts a caller defined before its callee), and an earlier
-- source-order fold silently certified any caller defined before its
-- ¬DMN-SAFE callee — the exact silent-null direction §2.4 exists to close.
-- Within the condensation: a singleton component takes its local clauses plus
-- one @TOTAL@ issue per uncertified callee; a self-loop is discharged (or
-- refused) by the structural termination check; and a cyclic component of
-- size > 1 is MUTUAL recursion, which @TERMINATES@ rejects in v1 on every
-- member — a refusal to certify, not a proof of divergence — so no member
-- un-lifts.
--
-- __Known gap, stated rather than glossed__: cross-module callees.
-- 'L4.Dmn.Lower' drops names from other modules by design (that is what keeps
-- every prelude function out of the DRG), so the fixpoint cannot see user
-- imports. A partial imported decision is invisible here; prelude callees are
-- covered by the structural termination check having certified the prelude's
-- own recursion shapes.
--
-- @StackOverflow@ has no syntactic image and is not an independent clause: it
-- is a resource bound (@pushFrame@). @DMN-SAFE@ claims definedness for
-- well-founded evaluation, not evaluation under a fixed frame budget. And a
-- reference to an @ASSUME@d term is deliberately NOT partial — @Stuck@ is the
-- /input/ channel, and reading it as partial rejects the entire
-- @ASSUME@-style corpus, flagship exhibit included.
analyzeSafety
  :: SafetyInput
  -> CallGraph
  -> [Decide Resolved]
  -> Map Unique [SafetyIssue]   -- ^ a decide absent from the map is certified safe
analyzeSafety inp cg decides =
  foldl' step Map.empty sccs   -- condensation order: callees before callers
 where
  byUnique = Map.fromList [(getUnique (decideResolvedA d), d) | d <- decides]

  -- callee list per CALLER, from the callee-keyed graph
  calleesOf :: Unique -> [Unique]
  calleesOf u = nubOrd
    [ callee
    | (callee, sites) <- Map.toList cg.cgCalls
    , any (\s -> s.csCaller == Just u) sites
    ]

  sccs :: [SCC (Decide Resolved)]
  sccs = stronglyConnComp
    [ (d, u, calleesOf u)
    | d <- decides
    , let u = getUnique (decideResolvedA d)
    ]

  step acc = \case
    AcyclicSCC d  -> record acc d (singleIssues acc d)
    -- a one-member cycle is SELF-recursion; 'selfRecursionIssues' (inside
    -- 'decideIssues') discharges or refuses it structurally
    CyclicSCC [d] -> record acc d (singleIssues acc d)
    CyclicSCC ds  ->
      let cycleUs = Set.fromList [getUnique (decideResolvedA d) | d <- ds]
      in foldl'
           ( \a d ->
               record a d
                 ( decideIssues d
                     <> [mutualIssue cycleUs d]
                     -- callees INSIDE the cycle are excluded: every member
                     -- already carries the TERMINATES issue above, and at
                     -- this point none of them is in @a@ yet
                     <> calleeIssues a cycleUs d
                 )
           )
           acc ds

  record acc d is =
    if null is then acc else Map.insert (getUnique (decideResolvedA d)) is acc

  singleIssues acc d = decideIssues d <> calleeIssues acc Set.empty d

  -- the TOTAL conjunct: @∀ c ∈ calls(d). TOTAL(c)@, read off the accumulator,
  -- which the condensation order guarantees already holds every callee's
  -- verdict (minus the exclusions the caller passes)
  calleeIssues :: Map Unique [SafetyIssue] -> Set Unique -> Decide Resolved -> [SafetyIssue]
  calleeIssues acc excluded d =
    [ MkSafetyIssue
        { safClause = "TOTAL"
        , safRange  = Nothing
        , safDetail =
            "calls `" <> maybe "?" decideNameA (Map.lookup c byUnique)
              <> "`, which could not itself be certified total"
        }
    | let u = getUnique (decideResolvedA d)
    , c <- calleesOf u
    , c /= u
    , not (Set.member c excluded)
    , Map.member c acc
    ]

  -- Mutual recursion rejects in v1 (the TERMINATES ruling): no structural
  -- measure spans a cycle of decisions, and an un-lifted cycle would emit
  -- mutually requiring <decision> elements — a DMN 1.3 §6.3.2 acyclicity
  -- violation. Wording per §2.4.4: a refusal to certify, never a proof.
  mutualIssue :: Set Unique -> Decide Resolved -> SafetyIssue
  mutualIssue cycleUs d =
    MkSafetyIssue
      { safClause = "TERMINATES"
      , safRange  = (getAnno d).range
      , safDetail =
          "mutually recursive with "
            <> Text.intercalate ", "
                 [ "`" <> maybe "?" decideNameA (Map.lookup u' byUnique) <> "`"
                 | u' <- Set.toList (Set.delete (getUnique (decideResolvedA d)) cycleUs)
                 ]
            <> "; mutual recursion could not be certified terminating (v1 has no \
               \structural measure that spans a cycle of decisions)"
      }

  decideIssues :: Decide Resolved -> [SafetyIssue]
  decideIssues d@(MkDecide dAnn _ _ rawBody) =
    let u    = getUnique (decideResolvedA d)
        body = carameliseExpr rawBody
    in [ MkSafetyIssue "L2" dAnn.range
           "the definition is decorated @nonexhaustive: its author declares the match incomplete"
       | Set.member u inp.siNonexhaustive
       ]
         <> selfRecursionIssues d body
         <> walkIssues StrictPos body

  ----------------------------------------------------------------------
  -- LOCALLY-TOTAL, PURE, DETERMINISTIC: one strictness-tracking walk
  ----------------------------------------------------------------------

  -- Partial OPERATIONS (L3–L6) are rejected only in strict positions: an
  -- @IF d EQUALS 0 THEN 0 ELSE n / d@ in ONE decision is accepted (the guard
  -- and the division travel together into one FEEL @if@), and the same
  -- division is rejected when the guard lives in a different decision — which
  -- is exactly the configuration un-lifting would create (§2.4.2).
  walkIssues :: Strictness -> Expr Resolved -> [SafetyIssue]
  walkIssues s e = case e of
    IfThenElse _ c t f ->
      walkIssues s c <> walkIssues LazyPos t <> walkIssues LazyPos f
    MultiWayIf _ gexprs oth ->
      concat [walkIssues s g <> walkIssues LazyPos b | MkGuardedExpr _ g b <- gexprs]
        <> walkIssues LazyPos oth
    Consider _ scrut brs ->
      considerIssues s e brs
        <> walkIssues s scrut
        <> concat [walkIssues LazyPos body | MkBranch _ _ body <- brs]
    Where _ body decls ->
      localGroupIssues e decls <> walkIssues s body <> concatMap (localIssuesOf s) decls
    LetIn _ decls body ->
      localGroupIssues e decls <> walkIssues s body <> concatMap (localIssuesOf s) decls
    DividedBy _ a b ->
      [ issue "L3" e "a division whose divisor is not a nonzero numeric literal can raise DivisionByZero, which has no FEEL image (the result is null)"
      | s == StrictPos, not (nonzeroLiteral b)
      ]
        <> walkIssues s a <> walkIssues s b
    Modulo _ a b ->
      [issue "L4" e "MODULO can raise NotAnInteger" | s == StrictPos]
        <> walkIssues s a <> walkIssues s b
    Equals _ a b ->
      [ issue "L7" e "EQUALS at a type whose transitive component structure contains a function or CONTRACT type raises EqualityOnUnsupportedType"
      | s == StrictPos
      , any (typeHasFunctionComponent . operandType) [a, b]
      ]
        <> walkIssues s a <> walkIssues s b
    AsString _ a ->
      [ issue "L8" e "AS STRING at a non-primitive type raises UserError"
      | s == StrictPos, not (primitiveOperand a)
      ]
        <> walkIssues s a
    Proj _ base fld ->
      [ issue "L11" e
          ("the projection `" <> unqualifiedNameToText (TC.getName fld)
             <> "` scrutinises a multi-constructor IS ONE OF whose constructors do not all declare that field; \
                \the selector application raises NonExhaustivePatterns at run time even though no CONSIDER is in sight")
      | s == StrictPos
      , Just ctors <- [enumOfOperand base]
      , length ctors > 1
      , not (all (\(_, fs) -> Set.member (unqualifiedNameToText (TC.getName fld)) fs) ctors)
      ]
        <> walkIssues s base
    App _ f es ->
      builtinAppIssues s e (getUnique f) es
        <> concatMap (walkIssues s) es
    Fetch _ a  -> issue "PURE" e "FETCH performs I/O" : walkIssues s a
    Post _ a b c ->
      issue "PURE" e "POST performs I/O"
        : concatMap (walkIssues s) [a, b, c]
    Env _ a    -> issue "PURE" e "GETENV reads the environment" : walkIssues s a
    Record {}  -> [issue "PURE" e "RECORD/COMMIT/ATTEST writes the ledger"]
    ReadCell {} -> [issue "PURE" e "RECALL reads the ledger"]
    _ -> concatMap (walkIssues s) (toListOf (gplate @(Expr Resolved)) e)

  builtinAppIssues :: Strictness -> Expr Resolved -> Unique -> [Expr Resolved] -> [SafetyIssue]
  builtinAppIssues s e u es
    | s == StrictPos, u == TC.exponentUnique =
        [issue "L4" e "TO THE POWER OF can produce NaN/Infinity"]
    | s == StrictPos, u == TC.splitUnique
    , not (case es of (_ : delim : _) -> nonEmptyStringLiteral delim; _ -> False) =
        [issue "L4" e "SPLIT with a non-literal or empty delimiter raises at run time"]
    | s == StrictPos, u `elem` [TC.sqrtUnique, TC.lnUnique, TC.log10Unique, TC.asinUnique, TC.acosUnique] =
        [issue "L5" e "SQRT/LN/LOG10/ASIN/ACOS can produce NaN outside their domain"]
    | s == StrictPos
    , u `elem` [TC.dateFromDMYUnique, TC.timeFromHMSUnique, TC.datetimeFromDTZUnique]
    , not (all isLiteralExpr es) =
        [issue "L6" e "a date/time constructor with a non-literal argument can raise UserError"]
    | s == StrictPos, u `elem` [TC.datetimeDateUnique, TC.datetimeTimeUnique] =
        [issue "L6" e "the DATE/TIME projections off a DATETIME can raise UserError"]
    | u `elem` [ TC.everBetweenUnique, TC.alwaysBetweenUnique
               , TC.whenLastUnique, TC.whenNextUnique, TC.valueAtUnique ] =
        [issue "L9" e "temporal ledger operators have no DMN lowering and can raise UserError"]
    -- DETERMINISTIC, kept separate from L10 because the remedy differs: a
    -- clock reader wants "synthesise today as an inputData", not a fallback.
    -- RULES EFFECTIVE DATE is deliberately NOT here: this exporter already
    -- binds law time as an inputData (§15.2), so reading it is deterministic
    -- in the emitted artifact.
    | u `elem` [TC.todaySerialUnique, TC.nowSerialUnique, TC.currentTimeUnique, TC.timezoneUnique] =
        [issue "DETERMINISTIC" e "reads the clock/timezone; the artifact would answer differently on different days"]
    | u == TC.jsonDecodeUnique =
        [issue "PURE" e "JSON DECODE can raise UserError"]
    | otherwise = []

  -- L1, both disjuncts, positioned: a CONSIDER in a strict position that the
  -- checker reported missing arms on (via the entityInfo-sourced oracle), OR
  -- whose analysis was suppressed (an opaque\/literal pattern; the primitive-
  -- scrutinee stand-down reaches here the same way, because those patterns
  -- are literal) and which has no OTHERWISE arm. The don't-know direction
  -- matters (§2.4.4): a suppressed analysis emits no warning, so warnings
  -- alone cannot certify — which is why the cheap scan-the-errors route is
  -- only half of this clause.
  considerIssues :: Strictness -> Expr Resolved -> [Branch Resolved] -> [SafetyIssue]
  considerIssues s whole brs
    | s /= StrictPos = []
    | reportedMissing =
        [issue "L1" whole "the checker reports this CONSIDER non-exhaustive (NonExhaustivePatterns at run time; null in FEEL)"]
    | suppressed && not hasOtherwise =
        [issue "L1" whole "this CONSIDER's exhaustiveness analysis was suppressed (opaque or literal patterns) and it has no OTHERWISE arm, so it could not be certified total"]
    | otherwise = []
   where
    mrange = (getAnno whole).range
    reportedMissing = case mrange of
      Nothing -> False
      Just r  -> any (rangeWithin r) inp.siMissingRanges
    suppressed = any branchOpaque brs
    hasOtherwise = any (\(MkBranch _ lhs _) -> case lhs of Otherwise _ -> True; When _ _ -> False) brs
    branchOpaque (MkBranch _ lhs _) = case lhs of
      Otherwise _ -> False
      When _ p    -> patOpaque p
    patOpaque = \case
      PatLit {}       -> True
      PatExpr {}      -> True
      PatVar {}       -> False
      PatApp _ _ ps   -> any patOpaque ps
      PatCons _ a b   -> patOpaque a || patOpaque b

  -- A checker warning attributed to this CONSIDER: its range sits inside the
  -- CONSIDER's own range, in the same module.
  rangeWithin :: SrcRange -> SrcRange -> Bool
  rangeWithin outer r =
    r.moduleUri == outer.moduleUri
      && r.start >= outer.start
      && r.end <= outer.end

  -- L12: WHERE/LET locals whose right-hand sides form a dependency cycle
  -- among themselves force a BlackholeForced. (Also required by TERMINATES,
  -- because those live inside the body rather than in @calls(d)@.)
  localGroupIssues :: Expr Resolved -> [LocalDecl Resolved] -> [SafetyIssue]
  localGroupIssues whole decls =
    [ issue "L12" whole "the WHERE/LET locals form a dependency cycle among themselves (BlackholeForced)"
    | hasCycle
    ]
   where
    locals =
      [ (getUnique n, refsOf b)
      | LocalDecide _ (MkDecide _ _ (MkAppForm _ n _ _) b) <- decls
      ]
    localSet = Set.fromList (map fst locals)
    refsOf b = Set.fromList
      [ getUnique r
      | r@Ref {} <- toList b
      , Set.member (getUnique r) localSet
      ]
    edges = Map.fromList locals
    hasCycle = any (dfs Set.empty) (map fst locals)
     where
      dfs path n
        | Set.member n path = True
        | otherwise =
            any (dfs (Set.insert n path))
              (Set.toList (Map.findWithDefault Set.empty n edges))

  localIssuesOf :: Strictness -> LocalDecl Resolved -> [SafetyIssue]
  localIssuesOf s = \case
    LocalDecide _ (MkDecide _ _ _ b) -> walkIssues s (carameliseExpr b)
    LocalAssume _ _                  -> []

  ----------------------------------------------------------------------
  -- TERMINATES: the structural check (§2.4.1)
  ----------------------------------------------------------------------

  -- A self-recursive @f@ structurally terminates if there is a parameter
  -- position @k@ such that every recursive call passes, in position @k@, a
  -- variable bound by a @FOLLOWED BY@ pattern of a @CONSIDER@ whose scrutinee
  -- is transitively parameter @k@. That certifies @foldr@\/@map@\/@filter@\/
  -- @sum@ and the corpus's @ror together@ shape automatically;
  -- @NUMBER@-measure recursion (@f (n - 1)@) rejects in v1 — a don't-know,
  -- not a proof of divergence, and the wording must say so.
  selfRecursionIssues :: Decide Resolved -> Expr Resolved -> [SafetyIssue]
  selfRecursionIssues d body
    | null selfCalls = []
    | structurallyTerminates = []
    | otherwise =
        [ MkSafetyIssue "TERMINATES" (getAnno d).range
            "self-recursion could not be certified structurally terminating (no parameter position decreases through a FOLLOWED BY pattern on every recursive call)"
        ]
   where
    selfU = getUnique (decideResolvedA d)
    params = map fst (decideParams d)

    allExprs = universeExpr body

    selfCalls =
      [es | App _ f es <- allExprs, getUnique f == selfU]

    structurallyTerminates = any positionOk (zip [0 :: Int ..] params)

    positionOk (k, p) = all (argDecreases k) selfCalls
     where
      -- S grows to a fixpoint: the parameter itself, then the TAIL binders of
      -- every CONSIDER whose scrutinee is already in S (recursing on the tail
      -- of a tail is still a decrease).
      decreasing = grow (Set.singleton (getUnique p))
      grow s =
        let s' = Set.union s (Set.fromList (tailBindersOf s))
        in if Set.size s' == Set.size s then s else grow s'
      tailBindersOf s =
        [ getUnique tb
        | Consider _ scrut brs <- allExprs
        , Just su <- [scrutVar scrut]
        , Set.member su s
        , MkBranch _ (When _ (PatCons _ _ tailPat)) _ <- brs
        , tb <- patBinders tailPat
        ]
      argDecreases k' es = case drop k' es of
        (App _ v [] : _) ->
          Set.member (getUnique v) (Set.delete (getUnique p) decreasing)
        _ -> False

    scrutVar = \case
      App _ v [] -> Just (getUnique v)
      _          -> Nothing

    patBinders = \case
      PatVar _ n     -> [n]
      PatApp _ _ ps  -> concatMap patBinders ps
      PatCons _ a b  -> patBinders a <> patBinders b
      PatExpr _ _    -> []
      PatLit _ _     -> []

  ----------------------------------------------------------------------
  -- Type plumbing
  ----------------------------------------------------------------------

  operandType :: Expr Resolved -> Maybe (Type' Resolved)
  operandType e = case (getAnno e).extra.resolvedInfo of
    Just (TypeInfo ty _) -> Just (TC.applyFinalSubstitution inp.siSubst inp.siUri ty)
    _                    -> Nothing

  primitiveOperand :: Expr Resolved -> Bool
  primitiveOperand e = case operandType e of
    Just (TyApp _ r []) ->
      getUnique r `elem`
        [ TC.numberUnique, TC.stringUnique, TC.booleanUnique
        , TC.dateUnique, TC.timeUnique, TC.datetimeUnique
        ]
    _ -> False

  enumOfOperand :: Expr Resolved -> Maybe [(Text, Set Text)]
  enumOfOperand e = case operandType e of
    Just (TyApp _ r _) -> Map.lookup (getUnique r) inp.siEnumFields
    _                  -> Nothing

  -- L7's transitive walk: a function or CONTRACT type anywhere in the
  -- component structure, through declared records, with a visited set for
  -- recursive types.
  typeHasFunctionComponent :: Maybe (Type' Resolved) -> Bool
  typeHasFunctionComponent = maybe False (go Set.empty)
   where
    go seen = \case
      Fun {} -> True
      TyApp _ r ts ->
        let u = getUnique r
        in u == TC.contractUnique
             || any (go seen) ts
             || ( not (Set.member u seen)
                    && any (go (Set.insert u seen))
                        (Map.findWithDefault [] u inp.siComponentTypes)
                )
      Forall _ _ ty -> go seen ty
      _ -> False

  nonzeroLiteral :: Expr Resolved -> Bool
  nonzeroLiteral = \case
    Lit _ (NumericLit _ r) -> r /= 0
    _                      -> False

  nonEmptyStringLiteral :: Expr Resolved -> Bool
  nonEmptyStringLiteral = \case
    Lit _ (StringLit _ t) -> not (Text.null t)
    _                     -> False

  isLiteralExpr :: Expr Resolved -> Bool
  isLiteralExpr = \case
    Lit _ _ -> True
    _       -> False

  issue :: Text -> Expr Resolved -> Text -> SafetyIssue
  issue clause e detail = MkSafetyIssue clause (getAnno e).range detail

-- | Every expression node, the node itself included.
universeExpr :: Expr Resolved -> [Expr Resolved]
universeExpr e = e : concatMap universeExpr (toListOf (gplate @(Expr Resolved)) e)

------------------------------------------------------------------------
-- The population filter (§2.5.6, §2.5.7)
------------------------------------------------------------------------

data PopulationInput = MkPopulationInput
  { piIncludeTests     :: !Bool
    -- ^ @--include-tests@: emit fixtures anyway, with no note.
  , piExternalRefNames :: !(Maybe (Set Text))
    -- ^ conjunct (d)'s importer view: the L4 names referenced by modules that
    -- import this one. 'Nothing' = the view is UNAVAILABLE, and the filter
    -- fails safe: nothing is dropped on an unverified conjunct — a
    -- report-only @D-FIXTURE@ advisory says what WOULD have been dropped.
    -- Dropping a decision on an unverified conjunct is how this rule deletes
    -- a statute (§2.5.7's @`relevant date`@, called from @ground-2ZA\/2ZB\/5F@
    -- while module-locally satisfying (a)+(b)+(c) exactly).
  , piForcedRef        :: !(Resolved -> Bool)
    -- ^ rule 4's notion of a reference that COUNTS: one that would become a
    -- decision edge or an @inputData@ — module-local, not a constructor, not
    -- a selector. Supplied by the caller because those sets live in
    -- "L4.Dmn.Lower".
  }

data DropReason
  = DroppedFixture        -- ^ satisfied @FIXTURE(a)–(d)@
  | DroppedFixtureHelper  -- ^ in the fixture-side transitive closure
  | DroppedRegulative     -- ^ uncalled regulative body
  deriving stock (Eq, Show)

data PopulationVerdict = MkPopulationVerdict
  { pvDropped           :: !(Map Unique DropReason)
  , pvFixtureUnverified :: !(Set Unique)
    -- ^ satisfied @FIXTURE(a)–(c)@ but (d) could not be checked (no importer
    -- view): KEPT, with a report-only advisory.
  , pvInert             :: !(Set Unique)
    -- ^ kept, uncalled, and the body forces no reference and no input.
  }

-- | The four buckets of §2.5.6, keyed off the one call graph. Rule 2's
-- closure is computed fixture-side and BEFORE rule 3 (re-seeding it live-side
-- after rule 3 measures 74.6%, which is not what is ruled — the ruled figure
-- is 46%).
--
-- __Honesty requirement (§2.5.8)__: rule 2's precision is 100% on the four
-- measured corpora, where every fixture happens to be reachable only from
-- directive arguments and every entry point happens to be tested — nothing in
-- L4 enforces either. It makes emission depend on @#ASSERT@ placement, so
-- adding a test can change the exported model. What overturns it: a
-- parameterised fixture builder also called from a decision body, or a
-- genuine statutory entry point with no directive reference and no callers
-- that is not inert prose. Either forces @--include-tests@ to default ON and
-- demotes the filter to a lint. (@\@export@ is the principled replacement and
-- cannot be the v1 criterion: three of the four corpora contain zero
-- @\@export@ decorations, so it would emit an empty model for them.)
classifyPopulation
  :: PopulationInput
  -> CallGraph
  -> [Decide Resolved]
  -> PopulationVerdict
classifyPopulation inp cg decides =
  MkPopulationVerdict
    { pvDropped = dropped
    , pvFixtureUnverified =
        if inp.piIncludeTests then Set.empty else unverified
    , pvInert = inertSet (Map.keysSet dropped)
    }
 where
  dropped :: Map Unique DropReason
  dropped
    | inp.piIncludeTests =
        Map.fromList [(u, DroppedRegulative) | u <- regulativeDrops Set.empty]
    | otherwise =
        Map.fromList
          ( [(u, DroppedFixture) | u <- Set.toList fixtureSeeds]
              <> [ (u, DroppedFixtureHelper)
                 | u <- Set.toList fixtureDropSet
                 , not (Set.member u fixtureSeeds)
                 ]
              <> [(u, DroppedRegulative) | u <- regulativeDrops fixtureDropSet]
          )

  byUnique = Map.fromList [(getUnique (decideResolvedA d), d) | d <- decides]

  bodyCallers :: Unique -> [Unique]
  bodyCallers u =
    nubOrd [c | s <- Map.findWithDefault [] u cg.cgCalls, Just c <- [s.csCaller]]

  -- references from non-Decide top-level declarations
  hasOtherRefs u =
    any (\s -> isNothing s.csCaller) (Map.findWithDefault [] u cg.cgCalls)

  directiveSites u = Map.findWithDefault [] u cg.cgDirective

  -- FIXTURE(a)–(c), module-local: no body or non-Decide reference; at least
  -- one directive reference ((b) is what keeps the unreferenced inert-prose
  -- carriers alive); never the tested subject of a directive.
  fixtureABC u =
    null (bodyCallers u)
      && not (hasOtherRefs u)
      && not (null (directiveSites u))
      && not (Set.member u cg.cgDirectiveHeads)

  -- conjunct (d): no caller in any module that imports this one.
  externallyClear :: Unique -> Maybe Bool
  externallyClear u = case inp.piExternalRefNames of
    Nothing    -> Nothing            -- view unavailable: fail safe
    Just names -> Just (not (Set.member (decideNameU u) names))

  decideNameU u = maybe "" decideNameA (Map.lookup u byUnique)

  fixtureSeeds :: Set Unique
  fixtureSeeds = Set.fromList
    [ u
    | u <- Map.keys byUnique
    , fixtureABC u
    , externallyClear u == Just True
    ]

  unverified :: Set Unique
  unverified = Set.fromList
    [ u
    | u <- Map.keys byUnique
    , fixtureABC u
    , isNothing (externallyClear u)
    ]

  -- The fixture-side transitive closure: a decide whose every body-caller is
  -- already fixture-side (and which HAS at least one — without that, every
  -- uncalled root joins vacuously and the rule deletes a statute), with no
  -- non-Decide references, not directly under test, and externally clear.
  fixtureDropSet :: Set Unique
  fixtureDropSet = grow fixtureSeeds
   where
    grow s =
      let s' = Set.union s (Set.fromList (helpers s))
      in if Set.size s' == Set.size s then s else grow s'
    helpers s =
      [ u
      | u <- Map.keys byUnique
      , not (Set.member u s)
      , let callers = bodyCallers u
      , not (null callers)
      , all (`Set.member` s) callers
      , not (hasOtherRefs u)
      , not (Set.member u cg.cgDirectiveHeads)
      , externallyClear u == Just True
      ]

  -- Rule 3, applied AFTER the fixture closure: an uncalled regulative body is
  -- routed to BPMN rather than emitted as a fake decision. Module-called
  -- regulatives stay in the DRG, still emitting raw L4 — they are §2.4.2's
  -- and §6.3-1's problem, and this rule must not be read as closing them.
  regulativeDrops :: Set Unique -> [Unique]
  regulativeDrops alreadyDropped =
    [ u
    | (u, d) <- Map.toList byUnique
    , not (Set.member u alreadyDropped)
    , exprIsRegulative (decideBodyA d)
    , null [c | c <- bodyCallers u, not (Set.member c alreadyDropped)]
    , not (hasOtherRefs u)
    ]

  -- Rule 4 (§2.5.6-4): kept, uncalled, and the body forces no reference and
  -- no input — NOT "the body is a literal". The corpus's dominant inert idiom
  -- is @"statutory text" ... TRUE@, which parses as 'And' over an 'Inert'
  -- node plus a constructor reference; a literal-shaped detector finds 19
  -- where the true population is ≥58, which is the point of the ruled
  -- predicate.
  inertSet :: Set Unique -> Set Unique
  inertSet droppedSet = Set.fromList
    [ u
    | (u, d) <- Map.toList byUnique
    , not (Set.member u droppedSet)
    , null [c | c <- bodyCallers u, not (Set.member c droppedSet)]
    , not (any inp.piForcedRef [r | r@Ref {} <- toList (decideBodyA d)])
    ]

exprIsRegulative :: Expr Resolved -> Bool
exprIsRegulative e =
  not $ null
    [ ()
    | c <- universeExpr e
    , case c of Regulative {} -> True; Event {} -> True; Breach {} -> True; _ -> False
    ]

------------------------------------------------------------------------
-- Shared helpers
------------------------------------------------------------------------

-- | A decide's @GIVEN@ binders with their declared types, positional.
decideParams :: Decide Resolved -> [(Resolved, Maybe (Type' Resolved))]
decideParams (MkDecide _ (MkTypeSig _ (MkGivenSig _ otns) _) _ _) =
  [(n, mty) | MkOptionallyTypedName _ n mty _ <- otns]

decideResolvedA :: Decide Resolved -> Resolved
decideResolvedA (MkDecide _ _ (MkAppForm _ n _ _) _) = n

decideNameA :: Decide Resolved -> Text
decideNameA = unqualifiedNameToText . getOriginal . decideResolvedA

decideBodyA :: Decide Resolved -> Expr Resolved
decideBodyA (MkDecide _ _ _ b) = b

-- | The decorator-driven L2 set for 'SafetyInput'.
nonexhaustiveDecides :: [Decide Resolved] -> Set Unique
nonexhaustiveDecides ds =
  Set.fromList
    [ getUnique (decideResolvedA d)
    | d <- ds
    , Export.isNonexhaustiveDecide d
    ]
