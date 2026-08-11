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

`P-…` codes are a different animal, enumerated at their emission sites in
`jl4-core/src/L4/Bpmn/Lower.hs`: places where **this exporter** approximated or refused. Three of
them belong to §8.3 and are named here because they are the ones a reader of a Reg CF golden will
meet:

| code            | severity | says                                                                                                                                |
| --------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `P-BRANCHGUARD` | Lossy    | a gateway's arms are opaque L4 text, with no DMN behind them (the pre-§8.3 default, and still what an unwired gateway gets)         |
| `P-DMNWIRED`    | Advisory | the arms are decided by a named DMN decision; states the residual, which is that exhaustiveness now lives in the table's hit policy |
| `P-NODMN`       | Lossy    | a DMN was available and this gateway still could not be wired to it, with the reason                                                |

F4 above is the obligation-level counterpart and is untouched by §8.3: it is a `PROVIDED` on one
obligation, not a branch condition on a gateway, and nothing yet delegates it.

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
post-M4 work and belongs to neither track alone. (Since ruled **mandatory** — see §8.3 — and
**built 2026-08-02**.)

The coupling as built is exactly one module wide and one direction deep: `L4.Bpmn.Wiring` reads
`L4.Dmn.IR`, `L4.Dmn` reads nothing from `L4.Bpmn`, and `L4.Bpmn.IR` / `L4.Bpmn.Lower` import no
DMN module at all — they take a `DmnWiring` value or `Nothing`. Nothing on the list above was
touched.

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
  (see [SPEC.md](./SPEC.md)); we show BPMN delegating decisions to DMN. **BUILT 2026-08-02
  — §8.3.**

### 8.1 The classes of jBPM REJECTED — measured 2026-08-01, re-measured 2026-08-02

Every `REJECTED` verdict in `etc/bpmn-kie-baseline.txt` decomposes into a small closed set of
classes. Re-measured 2026-08-02 after the §8.3 wiring landed, by running
`etc/check-bpmn-kie.sh jl4/examples/bpmn/expected/*.bpmn` (jbpm-bpmn2 7.74.1.Final, JDK
17.0.20). **The per-file error COUNTS and verdicts did not move** — `errors=4/1/6`, `RESULT 4`,
exactly as baselined — but two of the three reasons did, so the rows below are the current
reading and not the 2026-08-01 one.

| class | files (errors)                                        | what jBPM says                                                                                              | what it is                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| ----- | ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| (a)   | — (retired 2026-08-02)                                | `Unknown gateway direction: Mixed`                                                                          | **GONE, and not by choosing a different attribute value.** `Mixed` was computed for `regcf-reporting`'s fan-out gateway because the `HENCE <this rule>` renewal loop gave it a second arrival. §8.3's `businessRuleTask` now sits in front of that gateway and absorbs _both_ arrivals, so the gateway is a plain 1-in/3-out `Diverging` and jBPM no longer objects to it. The four-value probe recorded on 2026-08-01 (all four `gatewayDirection` values rejected on the 2-in/3-out shape) stands and is why the fix had to be structural; the structure changed for a different reason and took the finding with it.                                                 |
| (a′)  | regcf-reporting (1)                                   | `This type of node [Decide_0, ongoing reporting obligation] cannot have more than one incoming connection!` | Class (a) **relocated, not repaired**. jBPM will not give any node but a converging gateway more than one incoming sequence flow, and the renewal loop means something on that path has two. BPMN 2.0 permits multiple incoming flows on an activity (§13.2.1: an uncontrolled merge, one activity instance per token), and with a single token in flight that is exactly the intent, so the emitted file is right and the dialect is narrow. The only jBPM-acceptable form is the structural rewrite §8.1 has recorded as an option since 2026-08-01 — a converging `exclusiveGateway` in front of the `businessRuleTask` — still **an option, not built, not ruled**. |
| (b)   | regcf-advertising (4), regcf-resale (6), handover (4) | `mismatched input 'WITHIN'`, `Unable to Analyse Expression …`, `mismatched input 'period'`                  | jBPM compiling our **deliberately opaque** L4-text expression bodies as Drools rule expressions. The `P-BRANCHGUARD` fidelity stance working as designed — not a defect, and not to be "fixed". **Narrowed 2026-08-02**: these are now the _conditional boundary-event_ conditions only (a named deadline: `` `days in the resale restricted period` ``). The gateway `conditionExpression`s that used to be in this class are FEEL now, because §8.3 wired them.                                                                                                                                                                                                       |
| (c)   | regcf-advertising (4), regcf-resale (6)               | `Could not find variable 'notice_complies_with_Rule_204_b' for action 'notice_complies_with_Rule_204_b'`    | **New on 2026-08-02, and expected.** The wired gateway guard is a FEEL read of the decision's output variable; jBPM would only have that variable bound if it had actually invoked the DMN, and the harness deliberately never loads a sibling DMN (`etc/kie/KieBpmnCheck.java` compiles and plays the process, nothing more). Engine execution being a NON-GOAL, this is the linkage being _visible to_ an engine rather than _run by_ one. Whether declaring a `<bpmn:property>` per wired decision would satisfy jBPM's binder is **UNMEASURED** — a named follow-up, not a design.                                                                                  |

