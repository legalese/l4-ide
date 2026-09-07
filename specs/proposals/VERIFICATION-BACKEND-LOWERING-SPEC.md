# Verification Backend Lowering Specification

**Status:** Proposal. **Phase 1 is ruled but not built** — R-V1–R-V10 were answered by Meng on
2026-09-07 (§"Phase 1 rulings"); no prover exists in the tree as of that date, and `l4 prove` is
named throughout this document as a thing to write, not a thing that runs.
**Author:** Meng Wong
**Date:** 2026-06-29 (Phase 1 rulings appended 2026-09-07)
**Related:** [BOUNDED-DEONTICS-SPEC.md](../todo/BOUNDED-DEONTICS-SPEC.md), [ACTUS-L4-BRIDGE-SPEC.md](../done/ACTUS-L4-BRIDGE-SPEC.md), [DEONTIC-TRACE-API-SPEC.md](../done/DEONTIC-TRACE-API-SPEC.md), [PROHIBITION-BREACH-SPEC.md](../done/PROHIBITION-BREACH-SPEC.md)

## Overview

This specification elaborates **Phase 2 of [BOUNDED-DEONTICS-SPEC.md](../todo/BOUNDED-DEONTICS-SPEC.md)** ("Transpilation to Verification Backends") into a concrete architecture for **lowering** L4 to a portfolio of formal-methods tools: Z3 (SMT), Alloy, TLA+, NuSMV/nuXmv, UPPAAL, TAPAAL, SPIN/Promela, and Maude.

The thesis, in the vocabulary the bounded-deontics spec already establishes:

- The **object level** is the _letter_ of the law — the mechanics, written as `DO`/`HENCE`/`LEST` choice points.
- The **assertion level** is the _spirit_ of the law — properties written in temporal logic over paths.
- **Verification is the search for the gap between them**: a counterexample to a spirit-level property, expressed in the letter-level model, is a loophole, a race condition, or an impossible requirement.

Two case studies already validate the approach and, between them, motivate the _whole_ portfolio rather than any single tool:

1. **A regulatory race condition.** Formalizing a piece of secondary legislation surfaced a deontic + temporal double-bind: under certain timings, one clause _obliged_ an act while another _prohibited_ it. This is a **timed reachability** counterexample — squarely UPPAAL/TAPAAL territory, and the reason timed tools are not optional.
2. **An insurance payout ambiguity.** Formalizing a payout formula surfaced an arithmetic under-specification that leaked money. This is an **SMT satisfiability** question — Z3 territory.

No single backend answers both. The design problem is therefore not "pick a model checker" but "lower faithfully to many, each chosen by the question it answers."

## Design Principle: Fan-Out, Not a Pipeline

"Lowering" is the right word, but this is **not a linear pipeline to one target**. The backends inhabit genuinely different semantic universes — relational (Alloy), arithmetic/SMT (Z3), temporal-over-state-machines (TLA+, NuSMV), dense-timed (UPPAAL, TAPAAL), rewriting (Maude). It is a **fan-out of semantics-preserving translations**.

What makes the fan-out trustworthy is not any individual translator but the fact that **they all refine one reference semantics**:

> **The single source of truth is an L4 _core IR_ with a pinned semantics.** Each backend is a lowering carrying an explicit _faithfulness obligation_ against that semantics.

The failure mode to avoid: N backends each quietly encoding a slightly different notion of "obligation" or "deadline," disagreeing on a fixture, and leaving the user trusting _none_ of them — strictly worse than having one. Faithfulness is the central engineering risk, not coverage.

```
                          ┌──→ Z3 / SMT           (arithmetic, satisfiability, witnesses)
                          ├──→ Alloy 6            (relational, bounded conflict-finding)
 L4 source → Core IR ─────┼──→ TLA+ / nuXmv       (protocols: safety + liveness)
 (pinned semantics)       ├──→ UPPAAL / TAPAAL    (dense-time deadlines)
                          └──→ SPIN, Maude        (async message-passing; rewriting)
                                   │
                                   └── cross-validation harness asserts agreement
```

## The Backend Portfolio

Choose the backend by the **question class**, not by completeness for its own sake.

