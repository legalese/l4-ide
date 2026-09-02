# Logic-Programming Backends Specification

**Status:** Partly implemented, and no longer blocked. The middle-end this
spec calls for exists: `L4.Relational.{IR,Lower,Debug}` landed 2026-08-18
(legalese/l4-ide#272) to the brief in
[RELATIONAL-M1-BRIEF.md](../todo/RELATIONAL-M1-BRIEF.md), and the first of
the four emitters — the **s(CASP)** leg — shipped on top of it as the Blawx
bridge over 2026-08-19 (#273, #277, #278, #279; raw s(CASP) is dumped by
`l4 blawx --scasp`), specified by
[BLAWX-EXPORT-SPEC.md](../todo/BLAWX-EXPORT-SPEC.md). The other three legs —
**SWI-Prolog**, **Logical English**, **PROLEG** — remain unbuilt (verified
against `origin/unstable` on 2026-08-28: no emitter module for any of them
under `jl4-core/src`; `jl4-proleg` is still the reader/printer/burden-monad
trio of §8.1, not a transpiler). The design below is unchanged and still
governs those three; read its present-tense statements about what the tree
contains as claims of its 2026-08-12 authorship date, not of today.
**Author:** Meng Wong
**Date:** 2026-08-12 (status refreshed 2026-08-28)
**Related:**
[VERIFICATION-BACKEND-LOWERING-SPEC.md](VERIFICATION-BACKEND-LOWERING-SPEC.md),
[NEGATION-AS-FAILURE-SPEC.md](../done/NEGATION-AS-FAILURE-SPEC.md),
[SUBJECT-TO-NOTWITHSTANDING-SPEC.md](../todo/SUBJECT-TO-NOTWITHSTANDING-SPEC.md),
[BOUNDED-DEONTICS-SPEC.md](../todo/BOUNDED-DEONTICS-SPEC.md),
`paper/icail/l4-icail.tex` §6 and Appendix A, `jl4-proleg/`

## Overview

This specification proposes transpilation from L4 to four logic-programming
targets: **SWI-Prolog**, **Answer Set Programming** (clingo / s(CASP)),
**Logical English**, and **PROLEG**. Its central claim is architectural:

> These are not four transpilers. They are **one missing middle-end** — a
> relational lowering from L4's typed functional core to moded, typed Horn
> clauses — plus four comparatively thin emitters. The middle-end is the hard
> part, it does not exist, and every target is blocked on it.

_(Written 2026-08-12. The middle-end now exists — see the status header — so the
"does not exist" clause is history, not a description of the tree. The
one-middle-end architecture is what got built; whether the remaining three
emitters are as thin as claimed is still untested, since only the s(CASP) leg
has been written.)_

The ICAIL paper names the pass and its theory. §6 ("Two Readings of One
Program: Functional and Relational", `paper/icail/l4-icail.tex:500`) observes
that a total typed function _is_ its graph, and that L4's constitutive rules
"compile not only to a forward evaluator but also to a relational form: Horn
clauses in the manner of Prolog", with Mercury's modes and Curry's narrowing
as the conceptual bridges. The appendix specifies the mechanism in one line
(`l4-icail.tex:1468`): _"functions to predicates by A-normal-form flattening
with an added output argument."_ That sentence describes a compiler pass that
no code implements. This spec is the plan for that pass and its consumers.

### Why the previous generation never needed this pass — and why we do

natural4 (`/Users/mengwong/src/smucclaw/dsl`, the previous generation of this
codebase, studied here strictly as a design corpus) shipped Prolog, sCASP,
ASP, Epilog, and Logical English transpilers. It could, because its IR was
**already relational**: the spreadsheet front end parsed rules into
`Hornlike` rules of `HornClause2` values — a head `RelationalPredicate` and a
body `BoolStructR` of relational predicates
(`natural4/src/LS/XPile/Prolog.hs:48-67`). Emitting a logic program from
that is near pretty-printing, and the transpilers are structured as exactly
that (`rp2goal`, `bsr2struct`: syntax-directed prints, ~300 lines).

jl4 is a typed functional language with nested expressions, records,
pattern matching, `WHERE`-bound locals, and higher-order prelude functions.
The lowering natural4 never needed is precisely what jl4 requires. This is
structural invalidation of the old transpilers, not neglect: there is no
code to port, only lessons to mine (§8.3).

### The two readings must agree

The L4 evaluator (`jl4-core/src/L4/EvaluateLazy.hs`) is the reference
semantics. Every emitted logic program carries a faithfulness obligation
against it, discharged by differential testing over the existing corpus
(§6). This mirrors the cross-validation stance of
[VERIFICATION-BACKEND-LOWERING-SPEC.md](VERIFICATION-BACKEND-LOWERING-SPEC.md)
— and divides labour with it: that spec assigns temporal/deontic conflict
search to model checkers and names ASP as the natural host for the
non-monotonic in-force determination (its line 124). This spec builds the
lowering that would make such an ASP layer real. The regulative/deontic layer
itself is **out of scope for v1** (§5.6, LP-R9).

## 1. The four targets form a lattice, not a portfolio

The targets are ordered by **what each preserves of L4's meaning** — or,
read downward, what each erases. Choosing a backend is choosing which
dimensions of the source survive.

| Dimension preserved                              | swipl | ASP | PROLEG | LE  |
| ------------------------------------------------ | ----- | --- | ------ | --- |
| Truth condition (closed-world, stratified)       | ✓     | ✓   | ✓      | ✓   |
| **Multiplicity** (alternative consistent models) | ✗     | ✓   | ✗      | ✗   |
| **Burden of proof** (who loses if unproven)      | ✗     | ✗\* | ✓      | ✗   |
| Natural-language surface                         | ✗     | ✗   | ✗      | ✓   |

\* recoverable by convention (party-indexed literals), not by construction —
see §5.3.

### 1.1 Pure Prolog keeps the truth condition and nothing else

A stratified program under SLDNF computes the same closed-world verdicts as
L4's `holds`/`naf` reading (§3.4). Everything else is erased: `\+ e` does not
record _who_ had to establish `e` (the §5.6 argument, below), and SLD
resolution commits to one derivation — it cannot answer "how many consistent
readings does this rulebook have?". What swipl buys is ubiquity, speed, an
interactive query surface for backward/abductive queries
(`l4-icail.tex:525-533`), and the cheapest possible differential validation.

### 1.2 ASP preserves multiplicity — and multiplicity is the loophole hunt

The project's own ASP paper (Lim, Mahajan, Strecker & Wong 2022, §8.2.1)
defines a _legal model_ axiomatically and proves the ASP encoding sound: **the
answer sets of the encoded program are the legal models of the rule
configuration**. Its worked example (the Rolls-Royce/Mercedes rules) yields
exactly two answer sets — two mutually consistent readings of one rulebook —
and adding one modifier or one fact collapses or shifts them. A single-proof
system (swipl, PROLEG's meta-interpreter, L4's own evaluator) answers "is
this conclusion in force under this reading?"; only stable-model enumeration
answers "**what are all the readings?**", which is scenario search, which is
the loophole hunt of `l4-icail.tex:1465-1474`: the relational image of
`Provable`'s negation-as-failure is answer-set default negation, and
"stable-model enumeration becomes scenario search". The same paper also shows
the price of admission (§4.4): grounding and integer-only arithmetic — the
honest treatment is §5.2.

### 1.3 PROLEG preserves burden allocation

[SUBJECT-TO-NOTWITHSTANDING-SPEC.md](../todo/SUBJECT-TO-NOTWITHSTANDING-SPEC.md)
§5.6 (line 438) carries the key argument: **`exception(H, E)` is strictly
more expressive than `H :- B, not E`**, because it also records _who bears
the burden_ of establishing the exception — plaintiff proves the rule's
facts, defendant the exception, plaintiff the counter-exception. Bare NAF
erases that. The ICAIL appendix works the full correspondence
(`l4-icail.tex:1484-1499`): PROLEG's `exception` / implicit closed world /
`plausible` / `opposite(P)` map to `notProven` / `resolve` / the `Maybe` /
`flipBurden` of the `Provable` burden monad, and onward to the ASP image.
Emitting PROLEG is therefore not a syntax problem — `jl4-proleg` already
parses and prints canonical PROLEG round-trip — it is an **information
problem**: plain boolean L4 does not say which `AND NOT` conjuncts are
defeaters or who bears them. §5.4 confronts this; LP-R6 leaves the source of
the marking open.

### 1.4 Logical English is a surface over the Prolog image, not a peer

This is argued from the natural4 goldens, not assumed. Every `.le` golden
under `natural4/test/Testcases/LogicalEnglish/` (34 files across 33 cases)
begins with the declaration `the target language is: prolog.`, and the checked-in
hand-verified notes (e.g. `and-not/notes/and_not.pl`) show what the LE
toolchain compiles the document to: an ordinary Prolog program
(`is_an_aquatic_animal(A) :- lives_in_water(A), not lives_on_land(A).`) plus
`local_dict/3` clauses mapping each predicate to its word sequence. LE's
semantic content _is_ the logic program underneath; what LE adds is a
**controlled-natural-language rendering contract**: templates ("NLAs") with
`*a x*` variable indicators, determiner-based variable binding, and
paragraph layout. Correspondingly, natural4's LE transpiler (11 modules,
~2,387 LOC — the largest logic-programming emitter it had) spends its bulk
not on logic but on _linguistics_: `GenNLAs.hs` (467 lines) reconstructs
templates with regex machinery, and whole golden cases exist just to pin
regex anchoring and anaphora ("ditto") behaviour.

jl4 changes that cost structure: `@nlg` annotations already attach a
rendering template to a definition at source (every combinator in
`jl4-core/libraries/negation-as-failure.l4` carries one), so the LE
emitter's hard half is substantially pre-paid. LE therefore sits in the
plan as a rendering layer over the swipl leg (§5.5), sequenced after it.

## 2. The shared middle-end: `L4.Relational`

### 2.1 Position and shape

Follow the house backend pattern — the IR / Lower / Emit triple of
`jl4-core/src/L4/Dmn/{IR,Lower,Emit}.hs` and
`jl4-core/src/L4/OpenFisca/{IR,Lower,Emit}.hs`:

```
                                        ┌──→ L4.Relational.Emit.Swipl    (R1)
 Module Resolved ──→ L4.Relational.Lower ────→ L4.Relational.Emit.Asp    (R2)
 (typechecked)       └─ L4.Relational.IR ───→ L4.Relational.Emit.Le      (R3)
                                        └──→ jl4-proleg print layer      (R4)
```

- **Input:** a typechecked `Module Resolved`, the same input `L4.Dmn.Lower`
  and `L4.OpenFisca.Lower` take. Reuse `carameliseExpr` for desugaring and
  `L4.Viz.GuardedRows.normaliseGuarded` for `IF`/`BRANCH`/`CONSIDER`
  normalisation, as `L4.Dmn.Lower` does (`Lower.hs:120,125`).
- **Output:** a `RelProgram` — typed predicates, Horn clauses, a signed
  dependency graph, and provenance (`Unique` + `SrcRange` per clause, so a
  target-side answer can be lifted back to a citation).
- **Fidelity:** every deviation is a located `FidelityNote`, reusing
  `L4.Interchange.Fidelity` exactly as the DMN exporter does. The emitted
  program must never say something the L4 does not; anything unlowerable is
  rejected with a diagnostic, following the OpenFisca precedent
  (`jl4-core/src/L4/OpenFisca/Lower.hs:1-9`).

Whether the IR and Lower live in `jl4-core` (house pattern) or a separate
package (the `jl4-proleg` pattern: zero `jl4-core` dependence) is LP-R1.

### 2.2 The core transformation: ANF + output argument + modes

A `DECIDE`/`MEANS` of type `τ₁ → … → τₙ → τ` becomes a predicate of arity
n+1, its last argument the result. Nested calls are flattened through fresh
variables (A-normal form):

```l4
GIVEN loan IS A Loan
GIVETH A NUMBER
`monthly payment` loan MEANS payment WHERE ...
```

```prolog
monthly_payment(Loan, Payment) :- ...
```

A `BOOLEAN`-valued predicate may drop the output argument and become a plain
goal (the DMN exporter's "boolean column" move, in reverse). Guarded rows
lower one clause per row. **Negated guard prefixes are materialised**: row
_i_ of a `BRANCH` fires iff its own guard holds and no earlier guard did;
DMN's hit-policy `First` carries that quantifier implicitly
(`L4/Dmn/Lower.hs:24-30` records that it deliberately does _not_ materialise
the prefixes), but Horn clauses have no hit policy, and clause order is not
semantics we may rely on across four targets — in ASP it is nothing at all.
So each clause for row _i_ conjoins `⋀_{j<i} ¬gⱼ`. A swipl-only peephole
that restores clause order + cut is LP-R2; the IR itself stays
order-independent.

**Modes.** v1 fixes a single mode: all `GIVEN` positions input, result
output — the forward mode, which is what differential validation needs.
Mercury-style multi-mode declarations (and with them backward and abductive
queries as a supported surface, not just a Prolog-native accident) are
deferred: LP-R8.

### 2.3 Data representation

| L4 construct                                                        | Relational image                                                                                                                                                                                                            |
| ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DECLARE … IS ONE OF` (enum)                                        | atoms, one per constructor                                                                                                                                                                                                  |
| `DECLARE … HAS` (record)                                            | one functor term per record type; projection = unification against the term                                                                                                                                                 |
| Constructor with payload                                            | compound term                                                                                                                                                                                                               |
| `LIST OF τ`                                                         | Prolog/ASP list                                                                                                                                                                                                             |
| `MAYBE τ` (general)                                                 | `just(T)` / `nothing` terms                                                                                                                                                                                                 |
| `MAYBE BOOLEAN` under `holds`/`naf`/`presumed`                      | **erased into the target's negation** — §3.4                                                                                                                                                                                |
| `NUMBER` (`Rational` per `L4.Syntax` `NumericLit`, `Syntax.hs:401`) | swipl rationals / s(CASP) CLP(Q); on clingo see §5.2                                                                                                                                                                        |
| `STRING`                                                            | atom (quoted)                                                                                                                                                                                                               |
| Inert text (`Inert`, `Syntax.hs:327`)                               | erased to its context identity (`TRUE` in AND-context, `FALSE` in OR-context), as the evaluator does. Without this the entire inert-style corpus (e.g. `paper/case-studies/charities-jersey-2014/`) is out of the fragment. |

Names: reuse the two-stage fold-then-uniquify discipline of the DMN
exporter's `NameEnv` (per-name fold is non-injective; a per-module scope
makes it injective; references are looked up, never re-folded).

### 2.4 What lowers, what defunctionalises, what is rejected

**In the v1 fragment:** first-order `DECIDE`/`MEANS` over booleans, numbers,
strings, enums, records, lists, `MAYBE`; `IF`/`BRANCH`/`CONSIDER` with
patterns; `WHERE`/`LET` locals (lambda-lifted to auxiliary predicates with
the enclosing `GIVEN`s threaded through); recursion (logic programs are the
native home of recursion — but see LP-R7 on termination and tabling);
`#EVAL`/`#ASSERT` directives over the above (they become the differential
harness's queries).

**Defunctionalised, not general:** saturated calls to the known prelude
higher-order functions — `map`, `filter`, `all`, `any`, `foldr`, `elem`
(`jl4-core/libraries/prelude.l4:38-465`) — with a lambda or named-function
argument specialise to fresh first-order predicates at each call site
(Reynolds defunctionalisation). General lambda-passing, partial
application, and functions stored in data are **rejected** in v1 with a
diagnostic naming the site. This is the honest boundary: it is where the
typed-functional/relational impedance actually bites.

**Rejected in v1, by constructor** (all in `jl4-core/src/L4/Syntax.hs`):
`Regulative`/`Deonton` (line 251), `Event` (259), `Fetch`/`Env`/`Post`
(260-262, effects), `Record`/`ReadCell` (263, 289, the ledger), `Breach`
(326). The regulative layer's relational image is the event calculus
(`l4-icail.tex:513-515`); it is real, it is not v1 (LP-R9).

### 2.5 The stratification check is part of the middle-end

The appendix's soundness claim for exception-elimination is explicitly
conditional (`l4-icail.tex:1095-1097`): the classical reading of
negation-as-failure is sound _"exactly when the signed dependency graph is
stratified — a condition the transpiler must check, not assume."_ The
middle-end therefore computes the predicate dependency graph, signing an
edge negative when the dependency passes through a negation (`NOT`, a `naf`
/ `presumed` elimination per §3.4, or a materialised guard prefix), and
checks for cycles through negative edges (Apt–Blair–Walker stratification).
The result is part of the IR, because the legs consume it differently:

- **swipl:** a non-stratified program is rejected (or routed to well-founded
  semantics via SWI tabling — LP-R7).
- **ASP:** non-stratification is not an error; it is where multiple stable
  models — the whole point of the leg — come from. The report records it as
  information, not loss.
- **PROLEG / LE:** follow their execution engines (PROLEG's meta-interpreter
  and LE's Prolog target are SLDNF-based): stratified fragment only.

Precedent inside the project: the defeasible-reasoning paper's rule
elaboration likewise demands its rule-dependency order be a strict partial
order and fails on cycles (§8.2.1). And
[NEGATION-AS-FAILURE-SPEC.md](../done/NEGATION-AS-FAILURE-SPEC.md) (lines
154-157) deliberately stopped short of well-founded/stable-model semantics —
the Kleene lift is "the road to" them, not an arrival. This spec is where
the rest of that road gets built: stratified NAF on the swipl leg, stable
models on the ASP leg, WFS optionally via tabling (LP-R7).

## 3. Semantic keystones

### 3.1 The reference semantics is the evaluator

Differential ground truth is `#EVAL`/`#ASSERT` under
`L4.EvaluateLazy`. Note one asymmetry we must not paper over: L4 evaluation
is lazy and can be partial (a guard that would divide by zero is never
reached under `BRANCH` short-circuiting), while a logic program evaluates
goals wherever resolution takes it. The DMN exporter records the same
divergence and its non-detectability (`L4/Dmn/Lower.hs:61-75`). Same policy
here: total, pure guards are exact; partiality is a documented, undetected
residual risk.

### 3.2 Functions become relations that are still functions

The forward mode of a lowered `DECIDE` must be deterministic: for ground
inputs, exactly one answer, equal to the evaluator's. Guarded-row clauses
with materialised prefixes are mutually exclusive by construction, so the
determinism obligation is discharged structurally, and the differential
harness (§6) enforces it empirically (`findall` must yield exactly one
result in swipl; exactly one literal per queried atom in every answer set
on the stratified fragment).

### 3.3 Closed world at the eliminator, not the type

L4's negation-as-failure design puts the epistemics in the eliminator
(`fromMaybe FALSE`), not the type
([NEGATION-AS-FAILURE-SPEC.md](../done/NEGATION-AS-FAILURE-SPEC.md)). The
lowering must respect that: the same `MAYBE BOOLEAN` datum can be read
closed-world (`holds`) or open-world (`presumed`) at different sites, so no
single data-level translation of the value is correct.

### 3.4 Lowering the `negation-as-failure` library — the semantic hinge

L4 _reifies_ epistemic state as data (`JUST TRUE` / `JUST FALSE` /
`NOTHING`); logic-programming targets represent it _proof-theoretically_, as
presence or absence of a derivation. The lowering maps between the two by
translating the **eliminators**, special-casing the three combinators of
`jl4-core/libraries/negation-as-failure.l4` by name (precedent: the DMN
exporter's `neMaybePreds` special-cases the prelude's `isJust`/`isNothing`,
`L4/Dmn/Lower.hs:161-162`):

| L4 (`negation-as-failure.l4`) | Facts emitted for an assumed `p` | swipl          | ASP             |
| ----------------------------- | -------------------------------- | -------------- | --------------- |
| `p = JUST TRUE`               | `p_holds.`                       |                |                 |
| `p = JUST FALSE`              | `p_refuted.`                     |                |                 |
| `p = NOTHING`                 | _(no fact)_                      |                |                 |
| `holds p` (lines 16-19)       |                                  | `p_holds`      | `p_holds`       |
| `naf p` (lines 24-27)         |                                  | `\+ p_holds`   | `not p_holds`   |
| `presumed p` (lines 32-35)    |                                  | `\+ p_refuted` | `not p_refuted` |

This is the `Provable`→ASP column of the appendix's correspondence table
(`l4-icail.tex:1490-1499`: `notProven` ↦ `not e`, `resolve` ↦ default
negation) realised as a compiler rule. `MAYBE BOOLEAN` values that are
consumed by anything _other_ than these eliminators (or `isJust`/`isNothing`
/ `fromMaybe`) fall back to the general `just/nothing` term encoding of
§2.3. Whether the eliminator-directed translation is the right primary
design, versus a uniform data-level three-valued encoding, is LP-R3.

## 4. Per-target contracts

Each emitter owes three answers: its **negation policy**, its **arithmetic
story**, and its **explainability story**.

| Target  | Negation                                                                     | Arithmetic                                                    | Explanation                                                       |
| ------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------- | ----------------------------------------------------------------- |
| swipl   | `\+` under SLDNF; stratification checked (§2.5)                              | native rationals; CLP(Q) optional for future backward modes   | none native; provenance-carrying meta-interpreter (R1 stretch)    |
| clingo  | `not` (stable models); stratification informs, not gates                     | **grounding, integers only** — see §5.2                       | answer sets as scenario exhibits; unsat cores for double binds    |
| s(CASP) | `not` goal-directed, no grounding                                            | CLP(Q) constraints over rationals                             | **native justification trees**, in English via `#pred` directives |
| PROLEG  | `exception/2` — burden-bearing defeaters, NAF hidden in the meta-interpreter | integers/atoms in the canonical corpus                        | burden attribution: who loses on which unproven fact              |
| LE      | "it is not the case that" rendering of the Prolog image                      | whatever the underlying engine (Prolog target in all goldens) | the document _is_ the explanation; templates from `@nlg`          |

## 5. Design decisions per leg

### 5.1 swipl (R1)

Emit ISO-leaning Prolog with a small fixed runtime preamble (list helpers if
needed; no cut in generated clauses — LP-R2). Arithmetic via `is/2`; L4
`NUMBER` is `Rational` (`Syntax.hs:401`), which SWI handles natively.
Dates lower as Modified Julian Day integers wrapped in a `date/1` functor
(the daydate library is serial-based; `L4.Dmn.Lower` already imports
`toModifiedJulianDay` for the same purpose). Validation: for every `#EVAL`
in the fragment, run the emitted program under `swipl -g` and compare
against the evaluator's value.

### 5.2 ASP (R2): clingo core, s(CASP) dialect

The natural4-era ASP encoding was **never generated by a compiler** — the
defeasible-reasoning paper's conclusion states the ASP coding "has only been
done manually" (§8.2.1), and natural4's `LogicProgram` modules cover only
the propositional according-to/opposes meta-layer. So this leg has no
predecessor to match; it has a paper semantics to satisfy.

Two dialects from one IR:

- **clingo** for enumeration. Grounding forces the arithmetic decision:
  integers only. Policy (LP-R5): dates as MJD serials are exact; money
  lowers to minor units (cents) exactly when the source amounts are exact
  in minor units, with a `FidelityNote` otherwise; general non-integer
  arithmetic in a clause body **excludes that predicate from the clingo
  image** (located note, program still emitted for the other legs). We do
  not silently round: the DMN exporter's rule — never emit a model that
  says something the L4 does not — applies with full force.
- **s(CASP)** for justification and constraints. Goal-directed, no
  grounding, CLP(Q) rationals, and justification trees that satisfy the
  audit-grade explanation thesis. natural4's `TranslationMode = Prolog |
SCasp` with `IS → #=`, `< → #<`, `=< → #=<`
  (`natural4/src/LS/XPile/Prolog.hs:87,119-127`) is the precedent for the
  operator mapping.

The stratified fragment must yield exactly one answer set agreeing with
swipl and the evaluator (three-way differential). Outside the stratified
fragment, enumeration is the product: each answer set is a consistent
reading, per the legal-models soundness result (§8.2.1).

### 5.3 What ASP does _not_ give us for free

The defeasible paper's `subject_to`/`despite`/`strong_subject_to` layer and
the burden ledger are **meta-theory encoded by hand**, not consequences of
ASP. Burden can be simulated by party-indexed literal conventions
(`l4-icail.tex:1497`: "literals/party"), but nothing checks the convention.
That is exactly the §5.6 argument for PROLEG's construct: burden by
construction beats burden by convention.

### 5.4 PROLEG (R4)

The target syntax is done: `jl4-proleg` parses and prints canonical PROLEG
with a round-trip test-suite (`jl4-proleg/test/Roundtrip.hs`), and
`jl4-proleg/docs/proleg-concrete-syntax.md` fixes the grammar. The emitter's
real problem is where `exception(H, E)` marking comes from, since Mode-B L4
(`… AND NOT E`) has erased defeater identity and burden. Candidate sources
(LP-R6):

1. the `SUBJECT TO` / advice construct of
   [SUBJECT-TO-NOTWITHSTANDING-SPEC.md](../todo/SUBJECT-TO-NOTWITHSTANDING-SPEC.md)
   §6.5, once implemented — the override graph is exactly the exception
   structure, and §5.6 of that spec already anticipates the burden
   annotation;
2. recognising the `Provable`-record idiom of `jl4-proleg/l4/burden.l4`
   (`prove` / `notProven` / `flipBurden` / `resolve`) the way §3.4
   recognises the naf library — `burden.l4` is, in effect, a pinned
   specimen of what a burden-faithful emitter should produce from the lease
   fixture (`jl4-proleg/examples/lease.pl`);
3. an interim `@exception` annotation on conjuncts.

Until one is ruled, the PROLEG leg can emit only the rule layer (heads and
bodies, no `exception/2`) — legal but lossy, and the fidelity report must
say so.

### 5.5 Logical English (R3)

The LE emitter rides the swipl leg: same clauses, rendered through
templates. Template generation consumes `@nlg` annotations where present
(the entire naf library and prelude carry them) and falls back to a
deterministic name-to-words fold where absent, with the natural4 LE goldens
(33 cases) mined as a conformance corpus for template pitfalls (regex
anchoring, `*a x*` variable indicators, ditto/anaphora). Determiner
discipline — first occurrence `a x`, subsequent `the x` — is a
purely emitter-side rendering rule. Which LE implementation is the
reference engine, and how its output is golden-pinned, is LP-R10.

### 5.6 The regulative layer: explicitly deferred

The project's own publications settle where deontics-and-time belong.
_Deontics and Time in Contracts_ (JURIX 2023, §8.2.3) gives the regulative
layer an SOS over timed configurations, implemented in Maude — and notes it
does not yet handle rule override or deontic inconsistency. _Compliance
through Model Checking_ (WAICOM 2022, §8.2.2) shows the payoff of the
timed-automata route: UPPAAL found both the PDPA notify-while-prohibited
race and a deadline deadlock, via CTL queries over clock-bearing automata.
Neither capability is a logic-programming strength; both are already
assigned to the verification-backend portfolio. The event-calculus image of
`Deonton`s (a `HoldsAt`-style transition relation, `l4-icail.tex:1562-1565`)
is the correct future meeting point of that spec and this one — ruled out
of v1 by LP-R9 so that this spec ships a constitutive core instead of
half-shipping two layers.

## 6. Validation strategy

**The differential oracle is the asset.** The corpus in this tree today
(counted 2026-08-12, worktree at `origin/unstable`): 398 `.l4` files under
`jl4/examples/` (268 under `examples/ok/`, 53 under `examples/not-ok/`),
737 `.l4` files repo-wide, 1,472 `.golden` expectation files. Every `#EVAL`
and `#ASSERT` in a lowerable module is a free test case with a pinned
expected answer.

**`examples/not-ok/` is out of scope, by construction.** Those 53 modules are
front-end rejection tests — misplaced `@export`, type errors, ambiguous
overloads — whose golden output _is_ a diagnostic. The lowering consumes a
typechecked `Module Resolved`, so a module that never typechecks never
reaches it. They are therefore excluded from the census denominator (the
fragment fraction of §6.1 is over `examples/ok/`) and they place no
obligation on any emitter. The one thing they must not do is silently
inflate a coverage figure: the `--report` census counts them in a separate
`not-typechecked` bucket rather than as lowering rejections, because the two
are different failures and conflating them would make the fragment look
narrower than it is.

Mechanism, staged with the legs:

1. **R0 census.** `l4 relational --report FILE` (surface shape is LP-R11)
   lowers a module and reports: in-fragment or not; per-rejection
   constructor counts; not-typechecked; stratified or not.
   Run over the corpus, this yields the _measured_ fragment fraction. Prior
   to measurement we estimate — and this is an estimate, not a claim — that
   between a third and two-thirds of `examples/ok/` lowers in v1: the
   flagship isomorphic corpora (charities, BNA-style boolean/record
   statutes) are in-fragment by design, while deontic, ledger, HTTP, and
   heavy higher-order examples are out by §2.4. The census replaces this
   guess in the same PR that lands it.
2. **R1 harness.** For each in-fragment `#EVAL`/`#ASSERT`: evaluate under
   `jl4` (ground truth), emit swipl, run, compare values under a fixed
   value-encoding contract. Disagreement = lowering bug, surfaced as a test
   failure (the cross-validation stance of
   [VERIFICATION-BACKEND-LOWERING-SPEC.md](VERIFICATION-BACKEND-LOWERING-SPEC.md)).
3. **R2 three-way.** On the stratified fragment, clingo's unique answer set
   must agree with swipl and the evaluator. On s(CASP), additionally check
   the justification tree cites only clauses whose provenance ranges exist
   in the source module.
4. **R4 fixture.** `jl4-proleg/l4/burden.l4` carries four `#ASSERT`s
   (lines 178-181) encoding the Satoh lease judgement **that nothing
   currently runs** — no CI job names `jl4-proleg` and no test consumes
   `burden.l4`. Wire it into the harness as the PROLEG leg's acceptance
   fixture: L4-side asserts pass under `l4`, and the emitted PROLEG
   round-trips through `jl4-proleg`'s parser against
   `jl4-proleg/examples/lease.pl` modulo clause order.

**Engines in CI.** swipl and clingo are not in `flake.nix` today. Add them
to the dev shell; gate the differential suites on engine presence with a
skip-plus-notice, following the `etc/validate-dmn.mjs` precedent of local
evidence that never becomes a build dependency (repo `CLAUDE.md` §1.2).

## 7. Sequencing, with sizes

Order: **R0 → R1 → R2 → R3 → R4.** Rationale: the middle-end unblocks
everything (R0); swipl is the cheapest sound target and stands up the
harness (R1); ASP is the largest new capability — enumeration — and reuses
the harness three-way (R2); LE rides R1's emitter plus `@nlg` (R3); PROLEG
last **not** because its emitter is large — it is the smallest, the front
end already existing — but because its distinctive value is gated on the
LP-R6 ruling, which depends on language work (`SUBJECT TO`) or an idiom
detector that R1-R3 do not need. Shipping PROLEG earlier would mean shipping
it burden-blind, which §1.3 says is the one thing it must not be.

| Stage | Deliverable                                                                   | New code (est.)  | Exit criterion                                                              |
| ----- | ----------------------------------------------------------------------------- | ---------------- | --------------------------------------------------------------------------- |
| R0    | `L4.Relational.{IR,Lower}`, stratification check, `--report` census           | ~2,500-3,500 LOC | census over `jl4/examples` published in-tree; fragment % measured           |
| R1    | swipl emitter + differential harness + CI wiring                              | ~800-1,200 LOC   | 100% agreement on in-fragment `#EVAL`/`#ASSERT` corpus                      |
| R2    | ASP emitter (clingo core, s(CASP) dialect flag), enumeration mode             | ~700-1,000 LOC   | three-way agreement on stratified fragment; ≥1 worked multi-model demo      |
| R3    | LE emitter (templates from `@nlg`), golden suite seeded from natural4 lessons | ~1,000-1,500 LOC | LE documents load in the reference LE engine and answer queries identically |
| R4    | PROLEG emitter over `jl4-proleg`'s AST                                        | ~400-700 LOC     | lease fixture round-trip (§6.4); burden fidelity per LP-R6 ruling           |

Estimates are calibrated against the in-tree backends, counting **code
lines, not file lines** — the distinction matters here because this
codebase comments heavily. `L4/Dmn/Lower.hs` is 6,792 lines but only 3,581
of them are code; 2,787 (41%) are comment, much of it the design-note
haddock this spec cites in §2.2. The OpenFisca triple (`IR` 147, `Lower`
826, `Emit` 304 file-lines) is smaller. The natural4 LE transpiler was
~2,400 lines with the template problem unsolved at source. Read the table
above as code lines on the same basis; a reviewer comparing it against
`wc -l` on an existing backend will otherwise conclude the estimates are
half what they should be.

## 8. Prior art

### 8.1 In this tree

- **`jl4-proleg`** — PROLEG reader/printer (`Syntax`/`Parser`/`Print`), the
  `Provable` burden monad (`Burden.hs`), `burden.l4`, and the lease/duress
  fixtures. Its library depends on `base`, `text`, `transformers` only — no
  `jl4-core` (`jl4-proleg/jl4-proleg.cabal`), so it contains no transpiler
  in either direction despite its synopsis (cleanup, §9). It is in
  `cabal.project` (line 10) but named by no CI workflow.
- **The ICAIL appendix** (`paper/icail/l4-icail.tex:1025-1585`) — canonical
  PROLEG, the two translation modes, the clause-by-clause lease walkthrough,
  type reconstruction as a linter over the PROLEG corpus (misspelt defeaters
  that untyped Prolog accepts silently), the burden monad
  `MaybeT (Writer [Obligation])`, presumption as monoidal identity, the
  three-faces correspondence table, and proof actions over an event-sourced
  factbase.
- **The DMN and OpenFisca backends** — the IR/Lower/Emit house pattern,
  `FidelityNote` discipline, `NameEnv` naming, `GuardedRows` reuse.

### 8.2 The project's own publications

1. **Lim, Mahajan, Strecker & Wong, _Automating Defeasible Reasoning in
   Law_** (GDE workshop @ ICLP 2022; arXiv:2205.07335;
   `ink.library.smu.edu.sg/cclaw/1`). `subject to`/`despite` rule modifiers
   over (baby-)L4 rules; two semantics: classical — rule rewriting plus
   _inversion formulas_ (a Clark-completion analogue) discharged by SMT,
   requiring the rule-dependency order to be a strict partial order — and
   ASP — axioms A1-A7 defining _legal models_, an encoding via
   `according_to` / `opposes` / `defeated` / `legally_valid` /
   `not_legally_valid`, and the soundness lemma answer sets ⊆ legal models.
   Multiplicity is demonstrated (two answer sets for the Rolls/Mercedes
   config) and non-existence acknowledged. Its conclusion records that only
   the classical coding was implemented; **the ASP coding was manual** —
   the compiler this spec proposes is the one that paper lacked.
2. **Mahajan, Strecker, Watt & Wong, _Compliance through Model Checking_**
   (WAICOM 2022; `ink.library.smu.edu.sg/cclaw/3`). PDPA §§26A-E as three
   interacting UPPAAL timed automata; CTL queries expose the
   notify-while-prohibited trace and a 3-day-deadline deadlock. Grounds
   §5.6's deferral: clock-region bugs belong to timed model checkers, not
   to any LP target here.
3. **Watt, Goodenough & Wong, _Deontics and Time in Contracts: An
   Executable Semantics for the L4 DSL_** (JURIX 2023, FAIA 379 pp 119-124,
   doi:10.3233/FAIA230954). SOS over configurations of active rule
   instances with deadline timers; action vs tick transitions; breach
   states; executed and visualised in Maude. Explicitly does not yet
   prioritise/override rules or detect deontic inconsistency — the
   boundary at which a future event-calculus leg (LP-R9) and the
   verification portfolio meet.

### 8.3 natural4, read as negative results

What it got **right**: the isomorphism instinct (Prolog output as "a point
of reference for L4's operational semantics", `Prolog.hs:5-8`); one
parameterised representation for multiple LP targets
(`data LPLang = ASP | Epilog`, type-indexed `LPRule`/`LogicProgram`,
`LogicProgram/Common.hs:24-54`); the sCASP operator mapping; treating
according-to/opposes as a generic defeasibility meta-layer.

What it got **wrong**, each with the receipt:

- **Semantics by pretty-printer.** `bsp2struct`/`bsr2struct`
  (`Prolog.hs:266-276`) flatten a `BoolStruct` body by _prefixing marker
  pseudo-goals_: `Not p` becomes the term `neg` followed by the translation
  of `p`, `Any` becomes a term `or` — conjunction is real Prolog, but
  disjunction and negation are decorative atoms. The output parses as
  Prolog and means nothing. A middle-end with a defined IR semantics makes
  this class of error inexpressible.
- **Ill-formed output shipped until disabled.** Type-declaration clauses
  were "disabled completely because the code generated for enums is
  ill-formed (invalid Prolog)" (`Prolog.hs:160-161`).
- **Garbage-in tolerated.** The sCASP path "produces garbage without mercy
  and warnings" when spreadsheet cell conventions are violated
  (`Prolog.hs:17-31`) — the cost of an untyped front end, and the
  strongest argument for lowering from a _typechecked_ `Module Resolved`.
- **Surface sprawl.** ~30 CLI transpiler modes registered in
  `LS/Lib.hs:440-524`, most bit-rotted; no shared middle-end meant every
  mode re-derived its own fragment of the semantics.
- **Templates by regex.** The LE transpiler's centre of gravity was
  reconstructing natural-language templates from rule text
  (`GenNLAs.hs`, 467 lines; golden cases pinning regex anchoring). jl4's
  `@nlg` moves that information to the source, where it is authored once.

What jl4 **invalidates**: the founding assumption that emission is
pretty-printing. natural4's IR was born relational
(`Hornlike`/`HornClause2`/`RelationalPredicate`); jl4's is a typed lambda
calculus. Nothing transfers but the lessons.

### 8.4 External

- Satoh et al., _PROLEG: An Implementation of the Presupposed Ultimate Fact
  Theory of Japanese Civil Code by PROLOG Technology_ (JURISIN 2010) — and
  the ~2,500-rule corpus validated against bar examinations.
- Kowalski et al., _Logical English_ (CNL 2020/21 and later) — the CNL whose
  execution substrate is the logic program underneath (§1.4).
- Sergot, Sadri, Kowalski, Kriwaczek, Hammond & Cory, _The British
  Nationality Act as a Logic Program_ (CACM 1986) — the ancestor of the
  whole enterprise; its modern echo lives in this tree at
  `jl4/experiments/bna.pl`.
- Clark, _Negation as Failure_ (1978); Gelfond & Lifschitz, stable models
  (1988); Van Gelder, Ross & Schlipf, well-founded semantics (1991); Apt,
  Blair & Walker, stratification (1988).
- Somogyi, Henderson & Conway, _Mercury_ (1996) — mode/determinism
  discipline; Antoy & Hanus, _Curry_ (2010) — the functional-logic bridge
  (both already cited at `l4-icail.tex:503-510`).
- Arias, Carro, Salazar, Marple & Gupta, _s(CASP): Constraint Answer Set
  Programming without Grounding_ (TPLP 2018) — justification trees and
  CLP(Q), the answer to ASP's arithmetic problem.

## 9. Cleanup items this spec inherits

1. **`jl4-proleg.cabal:4`** — synopsis reads "Two-way transpiler between
   canonical PROLEG and L4"; the package is a reader/printer plus burden
   monad. Fix the synopsis now; let R4 earn it back.
2. **`specs/todo/TEMPORAL-MASTER.md:17`** — cites
   `doc/tutorial-code/temporals-bna.pl` and `doc/multitemporals.md`;
   neither path exists. The live Prolog artefact is
   `jl4/experiments/bna.pl`.
3. **`jl4-proleg/l4/burden.l4`** — four `#ASSERT`s no CI runs (§6.4). Wire
   into a test target when R1's harness exists, or sooner via `l4-cli`.

## 10. Open rulings

House convention: numbered so later work can answer and cite them
(`ANSWERED <date>, see §n` when ruled).

- **LP-R1 (home of the middle-end).** `L4.Relational.{IR,Lower}` inside
  `jl4-core` per the Dmn/OpenFisca pattern, or a separate `jl4-relational`
  package per the plug-in-seam backlog? Leaning: `jl4-core` for IR+Lower
  (they need the whole front end); emitters may live per-target. OPEN.
- **LP-R2 (clause order vs materialised prefixes).** IR materialises
  `⋀_{j<i} ¬gⱼ` (ruled in §2.2, load-bearing for ASP). Open half: may the
  swipl emitter peephole back to clause order + cut, and if so does the
  differential harness test both forms? OPEN.
- **LP-R3 (MAYBE BOOLEAN translation).** Eliminator-directed erasure (§3.4)
  vs uniform data-level three-valued encoding. Eliminator-directed is
  proposed; the data-level alternative is simpler but forfeits native
  negation in the target, which costs both idiom and s(CASP)
  justification quality. OPEN.
- **LP-R4 (ASP engine of record).** clingo (robust, packaged, enumeration)
  vs s(CASP) (arithmetic, justifications) as the CI-gating engine; the
  other becomes advisory. OPEN.
- **LP-R5 (ASP numerics).** Confirm §5.2's policy: serial dates exact;
  money in minor units when exact; otherwise exclude-with-note on the
  clingo leg. Alternative: reject any non-integer arithmetic outright. OPEN.
- **LP-R6 (source of `exception/2` marking).** `SUBJECT TO` construct vs
  `Provable`-idiom recognition vs interim `@exception` annotation (§5.4).
  This ruling gates R4's burden fidelity. OPEN.
- **LP-R7 (non-stratified programs on the swipl leg).** Reject, or emit
  `:- table` / `tnot` for well-founded semantics? WFS and stable models
  disagree on some programs, which would break the three-way differential;
  if tabling is adopted, the harness must scope WFS-vs-ASP comparison to
  the stratified fragment. OPEN.
- **LP-R8 (modes).** v1 is forward-mode only. When multi-mode arrives,
  Mercury-style declarations inferred or annotated? What surface exposes
  backward/abductive queries (`which facts, if changed, would flip this
decision?`)? OPEN.
- **LP-R9 (regulative layer).** Confirmed out of v1 scope (§5.6). The
  future event-calculus leg must refine the JURIX 2023 SOS and coordinate
  with VERIFICATION-BACKEND-LOWERING's ASP stratification. OPEN as to
  timing, not as to exclusion.
- **LP-R10 (LE reference engine).** Which Logical English implementation
  pins the golden suite, and does the harness execute LE documents or only
  diff them textually? OPEN.
- **LP-R11 (CLI surface).** R0's census and every emitter need a user-facing
  entry point, written above as `l4 relational --report FILE`. That shape is
  a placeholder, not a ruling: it is a new top-level subcommand on a surface
  this spec does not own. Options: one `l4 relational` subcommand with a
  `--target` flag (swipl / asp / scasp / le / proleg), one subcommand per
  target in the manner of the existing exporters, or a report-only flag on
  an existing command with emission arriving later. natural4's ~30
  independently-registered transpiler modes (§8.3, "surface sprawl") are the
  cautionary precedent for the per-target option. Whoever owns the `l4`
  subcommand surface rules this before R0 lands. OPEN.

## References

1. Satoh, K. et al. (2010). "PROLEG: An Implementation of the Presupposed
   Ultimate Fact Theory of Japanese Civil Code by PROLOG Technology."
   _JURISIN 2010_.
2. Lim, H.K., Mahajan, A., Strecker, M., Wong, M.W. (2022). "Automating
   Defeasible Reasoning in Law." _GDE @ ICLP 2022_; arXiv:2205.07335.
3. Mahajan, A., Strecker, M., Watt, S.J., Wong, M.W. (2022). "Compliance
   through Model Checking." _WAICOM 2022_.
4. Watt, S.J., Goodenough, O., Wong, M.W. (2023). "Deontics and Time in
   Contracts: An Executable Semantics for the L4 DSL." _JURIX 2023_, FAIA
   379, 119-124. doi:10.3233/FAIA230954.
5. Kowalski, R., Dávila, J., Sartor, G., Calejo, M. (2021+). "Logical
   English for Law and Education."
6. Sergot, M.J., Sadri, F., Kowalski, R.A., Kriwaczek, F., Hammond, P.,
   Cory, H.T. (1986). "The British Nationality Act as a Logic Program."
   _CACM_ 29(5).
7. Clark, K.L. (1978). "Negation as Failure." In _Logic and Data Bases_.
8. Gelfond, M., Lifschitz, V. (1988). "The Stable Model Semantics for Logic
   Programming." _ICLP_.
9. Van Gelder, A., Ross, K., Schlipf, J. (1991). "The Well-Founded
   Semantics for General Logic Programs." _JACM_ 38(3).
10. Apt, K., Blair, H., Walker, A. (1988). "Towards a Theory of Declarative
    Knowledge." In _Foundations of Deductive Databases and Logic
    Programming_.
11. Somogyi, Z., Henderson, F., Conway, T. (1996). "The Execution Algorithm
    of Mercury." _JLP_ 29(1-3).
12. Antoy, S., Hanus, M. (2010). "Functional Logic Programming." _CACM_
    53(4).
13. Arias, J., Carro, M., Salazar, E., Marple, K., Gupta, G. (2018).
    "Constraint Answer Set Programming without Grounding." _TPLP_ 18(3-4).
14. Reynolds, J.C. (1972). "Definitional Interpreters for Higher-Order
    Programming Languages." (defunctionalisation)
