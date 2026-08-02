---
name: running-the-l4-pipeline
description: Drives the single-instruction demo pipeline — the run that takes a body of law from source through an L4 encoding to every projection, gate and conversion report — by dispatching `etc/go/go.sh` and supplying the judgements no script can make. Use when the user says "SEC Regulation Crowdfunding: go" or names another subject the same way, asks to replay the corpus through its projections, asks what a run's verdict or a `DEGRADED`/`NOT-EXECUTABLE` status means, asks to grant or waive a human gate (`HG1`/`HG2`), or asks to resume a run that was interrupted.
---

# Running the L4 Pipeline

The instruction is one line — **"SEC Regulation Crowdfunding: go"** — and it names a pipeline of ten stages that carries a body of law from its source, through an isomorphic L4 encoding, through ambiguity forks and tests and an adversarial gate, out to seven projections, a conversion report and publication. The pipeline is specified in `specs/todo/single-instruction-demo/SPEC.md`. Its driver is `etc/go/go.sh`. This skill is the entry point that maps the instruction to the driver and then does the part the driver cannot: judging.

**Canonical documentation** — always authoritative for what actually runs today:

`specs/todo/single-instruction-demo/ORCHESTRATOR.md`

That spec states, in the present tense and against a named commit, which stages run and which are scaffolded and cannot run. Where this skill disagrees with it, it wins; where it disagrees with the tree, the tree wins. Three deeper references ship in this skill:

- [references/phases.md](references/phases.md) — what each of P0–P10 is for, what it takes as input, what it deposits as its interface, and which of them exist only as entry points that refuse
- [references/status-vocabulary.md](references/status-vocabulary.md) — the eight statuses and the five oracle classes, what each one licenses, and the four situations people most often mis-label
- [references/gates.md](references/gates.md) — HG1 and HG2: what each one is asking a human to certify, how a signature is requested and granted, and when a waiver is the honest move rather than a shortcut

> **The division of labour is the whole design, and it is not negotiable.** Scripts own every fact; this skill owns every judgement.
>
> - **Scripts** run every `l4` and `etc/*.mjs` invocation, interpret every exit code, hash every input and output, and write every status. `etc/go/lib/receipt.mjs` is the only writer of the run journal, and it refuses a receipt whose status is nicer than its evidence.
> - **This skill** decides which model runs which phase, judges the things no oracle can reach — isomorphism against the source text, fork completeness, the §8 triage — and writes the escalation when something goes wrong.
> - **You have no API for asserting a status.** You can run a phase script; the phase script writes the row. If a leg reports `DEGRADED` and you believe it should be green, the move is to fix the leg or record a note, never to relabel the receipt.
> - **You may not append to `journal.ndjson`.** It is hash-chained, and `render-report.mjs` prints a chain-verification failure in the report itself — so hand-editing the journal produces a report that says the journal was hand-edited.

---

## When to use this skill

Reach for this skill when the user wants to:

1. **Run the demo** — "SEC Regulation Crowdfunding: go", or any subject named the same way. That is a milestone-G1 replay run against the committed corpus.
2. **Resume an interrupted run** — a usage limit, a killed terminal, a machine that went to sleep. Re-entry is a digest comparison, not a memory, and every stage whose inputs are unchanged replays instead of re-running.
3. **Understand a verdict** — what `G1 COMPLETE` means when nine of thirteen legs are not green, or why a leg that passed every checker still reports `DEGRADED`.
4. **Grant or waive a human gate** — HG1 before the projections, HG2 before anything outward-facing.
5. **Audit a run somebody else did** — recompute every verdict from the committed artifacts, with no build, no model and no network.

It is the wrong tool for **writing L4**. Encoding a statute, drafting regulative rules, choosing between `IS`/`MEANS`/`IF` — that is [`writing-l4-rules`](../writing-l4-rules/SKILL.md), and this pipeline's de novo encode stage is not built yet anyway. It is also the wrong tool for a one-off projection: if you want a single DMN out of a single file, run `l4 export` directly and skip all of this.

---

## Core workflow

### 1. Point `L4` at a prebuilt binary

The orchestrator **never runs `cabal`.** The build lock is a shared resource, and concurrent invocations inside one worktree corrupt each other with errors that look like code defects and are not.

```bash
export L4=/path/to/dist-newstyle/build/<arch>/ghc-9.10.3/jl4-0.1/x/l4/build/l4/l4
```

