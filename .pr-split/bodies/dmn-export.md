# feat(dmn): DMN 1.3 export — lowering, fidelity reporting, and two engine harnesses that check answers

**What this adds.** L4 modules can now be exported to **DMN 1.3** — the OMG interchange format for
decision models — as XML, and to **dmnmd markdown**, from one shared intermediate representation.
The lowering turns L4's guarded chains (`IF` / `BRANCH` / `CONSIDER`) into DMN decision tables,
records and enums into typed `itemDefinition`s, cross-decision calls into
`businessKnowledgeModel`s with their `knowledgeRequirement` edges, sections into
`decisionService`s, and `RULES EFFECTIVE DATE` into a real date-axis input with `UNIQUE`-hit
interval tables. Every export is accompanied by a **fidelity report**: a located, named list of
what the target notation could not carry, at one of three severities (`Blocking` / `Lossy` /
`Advisory`). And the emitted XML is not merely schema-checked — two committed, version-pinned Java
harnesses run it through **Drools/KIE 8.44.0.Final** and **Camunda 8.7.6 (`io.camunda:zeebe-dmn`)**
and compare **every decision's answer** against a value pinned from L4 itself. Before this, L4 had
no decision-table interchange at all.

**Why.** This is track **D1** of the lexipedia-superset programme and the decision half of milestone
**M4** ("DMN + BPMN out, each with its fidelity report"). The motivating problem is stated in
`L4.Dmn.IR`'s own header: DMN's analysis lineage — completeness/consistency checking, inter-tabular
checking, cross-DRD SMT verification — is defined over **S-FEEL**, the simple fragment, while the
DMN specification itself (§9.1) says "few if any complete decision models can be defined using
S-FEEL" and tells you to use full FEEL instead. So the fragment you can verify is not the fragment
you are told to write, and an exporter that silently straddles that line ships models no checker
checks and no engine runs. The fidelity report exists to name each crossing, in place. Issues
answered along the way, all upstream in `smucclaw/l4-ide`: **#925** (engine flavors, ruling R7),
**#933** (date-literal provenance), **#936** (FEEL `some`/`every` and a binder that actually binds),
**#937** (`validate-dmn.mjs` was not a well-formedness backstop), and **#922** (`selectIdiom` folded
a *boolean* select to FEEL `max`/`min`, which DMN 1.3 Table 54 does not define over booleans —
"this module's strongest claim of executability, made about an expression DMN does not define, with
no fidelity note"). **#923** — R2 strictness — is a spec ruling and is discharged in the `specs`
theme, not here.

---

## What's in it

**101 files, +32,380 / −135.**

### Exporter core — 6 Haskell modules, ~10,300 lines

| module | lines | what it does |
| --- | --- | --- |
| `jl4-core/src/L4/Dmn/IR.hs` | 1350 | the DMN 1.3-shaped IR (`Drg`, `Decision`, `DecisionTable`, `UnaryTest`, `FeelExpr`, `ItemDefinition`), plus FEEL surface syntax: `renderNumber`, `quoteFeelString`, `reservedFeelWords`, `reservedFeelTypeNames`, `uniquifyIn`. Knows nothing about XML. |
| `jl4-core/src/L4/Dmn/Lower.hs` | 6792 | `Module Resolved` → `Drg`, by way of `L4.Viz.GuardedRows`. Table lowering, itemDefinitions, hydrator decisions for computed fields, `MAYBE`→FEEL `null`, `YMD`/`Date` folding to `date("YYYY-MM-DD")`, rule-date interval tables, BKM emission and call-site invocation, decisionService splitting, the deontic verdict table, and every fidelity note's text. |
| `jl4-core/src/L4/Dmn/Analysis.hs` | 1002 | the un-lifting (tier) analysis over call sites, totality/termination certification, and cycle detection over the requirement graph. |
| `jl4-core/src/L4/Dmn/Emit.hs` | 632 | `Drg` → DMN 1.3 XML, including `DMNDI` diagram geometry so the file opens in a modeler rather than as a blank canvas. |
| `jl4-core/src/L4/Dmn/Markdown.hs` | 455 | the same IR → dmnmd markdown, with its **own** loss list. Two emitters over one IR is the argument, not a convenience — the alternative is two hand-maintained exporters that quietly disagree about what a number looks like. |
| `jl4-core/src/L4/Interchange/Fidelity.hs` | 81 | the shared, dependency-free note/severity/report type. Deliberately small so the decision-side and process-side tracks can share it without coupling to each other — the BPMN exporter imports it too. |

