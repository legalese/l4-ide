# `etc/go/` — the "⟨body of law⟩: go" pipeline orchestrator

One instruction names a subject; the pipeline takes it from source text through an L4
encoding to every projection, gate and conversion report. The driver, libraries and phase
scripts are subject-generic: everything the pipeline knows about one body of law lives in a
per-subject sidecar under `etc/go/subjects/<id>/`. `regcf` (SEC Regulation Crowdfunding) is
the inaugural, replay-milestone subject, not the scope — the BNA smoke test (PR #195) is the
same pipeline pointed at a different statute, and it will slot in as a second sidecar.

Everything here has an exit code. Everything that is a judgement lives in the
skill at `.claude/skills/running-the-l4-pipeline/`. Scripts never call a model;
the skill never writes a status.

The spec is [`specs/todo/single-instruction-demo/ORCHESTRATOR.md`](../../specs/todo/single-instruction-demo/ORCHESTRATOR.md),
which states in the present tense what runs today and what is scaffolded and
cannot run. The pipeline it serves is `specs/todo/single-instruction-demo/SPEC.md`.

## Usage

```
etc/go/go.sh run     --milestone g1 --subject <id> [--run-id ID] [--through STAGE]
                     [--only STAGE] [--waive HG1=REASON] [--fixed-now ISO8601]
etc/go/go.sh plan    [--milestone g1|g2] [--subject <id>]
etc/go/go.sh status  [--run-id ID]
etc/go/go.sh verify  [--run-id ID] [--gates]
etc/go/go.sh gc      [--keep N]
etc/go/go.sh help
```

`<id>` names a sidecar directory under `etc/go/subjects/` (today: `regcf`). While exactly
one sidecar exists, `--subject` may be omitted and defaults to it; with several, naming one
is mandatory. An unknown subject exits 2 listing the available sidecars and the recipe for
adding one.

A first run, given a prebuilt `l4`:

```
export L4=/path/to/dist-newstyle/build/<arch>/ghc-9.10.3/jl4-0.1/x/l4/build/l4/l4
etc/go/go.sh run --milestone g1 --subject regcf
```

That stops at HG1 with exit 3 and tells you how to grant the gate. To proceed
without a signature, waive it on the record:

```
etc/go/go.sh run --milestone g1 --subject regcf \
  --waive HG1="G1 replays the already-reviewed committed corpus"
```

## Subjects

A subject sidecar is four files in `etc/go/subjects/<id>/`:

| file                 | role                                                                                                                                                                                                                                                                                                             |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `subject.json`       | the machine-readable descriptor: id, display name, legal citation, source entry URL, corpus module paths (`corpus.main`, optional `corpus.wizard`), per-subject check floors (`checks.min_dated_arms`, `checks.min_assertions`), and a `legs` object — one entry per projection leg, with its golden/cases paths |
| `pins.json`          | the CLI surface the stage table reads, measured against that subject's corpus                                                                                                                                                                                                                                    |
| `known-defects.json` | measured defects used as negative controls; empty groups say why they are empty                                                                                                                                                                                                                                  |
| `NOTES.md`           | free-prose idiosyncrasies of the corpus, for humans and the skill. **No script reads it.**                                                                                                                                                                                                                       |

`etc/go/lib/subject.mjs` resolves and validates a sidecar (unknown keys refused; a leg entry
naming a missing golden is a hard error naming the path) and exports it to the driver as
`GO_S_*` environment variables. **The `legs` object is the leg declaration**: a p7 stage is a
declared member of the milestone iff `legs` has its entry, and the wizard-dependent halves of
p0/p3/p6/p7-mcp engage iff `corpus.wizard` is present. So a future subject with no wizard and
no regulative rules (no bpmn/lts legs, no NLG goldens) simply omits those entries, and
`COMPLETE` still means what it says. To add a subject, copy an existing sidecar and re-measure
every value in it against the new corpus — the pins and floors are measurements, not defaults.

## Exit codes

Extending `etc/check-bpmn-kie.sh`'s 0/1/2/3/4:

| code | meaning                                                     |
| ---- | ----------------------------------------------------------- |
| 0    | clean                                                       |
| 1    | a finding                                                   |
| 2    | usage                                                       |
| 3    | a human gate is not satisfied                               |
| 4    | broken — a harness defect, never a finding about the corpus |
| 5    | a stage was SKIPPED while `L4_GO_REQUIRED=1`                |

## Environment

| variable             | effect                                                                                                                                                                                                                                                                                                                                               |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `L4`                 | **required.** Path to a prebuilt `l4`. This orchestrator never runs `cabal`; the build lock is a shared resource and concurrent invocations in one worktree corrupt each other. Same escape hatch as `JL4_LSP_CMD=` / `DMNMD=`.                                                                                                                      |
| `JL4_LIBRARY_PATH`   | defaults to `<repo>/jl4-core/libraries`                                                                                                                                                                                                                                                                                                              |
| `JL4_LSP_CMD`        | a prebuilt `jl4-lsp`, for the ladder leg. Absent ⇒ that leg is `SKIPPED` with a named reason.                                                                                                                                                                                                                                                        |
| `JL4_GO_SERVICE_URL` | a **loopback** `jl4-service` for the MCP leg. The URL is parsed, not string-trimmed, and userinfo is refused outright — `http://127.0.0.1:8080@REALHOST/` reads as loopback to a naive parser and as credentials-for-REALHOST to curl. A non-loopback host is refused: an outward-facing deployment is HG2's subject, not an environment variable's. |
| `L4_GO_RUNDIR`       | where runs live (default `$TMPDIR/l4-go`). Never the tree.                                                                                                                                                                                                                                                                                           |
| `L4_GO_REQUIRED`     | `1` ⇒ any `SKIPPED` stage is fatal (exit 5), which is what CI wants                                                                                                                                                                                                                                                                                  |
| `L4_GO_FIXED_NOW`    | pins the clock threaded into every `run`/`check`/`render` (default `2025-01-31T00:00:00Z`)                                                                                                                                                                                                                                                           |

## Requirements

`node` and `bash` for everything. `npx` for the DMN and BPMN interchange gates.
`npm` plus `JL4_LSP_CMD` for the ladder leg. `graphviz` optionally, to render
the LTS DOT to SVG. `mvn` + JDK 17/21 for the DMN engine harnesses on the
`p7-dmn` leg (reachable since PR #194 landed the corpus cases file). Every
absence produces a `SKIPPED` receipt naming what is missing and what it was
needed for.

## Selftests

```
node etc/go/selftest.mjs [--with-driver]
node etc/go/lib/assert-report.selftest.mjs
```

`selftest.mjs` proves the status lattice can still say no: that every status is
producible, that `PASS` is rejected with a null, failing, or _weak_ oracle, that
a `BROKEN` receipt cannot yield a `COMPLETE` milestone, and that editing,
deleting or rewriting a journal record breaks the chain. It also proves the
subject resolver refuses an unknown subject (listing the available sidecars), a
descriptor naming a nonexistent golden, and a descriptor carrying an unknown
key. `--with-driver` also
drives the whole G1 pipeline twice and asserts that the second run re-executes
nothing but the report — the only mechanical check that `replayed` means
anything.

`assert-report.selftest.mjs` mutates a real captured `l4 run --json` envelope
ten ways to prove the assertion checker can be red. It exists because `l4 run`
exits **0** on a failed `#ASSERT`, so neither the exit code nor the envelope's
`ok` field can be the oracle.

## Common errors

**`go.sh: L4 is unset.`** — point it at a prebuilt binary. The orchestrator will
not build one.

**`GATE HG1: REFUSED — no signer is enrolled.`** — the shipped state.
`specs/todo/single-instruction-demo/gate-allowed-signers` carries no public key,
so nothing verifies. Enrol a key, or waive the gate with a reason that will
appear in the report. A waiver binds to the sha256 of the corpus files it was
granted over: edit one and the gate re-opens, for that run and every resume of
it. **HG2 cannot be waived** — `--waive HG2=…` exits 2, because its subject is
anything outward-facing and that decision is not an agent's.

**`the CLI surface the stage table depends on has moved`** (exit 4) — a
discovery call returned a set that differs from the subject's
`etc/go/subjects/<id>/pins.json`. The message names the exact strings.
Re-verify the phase scripts against the new surface, then update the pin.

**`known-defects[…]: X NO LONGER REPRODUCES`** (exit 4) — a measured defect used
as a negative control has been fixed. Delete the entry from the subject's
`etc/go/subjects/<id>/known-defects.json`; a stale negative control is a lie
about what the leg measures.

**`subject '<id>' has no sidecar`** (exit 2) — the subject is not set up. The
message lists the available sidecars and the four files a new one needs; see
the Subjects section above.
