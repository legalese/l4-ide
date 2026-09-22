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
  gated behind §7.3's three preconditions and §7.2's two experiments. **That gate was run and
  ruled NO on 2026-09-21: they are not built** (§7.3).

If both experiments come back saying the list and the off-the-shelf simulator suffice, **P2d and
P2e should not be built**, and that is a good outcome, cheaply obtained.

**RULED 2026-09-21 — NO, and it is that outcome, though not by the route this paragraph
predicted.** The off-the-shelf simulator does _not_ suffice — P2a says so, and run 4 says it
more strongly, since the simulator cannot draw multi-instance at all. The gate is conjunctive,
and it failed on the other conjunct: on its own three questions the list was not beaten
(pooled Q1–Q3, list 39/48 against 41/48 and 42/48; ahead of both pictures on Q1 and Q3). **Rerun
2026-09-21 against the repaired list (§7.7a): 41/48 against 40/48 and 43/48, unbeaten on Q1 at
16/16 — the first reopening condition is not met and the ruling stands.** The decision, the numbers
it rests on and the three things that would reopen it are in §7.3.

### 0.1 Rulings

| #      | Ruling                                                                                                                                                                                                                                                                                                                                                                        |
| ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Q1** | **REVISED.** P2 answers **position**. Reachability it can only over-approximate (G9); dominance it can answer without a new picture (P2f). A P2 that only draws a prettier static graph still should not be built. §1                                                                                                                                                         |
| **Q2** | The formalism is a **two-plane marked transition system** — an action plane and a norm plane — with the drawing vocabulary borrowed from Petri markings, Symboleo lifecycles and Meyer's violation atom. §2                                                                                                                                                                   |
| **Q3** | **SCOPED.** The evaluator is the semantics **for the marking and the step log**. Anything counterfactual — the enabled set, the discharging/breaching partition — must be computed **by running the evaluator**, not by walking a residual. §2.4                                                                                                                              |
| **Q4** | The animated data is a new **deontic step log**, modelled on `traceEval`. It does not exist today; it is ~6 call sites in `Machine.hs`. The type is now defined, in §4.3. **BUILT 2026-09-15** (`lts/p2b-step-log`, merged into `lts/p2-stack` 2026-09-15, not yet in `unstable`): seventeen call sites, not six — see the §4.3 BUILT block.                                  |
| **Q5** | **The bare Petri net is not better than BPMN at F1.** What closes F1 is reifying the norm as a marked place, which a net permits and BPMN has no vocabulary for. That is encodability, not expressiveness. §2.1                                                                                                                                                               |
| **Q6** | P1 emits a **file**; P2 renders a **view**. Two pictures, one stated division of labour. §5.1                                                                                                                                                                                                                                                                                 |
| **Q7** | **REVISED.** The smallest useful first deliverable is **P2a′ — render the projections as a plain list and see whether anyone still wants a picture.** It is cheaper than the BPMN-simulator baseline, and it tests the question P2 actually leads with. §7                                                                                                                    |
| **Q8** | **NEW.** `StateGraph` as shipped **cannot** be P2's layout scaffold. It carries no key a runtime obligation can be correlated to, and it does not close loops. Both are P2 preconditions, and both are now cheaper than they were. §3.4 **B1 and B2 LANDED 2026-09-16** (`lts/b1-b2-loops`): the key is carried (`labelSite`) and the loop closes; B3 (layout) is still open. |

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
document still does not know whether the picture beats the list. An LLM-reader _proxy_ was run
2026-09-16 (§7.7); it is not the gate, and the sentence above stands.

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
2. **Action-pattern matching.** Gap 2, narrowed 2026-09-21: `pay 100` and `pay 5` are now two
   edges, because the act prints through `L4.Print.printActionPattern` (`prettyPattern`,
   `jl4-core/src/L4/StateGraph.hs:1500-1501`) instead of eliding its arguments. What survives is
   the open name: `pay price` is one edge standing for every value that would discharge it, since
   `matchPattern`'s `PatVar` arm binds the scrutinee whatever it is
   (`jl4-core/src/L4/EvaluateLazy/Machine.hs:4051-4052`). The edge now says which names are open
   — `` the rule binds `price` `` — so a reader is told where the walk stops being exact rather
   than left to infer it.
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
> route is live. It used to inherit **one in the opposite direction** as well, and that one is
> now closed.
>
> ~~a bare single-party `PARTY … MAY` whose `HENCE` leads on to another obligation lapses
> straight to `FULFILLED` in the evaluator, and the graph does not draw that route~~ —
> **CLOSED 2026-09-17.** The history is worth keeping because it is a case of a defect being
> narrowed twice before it was fixed, and of the narrowing making the remaining half look
> smaller than it was. Measured when it was live, on the fixture
> `PARTY Alice MAY pay WITHIN 5 HENCE (PARTY Bob MUST deliver WITHIN 10)`:
> it evaluates to `FULFILLED` on expiry, while `--dominators` listed both `pay` and `deliver`
> as on every path to `FULFILLED`, so "listed ⇒ necessary" failed below a
> single party's lapsing `MAY`. **Narrowed 2026-09-16** to the single-party case, after
> `6daf1d9d` (barrier) and `d544ed22` (fork) drew an `EVERY … MAY`'s lapse as a `LEST` edge to
> `Fulfilled` under either join. **Closed 2026-09-17**: the `DMay` arm now draws that edge for
> any permission carrying a `WITHIN`, quantified or not — the quantifier was never what the
> rule turned on, the deadline was. Re-measured on the fixture above, verbatim:
> `--dominators` now answers "nothing in particular (there is more than one route)" for
> `FULFILLED`, which is right, because Alice can let the permission expire.
> `jl4/examples/bpmn/option.l4` is the golden witness, and it also pins the exporter half:
> `L4.Bpmn.Lower` no longer synthesises a lapse timer and routes it "wherever HENCE lands",
> which in that shape
> drew the seller owing a transfer because the buyer did nothing. What is left is the
> permission with no `WITHIN`: no deadline, no expiry event, no arm — and there the drawn
> routes are the only routes.

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

