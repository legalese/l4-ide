# feat(lang): front end and typechecker — fixity declarations, exhaustiveness analysis, section scoping, and the #929 overload pre-filter

**What this adds**

This is the L4 compiler front end: lexer, parser, annotation attachment, name resolution, unification and the typechecker, together with the corpus of `.l4` fixtures and goldens that pin their behaviour. After it, a library can declare operator precedence and associativity (`@infixl 6` on `UNION`) so unparenthesized word-operator chains re-associate GHC-style instead of failing on arity; deeply nested outlines can be written with `•` bullets that desugar to `LIST`; a multi-clause pattern-matching `DECIDE` is analysed as a clause *matrix* so incomplete decision tables are reported instead of silently nulling at runtime; unqualified names resolve lexically through `§` sections; and the typechecker's overload resolution gained a definite-incompatibility pre-filter that turns the base-3 blowup on flat connective chains into something that finishes. It also carries a batch of soundness repairs — unification no longer builds cyclic substitutions or hangs, name-resolution failures no longer cascade into a wall of bogus diagnostics, deontic actions are checked against their declared party, directive ambiguity is a diagnostic rather than a crash, and `l4 format` (exactprint of the parsed AST) is the identity on source text for construct families where it previously scrambled or dropped code.

**Why**

Three distinct pressures. First, statutory transcription: verbatim legislative text produces very wide flat connective chains — `charities-jersey-2014` quotes Article 6(1) as a 27-operand disjunction — and the typechecker forked per overload candidate *before* examining arguments, so those files never finished checking (smucclaw/l4-ide#929). Second, drafting ergonomics: set-theoretic and mixfix operators were unusable without parentheses at every level, and isomorphic encodings of legislation had nowhere to put inert recital text. Third, correctness holes found by adversarial review and by the DMN export gate: `l4 format` silently corrupted regulative events (smucclaw/l4-ide#919) and mixfix call sites (smucclaw/l4-ide#918); multi-clause `DECIDE` groups were desugared into nested `CONSIDER`s *before* exhaustiveness analysis ran, so partial clause matrices were certified exhaustive (OPEN-6); a local binder shadowed a record selector at a projection label where it can never be meant (smucclaw/l4-ide#930); and the unifier could build a cyclic substitution and hang.

## What's in it

**Haskell — 14 modules under `jl4-core/src/L4`** (+5,228 / −557):

- **Lexer / surface syntax** (`Lexer.hs`, `Parser.hs`, `Syntax.hs`, `Mixfix.hs`, `Parser/MixfixRegistry.hs`)
  - `@infixl N` / `@infixr N` / `@infix N` lex as trivia (`TFixity`, `FixityDirection`) and ride the existing `@`-annotation rail; fixity lives in `MixfixInfo`, so it ships with the mixfix registry across `IMPORT` with no extra plumbing.
  - `•` bullet marker (`TBullet`) plus `bulletBlock` / `bulletItem` / `indentedGE` — a block of aligned `•` items desugars to the same `List` node as a `LIST` literal, and is valid in argument position so children nest under a constructor to any depth.
  - `@nonexhaustive` decorator token (`TNonexhaustive`), and the `TYPICALLY` keyword — `TypedName` / `OptionallyTypedName` each gain a default-value field (this is what the one-line `Names.hs` churn is).
  - Multi-clause pattern-matching `DECIDE`: `decidePatternMatch` / `desugarPatternClauses` / `matchClauses` / `matchOne` / `matchLast`, plus `PmMatrix` — the *source* clause matrix carried on the fused `Decide` so analysis can see it before desugaring.
  - `TStringLit` gains its raw source slice alongside the decoded text, so exactprint reproduces `"Österreich"` byte-for-byte instead of re-escaping through `showLitString`; `TIMEZONE IS` keywords are captured into the node anno; the `UNLESS` token stops being written to two nodes; lexer error spans stop collapsing to zero width.
  - The `RECORD` / `COMMIT` / `ATTEST` / `RECALL` / `OFFICIAL` AST constructors and their parsers (`Record`, `ReadCell`, `RecallMode`) — the syntax half of the ledger work whose evaluator lives in the **lang-eval-ledger** theme.
- **Annotation attachment** (`Parser/ResolveAnnotation.hs`, +672): a `HasFixity` rail that claims fixity annotations in document order and bounds them to adjacency (a stranded `@infixl` used to leak to a distant later definition, silently giving an operator a fixity nobody wrote), reporting every misplaced one as a parser warning; and the `HasRef` rail that attaches `@ref` annotations to the AST nodes that follow them, with its own misattachment warnings.
- **Typechecker** (`TypeCheck.hs` +2,822, `TypeCheck/{Types,Unify,Environment,Annotation}.hs`)
  - *Overload resolution*: `resolveTermFiltered` / `resolveTermFilteredIn` (in `TypeCheck/Types.hs`) restructure resolution into continuation-passing form with the ambiguity fallback appended lazily — `resolveTerm'` is byte-neutral by construction, defined as `resolveTermFiltered False p (const True) n pure`; `appCandidateFilter` / `candidateViableForArgs` / `approxArgHeads` approximate each argument's type head without recursion and drop candidates that definitely cannot apply. Every uncertainty degrades to keep-the-candidate; singletons are never filtered; ambiguity messages are still built from the unfiltered list.
  - *Fixity re-association*: `tryReassociateFixityChain`, a shunting-yard pre-pass at the `inferExpr` App site that rewrites a flat n-ary chain into the same nested binary tree parenthesized source produces. `normalizeChain` handles both parse shapes — operator-head (literal first operand) and operand-head (bare identifier first operand) — and an n-ary theft guard dry-runs the real mixfix matcher and declines whenever any registered pattern engages the shape.
  - *Variadic construction (route α)*: a record constructor with exactly one `LIST`-typed field applied to ≥2 arguments collects them into a synthesized `List` — `SET OF 1, 2, 3`. It is a per-call-site biased fallback that participates only when the entire nondeterministic resolution has zero successes, with `orElseKeepAll` added to `TypeCheck/Types.hs` to keep the curated ambiguity candidates alive.
  - *Exhaustiveness*: `constructorsInScopeFromEntityInfo` (the oracle — totality claims outside same-file top-level enums were vacuous without it), nabla-based missing-pattern expansion (`addConstraint`, `expandToPattern`, `maxUncoveredNablas`, `maxMissingSuggestions`), the `@nonexhaustive` decorator, `checkClauseMatrix` for multi-clause groups, and `hintSuspiciousBinders` / `exactlyOneEditApart` — the typo-binder hint that catches `WHEN nothing THEN …` silently binding everything.
  - *Scoping and resolution*: `withSectionStack` and `qualifiedAliases` for lexical `§` scoping (including types, constructors and selectors); `LocalsSpareSelectors` — at a projection-label occurrence the locals-only restriction now keeps selectors and constructors and lets type-directed resolution decide, while bare occurrences are unchanged; `suppressResolutionCascade`, so one unresolved name stops generating a cascade of downstream nonsense; colliding builtin environment keys merge rather than overwrite.
  - *Unification* (`TypeCheck/Unify.hs`): sibling rebinding, cyclic-substitution detection, type-synonym cycle quarantine, per-path fuel and AKA-aware cycle detection.
  - *Deontic and metadata checks*: `checkPartyActionAgreement`, `checkRegulativeActorAgreement` (a party may only perform an action whose performer is itself), `checkActionPattern`, and the `TYPICALLY` family (`checkTypically`, `isTypicallyLiteral`, `rejectTypicallyOnType` — a default requires an explicit type and is rejected on `TYPE` binders).
  - Directive ambiguity is reported as a diagnostic instead of crashing.
- **Desugar / Diagnostic** (`Desugar.hs`, `Diagnostic.hs`): computed-field desugaring and cycle detection (`detectComputedFieldCycles`, `detectTypeSynonymCycles`), and severity classification moved onto `TypeCheck.Types.severity`.

**Unit tests — 4 `jl4-core` specs** (+506): `UnifySpec` (new, 321 lines), `PatternMatchParserSpec` (new, 105), `EdgeCrashSpec` (new, 22), and `MixfixParserSpec` extended by 58 lines with `exactprint . parse ≡ id` round-trips for the issue-918 repro, chains, and trailing comments.

**Corpus — 88 fixtures** (57 under `jl4/examples/ok/`, 29 under `jl4/examples/not-ok/`, 2 `.cases.json`; 87 of them carry changes) **and 382 goldens** (93 `.golden`, 101 `.ep.golden`, 95 `.nlg.golden`, 95 `.schema.golden`). Grouped by what they pin:

| group | fixtures |
| --- | --- |
| fixity | `ok/fixity-{chain-basic,chain-right,cross-module-call,cross-module-def,identifier-operands,ignored-nonbinary,misplaced,nary-guard}.l4`; `not-ok/tc/fixity-{clash-mixed-assoc,conflict,conflict-viable-overload,malformed-priority,no-leak,nonassoc-chain,undeclared-chain}.l4` |
| pattern matching & exhaustiveness | `ok/pattern-matching*.l4` (incl. `-partial-{capped,matrix,multicolumn,nonexhaustive}`, `-decision-table`, `-nullary`, `-wildcard-shadow`), `ok/consider-*.l4`, `ok/{list,missing,pattern-nested,pattern-sibling}-*.l4`, `ok/{catchall-other,catchall-short,nonexhaustive-decorator*}.l4` |
| section scoping | `ok/section-{lexical-scoping,scoping-forward-ref,scoping-param-not-shadowed,scoping-projection-label}.l4`, `ok/cross-section-qualified{,-additive}.l4`; `not-ok/tc/section-scoping-{ambiguous,import-collision}.l4` |
| typo-binder hints | `ok/typo-binder-{after-coverage,case,distance-fp,last,qualified}.l4` |
| unification | `ok/unify-swapped-pair-args.l4`; `not-ok/tc/{unify-sibling-rebind,type-synonym-cycle,same-name-type-mismatch}.l4` |
| deontic / value-actor | `not-ok/tc/{deontic-action-type-mismatch,deontic-party-action-agreement,value-actor-agreement,value-actor-duplex,value-actor-procure}.l4` |
| TYPICALLY | `not-ok/tc/typically-{non-literal,on-type,requires-type,type-mismatch}.l4` |
| ambiguity & cascade | `not-ok/tc/{assert-directive-ambiguity,timezone-directive-ambiguity,timezone-mixed-ambiguity,resolution-cascade,set-equals-ambiguous,set-and-unoverloaded,variadic-construction-limits}.l4` |
| syntax | `ok/bullet-list-dot.l4`, `ok/enum-named-number.l4`, `ok/event-{exhaustive,type-resolves}.l4`, `ok/empty.l4` |

Twelve warning-only fixtures moved from `not-ok/tc/` to `ok/` in the process: on the line they were written, `SuccessfulTypeCheck` partitioned on `(== SInfo)` so warnings were fatal; here it partitions on `(/= SError)`, so they belong in `ok/` and gain the exactprint-identity check for free.

## Evidence

Quoted from the source PRs.

**Overload pre-filter / #929** (#169) — measured before (`34de2005`) → after:

| test | before | after |
| --- | --- | --- |
| flat `TRUE AND …` chain, N=12 | 2.76 s | 0.38 s |
| N=16 | timeout (>120 s) | 0.41 s |
| N=512 | — | 0.52 s (flat) |
| user-declared 2nd `__AND__` overload, N=16 | timeout | 0.04 s |
| charities part-3 (27-operand Art. 6(1) disjunction) | never finishes (~10⁷ s extrapolated) | 0.72–0.81 s |
| charities part-7 | ~10 h | 1.29–1.44 s |

"Perf figures were reproduced independently by the adversarial reviewer on the same machine." Soundness oracle: "tree-wide sweep of every `.actual` the suites produce (1,253 files) — zero divergences", plus "21 targeted probes through patched vs. stock binaries, byte-comparing full output"; one divergence found (diagnostics-only) and fixed, "all 21 probes now byte-identical". Honest residual quoted in that PR: "**No measurable jl4-test suite-level speedup** (181–188 s vs the 176 s reference on a tree with 95 more examples)". The companion prelude change (#168, in the **lang-sets** / **lang-imports-stdlib** themes) reported "the full golden suite runs ~28 % faster" and "two users of AND/OR-on-sets in the entire tree".

**Fixity** (#128) — "11 new fixtures / 44 goldens"; suites "jl4-test 1221/0, jl4-core-test 208/0, l4-cli-test 55/0". A "6-dimension multi-agent review (3 refuters per finding) surfaced **8 confirmed findings, all fixed**". The operand-head follow-up (#131) reported "jl4-test 1225/0, jl4-core-test 208/0" and noted that "**every golden fixture used literal operands**, so this whole class — chains over named values, and the prelude's own set operators — was untested".

**Bullets** (#109) — "9 new `BulletParserSpec` cases"; "full golden suite green (1116 examples)". The `indentedGE` `>=` corner case: "A corpus sweep found **0 of 571 `.l4` files** hit this today, so the behavior is pinned with a regression test".

**Variadic construction** (#123) — "Suite: **1128 examples, 0 failures**"; the first cut fired per resolution candidate and adversarial review "caught it converting four classes of currently-working programs into ambiguity errors".

**Exactprint fidelity** (#124, #125, #130) — #125: "jl4-core 169/0, jl4 goldens 1120/0". #130: the new `FormatFidelitySpec` has "**10/11 cases fail against the pre-fix parser**"; whole-corpus sweep "**0/243** ok/legal/libraries files non-identity under `l4 format`"; "23 stale `.ep.golden` files were regenerated to byte-identity with their sources"; suites "jl4-core 219/0, jl4 goldens 1412/0".

**Exhaustiveness oracle** (#182) — landed by cherry-pick after measuring that `main` does not carry it (`git grep constructorsInScopeFromEntityInfo`: empty on `origin/main`, ×6 at `8a8b46bc`); suites "jl4-test 2062/0, jl4-core-test 269/0, jl4-service-test 311/0, jl4-lsp-test 10/0, l4-cli-test 123/0".

**Clause-matrix exhaustiveness / OPEN-6** (#185) — "jl4-test 2129 examples, 0 failures; jl4-core-test 269/0; jl4-lsp-test 10/0; jl4-service-test 311/0; jl4-mlir-test 19/0; l4-cli-test 125/0" with KIE and Camunda checks required. That PR also records two **advisory** findings verbatim, which travel with this code and are not fixed here: (1) a partial group whose missing-row count exceeds `maxMissingSuggestions` (64) gets no warning *and* no D-PARTIAL, so the DMN gate certifies it safe; (2) the n=1 fused-group case still evades all three L1 channels, so the spec's "an incomplete clause group is now refused like any other partial match" is an overclaim for n=1.

**Projection-label shadowing / #930** (#211) — "whole-tree `l4 run` sweep, base binary vs branch binary, all 725 `.l4` files present on both sides, full stdout+stderr diffed. Result: **one file changes**, `jl4/experiments/patterns_and_idioms.l4`, red → green." And: "`l4 check` wall time is unchanged (±0.02 s) on the five collision-heaviest files, so the extra candidates do not reopen #929." The recorded over-reach: a local that *is* a function of the selector's exact type at a label used to resolve definitely and is now ambiguous — accepted, and recorded in the spec and haddock.

**Merge protection** (#189) — after merging `main` into `unstable`, the presence of this theme's symbols in the merged tree was counted rather than assumed: `constructorsInScopeFromEntityInfo` ×7, `checkClauseMatrix` ×10, `PmMatrix` ×5 in `TypeCheck.hs`; `TNonexhaustive` ×3 in `Lexer.hs`.

## Independence

**Siblings depend on this; this depends on very little.** These modules are the front end, so most other themes compile against types defined here:

- `Syntax.hs` defines the `Record` / `ReadCell` / `RecallMode` constructors that **lang-eval-ledger**'s `EvaluateLazy` and `Evaluate/Ledger.hs` pattern-match on, and the `PmMatrix` / `Fixity` types.
- `TypeCheck/Types.hs` defines the checker warnings (`PatternClausesMissing`, `PatternMatchesMissing`) that **dmn-export**'s `L4/Dmn/Analysis.hs` keys D-PARTIAL off.
- `Lexer.hs` defines `FixityDirection` and `TNonexhaustive`, which `L4/Export.hs` (**service-cli**) reads via `isNonexhaustiveDecide`.

Landing this theme *without* those siblings gives a compiler that parses, resolves and typechecks the new syntax; landing those siblings without this one does not build at all.

What it does need, honestly:

1. **The goldens here are whole-pipeline output.** A `.golden` captures diagnostics *and* `#EVAL` / `#TRACE` results; `.nlg.golden` and `.schema.golden` come from the NLG and schema exporters. So these files encode behaviour owned by **lang-eval-ledger** (evaluation), **lang-printer** (`L4/Print.hs`) and the exporters. If a sibling changes an evaluated answer or a rendered message, some of these goldens move. This is a real coupling, not a formality.
2. **The harness that reads them is not in this manifest.** `jl4/tests/Main.hs` — which hosts `exactprint identity` and the `prettyLayout round-trip` property — and `jl4-core/jl4-core.cabal` appear in no theme's file list. The three new unit specs (`UnifySpec`, `PatternMatchParserSpec`, `EdgeCrashSpec`) are registered in `jl4-core.cabal` on `unstable` and not on `main`, so they will not run until that cabal edit rides along with whichever PR carries it.
3. **`@ref` attachment is split.** The `HasRef` machinery is in `Parser/ResolveAnnotation.hs` here, but its unit spec (`RefAnnotationSpec.hs`) and fixture (`ok/ref-annotation.l4`) are assigned to **lang-printer**.
4. `TypeCheck.hs` imports `L4.Print (prettyLayout, quotedName)` and `L4.Export`; both symbols already exist on `main`, so no forward dependency on **lang-printer** or **service-cli** is created by the import itself.
5. The set-operator fixtures that exercise `@infixl` on `UNION` / `INTERSECT` live in **lang-sets**, and the prelude declarations they need live in **lang-imports-stdlib**. The fixity *mechanism* and its own fixtures are here and are self-sufficient; the prelude-level application is not.

## Risk if rejected

Nothing else in the split builds: every other Haskell theme references types and constructors defined in these 14 modules, so dropping this PR while its siblings land turns the tree red rather than merely reducing functionality. Even considered alone, the loss is the whole language increment — fixity declarations, bullets, `TYPICALLY`, clause-matrix exhaustiveness, section scoping, the unification and cascade repairs, the exactprint identity fixes, and the #929 pre-filter that is the difference between a statutory corpus checking in under a second and not checking at all.


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

Unstable PRs folded into this one:

- #89 — `mengwong/temporal-rule-version` (rule-version temporal axis; the `TypedName` shape it touches)
- #109 — `mengwong/bullet-list-syntax` (`•` bullet syntax)
- #122 — `mengwong/set-operators-phase1` (set operators, prelude side; the ambiguity fixtures here)
- #123 — `mengwong/set-operators-route-alpha` (route-α variadic construction)
- #124 — `mengwong/fix-mixfix-format` (exact-print mixfix call sites in source order, #918)
- #125 — `mengwong/fix-event-exactprint` (un-swap `Event` exactprint branches, #919)
- #128 — `mengwong/fixity-declarations` (`@infixl` / `@infixr` / `@infix`)
- #130 — `mengwong/format-fidelity` (TIMEZONE / UNLESS / unicode / multi-clause DECIDE identity)
- #131 — `mengwong/fixity-operand-head-fix` (operand-head chain re-association)
- #133 — `mengwong/set-operators-phase3d` (prelude fixity for set operators)
- #134 — `docs/library-resolution-shadow` (resolution-order goldens)
- #162 — `feat/regcf-projections` (`a9caf2f6`; section-qualification of types, constructors and selectors rode with it)
- #168 — `mengwong/set-andor-unoverload` (`not-ok/tc/set-and-unoverloaded.l4`)
- #169 — `mengwong/tc-overload-memo` (overload pre-filter + lazy ambiguity fallback, #929)
- #172 — `mengwong/regcf-rule-version`
- #182 — `mengwong/bkm-phase05-oracle` (exhaustiveness oracle, `@nonexhaustive`)
- #183 — `mengwong/bkm-phase4-unlift` (DMN Phase 4; checker-side hooks)
- #184 — `mengwong/maybe-minmax-nothing` (`set-equals-ambiguous` line-number golden)
- #185 — `mengwong/open6-clause-matrix` (clause-matrix exhaustiveness, OPEN-6)
- #188 — `mengwong/dmn-phase5-bkm` (its own PR body records the `TypeCheck.hs` touch as "a comment only")
- #189 — `merge/main-into-unstable` (revert protection for the oracle)
- #190 — `mengwong/mlir-parity-land`
- #211 — `mengwong/eval-pin-and-shadowing` (FIX A′ projection-label shadowing, #930)
- #214 — `mengwong/printer-batch-and-gensym` (`prettyLayout` round-trip; goldens)
