# RFC: `l4-lint` — a safe layout formatter + opt-in codemod layer for L4

Status: DRAFT for review. Synthesizes four design lenses (architecture, taxonomy,
layout, rename) and their four adversarial critiques into a single buildable plan.
Scope: design only — no implementation in this RFC.

---

## 0. ⚠️ POST-RFC RESOLUTION — Q1 settled empirically: **DISPLAY WIDTH** (2026-06-29)

The headline open question (§6 Q1) — does the lexer resolve `^` by code-point or display-width
columns? — has been **settled by experiment, and it is DISPLAY WIDTH**. The RFC's §4.1 ruling for
code points was **wrong**: the lone adversarial reviewer who *executed* the lexer was right, and the
three who *read the source* (no `wcwidth` table → "must be code points") were misled.

**Evidence (all against the real `~/.local/bin/l4`):**
1. *Ditto-binding test.* The same `^`, aligned two ways after a `中`, with an input chosen so the
   bound conjunct flips the result: the **display-width**-aligned caret binds correctly
   (`f(x,zzz)=FALSE`); the **code-point**-aligned one silently loses the conjunct (`=TRUE`).
2. *`l4 ast` columns.* A line of 43 code points containing one `中` reports `end column = 45` — i.e.
   44 display columns + 1. The AST source positions ARE display-width.
3. *Width characterization* (via `l4 ast` end-column deltas): East-Asian **Wide/Fullwidth = 2**
   (`中`/`字`/`가`/`Ａ`/`😀`); ASCII, half-width kana, NBSP, precomposed `é` = 1; **combining mark = 1**
   (so NOT true `wcwidth`); ZWJ emoji sequences summed per code point (**no grapheme clustering**);
   tab = tab-stop. Net: **East_Asian_Width W/F → 2, else → 1, per code point.**

**What flips (supersedes the body below where they conflict):**
- §4.1 metric → **display width** (`displayWidth`), not `Text.length`. dmnmd's `displayWidth` is the
  **correct** basis, not the latent bug — *except* its range table **misses the wide-emoji blocks**
  (it scores `😀` as 1); the correct table adds U+1F300–1F64F / 1F900–1F9FF / 1FA70–1FAFF.
- §6 Q1 → **RESOLVED: display width.** The golden test is no longer a blocker; it is retained as a
  **regression** pinning the exact width function to the lexer.
- §4.7 "do not bail ditto for CJK / visual blemish" → **moot**: under display-width padding CJK
  carets are both correct *and* visually aligned.
- The verifier's column logic and the summary's "code points; kill `displayWidth`" → display width.

**Already actioned:** `L4.Print.Columnar` now measures `displayWidth` (East-Asian table + emoji
blocks) and gained a single-token ditto guard (a `^` copies exactly one token, so `AT MOST` can't
collapse). `cabal build jl4-core` green. The mechanism by which stock-megaparsec columns come out
display-width is unexplained from source — itself the strongest argument for the single shared,
golden-pinned kernel this RFC proposes.

---

## 1. Thesis

`l4-lint` is **two tools wearing one codebase**, separated by *proof obligation*, not by surface effect:

1. **A formatter** (`l4 format`) — default-on, silent, opinionated, **idempotent** layout
   rules. Headline rule: **COLUMNAR** (align `BRANCH` arms into columns; collapse repeated
   guard tokens to the ditto operator `^`). Its safety contract is the strongest available:
   *the post-resolution AST and the comment/prose trivia of the output are provably identical
   to the input, verified on every run, with fallback to the unchanged input bytes on any
   doubt.*

2. **A codemod / suggestion layer** (`l4 lint`, `l4 rename`) — opt-in, reviewed-diff, never
   on-save. Headline rule: **camelCase → `` `back tick spaced` ``** rename. Its contract is
   *weaker and different*: semantics-preserving modulo a consistent renaming (alpha-equivalence),
   which deliberately changes meaning-bearing tokens and therefore **cannot** ride the
   formatter's byte-equal envelope.

**The organizing axis is the proof obligation, because it mechanically determines the trust
model, which determines default-on vs opt-in.** The dividing question is precise: *is the
transform closed under resolved-AST equality (and trivia-preserving)?*

| Class | Obligation | Mutates meaning-bearing tokens? | Trust model | Default |
|---|---|---|---|---|
| **Layout** | resolved-AST equal **and** trivia-multiset preserved **and** `f(f(x))==f(x)` | No (whitespace + the `^` token only) | verified every run; region-scoped fallback-to-bytes | **ON, silent** |
| **Codemod** | alpha-equivalence (Unique-graph iso up to substitution) over the **import closure** | Yes, on explicit request | reviewed diff, conflict-checked, atomic | **OFF** |
| **Suggestion** | none — pure analysis → diagnostics | No (read-only; a *fix* is delegated to Codemod) | advisory, per-rule/per-site config | **ON as diagnostics** |

This is exactly Go's own split (`gofmt` / `gofmt -r`+`gopls rename` / `go vet`), which is the
evidence the cut is natural. The two halves must stay **architecturally distinct**: one engine,
one edit primitive, but two verbs and two verifiers.

The single most consequential ruling in this RFC — that the column-alignment metric is **code
points, not display width** — is also the one place two adversarial reviewers reported opposite
empirical results. See §4.1 and §6.

---

## 2. Architecture

### 2.1 Strategy: surgical CST rewrite, not whole-file reprint

Three candidate strategies, judged against the hard facts of jl4-core:

| Strategy | Verdict |
|---|---|
| **A. Pure AST reprint** (`prettyLayout`) | **Rejected.** `L4.Print.printWithLayout`/`prettyLayout` consults only the AST node and **drops every comment, trailing trivia, and `Inert` prose** (Print.hs:161-172). Fatal for statutory L4 where prose is interleaved. |
| **B. Whole-file CST reprint** (ormolu-style) | Viable but high blast radius: every line regenerated, so any `displayPosToken`/trivia bug corrupts *untouched* code. Noisy diffs. |
| **C. Surgical span rewrite** (apply-refact-style) | **Chosen.** Emit `TextEdit`s only for spans a rule actively changes; **byte-copy** the rest. Untouched code is byte-identical by construction; comment-safety for untouched regions is trivially true. |

Synthesis: **globally C** (byte-preserving, surgical), **locally a bounded reprint inside each
touched group**, where the group renderer sources its cell text from **concrete tokens with
attached trivia**, never from `prettyLayout`. AST-reprint is demoted from a whole-file strategy
to an implementation detail of the region renderer.

`L4.ExactPrint.exactprint` is **not** the fallback serializer and **not** byte-verbatim: it
reconstructs text from tokens via `displayPosToken`, re-renders resolved carets back to `^`
(Lexer.hs:1035-1037), and can normalize trivia — and today's `l4 format` (`Rules.ExactPrint`)
*exits 1 and prints nothing* on parse/typecheck failure (Cli/Format.hs). **Ruling: the fallback
path returns the original source bytes with no printer in the loop.** exactprint survives only
as an internal serializer for fully-parsed passthrough, never as the safety net.

### 2.2 The IR and the unifying edit primitive

IR = jl4-core's already-parsed `Module Name` with its `Anno`. We do **not** invent a new CST.
The `Anno_` payload (`AnnoHole` for child subtrees, `AnnoCsn (CsnCluster_ t)` for real tokens,
`trailing` carrying `TSpace`/`TLineComment`/`TBlockComment` trivia — Annotation.hs) *is* the
concrete-syntax-with-trivia tree. `l4-lint` reads it; it does not rebuild it.

Every rule emits the same thing:

```haskell
type Edit = (SrcRange, Text)            -- LSP TextEdit: replace this span with this text
data RuleClass = Layout | Codemod | Diagnostic
class Rule r where
  ruleClass :: r -> RuleClass
  runRule   :: r -> Target -> [Edit]    -- Target carries source bytes + parsed (or resolved) module
```

This single primitive is why CLI `--fix`, LSP `textDocument/formatting`, and LSP `codeAction`
are the same machinery — they differ only in how `[Edit]` is delivered.

### 2.3 Package shape (keeping the columnar core light enough for dmnmd)

```
l4-columnar     (NEW; deps: base, text ONLY — no jl4-core)
  └─ L4.Columnar  -- LCell, Grid, DittoOpts, renderDittoGrid, width metric (§4.1)
        ▲                              ▲
   jl4-core / dmnmd             l4-lint  (NEW lib; deps: jl4-core + l4-columnar)
   (dmnmd consumes columnar     ├─ L4.Lint.Engine      -- Edit, Rule, applier, verifier, fixpoint guard
    WITHOUT pulling jl4-core)   ├─ L4.Lint.Layout      -- AST(MultiWayIf/DECLARE/GIVEN/…)→Grid bridge + region renderer
                                ├─ L4.Lint.Rename      -- de-ditto → rename → re-columnar pipeline
                                ├─ L4.Lint.Rule        -- registry, severity, suppression pragmas
                                └─ L4.Lint.AndOrDepth  -- MOVED from jl4-core (existing checkAndOrDepth)
        ▲                              ▲
       jl4 (CLI: `l4 format`, `l4 lint`, `l4 rename`)
       jl4-lsp (formatting + rangeFormatting + codeAction + diagnostics)
```

`l4-columnar` is the extraction target. It stays `text`-only so dmnmd keeps consuming columnar
layout without ever depending on jl4-core. **The AST→Grid bridge (`multiWayIfGrid`,
`conjunctCells`, `scanAnd`/`scanOr`) does NOT move into the kernel** — it is jl4-core-specific
(knows `Expr`/`MultiWayIf`) and lives in `L4.Lint.Layout`. The kernel is lexer-agnostic; the
caller (which has tokens) classifies cells (§4.4).

`AndOrDepth` moves cleanly: only `jl4-lsp` `Rules.hs:397` consumes it, so no dependency cycle.

### 2.4 Engine pipeline

1. **parse** source → `Module Name` (jl4-core lexer+parser; `mkPosTokens` resolves input `^` to
   real tokens here, so the formatter never sees authorial carets — it regenerates them).
2. **(codemod verb only)** resolve → `Module Resolved`; run the rename pipeline (§4.5); reparse.
3. **(format verb)** run Layout rules on `Module Name` → one edit per alignment group; each
   replacement produced by the region renderer (§4.2-4.4).
4. **apply** edits (non-overlapping by construction: groups disjoint, rename sites distinct).
5. **verify** (§2.5), **per region**: reparse candidate; assert resolved-AST equal **and**
   trivia-multiset preserved for that region. On failure → that region reverts to **original
   bytes** (other regions keep their edits).
6. **(CI/debug)** assert idempotency `format(candidate) == candidate` and effectiveness.

L4 files are human-scale; the reparse in step 2 is cheap. We deliberately choose **reparse over
incremental `Anno`-span offset patching** — simplicity over cleverness.