| Backend                   | Semantic model                                                 | Answers best                                                              | L4 driver                                                             |
| ------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| **Z3 / SMT**              | Quantifier-free theories (LIA/LRA/NIA, datatypes, strings)     | "Is this formula well-defined? Find a satisfying / violating assignment." | Fee tables, payout formulas (insurance leak), totality checks         |
| **Alloy 6**               | Relational FOL, bounded (small-scope) + LTL                    | "Find a small instance where clause A obliges and B forbids."             | Structural invariants; deontic double-bind counterexamples            |
| **TLA+** (TLC / Apalache) | State machines + temporal logic of actions; fairness           | "Safety _and_ liveness of a multi-party protocol."                        | Negotiation, multi-step settlement; "settlement eventually completes" |
| **NuSMV / nuXmv**         | Symbolic (BDD) + SAT/IC3; CTL + LTL; nuXmv adds infinite-state | "Does this finite control-state contract satisfy this CTL/LTL property?"  | Loophole = CTL violation → trace                                      |
| **UPPAAL**                | Networks of timed automata, dense clocks, TCTL                 | "Is the double-bind state reachable within these deadlines?"              | The regulatory race condition; clock-bearing clauses                  |
| **TAPAAL**                | Timed-arc Petri nets, dense time, TCTL                         | Same as UPPAAL, with token/resource-flow concurrency                      | Parties-as-token-flows; resource accounting                           |
| **SPIN / Promela**        | Explicit-state LTL; async processes                            | "Does this message-passing protocol deadlock / violate LTL?"              | Asynchronous offer/acceptance protocols                               |
| **Maude**                 | Rewriting logic; executable semantics                          | Operational reference + reachability/LTL                                  | Candidate _host for the reference semantics itself_                   |

### Three orthogonal axes

The portfolio also partitions along axes that should drive sequencing and UX:

1. **Witness-finding vs proof.** Bounded engines (Alloy, BMC, Z3-sat) return a _counterexample_; unbounded engines (UPPAAL exhaustive reachability, IC3 in nuXmv, Apalache, TLC) attempt a _proof_.
2. **Untimed vs timed.** Only UPPAAL/TAPAAL model dense clocks; everywhere else, deadlines must be faked as step counts (lossy for genuine real-time deadlines).
3. **Bounded vs unbounded** state/scope.

The use cases line up with the witness/proof axis:

| Use case                       | Wants       | Backend bias                                                                         |
| ------------------------------ | ----------- | ------------------------------------------------------------------------------------ |
| Consumer-facing wizards        | **Witness** | "Here is the scenario where you are double-bound" beats a green check; SMT/Alloy/BMC |
| Negotiation / contract testing | **Witness** | Fast counterexamples per draft; SMT/Alloy                                            |
| Rules-as-code / legislation    | **Proof**   | Assurance over all reachable states; UPPAAL/Apalache/IC3                             |

Witnesses are also _more explainable_, which matters because explanation (via the [deontic trace API](../done/DEONTIC-TRACE-API-SPEC.md)) is a first-class deliverable, not an afterthought.

## The Core IR and the Semantic Gap

The IR must capture, with a pinned semantics, everything a backend needs:

| L4 construct                    | IR concept                            | Lowers to                                                                     |
| ------------------------------- | ------------------------------------- | ----------------------------------------------------------------------------- |
| `DO` / `HENCE` / `LEST`         | Choice point with branch outcomes     | State-machine transitions (TLA+, NuSMV); automaton edges (UPPAAL)             |
| `MUST` / `MAY` / `SHANT`        | Deontic-sugared transitions + valence | Same transitions + assertion-level marking                                    |
| `WITHIN` / `BEFORE` (deadlines) | Clock constraints                     | Clocks + invariants/guards (UPPAAL/TAPAAL); step counters (untimed)           |
| `PARTY` (multi-party)           | Concurrent agents                     | Process interleaving (TLA+/SPIN); automata networks (UPPAAL); tokens (TAPAAL) |
| Fee tables, formulas, money     | Arithmetic over LIA/LRA/NIA           | SMT theories (Z3); bounded ints elsewhere                                     |
| Records, enums, parties as data | Algebraic datatypes / relations       | Datatypes (Z3, TLA+); relations (Alloy)                                       |
| Assertion level (LTL/CTL/TCTL)  | Property language                     | Native temporal logic of each backend                                         |

The **assertion language** itself needs first-class L4 syntax (see [BOUNDED-DEONTICS-SPEC.md](../todo/BOUNDED-DEONTICS-SPEC.md) Phase 3) so that the "spirit" can be authored alongside the "letter" and lowered to whichever logic the chosen backend speaks (LTL, CTL, TCTL).

### Worked fragment: the timed double-bind

```l4
-- Object level (the letter): two clauses with deadlines
UPON notice_served
  PARTY operator MUST remediate WITHIN 30 days
    HENCE compliant
    LEST  penalty

UPON assessment_pending
  PARTY operator SHANT remediate UNTIL assessment_complete
    HENCE compliant
    LEST  breach
```

```
-- Assertion level (the spirit): no reachable state simultaneously
-- obliges and forbids the same act
AG ¬( obligation(operator, remediate) ∧ prohibition(operator, remediate) )
```

If `assessment_complete` can lag past day 30, UPPAAL finds a clock valuation reaching the forbidden conjunction — the race condition, returned as a concrete timed trace. An untimed encoding can _miss_ it, because the bug lives in the clock region, not the control state. This is precisely why timed tools are in the portfolio.

## The Crux: Defeasibility

