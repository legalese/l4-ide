# test(cli): grow the black-box `l4` suite from 20 to 161 cases, with 108 fixtures and two live DMN engine harnesses

**What this adds**

`jl4/tests-cli` is the black-box test suite for the `l4` command-line binary: every case spawns the real `l4` executable as a subprocess and asserts on its exit code, stdout, stderr and — for the `--json` modes — the shape of the parsed envelope. On `main` it covers six subcommands with 20 `it` blocks. This PR replaces `jl4/tests-cli/Main.hs` (296 → 2387 lines, 161 `it` blocks in 29 `describe` groups) and adds **108 new fixture files** beside it. After this, the suite exercises `l4 batch` in all four output modes, `l4 export` to DMN/dmn-md/BPMN including its fidelity report and `--fail-on` gates, `l4 nlg`, `l4 verify`, `l4 openfisca`, import-cycle refusals, library-resolution shadowing, and — behind an opt-in environment variable — drives two real DMN engines (Drools/KIE 8.44.0.Final and Camunda 8.7.6 `zeebe-dmn`) over 35 hand-written `.dmn` probe files and the emitted goldens.

**Why**

Three separate gaps drove it. First, subcommands kept shipping with no front-door test at all: `l4 export`, `l4 nlg`, `l4 verify` and `l4 openfisca` each existed as a library entry point exercised only in-process, so nothing pinned that the CLI reached the same bytes. Second, a whole class of defect was invisible to in-process tests — PR #134 records that "the embedded stdlib came to outrank project-local libraries for a whole release without a red test", because no test ran `l4 check main.l4` from inside a project directory, and issue **smucclaw/l4-ide#906** is the diamond-import case of the same family. Third, the DMN export programme needed an answer to "does a real engine accept this?", and the only honest answer is to run one: the suite is where the committed KIE and Camunda harnesses get driven from a single `cabal test` command, with a skip contract that reports an unavailable engine as `# PENDING` rather than as a pass.

## What's in it

**One Haskell module, 108 fixtures.** `jl4/tests-cli/Main.hs` is the only modified file; every fixture is new. By kind: 36 `.cases.json`, 35 `.l4`, 35 hand-written `.dmn`, 2 `.csv`. **No build-file change is needed** — the `test-suite l4-cli-test` stanza in `jl4/jl4.cabal` is byte-identical between `main` and `unstable`.

**Harness infrastructure** (roughly the first 800 lines of `Main.hs`):

- `runL4In` reads both child streams as raw bytes and decodes UTF-8 leniently, bypassing the system locale — the fix for a Windows CI runner rejecting the `§` and em-dash bytes in help text. `jsonEnvelope` re-encodes stdout as UTF-8 rather than truncating each `Char` to eight bits, which had turned an em-dash in a corpus decision name into a control byte aeson rejected.
- `runL4WithXdgHome` / `runL4EmbeddedOnly` / `runL4In`'s `cwd` parameter let a test choose the child's environment **and** working directory, so the library resolver can be driven in the dev regime (no `JL4_LIBRARY_PATH`, a caller-controlled XDG store) that CI otherwise hides.
- `dmnEngineCheckOn` runs one committed engine harness over one file under an explicit contract: opt-in on `L4_DMN_ENGINE_CHECK=1`; assertion on the harness's `VERDICT:` banner rather than its exit code (a harness that cannot run also exits 0); `HarnessMustPass` / `HarnessMustFail` so negative controls can be pinned in the rejecting direction; a missing *script* is a failure even locally, because that is a fact about the repo and not about the machine.

**Subcommand coverage**, by group (counts are `it` blocks):