**Key idioms:**

- **A sibling worktree usually has one.** `find ~/src/legalese/l4wt -name l4 -type f -path '*x/l4/build*'` will find a binary you can borrow without taking the lock.
- **`JL4_LSP_CMD`** does the same job for the ladder leg, which drives a live `jl4-lsp`. Without it that leg reports `SKIPPED` with a named reason, which is a correct outcome, not a failure.
- **Do not build one to fix a `SKIPPED`.** A skipped leg with a named reason is more honest than a leg that ran under a binary nobody else can reproduce.

### 2. Read the plan before running it

```bash
etc/go/go.sh plan --milestone g1
```

This prints the declared stages in order, which human gate blocks each one, and — separately — the entry points that exist and refuse. Nothing is executed. Read it first when you are unsure what the run is about to touch.

### 3. Run the milestone

```bash
etc/go/go.sh run --milestone g1 --subject regcf
```

Today the only subject that resolves is `regcf`: SPEC.md scopes the demo to 17 CFR Part 227 and nothing beyond it gates acceptance. The run will stop at HG1 and exit 3 — see step 5.

**Key idioms:**

- **`--through STAGE`** stops after a named stage. Useful when you want the encoding checked but not the projections regenerated.
- **`--only STAGE`** runs exactly one. Useful when a single leg failed and you are iterating on it.
- **`--fixed-now ISO8601`** pins the clock threaded into every `run`, `check`, `render` and `batch`. It defaults to a fixed value on purpose: an unpinned clock makes two runs of the same corpus disagree.
- **`L4_GO_REQUIRED=1`** turns every `SKIPPED` into exit 5. That is what CI wants and what a laptop does not.

### 4. Read the statuses, and resist the urge to make them green

A G1 run reports something like:

```
p0-preflight: PASS
p3-check:     DEGRADED
p6-tests:     PASS
p7-dmn:       PASS
p7-bpmn:      DEGRADED
p7-tnr:       NOT-REGENERATED
p7-akn:       UNVERIFIED
go: VERDICT: g1 COMPLETE
```

