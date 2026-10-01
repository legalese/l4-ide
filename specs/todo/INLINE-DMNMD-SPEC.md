# Inline Decision Tables in `.l4` — the DX case

> **Status (2026-07-29): SPECULATIVE. The case is made; the design is NOT worked.**
>
> Nothing here is built, nothing is scheduled, and **no syntax below is final** — every code
> block marked ILLUSTRATIVE is a sketch to make the argument legible, not a grammar. There is no
> parser, no IR path, no diagnostic set, no golden. This document exists to answer one question —
> _is an inline table worth designing?_ — and deliberately stops before answering _how_.
>
> **Update (2026-09-26): three design questions RULED, none implemented.**
> Meng ruled on the "Tables, Trees, Prose" bench where the table code lives (§4.1, card T4), what a cell may contain (§5 item 3, card T5), and what conflicts and no-match mean (§5, "Conflicts and no-match", card T6).
> The rest of the paragraph above stands: there is still no parser, IR path, diagnostic set or golden, and syntax, layout and exactprint (§5 items 1, 2 and 6) are still not worked.
> The same bench ruled how a table is checked and rendered as prose (cards T1–T3); those rulings are recorded in `NLG-TNR-ROUNDTRIP-SPEC.md` §3.6 and §3.7.
>
> What **is** verified in-tree, and cited below: the export direction
> (`jl4-core/src/L4/Dmn/Markdown.hs`, over `L4/Dmn/IR.hs` and `L4/Dmn/Lower.hs`), the GuardedRows
> normal form as it actually ships (`jl4-core/src/L4/Viz/GuardedRows.hs`), columnar `BRANCH`
> (`L4/Parser.hs:2331-2342`), the DMN↔L4 mapping (`BUILD-SPEC-dmnmd-to-l4.md` §1), and the
> dependency prohibition (`CLAUDE.md` §1.2).
>
> **Do not read `GUARDED-ROWS.md` §3 as the tree.** Its `GuardedRows` record has four fields, a
> `Disjointness` ADT and a `DisjointnessWitness`; the shipped one has three fields and a plain
> `Bool`, and `grep -rn DisjointnessWitness --include=*.hs` is empty. An earlier draft of this
> document copied the design doc's record and presented it as code. That is the design doc's
> drift to fix, not this one's to inherit.
>
> Claims about `smucclaw/dmnmd`'s own tree are **not** restated here; see that repo's `CLAUDE.md`
> and `test/corpus/`. That is not politeness — the sibling spec has been wrong about dmnmd's tree
> in both directions inside two days, and its header says so.

---

## 1. The argument in one line

Tabular law arrives as a table, L4 already **emits** that table, and the compiler already
**computes** the normal form a table denotes. The missing edge is the one that lets an author
write the table down as a table — with columns, not just as a flat list of guards, which
`BRANCH` already gives (§2.6).

---

## 2. Five DX claims, and the objection that survives them

**2.1 Tables are how the material actually arrives.** Fee schedules, rate cards, tier
thresholds, penalty bands, eligibility matrices — the source artifact is a grid, in the statute,
in the annex, in the counterparty's PDF. Re-expressing a grid as a right-nested `IF / ELSE IF`
ladder is a **transcription**, not an isomorphism. L4's pitch is isomorphic formalisation: the
formal text should stand in visible correspondence with the source text, so a domain expert can
check it clause by clause. A ladder breaks that correspondence for exactly the material where it
is easiest to keep.

**2.2 A table read _is_ its analysis.** Columns are the inputs; rows are the cases. Read down a
column and you see the domain being partitioned; read across a row and you see one case's whole
guard. Gaps and overlaps show up as **holes and collisions in a grid**, which the eye finds for
free. The same content as a nested ladder hides both: a missing case is an absent `ELSE IF`
somewhere in a chain, and an overlapping case is invisible because first-match silently
swallows it.

**2.3 The loop is already half-built — and open at the wrong end.** `L4.Dmn.Markdown` is the
second emitter over `L4.Dmn.IR`, and its own header states the reason: _"it closes a loop we
already own"_ — `dmnmd --to=l4` exists, so `L4 → md → L4′` is a runnable property, not a claim
(`jl4-core/src/L4/Dmn/Markdown.hs:1-35`, `emitMarkdown` at :58). Today an author who wants a
table therefore round-trips **through an external file**: export, edit the markdown, translate
back, paste in. Every step is a place for the `.l4` file and the table to diverge, and the
authoritative artifact stops being the one under version control. Inline makes the `.l4` file
the single source and turns the round-trip from a workflow into a **test**.

