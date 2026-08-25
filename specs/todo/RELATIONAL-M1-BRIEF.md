# L4.Relational M1 — implementation brief

_Working brief for the M1 implementation pass, 2026-08-18. Authority chain:
`specs/proposals/LOGIC-PROGRAMMING-BACKENDS-SPEC.md` (the middle-end's design, PR #258),
`specs/todo/BLAWX-EXPORT-SPEC.md` (the driving consumer, R1–R14 ANSWERED — R2 rules that Blawx
drives this implementation and that findall/DNF live here, not in emitters). This file is the
coordinator's cut-down of both for the implementing agents; where it conflicts with either
spec, the spec wins and the conflict is a finding to report._

## What M1 delivers

`jl4-core/src/L4/Relational/{IR,Lower,Debug}.hs`, cabal-registered, with golden tests — **no
CLI verb**. PR A is testable entirely through the test suite via the Debug renderer; the `l4`
subcommand surface is deliberately untouched (defers #258's LP-R11, avoids the three-bridge
`Main.hs` collision). The Blawx emitter (PR B) is the first consumer; the swipl/ASP legs are
the next.

## IR design constraints (the load-bearing decisions)

1. **Field access stays abstract.** A projection is a goal (`RProj subj field out`), never a
   committed representation. Emitters choose: functor-term unification (swipl leg, #258 §2.3)
   or attribute-predicate goals (Blawx, BLAWX-EXPORT-SPEC R2 divergence). If Lower commits to
   either, the other family of emitters dies — this is the single most important constraint.
2. **Names are source names + `Unique`s.** No target mangling in the middle-end; each emitter
   mangles to its own lexical class and runs its own collision check (OpenFisca `pyIdent`
   precedent).
3. **Negation is pushed to literals before the IR.** Lower normalises: `NOT` over comparisons →
   complemented operator; `NOT` over boolean structure → De Morgan + DNF; what remains is
   `RNotCall` (negation of a predicate call — the only negation form in the IR). Emitters map
   `RNotCall` to their negation (Blawx applies its own input-vs-computed policy, R5). Never
   emit `neg`/`or` pseudo-atoms — the natural4 named failure mode (#258 §8.3).
4. **One clause per disjunct.** Body normalisation: DNF (aux-predicate factoring above a
   threshold, default 8 disjuncts); `BRANCH` arm _i_ conjoins negations of guards 1.._i−1_
   (materialised prefixes — clause order is not semantics, #258 §2.2); `CONSIDER` over
   payload-free enums → `RMatch var atom` discrimination; `IF/THEN/ELSE` in value position →
   guarded clause pair (guard / literal-complemented guard).
5. **ANF with bind-before-use ordering.** Every nested call/projection becomes a goal binding
   a fresh variable; arithmetic stays as a small expression tree over already-bound atoms in
   `REval out expr` (renders as `Out is Expr`).
6. **Aggregates are recognised here** (Blawx R2 ruling): `sum`/`length`/`min`/`max`/average
   patterns over a (possibly `map`-projected) list → `RFindAll` + `RAggregate`. Recogniser may
   share extraction with `L4.OpenFisca.Lower`'s `aggregation` (Blawx R9: share now, free to
   break loose later — do NOT contort either side to force sharing).
7. **Structural recursion is admitted and marked.** Self-reference with a structurally
   decreasing list argument (the `WHEN EMPTY / WHEN x FOLLOWED BY xs` shape) lowers to a
   two-clause definition and sets a per-predicate `recursion = Structural` marker; any other
   self-reference is a batch `LowerError` in M1 (widening tracks #258 LP-R7).
8. **The signed dependency graph and stratification check are part of the IR** (#258 §2.5):
   edges signed negative through `RNotCall`; Apt–Blair–Walker; result stored, not enforced —
   emitters decide (swipl rejects non-stratified, ASP records, Blawx rejects in v1).
9. **Provenance per clause**: originating `Unique` + `SrcRange`, so target-side answers lift
   back to citations.
10. **Errors accumulate**: `Either [LowerError] RelProgram`, OpenFisca's `errFn`/`errMsg`
    shape and its `constructorName` rejection catalogue as the starting scope statement.

## M1 fragment (scope control)

In: `DECLARE` records and payload-free enums; first-order monomorphic `@export` decisions and
their reachable helpers (`WHERE` lambda-lifted with enclosing `GIVEN`s threaded); `BOOLEAN`/
`NUMBER`/records/payload-free-enums/lists; `AND`/`OR`/`NOT`/`UNLESS`; `IF`/`BRANCH`/
`CONSIDER`; comparisons and `+ - * /`; the recognised aggregates; structural list recursion;
`#EVAL`/`#ASSERT` captured as `RelQuery`s (inputs = flattened record literal, expected = the
directive's value where statically present — the differential harness's seeds).

Out (batch-rejected with named diagnostics): strings beyond literal-equality atoms; dates
(M2 — see `DATE-LIBRARY-SPEC.md` before implementing); enums with payloads; `MAYBE` beyond
`isJust/isNothing/fromMaybe` shapes; general higher-order; non-structural recursion;
`Regulative`/`Event`/`Fetch`/`Post`/`Env`/`Record`/`ReadCell`/`Breach`; `SET OF`;
**boolean-valued calls in value position** (added at close-out by the R2-1 ruling below —
every boolean predicate's output argument is dropped, in both its spellings: a named
decision applied as an argument, and a computed `MEANS` BOOLEAN field, whose desugared
selector is the same shape; witness `not-ok/bool-value-position.l4`).

**Do not narrow silently**: anything in-fragment that fails to lower is a bug, anything
out-of-fragment that lowers is a bug.

## Facts that will bite (verified; do not re-derive)

- After resolution, infix operators arrive as `App` of builtin names (`__PLUS__`, `__AND__`,
  …), NOT the dedicated constructors — handle both, per `L4.OpenFisca.Lower.builtinOp`
  (`Lower.hs:357-373`). `pattern Var ann n = App ann n []`.
- Selection: `L4.Export.getExportedFunctions` (`Export.hs:115`); destructure
  `ef.exportDecide` like OpenFisca does; call `enrichReturnTypes` — Blawx needs return sorts.
- Repo is `-Wall -Werror` with `NoFieldSelectors` + `OverloadedRecordDot`; `-Wname-shadowing`
  is implied by `-Wall`. `Env` is an `Expr` constructor — don't name your environment `Env`.
- Key exemplars to read before writing: `L4.OpenFisca.{IR,Lower,Emit}` (house pattern),
  `L4.Docassemble.{IR,Lower,Emit}` (newest backend, current idioms), `L4.Dmn.Lower`'s use of
  `normaliseGuarded` (`L4.Viz.GuardedRows`) — reuse it for `IF`/`BRANCH`/`CONSIDER`
  normalisation per #258 §2.1 rather than reimplementing.
- Cabal: add the three modules to `jl4-core.cabal` `exposed-modules` (near `L4.OpenFisca.*`).
- Tests: golden tests belong in the existing suites; `jl4/tests-cli` is for CLI (not M1);
  find the jl4-core-level test entry point and follow its registration pattern. Goldens are
  Debug-renderer output over `jl4/examples/relational/*.l4` seed files; negative fixtures
  under `not-ok/`. **Ship goldens in the same commit as the `.l4` files** (repo CLAUDE.md
  §3.1 — but note that trap concerns `jl4-test`'s per-file goldens for files under
  `jl4/examples/`; check whether `jl4/examples/relational/` falls inside `jl4-test`'s corpus
  globs before placing seeds there, and if it does, either generate those goldens too or
  place seeds under a directory the globs do not sweep).
- Build lock: ONE cabal invocation at a time in this worktree. Concurrent builds corrupt
  dist-newstyle with phantom `renameFile` errors.

## Seed corpus (mirrors the Blawx spec's P1 list)

1. `benefit.l4` — the BLAWX-EXPORT-SPEC Appendix A module verbatim (records, OR/UNLESS,
   value-position IF, WHERE helper, comparisons, arithmetic). Expected relational shape is
   worked out in that appendix — the Debug golden should be recognisably the same program.
2. `mortality.l4` — two unary predicates, one rule, one query (minimal).
3. `scores.l4` — a `LIST OF NUMBER` field, sum + length + average via prelude combinators
   (exercises RFindAll/RAggregate).
4. `sumlist.l4` — structural recursion over a list (`CONSIDER … WHEN EMPTY … WHEN x FOLLOWED
BY xs`) — the construct Catala must reject and we admit.
5. `not-ok/deontic.l4`, `not-ok/higher-order.l4`, `not-ok/nonstructural.l4` — named
   rejections, all errors reported in one batch.

Each seed carries `#EVAL`s; their L4-evaluator values are the future differential oracle —
record them as comments beside the directives.

## Definition of done (M1)

`cabal build jl4-core` clean under `-Werror`; test suite green including new goldens; the
Debug render of `benefit.l4` inspected by a human-equivalent reviewer against Appendix A of
the Blawx spec; stratification check demonstrated on a negative fixture with a
through-negation cycle; no changes outside `jl4-core` + examples + tests.

## Addendum 2026-08-18 (post-launch, from portfolio invariants — binding)

- **I8 (laziness).** L4 connectives are lazy; Horn-clause bodies are strict conjunctions.
  M1 policy is #258 §3.1's: total, pure guards are exact; partiality is a documented,
  undetected residual — but the Debug renderer and any IR notes must not _claim_ strictness
  equivalence, and goal ordering must preserve the source's guard-before-use structure so a
  guarded division is not evaluated ahead of its guard.
- **I9 (date expressions are order-rigid).** Date addition is non-commutative and
  non-associative. M1 excludes dates, but the DNF/ANF machinery being built here must not
  assume commutativity or re-associate subexpressions generally: normalise boolean structure
  only, never arithmetic operand order. Write the constraint into the normaliser's comments
  now so M2 does not inherit a reordering pass it cannot use.

## Addendum 2, 2026-08-18 (pre-freeze requirements from the catala/docassemble sessions — binding)

Both sibling bridge sessions sent RelProgram requirements before the IR freeze. Items marked
_covered_ restate an existing constraint for emphasis (do not re-litigate); items marked
_new_ bind M1 now.

- **Normal form is declared, not implied** (_new_). `RelProgram` IS a normal form and its
  haddock must say so loudly: clause-per-disjunct, materialised guard prefixes, ANF bodies.
  A consumer that needs the source's boolean shape goes back to the AST via per-clause
  provenance (`Unique` + `SrcRange`); it must never reconstruct source shape from clauses.
  (Receipt: the docassemble session's M3 measurement silently walked a CNF'd form while its
  emitter lowered source form — a one-directional error that moved a headline number.)
- **Clause bodies are ordered sequences, and the order is semantics** (_new_ — sharpens I8).
  Goals in a body keep source evaluation order; ANF inserts binding goals before first use
  but never otherwise permutes; DNF distribution duplicates conjuncts into sibling clauses
  but never reorders them within a clause. Conjunction is a list, not a set — the IR type
  must say so, and the Debug renderer must not canonically sort goals. This rule is also
  the **premise under which the prefix construction below is sound**: transformed arm _i_
  evaluates ¬g₁..¬g₍ᵢ₋₁₎ then gᵢ in exactly the original's guard-evaluation sequence, so no
  raise is introduced or reordered even when guards can raise — an optimisation pass that
  permutes goals within a body silently invalidates the I7 discharge, not just Prolog-family
  behaviour.
- **`RNotCall` in the M1 fragment is classical** (_new_, documentation-binding). Every
  in-fragment negation originates as boolean `NOT` over a total computed decision; Lower
  introduces no closed-world or NAF assumption (aggregates run over lists, not open
  predicates). If a later widening introduces NAF-semantics negation it must be a NEW
  constructor, not an overload of `RNotCall` — classical consumers (SMT, Catala) must be
  able to reject it by type. Write this into `IR.hs`'s haddock now.
- **Reachability is transitive through application** (_new_ — implementation trap). Helper
  selection must traverse the bodies of called decides transitively: a decide referenced
  only from inside another helper's body is still reachable. (Receipt: two confirmed
  docassemble defects from a direct-bodies-only reference walk.)
- **Computed record fields do not exist after desugar** (_new_ — implementation trap).
  `L4.Desugar.desugarComputedFields` strips `MEANS` fields out of `RecordDecl` before type
  checking and synthesizes a top-level selector decide per field. A projection onto a
  computed field must route to the synthesized selector; a "record has no such field" branch
  for computed fields is dead code, and treating the stripped record as the field inventory
  is the trap.
- **BRANCH/CONSIDER priority compiles away by construction** (_covered_): the materialised
  guard-negation prefixes make arms disjoint syntactically, so no first-match/disjointness
  obligation survives into the IR (portfolio I7 is discharged in the middle-end, not
  delegated to emitters).
- **WHERE helpers keep their names** (_covered_): lambda-lifting yields one predicate per
  helper under its source name + `Unique`. Never inline a named local into its parent's
  body — the name is the citation hook.
- **Identity joins on `Unique`** (_covered_): a consumer needing the ladder/query-plan
  UUIDv5 atomId derives it from the same `Unique` (`L4.Docassemble.QueryPlan`'s
  `atomIdByUnique` pattern) — do not invent a second identity scheme.
- **R2-1 ruling (coordinator, 2026-08-18, at close-out).** The review confirmed that the
  mandatory boolean output-argument drop makes a boolean-valued call in value position
  unrepresentable. RULED: the drop stays mandatory in M1 and the narrowing joins the
  fragment statement above, loudly rejected — it is Blawx's (the driving consumer's) unary
  idiom, and #258 §2.2 permits either form. The M2 path, when a consumer needs the shape:
  a per-predicate drop flag (`rpBoolDropped`) set by a whole-program value-position
  analysis, so a predicate keeps its output argument iff some call site uses it as a value.
  The same ruling closed a latent miscompile the fix agent flagged: the computed-BOOLEAN-
  field selector path appended an output argument its `rpResult = Nothing` declaration does
  not have (silent arity mismatch, reachable from in-fragment source in both goal and value
  position). Fixed at close-out: goal position takes the call form with polarity
  (`computed.l4` golden), value position takes the same rejection as a named call
  (`not-ok/bool-value-position.l4`).
- **Recorded deferrals** (out of the M1 fragment, not forgotten): applicability-vs-
  requirement separation (the APPLIES/SUBJECT-TO seam) must arrive as distinct IR structure
  when regulative constructs widen in, never a boolean collapse; Fidelity-vocabulary gating
  (Blocking/Lossy/Advisory + `--fail-on`) is a CLI concern deferred to PR B — M1's batch
  `LowerError`s are all conceptually Blocking; and a **per-goal partiality/can-raise tag**
  is deliberately absent from M1 (ruled with the catala session 2026-08-18: the sequential
  Prolog family cannot be miscompiled by its absence, and the existing can-raise analysis
  lives in `L4.Catala.Lower`). Its trigger is precise: the tag becomes **mandatory at the
  boundary where any strict-target backend — Catala, DMN, or a RelProgram-based `l4
prove` — first consumes RelProgram**; whoever opens that consumer adds the field then.
