# BPMN export fixtures

Golden inputs for the BPMN 2.0 exporter (`L4.Bpmn.IR` / `L4.Bpmn.Lower` /
`L4.Bpmn.Emit`), exercised by `jl4/tests/BpmnExport.hs`.

The exporter runs over the **regulative** layer only — `PARTY p MUST a WITHIN d
HENCE … LEST …`, extracted to a state graph by `L4.StateGraph`. That layer
genuinely _is_ a transition system, so drawing it as one says nothing the source
did not. Predicates are a different matter, and belong to the ladder; see
`doc/concepts/language-design/logic-not-flowcharts.md`.

| Fixture         | Covers                                                                                                                                        |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `offering.l4`   | Three parties, a four-way `RAND` (concurrent obligations with different bearers), two `SHANT`s, timer boundary events, a breach terminal      |
| `handover.l4`   | A deadline that is a _name_ (no timer, no invented duration), a `RAND` whose branches provably reconverge (so a real join), and a `ROR`       |

Each produces two goldens under `expected/`:

- `<name>.bpmn` — the XML, exactly as `l4` would write it. Openable in Camunda
  Modeler as-is.
- `<name>.fidelity.txt` — what BPMN could not carry, naming the specific element
  that lost it. `F1`–`F5` are losses of the notation and cannot be fixed by
  writing more Haskell; `X1`–`X4` are approximations this exporter made and
  could be.

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

## Regenerating

Delete the golden and re-run the suite twice (the first run writes it and fails
by design, the second confirms it is stable):

```sh
rm jl4/examples/bpmn/expected/offering.bpmn
cabal test jl4:jl4-test --test-options='--match "bpmn export"'
```
