# DMN 1.3 export

The exhibit and golden for the DMN exporter — Track **D1** of the Lexipedia-superset
programme (`specs/todo/lexipedia-superset/SPEC.md`).

There are **two** subjects, and the difference between them is the deliverable.

| File                              | What it is                                                              |
| --------------------------------- | ----------------------------------------------------------------------- |
| `reg-cf.l4`                       | the **shape** exhibit: five decisions, one of each shape the exporter can produce |
| `expected/reg-cf.dmn`             | the emitted DMN 1.3 XML                                                 |
| `expected/reg-cf.fidelity.txt`    | what the XML target could not carry                                     |
| `expected/reg-cf.dmn.md`          | the same module as dmnmd markdown                                       |
| `expected/reg-cf.md.fidelity.txt` | what the **markdown** target could not carry — a different list         |
| `expected/regcf-corpus.*`         | the same four artifacts cut from the **real** 981-line corpus at `../legal/regcf/regcf.l4` |

Both sets are produced by `jl4/tests/DmnExport.hs` (`goldenSubjects`); regenerate by
deleting a golden and re-running `cabal test jl4:jl4-test` twice.

`reg-cf.l4` is written in module-level-scalar (`ASSUME`) style, which is the program
model DMN itself has, and its **figures are illustrative** — its own header says so, and
it must never be quoted as a statement of Reg CF. `regcf-corpus.*` is the real thing,
and it is here to be honest about what the real thing costs: **73 decisions, 3 tables,
70 boxed literal expressions, 61 `inputData` under 27 names, 75 blocking notes.** The
diagnosis is one sentence — a DMN decision is a 0-ary variable, so the house
`GIVEN`+record style turns every cross-decision reference into an unevaluable `f(x)` —
and it is written up at `../legal/regcf/PROJECTIONS.md` §1, which also records what
the projection *cannot* say. Read that before citing either file.

## The pipeline

```
Module Resolved
  └─ peel WHERE/LET, inline locals
       └─ L4.Viz.GuardedRows.normaliseGuarded   IF / BRANCH / CONSIDER -> first-match rows
            └─ flatten nested chains, lift max/min
                 └─ L4.Dmn.Lower                rows -> DecisionTable / Drg (+ notes)
                      ├─ L4.Dmn.Emit            Drg  -> DMN 1.3 XML
                      └─ L4.Dmn.Markdown        Drg  -> dmnmd markdown
```

Two emitters over one IR. That is the argument, not a convenience: the same
decision produces two artifacts with **two different loss lists**, each named.
The alternative — two hand-maintained exporters that quietly disagree about what
a number looks like — is the duplicated-knowledge bug this whole programme is a
critique of. `renderNumber` is shared for exactly that reason.

Fidelity notes use the shared `L4.Interchange.Fidelity` type, so the process-side
(BPMN) backend and this one produce one report shape between them. DMN's codes
are all prefixed `D-`.

`L4.Viz.GuardedRows` is shared with the ladder visualiser; this is its second consumer.
The two differ in one respect that matters: the ladder gates on boolean bodies, and the
DMN exporter deliberately does not — a `NUMBER`-returning `BRANCH` is exactly what a
decision table is for.

## What the exhibit is meant to show

- **`is accredited investor`** — a `CONSIDER` over distinct nullary constructors. The
  guards cannot both hold, so the table is honestly hit policy `U`; `OTHERWISE` becomes
  the `<defaultOutputEntry>`, because a catch-all rule with all-`-` cells would overlap
  every other rule and be illegal under `U`. Constant outputs and a single-hit policy
  mean this one is _inside_ the fragment DMN can analyse, and the report says nothing
  about it.
- **`combined resources`** — arithmetic, not a guarded chain, so a `<literalExpression>`.
  Dropping such a decision would leave the DRG describing a different rule set than the
  module does.
- **`annual limit basis`** — `IF a AT MOST b THEN a ELSE b`. Both arms are the guard's
  own operands, so this is `min`, not a decision over two cases. Expanding it into rows
  would manufacture cases 17 CFR 227.100(a)(2) does not have — the statute states an
  _operator_ ("the lesser of"), so `min(a, b)` is the isomorphic rendering.
