# Specification: TNR Generation and Round-Tripping

**Status:** Design document; nothing in it is CI-guarded. **RULED 2026-09-02
(§10):** the renderer this spec is written against is `L4.Export.Document` +
`L4.Export.Render` on `unstable` — the VS Code Render pane and `l4 render`.
The June demonstrator `L4.TNR` is retired and no longer in the tree; its last
commit is `0f90dab7` on this branch, for retrieval. What it demonstrated is
now the house-style worklist (§2.3). §3.6 is proposed, not built, and nothing
in it has been measured.
**Branch:** `nlg-roundtrip` (this file is the branch's whole diff against `unstable`)
**Related:** `specs/done/DESC-ANNOTATION-SPEC.md`, `specs/todo/REF-ANNOTATION-SPEC.md`, `jl4-core/src/L4/Nlg.hs`

## Executive Summary

Generate, from L4 source, legislative and regulative text that looks and feels
like something a Parliament or a government agency would produce — the **"TNR"
(Times New Roman) version** — while remaining provably faithful to the L4.
Output today is plain text, HTML and Akoma Ntoso from `l4 render`; production
output is `.docx` with proper paragraph styles.

The second half of the roadmap is **round-tripping**: humans edit the TNR
version, the L4 updates in response, and the _next_ generation of the TNR from
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

- **English is a view; L4 is the model.** The TNR document is a _projection_
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

| Annotation  | Syntax                                                         | Attaches to                                    | Status                                                                        |
| ----------- | -------------------------------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------- |
| NLG hint    | `@nlg text with %var%` (line) / `[inline]` / `<<block>>`       | `Name` nodes, by source position               | ✅ implemented; resolved through typecheck (`NlgMap` in `TypeCheck/Types.hs`) |
| Description | `@desc text` (leading or inline)                               | declarations, `GIVEN` params, record fields    | ✅ implemented (`DescMap`)                                                    |
| Citation    | `@ref "Section 4(1)(a)"`, `@ref url …`, `@ref-map`, `@ref-src` | lexed & collected; **not yet attached to AST** | 🟡 see `REF-ANNOTATION-SPEC.md`; TODO at `Parser.hs:216-218`                  |
| Export      | `@export [default] desc`                                       | `DECIDE` functions                             | ✅ implemented (`L4/Export.hs`)                                               |
| Section     | `§`/`§§`/… headings with names                                 | module structure                               | ✅ nesting depth = heading level                                              |

Key plumbing facts:

- `Extension { resolvedInfo, nlg, desc }` rides on every `Anno`
  (`Syntax.hs:424-447`), so hints survive parse → resolve → typecheck.
- `NlgFragment` = literal text interleaved with `%var%` references
  (`Syntax.hs:676-680`).
- `L4.Nlg.lin` (Nlg.hs:416) prefers the `@nlg` annotation when present, falls
  back to compositional linearization; binding-site annotations propagate to
  use sites (`Linearize Resolved`, Nlg.hs:369-383).

### 1.2 What exists for generation — and the gap (rewritten 2026-09-02)

Two layers exist, and they are not the same thing.

- **Leaf phrases.** `L4.Nlg.simpleLinearizer` produces flat text from a single
  expression, preferring an `@nlg` annotation where one is present. The
  `.nlg.golden` files (`jl4NlgAnnotationsGolden` in `jl4/tests/Main.hs`) and
  `l4 nlg` linearize **only `Directive` nodes**, so
  `imaginary-alcohol-act.nlg.golden` is empty and
  `ny-environmental-7.3.nlg.golden` reads
  `executing contract `Example Filing`at`Day`with`Jul` with 19 and 2025 …`.
  The go orchestrator's `p7-tnr.sh` diffs that payload and calls itself the
  "TNR / NLG leg"; it is not a document renderer.
- **The document.** `L4.Export.Document` walks a typechecked module plus its
  import closure into a presentation-neutral `Document` IR — sections,
  definitions, provisions, each rule body a recursive `Clause` outline — and
  `L4.Export.Render` emits it as plain text, standalone HTML or Akoma Ntoso.
  It is what the VS Code **Render** pane shows (custom LSP request
  `l4/exportDocument`) and what `l4 render` prints; it prunes unreachable
  imports, drops directives, and stamps every block with an id. It landed
  2026-06-14 (`2bb2b6d5`), three days after the June version of this spec.

The gap is therefore not "no module-level renderer", which is what this spec
said in June and was true then. The gap is **house style**. Measured
2026-09-02 on `imaginary-alcohol-act.l4`, `l4 render --format text` opens with
fourteen bullets of the form "The person is a body corporate is assumed to be
given", renders each rule as "X means: all of the following are true:",
renders negation as "the person is a public house is false", and a negated
conjunction as one run-on line. It is a faithful outline of the L4. It is not
what a Parliament prints. §2 is about closing that gap **inside**
`Export.Document`/`Render`, not beside it.

## 2. Goal 1: The TNR house style

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
  "_p_ must _a_ \[within / no later than _d_\]. If _p_ fails to do so, _l_."
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
- Source comments in the file contain the _original_ statutory text, giving us
  immediate human evaluation: does our output read like what Matt sent?

### 2.3 Architecture (rewritten 2026-09-02)

The IR exists. `L4.Export.Document`'s `Document` / `Block` / `Clause` is the
"Doc type" the June version of this section proposed to build, and it has what
that section asked for: presentation-neutral, one block per declaration, several
backends over one IR (`renderText`, `renderHtml`, `renderAkn` in
`L4.Export.Render`, plus the JSON form the TypeScript layer renders). So the
architecture is: **the TNR house style is a rendering mode of
`L4.Export.Render`**, selected by a `RenderConfig` field (working name
`houseStyle = Legislative`), and where the style needs structure the IR does
not carry, the IR grows a field. No second walker.

What the retired demonstrator (`L4.TNR`, 690 lines, last at `0f90dab7`) did
that `Export.Render` does not — and which is therefore the worklist, in the
order the alcohol act needs it:

1. **Bare-`BOOLEAN` `ASSUME`s are atoms, not definitions.** They appear inline
   inside the provisions that use them and get no "is assumed to be given"
   entry; the coverage tally counts them as inlined. This alone removes the
   fourteen-bullet preamble.
2. **Coode tabulation** for `AND`/`OR` bodies: lettered paragraphs ending
   "; and" / "; or", one tabulation level per nesting, the lead-in ending
   "if—". `Export.Document`'s `Clause` tree already has the nesting; this is a
   text backend, not a new analysis.
3. **Negation as a copula swap** (" is " → " is not ", " has " → " does not
   have ", first occurrence only), falling back to "it is not the case that—"
   over a tabulated group. `Export.Document` renders " is false".
4. **Negative-universal rewrite**: "the X must not VP", with every condition
   predicated of the X, renders as "No X may VP who—" with subject elision and
   verb-factored groups ("(e) has— (i) …; (ii) …"). Total and purely
   syntactic; declines on mixed subjects.
5. **Coverage tally** as a trailing comment (provisions / atoms inlined /
   directives suppressed) so suppression is visible, per §2.5.
6. **Anchors as round-trip identity** (§3.2). `Export.Render` already stamps
   every block with `<sort>_<n>_<module>`, documented as a short, stable,
   path-free link target. Whether it survives inserting a declaration above
   the block is to be measured before it is reused as identity; §3.2 wants the
   qualified name plus structural path. Either the existing id becomes that,
   or a second id is added; the HTML and AKN link targets need not change.

A Markdown backend is **not** on the list. Text and HTML exist; docx comes
from HTML or from the JSON IR via pandoc (Phase 3), not from Markdown.

CLI surface: `l4 render foo.l4 --format text|html|akn|json` plus one new flag
for the style. Goldens: **there is no golden harness for `l4 render` output
today** — `jl4/tests/Main.hs` has DMN, BPMN and relational export specs and
nothing that reads `Export.Render`. A `.render.golden` per legal-corpus file,
written by the same harness that writes `.nlg.golden`, is the first
deliverable of Phase 1, before any style work, so the style work has a diff to
land against. The June `.tnr.golden` files (26 of them at `0f90dab7`) are the
record of what the legislative style produced; they were goldens for code that
is gone and were removed with it.

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
  The renderer never paraphrases beyond its table — LLMs are _not_ in the
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

_The GPU drafts the phrasing once; the CPU replays it forever._ Fluency
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

### 2.7 The feedback loop: a style complaint lands as a rule, and persists (recorded 2026-09-02)

The thing the June demonstrator was actually good for, and the reason its
output improved by the hour, was not any one transform. It was the loop:

1. render the corpus;
2. Meng reads a provision and says what is wrong with it, in English
   ("that should read _No person may sell alcohol who—_", "_February with 4
   and 2024_ is not a date");
3. the agent decides **where the fix lands** (below), makes it, and re-renders
   the whole corpus;
4. the golden diff shows exactly which provisions changed, and nothing else;
5. Meng accepts, and the fix is in source control — it replays on every
   future render of every document.

This is §2.6's doctrine ("the GPU drafts once, the CPU replays forever")
applied one level up: not only phrasings persist as annotations, **style
rules persist as renderer code and data.** A complaint is never answered by
re-prompting the output. It is answered by changing the thing that generates
the output, so the answer is deterministic, diffable, and corpus-wide.

Where a fix lands, from narrowest to widest — the agent's first job on each
complaint is to pick the level, and the rule is _the widest level at which the
fix is total_:

| level                               | lives in                                                                  | reach                            | example from the demonstrator                                                                                                                                         |
| ----------------------------------- | ------------------------------------------------------------------------- | -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **A. annotation** (`@nlg`, `@desc`) | the `.l4` source                                                          | one phrase in one document       | §2.6: an atom's negative form; a clumsy lead-in                                                                                                                       |
| **B. house-style table**            | the connective / lead-in / marker / type-idiom strings in `Export.Render` | every document                   | `7d762caf`: `MAYBE T` renders "an optional T", `LIST T` "a list of T"; `0db07dcf`: possessive spacing                                                                 |
| **C. transform**                    | a pure syntactic rewrite over the IR in `Export.Render`                   | every document, where it applies | `21f157ec`: the negative-universal rewrite — "the X must not VP" with all conditions predicated of X becomes "No X may VP who—", subject elided, groups verb-factored |

Constraints on B and C, which are what keep the loop honest:

- **Total and syntactic.** A transform applies wherever its precondition holds
  and declines cleanly where it does not (`21f157ec` left the alcohol act's
  provisions 2–3 untouched because their subjects are mixed). It never guesses,
  and it never reads the meaning of an atom.
- **The golden diff is the acceptance evidence.** "Regenerating the demo corpus
  changed only the one rewritten provision — minimal-diff holds" is the
  sentence in `21f157ec`'s body that made it mergeable. A level-B or level-C
  change with no golden harness under it cannot show that it improved one
  document without degrading another, which is why Phase 0 (§5) precedes any
  style work: the harness is what makes a complaint answerable at levels B
  and C at all.
- **Complaints that surface in goldens become the worklist.** `7d762caf`
  records "date/money constructor applications ('February with 4 and 2024',
  'USD with 25000') want literal idioms" — observed in the new goldens, not
  imagined. The §9 Phase 2 list was built this way.
- **No render-time LLM.** §2.6's prohibition stands at every level. The agent
  is in the loop at development time, editing rules; the renderer stays a
  pure function of the L4 and its annotations.

Delivery: this loop is what the §6 agent skill encodes on the generation
side, alongside the ingestion workflow it already describes — render, take
the complaint, choose the level, apply, re-render, present the golden diff,
land on acceptance. The skill's job is the level choice; the CLI and the
goldens are its guardrails.

### 2.8 Dialects: synonymous forms as a bidirectional resource (design intuition, recorded 2026-09-02, not ruled)

Background, so nobody proposes it again: the team ran Grammatical Framework
(GF) for about two years and stopped because hand-writing concrete grammars
for everything was not feasible. GF's abstract syntax had to be built per
domain; L4 already _is_ the abstract syntax. What remained infeasible was the
concrete side, and that is the part the §2.7 loop grows from complaints
instead of from theory, and the part an AI can now do by **alignment** rather
than generation.

The intuition (Meng, 2026-09-02): the same L4 abstract expression has many
synonymous surface forms, chosen on stylistic preference; at the limit every
law firm has an internal dialect of English. Because each form is associated
with its L4 abstract expression, the set of forms is a resource for the
**ingester** as much as for the renderer.

In GF's terms: one abstract tree, one concrete grammar per dialect, and GF
parsed by running a concrete grammar in reverse. In machine-translation terms
the resource is a **phrase table** between L4 and each dialect, and phrase-table
extraction from an aligned corpus — a firm's precedent bank against the L4
forms — is what a model does that word-alignment statistics could not.

What follows, if pursued:

- **Generation** selects one form per abstract expression under the chosen
  dialect and stays deterministic (§2.6, §2.7 unchanged). **Ingestion**
  accepts the union over dialects.
- **Class A becomes mechanical.** An edit that moves within a synonym set is a
  wording edit by construction (§3.3); only movement out of every known set
  reaches the Class B path.
- **Coverage per dialect** — the fraction of a document the phrasebook
  accounts for — is the honest measure of how well a firm's dialect is
  learned, and grows as the §2.7 loop runs on that firm's documents.
- **Dialects live outside the `.l4`,** as data selected by a render option, so
  the L4 stays firm-neutral and English stays a view (Positioning). The `@nlg`
  annotation is the degenerate single-dialect case.
- **Synonymy is a ruling, not a fact.** "Best efforts" and "reasonable
  efforts" read as synonyms and are not. Every entry is admitted through the
  §2.6 back-translation gate, and §3.6 becomes the per-dialect test: render in
  dialect _D_, re-encode cleanroom, measure agreement. A dialect whose house
  style elides a qualifier shows as a lower rate with a witness naming the
  clause — "your house style is lossy, here is where" is a product finding in
  its own right.

#### Drafting offices are dialect users too

Not only firms. Matt Waddington (Jersey's legislative drafting office; the
"Matt" whose text the alcohol act in §2.2 was converted from) has long wanted
these methods for the **training and operations of legislative drafters**. In
dialect terms an office's drafting manual _is_ its dialect, and the machinery
above gives a drafter three things: a house-style check on a draft (does it
use the office's forms?), a training loop (render the L4 in the office style
and compare with what the trainee wrote), and — through §3.3 — a diff that
says whether a redraft changed the law or only the wording. The last is the
one drafters do by eye today.

#### A gold corpus: two English renderings that promise the same meaning

Singapore's **Plain Laws Understandable by Singaporeans** initiative (PLUS,
AGC Legislation Division, begun 2013 with a public survey) concluded as the
**2020 Revised Edition of Acts**: 510 Acts re-issued in modernised language,
in force 31 December 2021. The documented changes are the dialect shift in
miniature — "shall" → "must", "notwithstanding" → "despite", "for the avoidance
of doubt" → "to avoid doubt", "chairman" → "chairperson", Roman → Arabic
numerals, long provisions split into subsections.

What makes it a _gold_ corpus rather than merely a large one is that the
promise of meaning-preservation is **statutory**, not editorial. The Revised
Edition of the Laws Act 1983, s 4(1), gives the Law Revision Commissioners
their powers "**without changing the meaning of any Act**" — including, at
s 4(1)(j)(i), "changes to spelling, punctuation, grammar or syntax, **or the
use of conjunctives and disjunctives**", at (k) transposing words and
combining or dividing sections, and at (m) "verbal additions, omissions or
alterations". s 7(4) then makes the revised edition "the sole and only proper
Statute Book", and s 23 provides for rectification of errors by Gazette
order. So: two renderings of one meaning, 510 Acts wide, with the conjunctive
and disjunctive structure — the exact thing L4 makes checkable — explicitly
inside the editorial power.

Two uses, in order of cheapness:

1. **Phrase-table mining at scale** (§2.8 above): aligned pre- and
   post-revision provisions are exactly the parallel corpus the AI aligns; the
   pairs are already sentence-aligned by section number.
2. **§3.6 with a known expected answer.** Everywhere else the losslessness run
   produces a rate to be interpreted. Here the rate is _supposed_ to be 100%:
   encode the pre-revision text, encode the 2020 text cleanroom, run the diff
   oracle. Every divergence is an encoding error, an oracle limit, or a
   revision that changed the law — and the third kind has a statutory home in
   s 23. That is a finding a drafting office can act on, which is Matt's
   interest and PLUS's own stated aim, met from the outside.

A pilot is already half-built: `jl4/examples/legal/sg-succession/` encodes the
Wills Act 1838, the Intestate Succession Act 1967, the Probate and
Administration Act 1934 and the Guardianship of Infants Act 1934 from the
2020 text, with batteries and asserts. The pre-revision text of the same
sections is the second dialect.

Retrieval caveat, measured 2026-09-02: the lawplain corpus returns the
current consolidation for both its `act_current` and `act_revised` kinds
(probed on the Revised Edition of the Laws Act itself), so the **pre-2020
text is not in hand**; it has to come from Singapore Statutes Online's
point-in-time versions, which this spec has not yet verified are available
per section. The PLUS survey report (AGC, PDF) and the 2021 second-reading
speech on the Statute Law Reform Bill are the primary descriptions of intent.

Nothing here is built and none of it changes Phases 0–2. It changes what the
house-style table in §2.7 is allowed to become: keyed by dialect, and mined
rather than written.

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

- **Text / HTML / AKN:** a hidden per-block id — HTML `id`, AKN `eId` (and
  `GUID`). The text format carries none, which is what §3.6 needs.
- **docx:** bookmarks or content controls (invisible in print, survive Word
  editing reasonably well).
- Anchor identity = module + qualified name + structural path (e.g.
  `decide:the-person-must-not-sell-alcohol/if/and[3]`), **not** line numbers
  or section numbers — robust to reordering and renumbering.

### 3.3 Edit classification

`l4 ingest foo.md --against foo.l4` aligns edited blocks to anchors and
classifies each change:

| Class               | Example                                                                         | Action                                                                                                                                                                                                                                |
| ------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **A. Wording-only** | "body corporate" → "corporate body"; rephrased but logically identical          | Update/insert `@nlg` / `@desc` annotations in the `.l4`. Fully automatic.                                                                                                                                                             |
| **B. Semantic**     | a condition added/struck; threshold changed; "and" → "or"                       | Propose an L4 patch (LLM-assisted), then **validate**: typecheck + existing `#EVAL`/`#CHECK` regressions. Present logic-level diff to a human for confirmation. Tests that intentionally change behavior must be updated consciously. |
| **C. Unalignable**  | anchor destroyed; block deleted or wholesale rewritten; new free-floating prose | Flag for interactive re-formalization; never silently guess.                                                                                                                                                                          |

The Class A / Class B distinction is the heart of the design: most editorial
passes over legislation are wording passes, and those must round-trip into
_annotations_ — leaving the logic untouched and the regeneration trivially
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

### 3.6 Losslessness: the cleanroom round-trip (proposed 2026-09-02, not built)

The lens laws in §3.1 do not answer the question this project keeps being
asked — _is the TNR a lossless view of the L4?_ — and it is worth being exact
about why, because the prototype's own results look as if they do.

`put` takes the source `l4` as an argument. GetPut therefore says that
re-ingesting an unedited document **changes nothing**, which is stability, and
holds trivially whenever the source is in hand. The live prototype (§9,
2026-06-11) goes further: the whole L4 is handed to the LLM as context on every
ingest. That is the right design for an editing lens and it says nothing about
whether the prose _alone_ carries the meaning.

Nor is the answer "compare the generated prose with the original statute". That
measures the composed pipeline, human ingest then `get`, and three things sit
between the number and the claim:

- **echo leakage** — `get` reads `@nlg`, `@desc` and section names, which were
  typed in by someone looking at the statute. High textual fidelity can come
  entirely from those annotations while the logic under them is wrong; the more
  annotation, the less the comparison says.
- **paraphrase penalty** — a lossless IR rendered in a different house style
  scores badly. Fidelity is neither necessary nor sufficient.
- **no localisation** — original-vs-generated cannot say whether the ingest
  dropped a qualifier or the renderer did.

This repo has already ruled the same way twice on the nearest analogues:
`CLAUDE.md` §3.2.1 ("re-parsing is not re-meaning": the `prettyLayout`
round-trip was green while `l4 batch` silently re-associated a boolean) and
`specs/todo/single-instruction-demo/DENOVO-DIFF-ORACLE.md` §2 ("behavioural
first, textual second"). Meaning is measured by evaluation over fact patterns,
not by string comparison.

#### The property

Let `get : L4 → TNR` be the renderer with block ids **off** — the text format
carries none, and a round-trip anchor (§3.2) would carry the qualified name of
its node, which is a hint no reader of the printed statute would have. Let `reencode : TNR → L4` be an encoder that sees the prose and
**nothing else** — not the source `.l4`, not the original statute, not this
repo's corpus. Then

```
l4  ≡_B  reencode (get l4)
```

where `≡_B` is agreement over a shared fact battery, measured pairwise on
declared decision pairs. That is exactly what the §8 diff oracle
(`etc/go/lib/denovo-diff.mjs`) measures between the committed corpus and a de
novo encoding, and it is reused here unchanged: the left side is the corpus
module, the right side is the re-encoding, the surface map declares which
decision on the left pairs with which on the right, and `run` reports an
agreement count plus a minimised witness for every divergence. The oracle never
triages; the dispositions below are the reviewer's.

Note what this does and does not measure. It measures whether **TNR is a
faithful view of the L4**. It does _not_ measure whether the L4 is faithful to
the statute — that is the diff oracle's own G2 question, statute → two
independent encodings, and it stays separate. The composed claim in the
executive summary, that the whole path from legacy text through L4 and back is
meaning-preserving, needs **both** measurements, and neither substitutes for
the other.

Echo leakage does not inflate this number. A re-encoder that reads an `@nlg`
phrase back off the page is reading exactly what a human reader of the printed
instrument would read; if that phrase is enough to recover the decision, the
prose carried the meaning, which is the claim.

#### The bar

The charities cleanroom (PR #201, `jl4/examples/legal/charities-cleanroom/`,
`COMPARISON.md`) is the only two-encodings measurement on record: two
independent encodings _from the same statute_ agreed on 21,221 of 21,420 battery
rows (99.07%), and the 199 divergences reduced to four root causes, one of which
was an unrecorded interpretive fork in our own corpus.

A re-encoding _from generated prose_ is held to that bar as a floor, not a
target. The TNR is one step closer to the L4 than the statute is, so agreement
should be **higher**; if it is lower, the generated prose is lossier than the
statute it stands in for, and that is the finding. Above the floor, the
interesting output is not the rate but the **witness list**: each divergence
names a place where the prose lost something the L4 had.

#### Procedure

Split as ORCHESTRATOR.md §2.1 splits everything — scripts own facts, the skill
owns judgement:

| step         | who             | detail                                                                                                                                                                                                                                                                                                                                                                              |
| ------------ | --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. render    | script          | `l4 render --format text FILE > FILE.txt` — the plain outline today, the legislative style once it exists                                                                                                                                                                                                                                                                           |
| 2. re-encode | cleanroom agent | driven by the `writing-l4-rules` skill, handed **only** the `.txt`; its tool log is audited afterwards the way the charities cleanroom's was — zero reads of the source `.l4`, the corpus, or the statute. Plug `drafting-patterns.md`'s corpus citation first (it leaked Part 6 of the charities corpus last time).                                                                |
| 3. pair      | reviewer        | write the surface map. Names will differ; that is the point. The battery and the pairing conventions are the oracle's existing ones.                                                                                                                                                                                                                                                |
| 4. measure   | script          | `node etc/go/lib/denovo-diff.mjs run --map MAP.json`. Exit 0 or 1 is a measurement; 2 or 4 is a broken harness, never a finding about either side.                                                                                                                                                                                                                                  |
| 5. triage    | reviewer        | each witness is one of: **renderer defect** (the prose under-determines what the L4 fixes — fix `get`, or add the missing hint kind to §2.4); **encoder error** (the prose was sufficient and the agent misread it — discard, but count); **house-style gap** (the prose is ambiguous in a way the statute itself would be — an `@nlg` or connective-table finding, recorded here). |

#### What the oracle cannot see

Inherited from the oracle's own Limits, and not to be worked around silently:

- an enum-typed input cannot be fed across an import boundary (measured
  2026-08-05, recorded in the Reg CF surface map); decisions that take an
  `Interpretation` record are outside the pairing;
- deontic and temporal rules are not decisions; the oracle evaluates `DECIDE`s.
  A deontic body's round-trip needs an LTS comparison, which is out of scope for
  v1 and should be said so in the run receipt rather than counted as agreement;
- `ASSUME`-shaped modules do not evaluate at all.

#### Pilot and exit criterion

This does not wait for the house style. The plain outline is a `get` too, and
running §3.6 on it first gives the style work a baseline it must not regress.

Pilot on `imaginary-alcohol-act.l4` first (small, propositional, statute in the
comments — so the _textual_ comparison can be run beside it as a foil and its
disagreement with the behavioural number recorded), then on
`charities-cleanroom/charity-test.l4`, whose 2,115-row battery and surface map
already exist and need only their right side re-pointed.

Exit: **one measured run on one subject**, with the agreement rate, the witness
list and a disposition for every witness written into §9 of this spec. Until
that entry exists, every sentence in this section is a proposal.

## 4. Pilot Corpus

| File                                          | Why                                                                                                                       |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `jl4/examples/legal/imaginary-alcohol-act.l4` | Original statutory text in comments → direct human comparison; pure propositional structure; the north-star golden (§2.2) |
| `jl4/examples/legal/british-citizen-act.l4`   | Real legislation; deep AND/OR nesting; function application (`father of p`) stresses linearization                        |
| `jl4/examples/legal/ny-environmental-7.3.l4`  | Real regulation; deontics (`PARTY/MUST/WITHIN/HENCE`); `@ref` URL citations                                               |
| `jl4/examples/legal/promissory-note.l4`       | Contract (not statute) — tests that house style is pluggable; chained obligations                                         |
| `doc/reference/syntax/annotation-example.l4`  | Exercises every annotation form                                                                                           |

## 5. Phasing (re-cut 2026-09-02)

| Phase                              | Deliverable                                                                                                                                                                                                                                                         | Exit criterion                                                                                                                                       |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **0. Golden harness**              | `.render.golden` per legal-corpus file from `l4 render --format text`, written by the `jl4/tests/Main.hs` harness; `etc/check-corpus-goldens.mjs` taught the new kind                                                                                               | suite green on the 26-file legal corpus; a style change shows as a golden diff                                                                       |
| **1. Legislative house style**     | §2.3 items 1–5 inside `L4.Export.Render`, behind a `RenderConfig` flag and a CLI flag                                                                                                                                                                               | `imaginary-alcohol-act` renders as §2.2 modulo numbering (the June `.tnr.golden` at `0f90dab7` is the reference); coverage tally clean on the pilots |
| **2. Hints & polish**              | negation hints, whole-rule overrides, definitions section, `@ref` cites (after REF-ANNOTATION-SPEC); deterministic subject-factoring; **AI gloss pass** (§2.6) proposing `@nlg` patches gated by back-translation + goldens; every item lands through the §2.7 loop | british-citizen-act and ny-environmental renders pass review; deontic bodies no longer render as one run-on line on either style                     |
| **3. docx backend**                | pandoc from HTML or the JSON IR + `tnr-reference.docx` styles                                                                                                                                                                                                       | opens in Word with correct paragraph styles                                                                                                          |
| **4. Round-trip: Class A**         | round-trip anchors (§2.3 item 6, §3.2), alignment, wording-edit detection, surgical `@nlg`/`@desc` updates; GetPut + idempotence property tests                                                                                                                     | edit-a-phrase → regen produces minimal diff, `.l4` diff touches only annotations                                                                     |
| **5. Round-trip: Class B/C**       | LLM-assisted semantic patch proposal + typecheck/#EVAL validation gate + human confirmation UX                                                                                                                                                                      | demo: strike a condition in Word, confirm proposed L4 change, regen stable                                                                           |
| **6. Web playground** (§6.1)       | step 1 **exists**: the Render pane re-renders on each successful typecheck via `l4/exportDocument`. Remaining: TNR-side editing through the ingestion path                                                                                                          | edit the rendered pane in the browser → only the corresponding L4 block changes                                                                      |
| **Losslessness** (§3.6, any phase) | one cleanroom run on one subject through the diff oracle                                                                                                                                                                                                            | rate + witness list + dispositions recorded in §9                                                                                                    |

## 6. Delivery Vehicle: Agent Skill

Once the CLI surface stabilizes, these capabilities solidify into an **agent
skill** (in the style of the existing `l4` / `writing-l4-rules` skills) —
call it `l4-tnr` or fold it into the l4 skill as a workflow.

This is not just packaging; it resolves the Phase 5 architecture. The
"LLM-assisted" steps in round-tripping do **not** require embedding an LLM in
the toolchain — the agent _is_ the LLM in the loop, and the deterministic CLI
provides its guardrails:

```
deterministic core (Haskell)          agent skill (prompt + workflow)
─────────────────────────────         ────────────────────────────────
l4 render   render, anchors      ←→   drive renders, present diffs
l4 ingest   align, classify A/B/C ←→  draft Class B semantic patches
l4 check    typecheck, #EVAL      ←→  run validation gate, iterate
exact-print surgical edits        ←→  apply Class A edits mechanically
```

The skill encodes the _workflow_: render → hand to human → ingest edits →
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

1. **L4-edits-first — exists.** The VS Code Render pane re-renders on each
   successful typecheck through `l4/exportDocument`, i.e. `Export.Document`
   behind the language server. This alone demonstrates GetPut stability live:
   the right pane only changes where the L4 changed.
2. **TNR-edits-later:** make the right pane editable and wire the edits
   through the ingestion path (§3) — classification, annotation updates,
   AI-drafted semantic patches — reusing the mass-AI-ingestion tooling we
   already have. The left pane updating in response is the lens running
   in reverse, on screen.

## 7. Testing

- **Goldens:** `.render.golden` per legal-corpus file, same harness as
  `.nlg.golden`. **Does not exist yet** (§2.3, Phase 0).
- **Properties:**
  - idempotence: `render ∘ put ∘ get = render` on unedited docs (GetPut);
  - minimal-diff: for a corpus of synthetic single-block edits, regenerated
    docs differ from edited docs only at the edited anchor (+ renumbering);
  - coverage: no L4 declaration without an anchor in the output.
- **Human eval:** side-by-side of generated TNR vs. original statutory text
  for the alcohol act and british-citizen-act.
- **Losslessness (§3.6):** the cleanroom round-trip measured by the diff
  oracle. Run by hand, not in CI — it needs an agent in the loop and a
  reviewer to triage — and its result is recorded in §9, not asserted by a
  test.

## 8. Open Questions — provisionally resolved (2026-06-10)

1. **Negation-hint syntax** — _deferred to Phase 2._ v1 negates atoms with a
   conservative copula/auxiliary swap (" is " → " is not ", " has " →
   " does not have ", likewise are/have, first occurrence only) and falls
   back to the clumsy-but-faithful "it is not the case that …". On the
   alcohol act this already yields "the person is not a public house".
2. **`#EVAL`s** — _strictly suppressed_ in v1; counted in the trailing
   `tnr-coverage` comment so suppression is visible, not silent. An
   explanatory-notes appendix can come later.
3. **House style** — _hardcoded Commonwealth_ for v1, but every connective /
   lead-in / marker string lives in one place (the house-style
   helpers in `L4.Export.Render`) so making it data-driven later is mechanical.
4. **Anchor visibility** — _hidden HTML comments_, on by default,
   `--no-anchors` to suppress. Robustness against comment-stripping editors
   is a docx-era problem (see 5).
5. **Docx round-trip markers** — _deferred to Phase 3_ (bookmarks vs.
   content controls vs. fuzzy-match sidecar).

## 9. Status

Entries before 2026-09-02 describe `L4.TNR` and its demo in the present
tense. That code was removed on 2026-09-02 (§10); the entries stay as the
record of what the demonstrator showed, retrievable at `0f90dab7`.

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
- **2026-06-10 (later)** — built and verified: `l4 tnr` output is
  byte-identical to the scaffold; possessive spacing fixed; static
  two-pane demo at `specs/todo/tnr-prototype/demo/` (L4 left, TNR on
  statute paper right, anchor toggle). First de-stilting transform
  landed: **negative-universal rewrite** — "the X must not VP" with all
  conditions predicated of "the X" renders as "No X may VP who—" with
  subject elision and verb-factored nested groups ("(e) has— (i) an
  unspent conviction…"). Purely syntactic, total (declines on mixed
  subjects: alcohol-act provisions 2–3 unchanged), and minimal-diff
  (regeneration touched only the rewritten provision). The Python
  scaffold does NOT implement this transform and is now behind the
  Haskell.
- **2026-06-11** — round-trip prototype live (demo/server.py + editable
  TNR pane): human edits TNR in browser → `claude -p` proposes L4 →
  `l4 check` gates with diagnostics-feedback retry → canonical re-render.
  E2E verified on wording, numeric and semantic edits (typecheck attempt
  1, minimal diffs). Hierarchical segmentation: edited TNR aligns to the
  canonical render by anchor; only changed sections go to the LLM as
  before/after pairs (whole L4 stays as context so renames remain
  global); zero changed sections short-circuits in ~30ms with no LLM
  call; skeleton changes fall back to full-document mode. Akoma Ntoso
  export (`/api/akn`) added; all six demo instruments well-formed per
  xmllint. Latency: `claude -p` varies 10–90s; tiered model escalation
  (haiku→sonnet) is the obvious untried lever.
- **2026-09-02** — branch merged up to `unstable` (1,293 commits of drift;
  two add/add conflicts in `jl4/app/Main.hs` and `jl4/tests/Main.hs`, both
  wiring). The legal corpus has grown from 8 files to 26 since the fork, so
  the `tnr` harness now wants 18 new goldens. §3.6 written; **not run**.
  Finding recorded as §10.
- **2026-09-02 (later)** — **ruled** (§10): keep the thinking, drop the code.
  `L4.TNR`, `l4 tnr`, the `tnr` describe block, the 26 `.tnr.golden` files and
  `specs/todo/tnr-prototype/` removed; the five wiring/cabal/`Nlg.hs` touches
  restored to `unstable`'s versions. The branch's diff against `unstable` is
  now this file. §1.2, §2.3, §5, §6.1, §7 rewritten against `Export.Document`;
  §3.6 re-pointed at `l4 render --format text`. §2.7 added: the
  complaint-to-rule loop the demonstrator ran on, with its three landing
  levels and the golden diff as acceptance evidence.

## 10. The second renderer — RULED 2026-09-02

While this branch sat unmerged, `unstable` grew a second module-level document
renderer: `L4.Export.Document` (the IR) and `L4.Export.Render` (text, HTML,
Akoma Ntoso), commit `2bb2b6d5` of 2026-06-14, three days after this branch's
last commit. It is the code behind the VS Code **Render** pane (custom LSP
request `l4/exportDocument`, `ts-shared/jl4-client-rpc/custom-protocol.ts`),
behind `l4 render`, and behind `jl4-lsp`'s export plan. It has no spec of its
own; four other specs cite its line numbers. Both renderers share
`L4.Nlg.simpleLinearizer` for leaf phrases; the duplication is the document
walk, sectioning, definitions handling and connective house style.

A third surface borrows the name: `l4 nlg` and the go orchestrator's
`p7-tnr.sh` call themselves the "TNR / NLG leg" but linearize directives only.
They are not a document renderer and should not be read as one.

|                | `L4.TNR` (at `0f90dab7`)                                                | `L4.Export.Document` + `Render` (`unstable`)                          |
| -------------- | ----------------------------------------------------------------------- | --------------------------------------------------------------------- |
| lines          | 690                                                                     | 1,633 + 649                                                           |
| output         | Markdown, Coode tabulation                                              | text, HTML, AKN, JSON IR, plan                                        |
| block identity | hidden `<!-- l4: … -->` anchors, designed as round-trip identity (§3.2) | per-block `id` / AKN `eId`, `<sort>_<n>_<module>`, designed for links |
| extras         | coverage tally; negative-universal rewrite; `.tnr.golden`               | imports checklist; unused-definition pruning; numbering knobs         |
| wired into     | `l4 tnr`, jl4-test                                                      | VS Code Render pane, `l4 render`, jl4-lsp                             |
| spec           | this file                                                               | none                                                                  |

**Side-by-side, measured 2026-09-02** on the merged tree, both binaries from
one build. On `imaginary-alcohol-act.l4` (propositional, statute in the
comments): `l4 tnr --no-anchors` gives three numbered provisions in Coode
tabulation, the first as "No person may sell alcohol who— (a) is a body
corporate; … (e) has— (i) …; or (iii) …", 41 lines, reading as the statute
reads. `l4 render --format text` gives an "Assumptions" list of fourteen
bullets of the form "The person is a body corporate is assumed to be given",
then each rule as "X means: all of the following are true:" with negation
rendered "the person is a public house is false" and a negated conjunction as
one run-on line, 58 lines. On `ny-environmental-7.3.l4` (records, deontics,
fixtures) **neither** renderer copes: both emit the deontic body as a single
run-on line, and both render the example fixtures as provisions. So the two
are not duplicates of one strength. `L4.TNR` has the legislative house style
for propositional rules — tabulation, subject elision, the negative-universal
rewrite, atom inlining — and `Export.Document`/`Render` has the plumbing —
imports, reachability, HTML/AKN, LSP wiring. Deontics and record-shaped rules
are open on both sides (this spec's Phase 2 worklist, §9).

**Ruling (Meng, 2026-09-02).** `L4.TNR` was about half an hour of model time,
built as a demonstrator; the thinking in this spec is worth keeping and the
code is not. So: `Export.Document` + `Export.Render` is the renderer; the
demonstrator's house style is its worklist (§2.3), with the alcohol-act
rendering it produced as the target (§2.2); this spec keeps the lens laws
(§3.1), the anchors (§3.2), the edit classes (§3.3), the losslessness property
(§3.6) and the AI-gloss doctrine (§2.6), all of which are renderer-independent.
The code, its goldens and the prototype demo were removed from the branch in
the commit after `0f90dab7`; that hash is where to look if a detail of the
demonstrator is wanted.
