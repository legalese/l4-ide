# docs(specs): land the aug2026 specification record — rulings, programme specs, and the de novo deposit schemas

**What this adds.** This is the `specs/` tree as it stands on `unstable`: 93 changed paths, ~36k
added lines, almost all of it prose. It brings across the design documents and numbered rulings that
the last two months of work were decided by — the DMN export program model (R1–R13), the fidelity
severity axis, the Lexipedia superset programme, the 2026 ladder-diagram design, the
single-instruction demo pipeline — plus a new `specs/research/` tier for investigation records, three
`specs/proposals/` documents (one of them a rejection record), and a `specs/done/` promotion pass that
moves settled specs out of `todo/` and stamps the rest with dated reality banners. It is not purely
prose: `specs/todo/single-instruction-demo/schemas/` carries four JSON Schemas, seven fixtures and an
ssh `allowed_signers` file that the `go` orchestrator reads at runtime.

**Why.** This repo's house rule is that a decision is recorded in the document that owns it, in the
same PR, or it is not decided (CLAUDE.md §4). Two months of rulings were made under that rule on
`unstable` and none of them are on `main`, so `main`'s `specs/` currently answers questions with
stale text: specs marked "todo" that shipped, status banners written in the future tense for things
that now exist, and open rulings that were closed. Concretely, this is where
smucclaw/l4-ide#928 ("Blocking is two different facts") is ruled, where the four rulings blocking
smucclaw/l4-ide#923 are settled and #923 declared unblocked, where the `AND`/`OR`-on-sets reversal
forced by smucclaw/l4-ide#929 is written down, and where smucclaw/l4-ide#921's deliberate
constructor/selector deferral is turned into a design. Without this PR those answers exist only in
PR bodies and commit messages, which is exactly the failure mode CLAUDE.md §4 was written against.

---

## What's in it

### The single-instruction demo pipeline (18 files)

`specs/todo/single-instruction-demo/` — the spec for "SEC Regulation Crowdfunding: go".

- **`SPEC.md`** (729 lines) owns the pipeline-level decisions (R0–R5) and defers per-projection
  rulings to the specs that own them. **`ORCHESTRATOR.md`** (821) is the present-tense inventory of
  what `etc/go/go.sh` actually runs, milestone by milestone. **`EXPLAINER-REPORT-SPEC.md`** (1924) is
  the largest single document here and specifies the lay-and-encoding companion report.
  **`DENOVO-DIFF-ORACLE.md`** (541) specifies §8's acceptance comparator, and
  **`R4-FORK-REPRESENTATION.md`** (166) the `Interpretation` record parameter for ambiguity forks.
- **`schemas/`** — `source-bundle`, `external-modifications`, `fork-register` and `surface-map`
  JSON Schemas (4 files), seven fixtures split valid/invalid, and a README documenting the three
  conventions all four obey: `additionalProperties: false` everywhere, every absence paired with an
  `*_absent_reason`, and cross-field rules declared as `x-rules` that the validator must match
  two-way or refuse to run. **These are executable inputs, not illustrations** — see Independence.
- **`gate-allowed-signers`** — the ssh allowed-signers file for HG1/HG2. It ships **empty of keys,
  deliberately**, so every gated stage refuses with exit 3 and says why.

### The DMN track

- **`DMN-EXPORT-PROGRAM-MODEL-SPEC.md`** (6085 lines) — the single largest file in this PR. It
  replaces the exporter's "global scalars plus decisions over them" program model with un-lambda-lifting,
  and carries the ruling register R1–R13 with each ruling's date, section and state.
- **`FIDELITY-SEVERITY-AXIS-SPEC.md`** (1410) — the ruling on smucclaw/l4-ide#928.
- **`DMN-PHASE5-BUILD-PLAN.md`** (513), **`DMN-RECURSION-FLATTENING-SPEC.md`** (186),
  **`INLINE-DMNMD-SPEC.md`** (254, speculative DX case).

### The Lexipedia superset programme (7 files)

`SPEC.md` (the programme), `CORPUS-TRACK.md` (1529), `EMBEDDABLE.md` (1167),
`LTS-VISUALISER.md` (1062), `LEXIPEDIA-PROBE.md` (602, the read-only R2 reconnaissance),
`PROCESS-TRACK.md` (422), `GUARDED-ROWS.md` (308).

### Ladder diagrams 2026

`ladder-diagrams-2026/DESIGN.md` (1650) and `E1-IDE-INTEGRATION.md` (282).

### Language and tooling design

