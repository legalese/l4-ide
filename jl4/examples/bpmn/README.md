# BPMN export fixtures

Golden inputs for the BPMN 2.0 exporter (`L4.Bpmn.IR` / `L4.Bpmn.Lower` /
`L4.Bpmn.Emit`), exercised by `jl4/tests/BpmnExport.hs`.

The exporter runs over the **regulative** layer only — `PARTY p MUST a WITHIN d
HENCE … LEST …`, extracted to a state graph by `L4.StateGraph`. That layer
genuinely _is_ a transition system, so drawing it as one says nothing the source
did not. Predicates are a different matter, and belong to the ladder; see
`doc/concepts/language-design/logic-not-flowcharts.md`.

| Fixture       | Covers                                                                                                                                                     |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `offering.l4` | Three parties, a four-way `RAND` (concurrent obligations with different bearers), two `SHANT`s, timer boundary events, a breach terminal                    |
| `handover.l4` | A deadline that is a _name_ (no timer, no invented duration), a `RAND` and a `ROR`, and permissions whose deadlines are drawn as lapse timers               |

Neither fixture currently gets a converging parallel gateway, and that is the
point of both `P-NOJOIN` notes rather than a gap in coverage. `offering.l4`'s
`RAND` has a branch that can reach `BREACH`; `handover.l4`'s permissions each
carry a `WITHIN`, so each branch reaches the join by two mutually exclusive
routes — the task completing, or the lapse timer firing — and a parallel join
would wait for both. The one shape a join is sound for is exercised in
`BpmnExport.hs` (`randJoinSrc`): permissions with no deadline, no `LEST`, and no
guard, so each branch delivers exactly one token by exactly one route.

Each produces two goldens under `expected/`:

- `<name>.bpmn` — the XML, exactly as `l4` would write it. Openable in Camunda
  Modeler as-is.
- `<name>.fidelity.txt` — what BPMN could not carry, naming the specific element
  that lost it. The report type is `L4.Interchange.Fidelity`, shared with every
  other interchange backend so the CLI has one shape to render rather than one
  per target. Codes `F1`–`F5` are losses of the notation and cannot be fixed by
  writing more Haskell; codes `P-…` are this exporter's own doing — an
  approximation it made (`P-DEADLINE-UNIT`), a gateway it declined to invent
  (`P-NOJOIN`), or a shape the `StateGraph` types permit that BPMN has no honest
  drawing for at all (`P-MULTI-HENCE`, `P-JUNCTION-OBLIGATION`, `P-CYCLE`).
  (DMN uses `D-…`, so a combined report never confuses the two.)

## Checking the XML is really importable

`bpmn-moddle` is the library `bpmn-js`, and therefore Camunda Modeler, reads
BPMN with. Nothing is added to `package.json`:

```sh
npx --yes --package=bpmn-moddle@10 node etc/validate-bpmn.mjs \
  jl4/examples/bpmn/expected/offering.bpmn \
  jl4/examples/bpmn/expected/handover.bpmn
```

It reports parse errors, moddle warnings, unresolved references, boundary events
without a trigger, and any flow node or sequence flow missing its diagram
interchange. Both fixtures parse with zero warnings.

**It is not evidence that the diagram is right, and must never be cited as
such.** It checks well-formedness, and well-formedness is exactly what a wrong
diagram has: it passed an inverted prohibition, a converging gateway that
deadlocked, four dropped `WITHIN` windows, and twelve edges drawn straight
through unrelated nodes, all at zero warnings, while the Haskell suite was green
at 1581 examples. Run it to catch a regression in the XML; read
`BpmnExport.hs` for whether the XML says what the rule says.

## Regenerating

Delete the golden and re-run the suite twice (the first run writes it and fails
by design, the second confirms it is stable):

```sh
rm jl4/examples/bpmn/expected/offering.bpmn
cabal test jl4:jl4-test --test-options='--match "bpmn export"'
```
