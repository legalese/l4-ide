# `etc/go/` — the "SEC Regulation Crowdfunding: go" orchestrator

Everything here has an exit code. Everything that is a judgement lives in the
skill at `.claude/skills/running-the-l4-pipeline/`. Scripts never call a model;
the skill never writes a status.

The spec is [`specs/todo/single-instruction-demo/ORCHESTRATOR.md`](../../specs/todo/single-instruction-demo/ORCHESTRATOR.md),
which states in the present tense what runs today and what is scaffolded and
cannot run. The pipeline it serves is `specs/todo/single-instruction-demo/SPEC.md`.

## Usage

```
etc/go/go.sh run     --milestone g1 --subject regcf [--run-id ID] [--through STAGE]
                     [--only STAGE] [--waive HG1=REASON] [--fixed-now ISO8601]
etc/go/go.sh plan    [--milestone g1|g2]
etc/go/go.sh status  [--run-id ID]
etc/go/go.sh verify  [--run-id ID] [--gates]
etc/go/go.sh gc      [--keep N]
etc/go/go.sh help
```

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
the LTS DOT to SVG. `mvn` + JDK 17/21 only for the engine harnesses, which are
not reachable at G1 (see the `p7-dmn` blocker). Every absence produces a
`SKIPPED` receipt naming what is missing and what it was needed for.

## Selftests

```
node etc/go/selftest.mjs [--with-driver]
node etc/go/lib/assert-report.selftest.mjs
```

`selftest.mjs` proves the status lattice can still say no: that every status is
producible, that `PASS` is rejected with a null, failing, or _weak_ oracle, that
a `BROKEN` receipt cannot yield a `COMPLETE` milestone, and that editing,
deleting or rewriting a journal record breaks the chain. `--with-driver` also
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
discovery call returned a set that differs from `etc/go/PINS.json`. The message
names the exact strings. Re-verify the phase scripts against the new surface,
then update the pin.

**`known-defects[…]: X NO LONGER REPRODUCES`** (exit 4) — a measured defect used
as a negative control has been fixed. Delete the entry from
`etc/go/known-defects.json`; a stale negative control is a lie about what the
leg measures.