### 2.5 The verifier (this is where three critiques converged)

Annotation-erased AST equality alone is **necessary but not sufficient**. It is blind to the two
failures a formatter must never commit, and to a third:

- **Comment loss/relocation.** Comments are `Anno` trivia; erasing `Anno` erases them. A relaid
  group that drops or moves a comment **passes** bare-AST equality. → The verifier must include a
  **trivia obligation**: the multiset of comment/`§` tokens (and each comment's resolved anchor
  token) in `out` equals that in `in`. (`Inert` prose text *is* in the AST — Syntax.hs:243 — so
  it is covered by AST equality, but comments are not.)
- **Non-convergence.** The gate tests `in≡out`, not `f(f(x))==f(x)`. A resolve-preserving
  formatter can still oscillate. → Idempotency is a **CI obligation** over a corpus, plus a
  bounded **N=2 fixpoint guard** in the engine that bails to identity if a rule fails to converge.
- **Silent no-op masquerading as success.** If the equivalence relation is even slightly too
  strict (e.g. shipped as derived `==` over the *annotated* AST — which is `False` for any
  reformat), the verifier fails every file → emits input unchanged → the formatter is a no-op,
  **and `format∘format=format` is green for the identity function.** → CI must include an
  **effectiveness corpus**: deliberately-unformatted fixtures where `format(x) ≠ x` is *required*.

**Needed new primitive (a concrete deliverable, not free):** there is no `stripAnno` /
alpha-equivalence in jl4-core today — `Syntax` only derives `Eq` over the *annotated* AST. We must
build `π_AST`: instantiate the tree with `Anno` erased to `()` **and** compare `Name`s by resolved
`Unique`, not surface text. Pin it with golden tests on pairs known-equivalent (`^`-form vs
spelled-out) and known-different.

### 2.6 LSP / CLI surface and relationship to existing `l4 format`

- **`l4 format`** is *upgraded* from today's exact-print identity into the opinionated Layout
  formatter: columnar default-on, `--reindent-only`, `--check` (gofmt -l), `--diff`. **This is a
  genuine behavior change** — `format` stops being an identity pass. The old behavior is reachable
  as `--passthrough`. **`--check` must distinguish three states**, not two: *formatted*,
  *would-change* (exit non-zero, list files), and *refused-region* (exit non-zero, list regions
  that could not be verified) — so CI never goes green on a file the tool silently declined to touch.
- **`l4 lint [--fix]`** is new: Diagnostic rules, severity-tagged, `--fix` routes accepted hints
  through the Codemod class.
- **`l4 rename <name>`** is new: the camelCase→backtick codemod directly (§4.5), dry-run default.
- **Shake rules** (`jl4-lsp/src/LSP/L4/Rules.hs`): `Rules.Format` consumes **`GetParsedAst`**
  (parse-only — layout needs no resolution, so it runs on non-typechecking files, exactly when you
  most want formatting); `Rules.Lint`/`Rules.Rename` consume **`TypeCheck`/`GetResolved`**.
- **LSP**: `textDocument/formatting` + `rangeFormatting` → Format engine returns `TextEdit[]`
  (range-formatting = relayout only the groups overlapping the range). `codeAction` → rename +
  diagnostic fixes. Suppression pragma `{-# l4-format off #-}` … `{-# l4-format on #-}` parsed as
  `TLineComment` trivia and read as a hard byte-preserve region — the fourmolu anti-fork
  pressure-valve.

---

## 3. Rule catalogue

Severity legend: **error** blocks CI; **warning** visible non-blocking; **hint** info + optional
fix; **suggestion** = codemod offered explicitly.

### 3.1 Layout (Class A, default-ON, no per-rule toggles)

Engine = `L4.Columnar` consumed by `L4.Lint.Layout`. Cells sourced from **concrete tokens with
trivia**, never `prettyLayout`. Group boundary = blank line, full-line comment, `§` section
marker, `Inert` prose, arity change.

