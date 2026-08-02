# The `go` Orchestrator

**Status (2026-08-02): PARTIALLY IMPLEMENTED — milestone G1 runs; G2 and everything downstream of
it does not.** Written against `legalese/l4-ide` branch `mengwong/go-orchestrator`, cut from
`origin/unstable` at `162e5070`, and verified by running it on this worktree.

What that means precisely, in the present tense:

- **`etc/go/go.sh run --milestone g1 --subject regcf` runs end to end today.** It drives the
  committed Reg CF corpus through every reachable projection, records a receipt per stage, and
  emits conversion report v0. It refuses at HG1 unless a signature verifies or a waiver is
  recorded. The subject is resolved from a per-subject sidecar (§2.3), so the driver and phase
  scripts carry no Reg CF facts of their own.
- **Seven stages are scaffolded and cannot run**: `p1-ingest`, `p2-sweep`, `p3-encode`,
  `p4-forks`, `p5-gate`, `p8-verify`, `p10-publish`. Each is an entry point that prints what it
  would do and what is blocking it, then exits 3. Since R4 was ruled (2026-08-02) the
  encode/fork stages are blocked on engineering — the tooling is unbuilt — while `p8-verify`
  (R5) and `p10-publish` (R1/R2) still wait on open rulings. §5 names each blocker.
- **Milestone G2 is unbuilt.** `go.sh plan --milestone g2` refuses and says why: R4 is ruled
  but none of the de novo tooling it unblocks exists yet. The §8 diff oracle does not exist
  either.
- **This document owns the orchestrator's own decisions.** The pipeline it serves is
  [SPEC.md](./SPEC.md); per-projection rulings stay in their own specs. Where this document
  disagrees with the tree, **the tree wins**.

---

## 0. What exists as of this commit

```
etc/go/
├── go.sh                        the only entry point; dispatch, gates, resumability
├── selftest.mjs                 proof the lattice can still refuse
├── check-skill-drift.mjs        the skill's command set vs go.sh's dispatch table
├── gate-request.sh              prints the payload a human signs
├── gate-verify.sh               ssh-keygen -Y verify; the default-deny check
├── README.md                    usage, exit codes, environment, common errors
├── subjects/                    one sidecar directory per body of law (§2.3)
│   └── regcf/                   subject.json · pins.json · known-defects.json ·
│                                NOTES.md
├── lib/                         verdict · ledger · receipt · probe · digest ·
│                                discover · subject · canon-diff ·
│                                assert-report (+selftest) · fidelity-counts ·
│                                plan-shape · split-digraphs · known-defects ·
│                                gate-payload · verify-run · phase-prelude.sh
├── phases/                      p0 p3-check p6 p7×9 p9  (run) ·
│                                p1 p2 p3-encode p4 p5 p8 p10  (refuse)
└── report/                      render-report.mjs + template.md

.claude/skills/running-the-l4-pipeline/
├── SKILL.md
└── references/                  phases.md · status-vocabulary.md · gates.md

specs/todo/single-instruction-demo/
├── ORCHESTRATOR.md              this file
└── gate-allowed-signers         ssh allowed_signers — SHIPS WITH NO KEY, deliberately
```

CI runs it: `.github/workflows/pr-checks.yml` gains a `go:` paths filter over `etc/go/**`,
`.claude/skills/running-the-l4-pipeline/**` and `specs/todo/single-instruction-demo/**`, and a
`Go Orchestrator` job. That filter is load-bearing — `.claude/**` matched **no** existing filter,
so a skill-only PR previously ran zero jobs.

---

## 1. Measured results — one G1 run on this worktree

Run id `<UTC-date>-97b15013-002` (the digest names the corpus), subject `regcf`, HG1 waived, clock pinned to
`2025-01-31T00:00:00Z`. Measured twice: first on this branch's own tree, then re-measured
2026-08-02 after merging `origin/unstable` at `8d84c797` — which carries PR #194, the change that
made the corpus DMN executable — into this branch. The table shows the re-measurement; exactly one
row moved (`p7-dmn`, `NOT-EXECUTABLE` → `PASS`, §5.4). Every figure below is a `metrics` value on a `stage_end` row of
`journal.ndjson`; none was typed. That was not true when this table was first written: the nine
`ELSE IF` sites lived only in `artifacts/p3-check.txt`, which the journal names by path and sha256
— and a sha256 is not invertible, so the one bare figure in the table was the one figure nobody
could get back out of the journal it was said to come from. `p3-check` now records
`else_if_sites`, `dated_arms` and `min_dated_arms` as metrics.

