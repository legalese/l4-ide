# corpus(sets): acceptance corpus for `SET OF a`, variadic construction and infix mixfix exact-printing

**What this adds.** Five new `.l4` example programs under `jl4/examples/ok/` — the executable
acceptance suite for L4's set-theoretic vocabulary — together with their goldens, plus regenerated
exactprint goldens for the eight pre-existing `mixfix-*` examples. After this, the corpus
demonstrates and pins: writing sets with the canonical drafting words (`UNION`, `INTERSECT`,
`` `LESS` ``/`WITHOUT`, `` `is in` ``, `` `is subset of` ``, `` `set equals` ``, `setFromList`/
`setToList`/`setSize`/`emptySet`); chaining those words unparenthesized and getting the right
grouping from declared fixity (`a UNION b INTERSECT c` = `a UNION (b INTERSECT c)`); building a
record whose single field is a list by listing its elements (`Bag OF 1, 2, 3`); and round-tripping
infix mixfix call sites through `l4 format` without them being rewritten to prefix form. It carries
no compiler and no library code — it is the corpus half of that work.

**Why.** Two drivers. (1) The set vocabulary exists so that the drafting distinction legal texts
turn on — whether "education and welfare" is an intersection, a union, or an exegetical restatement —
can be written down and evaluated rather than argued about; the examples encode the trichotomy from
`SET-OPERATORS-SPEC.md` §11.5 as running code over real authorities (Royal Trust [1986] UKPC 34,
Nam Hong [2016] SGCA 42, Koh Lau Keow [2013] SGHC 155, Re Best [1904] 2 Ch 354). (2) The mixfix
goldens on `main` record a formatter bug: upstream smucclaw/l4-ide#918 — `l4 format` rewrote
`1 UNION 2` to `UNION 1 2` and duplicated keywords in chains (`1 UNION 2 UNION 3` →
`UNION UNION 1 2 UNION 3`). These goldens are the corpus-side evidence that it no longer does.

## What's in it

**Five new examples (5 `.l4`, 20 goldens — 4 per file: `.golden`, `.ep.golden`, `.nlg.golden`,
`.schema.golden`):**

- `ok/set-operators.l4` — the vocabulary end to end. The §11.5 trichotomy on strings (subset /
  disjoint / co-extensive / properly overlapping), difference in both spellings (backticked
  `` `LESS` `` because bare `LESS` is a lexer keyword, and the bare alias `WITHOUT`), an enum
  universe with a computable absolute complement (`DECLARE State IS ONE OF NY, NJ, CT`), and the
  construction/conversion corner.
- `ok/set-operators-overloads.l4` — the operator overloads that survive: `PLUS`/`MINUS` bare and
  precedence-correct (`a1 PLUS b1 MINUS b1` unparenthesized), with the semilattice trap
  demonstrated (`(a ∪ b) \ b` is *not* `a`), and numeric/string dispatch shown untouched. Its
  header records that the `AND`/`OR`-on-sets overloads were **removed** on 2026-07-28 and that
  term-level union is now spelled `UNION` in its own word.
- `ok/set-operators-precedence.l4` — the fixity acceptance test. Every bare chain is paired with
  its explicitly-parenthesized reading and the two `#EVAL`s must agree: `INTERSECT` binds tighter
  than `UNION`, same-operator chains left-associate, explicit parentheses still override, `WITHOUT`
  mixes at `UNION`'s precedence, and a longer mixed chain.
- `ok/set-operators-nested.l4` — pins a **known limit, deliberately**. The set quotient is one level
  deep: observers ignore order and duplicates among elements, but element comparison is builtin
  structural equality, so nested sets and record-wrapped sets compare by representation. The file's
  own comment says it is documented current behaviour, not an endorsement, and exists so that a
  future specificity rule or Phase-4 lint changes these results *loudly*.
- `ok/variadic-construction.l4` — route-α: a constructor with exactly one `LIST`-typed field applied
  to two or more arguments collects them (`C OF e1, …, en ⇒ C OF (LIST e1, …, en)`). It pins the
  boundaries as much as the feature: the exact-fit one-list reading still wraps rather than
  singleton-collecting, juxtaposition (`Bag 4 5 6`) collects identically, compound arguments work,
  and a same-named function that makes the call site typecheck directly wins outright over the
  rescue (`#EVAL Wrap 1 2` → `42`).

**Eight regenerated mixfix goldens** (`mixfix-basic`, `mixfix-over` — both `.golden` and
`.ep.golden`; `mixfix-multiline`, `mixfix-cross-module-binary-call`,
`mixfix-cross-module-ternary-call`, `mixfix-cross-module-ternary-def` — `.ep.golden` only). Two
kinds of change, both consequences of the #918 fix:

