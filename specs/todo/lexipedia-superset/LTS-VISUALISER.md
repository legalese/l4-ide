# P2 — the process/LTS visualiser

## Revision 2: what adversarial review changed, and why the picture is now gated

_Scoped 2026-07-26. Revised 2026-07-27 after a three-lens adversarial review (premise, accuracy,
buildability). Track P of [SPEC.md](./SPEC.md), spun out of
[PROCESS-TRACK.md](./PROCESS-TRACK.md) §7 under K5. **Own timeline.** It must not gate M4._

Companions: [`../ladder-diagrams-2026/DESIGN.md`](../ladder-diagrams-2026/DESIGN.md) §25.5 (the
seam this view is the far side of), [`../STATEFUL-CONTRACT-DEPLOYMENT.md`](../STATEFUL-CONTRACT-DEPLOYMENT.md)
§6.4 (the projections this view consumes), [`../../proposals/VERIFICATION-BACKEND-LOWERING-SPEC.md`](../../proposals/VERIFICATION-BACKEND-LOWERING-SPEC.md)
(the fan-out this view deliberately does **not** join).

---

## 0. Status, and what review changed

**Verdict of revision 1: DEFECTIVE, three reviewers out of three. None said the work should not
be done at all.** What did not survive was the _strength_ of the case, not the case. Revision 2
therefore does three things: it downgrades the claim, it defines the parts that were pointers to
nothing, and it moves the picture behind two falsification experiments and three preconditions.

**The headline change.** Revision 1 argued P2 on three questions — position, reachability,
dominance — and staged all six deliverables as one programme. Revision 2 concludes:

- **the back end is justified now** (P2b, P2c) and is worth building on its own merits;
- **the lead question's payload is data, not a picture** — a plain list answers it, and revision
  1 never considered that rival (§1.1a);
- **reachability, as P2 could actually compute it, is an over-approximation** and is now a named
  loss (G9), not a selling point;
- **dominance does not need the new picture at all** and is unbundled (P2f, §7.2);
- **the two-plane picture and the animator (P2d/P2e) are not justified by this document** and are
  gated behind §7.3's three preconditions and §7.2's two experiments.

If both experiments come back saying the list and the off-the-shelf simulator suffice, **P2d and
P2e should not be built**, and that is a good outcome, cheaply obtained.

### 0.1 Rulings

| #      | Ruling                                                                                                                                                                                                                                                                                                                                       |
| ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Q1** | **REVISED.** P2 answers **position**. Reachability it can only over-approximate (G9); dominance it can answer without a new picture (P2f). A P2 that only draws a prettier static graph still should not be built. §1                                                                                                                        |
| **Q2** | The formalism is a **two-plane marked transition system** — an action plane and a norm plane — with the drawing vocabulary borrowed from Petri markings, Symboleo lifecycles and Meyer's violation atom. §2                                                                                                                                  |
| **Q3** | **SCOPED.** The evaluator is the semantics **for the marking and the step log**. Anything counterfactual — the enabled set, the discharging/breaching partition — must be computed **by running the evaluator**, not by walking a residual. §2.4                                                                                             |
| **Q4** | The animated data is a new **deontic step log**, modelled on `traceEval`. It does not exist today; it is ~6 call sites in `Machine.hs`. The type is now defined, in §4.3. **BUILT 2026-09-15** (`lts/p2b-step-log`, merged into `lts/p2-stack` 2026-09-15, not yet in `unstable`): seventeen call sites, not six — see the §4.3 BUILT block. |
| **Q5** | **The bare Petri net is not better than BPMN at F1.** What closes F1 is reifying the norm as a marked place, which a net permits and BPMN has no vocabulary for. That is encodability, not expressiveness. §2.1                                                                                                                              |
| **Q6** | P1 emits a **file**; P2 renders a **view**. Two pictures, one stated division of labour. §5.1                                                                                                                                                                                                                                                |
| **Q7** | **REVISED.** The smallest useful first deliverable is **P2a′ — render the projections as a plain list and see whether anyone still wants a picture.** It is cheaper than the BPMN-simulator baseline, and it tests the question P2 actually leads with. §7                                                                                   |
| **Q8** | **NEW.** `StateGraph` as shipped **cannot** be P2's layout scaffold. It carries no key a runtime obligation can be correlated to, and it does not close loops. Both are P2 preconditions, and both are now cheaper than they were. §3.4                                                                                                      |

### 0.2 Disposition of every review finding

Nothing here is dropped. "Fact changed" means the finding was correct when filed and the tree has
since moved.

