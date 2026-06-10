# Specification: TNR Generation and Round-Tripping

**Status:** Draft
**Branch:** `nlg-roundtrip`
**Related:** `specs/done/DESC-ANNOTATION-SPEC.md`, `specs/todo/REF-ANNOTATION-SPEC.md`, `jl4-core/src/L4/Nlg.hs`

## Executive Summary

Generate, from L4 source, legislative and regulative text that looks and feels
like something a Parliament or a government agency would produce — the **"TNR"
(Times New Roman) version** — while remaining provably faithful to the L4.
Prototype output is Markdown; production output is `.docx` with proper
paragraph styles.

The second half of the roadmap is **round-tripping**: humans edit the TNR
version, the L4 updates in response, and the *next* generation of the TNR from
the updated L4 is as similar as possible to the previous generation, modulo
the edits. This is a bidirectional-transformation ("lens") problem and we
adopt the lens laws as our correctness criteria.

## Positioning: the neurosymbolic premise

L4's differentiator — already live via the MCP exposure of deployed L4 — is
**audit-grade, deterministic, logic-based answers via AI**: the AI gets the
logic out of the L4, not out of the English. Don't ask a GPU to do what a CPU
can. The industry keeps handwaving at this under many names (hybrid AI,
neurosymbolic, "LLMs need a business-rules engine / ontology layer"); L4 is
the concrete artifact those hand-waves are missing.

The TNR layer must respect that premise absolutely:

- **English is a view; L4 is the model.** The TNR document is a *projection*
  of the L4, never an alternative source of semantics. Any agent answering
  questions about the rules calls the reasoner (via MCP / `jl4-service`),
  not its own reading of the generated prose.
- Round-trip ingestion (§3) is the one place neural drafting touches the
  model — and there every patch is gated by the symbolic half (typecheck,
  `#EVAL` regressions, human confirmation) before it lands.
- This is also why faithfulness (§2.5) is a CI property, not an aspiration:
  if the projection drifts from the model, the audit chain breaks.

## 1. Current State (survey)

### 1.1 Annotation mechanisms already in the language

| Annotation | Syntax | Attaches to | Status |
| --- | --- | --- | --- |
| NLG hint | `@nlg text with %var%` (line) / `[inline]` / `<<block>>` | `Name` nodes, by source position | ✅ implemented; resolved through typecheck (`NlgMap` in `TypeCheck/Types.hs`) |
| Description | `@desc text` (leading or inline) | declarations, `GIVEN` params, record fields | ✅ implemented (`DescMap`) |
| Citation | `@ref "Section 4(1)(a)"`, `@ref url …`, `@ref-map`, `@ref-src` | lexed & collected; **not yet attached to AST** | 🟡 see `REF-ANNOTATION-SPEC.md`; TODO at `Parser.hs:216-218` |
| Export | `@export [default] desc` | `DECIDE` functions | ✅ implemented (`L4/Export.hs`) |
| Section | `§`/`§§`/… headings with names | module structure | ✅ nesting depth = heading level |

Key plumbing facts:

- `Extension { resolvedInfo, nlg, desc }` rides on every `Anno`
  (`Syntax.hs:424-447`), so hints survive parse → resolve → typecheck.
- `NlgFragment` = literal text interleaved with `%var%` references
  (`Syntax.hs:676-680`).
- `L4.Nlg.lin` (Nlg.hs:416) prefers the `@nlg` annotation when present, falls
  back to compositional linearization; binding-site annotations propagate to
  use sites (`Linearize Resolved`, Nlg.hs:369-383).

### 1.2 What exists for generation — and the gap

`L4.Nlg.simpleLinearizer` produces flat text from a single expression. The
test driver (`jl4/tests/Main.hs:131-134`) linearizes **only `Directive`
nodes** (`#EVAL` etc.) into `.nlg.golden` files. Consequences:

- `imaginary-alcohol-act.nlg.golden` is empty (no directives in the file).
- `ny-environmental-7.3.nlg.golden` reads like word salad:
  `executing contract `Example Filing` at `Day` with `Jul` with 19 and 2025 …`

