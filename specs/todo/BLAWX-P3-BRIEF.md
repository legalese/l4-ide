# L4.Blawx P3 — implementation brief (renderXml + the re-save fixpoint)

_Working brief for Blawx phase P3, 2026-08-19. Authority chain:
`specs/todo/BLAWX-EXPORT-SPEC.md` (in-tree copy on this branch is current: R1–R14 ANSWERED,
§10 P1/P2 marked EXECUTED) and `specs/todo/BLAWX-P1-BRIEF.md` (the shipped emitter this
extends). Where this brief conflicts with the ruled spec, the spec wins and the conflict is
a finding to report._

## What P3 delivers (spec §10, third bullet)

`renderXml :: BlawxDoc -> Text` — the paired Blockly XML for every workspace AND every
test — plus the arithmetic-image change in `renderScasp` that the fixpoint forces, re-blessed
goldens, and a headless fixpoint harness. Exit criterion (R12): **the re-save fixpoint holds
for every seed workspace** — import, open each workspace in the Blawx editor, save, and the
server-stored `scasp_encoding` is byte-identical to ours. The authoritative UI drive is the
coordinator's job (tier 2, real browser); the workflow's job is to make it true by
construction and prove it headlessly first.

The gate is on `scasp_encoding` ONLY. Re-saved `xml_content` may differ from ours (Blockly
re-serialisation adds menu caches, reorders attributes) — that is expected and out of scope.
Our XML must (a) deserialise cleanly through the restorers and (b) cause
`scasp_generator.js` to regenerate exactly the bytes we stored.

## Sub-deliverable 1: the arithmetic-parenthesization ruling comes due

P1 shipped one documented deviation: `renderScasp` parenthesises minimally; the generator
does not. Verified at `scasp_generator.js:557-561`: `sCASP['math_operation']` emits
`( LEFT op RIGHT )` — every binary node fully parenthesised, **spaces inside the parens**.
The fixpoint decides the ruling: **adopt the generator's image**. Work items:

- Pin down the full image from the generator source: `sCASP['calculation']` (`:551-556`, the
  `Var is Expr` wrapper), `math_operation`, number rendering, and whatever image `BANeg`
  must take (find the block the UI offers for negation — likely `0 - x` or a signed number
  field; if the UI cannot express a form our IR emits, that is a finding, because the
  restorers must round-trip it).
- Change `renderScasp`'s `BArith`/`BGIs` rendering to that image, byte-for-byte. Update the
  `BArith` haddock in `IR.hs` (it currently says "parenthesises minimally").
- Re-bless the four `.pl` + `.blawx` goldens; **read the diffs** — only arithmetic images
  may change, nothing else.
- Re-run the tier-1 harness: all 16 queries must still answer their L4-oracle values
  (parenthesization is semantically inert; prove it, don't assume it).
- Record the ruling in the spec **in this same change**: a dated addendum under §8.12 (it is
  an R12-delegated sub-decision) naming the generator lines and the adopted image.

## Sub-deliverable 2: `renderXml`

New rendering code beside `renderScasp` (same module or a sibling `L4.Blawx.EmitXml`
consumed by `Emit` — decide by size; the IR module haddock's two-renderer contract already
names `renderXml`). It consumes `BlawxDoc` and nothing else. If a datum the XML needs is
missing from the IR, that is a design finding — do not reach around the IR.

**Evidence base** (all in the read-only reference checkout `/Volumes/transcend/src/blawx`,
quirky `mengwong/main`; do not modify it):

- `blawx/static/blawx/examples/life_act.yaml` — the ONLY current-generator XML+scasp pair.
  `mortality.yaml` and the other shipped examples are STALE; never byte-compare against
  them. But note: even life_act's XML carries menu-cache attributes (`category_list`,
  `attribute_list`) because it was UI-saved; the spec verified (§8.12 **[E]**) that the
  restorers synthesise these — **we omit them**.
- `blawx/static/blawx/blawx-blocks.js` — block definitions: field names, mutation
  (`mutationToDom`/`domToMutation`) attribute inventories, statement/value input names.
  The restorers read predicate names from **mutation-restored properties, not fields**
  (`scasp_generator.js:264,683-699` **[E]**) — a block whose mutation is missing or
  mis-attributed regenerates wrong code or none.
- `blawx/static/blawx/scasp_generator.js` — what the regeneration will do to our XML.

**Verified conventions to emit** (spec §8.12; confirm each against the evidence before
coding, and extract the per-block-type templates into `p3-design/xml-plan.md`):

- Envelope `<xml xmlns="https://developers.google.com/blockly/xml">…</xml>`; one `<block>`
  root per canvas stack with `x`/`y` attributes; **single-column auto-layout** (delegated
  ruling, decided): stack the roots down one column with a fixed pitch; exact coordinates
  are not byte-load-bearing (the gate is scasp_encoding) but must be distinct and sane.
- **`<mutation>` before `<field>`** inside a block; `xmlns="http://www.w3.org/1999/xhtml"`
  on every mutation element; mutations carry the predicate/category names the restorers
  need; menu-cache attributes omitted.
- `<next>` chaining for blocks in one stack; `<statement name="…">` for statement inputs;
  `<value name="…">` for value inputs; `<field name="…">text</field>` for fields.
