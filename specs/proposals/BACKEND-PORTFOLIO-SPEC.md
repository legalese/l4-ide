# Backend Portfolio Specification

_Status: **coordination document, proposal.** Written 2026-08-16 on branch
`mengwong/backend-portfolio`, the day three transpiler bridges (Blawx, Catala, DocAssemble) went
into simultaneous flight alongside the shipped backends. This document owns the **cross-backend
invariants** (§4) and the **census/coverage map** (§2–§3). It does **not** own per-target or
per-family rulings — those stay with their owning specs and are indexed here (§6). Census rows are
dated pointers to owning artifacts, not independent claims: verify state at the pointer, and when
a state changes, update the row in the same PR that changes it._

**One-line summary.** No single backend consumes all of L4; the portfolio jointly does — execution
targets take the constitutive core, interaction targets add strings and defaults, reasoning
targets add defeasibility and multiplicity, verification targets are the only consumers of the
regulative and temporal layers jointly, and interchange/documentation targets carry the results to
standards bodies and readers — so L4's role is the hub, each bridge doubles as an
expressive-domain probe, and this document is the map, the shared invariants, and the collision
plan.

**Evidence legend.** **[E]** = read out of the named file/PR at the named date; **[U]** = believed
true, not re-verified here. Tree facts verified against `unstable` at `8af7d332`, 2026-08-16.

---

## 0. Ruling status

| ruling | state        | detail                                                    |
| ------ | ------------ | --------------------------------------------------------- |
| P1     | **PROPOSED** | this doc owns cross-backend invariants; specs cite it, §4 |
| P2     | **PROPOSED** | six-family taxonomy, §1.1                                 |
| P3     | **PROPOSED** | one shared exportable-core definition in code, §5         |
| P4     | **PROPOSED** | double-covered seams S1–S5 assigned owners, §7            |
| P5     | **PROPOSED** | collision & sequencing protocol, §8                       |

## 1. The thesis

A corporation — and a statute book — is the sum of its rules; the system of record for those rules
must speak to every downstream consumer in that consumer's language. The programme's answer is
hub-and-spoke: L4 is the single formalisation, and each backend is a projection into an ecosystem
that already has users, semantics, and tooling. Three consequences organise this document:

1. **Complementary coverage is the design, not an accident.** Each target family consumes a
   different slice of L4 (§3). The union approaches the whole language; the intersection — the
   _exportable core_ (§5) — is the fragment every execution bridge must handle identically.
2. **Every bridge is an expressive-domain probe.** Each `X-EXPORT-SPEC` maps L4's boundary against
   one neighbour. The asymmetries repeat: two independent targets (Catala's exception DAG, Blawx's
   defeat triples) implement the defeasibility that L4's `SUBJECT-TO-NOTWITHSTANDING-SPEC.md`
   proposes — target-side evidence flowing back into L4 language design (§3.1).
3. **Shared invariants must have one owner.** The architecture pattern, oracle direction, claim
   ladder, and harness posture have been independently restated in at least four documents (§4).
   Restatement is how drift starts; this document takes ownership (P1).

### 1.1 The six families (P2)

| family            | question it answers      | targets                                                                     |
| ----------------- | ------------------------ | --------------------------------------------------------------------------- |
| **execution**     | run the law              | OpenFisca, Catala, MLIR/WASM                                                |
| **interchange**   | hand the law to a system | DMN, BPMN, JSON schema                                                      |
| **interaction**   | ask the citizen          | DocAssemble, Blawx (front half), web wizards                                |
| **reasoning**     | query and explain        | swipl, ASP/clingo (s(CASP) dialect), PROLEG, Logical English                |
| **verification**  | prove or refute the law  | Z3, Alloy, TLA+, NuSMV/nuXmv, UPPAAL, TAPAAL, SPIN, Maude; future Lean, F\* |
| **documentation** | show the law             | Markdown, NLG/TNR round-trip, ladder diagrams, literate weave, state-graph  |