**There is no module-level document renderer.** Nothing walks `DECLARE`,
`ASSUME`, `DECIDE`, sections, and deontic rules to produce a *document*. The
`LinTree` type is token-level only; the TODO at `Nlg.hs:25-28` already wishes
for "a 'Doc' type… like GF, a typed LinTree that performs pre-analysis steps".
This spec is that Doc type, plus the house style to render it.

## 2. Goal 1: The TNR Renderer

### 2.1 Output target: legislative house style

The renderer must produce documents in conventional drafting style
(Commonwealth/Singapore conventions as the default house style; pluggable
later):

- **Hierarchy:** Part → section (`1.`) → subsection (`(1)`) → paragraph
  (`(a)`) → subparagraph (`(i)`). L4 `§` depth maps onto this hierarchy.
- **Coode tabulation** for conditions: an `IF` with an `AND`-list of
  conditions renders as a sentence ending "if—" followed by semicolon-
  separated paragraphs, with "; and" / "; or" on the penultimate item.
  Nested `OR` within `AND` drops one tabulation level (paragraphs →
  subparagraphs).
- **Deontics:** `PARTY p MUST a WITHIN d HENCE h LEST l` renders as
  "*p* must *a* \[within / no later than *d*\]. If *p* fails to do so, *l*."
  `MUSTNT` → "must not"; `MAY` → "may".
- **Definitions:** `DECLARE`/`ASSUME`d types and terms collect into an
  interpretation section: "In this Act, unless the context otherwise
  requires — 'Person' means …", drawing prose from `@desc`.
- **Citations:** `@ref` annotations render as marginal notes / parenthetical
  cites once REF-ANNOTATION-SPEC lands attachment.
- **Schedules** (Phase 2): data-valued `DECIDE`s — lists and tables of
  constants (e.g. british-citizen-act's list of British Overseas
  Territories) — render as numbered Schedules at the end of the instrument,
  referenced from the provision ("the territories listed in Schedule 1"),
  rather than as run-on prose.

### 2.2 Worked target example (north star golden)

From `jl4/examples/legal/imaginary-alcohol-act.l4` provisions (1)–(2):

```l4
DECIDE `the person must not sell alcohol`
IF  `the person is a body corporate`
    AND  `the person engages in business for profit`
    AND  NOT `the person is a public house`
    AND  NOT `the person is a hotel`
    AND
        `the person has an unspent conviction for fraud`
        OR  `the person has an unspent conviction for providing misleading information in relation to an application for a licence under an enactment`
        OR  `the person has an alcohol banning order`
```

Target TNR (Markdown prototype):

```markdown
# Imaginary Alcohol Act

## 1. Prohibition on sale of alcohol

(1) The person must not sell alcohol if—

   (a) the person is a body corporate;

   (b) the person engages in business for profit;

   (c) it is not the case that the person is a public house;

   (d) it is not the case that the person is a hotel; and

   (e) the person—

      (i) has an unspent conviction for fraud;

      (ii) has an unspent conviction for providing misleading
           information in relation to an application for a licence
           under an enactment; or

      (iii) has an alcohol banning order.
```

Observations driving design:

- The AND-list becomes lettered paragraphs ending `;` with `; and` before the
  last; the OR-group becomes roman subparagraphs with `; or`.
- `NOT atom` renders clumsily ("it is not the case that…") unless the author
  supplies a negative form — motivating a **negation hint** (§2.4).
- Paragraph (e) shows **subject factoring**: the three disjuncts share the
  prefix "the person", which is hoisted. v1 may do this only via explicit
  hints; automatic common-prefix factoring is a v2 nicety.
- Source comments in the file contain the *original* statutory text, giving us
  immediate human evaluation: does our output read like what Matt sent?

### 2.3 Architecture

New module `jl4-core/src/L4/TNR.hs` (working name; could live as
`L4.Nlg.Document`):

