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

| #      | Ruling                                                                                                                                                                                                                                                     |
| ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Q1** | **REVISED.** P2 answers **position**. Reachability it can only over-approximate (G9); dominance it can answer without a new picture (P2f). A P2 that only draws a prettier static graph still should not be built. §1                                      |
| **Q2** | The formalism is a **two-plane marked transition system** — an action plane and a norm plane — with the drawing vocabulary borrowed from Petri markings, Symboleo lifecycles and Meyer's violation atom. §2                                                |
| **Q3** | **SCOPED.** The evaluator is the semantics **for the marking and the step log**. Anything counterfactual — the enabled set, the discharging/breaching partition — must be computed **by running the evaluator**, not by walking a residual. §2.4           |
| **Q4** | The animated data is a new **deontic step log**, modelled on `traceEval`. It does not exist today; it is ~6 call sites in `Machine.hs`. The type is now defined, in §4.3.                                                                                  |
| **Q5** | **The bare Petri net is not better than BPMN at F1.** What closes F1 is reifying the norm as a marked place, which a net permits and BPMN has no vocabulary for. That is encodability, not expressiveness. §2.1                                            |
| **Q6** | P1 emits a **file**; P2 renders a **view**. Two pictures, one stated division of labour. §5.1                                                                                                                                                              |
| **Q7** | **REVISED.** The smallest useful first deliverable is **P2a′ — render the projections as a plain list and see whether anyone still wants a picture.** It is cheaper than the BPMN-simulator baseline, and it tests the question P2 actually leads with. §7 |
| **Q8** | **NEW.** `StateGraph` as shipped **cannot** be P2's layout scaffold. It carries no key a runtime obligation can be correlated to, and it does not close loops. Both are P2 preconditions, and both are now cheaper than they were. §3.4                    |

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
| **Anderson 1958** (_Mind_ 67(265):100-103); **Meyer 1988** (_NDJFL_ 29(1)) — `Fα ↔ [α]V`, `Pα ↔ ⟨α⟩¬V`                             | A distinguished **violation atom**. The three modals differ only in which transitions reach `V`.                                                                                                                | The reduction itself, and its price. §6 G4           |
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

### 4.4 The gotcha the animator must model: an event can be scrutinised twice

Expiry re-offers the revealing event to the continuation, at most once, marked by store address
(`markReoffered`/`isReoffered`, `Machine.hs:516-524`; the rule is documented at `:1480-1526` and
again in `ContractFrame.hs:68-75`). It exists to keep recursive `HENCE`/`LEST` continuations with
non-positive deadlines terminating — the motivating case in the comment being
`x MEANS PARTY p MUST a WITHIN d LEST x`.

A naive "one event, one animation frame" misrepresents this. `dsScrutiny` is the explicit
**witness-versus-consume** distinction, and the scrubber must be able to show the same event
twice without the viewer concluding it happened twice.

**And this is precisely where §3.4's B2 bites.** The motivating contract is recursive; the board
`StateGraph` draws for it does not close its loop; so the animator has nowhere to put the token
on the second scrutiny. The gotcha and the missing loop are the same problem seen from two sides.

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
and does not need an export format. If P2 ever grows one it becomes a second interchange
target with a second faithfulness obligation, and that is a new decision.

One thing P1 shipping **does** change: B1 and B2 are edits to a type P1 now depends on, so P2's
preconditions are no longer free of P1 — they cost golden regeneration and a re-run of
`etc/validate-bpmn.mjs`. Cheap, but no longer zero. §7.1.

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
    the other direction, and it did not exist when revision 1 claimed independence.
- **Nothing in Track D, the ladder, `ts-shared/`, or `VizExpr`** — PROCESS-TRACK §6 holds.
- **Live mode only** depends on `STATEFUL-CONTRACT-DEPLOYMENT` §3.1, which is somebody else's
  blocker. §4.5.

### 7.2 Staging — two experiments, then a gate, then maybe a picture