| stage          | status              | oracle class | why                                                                                                                                                                                                                                                                                          |
| -------------- | ------------------- | ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `p0-preflight` | PASS                | structural   | CLI enumerations and the module's regulative-rule names match the subject's `pins.json` as sets; every checker in the pin exists; the failing-`#ASSERT` tripwire still exits 0                                                                                                               |
| `p3-check`     | DEGRADED            | —            | both modules typecheck and all 2 matched dated arms carry an `@ref` (floor: 2); nine `ELSE IF` sites remain against P3's BRANCH-over-`ELSE IF` house rule                                                                                                                                    |
| `p6-tests`     | PASS                | execution    | the corpus's own `#ASSERT` directives all hold, read out of `results[]`                                                                                                                                                                                                                      |
| `p7-dmn`       | **PASS**            | execution    | executed by both engines over the committed 16-case file: KIE `1072/1072 value(s) as expected, 224/224 service output value(s) as expected`, Camunda `1072/1072 value(s) as expected`; fidelity 0 blocking / 21 lossy / 125 advisory; golden reproduced modulo the D1 canonicalisation       |
| `p7-dmn-md`    | DEGRADED            | —            | reproduces the golden; lossy by construction, and no engine executes markdown                                                                                                                                                                                                                |
| `p7-bpmn`      | DEGRADED            | —            | all three processes reproduce their goldens and pass soundness + interchange; the mandated BPMN→DMN wiring was not built at measurement time (since BUILT on PR #198, open — vendor-neutral businessRuleTask + name-matching resolver; this row re-measures when it lands under this branch) |
| `p7-ladder`    | SKIPPED             | —            | `JL4_LSP_CMD` unset, or `tsx` not installed in the checkout                                                                                                                                                                                                                                  |
| `p7-lts`       | PASS (INTERIM)      | structural   | `digraph` count equals the regulative-rule count the BPMN discovery call independently reports                                                                                                                                                                                               |
| `p7-mcp`       | SKIPPED             | —            | zip built and hashed; no loopback `jl4-service` configured. With one — measured 2026-08-02 against a prebuilt service on `127.0.0.1:18099` — this leg reaches `PASS`/`execution`: 6 corpus tools, matching the 6 functions the deployment reports                                            |
| `p7-tnr`       | **NOT-REGENERATED** | —            | no `l4` subcommand emits NLG; the goldens come from `cabal test`                                                                                                                                                                                                                             |
| `p7-wizard`    | DEGRADED            | —            | the plan is well formed and is not the interview query plan                                                                                                                                                                                                                                  |
| `p7-akn`       | UNVERIFIED (EXTRA)  | —            | Akoma Ntoso emitted; well-formedness is the only oracle and it cannot license PASS                                                                                                                                                                                                           |
| `p9-report`    | PASS                | structural   | every section SPEC.md §P9 requires is present                                                                                                                                                                                                                                                |
| **milestone**  | **G1 COMPLETE**     |              |                                                                                                                                                                                                                                                                                              |

Five of the thirteen are `PASS` — four as first measured, plus `p7-dmn`, which flipped from
`NOT-EXECUTABLE` when PR #194 landed the corpus cases file (§5.4). `G1 COMPLETE` with the other
eight non-green is the intended outcome, not a lowered bar — see §3.

### 1.1 Three defects this build measured, which are findings in their own right

**D1 — the DMN golden is not reproducible from the command line, and three places in the tree say
it is.** Both files are 3,248 lines, and `l4 export regcf.l4 --to dmn` differs from
`jl4/examples/dmn/expected/regcf-corpus.dmn` on **23** of them, every one of the form
`main.l4:<position>` in the golden against `regcf.l4:<position>` from the CLI. Cause:
`jl4/tests/DmnExport.hs:3212` — `drgFlavoredWith = drgGeneral emptyVFS id` — typechecks goldens
against an empty virtual file system, so no source URI reaches the `@ref` renderer and provenance
renders a placeholder.

(An earlier draft of this section said 92. `diff … | wc -l` is 92 because each of the 23 changed
lines produces four lines of diff output — `NNcNN`, `<`, `---`, `>`. `etc/go/lib/canon-diff.mjs`
records the 92 correctly, with its `wc -l` framing intact; this prose dropped the framing and
turned a diff-output-line count into a differing-line count that was 4× too large. Only artifact 1
is affected: a bare `--to dmn-md` and three bare `--to bpmn --rule …` all diff clean.)

Three claims are therefore false as written:

- `jl4/examples/legal/regcf/PROJECTIONS.md` §0 — "Every one of 1–3 reproduces byte for byte from
  the command line with no flags other than `--rule`";
- `jl4/examples/legal/regcf/PROJECTIONS.md` §6, under **Not a defect** — "the goldens now reproduce
  with **no flag at all**". This one is the dangerous shape: a retraction was written at the top of
  the file while the same file's triage section, further down, still carried the adjudication that
  the finding was not a defect — and a settled-looking adjudication is the more persuasive of two
  contradictory sentences. Retracted in place, under a new **Retracted** heading rather than
  deleted, so the reversal is on the record;
- `jl4/tests/DmnExport.hs:3157` — "Keeping this in step with `L4.Cli.Export.exportDmn` is what
  makes every DMN golden reproducible from the command line".

The orchestrator does **not** work around this by regenerating the golden — that would silently
rewrite the artifact `jl4-test` defends. It canonicalises, and the canonicalisation carries a
`because` naming that file:line and a `delete_when` naming the condition for its own removal.
Fixing the golden runner and retracting the two claims is the natural companion PR; it is not in
this change, because it touches Haskell and this branch does not build.

**D2 — PROJECTIONS.md stated a fidelity heading, a per-code table and two line counts that its own
artifacts contradicted.** Measured 2026-08-02 on the pre-#194 tree — after PR #194 the corpus
fidelity is 0 / 21 / 125, and the merge of `unstable` into this branch resolved PROJECTIONS.md to
that state; the figures below are the history of the repair, not current values. As measured then:
the fidelity report held 95 blocking / 21 lossy / 54 advisory while §"Fidelity" said 114 / 46 / 18; the per-code table said `D-LITERALEXPR` 89 /
`D-RENAME` 37 against an actual 80 / 11; and `regcf.l4` was given as 992 lines in the opening
sentence and 1,241 lines in §2, against an actual 1,236 (SPEC.md §5 repeated the 1,241).

**The first repair of the table was itself wrong, and that is the more instructive half.** Fixing
the heading and two rows left the table summing to 105 / 20 / 18 against its own corrected heading
of 95 / 21 / 54, still carrying two codes the exporter does not emit (`D-NONFEELINPUT`,
`D-NONFEELOUTPUT`, zero occurrences each) and omitting seven it does (`D-BKM` ×10,
`D-PARAM-AS-INPUT` ×10, `D-FIXTURE` ×7, `D-INERT` ×4, `D-REGULATIVE` ×2, `D-COMPUTEDFIELD` ×1,
`D-PARTIAL` ×1); the dmnmd table summed to 120 against a report of 121, omitting `D-MD-NOCONTEXT`.
Correcting the _cited_ figures and not re-deriving the _whole_ table is how a repaired document
stays wrong. Both tables are now the complete emitted set, and each column sums to its heading —
which is the arithmetic that catches the next stale row. Repaired in §9 below.

Deliberately not quantified: an earlier version of this entry, and three enforcement sites that
copied it, each gave a different COUNT of the stale figures (three, three, eleven). The count is
not the fact and it drifts every time the document is repaired; the shape — a heading, a table and
two line counts that disagreed with the artifacts they described — does not.

**D3 — `etc/check-bpmn-kie-baseline.mjs` cannot be a subset oracle.** Its baseline covers the
whole committed BPMN corpus, so a three-file Reg CF run reports the other three as `NOT CHECKED`
and exits 1. Measured. The BPMN leg therefore establishes byte-identity with the committed
goldens and lets CI's verdict over those goldens apply transitively, rather than pretending the
comparator answers a question it was not asked.

---

## 2. The governing invariant

**A status is a function of bytes on disk, not of an agent's assertion.**

One consequence drives the whole layout: the only code that may write a status is a script with
an exit code, and it may write `PASS` only when it can name an oracle that returned 0 over a file
whose sha256 it recorded.

The corollary is the honesty property. An agent that wants to claim a leg passed **has no API for
doing so**. It can run the phase script; the phase script writes the row. `etc/go/lib/receipt.mjs`
is the only writer of `journal.ndjson`, and it refuses — exit 4 — a receipt whose status its
evidence does not support.

### 2.1 The skill / script boundary

Scripts own every fact. The skill owns every judgement. Scripts never call a model; the skill
never writes a status.

| in `etc/go/`                                                | in `.claude/skills/running-the-l4-pipeline/`                           |
| ----------------------------------------------------------- | ---------------------------------------------------------------------- |
| every `l4` / `etc/*.mjs` / `npm` invocation and its argv    | which model runs which phase (SPEC.md §7.1)                            |
| exit-code interpretation, including the `l4 run` workaround | the P5 adversarial checklist, P4 fork discovery, §8 triage             |
| sha256 and byte count of every input and output             | how to write a note, and that a note renders as _claimed, unverified_  |
| toolchain probing → `SKIPPED(named reason)`                 | what to do on `DEGRADED`: record and continue, never retry-until-green |
| the milestone verdict                                       | mapping the instruction to `go.sh --milestone g1 --subject regcf`      |
| the hash-chained journal and the report                     | escalation text for `BROKEN` and for a refused gate                    |

The line sits there because SPEC.md §7.2 asks for control flow that is _deterministic_ and
_resumable after interruption_, and only the half that survives context loss can carry either. A
prompt cannot be resumed; a receipt can.

### 2.2 G1 requires zero model calls

Every G1 stage is deterministic: a binary is invoked, an oracle runs, a receipt is written. This
is the largest simplification in the design and the first thing a later reader will be tempted to
undo, so it is written down here as well as in the skill.

### 2.3 The subject sidecar

A second boundary, orthogonal to skill/script: **the pipeline owns every mechanism; the subject
sidecar owns every fact about one body of law.** The driver, libraries and phase scripts contain
no subject literals; everything subject-specific lives in `etc/go/subjects/<id>/`, four files:

- **`subject.json`** — the machine-readable descriptor: id, display name, legal citation, source
  entry URL, corpus module paths (`corpus.main`, optional `corpus.wizard`), per-subject check
  floors (`checks.min_dated_arms`, `checks.min_assertions` — these are _measurements_ of the
  corpus, which is why they cannot be pipeline constants), and a `legs` object carrying one entry
  per projection leg with its committed golden/cases/aux paths.
- **`pins.json`** — the CLI surface the stage table reads, measured against that subject's corpus
  (formerly `etc/go/PINS.json`).
- **`known-defects.json`** — measured defects used as negative controls (formerly
  `etc/go/known-defects.json`).
- **`NOTES.md`** — free-prose idiosyncrasies of the corpus, read by humans and the skill and
  **never by scripts**. Different legal sources have idiosyncratic pipeline variations; the prose
  half of those variations goes here, so the machinery stays generic.

`etc/go/lib/subject.mjs` resolves a subject id to exported `GO_S_*` environment variables, and
validates refuse-by-default: an unknown key anywhere in the descriptor is an error, and a leg
entry naming a missing golden is a hard error naming the path (the one carve-out is
`legs['p7-dmn'].cases`, whose _absence on disk_ is the p7-dmn leg's designed `NOT-EXECUTABLE`
story rather than a configuration error). An unknown subject exits 2 listing the available
sidecars and the recipe for adding one. Both refusals are selftest-covered.

**The `legs` object is the leg declaration.** `go.sh` declares `p0-preflight`, `p3-check`,
`p6-tests` and `p9-report` for every subject, and a p7 stage iff `legs` has its entry; the
wizard-dependent halves of p0/p3/p6/p7-mcp engage iff `corpus.wizard` is present. This is what
keeps the §3.2 milestone rule honest across subjects: a future subject with no wizard and no
regulative rules (so no bpmn/lts legs and no NLG goldens) omits those entries, and `COMPLETE`
still means every stage _that subject declares_ is accounted for — not that its sidecar faked
nine legs. The BNA corpus (PR #195, unmerged) will slot in as exactly such a sidecar; it is
deliberately not created here, because its corpus is not on this branch.

---

## 3. The status lattice, and why `COMPLETE` is not `green`

Eight statuses: `PASS` · `DEGRADED` · `NOT-EXECUTABLE` · `NOT-REGENERATED` · `UNVERIFIED` ·
`NOT-BUILT` · `SKIPPED` · `BROKEN`. Only the first is green. Definitions live in
`.claude/skills/running-the-l4-pipeline/references/status-vocabulary.md` and are enforced in
`etc/go/lib/verdict.mjs`.

### 3.1 The oracle-class rule, which is the design's own addition

The seven-status lattice as originally sketched has a gap: nothing rejects a leg that names a
**weak** oracle. XML well-formedness satisfies "an oracle ran and returned 0"; so does a JSON
parse; so does `dmn-moddle` reading a DMN that cannot execute. The rule as stated was "PASS
requires an oracle", not "PASS requires a _correctness_ oracle", and that is where a lattice
erodes first — not by someone deleting statuses, but by someone picking a cheap oracle.

So every oracle declares a class, and two of the five are structurally barred from `PASS`:

| class            | proves                                                                | may license `PASS` |
| ---------------- | --------------------------------------------------------------------- | ------------------ |
| `execution`      | ran on its target engine, on cases, and agreed                        | yes                |
| `differential`   | reproduces a committed golden another gate defends                    | yes                |
| `structural`     | a checker modelled its semantics, or a counted invariant cross-checks | yes                |
| `wellformedness` | it parses                                                             | **no**             |
| `presence`       | it exists and is non-empty                                            | **no**             |

This is why the AKN leg reports `UNVERIFIED` rather than `PASS`, and why the LTS leg cross-checks
its `digraph` count against an independently-derived rule count instead of settling for "the file
is non-empty".

### 3.2 The milestone rule

```
G1 = COMPLETE  iff  every declared stage has a receipt
                AND no receipt is BROKEN
                AND every non-PASS receipt carries a reason that appears in the report
                AND every gate is satisfied or explicitly waived
```

**Completeness of accounting, not greenness.** That is what SPEC.md §6 actually asks for when it
permits a non-executable DMN at G1 _only if the report says so in Blocking terms_ — a rule about
what the report contains, not about what colour the legs are. It is also why this design can be
honest about nine legs and still terminate.

`BROKEN` outranks `GATE`, which outranks `INCOMPLETE`.

---

## 4. Resumability

SPEC.md §7.2 asks for stages that are resumable after interruption. Re-entry is a **digest
comparison, not a memory**.

Each phase script answers `--inputs` with the files it reads. The driver digests that set,
including each file's size and sha256, with a missing file recorded `ABSENT` rather than skipped.
A stage whose digest matches a prior completed receipt is replayed: a fresh row is written that
keeps the original verdict, names the earlier receipt in `replayed_from`, and copies its artifact
records **verbatim** — re-hashing would launder a file that changed after the original receipt was
written.

Three properties, all mechanically checked by `etc/go/selftest.mjs --with-driver`:

- a second run back to back re-executes nothing but the report;
- the milestone verdict is unchanged by replay;
- replayed receipts keep their original verdict.

**A replayed `PASS` is not demoted.** Demotion was implemented first and is wrong: it makes the
milestone verdict depend on how many times you ran it, which destroys the only reason resumability
is worth having. The evidence for a replayed `PASS` is the earlier row, in the same hash-chained
journal, which `go.sh verify` re-checks.

**`p9-report` never replays**, and declares no inputs to guarantee it. The journal grows while the
report renders, so a report cannot digest its own future; the under-declared-input hazard in its
most damaging form is a stale report claiming to be current.

### 4.1 The journal

One append-only, hash-chained `journal.ndjson` per run. Each record carries `prev` (the previous
record's hash) and `hash` (sha256 of its own canonical JSON), so a record cannot be altered or
removed without breaking every hash after it. `journal_schema: 1`; an unknown schema is `BROKEN`,
not guessed at.

The chain is not a security control — an agent that can write the journal can rewrite the whole
chain. It is an **undeniability** control: `render-report.mjs` prints a chain-verification failure
in the report itself, so hand-editing the journal produces a report that says the journal was
hand-edited.

Run outputs live in `${L4_GO_RUNDIR:-$TMPDIR/l4-go}/<run-id>/`, never in the tree. `go.sh gc`
keeps the latest few runs **and** every run holding a granted gate.

---

## 5. Every stage, and what it does today

### 5.1 Stages that run

| stage          | oracle                                                                                                                                              | notes                                                                                                                                                              |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `p0-preflight` | discovery calls vs the subject's `pins.json`, plus checker existence, plus the `l4 run` tripwire                                                    | pins are **narrow** — four CLI enumerations and the module's rule names, not a hash of `l4 --help`. A tripwire that fires on an unrelated help reflow gets deleted |
| `p3-check`     | `l4 check` ×2, `ELSE IF` absence, `@ref` per dated arm                                                                                              | the third house rule — isomorphism against the source — is recorded as unverified and carried by HG1, never omitted                                                |
| `p6-tests`     | `results[]` parsed out of `l4 run --json`, plus a floor on the assertion count                                                                      | the exit code is **not** the oracle; see §5.3                                                                                                                      |
| `p7-dmn`       | canonicalise-then-diff vs golden + `etc/validate-dmn.mjs` + both engine harnesses over the committed cases file                                     | `PASS`/`execution` since 2026-08-02; see §5.4                                                                                                                      |
| `p7-dmn-md`    | canonicalise-then-diff vs golden                                                                                                                    | `DEGRADED` by construction                                                                                                                                         |
| `p7-bpmn`      | byte-diff vs goldens + soundness + interchange                                                                                                      | `DEGRADED`: the mandated DMN wiring is unbuilt                                                                                                                     |
| `p7-ladder`    | regenerate, then `git diff` over the committed figures must be **empty**                                                                            | a non-empty diff means the committed figures were stale, which is a fail and never a pass. The run never commits                                                   |
| `p7-lts`       | `digraph` count == regulative-rule count from the BPMN discovery call                                                                               | `PASS (INTERIM)` — the label rides in the status                                                                                                                   |
| `p7-mcp`       | HTTP 2xx, poll to `ready`, then a JSON-RPC `tools/list` POST whose non-generic tool count equals the deployment's function count, **loopback only** | see §6.4. A GET on `.mcp` is 405 by design, and a non-empty tool list is met vacuously by the service's own four generic tools                                     |
| `p7-tnr`       | none reachable                                                                                                                                      | `NOT-REGENERATED`                                                                                                                                                  |
| `p7-wizard`    | well-formedness + measured negative controls                                                                                                        | `DEGRADED`; the only oracle available is barred from `PASS`                                                                                                        |
| `p7-akn`       | shallow well-formedness                                                                                                                             | `UNVERIFIED`, declared `EXTRA`                                                                                                                                     |
| `p9-report`    | section-presence over the rendered report                                                                                                           | reads the journal and nothing else                                                                                                                                 |

### 5.2 Stages that are scaffolded and cannot run

Each exits 3 after printing what it would do and what is blocking it. None is a member of any
milestone's declared stage list, so its absence cannot make a milestone `INCOMPLETE`.

| stage         | blocker                                                                                                                                                                                                                                                         |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `p1-ingest`   | no bundle schema or manifest format is defined anywhere in SPEC.md (grepped 2026-08-02: `bundle` occurs once, in §4's P1 deliverable; `manifest` not at all) — nothing to write into, no acceptance condition. (R4, formerly listed here, was ruled 2026-08-02) |
| `p2-sweep`    | it is a web-search stage and this orchestrator makes no outward network request except the loopback deployment; and the external-modification register has no machine-readable format, so P5's "every entry disposed" cannot be checked                         |
| `p3-encode`   | the stage is unbuilt. R4 was its ruling blocker until 2026-08-02; the ruled `Interpretation` representation now waits on tooling, and the isomorphism judgement stays HG1's                                                                                     |
| `p4-forks`    | R4 ruled 2026-08-02, and the design note's own §6 says no code changes until the encode phase runs; the fork register still has no machine-readable format (the BNA smoke's register shape, PR #195, is the leading candidate)                                  |
| `p5-gate`     | its condition is explicitly a judgement; two of its five checks already run inside `p3-check`, and two of the remaining three join over registers that do not exist                                                                                             |
| `p8-verify`   | **R5** open, no CLI footing at all; SPEC.md §5's `P8 verifier toolchain` row inventories nothing ("not inventoried here — R5 asks which existing machinery or external tool goes first") and §6 gives it no pass condition. Gates nothing in G0–G4              |
| `p10-publish` | **R1** open (owner: Meng), **R2** open, and every outward-facing act here is HG2's                                                                                                                                                                              |

Until 2026-08-02 five of the seven were blocked on a ruling rather than on engineering — a
deliberate stance: building against an unruled representation is building to be rewritten. With
R4 ruled, only `p8-verify` (R5) and `p10-publish` (R1/R2) still wait on rulings; the rest wait on
tooling.

### 5.3 The `l4 run` workaround, and its expiry

`l4 run` exits **0** on a failed `#ASSERT`, on a runtime exception, and on a `Stuck` evaluation.
Only a typecheck error produces exit 1, and `--json`'s `ok` field tracks typechecking too.
Measured 2026-08-02:

```
$ l4 run /tmp/failing.l4 --json     # contains  #ASSERT `double` 21 EQUALS 43
{"diagnostics":[…"assertion failed"…],"ok":true,
 "results":[{"kind":"assertion","range":"failing.l4:5:1-30","value":false}]}
$ echo $?
0
```

So `etc/go/lib/assert-report.mjs` parses `results[]`, and ships with a selftest that mutates a
real captured envelope ten ways to prove it can be red. `p0-preflight` runs a deliberately failing
fixture and asserts it **still** exits 0 — when that tripwire goes red, `l4 run --fail-on-assert`
or its equivalent has shipped and the workaround must be deleted. The tripwire's error message
says so, with the three steps.

Patching `l4` itself is the right fix and `CORPUS-TRACK.md` already proposes it. It needs
`cabal build`, and this orchestrator does not build. Recorded as the top upstream ask.

### 5.4 The DMN leg: `NOT-EXECUTABLE` until 2026-08-02, `PASS`/`execution` after

**As first built,** this leg reported `NOT-EXECUTABLE`, for a reason kept on the record:
`etc/kie-dmn-check/run.sh` and `etc/camunda-dmn-check/run.sh` both require
`--cases CASES.json`, and no cases file existed for the **corpus** DMN — the only Reg CF
cases file, `jl4/examples/dmn/reg-cf.cases.json`, belongs to the 101-line toy that
CI's 25/25 step runs. Writing cases against a DMN whose 80 boxed literal expressions could not
evaluate would have manufactured a green the artifact had not earned; that was DMN Phase 5 (BKM
emission) work, and `NOT-EXECUTABLE` with a named blocker was the true status — R0 makes it a
defect rather than a caveat.

**Discharged by PR #194** (merged to `unstable` 2026-08-02 as `4122355a`): Phase 5 BKM emission
plus the R-A/R-B/R-C rulings took the corpus fidelity from 95 blocking to 0, and
`jl4/examples/dmn/regcf-corpus.cases.json` landed carrying 16 dated cases whose expected values
are **L4-evaluated, not hand-typed** — exactly the "earned green" condition the paragraph above
named. The phase script's engine-harness branch, written in advance for this day, now runs, and
the leg's class rose from `differential` to `execution`. Measured on run
`2026-08-02-97b15013-002`: KIE 8.44.0.Final `16 case(s), 0 error(s), 0 warning(s), 1072/1072
value(s) as expected, 224/224 service output value(s) as expected`; Camunda 8.7.6 (zeebe-dmn)
`1072/1072 value(s) as expected`.

---

## 6. The gates

SPEC.md §7.3 defines exactly two, and this implements both. What each one **means**, before the
mechanism: **HG1 is a human domain expert certifying isomorphism** — someone has read the
inert-style L4 against the source regulation, section by section, and signs that it says what the
law says. That judgement has no checkable form, which is why it is a gate and not an oracle.
**HG2 is Meng authorizing a specific outward-facing act** — creating the corpus repo, publishing
the report, any lexipedia contact. Different certifier, different question, different namespace.
The ssh-signature mechanism below exists for one reason: **an agent can verify a signature and
cannot make one**, so no agent — however convinced it is of its own encoding — can grant itself
either approval by signature. HG1 can additionally be waived, but only on the record and bound to
the corpus digest (§6.2) — circumvention is undeniable, not impossible — and HG2 cannot be waived
at all. The reader-facing treatment of both gates is
`.claude/skills/running-the-l4-pipeline/references/gates.md`.

### 6.1 Mechanism

A gate is granted by a **detached SSH signature over a payload derived from the journal** — run
id, repo HEAD and tree state, pinned clock, the sha256 of every corpus file, and the receipt hash
of every stage so far. `gate-request.sh` builds and prints it; the human signs out of band with
`ssh-keygen -Y sign` using a key that never enters the worktree; `gate-verify.sh` runs
`ssh-keygen -Y verify` against `gate-allowed-signers`. **Agents can verify and cannot sign.**

Two consequences follow from binding to content rather than issuing a token: a post-gate edit
re-opens the gate (touch a corpus file and the payload changes), and re-running is cheap (HG1 over an
unchanged corpus is effectively a standing signature). `gate-verify.sh` rebuilds the payload from
the journal every time, so a stale payload file on disk can never be what gets verified.

Both consequences had holes, and both are closed. The payload used to render one row per
`stage_end`, so the first documented resume appended replay rows, changed the payload and made a
valid signature stop verifying over an untouched corpus — replayed receipts are now excluded.
And the driver used to satisfy a gate by grepping the journal for any granting row, which memoised
the gate for the life of the run directory: `gate-verify.sh` was never called again on a resume,
so the signed route's own content binding stopped applying too. The gate is now open only while a
granting row records the digest of the corpus the run is actually using.

HG2 uses namespace `l4-go-gate-hg2`, so an HG1 signature cannot be replayed as an HG2 one.

`gate-allowed-signers` **ships with no key.** Every gated stage refuses with exit 3 and an
explanation. The orchestrator does not invent an approver.

### 6.2 Waivers

`--waive HG1="reason"` records a gate row with `state: waived`, the reason, and the sha256 of the
corpus files the waiver is granted over; the report's Gates section prints it. The gate table has
exactly two shapes that let a run proceed: `satisfied by <signature file>` or `waived: <reason>`.
**A waiver that is not in the report is impossible**, and a waiver with no reason is refused at the
command line. There is no `--skip-gate` and no environment override; adding one would have to be a
diff.

**A waiver binds to content, like a signature does.** The driver re-derives the corpus digest
before every gated stage and re-opens the gate when it has moved. Until 2026-08-02 it did not: one
`--waive HG1` at the top of a run covered every later edit to the encoding, so the corpus could be
changed mid-run and every HG1-gated stage re-ran against unreviewed content, leaving no diff, no
chain break and no `verify` finding — deniable, which is precisely what §6.3 claims this design is
not. Since `gate-allowed-signers` ships with no key, the waiver is the only route anyone can take
today, so the content-binding property has to hold on it or it holds nowhere.

**HG2 is not waivable at all.** `go.sh run --waive HG2=…` exits 2. Its subject is anything
outward-facing, and no agent decides that on its own; the rule used to live only in the skill while
the driver accepted the flag and `gate-verify.sh` recommended it by name.

The G1 path that bypasses HG1 is the identical code path that would bypass it at G2. That is the
point of implementing waivers rather than special-casing the replay milestone.

### 6.3 What the gate machinery does not do

Stated plainly, because a security claim that overreaches is worse than none.

**The threat model is a hurried agent, not a malicious root user.** An agent with write access can
edit `gate-verify.sh`, append a key to `gate-allowed-signers`, or rewrite the journal. Three
partial mitigations, in decreasing strength:

1. **`go.sh verify --gates`, run later by a different party.** It recomputes every verdict from
   the journal, re-hashes every artifact a receipt names, and checks that each granted gate was
   recorded _before_ the first stage it gates began — counting a `stage_end` as well as a
   `stage_begin`. That widening is what makes the check fire at all: `go.sh` decides the gate
   strictly before writing `stage_begin`, so a driver journal could never violate the narrow
   version, while a phase script invoked directly (which `go.sh plan` and SKILL.md both tell the
   reader to do) writes only a `stage_end` and was invisible to it. It is the only check the acting
   agent cannot pre-satisfy, because it happens afterwards and is performed by somebody else.
2. **The hash chain**, whose failure prints in the report — and now also in the driver's own exit
   code: `go.sh run` reads verify-run's findings instead of only its verdict, so a run whose
   recorded artifacts have vanished, or whose journal has been edited, no longer prints `COMPLETE`
   and exits 0 while `go.sh verify` over the same directory lists the findings and exits 1.
3. **The diff.** Every route past a gate leaves a change in the repository.

The claim is that gate circumvention is **undeniable**, not **unfakeable**.

### 6.4 The one outward-facing write, and its fence

Everywhere else, "nothing outward-facing happens" is guaranteed by there being no code that could.
The MCP leg posts a deployment, so the fence is explicit: the zip is built locally and hashed
unconditionally; the POST target must be **loopback**, and a non-loopback host is refused with
exit 3 citing HG2; with no `JL4_GO_SERVICE_URL` the leg is `SKIPPED` and the zip is still
recorded; the deployment id carries the run id so concurrent runs cannot collide.

The URL is parsed with a real URL parser, and **userinfo is refused outright**. The fence used to
extract the host with `sed 's#[:/].*$##'`, which truncates at the first colon: measured against a
loopback service, `http://127.0.0.1:8080@REALHOST/` read as host `127.0.0.1`, passed the
allow-list, and reached REALHOST, because curl consumes `127.0.0.1:8080` as Basic credentials. The
same parser refused `[::1]` and `LOCALHOST`, which are loopback — an ad-hoc parser was wrong in
both directions at once.

`p10-publish` refuses unconditionally today. The final `report.md` is written into the run
directory, never into the tree, and copying it anywhere a third party can read it is P10 — which
is HG2's.

---

## 7. Three ways this rots, and the counterweight

| rot                                                                              | mechanism                                                                   | counterweight                                                                                                                                                                                                                                                                                                                 |
| -------------------------------------------------------------------------------- | --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| the lattice collapses to PASS/FAIL, because eight statuses feel like bureaucracy | one edit in `verdict.mjs`                                                   | `etc/go/selftest.mjs` constructs a receipt for each status, asserts `PASS` is refused with a null, failing, **weak-class**, or artifact-less oracle, and asserts a `BROKEN` receipt cannot yield a `COMPLETE` milestone. CI-gated by the new `go:` filter                                                                     |
| measured numbers get transcribed into report prose and go stale                  | somebody pastes a figure into the template                                  | `report/template.md` contains **no** literal measurement, and `render-report.mjs` refuses to render one: any digit-run outside a small allowlist of spec coordinates is a template defect (exit 4), and an unresolved placeholder is too. Fidelity counts are parsed by `lib/fidelity-counts.mjs`, never typed                |
| the stage table drifts from the CLI and harness reality                          | a renamed checker, a new `--to` target, `--fail-on-assert` finally shipping | `p0-preflight` re-derives the four enumerations and the module's rule names **by discovery call** and compares them as sets, so a rename fails loudly naming the exact strings; it existence-checks every checker in the subject's `pins.json`; and the failing-`#ASSERT` tripwire fires the day the workaround becomes wrong |

A fourth was added after the first run: `check-skill-drift.mjs` compares the skill's documented
command set against `go.sh`'s dispatch table in **both** directions and refuses a runnable command
in any `references/` file, so the usage has exactly one copy to keep true. It caught two real
drifts on its first execution.

---

## 8. Deliberately not built

| not built                                                              | why                                                                                                                                                                                                                                                                                            |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| a workflow runtime (`agent()`/`pipeline()`/`parallel()`/`loopUntil()`) | those primitives are declared in `build-dmnmd-to-l4.workflow.js`'s header and defined **nowhere** in the tree — `grep` for `pipeline(` matches only that file. Bash dispatch plus a conductor reading the skill is what "deterministic and resumable" actually requires                        |
| `loopUntil`-style retry-until-green                                    | it is the precise anti-pattern for this stance: rerunning a projection until a regex matches is how `DEGRADED` becomes `PASS`. Banned in the skill, with the reason stated                                                                                                                     |
| the de novo path and the §8 diff oracle                                | **R4** was open when this was written (ruled 2026-08-02 — the `Interpretation` parameter, extended to regulative rules); building the tooling is now unblocked lap-two work, sequenced behind the encode phase per the design note's §6                                                        |
| P8 verification                                                        | **R5** open, gates nothing in G0–G4, and there is zero CLI footing. A leg here would be pure `UNVERIFIED`                                                                                                                                                                                      |
| the corpus-of-law repo and the lexipedia probe                         | **R1**/**R2** open, both HG2                                                                                                                                                                                                                                                                   |
| a `regcf-corpus.cases.json`                                            | **discharged 2026-08-02** — PR #194 landed the file (16 dated cases, expected values L4-evaluated), meeting the condition §5.4 named. "Not built _here_" stays true: the orchestrator consumes the committed file and still never writes one                                                   |
| patching `l4` for `--fail-on-assert`                                   | the right fix; needs `cabal build`, which this orchestrator never runs. Top upstream ask, shipped as a workaround with an expiry tripwire                                                                                                                                                      |
| machine-readable fork and external-modification registers              | SPEC.md defines neither format anywhere, and P5's "every entry disposed" (§4, P5) cannot be checked without them. They are P2/P4's deliverables; R4 is now ruled (2026-08-02), so defining them is unblocked — the BNA smoke's emergent register shape (PR #195) is the candidate to formalise |
| commits or pushes by the orchestrator                                  | matches `build-dmnmd-to-l4.workflow.js`'s `policy: { commit: false, push: false }`                                                                                                                                                                                                             |

---

## 9. What this change records elsewhere

Per `CLAUDE.md` §4 — a decision is recorded in its owning document in the same PR, or it is not
decided:

- **SPEC.md §5** — the `orchestrator ("go")` row said "**does not exist** — this spec is its birth
  certificate". That sentence became false when `etc/go/` landed; it now names what exists and
  points here.
- **SPEC.md §9 R3** — "orchestrator packaging: proposed §7.2. Confirm or redirect." §7.2's shape
  (a thin skill plus workflow scripts per phase, deterministic and resumable, one builder per
  worktree) is what was built, so R3 is marked `ANSWERED 2026-08-02, see ORCHESTRATOR.md`.
- **SPEC.md drift** — verified against `gh` on 2026-08-02 and repaired in the same change:
  PR #177 and PR #180 are MERGED (so G1's entry condition is satisfied), and `regcf.l4` is 1,236
  lines, not 1,241 — both in §5. Two further stale references, missed by the first pass because it
  repaired the cited lines rather than grepping for the claim: SPEC.md §4's P5 stage still read
  "#177 open" at line 135, and `R4-FORK-REPRESENTATION.md` still read "PR #185 (open at this
  writing)". #185 was never mentioned in SPEC.md at all, so the earlier version of this bullet
  claimed a repair with no target.
- **PROJECTIONS.md** — D2 above (superseded in part: PR #194 subsequently moved the fidelity
  heading again, to 0/21/125, and the `unstable` merge resolved PROJECTIONS.md to that state — the
  arrows below record what _this branch's_ repair did at the time): the fidelity heading 114/46/18 → 95/21/54; the §1 element counts
  102/91/68/202 → 92/80/37/189; both stale `regcf.l4` line counts → 1,236; the dmnmd figures; and —
  in this change, because the first pass corrected only the cited cells — BOTH per-code tables
  rewritten as the complete emitted set, each column summing to its heading. Also §6: the
  "not a defect" dismissal of the CLI-reproducibility finding is retracted in place (D1).

Not recorded at this document's first writing, and deliberately so: **R4 was then OPEN** —
nothing in the orchestrator build ruled it, and the stages that depend on it refused rather than
guessed. **Ruled 2026-08-02 during Meng's review of this PR** (R4-FORK-REPRESENTATION.md §7):
the `Interpretation` parameter, extended to regulative rules. The scaffolded stages still
refuse — their blocker is now unbuilt tooling, not an open ruling — and this change updates
every refusal text that said otherwise.
