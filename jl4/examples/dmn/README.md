# DMN 1.3 export

The exhibit and golden for the DMN exporter — Track **D1** of the Lexipedia-superset
programme (`specs/todo/lexipedia-superset/SPEC.md`).

There are **four** subjects here — `reg-cf.l4` (shape), `gst-rate.l4` (dated regime),
`../legal/regcf/regcf.l4` (the real corpus) and `sumtype.l4` (data model) — and the
difference between them is the deliverable.

| File                              | What it is                                                                                   |
| --------------------------------- | -------------------------------------------------------------------------------------------- |
| `reg-cf.l4`                       | the **shape** exhibit: five decisions, one of each shape the exporter can produce             |
| `expected/reg-cf.dmn`             | the emitted DMN 1.3 XML                                                                       |
| `expected/reg-cf.fidelity.txt`    | what the XML target could not carry                                                           |
| `expected/reg-cf.dmn.md`          | the same module as dmnmd markdown                                                             |
| `expected/reg-cf.md.fidelity.txt` | what the **markdown** target could not carry — a different list                               |
| `reg-cf.cases.json`               | five input contexts + the value every decision must answer under each                         |
| `gst-rate.l4`                     | the **dated-regime** exhibit: law time as a date axis (spec §15) — see below                  |
| `gst-rate.cases.json`             | ten **rule dates** + every decision's answer under each; the dates are fed as `{"$date": …}`  |
| `expected/gst-rate.*`             | its four artifacts — two `UNIQUE` date-interval tables, one `D-RULEDATE`, zero blocking on them |
| `not-ok/dated-chain-*.l4`         | six negative fixtures: mis-ordered arms, duplicate dates, a rolling `Date 32 1 2024`, a mixed chain (all `D-DATEDCHAIN`), a law-time-guarded obligation, and a nested `OTHERWISE` (the last two must stay off the dated path entirely) |
| `expected/regcf-corpus.*`         | the same four artifacts cut from the **real** 1,241-line corpus at `../legal/regcf/regcf.l4`  |

All four sets are produced by `jl4/tests/DmnExport.hs` (`goldenSubjects`); regenerate by
deleting a golden and re-running `cabal test jl4:jl4-test` twice.

