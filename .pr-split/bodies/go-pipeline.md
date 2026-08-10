# feat(go): the "⟨body of law⟩: go" pipeline orchestrator — driver, phase legs, deposit contracts, §8 diff oracle, explainer

**What this adds**

A single-instruction pipeline that takes one body of law from its source text through an L4 encoding and out to every projection, gate and report the repo can produce — driven by `etc/go/go.sh`, with a companion Claude skill (`.claude/skills/running-the-l4-pipeline/`) that supplies the judgements no script can make. Before this, running the demo meant a human invoking `l4 export`, `l4 run`, the DMN engine harnesses, the BPMN checkers and the ladder demo by hand, and then writing down what happened; the numbers lived in a PR body and nowhere else. After this, `etc/go/go.sh run --milestone g1 --subject regcf` drives the declared stages, writes one receipt per stage into a hash-chained `journal.ndjson`, and renders two documents from that journal and nothing else — an audit-facing `report.md` and a reader-facing `explainer.html`. The governing invariant is one sentence: **a status is a function of bytes on disk, not of an agent's assertion.** `etc/go/lib/receipt.mjs` is the only writer of the journal and refuses (exit 4) a receipt whose status is nicer than its evidence, so an agent that wants to claim a leg passed has no API for doing it — it can run the phase script; the phase script writes the row.

**Why**

The demo pipeline had a specification (`specs/todo/single-instruction-demo/SPEC.md`) and no implementation: PR #193 records that its §5 component table listed the orchestrator as "**does not exist** — this spec is its birth certificate". Everything the pipeline was supposed to prove was being proved once, by hand, into prose that then drifted — the same failure mode CLAUDE.md §4 exists to prevent. The pipeline also needed somewhere to put a status vocabulary that cannot quietly collapse to pass/fail: a projection that reproduces its golden but that no engine can execute is not the same thing as a projection that runs, and the tree had no way to say so. The de novo half (milestone G2) was blocked on ruling **R4** until PR #197, and the §8 acceptance comparator it needs did not exist at all.

---

## What's in it

89 files, all new — `git diff --stat origin/main...origin/unstable` over this theme's paths reports **20223 insertions, 0 deletions**. By kind: **27 shell scripts, 27 `.mjs` modules, 30 markdown files, 5 JSON descriptors**.

### The driver and its libraries (`etc/go/`)

- **`go.sh`** (936 lines) — `run` / `plan` / `status` / `verify` / `gc` / `help`, with `--milestone g1|g2`, `--subject`, `--through`, `--only`, `--waive`, `--fixed-now`. Exit codes extend `etc/check-bpmn-kie.sh`'s: `0` clean, `1` a finding, `2` usage, `3` a human gate is unsatisfied, `4` broken (a harness defect, never a finding about the corpus), `5` a stage was `SKIPPED` under `L4_GO_REQUIRED=1`.
- **22 phase scripts** under `phases/` covering P0–P10, plus `lib/phase-prelude.sh` and `lib/deposit-prelude.sh`.
- **22 library modules** under `lib/`: `receipt.mjs` (the sole journal writer), `verdict.mjs` (the status lattice and the five oracle classes), `verify-run.mjs` (chain and artifact re-verification), `subject.mjs` (sidecar resolution and validation), `ledger.mjs`, `digest.mjs`, `gate-payload.mjs`, `discover.mjs`, `probe.mjs`, `known-defects.mjs`, `canon-diff.mjs`, `label-order.mjs`, `dmn-tables.mjs`, `fidelity-counts.mjs`, `narrative.mjs`, `narrative-provenance.mjs`, `plan-shape.mjs`, `split-digraphs.mjs`, `assert-report.mjs` and its selftest, `register-validate.mjs`, `denovo-diff.mjs`.
- **Gates.** `gate-request.sh` / `gate-verify.sh` implement HG1 and HG2 as **detached SSH signatures over a payload derived from the journal**, so approval binds to content and a post-gate edit re-opens the gate. There is no `--skip-gate`; `gate-allowed-signers` ships with no enrolled key, so the only route today is `--waive HG1="reason"`, which lands as a gate record and prints in the report. `--waive HG2` exits 2.
- **Selftests.** `selftest.mjs` (3569 lines) and `lib/assert-report.selftest.mjs`, plus `check-skill-drift.mjs`, which compares the skill's command table against the driver's in both directions.
- **`README.md`** (323 lines) — usage, the subject-sidecar contract, environment variables, exit codes, how to get prebuilt `l4`/`jl4-lsp` binaries without taking the build lock, and a "Common errors" section keyed by the exact message.

