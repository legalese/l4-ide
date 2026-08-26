# `cleanroom-2026-08/report/`

Two artifacts of one pipeline run, kept because neither can be re-derived later.

## `run-2026-08-26-003.md`

The conversion report `etc/go/report/render-report.mjs` rendered from run
`2026-08-26-3ab3039f-003`'s journal, over tree `07e0a67d`. **HG1 was WAIVED on
that run, not granted** — the waiver text is in its Gates section and says what
it waived: a domain expert reading the encoding against the four Acts, section
by section. Everything else in it is machine-checkable fact.

Ordinarily a run report is left in the run directory under `$TMPDIR/l4-go/`,
because it is derivable: `etc/go/go.sh verify --run-id <id> --gates` re-reads
the journal, re-hashes every artifact a receipt names, and recomputes the
verdict without a build, a model or a network call. This copy exists because
`$TMPDIR` is swept and the corpus wants one worked example of what the pipeline
says about it.

**It is a snapshot and it will drift.** It describes the tree at `07e0a67d`.
Do not read a figure out of it as a current fact about this corpus; re-run the
pipeline instead. The one figure that is pinned rather than snapshotted is
`min_assertions`, which lives in the subject sidecar and travels with the
encoding.

## `cost-encoding-window.json`

The cost ledger over the ENCODING window — `2026-08-25T15:40:03Z` to
`2026-08-26T01:27:00Z`, the four-Act run from Meng's "proceed" to the end of the
pipeline run — built with `cost-ledger.mjs build --from … --to … --label …`.

This is here because it is the one measurement that genuinely cannot be
recovered. `p9-cost` clips to the run's own journal bracket, first record to
last, and reports **zero** in that window: the whole encoding happened before
the driver was first invoked, which the report says in its own words. So the
encoding's cost needs a window named by hand, and the transcripts it reads keep
growing.

It carries `standing: "attributed"` and it means it. The figures were read out
of 301 harness JSONL transcripts, each recorded with its sha256 and byte count
so a second party can repeat the derivation or show that a file moved
underneath it. They are NOT attested: a transcript is an ordinary file. Never
average an attributed figure with an attested one — that collapses both to the
weaker, which is the whole failure the two-standings split exists to prevent.

Headline, for the window above: 4,930 API requests, 1,059,035 output tokens
(83,027 of them reasoning), 913M cache reads. 1,142 model-initiated network
calls in 55m37s — 143 web searches, 198 fetches, 801 lawplain MCP calls. Six
workflow fan-outs, 84 agents. Span 9h47m, of which at least 8h29m is measured
tool time — a floor, not an estimate, counting nothing for model reasoning
between two tool calls.

The pipeline's own retrievals are a SEPARATE population and must never be added
to those: `fetch-sso.py` reports 14 HTTP requests over 7 documents, 2,153 ms,
3.66 MB, and a `curl` inside a shell call is invisible to a tool-name census.
