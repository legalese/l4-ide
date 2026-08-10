# feat(stdlib): hierarchy + negation-as-failure libraries, YMD dates, the SET type, and diamond-safe imports

## What this adds

The L4 standard library grows two new modules and three new capabilities, and the import resolver stops silently degrading one shape of import graph. `hierarchy.l4` gives nested legal text — recitals, outlines, `1.A.i.a` paragraph trees — a rose-tree datatype with a renderer that derives numbering markers from depth and sibling position, so an isomorphic encoding can carry inert structure without pretending it is a `DECIDE`. `negation-as-failure.l4` names the closed-world/open-world defaulting combinators (`holds`, `naf`, `presumed`) over `MAYBE BOOLEAN`. `daydate.l4` gains `YMD year month day` — an ISO-ordered, bounds-checking date constructor that *refuses* out-of-range components where `Date d m y` silently rolls them — plus a `Calendar Arithmetic` section (`add months`, `add years`) with day-clamping, relocated out of `actus-schedule.l4`. The prelude gains a `SET OF a` type with the set-theoretic drafting vocabulary. On the Haskell side, `L4.Import.Resolution` now hands a cached module's *resolved record* to later siblings instead of just its name, so both arms of a diamond import see the shared dependency's environment.

## Why

- **Inert nested text had no home.** Encoding legislation isomorphically routinely turns up prose that gates no decision but must be carried for line-by-line fidelity. `hierarchy.l4` is where that lives (PR #109).
- **The date footgun was measured, not theorised.** `Date 7 28 2026` — a day/month transposition — silently rolls month 28 forward to `2028-04-07` with no error. `YMD` puts the arguments in the order ISO 8601 writes them *and* round-trips the components back out of the candidate date, refusing anything that did not survive (PR #174, tightened in the bounds-check follow-up).
- **`add months` was in the wrong library.** It is not an ACTUS idea — the same day-clamp is Excel's `EDATE` and FEEL's `date + duration("P1M")`. Schedule generation was merely the first caller. Leaving both definitions in place would have been a genuine `DATE × NUMBER -> DATE` overload ambiguity, so it moved rather than being copied.
- **Diamond imports were degrading the second sibling** (issue smucclaw/l4-ide#904). In `A -> {B, C} -> D`, once `B` resolved `D`, the old name-set cache made `C` re-check against an *empty* dependency environment. `C`'s types and entities were silently degraded, and `A` then consumed them — the degradation never surfaced, because only the main module's errors reach `tcdErrors`.
- **Name-resolution failures cascaded into bogus diagnostics** (issue smucclaw/l4-ide#920). Every `OutOfScope` sentinel carried a deliberately unregistered `Unique`, which tripped `MissingEntityInfo` — rendered as "This is an error in this system and should be reported as a bug" — and then a vacuous `TypeMismatch` reading "must match … namely Verdict but is here of type Verdict". `ResolutionCascadeSpec` pins both halves of the fix and the control cases proving genuine type errors still fire.
- **The `AND`/`OR`-on-sets overloads had to go** (issue smucclaw/l4-ide#929): a second candidate for a boolean connective makes typechecking exponential in flat chains. Term-level union is now spelled `UNION`.
- **`IMPORT` resolution order was undocumented where library authors read.** A machine-global `~/.local/share/jl4/libraries/` symlink could shadow the stdlib the binary was built with. The order, and the Template Haskell embed-staleness gotcha behind "my prelude edit didn't take effect", are now written into `jl4-core/libraries/README.md` next to the files themselves.

## What's in it

30 files: 6 library files (2 new `.l4` modules, 3 modified, 1 README), 3 Haskell modules (1 source, 2 test), 2 new example `.l4` files, and 19 goldens.

### New library modules

- **`jl4-core/libraries/hierarchy.l4`** (354 lines, new) — `DECLARE RoseTree OF a HAS value, children`, generic operations (`count nodes`, `depth`, `flatten`, `map tree`), the natural-reading constructors `item` / `labeled` / `numbered` / `restartAt` (with `item` arity-overloaded from one to four children plus an explicit-`LIST` fallback for wider nodes), and a `render outline` that assigns a marker per depth from a scheme (`Decimal, UpperAlpha, LowerRoman, LowerAlpha` by default). Handles the irregular sequences legal drafting actually produces — an inserted "2b", an explicit restart — without disturbing neighbouring numbering. Carries 14 `#ASSERT`s of its own; its golden shows the rendered outputs verbatim (`"b.i	fair wear and tear excepted"`, `"2b	Late payment"`, and the restart cases).
- **`jl4-core/libraries/negation-as-failure.l4`** (35 lines, new) — `holds` (= `fromMaybe FALSE`, the closed-world assumption), `naf` (succeeds when `p` cannot be proven true — both `JUST FALSE` and `NOTHING`, mirroring Prolog's `\+` under SLDNF), and `presumed` (= `fromMaybe TRUE`, the open-world dual). Three definitions, each with an `@nlg` gloss; the point is that flipping the default `FALSE ↔ TRUE` *is* the closed-world/open-world switch, and naming it makes the choice reviewable.

### Existing libraries

- **`prelude.l4`** (+168 lines against `main`) — the `§§ Sets` section: `DECLARE SET OF a HAS elements IS A LIST OF a`, plus `emptySet` / `setFromList` / `setToList` / `setSize`, `` `is in` `` / `` `is subset of` `` / `` `set equals` ``, and `UNION` / `INTERSECT` / `` `LESS` `` / `WITHOUT` with `@infixl 6` on `UNION`/`WITHOUT` and `@infixl 7` on `INTERSECT` so bare chains re-associate the way `PLUS`/`TIMES` do. Overloads for `__PLUS__`, `__MINUS__` and `__EQUALS__`; the `__AND__`/`__OR__` overloads are deliberately **absent**, with the removal and its reason recorded inline at the site. Three `@nonexhaustive` annotations are added (`at`, `maximum`, `minimum`) — those `CONSIDER`s have no `WHEN EMPTY` arm and the annotation is how the exhaustiveness oracle is told so.
  Note that the `MAYBE NUMBER` extremum bodies are *not* part of this diff: `main` already carries the corrected pattern-matching form (`88bdf75d`), and PR #184 was the port of that fix onto `unstable`. Relative to `main`, only the annotations and the Sets section move.
- **`daydate.l4`** (+83) — the `YMD` binding with its `ASSUME `YMD refused an out-of-range month or day`` bottom, and the new `§§ Calendar Arithmetic` section holding `add months` (day-clamped) and `add years`.
- **`actus-schedule.l4`** (+7 / −17) — the `add months` definition is deleted; a comment in its place says where it went and why the definition could not simply be left behind. The module already `IMPORT`s `daydate`, so callers resolve unchanged.
- **`README.md`** (+85) — a resolution-order section (`JL4_LIBRARY_PATH` → project root → importer-relative → embedded → XDG → VSCode bundle, first hit wins, with the rationale for why project-scoped tiers outrank the embed and machine-global tiers rank below it); an "Editing these files? Read this first" block on the TH embed-staleness gotcha; the `DATE`/`Date` breaking-change section demoted from "Upcoming" to "proposed, not landed"; and a dated correction of a paragraph that had attributed `Date`'s rolling behaviour to `YMD`.

### Import resolution

- **`jl4-core/src/L4/Import/Resolution.hs`** — `resolveImports`' `resolved` parameter changes from `Set Text` to `Map Text ResolvedImport`, and the already-resolved branch now prepends the cached record instead of dropping it. The transitive cache is keyed to records too, so a subtree's resolutions are inherited by later siblings. `combineResolvedImports` additionally threads `constBodies` and `sectionPaths` through the accumulated `CheckState`, and the hand-rolled `MkCheckEnv` merge is replaced by the shared `unionImportedCheckEnv` — one merge site instead of two that had drifted.
- **`jl4-core/test/ImportResolutionSpec.hs`** (+33) — a diamond fixture (`A -> {left, right} -> bottom`) that asserts *every resolved import* type-checked clean, not merely that the main module succeeded. That assertion is the one the old behaviour failed.
- **`jl4-core/test/ResolutionCascadeSpec.hs`** (252 lines, new) — the #920 guard: asserts the diagnostics for an ambiguous or undefined name contain neither `MissingEntityInfo` nor the vacuous self-mismatch, and that genuine type errors are still reported.

### Examples and goldens

- **`jl4/examples/ok/prelude-min-max.l4`** + 4 goldens — 40 `#ASSERT`s and 16 `#EVAL`s over all four extremum functions across *both* overloads. Inputs are unsorted with the extremum in the interior, so returning the head, the last element or the seed cannot pass by accident; `maximum1`/`minimum1` are covered seed-loses, seed-wins and empty-list. A final section pins `NOTHING`-in-first/interior/last position plus the empty and all-`NOTHING` lists, with both `#EVAL` and `#ASSERT` — the `#EVAL`s keep any future change to `MAYBE` ordering visible as a golden diff, the `#ASSERT`s make a regression fail the suite outright.
- **`jl4/examples/ok/ymd-constructor.l4`** + 4 goldens — 21 `#EVAL`s: `YMD` agrees with `Date` on valid input, the `DATE_SERIAL` round-trip, the `AKA` alias, the transposition behaviour recorded honestly, and `YMD` composed with `EVAL UNDER RULES EFFECTIVE AT`.
- **Library goldens** — first-time goldens for `hierarchy` and `negation-as-failure` (4 each), and refreshed `.ep.golden` exactprints for `prelude`, `daydate` and `actus-schedule`. The `.ep.golden` files are byte-identical to their sources by construction; they move whenever the source does.

## Evidence

All figures below are quoted from the source PRs as they reported them; they are snapshots taken at different points on `unstable`, so the suite totals grow across the list rather than disagreeing.

- **PR #109** (hierarchy): "`jl4-test`: full golden suite green (1116 examples), including new `bullet-list-dot` and `hierarchy` golden baselines."
- **PR #122** (SET type): "**1136 examples, 0 failures** (includes 17 new goldens + refreshed prelude exactprint golden)."
- **PR #133** (set-operator fixity): "Full suite: **1481 examples, 0 failures.**"
- **PR #140** (the `MAYBE` extremum defect, since superseded on this line): a like-for-like baseline table — `origin/unstable` with the branch stashed, "**1481 examples, 0 failures, PASS**"; the branch, "**1486 examples, 0 failures, PASS**" — with the note "The +5 is exactly this PR's one new fixture: four golden tests … plus its `exactprint identity` case." The before/after was measured per directive: `maximum (LIST (JUST 3), (JUST 1), (JUST 4), (JUST 1), (JUST 5))` gave `JUST OF 1` and should give `JUST OF 5`.
- **PR #168** (removing the `AND`/`OR` set overloads): "every file in that corpus checks in **under a second** (part-3: 0.51 s; part-7: 0.83 s, previously 10 h+), and the full golden suite runs ~28 % faster." Blast radius: "two users of AND/OR-on-sets in the entire tree". Suites: "jl4-test 1830/0, jl4-core-test 269/0, jl4-service-test 311/0, l4-cli-test 96/0".
- **PR #174** (`YMD`): "`jl4-test`: 1854 examples, 0 failures (1 exactprint golden re-blessed for the library edit; 4 first-time goldens for the new example)." Adversarial probes covered "out-of-range months (0, -1, 13, 28), leap day 2024/2023, shadowing, and clamp-parity with `Date` on identical inputs."
- **PR #184** (the `NOTHING`-poisoning port): `jl4-test` 2062/0, `jl4-core-test` 269/0, `jl4-service-test` 311/0, `jl4-lsp-test` 10/0, `l4-cli-test` 123/0 — the last "with `L4_DMN_ENGINE_CHECK=1 KIE_CHECK_REQUIRED=1 CAMUNDA_CHECK_REQUIRED=1`; the Drools/KIE 8.44.0.Final and Camunda 8.7.6 checks genuinely executed rather than taking a skip path."
- **PR #134** (library resolution order, documented here in the README): `jl4-lsp-test` 10/10, `l4-cli-test` 60/60, `jl4-test` 1471/1471, `jl4-core-test` 219/219, `jl4-service-test` 293/293, `jl4-mlir-test` 19/19.
- **The calendar-arithmetic clamp** is justified in the `daydate.l4` comment by a measurement recorded at the site: "MEASURED on 2026-08-05 against Drools/KIE 8.44.0.Final and Camunda 8.7.6 (zeebe-dmn) — what FEEL's `date + duration("P1Y")` does on both DMN engines, over months and years alike, in all six probed cases."
- **The README correction** carries its own measurement: "`#EVAL YMD 1990 15 3` → `` `YMD refused an out-of-range month or day` ``, while `#EVAL Date 3 15 1990` → `DATE OF 3, 3, 1991`."
- **PR #196** reported that `YMD` FEEL-literal lowering took the British Nationality Act corpus from whole-file refusal to "1075/1075 decision(s)" on both KIE 8.44.0.Final and Camunda 8.7.6. That measurement belongs to the **dmn-export** theme, which carries the lowering code; it is quoted here only because `YMD` — added by this PR — is what it lowers.

Counts I measured directly against this tree while assembling the PR: `hierarchy.l4` 354 lines with 14 `#ASSERT`s; `negation-as-failure.l4` 35 lines; `prelude-min-max.l4` 40 `#ASSERT` / 16 `#EVAL`; `ymd-constructor.l4` 21 `#EVAL` / 0 `#ASSERT`; `ResolutionCascadeSpec.hs` 252 lines.

## Independence

**This PR is not standalone. It needs `lang-syntax-typecheck` to compile and to check.** Concretely:

- `prelude.l4` carries three `@nonexhaustive` annotations and three `@infixl` declarations, and the whole diff against `main` is `+168 / −0` — pure addition. `origin/main` has **no** occurrence of `nonexhaustive` anywhere under `jl4-core/src/L4/`, and **no** `infixl` in `Lexer.hs` or `Parser/ResolveAnnotation.hs`. Both annotation families — the `CONSIDER` exhaustiveness oracle and the fixity mechanism — are in `lang-syntax-typecheck`. Without it, this prelude does not check.
- `Import/Resolution.hs` calls `TypeCheck.unionImportedCheckEnv` and populates `constBodies` and `sectionPaths`. All three live in `TypeCheck.hs` / `TypeCheck/Types.hs`, in `lang-syntax-typecheck`. This is a compile-time dependency, not a behavioural one.
- `ResolutionCascadeSpec.hs` asserts the *absence* of `MissingEntityInfo` and of the vacuous self-mismatch. The fix it guards is in `TypeCheck.hs`, in `lang-syntax-typecheck`. Landed alone against `main`, this spec fails.
- `ymd-constructor.l4` opens with `TIMEZONE IS "Etc/UTC"`, and its `.ep.golden` is a byte-identical exactprint. The `TIMEZONE`-exactprint fix (PR #130) is in `Parser.hs`, in `lang-syntax-typecheck`. Without it that golden cannot hold.
- **Build plumbing is missing from every manifest.** `ResolutionCascadeSpec` is a new test module and must be listed in `jl4-core/jl4-core.cabal`'s `other-modules` (`hspec-discover` finds it, but `-Wall -Werror` implies `-Wmissing-home-modules`). `jl4-core.cabal` and `jl4/tests/Main.hs` both differ between `main` and `unstable` and appear in **none** of the 25 theme file lists. Whoever assembles the merge needs to route them somewhere; this PR cannot land green without the cabal line.

**Siblings that depend on this one, not the other way round:**

- `lang-sets` owns the four `set-operators*.l4` examples and their goldens. The `SET` type and every operator they exercise are defined in *this* PR's `prelude.l4`. Land `lang-sets` without this and those examples do not resolve.
- `lang-syntax-typecheck` owns `jl4/examples/not-ok/tc/tests/set-equals-ambiguous.golden`, which quotes `` `__EQUALS__` (defined at prelude.l4:1310:1-13) `` — a **line number inside this PR's `prelude.l4`**. Any change to the number of lines this PR adds above line 1310 rebleeds that golden. It also owns `jl4/examples/ok/bullet-list-dot.l4`, which `IMPORT`s `hierarchy`.
- `dmn-export` needs `YMD` to exist before `Lower.hs` can fold it; `corpus-legal-new` (BNA) and `corpus-regcf` both call `YMD`, and `regcf.l4` calls `add years`. `experiments` owns `negation-as-failure-examples.l4`.
- `docs` owns `doc/reference/libraries/resolution.md` and `specs/todo/LIBRARY-RESOLUTION-SHADOW-SPEC.md`, which this README links to; `lsp` owns `jl4-lsp/src/LSP/L4/Rules.hs`, which implements the resolution order this README documents. The README is accurate prose either way, but its cross-links dangle and its documented order is aspirational until `lsp` lands.

**What this PR does *not* need:** nothing from `dmn-export`, `bpmn-export`, `ladder-viz`, `service-cli`, `go-pipeline`, or any corpus theme. The two new library modules are self-contained apart from `IMPORT prelude`.

## Risk if rejected

Drop this and the stdlib itself is missing while everything built on it lands: `lang-sets`' examples have no `SET` type, `dmn-export`'s FEEL date-literal fold has no `YMD` to fold, the BNA and Reg CF corpora do not resolve, and `regcf.l4`'s anniversary arithmetic has no `add years`. The two compiler-side fixes are also lost — diamond imports quietly resume type-checking their second sibling against an empty environment (smucclaw/l4-ide#904, a silent wrong answer, not a crash), and the #920 diagnostic cascade resumes telling users to file a compiler bug when they have merely misspelled a name.

## Provenance

Unstable PRs folded into this one:

- #109 — `'•'` bullet syntax + hierarchy library for isomorphic recitals/outlines *(the `hierarchy.l4` half; the lexer/parser half is in `lang-syntax-typecheck`)*
- #122 — `feat(prelude): SET OF a` — set-theoretic operators (SET-OPERATORS-SPEC Phases 1+2)
- #124 — `fix(parser): exact-print mixfix call sites in source order (#918)` *(the refreshed library `.ep.golden`s only; the parser fix is in `lang-syntax-typecheck`)*
- #130 — `fix(format): l4 format identity` for TIMEZONE/UNLESS/unicode/multi-clause DECIDE + corpus invariant *(the library `.ep.golden` regenerations)*
- #133 — `feat(prelude): fixity for set operators` — bare UNION/INTERSECT chains (Phase 3d)
- #134 — Library resolution: embedded stdlib outranks ambient XDG/bundle copies (B′) *(the `libraries/README.md` documentation only)*
- #140 — `fix(prelude): maximum over MAYBE NUMBER returned the minimum` *(superseded on the body by #184; the `prelude-min-max.l4` fixture is its lasting contribution)*
- #168 — `feat(prelude): remove the AND/OR set overloads — write UNION explicitly`
- #174 — `feat(daydate): YMD — the ISO-ordered date constructor`
- #182 — Phase 0.5: land the exhaustiveness oracle on unstable *(the `@nonexhaustive` annotations on `prelude.l4`)*
- #184 — `prelude: NOTHING no longer poisons MAYBE min/max` (port of main's `88bdf75d`)
- #196 — `feat(dmn): FEEL date-literal lowering for YMD` *(the `libraries/README.md` correction only)*
- #224 — The explainer stage, a BPMN renderer, … and the de novo Reg CF run *(the `add months` move from `actus-schedule.l4` into `daydate.l4`, and `add years`)*

Three further merged PRs contributed files carried here but are not in this theme's manifest — noted so a reviewer tracing `git log` is not surprised:

- #34 — `negation-as-failure.l4` (the library module itself)
- #102 — `fix(imports): thread resolved records so diamond siblings inherit env` (`Import/Resolution.hs`, `ImportResolutionSpec.hs`)
- #152 — `fix(typecheck): stop name-resolution failures cascading into bogus diagnostics` (`ResolutionCascadeSpec.hs`)
