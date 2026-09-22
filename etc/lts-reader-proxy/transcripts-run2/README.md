# `transcripts-run2` — what RUN 2 (2026-09-21) recorded, and what it did not

Run 1's first commit carried only the scored rows, a reviewer called that unauditable, and the
`transcripts/` directory beside this one was the repair. **Run 2 is a partial repeat of that
mistake, and this file says so rather than letting the omission be discovered later.**

| artefact                                | run 1                       | run 2                |
| --------------------------------------- | --------------------------- | -------------------- |
| scored rows                             | `results.json`              | `results-run2.json`  |
| the exact text each reader was shown    | `transcripts/prompts/`      | **`packets/`, here** |
| each reader's verbatim answers          | `transcripts/readings.json` | **not captured**     |
| each judge's prompt and verbatim output | `transcripts/judge*`        | **not captured**     |
| model ids, timestamps, token usage      | `transcripts/readings.json` | **not captured**     |

So `results-run2.json` can be audited for _what the readers were given_ and for _whether its
arithmetic is right_, and **cannot** be audited for whether a rationale fairly describes the answer
it scores. Run 1 can. Treat any run-2 rationale as the judge's report of an answer nobody else can
now read. Fixing this needs no new experiment — it needs the next run to write the readings and the
judge outputs to a file as it goes, which is what `extract-transcripts.mjs` had to recover after the
fact for run 1.

## `packets/`

Twelve files, one per (contract, artifact) cell; all four readings of a cell — two models × two
repeats — were given the same packet. A packet is the **whole** of what a reader saw:

1. the one-line header `Document`;
2. for **B** and **C** only, the contract's `history.txt` verbatim (the position in plain words);
3. the artifact's full text, from `manifest.json`;
4. the five questions, verbatim from that contract's `truth.json` `questions` array;
5. the instruction _"Answer each question from this document alone. If it does not say, answer
   'cannot tell from this' rather than guess."_

Nothing else: no `truth.json`, no fidelity report, no tools (`grep -rl truth packets/` is empty).

**Two differences from run 1's prompts, both of which weaken row-for-row comparison** (RESULTS.md
§6 states them again where the comparison is made):

- **Run 2's header does not name the artifact kind.** Run 1's prompts said "a plain-text summary
  produced by a legal tool", "a diagram … in the GraphViz DOT language". Run 2's readers were told
  only "Document", so they were **more** blinded than run 1's.
- **`history.txt` names the contract's source file**, so B and C readers see the file name and A
  readers do not. That is unchanged from run 1: the blinding is of the artifact _kind_, not of the
  contract.

## Rebuilding

```
node etc/lts-reader-proxy/transcripts-run2/build-packets.mjs
```

from anywhere; it resolves its own paths. It rewrites `packets/` from the **current**
`manifest.json`, so on an unchanged tree `git diff` is empty and that emptiness is the check that
the committed packets are what the script produces — verified byte-identical, 12/12, when they were
committed. It does **not** re-cut the artifacts: `../prepare.sh` does that, and `manifest.json` has
to be current first or the packets will describe a tree that no longer exists.
