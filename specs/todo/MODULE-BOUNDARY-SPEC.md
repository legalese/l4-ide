# Module Boundary Specification

> **Status (2026-09-05): PARTLY IMPLEMENTED.** §4 (structure-preserving import) is built and
> measured on this branch. §5 (the implicit prelude) is **measured but NOT built** — the
> measurement is in §5 and the ruling that stops it is R3. Nothing in §5 describes the tree.
>
> This document owns ruling **D8 of the 2026-09-05 rulings sheet**, bench card
> **`D8-imports-namespacing`** — the module-boundary question. Always cite the slug, never a
> bare "D8": two unrelated ones already exist in `specs/` (`DATE-LIBRARY-SPEC.md`'s R-D8, on
> algebraic rewrites over date expressions, and `yc-safe/SPEC-NOTES.md`'s D8, on two-round
> collusion against the SAFE holder), so a bare letter-and-number is genuinely ambiguous today
> rather than hypothetically. `gm-rulings-scribe` records the sheet itself on `props/rulings`,
> which as of this writing carries D1–D6 and not yet D8; the sheet says _what Meng decided_,
> this file says _what the decision costs and what shipped_. Do not restate one in the other.
>
> Amends `specs/done/SECTION-LEXICAL-SCOPING-SPEC.md` §12 (FIX C's Residual) and is pointed at
> from its §8.

**Author:** Claude, from Meng's D8 ruling
**Date:** 2026-09-05
**Branch:** `props/module-boundary`

---

## 1. The question

Meng's framing, which is the premise of the whole ruling:

> "I'd always thought of sections as providing some scoping functionality. If you can define the
> same symbol in two sibling sections and there's a resolution rule around it, and a
> fully-qualified way of referring to specific symbols, isn't that scope?"

It is. Measured against the tree, sections are a **scope**: names carry section paths
(`recordSectionPath`, `TypeCheck/Types.hs:897`), ancestry governs resolution
(`sectionProximity`, `:1073`), proximity ranks candidates (`selectByProximity`, `:949`),
siblings may bind the same name, and every section-scoped name gets a second, qualified
spelling in the environment (`qualifiedAliases`, `TypeCheck.hs:3746`).

What sections are **not** is a **boundary**. Nothing can be made private. And — the claim this
document is about — `specs/done/SECTION-LEXICAL-SCOPING-SPEC.md` §12 records that the section
structure is _erased_ on import:

> "imports are treated as a single flat namespace with no notion of **their** internal section
> structure when viewed from an importer."

## 2. What was actually measured (2026-09-05, binary built from `b2a3faac`)

That residual is half right, and the half it gets wrong is the half people would act on.

### 2.1 Cross-module qualified access already works. It was never missing.

```
IMPORT math
#EVAL Math.Constants.EULER       -- 2.718281828459045
#EVAL Math's Constants's EULER   -- 2.718281828459045
#EVAL EULER                      -- 2.718281828459045
```

`math.l4:11` defines `EULER` inside `§ Math` / `§§ Constants`. All three spellings answer, with
no change to the compiler. The mechanism is not `sectionPaths` at all: `qualifiedAliases`
registers a **second environment key** (`QualifiedName ("Math" :| ["Constants"]) "EULER"`)
sharing the original `Unique`, and `unionImportedCheckEnv` (`TypeCheck/Types.hs:540`) unions
environments across the boundary with `Map.unionWith List.union`.

So an importer can already name an imported binding under its defining section. What it could
not do is **learn** that name from the compiler.

### 2.2 Merging `sectionPaths` cannot change which overload is chosen

This is the property the §12 residual worried about, and it is structural, not incidental.
`sectionPaths` has exactly three readers:

| reader                  | file:line                 | what it uses the path for |
| ----------------------- | ------------------------- | ------------------------- |
| `sectionQualified`      | `TypeCheck/Types.hs:731`  | **diagnostics only**      |
| `resolveTermFilteredIn` | `TypeCheck/Types.hs:1206` | proximity ranking         |
| `resolveType`           | `TypeCheck.hs:1433`       | proximity ranking         |

Both ranking readers reach the map only through `ancestorProximity` and `selectByProximity`,
and **both test the candidate's module URI before they consult it**:

- `ancestorProximity curUri _ _ u | u.moduleUri /= curUri = Nothing`
- `selectByProximity`: `isImport u = u.moduleUri /= curUri`; imports are appended unranked and
  are excluded from `ancestors` before `Map.findWithDefault [] u paths` is ever evaluated.

An imported `Unique` therefore never reaches the lookup. The standard-library overload
resolution that FIX C protects depends on that URI test, not on the map being empty — so
filling the map leaves it untouched.

`sectionQualified` is called only from `ambiguousTerm` and `ambiguousType`, both of which
`addError` and return an `OutOfScope` sentinel. Error **content** is never read by `prune`
(`Types.hs:1637`), which selects branches by viability, `deferredChoices` and position. So the
change cannot alter a successful resolution either.

### 2.3 The hole that is real: a diagnostic you cannot act on

Before this change, `jl4/examples/not-ok/tc/section-scoping-import-collision.l4` reported:

```
      `Local Section`.EULER (defined at section-scoping-import-collision.l4:14:1-6) of type NUMBER
      EULER (defined at math.l4:12:1-6) of type NUMBER
```

The reader is told the reference is ambiguous, then offered two options — one of them spelled
**exactly like the ambiguous name**. Pasting it back reproduces the error. By §2.1 a spelling
that works exists; the compiler simply had no way to say it.

Across the whole tree only **18 golden files** contain an ambiguity diagnostic at all, and only
**two lines** in all of them name a candidate defined in another module's section.

## 3. What cannot be delivered, and why it is not a matter of effort

"Proximity ranking among bindings imported from different sections of another module" has no
available meaning. The importer's `sectionStack` names a path in the **importer's** section
tree; an imported binding's path names one in the **imported module's** tree. `sectionProximity`
is `List.isPrefixOf` over those paths. Across two unrelated trees that relation is not merely
unimplemented, it is undefined — every imported candidate would be `Nothing` for the same
reason a stranger's street number is not nearer or farther along your own street.

Two designs could give it a meaning. Neither was ruled and neither is built:

- **Rank imports by their own depth.** Arbitrary: it would make a top-level export of a
  dependency beat a section-nested one for no reason a reader could predict, and it would
  silently repick overloads in the 283 files that import the prelude directly.
- **Scope an `IMPORT` written inside a section to that section.** Coherent, and it is what
  "sections as a boundary" would really mean — but it is a different feature with its own
  surface syntax, and it belongs behind a ruling of its own.

Recorded so that a later reader does not take §4 for a partial job.

## 4. RULED AND BUILT — structure-preserving import

**R1. An imported binding's section path crosses the import boundary.** A module's
`CheckResult` carries `sectionPaths` for every binding it can see — its own and, transitively,
its dependencies' — and both import-boundary merge sites union that map into the importer's
initial `CheckState`.

**R2. It is used for naming, not for ranking.** The merged entries are read by
`sectionQualified` only. The URI test in `ancestorProximity` / `selectByProximity` stays exactly
as FIX C left it, and cross-module candidates remain co-equal for overload resolution. §5.5 of
the section-scoping spec is unchanged as a resolution rule; only its residual is discharged.

### 4.1 What changed

| file                                                    | change                                                                                      |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `jl4-core/src/L4/TypeCheck/Types.hs`                    | new `type SectionPaths`; `CheckResult` gains a `sectionPaths` field                         |
| `jl4-core/src/L4/TypeCheck.hs`                          | populates it from the final `CheckState`                                                    |
| `jl4-core/src/L4/Import/Resolution.hs`                  | `combineOne` unions the dependency's map; `TypeCheckWithDepsResult` gains `tcdSectionPaths` |
| `jl4-lsp/src/LSP/L4/Rules.hs`                           | `TypeCheckResult` gains the field; `unionCheckStates` unions it                             |
| `jl4-core/src/L4/API.hs`, `jl4/tests/VizAutoRefresh.hs` | the other two construction sites                                                            |

`Map.union` is collision-free by construction: `Unique` embeds its defining module
(`Syntax.hs:41`), so two modules' maps have disjoint key sets and the merge is
order-independent. The two merge sites are kept verbatim-parallel and each carries a comment
naming the other, because they have drifted apart before (see the note on
`unionImportedCheckEnv`).

### 4.2 The payoff, demonstrated

The same diagnostic now reads:

```
      `Local Section`.EULER (defined at section-scoping-import-collision.l4:14:1-6) of type NUMBER
      Math.Constants.EULER (defined at math.l4:12:1-6) of type NUMBER
```

and **both options are spellings you can paste**, which
`jl4/examples/ok/section-scoping-import-qualified.l4` asserts by evaluating each one.

Quoting is handled by the existing renderer, so a section name containing spaces survives the
round trip. Measured on a probe against the prelude's `§§ Numeric Aggregates`:

```
      sum (defined at collide.l4:4:1-4) of type FUNCTION FROM LIST OF NUMBER TO NUMBER
      Prelude.`Numeric Aggregates`.sum (defined at prelude.l4:265:1-4) of type FUNCTION FROM LIST OF NUMBER TO NUMBER
```

and the suggested spelling evaluates:

```l4
#EVAL Prelude.`Numeric Aggregates`.sum (LIST 1, 2)   -- 3
```

### 4.3 Corpus effect

Two golden lines in the entire tree change, both of them a bare imported name gaining its
defining section:

- `not-ok/tc/tests/section-scoping-import-collision.golden` — `EULER` → `Math.Constants.EULER`
- `not-ok/tc/tests/set-equals-ambiguous.golden` — `` `__EQUALS__` `` → `` Prelude.Sets.`__EQUALS__` ``

No evaluated answer moves in any goldened file. The golden suite is itself an evaluation
differential and not merely a diagnostic one: a `.golden` captures the `Result:` of every
directive in its file (see `ok/tests/logic.golden`), and the goldens in the tree were generated
by the pre-change compiler. Run against them, the changed compiler gives **2815 examples,
2 failures** — the two lines above and nothing else.

**State its reach exactly, because it is not the whole corpus.** Counted from the goldens on
disk (a `tests/<stem>.golden` exists): **411 of the 894 `.l4` files are goldened, and 102 of
those have the prelude in scope.** So the run exercises 102 of the 298 prelude-importing files
directly; the other 196 are covered by the structural argument in §2.2, not by this run. That
ordering matters. The proof is that an imported `Unique` cannot reach the lookup; the
differential corroborates it and was never carrying it. An earlier draft of this section said
the run covered "all 282 that import the prelude", which was wrong on both the count and the
coverage — the kind of rounding-up that survives precisely because it points the right way.

### 4.4 What it costs, and what was not measured

Resolution does no extra work: no candidate is added, no comparison is added, and the merged
entries are reached only on the error path. The per-import cost is one `Map.union` over
disjoint key sets. #929 (the charities-corpus slow check) was a candidate explosion, and this
change cannot produce one.

The cost that IS real is memory. A module's `sectionPaths` now holds its **transitive**
closure, and every `CheckResult` / `TypeCheckResult` carries and forces one, so a deep import
chain stores the same entries once per level. Today's shape makes that uninteresting — the
whole `jl4-core/libraries` tree is 22 modules and the prelude contributes a few hundred entries
— but a much larger library graph would want this shared rather than copied.

**Not measured: before/after wall time.** The pre-change binary was overwritten by the rebuild
before a timing baseline was taken, and a comparison against a binary from another worktree
would not be sound. Absolute times on this branch, on a loaded machine: `prelude.l4` 0.51s,
`actus.l4` 2.53s, `set-equals-ambiguous.l4` 0.40s. Stated as absolutes, not as a delta.

## 5. MEASURED, NOT BUILT — the implicit prelude

D8's second half asks that every script get the prelude without writing `IMPORT prelude`, with
an opt-out spelled `IMPORT NOT Prelude`. It is **not built**. What follows is the measurement
that decided that, taken on the pre-change binary with no compiler change at all: the whole
`.l4` corpus was copied out of the repo with its directory structure intact (so
importer-relative resolution still behaves), `IMPORT prelude` was prepended to every file that
does not already have the prelude in scope, and `l4 check` was re-run. **The repository was
never modified by the measurement.**

### 5.1 How much would change

Transitive closure over `IMPORT`, resolving a module name against the importer's own directory
first and then `jl4-core/libraries`. Counted over **every `.l4` file in the worktree** —
`doc/`, `skills/` and `jl4/tests-cli/fixtures/` included — on this branch, which is
`88d9f8b9` plus §4 and adds one `.l4` of its own:

|                                                             | files   |
| ----------------------------------------------------------- | ------- |
| total `.l4` (893 at `88d9f8b9`; this branch adds one)       | 894     |
| prelude in scope today (directly or transitively)           | 298     |
| direct `IMPORT prelude`, of those                           | 283     |
| **no prelude in scope — what an implicit import would add** | **596** |

Both halves of that — the ref and the counting rule — are load-bearing. Four different totals
for "how many `.l4` files are there" circulated while this was being written (847, 884, 887,
894), and every difference was a ref or a directory filter, not a disagreement about the tree.
Re-measure rather than borrowing, and say which commit you measured at.

### 5.2 What it would cost

| verdict after adding the prelude                       | count  |
| ------------------------------------------------------ | ------ |
| green before, green after                              | 500    |
| **green before, RED after**                            | **18** |
| red before, red after (`not-ok` fixtures and the like) | 75     |
| skipped (the file _is_ a `prelude.l4`)                 | 3      |
| red before, green after                                | 0      |

**18 of the 518 files that check clean today would break — 3.5%.** Every one fails the same
way, an `AmbiguousTermError` against a same-named, same-typed prelude definition:

```
jl4/examples/ok/elem.l4
      `Membership in a list`.elem (defined at elem.l4:10:1-5) of type FOR ALL a FUNCTION FROM a AND LIST OF a TO BOOLEAN
      elem (defined at prelude.l4:465:1-5) of type FOR ALL a FUNCTION FROM a AND LIST OF a TO BOOLEAN
```

The eighteen: `doc/reference/types/for-all-example.l4`, and under `jl4/examples/ok/` —
`appform`, `datatypes`, `elem`, `fold`, `forward`, `inference`, `lazytrace`,
`lazytrace-exception`, `let-in-functions`, `loop`, `misc`, `mixfix-over`, `namedapp`,
`nested-patterns`, `nlg_decide2`, `replicate`, `typesynonms`.

**The failure class is loud, not silent**, and that is FIX C working as designed: an import and
a local binding of the same name and type stay a genuine ambiguity rather than one silently
shadowing the other. An evaluation differential over the files that stay green found **no
answer moving** (`l4 run`, `Result:` blocks compared per file): 490 identical, and the two that
differed did not reproduce — one stamps wall-clock transaction time and disagrees with itself
between two runs, the other makes live HTTP calls that return fresh UUIDs.

**Measured twice, at two bases, with the same answer — and the stability is the finding, not
the number.** These figures were first taken at `b2a3faac` (884 files, 588 without the prelude,
18 of 511 red) and re-taken at `88d9f8b9` after 23 commits landed. The eighteen files are
**identical both times**, by name, and the percentage is unchanged. The counts above are the
later ones.

What that buys is the difference between a measurement and a decision. A one-shot 3.5% invites
"re-measure later, it might be cheaper". A 3.5% that does not move across 23 commits says the
cost is a property of **the prelude's name surface** — how many ordinary names a general-purpose
standard library claims — and not an artefact of one snapshot of the corpus. It will not drift
away on its own, and R3 can be relied on rather than merely deferred to.

### 5.3 Three further obstacles, each measured

**The opt-out does not parse.** `IMPORT NOT Prelude` today:

```
    unexpected NOT
    expecting identifier or space token
```

`import'` (`Parser.hs:669`) is `TKImport` followed by `name`, and `MkImport Anno n (Maybe
NormalizedUri)` (`Syntax.hs:213`) has nowhere to put a negation. Supporting Meng's spelling
needs an optional `TKNot` lexeme in the production, a field on `MkImport`, exactprint support
(the token must be captured via `annoLexeme` or the printer loses it), an `L4.Print` case, and
a revisit of every `MkImport _ n _` match site. Feasible, not free — and it is grammar surface,
which is the part hardest to withdraw later.

**Three injection sites, not one.** An implicit import has to be synthesised in
`GetMixfixRegistry` (`Rules.hs:595`) as well as `GetImports` (`:631`) and
`L4.Import.Resolution` — the first because the prelude defines mixfix operators and the
_parser_ consults imported hints, so a file that got the prelude only at type-check time would
parse differently from one that imported it explicitly.

**Which prelude an implicit import resolves to is a decision, not a detail.** Resolution order
is `JL4_LIBRARY_PATH → root → importer-relative → embedded → XDG → bundle`. Three files are
named `prelude.l4`: the real one, a vendored copy in `jl4/experiments/thailand-cosmetics/`, and
`jl4/tests-cli/fixtures/library-shadow/sibling-wins/prelude.l4`, whose entire purpose is to
pin the shadowing order. Under the existing order, `anthropicClient.l4` and `promptLibrary.l4`
would silently begin importing the vendored copy, and a file that _is_ a prelude would
self-import — which fails as a silent `GraphException`, not a diagnosable error. Any
implementation must state its answer here and be checked against all four
`library-shadow` fixtures.

**R3 (ruling). The implicit prelude is not built on this evidence.** 18 files is a migration,
the brief asked for none, and the opt-out needs grammar surface. §5.4 records the one rule that
would remove the migration entirely, so the next attempt need not rediscover it. What ships
instead is the correction described in §5.5 — because the cost of _not_ deciding was that the
documentation had already promised the feature.

### 5.4 The design that would make it free, and why it is still not built tonight

R3 declines the implicit prelude because it costs an 18-file migration. That cost is not
inherent — it is a consequence of making the implicit import a **peer** of the module's own
bindings. One rule removes it:

> **An implicitly imported binding is invisible for any name the module already binds** —
> whether by its own definition or by an explicit `IMPORT`. The implicit prelude is a fallback,
> not a competitor.

By construction this makes all 18 green. Every one of them fails because a local definition and
a prelude definition of the same name and type became co-equal candidates; under the rule above
the prelude one is not a candidate at all, which is exactly the situation those files are in
today. And it is a **strict extension** for all 588: a name the file defines behaves precisely
as it does now, and a name it does not define becomes available. No file can change its answer,
because no name it currently resolves gains a competitor.

It is not built tonight for three reasons, all of them about surface rather than difficulty:

1. It is **a new resolution rule**, not a plumbing change, and it needs its own regression
   corpus — the interesting cases are a local that shadows a prelude name at a _different_
   type, and an explicit `IMPORT` of a module that re-exports a prelude name.
2. It needs a way to mark a candidate as implicitly imported. The module URI cannot carry it:
   an explicit `IMPORT prelude` and an implicit one resolve to the same file and mint the same
   `Unique`s, so the two would be indistinguishable exactly where they must differ.
3. The opt-out (§5.3) is grammar surface, and grammar is the hardest thing to withdraw.

Recorded here so that the next attempt starts from the rule rather than rediscovering the 18.

### 5.5 The documentation already claimed this, and it was false

Measured 2026-09-05 on the pre-change binary:

```
$ cat noimport.l4
#EVAL sum (LIST 1, 2, 3)
$ l4 check noimport.l4
    I could not find a definition for the identifier
      sum
```

Five published claims said otherwise. Line numbers are as at `88d9f8b9`, the base this was
measured and corrected on:

- `doc/reference/libraries/IMPORT.md:50` — "`prelude` | Core functions (auto-imported)"
- `doc/reference/libraries/IMPORT.md:60` — "Prelude is automatically imported in all files"
- `doc/reference/libraries/README.md:9` — "Standard functions (automatically imported)"
- `doc/reference/libraries/README.md:58` — "Automatically imported."
- `doc/reference/README.md:68` — "**prelude:** Standard functions (auto-imported)"

This is the drift the user-level `CLAUDE.md` rule 1 is about: a planned state written in the
present tense, believed by every reader since. **All five are corrected on
`props/auto-prelude`**, which stacks on `props/module-boundary` because it edits this file.

`libraries/README.md` contradicted itself, and the shape of the contradiction is why the false
half survived: the true statements **bracket** the false ones rather than sitting beside them.
At `88d9f8b9` that page reads "automatically imported" at **:9**, "Libraries require explicit
import:" at **:33**, "Automatically imported." at **:58**, and "Requires: `IMPORT prelude`" at
**:141** and **:153**. A reader arriving at :9 has no reason to doubt it, and by :33 has
already learned the opposite without noticing the collision.

(Two figures for the gap between those statements circulated tonight — "twenty-five lines" and
"eighty-three lines" — from picking different true-claim anchors. Both described a real
contradiction; neither was a measurement of the same thing. The list above replaces both.
A `file:line` is only as good as the ref it was read at: these are pinned to `88d9f8b9`.)

**Not corrected here: `skills/writing-l4-rules/SKILL.md`.** It carried the same falsehood as
"The prelude is always available.", and PR #336 fixed it first and better — its replacement
gives the failing probe verbatim and adds the transitive case (`hierarchy` opens with its own
`IMPORT prelude`), which none of the five above mention. That version stands; this branch took
it unchanged at the rebase.

If the implicit prelude is later built, that correction is what gets reverted — deliberately,
in the PR that makes it true again, and not before. A doc that promises a feature is not a
cheaper way of shipping it.

## 6. Open

- **Section privacy.** Nothing can be made private to a section. Sections are a scope and now
  name their contents across a boundary, but they still export everything. Not ruled.
- **`IMPORT` inside a section.** See §3. The coherent version of cross-module proximity, and
  the one a "module boundary" would need. Not ruled.
- **`constBodies` is flattened the same way** `sectionPaths` was, at both merge sites. Not
  investigated here; noted because the next reader of `combineOne` will see it.