**2.4 The landing pad exists: an inline table is surface syntax, not a language feature.**
`L4.Viz.GuardedRows` is the normal form the toolchain already computes from
`IF`/`BRANCH`/`CONSIDER` (`jl4-core/src/L4/Viz/GuardedRows.hs:47-56`, verbatim):

```haskell
-- | A first-match guarded chain, normalised.
data GuardedRows = MkGuardedRows
  { grRows      :: [(Expr Resolved, Expr Resolved)]
    -- ^ @(guard, body)@ in SOURCE order. The order is load-bearing: first match wins.
  , grOtherwise :: Maybe (Expr Resolved)
  , grDisjoint  :: Bool
    -- ^ Are the guards provably pairwise exclusive? When they are, a row need not
    -- restate that no earlier guard fired. Conservative: 'False' is always sound,
    -- merely verbose.
  }
```

It deliberately carries **rows rather than a boolean tree**, because "the DMN exporter … wants
`grRows` as decision-table rules rather than as a boolean tree" (GuardedRows.hs:18-22). An inline
table elaborates to precisely that record — which means the feature adds a **front end**, not a
semantics. Downstream, nothing changes: evaluation, ladder, DMN export and the exhaustiveness
machinery all see what they see today. (Note there is no scrutinee field: `CONSIDER`'s subject is
consumed into equality guards by `considerRows`, GuardedRows.hs:95-113.)

One consequence really does fall out: the target semantics for each construct is **already
written down**. `BUILD-SPEC-dmnmd-to-l4.md` §1 (lines 96-120) maps table →
`GIVEN…GIVETH…MEANS BRANCH`, input columns → `GIVEN` params, each row → one `IF g THEN r` arm,
`-` → omitted conjunct, multi-value cell → `OR`-of-`EQUALS`, repeated cell → ditto `^`, row
comment → `-- comment`.

A second consequence is often claimed for this design and is **not** free. Today `grDisjoint` is
a conservative `Bool`, computed by `guardsDisjoint` for `BRANCH` and by
`allDistinctJust (map (.biKey) infos)` for `CONSIDER` (GuardedRows.hs:66, :98); nothing records
_why_, and nothing validates a declared hit policy against it — `Markdown.hs` writes the
hit-policy cell straight from the IR, and its loss vocabulary (`Markdown.hs:245-310`) has no
overlap or completeness code. The witness ADT that would make `U`-vs-`F` a checkable claim is
specified in `GUARDED-ROWS.md` §3 and is **not built**. An inline table gives that check a reason
to exist; it does not inherit it. See §5.7.

**2.5 Tables diff.** A changed threshold is one changed cell on one line. The same edit to a
nested ladder is a diff whose shape depends on where in the nesting it landed, and re-ordering
two cases rewrites the indentation of everything below them. Reviewers and domain experts — the
people whose sign-off the isomorphism is _for_ — read a grid diff and cannot read a ladder diff.

**2.6 The strongest objection: `BRANCH` is already columnar, and it ships.** L4 has a flat
first-match form — `BRANCH / IF g THEN r / … / OTHERWISE r₀` (`L4/Parser.hs:2331-2342`; see
`jl4/examples/openfisca/scale.l4:31-36`). One row per case, no nesting, aligned `IF`/`THEN`
columns, a clean one-line diff per changed case. That takes most of the weight out of 2.1, 2.2
and 2.5 as stated: the ladder in §3 is a **`BRANCH` that was not written as one**, and rewriting
it needs no new syntax at all.

What `BRANCH` still does not give is the **grid**: there are no column headers, so there is no
shared input vocabulary to read down; each guard is a free-form conjunction, so a case that does
not constrain an input is silent rather than `-`; and because inputs are not aligned into
columns, a gap or an overlap is not a hole or a collision in a picture — it is still something you
must reconstruct by reading every guard. That residue, not "flatness", is the honest claim for an
inline table. Anyone weighing this feature should first price the much cheaper intervention:
**lint nested `IF/ELSE IF` chains into `BRANCH`.**

**Corollary (the ribbon).** The visual motivation is measured, not asserted: **17 of the 22
widest ladder diagrams in the corpus have exactly one leaf**, the widest 4372px holding 247
characters of raw L4, because a whole decision table renders as one opaque box
(GUARDED-ROWS.md:28-34). GuardedRows fixes that for the reader. Inline syntax fixes it for the
**author** — the thing already renders as a table downstream; let it be one upstream.

