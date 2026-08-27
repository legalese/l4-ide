# Reached versus Material — paper outline + venue scoping (v0.1)

> First-crack outline, 2026-08-27, generated alongside
> `specs/todo/CALL-GRAPH-MATERIALITY-SPEC.md` (which carries the measured evidence this paper
> leans on) and `related-work.md` (22 references, all verified against primary sources
> 2026-08-27). Everything here is provisional.

## Title candidates

- **"Reached versus Material: Counterfactual Explanation for Computational Law"** (front-runner).
  The two-word opposition carries the technical core: what an evaluator _forced_ is neither
  necessary nor sufficient for what legally _mattered_, and the gap between them is where
  explanation lives.
- Fallbacks: "Minimal Significant Counterfactuals in Computational Law"; "The Materiality Ladder";
  "Sliding Doors: pivotal events in executable contracts" (the film reference as a section title
  rather than the paper title, probably).

## Thesis (one sentence)

An execution trace of a legal decision, read naively, teaches the but-for fallacy — and the
repair is a materiality engine that computes membership in **minimal flip sets** (NESS-style, via
the AXp/CXp hitting-set duality) over the decision logic, extends to event traces as
**winning-region frontier crossings** over the contract automaton, and types history
counterfactuals by **time axis and legal remediability** through a bitemporal ledger.

## Program strategy (faceting)

One facet of the L4 papers series (`paper/README.md`): the **explanation facet**. The ICAIL intro
paper says L4 executes and explains; this paper says what "explains" must mean and measures what
happens when it doesn't. Adjacencies, to cross-cite rather than duplicate:

- `bounded-deontics/` owns the LTS/deontic semantics; this paper _consumes_ the automaton
  (winning regions, frontier pivots) and does not re-derive obligation semantics.
- `formal-methods-in-law/` owns the verification-ladder framing; the materiality engine is one
  more rung read through an explanation lens.
- The ladder-diagram and wizard work (question ordering, `l4 verify`'s shared atomId) is the
  implementation substrate, cited as system context.

## Claimed contributions (in order of novelty confidence)

1. **Typed bitemporal counterfactuals.** The XAI literature does not type counterfactual
   explanations by time axis; the valid-time / transaction-time / rule-version typing, with its
   mapping to legal remediability (incurable / curable / legislature's), appears to be new. The
   ledger-as-explicit-SCM observation (RECORD events are the exogenous variables) carries it.
2. **The metric is doctrine.** Trace-counterfactual admissibility (whose choices may be varied)
   is a legal parameter, not an algorithmic one — breach vs mitigation vs frustration select
   different intervention sets. Known in causation theory, not operationalized in XAI systems.
3. **The overdetermination trap as an implementation-experience finding.** Not merely that traces
   are incomplete: measured on a production evaluator, the natural directive idiom yields _no_
   explanation (spec F5) and short-circuit absence actively misleads (spec F6). Evidence that
   trace-only explanation is a defect class, not a missing feature.
4. **The unification claim.** Reached (trace), material (BDD flip-sets), and pivotal (automaton
   frontier) are three annotations of one dependency graph, and one engine feeds the diagram, the
   wizard prose, and the LLM tool-call payload.

## Section plan (mapping from the spec)

| §   | Working title                                              | Source                                                      |
| --- | ---------------------------------------------------------- | ----------------------------------------------------------- |
| 1   | Introduction: the but-for fallacy, taught by a debugger    | spec §1–§2 motivation; F5/F6 as hook                        |
| 2   | Background: L4, lazy evaluation, traces, the automaton     | spec §3; cite ICAIL paper                                   |
| 3   | The materiality ladder (M1–M4)                             | spec §2; NESS ↔ prime implicants; Chockler–Halpern grading |
| 4   | The engine: AXp/CXp over decision BDDs                     | spec D3; duality; tractability at statutory scale           |
| 5   | Event traces: frontiers, omissions, and doctrine as metric | spec §6.1–6.2; LTL₃; red dots; ghost branch                 |
| 6   | Typed history counterfactuals through the ledger           | spec §6.3                                                   |
| 7   | Implementation experience                                  | spec §4 (F1–F10), Appendix A protocol                       |
| 8   | Related work                                               | `related-work.md`                                           |
| 9   | Conclusion: explanation the wizard and the diagram share   | spec D5; convergence argument                               |

## Venue scoping

- **ICAIL** (primary): systems + theory fit; the implementation-experience section is the
  differentiator against pure-theory causation papers.
- **JURIX** (equal fit, earlier deadline cadence): same shape.
- **COMMA** (facet): if split, the argumentation strand (defeat edges for SUBJECT TO,
  Odekerken–Bex stability as the prospective mode) can stand alone there.
- Long-shot alternate: an FM venue for §5 alone (frontier crossings as anticipatory monitoring
  applied to contracts) — deliberately deferred, same "get the thoughts out first" policy as
  bounded-deontics.

## What must exist before submission

The paper's §7 is honest only if the engine exists. Minimum: D1 (static graph) + D2 (call-shaped
collapse) + D3 (AXp/CXp on at least the boolean skeleton) prototyped, re-measured against the
same corpus subset as Rung 0. §5–§6 can ship as formalization + worked example (CEO award /
promissory note automata already extract; the bitemporal example already traces). Implementation
proceeds on the same branch as the spec (`spec/callgraph-materiality`).

## Worked examples (candidates)

- **Decision side**: BNA scenario with two qualifying routes both true (overdetermination); Reg CF
  investment-limit thresholds (numeric CXps arrive as thresholds).
- **Event side**: promissory-note automaton — the missed-installment pivot, the cure window as
  open region, the timeout as omission-pivot; CEO award for multi-obligation structure.
- **History side**: `bitemporal-recall.l4` extended to a late-notice insurance shape: same
  verdict flip reachable via a valid-time edit (the accident) vs a transaction-time edit (the
  notice), with only the latter curable.