### The two rendered documents (`etc/go/report/`)

`render-report.mjs` builds the audit account from `journal.ndjson` and nothing else — its template may not contain a two-digit number, every figure is a placeholder resolved from a journal row. `render-explainer.mjs` (1489 lines) plus `md-lite.mjs` build the reader-facing sibling: run facts are journal placeholders, and every *other* number must be a placeholder or a citation of the form `[$5,000,000](src:path#L151)` whose source line the renderer re-opens and matches before printing. A citation that does not resolve prints the figure followed by a visible complaint and degrades the stage.

### The subject sidecar (`etc/go/subjects/regcf/`)

The driver and libraries are subject-generic; everything the pipeline knows about one body of law is a sidecar. Reg CF's is `subject.json` (corpus module paths, per-origin check floors, the `legs` declaration, the optional `denovo` deposit paths), `pins.json` (the CLI surface the stage table depends on, measured), `known-defects.json` (measured defects used as negative controls — a defect that stops reproducing is exit 4), `NOTES.md`, and the checked-in `explainer/` narrative: `manifest.json` (the document spine), `provenance.json` (per file: its digest, who drafted it, the sources it was drafted from with their digests, and its review state) and 22 markdown parts.

### The skill (`.claude/skills/running-the-l4-pipeline/`)

`SKILL.md` plus three references (`phases.md`, `status-vocabulary.md`, `gates.md`). The division of labour is the design: **scripts own every fact; the skill owns every judgement.** Scripts never call a model; the skill never writes a status, may not append to the hash-chained journal, and is barred from retry-until-green.

### Two things worth reviewing on their own

- **`lib/register-validate.mjs`** (1123 lines) — one validator for the three G2 deposit contracts (source bundle, external modifications, fork register). `additionalProperties: false`, every absence carries a reason, 48 cross-field `x-rules` with declared↔implemented id sets compared in both directions, and a keyword-subset audit so an unimplemented schema keyword is exit 2 rather than a silent partial pass. A cross-file rule whose peer file is absent prints `skip` with a reason; it never passes quietly.
- **`lib/denovo-diff.mjs`** (1508 lines) — SPEC.md §8's acceptance comparator. Two encodings of one body of law share no identifiers, so a textual diff is 100% different and 0% informative; this compares them by **what they answer**. It seeds a battery from the subject's cases file, perturbs one field at a time, evaluates both sides through a generated probe module, and reports minimised witnesses. It **never triages** — every witness reads `UNTRIAGED`, because §8's three dispositions are judgements. Its **Sensitivity** table is the part to read: a (pair, fact) leaf the battery perturbed without ever moving an answer is a surface on which agreement is silence rather than evidence.

---

## Evidence

All figures below are quoted from the source PRs' own bodies.

**G1 (replay of the committed corpus).** PR #193 reports thirteen declared stages, of which four PASS, and `go.sh verify --gates` over the same run directory: "journal chain verifies (29 records), 41 artifacts recorded and 41 still hash as recorded, `VERDICT: COMPLETE`". Four of thirteen PASS is stated there as "the honest count and … the intended shape": `G1 COMPLETE` is completeness of accounting, not greenness. PR #207 reports a later full G1 run, `2026-08-02-1733c452-005`: "thirteen declared legs unperturbed, hash chain verifies, 51/51 artifacts still hash as recorded, `VERDICT: g1 COMPLETE`", with `p7-tnr` **PASS**/differential and `p8-verify` **PASS**/structural newly among them.

**`p7-dmn` reaching execution.** PR #204: "**PASS**/`execution` — KIE 8.44.0.Final and Camunda 8.7.6 both **1072/1072**, 224/224 service outputs". PR #205 re-reports the same pins character-for-character after the field renames.

**The §8 diff oracle.** PR #197's identity run, verbatim: `6800 evaluation(s) over 2944 row(s) × 13 pair(s) — 6800 agreed · 0 diverged`. Three independent one-constant perturbations "each localizes to exactly the consuming decision pairs, witnesses inside the opened interval, everything else 0". PR #197 also reports the adversarial finding that earned the sensitivity accounting: a fourth perturbation "came back `6800 agreed · 0 diverged` — every word true, the impression false: no battery value ever crossed the threshold", fixed with per-(pair, fact) sensitivity accounting reporting `25 of 64 (pair, fact) leaves inert`. PR #205 exercises the oracle as a neutrality proof over a rename, verbatim: run 2 `9036 evaluation(s) over 3922 row(s) × 13 pair(s) / 9036 agreed · 0 diverged · 0 minimised witness(es) / 21 of 64 (pair, fact) leaves inert`, and a negative control moving one constant on the right-hand side `8960 agreed · 76 diverged · 2 minimised witness(es)`, exit 1 — "The comparator is sensitive; runs 1 and 2 are evidence."