---

## 3. The worked example

Rule 201(t) of Reg CF: three tiers of financial-statement requirement by aggregate offering
amount, with a bounded first-time-issuer carve-out inside tier 3.

**As it reads today** — `jl4/examples/legal/regcf/regcf.l4:355-370`, quoted verbatim:

```l4
@ref 17 CFR 227.201(t)(1)-(3)
GIVEN offering IS AN Offering
GIVETH A FinancialStatementRequirement
`financial statements required` offering MEANS
    IF   `aggregate` AT MOST `tier 1 ceiling`
    THEN `financial statements certified by the principal executive officer, with tax return information`
    ELSE IF   `aggregate` AT MOST `tier 2 ceiling`
         THEN `financial statements reviewed by an independent public accountant`
         ELSE IF   `first-time issuer relief applies`
              THEN `financial statements reviewed by an independent public accountant`
              ELSE `financial statements audited by an independent public accountant`
    WHERE
        `aggregate` MEANS `aggregate offering amount` offering
        `first-time issuer relief applies` MEANS
                NOT offering's `the issuer has previously sold securities in reliance on section 4(a)(6)`
            AND `aggregate` AT MOST `first-time issuer review ceiling`
```

Four cases, three of them nested inside the `ELSE` of the one above. The carve-out's **bound**
(`AT MOST 1235000`, the reason the relief runs out) is not merely far from the tier it modifies —
it is in a different block, and its interaction with the tier-2 ceiling above it has to be
reconstructed by the reader.

Per §2.6, **the nesting is the author's choice, not the language's**: this is a `BRANCH` written
as a ladder, and flattening it to four sibling `IF … THEN` arms is a pure rewrite that costs
nothing and is available today. Read the sketch below as an argument about the remaining gap —
column headers, `-`, and an aligned domain — not about nesting.

**Sketched as an inline table** — _ILLUSTRATIVE SYNTAX ONLY; the fence word, the header cells,
~~the cell language~~ and the binding form are all placeholders.
The cell language is no longer a placeholder: it was ruled on 2026-09-26 (§5 item 3), and the input cells below conform to it._

```l4
@ref 17 CFR 227.201(t)(1)-(3)
GIVEN offering IS AN Offering
GIVETH A FinancialStatementRequirement
`financial statements required` offering MEANS TABLE
    | F | aggregate : Number  | previously sold : Boolean | requirement (out) : String |
    | - | ------------------- | ------------------------- | -------------------------- |
    | 1 | <= 124000           | -                         | certified                  |
    | 2 | <= 618000           | -                         | reviewed                   |
    | 3 | <= 1235000          | false                     | reviewed                   |
    | 4 | -                   | -                         | audited                    |
    WHERE
        aggregate       MEANS `aggregate offering amount` offering
        previously sold MEANS offering's `the issuer has previously sold securities in reliance on section 4(a)(6)`
```

Read the `aggregate` column top to bottom and the partition is a list of ascending bounds with a
catch-all. The carve-out is **one row**, sitting between the tier it relaxes and the tier it
falls back to, with its bound in the same cell as the tiers it must be compared against. The
`-` in row 4 is the exhaustiveness argument, visible.

That block is not a new semantics: it elaborates to the `GuardedRows` of §2.4, whose four
`(guard, body)` pairs are the four rows in source order and whose `grOtherwise` is row 4.
Whether the declared `F` should have been `U` is then a question a compiler **could** be made to
answer (rows 1-3 are not pairwise disjoint on `aggregate` alone, so `F` is right) — but nothing in
the tree answers it today, and nothing would start to merely because the table is inline. See
§2.4 and §5.7.

---

## 4. Constraints that are already fixed

**4.1 `legalese/l4-ide` must never depend on `smucclaw/dmnmd`.** `CLAUDE.md` §1.2, in effect
verbatim: dmnmd may be used as local evidence when it happens to be checked out — see
`etc/validate-dmn.mjs`, which skips silently when it is absent — but **it must never become a
build dependency**. Concretely, for this feature: an inline-table reader is an **in-tree parser
for the format**, producing `L4.Dmn.IR` / `GuardedRows` directly. Never a shell-out to `dmnmd`,
never a library import, never a submodule, never a dev-dependency that CI happens to have. The
same posture the export side already takes: _"dmnmd's current behaviour is not a design input"_
(`DMN-EXPORT-PROGRAM-MODEL-SPEC.md`:2451-2456) — emit (and now read) within the grammar of the
day, record every gap, depend on nothing.