**Every backend listed is classical and monotonic. Law is defeasible.** Governatori's program — priorities, exceptions, contrary-to-duty (CTD) obligations, reparational chains — does not lower natively to Z3, TLA+, or UPPAAL. The Chisholm-paradox family means a naive deontic encoding will report "conflicts" that are artifacts of the encoding, not bugs in the law. **That is the single fastest way to discredit the whole approach.**

Two viable strategies, and the IR must commit to one (or layer both):

1. **Discharge defeasibility in the IR before lowering.** Evaluate the priority/argumentation semantics to a concrete _extension_ — the set of in-force obligations per state — compiling exceptions and overrides into explicit guards. The classical backend then checks a monotonic theory that already reflects the defeasible conclusions.
2. **Stratify.** Keep a non-monotonic layer (ASP — clingo/DLV — which is natively defeasible) for the in-force determination, and hand the resulting per-state obligation set to the classical backend for temporal/arithmetic/timed checking.

A reported conflict is only trustworthy once defeasibility is correctly discharged. The regulatory race condition above is real precisely _because_ it survives that discharge — distinguishing genuine conflicts from encoding artifacts is a core obligation of this work, not a detail.

## Faithfulness and the Cross-Validation Harness

Faithfulness must be **executable**, not argued:

- A corpus of L4 fixtures (drawn from `jl4/examples/` and the case studies) is lowered to **every applicable backend** and each backend's verdict + witness is recorded.
- The harness **asserts cross-backend agreement**: where two backends can answer the same query, they must agree on satisfiability and (up to representation) on the witness. Disagreement is a faithfulness bug in a lowering, surfaced as a test failure.
- This is differential testing across backends, and it slots into the existing golden-file workflow (see `AGENTS.md` → Testing).

The principle generalizes a hard-won lesson: bugs hide in the _contexts you did not enumerate_. The harness enumerates contexts (interleavings, clock regions, data assignments) so the happy path cannot lie.

## Implementation Roadmap

### Phase 0 — Pin the core IR semantics

> **Scope, ruled 2026-09-07 (R-V1).** Phase 0 gates **Phase 2 and after**, not Phase 1. Every item
> below is about obligations, clocks and defeasible priority; none of them is asked by the pure
> decision fragment Phase 1 targets, whose reference semantics already exists and is executable —
> the jl4 evaluator, already the oracle of record for the Catala backend's expected values, the DMN
> engine harnesses and the Blawx s(CASP) comparison (portfolio invariant I1).
>
> **This re-scoping is a deferral, not a cancellation, and it is the one most likely to evaporate.**
> Meng's note on R-V1: _"What I'm worried about is that we will do Phase 1 now and never get around
> to Phase 0. We have to stay true to the vision and not forget it."_ The register in
> §"Deferred obligations" carries it with a trigger; that register is the answer to this worry, and
> deleting an entry from it without discharging the work is the failure mode being guarded against.

- [ ] Define the IR (deontic transitions, clocks, parties, data, assertion language)
- [ ] Pin a reference semantics (candidate: rewriting logic in **Maude**, which can both _host_ the semantics and serve as a backend)
- [ ] Decide the defeasibility strategy (discharge-in-IR vs ASP-stratified) and specify the in-force determination
- [ ] Specify the assertion language surface syntax and its mapping to LTL/CTL/TCTL

### Phase 1 — Z3 / SMT (build first)

- [ ] Lower arithmetic/data fragments (fee tables, payout formulas) to SMT
- [ ] Well-definedness / totality / ambiguity checks (the insurance-leak class)
- [ ] Wire models → counterexamples and UNSAT cores → explanations via the [deontic trace API](../done/DEONTIC-TRACE-API-SPEC.md)
- [ ] Stand up the **cross-validation harness** here, even with one backend

### Phase 2 — Bounded conflict finder (Alloy 6)

- [ ] Lower the relational skeleton + deontic markings
- [ ] Counterexamples to deontic conflict (the double-bind) at small scope
- [ ] Bounded LTL for short temporal counterexamples

### Phase 3 — Timed backends (UPPAAL / TAPAAL)

- [ ] Lower `WITHIN`/`BEFORE`/`UNTIL` to clocks + invariants/guards
- [ ] Reproduce the regulatory race condition as a regression fixture
- [ ] TAPAAL variant for token/resource-flow concurrency

### Phase 4 — Unbounded temporal (TLA+ / Apalache, nuXmv)

- [ ] Lower multi-party protocols; safety + liveness under fairness
- [ ] CTL/LTL assurance for rules-as-code; IC3 / k-induction for infinite-state
- [ ] (Continuity with BOUNDED-DEONTICS Phase 2: SPIN/Promela, Maude)

### Cross-cutting

- [ ] Counterexample → IDE visualization (reuse the trace visualizer)
- [ ] Per-query backend selection heuristic (timed? arithmetic? liveness? → tool)

## Phase 1 rulings — R-V1 to R-V10