| #      | Finding                                                                             | Disposition                                                                                                                                         |
| ------ | ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1**  | Reachability claimed with no sound mechanism; over-approximation absent from §6     | **Accepted.** Q1 downgraded; mechanism stated and its unsoundness named as **G9**. §1.1b, §6                                                        |
| **2**  | P2a can only test the position question, yet gates P2d/P2e/P2f                      | **Accepted.** P2f unbundled from P2d (§7.2); P2a′ added as the gate that tests the lead question; each experiment now states what it cannot falsify |
| **3**  | Keeping `StateGraph` as layout scaffold contradicts gap 3 for recursive contracts   | **Accepted.** Ruling reversed — Q8 and §3.4. Loop closure is precondition **B2**, and it is shown to break P1's layout algorithm (§4.7)             |
| **4**  | The strongest rival — a plain list over endpoints 17-20 — was never considered      | **Accepted, and it is the most important finding in the set.** §1.1a; it becomes deliverable P2a′ and the primary gate                              |
| **5**  | P2d/P2e unbuildable: `DeonticStep` undefined, marking underived, no correlation key | **Accepted.** Type defined (§4.3), marking derivation defined (§4.2a), correlation key identified and made precondition **B1** (§3.4)               |
| **6**  | Dependency accounting contradictory; P2a depends on P1, and P1 does not exist       | **Fact changed.** P1 shipped in `cfeaea5d` (PR #141) on 2026-07-26 — `L4.Bpmn.{IR,Lower,Emit}`, goldens, Camunda import check. §7.1 rewritten       |
| **7**  | `ValROp` unmapped; §3.1 followed literally draws a false violation                  | **Accepted.** Rows added, with the flattening rule and the exact `ROr` counterexample. §3.1                                                         |
| **8**  | `DDo` has no row; `MAY` expiry → `LEST` is un-drawable                              | **Accepted.** Both rows added. §3.1                                                                                                                 |
| **9**  | Layout omitted — algorithm, cost, language                                          | **Accepted, and now evidenced.** P1 spent ~400 lines on layout and had to emit `P-CYCLE` because of it. §4.7                                        |
| **10** | Both §7.2 DOIs resolve to unrelated papers                                          | **Accepted and corrected**, and the claim they support was itself an over-claim. §7.4                                                               |
| **11** | "Each `AllOf` branch runs to its own `Fulfilled`" contradicts the cited code        | **Accepted.** The sinks are shared; corrected in gap 6 and R2                                                                                       |
| **12** | Q3's "no second semantics" contradicted by P2c's pure-walk plan                     | **Accepted.** Q3 scoped; P2c switched to the replay form (endpoints 22/23/24). §2.4, §7.2                                                           |
| n1     | 11-vs-14 `ContractFrame` miscount                                                   | **Corrected** — the sum has 14 constructors. §4.3                                                                                                   |
| n2     | `noteLedgerWrite` misnamed for `tellEventRouted`                                    | **Corrected** — `tellEventRouted` (`Machine.hs:552-555`) is the "modeled on `traceEval`" one; `noteLedgerWrite` is a one-liner at `:618`. §4.3      |
| n3     | "`traceEval` emitted only from the generic dispatch loop" is false as stated        | **Corrected** — it also fires at `Machine.hs:322,463,469,702,722`. The load-bearing claim (no `ContractFrame` emits) survives. §4.2                 |
| n4     | Q5's "BPMN forbids" overstates                                                      | **Corrected** to "has no vocabulary for". Q5, §2.1                                                                                                  |
| n5     | Wrong or inexact quote anchors (reachability, Hart, "reusable unchanged", the Crux) | **Corrected throughout**, and re-verified line by line against the tree at `cfeaea5d`                                                               |

---

## 1. The question this picture answers

### 1.1 The honest test

We ship or plan six pictures. Before adding a seventh, the test is whether any existing one
already answers its question.

| Picture                                    | The question it answers                                  |
| ------------------------------------------ | -------------------------------------------------------- |
| ladder (Track L)                           | _does this rule apply to me, and which term decides it?_ |
| DMN table (D1)                             | the same, as a table a business analyst can edit         |
| wizard (C2)                                | _what is my answer, and why — with citations?_           |
| `stateGraphToDot` (ships today)            | _what is the shape of this contract?_                    |
| BPMN (P1, ships as of `cfeaea5d`)          | the same shape, in a file someone else's tool can open   |
| `GraphViz2` evaluation trace (ships today) | _how did the evaluator reach this value?_                |

None of them answers this:

> **Given what has happened so far — what do I owe right now, what would discharge it, and what
> would put me in breach?**

That is a question about a **position**, not a shape. The state graph draws the board; the
residual `ValObligation` holds the position; nothing draws the position on the board. Today the
residual is rendered as text and only as text — see `jl4/examples/ok/tests/contracts.golden:4-8`,
which prints `PARTY B / MUST return / WITHIN 4 / HENCE FULFILLED` and expects the reader to
locate that in the picture themselves.

### 1.1a The rival revision 1 did not consider: a list

The table above compares P2 only against **pictures**. That is not the honest test; it is a
rigged one. The lead question decomposes into three clauses, and all three are already specified
as **data**, in `STATEFUL-CONTRACT-DEPLOYMENT.md` §6.4:

| The clause                    | The datum                                                                              |
| ----------------------------- | -------------------------------------------------------------------------------------- |
| _what do I owe right now_     | endpoints 14/15/16 (`obligations`/`permissions`/`prohibitions`) and 17 (next deadline) |
| _what would discharge it_     | endpoint 19, `discharging_events`                                                      |
| _what would put me in breach_ | endpoint 20, `breaching_events`                                                        |

So the strongest rival to P2 is not another diagram. It is **a bulleted list**, with no graph, no
new IR, no formalism, no layout, and no correlation key. Revision 1 half-knew this and did not
follow through: §4.2 lists exactly these endpoints as P2's own data sources, and §4.1 concedes
that the norm-plane marking "is the picture's payload; the control token is context for it" — an
admission that the payload is obtainable without the picture.

**This document does not know whether the picture beats the list.** Nobody has tried. That is
what P2a′ is for (§7.2), and it is now the first deliverable and the primary gate.

What the list plainly cannot do is show **where** in the contract you are, or **what happens
after** what you are about to do. Whether a reader wants that badly enough to fund a graph is an
empirical question, and this document declines to answer it from the armchair.

**LANDED 2026-09-15 (P2a′), on `lts/p2b-step-log` (merged into `lts/p2-stack` 2026-09-15, not yet in `unstable`): the list exists.** `l4 lts FILE`
prints it for every `#TRACE` in the file; §7.6 has the command, one contract's exact output, and
what it can and cannot answer. The reader experiment §7.3 gates on has **not** been run and this
document still does not know whether the picture beats the list.

### 1.1b Reachability: what P2 can honestly claim, which is less than revision 1 claimed

The ladder work poses a question at its seam and hands off:

> **Can the red lamp be lit?**

`DESIGN.md:1338-1341` — _"the citizen asks 'is green lit?', the litigator asks 'can red be lit?'
— which is a **reachability query**, and one **the verifier** can actually discharge."_

Note the subject of that sentence. It is the **verifier**, and P2 is not one: §2.4 rules that P2
renders the state the evaluator is already in, §5.4 declines a TAPAAL lowering, and §5.2 declines
to draw guards at all. The evaluator computes forward from supplied events; it does not quantify
over futures. So the only reachability P2 can compute is a **topological walk of the drawn
graph** — and that walk is blind to three things the evaluator is not:

1. **`PROVIDED` guards.** The evaluator gates every match on the guard: `Contract9`
   (`Machine.hs:1570-1575`) evaluates `fromMaybe trueExpr act.provided` and `Contract10`
   (`:1577`) branches on the result. A transition whose guard is false is not fireable, but it is
   drawn, so a topological walk will report a breach state reachable when it is not.
2. **Action-pattern matching.** Gap 2: `PatApp n args` renders as `n <> " ..."`, so `pay 100` and
   `pay 5` are one edge in the graph and two different matches at runtime.
3. **Deadline arithmetic.** Gap 7: `WITHIN` is a string in the IR and a decremented `Rational` in
   the evaluator (`Machine.hs:1469`), so timing-dependent unreachability is invisible.

**Therefore:** structural reachability is an **over-approximation**. It can say _"no path
reaches red"_ soundly (a genuine and useful answer — nothing you do can breach this clause). It
**cannot** soundly say _"red is reachable"_, which is the litigator's actual question. Revision 1
sold the second reading. That is now recorded as loss **G9**, and Q1 no longer rests on it.

Sound reachability is the verification backend's job, and `VERIFICATION-BACKEND-LOWERING-SPEC`
already owns it (`:55-56`, UPPAAL/TAPAAL, _"Is the double-bind state reachable within these
deadlines?"_). The available honest role for P2 is to **render a counterexample the verifier
produced**, not to discharge the query itself — which is a much smaller claim, and one that
cannot be made until there is a verifier. R3.

### 1.1c Dominance, and why it does not need this picture

Third, and already promised in print: the bounded `MUST` of the bounded-deontics paper is the
dominator set `dom_s(J)` over exactly this graph, and the paper is candid that it is
unimplemented (`paper/bounded-deontics/draft/bd-sections-7-9.tex:68-85`: _"realising it is a
near-linear dominator computation … over a graph that already exists in memory, not new
infrastructure"_).

Revision 1 listed this under P2 and made it depend on P2d. **That was an error of bundling.**
Lengauer–Tarjan over `StateGraph` is a Haskell pass with no renderer in it; its answer is a
_set of acts_ — "on every path from here to J you must do these" — which prints perfectly well as
a list, or as an annotation on the **BPMN P1 already emits**. It is unbundled in §7.2 and no
longer gates on, or is gated by, the new picture.

> **LANDED 2026-09-15** (`lts/p2f-dominators`) — `jl4-core/src/L4/StateGraph/Dominators.hs`,
> a new module with no edit to `StateGraph.hs`. The dominator query itself has no dependency
> on P2b/P2c/P2h; the reader-facing wording of an `EVERY` act reads P2h-first-half's
> `labelQuantifier` / `JoinLabelKind` (`Dominators.hs`, `renderTransition` and `joinText`), so the
> branch is based on `fix/join-on-state-graph` and merges after it — measured:
> `git log -S labelQuantifier -- jl4-core/src/L4/StateGraph.hs` lists only `f1efcbd2`, which is
> on that branch.
>
> **Algorithm.** Not Lengauer–Tarjan. The classical dominance equations —
> `Dom(entry) = {entry}`, `Dom(n) = {n} ∪ ⋂ Dom(pred)` — solved by iteration to their greatest
> fixpoint over the reachable nodes (`solveDominators`, `Dominators.hs`). That is the
> formulation Cooper, Harvey & Kennedy, _A Simple, Fast Dominance Algorithm_ (Rice CS
> TR-06-33870; see the bibliography) §2 start from; the answer is identical **by definition**
> — the dominator set of a node is unique, and every correct algorithm computes exactly it.
> The graphs are tens of nodes, so the near-linear engineering (theirs or Lengauer–Tarjan's)
> buys nothing here. Two adaptations: (i) acts are **edges**, so every transition is
> subdivided into a node of its own and the answer is read off the edge nodes; (ii) **neither
> `RAND` nor `ROR` has its join in the IR** (R2), so a literal walk says neither branch of a
> conjunction dominates `Fulfilled` and neither alternative of a choice dominates `Breach`.
> The evaluator's join (`Machine.hs`, `RBinOp2`: _"for RAND because all components must be
> fulfilled, for ROR because every alternative has been definitively lost"_) is supplied by
> two dual views, each for the one query that needs it: `fulfilmentView` rewrites each
> `AllOf` so its branches run in sequence — branch _k_'s arrivals at `Fulfilled` are
> re-pointed at branch _k+1_'s entry — and `breachView` does the same to each `ROR`-derived
> `OneOf` with arrivals at `Breach`. Each has the same set of edges on every path to its sink
> as the concurrent contract has on every run, since dominance is order-blind. An
> `IF`-derived `OneOf` (branch edges carry a `labelBranch`) is exclusive and left alone by
> both; an intermediate state lies inside one branch and is answered over the literal graph.
>
> _What review changed (2026-09-15)._ The first cut carried only the `RAND` half and asserted
> that breach "is already right" over the literal graph — the §2.4 hazard exactly, a
> re-derivation of half the `RBinOp` join. Measured with `l4 run` on
> `(PARTY Alice MUST pay WITHIN 3) ROR (PARTY Bob MUST deliver WITHIN 5)`: a stray event AT 4
> gives a residual `… OR PARTY Bob MUST deliver WITHIN 1`, AT 6 gives the breach — so both
> deadlines are on every run to `Breach`, and the tool now says so (`DominatorsSpec.hs`, "ROR:
> both timeouts dominate the breach sink"; nested cases `(a RAND b) ROR c` → only `c`'s
> deadline, `(a ROR b) RAND c` → nothing, each cross-checked the same way).
>
> **Scope, stated.** Two narrowings of the paper's `dom_s(J)` are deliberate: the question is
> asked from the start state only (no `s` parameter), and per **edge**, not per action label —
> the same act on two edges (say `sign` in both arms of an `IF`) dominates nothing here where
> the paper would count the label.
>
> **Command.** `l4 state-graph --dominators FILE` prints, per rule, the acts every path to
> `FULFILLED` and to `BREACH` must traverse; `--all-states` widens it to every state. Default
> DOT output is byte-identical to the reference checkout's 7 Aug binary on
> `jl4/examples/ok/contracts.l4`, `jl4/examples/bpmn/offering.l4` and
> `doc/reference/regulative/state-graph-example.l4` (measured by `diff`, 2026-09-15);
> `l4-cli-test` asserts only that the DOT path still prints DOT and no dominator text. The DOT
> annotation ("bold the dominating edges") was **not built** on that branch: it needs an option
> on `StateGraphOptions`, which was an edit to `StateGraph.hs` the branch was told to avoid while
> a fix to that file was in flight.
>
> **Annotation LANDED 2026-09-16** (`lts/b1-b2-loops`). `l4 state-graph --dominators --dot FILE`
> keeps the DOT and, for each terminal, draws every dominating edge with `penwidth=3` and a
> caption line `on every path to FULFILLED` / `… to BREACH` / `… to FULFILLED and to BREACH`
> (`StateGraphOptions.showDominators`, default `False`). `--dot` without `--dominators` and
> `--dot` with `--all-states` are refused (exit 1), as `--all-states` alone already was. **The
> option forced a module split**: `StateGraphOptions` and the renderer now live in
> `jl4-core/src/L4/StateGraph/Dot.hs`, because a Bool on the options record can only be honoured
> by a renderer that can call `dominators`, and `L4.StateGraph.Dominators` imports
> `L4.StateGraph` — so the renderer had to move below both. The IR and extraction stay in
> `L4.StateGraph`; four importers (`Lens.hs`, `jl4-service/DataPlane.hs`, `jl4-mlir/Schema.hs`,
> `Cli/StateGraph.hs`) changed one import line. **Default output byte-identical, pinned three
> ways**: the 71-file corpus DOT diff under B1 alone (none changed), `StateGraphSpec` "changes
> nothing when off" and "does not change the unmarked edges' attributes" (the marked edge's
> attribute list is the plain one with `penwidth` _appended_, so an unmarked edge's lines cannot
> drift), and `l4-cli-test` "without --dominators the DOT output is unchanged". Matching is by
> transition value, not index — `dominators` answers in transitions — which marks both of two
> byte-identical parallel edges if either dominates; neither can (each is one of two routes), so
> the ambiguity is not reachable.
>
> **Corrected 2026-09-16 (review).** The annotation marked edges the list never names. The list
> goes through `renderTransition`, which returns `Nothing` for a bare `RAND`/`ROR` branch edge (no
> party, no guard: a party does not _do_ a branch edge); `dominatorEmphasis` applied no such
> filter, so on `doc/reference/regulative/state-graph-example.l4`'s `delivery and payment` the
> FIRST branch edge came out `0 -> 1 [label="on every path to FULFILLED", penwidth=3]` while its
> sibling `0 -> 4` did not — an artefact of the sequential view, in which branch 1's fan edge is
> the only one kept. `STATE-GRAPH.md`'s "an arrow the list would not name is drawn exactly as it
> is without the flag" was false on the doc's own example. Fixed by one shared predicate,
> `Dominators.namesAnAct = isJust . renderTransition`, applied in `dominatorEmphasis`; pinned by
> `StateGraphSpec` "leaves a RAND's branch edges unmarked" (on `randSrc`: two `penwidth=3`, two
> captions, no caption on a `label=""` edge) and by the `l4-cli-test` `--dominators --dot` case.
> Corpus: after the fix no `label="on every path` / `label="\non every path` remains in any of the
> 71 DOTs.
>
> **Measured**, `l4 state-graph --dominators jl4/examples/ok/contracts.l4`:
>
> ```
> aContract
>   Every path to FULFILLED passes through:
>     - PARTY S delivery (MUST, WITHIN 3)
>   Every path to BREACH passes through: nothing in particular (there is more than one route).
> ```
>
> — correct on inspection of the graph: B's payment is bypassed by the `LEST` fine, and
> breach is reachable from the first deadline. On the spec fixtures in
> `jl4-core/test/DominatorsSpec.hs` (27 examples, 0 failures): a chain dominates its sink with
> every act; `ROR` fulfils with nothing and breaches with **both** timeouts; `RAND` fulfils
> with **both** branches (two-way and three-way) and breaches with nothing; `(a ROR b) RAND c`
> fulfils with `c` alone; `(a RAND b) ROR c` breaches with `c`'s timeout alone; an `IF` arm
> dominates the state inside it and is not sequentialised; a renewing duty (`HENCE` to self)
> terminates and only its timeout reaches breach; a hand-built unreachable state answers
> `Unreachable` (as of this block extraction never drew one — a rule whose arms were other named
> rules had no sink at all, and printed "this graph has no FULFILLED or BREACH state to reach".
> **Superseded by B2, 2026-09-16:** such a rule now draws the named rules' sinks and is answered
> like any other; "no FULFILLED or BREACH state" remains for a rule none of whose arms reaches a
> sink — permissions leading on to permissions, or a hand-over the map cannot follow; and
> `Unreachable` IS now reachable from a real file, truthfully, when the join cuts every route to a
> drawn sink — `(PARTY Alice MUST foo HENCE v) RAND (PARTY Bob MUST bar)` as `v`'s body, whose
> first branch can only renew, answers "No path reaches FULFILLED". See §3.4's B2 correction for
> the case where the same words were a false answer).
>
> **What the answer inherits** is §1.1b's three blind spots unchanged — it is sound in the
> direction "this act is on every drawn route" and says nothing about whether each drawn
> route is live — **plus one in the opposite direction**: a bare `MAY` whose `HENCE` leads on
> to another obligation lapses straight to `FULFILLED` in the evaluator, and the graph does not
> draw that route (`StateGraph.hs`, the `DMay` NOTE in `extractDeonton`). Measured:
> `PARTY Alice MAY pay WITHIN 5 HENCE (PARTY Bob MUST deliver WITHIN 10)` with a stray event
> AT 6 evaluates to `FULFILLED`, while `--dominators` lists both `pay` and `deliver` as on every
> path to `FULFILLED`. So "listed ⇒ necessary" fails below a lapsing `MAY`. The user page
> (`doc/reference/regulative/state-graph.md`, "What the answer does not know", item 4) says
> so; fixing the drawing is a separate change and would retire the caveat.

### 1.1d So what is left of the existence argument

Honestly stated:

- **Position** — real gap, real question, and the picture's advantage over the list is **untested**.
- **Reachability** — P2 can offer only an over-approximation, and the sound version belongs to a
  verifier that does not exist yet.
- **Dominance** — real, promised, and achievable without any of this.

That is a materially weaker case than revision 1 made, and it is the reason §7 now spends a
week on experiments before it spends a month on a renderer. The corollary from revision 1 stands
and is if anything sharper: **a P2 that only redraws the static graph more attractively answers
nothing and should not be built.**

### 1.2 The claim is narrower than the flowchart claim, and must be advertised as such

`doc/concepts/language-design/logic-not-flowcharts.md` is our standing argument that drawing a
_predicate_ as a flow is a category error. **It gives P2 no licence.** Its own table
(`:868`) lists `BPMN · Harel statechart · Petri net · DFA` as **co-equal** principled formalisms
for state transitions, BPMN named first; and `:697` lists them again in prose without ranking.
PROCESS-TRACK §1 reads it the same way — _"Exporting BPMN from the regulative layer is us using
the notation for the thing it is for."_

A P2 spec that cites `logic-not-flowcharts.md` as authority for _"BPMN is the wrong picture for
process"_ would be misquoting our own document. The argument has to come from the fidelity
report, and it is:

> **Correct category, missing vocabulary.** BPMN is the right kind of picture for a regulative
> rule. It simply has no words for three of the things the rule says.

And that fidelity report now exists in the tree rather than in prospect:
`jl4/examples/bpmn/expected/offering.fidelity.txt` names F1 five times, on specific elements,
including _"A prohibition is not an activity at all and BPMN has no negative shape for one, so
read literally this diagram instructs the reader to perform the very act the rule forbids."_

### 1.3 What "the Petri-net lineage from earlier work" resolves to

§7's phrase is a documentary lineage, not an artefact: a repo-wide search finds **no Petri
construct in any `.hs`, `.ts`, `.svelte`, `.l4` or `.cabal` file** (re-verified at `cfeaea5d`),
and only a handful of mentions in prose. It currently points at four different things, and
leaving it ambiguous will cause someone to cite the wrong one.

| Candidate                                                                                  | Verdict for P2                                                                            |
| ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------- |
| `EVERY-EACH-QUANTIFIER-SPEC` §3.1/§3.2/§14 — `EVERY` = AND-join, `EACH` = fork             | **This is what §7 means for semantics.** The only place L4 constructs get Petri readings. |
| `VERIFICATION-BACKEND-LOWERING-SPEC:56` — TAPAAL, timed-arc nets, "parties-as-token-flows" | **This is what §7 means for tooling** — and P2 declines to join it. §2.4                  |
| `logic-not-flowcharts.md:697,868`; `DESIGN.md:1207-1209,1368-1372`                         | The published promise P2 redeems.                                                         |
| `DMN-STEELMAN` — Zaidi & Levis 1997, Petri-net encoding of decision-rule chains            | **Red herring.** Decision-side verification; not this.                                    |

---

## 2. The formalism

### 2.1 The ambition's own suggestion, checked sceptically

PROCESS-TRACK §7 proposes the Petri-net lineage as the starting point. Taken literally — draw a
plain place/transition net — **it does not do what §7 wants it to do.** State this before a
reviewer does.

1. **BPMN is token-based already.** Its execution semantics is a token traversing sequence
   flows. Whatever P2 gains from "the token game", it does not gain by introducing tokens.
2. **Neither notation has a deontic primitive.** A net has one kind of transition; BPMN has one
   kind of task. In both, a modality must be _encoded_.
3. **Their defaults are opposite and both are wrong half the time.** Petri firing is
   **permissive** — an enabled transition _may_ fire, nothing compels it — so `MUST` needs
   fairness, urgency, or a timeout transition bolted on. BPMN flow is **prescriptive** — drawing
   a task is ordering it — so `MAY` needs a gateway and a skip branch, which is indistinguishable
   from a genuine business choice. This is not our observation: Kossak et al., _Deontic Process
   Diagrams_ (2016), _"all activities are (tacitly) obligatory, and whenever something should be
   optional, a gateway is used to split the process flow."_
4. **The tempting `SHANT` fix is wrong for law.** An inhibitor arc that disables the prohibited
   transition is **regimentation, not prohibition**. A prohibited act must remain _possible_ and
   _sanctioned_, or there is no violation to model, no reparation, and no contrary-to-duty chain
   — which is `LEST`, i.e. the entire point. The correct net encoding of `SHANT` is a fireable
   transition into a violation place, which is structurally the same trick as BPMN's task →
   error end event.

**The honest ledger**, in the F1-F5 vocabulary:

| Loss   | Plain Petri net vs BPMN                                                                                                                                                                                                                                     |
| ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **F1** | **No improvement.** Both need a convention. A norm plane fixes it — but that is a modelling architecture, not the net.                                                                                                                                      |
| **F2** | **Worse** for plain P/T (BPMN at least has lanes). Fixed by coloured nets, via token colour.                                                                                                                                                                |
| **F3** | **Yes, by encodability.** You may add a place and mean what you like by it, so `NeverApplicable` and `Discharged` become distinct markings. BPMN has no token-holder outside the control flow — not a prohibition in the standard, but an absence of words. |
| **F4** | **No.** A coloured net swaps an opaque string for a second language (CPN ML). Only single-sourcing closes this.                                                                                                                                             |
| **F5** | **No.** Not a property of any notation. §6.                                                                                                                                                                                                                 |
| —      | **Yes**, off-list: unambiguous semantics, true concurrency, and a **drawable complete state**. BPMN's own inclusive OR-join has non-local semantics, which is why Dijkman, Dumas & Ouyang (IST 50(12):1281-1294, 2008) map BPMN _to_ nets to analyse it.    |

So the sentence P2 must contain and must not soften:

> Petri nets do not express obligation. What they give us is a **free place** — a token-holder
> whose meaning we choose — and that is enough to build a norm plane in which a deontic position
> is a marked place, a violation is a transition, and a discharged obligation and a
> never-triggered one are different markings. BPMN has **no vocabulary for** a free place, which
> is why F2 and F3 are closed to it. **F1 is closed to a bare Petri net too.** It opens only with
> the norm plane, and the norm plane is an architecture we must design and justify, not a feature
> we inherit.

_(Revision 1 wrote "BPMN forbids". It does not forbid; the standard has data objects, artifacts
and text annotations one could abuse. What it lacks is a token-holder with execution semantics
outside the control flow — an absence of vocabulary, which is the whole thesis of §1.2 and is
weakened, not strengthened, by overstating it.)_

### 2.2 Four formalisms that do carry deontic content, and what each contributes

| Source                                                                                                                             | The move                                                                                                                                                                                                        | What P2 takes                                        |
| ---------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| **Anderson 1958** (_Mind_ 67(265):100-103); **Meyer 1988** (_NDJFL_ 29(1)) — `Fα ↔ [α]V`, `Pα ↔ ⟨α⟩¬V`                           | A distinguished **violation atom**. The three modals differ only in which transitions reach `V`.                                                                                                                | The reduction itself, and its price. §6 G4           |
| **Sileno, Boer & van Engers**, LPPN (AICOL/MIREL 2018, DOI `10.1007/978-3-030-00178-0_6`; author copy `MIREL2017.pdf`)             | **Two planes.** A procedural net for the world; a declarative net where normative positions — `Perm(A)`, `Forb(A)`, `Obl(B)` — are **places**, joined by constitutive links. CTD is topological, not axiomatic. | The architecture. §2.3                               |
| **Azzopardi, Pace, Schapachnik & Schneider**, contract automata (_AI & Law_ 24(3):203-243, 2016; timed variant arXiv `2410.12585`) | Modality annotated on **states**, not transitions. A state carries the set of norms in force — i.e. **a marking**. Persistent vs ephemeral norms.                                                               | Confirmation of where deontic status lives. §3.4     |
| **Sharifi, Parvizimosaed, Amyot, Logrippo & Mylopoulos**, Symboleo (RE 2020; _SoSyM_ 2022, DOI `10.1007/s10270-022-01053-6`)       | **One statechart per obligation and per power** — created / in-effect / suspended / discharged / violated / terminated.                                                                                         | The F3 answer: vacuity becomes a _named state_. §3.1 |

A fifth, **Lomuscio & Sergot**, _Deontic Interpreted Systems_ (_Studia Logica_ 2003; implemented
in MCMAS), partitions each agent's local states into "green" (correctly functioning) and "red",
with `O_i φ` holding iff `φ` holds in all of agent _i_'s green states — a **per-agent colouring
of states**. **Unverified:** the primary PDF would not extract and this characterisation rests on
secondary sources. It is flagged in R8 because it carries architectural weight — if correct, it
is a third independent formalism locating deontic status off the transition, and it is
per-party, which is the F2 shape.

### 2.3 The ruling — a two-plane marked transition system

**Action plane.** The control skeleton: states, transitions, and P0's `AllOf`/`OneOf` junctions.
This is the board. `L4.StateGraph` extracts a first approximation of it and **cannot serve as it
unmodified** — Q8, §3.4.

**Norm plane.** One **place per norm instance**, marked when that norm is in force. A norm
instance is an obligation as the evaluator holds it — `ValObligation` with its bearer, its
`RAction`, its residual deadline and its `HENCE`/`LEST` continuations
(`jl4-core/src/L4/Evaluate/ValueLazy.hs:60`). Each place carries a **lifecycle**, after Symboleo,
and the marking of the norm plane at any point _is_ the answer to §1.1's first question — which
is also exactly why §1.1a's list rival is live, since a marking prints as a list.

**Constitutive links** join the two: an action-plane transition firing is what _counts as_
discharging, violating or triggering a norm-plane place. This is LPPN's move and it is what makes
`LEST` drawable as topology rather than as a labelled arrow.

Three consequences worth stating plainly.

- **`SHANT` becomes drawable.** The prohibited act stays in the action plane as a fireable
  transition — as it must, or the violation vanishes — and the norm plane says the firing lights
  the violation. `MAY` costs **almost** no ink in the norm plane: an action with no violation
  link. (Not _no_ ink — see §3.1's `MAY`-expiry row, which revision 1 got wrong.) That is
  precisely the F1 loss, recovered.
- **Vacuity becomes a marking, not an absence.** An obligation that never became applicable sits
  in `Created`; one that was discharged sits in `Fulfilled`. Two distinct, nameable, drawable
  states. Today `StateType` (`StateGraph.hs:90-94`) has `TerminalFulfilled` and `TerminalBreach`
  and **no "never applicable"** — so our IR has BPMN's F3 problem natively.
- **The verdict vocabulary is not new.** Use the one already shipped on the decision side:
  `Undetermined | Holds | Fails | Complies | InBreach | NotApplicable` (`DESIGN.md:1506`). A
  wizard, a ladder and an LTS view that disagreed about one case would be, in that document's
  words, _"lying to the same user, in the same window"_ (`DESIGN.md:1524-1525`).

**Why not each alternative:**

| Rejected                                                                             | Because                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Bare Petri net                                                                       | §2.1. No deontic vocabulary; permissive default; the `SHANT` encoding is BPMN's trick with different ink.                                                                                                                                                                                                                                                                                                               |
| Coloured Petri net                                                                   | Fixes F2, and F4 only by introducing CPN ML as a second language. Deontics would be a colour field by convention — which is what `formatModal` already does on a DOT edge label.                                                                                                                                                                                                                                        |
| Harel statechart alone                                                               | The right shape for **one norm's lifecycle**, which is why we take it for the norm plane. It is not the right shape for the whole contract: orthogonal regions give concurrency but no marking to point at.                                                                                                                                                                                                             |
| DFA alone                                                                            | Flood & Goodenough's own framing, and the source of `StateGraph`'s lineage. A single flat control state cannot hold a set of live norms.                                                                                                                                                                                                                                                                                |
| DECLARE / ConDec (LTLf constraints)                                                  | **The road not taken, and it beats us on two counts.** Being open-world, it draws `absence(a)` natively — prohibition costs one glyph — and permission costs nothing. It also has a published, tool-supported notion of **vacuous satisfaction** (Di Ciccio et al., BPM 2016), which is F3 solved elsewhere. It loses the path, the token and the trace — i.e. everything §7 asks for.                                  |
| Deontic BPMN (Natschläger, DEXA 2011; _SoSyM_ 2015, DOI `10.1007/s10270-013-0329-5`) | Tasks explicitly classified obligatory / permissible / forbidden / alternative, with a proved semantics-preserving transformation. **Someone will ask why not this.** Two answers: it is a research extension, not OMG BPMN, so it does not open in Camunda Modeler and K4 dies; and marking a _task_ obligatory still gives you neither the norm's lifecycle (F3) nor its bearer apart from its performer (F2).        |
| C-O Diagrams (Martínez et al., TSE 2013)                                             | The closest existing artefact to the picture P2 wants — obligations, permissions, prohibitions, timing, penalties, timed-automata semantics, a CNL and an interactive editor. It is not design-changing because it is an **authoring** notation: the diagram is the source. Our whole thesis is that the language is the source and the picture is derived. Cite it as the strongest form of the opposing architecture. |

### 2.4 The evaluator is the semantics — scoped

`VERIFICATION-BACKEND-LOWERING-SPEC` governs a **fan-out** of semantics-preserving lowerings
over a pinned core IR, each carrying an explicit faithfulness obligation and a cross-validation
harness, precisely to avoid _"N backends quietly encoding different notions of 'obligation'"_.

**P2 declines to join it.** The ruling, with revision 2's scope attached:

> P2 renders the state that `L4.EvaluateLazy` is already in. It borrows a **drawing vocabulary**
> — marking from Petri nets, per-norm lifecycle from Symboleo, violation state from
> Anderson/Meyer — with named provenance, and it defines **no second semantics**. The picture is
> correct iff it agrees with the evaluator; there is no net to also be right about.
>
> **Scope (revision 2).** This exemption covers only what the evaluator has already computed:
> the **step log** (§4.3) and the **marking** derived from the residual (§4.2a). It does **not**
> cover anything counterfactual. The enabled set, and the discharging/breaching partition, are
> **predictions about events that have not happened**, and they must be obtained by **running the
> evaluator** on the hypothetical — not by re-deriving its modal routing in a second place.

Revision 1 failed its own rule here, and the review caught it. `STATEFUL-CONTRACT-DEPLOYMENT`
§6.4 specifies endpoints 19/20 as _"subset of (18) that would lead to `FULFILLED`/`BREACHED`"_
with _"No event replay; microsecond responses"_. Answering "would lead to FULFILLED" without
replay means reimplementing, outside `Machine.hs`, the `SHANT`-inverts-polarity rule (`:1583-1607`),
the `MAY`-expiry-routes-to-`LEST` rule (`:1532-1536`), and the `RAND`/`ROR` join with its CSL
tie-break (`:1635-1707`). That is a second notion of obligation, arrived at by the exact route
the fan-out spec exists to forbid. §5.1's own success criterion — _"it agrees with the evaluator,
event for event"_ — is a faithfulness obligation in all but name.

**Ruling.** P2c uses the **simulation** endpoints (`STATEFUL` §6.5, **22/23/24** — _"load the
actor's persisted history, run the evaluator with the hypothetical events appended, return the
result, don't write"_), not the pure-walk projections. It is slower and it is correct. The
micro-second pure-walk form remains a legitimate optimisation for someone who wants it, behind a
cross-validation test against the replay form; it is not P2's entry point. R11.

This is not a dodge; it is what makes P2 cheap and honest. A genuine timed-arc lowering to TAPAAL
remains available and desirable, and it is a **different piece of work** with a faithfulness
obligation attached. Re-opening condition in R3.

The corollary is that **K6 is not in tension with P2, it is the answer.** K6 was written for
exporters, and reads _"the service serves data, the browser draws."_ P2 obeys it exactly: the
step log, the marking, the enabled set **and the rank/lane assignment** (§4.7) are Haskell in
`jl4-core`, served as data; the animation is TypeScript in the browser.

**LANDED 2026-09-15 (P2c), the replay form as built, on `lts/p2b-step-log` (merged into `lts/p2-stack` 2026-09-15, not yet in `unstable`).**
`jl4-core/src/L4/Lts/WhatIf.hs`. It contains no modal routing: grep it for `DMustNot`, `DMay`,
`ToLest` — none. What it contains:

- **A candidate is** (`candidatesOf`, `WhatIf.hs:219`) one of three things read off the
  position's residual, which is data the evaluator already computed (endpoint 18): for every
  obligation in force, the act that is its own `(party, action)` shape, stamped at the position's
  clock — the party as the machine forced it (`reifyNF`) or its expression, the action pattern
  instantiated (`patternExpr`, `:508`: `PatApp`/`PatLit`/`PatExpr`, with an `EXACTLY e` read
  through the residual's heap by `reifyExpr`, `:524`, so `Sign (EXACTLY t)` under an `EVERY`
  names the member); for every distinct live deadline, a tick to just past it (endpoint 24) — a
  `WAIT UNTIL`, the machine's own no-party event, stamped by `tickPast` (`:277`: one unit past, or
  half-way to the next live deadline when nearer, because the machine expires on `stamp >
deadline` and a tick AT the deadline reveals nothing); and a listed refusal, when the shape
  cannot be instantiated — an action pattern that BINDS (`payment price`: "the action binds
  `price`, which the what-if cannot choose"), a `WITHIN` that was never evaluated and is not a
  literal (`deadlineOf`, `:264`). Refusals are listed, not dropped: an enabled set that omitted
  them would say "nothing else can happen". Each candidate's `LiveNorm` is rendered by
  `renderLive` (`Marking.hs:345`) from the very `RawObligation` its act is built from — the
  first cut paired `liveObligations` with the marking's `InEffect` list by `zip`, on the
  unguarded assumption that two walks agree in order; review 2026-09-15 replaced that with one
  walk.
- **The tick is held to the machine's word** (`tryCandidate`, `:335`; `confirmTick`, `:408`).
  A tick's stamp is derived here from the machine's timing rule (`deadlineOf`: anchor plus
  `WITHIN`; `tickPast`: expiry on `stamp > deadline`), which §2.4 forbids trusting unconfirmed.
  So a `TickPast` outcome must carry an `Expired` or `JoinExpired` step; if it does not, the
  arithmetic disagreed with the machine and the verdict is `Untried` naming `deadlineOf`, not an
  `Advancing` that reads as a genuine advance and lets `breaching` return `[]`. Measured: a tick
  forced to land ON the deadline (what an anchor one unit low would produce) is refused with
  "the tick to 10 past the deadline computed as 10 revealed no expiry"; the same candidate as
  computed, at 11, breaches (`LtsWhatIfSpec.hs`, case 8). Before the guard, the forced tick came
  back `Advancing ["in effect: Alice MUST deliver WITHIN 0"]`, which the same test pins as what
  the bare `whatIf` still says.
- **The replay** (`replay`, `:489`) rewrites the checked module so that every directive is dropped
  except the `#TRACE` in question, which gets the hypothetical appended, and runs
  `execEvalModuleWithDeonticLog` on it. The verdict (`classify`, `:438`) reads only the machine's
  own terminals: `ValFulfilled` → `Discharging`, `ValBreached` → `Breaching blame`, anything else
  → `Advancing marking` with the marking from the replay's own steps. An error or a refusal is
  `Untried` with the text. The steps an outcome carries are those past the longest prefix the
  replay's log shares with the position's (`afterCommonPrefix`, `:435`): a `Waiting` in the
  position becomes a match in the replay, so a fixed-length drop would be wrong, and was.
- **Cost per candidate** is one full replay: the module's top-level heap rebuilt, every prior
  event re-scrutinised, then the hypothetical. For a trace of _n_ events and _k_ live obligations
  with _d_ distinct deadlines, _k + d_ evaluations of _n + 1_ events each; nothing cached across
  candidates. **Measured**, warm, wall-clock around the call with verdict and steps forced:
  `ok/every/run-barrier.l4` trace 5 (one event, three-tenant barrier): position 45 µs; the two
  member acts 184 µs and 313 µs; the tick 83 µs. `ok/contracts.l4` trace 1 (three events):
  position 38 µs; the tick 93 µs. The first `position` call on a fresh module costs ~40 ms, which
  is the type-check being forced, not the replay. See R11.
- **The act is held to the machine's word too** (`confirmAct`, `:391`; **REVIEWED 2026-09-15**,
  moved here from the list renderer). The candidate set is read off the residual before the guard
  is asked (G9), so an act whose `PROVIDED` comes out false is a candidate and the replay reports
  it as `Advancing` to the position's own marking. P2a′ first corrected that in the renderer
  alone, which left the library's `advancing` returning a verdict §7.6 calls a lie to any other
  consumer. Review moved the reading into the verdict: an `ActBy` outcome none of whose steps is a
  `Matched`, `Expired`, `Breached` or join terminal is `PassedOver reason` (`Verdict`, `:284`;
  `PassOver`, `:299`: `GuardFalse`/`WrongAct`/`WrongParty`/`NoTaker`), so `advancing` and the
  list agree by construction. The reason is the candidate's OWN obligation's — the step at the
  candidate's site and with the candidate's bearer (`lnSite` against `nkSite`, `lnBearer`
  against `nkBearerName`; §4.3 LANDED 2026-09-16 — as first landed the site's reasons were
  ranked most specific first, a rank retired when the bearer became comparable) — because under
  an `RAND`/`ROR` the other side scrutinises the event first and logs its wrong-party first,
  which the first cut reported, and under an `EVERY` the members share the site. Measured, on
  `(PARTY S MUST payment EXACTLY 1 WITHIN 3) RAND (PARTY B MUST payment EXACTLY 5 PROVIDED FALSE WITHIN 3)`
  at its outset, B's act, before the fix: "it is not this party's to do" (the CLI, 2026-09-15);
  after: "its condition (PROVIDED) does not hold", and the same under `ROR` (`LtsListSpec.hs`,
  case 4). A `Joined` step deliberately does
  not count as the act being taken — under an `ROR` with nothing matched it says "still open",
  which is the pass-over case — and an outcome with no reason at all is `NoTaker`, never a
  silent advance.
- **The partition** is `discharging`/`breaching`/`advancing`/`passedOver`/`untried` over an
  `EnabledSet` (`enabledSet`, `:455`), i.e. endpoints 19 and 20 are a classification of 22's
  result and not a projection of their own.

**Measured** (`jl4-core/test/LtsWhatIfSpec.hs`, 13 examples): a `MUST` at the start — the act
advances into the `HENCE`, the tick past 10 breaches; one event in — the clock is the last stamp,
Bob's act discharges, the tick past 3 + 5 breaches. A `SHANT` with no `LEST` — the act
**breaches** and the tick **discharges**, which is the polarity the machine routes and this module
never states. A `MAY` with a `HENCE` — the act advances, the tick discharges (`LEST` defaulting to
`FULFILLED`). `contracts.l4`'s `aContract` one event in — `payment price` is listed `Untried`
naming the binder; the tick past 2 + 3 advances to the `LEST`'s `EXACTLY payment OF fine`. A
barrier of three with nobody acted — each member's act is **`Advancing`** with the `Awaiting` at
1 of 3, the tick breaches; with two acted — the last member's act is **`Discharging`** (the
`HENCE` is `FULFILLED`), the tick breaches. A fork — each member's act advances its **own**
continuation and leaves the others at `WITHIN 7`. Corpus goldens: `cabal test jl4-test`, see the
commit message — no `.l4` file and no printer changed, so none moves.

**Not built.** No CLI verb, no service endpoint, no `doc/` page: nothing a user can invoke
changed, and P2a′ (the list) is the deliverable that will need the page. A `PatCons` action is
not instantiated. A party the machine never forced and whose expression names a local it cannot
read fails at replay time and surfaces as `Untried` with the evaluator's message — loud, but late.
`what_if_sequence` (endpoint 23) is `replay` with a longer list and no separate entry.

---

## 3. The mapping

Same table style as PROCESS-TRACK §3, for direct comparison. **All line references re-verified
against `cfeaea5d`.**

### 3.1 L4 → the norm plane

Revision 1's table was not total. It omitted `ValROp` — the residual of _every_ compound contract
— and the `DDo` modal, and it got `MAY` expiry wrong. Following it literally drew violations the
evaluator had not concluded. The complete table:

| L4 / runtime                                            | Norm plane                                                                                                                                                                                                                                                                    |
| ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| a `Deonton` reachable in the current residual           | one **place**, marked                                                                                                                                                                                                                                                         |
| `ValObligation …` (`ValueLazy.hs:60`)                   | that place's **lifecycle state** — `InEffect`                                                                                                                                                                                                                                 |
| a `Deonton` whose guard has not yet been reached        | `Created` — **the F3 distinction, drawn**                                                                                                                                                                                                                                     |
| `ValFulfilled` (`Machine.hs:2963-2966`)                 | `Discharged`; Meyer-neutral, no violation                                                                                                                                                                                                                                     |
| `ValBreached (DeadlineMissed …)` (`ValueLazy.hs:82-86`) | `Violated`, with the blame fields it already carries — acting party, acting action, event stamp, obligated party, obligation, deadline                                                                                                                                        |
| `ValBreached (ExplicitBreach …)`                        | `Violated`, with `BREACH BY … BECAUSE …` — **which `StateGraph` currently erases** (`:288-290`)                                                                                                                                                                               |
| **`ValROp env ValRAnd l r`** (`ValueLazy.hs:61`)        | **both operands' markings, conjoined.** A breached operand cannot survive under `RAND` — `RBinOp2` reduces it away at `Machine.hs:1678-1691` — so no `Violated` is ever drawable from an AND operand                                                                          |
| **`ValROp env ValROr l r`**                             | **both operands' markings, disjoined**, and a `ValBreached` operand is **`Lapsed`, not `Violated`** — see the counterexample below                                                                                                                                            |
| **an operand still `Left rexpr`** in a `ValROp`         | `Created`. The `Either RExpr (Value a)` in the constructor **is** the not-yet-entered / entered distinction, already in the type                                                                                                                                              |
| `DMust`                                                 | violation link from _deadline expiry without the act_                                                                                                                                                                                                                         |
| `DMustNot`                                              | violation link from _the act occurring_ — the act stays fireable                                                                                                                                                                                                              |
| `DMay` + the act                                        | discharge link to `HENCE`. **No violation link.** Not a task with a skip gateway                                                                                                                                                                                              |
| **`DMay` + expiry**                                     | **a constitutive link to the authored `LEST`** (default `FULFILLED`). `Machine.hs:1532-1536`: _"expiry of a MAY routes to LEST … HENCE fires only when the permitted action is taken."_ Revision 1's "no violation link at all" was right about violation and wrong about ink |
| **`DDo`** (`Syntax.hs:360`)                             | **routes exactly as `DMust`** on expiry — `Machine.hs:1537`, `_ -> -- DMust, DDo: deadline passed = failure` — and as `DMust` on match (`:1605-1607`). It differs only in that the AST requires explicit `HENCE`/`LEST`, and `StateGraph` gives it no default `LEST` (`:486`) |
| `WITHIN d`, decremented per event (`Machine.hs:1469`)   | a **countdown on the place**, on the contract clock (`Rational`), not wall time                                                                                                                                                                                               |
| `HENCE` / `LEST`                                        | constitutive links to the _next_ norm's `Created`→`InEffect`, **from an action-plane transition or from an expiry**, which is not a transition — see the `MAY` row                                                                                                            |
| `LEST` chaining off a violation                         | contrary-to-duty, **as topology** — LPPN                                                                                                                                                                                                                                      |

**The `ROr` counterexample, spelled out, because it is the one that would have shipped a lie.**
Take `A ROR B`, with events that breach `B` and leave `A` outstanding. `RBinOp2` finds neither
"both breached" (`Machine.hs:1635-1666`) nor "either fulfilled" (`:1693-1704`), so it falls
through to `:1706-1707` and returns `ValROp env ValROr (Right (ValObligation …A…)) (Right
(ValBreached …B…))`. Revision 1's `ValBreached` row instructs the renderer to draw `Violated`,
with blame — but **the evaluator has not concluded a violation**: an `ROr` is breached only when
every alternative is definitively lost. Drawing red here is exactly the misrepresentation §6
exists to prevent. Hence `Lapsed`: the alternative is gone, the compound is not.

### 3.2 L4 → the action plane

| `StateGraph`                           | Action plane                                                                                                  |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `ContractState`                        | a place; the control token sits in exactly one                                                                |
| `Transition`                           | a transition, fireable iff its event shape is in the enabled set (§4.2)                                       |
| `FanKind = AllOf` (`:111-115`)         | a **fork**, and — see R2 — possibly a fork **plus a join**                                                    |
| `FanKind = OneOf`                      | a conflict (free choice): branches compete for the same token                                                 |
| `FanKind = Linear`                     | ordinary sequence                                                                                             |
| `InitialState`                         | the initial marking                                                                                           |
| `TerminalFulfilled` / `TerminalBreach` | absorbing places; **shared sinks** — `getTerminalState` (`:204-209`) is find-or-create by `(name, stateType)` |
| `labelModal` (`:128`)                  | **moves out of the label** into the norm plane. See R1 — this is the IR delta                                 |

### 3.3 What `StateGraph` does not give, and P2 needs

Reading `jl4-core/src/L4/StateGraph.hs` (708 lines at `cfeaea5d`) against the regulative AST,
seven gaps. All are P2 work, none were P1's problem — P1 shipped around every one of them, in
some cases by compensating downstream (§9).

| #   | Gap                                                                                                                                                                                                                                                                                                                                                                                                                                          | Evidence                                   |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| 1   | **No back-link to source.** Everything is `Text` via `prettyLayout`; no `Resolved`, no `Unique`, no `Anno`/`SrcRange` anywhere in the IR. Click-to-source is impossible — **and so is P2's correlation key**, §3.4 B1. Contrast `EvaluateLazy/GraphViz2.hs:43`, which keeps `bindingId :: Maybe Resolved` for exactly this reason.                                                                                                           | `:82-147`, `:393-397`                      |
| 2   | **Action arguments erased.** `PatApp n args` renders as `n <> " ..."`; `pay 100`, `payment EXACTLY n` and `order beer` collapse to the same string. The evaluator matches against the full `Pattern Resolved` (`Machine.hs:1561`), so the graph cannot express what the runtime actually matches on.                                                                                                                                         | `:518-524`                                 |
| 3   | **It is a tree, not an LTS.** Every `HENCE`/`LEST` creates a _fresh_ state; a target that is another named contract falls to `TargetOther`, makes a dead-end state named `"next"` or `"failure"`, and `extractExpr`'s catch-all stops there. A self-referential contract — the exact shape the evaluator's re-offer rule exists to survive — does not close its loop.                                                                        | `:419-431`, `:466-470`, `:496-503`, `:292` |
| 4   | **`BREACH BY … BECAUSE …` dropped.** The AST carries both fields; extraction ignores both.                                                                                                                                                                                                                                                                                                                                                   | `Syntax.hs:305`; `StateGraph.hs:288-290`   |
| 5   | **Enclosing bindings dropped.** `Where`/`LetIn` are traversed through and discarded; `GIVEN` parameters are dropped entirely. A contract parameterised on `patron`/`company` graphs with those as free unresolvable strings.                                                                                                                                                                                                                 | `:280-281`, `:235`                         |
| 6   | **Junction edges are blank and there is no join.** `fanLabel` is all-`Nothing`. `AllOf` branches fan out and **converge on one shared `Fulfilled` sink** (`getTerminalState`, find-or-create, `:204-209`, called from `:344` and `:412`) — which looks like a join and is not one: nothing says "all must complete", and nothing waits. The real join semantics — including breach blame and the CSL tie-break — live only in the evaluator. | `:375-382`; `Machine.hs:1635-1707`         |
| 7   | **No temporal semantics.** `labelDeadline` is a string. The IR has no notion that `WITHIN` is _relative_ and decremented per event, nor of `WITHIN d OF anchor`.                                                                                                                                                                                                                                                                             | `:130`; `Machine.hs:1469`                  |

_(Gap 6 corrected. Revision 1 said each `AllOf` branch "runs to its own `Fulfilled`", which its
own §3.2 row contradicted four paragraphs earlier. The sinks are shared. The substantive point —
no AND-join barrier — survives, and P1's `P-NOJOIN` fidelity note reaches the same conclusion by
a different route: `jl4/examples/bpmn/README.md`, "What can be joined, and why so little of it".)_

_(2026-09-16: gap 1 is closed for the edge — `labelSite` — and gap 3 is closed for named targets;
both by §3.4's B1/B2 blocks. A `RECORD` continuation is still a dead end, and the state still has
no range of its own. Gaps 2, 4, 5, 7 stand.)_

Also positional and worth fixing regardless: `sgInitialState = 0` is hardcoded on "first created
state is initial" (`:265`), true today only because both entry paths happen to create it first.

### 3.4 Extend the IR, or derive a new one? — and Q8, the scaffold

**Ruling: derive, and the scaffold cannot come from `StateGraph` as shipped.**

Revision 1 ruled "derive a new IR" and then handed layout back to `StateGraph` as the "layout
scaffold". Review found that self-contradictory, and it is: §4.4 makes the re-offer rule a
first-class animation requirement, the re-offer rule exists for **recursive continuations**
(`x MEANS PARTY p MUST a WITHIN d LEST x`, `Machine.hs:1491-1497`), and gap 3 says a recursive
contract's loop never closes in `StateGraph`. A loop-free scaffold has no board position for the
token to return to. The animator would be unable to animate the exact contracts the rule it must
model exists to survive.

Worse, and the review's blocking finding: **there is no key.** `Machine.hs` never mentions
`StateGraph` (grep-verified); `StateGraph`'s IR is `Text` and `Int` throughout (`:82-147`); so
nothing in a step log identifies which board position a runtime obligation is standing on.

**The fix is precise, and it is available.** `RAction` carries `anno :: Anno` (`Syntax.hs:366`)
and so does `Deonton` (`:345`); `Anno_` carries `range :: Maybe SrcRange` (`Annotation.hs:81`,
`rangeOf` at `:228`). The runtime side keeps the whole `RAction Resolved` inside `ValObligation`
(`ValueLazy.hs:60`), so **the source range is already in hand at runtime**. It is the _static_
side that throws it away. Therefore:

> **The correlation key is `(SrcRange of the RAction, activation ordinal)`.** The range identifies
> the clause; the ordinal distinguishes the _n_-th time a loop re-enters it. Neither half exists
> today: the range is dropped by extraction (gap 1), and the ordinal has nowhere to live because
> the graph has no loop to count round (gap 3).

Which gives P2's three preconditions, none of which is a renderer:

| ID     | Precondition                                                                                                                                                 | Cost                                                                   |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------- |
| **B1** | **Carry the key.** `TransitionLabel` (or `ContractState`) gains the `RAction`'s `SrcRange`. Closes gap 1 for the click-to-source case too.                   | Small. Changes `StateGraph`'s public type and the BPMN goldens.        |
| **B2** | **Close the loop.** `TargetOther` pointing at a named contract already extracted must reuse that state, not mint `"next"`. Needs a memo keyed by B1's range. | Medium, and it **makes layout harder** — see §4.7.                     |
| **B3** | **Layout.** §4.7. Undefined in revision 1; still not solved here, but now stated, costed and assigned.                                                       | Medium-large, and the two-plane form is strictly harder than P1's DAG. |

**What changed to make B1 tractable.** Revision 1 declined the `StateGraph` type change because
"P1 is mid-flight". P1 is no longer mid-flight — it shipped at `cfeaea5d` with goldens and a
Camunda import check. The cost of B1 is now "regenerate three `.bpmn` goldens and re-run the
validator", which is a chore, not a hazard. **The reason revision 1 gave for deferring R1 has
expired.**

The exception that stands: P0's `FanKind`, which P2 consumes **unchanged and directly** —
junction kind, branch sets, associative flattening and the tests that pin them
(`jl4-core/test/StateGraphSpec.hs`) are exactly what §7 said P2 depends on, and that dependency is
discharged.

Note that moving modality off the transition (R1) is corroborated by two independent published
formalisms — contract automata annotate states, LPPN marks places — and possibly a third
(Lomuscio & Sergot, unverified). Our IR is the odd one out.

> **B1 LANDED 2026-09-16** (`lts/b1-b2-loops`). `TransitionLabel.labelSite :: Maybe SrcRange`
> (`jl4-core/src/L4/StateGraph.hs`, the field's own comment), set in `extractDeonton` to
> `rangeOf action` — the same expression `armNormKey` (`Machine.hs`) evaluates to stamp
> `NormKey.nkSite`, so the two halves of the key agree by construction and not by convention.
> Both arms of an obligation carry it (the `HENCE` edge and the `LEST` edge are two outcomes of
> one obligation; `transType` says which); a junction's branch edge and a hand-built fixture
> leave it `Nothing`. `ContractState` was **not** changed: B2's memo did not need a site (see
> below), and click-to-source on a _state_ is answered by the edge that enters it.
>
> **Measured.** `StateGraphSpec.hs`, "B1: the correlation key": a two-obligation fixture with a
> `#TRACE` is run through `execEvalModuleWithDeonticLog` and `extractStateGraph`, and the
> `nkSite` of each logged step equals the `labelSite` of the corresponding `HENCE` edge, in
> order, both `Just` — the test would pass vacuously if either side were `Nothing`, so it also
> asserts they are not. The cost prediction in the table above was **wrong in fact**: "regenerate
> three `.bpmn` goldens" turned out to be zero goldens. `L4.Bpmn.Lower` reads label fields by
> name and never serialises the label, the DOT does not draw the site, and `l4 lts` does not read
> the graph; all 14 BPMN goldens, all 6 `l4 lts` goldens and all 71 corpus DOTs are byte-identical
> under B1 alone (`cabal test`'s "bpmn export" and "lts list" groups, 340 and 12 examples, and
> the DOT diff below). What B1 _did_ cost was the positional `TransitionLabel` constructions in
> two test files (eight-field now), and one module split forced by the annotation, §1.1c.
>
> **B2 LANDED 2026-09-16** (same branch). `extractStateGraphs` now builds a `Rules` map — every
> regulative `DECIDE` of the module, by `Unique`, with its drawn name and peeled body — and
> hands it to every extraction; `classifyTarget` returns `TargetNamed` for an `App` of one, and
> the new `wireTarget` (the one function all three arm sites — `HENCE`, `LEST`, junction branch —
> now go through) consults `ExtractState.esMemo :: Map Unique StateId`: an entry there is reused,
> else a state named after the rule is created, **memoised before its body is extracted**, and
> the body extracted from it. The memo is seeded with the rule being extracted at
> `initialStateId`, which retires `TargetSelf` as a special case — a self-`HENCE` is now the
> memo's first hit — and turns two rules that hand over to each other into a real cycle.
>
> **Keyed by `Unique`, not by B1's range.** The table above offered both. The memo answers "has
> this _rule_ been given a state?", and a rule's identity is its `DECIDE`; two arms written at two
> different ranges that both name it must land on one state, or the loop does not close. The
> range identifies the _arm_ — that is what `labelSite` carries — not what the arm points at.
> Arguments are ignored exactly as a renewing rule's were (the termination argument is the loss,
> as before; `P-CYCLE`). Not in the map, and so still `TargetOther` → `next`/`failure`: a rule
> from an `IMPORT` (measured with a two-file scratch pair: `next`), a `RECORD` continuation, a
> `Refuse`, an `AppNamed`, and any `DECIDE` whose body is not regulative.
>
> **Measured, (a) DOT over the corpus.** `l4 state-graph` over every `.l4` under `jl4/examples`
> and `doc` that accepts it: **71 files produce graphs, 9 changed** —
> `doc/concepts/legal-modeling/regulative-layer-whole-example.l4`,
> `doc/courses/{advanced/module-a1-regulatory,advanced/module-a2-cross-cutting,advanced/module-a3-contracts,foundation/module-7}-examples.l4`,
> `doc/reference/regulative/every-example.l4`, `doc/tutorials/obligations/what-follows.l4`,
> `jl4/examples/ok/contracts.l4`, `jl4/examples/ok/every/barrier.l4`. Files carrying a `next` or
> `failure` state went from 16 to 10; the 10 that remain are `IF` junctions (drawn as `next` with
> the arms below it — not dead ends) and the `ok/ledger/record-*` `RECORD` continuations (dead
> ends still). In `ok/contracts.l4`, `a MEANS z RAND z` now draws one `z` junction with two
> parallel edges into it where it drew two dead-end `z` states. The `LEST`-into-own-name arm lost
> its literal `"timeout"`/no-modal caption and goes through `lestArmWording` like its siblings:
> the two corpus rules with that shape (`ok/deontic-breach-semantics.l4`,
> `doc/courses/advanced/module-a3-contracts-examples.l4`) are `MUST … WITHIN`, so their caption
> is unchanged; a `SHANT` self-`LEST` now says `violation` (`StateGraphSpec`, "captions a LEST
> back into the rule's own name").
>
> **(b) BPMN.** All 14 goldens byte-identical — none of the golden sources hands over by name
> (Reg CF's self-loop already closed under `TargetSelf`, and `regcf-reporting.fidelity.txt` has
> carried `P-CYCLE` since `a9caf2f6`, 2026-07-27). `etc/bpmn-kie-baseline.txt` therefore did not move:
> `etc/check-bpmn-kie.sh jl4/examples/bpmn/expected/*.bpmn | node etc/check-bpmn-kie-baseline.mjs`
> → "14 file(s) checked, RESULT 12 with findings, all as baselined" (JDK 17.0.20 via
> `/opt/homebrew/opt/openjdk@17`). The new shapes were exported by hand instead: a scratch
> `ping`/`pong` pair, `what-follows.l4`'s `rent, receipt for the amount paid`, and `contracts.l4`'s
> `a` and `goesOn`. `etc/validate-bpmn.mjs`: 4/4 OK, all drawn. `etc/check-bpmn-soundness.mjs`:
> `ping` SOUND (the back-flow `Task_1 → Task_0` is a real loop; 8 markings, peak 1 token),
> `rent, receipt …` SOUND, `goesOn` SOUND, **`a` UNSOUND on S4 only** — two `RAND` branches into
> one `z` place is 2-bounded, which is what the L4 says and what a safe workflow net forbids; no
> fidelity note names it yet (owed to P1, noted on `doc/exports/dmn-bpmn.md`). jBPM: `rent …` and
> `goesOn` COMPLETED; `ping` REJECTED with class (a′) "cannot have more than one incoming
> connection" and `a` with class (a) "Unknown gateway direction: Mixed" — both dialect limits
> already on record in the baseline's hand-maintained block, relocated to the new shapes, not new.
> `P-CYCLE` fired on `ping` with the text §4.7 quotes: "The state graph has a cycle (initial,
> pong)".
>
> **(c) Dominators.** `DominatorsSpec.hs`, "a loop through another rule (B2)": the greatest
> fixpoint terminates on `ping`/`pong`, nothing dominates its `Breach` (two timeouts, two
> routes), and Alice's act dominates the `pong` state. `jl4-core-test`: 662 examples, 0 failures.
> **(d) Figures.** `l4 state-graph doc/reference/regulative/every-run-example.l4` is byte-identical
> before and after, and `etc/go/lib/split-digraphs.mjs` of it matches
> `doc/reference/regulative/figures/every-{barrier,fork}.dot` exactly; nothing regenerated.
> **(e) `l4 lts`.** 6 goldens byte-identical (the list reads the runtime, not the graph).
>
> **B2 corrected 2026-09-16 (review): the memo is scoped to the path, not the graph.** The
> "one `z` junction with two parallel edges into it" of (a) was the wrong drawing, and (c) had
> not looked at it: `l4 state-graph --dominators jl4/examples/ok/contracts.l4` answered `a`
> (`a MEANS z RAND z`) with **"No path reaches FULFILLED from the start state."**, exit 0 — a
> confident false answer where the base binary gave the honest non-answer "(this graph has no
> FULFILLED or BREACH state to reach)", for a rule whose own `#TRACE z` fixtures reach
> `FULFILLED`. Cause: `wireTarget` landed both `RAND` branches on the one memoised `z`;
> `Dominators.joinEdges`' fulfilment view walked branch 1, re-pointed `z`'s arrivals at
> `Fulfilled` at branch 2's entry — the same `z`, a self-loop — dropped branch 2's fan edge, and
> the `seen` guard never walked it, so `Fulfilled` had no incoming edge in the view. The module
> header's premise "an intermediate state lies inside one branch" was false for shared states.
> The BPMN measurement in (b) had already seen the same defect from the other side — `a` UNSOUND
> on S4, "two `RAND` branches into one `z` place is 2-bounded" — and read it as what the L4 says.
> It is not: `RBinOp1`/`RBinOp2` run _both_ operands, so `z RAND z` is two instances of `z`.
>
> **Ruling.** `extractFan` now runs each `RAND`/`ROR` branch under `perBranch`, which restores
> `esMemo` to what the branch found on entry: a rule that two branches both name is drawn once
> per branch. The memo a branch _inherits_ is intact, so a loop still closes — an arm back into a
> rule above the junction is a back-edge, and a back-edge never arrives at a sink, so the views
> never redirect it. An `IF`'s arms (`extractIfFan`) and an obligation's `HENCE`/`LEST` keep
> sharing: exactly one of them occurs, so they are one continuation, and the views never sequence
> them. The alternative — unrolling shared regions inside the views — would have had to duplicate
> states and then answer "every path passes through _some copy_ of e", which the per-edge
> definition (module header) does not express; instantiating at extraction makes the copies real
> edges, which the definition already handles (`z RAND z` to `BREACH`: two routes with disjoint
> edge sets, nothing dominates — where the shared drawing said both of one `z`'s timeouts did).
> The "must land on one state, or the loop does not close" argument above was right about loops
> and over-general about siblings.
>
> **Measured.** `DominatorsSpec` "a rule RANDed with itself (B2)": `a` draws two `z` states,
> `FULFILLED` and `BREACH` both "nothing in particular"; `z` itself still `[]` / both timeouts.
> `StateGraphSpec` "draws a rule once per RAND branch that names it, and shares it with an
> exclusive arm": ``HENCE (`the receipt` RAND `the receipt`) LEST `the receipt` `` draws three
> receipt states and Bob's obligation three times. `l4-cli-test` "--dominators answers for a rule
> RANDed with itself, and never says No path reaches" pins the `z` and `a` blocks of
> `contracts.l4` verbatim. Corpus, same 71 files as (a): against the pre-fix binary exactly one
> DOT and one `--dominators` output moved, `ok/contracts.l4`; against the base binary the
> `--dominators` output differs on **8 files** — the 9 of (a) less
> `doc/courses/advanced/module-a2-cross-cutting-examples.l4`, whose graphs changed shape but not
> answer — every one of them the hand-over now being followed: a "this graph has no FULFILLED or
> BREACH state to reach" or an answer over a dead-end `next` replaced by an answer over the named
> rule's region, and none saying "No path reaches". That answer is now reachable only
> truthfully; see the §1.1c note. `jl4-core-test`: 665 examples, 0 failures (662 + 3). The "13
> new" in the B1/B2 commit message was 14: `git diff lts/p2-followups...HEAD` on
> `StateGraphSpec.hs` and `DominatorsSpec.hs` adds fourteen `it` blocks (13 + 1) and removes
> none, and the `lts/p2-followups` test binary (`0139c6c5`) reports 648, so 648 + 14 = 662.
> `cabal test l4-cli-test --test-options='-m "l4 state-graph"'`: 8 examples (7 + 1).
>
> **B3 stays not built.** What B2 handed it is the input §4.7 asked for — a graph with real
> cycles — and nothing else; no feedback-edge set is computed anywhere yet.

---

## 4. Token game and trace animation

This is the part most likely to be hand-waved, so it names its data source line by line — and
revision 2 defines the two things revision 1 animated without specifying.

### 4.1 What is animated

Three things move, and nothing else:

1. **The control token** in the action plane — one place at a time.
2. **The norm-plane marking** — the set of live obligations, each with its lifecycle state and
   its countdown. This is the picture's payload; the control token is context for it. **Derived
   in §4.2a.**
3. **The enabled set** — every `(party, action)` shape that would fire from here, highlighted,
   partitioned into _discharging_ and _breaching_. **Obtained by replay, per §2.4.**

The scrubber axis is the **contract clock** (`Rational`, as `Machine.hs` computes it), not wall
time. Deadlines animate as counters that decrement per event; this is a step-counter
approximation of a dense-time deadline and `VERIFICATION-BACKEND-LOWERING-SPEC:65` already says
so in as many words. §6 G6.

### 4.2 The data, and whether it exists today

| Datum                                          | Source                                                                                                                              | Status                                                                               |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| the event list to replay                       | `TraceEvent { party, action, at }` + `startTime`/`events` on `FnArguments`, `jl4-service/src/Backend/Api.hs:125,146`                | **Ships.** POST events, get FULFILLED / BREACH / residual back over HTTP             |
| the residual after _n_ events                  | —                                                                                                                                   | **Missing.** Only the final value survives per directive (`EvaluateLazy.hs:280-292`) |
| which event caused which step, and its outcome | —                                                                                                                                   | **Missing.** §4.3                                                                    |
| **the norm-plane marking**                     | derived from the residual, **§4.2a**                                                                                                | **Specified here.** Was unowned in revision 1                                        |
| the enabled set                                | `DEONTIC-TRACE-API-SPEC` Phase 3 `GET .../expected-events` — _"uses the state graph extraction combined with the current position"_ | **Unbuilt.** No `expected-events` anywhere in tree. This is P2's entry point         |
| discharging vs breaching partition             | `STATEFUL-CONTRACT-DEPLOYMENT` §6.5 endpoints **22/23/24** (`what_if…`), **not** §6.4's 18/19/20 pure walks — §2.4                  | **Unbuilt**                                                                          |
| next deadline                                  | `STATEFUL` §6.4, endpoint **17**                                                                                                    | **Unbuilt**                                                                          |
| resumable residual (live mode)                 | `STATEFUL` §3.1                                                                                                                     | **Unbuilt, and flagged a blocker in its own spec**                                   |

Two important negatives, so nobody plans against them:

- **`EvalTrace` is not a deontic trace.** `EvalTraceAction = Enter | Exit | SetRef | Alloc |
AllocPre | Push | Pop` (`Trace.hs:87-95`) is an expression-level reduction tree. It is emitted
  from the generic dispatch loop (`EvaluateLazy.hs:176,186,190`) and from five sites in
  `Machine.hs` (`:322,463,469,702,722` — exception exit, explicit push/pop, allocation).
  **No `ContractFrame` transition emits anything**, which is the load-bearing point. The raw
  action stream does incidentally carry intermediate `ValObligation`/`ValBreached` values as
  `Exit` payloads, but with no event identity, no contract clock and no match/mismatch/expiry
  outcome — so you cannot say which event caused which step. And the post-processed trace every
  consumer actually sees is worse: `simplifyEvalTrace` deletes "trivial" nodes and
  `maxTraceNodes = 10000` truncates (`Trace.hs:411-412,473-493`).
- **The ledger is the wrong axis.** `LedgerEvent` is deliberately a sum, and its comment
  reserves the space — _"so that later milestones can add `Obliged`, `Breach`, etc. without
  disturbing callers"_ (`Ledger.hs:94-96`). But `txTime` is a per-run constant ordered by log
  position (`:172-173`), i.e. wall-clock. Good for "what did this party record"; wrong axis for
  the token game.

### 4.2a Deriving the marking — the function revision 1 never wrote

The marking is a structural fold over the residual value. It is total over the value shapes the
regulative evaluator can return, which is the property revision 1's table lacked.

```
markingOf :: Value a -> [NormPlacement]

markingOf ValFulfilled                       = []                       -- nothing live
markingOf (ValBreached r)                    = [Violated (blameOf r)]
markingOf (ValObligation _ party act due _ _)= [InEffect (normOf act party due)]
markingOf (ValROp _ op l r)                  = operand op l <> operand r
  where
    operand _  (Left  rexpr)                 = [Created (siteOf rexpr)]  -- branch not entered
    operand ValROr (Right (ValBreached r))   = [Lapsed (blameOf r)]      -- NOT Violated — §3.1
    operand _  (Right v)                     = markingOf v
markingOf _                                  = []                       -- not a regulative value
```

Four facts make this sound, each checked against `Machine.hs`:

1. A `ValROp ValRAnd` **cannot** hold a breached operand: `RBinOp2` reduces `RAND`-with-a-breach
   to the breach itself (`:1678-1691`). So the `Lapsed` case is `ROr`-only, by construction.
2. A `ValROp ValROr` **cannot** hold a fulfilled operand: `:1693-1704` reduces it to `Fulfilled`.
   So a surviving `ROr` always has at least one live or lapsed side.
3. A `ValROp` with **both** operands breached cannot survive either (`:1635-1666`), which is why
   `Lapsed` never has to stand in for a genuine compound violation.
4. `Left rexpr` operands are branches the machine has not forced yet. That is precisely Symboleo's
   `Created`, and F3's distinction, **already present in the runtime type** rather than something
   we must invent.

`normOf` is where B1 bites: it needs `(rangeOf act, activation ordinal)` to place the norm on the
board (§3.4). Without B1, `markingOf` still produces a perfectly good **list** — which is §1.1a's
rival, and is why P2a′ can be built before any precondition is closed.

**LANDED 2026-09-15 (P2c), on `lts/p2b-step-log` (merged into `lts/p2-stack` 2026-09-15, not yet in `unstable`; the §7.2 P2c
row and the P2h row's second-half status were updated at integration — the `Threshold`-shaped `markingOf` half has
landed, the drawing rule has not).** `jl4-core/src/L4/Lts/Marking.hs`, `markingOf ::
LayoutPrinter a => MarkingContext -> Value a -> [NormPlacement]` (`:294`). The sketch above is superseded by the module; this block records where
the built type departs from it and why, and what was measured.

- **The final `NormPlacement`** (`Marking.hs:100`): `Created {crSite, crSource}` (Symboleo),
  `InEffect LiveNorm` (Symboleo), `Violated Blame` (Anderson/Meyer), `Lapsed Blame` (this spec's
  coinage, R12 still open), and the join state `Awaiting {awJoinSite, awProgress :: Maybe
Progress}` (`:121`). `LiveNorm` carries the site (`rangeOf` the `RAction`), the bearer as
  `KnownParty`/`UnforcedParty` (a `PARTY p` that never met an event still holds the expression),
  the modal, the action pattern, a `Countdown` (`NoDeadline | UnforcedDeadline Text | Remaining
Rational` — the residual `WITHIN` is a number only once the obligation has scrutinised an event;
  before that it is the unevaluated expression, measured on the fixtures marked B″ and K), the
  `HENCE`/`LEST` text, and `lnMember :: Maybe Family` from the context — the family (join,
  total, join site; `Family`, `:158`), not a `MemberOf`: through a context keyed by action site
  a `moIndex` would be whichever member the log wrote last, so it is not carried (review
  2026-09-15; the first cut exposed `MemberOf` with an index that was nobody's). Fulfilled marks `[]`, as
  sketched — there is no `Discharged` place; §3.1's row was the table, §4.2a's fold is the rule.
- **Two `Created` shapes, not one.** The sketch had only the `Left rexpr` operand of a `ValROp`. A
  `ValQuantified` — an `EVERY` that has not met its event stream, so its cast is not drawn — is
  the other, and is `Created` with the whole rule's range and source (`markingOf`'s
  `ValQuantified` arm). It was not in the sketch because the sketch predates the quantifier.
- **The join, against `Threshold`.** `Progress = {prDone, prTotal, prThreshold :: Threshold
Resolved}`. Phase 3's count and measure forms add arms at `thresholdMet` (`:220`), at
  `placementText`'s `thresholdText` (`:449`), and in the machine at `assembleQuantified`'s
  `threshold@AllHave{}` (`Machine.hs:2435`); none of the three has a wildcard, so a new
  `Threshold` constructor is a compile error at each. (An earlier version of this sentence said
  `thresholdMet` was "the one place"; it was not, even within `Marking.hs`.) The same discipline
  holds for `JoinKind`: `markingOf`'s `progress` names `Fork` and `Distributive` rather than
  wildcarding them, so a future threshold-bearing join kind cannot fall through to `awProgress =
Nothing` and print as "run with the step log on". To get the
  threshold to the marking, `DeonticStep.JoinKind`'s `Barrier` now carries it (`Barrier
!(Threshold Resolved)`, `DeonticStep.hs:182`; `isBarrier` for the tests and `tellRoutedStep`),
  written at `registerCast` (`Machine.hs:514`) from the `JoinOnce` in hand. One `Awaiting` is
  emitted per barrier, after the members, however many are still pending.
- **Where the barrier's state comes from — the honest part.** The residual of a pending barrier is
  the `RAND` fold of its pending members whose `HENCE`/`LEST` slots hold the machine's sentinels
  (`barrierFinish`, `Machine.hs:2583`, "Phase-2 limit: the residual does NOT carry the JOIN
  LINE"). Neither the count nor the total nor the threshold is in the value. So `markingOf` takes
  a `MarkingContext` (`:228`, `contextOf :: [DeonticStep] -> MarkingContext`, `:252`), read back
  out of P2b's steps: casts by ACTION site from any step's `nkMember`, arms-done per JOIN site by
  a fold IN STEP ORDER — a `MemberSatisfied n` sets the site's count to `n`, and the join's own
  terminal (`JoinReleased`/`JoinExpired`/`JoinFailed`/`JoinStalled`, keyed by the join site in
  its `nkSite`) resets it to zero, mirroring `registerCast`'s `Map.insert jsite 0`
  (`Machine.hs:523`) at every entry. Nothing new is captured. **The first cut took the maximum
  `MemberSatisfied` instead**, and review 2026-09-15 found what that does to a `HENCE` that
  re-enters its own barrier: the machine zeroes its counter, the log reads `1 3, 2 3, 3 3,
  JoinReleased, 1 3`, and the maximum reported `3 of 3` with `thresholdMet` true while the
  `Awaiting` was pending. Measured on fixture R (`LtsMarkingSpec.hs`, a `HENCE` of `the tenancy` itself,
  four events): the old fold gives `PAwaiting (Just (3, 3, True))`, the in-order fold `(1, 3,
False)`; R′ pins the step sequence the reading depends on. Without a context (`noContext`) the
  `Awaiting` is still emitted — the member is recognised by the checkpoint sentinel in its
  `HENCE`: its NAME, `joinCheckpointName` (`Machine.hs:2541`, now a named constant and exported),
  AND the absence of a source range, since the machine mints it under `emptyAnno`
  (`Machine.hs:2522`, `:2550`) and a drafter's own `the join` written as a `HENCE` carries
  one (fixture S: no `Awaiting` for the homonym, with or without a context; the first cut matched
  by name alone) — but its `awProgress` is `Nothing`. The rule for a reader: no `Awaiting` means
  no barrier; an `Awaiting` with no progress means the residual was read without its run's log.
  Fixture B′ pins both.
- **The register cannot be matched by bearer from a normal form**, which is why the context is
  keyed by action site alone: P2b keys the cast register by `partyKeyWHNF`, which for a
  constructor party is its layout with unforced fields as heap addresses (`Tenant OF
&161@main.l4`), while the NF residual prints `Tenant OF "Bob"`. The two never agree. Keying by
  site inherits P2b's known limit — a `HENCE` re-entering its own `EVERY` overwrites the cast in
  `mcCasts` — which today loses nothing observable, because the second cast's family (join,
  total, join site) is the first's. What the context does NOT inherit is the count: that is
  folded per activation, above. (This sentence first read "adds nothing to it", written before
  the maximum-fold bug was found; it did add something, and the fold is the repair.)
- **`liveObligations`** (`:377`) is the same walk unrendered, for "L4.Lts.WhatIf", which needs
  the value and not its text, and `renderLive` (`:345`) is the `InEffect` reading of one raw
  obligation, used by `markingOf` for every `ValObligation` and by `candidatesOf` for every
  candidate; the K fixture asserts `map (renderLive ctx) (liveObligations v)` equals the
  `InEffect` list exactly — sites, bearers, text — not merely in length.

**Measured.** `JL4_LIBRARY_PATH=$PWD/jl4-core/libraries cabal test jl4-core-test`: 611 examples,
0 failures (was 578; 20 in `jl4-core/test/LtsMarkingSpec.hs`, 13 in `LtsWhatIfSpec.hs`; 607
before the 2026-09-15 review fixes added R, R′, S and WhatIf case 8). The
marking spec runs every §4.2a case as a `#TRACE` and reads the marking off the returned value:
FULFILLED → `[]`; a breach → `Violated (Alice, deadline 10)`; an obligation one event in →
`InEffect … Remaining 7`; an `RAND` of two → both; the `ROr` counterexample → `[InEffect Alice,
Lapsed Bob]` and nothing `Violated`; `#EVAL either` → two `Created` from the runtime's own `Left`s;
``#EVAL `the tenancy` `` → one `Created`, whole; `#EVAL 5` → `[]`. The four facts, each as a run:
F1 `RAND` with one side breaching reduces to `[Violated]` with no `Lapsed`; F2 `ROR` with one side
fulfilled reduces to `[]`; F3 both sides breached reduces to one `Violated`; F4 is case 6. The
barrier fixture (three tenants, one signed) marks `[InEffect Bob, InEffect Carol, Awaiting 1 of 3,
not met]` with `AllHave` as the threshold; nobody signed marks three members with
`UnforcedDeadline "14"` and `Awaiting 0 of 3`. The fork fixture marks the landlord's running
continuation (`UnforcedDeadline "5"`, no member), the two waiting members (`Remaining 6`, `Fork`
of 3, carrying the drafter's `HENCE` and not a sentinel) and **no** `Awaiting`. `cabal test
jl4-test`: see the §2.4 block — the corpus goldens do not move, since no `.l4` and no printer
changed.

**Not built.** The drawing rule for "marked but not enabled" — P2h's second half, per §7.2 and
§4.9, and blocked on nothing. (P2c's first write-up assigned it to the gated P2d in this sentence
and in §4.9; that was a re-staging done in a LANDED block, not a decision, and is retracted. If
it should move to P2d, that is an open question for the integrator: proposed 2026-09-15, not
decided.) `Lapsed`'s name is unverified against Symboleo (R12, unchanged).
`awProgress` from the residual alone, for the reason above. B1's static half of the key: nothing
in `L4.StateGraph` was touched.

### 4.3 The one piece of new back end: a deontic step log

`traceEval` is six lines — read an optional `IORef` from the reader env, `modifyIORef'` a
`DList` (`Machine.hs:309-314`) — and `tellEventRouted` (`:552-555`) is already a second instance
of the idiom, described in-comment as _"Modeled on `traceEval`, but non-optional: every write is
recorded, newest-last."_ (Revision 1 attributed that comment to `noteLedgerWrite`, which is a
different, one-line function at `:618-619`.)

`tellDeonticStep :: DeonticStep -> Eval ()` is the same shape. **Revision 1 deferred the type
itself to P2b and defined no field**, which the review correctly called unbuildable. Here it is:

```haskell
-- | One scrutiny of one event by one obligation, on the contract clock.
data DeonticStep = MkDeonticStep
  { dsClock   :: !Rational          -- ^ contract clock at this step (Machine.hs:1457-1470)
  , dsEvent   :: !(Maybe EventKey)  -- ^ Nothing when expiry fires with no event to blame
  , dsScrutiny:: !Scrutiny          -- ^ §4.4: consumed, or merely witnessed, or re-offered
  , dsNorm    :: !NormKey           -- ^ which norm instance did the scrutinising
  , dsOutcome :: !StepOutcome
  }

-- | The correlation key of §3.4. B1 is what makes the first field obtainable
-- on the STATIC side; the runtime already has it via ValObligation's RAction.
data NormKey = MkNormKey
  { nkSite       :: !(Maybe SrcRange)  -- ^ rangeOf the RAction (Syntax.hs:366)
  , nkActivation :: !Int               -- ^ n-th entry into that site in this trace
  , nkBearer     :: !Text              -- ^ partyKey, as the ledger already computes it
  , nkModal      :: !DeonticModal      -- ^ all four, including DDo
  }

data Scrutiny = Consumed | WitnessedOnly | Reoffered   -- ^ §4.4, R6

data StepOutcome
  = Waiting                      -- ^ Contract1, ValNil: no events left; residual stands
  | PartyMismatch                -- ^ Contract8 ValBool False (:1556-1566)
  | ActionMismatch               -- ^ Contract11 unwind (:1567-1568)
  | GuardFailed                  -- ^ Contract10 ValBool False with a PROVIDED present (:1608-1610)
  | Matched   !Branch            -- ^ Contract10 ValBool True; Branch says HENCE or LEST, per modal
  | Expired   !Branch            -- ^ Contract5 stamp > deadline (:1474); Branch per modal (:1527-1543)
  | Breached  !BreachSummary     -- ^ the ValBreached that was constructed here
  | Joined    !RBinOp !JoinNote  -- ^ RBinOp2: which side won, and whether by CSL tie-break

data Branch = ToHence | ToLest | ToBreach
```

Every field is already in scope at the decision points, because `ContractFrame` declares the
entire per-event pipeline as an explicit documented sum of **fourteen** constructors —
`Contract1`–`Contract11`, `RBinOp1`, `RBinOp2`, `ResolveParty` (`ContractFrame.hs:6-59`).
(Revision 1 said eleven; it counted only the `ContractN` half.) The six that carry a step:

| Frame               | `Machine.hs` | What the step records                                                                          |
| ------------------- | ------------ | ---------------------------------------------------------------------------------------------- |
| `Contract1`         | 1426-1452    | next event popped; `ev'reoffered` looked up; `ValNil` → the residual, i.e. `Waiting`           |
| `Contract5`         | 1457-1549    | `deadline = time' + due'`, `newDue`, expiry (`stamp > deadline`), and the modal-routed outcome |
| `Contract8`         | 1556-1566    | party match / mismatch → backtrack                                                             |
| `Contract10`        | 1577-1610    | action-pattern match, `PROVIDED` result, modal branch                                          |
| `RBinOp1`/`RBinOp2` | 1618-1707    | the `RAND`/`ROR` join, breach blame assignment, CSL tie-break                                  |

Roughly six call sites, no post-processing, and the log carries the contract clock rather than
wall time. **This is the whole of P2's back end**, it is independent of every precondition in
§3.4, and it is the one deliverable this document recommends unconditionally.

**BUILT 2026-09-15 (P2b), on `lts/p2b-step-log` (merged into `lts/p2-stack` 2026-09-15, not yet in `unstable`).** The types live in
`jl4-core/src/L4/EvaluateLazy/DeonticStep.hs`; the sketch above is superseded by that module and
this block records where the built types depart from it, and why.

- `dsClock :: Maybe Rational`, not `Rational`. Four step shapes have no clock in hand: a `Waiting`
  logged before the obligation has forced its time (a `#TRACE` with no events — forcing the thunk
  for the log's sake would change what the machine evaluates); a `Joined`, whose `RBinOp2`
  frame holds two values and no time; a `Breached` for an explicit `BREACH` terminal, which the
  expression arm builds with no time in hand; and a barrier with no `LEST` whose member ends in a
  value carrying no time — `JoinStalled` (the member's `ValFulfilled`), or `JoinFailed` when the
  member's own breach was an explicit `BREACH`. (Written as "two" until 2026-09-16, when review
  found the barrier-without-`LEST` steps logged `Nothing` unconditionally at `Machine.hs`'s
  `Barrier1` frame although a `DeadlineMissed` member carries its stamp; that `JoinFailed` is now
  clocked with the stamp, matching what `barrierFail` peeks for the `LEST` case.) The log **peeks and never forces** (`peekWHNF`,
  `Machine.hs:394`); that rule decides every `Maybe` below.
- `dsNorm :: Maybe NormKey`, not `NormKey`. A `Joined` step belongs to an `AND`/`OR` compound,
  which is not a norm instance (§2.3 gives places to obligations, not connectives) and, because
  `ValROp` carries no annotation, has no site. Every other step has a key.
- `dsEvent :: Maybe EventKey` with `EventKey = {ekStamp, ekParty :: Maybe Text, ekAction :: Maybe
Text}` — the sketch left `EventKey` undefined. Party and action are peeked. (Since the LANDED
  2026-09-16 block below: `+ ekPartyName`, and `NormKey` `+ nkBearerName`, the party rendered as
  the list renders it, recorded where the machine forced its fields; `nkBearer` stays the ledger
  key.)
- `Scrutiny` gains `NoEvent` for the steps no event caused (`Waiting`, `Joined`, the join's own).
  `Reoffered` takes precedence over the other two: it marks the continuation's second look at a
  re-offered event, whatever that look decided; a consumer counting events counts it as zero.
- `NormKey` gains `nkMember :: Maybe MemberOf` — §4.9's per-member identity, see below. `nkBearer`
  is a `Maybe`: a `PARTY p` obligation forces `p` lazily (at `Contract6` on the match path, at
  `ResolveParty` on the expiry path), so the bearer is refreshed at `Contract6`
  (`Machine.hs:1904`) and an `Expired` step is built at `Contract5` but **logged at
  `ResolveParty`** (`:1992`), where the party is known. Measured: an expiry with no `LEST` never
  forces the party; the breach's own party cell is peeked instead, so `PARTY Alice` (a nullary
  constructor, allocated as a value) is known and a computed party would not be.
- `StepOutcome`: the sketch's `Breached !BreachSummary` survives for exactly one site — the
  `BREACH` expression arm (`LEST BREACH`, `BREACH BY p`), where the machine constructs an
  `ExplicitBreach`; it carries no norm (a terminal is not an obligation) and no clock (the
  expression arm has none). A `DeadlineMissed` breach is not logged that way: it is the
  `Expired ToBreach` / `Matched ToBreach` step of the obligation that missed (the key already
  names the party and `Expired` carries the deadline), and a compound's is
  `Joined _ (JoinBreached summary)` at `RBinOp2`, where the blame is a choice between two and must
  be named. A `JoinNote` carries `jnResult`
  (`JoinFulfilled | JoinBreached BreachSummary | JoinPending`), `jnWinner :: Maybe Side` and
  `jnTieBreak :: Bool` — "which side won and whether by the CSL tie-break" is one step, not two.
  Three join-level outcomes were added for the `EVERY` machinery, which the sketch predates: `JoinReleased`,
  `JoinExpired !Branch !Rational`, `JoinFailed !Branch`, plus `JoinStalled` for the one arm of
  `Barrier1` that is neither (a `MAY` member lapsed under a barrier with no `LEST`). `Barrier1`
  matches its two terminals explicitly and throws on anything else (`Machine.hs:2059-2071`), so a
  new terminal value is a loud failure rather than a silent `JoinStalled`.
- `Branch` is `ToHence | ToLest | ToBreach` as sketched. Under a barrier the member's slots hold the
  join's sentinels, so for a norm whose `nkMember` is `Barrier`, `ToHence` reads "reported
  satisfied to the join" and `ToLest` "reported failed"; the join's own step follows.

The write is `tellDeonticStep :: DeonticStep -> Eval ()` (`Machine.hs:364`), modelled on
`traceEval`: an optional `IORef (DList DeonticStep)` in the reader env (`EvalState.deonticLog`,
`:286`), off by default (R5). `DeonticLog` carries two counters beside the steps — per-site
activations for `nkActivation`, and an `EVERY` cast register `(action site, bearer) ↦ MemberOf`,
written when a family is assembled (`registerCast`, `:514`) and read when a member's obligation
meets the stream (`armNormKey`, `:454`) — because the `ValObligation` a member becomes has no slot
for its membership and adding one is a value-type change P2b declined. With the log off the
machine computes nothing for it, but it does carry state it never reads: a lazy `norm :: NormKey`
through the eleven `Contract*` frame records and `QuantCtx` (`ContractFrame.hs:88` onward), which
nothing forces; the `ev'reoffered :: Bool` the machine already computed at `Contract2`, now
carried through six more records past `Contract5`, the only frame that consults it
(`ContractFrame.hs:143-188`); and a `pending :: Maybe DeonticStep` on `ResolvePartyFrame`
(`:324`), always `Nothing` when the log is off. One hot-path arm was also **restructured**, not
merely instrumented: the both-breached tie-break at `RBinOp2` (`Machine.hs:2136-2149`) went from
`vt <= vt' / otherwise / _` to `vt < vt' / vt' < vt / _` so the arm can expose which side won and
whether the tie-break chose it. Checked by hand: `vt == vt'` now falls through to the `_` arm and
picks the same operand the old `<=` branch did for both operators; the strict cases are
unchanged. The equality case is pinned by fixture 5; the strict cases rest on the golden suite.

**Call sites, as committed** (fresh line numbers; the July table above is stale):

| Site                                  | `Machine.hs` | Step                                                                                           |
| ------------------------------------- | ------------ | ---------------------------------------------------------------------------------------------- |
| `Breach` expression (`forwardExpr`)   | 1187–1191    | `Breached summary`: the explicit `BREACH`; no norm, no clock                                   |
| `App1` on `ValObligation`             | 1297         | `armNormKey`: the entry into the site; bumps `nkActivation`                                    |
| `Contract1` / `ValNil`                | 1708–1713    | `Waiting`, clock peeked                                                                        |
| `Contract5` expiry                    | 1801–1849    | `Expired branch deadline`, built here; routed cases logged at `ResolveParty`, breach case here |
| `Contract6`                           | 1858         | bearer refreshed                                                                               |
| `Contract8` / `False`                 | 1873         | `PartyMismatch`, `WitnessedOnly`                                                               |
| `Contract10`                          | 1893–1936    | `Matched ToHence/ToLest/ToBreach`, `Consumed`; `GuardFailed`                                   |
| `ResolveParty`                        | 1941         | the pending `Expired`, bearer filled, join progress worked out                                 |
| `Barrier1` verdict arms               | 2007–2019    | `JoinFailed ToBreach` on `ValBreached`, `JoinStalled` on `ValFulfilled`, throw otherwise       |
| `RBinOp1` (the `ROR` short-circuit)   | 2052         | `Joined ValROr JoinFulfilled LeftSide` — the OR's commonest success path                       |
| `RBinOp2` (six arms, one unreachable) | 2101–2160    | `Joined op note`; the fulfilled-LEFT `ROR` arm at `:2152` is unreachable past `RBinOp1`        |
| `startRollCall`                       | 2339         | `armJoinKey`: the join's own entry                                                             |
| `assembleQuantified`                  | 2374–2385    | `registerCast` (distributive 2374, fork 2375, barrier 2385)                                    |
| `fireBarrierHence`                    | 2559         | `JoinReleased`                                                                                 |
| `barrierFail`                         | 2590         | `JoinFailed ToLest`                                                                            |
| `barrierStateMissed`                  | 2606, 2614   | `JoinExpired ToLest` beside the `LEST` push, `JoinExpired ToBreach` beside the breach          |
| `patternMatchFailure`                 | 2921         | `ActionMismatch`, `WitnessedOnly`                                                              |

Seventeen sites. `JoinExpired` is logged inside `barrierStateMissed`'s two arms rather than at
`Barrier4`, so the log's `ToLest`/`ToBreach` is the machine's own routing and not a second copy of
the `lest` predicate (§2.4).

The library seam is `execEvalModuleWithDeonticLog` (`jl4-core/src/L4/EvaluateLazy.hs:662`):
`execEvalModuleWithEnv` with the log on for every directive, returning each directive's steps
beside its unchanged result, via `captureDeonticSteps` (`:192`, modelled on `captureTrace`; a
nested capture gets a fresh log and does not merge, because the counters would collide). The
existing signatures are untouched — `EvalDirectiveResult` is matched positionally at seventeen
sites (and by record syntax at seven more) across five packages, and was not widened. No CLI, no `doc/` page: nothing a user can invoke changed.

**Measured.** `jl4-core/test/DeonticStepSpec.hs` pins the exact sequence for seventeen shapes:
match → `HENCE`; expiry → `LEST` with the event `Reoffered` to the reparation; `MAY` expiry; party
mismatch then match; an `ROR` whose sides breach at the same instant, tie-break `RightSide`; a
barrier of two where member 1 logs `MemberSatisfied 1 2` and is not released, member 2
`MemberSatisfied 2 2`, then `JoinReleased` at clock 3, then the landlord's obligation; a fork where
Alice's continuation runs to completion before Bob's scan begins; a join-line deadline,
`JoinExpired ToLest 5` at clock 9, then the `LEST`'s `Breached`; an `ROR` whose LEFT side fulfils,
`Joined` at `RBinOp1`; `Waiting` for a plain obligation and for a barrier member; a prohibition
violated, `Matched ToLest` and `Matched ToBreach`; `GuardFailed`; `ActionMismatch`; a barrier with
a `LEST` whose member misses (`Expired ToLest 14`, `JoinFailed ToLest`, `Breached`); a barrier with
no `LEST` whose `MAY` member lapses (`JoinStalled`) and whose `MUST` member misses
(`JoinFailed ToBreach`). Every `StepOutcome` constructor now has at least one positive assertion.
The off path is proved unchanged by rendering every fixture both ways.
`JL4_LIBRARY_PATH=$PWD/jl4-core/libraries cabal test jl4-core-test`: 578 examples, 0 failures
(19 of them in this spec); the same variable and `cabal test jl4-test`: 3143 examples, 0 failures, no golden moved — including after `Barrier1` started throwing on an unnamed terminal, so no corpus file reaches one.
One thing the fixtures found that the design did not predict: `partyKeyWHNF` renders a
constructor party with its unforced fields as heap addresses (`Tenant OF &161@main.l4`), which is
the ledger's existing key and is pinned by prefix, not by value; `ekAction` does the same. (The
bearer half of this is answered by the LANDED 2026-09-16 block below; `ekAction` still is.)

About `Waiting` under a barrier, stated with its scope: a barrier member that **completes** never
logs `Waiting`, because its match hands control to the checkpoint sentinel; a member still
pending when the stream runs out **does** log `Waiting`, with `nkMember = Barrier`, and the join
logs nothing for it (fixture 11; the corpus shows the same residual at
`jl4/examples/ok/every/tests/run-barrier.golden:26`). The first commit on this branch, and an
earlier revision of this paragraph, stated the first half as a universal; that was one fixture in
which every member matched, generalised to a case it had not measured.

**Not built.** `dsClock` for `Joined` and `Breached` (no time in the frame or the expression arm;
for `Joined`, see the LANDED 2026-09-16 block for why the one time the frame could carry was
declined); a site for the compound (needs `ValROp` to carry its annotation); the residual's `NormKey` — a
`ValObligation` returned as the value of a directive carries no key, so a residual re-applied by a
later milestone (live mode, §4.5) starts a fresh activation count. The cast register is keyed by
`(action site, bearer)` value alone, with no activation in the key, so an `EVERY` whose `HENCE`
re-enters the same `EVERY` (a recursive quantified rule) overwrites the outer cast's entries before
the outer's later members are armed, and those members would then report the inner cast's
`moIndex`/`moTotal` — silently, exit 0. No fixture exhibits it (fixture 7 measures that a fork
member's continuation runs to completion before the next member is armed, which is the
precondition); the fix is the value-type change declined above, a membership slot on
`ValObligation`. Nothing in `L4.StateGraph` was touched: B1's static half of the key is still
owed there.

**What review changed (2026-09-15, same branch, second commit).** Two read-only reviewers found:
the `ROR` short-circuit at `RBinOp1` logged nothing, so the OR's commonest success path was silent
and the `RBinOp2` arm that would have logged it is unreachable — now logged at `RBinOp1`, fixture 9;
the explicit `BREACH` was logged nowhere, so a log ending `JoinExpired ToLest` could not say the
`LEST` was a breach rather than a reparation — now the `Breached` step, fixtures 8 and 15; the
"never logs `Waiting`" universal above, retracted; eight outcome constructors had no positive
assertion — fixtures 10–17; `Barrier4` re-derived the `LEST`-vs-breach routing for the log —
moved into `barrierStateMissed`'s arms; `Barrier1` classified with a wildcard — now explicit and
loud; and the "only extra work is a lazy `NormKey`" claim was narrower than what shipped — widened
above. Declined, with the reason recorded in "Not built": keying the cast register by activation.

**LANDED 2026-09-16 — the bearer, recorded at the match and made comparable (P2b follow-up, on
`lts/p2b-bearer`; not pushed, no PR as of 2026-09-16).** Three things had one cause: `--steps` printed `Tenant OF …` for a
record-shaped party (§7.6 "What it cannot"), the key could not be compared with a `LiveNorm`'s
`lnBearer` (§7.6 review finding 2, and `confirmAct`'s rank heuristic under an `EVERY`), and the
member ordinal was doing the reader's work of telling members apart. The cause was that
`nkBearer` is `partyKeyWHNF` at arming: the ledger key, whose unforced fields print as heap
addresses. Fixed by recording a second rendering **where the machine forces the fields**, not
at arming:

- `NormKey.nkBearerName :: Maybe Text` (`DeonticStep.hs:138`) is the party's `Value NF`
  rendered through `prettyLayout` — the same printer and shape `L4.Lts.Marking.renderLive` uses
  for `lnBearer` (`Marking.hs:348`) — so the two compare by `==`. `nkBearer` is **kept**, not
  repurposed: it is the key the cast register (`dlMembers`) is looked up by at `armNormKey`, and
  it exists before any field has been forced, which the name does not. `EventKey.ekPartyName`
  (`:205`) and `BreachSummary.bsBlameName` (`:349`) are the same rendering for the event's party
  and a breach's blame.
- The rendering is `peekNF` (`Machine.hs:416`): a `traverse` over the `Value` that reads each
  reference with `peekWHNF` and answers `Nothing` as soon as one is still a thunk, with
  `nfAux`'s depth cutoff. **It never forces.** `peekName` (`:430`) is its `prettyLayout`.
- Where it is read: `Contract8` (`:1914`, `naming party norm`) — the party equality at `Contract7`
  has just forced the fields (all of them on a match, up to the first difference on a mismatch),
  and the named key is carried into `Contract9`/`Contract11`/`Contract1` so `GuardFailed`,
  `ActionMismatch`, `Matched` and the following `Waiting` all carry it; `ResolveParty` (`:1997`)
  for the expiry path; `Contract5`'s no-`LEST` breach and `breachSummary` (`:526`) peek the
  breach's party cell the same way; `armNormKey` (`:468`) peeks at arming too, which is `Nothing`
  unless something earlier forced the fields. **The mismatch half of that parenthesis is a
  limit, not a footnote** (MEASURED 2026-09-16, below): the equality (`EqConstructor3`,
  `Machine.hs:1520`) answers `FALSE` at the first field pair that differs and never touches the
  rest, so a `PartyMismatch` step for a party whose _earlier_ field differed from the actor's has
  `nkBearerName = Nothing`, and so does the `Waiting` after it. Every party in the corpus and in
  fixtures 18 / case 6 has one field, where "the first difference" is also the last, which is
  why the first write-up read as if a mismatch named the party too. With the log off, `naming` is the old pure
  `bearing` behind one `asks`.
- Measured, `jl4-core/test/DeonticStepSpec.hs` fixture 18 (`:682`): on fixture 6's barrier every
  member step names `Tenant OF "Alice"` / `Tenant OF "Bob"`, the landlord's `Landlord OF "Ms
Ng"`, and the event party alongside; on fixture 15's expiry the `Expired` step at
  `ResolveParty` is named and the join's own step and the `Breached` are not; at the barrier's
  **outset** (no event compared) both `Waiting` steps have `nkBearerName = Nothing` while
  `nkBearer` is still the `Tenant OF &…` form — the log did not force the fields for its own
  sake; a nullary `PARTY Alice` renders `Alice` both ways. The log-off equivalence test covers
  the new fixture.
- `confirmAct` (`WhatIf.hs:391`) now finds the candidate's own step by **site and bearer**
  (`:412`: `nkBearerName == Just name` for a `KnownParty`), and the most-specific-reason rank is
  **retired**. The candidate's own step is named for a narrower reason than "the comparison ran":
  the hypothetical act is _by_ the candidate's bearer, so its own obligation's party comparison
  matched, and a match forces every field; the other members' mismatch steps may carry no name
  (the limit above) and are not the ones the filter wants. An `UnforcedParty` candidate has no rendered name to compare and takes every step
  at its site as its own — such an obligation is not an `EVERY` member (the roll call forces
  every member), so its site has one bearer. Measured, `LtsListSpec.hs` case 6 (`:230`; case 7, the two-field limit, `:271`): a
  barrier of two with `PROVIDED t EQUALS bob` — Alice's act is `PassedOver GuardFalse` and the
  step that carried it has her name, the other member's look at the same event has Bob's; Bob's
  act advances. Cases 1, 4 and 5 and `LtsWhatIfSpec` are unchanged.
- The renderer (`List.hs:468`, `partyText`) prints the name when the log had it and the elided
  key otherwise, in text and JSON. Goldens: `every-run-example.txt`/`.json` moved **only** in
  party text — `git diff lts/p2-followups...HEAD -- jl4/examples/lts/expected/every-run-example.txt
| grep -c '^[-+] '` = 78 (39 pairs, every one carrying `Tenant OF`/`Landlord OF`), and 144 on
  the `.json` (72 pairs: 71 `"party"`, 1 `"by"`), checked by `diff` before blessing (the commit
  message's 72/71 were the first pass's counts, before the `by` lines named the fork's breach);
  `contracts.*` (nullary parties) and `tenancy.*` (fresh positions: `Waiting` before any
  comparison, still `Tenant OF …`) did not move. The CLI's output is byte-identical to the
  blessed goldens — measured against an `exe:l4` rebuilt from HEAD (the first pass ran the diff
  with a binary older than its last edits, which printed `Tenant OF …` on the three `by` lines
  the goldens name; see MEASURED 2026-09-16 below). `--json`'s `format` stays `1`: `party` and `by` are free text, not
  discriminators, and mean what they meant; only the rendering is fuller.
- **Not built:** `ekAction` is still the elided layout (`Sign OF …`) — the action is unpacked
  only as far as the rule's pattern needs, and naming it fully would need the same peek over a
  value the machine may not have forced; the page says so. `dsClock` for `Joined`: the one time
  `RBinOp2` could carry with a single field is the compound's **arming** time (the `[time,
events]` args of `RBinOp1`), which is neither when the join reduced nor when a breach
  materialised — a fork's `both parts together: breached` after day 20 would print `at 0`. That
  misleads more than `at —`; the honest clock (the later of the operands') is not on the frame.
  Left as is.

**MEASURED 2026-09-16 — the review of the block above, re-run against a fresh binary.** A read-only
review found that every artefact the block's measurements were taken with predated the last source
edit (`exe:l4` 01:22:57 and `jl4-core-test` 01:28:22 against `Machine.hs` 01:32:59; only
`jl4-test`, linked 01:33:24, was fresh), and that the "who looked is named" claim held only for
one-field parties. Re-measured at HEAD, one `cabal` at a time:

- `cabal build exe:l4`, then `l4 lts doc/reference/regulative/every-run-example.l4 --steps | diff -
jl4/examples/lts/expected/every-run-example.txt` and the same with `--steps --json` against the
  `.json`: both `diff` exit 0. (The stale exe differed on exactly three lines — the `BREACH
declared by` and two `both parts together: breached by` lines, which it printed as `Tenant OF
…` — so the golden was right and the exe was behind.)
- A two-field party, `Tenant HAS name IS A STRING, age IS A NUMBER`, `alice MEANS Tenant OF
"Alice", 30`, `bob MEANS Tenant OF "Bob", 40`, the barrier of `every-run-example.l4`, one event
  `PARTY alice DOES Sign alice AT 1`: `l4 lts --steps` prints `at 1: Tenant OF "Alice", 30 does
Sign OF … at 1; Tenant OF …, … MUST (member 2 of 2) — not this party's event; passed over` and
  then `at 1: Tenant OF …, … MUST (member 2 of 2) — no more events; still waiting`. With the
  fields the other way round (`age` first, both 30, so the difference is in the LAST field) both
  lines name `Tenant OF 30, "Bob"`. That is the equality's short-circuit, exactly as the
  parenthesis above says and the page now says. With `PROVIDED t EQUALS bob` on the same
  two-field barrier, Alice's act is still `PassedOver GuardFalse` and Bob's advances: `confirmAct`
  is unaffected, for the reason now written beside it.
- Pinned: `LtsListSpec.hs` case 7 (the two-field barrier: verdicts as case 6; the other member's
  `PartyMismatch` step has `nkBearerName = Nothing`; `--steps` prints the two elided lines above)
  and, in `DeonticStepSpec.hs` fixture 18, a `bsBlameName` assertion on a record-shaped `LEST
BREACH BY t` (`forkBreachSrc`: the fork of `every-run-example.l4` with Bob never signing;
  `Breached` carries `bsBlame = Just "Tenant OF &…"`, `bsBlameName = Just "Tenant OF \"Bob\""`).
  `JL4_LIBRARY_PATH=$PWD/jl4-core/libraries cabal test jl4-core-test`: 651 examples, 0 failures.
- Not changed: `reasonFor`'s middle fallback (`mapMaybe reason (map snd atSite)`) was reviewed as
  a duplicate of `own` for an `UnforcedParty` candidate. It is — but for a `KnownParty` it is the
  documented "no step with the bearer's name at the site" fallback, `atSite` is `let`-bound and
  traversed, not recomputed, and dropping it would change behaviour for a case the comment names.
  Kept.

### 4.4 The gotcha the animator must model: an event can be scrutinised twice

Expiry re-offers the revealing event to the continuation, at most once, marked by store address
(`markReoffered`/`isReoffered`, `Machine.hs:767-778`; the rule is documented at `:1808-1839` and
again in `ContractFrame.hs:68-75`). It exists to keep recursive `HENCE`/`LEST` continuations with
non-positive deadlines terminating — the motivating case in the comment being
`x MEANS PARTY p MUST a WITHIN d LEST x`.

A naive "one event, one animation frame" misrepresents this. `dsScrutiny` is the explicit
**witness-versus-consume** distinction, and the scrubber must be able to show the same event
twice without the viewer concluding it happened twice.

**And this is precisely where §3.4's B2 bites.** The motivating contract is recursive; the board
`StateGraph` draws for it does not close its loop; so the animator has nowhere to put the token
on the second scrutiny. The gotcha and the missing loop are the same problem seen from two sides.
_(B2 landed 2026-09-16: the board now closes it, for a self-reference and for a reference through
another rule alike; see §3.4.)_

### 4.5 Two modes

| Mode       | Drives from                                                       | Blocked on                                           |
| ---------- | ----------------------------------------------------------------- | ---------------------------------------------------- |
| **Replay** | an authored `#TRACE c AT t WITH …` or a POSTed event list         | nothing but §4.3 and the enabled-set endpoint        |
| **Live**   | a deployed instance's persisted residual, advanced event by event | `STATEFUL-CONTRACT-DEPLOYMENT` §3.1, its own blocker |

**Replay is the deliverable.** Live mode is a later beneficiary of someone else's milestone and
must not be on P2's critical path.

### 4.6 Vocabulary we borrow rather than invent

- **Missing vs remaining tokens**, from token-based replay in process mining (van der Aalst et
  al.; PM4Py, arXiv `2007.14237`). A _missing_ token is a required act that was skipped —
  breach. A _remaining_ token is an obligation never discharged — F3 vacuity, at the end of the
  trace. These are established words for the two diagnostics we most need; do not coin new ones.
- **`Verdict`**, from `DESIGN.md:1506`, unchanged.
- **Symboleo's lifecycle names**, subject to R8's verification caveat. `Lapsed` (§4.2a) is
  **ours** and is flagged as such — R12.

### 4.7 Layout — the section revision 1 did not have

The word "layout" appeared once in revision 1, in a ruling the review then overturned. This is
the corrected treatment, and it is short only because the problem is now bounded, not because it
is small.

**The facts.** `StateGraph` has no coordinates (`:82-147` is all `Text` and `Int`), and the
shipped DOT renderer delegates positioning entirely to GraphViz (`GV.printDotGraph`, `:552`) —
a facility unavailable in the browser, where K6 and §2.4 put the drawing. So P2 must lay out its
own picture, and the two-plane form is **strictly harder** than P1's: norm-plane places plus
constitutive links that cross between planes.

**What P1 proved.** The BPMN exporter's layout is ~400 lines of `L4.Bpmn.Lower` (`:1210-1609`):
a layered left-to-right assignment from the **longest-path ranking**, banded by lane, with a
derived gutter width holding one channel per turning flow. Its own header is worth quoting as a
scope limit: _"State graphs are small, so this is enough; nothing here is trying to be a
graph-drawing engine."_

**What P1 also proved, and this is the sting.** That algorithm **cannot rank a node on a cycle**,
and the exporter says so in a fidelity note rather than drawing a lie:

> `P-CYCLE` — _"BPMN can draw a loop, but this layout places a node by its longest path from the
> start and a node on a cycle has none, so inside the loop a node further right no longer means a
> moment further on: the positions are wherever the relaxation ran out of fuel."_
> (`Lower.hs:781-799`)

Today that note never fires, because gap 3 means extraction never produces a cycle. **Closing the
loop (B2) is exactly what makes it fire.** So P2's own precondition breaks the only layout
algorithm we have shipped evidence for. That coupling was invisible in revision 1 and is the
single most under-costed item in this document.

> **MEASURED 2026-09-16, with B2 landed.** "Never fires" was already false when written: the
> self-`HENCE` closed under `TargetSelf` on 2026-07-27, and `regcf-reporting.fidelity.txt` has
> carried `P-CYCLE` since `a9caf2f6` the same day. What B2 added is the cycle _through another rule_, and here is what
> P1's layout did with one (`ping` → `pong` → `ping`, exported and read back): it emitted a real
> back-flow (`Flow_Task_1__Task_0`); the relaxation ran its `length nodes` steps of fuel and
> stopped with **both** tasks in the same, rightmost column (`x="1280"` for `Task_0` and
> `Task_1` in the DI) and the `Breach` end event to their _left_ (`x="1132"`), since every node
> on the loop climbs one rank per step until the fuel is gone; `P-CYCLE` fired naming
> `(initial, pong)`; Camunda's validator accepted the file; the token game found it SOUND (8
> markings, peak 1 token); and jBPM refused it on its "more than one incoming connection" dialect
> limit before executing anything. So the layout does not break; it draws a picture in which the
> horizontal axis is not time inside the loop — nor, here, outside it — and says so, which is
> exactly the loss the note promised. Nothing here changes the B3 ruling below: the
> feedback-edge set is still the honest answer, and still not built.

**Ruling (B3).** Layout splits along K6, as everything else does:

- **Haskell serves structure**: rank, lane/band, junction kind, plane assignment, and — once B2
  lands — a **feedback-edge set** so the ranking can run on the DAG that remains after cycle
  edges are set aside, with cycle edges drawn as explicit back-arcs. This is the standard
  Sugiyama first phase and it is the honest answer to `P-CYCLE`; it is also the piece P1 declined
  to build and reported instead.
- **TypeScript assigns pixels**: the browser turns ranks and bands into an SVG, and owns the
  scrubber, the highlight and the animation.

**Bounds, stated because revision 1 bounded nothing.** The picture is legible to roughly **40
action-plane states and 25 concurrently-marked norm places**. Past that it should degrade to
§1.1a's list rather than draw something unreadable, and P2 should emit its own `P-…`-style note
saying which. Nobody has measured the real corpus against those numbers; measuring them is part
of P2a′.

### 4.8 How the view is reached — a CodeLens above the rule, exactly as the ladder has

**Requirement, Meng 2026-09-14.** In **both** the jl4 web IDE and the VS Code extension, a small
clickable affordance sits immediately above a function whose body is a regulative (deontic)
expression, and opens the LTS view in a **separate pane**. This is the same affordance the boolean
ladder already has, and it should be built the same way.

Recording it here because §5.1 commits P2 to _"an interactive view … the reader, in our surface"_
and then never says how the reader reaches it. A view with no entry point is not a deliverable, and
"the IDE people will wire it up" is how it becomes nobody's.

#### The template, traced end to end

The ladder's lens is the thing to copy, and it existed in full when this was written. _(The
anchors in this list and in the table below are of `unstable` before P2g; the P2g commit moved or
shifted every one of them — items 1 and 4 and the table's `producer` row now live at
`jl4-lsp/src/LSP/L4/Actions.hs:181` and `API.hs:691`, `:706`, `:405` — see LANDED below. They are
left as written so the "four edits" argument still reads against the tree it was made on.)_

1. **LSP producer** (`jl4-lsp/app/LSP/L4/Handlers.hs:381-407`; moved 2026-09-15 to
   `Actions.hs:181` `decisionGraphCodeLenses`). `mkDecisionGraphCodeLens` emits
   `{ title = "Show decision graph", command = "l4.visualize", arguments = [verTextDocId, srcPos, False] }`
   anchored at `pointRange (srcPosToPosition node.start)`. `foldTopLevelDecides` supplies the
   candidates and `canVisualize` (`:392`; now `Actions.hs:196`) filters them by **speculatively
   running the visualiser** and keeping only the `isRight` — so a lens never appears above
   something that would fail to draw.
2. **VS Code host.** `l4.visualize` is declared in `ts-apps/vscode/package.json:274`, named in
   `ts-apps/vscode/src/commands.ts:1`, and handled in `extension.mts`, which owns a panel manager
   (`:335`).
3. **Web host.** There is no language server in the browser, so the wasm shim re-implements the
   protocol: `ts-apps/jl4-web/src/lib/wasm/wasm-message-transports.ts` advertises
   `codeLensProvider` with `l4.visualize` in its command list (`:296-302`), routes
   `textDocument/codeLens` (`:245`) to `handleCodeLens` (`:356`), and executes the command at
   `:586`.
4. **Wasm producer** (`jl4-core/src/L4/API.hs:644-676`; shifted 2026-09-15 to `:691`, `mkVizLens`
   at `:706`). `l4CodeLenses` builds its own lens via `Ladder.findAllVisualizableDecides`
   (`jl4-core/src/L4/Viz/Ladder.hs:242`) and `mkVizLens`.

**The discovery half is already symmetric.** `L4.StateGraph`'s own walk
(`extractFromTopDecl`, `StateGraph.hs:393-398`) is the same shape as `foldTopLevelDecides` plus
`canVisualize`: top-level `Decide`s, kept when `findRegulativeExpr` succeeds on the body. The
predicate P2 needs is therefore "`extractStateGraph` returns a graph", and it is the
speculative-success gate by construction, exactly as the ladder's is.

#### The trap: two producers, two addressing modes, two hosts

The costly, non-obvious part — and the reason this is a spec entry rather than a checklist item —
is that the two lens producers are **independent code paths that do not agree on how a target is
named**:

|                         | LSP path (VS Code)                                   | wasm path (web IDE)                                                                   |
| ----------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------- |
| producer                | `Handlers.hs:381`, in Haskell (now `Actions.hs:181`) | `API.hs:658` `mkVizLens`, in Haskell (now `:706`)                                     |
| addresses the target by | **source position** (`srcPos`)                       | **name** (`vd.vdName`)                                                                |
| dispatches to           | `Ladder.doVisualize` on the node at that position    | `l4_visualize_by_name` (`API.hs:403-407`; now `:405-409`)                             |
| index base              | LSP, 0-indexed                                       | Monaco, **1-indexed** (`mkVizLens`'s comment says so)                                 |
| TS side must also       | declare the command in `package.json`                | list the command in `codeLensProvider` **and** add a `case` to the command dispatcher |

So a deontic lens is **four edits, not one**: a lens in the LSP handler, a lens in `l4CodeLenses`, a
new name-addressed wasm export beside `l4_visualize_by_name` (there is no `l4_state_graph_by_name`
today), and registration in each host. Anyone who scopes this as "add a CodeLens" will find the
web IDE silently lensless, because the browser never runs the handler they edited.

#### What this makes cheap, and why it strengthens the gate

**The entry point is independent of whichever renderer sits behind the pane.** The lens produces a
command and arguments; the host opens a pane; what the pane draws is the renderer's business. That
has a useful consequence for §7.3: the lens can be wired to the **shipped** `stateGraphToDot`
output — which needs no P2 back end at all — and that is the cheapest available way to run P2a′ and
P2a **in the place readers actually are**, rather than in a CLI they will not use. A picture judged
from a terminal is being judged out of position.

Two smaller points, stated rather than ruled:

- **Pane sharing.** VS Code already has one panel manager for the ladder. Whether the LTS view is a
  second tab in that panel or a panel of its own is a real choice and belongs to whoever builds it;
  the default that costs least is a second view type in the existing manager.
- **Unmeasured.** Nobody has checked whether a `Decide` whose body is regulative _also_ passes
  `canVisualize`, i.e. whether the two lenses would stack on one line. It is a five-minute
  observation against `jl4/examples/legal/regcf/regcf.l4` and it should be made before the lens is
  designed, not after. R13. _(Measured 2026-09-15: they never stack. See §8 R13.)_

#### LANDED 2026-09-15 — P2g, on `lts/p2g-codelens` (merged into `lts/p2-stack` 2026-09-15, not yet in `unstable`)

The four edits, plus the shared piece the "four edits" framing did not predict. Line numbers are
of the tree this block was committed in. "Landed" here means committed on the branch: at the time
of writing the branch is unpushed and has no PR, and what would make it more than that is a PR
into `unstable` with the `wasm-build` job green (see the last "not built" item).

**The shared piece: `jl4-core/src/L4/StateGraph/Lens.hs` (new).** Both producers need the same
three things — which `Decide`s earn a lens, how to find one again from a click, and what a click
returns — so they live once. `stateGraphTargets` (`:76`) runs `extractStateGraphs` over the module
and joins each graph back to its `Decide` by `sgDecide` (the `Unique` extraction already records),
keeping only `Decide`s that have a source range to anchor on. `stateGraphAtPos` (`:99`) is the LSP
address, `stateGraphByName` (`:104`) the wasm one, and `stateGraphResponse` (`:116`) is the
payload: `{ "name": sgName, "dot": stateGraphToDot defaultStateGraphOptions }`. The gate is exactly
the speculative-success gate §4.8 predicted — a `Decide` has a lens iff extraction produced a graph
for it — and `L4.StateGraph` itself is untouched.

1. **LSP producer.** The ladder's inline lens code moved out of the handler into
   `jl4-lsp/src/LSP/L4/Actions.hs` as `decisionGraphCodeLenses` (`:181`, behaviour unchanged) so a
   test can call it; `stateGraphCodeLenses` (`:213`) sits beside it, title "Show state graph",
   command `l4.stateGraph`, arguments `[verTextDocId, srcPos]` (the ladder's shape minus the
   simplify flag), anchored at the `Decide` node's start like the ladder's. `stateGraphAtPos`
   (`:229`) serves the click. `Handlers.hs` concatenates the two producers (`:394-395`), gains
   `CmdStateGraph` (`:1044`, `:1051`) and dispatches it (`:322-329`). Because `l4CmdNames` feeds
   `optExecuteCommandCommands` (`jl4-lsp/app/Server.hs:90-91`), the VS Code client and the
   websocket-connected web client register the command from server capabilities; the wasm shim
   has no server to ask and lists the command itself (item 4).
2. **Wasm producer.** `jl4-core/src/L4/API.hs`: `l4CodeLenses` appends `stateGraphLenses` (`:702`)
   built by `mkStateGraphLens` (`:729`) — name-addressed, Monaco 1-indexed, arguments
   `[verDocId, name]` where `name` is `prettyLayout (getActual …)` with backticks, spelled the same
   way `findAllVisualizableDecides` spells `vdName`; `l4StateGraphByName` (`:654`) serves it and
   `foreign export javascript "l4_state_graph_by_name"` (`:413`) sits beside `l4_visualize_by_name`
   under the same `wasm32_HOST_ARCH` guard. It does not refuse on a type error elsewhere in the
   module, unlike the ladder export: the graph is read off the resolved syntax.
3. **VS Code host.** `ts-apps/vscode/package.json:278` declares the command,
   `src/commands.ts:3` names it, and `extension.mts` branches on it in the `executeCommand`
   middleware (`:330`) _before_ the ladder decoder, since the payload is not a ladder. The pane is
   `src/state-graph-panel.ts` (new): one reusable webview beside the editor showing the DOT text
   with a **Copy DOT** button (the copy goes through `vscode.env.clipboard`). **No renderer.**
   Measured 2026-09-15: `grep -i "graphviz\|viz\.js\|d3-graphviz\|hpcc-js\|@viz-js"` over
   `package-lock.json` and every `ts-apps/*/package.json` and `ts-shared/*/package.json` finds
   nothing, so drawing the picture in-pane means a new dependency and a lockfile change, which this
   branch does not make. The pane says so to the reader.
4. **Web host.** `wasm-bridge.ts` declares the export (`:103`) and wraps it as `stateGraphByName`
   (`:476`); `wasm-message-transports.ts` lists the command (`:305`) and dispatches it to
   `handleStateGraph` (`:598`, `:614`); `+page.svelte` intercepts the `{name, dot}` reply in its
   middleware (`:756`) and shows it in a third right-pane view, `'stategraph'` (`:77`, `:1227`),
   rendered by `src/lib/components/state-graph-panel.svelte` (new). Over the websocket transport
   the same middleware branch handles the LSP producer's reply, since both producers answer with
   the same JSON.

**Tests.** `jl4-lsp/test/StateGraphLensSpec.hs` (6 examples): the two lenses on a one-of-each
fixture land on different lines with the right titles and arguments; a click returns DOT named
after the rule; a click on the boolean rule's anchor is refused; and on `ok/contracts.l4` and
`doc/reference/regulative/every-run-example.l4` every regulative rule (7 and 2) gets the lens and
none gets the ladder's. `jl4-core/test/ApiStateGraphLensSpec.hs` (4 examples): the wasm lens's
line, title and `[verDocId, name]` arguments; the name round-trips through `l4StateGraphByName`;
`notFound` for the boolean rule. `JL4_LIBRARY_PATH=$PWD/jl4-core/libraries cabal test jl4-lsp-test`
→ 21 examples, 0 failures; `… cabal test jl4-core-test` → 563 examples, 0 failures. TS: `npm run
lint` (vscode, jl4-web), `tsc -b` (vscode, 0 errors after building its workspace deps), `npm run
check` (jl4-web, 0 errors 0 warnings), `npm run test` (vscode, 6 pass), `npx prettier@3.4.2
--check` on every touched file — all green.

**Doc.** `doc/reference/regulative/STATE-GRAPH.md` (new), linked from `SUMMARY.md`, the regulative
README, module 6 and the regulative-rules concept page; `doc/test-docs.sh` → 1495 links, 100 `.l4`
files, 250 linked, 0 errors. _Review 2026-09-15 changed:_ the page had said the lens "works the
same way … in the web editor at jl4.legalese.com" in the present tense; the web path was never
built for wasm here (previous bullet), and that host is deployed by hand with `nixos-rebuild`
from a checkout (`nix/README.md:22-29`) that cannot contain an unpushed branch. It now says the web editor gets it "from the release that carries this change" and names no URL.
Same pass: `next`/`failure` for the two hand-over arms (`StateGraph.hs:861`, `:909`), the bare-MAY
gap from the extractor's own NOTE (`:917-935`), and the web-host pane eviction above.

**Not built, and what would make it true.**

- _The picture._ The pane shows DOT source. An in-pane rendering needs a DOT renderer in
  `ts-shared/` (a `@viz-js/viz` or `@hpcc-js/wasm` dependency, hence a lockfile change reviewed on
  its own), or a hand layout of `StateGraph` in Svelte — §4.7 says what that costs.
- _Live refresh._ The ladder redraws on every `didChange`; the state-graph pane is a snapshot and
  says so. Wiring it to `didChange` is one more branch in each host's middleware plus a "last
  target" slot, the same shape as `lastVizArgs`; not done because a snapshot of DOT text that
  nobody renders in-pane gains nothing from refreshing. **In the web host the snapshot is also
  evicted:** every edit runs `debouncedVisualize` (`+page.svelte:161-167`, called from `didChange`
  at `:826`), and a successful ladder reply sets `rightPaneView = 'ladder'` unconditionally
  (`:797`), reclaiming the shared pane from `'stategraph'` (`:763`) — the same thing already
  happens to the `'inspector'` view (`:561`, `:718`). Read from code, not clicked. Left as is
  rather than guarded, because guarding would leave a stale map in front of a reader who has just
  changed the rule, and the doc page now says what happens instead. VS Code is unaffected: its
  pane is a separate webview (`state-graph-panel.ts`).
- _Pane sharing._ VS Code got a panel of its own rather than a second view type in the ladder's
  `PanelManager`, because that manager loads the ladder webview bundle and messenger, none of which
  a `<pre>` needs. Revisit when there is a picture.
- _Neither host was exercised by a human click._ The producers and the LSP click handler are
  under test; the TS is type-checked and linted, but **no unit test covers the state-graph path
  in either host** — the "6 pass" above is `path-translation.test.ts` and `extension.test.ts`,
  both pre-existing, and `grep -rn "stateGraph\|StateGraphPanel\|cmdStateGraph"` over
  `ts-apps/vscode/src/unit-tests/` and `src/test/suite/` finds nothing. Nobody opened an editor
  and pressed the lens. That is the first thing the integrator should do.
- _The wasm build._ `l4_state_graph_by_name` (`API.hs:413`) and the `l4CodeLenses` change sit
  under `#if defined(wasm32_HOST_ARCH)` (`API.hs:356`–`444`), and no wasm toolchain is installed
  where this was built (`wasm32-wasi-ghc`, `wasm32-wasi-cabal`: not found), so `cabal test all`
  never compiled that export and nothing on this branch has run it. CI's `wasm-build` job
  (`.github/workflows/pr-checks.yml:2018`) compiles it on the PR; nothing executes it until someone
  clicks the lens in jl4-web in wasm mode. The native tests in `ApiStateGraphLensSpec.hs` exercise
  `l4StateGraphByName`/`l4CodeLenses`, i.e. everything up to the FFI edge, not the edge itself.

### 4.9 Catching up with EVERY/EACH — where the join is lost, measured

**Raised by Meng, 2026-09-14: this strand needs bringing up to date with the branch/fork/join logic
that landed on the EVERY/EACH branch.** He is right, and the gap is structural rather than
cosmetic. R2 carries the corrected status; this section carries the measurement.

`EVERY-EACH-QUANTIFIER-SPEC.md` §2.5, under _"Owed, from these rulings"_, records the symptom and
leaves the diagnosis open, in terms worth quoting because they are the assignment:

> **The BPMN export cannot tell a barrier from a fork, and its fidelity report does not say so.**
> … one rule exported twice, once with `ONCE ALL HAVE` and once with `UPON EACH`, gives
> **byte-identical** BPMN XML and a **byte-identical** fidelity report. … Not yet located: the
> collapse may be in the state graph the exporter reads or in `L4.Bpmn.Lower`; whoever fixes it
> should measure which before writing a finding.

**Located, by source read on `unstable` at `75068010`, 2026-09-14. It is the state graph, and
`L4.Bpmn.Lower` could not fix it if it wanted to** — the distinction is already gone by the time
the exporter reads its input. Three independent confirmations:

1. `extractDeonton` (`StateGraph.hs:673`) destructures
   `MkDeonton{subject, action, due, hence, lest}`. **`join` is not bound.** Nothing downstream can
   consult a field the extractor never reads, and because this is a record pattern it does not
   fail to compile when the constructor grows — the field was added and the extractor kept
   building, silently.
2. `subjectText`'s own header (`StateGraph.hs:884-890`) says so outright, and honestly: an `EVERY`
   is rendered as **one node labelled with the quantifier**, the cast is not fanned out, and _"the
   `ONCE …` join line is likewise not drawn."_ That is a deliberate phase-1 scope note, correctly
   written down — it is only a defect now because the language moved past phase 1.
3. `JoinOnce`/`JoinUpon` appear in nine modules under `jl4-core/src` — `Syntax`, `Parser`,
   `Desugar`, `TypeCheck`, `TypeCheck.Annotation`, `Parser.ResolveAnnotation`, `Print`, `Nlg`,
   `EvaluateLazy.Machine`. **`StateGraph.hs` is not among them, and neither is any `L4/Bpmn/*.hs`.**
   The front end and the evaluator know about the join; both process projections do not.

_(Source-level localisation, not an execution: the byte-identical-XML measurement above is the GM's
of 2026-09-07 and stands on its own. What is added here is where it happens and why.)_

**FIXED FORWARD 2026-09-15 — P2h's first half, on `fix/join-on-state-graph`.** Re-measured before
the change with `l4 state-graph` on `ok/every/barrier.l4` and `fork.l4`: the `EVERY` edge read
`EVERY Tenant t MUST Sign ... [14]` and `EVERY Tenant t MUST Pay ... [7]`, no join anywhere. After:
`…\nONCE ALL HAVE` and `…\nUPON EACH`, and `once-within.l4` shows `ONCE ALL HAVE WITHIN 30`. The
pattern at `extractDeonton` is now positional — `(MkDeonton _ subject action due mJoin hence lest)`
— so the next field the constructor grows is a type error there rather than a silent drop; the
`Threshold` and `Join` cases have no wildcard arm for the same reason. Two things the fix found
that the localisation did not predict: (1) a rule whose only `WITHIN` sits on the join line had its
`LEST` arm captioned `unreachable: no WITHIN`, contradicting `Machine.hs`'s `memberDue`, which
falls back to the join's deadline — `memberDeadline` now encodes that rule for every consumer; (2)
the prediction that this "moves P1's goldens" was wrong in fact: none of the six BPMN golden sources
contains an `EVERY`, so all six are byte-identical before and after, and the witness is two **new**
goldens cut from the reference page's own example. jBPM rejects both new files for want of a
collection on the multi-instance activity (`ForEach has no collection expression`) — the exact gap
`P-CAST` declares, now with an engine's word for it; `etc/bpmn-kie-baseline.txt` records it as
class (d). What P2 still owes is the second half: the norm-plane drawing rule for "marked but not
enabled", and `markingOf` against `Threshold`. **The second of those LANDED 2026-09-15** (P2c,
§4.2a's block: `Awaiting {awProgress :: Maybe Progress}` with `Progress.prThreshold :: Threshold
Resolved`); the drawing rule (P2h's second half, §7.2) is still owed.

**Reviewed the same day by the concurrency persona; verdict RESERVATIONS, all confirmed by
re-execution, all fixed in the same branch.** (1) The multi-instance marker, exact for `MUST`,
inverted a `SHANT` barrier (drawn as breaching only when _every_ member had offended; golden says
one act) and a `MAY` barrier with a continuation (the lapse timer routed _into_ the chair's duty to
publish a resolution that did not pass; `l4 run` says FULFILLED). Fixed: `completionCondition
nrOfCompletedInstances >= 1` on a prohibition, read off R-Q5; and the state graph now draws a
barrier-joined `MAY`'s lapse as a LEST arm to Fulfilled. (2) The fork's interrupting timer cancels
every instance, so a continuation a member had already spawned is never drawn — an obligation L4
says arose is absent and its breacher exonerated; new `P-FORK-CANCEL`. (3) `P-JOIN-DEADLINE` on a
fork reported a loss that is not one: `joinStateDue` is `Nothing` for `JoinUpon`, so the runtime
ignores it too; now Advisory, worded "dead in both". (4) The `<documentation>` asserted "drawn
faithfully" unconditionally; now gated on the modal. One golden per modal × join cell
(`jl4/examples/bpmn/modals.l4`) is what would have caught (1). **Two findings for P2 proper.**
First, on E: the graphs are now _isomorphic automata with different labels_, not different
automata — the join moved from dropped to carried as an edge annotation, which the exporter reads
structurally (sound) and which nothing reasoning over structure can see. The recommended second-half
rule, as an invariant: a barrier's continuation region is **1-safe**, a fork's **n-bounded** — draw
arc multiplicity on the HENCE edge (1 out of a barrier's join, symbolic _n_ out of a fork's) and give
the target place capacity 1 under a barrier, unbounded under a fork; the barrier's join place is a
third norm-plane placement beside `InEffect`/`Violated`, marked with _k_ of _n_ completions and not
enabled while _k < n_. Second, **a blocker on that second half: it is gated on a runtime change,
not only a drawing rule.** `barrierFinish` (`Machine.hs`) records that the residual does not carry
the join line — its members' HENCE/LEST slots hold the `` `the join` `` / `` `the join fails` ``
sentinels — so `markingOf` cannot produce the join place from what the runtime hands it without
sniffing user-visible strings. P2b's `DeonticStep` has to carry the join, or the residual has to.

#### What follows for P2

**This is P2's problem before it is P1's.** §5.1's division of labour gives P1 the shape and P2 the
position, and the barrier/fork difference is a difference in _what is waiting_ — which is
precisely the norm plane's subject matter. A two-plane picture that cannot distinguish "three
obligations outstanding, continuation blocked at a barrier" from "three obligations outstanding,
each with its own continuation already running" is not drawing the norm plane at all; it is
drawing the action plane twice.

Consequences, stated so they are not rediscovered:

- **R2 is answered by the language, not by P2.** The shipped `AllOf` is a fork with no join because
  the IR predates `Join`. It is no longer open whether L4 has a join — it has two, distinguished by
  trigger discipline (level vs edge). What is open is the drawing rule, which is §3.1's business
  and is now blocked on nothing.
- **`markingOf` (§4.2a) has to carry the join.** A barrier's continuation is a norm-plane place
  that is _marked but not enabled_ until the threshold is met — the exact thing a marked transition
  system is good at and a DFA is not, and, incidentally, the best argument in this document for
  §2.3's formalism over Flood & Goodenough's automaton. `JoinOnce`'s `Threshold` is already
  parameterised for the phase-3 count and measure forms (`SOME 2 OF … HAVE`,
  `sum OF amount AT LEAST rent`), so the marking function should be written against `Threshold`
  from the start rather than against the phase-1 barrier it currently has only one constructor for.
- **`DeonticStep` (§4.3) is under-specified as written.** It was designed before the join existed.
  A step that satisfies one arm of a barrier is not the same event as the step that satisfies the
  last arm and releases the continuation, and the type has no way to say which just happened.
  Whether that is a new field or a derived predicate over the marking is an implementation
  question; that it must be sayable is not. **This is the concrete edit P2b needs before it is
  built** — cheap now, a migration later.

  **TAKEN 2026-09-15, as a field, with one deliberate refusal.** `dsJoin :: Maybe JoinProgress`
  on the member's own step, `JoinProgress = MemberSatisfied {done, total} | ForkContinued {member,
total}`, filled from the key's `nkMember` at the routing sites (`tellRoutedStep`,
  `Machine.hs:375`). A "released" value was considered and **declined**: the last member's step
  cannot honestly say the continuation is released, because that is decided _after_ it by the
  `ONCE … WITHIN` check — `JoinExpired` is the other answer. So the release is the join's own
  step, `JoinReleased`, keyed by the join line's range, and a barrier's log reads `MemberSatisfied
1 2`, `MemberSatisfied 2 2`, then either `JoinReleased` or `JoinExpired`. The eighth fixture in
  `DeonticStepSpec.hs` is exactly the case that would have made a member-side "released" a lie:
  both arms satisfied, `JoinExpired ToLest 5` at clock 9. A fork has no join step; each member's
  routed step carries `ForkContinued`. The **sequencing** bullet below is discharged by the same
  change: `nkBearer` is the member's key, `nkSite` the shared `RAction` range, `nkActivation` the
  member's own entry (roll order), and `nkMember` says which family it belongs to.

- **Sequencing.** The B1 correlation key wants a per-member identity under an `EVERY`, not just a
  per-rule one, since the whole point of the cast is that there are _n_ outstanding obligations
  sharing one source range. B1 as §3.4 specifies it — an `RAction`'s `SrcRange` — is therefore
  **necessary but not sufficient**, and the missing half is the run-time cast member. R-T6 says the
  cast is only known at run time, which is why this rides the step log (P2b) rather than the static
  extraction.

**The smallest honest first step is not a picture.** Teach `extractDeonton` to bind `join` and
carry it on the graph, so the two process projections stop being byte-identical for programs that
differ. That is a small change to a type P1 depends on — the same class of edit as B1, with the
same golden-regeneration cost — and it unblocks the fidelity report saying the one thing a reader
currently cannot discover from the export.

---

## 5. What this deliberately does not do

### 5.1 The division of labour with P1

Two process pictures need one stated rule, or the programme has two answers to one question.

> **P1 emits a file; P2 renders a view.**

|              | **P1 — BPMN export (ships)**                 | **P2 — the LTS view**                           |
| ------------ | -------------------------------------------- | ----------------------------------------------- |
| the question | _what is the shape of this contract?_        | _where are we in it, and what can happen next?_ |
| the artefact | a `.bpmn` file                               | an interactive view; **no interchange format**  |
| the audience | the reader's own tool — Camunda Modeler (K4) | the reader, in our surface                      |
| the input    | the static `StateGraph`                      | the static graph **plus a trace**               |
| success      | it imports cleanly elsewhere                 | it agrees with the evaluator, event for event   |
| fidelity     | names what BPMN dropped (F1-F5, P-…)         | names what **we** dropped (§6)                  |

P2 does **not** replace P1, does not compete with it for the Reg CF exhibit (M3/M4 are P1's),
and does not need an export format. _"In our surface" is discharged by §4.8 — a CodeLens
above the rule, in both the web IDE and VS Code, opening a pane._ If P2 ever grows one it becomes a second interchange
target with a second faithfulness obligation, and that is a new decision.

One thing P1 shipping **does** change: B1 and B2 are edits to a type P1 now depends on, so P2's
preconditions are no longer free of P1 — they cost golden regeneration and a re-run of
`etc/validate-bpmn.mjs`. Cheap, but no longer zero. §7.1. _(Measured 2026-09-16: zero goldens
moved under either; the re-run was done on hand exports instead. §3.4.)_

### 5.2 It does not draw guards

The ladder DESIGN §25.5 seam is explicit and decided (2026-07-14): the ladder renders the
**guard** — _"reusable unchanged"_ (`DESIGN.md:1387`, and _"free, since it is the same machinery"_
at `:1479`) — and then hands off. The consequent renders as a **folded handle** that opens into
this view.

**P2 draws the consequent only.** A P2 that re-draws guards duplicates Track D, re-opens the F4
seam internally, and — since PROCESS-TRACK §6 forbids this track from depending on the ladder —
would have to build a second one. What P2 owes the seam is a **stated input contract**: which
obligation, at what valuation, under which rule version. It does not owe the handle, which is a
ladder-side feature. R4.

Note the consequence, now recorded as G9: not drawing guards is also what makes P2's structural
reachability an over-approximation. The two are the same decision.

### 5.3 Not an authoring notation

C-O Diagrams are the strongest existing version of the opposite architecture, where the diagram
is the source. Our thesis is that the language is the source and every picture is derived. P2 is
read-only over the L4 module. No editing, no round-trip.

### 5.4 Not a verification backend

§2.4. And specifically not a TAPAAL lowering, which remains desirable and is somebody else's
faithfulness obligation — and which is where §1.1b's sound reachability lives.

### 5.5 Not Deontic BPMN

§2.3, last row. The question will be asked; the answer is K4 plus F2 plus F3.

---

## 6. Fidelity — what **this** notation loses

Every exporter we ship names its losses. So does this viewer, in the same vocabulary — and it
uses the same type, `L4.Interchange.Fidelity` (shipped at `cfeaea5d`), so a combined report has
one shape.

| #       | Loss                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **G1**  | **Defeasibility and priority.** Overriding, `SUBJECT TO`, salience. LPPN draws suspension with inhibiting arcs — which is a _design choice about salience_, not a neutral drawing. `VERIFICATION-BACKEND-LOWERING-SPEC` §"The Crux: Defeasibility" (`:117-119`) already names a naive deontic encoding reporting conflicts that are encoding artifacts as _"the single fastest way to discredit the whole approach."_ This is P2's most serious loss.                                                                          |
| **G2**  | **Guard bodies — F4 persists.** The `PROVIDED` condition is still drawn elsewhere. Single-sourcing _mitigates_ it (both pictures come from one module, so the guard can be a live sub-view rather than a stale string) but does not close it. Do not claim Petri nets fixed F4; they did not.                                                                                                                                                                                                                                  |
| **G3**  | **Rule version — F5 persists.** No process notation has an as-of-date, ours included. **F5 is not a property of BPMN** and should be dropped from the motivating argument: a BPMN file exported from L4 and stamped is exactly as good on F5 as a P2 view derived and stamped. F5 motivates **derivation**, not notation, and it is a requirement on **both** exporters. See PROCESS-TRACK §5's closing line, which currently over-claims.                                                                                     |
| **G4**  | **The Anderson/Meyer reduction itself.** Reducing _ought-to-do_ to reachability of a bad state is contested — Hart's "being obliged" versus "having an obligation" (`paper/bounded-deontics/related-work.md:107`). Every violation-state picture inherits this, ours included. P2 draws the reduct and should say so.                                                                                                                                                                                                          |
| **G5**  | **Powers.** `paper/hohfeld-higher-order/section-powers-as-higher-order-deontics.tex`: `MUST` is a fact about a _fixed_ transition system; a power **changes** the system. A power cannot be an edge in the LTS it modifies. Symboleo gives powers their own lifecycle; whether we follow is R9.                                                                                                                                                                                                                                |
| **G6**  | **Dense time.** Deadlines are step counters on the contract clock, not clocks. Genuine real-time deadlines are lossy here, per `VERIFICATION-BACKEND-LOWERING-SPEC:65`. Timed-arc is the fix and it is out of scope.                                                                                                                                                                                                                                                                                                           |
| **G7**  | **Interchange.** There is no file to hand anyone. That is P1's job and P2 does not duplicate it.                                                                                                                                                                                                                                                                                                                                                                                                                               |
| **G8**  | **Bearer vs performer — F2 is only partly ours to fix.** `TransitionLabel` has one `labelParty` (`StateGraph.hs:127`), so today **our own IR** loses the distinction BPMN's lanes lose. The norm plane can hold bearer and performer separately, but only once the extractor carries both. That is P2 work, not a target-notation excuse.                                                                                                                                                                                      |
| **G9**  | **Reachability is an over-approximation — NEW, and it is the loss revision 1 hid.** A walk of the drawn graph ignores `PROVIDED` guards (`Machine.hs:1570-1577`), collapses action arguments (gap 2) and has no deadline arithmetic (gap 7). It is **sound for "no path reaches red"** and **unsound for "red is reachable"** — which is the litigator's question. Any UI affordance that reads as "this breach can happen" must be labelled as structural, or dropped. Sound reachability belongs to the verifier. §1.1b, R3. |
| **G10** | **Legibility bound — NEW.** Past roughly 40 states / 25 marked places the picture stops being a picture (§4.7). Degrading to a list is not a fallback embarrassment; it is §1.1a's rival winning on that input, and the tool should say so.                                                                                                                                                                                                                                                                                    |

**F1 and F3 are the two the argument rests on.** F1 because erasing the modal does not lose a
badge — it loses the **key that decodes the topology BPMN kept**: `HENCE` and `LEST` are
modal-polarised, and `SHANT` inverts them (`doc/reference/regulative/README.md:163`, _"Note that
SHANT flips the polarity: for prohibitions, the action happening is the failure case (LEST),
while the deadline passing without action is the success case (HENCE)"_). F3 because it is the
regulative twin of the ladder's own two-lamp verdict — _"N/A is a state, not a path"_
(`logic-not-flowcharts.md:657`) — and we have already convicted ourselves of it one formalism
over.

---

## 7. Dependencies and staging

### 7.1 Dependencies

- **P0 — discharged.** `FanKind` landed in `32718b0c` (PR #138) and is pinned by
  `jl4-core/test/StateGraphSpec.hs`. §7's sole stated dependency is already satisfied.
  _(Correction to carry back: PROCESS-TRACK §4 is stale — its quoted `StateGraph.hs:240-248`
  snippet no longer exists, and §2's "Today it has one renderer" is now false.)_
- **P1 — shipped.** `L4.Bpmn.{IR,Lower,Emit}`, `etc/validate-bpmn.mjs`, three fixtures with
  `.bpmn` and `.fidelity.txt` goldens, landed in `cfeaea5d` (PR #141) on 2026-07-26.
  **Revision 1 was internally contradictory here** — its header claimed P0-only, §7.1 said "P2
  does not need P1", and its own first deliverable depended on P1's output, which did not then
  exist. Both halves are now resolved by fact and by ruling:
  - **P2a needs P1**, and P1 is there. The experiment is unblocked today.
  - **P2's preconditions now cost P1 something.** B1 and B2 change `StateGraph`'s public type and
    its shape, which regenerates the BPMN goldens. That is a real, small, stated dependency in
    the other direction, and it did not exist when revision 1 claimed independence. (Measured
    2026-09-16: zero goldens moved under B1 or B2 — none of the 14 golden sources hands over by
    name; §3.4's B1 and B2 blocks. The dependency is real in principle and was zero in fact.)
- **Nothing in Track D, the ladder, `ts-shared/`, or `VizExpr`** — PROCESS-TRACK §6 holds.
- **Live mode only** depends on `STATEFUL-CONTRACT-DEPLOYMENT` §3.1, which is somebody else's
  blocker. §4.5.

### 7.2 Staging — two experiments, then a gate, then maybe a picture

| ID       | Work                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Depends on                                                   | Gates M4?      |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ | -------------- |
| **P2b**  | `tellDeonticStep` + the `DeonticStep` type of §4.3. ~6 call sites in `Machine.hs`. **No renderer.** Tested in Haskell alone against `contracts.golden`. **Recommended unconditionally.** **BUILT 2026-09-15** (`lts/p2-stack`, not yet in `unstable`): `L4.EvaluateLazy.DeonticStep`, `tellDeonticStep` optional and off by default (R5 answered), seventeen call sites, `DeonticStepSpec`; §4.3's BUILT block.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | —                                                            | no             |
| **P2c**  | The enabled set and the discharging/breaching partition, in the **replay** form (`STATEFUL` §6.5 endpoints 22/23/24), per §2.4. Plus `markingOf` (§4.2a) as a library function. **BUILT 2026-09-15** (`lts/p2-stack`): `L4.Lts.Marking` (`markingOf` against `Threshold`, with `Awaiting` for the join — the `markingOf` half of P2h's second half) and `L4.Lts.WhatIf` (the replay form, per candidate); §4.2a and §2.4 LANDED blocks.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | P2b                                                          | no             |
| **P2a′** | **The list baseline, and the primary gate.** Render §4.2a's marking + endpoints 17/19/20 as plain text — CLI first. Put it in front of readers against the same contract drawn by `stateGraphToDot` and P1. **BUILT 2026-09-15** (`lts/p2-stack`): `l4 lts FILE [--steps] [--json] [--contract NAME]`, goldens under `jl4/examples/lts/expected/`, page `doc/reference/regulative/lts-list.md`; §7.6. **The reader experiment itself has not been run** — the list exists, the gate is still open.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | P2c                                                          | no             |
| **P2a**  | **The picture baseline.** Point `bpmn-io/bpmn-js-token-simulation` (MIT) at P1's shipped output and write down, case by case, what it cannot say. **MEASURED 2026-09-15** (`lts/p2-stack`): harness `etc/bpmn-token-sim/`, report `P2A-TOKEN-SIM-BASELINE.md`, RESULT block below. Measured over the eight goldens that existed that afternoon; the six `modals-*` goldens `6daf1d9d` added later the same day are **unmeasured**.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | P1 (shipped)                                                 | no             |
| **P2f**  | **Unbundled.** `dom_s(J)` by Lengauer–Tarjan over `StateGraph`, answered as a **set of acts** — printable as a list or as an annotation on P1's BPMN. **No new picture required.** **BUILT 2026-09-15** (`lts/p2-stack`): `L4.StateGraph.Dominators`, `l4 state-graph --dominators [--all-states]`, `DominatorsSpec`; §1.1c LANDED block (iterated dominance equations, not Lengauer–Tarjan; same answer by definition). DOT annotation not built.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | P0 (shipped)                                                 | no             |
| **B1**   | Carry the correlation key (§3.4). Regenerates BPMN goldens.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | P1                                                           | no             |
| **B2**   | Close the loop (§3.4). Makes `P-CYCLE` reachable; see §4.7.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | B1                                                           | no             |
| **B3**   | Layout: Haskell ranks with a feedback-edge set, TS draws (§4.7).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | B2                                                           | no             |
| **P2g**  | **The entry point (§4.8).** A CodeLens above every `Decide` whose body is regulative, in **both** lens producers, opening the view in a pane in VS Code and in the web IDE. Independent of which renderer sits behind the pane — wire it to the shipped `stateGraphToDot` first, which is how P2a′/P2a get run where readers actually are. Four edits, not one; see the table in §4.8. **BUILT 2026-09-15** (`lts/p2-stack`): the lens in both producers and both hosts, `l4_state_graph_by_name`; the pane shows DOT source with Copy (no renderer in the tree); R13 answered — the lenses never stack; §4.8 LANDED block. Not yet clicked by a human in either host.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | shipped `StateGraph` (DOT), or P2d for the two-plane picture | no             |
| **P2h**  | **Carry the join (§4.9).** Teach `extractDeonton` to bind `Deonton.join` and put it on the graph, so a barrier and a fork stop producing byte-identical output; then the drawing rule, and `Threshold`-shaped `markingOf`. Answers R2 and closes the one export gap `EVERY-EACH-QUANTIFIER-SPEC` §2.5 says a reader cannot discover from the export. Same class and cost as B1 — it moves P1's goldens. **Do the first half before P2b**, which is specified against a pre-join `Deonton`. **First half LANDED 2026-09-15** (`fix/join-on-state-graph`): `extractDeonton` binds the join by positional pattern, `TransitionLabel.labelQuantifier` carries it (`Quantifier`/`JoinLabel`/`JoinLabelKind` — renamed from `JoinKind` 2026-09-16, which `DeonticStep` also exports), the DOT draws it on the edge, and BPMN lowers an `EVERY` to a parallel multi-instance task with `P-CAST`/`P-FORK`/`P-JOIN-DEADLINE`. Measured against the prediction here that it "moves P1's goldens": it moved **none** of the six — no golden source contained an `EVERY` — and added two (`tenancy-barrier`, `tenancy-fork`). Second half (the norm-plane drawing rule, `Threshold`-shaped `markingOf`) still open. **Second half, 2026-09-15:** `markingOf` against `Threshold` LANDED with P2c (§4.2a); the norm-plane drawing rule remains P2d's and is gated with it. | shipped `EVERY` (PRs #360/#370/#374)                         | **first half** |
| **P2d**  | The P2 IR and the **static** two-plane picture. No animation. **Gated: build only if §7.3's condition is met.**                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | P2c, B1-B3                                                   | no             |
| **P2e**  | The animator: scrubber, token, marking, enabled-set highlight. TypeScript, per K6.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | P2d                                                          | no             |

_Note, 2026-09-16 (not a row edit — the table is the integrator's): the P2f row's "DOT annotation not built" was made false the same day by `lts/b1-b2-loops` — **DOT annotation LANDED 2026-09-16** (`--dominators --dot`, §1.1c's Annotation LANDED block and its correction)._

**Ordering is now explicit**, which revision 1's table was not (it said "P2a first" in prose while
giving P2b no dependency): **P2h(first half) → P2b → P2c → P2a′, with P2a, P2f and P2g runnable
in parallel at any time.** P2h moves to the front because §4.9 shows P2b's type was designed
against a `Deonton` that had no join. P2b and P2c come first because P2a′ needs data to list, and because they are the two
deliverables whose value does not depend on the gate's outcome.

**What each experiment can and cannot falsify**, stated so neither is over-read:

| Experiment | Tests                                             | **Cannot** test                                                                              |
| ---------- | ------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **P2a′**   | position — the lead question, against a list      | reachability, dominance; and it cannot tell you whether a _better_ picture would have won    |
| **P2a**    | position, as an off-the-shelf animation over BPMN | reachability (a token simulator has no such query) and dominance (it computes no dominators) |

Revision 1 gave P2a alone the power to kill P2d/P2e/P2f on the strength of a token simulator that
has neither of the two graph-native queries. That was structurally incapable of the job. P2f is
now independent of the gate entirely; the gate is P2a′, which tests the question P2 actually
leads with.

> **RESULT — P2a, MEASURED 2026-09-15.** `bpmn-js-token-simulation` 0.40.0 over `bpmn-js` 18.28.0,
> driven headlessly by `etc/bpmn-token-sim/` over all eight goldens in `jl4/examples/bpmn/expected/`;
> report with per-fixture tables, screenshots and the simulator's own JSON in
> [P2A-TOKEN-SIM-BASELINE.md](./P2A-TOKEN-SIM-BASELINE.md). In five lines:
>
> 1. **A token does not know its modality.** The same token, play button and pad sit on a `MUST`, a
>    `MAY`, a `SHANT` and a `businessRuleTask`; on `offering` and both `regcf-*` prohibitions,
>    "continue" on the `SHANT` task **is** the breach, and its timer is the compliance exit — the
>    inverse of every `MUST` beside it, with no notational difference.
> 2. **The barrier and the fork animate identically.** `tenancy-barrier` and `tenancy-fork` give
>    the same scopes, triggers, history and end events (JSONs differ only in label text); the
>    multi-instance task is one token and one click, never `n`, so `ONCE ALL HAVE` waits for nothing
>    and `UPON EACH` fires once.
> 3. **No clock, no guards, no unreachability.** No timer fired on its own in 4.5 s; every boundary
>    that was offered was offered from the moment its host held a token, whatever its duration;
>    `conditionExpression`s were never read (the arm is a gateway setting, default first flow);
>    `regcf-advertising`'s _"unreachable: no WITHIN"_ boundary fired on request, to Fulfilled;
>    `regcf-reporting`'s `P-CYCLE` looped six times (twelve clicks) to the step limit.
> 4. **Breach does not end the process.** On `offering` the error end consumed its own token and the
>    siblings ran on to _"Process finished"_ with two Fulfilled and two Breach exits; `handover` has
>    no breach node at all, so the tenant's timeout ends in _"Fulfilled"_. `BREACH BY … BECAUSE …`
>    appears nowhere.
> 5. **What it does well:** four concurrent tokens in three lanes on `offering`'s `RAND`, and
>    `consultation`'s one drawn join animating as a barrier.
>
> The measured fact: the simulator's picture carries no modality, bearer, deadline, cardinality or
> breach attribution, and every one of those gaps is one P1's fidelity report already names, shown in
> motion. Whether a reader can nonetheless answer §7.3's question — _what do I owe, what discharges
> it, what breaches it_ — from that picture is **unmeasured**: §7.3 phrases both conjuncts in terms
> of readers, and the only reader here was a script clicking what the tool offered. **This block
> does not decide the gate.** Also unmeasured: the first conjunct (P2a′, no reader has been shown a
> list or the animation); what a human understands from the animation — the quantity §7.4's studies
> are about; and whether a differently drawn BPMN (a multi-instance subProcess for the fork, which
> `P-FORK` says the exporter does not emit) would animate better. Staging table above left for the
> integrator.
>
> _What review changed (2026-09-15, same day):_ point 3 said "every boundary was clickable at
> t = 0" — the data records `triggers` only at start, where exactly one boundary is offered
> (`out/offering.json`: `["Start_0","Task_0","Boundary_0"]`); "looped twelve times" was twelve
> clicks, six round trips; point 5 said "four lanes" — `offering.bpmn` has three; and the closing
> paragraph called §7.3's second conjunct "satisfied" when no reader was measured. Each is now
> stated as measured.

### 7.3 The gate

> **Build P2d/P2e only if P2a′ shows that readers cannot answer "what do I owe, what discharges
> it, what breaches it" from the list — and P2a shows the off-the-shelf simulator cannot either.**
> If either baseline suffices, stop. The back end (P2b/P2c) and the dominator answer (P2f) are
> already delivered by then, and they are the parts with independent value.

Both experiments together cost about three days. B1-B3 plus P2d plus P2e cost considerably more,
and §4.7 says the layout half is under-costed even now. Spending the three days first is the
whole of revision 2's staging argument.

### 7.4 The empirical warrant, corrected

Revision 1 attached two DOIs to this claim. **Both were wrong**, and each resolved to an
unrelated paper — `10.1016/j.im.2024.103943` is "Online impulsive buying in social commerce"
(Xu, Gong & Yan) and `10.1016/j.chbr.2025.100655` is "Deconstructing screen time" (Jespersen et
al.). In a document whose stated method is named provenance, that is the worst single defect the
review found. The correct references, verified via Crossref on 2026-07-27:

- Maslov & Poelmans, "Facilitating the comprehension of business process models for unexperienced
  modelers using token-based animations", _Information & Management_ **61**:103967, 2024.
  DOI `10.1016/j.im.2024.103967`.
- Maslov, Poelmans, Wautelet & Gailly, "Novice modelers' subjective comprehension and interaction
  with token-animated process models", _Journal of Computer Languages_ **84**:101350, 2025.
  DOI `10.1016/j.cola.2025.101350`. _(Not CHBR — the venue was wrong too.)_

**And the claim itself was an over-claim.** Revision 1 said token animation "measurably helps
inexperienced modellers comprehend process models". The follow-up study (119 students) reports
that animation **did not significantly improve comprehension scores directly**; it significantly
reduced **extraneous cognitive load**, which in turn predicted comprehension, with modelling
expertise reducing both intrinsic and extraneous load and improving comprehension directly.

So the honest version, which is weaker and still worth having:

> Token animation has a measured effect on _how hard a process model is to read_ for people who
> are not process modellers, mediated by cognitive load rather than showing up as a direct
> comprehension gain. That is a real warrant for the audience thesis — the man on the street, the
> SME founder — and it is **not** a warrant for expecting readers to get more answers right.

Which is, in turn, another reason the P2a′ gate exists: the literature does not promise that the
picture beats the list, and it is not evidence for our two-plane picture in particular.

### 7.5 M4

**Nothing here gates M4.** M4 is DMN + BPMN out with fidelity reports (D1, P1, S0) — of which P1
is now done. P2a merely _consumes_ P1's output; P2b adds an optional log to the evaluator and
should default off, mirroring `TracePolicy.hs:97-101 cliDefaultPolicy`. B1/B2 touch P1's goldens
and so must land **after** M4 ships or be scheduled with it deliberately. (Measured 2026-09-16:
zero goldens moved under B1 or B2, so this sequencing constraint is moot; §3.4.) P2 is M6 and
stays there.

### 7.6 P2a′ as built — LANDED 2026-09-15, on `lts/p2b-step-log` (merged into `lts/p2-stack` 2026-09-15, not yet in `unstable`)

**The command.** `l4 lts FILE [--steps] [--json] [--contract NAME]...`, registered in
`jl4/app/Main.hs` beside `state-graph`, implemented in `jl4/app/L4/Cli/Lts.hs` (`ltsCmd`, `:72`)
over a new library module `jl4-core/src/L4/Lts/List.hs`. The verb is named for the view it is
the first rendering of — §2.3's LTS — so that a picture, if §7.3 ever admits one, lands on the
same verb as a format flag and not as a second command a reader has to know to look for.
`status`/`position` were considered and declined: `STATEFUL-CONTRACT-DEPLOYMENT` already uses
those words for the deployed actor's persisted state, which this is not.

**What it renders, and from where.** Nothing new is computed. `reportOf` (`List.hs:130`;
`reportFrom`, `:135`, is the pure half, so a test can hand it an outcome) is `enabledSet` (P2c)
plus a reading of the result: the marking is `posMarking` (§4.2a), the five sections are the
`discharging`/`breaching`/`advancing`/`passedOver`/`untried` partition (endpoints 19/20 and the
rest of 18), the next deadline (endpoint 17) is the least **confirmed** `TickPast` deadline (see
the review block below), and the `--steps` log is `posSteps` (P2b). Two things the list adds on
top of P2c's verdicts, both read from the machine's own steps rather than decided here:

- **A fifth section, "what the contract would pass over"** (`passOverWords`, `List.hs:278`,
  wording a `PassedOver` verdict). The candidate set is read off the residual before the guard is
  asked, so an act whose `PROVIDED` comes out false is a candidate, and the replay reports it as
  `Advancing` to a marking that is the position's own. Listing that under "moves things along"
  would be a lie. Measured: `PARTY B MUST payment EXACTLY 5 PROVIDED FALSE WITHIN 3` at its
  outset lists "B does payment OF 5 now (at 0) — its condition (PROVIDED) does not hold" and no
  "move things along" section (`jl4-core/test/LtsListSpec.hs`, case 1). This is G9 (§1.1b)
  showing up in the built thing: the shapes are an over-approximation of what the contract takes,
  and the replay is where the over-approximation is corrected, one candidate at a time. **As
  first built the classification lived in the renderer and took the first pass-over's reason in
  the machine's order; review 2026-09-15 moved it into the verdict (`confirmAct`, §2.4's P2c
  block) and made the reason the candidate's own obligation's.**
- **An unforced `WITHIN` is dated through the confirmed tick.** A fresh obligation's residual
  still holds its `WITHIN` expression, so the marking alone can say only "due within 7 from
  now". The tick candidate for the same obligation computed the absolute deadline
  (`deadlineOf`) and the machine confirmed it (`confirmTick`: the tick revealed an expiry), so
  the "Owed now" line reads "due by 9 (7 from now)" — from `rpDeadlines`, populated only from
  ticks whose verdict is not `Untried`. An obligation whose tick was refused stays "due within".
  **The "Next deadline" line is held to the same rule** (review 2026-09-15: as first built it was
  the least of ALL `TickPast` deadlines, refused ones included — the one number §2.4 says not to
  print, printed on the one line that names a date). `rpNext` (`List.hs:97`) is now the least
  confirmed tick, and `rpUnknown` (`:102`) names every live obligation whose deadline the list
  could not confirm — a refused tick, or a `NoTick` with a `WITHIN` — on the same line: "Next
  deadline: 3 (B: payment OF 5)"; with an unknown, "… — not counting S: delivery, whose deadline
  is not known here"; with nothing confirmed, "Next deadline: not known here — B: payment OF 5
  has a deadline this list could not work out". Measured: the guarded fixture's tick forced to
  land ON the deadline (as `LtsWhatIfSpec` case 8 forces it) is `Untried`, `rpNext` is `Nothing`,
  the line reads "not known here", and the owed line falls back to "due within 3 from now"
  (`LtsListSpec.hs`, case 5). `NoDeadline` obligations are not "unknown": they have no deadline.
- **The act is written as it would be done, when it can be.** "Owed now" and "Next deadline"
  print the reified act of the `ActBy` candidate for the same `LiveNorm` (`rpActions`,
  `List.hs:112`; `actionText`, `:322`) — `payment OF 2`, the `EXACTLY n` read through the heap —
  rather than the pattern `payment (EXACTLY n)`, which named a variable the reader could not
  resolve without the discharge line three lines down (review 2026-09-15). A pattern that binds
  (`Pay … amount`) has no reified act and prints as the pattern; the "then:" markings under
  "move things along" have no candidates and always print the pattern. This moved
  `contracts.txt:83,91` and `tenancy.txt:5-7,27` and the `action` fields of the JSON goldens;
  nothing else in the six goldens moved.

**`--contract NAME`** (`freshTrace`, `List.hs:190`) appends a `#TRACE NAME AT 0 WITH` — no
events — to the checked module for a top-level nullary rule of that name, so a file with no
trace (`jl4/examples/bpmn/tenancy.l4`, which is the P2h pair with the traces left out) can be
listed at its outset. It is exactly the authored empty directive: `LtsListSpec.hs` case 3 pins
that the two renderings are byte-identical up to the line number. A rule with inputs, or an
unknown name, is refused with a message, not an empty list.

**The exact output for one contract** — `jl4/examples/ok/contracts.l4`, first `#TRACE`
(`aContract`, three events, the last a `WAIT UNTIL 10`), as `l4 lts jl4/examples/ok/contracts.l4
--steps` prints it and as `jl4/examples/lts/expected/contracts.txt:1-22` pins it:

```
aContract — after 3 events, the clock stands at 10 (the #TRACE on line 23)
    PARTY S DOES delivery AT 2
    PARTY B DOES payment OF 21 AT 4
    `WAIT UNTIL` OF 10
  Standing: in progress.

  Owed now:
    - B MUST return — due by 14 (4 from now)

  What would put someone in breach:
    - nothing happens by 14 (the clock reaches 15) → B is in breach: MUST return was due by 14; the clock reached 15 without it

  What could not be tried:
    - B does return — the action binds `return`, which the what-if cannot choose

  Next deadline: 14 (B: return)

  Steps, in order:
    at 2: S does delivery at 2; S MUST — done; on to what follows
    at 4: B does payment OF … at 4; B MUST — done; on to what follows
    at 10: the clock runs to 10 with nothing happening; B MUST — not this party's event; passed over
    at 10: B MUST — no more events; still waiting
```

(`return` is a variable pattern in that corpus file — there is no `return` constructor — which
is why the act cannot be tried; the list says so rather than dropping it.)

**Vocabulary.** The default output names no constructor, and `jl4/tests/LtsList.hs`
(`constructorNames`, `:111`) asserts it over all three corpus outputs: `Matched ToHence` is "done;
on to what follows", `Expired _ d ToLest` is "deadline d passed without the act; on to the
fallback", `Awaiting` is "the next step is held back until all have acted: n of m have",
`MemberSatisfied n m` is "(n of m have acted; the shared next step waits for the rest)",
`ForkContinued i m` is "(member i of m: their own next step begins)". The machine's `WAIT
UNTIL` sentinels — the builtins `neverMatchesParty`/`neverMatchesAct`, whose surface names are
`NEVERMATCHESPARTY`/`NEVERMATCHESACT` because the builtin environment upper-cases every builtin
not given a `rename` (`jl4-core/src/L4/TypeCheck/Environment/TH.hs:66`, `mkBuiltin`; the two are
listed without one at `Environment.hs:101`) — are rendered as "the clock runs to t with nothing
happening" and never printed. (The first write-up credited the upper-casing to "the ledger key";
`partyKeyWHNF`, `Machine.hs:2683`, does no casing. Corrected on review 2026-09-15.)

**Measured** (as first landed; the review block below re-measures what it changed). `cabal test
jl4-test -m "lts list"`: 12 examples, 0 failures — six goldens
(text and JSON, with steps, for `ok/contracts.l4`, `doc/reference/regulative/every-run-example.l4`
and `bpmn/tenancy.l4` at its outset), the no-constructor property over the three, and the
barrier/fork wording assertions: the tenancy barrier says "one of 3 who must all act before the
next step" and "held back … 0 of 3 have", and one act takes it to "1 of 3"; the fork says "one of
3, each with a next step of their own" and has no "held back" line; the barrier's tick breaches
naming nobody (`LEST BREACH`), the fork's names Alice (`LEST BREACH BY t`). `cabal test
jl4-core-test -m P2a`: 3 examples, 0 failures. `doc/test-docs.sh` with the worktree's `l4` first on
`PATH`: 1499 links, 101 `.l4` files, 251 linked, 0 orphans. Wall clock, warm binary:
`contracts.l4` (13 traces) 0.03 s, `every-run-example.l4` (4 traces, imports prelude) 0.26 s,
`tenancy.l4` at its outset 0.02 s. The CLI's text output for all three is byte-identical to the
goldens the test suite writes through the library (`diff`, 2026-09-15), so the verb and the test
render the same thing.

**What the list can answer** (§1.1a's three clauses, and 17): what is owed, by whom, by when;
which listed act discharges; which listed act or tick breaches; the next deadline. And, from the
steps, what the contract did with each event so far.

**What it cannot, stated on the page** (`doc/reference/regulative/lts-list.md`, "Limits"):

- **The enabled set is an over-approximation, and also incomplete.** The shapes tried are the
  live obligations' own `(party, action)` at the current clock plus one tick per distinct
  deadline. A listed verdict is the machine's and exact; a shape the guard rejects is listed
  and then reported as passed over; an event nobody's obligation names — a wrong-amount
  payment, a third party's act — is not listed at all, though it would advance the clock. "No
  listed act breaches" is sound; "nothing else could happen" is not something the list says.
- **Some shapes cannot be tried** (a binding pattern, an unevaluated non-literal `WITHIN`) and
  are listed with the reason. The reason text is P2c's and still says "binds".
- **Replay is per candidate**, so the cost is _k + d_ full runs per trace (§2.4); measured
  above on small casts, and stated on the page as proportional to the live obligations.
- **Nothing about where in the contract you are, or what happens after** the one step "move
  things along" shows (§1.1a).
- **The step log's party keys are partly-evaluated layouts — RESOLVED 2026-09-16 for parties.**
  `nkBearer` is `partyKeyWHNF`: for a constructor party with unforced fields that is
  `Tenant OF &229@file.l4`, a heap reference, and as first built the renderer elided it to `…`
  and left the member ordinal to tell the members apart. The fix was as predicted here: record
  the bearer at the match, where the machine has forced the party, rather than at arming —
  `nkBearerName`, `ekPartyName`, `bsBlameName`, peeked and never forced; see the LANDED
  2026-09-16 block in §4.3. `--steps` now reads `Tenant OF "Bob" does Sign OF … at 2; Tenant OF
"Bob" MUST (member 2 of 3)`. What remains elided is the **act** (`Sign OF …`) and a party
  whose fields no comparison has forced _all_ of: a `still waiting` at the outset, and — measured
  2026-09-16, §4.3 — a party with two or more fields whose _earlier_ field differed from the
  actor's, since the equality stops there (its `not this party's event` step and the `Waiting`
  after it print `Tenant OF …, …`). One-field parties, the whole corpus, never hit the second
  case. The page says which.

**REVIEWED 2026-09-15 — what two read-only reviews changed, on the same branch.** Ten findings;
eight acted on, one rejected, one moot. (1) **Next deadline from refused ticks** — fixed as above
(`rpNext` confirmed-only, `rpUnknown` named). (2) **Pass-over reason from the wrong norm** under
`RAND`/`ROR` — fixed in `confirmAct`, §2.4 (by site; under an `EVERY`, by a specificity rank
until 2026-09-16, and by bearer since — §4.3's LANDED 2026-09-16 block). (3) **"the ledger key upper-cases"** — a mechanism
misattributed; corrected at both sites (`List.hs:379`, above). (4) **`at —` has three causes, not
two** — the explicit `BREACH` (`Machine.hs:1235`, `every-run-example.txt:32,75`) added to the
page and to `DeonticStep.hs`'s header. (5) **"in the order it happened"** over-described the
step log — the page now says the order is the contract's (member by member, branch by branch) and
that `at t:` is the obligation's clock, not the event's. (6) **`advancing` disagreed with the
list** — fixed by the verdict move, §2.4. (7) **Owed line printed `payment (EXACTLY n)`** — fixed
as above (`rpActions`). (8) **`l4-cli.md`'s closing list and help listing omitted `lts`** — both
refreshed from the worktree binary. (9) **`Joined _ _ -> False` contradicted the docstring's "or
joined"** — the docstring was wrong, the arm is deliberate (an `ROR`'s "still open" is the
pass-over case); `confirmAct`'s comment now says so, and a reason-less outcome is `NoTaker`, not
a silent advance. (10) **`SrcPos (..)`/`SrcRange (..)` a plausible unused-import hazard** —
rejected: the build is `-Wall -Werror` and passes; under `NoFieldSelectors` the `(..)` is what
brings the `start`/`line` fields into scope for `HasField`, so the import is load-bearing, and a
comment now says so (`List.hs:76`). Re-measured after the fixes: `cabal test jl4-core-test
--test-options='-m P2a -m P2c'` 18 examples, 0 failures (5 list, 13 what-if; cases 4 and 5 are
new); `JL4_LIBRARY_PATH=$PWD/jl4-core/libraries cabal test jl4-test --test-options='-m "lts
list"'` 12 examples, 0 failures after blessing the six goldens, whose diff was exactly the
reified `action` texts and one new always-present JSON key, `deadlineNotKnown`;
`doc/test-docs.sh` and the full `jl4-test` as recorded in the commit message.

**REVIEWED 2026-09-16 — a third review, of the JSON and the join's own steps.** Seven findings;
six acted on, one rejected. (1) **`--json` used prose as discriminators** — `"what": "passed
over: not this party"`, `"kind": "held back"`, two keys with spaces (`"shared next step":
"waits"`), and `TickPast`/`NoTick` both `"kind": "tick"` — on a shape the page advertises "for a
program to read", and about to be goldened on `unstable`. Every discriminator is now a camelCase
token (`heldBack`, `notStarted`, `inBreach`, `partyMismatch`, `joinReleased`, `noTick`, join
`barrier`/`fork`, scrutiny `witnessedOnly`, …), `passedOver[]` carries a `reason` token beside
its `why` sentence, every step event carries `kind: act|clock`, and a top-level `format: 1` is
the shape's version; the page's `--json` section now lists the tokens by key and states the
`Rational`→double rounding. Three `.json` goldens re-blessed; the diff was exactly the tokens.
(2) **The pin on `doc/reference/regulative/every-run-example.l4` is dark in CI** — **rejected**:
`pr-checks.yml`'s Haskell job runs on `needs.changes.outputs.docs == 'true'` and the `docs`
filter is `doc/**`, so a docs-only edit to that file runs `cabal test all`; the pin under `doc/`
is _better_ guarded than the two under `jl4/examples/`, which match no filter (CLAUDE.md §3.1).
(3) **The join's own steps read `(party not yet known) MUST —`** — `renderStep` now prints
`the group —` for the four join outcomes; `every-run-example.txt:15,31` and the page's pasted
block re-blessed. (4) **`at —` has four causes, not three** — the barrier-without-`LEST` steps;
fixed as recorded in the P2b block above (the `DeadlineMissed` stamp is used; `JoinStalled` and
an explicit-`BREACH` member remain unclocked), and all three texts now agree on four. (5)
**`JoinKind` exported twice** — `L4.StateGraph`'s is now `JoinLabelKind`; the constructors
`Barrier`/`Fork` still collide, so a module drawing the norm plane over the graph (P2d) imports
one of them qualified. `DMustNot` is spelled `SHANT` by all three P2 renderers (it was `MUST
NOT` in `l4 lts` alone; the lexer token and the state-graph goldens say `SHANT`). (6) **A
committed evidence file carried an absolute path** — `run.mjs` makes `npm ls`'s heading
repo-relative; `run-meta.json` hand-edited to the same string. (7) **`l4 state-graph
--all-states` without `--dominators` printed DOT and exited 0** — refused with `requires
--dominators`, one `l4-cli-test` case. Not done: deriving `Marking.Blame` from `BreachSummary`
(a refactor, not a defect).

**Not run, and not claimed.** §7.3's gate is a **reader** experiment — put this list in front of
readers against the same contract drawn by `stateGraphToDot` and P1's BPMN, and see whether they
can answer the three questions from the list. That cannot be run from a build session, and it
has not been. This section records that the list exists and what it says; it records **no
verdict** on whether the picture beats it, and nothing below P2d should be read as unblocked by
it.

---

## 8. Open rulings

In the style of the other track specs: questions this document could not settle, recorded
rather than assumed benign. R11 and R12 are new in revision 2; R13 was added on 2026-09-14 with §4.8 and answered on 2026-09-15.

| #       | Ruling needed                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **R1**  | **Does `labelModal` move off `TransitionLabel`, or coexist with the norm plane?** §2.3 argues it should move; three published formalisms put deontic status on states or places, and our IR is the odd one out. Revision 1 deferred this because "P1 is mid-flight"; **P1 has now shipped, so that reason has expired** and the question is live. It remains a P0-scale change if taken.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| **R2**  | **Is `AllOf` a fork, or a fork with a join?** The shipped IR makes it a **fork with no join**: branches fan out and converge on a **shared** `Fulfilled` sink (`getTerminalState`, `:204-209`) that nothing waits at. `EVERY-EACH-QUANTIFIER-SPEC` §3.1 commits `EVERY` to **barrier semantics**, an AND-join firing HENCE once. The evaluator has a real join (`Machine.hs:1635-1707`, with blame assignment and the CSL tie-break). So the IR is the outlier. P1 reached the same place independently and reports it as `P-NOJOIN`. **UPDATED 2026-09-14 — the mitigation has expired.** Revision 2 wrote _"mitigating: `EVERY`/`EACH` are **unimplemented**"_; true when written, false now. The front end merged as PR #360 (`734b8015`, 2026-09-07), evaluation as PR #370 (`6247ba69`, 2026-09-08), `EVERY Cast v IN xs` as PR #374 (`28c48e3f`, same day). The join is **first-class in the AST**: `Deonton.join :: Maybe (Join n)` (`Syntax.hs:422-426`), with `JoinOnce` (`ONCE …`, level-triggered — the barrier) and `JoinUpon` (`UPON EACH`, edge-triggered — the fork) at `Syntax.hs:491-497`; the type checker makes it **mandatory** under an `EVERY` carrying `HENCE`/`LEST`, and an error under a `PARTY`. R2 is therefore no longer a question about a hypothetical: the language now draws the distinction and P2's input throws it away. §4.9. **LANDED 2026-09-15:** P2's input no longer throws it away — `labelQuantifier` carries `Barrier`/`Fork` structurally (P2h first half, §4.9). What remains of R2 is the drawing rule for the norm plane.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| **R3**  | **Under what condition does §2.4 re-open?** P2 declines a Petri-net _semantics_. If a TAPAAL lowering is later built, does P2 re-base onto it (gaining a checkable picture and **sound reachability**, inheriting the faithfulness obligation and the cross-validation harness) or stay a rendering of the evaluator? G9 raises the stakes: today P2 has no sound answer to the litigator's question at all. Deciding now is premature; deciding never is how two notions of "obligation" get shipped.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| **R4**  | **What crosses the §25.5 seam?** The handle is ladder-side, and PROCESS-TRACK §6 forbids P2 from depending on the ladder — so P2 can only define the state it _accepts_: obligation identity, valuation, rule version, and what else? Someone has to own the interface, and neither track may unilaterally.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| **R5**  | **Is the deontic step log optional or non-optional?** `traceEval` is optional and off by default; `tellEventRouted` is deliberately non-optional. Optional keeps the evaluator's hot path untouched and keeps P2b off M4's critical path. Non-optional means the residual can always explain itself, which is what an audit-grade tool-calling story wants. **ANSWERED 2026-09-15: OPTIONAL, off by default**, mirroring `cliDefaultPolicy` (`jl4-core/src/L4/TracePolicy.hs:97-101`), because §7.5 requires the evaluator's hot path untouched for M4 and P2b is built (on `lts/p2b-step-log`, merged into `lts/p2-stack` 2026-09-15, not yet in `unstable`) as `EvalState.deonticLog :: Maybe DeonticLog` with every call site behind that `Maybe` (`Machine.hs:286,359`). What non-optional would have bought — a residual that always explains itself — is available to any caller through `execEvalModuleWithDeonticLog` at the cost of asking; the audit-grade story can turn it on per request the way `#EVALTRACE` turns the trace on.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| **R6**  | **How is a re-offered event drawn?** §4.4. `dsScrutiny` records the distinction; it does not decide the rendering. One frame with a "witnessed" mark, or two frames with the second marked "re-offered"? Getting this wrong makes the animation lie about how many things happened.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| **R7**  | **Was `logic-not-flowcharts.md`'s state-transitions row intended as unranked?** It reads as unranked and PROCESS-TRACK §1 reads it that way, but it was written before P2 was contemplated, so it may simply never have been asked the question. **Ask Meng** rather than infer; §1.2's whole framing depends on it.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| **R8**  | **Verify Lomuscio & Sergot before print.** The green/red state-partition characterisation in §2.2 is from secondary sources; the primary PDF would not extract. It carries architectural weight (per-party colouring is the F2 shape). Symboleo's exact lifecycle state names are likewise search-verified rather than read — there is probably an `Expired`/`Terminated` and a `Suspended`→`Resumed` pair we have not recorded. §7.4's citation failure is the reason this caveat is now load-bearing rather than decorative.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| **R9**  | **Does P2 draw powers, or refuse?** G5 says a power changes the transition system, so it cannot be an edge in it. Symboleo gives powers their own lifecycle, which is one answer. Refusing and drawing the boundary is another, and is consistent with §25.5's own precedent of drawing the seam rather than pretending.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| **R10** | **Does P2f belong here or in the bounded-deontics work?** Sharpened by revision 2's unbundling: P2f no longer needs anything of P2's except the graph P0 already ships, so the case for it living here is weaker than it was. The query is that paper's contribution; the graph is `StateGraph`'s; the renderer may be P1's BPMN or a list. **Observation 2026-09-15 (still OPEN):** P2f was built on `lts/p2f-dominators` as a function over `StateGraph` (`L4.StateGraph.Dominators`) with **no dependency on the rest of P2** — not on the step log, the marking or the picture (its reader-facing wording of an `EVERY` act does read P2h-first-half's `labelQuantifier`, so it is stacked on that branch) — and it needed one thing of the graph the paper's definition does not mention: the `RAND` and `ROR` joins the IR lacks, supplied inside the module as `fulfilmentView` and `breachView`. That is evidence for the split the ruling proposes — the graph (and its join) is `StateGraph`'s, the query is the paper's — and the paper's §7 sentence _"the dominator query … designed and not yet built"_ is now false and should be updated when it is next touched.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| **R11** | **NEW. Does `STATEFUL` §6.4 need correcting?** §2.4 rules that P2 uses the replay endpoints (22/23/24) rather than 18/19/20, because "would lead to `FULFILLED`" cannot be answered by a pure walk without reimplementing modal routing. That is a finding **about `STATEFUL`'s own spec**, whose §6.4 promises exactly that pure walk with "microsecond responses". Either that spec should record the faithfulness obligation, or 19/20 should be re-specified as replay, or the pure walk should be kept behind a cross-validation test. Not P2's call alone. **OBSERVED 2026-09-15, not decided:** P2c's replay form (§2.4 block) measured 83–313 µs per candidate, warm, on the corpus's barrier and `contracts.l4` traces — inside the "microsecond responses" §6.4 promised for the pure walk, at trace lengths of one to three events. The replay's cost is linear in the persisted history (every prior event is re-scrutinised per candidate), so the promise is met today by the form §2.4 prefers and would stop being met at some history length nobody has measured. What §6.4 needs is therefore not a faster form but a number: the history length at which replay exceeds its budget, which is when a pure walk earns its faithfulness obligation. Still not P2's call alone.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| **R12** | **NEW. Is `Lapsed` the right name, and is it Symboleo's?** §4.2a needs a lifecycle state for "this `ROr` alternative is definitively lost but the compound is not violated". Symboleo has `terminated` and possibly `expired`; whether either covers this, or whether we are coining, is unverified and folded into R8's reading task.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| **R13** | **ANSWERED 2026-09-15, see §4.8 LANDED: no, never — by measurement and by construction.** Measured with `cabal repl jl4-core-test --repl-no-load` from `jl4-core/`, loading each file with `checkWithImports emptyVFS`, taking `map (.sgName) (extractStateGraphs m)` against `map (.vdName) (findAllVisualizableDecides uri m subst)` with the ladder's backticks stripped (the two spell names differently — the first run compared unstripped names and its 0 was worthless; the number below is the corrected run): `regcf.l4`: 109 top-level `Decide`s, 3 state graphs (`advertising restriction`, `ongoing reporting obligation`, `resale restriction`), 43 ladder-visualisable, **0 in both**; `ok/contracts.l4`: 8 / 7 / 0 / **0**; `every-run-example.l4`: 7 / 2 / 0 / **0**. So 0 of 12 regulative rules pass `canVisualize`. It could not be otherwise: `Ladder.translateDecide` (`jl4-core/src/L4/Viz/Ladder.hs:304-305`) throws `InvalidDecideMustHaveBoolRetType` unless the body is `BOOLEAN`, and a regulative body — including an `IF` whose arms are regulative — is `DEONTIC`. Consequences taken: the lens is titled "Show state graph" beside "Show decision graph", anchored at the same `Decide` start, and no title needs to disambiguate a shared line. Pinned by `jl4-lsp/test/StateGraphLensSpec.hs` and `jl4-core/test/ApiStateGraphLensSpec.hs`. _Original question (2026-09-14):_ Do the ladder lens and the deontic lens ever stack on the same line? §4.8 asks for a lens above every regulative `Decide`; the ladder already puts one above every `Decide` that `canVisualize` accepts. Whether those two sets are disjoint is **unmeasured** — nobody has run `Ladder.doVisualize` against a regulative body to see whether it succeeds. If they overlap, two lenses share one anchor position and the titles have to distinguish them ("Show decision graph" is already taken). Five minutes against `jl4/examples/legal/regcf/regcf.l4` settles it, and it should be settled before the lens is designed rather than after. |

---

## 9. Two today-bugs found while scoping — filed as smucclaw/l4-ide#927, both now FIXED

Neither was P2 work; both affected `l4 state-graph` output as it shipped. Line numbers were
verified at `cfeaea5d` and have since moved.

1. **`SHANT` + explicit `LEST` is labelled `"timeout"`, which is exactly inverted.**
   `StateGraph.hs:446-470`: all four `Just lestExpr` branches build
   `TransitionLabel Nothing Nothing "timeout" Nothing Nothing` (`:451`, `:456`, `:462`, `:468`)
   regardless of `action.modal`. For `DMustNot` the `LEST` fires when the action **is taken**, not
   on timeout (`doc/reference/regulative/README.md:163`). The no-`LEST` default path gets it right
   (`"violation"`, `:484`); the explicit-`LEST` path does not. Symmetrically, the `HENCE` edge for
   a `SHANT` carries the full action text (`:399-405`) but fires on the action's _absence_.
   **F1 is not only BPMN's problem — it is already mis-drawn in our own GraphViz output.**

   **Update:** P1 hit this and **compensated downstream rather than fixing the source**
   (`55a0fe7a`; `Lower.hs:927-943` documents the workaround in full). So the defect is now
   load-bearing in one consumer and papered over in another, which is the worst of both — a
   second consumer would have to reinvent the same patch. Fixing it in `StateGraph` and dropping
   P1's compensation is the right sequence, and it is a natural companion to B1.

   **Resolved.** `L4.StateGraph.lestArmWording` now derives the caption from the modal _and_ the
   deadline, and the `LEST` edge carries `labelModal` so a consumer holding only that edge can
   tell the arms apart. `SHANT` + explicit `LEST` reads `violation`; `MAY` + `WITHIN` reads
   `lapses`. Asserted in `jl4-core/test/StateGraphSpec.hs`, "LEST edge captions", and — for the
   BPMN side, which the goldens do **not** pin — in `jl4/tests/BpmnExport.hs`, "the LEST caption
   where BPMN actually consumes it".

   **The no-`WITHIN` row went one step further than the issue asked.** Naming it `timeout`
   asserts a deadline the rule never set; the first patch changed it to `not performed`, which
   asserts a transition the runtime never makes. Measured — `PARTY Alice MUST pay LEST (…)` with
   no `WITHIN`, run to ``(`WAIT UNTIL` 1000)`` — the obligation stays outstanding as a residual
   and the `LEST` arm is never taken, because `Contract4` skips the timing step and `Contract5`,
   the only frame that consults `lest` on expiry, never runs. Same for `MAY` and `DO`; `SHANT` is
   the exception because its trigger is the act. So the caption is `unreachable: no WITHIN`, and
   `L4.Bpmn.Lower` uses the same word on the boundary event it draws for that arm.

   **But the second half of the prescription above is wrong, and was wrong when written.**
   Dropping P1's compensation _moves the BPMN goldens_: deleting the `DMustNot` clause of
   `Lower.triggerName` renames `offering.bpmn`'s two prohibition boundaries from
   `"after P30D, not performed"` / `"after P365D, not performed"` to bare `"after P30D"` /
   `"after P365D"`, and the untimed one to `"violation"`. It is not a compensation for a bad
   label. `raceArms` puts a prohibition's boundary event on the **HENCE** arm while it is
   _constructed from_ the LEST edge, so that node names an event the state graph gives no caption
   to at all; a correct LEST caption is still the wrong words for it. The right characterisation
   is the ordinary one: `StateGraph` owns what an edge _means_, `Lower` owns what a BPMN node is
   _called_, and the general path of `triggerName` does now take its words from `StateGraph`.

   That split had a hole in it, found by an adversarial pass and fixed here: `boundaryTrigger`'s
   `fallbackCondition` was **not** guarded the way `triggerName` was, so on a `SHANT` with no
   `WITHIN` one element carried `name="the act is not performed"` over
   `<condition>violation</condition>` — the two halves of a single node asserting opposite arms.
   Both halves now read `unreachable: no WITHIN`, which is true of that node in a way neither
   previous word was.

2. **`MAY` and `MUST` without `HENCE` produce literally the same edge.** `:435-442` is a `case`
   with two branches and identical bodies. A permission exercised and an obligation discharged
   are one arrow. Arguably correct-by-accident given the defaults table, but it should be one
   branch with a comment, or two branches that differ.

   **Resolved: collapsed to one branch.** Every modal defaults `HENCE` to `FULFILLED`, so there
   was nothing to distinguish. The seam a reader will come looking for — `SHANT`'s HENCE edge is
   taken by the deadline _expiring_, so its caption reads backwards — deliberately stays
   unopened, because that caption is the obligation restated and is the record `Lower` builds its
   task name and lane from. A comment at the site says so.

---

## 10. References

**Ours** — `doc/concepts/language-design/logic-not-flowcharts.md`;
`doc/reference/regulative/README.md`; `jl4/examples/bpmn/README.md`;
`specs/todo/ladder-diagrams-2026/DESIGN.md` §25;
`specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md`; `specs/todo/STATEFUL-CONTRACT-DEPLOYMENT.md`;
`specs/done/DEONTIC-TRACE-API-SPEC.md`; `specs/proposals/VERIFICATION-BACKEND-LOWERING-SPEC.md`;
`paper/bounded-deontics/`; `paper/hohfeld-higher-order/`.

**Theirs.** Anderson, "A reduction of deontic logic to alethic modal logic", _Mind_ 67(265), 1958.
Meyer, "A different approach to deontic logic", _NDJFL_ 29(1), 1988. Flood & Goodenough,
"Contract as automaton", _AI & Law_ 30:391-416, 2021 (`StateGraph.hs`'s stated lineage; an
explicit DFA over an event alphabet, with a completeness-relative-to-alphabet check we do not
yet do). Sileno, Boer & van Engers, LPPN, AICOL/MIREL 2018,
DOI `10.1007/978-3-030-00178-0_6`. Azzopardi, Pace, Schapachnik & Schneider, "Contract
automata", _AI & Law_ 24(3), 2016, DOI `10.1007/s10506-016-9185-2`; Azzopardi & Pace, arXiv
`2410.12585`, 2024. Sharifi et al., Symboleo, RE 2020; _SoSyM_ 2022,
DOI `10.1007/s10270-022-01053-6`. Lomuscio & Sergot, "Deontic interpreted systems", _Studia
Logica_ 2003 (**unverified**, R8). Natschläger, Deontic BPMN, DEXA 2011; Natschläger, Kossak &
Schewe, _SoSyM_ 2015, DOI `10.1007/s10270-013-0329-5`; Kossak & Illibauer, "Deontic process
diagrams", 2016. Martínez, Cambronero, Díaz & Schneider, C-O Diagrams, TSE 2013. Pesic & van der
Aalst, DECLARE; Di Ciccio et al., "Semantical vacuity detection in declarative process mining",
BPM 2016. Dijkman, Dumas & Ouyang, "Semantics and analysis of business process models in BPMN",
_IST_ 50(12):1281-1294, 2008. Bartoletti et al., lending Petri nets, arXiv `1211.3624`.
Lengauer & Tarjan, 1979 (the dominator computation P2f names); Cooper, Harvey & Kennedy, "A
simple, fast dominance algorithm", Rice CS TR-06-33870 — the report's own front-page stamp; the
Rice repository catalogues the same PDF as TR06-38870, <https://hdl.handle.net/1911/96345>,
issued 2006 (the iterative formulation P2f implements, §1.1c). Sugiyama, Tagawa & Toda, "Methods
for visual understanding of hierarchical system structures", _IEEE SMC_ 11(2), 1981 (the
layered-layout phases §4.7 needs once B2 introduces cycles). Maslov & Poelmans, _I&M_ 61:103967,
2024, DOI `10.1016/j.im.2024.103967`; Maslov, Poelmans, Wautelet & Gailly, _JCL_ 84:101350, 2025,
DOI `10.1016/j.cola.2025.101350` (§7.4).
