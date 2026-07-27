# DMN 1.3 export

The exhibit and golden for the DMN exporter — Track **D1** of the Lexipedia-superset
programme (`specs/todo/lexipedia-superset/SPEC.md`).

| File                              | What it is                                                             |
| --------------------------------- | ---------------------------------------------------------------------- |
| `reg-cf.l4`                       | the source: five decisions, one of each shape the exporter can produce |
| `expected/reg-cf.dmn`             | the emitted DMN 1.3 XML                                                |
| `expected/reg-cf.fidelity.txt`    | what the XML target could not carry                                    |
| `expected/reg-cf.dmn.md`          | the same module as dmnmd markdown                                      |
| `expected/reg-cf.md.fidelity.txt` | what the **markdown** target could not carry — a different list        |
| `reg-cf.cases.json`               | five input contexts + the value every decision must answer under each  |

Both goldens are produced by `jl4/tests/DmnExport.hs`; regenerate them by deleting the
file and re-running `cabal test jl4:jl4-test`.

`reg-cf.cases.json` is hand-written, not generated, and its keys are **FEEL** names
(`annual_income`, not `annual income`). That is not a quirk of the harness — it is the
thing being checked; see "Running it through the real engines" below.

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

## Running it through the real engines

Two committed harnesses take `expected/reg-cf.dmn` to the two engines that matter and
report what the **engine** says, which is a different question from what a schema or a
metamodel parser says:

```sh
etc/kie-dmn-check/run.sh     jl4/examples/dmn/expected/reg-cf.dmn --cases jl4/examples/dmn/reg-cf.cases.json
etc/camunda-dmn-check/run.sh jl4/examples/dmn/expected/reg-cf.dmn --cases jl4/examples/dmn/reg-cf.cases.json
```

| Harness                  | Engine                                     | Legs                                                                                | JDK |
| ------------------------ | ------------------------------------------ | ----------------------------------------------------------------------------------- | --- |
| `etc/kie-dmn-check/`     | Drools/KIE `8.44.0.Final`                  | Xerces XSD, KIE validator, `KieBuilder`, `evaluateAll` + services, **expected values** | 17  |
| `etc/camunda-dmn-check/` | Camunda 8 `8.7.6` (`io.camunda:zeebe-dmn`) | `parse()` + `isValid()`, `evaluateDecisionById`, **expected values**                  | 21+ |

Each harness reports the engine version it **observed off its own classpath** (not one its
launcher passed in) and fails if that disagrees with the pin in its `pom.xml`, so the
version in a `VERDICT` banner is evidence about which engine looked at the file.

Zero-install, exactly like `etc/validate-dmn.mjs`: Maven resolves each classpath into
`$TMPDIR`, nothing is written into the repo, and `package.json` and the lockfile are
untouched. Both **skip loudly** — `SKIP <checker>: <reason>` on stderr and exit 0 — when
the toolchain is absent, and neither prints its `VERDICT` banner when it skips. Set
`KIE_CHECK_REQUIRED=1` / `CAMUNDA_CHECK_REQUIRED=1` to turn every skip path into a
failure; the `dmn-engines` CI job does, so **in CI an unavailable checker is a failure**.

A missing toolchain skips; a **broken harness does not**. If `javac` fails, both scripts
exit 1 whether or not `*_CHECK_REQUIRED` is set, because absent tooling is a fact about
the machine while a harness that will not compile is a fact about the repo. That
distinction is not theoretical: it was added after a `KieDmnCheck.java` with an
unbalanced brace in it reported `SKIP … javac failed` and exited 0.

> **The `dmn-engines` job is not yet a required status check** on the `unstable` ruleset
> (`gh api repos/legalese/l4-ide/rulesets/18543507` lists only TypeScript, Haskell, WASM
> and Nix). Until its context is added there, a failure of this job — including the
> deliberate `exit 1` the skip contract is built on — does not block a merge.

The same two harnesses are wired into `l4-cli-test` behind `L4_DMN_ENGINE_CHECK=1`:

```sh
cd jl4 && L4_DMN_ENGINE_CHECK=1 cabal test l4-cli-test
```

