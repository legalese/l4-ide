---
name: running-the-l4-pipeline
description: Drives the single-instruction demo pipeline — the run that takes a body of law from source through an L4 encoding to every projection, gate and conversion report — by dispatching `etc/go/go.sh` and supplying the judgements no script can make. Use when the user issues "⟨body of law⟩: go" — "SEC Regulation Crowdfunding: go" is the historical example, and any other subject named the same way counts — asks to replay a subject's corpus through its projections, asks what a run's verdict or a `DEGRADED`/`NOT-EXECUTABLE` status means, asks to grant or waive a human gate (`HG1`/`HG2`), or asks to resume a run that was interrupted.
---

# Running the L4 Pipeline

The instruction is one line — **"⟨body of law⟩: go"** (historically, "SEC Regulation Crowdfunding: go") — and it names a pipeline of ten stages that carries that body of law from its source, through an isomorphic L4 encoding, through ambiguity forks and tests and an adversarial gate, out to seven projections, a conversion report and publication. The pipeline is specified in `specs/todo/single-instruction-demo/SPEC.md`. Its driver is `etc/go/go.sh`. This skill is the entry point that maps the instruction to the driver and then does the part the driver cannot: judging.

The pipeline is subject-generic; the subject's idiosyncrasies are not. Everything specific to one body of law — which corpus modules and projection legs it declares, its pins, its known defects, its house-rule exceptions and temporal cliffs — lives in a **sidecar** at `etc/go/subjects/<subject>/`, resolved by `etc/go/lib/subject.mjs`. **Read `etc/go/subjects/<subject>/NOTES.md` before running** — it carries that subject's idiosyncrasies, and nothing in this skill repeats them.

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

