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

## Where to look

- **Worked examples:** `jl4/examples/dmn/` and `jl4/examples/bpmn/`, both with goldens and
  committed fidelity reports so you can see what a real report says.
- **Design and rulings:** `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` under `specs/`.
- **Evidence:** the DMN goldens are executed in CI against **two independent engines**, KIE and
  Camunda, and the BPMN output is checked for soundness — so the exports are validated against
  real implementations rather than against our reading of the standard.
