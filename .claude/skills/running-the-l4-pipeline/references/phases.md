# Phases Reference

What each stage of the single-instruction pipeline is for, what it deposits as its interface to the next stage, and — for the seven that cannot run — exactly what is blocking it.

**Canonical references:**

- The pipeline itself: `specs/todo/single-instruction-demo/SPEC.md`
- What runs today, in the present tense: `specs/todo/single-instruction-demo/ORCHESTRATOR.md`
- The fork-representation design note P4 is waiting on: `specs/todo/single-instruction-demo/R4-FORK-REPRESENTATION.md`

---

## Contents

- [The interface rule](#the-interface-rule)
- [What runs at G1](#what-runs-at-g1)
- [What refuses, and why](#what-refuses-and-why)
- [The seven projection legs](#the-seven-projection-legs)
- [The one leg that is not in the spec](#the-one-leg-that-is-not-in-the-spec)
- [Reading a phase script](#reading-a-phase-script)

---

## The interface rule

SPEC.md states it once and it governs everything: _each stage names its deliverable, and the deliverable is the interface — a later stage may read only what an earlier stage committed._

In the driver this is not a convention, it is the mechanism. A stage's `--inputs` list is what gets digested to decide whether it may replay; if a stage reads something it did not declare, the digest is wrong and the stage will report `replayed` when it should have re-run. Declaring an input and reading an input are the same act, performed twice, and they have to agree.

---

## What runs at G1

G1 is the **replay run**: the committed corpus driven through every reachable projection. No encoding happens. SPEC.md's entry condition for it — PRs #177 and #180 landed — is satisfied.

| stage          | what it does                                                                                                                                                                                         | interface it deposits                                                                          |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `p0-preflight` | identifies the tree, the binary, the clock and the corpus by sha256; probes the toolchain; checks the CLI surface the stage table depends on; fires the upgrade tripwire for the `l4 run` workaround | `probes.json`, `cli-surface.txt`, and the corpus hashes every later gate payload is built from |
| `p3-check`     | typechecks both corpus modules and runs the two mechanisable P3 house-style rules                                                                                                                    | `p3-check.txt`                                                                                 |
| `p6-tests`     | evaluates the corpus's own `#ASSERT` directives and reads `results[]` — **not** the exit code                                                                                                        | `regcf.run.json`, `regcf-wizard.run.json`, `p6-assertions.txt`                                 |
| `p7-*`         | one script per projection leg, all read-only, each with its own oracle                                                                                                                               | the emitted artifacts and their fidelity reports                                               |
| `p9-report`    | renders the conversion report from the journal and checks that every section SPEC.md §P9 requires is present                                                                                         | `report.md`, `report.html`                                                                     |

`p0-preflight` and `p3-check` are ungated. Everything from `p6-tests` on is behind HG1.

### The two checks `p3-check` can make, and the one it cannot

P3's house rules are: inert style, `GIVEN` over `ASSUME`, `BRANCH` over `ELSE IF` chains, and an `@ref` FR citation on every dated arm. Two of those are greppable and are checked. The third — "isomorphic, a domain expert can review it section by section against the regulation" — has no mechanical form, and the stage records that fact rather than passing over it in silence.

The `@ref` check is scoped narrowly on purpose: a dated arm is a line comparing `RULES EFFECTIVE DATE` against a `Date` **literal**, excluding comments and `EVAL UNDER RULES EFFECTIVE AT` test directives, and its citation must appear in the same contiguous block. A first attempt used a three-line window and produced twenty false findings, including comment prose and every `#EVAL` line. A check that cries wolf is worse than no check.

---

## What refuses, and why

Seven stages exist as entry points and cannot run. Each prints what it would do and what is blocking it, then exits 3. None of them is a member of any milestone's declared stage list, so their absence cannot make a milestone incomplete.

| stage         | blocker                                                                                                                                                                                                                                                                                     |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `p1-ingest`   | G2 entry is gated on **R4**, which is open. Independently, no bundle schema or manifest format is defined anywhere in SPEC.md, so there is nothing for an ingest stage to write into and no acceptance condition to check it against.                                                       |
| `p2-sweep`    | Two blockers. It is a web-search stage, and this orchestrator makes no outward network request except the loopback deployment in the MCP leg. And SPEC.md defines no machine-readable external-modification register anywhere — without one, P5's "every entry disposed" cannot be checked. |
| `p3-encode`   | **R4** is open, so an encoding stage would be writing to be rewritten.                                                                                                                                                                                                                      |
| `p4-forks`    | **R4** is open, and the design note's own §6 says no code changes until the demo's encode phase runs. The fork register has no machine-readable format either.                                                                                                                              |
| `p5-gate`     | Its condition is explicitly a judgement. Two of its five checks already run inside `p3-check`; the other three are not mechanisable and two of them join over registers that do not exist yet. A script cannot hold this gate — the skill's checklist and HG1 do.                           |
| `p8-verify`   | **R5** is open (which verifier goes first), there is no CLI footing at all, SPEC.md §5's `P8 verifier toolchain` row inventories nothing and §6 gives it no pass condition. A stage here would be pure `UNVERIFIED` by construction. P8 gates nothing in G0–G4.                             |
| `p10-publish` | **R1** is open and owned by Meng: the corpus-of-law repository has no name, org, license or layout, and `jl4/examples/` is explicitly not its home. **R2** is open and needs a read-only probe first. Every outward-facing act here is HG2's.                                               |

The pattern is worth naming: **five of the seven are blocked on an open ruling, not on engineering.** Building against an unruled representation is building to be rewritten, and the design's refusal to do that is deliberate rather than incidental.

---

## The seven projection legs

R0 rules that "it renders but cannot execute" is a **defect**, not a caveat. The statuses below are what that rule looks like when it is applied honestly rather than aspirationally.

| leg    | what it emits                                                         | oracle                                                                                                                                                                        | typical status                                                                                                   |
| ------ | --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| DMN    | DMN 1.3 XML + fidelity report                                         | canonicalise-then-diff against the committed golden, plus the `dmn-moddle` interchange gate                                                                                   | `NOT-EXECUTABLE` — no cases file exists for the corpus DMN, so neither engine harness can be pointed at it       |
| dmnmd  | one markdown table + a long loss report                               | differential against the golden                                                                                                                                               | `DEGRADED` — lossy by construction, and no engine executes markdown, so it can never reach the `execution` class |
| BPMN   | three processes, one per regulative rule                              | byte-diff against the goldens, then soundness and interchange                                                                                                                 | `DEGRADED` — the mandated BPMN→DMN wiring is not built and has no checker                                        |
| ladder | the committed SVG figures, regenerated                                | drift: a non-empty `git diff` over the figures directory is a **fail**, never a pass                                                                                          | `PASS` with `JL4_LSP_CMD` set; `SKIPPED` otherwise                                                               |
| LTS    | GraphViz DOT, one `digraph` per regulative rule                       | the `digraph` count must equal the rule count the BPMN discovery call independently reports                                                                                   | `PASS (INTERIM)` — the proper visualiser is unbuilt and graphviz is the spec's declared stand-in                 |
| MCP    | a deployable zip, and a loopback deployment when a service is running | HTTP 2xx, then the deployment polled to `ready`, then a JSON-RPC `tools/list` **POST** to `.mcp` whose non-generic entries number exactly the deployment's own function count | `SKIPPED` without a service                                                                                      |
| TNR    | nothing                                                               | none reachable                                                                                                                                                                | `NOT-REGENERATED` — the NLG goldens come from `cabal test jl4:jl4-test` and this orchestrator never builds       |
| wizard | the disposition/reachability plan                                     | well-formedness plus measured negative controls                                                                                                                               | `DEGRADED` — the plan is not the interview query plan, and the only oracle available is barred from `PASS`       |

### Why the DMN leg needs a canonicalisation, and why that is not a fudge

`l4 export regcf.l4 --to dmn` is **not** byte-identical to the committed golden. Measured: both files are 3,248 lines and 23 of them differ, every one of the form `main.l4:<position>` in the golden against `regcf.l4:<position>` from the CLI, because `jl4/tests/DmnExport.hs:3212` typechecks goldens against an empty virtual file system so no source URI reaches the `@ref` renderer. (`diff | wc -l` is 92 — four output lines per changed line — which is the figure this sentence used to quote as a line count.)

A bare byte-diff would therefore be red on day one, and the pressure on the first operator would be to regenerate the golden from the CLI — silently rewriting the artifact `jl4-test` defends. So the leg canonicalises first, and every canonicalisation in `etc/go/lib/canon-diff.mjs` carries two required fields: a `because` naming the file and line that causes it, and a `delete_when` naming the condition under which the entry must be removed. A canonicalisation with no `because` is a lie about how much the diff proved, and the module refuses to load one.

---

## The one leg that is not in the spec

`l4 render FILE --format akn` emits Akoma Ntoso 3.0 with FRBR metadata. It works. It appears in no projection table, and the command's own description lists only `html|text|json|plan`.

It is declared **EXTRA** and reports `UNVERIFIED`: this repo carries no AKN schema and no AKN checker, so well-formedness is the only oracle available and that class cannot license `PASS`. It is surfaced anyway, because a demo whose thesis is "cooperate with the standards" should not be sitting on an unlisted LegalDocML output without saying so.

---

## Reading a phase script

Every one has the same four parts, in the same order:

1. a header comment saying what the stage does and — where the status is not going to be green — why that is the correct outcome rather than a failure;
2. an `--inputs` block that prints the files the driver should digest, and exits;
3. the work, with each command's exit code captured rather than allowed to abort;
4. exactly one `go_receipt` call per exit path.

If you are adding a leg, copy `p7-lts.sh`: it is the shortest one that has a real oracle rather than a weak one, and it shows the cross-check pattern — two independent code paths made to agree on a number — that turns a presence check into a structural one.

---

## See also

- [status-vocabulary.md](status-vocabulary.md) — what each status licenses
- [gates.md](gates.md) — the two human gates and what they certify
- `etc/go/README.md` — invocation, exit codes, environment
