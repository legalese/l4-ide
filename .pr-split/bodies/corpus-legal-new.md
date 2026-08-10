# corpus(legal): de novo BNA 1981 s 1 and cleanroom Jersey charity test, with their goldens

**What this adds.** Two brand-new statutory corpora under `jl4/examples/legal/`, each encoded from
the primary source by hand and each shipping the four `jl4-test` goldens that keep it honest. The
first, `bna/`, formalises **section 1 of the British Nationality Act 1981** — acquisition of British
citizenship by birth or adoption — in isomorphic inert house style, with 42 `#ASSERT`s, a DMN
projection, fidelity sidecars and a 25-world engine case file. The second,
`charities-cleanroom/`, is a **second, independent encoding of the Charities (Jersey) Law 2014
charity test**, written without sight of the encoding this repo already had, then diffed against it
as a control. After this lands, the repo has both a fresh de novo subject that the demo pipeline can
be smoke-tested against end to end, and — for the first time — a genuine two-encoding control for
measuring how much of an L4 encoding is forced by the statute and how much is the encoder's choice.
The PR also carries five small golden/comment deltas on the pre-existing `promissory-note` and
`ceo-performance-award` examples.

**Why.** Two gaps. First, every corpus in the tree had been encoded by the same hands under the same
house style, so nothing in the repo could distinguish "the statute forces this shape" from "we
always write it this way" — the cleanroom encoding exists to answer that question by construction
rather than by argument. Second, the `go` orchestrator's stages needed a requirements document
written from an actual end-to-end run rather than from a design; `bna/SMOKE-REPORT.md` is that
document, produced by walking a fresh statute through every stage by hand. Both corpora were also
built to be *adversarial* to the toolchain, and both succeeded at that. BNA's projection isolated the
missing `YMD y m d → date("y-m-d")` FEEL lowering — with both engines refusing the whole file over
three dated constants, and a three-line scratch patch proving it was the sole defect. The charities
projection produced three findings at once: the missing `any`/`all` quantifier lowering, the
unsound-under-a-binder parameter lift hiding behind it (smucclaw/l4-ide#936), and — in
`evidence/xmllint-vs-moddle.txt` — `etc/validate-dmn.mjs` printing `OK … 40 decision(s)` on XML that
`xmllint` rejects outright (smucclaw/l4-ide#937). Finally, the two golden-only commits folded in here
(#202, #212) exist because both corpora first landed *without* their `tests/` directories and turned
`unstable` red — the episode that put §3.1 of `CLAUDE.md` on the page.

## What's in it

**`jl4/examples/legal/bna/` — British Nationality Act 1981 s 1 (13 files)**

- `bna.l4` — the encoding: subsections (1), (1A), (2), (3), (3A), (4), (5), (5A), (6) and (7) as
  predicates over two `GIVEN` records (`PersonProfile`, `AdoptionCase`), no top-level `ASSUME`,
  `TIMEZONE IS "Europe/London"`, 42 `#ASSERT` + 1 `#EVAL`. Twelve interpretive choices are recorded
  as machine-greppable `-- AMBIGUITY:` comments at their sites.
- `README.md` (article map, scope-outs, provenance), `source-s1.txt` (the verbatim consolidated
  text with its F1–F19 amendment markers and C1–C5 modification notes, stated as in force
  2026-07-04), and `SMOKE-REPORT.md` — the stage-by-stage ledger that doubles as the requirements
  document for the orchestrator's p1–p8.
- Projections and evidence: `bna.dmn`, `bna.dmn.md`, `bna.fidelity.txt`, `bna.dmn.fidelity.txt`, and
  `bna.cases.json` (25 cases × 43 pins, under the activation contract).
- `tests/bna.{golden,ep.golden,nlg.golden,schema.golden}`.

**`jl4/examples/legal/charities-cleanroom/` — Charities (Jersey) Law 2014, Articles 5–7 (28 files)**

- `charity-test.l4` — 1 428 lines, 45 `@ref` citations, 102 `#ASSERT`s, twelve numbered ambiguities.
- Source and prose: `SOURCE-EXTRACT.md` (the fetched statute with provenance and a quote-hygiene
  statement), `README.md` (article map, ambiguity register, mutation testing, the encoding agent's
  integrity declaration *and the audit of it*), `PROJECTIONS.md`, `COMPARISON.md`.
- `projections/` — the emitted `charity-test.dmn`, two fidelity reports, the `make-cases.py`
  generator, a hand-patched `probe-feel-quantifier.dmn` used to isolate the exporter gap, and eight
  raw engine-evidence transcripts (`evidence/{kie,camunda}.txt`, their `-probe` variants,
  `bpmn-export.txt`, `state-graph.txt`, `validate-dmn.txt`, `xmllint-vs-moddle.txt`).
- `comparison/` — the three-way diff apparatus: `make-surface-map.py`, the generated
  `charity-test.surface-map.json`, and the `denovo-diff.{md,json}` oracle output, unedited.
- `charity-test.cases.json` (25 worlds × 40 decisions, every pin L4-evaluated).
- `tests/charity-test.{golden,ep.golden,nlg.golden,schema.golden}`.

**Five deltas on existing legal examples**

- `promissory-note.l4` — comment sync only: the illustrative `#TRACE` output in the prose was stale,
  and now explains why the residual obligation prints its `PARTY` and `WITHIN` in *evaluated* form
  (the full `Commercial Borrower` value, and `61` rather than the symbolic
  `Default After Days Beyond Commencement`).
- `promissory-note.golden` — the same residual obligation, now rendered on one line, following the
  `prettyLayout` repair.
- `promissory-note.ep.golden` — regenerated after the `Event` exactprint `atFirst` branches were
  un-swapped; every `PARTY … DOES … AT …` event had been printing with its operands rotated one
  keyword slot.
- `ceo-performance-award.schema.golden` — builtin types now emit real JSON Schema
  (`"type": "boolean"`, `"format": "date"`, `items` on `LIST`, `anyOf`+`null` on `MAYBE`) instead of
  dangling `$ref: "#/$defs/BOOLEAN"` with no matching `$defs` entry.
- `ceo-performance-award.cases.json.pending` — a curated parity case file deliberately **not** named
  `.cases.json`, so the parity harness does not auto-load it while the function still refuses on the
  WASM backend. Its `__doc__` block names the two backend gaps that must land before it is renamed.

## Evidence

Quoted from the source PRs.

**BNA, L4 leg (#195):** `l4 check` exit 0, "Check succeeded."; `l4 run` exit 0 with "84 `assertion
satisfied` lines (42 asserts, each printed twice) and 0 `assertion failed`" — deliberately
log-content-gated, because `l4 run` exits 0 even when an assertion fails.

**BNA, engine leg.** As first landed, both engines refused the emitted file on three unlowered dated
constants; a scratch copy with only those three rewritten to FEEL `date("…")` went green:

```
KIE 8.44.0.Final VERDICT: 1 file(s), 25 case(s), 0 error(s), 0 warning(s), 1075/1075 decision(s) SUCCEEDED, 1075/1075 value(s) as expected, 325/325 service output value(s) as expected
Camunda 8.7.6 (zeebe-dmn) VERDICT: 1 file(s), 25 case(s), 1 parsed, 0 error(s), 1075/1075 decision(s) evaluated, 1075/1075 value(s) as expected
```

The committed `bna.dmn` in *this* PR is the re-cut one: #206 reports `bna.fidelity.txt` going
"3 blocking → 0" (78 advisory) once the exporter learned the `YMD` lowering, with the same
1075/1075 on both engines, and `l4 export` reproducing both `bna.dmn` and `bna.fidelity.txt`
byte-for-byte.

**Charities, L4 leg (#201):** `l4 check` "EXIT 0 :: Check succeeded."; `l4 run` "EXIT 0 · #ASSERT in
source 102 | Evaluation blocks 102 | assertion satisfied 102 | assertion failed 0 · diagnostics
above Information: 0".

**Charities, the comparison headline (#201):** the cleanroom and the existing corpus "agree on
**21 221 of 21 420 evaluations (99.07 %)**; the 199 divergences minimise to 60 witnesses and four
root causes, two of them genuine statutory ambiguities that our corpus resolved without recording
that a choice existed."

**Charities, cleanroom integrity audit (#201):** verdict **INDEPENDENT**, on three legs — a tool-log
audit of the encoding agent's 38 tool calls ("not one names a path matching `*charit*` outside its
own output directory"); a mechanical identifier audit ("175 distinct backticked identifiers in the
cleanroom, 92 in `part-3-charity-test.l4`, **exactly four shared** — and all four forced …
**Zero unforced identifiers coincide**"); and a behavioural leg (the cleanroom *refuses* a reading
the corpus took). Quote hygiene: the source was re-fetched independently (HTTP 200, 524 973 bytes)
and "all **62** statutory strings quoted inline in `charity-test.l4`, and all **80** blockquote
paragraphs in `SOURCE-EXTRACT.md`, matched the fetch **verbatim**. **No fabricated quotation.**"

**Charities, engine leg (#201).** Both engines refuse the emitted DMN whole-file. The
cause-isolation probe — only the two quantifier bodies hand-patched to FEEL `some`/`every` —
returns `1000/1000 decision(s)` but only `993/1000 value(s) as expected` on both engines, which
#201 calls "a **second, worse** gap hiding behind" the first: "Fix the first without the second and
a loud refusal becomes a silent wrong answer." The committed `projections/evidence/` transcripts are
that measurement.

**Goldens (#202, #212).** BNA: the four goldens "generated by the suite itself on this tree and
verified green on re-run (`4 examples, 0 failures`, exit 0, `JL4_LIBRARY_PATH` pinned)". Charities:
first run `2250 examples, 4 failures` — all four "Golden file did not exist and was created" —
second run `2250 examples, 0 failures`, exit 0, with "No existing golden moved."

**Label ruling applied to these corpora (#208).** `bna.l4` went from 24 inert strings to 21, of which
18 are label-only; `charity-test.l4` from 69 to 62, of which 38 are label-only. Semantics were
measured, not argued: stripping all 16 operand-joined labels from `bna.l4` left the evaluation output
**byte-identical**. Engine numbers were unmoved (BNA 1075/1075 on both engines), and #208 explicitly
attributes BNA's green to the exporter rather than to the ruling: "the **pre-ruling** `bna.l4`,
emitted with today's binary, produces **0 blocking notes** and KIE `25 / 1075/1075 / 325/325` —
identical."

**The five `promissory-note` / `ceo-performance-award` deltas.** No quantitative claim is made about
them here beyond the suite banners of the PRs that produced them — #125 reports "jl4-core 169/0, jl4
goldens 1120/0" and #214 reports `jl4-test` 2550/0. Both are figures for the whole tree at their
respective tips, not for these files.

## Independence

All 46 files are data or prose under `jl4/examples/legal/`. **No Haskell, no TypeScript, no CI
configuration** — the only executable files are two Python generators (`make-cases.py`,
`make-surface-map.py`) that nothing in the build invokes.

**The two new corpora are self-contained.** They typecheck, run and golden against the language as
`main` already has it: `jl4-test` writes exactly four goldens per `.l4` file (`.golden`,
`.ep.golden`, `.nlg.golden`, `.schema.golden`) and all eight of theirs were produced by the
unmodified suite. Nothing here needs a sibling to land first.

**Three of the five deltas on the pre-existing examples are not.** Each records the output of a code
change that lives elsewhere, and each will mismatch if that theme is dropped:

- **`lang-printer`** — `promissory-note.golden` records the one-line residual obligation the
  `prettyLayout` repair produces (#214).
- **`lang-syntax-typecheck`** — `promissory-note.ep.golden` records the *un-swapped* `Event`
  exactprint order (#125, `jl4-core/src/L4/Syntax.hs`).
- **`service-cli`** — `ceo-performance-award.schema.golden` records the repaired
  `jl4-core/src/L4/JsonSchema.hs` output.

The remaining two are inert: `promissory-note.l4` is a comment-only edit, and
`ceo-performance-award.cases.json.pending` is deliberately named so that no harness loads it.

**`dmn-export` is a softer dependency than it looks.** The committed `bna.dmn`, `bna.fidelity.txt`
and `bna.dmn.fidelity.txt` were re-cut on the exporter *after* the `YMD → FEEL date()` lowering
landed, so without that theme `l4 export` will not reproduce these bytes and the fidelity report will
read 3 blocking notes rather than 0. But no test regenerates them — `jl4-test` writes only the four
`tests/*.golden` files, and the `.dmn` / `.fidelity.txt` sidecars are committed evidence — so the
suite stays green either way. The charities projections are the opposite case entirely: they were cut
*before* the quantifier fix and their whole point is to record the refusal, so they are already
consistent with `main` and need `dmn-export` not at all.

**`go-pipeline` depends on this PR, not the reverse.** `etc/go/phases/p1`–`p4` cite
`bna/SMOKE-REPORT.md` §2 as their requirements source, and the `specs` theme's
`fork-register.valid.json` / `source-bundle.valid.json` fixtures are transcribed from `bna.l4` and
`source-s1.txt` (their own notes say the digest checks report `skip` on branches where those files
are absent, so nothing hard-breaks). In the other direction, `charities-cleanroom/comparison/` cites
`etc/go/lib/denovo-diff.mjs` — a `go-pipeline` file — but only as a reproduction instruction; the
oracle's output is committed here verbatim, so the comparison is readable and auditable without it.

Suggested landing order: `lang-syntax-typecheck`, `lang-printer` and `service-cli` before this one,
`dmn-export` ideally but not necessarily. If any slips, the affected golden can be reverted in this
PR to whatever `main` actually emits; the two new corpora are unaffected either way.

## Risk if rejected

The repo loses its only two-encoding control — nothing else in the tree can tell a statute-forced
encoding decision from a house-style habit — and it loses the two adversarial corpora whose emitted
DMN is the *reason* the `dmn-export` fixes exist, leaving those fixes with no committed artifact
demonstrating the defect they close. It also strands `go-pipeline` and `specs`, whose phase scripts
and fixtures are written against `bna/SMOKE-REPORT.md`, `bna.l4` and `source-s1.txt` by name. Nothing
on `main` stops compiling, but the three golden deltas on the pre-existing `promissory-note` and
`ceo-performance-award` examples would have to be re-homed inside whichever sibling theme carries
their code change, or the golden suite goes red the moment that theme lands.

## Provenance

Unstable PRs folded into this one:

- **#195** — `corpus/bna-smoke`: the de novo BNA 1981 s 1 corpus, its DMN projection, cases and
  `SMOKE-REPORT.md`.
- **#202** — `fix/bna-goldens`: the four `jl4-test` goldens #195 landed without.
- **#201** — `corpus/charities-cleanroom`: the cleanroom Jersey charity-test encoding, its
  projections, engine evidence and three-way comparison.
- **#212** — `fix/charities-goldens`: the four `jl4-test` goldens #201 landed without.
- **#208** — `mengwong/inert-label-truncation`: the enumeration-label ruling applied to `bna.l4` and
  `charity-test.l4` (this theme takes only the corpus half; the Reg CF half and the lint belong to
  `corpus-regcf` and `go-pipeline`).
- **#206** — `mengwong/exporter-fixes`: the BNA projection re-cut on the post-#196 exporter (this
  theme takes only the regenerated `bna.dmn` / fidelity sidecars; the exporter code is
  `dmn-export`).
- **#214** — `mengwong/printer-batch-and-gensym`: the `promissory-note.golden` move (code is
  `lang-printer`).
- **#125** — `mengwong/fix-event-exactprint`: the `promissory-note.ep.golden` regeneration (code is
  `lang-syntax-typecheck`).
- **#190** — `mengwong/mlir-parity-land`: `ceo-performance-award.cases.json.pending`, the pinned
  refusal case file from ledger #8.

Two of the small golden deltas also carry work from unstable merges earlier than the list above —
`ceo-performance-award.schema.golden` from the `fix/schema-eval-robustness` merge, and the
`promissory-note.l4` comment sync from the `fix/deontic-breach-semantics` merge — which the
file-level split assigns here because the affected files are legal-corpus files.