1. **Run the demo** — "⟨body of law⟩: go" ("SEC Regulation Crowdfunding: go" is the historical example). That is a milestone-G1 replay run against the subject's committed corpus.
2. **Resume an interrupted run** — a usage limit, a killed terminal, a machine that went to sleep. Re-entry is a digest comparison, not a memory, and every stage whose inputs are unchanged replays instead of re-running.
3. **Run the de novo path** — "encode ⟨body of law⟩ from source". That is milestone G2: you fetch, sweep, encode and fork; the stages validate what you deposited. See [the G2 runbook](#the-g2-runbook--the-de-novo-path).
4. **Understand a verdict** — what `G1 COMPLETE` means when nine of thirteen legs are not green, or why a leg that passed every checker still reports `DEGRADED`.
5. **Grant or waive a human gate** — HG1 before the projections, HG2 before anything outward-facing.
6. **Audit a run somebody else did** — recompute every verdict from the committed artifacts, with no build, no model and no network.

It is the wrong tool for **writing L4**. Encoding a statute, drafting regulative rules, choosing between `IS`/`MEANS`/`IF` — that is [`writing-l4-rules`](../writing-l4-rules/SKILL.md). This pipeline's de novo encode stage does not write L4 either; it checks the module you deposited (see the G2 runbook). It is also the wrong tool for a one-off projection: if you want a single DMN out of a single file, run `l4 export` directly and skip all of this.

---

## Core workflow

### 0. Register the subject, if it does not exist yet

Everything the pipeline knows about one body of law lives in a sidecar under `etc/go/subjects/<id>/`. To create one:

```bash
etc/go/go.sh new-subject sg-tax \
  --citation "Income Tax Act 1947" \
  --source-url "https://sso.agc.gov.sg/Act/ITA1947"
```

That is enough to make `plan --subject sg-tax` work immediately, **before any L4 exists**. The sidecar declares `encoding.state: "unwritten"`: the encoding is not written, `encoding.main` is where it _will_ live, and every stage that reads a module reports SKIPPED naming the file to deposit. The gate digest is taken over the absent path, so depositing the first module moves the digest and re-opens HG1 — a gate granted before the encoding existed cannot survive the encoding arriving.

The declaration is checked in both directions. Once the file exists, `subject.mjs` refuses the sidecar until you flip the state to `"written"`, so it cannot rot into a false statement about the tree.

`pins.json` and `known-defects.json` are written **empty and marked unmeasured**, and that is deliberate. Both are measurement records — pins are probed against a real binary, defects are observed on a stated date — so a scaffolder that emitted plausible contents would be manufacturing the evidence the pipeline exists to demand, and it would be believed, because a file that looks measured is indistinguishable from one that is. The stages that need them refuse loudly instead.

Then: write the encoding (that is [`writing-l4-rules`](../writing-l4-rules/SKILL.md), not this skill), flip the state, measure the pins, and declare only the projection legs the subject genuinely supports — the driver declares a stage **iff** its leg is declared, so an omitted leg is an honest silence rather than a failing stage.

### 1. Run the doctor first

```bash
etc/go/go.sh doctor --milestone g1
```

This is the front-door forecast: it says which declared stages will run whole and which will not, each with its remedy, before any stage spends time. Exit 0 = every declared stage's environmental wants are met; 1 = something will not run whole; 2 = no usable `l4` anywhere. It runs no stage, writes no run directory, and sees only the environment — gates, deposit presence and oracle verdicts stay the stages' own account.

The orchestrator **never runs `cabal`.** The build lock is a shared resource, and concurrent invocations inside one worktree corrupt each other with errors that look like code defects and are not. When `L4` or `JL4_LSP_CMD` is unset, `run` and `doctor` **discover** a built binary under `dist-newstyle` — this worktree's own first, then the newest among sibling worktrees — and say so with a `[discovered]` marker. An explicit export always wins:

```bash
export L4=/path/to/dist-newstyle/build/<arch>/ghc-9.10.3/jl4-0.1/x/l4/build/l4/l4
```

**Key idioms:**

- **`JL4_GO_SERVICE_URL` is never discovered.** A deployment target must be named by a human; the MCP deploy half reports `SKIPPED` until one is.
- **Do not build a binary to fix a `SKIPPED`.** A skipped leg with a named reason is more honest than a leg that ran under a binary nobody else can reproduce.

### 2. Read the plan before running it

```bash
etc/go/go.sh plan --milestone g1
```

This prints the declared stages in order, which human gate blocks each one, and — separately — the entry points that exist and refuse. Nothing is executed. Read it first when you are unsure what the run is about to touch.

The declared stage set is the subject descriptor's, not the pipeline's: a projection leg runs iff the subject's `subject.json` declares it, so two subjects' plans — and their `COMPLETE` verdicts — may cover different stage sets.

### 3. Run the milestone

```bash
etc/go/go.sh run --milestone g1 --subject regcf
```

(`--subject regcf` here is the worked example throughout this skill — it is **an** example, never the default. With more than one sidecar committed, `--subject` is mandatory and a bare `run`/`plan`/`doctor` refuses, because a run about an unnamed body of law is not a run about anything.) A subject resolves iff `etc/go/subjects/<id>/` exists and validates — the sidecar carries the subject's descriptor (`subject.json`), pins, known defects and `NOTES.md`. Run `node etc/go/lib/subject.mjs --list` for what is committed rather than trusting a list written here; as at 2026-08-20 it is `regcf` and `sg-succession`. Note that a corpus under `jl4/examples/legal/` is **not** automatically a subject: `bna` and `charities-cleanroom` are committed corpora with no sidecar, so no milestone runs over them, and `etc/check-subject-ci-coverage.mjs` prints that as a note every CI run. The run will stop at HG1 and exit 3 — see step 5.

**Key idioms:**

- **`--through STAGE`** stops after a named stage. Useful when you want the encoding checked but not the projections regenerated.
- **`--only STAGE`** runs exactly one. Useful when a single leg failed and you are iterating on it.
- **`--fixed-now ISO8601`** pins the clock threaded into every `run`, `check`, `render` and `batch`. It defaults to a fixed value on purpose: an unpinned clock makes two runs of the same corpus disagree.
- **`L4_GO_REQUIRED=1`** turns every `SKIPPED` into exit 5. That is what CI wants and what a laptop does not.

### 4. Read the statuses, and resist the urge to make them green

A G1 run reports one row per declared stage. What the regcf sidecar's G1 run measures, as a worked example:

```
p0-preflight: PASS
p3-check:     DEGRADED
p6-tests:     PASS
p7-dmn:       PASS
p7-bpmn:      DEGRADED
p7-tnr:       PASS
p7-akn:       UNVERIFIED
p9-report:    PASS
p9-explain:   DEGRADED
go: VERDICT: g1 COMPLETE
```

That is a **successful** run. `COMPLETE` means every declared stage has a receipt, nothing is `BROKEN`, every non-`PASS` receipt carries a reason that appears in the report, and every gate is signed or explicitly waived. It is completeness of accounting, not greenness. (Until 2026-08-02 the `p7-dmn` row here read `NOT-EXECUTABLE` — permitted at G1 only because the report said so in Blocking terms, per SPEC.md §6; PR #194's corpus cases file flipped it to `PASS` with oracle class `execution`. The `p7-tnr` row read `NOT-REGENERATED` until `l4 nlg` gave the leg something to regenerate; it now reproduces the committed `.nlg.golden`s and carries oracle class `differential`.)

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

Each stage declares its own inputs; the driver digests them; an unchanged digest replays the receipt with its verdict intact — and since 2026-08-20 that lookup crosses run boundaries, so a stage borrows a receipt from an earlier run of the SAME subject when the digest matches. A second run back to back therefore re-executes only the two stages that declare no inputs, plus anything whose digest actually moved. (This sentence was WRONG until 2026-08-20 and is now right by accident: it survived a 2026-08-09 correction that fixed the same claim in ORCHESTRATOR.md but not here, and the cross-run change happens to have made it true.)

**Key idioms:**

- **Resume into the same run id** when you want the same run _directory_ — that is what `--run-id` is for. A new run id is still a distinct run, but since 2026-08-20 it is no longer a redo: eligible stages replay from the earlier run's receipts. The exceptions are `p7-mcp` and `p2-sweep`, which never cross a run boundary because their results are not a function of their declared inputs (`CROSS_RUN_INELIGIBLE` in `etc/go/lib/ledger.mjs` says why), and `p9-report`/`p9-explain`, which declare no inputs and so never replay at all.
- **`p9-report` and `p9-explain` never replay**, by design: each is a function of the journal, the journal grows while it runs, and a stale document claiming to be current is the worst possible artifact. They are the only two stages that declare an empty `--inputs` set, and `etc/go/selftest.mjs` asserts that as a named set rather than as a count.
- **If a stage re-runs when you expected a replay, an input moved.** That is the digest doing its job. Find out what changed before assuming the driver is wrong.

### 7. Read the report

```
$TMPDIR/l4-go/<run-id>/report.md
```

It is rendered from `journal.ndjson` and nothing else. Sections SPEC.md §P9 requires but this milestone cannot fill render as **ABSENT** with the reason and the stage that would have supplied them — never omitted. Notes you asked a phase script to record render in a block labelled _claimed, not verified_, with the author.

Run directories accumulate. `etc/go/go.sh gc` prunes them — run dirs only; the object store has its own sweep, see 7a — keeping the most recent few **of each subject** **and** every run holding a granted gate — a signature is expensive to obtain and must never be collected. Per subject matters once more than one exists: retention used to take the newest few across the whole store, so a burst of runs on one subject would have collected every run of another, and cross-run replay reuses receipts from exactly those older runs.

### 7a. The store: what outlives the run

Run directories are volatile — measured, files in `$TMPDIR` last about two to five days — and that used to take the evidence with them. Artifacts and blessings now also go to a durable store, `$L4_GO_STORE` (default `${XDG_STATE_HOME:-~/.local/state}/l4-go/store`).

```bash
etc/go/go.sh store ls --subject sg-succession
etc/go/go.sh store diff              # witnesses that DISAGREE
etc/go/go.sh store cat <sha256>      # the bytes, if they may be served
etc/go/go.sh store gc --keep-days 90 --dry-run
etc/go/go.sh store verify            # the blessing chain, and every claim in it
```

**`diff` is the point of the store, not `cat`.** The witness key is `(stage, inputs_digest, rel)` — same phase, same declared inputs, same slot — so a key holding two different hashes is a producer that did **not** converge over inputs the pipeline calls identical. That difference is the finding, not the waste: the producers here are agents, and two runs over identical inputs are _expected_ to differ. Exit 1 on any divergence.

Some artifacts embed their own run's path (`p0-preflight`'s `tripwire.json` does), so they can never dedupe and always show as divergent. Those pairs are **labelled `SELF-REFERENTIAL` and never filtered**, with the exact substring that triggered the label — filtering would hide a real finding the day the heuristic is wrong.

**`cat` is default-deny, and that is R11.** An object is servable only if some admission of those bytes was under a **satisfied** blessing. An artifact from an ungated stage, from a refused run, or from any run older than the store has no blessing and is refused. `waived` is an edge and not an absence, so it resolves — but you need `--allow-waived`, and the waiver's reason is printed to stderr, because a waiver is a verdict with a reason attached and that reason belongs in whatever you say about the result.

**`store gc` is not `gc`.** `etc/go/go.sh gc` sweeps run directories, which are a cache. `store gc` sweeps the object store, which is evidence, and it collects by **reachability** before age: blessed bytes and every `covers[]` member are unreachable by any age policy, because they are the one thing R11 exists to keep fetchable.

### 7c. `readset`: what a stage READ, and whether any of it has moved since

Every receipt now carries the **members** of the input set its digest folds, not just the digest. A digest can say _that_ something changed; a read-set says _which_ member changed, and lets three further questions be asked at all.

```bash
etc/go/go.sh readset --subject sg-succession
etc/go/go.sh readset --run-id <run-id> --stage p6-tests --json
```

**Freshness is Make's, and it is derived — never stored.** A member is stale when a newer version of that prerequisite exists: the tree file changed on disk, or a newer artifact was admitted under the same `(subject, stage, rel)`. Recording the answer would freeze the one thing whose whole value is being recomputed. Ordering comes from append order in the store index, never from a timestamp — a clock-derived answer would make the verdict depend on when it was asked.

**A param nobody supplied reads `unknown`, never `current`.** The driver owns the toolchain facts and passes them in (`--param l4-binary=…`). Assuming an unsupplied one unchanged is exactly the bug this closes: the `l4` binary and the stdlib were inputs to every stage, declared by none, and moved without any digest noticing.

**The query resolves a prerequisite the same way a run would.** `readset` runs the driver's own toolchain discovery before asking. An earlier version used a bare `command -v l4` and reported every stage of a clean run stale, because the driver had discovered a binary under a sibling worktree's `dist-newstyle` while the PATH held an unrelated one. Nothing had moved; two resolutions had disagreed.

**`read_set` rides on `stage_end`, including on a replay.** A replayed stage writes no `stage_begin` — it never began — so a read-set carried only there would vanish for exactly the stages whose freshness you most want. Exit 1 if any stage is stale.

A stage that declares **no** inputs has no read-set, and that is deliberate rather than a gap: `p9-report` and `p9-explain` are functions of the journal they are writing into, and a stage cannot digest its own future.

### 7d. `subject-report`: the account of a SUBJECT, not of one run

`p9-report` renders **one run's** journal, and no single run exercises every phase — `sg-succession`'s g1 report marks §P1 and §P2 ABSENT while a g2 report marks the measurement stages SKIPPED, and both are correct about their own run.

```bash
etc/go/go.sh subject-report --subject sg-succession
etc/go/go.sh subject-report --subject regcf --json
```

**The fold is not a union.** A receipt binds to the digest it ran over, so evidence from two runs is jointly meaningful only where both ran over the same inputs. Each phase resolves to exactly one state: `CURRENT`, `STALE`, `NEVER RUN`, plus `NO READ-SET` for a stage that declares no inputs and `UNKNOWN` when some prerequisite could not be evaluated.

**`NEVER RUN` is the state that would have caught R12's failure.** A run report says a phase is "not declared at this milestone" — true, and readable as _"accounted for elsewhere"_ when nothing had accounted for it anywhere. So the phase universe is built widest-first: what the driver says is **declarable**, then what the subject has declared, then what the store has recorded. A universe built only from what has been declared cannot contain the phase nobody ever declared, which is precisely the phase worth naming.

**`STALE` is R4's, not "over an older digest".** A digest can differ with no prerequisite newer, and a prerequisite can be newer with the digest unmoved — that second case is the whole class of bug where the clock, the stdlib and the `IMPORT` closure were real input changes that moved no digest. So staleness is read from read-sets, and the moved member is named.

**The evidence horizon is printed, because a narrowed view must not read as an empty world.** Run journals last about two to five days; the store outlives them but records only stages that produced an artifact, so a SKIPPED stage leaves no trace there. The footer says how many journals were visible and how many were excluded for failing to verify. Exit 1 if any phase is stale.

### 7b. Read the explainer, which is a different document for a different reader

```
$TMPDIR/l4-go/<run-id>/explainer.html   (and explainer.md)
```

`report.md` accounts for the run. `explainer.html` explains **the body of law**, and — interleaved with that — **what happened when somebody made it executable**. It is rendered by `p9-explain` from the journal, from the subject's checked-in narrative under `etc/go/subjects/<id>/explainer/`, and from the artifacts this run's receipts attest.

**Key idioms:**

- **Prose lives in the subject, not in the template.** A narrative file carries its own provenance record naming the sources it was drafted from, with their digests, so a later run detects drift in the narrative, in a source, or in a review that no longer covers the text it signed.
- **Every number in it is checked at render time.** A figure is either a placeholder resolved from the journal or a citation — `[$5,000,000](src:path#L151)` — whose source line the renderer re-opens and matches before printing it. A citation that does not resolve prints the figure followed by a visible complaint and degrades the stage.
- **Unreviewed narrative renders as draft, three times over.** No signer is enrolled today, so every section does, and `p9-explain` rides `DEGRADED` for that reason. That is the correct state, not a near miss.
- **The explainer never links back from the report.** It can legitimately not exist for a run; a report linking to a document that was never produced would be a claim the journal does not support. `go.sh` prints its path at the end of a run instead.
- **Edited the corpus? Re-read the narrative, then re-bless it.** `node etc/go/lib/narrative-provenance.mjs <subject> --check` names every section whose text or cited sources have moved; `--bless` updates the digests and **clears the affected review states**, because a review signed over one text says nothing about another. Do not bless without reading.
- Design and rulings: `specs/todo/single-instruction-demo/EXPLAINER-REPORT-SPEC.md`.

### 8. Hand it to somebody who should not have to trust you

```bash
etc/go/go.sh verify --run-id <run-id> --gates
```

This re-reads the journal, re-hashes every artifact a receipt names, checks that each granted gate was recorded before the first stage it gates began — counting `stage_end` as well as `stage_begin`, so gated work run outside the driver is caught — and recomputes the milestone verdict. No build, no model, no network. It is the one check the agent that did the run cannot pre-satisfy, and it is what makes the run's claims worth anything to a second party.

### 9. Validate any register you wrote by hand

```bash
node etc/go/lib/register-validate.mjs <fork-register|external-modifications|source-bundle> <file> [peer-file ...]
node etc/go/lib/register-validate.mjs --rules <schema>
```

G2 work deposits three registers — the source bundle (P1), the external-modification register (P2), the fork register (P4) — and **you write them, because no stage does**. Their formats live in `specs/todo/single-instruction-demo/schemas/` and this validator is their oracle. Give it the peer files and the cross-file joins run; withhold one and the joins that needed it print `skip` with a reason rather than passing quietly. Fixtures under `schemas/fixtures/` show a valid and an invalid instance of each. Validate before you report anything about a register: several of the schemas' rules exist because one careful human sweep got them wrong.

Calling this validator by hand is the fast inner loop. The **fact** is the receipt the stage writes — see the G2 runbook below.

### 10. Diff a de novo encoding against the corpus (G2 acceptance)

```bash
node etc/go/lib/denovo-diff.mjs run --map <surface-map.json> --out <dir>
```

SPEC.md §8's comparator. It compares two encodings by **what they answer**, never by their text, over a battery seeded from the subject's cases file and perturbed one field at a time. You write the surface map — the declared pairing of decisions and fact slots, schema and fixture in the same `schemas/` directory — and the oracle's job is to disagree with your declaration behaviourally. Exit `1` means it found a divergence, which under §8 is the **better** result, not a failure.

Two things it will not do for you. It **never triages** — every witness reads `UNTRIAGED`, and deciding whether a divergence is an encoding error, a genuine ambiguity or an improvement over the hand corpus is yours. And it cannot tell you about surface it never moved: read the report's **Sensitivity** table with its agreement counts, because a (pair, fact) leaf that was perturbed without ever changing an answer is one where agreement is silence, not evidence. Design and limits: `specs/todo/single-instruction-demo/DENOVO-DIFF-ORACLE.md`.

---

## The G2 runbook — the de novo path

**The shape of every step below is the same: you produce an artifact, you deposit it where the sidecar says, you run the stage, and the receipt is the fact.** P1, P2, P3 and P4 do not fetch, search, encode or find forks — those need the network or a model, and the driver takes neither. Each of them validates a deposit and reports one of three things: `SKIPPED` because the deposit is not there (a missing prerequisite, not a defect), `DEGRADED` naming the rules that fired, or `PASS` over an artifact whose sha256 is on the row.

Start by reading what the subject has and has not deposited:

```bash
etc/go/go.sh plan --milestone g2 --subject <id>
```

Every deposit row reads `present`, `absent` or `undeclared`. `undeclared` means the sidecar does not name that deposit — fix `etc/go/subjects/<id>/subject.json` first, because a stage cannot validate a file nobody named.

**There is no `denovo` object any more, and its removal is the ruling, not a tidy-up.** `denovo` is an ordinal — "the second pass" — and it bundled six keys covering four unrelated kinds of thing. Each now sits under what it _is_:

```json
"natlang_sources": {
  "bundle":   "jl4/examples/legal/<id>/sources/source-bundle.json",
  "register": "jl4/examples/legal/<id>/sources/external-modifications.json"
},
"comparison": {
  "fork_register": "jl4/examples/legal/<id>/sources/fork-register.json",
  "surface_map":   "jl4/examples/legal/<id>/sources/surface-map.json"
},
"encodings": {
  "cleanroom-2026-08": {
    "modules": ["jl4/examples/legal/<id>/cleanroom/<id>-cleanroom.l4"],
    "checks":  { "min_dated_arms": 0, "min_assertions": 39 }
  }
}
```

Those paths need not exist — that is the point.

**An encoding id names an occasion, not a position.** `cleanroom-2026-08` is a fact about the job; "de novo" was a fact about the job's _place in a sequence_, which the graph can answer and a schema key cannot. `primary` is reserved for the committed encoding declared under `encoding`.

**Floors travel with their encoding, structurally.** `encodings.<id>.checks` sits inside the encoding it measures, so a committed floor can no longer be applied to a deposit — which would fail a healthy deposit for not being the committed encoding — and a deposit floor cannot be applied to the committed one, which would let it shrink unnoticed. That used to be a convention the reader had to hold in their head.

**An additional encoding's modules may not name a committed module**: SPEC.md §8 compares the two, and an additional module that _is_ the committed one makes the comparison an identity. The resolver refuses it.

**Selecting one:** `--encoding <id>` names it. `--milestone g2` still works and is translated — it selects the subject's sole additional encoding, and refuses when there is more than one, because an ordinal cannot name one of several. That refusal is the clearest statement of why the rename happened.

Then run the whole thing, or one stage at a time while you iterate:

```bash
etc/go/go.sh run --encoding <enc-id> --subject <id> --only p1-ingest
```

### P1 — fetch with provenance

Fetch the subject's source from its `source_url` and write a `source-bundle`.

**Fetch the instrument it is made under, too.** A regulation is promulgated under a statute, a statutory instrument under a parent Act, a by-law under an ordinance. Fetch that with the same provenance and record it as a document with `role: "instrument"` — the specific empowering provision where the source names one, the enabling Act where it does not.

This is not bookkeeping, and it is not the same job as P2. **You cannot tell whether a word in the subject is compelled or chosen without reading the text above it**, and no other stage looks there: P2 sweeps _forward_ in time for what has happened to a provision since it was printed, never _up_ to its source of authority.

Reg CF is the worked instance. 17 CFR 227.100(a)(2) computes the investment limit from "the greater of" the investor's annual income or net worth. Read alone, that is simply what the law says. Read against 15 U.S.C. 77d(a)(6)(B) it is something else: the statute says only "a given percentage of the annual income or net worth of such investor, as applicable" — **it specifies neither** — and the Commission picked "lesser of" in 2015, held it five years, then reversed to "greater of" in 2021, noting that "[t]he statutory language does not expressly provide that the investor use the lesser of" (86 FR 3496, n.460). So the operative word is a reversible policy choice with a live prior arm, not a statutory command. The corpus built the slow way carries both arms on the rule-version axis (`regcf.l4:405-407`). The de novo run captured three regulations and three corroborations, never reached up, and encoded "greater of" as though the statute had said so.

That is the general shape, and it is why the fetch is not optional: **a regulation's word looks compelled until you read the instrument that did not compel it.**

What the schema makes non-optional is what the BNA smoke run learned the hard way:

- **Archive fallback.** legislation.gov.uk answered an AWS WAF challenge, and the run completed through Wayback captures. Record that as `retrieval_method: "archive"` with the `archive_url` — the schema requires the URL when the method is `archive`, and forbids it otherwise.
- **The in-force banner**, in `in_force` — the "up to date with all changes known to be in force on or before ⟨date⟩" line, or a stated reason there is none. The Jersey charities fetch recorded "Showing the law from 16 October 2025 to Current" instead, which is the same field for a different jurisdiction's phrasing.
- **The annotation inventory.** Amendment and modification markers (the UK's F1–F19 / C1–C5; a jurisdiction's endnote numbers) go in `documents[].annotations[]`, because P2 disposes of them one by one and P5 joins over them. Set `inventory_complete` honestly: `false` obliges you to say why in `inventory_note`, and `true` makes every marker something P2 must dispose of or fail.
- **Integrity.** Either a `sha256` over the bytes you captured, with `local_path` so the validator can re-hash them, or an `archive_url` pinning an immutable capture. Neither is not an option.

Quote hygiene is yours and nothing checks it: every string you later quote in the encoding should be extracted mechanically from this fetch, never reconstructed from memory. Deposit the bundle; run the stage; the receipt is the fact.

### P2 — sweep, and record what you searched

Search for what has happened to the text since it was printed: courts striking, staying or reading down a provision; the regulator's interpretive guidance (for the SEC, C&DIs, no-action letters, staff bulletins); proposed rules, the regulatory agenda, litigation in flight.

**The `searches[]` section is the part people skip, and it is the part that matters.** SPEC.md §4 P2 requires the report to state what was searched, not only what was found — so a search records its scope, its date, and, required, what it does **not** cover. A sweep that found nothing and says so, with its searches enumerated, is a checked claim; a sweep that found nothing and enumerates nothing is an assumption wearing a register's clothes. The stage records `searches` and `entries` as metrics precisely so a reader can see which of the two you wrote.

Then route every finding — binding / interpretive guidance / prospective — and dispose of every annotation the bundle's inventory declares. A binding modification disposed as `encoded` must name where it landed: a `rule_version_arm` (the provision stays encoded, marked inoperative on the rule-version axis, citing the striking authority) or a fork id. Interpretive guidance routes to a fork it opens or settles. An undated prospective change must be flagged as a currency risk with a reason.

Deposit the register; run the stage; the receipt is the fact. Run it **after** P1's bundle exists, or the completeness join over the annotation inventory reports `skip` and the receipt says so.

### P3 — encode

This is [`writing-l4-rules`](../writing-l4-rules/SKILL.md)'s job, not this skill's, and the house rules are SPEC.md §4 P3's: inert style; `GIVEN` over `ASSUME` (unbound assumed terms stall `#EVAL`); `BRANCH` over `ELSE IF` chains; the shipped temporal mechanisms for rule versions, with an `@ref` citation on every dated arm. Encode from the **bundle**, not from the committed corpus — that independence is what the §8 diff is measuring, and reading the corpus destroys it silently and unrecoverably.

Then deposit the module(s) at `denovo.modules` and run `p3-encode`. **Read what its PASS means before you rely on it.** The stage runs `l4 check` and nothing else: it proves the deposit is L4 the toolchain accepts. The two mechanisable house rules live in `p3-check`, which reads the subject's committed corpus — re-pointing it at a de novo deposit is unbuilt — and isomorphism, the actual deliverable, is HG1's. A module that typechecks and says something else entirely reaches the same PASS.

### P4 — forks

Open a fork wherever two readings of the source survive, and record it. R4 is ruled: a materialised fork is one field of an `Interpretation` record threaded as an ordinary `GIVEN`, and the register enforces that map 1:1 — two entries may not claim the same field. Every entry carries the readings, which one you took, and why; a live reading must cite the text that licenses it, and a non-live one must explain its rejection.

`materialisation` is a discriminator, not an assumption. The two inventories anyone has actually produced — the BNA smoke's twelve and the Jersey charities cleanroom's twelve — resolved **every** ambiguity at encode time or delegated it to a fact-supplier, and materialised none. "Twelve forks, none materialised" is a real and interesting result, and the stage records the counts per class so the report can say it.

Cross-reference P2: a fork an authority has already settled carries `settled_by` rather than presenting as open, and the `cross-refs-resolve` join checks that the id it cites is real.

**Cross-reference P1's `instrument` document too, and read the two texts against each other.** Where the subject says something its authorising instrument does not, that is a fork of a distinct kind — not an ambiguity in one text but a disagreement between two, and the reading with the weaker claim may be the one the subject itself states. Record both readings and say which instrument licenses each. If the bundle has no `instrument` document, this check cannot run, and P4 should say so rather than leave a reader to infer the texts agreed. Deposit the register; run the stage; the receipt is the fact.

### P5 — the adversarial gate

`p5-gate` runs the mechanisable third of SPEC.md §4 P5's checklist — the cross-file joins, over all three deposits at once. It **SKIPs rather than passes** when a deposit is missing, because every join needs two of them and a validator run with one file present reports its joins as `skip` and exits 0, which would be a green receipt for a gate that checked nothing.

Two of the five checks are discharged in `p3-check` (house style, temporal closure). **Two are yours**, and they ride on every receipt this stage writes, PASS included: fork-register completeness (unfalsifiable in principle — no procedure establishes that you found every ambiguity) and isomorphism spot-checks against the source. This stage's PASS is not the P5 gate; HG1 is. Do the adversarial review — the BNA run's own §2 ledger is the checklist worth copying: verify every provenance claim against the fetched source it cites, treating quotation marks and pinpoint cites as claims to be string-checked rather than decoration; for every negative assertion whose comment names a cause, check the cause is not overdetermined; and fix legal-fidelity defects by making the encoding match the statute, never by weakening a test.

### §8 — the acceptance diff

Write a surface map (`schemas/surface-map.schema.json`) declaring the pairing between the de novo encoding and the committed corpus, then run the oracle as in step 10 above — or read the receipt of `p8-diff`, the declared g2 stage that has run the same oracle over `denovo.surface_map` since 2026-08-09. Exit `1` means it found a divergence, which is the **better** outcome. Triage each witness yourself; neither the script nor the stage ever will.

### Reading a g2 verdict

`g2 COMPLETE` means every g2 stage is accounted for. It does **not** mean a de novo run happened: a run with every deposit absent reports ten `SKIPPED` receipts — the five deposit validators plus `p3-check`, `p6-tests`, `p7-dmn`, `p8-verify` and `p8-diff`, which all follow the deposit contract since 2026-08-09 — and `COMPLETE`, which is completeness of accounting doing exactly its job. `L4_GO_REQUIRED=1` turns each of those skips into exit 5, which is what CI should want. SPEC.md §6's G2 acceptance is the §8 diff oracle, and the declared stage `p8-diff` calls it over `denovo.surface_map`: read that receipt, including its `perturbation_enabled` metric, before repeating its agreement number. The p7 legs other than DMN are the rows `plan --milestone g2` still names `NOT WIRED`, each with its own reason.

---

## Delegating the phases

SPEC.md §7.1 rules that Fable or Opus conducts, delegating to Fable, Opus or Sonnet. The split follows the skill/script boundary exactly.

### What needs no model at all

**Milestone G1 requires zero model calls.** Every stage in it is deterministic: a binary is invoked, an oracle runs, a receipt is written. If you find yourself reasoning about what a G1 leg should report, stop — the leg reports what its oracle returned, and reasoning about it is how a status stops being a function of bytes on disk.

That is the single largest simplification in this design and the first thing a later reader will be tempted to undo. Do not.

### What needs frontier reasoning

| stage               | why it cannot be a script                                                                                                                                                                                       |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P3 encode           | "isomorphic — a domain expert can review it section by section against the regulation" has no mechanical form. It is SPEC.md §4's P3 deliverable and SPEC.md §7.3's HG1.                                        |
| P4 forks            | fork-register **completeness** is unfalsifiable in principle: no procedure establishes that you found every ambiguity.                                                                                          |
| P5 adversarial gate | its own condition is "as good as it can be", which is a judgement. Two of its five checks are joins over registers whose format landed 2026-08-02 — so those two are exit codes, and the judgement is the rest. |
| §8 triage           | the diff is mechanical; classifying each disagreement as encoding error / genuine ambiguity / improvement over the hand corpus is not, and no diff outcome constitutes a fail.                                  |

All four are **G2** work, and all four are yours rather than the driver's. The stages exist and run: each validates the deposit you produced and reports `SKIPPED`/`DEGRADED`/`PASS` over it. What they cannot do is produce it — P1 and P2 need the network, P3 and P4 need a model — so the judgement above is the work and the stage is the acceptance condition. See the G2 runbook.

### What mid-tier models are for

Mechanical transforms, golden regeneration, formatting, and reading harness output back to a human. None of it touches a status.

### ✔ / ✘ — delegating

```
✔  "Run etc/go/go.sh run --milestone g1 --subject regcf and report the journal's verdict."
✘  "Run the G1 pipeline and tell me whether the DMN projection is good."
```

The second question has no answer the run can give. The DMN leg's `PASS` proves the emitted DMN executed on both engines over the subject's committed cases and agreed; whether the artifact is _good_ — whether its lossy findings (21 of them, in the regcf run) are acceptable losses — is a judgement, not an output of this run.

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

- **`go.sh: L4 is unset, and no built l4 was discovered…`** — discovery found nothing under `dist-newstyle` in this worktree or its siblings. Point `L4` at a prebuilt binary, or build one in a _different_ worktree. The orchestrator will not build one, and adding a `cabal` call to make this go away will corrupt somebody else's build.
- **`GATE HG1: REFUSED — no signer is enrolled`** — the shipped state. `specs/todo/single-instruction-demo/gate-allowed-signers` carries no public key. Enrol one, or waive with a reason.
- **`the CLI surface the stage table depends on has moved`** (exit 4) — a discovery call returned a set that differs from the subject's pins (`etc/go/subjects/<subject>/pins.json`), and the message names the exact strings. Re-verify the phase scripts against the new surface, then update the pin. Do not update the pin first.
- **`X NO LONGER REPRODUCES`** (exit 4) — a measured defect used as a negative control has been fixed. Delete the entry from the subject's `known-defects.json`. A stale negative control turns a genuine improvement into a permanent red.
- **`receipt.mjs: REFUSED the receipt for stage …`** (exit 4) — a phase script tried to write a status its evidence does not support. The message lists which rule it broke. This is a defect in the phase script, never a finding about the corpus.
- **A stage re-ran that you expected to replay** — one of its declared inputs changed. `etc/go/go.sh status` shows the receipt count per stage.
- **The report says the chain does not verify** — something other than `receipt.mjs` wrote to `journal.ndjson`. The run's findings are no longer evidence of anything; start a fresh run.

---

## Further reading

`specs/todo/single-instruction-demo/ORCHESTRATOR.md`

`specs/todo/single-instruction-demo/SPEC.md`

`specs/todo/single-instruction-demo/R4-FORK-REPRESENTATION.md`

`etc/go/README.md`

`etc/go/subjects/<subject>/NOTES.md` — the subject's own idiosyncrasies; regcf's corpus additionally carries `jl4/examples/legal/regcf/PROJECTIONS.md`

The spec files are ground truth over anything written in this skill. If a command in here has drifted from `etc/go/go.sh`, believe `etc/go/go.sh help` — and fix this file in the same change that revealed the drift, because a stale entry here is worse than a missing one.