`SET-OPERATORS-SPEC.md` (2116, including §16's recorded reversal), `SECTION-RANKING-SPEC.md` (1035),
`IN-RELIANCE-ON-SPEC.md` (804), `TEMPORAL-RULE-VERSION-DESIGN.md` (850),
`mlir-parity-fixes.md` (555), `LIBRARY-RESOLUTION-SHADOW-SPEC.md` (406),
`IMPLICIT-PROPS-DESIGN.md` (395), `QUESTION-ORDERING-SPEC.md` (249),
`SUBJECT-TO-NOTWITHSTANDING-SPEC.md` (96), the three
`consider-exhaustiveness-*.md` notes (scope hardening 401, builtin containers 66, imported enums 60),
`housing-act-citizen-wizard-demo.md` (226), and `TIER1-WIP-INDEX.md` (207, the WIP tracker).

### Long-arc spec notes

`corporate-resolutions/SPEC-NOTES.md` (509), `yc-safe/SPEC-NOTES.md` (387),
`godel-loophole/SPEC-NOTES.md` (369) — self-reference in normative systems.

### `specs/research/` — a new tier

A new directory with an explicit charter in its README: **these are not documentation.** They keep
the false starts, the dead ends and the citation traps. Two records: **`DMN-STEELMAN.md`** (1242) and
**`MERMAID-PLAN-B.md`** (332) with its `mermaid-planb/` working set — five `.mmd` sources and
`ghsim.mjs`, which replays GitHub's actual Mermaid rendering pipeline (its version, `initialize()`
config, DOMPurify allowlist and viewscreen CSS) so a candidate can be checked without loading
github.com. The README also fixes a citation convention that the rest of the tree now leans on:
`[V]` read at primary source, `[P]` bibliographic record verified only, `[U]` unverified — **do not
cite**.

### `specs/proposals/` — a new tier (3 files)

`GIVETH-INLINE-TYPE-DECL-SPEC.md` (242, **retained as a rejection record**),
`GIVETH-MULTIPLE-RESULTS-SPEC.md` (214), `VERIFICATION-BACKEND-LOWERING-SPEC.md` (198, lowering L4 to
Z3/Alloy/TLA+/NuSMV/UPPAAL/SPIN/Maude).

### Housekeeping: promotions and reality banners

Sixteen documents now live in `specs/done/` — thirteen moved there from `todo/` with a dated status
banner added, and three (`STATE-AS-LEDGER-SPEC.md` 535, `DEONTIC-PARTY-ACTION-AGREEMENT-SPEC.md` 675,
`NEGATION-AS-FAILURE-SPEC.md` 301) written on `unstable` and landing already-done.
`specs/roadmap/future-features.md` gains an audit banner and two new measured roadmap items.

The 93 changed paths break down as: **16 in-place edits** to documents that already exist on `main`
(`BOUNDED-DEONTICS`, `CHARTING-LIBRARY`, `EVERY-EACH-QUANTIFIER`, `EXCEL-DATE-COMPAT`,
`HOMOICONICITY`, `ISSUE-635-PLANNING-STATUS`, `L4-VERSIONING`, `PARENT-NODE-ASSERTION`,
`PRODUCT-STRATEGY-2025-01`, `STATEFUL-CONTRACT-DEPLOYMENT`, `SUBJECT-TO-NOTWITHSTANDING`,
`TEMPORAL-MASTER`, `TEMPORAL_EVAL_SPEC`, `TEMPORAL_PRELUDE_MACROS`, `UPON-EXTERNAL-EVENTS`, and the
roadmap), **13 `todo/` → `done/` renames**, and **64 new files**. Deletions across the whole PR total
**57 lines**, all of it status text being corrected — nothing is removed.

## Evidence

Quoted from the source PRs and from the documents themselves:

- **Spec staleness audit** (`TIER1-WIP-INDEX.md`): "Audited all 31 todo specs + roadmap. 9 resolved
  specs moved to `specs/done/`; 18 reality-banners added; roadmap annotated." PR #85 then promoted a
  further six: "promote 6 drifted specs to done/ (state-as-ledger, pattern-matching, batch,
  deontic-party-action, negation-as-failure, ref-annotation)".
- **Roadmap audit** (`specs/roadmap/future-features.md`): "roadmap reviewed — 1 of 7 items now
  implemented (plus 1 partial); see per-item annotations."
- **`DMN-STEELMAN.md`**, per the research README: "Are our criticisms of DMN / decision tables
  defensible? (Answer: three of four were **false**.) 82 confidence-marked citations."
- **`FIDELITY-SEVERITY-AXIS-SPEC.md`**: "Thirty-five distinct findings, all dispositioned in §9…
  Three findings were **rejected on measurement**, and the measurements are in §9. One new external
  oracle was run for the revision (`bpmnlint`, §1.8) and found a defect no fidelity note reports."
- **`GIVETH-INLINE-TYPE-DECL-SPEC.md`**: "❌ **REJECTED 2026-07-26** — adversarial review, 5/5 lenses,
  11 fatal findings."
- **The deposit schemas**, per PR #197: "de novo foundations — 3 deposit schemas + validator
  (48 x-rules, selftest 105 ok) + §8 diff oracle (identity 6800/6800; 3 perturbations localize;
  false-green fixed with sensitivity accounting)".
