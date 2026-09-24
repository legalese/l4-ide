# `cleanroom-2026-08/report/`

**This directory is NOT the canonical home of this encoding's cost analysis.**
The canonical copy is the deposit in `legalese/canon`, on `mengwong/drafts`:

    subjects/sg/succession/encodings/cleanroom-2026-08/report/README.md

That copy describes a fuller directory — it also holds the run journal, the
pipeline's own cost ledger, and the §8 diff artifacts — and it carries the
priced analysis. **Corrections to a shared claim land there first.** This file
deliberately does not restate the dollar figures, so that it cannot drift out of
agreement with them; there is no second copy of a number to go stale.

What this directory holds, and why each file is here rather than re-derived:

## `run-2026-08-26-003.md`

The conversion report `etc/go/report/render-report.mjs` rendered from run
`2026-08-26-3ab3039f-003`'s journal, over tree `07e0a67d`. **HG1 was WAIVED on
that run, not granted** — the waiver text is in its Gates section and names what
it waived: a domain expert reading the encoding against the four Acts, section
by section. Everything else in it is machine-checkable fact.

Nothing in it was typed. Every figure resolves from a journal row, which is what
makes it re-derivable: `etc/go/go.sh verify --run-id <id> --gates` re-reads the
journal, re-hashes every artifact each receipt names, and recomputes the verdict
without a build, a model or a network call.

A run report ordinarily stays in `$TMPDIR/l4-go/` for exactly that reason. This
copy exists because `$TMPDIR` is swept and the corpus wants one worked example.

**It is a snapshot and it will drift.** It describes the tree at `07e0a67d`. Do
not read a figure out of it as a current fact about this corpus; re-run the
pipeline instead. The one figure that is pinned rather than snapshotted is
`min_assertions`, which lives in the subject sidecar and travels with the
encoding.

## `cost-encoding-window.json`

The cost ledger over the ENCODING window — `2026-08-25T15:40:03Z` to
`2026-08-26T01:27:00Z`, the four-Act run from the instruction that started it to
the end of the pipeline run — built with
`cost-ledger.mjs build --from … --to … --label …`.

This is here because it is the one measurement that cannot be recovered.
`p9-cost` clips to the run's own journal bracket and reports **zero** in that
window: the whole encoding happened before the driver was first invoked, which
the report says in its own words. So the encoding's cost needs a window named by
hand, and the transcripts it reads keep growing.

It carries `standing: "attributed"` and means it. The figures were read out of
301 harness JSONL transcripts, each recorded with its sha256 and byte count so a
second party can repeat the derivation or show that a file moved underneath it.
They are NOT attested: a transcript is an ordinary file. **Never average an
attributed figure with an attested one** — that collapses both to the weaker,
which is the whole failure the two-standings split exists to prevent.

The pipeline's own retrievals are a SEPARATE population again and must never be
added to either: `fetch-sso.py` reports 14 HTTP requests over 7 documents,
2,153 ms, 3.66 MB, and a `curl` inside a shell call is invisible to a tool-name
census of what the model did.

## Where the dollars are

In the canon copy named at the top of this file, with the rate card dated, and
kept out of both ledgers. Token counts can be recomputed from the transcripts
whenever you like; a rate card cannot be recovered from anything once it moves,
so pricing is a third and weaker standing than either ledger carries.