**The G2 deposit stages.** PR #204: `etc/go/selftest.mjs` **144 ok, 0 fail** (1 skipped — the driver-driven idempotence check); `check-skill-drift.mjs` green; g2 with no deposits gives "five honest `SKIPPED` + `p9-report` PASS → `g2 COMPLETE`", the same run under `L4_GO_REQUIRED=1` gives **exit 5**, a valid deposit trio gives "`p1 p2 p4 p5` all **PASS**, 48 rules, **0 joins skipped**", and an adversarial trio gives "all four **DEGRADED**, each naming its own rules".

**G2 measuring the deposited encoding.** PR #226, from a fresh post-repair run, independently reproduced: `p3-check` PASS with `module_origin=denovo`, dated arms 0/floor 0 → "**`temporal closure: NOT CHECKED`** on the receipt, not a vacuous green"; `p6-tests` PASS/execution with `assertions_total=39` against `denovo.checks.min_assertions=39`; `p7-dmn` **DEGRADED** because "both engines refuse the artifact: KIE 'Compiled model is null!', Camunda **26 verbatim FEEL parse errors**"; `p8-verify` **DEGRADED** with "5/5 controls reproduce; 253 decisions, 114 analysed, **2 `vacuous-guard` findings**"; `p8-diff` PASS/structural with "**80/80 agreed** over 4 pairs × 20 rows, 0 untriaged", density "replay **0.43** vs de novo **0.08**". Verdict: "**g2 COMPLETE, exit 0** — the two DEGRADED rows are true findings about the deposit and the exporter, reported, never retried."

**`l4 verify` on the committed corpus.** PR #207: "`regcf.l4` 102 decisions / 42 analysed / 60 skipped / **0 findings**; `regcf-wizard.l4` 52 / 1 / 51 / **0**", bounded by three measurements in the same PR — 25 of the 42 analysed decisions have exactly one atom, `merged_atom_occurrences = 0`, and "111 of 154 decisions are skipped as non-`BOOLEAN`. Counted and named in the artifact, never folded into 'clean'."

**The label-order lint.** PR #208: "`regcf` + wizard 21 labels / 0 warnings / 0 gaps; `bna` 18 / 0 / 0; `charities` 38 / 0 / 0", and all **77** label-only sites across four corpora on-shape — "**73** operand-joined … and **4** leading … **0** off-shape", with six negative controls in `selftest.mjs`. PR #208 also reports `etc/go/selftest.mjs` at "144 checks, all pass (3 environmental skips)".

**CI.** PR #193 reports that the new **Go Orchestrator** job "passes on CI in 8s", and that the `go:` paths filter it added was load-bearing because `.claude/**` previously matched no filter at all, so a skill-only PR ran zero jobs. (The workflow file itself is not in this PR — see Independence.)

**Adversarial findings.** PR #193 reports "Twenty defects, each reproduced before it was touched and re-verified after. Six let a status be wrong". Among them: the MCP leg read the tool list with a GET that `jl4-service` answers 405 by design, so the leg fell through to a zero-tool branch and its documented `execution` PASS "was unreachable in all three" places it was claimed; the loopback fence was bypassable with URL userinfo (`http://127.0.0.1:8080@REALHOST/`); no stage digested the `l4` binary, so a resumed run replayed every leg without invoking it — "Measured with a stub that exits 1 on every call: thirteen `replayed` lines, `VERDICT: g1 COMPLETE`, exit 0". PR #226 reports the same class caught again after green suites: floors that were not in `--inputs` (so editing a floor and resuming replayed the old PASS), a vacuous PASS over `assertions_total=0`, and "an ungated 127 KB artifact" — g2 runs rendering the committed-corpus explainer with no receipt and outside the HG1 digest.

---

## Independence

**This PR is not standalone.** It merges cleanly on its own — all 89 files are new, so there is nothing to conflict with — but the pipeline it installs is a harness over other themes' artifacts, and several of those are hard runtime dependencies rather than nice-to-haves:

- **`specs`** — `lib/register-validate.mjs:47` resolves its three schemas out of `specs/todo/single-instruction-demo/schemas/`, and `gate-verify.sh:50` reads `specs/todo/single-instruction-demo/gate-allowed-signers`. Without that theme the deposit validator and the gate verifier have nothing to read. The specs that the scripts cite as authoritative — `ORCHESTRATOR.md`, `SPEC.md`, `DENOVO-DIFF-ORACLE.md`, `EXPLAINER-REPORT-SPEC.md` — also live there.
- **`service-cli`** — `p8-verify.sh` invokes `l4 verify` and `p7-tnr.sh` invokes `l4 nlg`. Both subcommands are Haskell (`jl4/app/L4/Cli/Verify.hs`, `jl4/app/L4/Cli/Nlg.hs`) and are carried by that theme. Without them those two legs cannot run.
- **`tests-cli`** — `p8-verify.sh` reproduces five committed control fixtures (`jl4/tests-cli/fixtures/verify-{clean,unsat,dead-branch,vacuous-guard,seam}.l4`) before it will report anything; a control that does not reproduce makes the leg `BROKEN`.
- **`corpus-regcf`** — `subject.json` names `jl4/examples/legal/regcf/regcf.l4`, `regcf-wizard.l4` and the five de novo deposits under `jl4/examples/legal/regcf/denovo/`. `lib/subject.mjs` treats a leg entry naming a missing file as a hard error, so the sidecar as committed resolves only once those files exist.
- **`dmn-export`, `bpmn-export`, `ladder-viz`** — the `legs` object names their goldens and demo entry point (`jl4/examples/dmn/expected/regcf-corpus.dmn`, `jl4/examples/dmn/regcf-corpus.cases.json`, `jl4/examples/bpmn/expected/`, `ts-shared/ladder-svg` `demo:regcf`). Those legs are declared members of the milestone, so their goldens are not optional to a `COMPLETE` verdict.
- **`ci-build`** — the `go:` paths filter and the `Go Orchestrator` job live in `.github/workflows/pr-checks.yml`, which that theme carries. Landing this PR without it means `etc/go/**` and `.claude/**` changes still match no filter and run no job, which is exactly the hole PR #193 opened the filter to close.

**What it does not need.** No Haskell and no TypeScript source is touched here, and the orchestrator never runs `cabal` by design — the build lock is a shared resource and concurrent invocations in one worktree corrupt each other. Every missing tool produces a `SKIPPED` receipt naming what is missing and what it was needed for (`JL4_LSP_CMD` absent ⇒ the ladder leg skips; no loopback `jl4-service` ⇒ the MCP leg skips), so the pipeline degrades to honest accounting rather than to failure when a sibling is not present.

**Reviewer note, measured on this branch:** `etc/go/lib/discover.mjs` carries **2 literal NUL bytes** (used as a join separator), so git classifies it as binary — `git diff --stat` reports it as `Bin 0 -> 6339 bytes`, with no line diff, no blame and no three-way merge. This is the same defect PR #208 found and repaired in `lib/label-order.mjs`; the repair was not applied to `discover.mjs`. Worth fixing in review by writing the separator as an escape sequence — same bytes at runtime, reviewable file.

---

## Risk if rejected

Every sibling theme keeps its own tests, but the repo loses the only thing that re-derives their evidence together: the hash-chained journal, the artifact re-hashing, the status lattice that forbids a cheap oracle from licensing a PASS, and the two documents rendered from that journal rather than transcribed. `l4 verify` and `l4 nlg` lose their only caller outside the test suite, the three de novo deposit schemas in `specs/` lose their only validator, and the de novo Reg CF encoding in `corpus-regcf` loses the §8 comparator that is its acceptance condition — leaving it a committed artifact with no oracle pointed at it.

---

## Provenance

Unstable PRs folded into this one:

- **#193** — `mengwong/go-orchestrator` — the orchestrator, the skill, the CI job, milestone G1
- **#197** — `mengwong/denovo-foundations` — three deposit schemas + validator, and the §8 diff oracle
- **#204** — `mengwong/denovo-harnesses` — the five de novo stages stop refusing and validate a deposit
- **#205** — `mengwong/clitic-corpus-fix` — the diff oracle used as a rename-neutrality proof; a stale selftest pin repaired
- **#206** — `mengwong/exporter-fixes` — sidecar `NOTES.md` re-measured against the 20-case file
- **#207** — `mengwong/cli-footings` — `p7-tnr` regenerates instead of hashing itself; `p8-verify` gets its CLI footing
- **#208** — `mengwong/inert-label-truncation` — the `label-order.mjs` lint with its six negative controls
- **#224** — `mengwong/go-explainer` — `p9-explain`, `render-explainer.mjs`, the narrative libraries, and the checked-in Reg CF explainer
- **#226** — `mengwong/g2-wiring` — per-origin floors, module rebinding, `p8-diff`, `p8-verify` declared at both milestones, emit-only `p7-dmn` at g2