| # | Rule | Default | Safety notes |
|---|---|---|---|
| A1 | **COLUMNAR** — align `BRANCH` arms into guard columns + collapse repeated guard tokens → `^` | ON | Caret collapse is **verification-gated per group** (§4.6): a group collapses only if it round-trips; otherwise it silently degrades to A2 (reindent, spelled-out). Requires the single-lexical-token guard (§4.4) and prev-non-blank-line adjacency (§4.3). |
| A2 | **REINDENT-TO-COLUMNS** — reflow guard/result to shared column slots, no `^` | ON | The engine with `enableDitto=False` (kernel's "safe oracle mode"). 100% of alignment benefit, zero caret-resolution fragility. **This is the always-safe substrate A1 degrades to.** |
| A3 | **Align IS / MEANS / THEN** across sibling decls/arms | ON | Must be part of the **single joint layout solve** (§4.7), not an independent pad-to-max pass, or it fights A1/A4. |
| A4 | **Align DECLARE record fields + types** into columns | ON | Same joint-solve constraint. |
| A5 | **Align GIVEN / GIVETH signature blocks** | ON | Same. |
| A6 | **Align asyndetic `...` / `..` list items** vertically | ON | Same. |
| A7 | **Gutter normalization + trailing-whitespace strip** | ON | **Right-strip each emitted line** (the kernel deliberately does NOT — that is correct for its suffix-appending callers, but a file formatter must strip or it fights `trailing-whitespace` pre-commit hooks and breaks `--check`). Padding *after* the last token is layout-inert; padding *left of* it is load-bearing — strip only the former. |
| A8 | **Blank-line + `§` spacing normalization** (≤1 blank between decls) | ON | Safe for ditto: `mkPosTokens` skips whitespace-only lines when snapshotting `prevLineToks` (Lexer.hs:683). |

**Excluded from A** (looks like layout, isn't safe): tab→space *as a silent rewrite* (handled
explicitly per §4.8, not ignored); any reflow of `Inert` prose (byte-preserved, immovable);
trailing-comment column alignment (clang `AlignTrailingComments` — width swings with comment
length, threatens idempotency; leave trailing comments where they fall).

### 3.2 Codemod (Class B, OPT-IN, reviewed diff, atomic per file/closure)

| # | Rule | Obligation | Default | Notes |
|---|---|---|---|---|
| B1 | **camelCase / snake_case → `` `back tick spaced` ``** | alpha-equiv | OFF | The pipeline of §4.5. Resolver-driven, refuse-on-collision, import-closure-scoped, statute-desync guard. |
| B2 | **Redundant-backtick removal** (`` `foo` `` → `foo`) | alpha-equiv | OFF | Exact inverse of `quoteIfNeeded` (Print.hs:818) — the canonical predicate both must agree on. |
| B3 | **Qualified-name canonicalization** | alpha-equiv | OFF | Shortest unambiguous form. |
| B4 | **Shadowing-rename** (disambiguate a shadowing binder) | alpha-equiv | OFF | Same machinery as B1; collision check is *mandatory*, shared with B1. |
| B5 | **Denotation-preserving simplifications** (`IF x THEN TRUE ELSE FALSE`→`x`; drop dead `OTHERWISE`; remove unreachable arm) | **denotational** equiv (needs typechecker/solver) | OFF | The apply-side of C2/C5/C6/C7 fixes. **C detects, B applies.** |

### 3.3 Suggestion (Class C, advisory, hlint-style configurable), ranked by value

Pure analysis over `Module Name` / `Module Resolved` → diagnostics, like the in-tree
`L4.Lint.AndOrDepth.checkAndOrDepth`.

| # | Lint | Default sev | Needs | Why it matters (L4-specific) |
|---|---|---|---|---|
| C1 | **Fragile / unresolvable ditto** — a `^` whose column resolves to *nothing* on the previous non-blank line | **error** | lexer | The silent footgun. Re-run `findMatchingToken`; **error only when it resolves to `Nothing`** (an actual miscompile/parse hazard). |
| C1b | **Suspicious ditto** — `^` resolves, but to a token the author plausibly didn't mean | warning | lexer | Split from C1: "plausibly meant" is not computable, so it must not block CI. |
| C2 | **Deontic / temporal double-bind** — obligation to do X co-reachable with prohibition on X | **error** | reasoner API | The crown jewel (the gov-agency race condition). Beyond lexer/parser — depends on the reasoner, so it does **not** gate the taxonomy's launch. |
| C3 | **Mixed AND/OR at same column** | warning | AST | **Already implemented** (`AndOrDepth`). Adopt as-is. |
| C4 | **Non-exhaustive CONSIDER** — pattern match over a DECLARE'd sum missing a constructor | warning (→error opt) | types | GHC `-Wincomplete-patterns` analogue. |
| C5 | **Unreachable BRANCH arm** — guard subsumed by an earlier arm | warning | AST (+solver) | Syntactic subsumption first; escalate with solver. Fix = B5. |
| C6 | **Dead / redundant OTHERWISE** — guards already exhaustive | hint | types | Fix = B5. |
| C7 | **Redundant boolean** — `… THEN TRUE ELSE FALSE`, `x AND TRUE` | hint | AST | `scanAnd`/`scanOr` to flatten. Fix = B5. |
| C8 | **Overlapping / nondeterministic guards** — two arms simultaneously satisfiable, different results | warning | solver | The insurance-leak class. |
| C9 | **Unused binding** — a `Def` Unique with zero `Ref` | hint | resolver | `FindReferences` directly. |
| C10 | **Out-of-scope reference** — `OutOfScope` in `Resolved` | error | resolver | Catches pre-typecheck. |
| C11 | **camelCase identifier present** — style nudge toward B1 | hint | resolver | The bridge: C detects style drift, offers B1 as fix. |

---

## 4. The hard problems & rulings

### 4.1 Column-alignment metric: **display width (with tab expansion)** — RULING (corrected; see §0)

> **CORRECTED.** This section originally ruled for *code points* on the strength of a source read
> (no `wcwidth` table in `jl4-core/src`, the lexer reads only `unPos sourceColumn`). That was
> **empirically refuted** — see §0. The metric is **display width**. The reasoning is kept for the
> record but its ruling is inverted.

`^` is resolved **in the lexer** by exact start-column match (`findMatchingToken`,
`pt.range.start.column == c`). Column position is therefore *meaning-bearing*; the metric must
mirror the lexer exactly. The source has no width-table code, which *looked* like code points — but
the lexer's reported columns come out display-width regardless (mechanism unexplained; a
megaparsec-version behavior, pinned by the §6 golden regression).

**Ruling: the kernel measures cell width in DISPLAY width (East_Asian_Width W/F → 2, else → 1, per
code point), with tabs expanded to tab stops. dmnmd's `displayWidth`/`isWideChar` IS the correct
basis (extended with the wide-emoji blocks it omits).** `L4.Print.Columnar` has been updated from
`Text.length` to `displayWidth` accordingly.

