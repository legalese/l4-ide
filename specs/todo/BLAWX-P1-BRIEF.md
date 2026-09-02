# L4.Blawx P1 — implementation brief (PR B)

_Working brief for the Blawx emitter, 2026-08-18. Authority chain:
`specs/todo/BLAWX-EXPORT-SPEC.md` — **read the RULED copy at
`/Users/mengwong/src/legalese/l4wt/blawx-bridge/specs/todo/BLAWX-EXPORT-SPEC.md`** (R1–R14
ANSWERED; the in-tree copy on this branch predates the rulings and the Appendix A
correction) — and `specs/todo/RELATIONAL-M1-BRIEF.md` (the middle-end this consumes, shipped
as PR #272 on this very branch). Where this brief conflicts with the ruled spec, the spec
wins and the conflict is a finding to report._

## What P1 delivers (spec §10, first bullet)

`jl4-core/src/L4/Blawx/{IR,Lower,Emit}.hs` + CLI `l4 blawx FILE [-o FILE] [--scasp]`, seed
corpus under `jl4/examples/blawx/` with goldens in `tests-cli`, and a tier-1 execution
harness. Exit criterion: **every emitted golden executes correctly under tier 1** (raw
s(CASP) queries answer L4-oracle values), plus the R7 numeric-fidelity experiment re-run and
recorded. `renderXml` is P3, NOT this PR — every emitted `xml_content` is the empty string
(R12 delegated sub-decision, consistent with the executed tier-2 smoke). Import is P5.

## Architecture (spec §7, ruled)

- **`IR.hs`** — a **block-level** IR (`BlawxDoc`: ruledoc name, CLEAN `rule_text`,
  workspaces, tests; workspaces are block trees: `BDeclareCategory`, `BDeclareAttribute`,
  `BAttributedRule`, `BFact`, `BQuery`, `BAbducible`, goal nodes). Blocks, not s(CASP): the
  only pivot both wire formats and the P5 import can share.
- **`Lower.hs`** — thin: consumes `L4.Relational.IR.RelProgram` (produced by
  `L4.Relational.Lower`) and **classifies** into a `BlawxDoc`. No relationalization here —
  R2 put DNF/ANF/aggregates/prefixes in the middle-end, and they are there.
- **`Emit.hs`** — `renderScasp` (byte-exact per R10/R12) + `renderBlawxYaml` (the
  import-shaped fixture stream, R1). Line-oriented `Text`, no pretty-printer.
- **CLI** — `jl4/app/L4/Cli/Blawx.hs`, registered in `jl4/app/Main.hs` exactly as
  OpenFisca's four touch points. Default output: the `.blawx` YAML **plus a sibling `.pl`
  dump** of the concatenated s(CASP) (R1 ruled: "dump the pl also alongside"); `--scasp`
  prints the s(CASP) to stdout/`-o`.
- **Tests** — `describe "l4 blawx"` in `jl4/tests-cli/Main.hs` beside the OpenFisca block:
  one `expectGolden` per example, `expectFail` fixtures under `not-ok/`, one structural
  smoke test, one typecheck-failure case, one `--help` listing assertion.

## Consuming RelProgram — the contract M1 wrote for you

Read `L4.Relational.IR`'s module haddock **first**, especially "what an emitter still has to
work out for itself". The load-bearing points, restated:

1. **`RProj` → attribute-predicate goals** (never functor terms): `attr(Subject, Value)` per
   the spec's §4.1/§4.2. The record's field inventory and sorts are in `rpgRecords`.
2. **Sorts**: derivable in one linear pass (head → `rpParams`, `RProj` → `rfSort`, `RCall` →
   callee `rpResult`, `REval`/`RFindAll` → number/list). Do it in `Lower.hs`, once.
3. **Query subjects must be skolemised** (R2-5 contract in the `RFact`/`RQuery` haddock):
   one constant per `(rqId, rvId)` — `age(_G1, 70)` runs and answers a different question.
   The subject's record type is recoverable from its facts' field names.
4. **`REq` is generic equality**: choose the target form by operand sort — s(CASP)
   `#=`/CLP for numbers (R7), `=`/unification for atoms. The IR haddock says every emitter
   must make this choice; make it explicitly and comment it.
5. **Arity ceiling is YOURS**: `loMaxArity` defaults `Nothing` — the middle-end does NOT
   reject arity. Blawx relationships take ≤ 10 arguments; check it in `L4.Blawx.Lower`
   with a named diagnostic.
6. **Stratification**: `rpgStrata` is recorded, not enforced. Blawx v1 REJECTS
   `RUnstratified` with a named diagnostic (spec R2/#258 §2.5 division of labour).
7. **Negation**: the only IR form is `RNotCall`. Map by callee's `RPredKind`:
   `RInput` → classical `-p`; `RComputed`/`RAuxiliary` → NAF `not p` (R5). Comparisons
   already arrive operator-complemented.
8. **Boolean predicates are unary attributes** — `rpResult = Nothing` means no output
   argument, which is exactly Blawx's idiom (M1's R2-1 ruling aligned the fragment with
   this; you inherit no boolean-in-value-position cases).
9. **NLG**: `rpNlg`/`rpRef`/`rfNlg` ride the IR precisely so you need not take
   `Module Resolved` as a second input. `#pred` strings from `rpNlg` when present, else
   prettified from `rnBase`.
10. **Provenance**: `rcProv`/`rpProv` carry `Unique` + `SrcRange` — use them for the R4
    section attribution (which decision cluster a rule belongs to).

## Byte-exactness facts (verified at Blawx checkout `02eded1`; do not re-derive)

The reference checkout is `/Volumes/transcend/src/blawx` (read-only; local branch
`mengwong/main` at `e36ac8f` adds only CLAUDE.md corrections — the corrected CLAUDE.md
there is trustworthy and summarises these). Normative pair for declaration emission:
`scasp_generator.js:927-1156` + **`life_act.yaml`**. **`mortality.yaml` and the other
shipped examples are STALE generator output — never byte-compare against them.**

- One declaration block = **44 lines**: 3 header (comment, `:- dynamic p/N.`, blank-ish
  per generator), **exactly 21 `#pred` NLG annotations**, **exactly 20 temporal frame
  axioms** — emitted in the generator's exact order, INCLUDING its two frame-axiom
  asymmetry quirks (`scasp_generator.js:997-1006` and parallels). Emit the full temporal
  set even though v1 never asserts events: the editor re-emits it on save and the R12
  fixpoint fails otherwise. `'` → `\'` escaping in `#pred` strings ONLY.
- The attributed-rule triple per rule (R6 Mode A): `according_to(sec_N, conclusion…)` /
  `holds :- according_to` bridge / the bare-predicate rule — with the **flattened
  conclusion** (generator's `deconstruct_term`), `% BLAWX CHECK DUPLICATES` exact-line
  dedup markers, and the **two-space indent on the third rule** (byte-significant leak;
  reproduce it).
- Workspace names = predicted AKN eIds + `_section` (`sec_1_section`, …). `rule_text` is
  CLEAN markup per R4: title + **flat numbered sections** (one per `§`-anchored decision
  cluster; modules without `§` get one synthetic section per exported decision);
  declarations go to `root_section`. eId prediction was verified in the tier-2 smoke
  (predicted `sec_1`/`sec_2` matched the container's regenerated AKN exactly).
- `.blawx` wire format (R1): concatenated Django dumpdata YAML, **one `blawx.ruledoc`
  FIRST** (placeholder pk and owner — `/import/` remaps), then workspaces, then tests;
  omit `akoma_ntoso`/`navtree`/`rule_slug`; `\n` newlines; **no trailing newline inside
  the encodings**. A hand-authored exemplar that was ACCEPTED by `/import/` and ran
  correctly is at
  `/private/tmp/claude-502/-Users-mengwong-src-legalese-l4-ide/4638d7ee-14b9-4ef5-8061-36a8c1ced864/scratchpad/benefit.blawx`.
- Names (R3): mangle to `^[a-z]\w*$`, not ending `_\d+` (the UI validator silently
  rewrites violations, breaking the fixpoint); injective collision check per OpenFisca's
  `pyIdent`/`checkCollisions` discipline; reserve Blawx's library predicates (`holds`,
  `according_to`, `blawx_*`, `date_compare`, …) and Prolog keywords.
- Tests (R11): one BlawxTest per `#EVAL`/`#ASSERT` (from `rpgQueries`); test names
  slugified to `[-a-zA-Z0-9_]+`; **assert facts directly in the test body — NEVER emit
  `fact_scenario` rows** (float timestamps, container-TZ, P3D crash landmines). Expected
  values live in the HARNESS, computed from the L4 oracle — never in the `.blawx`.
  `#ASSERT`s additionally emit as `false :- …` constraints (runtime-checked both sides).
- Numbers (R7): cents-as-integers convention where money appears; CLP comparisons; the
  local measurement (`X is 1/3` → `1r3` exact rational) must be RE-RUN as part of P1 and
  recorded — it crashed scasp's second sequential call locally
  (`scasp_solve:stack_parents/3`), so structure the harness one-query-per-process.
- Dates: rejected in v1 with a named diagnostic (`DATE-LIBRARY-SPEC.md` R-D1/R-D4 record
  the eventual convention: functor-wrapped integer POSIX seconds, UTC midnight).

## Tier-1 harness

`swipl` 9.2.9 with the s(CASP) pack is installed on this machine (verified 2026-08-18).
The harness reassembles `reasoner.py`'s load order: harness preamble, vendored Blawx
Prolog libraries (string content of `passthrough.py`/`dates.py`/`aggregates.py`/
`events.py` — vendor with a LOUD provenance comment naming source file + Blawx commit
`02eded1` + the drift risk; NO checksum pin, per R13 as ruled), our emitted encodings,
the test's, the dedup pass — then runs each test query and compares bindings to the
L4-oracle values. A working single-example harness from the design pass is at
`<scratchpad>/benefit_tier1.pl` (answered `Amount = 1000`); generalise it. The harness
lives under `etc/` or beside the examples as a script + vendored fixture, is
**optional-when-present, never a build dependency**, and skips silently when swipl or the
pack is absent. One query per swipl process (see the crash note above).

## Seed corpus (spec §10 P1; mirror `jl4/examples/relational/`)

The four relational seeds that are in the Blawx v1 fragment, copied (not symlinked) into
`jl4/examples/blawx/`: `benefit.l4` (Appendix A — the tier-1/tier-2 smoke already proved
this end-to-end), `mortality.l4`, `scores.l4` (aggregates → the `findall` +
`*_blawx_list` peephole), `sumlist.l4` (structural recursion — the construct Catala must
reject). Keep the `-- L4 oracle ==>` comments; they are the harness's expectations.
`not-ok/`: a dates fixture, an unstratified fixture (Blawx rejects what the middle-end
recorded), an arity>10 relationship fixture. Goldens: the `.blawx` and the `.pl` per
seed, under `expected/`, wired via `tests-cli` `expectGolden`. Check
`etc/check-corpus-goldens.mjs` sweeps (`ok/`, `legal/`, `not-ok/` at the examples root
only) — `jl4/examples/blawx/` is outside them, same bargain as `openfisca/`.

## Facts that will bite (house)

- Repo is `-Wall -Werror`, `NoFieldSelectors` + `OverloadedRecordDot`; `Env` is an `Expr`
  constructor. ONE cabal invocation at a time in this worktree; the dist-newstyle here is
  warm (M1 built in the sibling worktree; this one branched from it — expect a full first
  build, budget for it).
- `jl4/app/Main.hs` + `jl4.cabal`/`jl4-core.cabal` + `jl4/tests-cli/Main.hs` are collision
  surfaces with the open Catala PR #266 — follow OpenFisca's registration pattern exactly
  and keep the diff hunks minimal.
- Exemplars: `L4.OpenFisca.Emit` (line-oriented emission + golden rationale),
  `L4.Docassemble.*` (newest idioms), `L4.Cli.OpenFisca` (CLI verb pattern).
- prettier is pinned 3.4.2 for any markdown; goldens are not markdown.
- Do NOT commit — leave the tree dirty for the coordinator. Scratch in `p1-design/`.

## Definition of done (P1)

`cabal build all` clean under `-Werror`; all suites green including the new tests-cli
goldens; every emitted `.pl` golden executes under the tier-1 harness with every query
answering its L4-oracle value; `benefit.l4`'s emitted `.blawx` diffed against the
design-pass exemplar (`<scratchpad>/benefit.blawx`) with every difference explained; the
44-line declaration blocks byte-diffed against a `life_act.yaml`-derived expectation for
at least one predicate; the R7 measurement re-run and its result recorded in the spec's
§8.8 evidence trail (as a finding for the coordinator to land); no changes outside
`jl4-core/`, `jl4/app/`, `jl4/tests-cli/`, `jl4/examples/blawx/`, `etc/`, and this brief's
directory.
