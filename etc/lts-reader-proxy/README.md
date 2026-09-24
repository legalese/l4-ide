# `etc/lts-reader-proxy` — materials for an LLM-reader PROXY of the §7.3 gate

**Status: prepared 2026-09-16, and RUN TWICE — 2026-09-16 and 2026-09-21.** Both runs are written
up in [`RESULTS.md`](./RESULTS.md); the scored rows are `results.json` (run 1) and
`results-run2.json` (run 2). Nothing in this directory is a verdict on the gate.

| run   | date       | artifacts the readers saw               | evidence recorded                                                                                                                               |
| ----- | ---------- | --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| run 1 | 2026-09-16 | the **refusing** list; pre-#430 B and C | `transcripts/` — every reader's prompt and verbatim answers, every judge's prompt and output, model ids, recovered by `extract-transcripts.mjs` |
| run 2 | 2026-09-21 | the **repaired** list; re-cut B and C   | `transcripts-run2/` — **the twelve reader packets only.** Answers and judge outputs were not captured; see that directory's `README.md`         |

**The gate was ruled on 2026-09-21 — NO, P2d and P2e are not built** (LTS-VISUALISER.md §7.3). That
ruling cites run 1 as one of four grounds, is explicit that a proxy is not the experiment, and names
three things that would reopen it — the first being a rerun of these same 48 readings against a
repaired `WhatIf`. **Run 2 is that rerun, and it did not confirm the ruling** (RESULTS.md §6.9):
the repaired list is last of the three artifacts on the gate's own Q1–Q3, so the reopening condition
is met on the numbers and the ruling is back with Meng. Read that alongside RESULTS.md §6.2, which
measures a run-to-run drift on unchanged documents larger than the effect the rerun was for. This
directory remains materials and evidence, not a verdict.

**The record is frozen; every artifact `prepare.sh` cuts is not.** `A.txt`, `lts.json`, `B.dot`,
`C.bpmn`, `C.fidelity.txt` and `probes.out` are all regenerated from the corpus, and all of them
are kept current rather than frozen. The record of what the 48 readers were actually shown is
`manifest.json` and `transcripts/` — those are the primary evidence for every score in
`RESULTS.md`, and the regenerated files are not. Do not re-cut `manifest.json` or `transcripts/`
to make the directory self-consistent: that would score 48 committed readings against a packet
nobody read. `prepare.sh` ends with `build-manifest.mjs`, which rewrites `manifest.json` with the
full artifact text, so re-cutting one packet by hand with `prepare.sh`'s own commands is the way
to keep the record intact.

**What has moved since the runs, measured 2026-09-23 rather than assumed.** The four `B.dot` were
re-cut on 2026-09-21 and again on 2026-09-23 from `lts/draw-what-it-means`, where five fixes
changed what `l4 state-graph` writes on a node and on an arrow. **All four `C.bpmn` had also gone
stale** — the same branch un-elided the act, so a task the packets carry as `name="MUST Pay ..."`
now exports as `name="MUST Pay t theLandlord amount"` — and were re-cut on 2026-09-23. Three of
the four `A.txt` were still current; `tenancy/A.txt` went out of date the same day, when
`jl4/examples/bpmn/tenancy.l4` had its ten deprecated `EXACTLY` keywords swept out, and was re-cut
with them. One `B.dot` had already drifted from its own source before any of this
(`contracts/B.dot` said `B must payment OF fine` at a tree that emitted something else).

`specs/todo/lexipedia-superset/LTS-VISUALISER.md` §7.3 gates the two-plane picture (P2d/P2e) on a
**reader** experiment: can readers answer _what do I owe, what discharges it, what breaches it_
from the plain list (`l4 lts`, §7.6), and does a picture add _where am I_ and _what happens
after_ (§1.1a)? No human reader experiment has been run. This directory prepares a **proxy**: fresh
LLM readers, each shown **one** artifact for one contract and nothing else, asked five questions,
scored against a ground truth derived from the evaluator.

## What a proxy of this kind can and cannot say

- It is **not the gate**. §7.3 and §7.4 are about people; the warrant in §7.4 (Maslov & Poelmans)
  is about the _cognitive load_ of novice modellers, which an LLM reader cannot stand in for. A
  proxy result is at most a reason to run, or not bother running, the human experiment.
- Readers of **B** get the `l4 state-graph` **DOT source as text**, not a rendered picture. Every
  edge label, colour and shape is in the text, but nobody is _looking_ at anything, so this
  measures whether the graph's _content_ carries the answer, not whether a drawing helps.
- Readers of **C** get the P1 **BPMN XML** as text, with the same caveat, plus the exporter's own
  losses (`C.fidelity.txt`): no modality, no bearer, deadlines as durations.
- The list (**A**) states its own position; B and C readers get the same history in plain words
  (`history.txt`). The promissory note's list prints day serials; `history.txt` gives the calendar
  conversions to B and C readers, and A readers get only what the list prints.
