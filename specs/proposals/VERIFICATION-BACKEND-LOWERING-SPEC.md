# Verification Backend Lowering Specification

**Status:** Proposal
**Author:** Meng Wong
**Date:** 2026-06-29
**Related:** [BOUNDED-DEONTICS-SPEC.md](../todo/BOUNDED-DEONTICS-SPEC.md), [ACTUS-L4-BRIDGE-SPEC.md](../todo/ACTUS-L4-BRIDGE-SPEC.md), [DEONTIC-TRACE-API-SPEC.md](../done/DEONTIC-TRACE-API-SPEC.md), [PROHIBITION-BREACH-SPEC.md](../done/PROHIBITION-BREACH-SPEC.md)

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

## Open Questions

- **Backend selection:** automatic (infer from which IR features a query touches) vs explicit annotation?
- **Witness translation:** can a backend counterexample always be lifted back to an L4-level, citation-bearing trace a non-lawyer can read?
- **Scope/bounds discipline:** for bounded engines, how do we communicate "checked up to scope N" honestly (no silent truncation of assurance)?
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
