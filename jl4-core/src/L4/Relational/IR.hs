-- | The shared relational middle-end's intermediate representation: L4's typed
-- functional core rendered as moded, typed Horn clauses. One IR, four-plus
-- emitters (Blawx first, then swipl, ASP, Logical English, PROLEG) — see
-- @specs\/proposals\/LOGIC-PROGRAMMING-BACKENDS-SPEC.md@ §2 (PR #258, pinned at
-- commit @ec6d3627@ while that PR is open) and
-- @specs\/todo\/BLAWX-EXPORT-SPEC.md@ R2.
--
-- __'RelProgram' is a NORMAL FORM, and says so on purpose.__ Clause-per-disjunct,
-- materialised guard prefixes, A-normal-form bodies. It is /not/ a picture of the
-- source's boolean shape and must never be read as one: a consumer that needs the
-- shape the author wrote goes back to the AST through per-clause provenance
-- ('RProv' — a 'Unique' plus a 'SrcRange'), never by reconstructing it from
-- clauses. (Receipt: a sibling bridge's measurement pass silently walked a
-- CNF'd form while its emitter lowered source form, and the disagreement moved a
-- headline number in one direction only.)
--
-- __A clause body is an ORDERED SEQUENCE, and the order is semantics.__ Goals keep
-- source evaluation order; the ANF pass inserts a binding goal before its first
-- use and otherwise permutes nothing; DNF distribution duplicates conjuncts into
-- sibling clauses but never reorders them within a clause. Conjunction is a list,
-- not a set — which is why 'rcBody' is @['RGoal']@ — and no consumer, renderer or
-- optimiser may canonically sort it. This is also the premise under which the
-- materialised guard prefix is sound: transformed arm /i/ evaluates
-- ¬g₁ … ¬g₍ᵢ₋₁₎ then gᵢ in exactly the original chain's guard-evaluation order, so
-- no raise is introduced or reordered even where a guard can raise. A pass that
-- permutes goals within a body does not merely change Prolog-family behaviour; it
-- invalidates that discharge.
--
-- __Guards are not claimed to be strict.__ L4's connectives are lazy and a
-- Horn-clause body is a strict conjunction. M1's policy (#258 §3.1) is that
-- /total, pure/ guards are exact and that partiality is a documented, undetected
-- residual — so nothing here, and nothing the Debug renderer prints, asserts
-- strictness equivalence. Goal order preserves the source's guard-before-use
-- structure precisely so a guarded division is not evaluated ahead of its guard.
--
-- __The load-bearing constraint is what this IR refuses to decide.__ A field
-- access is a goal ('RProj'), never a committed representation: the swipl leg
-- may unify against a functor term (#258 §2.3), the Blawx leg must emit an
-- attribute-predicate goal (BLAWX-EXPORT-SPEC R2's deliberate divergence,
-- because a functor term would execute but be invisible to the scenario editor
-- and the ontology API). An IR that picked either would kill the other family
-- of emitters. The same refusal governs names ('RName' carries the /source/
-- name and its 'Unique'; every emitter mangles into its own lexical class and
-- runs its own collision check) and stratification ('RStratification' is
-- /recorded/, not enforced: swipl rejects a non-stratified program, ASP treats
-- it as the whole point, Blawx rejects it in v1).
--
-- Negation exists in exactly one form here, 'RNotCall'. 'L4.Relational.Lower'
-- pushes @NOT@ down before the IR is built: over a comparison it complements
-- the operator, over boolean structure it applies De Morgan and re-normalises
-- to DNF, over a projected boolean it becomes a 'RUnify' against 'RTBool'.
-- What survives is the negation of a predicate call, which is the only thing
-- every target can express. This is deliberately not natural4's mistake, whose
-- @bsr2struct@ emitted a marker pseudo-atom @neg@ followed by the translation
-- of its operand — output that parses as Prolog and means nothing (#258 §8.3).
--
-- __'RNotCall' in the M1 fragment is CLASSICAL negation.__ Every in-fragment
-- negation originates as boolean @NOT@ over a total computed decision; the
-- lowering introduces no closed-world or negation-as-failure assumption
-- (aggregates run over lists, not over open predicates). A later widening that
-- introduces NAF-semantics negation must add a NEW constructor rather than
-- overload this one, so that classical consumers — an SMT leg, the Catala
-- bridge — can reject it by type instead of by convention.
--
-- Disjunction likewise has no constructor: it lives in the /multiplicity of
-- clauses/. A body is a conjunction of goals; alternatives are separate
-- 'RClause's under one 'RPred'. Guarded chains materialise their negated
-- prefixes (#258 §2.2) because clause order is not semantics we may rely on
-- across four targets — in ASP it is nothing at all. A corollary worth stating:
-- @BRANCH@\/@CONSIDER@ first-match priority therefore compiles away /by
-- construction/, and no disjointness obligation survives into the IR for an
-- emitter to discharge.
--
-- == What an emitter still has to work out for itself
--
-- Stated here so that no consumer discovers it by writing a wrong emitter. None
-- of these is a hole in the lowering; each is a place where the IR deliberately
-- carries the /neutral/ fact and leaves the target-shaped one to the leg.
--
-- * __A body variable's sort.__ 'RVar' carries an id and a rendering hint, never
--   a sort ('rvHint' is not one). The sorts are recoverable in one linear pass:
--   a head variable's is the corresponding 'rpParams' entry, an 'RProj' output's
--   is the field's 'rfSort' in 'rpgRecords', an 'RCall' output's is the callee's
--   'rpResult', an 'REval' or numeric 'RAggregate' output is a number, an
--   'RFindAll' output is a list. A leg that needs sorts pervasively (swipl's
--   functor terms, #258 §2.3) should build that map once rather than guess.
-- * __Which equality an 'RCmp' 'REq' is.__ It is /generic/ equality, not
--   arithmetic equality — see 'RCmp'.
-- * __A ground object for a query subject.__ 'RQuery' subjects are 'RTVar's; a
--   target whose scenario facts must be ground skolemises them. See 'RQuery'.
-- * __Arity ceilings and other target limits.__ Recorded nowhere, enforced
--   nowhere: Blawx's relationship ceiling is Blawx's (its emitter rejects above
--   it), exactly as 'RStratification' is recorded here and rejected there.
module L4.Relational.IR
  ( -- * Names and variables
    RName (..)
  , RVar (..)
    -- * Terms
  , RTerm (..)
  , rTermList
    -- * Goals
  , RGoal (..)
  , RCmpOp (..)
  , complementCmp
  , RArith (..)
  , RArithOp (..)
  , RAggOp (..)
    -- * Clauses and predicates
  , RClause (..)
  , RProv (..)
  , RPred (..)
  , RPredKind (..)
  , RRecursion (..)
    -- * Sorts (the typed half of "moded, typed Horn clauses")
  , RSort (..)
    -- * Ontology
  , RRecordDef (..)
  , RFieldDef (..)
  , REnumDef (..)
  , RAbstractDef (..)
    -- * Queries (the differential harness's seeds)
  , RQuery (..)
  , RQueryKind (..)
  , RFact (..)
    -- * Signed dependency graph and stratification
  , RSign (..)
  , RDepEdge (..)
  , RStratification (..)
  , isStratified
    -- * The program
  , RelProgram (..)
    -- * Errors
  , LowerError (..)
  , LowerErrorKind (..)
  , renderLowerError
  , renderLowerErrorKind
  ) where

import Base
import qualified Base.Text as Text

import L4.Interchange.Fidelity (FidelityReport)
import L4.Parser.SrcSpan (SrcRange, prettySrcRange)
import L4.Syntax (Unique)

-- ---------------------------------------------------------------------------
-- Names and variables
-- ---------------------------------------------------------------------------

-- | A predicate, field, constructor or type name, as written in the source,
-- plus the 'Unique' that is its identity.
--
-- __No mangling happens in the middle-end.__ Each emitter folds these into its
-- own lexical class (Prolog atoms are lowercase-initial; Blawx slugs are
-- @[-a-zA-Z0-9_]+@; s(CASP) @#pred@ strings escape @'@) and runs its own
-- collision check, following the OpenFisca @pyIdent@ + @checkCollisions@
-- precedent. A fold performed here would be either wrong for some target or the
-- intersection of all of them, which is worse.
--
-- Two textual forms are carried because emitters genuinely need both: 'rnText'
-- is @rawNameToText@ verbatim, 'rnBase' is @unqualifiedRawNameToText@ — and
-- @L4.Syntax@'s own guidance is that export formats which give @.@ another
-- meaning should ask for the base name and account for any collision it creates
-- in their own report.
--
-- __A definition's 'rnText' is NOT section-qualified, and no emitter may use it
-- to recover a @§@.__ The section-qualified spelling of a name declared under a
-- @§@ exists only as a separate @defAka@ alias 'Resolved' sharing the original's
-- 'Unique' (@L4.TypeCheck.qualifiedAliases@); @getOriginal@ on the /defining/
-- occurrence returns the bare @NormalName@, so every predicate, field and
-- constructor name built from a definition has @rnText == rnBase@. Only a
-- referring occurrence written through the alias can carry a qualified spelling.
-- A consumer that needs per-section anchoring (BLAWX-EXPORT-SPEC R4's workspace
-- naming) must take it from 'RProv' — the 'SrcRange' locates the definition in
-- the source — or from a second pass over the module, not from this field.
--
-- Identity joins on the 'Unique': a consumer that needs the ladder or
-- query-plan UUIDv5 atom id derives it from this same 'Unique' (the
-- @atomIdByUnique@ pattern), rather than inventing a second identity scheme.
data RName = MkRName
  { rnText   :: !Text     -- ^ source spelling, verbatim (may be @a.b@ qualified)
  , rnBase   :: !Text     -- ^ same, with any @§@ qualification dropped
  , rnUnique :: !Unique   -- ^ identity
  }
  deriving stock (Show, Generic)
  deriving anyclass (NFData)

-- | Identity is the 'Unique' alone. Two 'RName's that disagree on spelling but
-- agree on 'Unique' are the same entity (a referring occurrence spelled through
-- an @AKA@ alias, for instance); comparing the text as well would make an alias
-- a different predicate and silently split its clauses.
instance Eq RName where
  a == b = a.rnUnique == b.rnUnique

instance Ord RName where
  compare a b = compare a.rnUnique b.rnUnique

-- | A logic variable minted by the ANF pass.
--
-- Identity is 'rvId' alone; 'rvHint' is a rendering aid derived from whatever
-- the variable stands for (a @GIVEN@ name, a field name, @Tmp@), so the Debug
-- renderer and the emitters can produce @Income@ rather than @V7@. The
-- instances are written by hand rather than derived precisely so a hint can be
-- improved without changing variable identity.
data RVar = MkRVar
  { rvId   :: !Int
  , rvHint :: !Text
  }
  deriving stock (Show, Generic)
  deriving anyclass (NFData)

instance Eq RVar where
  a == b = a.rvId == b.rvId

instance Ord RVar where
  compare a b = compare a.rvId b.rvId

-- ---------------------------------------------------------------------------
-- Terms
-- ---------------------------------------------------------------------------

-- | A first-order term.
--
-- __There is deliberately no functor-term constructor for records.__ A record
-- value is reached only as an opaque 'RTVar' plus 'RProj' goals; a record
-- /literal/ (in a query's inputs) is flattened to 'RFact's. This is IR
-- constraint 1 made structural: an emitter that wants @applicant(A, Age,
-- Income)@ builds it from the record's 'RRecordDef' and the projections; an
-- emitter that wants @age(A, Age)@ builds that instead. Neither is privileged
-- here, and neither can be smuggled in by an emitter that just prints terms.
--
-- Enum constructors DO appear, as 'RTAtom' — payload-free by construction
-- (payload-carrying enums are out of the M1 fragment), so the compound-term
-- question does not arise for them either.
data RTerm
  = RTVar  !RVar
  | RTNum  !Rational      -- ^ L4 @NUMBER@ is @Rational@
  | RTStr  !Text          -- ^ literal-equality atoms only in M1
  | RTBool !Bool
  | RTAtom !RName         -- ^ a payload-free enum constructor
  | RTNil                 -- ^ the empty list
  | RTCons !RTerm !RTerm  -- ^ @[H|T]@ — list decomposition in a clause head is
                          --   how structural recursion is expressed
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | A ground list literal, right-folded into 'RTCons' \/ 'RTNil'.
rTermList :: [RTerm] -> RTerm
rTermList = foldr RTCons RTNil

-- ---------------------------------------------------------------------------
-- Goals
-- ---------------------------------------------------------------------------

-- | One goal in a clause body. A body is a /conjunction/ of these, in
-- bind-before-use order: every 'RVar' occurring in an input position of a goal
-- is bound by an earlier goal or by the clause head.
--
-- The list order is semantics (see the module header). Disjunction is absent by
-- design (it is clause multiplicity); negation appears only as 'RNotCall'.
data RGoal
  = RCall !RName ![RTerm]
    -- ^ A predicate call. For a value-returning predicate the /last/ term is
    -- the output argument (#258 §2.2: \"functions to predicates by A-normal-form
    -- flattening with an added output argument\"); for a boolean-valued
    -- predicate ('rpResult' = 'Nothing') there is no output argument at all.
  | RNotCall !RName ![RTerm]
    -- ^ __The only negation form in the IR__, and __classical__ in the M1
    -- fragment (module header). Emitters map it to their own negation and are
    -- free to refine by what the callee is: BLAWX-EXPORT-SPEC R5 splits input
    -- predicates (classical @-p@, so an absent input fails loudly instead of
    -- reading as false) from computed decisions (@not p@), and 'rpKind' on the
    -- callee is what lets it. Whether the surrounding program is stratified
    -- enough for that to be sound is 'rpgStrata'.
  | RProj !RTerm !RName !RVar
    -- ^ __Abstract field access__ — @RProj subject field out@. The single most
    -- important thing this IR does not decide (see the module header).
  | RUnify !RVar !RTerm
    -- ^ @X = t@. Also the image of @NOT@ over a projected boolean:
    -- @RProj a isVeteran V, RUnify V (RTBool False)@, which the Blawx emitter
    -- peepholes to @-is_veteran(A)@ and a functor-term emitter reads as
    -- ordinary unification.
  | RMatch !RVar !RName
    -- ^ @X = \<nullary constructor atom\>@ — @CONSIDER@ discrimination over a
    -- payload-free enum, kept distinct from 'RUnify' + 'RTAtom' so an emitter
    -- can render it as a match rather than an equation (Blawx §4.4's
    -- equality-discrimination goal; s(CASP) may prefer a distinct form). It is
    -- a convenience, not a semantic requirement: the normaliser produces an
    -- equality guard, and 'RMatch' is reached by recognising that guard's shape
    -- afterwards, so textually similar L4 can yield 'RMatch' or 'RCmp' 'REq'
    -- depending on whether the constructor is nullary and known.
  | RCmp !RCmpOp !RTerm !RTerm
    -- ^ A comparison whose operator is already the one to emit: @NOT@ over a
    -- comparison was discharged by 'complementCmp' in Lower, never here.
    --
    -- __'REq' \/ 'RNeq' are GENERIC equality, not arithmetic equality.__ The
    -- ordering operators only ever relate numbers, but the two equalities also
    -- relate enum atoms, booleans and string literals: a negated @CONSIDER@ row
    -- or a negated @EQUALS@ against a nullary constructor lowers to
    -- @'RCmp' 'RNeq' x ('RTAtom' c)@ (it cannot be an 'RMatch', which has no
    -- negative form). An emitter must therefore choose its comparison by
    -- operand shape — in the Prolog family @=:=@ \/ @=\\=@ for numbers and
    -- @==@ \/ @\\==@ for everything else, since @=:=@ on an atom raises a type
    -- error rather than failing. "L4.Relational.Debug" does exactly this.
  | REval !RVar !RArith
    -- ^ @Out is Expr@ — arithmetic over already-bound atoms. The only place an
    -- expression /tree/ survives into the IR, and deliberately so: flattening
    -- @a + b * c@ into three goals buys nothing and costs every emitter a
    -- reassembly pass.
  | RFindAll !RVar ![RGoal] !RVar
    -- ^ @findall(Template, Goal, List)@ — @RFindAll template body out@. The
    -- @body@ is a conjunction; a disjunctive collection body must be factored
    -- into an auxiliary 'RPred' first (Lower does this), because @findall@ over
    -- a disjunction is not portable across the legs.
  | RAggregate !RAggOp !RVar !RVar
    -- ^ @RAggregate op list out@, i.e. @Out = agg(List)@ — the LIST comes
    -- first, the output second, matching 'RFindAll' and Blawx's own
    -- @sum_blawx_list(List, Sum)@. The two fields are same-typed, so an emitter
    -- that swapped them would typecheck and emit a wrong program silently;
    -- stating the order here is the only guard against that.
    --
    -- Recognised in the middle-end, not in the emitters (BLAWX-EXPORT-SPEC
    -- R2\/R9), so all four legs inherit one recogniser.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

data RCmpOp = RLt | RLeq | RGt | RGeq | REq | RNeq
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

-- | The operator that holds exactly when this one does not. Total, and an
-- involution — the property a test should pin, because it is what makes
-- \"@NOT@ over a comparison never touches negation semantics\"
-- (BLAWX-EXPORT-SPEC §4.3) true rather than merely claimed.
complementCmp :: RCmpOp -> RCmpOp
complementCmp = \case
  RLt  -> RGeq
  RGeq -> RLt
  RGt  -> RLeq
  RLeq -> RGt
  REq  -> RNeq
  RNeq -> REq

-- | Arithmetic over already-bound atoms. No calls, no projections: those were
-- lifted into preceding goals by the ANF pass.
--
-- __Operand order and association are load-bearing and must never be
-- normalised.__ Boolean structure is the only thing the normaliser touches.
-- M1 excludes dates, but date addition is neither commutative nor associative
-- (portfolio invariant I9), so a reassociating or operand-sorting pass built
-- here would be silently unusable the moment M2 admits them — and its output
-- would still typecheck. Do not add one.
data RArith
  = RANum !Rational
  | RAVar !RVar
  | RABin !RArithOp !RArith !RArith
  | RANeg !RArith
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

data RArithOp = RAdd | RSub | RMul | RDiv | RMod
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

-- | The aggregations recognised over a collected list.
--
-- Spelled after L4's /prelude/ names, which are not the ones a Haskell or SQL
-- reader expects: the prelude has @sum@, @count@ (not @length@), @maximum@ and
-- @minimum@ over lists — @max@ and @min@ are the BINARY combinators
-- (@jl4-core\/libraries\/prelude.l4:265,119,336,345,302,309@). @average@ has no
-- prelude definition at all; 'RAvg' is produced only from the composite idiom
-- @sum xs \/ count xs@ over one @xs@.
data RAggOp = RSum | RCount | RMinimum | RMaximum | RAvg
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- Sorts
-- ---------------------------------------------------------------------------

-- | The sort of a predicate argument or result. Needed by the Blawx leg, which
-- declares an attribute's value type in its ontology and cannot infer it from
-- the clauses; supplied by @L4.Export.enrichReturnTypes@ \/ @enrichParamTypes@
-- where the source omits a @GIVETH@.
--
-- 'RSOpaque' is the honest escape hatch: a type the M1 fragment admits
-- structurally but has no sort for. It is never silently emitted — Lower
-- produces it only alongside a @FidelityNote@.
data RSort
  = RSBool
  | RSNum
  | RSString
  | RSEnum   !RName      -- ^ payload-free enum type
  | RSRecord !RName
    -- ^ __A category-shaped sort, not necessarily a declared record.__ Two
    -- sources reach it: a @DECLARE … HAS@ record (listed in 'rpgRecords' with
    -- its fields) and a top-level @ASSUME T IS A TYPE@ (listed in
    -- 'rpgAbstract', which carries a name and a provenance and nothing else,
    -- because an abstract category has no fields to carry). A consumer that
    -- needs the field list looks the name up in 'rpgRecords' and treats an
    -- absence as \"abstract\" rather than as a missing declaration. The two
    -- share one constructor on purpose: every downstream use — Blawx's
    -- category block, the category guards, the swipl leg's functor head — wants
    -- \"a category named /n/\", and a second constructor would make each of
    -- them re-derive that they mean the same thing.
  | RSList   !RSort
  | RSMaybe  !RSort
  | RSOpaque !Text       -- ^ the L4 type's printed form; carries a fidelity note
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- Clauses and predicates
-- ---------------------------------------------------------------------------

-- | Where a clause came from, so a target-side answer lifts back to a citation
-- (#258 §2.1; IR constraint 9). The 'Unique' is the originating definition's —
-- it survives renaming and is the join key against the module — and the
-- 'SrcRange' is the span to quote. 'Nothing' for a range means the node carried
-- no source span (a synthesised guard-prefix negation, say), which is
-- information, not an error.
--
-- Note for whoever fills this in: a guard synthesised by
-- @L4.Viz.GuardedRows.considerRows@ carries @emptyAnno@ and therefore has no
-- range at all. Take the range from the enclosing @Branch@ \/ @Decide@ node, not
-- from the guard expression, or the whole @CONSIDER@ family loses its citations
-- and the loss is invisible — a 'Nothing' range reads as a legitimate absence.
data RProv = MkRProv
  { rpvUnique :: !Unique
  , rpvRange  :: !(Maybe SrcRange)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | One Horn clause: a head argument list and a conjunctive body.
--
-- __One clause per disjunct__ (IR constraint 4). A @BRANCH@ arm /i/ carries the
-- negations of guards 1../i−1/ already conjoined into 'rcBody' — materialised,
-- not implied by position — because clause order is not semantics across four
-- targets and in ASP it is nothing at all (#258 §2.2). 'rcGuardPrefix' records
-- how many leading goals are that materialised prefix, so a swipl-only peephole
-- back to clause-order-plus-cut (#258 LP-R2, still OPEN) can find them without
-- re-deriving them, and so a reader of the Debug render can tell a prefix from a
-- real condition.
--
-- __A prefix goal is not thereby a negated goal.__ @NOT@ is pushed to the
-- literals /before/ the prefix is built, so the prefix of arm /i/ is the
-- lowering of ¬gⱼ and already contains whatever negation that took: an
-- 'RNotCall', a complemented 'RCmp', or a projection bound and then falsified
-- against @FALSE@. An 'RCall' or 'RProj' surviving inside a prefix is a
-- genuinely /positive/ occurrence — @NOT (q x AT LEAST 5)@ becomes
-- @q(X, V), V \< 5@, which depends on @q@ positively. The dependency-graph
-- builder therefore signs edges from the goals themselves and not from this
-- field; signing by position manufactured negative edges that were never in the
-- source and could report a stratified program as unstratified.
--
-- 'rcBody' is a list because the order is semantics (module header). Do not sort
-- it, and do not let an optimiser permute it.
--
-- One obligation this type hands to the emitters: __a head may bind a variable
-- no goal uses__ (@member(X, [X|Rest])@, and every non-recursive list
-- destructuring). The middle-end is the only layer that can see it — 'RVar'
-- identity is 'rvId' — but naming it here is not the middle-end's business,
-- since \"the anonymous variable\" is a target's lexical class. A Prolog-family
-- emitter should render an unused head variable as @_@ (or @_Rest@) rather than
-- inherit a singleton-variable warning per clause.
data RClause = MkRClause
  { rcHead        :: ![RTerm]
  , rcBody        :: ![RGoal]
  , rcGuardPrefix :: !Int
  , rcProv        :: !RProv
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | Why a predicate exists — which the emitters need, not just the reader.
--
-- BLAWX-EXPORT-SPEC R5 makes the input\/computed split /semantic/: @NOT@ over an
-- input attribute emits classical @-p(A)@ so an accidentally-absent input fails
-- loudly, while @NOT@ over a computed decision emits @not p(A)@ because its
-- rules are a total definition. An emitter cannot recover that distinction from
-- the clause list (an input predicate simply has no clauses, which is also true
-- of a bug), so the middle-end states it.
data RPredKind
  = RInput
    -- ^ A stored value the program reads and never defines — no clauses.
    --
    -- __Two sources reach this kind, and both are inputs in the same sense.__
    --
    -- 1. A __stored record field__ a lowered clause projects. Its 'rpParams' is
    --    the owning record's sort and its 'rpResult' is the field's, so a
    --    @BOOLEAN@ field is @'Just' 'RSBool'@ — the goal it appears in is an
    --    'RProj' plus an 'RUnify', which an emitter peepholes to a signed unary
    --    call.
    -- 2. A __top-level @ASSUME@__ a lowered clause calls. Its 'rpParams' is the
    --    arrow spine of the @ASSUME@\'s signature and its 'rpResult' follows
    --    the ordinary boolean convention ('Nothing' for a boolean, so the goal
    --    is a plain 'RCall' \/ 'RNotCall'). BLAWX-EXPORT-SPEC §4.10\'s
    --    @#abducible@ interview test is what this exists for: an @ASSUME@d name
    --    is precisely a fact the interview asks the user about.
    --
    -- They are told apart by identity, not by a flag: an input predicate built
    -- from a field shares that field's 'Unique' (so it is found among the
    -- 'rrFields' of 'rpgRecords'), and an @ASSUME@-derived one is not. A leg
    -- that needs the distinction — Blawx declares a field's attribute block
    -- from the record and an @ASSUME@\'s from the predicate — tests membership
    -- there. Nothing about R5's semantics differs between them, which is why
    -- there is no second constructor.
    --
    -- __Both are gated on reachability.__ A field no projection reads and an
    -- @ASSUME@ no clause calls contribute nothing, exactly as a declared but
    -- unused record contributes an ontology entry and no predicate.
    --
    -- The residue: an @ASSUME@ whose signature the fragment refuses (a
    -- function-typed parameter, a @DATE@\/@MAYBE@ sort) is rejected by name at
    -- its first use, with the range of the @ASSUME@ rather than of the use, and
    -- a /local/ @ASSUME@ has no module-level identity to declare and stays out
    -- ('LEUnsupported' @\"local ASSUME\"@).
    --
    -- One consequence for a differential harness: @ASSUME@ is uninterpreted in
    -- L4, so a module in that style typechecks and does not evaluate, and the
    -- L4 oracle cannot answer for a predicate built this way. That is a fact
    -- about what the harness may anchor on, not a reason to withhold the
    -- predicate — the target-side answer is still checkable against a
    -- semantically equivalent @GIVEN@-record spelling of the same logic.
  | RComputed   -- ^ an @\@export@ decision or a reachable top-level helper
  | RAuxiliary  -- ^ lambda-lifted @WHERE@\/@LET@, a DNF factoring, a findall body
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

-- | Whether a predicate refers to itself, and if so on what warrant.
--
-- M1 admits exactly one warrant: a structurally decreasing list argument, the
-- @CONSIDER l WHEN EMPTY … WHEN x FOLLOWED BY xs …@ shape, which lowers to a
-- two-clause definition over 'RTNil' \/ 'RTCons' heads. Any other self-reference
-- is a batch 'LowerError' ('LEUncheckedRecursion'), not a marker — the promise
-- \"emitted programs terminate\" stays checkable (BLAWX-EXPORT-SPEC R9).
--
-- The constructor set is expected to widen when #258's LP-R7 (tabling \/
-- well-founded semantics on the swipl leg) is ruled; widening it is a source
-- change here and a new case in each emitter, which is the point.
data RRecursion
  = RNonRecursive
  | RStructural !Int  -- ^ the 0-based head position of the decreasing list argument
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | A predicate: its interface, its clauses, and what Lower learned about it.
--
-- @'rpResult' = 'Nothing'@ marks a boolean-valued predicate that has /dropped/
-- its output argument and become a plain goal — the DMN exporter's \"boolean
-- column\" move in reverse (#258 §2.2), and what makes @eligible_for_benefit(A)@
-- rather than @eligible_for_benefit(A, true)@.
--
-- A lambda-lifted @WHERE@\/@LET@ helper keeps its source name here. Never inline
-- a named local into its parent's body: the name is the citation hook, and two
-- helpers spelled alike in two decisions stay distinct because 'RName' identity
-- is the 'Unique', not the text.
data RPred = MkRPred
  { rpName      :: !RName
  , rpKind      :: !RPredKind
  , rpParams    :: ![RSort]
  , rpResult    :: !(Maybe RSort)  -- ^ 'Nothing' = boolean goal, output arg dropped
  , rpRecursion :: !RRecursion
  , rpClauses   :: ![RClause]      -- ^ empty exactly when 'rpKind' is 'RInput'
  , rpExported  :: !Bool           -- ^ carried an @\@export@ (a query entry point)
  , rpDesc      :: !(Maybe Text)   -- ^ the @\@desc@ prose
  , rpNlg       :: !(Maybe Text)
    -- ^ the @\@nlg@ sentence, linearised. Carried beside 'rpDesc' rather than
    -- folded into it because they are different artifacts with different
    -- consumers: @\@desc@ is prose /about/ the decision, @\@nlg@ is the sentence
    -- the decision /is/, with its @%parameter%@ slots. BLAWX-EXPORT-SPEC R10
    -- sources its mandatory @#pred@ strings from @\@nlg@ (falling back to a
    -- prettified name), and Logical English and PROLEG want the same text — so
    -- it belongs in the shared IR, not in one emitter's second pass over the
    -- module.
  , rpRef       :: !(Maybe Text)
    -- ^ the @\@ref@ citation, verbatim. The other half of what an
    -- ontology-bearing target needs and cannot recover from clauses:
    -- BLAWX-EXPORT-SPEC R4 anchors each decision's rules in the workspace named
    -- after its section, and 'RName' cannot supply that (see 'RName').
  , rpProv      :: !RProv
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- Ontology
-- ---------------------------------------------------------------------------

-- | A @DECLARE … HAS@ record, kept as a /declaration/ rather than baked into
-- terms. The Blawx leg turns it into a category plus one attribute per field;
-- the swipl leg may turn it into a functor term; both read the same table.
--
-- Only /stored/ fields appear. @L4.Desugar.desugarComputedFields@ strips a
-- @MEANS@ field out of the record before type checking and synthesises a
-- top-level selector for it, so in a @Module Resolved@ a computed field is
-- already an ordinary unary decision: a projection onto one lowers to an
-- 'RCall', not an 'RProj', and a \"record has no such field\" branch for it is
-- dead code.
data RRecordDef = MkRRecordDef
  { rrName   :: !RName
  , rrFields :: ![RFieldDef]
  , rrProv   :: !RProv
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

data RFieldDef = MkRFieldDef
  { rfName :: !RName
  , rfSort :: !RSort
  , rfDesc :: !(Maybe Text)
  , rfNlg  :: !(Maybe Text)   -- ^ the field's @\@nlg@ sentence, linearised (see 'rpNlg')
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | A top-level @ASSUME T IS A TYPE@: a category with no fields, and nothing
-- else to say about it.
--
-- Kept apart from 'RRecordDef' rather than folded in as a zero-field record,
-- because 'rpgRecords' is documented as \"a @DECLARE … HAS@ record\" and a
-- consumer that reads it to find a record literal's fields (or to decide that a
-- name may head one) must not be handed a type that has none. Emitted only when
-- some admitted predicate's parameter or result is sorted by it — the same
-- reachability discipline every other ontology entry follows.
data RAbstractDef = MkRAbstractDef
  { raName :: !RName
  , raProv :: !RProv
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | A @DECLARE … IS ONE OF@ enum, payload-free (constructors with payloads are
-- out of the M1 fragment, 'LEEnumPayload'). Constructors become 'RTAtom's.
data REnumDef = MkREnumDef
  { reName :: !RName
  , reCons :: ![RName]
  , reProv :: !RProv
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------

-- | One row of a query's input scenario. A record literal argument to an
-- @#EVAL@ is /flattened/ into these, one per stored field, which is the only
-- representation both the functor-term and the attribute-predicate emitters can
-- build from without the IR having chosen (IR constraint 1 again).
--
-- __The subject is an 'RTVar', and an emitter that needs ground facts MUST
-- skolemise it.__ A record literal has no name in the source, so the middle-end
-- mints a variable for it (shared, by 'rvId', between the facts and the
-- enclosing 'RQuery' \'s 'rqArgs') rather than inventing an object name — naming
-- is the emitters' job, in their own lexical class ('RName'). Rendered
-- literally, @age(A0_11, 70)@ is a fact about /every/ subject and
-- @?- eligible(A0_11, R)@ asks a different question from the one the @#EVAL@
-- asked: it is not a type error, not a lowering error, and it silently answers
-- wrongly. One constant per @('rqId', 'rvId')@ pair is the minimum an emitter
-- owes here.
--
-- The subject's record type is not carried either, and is recoverable: look any
-- of its facts' 'rfaPred' up among the 'rrFields' of 'rpgRecords'. A leg that
-- needs a category fact (@applicant(a0)@) synthesises it from that.
data RFact = MkRFact
  { rfaPred :: !RName
  , rfaArgs :: ![RTerm]
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

data RQueryKind = RQEval | RQAssert
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

-- | An @#EVAL@ or @#ASSERT@ lifted to a query — the differential harness's
-- seeds (#258 §6.2; BLAWX-EXPORT-SPEC R11, whose ruling is that the /oracle
-- lives outside the artifact/, so a bridge bug that shifts actual and expected
-- together cannot pass silently).
--
-- 'rqExpected' is filled only where the directive's value is statically
-- present; where it is not, the harness must obtain it by running the L4
-- evaluator. It is 'Maybe' rather than a synthesised default precisely so the
-- absence is visible.
data RQuery = MkRQuery
  { rqId       :: !Text
  , rqKind     :: !RQueryKind
  , rqGoal     :: !RName
  , rqArgs     :: ![RTerm]         -- ^ subject term(s); output var last if any
  , rqOut      :: !(Maybe RVar)    -- ^ the variable the answer binds
  , rqFacts    :: ![RFact]         -- ^ flattened record-literal inputs
  , rqExpected :: !(Maybe RTerm)
  , rqProv     :: !RProv
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- Signed dependency graph and stratification
-- ---------------------------------------------------------------------------

data RSign = RPositive | RNegative
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

-- | An edge @from@ depends on @to@. Signed negative when the dependency passes
-- through a negation: an 'RNotCall', or a materialised guard prefix (which is a
-- negation even though it never printed a @NOT@ in the source).
data RDepEdge = MkRDepEdge
  { redFrom :: !RName
  , redTo   :: !RName
  , redSign :: !RSign
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | The Apt–Blair–Walker result, __recorded and not enforced__ (#258 §2.5, IR
-- constraint 8). The legs consume it differently and the middle-end must not
-- pre-empt them: swipl rejects a non-stratified program (or routes it to
-- tabling, LP-R7); ASP treats non-stratification as the source of the multiple
-- stable models that are the entire point of that leg; Blawx rejects in v1
-- because its L4-oracle determinism obligation does not tolerate more than one
-- answer, even though s(CASP) itself would.
--
-- A non-stratified module therefore lowers /successfully/, carrying
-- 'RUnstratified'. Turning it into a 'LowerError' here would break the ASP leg
-- before it exists.
data RStratification
  = RStratified !(Map RName Int)
    -- ^ a stratum index per predicate; no negative edge climbs
  | RUnstratified ![[RName]]
    -- ^ the strongly-connected components that contain a negative edge, in
    -- discovery order — named, because \"not stratified\" is useless to a
    -- reader who then has to find the cycle themselves
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

isStratified :: RStratification -> Bool
isStratified = \case
  RStratified _   -> True
  RUnstratified _ -> False

-- ---------------------------------------------------------------------------
-- The program
-- ---------------------------------------------------------------------------

-- | A whole module in relational normal form. See the module header for what
-- \"normal form\" commits the reader to.
data RelProgram = MkRelProgram
  { rpgSource   :: !Text            -- ^ source file basename, for headers
  , rpgTitle    :: !(Maybe Text)    -- ^ the module's outermost @§@ heading
  , rpgRecords  :: ![RRecordDef]
  , rpgAbstract :: ![RAbstractDef]
    -- ^ the @ASSUME@d types some admitted predicate's signature mentions, in
    -- source declaration order. Category-shaped like 'rpgRecords' and
    -- deliberately not in it (see 'RAbstractDef').
  , rpgEnums    :: ![REnumDef]
  , rpgPreds    :: ![RPred]         -- ^ inputs first, then computed, then auxiliary
  , rpgQueries  :: ![RQuery]
  , rpgDeps     :: ![RDepEdge]
  , rpgStrata   :: !RStratification
  , rpgFidelity :: !FidelityReport
    -- ^ what the /middle-end/ could not carry losslessly, in the shared shape
    -- every other backend uses (#258 §2.1). Distinct from 'LowerError': a note
    -- accompanies output, an error replaces it. It lives inside 'RelProgram'
    -- rather than beside it (the Docassemble bridge returns a tuple) because an
    -- emitter adds its own notes to the same report, and a tuple makes that
    -- plumbing manual at every call site.
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- Errors
-- ---------------------------------------------------------------------------

-- | A reason a module could not be lowered.
--
-- __Errors accumulate__ (IR constraint 10): @'Either' ['LowerError']
-- 'RelProgram'@, so a module with four out-of-fragment constructs reports four
-- diagnostics, not the first one. The shape follows OpenFisca's
-- @errFn@\/@errMsg@ with two additions the relational leg needs: a 'SrcRange',
-- because the same construct can appear many times in one decision, and a
-- machine-readable 'LowerErrorKind', because #258 §6.1's census counts
-- rejections /by constructor/ and a census that greps English prose is a census
-- that breaks on a reworded sentence.
--
-- Every M1 'LowerError' is conceptually Blocking. The Fidelity vocabulary's
-- Blocking\/Lossy\/Advisory gating (and any @--fail-on@ flag) is a CLI concern
-- and is deferred.
data LowerError = MkLowerError
  { errFn    :: !Text              -- ^ the offending definition (empty = module level)
  , errRange :: !(Maybe SrcRange)
  , errKind  :: !LowerErrorKind
  , errMsg   :: !Text              -- ^ one sentence, in the author's vocabulary
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | The rejection catalogue. Mirrors the /scope statement/ of the M1 fragment
-- one-for-one, which is what makes \"anything in-fragment that fails to lower
-- is a bug, anything out-of-fragment that lowers is a bug\" a testable claim
-- rather than a slogan.
data LowerErrorKind
  = LENoExport            -- ^ no @\@export@-annotated DECIDE to lower
  | LEDeontic             -- ^ @Regulative@ \/ @Deonton@
  | LEEvent               -- ^ @Event@
  | LEEffect              -- ^ @Fetch@ \/ @Env@ \/ @Post@
  | LELedger              -- ^ @Record@ \/ @ReadCell@
  | LEBreach              -- ^ @Breach@
  | LEString              -- ^ string computation beyond literal-equality atoms
  | LEDate                -- ^ dates — M2, see @DATE-LIBRARY-SPEC.md@
  | LEEnumPayload         -- ^ an enum constructor with a payload
  | LEMaybe               -- ^ a @MAYBE@ use beyond @isJust@\/@isNothing@\/@fromMaybe@,
                          --   including the @holds@\/@naf@\/@presumed@ eliminators of
                          --   the negation-as-failure library (#258 LP-R3 is OPEN, so
                          --   M1 rejects them by name rather than lowering them as
                          --   inert ordinary calls)
  | LEHigherOrder         -- ^ a lambda outside a recognised combinator position
  | LEUncheckedRecursion  -- ^ self-reference with no structurally decreasing argument
  | LESet                 -- ^ @SET OF@
  | LEArity               -- ^ a predicate above the target-independent arity ceiling
  | LEUnbound             -- ^ a reference the lowering cannot resolve to a predicate
  | LEUnsupported !Text   -- ^ an in-tree constructor with no image; the 'Text' names it
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | The English name of a rejection kind. Deliberately separate from 'errMsg':
-- the kind names /what/ was rejected (stable, greppable, census-countable), the
-- message says /where and why/ (free prose, may be reworded).
renderLowerErrorKind :: LowerErrorKind -> Text
renderLowerErrorKind = \case
  LENoExport           -> "no @export decision"
  LEDeontic            -> "deontic/regulative rule (PARTY/MUST/MAY)"
  LEEvent              -> "EVENT"
  LEEffect             -> "effect (FETCH/POST/ENV)"
  LELedger             -> "ledger (RECORD/COMMIT/ATTEST/RECALL)"
  LEBreach             -> "BREACH"
  LEString             -> "string computation"
  LEDate               -> "date arithmetic"
  LEEnumPayload        -> "enum constructor with payload"
  LEMaybe              -> "MAYBE beyond isJust/isNothing/fromMaybe"
  LEHigherOrder        -> "higher-order function"
  LEUncheckedRecursion -> "non-structural recursion"
  LESet                -> "SET OF"
  LEArity              -> "arity ceiling"
  LEUnbound            -> "unbound reference"
  LEUnsupported t      -> t

renderLowerError :: LowerError -> Text
renderLowerError e =
  loc <> scope <> renderLowerErrorKind e.errKind <> ": " <> e.errMsg
 where
  scope
    | Text.null e.errFn = ""
    | otherwise         = "in `" <> e.errFn <> "`: "
  loc = maybe "" (\r -> prettySrcRange r <> ": ") e.errRange
