# The process track — `StateGraph` and BPMN export

_Scoped 2026-07-25. Track P of [SPEC.md](./SPEC.md). **Deliberately independent**: this track
shares nothing with the decision-side track ([GUARDED-ROWS.md](./GUARDED-ROWS.md)) except the
CLI and service surface, and can be built in parallel by someone else._

---

## 1. Why BPMN is the right target here, and only here

`doc/concepts/language-design/logic-not-flowcharts.md` argues that drawing a _predicate_ as a
flowchart is a category error. It does not argue that process notation is worthless. A
regulative rule — `PARTY p MUST a WITHIN d HENCE … LEST …` — genuinely **is** a transition
system, and drawing it as one says nothing the source did not.

So the division of labour is principled rather than tactical:

- the **constitutive** layer (`DECIDE`, boolean structure) → ladder, and DMN where it fits;
- the **regulative** layer (`Regulative`/`Deonton`) → state graph, and BPMN where it fits.

Exporting BPMN from the regulative layer is us using the notation for the thing it is for.
Lexipedia's error is not that they used BPMN; it is that they drew _both_ layers with it.

---

## 2. What already exists

`jl4-core/src/L4/StateGraph.hs` — Contract-as-Automaton extraction, after Flood & Goodenough,
reachable from `l4 state-graph` and (because it is in `jl4-core`) from `jl4-service` too. It
already carries almost exactly what BPMN needs:

```haskell
data TransitionLabel = TransitionLabel
  { labelParty    :: Maybe Text            -- ^ → lane / pool
  , labelModal    :: Maybe DeonticModal    -- ^ → nothing. see §5.
  , labelAction   :: Text                  -- ^ → task name
  , labelDeadline :: Maybe Text            -- ^ → timer boundary event
  , labelGuard    :: Maybe Text            -- ^ → conditionExpression
  }

data TransitionType = HenceTransition | LestTransition | DefaultTransition
data StateType = InitialState | IntermediateState | TerminalFulfilled | TerminalBreach
```

Today it has one renderer, `stateGraphToDot`. P1 adds a second.

---

## 3. The mapping

| `StateGraph`                     | BPMN 2.0                                                               |
| -------------------------------- | ---------------------------------------------------------------------- |
| `StateGraph`                     | `<process>` (in a `<collaboration>` when there is more than one party) |
| `labelParty`                     | `<lane>`, or a pool per party                                          |
| a `Transition`                   | `<task>` — the _action_ is the work; the states are its endpoints      |
| a state with >1 outgoing `Hence` | `<exclusiveGateway>`                                                   |
| `InitialState`                   | `<startEvent>`                                                         |
| `TerminalFulfilled`              | `<endEvent>` (none)                                                    |
| `TerminalBreach`                 | `<endEvent>` with `<errorEventDefinition>`                             |
| `HenceTransition`                | the task's normal outgoing `<sequenceFlow>`                            |
| **`LestTransition`**             | **a `<boundaryEvent>` on the task** — interrupting                     |
| `labelDeadline`                  | that boundary event's `<timerEventDefinition>`, ISO 8601 duration      |
| `labelGuard` (`PROVIDED`)        | `<conditionExpression>` on the outgoing flow                           |

**`LEST` is a boundary interrupting event.** That is the one genuinely satisfying line in this
table: L4's "if the obligation is not discharged, go here instead" is precisely what BPMN
boundary events exist to express, and a deadline-carrying `LEST` is exactly a timer boundary
event. Where the notations agree, they agree well.

### 3.1 Diagram interchange is not optional

A BPMN file without `<BPMNDiagram>` / `<BPMNPlane>` / `<BPMNShape>` / `<BPMNEdge>` coordinates
is not a usable deliverable — the whole point of K4 is that someone can open it in Camunda
Modeler. So P1 must emit DI with real coordinates.

State graphs are small, so a layered left-to-right assignment from the topological order is
sufficient; there is no need to reach for the BBE engine (which is built for ladders and the
wrong shape here) or to shell out to GraphViz for positions.

---