Accepted, stated consequence: a CJK/Tamil guard column is aligned **for the lexer, not for the
eye** — `中` advances one lexer column but renders two glyph-widths, so a lexically-correct table
can *look* ragged. **Carets remain correct under code-point padding even with CJK** (they only
look misaligned), so we do **not** bail ditto for CJK — it is a visual blemish, not a correctness
failure. If the language team ever wants "what you see is what resolves," the fix is in the
**lexer** (teach it display-width advance), and *then* the metric here flips. The metric is a
mirror of the lexer, not a formatter preference.

**Caveat — this is the one place the reconnaissance disagreed with itself.** One adversarial
reviewer reported executing the real lexer on `中 foo\n^  ^` and observing display-width behavior
(`foo` at column 4, caret-at-col-4 copying `foo`). That directly contradicts (a) the absence of
any width-table code in the source, (b) megaparsec's documented `Stream Text` behavior, and
(c) two other reviewers who inspected the same files. The weight of evidence is overwhelmingly
code points, so this RFC rules for code points — **but because the disagreement is empirical and
load-bearing, it is settled by a mandatory golden test before any code is written** (§6, Q1):
round-trip a CJK + emoji + combining-mark + tab `BRANCH` through the real `execLexer` and assert
which column each `^` binds. Both camps already agree the metric *must* mirror the lexer; the test
is the adjudicator. Pin the megaparsec version as part of the formatter's contract.

### 4.2 Comment / `Inert`-prose preservation: the actually-hard part

`prettyLayout` reads only the AST node and discards comments, trailing trivia, and `Inert`. Only
`exactprint` preserves them, via `CsnCluster_.trailing`. The two paths are disjoint and **neither
alone is a formatter.** Architectural commitment:

> The layout pass is a **targeted token-stream rewrite inside `Anno` clusters**, never a
> whole-file re-`prettyLayout`. Grid cell text comes from the existing **concrete tokens**
> (their `CsnCluster_` payload + `trailing`), not from reprinting the AST. Only the *inter-token
> whitespace within a detected group* is regenerated. Everything else is byte-preserved.

This dissolves most of the comment problem: if cells carry real tokens with attached trivia,
comments ride along. The cell type the engine consumes is therefore richer than today's
`type Cell = Maybe Text`:

```haskell
data LCell = LCell
  { cellToken  :: Maybe Text     -- the resolvable token, or Nothing (absent slot)
  , cellLead   :: [Trivia]       -- comments/space BEFORE the token, attached to it
  , cellTrail  :: [Trivia]       -- comments/space AFTER, same line
  , cellAtomic :: Bool           -- True iff exactly ONE lexer token (the singleToken guard)
  }
```

Trivia rulings, by kind:

1. **Row-trailing `-- comment`**: attaches to the last cell's `cellTrail`, emitted after padding
   (`… THEN result   -- note`); never counted in column width. No trailing-comment column (§3.1).
2. **Full-line comment between rows**: a **hard group boundary** (clang `AcrossComments=false`).
   This is **mandatory for correctness, not cosmetic**: the lexer skips comment-only lines when
   computing `prevLineToks` (they lex as `TSpaces`), so the grid's "row above" and the lexer's
   "nearest non-blank-non-comment row above" agree **only if** no comment/blank line sits between
   two caret-bearing rows. The boundary enforces exactly that. Relaxing it (an "AcrossComments"
   feature) is one refactor away from silent caret miscompile — document *why* it is forbidden.
3. **`Inert` verbatim prose**: immovable, byte-preserved, hard group boundary, internal whitespace
   never touched even inside a `{-# l4-format on #-}` region. **But `Inert` is NOT trivia** — see
   §4.3.
4. **Comment *inside* a row** (between two guard tokens): if any cell has interior
   `cellLead`/`cellTrail`, the row is **non-alignable** — emit it plain, break the group. Do not
   thread a comment through a padded column.

### 4.3 `Inert` is a semantic node, and the transitive caret chain breaks on real tokens

Two corrections the layout/architecture critiques surfaced:

- **`Inert` (Syntax.hs:243) is a real `Expr`**, not trivia. It evaluates to its boolean operator's
  identity (AND→True, OR→False), assigned during typecheck (`setInertContext`). When inert prose is
  interleaved *between conjuncts of one guard* (the brief says this is the common case),
  `scanAnd`/`scanOr` return it as a conjunct and `conjunctCells` emits it as a cell. **Ruling: treat
  `Inert` as a first-class compound grid cell — never dittoable, never width-collapsed — and state
  that layout tolerates `InertCtxNone`** (layout runs on `Module Name`, pre-typecheck, so
  `InertContext` is unset).
- **Annotation lines and `Inert` lines are real tokens, not whitespace** (Lexer.hs:682 comment:
  "currently not annotations"). The lexer's `^` resolves against the **immediately preceding
  non-whitespace line** (`prevLineToks`), transitively (`computedPayload`/`RealTCopy`). Comments are
  `TSpaces` → skipped (chain survives). But an `@nlg`/`@desc` line or an interleaved inert-prose line
  **becomes `prevLineToks`**, so a `^` on the line below resolves against *its* columns. **Ruling:
  caret eligibility is computed against the lexer's `prevLineToks` rule (previous non-whitespace
  physical line), NOT the grid's logical row index `i-1`.** Annotation/`Inert` lines force
  "spell out," never "collapse." The `Columnar` engine must take an explicit *"row above is the
  lexer's predecessor"* bit per row rather than assuming `i-1`.

