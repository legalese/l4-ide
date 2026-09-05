# DMN and BPMN

## What DMN and BPMN are

**DMN** — Decision Model and Notation — and **BPMN** — Business Process Model and Notation — are
OMG standards, the same standards body behind UML. They are the lingua franca of enterprise
business-rules work, and between them they cover the two halves of "what does the organisation
do?"

**DMN describes decisions.** Its central artifact is the decision table: a grid, readable and
editable in a spreadsheet-like UI, where each row is a rule and each column an input or output.
Business analysts author and review these directly, without a developer in the loop. Decision
tables compose into a decision requirements diagram showing which decisions feed which, and the
expressions inside cells are written in FEEL, DMN's own expression language. Engines that execute
DMN include Camunda and KIE/Drools.

**BPMN describes processes.** Its artifact is the process diagram: tasks, gateways, events,
timers, and pools for the different parties. It answers "who does what, in what order, and what
happens if they miss the deadline?"

The two are designed to work together — a BPMN process reaches a decision point and delegates to a
DMN decision through a business rule task.

## Why compile L4 to it

This is the export for handing your rules to an organisation rather than an individual.

- **Business stakeholders can read it without learning anything.** A decision table is the format
  in which enterprise rules are already discussed. Putting your L4 into it means the review
  conversation happens in the reviewer's notation.
- **It runs on engines companies already own.** DMN is executed by commercial and open-source
  engines that are already deployed, monitored, and integrated. The export lands in that world
  rather than asking for a new runtime.
- **The regulative layer becomes a picture that is actually true.** BPMN is generated from L4's
  deontic rules — `PARTY p MUST a WITHIN d HENCE … LEST …` — by extracting the state graph. That
  layer genuinely _is_ a transition system, so drawing it as one asserts nothing the source did
  not. (Predicates are a different matter and deliberately stay out of the diagram; see
  [logic, not flowcharts](../concepts/language-design/logic-not-flowcharts.md).)
- **Deadlines and breach become first-class.** A `WITHIN` becomes a timer boundary event and a
  `LEST` becomes the path taken when it fires — which is exactly how a process modeller would have
  drawn it by hand.

## The command

```
l4 export --to dmn FILE
l4 export --to bpmn FILE
```

| Flag                     | Effect                                                                                 |
| ------------------------ | -------------------------------------------------------------------------------------- |
| `--to NOTATION`          | `dmn` (DMN 1.3 XML) · `dmn-md` (dmnmd markdown) · `bpmn` (BPMN 2.0 XML)                |
| `--output FILE`          | write the document to `FILE` instead of stdout                                         |
| `--fidelity-report`      | also emit the full fidelity report; a one-line tally prints either way                 |
| `--fail-on SEVERITY`     | exit non-zero at `blocking`, `lossy` or `advisory`; default `none`                     |
| `--model-name NAME`      | DMN only: the `<definitions>` name and namespace seed                                  |
| `--flavor ENGINE`        | DMN only: `camunda` (default) or `kie`                                                 |
| `--include-tests`        | DMN only: also emit decisions that are test scaffolding — off by default               |
| `--rule NAME`            | BPMN only: which regulative rule to export, required when the file holds more than one |
| `--deadline-unit POLICY` | BPMN only: how to read a unitless `WITHIN` — `days` (default) or `refuse`              |

`--flavor` exists because the two major engines disagree on exactly one point: whether a
`<decisionService>` may be the target of a `<knowledgeRequirement>`. Camunda 8 rejects the entire
file at parse time if it is, so that shape is emitted only for `kie`. Choose the flavour matching
the engine you will actually run on.

`dmn-md` is worth knowing about: it emits decision tables as markdown rather than XML, which is far
easier to read in a diff or a pull request than DMN's XML.

## What they consume

They take **different layers of L4**, which is why they are one command with two very different
outputs:

- **DMN** takes the decision layer — `@export`ed decisions, lowered to decision tables and the
  requirement graph between them.
- **BPMN** takes the **regulative** layer — the deontic rules, via their state graph. A file with
  no regulative rules has no BPMN to emit.

By default DMN's population filter omits decisions that are only test scaffolding, referenced from
directive arguments with no real callers. Emitting a fixture as a `<decision>` would misdescribe
the rule set, so you must ask for it with `--include-tests`.

## What doesn't survive

Both emit a **fidelity report**, and reading it is not optional. `Blocking` notes here usually
describe the target notation's limits rather than a defect in your file — DMN and BPMN are
substantially less expressive than L4 — which is why `--fail-on` defaults to `none`. A clean exit
means the export ran, not that everything made it across.