## 4. P0 — the IR gap, found while scoping

`extractExpr` (`StateGraph.hs:240-248`) handles `RAnd` and `ROr` **identically**:

```haskell
  RAnd _ e1 e2 -> do
    -- Parallel composition: both obligations must be fulfilled
    extractExpr mFromState e1
    extractExpr mFromState e2

  ROr _ e1 e2 -> do
    -- Choice: either obligation can be fulfilled
    extractExpr mFromState e1
    extractExpr mFromState e2
```

The comments state the distinction; the code does not make it. Both cases fan two transitions
out of one state, and the resulting graph cannot say whether that fan is a **conjunction** (do
both) or a **choice** (do either). GraphViz output has been getting away with it because a
reader supplies the intent. BPMN cannot: it is a `<parallelGateway>` or an `<exclusiveGateway>`,
and picking the wrong one inverts the meaning of the diagram.

**P0 is therefore: give the IR a junction concept** — states gain a fan kind (`AllOf` /
`OneOf` / `Linear`), populated from `RAnd` / `ROr`, and the DOT renderer starts drawing the
distinction too. This is a prerequisite for P1 and an outright bug fix for the existing
renderer.

### 4.1 Why the flagship example forces this immediately

The Reg CF obligation tail is drawn by Lexipedia as a straight line: check limits → prepare
disclosures → select intermediary → comply with advertising restrictions → prepare ongoing
reporting → understand resale restrictions.

It is not a line. Those are **concurrent obligations with different bearers and different
temporal extents**: some are one-shot filings with deadlines, one is a standing prohibition on
the issuer for the life of the offering, and the resale restriction binds a _different party_
(the investor) for a period after it. Rendering that as a sequence invents an ordering the
regulation does not impose — which is the same defect the critique names in their gateways,
appearing again in the tail.

So the exporter cannot dodge P0: getting this example right **requires** the parallel gateway,
and getting it right is the entire point of the exhibit.

---

## 5. The fidelity report

Emitted alongside the XML, naming what BPMN could not carry. Known losses, in descending
severity:

| #   | Loss                                                                                                                                                                                                                                                            |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| F1  | **Deontic modality.** `MUST`, `MAY` and `SHANT` all become "a task". BPMN has no way to say that skipping this one is a breach while skipping that one is fine. `DMustNot` is worst served: a prohibition is not a task at all.                                 |
| F2  | **Bearer vs performer.** A lane says who _does_ it; a deontic says who _owes_ it. These come apart whenever an agent acts for a principal — the case the actor-indexed actions work exists to model.                                                            |
| F3  | **Vacuity.** An obligation that never became applicable is not the same as one that was discharged. BPMN has one kind of "did not happen".                                                                                                                      |
| F4  | **Guard bodies.** A `PROVIDED` condition backed by a whole ladder becomes an opaque `conditionExpression` string. DMN would be the right home, but the DMN↔BPMN link is an _association_, not a semantics — which is exactly the seam the critique identifies. |
| F5  | **Rule version.** BPMN has no as-of-date. A threshold that changes is a number someone has to remember to edit.                                                                                                                                                 |

F1 and F5 are the two that matter for the argument, and neither is a criticism of the
exporter — they are properties of the target notation, which is why naming them is a feature
rather than an apology.

---

## 6. Independence contract

What this track may **not** depend on, so it can proceed in parallel:

- nothing in `GuardedRows` or the ladder;
- nothing in `ts-shared/`;
- no change to `VizExpr`.

Shared surfaces, agreed in advance so they do not collide:

- `l4 export --to=bpmn` alongside `--to=dmn`, sharing only the `--fidelity-report` flag and its
  output shape;
- one `jl4-service` export endpoint family, parameterised by target.

The one soft coupling worth stating: **F4 is where the two tracks meet.** When both exist, a
guard exported to BPMN can reference a decision exported to DMN. Wiring that association is
post-M4 work and belongs to neither track alone. (Since ruled **mandatory** — see §8.3.)

---

## 7. P2 — the process/LTS visualiser