**Where the table code lives — RULED 2026-09-26 (T4).**
Ruled by Meng on 2026-09-26, bench "Tables, Trees, Prose", card T4, marked accept: option C of three, with four conditions.
Ruled, not implemented; none of the code it places exists.
The table→tree compiler (`NLG-TNR-ROUNDTRIP-SPEC.md` §3.7) and the region checker (`≡_R`, its §3.6) live in l4-ide.
The region enumerator and `#ASSERT` generation live in dmnmd.
Both halves implement one written spec.
Option A (both in l4-ide) and option B (both in dmnmd) were not taken.
The four conditions, as printed on the card:

1. The CI gate for the l4-ide compiler and checker is a per-region `cases.json` battery, run through the existing KIE + Camunda job (`.github/workflows/pr-checks.yml:1468`, "DMN Engine Checks (KIE + Camunda)").
   The dmnmd leg is local evidence only.
2. Fixing dmnmd's no-match crash, so that F and P answer null rather than crash (dmnmd's `symptom/eval-hp-first-no-match-crash`), comes before `emitAsserts`.
3. The written spec names one canonical copy.
   The precedent it avoids is `BUILD-SPEC-dmnmd-to-l4.md`, which exists in both repos, differs between them, and names no canonical copy.
4. The `dmn-core` package option stays deferred, on the trigger dmnmd's `DMN-CORE-HACKAGE-FINDINGS.md` already sets: reopen it when `DMN-EXPORT-PROGRAM-MODEL-SPEC.md`'s status header stops saying "not yet implemented".
   It still says so (`DMN-EXPORT-PROGRAM-MODEL-SPEC.md:3`).

This ruling adds to §4.1 and does not relax the paragraph above.
Nothing in it makes dmnmd a dependency of l4-ide, and a differential against dmnmd can never gate CI here, because this repo may use dmnmd only as local evidence that skips silently (`etc/validate-dmn.mjs:25`, "THE dmnmd LEGS (local evidence, not CI)").
That is why condition 1 puts the gate on the two foreign engines.

**What review changed.**
An independent skeptic argued that C's edge over A is a dmnmd differential that can never gate, while A's cross-check, KIE and Camunda, already gates CI; and that dmnmd's interpreter crashes on F and P tables with no match, which is exactly where a checker should look.
The objection was taken: C stays, but now says plainly what gates and what is only evidence, and carries the four conditions.
A's cost as printed: no second implementation at all, not even as local evidence.
B's: l4-ide's renderer cannot use it without breaking `CLAUDE.md` §1.2, short of a published package.

**4.2 The exporter already owns a serialiser, so a parser gets a fixture corpus free.** Every
table `emitMarkdown` produces is, by construction, an input the reader must accept, which makes
`parse . emit ≡ id` a property testable over the whole existing corpus with no fixtures written
by hand. The grammar's three hard-won limits are documented at `Markdown.hs:21-35` and constrain
the reader identically: a column header is a bare varname (letter, then
alphanumerics/spaces/tabs/underscores — no `.`, no expressions); **every table line must end in a
newline** or the failure is reported eight lines away at the header row; and `(out )` does not
parse while `(out)` does. The emitter's loss vocabulary — `D-MD-NONIDENTCOLUMN`,
`D-MD-CELLSYNTAX`, `D-MD-NODEFAULT`, `D-MD-TYPE`, `D-MD-NOLITERAL` (`Markdown.hs:245-310`) — is
the ready-made diagnostic set for the **reject** direction.

**4.3 The round-trip modulus is inherited, not renegotiated.** §8 of the export spec rules that
record-threaded L4 flattens to prefixed scalar columns (`i.annual_income` → `i annual income :
Number`, one `D-MD-FLATRECORD` note per table), and states the contract as **L4 → md → L4′ equal
modulo record flattening** (`DMN-EXPORT-PROGRAM-MODEL-SPEC.md`:2417-2435). The inline direction
inherits exactly that modulus — which is also why the §3 sketch has `WHERE` bindings doing the
projection rather than dotted column headers.

---

## 5. Deliberately not worked here

Named so nobody mistakes their absence for triviality. Each is a design task in its own right:

1. **Grammar and lexer integration** — how a table block is opened and closed, whether it is a
   fenced region or lexed cell-by-cell, and how it interacts with `MEANS`, `WHERE` and `DECIDE`.