- the `.ep.golden` files stop recording prefix-mangled output — `` `plus` 3 5 `` becomes
  `` 3 `plus` 5 ``, `` `op1` `op2` `op3` `op4` 1 2 `op2` 3 … `` becomes
  `` 1 `op1` 2 `op2` 3 `op3` 4 `op4` 5 ``, and the postfix cases stop dropping their operand
  entirely (`#EVAL percent` → `#EVAL 50 percent`). `mixfix-multiline.ep.golden` shows the same
  correction across line breaks: the leading keyword no longer floats above its operands
  (`` `raised to` `` / `base` / `exponent` becomes `base` / `` `raised to` `` / `exponent`);
- the two `.golden` files shift only **source ranges** (`mixfix-basic.l4:72:1-15` → `:72:1-17`), not
  values — the mixfix `App` node's range used to be just the keyword token and is now the full call
  span. Every evaluated result in both files is unchanged.

## Evidence

Quoted from the source PRs:

- #122 (prelude + these examples): "Suite: **1136 examples, 0 failures** (includes 17 new goldens +
  refreshed prelude exactprint golden)." Review was a "33-agent adversarial workflow (5 lenses, 2
  refuters per finding): 11 confirmed findings, all fixed or pinned — including the
  `contents`→`elements` field rename (Dictionary collision)".
- #123 (route-α variadic construction): "Suite: **1128 examples, 0 failures**."
- #124 (mixfix exactprint, #918): "Verified end-to-end: `l4 format` on the issue repro is
  byte-identity; `#EVAL` results unchanged between original and formatted output." Reviewed by
  "adversarial multi-agent review over five lenses (anno invariants, typechecker interaction,
  LSP/range consumers, parser layout, test adequacy) with per-finding refutation."
- #133 (fixity on the set operators): "Full suite: **1481 examples, 0 failures**."
- #168 (removing the `AND`/`OR` set overloads): the removal was performance-driven —
  smucclaw/l4-ide#929, a second `__AND__`/`__OR__` candidate making typechecking exponential
  (base 3) in chain depth. "With the overloads removed, every file in that corpus checks in **under
  a second** (part-3: 0.51 s; part-7: 0.83 s, previously 10 h+), and the full golden suite runs
  ~28 % faster." Blast radius was "two users of AND/OR-on-sets in the entire tree — the feature's
  own acceptance example (reworked to `UNION`) and `doc/reference/libraries/sets-example.l4`."
  `cabal test all` green at "jl4-test 1830/0, jl4-core-test 269/0, jl4-service-test 311/0,
  l4-cli-test 96/0".

Verified directly against the two branches while preparing this split (not a quote from any PR): on
`main`, `mixfix-basic.ep.golden`, `mixfix-over.ep.golden` and `mixfix-multiline.ep.golden` all
differ from their `.l4` sources; on `unstable`, **all eleven** `.ep.golden` files this PR touches or
adds — the six mixfix ones and the five new set/variadic ones — are byte-identical to their sources.
That byte-identity is the property the exactprint suite is for, and it is what #918 broke.

Note the suite totals above are snapshots from five different days on a moving branch and are not
comparable to each other.

## Independence

**This PR is corpus only. It does not stand alone.** Every one of its 25 set-and-variadic files
exercises code that lives in sibling themes, and every golden encodes the behaviour of that code:

- **lang-imports-stdlib** owns `jl4-core/libraries/prelude.l4` — the `SET OF a` declaration, the
  whole vocabulary, the `PLUS`/`MINUS`/`EQUALS` overloads, the removal of the `AND`/`OR` overloads,
  and the `@infixl 6`/`@infixl 7` annotations. Without it, all four `set-operators*.l4` files fail
  to typecheck.
- **lang-syntax-typecheck** owns the compiler side: the mixfix parser change behind the regenerated
  `.ep.golden` files, the fixity mechanism that `set-operators-precedence.l4` measures, and the
  route-α typechecker rescue (`orElseKeepAll` in `TypeCheck/Types.hs`) that
  `variadic-construction.l4` exists to exercise. It also carries the matching negative tests
  (`not-ok/tc/set-equals-ambiguous.l4`, `not-ok/tc/set-and-unoverloaded.l4`) that these positive
  examples cross-reference in their comments.
- **specs** owns `specs/todo/SET-OPERATORS-SPEC.md`, which these files cite by section (§5, §11.5,
  §14, §16, §D7.1). Prose only — nothing breaks if it lands later, but the comments point at
  sections a reader cannot otherwise find.