`reg-cf.l4` is written in module-level-scalar (`ASSUME`) style, which is the program
model DMN itself has, and its **figures are illustrative** — its own header says so, and
it must never be quoted as a statement of Reg CF. `regcf-corpus.*` is the real thing,
and it is here to be honest about what the real thing costs. Measured 2026-08-02 on the
shipped goldens (R12 + R13, spec §15.12/§16, on top of Phase 5's BKM emission; recounted
2026-08-05 after Rule 501(a)'s "one year" became a calendar anniversary):
**69 decisions (12 decision tables), 10 businessKnowledgeModels, 7 decisionServices,
15 `inputData`, and ZERO blocking notes (0 blocking / 21 lossy / 130 advisory)** — and
both engines evaluate it end to end over the 21 cases in `regcf-corpus.cases.json`
(the base world, 15 dated relocation cases per spec §15.12.1, 4 seed cases added
2026-08-03, and the leap case added 2026-08-05), 1449/1449 values as expected (see "Running it through the real engines" below for the verbatim verdicts). The two blocking families the
2026-08-01 measurement counted (32 notes: the 15 `EVAL UNDER RULES EFFECTIVE AT`
bodies with their 15 `D-RULEDATE-UNBOUND` companions, and the deontic reporting spine
with its D-CYCLE) are **gone**: R12 drops the rebinding decides at population time
(Lossy-noted, no longer emitted) and R13 lowers the deontic spine to a verdict decision
table. The old one-sentence diagnosis — a DMN decision is a 0-ary variable, so the house
`GIVEN`+record style turns every cross-decision reference into an unevaluable `f(x)` —
is RETIRED for tier 2: those call sites now render as FEEL invocations of emitted
BKMs (`../legal/regcf/PROJECTIONS.md` §1 records the history). Read that file
before citing either of these.

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

### The dated-regime exhibit (`gst-rate.l4`)

`gst-rate.l4` is the smallest module that exercises **law time** end to end, and it is the
one exhibit whose engine cases feed **dates**. Two chains, deliberately in the two idioms
the recogniser admits:

- **`GST rate percent`** — the PREDICATE idiom, as the Reg CF corpus writes it: a
  one-parameter `DATE`-typed helper applied to named regime constants.
- **`tourist refund minimum spend`** — the INLINE idiom: the same comparison with no
  helper predicate, written once against a **named** regime constant and once against a
  bare `Date d m y`. Those are the two things an inline right-hand side may be, and they
  reach different code, so the exhibit writes one of each.

Both lower to a **single-column `hitPolicy="UNIQUE"` table** over `RULES_EFFECTIVE_DATE`
whose cells are half-open FEEL date intervals — `>= date("2024-01-01")`,
`[date("2023-01-01")..date("2024-01-01"))`, and a floor row `< date("1994-04-01")` for the
pre-commencement refusal. That is inside S-FEEL, so the table is gap/overlap-analysable by
construction rather than by inspection.

`GST payable on` is there to show a **date driving a number driving a number** across
`informationRequirement` edges. `GST rate percent` has four rules and therefore **three
seams**, and `gst-rate.cases.json` straddles every one of them with a day-of/day-before
pair — that is what pins the closed-low/open-high convention. Straddling only the newest
seam (which the first version did) leaves an off-by-one on the middle interval, or on the
floor row, invisible.

Both engines answer all ten: `70/70 value(s) as expected` on KIE 8.44.0.Final and on
Camunda 8.7.6. See `specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §15.

### The Phase 4 exhibit (`unlift.l4`)

`unlift.l4` holds one of each Phase 4 behaviour, deliberately, in one module — see the
comment at the top of the file for the per-decision map. The behaviours, and the codes
that report them:

- **Un-lifting (tier 1).** A top-level `DECIDE` with `GIVEN` parameters that is applied
  to the **same** argument expression at every (non-directive) call site is not a
  function; it is a decision over shared inputs. Its parameters become module-level
  `<inputData>` **merged by L4 name** with every other un-lifted decision's same-named,
  same-typed parameters, and calls to it render as its **bare FEEL name** over a
  `requiredDecision` edge — where they used to be verbatim L4 no engine could compile.
  `D-PARAM-AS-INPUT` (Advisory, one per merged group) names the cost: the model reads
  one shared subject, and the call sites' argument expressions are discarded.
- **The type-conflict refusal.** Same parameter name at **different declared types**:
  the merge is refused, the parameters stay distinct elements, and `D-PARAMTYPE`
  (Blocking) names every claimant and every type. Merging anyway was measured on both
  engines as `null` with status `SUCCEEDED` and zero messages — the silent-wrong-answer
  shape this exporter exists to refuse.
- **Tier 2 (`D-BKM`, Advisory).** Applied to two *distinct* argument expressions — a
  real function. Classified now, emitted as a `businessKnowledgeModel` in Phase 5; its
  call sites stay verbatim (Blocking) until then.
- **`DMN-SAFE` (`D-PARTIAL`, Blocking or Lossy).** A decision that cannot be certified
  total, pure and deterministic does not un-lift: DMN has no `undefined`, an undefined
  FEEL result is `null`, and `null` reads as `false` at the first boolean consumer.
  Severity keys off the call sites (any strict consumer, or none ⇒ Blocking; all lazy ⇒
  Lossy), the note names the failing clause and range, and says *not certified total* —
  the analysis refuses to certify; it does not prove partiality.
- **The population filter.** Test fixtures (referenced only from `#EVAL`/`#ASSERT`
  argument positions, no callers here or in any importing sibling) and their
  fixture-side helper closure are **not emitted** — `D-FIXTURE` (Advisory) names each,
  and `--include-tests` restores them. Uncalled **regulative** bodies route to the BPMN
  exporter instead of becoming fake decisions — `D-REGULATIVE` (Lossy). Inert prose
  carriers (a body forcing no reference and no input) are **kept** and flagged
  `D-INERT` (Advisory).

The measured effect on the corpus golden: `regcf-corpus.dmn` went from 66 `<inputData>`
to 37, and from KIE refusing the whole model (`Compiled model is null!`) to a
node-by-node build whose 37 residual errors are all verbatim tier-2/refused call sites —
Phase 5's work.

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