- The five questions are the same for every contract. Q1–Q3 are §1.1a's three clauses; Q4–Q5 are
  the two things §1.1a says a list cannot do.

## The four contracts and their positions

| dir                 | rule (source)                                                  | position                                                                                  | why this one                                                                                 |
| ------------------- | -------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `contracts`         | `aContract`, `jl4/examples/ok/contracts.l4`                    | the file's own first `#TRACE` (line 23): S delivers at 2, B pays 21 at 4, `WAIT UNTIL` 10 | the file's richest trace; a live obligation in the third link of a HENCE chain               |
| `every-run-example` | `the tenancy`, `doc/reference/regulative/every-run-example.l4` | **appended** (`position.trace`): Alice signs at 1, Bob at 2, Carol not yet; clock 2       | the barrier; the file's own traces both end, so a mid-contract position had to be added      |
| `tenancy`           | `receipts`, `jl4/examples/bpmn/tenancy.l4`                     | the outset, `l4 lts --contract receipts`                                                  | the fork, as the task fixed it                                                               |
| `promissory-note`   | `Payment Obligations`, `jl4/examples/legal/promissory-note.l4` | the file's own second `#TRACE` (line 192): one late payment on 3 April 2025               | a real LEST chain (reparation, then a deadline-free reparation of the reparation), see below |

**Why not a Reg CF rule.** The task asked for a regcf rule with a LEST chain, a BPMN golden and a
runnable `#TRACE`. None exists: `jl4/examples/legal/regcf/regcf.l4`'s three regulative rules
(`advertising restriction`, `ongoing reporting obligation`, `resale restriction`) contain **no
`LEST`** — two are bare `SHANT`s and the third is a `HENCE` cycle — and
`jl4/examples/legal/regcf/denovo/regcf-denovo.l4` has `LEST BREACH … BECAUSE` arms but no
`#TRACE` and no BPMN golden. So the fourth is from `jl4/examples/legal/`, per the task's fallback.

## Files per contract

| file                   | what                                                                                                                                                                                |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `A.txt`                | the `l4 lts` block for the position, default flags (no `--steps`, no `--json`)                                                                                                      |
| `B.dot`                | the one `digraph` for the rule from `l4 state-graph FILE`. **Kept current, so it is no longer the B text the readers saw** — that is in `manifest.json`; see the status block above |
| `C.bpmn`               | the P1 BPMN: the golden from `jl4/examples/bpmn/expected/` where one exists (`tenancy`, `every-run-example`), else `l4 export bpmn FILE --rule NAME`                                |
| `C.fidelity.txt`       | the exporter's fidelity report for `C.bpmn` (golden or freshly cut); not shown to readers                                                                                           |
| `history.txt`          | the position in plain words, for B and C readers                                                                                                                                    |
| `truth.json`           | the five questions, the five answers, and per answer the evidence it was read from                                                                                                  |
| `lts.json`             | `l4 lts --json` for the position — the Q1–Q3 evidence                                                                                                                               |
| `probes.l4`            | the contract (verbatim) plus `#TRACE`s that extend the position by one or two events — the Q2, Q3, Q5 evidence; `probes.out` is their `l4 lts --steps` output                       |
| `position.l4`/`.trace` | `every-run-example` only: the source file with the appended trace that is the position                                                                                              |

`manifest.json` is the reader-facing bundle: twelve entries `{contract, artifact, text, history,
questions, truth}` — the **full** text of each artifact, since a reader sees only what the entry
carries; `history` is `null` for A. `transcripts-run2/build-packets.mjs` turns it into the twelve
packets run 2's readers were actually handed (artifact + history + the five questions + one
instruction, and nothing else); `transcripts-run2/README.md` says what run 2 recorded and what it
did not.

## Regenerating

```
L4=$(cd <worktree with a build> && cabal list-bin l4) etc/lts-reader-proxy/prepare.sh
```

from the repo root; needs `jq` and `node`. It rewrites A/B/C, `lts.json`, `probes.out` and
`manifest.json`, and fails if `every-run-example`'s rule stops exporting byte-identically to the
`tenancy-barrier` golden. `truth.json` and `history.txt` are hand-written and are **not**
regenerated: after a rerun, diff `lts.json` and `probes.out` and re-read the answers. **That last
sentence is the one this directory has already got wrong once — see the note on the promissory
note's key below, and RESULTS.md §6.6.**

**The committed artifacts are the RUN 2 cut (2026-09-21), on this branch's repaired binary.** Run
1's artifacts are not in the tree; `git show e633e2e58` is the diff between them, classified by
cause, and RESULTS.md §6.1 is the summary. The history, for anyone tracing a run-1 number: run 1's
were cut with the `lts/p2-stack` build at `0139c6c5`, re-cut 2026-09-16 on `lts/p2-followups` after
the bearer change (only `probes.out` moved), and `tenancy/probes.out` and
`every-run-example/probes.out` alone were re-cut 2026-09-19 from `lts/p2-followups-2` (item 1
below).