```haskell
-- A structured document IR between AST and concrete formats
data Doc
  = DocTitle Text
  | DocPart  Numbering Text [Doc]
  | DocSection Numbering (Maybe Text) [Doc]       -- "1. Heading"
  | DocProvision Anchor [Inline]                  -- running prose
  | DocTabulation Anchor Conj [Doc]               -- Coode list, "; and"/"; or"
  | DocDefinition Anchor Text [Inline]            -- "X means ..."
  deriving stock (Show, Eq, Generic)

data Anchor = MkAnchor { unique :: Unique, path :: Text }  -- see §3.2

render :: Module Resolved -> Doc          -- the "get" of the lens
renderMarkdown :: Doc -> Text
renderPandocJSON :: Doc -> Value          -- → docx via pandoc, v2
```

- `render` walks the module: sections → headings; `DECIDE`/`MEANS` →
  provisions (Coode-tabulated via the existing `Linearize` machinery for
  leaf expressions, reusing `lin`'s `@nlg` preference); `DECLARE`/`ASSUME` →
  definitions; `Regulative`/deontic exprs → obligation prose; directives
  (`#EVAL`, `#TRACE`) are **omitted** (they are tests, not law) — or
  optionally rendered into an explanatory-notes appendix.
- Every `Doc` block carries the `Anchor` of the L4 node it came from. This is
  the backbone of both faithfulness checking and round-tripping.
- **Markdown first.** `.docx` lands in v2 via pandoc with
  `--reference-doc=tnr-reference.docx` whose styles (`Title`, `PartHeading`,
  `SectionHeading`, `Subsection`, `Paragraph`, `Definition`) carry the actual
  Times New Roman formatting. The IR is designed so no information is lost
  between the MD and docx backends.

CLI surface:

```
l4 tnr foo.l4 [--format md|docx] [--anchors visible|hidden|none]
```

Golden tests: `foo.tnr.golden` alongside the existing `.nlg.golden` files in
`jl4/examples/legal/tests/`, generated by the same harness in
`jl4/tests/Main.hs`.

### 2.4 New hint surface needed (small, incremental)

1. **Negative form** for atoms: without it every `NOT` is "it is not the case
   that…". Proposal: a second NLG slot, e.g.
   `@nlg the person is a public house @nlg.neg the person is not a public house`
   (exact syntax TBD; could also be `@nlg "pos" / "neg"`).
2. **Whole-rule prose override**: `@nlg` today attaches to `Name`s. Allow a
   block `<<…>>` annotation on a whole `DECIDE` to override the entire
   provision's rendering while keeping the anchor (escape hatch for hard
   cases; the faithfulness checker §2.5 still applies).
3. **Section headings vs. running text**: `§` names like
   `` `Imaginary Alcohol Act` `` are already headings; a `@desc` on a section
   could supply a long title or marginal note.
4. **Document front matter**: title, short title, enacting formula. Proposal:
   reuse `@desc` on the top-level module/first section, plus a conventional
   `§ Preamble` section; no new syntax required for v1.

### 2.5 Faithfulness

"Faithful to the L4 itself" must be checkable, not vibes:

- **Structural completeness:** every `Decide`, `Assume`, `Declare`, and
  deontic clause in the module appears as exactly one anchored block (or is
  explicitly suppressed with a documented hint). The renderer emits a
  coverage report; CI fails on unanchored/uncovered nodes.
- **No invented semantics:** prose for connectives comes only from the fixed
  house-style table (and/or/not/if/must/may…) and from author annotations.
  The renderer never paraphrases beyond its table — LLMs are *not* in the
  v1 generation path (they enter in round-trip ingestion, §3.4, where
  output is validated).

### 2.6 The AI gloss: annotation authoring, not render-time paraphrase

The deterministic renderer will produce awkward constructions wherever atom
names are mechanical ("if the person is a person and not a nonperson…").
We want idiomatic output — but a render-time LLM smoothing pass would break
determinism (same L4 ↛ same TNR), minimal-diff regeneration (every re-gloss
re-rolls phrasing document-wide), and auditability (the shipped English
would no longer have a mechanical derivation from the L4).

Instead, **the gloss is an authoring assistant whose output is `@nlg`/`@desc`
hint patches committed into the L4 source**:

1. deterministic render (Phase 1);
2. a gloss agent reads the output, flags awkward fragments, and proposes
   annotation patches — atom phrasings, negative forms, group lead-ins;
3. each proposal is validated before landing: annotations cannot change
   logic by construction (typecheck + goldens confirm), and a
   **back-translation check** verifies the proposed phrasing still denotes
   the same atom ("not a public house" ≠ "a private residence");
4. a human accepts; the hints are committed; the deterministic renderer
   replays them forever.

*The GPU drafts the phrasing once; the CPU replays it forever.* Fluency
compounds in source control — diffable, reviewable, stable across
regenerations — rather than being re-rolled per render. Mechanically this is
the Class A round-trip path (§3.3) running in self-edit mode.

Constraints:

- **Granularity:** the gloss touches leaf clauses and lead-ins only.
  Numbering, tabulation structure, and the and/or/not skeleton stay
  CPU-only. Whole-provision `@nlg` overrides remain an escape hatch with
  stricter review (they hide structure).
- **Deterministic aggregation first:** common-subject factoring
  ("the person— (i) has X; (ii) has Y") and similar GF-style aggregations
  are pure-Haskell improvements; the AI handles only the genuinely
  linguistic residue.
- The MCP answer path never reads the gloss: English stays a view, logic
  stays the model.

## 3. Goal 2: Round-Tripping

### 3.1 Correctness criteria — lens laws

Let `get : L4 → TNR` be the renderer and `put : (TNR', L4) → L4'` be
ingestion of an edited TNR against the source L4.

1. **GetPut (stability):** `put (get l4, l4) = l4` — re-ingesting an
   unedited document changes nothing. Byte-identical `.l4`, byte-identical
   regenerated TNR.
2. **PutGet (fidelity):** `get (put (tnr', l4))` reflects the edit — the
   regenerated document contains the edited content (possibly normalized to
   house style).
