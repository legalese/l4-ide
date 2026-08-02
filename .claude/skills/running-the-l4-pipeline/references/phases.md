# Phases Reference

What each stage of the single-instruction pipeline is for, what it deposits as its interface to the next stage, which of them validate a deposit rather than producing one, and — for the two that still cannot run — exactly what is blocking it.

**Canonical references:**

- The pipeline itself: `specs/todo/single-instruction-demo/SPEC.md`
- What runs today, in the present tense: `specs/todo/single-instruction-demo/ORCHESTRATOR.md`
- The fork representation P4 builds to (R4, ruled 2026-08-02): `specs/todo/single-instruction-demo/R4-FORK-REPRESENTATION.md`

---

## Contents

- [The interface rule](#the-interface-rule)
- [What runs at G1](#what-runs-at-g1)
- [The de novo stages: what they check, and what stays yours](#the-de-novo-stages-what-they-check-and-what-stays-yours)
- [What still refuses, and why](#what-still-refuses-and-why)
- [The seven projection legs](#the-seven-projection-legs)
- [The one leg that is not in the spec](#the-one-leg-that-is-not-in-the-spec)
- [Reading a phase script](#reading-a-phase-script)

---

## The interface rule

SPEC.md states it once and it governs everything: _each stage names its deliverable, and the deliverable is the interface — a later stage may read only what an earlier stage committed._

In the driver this is not a convention, it is the mechanism. A stage's `--inputs` list is what gets digested to decide whether it may replay; if a stage reads something it did not declare, the digest is wrong and the stage will report `replayed` when it should have re-run. Declaring an input and reading an input are the same act, performed twice, and they have to agree.

---

## What runs at G1

G1 is the **replay run**: the subject's committed corpus driven through every projection leg its descriptor declares. No encoding happens. SPEC.md's entry condition for it — PRs #177 and #180 landed — is satisfied.

The corpus modules, cases files and goldens named below are the subject's declarations, resolved from its sidecar (`etc/go/subjects/<id>/`); where a concrete filename helps, the regcf sidecar's values are shown as the worked example.

| stage          | what it does                                                                                                                                                                                         | interface it deposits                                                                                                      |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `p0-preflight` | identifies the tree, the binary, the clock and the corpus by sha256; probes the toolchain; checks the CLI surface the stage table depends on; fires the upgrade tripwire for the `l4 run` workaround | `probes.json`, `cli-surface.txt`, and the corpus hashes every later gate payload is built from                             |
| `p3-check`     | typechecks the subject's declared corpus modules and runs the two mechanisable P3 house-style rules                                                                                                  | `p3-check.txt`                                                                                                             |
| `p6-tests`     | evaluates the corpus's own `#ASSERT` directives and reads `results[]` — **not** the exit code                                                                                                        | one `<module>.run.json` per declared corpus module (regcf: `regcf.run.json`, `regcf-wizard.run.json`), `p6-assertions.txt` |
| `p7-*`         | one script per projection leg, all read-only, each with its own oracle                                                                                                                               | the emitted artifacts and their fidelity reports                                                                           |
| `p9-report`    | renders the conversion report from the journal and checks that every section SPEC.md §P9 requires is present                                                                                         | `report.md`, `report.html`                                                                                                 |

`p0-preflight` and `p3-check` are ungated. Everything from `p6-tests` on is behind HG1.

### The two checks `p3-check` can make, and the one it cannot

P3's house rules are: inert style, `GIVEN` over `ASSUME`, `BRANCH` over `ELSE IF` chains, and an `@ref` FR citation on every dated arm. Two of those are greppable and are checked. The third — "isomorphic, a domain expert can review it section by section against the regulation" — has no mechanical form, and the stage records that fact rather than passing over it in silence.

The `@ref` check is scoped narrowly on purpose: a dated arm is a line comparing `RULES EFFECTIVE DATE` against a `Date` **literal**, excluding comments and `EVAL UNDER RULES EFFECTIVE AT` test directives, and its citation must appear in the same contiguous block. A first attempt used a three-line window and produced twenty false findings, including comment prose and every `#EVAL` line. A check that cries wolf is worse than no check.

---

## The de novo stages: what they check, and what stays yours

**Five of the seven stages that used to refuse now run.** `p1-ingest`, `p2-sweep`, `p3-encode`, `p4-forks` and `p5-gate` are milestone G2's declared members, and each validates a **deposit** rather than producing one: the sidecar's `denovo` section says where the deposit lives, and the stage reports `SKIPPED` when it is not there (a missing prerequisite), `DEGRADED` naming the rules that fired, or `PASS` over an artifact whose sha256 is on the row. The runbook is in SKILL.md; this table says what the stage's oracle does and does not reach.

| stage       | its oracle reaches                                                                                                                                                                                                                                                                                        | what stays yours                                                                                                                                                           |
| ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `p1-ingest` | the bundle satisfies `schemas/source-bundle.schema.json` and its `x-rules`, it is about this subject, every captured document is pinned by digest or by an immutable capture, and a recorded digest is re-hashed against the file                                                                         | **retrieval.** Fetching is an outward network act the orchestrator does not perform, including the archive-fallback route. Whether the bundle is the _right_ text is HG1's |
| `p2-sweep`  | `searches[]` matches `entries[]` in both directions, every routing rule holds, and — with the P1 bundle present — every annotation the inventory declares complete has a disposition                                                                                                                      | **searching**, and judging what a finding means. No procedure enumerates the searches that should have been run, so a register that searched nothing validates cleanly     |
| `p3-encode` | `l4 check` over every deposited module. That is all it is: the compiler's own verdict that the deposit is L4 the toolchain accepts                                                                                                                                                                        | **the encoding.** Isomorphism is HG1's, and the two mechanisable house rules run in `p3-check` over the _committed_ corpus — re-pointing them at a deposit is unbuilt      |
| `p4-forks`  | R4's 1:1 map between a materialised fork and an `Interpretation` field, in both directions; the reading taken is one of the register's live readings; a live reading cites its licence and a non-live one explains itself; cross-references into P2 resolve                                               | **finding the forks**, and **completeness** — unfalsifiable in principle, and carried by HG1                                                                               |
| `p5-gate`   | the cross-file joins over all three deposits at once, which is SPEC.md §4 P5's third check ("disposition of every P2 entry") as an exit code. It **SKIPs** rather than passing when a deposit is missing, because a join whose peer is absent reports `skip` and would leave a green receipt over nothing | **two of the five checks** — fork-register completeness and isomorphism spot-checks — which ride as notes on every receipt it writes, `PASS` included                      |

`p3-check`, `p6-tests` and the p7 legs are **not** wired at G2: they read the subject's committed corpus and goldens, so running them in a de novo run would measure the replay artifacts under a de novo label. `go.sh plan --milestone g2` names each of them as `NOT WIRED` with that reason.

## What still refuses, and why

Two stages exist as entry points and cannot run. Each prints what it would do and what is blocking it, then exits 3. Neither is a member of any milestone's declared stage list, so their absence cannot make a milestone incomplete.

| stage         | blocker                                                                                                                                                                                                                                                                                          |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `p8-verify`   | **R5** ruled 2026-08-02: ROBDD first (unsat/dead-branch/vacuity over the boolean skeleton), fork-space sweep second, external model checker last. Remaining blocker is engineering: no CLI exposes the ROBDD to a script, and SPEC.md §6 gives P8 no pass condition yet. Gates nothing in G0–G4. |
| `p10-publish` | **R1** ruled in full 2026-08-02: the repo is `legalese/canon` (public, Apache-2.0 + carried source-terms, sidecar class/instance layout) — but it does not exist yet, and creating it is an HG2 act. **R2** ruled the same day (probe done, PR #199). Remaining blockers: HG2 + unbuilt tooling. |

The pattern is worth naming: **a stage blocked on an open ruling refuses rather than guesses** — building against an unruled representation is building to be rewritten, and the design's refusal to do that is deliberate rather than incidental. Until 2026-08-02 that covered five of the seven; by end of that day R4, R5, R2 and R1 (in full — `legalese/canon`) were all ruled, so no stage waits on an open ruling. The five de novo stages then shed their remaining blocker the way the design predicted they would: not by taking the network or calling a model, but by splitting the deliverable from its acceptance condition and keeping only the half a script can hold.

Since 2026-08-02, **"no machine-readable format exists" is false everywhere it used to be written.** The three deposit contracts the de novo stages write into — source bundle (P1), external modifications (P2), fork register (P4) — live under `specs/todo/single-instruction-demo/schemas/`, each with worked fixtures, and one validator checks all three. The invocation is in SKILL.md step 9; that is the only copy.

What the formats buy, stage by stage: P1 gets an acceptance condition (a bundle that records how each document was reached, and pins it by digest or by an immutable capture). P2 gets `searches[]`, which is where "what was searched, not only what was found" stops being a hope, plus a completeness join against the bundle's annotation inventory. P4 gets R4's 1:1 map enforced — and a `materialisation` discriminator, because the BNA's twelve ambiguities produced zero runtime forks and a schema demanding an `Interpretation` field of each would have recorded none of them.

What they do not buy: any of the three deliverables. P1 and P2 still need the network and P3/P4 still need a model — the stages check what you deposited, and a stage that has nothing deposited says `SKIPPED` with the path it was looking for.

---

## The seven projection legs

R0 rules that "it renders but cannot execute" is a **defect**, not a caveat. A leg runs iff the subject's descriptor declares it. The statuses below are what that rule looks like when it is applied honestly rather than aspirationally; the status column is what the regcf G1 run **measures**, quoted as the worked example, not what any subject's run is promised.

| leg    | what it emits                                                         | oracle                                                                                                                                                                                                   | status measured on the regcf G1 run                                                                                                                                                                                           |
| ------ | --------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| DMN    | DMN 1.3 XML + fidelity report                                         | canonicalise-then-diff against the subject's declared DMN golden, the `dmn-moddle` interchange gate, and both engine harnesses over the subject's declared cases file (regcf: `regcf-corpus.cases.json`) | `PASS`/`execution` since 2026-08-02 (PR #194 landed regcf's cases file) — both engines agree, 1072/1072 values                                                                                                                |
| dmnmd  | one markdown table + a long loss report                               | differential against the subject's declared golden                                                                                                                                                       | `DEGRADED` — lossy by construction, and no engine executes markdown, so it can never reach the `execution` class                                                                                                              |
| BPMN   | one process per regulative rule (three, in the regcf corpus)          | byte-diff against the subject's declared goldens, then soundness and interchange                                                                                                                         | `DEGRADED` as measured — the wiring was unbuilt at measurement time. Since BUILT and MERGED (PR #198, 2026-08-03): vendor-neutral `businessRuleTask` + a decisionRef resolver checker; the leg re-measures on the next G1 run |
| ladder | the committed SVG figures, regenerated                                | drift: a non-empty `git diff` over the figures directory is a **fail**, never a pass                                                                                                                     | `PASS` with `JL4_LSP_CMD` set; `SKIPPED` otherwise                                                                                                                                                                            |
| LTS    | GraphViz DOT, one `digraph` per regulative rule                       | the `digraph` count must equal the rule count the BPMN discovery call independently reports                                                                                                              | `PASS (INTERIM)` — the proper visualiser is unbuilt and graphviz is the spec's declared stand-in                                                                                                                              |
| MCP    | a deployable zip, and a loopback deployment when a service is running | HTTP 2xx, then the deployment polled to `ready`, then a JSON-RPC `tools/list` **POST** to `.mcp` whose non-generic entries number exactly the deployment's own function count                            | `SKIPPED` without a service                                                                                                                                                                                                   |
| TNR    | nothing                                                               | none reachable                                                                                                                                                                                           | `NOT-REGENERATED` — the NLG goldens come from `cabal test jl4:jl4-test` and this orchestrator never builds                                                                                                                    |
| wizard | the disposition/reachability plan                                     | well-formedness plus measured negative controls                                                                                                                                                          | `DEGRADED` — the plan is not the interview query plan, and the only oracle available is barred from `PASS`                                                                                                                    |

### Why the DMN leg needs a canonicalisation, and why that is not a fudge

The CLI export is **not** byte-identical to the committed golden. Measured on the regcf subject: `l4 export regcf.l4 --to dmn` against its golden, both files are 3,248 lines and 23 of them differ, every one of the form `main.l4:<position>` in the golden against `regcf.l4:<position>` from the CLI, because `jl4/tests/DmnExport.hs:3212` typechecks goldens against an empty virtual file system so no source URI reaches the `@ref` renderer. (`diff | wc -l` is 92 — four output lines per changed line — which is the figure this sentence used to quote as a line count.)

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