> **The corpus has now been through both engines, and here is what they said**
> (2026-08-01, on the shipped `expected/regcf-corpus.dmn`, verbatim):
>
> - KIE 8.44.0.Final: `XSD valid`; `VALID 17 error(s), 0 warning(s)`;
>   `BUILD 17 error(s)` — and the harness then deliberately refuses to evaluate
>   (any build error aborts the run; that is its ruled contract). All 17 errors
>   are the DELIBERATE refusals the fidelity report names at Blocking — 15
>   `EVAL UNDER RULES EFFECTIVE AT` bodies (the temporal family), the deontic
>   reporting spine, and its cyclic-dependency echo. Every tier-2 call site,
>   which accounted for the bulk of Phase 4's 37 residual errors, now compiles.
> - Camunda 8.7.6: `PARSE INVALID: Invalid DMN model: Cyclic dependencies
>   between decisions detected.` — the un-suppressed `ongoing reporting
>   obligation` self-edge, honestly emitted, refused loudly; behind it zeebe
>   also rejects raw-L4 literal expressions at parse.
>
> **Both verdicts above were superseded on 2026-08-02**, when the self-edge went
> back to being erased at emission because DMN §7.3.1 forbids an element from
> requiring itself and the file therefore would not load — ruled and measured at
> `specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §6.4.4-4a; the `D-CYCLE` note is
> unchanged and still fires. Re-measured, both engines:
>
> - KIE 8.44.0.Final: `XSD valid`; `VALID 16 error(s), 0 warning(s)`;
>   `BUILD 16 error(s)`; verdict `32 error(s)`, was 34. The whole delta is the
>   cyclic-dependency echo, once per leg; the reporting spine still carries its
>   own raw-L4 FEEL error, so nothing that was refused has become executable.
> - Camunda 8.7.6: still `PARSE INVALID`, still `0 parsed` — now on
>   `FEEL expression: failed to parse expression 'IF (…ongoing reporting
>   obligation may terminate… OF status) THEN (PARTY Issuer MUST …'`, i.e. the
>   raw-L4 deontic body the old note predicted would refuse next. **The corpus
>   still does not load on Camunda 8.** What changed is the metamodel gate
>   (`etc/validate-dmn.mjs` now passes) and one KIE error; the deontic-literal
>   refusal is a separate defect.
>
> `regcf-corpus.cases.json` now EXISTS — the `f(x)` problem that blocked it
> (`../legal/regcf/PROJECTIONS.md` §1) is what Phase 5 solved — and pins all 82
> decisions symmetrically, with its own header recording why it is not yet
> engine-exercisable and what must retire first. So `25/25 value(s) as expected`
> below is still a statement about the five-decision shape exhibit only; the
> corpus verdicts are the two quoted lines above, no more.
>
> **Superseded again on 2026-08-02, and this time the corpus EXECUTES.** R12
> (spec §15.12) removed the 15 `EVAL UNDER RULES EFFECTIVE AT` decisions from
> the artifact, and R13 (spec §16) lowered the deontic reporting spine to a
> verdict decision table — the two verbatim families named above, retired.
> Measured on the shipped `expected/regcf-corpus.dmn` with
> `regcf-corpus.cases.json` (67 decisions, 67 pins), verbatim:
>
> - KIE 8.44.0.Final: `XSD valid`; `VALID clean`; `BUILD clean`;
>   `KIE 8.44.0.Final VERDICT: 1 file(s), 1 case(s), 0 error(s), 0 warning(s),
>   67/67 decision(s) SUCCEEDED, 67/67 value(s) as expected, 14/14 service
>   output value(s) as expected` — the last clause is the decision-service
>   sweep, a VALUE check since 2026-08-02: each of the seven emitted services
>   (including `_7_Ongoing_reporting_Rules_202_203_b`, which only became
>   emittable when the verdict table gave the § an output decision) is fed its
>   declared inputDecisions' computed values and each of the 14 declared
>   outputDecisions is compared against the same `expect` pin that checks it
>   as a plain decision. (Until 2026-08-02 the sweep was a null-fed smoke
>   test — six "Required input not found" runtime WARNs that the banner's
>   warning counter did not even count. Both repaired in the harness.)
> - Camunda 8.7.6: `PARSE ok: SEC Regulation Crowdfunding — 17 CFR Part 227
>   (67 decision(s))`; `Camunda 8.7.6 (zeebe-dmn) VERDICT: 1 file(s),
>   1 case(s), 1 parsed, 0 error(s), 67/67 decision(s) evaluated, 67/67
>   value(s) as expected`.
>
> One pin moved under measurement, and it is a finding, not noise:
> `the_over_limit_investor_case_qualifies` had been pinned `false` on the
> unmeasured claim that the investor limb varies per call through BKM
> parameters. Both engines answer `true`: the investment-limit limb's figures
> enter the BKM through its λ-LIFTED closure parameters, bound `name: name` to
> the GLOBAL decisions (spec §6.2), so the per-call over-limit investor never
> reaches the limit check. The pin now records the model truth with that
> derivation — the fourth member of the deliberately-pinned-'wrong' quartet,
> which is now four for four.

> **Extended later the same day (2026-08-02): the dropped fixtures' temporal
> truths relocate into the case harness.** Ruling R-C (spec §15.12.1: "the
> model owns the law under a date; the harness owns the dates") turns the 15
> rule-date-rebinding fixture decisions R12 removed from the artifact into 15
> dated engine cases in `regcf-corpus.cases.json` — each sets
> `RULES_EFFECTIVE_DATE` to the fixture's pinned date, delivers the fixture's
> scenario through the global `inputData`, and pins all 67 decisions to
> L4-evaluated ground truth (the cases file's note block records every
> derivation). Four further SEED cases were added 2026-08-03 to close the two
> structurally inert leaves the §8 diff oracle reported. Measured 2026-08-03 on
> the shipped `expected/regcf-corpus.dmn` with the 20-case file, verbatim:
>
> - KIE 8.44.0.Final: `XSD valid`; `VALID clean`; `BUILD clean`;
>   `KIE 8.44.0.Final VERDICT: 1 file(s), 20 case(s), 0 error(s),
>   0 warning(s), 1340/1340 decision(s) SUCCEEDED, 1340/1340 value(s) as
>   expected, 280/280 service output value(s) as expected`
> - Camunda 8.7.6: `PARSE ok: SEC Regulation Crowdfunding — 17 CFR Part 227
>   (67 decision(s))`; `Camunda 8.7.6 (zeebe-dmn) VERDICT: 1 file(s),
>   20 case(s), 1 parsed, 0 error(s), 1340/1340 decision(s) evaluated,
>   1340/1340 value(s) as expected`
>
> Same artifact, twenty worlds: the `1 case(s) … 67/67` banners quoted above
> were the measurement at the single base case, and `16 case(s) … 1072/1072`
> was the measurement before the seed cases; both stand as history.

> **Superseded 2026-08-05: the unit of Rule 501(a)'s "one year".** The corpus
> encoded the resale restricted period as the constant `365`, which is wrong by
> one day for any holding spanning a 29 February. It is now a calendar
> anniversary (`add years`, in `daydate`'s Calendar Arithmetic, whose clamp
> matches Excel's `EDATE` and — measured — FEEL's `date + duration("P1Y")` on
> both engines), and `Transfer` carries two dates instead of an elapsed count.
> That added two decisions, 67 → **69**, and one case, 20 → **21**: the transfer
> the constant got WRONG, on day 365 of a leap-spanning holding, which the flat
> count permitted and both engines now refuse. Measured 2026-08-05 on the
> shipped `expected/regcf-corpus.dmn`, verbatim:
>
> - KIE 8.44.0.Final: `XSD valid`; `VALID clean`; `BUILD clean`;
>   `KIE 8.44.0.Final VERDICT: 1 file(s), 21 case(s), 0 error(s),
>   0 warning(s), 1449/1449 decision(s) SUCCEEDED, 1449/1449 value(s) as
>   expected, 315/315 service output value(s) as expected`
> - Camunda 8.7.6: `PARSE ok: SEC Regulation Crowdfunding — 17 CFR Part 227
>   (69 decision(s))`; `Camunda 8.7.6 (zeebe-dmn) VERDICT: 1 file(s),
>   21 case(s), 1 parsed, 0 error(s), 1449/1449 decision(s) evaluated,
>   1449/1449 value(s) as expected`
>
> The lowering that made this possible is two arms in `L4.Dmn.Lower`, both
> measured against the engines before being written: `add years`/`add months`
> render as `date + duration(...)` (with `floor(n) * duration("P1Y")` when the
> count is a named constant rather than a literal, so the reference survives),
> and `Day d2 MINUS Day d1` renders as `(d2 - d1).days`. Before them the two new
> decisions emitted raw L4 and were Blocking — the fix and its export had to land
> together, which is the whole argument for R0.

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

Absent the variable those examples are reported `PENDING … UNEXERCISED`, never as
passes, so a green run always says which engine actually looked at the artifact.

### The negative control: does the schema gate go red?

Everything above asserts that a gate stays **green**, which on its own is not evidence the
gate is connected to anything. `jl4/tests-cli/fixtures/dmn-xsd-order/` holds a matched pair
of hand-written DMN 1.3 files that answers the other question:

| file                              |                                                              |
| --------------------------------- | ------------------------------------------------------------ |
| `M1-itemdef-before-inputdata.dmn` | `itemDefinition` first — DMN 1.3 valid (the positive control) |
| `M1-itemdef-after-inputdata.dmn`  | `itemDefinition` last — DMN 1.3 **invalid**                   |

They contain **the same lines**, differing only in where the `<itemDefinition>` block sits,
and the suite asserts that (`sort . lines` equality) so a red negative always isolates
placement as the cause. They are fixtures, never regenerated: the emitter cannot produce
the negative case, which is the property under test.

What the four checkers say about the misordered file — **measured 2026-07-29**, and worth
reading before trusting any one of them:

| checker                                | on `M1-itemdef-after-inputdata.dmn`                                                            |
| -------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Xerces, via `etc/kie-dmn-check` leg 1   | `XSD INVALID`, `cvc-complex-type.2.4.a`; KIE validator adds `FAILED_XML_VALIDATION`; exit 1     |
| Drools/KIE 8.44 `KieBuilder` + runtime  | **clean** — it builds, loads and answers both cases correctly                                    |
| Camunda 8.7.6                           | `PARSE INVALID`, `0 parsed, 1 error(s)` — rejected outright                                      |
| `etc/validate-dmn.mjs` (dmn-moddle)     | `OK` — misses it entirely, exactly as its own header warns                                       |

So on Drools the **schema check is the only thing** standing between a misordered emitter
and a shipped artifact; "the engine would have caught it" is true of Camunda and false of
Drools. That asymmetry is the whole argument for keeping the Xerces leg first.

```sh
etc/kie-dmn-check/run.sh jl4/tests-cli/fixtures/dmn-xsd-order/M1-itemdef-after-inputdata.dmn \
  --cases jl4/tests-cli/fixtures/dmn-xsd-order/M1-itemdef.cases.json   # expected: exit 1
```

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

Track **S0** is wired for the toy pair: `reg-cf.dmn` and `reg-cf.dmn.md` are
reproducible **byte-for-byte** through `l4 export`, from a repo checkout with
`jl4/examples/dmn/` as the working directory (`jl4/tests-cli` mirrors the `.dmn` leg).

```sh
l4 export --to=dmn    reg-cf.l4 | diff - expected/reg-cf.dmn
l4 export --to=dmn-md reg-cf.l4 | diff - expected/reg-cf.dmn.md

# the corpus, likewise with no flags
l4 export --to=dmn    ../legal/regcf/regcf.l4 | diff - expected/regcf-corpus.dmn
l4 export --to=dmn-md ../legal/regcf/regcf.l4 | diff - expected/regcf-corpus.dmn.md
```

**The corpus `.dmn` (and `gst-rate.dmn`) do NOT reproduce byte-for-byte, and the
difference is exactly the source-range labels** (measured 2026-08-02): the goldens are
generated by `jl4/tests/DmnExport.hs` through `checkWithImports`, which loads every
module under the virtual URI `main`, so the dated-constant annotation columns carry
`(main.l4:…)` where the CLI — which knows the real path — writes `(regcf.l4:…)` /
`(gst-rate.l4:…)`. The corpus diff is those 23 annotation lines and nothing else
(gst-rate: 4); the `.dmn.md` legs carry no source ranges and reproduce exactly. An
earlier revision of this section claimed byte-for-byte reproduction for everything
here, which the corpus golden never satisfied. Making the golden harness carry real
paths is a possible follow-up; until then, this paragraph is the contract.

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

`--include-tests` (DMN targets only) also emits decisions the population filter
classifies as test scaffolding. It defaults **off** — a fixture emitted as a
`<decision>` misdescribes the rule set — but the switch exists because the filter is a
measurement about four corpora, not a soundness property: it keys off `#ASSERT`
placement, so adding a test can change the exported model. Every drop is named by a
`D-FIXTURE` or `D-REGULATIVE` note; the filter is never silent.

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