- **`financial statements required`** — a `WHERE`-wrapped chain of `ELSE IF`s. Each tier
  introduces a threshold the one above did not, so this one _is_ a decision and _does_
  flatten: four sibling rules under `F`. The `WHERE`-local `aggregate` has to be peeled
  and inlined before the chain is visible to the normaliser at all.
- **`investor limit`** — overlapping thresholds under hit policy `F`, with a lifted
  \$2,500 floor and a computed output. Note what is _absent_: no rule restates that an
  earlier one did not fire. `First` already means that, and materialising the negated
  prefixes (which the ladder expansion has no choice but to do) would turn a readable
  table into a triangular mess.

### The discriminator between the last two

> Flatten a nested chain only when the inner guard introduces a condition the outer one
> did not. When the inner conditional's arms are its own comparison operands, it computes
> a value — lift it into the output expression instead.

`financial statements required` flattens; `annual limit basis` and the floor inside
`investor limit` do not.

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

## The dmnmd round trip

`dmnmd --to=l4` already exists, so `L4 → dmnmd → L4′` is a property that can be run
rather than claimed. Verified locally on this exhibit:

```
dmnmd -f md -t l4 expected/reg-cf.dmn.md > /tmp/rt.l4   # imported 2 tables
cabal run l4 -- check /tmp/rt.l4                        # Check succeeded.
```

Two of the five decisions survive that trip; the other three have no markdown form and
are named in `reg-cf.md.fidelity.txt` rather than silently dropped. The XML leg of the
same differential is blocked on four dmnmd bugs — see the header of `etc/validate-dmn.mjs`.

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
XSD sequence order; neither claim is made here. **dmnmd cannot cross-check the XML** —
its reader is blocked (see above) — so the XML rests on `dmn-moddle` alone, and the
markdown rests on dmnmd alone. They are not two independent checks of the same thing.

Set `DMNMD=<path to the cabal-built dmnmd>` to make the script exercise the markdown leg
too; without it that leg is skipped.

## From the CLI

Track **S0** is wired: both goldens in this directory are reproducible byte-for-byte
through `l4 export`, from a repo checkout with `jl4/` as the working directory.

```sh
l4 export --to=dmn    reg-cf.l4 | diff - expected/reg-cf.dmn
l4 export --to=dmn-md reg-cf.l4 | diff - expected/reg-cf.dmn.md

# the corpus, likewise with no flags
l4 export --to=dmn    ../legal/regcf/regcf.l4 | diff - expected/regcf-corpus.dmn
l4 export --to=dmn-md ../legal/regcf/regcf.l4 | diff - expected/regcf-corpus.dmn.md
```

No `--model-name` is needed, and that is the point. `lowerModule` takes the
`<definitions>` name as a parameter rather than reading it off the module's URI, so
the emitted bytes do not depend on where the file lives; the CLI supplies it from the
module's own outermost `§` heading, falling back to the file's base name. Both files
here carry such a heading, so each names its own model exactly once, in the file that
*is* the model.

The flag still exists and still overrides. It used to be *required* for the corpus
golden, whose title was consequently hand-typed in `jl4/tests/DmnExport.hs` — so one
model had three names at once (`SEC Regulation Crowdfunding — 17 CFR Part 227` in the
corpus, `Regulation Crowdfunding (17 CFR Part 227)` in the test, `regcf` from a bare
CLI run). A title duplicated across three files and stale in two of them is exactly
the defect this exhibit exists to criticise.

Add `--fidelity-report` for the loss list — written to `<output>.fidelity.txt` when
`-o` is given, and to stderr otherwise, so that a redirected document stays a document.
A one-line tally goes to stderr either way, whether or not the flag was passed.

`l4 export --to=dmn` refuses a module with no decisions in it, rather than emitting a
`<definitions>` that opens as an empty canvas. It does **not** fail merely because the
report holds `blocking` notes — `blocking` describes what DMN cannot express (see
below), and this exhibit has one. Pass `--fail-on=blocking|lossy|advisory` if a
pipeline wants a gate.

The **service** surface (track **S2**) is still to come.