### 4.4 The single-lexical-token guard (Atom vs Compound) — classify by token count, not by role

The dmnmd twin guards collapse with `singleToken t = ' ' notElem t`; `L4.Print.Columnar` **lacks
this guard — a latent miscompile today.** A `^` copies exactly one token, so any multi-token cell
must never collapse. The cell type carries `cellAtomic`, but the *classification rule* must be
correct:

- **Wrong rule** (one critique's): "value of a comparison = Atom." The value is `prettyLayout r`
  for an arbitrary `Expr`; `field > 100 USD`, `x >= y + 1` all produce **multi-token** value cells.
  And the multi-token *operators* `AT MOST` / `AT LEAST` / `LESS THAN` / `GREATER THAN`
  (`conjunctCells`, Print.hs:143-153) are each **two tokens** — collapsing the second `AT MOST` to
  `^` copies `AT` and drops `MOST`. **This is a miscompile in the code path today, on the default
  rendering of every such comparison.**
- **Ruling: `cellAtomic = True` iff the cell is exactly one lexer token.** Classify by `Expr`
  atomicity (literal / bare var / backtick-quoted name → atomic; a `` `card to use` `` is a single
  `TQuoted` lexeme, Lexer.hs:444) **or** re-lex the rendered cell and count tokens. Single-
  lexical-token-ness — not "is it a comparison value" — is the gate. Non-atomic cells still *align*;
  they just never collapse to `^`.

### 4.5 Rename: de-ditto → rename → re-columnar (RENAME depends on COLUMNAR, is not its sibling)

The rename critique's P1/P2 are decisive and change the rename architecture. `findReferences`
returns **caret spans**: when a `^` dittoes an identifier, the parser sees a normal `Ref`, but its
`SrcRange` is the **single `^` character**, not the name text (Lexer.hs:687-700; carets are
transitive). So a naïve span-edit inserts the full 13-char `` `card to use` `` at a 1-char caret
span — different width deltas at def vs ref vs caret sites — which **guarantees** column desync to
the right of any caret, dangling every downstream `^` (exact-column match). The alpha-eq gate then
*refuses*, so the feature **silently no-ops on exactly the collapsed columnar tables it exists to
serve.**

**Ruling — the rename pipeline:**

1. **de-ditto** — expand every `^` in affected groups to the literal token the lexer already
   resolved (`TCopy (Just tt)` / `RealTCopy` carries it for free). Now every occurrence is
   full-width; width deltas are uniform.
2. **rename** — span-edits on the de-dittoed source. Target = a `Unique` (from cursor or name arg);
   rename set = every `Resolved` whose `getUnique == target`, spans via `buildReferenceMapping` /
   `findReferences`. Split words with `camelSplit`; emit via `quote`/`quoteIfNeeded` so the rename
   agrees byte-for-byte with the printer's own quoting rule.
3. **re-columnar** — re-run the default Layout pass so the output is a **fixed point of the
   formatter** (`columnar(rename(x)) == rename(x)`), through the **same comment-preserving engine**
   built for this package — never `prettyLayout`.

This makes RENAME a **dependent of COLUMNAR**, routed through its engine. The "we never round-trip
through `prettyLayout` so comments survive" guarantee holds only on the pure span-edit path; once
we re-columnar, comment-safety is inherited from the §4.2 engine, not from avoiding reprint.

**Split rules** (`camelSplit :: Text -> Either Refusal [Word]`): boundaries are only (1) lower→upper
case transition and (2) underscore. Lowercase each word, join with single spaces. **The acronym
rule is a guess and is tiered by confidence:** pure lower→upper and snake_case = HIGH (auto-eligible);
caps-runs (`HTTPServer`), digits-adjacent (`oauth2Token`), and ambiguous cases = LOW (confirm or
skip; digits never introduce a boundary). Already-spaced / single-word = no-op (idempotency). An
explicit per-identifier override map always wins.

**Collisions — detect and refuse atomically** (never auto-disambiguate): (1) two `Unique`s → same
`NewText` in scope; (2) `NewText` equals an existing backtick name; (3) cross-sort coincidence
(term `cardToUse` and type `CardToUse` both → "card to use") — refuse by default, `--allow-cross-sort`
to override. The collision check is **mandatory for B1**, shared with B4.

**Reversibility — honest answer: lossy, not a function.** `camelify` (backtick→camel) is *not* a
left inverse (acronyms gone, leading case gone, many-to-one). **Ruling: do not ship `camelify` as a
general transform in v1.** If an exact inverse is needed, record the original spelling **out-of-band**
(a sidecar keyed by stable identity) — **NOT** as a `Hidden`-annotated in-band node: inserting an AST
annotation requires reprinting the node, reintroducing the comment-loss hazard and polluting
statutory source with tool metadata. `camelify` must also refuse on any backtick name that is not
pure space-separated alphanumeric words (`` `clause 3(a)` ``, `` `pre-tax income` `` are legal and
un-camelifiable).

### 4.6 Ditto round-trip invariant & idempotency (why it is a theorem, not a loop)

Define `R = lex∘resolve` (the lexer's resolution function) and `L` = the layout function. The
formatter works from the **post-`^`-expansion** AST (lexing expands authorial carets via
`computedPayload`, transitively), where every column holds its real resolved token; it then
*regenerates* carets from scratch via the grid. Two facts make idempotency fall out:

- **Collapse compares against the original cell value, not the rendered caret** (`Columnar.hs:108`
  tests `(normRows!!(i-1))!!j == Just t`, the previous row's *resolved* token — mirroring the
  lexer's transitive resolution). Keep this; comparing against the emitted `^` would break
  transitivity.
- **The collapse decision is a pure function of the resolved grid**, which is a pure function of the
  resolved AST. `format(format(x))` re-derives the *same* resolved AST (emitted carets expand right
  back to the same tokens), feeds the *same* grid to the *same* deterministic renderer, reproduces
  *identical* carets at *identical* code-point columns. Fixpoint.

**Therefore idempotency = round-trip-safety + renderer-determinism + boundary-stability**, all
already required — guarded (not assumed) by the N=2 fixpoint check and the effectiveness corpus.
Two proof-breakers and their closing rules:

- **Intent-reading from layout (prettier trap).** If "is this BRANCH vertical?" is read from
  *whitespace*, formatting changes the whitespace → the next run reads different intent →
  oscillation. **Ruling: every layout/bail decision is a function of the resolved AST, never of
  surface whitespace.** Adopt exactly one intent signal — vertical-vs-inline by arm count (or, more
  conservatively for v1, "already multi-line stays multi-line; never convert") — derived from AST
  shape.
- **Caret oscillation** — closed above: collapse runs once, against resolved values; re-expansion
  happens only in the lexer on the next run and yields the same tokens.

**Per-group verification gate (the A1→A2 degrade):** a group emits carets only if that group, with
carets, reparses to the same resolved tokens *and* its prev-non-blank-line adjacency holds. If not,
the group is emitted reindented-but-spelled-out (A2). So COLUMNAR is default-on **as an aspiration
applied wherever it is provably safe**, and REINDENT is the guaranteed floor — honoring the brief's
"columnar default-on" while obeying the architecture critique's safety pushback.

### 4.7 When to bail on alignment (clang discipline, sharpened)

Alignment is best-effort; misalignment here *re-resolves* `^`, so: **align only when clean;
otherwise emit plain spelled-out arms** (always safe). Bail predicates, all computed from the
resolved AST (never surface whitespace):

- **Single row** → no column, plain.
- **Arity/shape mismatch** → grid mostly `Nothing` (sparsity > 0.5) → plain; also bail a *column*
  with < 2 populated rows.
- **Over-wide column** → would exceed `targetWidth`, or one cell dwarfs neighbors → plain.
- **Non-atomic cell** (§4.4) → still align, never collapse.
- **Interior-trivia row** (§4.2.4) → plain, break group.
- **All-`Nothing` row** → renders as a blank line the lexer skips → **forbid inside a group**
  (it desyncs grid-predecessor from lexer-predecessor).
- **Hard boundaries** → full-line comment, `Inert`, new `§`, blank line → end group, start fresh
  (clang `AcrossEmptyLines=false`, `AcrossComments=false`).
- **Joint solve, not a pipeline** → A1-A6 are one column-solve, not independent pad-to-max passes
  that fight each other and break idempotency; the canonical style must define precedence when two
  alignments demand different positions for the same token.
- **Verification failure** → the ultimate bail: revert that region to **original bytes**.

### 4.8 Tabs

`whitespace` accepts `\t`; megaparsec expands it to width-8 tab stops. A space-only kernel cannot
reproduce a tab-indented file's caret columns. **Ruling: state a tab policy explicitly** — on the
*touched* path, expand tabs to spaces and re-run the verifier; for *untouched* (byte-copied)
groups, either replicate the tab-stop math when modeling caret alignment or exclude tab-containing
groups from caret analysis. Tabs are code points that are not column-units; "code points" in §4.1
means "code points **with tab expansion**."

---

## 5. Phased roadmap

**v1 — the safe layout family (PR #42 follow-up).** Extract `l4-columnar` (`text`-only) with the
**two mandatory fixes**: (a) the single-lexical-token guard `cellAtomic` (§4.4), (b) confirm
code-point metric + tab expansion (§4.1, §4.8) and *do not* port `displayWidth`. Generalize
`Cell → LCell` to carry trivia (§4.2). Build `L4.Lint.Engine` (the `Edit` primitive, the
region-scoped applier, the **trivia+idempotency+effectiveness** verifier of §2.5, the N=2 fixpoint
guard) and `L4.Lint.Layout` (AST→Grid bridge sourced from concrete tokens, prev-non-blank-line
adjacency, joint solve, the A1→A2 verification-gated degrade). Ship `l4 format` (columnar default-on,
`--reindent-only`, three-state `--check`, `--diff`), `Rules.Format` over `GetParsedAst`, LSP
formatting + rangeFormatting, the `{-# l4-format off #-}` pragma. Also land the two cheapest, highest-
value lints that need no formatter and reuse the `AndOrDepth` scaffold: **C1 unresolvable-ditto =
error** and **C3 mixed-AND/OR**. Move `AndOrDepth` into `l4-lint`.

**v2 — the opt-in rename codemod, with rails.** `L4.Lint.Rename` as the **de-ditto → rename →
re-columnar** pipeline of §4.5. Consumes `Module Resolved`; `camelSplit` with confidence tiers and
override map; mandatory collision-refuse; **import-closure-scoped** alpha-eq gate (Unique-bijection
+ substitution, spans ignored, reparsed through `mkPosTokens`); statute-desync guard (scan
`Inert`/annotation trivia for the old surface form; refuse-or-warn in statutory mode). Dry-run
default, `--write` to apply, atomic, LSP code action + `l4 rename` / `l4 lint --fix Rename` at
**suggestion** severity. Provenance stored out-of-band, not `Hidden` in-band. Ship B2
(backtick-removal) as the agreeing inverse of `quoteIfNeeded`.

**v3 — the suggestion lints.** Grow `L4.Lint.*`: C4-C11 (resolver/type/solver-backed), with C
detecting and B5 applying fixes; `.l4lint.yaml` + inline suppression for Class C only. **Defer C2
(deontic/temporal double-bind)** — the marquee capability, but it depends on the reasoner API, not
the lint substrate, so it must not gate launch.

---

## 6. Open questions (assumptions most likely wrong — flagged for the human)

**Q1 (HEADLINE) — RESOLVED: display width.** Settled empirically (§0): the lexer resolves `^` by
display-width columns (`中`/`😀` = 2), not code points. The source read that suggested code points
(no `wcwidth` table) was misleading; the dissenting reviewer who executed the lexer was right. The
proposed golden test was run (ditto-binding + `l4 ast` end-column characterization) and is now
retained as a **regression** pinning the exact width function (East_Asian_Width W/F → 2; combining =
1; no grapheme clustering; tab = tab-stop) to the lexer. Consequence applied: §4.1 flips to display
width, dmnmd's `displayWidth` is the correct basis (plus the emoji blocks it omits), and
`L4.Print.Columnar` is already fixed. **Pin the megaparsec version** as part of the contract — the
mechanism producing display-width columns from stock megaparsec is unexplained, so a version bump
could change it; the regression guards against that.

**Q2. Can intra-group comments / `Inert` prose be deterministically re-attached, and are group
boundaries stable, so the region renderer is both comment-safe and idempotent?** The design leans on
"trivia stays put." A trailing comment on a guard line is ambiguous (binds to the cell, the arm, or
the physical line); if pass 1 and pass 2 resolve it even slightly differently, idempotency breaks —
worse, a comment landing at a different start column could shift a token and **re-resolve a `^`**. The
mitigation (any intra-group comment/`Inert`/`§`/blank line = hard sub-group boundary the renderer
refuses to cross) may prove **too conservative**, shattering "columnar" into many tiny ununified
tables on exactly the prose-interleaved statutory inputs where the feature is most wanted — undercutting
its value. The principled fix if so (anchor each comment to a specific `CsnCluster_` token, not a line)
is a meaningfully larger build than this RFC assumes.

**Q3. Is RENAME's single-module resolution + per-module gate ever safe for exported names?**
`buildReferenceMapping`/`findReferences` run over **one** `Module Resolved`, and `Unique` is
`moduleUri`-qualified precisely because refs to an exported binder live in *other* files. The trap:
the alpha-eq gate also runs per-module, so it **passes** (local refs updated) while downstream
importers silently break. Mitigation: require the whole import closure before renaming any exported
name and **refuse** when the workspace index is incomplete/stale. If closure-completeness can't be
guaranteed, restrict RENAME to single-file scripts and say so loudly — it is safe there and unsafe
exactly where it is most useful.

**Q4. Does default-on COLUMNAR fire its A2 degrade *frequently* on real statutes?** If the gnarliest,
most-aligned fee tables (the highest-value targets, already hand-tuned with carets at specific
columns) routinely fail the per-group caret verification, COLUMNAR becomes a frequent silent reindent
on its best targets — at which point caret-collapse arguably belongs in Class C (suggestion) with a
Class B opt-in fix, dissolving the A1-as-default-on premise. Measure the degrade rate on the pilot
corpora (the payments-fintech fee tables, the SG statute) before committing to caret-collapse-on-save.

**Q5. Is identifier spelling ever an external contract the alpha-eq gate cannot see?** The
payments-fintech use case serves L4 via an SQL-like API; if an L4 identifier's spelling *is* a
column/field name on the wire, B1 rename changes the external contract while the resolved AST is
"equal" — the gate green-lights a breaking change, and editing the bound `Inert` statute prose to
match would be *altering the statute*. B1 in statutory/published-API mode must **refuse or warn-only**,
not merely be opt-in; this gates B1's launch in those uses, not a risk-appendix footnote.

---

### Summary of rulings (the decisive cuts)

1. **Surgical CST span-rewrite, byte-copy the rest**; region renderer sources cells from concrete
   tokens, never `prettyLayout`; fallback is **original bytes**, never exactprint.
2. **One edit primitive** (`SrcRange → Text`); three classes by **proof obligation**; two verifiers.
3. **Display width + tab expansion** for column width (regression-pinned to the lexer); USE `displayWidth` (the shared kernel), extended for wide emoji.
4. Verifier checks **resolved-AST equality + trivia-multiset preservation + idempotency +
   effectiveness** — bare-AST equality alone is a silent-no-op trap.
5. **`cellAtomic` = exactly one lexer token**; multi-token operators (`AT MOST` …) and comparison
   values never collapse to `^`.
6. **Caret eligibility against the lexer's prev-non-blank-line**, not the grid's row `i-1`;
   annotation/`Inert` lines break the chain; `Inert` is a semantic cell, not trivia.
7. **COLUMNAR default-on but per-group verification-gated**, degrading silently to REINDENT (the
   always-safe floor) — honoring the brief while obeying the safety pushback.
8. **RENAME = de-ditto → rename → re-columnar**, a dependent of COLUMNAR; import-closure-scoped
   gate; refuse-on-collision; statute-desync guard; provenance out-of-band; ship no general
   `camelify`.