| ID       | Work                                                                                                                                                                                                        | Depends on   | Gates M4? |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ | --------- |
| **P2b**  | `tellDeonticStep` + the `DeonticStep` type of §4.3. ~6 call sites in `Machine.hs`. **No renderer.** Tested in Haskell alone against `contracts.golden`. **Recommended unconditionally.**                    | —            | no        |
| **P2c**  | The enabled set and the discharging/breaching partition, in the **replay** form (`STATEFUL` §6.5 endpoints 22/23/24), per §2.4. Plus `markingOf` (§4.2a) as a library function.                             | P2b          | no        |
| **P2a′** | **The list baseline, and the primary gate.** Render §4.2a's marking + endpoints 17/19/20 as plain text — CLI first. Put it in front of readers against the same contract drawn by `stateGraphToDot` and P1. | P2c          | no        |
| **P2a**  | **The picture baseline.** Point `bpmn-io/bpmn-js-token-simulation` (MIT) at P1's shipped output and write down, case by case, what it cannot say.                                                           | P1 (shipped) | no        |
| **P2f**  | **Unbundled.** `dom_s(J)` by Lengauer–Tarjan over `StateGraph`, answered as a **set of acts** — printable as a list or as an annotation on P1's BPMN. **No new picture required.**                          | P0 (shipped) | no        |
| **B1**   | Carry the correlation key (§3.4). Regenerates BPMN goldens.                                                                                                                                                 | P1           | no        |
| **B2**   | Close the loop (§3.4). Makes `P-CYCLE` reachable; see §4.7.                                                                                                                                                 | B1           | no        |
| **B3**   | Layout: Haskell ranks with a feedback-edge set, TS draws (§4.7).                                                                                                                                            | B2           | no        |
| **P2d**  | The P2 IR and the **static** two-plane picture. No animation. **Gated: build only if §7.3's condition is met.**                                                                                             | P2c, B1-B3   | no        |
| **P2e**  | The animator: scrubber, token, marking, enabled-set highlight. TypeScript, per K6.                                                                                                                          | P2d          | no        |

**Ordering is now explicit**, which revision 1's table was not (it said "P2a first" in prose while
giving P2b no dependency): **P2b → P2c → P2a′, with P2a and P2f runnable in parallel at any
time.** P2b and P2c come first because P2a′ needs data to list, and because they are the two
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
and so must land **after** M4 ships or be scheduled with it deliberately. P2 is M6 and stays
there.

---

## 8. Open rulings

In the style of the other track specs: questions this document could not settle, recorded
rather than assumed benign. R11 and R12 are new in revision 2.