**R7 ANSWERED 2026-09-16 (Meng): _"Unranked; the derived-view column is the commitment."_** The
row's third column lists principled formalisms for the _concern_, co-equal and in no order; its
fifth column — **statechart / timeline** — is what the document commits to as the _derived
picture_, and `:935` says the same in prose ("regulative rules, which are a statechart in
disguise"). Three readings were put to Meng: (1) unranked with the derived-view column as the
commitment; (2) ranked, BPMN first on purpose — which would have set the row against its own
fifth column and changed PROCESS-TRACK §1's sentence; (3) never considered, rule it now. He
chose (1), so: this section stands as written, `logic-not-flowcharts.md` needs no edit,
PROCESS-TRACK §1's reading is confirmed, and the two-plane picture of §2.3 — a statechart per
norm with a marking to point at — is the derived view the row promised. BPMN remains a right kind
of picture for the concern and a wrong _derived view_ for it, which is the fidelity report's
claim, not this document's.

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

| Source                                                                                                                                                                               | The move                                                                                                                                                                                                                                                                                                                  | What P2 takes                                        |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| **Anderson 1958** (_Mind_ 67(265):100-103); **Meyer 1988** (_NDJFL_ 29(1)) — `Fα ↔ [α]V`, `Pα ↔ ⟨α⟩¬V`                                                                             | A distinguished **violation atom**. The three modals differ only in which transitions reach `V`.                                                                                                                                                                                                                          | The reduction itself, and its price. §6 G4           |
| **Sileno, Boer & van Engers**, LPPN (AICOL/MIREL 2018, DOI `10.1007/978-3-030-00178-0_6`; author copy `MIREL2017.pdf`)                                                               | **Two planes.** A procedural net for the world; a declarative net where normative positions — `Perm(A)`, `Forb(A)`, `Obl(B)` — are **places**, joined by constitutive links. CTD is topological, not axiomatic.                                                                                                           | The architecture. §2.3                               |
| **Azzopardi, Pace, Schapachnik & Schneider**, contract automata (_AI & Law_ 24(3):203-243, 2016; timed variant arXiv `2410.12585`)                                                   | Modality annotated on **states**, not transitions. A state carries the set of norms in force — i.e. **a marking**. Persistent vs ephemeral norms.                                                                                                                                                                         | Confirmation of where deontic status lives. §3.4     |
| **Sharifi, Parvizimosaed, Amyot, Logrippo & Mylopoulos**, Symboleo (RE 2020, DOI `10.1109/RE48521.2020.00049`, Fig. 2 p. 367; Parvizimosaed's 2022 thesis Fig. 5.1 p. 38 — read, R8) | **One statechart per obligation and per power.** Obligation states as printed: `Create`, `Active` ⊃ {`InEffect`, `Suspension`}, `Discharge`, `Fulfillment`, `Violation`, `Unsuccessful Termination`. Power states: `Create`, `Active` ⊃ {`InEffect`, `Suspension`}, `Successful Termination`, `Unsuccessful Termination`. | The F3 answer: vacuity becomes a _named state_. §3.1 |

A fifth, **Lomuscio & Sergot**, _Deontic Interpreted Systems_ (_Studia Logica_ 75(1):63-92,
2003, DOI `10.1023/A:1026176900459`), partitions each agent's local states into "green"
(correctly functioning) and "red", with `O_i φ` holding iff `φ` holds in all global states in
which agent _i_ is in a green local state — a **per-agent colouring of states**.

**VERIFIED 2026-09-16 (R8), from the primary text** — the authors' copy, `LomSer-DIS.ps` on
Lomuscio's Imperial page, converted with `ps2pdf` + `pdftotext`; page numbers below are that
copy's, not the journal's. §2.3, Definition 5, p. 6: _"We now define deontic systems of global
states by assuming that for every agent, its set of local states can be divided into allowed and
disallowed states. We indicate these as green states, and red states respectively. … G_i is
called the set of green states for agent i. The complement of G_e with respect to L_e
(respectively G_i with respect to L_i) is called the set of red states for the environment
(respectively for agent i)."_ Definition 8, p. 8: _"the truth of formula O_i φ at a global state
signifies the truth of formula φ in all the global states in which agent i is in a correct local
state, i.e. in a green state."_ The characterisation this spec carried was correct. Three things
the primary text adds that the secondary sources did not:

- **It is a colouring of states with no transitions at all.** p. 5: _"In this paper we do not
  deal with time, and so we will simplify this notion by not considering runs."_ So "locating
  deontic status off the transition" is true of it by construction, not by choice; protocols and
  transitions enter only in the companion paper (Lomuscio & Sergot, "A formalisation of
  violation, error recovery, and enforcement in the bit transmission problem", _J. Applied
  Logic_ 2(1):93-116, 2004, DOI `10.1016/j.jal.2004.01.005`, §2 Definition 2, p. 4 — also read
  from the author copy `LomSer-JAL.ps`; it restates the green/red definition and adds, p. 4: _"The
  terms 'green' and 'red' are chosen as neutral terms, to avoid overloading them with unintended
  readings and connotations."_).
- **The colouring is absolute**, §4.1 p. 15: _"the criterion for what counts as a green state is
  absolute, that is to say, the set of green states for an agent is independent of the state in
  which it currently is."_ Our `Violated` is history-dependent (a deadline was missed); in their
  model that history has to be folded into the local state. The F2 shape survives, but the
  per-party colour is a property of the state, not of how it was reached.
- **`O_i` is a correctness operator, not an obligation on a party.** JAL 2004 p. 4: _"it would
  not be appropriate to read the expression O_i φ as 'there is an obligation on agent i that
  φ'."_ It is the third independent formalism locating deontic status on states rather than
  transitions, and it is per-party — but what it colours is compliance, not a norm lifecycle,
  so it corroborates R1 and says nothing about §3.1's lifecycle names.

"Implemented in MCMAS" is also verified, from a different paper: Lomuscio, Qu & Raimondi,
"MCMAS: A Model Checker for the Verification of Multi-Agent Systems", CAV 2009, LNCS 5643:682-688,
DOI `10.1007/978-3-642-02658-4_55` (author copy `CAV-AL+.pdf`), §3: _"An optional section
`RedStates` permits the definition of non-green states by means of any Boolean formula on the
variables of the local states to interpret the correctness modalities O_i"_, with predefined
atoms `GreenStates` and `RedStates`. The 2003 paper itself does not name MCMAS; it predates it.

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

### 2.3a R1 — where modality lives: the record (ANSWERED 2026-09-16, coexist)

Meng closed R1 on 2026-09-16 as **coexist**: `TransitionLabel.labelModal` stays on the action-plane
transition as the extractor's reading of the text, and the norm plane's own modal field is the
semantics. He asked that the positions be recorded in detail so the question can be reopened
without re-deriving them. They are, in the order they were argued.

**Position 1 — the spec, revisions 1 and 2 (§2.3, §3.2, §3.4): it should move.** Modality belongs
on places, not transitions. Three published formalisms put deontic status on states or places —
contract automata annotate states, LPPN marks places, and Lomuscio & Sergot colour each agent's
local states (with §2.2's caveat, verified 2026-09-16 from the primary text: the 2003 model has no
transitions at all, so it is off the transition by construction rather than by choice, and what it
colours is compliance, not a norm lifecycle). "Our IR is the odd one out." Revision 1 deferred
because P1 was mid-flight; revision 2 recorded that reason as expired when P1 shipped at
`cfeaea5d`, costed the change as "regenerate three `.bpmn` goldens and re-run the validator", and
§3.2's table named it "**the IR delta**". Left unqualified, that row was a planned state in the
present tense — the correction is dated there.

**Position 2 — the tree, measured 2026-09-16 on `lts/p2-followups@c0092730`: it already
coexists, and has since P2b/P2c.** The static side: `labelModal :: Maybe DeonticModal`
(`jl4-core/src/L4/StateGraph.hs:159`), set at the two `extractDeonton` arms (`:908`, `:930`) and
read at **fifteen sites** — `L4/Bpmn/Lower.hs` ten times (`:199` task-arm note, `:236` and `:589`
the modal of an obligation or its continuation, `:1431`/`:1456` task naming, `:1495` the barrier
arm, `:1525` the multi-instance marker, `:1885`/`:1932` the `SHANT` negative-shape trick,
`:1982` the F1 fidelity finding's wording), `L4/StateGraph/Dot.hs:225` (the word printed on the edge,
via `formatModal`), `L4/StateGraph/Dominators.hs` three times (`:382` and `:414` special-case
`DMustNot`; `:391` renders the modal into the answer), and two tests (`StateGraphSpec.hs:408`,
`jl4/tests/BpmnExport.hs:342`). The semantic side: the norm plane carries the modal **on the
place** — `LiveNorm.lnModal :: DeonticModal` (`L4/Lts/Marking.hs:148`), filled from the
evaluator's own value `raw.roAction.modal` (`:358`), and `NormKey.nkModal` in the step log
(`L4/EvaluateLazy/DeonticStep.hs:151`). That is the move the three formalisms make, already
made, on the plane where the semantics live.

**Position 3 — the steelman for moving anyway.** Two homes for one fact are two chances to
disagree, and the IR being the odd one out invites a reader to treat the edge word as the
semantics. `Dominators.hs:382`/`:414` is a second reader that routes on the static label — a
static query, which §2.4 permits (its prohibition on re-deriving modal routing is for the
what-if), but a second reader all the same. A single home would make §2.4's "no second
semantics" structural rather than disciplinary.

**Position 4 — the case for coexist (this session's recommendation, adopted).** The published
formalisms' claim is about the semantic model, and the semantic model satisfies it (position 2).
`StateGraph` is not the semantics; it is a static extraction from the rule text, a drawing aid
(§2.4), and its two heavy consumers — BPMN export and the dominator query — are static too: they
have no event stream, so there is no marking for them to read a modal from. "Moving" the field
would therefore mean inventing a **static** norm plane (one place per `RAction` site) to hold one
enum, rewriting fifteen sites, and regenerating fourteen BPMN goldens, to deliver nothing the
norm plane does not already deliver. And the hazard position 3 names is real but is not a
hazard of _location_: it is a hazard of _disagreement_, and the witness is `d544ed22` — the
extractor's `DMay` arm routed a fork-`MAY`'s expiry where `HENCE` routes, the runtime routed it
to `FULFILLED`, and the `modals-may-fork` golden lied until someone measured (§4.9; found by the
P2a re-measure on `lts/p2a-remeasure@11199a16`). Moving `labelModal` would not have caught that;
the static-picture-versus-runtime-step-log differential did. So the control is the differential,
not the field's address.

**What is left of R1 is a drawing rule, and it belongs to P2d.** `Dot.hs:225` prints
`formatModal labelModal` on every edge. When a picture draws both planes, the edge should stop
printing `MUST`/`MAY`/`SHANT` so modality is not shown twice — one line, decided when P2d decides
what it draws, not an IR change and not before the §7.3 gate. Meng's framing of the timing
question ("before or after the gate") therefore gets the answer _neither, as an IR change_.
**2026-09-21: P2d is not being built — the §7.3 gate is ruled NO — so this residue is moot
unless that gate is reopened on one of the three conditions §7.3 names, and until then
`Dot.hs:225` goes on printing the modal on every edge, which is the right rendering while only
one plane is drawn.**

**What would reopen it.** (a) P2d or P2e ends up drawing modality _from the edge_ rather than
from the marking — two sources feeding one picture is when to consolidate; (b) a differential run
finds a second static consumer routing on `labelModal` in a way the runtime does not, i.e. a
second `d544ed22`; (c) a static consumer that _needs_ a lifecycle (not just a modal) appears, at
which point the static norm plane position 4 declines to build has a customer. Absent one of
those, the field stays, the norm plane is the truth, and a disagreement between them is an
extractor bug.

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
  instantiated (`patternExpr`, `:523`: `PatApp`/`PatLit`/`PatExpr`, with an `EXACTLY e` read
  through the residual's heap by `reifyExpr`, `:539`, so `Sign (EXACTLY t)` under an `EVERY`
  names the member); for every distinct live deadline, a tick to just past it (endpoint 24) — a
  `WAIT UNTIL`, the machine's own no-party event, stamped by `tickPast` (`:277`: one unit past, or
  half-way to the next live deadline when nearer, because the machine expires on `stamp >
deadline` and a tick AT the deadline reveals nothing); and a listed refusal, when the shape
  cannot be instantiated — a `WITHIN` that was never evaluated and is not a
  literal (`deadlineOf`, `:264`). Refusals are listed, not dropped: an enabled set that omitted
  them would say "nothing else can happen". **Amended 2026-09-19 (every-each round 2, O2; the
  proxy's one actionable finding, §7.7):** an action that NAMES a local the residual holds
  unforced — a member's pattern-bound `amount` read through a fork's `HENCE`
  (`ok/every/run-fork.l4`); a rule `GIVEN` no event has compared yet — is the same refusal,
  with the same sentence, and it is made BEFORE any replay (`closedAction`/`openLocals`): the
  replay evaluates a hypothetical in the module's top-level environment, whose keys `position`
  now records (`posReplayScope`, from the heap `replay` returns, plus `rigEnv`; builtins by
  sort), so a `Var` the obligation's environment holds that is neither there nor a builtin can
  only fail at replay — and until this date it did, surfacing the evaluator's own "Internal
  error: amount is not in scope" as the `Untried` reason (measured on `run-fork.l4`'s second
  trace and on `regulative-reference-expressions.l4`'s `projection operand`). A genuinely broken
  name — one the environment does NOT hold — is deliberately left to the replay, so an
  unexpected exception still surfaces loudly. Two things came with it: `reifyExpr` now visits
  every `Var` under any operator (it read only `App` arguments before, so `p` under `p's
  landlord` stayed unread even when forced, and that witness now discharges rather than
  refuses); and a candidate carries `cdShape`, the action as far as the residual could read it,
  so the refused receipt is still named `Receipt OF (Landlord OF "Ms Ng"), (Tenant OF "Alice"),
  amount` — the member known, the sum open — where a `PatVar` pattern, which has no expression
  form, is still named as the pattern. Pinned in `LtsWhatIfSpec` cases 10 and 10'. Each
  candidate's `LiveNorm` is rendered by `renderLive` (`Marking.hs:354`) from the very
  `RawObligation` its act is built from — the first cut paired `liveObligations` with the
  marking's `InEffect` list by `zip`, on the unguarded assumption that two walks agree in order;
  review 2026-09-15 replaced that with one walk.
- **A pattern that BINDS is a SET of acts, and the what-if answers for the set — AMENDED
  2026-09-21** (`BoundAct`, `boundActOf`, `confirmBound`; `LtsWhatIfSpec` cases 4/13, 11, 11',
  12, 12'). Until this date an action pattern that bound a variable was refused outright, with
  the same sentence as the unforced-local case above — "the action binds `price`, which the
  what-if cannot choose". §7.7 point 2 measured what that cost: **all eight** of the list's Q2
  misses were on the three contracts whose `A.txt` printed it, and on the one contract where the
  act could be tried the list was 4/4. It is now repaired, and the repair keeps two claims
  apart, which is the whole of its honesty:
  - **asserted, from the rule's own text** — that the binder matches whatever the event carries.
    That is the language's PATTERN semantics (`PatVar` binds, it does not test), not a second
    reading of the deontic machine, so it is not the re-derivation this section forbids. A
    `PROVIDED` guard that names the binder does test it, and then the assertion narrows to "any
    value for which this holds", the guard printed as the rule wrote it with whatever the
    residual has already computed read back into it (`reifyExpr`), so the promissory note's
    threshold prints as the number rather than as the name of the expression that computes it.
  - **checked, by the replay, exactly as any other candidate is** — that ONE act drawn from the
    set is taken, and what the machine then does with the whole contract. The value is never
    invented: it is the guard's own other operand where there is one (`price >= 20` → 20), else
    the simplest value of the type the rule declares for that place (`0` for a `NUMBER`, `""`
    for a `STRING`, the first field-less constructor of a declared type), else — for a binder
    that IS the whole action, which has no declared type to read — an act the `#TRACE` itself
    writes (`authoredAct`; a `#TRACE` is type-checked against its contract, so such an act is an
    act of the contract's own action type).
    A witness the contract PASSES OVER proves nothing about the rest of the set, so `confirmBound`
    turns that outcome into an `Untried` naming the witness — the same shape of guard as
    `confirmTick` and `confirmAct`, and for the same reason. So does a set no witness could be
    built for. Both keep their own wording; the unforced-local refusal above keeps `cannotChoose`
    unchanged, because there the what-if cannot say even what the set is, and the list's consumers
    key on that sentence.
    **The two lines the list prints beside the verdict must not let the verdict be read as the
    SET's — CORRECTED 2026-09-21, after review** (`boundLines`, `List.hs`). The first cut said
    "any `price` the condition accepts **counts**" under a heading that names an outcome, so the
    pair asserted that outcome for every member, and the flagship corpus file contradicts that
    ten lines below its own listing: `ok/contracts.l4`'s `MUST payment price PROVIDED price >= 20
HENCE (IF price = 20 THEN FULFILLED ELSE PARTY B MUST return WITHIN 10)` is matched by every
    price of 20 or more and DISCHARGED by exactly one of them — and `guardOther` systematically
    picks that boundary value, so the line read as the set's answer while being the witness's.
    The same shape put "any act by B counts" under "What would move things along (neither ends
    nor breaches it)" while the section immediately above named an act by B that breaches (a
    `MUST ret` beside a `SHANT bad`), because `reach` consults the candidate's own norm and no
    other. Repaired by splitting the two claims in the words themselves: the reach line is about
    MATCHING and about **this obligation** ("this obligation's pattern matches any `price` the
    condition accepts"), and the second line carries the verdict's scope ("the verdict above is
    one act's, not the set's: `price` = 20 was replayed, and another member may end elsewhere").
    `noWitness`'s reach clause took the same "this obligation" narrowing.
    **The refusal's last clause is the obligation's own question — CORRECTED 2026-09-21**
    (`outcomeWord`, `baModal`). `witnessPassedOver` said "so what would discharge it is not
    confirmed here" for every modal, which tells a PROHIBITION's reader the opposite of what the
    rule does: an act a `SHANT`'s `PROVIDED` accepts is the breach. Live on
    `doc/reference/regulative/shant-example.l4`'s own `debt restriction` when it was found;
    `BoundAct` now carries the modal and a `SHANT` reads "what would breach it". Pinned,
    `LtsWhatIfSpec` case 12''.
    **The guard route is held to the binder's declared type — CORRECTED 2026-09-21** (`fitsType`).
    `guardOther` reads the guard's SHAPE, and its `App _ _ [a, b]` case — which the promissory
    note needs, its guard being `is money at least equal within error` OF … — matches an
    application whose two argument places are different types, so the operand beside the binder
    could be a value the binder could never hold. Since the replay does not type-check a
    hypothetical, that reached the reader two ways: as the evaluator's internal error inside the
    list (the one text `doc/reference/regulative/lts-list.md` promises the list never shows), and
    — silently, which is the worse half — as the contract's answer for a value the contract was
    never given (`amount` = `"hello"` in a `NUMBER` field, reported as discharging). `witnessFor`
    now checks route 1's value against the type `binderTypes` recorded and falls to route 2 when
    it does not fit. The check is a head check and ABSTAINS where either side is unreadable, so
    the note's `Money` witness still comes from the guard. Pinned, `LtsWhatIfSpec` case 12'''.
    **Measured** (the binder's type): a pattern binder reaches NEITHER the module-level
    `EntityInfo` the rig carries (`doCheckProgram` returns the top-level environment, not the
    reader-local scope `inferPatternVar`'s `makeKnown` opens) NOR its own annotation
    (`inferPatternVar` builds the `PatVar` with a bare `mkAnno`; only `PatApp` and `PatCons` are
    stamped by `setAnnResolvedType`). Both were tried and both came back empty, which is why
    `binderTypes` reads the ENCLOSING CONSTRUCTOR's declared field types instead — and why a
    whole-action binder has no type to read at all.
- **The tick is held to the machine's word** (`tryCandidate`, `:335`; `confirmTick`, `:423`).
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
- **The replay** (`replay`, `:504`) rewrites the checked module so that every directive is dropped
  except the `#TRACE` in question, which gets the hypothetical appended, and runs
  `execEvalModuleWithDeonticLog` on it. The verdict (`classify`, `:453`) reads only the machine's
  own terminals: `ValFulfilled` → `Discharging`, `ValBreached` → `Breaching blame`, anything else
  → `Advancing marking` with the marking from the replay's own steps. An error or a refusal is
  `Untried` with the text. The steps an outcome carries are those past the longest prefix the
  replay's log shares with the position's (`afterCommonPrefix`, `:450`): a `Waiting` in the
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
  `EnabledSet` (`enabledSet`, `:470`), i.e. endpoints 19 and 20 are a classification of 22's
  result and not a projection of their own.

**Measured** (`jl4-core/test/LtsWhatIfSpec.hs`, 21 examples): a `MUST` at the start — the act
advances into the `HENCE`, the tick past 10 breaches; one event in — the clock is the last stamp,
Bob's act discharges, the tick past 3 + 5 breaches. A `SHANT` with no `LEST` — the act
**breaches** and the tick **discharges**, which is the polarity the machine routes and this module
never states. A `MAY` with a `HENCE` — the act advances, the tick discharges (`LEST` defaulting to
`FULFILLED`). `contracts.l4`'s `aContract` one event in — `payment price PROVIDED price >= 20`
is tried with the guard's own threshold, 20, and **discharges** (the `HENCE` is
`IF price = 20 THEN FULFILLED`); the tick past 2 + 3 advances to the `LEST`'s
`EXACTLY payment OF fine`. _(Until 2026-09-21 that first row was `Untried` naming the binder;
case 4 is now case 4/13 and pins the guard's printed form, the witness and the act replayed.)_
The same file at its own first `#TRACE` — `PARTY B MUST return`, a binder that IS the whole
action — B does **anything** and the contract is fulfilled, checked on `delivery`, the first act
the `#TRACE` writes (case 11); the same shape with nothing authored to draw from stays refused,
in its own words and not the unforced-local one (case 11'); an argument binder with no guard is
tried with `0`, the simplest value of its declared type (case 12); and a guard the witness does
not satisfy (`amount GREATER THAN 20`, witness 20) is reported `Untried` naming the witness,
never as the contract's answer for every amount (case 12'). A
fork's `HENCE` naming the member's open `amount` (`run-fork.l4`) and a rule `GIVEN` at its
outset — refused before the replay, `ocSteps` empty, no verdict text containing "not in scope";
the same `GIVEN` once a comparison has forced it — read through a projection and discharging
(cases 10, 10', added 2026-09-19). A
barrier of three with nobody acted — each member's act is **`Advancing`** with the `Awaiting` at
1 of 3, the tick breaches; with two acted — the last member's act is **`Discharging`** (the
`HENCE` is `FULFILLED`), the tick breaches. A fork — each member's act advances its **own**
continuation and leaves the others at `WITHIN 7`. Corpus goldens: `cabal test jl4-test` — no
`.l4` file and no printer changed, so no corpus golden moves; the two `l4 lts` goldens that the
bound-variable repair does move (`contracts`, `tenancy`) are named in the commit message.

**Not built.** No CLI verb, no service endpoint, no `doc/` page: nothing a user can invoke
changed, and P2a′ (the list) is the deliverable that will need the page _(P2a′ landed the same
day — `l4 lts` and `doc/reference/regulative/lts-list.md`, §7.6; no service endpoint still)_. A `PatCons` action is
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

| `StateGraph`                           | Action plane                                                                                                                                                                                                          |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ContractState`                        | a place; the control token sits in exactly one                                                                                                                                                                        |
| `Transition`                           | a transition, fireable iff its event shape is in the enabled set (§4.2)                                                                                                                                               |
| `FanKind = AllOf` (`:111-115`)         | a **fork**, and — see R2 — possibly a fork **plus a join**                                                                                                                                                            |
| `FanKind = OneOf`                      | a conflict (free choice): branches compete for the same token                                                                                                                                                         |
| `FanKind = Linear`                     | ordinary sequence                                                                                                                                                                                                     |
| `InitialState`                         | the initial marking                                                                                                                                                                                                   |
| `TerminalFulfilled` / `TerminalBreach` | absorbing places; **shared sinks** — `getTerminalState` (`:204-209`) is find-or-create by `(name, stateType)`                                                                                                         |
| `labelModal` (`:128`)                  | ~~**moves out of the label** into the norm plane. See R1 — this is the IR delta~~ **Corrected 2026-09-16: stays.** R1 ANSWERED coexist (§2.3a); the norm plane carries its own `lnModal`, so this is not an IR delta. |

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

_(Gap 6's first clause, measured 2026-09-23 on `ab6ecc4af`: which arrows are blank is a rule, not
an accident. Over the 88 files under `jl4/examples` and `doc` that produce a graph, 107 edges carry
`label=""`, and every one is a `RAND` branch (63, violet `#6f42c1`) or an `ROR` branch (44, amber
`#e8850c`) — `fanLabel` is all-`Nothing` for those two (`jl4-core/src/L4/StateGraph.hs:986-1000`).
An `IF` branch edge is not blank: it carries the guard that selects it, and has since 2026-08-02
(`82c49e619`). No obligation edge is blank either: an edge that leaves the entry
state of its own obligation drops the party, the modal and the act, and `suppress`
(`jl4-core/src/L4/StateGraph/Dot.hs:398-399`) does that only where a guard, a join line or a binder
clause survives it — with nothing left to read, the full caption prints.)_

_(2026-09-16: gap 1 is closed for the edge — `labelSite` — and gap 3 is closed for named targets;
both by §3.4's B1/B2 blocks. A `RECORD` continuation is still a dead end.)_

_(2026-09-21: gap 1 is closed for the state as well — `ContractState.stateSite`, §3.4's B1 block —
and gap 2 is narrowed rather than closed. An act prints its arguments through
`L4.Print.printActionPattern`, so `pay 100` and `pay 5` are two edges and `Pay (EXACTLY t)` keeps
its `EXACTLY`; what is still not expressed is the value behind an open name, and the edge now says
which names those are — `` the rule binds `price` ``. Gaps 4, 5, 7 stand.)_

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

| ID     | Precondition                                                                                                                                                                                                                                | Cost                                                                                           |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| **B1** | **Carry the key.** `TransitionLabel` (or `ContractState`) gains the `RAction`'s `SrcRange`. Closes gap 1 for the click-to-source case too. **LANDED 2026-09-16**, below.                                                                    | Small. Changes `StateGraph`'s public type; predicted to move the BPMN goldens, and moved none. |
| **B2** | **Close the loop.** `TargetOther` pointing at a named contract already extracted must reuse that state, not mint `"next"`. Needs a memo — keyed, as built, by the rule's `Unique`, not by B1's range (below). **LANDED 2026-09-16**, below. | Medium, and it **makes layout harder** — see §4.7.                                             |
| **B3** | **Layout.** §4.7. Undefined in revision 1; still not solved here, but now stated, costed and assigned. **Still not built** as of 2026-09-16 (the in-pane picture is viz.js over the DOT, §4.8, not this).                                   | Medium-large, and the two-plane form is strictly harder than P1's DAG.                         |

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
formalisms — contract automata annotate states, LPPN marks places — and a third with a caveat
(Lomuscio & Sergot colour states per agent, but their 2003 model has no transitions to put the
modality on, so it is off the transition by construction rather than by choice, and what it
colours is compliance, not a norm lifecycle — verified 2026-09-16, §2.2). Our IR is the odd one
out. (**R1 ANSWERED 2026-09-16 — coexist**, §2.3a: the corroboration is for the norm plane, which
already carries the modal on the place; the action-plane field stays as the extractor's reading,
and the residue is a P2d drawing rule, not an IR change — and 2026-09-21 that residue is moot,
P2d not being built, §7.3.)

> **B1 LANDED 2026-09-16** (`lts/b1-b2-loops`). `TransitionLabel.labelSite :: Maybe SrcRange`
> (`jl4-core/src/L4/StateGraph.hs`, the field's own comment), set in `extractDeonton` to
> `rangeOf action` — the same expression `armNormKey` (`Machine.hs`) evaluates to stamp
> `NormKey.nkSite`, so the two halves of the key agree by construction and not by convention.
> Both arms of an obligation carry it (the `HENCE` edge and the `LEST` edge are two outcomes of
> one obligation; `transType` says which); a junction's branch edge and a hand-built fixture
> leave it `Nothing`.
>
> **The key is load-bearing in a second place since 2026-09-21** (`289e8aaf5`, `lts/draw-what-it-means`), **so a change to either half now breaks two things.**
> The second place is `ContractState.stateSite :: Maybe SrcRange` (`jl4-core/src/L4/StateGraph.hs:131`), which carries `rangeOf` the same `RAction` (`deontonSite`, `:1402-1403`) on the state `wireTarget` names after an obligation (`:943`), so a state now carries the range that click-to-source on a _state_ would need rather than having it read off the edge that enters it.
> The renderer then reads the two halves against each other: `leavesItsOwnObligation = isJust fromSite && fromSite == transLabel.labelSite` (`jl4-core/src/L4/StateGraph/Dot.hs:222`, source site from `:111`), and an edge that passes it drops the party, the modal and the act, because the node it leaves already says all three.
> So the key now decides both P2's correlation of a logged obligation to an edge and what every DOT caption says.
> The comment at `Dot.hs:214-221` gives the reason it is a range and not a string comparison, and that reason is the same one this block gives for `nkSite` ↔ `labelSite`: two texts built by two functions agree until one spelling moves, and then disagree silently, while both ranges are read off one `RAction`.
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
> as before; `P-CYCLE`). Not in the map, and so still `TargetOther`, which is a dead end named
> after the arm that reaches it (`HENCE of …` / `LEST of …` since 2026-09-21, `next`/`failure`
> before that): a rule from an `IMPORT` (measured with a two-file scratch pair), a `RECORD`
> continuation, a `Refuse`, an `AppNamed`, and any `DECIDE` whose body is not regulative.
>
> **Measured, (a) DOT over the corpus.** `l4 state-graph` over every `.l4` under `jl4/examples`
> and `doc` that accepts it: **71 files produce graphs, 9 changed** —
> `doc/concepts/legal-modeling/regulative-layer-whole-example.l4`,
> `doc/courses/{advanced/module-a1-regulatory,advanced/module-a2-cross-cutting,advanced/module-a3-contracts,foundation/module-7}-examples.l4`,
> `doc/reference/regulative/every-example.l4`, `doc/tutorials/obligations/what-follows.l4`,
> `jl4/examples/ok/contracts.l4`, `jl4/examples/ok/every/barrier.l4`. Files carrying a `next` or
> `failure` state went from 16 to 10; the 10 that remain are `IF` junctions (not dead ends) and
> the `ok/ledger/record-*` `RECORD` continuations (dead ends still).
>
> **Both literals are gone since 2026-09-21** (`289e8aaf5`, `lts/draw-what-it-means`): the fallback name is `HENCE of <obligation>` (`jl4-core/src/L4/StateGraph.hs:1162`) or `LEST of <obligation>` (`:1191`), and a junction says which keyword fanned it on a second line, from `ContractState.stateConstruct`.
> `ok/contracts.l4`'s reads `HENCE of B must payment price\nIF: ONE OF`.
>
> **Re-measured 2026-09-23** on `ab6ecc4af`, same sweep, over a corpus that has grown: **88 files under `jl4/examples` and `doc` produce a graph** (71 on 2026-09-16), **none draws a state named `next` or `failure`**, and 13 files draw a `HENCE of …` / `LEST of …` state.
> Of those states, 13 are junctions in 5 files (`bpmn/handover.l4`, `bpmn/offering.l4`, `ok/contracts.l4`, `ok/every/run-anchors.l4`, `ok/every/run-stack.l4`) and 19 are dead ends in 9 files, six of them the `ok/ledger/record-*` continuations — `record-block.l4` draws `1 [label="HENCE of P must serve"]` with no outgoing edge, exactly as the `next` it replaces did.
> The two file counts are not comparable, because the sweep is not the same sweep; what is comparable is that the literals are at zero. In `ok/contracts.l4`, `a MEANS z RAND z` now draws one `z` junction with two
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

_(The status column is revision 2's, 2026-07-27, and is left as the record. As of 2026-09-15 the
residual after each event and the step that produced it are P2b's log (§4.3), the marking is
`L4.Lts.Marking` (§4.2a), and the enabled set, the discharging/breaching partition and the next
deadline are `L4.Lts.WhatIf` and `l4 lts` (§2.4, §7.6) — library functions and a CLI verb, none of
them an HTTP endpoint. `expected-events` is still nowhere in the tree, and live mode is still
blocked where it was.)_

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
LayoutPrinter a => MarkingContext -> Value a -> [NormPlacement]` (`:303`). The sketch above is superseded by the module; this block records where
the built type departs from it and why, and what was measured.

- **The final `NormPlacement`** (`Marking.hs:109`): `Created {crSite, crSource}` (Symboleo's
  `Create`, past-participled), `InEffect LiveNorm` (Symboleo's `InEffect`, exactly), `Violated
Blame` (Anderson/Meyer's violation atom; Symboleo's state is `Violation`), `Lapsed Blame`
  (**ours** — R12 ANSWERED 2026-09-16, below), and the join state `Awaiting {awJoinSite,
awProgress :: Maybe Progress}` (`:130`). `LiveNorm` carries the site (`rangeOf` the `RAction`), the bearer as
  `KnownParty`/`UnforcedParty` (a `PARTY p` that never met an event still holds the expression),
  the modal, the action pattern, a `Countdown` (`NoDeadline | UnforcedDeadline Text | Remaining
Rational` — the residual `WITHIN` is a number only once the obligation has scrutinised an event;
  before that it is the unevaluated expression, measured on the fixtures marked B″ and K), the
  `HENCE`/`LEST` text, and `lnMember :: Maybe Family` from the context — the family (join,
  total, join site; `Family`, `:167`), not a `MemberOf`: through a context keyed by action site
  a `moIndex` would be whichever member the log wrote last, so it is not carried (review
  2026-09-15; the first cut exposed `MemberOf` with an index that was nobody's). Fulfilled marks `[]`, as
  sketched — there is no `Discharged` place; §3.1's row was the table, §4.2a's fold is the rule.
- **Two `Created` shapes, not one.** The sketch had only the `Left rexpr` operand of a `ValROp`. A
  `ValQuantified` — an `EVERY` that has not met its event stream, so its cast is not drawn — is
  the other, and is `Created` with the whole rule's range and source (`markingOf`'s
  `ValQuantified` arm). It was not in the sketch because the sketch predates the quantifier.
- **The join, against `Threshold`.** `Progress = {prDone, prTotal, prThreshold :: Threshold
Resolved}`. Phase 3's count and measure forms add arms at `thresholdMet` (`:229`), at
  `placementText`'s `thresholdText` (`:458`), and in the machine at `assembleQuantified`'s
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
  a `MarkingContext` (`:237`, `contextOf :: [DeonticStep] -> MarkingContext`, `:261`), read back
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
  (`Machine.hs:2529-2530`, `:2557-2560`) and a drafter's own `the join` written as a `HENCE` carries
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
- **`liveObligations`** (`:386`) is the same walk unrendered, for "L4.Lts.WhatIf", which needs
  the value and not its text, and `renderLive` (`:354`) is the `InEffect` reading of one raw
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
decided. _2026-09-21: moot in one direction — §7.3 is ruled NO, so there is no P2d for it to
move to; it stays P2h's second half and stays blocked on nothing._) `Lapsed` is ours, not
Symboleo's — R12, answered below.
`awProgress` from the residual alone, for the reason above. B1's static half of the key: nothing
in `L4.StateGraph` was touched by P2c _(B1 LANDED 2026-09-16, §3.4 — `labelSite` is that half,
and `StateGraphSpec` proves it equal to `nkSite`)_.

**ANSWERED 2026-09-16 (R8 half, R12) — the lifecycle provenance, read from the primary text.**
Two Symboleo sources were read, not searched: the RE 2020 paper (Sharifi, Parvizimosaed, Amyot,
Logrippo & Mylopoulos, "Symboleo: Towards a Specification Language for Legal Contracts", _RE
2020_ pp. 364-369, DOI `10.1109/RE48521.2020.00049`; open copy at the Cyberjustice Laboratory,
Fig. 2 on p. 367, rendered and read because the statechart labels are not in the PDF's text
layer), and Parvizimosaed, _Symboleo: Specification and Verification of Legal Contracts_, PhD
thesis, University of Ottawa, 2022, <https://ruor.uottawa.ca/handle/10393/44186>, Fig. 5.1 p. 38
and Listing 7.4 p. 78. The two figures agree on the obligation and power charts (the thesis adds
`Rescission` to the _contract_ chart only). The _SoSyM_ 2022 paper (DOI
`10.1007/s10270-022-01053-6`, resolved via Crossref: first author is **Parvizimosaed**, not
Sharifi, pp. 2395-2427) is paywalled and was **not** read; nothing here rests on it.

- **Every obligation state, as printed** (RE 2020 Fig. 2; thesis Fig. 5.1): `Create`; the
  `Active` superstate containing `InEffect` and `Suspension`; and four terminal states
  `Discharge`, `Fulfillment`, `Violation`, `Unsuccessful Termination`. The transitions are
  `Triggered` (→ `Create` if conditional, → `InEffect` if unconditional — the thesis labels these
  `Triggered(conditional)` / `Triggered (unconditional)`), `Activated` (`Create` → `InEffect`),
  `Expired` (`Create` → `Discharge`), `Discharged` (`InEffect` → `Discharge`), `Fulfilled`,
  `Violated`, `Terminated` (`Active` → `Unsuccessful Termination`), and the `Suspended` /
  `Resumed` pair. So R8's guess was half right: there **is** a `Suspended`→`Resumed` pair and
  there **are** `Expired` and `Terminated` — but as _events_, not states; the states they lead to
  are `Discharge` and `Unsuccessful Termination`. The thesis's nuXmv encoding (Listing 7.4 p. 78)
  enumerates the states as `{not_created, create, inEffect, suspension, discharge, fulfillment,
violation, unsTermination}`. (§3.1 and `Marking.hs` write `InEffect`, as the figures do. The
  `Marking.hs` Haddock — `1a90524b`, 2026-09-15, and still the tree's text at `:113` — writes
  `/inEffect/`; that predates this reading of the thesis, so it was not borrowed from Listing
  7.4. It is **not** corrected in this track; see the NOT BUILT block at the end of §4.2a.)
- **Every power state, as printed**: `Create`; `Active` ⊃ {`InEffect`, `Suspension`};
  `Successful Termination` (reached by `Exerted`) and `Unsuccessful Termination` (reached by
  `Expired` from either `Create` or `InEffect`, or by `Terminated`). Relevant to R9, which stays
  open.
- **`Created` / `InEffect` — Symboleo's, with one letter of licence.** `InEffect` is exact.
  `Created` is Symboleo's `Create` past-participled to match its siblings; the thesis's own
  prose does the same (p. 39: _"Conditional obligations are created (instantiated) when their
  triggers become true"_). Kept.
- **`Violated` — Anderson/Meyer, as recorded; Symboleo's state is `Violation`** and its event is
  `Violated`. The provenance line stands, and the Haddock (`Marking.hs:19-20`) now says which is
  which — see the BUILT block below.
- **`Lapsed` — ours. No Symboleo state covers it, and the two candidates both mislead.** What
  `Lapsed` marks is a `ValBreached` operand of a surviving `ROr`: the machine **did** conclude a
  breach of that alternative, with blame (§3.1's counterexample), and only the compound is not
  violated. Symboleo has one lifecycle per obligation instance. An alternative can be encoded
  there as a separate obligation (which would simply be in `Violation`) or as a disjunct of one
  obligation's consequent — the grammar admits it: `Proposition: POr;` / `POr returns
Proposition: PAnd ({POr.left=current} "or" right=PAnd)*` (thesis Listing A.1, printed
  p. 149), and p. 107: _"Recursive combinations of atomic situations result in a composite
  situation"_ — and in **neither** encoding is there a state for "this disjunct is lost but the
  obligation stands": a lost disjunct inside a consequent has no state at all, and a separate
  obligation has only `Violation`. (An earlier draft of this block said Symboleo expresses
  alternatives as "separate obligations plus powers"; the thesis does not say that, and the
  grammar contradicts it. Corrected 2026-09-16.) The two candidates R12 named: `Discharge` is
  _"cancelled obligations rather than unsuccessfully terminated ones"_ (thesis p. 39; RE 2020
  p. 368), reached by `Expired` from `Create` — an obligation whose **antecedent** can never come
  true, i.e. one that never took effect — **or** by `Discharged` from `InEffect`, the creditor's
  power (thesis p. 40: a power _"entitles its creditor to suspend, terminate, or discharge one
  or more InEffect obligation instances"_; the edge is in RE 2020 Fig. 2 and thesis Fig. 5.1);
  in neither case has the debtor breached. `Unsuccessful Termination` is reached by
  `Terminated` — cancellation by a power or by the contract's own termination, again with no
  breach by the debtor. Both would erase the blame `Lapsed` carries. **Ruling: keep `Lapsed`,
  record it as this spec's coinage, do not rename.** No P2c follow-up is needed for the name;
  the only code-side consequence is the Haddock provenance comment, which this track does not
  touch (below).
- **A naming hazard, recorded because it fails silently.** §3.1 maps `ValFulfilled` to
  `Discharged`, in the ordinary legal sense of discharge by performance. That is **not**
  Symboleo's `Discharge`, which is the no-performance cancellation above; Symboleo's word for
  performance is `Fulfillment`. There is no `Discharged` place today (`Marking.hs` marks
  `ValFulfilled` as `[]`), so nothing is wrong in the tree — but whoever adds one must not
  label it with Symboleo's name, or the picture will say "cancelled" where the evaluator said
  "performed".

**BUILT 2026-09-16 (second pass) — the `Marking.hs` Haddock now carries the ruling.** The
comment-only correction first written as `1603ae64` and `a627e7f3` and reverted by `b9f13f0f`
(the R8-R12 track was gated on touching no Haskell, Haddock included) was re-applied verbatim
from those two commits' `Marking.hs` hunks on `lts/p2-followups`: the module's "Provenance of the
lifecycle vocabulary" list (`jl4-core/src/L4/Lts/Marking.hs:12-33`) now names Symboleo's
`Create`/`InEffect` (`:14-18`), gives `Violation` as Symboleo's counterpart of `Violated`
(`:19-20`), and states R12's answer for `Lapsed` in the softened form the bullets above use —
one lifecycle per obligation instance, `POr` disjunct or separate obligation, `Discharge`
reachable from `Create` or `InEffect` (`:21-30`); the constructor comments write `Symboleo's
@Create@` and `@InEffect@` (`:117`, `:122`) and `(R12, ours)` (`:127`). 19 lines added, 10
removed, no code; the header grew by **+9**, measured, and the ten line cites in this section
plus `renderLive` (§2.4), `NormPlacement` (§4.2a) and `lnBearer` (§4.3) were re-anchored by
that amount against the tree. `cabal build jl4-core` clean under `-Wall -Werror`.

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
  clocked with the stamp. Until #412 that matched what `barrierFail` peeks for the `LEST` case;
  since #412 the two differ **by design** — `JoinFailed ToBreach` is clocked at the anchoring
  failure's _revealing_ stamp (`barrierFinish`, `Machine.hs:3333-3337`), while `JoinFailed ToLest`
  is clocked at the missed _deadline_ the `LEST` counts from (`barrierFail`, `Machine.hs:3494`,
  peeking the sentinel's `failTimeRef`; EVERY-EACH-QUANTIFIER-SPEC §5.2). Pinned:
  `DeonticStepSpec.hs` case 15 row `:721` (`Just 14`, the deadline) beside case 17 row `:747`
  (`Just 20`, the stamp); `--steps` words them `a member did not come through; on to the
fallback` / `…; that is a breach` (`List.hs:486`), the first at `at 14:` in
  `every-run-example.txt:31`.) The log **peeks and never forces** (`peekWHNF`,
  `Machine.hs:443`); that rule decides every `Maybe` below.
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
  constructor, allocated as a value) is known and a computed party would not be. **BUILT
  2026-09-19 (O1, `lts/p2-followups-2`): `NormKey` `+ nkBearerSource :: Maybe Text`** — the party
  AS WRITTEN, the `prettyLayout` of the `PARTY p` expression's syntax, taken at `armNormKey`.
  It is source, not value, so recording it forces nothing (peek-never-force stands), and it is
  what the log has on the one step neither `nkBearer` nor `nkBearerName` can be known: the
  no-`LEST` breach of a computed party. `Nothing` for an obligation whose party arrived as a
  value (an `EVERY` member; the roll call forced it and `nkBearer` knows it) and for a join's own
  key. `List.hs` falls back to it when both value renderings are absent, **marked as the written
  form**: `ok/every/run-lest.l4`'s trace at :108 now reads
  `at 10: the event at 18; theLandlord (as written; not yet resolved) MUST — deadline 15 passed
without the act; that is a breach` where it read `(party not yet known) MUST`; the JSON keeps
  `party: null` and adds `partyAsWritten: "theLandlord"` beside it (only when `party` is null;
  no existing field changes meaning, `format` stays 1). `theLandlord` and the Standing line's
  `Landlord OF "Ms Ng"` are one party under two spellings and do NOT compare by equality, which
  is what the marker is for. "(party not yet known)" survives for a key with no written form
  either, i.e. the join's own key, which `renderStep` words as "the group" anyway. **Not done
  for `FailureSummary`** (`MissedSummary`'s party, `PartyNamed Nothing`): those are read off a
  `Failure Reference`, which holds the party as a heap reference and nothing else; carrying the
  syntax there is a change to a wire type (`ValueLazy.Failure`, serialised by `ValueLazyJSON`),
  not to the log, and the placeholder stays on those two lines. Pinned: `DeonticStepSpec` case
  21 (the run-lest shape: a `MEANS`-named party, a missed deadline, no `LEST`; asserts the field
  and the step text on both the breach and a `Waiting` before any event, `Just "Alice"` for a
  literal, `Nothing` for a member, and that a forced name still wins over the source).
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
- **`BreachSummary` after the PR-A absorb (2026-09-16).** PR-A made a breach's reason a `Blame`
  zipper of `Failure`s (R-T3, EVERY-EACH-QUANTIFIER-SPEC §6.1.1), so the summary now describes the
  ANCHOR in its three scalars and carries the full list beside them: `bsFailures`, a list of
  `FailureSummary` (one per failed obligation, in operand / roll / list order), and `bsAnchor`,
  the anchor's index. A `FailureSummary` is either `MissedSummary party action deadline` or
  `DeclaredSummary named reason`, where `named` is a `NamedParty`: `NobodyNamed`, or
  `PartyNamed (Maybe Text)`. That tri-state is a review correction, not the absorb's first shape:
  the absorb wrote `Maybe Text`,
  which mapped a `BREACH BY` whose party the machine had not forced to the same value as a bare
  `BREACH`, and `l4 lts --steps` printed "(nobody named)" for a party the drafter had written —
  which party depended on incidental heap sharing (`BREACH BY LIST bob, alice`: Bob unnamed, Alice
  named because the obligation's `PARTY` shared her cell). Whether `BY` named anyone is a fact of
  the source and is known without forcing; who, only if forced — the two are now kept apart, in
  the text ("(nobody named)" vs "(party not yet known)") and on the wire (`named: Bool` beside a
  nullable `party`). The same review made the `joined` step's JSON carry what its text already
  printed — `winner`, `tieBreak`, and for a breached join `by` / `names` / `anchor` — and gave
  the list's unforced-`WITHIN` line an anchor-aware wording: "due by 35 (WITHIN 5 OF THE
  DEADLINE)", never "5 OF THE DEADLINE from now", with `dueAnchor` its own JSON field. None of
  these move a clock; nothing here waits on PR-B.

The write is `tellDeonticStep :: DeonticStep -> Eval ()` (`Machine.hs:364`), modelled on
`traceEval`: an optional `IORef (DList DeonticStep)` in the reader env (`EvalState.deonticLog`,
`:286`), off by default (R5). `DeonticLog` carries two counters beside the steps — per-site
activations for `nkActivation`, and an `EVERY` cast register `(action site, bearer) ↦ MemberOf`,
written when a family is assembled (`registerCast`, `:514`) and read when a member's obligation
meets the stream (`armNormKey`, `:454`) — because the `ValObligation` a member becomes has no slot
for its membership and adding one is a value-type change P2b declined. With the log off the
machine computes nothing for it, but it does carry state it never reads: a lazy `norm :: NormKey`
through the eleven `Contract*` frame records and `QuantCtx` (`ContractFrame.hs:88` onward), which
nothing forces; the re-offer mark `ev'reoffered` the machine already looked up at `Contract1` (a
`Bool` as P2b built it; the EVERY wave's LEST pass of 2026-09-16 re-typed it to the mark a
re-offered copy carries — §4.4 below, `ContractFrame.hs` `data Reoffered`), now
carried through six more records past `Contract5`, the only frame that consults it
(`ContractFrame.hs:143-188`); and a `pending :: Maybe DeonticStep` on `ResolvePartyFrame`
(`:324`), always `Nothing` when the log is off. One hot-path arm was also **restructured**, not
merely instrumented: the both-breached tie-break at `RBinOp2` (`Machine.hs:2136-2149`) went from
`vt <= vt' / otherwise / _` to `vt < vt' / vt' < vt / _` so the arm can expose which side won and
whether the tie-break chose it. Checked by hand: `vt == vt'` now falls through to the `_` arm and
picks the same operand the old `<=` branch did for both operators; the strict cases are
unchanged. The equality case is pinned by fixture 5; the strict cases rest on the golden suite.

**Call sites, as committed** (line numbers re-anchored **2026-09-17 on `caf1738dc`**, the merged
tree, after the merges of #399, #411 and #412 moved every site again; the 2026-09-16 table,
measured at reconciliation after `lts/p2b-bearer` moved every site below `Contract5`, was ~840
lines off by then — `barrierFail` was cited at 2649, where `startRollCall` now sits. The July
table above is staler still):

| Site                                    | `Machine.hs`                   | Step                                                                                                            |
| --------------------------------------- | ------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| `Breach` expression (`declareBreach`)   | 626–633 (from 1366, 2500–2503) | `Breached summary`: the explicit `BREACH`; no norm, no clock; called for no-`BY` and at `BreachBy`'s end        |
| `App1` on `ValObligation`               | 1476                           | `armNormKey`: the entry into the site; bumps `nkActivation`                                                     |
| `Contract1` / `ValNil`                  | 1898–1903                      | `Waiting`, clock peeked                                                                                         |
| `Contract5` expiry                      | 1961–2192                      | `Expired branch deadline`, built at 2120–2128; routed cases logged at `ResolveParty`, breach case at 2182       |
| `Contract6`                             | 2193                           | bearer refreshed                                                                                                |
| `Contract8` / `False`                   | 2211–2215                      | `PartyMismatch`, `WitnessedOnly`                                                                                |
| `Contract10`                            | 2230–2324                      | `EarlyAct` (2260, since #412), `Matched ToHence/ToLest/ToBreach` `Consumed` (2266–2270); `GuardFailed` (2323)   |
| `ResolveParty`                          | 2328–2334                      | the pending `Expired`, bearer filled, join progress worked out                                                  |
| `barrierFinish` (was `Barrier1`'s arms) | 3337, 3343                     | `JoinFailed ToBreach` once the verdict is decided, `JoinStalled` on a lapsed `MAY`                              |
| `RBinOp1` (the `ROR` short-circuit)     | 2561–2572                      | `Joined ValROr JoinFulfilled LeftSide` — the OR's commonest success path                                        |
| `RBinOp2` (six arms, one unreachable)   | 2585–2691                      | `Joined op note` via `joinedStep` (2791); the fulfilled-LEFT `ROR` arm at `:2679` is unreachable past `RBinOp1` |
| `startRollCall`                         | 2997                           | `armJoinKey`: the join's own entry                                                                              |
| `assembleQuantified`                    | 3032–3043                      | `registerCast` (distributive 3032, fork 3033, barrier 3043)                                                     |
| `fireBarrierHence`                      | 3450                           | `JoinReleased`                                                                                                  |
| `barrierFail`                           | 3494                           | `JoinFailed ToLest`                                                                                             |
| `barrierStateMissed`                    | 3524, 3530                     | `JoinExpired ToLest` beside the `LEST` push, `JoinExpired ToBreach` beside the breach                           |
| `patternMatchFailure`                   | 4014                           | `ActionMismatch`, `WitnessedOnly`                                                                               |

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
`ValObligation`. Nothing in `L4.StateGraph` was touched by P2b: B1's static half of the key was
still owed there _(and was paid 2026-09-16 — `labelSite`, §3.4's B1 block; the bearer follow-up
below did not touch `L4.StateGraph` either)_.

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

- `NormKey.nkBearerName :: Maybe Text` (`DeonticStep.hs:153`) is the party's `Value NF`
  rendered through `prettyLayout` — the same printer and shape `L4.Lts.Marking.renderLive` uses
  for `lnBearer` (`Marking.hs:415`) — so the two compare by `==`. `nkBearer` is **kept**, not
  repurposed: it is the key the cast register (`dlMembers`) is looked up by at `armNormKey`, and
  it exists before any field has been forced, which the name does not. `EventKey.ekPartyName`
  (`:220`) and `BreachSummary.bsBlameName` (`:387`) are the same rendering for the event's party
  and a breach's blame.
- The rendering is `peekWholeNF` (`Machine.hs:469`; it was `peekNF` until the merge of #412 on
  2026-09-17, which brought its own `peekNF :: WHNF -> Machine NF` — the PARTIAL reading a
  note's wording wants, `…` for an unevaluated part — so the all-or-nothing one was renamed;
  a name with an `…` in it compares equal to nothing): a `traverse` over the `Value` that reads each
  reference with `peekWHNF` and answers `Nothing` as soon as one is still a thunk, with
  `nfAux`'s depth cutoff. **It never forces.** `peekName` (`:483`) is its `prettyLayout`.
- Where it is read: `Contract8` (`:2200`, `naming party norm`) — the party equality at `Contract7`
  has just forced the fields (all of them on a match, up to the first difference on a mismatch),
  and the named key is carried into `Contract9`/`Contract11`/`Contract1` so `GuardFailed`,
  `ActionMismatch`, `Matched` and the following `Waiting` all carry it; `ResolveParty` (`:2328`)
  for the expiry path; `Contract5`'s no-`LEST` breach and `breachSummary` (`:584`) peek the
  breach's party cell the same way; `armNormKey` (`:510`) peeks at arming too, which is `Nothing`
  unless something earlier forced the fields. **The mismatch half of that parenthesis is a
  limit, not a footnote** (MEASURED 2026-09-16, below): the equality (`EqConstructor3`,
  `Machine.hs:1662`) answers `FALSE` at the first field pair that differs and never touches the
  rest, so a `PartyMismatch` step for a party whose _earlier_ field differed from the actor's has
  `nkBearerName = Nothing`, and so does the `Waiting` after it. Every party in the corpus and in
  fixtures 20 / case 6 has one field, where "the first difference" is also the last, which is
  why the first write-up read as if a mismatch named the party too. With the log off, `naming` is the old pure
  `bearing` behind one `asks`.
- Measured, `jl4-core/test/DeonticStepSpec.hs` fixture 20 (`:791`; it was fixture 18 until the
  merge of #412 on 2026-09-17, whose own 18 and 19 took the numbers): on fixture 6's barrier every
  member step names `Tenant OF "Alice"` / `Tenant OF "Bob"`, the landlord's `Landlord OF "Ms
Ng"`, and the event party alongside; on fixture 15's expiry the `Expired` step at
  `ResolveParty` is named and the join's own step and the `Breached` are not; at the barrier's
  **outset** (no event compared) both `Waiting` steps have `nkBearerName = Nothing` while
  `nkBearer` is still the `Tenant OF &…` form — the log did not force the fields for its own
  sake; a nullary `PARTY Alice` renders `Alice` both ways. The log-off equivalence test covers
  the new fixture.
- `confirmAct` (`WhatIf.hs:464`) now finds the candidate's own step by **site and bearer**
  (`:486`: `nkBearerName == Just name` for a `KnownParty`), and the most-specific-reason rank is
  **retired**. The candidate's own step is named for a narrower reason than "the comparison ran":
  the hypothetical act is _by_ the candidate's bearer, so its own obligation's party comparison
  matched, and a match forces every field; the other members' mismatch steps may carry no name
  (the limit above) and are not the ones the filter wants. An `UnforcedParty` candidate has no rendered name to compare and takes every step
  at its site as its own — such an obligation is not an `EVERY` member (the roll call forces
  every member), so its site has one bearer. Measured, `LtsListSpec.hs` case 6 (`:230`; case 7, the two-field limit, `:271`): a
  barrier of two with `PROVIDED t EQUALS bob` — Alice's act is `PassedOver GuardFalse` and the
  step that carried it has her name, the other member's look at the same event has Bob's; Bob's
  act advances. Cases 1, 4 and 5 and `LtsWhatIfSpec` are unchanged.
- The renderer (`List.hs:528`, `partyText`) prints the name when the log had it and the elided
  key otherwise, in text and JSON. Goldens: `every-run-example.txt`/`.json` moved **only** in
  party text — measured on the bearer commit itself, `git diff 351d0d9cc^ 351d0d9cc --
jl4/examples/lts/expected/every-run-example.txt | grep -c '^[-+] '` = 78 (39 pairs, every one
  carrying `Tenant OF`/`Landlord OF`), and 144 on the `.json` (72 pairs: 71 `"party"`, 1 `"by"`),
  checked by `diff` before blessing (the commit message's 72/71 were the first pass's counts,
  before the `by` lines named the fork's breach). (Re-pinned 2026-09-17: the command was first
  written against the branch names `lts/p2-followups...HEAD`, which have since moved under it —
  on the merged tree that pair diffs 0 lines. Against `origin/unstable` @ `d7581074c` the `.txt`
  still diffs 78 and the `.json` 148: the extra two pairs are the `"by"` lines `d8d67dc37`
  named later, and the #412 `at 20`→`at 14` clock is on both sides.);
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
  and, in `DeonticStepSpec.hs` fixture 20, a `bsBlameName` assertion on a record-shaped `LEST
BREACH BY t` (`forkBreachSrc`: the fork of `every-run-example.l4` with Bob never signing;
  `Breached` carries `bsBlame = Just "Tenant OF &…"`, `bsBlameName = Just "Tenant OF \"Bob\""`).
  `JL4_LIBRARY_PATH=$PWD/jl4-core/libraries cabal test jl4-core-test`: 651 examples, 0 failures
  as measured then, before the merge of #412; **671 examples, 0 failures** on the merged tree
  (`caf1738dc`, re-run 2026-09-17 — #412 brought its own specs in).
- Not changed: `reasonFor`'s middle fallback (`mapMaybe reason (map snd atSite)`) was reviewed as
  a duplicate of `own` for an `UnforcedParty` candidate. It is — but for a `KnownParty` it is the
  documented "no step with the bearer's name at the site" fallback, `atSite` is `let`-bound and
  traversed, not recomputed, and dropping it would change behaviour for a case the comment names.
  Kept.

### 4.4 The gotcha the animator must model: an event can be scrutinised twice — or more

Expiry re-offers the revealing event to the continuation, at most once, marked by store address
(`markReoffered`/`isReoffered`, `Machine.hs:767-778`; the rule is documented at `:1808-1839` and
again in `ContractFrame.hs:68-75`). It exists to keep recursive `HENCE`/`LEST` continuations with
non-positive deadlines terminating — the motivating case in the comment being
`x MEANS PARTY p MUST a WITHIN d LEST x`. _(Superseded 2026-09-16 by the `every/lest-anchor`
branch's adversarial pass: since a `LEST` counts from the missed deadline, one event can be past
several `LEST` windows, and it is now re-offered to every layer in turn, unconditionally (round 1
re-offered it only while the deadline strictly advanced and consumed it otherwise; round 2 found
that dropped a timely performance behind a `WITHIN 0` or an already-past anchored layer). The
only chain that does not end — a continuation that reaches itself with its deadline already
past — is refused by name after a bounded number of stalled hand-offs, not consumed —
`EVERY-EACH-QUANTIFIER-SPEC.md` §5.2.1, "The termination argument, re-read". An animator must
model an event scrutinised k+1 times for k expired layers, not at most twice, and a refusal as a
possible end of the walk.)_

_(The state layer's mark — BUILT 2026-09-19, `lts/p2-followups-2`. This does not answer R6,
which is §8's question of how the re-offered event is DRAWN, and stays open; what it closes is one
more gap in the data R6 will draw from, so that `dsScrutiny` is right for every re-look before
anyone decides the frames. Until then the mark was the act layer's only: a barrier whose
`ONCE … WITHIN` was missed hands its `LEST` the members' OWN cells from the first event past the
state deadline (`BarrierTrim`, 2026-09-16), and the `LEST`'s look at the completion that landed
after the deadline was logged as a fresh `WitnessedOnly`/`Consumed` — EVERY-EACH-QUANTIFIER-SPEC
§5.2.1's S3 made pairing those looks by stamp, party and action a consumer contract. Now it is a
mark: `dsScrutiny` reads `Reoffered` for
a look, anywhere under that hand-off, at a cell one of the barrier's members had looked at, and
stays fresh for a cell no member reached — including one stamped AT the last completion but
placed after it, which a "re-offered up to the last completion's stamp" watermark would have
marked though nobody had seen it (`DeonticStepSpec` cases 18 and 18b pin both). `markReoffered`
was not borrowed: it marks a copy the act layer allocates and Contract5 reads its stall count from
it, so putting it on the members' shared cells would have counted a state re-look as a stalled
hand-off under a `LEST` with a non-positive `WITHIN` (the refusal one layer earlier) and leaked
to every other scanner of the stream (an `AND` sibling). The state layer's mark
is the log's own — `dlMemberLooks`, every barrier member's look keyed by join and cell address,
and `dlRelookScope`, the joins whose state-`LEST` hand-off the machine is inside, entered by
`barrierStateLest` and left by the `RestoreCurrentParty` frame that hand-off already pushes — read
beside `ev'reoffered` at Contract1 into `ev'relooked`, which the machine never consults; with the
log off nothing is written, read or pushed, and the goldens are unchanged. Not marked, and said so
in `DeonticStep.hs`: a sibling operand's look at the same stream (no hand-off), and the HENCE's
stream, which starts after the first-in-roll-order completion at the latest stamp.)_

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
- **Symboleo's lifecycle names**, read from the primary text 2026-09-16 (R8; the exact list is
  in §4.2a's ANSWERED block). `Lapsed` (§4.2a) is **ours**, confirmed — R12.

### 4.7 Layout — the section revision 1 did not have

The word "layout" appeared once in revision 1, in a ruling the review then overturned. This is
the corrected treatment, and it is short only because the problem is now bounded, not because it
is small.

**The facts.** `StateGraph` has no coordinates (`:82-147` is all `Text` and `Int`), and the
shipped DOT renderer delegates positioning entirely to GraphViz (`GV.printDotGraph`, `:552`) —
a facility unavailable in the browser, where K6 and §2.4 put the drawing. So P2 must lay out its
own picture, and the two-plane form is **strictly harder** than P1's: norm-plane places plus
constitutive links that cross between planes.

> **2026-09-16:** "unavailable in the browser" stopped being true on `lts/p2g-render`: GraphViz is
> in both hosts via `@repo/state-graph-render` (viz.js), and its `json`/`plain`/`xdot` outputs
> expose every coordinate it computes (`instance().formats`, `renderJSON`). **B3 stands on the
> coordinate-ownership argument, not on unavailability** — see §4.8's LANDED block of the same
> date for the argument as corrected.

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

- **Haskell serves structure**: rank, lane/band, junction kind, plane assignment, and — now that
  B2 has landed (2026-09-16) — a **feedback-edge set** so the ranking can run on the DAG that remains after cycle
  edges are set aside, with cycle edges drawn as explicit back-arcs. This is the standard
  Sugiyama first phase and it is the honest answer to `P-CYCLE`; it is also the piece P1 declined
  to build and reported instead.
- **TypeScript assigns pixels**: the browser turns ranks and bands into an SVG, and owns the
  scrubber, the highlight and the animation.

> **RULED 2026-09-21 — the width that prompted a look at layout was label geometry, and B3 was not built.**
> The measurement that prompted it: `dot -Tplain | head -1` on the four §7.3 proxy artifacts at the merge base `392ba5aa9` gives `promissory-note/B.dot` a canvas of **28.463 × 6.3256 inches**, against 6.1379, 4.7335 and 4.7032 for `contracts`, `every-run-example` and `tenancy`.
> Six nodes — a chain `0 → 1 → 2 → 4` with one back edge `1 → 0` and two terminals — and a ranking with nothing wrong with it.
> What was wide was three edge labels of **199, 173 and 141 characters** (`1 -> 0`, `2 -> 3`, `4 -> 3`), each restating the name of its own source node — all three of those nodes read `` `The Borrower` must pay monthly installment to ... ``.
> A Haskell ranker would have produced the same 28 inches.
> The note's node and edge sets are identical before and after this branch (six nodes; `0 -> 1`, `0 -> 3`, `1 -> 0`, `1 -> 2`, `2 -> 3`, `2 -> 4`, `4 -> 3`, `4 -> 5`), so only the captions moved, and that alone brought the canvas to 9.9125 × 9.5317.
> So the layout work taken was **label geometry** (a 36-column wrap, `L4.StateGraph.Dot.labelWidth`, `Dot.hs:471-472`) and **duplication removal** (an edge drops the party, modal and act its own source node already says, `Dot.hs:398`), and **no ranker was written**: `grep -rniE 'feedback[- ]edge' jl4-core/src ts-shared` is empty, measured 2026-09-23.
>
> **The coordinate-ownership argument is not retracted.**
> It is untouched by this, and it is still the reason to build B3 if and when a consumer needs coordinates rather than a picture: nothing on this branch computes a rank, a band or a feedback edge, and GraphViz still owns every position the shipped renderer draws.
>
> **Measured 2026-09-23, before (`392ba5aa9`) and after (`ab6ecc4af`).**
> "Longest line" is the longest single rendered line of any label in the file, which is what GraphViz sizes a box by; "whole" is the same label with its `\n` removed; the canvas is `dot -Tplain`'s first line.
>
> | `etc/lts-reader-proxy/<c>/B.dot` | longest line | whole | canvas (in)         |
> | -------------------------------- | ------------ | ----- | ------------------- |
> | `contracts` before               | 43           | 43    | 6.1379 × 6.3256     |
> | `contracts` after                | 29           | 42    | 7.849 × 6.4818      |
> | `every-run-example` before       | 44           | 57    | 4.7335 × 3.7804     |
> | `every-run-example` after        | 36           | 54    | 5.3253 × 4.2215     |
> | `tenancy` before                 | 42           | 51    | 4.7032 × 3.7804     |
> | `tenancy` after                  | 34           | 109   | 5.3418 × 4.9259     |
> | `promissory-note` before         | 199          | 199   | **28.463 × 6.3256** |
> | `promissory-note` after          | 42           | 137   | 9.9125 × 9.5317     |
>
> Read honestly: the longest line falls on all four, and no line now exceeds 36.
> The canvas is _wider_ on the other three, because two clauses were added where an act was ambiguous — the window moved onto the node that carries it, and a rule that binds an open pattern variable says so on its own line — so `tenancy`'s whole-label figure grows 51 → 109 while its longest line falls.
> That is bought width, not a wrap regression, and it is the note — the artifact that prompted the section — that collapses, from 28.463 wide to 9.9125, paying 6.3256 → 9.5317 in height for it.
> One baseline is not what it looks like: `contracts/B.dot` at `392ba5aa9` predated a source edit, so its 6.1379 is measured on a stale artifact; the same rule's `jl4/examples/state-graphs/aContract.dot` at that commit gives 5.7943 × 6.3256.

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

_(Reconciled 2026-09-16, after `lts/p2g-render` and `lts/b1-b2-loops` merged beside this: the
`+page.svelte` and `extension.mts` anchors in this block are of the tree before the render track
rewrote both files, and some of the code they point at — the unconditional `rightPaneView =
'ladder'`, the `<pre>`-only pane — no longer exists; they are left as the record of what the
render track changed. The `StateGraph.hs` anchors below are re-anchored in place. Of the four
"not built" items at the end, the first two — the picture and live refresh — landed the same
day; the next LANDED block is their record.)_

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
   with a **Copy DOT** button (the copy goes through `vscode.env.clipboard`). **No renderer**
   _(until 2026-09-16, next block)_. Measured 2026-09-15: `grep -i "graphviz\|viz\.js\|d3-graphviz\|hpcc-js\|@viz-js"` over
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
Same pass: the names of the two hand-over arms, the bare-MAY gap from the extractor's own note, and the web-host pane eviction above.
Those two arms go through `wireTarget` since B2, and since 2026-09-21 they are named `HENCE of <obligation>` (`StateGraph.hs:1162`) and `LEST of <obligation>` (`:1191`) rather than `next` and `failure`; the page says so at `STATE-GRAPH.md:284-287`, and the bare-MAY note is now `StateGraph.hs:1196-1239`.
Line numbers in this paragraph were re-measured 2026-09-23 on `ab6ecc4af` and will move again; the names and the function are what to search for.

**Not built, and what would make it true** _(as of 2026-09-15; the first two items landed
2026-09-16 — the next LANDED block)_.

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

#### LANDED 2026-09-16 — in-pane rendering and live refresh (P2g's first two "not built" items), on `lts/p2g-render`

Three design memos (A: vendor Graphviz-in-wasm; B: SVG from Haskell reusing P1's `layoutDiagram`;
C: a dependency-free layered layout in TypeScript) were written and judged on 2026-09-16; A won,
22 points to C's 18 and B's 17, on fidelity and effort. **The memos and the scoring are not in the
tree**: they were written in the session that built this (`lts-diagrams-2`) and the numbers are
quoted from it, so a reader of this tree cannot re-check them; what the tree carries is the
measurement in the "MEASURED" paragraph below. This block records what was built. Line numbers
are of the tree this block was committed in, re-anchored 2026-09-16 by the review fix-up commit
that follows the first. "Landed" means committed on the branch; it is unpushed and has no PR.

**This is the read-only picture, and only that.** It draws the DOT the lens already returned. It
does not change ruling B3 (§4.7): _Haskell serves structure (rank, feedback-edge set), TypeScript
assigns pixels_ is unchanged and still pending. The reason is **not** that Graphviz's coordinates
are out of reach — they are not: the vendored `@viz-js/viz` 3.30.0 lists `json`, `json0`, `plain`,
`plain-ext`, `xdot` and `xdot_json` among `instance().formats`, exports `renderJSON`
(`node_modules/@viz-js/viz/types/index.d.ts:74`), and `render('digraph{0->0;0->1}', {format:
'json'})` returns `_draw_` point arrays (checked 2026-09-16; an earlier draft of this paragraph
said the opposite and was wrong). The reason is that the scrubber, the highlight and the
animation (§4.1, K6) need a coordinate model **TypeScript owns**: stable place positions across
edits, ranks and a feedback-edge set that carry L4 meaning (§4.7), and edge geometry a token can
be moved along. Graphviz gives spline control points that it re-lays-out from scratch on every
input and moves between its own releases (`render.test.ts` asserts no coordinate for exactly this
reason). **P2 must not build on viz.js's coordinates**; when the token game arrives it replaces
this renderer behind the wrapper below rather than decorating its output. The wrapper's single
export is the seam.

**The dependency.** `@viz-js/viz` 3.30.0 (MIT; embeds Graphviz 16.0.0 under EPL-1.0 and Expat),
pinned without a caret, declared **only** in the new workspace
`ts-shared/state-graph-render/package.json`; `ts-apps/vscode` and `ts-apps/jl4-web` depend on
`@repo/state-graph-render` via `"*"` like `@repo/viz-expr`. Zero transitive dependencies, so the
lockfile delta is **29 insertions, 0 deletions** (`git diff --stat package-lock.json`), regenerated
with `npx npm@11.11.0 install` on Node 26.4.0 and re-verified with `npx npm@11.11.0 ci` → "added
1207 packages", exit 0. The renderer is one JavaScript file with the wasm embedded as a string:
no `.wasm` asset, no worker, no `fetch`. The EPL attribution is in `ts-apps/vscode/README.md`
("Third-party notices"), and viz.js's `/*! … Graphviz … */` banner survives esbuild's minifier —
`grep -c "Viz.js 3.30.0" out/extension.js` → 1.

**The wrapper.** `ts-shared/state-graph-render/src/index.ts`: `renderStateGraphSvg(dot):
Promise<string>` (`:82`) — one lazily-instantiated Graphviz per process, `render(dot, {format:
'svg', engine: 'dot'})`, the XML prologue stripped, Graphviz's `agerr` messages surfaced as a typed
`StateGraphRenderError`, and the canvas-sized `<polygon fill="white">` removed (`stripBackground`,
`:114`) so the picture sits on the host's theme; `graphvizVersion` (`:37`) re-exported so a bump
is a visible diff. Swapping in `@hpcc-js/wasm-graphviz`, or a TS layout, touches this file and no
host.

**MEASURED 2026-09-16 — is it the picture `dot` draws?** The first commit's module header said
the renderer had been "measured on every corpus graph"; nothing in the tree recorded that, so it
was measured and recorded. `etc/state-graph-corpus-diff.mjs` (new; local evidence, not CI — it
needs a system `dot`) renders every `.dot` under `jl4/` and `doc/` — the 37 goldens in
`jl4/examples/state-graphs/` and the four figures in `doc/reference/regulative/figures/`, 41 files
— through the wrapper and through the system `dot -Tsvg`, and compares counts of `class="node"`,
`class="edge"`, `<ellipse>`, `<polygon>`, `<path>`, `<text>` and the sorted set of `<title>`s.
Coordinates are not compared. `node etc/state-graph-corpus-diff.mjs` → `viz.js Graphviz 16.0.0
vs system "dot - graphviz version 14.1.0 (20251206.1807)": 41 same, 0 differ, of 41`. The first
run reported 41 differ, every one by exactly one `<polygon>`: the white canvas the wrapper strips
and the system output keeps; the script now strips it from both. So the doc page's "the same
picture the `dot` program would draw" holds structurally across two major Graphviz versions, and
the page now says which version is built in.

**VS Code host.** Rendering happens **in the extension host**, not the webview
(`src/state-graph-panel.ts`, `show` `:43`, `refresh` `:73`, `markStale` `:85`), and the finished
`<svg>` is inlined into the document (`src/state-graph-html.ts`, new, `vscode`-free so it can be
unit-tested). The webview CSP is **byte-identical** to P2g's — `default-src 'none'; style-src
'unsafe-inline'; script-src 'nonce-…'` (`state-graph-html.ts:28`), no `wasm-unsafe-eval`, no
`img-src` — and a unit test pins it. Inline SVG is DOM, not a fetched resource; Graphviz writes
presentation attributes, not `style=`; and every label is XML-escaped by Graphviz (a rule named
`<script>` arrives as `&lt;script&gt;`, tested). The DOT `<pre>` and **Copy DOT** stay under a
`<details>` fold (`:89`). Dark themes: with the white polygon gone, the title, edge labels and
`stroke="black"` strokes are recoloured to `--vscode-foreground` by CSS (`:68-70`); node-label text
keeps Graphviz's black because the node fills are pastel in every theme. An `update` whose render
failed (no `svg`, an `error`) keeps the last picture **dimmed** under the error text
(`#picture.faded`, `:61`; toggled `:117`) — deliberate, so a stale drawing is not read as current;
the `stale` notice, by contrast, keeps it undimmed because that picture _is_ the last good one.
Extension bundle, measured
with `npm run bundle-esbuild` before and after: `out/extension.js` **984,946 → 2,527,575 B**
(+1,542,629; gzip 276,473 → 771,819, +495,346). It is in the main bundle, not lazy: the bundle is
`format: 'cjs'`, and esbuild only splits ESM.

**Web host.** `state-graph-panel.svelte` loads the renderer with `await import()` on first use
(`:31-32`) and inlines the result with `{@html}` (`:80`); jl4-web sets no CSP anywhere (checked
again: `app.html`, `svelte.config.js`, `nix/`), so nothing to change. Vite emits it as **its own
chunk, dynamically imported and not `modulepreload`ed** from `index.html`: `_app/immutable/chunks/
Cfh5j4hd.js` 1,350,762 B (`.br` 388,174; `.gz` 482,023). Whole-build JS: 17,403,620 → 18,756,650
B across 30 → 31 files — the 14.4 MB Monaco chunk is still the largest thing on the page.

**Live refresh — built in both hosts, one middleware branch and one last-target slot each, the
shape P2g predicted.** The slot is `lastStateGraphTarget` (`extension.mts:106`) /
`stateGraphTarget` (`+page.svelte:90`), filled by the click's branch (`extension.mts:363`); the
branch is in `didChange`, after the ladder's own refresh (`extension.mts:427-469`,
`+page.svelte:900`). The refresh does **not** go through `vscode.commands.executeCommand`: the
click's branch reveals the pane, and a keystroke must not, so the refresh sends
`workspace/executeCommand` straight to the server (`ExecuteStateGraphRequest`,
`extension.mts:120`; `+page.svelte:98`, sent by `debouncedStateGraphRefresh` `:193`, debounced
150 ms like the ladder's). **Replies are guarded by a generation counter** (`stateGraphGeneration`,
`extension.mts:116`, `+page.svelte:95`), bumped on every click, every refresh sent and every
"edited away"; a refresh applies its reply only if the counter is still what it captured. Without
it — the first commit — a click on a _different_ rule while an edit's request was in flight let
the slower reply win, retitling the pane to the old rule while the slot pointed at the new one;
VS Code has no debounce, so an edit burst could also deliver replies out of order. Found in
review, not by a click. What the two
producers disagree on (§4.8's table) bites here: the wasm lens addresses by **name**, so its args
are re-sent unchanged; the LSP lens addresses by **exact `SrcPos`**
(`L4.StateGraph.Lens.stateGraphAtPos`), so the position must be moved along under every edit.
`trackSrcPos` (`ts-shared/jl4-client-rpc/state-graph.ts:59`) does that with the LSP's incremental
semantics — an edit ending at or before the position shifts it, one covering it returns `null` —
applied to every `contentChanges` in the same `didChange`, before the debounce. On `null`, or when
the server refuses ("No regulative rule starts at that position"), the slot is cleared and the pane
keeps its last picture with a stale notice; the next click re-arms it. **No Haskell changed** — a
name-addressed LSP form would have been cleaner and is the obvious follow-up if the tracker proves
too fragile.

_Corrected 2026-09-16 (doc-claims review of the follow-ups merge)._ As first landed, **both hosts
also let go on a transient parse error**, which the paragraph above did not say and the doc page
contradicted ("the pane follows, the same way the decision graph does"). Measured: a file ending
`… HENCE (PARTY Bob MUST bar WITHIN 2) LEST` with no arm yet is a parser error (`l4 state-graph`
exit 1, `Source: parser`); on that input the LSP's `use TypeCheck` is `Nothing`
(`Rules.hs` `GetParsedAst` returns `Nothing` on `Left errs`), `stateGraphAtPos` answers "Could not
check …" (`Actions.hs:237`), and VS Code's `catch` cleared `lastStateGraphTarget` for _every_
refusal, so nothing re-armed until the next click; the wasm side likewise, since `l4StateGraphByName`
returns `{ error }` on `checkWithImports`'s `Left` (which includes parse errors, `API.hs`), the
transport collapsed that to `null`, and `+page.svelte` cleared `stateGraphTarget` on `null`. The
ladder's autorefresh on the same `Nothing` returns quietly and keeps following (`runMaybeT`,
`Actions.hs`). Fixed in TypeScript only: `stateGraphTargetGone` in
`ts-shared/jl4-client-rpc/state-graph.ts` sorts a refusal into _gone_ (the server's "No regulative
rule starts at that position", or the shim's `notFound: true`) versus _transient_ (everything
else — "Could not check", a bare `{ error }`, a dropped socket); both hosts clear the slot only on
_gone_, and on _transient_ keep the target and the picture and post "Waiting for the file to parse"
(cleared by the next successful `refresh`). The wasm transport now passes `{ error, notFound }`
through instead of `null` so the page can tell the two apart. Four `node --test` cases in
`state-graph.test.ts` pin the classifier (22 tests in that rig now). The LSP still signals the
difference only by message text; an error code on `defaultResponseError` would be the tidier
follow-up and would touch Haskell.

**The web-host eviction is resolved as "survive", not "redraw over".** P2g measured that every
edit's ladder auto-refresh set `rightPaneView = 'ladder'` unconditionally. Now it does so only when
the ladder was asked for by a click (`args.length > 1`, i.e. `[verDocId, name, simplify]`) or the
pane is not showing the state graph (`+page.svelte:864`); the auto-refresh `[verDocId]` redraws
the ladder in place behind the state graph, which is being redrawn from the same edit. The
`'inspector'` view's eviction is untouched.

**Tests.** `ts-shared/state-graph-render/test/render.test.ts` (`tsx --test`, the `ladder-svg`
pattern): 8 tests — `graphvizVersion === '16.0.0'`; prologue and white polygon gone, 4 nodes/4
edges intact; `every-barrier.dot` has 6 `<ellipse>` (two per terminal), 2 × `stroke="#dc3545"
stroke-dasharray="5,2"`, and two `<text>` lines on edge1 with `ONCE ALL HAVE` second; a
**self-loop fixture** `test/fixtures/self-loop.l4` (HENCE back to the rule's own name, DOT written
by `l4 state-graph`, `0 -> 0` — the task's cycle witness) renders the loop in HENCE green with its
label; RAND/ROR diamonds with `ALL OF`/`ONE OF` (hand-written DOT, so it still passes; the
emitter has said `RAND: ALL OF` / `ROR: ONE OF` since 2026-09-21, and this fixture is no longer
representative of it); XML escaping of `<img onerror>` and `<script>`;
bad DOT rejects with Graphviz's `syntax error`. `ts-apps/vscode/src/unit-tests/state-graph.test.ts`
(`node --test`, the existing rig): 12 tests — the CSP string, the inlined picture and the
`<details>` fold, heading escaping and `</`-safe JSON, the error document, the dimmed-under-error
update (added by the review fix-up; it pins the CSS rule and the two lines of the message handler,
since the webview script has no DOM to run in here), and `trackSrcPos` across six edit shapes
(below/above/at the DECIDE, same-line column shifts, a covering delete, two changes in order). Root
`npm run test` → 28 tasks successful, `state-graph-render` 8/8, `l4-vscode` 18/18 (6 pre-existing
plus 12); `npm run build`, `lint`, `format:check`, `check` all green; `doc/test-docs.sh` → 1518
links, 103 `.l4` files, 254 linked, 0 errors (re-run after the fix-up: same counts). The
generation guard has no unit test: both hosts' refresh paths live inside the language-client
middleware, which neither rig instantiates; it was read, not clicked. The Haskell side is
untouched, so `StateGraphLensSpec.hs` was not extended and no cabal target was rebuilt.

**Doc.** `doc/reference/regulative/STATE-GRAPH.md` no longer says the pane shows source, no longer
tells the reader to paste DOT into a GraphViz viewer, and no longer describes the snapshot/eviction;
it says the pane redraws, what happens when the rule is edited away, the transparent background
and dark-theme recolouring, and that there is no zoom or pan. `ts-apps/vscode/README.md` gains the
feature line and the third-party notice.

**Not built, and what would make it true.**

- _A human click, in either host._ Still nobody. This session tried: `jl4-lsp ws` on `:5007`
  plus `vite dev` on `:5173`, driven from Chrome — the page's `MonacoLanguageClient` construction
  throws `Default api is not ready yet, do not forget to import 'vscode/localExtensionHost'`
  before any lens can exist, **identically with this branch's `+page.svelte` and with
  `0139c6c5`'s (`lts/p2-followups`, the base) swapped back in** — measured by copying the two
  edited files under `ts-apps/jl4-web/src/` aside, `git show 0139c6c5:… >`, reloading, and
  restoring; **two files reverted, the new workspace dependency in `ts-apps/jl4-web/package.json`
  and the lockfile stayed in place**, so the experiment clears the Svelte edits, not the
  dependency change (a `monaco-vscode-api` init error is not plausibly a dependency's doing, but
  the swap did not test that). The failure is pre-existing in this dev setup and not this
  change, and it blocks the click here. What was exercised in Chrome instead, by importing the built
  wrapper into the loaded page: the self-loop fixture rendered in **31.6 ms** with 6 ellipses and
  the `0 -> 0` edge, i.e. Graphviz-in-wasm instantiates and draws in this browser. The VS Code
  path was exercised only as far as an esbuild `cjs` bundle of the wrapper under Node (renders
  the fixture in 21 ms); nobody opened VS Code. Pressing the lens in each host is still the
  integrator's first act.
- _The wasm build._ Unchanged from P2g: no `wasm32-wasi-ghc` here, so `l4_state_graph_by_name`
  has still never been compiled or executed on this machine; CI's `wasm-build` job compiles it.
- _Pan/zoom, and a name-addressed LSP refresh._ Neither; the doc page says so for the first, the
  paragraph above for the second.
- _The picture P2 actually needs (B3)._ Unchanged and pending, as the first paragraph says.

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
— so the next field the constructor grows is a type error there rather than a silent drop _(and it
did: the `AFTER`/`BEFORE` track grew `opens` between `action` and `due` on 2026-09-16, and the
pattern has been the eight-field `(MkDeonton _anno subject action opens due mJoin hence lest)`
since; the seven-field quotation is the shape of 2026-09-15)_; the
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
barrier-joined `MAY`'s lapse as a LEST arm to Fulfilled. **Corrected 2026-09-16:** the review's
§A also said a fork's `MAY` "carries the real HENCE per member, so a lapsed member does route
there", and the first cut drew it so. Re-measured by `lts-diagrams-2` and reproduced: nobody
approves, chair publishes anyway → FULFILLED under the fork as under the barrier; the continuation
arises only from an act. The lapse arm now goes to Fulfilled under either join, the two tests that
had pinned the reviewer's reading were flipped, and `modals-may-fork` re-goldened. A reviewer's
sentence is a claim like any other; the pin that caught nothing was the pin written from it. (2) The fork's interrupting timer cancels
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

The measurement behind that correction originated on `lts/p2a-remeasure` as `11199a16` (the two `#TRACE`s on `jl4/examples/ok/every/run-modals.l4` §7, goldened in `ok/every/tests/run-modals.golden`, and P2A-TOKEN-SIM-BASELINE.md §3.7) and was folded into legalese/l4-ide#395 as `d544ed22`, which also emits `P-FORK-CANCEL` on the `MAY` fork.

#### LANDED 2026-09-19: the fork is a multi-instance sub-process, and E is no longer isomorphic

The reviewer's finding on E — that a barrier and a fork were "isomorphic automata with different
labels, not different automata", so nothing reasoning over structure could tell them apart — is
**now false, deliberately.** The BPMN exporter encloses a fork's obligation, its deadline and its
whole continuation in a `<subProcess>` carrying the multi-instance marker, where a barrier keeps
the marker on the task. One copy outside the join versus _n_ copies inside it: the distinction is
structural in the emitted artifact, which is the first place in this arc that it is.

What that discharges, and what it does not:

- **`P-FORK` and `P-FORK-CANCEL` are discharged.** They now exist only as a refusal: `addForkScope`
  files `P-FORK`, naming which check failed, when it declines to enclose a continuation it cannot
  (shared with a path outside the fork, leaving for a third destination, or more than one entry).
  A fidelity note has to describe the file that was emitted, so they moved out of `quantifierNotes`
  and into the pass that knows which of the two shapes was drawn.
- **The empty cast, which none of the earlier notes reached.** `P-FORK`'s wording was an n≥1
  framing. At n=0 the loss ran the other way: a multi-instance activity over an empty collection
  completes at once and its outgoing flow IS taken, which is right for a barrier and MANUFACTURED
  an obligation for a flat fork. With the continuation inside, there is no instance to run it.
  `etc/check-bpmn-soundness.mjs` plays the emitted goldens at n ∈ {0, 2} and both are SOUND.
- **New in their place:** `P-FORK-JOIN` (a sub-process regroups at its end and a fork does not —
  immaterial while each continuation ends inside its own instance, material the moment one feeds
  shared downstream flow) and `P-FORK-LANES`.
- **Class (d) in `etc/bpmn-kie-baseline.txt` is closed**, RESULT 12 → 4. The exporter now emits the
  collection, and jBPM accepts all eight quantified goldens. Two measurements worth keeping: a
  `<dataObject>` is the vanilla BPMN 2.0 spelling and jBPM refuses to PARSE it (bpmn-moddle accepts
  it silently), where a process `<property>` is accepted by both; and an unseeded `COMPLETED` on
  these rows means the empty cast ran, not that a member's obligation did — seeded with three
  members, `MUST Receipt` fires three times where the flat drawing fired once.
- **The second half is still gated where it was.** Nothing here touches `barrierFinish`: the
  residual still does not carry the join line, so `markingOf` still cannot build the join place.
  P2h's second half remains owed, and remains a runtime change rather than a drawing rule.

**The first cut of this relocated `P-FORK-CANCEL` instead of discharging it, and the review caught
it.** The escalation left the instance without interrupting its siblings, correctly — and then
reached the top-level ERROR end, which ends every active thread in the process, including the
instances still running. A duty another member had already earned vanished one flow later.
`run-fork.golden` keeps exactly that duty on the matching trace, so the loss was verbatim the old
note's: "every continuation spawned before the timer fired". Worse, the emitted file asserted the
opposite in its own `<documentation>` on the boundary — "every other member remains bound" — and
this spec, `EVERY.md` and the fixture README all said "discharged" in four places.

**The first fix for it was also wrong, and in a more instructive way.** It demoted the two shared
terminals in place — the breach end losing its `errorEventDefinition`, the fulfilled end losing the
name `Fulfilled` — guarded by "only where the fork is their sole feeder". That is correct on every
golden in the corpus, and wrong the moment anything else breaches. Probed deliberately, because the
guard was the part I distrusted: a `RAND` of a fork beside a `PARTY` obligation, both `LEST BREACH`,
which is `ok/every/rand.l4`'s shape with one token changed. The guard did not fire and the file kept
**409** markings that could complete only by terminating. A correctness cliff hidden behind a
condition that happens to hold everywhere you have looked is worse than the bug it patches, because
the goldens report it fixed.

So the fork gets **its own** top-level terminals — `EndGroup_<n>` ("every run has ended") and
`EndBreach_<n>` — and the shared ones are dropped when nothing else feeds them. There is no
condition left to get wrong. On the probe the fork's contribution goes to zero and 113 remain,
which are the landlord's own breach terminating under `RAND`. That is pre-existing and **already
declared** — `offering.fidelity.txt`'s `P-NOJOIN` says a branch reaching BREACH "abandons its
siblings rather than waiting for them" — but it is a declared LOSS, not a faithful drawing, and the
difference matters because the first draft of this section called it faithful. L4 does not abandon
the sibling conjunct: `ok/every/run-blame.l4` §8 is a `RAND` whose left operand breaches at once and
whose right is still evaluated to its deadline and named separately in the verdict
(`run-blame.l4:16`: "when both sides are lost, both sides' failures are named, left first"). So the
113 are real loss, correctly attributed to `P-NOJOIN` and correctly out of scope here. One wording
gap worth knowing: `P-NOJOIN`'s "siblings" reads as the other `RAND` branches, and nothing in it
extends to _every instance of a multi-instance scope inside one of them_, which is what it now also
covers.

Measured, and the numbers separate the defect from the faithful case cleanly — markings that can
complete ONLY by terminating, at two instances:

| golden                           | before | after |
| -------------------------------- | ------ | ----- |
| `tenancy-fork`                   | 121    | 0     |
| `modals-may-fork`                | 108    | 0     |
| `modals-shant-fork`              | 78     | 0     |
| `modals-must-fork-join-deadline` | 78     | 0     |
| `tenancy-fork-beside-party`      | 409    | 113   |
| the four barrier goldens         | 1–2    | 1–2   |

A barrier failing as a group and ending everything is `ONCE ALL HAVE`, so 1–2 is right there and
unchanged.

**The fifth row does not go to zero, and belongs in the table for exactly that reason.** It is the
`RAND` shape, so its remaining 113 are the landlord's own error end, which is `P-NOJOIN`'s declared
loss and not this branch's to fix. Listing only the four that reach zero would have read as "every
fork goes to zero", which is the kind of table that makes a later reader think a regression has
appeared when they meet the fifth. There are **five** fork-bearing goldens, not four. Two notes come out of the demotion: `P-FORK-BREACH-UNMARKED` (advisory) and
`P-FORK-VERDICT` (lossy — the rule's verdict is the fold over members, which BPMN cannot express
without inventing data, so it is declined rather than drawn wrongly; the terminal is named "every
run has ended").

**What is worth keeping about how this was found.** Not by the gate. The gate reported the number
on every single run, under `info`:

> `info  121 marking(s) can reach completion ONLY by terminating`

and scored the file SOUND, which it was, because terminating is a legitimate way to complete. The
line was printed, read, and not connected — by me, in this session, twice. It took an adversarial
reader asked specifically about concurrency semantics. A gate that tells you the truth in a
severity class nobody triages is a gate you have not finished building.

One finding of the checker's own, recorded because it is the shape §5's gate arguments are about:
teaching `check-bpmn-soundness.mjs` to expand scopes made its synthetic join wait for one token per
(instance × arrival flow) rather than one per instance, so any interior with two ways to reach its
end deadlocked **in the model** while the file was correct. It was found by the exporter's own
`modals-may-fork` golden coming back UNSOUND, not by inspection, and the checker looked like it was
working while it did — it produced a deadlock witness naming real flows. Fixed with one XOR
"instance finished" gateway per copy; pinned by `jl4/examples/bpmn/sound/mi-subprocess-two-ways-to-done.bpmn`,
which was verified by reverting the fix and watching it fail.

#### LANDED 2026-09-21: the blame set, declared as `F6`

The dated line `EVERY-EACH-QUANTIFIER-SPEC` §6.1.1 asked this section for, under _"Owed downstream, not done here"_.

**A barrier's breach end event names no member, and now says so.**
Since R-T3 (built 2026-09-15, §6.1.1) a failed barrier's `LEST` is handed a non-empty LIST of failures rather than one party — one entry per failed obligation, undeduplicated, each entry naming what was failed and not merely who (`Failure`/`Blame`/`ReasonForBreach`, `jl4-core/src/L4/Evaluate/ValueLazy.hs`).
The diagram has one end event for the whole group, and BPMN has no shape for a set of parties on an end event, so the loss is a loss of the notation: `F6`, `Lossy`, filed on the breach end event by `quantifiedBreachNote` in `jl4-core/src/L4/Bpmn/Lower.hs`.

Measured: it moves **three** of the sixteen BPMN goldens and no others — `tenancy-barrier` (`End_3`), `modals-shant-barrier` (`End_2`) and `modals-must-barrier-both-deadlines` (`End_2`).
The fourth barrier golden, `modals-may-barrier`, does **not** gain it, and that is the check that the guard discriminates: its `EVERY` is a `MAY` with a `HENCE` and no `LEST`, so the group has no breach terminal at all — the `End_3 "Breach"` in that file belongs to the chair's own `PARTY` obligation.
`modals-must-barrier-both-deadlines` does gain it despite having no written `LEST`, because a `MUST` whose deadline passes breaches and the state graph builds the arm.

**Repaired twice on the day it landed, after two rounds of review, in THREE places where the note was wrong about its ELEMENT rather than about the loss.**
All three had the same cause and now have the same answer: the note is built in the findings pass (`barrierBreachFindings`), which reads the emitted file, instead of in the chain pass, which had to predict it.

1. **Filed twice.** Keyed on the terminal and built once per state that reaches it, so two barriers whose `LEST` arms converge on one breach end filed it twice, byte for byte. It is now filed once per END EVENT. (`dedupNotes` also hides an exact repeat and stays as a backstop, but is no longer what makes this single — a dedup that hides a double emission would have gone on hiding it for any two copies that differed in a word.)
2. **Claimed a shared terminal was the group's.** Under `RAND` one operand's breach is the whole contract's, and a barrier whose `HENCE` obliges somebody who can breach in turn shares the terminal too. That was live in a committed golden — `tenancy-barrier`'s `End_3` is reached from `Boundary_0` (the tenants' deadline) and from `Boundary_1` (the landlord's). The note now NAMES the other arms and the lane each sits in ("`Boundary_1` (theLandlord) also ends at this very event"), counted on the emitted flows rather than on the state graph, and its `lost:` says the larger thing the first repair still left out: not only which member fell short, but whether a member fell short AT ALL rather than the landlord. Two group obligations converging is its own overclaim — an event two groups reach is not "the whole group's" either — and the note says it cannot tell which group, naming both arms.
3. **Named an element the file does not have.** The id was derived as `End_<state id>`, which is the terminal's name only outside a fork's scope: a barrier nested in a fork's `HENCE` has its terminal absorbed by `addForkScope`, the arm re-pointed to `EscScope_<root>` and the terminal dropped as an orphan. Measured on the binary at `0d79f3b40`: the shipped report said `End_3` and `grep -c End_3` on the emitted XML was **0** — the dangling-reference class `etc/check-bpmn-dmn-refs.mjs` exists for. The element is now read off the emitted flow leaving the `LEST` arm's own source (`raceArms`), so it cannot be a name the file lacks; where that cannot be identified unambiguously, no note is filed rather than a wrong one.

All three are pinned by tests in `jl4/tests/BpmnExport.hs` under "F6, the blame set, on a breach end two things can reach" — eight of them, including the controls that a lone barrier claims neither extra sentence and that every element F6 names is a node of the diagram it describes.
Three goldens move and no `.bpmn` does: `tenancy-barrier` gains the named arm, and all three carry F6 in a new position, since it is now filed after the per-element notes and before the two process-wide ones.

**Scoped to the barrier, deliberately, and the fork is still owed a ruling.**
A fork's `LEST` fires per member, so at each firing the blame is a singleton: the loss there is WHICH member, not which set, and filing `F6` on a fork would claim a set-shaped loss the fork does not have.
That per-member loss is today stated in prose rather than as a note — `escalationCatchName` (`Lower.hs`) captions the boundary "a member breached" precisely because it cannot say which, and its own comment says so.
Whether it also deserves a note is a ruling nobody has made.

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

### 7.2 Staging — two experiments, then a gate, and — 2026-09-21 — no picture

**Both experiments are done and the gate was ruled: NO (§7.3, RULED 2026-09-21), and the ruling
STANDS** — the rerun that ruling named as its first reopening condition was run the same day and did
not meet it (§7.7a; §7.3's TESTED block). The heading's "then maybe a picture" was decided in the
negative; the P2d and P2e rows below say NOT BUILT and keep what they would have been.

| ID       | Work                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Depends on                                                                             | Gates M4?      |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | -------------- |
| **P2b**  | `tellDeonticStep` + the `DeonticStep` type of §4.3. ~6 call sites in `Machine.hs`. **No renderer.** Tested in Haskell alone against `contracts.golden`. **Recommended unconditionally.** **BUILT 2026-09-15** (`lts/p2-stack`, not yet in `unstable`): `L4.EvaluateLazy.DeonticStep`, `tellDeonticStep` optional and off by default (R5 answered), seventeen call sites, `DeonticStepSpec`; §4.3's BUILT block. **Follow-up 2026-09-16** (`lts/p2-followups`): the bearer is recorded where the machine forces it (`nkBearerName`, `ekPartyName`) and the list matches by it; `--steps` prints real party names.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | —                                                                                      | no             |
| **P2c**  | The enabled set and the discharging/breaching partition, in the **replay** form (`STATEFUL` §6.5 endpoints 22/23/24), per §2.4. Plus `markingOf` (§4.2a) as a library function. **BUILT 2026-09-15** (`lts/p2-stack`): `L4.Lts.Marking` (`markingOf` against `Threshold`, with `Awaiting` for the join — the `markingOf` half of P2h's second half) and `L4.Lts.WhatIf` (the replay form, per candidate); §4.2a and §2.4 LANDED blocks.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | P2b                                                                                    | no             |
| **P2a′** | **The list baseline, and the primary gate.** Render §4.2a's marking + endpoints 17/19/20 as plain text — CLI first. Put it in front of readers against the same contract drawn by `stateGraphToDot` and P1. **BUILT 2026-09-15** (`lts/p2-stack`): `l4 lts FILE [--steps] [--json] [--contract NAME]`, goldens under `jl4/examples/lts/expected/`, page `doc/reference/regulative/lts-list.md`; §7.6. **The reader experiment itself has not been run**, and still has not been — the list exists, and the human experiment is now one of §7.3's three reopen conditions rather than the open gate. **Proxy run 2026-09-16** (`lts/p2-followups`, §7.7): 48 LLM readers, one artifact each — list 50/80, DOT-as-text 71/80, BPMN-as-text 66/80; on the gate's Q1–Q3 the list is 39/48 vs 41/48 and 42/48. Not the gate — but **the gate was RULED NO, 2026-09-21** (§7.3), on this proxy plus three further grounds recorded there. **RERUN 2026-09-21 against the repaired list** (`lts/whatif-bound-values`, §7.7a): list 66/80, DOT 66/80, BPMN 73/80; Q2 for the list 8/16 → 13/16 and Q4–Q5 11/32 → 25/32, both moved by the repair, and **on the gate's Q1–Q3 the list is second of three, 41/48 against 40/48 and 43/48, unbeaten and perfect on Q1 at 16/16** — so §7.3's first reopening condition is **not** met and the NO stands. Read with §7.7a's caveats: run 2 was scored twice (its first scoring used a `promissory-note` key `12055ae73` had invalidated, and all four contracts were re-judged); the control cells flipped 23 of 80 answers but totalled −1, against +19 of 160 on the cells that changed; and the reader-model gap, 23 answers of 120, is larger than any artifact gap in the run.                                                                                                                                                                                                                                                                                     | P2c                                                                                    | no             |
| **P2a**  | **The picture baseline.** Point `bpmn-io/bpmn-js-token-simulation` (MIT) at P1's shipped output and write down, case by case, what it cannot say. **MEASURED 2026-09-15** (`lts/p2-stack`): harness `etc/bpmn-token-sim/`, report `P2A-TOKEN-SIM-BASELINE.md`, RESULT block below. Measured over the eight goldens that existed that afternoon; the six `modals-*` goldens `6daf1d9d` added later the same day were unmeasured until the **RE-MEASURED** run of 2026-09-15 17:19 UTC (2026-09-16 SGT) over all fourteen goldens (`lts/p2-followups`; the RE-MEASURED block below), which found the fork-MAY lapse animation contradicting the runtime; `d544ed22` (legalese/l4-ide#395) then moved that lapse to Fulfilled in the state graph, and a third run at 2026-09-15 20:25 UTC over all fourteen (**MEASURED**, the committed `out/`) animates `modals-may-fork` as its barrier twin — the fork-MAY animation now agrees with the runtime. **RUN 4, 2026-09-18 23:23 UTC (2026-09-19 SGT), supersedes the 2026-09-16 re-measure:** all sixteen goldens (`option` from #425, `tenancy-fork-beside-party` from #430) in one run on `lts/token-sim-determinism` (`a3c7bdce3`, harness `9cd110c5d`), the first diffable baseline — two runs back to back differ in `run-meta.json`'s `runAt` lines only, 52/52 screenshots byte-identical. Result for the barrier/fork pairs: since #430 the fork is a multi-instance sub-process and the animation **can tell the pairs apart in shape** (a box holding the task, `instances: {"Scope_0": 1}`, an escalation relay, two end events per exit — `EndScope_0`/`EscScope_0` inside, `EndGroup_0`/`EndBreach_0` outside) but **not in cardinality**: `bpmn-js-token-simulation` 0.40.0 has no multi-instance behaviour, so the box runs once and `EndGroup_0` lands in the same step as the one instance's end; the `MAY` fork's lapse still reaches Fulfilled (`EndScope_0`) and the `SHANT` fork's "continue" is still the breach. Report §3.1, §3.7, §4. | P1 (shipped)                                                                           | no             |
| **P2f**  | **Unbundled.** `dom_s(J)` by Lengauer–Tarjan over `StateGraph`, answered as a **set of acts** — printable as a list or as an annotation on P1's BPMN. **No new picture required.** **BUILT 2026-09-15** (`lts/p2-stack`): `L4.StateGraph.Dominators`, `l4 state-graph --dominators [--all-states]`, `DominatorsSpec`; §1.1c LANDED block (iterated dominance equations, not Lengauer–Tarjan; same answer by definition). The DOT annotation was not built on that branch; it was **BUILT 2026-09-16** with B1/B2 (`--dominators --dot`, §1.1c's Annotation LANDED block and its correction).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | P0 (shipped)                                                                           | no             |
| **B1**   | Carry the correlation key (§3.4). Predicted to regenerate the BPMN goldens; in fact none moved. **LANDED 2026-09-16** (`lts/p2-followups`): `TransitionLabel.labelSite` = `rangeOf` the RAction, proved equal to P2b's `nkSite` by test; default DOT and all 14 BPMN goldens byte-identical. §3.4 block.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | P1                                                                                     | no             |
| **B2**   | Close the loop (§3.4). Makes `P-CYCLE` reachable; see §4.7. **LANDED 2026-09-16** (`lts/p2-followups`): a named rule already extracted is reused (memo keyed by the rule's `Unique`, not the range — §3.4 says why); 9 of 71 corpus files (with graphs) changed, `next`/`failure` dead ends 16 → 10; BPMN goldens unchanged (no golden source hands over by name). RECORD continuations still dead-end.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | B1                                                                                     | no             |
| **B3**   | Layout: Haskell ranks with a feedback-edge set, TS draws (§4.7). **Still not built 2026-09-21**, and the label work of `lts/draw-what-it-means` is not a down payment on it — §4.7's ruling block says what that work was and what it measured.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | B2                                                                                     | no             |
| **P2g**  | **The entry point (§4.8).** A CodeLens above every `Decide` whose body is regulative, in **both** lens producers, opening the view in a pane in VS Code and in the web IDE. Independent of which renderer sits behind the pane — wire it to the shipped `stateGraphToDot` first, which is how P2a′/P2a get run where readers actually are. Four edits, not one; see the table in §4.8. **BUILT 2026-09-15** (`lts/p2-stack`): the lens in both producers and both hosts, `l4_state_graph_by_name`; the pane shows DOT source with Copy (no renderer in the tree); R13 answered — the lenses never stack; §4.8 LANDED block. Not yet clicked by a human in either host. **In-pane rendering LANDED 2026-09-16** (`lts/p2-followups`): `@viz-js/viz@3.30.0` in `ts-shared/state-graph-render`, both hosts draw the picture and redraw on edit (web pane survives the ladder's refresh); extension bundle +1.5 MB (+495 KB gzip), one lazy web chunk; still no human click.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | shipped `StateGraph` (DOT); the "or P2d" alternative is dead, §7.3 ruled NO 2026-09-21 | no             |
| **P2h**  | **Carry the join (§4.9).** Teach `extractDeonton` to bind `Deonton.join` and put it on the graph, so a barrier and a fork stop producing byte-identical output; then the drawing rule, and `Threshold`-shaped `markingOf`. Answers R2 and closes the one export gap `EVERY-EACH-QUANTIFIER-SPEC` §2.5 says a reader cannot discover from the export. Same class and cost as B1 — it moves P1's goldens. **Do the first half before P2b**, which is specified against a pre-join `Deonton`. **First half LANDED 2026-09-15** (`fix/join-on-state-graph`): `extractDeonton` binds the join by positional pattern, `TransitionLabel.labelQuantifier` carries it (`Quantifier`/`JoinLabel`/`JoinLabelKind` — renamed from `JoinKind` 2026-09-16, which `DeonticStep` also exports), the DOT draws it on the edge, and BPMN lowers an `EVERY` to a parallel multi-instance task with `P-CAST`/`P-FORK`/`P-JOIN-DEADLINE`. Measured against the prediction here that it "moves P1's goldens": it moved **none** of the six — no golden source contained an `EVERY` — and added two (`tenancy-barrier`, `tenancy-fork`). Second half (the norm-plane drawing rule, `Threshold`-shaped `markingOf`) still open. **Second half, 2026-09-15:** `markingOf` against `Threshold` LANDED with P2c (§4.2a); the norm-plane drawing rule remains P2d's and is gated with it. **2026-09-21: the §7.3 gate is ruled NO and P2d is not built**, so the part of P2h that was gated with it is not owed by anything unless the gate reopens; the "marked but not enabled" rule §4.2a records as blocked on nothing is a separate residue and is unaffected.                                                                                                                                                                                                                                                                                                                                                                     | shipped `EVERY` (PRs #360/#370/#374)                                                   | **first half** |
| **P2d**  | The P2 IR and the **static** two-plane picture. No animation. ~~Gated: build only if §7.3's condition is met.~~ **NOT BUILT — gate ruled NO 2026-09-21** (§7.3's RULED block). What it would have been, kept as the record: §2.3's two-plane marked transition system as an IR, drawn statically — an action plane over a norm plane — carrying R1's residue drawing rule (§2.3a: `Dot.hs:225` stops printing the modal on the edge when both planes are drawn) and the norm-plane half of P2h (§4.9). Its three reopen conditions are in §7.3.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | P2c, B1-B3                                                                             | no             |
| **P2e**  | The animator: scrubber, token, marking, enabled-set highlight. TypeScript, per K6. **NOT BUILT — gate ruled NO 2026-09-21** (§7.3), and it depended on P2d, which is not built either. What it would have been, kept as the record: §4.1's animated marking driven by §4.3's deontic step log (which _is_ built), the two modes of §4.5, §4.4's re-scrutiny frame (R6, still unanswered) and §4.7's layout.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | P2d                                                                                    | no             |

_Reconciled 2026-09-16: the P2f row read "DOT annotation not built" beside "BUILT 2026-09-16" after the six tracks merged (the B1/B2 track had left a note here rather than edit the integrator's table); the row now states the sequence. The RE-MEASURED and PROXY RUN blocks below deferred their rows to the integrator in the same way; those rows were written at integration (`af263553`)._

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
> driven headlessly by `etc/bpmn-token-sim/` over the eight goldens then in `jl4/examples/bpmn/expected/`
> (**re-measured 2026-09-15 17:19 UTC over all fourteen**, 2026-09-16 SGT — the `RE-MEASURED` block after this one);
> report with per-fixture tables, screenshots and the simulator's own JSON in
> [P2A-TOKEN-SIM-BASELINE.md](./P2A-TOKEN-SIM-BASELINE.md). In five lines:
>
> 1. **A token does not know its modality.** The same token, play button and pad sit on a `MUST`, a
>    `MAY`, a `SHANT` and a `businessRuleTask`; on `offering` and both `regcf-*` prohibitions,
>    "continue" on the `SHANT` task **is** the breach, and its timer is the compliance exit — the
>    inverse of every `MUST` beside it, with no notational difference.
>    **MEASURED 2026-09-19 by `lts-diagrams-2`, and it bounds this whole track: the token simulator
>    cannot show multi-instance at all.** `bpmn-js-token-simulation` 0.40.0 has zero occurrences of
>    `multiInstance` or `loopCharacteristics` anywhere in `lib/`, so a multi-instance sub-process plays
>    as ONE instance and `EndGroup_<n>` fires the moment that instance ends — on a breach path
>    `EndBreach_<n>` and `EndGroup_<n>` arrive together. **So `etc/check-bpmn-soundness.mjs` is the only
>    thing in this repository that plays n > 1**, and any claim about what a reader would SEE of the
>    per-member picture has to come from the gate rather than from the animation.

What the animation does now show of the join, which the flat drawing did not, is structural: a box,
the escalation relay, and two terminals of the fork's own. That is a real improvement on the
identical-in-every-field result recorded below — but it is a difference in the PICTURE, not a
difference in the play, and the two were worth separating before someone cited the wrong one.

Two further facts from the same run, worth having where the emitter is discussed:
`BoundaryEsc_<n>` is the **only non-interrupting boundary in the whole corpus** — every other
`Boundary_<n>` across all sixteen goldens is interrupting — and firing that relay cold, before the
member's task is entered, produces an `EndBreach_<n>` with a breach that has no cause, which is why
a simulator driving boundaries must fire only the interrupting ones.

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

> **RE-MEASURED 2026-09-15 17:19 UTC (2026-09-16 SGT) — the six `modals-*` goldens** (`6daf1d9d`, legalese/l4-ide#395:
> `modals-{may,shant}-{barrier,fork}`, `modals-must-barrier-both-deadlines`,
> `modals-must-fork-join-deadline`). Same harness, same versions, one run over all fourteen at
> 2026-09-15 17:19:57 UTC (`etc/bpmn-token-sim/out/run-meta.json`); the committed `out/` is that
> run in full, the first run's files replaced — six of its eight JSONs matched the new ones apart
> from instance ids, `consultation` and `offering` also differed in the arrival order of concurrent
> tokens after a parallel split, and the census gained a `completionCondition` field, so nothing
> was byte-comparable and nothing was kept. Report §3.7 has the per-fixture table. The three
> questions the re-run was asked:
>
> 1. **The `SHANT`'s `completionCondition` changes nothing on "continue".** bpmn-moddle imports it
>    (`elements[Task_0].multiInstance.completionCondition: "nrOfCompletedInstances >= 1"` on both
>    `modals-shant-*`, `null` elsewhere), the simulator's `lib/` never mentions it (0 grep hits),
>    and the run is one scope, one token, one click to Breach — the same as `tenancy-*` without
>    the condition. The engine case it guards against, waiting for every member to offend, cannot
>    arise with one instance.
> 2. **The `MAY`'s lapse arm animates, and lands in different places on the barrier and the
>    fork.** On `modals-may-barrier` firing `Boundary_0` reaches `End_2` Fulfilled, the process
>    finishes and no token is left. On `modals-may-fork` firing `Lapse_0` leaves a token on the
>    chair's `MUST Publish` with its `P5D` timer offered — animated faithfully, and contradicting
>    the runtime, which routes an unexercised `MAY`'s expiry to `LEST`/`FULFILLED` under a fork
>    as under a barrier (measured 2026-09-16, `ok/every/run-modals.l4` §7 and its golden; §4.9's
>    correction of that date names the two in-tree claims it overturned). It was the first
>    barrier/fork pair in fourteen whose animation differed. **Fixed and RE-MEASURED 2026-09-15
>    20:25 UTC (2026-09-16 SGT):** `d544ed22` (legalese/l4-ide#395) widened the `DMay` arm so
>    the fork's lapse is a `LEST` edge to Fulfilled too, and the golden's `Lapse_0 → Task_1`
>    became `Boundary_0 → End_2`; the harness re-run over all fourteen (the committed `out/`,
>    `run-meta.json` at 20:25:02 UTC) has `modals-may-fork` firing `Boundary_0` to `End_2`
>    Fulfilled with no token left, identical to `modals-may-barrier` in every field but the
>    fixture path (`jq 'del(.. | .log?)'`, no difference); the twelve other JSONs are unchanged
>    modulo ids, bar `consultation`'s already-known reordering after its parallel split. The
>    fork-MAY animation now agrees with the runtime. Report §3.7 has the rewritten row.
> 3. **`modals-must-barrier-both-deadlines` shows one timer, not two.** The census has one
>    `bpmn:BoundaryEvent` (`P30D`, the member's); the join line's `WITHIN 10` is not in the file
>    (`P-JOIN-DEADLINE`, lossy) and survives only in `<documentation>`, which the simulator does
>    not display. Its fork twin also has one timer (`P10D`), and the two JSONs differ in that
>    label and the path alone — so the tighter deadline, the one `run-modals.golden` breaches on,
>    is the one the picture cannot show.
>
> Points 1 and 3 above stand on the new files: "continue" on both `modals-shant-*` tasks is the
> Breach and their timer the Fulfilled exit (point 1); no timer fired unaided on any of the six
> (offered at 1.5 s, unchanged at 4.5 s; point 3). Points 4 and 5 are not exercised by them — every
> `modals-*` file is a single branch with one multi-instance task, so no sibling survives a breach
> and no two tokens are ever live — and stand on the original eight alone. `modals-shant-*` are
> byte-identical modulo ids and path; `modals-must-*` differ by one label. Point 2 holds for
> all four barrier/fork pairs: it held for three on the 17:19 run, and the `modals-may-*`
> exception of question 2 closed with `d544ed22` and the 20:25 run. Still unmeasured: everything the previous paragraph lists
> as unmeasured. **This block does not decide the gate either.** The staging table row for P2a
> read "unmeasured" for the `modals-*` goldens when this was written; it was updated at integration.
>
> **SUPERSEDED BY RUN 4, 2026-09-18 23:23 UTC (2026-09-19 SGT).** With legalese/l4-ide#430's
> head `646f58e9c` merged into `lts/token-sim-determinism` (`b24e19bae`; #430 lowers a fork to a
> multi-instance sub-process and is an **open** PR as of 2026-09-19, so this shape reaches
> `unstable` only when it merges, and #426 must land after it), all sixteen goldens were re-run in
> one diffable run (`a3c7bdce3`; report header, §3.1, §3.7): the four
> barrier/fork pairs are now distinguishable in shape — the fork's box, its count of one, its
> escalation relay and its inner/outer end events — and still not in cardinality, since the
> simulator has no multi-instance behaviour and runs the box once; point 2 above holds for the
> `n` and no longer for the picture. Points 1 and 3 changed in detail: the `completionCondition`
> is now on `modals-shant-barrier` alone (the fork's box has none), and the fork twin of point 3
> keeps its one `P10D` timer inside the box. Every number in this block is run 3's; the report is
> the current reading.

**PROXY RUN 2026-09-16, for P2a′; RERUN 2026-09-21, see §7.7a.** An LLM-reader _proxy_ of the P2a′ reader experiment was run
over four contracts — the list, the DOT source and the BPMN XML, each read as text by fresh LLM
readers with no tools — and is written up in §7.7 and `etc/lts-reader-proxy/RESULTS.md`. Pooled:
list 50/80, DOT 71/80, BPMN 66/80; on Q1–Q3 the list is 39/48 against 41/48 and 42/48, on Q4–Q5
11/32 against 30/32 and 24/32. It is **not** the gate — no person, no picture, no cognitive-load
measure — and §7.7 says what it can and cannot support. The P2a′ row above carries these numbers
as of integration; it decides nothing either.

### 7.3 The gate

**RULED 2026-09-21 (Meng) — NO. P2d and P2e are not built. The ruling STANDS: the rerun it named
as its first reopening condition was run the same day and did not meet it (see the block at the end
of this section).** The rule quoted below is the rule that was applied, and it stays as written;
what follows is the decision, the measurement it rested on, and the measurement that tested it.

**The measurement.** §7.7's LLM-reader proxy, RUN 2026-09-16 — four contracts, three artifacts
each (**A** the `l4 lts` list, **B** the `l4 state-graph` DOT, **C** the P1 BPMN), two models,
two repeats: 48 readings, 240 answers — read with §7.7's own six limits in front of it, of which
the two that bite here are that no human read anything and that a one- or two-answer difference
in a column of sixteen is inside what a rerun could reverse.

1. **The gate is conjunctive, and on its own three questions the list is not beaten.** The
   sentence below asks about _what do I owe, what discharges it, what breaches it_ — Q1–Q3 of
   the proxy, and nothing else. Pooled: **A 39/48, B 41/48, C 42/48**. On **Q1 and Q3 alone the
   list is ahead of both pictures — 16/16 and 15/16**, against B's 13/16 and 13/16 and C's 14/16
   and 14/16; all five Q1 misses in the run are on the pictures, and all five are definite wrong
   answers. A three-answer spread over 48 readings, in a run whose own limit (vi) says a one- or
   two-answer difference in a column of sixteen could reverse on a rerun, is not readers being
   unable to answer from the list.

2. **The list's single deficit is Q2 at 8/16, and it has one repairable cause.** §7.7 point 2
   traces **every one of those eight misses** to `WhatIf`'s refusal of a bound pattern variable:
   they all sit on the three contracts whose `A.txt` prints _"the action binds `return` /
   `amount` / `Amount Transferred`, which the what-if cannot choose"_, and on
   `every-run-example` — the one contract where the act could be tried — the list is 4/4. That
   is a gap in this list, not a fact about lists. **The repair landed in this same PR**
   (2026-09-21, §2.4's bound-variable block), and it is cheaper than P2d + P2e by an order of
   magnitude. It is a repair to the list, not to the run: the 48 readings were taken against the
   old output and no number in §7.7 has moved, so **nothing here is yet evidence that the Q2
   column changes**. What would settle that is the rerun §7.7's cost-order list puts first.
   _(Run 2026-09-21, §7.7a: the Q2 column does change, **8/16 → 13/16** — but not uniformly. On
   `contracts` it went 1/4 → 4/4 and on `promissory-note` 2/4 → 4/4; on `tenancy`, where the repair
   also landed, it stayed 1/4, three of four readers not using the block the list now prints. So the
   refusal was a real cause and not the only one.)_

3. **P2a's half of the condition IS met — and more strongly than when this gate was written.**
   Run 4 (2026-09-18 23:23 UTC, 2026-09-19 SGT; harness `etc/bpmn-token-sim`, report
   [P2A-TOKEN-SIM-BASELINE.md](./P2A-TOKEN-SIM-BASELINE.md)) measured that
   `bpmn-js-token-simulation` 0.40.0 has **no multi-instance support at all** — zero occurrences
   of `multiInstance` or `loopCharacteristics` under `lib/` — so the per-member picture is not
   drawable with that tool **structurally**, not by configuration. But a conjunctive gate needs
   both halves, and the other half did not fail.

4. **A premise has changed since this gate was written: a third artifact now ships.** P2g plus
   legalese/l4-ide#401's in-pane renderer put the `l4 state-graph` picture in front of readers in
   both hosts, and **B — that same DOT — was the best artifact in the proxy, 71/80.** P2d's
   marginal value is therefore not _a picture versus no picture_, which is what the sentence
   below assumes; it is _a bespoke two-plane picture versus the state graph we already draw_.
   That is a much smaller margin to justify a build against.

5. **The counterweight, stated rather than hidden: on Q4 and Q5 the list loses badly** — 11/32,
   against B's 30/32 and C's 24/32, exactly in §1.1a's direction. Two things qualify it, and
   neither makes it go away. Those two questions (_where are we_, _what next_) are §1.1a's own
   "what a list cannot do" and are **not in the gate's sentence**; and B and C readers were
   handed the position in plain words (`history.txt`) while A readers had to derive it from the
   list, so this is the pictures' best case on exactly those two columns. If _where are we_ turns
   out to matter, the first move is to **make the list say it** — cheap, and re-measurable with
   the same materials — not to draw it.

**What would reopen it.** Any one of: (a) the repaired list still failing Q1–Q3 when these same 48
readings are rerun — **RUN 2026-09-21, and NOT met: see the block immediately below**;
(b) a vision run — B and C **rendered** rather than read as text — showing that _drawing_, as
opposed to content, is what carries the answer; or (c) the human experiment the sentence below
actually asks for, showing that novices cannot use the repaired list.

> **TESTED 2026-09-21 — condition (a) is NOT met, and this ruling STANDS.** The rerun is §7.7a.
> Measured, Q1–Q3 pooled over the four contracts: **A 41/48, B 40/48, C 43/48** — the repaired list
> is second of the three on the gate's own three questions, one answer ahead of the DOT and two
> behind the BPMN, which is the spread point 1 above called _"not beaten"_ at 39/48. Point 1's
> sharper sub-claim splits: the list is unbeaten and now **perfect on Q1** (16/16 against 11/16 and
> 13/16) and is **behind both on Q3** by two (12/16 against 14/16 and 14/16), which §7.7a item 3
> traces to one appended clause in the breach line that is not the repair's. Point 2 half-held — the
> repair moved Q2 8/16 → 13/16, but not on `tenancy`, where it landed and the column did not move.
>
> **Three things go to Meng alongside that, none of them a softening.** Point 5's counterweight
> **weakened**: Q4–Q5 for the list went 11/32 → 25/32, level with the DOT. **The note-excluded cut
> disagrees**: drop `promissory-note` and the list is last on Q1–Q3, 30/36 against 32/36 and 35/36 —
> which is the cut on which condition (a) would be met, and it is the contract whose key was just
> re-derived from the tree. And **the reader, not the artifact, is the largest effect in the run**:
> sonnet beats haiku by 23 answers of 120, against a three-answer artifact spread on Q1–Q3.
>
> **The run's own caveats, stated rather than left to be found.** Run 2 was scored twice: its first
> scoring judged `promissory-note` against a key `12055ae73` had invalidated, marking readers wrong
> for printing the day serial the artifact prints; the key has been re-derived and all four contracts
> re-judged under one judge, moving 24 of 240 answers (§7.7a). The control — four cells shown
> byte-identically in both runs — flipped 23 of 80 answers but totalled **−1**, against **+19 of 160**
> on the cells that changed, so per answer the instrument is noisy and in total it is nearly flat.
>
> **The ruling is not amended by this section** — §7.3 is Meng's. What changes is its status: it
> stood on a measurement that has now been taken, and the measurement came back the way the ruling
> assumed. §7.7a's recommendations before any re-decision: re-word the breach-names clause; re-cut
> `promissory-note/history.txt`'s conversion table; run a true test-retest so the next comparison has
> an error bar.

> **Build P2d/P2e only if P2a′ shows that readers cannot answer "what do I owe, what discharges
> it, what breaches it" from the list — and P2a shows the off-the-shelf simulator cannot either.**
> If either baseline suffices, stop. The back end (P2b/P2c) and the dominator answer (P2f) are
> already delivered by then, and they are the parts with independent value.

Both experiments together cost about three days. B1-B3 plus P2d plus P2e cost considerably more,
and §4.7 says the layout half is under-costed even now. Spending the three days first is the
whole of revision 2's staging argument.

**PREPARED 2026-09-16 — materials for an LLM-reader _proxy_ of this gate, on `lts/p2a-prime-proxy`;
RUN the same day, as a proxy — results in §7.7 and `etc/lts-reader-proxy/RESULTS.md`. No verdict
on the gate.** The gate is a reader experiment and no human has been shown anything. What
exists is `etc/lts-reader-proxy/` (its `README.md` is the authoritative description): for four
contracts, at one fixed position each, the three artifacts a reader would be given — **A** the
`l4 lts` list at default flags, **B** the `l4 state-graph` DOT for the rule, **C** the P1 BPMN
(the `jl4/examples/bpmn/expected/` golden where one exists, else `l4 export --to bpmn --rule`) —
plus, for B and C, the position in plain words, and a `truth.json` per contract: five questions
(Q1–Q3 are §1.1a's three clauses; Q4 _where are we_, Q5 _what happens after_, the two things
§1.1a says a list cannot do) with answers read off `l4 lts --json` for Q1–Q3 and off `probes.l4`
`#TRACE` runs and the DOT for Q4–Q5, each answer citing the field or trace line it came from.
`manifest.json` carries the full text of all twelve artifacts, because a reader sees only that.

- **Positions.** `ok/contracts.l4` `aContract` at its own first `#TRACE` (line 23; the §7.6
  block); `every-run-example.l4` `the tenancy` at an **appended** trace (Alice at 1, Bob at 2,
  Carol not yet — the file's own barrier traces both end, so a mid-contract position had to be
  added; `position.trace`); `bpmn/tenancy.l4` `receipts` at its outset (`--contract receipts`);
  and `legal/promissory-note.l4` `Payment Obligations` at its own second `#TRACE` (line 192), one
  late payment sitting in the first LEST arm.
- **Why the fourth is not Reg CF.** Measured by `grep -n 'LEST' jl4/examples/legal/regcf/regcf.l4`:
  no hits in any of its three regulative rules — the advertising and resale restrictions are bare
  `SHANT`s, the ongoing reporting obligation is a `HENCE` cycle — and `regcf-denovo.l4` has
  `LEST BREACH … BECAUSE` arms and no `#TRACE`. The promissory note is a real chain
  (reparation, then a deadline-free reparation of the reparation) and its evaluator answers are
  the least obvious of the four: at the position **nothing can breach** (`lts.json`:
  `breaching: []`; the tick past 3 June 2025 takes the `2 -> 4` timeout edge in `B.dot`, and the
  only breach edge out of node 4 is `4 -> 5 "unreachable: no WITHIN"` — both still true of the
  re-cut `B.dot`, checked 2026-09-23, on which that timeout edge now also names its deadline), and
  paying the penalty amount in time ends the **whole twelve-installment note** FULFILLED, because
  the reparation arm has no `HENCE` (`probes.out`, the trace on `probes.l4:294`).
- **What this proxy cannot measure, stated in the README so the result is not over-read**: it is
  not the gate (§7.3 is about people); §7.4's warrant is about novice modellers' cognitive load,
  which an LLM reader cannot stand in for; B and C readers get DOT and XML **as text**, so the
  proxy measures whether the graph's content carries the answer, not whether a drawing helps;
  and the note's list prints day serials, which A readers get unconverted.
- **The binary.** The artifacts **the readers were shown** were cut with the `lts/p2-stack` build
  at `0139c6c5` (the same commit this branch is on); its `l4 lts` output diffed byte-identical
  against all three committed goldens under `jl4/examples/lts/expected/` before anything was cut,
  and `every-run-example.l4`'s `the tenancy` exports byte-identical to `tenancy-barrier.bpmn`
  (`prepare.sh` asserts this on every run).
  **The four `B.dot` files on disk are no longer that text.** They were re-cut on 2026-09-21 and
  again on 2026-09-23, as `lts/draw-what-it-means` moved the captions. The reading is frozen and
  the artifact is not: `etc/lts-reader-proxy/manifest.json` and `transcripts/` still carry what the
  readers were given, and every number in §7.7 and in `RESULTS.md` is scored against those. Do not
  regenerate them to agree, which would put 48 committed readings against a packet nobody read.
- **Two things seen one step past the `tenancy` position, not fixed, not in any reader
  artifact** (`etc/lts-reader-proxy/tenancy/probes.out:15` and `:11`): with Alice paid at 3, the
  what-if for the landlord's `Receipt (EXACTLY theLandlord) (EXACTLY t) (EXACTLY amount)` is
  refused with the replay's own `Internal error: amount is not in scope` as its reason —
  `reifyExpr` (`jl4-core/src/L4/Lts/WhatIf.hs:539`, as of the run's `0139c6c5`) cannot read a
  member's open pattern variable through the `HENCE`; the verdict (untried) is right, the wording
  is not the list's.
  _The first is fixed 2026-09-19 (§2.4, amended; every-each round 2 O2): the refusal is now
  made before the replay, by `closedAction`, and reads "the action binds `amount`, which the
  what-if cannot choose", and the receipt is still named with its member; `tenancy/probes.out`
  is re-cut from that binary, so its line 15 reads the new sentence._
  And the tick past 7 prints as `the clock reaches 7.5` — `tickPast` (`WhatIf.hs:278`, as of
  `0139c6c5`) going
  half-way to the next live deadline, as §2.4 says, which a reader is not told.

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

  What would discharge it (the contract ends fulfilled):
    - B does anything now (at 10) → fulfilled
      this obligation's pattern matches any act by B: the rule binds `return` rather than naming an act
      the verdict above is one act's, not the set's: `return` = delivery was replayed, and another member may end elsewhere

  What would put someone in breach:
    - nothing happens by 14 (the clock reaches 15) → B is in breach: MUST return was due by 14; the clock reached 15 without it

  Next deadline: 14 (B: return)

  Steps, in order:
    at 2: S does delivery at 2; S MUST — done; on to what follows
    at 4: B does payment OF … at 4; B MUST — done; on to what follows
    at 10: the clock runs to 10 with nothing happening; B MUST — not this party's event; passed over
    at 10: B MUST — no more events; still waiting
```

(`return` is a variable pattern in that corpus file — there is no `return` constructor — so what
discharges the obligation is a SET of acts, not one. **Amended 2026-09-21 (§2.4's bound-variable
block).** Until then this block read

```
  What could not be tried:
    - B does return — the action binds `return`, which the what-if cannot choose
```

and that refusal, across three of the proxy's four contracts, was the whole of the list's Q2
deficit — §7.7 point 2.)

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
it. An LLM-reader _proxy_ was run on 2026-09-16 (§7.7); it changes nothing in this paragraph.
_2026-09-21: the gate is now ruled — **NO**, §7.3 — on that proxy plus three further grounds
recorded there. The human reader experiment is still unrun, and this paragraph still stands; what
changed is that P2d and P2e are not being built while it stays unrun, and running it is one of
the three things that would reopen them._

### 7.7 The §7.3 gate — an LLM-reader proxy, RUN 2026-09-16 and RERUN 2026-09-21

**RUN 2026-09-16, on `lts/p2a-prime-proxy`, as a PROXY. This section decides nothing about the
gate.** Full write-up, per-reading rationales and the raw scored rows:
`etc/lts-reader-proxy/RESULTS.md` and `results.json`; every number here is computed from that
file.

**Method.** The materials §7.3's PREPARED block describes: four contracts at one fixed position
each (`contracts`, `every-run-example`, `tenancy`, `promissory-note`), three artifacts each — **A**
the `l4 lts` list at default flags, **B** the `l4 state-graph` DOT source _as text_, **C** the P1
BPMN XML _as text_ (B and C readers also got the position in plain words, `history.txt`; A readers
got only the list). Readers: `claude-haiku-4-5-20251001` and `claude-sonnet-5` (recorded as
`haiku` and `sonnet`); each reading a fresh single-turn Claude Code subagent, **no tools** but the
answer form, one artifact and the five questions, nothing else, told to say _"cannot tell from
this"_ rather than guess; **two repeats** per (contract, artifact, model) — 48 readings, 240
answers. Judge: one `claude-opus-5` per contract, scoring each answer 0/1 against `truth.json`
with a rationale. Its prompt states one rule verbatim — _"'cannot tell' is 0 unless the truth
says the artifact cannot say it"_; a second, _incomplete but nothing wrong scores 1_, is inferred
from the rationales, not written; and neither was applied uniformly (RESULTS.md §1 names three
rows: `promissory-note/A/haiku/0` Q4, `promissory-note/A/haiku/1` Q3, `tenancy/A/sonnet/1` Q2),
so any count that turns on them is ±2. **Recorded** (`etc/lts-reader-proxy/transcripts/`,
recovered by `extract-transcripts.mjs`, which also asserts `results.json` == judge output and
judge input == reader output): every reader prompt and verbatim answer, every judge prompt and
output, model ids, timestamps. **Still not recorded:** the harness system prompt the subagents
ran under, and their thinking (signatures only in the transcript).

**Accuracy, correct/readings** (a per-contract cell is 2 models × 2 repeats; pooled is 16):

| contract            | artifact   | Q1        | Q2        | Q3        | Q4        | Q5        | all                                  |
| ------------------- | ---------- | --------- | --------- | --------- | --------- | --------- | ------------------------------------ |
| `contracts`         | A / B / C  | 4 / 4 / 4 | 1 / 4 / 4 | 4 / 4 / 4 | 2 / 4 / 4 | 0 / 4 / 4 | 11 / 20 / 20 of 20                   |
| `every-run-example` | A / B / C  | 4 / 4 / 4 | 4 / 4 / 4 | 4 / 4 / 4 | 2 / 4 / 4 | 4 / 4 / 4 | 18 / 20 / 20 of 20                   |
| `tenancy`           | A / B / C  | 4 / 3 / 4 | 1 / 4 / 4 | 4 / 2 / 4 | 3 / 4 / 4 | 0 / 4 / 0 | 12 / 17 / 16 of 20                   |
| `promissory-note`   | A / B / C  | 4 / 2 / 2 | 2 / 3 / 2 | 3 / 3 / 2 | 0 / 3 / 2 | 0 / 3 / 2 | 9 / 14 / 10 of 20                    |
| **pooled**          | **A** list | 16/16     | 8/16      | 15/16     | 7/16      | 4/16      | **50/80** (Q1–Q3 39/48, Q4–Q5 11/32) |
|                     | **B** DOT  | 13/16     | 15/16     | 13/16     | 15/16     | 15/16     | **71/80** (Q1–Q3 41/48, Q4–Q5 30/32) |
|                     | **C** BPMN | 14/16     | 14/16     | 14/16     | 14/16     | 10/16     | **66/80** (Q1–Q3 42/48, Q4–Q5 24/32) |

By model: haiku A 22/40, B 33/40, C 36/40; sonnet A 28/40, B 38/40, C 30/40. The two repeats of
a cell agreed exactly in 16 of 24 cells.

**The misses, sorted before they are read** (53 of 240; classification from the judge rationales):
the list's 30 are **25 "cannot tell"**, 3 incomplete, 2 wrong; the DOT's 9 are 7 wrong, 2 vague,
0 "cannot tell"; the BPMN's 14 are **13 wrong**, 1 "cannot tell". The list fails loudly; the
pictures-as-text fail silently — with the caveat that every reader was told not to guess, so the
loud failure was invited and its size is partly the prompt's (RESULTS.md §3).

**What the proxy can say** (each with its evidence in RESULTS.md §3):

1. **On Q1 and Q3 the list is not beaten** — 16/16 and 15/16 against 13/16, 13/16 (DOT) and
   14/16, 14/16 (BPMN). All five Q1 misses are on the pictures and all five are definite wrong
   answers.
2. **The list's Q2 loss (8/16) is entirely `WhatIf`'s refusal of open pattern variables.** All
   eight misses are on the three contracts whose `A.txt` prints _"the action binds `return` /
   `amount` / `Amount Transferred`, which the what-if cannot choose"_
   (`jl4-core/src/L4/Lts/WhatIf.hs:525`, printed by `L4/Lts/List.hs:216` under _What could not
   be tried_); on `every-run-example`, the one contract where the act could be tried, the list
   is 4/4. The readers who scored 1 inferred what the list did not print. This points at a
   list-side repair, re-measurable with the same materials, before any picture.
   **REPAIRED 2026-09-21** (§2.4's bound-variable block): all three now print what discharges
   the obligation — `contracts` "B does anything now (at 10) → fulfilled"; `tenancy` each
   tenant's payment "with any `amount`", checked at 0; `promissory-note` "with any
   `Amount Transferred` for which `is money at least equal within error` … (Money OF "USD",
   2369.2806990603694) holds → fulfilled". **RERUN 2026-09-21 — the numbers in this table are
   run 1's and have NOT been restated; run 2's are in §7.7a below.** Q2 for the list moved
   8/16 → 13/16, and the move is not uniform: `contracts` 1/4 → 4/4, `promissory-note` 2/4 → 4/4,
   **`tenancy` 1/4 → 1/4 despite the repair landing on it.**
3. **On Q4–Q5 the list loses badly (11/32 vs 30/32 and 24/32), in §1.1a's direction — and
   §1.1a's reason is only half right.** All four of the list's Q5 hits are `every-run-example`,
   where the list itself prints the `→ then:` continuation one step deep (§7.6); it printed
   nothing on the other three because the what-if was refused (point 2). The residual, measured
   claim is Q4: the list gives the event history, not the branch taken (`contracts`: sonnet named
   the live state — _"the return obligation now live and its deadline at 14"_ — without naming
   the branch, twice, and was credited; haiku said "cannot tell" twice; `promissory-note`: 0/4,
   and A readers alone were not told the April payment was refused).
4. **The BPMN's 13 wrong answers: 5 sit squarely on a documented exporter loss, 8 contradict
   the history the reader was given.** `tenancy` Q5 0/4: three readers said receipts wait for
   _all_ tenants — `[P-FORK] lossy` in `tenancy/C.fidelity.txt` verbatim, _"what is drawn fires
   once, for the group"_; haiku on the note, Q3 wrong twice, asserting `Boundary_4` fires when
   its own `<documentation>` says nothing can fire it (`[P-DEADLINE]`). Those are the five. The
   eight are `promissory-note`, sonnet 2/10: both readings credited the April payment although
   `history.txt` said it was _"the plain installment amount, paid after the deadline"_ — at most
   consistent with the `PROVIDED` guard being an opaque `conditionExpression` (`[F4]`) and the
   deadline a text boundary (`[P-DEADLINE]`), not caused by them.
5. **The DOT source as text is the best artifact** — 71/80, 10 of 16 readings perfect; its
   misses are 7 confident wrong answers, 6 of them on the note.

**What the proxy cannot decide — the gate.** (i) §7.3 is about people; no person read anything,
and an LLM that infers an unprinted discharge is not evidence a member of the public would.
(ii) It measures right answers, not cognitive load — the quantity §7.4's warrant is about and the
one §7.4 says animation does _not_ move. (iii) B and C were read as text: "DOT beats BPMN" here
means one serialisation was easier to read than another, and says nothing about a drawing.
(iv) A readers were disadvantaged on the note by design (day serials unconverted), which
confounds that contract's Q4 column. (v) The judge is an LLM, and "cannot tell = 0" is a choice
that costs the list 25 of its 30 misses and the pictures almost nothing; it is the right rule for
_can the reader answer_ and the wrong rule for _does the artifact mislead_, and those two
questions have opposite answers on this data. (vi) Four contracts, two models, two repeats, no
intervals: a one- or two-answer difference in a column of sixteen is within what a rerun could
reverse. **Nothing here passes or fails §7.3.** The §7.2 P2a′ row records this run and says the same.

_What would move it, in cost order — statuses as of 2026-09-21, after the rerun:_ **repair LANDED,
rerun DONE** — the open-binder what-if is repaired (point 2 above, §2.4) and the same 48 readings
were rerun the same day (§7.7a); **open, and narrowed** — equalise the note's calendar conversion
across A/B/C: the key itself was re-derived on 2026-09-21 and all four contracts re-judged against
it, but `promissory-note/history.txt`, which is what B and C readers are shown, still converts day
739769 and not 739752 (§7.7a, RESULTS.md §6.6); **open, and now the highest-value item** — rerun
outside the harness with a bare API call and a fixed system prompt, since §7.7a measures a
reader-model gap of 23 answers in 120, larger than any artifact effect yet found; **open** — a vision run with B and C rendered, to separate content from
drawing; **open** — and then the reader experiment §7.3 actually asks for. **NEW, and cheapest of
all** — a true test-retest, the same packets and settings twice, which has never been run. The
first, the fourth and the fifth are also §7.3's three reopen conditions.

_What review changed (2026-09-16, same day):_ the first version of this section said the model
ids, prompts and judge were not recorded; a reviewer pointed out that this left `results.json`
unauditable. They were recoverable from the run's own transcripts and are now committed under
`etc/lts-reader-proxy/transcripts/`. The same review corrected three borrowed-and-sharpened
claims here and in RESULTS.md: sonnet "reconstructed the `ELSE` branch" (it named the state, not
the branch); "8 of 16" list readers inferred the discharge (4 of 12 on the refused contracts —
the other four cited `every-run-example`'s printed `→ then:` line); and "all 13" BPMN misses sit
on documented losses (five do). No number in the table changed.

### 7.7a The rerun — RUN 2, 2026-09-21, and what it does to §7.3

**RERUN 2026-09-21, on `lts/whatif-bound-values`, as a PROXY. Like §7.7 it decides nothing about
the gate — but it is the measurement §7.3 named as its first reopening condition, so it does bear
on whether the ruling stands.** Scored rows: `etc/lts-reader-proxy/results-run2.json`; the readers'
verbatim answers: `etc/lts-reader-proxy/transcripts-run2/readings.json`; full write-up, control and
per-finding account: `etc/lts-reader-proxy/RESULTS.md` §6. Every number here is computed from the
scored rows.

**Run 2 was scored twice, and only the second scoring is quoted here.** The first judged
`promissory-note` against a `truth.json` that `12055ae73` (2026-09-17, `EVERY-EACH-QUANTIFIER-SPEC`
§5.2) had invalidated: a `LEST` now anchors at the **missed deadline**, so the reparation falls due
day **739752** (44 days from the position), where the key still said 739769 (61 days). The re-cut
`A.txt` had printed 739752 since `e633e2e58`, so **readers were marked wrong for reading the artifact
correctly.** The key was re-derived from the tree (`9354b6cf4`) and **all four contracts re-judged
under the same two rules by one judge instead of four**; 24 of 240 answers moved, on all four
contracts and all three artifacts. The superseded rows are kept as
`etc/lts-reader-proxy/results-run2-superseded.json`. RESULTS.md §6.0 states the scoring boundary
that was applied uniformly, which is the thing four judges had drawn in four places.

**Method, and the three differences from run 1.** Same four contracts, same three artifacts, same
five questions, same two reader models, two repeats — 48 readings, 240 answers, scored 0/1.
Differences: the artifacts were **re-cut on the repaired binary**; readers ran **inside a workflow at
fixed medium effort** (run 1's were single-turn Claude Code subagents at harness default); the packet
header was the bare word `Document`, so run 2's readers did **not** know which artifact kind they had
(run 1's did — _"a diagram … in the GraphViz DOT language"_), which makes them **more** blinded, not
less; and **both scoring rules were stated verbatim**, where run 1 had one in the prompt and one
inferred. **Those three changes are why the across-run delta is weaker evidence than any comparison
made inside a single run**, and why §7.3's condition is read below off run 2's own three columns
rather than off a run-1-to-run-2 difference.

**Accuracy, correct/readings** (a per-contract cell is 2 models × 2 repeats; pooled is 16):

| contract            | artifact   | Q1        | Q2        | Q3        | Q4        | Q5        | all                                  |
| ------------------- | ---------- | --------- | --------- | --------- | --------- | --------- | ------------------------------------ |
| `contracts`         | A / B / C  | 4 / 4 / 4 | 4 / 4 / 4 | 4 / 4 / 4 | 4 / 4 / 4 | 2 / 4 / 4 | 18 / 20 / 20 of 20                   |
| `every-run-example` | A / B / C  | 4 / 3 / 4 | 4 / 4 / 4 | 4 / 4 / 4 | 2 / 4 / 4 | 4 / 4 / 4 | 18 / 19 / 20 of 20                   |
| `tenancy`           | A / B / C  | 4 / 2 / 3 | 1 / 3 / 4 | 1 / 4 / 4 | 4 / 4 / 4 | 2 / 3 / 4 | 12 / 16 / 19 of 20                   |
| `promissory-note`   | A / B / C  | 4 / 2 / 2 | 4 / 4 / 4 | 3 / 2 / 2 | 4 / 2 / 2 | 3 / 1 / 4 | 18 / 11 / 14 of 20                   |
| **pooled**          | **A** list | **16/16** | 13/16     | 12/16     | 14/16     | 11/16     | **66/80** (Q1–Q3 41/48, Q4–Q5 25/32) |
|                     | **B** DOT  | 11/16     | 15/16     | 14/16     | 14/16     | 12/16     | **66/80** (Q1–Q3 40/48, Q4–Q5 26/32) |
|                     | **C** BPMN | 13/16     | 16/16     | 14/16     | 14/16     | 16/16     | **73/80** (Q1–Q3 43/48, Q4–Q5 30/32) |

With `promissory-note` removed — the contract §7.7a's first paragraph is about — Q1–Q3 reads
**A 30/36, B 32/36, C 35/36**, and the list is last. Both cuts are stated in RESULTS.md §6.4.2; the
four-contract figure is the run as designed, and the note is the one contract whose key has just been
re-derived from the tree.

**The largest single effect in the run is the reader, not the artifact.** By model: haiku A 28/40,
B 30/40, C 33/40 (91/120); sonnet A 38/40, B 36/40, C 40/40 (114/120). **A 23-answer gap between two
reader models, against a three-answer spread between the three artifacts on Q1–Q3.** The two repeats
of a cell agreed exactly in 17 of 24 cells, against run 1's 16.

**THE CONTROL.** The re-cut left four (contract, artifact) cells byte-identical between the runs —
`every-run-example/B`, `tenancy/B`, `promissory-note/B`, `promissory-note/C`: 80 answers on documents
that did not move.

> **23 of 80 answers flipped (28.8%), and the total moved 61/80 → 60/80, a drift of −1.** Inside the
> gate's Q1–Q3 window the control moved 35/48 → 36/48, **+1**. Over the eight cells whose document
> _did_ change, the experiment moved **+19 of 160**. Per answer the instrument is noisy; in total it
> is nearly flat, and the experiment moved further on the documents that changed than the instrument
> moved on the ones that did not.

Run 1's limit (vi) — _"a one- or two-answer difference in a column of sixteen is within what a rerun
could reverse"_ — holds per answer and is what the 28.8% measures. The packet header and effort
setting also differ (§6.1), so that figure is reader-framing-plus-model-plus-judge variance, not
sampling variance alone, and **a true test-retest has still never been run.**

**What survives the control, because each is tied to a specific sentence in a specific artifact:**

1. **The repair works, and completely on two contracts.** `contracts` A Q2 **1/4 → 4/4** and that
   contract's A total 11/20 → 18/20; `promissory-note` A Q2 **2/4 → 4/4** and its A total 9/20 →
   18/20. Both contracts' B and C cells were unchanged or near-unchanged, so no drift carries them.
2. **Printing the answer does not guarantee it is read.** `tenancy` A Q2 **1/4 → 1/4**, although the
   list now prints all three tenants' payments with their consequences. Two haiku readers said a bare
   "cannot tell"; one sonnet reader recited the acts and then said the artifact "does not say what
   event(s) would actually discharge what is owed". The heading differs between the contracts —
   `contracts` and `promissory-note` print under _"What would discharge it"_ and `tenancy` under
   _"What would move things along"_, which does not contain the word Q2 asks with. Untested
   hypothesis, cheap to test.
3. **A line added for precision cost most of a column.** `tenancy` A Q3 **4/4 → 1/4**. The only change
   to that part of the artifact is an appended clause — _"; the breach names, in order: Tenant Alice,
   Tenant Bob, Tenant Carol"_ — which faithfully renders `lts.json`'s `names` beside its `party`, and
   which three of four readers turned into a collective breach where all four run-1 readers, given the
   shorter line, did not. The fourth quoted the names **and** kept Alice as the party in breach, which
   is the existence proof that the clause is ambiguous rather than wrong. **Not the repair's doing**:
   it is `unstable` drift the re-cut picked up. The fix is a wording change distinguishing _who is in
   breach_ from _whose names the breach carries_ — a distinction `lts.json` draws and the sentence
   does not.
4. **Run 1's loud-versus-silent split is reproduced.** Of the list's 14 misses, 10 are refusals; of
   the DOT's 14, 11 are confident wrong answers. That is run 1's §3 finding, and it now stands on
   readings that can be re-read rather than on rationales alone.

#### Does the §7.3 ruling still stand?

**Yes, on this measurement. The ruling's first reopening condition is NOT met.**

§7.3 rules NO on four grounds, of which point 1 is the load-bearing one: _"the gate is conjunctive,
and on its own three questions the list is not beaten"_ — A 39/48, B 41/48, C 42/48 in run 1, with
the sharper sub-claim that _"on Q1 and Q3 alone the list is ahead of both pictures"_. Its reopening
condition (a) is _"the repaired list still failing Q1–Q3 when these same 48 readings are rerun"_.

**Measured, run 2: A 41/48, B 40/48, C 43/48.** The repaired list is **second of the three** on the
gate's own three questions — one answer ahead of the DOT, two behind the BPMN, a spread of three over
48, which is the same shape run 1 gave and is what point 1 called _"not beaten"_. Point 1's sub-claim
splits: on **Q1 the list is unbeaten and now perfect, 16/16** against 11/16 and 13/16, every Q1 miss
in the run being on a picture; on **Q3 it is behind both by two** (12/16 against 14/16 and 14/16),
which is the half that fails — and item 3 above identifies one repairable sentence as its cause.

**Three things go to Meng with that, and none is a softening.**

_First, the note-excluded cut disagrees._ Drop `promissory-note` and the list **is** last on Q1–Q3,
30/36 against 32/36 and 35/36. Excluding it is not a neutral robustness check — it is the contract
where the list beats both pictures by seven answers and the one whose key was just re-derived — but
it is the cut on which condition (a) would be met, and it is stated here rather than left to be
found.

_Second, the run undercuts §7.3's own counterweight._ Point 5 is that _"on Q4 and Q5 the list loses
badly — 11/32, against B's 30/32 and C's 24/32"_. In run 2 the list is at **25/32**, level with the
DOT's 26/32. The repair moved the list on exactly the two questions §1.1a says a list cannot answer.

_Third, the run cannot bear much weight in either direction._ The reader-model gap (23 of 120) is
seven times the artifact spread being read off it; `tenancy` Q2 is 1/4 with the answer printed on the
page, which is a finding about readers no amount of printing fixes; and nothing here shows that **a
list** cannot answer Q3, A's Q3 column being held down by one wording defect that is not the repair's.

**Recommended to the ruling's owner, as a recommendation and not a decision:** re-word the
breach-names clause; re-cut `promissory-note/history.txt`'s conversion table, which still converts
739769 and not 739752 and is what B and C readers are shown; run the test-retest the control calls
for, so the next comparison has an error bar. **What this run does not support is building P2d on
it** — the gate's own question came back with the list second of three and unbeaten on Q1.

---

## 8. Open rulings

In the style of the other track specs: questions this document could not settle, recorded
rather than assumed benign. R11 and R12 are new in revision 2; R13 was added on 2026-09-14 with §4.8 and answered on 2026-09-15; R1, R7, R8 and R12 were answered on 2026-09-16.

| #       | Ruling needed                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **R1**  | **ANSWERED 2026-09-16 (Meng), see §2.3a: coexist.** `labelModal` stays on the transition as the extractor's reading; the norm plane's `LiveNorm.lnModal` / `NormKey.nkModal` is the semantics, which is where the three published formalisms put it. Measured: fifteen static read sites (BPMN export, DOT, dominators, two tests) with no event stream to read a marking from, so "move" would mean a static norm plane invented to hold one enum. The witness that the hazard is disagreement, not location, is `d544ed22`. Residue: a P2d drawing rule (`Dot.hs:225` stops printing the modal on edges when both planes are drawn) — _moot as of 2026-09-21, P2d not being built (§7.3 ruled NO), unless that gate reopens_. Reopen conditions and all four positions are recorded in §2.3a. The original question: does `labelModal` move off `TransitionLabel`, or coexist with the norm plane? §2.3 argued move; revision 1 deferred for P1; revision 2 said that reason had expired.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| **R2**  | **Is `AllOf` a fork, or a fork with a join?** The shipped IR makes it a **fork with no join**: branches fan out and converge on a **shared** `Fulfilled` sink (`getTerminalState`, `:204-209`) that nothing waits at. `EVERY-EACH-QUANTIFIER-SPEC` §3.1 commits `EVERY` to **barrier semantics**, an AND-join firing HENCE once. The evaluator has a real join (`Machine.hs:1635-1707`, with blame assignment and the CSL tie-break). So the IR is the outlier. P1 reached the same place independently and reports it as `P-NOJOIN`. **UPDATED 2026-09-14 — the mitigation has expired.** Revision 2 wrote _"mitigating: `EVERY`/`EACH` are **unimplemented**"_; true when written, false now. The front end merged as PR #360 (`734b8015`, 2026-09-07), evaluation as PR #370 (`6247ba69`, 2026-09-08), `EVERY Cast v IN xs` as PR #374 (`28c48e3f`, same day). The join is **first-class in the AST**: `Deonton.join :: Maybe (Join n)` (`Syntax.hs:422-426`), with `JoinOnce` (`ONCE …`, level-triggered — the barrier) and `JoinUpon` (`UPON EACH`, edge-triggered — the fork) at `Syntax.hs:491-497`; the type checker makes it **mandatory** under an `EVERY` carrying `HENCE`/`LEST`, and an error under a `PARTY`. R2 is therefore no longer a question about a hypothetical: the language now draws the distinction and P2's input throws it away. §4.9. **LANDED 2026-09-15:** P2's input no longer throws it away — `labelQuantifier` carries `Barrier`/`Fork` structurally (P2h first half, §4.9). What remains of R2 is the drawing rule for the norm plane.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| **R3**  | **Under what condition does §2.4 re-open?** P2 declines a Petri-net _semantics_. If a TAPAAL lowering is later built, does P2 re-base onto it (gaining a checkable picture and **sound reachability**, inheriting the faithfulness obligation and the cross-validation harness) or stay a rendering of the evaluator? G9 raises the stakes: today P2 has no sound answer to the litigator's question at all. Deciding now is premature; deciding never is how two notions of "obligation" get shipped.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| **R4**  | **What crosses the §25.5 seam?** The handle is ladder-side, and PROCESS-TRACK §6 forbids P2 from depending on the ladder — so P2 can only define the state it _accepts_: obligation identity, valuation, rule version, and what else? Someone has to own the interface, and neither track may unilaterally.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| **R5**  | **Is the deontic step log optional or non-optional?** `traceEval` is optional and off by default; `tellEventRouted` is deliberately non-optional. Optional keeps the evaluator's hot path untouched and keeps P2b off M4's critical path. Non-optional means the residual can always explain itself, which is what an audit-grade tool-calling story wants. **ANSWERED 2026-09-15: OPTIONAL, off by default**, mirroring `cliDefaultPolicy` (`jl4-core/src/L4/TracePolicy.hs:97-101`), because §7.5 requires the evaluator's hot path untouched for M4 and P2b is built (on `lts/p2b-step-log`, merged into `lts/p2-stack` 2026-09-15, not yet in `unstable`) as `EvalState.deonticLog :: Maybe DeonticLog` with every call site behind that `Maybe` (`Machine.hs:286,359`). What non-optional would have bought — a residual that always explains itself — is available to any caller through `execEvalModuleWithDeonticLog` at the cost of asking; the audit-grade story can turn it on per request the way `#EVALTRACE` turns the trace on.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| **R6**  | **How is a re-offered event drawn?** §4.4. `dsScrutiny` records the distinction; it does not decide the rendering. One frame with a "witnessed" mark, or two frames with the second marked "re-offered"? Getting this wrong makes the animation lie about how many things happened.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| **R7**  | **ANSWERED 2026-09-16 (Meng), see §1.2: _"Unranked; the derived-view column is the commitment."_** The `BPMN · Harel statechart · Petri net · DFA` list at `logic-not-flowcharts.md:1100` is co-equal; the row's **statechart / timeline** column is the promise, and §2.3's two-plane picture is what redeems it. No edit to the doc; PROCESS-TRACK §1's reading confirmed; §1.2's framing stands. The original question: it read as unranked and PROCESS-TRACK §1 read it that way, but the row predates P2, so it might never have been asked — "Ask Meng rather than infer; §1.2's whole framing depends on it."                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| **R8**  | **ANSWERED 2026-09-16, see §2.2 VERIFIED and §4.2a ANSWERED: confirmed, from the primary texts.** Lomuscio & Sergot's green/red partition of each agent's local states and the `O_i` semantics are quoted from the authors' copy of _Deontic Interpreted Systems_ (_Studia Logica_ 75(1):63-92, 2003, DOI `10.1023/A:1026176900459`, Definitions 5 and 8) and the companion _J. Applied Logic_ 2(1):93-116, 2004 paper (DOI `10.1016/j.jal.2004.01.005`, Definition 2); the characterisation §2.2 carried was right, with three caveats now recorded there (no transitions in the 2003 model; the colouring is absolute; `O_i` is correctness, not obligation-on-a-party). MCMAS's `RedStates` is verified from CAV 2009 (DOI `10.1007/978-3-642-02658-4_55`). Symboleo's lifecycle states were read off RE 2020 Fig. 2 (DOI `10.1109/RE48521.2020.00049`, p. 367) and the 2022 thesis Fig. 5.1 (p. 38); the full list is in §4.2a. The guessed `Expired`/`Terminated` exist but are **events**, not states; the `Suspended`→`Resumed` pair exists. All four DOIs were resolved via Crossref on 2026-09-16 before being written down.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| **R9**  | **Does P2 draw powers, or refuse?** G5 says a power changes the transition system, so it cannot be an edge in it. Symboleo gives powers their own lifecycle, which is one answer. Refusing and drawing the boundary is another, and is consistent with §25.5's own precedent of drawing the seam rather than pretending.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| **R10** | **Does P2f belong here or in the bounded-deontics work?** Sharpened by revision 2's unbundling: P2f no longer needs anything of P2's except the graph P0 already ships, so the case for it living here is weaker than it was. The query is that paper's contribution; the graph is `StateGraph`'s; the renderer may be P1's BPMN or a list. **Observation 2026-09-15 (still OPEN):** P2f was built on `lts/p2f-dominators` as a function over `StateGraph` (`L4.StateGraph.Dominators`) with **no dependency on the rest of P2** — not on the step log, the marking or the picture (its reader-facing wording of an `EVERY` act does read P2h-first-half's `labelQuantifier`, so it is stacked on that branch) — and it needed one thing of the graph the paper's definition does not mention: the `RAND` and `ROR` joins the IR lacks, supplied inside the module as `fulfilmentView` and `breachView`. That is evidence for the split the ruling proposes — the graph (and its join) is `StateGraph`'s, the query is the paper's — and the paper's §7 sentence _"the dominator query … designed and not yet built"_ is now false and should be updated when it is next touched.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| **R11** | **NEW. Does `STATEFUL` §6.4 need correcting?** §2.4 rules that P2 uses the replay endpoints (22/23/24) rather than 18/19/20, because "would lead to `FULFILLED`" cannot be answered by a pure walk without reimplementing modal routing. That is a finding **about `STATEFUL`'s own spec**, whose §6.4 promises exactly that pure walk with "microsecond responses". Either that spec should record the faithfulness obligation, or 19/20 should be re-specified as replay, or the pure walk should be kept behind a cross-validation test. Not P2's call alone. **OBSERVED 2026-09-15, not decided:** P2c's replay form (§2.4 block) measured 83–313 µs per candidate, warm, on the corpus's barrier and `contracts.l4` traces — inside the "microsecond responses" §6.4 promised for the pure walk, at trace lengths of one to three events. The replay's cost is linear in the persisted history (every prior event is re-scrutinised per candidate), so the promise is met today by the form §2.4 prefers and would stop being met at some history length nobody has measured. What §6.4 needs is therefore not a faster form but a number: the history length at which replay exceeds its budget, which is when a pure walk earns its faithfulness obligation. Still not P2's call alone.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| **R12** | **ANSWERED 2026-09-16, see §4.2a ANSWERED: `Lapsed` is ours, and stays.** Symboleo has one lifecycle per obligation instance; an alternative can be a separate obligation (which would simply be in `Violation`) or a disjunct of one obligation's consequent (`POr`, thesis Listing A.1 p. 149), and in neither encoding is there a state for "this disjunct is lost but the obligation stands". Its `Discharge` is reached by `Expired` from `Create` (the antecedent can no longer come true) or by `Discharged` from `InEffect` (the creditor's power), and `Unsuccessful Termination` is cancellation by a power or by the contract's termination — none of these involves a breach by the debtor, and either name would erase the blame `Lapsed` carries. (Corrected 2026-09-16: an earlier form of this row said Symboleo "has no compound obligations" and that `Discharge` is reached only from `Create`; both were sharper than the sources.) `Created`/`InEffect` are Symboleo's `Create`/`InEffect`; `Violated` stays Anderson/Meyer (Symboleo's state is `Violation`). No rename, so no P2c follow-up; the `Marking.hs` Haddock still reads "R12 open" and is NOT touched in this track (§4.2a NOT BUILT 2026-09-16 — the R8-R12 gate forbids Haskell, comments included). One hazard recorded: Symboleo's `Discharge` is _not_ discharge by performance — that is `Fulfillment`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
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
   `lapses`, and since 2026-09-21 that arm also names the clock that takes it — `lapses [30]`,
   `timeout [14]` — except where two clocks could both take it, an act deadline and a `BARRIER`
   join deadline, where it goes back to the bare word rather than guess which fired
   (`twoClocksTakeThisArm`, `jl4-core/src/L4/StateGraph.hs:1108-1119`; a `FORK` is not that case,
   because the join's deadline is dead there). `violation` never carries a bracket: what reaches
   it is an act, not a clock. Asserted in `jl4-core/test/StateGraphSpec.hs`, "LEST edge captions", and — for the
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
`2410.12585`, 2024. Sharifi, Parvizimosaed, Amyot, Logrippo & Mylopoulos, "Symboleo: Towards a
Specification Language for Legal Contracts", _RE 2020_ pp. 364-369, DOI
`10.1109/RE48521.2020.00049` (read; Fig. 2); Parvizimosaed, _Symboleo: Specification and
Verification of Legal Contracts_, PhD thesis, University of Ottawa, 2022,
<https://ruor.uottawa.ca/handle/10393/44186> (read; Fig. 5.1, Listing 7.4); Parvizimosaed,
Sharifi, Amyot, Logrippo, Roveri, Rasti, Roudak & Mylopoulos, "Specification and analysis of
legal contracts with Symboleo", _SoSyM_ 21:2395-2427, 2022, DOI `10.1007/s10270-022-01053-6`
(DOI resolved, text not read). Lomuscio & Sergot, "Deontic interpreted systems", _Studia Logica_
75(1):63-92, 2003, DOI `10.1023/A:1026176900459` (read, R8); Lomuscio & Sergot, "A formalisation
of violation, error recovery, and enforcement in the bit transmission problem", _J. Applied
Logic_ 2(1):93-116, 2004, DOI `10.1016/j.jal.2004.01.005` (read); Lomuscio, Qu & Raimondi,
"MCMAS: A Model Checker for the Verification of Multi-Agent Systems", CAV 2009, LNCS
5643:682-688, DOI `10.1007/978-3-642-02658-4_55` (read, §3). Natschläger, Deontic BPMN, DEXA 2011; Natschläger, Kossak &
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
