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
post-M4 work and belongs to neither track alone.

---

## 7. P2 — the process/LTS visualiser

**Now specified: [LTS-VISUALISER.md](./LTS-VISUALISER.md).**

Out of scope here, and it gets its own spec. Recorded so the boundary is explicit: the ambition
is to draw the transition system _better than BPMN can_, with the Petri-net lineage from earlier
work as the starting point — token game, trace animation, and the deontic distinctions F1 says
BPMN cannot make.

It depends on P0 (it wants the same junction concept) and on nothing else here. It must not
gate M4.