| #       | Ruling needed                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **R1**  | **Does `labelModal` move off `TransitionLabel`, or coexist with the norm plane?** §2.3 argues it should move; three published formalisms put deontic status on states or places, and our IR is the odd one out. Revision 1 deferred this because "P1 is mid-flight"; **P1 has now shipped, so that reason has expired** and the question is live. It remains a P0-scale change if taken.                                                                                                                                                                                                                                            |
| **R2**  | **Is `AllOf` a fork, or a fork with a join?** The shipped IR makes it a **fork with no join**: branches fan out and converge on a **shared** `Fulfilled` sink (`getTerminalState`, `:204-209`) that nothing waits at. `EVERY-EACH-QUANTIFIER-SPEC` §3.1 commits `EVERY` to **barrier semantics**, an AND-join firing HENCE once. The evaluator has a real join (`Machine.hs:1635-1707`, with blame assignment and the CSL tie-break). So the IR is the outlier. Mitigating: `EVERY`/`EACH` are **unimplemented**. P1 reached the same place independently and reports it as `P-NOJOIN`. It becomes live the moment P2 draws `RAND`. |
| **R3**  | **Under what condition does §2.4 re-open?** P2 declines a Petri-net _semantics_. If a TAPAAL lowering is later built, does P2 re-base onto it (gaining a checkable picture and **sound reachability**, inheriting the faithfulness obligation and the cross-validation harness) or stay a rendering of the evaluator? G9 raises the stakes: today P2 has no sound answer to the litigator's question at all. Deciding now is premature; deciding never is how two notions of "obligation" get shipped.                                                                                                                              |
| **R4**  | **What crosses the §25.5 seam?** The handle is ladder-side, and PROCESS-TRACK §6 forbids P2 from depending on the ladder — so P2 can only define the state it _accepts_: obligation identity, valuation, rule version, and what else? Someone has to own the interface, and neither track may unilaterally.                                                                                                                                                                                                                                                                                                                         |
| **R5**  | **Is the deontic step log optional or non-optional?** `traceEval` is optional and off by default; `tellEventRouted` is deliberately non-optional. Optional keeps the evaluator's hot path untouched and keeps P2b off M4's critical path. Non-optional means the residual can always explain itself, which is what an audit-grade tool-calling story wants.                                                                                                                                                                                                                                                                         |
| **R6**  | **How is a re-offered event drawn?** §4.4. `dsScrutiny` records the distinction; it does not decide the rendering. One frame with a "witnessed" mark, or two frames with the second marked "re-offered"? Getting this wrong makes the animation lie about how many things happened.                                                                                                                                                                                                                                                                                                                                                 |
| **R7**  | **Was `logic-not-flowcharts.md`'s state-transitions row intended as unranked?** It reads as unranked and PROCESS-TRACK §1 reads it that way, but it was written before P2 was contemplated, so it may simply never have been asked the question. **Ask Meng** rather than infer; §1.2's whole framing depends on it.                                                                                                                                                                                                                                                                                                                |
| **R8**  | **Verify Lomuscio & Sergot before print.** The green/red state-partition characterisation in §2.2 is from secondary sources; the primary PDF would not extract. It carries architectural weight (per-party colouring is the F2 shape). Symboleo's exact lifecycle state names are likewise search-verified rather than read — there is probably an `Expired`/`Terminated` and a `Suspended`→`Resumed` pair we have not recorded. §7.4's citation failure is the reason this caveat is now load-bearing rather than decorative.                                                                                                      |
| **R9**  | **Does P2 draw powers, or refuse?** G5 says a power changes the transition system, so it cannot be an edge in it. Symboleo gives powers their own lifecycle, which is one answer. Refusing and drawing the boundary is another, and is consistent with §25.5's own precedent of drawing the seam rather than pretending.                                                                                                                                                                                                                                                                                                            |
| **R10** | **Does P2f belong here or in the bounded-deontics work?** Sharpened by revision 2's unbundling: P2f no longer needs anything of P2's except the graph P0 already ships, so the case for it living here is weaker than it was. The query is that paper's contribution; the graph is `StateGraph`'s; the renderer may be P1's BPMN or a list.                                                                                                                                                                                                                                                                                         |
| **R11** | **NEW. Does `STATEFUL` §6.4 need correcting?** §2.4 rules that P2 uses the replay endpoints (22/23/24) rather than 18/19/20, because "would lead to `FULFILLED`" cannot be answered by a pure walk without reimplementing modal routing. That is a finding **about `STATEFUL`'s own spec**, whose §6.4 promises exactly that pure walk with "microsecond responses". Either that spec should record the faithfulness obligation, or 19/20 should be re-specified as replay, or the pure walk should be kept behind a cross-validation test. Not P2's call alone.                                                                    |
| **R12** | **NEW. Is `Lapsed` the right name, and is it Symboleo's?** §4.2a needs a lifecycle state for "this `ROr` alternative is definitively lost but the compound is not violated". Symboleo has `terminated` and possibly `expired`; whether either covers this, or whether we are coining, is unverified and folded into R8's reading task.                                                                                                                                                                                                                                                                                              |

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
Lengauer & Tarjan, 1979 (the dominator computation P2f needs). Sugiyama, Tagawa & Toda, "Methods
for visual understanding of hierarchical system structures", _IEEE SMC_ 11(2), 1981 (the
layered-layout phases §4.7 needs once B2 introduces cycles). Maslov & Poelmans, _I&M_ 61:103967,
2024, DOI `10.1016/j.im.2024.103967`; Maslov, Poelmans, Wautelet & Gailly, _JCL_ 84:101350, 2025,
DOI `10.1016/j.cola.2025.101350` (§7.4).
