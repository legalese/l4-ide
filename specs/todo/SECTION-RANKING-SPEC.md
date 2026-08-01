# Section Ranking for Constructors and Selectors

_Status: **design, not yet implemented.** Written 2026-07-27 on branch `docs/section-ranking-spec`,
measured against `origin/unstable` @ `15d99856` and rebased onto `3b9bfc6e`. Revised the same day
after a three-lens adversarial review; §12 records what each finding changed. All line numbers hold
at both commits: `git diff 15d99856..3b9bfc6e` touches none of `TypeCheck.hs`, `TypeCheck/Types.hs`,
`Import/Resolution.hs`, `jl4/tests/Main.hs` or `ResolutionCascadeSpec.hs`._

**One-line summary.** `SECTION-LEXICAL-SCOPING-SPEC.md` (specs/done) says unqualified names resolve
to the nearest enclosing section. Data constructors and stored record selectors are the only
name-bearing declarations in the language that do not obey it, and that exemption was never
designed — it is where the implementation happened to stop. This spec proposes finishing it, and
adds the one diagnostic and the one resolution fix that make finishing it non-silent.

The deferral is explicit in the code. PR [legalese/l4-ide#152](https://github.com/legalese/l4-ide/pull/152)
(commit `1607cba1`, fixing [smucclaw/l4-ide#921](https://github.com/smucclaw/l4-ide/issues/921))
gave constructors and selectors a section-qualified _spelling_ via `addQualifiedAliases`
(`jl4-core/src/L4/TypeCheck.hs:2668`) rather than `withQualified` (`:2605`), precisely so that it
would not also change how their _unqualified_ references rank. Its haddock (`:2650-2667`) names this
document's job.

Everything below marked "measured" was executed against the prebuilt `dist-newstyle/…/l4` binary,
read-only; nothing was built and nothing in the tree was modified. Measurements added during the
revision pass are marked "measured (rev)". §10 lists what is still open.

---

## 1. The question, stated exactly

`selectByProximity` (`jl4-core/src/L4/TypeCheck/Types.hs:803`) reads a candidate's defining section
path out of `CheckState.sectionPaths` (`Types.hs:64`) with

```haskell
Map.findWithDefault [] u paths
```

so **absence from the map and "declared at top level" are the same thing** — and `[]` is a prefix of
every path, so a pathless binding is an ancestor of every section in its module, at distance equal to
the reference site's nesting depth.

Only four call sites ever write to that map, all through `withQualified` → `recordSectionPath`
(`Types.hs:755`). Constructors (`TypeCheck.hs:984`) and stored selectors (`:1056`) are not among
them. So today:

> A data constructor or stored record selector declared inside `§ Alpha` is, for the purposes of
> unqualified name resolution, a top-level binding of the module: maximally far from everywhere, and
> never out of scope anywhere.

The question this spec answers is whether that should change, and if so, what the migration costs.

---

## 2. The current semantics, contract-grade

### 2.1 The mechanism, in five functions

| Function            | Anchor              | Role                                                                                                                                             |
| ------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `pushSection`       | `Types.hs:1305`     | **Appends** to `CheckEnv.sectionStack` (`Types.hs:424`), so the stack is outermost-first.                                                        |
| `withSectionStack`  | `TypeCheck.hs:3604` | Pushes the section's name together with its `AKA` aliases as one `NonEmpty Text`. An anonymous `§` pushes nothing and is transparent to ranking. |
| `recordSectionPath` | `Types.hs:755`      | Snapshots the stack against each `Unique`. Explicitly a no-op at top level.                                                                      |
| `sectionProximity`  | `Types.hs:772`      | `candidate isPrefixOf current` → `length current - length candidate`; else `Nothing`. "Ancestor" is literally list prefix.                       |
| `selectByProximity` | `Types.hs:803`      | Keeps the minimum-distance ancestors, re-appends imports, and **falls back to the entire viable set when no candidate is an ancestor**.          |

Ranking is applied **within each type group**, not globally: `selectByProximityPerType`
(`Types.hs:894`) partitions by `TypeKey` (`Types.hs:843`) — for `resolveType`, by `Kind`
(`TypeCheck.hs:1131-1140`) — runs `selectByProximity` inside each group, then unions and dedups by
`Unique`. That is what lets the prelude's NUMBER/STRING/BOOLEAN/MAYBE comparison overloads live in
sibling subsections without shadowing each other.

Two callers: `resolveTerm'` (`Types.hs:939`) and `resolveType` (`TypeCheck.hs:1098`). Both run
locals-first (`Types.hs:955-961`, `TypeCheck.hs:1106-1110`) before proximity, and both end in the
same four-way case: `[]` → `OutOfScopeError`; `[x]` → done; `xs` → `choose xs` (type-direction) and
only then `AmbiguousTermError` / `AmbiguousTypeError`.

Neither caller inspects the reference's `RawName`. **A `QualifiedName` reference is ranked by
proximity exactly like a `NormalName` one.** That is §2.4d, and it is load-bearing for §5.

### 2.2 Who records a section path

| Entity                                      | Writer                                                                                                                                               | Path?                                                         | Ranks?                                                                                                                   |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `DECIDE` / `MEANS` value, incl. `GIVETH`    | `withQualified` @ `TypeCheck.hs:3651`                                                                                                                | yes                                                           | yes                                                                                                                      |
| term `ASSUME`                               | `withQualified` @ `:3684`                                                                                                                            | yes                                                           | yes                                                                                                                      |
| `DECLARE`'d type name, incl. type synonyms  | `withQualified` @ `:2790`                                                                                                                            | yes                                                           | yes                                                                                                                      |
| type `ASSUME` name                          | `withQualified` @ `:2820`                                                                                                                            | yes                                                           | yes                                                                                                                      |
| **computed** field (`HAS f IS A T MEANS …`) | desugared to a `DECIDE` → `withQualified` @ `:3651`, `TermKind` overridden to `ComputedSelector` @ `:3643`                                           | **yes**                                                       | **yes**                                                                                                                  |
| **data constructor**                        | `addQualifiedAliases` @ `:984`                                                                                                                       | **no**                                                        | **no**                                                                                                                   |
| **stored** record selector                  | `addQualifiedAliases` @ `:1056`                                                                                                                      | **no**                                                        | **no**                                                                                                                   |
| infer-phase requalification of a `DECLARE`  | `addQualifiedAliases` @ `:2724`                                                                                                                      | no (deliberate no-op; `:2790` already recorded it)            | —                                                                                                                        |
| `WHERE`/`LET` local `DECIDE`                | `withQualified` @ `:3651` via `scanFunSigLocalDecl` `:3630`                                                                                          | yes, but **inert** — `localBindings` short-circuits proximity | n/a                                                                                                                      |
| `GIVEN` param, pattern var, type var        | plain `makeKnown`, `Local` / `KnownTypeVariable`                                                                                                     | no                                                            | n/a — locals win absolutely                                                                                              |
| imported binding                            | **none** — `combineOne` keeps `accState.sectionPaths` and drops `r.sectionPaths` (`Import/Resolution.hs:383`, and `:359` folds only the accumulator) | **no**                                                        | no — and moot: `isImport` (`Types.hs:816`) exempts them from ranking _and_ from elimination before any path is consulted |

The imports row was stated backwards in the first draft ("yes"). It is worth getting right because
it means importers see a genuinely flat namespace: this is the same residual
`SECTION-LEXICAL-SCOPING-SPEC.md` §12 records, and it is why I3 holds for a reason stronger than
`isImport` alone.

### 2.3 What a user can rely on today

These are the guarantees the current implementation actually offers. They are stated here because
§5 must preserve or knowingly repeal each one.

- **G1 — Nearest section wins, for values and types.** Same-typed, same-named bindings shadow along
  the ancestry chain. (`SECTION-LEXICAL-SCOPING-SPEC.md` §3.1.)
- **G2 — Distinct types never shadow.** Grouping by `TypeKey` means an overload is never eliminated
  by proximity. (`Types.hs:878-892`.)
- **G3 — A lone candidate always resolves.** If no candidate is on the ancestry chain,
  `selectByProximity` returns the whole viable set (`Types.hs:810`). Cross-section references without
  a rival therefore never become out-of-scope.
- **G4 — Locals beat everything.** (FIX A; `Types.hs:955-961`.)
- **G5 — Imports stay co-equal.** An import/local same-typed collision is a genuine ambiguity, not a
  silent shadow. (FIX C; spec §5.5.)
- **G6 — ~~Qualified spellings bypass ranking entirely.~~ FALSE. Measured (rev).** See §2.4d. This
  was asserted in the first draft and is wrong. Qualified references are ranked like any other. S9
  makes G6 true; until then it is not a guarantee, it is a bug.
- **G7 — Constructors and stored selectors are visible from everywhere in their module.** The
  consequence of pathlessness, and the only thing the current exemption actually buys.

### 2.4 Four places where the current rule is not a rule anyone wrote

**(a) A computed field ranks; a stored field does not. Measured.** Both are declared by the same
`DECLARE … HAS` construct and reached by the same `x's f` syntax. But a computed field is desugared
to a `DECIDE` before typechecking (`TypeCheck.hs:1050-1052` note) and therefore travels
`scanFunSigDecide` → `withQualified`, while a stored field travels `inferSelector` →
`addQualifiedAliases`. The two collide with an enclosing value in opposite directions:

```l4
-- cf1: STORED field.  Result: 1 — the selector wins (pathless ⇒ ancestor of § Gamma).  exit 0
§ Alpha
DECLARE Wrapper HAS w IS A NUMBER
§ Beta
GIVEN r IS A Wrapper
GIVETH A NUMBER
w MEANS 99
§ Gamma
GIVETH A NUMBER
pick MEANS w OF (Wrapper WITH w IS 1)
```

```l4
-- cf2: COMPUTED field, same collision.  AmbiguousTermError.  exit 1
§ Alpha
DECLARE Wrapper HAS
    v IS A NUMBER
    w IS A NUMBER
      MEANS v * 1
§ Beta
GIVEN r IS A Wrapper
GIVETH A NUMBER
w MEANS 99
§ Gamma
GIVETH A NUMBER
pick MEANS w OF (Wrapper WITH v IS 1)
```

> ```
> There are multiple definitions for the identifier   w
>   w (defined at cf2-computed-sel.l4:10:1-2) of type FUNCTION FROM Wrapper TO NUMBER
>   w (defined at cf2-computed-sel.l4:4:5-6)  of type FUNCTION FROM Wrapper TO NUMBER
> ```

And in the other direction, against a top-level rival with the reference _inside_ `§ Alpha`: the
stored field is an `AmbiguousTermError` (both at distance 1), while the computed field **wins
silently at distance 0** — exactly the behaviour this spec is asked to consider granting stored
fields:

| probe                                                     | shape                                   | measured                                           |
| --------------------------------------------------------- | --------------------------------------- | -------------------------------------------------- |
| `cf3` stored field vs top-level value, ref in `§ Alpha`   | stored `w` @`§ Alpha` + top-level `w`   | **error**, exit 1                                  |
| `cf4` computed field vs top-level value, ref in `§ Alpha` | computed `w` @`§ Alpha` + top-level `w` | **`1`**, exit 0, no diagnostic                     |
| `cf5` computed field, no rival, ref from `§ Gamma`        | computed `w` @`§ Alpha`                 | **`6`**, exit 0 — G3 holds for computed fields too |

The seam also covers the answer-changing row directly. Measured (rev), on a character-identical
pair differing only in whether `payout` is stored or computed:

```l4
§ Act
GIVEN c IS A Claim
GIVETH A NUMBER
payout MEANS 500

§§ Schedule
DECLARE Claim HAS payout IS A NUMBER      -- stored:   `amount due` (Claim WITH payout IS 123) = 500
                                          -- computed: the same program answers 123
GIVEN c IS A Claim
GIVETH A NUMBER
`amount due` c MEANS payout OF c
```

The stored version answers **500** today; replacing the field with a computed one of the same name
answers **123** today, exit 0, no diagnostic in either case. This is row 3a of §3 — the single row
whose _answer_ changes under this spec — and half of the construct already ships the post-change
answer.

**This reframes the entire decision.** "Should selectors rank by section proximity, accepting the
silent-rebinding hazard?" is not a question about a change that has never been made. Half of one
construct already ranks, shipped, with the silent direction live and untested. The real question is
whether the two halves of a `DECLARE … HAS` should agree, and which way.

**(b) A `DECLARE`'s type name ranks; its constructors and selectors do not.** One declaration, two
halves, opposite scoping rules. Verified for types by probe (`§ Alpha`'s `Tag` beats a top-level
`Tag` at distance 0; two sibling `Tag`s from a third section are an `AmbiguousTypeError`) and by
code: `scanTyDeclDeclare` (`TypeCheck.hs:2784`) calls `withQualified` at `:2790`.

**(c) "A selector's name is already scoped by its record type" is false in the implementation.**
`inferRecordProjection` calls `resolveTerm` — the whole term namespace, unfiltered
(`TypeCheck.hs:1810`) — and only afterwards unifies via `matchFunTy`. The filtered
`_resolveSelector` (`Types.hs:1032`) is dead code, hence the leading underscore. So a selector
competes head-on with any value of type `FUNCTION FROM R TO t`; the record type helps only insofar
as it makes `TypeKey`s differ. Constructors _are_ namespace-scoped, but only in **pattern** position
(`resolveConstructor = resolveTerm' (== Constructor)`, `Types.hs:1035`) — a bare `yes` in expression
position goes through the unfiltered `resolveTerm`.

The consequence of (c) is the sharpest cost of the status quo:

```l4
§ Outer
GIVEN r IS A R
GIVETH A NUMBER
w MEANS 99
§§ Alpha
DECLARE R HAS w IS A NUMBER
useDot MEANS (R WITH w IS 7)'s w      -- evaluates to 99.  exit 0, no diagnostic.
```

Field-access syntax that does not access the field, three tokens after a record-construction label
`w` that _does_ — because construction labels resolve structurally through
`findOptionallyNamedType` (`TypeCheck.hs:2068`), not through the environment. The two `w`s mean
different things. (Grounding-pass probe; the mechanism is confirmed by code at `TypeCheck.hs:1810` +
`:2068`, and the same inversion is re-measured in the stored/computed pair above.)

**(d) Qualified spellings are ranked by proximity too, so the same qualified token means different
things in different places. Measured (rev). This one is not about constructors at all.**

`qualifiedAliases` (`TypeCheck.hs:2624`) builds each alias with `defAka`, which **shares the
original's `Unique`** (`:2642`, comment: "Use defAka to share the same Unique"). `sectionPaths` is
keyed by `Unique`. `resolveTerm'` never looks at whether `rawName n` is a `QualifiedName`. Therefore
a qualified lookup is ranked by the _reference site's_ section stack, against the _original's_ path.

Two values, no constructors, no selectors:

```l4
§ Alpha AKA shared
GIVETH A NUMBER
p MEANS 1

GIVETH A NUMBER
fromAlpha MEANS `shared`.p     -- Result: 1.  exit 0.  No diagnostic.

§ Beta AKA shared
GIVETH A NUMBER
p MEANS 2

§ Gamma
GIVETH A NUMBER
fromGamma MEANS `shared`.p     -- AmbiguousTermError, exit 1.
```

The identical token `` `shared`.p `` is a silent `1` inside `§ Alpha` and a fatal ambiguity inside
`§ Gamma`. (AKA fan-out is what makes two sections share one qualified key here — `sequence neSects`
picks one alias per level — but the ranking is what picks a winner without saying so.)

The same happens across kinds, which is why it lands in this spec's blast radius. Measured (rev):

| probe      | shape                                                                  | `` `Alpha`.x `` from inside `§ Alpha` | from `§ Beta`                       |
| ---------- | ---------------------------------------------------------------------- | ------------------------------------- | ----------------------------------- |
| `probe-q1` | constructor `yes` and same-typed value `yes`, both in `§ Alpha`        | the **value** (`no`), exit 0, silent  | the **constructor** (`yes`), exit 0 |
| `probe-q2` | stored selector `w` on `R` and same-typed value `w`, both in `§ Alpha` | the **value** (`99`), exit 0, silent  | the **selector** (`7`), exit 0      |

Two further facts about qualified spellings, both measured (rev), both needed by §5:

- **Aliases are full-path only.** For `§ Outer` / `§§ Alpha`, the alias key is
  `` `Outer`.`Alpha`.x ``; `` `Alpha`.x `` is an out-of-scope error (`sequence neSects` produces one
  full-length path per alias combination, never a suffix). Any diagnostic that suggests a spelling
  must spell the whole path.
- **A top-level binding has no qualified spelling at all.** `qualifiedAliases` returns `[]` when the
  section stack is empty, so there is no way to name a top-level binding explicitly.

---

## 3. The disagreement set

Write `dS` for the nesting depth of the reference site, `dC` for the depth of the section declaring
`C` (a constructor or stored selector), and `dV` for the proximity of a rival binding `V` **in the
same `TypeKey` group** — that precondition is necessary, because `selectByProximityPerType`
partitions before it ranks.

Today `C` is always an ancestor at distance `dS`. Under ranking `C` is an ancestor at `dS - dC` when
its declaring path prefixes the reference's stack ("on-chain"), and off-ancestry otherwise. `V` is
either an ancestor at some `dV ≤ dS`, or off-ancestry, or an import.

The first draft's table had five rows and was **wrong in two ways**: it omitted three cases, and its
row-3 "today" column asserted `V wins` for a sub-case that is measurably an error (`cf3`). The
complete enumeration is below; the two right-hand columns are the W-SHADOW-CROSSKIND firing set
(§5 S5), which the first draft also got wrong.

| #   | `C` on-chain? | `V`                                          | today                | ranked                           | change               | warns today | warns after |
| --- | ------------- | -------------------------------------------- | -------------------- | -------------------------------- | -------------------- | ----------- | ----------- |
| 1   | no            | off-ancestry                                 | `C` wins (V dropped) | no ancestor → G3 → **ambiguous** | **error introduced** | **yes**     | no          |
| 2   | no            | ancestor, `dV = dS` (top level, ref outside) | tie → **ambiguous**  | `C` dropped → `V` wins           | **error removed**    | no          | **yes**     |
| 2′  | no            | ancestor, `dV < dS`                          | `V` wins             | `V` wins                         | none                 | **yes**     | **yes**     |
| 3′  | yes           | off-ancestry                                 | `C` wins             | `C` wins                         | none                 | **yes**     | **yes**     |
| 3a  | yes           | ancestor, `dS − dC < dV < dS`                | `V` wins             | **`C` wins**                     | **answer changed**   | **yes**     | **yes**     |
| 3b  | yes           | ancestor, `dS − dC < dV = dS` (top level)    | tie → **ambiguous**  | **`C` wins**                     | **error removed**    | no          | **yes**     |
| 4   | yes           | ancestor, `dS − dC = dV` (same section)      | `V` wins             | tie → **ambiguous**              | **error introduced** | **yes**     | no          |
| 5   | yes           | ancestor, `dS − dC > dV`                     | `V` wins             | `V` wins                         | none                 | **yes**     | **yes**     |
| 6   | —             | none in group                                | `C` wins             | G3 fallback → `C` wins           | none                 | no          | no          |
| 7   | —             | import (different `moduleUri`)               | co-equal → ambiguous | identical (G5)                   | none                 | no          | no          |

Mapping from the first draft, for anyone reading the review trail: old row 1 = new 1, old 2 = new 2,
old 3 = new **3a** _and_ **3b** (the draft merged them and printed 3a's "today" for both), old 4 =
new 4, old 5 = new 5, old 6 = new 6, old 7 = new 7. New rows **2′** and **3′** were missing
entirely; both are "no change" rows, but both fire the warning, which is why their absence broke the
phase plan (§7.3).

Each row is anchored to a measurement where one exists:

- Row 1 — `cf1` (`1`, exit 0) and `jl4/examples/ok/cross-section-qualified-additive.l4`'s `useCon` /
  `useSel`.
- Row 3a — the stored/computed pair of §2.4a (`500` today, `123` under ranking, `123` today for the
  computed twin).
- Row 3b — `cf3` (**error**, exit 1) with `cf4` showing the post-change answer already shipping for
  computed fields.
- Row 6 — `cf5` (`6`, exit 0).

Rows 1 and 4 are loud: an `AmbiguousTermError` naming both definition ranges, exit 1 (measured —
`l4 check` returns 1 on ambiguity and on out-of-scope, 0 on success; the exit codes are reliable,
contrary to a note in the grounding pass).

Rows 3a and 5 are today silent: exit 0, no diagnostic of any severity, `--json` reports
`{"ok":true,…}` without naming the chosen binding, `l4 ast` is pre-resolution, and no `#EVALTRACE`
mentions it. The only in-band signal is IDE go-to-definition. **Row 3a is the case that changes an
answer.** Any option permitting it must answer for it; §5 does.

Row 6 is the load-bearing one for adoption: it is why "constructors stop being visible across
sections" — the intuitive fear — is not what ranking does. Of 6545 unqualified cross-section
constructor/selector references measured across 93 corpus files (grounding corpus pass), 6543 fall
under row 6 and do not move.

**Not in the table, because it is not a proximity question:** the qualified-spelling collisions of
§2.4d. They are ranked by the same machinery and S1 moves them (a constructor that gains a path
turns a today-resolving qualified reference into a tie or a G3 fallback), but the fix is S9, not a
row.

---

## 4. Options

### (A) Status quo — qualified spelling only, no path

**Rejected.** It is not a coherent status quo to preserve:

- it is internally inconsistent along three seams that nobody designed (§2.4a, §2.4b, §2.4d), and
  the computed-field seam already ships the very silence (row 3a) that A is supposed to be avoiding
  — the same program, one keyword different, answers 500 or 123 with no diagnostic either way;
- its own silent failure — `(R WITH w IS 7)'s w` → `99` — inverts the reading rule the language
  advertises for everything else, and has no analogue anywhere in L4;
- it preserves §2.4d: a qualified reference that is silently one binding here and a hard error there.
  A is the only option under which that stays silent;
- it is not documented anywhere a user reads. `SECTION-LEXICAL-SCOPING-SPEC.md` §3.1 says
  "when resolving an unqualified name `x`" with no carve-out. A user who reads the spec is wrong
  about the language.

The single thing A buys is G7, and G7 survives every other option intact via the G3 fallback
(row 6).

### (B) Full participation — constructors and stored selectors rank exactly like values

Record the path at `TypeCheck.hs:984` and `:1056` (`withQualified`, or equivalently
`addQualifiedAliases` + `recordSectionPath`). Nothing else changes: `selectByProximity`,
`selectByProximityPerType`, `TypeKey` grouping, the locals gate and the import exemption are all
namespace-blind already.

Gets: one rule for the whole language; the two `DECLARE` halves agree; `x's w` stops meaning an
unrelated function; rows 2 and 3b's spurious ties become answers.
Costs: rows 1 and 4 introduce errors; row 3a changes an answer **silently**; and S1 propagates into
qualified resolution via §2.4d, which B alone does not address.

### (C) Rank, but a constructor/selector-vs-value collision is an error

Rows 1 and 4 already error under B. C's content is therefore precisely: **make every remaining row
with a cross-kind same-`TypeKey` rival an error too** — rows 2, 2′, 3′, 3a, 3b _and_ 5. That is a
larger set than the first draft credited (it said "rows 2 and 3"), because rows 2′, 3′ and 5 have a
discarded cross-kind rival without any change of meaning: C would turn six working shapes into
errors, three of which behave identically before and after S1.

**Rejected as stated, adopted in substance.** As an error it is too blunt:

- Rows 3a/3b are ordinary lexical shadowing. L4 already commits to it silently for values, types,
  term and type `ASSUME`s and computed fields; making it an error _only_ when one side is a
  constructor invents a fourth rule and re-creates the very asymmetry B exists to remove.
- It would be un-suppressible except by renaming, in a language whose corpora are transcriptions of
  legal texts where the names are not the author's to choose.
- It cannot be honoured in pattern position at all, where `resolveConstructor` filters values out
  before ranking ever runs (`Types.hs:1035`).

But C's _demand_ is right, and it is the one thing B lacks: **no silent rebinding**. §5 adopts it as
a diagnostic rather than a rejection.

### (D1) Record-scoped projection

Resolve `e's f` against the fields of `e`'s type first, falling back to the term namespace only on
miss. This removes stored selectors from the proximity question entirely and fixes §2.4c more
directly than B does.

**Attractive, orthogonal, out of scope.** It requires `e`'s type before `f` is resolved, which is a
bidirectional change to `inferRecordProjection` (`TypeCheck.hs:1806-1834`), and it says nothing about
constructors. It should be its own spec. See R4.

### (D2) Separate namespaces for constructors and selectors

Give them their own `Environment` so they never collide with values. Kills both directions — and, in
particular, it is the only option that dissolves row 4 rather than converting it to an error, which
matters because row 4 is the one shape with no spelling-based escape hatch (see the Decision below).

**Rejected for now, and the review made it closer than the first draft did.** `Environment` is a
flat `Map RawName [Unique]` and `resolveTerm'` filters by `TermKind` _after_ lookup by design; the
projection path deliberately uses the unfiltered `resolveTerm`. This is a large change with its own
acceptance fallout, and it would also silently repeal the ability to write a helper named like a
field — which the corpora do use. Against that, its unique advantage bites in exactly zero corpus
files (§7.1: the only row-4-shaped site in the tree is the pin, and it is cross-section, hence row 1
not row 4). Buying a large refactor to dissolve a shape that no corpus file has, and that B⁺ reports
loudly when it appears, is not a trade worth making now. Revisit if row 4 shows up in practice.

### (D3) Ancestor everywhere, with credit for its own subtree

Give constructors/selectors a path, but compute their distance as
`min(real distance if ancestor, dS)` — i.e. they keep G7 unconditionally _and_ gain proximity credit
inside their own subtree.

This is the minimum-breakage option, and worth stating precisely because it is not obvious that it
loses. Against §3: rows 1, 2, 2′, 3′ and 5 unchanged, **rows 3a and 3b improved**. Only row 4
breaks — and it breaks the same way B does, into an ambiguity with no escape spelling. D3 therefore
does **not** avoid B's sharpest cost; it only avoids B's row-1 and row-2 transitions.

**Rejected.** It buys nothing the corpus needs — the measured breakage of B is one file (§7), and
that file is the pin — and it costs a rule with no analogue anywhere in the language ("this binding
is simultaneously in `§ Alpha` and at top level"), unexplainable in
`SECTION-LEXICAL-SCOPING-SPEC.md` §3.1's four-level priority list. It also leaves §2.4a unfixed:
computed fields would keep pure value ranking, or would have to be _widened_ to D3, which is a
regression on shipped behaviour. Preferring a bespoke rule over a uniform one to avoid zero
breakages is a bad trade, especially when it does not avoid the breakage that has no workaround.

### Decision: **B + W-SHADOW-CROSSKIND + qualified-bypass** ("B⁺")

**Re-affirmed after review, on the review's own evidence.** Three lenses attacked the ruling; none
concluded a different option wins, and the strongest new finding — §2.4d — turned out to afflict A,
B, C, D1 and D3 alike, while being _worst_ under A, the only option that leaves it silent. The
review did change the spec's content: B⁺ now has a third component (S9), the disagreement table is
rebuilt, and one cost is newly admitted (row 4, below).

Rank uniformly (B), add one warning that fires exactly where a cross-kind candidate is discarded by
proximity (S5), and stop ranking qualified references at all (S9), so that the warning's advice is
executable. Under B⁺ **every row of §3 whose meaning differs from today is either an error or a
warning; none is silent** — rows 1 and 4 are `AmbiguousTermError` at exit 1, and rows 2, 3a and 3b
warn. The warning is a proper superset of the disagreement set: rows 2′, 3′ and 5 also warn, and
that is the right superset, because row 5 _is_ `x's w → 99`, which a user should be told about
whether or not this spec lands.

**The admitted cost.** In row 4 — a constructor or selector and a same-typed value in the _same_
section — B⁺ produces an ambiguity with **no escape hatch**: both candidates' qualified spellings
are the identical string, so no spelling reaches either binding and renaming is the only fix. That
is the exact cost this spec charges against option C, and B⁺ pays it in one row. Three things make
it acceptable rather than disqualifying:

1. it is one row out of ten, and the one row where the two names genuinely cannot be told apart by
   any means the language offers today either (§2.4d probe-q1: the same qualified token already
   means different things at different sites, silently);
2. D3, the only option that keeps rows 1 and 2 unchanged, pays the identical cost in the identical
   row, so this is not a reason to prefer D3;
3. it is measurably absent from the corpus (§7.1), and it arrives as a loud error naming both
   definitions, not as a wrong answer.

---

## 5. The chosen semantics, normatively

- **S1.** `inferConDecl` (`TypeCheck.hs:984`) and `inferSelector` (`:1056`) record a section path for
  every name they bind, over the same `Resolved`s and under the same section stack that produced
  their qualified aliases.
- **S2.** No other change to the proximity machinery. `sectionProximity`, `selectByProximity`,
  `selectByProximityPerType`, `TypeKey`, `groupByKey`, the locals gate and `isImport` are untouched.
  **G1–G5 hold verbatim. G6 is false today (§2.4d) and is _made_ true by S9. G7 is repealed and
  replaced by S3.** (The first draft said "G1–G6 hold verbatim", which was unsatisfiable.)
- **S3.** A constructor or selector with no same-`TypeKey` rival on the reference's ancestry chain
  still resolves from anywhere in its module, by the G3 fallback (`Types.hs:810`). Cross-section
  visibility is lost **only** in the presence of a competing same-typed binding, and then it is lost
  to an error (rows 1, 4) or to a warned-about shadow (rows 2, 2′), **never to silence.** (The first
  draft said "to an error, never to silence", which is false for rows 2 and 2′, where `V` simply
  wins and the loss is reported by S5.)
- **S4.** `isValueBinding` (`Types.hs:1020`) is **not** changed. FIX B is about wildcard (`InfVar`)
  forward references to un-annotated `DECIDE`s; constructors and selectors are registered in the
  infer phase with concrete types and can never be wildcards, so including them would be dead code
  at best and would re-open the `WHERE`-binding-named-like-a-field regression at worst — the concern
  is recorded in the FIX B comment at `Types.hs:967-975`, **not** in
  `section-scoping-forward-ref.l4`, which exercises a plain inner-section forward reference with no
  `WHERE` and no field (see §9 test 14: nothing in the tree covers the shape the comment names).
  Corroborated independently: the phase driver (`TypeCheck.hs:267`) runs all `DECLARE` inference
  before any expression inference, so S1 introduces no forward-reference ordering hazard of its own.
- **S5 — W-SHADOW-CROSSKIND.** A new `CheckWarning` (`Types.hs:145`, emitted via `addWarning`
  `Types.hs:561`, severity `SWarn`). Fires at an unqualified reference when `selectByProximity`
  discarded at least one candidate that (i) is in the same `TypeKey` group as the kept candidate and
  (ii) differs from it in **kind class**, where the two classes are `{Computable, Local, Assumed}`
  and `{Constructor, Selector, ComputedSelector}` — i.e. `isValueBinding` (`Types.hs:1020`), reused
  as the class function.

  **"Discarded" means either kind of drop `selectByProximity` performs** — a farther ancestor, or an
  off-ancestry candidate eliminated because some ancestor existed. Both are required: the off-ancestry
  drop is what makes rows 2 and 2′ warn, and without it row 2 would be silent, contradicting the
  Decision. Consequently the firing set is the two right-hand columns of §3, not a subset of the
  changed rows; §7.3 plans around that rather than against it. The G3 fallback discards nothing, so
  rows 1-after and 4-after do not warn — they error instead.

  Message shape (final wording is R1), for the §2.4c program (`§ Outer` containing `§§ Alpha`):

  > `w` here is the record field declared at `§ Outer` › `§§ Alpha` (file:6:21-22).
  > The same-typed value `w` at `§ Outer` (file:3:1-2) is shadowed and was not considered.
  > Write `` `Outer`.`Alpha`.w `` or `` `Outer`.w `` to be explicit.

  The spellings must be **full paths from the module root** and the message must omit the suggestion
  for any candidate declared at top level, because such a candidate has no qualified spelling at all
  (§2.4d). The first draft's example suggested `` `Alpha`.w ``, which is an out-of-scope error for a
  nested section — measured (rev).

  Rationale for restricting to cross-kind: within a kind class, shadowing is the idiom — a section
  redefining a term is the whole point of `SECTION-LEXICAL-SCOPING-SPEC.md`, and warning on it would
  fire on the prelude. Across classes, a value named like a constructor of a type is nearly always
  accidental, because the two play different syntactic roles.

- **S6.** W-SHADOW-CROSSKIND is `SWarn`, not `SError`. `jl4/tests/Main.hs:82-84` records that only
  `SError` blocks `SuccessfulTypeCheck`, so this does not break a corpus that merely triggers it.
- **S7.** The warning **must land in the same change as, or before, S1** — never after. Its entire
  justification is that no meaning-change reaches a user unannounced.
- **S8.** Ambiguity reporting is unchanged in mechanism (`Types.hs:987-1000`,
  `TypeCheck.hs:1114-1127`) but the message is not: today it prints definition ranges and types and
  **never mentions sections** (`TypeCheck.hs:4026-4042`). Since rows 1 and 4 make section membership
  the operative fact, `AmbiguousTermError` / `AmbiguousTypeError` should name each candidate's
  section path and suggest the qualified spellings — subject to the same two caveats as S5 (full
  paths; no suggestion for a top-level candidate, and in row 4 no suggestion at all, because both
  spellings coincide). See R2.
- **S9 — qualified references are not ranked.** In `resolveTerm'` (`Types.hs:939`) and `resolveType`
  (`TypeCheck.hs:1098`), when the reference's `rawName` is a `QualifiedName`, skip
  `selectByProximityPerType` and pass the viable set straight to the existing four-way case
  (`[]` → out of scope, `[x]` → done, `xs` → `choose` then ambiguity). The `Unique`-dedup that
  `selectByProximityPerType` performs (`Types.hs:902`, `:909-915`) must be kept; only the ranking is
  dropped.

  This is not a widening of scope for its own sake. It is:

  - **a bug fix that stands alone.** §2.4d's probe uses two ordinary values and no constructors:
    `` `shared`.p `` is a silent `1` in one section and a fatal error in another, today.
  - **a prerequisite for S5 and S8.** Their entire remedy is "write the qualified spelling". Without
    S9 that advice is unsound: the qualified spelling is itself proximity-ranked, so following it
    can land on the binding the user was trying to avoid.
  - **exactly what the alias keys already mean.** A `QualifiedName` key encodes the full section
    path, so the candidate set under that key is already the set of bindings declared at that path.
    Ranking it by the _reference's_ stack is comparing two unrelated coordinates.
  - **near-zero blast radius.** Measured (rev): four `.l4` files in the tree use a qualified spelling
    at all (`quoted-sections.l4`, `cross-section-ref.l4`, `cross-section-qualified.l4`,
    `cross-section-qualified-additive.l4`), and none has two bindings under one qualified key. S9
    changes no corpus answer.

  S9 does **not** rescue row 4, where both candidates share one qualified key by construction. That
  is admitted in §4's Decision rather than papered over.

---

## 6. Invariants that must survive

- **I1 — Pattern position is no less total than it is today.** A constructor must not become
  ambiguous or unresolvable in a pattern _as a result of S1_.

  The first draft proved something stronger and false: it claimed two same-named constructors of one
  type are impossible because "a type is declared once". Both halves are wrong. Measured (rev):
  `DECLARE V IS ONE OF yes, yes` is **accepted at declaration** and produces an `AmbiguousTermError`
  at the reference (`yes … of type V` twice, exit 1); in pattern position the same duplication yields
  the ambiguity plus a `PatternMatchesMissing` warning. And a type name can be declared more than
  once — `ResolutionCascadeSpec.hs:79-91` deliberately declares `Verdict` in two sections.

  The repaired proof: `resolveConstructor` filters to `Constructor` before ranking
  (`Types.hs:1035`), so no value can compete; two same-named constructors of _different_ types land
  in different `TypeKey` groups, because a constructor's codomain is its own type, and
  `selectByProximity` on a singleton either keeps it as an ancestor or returns it via the G3
  fallback, never emptying it. The residual case — two same-named constructors of the _same_ type —
  is a pre-existing pathology that is already an error today and is **unmoved by S1**, because both
  duplicates are registered under the same section stack and therefore move together, tying before
  and after.

  This invariant is load-bearing, not decorative. A nullary pattern is checked as
  `inferPatternApp` falling back, via `orElse`, to `inferPatternVar` (`TypeCheck.hs:2118-2119`), and
  `orElse` (`Types.hs:1191`) takes the fallback whenever the first branch produced _any_ error — so
  a nullary pattern head that fails to resolve as a constructor **silently becomes a catch-all
  binder**, with a `CONSIDER`-redundancy warning as the only tell. If I1 ever fails, that amplifier
  becomes reachable.

- **I2 — Record construction labels are unaffected.** `R WITH w IS 7` resolves structurally in
  `findOptionallyNamedType` (`TypeCheck.hs:2068`), not through the environment. This is why the
  §2.4c program has two `w`s meaning different things, and it stays true under B⁺: the label still
  names the field while the projection now also does.

- **I3 — Cross-module behaviour is unchanged.** `isImport` (`Types.hs:816`) exempts foreign
  `Unique`s from ranking and from elimination in both directions, so no importer of a library can be
  affected by S1, whatever that library's internal section structure. Reinforced by §2.2: imported
  bindings carry no section path at all, `combineOne` having dropped it
  (`Import/Resolution.hs:383`).

- **I4 — Locals still win.** FIX A (`Types.hs:955-961`) runs before proximity; a `GIVEN` parameter
  named like a nearby constructor still resolves to the parameter.

- **I5 — Overloads still coexist.** Constructors of _different_ types sharing a name, and selectors
  of _different_ records sharing a name, remain in different `TypeKey` groups and are unaffected in
  both directions. A constructor and a selector can never collide in one `TypeKey` group at all: a
  constructor's type is its own datatype, a selector's is a function from its record.

- **I6 — Types are untouched by S1.** `resolveType` ignores `KnownTerm` entirely
  (`TypeCheck.hs:1140`), so giving a constructor a path cannot perturb a type reference of the same
  name. Only S9 touches `resolveType`, and only by declining to rank qualified type references.

---

## 7. Migration

### 7.1 Measured impact: one file, and it is the pin

Three scans agree on the collision set: the grounding corpus pass, a line-based re-derivation, and a
third scan during the review pass.

|                                                                                                   | count    |
| ------------------------------------------------------------------------------------------------- | -------- |
| `.l4` files in the repo (excl. `dist-newstyle`, `node_modules`)                                   | 636      |
| files declaring a constructor or selector inside a **named** section                              | 131 (±2) |
| — of those, inside a CI-globbed directory                                                         | 35 (±1)  |
| files with a name collision between a section-declared constructor/selector and a same-file value | **1**    |

The denominator is 639 at the rebase base `3b9bfc6e`:
`jl4/tests-cli/fixtures/export-{nothing,advisory-only,two-rules}.l4` were added after the
measurement, and none of them contains a `§`, so the population, the CI split and the collision
count are all unchanged.

The population figures carry a ±2 scanner band: two of the three scans give 131/35/96, the third
gives 129/34/95. The band is `DECLARE`-block-boundary noise and does not move the collision count,
which all three put at 1.

Two scoping caveats, stated so the "1" is not read as stronger than it is:

- **The value side is definition-head position only** — a name starting a line, optionally after
  `DECIDE`/`ASSUME`. Indented `WHERE`/`LET` locals are excluded. Include them and six more files
  match the literal wording, two of them in CI; all six are inert, because the locals gate
  (`Types.hs:955-961`, G4/I4) short-circuits proximity before a local can ever compete with a
  constructor. The exclusion is deliberate and is now stated rather than assumed.
- **Same-`TypeKey` is not checked by the scanner**, so the "1" is an upper bound on real collisions
  and the near-misses below are the manual filter.

The one file is `jl4/examples/ok/cross-section-qualified-additive.l4`, whose header says in so many
words that its purpose is to pin the current behaviour against exactly this change. Its two
collisions (`yes` and `w`) are same-typed on purpose, and both are **cross-section** (constructor and
selector in `§ Alpha`, values in `§ Beta`, references in `§ Gamma`) — i.e. row 1, not row 4. Under
B⁺ it produces two ambiguity errors, which is the intended outcome. Note also that its two qualified
references (`` `Alpha`.yes ``, `` `Alpha`.w ``) name a different key from `` `Beta`.yes `` and so are
untouched by S9 and by §2.4d — the pin cannot detect the qualified hazard.

The re-derivation initially reported 7 files; six were scanner artifacts, each explained: multi-word
backticked constructor names in `regcf.l4` (`` `financial statements audited by …` ``) split on
whitespace into spurious tokens `audited`/`certified`/`reviewed`, and `IS A Maybe Person` field-type
continuations in `british-citizen-act.l4` and the `macma*`/`britishcitizen` experiments read as
constructor lines. Inspected by hand; none is a real collision.

Three inert near-misses are worth recording so nobody re-litigates them:
`jl4-core/libraries/actus-core.l4` has `PF` as a constructor of two different types in sibling
subsections (different `TypeKey`s, I5); 23 selector-name cases across the Charities Jersey and ACTUS
corpora are structurally inert because a selector's domain is its own record; and
`Singapore-Data-Protection-Act.l4`'s `` `Nearest Relative` `` is a type-vs-selector case in one
section (inert by I6).

**Phase-1 warning volume, measured (rev).** Because W-SHADOW-CROSSKIND fires on today's compiler in
six of the ten rows, its volume had to be measured separately from S1's impact, over
constructors/selectors at _any_ depth including top level (a top-level constructor is unmoved by S1
but still discards a nearer value). Three files in the tree have a cross-kind name collision at all:

| file                                                  | names      | same `TypeKey`?                                                                                            | fires?  |
| ----------------------------------------------------- | ---------- | ---------------------------------------------------------------------------------------------------------- | ------- |
| `jl4/examples/ok/cross-section-qualified-additive.l4` | `yes`, `w` | **yes**, deliberately                                                                                      | **yes** |
| `jl4/examples/ok/contracts.l4`                        | `foo`, `x` | no — constructor `foo : Action` vs value `foo : NUMBER`; selector `x : baz → foo` vs value `x : DEONTIC …` | no      |
| `jl4/experiments/jerseyCharities.l4`                  | `name`     | no — selectors `… → STRING` vs `ASSUME name : Entity → Name`, and `ASSUME Name IS A TYPE` (`:27`)          | no      |

So phase 1 re-cuts exactly one golden, and it is the pin's. That is a smaller number than the
per-row firing table would suggest, and it is the number that matters for scheduling.

### 7.2 What that licenses, and what it does not

It licenses making the change **now**. Nothing in the corpus depends on either behaviour, so this is
the cheapest this decision will ever be — and every program written after it lands will depend on
whichever answer is in the compiler.

It does **not** license calling the corpus a safety net. Read carefully, the measurement cuts both
ways: a green suite here is not evidence that the change is safe, it is evidence that the suite
cannot detect it. Three facts sharpen this:

1. `jl4/tests/Main.hs:73-86` globs `ok/**`, `legal/**`, `jl4-core/libraries/*.l4`, `not-ok/tc/**`,
   `not-ok/nlg/**`, `not-ok/export-*`, `lsp/semantic-tokens/**` and `lsp/hover/**`.
   **`jl4/experiments/`, `paper/case-studies/` and `doc/` are not tested at all** — 96 of the 131
   population files are outside CI.
2. The existing section-scoping fixtures (`section-lexical-scoping.l4`,
   `section-scoping-forward-ref.l4`, `section-scoping-param-not-shadowed.l4`,
   `ambiguous-sections.l4`, `nested-sections.l4`, `not-ok/tc/section-scoping-ambiguous.l4`,
   `not-ok/tc/section-scoping-import-collision.l4`) **cover value bindings only. None declares a
   constructor or selector inside a section.** The ranking rules have essentially no
   constructor/selector coverage apart from the additive pin.
3. Nothing in the tree covers §2.4d at all. Of the four files that use a qualified spelling, none
   puts two bindings under one qualified key, so the site-dependence of `` `Alpha`.x `` is invisible
   to CI. That is why it survived to be found by review rather than by a test.

### 7.3 Sequence

The first draft's phase plan assumed W-SHADOW-CROSSKIND "fires only in row 5" on today's compiler.
That is false — §3's firing column shows six rows firing pre-flip, including the pin's `useCon` and
`useSel` — so phase 1 does re-cut a golden, and the plan below says so rather than being surprised
by it. The measured volume (§7.1) is one file.

| Phase | Content                                                                                                                                                                                                                                                                                                   | Depends on |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| **0** | §9 tests written against **today's** behaviour, so the diff is visible in goldens rather than argued. The `not-ok/tc` cases go in as `ok` cases first. **Also: the _before_ leg of the phase-4 diagnostic sweep** — capture `l4 check` output for all 96 untested files now, while "before" still exists. | —          |
| **1** | S9 — stop ranking qualified references. Independently correct (§2.4d is a live silent-inversion bug in plain values), independently shippable, measured to change no corpus answer, and a prerequisite for S5's advice being sound.                                                                       | 0          |
| **2** | W-SHADOW-CROSSKIND (S5–S6). Fires today in rows 1, 2′, 3′, 3a, 4 and 5 — i.e. it pre-announces every site S1 will later flip or error, which is the point. Re-cuts one golden: `cross-section-qualified-additive.l4` gains two warnings on `useCon`/`useSel` while keeping its answers.                   | 0          |
| **3** | S1 — record the path. Flip `TypeCheck.hs:984` and `:1056`. Move the phase-0 fixtures to their post-change expectations; rewrite `cross-section-qualified-additive.l4` (see 7.4).                                                                                                                          | 1, 2       |
| **4** | S8 — sections in ambiguity messages.                                                                                                                                                                                                                                                                      | 3          |
| **5** | The _after_ leg of the sweep over the 96 untested files: re-run `l4 check`, diff against the phase-0 capture. Not a CI addition; a migration receipt.                                                                                                                                                     | 3          |

Phases 1 and 2 are each independently shippable and independently useful. S7 is satisfied: the
warning (phase 2) strictly precedes the meaning change (phase 3).

### 7.4 `cross-section-qualified-additive.l4` is rewritten, not deleted

It is the only file in the tree that exercises the interaction at all. It keeps its two same-typed
collisions and its structure; its header comment is rewritten to cite this spec, and its expectations
change twice: at phase 2 `useCon` and `useSel` gain W-SHADOW-CROSSKIND while still answering `yes`
and `5`; at phase 3 they become the row-1 ambiguity errors and the file moves to `not-ok/tc/`. Its
qualified-access half (`qBetaValue`, `qAlphaCon`, `qAlphaSel`) is what #921 added and must be
preserved verbatim in a sibling `ok/` file — the additive claim about _spelling_ remains true and
still needs a pin. That sibling should additionally gain the same-section qualified collision the
pin cannot express (§9 test 17), because the pin's cross-section shape is blind to §2.4d.

---

## 8. Consistency with `SECTION-LEXICAL-SCOPING-SPEC.md`

That spec is **honoured, not revised.** Its §3.1 states the priority order for "an unqualified name
`x`" with no carve-out for any namespace; its §5.1 (siblings do not shadow), §5.2 (top level is
lowest priority), §5.3 (proximity before type-direction), §5.4 (AKA), §5.5 (imports) and §5.6
(forward references are orthogonal) all apply verbatim to constructors and selectors under B⁺. The
exemption this spec removes appears nowhere in it. That is the strongest single argument for B: the
carve-out is an implementation artifact, and the specification of record it contradicts is already
marked DONE.

S9 is the one place B⁺ goes beyond that spec rather than completing it: §3.1 speaks only of
unqualified names, and is silent on whether a _qualified_ name is ranked. The implementation ranks
it; S9 says it should not. That is a gap-fill, not a contradiction, but it belongs in the DONE
spec's §3 when this lands.

Two of its open items are touched:

- **§8 Q1 — "should section scoping apply to types as well as terms?"** Answered yes, and shipped
  (`scanTyDeclDeclare` → `withQualified`, `TypeCheck.hs:2790`). B⁺ extends the same yes to the other
  half of a `DECLARE`.
- **§8 Q5 — "should the compiler emit a hint when a name is resolved via section proximity,
  shadowing an outer definition?"** Answered by S5, narrowed to the cross-kind case where the hint
  is worth its noise.

One is made more urgent rather than answered:

- **§9 — audit-grade desugaring.** That section asks for unqualified references to be rewritten to
  qualified form with a logged reason, so an auditor can see which binding was chosen and why. It is
  unimplemented. B⁺ moves meaning in row 3a and therefore raises the cost of not having it; S5 is a
  narrow, cheap substitute for the cross-kind case only. §2.4d is a second argument for it: an
  audit-grade rewrite would have made the site-dependence of `` `shared`.p `` visible on the page.
  See R3.

On the language-design question the task poses — constructors and selectors are not values, so
should they rank differently? — the answer from the code is that the premise does not hold as stated
(§2.4c): in expression and projection position they already live in the same flat namespace as
values and are already resolved by the same function. They are _not_ separately scoped, so there is
no separate scope to justify a separate rule. The place where they genuinely are namespace-scoped —
pattern position — is exactly the place where ranking provably cannot bite (I1). The distinction
the language actually draws is therefore orthogonal to proximity, and does not argue for an
exemption.

---

## 9. Tests

All new fixtures under `jl4/examples/ok/` and `jl4/examples/not-ok/tc/`, both inside the CI globs
(`jl4/tests/Main.hs:75-86`). Each is listed with the row it covers.

**Direction (a) — errors introduced (rows 1, 4).** `not-ok/tc/`:

1. `section-rank-ctor-sibling-collision.l4` — constructor in `§ Alpha`, same-typed value in
   `§ Beta`, referenced from `§ Gamma`. Row 1. Golden must show both ranges and (after phase 4) both
   sections.
2. `section-rank-ctor-samesection-collision.l4` — constructor and same-typed value both in
   `§ Outer`, referenced from `§ Outer`. Row 4. Golden must **not** suggest a qualified spelling,
   because both candidates spell the same (§4 Decision, admitted cost); asserting the absence of the
   suggestion is the point of the fixture.
3. `section-rank-sel-sibling-collision.l4` — the selector twin of 1, in projection position.
4. `section-rank-sel-samesection-collision.l4` — the selector twin of 2. Row 4. (Missing from the
   first draft, which had no selector twin for row 4.)

**Direction (b) — meaning changed (rows 2, 3a, 3b), each with its warning golden.** `ok/`:

5. `section-rank-ctor-beats-toplevel.l4` — constructor in `§ Alpha`, same-typed value at top level,
   referenced from inside `§ Alpha`. **Row 3b** (the first draft labelled this "Row 2" and then
   expected row 2's opposite winner): today an `AmbiguousTermError`, after B⁺ resolves to the
   constructor **plus W-SHADOW-CROSSKIND**. This is `cf3`/`cf4`'s shape; the golden should note that
   the computed-field twin already answers this way today.
6. `section-rank-value-beats-ctor-toplevel.l4` — **row 2**, the genuine one: constructor in
   `§ Alpha`, same-typed value at top level, referenced from `§ Beta`. Today ambiguous; after B⁺ the
   value wins, with the warning. Distinguishing 5 from 6 is the whole content of the row-2/row-3b
   split.
7. `section-rank-nested-answer-change.l4` — value in `§ Outer`, constructor in `§§ Alpha`, reference
   inside `§§ Alpha`. **Row 3a**, the answer-changing case. Must `#EVAL` to the constructor and warn.
   The file should also contain the two qualified spellings (`` `Outer`.yes ``,
   `` `Outer`.`Alpha`.yes ``) and `#EVAL` both, so the golden records all three readings side by
   side. Note the spellings are full-path: `` `Alpha`.yes `` is an error (§2.4d).
8. `section-rank-sel-projection.l4` — `(R WITH w IS 7)'s w` must evaluate to `7`, not `99`, with the
   enclosing-section function `w` shadowed and warned about. This is the §2.4c fix, and the single
   most legible reason for the change.

**Regressions against over-eager elimination (rows 2′, 3′, 5, 6; G3).** `ok/`:

9. `section-rank-ctor-crossection-lone.l4` — constructor in `§ Alpha` referenced unqualified from
   `§ Gamma` with **no** rival. Row 6. Must still resolve. Guards the 6543-of-6545 case.
10. `section-rank-far-value-still-wins.l4` — row 5: the value is nearer than the constructor;
    nothing changes, but the warning fires. Pins that the warning is not gated on a behaviour
    change.
11. `section-rank-no-change-warns.l4` — rows 2′ and 3′ in one file: two shapes whose answer is
    identical before and after, both of which warn in both states. Pins the firing table's
    "no change / warns both" cells, which the first draft's plan denied existed.

**Inertness controls (I5, I6).** `ok/`:

12. `section-rank-ctor-vs-ctor.l4` — `yes` as a constructor of `V` in `§ Alpha` and of `W` in
    `§ Beta`, both used from `§ Gamma`. Both resolve, type-directed, before and after.
13. `section-rank-sel-vs-sel.l4` — field `w` on `R` in `§ Alpha` and on `S` in `§ Beta`. Both
    resolve.
14. `section-rank-type-vs-ctor.l4` — I6: a type and a constructor sharing a name across sections.
    `resolveType` ignores `KnownTerm`, so nothing moves.

**The asymmetry regression (§2.4a).** `ok/`:

15. `section-rank-stored-vs-computed.l4` — one record with a stored field and a computed field, each
    colliding identically with the same enclosing value. **The two must produce identical
    diagnostics and identical answers.** This is the test that would have caught the current split,
    and the one that keeps it from reappearing. The §2.4a `payout` pair is the ready-made body.

**Invariants.** `ok/` unless noted:

16. `section-rank-pattern-total.l4` — I1: constructor in `§ Alpha`, same-typed value in `§ Beta`,
    `CONSIDER` from `§ Gamma`. Every branch must still match its constructor; no
    `PatternMatchesMissing`, no `CONSIDER`-redundancy warning, no catch-all-binder degradation.
17. `not-ok/tc/section-rank-dup-ctor-pattern.l4` — I1's residual: `DECLARE V IS ONE OF yes, no, yes`
    must produce the same ambiguity plus `PatternMatchesMissing` before and after S1. Pins that the
    duplicate pathology is unmoved, since the first draft's proof wrongly claimed it was impossible.
18. `section-rank-locals-win.l4` — I4: a `GIVEN` parameter named like a constructor in the enclosing
    section. Add a `WHERE` binding named like a field it projects — the shape the FIX B comment
    (`Types.hs:967-975`) names and **no existing fixture covers**; `section-scoping-forward-ref.l4`
    is a plain inner-section forward reference with no `WHERE` and no record, so S4's regression risk
    is currently untested.
19. `section-rank-forward-ref.l4` — S4: the `section-scoping-forward-ref.l4` shape, unchanged, with a
    constructor added in the same section to prove `isValueBinding` still excludes it from FIX B.
20. `not-ok/tc/section-rank-import-collision.l4` — I3/G5: an imported same-named, same-typed binding
    stays ambiguous against a local constructor.
21. `section-rank-reopened-section.l4` — a constructor declared in `§ Alpha` and referenced from a
    later reopened `§ Alpha` must be at proximity 0. Paths are compared by name vector, so reopening
    rejoins. (The first draft cited `ResolutionCascadeSpec.hs:82-88` as already relying on this "for
    values"; it does not — `sameNameDistinctTypes` at `:79-91` reopens `§ Alpha` and relies on it for
    a **type** name, and is a deliberate type-mismatch fixture. Under B⁺ its `no` becomes
    off-ancestry and still resolves by G3, so the mismatch it asserts is unchanged; that is worth an
    explicit check, not a citation.)
22. `section-rank-construction-label.l4` — I2: `R WITH w IS 7` in the presence of a same-typed value
    `w`. The label must resolve structurally regardless of what the environment says, before and
    after.

**Qualified resolution (S9, §2.4d).** New, absent from the first draft entirely:

23. `not-ok/tc/section-rank-qualified-same-section.l4` — constructor and same-typed value both in
    `§ Alpha`, referenced as `` `Alpha`.yes `` from inside `§ Alpha` **and** from `§ Beta`. Today
    (golden at phase 0): the value and the constructor respectively, silently, exit 0. After S9:
    the same `AmbiguousTermError` from both sites. This is the fixture that makes §2.4d a
    regression rather than an anecdote.
24. `not-ok/tc/section-rank-qualified-aka-fork.l4` — the `§ Alpha AKA shared` / `§ Beta AKA shared`
    program of §2.4d, with `` `shared`.p `` referenced from inside `§ Alpha` and from `§ Gamma`.
    Today: `1` and an error. After S9: an error from both. Uses only values, so it pins S9
    independently of S1.
25. `section-rank-qualified-nested-fullpath.l4` — `` `Outer`.`Alpha`.x `` resolves and
    `` `Alpha`.x `` does not, for `§ Outer` / `§§ Alpha`. Pins the full-path rule that S5's and S8's
    message wording depends on.

**Unit level.** `jl4-core/test/` — a property that `selectByProximity` never returns `[]` when given
a non-empty input (the formal statement of G3 and half of I1), and that it is a permutation-stable
subset of its input. Add a second property that it is the identity on any input whose reference is a
`QualifiedName` once S9 lands (i.e. that the bypass is total, not partial).

---

## 10. Open rulings

- **R1 — W-SHADOW-CROSSKIND's exact wording and anchor range.** The message must name both
  candidates by section path and offer both qualified spellings, subject to S5's two caveats (full
  paths from the module root; no spelling exists for a top-level candidate, or for either candidate
  in row 4). Open: whether the diagnostic anchors on the _reference_ (useful in the IDE, noisy when a
  name is referenced fifty times) or on the _definition_ of the shadowed binding (one diagnostic per
  collision, but points away from where the reader is). Leaning reference-anchored with
  de-duplication per (reference-name, winner, loser) triple. Nothing in the current `CheckError`
  plumbing forces either.
- **R2 — Sections in ambiguity messages.** `AmbiguousTermError` / `AmbiguousTypeError` today print
  ranges and types and never mention sections (`TypeCheck.hs:4026-4042`); a section name appears only
  by accident, when a candidate's _type_ happened to be written with a qualified spelling
  (`Print.hs:177`). Under B⁺ section membership is the operative fact in rows 1 and 4. Open: whether
  §5 S8 lands as part of phase 3 (so the new errors are self-explaining on arrival) or as its own
  change touching every existing ambiguity golden. Leaning phase 4, separately, because it re-cuts
  goldens unrelated to this spec.
- **R3 — Does this force `SECTION-LEXICAL-SCOPING-SPEC.md` §9?** That section asks for resolution to
  be an explicit desugaring pass with a logged reason, not implicit typechecker behaviour. B⁺ moves
  meaning in row 3a and answers only the cross-kind slice of it. §2.4d strengthens the case: a hazard
  that lived in shipped code, in plain values, invisible to every one of 636 corpus files, is the kind of thing
  a logged resolution decision would have surfaced immediately. Open: whether §9 is now a blocker for
  anything, or remains a standing debt that S5 partially services. Leaning standing debt — but it is
  the honest place to record that L4's audit-grade promise currently has no coverage of name
  resolution at all.
- **R4 — Record-scoped projection (option D1).** Should `e's f` consult the fields of `e`'s type
  before the term namespace? It would make §2.4c a non-question and shrink the selector half of this
  spec to nothing. It is a bidirectional change to `inferRecordProjection` (`TypeCheck.hs:1806`) with
  its own acceptance fallout, and it does not touch constructors. Deliberately deferred to its own
  spec, **not** rejected. If it ever lands, S1's selector half becomes redundant, not wrong.
- **R5 — AKA-sensitivity of section paths.** Measured: `§ Alpha AKA a` and `§ Alpha` are **different
  sections** for ranking. A path element is the whole `NonEmpty Text` of name-plus-aliases
  (`withSectionStack`, `TypeCheck.hs:3604`), compared by list equality in `sectionProximity`
  (`Types.hs:772`), so reopening a section while omitting its `AKA` silently forks the ancestry:

  ```l4
  § Alpha AKA a
  GIVETH A NUMBER
  top MEANS 1
  § Alpha           -- same section to a reader; a different path to the compiler
  GIVETH A NUMBER
  top MEANS 2
  § Alpha AKA a
  GIVETH A NUMBER
  pick MEANS top    -- Result: 1.  exit 0.  No diagnostic.
  ```

  The converse fork also exists and is worse, because it collapses two sections into one key: an
  `AKA` shared between siblings gives them a common qualified spelling, which is the mechanism
  §2.4d's probe uses. This is pre-existing and orthogonal, but B⁺ extends its reach to constructors
  and selectors, and S9 converts its silent half into an error. Open: whether the path element
  should be the section's _primary_ name only, with AKAs contributing to qualified spellings but not
  to identity — and, separately, whether a duplicated `AKA` across siblings should be rejected at
  declaration. Leaning yes to both, as separate fixes. Until then it is a trap worth documenting.

- **R6 — Should `ComputedSelector` be in the value class or the constructor/selector class for
  W-SHADOW-CROSSKIND?** §5 S5 puts it with selectors, on the grounds that it is reached by `x's f`
  and is a field to the reader. But it is a `DECIDE` to the compiler and already ranks as one, so
  under that reading a computed-field-vs-value collision is a same-class shadow and should be silent.
  The choice only affects warning volume, never resolution. Leaning selector class, because the
  reader's model is what the warning is for — and because §2.4a's `payout` pair shows a
  computed-field shadow silently changing an answer today, which is precisely what the warning is
  for.
- **R7 — The untested 96.** Phases 0 and 5 propose a one-off before/after diagnostic diff over
  `jl4/experiments/`, `paper/case-studies/` and `doc/`. The _before_ leg is hoisted into phase 0
  deliberately: the scanners used for §7.1 had a demonstrated 6-of-7 false-positive rate, so a
  captured `l4 check` baseline is worth more than any static scan. Open: whether any of the 96 should
  be promoted into CI as a consequence, or whether the receipt is enough. Two of them are known
  slow — one Charities Jersey file timed out at 120 s during the grounding pass — so promotion is not
  free.
- **R8 — Does row 4 need an escape hatch at all?** B⁺ leaves a constructor/selector and a same-typed
  value in one section mutually unnameable (§4 Decision). Options, none taken here: accept renaming
  (status quo of this spec); revive D2 for that case only; or invent a kind-directed spelling
  (`CONSTRUCTOR yes` / a projection-only form) so the two roles can be told apart. Measured corpus
  incidence is zero, so this stays open rather than blocking. It should be re-opened the first time
  the error is reported by a user rather than by a fixture.

---

## 11. Non-goals

- Not a namespace redesign (D2). Constructors, selectors and values continue to share one flat
  `Environment` keyed by `RawName`.
- ~~Not a change to qualified-name resolution.~~ **Amended after review.** S1 alone _would_ change
  it, silently and unavoidably, because qualified aliases share the original's `Unique` and are
  ranked by the reference site (§2.4d). B⁺ therefore includes S9, which changes qualified resolution
  deliberately: it stops being proximity-ranked. #921's additive claim about _spelling_ stands
  unmodified — every spelling it added still names what it named — but the claim that spelling was
  the _only_ thing at issue does not survive the measurement.
- Not a change to cross-module resolution. I3 and G5 are preserved exactly; the residual noted in
  `SECTION-LEXICAL-SCOPING-SPEC.md` §12 (imports are a flat namespace with no modelled internal
  section structure when seen from an importer) is untouched and remains out of scope — and is
  reinforced by §2.2, since `combineOne` drops imported section paths outright.
- Not `resolveType`'s ranking. Type names already rank and keep ranking; S9's bypass applies to
  qualified type references for consistency, but no unqualified type reference moves.

---

## 12. Review disposition

Three adversarial lenses reviewed the first draft. None concluded a different option wins; two
returned DEFECTIVE on accuracy and completeness. Every finding is dispositioned here.

| #   | Finding                                                                                            | Disposition                                                                                                                                                                                                                                                                                                                                                                                                                              |
| --- | -------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | §7.3 phase 1's "fires only in row 5" is false; the warning also fires in row-3/row-4 shapes today  | **Accepted, fixed.** Re-measured (`row3-stored.l4` → 500 today, a cross-kind discard). §3 now carries an explicit firing column; §7.3 rewritten.                                                                                                                                                                                                                                                                                         |
| 2   | §3's table is incomplete and §9 test 4 mislabels the shape it tests                                | **Accepted, fixed.** Diagnosis refined: the shape does fit old row 3's inequality, but old row 3's _today_ column was wrong for its `dV = dS` sub-case (`cf3` is an error, not "V wins"). Table rebuilt with 3a/3b/2′/3′; test renumbered 5 and relabelled row 3b; new test 6 covers the real row 2.                                                                                                                                     |
| 3   | Qualified resolution is in S1's blast radius and entirely outside the spec; G6 is false            | **Accepted in full — the most important finding.** Replicated (`probe-q1`/`q2`) and extended with a values-only receipt (`` `shared`.p `` → silent `1` here, error there). G6 restated as false; new §2.4d; new **S9**; §11's non-goal amended; three new fixtures (23–25); row 4's un-suppressibility admitted in §4.                                                                                                                   |
| 4   | S5's trigger scope is unspecified and each reading contradicts something                           | **Accepted, fixed.** S5 now says explicitly that both farther-ancestor and off-ancestry drops count, and why (row 2 needs the off-ancestry drop). The firing table is the specification.                                                                                                                                                                                                                                                 |
| —   | S3's "lost to an error, never to silence" contradicts rows 2/2′                                    | **Accepted, fixed.** S3 now reads "to an error or to a warned-about shadow, never to silence".                                                                                                                                                                                                                                                                                                                                           |
| —   | I1's proof cites a guard that does not exist                                                       | **Accepted, fixed — and the reviewer's replacement was also wrong.** Measured (rev): `DECLARE V IS ONE OF yes, yes` is _accepted_, and errors at the reference, not the declaration. I1 re-proved and its scope narrowed to "no less total than today"; new fixture 17.                                                                                                                                                                  |
| —   | §2.2's imported-binding "Path? yes" is backwards                                                   | **Accepted, fixed.** `combineOne` (`Import/Resolution.hs:383`) keeps the accumulator and drops `r.sectionPaths`. Row rewritten; I3 strengthened.                                                                                                                                                                                                                                                                                         |
| —   | The one-collision claim depends on an unstated `WHERE`-local exclusion                             | **Accepted, stated.** §7.1 now names the definition-head restriction, the six additional files it excludes, and why all six are inert (G4/I4).                                                                                                                                                                                                                                                                                           |
| —   | Population counts differ by ±2 between scans                                                       | **Accepted, stated.** Re-derived a third time (636/131/35/96); the band is disclosed and does not move the collision count.                                                                                                                                                                                                                                                                                                              |
| —   | The forward-ref and `ResolutionCascadeSpec` citations mischaracterise those fixtures               | **Accepted, fixed.** S4 now cites the FIX B comment (`Types.hs:967-975`), not the fixture; test 21 corrects the cascade citation (`:79-91`, a **type**, deliberately mismatched); test 18 records that the `WHERE`/field shape has no coverage at all.                                                                                                                                                                                   |
| —   | Phase 4's before-leg should hoist to phase 0                                                       | **Accepted, done.** Now phase 0; rationale (scanner fragility) recorded in R7.                                                                                                                                                                                                                                                                                                                                                           |
| —   | Fixture plan omits selector twins for rows 2/4, qualified-collision and construction-head fixtures | **Accepted, added** as tests 4, 6, 22, 23–25.                                                                                                                                                                                                                                                                                                                                                                                            |
| —   | Reviewer-verified claims that survived unchanged                                                   | `isImport` exempts imports in both directions (I3); `resolveType` ignores `KnownTerm` (now I6); constructor-vs-selector same-`TypeKey` collision is structurally impossible (now in I5); the phase driver orders all `DECLARE` inference first (now cited in S4); every measured hazard reproduction (cf1–cf5, `(R WITH w IS 7)'s w` → 99, R5's AKA fork); exit-code reliability for `run` and `check`; the corpus migration conclusion. |

The ruling did not change. The review's own strongest finding argues _against_ the only option it
could have favoured: §2.4d is silent under A and loud under B⁺, and the spec's entire criterion is
that a meaning-change must not be silent.