- **docs** owns `doc/reference/libraries/sets-example.l4`, the other file #168 had to fix.

Ordering: this PR should land **at or after** lang-imports-stdlib and lang-syntax-typecheck. Landing
it before either turns `jl4-test` red (per CLAUDE.md §3.1, `failFirstTime` is `True` and every `.l4`
under `jl4/examples/ok/` must have its four goldens matching). The eight regenerated mixfix goldens
are the sharper constraint of the two: they are *edits* to files that already exist on `main`, so
this PR and lang-syntax-typecheck's parser change must land together or the mixfix goldens fail from
whichever side goes first.

## Risk if rejected

The set vocabulary, the fixity, the variadic rescue and the #918 formatter fix would all ship with
**no executable acceptance test and no goldens** — including the four rows of the drafting
trichotomy that are the whole point of the feature, the paired bare-vs-parenthesized chains that are
the only check that fixity groups correctly, and the regression lock that keeps a same-named
function from being shadowed by the route-α rescue. Worse, dropping this while lang-syntax-typecheck
lands leaves the eight stale mixfix goldens on disk still asserting the prefix-mangled output, so
`jl4-test` fails on `main` until someone re-blesses them by hand.

## Part of a 15-PR merge batch — measured by building and testing, not inferred

**This PR cannot land on its own, and neither can the other fourteen below.** They go into the merge
queue as one batch, or land in immediate succession accepting that `main` is broken in between.

| PR | theme | | PR | theme | | PR | theme |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **#245** | `lang-syntax-typecheck` | | **#252** | `service-cli` | | **#247** | `mlir` |
| **#241** | `lang-eval-ledger` | | **#236** | `dmn-export` | | **#230** | `actus-archive` |
| **#242** | `lang-imports-stdlib` | | **#232** | `bpmn-export` | | **#244** | `lang-sets` † |
| **#243** | `lang-printer` | | **#250** | `openfisca-export` | | **#234** | `corpus-legal-new` † |
| **#240** | `ladder-viz` | | **#246** | `lsp` | | **#235** | `corpus-regcf` † |

† The three marked themes are not needed to **compile** — they are needed to make the **golden suite
pass**. The distinction matters because the merge queue's required check is *Haskell Build **&
Test***, so the set that can actually merge is all fifteen. Twelve is only the build-green floor.

### Why the split cannot separate them