- **`DENOVO-DIFF-ORACLE.md`** reports "80/80 agreement across 4 pairs × 20 battery rows (2026-08-09)"
  and immediately qualifies it: the committed map declares `battery.perturbation.enabled=false`, so
  "0 leaves were perturbed, the Sensitivity table is empty, and the agreement count is unweighted by
  leaf inertness".
- **`LEXIPEDIA-PROBE.md`**: adversarially re-verified by a second independent pass that "found four
  defects and fixed them forward", each recorded inline as a _Verification correction_ block; every
  other measured claim re-derived unchanged. PR #199 summarises: "CC BY-SA 4.0 confirmed, coverage
  diff vs regcf corpus".
- **`mlir-parity-fixes.md`**: "**22/22 Haskell tests pass**" on the merged working tree.
- **#923 unblocked** (PR #161, "rule R3–R6, resolve the cross-ruling interactions, and unblock #923"):
  the spec's §0 states it directly — "Is #923 unblocked? **Yes.**"

Where a status header says BUILT or SHIPPED, it is describing code that lands in a sibling PR, not in
this one.

## Independence

**Buildable and mergeable on its own. Two siblings depend on it; it depends on none of them.**

- **Nothing here is compiled or tested.** No Haskell, no TypeScript, no goldens. On `main`'s CI the
  only job a `specs/`-only change reaches is the docs job, whose substance is `prettier --check .`
  — so the markdown must be clean under the pinned prettier `3.4.2` (CLAUDE.md §3.1); a bare
  `npx prettier` will reformat the tables and fail. `doc/test-docs.sh` link-checks only files under
  `doc/`, so nothing validates the links **out of** `specs/`.
- **`go-pipeline` depends on this PR.** `etc/go/lib/register-validate.mjs` resolves
  `specs/todo/single-instruction-demo/schemas` as its schema directory,
  `etc/go/lib/denovo-diff.mjs` reads `surface-map.schema.json`, `etc/go/selftest.mjs` reads both the
  schemas and the `fixtures/` directory, and `etc/go/gate-verify.sh` names
  `specs/todo/single-instruction-demo/gate-allowed-signers` as its only allowed-signers source. Land
  `go-pipeline` without this and its validator has no schemas, its selftests have no fixtures, and
  HG1/HG2 verification has no signer file to consult. **This PR should land first.**
- **`docs` depends on this PR too.** Four `doc/` pages on `unstable` link to files added here —
  `specs/done/DEONTIC-PARTY-ACTION-AGREEMENT-SPEC.md`, `specs/todo/QUESTION-ORDERING-SPEC.md`,
  `specs/todo/SET-OPERATORS-SPEC.md`, `specs/todo/TEMPORAL-RULE-VERSION-DESIGN.md`. `doc/test-docs.sh`
  treats a relative link with no target as a hard `LINK_ERRORS` failure, so the docs theme goes red if
  it lands first. (A fifth target, `specs/todo/BOUNDED-DEONTICS-SPEC.md`, already exists on `main`.)
- **Status headers describe siblings' code.** Many banners here are written in the present tense
  about code that lives in `dmn-export`, `go-pipeline`, `ladder-viz`, `lang-sets`,
  `lang-syntax-typecheck`, `corpus-regcf`, `bpmn-export`, `mlir` and `agent-tooling`. Landing this
  first makes those sentences forward-looking, which is what CLAUDE.md §4.1 forbids. The cheap,
  honest fix is one dated line at the top of the affected files ("describes work landing in
  `<theme>`"), not rewriting the specs — and it should be reverted as each sibling lands.
- **Outbound cross-references are cosmetic.** Documents here link to `doc/concepts/language-design/`
  pages owned by the **docs** and **papers** themes (notably `dmn-analysis-prior-art.md` and
  `logic-not-flowcharts.md`) and to `.claude/skills/running-the-l4-pipeline/` in **agent-tooling**.
  Nothing checks these, so they degrade to dead links rather than breaking CI, but a reviewer
  following them before those themes land will hit 404s.

## Risk if rejected

The rulings that governed the DMN exporter, the fidelity report, the ladder rewrite and the Reg CF
demo would exist only in PR descriptions and commit messages, so every sibling PR would arrive with
no design document to check the code against and `main`'s `specs/` would keep giving stale answers to
questions it has already settled. It would also break the `go` pipeline outright: `register-validate.mjs`,
`selftest.mjs`, `denovo-diff.mjs` and `gate-verify.sh` all resolve paths inside
`specs/todo/single-instruction-demo/`, so the `go-pipeline` theme cannot run without this one.

## Provenance

Folded in from these `unstable` PRs (only the `specs/` portion of each; most also carry code that
belongs to other themes):

85, 89, 99, 116, 119, 134, 135, 136, 142, 155, 158, 159, 160, 161, 166, 168, 170, 172, 173, 175, 176,
177, 178, 179, 180, 181, 182, 183, 185, 186, 187, 188, 190, 191, 193, 194, 196, 197, 198, 199, 200,
204, 206, 207, 208, 211, 217, 224, 226, 227
