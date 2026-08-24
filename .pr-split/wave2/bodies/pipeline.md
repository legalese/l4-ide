# feat(go): pipeline hardening from the second subject, and the artifact store with the blessing edge (R6 + R11)

**48 files, +9,606/−2,755.** This PR is the pipeline-infrastructure half of wave 2: what
running a second subject (sg-succession) through `etc/go` shook loose, plus the artifact
store and blessing edge that landed as upstream #281 on top of those repairs.

## What this adds

**From #274 — the pipeline made subject-generic in practice, not just in principle:**

- `etc/go/lib/` gains `subject.mjs`, `discover.mjs`, `new-subject.mjs`, `gc-subjects.mjs`,
  `stdlib-digest.mjs`, `corpus-metrics.mjs`, `known-defects.mjs`, `gate-payload.mjs` —
  the subject-resolution layer that stops a second subject answering for the first
  (`go.sh status --subject regcf` once resolved to sg-succession's newer run).
- 14 phase scripts under `etc/go/phases/` updated for subject-parameterisation.
- `etc/go/subjects/` — the subject registry: `regcf/subject.json` migrated to the new
  schema, `sg-succession/{subject.json,pins.json,known-defects.json,NOTES.md}` added.
- **CI wiring**: `.github/workflows/pr-checks.yml` plus two new gates —
  `etc/check-subject-ci-coverage.mjs` (every registered subject must have CI coverage;
  fails naming the exact missing entry) and `etc/check-not-precedence.mjs` (guards the
  stdlib NOT-precedence class of bug found during encoding).

**From #281 — the artifact store (rulings R6 + R11 of the artifact-model spec):**

- `etc/go/lib/store.mjs`, `store-cli.mjs`, `verdict.mjs`, `receipt.mjs`, `ledger.mjs` —
  content-addressed run artifacts with receipts, and the **blessing edge**: a human gate's
  grant is recorded against the exact artifact digest it blessed, so a later re-run cannot
  silently inherit a blessing for different content.
- `etc/go/gate-verify.sh`, `etc/go/lib/phase-prelude.sh` — the enforcement seam every
  phase sources.
- `etc/go/selftest.mjs` grown accordingly (it fabricates its own fixtures; it does not
  read any real corpus).
- The skill (`.claude/skills/running-the-l4-pipeline/`) and
  `specs/todo/PIPELINE-ARTIFACT-MODEL-SPEC.md` updated in lockstep — `check-skill-drift.mjs`
  compares skill and driver in both directions.
- `specs/todo/single-instruction-demo/{SPEC,ORCHESTRATOR}.md` — the programme record.

## Why one PR

`selftest.mjs`, `go.sh` and the skill each carry both layers (#274's repairs, then #281's
store on top of them) in single files; splitting them would leave each half red in opposite
directions. All `etc/go` content in wave 2 therefore reviews as one unit. The sg-succession
*corpus* that motivated the repairs is its own sibling PR.

## Evidence

- `node etc/go/selftest.mjs` is run by CI's go-orchestrator job; the selftest is
  self-contained (synthetic fixtures, no corpus reads).
- Every line here reached `unstable` through the sequential merge queue (#281 cleared it
  minutes before the wave-2 cut), and the push-triggered full-matrix run at `bf355e79`
  **completed green** (24 Aug, after this PR opened).

## Independence

- The **CI wiring is gate-ahead-of-code by design**, as wave 1's ci-build PR (#233)
  established: `pr-checks.yml` here knows about the sg-succession subject, whose corpus is
  a sibling PR. If a subject-coverage job runs on this slice without the corpus present,
  that is expected red, documented here once.
- Nothing else in wave 2 depends on this PR.

## Provenance

Upstream `unstable` PRs folded in: #274 (pipeline files only; the corpus is the
sg-succession sibling, the stdlib/service fixes are in repairs), #281 (the artifact store
and blessing edge, R6 + R11).
