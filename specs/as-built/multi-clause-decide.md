# Multi-clause pattern-matching DECIDE (as built)

As built on unstable at 73a953821. Source spec: specs/done/PATTERN-MATCHING-SPEC.md (on main at `specs/todo/PATTERN-MATCHING-SPEC.md`). Differences from the source spec: `_` and `_name` wildcards are lexer errors; inside a clause group a variable whose name differs from its `GIVEN` is accepted and binds, where the spec requires an error; the Phase 1 redundancy and overlap warnings were never built, and a clause after a total clause is dropped before type checking; the Phase 1 exhaustiveness warning is in this PR, adapted from #185 (see below), and does not cover groups that match literals, lists or types declared in another module; a type error in a clause pattern names the scrutinee "at <no location>".

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

## In this PR: the fall-through warning

Main's CONSIDER exhaustiveness check, as extended by main's `7531f1d9a` (builtin constructors such as `TRUE`/`FALSE`, and the `declareDeclarations` union), predates this feature; on unstable those extensions arrived with #182, after #49.
So in this PR `checkConsider` skips the missing-arm warning for a `CONSIDER` whose innermost enclosing definition is a `__pm_fallthrough_` local (`inPatternFallthrough`, reading the checker's error context).
Without it, total groups such as `` `to bit` `` warn at `<no location>` about a hidden name.
Nothing on main alone pins this: main's golden harness prints only `SInfo` diagnostics after "Typechecking successful", so the three fixtures' goldens are the same with or without it; with the golden-harness change also on main, they pin it.
On unstable, #183 does this job with `isSyntheticFallthrough` instead.
The suppression also silences a user-written `CONSIDER` in the body of clauses 2..n, the residual unstable documents for #183's mechanism.
It is narrower than #183's in one way: it stops at the innermost enclosing definition, so a WHERE or LET helper inside a fall-through still warns.
Redundancy warnings are unaffected, and a value no clause matches still fails at run time; an incomplete group of two or more clauses is reported by the group-level warning below instead (a one-clause group still warns through the ordinary path).

## In this PR: exact-print of a clause group (from #130)

The multi-clause part of #130 is carried here; the rest of #130 (`TIMEZONE IS`, `UNLESS`, non-ASCII string literals) is not.
`decidePatternMatch` captures the group's raw tokens with `match`, and `desugarPatternClauses` stores them as one visible node built by `rawTokensAnno`, with a hole for the signature and none for the head or the fused body.
`rawTokensAnno` keeps the whitespace, comments and annotations after the last clause as trailing tokens, so they print but stay outside the group's range, which stops at the last clause (an ordinary single-clause definition's range does run over a following `@desc` or `@export`, measured with `jl4-lsp`); #130's version keeps them visible (read in code); with that version on this branch, a group on lines 3-7 had the range 3-12, up to the next definition's first token, and hovering on the next rule's comment or `@export` in an editor showed the group's type (measured with `jl4-lsp`).
Exact-print, and so `l4 format`, reproduces the clauses as written, comments included; before this, it printed only the signature and the head name.
The three `ok/pattern-matching*.ep.golden` files now equal their sources byte for byte, as they do on unstable, and `jl4/tests-cli` has a case (`l4 format` "reproduces multi-clause DECIDE and MEANS groups byte-for-byte", fixture `tests-cli/fixtures/multi-clause-format.l4`).
`PatternMatchParserSpec` checks that a group followed by comments and `@export` keeps its range to its own lines and that the file exact-prints unchanged.
Semantic tokens walk the same annotation (the generic `Decide` instance, `jl4-lsp/src/LSP/L4/SemanticTokens.hs:212`), so each token of a group is coloured by its token kind alone (`standardTokenType`, `:30-42`): an identifier as a variable, a keyword as a keyword (read in code, not measured in an editor).

## In this PR: the missing-case warning (adapted from #185)

On unstable, #185 (merge `9e684f9b8`) is seven commits: `97cc781c9` (the parser records the clause matrix), `4556d4419` (the checker), `38f0f6fb7` (the column-wildcard fix), fixtures and goldens (`683b20cb0`, `51b08333f`), a DMN test (`0cc42baf6`) and spec notes (`f0e224fd0`).
This PR carries the code of `97cc781c9` and `38f0f6fb7`, with comments adapted to main, and `4556d4419`'s outer structure; the analysis inside it is new, because #185's runs on the residual-set coverage oracle (`analyzeGuardRows` over `analyzeBranch`, `maxUncoveredNablas`, `constructorArity`, `constructorsInScopeFromEntityInfo`), which reached unstable before #185 and is not on main.
Main's own CONSIDER analysis is not reused either: `normalizeRefinement` merges every disjunct into one constraint set (`jl4-core/src/L4/TypeCheck.hs:2167-2174` on this branch, with the union at `:2152`), which loses the row structure a group of several columns needs: traced by hand on `f TRUE TRUE` / `f FALSE FALSE`, it reports nothing missing (not run, since a `CONSIDER` has one scrutinee).

Where it lives, on this branch:

- `jl4-core/src/L4/Syntax.hs`: `PmMatrixClause` and `PmMatrix` (`:439`, `:461`), the `pmMatrix` field of `Extension` (`:481`), `annPmMatrix` and `setPmMatrix` (`:523-527`).
- `jl4-core/src/L4/Parser.hs:897-908`: `desugarPatternClauses` records the scrutinees and each clause's head range and patterns.
- `jl4-core/src/L4/TypeCheck.hs`: `inferDecide` calls `checkClauseMatrix` after checking the body (`:531`); `checkClauseMatrix` (`:556`), `quietly` (`:689`), `coveragePattern` (`:706`), `constructorFamilies` (`:726`), `uncoveredRows` (`:761`), `maxMissingClauses` (`:806`), `patternHasOpaque` (`:816`); the message (`:3604`) and `prettyMissingClauseLhs` (`:3618`).
- `jl4-core/src/L4/TypeCheck/Types.hs:106`: the warning `PatternClausesMissing`, whose range (`:209`) is the hull of the clause heads.

Behaviour:

- Groups of two or more clauses are checked; a one-clause group is left to the ordinary `CONSIDER` warning, as on unstable.
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
