# `etc/lts-reader-proxy` — materials for an LLM-reader PROXY of the §7.3 gate

**Status (2026-09-16): prepared, and run the same day as a proxy — see [`RESULTS.md`](./RESULTS.md),
the scored rows in `results.json`, and the primary evidence under `transcripts/` (every reader's
prompt and verbatim answers, every judge's prompt and verbatim output, model ids; recovered from
the run's transcripts by `extract-transcripts.mjs`, which also checks that `results.json` is the
judges' output and the judges' input is the readers' output).** Nothing in this directory is a
verdict on the gate.

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

| file                   | what                                                                                                                                                          |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `A.txt`                | the `l4 lts` block for the position, default flags (no `--steps`, no `--json`)                                                                                |
| `B.dot`                | the one `digraph` for the rule from `l4 state-graph FILE`                                                                                                     |
| `C.bpmn`               | the P1 BPMN: the golden from `jl4/examples/bpmn/expected/` where one exists (`tenancy`, `every-run-example`), else `l4 export FILE --to bpmn --rule NAME`     |
| `C.fidelity.txt`       | the exporter's fidelity report for `C.bpmn` (golden or freshly cut); not shown to readers                                                                     |
| `history.txt`          | the position in plain words, for B and C readers                                                                                                              |
| `truth.json`           | the five questions, the five answers, and per answer the evidence it was read from                                                                            |
| `lts.json`             | `l4 lts --json` for the position — the Q1–Q3 evidence                                                                                                         |
| `probes.l4`            | the contract (verbatim) plus `#TRACE`s that extend the position by one or two events — the Q2, Q3, Q5 evidence; `probes.out` is their `l4 lts --steps` output |
| `position.l4`/`.trace` | `every-run-example` only: the source file with the appended trace that is the position                                                                        |

`manifest.json` is the reader-facing bundle: twelve entries `{contract, artifact, text, history,
questions, truth}` — the **full** text of each artifact, since a reader sees only what the entry
carries; `history` is `null` for A.

## Regenerating

```
L4=$(cd <worktree with a build> && cabal list-bin l4) etc/lts-reader-proxy/prepare.sh
```

from the repo root; needs `jq` and `node`. The committed artifacts were cut with the `l4` built
from `lts/p2-stack` at `0139c6c5` (re-cut 2026-09-16 on `lts/p2-followups` after the bearer
change: only `probes.out` moved, see RESULTS.md). It rewrites A/B/C, `lts.json`, `probes.out` and
`manifest.json`, and fails if `every-run-example`'s rule stops exporting byte-identically to the
`tenancy-barrier` golden. `truth.json` and `history.txt` are hand-written and are **not**
regenerated: after a rerun, diff `lts.json` and `probes.out` and re-read the answers.

None of the `.l4` files here is under a goldened glob (`CLAUDE.md` §3.1), so they carry no
`tests/` goldens; `probes.l4` is type-checked by hand with `l4 check` before committing.

## Two things seen while preparing, not fixed here

Both are one step _past_ the `tenancy` position and appear in `tenancy/probes.out`, not in any
reader artifact:

1. With Alice paid at 3, the list's what-if for the landlord's receipt is refused with
   `Internal error: amount is not in scope` (`probes.out:15`). The fork's `HENCE` says
   `Receipt (EXACTLY theLandlord) (EXACTLY t) (EXACTLY amount)`, where `amount` is the member's
   own pattern variable, left open for the event to fill; `reifyExpr` (`jl4-core/src/L4/Lts/WhatIf.hs:539`) cannot read it, and the
   replay's error text is printed as the reason. The verdict is right (the act is untried); the
   reason should be the list's own wording.
2. The tick past 7 prints as `the clock reaches 7.5` because the next live deadline is 8 and
   `tickPast` (`WhatIf.hs:278`) goes half-way. By design (§2.4, the P2c block), but a reader will not know that.