2. **Layout interaction** — L4 is layout-sensitive; pipe tables are line-oriented and
   whitespace-padded. How the two disciplines coexist is unresolved and is probably the hardest
   part.
3. **Cell expression language** — FEEL, L4 expressions, or a deliberately impoverished third
   thing. The export side has a `L4Verbatim` escape hatch; ~~whether the read side should is open~~
   the read side has none in its cells.
   **ANSWERED 2026-09-26 (T5): S-FEEL unary tests with constant endpoints; see "The cell language" below.**
4. **Hit policies beyond First / Unique** — `Priority`, `Any`, and especially `Collect`, which
   `BUILD-SPEC-dmnmd-to-l4.md` §1.6 has deferred throughout and which is not a `BRANCH` at all.
   Still open.
   T6 ("Conflicts and no-match", below) rules what a conflict means under Unique and Any, not which hit policies an inline table accepts.
5. **Error reporting** — column/cell-accurate spans, and _not_ inheriting the misreported
   missing-newline failure described in §4.2.
6. **Exactprint and round-trip fidelity** — alignment padding, ditto `^`, comment placement, and
   the repo's exactprint law that tokens live in the child whose position they occupy.
7. **The disjointness witness and the hit-policy check** — replacing `grDisjoint :: Bool` with a
   witness (`GUARDED-ROWS.md` §3) and adding the consumer that validates a declared `U`/`F`
   against it. Independently useful, unbuilt, and **not** a free consequence of inline syntax; it
   is listed here because §2.4 used to smuggle it in as one.
   Still open.
   T4 (§4.1) places the region checker in l4-ide, and T6 (below) rules what happens when it finds a conflict; how a witness replaces `grDisjoint :: Bool` is not ruled.

None of the seven is a reason not to design this. ~~All seven are~~ The six still open, all but
item 3, are reasons this document is not the design.

### The cell language — RULED 2026-09-26 (T5)

Ruled by Meng on 2026-09-26, bench "Tables, Trees, Prose", card T5, marked accept: option A of four.
It answers item 3 above, whose "is open" clause is struck, and it retires the §3 sketch's "cell language" placeholder.
Ruled, not implemented: there is still no reader for any cell language.

- **Cells are S-FEEL unary tests with constant endpoints** (literals, dates, constructors).
  That is the fragment the export side already emits: "A /constant/ FEEL value: the only thing this exporter will ever put on the endpoint of a 'UnaryTest'" (`jl4-core/src/L4/Dmn/IR.hs:208-209`), whose cells "never leave the analysable fragment" (`:239`).
- **A computed condition is its own column, bound in `WHERE`**, the way the §3 sketch binds its inputs.
  The checker treats that column as opaque and reports the loss for that column only, the scope `D-UNDECOMPOSABLE` already uses (`jl4-core/src/L4/Dmn/Lower.hs:3417`), rather than downgrading the whole table.
- **Named endpoints are refused**, for example `<= tier 1 ceiling`, with a message that says to write a computed column.

**Not taken.**
Option B, the alternative the card named, accepts named endpoints and downgrades that column to battery checking; a reader then cannot tell at a glance whether a cell is a value or a reference, which is the exporter's own reason (`IR.hs:211-216`).
Option C, an L4 escape hatch in cells, costs the whole table its exact check for one computed cell.
Option D, L4 expressions in cells, breaks §4.2's `parse . emit ≡ id` and the dmnmd round trip.

**What review changed.**
The card's first draft recommended C.
An independent skeptic showed that l4-ide had already decided this for export, since cells hold constant endpoints and anything else becomes a column whose input expression carries it, and the recommendation moved to A in full.

**One consequence to know before the first real table.**
Reg CF's thresholds are not constants: they depend on the rule date (`jl4/examples/canon/us/regcf/regcf.l4:191`, `:201`, `:211`).
So a faithful inline Reg CF table writes each threshold test as a computed column, as the DMN export already does (`jl4/examples/dmn/expected/regcf-corpus.dmn:1825`, `aggregate_offering_amount <= tier_1_ceiling`).
The constant cells in the §3 sketch are the 2022 figures only.

### Conflicts and no-match — RULED 2026-09-26 (T6)