**ANSWERED 2026-09-07 by Meng**, off a bench card of ten rulings. Each entry states the ruling, the
measurement that drove it, and — where the answer diverged from the recommendation put to him — what
changed and why. Everything here is scoped to Phase 1 (the pure decision fragment, Z3/SMT); nothing
in it rules anything about the deontic, timed or defeasible layers.

Two facts frame the whole set, both measured against `origin/unstable` on 2026-09-07:

- **Rung 1 already shipped.** `l4 verify` compiles each `BOOLEAN` decision to a canonical
  hash-consed ROBDD and reads unsatisfiability off the constant node
  (`jl4/app/L4/Cli/Verify.hs`, via `L4.Decision.BooleanDecisionQuery`). Its own
  `propositionalBound` statement (`Verify.hs:93-152`) names precisely what Phase 1 must add:
  _"`amount > 5000000` and `amount > 1000000` are two unrelated atoms, so no numeric, interval,
  string or date contradiction is visible"_, and _"a call to another DECIDE is a leaf, not an
  inlined body … in a corpus written as many small named limbs — which is the house style — that is
  most of the corpus."_ Phase 1 is the answer to a limitation the tree already prints to its users.
- **There is no SMT anything in the tree.** No `.cabal` file mentions z3, sbv, simple-smt, cvc5 or
  yices. The only Z3 that runs today runs inside `catala proof`, out of process, via
  `etc/validate-catala.mjs` — and that route is provably incapable of the job: its VC kinds are
  exactly `NoEmptyError | NoOverlappingExceptions` and scope assertions enter as _hypotheses_
  (`conditions.ml:278`, `conditions.mli:36` @ `d37aca74`), the opposite polarity, so user invariants
  cannot be proven on it. That is seam S3's route 2 ceiling, and it is why route 1 exists.

### R-V1 — Phase 0 gates Phase 2, not Phase 1. ANSWERED 2026-09-07, see Phase 0 above.

Build Phase 1 on the pure decision fragment now. **What drove it:** Phase 1's own named drivers in
this document — fee tables, payout formulas, the insurance leak, totality checks — are all inside
that fragment, where the defeasibility crux that motivates Phase 0 has nothing to bite on. The
fragment's reference semantics already exists and is executable.

**Carried worry, recorded verbatim because it is the point:** _"Sounds like doing Calvanese on the
decision logic part. What I'm worried about is that we will do Phase 1 now and never get around to
Phase 0. We have to stay true to the vision and not forget it."_ See §"Deferred obligations" D1.

### R-V2 — v1 proves user properties **and** generated well-definedness obligations, with the call graph unfolded. ANSWERED 2026-09-07.

Division-by-zero, non-total matches and mutually-satisfiable conditions that should be disjoint each
become an obligation with no user input; named decisions lower to solver definitions so the solver
unfolds them. **What drove it:** the insurance leak was found by looking, not by someone writing the
property "this payout formula is unambiguous" — a prover that only answers what it is asked is worth
the questions people think to ask. Unfolding answers the second of `propositionalBound`'s
limitations, the one it says covers most of the corpus.

**Consequence to hold:** unfolding needs a recursion guard. `L4.Catala.Lower`'s `recursionErrors`
already rejects every cycle in the reachable call graph, naming the cycle path — reuse it rather
than writing a second one.

### R-V3 — No new directive. `l4 prove` discharges the `#ASSERT`s that already cannot be decided. ANSWERED 2026-09-07. **Diverges from the recommendation.**

An `#ASSERT` whose free variables are section binders is already a universally quantified statement
that the evaluator cannot decide, and the tree already treats it as undecidable-on-purpose. `l4
prove` decides it. **Plus** the half of the recommendation Meng kept: the non-ground `#ASSERT`
diagnostic is reworded to point at `l4 prove` instead of stopping at "assertion could not be
evaluated".

**What drove the divergence.** The recommendation was a new `#PROVE` directive, on explicitness
grounds — a ground test and a theorem are different objects and a reader should see which is which.
Meng's answer: _"why not B, and reword the non-ground ASSERT diagnostic to point at `l4 prove`"_ —
i.e. buy the explicitness with the diagnostic rather than with a keyword. The cost side is
measured and large: a sixth directive is **15 compiler-enforced sites** (lexer keyword map, AST,
parser, typechecker, evaluator, directive filter, layout printer, annotation resolver, NLG
linearizer, DMN call-graph roots, the AND/OR-depth lint, the Relational and Catala lowerings, three
code-lens label tables) plus goldens, plus two that fail **silently**: the TypeScript highlight
token list, and `jl4-service`'s second text-based directive filter, which already disagrees with the
Haskell one about `#TRACE`. B costs none of that.