- Observed structural convention (life_act.yaml, verify): the declarations stack of a
  workspace is WRAPPED in an `unattributed_fact` block whose `statements` input holds the
  chained declaration blocks. Establish which of our `BBlock` images are statement-position
  wrappers vs bare roots, for every constructor: declarations, `BAttributedRule` (find the
  `attributed_rule` block's inputs: doc_selector section, conclusion, conditions),
  `BFact`, `BConstraint`, `BAbducible`, and in tests `BQuery`.
- Block `id` attributes: unique within the document; generate DETERMINISTICALLY (goldens
  must be stable) from a counter, in a charset that needs no XML escaping and cannot
  collide with Blockly's own 20-char ids on re-save. Verify Blockly accepts arbitrary id
  strings (it does in upstream Blockly; confirm the vendored version).
- Variables: check how the current generator's XML represents rule variables (a
  `<variables>` header? variable blocks with id refs? plain fields?). life_act.yaml's rule
  workspaces are the witness. Whatever it is, reproduce it — variable identity must survive
  the restorers or the regenerated clause renames/breaks.
- XML escaping: `&`, `<`, `>`, `"` in field text (NLG strings!) escaped per XML; the
  evidence shows `&quot;` in attribute values. Our NLG fields carry user prose — escape
  rigorously.
- Tests: `BlawxTest` rows get `xml_content` too (the test editor is also Blockly and also
  regenerates on save — same data-loss argument). Extract test-editor block types
  (scenario fact blocks, the query block) from the evidence; if life_act.yaml's tests are
  stale-generator, find the freshest witness or derive from `blawx-blocks.js` +
  `scasp_generator.js` and flag the residual risk for the coordinator's browser pass.

**YAML plumbing**: `renderBlawxYaml` swaps `xml_content: ''` for the rendered XML. Choose a
stable YAML scalar encoding for a very long single line (the `|-` block-scalar convention
used for `scasp_encoding` is fine; `/import/` PyYAML-parses, so any valid encoding works —
but pick ONE and keep goldens readable). No trailing newline inside the value.

## Sub-deliverable 3: the headless fixpoint harness

`etc/blawx-fixpoint-harness.mjs` (name it what it is): Node + jsdom, loading the reference
checkout's vendored Blockly + `blawx-blocks.js` + `scasp_generator.js`, then per golden
workspace/test: parse our `xml_content`, `Blockly.Xml.domToWorkspace` into a headless
workspace, run the s(CASP) generator, and byte-diff the result against our
`scasp_encoding`. This exercises the REAL restorers and the REAL generator — it is the
fixpoint minus the browser chrome.

- Posture per R13: optional-when-present, **never a build dependency**; skips silently
  (with a one-line reason) when the checkout or node_modules are absent; loud provenance
  comment naming the Blawx commit (`02eded1`) and the drift risk. Model it on
  `etc/validate-dmn.mjs`'s skip discipline and the tier-1 harness's provenance comment.
- jsdom may need shims (Blockly touches `document`, `navigator`, sometimes canvas). Measure
  early — this is the riskiest unknown in P3. If headless Blockly genuinely cannot load the
  vendored bundle, fall back to driving real headless Chrome (puppeteer-core with
  `executablePath` pointed at the installed Chrome, against a file:// shim page — still no
  server needed) and record why. Do not silently weaken the harness to "XML well-formed".
- Exit for the workflow: **harness green on all four goldens — every workspace and every
  test regenerates our exact bytes.**

## What must NOT change

- `renderScasp` outside the arithmetic image: declaration blocks, rule triples, dedup
  markers, quirks — all stay byte-identical (existing goldens enforce this; the ONLY
  golden churn allowed is arithmetic parens and `xml_content` values).
- `L4.Blawx.Lower`, `L4.Relational.*`, the CLI surface, test registration shape.
- `jl4/examples/blawx/*.l4` seed sources and their `-- L4 oracle ==>` comments.
- The reference checkout (read-only, stays on quirky `mengwong/main`).

## Facts that will bite (house)

- Repo is `-Wall -Werror`, `NoFieldSelectors` + `OverloadedRecordDot`. **ONE cabal
  invocation at a time in this worktree** — it is freshly cut (no `dist-newstyle`), so the
  first build is a full build; budget for it and serialise all building agents.
- prettier pinned 3.4.2 for markdown (the spec edit!); goldens are not markdown.
- tests-cli goldens: `expectGolden` re-blessing writes `.actual` first; read every diff
  before promoting. Blessing output you have not read is how a wrong answer becomes the
  expected answer.
- Do NOT commit — leave the tree dirty for the coordinator. Scratch in `p3-design/`.
- The tier-1 harness command lines are in `etc/blawx-tier1-harness.py`'s header; one query
  per swipl process (scasp crashes on the second sequential call).

## Definition of done (workflow's share of P3)

`cabal build all` clean under `-Werror`; all suites green; the four `.blawx` goldens carry
non-empty `xml_content` for every workspace and test; `.pl`/`.blawx` scasp arithmetic in
the generator's `( … )` image with the IR haddock updated; tier-1 harness re-run 16/16;
headless fixpoint harness green on all four goldens; spec §8.12 addendum recording the
paren ruling; `p3-design/xml-plan.md` recording the per-block XML templates and their
evidence lines; no changes outside `jl4-core/`, `jl4/tests-cli/`, `jl4/examples/blawx/`,
`etc/`, `specs/todo/`, and `p3-design/`. The coordinator then runs the authoritative
tier-2 pass: import into the container, open-and-save every workspace in the real UI,
byte-diff the stored encodings, and record §10 P3 EXECUTED.