`FidelitySeverity` is ordered `Blocking < Lossy < Advisory`, and the doc comment is explicit that
`Blocking` is a statement about **the target notation**, not about your file: "the target cannot
express this at all; we emitted a fallback."

### Engine harnesses and gates — 7 files

- `etc/kie-dmn-check/` (`pom.xml`, `run.sh`, `KieDmnCheck.java`, 726 lines) — four legs: Xerces XSD
  validation (from the resource inside `kie-dmn-validation`'s own jar, so nothing is downloaded),
  the KIE validator, `KieBuilder`, and `evaluateAll` + `evaluateDecisionService` with
  expected-value comparison. Version-pinned to `8.44.0.Final`; Maven resolves into `$TMPDIR`,
  nothing resolved is committed, `package.json` and the lockfile are untouched.
- `etc/camunda-dmn-check/` (`pom.xml`, `run.sh`, `CamundaDmnCheck.java`, 443 lines) — the same
  contract against `io.camunda:zeebe-dmn` 8.7.6.
- `etc/validate-dmn.mjs` (457 lines) — a dependency-free lexical well-formedness scanner, plus
  `xmllint --noout` when it is on PATH (never *required*, because a gate that silently weakens on a
  missing binary is the failure being fixed), in front of the `dmn-moddle` metamodel check.

Both harnesses take a `--cases` file and compare **values**, not liveness. That distinction is
load-bearing: `25/25 SUCCEEDED` passes a file that answers `true` where a number was meant, which is
exactly the Camunda misparse the flavor work was built around.

### Exhibits, cases and goldens

- **9 `.l4` subjects** under `jl4/examples/dmn/`: `reg-cf.l4` (shape), `gst-rate.l4` (dated regime),
  `sumtype.l4` (data model), `hydration.l4` (computed fields), `bkm.l4`, `svc.l4` (decisionService),
  `unlift.l4`, `deontic-verdict.l4`, `ymd-dates.l4`.
- **7 `.cases.json`** expected-value files. Every pinned value is evaluated from L4, never read back
  from an engine.
- **20 negative fixtures** under `not-ok/`: 11 cycle shapes (forward, mutual nullary, mutual
  parameterised, self, `WHERE`-local, computed field, section-qualified, `MEANS`, guard, triangle),
  6 dated-chain refusals (mis-ordered, duplicate date, rolling date, mixed axis, nested
  `OTHERWISE`, regulative body), plus `ruledate-rebind`, `svc-empty-ruledate` and
  `ymd-unfoldable-date`.
- **42 goldens** under `expected/`: 11 `.dmn`, 10 `.dmn.md`, 21 fidelity reports. The `svc.kie.*`
  pair is the flavor split made visible — on the `kie` flavor a call site becomes
  `knowledgeRequirement` → `decisionService` and emits `special_assessment(p: 150, q: 5) +
  base_charge`, where the `camunda` flavor emits an `informationRequirement` and the raw-L4
  fallback ``(`special rate` OF 150, 5) PLUS `base charge` ``.
- `jl4/examples/dmn/README.md` (545 lines) — the exhibit index, the pipeline diagram, the engine
  instructions, and the dated measurement log.

### Tests

- `jl4/tests/DmnExport.hs` (4198 lines) — the golden driver plus the property tests: the law-time
  invariant, the cycle-refusal family, the flavor same-bytes/divergence assertions, the tier-split
  census, and the BKM probe matrix.
- **8 evaluation-trace goldens move** (`jl4/examples/{ok,legal}/tests/*.golden`, −135 lines net).
  These are *not* DMN goldens — they record `L4.Print.prettyLayout` output and move with the printer
  round-trip repair. See **Independence**.

---

## Evidence

Quoted from the source PRs, in the order they were measured.

**#143 — the originating exporter.** "Measured across 367 corpus files: only 23% of the 3272 FEEL
texts the exporter emits are in the statically analysable fragment (1521 `L4Verbatim` / 982
`FullFeel` / 769 `SFeel`)." `cabal test jl4` — **1555 examples, 0 failures**. The bug it fixed: a
verbatim `defaultOutputEntry` "returns null with status `SUCCEEDED` and **no** evaluation-time
message — the silent case, and 18 of the 28 affected cells were in exactly that position."

**#160 — two engine flavors (R7), answers not liveness.** KIE 8.44.0.Final: `1 file(s), 5 case(s),
0 error(s), 0 warning(s), 25/25 decision(s) SUCCEEDED, 25/25 value(s) as expected`. Camunda 8.7.6:
`1 file(s), 5 case(s), 1 parsed, 0 error(s), 25/25 decision(s) evaluated, 25/25 value(s) as
expected`. The flavors were **byte-identical at that point** and the PR says so, with a test named
*"EXPECTED TO FAIL AT PHASE 5: the two flavors are still byte-identical"*. The one measured
divergence: a `decisionService` as the target of a `knowledgeRequirement` gives KIE `caller
SUCCEEDED = 610` and Camunda `PARSE INVALID: DecisionServiceImpl cannot be cast to
BusinessKnowledgeModel` — whole DRG rejected. Suites: `jl4-test` 1820/0, `l4-cli-test` 96/0
(2 pending), and with `L4_DMN_ENGINE_CHECK=1 KIE_CHECK_REQUIRED=1 CAMUNDA_CHECK_REQUIRED=1`,
**96/0/0 pending**.

**#175 — itemDefinitions (Phase 3).** "**KIE errors on the corpus: 48 → 2.**" `jl4-test` 1875/0;
`l4-cli-test` 101/0 with both engines required; "KIE 8.44.0.Final answers the reg-cf golden 25/25".

**#178 — law time on a date axis.** `gst-rate.l4` "answers **70/70 values on KIE 8.44.0.Final and
Camunda 8.7.6**, including both boundary seams … and the pre-commencement floor." `jl4-test`
1901/0; `l4-cli-test` 108/0 with both engines REQUIRED; ".actual sweep 1283/1283 byte-identical."

**#180 — hydration + MAYBE→null.** New golden subject `hydration.l4`: "**44/44 on KIE 8.44 and 44/44
on zeebe-dmn 8.7.6**, distinct from the hand-written probe (6/6 both) so a red run isolates engine
vs lowering." `jl4-test` 1922/0, `l4-cli-test` 123/0 with both engines required.

**#181 — Phase 5 groundwork.** 23 hand-written BKM probe fixtures executed against both engines;
baseline recorded as **112 Blocking / 44 Lossy / 21 Advisory** on `regcf-corpus.fidelity.txt`, and
a corrected prediction of **112 → 104**.

**#183 — Phase 4 un-lifting.** KIE: "4 cases, 0 errors, 0 warnings, **40/40** decisions SUCCEEDED,
**40/40** values as expected"; Camunda: "1 parsed, 0 errors, **40/40** decisions evaluated, **40/40**
values as expected." Census on `regcf-corpus`, before → after: inputData **66 → 37**; decisions
**101 → 92**; D-SCOPE **9 → 7**; D-LITERALEXPR **89 → 80**; D-RENAME **35 → 11**. Measured tier-2
rates **4.8% / 4.0% / 5.9%** across corpora. `jl4-test` 2102/0, `l4-cli-test` 125/0 with engines
live. The PR also discloses eleven advisory findings verbatim, including that the §8 census
obligation is **only partly discharged** — the old `654/5/0.8%` and `541/1/0.2%` cells have no
successor figure.

**#188 — Phase 5 BKM emission.** "**Blocking findings on `regcf-corpus.fidelity.txt`: 95 → 32**";
full decomposition at that tip **32 blocking / 5 lossy / 115 advisory**. And, stated plainly in the
same PR: "**The corpus loads on neither engine, and nothing in this PR claims otherwise** — KIE
stops at 16 build errors and evaluates nothing; Camunda refuses the file at parse, `0 parsed`." The
PR was retitled for exactly that reason: "the title previously read 'the corpus executes'; measured,
the corpus loads on neither engine." `jl4-test` 2161/0, `l4-cli-test` 175/0/0 pending, **46 probe
engine legs green** (23 KIE + 23 Camunda).

**#194 — R12 + R13, the corpus executes.** KIE: `1 file(s), 1 case(s), 0 error(s), 0 warning(s),
67/67 decision(s) SUCCEEDED, 67/67 value(s) as expected, 14/14 service output value(s) as
expected`. Camunda: `1 parsed, 0 error(s), 67/67 decision(s) evaluated, 67/67 value(s) as
expected`. Census `32 blocking / 5 lossy / 115 advisory` → **0 blocking / 21 lossy / 125
advisory**; `D-CYCLE` 1 → **0, by construction**. 18 adversarial findings confirmed and fixed,
"none was fixed by weakening a pin or deleting a finding." `jl4-test` 2213/0, `l4-cli-test` 177/0.

**#196 — `YMD` date-literal folding.** The BNA corpus goes from `0 case(s), 6 error(s)` (KIE) and
`0 parsed, 1 error(s)` (Camunda) on `ERR_COMPILING_FEEL … 'YMD OF 1983, 1, 1' … syntax error near
'OF'` to `1075/1075 decision(s) SUCCEEDED, 1075/1075 value(s) as expected, 325/325 service output
value(s) as expected` (KIE) and `1075/1075` (Camunda) — fidelity **3 blocking → 0**. The new
`ymd-dates` exhibit: `48/48` values and `16/16` service outputs on KIE, `48/48` on Camunda. Golden
immutability was checked and reported: all four `expected/` changes are **additions**, "no
pre-existing golden byte moved."

**#206 — three exporter defects, each with a failing negative control.** The quantifier fix takes
the Jersey charities cleanroom to `1000/1000` on both engines; **reverting the binder half alone**
takes it to **993/1000** and the four fresh worlds to **152/160**, where "the broken artifact says
an entity **meets the charity test** where L4 says it does not." The `validate-dmn.mjs` backstop
agrees with `xmllint`'s exit status **20/20** on a 20-case well-formedness battery. Reg CF engine
cases 16 → 20: `1340/1340` on both. And the sensitivity table, which is the most useful number in
the set — with the pre-seed 16 cases, **deleting the entire 501(a)(2) accredited-investor exception
still scored 1072/1072, exit 0 — invisible**; with the 4 seed cases it scores 266/268.

**#208 — enumeration labels.** Reg CF numbers deliberately unmoved: KIE `16 cases, 0 errors,
1072/1072 decisions, 1072/1072 values, 224/224 service outputs`; Camunda `1072/1072`. BNA
`1075/1075` on both. Two findings the PR asks you not to misread: BNA's green "belongs to the
exporter, not to this ruling", and "the Reg CF DMN moved in associativity only."

**Final state, at the tip of `unstable`** — from `jl4/examples/dmn/README.md`, measured 2026-08-09
on the shipped `expected/regcf-corpus.dmn`, verbatim:

- **70 decisions (12 decision tables), 10 `businessKnowledgeModel`s, 7 `decisionService`s,
  15 `inputData`, and ZERO blocking notes (0 blocking / 21 lossy / 133 advisory).** Every figure in
  this line was re-counted directly off the two shipped goldens while drafting this PR, not taken
  on the README's word: `<decision id=` 70, `<decisionTable` 12, `<businessKnowledgeModel` 10,
  `<decisionService` 7, `<inputData id=` 15, and 0 / 21 / 133 severity lines in
  `regcf-corpus.fidelity.txt`.
- KIE 8.44.0.Final: `XSD valid`; `VALID clean`; `BUILD clean`; `1 file(s), 22 case(s), 0 error(s),
  0 warning(s), 1540/1540 decision(s) SUCCEEDED, 1540/1540 value(s) as expected, 330/330 service
  output value(s) as expected`
- Camunda 8.7.6: `PARSE ok: SEC Regulation Crowdfunding — 17 CFR Part 227 (70 decision(s))`;
  `1 file(s), 22 case(s), 1 parsed, 0 error(s), 1540/1540 decision(s) evaluated, 1540/1540 value(s)
  as expected`

---

## Independence

**This PR is not standalone.** It is the largest single body of code in the split and it sits in the
middle of the dependency graph. Honestly:

**It needs, to build:**

- **`ladder-viz`** — `jl4-core/src/L4/Viz/GuardedRows.hs`. `L4.Dmn.Lower` is *driven by* the
  `normaliseGuarded` normaliser; there is no table lowering without it. Hard compile-time
  dependency.
- **Shared cabal plumbing not owned by any theme** — the `L4.Dmn.*` / `L4.Interchange.Fidelity`
  stanzas in `jl4-core/jl4-core.cabal`, the `DmnExport` other-module in `jl4/jl4.cabal`, and the
  `goldenSubjects` registration in `jl4/tests/Main.hs`. These must be merged, not chosen.

**It needs, for its goldens to be reproducible:**

- **`corpus-regcf`** — `jl4/examples/legal/regcf/regcf.l4`. Four of the 42 goldens
  (`regcf-corpus.{dmn,dmn.md,fidelity.txt,md.fidelity.txt}`) and `regcf-corpus.cases.json` are cut
  from that file; without it they regenerate to nothing. The 1540/1540 headline is a measurement of
  *that corpus through this exporter*, so the two are joint evidence.
- **`lang-printer`** — `L4.Print.prettyLayout`. Two ways: the raw-L4 verbatim fallback inside
  `<text>` elements is `prettyLayout` output, so the `.dmn` goldens encode printer behaviour; and
  the 8 evaluation-trace goldens in this file set (`ok/lazytrace*.golden`, `ok/contracts.golden`,
  `ok/prohibition.golden`, `legal/ceo-performance-award.golden`,
  `legal/directive-showcase.golden`, `legal/ny-environmental-7.3.golden`) move **only** because of
  the round-trip repair in PR #214 — they are printer goldens that landed in this file set because
  they were touched by a PR this theme also draws from. If `lang-printer` is dropped, those eight
  files should be dropped with it.
- **`lang-syntax-typecheck`** — PR #185's clause-matrix exhaustiveness added 19 lines to
  `L4/Dmn/Analysis.hs` and 11 to `Lower.hs`; PR #198's BPMN→DMN wiring added 10 to `IR.hs` and 6 to
  `Lower.hs`. Those hunks ride along here, but the analysis they cooperate with lives elsewhere.

**It needs, to be reachable and gated by a user:**

- **`service-cli`** — `jl4-core/src/L4/Export.hs` and `jl4/app/L4/Cli/Export.hs`, i.e.
  `l4 export --to=dmn|dmn-md`. Without it the exporter is a library entry point exercised only by
  the test suite (which is exactly the state PR #154 was opened to fix).
- **`tests-cli`** — `jl4/tests-cli/Main.hs` is where the engine legs are actually invoked under
  `L4_DMN_ENGINE_CHECK=1 KIE_CHECK_REQUIRED=1 CAMUNDA_CHECK_REQUIRED=1`. This PR ships the
  harnesses; that PR ships the calls.
- **`ci-build`** — the `dmn-engines` job in `.github/workflows/pr-checks.yml`.
- **`specs`** — `specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md`, `DMN-PHASE5-BUILD-PLAN.md`,
  `FIDELITY-SEVERITY-AXIS-SPEC.md`. Note text and code comments cite these by section number
  (§6.2, §11-R8, §15.12, §16), so dropping the specs leaves live dangling references.

**What depends on it (not the other way round):**

- **`bpmn-export`** imports `L4.Interchange.Fidelity` from this PR. The module is deliberately
  dependency-free in the other direction — it knows nothing about DMN.
- **`go-pipeline`** and **`corpus-legal-new`** consume the exporter to cut projections.

**What it does not need at all:** `agent-tooling`, `wizard-housing`, `wizard-regcf`, `mlir`,
`proleg`, `openfisca-export`, `actus-archive`, `papers`, `experiments`, `lang-sets`, `lsp`, `docs`,
and anything in `ladder-viz` beyond `GuardedRows.hs`.

---

## Risk if rejected

Dropping this drops the entire decision half of milestone M4: no DMN XML, no dmnmd markdown, no
fidelity report type — which also breaks `bpmn-export`, since `L4.Interchange.Fidelity` lives here
and the BPMN side imports it. `service-cli`'s `l4 export --to=dmn` and `--to=dmn-md` become dead
flags, the `dmn-engines` CI job has nothing to run, and the strongest external validation this repo
has of its own semantics — two independent commercial engines agreeing with `l4` on 1540 values
across 22 cases of a real 17 CFR Part 227 encoding — disappears with it.

---

## Provenance

Unstable PRs folded into this one:

- **#143** — `mengwong/dmn-export`, *feat(dmn): DMN 1.3 exporter, with fidelity reporting that
  blocks on unexecutable output* — the originating PR. Not listed in the theme manifest; recovered
  from history (`20992358`, `97852a7d`, `8494290e`, `7ee8c99f`, `5cf9d3a8` all trace to it).
- **#154** — `legalese/feat/export-surfaces` — *feat(surfaces): l4 export CLI (S0) + jl4-service
  /ladder (S1)*. Only its `jl4/examples/dmn/README.md` hunk lands here — the copy-pasteable
  CLI reproduction instructions. The CLI itself belongs to `service-cli`.
- **#160** — `legalese/feat/dmn-engine-flavors` — *fix(dmn): two engine flavors (R7), with both
  engines checking answers not just liveness*.
- **#162** — `legalese/feat/regcf-projections` — *feat(regcf): cut BPMN from the corpus itself;
  triage every projection finding* (DMN projection portion).
- **#172** — `legalese/mengwong/regcf-rule-version` — *feat(regcf): the rule-version axis — C1
  complete, temporally closed, OpenFisca-informed* (corpus golden re-cut).
- **#175** — `legalese/mengwong/dmn-itemdefs` — *feat(dmn): itemDefinitions for records and enums —
  export Phase 3*.
- **#178** — `legalese/mengwong/dmn-ruledate` — *feat(dmn): law time on a date axis — rule-date
  input, UNIQUE interval tables, D-RULEDATE*.
- **#180** — `legalese/mengwong/dmn-hydration-null` — *feat(dmn): hydration for computed fields +
  MAYBE→null (R8-d′) + isJust recognition*.
- **#181** — `legalese/mengwong/bkm-phase5` — *DMN Phase 5 groundwork: BKM engine probes + build
  plan* (the 10 `not-ok/cycle-p*.l4` fixtures).
- **#183** — `legalese/mengwong/bkm-phase4-unlift` — *DMN Phase 4: un-lifting analysis + totality +
  R6 population filter*.
- **#185** — `legalese/mengwong/open6-clause-matrix` — *exhaustiveness for multi-clause DECIDEs*
  (the `Analysis.hs`/`Lower.hs` hunks only).
- **#188** — `legalese/mengwong/dmn-phase5-bkm` — *DMN Phase 5: BKM emission — corpus blocking
  findings 95 → 32*.
- **#194** — `legalese/mengwong/dmn-r0-executable` — *dmn(R12+R13): the Reg CF corpus executes —
  67/67 values on KIE and Camunda, 14/14 service outputs value-checked*.
- **#196** — `legalese/mengwong/feel-date-lowering` — *feat(dmn): FEEL date-literal lowering for
  `YMD`*.
- **#198** — `legalese/mengwong/bpmn-dmn-wiring` — *feat(bpmn): wire each guarded gateway to the
  emitted DMN* (the `IR.hs`/`Lower.hs` hunks only).
- **#205** — `legalese/mengwong/clitic-corpus-fix` — *refactor(regcf): drop the redundant leading
  `is ` from 11 field names* (golden re-key).
- **#206** — `legalese/mengwong/exporter-fixes` — *fix(dmn): three exporter defects closed with
  failing negative controls — quantifier binder (#936), date provenance (#933), well-formedness
  gate (#937)*.
- **#208** — `legalese/mengwong/inert-label-truncation` — *Enumeration labels: inert never shadows
  active* (goldens unmoved in value; associativity only).
- **#214** — `legalese/mengwong/printer-batch-and-gensym` — *fix(print): make prettyLayout
  round-trip* (the 8 evaluation-trace goldens and the corpus `<text>` re-render; the printer itself
  belongs to `lang-printer`).
- **#224** — `legalese/mengwong/go-explainer` — *The explainer stage, a BPMN renderer, the grouping
  tutorial, and the de novo Reg CF run*. Contributes two calendar-arithmetic lowerings to
  `Lower.hs` (+84 lines): `Day d2 MINUS Day d1` as a peephole rendering to `(d2 - d1).days`, and
  `add months`/`add years` as `date + duration(...)` — the code comment records both as measured on
  KIE 8.44.0.Final and Camunda 8.7.6 across six cases. Plus the corpus golden re-cut that follows.
