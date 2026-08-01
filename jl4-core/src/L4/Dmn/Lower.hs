-- | Lower a typechecked L4 module to the DMN 1.3 'Drg' IR.
--
-- The decision side of the Lexipedia-superset spine
-- (@specs\/todo\/lexipedia-superset\/SPEC.md@ §3): "L4.Viz.GuardedRows" normalises
-- @IF@ \/ @BRANCH@ \/ @CONSIDER@ into first-match rows, and this module is its
-- /second/ consumer — the first being the ladder. The correspondence is close to
-- definitional (GUARDED-ROWS.md §7):
--
-- > grRows in source order   ->  rules, in rule order
-- > grDisjoint = False       ->  hit policy First   (order-dependent, DMN 8.2.10)
-- > grDisjoint = True        ->  hit policy Unique
-- > grOtherwise              ->  the default output / catch-all rule
-- > a guard                  ->  an input entry
-- > a body                   ->  an output entry (an EXPRESSION, DMN 8.2.9)
--
-- Three things that table leaves implicit, and that this module has to get right:
--
-- [Where @OTHERWISE@ goes] A catch-all rule with all-@-@ input entries overlaps
--   /every/ other rule, so it is illegal under @U@. Under 'HitUnique',
--   @grOtherwise@ therefore becomes the @\<defaultOutputEntry\>@ on the output
--   clause, which DMN 1.3 supports precisely for the single-hit policies; only
--   under 'HitFirst' does it become a final all-@-@ rule.
--
-- [Negated prefixes are not materialised] Row @i@ of a @BRANCH@ fires iff its own
--   guard holds /and no earlier guard did/. The ladder consumer has to write those
--   @⋀_{j\<i} ¬gⱼ@ prefixes out, because an And\/Or tree has no other way to say
--   "first match wins". A DMN table does: hit policy @First@ /is/ that
--   quantifier. Restating the prefixes would be redundant and would turn a
--   readable table into a triangular mess, so each rule carries only its own
--   guard. This is a genuine advantage the table has over the ladder expansion.
--
-- [Non-boolean bodies are in scope] The ladder consumer gates on boolean type;
--   this one must not. A @NUMBER@-returning @BRANCH@ — a fee schedule, an
--   investor limit — is precisely what a decision table is /for/.
--
-- __The boundary this exporter reports on.__ Everything DMN can statically
-- check — completeness and consistency since Montalbano (1962), inter-tabular
-- checking since 1998, cross-DRD SMT verification since 2022 — is defined over
-- __S-FEEL input entries, constant output entries, and a single-hit policy__.
-- The DMN specification's own §9.1 then says "few if any complete decision
-- models can be defined using S-FEEL" and encourages "the full FEEL
-- specification rather than the S-FEEL subset". So the fragment you can verify
-- is not the fragment you are told to write
-- (@specs\/research\/DMN-STEELMAN.md@ §2.5, which also records what must /not/
-- be claimed: nobody has proved FEEL analysis undecidable). This exporter's job
-- is to say, per file, exactly where the emitted model crossed that line.
--
-- Of the three conditions, the third is met for free: the only hit policies here
-- are @U@ and @F@, both single-hit. @Collect@ is excluded from every published
-- result (Semantic DMN: "S-FEEL does not provide list-handling constructs …
-- hence only single-hit policies combine well with S-FEEL within a DRG"), and
-- L4's guarded chains are single-hit by construction anyway.
--
-- __The conservatism, stated once.__ A guard conjunct becomes a column plus a
-- unary test only when the test reduces to a /constant/ endpoint. Anything else
-- becomes its own boolean column whose input expression is the conjunct's own
-- text and whose cell is @true@, plus a 'FidelityNote'. That is always sound;
-- guessing is not. The exporter must never emit a table that says something the
-- L4 does not.
--
-- __One divergence this does not detect, recorded rather than hidden.__ @BRANCH@
-- short-circuits: a later guard is never evaluated once an earlier one has
-- fired. A DMN table does not — its /input expressions/ are evaluated once for
-- the whole table and then tested rule by rule. For __total, pure__ guards the
-- two agree exactly, which is what makes the mapping sound, and effectful guards
-- bail out ('EffectfulGuard'). But a __partial__ guard is a third case: in
--
-- > BRANCH
-- >   IF x EQUALS 0        THEN 0
-- >   IF 100 / x AT LEAST 5 THEN 1
-- >   OTHERWISE 2
--
-- L4 never divides by zero and DMN always does. Partiality is not decidable
-- here, so no note is emitted; a guard that can fail on inputs an earlier rule
-- would have caught is a real, undetected fidelity loss.
module L4.Dmn.Lower
  ( -- * The interface the spec fixes
    rowsToDmn
    -- * Richer entry points
  , rowsToDmnWith
  , TableCtx (..)
  , defaultTableCtx
  , lowerModule
  , moduleTitle
  , DmnLowerOptions (..)
  , defaultDmnLowerOptions
  , MaybePredicates (..)
  , resolveMaybePredicates
    -- * Reusable pieces
  , renderFeel
  , renderFeelIn
  , NameEnv (..)
  , emptyNameEnv
  , sanitiseId
  , selectShape
  , selectIdiom
  , selectIdiomIn
  , TypeOracle (..)
  , noTypeOracle
  , TypeEnv (..)
  , emptyTypeEnv
  , TypeFlags (..)
  , noTypeFlags
  , classifyType
  , peelLocals
  , flattenGuarded
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Char (isAlphaNum, isAscii, isDigit)
import Data.Either (partitionEithers)
import Data.Ratio (denominator, numerator)
import Data.Time.Calendar (Day, fromGregorianValid, showGregorian, toModifiedJulianDay)
import Optics

import L4.Annotation (Anno_ (..), emptyAnno, getAnno)
import L4.Desugar (carameliseExpr)
import L4.Parser.SrcSpan (SrcRange, prettySrcRange)
import L4.Print (prettyLayout)
import L4.Syntax
import qualified L4.TypeCheck as TC
import L4.Viz.GuardedRows (GuardedRows (..), hasEffectfulNode, normaliseGuarded)
import L4.Interchange.Fidelity

import qualified L4.Dmn.Analysis as A
import L4.Dmn.IR

------------------------------------------------------------------------
-- Contexts
------------------------------------------------------------------------

-- | The resolved FEEL names of everything a reference can name (§5.2 stage 2).
--
-- Stage 1 ('feelIdentText') is a per-name fold and is deliberately
-- non-injective; stage 2 ('uniquifyIn') makes it injective /within a scope/ and
-- is therefore a property of the whole module, not of a string. So a reference
-- cannot be rendered by folding the name it mentions — it has to look the name
-- up. That is what this environment is for, and it is what makes a rename reach
-- __references__ and not only declarations.
--
-- Two scopes, because DMN has two namespaces here (§5.2 scopes 1 and 2):
--
--   * 'neVars' — the DRG's flat variable namespace: every @inputData@ variable
--     and every @decision@ variable together, since they share one evaluation
--     scope.
--   * 'neFields' — record-field projection paths, keyed by the selector's own
--     'Unique'. A selector is unique to its declaring type, so one flat map
--     covers every record at once, and the map is per-declaration internally:
--     two records may each have a field that folds to @foo_bar@ without either
--     being renamed.
--
-- Three further fields carry what 'renderFeelIn' cannot recompute from the
-- expression in front of it: 'neMaybePreds' (R8-d′'s combinator table),
-- 'neHydrated' and 'neBareProj' (H1's fold, §4.4).
data NameEnv = MkNameEnv
  { neVars       :: !(Map Unique Text)
  , neFields     :: !(Map Unique Text)
  , neMaybePreds :: !(Maybe MaybePredicates)
    -- ^ the prelude's @isJust@ \/ @isNothing@, when this module can see them.
  , neHydrated   :: !(Map Unique Text)
    -- ^ a hydrated instance's 'Unique' to its hydrator's FEEL name. A computed
    -- read of such an instance folds to a path access on the hydrator (§4.4).
  , neBareProj   :: !(Set Unique)
    -- ^ receivers whose projections render BARE. Holds the @_self@ binder while
    -- a computed field's own body is being rendered INSIDE the hydrator, where
    -- a sibling entry is named by its bare entry name and not by a path.
  , neUnlifted   :: !(Set Unique)
    -- ^ tier-1, @DMN-SAFE@ decides that Phase 4 un-lifted (§2.1): a
    -- /saturated call/ to one renders as the callee's bare FEEL name
    -- (fragment 'SFeel'), because its parameters are now module-level
    -- @inputData@ and the argument expression at the call site is discarded
    -- (@D-PARAM-AS-INPUT@ names that loss). Everything else still falls to
    -- the verbatim case.
  , neComputedFields :: !(Set Unique)
    -- ^ the COMPUTED selectors (§4.4). A projection of one that was not
    -- folded onto a hydrator (D12's boundary: a non-nullary receiver) must
    -- render VERBATIM: the emitted record carries stored components only, so
    -- @base.computedField@ would be valid FEEL silently answering null.
    -- Phase 4 made this guard load-bearing — an un-lifted call in base
    -- position now renders as a clean bare name, which would otherwise
    -- launder the whole projection into 'SFeel'.
  , neBkms       :: !(Map Unique BkmCallInfo)
    -- ^ Phase 5 (§6.1, §6.2): the emitted BKMs, keyed by the decide's
    -- 'Unique'. A __saturated__ call to one renders as a FEEL named-argument
    -- invocation @f(p: x, q: y, …)@ — named rather than positional because it
    -- makes §6.2's position→name binding visible and kills silent argument
    -- transposition (probe A2: zeebe-dmn accepts named args in scrambled
    -- order; A1 shows positional also works). A __bare__ reference renders
    -- verbatim: a BKM is an invocable, not a variable, and §6.3-2 refuses
    -- higher-order use. The map's values carry the resolved parameter names,
    -- so the call site and the emitted @formalParameter@ cannot disagree.
  , neBkmParams  :: !(Set Unique)
    -- ^ the @GIVEN@ binders of every emitted BKM. Inside a BKM body they
    -- render by their formalParameter FEEL names (via 'neVars' entries), and
    -- a COMPUTED-field read through one takes the inline arm
    -- ('neComputedInline') rather than the hydrator fold — a parameter is
    -- per-call, so no global hydrator can stand for it.
  , neServiceCalls :: !(Map Unique SvcCallInfo)
    -- ^ @kie@ flavor ONLY (§13.5 — the one flavor bit): decides whose
    -- saturated call sites render as an invocation of their section's
    -- @decisionService@, `svc(p: e, …)` with the service's inputData names as
    -- the parameter names (§2.3.1: named binding at every service call site).
    -- Populated for the narrow measured shape — a safety-refused parameterised
    -- decide that is the sole output of its (post-split) service, whose
    -- service inputs are exactly its own GIVEN params — and EMPTY on the
    -- default flavor, where the knowledgeRequirement→service edge this render
    -- requires is fatal to Camunda's parse() (§13.4, probe D2).
  , neRecordCtors :: !(Map Unique [Unique])
    -- ^ RECORD constructors only (never an enum's payload constructor — those
    -- carry a tag FEEL cannot spell and stay refused under @D-SUMTYPE@), each
    -- to its declared STORED field selectors in declaration order. A
    -- saturated @R WITH f IS e, …@ construction lowers to the FEEL context
    -- literal @{f: e, …}@ — the same reading the hydration design gives a
    -- record (a FEEL context IS the record) — iff every stored field is
    -- supplied exactly once; anything else stays verbatim.
  , neComputedInline :: !(Map Unique (Unique, Expr Resolved))
    -- ^ self-contained computed selectors (§4.4 × §6.2): selector 'Unique' →
    -- (the @_self@ binder's 'Unique', the prepared body). A computed read
    -- through a BKM __parameter__ inlines the selector body with @_self@
    -- substituted by the receiver — the only faithful form, since the
    -- parameter cannot be hydrated. Restricted to selectors whose bodies
    -- reference nothing beyond @_self@ (no module globals, no sibling
    -- computed reads), so the inline cannot smuggle unliftable environment
    -- references into a BKM body.
  }

-- | One member of a BKM's λ-lifted closure (§6.2): either a module element
-- read directly (an @inputData@ or a decision variable, by canonical
-- 'Unique'), or the __hydrator__ of an instance whose computed field the body
-- reads — the fold points the rendered text at the hydrator, so the hydrator
-- is what must be passed.
data ClosureRef = EnvDirect !Unique | EnvHydrator !Unique
  deriving stock (Eq, Ord, Show)

-- | What a call site needs to know about an invocable @§@ (@kie@ flavor only).
data SvcCallInfo = MkSvcCallInfo
  { sciFeelName :: !Text
  , sciParams   :: ![Text]
    -- ^ the service's inputData FEEL names, positional in the callee's GIVEN
    -- order — the names the named-argument invocation binds.
  }

-- | What a call site needs to know about an emitted BKM (§6.2).
data BkmCallInfo = MkBkmCallInfo
  { bciFeelName :: !Text
  , bciParams   :: ![Text]
    -- ^ the resolved FEEL names of the L4 @GIVEN@ parameters, positional — the
    -- position→name map fixed once at the BKM and reused at every call site.
  , bciClosure  :: ![Text]
    -- ^ the λ-lifted closure parameters (§6.2's measured boundary: a BKM body
    -- may read nothing beyond its parameters and knowledge requirements),
    -- each named exactly as the module element it lifts; the call site
    -- supplies each as @name: name@, which the caller has in scope through
    -- its own requirement edges.
  }

-- | The resolved 'Unique's of the prelude's @isJust@ and @isNothing@.
--
-- Compared by 'Unique' and never by name: these are ordinary prelude L4 source
-- rather than builtins, so their 'Unique's are minted when the prelude module is
-- checked and cannot be TH-generated constants the way @maybeUnique@ is. See
-- 'resolveMaybePredicates' for how they are found, once, under a type check.
data MaybePredicates = MkMaybePredicates
  { mpIsJust    :: !Unique
  , mpIsNothing :: !Unique
  }
  deriving stock (Eq, Show)

-- | Knows no names, so every reference falls back to the stage-1 fold. Right for
-- 'renderFeel', which holds an expression and nothing else; wrong inside a
-- module, where 'lowerModule' always supplies the resolved environment.
emptyNameEnv :: NameEnv
emptyNameEnv = MkNameEnv
  { neVars       = Map.empty
  , neFields     = Map.empty
  , neMaybePreds = Nothing
  , neHydrated   = Map.empty
  , neBareProj   = Set.empty
  , neUnlifted   = Set.empty
  , neComputedFields = Set.empty
  , neBkms       = Map.empty
  , neBkmParams  = Set.empty
  , neServiceCalls = Map.empty
  , neRecordCtors = Map.empty
  , neComputedInline = Map.empty
  }

-- | What a single table needs to know beyond its rows.
data TableCtx = MkTableCtx
  { tcName         :: !Text        -- ^ the decision's name; also the table's
  , tcFeelName     :: !Text
    -- ^ the decision's __resolved__ FEEL name (§5.2 stage 2). The output
    -- clause's @ocName@ is this, not a re-fold of 'tcName': the markdown carrier
    -- keys its column off it, and a name that disagreed with the decision's
    -- @\<variable\>@ would name a variable that does not exist.
  , tcNames        :: !NameEnv     -- ^ resolved FEEL names for every reference
  , tcIdPrefix     :: !Text        -- ^ every id in the table derives from this
  , tcOutputType   :: !DmnType     -- ^ from @GIVETH@, when the source declared one
  , tcConstructors :: !(Set Unique)
    -- ^ nullary constructors visible in the module. A @CONSIDER@ arm becomes an
    -- equality against a constant only if we can tell a constructor from a
    -- variable; see 'isConstantRef' for why guessing here is unsound.
  , tcConstants    :: !(Set Unique)
    -- ^ nullary decisions whose body is a literal, i.e. named thresholds. Used
    -- only to decide whether a lifted @max@\/@min@ deserves a
    -- @D-LIFTEDTHRESHOLD@ note; it never changes the lowering.
  , tcTypes        :: !TypeEnv
    -- ^ what the module's own @DECLARE@s say: which types have an
    -- @itemDefinition@ and what it is called, which have a finite domain, and
    -- which are payload-carrying unions. One environment answers the @typeRef@
    -- question and the @inputValues@ question at once, which is why they are
    -- not two lookups (§3, §4.2).
  , tcOutputValues :: !(Maybe [Text])
    -- ^ the @GIVETH@ type's domain, when it has one. Becomes
    -- @\<outputValues\>@; see 'OutputColumn'.
  , tcDateConstants :: !(Map Unique Day)
    -- ^ nullary decisions whose body folds to a DATE literal, i.e. named
    -- effective dates. A CELL may inline such a constant's value as an endpoint
    -- (that is what an endpoint is for); an EXPRESSION may not, because there
    -- the constant is a DMN decision variable and inlining would erase the
    -- reference. See 'constantOf' and 'renderFeelIn' respectively.
  , tcSubst        :: !TC.Substitution
  , tcUri          :: !NormalizedUri
  }

-- | Enough to satisfy 'rowsToDmn' standing alone. Knows no constructors, so a
-- @CONSIDER@ lowered through it degrades to boolean columns — which is why the
-- module-level path builds a real 'TableCtx'.
defaultTableCtx :: TableCtx
defaultTableCtx = MkTableCtx
  { tcName         = "decision"
  , tcFeelName     = "decision"
  , tcNames        = emptyNameEnv
  , tcIdPrefix     = "decision"
  , tcOutputType   = DmnAny
  , tcConstructors = Set.empty
  , tcConstants    = Set.empty
  , tcTypes        = emptyTypeEnv
  , tcOutputValues = Nothing
  , tcDateConstants = Map.empty
  , tcSubst        = Map.empty
  , tcUri          = toNormalizedUri (Uri "")
  }

-- | The typechecker's answer to "what type is this expression?", bundled — the
-- three arguments 'annTypeOf' already takes.
--
-- 'TableCtx' carries all three already, but 'renderFeelIn' has to ask the same
-- question without being inside a table: FEEL orders only the datatypes DMN 1.3
-- Table 54 lists, so both the select-idiom gate ('selectIdiomIn') and the
-- rendering of @\<@ \/ @\<=@ \/ @\>@ \/ @\>=@ itself need the operand's type.
-- Bundling is what lets a caller that holds only an expression ('renderFeel')
-- and a caller that holds a whole table ('mkColumn') ask through the same
-- predicate.
--
-- Deliberately NOT threaded into 'flattenGuarded': its @childOf@ guard is
-- structural, not type-directed. See 'selectShape'.
data TypeOracle = MkTypeOracle
  { toTypes :: !TypeEnv
  , toSubst :: !TC.Substitution
  , toUri   :: !NormalizedUri
  }

-- | An oracle that knows only what each node's own annotation already says.
--
-- Weaker, and the two directions differ. An operand still annotated with an
-- inference variable resolves to 'DmnAny' rather than to whatever the final
-- substitution would have given, so 'selectIdiomIn' declines to fold — a lost
-- peephole, nothing more. But 'DmnAny' also fails 'isBooleanOperand', so a
-- comparison whose operand type is unknown still renders as @a \>= b@; that is
-- right for every type FEEL orders and wrong only for a BOOLEAN comparison the
-- oracle could not see was one.
--
-- In practice it sees: a resolved comparison's operands carry the winning
-- overload's ground type in their own annotation (see 'feelOrderable'), which is
-- exactly what this oracle reads. Every lowering path inside a module goes
-- through 'oracleOf' and its substitution anyway; this one exists for
-- 'renderFeel', which has an expression and nothing else.
noTypeOracle :: TypeOracle
noTypeOracle = MkTypeOracle
  { toTypes = emptyTypeEnv
  , toSubst = Map.empty
  , toUri   = toNormalizedUri (Uri "")
  }

oracleOf :: TableCtx -> TypeOracle
oracleOf ctx = MkTypeOracle
  { toTypes = ctx.tcTypes
  , toSubst = ctx.tcSubst
  , toUri   = ctx.tcUri
  }

data DmnLowerOptions = MkDmnLowerOptions
  { dloModelName    :: !Text
    -- ^ the @\<definitions\>@ name, and the seed of its namespace. Taken as a
    -- parameter rather than read off the module's URI so that goldens do not
    -- depend on where the file lives.
  , dloSubstitution :: !TC.Substitution
    -- ^ the typechecker's final substitution, used to resolve inference
    -- variables into @typeRef@s. 'Map.empty' is fine; every unresolved type
    -- simply becomes @Any@.
  , dloFlavor       :: !DmnFlavor
    -- ^ which engine the document is aimed at. It is a __lowering__ option and
    -- not a post-hoc XML rewrite for three reasons, in order of force
    -- (@specs\/todo\/DMN-EXPORT-PROGRAM-MODEL-SPEC.md@ §13.5): the FEEL /text/ of
    -- a call site differs and cannot be recovered from a @\<text\>@ node after
    -- the fact; the fidelity report is generated from this same IR, so a rewrite
    -- would ship a report describing a different artifact — the "valid per the
    -- validator, wrong in the engine" failure this whole exercise exists to
    -- close, one layer up; and Camunda 8 fails at @parse()@ whole-file, so "emit
    -- the rich form and strip later" has no safe intermediate.
  , dloMaybePredicates :: !(Maybe MaybePredicates)
    -- ^ the resolved 'Unique's of the prelude's @isJust@ \/ @isNothing@, when
    -- this module can see them (R8-d′'s combinator table).
    --
    -- __Why this has to be plumbed at all.__ Both are ordinary prelude L4
    -- source, not builtins: builtin 'Unique's are TH-generated constants in
    -- "L4.TypeCheck.Environment", and there is no such constant for these
    -- because their 'Unique's are minted when the prelude module is checked and
    -- carry a machine-dependent module URI. 'lowerModule' sees one
    -- @Module Resolved@ and this record — no 'TC.Environment', no
    -- 'TC.EntityInfo' — so without this field @isJust q@ would render verbatim
    -- and the idiomatic L4 spelling of an absence test would produce a WORSE
    -- artifact than the longhand CONSIDER.
    --
    -- Resolved ONCE, at the lowering boundary, by 'resolveMaybePredicates', and
    -- compared by 'Unique' thereafter: the name is read exactly once, under a
    -- type check, and never again.
  , dloIncludeTests :: !Bool
    -- ^ @--include-tests@ (§2.5.6 rule 2): emit test fixtures and their
    -- fixture-side helper closure anyway. Default OFF — the filter's whole
    -- point is that a fixture emitted as a @\<decision\>@ misdescribes the
    -- rule set — but the switch must exist because the filter is a
    -- measurement about four corpora, not a soundness property (§2.5.8).
  , dloMissingMatchRanges :: ![SrcRange]
    -- ^ the source ranges of the checker's @PatternMatchesMissing@ warnings,
    -- for @DMN-SAFE@'s L1 (§2.4.1). Empty means "no warnings", which is only
    -- sound when the caller really ran the checker — both call sites
    -- (@jl4\/app\/L4\/Cli\/Export.hs@ and the golden harness) extract these
    -- from the same 'TC.CheckErrorWithContext' list the module came from.
  , dloClauseMatrixRanges :: ![SrcRange]
    -- ^ the source ranges (clause-head hulls) of the checker's
    -- @PatternClausesMissing@ warnings — L1's Decide-level channel for
    -- multi-clause pattern-matching groups (§14.7). A separate list from
    -- 'dloMissingMatchRanges' on purpose: those are matched against
    -- CONSIDER ranges, which a clause-head hull never sits inside (the
    -- desugarer's CONSIDERs are rangeless), and a shared list checked at
    -- Decide level would double-report every ordinary partial CONSIDER.
    -- Extracted at the same two call sites, by the same comprehension.
  , dloExternalRefNames :: !(Maybe (Set Text))
    -- ^ @FIXTURE(d)@'s importer view (§2.5.7): the L4 names referenced by
    -- modules that import this one. 'Nothing' = unavailable — the population
    -- filter then FAILS SAFE (drops nothing, reports what it would have
    -- dropped). The CLI supplies a sibling-directory scan; the golden harness
    -- supplies its VFS's contents.
  }

defaultDmnLowerOptions :: DmnLowerOptions
defaultDmnLowerOptions = MkDmnLowerOptions
  { dloModelName          = "L4"
  , dloSubstitution       = Map.empty
  , dloFlavor             = defaultDmnFlavor
  , dloMaybePredicates    = Nothing
  , dloIncludeTests       = False
  , dloMissingMatchRanges = []
  , dloClauseMatrixRanges = []
  , dloExternalRefNames   = Nothing
  }

-- | Find the prelude's @isJust@ and @isNothing@ by SHAPE, not by module path.
--
-- Lives here, and is exported, so that the two call sites (the CLI's exporter
-- and the golden harness) cannot drift apart on how recognition is done — the
-- failure mode being that one of them recognises the combinators and the other
-- silently does not, which shows up as a golden that changes when nothing did.
--
-- The check is a TYPE check, and each half is load-bearing:
--
--   * the entity is a @KnownTerm ty Computable@ — a term, not a constructor or
--     a type;
--   * stripping the @∀@, @ty@ is a one-value-argument function;
--   * its ARGUMENT's type head is 'TC.maybeUnique';
--   * its RESULT's type head is 'TC.booleanUnique'.
--
-- Requiring EXACTLY ONE survivor per name is what makes a user who shadows
-- @isJust@ ALONGSIDE the prelude fall back to no recognition rather than to the
-- wrong one: two candidates, so 'Nothing'.
--
-- __Two PROVENANCE conditions on top of the shape, and neither is a path
-- test.__ 'Unique' carries the URI of the module that minted it, so:
--
--   * both survivors must come from the SAME module — one prelude defines the
--     pair, and a mix-and-match of two unrelated definitions is not it;
--   * that module must NOT be the module being exported.
--
-- The second is the one that matters. Without it a module that defines its own
-- @isJust@ and does not import the prelude has exactly ONE shaped candidate,
-- and the shape check cannot see the body: @\`isJust\` x MEANS FALSE@ has the
-- right type and would have been rendered @x != null@ — a wrong answer with no
-- fidelity note at all, because a recognised combinator renders as clean FEEL.
-- The "exactly one survivor" sentence above USED to claim it covered that case;
-- it did not, and the case it named was the one it missed.
--
-- __Still not filtered by the module's PATH.__ The prelude's URI differs between
-- the CLI (a real file path, or @jl4-embedded:@, or an XDG store) and the VFS
-- harness (@project:\/prelude.l4@), so a path test would recognise the
-- combinators in one and not the other — the same drift this function exists to
-- prevent, only harder to see. Comparing URIs for EQUALITY is immune to that,
-- because both sides are minted by the same resolver in the same run.
--
-- __What is still not established, stated rather than glossed:__ that the
-- defining module is the L4 prelude and not some other imported library that
-- happens to define both names at both types. Closing that would need the
-- BODIES, and 'TC.EntityInfo' carries only types. A library that reimplements
-- @isJust@ and @isNothing@ at @MAYBE a -> BOOLEAN@ and is imported INSTEAD of
-- the prelude will be recognised; a library imported ALONGSIDE it will not.
resolveMaybePredicates
  :: Module Resolved   -- ^ the module being exported; a definition from HERE is not the prelude's
  -> TC.Environment
  -> TC.EntityInfo
  -> Maybe MaybePredicates
resolveMaybePredicates (MkModule _ selfUri _) env info = do
  j <- soleMatch "isJust"
  n <- soleMatch "isNothing"
  guard (j.moduleUri == n.moduleUri)
  guard (j.moduleUri /= selfUri)
  pure (MkMaybePredicates { mpIsJust = j, mpIsNothing = n })
 where
  soleMatch nm = case filter shaped (Map.findWithDefault [] (NormalName nm) env) of
    [u] -> Just u
    _   -> Nothing

  shaped u = case Map.lookup u info of
    Just (_, TC.KnownTerm ty Computable) -> isMaybePredicate ty
    _                                    -> False

  -- @MAYBE a -> BOOLEAN@, under any number of leading @∀@s.
  isMaybePredicate = \case
    Forall _ _ t -> isMaybePredicate t
    Fun _ [arg] res ->
      headIs TC.maybeUnique (argType arg) && headIs TC.booleanUnique res
    _ -> False

  argType = \case
    MkOptionallyNamedType _ _ t -> t

  headIs u = \case
    TyApp _ n _ -> getUnique n == u
    _           -> False

------------------------------------------------------------------------
-- rowsToDmn
------------------------------------------------------------------------

-- | The interface GUARDED-ROWS.md §7 fixes.
rowsToDmn :: GuardedRows -> Either FidelityLoss DecisionTable
rowsToDmn = rowsToDmnWith defaultTableCtx

-- | 'rowsToDmn', told who it is working for.
rowsToDmnWith :: TableCtx -> GuardedRows -> Either FidelityLoss DecisionTable
rowsToDmnWith ctx = rowsToDmnWith' ctx [] []

-- | 'rowsToDmnWith', plus the two things only the module-level caller knows:
-- which @WHERE@\/@LET@ locals it inlined, and which nested bodies it declined to
-- flatten. Both are reported, not silently absorbed.
rowsToDmnWith'
  :: TableCtx -> [Text] -> [Expr Resolved] -> GuardedRows -> Either FidelityLoss DecisionTable
rowsToDmnWith' ctx inlined cappedBodies rows = do
  -- A DMN input expression is evaluated ONCE for the whole table and then tested
  -- by every rule, whereas BRANCH short-circuits. Tabulating an effectful guard
  -- would therefore change how often the effect runs. (GUARDED-ROWS.md §6.)
  when (any (hasEffectfulNode . fst) rows.grRows) (Left EffectfulGuard)
  -- A deontic body is a transition system, not a value. DMN "has no notion of
  -- time" and cannot hold an obligation as a state.
  when (any isRegulative (map fst rows.grRows <> bodies)) (Left RegulativeBody)
  when (null rows.grRows) (Left NoRules)
  pure table
 where
  bodies = map snd rows.grRows <> maybeToList rows.grOtherwise

  decomposed  = map (decomposeGuard ctx . fst) rows.grRows
  columnCells = orderedColumns decomposed
  columnKeys  = map (.cellKey) columnCells
  columns     = zipWith (mkColumn ctx) [1 :: Int ..] columnCells

  -- Note what does NOT happen here: a row whose body is FALSE is kept. The
  -- ladder consumer deletes such rows because a FALSE disjunct cannot conduct;
  -- a DMN output entry of `false` is an ordinary answer, and deleting the rule
  -- would silently reroute those inputs to the default.
  ruleCells =
    [ [ maybe TestAny (.cellTest) (findCell key row) | key <- columnKeys ]
    | row <- decomposed
    ]
  findCell key row = listToMaybe [c | c <- row, c.cellKey == key]

  policy = if rows.grDisjoint && rulesPairwiseDisjoint ruleCells then HitUnique else HitFirst

  rowRules = zipWith3 mkRule [1 :: Int ..] ruleCells rows.grRows
  mkRule i cells (guardE, body) = MkDmnRule
    { drId          = ctx.tcIdPrefix <> "_r" <> tshow i
    , drInputs      = cells
    -- NB the empty constructor set is this call site's existing behaviour (a
    -- rule output has never quoted constructors, unlike `defaultOut` below);
    -- only the oracle is new here.
    , drOutput      = renderFeelIn ctx.tcNames Set.empty (oracleOf ctx) body
    , drDescription = Just (oneLine (prettyLayout guardE))
    , drAnnotations = []
    }

  -- Under First the catch-all is a final rule with all-`-` inputs, which is
  -- exactly what First means. Under Unique it cannot be a rule at all (it would
  -- overlap everything), so it goes on the output clause instead.
  catchAll = case (policy, rows.grOtherwise) of
    (HitFirst, Just b0) ->
      [ MkDmnRule
          { drId          = ctx.tcIdPrefix <> "_r" <> tshow (length rowRules + 1)
          , drInputs      = map (const TestAny) columnKeys
          , drOutput      = renderFeelIn ctx.tcNames ctx.tcConstructors (oracleOf ctx) b0
          , drDescription = Just "OTHERWISE"
          , drAnnotations = []
          }
      ]
    _ -> []

  allRules   = rowRules <> catchAll
  defaultOut = renderFeelIn ctx.tcNames ctx.tcConstructors (oracleOf ctx) <$> rows.grOtherwise

  -- A column's declared type is whatever L4 inferred for its subject; when that
  -- is opaque to FEEL (an enum, a record, an inference variable) but every cell
  -- in the column is the same kind of constant, say so instead. That is how a
  -- CONSIDER over constructors becomes a `string` column rather than an `Any` one.
  typedColumns = zipWith retype [0 ..] columns
  retype i col
    | col.icType /= DmnAny = col
    | otherwise            = col { icType = typeFromCells [row !! i | row <- ruleCells] }

  outColumn = MkOutputColumn
    { ocId      = ctx.tcIdPrefix <> "_o1"
    , ocName    = ctx.tcFeelName
    , ocType    = resolveOutputType ctx (map (.drOutput) allRules <> maybeToList defaultOut)
      -- Only when the DECLARED type is what won: a type recovered from the
      -- cells says what this table happens to mention, which is exactly the
      -- domain we must not assert (§3.2).
    , ocValues  = if ctx.tcOutputType /= DmnAny then ctx.tcOutputValues else Nothing
    , ocDefault = if policy == HitUnique then defaultOut else Nothing
    }

  table = MkDecisionTable
    { dtId        = ctx.tcIdPrefix <> "_table"
    , dtName      = ctx.tcName
    , dtHitPolicy = policy
    , dtInputs    = typedColumns
    , dtOutput    = outColumn
    , dtRules     = allRules
      -- Only a rule-date interval table carries an annotation column (§15.3).
    , dtAnnotations = []
    , dtNotes     = tableNotes ctx decomposed columnCells typedColumns policy rows inlined cappedBodies
    }

------------------------------------------------------------------------
-- Guard decomposition
------------------------------------------------------------------------

-- | One decomposed conjunct: the column it constrains, and how.
data Cell = MkCell
  { cellKey      :: !(Expr Resolved)  -- ^ 'clearAnno'd subject, for column identity
  , cellSubject  :: !(Expr Resolved)  -- ^ the subject as written, for rendering
  , cellTest     :: !UnaryTest
  , cellFallback :: !Bool             -- ^ did we have to demote it to a boolean column?
  , cellNote     :: !Bool             -- ^ ...and is that worth reporting?
  }

-- | Split a guard into conjuncts and classify each one.
--
-- Two conjuncts of one row landing on the same column is a real possibility
-- (@income AT LEAST 100 AND income LESS THAN 200@) and a DMN cell is a
-- /disjunctive/ list, so they cannot simply both be written there. Where they
-- form an interval we merge them into one; otherwise the later one is demoted to
-- its own boolean column, which is verbose but says the same thing.
decomposeGuard :: TableCtx -> Expr Resolved -> [Cell]
decomposeGuard ctx = foldl' add [] . filter (not . isInert) . conjuncts
 where
  add acc conj =
    let cell = classify ctx conj
    in case break (\c -> c.cellKey == cell.cellKey) acc of
      (_, [])             -> acc <> [cell]
      (before, c : after) -> case mergeTests c.cellTest cell.cellTest of
        Just merged -> before <> [c { cellTest = merged }] <> after
        Nothing     -> acc <> [fallbackCell conj]

  -- An Inert node is grammatical scaffolding that evaluates to its context's
  -- identity; in a conjunction that is TRUE, so it constrains nothing. The words
  -- are not lost: the rule's description carries the guard's full source text.
  isInert = \case
    Inert {} -> True
    _        -> False

conjuncts :: Expr Resolved -> [Expr Resolved]
conjuncts = \case
  And _ a b -> conjuncts a <> conjuncts b
  e         -> [e]

disjuncts :: Expr Resolved -> [Expr Resolved]
disjuncts = \case
  Or _ a b -> disjuncts a <> disjuncts b
  e        -> [e]

classify :: TableCtx -> Expr Resolved -> Cell
classify ctx e = case e of
  Not _ inner -> case tryDecompose ctx inner of
    Just (subj, t) -> mkCell subj (TestNot t) False False
    -- A negated conjunct we cannot decompose is still boolean, so it becomes a
    -- `false` cell on its operand's column rather than a `true` cell on a column
    -- spelled `not(...)`. Same meaning, one fewer column, and it lines up with
    -- any positive occurrence of the same proposition elsewhere in the table.
    Nothing -> mkCell inner (TestEq (VBool False)) True (isCompound inner)
  _ -> case tryDecompose ctx e of
    Just (subj, t) -> mkCell subj t False False
    Nothing        -> fallbackCell e
 where
  mkCell subj t fb note = MkCell
    { cellKey      = clearAnno subj
    , cellSubject  = subj
    , cellTest     = t
    , cellFallback = fb
    , cellNote     = note
    }

-- | The always-correct answer: the conjunct becomes its own boolean column with
-- a @true@ cell. Reported only when the conjunct is compound — a bare boolean
-- term is an idiomatic DMN column and loses nothing.
fallbackCell :: Expr Resolved -> Cell
fallbackCell e = MkCell
  { cellKey      = clearAnno e
  , cellSubject  = e
  , cellTest     = TestEq (VBool True)
  , cellFallback = True
  , cellNote     = isCompound e
  }

isCompound :: Expr Resolved -> Bool
isCompound = \case
  App _ _ [] -> False
  Proj {}    -> False
  Lit {}     -> False
  _          -> True

-- | @Just (subject, test)@ when the conjunct is a comparison or equality against
-- a constant, or a disjunction of such over one subject.
tryDecompose :: TableCtx -> Expr Resolved -> Maybe (Expr Resolved, UnaryTest)
tryDecompose ctx = \case
  Lt     _ a b -> comparison OpLt  OpGt  a b
  Leq    _ a b -> comparison OpLeq OpGeq a b
  Gt     _ a b -> comparison OpGt  OpLt  a b
  Geq    _ a b -> comparison OpGeq OpLeq a b
  Equals _ a b -> equalityOn a b
  -- A comma-separated cell is DMN's own idiom for disjunction over one column,
  -- and it is exact: `red, blue` on column `c` means `c = red or c = blue`.
  e@Or {} -> case traverse (tryDecompose ctx) (disjuncts e) of
    Just parts@((subj, _) : _ : _)
      | all (\(s, _) -> clearAnno s == clearAnno subj) parts
      -- S-FEEL puts @not(...)@ at the TOP of a cell only: the grammar is
      -- @simple unary tests = simple POSITIVE unary tests | "not" "(" simple
      -- positive unary tests ")" | "-"@, so @1, not(2)@ is not a legal cell. A
      -- disjunct that needs a negation therefore does not get merged.
      , all (isPositiveTest . snd) parts
      -> Just (subj, TestOneOf (concatMap (flattenOneOf . snd) parts))
    _ -> Nothing
  _ -> Nothing
 where
  flattenOneOf = \case
    TestOneOf ts -> ts
    t            -> [t]

  -- A boolean endpoint is refused for the same reason 'renderFeelIn' sends a
  -- boolean @\>=@ out verbatim: DMN 1.3 §10.3.2.13 defines the ordering
  -- operators "only for the datatypes listed in Table 54", which has no boolean
  -- row, so a cell reading @\>= true@ is outside FEEL. Refusing here sends the
  -- conjunct to 'fallbackCell', where the whole comparison becomes the column
  -- subject and is reported Blocking rather than silently emitted as S-FEEL.
  comparison op mirrored a b = case (constantOf ctx a, constantOf ctx b) of
    (Nothing, Just v) | not (isBoolValue v) -> Just (a, TestCmp op v)
    (Just v, Nothing) | not (isBoolValue v) -> Just (b, TestCmp mirrored v)
    _                                       -> Nothing

  isBoolValue = \case
    VBool _ -> True
    _       -> False

  equalityOn a b = case (constantOf ctx a, constantOf ctx b) of
    (Nothing, Just v) -> Just (a, TestEq v)
    (Just v, Nothing) -> Just (b, TestEq v)
    _                 -> Nothing

-- | Is this test legal as one element of a comma-separated cell? (S-FEEL calls
-- these @simple positive unary tests@.)
isPositiveTest :: UnaryTest -> Bool
isPositiveTest = \case
  TestNot _    -> False
  TestAny      -> False
  TestOneOf ts -> all isPositiveTest ts
  TestEq _     -> True
  TestCmp _ _  -> True
  TestRange {} -> True

-- | The constant an expression denotes, if any.
constantOf :: TableCtx -> Expr Resolved -> Maybe FeelValue
constantOf ctx = \case
  Lit _ (NumericLit _ r) -> Just (VNum r)
  Lit _ (StringLit _ t)  -> Just (VStr t)
  -- A NULLARY reference to a named date constant folds to its VALUE here, and
  -- only here. A cell endpoint IS a value, so inlining is what an endpoint
  -- means; the same reference inside an /expression/ must stay a name, because
  -- there it denotes a DMN decision variable (see 'renderFeelIn').
  App _ r [] | Just d <- Map.lookup (getUnique r) ctx.tcDateConstants -> Just (VDate d)
  App _ r []             -> constantRef ctx r
  e | Just d <- foldDateLiteral (oracleOf ctx) e -> Just (VDate d)
  _                      -> Nothing

-- | The 'Day' a @Date d m y@ application denotes, when every component is an
-- integer literal and the three name a real calendar day.
--
-- __A refusal, not a repair.__ @Date@ is LENIENT: @daydate.l4@:52-56 computes
-- @DATE_FROM_SERIAL (jan1serial + monthDays + day - 1)@, so @Date 32 1 2024@
-- rolls forward to 2024-02-01. Replicating the roll would put a date into the
-- artifact that the source does not obviously say, so an out-of-range component
-- falls through to the existing path instead, which is honest.
--
-- @YMD@ (@daydate.l4@:83-118) is deliberately NOT folded: its body is an
-- @IF ... THEN candidate ELSE \<ASSUME bottom\>@, so a naive structural match
-- would silently drop the refusal arm.
--
-- Prior art for the same predicate, on the NLG side:
-- "L4.Export.Document"'s @dateFromArgs@ (:1307-1315), reached from :1229.
foldDateLiteral :: TypeOracle -> Expr Resolved -> Maybe Day
foldDateLiteral oracle e = case e of
  App _ r [dE, mE, yE]
    | dateHead r
      -- Belt and braces against a user module shadowing `Date` with something
      -- of another type: ask the typechecker what the WHOLE application is.
    , oracleType oracle e == DmnDate
    , Just d <- intLitOf dE
    , Just m <- intLitOf mE
    , Just y <- intLitOf yE
    , d >= 1, d <= 31, m >= 1, m <= 12 ->
        fromGregorianValid y (fromInteger m) (fromInteger d)
  _ -> Nothing
 where
  dateHead r =
    getUnique r == TC.dateFromDMYUnique
      || nameOf r `elem` ["Date", "Days to date"]
      || unqualifiedNameToText (getActual r) `elem` ["Date", "Days to date"]

intLitOf :: Expr Resolved -> Maybe Integer
intLitOf = \case
  Lit _ (NumericLit _ r) | denominator r == 1 -> Just (numerator r)
  _                                           -> Nothing

constantRef :: TableCtx -> Resolved -> Maybe FeelValue
constantRef ctx = constantRefIn ctx.tcConstructors

constantRefIn :: Set Unique -> Resolved -> Maybe FeelValue
constantRefIn ctors r
  | u == TC.trueUnique    = Just (VBool True)
  | u == TC.falseUnique   = Just (VBool False)
  | isBuiltinSumCon r     = Nothing
  | isConstantRef ctors r = Just (VStr (nameOf r))
  | otherwise             = Nothing
 where
  u = getUnique r

-- | A constructor of one of L4\'s __builtin open sums__: @NOTHING@, @JUST@,
-- @LEFT@, @RIGHT@.
--
-- The typechecker stamps these with the @Constructor@ 'TermKind'
-- ("L4.TypeCheck.Environment"), exactly as it stamps a user-declared one, so
-- 'isConstructorKind' accepted them and 'constantRefIn' turned @NOTHING@ into
-- the S-FEEL __string constant__ @\"NOTHING\"@. Measured on the Charities and
-- Reg CF corpora: six decisions of the shape @IF p THEN JUST c ELSE NOTHING@
-- shipped with a @Blocking@ note on the @JUST@ arm and a silently wrong
-- @\"NOTHING\"@ on the other — strictly worse than a loud failure, because a
-- reader who checks the report sees one arm reported and concludes the other is
-- fine (R8-f).
--
-- __Excluding them from 'constantRefIn' is not sufficient on its own__, and the
-- second half is in 'renderFeelIn': without it a bare @NOTHING@ would fall
-- through to 'feelIdentIn' and render as a bare FEEL /identifier/ tagged
-- 'SFeel' — an unresolvable name carrying this module\'s strongest
-- executability claim, which is worse still. So a reference to one of these
-- renders __verbatim__, which is honest, and the decision that mentions it is
-- routed to a boxed literal expression with @D-SUMTYPE@ before any cell is
-- asked for (R8-d).
isBuiltinSumCon :: Resolved -> Bool
isBuiltinSumCon r = Set.member (getUnique r) builtinSumCons

builtinSumCons :: Set Unique
builtinSumCons =
  Set.fromList [TC.nothingUnique, TC.justUnique, TC.leftUnique, TC.rightUnique]

-- | Is this nullary reference a data constructor?
--
-- The question matters because 'L4.Syntax.Var' is a pattern synonym for
-- @App ann n []@, so "a nullary application is a nullary constructor" also
-- matches every @GIVEN@ parameter, every local binding and every zero-argument
-- @DECIDE@. Treating @WHEN EXACTLY lo@ as a constant would put the /name/ @lo@
-- in a cell as though it were a value — and, worse, would let the disjointness
-- check declare two such rows exclusive when @lo == hi@. (Same trap
-- GUARDED-ROWS.md §5a records for the ladder.)
--
-- Two independent witnesses, either of which suffices; neither guesses:
-- membership of the module's own declared constructors, and the @Constructor@
-- 'TermKind' the typechecker stamps on a resolved constructor name.
isConstantRef :: Set Unique -> Resolved -> Bool
isConstantRef ctors r = Set.member (getUnique r) ctors || isConstructorKind r

isConstructorKind :: Resolved -> Bool
isConstructorKind r = case getActual r of
  MkName cAnn _ -> case cAnn.extra.resolvedInfo of
    Just (TypeInfo _ (Just Constructor)) -> True
    _                                    -> False

-- | Is this the synthetic function "L4.Desugar" made out of a __computed record
-- field__ (a @MEANS@ clause on a @DECLARE@)?
--
-- @desugarComputedFields@ runs BEFORE typechecking, so by the time this module
-- sees a @DECLARE@ its computed fields are already gone: each is a top-level
-- @DECIDE@ of the shape @GIVEN … _self IS A R / GIVETH τ / f _self MEANS …@.
-- Recognising them is what lets §4.4 fold a computed read back into a hydrator
-- instead of shipping an L4 call no engine can resolve.
--
-- The provenance is carried by the 'TermKind', not reconstructed: 'TypeCheck'
-- stamps these 'ComputedSelector' rather than 'Computable', keyed off
-- @CheckEnv.computedFields@ — and 'resolveTermFiltered' writes the kind onto
-- every REFERENCE occurrence too, not only the definition, so no environment
-- has to be threaded here.
--
-- Two independent witnesses are accepted because 'withRange' skips RANGELESS
-- names, so a synthesised reference carries no stamp. Every reference this
-- module cares about comes from source and has a range; the definition's own
-- annotation is the second witness. Same construction 'isConstantRef' uses.
--
-- Deliberately NOT the test in "L4.Export.Document", which recognises the same
-- thing by comparing the receiver's name to the string @"_self"@. A name test
-- is what R8-f was.
isComputedSelectorKind :: Resolved -> Bool
isComputedSelectorKind r = case getActual r of
  MkName cAnn _ -> case cAnn.extra.resolvedInfo of
    Just (TypeInfo _ (Just ComputedSelector)) -> True
    _                                         -> False

-- | The record a 'ComputedSelector' decide belongs to, and its @_self@ binder.
--
-- @makeComputedDecide@ builds the signature as @typeParams ++ [selfParam]@ and
-- the app form as @f _self@, so the owning record is __the head type of the last
-- GIVEN parameter__ and the binder is the sole value parameter. The parameter
-- being spelled @_self@ corroborates but is not the key: the TYPE is.
computedSelectorOwner :: Decide Resolved -> Maybe (Unique, Resolved, Type' Resolved)
computedSelectorOwner (MkDecide _ (MkTypeSig _ (MkGivenSig _ gs) _) (MkAppForm _ _ [p] _) _) = do
  MkOptionallyTypedName _ selfN (Just selfTy) _ <- lastMaybe gs
  guard (getUnique selfN == getUnique p)
  u <- typeHeadUnique selfTy
  pure (u, p, selfTy)
 where
  lastMaybe xs = case reverse xs of
    (x : _) -> Just x
    []      -> Nothing
computedSelectorOwner _ = Nothing

-- | One computed record field, recovered from the synthetic @DECIDE@ the
-- desugaring left behind.
data ComputedField = MkComputedField
  { cfSel  :: !Resolved          -- ^ the selector: the synthetic decide's own name
  , cfSelf :: !Resolved          -- ^ its @_self@ binder
  , cfBody :: !(Expr Resolved)   -- ^ the field's @MEANS@ body, with siblings
                                 --   already rewritten to projections on @_self@
  }

-- | A __foldable computed read__ of a record instance: @x's f@ or @f x@, where
-- @f@ is a computed selector and @x@ is a nullary reference.
--
-- Both spellings occur in real corpora and both must be recognised: L4 house
-- style writes the projection, while @jl4\/examples\/legal\/regcf\/regcf-wizard.l4@
-- writes the application.
--
-- The receiver must be NULLARY. @greater of … (`investor profile from` facts)@
-- applies a computed selector to a record-valued EXPRESSION, which no hydrator
-- names, so it is not foldable and falls through to the ordinary verbatim path
-- with its existing @D-NONFEEL*@ diagnosis. That is a deliberate graceful
-- refusal rather than an oversight, and regcf-wizard.l4 is left carrying it so
-- the path stays exercised by a real file.
foldableComputedRead :: Expr Resolved -> Maybe (Resolved, Resolved)
foldableComputedRead = \case
  Proj _ (App _ x []) f | isComputedSelectorKind f -> Just (x, f)
  App _ f [App _ x []] | isComputedSelectorKind f  -> Just (x, f)
  _                                                -> Nothing

-- | The name of a binding, as DMN should spell it.
--
-- L4 gives a constructor or a stored record selector declared inside a @§@ a
-- section-qualified /spelling/ as well as its bare one (see
-- @specs\/todo\/SECTION-RANKING-SPEC.md@ and @addQualifiedAliases@ in
-- "L4.TypeCheck"). 'rawNameToText' renders that qualification by joining the
-- section path with @.@ — which is right for L4, where @.@ separates scopes,
-- and wrong for FEEL, where @.@ is path traversal into a value.
--
-- Flattening the qualified spelling into FEEL therefore produced text that
-- /parses/ as a path and cannot resolve: the corpus at
-- @jl4\/examples\/legal\/regcf\/regcf.l4@ emitted, among 22 such decisions,
--
-- > investor._3. Investor investment limits _ Rule 100_a__2_.annual income
--
-- — four path steps, of which two are a section heading with its punctuation
-- mangled by 'feelIdentText'. Because that renders as structured FEEL it never
-- reached the verbatim fallback, so no @D-NONFEELINPUT@ fired and the model
-- was silently unevaluable rather than loudly so. The same flattening put a
-- section heading in front of every enum value in the one clean decision table
-- the corpus produced.
--
-- FEEL has no notion of L4 sections, so the qualification cannot be carried,
-- and dropping it is the only honest rendering. Where dropping it makes two
-- bindings collide, @D-SCOPE@ already says so — that note is the reason this
-- is a documented loss rather than a silent one.
nameOf :: Resolved -> Text
nameOf = unqualifiedNameToText . getOriginal

------------------------------------------------------------------------
-- Columns
------------------------------------------------------------------------

-- | Column identity is the subject expression modulo annotations; column /order/
-- is first appearance, scanning rows in rule order and conjuncts left to right.
-- Both are properties of the source, so both are deterministic.
--
-- The FIRST cell to reach a column is kept, not just its key: 'clearAnno' erases
-- the inferred type and the source range along with the positions, so a column
-- built from the key alone could be neither typed nor located.
orderedColumns :: [[Cell]] -> [Cell]
orderedColumns rows = go Set.empty [c | row <- rows, c <- row]
 where
  go _ [] = []
  go seen (c : cs)
    | Set.member c.cellKey seen = go seen cs
    | otherwise                 = c : go (Set.insert c.cellKey seen) cs

-- | The column, and — from the same walk of the subject's type — its domain
-- (§3.1). One classification answers both, which is what keeps a column's
-- @typeRef@ and its @\<inputValues\>@ from being derived by two rules that can
-- disagree.
mkColumn :: TableCtx -> Int -> Cell -> InputColumn
mkColumn ctx i c = MkInputColumn
  { icId     = ctx.tcIdPrefix <> "_i" <> tshow i
  , icLabel  = oneLine (prettyLayout c.cellSubject)
  , icExpr   = renderFeelIn ctx.tcNames ctx.tcConstructors (oracleOf ctx) c.cellSubject
  , icType   = ty
  , icValues = dom
  }
 where
  (ty, dom, _) = oracleClassify (oracleOf ctx) c.cellSubject

-- | When L4's own type is opaque to FEEL, fall back to what the cells say.
typeFromCells :: [UnaryTest] -> DmnType
typeFromCells tests = case nub (concatMap kinds tests) of
  [t] -> t
  _   -> DmnAny
 where
  kinds = \case
    TestAny             -> []
    TestEq v            -> [kindOf v]
    TestCmp _ v         -> [kindOf v]
    TestNot t           -> kinds t
    TestOneOf ts        -> concatMap kinds ts
    TestRange _ lo hi _ -> [kindOf lo, kindOf hi]
  kindOf = \case
    VNum _  -> DmnNumber
    VStr _  -> DmnString
    VBool _ -> DmnBoolean
    VDate _ -> DmnDate

-- | @GIVETH@ wins; failing that, agreement among the output entries' own
-- literals. Deliberately syntactic, because this only runs when the declared
-- type said nothing and the annotation gave back an inference variable.
resolveOutputType :: TableCtx -> [FeelExpr] -> DmnType
resolveOutputType ctx outs
  | ctx.tcOutputType /= DmnAny = ctx.tcOutputType
  | otherwise = case nub (mapMaybe literalKind outs) of
      [t] | length (mapMaybe literalKind outs) == length outs -> t
      _ -> DmnAny
 where
  literalKind fe
    | fe.feFragment /= SFeel              = Nothing
    | fe.feText `elem` ["true", "false"]  = Just DmnBoolean
    | Text.isPrefixOf "\"" fe.feText      = Just DmnString
    | isNumericText fe.feText             = Just DmnNumber
    | otherwise                           = Nothing

isNumericText :: Text -> Bool
isNumericText t =
  not (Text.null t) && Text.all (\c -> isDigit c || c == '.' || c == '-') t

------------------------------------------------------------------------
-- Unary-test algebra
------------------------------------------------------------------------

-- | Two bounds on one column, as one interval. Only for numbers, and only when
-- the interval is non-empty; anything else returns 'Nothing' and the caller
-- falls back to a separate column.
mergeTests :: UnaryTest -> UnaryTest -> Maybe UnaryTest
mergeTests a b = case (a, b) of
  (TestCmp OpGeq lo, TestCmp OpLeq hi) -> range True lo hi True
  (TestCmp OpGeq lo, TestCmp OpLt  hi) -> range True lo hi False
  (TestCmp OpGt  lo, TestCmp OpLeq hi) -> range False lo hi True
  (TestCmp OpGt  lo, TestCmp OpLt  hi) -> range False lo hi False
  (TestCmp OpLeq _, TestCmp OpGeq _)   -> mergeTests b a
  (TestCmp OpLt  _, TestCmp OpGeq _)   -> mergeTests b a
  (TestCmp OpLeq _, TestCmp OpGt  _)   -> mergeTests b a
  (TestCmp OpLt  _, TestCmp OpGt  _)   -> mergeTests b a
  _                                    -> Nothing
 where
  range lc lo hi hc = case (lo, hi) of
    (VNum x, VNum y)   | x <= y -> Just (TestRange lc lo hi hc)
    -- The same merge on the DATE axis, which is what turns an inline law-time
    -- window (`RULES EFFECTIVE DATE AT LEAST d1 AND AT MOST d2`) into one
    -- interval cell rather than two boolean columns.
    (VDate x, VDate y) | x <= y -> Just (TestRange lc lo hi hc)
    _                           -> Nothing

-- | Can no input satisfy both cells? Sound but incomplete: a 'False' costs only
-- a hit-policy downgrade, never correctness.
testsDisjoint :: UnaryTest -> UnaryTest -> Bool
testsDisjoint a b = case (a, b) of
  (TestAny, _)                   -> False
  (_, TestAny)                   -> False
  (TestOneOf ts, u)              -> all (`testsDisjoint` u) ts
  (u, TestOneOf ts)              -> all (testsDisjoint u) ts
  (TestNot x, y)                 -> x == y
  (x, TestNot y)                 -> x == y
  (TestEq x, TestEq y)           -> x /= y
  (TestEq x, TestCmp op v)       -> refutes x op v
  (TestCmp op v, TestEq x)       -> refutes x op v
  (TestEq x, r@TestRange {})     -> not (inRange x r)
  (r@TestRange {}, TestEq x)     -> not (inRange x r)
  (TestCmp o1 v1, TestCmp o2 v2) -> cmpDisjoint o1 v1 o2 v2
  (TestCmp o v, r@TestRange {})  -> any (uncurry (cmpDisjoint o v)) (rangeBounds r)
  (r@TestRange {}, TestCmp o v)  -> any (uncurry (cmpDisjoint o v)) (rangeBounds r)
  (r1@TestRange {}, r2@TestRange {}) ->
    or [ cmpDisjoint o1 v1 o2 v2 | (o1, v1) <- rangeBounds r1, (o2, v2) <- rangeBounds r2 ]
 where
  refutes x op v = fromMaybe False (not <$> satisfies x op v)

rangeBounds :: UnaryTest -> [(CmpOp, FeelValue)]
rangeBounds = \case
  TestRange lc lo hi hc -> [(if lc then OpGeq else OpGt, lo), (if hc then OpLeq else OpLt, hi)]
  _                     -> []

inRange :: FeelValue -> UnaryTest -> Bool
inRange x r = and [fromMaybe True (satisfies x op v) | (op, v) <- rangeBounds r]

-- | Does @x@ satisfy @x op v@? 'Nothing' when the two are not comparable, in
-- which case every caller degrades to "assume it might".
satisfies :: FeelValue -> CmpOp -> FeelValue -> Maybe Bool
satisfies x op v = case (ordKey x, ordKey v) of
  (Just (kx, p), Just (kv, q)) | kx == kv ->
    Just $ case op of
      OpLt  -> p < q
      OpLeq -> p <= q
      OpGt  -> p > q
      OpGeq -> p >= q
  _ -> Nothing

-- | An ORDER KEY: which axis a value lives on, and where on it.
--
-- __Replaces a bare @Rational@, and the axis tag is the point.__ Two values on
-- DIFFERENT axes are not comparable at all, and every caller must degrade to
-- "assume they might overlap" rather than compare their positions — which is
-- exactly what a bare @Rational@ would have let it do the moment 'VDate'
-- existed, since a date's Modified Julian Day is a perfectly good number and
-- @TestEq (VNum 5)@ would have been declared disjoint from
-- @TestCmp OpLt (VDate ...)@ on arithmetic that means nothing.
--
-- Behaviour on every @VNum@-only table is unchanged.
ordKey :: FeelValue -> Maybe (Int, Rational)
ordKey = \case
  VNum r  -> Just (0, r)
  VDate d -> Just (1, fromInteger (toModifiedJulianDay d))
  VStr _  -> Nothing
  VBool _ -> Nothing

-- | Is @x op1 v1 AND x op2 v2@ unsatisfiable?
cmpDisjoint :: CmpOp -> FeelValue -> CmpOp -> FeelValue -> Bool
cmpDisjoint o1 v1 o2 v2 = fromMaybe False $ do
  (k1, p) <- ordKey v1
  (k2, q) <- ordKey v2
  guard (k1 == k2)
  pure $ case (o1, o2) of
    (OpLt,  OpGeq) -> p <= q
    (OpLt,  OpGt)  -> p <= q
    (OpLeq, OpGt)  -> p <= q
    (OpLeq, OpGeq) -> p < q
    (OpGeq, OpLt)  -> q <= p
    (OpGt,  OpLt)  -> q <= p
    (OpGt,  OpLeq) -> q <= p
    (OpGeq, OpLeq) -> q < p
    _              -> False

-- | Can the emitted table itself witness that no two rules both fire?
--
-- @grDisjoint@ is a claim about the L4 /guards/; hit policy @U@ is a claim about
-- the emitted /cells/, and the decomposition can lose the connection between
-- them. @income LESS THAN limit@ versus @income AT LEAST limit@ are exclusive in
-- L4, but neither has a constant endpoint, so both become boolean columns and the
-- two rules then overlap syntactically wherever both hold. Emitting @U@ on that
-- table would be a false claim about the artifact, so we check the cells and
-- downgrade to @F@ — always sound, since @F@ reproduces first-match order.
rulesPairwiseDisjoint :: [[UnaryTest]] -> Bool
rulesPairwiseDisjoint rules =
  and [or (zipWith testsDisjoint r1 r2) | (r1 : rest) <- tails rules, r2 <- rest]

------------------------------------------------------------------------
-- Law time: rule-date interval tables (spec §15.3)
------------------------------------------------------------------------

-- | One arm of a recognised rule-date chain.
data DatedArm = MkDatedArm
  { daDay    :: !Day
  , daRegime :: !(Maybe Resolved)
    -- ^ the named regime constant the guard applied the law-time predicate to,
    -- when the guard was written in the PREDICATE idiom. 'Nothing' for the
    -- inline idiom, which names no constant at all.
  , daGuard  :: !(Expr Resolved)
  , daBody   :: !(Expr Resolved)
  }

-- | What a guarded chain turned out to be.
data DatedChain
  = NotDated
    -- ^ take the existing path, with its existing findings, unchanged.
  | Dated ![DatedArm] !(Expr Resolved) !Resolved
    -- ^ arms newest-first, the @OTHERWISE@ body, and the law-time reference the
    -- emitted column's subject is built from (a real 'Resolved', never a
    -- synthesised one).
  | DatedRefused !Text
    -- ^ it looked dated and could not be tabled; say why, loudly.

-- | Does this chain read the rule date on every arm, against a foldable
-- constant date, in strictly descending order?
--
-- __Conservative and all-or-nothing__, in the manner of
-- "L4.OpenFisca.Lower"'s @splitDated@ (:589-593). A chain that mixes a
-- rule-date arm with an ordinary one is exactly how a temporal bug hides, and
-- half-converting it would be worse than either alternative.
datedChain
  :: TableCtx
  -> Map Unique Resolved   -- ^ law-time PREDICATES: their 'Unique' ↦ the law-time ref in the body
  -> GuardedRows
  -> DatedChain
datedChain ctx preds rows = case rows.grOtherwise of
  -- A CONSIDER-derived chain with no OTHERWISE has no floor row to derive.
  Nothing -> NotDated
  Just oth
    -- 'rowsToDmnWith'' refuses three shapes BEFORE it builds anything (:315-319)
    -- and this path does not go through it, so those refusals must be restated
    -- here or they stop applying the moment a chain happens to look dated.
    -- @NoRules@ is unreachable ('Dated' means a non-empty `arms`), but the other
    -- two are NOT: a deontic body is a transition system rather than a value —
    -- DMN "has no notion of time" and cannot hold an obligation as a state — and
    -- tabulating an effectful guard changes how often the effect runs. Both
    -- shapes are one law-time guard away in this very corpus (`regcf.l4:638-642`
    -- is @IF cond THEN <regulative> ELSE <regulative>@), so returning 'NotDated'
    -- here is what keeps 'RegulativeBody' and 'EffectfulGuard' reachable.
    | any isRegulative (guards <> bodies <> [oth]) -> NotDated
    | any hasEffectfulNode guards -> NotDated
    -- Zero arms matched: this is an ordinary chain, and nothing is refused.
    | null arms, null badDates -> NotDated
    | (i, why) : _ <- badDates ->
        DatedRefused ("arm " <> tshow i <> " of the chain " <> why)
    | (i, g) : _ <- others     ->
        DatedRefused
          ("arm " <> tshow i <> " of the chain (`" <> oneLine (prettyLayout g)
             <> "`) is not a rule-date guard while "
             <> tshow (length arms) <> " other arm(s) are, so the chain has no \
                \single date axis")
    | Just why <- outOfOrder   -> DatedRefused why
    | not (rulesPairwiseDisjoint (map (: []) (datedTests arms))) ->
        DatedRefused
          "the derived intervals are not pairwise disjoint -- this is an exporter \
          \defect, please report it"
    -- The cross product of a date axis with an inner axis is a bigger design;
    -- v1 handles the flat case, which is 8 of 8 in the corpus. The @OTHERWISE@
    -- counts as an arm body here: on the ordinary path @expandOtherwise@ splices
    -- a nested catch-all chain's rows into the table (and reports what it
    -- declines to splice as @D-FLATTENCAP@), whereas the dated path would
    -- collapse the whole nested chain into one floor-row output entry with no
    -- note at all.
    | any (isJust . normaliseGuarded) (oth : map (.daBody) arms) -> NotDated
    | (lawRef : _) <- lawRefs -> Dated arms oth lawRef
    -- Unreachable: a non-empty `arms` implies a non-empty `lawRefs`, since both
    -- come from the same 'RowDated' constructor. Spelled as a fallthrough
    -- rather than a `head` so that the invariant cannot become a crash.
    | otherwise -> NotDated
 where
  classified = zip [1 :: Int ..] (map classifyRow rows.grRows)

  guards = map fst rows.grRows
  bodies = map snd rows.grRows

  -- Every ordinal a refusal quotes is an index into the CHAIN's own rows, so
  -- "arm 3" means the same source arm in all three messages. Numbering the
  -- matched arms separately (which an earlier draft did for the ordering
  -- refusal) made "arm 3" mean two different things on one file.
  armsIx   = [(i, a)   | (i, RowDated a _)   <- classified]
  arms     = map snd armsIx
  lawRefs  = [r        | (_, RowDated _ r)   <- classified]
  badDates = [(i, why) | (i, RowBadDate why) <- classified]
  others   = [(i, fst row) | ((i, RowOther), row) <- zip classified rows.grRows]

  -- Strictly descending, which also covers DUPLICATE dates: two arms on one day
  -- make the second dead, and an empty @[d..d)@ interval would be isomorphic to
  -- that but un-analysable. Same predicate as "L4.OpenFisca.Lower"'s
  -- @strictlyDescDates@ (:521-523).
  outOfOrder = listToMaybe
    [ "arm " <> tshow j <> " of the chain (`" <> oneLine (prettyLayout b.daGuard)
        <> "`) is dated " <> Text.pack (showGregorian b.daDay)
        <> ", which is not strictly earlier than arm " <> tshow i <> "'s "
        <> Text.pack (showGregorian a.daDay)
    | ((i, a), (j, b)) <- zip armsIx (drop 1 armsIx)
    , not (a.daDay > b.daDay)
    ]

  oracle = oracleOf ctx

  isLawTime r = getUnique r == TC.rulesEffectiveDateUnique

  -- Only the conjunct COUNT is structural here; a multi-conjunct dated guard
  -- (`lawtime >= d AND something`) is a v1 non-goal and takes the ordinary path.
  classifyRow (g, b) = case filter (not . inertNode) (conjuncts (carameliseExpr g)) of
    [c] -> lawTimeGuard g b c
    _   -> RowOther

  inertNode = \case
    Inert {} -> True
    _        -> False

  lawTimeGuard g b = \case
    -- (a) the PREDICATE idiom, as the Reg CF corpus writes it.
    App _ f [arg] | Just lawRef' <- Map.lookup (getUnique f) preds ->
      case constantDay arg of
        Just (d, reg) -> RowDated (MkDatedArm d reg g b) lawRef'
        Nothing       -> RowBadDate (badDateReason arg)
    -- (b) the same comparison written INLINE against a `Date d m y` literal.
    -- `AT LEAST` desugars to an application that 'carameliseExpr' turns back
    -- into 'Geq'; the mirrored `AT MOST` form is 'Leq' and means the same
    -- relation. Strict comparators are a v1 non-goal and reach 'RowOther'.
    Geq _ (App _ r []) e | isLawTime r -> inlineArm g b r e
    Leq _ e (App _ r []) | isLawTime r -> inlineArm g b r e
    _ -> RowOther

  -- 'constantDay', NOT the bare literal fold. The inline idiom is the predicate
  -- idiom with the one-line helper elided, so
  -- @`RULES EFFECTIVE DATE` AT LEAST `the 2024 rate change`@ carries exactly the
  -- information the predicate form does and must fold the same way — and the
  -- regime constant it names is then available to the annotation column, which
  -- is strictly better than degrading to a bare @from <day>@. An earlier draft
  -- called 'foldDateLiteral' here, which refused every such chain while
  -- 'badDateReason' told the reader that nullary constants ARE folded.
  inlineArm g b r e = case constantDay e of
    Just (d, reg) -> RowDated (MkDatedArm d reg g b) r
    Nothing       -> RowBadDate (badDateReason e)

  badDateReason e =
    "has date `" <> oneLine (prettyLayout e)
      <> "`, which is not a foldable date constant (only `Date d m y` over three \
         \integer literals, or a nullary decision whose body is one, is folded; \
         \`YMD` and computed dates are not)"

  -- One hop through the module's named date constants, then the literal fold.
  constantDay e = case e of
    App _ c [] | Just d <- Map.lookup (getUnique c) ctx.tcDateConstants -> Just (d, Just c)
    _ -> (\d -> (d, Nothing)) <$> foldDateLiteral oracle e

-- | Internal: a row's classification, and the law-time reference it found.
data RowKind
  = RowDated !DatedArm !Resolved
  | RowBadDate !Text
  | RowOther

-- | The half-open interval cells a chain's arms denote, plus the floor row.
--
-- For arms dated @d₁ > d₂ > … > dₙ@, L4's first-match semantics are exactly
-- @r₁ ⟺ x ≥ d₁@, @rᵢ ⟺ dᵢ ≤ x < dᵢ₋₁@, @floor ⟺ x < dₙ@ — total over the date
-- axis and pairwise disjoint, which is what buys @hitPolicy="UNIQUE"@ and, with
-- it, gap and overlap analysis __by construction__.
datedTests :: [DatedArm] -> [UnaryTest]
datedTests [] = []
datedTests arms =
  zipWith mk (Nothing : map (Just . (.daDay)) arms) arms <> [floorTest]
 where
  mk Nothing     a = TestCmp OpGeq (VDate a.daDay)
  mk (Just prev) a = TestRange True (VDate a.daDay) (VDate prev) False
  floorTest = TestCmp OpLt (VDate (last arms).daDay)

-- | Build the interval table directly, rather than routing through
-- 'rowsToDmnWith''.
--
-- __The generic path cannot produce this and was not asked to.__ @policy@
-- (:330) requires @rows.grDisjoint@, which comes from @guardsDisjoint@
-- ("L4.Viz.GuardedRows":182-197); its @exclusive@ relation has no @(Geq, Geq)@
-- case, so two @>=@ guards are never exclusive there and every dated chain would
-- stay @FIRST@ no matter what the cells said.
--
-- 'tableNotes' is REUSED rather than duplicated, so the output-side families
-- (@D-NONFEELOUTPUT@, @D-COMPUTEDOUTPUT@) still see exactly the bodies they see
-- today, and the input-side families fall silent because the one column really
-- is S-FEEL.
datedTable
  :: TableCtx
  -> Map Unique Text        -- ^ @\@ref@ text, by decide 'Unique'
  -> Map Unique SrcRange    -- ^ definition position, by decide 'Unique'
  -> GuardedRows
  -> [DatedArm]
  -> Expr Resolved          -- ^ the @OTHERWISE@ body
  -> Resolved               -- ^ the law-time reference
  -> [Text]                 -- ^ names of inlined WHERE\/LET locals
  -> DecisionTable
datedTable ctx refs ranges rows arms oth lawRef inlined = table
 where
  lawExpr = App emptyAnno lawRef []
  tests   = datedTests arms

  -- Asserted, not inferred: the subject is SYNTHESISED, so 'oracleClassify'
  -- would answer 'DmnAny' on it. ('retype' only fires on 'DmnAny' and so will
  -- not touch this.) 'icValues' stays Nothing because the date axis is
  -- unbounded; §3.1's inputValues is for finite domains.
  column = MkInputColumn
    { icId     = ctx.tcIdPrefix <> "_i1"
    , icLabel  = oneLine (prettyLayout lawExpr)
      -- 'feelIdentIn' reads 'neVars', so a collision rename propagates here.
    , icExpr   = MkFeelExpr (feelIdentIn ctx.tcNames lawRef) SFeel
    , icType   = DmnDate
    , icValues = Nothing
    }

  cellOf t = MkCell
    { cellKey      = clearAnno lawExpr
    , cellSubject  = lawExpr
    , cellTest     = t
    , cellFallback = False
    , cellNote     = False
    }

  decomposed  = [[cellOf t] | t <- tests]
  columnCells = take 1 (map cellOf tests)

  -- The output-rendering asymmetry of 'rowsToDmnWith'' is REPRODUCED, not
  -- repaired: dated rows render their output with an empty constructor set and
  -- the floor row with the module's, exactly as :339 and :351 already do. So
  -- every output entry is byte-identical to today's, and the golden diff is
  -- confined to columns and cells. Unifying the two is a separate change.
  ruleSpecs =
    [ (t, Just (oneLine (prettyLayout a.daGuard)), a.daBody, Set.empty, armAnnotation a)
    | (t, a) <- zip tests arms
    ]
      <> [ ( last tests
           , Just "OTHERWISE"
           , oth
           , ctx.tcConstructors
           , floorAnnotation
           )
         ]

  allRules =
    [ MkDmnRule
        { drId          = ctx.tcIdPrefix <> "_r" <> tshow i
        , drInputs      = [t]
        , drOutput      = renderFeelIn ctx.tcNames ctors (oracleOf ctx) b
        , drDescription = desc
        , drAnnotations = [ann]
        }
    | (i, (t, desc, b, ctors, ann)) <- zip [1 :: Int ..] ruleSpecs
    ]

  named r =
    nameOf r
      <> maybe "" ((" \8212 " <>) . stripRefKeyword) (Map.lookup (getUnique r) refs)
      <> maybe "" (\sr -> " (" <> prettySrcRange sr <> ")")
           (Map.lookup (getUnique r) ranges)

  -- The lexed `Ref` text keeps its own `@ref` keyword. That token is L4 syntax,
  -- not part of the citation, and an annotation column is read by a human.
  stripRefKeyword t = fromMaybe t (Text.stripPrefix "@ref " (Text.strip t))

  armAnnotation a = case a.daRegime of
    Just r  -> named r
    -- The inline idiom names no constant, so the day itself is the whole of
    -- what the source says about this regime.
    Nothing -> "from " <> Text.pack (showGregorian a.daDay)

  floorAnnotation = case oth of
    App _ r [] -> named r
    _          -> "before " <> Text.pack (showGregorian (last arms).daDay)

  outColumn = MkOutputColumn
    { ocId      = ctx.tcIdPrefix <> "_o1"
    , ocName    = ctx.tcFeelName
    , ocType    = resolveOutputType ctx (map (.drOutput) allRules)
    , ocValues  = if ctx.tcOutputType /= DmnAny then ctx.tcOutputValues else Nothing
      -- R9: the OTHERWISE is a floor ROW, so there is no defaultOutputEntry.
      -- §3.3.1's SHALL then REQUIRES omitting it: the rules already cover the
      -- input space, and a default on a complete table declares it incomplete.
    , ocDefault = Nothing
    }

  table = MkDecisionTable
    { dtId          = ctx.tcIdPrefix <> "_table"
    , dtName        = ctx.tcName
    , dtHitPolicy   = HitUnique
    , dtInputs      = [column]
    , dtOutput      = outColumn
    , dtRules       = allRules
    , dtAnnotations = ["regime"]
    , dtNotes       = tableNotes ctx decomposed columnCells [column] HitUnique rows inlined []
    }

-- | The references the EMITTED TEXT still names, plus the instances it reaches
-- THROUGH a hydrator.
--
-- This is R11's function, and it now serves both rewrites:
--
--   * §15.3, law time. A dated table's cells reference the rule-date input and
--     its expression no longer references the guard predicate or the regime
--     constants, so its @informationRequirement@s are computed from the bodies
--     that SURVIVE into the artifact rather than from the source.
--   * §4.4, hydration. On a foldable computed read this records the INSTANCE
--     and does NOT descend into the receiver or the selector, because after the
--     fold neither appears in the emitted FEEL. The caller turns the recorded
--     instance into an edge to its hydrator.
--
-- Fold-aware traversal rather than a filter over the free references, because
-- a filter cannot tell a name that was folded away from one that is still
-- there. A DRG whose edges named a variable its expression no longer mentions
-- would be describing a different model.
--
-- It SUBSUMES the @exprFreeRefs@ it replaced and carries over both of that
-- function's exclusions unchanged: a name bound inside the body (@Def@ covers
-- lambda parameters, LET\/WHERE locals and pattern binders without enumerating
-- them) and a projection's SELECTOR, which is a reference but not a term.
--
-- ★ The fold is expressed as a PRUNE of the tree followed by the SAME total
-- @toList@ collection @exprFreeRefs@ used, and that shape is load-bearing. The
-- first version of this function walked the tree with a per-node WHITELIST
-- (@App@ contributes its head, @Proj@ contributes nothing, everything else
-- contributes nothing), which silently dropped every name that is not an
-- @App@ head: an 'AppNamed' head above all, but also the names inside
-- 'Regulative', 'Event', 'Record' and — wherever @gplate@ does not descend —
-- @WHERE@\/@LET@ local bodies and @CONSIDER@ arms. Because 'dcnRequirements'
-- can only ever REMOVE edges relative to the source, the loss was invisible in
-- the goldens and showed up only as a decision whose text named a decision its
-- graph did not require. A prune cannot have that failure mode: what is not
-- folded is collected exactly as before.
survivingRefs :: [Expr Resolved] -> ([Resolved], [Unique])
survivingRefs bodies =
  ( nubOrdOn getUnique
      [ r
      | b <- pruned
      , r@Ref {} <- toList b
      , not (Set.member (getUnique r) bound)
      , not (Set.member (getUnique r) projFields)
      ]
  , nubOrd touched
  )
 where
  -- The fold. Neither the receiver nor the selector survives into the emitted
  -- text, so the whole read is replaced by a name-free placeholder; the
  -- INSTANCE is recorded separately so the caller can add the hydrator edge
  -- that replaces the direct one.
  pruned = map (transformOf (gplate @(Expr Resolved)) prune) bodies

  prune e = case foldableComputedRead e of
    Just _  -> Lit (getAnno e) (NumericLit emptyAnno 0)
    Nothing -> e

  touched =
    [ getUnique x
    | b <- bodies
    , e <- toListOf (cosmosOf (gplate @(Expr Resolved))) b
    , Just (x, _) <- [foldableComputedRead e]
    ]

  bound = Set.fromList [u | b <- bodies, Def u _ <- toList b]

  projFields = Set.fromList
    [ getUnique n
    | b <- pruned
    , Proj _ _ n <- toListOf (cosmosOf (gplate @(Expr Resolved))) b
    ]

------------------------------------------------------------------------
-- L4 -> FEEL
------------------------------------------------------------------------

-- | Render an L4 expression as FEEL, and say honestly which fragment the result
-- lies in.
--
-- 'SFeel' is the claim that matters: DMN's completeness, consistency and overlap
-- checking are all defined over S-FEEL (@simple expression = arithmetic
-- expression | simple value | comparison@, grammar rule 3). Boolean connectives,
-- function invocation and @if@ are ordinary FEEL but outside that grammar, so
-- they are 'FullFeel'; anything we cannot render at all is 'L4Verbatim' and the
-- text is L4.
--
-- If any sub-expression is 'L4Verbatim' the whole node is re-rendered with
-- 'prettyLayout' rather than spliced, so the text never mixes the two languages.
renderFeel :: Expr Resolved -> FeelExpr
renderFeel = renderFeelIn emptyNameEnv Set.empty noTypeOracle

-- | 'renderFeel', told which nullary references are data constructors, and given
-- a 'TypeOracle'.
--
-- The constructor set matters on the OUTPUT side and is easy to get wrong: a
-- constructor is a /value/, and FEEL has no sum types, so it must be quoted.
-- Rendered as a bare name it would read as a reference to a variable of that
-- name — and it would disagree with the input side, where 'constantOf' has
-- already quoted the same constructor into a @\"red\"@ cell.
--
-- The oracle answers the one question FEEL's grammar cannot: which of L4's
-- comparisons DMN actually orders. It decides whether the select idiom may fold
-- ('selectIdiomIn'), and whether a bare @\<@ \/ @\<=@ \/ @\>@ \/ @\>=@ is FEEL
-- at all (see 'ordering' below). Both fall out of DMN 1.3 Table 54, so both ask
-- the same predicate family and cannot drift apart.
renderFeelIn :: NameEnv -> Set Unique -> TypeOracle -> Expr Resolved -> FeelExpr
renderFeelIn names ctors oracle top = let (_, txt, frag) = go top in MkFeelExpr (oneLine txt) frag
 where
  -- (precedence, text, fragment)
  go :: Expr Resolved -> (Int, Text, FeelFragment)
  go e = case e of
    Lit _ (NumericLit _ r) -> (atomPrec, renderNumber r, SFeel)
    Lit _ (StringLit _ s)  -> (atomPrec, quoteFeelString s, SFeel)
    -- R8-d′ (ruled 2026-07-31). NOTHING is FEEL's `null`.
    --
    -- The fragment is 'FullFeel' and never 'SFeel', deliberately: DMN 1.3
    -- grammar rule 34 makes `null` a LITERAL, and rule 33's `simple literal` is
    -- numeric | string | boolean | date-time only, so tagging it 'SFeel' would
    -- admit it to a cell ENDPOINT, which R8-d′ refuses. The mechanical
    -- guarantee is separate and stronger and does not depend on this tag being
    -- right: there is no @VNull@ in 'FeelValue', and 'constantRefIn' still
    -- short-circuits on 'isBuiltinSumCon', so `null` cannot reach an
    -- @\<inputEntry\>@ by any route.
    --
    -- LEFT and RIGHT keep the old verbatim treatment unchanged (R8-e): EITHER
    -- has no FEEL image at all, and R8-f's defect -- a constructor silently
    -- becoming the S-FEEL string constant @"LEFT"@ -- is still fixed for them
    -- by the same mechanism.
    --
    -- ★ Every arm below that gives a MAYBE a FEEL image is GUARDED on
    -- 'flatMaybe', and the guard is what keeps R8-c a refusal rather than a
    -- wrong answer. A @D-SUMTYPE@ note does NOT stop the body being rendered --
    -- 'literalFallback' renders it and reports Blocking beside it -- so on a
    -- @MAYBE (MAYBE τ)@ an unguarded arm would emit FEEL that COMPILES and
    -- answers differently from L4 (`JUST NOTHING` and `NOTHING` both become
    -- `null`, so an absence test says "absent" where L4 says "present"). That
    -- is an ANSWER CHANGE, and it would be a strictly worse artifact than the
    -- L4 source no engine can compile that this backend emitted before
    -- R8-d′. Refused here, the expression falls through to 'verbatim' and the
    -- refusal stays loud.
    App _ r [] | getUnique r == TC.nothingUnique, flatMaybe e -> (atomPrec, "null", FullFeel)
               | isBuiltinSumCon r                            -> verbatim e
               -- A BARE reference to an emitted BKM (§6.3-2): a BKM is an
               -- invocable, not a variable, and its FEEL name no longer names
               -- a decision variable — rendering it bare would be valid-looking
               -- FEEL that KIE refuses and Camunda nulls. Verbatim, Blocking.
               | Map.member (getUnique r) names.neBkms        -> verbatim e
               | otherwise                                    -> (atomPrec, nullaryText r, SFeel)
    -- JUST x IS x. FEEL has one flat null and no tag, so the constructor has no
    -- image; the payload does. (R8-d′)
    App _ r [x] | getUnique r == TC.justUnique, flatMaybe e -> go x
    -- The combinator table, checked BEFORE the general App arms so that the
    -- prelude's own CONSIDER -- which this exporter never sees -- is not what
    -- decides the rendering. Recognised by the RESOLVED UNIQUE of the prelude
    -- definition (see 'resolveMaybePredicates'), never by name string: matching
    -- on a name is precisely the class of defect R8-f was.
    App _ r [x]
      | Just mp <- names.neMaybePreds, getUnique r == mp.mpIsJust, flatMaybe x ->
          nullCompare e "!=" x
      | Just mp <- names.neMaybePreds, getUnique r == mp.mpIsNothing, flatMaybe x ->
          nullCompare e "="  x
    -- §4.4. INSIDE a hydrator, rendering a computed field's own body, a
    -- projection on the `_self` binder is the BARE sibling entry name: a boxed
    -- context's entries see each other unqualified. This is what turns
    -- `_self's amount TIMES 2` into `amount * 2`.
    Proj _ (App _ r []) n
      | Set.member (getUnique r) names.neBareProj ->
          (atomPrec, feelFieldIn names n, SFeel)
    -- §4.4, the DOWNSTREAM half. A computed read of a hydrated instance folds
    -- to a path access on the HYDRATOR, and the receiver and the selector both
    -- disappear from the emitted text -- which is why 'survivingRefs' must not
    -- descend into them when it computes the DRG edges.
    --
    -- 'SFeel' is the right claim and the same one the ordinary Proj case makes:
    -- a qualified name is FEEL grammar rule 20 and is inside S-FEEL.
    _ | Just (x, f) <- foldableComputedRead e
      , Just h <- Map.lookup (getUnique x) names.neHydrated ->
          (atomPrec, h <> "." <> feelFieldIn names f, SFeel)
    -- §4.4 × §6.2: a computed read through a BKM PARAMETER. The parameter is
    -- per-call, so no global hydrator can stand for it; the faithful form is
    -- to inline the selector's own body with `_self` substituted by the
    -- receiver, which turns `investor's greater of a or b` into FEEL over the
    -- parameter's STORED components (`max(investor.a, investor.b)`). Gated to
    -- BKM parameters (so D12's verbatim boundary is untouched everywhere
    -- else) and to SELF-CONTAINED selectors ('neComputedInline' membership),
    -- so the inline cannot pull module globals or sibling computed reads into
    -- a BKM body behind the closure computation's back.
    _ | Just (x, f) <- foldableComputedRead e
      , Set.member (getUnique x) names.neBkmParams
      , Just (self, sbody) <- Map.lookup (getUnique f) names.neComputedInline ->
          go (substLocals (Map.singleton self (App emptyAnno x [])) sbody)
    -- §4.4, D12's boundary, preserved under Phase 4 un-lifting: a COMPUTED
    -- field that was NOT folded onto a hydrator (the arm above) has no image
    -- in the artifact — the emitted record carries stored components only —
    -- so `base.computedField` would be valid FEEL silently answering null.
    -- Verbatim, and Blocking-noted, is the honest form. Before un-lifting
    -- this arm was unreachable in practice, because the refused receivers
    -- were themselves verbatim and poisoned the whole projection.
    Proj _ _ n | Set.member (getUnique n) names.neComputedFields -> verbatim e
    -- A projection path is FEEL's `qualified name`, and its steps live in the
    -- FIELD namespace (§5.2 scope 2), not the DRG's variable namespace. That is
    -- where the one executed corpus collision lands (§5.3.4): two distinct
    -- fields folding to one path step is valid FEEL computing a wrong number.
    Proj _ x n             -> unary e SFeel (\t -> t <> "." <> feelFieldIn names n) x
    Plus      _ a b -> binary e 6 SFeel "+"  a b
    Minus     _ a b -> binary e 6 SFeel "-"  a b
    Times     _ a b -> binary e 7 SFeel "*"  a b
    DividedBy _ a b -> binary e 7 SFeel "/"  a b
    Lt        _ a b -> ordering e "<"  a b
    Leq       _ a b -> ordering e "<=" a b
    Gt        _ a b -> ordering e ">"  a b
    Geq       _ a b -> ordering e ">=" a b
    -- Equality, unlike ordering, is total in FEEL: Table 52 requires only that
    -- both sides be "of the same kind/datatype", and Table 53 gives boolean its
    -- own row ("e1 and e2 must both be true or both be false").
    Equals    _ a b -> binary e 5 SFeel "="  a b
    -- Inert text is grammatical scaffolding -- a quoted fragment of the statute
    -- carried along for isomorphism -- whose VALUE is its context's identity
    -- element. That is the evaluator's own definition
    -- ("L4.EvaluateLazy.Machine": @InertCtxAnd -> ValBool True@,
    -- @InertCtxOr -> ValBool False@, @InertCtxNone -> ValBool True@), and the
    -- ladder reads it the same way. A boolean literal is S-FEEL, so this costs
    -- nothing. The words are not lost: a guard's full source text is already the
    -- rule's @\<description\>@. Before this case, 794 statute quotations in the
    -- Charities corpus alone poisoned their enclosing guards into L4 source.
    Inert _ _ ictx -> (atomPrec, inertText ictx, SFeel)
    -- @n %@ is @n / 100@ ("L4.EvaluateLazy.Machine":
    -- @UnaryPercent -> ValNumber (val / 100)@), and division is inside S-FEEL's
    -- `arithmetic expression`, so the fragment claim is unchanged. Written at
    -- division's own precedence rather than wrapped in parentheses, because
    -- S-FEEL's grammar has no parenthesised-expression production (rules 2, 3,
    -- 16-21): @(10 %) TIMES base@ becomes @10 / 100 * base@, which is how the
    -- Reg CF exhibit already spells the same quantity.
    Percent _ x ->
      let (p, t, f) = go x
      in if f == L4Verbatim
           then verbatim e
           else (7, parenIf (p < 7) t <> " / 100", max SFeel f)
    -- Legal FEEL, outside S-FEEL's `simple expression`.
    And    _ a b -> binary e 3 FullFeel "and" a b
    Or     _ a b -> binary e 2 FullFeel "or"  a b
    Modulo _ a b -> call e "modulo" [a, b]
    Not    _ a   -> call e "not" [a]
    -- FEEL has no implication operator; material implication is the reading L4
    -- gives a constitutive IMPLIES, and it is what the ladder's seam draws.
    Implies _ a b -> pair e FullFeel (\ta tb -> "(not(" <> ta <> ") or " <> tb <> ")") a b
    List _ xs -> nary e FullFeel (\ts -> "[" <> Text.intercalate ", " ts <> "]") xs
    -- FEEL has no cons operator, but it has `concatenate` (DMN 1.1 §10.3.4), and
    -- a one-element list literal is how you spell the head.
    Cons _ x xs -> pair e FullFeel (\tx txs -> "concatenate([" <> tx <> "], " <> txs <> ")") x xs
    -- @AppNamed@: the RECORD-CONSTRUCTION subset lowers to a FEEL context
    -- literal; everything else still falls to 'verbatim' below and is reported
    -- Blocking. An unrestricted @{f: v, …}@ lowering was once written and
    -- REVERTED for four measured reasons; the arm below is gated so that each
    -- is answered rather than reintroduced:
    --
    --   1. @AppNamed@ is L4\'s general NAMED-ARGUMENT APPLICATION, not record
    --      construction ('inferAppNamed' types it against any @Fun@) — so the
    --      head must resolve in 'neRecordCtors', which holds record
    --      constructors and nothing else. @f WITH x IS 3@ over a function @f@
    --      stays verbatim. (A named-argument call to an emitted BKM also stays
    --      verbatim + Blocking — deferred, recorded in spec §6.1.)
    --   2. An enum\'s payload constructor carries a TAG FEEL cannot spell
    --      (@Paid WITH amount IS 40@ ≠ @Owed WITH amount IS 40@) — so enum
    --      constructors are not in the map at all, and stay under @D-SUMTYPE@.
    --      A record has one constructor; a context IS its faithful image, and
    --      it is the same image hydration already gives records.
    --   3. Field names must be FEEL-safe — the entry keys come from the same
    --      'neFields' scope the 'ItemComponent' names and 'Proj' path steps
    --      use, so a field called @for@ folds exactly as its component does
    --      and the write side cannot disagree with the read side.
    --   4. Computed fields are ABSENT from the context, deliberately: a
    --      stored-components-only context is what the hydration design calls
    --      the record, and every computed READ is separately guarded — folded
    --      onto a hydrator (global instances), inlined ('neComputedInline',
    --      BKM parameters), or refused verbatim ('neComputedFields'). The
    --      construction must still supply every STORED field exactly once, or
    --      a missing entry would answer null where L4 has a value — the guard
    --      compares the supplied set against the declaration.
    AppNamed _ r nes _
      | Just fields <- Map.lookup (getUnique r) names.neRecordCtors
      , let supplied = Map.fromList [(getUnique n, (n, x)) | MkNamedExpr _ n x <- nes]
      , length nes == length fields
      , Map.keysSet supplied == Set.fromList fields ->
          let entries =
                [ (feelFieldIn names n, go x)
                | fu <- fields
                , Just (n, x) <- [Map.lookup fu supplied]
                ]
          in if any (\(_, (_, _, fr)) -> fr == L4Verbatim) entries
               then verbatim e
               else ( atomPrec
                    , "{" <> Text.intercalate ", " [k <> ": " <> t | (k, (_, t, _)) <- entries] <> "}"
                    , FullFeel
                    )
    -- A conditional whose arms ARE its comparison's operands is not a decision;
    -- it is `max` / `min`. Lower it to FEEL's own function rather than to an
    -- `if`, the way a compiler backend recognises a select pattern instead of
    -- emitting a branch.
    IfThenElse _ c t f
      | Just (fn, a, b) <- selectIdiomIn oracle e -> call e fn [a, b]
      | otherwise ->
          triple e FullFeel (\tc tt tf -> "(if " <> tc <> " then " <> tt <> " else " <> tf <> ")") c t f
    -- A call to an L4 function is NOT a FEEL function invocation, and this used
    -- to be rendered @f(args)@ and labelled 'FullFeel' -- a claim of
    -- executability the exporter cannot honour. FEEL resolves an invocation
    -- against its own builtins or against a BKM in the same DRG, and this
    -- exporter emits neither: an L4 @DECIDE@ becomes a 0-ary DMN decision
    -- variable (Vandevelde et al.: "the 'variables' of standard DMN correspond
    -- to constants"), so @f(x)@ names nothing an engine can resolve. Drools/KIE
    -- 8.44 answers @Unknown variable 'JUST'@ for @JUST(40)@ -- which the shipped
    -- Charities corpus emitted four times -- and the whole decision evaluates to
    -- null. So it is verbatim, and the report says Blocking. The FEEL builtins
    -- this backend DOES emit (@not@, @modulo@, @max@, @min@, @concatenate@) are
    -- constructed here by name and never routed through this case.
    -- ...with one exception, and it is a LITERAL rather than a call: `Date d m
    -- y` over three integer literals denotes a day, and FEEL can spell a day.
    -- `date("YYYY-MM-DD")` is DMN 1.3 grammar rule 21's `date time literal` and
    -- rule 33's `simple literal`, so the fragment claim is SFeel, not FullFeel.
    --
    -- A NULLARY reference to a named date constant is deliberately NOT folded
    -- here: it names a DMN decision variable, and inlining its value into an
    -- expression would erase a reference the DRG records. Only cells inline
    -- (see 'constantOf').
    App _ _ (_ : _) | Just d <- foldDateLiteral oracle e ->
      (atomPrec, renderFeelValue (VDate d), SFeel)
    -- Phase 4 un-lifting (§2.1): a saturated call to a tier-1, DMN-SAFE
    -- decision renders as the callee's bare FEEL name. The decision's
    -- parameters are module-level inputData now, so the FEEL name resolves to
    -- its <decision> variable and the requiredDecision edge (already emitted
    -- by 'classifyRef', which records every body reference) makes the DRG
    -- agree with the text. The ARGUMENT expression is discarded — that is the
    -- loss @D-PARAM-AS-INPUT@ names, and binding the parameter to the shared
    -- argument instead is a strictly better lowering the spec does not rule
    -- (deliberately not built in Phase 4).
    App _ f (_ : _) | Set.member (getUnique f) names.neUnlifted ->
      (atomPrec, feelIdentIn names f, SFeel)
    -- Phase 5 (§6.1, corrected block; §6.2): a SATURATED call to an emitted
    -- BKM renders as a FEEL named-argument invocation. Named, not positional
    -- (probe A2), so the position→name binding is visible in the artifact and
    -- an argument transposition cannot be silent. The λ-lifted closure
    -- parameters are appended as `name: name` — the caller has each lifted
    -- element in scope through its own requirement edges, and the parameter
    -- deliberately shadows the same-named global inside the BKM body (probes
    -- E1/E7). The fragment is FullFeel: an invocation is not S-FEEL. A
    -- partial application (wrong arity) falls through to verbatim, which is
    -- §6.3-2's refusal.
    App _ f es@(_ : _)
      | Just info <- Map.lookup (getUnique f) names.neBkms
      , length es == length info.bciParams ->
          let parts = map go es
          in if any (\(_, _, fr) -> fr == L4Verbatim) parts
               then verbatim e
               else ( atomPrec
                    , info.bciFeelName <> "("
                        <> Text.intercalate ", "
                             ( zipWith (\p (_, t, _) -> p <> ": " <> t) info.bciParams parts
                                 <> [c <> ": " <> c | c <- info.bciClosure]
                             )
                        <> ")"
                    , FullFeel
                    )
    -- §13.5's one flavor bit, the call-site half: on `kie`, a saturated call
    -- to a §-invocable decide renders as a named-argument invocation of the
    -- SERVICE, binding the service's inputData names (§2.3.1). Empty map on
    -- the default flavor, where the edge this needs kills Camunda's parse().
    App _ f es@(_ : _)
      | Just sci <- Map.lookup (getUnique f) names.neServiceCalls
      , length es == length sci.sciParams ->
          let parts = map go es
          in if any (\(_, _, fr) -> fr == L4Verbatim) parts
               then verbatim e
               else ( atomPrec
                    , sci.sciFeelName <> "("
                        <> Text.intercalate ", "
                             (zipWith (\p (_, t, _) -> p <> ": " <> t) sci.sciParams parts)
                        <> ")"
                    , FullFeel
                    )
    App _ _ (_ : _) -> verbatim e
    -- R8-d′. A CONSIDER over a MAYBE is an ABSENCE TEST, and FEEL spells one
    -- with a comparison against null. Two arms, in either source order, one
    -- binding and one not.
    --
    -- Rendered HERE rather than by rewriting the source to an 'IfThenElse',
    -- which was the other design and is recorded deferred as R8-d″: a
    -- 'renderFeelIn' case COMPOSES, so a CONSIDER nested inside a larger
    -- expression is still rendered, where a source rewrite only fires when the
    -- CONSIDER is the whole body. The cost is that the result is a boxed
    -- literal rather than a two-row table; the benefit is that it is FEEL at
    -- all, everywhere it appears.
    --
    -- MEASURED, not assumed, before this was written: `x != null` is a proper
    -- BOOLEAN on KIE 8.44 and zeebe-dmn 8.7.6, so the composed `if` takes the
    -- branch it looks like it takes. Had either engine answered null the
    -- condition would have been non-boolean, the else branch would always have
    -- been taken, and this would have been an ANSWER CHANGE rather than a
    -- rendering change -- see jl4/tests-cli/fixtures/dmn-null-probe.
    Consider _ scrut brs
      | Just (g, a, b) <- maybeConsiderArms brs
      -- R8-c. `null` does not nest, so on a MAYBE (MAYBE τ) scrutinee this
      -- rendering would answer "absent" for `JUST NOTHING` where L4 answers
      -- "present". Refused, not rendered -- see the note on 'flatMaybe'.
      , flatMaybe scrut
      -- The scrutinee's TEXT is emitted twice (once in the test, once for each
      -- occurrence of the binder), so an effectful scrutinee would be run twice.
      , not (hasEffectfulNode scrut)
      ->
        let (ps, ts, fs) = go scrut
            (_, ta, fa)  = go (substLocals (Map.singleton (getUnique g) scrut) a)
            (_, tb, fb)  = go b
        in if L4Verbatim `elem` [fs, fa, fb]
             then verbatim e
             else ( 0
                  , "if " <> parenIf (ps < 5) ts <> " != null then " <> ta <> " else " <> tb
                  , maximum [FullFeel, fs, fa, fb]
                  )
    _ -> verbatim e
   where
    atomPrec = 9 :: Int

    -- @CONSIDER … WHEN JUST g THEN a / WHEN NOTHING THEN b@, in either source
    -- order. Both shapes are the @PatApp cn ps@ form 'nullaryOnlyNotes' already
    -- matches, so nothing new is being recognised here -- only re-read.
    maybeConsiderArms brs = case brs of
      [j, n] -> case pick j n of
                  Just r  -> Just r
                  Nothing -> pick n j
      _      -> Nothing
     where
      pick jb nb = do
        (g, a) <- justArm jb
        b      <- nothingArm nb
        pure (g, a, b)
      justArm = \case
        MkBranch _ (When _ (PatApp _ cn [PatVar _ g])) a
          | getUnique cn == TC.justUnique -> Just (g, a)
        _ -> Nothing
      nothingArm = \case
        MkBranch _ (When _ (PatApp _ cn [])) b
          | getUnique cn == TC.nothingUnique -> Just b
        _ -> Nothing

    -- R8-c's guard, asked of the expression whose FEEL image would be `null`
    -- or would test against it. TRUE means "this MAYBE is one level deep and
    -- carries no EITHER", i.e. FEEL's single flat `null` is a faithful image of
    -- its absent case. FALSE sends the caller to 'verbatim', which is the same
    -- refusal 'sumTypeReasons' reports as @D-SUMTYPE@ Blocking -- the two are
    -- deliberately separate, because the note describes the DECISION while this
    -- guard describes one sub-expression, and 'renderFeelIn' composes.
    --
    -- An expression the oracle cannot type answers TRUE, which is the same
    -- fail-open direction every other oracle question in this module takes: an
    -- untyped MAYBE was rendered before R8-c had a guard at all.
    flatMaybe x = let (_, _, fl) = oracleClassify oracle x
                  in not (fl.tfNestedMaybe || fl.tfEither)

    -- `x != null` / `x = null`, at FEEL's comparison precedence. FullFeel
    -- because one operand is `null`, which rule 33 does not admit as a simple
    -- literal.
    nullCompare whole op x =
      let (px, tx, fx) = go x
      in if fx == L4Verbatim
           then verbatim whole
           else (5, parenIf (px < 5) tx <> " " <> op <> " null", max FullFeel fx)

    inertText = \case
      InertCtxAnd  -> "true"
      InertCtxOr   -> "false"
      InertCtxNone -> "true"

    unary whole frag build x =
      let (p, t, f) = go x
      in if f == L4Verbatim
           then verbatim whole
           else (atomPrec, build (parenIf (p < atomPrec) t), max frag f)

    -- FEEL's ORDERING operators are partial in a way its equality is not.
    -- DMN 1.3 §10.3.2.13: "The other comparison operators are defined only for
    -- the datatypes listed in Table 54", and Table 54 has rows for number,
    -- string, date, date-and-time, time and the two durations — and __none for
    -- boolean__. L4 does order booleans (@__LEQ__@ has a
    -- @BOOLEAN AND BOOLEAN TO BOOLEAN@ variant, "L4.TypeCheck.Environment"), so
    -- @IF p AT LEAST q@ is a well-typed L4 program whose obvious transliteration
    -- @p >= q@ is outside FEEL's language, not merely outside S-FEEL.
    --
    -- Emitting it tagged 'SFeel' would be the strongest executability claim this
    -- module can make about a fragment DMN does not define. So it goes out
    -- verbatim, which is what this module already does for every other
    -- "renders fine, evaluates to nothing" case (see the @App@ note above), and
    -- verbatim is what raises @D-NONFEELINPUT@ \/ @D-NONFEELOUTPUT@ Blocking.
    ordering whole op a b
      | any (isBooleanOperand oracle) [a, b] = verbatim whole
      | otherwise                            = binary whole 5 SFeel op a b

    binary whole prec frag op a b =
      let (pa, ta, fa) = go a
          (pb, tb, fb) = go b
      in if fa == L4Verbatim || fb == L4Verbatim
           then verbatim whole
           else ( prec
                , parenIf (pa < prec) ta <> " " <> op <> " " <> parenIf (pb <= prec) tb
                , maximum [frag, fa, fb]
                )

    pair whole frag build a b =
      let (_, ta, fa) = go a
          (_, tb, fb) = go b
      in if fa == L4Verbatim || fb == L4Verbatim
           then verbatim whole
           else (atomPrec, build ta tb, maximum [frag, fa, fb])

    triple whole frag build a b c =
      let (_, ta, fa) = go a
          (_, tb, fb) = go b
          (_, tc, fc) = go c
      in if L4Verbatim `elem` [fa, fb, fc]
           then verbatim whole
           else (atomPrec, build ta tb tc, maximum [frag, fa, fb, fc])

    nary whole frag build xs =
      let parts = map go xs
      in if any (\(_, _, f) -> f == L4Verbatim) parts
           then verbatim whole
           else (atomPrec, build [t | (_, t, _) <- parts], maximum (frag : [f | (_, _, f) <- parts]))

    call whole fn args =
      nary whole FullFeel (\ts -> fn <> "(" <> Text.intercalate ", " ts <> ")") args

    verbatim whole = (atomPrec, prettyLayout whole, L4Verbatim)

    parenIf True t  = "(" <> t <> ")"
    parenIf False t = t

  nullaryText r = case constantRefIn ctors r of
    Just v  -> renderFeelValue v
    Nothing -> feelIdentIn names r

-- | An L4 name as the FEEL name that refers to it.
--
-- The declaring side (an @inputData@\'s or a @decision@\'s @\<variable\>@)
-- carries its resolved name on the IR, and this is the same map, so the two
-- always agree — including after a collision rename, which is the case a
-- per-name fold cannot get right (§5.2 stage 2).
--
-- The fallback is the bare fold, for a reference the environment does not know:
-- 'renderFeel' standing alone, and a reference to something outside the DRG's
-- namespace. It is stage 1's answer, which is what the exporter emitted for
-- everything before stage 2 landed.
feelIdentIn :: NameEnv -> Resolved -> Text
feelIdentIn env r =
  Map.findWithDefault (feelIdentText (nameOf r)) (getUnique r) env.neVars

-- | A record field, as the FEEL path step that reads it. Its own namespace.
feelFieldIn :: NameEnv -> Resolved -> Text
feelFieldIn env r =
  Map.findWithDefault (feelIdentText (nameOf r)) (getUnique r) env.neFields

------------------------------------------------------------------------
-- The select idiom: max / min wearing a conditional's clothes
------------------------------------------------------------------------

-- | @IF a AT LEAST b THEN a ELSE b@ is not a decision over two cases. It is
-- @max a b@, and the L4 prelude literally defines @max@ that way.
--
-- A corpus survey found 17 instances across 12 files, ten of which sit under a
-- declaration or comment that /names/ the operation in English — "The lesser
-- of", "the earlier of", "greater of annual income or net worth" — while
-- spelling the conditional out longhand. So authors know it is @min@; they just
-- do not write @min@.
--
-- Recognising it is the peephole a compiler backend runs (LLVM's
-- @matchSelectPattern@ folding a branch into @SPF_SMAX@\/@SMIN@), and recognising
-- the SHAPE also matters structurally, whether or not the fold fires: without
-- 'selectShape', 'flattenGuarded' would expand the conditional into extra table
-- rows, manufacturing cases the regulation does not have. 17 CFR
-- 227.100(a)(2)(i) says "__The greater of__ $2,500, or 5 percent of …" — the
-- statute states an operator, so @max@ is the isomorphic rendering and the
-- expansion would be a derivation the statute never makes.
--
-- __Strictness does not matter here__, which is why @>=@ and @>@ map to the same
-- thing: the arms are the operands, so on a tie both branches return equal
-- values.
--
-- The match is exact and syntactic — arms must be the comparison's own operands
-- modulo annotations. That is what keeps it off the corpus\'s near misses:
-- @IF pool > promised THEN pool + increase ELSE pool@ (an arm is an operand
-- /plus a term/), @IF n < 0 THEN 0 - n ELSE n@ (@abs@, four times in the
-- corpus), and @IF n > k THEN n - 1 ELSE n@ (an off-by-one).
--
-- __The shape is not the whole test.__ L4\'s @\<@ \/ @\<=@ \/ @\>@ \/ @\>=@ are
-- overloaded — "L4.TypeCheck.Environment" gives each a @NUMBER@, a @STRING@ and
-- a @BOOLEAN@ variant, and @daydate.l4@ adds a @DATE@ one — so
-- @IF s AT LEAST t THEN s ELSE t@ is a well-typed L4 program over any of the
-- four, and the syntax says nothing about which. FEEL\'s @min@\/@max@ take a
-- "non-empty list of __comparable__ items" (DMN 1.3 §10.3.4.4 Table 75), and
-- what FEEL can compare is fixed by §10.3.2.13: "The other comparison operators
-- are defined only for the datatypes listed in Table 54", whose rows are number,
-- string, date, date-and-time, time and the two durations. __Boolean is absent__,
-- so @max(true, false)@ is outside the builtin\'s domain and §10.3.4 makes an
-- out-of-domain parameter yield @null@. (Drools\/KIE 8.44 answers @true@ anyway,
-- because it delegates to Java\'s @Comparable@ — engine-specific luck an exporter
-- must not bank on.)
--
-- So the gate is __FEEL-orderable operands__ ('feelOrderable'), which of the
-- types this backend models means @NUMBER@, @STRING@ and @DATE@. That line is
-- forced rather than chosen: the un-folded fallthrough is
-- @(if s >= t then s else t)@, whose @\>=@ is legal in exactly the same rows of
-- exactly the same table. Refusing to emit @min@ over dates while emitting @\<=@
-- over dates would not be conservative, just inconsistent. Boolean fails the
-- gate for a reason that applies to both spellings at once, and 'renderFeelIn'
-- accordingly sends a boolean @\>=@ out verbatim rather than pretending it is
-- S-FEEL.
--
-- An operand the oracle cannot type at all ('DmnAny' — no annotation, an
-- unresolved inference variable, a synthesised node) also fails the gate: not
-- because @if@ is safer, but because we cannot say it is orderable. Missing type
-- information costs a peephole, never correctness.
--
-- 'selectIdiom' asks the weakest oracle there is ('noTypeOracle'): it reads each
-- operand\'s own annotation and nothing else. Callers holding a 'TableCtx' should
-- use 'selectIdiomIn' with 'oracleOf', which can additionally resolve an operand
-- whose annotation is still an inference variable.
selectIdiom :: Expr Resolved -> Maybe (Text, Expr Resolved, Expr Resolved)
selectIdiom = selectIdiomIn noTypeOracle

-- | 'selectIdiom', told how to type an operand.
selectIdiomIn :: TypeOracle -> Expr Resolved -> Maybe (Text, Expr Resolved, Expr Resolved)
selectIdiomIn oracle e = do
  found@(_, a, b) <- selectShape e
  guard (feelOrderable oracle a && feelOrderable oracle b)
  pure found

-- | The select /shape/, with no view on the operands\' type: @IF@ whose arms are
-- its own comparison\'s operands.
--
-- Separate from 'selectIdiomIn' because the two questions have different
-- consumers and must not be conflated:
--
--   * __may we fold?__ is 'selectIdiomIn', and it is about what FEEL can
--     evaluate.
--   * __may we expand?__ is this one, and it is about ISOMORPHISM. @childOf@ in
--     'flattenGuarded' asks it to keep a select out of the row splicer, because
--     splicing @IF a >= b THEN a ELSE b@ into two rules manufactures a case
--     distinction the source does not make and drags the whole table from @U@ to
--     @F@ (DMN 8.2.10 order dependence) for a body that is one operator. That
--     harm does not go away when the operands are strings, and it is not caused
--     by the fold — so gating expansion on the fold's type test would have made
--     the artifact worse for exactly the operands the fold declines.
selectShape :: Expr Resolved -> Maybe (Text, Expr Resolved, Expr Resolved)
selectShape = \case
  IfThenElse _ c t f -> do
    (thenIsA, a, b) <- comparisonOf c
    let same x y = clearAnno x == clearAnno y
    if      same t a && same f b then Just (if thenIsA then "max" else "min", a, b)
    else if same t b && same f a then Just (if thenIsA then "min" else "max", a, b)
    else Nothing
  _ -> Nothing
 where
  -- 'thenIsA' is True when taking the THEN arm as `a` means "the bigger one".
  comparisonOf = \case
    Geq _ a b -> Just (True, a, b)
    Gt  _ a b -> Just (True, a, b)
    Leq _ a b -> Just (False, a, b)
    Lt  _ a b -> Just (False, a, b)
    _         -> Nothing

-- | Is this operand of a comparison of a type FEEL can ORDER (DMN 1.3 Table 54)?
--
-- The overload the typechecker committed to is /not/ readable here: it desugars
-- @a AT LEAST b@ into an application of one of @__GEQ__@\'s variants, but
-- 'carameliseExpr' — which "L4.Dmn.Lower" runs to make a comparison look like a
-- comparison again — matches on the head\'s NAME TEXT and drops the 'Resolved',
-- which is the only carrier of the chosen 'Unique'. Every variant, including
-- @daydate.l4@\'s user-level @DATE@ ones, caramelises to the identical 'Geq'
-- node.
--
-- What survives is better placed anyway. @matchFunTy@ checks each argument
-- against the chosen candidate\'s own declared parameter type, and @checkExpr@
-- stamps that expected type onto the node
-- ("L4.TypeCheck": @setAnnResolvedType t Nothing re@). Since the comparison
-- builtins are @fun_ [ty, ty] boolean@ for a ground @ty@, a resolved
-- comparison\'s operand carries the winning overload\'s concrete
-- @NUMBER@\/@STRING@\/@BOOLEAN@\/@DATE@ — in an annotation caramelisation
-- rebuilds in place and 'substLocals' splices intact. That is exactly the fact
-- the discarded 'Unique' would have given.
feelOrderable :: TypeOracle -> Expr Resolved -> Bool
feelOrderable oracle e = builtinOperandType oracle e `elem` [DmnNumber, DmnString, DmnDate]

-- | Is this operand a @BOOLEAN@ — the one type L4 orders and FEEL does not?
isBooleanOperand :: TypeOracle -> Expr Resolved -> Bool
isBooleanOperand oracle e = builtinOperandType oracle e == DmnBoolean

-- | The operand\'s type as a FEEL /builtin/, with the enum collapse deliberately
-- switched off.
--
-- 'oracleClassify' maps an @IS ONE OF@ to a named itemDefinition over @string@, which
-- is right for a typeRef — an enum\'s values serialise as strings — but wrong as
-- a licence to ORDER them. @max("red", "green")@ compares constructor
-- SPELLINGS, and the L4 declaration order those constructors were written in is
-- the only ordering the source ever suggested. Passing the empty environment
-- makes 'classifyType' fall through to 'builtinType', so an enum answers
-- 'DmnAny' here and fails both gates.
builtinOperandType :: TypeOracle -> Expr Resolved -> DmnType
builtinOperandType o = annTypeOf emptyTypeEnv o.toSubst o.toUri

isSelectIdiomIn :: TypeOracle -> Expr Resolved -> Bool
isSelectIdiomIn oracle = isJust . selectIdiomIn oracle

isSelectShape :: Expr Resolved -> Bool
isSelectShape = isJust . selectShape

-- | Lifted @max@\/@min@ whose operands include a literal or a named constant.
--
-- Lifting is right (see 'selectIdiom'), but it has a real cost that the report
-- must not swallow: the Reg CF $2,500 investment floor becomes part of
-- @max(2500, …)@ instead of being a row a compliance reader can point at. Two
-- symmetric computed quantities (@max(annual income, net worth)@) are
-- arithmetic and get no note; a named or literal threshold as one operand is
-- policy, and does.
liftedThresholds :: TableCtx -> Expr Resolved -> [(Text, Expr Resolved)]
liftedThresholds ctx top =
  [ (fn, sub)
  | sub <- toListOf (cosmosOf (gplate @(Expr Resolved))) top
  , Just (fn, a, b) <- [selectIdiomIn (oracleOf ctx) sub]
  , any isThreshold [a, b]
  ]
 where
  isThreshold = \case
    Lit _ _    -> True
    App _ r [] -> Set.member (getUnique r) ctx.tcConstants
    _          -> False

------------------------------------------------------------------------
-- WHERE / LET
------------------------------------------------------------------------

-- | Peel @WHERE@ and @LET@ wrappers off a decision body, substituting every
-- local into the expression that used it.
--
-- 'normaliseGuarded' matches only @IfThenElse@ \/ @MultiWayIf@ \/ @Consider@, so
-- a @WHERE@-wrapped chain is invisible to it — and the corpus\'s best decision
-- tables are all @WHERE@-wrapped. Peeling is therefore not a nicety.
--
-- __Inlining, not hoisting.__ A @WHERE@-local could in principle become its own
-- DRG decision, but DMN\'s decisions are globally named where L4\'s locals are
-- lexically scoped, so hoisting invites collisions between two decisions that
-- each happen to define @aggregate@. The DRG still gets a real dependency chain
-- from the module\'s top-level @MEANS@ declarations.
--
-- Bails (rather than producing a table with dangling names) when a local takes
-- parameters, is an @ASSUME@, performs I\/O, or is recursive.
peelLocals :: Expr Resolved -> Either FidelityLoss (Expr Resolved, [Text])
peelLocals = collect Map.empty []
 where
  collect env names = \case
    Where _ body ds -> absorb env names body ds
    LetIn _ ds body -> absorb env names body ds
    e               -> Right (substLocals env e, reverse names)

  absorb env names body ds = do
    bindings <- traverse binding ds
    env' <- resolveEnv (env <> Map.fromList [(u, b) | (u, _, b) <- bindings])
    collect env' (reverse [nm | (_, nm, _) <- bindings] <> names) body

  binding = \case
    LocalDecide _ (MkDecide _ _ (MkAppForm _ n [] _) b)
      | not (hasEffectfulNode b) -> Right (getUnique n, nameOf n, b)
    _ -> Left UninlinableLocal

  -- Later locals may reference earlier ones (and, in a WHERE, vice versa), so
  -- substitute the environment into itself until it stops changing. Bounded by
  -- the number of bindings; anything still self-referential after that is
  -- recursive, which has no closed form.
  resolveEnv raw =
    let step m = Map.map (substLocals m) m
        fixed  = iterate step raw !! Map.size raw
    in if any (mentions (Map.keysSet raw)) (Map.elems fixed)
         then Left UninlinableLocal
         else Right fixed

  mentions keys e =
    or [Set.member (getUnique r) keys | App _ r [] <- toListOf (cosmosOf (gplate @(Expr Resolved))) e]

-- | Replace every nullary reference to a bound local with its body.
substLocals :: Map Unique (Expr Resolved) -> Expr Resolved -> Expr Resolved
substLocals env
  | Map.null env = id
  | otherwise    = go
 where
  go e = case e of
    App _ r [] | Just b <- Map.lookup (getUnique r) env -> b
    _ -> over (gplate @(Expr Resolved)) go e

------------------------------------------------------------------------
-- Flattening nested chains
------------------------------------------------------------------------

-- | How deep to splice nested chains, and how many rules to tolerate.
--
-- @IF a THEN x ELSE IF b THEN y ELSE IF c THEN z ELSE w@ normalises to ONE row
-- plus an @OTHERWISE@ that is itself a chain. Lowered naively that is a
-- one-rule table whose default output is a nested conditional — the opaque
-- ribbon this programme exists to remove, relocated into DMN. So splice:
--
-- > row (g, b) where b normalises to [(h1,c1) … (hm,cm)] + otherwise c0
-- >   =>  (g and h1, c1) … (g and hm, cm), (g, c0)
--
-- The final @(g, c0)@ is correct under @First@, and the parent\'s negated prefix
-- stays implicit for the same reason no other prefix is materialised.
--
-- The caps are not paranoia: nesting multiplies, and an unbounded splice on a
-- deeply nested rule is a table-size explosion.
maxFlattenDepth, maxFlattenRows :: Int
maxFlattenDepth = 4
maxFlattenRows  = 64

-- | Splice nested chains into more rows. Returns the flattened chain and the
-- bodies left unflattened by a cap.
--
-- Deliberately type-blind: @childOf@ below asks 'selectShape', not
-- 'selectIdiomIn'. Whether the select may be FOLDED is a question about FEEL\'s
-- domain; whether it may be EXPANDED is a question about isomorphism, and the
-- answer to the second is no for every operand type.
flattenGuarded :: GuardedRows -> (GuardedRows, [Expr Resolved])
flattenGuarded rs0
  | length flat.grRows > maxFlattenRows = (rs0, [b | (_, b) <- rs0.grRows, isJust (childOf b)])
  | otherwise                           = (flat, capped)
 where
  (flat, capped) = go maxFlattenDepth rs0

  go depth rs =
    let expanded = map (expandRow depth) rs.grRows
        (othRows, othFinal, othDisj, othCapped) = expandOtherwise depth rs.grOtherwise
        rows = concatMap (\(r, _, _) -> r) expanded <> othRows
        -- Disjointness composes: the flattened family is exclusive iff the
        -- parent family was AND every child family is AND no child contributed
        -- a bare catch-all row (which its siblings' guards all imply).
        disjoint = rs.grDisjoint && and [d | (_, d, _) <- expanded] && othDisj
    in ( MkGuardedRows
           { grRows      = rows
           , grOtherwise = othFinal
           , grDisjoint  = disjoint
           }
       , concatMap (\(_, _, c) -> c) expanded <> othCapped
       )

  expandRow depth (g, b) = case childOf b of
    Nothing  -> ([(g, b)], True, [])
    Just sub
      | depth <= 0 -> ([(g, b)], True, [b])
      | otherwise ->
          let (child, ccapped) = go (depth - 1) sub
          in ( [(conj g h, c) | (h, c) <- child.grRows]
                 <> [(g, c0) | Just c0 <- [child.grOtherwise]]
             , child.grDisjoint && isNothing child.grOtherwise
             , ccapped
             )

  expandOtherwise _ Nothing = ([], Nothing, True, [])
  expandOtherwise depth (Just b0) = case childOf b0 of
    Just sub | depth > 0 ->
      let (child, ccapped) = go (depth - 1) sub
      -- Splicing the OTHERWISE's rows AFTER the parent's is exactly First; but
      -- the parent's guards and these need not exclude one another, so once any
      -- parent row exists the family is no longer provably disjoint.
      in (child.grRows, child.grOtherwise, False, ccapped)
    _ -> ([], Just b0, True, [])

  conj = And emptyAnno

  -- Reuse the normaliser's own answer rather than re-deriving its bail
  -- conditions, and refuse the two cases this module adds on top of them.
  childOf b
    | isSelectShape b    = Nothing
    | hasEffectfulNode b = Nothing
    | otherwise = case normaliseGuarded b of
        Just sub
          | not (rowsElided b sub)
          , not (any (hasEffectfulNode . fst) sub.grRows) -> Just sub
        _ -> Nothing

------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------

-- | What the module's own @DECLARE@s say about a type.
--
-- Phase 3 replaced a bare @Set Unique@ of "enums" with this, because the old
-- set answered one question ("does this collapse to @string@?") and lost two
-- others in the same step: /which/ itemDefinition the type is, and what its
-- domain is. §3 and §4.2 want both, and one walk of the type now produces both.
data TypeEnv = MkTypeEnv
  { teNamed   :: !(Map Unique Text)
    -- ^ type 'Unique' -> the minted @itemDefinition@'s FEEL name. Module-local
    -- declarations only: 'topDecls' does not descend into imports, so a type
    -- declared elsewhere has no definition to point at and stays @Any@.
  , teDomains :: !(Map Unique [Text])
    -- ^ type 'Unique' -> its constructor names, in __declaration order__ and in
    -- the __'nameOf' spelling__. Not 'feelIdentText': a constructor name becomes
    -- a FEEL /string literal/ (the tag value), never an identifier, so the name
    -- fold must not touch it (§5.3.6) — and this is precisely the string the
    -- cells already carry, so a domain and a cell cannot disagree.
  , tePayload :: !(Set Unique)
    -- ^ types that are payload-carrying @IS ONE OF@s: more than one
    -- constructor, at least one of which declares fields. R4-a's subject.
  , teOptional :: !(Map Unique Text)
    -- ^ type 'Unique' -> the FEEL name of its __domain-free alias__, for the
    -- types that have a domain at all (R8-a's carve-out, §11-R8-a).
    --
    -- A @MAYBE τ@ site points here instead of at 'teNamed' when τ is one of
    -- them, because pointing at τ's own definition would defeat R8-b one
    -- @typeRef@ hop away: R8-b suppresses @allowedValues@ /at the element/,
    -- §7.3.3 makes @allowedValues@ the __complete__ range of the definition
    -- reached through the @typeRef@, and nothing this exporter emits lowers to
    -- @null@ — so an enforcing engine would reject the absent case that is the
    -- whole content of the @MAYBE@. That is an answer change, not a reporting
    -- gap, which is why it is repaired in the artifact rather than in prose.
    --
    -- Empty for a τ with no domain: a record, a builtin and a @LIST OF@ assert
    -- no range to begin with, so R8-a's plain lowering is already correct for
    -- them and an alias would be the pure ceremony §4.3 refuses.
  , teUri     :: !NormalizedUri
    -- ^ the module being lowered, so "declared in another module" is decidable.
  }

emptyTypeEnv :: TypeEnv
emptyTypeEnv = MkTypeEnv
  { teNamed    = Map.empty
  , teDomains  = Map.empty
  , tePayload  = Set.empty
  , teOptional = Map.empty
  , teUri      = toNormalizedUri (Uri "")
  }

-- | What a classification found on the way that the @typeRef@ alone cannot say.
--
-- These are the R8 flags plus the two @D-ITEMDEF@ reasons. They exist because
-- the answer "this element is typed @number@" is true and incomplete when the
-- L4 said @MAYBE NUMBER@: the loss is real, it is not visible in the artifact,
-- and the only place it can be reported from is the walk that erased it.
data TypeFlags = MkTypeFlags
  { tfMaybe         :: !Bool  -- ^ a @MAYBE τ@ was lowered to τ's own typeRef (R8-a)
  , tfOptionalAlias :: !(Maybe (Text, Text))
    -- ^ ...and τ had a finite domain, so the element points at a __domain-free
    -- alias__ instead: @Just (the alias's name, τ's own name)@.
    --
    -- This is R8-a's carve-out, and it exists because the plain lowering was
    -- __defeated one @typeRef@ hop away__. R8-b suppresses @allowedValues@ \/
    -- @inputValues@ /at the element/; §7.3.3 then makes the @allowedValues@ of
    -- whatever the @typeRef@ resolves to the __complete__ range of the element
    -- — so pointing a @MAYBE@ site at τ's own definition re-asserts, one hop
    -- on, exactly the range R8-b just refused to write, and it is a range with
    -- no absent case in it, so under an enforcing engine the absent case that
    -- is the whole content of the @MAYBE@ is rejected: an answer change.
    --
    -- __CORRECTED 2026-07-31.__ This used to read "Nothing this exporter emits
    -- lowers to @null@", which R8-d′ made false: @NOTHING@ now lowers to FEEL
    -- @null@ on the value channel. The carve-out is UNCHANGED and is in fact
    -- strengthened -- the rejection above used to be hypothetical and is now
    -- real, because the exporter genuinely emits @null@ into positions typed
    -- @\<τ\>_optional@.
    --
    -- Nothing but a 'DmnNamed' with a domain can reach this field, because
    -- 'classifyType' returns a domain only from the branch that mints a name.
    -- A record, a builtin and a @LIST OF@ keep R8-a's plain lowering and leave
    -- this 'Nothing' — they assert no range, so there is nothing to defeat.
  , tfNestedMaybe   :: !Bool  -- ^ @MAYBE (MAYBE τ)@: refused, because @null@ does not nest (R8-c)
  , tfEither        :: !Bool  -- ^ @EITHER a b@: refused (R8-e)
  , tfList          :: !Bool  -- ^ @LIST OF τ@: @isCollection@ needs an itemDefinition of its own
  , tfForeign       :: !Bool  -- ^ a type declared in another module, so no itemDefinition exists
  }
  deriving stock (Eq, Show, Generic)

noTypeFlags :: TypeFlags
noTypeFlags = MkTypeFlags
  { tfMaybe = False, tfOptionalAlias = Nothing, tfNestedMaybe = False, tfEither = False
  , tfList = False, tfForeign = False
  }

oracleType :: TypeOracle -> Expr Resolved -> DmnType
oracleType o e = let (t, _, _) = oracleClassify o e in t

-- | The classifier, asked about an expression's inferred type.
oracleClassify :: TypeOracle -> Expr Resolved -> (DmnType, Maybe [Text], TypeFlags)
oracleClassify o e = case annTypeSource o e of
  Just ty -> classifyType o.toTypes ty
  Nothing -> (DmnAny, Nothing, noTypeFlags)

-- | An expression's inferred type, with the final substitution applied.
annTypeSource :: TypeOracle -> Expr Resolved -> Maybe (Type' Resolved)
annTypeSource o e = case (getAnno e).extra.resolvedInfo of
  Just (TypeInfo ty _) -> Just (TC.applyFinalSubstitution o.toSubst o.toUri ty)
  _                    -> Nothing

-- | Kept separate from 'oracleClassify' on purpose: 'TableCtx' has strict fields, so a
-- caller computing @tcOutputType@ from an expression's annotation cannot go
-- through the context it is in the middle of building.
annTypeOf :: TypeEnv -> TC.Substitution -> NormalizedUri -> Expr Resolved -> DmnType
annTypeOf env subst uri =
  oracleType MkTypeOracle { toTypes = env, toSubst = subst, toUri = uri }

-- | FEEL's type system is numbers, strings, booleans, dates, lists and contexts
-- — no algebraic data types. What it /does/ have is the __context__, which is a
-- record, and DMN's @itemDefinition@ is how you name one. So a module-local
-- @DECLARE@ maps across (§4.1, §4.2) and everything else is honestly @Any@.
--
-- Returns the @typeRef@, the type's __domain__ if it has a finite one, and the
-- 'TypeFlags' the walk found. One walk rather than three, because §3's column
-- domains and §4.2's @allowedValues@ are the same question asked at two scopes,
-- and answering them separately is how they drift.
--
-- The rules, in the order they are tested:
--
--   * @NUMBER@ \/ @STRING@ \/ @BOOLEAN@ \/ @DATE@ — a builtin @typeRef@, and
--     __no itemDefinition__ (§4.3: an alias over @number@ adds no information
--     and degrades for a consumer that does not resolve typeRefs).
--   * a module-local __record__ — @DmnNamed@, no domain.
--   * a module-local __@IS ONE OF@__ — @DmnNamed@ over @string@, domain =
--     __every__ constructor, including payload-carrying ones. Listing them all
--     is what makes the missing constructor visible to a gap analyser as a gap
--     (§4.2.1-9); listing only the nullary ones would assert a domain the type
--     does not have.
--   * @MAYBE τ@ — __τ's own typeRef__, and __no domain at this element__ (R8-a,
--     R8-b): @tItemDefinition@ has no nullability flag, so the @MAYBE@ is
--     recorded in the fidelity report rather than spelled in the artifact; and
--     §7.3.3 makes @allowedValues@ the /complete/ range, which a list that
--     cannot include @null@ would not be.
--   * @MAYBE τ@ __where τ carries a domain__ — a __domain-free alias__ of τ
--     ('teOptional'), because there the plain lowering is not merely lossy but
--     wrong: §7.3.3 reads the range off whatever the @typeRef@ resolves to, so
--     pointing at τ's own definition re-asserts one hop on the complete range
--     R8-b just suppressed, and that range has no absent case. The alias is
--     __not__ a way to spell nullability — @tItemDefinition@ still cannot — it
--     is what keeps R8-b's suppression from being undone by the hop.
--     'tfOptionalAlias' records both names so @D-MAYBE-NULL@ can report what
--     the alias costs: no engine-side validation of the values that /are/
--     present at this site.
--   * @MAYBE (MAYBE τ)@ — @Any@ and refused (R8-c). @null@ does not nest, so
--     @JUST NOTHING@ and @NOTHING@ would become one FEEL value and FEEL @=@
--     would answer @true@ where L4 answers @false@. That is an answer change.
--   * @EITHER a b@ — @Any@ and refused (R8-e).
--   * @LIST OF τ@ — @Any@. @isCollection@ is an attribute of
--     @tItemDefinition@, so a list needs a definition of its own; @D-ITEMDEF@.
--   * a type declared in __another module__ — @Any@, because 'topDecls' is
--     module-local and there is nothing to point a @typeRef@ at; @D-ITEMDEF@.
classifyType :: TypeEnv -> Type' Resolved -> (DmnType, Maybe [Text], TypeFlags)
classifyType env = go False
 where
  go inMaybe = \case
    TyApp _ n args -> case args of
      [inner] | getUnique n == TC.maybeUnique ->
        if inMaybe
          then (DmnAny, Nothing, noTypeFlags { tfMaybe = True, tfNestedMaybe = True })
          else
            -- R8-a, and R8-a's carve-out. τ's own typeRef is the answer unless
            -- τ carries a domain, in which case pointing at it would re-assert
            -- through the hop the complete range R8-b just suppressed. Those
            -- sites get the domain-free alias instead; everything else is
            -- unchanged.
            let (t, dom, f) = go True inner
                aliased = do
                  _ <- dom
                  u <- typeHeadUnique inner
                  a <- Map.lookup u env.teOptional
                  pure (a, dmnTypeAttr t)
            in case aliased of
                 Just (a, base) ->
                   ( DmnNamed a (dmnTypeBase t)
                   , Nothing
                   , f { tfMaybe = True, tfOptionalAlias = Just (a, base) }
                   )
                 Nothing -> (t, Nothing, f { tfMaybe = True })
      [] -> named (getUnique n)
      _ : _
        | getUnique n == TC.eitherUnique -> (DmnAny, Nothing, noTypeFlags { tfEither = True })
        | getUnique n == TC.listUnique   -> (DmnAny, Nothing, noTypeFlags { tfList = True })
        | otherwise                      -> (DmnAny, Nothing, noTypeFlags)
    _ -> (DmnAny, Nothing, noTypeFlags)

  named u
    | Just nm <- Map.lookup u env.teNamed =
        ( DmnNamed nm (if Map.member u env.teDomains then DmnString else DmnAny)
        , Map.lookup u env.teDomains
        , noTypeFlags
        )
    | builtinType u /= DmnAny = (builtinType u, Nothing, noTypeFlags)
    | otherwise               = (DmnAny, Nothing, noTypeFlags { tfForeign = foreign_ u })

  -- An inference variable's Unique belongs to no module and must not be
  -- reported as an unresolvable import; only a name the checker actually
  -- resolved somewhere else is.
  foreign_ u = u.moduleUri /= env.teUri && env.teUri /= toNormalizedUri (Uri "")

-- | One module-local @DECLARE@ that earns an @itemDefinition@ (§4.1, §4.2).
--
-- Not exported: it is the shape of an analysis "L4.Dmn.Lower" runs once over
-- the module's declarations, and every consumer downstream sees the
-- 'ItemDefinition' it produces instead.
data ItemDecl = MkItemDecl
  { itdUnique   :: !Unique
  , itdName     :: !Text                            -- ^ the verbatim L4 type name
  , itdCtors    :: ![Text]                          -- ^ @IS ONE OF@: constructors in declaration order
  , itdFields   :: ![(Resolved, Type' Resolved)]    -- ^ record: STORED fields in declaration order
  , itdComputed :: ![Text]                          -- ^ record: computed fields, which are skipped
  , itdPayload  :: !Bool                            -- ^ a multi-constructor union with a payload arm
  }

-- | The head type constructor of a type, seen through a @MAYBE@.
typeHeadUnique :: Type' Resolved -> Maybe Unique
typeHeadUnique = \case
  TyApp _ n [inner] | getUnique n == TC.maybeUnique -> typeHeadUnique inner
  TyApp _ n []                                      -> Just (getUnique n)
  _                                                 -> Nothing

builtinType :: Unique -> DmnType
builtinType u
  | u == TC.numberUnique  = DmnNumber
  | u == TC.stringUnique  = DmnString
  | u == TC.booleanUnique = DmnBoolean
  | u == TC.dateUnique    = DmnDate
  | otherwise             = DmnAny

------------------------------------------------------------------------
-- Notes
------------------------------------------------------------------------

-- | The note codes this backend emits. All prefixed @D-@ so they cannot collide
-- with the process-side backend's in a combined report.
--
-- Severity follows the shared vocabulary: 'Blocking' means DMN cannot express
-- the thing at all and we emitted a fallback; 'Lossy' means something the L4
-- said is gone; 'Advisory' means the emission is faithful but a /target-side/
-- capability is forfeited. Most of these are Advisory, and that is the point —
-- the losses are properties of DMN, not defects in the export.
--
-- The codes, and the line between the two severities that matters most here:
--
-- [@D-NONFEELINPUT@ (Blocking)] an input expression is L4 source, not FEEL
--   ('L4Verbatim'). No engine can evaluate the table.
-- [@D-NONFEELOUTPUT@ (Blocking)] an output entry is L4 source, not FEEL.
-- [@D-LITERALEXPR@ (Blocking)] the decision has no table shape and became a
--   boxed literal expression.
-- [@D-DATEDCHAIN@ (Blocking)] the decision is a chain of rule-date guards that
--   could not be lowered to a date-interval table, so it shipped as boolean
--   columns over raw L4 that no engine can evaluate (spec §15.3, R10).
-- [@D-RULEDATE-UNBOUND@ (Blocking)] the decision rebinds law time with
--   @EVAL UNDER RULES EFFECTIVE AT@; a DRG has one global rule-date input and no
--   scoped rebinding, so supplying that input does not make it answer. The
--   message has TWO forms, chosen from the emitted logic: a boxed literal gets
--   the whole-decision claim, and a decision that still ships a table gets the
--   sub-expression claim, because "no engine can evaluate this decision" would
--   be false of a table an engine will run (spec §15.5).
-- [@D-SCOPE@ (Lossy)] two differently-scoped L4 terms collide on one DMN
--   @inputData@ name.
-- [@D-RULEDATE@ (Advisory)] the model is temporally parameterised: the rule-date
--   @inputData@ was emitted and named decisions depend on it. Exactly one per
--   DRG (spec §15.5).
-- [@D-NONFEEL@ (Advisory)] the input expression is /valid/ FEEL but outside
--   S-FEEL.
-- [@D-COMPUTEDOUTPUT@ (Advisory)] the output entry is /valid/ FEEL but an
--   expression rather than a constant.
-- [@D-UNDECOMPOSABLE@, @D-HITPOLICY@, @D-ORDERDEPENDENT@, @D-INLINEDLOCAL@,
--  @D-FLATTENCAP@, @D-LIFTEDTHRESHOLD@ (Advisory)] faithful emissions that
--   forfeit a DMN-side capability.
--
-- __The @NONFEEL@\/valid-FEEL split is a soundness boundary, not a gradation.__
-- Before it existed, an 'L4Verbatim' cell — DMN that no engine can execute —
-- was reported by @D-COMPUTEDOUTPUT@, whose message ("an expression, not a
-- constant") describes a much milder problem, and on the input side it could be
-- suppressed entirely. A reader who acts on an Advisory note ships a model that
-- fails at run time, and 18 of the 28 corpus instances failed /silently/ (a
-- verbatim @defaultOutputEntry@ evaluates to @null@ with status @SUCCEEDED@ on
-- Drools\/KIE 8.44). Each 'L4Verbatim' cell therefore raises exactly one
-- Blocking note and never also the Advisory one: the pairs
-- @D-NONFEELINPUT@\/@D-NONFEEL@ and @D-NONFEELOUTPUT@\/@D-COMPUTEDOUTPUT@ are
-- mutually exclusive by construction.
dmnNote :: Text -> FidelitySeverity -> Text -> Maybe SrcRange -> Text -> Text -> FidelityNote
dmnNote c sev el rng msg lostWhat =
  MkFidelityNote
    { code     = c
    , severity = sev
    , element  = el
    , range    = rng
    , message  = msg
    , lost     = lostWhat
    }

-- | The one Blocking note for an output position whose text is L4, not FEEL.
--
-- Shared by the decision-table path and the boxed-literal select-idiom path,
-- because the failure is the same in both and a reader must not have to know
-- which shape the exporter chose.
nonFeelOutput :: Text -> Maybe SrcRange -> FeelExpr -> FidelityNote
nonFeelOutput el rng fe =
  dmnNote "D-NONFEELOUTPUT" Blocking el rng
    ("the output entry `" <> fe.feText
       <> "` is L4 source, not FEEL: this backend has no FEEL rendering for it, so the text \
          \was emitted verbatim and NO DMN engine can evaluate it")
    "execution: an engine fails to compile the entry -- loudly when the rule fires, but \
    \SILENTLY (a null result, reported as success) when it is the defaultOutputEntry"

-- | @D-MAYBE-NULL@ (R8-a, R8-b): a @MAYBE τ@ was lowered to τ's own @typeRef@.
--
-- __Explicit and mandatory, not silent__, because of what the encoding costs.
-- The type-level half of R8 is sound: §2.4's refusal is about L4's /error/
-- channel, and @NOTHING@ is a value of a total function, not a raise — §2.4.1
-- says so itself when it accepts @TO NUMBER@ \/ @TO DATE@ as "genuinely total"
-- precisely /because/ they return a @MAYBE@. What the encoding does lose is a
-- distinction the target cannot make: FEEL has one @null@, and it spells both
-- "the rule says there is none" and "the engine could not compute it". L4 keeps
-- those apart; the artifact cannot, and no reader or analyser can recover which
-- was meant. That is a fidelity loss rather than a soundness one — hence
-- 'Lossy' — and it is exactly what a fidelity report is for.
--
-- The second sentence fires only when τ is a __named__ type with a finite
-- domain, and it reports an alias rather than a loss of domain. R8-b suppresses
-- @allowedValues@ \/ @inputValues@ /at this element/, and the reason stands:
-- §7.3.3 makes @allowedValues@ the __complete__ range of values the type
-- represents, DMN 1.3's grammar rules 13-17 make an S-FEEL endpoint a @simple
-- value@, and @null@ (rule 34, a /literal/) is not one — so a list written here
-- would exclude a value the type admits. The suppression would not survive the
-- @typeRef@ hop, though, because §7.3.3 reads the range off the definition the
-- @typeRef@ resolves to: pointing at τ's own would re-assert the very range
-- just suppressed. So the element points at a __domain-free alias__ of τ
-- instead (R8-a's carve-out).
--
-- __What that costs, and what it does not.__ It does not spell nullability;
-- @tItemDefinition@ has no flag for it and the alias invents none, which is why
-- the note fires here at all. What it forfeits is the /other/ half of the
-- domain's job: at this site an engine no longer validates the values that
-- __are__ present, so a string outside τ's constructors passes where at a
-- non-@MAYBE@ site it would be rejected. That is a checking loss on the present
-- case, deliberately taken to keep the absent case admissible — and naming both
-- the alias and τ is what lets a reader see the trade in the artifact.
maybeNullNote :: Text -> Maybe SrcRange -> Text -> Text -> Maybe (Text, Text) -> FidelityNote
maybeNullNote el rng what tyText optionalAlias =
  dmnNote "D-MAYBE-NULL" Lossy el rng
    ( what <> " is declared `" <> tyText
        <> "`, and DMN has no nullability marker -- tItemDefinition has no such flag -- so the \
           \emitted typeRef is the payload type's own. FEEL has one `null` and it means both \
           \\"there is no value\" and \"the value could not be computed\", so NOTHING and an \
           \undefined result can no longer be told apart in the artifact. ADOPTED 2026-07-31 \
           \(R8-d'): NOTHING now lowers to FEEL `null` on the VALUE channel, so the conflation \
           \this note reports is a price paid deliberately and not an accident of the encoding. \
           \What buys it is that the artifact becomes EXECUTABLE where it was previously L4 \
           \source no engine could compile. `null` is still refused as an input ENTRY -- DMN 1.3 \
           \grammar rule 34 makes it a literal and rule 33's `simple literal` does not include \
           \it -- so no cell in this model asks an engine to test against it"
        <> case optionalAlias of
             Just (alias, base) ->
               ". No allowedValues or inputValues is emitted AT THIS ELEMENT, because DMN 7.3.3 \
               \makes allowedValues the COMPLETE range of values a type represents and `null` is \
               \not a legal S-FEEL endpoint -- and because that range is read through the typeRef, \
               \this element points at `" <> alias <> "`, a domain-free alias of `" <> base
               <> "`, rather than at `" <> base <> "` itself. Pointing at `" <> base
               <> "` would re-assert its complete range one hop on, and that range has no absent \
                  \case in it, so an enforcing engine would reject the very NOTHING this type \
                  \exists to allow"
             Nothing -> ""
    )
    ("the distinction between an absent value and an undefined one"
       <> case optionalAlias of
            Just (_, base) ->
              ", and -- at THIS element only -- engine-side validation of the values that ARE \
              \present: `" <> base <> "`'s domain is deliberately not asserted here, so a value \
              \outside it is no longer rejected at this site"
            Nothing -> "")

tableNotes
  :: TableCtx
  -> [[Cell]]
  -> [Cell]
  -> [InputColumn]
  -> HitPolicy
  -> GuardedRows
  -> [Text]              -- ^ names of inlined WHERE/LET locals
  -> [Expr Resolved]     -- ^ bodies left unflattened by the cap
  -> [FidelityNote]
tableNotes ctx decomposed columnCells columns policy rows inlined cappedBodies =
  dedupeNotes $
    fallbackNotes <> nonFeelInputNotes <> sfeelNotes <> policyNotes
      <> nonFeelOutputNotes <> outputNotes
      <> inlineNotes <> capNotes <> thresholdNotes <> columnMaybeNotes
 where
  here = ctx.tcIdPrefix

  -- R8-a's column site. The output clause has no site of its own: this emitter
  -- deliberately emits no @typeRef@ on a @\<output\>@ (measured: KIE says
  -- ILLEGAL_USE_OF_TYPEREF), so a MAYBE-typed decision is reported once, at its
  -- own @\<variable\>@, in "lowerModule".
  columnMaybeNotes =
    [ maybeNullNote here (bestRange c.cellSubject)
        ("the column `" <> oneLine (prettyLayout c.cellSubject) <> "`")
        (oneLine (prettyLayout sty)) fl.tfOptionalAlias
    | c <- columnCells
    , Just sty <- [annTypeSource (oracleOf ctx) c.cellSubject]
    , let (_, _, fl) = classifyType ctx.tcTypes sty
    , fl.tfMaybe
    ]

  fallbackNotes =
    [ dmnNote "D-UNDECOMPOSABLE" Advisory here (bestRange c.cellSubject)
        ("the guard `" <> oneLine (prettyLayout c.cellSubject)
           <> "` has no constant endpoint, so it became its own boolean column rather than \
              \an input expression tested by a unary test")
        "interval gap and overlap analysis over this condition"
    | row <- decomposed, c <- row, c.cellNote
    ]

  -- A column born of a fallback already has a note; do not say it twice.
  fallbackKeys = Set.fromList [c.cellKey | row <- decomposed, c <- row, c.cellFallback]

  -- The input-side half of the soundness boundary, and the reason it is NOT
  -- filtered by 'fallbackKeys' the way 'sfeelNotes' is. That suppression is
  -- right for D-NONFEEL, which reports a lost DMN capability the fallback note
  -- has already reported in other words. It is wrong here: D-UNDECOMPOSABLE says
  -- "no constant endpoint, so it became a boolean column", which is true of
  -- perfectly executable columns and says nothing about executability. Three
  -- verified corpus shapes reached the shipped DMN through that gap — one with
  -- only D-UNDECOMPOSABLE, and two (a `Proj` of a verbatim object; a select
  -- idiom over an unrenderable operand) with no note at all.
  nonFeelInputNotes =
    [ dmnNote "D-NONFEELINPUT" Blocking here (bestRange c.cellSubject)
        ("the input expression `" <> col.icExpr.feText
           <> "` is L4 source, not FEEL: this backend has no FEEL rendering for it, so the \
              \text was emitted verbatim and NO DMN engine can evaluate this column")
        "execution: the table is well-formed DMN but the engine fails to compile the column, \
        \and every rule that tests it is silently treated as non-matching"
    | (col, c) <- zip columns columnCells
    , col.icExpr.feFragment == L4Verbatim
    ]

  sfeelNotes =
    [ dmnNote "D-NONFEEL" Advisory here (bestRange c.cellSubject)
        ("the input expression `" <> col.icExpr.feText
           <> "` is outside S-FEEL (which admits only arithmetic, simple values and comparisons)")
        "completeness, consistency and overlap checking, all of which DMN's analysis is defined over S-FEEL only"
    | (col, c) <- zip columns columnCells
    , col.icExpr.feFragment == FullFeel
    , not (Set.member c.cellKey fallbackKeys)
    ]

  -- Located at the first guard: these are properties of the whole table, and
  -- that is the nearest thing it has to a position.
  tableRange = listToMaybe (mapMaybe (bestRange . fst) rows.grRows)

  policyNotes =
    [ dmnNote "D-HITPOLICY" Advisory here tableRange
        "the L4 guards are provably exclusive, but the emitted columns cannot witness it, \
        \so the hit policy is First rather than Unique"
        "the reader's and the tool's ability to see that the rules cannot conflict"
    | rows.grDisjoint, policy == HitFirst
    ]
      <> [ dmnNote "D-ORDERDEPENDENT" Advisory here tableRange
             "hit policy First is order-dependent: DMN 8.2.10 says of such tables that \
             \\"the table is hard to validate manually and therefore has to be used with care\""
             "order-free reading; a rule cannot be checked without the rules above it"
         | policy == HitFirst
         , length rows.grRows + length (maybeToList rows.grOtherwise) > 1
         ]

  -- The whole point of the S-FEEL pincer, made concrete. DMN 8.2.9 says "a rule
  -- output entry is an expression", so this is legal and we emit it faithfully.
  -- But both Calvanese formalisations define an output entry as mapping to an
  -- OBJECT, so a computed-output table is outside the analysable fragment BY
  -- CONSTRUCTION -- and our flagship exhibit, a MIN/MAX of computed quantities,
  -- is exactly such a table. Saying nothing here would let a reader assume the
  -- DMN tooling can check a table it cannot.
  -- R8-d′ made `null` an output entry this backend genuinely emits, and the
  -- generic message above would then say of it "is an expression, not a
  -- constant" -- flatly contradicting @D-MAYBE-NULL@, in the same report, which
  -- says DMN 1.3 grammar rule 34 makes `null` a LITERAL. Both cannot be right,
  -- and the literal reading is the correct one. What survives is the
  -- ANALYSABILITY claim, for a different reason: a decision-table analysis maps
  -- an output entry to an OBJECT in a domain, and `null` denotes none.
  computedOutputText fe
    | fe.feText == "null" =
        "the output entry `null` is FEEL's null LITERAL (DMN 1.3 grammar rule 34), not an \
        \expression -- but it denotes no object in any domain, and every published \
        \decision-table analysis maps an output entry to one"
    | otherwise =
        "the output entry `" <> fe.feText
          <> "` is an expression, not a constant; DMN 8.2.9 permits that, but every published \
             \decision-table analysis defines an output entry as a constant"

  outputNotes =
    [ dmnNote "D-COMPUTEDOUTPUT" Advisory here (bestRange body)
        (computedOutputText fe)
        "gap and overlap analysis of this table: DMN renders it, DMN's checkers do not check it"
    | body <- outputBodies
    , let fe = renderFeelIn ctx.tcNames ctx.tcConstructors (oracleOf ctx) body
      -- MUTUALLY EXCLUSIVE with D-NONFEELOUTPUT. An L4Verbatim entry satisfies
      -- `not . isConstantText` too, and used to be reported by this Advisory
      -- note alone -- a note about ANALYSABILITY standing in for a failure of
      -- EXECUTABILITY. That is the defect this split fixes.
    , fe.feFragment /= L4Verbatim
    , not (isConstantText fe)
    ]

  -- The output-side half of the soundness boundary. DMN 8.2.9 does say "a rule
  -- output entry is an expression", so an expression here is legal -- but only
  -- if it is a FEEL expression. This text is not.
  nonFeelOutputNotes =
    [ nonFeelOutput here (bestRange body) fe
    | body <- outputBodies
    , let fe = renderFeelIn ctx.tcNames ctx.tcConstructors (oracleOf ctx) body
    , fe.feFragment == L4Verbatim
    ]

  outputBodies = map snd rows.grRows <> maybeToList rows.grOtherwise

  inlineNotes =
    [ dmnNote "D-INLINEDLOCAL" Advisory here tableRange
        ("the WHERE/LET local(s) " <> Text.intercalate ", " (map tick inlined)
           <> " were inlined into the cells that used them; DMN has no lexically scoped \
              \intermediate value")
        "the name the drafter gave the intermediate quantity"
    | not (null inlined)
    ]

  capNotes =
    [ dmnNote "D-FLATTENCAP" Advisory here (bestRange b)
        ("a nested guarded chain was left as an output expression rather than spliced into \
         \more rules, because flattening hit the depth or row cap")
        "the rows the nested chain would have contributed"
    | b <- cappedBodies
    ]

  thresholdNotes =
    [ dmnNote "D-LIFTEDTHRESHOLD" Advisory here (bestRange sub)
        ("`" <> oneLine (prettyLayout sub) <> "` was lifted to " <> fn
           <> "(...): the threshold is now inside an output expression rather than a row of the table")
        "a compliance reader's ability to point at the threshold as a rule"
    | body <- outputBodies
    , (fn, sub) <- liftedThresholds ctx body
    ]

  tick t = "`" <> t <> "`"

  isConstantText fe =
    fe.feFragment == SFeel
      && ( fe.feText `elem` ["true", "false"]
             || Text.isPrefixOf "\"" fe.feText
             || isNumericText fe.feText
         )

dedupeNotes :: [FidelityNote] -> [FidelityNote]
dedupeNotes = go Set.empty
 where
  go _ [] = []
  go seen (n : ns)
    | Set.member k seen = go seen ns
    | otherwise         = n : go (Set.insert k seen) ns
   where
    k = (n.code, n.message)

-- | The first source range anywhere under an expression. Guards synthesised by
-- 'normaliseGuarded' (a @CONSIDER@ arm becomes @scrutinee EQUALS ctor@) carry an
-- empty annotation at the root, but their scrutinee still knows where it came
-- from, so a note is still locatable.
bestRange :: Expr Resolved -> Maybe SrcRange
bestRange e =
  listToMaybe
    (mapMaybe (\x -> (getAnno x).range) (toListOf (cosmosOf (gplate @(Expr Resolved))) e))

------------------------------------------------------------------------
-- The module
------------------------------------------------------------------------

-- | Every top-level @DECIDE@ becomes a @\<decision\>@; every free term becomes an
-- @\<inputData\>@; references between decisions become
-- @\<informationRequirement\>@s.
lowerModule :: DmnLowerOptions -> Module Resolved -> Drg
lowerModule opts modul@(MkModule _ uri _) =
  MkDrg
    { drgId        = "definitions_" <> modelId
    , drgName      = opts.dloModelName
    , drgNamespace = "https://legalese.com/l4/dmn/" <> modelId
    , drgFlavor    = opts.dloFlavor
    , drgItemDefs  = itemDefs
    , drgNodes     = nodes
    , drgNotes     = sharedInputNotes <> renameNotes <> feelNameCollisionNotes
                       <> itemDefNotes <> componentMaybeNotes <> inputMaybeNotes
                       <> ruleDateNotes <> computedFieldNotes <> hydratorVerbatimNotes
                       <> concatMap snd lowered
                       <> phase4Notes
                       <> serviceNotes
    }
 where
  modelId = sanitiseId opts.dloModelName

  -- Named rather than inlined into 'drgNodes' because the itemDefinition list
  -- reads the emitted types back off it, to decide which domain-free aliases
  -- are pointed at. Nothing flows the other way, so there is no knot.
  --
  -- Phase 5: the tier-2 emitted-BKM decides leave the decision block and are
  -- APPENDED as businessKnowledgeModel nodes (tDefinitions sequences
  -- drgElement*, and intra-group order is free — the same reasoning that puts
  -- hydrators after the decisions). Every caller — decision and hydrator
  -- alike — goes through 'finishCaller', which splits classifyRef's uniform
  -- edges into informationRequirements and knowledgeRequirements and adds the
  -- requirement edges the rendered closure arguments need.
  nodes =
    finishedDecisionNodes
      <> [ NodeBkm (toBkm d dec)
         | (d, (dec, _)) <- zip decides lowered
         , isBkmDecide d
         ]
      <> serviceNodes

  finishedDecisionNodes :: [DrgNode]
  finishedDecisionNodes =
    map NodeInputData inputNodes
      <> [ NodeDecision (finishCaller dec)
         | (d, (dec, _)) <- zip decides lowered
         , not (isBkmDecide d)
         ]
      <> map (NodeDecision . finishCaller) hydratorNodes

  -- The emitted BKM ids, and the way back from an edge target to the BKM.
  bkmIdSet :: Set Text
  bkmIdSet = Set.fromList (Map.elems bkmIdByUnique)

  bkmIdByUnique :: Map Unique Text
  bkmIdByUnique = Map.fromList
    [ (getUnique (decideResolved d), did)
    | (d, did) <- zip decides decideIds
    , isBkmDecide d
    ]

  bkmUniqueById :: Map Text Unique
  bkmUniqueById = Map.fromList [(i, u) | (u, i) <- Map.toList bkmIdByUnique]

  -- Phase 5 (§6.2): split the uniform RequiredDecision edges 'classifyRef'
  -- produced into (a) true informationRequirements, (b) knowledgeRequirement
  -- edges for called BKMs — the edge is REQUIRED by KIE (compile error
  -- without it) and Camunda has no backstop at all (silent null), probes
  -- C3/D3 — and (c) the extra information requirements the caller needs so
  -- that every λ-lifted closure argument it now renders (`name: name`) is in
  -- its FEEL scope.
  finishCaller :: Decision -> Decision
  finishCaller dec =
    dec
      { dcnRequirements  = sort (nubOrd (plainEdges <> closureExtras))
      , dcnKnowledgeReqs =
          sort
            (nubOrd
               ( [RequiredBkm t | RequiredDecision t <- bkmEdges]
                   -- kie only (the map is empty otherwise): the caller's info
                   -- edge on a §-invocable callee becomes the
                   -- knowledgeRequirement→SERVICE edge the invocation needs —
                   -- REPLACES, not accompanies: an informationRequirement
                   -- would make the safety-refused callee a hard dependency
                   -- of this caller on KIE.
                   <> [ RequiredService sid
                      | RequiredDecision t <- svcEdges
                      , Just sid <- [Map.lookup t svcEdgeByDecisionId]
                      ]
               ))
      }
   where
    (bkmEdges, infoEdges) = partition isBkmEdge dec.dcnRequirements
    (svcEdges, plainEdges) = partition isSvcEdge infoEdges
    isBkmEdge = \case
      RequiredDecision t -> Set.member t bkmIdSet
      RequiredInput _    -> False
    isSvcEdge = \case
      RequiredDecision t -> Map.member t svcEdgeByDecisionId
      RequiredInput _    -> False
    closureExtras =
      [ edge
      | RequiredDecision t <- bkmEdges
      , Just bu <- [Map.lookup t bkmUniqueById]
      , cr <- Set.toList (Map.findWithDefault Set.empty bu bkmClosure)
      , Just edge <- [closureEdge cr]
      ]

  -- A lowered tier-2 decide, rewrapped as the BKM it is (§6.2). Its
  -- 'dcnRequirements' are consumed rather than kept: the BKM-target edges
  -- become its OWN knowledgeRequirements (the BKM→BKM edge lives on the
  -- calling BKM, probe C1), and everything else was λ-lifted into
  -- formalParameters — a BKM has no informationRequirement child at all.
  toBkm :: Decide Resolved -> Decision -> Bkm
  toBkm d dec =
    MkBkm
      { bkmId            = dec.dcnId
      , bkmName          = dec.dcnName
      , bkmFeelName      = dec.dcnFeelName
      , bkmType          = dec.dcnType
      , bkmParams        =
          [ MkFormalParameter
              { fpId    = dec.dcnId <> "_p" <> tshow i
              , fpName  = fn
              , fpLabel = lbl
              , fpType  = t
              }
          | (i, (fn, lbl, t)) <- zip [1 :: Int ..] (givenTriples <> closureTriples)
          ]
      , bkmLogic         = dec.dcnLogic
      , bkmKnowledgeReqs =
          sort
            (nubOrd
               [ RequiredBkm t
               | RequiredDecision t <- dec.dcnRequirements
               , Set.member t bkmIdSet
               ])
      }
   where
    (givens, closures) =
      Map.findWithDefault ([], []) (getUnique (decideResolved d)) bkmSignatures
    givenTriples   = [(gn, lbl, t) | (_, lbl, gn, t) <- givens]
    -- A closure parameter's label IS its name: the parameter stands for the
    -- module element of that exact spelling, and 'namedAttrs' omits an
    -- @label@ that equals the @name@.
    closureTriples = [(cn, cn, t) | (_, cn, t) <- closures]

  decls   = topDecls modul
  -- The TopDecl's own annotation is kept, not discarded: `attachRef` claims an
  -- `@ref` at the TopDecl level ("L4.Parser.ResolveAnnotation":1050-1061), so
  -- reading only the inner MkDecide's annotation loses every citation. Both are
  -- read, joined with `<|>`, so the annotation column does not depend on which
  -- node ends up holding it.
  -- §4.4. The synthetic functions "L4.Desugar" made out of computed record
  -- fields LEAVE the decision list: they mint no id, no FEEL name and no node,
  -- because a hydrator computes them inline from its sibling entries instead.
  -- What replaces them is 'hydrators' below.
  --
  -- Their 'Unique's rejoin the story in two places, and BOTH are load-bearing:
  -- 'selectors' (or a reference to `doubled amount` would mint a bogus
  -- inputData named after the field) and 'fieldScopes' (or the hydrated
  -- component would miss the record's own uniquifyIn scope and could collide
  -- with a stored field's path step in silence).
  (computedSelectorDecides, allDecidesAnn) =
    partitionEithers
      [ if isComputedSelectorKind (decideResolved d) then Left d else Right (ann, d)
      | Decide ann d <- decls
      ]
  allDecides = map snd allDecidesAnn
  assumes = [a | Assume _ a <- decls]

  ------------------------------------------------------------------------
  -- Phase 4: the call-graph analysis (L4.Dmn.Analysis), over the FULL
  -- decide population — the population filter itself is one of its outputs.
  ------------------------------------------------------------------------

  callGraph :: A.CallGraph
  callGraph =
    A.buildCallGraph allDecides
      [dir | Directive _ dir <- decls]
      -- non-Decide top-level expressions whose references keep a decide
      -- alive: TIMEZONE declarations and the computed-field selector bodies
      -- (those left 'decides' in the §4.4 partition above, but a computed
      -- field reading a decision is a real, live reference).
      ( [e | Timezone _ e <- decls]
          <> map (view decideBody) computedSelectorDecides
      )

  safetyIssues :: Map Unique [A.SafetyIssue]
  safetyIssues =
    A.analyzeSafety
      A.MkSafetyInput
        { A.siMissingRanges  = opts.dloMissingMatchRanges
        , A.siClauseMatrixRanges = opts.dloClauseMatrixRanges
        , A.siNonexhaustive  = A.nonexhaustiveDecides allDecides
        , A.siEnumFields     =
            Map.fromList
              [ ( getUnique tn
                , [ (nameOf cn, Set.fromList [nameOf fn | MkTypedName _ fn _ _ _ <- fs])
                  | MkConDecl _ cn fs <- cds
                  ]
                )
              | Declare _ (MkDeclare _ _ (MkAppForm _ tn _ _) (EnumDecl _ cds)) <- decls
              , length cds > 1
              ]
        , A.siComponentTypes =
            Map.fromList
              [ (getUnique tn, componentTysOf td)
              | Declare _ (MkDeclare _ _ (MkAppForm _ tn _ _) td) <- decls
              ]
        , A.siSubst          = opts.dloSubstitution
        , A.siUri            = uri
        }
      callGraph allDecides
   where
    componentTysOf = \case
      RecordDecl _ _ fs -> [ty | MkTypedName _ _ ty _ _ <- fs]
      EnumDecl _ cds    -> [ty | MkConDecl _ _ fs <- cds, MkTypedName _ _ ty _ _ <- fs]
      SynonymDecl _ ty  -> [ty]

  popVerdict :: A.PopulationVerdict
  popVerdict =
    A.classifyPopulation
      A.MkPopulationInput
        { A.piIncludeTests     = opts.dloIncludeTests
        , A.piExternalRefNames = opts.dloExternalRefNames
        , A.piForcedRef        = \r ->
            let u = getUnique r
            in (u.moduleUri == uri || u == TC.rulesEffectiveDateUnique)
                 && not (Set.member u constructors)
                 && not (Set.member u selectors)
                 && not (Set.member u computedSelfUniques)
        -- R12 (§15.12): the rebind predicate, over the RAW body. The old
        -- lowering-time detection ran over the caramelised+peeled body;
        -- 'gplate' descends through WHERE/LET locals from the raw body too,
        -- which not-ok/ruledate-rebind.l4's WHERE-wrapped case pins.
        , A.piRuleDateRebind   = \b ->
            or [ getUnique r == TC.evalUnderRulesEffectiveAtUnique
               | App _ r _ <- toListOf (cosmosOf (gplate @(Expr Resolved))) b
               ]
        }
      callGraph allDecides

  -- The EMITTED population: everything the filter did not drop. Every
  -- consumer below reads this list, so a dropped decision mints no node, no
  -- FEEL name and no inputData — and its absence is never silent, because
  -- 'populationNotes' names every drop.
  decidesAnn = [p | p@(_, d) <- allDecidesAnn, kept d]
   where
    kept d = not (Map.member (getUnique (decideResolved d)) popVerdict.pvDropped)
  decides = map snd decidesAnn

  -- Tier-1, DMN-SAFE, parameterised, kept: the un-lift set (§2.1, §2.4).
  -- Everything else keeps today's behaviour — a <decision> whose saturated
  -- call sites render verbatim (already Blocking-noted) — which is OPEN-1's
  -- ruling: Phase 4 classifies and reports; it does not change node kind.
  unliftedSet :: Set Unique
  unliftedSet = Set.fromList
    [ u
    | d <- decides
    , let u = getUnique (decideResolved d)
    , not (null (A.decideParams d))
    , A.tierOf callGraph u == A.Tier1
    , not (Map.member u safetyIssues)
    ]

  ------------------------------------------------------------------------
  -- Phase 5: BKM emission (§6.2)
  ------------------------------------------------------------------------

  -- Tier-2, DMN-SAFE, parameterised, kept: the emitted-BKM set. The same
  -- predicate as the D-BKM classification, MINUS the safety-refused members
  -- (§6.2's stated boundary): a tier-2 decide with safetyIssues keeps its
  -- <decision> node, its verbatim call sites and its D-PARTIAL note exactly
  -- as in Phase 4 — an uncertified body inside a BKM would be the same silent
  -- null one element kind later.
  bkmCandidateSet :: Set Unique
  bkmCandidateSet = Set.fromList
    [ u
    | d <- decides
    , let u = getUnique (decideResolved d)
    , not (null (A.decideParams d))
    , A.tierOf callGraph u == A.Tier2
    , not (Map.member u safetyIssues)
    ]

  isBkmDecide d = Set.member (getUnique (decideResolved d)) bkmCandidateSet

  (bkmDecides, plainDecides) = partition isBkmDecide decides

  -- The GIVEN binders of every emitted BKM. These leave the inputData
  -- population ('decideFreeTerms' filters them): a BKM parameter is bound
  -- per-call by the invocation, not supplied globally — which is the whole
  -- point of tier 2.
  bkmParamSet :: Set Unique
  bkmParamSet = Set.fromList
    [ getUnique p
    | d <- bkmDecides
    , (p, _) <- A.decideParams d
    ]

  ------------------------------------------------------------------------
  -- Phase 4: the name-keyed parameter merge (§2.1, §2.5.3)
  ------------------------------------------------------------------------

  -- GIVEN parameters of un-lifted decisions, grouped by VERBATIM L4 name
  -- (OPEN-2: two spellings that merely FOLD to one FEEL identifier are
  -- different parameters; 'uniquifyIn' renames them apart and @D-RENAME@
  -- reports it). Each entry: binder unique, declared-type spelling
  -- ('Nothing' = the GIVEN carries no declared type), owner name, owner
  -- unique.
  paramGroups :: Map Text [(Unique, Maybe Text, Text, Unique)]
  paramGroups = Map.fromListWith (flip (<>))
    [ ( nameOf p
      , [ ( getUnique p
          , oneLine . prettyLayout <$> mty
          , decideName d
          , getUnique (decideResolved d)
          )
        ]
      )
    | d <- decides
    , Set.member (getUnique (decideResolved d)) unliftedSet
    , (p, mty) <- A.decideParams d
    ]

  -- The merge, refused per group on type conflict: the group map is built
  -- with 'Map.fromListWith' and consumed as a whole list — NEVER
  -- 'Map.fromList', which is last-wins and is the genuine defect §7 names
  -- (latent while 'freeTermSrc' was keyed by 'Unique'; a name-keyed merge is
  -- exactly what makes it live). On conflict nothing merges and
  -- 'paramTypeNotes' says so at Blocking; un-lifting of each individual
  -- decision still proceeds — what is refused is the MERGE.
  --
  -- A merge needs POSITIVE evidence of agreement: every member DECLARES a
  -- type, and all the spellings agree. An untyped GIVEN supplies no evidence
  -- at all, so any group containing one is a conflict. This used to compare
  -- the sentinel spelling @\"\<untyped\>\"@ instead, under which two untyped
  -- same-named GIVENs of different INFERRED types compared equal, merged into
  -- one @typeRef=Any@ element, and silenced both D-PARAMTYPE and D-SCOPE —
  -- one decision then read the other's NUMBER as its BOOLEAN and answered
  -- null\/SUCCEEDED with zero notes, the precise hazard the conflict test was
  -- written to stop.
  mergedGroups, conflictGroups :: [(Text, [(Unique, Maybe Text, Text, Unique)])]
  (mergedGroups, conflictGroups) =
    partitionEithers
      [ case traverse (\(_, mty, _, _) -> mty) members of
          Just tys | length (nubOrd tys) == 1 -> Left (nm, members)
          _                                   -> Right (nm, members)
      | (nm, members) <- Map.toAscList paramGroups
      , length members > 1
      ]

  -- member unique -> canonical unique (the first claimant in source order).
  mergeMap :: Map Unique Unique
  mergeMap = Map.fromList
    [ (u, canonical)
    | (_, members@((canonical, _, _, _) : _)) <- mergedGroups
    , (u, _, _, _) <- members
    ]

  canonUnique :: Unique -> Unique
  canonUnique u = Map.findWithDefault u u mergeMap

  -- @ref text and definition position, by the decide's own Unique. Both feed
  -- the interval table's annotation column (§15.9).
  decideRefs :: Map Unique Text
  decideRefs = Map.fromList
    [ (getUnique (decideResolved d), getRef r)
    | (ann, d) <- decidesAnn
    , Just r <- [listToMaybe (catMaybes [view annRef ann, view annRef (getAnno d)])]
    ]

  decideRanges :: Map Unique SrcRange
  decideRanges = Map.fromList
    [ (getUnique (decideResolved d), rng)
    | d <- decides
    , Just rng <- [(getAnno d).range]
    ]

  constructors = Set.fromList
    [ getUnique n | Declare _ (MkDeclare _ _ _ td) <- decls, n <- constructorNames td ]

  constructorNames = \case
    EnumDecl _ cds    -> [n | MkConDecl _ n _ <- cds]
    RecordDecl _ mn _ -> maybeToList mn
    SynonymDecl _ _   -> []

  -- Field selectors are references in the AST but are not terms; a record
  -- projection must not conjure an inputData element for the field name.
  -- ...and the COMPUTED selectors join them (§4.4). This is not cosmetic:
  -- 'decideFreeTerms' excludes a reference only if it is a known decide, a
  -- constructor or a selector, so taking the computed-field decides out of
  -- 'decides' without putting their Uniques here would turn every read of
  -- `doubled amount` into an <inputData> named after the field -- a supplied
  -- value where the model computes one. They ARE selectors; 'TermKind' says so.
  selectors = Set.fromList $
    [ getUnique n | Declare _ (MkDeclare _ _ _ td) <- decls, n <- selectorNames td ]
      <> map (getUnique . decideResolved) computedSelectorDecides

  selectorNames = \case
    EnumDecl _ cds    -> [n | MkConDecl _ _ fs <- cds, MkTypedName _ n _ _ _ <- fs]
    RecordDecl _ _ fs -> [n | MkTypedName _ n _ _ _ <- fs]
    SynonymDecl _ _   -> []

  -- §5.2 SCOPE 2: the record-field namespace. One 'uniquifyIn' PER DECLARED
  -- TYPE, in field source order, because that is the namespace DMN has -- an
  -- itemDefinition's itemComponent list, and until itemDefinitions exist
  -- (Phase 3) the projection paths this module emits. Two different records may
  -- each own a field that folds to `foo_bar` without either being renamed; two
  -- fields of ONE record may not, and that case is the corpus's one executed
  -- collision, which used to emit `p.foo_bar + p.foo_bar` -- valid FEEL,
  -- computing a wrong number, with no note (§5.3.4).
  -- COMPUTED selectors are appended to their record's stored ones, inside the
  -- SAME 'uniquifyIn' call (§4.4). Two consequences, both wanted:
  --
  --   * a computed component and a stored one that fold to the same identifier
  --     are separated here, once, rather than colliding as path steps later --
  --     which is §5.3.4's executed collision, and it would otherwise be
  --     reintroduced by hydration;
  --   * 'neFields' then serves BOTH the context entry names and the downstream
  --     `hydrated.entry` path steps, so those two agree by construction and not
  --     because two functions happen to fold the same way.
  --
  -- Appended AFTER the stored ones so a record with no computed fields keeps
  -- byte-identical component names.
  fieldScopes :: [(Text, [(Resolved, Text, Text)])]
  fieldScopes =
    [ (nameOf tn, zip3 ns (map (feelIdentText . nameOf) ns) (uniquifyIn foldedNs))
    | Declare _ (MkDeclare _ _ (MkAppForm _ tn _ _) td) <- decls
    , let ns = selectorNames td <> computedSelectorsOf (getUnique tn)
    , let foldedNs = map (feelIdentText . nameOf) ns
    , not (null ns)
    ]

  ------------------------------------------------------------------------
  -- Computed fields, recovered from the desugaring (§4.4)
  ------------------------------------------------------------------------

  -- Every computed field, keyed by the Unique of the record that owns it, in
  -- DECLARATION order. @desugarCFDeclare@ emits @newDeclare : syntheticDecides@
  -- with the decides in field order, and 'decls' preserves that, so no sorting
  -- is needed to recover the source order -- only the topological one below.
  computedFieldsOf :: Map Unique [ComputedField]
  computedFieldsOf = Map.fromListWith (flip (<>))
    [ (owner, [MkComputedField { cfSel = decideResolved d, cfSelf = self, cfBody = body }])
    | d@(MkDecide _ _ _ body) <- computedSelectorDecides
    , Just (owner, self, _) <- [computedSelectorOwner d]
    ]

  computedSelectorsOf u = map (.cfSel) (Map.findWithDefault [] u computedFieldsOf)

  -- Every synthetic `_self` binder in the module, so 'freeTerms' can exclude
  -- them and 'hydratorNodes' can keep them out of the DRG.
  computedSelfUniques :: Set Unique
  computedSelfUniques = Set.fromList
    [getUnique cf.cfSelf | cfs <- Map.elems computedFieldsOf, cf <- cfs]

  -- The computed fields of one record, ordered so that every field comes AFTER
  -- the siblings it reads.
  --
  -- ★ A boxed context's entries evaluate in order and only EARLIER siblings are
  -- in scope, so getting this wrong is silently wrong rather than loudly:
  -- the reference resolves to nothing and FEEL answers null.
  -- @detectComputedFieldCycles@ guarantees ACYCLICITY only; declaration order is
  -- not guaranteed topological, and jl4/examples/ok/computed-fields.l4 cannot
  -- catch the omission because its declaration order already happens to be
  -- topological. jl4/examples/dmn/hydration.l4 declares a dependent BEFORE its
  -- dependency precisely so that it can.
  --
  -- A depth-first emit in DECLARATION order: walk the fields as declared, and
  -- before emitting one, emit any sibling it reads that is not out yet. That
  -- gives dependency order where there IS a dependency and declaration order
  -- everywhere else — which is the property a reader diffing the base
  -- itemDefinition against the hydrated one relies on, and which the
  -- @D-COMPUTEDFIELD@ note asserts when it says the derived components are
  -- computed "from the components declared before them".
  --
  -- ★ NOT 'Data.Graph.stronglyConnComp', which was the first implementation.
  -- It does give dependencies first, but it gives no guarantee at all about
  -- INDEPENDENT vertices, and it duly reversed Reg CF's `greater of …` and
  -- `lesser of …` — two mutually independent fields — against their DECLARE.
  -- Harmless to evaluate, wrong as a claim, and the comment that used to sit
  -- here asserted the opposite.
  --
  -- Termination does not depend on acyclicity: a field is marked emitted BEFORE
  -- its dependencies are walked, so a cycle stops rather than loops. Acyclicity
  -- itself comes from @detectComputedFieldCycles@ (L4.Desugar), which runs long
  -- before this.
  computedFieldsSorted :: Unique -> [ComputedField]
  computedFieldsSorted owner = snd (foldl' step (Set.empty, []) fields)
   where
    fields = Map.findWithDefault [] owner computedFieldsOf
    byUniq = Map.fromList [(getUnique cf.cfSel, cf) | cf <- fields]

    step (seen, acc) cf = let (seen', out) = emit seen cf in (seen', acc <> out)

    emit seen cf
      | Set.member u seen = (seen, [])
      | otherwise         = let (seen', before) = foldl' pull (Set.insert u seen, []) (siblingDeps cf)
                            in (seen', before <> [cf])
     where
      u = getUnique cf.cfSel

    pull (seen, acc) d = case Map.lookup d byUniq of
      Just dcf -> let (seen', out) = emit seen dcf in (seen', acc <> out)
      Nothing  -> (seen, acc)

    siblingDeps cf =
      [ u
      | n <- projSelectorsOf cf.cfBody
      , let u = getUnique n
      , Map.member u byUniq
      ]

  projSelectorsOf e =
    [n | Proj _ _ n <- toListOf (cosmosOf (gplate @(Expr Resolved))) e]

  fieldNames :: Map Unique Text
  fieldNames = Map.fromList
    [ (getUnique n, resolved) | (_, fs) <- fieldScopes, (n, _, resolved) <- fs ]

  ------------------------------------------------------------------------
  -- The data model (§4, Phase 3)
  ------------------------------------------------------------------------

  -- Every module-local DECLARE that has an itemDefinition, in source order.
  --
  -- __Referenced or not.__ Reachability-gating would make the artifact depend
  -- on which decisions happened to survive lowering -- a moving target that
  -- would change the type-level output of the export every time a body did --
  -- and an unreferenced itemDefinition is inert.
  itemDecls :: [ItemDecl]
  itemDecls =
    [ MkItemDecl
        { itdUnique   = getUnique tn
        , itdName     = nameOf tn
        -- Constructor spellings come from 'nameOf', NOT 'feelIdentText': a
        -- constructor name becomes a FEEL string LITERAL (the tag value), never
        -- an identifier, so the name fold must not touch it (§5.3.6). It is
        -- also the exact string the cells already carry, so the domain and the
        -- cells cannot disagree.
        , itdCtors    = ctors
        -- STORED fields only. The 5th field of 'MkTypedName' is `Just expr` for
        -- a COMPUTED field (a `MEANS` clause), which is derived rather than
        -- supplied; emitting it as an itemComponent would misstate the model's
        -- input contract, so it is skipped and reported D-ITEMDEF.
        --
        -- __The filter is unexercised on this tree, and the reason is worth
        -- knowing rather than discovering.__ "L4.Desugar" rewrites a computed
        -- field into a synthetic top-level @DECIDE@ __before type checking__,
        -- so the @Declare@ this module sees never carries one: on
        -- @jl4\/examples\/dmn\/sumtype.l4@, whose @Claim@ declares
        -- @`doubled amount` IS A NUMBER MEANS …@, the emitted itemDefinition
        -- has the other components and the field is a @\<decision\>@ of its own
        -- reading a @_self@ @inputData@ typed @Claim@. So the information is
        -- relocated, not dropped, and the D-ITEMDEF arm below has zero
        -- exercise. It is kept for the same reason @D-FEELNAME@ is (§7): the
        -- day the desugaring stops running before this pass, an input contract
        -- that silently gained a derived field is not a failure anyone would
        -- see.
        --
        -- __Do not confuse this with @D-COMPUTEDFIELD@ (§4.4, added
        -- 2026-07-31), which is a different note about a different type.__ This
        -- arm would say that the BASE definition dropped a derived field;
        -- @D-COMPUTEDFIELD@ says that the HYDRATED definition CARRIES derived
        -- components and that DMN cannot mark them as derived. Both remain
        -- true simultaneously, and the base definition staying stored-only is
        -- deliberate: it is the model's input contract, and a caller never
        -- supplies a derived component.
        , itdFields   = [(fn, fty) | MkTypedName _ fn fty _ Nothing <- flds]
        , itdComputed = [nameOf fn | MkTypedName _ fn _ _ (Just _) <- flds]
        , itdPayload  = payload
        }
    | Declare _ (MkDeclare _ _ (MkAppForm _ tn _ _) td) <- decls
    , Just (ctors, flds, payload) <- [itemShapeOf td]
    ]

  -- @Just (constructor names, stored+computed fields, is a payload union)@, or
  -- 'Nothing' for a declaration that gets no itemDefinition.
  itemShapeOf = \case
    RecordDecl _ _ rfs -> Just ([], rfs, False)
    -- §4.2.1-7 leaves the SINGLE payload constructor unruled, and there are
    -- zero in the corpora, so the choice is free and stating it stops a guess:
    -- it is a record, and the itemDefinition is named after the TYPE, which is
    -- what §4.1 already does for `DECLARE T HAS`.
    EnumDecl _ [MkConDecl _ _ cfs] | not (null cfs) -> Just ([], cfs, False)
    EnumDecl _ cds ->
      Just
        ( [nameOf cn | MkConDecl _ cn _ <- cds]
        , []
        , length cds > 1 && any (\(MkConDecl _ _ cfs) -> not (null cfs)) cds
        )
    SynonymDecl _ _ -> Nothing

  itemDefIds   = assignIds "itemdef_" (map (.itdName) itemDecls)

  -- The types that assert a range, and therefore the ones a @MAYBE@ site needs
  -- a domain-free alias of (R8-a's carve-out).
  domainDecls = [d | d <- itemDecls, not (null d.itdCtors)]

  -- ONE 'uniquifyIn' scope (§5.2, A3), and it is the itemDefinition-name
  -- namespace only: DMN keeps that apart from the DRG's variable namespace, so
  -- a type and a variable may share a name without either being renamed.
  --
  -- __The aliases are minted in the same scope as the base names__, and after
  -- them, so a hand-written @DECLARE Grade_optional@ keeps its own name and the
  -- alias takes the suffix rather than the other way round. That is why this is
  -- one 'uniquifyIn' over a concatenation and not two: two scopes could hand
  -- the same string to a type and to an alias, and the alias would then silently
  -- acquire the domain it exists to drop.
  -- ...and the HYDRATED names are minted in the same scope, after the aliases,
  -- for the same reason: a hand-written @DECLARE Claim_hydrated@ keeps its own
  -- name and the generated one takes the suffix, rather than the other way
  -- round.
  (itemDefNames, aliasAndHydratedNames) =
    splitAt (length itemDecls) $ uniquifyIn $
      map (feelTypeNameText . (.itdName)) itemDecls
        <> [feelTypeNameText d.itdName <> "_optional" | d <- domainDecls]
        <> [feelTypeNameText d.itdName <> "_hydrated" | d <- hydratedDecls]
  (optionalNames, hydratedNames) =
    splitAt (length domainDecls) aliasAndHydratedNames

  -- One hydrated definition per hydrated TYPE, gated identically to the
  -- hydrators that point at it -- same alias rationale as above.
  hydratedDecls :: [ItemDecl]
  hydratedDecls =
    [d | d <- itemDecls, Set.member d.itdUnique hydratedRecordUniques]

  hydratedRecordUniques :: Set Unique
  hydratedRecordUniques = Set.fromList [owner | (_, _, owner) <- hydratedInstances]

  hydratedNameOf :: Map Unique Text
  hydratedNameOf = Map.fromList (zip (map (.itdUnique) hydratedDecls) hydratedNames)

  hydratedIdOf :: Map Unique Text
  hydratedIdOf = Map.fromList
    [ (d.itdUnique, iid <> "_hydrated")
    | (d, iid) <- zip itemDecls itemDefIds
    , Set.member d.itdUnique hydratedRecordUniques
    ]

  optionalNameOf :: Map Unique Text
  optionalNameOf = Map.fromList (zip (map (.itdUnique) domainDecls) optionalNames)

  typeEnv :: TypeEnv
  typeEnv = MkTypeEnv
    { teNamed    = Map.fromList (zip (map (.itdUnique) itemDecls) itemDefNames)
    , teDomains  = Map.fromList
        [(d.itdUnique, d.itdCtors) | d <- itemDecls, not (null d.itdCtors)]
    , tePayload  = Set.fromList [d.itdUnique | d <- itemDecls, d.itdPayload]
    , teOptional = optionalNameOf
    , teUri      = uri
    }

  -- The base definitions, then the aliases any element actually points at.
  --
  -- __Alias minting is reachability-gated and the base definitions are not__,
  -- and the asymmetry is the point. A base definition is minted per @DECLARE@
  -- because an unreferenced one is inert and gating it would make the type
  -- half of the artifact move whenever a decision body did. An alias is not
  -- inert in the same way: it exists only to be the target of a @MAYBE@ site,
  -- so one with no referrer is noise in an artifact whose whole claim is that
  -- every line in it means something. The gate is the emitted 'DmnType's, not
  -- the L4, so what is minted and what is pointed at cannot disagree.
  itemDefs :: [ItemDefinition]
  itemDefs = baseItemDefs <> aliasItemDefs <> hydratedItemDefs

  -- §4.4. The stored components verbatim -- same names, same typeRefs, so a
  -- reader can diff the two definitions and see exactly what hydration added --
  -- then the computed ones, in the same topological order the context entries
  -- take.
  --
  -- __The computed components' types come from the synthetic decides' GIVETH,
  -- not from the DECLARE__: 'itdComputed' is empty on this tree, because the
  -- desugaring already ran and took the MEANS clauses with it.
  hydratedItemDefs :: [ItemDefinition]
  hydratedItemDefs =
    [ MkItemDefinition
        { idfId         = hid
        , idfName       = hnm
        , idfLabel      = d.itdName
        , idfBase       = Nothing
        , idfValues     = Nothing
        , idfComponents =
            zipWith (itemComponent hid) [1 :: Int ..] d.itdFields
              <> [ MkItemComponent
                     { icmId    = hid <> "_c" <> tshow i
                     , icmName  = feelFieldIn nameEnv cf.cfSel
                     , icmLabel = nameOf cf.cfSel
                     , icmType  = computedFieldType cf
                     }
                 | (i, cf) <- zip [length d.itdFields + 1 ..]
                                  (computedFieldsSorted d.itdUnique)
                 ]
        }
    | d <- hydratedDecls
    , Just hid <- [Map.lookup d.itdUnique hydratedIdOf]
    , Just hnm <- [Map.lookup d.itdUnique hydratedNameOf]
    ]

  -- The GIVETH of the synthetic decide the field became.
  computedFieldType cf =
    case [ty | MkDecide _ (MkTypeSig _ _ (Just (MkGivethSig _ ty))) (MkAppForm _ n _ _) _
                 <- computedSelectorDecides
             , getUnique n == getUnique cf.cfSel] of
      (ty : _) -> let (t, _, _) = classifyType typeEnv ty in t
      []       -> DmnAny

  -- D-COMPUTEDFIELD: ADVISORY, one per hydrated TYPE, raised on the hydrated
  -- itemDefinition.
  --
  -- Advisory rather than Lossy, and it is not a fudge: nothing an ENGINE needs
  -- is missing, because hydration means no caller ever supplies a derived
  -- component. What a reader of the TYPE ALONE cannot do is tell which
  -- components are the model's input contract and which the model computes for
  -- itself -- and that is a note about legibility, not about correctness.
  -- FIDELITY-SEVERITY-AXIS-SPEC.md §3.2 binds Advisory to the `Faithful`
  -- effect, which is exactly the claim being made.
  computedFieldNotes =
    [ dmnNote "D-COMPUTEDFIELD" Advisory hid Nothing
        ("`" <> d.itdName <> "` is hydrated as `" <> hnm <> "`, whose component(s) "
           <> Text.intercalate ", " (map (tick . nameOf . (.cfSel)) cfs)
           <> " are DERIVED: L4 defines each by a MEANS clause on the DECLARE, and this model \
              \computes them in the boxed context of the hydrated decision from the components \
              \declared before them. DMN cannot say so -- tItemDefinition has no derived flag, \
              \and a contextEntry is indistinguishable from a supplied value -- so a reader of \
              \the hydrated type alone cannot tell a derived component from a stored one")
        "nothing an engine needs -- hydration means no caller ever supplies one. What is lost \
        \is a reader's ability to tell, FROM THE TYPE, which components are the model's input \
        \contract and which the model computes for itself"
    | d <- hydratedDecls
    , Just hid <- [Map.lookup d.itdUnique hydratedIdOf]
    , Just hnm <- [Map.lookup d.itdUnique hydratedNameOf]
    , let cfs = computedFieldsSorted d.itdUnique
    , not (null cfs)
    ]

  -- ★ A hydrator's context entries go through the SAME verbatim gate every
  -- other emitted expression does, and this note is what applies it.
  --
  -- Every other rendering path in this module asks @feFragment == L4Verbatim@
  -- before it emits (that gate IS @D-NONFEELOUTPUT@). 'hydratorNodes' is built
  -- outside 'lowered', so none of the per-decide note machinery ever looks at a
  -- context entry — and a computed field whose body 'renderFeelIn' cannot
  -- render (a record CONSTRUCTION, a CONSIDER over a user-declared payload sum,
  -- a LIST comprehension) shipped raw L4 source inside a @\<literalExpression\>@
  -- with no note at all, a clean fidelity report and exit 0. That is the exact
  -- "green in the validator, wrong in the engine" failure the exporter exists to
  -- close, so the code is @D-NONFEELOUTPUT@ and the severity is Blocking: the
  -- loss is EXECUTABILITY, not analysability, and its message ("NO DMN engine
  -- can evaluate it") is already exactly right.
  --
  -- The message is written for a CONTEXT ENTRY rather than reusing
  -- 'nonFeelOutput' verbatim, whose words ("output entry", "defaultOutputEntry")
  -- would be false here: a hydrator has neither.
  hydratorVerbatimNotes =
    [ dmnNote "D-NONFEELOUTPUT" Blocking h.dcnId Nothing
        ("the context entry `" <> ce.ceLabel <> "` of `" <> h.dcnName
           <> "` (hydrated) is L4 source, not FEEL (`" <> ce.ceExpr.feText
           <> "`): it is a DERIVED field whose MEANS body this backend has no FEEL rendering \
              \for, so the text was emitted verbatim and NO DMN engine can evaluate it")
        "execution: an engine fails to compile the hydrated record, and with it every decision \
        \that reads a component through it"
    | h <- hydratorNodes
    , LogicContext es <- [h.dcnLogic]
    , ce <- es
    , ce.ceExpr.feFragment == L4Verbatim
    ]

  -- The hydrator decisions themselves. Appended AFTER the ordinary decisions in
  -- 'drgNodes': tDefinitions sequences drgElement*, and both <decision> and
  -- <inputData> are in that substitution group, so intra-group order is free
  -- and DMN resolves requirements by @href rather than by document order.
  -- Appending keeps every existing decision id byte-stable.
  hydratorNodes :: [Decision]
  hydratorNodes =
    [ MkDecision
        { dcnId           = hid
        , dcnName         = nm
        , dcnFeelName     = feel
        , dcnType         = DmnNamed hnm DmnAny
        -- filled by 'finishCaller': a hydrator entry may invoke a BKM (probe
        -- B1 — the edge lives on the ENCLOSING decision), and classifyRef
        -- records the reference below like any other.
        , dcnKnowledgeReqs = []
        , dcnLogic        = LogicContext (storedEntries <> computedEntries)
        -- ★ The source instance is NOT the only edge, and treating it as the
        -- only one was a defect: a computed field's @MEANS@ body may reference
        -- anything in scope at the DECLARE, and 'Desugar.rewriteFieldRefs'
        -- rewrites only the names that are the record's OWN fields. So
        -- @`b` IS A NUMBER MEANS `a` TIMES `vat rate`@ renders `a * vat_rate`
        -- inside the context, and without an edge to `decision_vat_rate` that
        -- name is not in the hydrator's evaluation scope: KIE 8.44 answers
        -- "Required dependency not found" and SKIPs, zeebe-dmn silently reads
        -- null and multiplies by it (both measured, jl4/tests-cli/fixtures/
        -- dmn-null-probe/null-absent.dmn). Computing them from the RENDERED
        -- bodies, through the same 'survivingRefs'/'classifyRef' pair every
        -- other decision uses, is what discharges R11 here as well.
        , dcnRequirements =
            sort (nubOrd (maybeToList (classifyRef hid srcRef) <> bodyEdges))
        }
    | ((u, nm, owner), hid, feel) <- zip3 hydratedInstances hydratorIds hydratorFeelNames
    , Just hnm <- [Map.lookup owner hydratedNameOf]
    , Just d   <- [listToMaybe [i | i <- itemDecls, i.itdUnique == owner]]
    , Just srcRef <- [Map.lookup u instanceRefOf]
    , let src = sourceFeelNameOf u
    , let cfs = computedFieldsSorted owner
    , let storedEntries =
            [ MkContextEntry
                { ceId    = hid <> "_ce" <> tshow i
                , ceName  = feelFieldIn nameEnv fn
                , ceLabel = nameOf fn
                , ceType  = let (t, _, _) = classifyType typeEnv fty in t
                  -- A plain copy off the source instance. Every STORED field is
                  -- copied, not only the ones a formula reads: the hydrated
                  -- itemDefinition declares them all, and a partial record whose
                  -- missing entries answer null is a trap. The cost is verbosity.
                , ceExpr  = MkFeelExpr (src <> "." <> feelFieldIn nameEnv fn) SFeel
                }
            | (i, (fn, fty)) <- zip [1 :: Int ..] d.itdFields
            ]
    , let computedEntries =
            [ MkContextEntry
                { ceId    = hid <> "_ce" <> tshow i
                , ceName  = feelFieldIn nameEnv cf.cfSel
                , ceLabel = nameOf cf.cfSel
                , ceType  = computedFieldType cf
                  -- Rendered with the field's own body under 'neBareProj', so a
                  -- projection on `_self` becomes the BARE sibling entry name --
                  -- which is what turns `_self's amount TIMES 2` into
                  -- `amount * 2`, the measured probe's shape exactly.
                  --
                  -- 'carameliseExpr' FIRST, and it is not optional: the
                  -- typechecker desugars every binary operator into a function
                  -- application, and an uncamelised body renders `amount * 2`
                  -- as an unrecognisable @App@ and therefore verbatim. Every
                  -- other rendering path in this module caramelises for the
                  -- same reason; a hydrator that skipped it would ship L4
                  -- source inside a context entry.
                , ceExpr  = renderFeelIn (bareProjEnv cf.cfSelf) constructors
                              moduleOracle (hydratorBody cf.cfBody)
                }
            | (i, cf) <- zip [length d.itdFields + 1 ..] cfs
            ]
      -- The `_self` binders are the desugaring's own synthetic parameter and
      -- render BARE (a sibling entry name), so they must not become edges:
      -- `_self` names nothing in the artifact.
    , let (bodyRefs, bodyTouched) =
            survivingRefs (map (hydratorBody . (.cfBody)) cfs)
    , let bodyEdges =
            mapMaybe (classifyRef hid)
              [r | r <- bodyRefs, not (Set.member (getUnique r) computedSelfUniques)]
              -- A computed field may itself read a COMPUTED field of some other
              -- hydrated instance, in which case the fold points the entry at
              -- that hydrator and the edge has to follow it.
              <> [ RequiredDecision h
                 | t <- bodyTouched
                 , not (Set.member t computedSelfUniques)
                 , Just h <- [Map.lookup t hydratorIdByInstance]
                 , h /= hid
                 ]
    ]

  bareProjEnv self = nameEnv { neBareProj = Set.singleton (getUnique self) }

  -- The same two preparations every other body gets before rendering:
  -- caramelise the typechecker's operator applications back into operators,
  -- then inline WHERE/LET locals. A computed field may perfectly well be
  -- written with a WHERE, and an unpeeled one would render verbatim.
  hydratorBody raw =
    let caramelised = carameliseExpr raw
    in either (const caramelised) fst (peelLocals caramelised)

  -- The defining 'Resolved' of each hydrated instance, so the hydrator's own
  -- requirement can go through the same 'classifyRef' every other edge does.
  instanceRefOf :: Map Unique Resolved
  instanceRefOf = Map.fromList
    ( [ (getUnique r, r)
      | d <- decides
      , r <- freeRefs d
      ]
        <> [(getUnique (decideResolved d), decideResolved d) | d <- decides]
    )

  aliasItemDefs :: [ItemDefinition]
  aliasItemDefs =
    [ MkItemDefinition
        { idfId         = iid <> "_optional"
        , idfName       = anm
        -- The L4 type name, verbatim, exactly as the base definition carries
        -- it: the alias IS `Grade`, minus the range. A reader who wants to
        -- know which values it holds reads the label and finds the base.
        , idfLabel      = d.itdName
        , idfBase       = Just DmnString
        -- The whole content of the alias. R8-b's suppression is what this
        -- Nothing spells, and it is spelled HERE so that the typeRef hop
        -- cannot undo it.
        , idfValues     = Nothing
        , idfComponents = []
        }
    | (d, iid) <- zip itemDecls itemDefIds
    , Just anm <- [Map.lookup d.itdUnique optionalNameOf]
    , Set.member anm referencedTypeNames
    ]

  -- Every minted type name some element's typeRef actually resolves to.
  referencedTypeNames :: Set Text
  referencedTypeNames = Set.fromList
    [ nm
    | DmnNamed nm _ <-
        concatMap nodeTypeRefs nodes
          <> [c.icmType | b <- baseItemDefs, c <- b.idfComponents]
    ]

  nodeTypeRefs :: DrgNode -> [DmnType]
  nodeTypeRefs = \case
    NodeInputData i -> [i.idType]
    NodeDecision  d -> d.dcnType : logicTypeRefs d.dcnLogic
    -- A BKM's variable, its formalParameters and its logic all carry typeRefs
    -- (§6.2), and each is a reference like any other.
    NodeBkm b -> b.bkmType : map (.fpType) b.bkmParams <> logicTypeRefs b.bkmLogic
    NodeService s -> [s.dsvType]
   where
    logicTypeRefs = \case
      LogicTable t    -> map (.icType) t.dtInputs
      LogicLiteral _  -> []
      -- A hydrator's entry typeRefs are REFERENCES like any other, and this
      -- arm is load-bearing rather than mechanical: it is what keeps a
      -- `_optional` alias alive when the only element pointing at it is a
      -- context entry of a hydrated record. Returning [] here would mint a
      -- typeRef with no definition -- valid XML, unresolvable in an engine.
      LogicContext es -> map (.ceType) es

  baseItemDefs :: [ItemDefinition]
  baseItemDefs =
    [ MkItemDefinition
        { idfId         = iid
        , idfName       = fnm
        , idfLabel      = d.itdName
        -- An enum's values serialise as strings, so its definition is a string
        -- with a domain; a record's definition IS the component list and has no
        -- base typeRef at all.
        , idfBase       = if null d.itdCtors then Nothing else Just DmnString
        , idfValues     = if null d.itdCtors then Nothing else Just d.itdCtors
        , idfComponents = zipWith (itemComponent iid) [1 :: Int ..] d.itdFields
        }
    | (d, iid, fnm) <- zip3 itemDecls itemDefIds itemDefNames
    ]

  -- The component's name comes from the SAME map a projection path reads
  -- ('fieldNames', §5.2 scope 2), so `r.f` and the component it names are one
  -- string by construction rather than by two functions agreeing.
  itemComponent iid i (fn, fty) = MkItemComponent
    { icmId    = iid <> "_c" <> tshow i
    , icmName  = Map.findWithDefault (feelIdentText (nameOf fn)) (getUnique fn) fieldNames
    , icmLabel = nameOf fn
    , icmType  = let (t, _, _) = classifyType typeEnv fty in t
    }

  -- D-ITEMDEF: one code, three reasons, so the report stays readable.
  itemDefNotes =
    [ dmnNote "D-ITEMDEF" Lossy iid Nothing
        ("`" <> d.itdName <> "`'s field `" <> f
           <> "` is COMPUTED (it is declared with a MEANS clause), so it is not part of the \
              \model's input contract and no <itemComponent> was emitted for it; DMN has no \
              \notion of a derived component")
        "the derived field: a reader of the itemDefinition cannot see that the type has it"
    | (d, iid) <- zip itemDecls itemDefIds
    , f <- d.itdComputed
    ]
      <> [ dmnNote "D-ITEMDEF" Lossy (iid <> "_c" <> tshow i) Nothing
             ("`" <> d.itdName <> "`'s component `" <> nameOf fn <> "` is typed `"
                <> oneLine (prettyLayout fty) <> "`, " <> reason
                <> ", so it is emitted as typeRef=\"Any\"")
             "the component's declared type; nothing downstream can tell what it holds"
         | (d, iid) <- zip itemDecls itemDefIds
         , (i, (fn, fty)) <- zip [1 :: Int ..] d.itdFields
         , let (_, _, fl) = classifyType typeEnv fty
         , Just reason <- [itemDefReason fl]
         ]

  -- @Nothing@ when the component's type needed no explanation.
  itemDefReason fl
    | fl.tfList =
        Just "and a collection needs an itemDefinition of its OWN -- isCollection is an \
             \attribute of tItemDefinition, not of a typeRef -- which this phase does not mint"
    | fl.tfForeign =
        Just "and it is declared in ANOTHER MODULE: this exporter lowers one module at a time, \
             \so there is no itemDefinition in this file to point a typeRef at"
    | otherwise = Nothing

  -- R8-a at the itemComponent site.
  componentMaybeNotes =
    [ maybeNullNote (iid <> "_c" <> tshow i) Nothing
        ("`" <> d.itdName <> "`'s component `" <> nameOf fn <> "`")
        (oneLine (prettyLayout fty)) fl.tfOptionalAlias
    | (d, iid) <- zip itemDecls itemDefIds
    , (i, (fn, fty)) <- zip [1 :: Int ..] d.itdFields
    , let (_, _, fl) = classifyType typeEnv fty
    , fl.tfMaybe
    ]

  -- Which module-local records THREAD a payload-carrying sum type: R4-a's
  -- second `Lossy` arm, reported at the decision that passes the record around.
  --
  -- The third component is the typeRef the itemComponent is ACTUALLY emitted
  -- with, taken from the same 'classifyType' call 'itemComponent' uses rather
  -- than from a constant in the message. It used to be spelled "Any" in the
  -- note's prose while the artifact emitted the minted name, which is the kind
  -- of claim only the artifact can settle -- so the note now reads it off the
  -- same computation the emitter does.
  sumFieldRecords :: Map Unique [(Text, Text, Text)]
  sumFieldRecords = Map.fromList
    [ (d.itdUnique, threaded)
    | d <- itemDecls
    , let threaded =
            [ ( nameOf fn
              , Map.findWithDefault "" hu itemDeclNames
              , let (t, _, _) = classifyType typeEnv fty in dmnTypeAttr t
              )
            | (fn, fty) <- d.itdFields
            , Just hu <- [typeHeadUnique fty]
            , Set.member hu typeEnv.tePayload
            ]
    , not (null threaded)
    ]

  itemDeclNames = Map.fromList [(d.itdUnique, d.itdName) | d <- itemDecls]

  -- The constructors and selectors of a payload-carrying union, each mapped to
  -- the L4 name of the type that owns it. R4-a's first three reading forms are
  -- membership tests against this.
  payloadOwner :: Map Unique Text
  payloadOwner = Map.fromList
    [ (u, nameOf tn)
    | Declare _ (MkDeclare _ _ (MkAppForm _ tn _ _) (EnumDecl _ cds)) <- decls
    , length cds > 1
    , MkConDecl _ cn cfs <- cds
    , not (null cfs)
    , u <- getUnique cn : [getUnique fn | MkTypedName _ fn _ _ _ <- cfs]
    ]

  -- Aligned with 'decides'. Emitted BKMs take a "bkm_" id prefix (the probes'
  -- own convention); the mixed list goes through ONE 'uniquifyIn' so the two
  -- kinds cannot collide, and the differing prefixes keep every pre-Phase-5
  -- decision id byte-stable in a module with no tier-2 decides.
  decideIds =
    uniquifyIn
      [ (if isBkmDecide d then "bkm_" else "decision_") <> sanitiseId (decideName d)
      | d <- decides
      ]

  -- A nullary decision whose body is a literal is a NAMED THRESHOLD -- the thing
  -- that makes a lifted max/min worth a D-LIFTEDTHRESHOLD note.
  namedConstants = Set.fromList
    [ getUnique n
    | MkDecide _ _ (MkAppForm _ n [] _) b <- decides
    , Lit _ _ <- [carameliseExpr b]
    ]
  decideByUnique = Map.fromList (zip (map (getUnique . decideResolved) decides) decideIds)

  ------------------------------------------------------------------------
  -- Hydration (§4.4)
  ------------------------------------------------------------------------

  -- Which instances are hydrated, in a source-determined order.
  --
  -- An instance qualifies iff it is a free term or a surviving decide whose
  -- type head is a record owning computed fields, AND some surviving decide
  -- contains a foldable computed read OF THAT INSTANCE.
  --
  -- __The use gate is not an optimisation__, it is the same rule the
  -- `_optional` aliases follow and for the same reason: a base itemDefinition
  -- is inert and is therefore minted ungated, but a hydrator is a <decision>,
  -- and one with no dependents is noise in an artifact whose whole claim is
  -- that every line in it means something. It costs the Reg CF corpus eight
  -- hydrators it would otherwise mint and never read.
  --
  -- No knot: the gate is a purely syntactic scan of decide bodies, computed
  -- before 'lowered'.
  hydratedInstances :: [(Unique, Text, Unique)]   -- (instance, L4 name, owning record)
  hydratedInstances =
    nubOrdOn (\(u, _, _) -> u)
      [ (u, nm, owner)
      | (u, nm) <- instanceCandidates
      -- Phase 5: an emitted BKM is applied, not read as a record instance,
      -- and a hydrator over one would read a global that no longer exists.
      , not (Set.member u bkmCandidateSet)
      , Set.member u computedlyRead
      , Just owner <- [Map.lookup u instanceRecordOf]
      , not (null (Map.findWithDefault [] owner computedFieldsOf))
      -- ★ The lookups 'hydratorNodes' needs are checked HERE, not there, so a
      -- miss drops the instance from BOTH the graph and the FOLD. 'neHydrated'
      -- is a projection of this list, so an instance that survived here and
      -- then failed a lookup inside 'hydratorNodes' would leave downstream
      -- reads folded to `<x>_hydrated.<field>` -- a path into a decision
      -- variable nobody emitted, which FEEL answers null for. That is §4.4.5's
      -- defect shape exactly, reintroduced one level up.
      --
      -- These two cannot be spelled as the lookups themselves without a knot:
      -- 'hydratedNameOf' is derived from 'hydratedDecls', which is derived from
      -- THIS list. They are the same conditions one step earlier -- a hydrated
      -- record must have an itemDefinition, and a hydrated instance must have a
      -- defining reference for its own edge.
      , any ((== owner) . (.itdUnique)) itemDecls
      , Map.member u instanceRefOf
      ]

  -- Every read of a computed field, by the instance it reads through.
  computedlyRead :: Set Unique
  computedlyRead = Set.fromList
    [ canonUnique (getUnique x)
    | d <- decides
    , e <- toListOf (cosmosOf (gplate @(Expr Resolved))) (view decideBody d)
    , Just (x, _) <- [foldableComputedRead e]
    ]

  -- Free terms are candidates before ids exist, so this reads 'freeTerms'
  -- rather than 'inputNodes'; a record-valued DECIDE is the other kind.
  instanceCandidates :: [(Unique, Text)]
  instanceCandidates =
    freeTerms <> [(getUnique (decideResolved d), decideName d) | d <- decides]

  instanceRecordOf :: Map Unique Unique
  instanceRecordOf = Map.fromList
    ( [ (u, hu)
      | (u, _) <- freeTerms
      , Just ty <- [Map.lookup u freeTermSrc]
      , Just hu <- [typeHeadUnique ty]
      ]
        <> [ (getUnique (decideResolved d), hu)
           | d@(MkDecide _ (MkTypeSig _ _ (Just (MkGivethSig _ ty))) _ _) <- decides
           , Just hu <- [typeHeadUnique ty]
           ]
    )

  hydratorIds = assignIds "hydration_" [nm | (_, nm, _) <- hydratedInstances]

  hydratorIdByInstance :: Map Unique Text
  hydratorIdByInstance =
    let base = Map.fromList (zip [u | (u, _, _) <- hydratedInstances] hydratorIds)
    in Map.union base (aliasThrough base)

  hydratorFeelNameByInstance :: Map Unique Text
  hydratorFeelNameByInstance =
    Map.fromList (zip [u | (u, _, _) <- hydratedInstances] hydratorFeelNames)

  -- The FEEL name of the instance being hydrated -- an inputData's or a
  -- decision's, whichever it is.
  --
  -- TOTAL by construction, and the default is unreachable rather than a
  -- fallback: 'instanceCandidates' is exactly @freeTerms <> decides@, and
  -- 'neVars' is built by zipping those same two lists with their FEEL names.
  -- (An empty default would emit a context entry reading `.salary`, so if this
  -- ever becomes reachable it wants a Blocking note, not a silent name.)
  sourceFeelNameOf u = Map.findWithDefault "" u nameEnv.neVars

  ------------------------------------------------------------------------
  -- Law time (§15.2, §15.3)
  ------------------------------------------------------------------------

  -- Nullary decisions whose body folds to a DATE literal, i.e. the module's
  -- named effective dates. In the Reg CF corpus this is the four constants at
  -- regcf.l4:104,108,112,116.
  dateConstants :: Map Unique Day
  dateConstants = Map.fromList
    [ (getUnique n, day)
    | MkDecide _ _ (MkAppForm _ n [] _) b <- decides
    , Just day <- [foldDateLiteral moduleOracle (carameliseExpr b)]
    ]

  moduleOracle = MkTypeOracle
    { toTypes = typeEnv, toSubst = opts.dloSubstitution, toUri = uri }

  -- The law-time PREDICATE idiom (regcf.l4:119-121):
  --
  -- > GIVEN amendment IS A DATE
  -- > GIVETH A BOOLEAN
  -- > `the rules in force include` amendment MEANS `RULES EFFECTIVE DATE` AT LEAST amendment
  --
  -- The value is the law-time 'Resolved' found in the body, kept so the emitted
  -- column's subject is a real reference rather than a synthesised one.
  lawTimePreds :: Map Unique Resolved
  lawTimePreds = Map.fromList
    [ (getUnique f, r)
    | MkDecide _ (MkTypeSig _ (MkGivenSig _ gs) _) (MkAppForm _ f [p'] _) b <- decides
    , [MkOptionallyTypedName _ p (Just ty) _] <- [gs]
    , let (pty, _, _) = classifyType typeEnv ty
    , pty == DmnDate
    , getUnique p' == getUnique p
    , Just r <- [lawTimeComparison (getUnique p) (carameliseExpr b)]
    ]
   where
    lawTimeComparison pu = \case
      Geq _ (App _ r []) (App _ q []) | isLaw r, getUnique q == pu -> Just r
      Leq _ (App _ q []) (App _ r []) | isLaw r, getUnique q == pu -> Just r
      _ -> Nothing
    isLaw r = getUnique r == TC.rulesEffectiveDateUnique

  -- Free terms, collected across every decision first so that ids and types are
  -- assigned once, in a source-determined order.
  -- Law time is APPENDED rather than interleaved in source order (D1, §15.2).
  -- A GIVEN is written at a source position and source order is the right key
  -- for it; a builtin is written at NO source position, so its "first mention"
  -- is an accident of which decision happens to read law time first. Appending
  -- also keeps the existing inputData block byte-identical, which is what makes
  -- the binding diff reviewable.
  freeTerms :: [(Unique, Text)]
  freeTerms = ordinaryTerms <> lawTimeTerms
   where
    allTerms = nubOrdOn fst (concatMap decideFreeTerms decides <> computedTerms)

    -- §4.4. A computed field's @MEANS@ body may name a module-level term as
    -- well as the record's own fields, and that term must still become an
    -- inputData: before hydration the field WAS its own decision and did mint
    -- one, and after hydration the context entry names it just the same.
    -- APPENDED, so every pre-existing inputData keeps its id and FEEL name.
    --
    -- The synthetic `_self` parameter is excluded, and that exclusion is the
    -- whole reason this is not simply @decides <> computedSelectorDecides@:
    -- 'freeRefs' reads only a decide's BODY, so a @GIVEN@ parameter is a Ref
    -- and not a Def, and letting `_self` through would put `input_self` -- the
    -- desugaring's own scaffolding -- back into the model's input contract.
    computedTerms =
      [ t
      | d <- computedSelectorDecides
      , t <- decideFreeTerms d
      , not (Set.member (fst t) computedSelfUniques)
      ]

    isLawTime (u, _) = u == TC.rulesEffectiveDateUnique
    lawTimeTerms  = filter isLawTime allTerms
    ordinaryTerms = filter (not . isLawTime) allTerms

  decideFreeTerms d =
    -- Phase 4: the merge is applied HERE, at the source of every free-term
    -- list — a member of a merged parameter group is replaced by its
    -- canonical 'Unique', so one <inputData> is minted per group and every
    -- downstream consumer ('freeTerms', 'varFolded', 'sharedNames', the
    -- hydration instance maps) sees the canonical identity only.
    [ (canonUnique u, nameOf r)
    | r <- freeRefs d
    , let u = getUnique r
    -- Every OTHER builtin lives in `jl4:builtin` and is correctly excluded:
    -- FEEL has its own `not`, `max`, `min`, and a DMN model does not declare
    -- them. Law time is the one builtin whose VALUE the caller must supply, so
    -- it is the one builtin that is an inputData.
    , u.moduleUri == uri || u == TC.rulesEffectiveDateUnique
    , not (Map.member u decideByUnique)
    , not (Set.member u constructors)
    , not (Set.member u selectors)
    -- Phase 5 (§6.2): an emitted BKM's GIVEN binders are formalParameters,
    -- bound per-call by the invocation. They must not mint inputData.
    , not (Set.member u bkmParamSet)
    ]

  -- The emitted element id of the rule-date input, when the module reaches law
  -- time at all. Everything in D1/D2/D3 keys off this being 'Just'.
  lawTimeInputId :: Maybe Text
  lawTimeInputId = Map.lookup TC.rulesEffectiveDateUnique inputByUnique

  inputIds      = assignIds "input_" (map snd freeTerms)
  -- Merged members ALIAS their canonical element: a reference through any
  -- member 'Unique' (a body edge via 'classifyRef', a hydration read) reaches
  -- the one merged element.
  inputByUnique =
    Map.union
      (Map.fromList (zip (map fst freeTerms) inputIds))
      (aliasThrough (Map.fromList (zip (map fst freeTerms) inputIds)))

  -- member -> canonical's value, for every map keyed by instance 'Unique'.
  aliasThrough :: Map Unique a -> Map Unique a
  aliasThrough m = Map.fromList
    [ (member, v)
    | (member, canonical) <- Map.toList mergeMap
    , member /= canonical
    , Just v <- [Map.lookup canonical m]
    ]

  inputNodes =
    [ MkInputData
        { idId       = iid
        , idName     = nm
        , idFeelName = feel
        , idType     = Map.findWithDefault DmnAny u freeTermTypes
        }
    | ((u, nm), iid, feel) <- zip3 freeTerms inputIds inputFeelNames
    ]

  -- §5.2 SCOPE 1: the DRG's FEEL variable namespace -- every inputData variable
  -- and every decision variable TOGETHER, since they share one evaluation scope
  -- ("the 'variables' of standard DMN correspond to constants"). The traversal
  -- order is inputData then decision, which is the order 'drgNodes' is
  -- assembled in above, so the resolution is a function of source order alone.
  --
  -- BKM element/variable names are IN this scope, appended last -- a hard
  -- requirement, not a convenience: probe E4 (`collide-bkm-decision`) measured
  -- the two engines DISAGREEING about what a colliding document means (KIE:
  -- the BKM wins and the decision is deleted from the result, build clean;
  -- Camunda: disjoint namespaces, both right, silent), so neither engine can
  -- backstop the emitter. Two further scopes now exist as their own
  -- 'uniquifyIn' calls, per Group E's measurement: BKM `formalParameter`
  -- names, one scope per encapsulatedLogic ('bkmSignatures' below; E1/E2/E7:
  -- a parameter shadows same-named inputData and decisions, and parameters do
  -- not collide across BKMs), and `decisionService` names (§2.3, their own
  -- scope, arriving with the service emitter).
  -- Hydrator names are APPENDED after the decisions, and BKM names after the
  -- hydrators, for the same reason law time's inputData is (§15.2): appending
  -- keeps every existing FEEL name byte-stable, so the diff shows only the
  -- new element kind.
  varFolded =
    map (feelIdentText . snd) freeTerms
      <> map (feelIdentText . decideName) plainDecides
      <> [feelIdentText (nm <> " hydrated") | (_, nm, _) <- hydratedInstances]
      <> map (feelIdentText . decideName) bkmDecides
  varResolved = uniquifyIn varFolded
  (inputFeelNames, varRest) = splitAt (length freeTerms) varResolved
  (plainDecideFeelNames, varRest2) = splitAt (length plainDecides) varRest
  (hydratorFeelNames, bkmFeelNames) = splitAt (length hydratedInstances) varRest2

  -- Every decide's resolved FEEL name, whichever segment it came from.
  feelNameByDecideU :: Map Unique Text
  feelNameByDecideU = Map.fromList
    ( zip (map (getUnique . decideResolved) plainDecides) plainDecideFeelNames
        <> zip (map (getUnique . decideResolved) bkmDecides) bkmFeelNames
    )

  -- Aligned with 'decides', as every zip3 consumer below expects.
  decideFeelNames =
    [ Map.findWithDefault (feelIdentText (decideName d)) (getUnique (decideResolved d)) feelNameByDecideU
    | d <- decides
    ]

  -- The variable namespace WITHOUT the BKM parameter entries. Named so that
  -- 'closureFeelName' can read it: reading the finished 'neVars' there would
  -- tie a strict knot (neVars ← bkmParamNames ← bkmSignatures ←
  -- closureFeelName ← neVars), and a closure member is a global, never a
  -- parameter, so the base map is also the RIGHT map.
  baseVarNames :: Map Unique Text
  baseVarNames =
    let base = Map.fromList
          ( zip (map fst freeTerms) inputFeelNames
              <> Map.toList feelNameByDecideU
          )
    -- a body reference through a merged MEMBER binder renders the
    -- canonical (shared) FEEL name
    in Map.union base (aliasThrough base)

  nameEnv = MkNameEnv
    { neVars   = Map.union baseVarNames bkmParamNames
    , neFields = fieldNames
    , neMaybePreds = opts.dloMaybePredicates
    , neHydrated   = Map.union hydratorFeelNameByInstance (aliasThrough hydratorFeelNameByInstance)
    , neBareProj   = Set.empty
    , neUnlifted   = unliftedSet
    , neComputedFields =
        Set.fromList (map (getUnique . decideResolved) computedSelectorDecides)
    , neBkms       = bkmCallInfos
    , neBkmParams  = bkmParamSet
    , neServiceCalls = svcCallInfos
    , neRecordCtors = recordCtorFields
    , neComputedInline = selfContainedSelectors
    }

  -- RECORD constructors only — see 'neRecordCtors'. An enum's constructors
  -- (payload-carrying or not) are deliberately absent.
  recordCtorFields :: Map Unique [Unique]
  recordCtorFields = Map.fromList
    [ (getUnique cn, [getUnique n | MkTypedName _ n _ _ _ <- fs])
    | Declare _ (MkDeclare _ _ _ (RecordDecl _ mn fs)) <- decls
    , cn <- maybeToList mn
    ]

  ------------------------------------------------------------------------
  -- Phase 5: BKM signatures — parameter scopes and the λ-lifted closure (§6.2)
  ------------------------------------------------------------------------

  -- What a BKM body may reference beyond its own parameters, measured on both
  -- engines (§6.2, 2026-08-01): NOTHING that is not passed. A decision
  -- variable read from inside an encapsulatedLogic is a KIE whole-model
  -- compile error and a silent Camunda null (probe E3); an unshadowed
  -- inputData read is a KIE compile error while Camunda ANSWERS (the engines
  -- disagree, so neither spelling-by-omission is portable). The lift is the
  -- classical λ-lift: each module-level free reference of the body becomes an
  -- extra formalParameter named EXACTLY as the global it lifts — a parameter
  -- shadows the same-named global on both engines (E1/E7), so the body text
  -- is unchanged — and every call site supplies it as `name: name`.
  --
  -- The closure is TRANSITIVE through BKM→BKM calls (measured: the threaded
  -- shape passes both engines): if g calls h and h lifts `n`, then g lifts
  -- `n` too, so g's own body can supply `n: n` from its parameter scope.
  bkmEnvRefs :: Map Unique (Set ClosureRef, Set Unique)
  bkmEnvRefs = Map.fromList
    [ (u, (Set.fromList (envRefs <> hydraRefs), Set.fromList callees))
    | d <- bkmDecides
    , let u = getUnique (decideResolved d)
    , let params = Set.fromList (map (getUnique . fst) (A.decideParams d))
    , let (survivors, touched) = survivingRefs [view decideBody d]
    , let classified =
            [ cls
            | r <- survivors
            , let ru = getUnique r
            , not (Set.member ru params)
            , not (Set.member ru computedSelfUniques)
            , Just cls <-
                [ if Set.member ru bkmCandidateSet
                    then Just (Right ru)
                    else if Map.member ru decideByUnique
                      then Just (Left (EnvDirect ru))
                      else if Map.member ru inputByUnique
                        then Just (Left (EnvDirect (canonUnique ru)))
                        else Nothing
                ]
            ]
    , let envRefs  = [c | Left c  <- classified]
    , let callees  = [c | Right c <- classified]
    , let hydraRefs =
            [ EnvHydrator (canonUnique t)
            | t <- touched
            , not (Set.member t params)
            , Map.member t hydratorIdByInstance
            ]
    ]

  -- Least fixpoint of closure(b) = env(b) ∪ ⋃ closure(callees b). Monotone
  -- and bounded by the module's element count, so the iteration terminates
  -- even on a (refused, D-RECURSIVE) cyclic BKM graph.
  bkmClosure :: Map Unique (Set ClosureRef)
  bkmClosure = go (Map.map fst bkmEnvRefs)
   where
    go m =
      let m' = Map.mapWithKey step m
          step u env =
            Set.unions
              ( env
                  : [ Map.findWithDefault Set.empty k m
                    | k <- Set.toList (maybe Set.empty snd (Map.lookup u bkmEnvRefs))
                    ]
              )
      in if m' == m then m else go m'

  closureFeelName :: ClosureRef -> Text
  closureFeelName = \case
    EnvDirect u   -> Map.findWithDefault "" u baseVarNames
    EnvHydrator u -> Map.findWithDefault "" u hydratorFeelNameByInstance

  closureDmnType :: ClosureRef -> DmnType
  closureDmnType = \case
    EnvDirect u
      | Just t <- Map.lookup u freeTermTypes     -> t
      | Just t <- Map.lookup u decideGivethTypes -> t
      | otherwise                                -> DmnAny
    EnvHydrator u -> Map.findWithDefault DmnAny u hydratorTypeByInstance

  closureEdge :: ClosureRef -> Maybe Requirement
  closureEdge = \case
    EnvDirect u -> case Map.lookup u decideByUnique of
      Just t  -> Just (RequiredDecision t)
      Nothing -> RequiredInput <$> Map.lookup u inputByUnique
    EnvHydrator u -> RequiredDecision <$> Map.lookup u hydratorIdByInstance

  decideGivethTypes :: Map Unique DmnType
  decideGivethTypes = Map.fromList
    [ (getUnique (decideResolved d), t)
    | d@(MkDecide _ (MkTypeSig _ _ (Just (MkGivethSig _ ty))) _ _) <- decides
    , let (t, _, _) = classifyType typeEnv ty
    ]

  -- Independent of 'hydratorNodes', deliberately: 'neBkms' needs the type and
  -- reading it off the node list would thread a lazy knot through renderFeelIn.
  hydratorTypeByInstance :: Map Unique DmnType
  hydratorTypeByInstance = Map.fromList
    [ (u, DmnNamed hnm DmnAny)
    | (u, _, owner) <- hydratedInstances
    , Just hnm <- [Map.lookup owner hydratedNameOf]
    ]

  -- One 'uniquifyIn' scope PER encapsulatedLogic (§5.2 scope 4, measured by
  -- E1/E2/E7). The closure names go through it FIRST so each keeps the exact
  -- spelling of the global it lifts (globals are already injective under
  -- scope 1); a GIVEN whose fold collides with a lifted global is the one
  -- that gets the suffix — its body references resolve through 'neVars' to
  -- the suffixed name, so declaration and reference cannot disagree.
  bkmSignatures :: Map Unique ([(Unique, Text, Text, DmnType)], [(ClosureRef, Text, DmnType)])
  bkmSignatures = Map.fromList
    [ (u, (givens, closures))
    | d <- bkmDecides
    , let u = getUnique (decideResolved d)
    , let givenPs = A.decideParams d
    , let closureRefs =
            sortOn closureFeelName (Set.toList (Map.findWithDefault Set.empty u bkmClosure))
    , let closureNames = map closureFeelName closureRefs
    , let resolved = uniquifyIn (closureNames <> map (feelIdentText . nameOf . fst) givenPs)
    , let (closResolved, givenResolved) = splitAt (length closureNames) resolved
    , let givens =
            [ (getUnique p, nameOf p, gn, Map.findWithDefault DmnAny (getUnique p) freeTermTypes)
            | ((p, _), gn) <- zip givenPs givenResolved
            ]
    , let closures =
            [ (cr, cn, closureDmnType cr)
            | (cr, cn) <- zip closureRefs closResolved
            ]
    ]

  -- Body references to a GIVEN of an emitted BKM render by its resolved
  -- formalParameter name. Keyed by binder 'Unique', so the entries are
  -- per-BKM by construction even though they live in the one shared map.
  bkmParamNames :: Map Unique Text
  bkmParamNames = Map.fromList
    [ (pu, gn)
    | (givens, _) <- Map.elems bkmSignatures
    , (pu, _, gn, _) <- givens
    ]

  bkmCallInfos :: Map Unique BkmCallInfo
  bkmCallInfos = Map.fromList
    [ ( u
      , MkBkmCallInfo
          { bciFeelName = Map.findWithDefault "" u feelNameByDecideU
          , bciParams   = [gn | (_, _, gn, _) <- givens]
          , bciClosure  = [cn | (_, cn, _) <- closures]
          }
      )
    | (u, (givens, closures)) <- Map.toList bkmSignatures
    ]

  ------------------------------------------------------------------------
  -- Phase 5: one decisionService per § (§2.3), the splitter (§2.3.2), and
  -- the flavor bit (§13.5)
  ------------------------------------------------------------------------

  -- Every NAMED section with its kept, non-BKM member decides — each decide
  -- assigned to its INNERMOST named §. 'topDecls' flattens the tree, so this
  -- walks the module itself; the walk is the only consumer of the nesting.
  --
  -- The walk collects EVERY decide and the kept/dropped filters are applied
  -- outside, because D-SVCEMPTY's first arm needs to see a § whose entire
  -- membership was rule-date-rebind-dropped (§15.12) — a § the kept-only
  -- table would render indistinguishable from one that never held a decide.
  sectionTable :: [(Text, [Unique])]
  sectionTable =
    [ ( nm
      , [ u
        | (c, u) <- sectionAssigns
        , c == i
        , Map.member u decideByUnique
        , not (Set.member u bkmCandidateSet)
        ]
      )
    | (i, nm) <- sectionNames
    ]

  -- Aligned with 'sectionTable': the same §s, membership = rebind-dropped.
  sectionRebindDropped :: [(Text, [Unique])]
  sectionRebindDropped =
    [ (nm, [u | (c, u) <- sectionAssigns, c == i, Set.member u rebindDroppedSet])
    | (i, nm) <- sectionNames
    ]

  rebindDroppedSet :: Set Unique
  rebindDroppedSet = Set.fromList
    [u | (u, A.DroppedRuleDateRebind) <- Map.toList popVerdict.pvDropped]

  sectionAssigns :: [(Int, Unique)]
  sectionNames   :: [(Int, Text)]
  (sectionAssigns, sectionNames) = (assigns, secs)
   where
    MkModule _ _ topSec = modul
    (assigns, secs, _) = goSec Nothing (0 :: Int) topSec
    goSec cur idx (MkSection _ mName _ ds) =
      let (cur', idx', secs0) = case mName of
            Just n  -> (Just idx, idx + 1, [(idx, nameOf n)])
            Nothing -> (cur, idx, [])
          step (as, ss, i) dcl = case dcl of
            Section _ sub ->
              let (as2, ss2, i2) = goSec cur' i sub
              in (as <> as2, ss <> ss2, i2)
            Decide _ dd ->
              let u = getUnique (decideResolved dd)
              in (as <> [(c, u) | Just c <- [cur']], ss, i)
            _ -> (as, ss, i)
      in foldl' step ([], secs0, idx') ds

  -- The SYNTACTIC decision→decision reference approximation the service
  -- structure is computed over. Deliberately NOT the emitted edges: the
  -- emitted `dcnRequirements` force each decision's rendered logic (strict
  -- fields), and the render reads 'neServiceCalls', which needs the service
  -- structure — a strict knot. Raw 'freeRefs' is a SUPERSET of the emitted
  -- edges (dated chains and hydration only remove or redirect), and a
  -- superset is safe here: an extra edge can cause an extra split (Advisory)
  -- but never hide a cycle, and 'checkDrg''s §6.3.10 pass asserts the final
  -- artifact regardless.
  decideReqUniques :: Map Unique (Set Unique)
  decideReqUniques = Map.fromList
    [ ( u
      , Set.fromList
          [ ru
          | r <- freeRefs d
          , let ru = getUnique r
          , ru /= u
          , Map.member ru decideByUnique
          , not (Set.member ru bkmCandidateSet)
          ]
      )
    | d <- decides
    , let u = getUnique (decideResolved d)
    ]

  -- The §2.3.2 splitter, run to FIXPOINT over 'cyclicGroups' — the same
  -- routine as every other acyclicity question (§6.4.4). A section whose
  -- grouping closes a service-level cycle is split into per-decision
  -- services; a SINGLETON that still cycles holds a genuine decision-level
  -- cycle (already D-CYCLE) and is DROPPED rather than re-split, which is
  -- what makes the iteration terminate on any input.
  -- Each struct: (original § name if this is a split fragment, service name,
  -- members).
  finalServiceStructs :: [(Maybe Text, Text, [Unique])]
  svcSplitEvents      :: [(Text, [Text])]   -- (§ name, fragment names)
  svcDroppedCycles    :: [Text]             -- service names dropped as genuine cycles
  (finalServiceStructs, svcSplitEvents, svcDroppedCycles) =
    goSplit [(Nothing, nm, us) | (nm, us) <- sectionTable, not (null us)] [] []
   where
    goSplit svcs splits dropped =
      let keyed = zip [0 :: Int ..] svcs
          memberSvc = Map.fromList [(u, i) | (i, (_, _, us)) <- keyed, u <- us]
          edgesOf i us = nubOrd
            [ j
            | u <- us
            , t <- Set.toList (Map.findWithDefault Set.empty u decideReqUniques)
            , Just j <- [Map.lookup t memberSvc]
            , j /= i
            ]
          cycSet = Set.fromList
            (concat (cyclicGroups [(i, i, edgesOf i us) | (i, (_, _, us)) <- keyed]))
      in if Set.null cycSet
           then (svcs, splits, dropped)
           else
             let splitOne (i, s@(orig, nm, us))
                   | not (Set.member i cycSet) = ([s], [], [])
                   | [_] <- us = ([], [], [nm])
                   | otherwise =
                       let frags =
                             [ ( Just (fromMaybe nm orig)
                               , nm <> " — " <> decideNameByUnique u
                               , [u]
                               )
                             | u <- us
                             ]
                       in (frags, [(fromMaybe nm orig, [n | (_, n, _) <- frags])], [])
                 parts = map splitOne keyed
             in goSplit
                  (concatMap (\(a, _, _) -> a) parts)
                  (splits <> concatMap (\(_, b, _) -> b) parts)
                  (dropped <> concatMap (\(_, _, c) -> c) parts)

  decideNameByUnique :: Unique -> Text
  decideNameByUnique u =
    Map.findWithDefault "" u
      (Map.fromList [(getUnique (decideResolved d), decideName d) | d <- decides])

  -- §5.2 SCOPE 3: decisionService names are their OWN uniquifyIn scope —
  -- measured, not assumed (E6: two same-named services both resolve to the
  -- FIRST, silently; E5: a service sharing a DECISION's name is
  -- validator-only with zero runtime effect, so services do not uniquify
  -- against decisions).
  svcFeelNames = uniquifyIn (map (\(_, nm, _) -> feelIdentText nm) finalServiceStructs)
  svcIds       = assignIds "service_" (map (\(_, nm, _) -> nm) finalServiceStructs)

  -- §13.5 row 6: which decides are §-INVOCABLE — the narrow measured shape.
  -- A kept, parameterised, NOT-un-lifted, NOT-BKM decide (the safety-refused
  -- verbatim population) that is the SOLE output of its service, whose
  -- service has encapsulated members, no cross-service decision inputs, and
  -- whose service inputData are EXACTLY the decide's own GIVEN params. Under
  -- those conditions `svc(p: e, …)` computes the decide with its inputs bound
  -- per call, which is what the L4 call means.
  svcInvocable :: Map Unique Int
  svcInvocable = Map.fromList
    [ (uf, i)
    | (i, (_, _, us)) <- zip [0 :: Int ..] finalServiceStructs
    , let memberSet = Set.fromList us
    , let requiredByMembers =
            Set.unions [Map.findWithDefault Set.empty m decideReqUniques | m <- us]
    , let outputs = [m | m <- us, not (Set.member m requiredByMembers)]
    , [uf] <- [outputs]
    , length us > 1   -- §6.3.10: encapsulated members must exist
    , Just d <- [listToMaybe [d' | d' <- decides, getUnique (decideResolved d') == uf]]
    , let ps = A.decideParams d
    , not (null ps)
    , not (Set.member uf unliftedSet)
    , not (Set.member uf bkmCandidateSet)
    -- every decision reference of every member stays inside the service
    , Set.isSubsetOf requiredByMembers memberSet
    -- the members' input references are exactly the callee's params
    , let inputRefs = Set.fromList
            [ canonUnique ru
            | m <- us
            , d' <- decides
            , getUnique (decideResolved d') == m
            , r <- freeRefs d'
            , let ru = getUnique r
            , Map.member ru inputByUnique
            ]
    , inputRefs == Set.fromList (map (getUnique . fst) ps)
    ]

  -- The invocation map the renderer reads — populated on `kie` ONLY.
  svcCallInfos :: Map Unique SvcCallInfo
  svcCallInfos
    | opts.dloFlavor /= FlavorKie = Map.empty
    | otherwise = Map.fromList
        [ ( uf
          , MkSvcCallInfo
              { sciFeelName = svcFeelNames !! i
              , sciParams =
                  [ Map.findWithDefault "" (getUnique p) baseVarNames
                  | Just d <- [listToMaybe [d' | d' <- decides, getUnique (decideResolved d') == uf]]
                  , (p, _) <- A.decideParams d
                  ]
              }
          )
        | (uf, i) <- Map.toList svcInvocable
        ]

  -- decision id → service id, for 'finishCaller' (kie only): the caller's
  -- info edge onto the callee decision is REPLACED by the knowledgeRequirement
  -- onto the service — an info requirement would make the (uncompilable,
  -- safety-refused) callee a hard dependency of the caller on KIE.
  svcEdgeByDecisionId :: Map Text Text
  svcEdgeByDecisionId
    | opts.dloFlavor /= FlavorKie = Map.empty
    | otherwise = Map.fromList
        [ (did, svcIds !! i)
        | (uf, i) <- Map.toList svcInvocable
        , Just did <- [Map.lookup uf decideByUnique]
        ]

  -- The final service NODES, assembled from the FINISHED decisions so the
  -- emitted member lists agree with the emitted edges (lazy — nothing on the
  -- render path reads these). A struct that fails the D5/§6.3.10 guards is
  -- returned 'Left' so D-SVCEMPTY can say so — the skip used to be silent.
  serviceStructResults :: [Either (Text, Int, Int, Int) DrgNode]
  serviceStructResults =
    [ -- probe D5: a service with no outputDecision is a KIE runtime throw and
      -- a Camunda silence; §6.3.10: at least one of encapsulated /
      -- inputDecisions SHALL be present. A § that cannot satisfy both emits
      -- no service — loudly, via D-SVCEMPTY's second arm.
      if null outputs || (null encapsulated && null inputDecisions)
        then Left (nm, length outputs, length encapsulated, length inputDecisions)
        else Right $ NodeService MkDecisionService
          { dsvId             = sid
          , dsvName           = nm
          , dsvFeelName       = feel
          , dsvType           = case outputs of
              [o] -> maybe DmnAny (.dcnType) (Map.lookup o finishedById)
              _   -> DmnAny
          , dsvOutputs        = outputs
          , dsvEncapsulated   = encapsulated
          , dsvInputDecisions = inputDecisions
          , dsvInputData      = inputDataIds
          }
    | ((_, nm, us), feel, sid) <- zip3 finalServiceStructs svcFeelNames svcIds
    , let declaredIds = [did | u <- us, Just did <- [Map.lookup u decideByUnique]]
    , let declaredSet = Set.fromList declaredIds
    -- A HYDRATOR whose readers all live in this § joins the service as an
    -- encapsulated member — it is scaffolding of those readers, and leaving
    -- it outside makes it an inputDecision that KIE's evaluateDecisionService
    -- then wants precomputed in the invocation context, warning
    -- "Required input '<hydrator>' not found ... invoking using null"
    -- (measured on the bkm exhibit). Cross-§ readers leave it outside.
    , let absorbedHydrators =
            [ hid
            | NodeDecision h <- finishedDecisionNodes
            , let hid = h.dcnId
            , Text.isPrefixOf "hydration_" hid
            , let readers =
                    [ dec.dcnId
                    | NodeDecision dec <- finishedDecisionNodes
                    , RequiredDecision hid `elem` dec.dcnRequirements
                    ]
            , not (null readers)
            , all (`Set.member` declaredSet) readers
            ]
    , let memberIds = declaredIds <> absorbedHydrators
    , let memberSet = Set.fromList memberIds
    , let memberDecs = [dec | m <- memberIds, Just dec <- [Map.lookup m finishedById]]
    , let requiredByMembers = Set.fromList
            [t | dec <- memberDecs, RequiredDecision t <- dec.dcnRequirements]
    , let outputs      = [m | m <- memberIds, not (Set.member m requiredByMembers)]
    , let encapsulated = [m | m <- memberIds, Set.member m requiredByMembers]
    , let inputDecisions = nubOrd
            [ t
            | dec <- memberDecs
            , RequiredDecision t <- dec.dcnRequirements
            , not (Set.member t memberSet)
            ]
    , let inputDataIds = nubOrd
            [t | dec <- memberDecs, RequiredInput t <- dec.dcnRequirements]
    ]

  serviceNodes :: [DrgNode]
  serviceNodes = [n | Right n <- serviceStructResults]

  -- (§ name, #outputs, #encapsulated, #inputDecisions) of every guard-failing
  -- struct, for D-SVCEMPTY's second arm.
  svcEmptySkips :: [(Text, Int, Int, Int)]
  svcEmptySkips = [x | Left x <- serviceStructResults]

  finishedById :: Map Text Decision
  finishedById = Map.fromList
    [(dec.dcnId, dec) | NodeDecision dec <- finishedDecisionNodes]

  -- D-SVCSPLIT (Advisory): the artifact departs from the source's sectioning
  -- (§2.3.2 — the split is OUR granularity repair, semantics-preserving,
  -- which is exactly why it is performed rather than reported-and-refused;
  -- contrast §6.4.4-4 on decision-level cycles). D-FLAVOR-NOSERVICE: §13.5's
  -- two ruled arms.
  serviceNotes :: [FidelityNote]
  serviceNotes =
    [ dmnNote "D-SVCSPLIT" Advisory (feelIdentText orig) Nothing
        ("the section `" <> orig <> "` would close a service-level requirement cycle \
          \(DMN 1.3 §6.3.10) as one decisionService, so it is emitted as "
           <> tshow (length frags) <> " finer service(s): "
           <> Text.intercalate ", " (map tick frags)
           <> ". Section granularity can manufacture a cycle decisions do not have; \
              \splitting until acyclic preserves every decision and every edge")
        "the source's own sectioning: the artifact's service boundaries are finer than \
        \the module's § boundaries"
    | (orig, frags) <- svcSplitEvents
    ]
      <> [ dmnNote "D-SVCSPLIT" Advisory (feelIdentText nm) Nothing
             ("the section `" <> nm <> "` holds a genuine decision-level requirement \
               \cycle, which no service granularity can repair, so NO decisionService is \
               \emitted for it (its members and their D-CYCLE note are unaffected)")
             "the § as an invocable or grouping unit"
         | nm <- svcDroppedCycles
         ]
      <> [ dmnNote "D-FLAVOR-NOSERVICE" Blocking callerId Nothing
             ("`" <> callerName <> "` applies `" <> decideNameByUnique uf
                <> "`, which is §-invocable — on the `kie` flavor this call renders as \
                   \a FEEL invocation of the decisionService `" <> (svcFeelNames !! i)
                <> "` — but the `camunda` flavor never emits the \
                   \knowledgeRequirement→decisionService edge that invocation needs \
                   \(it is fatal to Camunda 8's parse(), §13.4), so the call site stays \
                   \raw L4")
             "the invocation on this flavor: route the callee to a BKM (make it \
             \DMN-SAFE) or evaluate on the kie flavor"
         | opts.dloFlavor == FlavorCamunda
         , (uf, i) <- Map.toList svcInvocable
         , (callerId, callerName) <- qualifyingCallers uf
         ]
      <> [ dmnNote "D-FLAVOR-NOSERVICE" Advisory sid Nothing
             ("the decisionService `" <> feel <> "` (§ `" <> nm <> "`) is emitted as \
               \GROUPING only: no call site invokes it"
                <> (if opts.dloFlavor == FlavorKie
                      then ""
                      else ", and on this flavor none could — the `camunda` flavor \
                           \never emits the knowledgeRequirement→decisionService edge \
                           \an invocation needs (§13.4/§13.5)"))
             "nothing: an uninvoked grouping service is inert on both engines (probe D1)"
         | ((_, nm, _), feel, sid, i) <-
             zip4 finalServiceStructs svcFeelNames svcIds [0 :: Int ..]
         -- only services that actually EMIT (the D5/§6.3.10 skips filter some
         -- structs out); a note naming an element id the artifact does not
         -- contain would be describing a different file
         , Set.member sid emittedServiceIds
         , i `notElem`
             [ j | (uf, j) <- Map.toList svcInvocable, not (null (qualifyingCallers uf)) ]
         ]
      -- D-SVCEMPTY (§15.12's companion): one code, one severity, two message
      -- forms (D-FIXTURE's precedent). Advisory, and the Advisory ⟹ Faithful
      -- argument is discharged in FIDELITY-SEVERITY-AXIS-SPEC.md §5.2: the
      -- per-decision loss is already carried (Lossy) by D-RULEDATE-UNBOUND,
      -- and a service shell is grouping metadata (D-FLAVOR-NOSERVICE's
      -- grouping-arm precedent). Elements are named by the §'s FEEL-folded
      -- name, never by a service id the artifact does not contain.
      --
      -- Arm (i): a § whose ENTIRE decide membership was rebind-dropped. The
      -- kept-only section table renders such a § indistinguishable from one
      -- that never held a decide, which is exactly the silence this arm ends.
      <> [ dmnNote "D-SVCEMPTY" Advisory (feelIdentText nm) Nothing
             ("the section `" <> nm <> "` has no emitted member decisions: its "
                <> englishCount (length droppedUs) <> " member decide(s) "
                <> Text.intercalate ", " (map (tick . droppedNameOf) droppedUs)
                <> " were all dropped as rule-date-rebinding (D-RULEDATE-UNBOUND, \
                   \§15.12), so no decisionService is emitted for it")
             "nothing an engine needs: the grouping shell had no members left to group; \
             \the members' own loss is carried by their D-RULEDATE-UNBOUND notes"
         | ((nm, kept), (_, droppedUs)) <- zip sectionTable sectionRebindDropped
         , null kept
         , not (null droppedUs)
         ]
      -- Arm (ii): a struct with kept members that cannot satisfy §6.3.10's
      -- decisionService shape. This skip existed before and was silent; the
      -- note is new, the behaviour is not.
      <> [ dmnNote "D-SVCEMPTY" Advisory (feelIdentText nm) Nothing
             ("the section `" <> nm <> "` cannot satisfy DMN 1.3 §6.3.10's \
              \decisionService shape — at least one output decision, and at least one \
              \encapsulated member or input decision; this one has " <> shapeText
                <> " — so no decisionService is emitted for it (probe D5: a service \
                   \with no outputDecision is a KIE runtime throw and a Camunda silence)")
             "the § as a grouping unit: its member decisions are all emitted; only the \
             \service shell is not"
         | (nm, nOut, _nEnc, _nInp) <- svcEmptySkips
         , let shapeText
                 | nOut == 0 = "no output decision"
                 | otherwise =
                     tshow nOut <> " output(s) but no encapsulated member and no \
                     \input decision"
         ]

  emittedServiceIds :: Set Text
  emittedServiceIds = Set.fromList [s.dsvId | NodeService s <- serviceNodes]

  -- The call sites that MEET the §-invocation condition, per callee: applied,
  -- arity-matching, from an emitted caller. Flavor-independent — on kie they
  -- render, on camunda they draw the Blocking arm.
  qualifyingCallers :: Unique -> [(Text, Text)]
  qualifyingCallers uf = nubOrd
    [ (callerId, decideNameByUnique c)
    | Just d <- [listToMaybe [d' | d' <- decides, getUnique (decideResolved d') == uf]]
    , let arity = length (A.decideParams d)
    , s <- Map.findWithDefault [] uf callGraph.cgCalls
    , s.csApplied
    , length s.csArgs == arity
    , Just c <- [s.csCaller]
    , Just callerId <- [Map.lookup c decideByUnique]
    ]

  -- §4.4 × §6.2: computed selectors whose bodies reference nothing beyond the
  -- record's own `_self` — the only ones safe to inline at a BKM parameter
  -- receiver (anything wider would smuggle environment references past the
  -- closure computation; anything nested would recurse through another
  -- selector). Everything else falls to verbatim, Blocking-noted as today.
  selfContainedSelectors :: Map Unique (Unique, Expr Resolved)
  selfContainedSelectors = Map.fromList
    [ (getUnique (decideResolved d), (getUnique self, prepared))
    | d <- computedSelectorDecides
    , Just (_, self, _) <- [computedSelectorOwner d]
    , let prepared = hydratorBody (view decideBody d)
    , let (survivors, touchedS) = survivingRefs [prepared]
    , all (\r -> Set.member (getUnique r) computedSelfUniques) survivors
    , null touchedS
    ]

  -- A GIVEN's declared type is the best evidence about a free term; an ASSUME's
  -- is the other source. Anything else stays Any.
  freeTermSrc :: Map Unique (Type' Resolved)
  freeTermSrc = Map.fromList
    ( -- Law time's declared type is the builtin's own: `date`
      -- ("L4.TypeCheck.Environment":264-265). Putting it HERE rather than
      -- post-patching 'freeTermTypes' is what keeps the type and the two note
      -- families ('inputMaybeNotes', 'sharedInputNotes') in one place.
      [ (TC.rulesEffectiveDateUnique, TC.rulesEffectiveDateBuiltin)
      | isJust lawTimeInputId
      ]
        <> [ (getUnique n, ty)
           | MkDecide _ (MkTypeSig _ (MkGivenSig _ gs) _) _ _ <- decides
           , MkOptionallyTypedName _ n (Just ty) _ <- gs
           ]
        <> [ (getUnique n, ty)
           | MkAssume _ _ (MkAppForm _ n _ _) (Just ty) _ <- assumes
           ]
    )

  freeTermTypes = Map.map (\ty -> let (t, _, _) = classifyType typeEnv ty in t) freeTermSrc

  -- R8-a at the inputData site.
  inputMaybeNotes =
    [ maybeNullNote iid Nothing ("the input `" <> nm <> "`")
        (oneLine (prettyLayout ty)) fl.tfOptionalAlias
    | ((u, nm), iid) <- zip freeTerms inputIds
    , Just ty <- [Map.lookup u freeTermSrc]
    , let (_, _, fl) = classifyType typeEnv ty
    , fl.tfMaybe
    ]

  -- TWO DIFFERENT free terms that spell the same FEEL name. L4 scopes a GIVEN
  -- to its own decision, so `n` in one rule and `n` in another are unrelated;
  -- DMN's variables are 0-ary functions with no scope at all ("the 'variables'
  -- of standard DMN correspond to constants", Vandevelde et al. on cDMN), so the
  -- emitted model has two inputData elements a FEEL expression cannot tell
  -- apart. Note that the same term used by two decisions is NOT this, and does
  -- not warn.
  -- The counts are computed, not spelled. They used to read "two ... two"
  -- unconditionally under a guard of @length us > 1@, which understated the
  -- Reg CF corpus's eight-way collision on `issuer` as a two-way one.
  --
  -- __The message changed when @uniquifyIn@ landed, and it had to.__ It used to
  -- end "...so the emitted model has eight elements a FEEL expression cannot
  -- tell apart". After §5.2 stage 2 that sentence is FALSE: the elements are
  -- renamed apart, and every reference reaches the one it means. The loss that
  -- SURVIVES is the one this note was always about and never said plainly --
  -- L4 scoped N parameters locally, one per decision, and DMN has N globals, so
  -- a caller must now supply eight values where the L4 has one name used eight
  -- times. The note also names both the L4 spellings and the resolved FEEL
  -- names, per §5.3.6: under the fold the folded name is precisely what a
  -- reader cannot invert.
  --
  -- The PREDICATE is unchanged, deliberately. §7's header warns that it is the
  -- tree's only detector of duplicate `inputData/@name` (TP=185/FP=0/FN=0), and
  -- the type-conflict repurpose it proposes is Phase 4 work that must ADD a
  -- code rather than take this one over.
  sharedInputNotes =
    [ dmnNote "D-SCOPE" Lossy ("input_" <> sanitiseId nm) Nothing
        (englishCount (length us) <> " different terms fold to the FEEL name `"
           <> nm <> "` (L4: " <> Text.intercalate ", " (map tick l4spellings)
           <> "; used in " <> Text.intercalate ", " users
           <> "); they are emitted as the distinct globals "
           <> Text.intercalate ", " (map tick feelSpellings)
           <> ", because DMN's inputData is global and has no scope at all")
        -- The lost: text branches on WHAT collided (§7): "L4's lexical
        -- scoping of GIVEN parameters" is false when two global ASSUMEs
        -- collide — an ASSUME has module scope, and what is lost there is the
        -- distinct identity of two same-named globals, not any local scoping.
        ( if all (`Set.member` assumeUniques) us
            then
              "the distinct identities of same-named global ASSUMEs: the collision is \
              \between module-scoped terms, and a caller must supply one value per element"
            else
              "L4's lexical scoping of GIVEN parameters: a caller must now supply one value per \
              \element where the L4 has one locally-scoped name"
        )
    | (nm, us) <- Map.toAscList sharedNames
    , length us > 1
    , let users = nubOrd [decideName d | d <- decides, any ((`elem` us) . fst) (decideFreeTerms d)]
    , let l4spellings = nubOrd [tnm | (u, tnm) <- freeTerms, u `elem` us]
    , let feelSpellings =
            [ feel | (feel, (u, _)) <- zip inputFeelNames freeTerms, u `elem` us ]
    ]

  assumeUniques :: Set Unique
  assumeUniques = Set.fromList
    [getUnique n | MkAssume _ _ (MkAppForm _ n _ _) _ _ <- assumes]

  ------------------------------------------------------------------------
  -- Phase 4 notes: the population filter, the merge, and D-PARTIAL
  ------------------------------------------------------------------------

  phase4Notes :: [FidelityNote]
  phase4Notes =
    populationNotes <> paramTypeNotes <> paramAsInputNotes
      <> partialNotes <> bkmNotes <> bkmConsumerNotes

  allDecideByUnique :: Map Unique (Decide Resolved)
  allDecideByUnique =
    Map.fromList [(getUnique (decideResolved d), d) | d <- allDecides]

  droppedNameOf u = maybe "?" decideName (Map.lookup u allDecideByUnique)
  droppedRangeOf u =
    Map.lookup u allDecideByUnique >>= \d -> (getAnno d).range

  -- D-FIXTURE / D-REGULATIVE: a drop is NEVER silent — the filter is a
  -- measurement about four corpora, not a soundness property (§2.5.8), and
  -- the note is how a reader finds out that adding a test changed the model.
  populationNotes =
    [ case reason of
        A.DroppedFixture ->
          dmnNote "D-FIXTURE" Advisory nm rng
            ("`" <> nm <> "` is test scaffolding (referenced only from directive argument \
             \positions, with no callers in this module or its importers), so it is not \
             \emitted; pass --include-tests to emit it")
            "nothing about the rule set: the decision exists to exercise it, not to state it"
        A.DroppedFixtureHelper ->
          dmnNote "D-FIXTURE" Advisory nm rng
            ("`" <> nm <> "` is referenced only from test scaffolding (the fixture-side \
             \transitive closure), so it is not emitted; pass --include-tests to emit it")
            "nothing about the rule set: the decision exists to exercise it, not to state it"
        A.DroppedRegulative ->
          dmnNote "D-REGULATIVE" Lossy nm rng
            ("`" <> nm <> "` has a regulative body and no callers, so it is not emitted as a \
             \decision: DMN models decisions; lifecycle is BPMN's and CMMN's job, and a \
             \<decision> whose logic is raw deontic L4 misdescribes both")
            "the obligation's lifecycle: route this rule to the BPMN exporter instead"
        -- R12 (§15.12): same code as the old lowering-time note, retexted, ONE
        -- severity (Lossy, D-REGULATIVE's precedent): nothing emitted is
        -- broken, and the document is genuinely incomplete w.r.t. the source.
        A.DroppedRuleDateRebind ->
          dmnNote "D-RULEDATE-UNBOUND" Lossy nm rng
            ("`" <> nm <> "` evaluates a sub-graph under its OWN rule date (`EVAL UNDER \
             \RULES EFFECTIVE AT`); a DMN DRG has one global rule-date input and no \
             \scoped rebinding, so no faithful <decision> exists and it is not emitted")
            "the pinned-regime scenario: evaluate it in L4, or vary RULES_EFFECTIVE_DATE \
            \across engine invocations"
    | (u, reason) <- Map.toAscList popVerdict.pvDropped
    , let nm  = droppedNameOf u
    , let rng = droppedRangeOf u
    ]
      <> [ dmnNote "D-FIXTURE" Advisory nm rng
             ("`" <> nm <> "` satisfies the module-local fixture criterion (referenced only \
              \from directive argument positions, no callers in this module), but no importer \
              \view was available, so conjunct (d) — no caller in any importing module — was \
              \NOT checked and the decision is KEPT. Dropping on an unverified conjunct is \
              \how this filter would delete a statute")
             "nothing yet: this is a report-only advisory"
         | u <- Set.toAscList popVerdict.pvFixtureUnverified
         , let nm  = droppedNameOf u
         , let rng = droppedRangeOf u
         ]
      <> [ dmnNote "D-INERT" Advisory (Map.findWithDefault nm u decideByUnique) rng
             ("`" <> nm <> "` is kept, but its body forces no reference and no input — an \
              \inert prose carrier (typically statutory text plus a constant)")
             "nothing: the note exists so a reader can tell a constant stub from a live rule"
         | u <- Set.toAscList popVerdict.pvInert
         , let nm  = droppedNameOf u
         , let rng = droppedRangeOf u
         ]

  -- D-PARAMTYPE (OPEN-4's chosen spelling), Blocking: same-L4-named GIVEN
  -- parameters of un-lifted decisions whose DECLARED types differ. The merge
  -- is refused — the members stay distinct elements, exactly as today — and
  -- this note is what keeps the hazard visible: merging them anyway measures
  -- `null [SUCCEEDED]` with zero runtime messages on both target engines
  -- (GCO-first-version.l4:157,164), and D-SCOPE goes quiet at precisely the
  -- moment the merge happens, so a silent refusal would be undetectable.
  paramTypeNotes =
    [ dmnNote "D-PARAMTYPE" Blocking (Text.intercalate ", " elemIds) Nothing
        ("the GIVEN parameter `" <> nm <> "` "
           <> ( if hasUntyped
                  -- an untyped GIVEN is not a type CLASH, it is a type
                  -- UNKNOWN: nothing certifies agreement, so the refusal
                  -- wording must say "could not be certified", not "differ"
                  then
                    "is not declared at one certifiable type across un-lifted \
                    \decisions ("
                  else
                    "is bound at " <> englishCount (length distinctTys)
                      <> " different declared types across un-lifted decisions ("
              )
           <> Text.intercalate "; " claimantDescs
           <> "), so the Phase 4 merge is REFUSED and the parameters are emitted as the \
              \distinct elements "
           <> Text.intercalate ", " (map tick feelsOf)
           <> ". Merging them would make every decision read whichever value the caller \
              \bound to the one name — measured on both target engines as a null answer \
              \with status SUCCEEDED and zero runtime messages")
        "the one-input-per-name economy of the merge; every claimant keeps its own element, \
        \and a caller must bind each one"
    | (nm, members) <- conflictGroups
    , let hasUntyped = any (\(_, mty, _, _) -> isNothing mty) members
    , let distinctTys = nubOrd [ty | (_, Just ty, _, _) <- members]
    , let claimantDescs =
            [ maybe "no declared type" tick mty <> " in " <> tick owner
            | (_, mty, owner, _) <- members
            ]
    , let elemIds =
            [ Map.findWithDefault ("input_" <> sanitiseId nm) u inputByUnique
            | (u, _, _, _) <- members
            ]
    , let feelsOf =
            [ feel
            | (u, _, _, _) <- members
            , (feel, (fu, _)) <- zip inputFeelNames freeTerms
            , fu == u
            ]
    ]

  -- D-PARAM-AS-INPUT (OPEN-3, amended): one note per merged group of size
  -- >= 2, AND one per singleton group whose owner has an applied call site.
  -- The original size >= 2 gate was justified on the inputData side only
  -- ("a singleton parameter becomes a global input, which is unremarkable")
  -- — but the un-lift render discards the call-site ARGUMENT expression for
  -- a singleton exactly as for a merged group: `a MEANS net 100` renders as
  -- the bare FEEL name `net`, the literal 100 vanishes, and `a` evaluates to
  -- whatever the caller binds to the input — a Blocking verbatim note turned
  -- into a silently wrong number. So the singleton case notes too. A vacuous
  -- tier-1 decision (zero applied call sites) discards nothing and stays
  -- silent — there the old justification really does hold.
  paramAsInputNotes =
    [ dmnNote "D-PARAM-AS-INPUT" Advisory elemId Nothing body lost
    | (nm, members@((canonical, _, _, _) : _)) <- mergedGroups <> singletonArgGroups
    , let owners = nubOrd [owner | (_, _, owner, _) <- members]
    , let elemId = Map.findWithDefault ("input_" <> sanitiseId nm) canonical inputByUnique
    , let (body, lost) = case owners of
            [owner] ->
              ( "the GIVEN parameter `" <> nm <> "` of " <> tick owner
                  <> " became the model input " <> tick elemId
                  <> "; the decision can no longer be applied to different subjects \
                     \within this model, and the argument expressions at its call sites \
                     \are discarded — each call site now reads the one global value"
              , "per-call-site argument binding: L4 applied this decision to an \
                \expression; the DMN model reads one global value"
              )
            _ ->
              ( "the GIVEN parameter `" <> nm <> "` of " <> englishCount (length members)
                  <> " decisions (" <> Text.intercalate ", " (map tick owners)
                  <> ") became the one shared model input " <> tick elemId
                  <> "; those decisions can no longer be applied twice to different subjects \
                     \within this model, and the argument expressions at their call sites are \
                     \discarded"
              , "per-call-site argument binding: L4 applied these decisions to expressions; \
                \the DMN model reads one global value"
              )
    ]

  -- Singleton parameter groups whose owning decision is actually APPLIED
  -- somewhere: those call sites' argument expressions are what the un-lift
  -- discards, so they join 'paramAsInputNotes' above.
  singletonArgGroups :: [(Text, [(Unique, Maybe Text, Text, Unique)])]
  singletonArgGroups =
    [ (nm, members)
    | (nm, members@[(_, _, _, ownerU)]) <- Map.toAscList paramGroups
    , any (.csApplied) (Map.findWithDefault [] ownerU callGraph.cgCalls)
    ]

  -- D-PARTIAL (§2.4.2, OPEN-1): Phase 4 classifies and reports; it does not
  -- change node kind. A ¬DMN-SAFE decision simply does not un-lift — it keeps
  -- today's <decision> + verbatim call sites — and carries this note at the
  -- ruled severity, keyed off the CALL SITE, not the node kind (null arrives
  -- identically from a <decision> body, a BKM's encapsulatedLogic or an
  -- inlined cell; routing removes the widening, never the coercion).
  partialNotes =
    [ dmnNote "D-PARTIAL" sev did (headIssue >>= \i -> i.safRange)
        ("`" <> decideName d <> "` could not be certified total ("
           <> clauseText
           <> "), so it is not un-lifted: it keeps its <decision> node and its saturated \
              \call sites remain raw L4 (Phase 5 routes such decisions to a \
              \businessKnowledgeModel or inlines them). A DMN decision node is evaluated \
              \on every input any requiring decision is evaluated on, and an undefined \
              \FEEL result is null, which reads as false in every consuming boolean \
              \position"
           <> fallbackText)
        "the certainty that this node evaluates wherever the DRG reaches it: an input \
        \outside the decision's domain answers null with status SUCCEEDED, not an error"
    | d <- decides
    , let u = getUnique (decideResolved d)
    , Just issues <- [Map.lookup u safetyIssues]
    , let did = Map.findWithDefault (decideName d) u decideByUnique
    , let headIssue = listToMaybe issues
    , let clauseText = case issues of
            [] -> "unknown clause"
            (i : rest) ->
              i.safClause
                <> maybe "" (\r -> " at " <> prettySrcRange r) i.safRange
                <> ": " <> i.safDetail
                <> (if null rest
                      then ""
                      else "; and " <> tshow (length rest) <> " further clause(s)")
    , let sites = Map.findWithDefault [] u callGraph.cgCalls
    , let (sev, fallbackText)
            | null sites =
                (Blocking, ". No call site consumes it (it is a DRG root), so no guard can fence the null")
            | any (\s -> s.csStrict == A.StrictPos) sites =
                (Blocking, ". At least one call site consumes it from a strict position, so no guard fences the null")
            | otherwise =
                (Lossy, ". Every call site consumes it from a lazy position (an IF/CONSIDER arm), so a guard in the consumer can fence the null")
    ]

  -- D-BKM (Phase 5, §6.2): the tier-2 classification, now carried out. The
  -- decide is emitted as a <businessKnowledgeModel>; saturated call sites
  -- render as FEEL named-argument invocations backed by a knowledgeRequirement
  -- edge on each caller; module-level free terms of the body are λ-lifted
  -- into extra formal parameters (see 'bkmSignatures'). Advisory, per §7: the
  -- note records the emission and its lift, not a loss.
  --
  -- The SAFETY-REFUSED tier-2 residue (a member of safetyIssues) keeps the
  -- Phase 4 wording: it stays a <decision> with verbatim call sites, D-PARTIAL
  -- says why, and this note says what that costs.
  bkmNotes =
    [ if Set.member u bkmCandidateSet
        then
          dmnNote "D-BKM" Advisory did Nothing
            ("`" <> decideName d <> "` is emitted as a businessKnowledgeModel \
              \(tier 2): it is applied to distinct argument expressions"
               <> (if null callerNames
                     then ""
                     else " by " <> Text.intercalate ", " (map tick callerNames))
               <> ". Saturated call sites render as FEEL named-argument invocations \
                  \with a knowledgeRequirement edge on each caller"
               <> closureText)
            "the decision-as-variable reading: the callee no longer appears as a 0-ary \
            \decision variable, and is reachable only by invocation"
        else
          dmnNote "D-BKM" Advisory did Nothing
            ("`" <> decideName d <> "` is classified as a businessKnowledgeModel candidate \
              \(tier 2): it is applied to distinct argument expressions"
               <> (if null callerNames
                     then ""
                     else " by " <> Text.intercalate ", " (map tick callerNames))
               <> ", but it could not be certified total (see its D-PARTIAL note), so it \
                  \keeps its <decision> node and its call sites stay verbatim")
            "the invocation: an uncertified body inside a BKM would answer the same silent \
            \null one element kind later, so the emission is refused rather than degraded"
    | d <- decides
    , let u = getUnique (decideResolved d)
    , not (null (A.decideParams d))
    , A.tierOf callGraph u == A.Tier2
    , let did = Map.findWithDefault (decideName d) u decideByUnique
    , let callerNames = nubOrd
            [ droppedNameOf c
            | s <- Map.findWithDefault [] u callGraph.cgCalls
            , Just c <- [s.csCaller]
            ]
    , let closureText = case Map.findWithDefault ([], []) u bkmSignatures of
            (_, [])       -> ""
            (_, closures) ->
              "; " <> tshow (length closures)
                <> " module-level free reference(s) of its body ("
                <> Text.intercalate ", " [tick cn | (_, cn, _) <- closures]
                <> ") are λ-lifted into extra formal parameters, supplied at every call \
                   \site as `name: name` — a BKM body may read nothing beyond its \
                   \parameters (measured on both engines, §6.2)"
    ]

  -- §6.3-3, as narrowed by R7/§13.3: NOT a suppression and NOT a flavor gate —
  -- one Advisory, module-level, naming the consumers we do NOT emit for that
  -- cannot execute a BKM. Named because their failure modes are silent in
  -- opposite ways, so a reader who ships this artifact to one of them would
  -- learn nothing from the artifact itself.
  bkmConsumerNotes =
    [ dmnNote "D-BKM-CONSUMERS" Advisory "definitions" Nothing
        (tshow (Set.size bkmCandidateSet)
           <> " decision(s) are emitted as businessKnowledgeModels. Both target \
              \flavors execute BKMs (KIE 8.44, Camunda 8; §13.3), but two known \
              \NON-target consumers cannot: @hbtgmbh/dmn-eval-js has no BKM support \
              \and falls through to the next rule on an unresolvable callee \
              \(a plausible wrong answer), and Camunda 7 answers null, silently")
        "nothing on the target engines; portability to BKM-less consumers, which fail \
        \silently rather than loudly"
    | not (Set.null bkmCandidateSet)
    ]

  -- D-RULEDATE (§15.5), Advisory, exactly ONE per DRG. Structural model:
  -- 'sharedInputNotes' -- one note naming a list of dependent elements.
  --
  -- Knot 5's complaint is that the report was SILENT about law time. This is
  -- what makes it speak: an unbound `RULES_EFFECTIVE_DATE` is a well-formed DMN
  -- model that answers null in every dated decision, and nothing in the emitted
  -- artifact said so.
  --
  -- The FEEL name is READ OFF 'inputNodes', never re-folded: 'uniquifyIn' makes
  -- it a property of the whole DRG (see "L4.Dmn.Emit":200-208). The dependent
  -- list is read off the emitted IR, so it reflects R11's requirement rewrite
  -- and therefore includes every dated table.
  ruleDateNotes =
    [ dmnNote "D-RULEDATE" Advisory lawId Nothing
        ("this model is temporally parameterised: " <> tshow (length dependents)
           <> " decision(s) read the rule date, which is supplied as the DMN input `"
           <> feel <> "` (L4: `" <> nm <> "`) -- "
           <> Text.intercalate ", " (map tick dependents)
           <> ". Bind that input or every dated decision answers null")
        ("the reader's ability to run this model without knowing it has a rule-date \
         \precondition: an unbound `" <> feel <> "` is a well-formed DMN model that \
         \silently answers null in every dated decision")
    | Just lawId <- [lawTimeInputId]
    , i <- take 1 [n | n <- inputNodes, n.idId == lawId]
    , let feel = i.idFeelName
    , let nm = i.idName
    , let dependents =
            [ dn.dcnName
            | NodeDecision dn <- nodes
            , RequiredInput lawId `elem` dn.dcnRequirements
            ]
    ]

  sharedNames = Map.fromListWith (flip (<>))
    [ (feelIdentText tnm, [u]) | (u, tnm) <- freeTerms ]

  tick t = "`" <> t <> "`"

  -- D-RENAME, §5.2 stage 2's own note: the COLLISION arm only.
  --
  -- One note per element whose FEEL name had to be suffixed, naming the L4 name,
  -- the resolved FEEL name and the other claimants on the base. `Lossy` rather
  -- than `Blocking` is exactly what §5.3.4-3 makes conditional on stage 2: the
  -- names are now made distinct and `@label` preserves the source, so nothing is
  -- silently wrong -- what is lost is the resemblance between the FEEL text and
  -- the L4 name.
  --
  -- __The benign-mangle arm (`Advisory`) is deliberately NOT built here.__ §7's
  -- header defers the two-severities-on-one-code shape to a re-ruling against
  -- FIDELITY-SEVERITY-AXIS-SPEC.md §5, and the arm would emit ~169 Advisory
  -- notes on one corpus module while `@label` already carries the source name.
  renameNotes =
    [ dmnNote "D-RENAME" Lossy eid Nothing
        ("`" <> l4name <> "` is emitted as the FEEL name `" <> resolved
           <> "`, not `" <> foldedName <> "`: " <> englishCount (length claimants)
           <> " " <> kindPlural <> " in this module fold to `" <> foldedName
           <> "` (" <> Text.intercalate ", " (map tick claimants)
           <> "), and the first claimant in source order keeps the base name")
        "the resemblance between the emitted FEEL name and the L4 name it came from; \
        \the L4 name survives in @label"
    | (eid, kindPlural, l4name, foldedName, resolved, claimants) <- renameCandidates
    , resolved /= foldedName
    ]

  renameCandidates =
    [ (iid, "elements of the DRG's flat variable namespace", nm, feelIdentText nm, feel
      , [ other | (other, ofolded) <- varClaimants, ofolded == feelIdentText nm ])
    | ((_, nm), iid, feel) <- zip3 freeTerms inputIds inputFeelNames
    ]
      <> [ (did, "elements of the DRG's flat variable namespace", nm, feelIdentText nm, feel
           , [ other | (other, ofolded) <- varClaimants, ofolded == feelIdentText nm ])
         | (d, did, feel) <- zip3 decides decideIds decideFeelNames
         , let nm = decideName d
         ]
      <> [ ("itemdef_" <> sanitiseId tyName, "fields of one declared type", nameOf n, fldFolded, resolved
           , [ nameOf other | (other, _, _) <- fs ])
         | (tyName, fs) <- fieldScopes
         , (n, fldFolded, resolved) <- fs
         ]

  varClaimants =
    [ (nm, feelIdentText nm) | (_, nm) <- freeTerms ]
      <> [ (nm, feelIdentText nm) | d <- decides, let nm = decideName d ]

  -- TWO DIFFERENT DRG ELEMENTS THAT SPELL THE SAME FEEL NAME -- the whole
  -- namespace, not just the inputData half of it.
  --
  -- 'sharedInputNotes' above covers exactly one of the three ways this happens
  -- (inputData x inputData) because it is computed from 'freeTerms'. The other
  -- two -- inputData x decision, and decision x decision -- had no note at all,
  -- and they are the worse pair. Measured, on the two engines this exporter
  -- targets, with three two-element modules (base = 100, `net worth` = 7):
  --
  --   inputData x inputData   L4 says 10 + 200. KIE: validator 2x ERROR
  --                           [DUPLICATE_NAME], BUILD CLEAN, answers 20 --
  --                           both inputs read the one supplied value.
  --                           Camunda 8: parses clean, 0 errors, answers 20.
  --   inputData x decision    L4 says 7 + 101 = 108. KIE: validator 2x ERROR,
  --                           build clean, the decision is NOT_EVALUATED and
  --                           the answer is 14 -- the INPUT won. Camunda 8:
  --                           silent, and answers 202 -- the DECISION won.
  --   decision  x decision    L4 says 101 + 102 = 203. KIE: validator 2x ERROR,
  --                           one decision NOT_EVALUATED, answers 202.
  --                           Camunda 8: silent, answers 204.
  --
  -- Note what that table does NOT say. KIE does not /reject/ any of these: the
  -- DUPLICATE_NAME errors come from the validator leg, the KieBuilder leg is
  -- clean, and the model deploys and answers. So neither engine refuses the
  -- file, neither returns what L4 said, and the two do not even agree with each
  -- other on which element wins. Camunda -- the default flavor -- is the one
  -- that says nothing at all.
  --
  -- Blocking rather than Lossy for that reason: nothing was approximated, an
  -- answer was changed, and it survived every other check we have (the file is
  -- schema-valid, dmn-moddle-clean, and reports every decision as evaluated).
  --
  -- The fix that makes the collision go away rather than merely loud is §5.2's
  -- stage-2 @uniquifyIn@, and it has now landed: the names below are the
  -- RESOLVED ones, so this predicate fires __zero times by construction__ and
  -- D-RENAME reports the rename instead.
  --
  -- The code and its predicate are kept anyway, and §7's header says why: it
  -- must not be deleted until something else reports a duplicate
  -- `inputData/@name`, which DMN 1.3 §7.3.4 makes a violation of a normative
  -- SHALL. A test pins the count at zero, so the day it fires again is visible
  -- rather than inferred.
  declaredFeelNames :: [(Text, (Text, Text, Text))]
  declaredFeelNames =
    [ (n.idFeelName, ("inputData", n.idName, n.idId)) | n <- inputNodes ]
      <> [ (feel, (kind, decideName d, did))
         | (d, did, feel) <- zip3 decides decideIds decideFeelNames
         -- Phase 5: BKM names live in the same flat scope (probe E4 — the
         -- engines DISAGREE on a BKM/decision collision, so the detector must
         -- cover it), and the note should name the element kind that collided.
         , let kind = if isBkmDecide d then "businessKnowledgeModel" else "decision"
         ]

  feelNameCollisionNotes =
    [ dmnNote "D-FEELNAME" Blocking eid Nothing
        ("`" <> fname <> "` is the FEEL name of " <> Text.pack (show (length grp))
           <> " elements this module keeps apart ("
           <> Text.intercalate ", " [kind <> " `" <> l4name <> "`" | (kind, l4name, _) <- grp]
           <> "); DMN's variable namespace is flat, so no FEEL reference can pick one of them. \
              \Neither engine refuses the file: KIE's validator says DUPLICATE_NAME but still \
              \builds and answers, and Camunda 8 says nothing at all. Both answer with whichever \
              \element they resolved first, and they do not agree on which that is")
        "the distinction between them; every reference to either now reaches one of them"
    | (fname, grp@((_, _, eid) : _ : _)) <- Map.toAscList feelNameGroups
    ]

  feelNameGroups = Map.fromListWith (flip (<>)) [(f, [x]) | (f, x) <- declaredFeelNames]

  lowered = zipWith3 lowerOne decides decideIds decideFeelNames

  lowerOne d did feelName = (decision, notes)
   where
    MkDecide _ (MkTypeSig _ (MkGivenSig _ givens) mGiveth) _ rawBody = d
    -- The typechecker desugars every binary operator into a function
    -- application; 'carameliseExpr' undoes that, which is what makes a
    -- comparison recognisable as a comparison. The ladder does the same.
    caramelised = carameliseExpr rawBody

    -- WHERE/LET first: 'normaliseGuarded' cannot see through a wrapper, and the
    -- corpus's best tables are all WHERE-wrapped.
    peeled = peelLocals caramelised
    (body, inlined) = either (const (caramelised, [])) id peeled

    -- The oracle, built WITHOUT going through 'tctx'. 'TableCtx' has strict
    -- fields, so asking `oracleOf tctx` while computing `tcOutputType` would
    -- force the record that is being built.
    oracle0 = MkTypeOracle
      { toTypes = typeEnv, toSubst = opts.dloSubstitution, toUri = uri }

    givethSrc = case mGiveth of
      Just (MkGivethSig _ ty) -> Just ty
      Nothing                 -> annTypeSource oracle0 body

    (declaredType, declaredDomain, declaredFlags) =
      maybe (DmnAny, Nothing, noTypeFlags) (classifyType typeEnv) givethSrc

    -- Every type the decision states at its own boundary: the GIVEN parameters
    -- that carry a declared type, and the GIVETH.
    boundaryTypes =
      [ty | MkOptionallyTypedName _ _ (Just ty) _ <- givens] <> maybeToList givethSrc

    tctx = MkTableCtx
      { tcName         = decideName d
      , tcFeelName     = feelName
      , tcNames        = nameEnv
      , tcIdPrefix     = did
      , tcOutputType   = declaredType
      , tcConstructors = constructors
      , tcConstants    = namedConstants
      , tcTypes        = typeEnv
      , tcOutputValues = declaredDomain
      , tcDateConstants = dateConstants
      , tcSubst        = opts.dloSubstitution
      , tcUri          = uri
      }

    subExprs = toListOf (cosmosOf (gplate @(Expr Resolved))) body

    -- R4-a's three reading forms, plus R8-c/d/e. Each is a SENTENCE COMPLETING
    -- "`<decision>` is ...", so 'literalFallback' can render them all one way.
    --
    -- __Decided before 'normaliseGuarded' and before the select-idiom branch__
    -- (§4.2.1-8): a payload-binding CONSIDER fails inside "L4.Viz.GuardedRows"
    -- for a reason of its own, and would otherwise be reported "is not a guarded
    -- chain" -- a table-shape diagnosis for a FEEL type-system limit.
    sumTypeReasons :: [Text]
    sumTypeReasons =
      [ "a reader of `" <> owner
          <> "`, a payload-carrying sum type FEEL has no way to represent (it projects the \
             \payload field `" <> nameOf n <> "`)"
      | Proj _ _ n <- subExprs
      , Just owner <- [Map.lookup (getUnique n) payloadOwner]
      ]
        <> [ "a constructor of `" <> owner
               <> "`, a payload-carrying sum type FEEL has no way to represent (it applies `"
               <> nameOf r <> "` to arguments)"
           | (r, applied) <- appHeads
           , applied
           , Just owner <- [Map.lookup (getUnique r) payloadOwner]
           ]
        <> [ "a reader of `" <> owner
               <> "`, a payload-carrying sum type FEEL has no way to represent (a CONSIDER arm \
                  \binds `" <> nameOf cn <> "`'s payload)"
           | Consider _ _ brs <- subExprs
           , MkBranch _ (When _ (PatApp _ cn ps)) _ <- brs
           , not (null ps)
           , Just owner <- [Map.lookup (getUnique cn) payloadOwner]
           ]
        -- R8-e. NARROWED 2026-07-31 from all four builtin sum constructors to
        -- LEFT/RIGHT alone: R8-d′ gives JUST and NOTHING real FEEL renderings
        -- (`x` and `null`), so a decision that mentions them is no longer
        -- refused. EITHER has no FEEL image at any tag arity, so its two
        -- constructors keep the refusal AND keep the verbatim rendering that
        -- fixed R8-f.
        --
        -- The narrowing is what the three EITHER tests in jl4/tests/DmnExport.hs
        -- exist for. They were written and watched go green BEFORE this line
        -- moved, because EITHER had zero coverage here and zero corpus exposure,
        -- and a refusal nothing pins is a refusal a narrowing can take with it.
        <> [ "a decision that constructs or matches EITHER (it mentions `"
               <> nameOf r <> "`), and FEEL has no way to spell a tagged value"
           | r <- toList d
           , getUnique r `elem` [TC.leftUnique, TC.rightUnique]
           ]
        -- A CONSIDER over a MAYBE is no longer refused: R8-d′ renders it as
        -- `if <scrut> != null then a else b`, which never asks for a cell at
        -- all, so the endpoint-grammar objection does not arise.
        --
        -- `fl.tfEither || fl.tfNestedMaybe`, and the second disjunct is not
        -- redundant: 'classifyType' sets tfMaybe TRUE as well as tfNestedMaybe
        -- on a nested MAYBE, so narrowing to `tfEither` alone would let a
        -- MAYBE (MAYBE τ) scrutinee through and collapse `JUST NOTHING` and
        -- `NOTHING` onto one FEEL null -- an ANSWER CHANGE. Pinned by
        -- "refuses a NESTED MAYBE used as a CONSIDER SCRUTINEE".
        <> [ "a CONSIDER over `" <> oneLine (prettyLayout sty)
               <> "`, which has no faithful image: FEEL's `null` does not nest and FEEL has \
                  \no EITHER"
           | Consider _ scrut _ <- subExprs
           , Just sty <- [annTypeSource oracle0 scrut]
           , let (_, _, fl) = classifyType typeEnv sty
           , fl.tfEither || fl.tfNestedMaybe
           ]
        -- R8-c and R8-e at the boundary. Nested MAYBE is refused because `null`
        -- does not nest: `JUST NOTHING` and `NOTHING` would become one FEEL
        -- value, and FEEL `=` would answer true where L4 answers false. That is
        -- an ANSWER CHANGE, which is §2.4's own severity line.
        <> [ "typed `" <> oneLine (prettyLayout bty)
               <> "` at its own boundary: FEEL's `null` does not nest and FEEL has no EITHER, so \
                  \the type has no faithful image"
           | bty <- boundaryTypes
           , let (_, _, fl) = classifyType typeEnv bty
           , fl.tfNestedMaybe || fl.tfEither
           ]

    appHeads =
      [(r, not (null as)) | App _ r as <- subExprs]
        <> [(r, not (null as)) | AppNamed _ r as _ <- subExprs]

    -- R4-a's `Lossy` arms. Emitted only when the decision is NOT refused, so a
    -- reader is not told two different things about one decision.
    sumTypeLossyNotes
      | not (null sumTypeReasons) = []
      | otherwise = nullaryOnlyNotes <> threadedRecordNotes

    nullaryOnlyNotes =
      [ dmnNote "D-SUMTYPE" Lossy did (bestRange scrut)
          ("`" <> decideName d <> "` CONSIDERs `"
             <> Map.findWithDefault "" tu itemDeclNames
             <> "`, a payload-carrying sum type, over its nullary constructors only; no cell is \
                \emitted for " <> Text.intercalate ", " (map tick missing)
             <> ", and no FEEL value can stand for one")
          "the refused constructors' share of the domain -- the itemDefinition's allowedValues \
          \lists them, so a gap analyser reports the missing rows, which is the loss made visible"
      | Consider _ scrut brs <- subExprs
      , Just sty <- [annTypeSource oracle0 scrut]
      , Just tu <- [typeHeadUnique sty]
      , Set.member tu typeEnv.tePayload
      , let mentioned = Set.fromList [nameOf cn | MkBranch _ (When _ (PatApp _ cn _)) _ <- brs]
      , let missing =
              [c | c <- Map.findWithDefault [] tu typeEnv.teDomains, not (Set.member c mentioned)]
      , not (null missing)
      ]

    -- What survives is the type NAME, not the type: the component points at an
    -- itemDefinition over `string` whose allowedValues list every constructor as
    -- a bare tag. So the note names the typeRef it really emitted -- a reader
    -- can check that against the artifact -- and reports the loss that is
    -- actually there, which is the tag/payload distinction rather than the
    -- component's declared type.
    threadedRecordNotes =
      [ dmnNote "D-SUMTYPE" Lossy did Nothing
          ("`" <> decideName d <> "` threads `" <> Map.findWithDefault "" hu itemDeclNames
             <> "`, whose field `" <> fld <> "` is typed `" <> sumNm
             <> "`, a payload-carrying sum type; the itemComponent is emitted as typeRef=\""
             <> tref <> "\", which resolves to an itemDefinition over `string` listing every \
                \constructor as a bare tag -- FEEL has no tagged value, so a constructor that \
                \carries a payload and the same constructor without one are a single FEEL string")
          ("the tag/payload distinction: every `" <> sumNm
             <> "` constructor is spelled as a bare string, and the payload one of them carries \
                \has no image in the component at all")
      | bty <- boundaryTypes
      , Just hu <- [typeHeadUnique bty]
      , Just threaded <- [Map.lookup hu sumFieldRecords]
      , (fld, sumNm, tref) <- threaded
      ]

    -- R8-a at the decision's <variable>. This is also where a MAYBE-typed
    -- OUTPUT is reported: 'outputXml' emits no typeRef on an <output> at all
    -- (measured -- KIE says ILLEGAL_USE_OF_TYPEREF), so the decision's variable
    -- is the only place the type is written down.
    decisionMaybeNotes =
      [ maybeNullNote did (bestRange body) ("`" <> decideName d <> "`")
          (oneLine (prettyLayout sty)) declaredFlags.tfOptionalAlias
      | declaredFlags.tfMaybe
      , Just sty <- [givethSrc]
      ]

    (logic, tableNotes') = case sumTypeReasons of
      -- §4.2.1-8's diagnosis order, made structural.
      reason : _ -> literalFallback (SumTypeRead reason)
      [] -> plainLowering

    -- D-RULEDATE-UNBOUND moved to population time (R12, §15.12): a decide that
    -- rebinds law time is dropped by 'classifyPopulation' before this function
    -- ever sees it, and 'populationNotes' carries the (now Lossy) note. The
    -- per-decision two-message machinery that lived here described an emitted
    -- element that no longer exists.
    notes = tableNotes' <> sumTypeLossyNotes <> decisionMaybeNotes

    -- Computed ONCE and shared by 'plainLowering' and the requirement rewrite
    -- below, so the emitted logic and the emitted DRG edges cannot disagree.
    guardedRows = case peeled of
      Left _ -> Nothing
      Right _ | isSelectIdiomIn (oracleOf tctx) body -> Nothing
      Right _ -> normaliseGuarded body

    datedResult = case (sumTypeReasons, guardedRows) of
      ([], Just rs0) -> datedChain tctx lawTimePreds rs0
      _              -> NotDated

    -- R11: what SURVIVES into the artifact. D2 inlines the guard predicate and
    -- the regime constants into interval endpoints, so a dated decision's
    -- emitted expression no longer references them while its cells now
    -- reference the rule-date input. Computing 'dcnRequirements' from the
    -- source 'freeRefs' would describe a graph the expression contradicts.
    datedSurvivors = case datedResult of
      Dated arms oth _ -> Just (map (.daBody) arms <> [oth])
      _                -> Nothing

    plainLowering = case peeled of
      Left loss -> literalFallback loss
      -- A whole body that IS the select idiom is a formula, not a one-case
      -- table. DMN's own answer for a formula is a boxed literal expression, so
      -- this is not a loss and gets no D-LITERALEXPR note -- only the threshold
      -- note, if a threshold went inside the expression.
      Right _ | isSelectIdiomIn (oracleOf tctx) body ->
        let rendered = renderFeelIn nameEnv constructors (oracleOf tctx) body
        in
        ( LogicLiteral rendered
        , [ dmnNote "D-LIFTEDTHRESHOLD" Advisory did (bestRange sub)
              ("`" <> oneLine (prettyLayout sub) <> "` was lifted to " <> fn
                 <> "(...): the threshold is now inside an expression rather than a row of a table")
              "a compliance reader's ability to point at the threshold as a rule"
          | (fn, sub) <- liftedThresholds tctx body
          ]
          -- ...and the third no-note hole. This branch deliberately emits no
          -- D-LITERALEXPR (a formula IS a boxed expression, so nothing is lost),
          -- which meant a max/min over an operand we cannot render shipped with
          -- ZERO fidelity notes. Real corpus instance: `max(cash out, conversion
          -- amount(liq))`, where the second operand is an L4 call.
          <> [ nonFeelOutput did (bestRange body) rendered
             | rendered.feFragment == L4Verbatim
             ]
        )
      Right _ -> case guardedRows of
        Nothing -> literalFallback NotAGuardedChain
        Just rs0 -> case datedResult of
          -- D2: a newest-first chain of rule-date guards becomes ONE column
          -- over the rule-date input with half-open interval cells, UNIQUE.
          Dated arms oth lawRef ->
            ( LogicTable
                (datedTable tctx decideRefs decideRanges rs0 arms oth lawRef inlined)
            , []
            )
          -- It looked dated and could not be tabled. The SOUND fallback still
          -- ships (with its own D-NONFEELINPUT), and the refusal says why.
          DatedRefused why ->
            let (lg, ns) = ordinaryPath rs0
            in ( lg
               , ns
                   <> [ dmnNote "D-DATEDCHAIN" Blocking did
                          (listToMaybe (mapMaybe (bestRange . fst) rs0.grRows))
                          ("`" <> decideName d
                             <> "` is a chain of rule-date guards, but " <> why
                             <> ", so it was emitted as boolean columns over raw L4 rather \
                                \than as a date-interval table")
                          "interval gap and overlap analysis over the rule-date axis, which is \
                          \the whole reason a dated chain is worth tabulating"
                      ]
               )
          NotDated -> ordinaryPath rs0
     where
      ordinaryPath rs0
        | rowsElided body rs0 = literalFallback RowsElided
        | otherwise =
            let (rs, capped) = flattenGuarded rs0
            in case rowsToDmnWith' tctx inlined capped rs of
                 Right t   -> (LogicTable t, [])
                 Left loss -> literalFallback loss

    -- Never drop a decision. DMN's own answer for logic that is not tabular is a
    -- boxed literal expression, and a DRG that quietly omitted such decisions
    -- would describe a different rule set than the module does.
    --
    -- The loss chooses its own CODE ('fidelityLossCode'): a decision refused
    -- because FEEL has no sum type is @D-SUMTYPE@, everything else is
    -- @D-LITERALEXPR@. One shape, two diagnoses, which is §4.2.1-8's
    -- requirement expressed where it cannot be forgotten.
    --
    -- @D-LITERALEXPR@'s SEVERITY is keyed on the RENDERED FRAGMENT (ruled at
    -- the Phase 5 build, recorded in §7): Blocking's definition is "the target
    -- cannot express this at all; we emitted a fallback", which is true of a
    -- raw-L4 literal no engine can compile and FALSE of a boxed literal whose
    -- body is genuine FEEL — that one EXECUTES, and what it forfeits is the
    -- decision-table analyses, which is Advisory's definition to the letter.
    -- Before this, `Reg CF commenced MEANS Date 20 9 2016` — a date constant
    -- both engines evaluate — was counted in the same Blocking total as a
    -- deontic body, and the corpus's headline could not distinguish "will not
    -- execute" from "will not tabulate". @D-SUMTYPE@ keeps its ruled Blocking
    -- regardless of fragment (§4.2.1: the rendered text may compile and still
    -- answer differently from L4, which is worse than not compiling).
    literalFallback loss =
      ( LogicLiteral rendered
      , [ if blocking
            then
              dmnNote code Blocking did (bestRange body)
                ("`" <> decideName d <> "` is " <> renderFidelityLoss loss
                   <> ", so it is emitted as a boxed literal expression rather than a \
                      \decision table" <> verbatimTail)
                "every decision-table analysis: gap, overlap, consistency and manual review"
            else
              dmnNote code Advisory did (bestRange body)
                ("`" <> decideName d <> "` is " <> renderFidelityLoss loss
                   <> ", so it is emitted as a boxed literal expression rather than a \
                      \decision table; the expression is FEEL, and an engine evaluates it")
                "the decision-table analyses (gap, overlap, consistency): the literal \
                \computes, but it is not rules a checker can reach"
        ]
      )
     where
      rendered = renderFeelIn nameEnv constructors (oracleOf tctx) body
      code     = fidelityLossCode loss
      blocking = code == "D-SUMTYPE" || rendered.feFragment == L4Verbatim
      verbatimTail
        | rendered.feFragment == L4Verbatim =
            ". Its body could not be rendered as FEEL, so the emitted text is raw L4 \
            \that NO engine can evaluate"
        | otherwise = ""

    decision = MkDecision
      { dcnId           = did
      , dcnName         = decideName d
      , dcnFeelName     = feelName
      -- filled by 'finishCaller' (or consumed by 'toBkm'), from the edge set
      -- computed below.
      , dcnKnowledgeReqs = []
      , dcnType         = case logic of
          LogicTable t    -> t.dtOutput.ocType
          LogicLiteral _  -> declaredType
          LogicContext _  -> declaredType
      , dcnLogic        = logic
      -- R11 (§15.3): a dated table's requirements are computed from what
      -- SURVIVES into the artifact -- the arm bodies and the OTHERWISE -- plus
      -- the rule-date input its cells now name. Guards are excluded because D2
      -- has inlined their content into interval endpoints. Consequence, and it
      -- is intended: the regime constants and the guard predicate become DRG
      -- leaves with no dependents. They are NOT dropped (see 'literalFallback');
      -- the annotation column carries their provenance into the artifact.
      --
      -- §4.4 extends the same principle to hydration. Where a read of `x`'s
      -- COMPUTED field has been folded, the emitted FEEL names the hydrator and
      -- not `x`, so the direct edge must go and an edge to the hydrator must
      -- appear. Consequence, and it is intended: a decide that reads ONLY
      -- computed fields of `x` ends up `x -> hydration_x -> decide`, with no
      -- direct edge at all. A decide that reads both raw and computed fields
      -- keeps both edges, which is also correct.
      , dcnRequirements = case (datedSurvivors, lawTimeInputId) of
          (Just bodies, Just lawId) ->
            let (survivors, touched) = survivingRefs bodies
            in sort . nubOrd $
                 RequiredInput lawId
                   : mapMaybe (classifyRef did) survivors <> hydratorEdges touched
          _ ->
            let (survivors, touched) = survivingRefs [view decideBody d]
                -- 'freeRefs' bounds the survivors to what this decide does not
                -- itself bind, exactly as before; the fold only removes.
                free = Set.fromList (map getUnique (freeRefs d))
                kept = [r | r <- survivors, Set.member (getUnique r) free]
            in sort . nubOrd $
                 mapMaybe (classifyRef did) kept <> hydratorEdges touched
      }
     where
      hydratorEdges touched =
        [ RequiredDecision hid
        | u <- touched
        , Just hid <- [Map.lookup u hydratorIdByInstance]
        ]

  -- DMN 1.3 §6.3.7: a Decision SHALL not require itself, "directly or
  -- indirectly". Both cases are DETECTED, not suppressed (§6.4.4-2):
  --
  --   * the direct case used to be erased here (a `target /= did` arm) and in
  --     'freeRefs' (which bound the decide's own name), so a self-requiring
  --     decision exported with advisory-only fidelity, KIE compiled it, and
  --     `x=false` answered a silent null [SUCCEEDED]. The filter was what
  --     converted a violation three engines catch loudly into a silent one.
  --     Deleted; a self-edge now reaches 'dcnRequirements' and 'checkDrg'
  --     reports it as a one-member SCC (`D-CYCLE`).
  --   * the indirect case exists — L4 DOES admit forward references among
  --     top-level DECIDEs (the three-phase pipeline scans declarations before
  --     inferring bodies; an earlier version of this comment asserted the
  --     opposite, reasoned from a stale TypeCheck.hs header) — and is the same
  --     SCC check's ≥ 2 arm.
  -- The first parameter (the owner's id) is retained so every call site reads
  -- unchanged; nothing branches on it any more.
  classifyRef _did r = case Map.lookup u decideByUnique of
    Just target -> Just (RequiredDecision target)
    Nothing -> RequiredInput <$> Map.lookup u inputByUnique
   where
    u = getUnique r

-- | Deterministic element ids: derived from the L4 name, with a positional
-- suffix only where two names sanitise to the same id.
--
-- This __is__ §5.2 stage 2, and always was — first claimant keeps the base, the
-- nth gets @base_\<n\>@ — applied to XML ids rather than to FEEL names. It is
-- now expressed in terms of 'uniquifyIn' so the id namespace and the FEEL
-- namespace cannot drift apart on the stepper they share. (The one behavioural
-- difference is a repair: 'uniquifyIn' takes the least FREE suffix, so a
-- source name that already spells @foo_2@ can no longer be handed out twice.)
assignIds :: Text -> [Text] -> [Text]
assignIds prefix names = uniquifyIn (map ((prefix <>) . sanitiseId) names)

-- | Small counts spelled as words, as a fidelity note's prose wants them.
englishCount :: Int -> Text
englishCount n = case n of
  2 -> "two"
  3 -> "three"
  4 -> "four"
  5 -> "five"
  6 -> "six"
  7 -> "seven"
  8 -> "eight"
  9 -> "nine"
  _ -> tshow n

-- | An XML @ID@-safe, deterministic slug.
sanitiseId :: Text -> Text
sanitiseId t
  | Text.null trimmed           = "unnamed"
  | isDigit (Text.head trimmed) = "_" <> trimmed
  | otherwise                   = trimmed
 where
  trimmed  = Text.intercalate "_" (filter (not . Text.null) (Text.split (== '_') lowered))
  lowered  = Text.map keep (Text.toLower t)
  keep c
    | isAscii c && isAlphaNum c = c
    | otherwise                 = '_'

------------------------------------------------------------------------
-- Module traversal
------------------------------------------------------------------------

-- | Every top-level declaration, descending through nested @SECTION@s.
-- | The module's own title: the name of its outermost @§@ heading, if it has
-- one.
--
-- This exists so that the @\<definitions\>@ name has a single source. It was
-- previously supplied by the caller in every case, which meant the Reg CF
-- corpus's model was called three different things at once — its own heading
-- (@SEC Regulation Crowdfunding — 17 CFR Part 227@), a string hand-typed in
-- the golden test, and the file's base name from the CLI. A title duplicated
-- across three files and stale in at least two of them is the exact defect
-- this exhibit exists to criticise.
moduleTitle :: Module Resolved -> Maybe Text
moduleTitle (MkModule _ _ (MkSection _ mName _ decls)) =
  listToMaybe
    ( [nameOf n | Just n <- [mName]]
        <> [nameOf n | Section _ (MkSection _ (Just n) _ _) <- decls]
    )

topDecls :: Module Resolved -> [TopDecl Resolved]
topDecls (MkModule _ _ sec) = section sec
 where
  section (MkSection _ _ _ ds) = concatMap decl ds
  decl d = case d of
    Section _ sub -> d : section sub
    _             -> [d]

decideResolved :: Decide Resolved -> Resolved
decideResolved (MkDecide _ _ (MkAppForm _ n _ _) _) = n

decideName :: Decide Resolved -> Text
decideName = nameOf . decideResolved

-- | Names a decision refers to but does not itself bind.
--
-- @Resolved@ already distinguishes defining from referring occurrences, so
-- "bound inside the body" is exactly "has a 'Def' inside the body" — which covers
-- lambda parameters, @LET@\/@WHERE@ locals and pattern binders without
-- enumerating them. @GIVEN@ parameters are bound in the /signature/, not the
-- body, so they correctly come out free and become @inputData@.
--
-- Record-field projections are dropped here (a selector is a reference but not a
-- term); constructors and names from other modules are dropped by the caller,
-- which is what keeps every prelude function and builtin out of the DRG.
freeRefs :: Decide Resolved -> [Resolved]
freeRefs (MkDecide _ _ _ body) =
  [r | r <- refs, not (Set.member (getUnique r) bound)]
 where
  allResolved = toList body
  -- The decide's OWN name is deliberately NOT in `bound` (§6.4.4-2): treating a
  -- self-reference as bound erased the self-edge before any graph could see it,
  -- which is how a decision that requires itself — the case DMN 1.3 §6.3.7
  -- names first — exported with advisory-only fidelity. Downstream consumers
  -- are unaffected: 'decideFreeTerms' filters `decideByUnique` membership, so
  -- the own name cannot mint an inputData; what it now CAN do is reach
  -- 'classifyRef' and appear in 'dcnRequirements' as the self-edge it is.
  bound = Set.fromList [u | Def u _ <- allResolved]
  projFields = Set.fromList
    [getUnique n | Proj _ _ n <- toListOf (cosmosOf (gplate @(Expr Resolved))) body]
  refs = nubOrdOn getUnique
    [r | r@Ref {} <- allResolved, not (Set.member (getUnique r) projFields)]

-- | Did 'normaliseGuarded' drop a @CONSIDER@ arm, leaving nothing to cover the
-- inputs it used to catch?
--
-- @considerRows@ may elide an arm whose pattern binds but whose body is inert
-- (literally @FALSE@) -- which is what rescues the corpus's two widest diagrams.
-- For the ladder that is exact: a missing disjunct contributes FALSE. For DMN it
-- is not, because an unmatched input yields __null__, not @false@. When an
-- @OTHERWISE@ survives, its body becomes the default output and the hole is
-- plugged; when there is none, the table would answer differently from the rule,
-- so we refuse to emit one.
--
-- This check cannot live inside 'rowsToDmnWith', because 'GuardedRows' does not
-- record that an arm was elided -- which is also why 'rowsToDmn', whose signature
-- the spec fixes, cannot make it. A less conservative fix is available (the
-- elided arms are all FALSE by @considerRows@' own contract, so a @false@ default
-- output would be exactly right) but it would couple this module to that
-- contract, and the shape is rare.
rowsElided :: Expr Resolved -> GuardedRows -> Bool
rowsElided body rs = case body of
  Consider _ _ brs ->
    not (any isOtherwiseBranch brs)
      && length [() | MkBranch _ When {} _ <- brs] > length rs.grRows
  _ -> False
 where
  isOtherwiseBranch (MkBranch _ lhs _) = case lhs of
    Otherwise _ -> True
    When _ _    -> False

-- | Deontic material anywhere in the body. DMN models /decisions/; lifecycle is
-- BPMN's and CMMN's job, and there is no joint semantics across that seam (the
-- mechanism that would connect them lives in DMN's non-normative Annex A).
isRegulative :: Expr Resolved -> Bool
isRegulative = anyOf (cosmosOf (gplate @(Expr Resolved))) $ \case
  Regulative {} -> True
  Event {}      -> True
  Breach {}     -> True
  _             -> False

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------

tshow :: Show a => a -> Text
tshow = Text.pack . show