Blawx deliberately straddles interaction and reasoning: its reasoner is s(CASP) (the reasoning
family's dialect) while its value proposition is the ontology/scenario/NLG front end
(interaction). See seam S2.

## 2. Census

States: **SHIPPED** (in-tree, tested), **SPEC** (design PR open), **IN FLIGHT** (session drafting),
**PROPOSED** (family spec exists, no code), **FUTURE** (named, no spec). All rows dated 2026-08-16.

### 2.1 Execution

| target      | state                                                                                                                                                                                                                                                                                                                                          | owning artifact                                                                                          |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| OpenFisca   | **SHIPPED** v1 + executed round-trips **[E]**                                                                                                                                                                                                                                                                                                  | `jl4-core/src/L4/OpenFisca/{IR,Lower,Emit}.hs`; `l4 openfisca`; `jl4/examples/openfisca/L4-OPENFISCA.md` |
| Catala      | **SPEC MERGED, IMPL OPEN** — spec PR #260 merged 2026-08-16 (R1–R11 ANSWERED; R4 REVERSED to Mode-B-primary, `219281c2`); implementation PR #266 open, next through the seam per §8: `L4.Catala.{IR,Lower,Emit,Equivalence}` + `l4 catala`, validated vs real catala 1.2.1 (typecheck+proof ×8, `clerk test` 64/64, `jl4-test` 2568/0) **[E]** | merged PR #260; open PR #266                                                                             |
| MLIR / WASM | **SHIPPED** in-tree (parity ledger) **[E]**                                                                                                                                                                                                                                                                                                    | `jl4-mlir/`                                                                                              |

OpenFisca is the only backend in any family that consumes the **temporal** layer today (dated
`formula_YYYY_MM` overrides lowered from year-guarded `BRANCH`) **[E]**. Catala is the only one
whose numeric model matches L4's exact rationals, which is why its round-trip claims can demand
equality rather than tolerance **[E]** (PR #260).

### 2.2 Interchange

| target      | state                                                                                                                                | owning artifact                                                                                                                        |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| DMN         | **SHIPPED** through Phase 3; BKM Phases 4/5 planned **[E]**                                                                          | `jl4-core/src/L4/Dmn/{IR,Lower,Emit,Markdown}.hs`; `l4 export --to=dmn\|dmn-md`; `specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md` (R1–R8) |
| BPMN        | **SHIPPED**; wired to DMN via `businessRuleTask` (PR #198) **[E]**                                                                   | `jl4-core/src/L4/Bpmn/{IR,Lower,Emit}.hs`, fed by `L4.StateGraph`; `l4 export --to=bpmn`                                               |
| JSON schema | **SHIPPED** (service export surface)                                                                                                 | `jl4-service` / `l4 export`                                                                                                            |
| LegalRuleML | **FUTURE** — researched 2026-08-16; verdict: viable as a publication-and-provenance artifact, NOT an interoperability bridge **[E]** | `specs/research/LEGALRULEML-RESEARCH.md`                                                                                               |

BPMN is the one shipped consumer of the **regulative** layer: it lowers the deontic state graph
(`L4.StateGraph`) into process XML **[E]** (`jl4/app/L4/Cli/Export.hs:10-11`). Known DMN gaps
(FEEL date lowering, exporter conformance) are tracked in the DMN spec and upstream issues, not
here.

LegalRuleML (OASIS Standard, 2021-08-30) was researched 2026-08-16 —
`specs/research/LEGALRULEML-RESEARCH.md` pins every claim here. The remembered shape partly
survived: it IS the first interchange candidate for the near-empty strata, but as a
**publication-and-provenance artifact, not an interoperability bridge** — every reasoner that
consumed it is dead (Regorous HTTP 410, SPINdle 2017, TC repo frozen 2020-07) and the standard is
deliberately semantics-free. CLEAN mappings **[E]**: directed deontic operators with `Bearer`
slots (`PARTY p MUST`); `SuborderList` = Governatori & Rotolo's ⊗, an exact `LEST` cascade;
`TemporalCharacteristic` in-force/efficacy pins (`EVAL … UNDER RULES EFFECTIVE AT` restated in
the standard's own motivating example); `Alternatives` (the ambiguity register — flagship fit);
`LegalSources`/`Association` with Akoma Ntoso conventions (`@ref`/`@ref-map`). OUT: `WITHIN`
deadlines, `HENCE` success continuations, `RAND`/`ROR`, `#TRACE`, effects. The constitutive core
is relational there, so an emitter sits downstream of #258's `L4.Relational`. Day-one validation
gate verified: stock `xmllint` passes all 30 shipped goldens offline; the honest strongest claim
is schema-valid + conformance-clause-conformant + structurally faithful — there is no round-trip
tier, and any "LegalRuleML support" claim is about a file format, never a running system. Its
`Override` + strength trio is now cited as the third defeasibility prior-art datapoint in
`SUBJECT-TO-NOTWITHSTANDING-SPEC.md`.

### 2.3 Interaction

| target      | state                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | owning artifact                                           |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------- |
| DocAssemble | **COMPLETE AND MERGED 2026-08-20** — every milestone resolved and in `unstable`: M1 #264+#265 (first bridge through the seam), M2 #267, M4 #268 (`2ac68a15`), M3 #269 (`825dd7cf`). Gates green at merge (build, `l4-cli-test` 317/0, `jl4-test` 2585/0, corpus guard 355 files, headless harness vs docassemble.base 1.10.7). Spec discharged to `specs/done/`. M3 is **DECLINED on its own evidence, not deferred**: measured over 589 decisions, adaptive info-gain ordering beats declaration order by 3.38% of one question, and a compile-time operand sort captures 100.00% of that (0/138 decisions favour the planner) — most L4 legal decisions are flat AND/OR chains (60/75 at the 2 − 2^−(n−1) closed form). Harness at `jl4/measure/`, re-runnable **[E]** | all merged: #264+#265, #267, #268, #269                   |
| Blawx       | **RULINGS ANSWERED + MIDDLE-END UNDERWAY** — spec PR #261 merged 2026-08-16; R1–R14 ANSWERED by Meng, recorded in PR #270 (open, which also opens the `DATE-LIBRARY-SPEC.md` ledger). Per R2 the Blawx session drives the **`L4.Relational` middle-end implementation** (branch `mengwong/l4-relational` off `afcef88f`; findall/aggregate recognition and DNF normalisation live in the middle-end, not the emitter). Per R10 generator-quirk fixes go to the `legalese/blawx` fork. Tier-1 s(CASP) execution green **[E]**                                                                                                                                                                                                                                             | PRs #261 (merged) + #270; branch `mengwong/l4-relational` |
| web wizards | **SHIPPED** (Housing Act, Reg CF; question-ordering PR #94 v1, #110 v2 priors)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | in-tree                                                   |

DocAssemble is the designated consumer of three L4 assets no other bridge can use: `STRING`
(rejected/elided by Catala, absent from Catala's type system), landed metadata-only `TYPICALLY`
(prefill — the interaction-family analogue of Catala's R10 `context` mapping), and the
explicit/unknown/unasked input-state trichotomy (`specs/todo/RUNTIME-INPUT-STATE-SPEC.md`).

### 2.4 Reasoning

| target                                               | state                                                                                 | owning artifact                                      |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| swipl, ASP/clingo (s(CASP)), PROLEG, Logical English | **PROPOSED** — PR #258, one shared middle-end `L4.Relational` + thin emitters **[E]** | `specs/proposals/LOGIC-PROGRAMMING-BACKENDS-SPEC.md` |

PR #258's load-bearing claim: these are not four transpilers but one missing relational lowering
(ANF + output argument + modes) that no code yet implements; natural4's emitters cannot be ported
because its IR was already relational **[E]**. Blawx (PR #261) positions itself as a _fifth
consumer_ of `L4.Relational` rather than a fifth lowering, with one recorded data-representation
divergence (seam S2). The regulative layer is explicitly deferred by #258 §5.6 **[E]**. Update 2026-08-18: the middle-end is now being **implemented**, driven by the Blawx session per Blawx R2 (branch `mengwong/l4-relational`); when it lands, the four LP legs' R0 dependency is satisfied.

### 2.5 Verification

| target                                                                        | state                                                                        | owning artifact                                                                               |
| ----------------------------------------------------------------------------- | ---------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Z3, Alloy 6, TLA+/Apalache, NuSMV/nuXmv, UPPAAL, TAPAAL, SPIN/Promela, Maude  | **PROPOSED** — fan-out design, phased Z3 → Alloy → timed → unbounded **[E]** | `specs/proposals/VERIFICATION-BACKEND-LOWERING-SPEC.md` (elaborates BOUNDED-DEONTICS Phase 2) |
| Lean, F\*                                                                     | **FUTURE** — named here, no spec                                             | this document, §7 S5                                                                          |
| L4-native: `#CHECK`, exhaustiveness oracle, ROBDD, `l4 state-graph`, `#TRACE` | **SHIPPED**                                                                  | in-tree                                                                                       |

The verification family is the **only** family that consumes the regulative and temporal layers
jointly (timed reachability over `DO`/`HENCE`/`LEST` choice points — the letter/spirit gap
search) **[E]**. Its two motivating case studies (the regulatory double-bind, the payout leak) are
the programme's founding war stories.

### 2.6 Documentation

| target                       | state                              | owning artifact                   |
| ---------------------------- | ---------------------------------- | --------------------------------- |
| Markdown                     | **SHIPPED** (`--to=dmn-md` et al.) | in-tree                           |
| NLG / TNR round-trip         | **BRANCH** (`nlg-roundtrip`)       | `jl4-core/src/L4/Nlg.hs` + branch |
| ladder diagrams              | **SHIPPED** Steps 1–3              | ladder-diagrams-2026 programme    |
| literate weave               | **via Catala** (PR #260 P3)        | CATALA-EXPORT-SPEC §4.9           |
| state-graph / LTS visualiser | **SHIPPED** (`l4 state-graph`)     | in-tree                           |

## 3. The coverage matrix

Columns are representative targets; ✓ = consumes, ◐ = partial/planned, — = out (rejected with
diagnostics where the family has a lowering).

| L4 stratum                                  | OpenFisca          | Catala             | MLIR | DMN | BPMN            | DocAssemble | Blawx/LP               | Verification           |
| ------------------------------------------- | ------------------ | ------------------ | ---- | --- | --------------- | ----------- | ---------------------- | ---------------------- |
| exportable core (§5)                        | ✓                  | ✓                  | ✓    | ✓   | —               | ✓           | ✓                      | ✓                      |
| `STRING` computation                        | ◐                  | —                  | ◐    | ◐   | —               | ✓           | ◐                      | —                      |
| `SET OF`                                    | —                  | ◐ emul.            | —    | —   | —               | —           | ◐                      | ◐                      |
| higher-order / recursion beyond combinators | —                  | —                  | ✓    | —   | —               | —           | —                      | ◐                      |
| `TYPICALLY` metadata                        | —                  | ✓ (R10, `context`) | —    | —   | —               | ✓ (prefill) | ◐ (#abducible)         | ◐ (assumption)         |
| `@desc` parameters/scales                   | ✓                  | ◐                  | —    | —   | —               | —           | —                      | —                      |
| temporal (rule versions, dated)             | ✓ (dated formulas) | —                  | —    | —   | —               | —           | —                      | ✓ (planned)            |
| regulative deontics                         | —                  | —                  | ◐    | —   | ✓ (state graph) | —           | — (#258 §5.6 deferred) | ✓ (planned, the point) |
| `#TRACE` / events                           | —                  | —                  | —    | —   | ◐               | —           | —                      | ✓ (planned)            |
| effects / ledger                            | —                  | —                  | —    | —   | —               | —           | —                      | —                      |

Three observations the matrix makes visible:

1. **The effects/ledger row is empty.** `FETCH`/`POST`/`RECORD`/`COMMIT`/`ATTEST`/`RECALL` stay
   home in every direction; only jl4 itself executes them. That is a considered boundary, not a
   backlog item — external systems consume the _results_ of ledgered evaluation via jl4-service.
2. **Regulative + temporal jointly have exactly one consumer family**, and it is the unbuilt one.
   The verification spec is therefore not one more spoke: it is the only planned externalisation
   of the layers that most distinguish L4 from every neighbour in this census.
3. **Defeasibility evidence flows target→L4.** Catala's exception DAG (PR #260 §5.2) and Blawx's
   defeat triples (PR #261 §1.1/§5.2) are independent, battle-tested implementations of what
   `SUBJECT-TO-NOTWITHSTANDING-SPEC.md` proposes; that spec now carries the consolidated
   prior-art pointer (added in this branch, by request of the Blawx session, to avoid three
   sessions editing one file).

## 4. Shared invariants (owned here — P1)

Per-target specs cite these henceforth instead of restating them. Each was previously stated
independently in at least two of: the OpenFisca doc §6, CATALA-EXPORT-SPEC §7/R7/R9, PR #258
§3.1/§6, VERIFICATION-BACKEND-LOWERING-SPEC's harness section, and the Blawx spec.

- **I1 — Architecture pattern.** A forward bridge is `L4.<Target>.{IR,Lower,Emit}` plus a CLI verb
  (or an `l4 export --to=` format for interchange XML), keyed on `@export` via
  `L4.Export.getExportedFunctions`, with `lowerModule :: Module Resolved -> Either [LowerError] …`
  reporting **all** rejections in one batch, each naming the construct and source range.
- **I2 — Oracle direction.** `L4.EvaluateLazy` is the reference semantics for every backend.
  Every `#EVAL`/`#ASSERT` in a lowerable module is a free differential test case with a pinned
  expected value. Expected outputs in target-side test harnesses are populated **from L4's
  evaluator**, never by accepting the target's own output (self-acceptance inverts the oracle).
- **I3 — The claim ladder.** Three tiers, always distinguished in docs and PR descriptions:
  _golden_ (regression-stability only), _executed round-trip_ (emitted artifact runs in the real
  target toolchain and agrees with L4 on the test population), _law-validated_ (agreement with an
  independent authority: upstream implementation, published worked example, oracle corpus).
- **I4 — Harness posture.** Target-toolchain validation harnesses run when the toolchain is
  present and skip silently when absent; they are never build dependencies and never required CI
  (the `etc/validate-dmn.mjs` posture, now also `catala`'s per PR #260 R9).
- **I5 — Naming.** Specs are `specs/todo/<TARGET>-EXPORT-SPEC.md` (family specs live in
  `specs/proposals/`); identifier mangling folds Unicode (DMN R3 precedent) and documents the
  target's lexical-class mapping in the target spec. Mangling must also route around the
  **target's reserved-identifier namespace, vendored as a set** — the measured hazard: any
  emitted attribute whose sanitised name collides with one of docassemble's 83 `DAObject` method
  names (probed live) is silently pre-satisfied by a truthy bound method, wrong verdict, no
  diagnostic (PR #265 adversarial-review finding). Every bridge owes its target the same probe.
- **I6 — Spec form.** Status header in the present tense with a date; `[E]`/`[U]` evidence marks;
  rulings `R1..Rn` with the measurement → ruling → cost → case-against → not-decided template; a
  ruling-status table at §0.
- **I7 — Priority is compiled away only under a disjointness proof.** Ordered first-match
  constructs (`BRANCH`/`CONSIDER`, DMN FIRST hit policy, Catala exception ladders, LP clause
  order) may be flattened to an unordered form (UNIQUE tables, boolean normal form, Catala
  Mode A) only when arm disjointness is proven or the priority is made explicit in the output.
  The shared implementation is `L4.Viz.GuardedRows` (`normaliseGuarded`/`flattenGuarded`),
  already consumed by DMN's FIRST↔proof-gated-UNIQUE duality with `OTHERWISE` →
  `defaultOutputEntry` (`jl4-core/src/L4/Dmn/Lower.hs:1203,20` **[E]**); Catala's Mode A/B gate
  (PR #260 R4) and #258's "the two readings must agree" are the same seam. Surfaced by the
  catala-bridge session from DMN's implementation, 2026-08-16. Executed at scale in that bridge's adversarial review: 24 findings, 0 refuted — including `OTHERWISE`-reordering and elision-vs-record-equality, both instances of shape compiled away without a proof.
- **I8 — Evaluation order is part of the contract.** L4's `AND`/`OR`/`IMPLIES` are lazy; a
  target with strict connectives turns guard-then-use idioms into runtime aborts if lowered
  naively. Re-encode short-circuit connectives as `if`/`then`/`else` in strict targets, and where
  the target evaluates branches eagerly regardless (Catala's default calculus evaluates every
  ladder rung), any rung whose condition can raise must veto the idiomatic form and force the
  conservative encoding (the Catala bridge's "strictness veto", PR #266). Any strict-boolean
  backend — including our own direct C-family emitters — inherits this hazard class.
- **I9 — No algebraic rewrite without the algebra.** Printers, normalisers and optimisers may
  only apply rewrites the domain's laws actually license. Date addition is non-commutative AND
  non-associative (Monat, ESOP 2024 — who rejected SMT for dates for this reason), so any
  reassociation or reordering of date expressions in any backend or printer is a miscompile.
  This repo has already paid for the boolean cousin of this bug: `prettyConj` dropped a bracket
  and silently changed evaluated answers while every structural test stayed green (l4-ide
  CLAUDE.md §3.2.1). Rewrite passes over non-free algebras carry the burden of proof.
- **I10 — Measure the program you lower, not a normalised cousin.** Several in-tree views
  transform before displaying: `LSP.L4.Viz.Ladder` runs `simplify = cnf . nnf`, so any consumer
  reasoning about evaluation order, cost or pruning over the ladder is reading a _different
  program_ from the one the emitters lower — and CNF distribution can only add demands, so the
  error is one-directional and flatters whatever is being measured (it cost the docassemble M3
  study a wrong headline, 3.58% → 3.38%, caught by adversarial methodology review). Bind every
  measurement and every claim to the exact IR the backend consumes.

## 5. The exportable core (P3)

The intersection fragment every execution/interaction/reasoning bridge consumes: first-order,
non-recursive, total constitutive L4 — records, enums with payloads, `LIST`, `MAYBE`, `BOOLEAN`,
`NUMBER`, `DATE`, `CONSIDER`/`BRANCH`/`IF`/`WHERE`, prelude combinators with literal-lambda
arguments, `@export` entry points over a subject record, `ASSUME`d inputs. Each family then
extends it in its own direction (§3).

**Proposal.** Define fragment membership **once, in code** — working name `L4.Export.Fragment` —
owning reachability from `@export` roots, membership tests, and the batch-diagnostic vocabulary.
Today the OpenFisca lowering implements this privately; PR #260 and PR #261 each specify it again;
PR #258's `L4.Relational` §2.4 specifies its own accept/reject/defunctionalise partition. Three
(soon six) private copies of "what is in the fragment" is exactly the drift §4 exists to prevent —
`L4.Relational` and every `Lower.hs` should _consume_ the shared membership decision and add only
target-specific narrowing. **Cost:** a refactor of shipped OpenFisca code that currently works.
**The case against:** the fragments are _not_ identical per family (DocAssemble keeps `STRING`,
MLIR keeps recursion), so the shared module must express the core plus per-target deltas, which is
more design than three if-statements — and premature abstraction over two shipped + three
in-flight implementations could ossify the wrong boundary. **Not decided:** module name, timing
(before or after the third bridge ships), whether OpenFisca retrofits or grandfathers.

## 6. Ruling cross-index (indexed, not owned)

Analogous per-target rulings, so a session deciding one can see its neighbours. The owning spec is
authoritative; disagreement across a row is fine when the targets genuinely differ, and a drift
bug when they don't.

| concern                 | rulings across the portfolio                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| number lowering         | Catala R2 (decimal-default, money never inferred); OpenFisca (float32, documented caveat); DMN (FEEL number); DocAssemble R6 (`datatype: number`, i.e. Python float — same divergence class as OpenFisca's float32, carried as a per-module Advisory note; `currency` refused outright because docassemble coerces it through `float()`, so it must never carry exact-decimal money). Guidance: exact-by-default, every lossy target documents its loss list.                                                                                          |
| dates                   | Catala R3 (never auto-pick a rounding mode; the Feb-31 three-way divergence); OpenFisca periods; DMN/FEEL date gap (tracked in DMN spec); UPPAAL clocks (verification spec Phase 3). Cross-backend date/duration requirements now accumulate in the `specs/todo/DATE-LIBRARY-SPEC.md` ledger (opened by Blawx R8, PR #270) — add a subsection there; never satisfy a date requirement silently.                                                                                                                                                        |
| name mangling           | DMN R3 (fold, not keep) — adopted portfolio-wide as I5.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `TYPICALLY`             | Catala R10 (`context`); DocAssemble prefill (spec `09ac99f8`); Blawx `#abducible` (PR #261); `RUNTIME-INPUT-STATE-SPEC.md` owns the L4-side trichotomy. Landed carrier: PR #92 (metadata-only), consumed by ordering v2 in #110. VERIFIED GAP (2026-08-18): `collectTypicallyDefaults` reads GIVEN binders + ASSUMEs only — record-field `TYPICALLY` never reaches the ordering priors, and house-style GIVEN-record corpora therefore run prior-free; filed as smucclaw#942 (found by docassemble M3, independently verified at `Ladder.hs:331-342`). |
| `STRING`                | Catala R11 (elide with warning); DocAssemble in-domain (owns the only affirmative STRING ruling).                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| defeasibility           | owned by `SUBJECT-TO-NOTWITHSTANDING-SPEC.md`; evidence: Catala §5.2, Blawx §1.1/§5.2 (see §3.3).                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| exhaustiveness severity | L4's oracle WARNS (`PatternMatchesMissing` via `addWarning`, `TypeCheck.hs:1934` at `8af7d332`) where Catala and DMN-UNIQUE ERROR — export lowerings close the gap (warning-as-error inside the fragment, or explicit arms). `@nonexhaustive` IS on `unstable` since the #256 main-merge (`Lexer.hs:83,444-445` at `8af7d332`; checkouts at `fe8d37d3`-or-earlier lack it): it silences only the missing-branch warning, i.e. author-declared partiality — which lowerings can honour by emitting explicit `impossible` arms (Catala `0dfce71c`).      |
| tests/oracle            | I2/I3 here; instances: OpenFisca `roundtrip_check.py`, Catala R7, #258 §6, Blawx (PR #261).                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| CLI verb surface        | #258's ruling on LP verbs; Blawx defers to it; execution bridges use one verb each (I1).                                                                                                                                                                                                                                                                                                                                                                                                                                                               |

## 7. Double-covered seams (P4)

Places where two documents could plausibly own the same design. Proposed owners; each needs
sign-off from both sides' specs in their next revision.

- **S1 — PROLEG.** Covered as #258's fourth leg _and_ by standalone branches
  (`origin/claude/aug2026-proleg`, `origin/mengwong/proleg-scaffold`) with a two-way ambition.
  **Proposed:** #258 owns the forward lowering (it is one emitter over `L4.Relational`); the
  PROLEG branches own reverse-direction and scaffold work. Needs a reconciliation note in both.
- **S2 — s(CASP)/Blawx.** #258 §5.2 treats s(CASP) as its ASP dialect; PR #261 consumes s(CASP)
  through the Blawx application. **Resolved by PR #261's own positioning** (fifth consumer, not
  fifth lowering), with one recorded divergence: Blawx lowers records to ontology predicates
  (category + per-field attributes) rather than #258 §2.3's functor terms, because functor terms
  are invisible to Blawx's scenario editor/NLG/ontology API — the reasons to target Blawx at all
  **[E]**. #258 should acknowledge the divergence so its data-representation section doesn't
  read as portfolio-universal.
- **S3 — Z3, two routes.** Direct SMT lowering (verification spec Phase 1) vs. Z3 via Catala's
  proof plugin over emitted code (PR #260 §4.11, P4). **Both stand** — they prove different
  things (L4-level properties vs. emitted-artifact properties); any claim must cite its route. Disclosed-open (Catala spec §8.4): the standing equivalence grid verifies a re-derived rendering, not the emitted text itself; closing that gap needs solver-derived witnesses over the emitted artifact — future work on this seam's emitted-artifact route.
  Updated 2026-08-17 from the catala-bridge session's solver-landscape review (commissioned by
  Meng): the route-2 ceiling is now hard fact — catala-proof's VC kinds are exactly
  `NoEmptyError | NoOverlappingExceptions` and scope assertions enter as _hypotheses_
  (`conditions.ml:278`, `conditions.mli:36` @ `d37aca74`, independently corroborated), so user
  invariants are unprovable on route 2, period. Route 1 has a PROPOSED shape — un-ruled, not a
  commitment: `l4 prove`, reusing `L4.Catala.Lower`'s fragment classification, emitting SMT-LIB2
  text to a z3 subprocess (no Haskell dependency; `NUMBER`→`Real` is faithful since values are
  exact rationals), flagship application proving Mode A ≡ Mode B to close CATALA-EXPORT-SPEC
  §8.4's witness gap. Footnote technologies: CUTECat (ESOP 2025) checks assertions as _goals_ via
  concolic execution, but is an unmerged fork pinned to Catala 0.10.0 with lists and month/year
  dates silently falling back to concrete; DateSAT is the candidate date-encoding fix.
- **S4 — prose, two producers.** Logical English (#258, a surface over the Prolog image) vs.
  TNR/NLG round-trip (branch `nlg-roundtrip`). Different fidelity contracts (executable surface
  vs. drafting prose); both stand; cross-cite.
- **S5 — Lean/F\* (future provers).** In no spec today. Two notes so the eventual spec starts
  ahead: Catala's kernel is formalised in F\*, so an indirect L4→Catala→F\* path exists in
  principle **[E]**; and the verification spec's fan-out principle (choose the tool by the
  question) applies — mechanised provers answer _metatheory and deep-correctness_ questions no
  model checker reaches. A future `PROVER-BACKENDS-SPEC` would join the verification family.

## 8. Collision and sequencing protocol (P5)

- **Docs-only spec PRs are parallel-safe** and should stay docs-only (the three bridge specs and
  this document all are).
- **Implementation hotspots:** `jl4/app/Main.hs` (verb table), `jl4.cabal`/`jl4-core.cabal`
  (module lists), shared golden directories. The footprint is named precisely (per the
  DocAssemble M1 measurement, 2026-08-16): the **OpenFisca five-edit shape** — Main.hs import,
  `Command` constructor, subparser entry, dispatch arm, `jl4.cabal` other-modules — plus three
  `exposed-modules` lines in `jl4-core.cabal`. Every bridge touches the same lines; conflicts are
  trivial and named in advance, and the second and third implementers should expect exactly these
  on rebase. First two implementation PRs: sequence through the
  SEQUENTIAL merge queue with rebases. If a third lands in the same window, that is the forcing
  function for the backend-registration seam already on the backlog
  (extension/plug-in architecture), and the seam PR goes first.
- **Assigned merge order (provisional, 2026-08-16; hardens when P5 is signed off):**
  implementation PRs merge in readiness order — **DocAssemble** (#264 spec → #265 impl) →
  **Catala** (#260 spec → #266 impl) → **Blawx** (gated on #258-R0 or its private-subset
  contingency, plus tier-2 infra). Both finished implementations are stacked on their spec
  PRs; merge each spec first so the implementation enters the queue spec-free.
  Later arrivals rebase over earlier merges. If a third implementation PR is open while two are
  queued, the backend-registration seam goes first and all three rebase onto it.
- **Dependency-direction constraint** (from the DocAssemble spec's M3): `jl4-query-plan` depends
  on `jl4-core`, so a backend in `jl4-core` cannot import the compiled question plan — backends
  wanting it compose in `jl4/app` (the `jl4-wasm` precedent). Bridges consuming question ordering
  (DocAssemble, wizards) inherit this shape; the proposed lift of the duplicated
  `vizExprToBoolExpr` glue into `jl4-query-plan` is owned by the DocAssemble spec.
- **Session mechanics:** each bridge session keeps its spec's status header true and its memory
  file current; this census updates in the same PR as any state change it reports (see the
  status-header charge at the top of this document).
- **Cite pinning:** evidence cites name a commit and are read via `git show <commit>:<path>` —
  never a working tree, including the reference checkout, which may lag or lead (this bit three
  sessions on 2026-08-16 — a correction, a self-audit, and, within hours of this rule being
  written, this document's own §6 row — every one a `fe8d37d3` working-tree read masquerading as
  an `8af7d332` fact).
- **One file, one editor:** cross-cutting files (`SUBJECT-TO-NOTWITHSTANDING-SPEC.md`, this
  document) are edited through the portfolio session while multiple bridge sessions are live, by
  the convention established 2026-08-16 (the Blawx session routed its prior-art pointer here
  rather than editing directly).

## 9. Non-goals

This document does not own per-target rulings (§6 is an index); does not decide L4-side language
changes (defeasibility belongs to SUBJECT-TO, temporal to the TEMPORAL series); does not replace
the two family specs it indexes; and does not schedule the FUTURE rows (Lean/F\*) beyond naming
them.

---

_Programme journal, 2026-08-16: three bridge sessions in simultaneous flight (Blawx → draft
PR #261; Catala → draft PR #260; DocAssemble → spec drafting), coordinated from the portfolio
session that wrote this document. PR #258 (LP family) and the in-tree verification spec predate
them. This paragraph is a snapshot for archaeology, not a live status board — the census above is
the maintained surface._