That is a **successful** run. `COMPLETE` means every declared stage has a receipt, nothing is `BROKEN`, every non-`PASS` receipt carries a reason that appears in the report, and every gate is signed or explicitly waived. It is completeness of accounting, not greenness. (Until 2026-08-02 the `p7-dmn` row here read `NOT-EXECUTABLE` — permitted at G1 only because the report said so in Blocking terms, per SPEC.md §6; PR #194's corpus cases file flipped it to `PASS` with oracle class `execution`.)

**Key idioms:**

- **Never re-run a leg until it goes green.** Rerunning a projection until a regex matches is how `DEGRADED` becomes `PASS` without anything having improved. It is banned, and it is banned because it is the single easiest way to destroy the thing this pipeline is for.
- **A `SKIPPED` leg is a missing tool, not a finding.** Install the tool or leave it skipped; do not reclassify it.
- **A `BROKEN` receipt stops everything.** It means a harness defect — a repo problem — and nothing in the run should be read as a statement about the encoding until it is fixed.
- Full definitions in [references/status-vocabulary.md](references/status-vocabulary.md).

### 5. Grant or waive the gate

```bash
etc/go/gate-request.sh HG1 --run "$TMPDIR/l4-go/<run-id>"
```

That prints a payload derived from the journal — the run, the tree, the sha256 of every corpus file, the receipt hash of every stage so far — and the `ssh-keygen -Y sign` line a human runs out of band. You can verify a signature; you cannot make one.

If no signer is enrolled (the shipped state) the honest alternative is a recorded waiver:

```bash
etc/go/go.sh run --milestone g1 --subject regcf \
  --waive HG1="G1 replays the already-reviewed committed corpus; no new encoding exists for a domain expert to review"
```

**Key idioms:**

- **A waiver is a verdict, not an absence.** It lands on the journal and prints in the report's Gates section with your reason attached. A waiver that is not in the report is impossible.
- **Write the reason for the reader, not for the parser.** Someone will read it a year from now trying to work out whether the gate mattered.
- **HG2 cannot be waived** — `go.sh run --waive HG2=…` exits 2, so this is the driver's rule and not only the skill's. HG1 covers work that has already been reviewed by other means; HG2 covers anything outward-facing, and there is no circumstance in which an agent should decide that on its own. See [references/gates.md](references/gates.md).

### 6. Resume, rather than restart

```bash
etc/go/go.sh run --milestone g1 --subject regcf --run-id <run-id>
```

Each stage declares its own inputs; the driver digests them; an unchanged digest replays the receipt with its verdict intact. A second run back to back re-executes nothing but the report.

**Key idioms:**

- **Resume into the same run id.** A new run id is a new run, and it will redo everything.
- **`p9-report` never replays**, by design: the journal grows while it runs, and a stale report claiming to be current is the worst possible artifact.
- **If a stage re-runs when you expected a replay, an input moved.** That is the digest doing its job. Find out what changed before assuming the driver is wrong.

### 7. Read the report

```
$TMPDIR/l4-go/<run-id>/report.md
```

It is rendered from `journal.ndjson` and nothing else. Sections SPEC.md §P9 requires but this milestone cannot fill render as **ABSENT** with the reason and the stage that would have supplied them — never omitted. Notes you asked a phase script to record render in a block labelled _claimed, not verified_, with the author.

Run directories accumulate. `etc/go/go.sh gc` prunes them, keeping the most recent few **and** every run holding a granted gate — a signature is expensive to obtain and must never be collected.

### 8. Hand it to somebody who should not have to trust you

```bash
etc/go/go.sh verify --run-id <run-id> --gates
```

This re-reads the journal, re-hashes every artifact a receipt names, checks that each granted gate was recorded before the first stage it gates began — counting `stage_end` as well as `stage_begin`, so gated work run outside the driver is caught — and recomputes the milestone verdict. No build, no model, no network. It is the one check the agent that did the run cannot pre-satisfy, and it is what makes the run's claims worth anything to a second party.

---

## Delegating the phases

SPEC.md §7.1 rules that Fable or Opus conducts, delegating to Fable, Opus or Sonnet. The split follows the skill/script boundary exactly.

### What needs no model at all

**Milestone G1 requires zero model calls.** Every stage in it is deterministic: a binary is invoked, an oracle runs, a receipt is written. If you find yourself reasoning about what a G1 leg should report, stop — the leg reports what its oracle returned, and reasoning about it is how a status stops being a function of bytes on disk.

That is the single largest simplification in this design and the first thing a later reader will be tempted to undo. Do not.

### What needs frontier reasoning

| stage               | why it cannot be a script                                                                                                                                                      |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| P3 encode           | "isomorphic — a domain expert can review it section by section against the regulation" has no mechanical form. It is SPEC.md §4's P3 deliverable and SPEC.md §7.3's HG1.       |
| P4 forks            | fork-register **completeness** is unfalsifiable in principle: no procedure establishes that you found every ambiguity.                                                         |
| P5 adversarial gate | its own condition is "as good as it can be", which is a judgement three of whose five checks are joins over registers that have no format yet.                                 |
| §8 triage           | the diff is mechanical; classifying each disagreement as encoding error / genuine ambiguity / improvement over the hand corpus is not, and no diff outcome constitutes a fail. |

All four are **G2** work, and G2 entry is gated on ruling R4, which is open. Today they are entry points that refuse with a named blocker. Run one directly to see it.

### What mid-tier models are for

Mechanical transforms, golden regeneration, formatting, and reading harness output back to a human. None of it touches a status.

### ✔ / ✘ — delegating

```
✔  "Run etc/go/go.sh run --milestone g1 --subject regcf and report the journal's verdict."
✘  "Run the G1 pipeline and tell me whether the DMN projection is good."
```

The second question has no answer the run can give. The DMN leg's `PASS` proves the emitted DMN executed on both engines over the committed cases and agreed; whether the artifact is _good_ — whether its 21 lossy findings are acceptable losses — is a judgement, not an output of this run.

---

## Status anchor

Just enough to read a run's output without a round-trip. Full treatment in [references/status-vocabulary.md](references/status-vocabulary.md).

### The eight statuses

| status            | means                                                                          |
| ----------------- | ------------------------------------------------------------------------------ |
| `PASS`            | an oracle ran, returned 0, and named an artifact whose sha256 is recorded      |
| `DEGRADED`        | the artifact exists; something the spec mandates about it is missing or wrong  |
| `NOT-EXECUTABLE`  | the artifact exists and its own engine cannot run it                           |
| `NOT-REGENERATED` | the artifact exists in the tree; **this run did not produce it**               |
| `UNVERIFIED`      | the artifact exists and no oracle strong enough to license `PASS` is available |
| `NOT-BUILT`       | the capability is named by a spec and has no implementation                    |
| `SKIPPED`         | this machine lacks a named prerequisite                                        |
| `BROKEN`          | the harness itself is defective. A repo defect, fatal everywhere.              |

### The five oracle classes

| class            | proves                                                                | may license `PASS` |
| ---------------- | --------------------------------------------------------------------- | ------------------ |
| `execution`      | the artifact ran on its target engine, on cases, and agreed           | ✔                 |
| `differential`   | it reproduces a committed golden that another gate defends            | ✔                 |
| `structural`     | a checker modelled its semantics, or a counted invariant cross-checks | ✔                 |
| `wellformedness` | it parses                                                             | ✘                  |
| `presence`       | it exists and is non-empty                                            | ✘                  |

The last two are barred by construction. "The XML parses" is not "the XML says what the statute says", and a lattice erodes not because somebody deletes a status but because somebody picks a cheap oracle.

### The four milestone verdicts

| verdict      | exit | means                                                                               |
| ------------ | ---- | ----------------------------------------------------------------------------------- |
| `COMPLETE`   | 0    | every declared stage accounted for, every non-`PASS` explained, every gate resolved |
| `INCOMPLETE` | 1    | a declared stage has no receipt, or a non-`PASS` receipt gave no reason             |
| `GATE`       | 3    | a human gate was not satisfied and the run refused to go past it                    |
| `BROKEN`     | 4    | a harness defect; read nothing here as a statement about the encoding               |

---

## Writing a status

The rule is that a reason is written for the person who reads the report a year from now, and it names what is missing rather than how the run felt about it.

```
✔  "the DMN regenerates identically to the committed golden and passes the interchange
    gate, and it CANNOT BE EXECUTED: neither engine harness can be pointed at it,
    because no cases file for the corpus DMN exists."

✘  "DMN export mostly works but has some issues with execution."
```

The first sentence can be checked by someone who disagrees with it. The second cannot be checked by anyone, which means it is not a status — it is a mood.

(The ✔ example was `p7-dmn`'s real reason until PR #194 landed the corpus cases file on
2026-08-02; the leg now passes. The sentence stays because its checkability is the point.)

---

## Troubleshooting

- **`go.sh: L4 is unset`** — point `L4` at a prebuilt binary. The orchestrator will not build one, and adding a `cabal` call to make this go away will corrupt somebody else's build.
- **`GATE HG1: REFUSED — no signer is enrolled`** — the shipped state. `specs/todo/single-instruction-demo/gate-allowed-signers` carries no public key. Enrol one, or waive with a reason.
- **`the CLI surface the stage table depends on has moved`** (exit 4) — a discovery call returned a set that differs from `etc/go/PINS.json`, and the message names the exact strings. Re-verify the phase scripts against the new surface, then update the pin. Do not update the pin first.
- **`X NO LONGER REPRODUCES`** (exit 4) — a measured defect used as a negative control has been fixed. Delete the entry from `etc/go/known-defects.json`. A stale negative control turns a genuine improvement into a permanent red.
- **`receipt.mjs: REFUSED the receipt for stage …`** (exit 4) — a phase script tried to write a status its evidence does not support. The message lists which rule it broke. This is a defect in the phase script, never a finding about the corpus.
- **A stage re-ran that you expected to replay** — one of its declared inputs changed. `etc/go/go.sh status` shows the receipt count per stage.
- **The report says the chain does not verify** — something other than `receipt.mjs` wrote to `journal.ndjson`. The run's findings are no longer evidence of anything; start a fresh run.

---

## Further reading

`specs/todo/single-instruction-demo/ORCHESTRATOR.md`

`specs/todo/single-instruction-demo/SPEC.md`

`specs/todo/single-instruction-demo/R4-FORK-REPRESENTATION.md`

`etc/go/README.md`

`jl4/examples/legal/regcf/PROJECTIONS.md`

The spec files are ground truth over anything written in this skill. If a command in here has drifted from `etc/go/go.sh`, believe `etc/go/go.sh help` — and fix this file in the same change that revealed the drift, because a stale entry here is worse than a missing one.