3. **Minimal diff (the user-facing requirement):** the regenerated TNR
   differs from the edited TNR only at (a) the edited blocks and (b) forced
   renumbering. Diffs are computed **modulo numbering**: anchors, not
   section numbers, are identity. (Renumbering on insertion is normal in
   legislation; we surface it, we don't fight it.)

Determinism is a prerequisite: rendering depends only on the AST and
annotations — stable ordering (source order), no timestamps, no randomness.

### 3.2 Anchors

Each rendered block embeds a stable identifier linking it to its L4 node:

- **Markdown:** trailing HTML comment, e.g.
  `<!-- l4: imaginary-alcohol-act § the-person-must-not-sell-alcohol -->`
- **docx:** bookmarks or content controls (invisible in print, survive Word
  editing reasonably well).
- Anchor identity = module + qualified name + structural path (e.g.
  `decide:the-person-must-not-sell-alcohol/if/and[3]`), **not** line numbers
  or section numbers — robust to reordering and renumbering.

### 3.3 Edit classification

`l4 ingest foo.md --against foo.l4` aligns edited blocks to anchors and
classifies each change:

| Class | Example | Action |
| --- | --- | --- |
| **A. Wording-only** | "body corporate" → "corporate body"; rephrased but logically identical | Update/insert `@nlg` / `@desc` annotations in the `.l4`. Fully automatic. |
| **B. Semantic** | a condition added/struck; threshold changed; "and" → "or" | Propose an L4 patch (LLM-assisted), then **validate**: typecheck + existing `#EVAL`/`#CHECK` regressions. Present logic-level diff to a human for confirmation. Tests that intentionally change behavior must be updated consciously. |
| **C. Unalignable** | anchor destroyed; block deleted or wholesale rewritten; new free-floating prose | Flag for interactive re-formalization; never silently guess. |

The Class A / Class B distinction is the heart of the design: most editorial
passes over legislation are wording passes, and those must round-trip into
*annotations* — leaving the logic untouched and the regeneration trivially
stable. Only genuinely semantic edits touch the rule bodies.

### 3.4 Surgical L4 updates (exact-printing)

L4's parser already retains concrete syntax (`Anno`/`PosToken`,
`CsnCluster`). `put` must use **exact-print style surgical edits** — splice
the changed annotation or subexpression into the original source text,
preserving all other bytes (comments, layout, the author's formatting) —
rather than pretty-printing the whole module. This is what makes GetPut hold
at the `.l4` level and keeps `git diff` on the L4 side as small as the edit.

### 3.5 What we explicitly do not promise (v1)

- Free-form prose inserted between anchors (recitals, notes) is preserved
  verbatim as "unmanaged text" but not formalized.
- Edits inside Word that destroy bookmarks degrade to Class C.
- Multi-file modules: v1 round-trips a single `.l4` ↔ single document.

## 4. Pilot Corpus

| File | Why |
| --- | --- |
| `jl4/examples/legal/imaginary-alcohol-act.l4` | Original statutory text in comments → direct human comparison; pure propositional structure; the north-star golden (§2.2) |
| `jl4/examples/legal/british-citizen-act.l4` | Real legislation; deep AND/OR nesting; function application (`father of p`) stresses linearization |
| `jl4/examples/legal/ny-environmental-7.3.l4` | Real regulation; deontics (`PARTY/MUST/WITHIN/HENCE`); `@ref` URL citations |
| `jl4/examples/legal/promissory-note.l4` | Contract (not statute) — tests that house style is pluggable; chained obligations |
| `doc/reference/syntax/annotation-example.l4` | Exercises every annotation form |

## 5. Phasing

| Phase | Deliverable | Exit criterion |
| --- | --- | --- |
| **1. TNR/MD renderer** | `L4.TNR` Doc IR + Markdown backend + `l4 tnr` + `.tnr.golden` harness | `imaginary-alcohol-act.tnr.golden` judged faithful & readable against the in-comment original; coverage report clean on pilot corpus |
| **2. Hints & polish** | negation hints, whole-rule overrides, definitions section, `@ref` cites (after REF-ANNOTATION-SPEC); deterministic subject-factoring; **AI gloss pass** (§2.6) proposing `@nlg` patches gated by back-translation + goldens | british-citizen-act and ny-environmental renders pass review |
| **3. docx backend** | pandoc JSON writer + `tnr-reference.docx` styles | opens in Word with correct paragraph styles |
| **4. Round-trip: Class A** | anchor alignment, wording-edit detection, surgical `@nlg`/`@desc` updates; GetPut + idempotence property tests | edit-a-phrase → regen produces minimal diff, `.l4` diff touches only annotations |
| **5. Round-trip: Class B/C** | LLM-assisted semantic patch proposal + typecheck/#EVAL validation gate + human confirmation UX | demo: strike a condition in Word, confirm proposed L4 change, regen stable |
| **6. Web playground** (§6.1) | split-pane jl4-web: L4 editor left, live TNR render right; later TNR-side editing via the ingestion path | edit L4 in browser → only the corresponding TNR block changes |

## 6. Delivery Vehicle: Agent Skill

Once the CLI surface stabilizes, these capabilities solidify into an **agent
skill** (in the style of the existing `l4` / `writing-l4-rules` skills) —
call it `l4-tnr` or fold it into the l4 skill as a workflow.

This is not just packaging; it resolves the Phase 5 architecture. The
"LLM-assisted" steps in round-tripping do **not** require embedding an LLM in
the toolchain — the agent *is* the LLM in the loop, and the deterministic CLI
provides its guardrails:

```
deterministic core (Haskell)          agent skill (prompt + workflow)
─────────────────────────────         ────────────────────────────────
l4 tnr      render, anchors      ←→   drive renders, present diffs
l4 ingest   align, classify A/B/C ←→  draft Class B semantic patches
l4 check    typecheck, #EVAL      ←→  run validation gate, iterate
exact-print surgical edits        ←→  apply Class A edits mechanically
```

The skill encodes the *workflow*: render → hand to human → ingest edits →
classify → auto-apply Class A → for Class B, propose an L4 patch, run
`l4 check` and the `#EVAL` regressions, show the human a logic-level diff,
apply on confirmation → regenerate → verify minimal diff. Every
agent-generated patch passes through the typechecker and golden tests before
it lands, satisfying the "guardrailed left-brain logic" doctrine: the neural
half drafts, the symbolic half verifies.

A skill is also the right home for the editorial judgment the renderer
shouldn't hardcode: choosing `@nlg` phrasings, deciding when a clumsy
rendering warrants a negation hint, and conducting the human-eval comparison
against original statutory text (§7).

Deliverable: a `SKILL.md` (plus reference docs) added in Phase 5, once
Phases 1–4 give it real commands to drive.

### 6.1 Web playground

A second delivery vehicle, reusing `ts-apps/jl4-web`: a split-pane view with
the existing L4 web editor on the left and an auto-refreshing rendered
Markdown pane on the right — the **prototype TNR**. Sequencing:

1. **L4-edits-first:** left pane editable; on each successful typecheck the
   right pane re-renders (`l4 tnr` behind the existing language-server /
   websessions plumbing). This alone demonstrates GetPut stability live:
   the right pane only changes where the L4 changed.
2. **TNR-edits-later:** make the right pane editable and wire the edits
   through the ingestion path (§3) — classification, annotation updates,
   AI-drafted semantic patches — reusing the mass-AI-ingestion tooling we
   already have. The left pane updating in response is the lens running
   in reverse, on screen.

## 7. Testing

- **Goldens:** `.tnr.golden` per pilot file, same harness as `.nlg.golden`.
- **Properties:**
  - idempotence: `render ∘ put ∘ get = render` on unedited docs (GetPut);
  - minimal-diff: for a corpus of synthetic single-block edits, regenerated
    docs differ from edited docs only at the edited anchor (+ renumbering);
  - coverage: no L4 declaration without an anchor in the output.
- **Human eval:** side-by-side of generated TNR vs. original statutory text
  for the alcohol act and british-citizen-act.

## 8. Open Questions — provisionally resolved (2026-06-10)

1. **Negation-hint syntax** — *deferred to Phase 2.* v1 negates atoms with a
   conservative copula/auxiliary swap (" is " → " is not ", " has " →
   " does not have ", likewise are/have, first occurrence only) and falls
   back to the clumsy-but-faithful "it is not the case that …". On the
   alcohol act this already yields "the person is not a public house".
2. **`#EVAL`s** — *strictly suppressed* in v1; counted in the trailing
   `tnr-coverage` comment so suppression is visible, not silent. An
   explanatory-notes appendix can come later.
3. **House style** — *hardcoded Commonwealth* for v1, but every connective /
   lead-in / marker string lives in one place (`L4.TNR`'s house-style
   helpers) so making it data-driven later is mechanical.
4. **Anchor visibility** — *hidden HTML comments*, on by default,
   `--no-anchors` to suppress. Robustness against comment-stripping editors
   is a docx-era problem (see 5).
5. **Docx round-trip markers** — *deferred to Phase 3* (bookmarks vs.
   content controls vs. fuzzy-match sidecar).

## 9. Status

- **2026-06-10** — Phase 1 implemented:
  - `jl4-core/src/L4/TNR.hs`: Doc IR + module walker + Coode tabulation +
    Markdown backend, reusing `L4.Nlg`'s annotation-aware linearizer for
    leaf text (`LinTree` internals now exported from `L4.Nlg`).
  - `l4 tnr FILE [--no-anchors]` CLI subcommand (`jl4/app/L4/Cli/Tnr.hs`).
  - **Not yet compiled**: the GHC toolchain lives on `/Volumes/transcend`
    and the working session lacked macOS permission to read removable
    volumes. Build + `.tnr.golden` harness wiring is the immediate next
    step.
  - `specs/todo/tnr-prototype/tnr_proto.py`: throwaway Python demonstrator
    of the same algorithm (micro-parser, alcohol-act subset only); its
    output on the alcohol act (`imaginary-alcohol-act.tnr.md` alongside)
    matches the original statutory text in the file's comments nearly
    word-for-word. Delete once the Haskell golden exists.