(What measurement changed, kept so nobody re-derives it. **2026-08-01**: an earlier draft of
this section, committed hours before, called class (a) "a defect against this bar" and
prescribed emitting `Unspecified` where `Mixed` is computed. The prescription was implemented,
run, and **falsified the same day** — jBPM rejects `Unspecified` with the same exception — so the
change was reverted before it shipped and a full four-value probe was recorded instead. That
probe evidence lives at `gatewayFlowFor` in `jl4-core/src/L4/Bpmn/Lower.hs` and in
`jl4/examples/bpmn/unsound/README.md`, and it is still the reason `Mixed` is emitted wherever it
is still computed. **2026-08-02**: the §8.3 wiring removed the 2-in gateway on the one file that
had one, so class (a) has no members left — which is a change in the tree, not a retraction of
the probe. Class (a′) is where the same dialect limit now lands.)

The two non-REJECTED verdicts are worth naming too:

- **offering.bpmn `ABORTED`** — "via error end event [Breach] — a modelled terminal state,
  not a liveness defect". jBPM executed it fine and reached the modelled `Breach` terminal:
  the `LEST` arm doing its job. An exhibit, not a failure.
- **consultation.bpmn `COMPLETED`** clean.

### 8.2 What the bar means operationally

`validate-bpmn.mjs` + `check-bpmn-soundness.mjs` + `check-bpmn-dmn-refs.mjs` green on every
emitted golden = the bar is met. The third is §8.3's own gate: every `businessRuleTask`
reference must resolve in the sibling emitted DMN, and a dangling one is a hard error, because
it is the single defect this linkage can have that a reader cannot see (the diagram still draws,
the file still parses, the delegation silently does nothing).

The jBPM baseline (`etc/bpmn-kie-baseline.txt`) records corroboration standing,
measured-not-intended; class (b) reds stay red there **by design** — §8.3 narrowed that class to
the boundary-event conditions but did not empty it, and regenerating the file to green by
weakening the remaining opaque guards would be lowering law text into engine dialect, refused
above.

### 8.3 The DMN wiring — mandated 2026-08-01, BUILT 2026-08-02