Ruled by Meng on 2026-09-26, bench "Tables, Trees, Prose", card T6, marked accept: option A of three.
Ruled, not implemented, in either repo.
It is the ruling that dmnmd's `DECISIONS.md` D-13 deferred: whether a trailing catch-all under U is "an authoring error, or an accepted idiom".
dmnmd's full record of it belongs in that repo's `DECISIONS.md`; this note records the ruling for the inline design and keeps the card's list of what moves.
It amends no earlier text in this document; items 4 and 7 above point here.

- **A trailing catch-all under U is an accepted idiom.**
  It is read as the DMN 1.3 §8.2.11 default output value, in dmnmd's interpreter too.
- **Any other conflict region on scalar columns is refused.**
  A conflict region is one where two rules are live under U, or where the live rules' outputs differ under A.
  DMN 1.3 §8.2.10 says a U table "SHALL NOT contain overlapping rules", and that when A's outputs are non-equal "the result is undefined".
  Collection-input U and A tables keep dmnmd's overlap warning until regions model membership.
- **"No rule matched" is rendered, not papered over.**
  It is `NOTHING` in L4, with a `MAYBE` result only where a no-match region exists, so total tables stay bare.
  It is `null` in DMN, as DMN 1.3 §10.3.2.10 already says ("or null if no default output value is specified"), and "no rule applies" in prose.
  dmnmd's interpreter answers null on no-match, not an error or a crash.

Applied to an inline table, which is not built: a `U` table's trailing all-`-` row would become the §2.4 `grOtherwise`, a conflict region on a scalar column would be a located error rather than a first-match `BRANCH`, and a table with a no-match region would elaborate to a `MAYBE` result.

**What moves, as printed on the card.**
These are dmnmd corpus recordings under `languages/haskell/test/corpus/cases/`, each checked to exist on dmnmd `origin/trunk` at `db5311d`.
Per this document's header, it does not restate dmnmd's behaviour; this is the ruling's list, and re-recording them is dmnmd's work.

- `policy/l4-otherwise-sentinel-not-last-row`, `policy/list-output-l4-literal`, `policy/list-input-membership-l4` and `policy/md-eval-unique-conflict` move.
  `md-eval-unique-conflict` is re-fixtured with a genuine overlap (`<= 20` / `>= 10`), so the refusal stays pinned.
- The one table in `symptom/l4-hitpolicy-unique-silently-first` starts refusing.
- Added after step 0, a throwaway measurement of 2026-09-26: five more `policy/` tables have a conflict region beyond any trailing catch-all, and would start refusing.
  Four are U: `hp-unique-near-duplicate-rows-accepted` (rows 3 and 4 overlap on Winter), `md-prefix-comparisons` (`< 18` / `<= 21`), `md-multivalue-dash-reprocessed` (`4, -` / `8`) and `md-negation-in-numeric-column-emitted` (`not([1..5])` / `[10..20]`).
  One is A: `eval-hp-any-two-rows-disagree`.
  `symptom/hp-any-duplicate-rows-disagree-silent` starts refusing too, which is progress.
- Those four U cases pin something else: D-13's guard against false refusals, prefix comparisons, a multi-value dash, and negation.
  Each is re-fixtured with non-overlapping rows, keeping the property it was written for, and the overlap is pinned by the new refusal cases instead.
  The A case becomes a refusal case.
  This addition had no fresh skeptic.

**What review changed.**
An independent skeptic showed that the catch-all reading reverses the card's own exhibit: `md-eval-unique-conflict`'s only overlap is its trailing catch-all, so under that reading it answers `Spareribs` instead of refusing.
The skeptic also showed that the draft decided D-13's deferred question without naming it, and that refusing "any conflict region" would refuse the collection-input U tables dmnmd deliberately only warns about.
The objection was taken: the ruling names D-13, limits refusal to scalar columns, and lists the recordings step 0 found the draft had missed.

**Not taken.**
Option B, today's first-match resolution and type sentinel, gives silent wrong answers at exit 0 in both renderers, and four readings of one table.
Option C, conflicts rendered as "undefined" leaves, publishes a provision with a hole in it.
For a Boolean output, DMN `null` is observationally the `FALSE` sentinel, because it "reads as `false` in every consuming boolean position" (`jl4-core/src/L4/Dmn/Analysis.hs:14-16`).

**A consequence for this repo, not ruled.**
`L4.Dmn.Markdown` downgrades a U table that has a default to F with a final all-`-` row, because emitting `U` with a catch-all "would be a table dmnmd reads back as saying something else" (`jl4-core/src/L4/Dmn/Markdown.hs:164-171`).
Once dmnmd implements T6, that premise stops holding; whether to emit U then is a separate question.
