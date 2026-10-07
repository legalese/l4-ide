# Multi-clause pattern-matching DECIDE (as built)

As built on unstable at 73a953821. Source spec: specs/done/PATTERN-MATCHING-SPEC.md (on main at `specs/todo/PATTERN-MATCHING-SPEC.md`). Differences from the source spec: `_` and `_name` wildcards are lexer errors; inside a clause group a variable whose name differs from its `GIVEN` is accepted and binds, where the spec requires an error; the Phase 1 redundancy and overlap warnings were never built, except that the clauses after one that matches every input are reported as never used (in this PR, from #569); the Phase 1 exhaustiveness warning is in this PR, adapted from #185 (see below), and does not cover groups that match literals, lists or types declared in another module.

This PR carries PR #49 (branch `tier1/pattern-matching-p1`, carried in batch #77 as `c2ea232c5a`, commits `759868632` and `f030c28c1`).
Its 20-line edit to the spec's Phase 1 notes is not carried here.

## What it does

Several `DECIDE` (or `MEANS`) clauses with the same head, written one after another under a single `GIVEN`/`GIVETH` signature, may put literal or constructor patterns in argument positions:

```l4
GIVEN n IS A NUMBER
GIVETH A NUMBER
DECIDE factorial 0 IS 1
DECIDE factorial n IS n * factorial (n - 1)
```

The parser fuses the group into one `Decide` whose body is a chain of `CONSIDER … WHEN` tests.
Clauses are tried top to bottom and the first match wins; if none matches, evaluation stops with a non-exhaustive-patterns error.

## Where it lives

All in `jl4-core/src/L4/Parser.hs @ 73a953821`:

- `topdecl` tries the group parser first: `try (decidePatternMatch sig) <|> decide sig` (`:653`).
- `PMClause`, a parser-internal clause record that never enters the AST (`:957-969`).
- `decidePatternMatch`, grouping and the commit test (`:979-1031`); `pmClause`, one clause (`:1037-1058`).
- `isDistinguishablePat` (`:1066-1072`) and `givenTermNames` (`:1076-1081`).
- `desugarPatternClauses`, which builds the fused `MkDecide` (`:1088-1137`).
- `matchClauses` (`:1165-1189`), `fallthroughName` (`:1192-1194`), `clausesSrcAnno` (`:1205-1208`), `bindFallthrough` (`:1215-1223`).
- `matchOne` (`:1227-1243`), `matchLast` (`:1247-1254`), `patAlwaysMatchesAs` (`:1260-1263`).
  The runtime error is `NonExhaustivePatterns` (`jl4-core/src/L4/EvaluateLazy/Exceptions.hs:71`), thrown at `EvaluateLazy/Machine.hs:4041`.

## Behaviour and rules (read in code on unstable)

Grouping.
The first clause sets the column, the head name and the arity.
Further clauses must start at exactly that column (`withIndent EQ`) and have the same raw head name and the same number of argument patterns.
Anything else ends the group, including an intervening `GIVEN`, so type-overloaded definitions, each with its own signature, are never merged.

Clause forms.
`DECIDE head pat… [AKA …] IS|IF body`, or `head pat… [AKA …] MEANS body`.
Argument patterns are atomic, so an applied constructor needs parentheses: `(JUST v)`, `(x FOLLOWED BY xs)`.
The first `AKA` found in any clause is used for the fused head.

When the group is taken (`guard`, `:1013`).
It is taken when some clause has a distinguishable pattern: a literal, a cons, an `EXACTLY` expression, or a constructor with arguments.
It is also taken when the group has at least two clauses, every argument is a bare name, and in some column the bare names differ (`TRUE`/`FALSE`, enum constants).
Otherwise the parser backtracks and the ordinary single-clause `decide` parser runs, so a lone bare-name clause is unchanged.

Scrutinees.
If the signature's term parameters (`GIVEN` names that are not `IS A TYPE`) number exactly the arity, and the arity is positive, they are the scrutinees and the fused head takes no parameters.
Otherwise the head gets synthetic parameters `_pm_arg_1 … _pm_arg_n`, which become the scrutinees.

Desugaring.
For each column, a bare name equal to the scrutinee's name matches without a test and binds nothing new.
Any other pattern becomes `CONSIDER <scrutinee> WHEN <pattern> …`.
A bare name that is not the scrutinee's name is therefore a `WHEN` pattern, and the checker decides whether it is a nullary constructor or a fresh variable: in `DECIDE premium other IS 0`, `other` binds the argument.
Every non-final clause gets `OTHERWISE <fall-through>`; the final clause gets no `OTHERWISE`, so a value no clause matches raises `NonExhaustivePatterns` at run time.
The fall-through (the desugaring of the remaining clauses) is bound once per clause boundary to a nullary local `__pm_fallthrough_<k>` with `LET … IN`, and referenced by name, so the tree is linear in clauses times columns (the first version inlined it and grew multiplicatively).
Each such local `Decide` gets a synthetic source range spanning the remaining clause bodies, because the checker keys function signatures by `Decide` range.
A clause in which every column matches without a test is total: the clauses after it are neither bound nor desugared (`:1180-1184`).

## Diagnostics

At run time, a value no clause matches: "The value … reached a CONSIDER that has no branch for it. Add a WHEN branch for this case, or a catch-all OTHERWISE branch." (`Exceptions.hs:121-126`; the wording is later than #49).
#49 itself adds no diagnostic.
Because the pattern parser is tried first, a malformed `DECIDE` head now lists pattern tokens among the expected ones: `expecting (, AKA, EXACTLY, Float Literal, IF, IS, Numeric Literal, OF, String Literal, identifier, or space token` (`jl4/examples/not-ok/tc/tests/parse-error4.golden:14`).

## Tests and fixtures that pin it

- `jl4-core/test/PatternMatchParserSpec.hs` (in `jl4-core-test`), five cases: literal and variable clauses group into one `CONSIDER`-bodied `Decide`; `EMPTY`/`FOLLOWED BY` clauses group; a single literal clause desugars; a single variable clause is left alone; two different heads stay two `Decide`s.
- `jl4/examples/ok/pattern-matching.l4`: factorial, fib, list length, `from maybe`, a two-column decision table, and nested `(JUST (JUST k))`.
- `jl4/examples/ok/pattern-matching-nullary.l4`: `TRUE`/`FALSE` and enum-constant groups, one with a catch-all variable.
- `jl4/examples/ok/pattern-matching-decision-table.l4`.
- Each fixture has its four goldens under `jl4/examples/ok/tests/`.

## Limits and known defects on unstable (verified)

Probed 2026-09-30 with the installed `l4` (built 2026-09-30; the reference checkout is at `f9a504b77`, whose `jl4-core/` and `jl4/` trees equal unstable's, but the binary's own commit is unproven).

- Wildcards: `DECIDE f _ IS 0` and `DECIDE f _unused IS 0` are lexer errors ("unexpected '\_'").
  An underscore written as a backtick-quoted name is lexed as a name, and reaches the underscore test in `patAlwaysMatchesAs` (`Parser.hs:1262`): it matches without a test, so the clauses after it are dropped, and a quoted-underscore clause followed by an ill-typed clause checks clean (measured on this PR's `l4`).
- Names: with `GIVEN x … y …`, the group `DECIDE f 0 q IS q` / `DECIDE f p q IS p + q` is accepted, and `f 2 5` gives 7.
  A single clause with a mismatched name (`DECIDE double b IS a * 2`) is still an error, because it takes the ordinary path.
- Redundancy: `DECIDE f TRUE IS 1` / `DECIDE f b IS 2` / `DECIDE f FALSE IS 3` draws no warning, and `f FALSE` gives 2.
  `DECIDE f n IS 7` / `DECIDE f 0 IS 0` draws none either, and `f 0` gives 7.
- Dropped clause: after a total clause, the rest are not type-checked.
  `DECIDE f n IS 7` / `DECIDE f 0 IS "oops" PLUS TRUE` checks clean; with the two clauses swapped the same body is a type error (positive control).
- Location: `GIVEN n IS A NUMBER` with `DECIDE f "hello" IS 0` / `DECIDE f 1 IS 1` reports the pattern's range, but names the scrutinee as `n (at <no location>)`: the synthetic `CONSIDER` scrutinee is built with `emptyAnno` (`:1239`, `:1252`).
- No page under `doc/` describes multi-clause `DECIDE` on unstable (`grep -rli multi-clause doc` is empty); this PR adds `doc/reference/functions/multi-clause-DECIDE.md`.
- Code comments cite `specs/todo/PATTERN-MATCHING-SPEC.md` (`Parser.hs:929`, `PatternMatchParserSpec.hs:7`, `ok/pattern-matching-nullary.l4:9`); on unstable the file is under `specs/done/`, and with this change it is at the cited path.

## In this PR: clause hygiene (from #569)

Unstable #569 (merge `643adeae8`, commits `76450f38f..6215a03c7` on `fix/multi-clause-hygiene`) reports a clause group in the drafter's terms. This PR carries the parts that do not depend on unstable's coverage analysis.

Where it lives, on this branch:

- `jl4-core/src/L4/Syntax.hs`: `PmGroup` (`:482`) and `PmSynthetic` (`:496`, `PmConsider`, `PmFallthrough`, `PmUnreachable`), the `pmSynthetic` field of `Extension` (`:518`) and `annPmSynthetic` (`:567`); `PmMatrix` gains `synthesizedScrutinees` (`:463`) and `catchAll` (`:467`).
- `jl4-core/src/L4/Parser.hs`: `matchClauses` (`:964`) marks every generated CONSIDER (`generatedConsider`, `:1034`) and fall-through binding (`bindFallthrough`, `:1023`), and binds the clauses after a clause that matches every input instead of dropping them (`PmUnreachable`); `clauseMatchesAnything` (`:995`); `givenTermParams` (`:852`).
- `jl4-core/src/L4/TypeCheck.hs`: `settleOneClause` (`:556`), `decideErrorContext` (`:581`), `isClausesBinding` (`:589`), `checkClausesLet` (`:632`, dispatched from `checkExpr` at `:1540`), `speculatively` (`:669`), `warnUnreachableClauses` (`:826`); `checkConsider` (`:1626`) reads the mark; the messages (`:3800`, `:3882`).
- `jl4-core/src/L4/TypeCheck/Types.hs`: `UnreachableClause` (`:110`), `PatternClauseUnreachable`, `ExpectClauseInputContext` (`:157`).
- `jl4-core/src/L4/EvaluateLazy/Exceptions.hs:110` and `Machine.hs` (`consideredClauses`, `:358`): the run-time message in clause terms.

Behaviour:

- No check reads the `__pm_fallthrough_` name any more; every generated node carries a `PmSynthetic` mark. A CONSIDER the drafter wrote in any clause's body is checked like any other, and so is a definition whose name only looks generated.
- The generated CONSIDERs of a group of two or more clauses report no missing branches (the group-level warning does) and no redundant ones (see the adaptations below).
- A group of one clause is checked as a clause too ("This clause does not cover all cases."). Where the check gives up (a literal pattern, more than 64 missing clauses, a type the check does not know), the warning for the CONSIDER it compiles to is kept, moved from no location to the clause.
- The clauses after one that matches every input (one whose patterns all name their column's `GIVEN`) are bound, checked against the group's type outside the earlier clause's scope, with what they infer discarded (`speculatively`), and dropped from the checked tree. One warning goes at the first of them: "This clause of `g` is never used. The clause above it matches every input…".
- Clauses are checked from the top, so a type error is reported at the drafter's clause, as an input of the group ("The first input of `f` is declared to be of type …") rather than about a generated scrutinee.
- At run time, a generated CONSIDER that runs out of branches says "No clause of `k` matches these inputs…" (or "The only clause of `z` …"); a CONSIDER the drafter wrote keeps its wording.

Adapted for main:

- Not carried: #569's second "never used" form, for a clause that repeats one above it or follows a clause binding a new name. It needs the redundant rows of unstable's analysis, which `uncoveredRows` does not compute; `warnUnreachableClauses` and `UnreachableClause` mark the seam. The reference page says these clauses are not flagged.
- `checkClausesLet` checks the clause in scope of the binding that `withScanTypeAndSigEnvironment` makes; #569 adds it again with `extendKnownMany` to mark it a lexical local, which main has no notion of, and on main that second copy made every reference to the binding ambiguous.
- `checkConsider` also reports no redundant branch for a generated CONSIDER. Main's redundancy analysis flags the OTHERWISE after a clause whose pattern is a new name, at no location, naming `__pm_fallthrough_k`; unstable's analysis never flags an OTHERWISE.
- The renderer for a no-GIVEN group's open column reads `synthesizedScrutinees`, replacing this PR's own reading of the written signature.
- `NonExhaustivePatterns` keeps main's two cases (main has no `WHNFWhen`).

Still as on unstable after #569 (measured on both): `l4 render` prints the generated `otherwise: __pm_fallthrough_0`; a GIVEN that names fewer inputs than the clauses have still reports `_pm_arg_2` and `` `_pm_arg_1` (at <no location>) ``.

Tests: `PatternClausesMissingSpec` cases for each behaviour above (8 new; they fail on the commit before this one), and fixtures `not-ok/tc/pattern-matching-clause-type-errors.l4` (its messages equal unstable's golden), `ok/pattern-matching-fallthrough-name.l4`, and `ok/pattern-matching-clause-hygiene.l4` and `ok/pattern-matching-one-clause-fallback.l4`, which are adapted: where a behaviour depends on the check, MAYBE patterns become patterns over enumerations it knows, and the comments say that the warnings are pinned in the spec (main's golden for an `ok/` file records only its results).

## In this PR: exact-print of a clause group (from #130)

The multi-clause part of #130 is carried here; the rest of #130 (`TIMEZONE IS`, `UNLESS`, non-ASCII string literals) is not.
`decidePatternMatch` captures the group's raw tokens with `match`, and `desugarPatternClauses` stores them as one visible node built by `rawTokensAnno`, with a hole for the signature and none for the head or the fused body.
`rawTokensAnno` keeps the whitespace, comments and annotations after the last clause as trailing tokens, so they print but stay outside the group's range, which stops at the last clause (an ordinary single-clause definition's range does run over a following `@desc` or `@export`, measured with `jl4-lsp`); #130's version keeps them visible (read in code); with that version on this branch, a group on lines 3-7 had the range 3-12, up to the next definition's first token, and hovering on the next rule's comment or `@export` in an editor showed the group's type (measured with `jl4-lsp`).
Exact-print, and so `l4 format`, reproduces the clauses as written, comments included; before this, it printed only the signature and the head name.
The three `ok/pattern-matching*.ep.golden` files now equal their sources byte for byte, as they do on unstable, and `jl4/tests-cli` has a case (`l4 format` "reproduces multi-clause DECIDE and MEANS groups byte-for-byte", fixture `tests-cli/fixtures/multi-clause-format.l4`).
`PatternMatchParserSpec` checks that a group followed by comments and `@export` keeps its range to its own lines and that the file exact-prints unchanged.
Semantic tokens walk the same annotation (the generic `Decide` instance, `jl4-lsp/src/LSP/L4/SemanticTokens.hs:212`), so each token of a group is coloured by its token kind alone (`standardTokenType`, `:30-42`): an identifier as a variable, a keyword as a keyword (read in code, not measured in an editor).

## In this PR: the missing-case warning (adapted from #185)

Ruling M1, 2026-10-07 (bench "Multi-clause Main", https://claude.ai/artifact/152eFCmvtT18nVKr9KyTdn): option A, this engine is main's, with no end date; conditions: main's carry of #569 warns only about clauses after a catch-all, and the user documentation says so; the user documentation names the `EXACTLY` and step limits. Meng: "ok. M1 A as printed."

On unstable, #185 (merge `9e684f9b8`) is seven commits: `97cc781c9` (the parser records the clause matrix), `4556d4419` (the checker), `38f0f6fb7` (the column-wildcard fix), fixtures and goldens (`683b20cb0`, `51b08333f`), a DMN test (`0cc42baf6`) and spec notes (`f0e224fd0`).
This PR carries the code of `97cc781c9` and `38f0f6fb7`, with comments adapted to main, and `4556d4419`'s outer structure; the analysis inside it is new, because #185's runs on the residual-set coverage oracle (`analyzeGuardRows` over `analyzeBranch`, `maxUncoveredNablas`, `constructorArity`, `constructorsInScopeFromEntityInfo`), which reached unstable before #185 and is not on main.
Main's own CONSIDER analysis is not reused either: `normalizeRefinement` merges every disjunct into one constraint set (`jl4-core/src/L4/TypeCheck.hs:2356-2363` on this branch, with the union at `:2341`), which loses the row structure a group of several columns needs: traced by hand on `f TRUE TRUE` / `f FALSE FALSE`, it reports nothing missing (not run, since a `CONSIDER` has one scrutinee).

Where it lives, on this branch:

- `jl4-core/src/L4/Syntax.hs`: `PmMatrixClause` and `PmMatrix` (`:439`, `:461`), the `pmMatrix` field of `Extension` (`:517`), `annPmMatrix` and `setPmMatrix` (`:561-565`).
- `jl4-core/src/L4/Parser.hs:908-921`: `desugarPatternClauses` records the scrutinees and each clause's head range and patterns.
- `jl4-core/src/L4/TypeCheck.hs`: `inferDecide` calls `checkClauseMatrix` after checking the body (`:532`); `checkClauseMatrix` (`:696`), `quietly` (`:853`), `coveragePattern` (`:870`), `constructorFamilies` (`:890`), `uncoveredRows` (`:925`), `maxMissingClauses` (`:970`), `patternHasOpaque` (`:980`); the message (`:3793`) and `prettyMissingClauseLhs` (`:3819`).
- `jl4-core/src/L4/TypeCheck/Types.hs:120`: the warning `PatternClausesMissing`, whose range (`:232`) is the hull of the clause heads.

Behaviour:

- Every group is checked, one clause or many (one-clause groups since the #569 carry above).
- Each clause's patterns are checked again against the `GIVEN` types with every diagnostic discarded (`quietly`); a clause naming its column's `GIVEN` is read as matching anything before that, as the desugarer reads it (`patIsColumnWildcard`, `38f0f6fb7`).
- The missing rows are computed by specialisation and the default matrix (Maranget, "Warnings for pattern matching", JFP 2007, §3.1 and §5), over the constructors main's `CONSIDER` analysis knows: `TRUE`/`FALSE` and the enumerations and records declared in the module (`constructorFamilies` reads the same declarations as `buildConstructorLookup`).
- In each suggested clause, an input that the missing case leaves open is written as its `GIVEN` name, or as `` `_` `` when the user wrote no `GIVEN` for it (#185's `renderColumnWildcard` writes the parser's `_pm_arg_i` there, measured on unstable at 568817a6d), and an applied constructor is parenthesised, so each suggested `DECIDE … IS` line can be pasted.
- The warning text is unstable's: "This multi-clause definition does not cover all cases. The following clauses are still needed:".
- Fail-open, as on unstable: a literal or `EXACTLY` pattern anywhere, a pattern that does not re-check, more than 64 missing clauses, or more than 10000 steps means no warning.

Where main differs from unstable (each an absence of a warning, never a different one):

- A group matching lists (`EMPTY`, `FOLLOWED BY`) or values of a type declared in another module (such as `MAYBE` from the prelude) is not checked: main's constructor lookup does not know those constructors.
- There is no `@nonexhaustive`, so a group cannot be marked deliberately partial.
- #185's DMN channel (`siClauseMatrixRanges`) is not carried: main has no DMN export.

Tests: `jl4-core/test/PatternClausesMissingSpec.hs` (15 cases, matching warnings by severity and rendered text, including the documented silences for numbers, lists, `MAYBE`, an enumeration from another file and the 64-clause cap), and `jl4/tests-cli` "warns that a multi-clause DECIDE misses a case, and still succeeds" (fixture `tests-cli/fixtures/multi-clause-missing.l4`).
Main's golden harness prints only infos after "Typechecking successful", so no golden shows the warning.

## Later changes

- #92 (`TYPICALLY`): `givenTermNames` reads the four-field `MkOptionallyTypedName` (`:1078`).
- #183: the checker does not warn inside `__pm_fallthrough_` locals, which are partial by construction (`jl4-core/src/L4/TypeCheck.hs:1139-1170`).
- #333: `PatternMatchParserSpec`'s helper matches the five-field `MkSection`.