**Now specified: [LTS-VISUALISER.md](./LTS-VISUALISER.md).**

Out of scope here, and it gets its own spec. Recorded so the boundary is explicit: the ambition
is to draw the transition system _better than BPMN can_, with the Petri-net lineage from earlier
work as the starting point — token game, trace animation, and the deontic distinctions F1 says
BPMN cannot make.

It depends on P0 (it wants the same junction concept) and on nothing else here. It must not
gate M4.

---

## 8. The acceptance bar — ruled 2026-08-01

Meng, 2026-08-01, verbatim: _"Let me rule roughly that, with the modification that the emitted
BPMN should wire together with the emitted DMN. We started by looking at the Lexipedia BPMN
and commenting that the sorrow is obvious. We have to show the better way: BPMN delegating
decisions to DMN."_

As adopted:

- **The exhibit is the diagram and its soundness.** The bar is **acceptance**: the emitted
  file renders in Camunda Modeler / bpmn-js (`etc/validate-bpmn.mjs`) and passes the
  exhaustive soundness gate (`etc/check-bpmn-soundness.mjs`). jBPM (`etc/check-bpmn-kie.sh`)
  corroborates where its dialect allows; it is evidence, not a gate, and §8.1 decomposes
  exactly where its dialect does not allow.
- **Engine execution is a NON-GOAL**, because process execution runs on the parties. A BPMN
  process here describes work that people and firms do; nothing in the demo asks an engine to
  do it for them.
- **Guard executability, when it is wanted, arrives via BPMN→DMN linkage** — a
  `businessRuleTask` invoking an emitted decision, with gateway guards reduced to trivial
  tests over that decision's output — **never** by lowering law text into an engine's
  expression dialect. Declining to lower is the `P-BRANCHGUARD` fidelity stance working as
  designed (§8.1 class (b) is that stance, measured).
- **The emitted BPMN MUST wire to the emitted DMN.** That is the demo's better-way exhibit:
  lexipedia advertises BPMN _and_ DMN, ships no DMN, and draws its decisions as gateways
  (see [SPEC.md](./SPEC.md)); we show BPMN delegating decisions to DMN. §8.3 sketches the
  design; it is not built.

### 8.1 The two classes of jBPM REJECTED — measured 2026-08-01

Every `REJECTED` verdict in `etc/bpmn-kie-baseline.txt` decomposes into exactly two classes.
Re-measured 2026-08-01 by running `etc/check-bpmn-kie.sh jl4/examples/bpmn/expected/*.bpmn`
(jbpm-bpmn2 7.74.1.Final, JDK 17.0.20):

| class | files (errors)                                        | what jBPM says                                                                             | what it is                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ----- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| (a)   | regcf-reporting (1)                                   | `Unknown gateway direction: Mixed`                                                         | `Mixed` is legal BPMN 2.0 (§10.5.2); jBPM does not implement it. **Not fixable at the attribute level — measured 2026-08-01**: all four `gatewayDirection` values were run against this file's 2-in/3-out gateway and all four are rejected (`Unspecified` → `Unknown gateway direction: Unspecified`; `Diverging` → `cannot have more than one incoming connection!`; `Converging` → `cannot have more than one outgoing connection!`). jBPM models a gateway as either a split or a join, chosen by this attribute, and has no node for a gateway that is both — the **shape** is what it will not have. So class (a) is a documented engine delta like class (b), for a different reason; `Mixed` stays emitted because it is the truthful value and the one `check-bpmn-soundness.mjs` can hold against the edges (`Unspecified` it skips). The only jBPM-acceptable form would be a structural converging→diverging split of the node — recorded as an option, not built, not ruled. |
| (b)   | regcf-advertising (4), regcf-resale (6), handover (4) | `mismatched input 'WITHIN'`, `Unable to Analyse Expression …`, `mismatched input 'period'` | jBPM compiling our **deliberately opaque** L4-text expression bodies (sequence-flow `conditionExpression`s and conditional boundary-event conditions) as Drools rule expressions. The `P-BRANCHGUARD` fidelity stance working as designed — not a defect, and not to be "fixed".                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