**The mechanism this rests on, verified 2026-09-07.** A section `GIVEN` is desugared into a 0-ary
`ASSUME` at the head of the section (`L4.Desugar.desugarSectionGivens`) and then discharged into an
ordinary parameter of every definition that reads it (`L4.Discharge`) — but, in that module's own
words, _"'Assumed term' survives only as 'unsupplied at the root', because the root's own reference
to the binder is still the module-level `ASSUME` the desugaring left there."_ A directive is at the
root. So a directive over a section binder is still stuck, which is exactly the handle B needs.

**Load-bearing consequence — one pinned CLI behaviour changes, and only one.** `l4 run` today
**exits non-zero** on a stuck `#ASSERT`: `evalDirectiveCrashed` maps `Assertion (Errored _)` to
`True` (`jl4/app/L4/Cli/Run.hs:136-158`), a stuck assert reports `Errored (Stuck _)`, and
`jl4/tests-cli/Main.hs` pins it — _"fails the run when an #ASSERT is stuck on a bare assumed
BOOLEAN"_. Under B, a file carrying proof obligations would fail `l4 run`, which would push authors
into keeping obligations in separate files from tests. So B adds a fourth assertion outcome,
**deferred**, distinct from `Holds`/`Fails`/`Errored`.

**Deferred is narrow on purpose. The rule is not "stuck asserts now pass."** Before this ruling, an
`#ASSERT` over an unsupplied binder had no valid reading, so exit 1 was right — it meant the file
was broken. B gives that one shape a valid reading, and nothing else. Therefore:

> An `#ASSERT` is **deferred** if and only if its free variables are unsupplied section binders.
> Every other way of being stuck stays `Errored` and keeps exit 1.

A typo that leaves an assert stuck on something that is not a binder still fails the run, exactly as
today. And a deferred obligation is not thereby excused: it is reported by count on the run, and
`l4 prove` is what discharges it — a mistaken obligation comes back as `refuted` **with a witness**,
which is strictly better news than the exit 1 it used to get. The existing `expectFail` test changes
to expect the deferred outcome; that change is part of the ruling.

**Define deferral syntactically, not by observing a stuck evaluation.** The handle must be _"this
assert's free variables include unsupplied section binders"_ — a property of the module — and **not**
_"evaluation produced `ValAssumed`"_. The two coincide today only because
`L4.Desugar.desugarSectionGivens` leaves a module-level `ASSUME` that `L4.Discharge` does not remove
at the root. That is an implementation detail of a **deprecated** construct (props R0, 2026-09-04),
and a later cleanup of the discharge would silently change which asserts are deferred if the handle
were the evaluation artifact. Reading the binder instead makes B survive `ASSUME`'s retirement.