**Status: BUILT.** Everything in this section describes the tree unless it says otherwise; the
three sentences that describe something NOT built say so in bold. Prerequisites, both discharged
before the build started: DMN Phase 5 BKM emission (PR legalese#188, `973bdf93`) gave a
`businessRuleTask` something to call, and R13 (`DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §16) gave it
the stable verdict decision — `decision_ongoing_reporting_obligation`, `typeRef="string"`,
enumerated `outputValues` = the three arm verdicts.

#### The flavor question — MEASURED 2026-08-02, and it did not need a flavor split

The 2026-08-01 sketch recorded "how the `businessRuleTask` names its decision" as an open probe
between Camunda 7 `camunda:decisionRef`, Camunda 8 `zeebe:calledDecision`, and the pure BPMN 2.0
`implementation` attribute. Seven probe files were built and run through both checkers
(`npx --package=bpmn-moddle@10 node etc/validate-bpmn.mjs`, and
`etc/check-bpmn-kie.sh` against jbpm-bpmn2 7.74.1.Final on JDK 17.0.20):

| probe                                                                                 | bpmn-moddle | jBPM                                                                          |
| ------------------------------------------------------------------------------------- | ----------- | ----------------------------------------------------------------------------- |
| A bare `businessRuleTask`                                                             | OK          | `errors=1` — `RuleSet (DRL) has no ruleflow-group`                            |
| B `implementation="…/DMN/20191111/MODEL/"` + `<bpmn:import>`                          | OK          | `errors=1` — `Unsupported rule language`                                      |
| C `camunda:decisionRef` (Camunda 7)                                                   | OK          | `errors=1` — `Unsupported rule language 'http://camunda.org/schema/1.0/bpmn'` |
| D `zeebe:calledDecision` (Camunda 8)                                                  | OK          | `errors=1` — falls back to `RuleSet (DRL) has no ruleflow-group`              |
| E `implementation="http://www.jboss.org/drools/dmn"` alone                            | OK          | `errors=2` — `RuleSet (DMN) has no namespace` / `has no model`                |
| **G** = E + `ioSpecification` dataInputs `namespace`/`model`/`decision` + assignments | OK          | **`errors=0 warnings=0`**                                                     |
| H = G + `<bpmn:import>`                                                               | OK          | `errors=0 warnings=0`, identical to G                                         |

Two readings, both load-bearing:

- **`bpmn-moddle` does not discriminate.** It tolerates an unregistered foreign attribute
  (`camunda:decisionRef`) and an unregistered `extensionElements` child (`zeebe:calledDecision`)
  alike, at zero warnings. So the K4 acceptance signal could not have chosen between these, and
  a probe run only against it would have "confirmed" whichever form was tried first.
- **Form G is emitted, and it needs no flavor axis.** It is the only form both checkers accept,
  and — the part that matters for the argument this exhibit is making — it contains **no vendor
  namespace at all**. `implementation` is a standard BPMN 2.0 `businessRuleTask` attribute whose
  value is a URI naming a rule language; `ioSpecification` / `dataInput` / `inputSet` /
  `dataInputAssociation` / `assignment` are all standard BPMN 2.0. One vendor-specific _string_,
  zero vendor-specific _elements_. There is consequently nothing for a `--bpmn-flavor` flag to
  split: the alternatives are strictly worse (rejected by jBPM, not required by bpmn-moddle).
  **NOT BUILT, and deliberately**: if a later probe shows Camunda Modeler's DMN-link _UI_ needs
  `camunda:decisionRef` to light up, that is when a flavor axis earns its place. Recorded as an
  unmeasured open item, not a design.
- **No file path is emitted.** jBPM's contract is `(namespace, model, decision-name)`, all three
  derivable from the same module (`drgNamespace`, `dloModelName`, `dcnFeelName`). Nothing in the
  artifact says where the `.dmn` lives on disk, so a golden carries no trace of the environment
  that produced it. `<bpmn:import>` is optional and probe H measured it to change nothing, so it
  is left out.

#### The two shapes, in priority order, and the refusal below them

`L4.Bpmn.Lower` tries these per guarded exclusive gateway. **The order is load-bearing**, for a
reason the corpus supplies rather than one anybody chose.

1. **Verdict.** When the _rule's own_ `DECIDE` resolved to an emitted decision carrying an
   enumerated string output, each arm becomes a comparison against the verdict that arm
   produces: `ongoing_reporting_obligation = "file a Form C-AR annual report and continue"`.
   Applies to `regcf-reporting`.
2. **Guard.** Else, when every guard atom of every arm applies the _same_ emitted boolean
   decision, each arm becomes that decision's variable, negated or not:
   `notice_complies_with_Rule_204_b` / `not(notice_complies_with_Rule_204_b)`. Applies to
   `regcf-advertising` and `regcf-resale`.
3. **Refuse.** Else emit no `businessRuleTask`, keep the opaque `conditionExpression`, keep
   `P-BRANCHGUARD`, and add `P-NODMN` (Lossy) naming the reason.

**The anonymous-guard-atom question §8.3 left open on 2026-08-01 is ANSWERED by that order.**
Reg CF reporting's second arm is guarded by `` `annual cycles` AT MOST 0 ``, a comparison and not
a call, so it has no decision of its own and the _guard_ shape cannot resolve it. The _verdict_
shape does not need it to: R13's lowering already consumed that atom as a **column** of the
verdict table, and what the gateway reads is the table's answer. Trying the guard shape first
would refuse a rule the verdict shape wires cleanly.

**One decision per gateway, in v1.** The guard shape refuses an `IF` chain whose arms test two
different predicates: a `businessRuleTask` invokes one decision, and two tasks plus an ordering
rule is a design nothing in the corpus asks for. The refusal says so rather than wiring the first
predicate and leaving the second silently unbacked. **NOT BUILT**, by choice, not by oversight.

**And one decision is not yet one question — added 2026-08-02 by the verify pass, with the defect
measured first.** A `Unique` says which `DECIDE` a guard applies, not what it applies it _to_, and
the guard shape maps every atom of every arm onto the same decision variable. So
``IF `conforms` a THEN … ELSE IF `conforms` b THEN …`` — one decide, two questions — lowered arm
2 to `not(conforms) and conforms`: a **contradiction**, silently asserting that a perfectly
reachable obligation can never be reached. Measured on that fixture before the check existed; the
three arms came out `conforms` / `not(conforms) and conforms` / `not(conforms) and not(conforms)`.
The guard shape now refuses unless every atom naming the decision is the _same atom text_, and
names the differing arguments.

Nothing in the corpus moved — all three wired goldens have exactly one distinct guard atom, so the
check is byte-neutral there. What it removes is a dependency on the _other_ backend: the CLI could
not reach the shape anyway, because two call sites lift the decide to a `businessKnowledgeModel`
(measured: a probe of that source exports `bkm_the_notice_conforms` and no decision) and a BKM is
never in the wiring table. That is a fact about the DMN tiering rule, and a silently wrong diagram
is not a thing to leave resting on one. The test therefore builds the wiring by hand rather than
through `wiringFromDrg`, since a coincidence cannot be regression-tested through the pipeline it
is a coincidence of.

#### Why a dangling `decisionRef` is unrepresentable

The naming coordination the 2026-08-01 sketch called for ("the BPMN side must consume the names
the DMN exporter emitted, not re-derive them") is enforced structurally rather than by care:

- `L4.Dmn.IR.Decision` carries `dcnDecide :: Maybe Unique` — the `DECIDE` it was lowered from,
  emitted nowhere, present so a sibling backend can ask what a rule became.
- `L4.Bpmn.Wiring.wiringFromDrg` indexes **`drgDecisions` of the emitted graph** by that key. A
  decide the population filter dropped, or one emitted as a `businessKnowledgeModel` (a function,
  with no variable to read and no lookup triple), is simply absent from the table.
- `L4.Bpmn.Lower` can mint a `DmnCall` from nothing but a table entry.

So the reference exists only where a lookup succeeded, by construction. `L4.Bpmn.IR` and
`L4.Bpmn.Lower` import nothing from `L4.Dmn`; `L4.Bpmn.Wiring` is the whole of §6's soft coupling,
one module and one direction wide.

That is a claim about code. `etc/check-bpmn-dmn-refs.mjs` is the claim about **artifacts**: it
reads both files independently and hard-errors on a `businessRuleTask` whose
`(namespace, model, decision)` triple names anything the supplied DMN does not declare. Its
self-test (`etc/check-bpmn-dmn-refs.selftest.mjs`) breaks the real emitted pair six ways and
asserts it objects, then twice more and asserts it does not — because the resolver's only observed
behaviour in CI is otherwise "OK", which is indistinguishable from a resolver that says OK
unconditionally. Both run in the `bpmn` job of `.github/workflows/pr-checks.yml`.

#### `P-BRANCHGUARD`'s endgame, reached — and what it did NOT discharge

Where a gateway is wired, `P-BRANCHGUARD` is replaced by `P-DMNWIRED` (Advisory), naming the
decision, its element id, the model, and which of the two shapes matched. Where the wiring was
attempted and refused, `P-BRANCHGUARD` stays **and** `P-NODMN` (Lossy) says why. Where no
`DmnWiring` was supplied at all — the hand-built fixtures, and any caller that lowers a state
graph without a DRG — nothing changes, which is why `offering`, `handover` and `consultation`
are byte-identical across this build.

`P-DMNWIRED` does not claim nothing was lost. The residual it states: the arms' exhaustiveness
and mutual exclusion are now properties of the DMN table's hit policy, and BPMN still has no way
to say so at the gateway. Note also that the reporting verdict table is `FIRST`, not `UNIQUE` —
priority-ordered rather than provably non-overlapping — so the 2026-08-01 sketch's "live in the
DMN table's `UNIQUE` hit policy" is true of the _guard_-shape decisions and only half true of the
verdict one.

#### What the wiring did NOT do

- **Timer boundary events for the `WITHIN` deadlines. NOT BUILT.** Reg CF's deadlines are named
  constants (`` `business days to file Form C-TR` ``), and turning one into an ISO 8601
  `<timeDuration>` needs its _value_, which means evaluating the corpus. Today they are
  conditional boundary events carrying the raw text, reported as `P-DEADLINE` at `Blocking`.
  Inventing a duration is precisely what that refusal exists to prevent, so it was left alone.
- **The `HENCE <this rule>` loop-back edge** was already drawn before this change; what moved is
  that it now passes _through_ the `businessRuleTask`, which is the semantics (each cycle re-asks
  the decision) rather than a side effect.
- **Declaring a `<bpmn:property>` per wired decision**, which might satisfy jBPM's variable
  binder (§8.1 class (c)). **UNMEASURED**, and named as a follow-up rather than guessed at.