Absent the variable those two examples are reported `PENDING … UNEXERCISED`, never as
passes, so a green run always says which engine actually looked at the artifact.

**Why this exists.** Until 2026-07-27 this exhibit was checked by `dmn-moddle` and by an
ad-hoc KIE run that was never committed — and the committed golden was, at that point,
rejected by **both** engines: KIE fired `VARIABLE_NAME_MISMATCH` and then failed to
build, and Camunda 8 rejected the whole DRG at `parse()`. The cause was that FEEL names
kept their spaces and only half of each name was mangled. The engines bind the FEEL name
off different attributes — KIE off the node's `@name`, Camunda off the `<variable>`'s —
so doing half of each fails both, for opposite reasons. `@name` now carries a FEEL-safe
identifier and `@label` the verbatim L4 name. See
`specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §5.2 and §13.

The Camunda failure was the bad kind, and the exact shape of it decides what the harnesses
have to check. `annual income` does not fail to resolve: it is tokenised as `annual` `in`
`come`, the membership operator. Measured — in a model declaring `annual income` = 100000,
`annual` = 5 and `come` = [1,2,5], Camunda 8.7.6 answers `true` to `annual income`,
identically to `annual in come`, where KIE 8.44 answers `100000`.

`true` is not `null`, so a harness that failed only on `FAILED`, `SKIPPED` and `null`
would wave that file through. That is why both harnesses take `--cases` and compare
against **expected values**: `25/25 decision(s) SUCCEEDED` is a liveness claim, and only
`25/25 value(s) as expected` says the answers were right. The null check is kept as well,
but it is necessary rather than sufficient.

Between them the five cases fire all nine `<rule>` elements and both
`<defaultOutputEntry>` paths; one context alone leaves six of the nine unevaluated. What
they cannot catch is stated in the fixture itself: `annual income` and `net worth` are
consumed only by `+` and `min`, both commutative, so exchanging those two bindings is
invisible on this exhibit — faithful to a statute that is symmetric in the two rather
than a gap a further case could close.

## From the CLI

Track **S0** is wired: both goldens in this directory are reproducible byte-for-byte
through `l4 export`, from a repo checkout with `jl4/` as the working directory.

```sh
l4 export --to=dmn    reg-cf.l4 --model-name "Regulation Crowdfunding" | diff - expected/reg-cf.dmn
l4 export --to=dmn-md reg-cf.l4 --model-name "Regulation Crowdfunding" | diff - expected/reg-cf.dmn.md
```

`--model-name` matters: `lowerModule` takes the `<definitions>` name as a parameter
rather than reading it off the module's URI, precisely so the emitted bytes do not
depend on where the file lives. Without it the name defaults to the file's base name
(`reg-cf`), and the `id`/`namespace` attributes change with it.

Add `--fidelity-report` for the loss list — written to `<output>.fidelity.txt` when
`-o` is given, and to stderr otherwise, so that a redirected document stays a document.
A one-line tally goes to stderr either way, whether or not the flag was passed.

`l4 export --to=dmn` refuses a module with no decisions in it, rather than emitting a
`<definitions>` that opens as an empty canvas. It does **not** fail merely because the
report holds `blocking` notes — `blocking` describes what DMN cannot express (see
below), and this exhibit has one. Pass `--fail-on=blocking|lossy|advisory` if a
pipeline wants a gate.

`--flavor camunda|kie` picks which engine the document is shaped for; `camunda` (meaning
Camunda 8) is the default, and `drools` is accepted as a synonym for `kie`. The two
differ on exactly one thing: whether a `<decisionService>` may be the target of a
`<knowledgeRequirement>`. Camunda 8 rejects the whole file at `parse()` if it is, and KIE
runs that shape correctly — so it is `kie`-only. **Neither construct is emitted yet**
(that is Phase 5), so today the two flavors produce identical bytes and the flag is
visible only in the fidelity report's target line. Both `jl4/tests/DmnExport.hs` and
`jl4/tests-cli/Main.hs` pin that identity as a test which is _expected to fail_ when
Phase 5 lands; the fix then is to split the goldens, not to delete the test. The ruling
is `specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §13.

The **service** surface (track **S2**) is still to come.