**Which files the run-2 re-cut moved, and which it did not**, because this is what makes the
across-run control in RESULTS.md §6.2 possible: it moved all four `A.txt`, one of four `B.dot`
(`contracts`, a label), three of four `C.bpmn`, and **no `truth.json` and no `history.txt` at all**.
So `every-run-example/B`, `tenancy/B`, `promissory-note/B` and `promissory-note/C` were shown to
run-2 readers byte-identically to run 1 — four cells that measure the instrument rather than the
artifact.

> **The promissory note's key is STILL STALE, and it is now stale against the committed artifact.**
> This warning stood here before run 2 and was not acted on, so it is restated as a defect rather
> than a risk. `promissory-note/truth.json` answers with a reparation deadline of day 739769 /
> 3 June 2025 / 61 days from the position. `12055ae73` (2026-09-17,
> EVERY-EACH-QUANTIFIER-SPEC §5.2) anchors a `LEST` at the missed deadline rather than at the late
> act, so the list says **739752 (44 from now)** — day 102 after commencement, 17 May 2025; see
> `jl4/examples/legal/promissory-note.l4:202-208`. **The 2026-09-21 re-cut moved `A.txt` to 739752
> and left `truth.json` at 739769**, which is exactly the split the `drift` key says must never
> happen, and run 2's readers were marked wrong for printing the artifact's own number: eight of
> A's eleven misses on that contract name the day serial as a ground (RESULTS.md §6.6).
>
> **Fix the key and re-cut in ONE change, before quoting any `promissory-note` column from run 2.** > `truth.json`'s `drift` key spells out the substitutions. Correcting the key without re-cutting A,
> or re-cutting A without correcting the key, puts the two on different trees either way — and the
> second is what happened.

**What run 2 changed in A, and why it is two things and not one.** On 2026-09-21 the what-if
stopped refusing a bound pattern variable and began answering for the SET of acts it describes
(LTS-VISUALISER.md §2.4, the bound-variable block) — §7.7 point 2's repair, and the one line on
three of these four contracts that run 1 traced all eight of the list's Q2 misses to. The same day,
the two lines printed beside a bound act were reworded (`L4.Lts.List.boundLines`). **But the re-cut
also picked up `unstable` drift that is not the repair**: the breach line now appends _"the breach
names, in order: …"_, the note's `LEST` anchor moved (above), and the action text re-renders per
member. RESULTS.md §6.1 has the classification and §6.7.3 has why the breach-names clause matters —
`tenancy` Q3 went 4/4 to 0/4 on it. So "A changed by design" is half true, and the half that is not
is where run 2's most interesting finding is.

**A full `prepare.sh` un-freezes the record**, because it rewrites `manifest.json` along with the
artifacts, and `manifest.json` is what the 48 committed readings were made from. To refresh one
artifact without touching the record — which is what was done for `B.dot` on 2026-09-21 and
2026-09-23 — cut that file alone with the same command `prepare.sh` uses for it, and say in
`RESULTS.md` which artifacts have moved away from the reading.

None of the `.l4` files here is under a goldened glob (`CLAUDE.md` §3.1), so they carry no
`tests/` goldens; `probes.l4` is type-checked by hand with `l4 check` before committing.

## Two things seen while preparing, not fixed here

Both are one step _past_ the `tenancy` position and appear in `tenancy/probes.out`, not in any
reader artifact:

1. With Alice paid at 3, the list's what-if for the landlord's receipt is refused with
   `Internal error: amount is not in scope` (`probes.out:15`). The fork's `HENCE` says
   `Receipt (EXACTLY theLandlord) (EXACTLY t) (EXACTLY amount)`, where `amount` is the member's
   own pattern variable, left open for the event to fill; `reifyExpr` (`jl4-core/src/L4/Lts/WhatIf.hs:539`, as of the run's `0139c6c5`) cannot read it, and the
   replay's error text is printed as the reason. The verdict is right (the act is untried); the
   reason should be the list's own wording. _Fixed 2026-09-19 on `lts/p2-followups-2`
   (`closedAction`, `WhatIf.hs`): the line now reads "the action binds `amount`, which the
   what-if cannot choose". `tenancy/probes.out` and `every-run-example/probes.out` were re-cut
   with that binary — the only two files here it moves, and the same rerun also picks up what
   `unstable` changed since `0139c6c5` (a breach line now lists the names it carries, in order;
   a group's fallback is clocked at the missed deadline). The other artifacts, `manifest.json`
   included, are still the run's: they are what the readers were shown._
2. The tick past 7 prints as `the clock reaches 7.5` because the next live deadline is 8 and
   `tickPast` (`WhatIf.hs:278`, as of `0139c6c5`) goes half-way. By design (§2.4, the P2c block), but a reader will not know that.
