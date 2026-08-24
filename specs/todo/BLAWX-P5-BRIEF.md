# L4.Blawx P5 — implementation brief (import: Parse, Lift, and the IR extension)

_Working brief for Blawx phase P5, 2026-08-19. Authority chain:
`specs/todo/BLAWX-EXPORT-SPEC.md` (R14 as ruled: `l4 blawx --import`; XML is the canonical
parse source; the block IR is the pivot; "the Blawx project drives [SUBJECT-TO] work
incrementally rather than waiting on it") and the P1/P3 briefs. Full import-scouting
evidence — READ IT FIRST, it is the ground truth this brief compresses:
`/private/tmp/claude-502/-Users-mengwong-src-legalese-l4-ide/4638d7ee-14b9-4ef5-8061-36a8c1ced864/scratchpad/p5-evidence/bird-scout-report.md`_

## Exit (spec §10 P5)

`L4.Blawx.Parse` + `L4.Blawx.Lift`; `lift . emit = id` on the v1 export fragment;
**bird.yaml** (`/Volumes/transcend/src/blawx/blawx/static/blawx/examples/bird.yaml` — NOT
the fixtures/docs decoy) lifted to L4, its four tests re-expressed as `#EVAL`s, and both
engines agreeing on every query.

## Coordinator rulings (under delegated R12/R14 — follow these; conflicts are findings)

- **P5-1: ONE shared IR, extended — never a superset type.** The scout established that
  bird sits largely outside the Mode-A export IR (no `overrules`, no `applies`/`holds`
  goals, no `inapplicable` flag on rules, no span/hierarchical section names, no negated
  queries, no object declarations with NLG). Extend `L4.Blawx.IR` with those constructors.
  The two-renderer contract holds for every new constructor: BOTH `renderScasp` and
  `renderXml` must render it (the shipped generator defines both images — extract them
  from `scasp_generator.js` + `blawx-blocks.js`, exactly as P1/P3 did). The export
  `Lower` never constructs the new ones (Mode A unchanged); **every P1/P3 golden stays
  byte-identical** — that is the regression gate on the extension.
- **P5-2: the regenerate-and-diff staleness cross-check is a WARNING, never a failure.**
  10 of 15 shipped examples carry stale `scasp_encoding` (only `life_act` matches the
  current generator). The warning names the first diverging line.
- **P5-3: `disabled="true"` blocks are SKIPPED, matching the editor, with a warning
  naming each skipped block.**
- **P5-4: `<comment>` text lifts into the L4 output as comments** (prose preserved,
  newlines intact).
- **P5-5: XML parsing is hand-rolled in `jl4-core`** unless the design pass finds a
  genuine blocker: the wild grammar is closed (8 elements:
  `xml block field value statement next mutation comment` — measured over all 1,953
  blocks), the repo precedent is hand-rolled XML emission (`L4.Dmn.Emit`'s local `Xml`
  type), and there is NO XML library anywhere in the current dependency closure
  (`cabal.project` pins `index-state: 2025-03-31T10:46:26Z` if you do end up needing
  one). YAML: the `yaml` package already ships in the `jl4` (CLI) package for Batch — the
  `.blawx` YAML layer may live CLI-side with the XML/block layer in `jl4-core`; design
  decides placement, constraint: `jl4-core` stays lean.

## Architecture

- **`L4.Blawx.Parse`** — `.blawx` dumpdata YAML → per-row `xml_content` → block trees →
  `BlawxDoc`. Wild-XML tolerances the scout measured (all REQUIRED): menu-cache mutation
  attributes ignored (`category_list`/`attribute_list`/`type_list`); 20-char random block
  ids over the full Blockly charset ignored (round-trip compares modulo ids); arbitrary
  and negative `x`/`y`; namespace-tolerant on `<mutation>` (it re-declares xhtml);
  `<comment pinned h w>` with literal newlines; two distinct empty-workspace encodings
  (`''` AND the 61-char bare `<xml xmlns=…></xml>`). YAML traps: `xml_content` is a
  PLAIN multi-line scalar — the dumper hard-wraps at ~80 columns and a spec-compliant
  reader folds the newlines back to spaces (a hand-rolled YAML reader would corrupt every
  field containing a space — use the real parser); model rows are `blawx.ruledoc` /
  `blawx.workspace` / `blawx.blawxtest` only; `akoma_ntoso`/`navtree` optional,
  `rule_slug` never present; pks are arbitrary ints, `owner` dangles; ruledoc-first
  ordering is validated, not assumed. `fact_scenario` is a FIELD of blawxtest (always
  empty in the corpus), not a model.
- **`L4.Blawx.Lift`** — `BlawxDoc` → L4 source text, per R14: ontology → `DECLARE`
  (`object_declaration` NLG carried); stratified ground rules → decisions
  (`OR`-of-bodies); **defeat unfolded to explicit booleans** with `@ref` provenance
  comments (bird's shape: `overrules(s3, s2)` triples + the `applies`-default idiom —
  `sec_5`'s closed-world applicability rule and the `[pingu]` span's
  `holds(logical_negation(applies(NBA 5, pingu)))` carve-out); `not`/`-`/`assume` →
  `negation-as-failure` combinators over `MAYBE BOOLEAN`; CLEAN `rule_text` → `§`
  scaffolding + `@ref`; tests → `#EVAL` with the Blawx run result as the recorded
  expectation. The lift REFUSES gracefully (named diagnostics) on the OUT list: CLP
  residuals, the event/temporal layer (`net30`/`covid_test`/`oasa`/`life_act` date
  blocks), unstratified programs, and `logical_constraints`-style
  unsat-as-expected-result (scout's candidate third OUT entry — record it in the spec's
  §5.2 as a finding).
- **`l4 blawx --import FILE [-o out.l4]`** (R14's ruled surface) in
  `jl4/app/L4/Cli/Blawx.hs`, minimal diff.
- **Properties and evidence**:
  1. `lift . emit = id` (modulo ids/layout/formatting) — property over the four P3 seed
     goldens: emit → parse → the SAME `BlawxDoc` (structural equality on the IR, ignoring
     provenance), plus lift → re-emit → byte-identical `.blawx`. Wire as a tests-cli or
     jl4-core-test case, no foreign toolchain.
  2. **bird**: parse bird.yaml (warning on its stale encodings, per P5-2); lift to
     `jl4/examples/blawx/imported/bird.l4` (committed, with its own goldens for the
     re-emission); re-express its four tests (`is_pingu_a_bird` → model with `A = pingu`;
     `pingu_cant_fly` → `not flies(pingu)` holds; `pingu_on_plane_can_fly`;
     `pingu_with_jetpack_cant_fly`) as `#EVAL`s over the lifted module and verify the L4
     answers match; run the OTHER side by regenerating bird's s(CASP) from parsed blocks
     via our `renderScasp` and driving the four queries through the tier-1 harness —
     both engines local, no container. Negated queries need whatever the IR extension
     gives `BQuery` (a sign/NAF wrapper — part of the extension).
  3. Wild-corpus census smoke: `Parse` (not Lift) runs over ALL 15 shipped examples and
     reports per-example: parsed clean / parsed-with-warnings / refused-with-diagnostic.
     The scout's fragment expectation: 13 of the 14 non-empty examples parse
     (`wills_tutorial` is empty — correct the spec's "13 of 15" while you are in there);
     the date-layer examples parse into the IR but their LIFT refuses.

## The IR extension, concretely (from the scout's census)

New `BBlock`: `overrules` (four children: defeating_rule doc_selector + statement,
defeated_rule + statement), `unattributed_rule` (body + head, the applicability-default
idiom), `object_declaration` (prefix/postfix NLG + category), `holds` (section-attributed
assertion). New `BGoal`: `applies`/`holds`/`according_to` — each takes a section
reference plus a nested statement, which `BTerm` cannot carry; model the payload as a
conclusion-shaped node. `BRule` gains `brInapplicable` (bird s5's checkbox is TRUE — the
whole point of the span). `BSectionRef` gains the span and hierarchy forms
(`sec_5__span_pingu_section`, `sec_34__subsec_1__para_b__subpara_i_section` — a path
representation, keeping `BRoot`/`BSec` as the common cases and the P1/P3 rendering
byte-stable). `BQuery` gains a polarity/NAF wrapper (3 of bird's 4 tests are
`?- not p(…)`). `doc_selector`'s `<mutation section_reference>` + `doc_part_name` field
is the cross-link (it is NOT a menu cache). Dates stay OUT (no `BTerm` date constructor
this phase — the lift refuses the date-layer examples; DATE-LIBRARY-SPEC owns that
future).

**AMENDED 2026-08-19 — the date layer is refused at CLASSIFICATION, not at lift.** Ruling
P5-1's parenthesis above and evidence item 3 both say the date-layer examples "parse into
the IR but their LIFT refuses". Measured, they never reach a `BlawxDoc`: `covid_test`,
`life_act`, `net30` and `oasa` are refused by `L4.Blawx.Parse` with
`ERROR blawx-parse/unsupported-block: … <date_add> is not supported this phase`, owner
`DATE-LIBRARY-SPEC` (18 such diagnostics; `p5-design/census-results.md` §2, and the
spec's §5.2 calibration table records the parse-time cut). These are different diagnostic
surfaces — `l4 blawx --import net30.yaml` reports a **parse** error, not a lift refusal —
so the deviation is written down rather than glossed. The ruling's INTENT (no `BTerm`
date constructor this phase) is honoured exactly; only the layer that says so moved.
Moving the refusal back to the lift is additive and does not violate the two-renderer
contract (`BTDate`/`BTTime`/`BTDatetime`/`BTDuration`; both images exist upstream) — left
to the coordinator, since it buys a better error message and nothing else.

Likewise, **evidence item 3's "13 of the 14 non-empty examples parse" is retired**: at the
block-tree layer the measured answer is **14 of 14**; at the `BlawxDoc` layer it is
**10 of 15**. Both numbers are real and they are not the same number, which is why
`L4.Blawx.Blocks` is a layer of its own.

Renderer images for the new constructors: extract from the generator
(`sCASP['attributed_rule']` already shows the `inapplicable` checkbox handling;
`overrules`/`applies`/`holds`/`according_to`/`unattributed_rule` arms are all in
`scasp_generator.js`) and reproduce byte-exactly, INCLUDING quirks, per R10. The headless
fixpoint harness (`etc/blawx-fixpoint-harness.mjs`) must stay green on the P3 goldens and
extend to the re-emitted bird.

## Facts that will bite (house)

- Repo is `-Wall -Werror`, `NoFieldSelectors` + `OverloadedRecordDot`. **ONE cabal
  invocation at a time in this worktree** (freshly cut — first build is full).
- The IR extension touches files the P4 workflow does NOT touch (IR/EmitXml/Emit vs
  Lower/corpus), but BOTH add tests-cli blocks and P4 may land first — keep hunks
  minimal and mergeable.
- python3.14 has `yaml` but broken `pyexpat`; python3.13 the reverse — if you script
  against the corpus, mind the scout's JSON hand-off pattern (their tools are in the
  session scratchpad: `examples.json`, `census.py`, `pp.py`).
- The reference checkout is READ-ONLY and stays on quirky `mengwong/main`.
- prettier 3.4.2 for markdown. Do NOT commit; scratch in `p5-design/`.

> **Formatting note (2026-08-19).** This file is now prettier-3.4.2-clean, which took four
> edits it is worth knowing about, because the first attempt at running prettier over the
> original **changed its meaning**: a bare `object_declaration` and a later bare
> `logical_` paired into an emphasis span, and prettier rewrote them as
> `object*declaration` / `logical*`. Code spans that straddled a line break
> (`` `xml block field value\nstatement …` ``, `` `jl4/app/L4/Cli/\nBlawx.hs` ``) also
> lost the spaces around their neighbours. The repair is to backtick identifiers
> containing `_` and to keep a code span on one line; the prose is otherwise untouched.
> `specs/` is not in `.prettierignore`, so `format:check` does cover this file.

## Definition of done (workflow's share of P5)

`cabal build all` clean under `-Werror`; all suites green; P1/P3 goldens byte-identical
through the IR extension; `lift . emit = id` property wired and green over the four
seeds; bird.yaml parses (stale-encoding warning), lifts, its four tests agree across both
engines locally, and its re-emission passes the headless fixpoint harness; the
15-example census smoke recorded in `p5-design/census-results.md`; `l4 blawx --import`
registered with refusal/typecheck/help coverage; spec updates in the same change (R14
executed-evidence notes, the §5.2 corrections: 13-of-14 and the `logical_constraints`
OUT candidate); no changes outside `jl4-core/`, `jl4/app/`, `jl4/tests-cli/`,
`jl4/examples/blawx/`, `etc/`, `specs/todo/`, and `p5-design/`. The coordinator then
imports the re-emitted bird into the container, verifies the fixpoint through the real
UI, and writes §10 P5's EXECUTED entry.
