# DMN 1.3 export

The exhibit and golden for the DMN exporter — Track **D1** of the Lexipedia-superset
programme (`specs/todo/lexipedia-superset/SPEC.md`).

| File                            | What it is                                                                |
| ------------------------------- | ------------------------------------------------------------------------- |
| `reg-cf.l4`                     | the source: four decisions, one of each shape the exporter can produce    |
| `expected/reg-cf.dmn`           | the emitted DMN 1.3 XML, as a golden                                      |
| `expected/reg-cf.fidelity.txt`  | the fidelity report for the same module, as a golden                      |

Both goldens are produced by `jl4/tests/DmnExport.hs`; regenerate them by deleting the
file and re-running `cabal test jl4:jl4-test`.

## The pipeline

```
Module Resolved
  └─ L4.Viz.GuardedRows.normaliseGuarded   IF / BRANCH / CONSIDER  ->  first-match rows
       └─ L4.Dmn.Lower                     rows  ->  DecisionTable / Drg  (+ fidelity notes)
            └─ L4.Dmn.Emit                 Drg   ->  DMN 1.3 XML
```

`L4.Viz.GuardedRows` is shared with the ladder visualiser; this is its second consumer.
The two differ in one respect that matters: the ladder gates on boolean bodies, and the
DMN exporter deliberately does not — a `NUMBER`-returning `BRANCH` is exactly what a
decision table is for.

## What the exhibit is meant to show

- **`is accredited investor`** — a `CONSIDER` over distinct nullary constructors. The
  guards cannot both hold, so the table is honestly hit policy `U`; `OTHERWISE` becomes
  the `<defaultOutputEntry>`, because a catch-all rule with all-`-` cells would overlap
  every other rule and be illegal under `U`.
- **`combined resources`** — arithmetic, not a guarded chain, so a `<literalExpression>`.
  Dropping such a decision would leave the DRG describing a different rule set than the
  module does.
- **`annual limit basis`** — a guard comparing two _variables_. There is no constant
  endpoint to put in a cell, so the conjunct becomes its own boolean column and the
  report says so. Guessing an endpoint is the one thing the exporter will not do.
- **`investor limit`** — overlapping thresholds under hit policy `F`, with a computed
  output entry. Note what is _absent_: no rule restates that an earlier one did not
  fire. `First` already means that, and materialising the negated prefixes (which the
  ladder expansion has no choice but to do) would turn a readable table into a
  triangular mess.

## The fidelity report

The report is the point, not a footnote. DMN's decision-table analysis — completeness
and consistency checking since Montalbano (1962), inter-tabular checking since 1998,
cross-DRD SMT verification since 2022 — is all defined over **S-FEEL**, with constant
outputs. The DMN specification itself (§9.1) says "few if any complete decision models
can be defined using S-FEEL" and tells you to use full FEEL instead.

So the fragment you can verify is not the fragment you are told to write
(`specs/research/DMN-STEELMAN.md` §2.5). Each note in `reg-cf.fidelity.txt` is one
located instance of that gap in a real file: where the model left the analysable
fragment, and which capability that cost.

## Validating the output

`etc/validate-dmn.mjs` parses the emitted XML with **dmn-moddle** — the moddle
descriptor Camunda's own DMN tooling is built on — and cross-checks two things a parse
will not: that every rule is as wide as its table, and that every information
requirement `href` resolves.

```
npx --yes --package=dmn-moddle node etc/validate-dmn.mjs
```

It installs nothing into the repo (`package.json` and the lockfile are left alone).
A clean run means every element and attribute is one DMN 1.3 defines, in a place it is
allowed to be. It does **not** mean Camunda will import the file, and it does not check
XSD sequence order; neither claim is made here.

## Not yet wired

There is no `l4 export --to=dmn` yet: the CLI and service surfaces are track **S0**/**S2**,
which the programme spec sequences after both exporters land. For now `L4.Dmn.Emit.emitDrg`
is a library entry point, exercised by the test suite.