(What measurement changed: an earlier draft of this section, committed hours before, called
class (a) "a defect against this bar" and prescribed emitting `Unspecified` where `Mixed` is
computed. The prescription was implemented, run, and **falsified the same day** — jBPM rejects
`Unspecified` with the same exception — so the change was reverted before it shipped and the
row above records the full four-value probe instead. The probe evidence also lives at
`gatewayFlowFor` in `jl4-core/src/L4/Bpmn/Lower.hs` and in
`jl4/examples/bpmn/unsound/README.md`.)

The two non-REJECTED verdicts are worth naming too:

- **offering.bpmn `ABORTED`** — "via error end event [Breach] — a modelled terminal state,
  not a liveness defect". jBPM executed it fine and reached the modelled `Breach` terminal:
  the `LEST` arm doing its job. An exhibit, not a failure.
- **consultation.bpmn `COMPLETED`** clean.

### 8.2 What the bar means operationally

`validate-bpmn.mjs` + `check-bpmn-soundness.mjs` green on every emitted golden = the bar is
met. The jBPM baseline (`etc/bpmn-kie-baseline.txt`) records corroboration standing,
measured-not-intended; class (b) reds stay red there **by design** until §8.3 exists, and
regenerating that file to green by weakening the opaque guards would be lowering law text
into engine dialect — refused above.

### 8.3 The DMN wiring — mandated 2026-08-01, design sketched here, NOT BUILT

**Status: mandated 2026-08-01; what follows is a design sketch, not a description of the
tree. Nothing below is built.** Build was gated on DMN Phase 5 BKM emission, which has
**LANDED** (PR legalese#188, merged to `unstable` 2026-08-01, commit `973bdf93` — the branch
`mengwong/dmn-phase5-bkm` is no longer in flight): a `businessRuleTask` needs a decision to
call before wiring one is meaningful, and the decisions now exist.

**DMN-side prerequisite DISCHARGED 2026-08-02 (R13, `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §16):**
the stable verdict decision now exists. `ongoing reporting obligation` emits as a real decision
table (`decision_ongoing_reporting_obligation`, `typeRef="string"`, enumerated `outputValues` =
the three arm verdicts), designed as the interface this wiring consumes: a gateway's outgoing
flows compare against the enumerated verdict strings. The wiring itself remains **NOT BUILT** — a
named follow-up ("BPMN businessRuleTask wiring", scoped out of the R12/R13 PR deliberately, see
DMN spec §16.5) — and everything below this line is still a sketch, including the anonymous-guard
question (`annual cycles AT MOST 0` now HAS a DMN home: it is a column of the verdict table, not a
decision of its own, which sharpens rather than answers the open probe).

The sketch:

- one `businessRuleTask` **preceding each guarded exclusive gateway**, invoking the DMN
  exporter's decision for the guard's predicate, referenced by its **emitted** id/name. That
  makes coordination with the DMN side's `uniquifyIn` naming
  (`DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §5.2) a design constraint recorded now: the BPMN side
  must consume the names the DMN exporter emitted, not re-derive them from the L4 source;
- each outgoing flow's guard becomes a **trivial test over the decision's declared output**
  (compare-to-output-value, no L4 text), replacing the opaque `conditionExpression` for
  engines while the L4 text stays available as documentation;
- **open probe — the flavor question.** How the `businessRuleTask` names its decision is
  engine-flavored: Camunda 7 `camunda:decisionRef`, Camunda 8 `zeebe:calledDecision`, or the
  pure BPMN 2.0 `implementation` attribute. Recorded as an open probe, to be measured rather
  than presumed, with the DMN flavor split (`DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §13.7) as
  precedent;
- **`P-BRANCHGUARD`'s endgame.** The linkage partially discharges `P-BRANCHGUARD`'s fidelity
  note: exhaustiveness and mutual exclusion of a gateway's arms live in the DMN table's
  `UNIQUE` hit policy, where they belong. That is the **intended endgame, not current
  behaviour** — today the finding still reports the loss, and must keep doing so until the
  wiring exists.