The partition is by file, but several changes are atomic at the *type* level.
`lang-syntax-typecheck` reshapes types that modules in ten other themes construct or pattern-match:
it removes the `Expr` constructor `Exponent` (upstream #83), widens `MkAssume` 4→5, `MkTypedName`
4→5 and `MkOptionallyTypedName` 3→4 (the `TYPICALLY` default), adds `Record` / `ReadCell` /
`RecallMode` and `unqualifiedNameToText`, and adds strict fields to `MkCheckState` and `MkCheckEnv`.
`lang-eval-ledger` widens `MkEvalDirectiveResult` 3→4; `service-cli` adds a field to
`FunctionSchema.Parameter` and owns the `L4.Dmn.*` / `L4.Bpmn.*` call sites in the CLI.

The dependency runs **both ways**, which is what makes it unbreakable at file granularity. Land
`lang-syntax-typecheck` alone and other themes' modules — still at `main`'s revision — name a
constructor that is gone or pass the wrong number of arguments. Land any of those alone and its
updated module meets `main`'s unchanged types. Neither direction compiles.

### The measurement

Each row is `git merge` of the named slices onto `origin/main`, then `cabal build all` under GHC
9.10.3. The `jl4/tests/Main.hs` conflict resolves to the union import `(lookupEnv, setEnv)`, and the
`.cabal` conflicts to the union of added lines.

| slices under test | result |
| --- | --- |
| the five previously claimed here — 245, 241, 243, 252, 247 | **fails to build**, 4 errors |
| + 242, 240, 246 (eight) | **fails to build**, 1 error |
| + 230 (nine) | **fails to build**, 9 errors |
| nine, less 246 | **fails to build**, 5 errors |
| twelve, less 247 | **fails to build**, 4 errors |
| **twelve** | **builds**; 6 of 7 suites pass, `jl4-test` **fails 39 of 2508** |
| **fifteen** (+ 244, 234, 235) | **builds**; `jl4-test` **2568 examples, 0 failures** |

The first error of each failing build, verbatim, and the slice that supplies the fix:

```
src/L4/Import/Resolution.hs:341:7: error: [GHC-95909]
    • Constructor ‘TypeCheck.MkCheckState’ does not have the required strict field(s):
        constBodies :: Map Unique (Expr Resolved)
        sectionPaths :: Map Unique [NonEmpty Text]
                                                        -> lang-imports-stdlib  #242

src/L4/Viz/Ladder.hs:310:18: error: [GHC-27346]
    • The data constructor ‘MkOptionallyTypedName’ should have 4 arguments, but has been given 3
                                                        -> ladder-viz           #240

src/L4/ACTUS/FeatureExtractor.hs:519:12: error: [GHC-27346]
    • The data constructor ‘MkTypedName’ should have 5 arguments, but has been given 4
                                                        -> actus-archive        #230

src/LSP/L4/Inspector.hs:141:43: error: [GHC-27346]
    • The data constructor ‘EL.MkEvalDirectiveResult’ should have 4 arguments, but has been given 3
                                                        -> lsp                  #246

src/L4/MLIR/Schema.hs:675:7: error: [GHC-76037]
    Not in scope: data constructor ‘Exponent’
                                                        -> mlir                 #247

app/L4/Cli/Export.hs:74:1: error: [GHC-87110]
    Could not load module ‘L4.Bpmn.Emit’.
                                                        -> dmn-export           #236
                                                           bpmn-export          #232
                                                           openfisca-export     #250
```

And the 39 golden failures at twelve, which is what adds the last three:

| failures | tests | supplied by |
| --- | --- | --- |
| 8 | `ok/mixfix-{basic,cross-module-*,multiline,over}.l4` — parses/exactprints | `lang-sets` **#244** |
| 3 | `legal/{promissory-note,ceo-performance-award}.l4` — exactprint, json schema | `corpus-legal-new` **#234** |
| 28 | DMN 1.3 export and BPMN export over *the Reg CF corpus* (§15, §16, PROCESS-TRACK §8.3) | `corpus-regcf` **#235** |

Three of these could not have been found by reading:

- **`actus-archive` (#230) is a batch member.** `jl4-actus-analyzer` lives on `main`, is deleted by
  `unstable`, and its `FeatureExtractor.hs` pattern-matches `MkTypedName`. It is in `main`'s
  `cabal.project`, so `cabal build all` compiles it. Invisible to CI on any single PR, because the
  build dies inside `jl4-core` long before reaching it.
- **The three corpus themes are load-bearing.** Their `.l4` files are the input the exporter tests
  read. They are also exactly the PRs whose own CI reports green without running a single test —
  the `haskell` paths-filter in `pr-checks.yml` does not match `jl4/examples/**`.
- **The import-level check cannot see any of this.** `depcheck.mjs` resolves module imports, and
  every type above lives in a module `main` already has. An earlier revision of this section named
  five PRs on the strength of the `Exponent` constructor alone.

### What is *not* in the batch

Everything else in the `aug2026` set is independent or a one-way dependent that can follow. In
particular `tests-cli` (#253) needs this batch for its 47 fixtures, and `ci-build` (#233) must merge
**last** — its new jobs gate code that arrives with the feature PRs.


## Provenance

Folded from these `unstable` PRs (only their `jl4/examples/ok/` contents; each also carried prelude,
compiler or spec changes now split into the themes named above):

- legalese/l4-ide#122 — `feat(prelude): SET OF a — set-theoretic operators (SET-OPERATORS-SPEC Phases 1+2)` (`mengwong/set-operators-phase1`)
- legalese/l4-ide#123 — `feat(typecheck): route-α variadic construction — SET OF 1, 2, 3 (SET-OPERATORS-SPEC Phase 3a)` (`mengwong/set-operators-route-alpha`)
- legalese/l4-ide#124 — `fix(parser): exact-print mixfix call sites in source order (#918)` (`mengwong/fix-mixfix-format`)
- legalese/l4-ide#133 — `feat(prelude): fixity for set operators — bare UNION/INTERSECT chains (SET-OPERATORS-SPEC Phase 3d)` (`mengwong/set-operators-phase3d`)
- legalese/l4-ide#168 — `feat(prelude): remove the AND/OR set overloads — write UNION explicitly` (`mengwong/set-andor-unoverload`)

Upstream issues referenced by those PRs: smucclaw/l4-ide#918 (mixfix formatter), smucclaw/l4-ide#929
(exponential typechecking on overloaded connectives). Per CLAUDE.md §1.1 they must be closed by hand
once the owning theme lands — the fixes themselves are in lang-syntax-typecheck and
lang-imports-stdlib, not here.