| group | n | what it pins |
| --- | --- | --- |
| `run` / `check` / `format` / `ast` / `trace` / `state-graph` | 22 | the pre-existing six, plus a crashing `#EVAL` failing `l4 run` while `l4 check` still succeeds on the same file |
| `batch` | 12 | NDJSON / `--format json` / `--format csv` / `--output`, stop-at-first-failure vs `--continue-on-error`, `validate-only`, CSV cell type inference, exponent-form cells kept as STRING, `MAYBE` primitive params, backslash/quote/control-char payloads |
| `trace` output-path safety | 2 | no shell is spawned for the output path (metacharacters cannot inject); a directory whose path contains a space |
| import cycles | 6 | 3-module ring, 2-module ring, self-import, JSON `ok=false`, and a clean multi-file import as the over-firing guard |
| embedded-library diamond (#906) | 1 | a transitive re-export threaded into both diamond siblings |
| library-resolution shadow (B′) | 8 | embedded stdlib outranks a poisoned XDG copy; symlinks dereferenced when naming the shadowed file; a project-local override still wins; identical copies stay silent, differing copies warn; the same questions again with the entry file named bare; and an *embedded* importer being type-checked against the project-local override |
| `export` | 32 | BPMN / DMN 1.3 XML / dmnmd goldens reproduced byte-for-byte on stdout; the fidelity report written as a sibling file, or to stderr when the document owns stdout; the four `--fail-on` thresholds against a matched blocking-only + advisory-only fixture pair; refusals that name their candidates; `--flavor camunda\|kie\|drools` and its rejections |
| `nlg` | 4 | linearizes and exits 0, refuses a module that does not typecheck, reproduces the two committed regcf `.nlg` goldens byte for byte |
| `verify` | 18 | one clean control plus one negative per finding family (`unsat`, `dead-branch`, `vacuous-guard`, `unreachable-outcome`), asserting the finding **kind** and not just exit 1; the propositional bound stated in the report, in `--help`, and rendered as paragraphs rather than one reflowed wall; `nestedNotVisited` counted so `analysed + skipped` stops reading as a total |
| `openfisca` | 14 | ten example modules compiled against their committed `.py` goldens, two rejections, and two shape assertions |

**The engine legs** — every `describe` here carries `(opt-in: L4_DMN_ENGINE_CHECK=1)` in its own title:

- `dmn-bkm-probe/` — **23 hand-written model + cases pairs (46 files)**, driven as 46 legs (23 KIE + 23 Camunda) from a single `bkmProbeMatrix` table that records each fixture's measured outcome per engine. Groups A (BKM shape), B (BKM × hydration), C (`knowledgeRequirement`), D (`decisionService`), E (name collisions). The asymmetric rows are the point: seven fixtures fail on KIE and pass on Camunda, and in every one of them Camunda's silence is the hazard.
- `dmn-xsd-order/` — a committed pair differing **only** in where the `<itemDefinition>` block sits, plus a plain text assertion that this is the only difference. Xerces rejects the misordered one; both engines are pinned accepting the good one and rejecting the bad one.
- `dmn-date-probe/` and `dmn-date-arith/` — date literals and comparisons on both engines, `annotationEntry` with and without an `@id` (the negative control), and the clamp equivalence: `daydate`'s `add months` / `add years` clamp, FEEL's `date + duration(...)` had to be *measured* to clamp the same way, and `reconstruct-refused.dmn` is the `MustFail` twin showing the component-reconstruction idiom cannot.
- `dmn-null-probe/`, `dmn-hydration-probe/`, `dmn-engine-intersection/` — FEEL null semantics (including the one question the engines answer differently, pinned MustPass on one and MustFail on the other, each asserting that engine's own words); the boxed-context hydration idiom; and the three spellings of one statute-shaped per-element predicate.

## Evidence

Quoted from the source PRs, each measured on its own tree:

- **#134** — `l4-cli-test` **60/60**, "5 new black-box regressions: poisoned-XDG §3.1 incident, symlink dereference in the warning, project-local override wins, identical-copies silence, non-embedded-module shadow warning".
- **#154** — `l4-cli-test` 64 → **87, 0** — "+23, all `l4 export`". Also: "across `jl4-service/test` and `jl4/tests-cli` the diff deletes **zero** `it "…"` lines and adds 41."
- **#160** — `l4-cli-test` **96 examples, 0 failures, 2 pending**; with `L4_DMN_ENGINE_CHECK=1 KIE_CHECK_REQUIRED=1 CAMUNDA_CHECK_REQUIRED=1`: "**96 examples, 0 failures, 0 pending**, both engines `[✔]`".
- **#175** — `l4-cli-test` **101/0** with both engines required.
- **#176** — `l4-cli-test`: "**107 examples (6 new), 0 failures** … all six intersection specs exercised live, none pending". Its measured triple: inline-in-`satisfies` → KIE pass, 0 warnings / zeebe-dmn pass; decision table in a boxed-context entry → KIE pass, 1 warning / zeebe-dmn **parse failure**; the same table in a BKM → pass on both.
- **#178** — `l4-cli-test` **108/0** with both engines REQUIRED.
- **#180** — `l4-cli-test` **123/0** with `KIE_CHECK_REQUIRED=1 CAMUNDA_CHECK_REQUIRED=1`.
- **#181** — the 23 probes "executed 2026-07-31 against **KIE 8.44.0.Final (JDK 17)** and **zeebe-dmn 8.7.6**".
- **#183** — `l4-cli-test` (engines live) **125 examples, 0 failures**; "KIE 8.44.0.Final — 4 cases, 0 errors, 0 warnings, 40/40 decisions SUCCEEDED, 40/40 values as expected"; "Camunda 8.7.6 (zeebe-dmn) — 1 parsed, 0 errors, 40/40 decisions evaluated, 40/40 values as expected". Two of the 125 initially failed on a stale `44/44` literal left behind when the cases file was reshaped; both engines had been reporting `40/40 … as expected` the whole time.
- **#188** — `l4-cli-test` **175 examples, 0 failures, 0 pending**; "**46 probe engine legs green** — counted from the run, 23 KIE + 23 Camunda, including the `D2 svc-invoked` pair (`KIE MustPass` / `Camunda MustFail`). Zero pending, zero skipped."
- **#194** — `l4-cli-test` **177/0** with both engines required, zero pending; the corpus leg's verbatim verdicts were "67/67 decision(s) SUCCEEDED, 67/67 value(s) as expected, 14/14 service output value(s) as expected" (KIE) and "1 parsed, 0 error(s), 67/67 decision(s) evaluated, 67/67 value(s) as expected" (Camunda).
- **#206** — `l4-cli-test` **180/0, 79 pending**.
- **#207** — `l4-cli-test` **PASS (202 examples, 0 failures, 79 pending)**. Also: "Five committed `verify-*.l4` control fixtures reproduce their declared verdicts — one clean module at exit 0, one module per finding family at exit 1 reporting exactly the family it is named for. Kinds, not exit codes, because `x AND x` exits 1 for the wrong reason."

The 161 `it` blocks in the source expand at run time — the 23-row probe matrix contributes two legs each, and one helper is instantiated twice — which is why the run counts above exceed the static block count. The last figure measured in a source PR is #207's 202/79; the date-arithmetic clamp probe landed after it and adds four more engine legs.

## Independence

**This PR is not standalone.** It is a test suite, and it tests other themes' code. Specifically:

- **`service-cli`** — hard dependency. `jl4/app/Main.hs` and `jl4/app/L4/Cli/{Export,Nlg,Verify,Batch,Trace,Run,Check,Common}.hs` live there, as does the `jl4/jl4.cabal` edit that registers `L4.Cli.Export`, `L4.Cli.Nlg` and `L4.Cli.Verify` as modules of the `l4` executable. Without that theme, the 54 blocks covering `export` (32), `verify` (18) and `nlg` (4) fail at the subcommand level — those three subcommands do not exist on `main` — and the 12 `batch` blocks and 2 trace-safety blocks assert behaviour that theme adds to subcommands `main` already has.
- **`dmn-export`** — hard dependency for every engine leg and every `--to=dmn` golden comparison. It owns `jl4/examples/dmn/**` (the goldens, the `.cases.json` files) and both harness scripts, `etc/kie-dmn-check/run.sh` and `etc/camunda-dmn-check/run.sh`. A missing harness script is asserted as a **failure**, not a skip, so this theme cannot land its engine block ahead of `dmn-export`.
- **`bpmn-export`** — hard dependency for the three BPMN blocks, which read `jl4/examples/bpmn/offering.l4` and its `expected/` goldens.
- **`openfisca-export`** — hard dependency for all 14 `l4 openfisca` blocks, which compare stdout against `jl4/examples/openfisca/expected/*.py`.
- **`corpus-regcf`** — hard dependency for the two `l4 nlg` golden comparisons (`examples/legal/regcf/tests/regcf{,-wizard}.nlg.golden`) and for the corpus engine leg.
- **`lsp`** and **`lang-imports-stdlib`** — behavioural dependency. The nine library-shadow blocks assert the B′ precedence order and the exact wording of the shadow warning (`[chosen]   project root`, ``Multiple differing copies of module `daydate` ``), which are produced by the resolver in `jl4-lsp/src/LSP/L4/Rules.hs`.
- **`ci-build`** — not needed to compile or run, but it owns `.github/workflows/pr-checks.yml`, where the `dmn-engines` job runs the two harness scripts directly with `*_CHECK_REQUIRED` set. `Main.hs` documents in situ that CI does **not** invoke `l4-cli-test` for the engine legs; the suite is the developer-facing entry point and the job is the gate.

What it does **not** need: any change to `jl4/jl4.cabal`'s `test-suite l4-cli-test` stanza (verified byte-identical between `main` and `unstable`), and nothing from `ladder-viz`, `mlir`, `proleg`, `papers`, `wizard-*` or the spec/docs themes.

Ordering advice: land `service-cli`, `dmn-export`, `bpmn-export`, `openfisca-export` and `corpus-regcf` first; this PR is a natural late merge.

## Risk if rejected

The `l4` binary keeps shipping four subcommands (`export`, `nlg`, `verify`, `openfisca`) with no black-box test at all, and the DMN work loses its only single-command route to a real engine — the 46 BKM/service probe legs, the XSD sequence-order gate, the date-arithmetic clamp equivalence and the null-semantics divergence all become uncommitted measurements, which this repo's own history treats as indistinguishable from measurements never taken. The library-resolution regressions (#906 and the poisoned-XDG incident) also lose their guard, in the exact regime — no `JL4_LIBRARY_PATH`, entry file named bare — that CI otherwise hides.

## Provenance

Unstable PRs folded into this one:

- #134 — library resolution: embedded stdlib outranks ambient XDG/bundle copies (B′)
- #154 — `l4 export` CLI (S0) + `jl4-service` `/ladder` (S1)
- #160 — two DMN engine flavors (R7), both engines checking answers not just liveness
- #175 — itemDefinitions for records and enums (DMN export Phase 3)
- #176 — engine-intersection triple: BKM is the only portable tabular predicate
- #178 — law time on a date axis: rule-date input, UNIQUE interval tables, D-RULEDATE
- #180 — hydration for computed fields + MAYBE→null (R8-d′)
- #181 — DMN Phase 5 groundwork: the 23 BKM engine probes + build plan
- #183 — DMN Phase 4: un-lifting analysis + totality + R6 population filter
- #188 — DMN Phase 5: BKM emission
- #189 — merge `main` into `unstable`
- #194 — R12/R13: the Reg CF corpus executes on both engines
- #206 — three exporter defects closed with failing negative controls (#936, #933, #937)
- #207 — `l4 verify` + `l4 nlg`, the two CLI footings P8 and P7-TNR were missing
- #224 — the explainer stage, a BPMN renderer, and the de novo Reg CF run