The recurring case for BPMN is the unitless deadline: L4 permits a `WITHIN` with no unit, and BPMN
timers require one. `--deadline-unit days` assumes days and records a note saying it did; `refuse`
emits no timer and records that instead. Neither silently invents a unit.

## When a decision can refuse

[`REFUSE`](../reference/control-flow/REFUSE.md) is how an L4 rule says **"the model does not cover
this"** — a determinate outcome that is neither a value nor an error. A rule that reaches one stops,
with the author's sentence, and no other rule can catch it. It is what you write for the day before
a statute commenced, or for a case its drafters never addressed.

**DMN has no such outcome.** Its whole vocabulary for "no answer" is FEEL's single `null`, and that
same `null` also spells "there is none" and "the engine could not compute it". So the export has to
choose, and this is what it chose.

**A refusal becomes `null`, and the reason travels with it.** A refusing row keeps its place in the
table and answers `null`; the author's sentence goes on that row's `<description>`, reading
`OTHERWISE — REFUSE: no fee is prescribed before commencement on 1983-01-01`. A decision whose
_whole body_ refuses becomes a boxed `null`, and the sentence goes on the `<decision>`'s own
`<description>`. Nothing is deleted from the artifact: deleting the refusing row answers `null` too
— that was measured on both engines — and it would take the reason with it.

**The fidelity report names it, at a severity that depends on who reads the answer.** Every decision
that can refuse — because it contains a `REFUSE`, or because it calls something that does — gets a
`D-REFUSE` note carrying the reason:

| severity     | when                                                                                |
| ------------ | ----------------------------------------------------------------------------------- |
| **Lossy**    | every caller consumes it from an `IF`/`CONSIDER` arm, so a guard can fence the null |
| **Blocking** | some caller consumes it unconditionally, or nothing calls it at all                 |

The second row is the one to act on: nothing downstream can tell that `null` apart from an answer.
`--fail-on blocking` turns it into a non-zero exit.

**A refusing decision is evaluated even when nothing reaches it.** A DMN `<decision>` is a node in a
graph, not a branch of an expression, so an engine evaluates it whenever it evaluates the model. A
named refusal therefore comes back `null` in _every_ result, including the runs where no rule
reached it. That is not a defect in the export; it is what a decision requirements graph is.

**One shape needed a repair, and it is why this is measured rather than reasoned about.** When the
refusing decision returns an enum, its table declares the domain in `<outputValues>` — and `null` is
not in that list. The two engines disagreed about what that means: KIE 8.44.0.Final enforces the
list at run time and **fails the decision**, while Camunda 8.7.6 returns the `null` silently. One
file, two answers. So the export adds `null` to _that table's_ `<outputValues>`, which makes both
engines agree, and records a `D-OUTPUTVALUES-NULL` note saying it did. The enum type's own declared
domain is left exactly as L4 wrote it: only the table that can decline says that it can.

**Limits, stated plainly.**

- A DMN engine cannot tell you _which_ refusal it hit, only that the answer is `null`. The reason is
  in the artifact for a person to read, not in the result for a program to branch on.
- Refusal is order-dependent under lazy `AND`/`OR` in L4 (`FALSE AND x` answers, `x AND FALSE`
  refuses) and FEEL's logic is not, so a refusal buried inside a boolean can move.
- The **markdown carrier** (`--to dmn-md`) cannot carry a refusal at all. dmnmd's cell grammar is a
  number, an integer range, or a bare token, with no `null`, so a refusing table is **omitted** and
  the markdown fidelity report says so once per table. A bare `null` cell would be read back as the
  _string_ `"null"`, which is the one outcome worse than omitting the table.
- `l4 verify` does not model refusals; see [REFUSE](../reference/control-flow/REFUSE.md).

The worked example is `jl4/examples/dmn/refuse.l4` — one of each position a refusal can occupy — and
`jl4/examples/dmn/refuse.cases.json` runs it through both engines in CI.

## Where to look

- **Worked examples:** `jl4/examples/dmn/` and `jl4/examples/bpmn/`, both with goldens and
  committed fidelity reports so you can see what a real report says.
- **Design and rulings:** `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` under `specs/`.
- **Evidence:** the DMN goldens are executed in CI against **two independent engines**, KIE and
  Camunda, and the BPMN output is checked for soundness — so the exports are validated against
  real implementations rather than against our reading of the standard.