**What B does not touch.** `REFUSE` is unaffected: `l4 run` already exits 0 on
`Assertion (Refused _)`, deliberately (_"a REFUSAL is not a crash … the two must not be conflated,
which is the whole point of REFUSE"_), and R-V4 keeps a refusal as its own outcome class rather than
a counterexample. `ASSUME` is not entrenched — B rests on the section binder, its supported
successor. The prover itself is purely additive: a new subcommand reading existing syntax, removing
nothing.

**Measured blast radius, and the file that proves the rule discriminates.**
`jl4/examples/ok/assert-raises.l4` already contains both kinds of stuck assert, side by side, and
its golden pins all of them:

| line       | assert                           | why it is stuck                     | under B                           |
| ---------- | -------------------------------- | ----------------------------------- | --------------------------------- |
| 7, 8       | `(1 DIVIDED BY 0) EQUALS 1`      | genuine runtime error, no free vars | **`Errored`, exit 1 — unchanged** |
| 11, 12     | `x EQUALS 1`                     | `x` is the section's `GIVEN` binder | **deferred**                      |
| 21, 22     | `b`                              | `b` is the section's `GIVEN` binder | **deferred**                      |
| 15, 25, 26 | short-circuit and ground asserts | not stuck                           | unchanged                         |

That is the syntactic rule doing exactly the work asked of it: division by zero has no free
variables and stays an error; `x EQUALS 1` has a free variable that is an unsupplied binder and
becomes an obligation. All four deferred asserts are also **refutable** — `x = 2`, `x = 1`,
`b = FALSE`, `b = TRUE` — so `l4 prove` replaces four "could not be evaluated" reports with four
witnesses. Strictly more information than the tree gives today.

The whole measured cost of the change, over `origin/unstable` on 2026-09-07: **one golden**
(`jl4/examples/ok/tests/assert-raises.golden`, where 4 of 9 entries change and the two
division-by-zero entries must **not**), **one CLI test** (`expectFail` on `assert-assumed.l4`
becomes the deferred outcome), and **no corpus file at all** — `assert-raises.golden` is the only
golden in the tree containing the string "assertion could not be evaluated". Re-blessing that
golden without reading it would hide the one thing worth checking, which is that lines 7 and 8 did
not move.

**The safety net is CI, not the exit code.** Since a deferred obligation no longer fails `l4 run`,
something must ensure it is actually discharged rather than accumulating unseen. That is the same
"silently missing" problem `etc/check-corpus-goldens.mjs` was written for, and it takes the same
shape: a check that every corpus file reporting deferred obligations is covered by an `l4 prove`
run. It ships with the prover's first PR, not after it.

**Smallest first test, free.** `jl4/tests-cli/fixtures/assert-assumed.l4` is a section
`GIVEN b IS A BOOLEAN` with `#ASSERT b` and `#ASSERT NOT b`. Under B both become obligations, and
both are **refutable**: `l4 prove` should answer `refuted` with witness `b = FALSE` and `b = TRUE`
respectively. The fixture that documents undecidability becomes the smallest demonstration of
refutation, with no new corpus.

### R-V4 — Consume `analyzeSafety`; each clause becomes a side condition or a named refusal. ANSWERED 2026-09-07.

**What drove it:** the enumeration already exists and is better than one written fresh.
`L4.Dmn.Analysis.analyzeSafety` is exported, clause-coded L1–L12 plus
`PURE`/`REFUSE`/`TOTAL`/`TERMINATES`, and was written for this exact reason (DMN's `null` swallows
partiality into a silent wrong answer). Its best idea is **strictness-position refinement** —
division only counts in strict position, because `IF d EQUALS 0 THEN 0 ELSE n / d` is safe when the
guard and the operation travel together — and `TOTAL` is a **greatest** fixed point over the call
graph's condensation, with the note that a least solution would wrongly reject `sum`/`map`/`filter`.

**Two hazards the ruling inherits, stated so they are not rediscovered.** (1) The exhaustiveness
oracle is **fail-open in three ways and unexported**: it gives up past 128 uncovered cases, reports
no missing arms past 64 suggestions, and suppresses itself on literal or expression patterns.
**Silence is not a totality proof** — read totality through `considerIssues`, which is already
three-valued, never through the absence of a warning. (2) `analyzeSafety`'s own known gap is that
cross-module callees are invisible; that becomes the prover's gap too and belongs in the coverage
line (R-V8).

### R-V5 — Two-oracle discipline, in both directions. ANSWERED 2026-09-07.

On `sat`, replay the model through the jl4 evaluator and report a counterexample only if the
evaluator agrees the property fails there; otherwise report an **encoding defect**, loudly. On
`unsat`, sample ground points and check the encoding against the evaluator pointwise.

**What drove it:** this document asks for the cross-validation harness to be stood up in Phase 1
_"even with one backend"_, and with one backend the second oracle is the evaluator — which is
already the oracle for the Catala backend's expected values, the DMN engine harnesses and the Blawx
comparison. The `sat` half makes counterexamples self-checking for free; the `unsat` half is what
catches a systematically over-constrained encoding, which otherwise proves everything and is never
caught. This also answers this document's own open question on witness translation, for Phase 1: a
model is a concrete input, so the lift back to L4 is an evaluator run, not a translation.

### R-V6 — Emit SMT-LIB2 text; shell to a `z3` subprocess; no Haskell solver dependency. ANSWERED 2026-09-07.

Discovery follows the established ladder: explicit `Z3_EXE` first (a configured path that does not
exist is a hard failure), then `z3 --version` on `PATH`. The CLI is a **requested artifact**, so a
missing solver fails with a named reason, as `l4 trace --format png` does for Graphviz; the CI check
is **optional evidence**, so it prints one `skipped:` line naming what would have been measured and
exits 0, as `etc/validate-catala.mjs` does. Goldens over the emitted SMT-LIB2 run with no solver
installed at all. Keep the emitted text portable — no z3-specific tactics — so cvc5 is a free second
opinion on any `unsat`.

**Prior art answered.** `specs/done/BOOLEAN-MINIMIZATION-SPEC.md` considered and rejected `sbv`:
_"requires external solver (Z3, CVC5), heavier dependency, overkill for pure boolean."_ That
rejection was right for its question — pure boolean minimisation, where BDDs suffice — and does not
reach this one, whose whole point is theory reasoning that BDDs cannot do. Recorded rather than
quietly contradicted.

**Ruled with an exit, per Meng's note:** _"let's record that we go with Plan A first, in future we
want to support Plan B eventually; but if anything goes wrong with Plan A we can pivot to Plan B
quickly. the difference between harness vs emitter should not get in our way."_ So the SMT-LIB2
emitter sits behind an interface narrow enough that an `sbv` implementation is a drop-in — the
pivot is a swap of one module, not a rewrite — and the emitter must not leak subprocess assumptions
into the lowering. See §"Deferred obligations" D3.

### R-V7 — Encode rounding, modulo and dates exactly; reject transcendentals by name. ANSWERED 2026-09-07.

`BOOLEAN` → `Bool`; `NUMBER` → `Real`, which is **faithful** rather than approximate because L4
numbers are exact rationals (`ValNumber !Rational`) and SMT reals are the rationals; enums and
records → SMT datatypes; optionals → an option datatype; `STRING` → an uninterpreted sort with
equality only; a bodiless `DECLARE T` → an uninterpreted sort, which is what it already is.

**The three places a natural encoding lies, all measured:**

| operation       | L4's semantics                                             | the trap                                                              |
| --------------- | ---------------------------------------------------------- | --------------------------------------------------------------------- |
| `ROUND`         | Haskell `round` — **banker's rounding**, half to even      | not half-up, and not SMT-LIB `to_int`, which is floor                 |
| `MODULO`        | Haskell `mod` — **floor-modulo**, sign follows the divisor | SMT-LIB `mod` is Euclidean, always non-negative — a third convention  |
| `LN`/`SQRT`/`^` | round-trip through `Double` in the evaluator               | not faithfully encodable in any decidable arithmetic → refuse by name |

A payout rule that rounds is the exact shape of the insurance case study, so `B` (refuse everything
subtle) would have excluded the class this was built for.

**Dates: `DATE` → `Int` day serial, exact — but only up to the calendar constructors.** There is no
date arithmetic _operator_ at all; dates convert through integer day serials
(`DATE_SERIAL`/`DATE_FROM_SERIAL`, epoch `0001-01-01`). Comparisons, serial round-trips and day
offsets are therefore exact and linear.

The calendar constructors are **not** in the v1 fragment, and this ruling agrees with
`DATE-LIBRARY-SPEC.md` **R-D14** rather than weakening it. Measured in
`jl4-core/libraries/daydate.l4`: `Date` is defined through
`` `Months since year start to days` ``, which is **recursive** by its own comment ("Recursively add
all days of months that year"), and `` `is leap year` `` goes through `FLOOR (y DIVIDED BY 4)`. So
month and year arithmetic is caught by R-V2's recursion guard and refused by name, landing in
R-V8's `unknown (out of fragment)` — which is exactly the granularity boundary R-D14 draws, reached
from the other side. DateSAT remains the adoption candidate for going past it.

**Two corrections to the August assessment, recorded because they were wrong in my own notes.**
(1) "L4 native dates lack month arithmetic, so the Monat ambiguity is inexpressible by construction"
was **false**: the arithmetic exists as library code, and the ambiguity is expressible. (2) What is
true, and more useful, is that the library already distinguishes two of Monat's three rounding modes
**by name** — `Date` rolls forward on an impossible day, `YMD` `REFUSE`s it, which is the abort
default ESOP 2024 argues for. The semantics were settled before the question was asked; only the
solver coverage is bounded.

### R-V8 — Three verdicts; every `unknown` names its reason; every run ends with a coverage line. ANSWERED 2026-09-07.

`proved` / `refuted` / `unknown (timeout after Ns)`, `unknown (non-linear: product of two
variables)`, `unknown (out of fragment: recursion in \`scale\`)`. The run ends with what it did not
attempt and why, including `analyzeSafety`'s invisible cross-module callees (R-V4).

**What drove it:** house style, not novelty. `#ASSERT` on an unsupplied term already reports
"assertion could not be evaluated" rather than picking a side, and `assert-assumed.l4` exists to pin
that both polarities give the _same_ undecided answer. `l4 verify` prints sixty lines of its own
limits for the same reason — _"an exclusion nobody can size is an exclusion nobody believes."_ The
cautionary datapoint outside the tree is Bedrock's Automated Reasoning checks: **99.4% soundness at
14.9% recall**, abstaining ~85% of the time, with the soundness figure the one that gets quoted.

**This answers this document's open question on scope/bounds discipline, for this backend.**

### R-V9 — Consume in place for the first PR; lift in a follow-up that does nothing else. ANSWERED 2026-09-07.

The prover imports `L4.Dmn.Analysis` and `LSP.L4.Viz.QueryPlan` as they stand; the follow-up PR is a
pure move with no behaviour change.

**What drove it:** a feature PR that is only a feature, and a rename PR that is only a rename — the
combination is what makes review hard and bisection worse. The second consumer is also what reveals
which parts are genuinely general, so the move is better informed after it exists.

**What is misfiled, for the follow-up to act on.** There is **no** reusable fragment predicate in
the Catala backend — fragment membership there is a side effect of `lowerModule` returning `Right`,
so a prover cannot ask the question without doing the Catala lowering and discarding the answer.
What _is_ general and misfiled: `analyzeSafety`, `considerIssues`, the call graph and
`nonexhaustiveDecides` under `L4.Dmn`; `vizExprToBoolExpr` under `LSP.L4.Viz` (already on its third
consumer while living behind an editor namespace); and in `L4.Catala.Lower`, `recursionErrors`,
`reachableFrom`, `mayRaiseL4`, the nullary-binding topological sort, and the batched ranged-error
applicative that reports every refusal at once instead of the first.

**Explicitly not the substrate:** `L4.Relational`. It is DNF-clause-shaped for logic-programming
targets — right for Blawx and PROLEG, wrong for SMT, where the expression structure is what you hand
the solver.

**Meng's note:** _"let's not forget to do the later."_ See §"Deferred obligations" D2.

### R-V10 — The first PR is the prover with Mode A ≡ Mode B as its acceptance test. ANSWERED 2026-09-07.

**What drove it:** the prover's first customer is a debt we have already disclosed, in a document
that names the tool it is waiting for. `CATALA-EXPORT-SPEC.md` §8.4: _"Closing this properly means
emitting an `AgreeAt` over concrete records that calls the real scope, with witnesses derived from
the atoms … **That needs a solver for the witnesses and is not built; saying so is the interim.**"_
The standing grid enumerates all 2ⁿ assignments of the lifted atoms and is **capped at n = 8**; past
256 rows the rule falls back to Mode A with the reason recorded. A solver removes the cap as well as
the sampling. The gate is not hypothetical: it caught a real ladder-direction inversion on a
three-band rate table that `catala typecheck` was green on.

When this lands, `CATALA-EXPORT-SPEC.md` §8.4's disclosed-open item is discharged **in the same PR**
or it is not discharged.

## Deferred obligations

Three of the Phase 1 rulings buy their speed by deferring something. This register exists because
two of Meng's ruling notes say, in different words, _don't let this evaporate_. An entry leaves this
table only when the work is done or the deferral is explicitly withdrawn — not because it stopped
being convenient.

| id     | what was deferred                                                                          | trigger                                                                                                     | owed by |
| ------ | ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- | ------- |
| **D1** | Phase 0 — core IR, reference semantics, defeasibility strategy, assertion-language surface | **The first deontic, timed or defeasible property anyone wants to check.** Phase 2 cannot start without it. | R-V1    |
| **D2** | Lifting `analyzeSafety` and `vizExprToBoolExpr` out of the `Dmn`/`Viz` namespaces          | The PR immediately after the prover's first. It does nothing else.                                          | R-V9    |
| **D3** | An `sbv`-backed implementation behind the same interface                                   | Hand-rolled SMT-LIB2 emission or model parsing costing more than it saves — pivot, do not endure.           | R-V6    |

**D1 is the one to watch.** It is deferred by a whole phase rather than a PR, it is the only one
whose absence is invisible while Phase 1 works fine, and it is the one Meng flagged in his own
words. A Phase 1 that ships and a Phase 0 that never starts is the failure this register is for.

## Open Questions

- **Backend selection:** automatic (infer from which IR features a query touches) vs explicit annotation?
- **Witness translation:** can a backend counterexample always be lifted back to an L4-level, citation-bearing trace a non-lawyer can read? — **Answered for Phase 1 by R-V5**: an SMT model is a concrete input, so the lift is an evaluator run rather than a translation, and the replay doubles as the confirmation. Open for the backends whose counterexample is a _path_ rather than an assignment.
- **Scope/bounds discipline:** for bounded engines, how do we communicate "checked up to scope N" honestly (no silent truncation of assurance)? — **Answered for Phase 1 by R-V8**: three verdicts, every `unknown` naming its reason, and a per-run coverage line. Open for the bounded engines, where the honest statement is about scope rather than about theory.
- **Defeasibility round-trip:** if the ASP layer changes the in-force set, must every downstream backend re-run, and how is that cached?

## References

1. Governatori, G. (2005). "Representing Business Contracts in RuleML." _Int. J. Cooperative Information Systems_.
2. Governatori, G. & Rotolo, A. (2006). "Logic of Violations: A Gentzen System for Reasoning with Contrary-to-Duty Obligations." _Australasian J. Logic_.
3. Hvitved, T. (2012). _Contract Formalisation and Modular Implementation of Domain-Specific Languages_. PhD thesis, U. Copenhagen.
4. Jackson, D. (2012). _Software Abstractions: Logic, Language, and Analysis_ (Alloy). MIT Press.
5. Lamport, L. (2002). _Specifying Systems_ (TLA+). Addison-Wesley.
6. Konnov, I., Kukovec, J., Tran, T-H. (2019). "TLA+ Model Checking Made Symbolic" (Apalache). _OOPSLA_.
7. Cavada, R. et al. (2014). "The nuXmv Symbolic Model Checker." _CAV_.
8. Behrmann, G., David, A., Larsen, K.G. (2004). "A Tutorial on Uppaal." _SFM-RT_.
9. David, A. et al. (2012). "TAPAAL 2.0: Integrated Development Environment for Timed-Arc Petri Nets." _TACAS_.
10. Holzmann, G. (2003). _The SPIN Model Checker_. Addison-Wesley.
11. Clavel, M. et al. (2007). _All About Maude — A High-Performance Logical Framework_. Springer.
12. de Moura, L. & Bjørner, N. (2008). "Z3: An Efficient SMT Solver." _TACAS_.
13. Clarke, E., Grumberg, O., Peled, D. (1999). _Model Checking_. MIT Press.
