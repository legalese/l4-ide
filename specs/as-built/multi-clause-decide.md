# Multi-clause pattern-matching DECIDE (as built on main)

This describes branch `carve/multi-clause-decide` (PR #545, into `main`), re-measured on 2026-10-13 (the goldens and the test counts, after the carry of #631 described under "Review round 5"); a measurement dated earlier in the text keeps its date.
The `file:line` citations were last re-derived on 2026-10-15, after the merges of `main` into the branch that carries the ladder section (#656).
Every `file:line` below is at the commit that last changed this file.
The user page `doc/reference/functions/multi-clause-DECIDE.md`, named in several places below, was folded into `doc/reference/functions/DECIDE.md` on `main` (dd7521bb0) and no longer exists; this branch's section of it, on the decision graph and the query plan, is now `DECIDE.md`, "Several clauses", "The decision graph and the query plan", and the other sections the old page had are in `doc/reference/errors/README.md` and `doc/concepts/type-system/exhaustiveness.md` as `main` has them.
The mentions of the old page below say what it said when they were written.
The probes, test counts and timings below were run on binaries built from earlier commits, the one the text names beside each where it names one; a commit that changes only this file does not re-run them.
The branch carries work first merged into unstable, one PR at a time, and each section below names its unstable source.
The unstable commits named here are on unstable only: none of them is on this branch or on main.

This branch, oldest first: `d0905e1d8` (the clauses, from #49), `d6594578b` (exact-print, from #130), `17e944423` (the missing-case warning, adapted from #185), `1a67532c7` (clause hygiene, from #569), `f02f0a6b7` (a merge of main), `ee407387b` (ruling M1), `b7c54a6cb` (generated names, printing, editor and render, from #581), `f2d938863` (the missing-case check's limits in the user documentation; this file rewritten for main), `36c549226` (`l4 run --json` reports an evaluation error in the drafter's terms), `6d0146f27` (ruling M2, from legalese/l4-ide#587), the round-2 review's `c8907bf66`, `21df62c92`, `526f70396`, `d0f4c7afa` and `232e14b1b`, the commit that wrote that review into this file (`b1002d9af`), the round-3 fixes `8e4c920ca`, `05559e4ec` and `2113516a1`, the commit that wrote those into this file (`0350c079b`), the second round-3 fix `67d0903c2`, `764671496` (the round-3 fixtures' goldens, made on main), the commit that wrote those into this file (`03bf38dc4`), `2dd411963` (a warning at an annotation above a later clause), the commit that wrote that into this file (`c09a64cd9`), `b42394622` (a group's annotations read as a plain definition's, and a warning at each later one), the commit that wrote that into this file (`ce2b10bda`), the round-4 fixes `fb719cd6d` and `07a84815a`, the commit that wrote those into this file (`93be32d32`), the second round-4 fixes `436d9ed26` and `eeac2e4de`, the commit that wrote those into this file (`860824ffc`), `e7b13bbfe` (an annotation inside a group that nothing of it claims is not the next rule's), the commit that wrote that into this file (`aab4180c4`), `395984253` (the merge of the literal-pattern work, next paragraph), `db5671b5f` (a merge of main `00298eb60`), `d4484eecb` (this file's `file:line` citations re-derived against the merged tree), `42bce62ae` (single backticks, for prettier 3.4.2), `9957f5b32` (three places that said an `ok/` golden records no warnings now say that the harness prints them), `5f9409a37` (nine `ok/` goldens re-recorded for that harness), the pre-review's text pass (`6be250de9` this file's reference check, `101572dad` the pages that said the two spellings of a rule warn alike, and comments that cited rulings by trigger word, `a022af716` the comment of Test 30, `5db1ace0d` the nested-`CONSIDER` timings, `ca13ef36d` a comment's file name and `f5eb82e5f` the Paint example), the carry of #631 (`9cf43f128` the error for a clause in a mixfix rule's form, `869fb9c02` the warning for a definition after a group with another number of inputs, `4c9e9d0e7` the editor tests, `9da6f8f4a` the sentence in the user documentation, `bb3691618` "Review round 5" below), `aede1e07d` (a local in `checkConsider` renamed), the commit that wrote that into this file (`faf0ae8b3`), `90bf26112` (the stray label under Test 23 in the literal-clauses fixture), `099aa5d57` (the header of `CheckSource.hs`), the commit that wrote these into this file (`c0d810432`), the commit that corrected the editor tests' paragraph (`a55036989`), the carry of the fourth review's two fixes (`dde18caf4` the parser, `ce780a02e` the fixtures and the documentation, `e01e9b6f9` the timing guard), `d37c01f5a` (the commit that wrote those into this file), the two fixes the reviewer of that carry asked for (`9f8d664ed` the page's limit on what is not refused, `1c208b367` the stuck clock and the control), and the commit that wrote these into this file.
The literal-pattern work, 36 commits from `8da1c4eaa` to `028b04f93` (on top of `2113516a1`), is merged into this branch as `395984253` and is described under "Literal patterns" below.

Source spec: `specs/done/PATTERN-MATCHING-SPEC.md`.
Differences from the source spec, each probed on this branch:

- `_` and `_name` are lexer errors (`DECIDE f _ IS 0`: "unexpected '\_'").
  An underscore written as a backtick-quoted name is lexed as a name, and matches without a test, as the desugarer reads `_` (`patAlwaysMatchesAs`, `jl4-core/src/L4/Syntax.hs:116`).
- Inside a group, a pattern variable whose name differs from its `GIVEN` is accepted and binds, where the source spec requires an error.
  With `GIVEN x … y …`, `DECIDE f 0 q IS q` / `DECIDE f p q IS p + q` checks, and `f 2 5` gives 7.
  A single clause with a mismatched name (`DECIDE double b IS a * 2`) is still an error, because it takes the ordinary path.
- The Phase 1 redundancy and overlap warnings are not built, except that the clauses after one that matches every input, by its inputs' own names, `_` or new names, are reported as never used; a clause that repeats one above it is not.
  `DECIDE f TRUE IS 1` / `DECIDE f other IS 2` / `DECIDE f FALSE IS 3` warns that the `FALSE` clause is never used, naming `other`, and `f FALSE` gives 2.
- The Phase 1 exhaustiveness warning is built, adapted from #185, and does not cover every group (see the limits under "The missing-case warning").

## What it does

Several `DECIDE` (or `MEANS`) clauses with the same head, written one after another under a single `GIVEN`/`GIVETH` signature, may put literal or constructor patterns in argument positions:

```l4
GIVEN n IS A NUMBER
GIVETH A NUMBER
DECIDE factorial 0 IS 1
DECIDE factorial n IS n * factorial (n - 1)
```

The parser fuses the group into one `Decide` whose body is a chain of `CONSIDER … WHEN` tests.
Clauses are tried top to bottom and the first match wins; if none matches, evaluation stops with an error.

## Where it lives

In `jl4-core/src/L4/Parser.hs`:

- `topdecl` tries the group parser first, and a definition that is no group through `decideNotInMixfixForm`, which wraps `decide`: `try (decidePatternMatch sig) <|> decideNotInMixfixForm sig` (`:466`).
- `PMClause`, a parser-internal clause record that never enters the AST (`:740`).
- `decidePatternMatch`, grouping and the commit test (`:763`); `pmClause`, one clause (`:954`).
- `givenTermNames` (`:1094`) and `givenTermParams` (`:1099`).
- `desugarPatternClauses`, which builds the fused `MkDecide` and records the clause matrix (`:1111`).
- `generatedName` (`:1185`), `givenInputBinding` (`:1194`), `scrutineeRef` (`:1202`), `rawTokensAnno` (`:1215`).
- `matchClauses` (`:1243`), `clauseMatchesAnything` (`:1274`), `fallthroughName` (`:1281`), `clausesSrcAnno` (`:1302`), `bindFallthrough` (`:1311`), `generatedConsider` (`:1325`), `matchOne` (`:1331`), `matchLast` (`:1351`).

In `jl4-core/src/L4/Syntax.hs`: `isDistinguishablePat` (`:103`), `patAlwaysMatchesAs` (`:116`) and `isGeneratedName` (`:124`), shared by the parser, the checker, the printer and the editor.

The run-time error is `NonExhaustivePatterns` (`jl4-core/src/L4/EvaluateLazy/Exceptions.hs:46`), thrown at `EvaluateLazy/Machine.hs:1190`.

## Behaviour and rules

Grouping.
The first clause sets the column, the head name and the arity.
Further clauses must start at exactly that column (`withIndent EQ`, `Parser.hs:782`) and have the same raw head name and the same number of argument patterns.
Anything else ends the group, including an intervening `GIVEN`, so type-overloaded definitions, each with its own signature, are never merged.

Clause forms.
`DECIDE head pat… [AKA …] IS|IF body`, or `head pat… [AKA …] MEANS body`.
Argument patterns are atomic, so an applied constructor needs parentheses: `(JUST v)`, `(x FOLLOWED BY xs)`.
The first `AKA` found in any clause is used for the fused head; each clause also keeps its own (`PmMatrixClause`), which the printer writes back on that clause, and a run of overloads gives to its own definition (see "Review round 3" below).

When the group is taken (`isGroup`, `Parser.hs:807`).
It is taken when some clause has a distinguishable pattern: a literal, a cons, an `EXACTLY` expression, or a constructor with arguments.
It is also taken when the group has at least two clauses, every argument is a bare name, and in some column the bare names differ (`TRUE`/`FALSE`, enum constants).
Otherwise the parser backtracks and the ordinary single-clause `decide` parser runs, so a lone bare-name clause is unchanged.
A group of the second kind can be a run of overloads, told apart by their types (`show n MEANS n + 1` / `show b MEANS b AND TRUE`); the checker turns it back into separate definitions when none of its names is a constructor (`separateOverloads`, see "Review round 2" below).

Inputs.
If the signature's term parameters (`GIVEN` names that are not `IS A TYPE`) number exactly the arity, and the arity is positive, they are the group's inputs, bound in the definition at the `GIVEN`'s own location with none of its tokens (`givenInputBinding`).
Otherwise the desugarer makes the inputs up: `input 1 … input n`, spelled with `PreDef` (`generatedName`), which no source can write; a backtick-quoted `` `input 1` `` is a `NormalName`, and so a different name.
A `GIVEN` that does not name one input per pattern, a type-only `GIVEN` included, is an error (see Diagnostics).

Desugaring.
For each column, a bare name equal to the input's name, or `_` written as a quoted name, matches without a test and binds nothing new.
Any other pattern becomes a generated `CONSIDER … WHEN <pattern>`, marked `PmConsider` (`generatedConsider`).
It reads the input by the input's name respelled with `PreDef` (`scrutineeRef`), which the checker makes another name of the `GIVEN` input (`clauseInputSpellings`, `TypeCheck.hs:840`), so a pattern variable an earlier column binds under that name cannot capture the reference.
A bare name that is not the input's name is a `WHEN` pattern, and the checker decides whether it is a nullary constructor or a fresh variable: in `DECIDE premium other IS 0`, `other` binds the input.
Every non-final clause gets `OTHERWISE <the later clauses>`; the final clause gets no `OTHERWISE`, so a value no clause matches raises `NonExhaustivePatterns` at run time.
The later clauses are bound once per clause boundary, with `LET … IN`, to a nullary local named for what it holds, `the result of clauses 2 to 3` or `the result of clause 3` (`fallthroughName`), also spelled with `PreDef`, and referenced by name, so the tree is linear in clauses times columns.
Each such local `Decide` has its first clause's body as its source range (`clausesSrcAnno`), because the checker keys function signatures by `Decide` range; only the body, so that hover on a pattern between the bodies finds the pattern and not the binding.
The clauses after one in which every column matches without a test are bound too, marked `PmUnreachable`, so that they are checked (see clause hygiene below).

## Diagnostics

- At run time, a generated `CONSIDER` that runs out of branches says "No clause of `k` matches these inputs.", or "The only clause of `z` does not match these inputs." (`Exceptions.hs:110`); a `CONSIDER` the drafter wrote keeps "The value … reached a CONSIDER that has no branch for it." (`:100`).
- A `GIVEN` that does not name one input per pattern, a type-only `GIVEN` included, is one error at the first clause's head (`ClausePatternCountMismatch`, `jl4-core/src/L4/TypeCheck/Types.hs:77`; message at `TypeCheck.hs:4411`): "Each clause of `f` has 2 patterns, but its GIVEN names 1 input."
- A pattern of the wrong type is reported as an input of the group: "The first input of `f` is declared to be of type NUMBER but the pattern written for it here is of type STRING", at the pattern (`ExpectClauseInputContext`, `Types.hs:195`; message at `TypeCheck.hs:4776`).
- The missing-case warning and the never-used warning are described below.
- Because the pattern parser is tried first, a malformed `DECIDE` head lists pattern tokens among the expected ones: `expecting (, AKA, EXACTLY, Float Literal, IF, IS, Numeric Literal, OF, String Literal, identifier, or space token` (`jl4/examples/not-ok/tc/tests/parse-error4.golden:14`).

## Tests and fixtures that pin it

- `jl4-core/test/PatternMatchParserSpec.hs` (in `jl4-core-test`), eight cases: literal and variable clauses group into one `CONSIDER`-bodied `Decide`; `EMPTY`/`FOLLOWED BY` clauses group; a single literal clause desugars; a single variable clause is left alone; two different heads stay two `Decide`s; a group's range stops at its own lines and the file exact-prints unchanged; and two timing guards, for a run of one name and for definitions with different names (see "Review round 3").
- `jl4-core/test/PatternClausesMissingSpec.hs`, 100 cases (see "The missing-case warning" below), and `jl4-core/test/MultiClausePrintSpec.hs`, both described below.
- `jl4/examples/ok/`: `pattern-matching.l4` (factorial, fib, list length, `from maybe`, a two-column decision table, nested `(JUST (JUST k))`), `pattern-matching-nullary.l4`, `pattern-matching-decision-table.l4`, `pattern-matching-clause-hygiene.l4`, `pattern-matching-one-clause-fallback.l4`, `pattern-matching-fallthrough-name.l4`, `pattern-matching-input-names.l4` and `pattern-matching-literal-clauses.l4`, each with its four goldens under `tests/`.
- `jl4/examples/not-ok/tc/`: `pattern-matching-clause-type-errors.l4` and `pattern-matching-clause-inputs.l4`, and, from "Review round 5", `pattern-matching-mixfix-form-clause.l4`, `pattern-matching-mixfix-form-definition.l4` and `pattern-matching-mixfix-form-group.l4`.
- `jl4/examples/lsp/hover/multi-clause-hover.l4`, with its positions in `jl4/tests/Hover.hs`.
- `jl4-lsp/test/ClauseGeneratedNamesSpec.hs`, ten examples in `jl4-lsp-test`, the test suite of `jl4-lsp` that this branch adds ("Review round 5"); `ok/pattern-matching-mixfix-neighbours.l4` and `ok/pattern-matching-clause-arity-change.l4` are the two `ok/` fixtures of the same round.
- `jl4/tests-cli`: `l4 format` "reproduces multi-clause DECIDE and MEANS groups byte-for-byte" (fixture `multi-clause-format.l4`); `l4 check` "warns that a multi-clause DECIDE misses a case, and still succeeds" (`multi-clause-missing.l4`); "multi-clause groups: the names they are compiled to" (`multi-clause-render.l4`, through `l4 render` and `l4 trace`); and "l4 batch: re-prints a multi-clause group as its clauses" (the `batch-multi-clause*` fixtures).

Main's golden harness prints warnings after "Typechecking successful" (`6ca1fc34c`, described in `specs/as-built/golden-harness.md`), so the golden of an `ok/` file has to record the warnings of its source; `PatternClausesMissingSpec` pins them as well.

## Exact-print of a clause group (from #130)

The multi-clause part of #130 is carried here; the rest of #130 (`TIMEZONE IS`, `UNLESS`, non-ASCII string literals) is not.
`decidePatternMatch` captures the group's raw tokens with `match`, and `desugarPatternClauses` stores them as one visible node built by `rawTokensAnno`, with a hole for the signature and none for the head or the fused body.
`rawTokensAnno` keeps the whitespace, comments and annotations after the last clause as trailing tokens, so they print but stay outside the group's range, which stops at the last clause (an ordinary single-clause definition's range does run over a following `@desc` or `@export`, measured with `jl4-lsp` when this was carried); #130's version keeps them visible (read in code), and with that version a group on lines 3-7 had the range 3-12, up to the next definition's first token, so hovering on the next rule's comment or `@export` in an editor showed the group's type (measured with `jl4-lsp` when this was carried).
Exact-print, and so `l4 format`, reproduces the clauses as written, comments included.
The three `ok/pattern-matching*.ep.golden` files of #49 equal their sources byte for byte.
Semantic tokens walk the same annotation (the generic `Decide` instance, `jl4-lsp/src/LSP/L4/SemanticTokens.hs:212`), so each token of a group is coloured by its token kind alone (`standardTokenType`, `:30-42`): an identifier as a variable, a keyword as a keyword (read in code, not measured in an editor).

## Clause hygiene (from #569)

Unstable #569 (merge `643adeae8`, on unstable) reports a clause group in the drafter's terms.
This branch carries the parts that do not depend on unstable's coverage analysis.

Where it lives:

- `jl4-core/src/L4/Syntax.hs`: `PmGroup` (`:540`) and `PmSynthetic` (`:554`: `PmConsider`, `PmFallthrough`, `PmUnreachable`), the `pmSynthetic` field of `Extension` (`:583`), `annPmSynthetic` (`:672`) and `setPmSynthetic` (`:675`); `PmMatrix` has `synthesizedScrutinees` (`:520`) and `catchAll` (`:525`).
- `jl4-core/src/L4/Parser.hs`: `matchClauses` (`:1243`) marks every generated CONSIDER (`generatedConsider`, `:1325`) and binding of later clauses (`bindFallthrough`, `:1311`), and binds the clauses after a clause that matches every input instead of dropping them (`PmUnreachable`); `clauseMatchesAnything` (`:1274`); `givenTermParams` (`:1099`).
- `jl4-core/src/L4/TypeCheck.hs`: `settleOneClause` (`:719`), `decideErrorContext` (`:744`), `isClausesBinding` (`:752`), `checkClausesLet` (`:886`, dispatched from `checkExpr` at `:2066`), `speculatively` (`:923`), `warnUnreachableClauses` (`:1164`); `checkConsider` (`:2187`) reads the mark; the messages (`:4630`, `:4776`).
- `jl4-core/src/L4/TypeCheck/Types.hs`: `UnreachableClause` (`:128`), `PatternClauseUnreachable` (`:150`), `ExpectClauseInputContext` (`:195`).
- `jl4-core/src/L4/EvaluateLazy/Exceptions.hs:110` and `Machine.hs` (`consideredClauses`, `:363`): the run-time message in clause terms.

Behaviour:

- No check reads a generated name; every generated node carries a `PmSynthetic` mark. A CONSIDER the drafter wrote in any clause's body is checked like any other, and so is a definition whose name only looks generated.
- The generated CONSIDERs of a group of two or more clauses report no missing branches (the group-level warning does) and no redundant ones (see the adaptations below).
- A group of one clause is checked as a clause too ("This clause does not cover all cases."). Where the check gives up (see its limits below), the warning for the CONSIDER it compiles to is kept, moved from no location to the clause.
- The clauses after one that matches every input by its patterns as written (each its input's own name or `_`) are bound, checked against the group's type outside the earlier clause's scope, with what they infer discarded (`speculatively`), and dropped from the checked tree. One warning goes at the first of them: "This clause of `g` is never used. The clause above it matches every input…".
- Clauses are checked from the top, so a type error is reported at the drafter's clause, as an input of the group, rather than about a generated scrutinee.
- At run time, a generated CONSIDER that runs out of branches speaks of clauses (see Diagnostics); a CONSIDER the drafter wrote keeps its wording.

Adapted for main:

- Not carried: #569's second "never used" form, for a clause that repeats one above it. It needs the redundant rows of unstable's analysis, which `uncoveredRows` does not compute; `warnUnreachableClauses` and `UnreachableClause` mark the seam. The user documentation says these clauses are not flagged (`doc/reference/errors/README.md`, "Clause that is never used"; `doc/reference/functions/multi-clause-DECIDE.md`, "Limits").
- `checkClausesLet` checks the clause in scope of the binding that `withScanTypeAndSigEnvironment` makes; #569 adds it again with `extendKnownMany` to mark it a lexical local, which main has no notion of, and on main that second copy made every reference to the binding ambiguous.
- `checkConsider` also reports no redundant branch for a generated CONSIDER. Main's redundancy analysis flags the OTHERWISE after a clause whose pattern is a new name, at no location, naming the binding of the later clauses; unstable's analysis never flags an OTHERWISE. What it finds is reported in the drafter's terms instead, when a whole clause matches every input (see "Review round 2" below).
- The renderer for a no-GIVEN group's open column reads `synthesizedScrutinees`.
- `NonExhaustivePatterns` keeps main's two cases (main has no `WHNFWhen`).

Tests: eight `PatternClausesMissingSpec` cases for the behaviour above (they failed on the commit before `1a67532c7`, measured when it was carried), and the fixtures `not-ok/tc/pattern-matching-clause-type-errors.l4`, `ok/pattern-matching-fallthrough-name.l4`, `ok/pattern-matching-clause-hygiene.l4` and `ok/pattern-matching-one-clause-fallback.l4`; where a behaviour depends on the check, their MAYBE patterns are patterns over enumerations it knows.

## The missing-case warning (adapted from #185)

Ruling M1, ruled by Meng, 2026-10-07: option A, this engine is main's, with no end date; conditions: main's carry of #569 warns only about clauses after a catch-all, and the user documentation says so; the user documentation names the `EXACTLY` and step limits. Meng: "ok. M1 A as printed."

Both conditions are met in the user documentation on this branch: `doc/reference/errors/README.md` ("Multi-clause DECIDE does not cover all cases", its Note; "Clause that is never used") and `doc/reference/functions/multi-clause-DECIDE.md` ("Limits") name every limit listed below, with an example of each, and say that only the clauses after a catch-all are reported as never used.

Ruling M2: option A, "Refuse at check"; conditions: on unstable first, then carried to #545, plus one issue for inputs with no declared type published with the wrong schema type, filed as smucclaw/l4-ide#1024; Meng gave no note beyond choosing the option; ruled by Meng, 2026-10-08; carried from legalese/l4-ide#587

M2 is about publishing, not about missing cases; it is described under "Refusing an @export of clauses with no GIVEN" below.

On unstable, #185 (merge `9e684f9b8`) is seven commits: `97cc781c9` (the parser records the clause matrix), `4556d4419` (the checker), `38f0f6fb7` (the column-wildcard fix), fixtures and goldens (`683b20cb0`, `51b08333f`), a DMN test (`0cc42baf6`) and spec notes (`f0e224fd0`).
This branch carries the code of `97cc781c9` and `38f0f6fb7`, with comments adapted to main, and `4556d4419`'s outer structure; the analysis inside it is new, because #185's runs on the residual-set coverage oracle (`analyzeGuardRows` over `analyzeBranch`, `maxUncoveredNablas`, `constructorArity`, `constructorsInScopeFromEntityInfo`), which reached unstable before #185 and is not on main.
Main's own CONSIDER analysis is not reused either: `normalizeRefinement` merges every disjunct into one constraint set (`jl4-core/src/L4/TypeCheck.hs:3049-3056`, with the union at `:3034`), which loses the row structure a group of several columns needs: traced by hand on `f TRUE TRUE` / `f FALSE FALSE`, it reports nothing missing (not run, since a `CONSIDER` has one scrutinee).

Where it lives:

- `jl4-core/src/L4/Syntax.hs`: `PmMatrixClause` and `PmMatrix` (`:478`, `:518`), the `pmMatrix` field of `Extension` (`:582`), `annPmMatrix` and `setPmMatrix` (`:666-670`).
- `jl4-core/src/L4/Parser.hs:1159-1175`: `desugarPatternClauses` records the inputs and each clause's head range and patterns.
- `jl4-core/src/L4/TypeCheck.hs`: `inferDecide` calls `checkClauseMatrix` after checking the body (`:691`); `checkClauseMatrix` (`:950`), `quietly` (`:1196`), `coverageRow` (`:1229`), `coveragePattern` (`:1269`), `constructorFamilies` (`:1332`), `uncoveredRows` (`:1396`), `maxMissingClauses` (`:1472`), `clauseMatrixFuel` (`:1510`); the message (`:4608`) and `prettyMissingClauseLhs` (`:4688`).
- `jl4-core/src/L4/TypeCheck/Types.hs:143`: the warning `PatternClausesMissing`, whose range (`:284`) is the hull of the clause heads.

Behaviour:

- Every group is checked, one clause or many.
- Each clause's patterns are checked again against the `GIVEN` types with every diagnostic discarded (`quietly`); a clause naming its column's `GIVEN` is read as matching anything before that, as the desugarer reads it (`patIsColumnWildcard`, `TypeCheck.hs:1131`, from unstable's `38f0f6fb7`).
- The missing rows are computed by specialisation and the default matrix (Maranget, "Warnings for pattern matching", JFP 2007, §3.1 and §5), over the constructors main's `CONSIDER` analysis knows: `TRUE`/`FALSE` and the enumerations and records declared in the module (`constructorFamilies` reads the same declarations as `buildConstructorLookup`).
- In each suggested clause, an input that the missing case leaves open is written as its `GIVEN` name, or as `` `_` `` when the user wrote no `GIVEN` for it (#185's `renderColumnWildcard` wrote the parser's `_pm_arg_i` there, measured on unstable at `568817a6d`), and an applied constructor is parenthesised, so each suggested `DECIDE … IS` line can be pasted.
- The warning text is unstable's: "This multi-clause definition does not cover all cases. The following clauses are still needed:".

Limits.
Each is fail-open: the check gives up with no warning, and no diagnostic says that it gave up (assumed, not ruled, 2026-10-08: the user documentation names the limits instead).

- A group matching lists (`EMPTY`, `FOLLOWED BY`), or values of a type declared in another module (such as `MAYBE` from the prelude), is checked only as far as the analysis need not tell those values apart: main's constructor lookup does not know those constructors, so the analysis gives up where it meets one as a column head, and answers where a row of wildcards or the other columns settle the question first (`t Red EMPTY` / `t Red xs` / `t Green xs` lists `Blue xs`; `f Red (JUST 0)` / `f Green m` lists `Red m` and `Blue m` through the coarse tier; `show NOTHING` / `show (JUST 0)` and `f (JUST 0)` / `f (JUST n)` are silent).
  A group whose every clause has a number or a piece of text in it is answered by the coarse tier below with the one all-names clause (`f (JUST 0)` alone suggests ``DECIDE `f` m IS``).
- An `EXACTLY` the analysis cannot read: on an enumeration or `BOOLEAN` input, any `EXACTLY` other than a value of the input's type or the input's own name; on any input, an `EXACTLY` whose expression mentions the input itself; inside a pattern, the same by the type of the position, read off the pattern's annotation after the re-check's substitution, and an `EXACTLY` of a value it cannot name where that type is still an inference variable.
  On a number, text or date input or field, or one declared under another name for one (`DECLARE Age IS A NUMBER`; synonyms are expanded for the analysis, `expandSynonymsIn`, `:1311`), an `EXACTLY` of a value the analysis cannot name (`EXACTLY someConstant`, at the top of a clause or inside a pattern, as in `f (Box (EXACTLY zero))` / `f (Box n)`) leaves its clause out instead of stopping the group, and the group then gets the coarse list alone; see "Literal patterns" below.
- More than 64 rows at any level of the analysis (`maxMissingClauses`), or more than 10000 steps (`clauseMatrixFuel`), in both tiers.
- A pattern that does not re-check against its `GIVEN` type.
- There is no `@nonexhaustive`, so a group cannot be marked deliberately partial.
- #185's DMN channel (`siClauseMatrixRanges`) is not carried: main has no DMN export.

Tests: `jl4-core/test/PatternClausesMissingSpec.hs` (100 cases, matching warnings by severity and rendered text; counted as the lines that begin `it "` in the merged file: 76 in `clauseSpec`, 8 in `considerSpec`, 6 in `plainConsiderSpec` and 10 in `redundantCatchAllSpec`).
The `clauseSpec` cases are: the 14 from `17e944423` less the number silence, including the silences for lists, `MAYBE`, an enumeration from another file and the 64-row cap; eight for clause hygiene; two for the clause after a new name (review round 2); eight for annotations between clauses (review round 3, and three of round 4); and the literal-pattern cases listed under "Literal patterns" below, which replaced the three that pinned the former silences for a number anywhere, an `EXACTLY` pattern and the nine-input step limit.
`considerSpec` and `plainConsiderSpec` are listed under "Literal patterns" below; `redundantCatchAllSpec` is `d615262bf`, "a catch-all branch after a catch-all branch is redundant again", whose behaviour this file does not otherwise describe.
`jl4/tests-cli` "warns that a multi-clause DECIDE misses a case, and still succeeds" (fixture `tests-cli/fixtures/multi-clause-missing.l4`).

## Generated names, printing, editor and render (from #581)

Unstable PR #581 (branch `fix/multi-clause-names`, six commits ending at `796cc8eb1`; merged into unstable on 2026-10-07, after this was carried) is carried as one commit, `b7c54a6cb`, because each part needed adapting to main's printer, test harnesses and AST, and the parts depend on each other.

Where it lives:

- The names: `generatedName`, `givenInputBinding`, `scrutineeRef` and `fallthroughName` in `Parser.hs` (see "Where it lives" above); `isGeneratedName` (`Syntax.hs:124`); `clauseInputSpellings` (`TypeCheck.hs:840`), added to scope in `inferDecide` (`:683`).
- The count of inputs: `clauseInputsAgainstGiven` (`TypeCheck.hs:775`), `givenInputsInScope` (`:791`) and `givenMisnamesInputs` (`:800`), used by `scanFunSigDecide` (`:4050`) and `checkClauseMatrix` (`:950`).
- Hover: `recordInputPatterns` (`TypeCheck.hs:974`).
- Printing: the `Decide` printer (`jl4-core/src/L4/Print.hs:268`), `writtenClauses` (`:314`), `clauseHeadPattern` (`:338`), `unusedInputNames` (`:359`), `clauseBodies` (`:371`) and `writtenSignature` (`:394`).
- Render: `clauseLayout` (`jl4-core/src/L4/Export/Document.hs:812`).
- Editor: completion leaves out generated names (`jl4-lsp/src/LSP/L4/Actions.hs:352`), and so does the outline (`outlineGivenParams` and `outlineLocals`, `jl4-lsp/src/LSP/L4/Actions.hs:283` and `:290`, called at `jl4-lsp/app/LSP/L4/Handlers.hs:506-507` and `:622`; both filters were in the handler until the carry of #631, see "Review round 5").

Behaviour:

- Every name the desugarer makes up is spelled with `PreDef`, so no drafter's name can capture it and no generated name can capture a drafter's: a clause body naming a definition `` `the result of clauses 2 to 3` `` or `` `__pm_fallthrough_0` `` reads that definition.
- A `GIVEN` that does not name one input per pattern, a type-only `GIVEN` included, is one `ClausePatternCountMismatch` at the first clause; the inputs it does name stay in scope at their declared types, so a clause body that reads one draws no second error. At `ee407387b` the same group reported `_pm_arg_2` and `` `_pm_arg_1` (at <no location>) ``.
- `prettyLayout`, which `l4 batch` and the REPL print a module through before running it again, prints a group as its clauses, from the AST: the patterns from the clause matrix, in which every ditto is already resolved, and each body from the tree. A group whose only clause left matches anything and whose inputs are made up prints as a plain definition, with input names its body does not use. Main's pattern printer has no `parensIfNeeded` and breaks constructor arguments onto lines, so clause heads use their own one-line printer (`clauseHeadPattern`).
- Hover on a pattern that is its input's own name answers the input's type.
- `l4 render` lays a group of one input out as one list of cases ("if it is Red: 1 / if it is Green: 2 / otherwise: 3"); at `ee407387b` it rendered "otherwise: \_\_pm_fallthrough_0" with a "where" entry for it, and "pm arg 1" for an input with no `GIVEN`. A group over several inputs keeps a "where" entry, named for the clauses it holds ("The result of clause 2").

Left out, and why:

- The fixity fixtures and tests: main has no `@infixl`.
- Unstable's note in `specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §14.7: main has no such file; this file is main's record.
- `restoreMixfixPatterns` in `MultiClausePrintSpec`'s pipeline: not on main; the spec prints as main's REPL does.

Adapted for main:

- The trace test reads `l4 trace` (DOT), because main's `l4 run` prints no trace.
- The hover harness pins positions per fixture.
- The catch-all batch fixture passes a fixed colour to its group: main's batch wrapper declares a record whose fields share the export's input names, and on main a function whose input type nothing fixes is then ambiguous between the input and the field, with or without this change.

Measured on this branch against `ee407387b`, with the four review rounds' probes:

- `l4 batch` on `tests-cli/fixtures/batch-multi-clause.l4` did not re-parse at `ee407387b` (main's printer wrote `… THEN GreenIN  CONSIDER`), and `batch-multi-clause-capture.l4` failed `l4 check` there ("multiple definitions for the identifier b"); both now run and answer as their clauses say. The ditto, tab and catch-all fixtures already ran there and answer the same.
- `l4 run` against the REPL, over 198 probe files: of the 85 that check and evaluate, 81 give the same answers; the REPL fails to type-check the other four (three mixfix probes, and one with a hand-written nested CONSIDER), exactly as at `ee407387b`, because main's printer has no mixfix restoration and mis-prints that CONSIDER.
- `l4 batch` over 66 probe and input pairs: 49 answer as unstable's build with #581 does; the other 17 fail loudly (an error row, or a module that does not check or parse on main) exactly as at `ee407387b`, for reasons outside this change (no fixity declarations, section `GIVEN` or local shadowing on main; main's batch wrapper and how it reports a row's error; main's printing of records, `IF`, mixfix calls and one hand-written CONSIDER). None of these 66 gives a different successful answer.
  That holds for these pairs only: on main, `l4 batch` already answers differently from `l4 run`, with status success, for a decimal longer than a `Double` holds (the printer rounds it; `unstable` prints it exactly since `35d7b63b3`) and for a string input containing a newline, in rules written without clauses too.
- `l4 run --json` reported an evaluation error as the Haskell `show` of the exception, which since the #569 carry includes the group's internal `MkPmGroup` record. It now uses `prettyEvalException`, as `unstable` does (`75e08b55e`), so it reads "No clause of `price` matches these inputs" (`jl4/app/L4/Cli/Run.hs`, test "reports an evaluation error in JSON in the drafter's terms").

Tests: `jl4-core/test/MultiClausePrintSpec.hs` (19 examples: each module prints, re-parses and answers the same, with no generated name in the printed text), the `l4 batch` cases in `jl4/tests-cli` (eight, and one pending: the printer indents the later lines of a string that spans lines, in every rule, as on unstable), the `l4 render` and `l4 trace` cases, `not-ok/tc/pattern-matching-clause-inputs.l4`, `ok/pattern-matching-input-names.l4`, the second case in `ok/pattern-matching-fallthrough-name.l4`, and the hover positions for `lsp/hover/multi-clause-hover.l4`.

## Refusing an @export of clauses with no GIVEN (ruling M2, from #587)

Unstable PR legalese/l4-ide#587 (commit `3dee6cc3a`, on unstable) is carried as one commit.

Where it lives:

- `jl4-core/src/L4/TypeCheck.hs`: `refuseExportedClausesWithoutGiven` (`:822`), called from `inferTopDecl` (`:636`); the message (`:4409`).
- `jl4-core/src/L4/TypeCheck/Types.hs:82`: the error `ExportedClausesWithoutGiven`, whose range (`:280`) is the `@export` annotation's.
- `jl4-core/src/L4/Export.hs:440`: `isExportedDecide`, now polymorphic in the pass, so the checker can ask it before resolution.

Behaviour:

- `l4 check` refuses an `@export` of a definition written as clauses with patterns, one clause or several, that has no `GIVEN`: "`size` is published with @export, but its inputs have no names: add a GIVEN that names and types each one.", at the `@export`.
  It fires when the definition has a `PmMatrix` with `synthesizedScrutinees` and no `GIVEN` at all; a `GIVEN` that names the wrong number of inputs gets `ClausePatternCountMismatch` only.
- It asks the question main's publication asks: `isExportedDecide` and `buildExportedFunction` (`Export.hs:171`) both read `parseDescText`'s `isExport` flag from the definition's `@desc`, so `@export`, `@export default`, and a `@desc` whose first word is `export` or `default` all count.
- Main has no `isExportPublicationRefusal`, and no Blawx or relational lowering, so unstable's assumption about those does not arise here.
- The error fails the check, so `l4 run`, the REPL and `l4 batch` refuse the file, and jl4-service rejects the deployment ("Update rejected: compilation failed: …", through `blockingErrs`, `jl4-service/src/Compiler.hs:202`).

Measured on this branch against `36c549226`:

- `size.l4` (three clauses, no `GIVEN`): at `36c549226`, `l4 run` and the REPL answered 5 for `size Green 4`, `l4 batch` failed inside its wrapper with a type error, and jl4-service published the inputs `input 1` and `input 2`, typed "object", and answered 422 "#EVAL produced function closure". Now run, batch (exit 1, "type checking failed") and the REPL refuse it, and the deployment is rejected.
- `one.l4` (`@export DECIDE discount 0 IS 1`): at `36c549226`, run and the REPL answered 1, `l4 batch` answered 1 for `{"input 1": 0}`, and jl4-service published `input 1` as "object" and answered 422. Now all four refuse it.
- The same three clauses with a `GIVEN`: 5 under run, batch and the REPL, before and after; jl4-service publishes `c` ("string") and `n` ("number") and answers 5.
- Every file under `jl4/examples`, `jl4/tests-cli`, `jl4/experiments` and `doc` that publishes something (43 with the two new corpus files) checks the same way on both binaries; the new error fires only in the new not-ok file.

Tests: `not-ok/tc/pattern-matching-export-without-given.l4` and `ok/pattern-matching-export-given.l4`, whose goldens equal unstable's except that main's schema writes `n` as `{"$ref": "#/$defs/NUMBER"}`; and the jl4-service cases "refuses a module that @exports a clause group with no GIVEN" and "publishes the same clause group with a GIVEN, under the names it gives".
User documentation: `doc/reference/errors/README.md` ("An @export of clauses with no GIVEN") and one sentence under "Syntax" in `doc/reference/functions/multi-clause-DECIDE.md`.

## Review round 2 (items 1, 2, 3, 5 and 6)

The second review of #545 asked for six changes; item 4, literal patterns in the missing-case check, is under "Literal patterns (review round 2, item 4)" below.
Items 1 to 3 were made for unstable first, on branch `fix/clause-group-round3`, merged into unstable as legalese/l4-ide#604 (`64e917f1d`, `cdd3e5515`, `cb1167363`, on unstable); item 5 is legalese/l4-ide#591 (`635507a96`, on unstable); item 4 is legalese/l4-ide#605 (branch `fix/clause-literals`, merged into unstable on 2026-10-10 as `539cad5fd`); none of these commits is on this branch.

Item 1, overloads.
A run of bare-name clauses whose names differ is grouped by the parser, which cannot tell `TRUE` / `FALSE` from two overloads told apart by their types.
`separateOverloads` (`TypeCheck.hs:274`), called from `checkProgram` (`:200`) once the module's types and constructors are in scope and before the definitions' signatures are scanned, turns a group whose patterns are all bare names, none of them a constructor, back into the definitions it is made of: the first with the group's signature and annotation, the rest with no signature, each located from its clause's head to the end of its body (since round 3, each with its own clause's head, `AKA` and annotations).
A group with any constructor name stays a group, a misspelt one included.
Measured: the `show n` / `show b` file failed to check at `6d0146f27` and now gives `show 3` 4 and `show TRUE` TRUE, as main (`71ebf5ca1`) does; `ok/pattern-matching-overloads.l4` pins it.

Item 2, linear parsing.
Every clause of a run the group parser turned down was then parsed as a definition of its own, where the group parser read the rest of the run again, so a file of n lines `f x MEANS i` took time quadratic in n.
`decidePatternMatch` now records the positions of a run it turns down (`turnDownRun`, `Parser.hs:1060`) and fails at once at any of them (`runTurnedDown`, `:1066`); every suffix of a run turned down is turned down too.
The body of a clause is parsed once per position (`clauseBody`, `:982`; `memoClauseBody`, `:1022`), so an ordinary definition replays the body the group parser read.
Both live in `ClauseMemo` (`:988`), a layer below megaparsec in `Parser` (`:69`) that backtracking does not undo, run by `runJl4Parser` (`:2841`).
On unstable the same replay is `memoGroup` (legalese/l4-ide#582), which also serves bracketed groups; main has no `memoGroup`, so `ClauseMemo` holds only these two tables, and main has no switch to turn the memo off for a comparison run.
Measured, `l4 check`: 1,000 lines took 29.5 s at `6d0146f27`; now 2,000 take 0.38 s and 4,000 take 0.73 s.
`PatternMatchParserSpec` required 1,000 lines to parse in less than 8 times the wall-clock time of 250; since round 3 it compares CPU time for 250 and 2,000 lines.

Item 3, the clause after a new name.
`checkClauseMatrix` resolves the patterns even where the missing-clause analysis stands down (a list, a `MAYBE` value, an `EXACTLY` it cannot read), and finds the first clause whose patterns all match anything because some are new names (`newNameCatchAll`, `TypeCheck.hs:1068`).
`warnUnreachableClauses` (`:1164`) gives the clauses after it one warning, `AfterClauseBindingNewName` (`Types.hs:132`; message at `TypeCheck.hs:4615`): "This clause of `colour` is never used, because the clause above it with the new name `Gren` matches every input."
Main has no hint for a name close to a value, so there is no CONSIDER-worded hint to translate, as there was on unstable.
This keeps ruling M1's condition: main warns only about clauses after one that matches every input, and a new name does; a repeated clause still draws no warning.
Measured: Red / Gren / Blue checked clean at `6d0146f27` (`colour Blue` gives 2) and now warns; so does a group over numbers with `other`.

Item 5, the clause wording after a reload.
The evaluator words a value no clause matches from `pmSynthetic`, a mark on the annotations of the generated CONSIDERs.
jl4-service's `bundle.cbor` used to write every annotation as `()`, so a restarted service had lost the mark; this item made `Serialise Anno` keep it and nothing else (`Syntax.hs:1110`).
Since legalese/l4-ide#666 a restart compiles the stored sources again, as a deploy does, and reads no cache, so the desugarer sets the mark again; the instance stays behind `jl4-core`'s `serialise-support` flag (`jl4-core.cabal:28`), whose description says nothing in this repository uses it now.
`IntegrationSpec` ("after a restart", "words a rule written as clauses as it did before the restart") asks a rule written as clauses for an input no clause matches, on a fresh deployment and on a restarted one, and wants the same words.
`SerialisationSpec` went with the cache.

Item 6: the `l4 render` test in `jl4/tests-cli` drops carriage returns before matching two lines, for Windows.

Also from the review: the user documentation says clause groups are top level only and cannot have a mixfix head; this spec's source, `PATTERN-MATCHING-SPEC.md`, moved to `specs/done/`; the bench links in the ruling lines are replaced by "ruled by Meng"; and the glossary has an entry for clauses.
Not done here, for later: literal patterns in `jl4-mlir`, which compile as "always matches"; semantic tokens and go-to-definition inside a clause group; and the release notes.

## Review round 3 (the refutation of round 2's fixes)

A refuter probed the round-2 fixes on unstable and found three defects that this branch had too; each was fixed on unstable first, on `fix/clause-group-round3` (legalese/l4-ide#604; `fd4209700`, `0c1844c22`, `182dff94e`, on unstable), and carried here as `8e4c920ca`, `05559e4ec` and `2113516a1`.
A second refuter pass found that the L2 fix made the parse quadratic in the number of definitions (F1, below), fixed on unstable as `99f9f9075` and here as `67d0903c2`.

S1 and L1, the overloads' own annotations.
`separateOverloads` gave the first definition the first `AKA` written on any clause, and the later definitions no `AKA`, no `@desc` or `@export`, and no `@nlg`.
Measured at `b1002d9af`: `DECIDE f n IS n + 1` / `DECIDE f m AKA g IS m > 3` gave `g 5` 6, the first overload's answer, with no diagnostic; with an `AKA` on each, the second was not found; with an `@export` above the second, `l4 batch` said "no @export functions found in module"; an `@nlg` above it was "Not attached to any valid syntax node".
Each clause now keeps its head as written, its `AKA` and the `@desc` or `@export` above it in the clause matrix (`PmMatrixClause`, `Syntax.hs:478`), and the annotation passes give a later clause of a group the `@desc` or `@export` and the `@nlg` above it (`claimLaterClauseDescs` and `claimLaterClauseNlgs`, `jl4-core/src/L4/Parser/ResolveAnnotation.hs:755` and `:286`; until `2dd411963` only for a run of bare names).
`separateOverloads` gives each definition its own clause's head, `AKA` and annotations, and the printer writes each clause's own `AKA` (`writtenClauses`, `Print.hs:314`).
Main's printer prints no `@desc` and no `@nlg` for any definition, and `l4 batch` finds its `@export` on the checked module before printing it, so the printer change here is the `AKA` alone; on unstable the printer writes the `@desc` too.
Measured on this branch: `g 5` is TRUE under `l4 run`, `l4 batch` (through an exported rule that calls `g`) and the REPL; the two-`AKA` file gives 6 and TRUE; `l4 batch` finds the `@export` on the second overload, and then evaluates the first overload of that name (see the known limit below); the `@nlg` is attached.
In a group that stays a group, an annotation written between two clauses is used by nothing, and since `2dd411963` it draws a warning, one at each annotation (`ClauseAnnotationUnused`, `Types.hs:154`, from `warnLaterClauseAnnotations`, `TypeCheck.hs:1154`, called by `checkClauseMatrix`): "This @export is above the second clause of `colour code`, where it is not used."
The second line says where that kind of annotation does go (`place`, `TypeCheck.hs:4655`): an `@desc` or `@export` is told to come from "above its GIVEN" (from "above its first clause" in a group with no `GIVEN`), and an `@nlg` from "the line above its first clause".
Before that, the `@nlg` in `DECIDE k Red IS 1` / `@nlg the green value` / `DECIDE k Green IS 2` drew "Not attached to any valid syntax node" at `b1002d9af` and nothing from `8e4c920ca` on (measured at `2113516a1`), and an `@export` there drew nothing at either.
Overloads reach `checkClauseMatrix` without a matrix, so theirs draw none.

A refuter then found the warning wrong in three ways, fixed on unstable as `887dcb763` and here as `b42394622`.
A1, the rule's own `@nlg`.
An `@nlg` on the line above the first clause is the rule's, and the group did not use it.
The reason, read in code and not measured: the group's head is the first clause's, and the annotation pass gives it a region that ends before the comment, because the inputs of the head form are the `GIVEN`'s, located up in the signature (`givenInputBinding`, `Parser.hs:1194`).
`HasNlg Decide` now claims it for the head in the head form's region (`claimFirstClauseNlgs`, `ResolveAnnotation.hs:264`, called at `:248`).
Measured with a control build that skips that claim: `#EVAL code Green` renders "`code` with `Green`", where with the claim it renders "the code of `c` with `Green`".
A2, the annotations above the first clause are not the second clause's.
`claimLaterClauseDescs` matched every `@desc` and `@export` that ends before the later clause's head, so one the first clause had left (a `@desc` between the `GIVETH` and the first clause, which belongs to no rule) was counted as above the second clause and warned.
It then took only those that start after the line of the clause above (`ResolveAnnotation.hs:755`), as `claimLaterClauseNlgs` already did; round 4 replaces that test (see below).
Measured with a control build without that bound (and with A3's fix also disabled): a `@desc` between the `GIVETH` and the first clause of `steps` draws "This @desc is above the second clause of `steps`", and an `@export` between the `GIVETH` and the first clause of `hops` draws the same for `hops`.
A3, one warning for each.
`PmMatrixClause` held one `Desc`, so several `@desc` and `@export` lines stacked above a later clause were reduced to one and drew one warning between them.
It holds `clauseDescs` and `clauseNlgs`, every one written between the clause above and this one, and `warnLaterClauseAnnotations` warns at each; a separated overload still keeps one `@desc`, as a definition does (`pickDesc`, `ResolveAnnotation.hs:882`).
Measured with a control build that keeps only the first `@desc`: the stacked group draws three warnings, where each of the four annotations should draw one.
The group now reads its `@desc` and `@export` as a plain `DECIDE` with the same layout does: one above the `GIVEN` is the rule's, and one between the `GIVETH` and the first clause is used by neither and draws no warning for either.
A fourth finding, that a warning from an imported module shows in `l4 run`, needed no change: `l4 run` prints the diagnostics of every module in the run, each under its own `File:` line (measured on this branch with a module that imports a library with an `@desc` and an `@export` between clauses, and with one that imports a group missing a case).
A difference from unstable that the fixture shows: main has no `signatureBeforeKeyword`, so a plain definition's `@nlg` between its `GIVETH` and its `DECIDE` lands on the `GIVETH`'s type name (`NUMBER` in `GIVETH A NUMBER`; read in `l4 ast`), and `#EVAL hue Green` renders "`hue` with `Green`" in `ok/pattern-matching-first-clause-annotations.nlg.golden`, where unstable renders "the hue of `Green`".
The group's `@nlg` lands on its head and is used, which unstable's plain definition does too.
Tests: `ok/pattern-matching-later-clause-annotations.l4` for the answers and that nothing is published, `ok/pattern-matching-first-clause-annotations.l4` for the annotations above the first clause (each beside a plain twin), and five `PatternClausesMissingSpec` cases for the warnings; main's golden harness prints warnings, so `ok/tests/pattern-matching-later-clause-annotations.golden` records them as well.
Each of the three fixes fails a test with the fix disabled: A1 the fixture's `nlg.golden`, A2 "does not warn at the annotations above a group's first clause", and A3 "warns at each of several annotations stacked above a later clause".
Test: `ok/pattern-matching-overloads-own-annotations.l4`, and the jl4-service case "publishes the overload whose @export is written above it".
Its second `AKA` is `c` here and `b` on unstable: main reads the input `b` in `DECIDE shown b IS b AND TRUE` as ambiguous with an `AKA` named `b`, where unstable lets the input win.
On main the `@nlg` above the second `shown` is used for that overload's call only ("`b` is shown with `TRUE`", and "`shown` with 3" for the first); unstable uses it for both.
A known limit, before and after: `l4 batch` and jl4-service find an overloaded `@export` by its name, and evaluate the first overload of that name.
With the `@export` on the second `twice`, `l4 batch` given `{"b": 3}` answers 6, from the number overload, and given `{"b": true}` fails with "Expected JSON number but got: Bool True" (measured on this branch and on unstable); the refuter found jl4-service answering "Parameter 'n': missing required parameter" on unstable, and the limit on unstable's base and on main.

L2, the parse error a turned-down run reports.
`decidePatternMatch` failed at once, with no error of its own, at a clause of a run it had turned down, so megaparsec reported a nearer error than reading the run again would have.
Measured at `b1002d9af`: `f x MEANS 1` / `f x MEANS 2` / `f (x) MEANS 3` / `f x MEANS 4` / `g y MEANS 5` gave its error at 3:3, and at 5:1 with the run memo turned off.
The attempt now records the error it failed with at every clause of the run (`recordRunFailure`, `Parser.hs:1079`), and fails with it at any of them; `ClauseMemo` keeps an `IntMap` from position to that error.
Measured with a control binary built with `runTurnedDown` (`Parser.hs:1066`) returning nothing, which is the parser without the run memo: on the refuter's 12 parse probes, its 21 fuzzed files on which the memo had changed the output, and the new fixture, `l4 check` gives byte-identical output and exit code with and without the memo; at `b1002d9af`, 23 of those 34 differed.
Main has no switch to turn the memo off and no test comparing the two, so this comparison was made by hand.
Test: `not-ok/tc/pattern-matching-run-parse-error.l4`.

F1, the cost of recording that error.
`recordRunFailure` first recorded the error by rewriting the whole table of turned-down positions on every failed attempt, and every definition that is not a clause group fails one, so `n` definitions with different names cost time quadratic in `n`.
Measured, `l4 check` on 16,000 lines `f<i> x MEANS <i>`, user CPU: 3.68 s at `b1002d9af`, 24.50 s at `2113516a1`, 3.80 s at `67d0903c2`.
`turnDownRun` now puts the run's positions in a list of their own (`turnedDownRun`, in `ClauseMemo`), and the failure that follows at once records them with its error and empties it (`recordRunFailure`, `Parser.hs:1079`); a failed attempt that turned no run down records nothing.
Re-run at `67d0903c2`, the comparison with the memo-off control above is still identical on all 34 files.

L3, the linear-parsing guard.
It compared wall-clock time, and on a busy machine it failed (the refuter, on unstable: 12 failures in 60 runs with twelve jobs at once).
`PatternMatchParserSpec` now compares the process's CPU time for 250 and 2,000 lines, and fails at a ratio of 24 (linear is about 8, quadratic about 64).
Since F1 it also times definitions with different names, at 1,000 and 12,000 lines, failing at 24, twice linear, because at 250 and 2,000 lines F1's quadratic part was too small to show (measured on unstable: 8.4, where linear is 8).
With F1's recorder that test failed 3 runs of 3 on this branch (ratios 59.9 to 108.9); with the fix both guards passed 10 runs of 10 at a load average of about 8.
The parse-scaling probe (`etc/probe-parse-scaling.mjs`, on unstable, 1,000 and 4,000 lines, `l4 check`) gives 5.1 for different names and 4.0 for one name at `67d0903c2`, and 7.5 and 3.6 at `2113516a1`; it passes both.

Not carried, because main lacks what they changed: the wording of unstable's hint for a name close to a value (main has no such hint), and a sentence in `specs/done/PATTERN-MATCHING-SPEC.md` (main's copy has no sentence about overloads).
The user documentation's claim that the warning naming a new name "holds for every rule" is corrected: it is not given when a pattern of the rule does not fit its input's type, and not for a new name inside a larger pattern (`doc/reference/errors/README.md`).

A difference from main remains, by the rule round 2 asked for: a parameter spelled like a constructor keeps a run a group.
With `DECLARE Colour IS ONE OF Red, Green`, `DECIDE show Red IS Red + 1` / `DECIDE show b IS b AND TRUE` is a type error on this branch, where main reads two overloads (main's behaviour as the refuter measured it).

## Review round 4 (the refutation of the later-clause warning's contract)

A refuter probed the warning at `887dcb763` on unstable and found holes in what it claims to do.
They were fixed on unstable first, on `fix/clause-group-round3` (legalese/l4-ide#604; `7c3c9857e`, `35c57a026`, `dc33afa39`, `3c7c616fd`, on unstable), and what applies here is carried as `fb719cd6d` and `07a84815a`.

S1, the rule after a group.
After a rule written as clauses, an `@nlg` written above the next rule was swallowed when that rule had no `GIVEN`.
Measured with a control build of this branch without the fix: in `ok/pattern-matching-annotations-after-group.l4`, `#EVAL two` (a plain rule with no `GIVEN`) renders "`two`" and `#EVAL four` (a group with none) renders "`four`", where with the fix they render "the second rule" and "the fourth rule with `Green`".
The CONSIDERs and LETs a group is lowered to hold names that the parser made up (`generatedName`), which have no range, and a name with no range has no bound on the region it may claim, so it took every `@nlg` up to the next token that had one.
`HasNlg Name` now claims nothing for a name with no range (`ResolveAnnotation.hs:465`).
Unstable had a second cause that this branch does not: its `rawTokensAnno` kept the annotations after the last clause in the group's tokens, so the group's range ran over the next rule's `@nlg`; this branch's keeps them as trailing tokens (`d6594578b`).

S2 and L1, one rule for "between two clauses".
Which annotations counted as written above a later clause was decided by the clause head's line and column.
An annotation indented past the head's column drew no warning (S2), and an annotation inside a `WHERE` of an earlier clause was taken by the next clause and warned about (L1).
The clause matrix now keeps the range of each clause's body, `WHERE` included (`PmMatrixClause`, `Syntax.hs:478`, field `bodyRange`), and an annotation is between two clauses when it starts after the end of the clause above and ends before the head of this one (`betweenClauses`, `ResolveAnnotation.hs:315`, used by `claimLaterClauseDescs` and `claimLaterClauseNlgs`).
Measured with a control build without that rule and without the S1 fix: the two new `PatternClausesMissingSpec` cases fail, and so does the json schema golden of `ok/pattern-matching-later-clause-annotations.l4`, because the indented `@export`, taken by no clause, then publishes the rule after the group (`helped`).
An `@nlg` inside a `WHERE` of a clause was "Not attached to any valid syntax node", where a rule written as one definition attaches it to the helper; see "R1" below for the second half.

N1 and N2, an annotation after a clause's body.
A second pass of the refuter found that `betweenClauses` took an annotation written after a clause's body on the same line, `DECIDE f n IS n + 1 @export published?`, for the next clause's, because it starts after the end of the clause above.
Measured on this branch at `93be32d32`: `l4 batch` of that line followed by `DECIDE f b IS b AND TRUE` found the second overload published under it (there is no function for the rule written as one definition), `#EVAL g TRUE` rendered the inline `@nlg` of the first overload, and a group with an `@desc`, an `@nlg` and an `@export` after its first three bodies drew "This ... is above the second clause", and the third and the fourth.
An annotation is between two clauses only if it starts on a line after the one where the clause above ends (`betweenClauses`, `ResolveAnnotation.hs:315`); one on that line stays with the clause.
Fixture `ok/pattern-matching-inline-annotations.l4` (unstable's): its nlg and schema goldens fail with the line test replaced by the position test alone, and so does the `PatternClausesMissingSpec` case "does not move an annotation written after a clause's body to the next clause".

R1, a definition in the `WHERE` of a clause.
An `@nlg` above a definition in a `WHERE` was "Not attached to any valid syntax node" in every clause of a group, the last included, where a rule written as one definition attaches it to the helper (measured at `93be32d32`: the refuter's `r02` and `c01`, and the last clause alone).
A group is lowered to a `LET` whose declaration binds the clauses after the first and whose body is the first (`bindFallthrough`), and the descent visited the declaration before the body, so the clauses were visited last to first, against the order in which the regions between neighbouring nodes are taken; read in code, not measured, a declaration that precedes its body in the tree and follows it in the file then has an empty region. What is measured is that visiting the body first attaches the `@nlg`.
`bindsLaterClauses` recognises that `LET`, and the descent into it takes its body first (`HasNlg` for an expression, `ResolveAnnotation.hs`).
Visiting the clauses in order let a name of a clause take an `@nlg` written directly above it, the pattern `other` for the one between the second and third clauses, and the warning "This @nlg is above the third clause" was lost, so the `@nlg` between two clauses are claimed first (`HasNlg Decide`).
Measured: the whole of `jl4-test`, 956 examples, has one failure with the change, the one it fixes (the `@nlg` in a `WHERE` of `not-ok/nlg/nlg_group_neighbours.l4` is no longer "Not attached").
Each change disabled alone: the order of the descent fails `nlg_group_neighbours`; claiming the `@nlg` between clauses first fails three `PatternClausesMissingSpec` cases (the first, the stacked one and the indented one).
The `@desc` half is not carried: `HasDesc` for an expression is `pure` on this branch, so an `@desc` above a definition in a `WHERE` reaches no helper, in a group or in a rule written as one definition. What it reaches instead is the next top-level rule, see "The next rule's `@desc`" below.

The next rule's `@desc`.
Because the bodies of the clauses are not read, an `@desc` or `@export` inside a group that nothing of the group claims was taken by the top-level rule after it, which takes every one written before it and within 8 columns of its start (`descPrecedesNode`, `topLevelColumnSlack`).
Measured at `860824ffc` on `ok/pattern-matching-unclaimed-annotations.l4`: an `@export` between a group's `GIVETH` and its first clause published the group after it, under the description "between the `GIVETH` and the first clause", and an `@export` above a definition in a `WHERE` did the same to the next one; the refuter's `r04`, with an `@desc`, made a helper's description the group's after it.
`dropUnclaimedWithinGroup` (`ResolveAnnotation.hs:741`) runs after the group's own claims and drops the `@desc` and `@export` still unclaimed inside the group's range, so a group's `@export` between its `GIVETH` and its first clause stays unpublished, as ruled in round 3, and no other rule gets it.
The same defect remains for a rule written as one definition, on this branch (an `@desc` above a definition in its `WHERE` became the description of the rule after it) and on unstable (an `@export` between a plain rule's `GIVETH` and its `DECIDE` published the rule after it, measured at `9c3ae1088`); unstable's groups do not have it (`r04` and the layout above attach or park the `@desc` on the helper or a generated node, measured at `9c3ae1088`).
Measured: `jl4-test`, 964 examples, passes with the change, and `l4 check` over 341 files prints the same as before; with the drop disabled alone, the fixture's schema golden fails.

L5 and L2, not carried.
On unstable the group's head form no longer claims the copies of the `GIVEN`'s inputs (`addNlgGroupHead`), so an `@nlg` above the first clause and a herald on the same head collide there as on a rule written as one definition, and an `@nlg` on a `GIVEN` item of a group is attached.
That is not carried, for what it does here: measured in a build of this branch with that change, a rule written as clauses is claimed exactly as a plain rule is, and a plain rule's `@nlg` between its `GIVETH` and its `DECIDE` lands on the `GIVETH`'s type name (this branch has no `signatureBeforeKeyword`), so `#EVAL code Green` in `ok/pattern-matching-first-clause-annotations.l4` renders "`code` with `Green`" and round 3's A1 is lost.
So this branch keeps `claimFirstClauseNlgs` (`ResolveAnnotation.hs:264`, called at `:248`), and two things stay as they were.
A rule written as clauses reports an `@nlg` on a `GIVEN` item as "Not attached to any valid syntax node" where a rule written as one definition attaches it (L2; measured with `GIVEN c IS A Colour @nlg the colour %c%`).
An `@nlg` above the first clause together with a herald on the head draws no collision for a rule written as clauses nor for a rule written as one definition (L5; measured, no diagnostic for either).

L3, not applicable here.
Unstable's printer writes a stray later-clause `@nlg` back as a herald, so the re-checked module reports "Not attached" in place of the check's warning.
This branch's printer prints no `@nlg` for any definition, so a re-checked module has none.

Tests: three `PatternClausesMissingSpec` cases, "warns at an annotation indented past the head of the clause below it", "does not warn at an annotation inside a WHERE of an earlier clause" and "does not move an annotation written after a clause's body to the next clause" (35 cases in all at that point; the count in this tree is under "The missing-case warning"), and these fixtures: `ok/pattern-matching-annotations-after-group.l4` (S1), the indented group and the `WHERE` group added to `ok/pattern-matching-later-clause-annotations.l4`, `ok/pattern-matching-inline-annotations.l4` (N1, N2), and `not-ok/nlg/nlg_group_neighbours.l4` (the `@nlg` in a `WHERE`, now attached, and one after the last rule of the file).
They are unstable's fixtures, except that `nlg_group_neighbours.l4` is shorter here and one comment sentence of the first differs; unstable's `ok/pattern-matching-given-gloss.l4` is not carried, since it pins what is not carried.
Each fails with its fix disabled: the after-group golden without the S1 fix, the two cases of S2 and L1 with the S1 fix and the rule above both off (the same build), and the inline cases and fixture without the line test (a build with only that off).

## Literal patterns (review round 2, item 4)

The reviewer's item 4: let the missing-case check cope with number and text patterns instead of giving up (`hasOpaque`).
Designed and critiqued adversarially in the session that built it (those notes are not kept in the tree), built on unstable first (legalese/l4-ide#605, branch `fix/clause-literals`, on unstable's guard model, merged into unstable on 2026-10-10 as `539cad5fd`) and then here on main's own engine (ruling M1), in two commits that can be reverted alone, plus one per fix after the review of this build (see below).

What changed, 2026-10-09:

- `coveragePattern` (`TypeCheck.hs:1269`) reads a number or a piece of text, bare or under `EXACTLY`, as one value of its column (`CovLit`, keyed by `LitKey`, `:1216`: `1` and `1.0` are one key, as the evaluator compares them); `EXACTLY` of a value of the column's type as that value; `EXACTLY` of the column's own input as a wildcard; any other `EXACTLY` as a clause that counts for nothing on a number, text or date input (`isPrimitiveType`, `:2709`, after synonym expansion, `expandSynonymsIn`, `:1311`), and as a bail on any other input, or on any input when its expression mentions the input itself.
  The top-level column is classified by its type after substitution and synonym expansion; a nested position by its annotation, which the re-check resolves through its substitution before that is dropped, and which is expanded through synonyms the same way, so an `EXACTLY` of a constant at a number position inside a pattern counts for nothing too (since 2026-10-09, in step with unstable); an inference variable still left there bails.
  `hasOpaque` and `patternHasOpaque` are gone.
- `uncoveredRows` (`:1396`) takes the column count, so that no rows at all yield the one all-wildcard row; a row of wildcards ends the recursion; a column of numbers or text recurses into each key the rows name, in the order the rows first name them, and then into the wildcard rows for the rest of the column, which renders as the input's name (`renderRow`).
  Two tiers: the exact partition, and when that bails (the cap, the fuel, or a constructor it cannot enumerate below a key) the same engine over the rows without a number or a piece of text, with fresh fuel; a group with no number or text in it has only the first tier, and a group with a clause left out only the second.
- `prettyMissingPattern` (`:4698`) prints a number as its clause spelled it, from the token on its annotation (`literalAsWritten`, `:4728`): `1.50` stays `1.50`, `-1` keeps its sign, and `0.1234567890123456789` keeps every digit, where `prettyRatio` rounds past sixteen.
  A piece of text prints through `L4.Print`'s own printer, every printable character as it is and `"` and `\` escaped, because the lexer keeps only the decoded text and the token's own display would write `"São Paulo"` as `"S\227o Paulo"`; a text with a character that does not print keeps that Haskell-style form, which L4 reads back.
- `settleOneClause` (`:719`): a one-clause group with a number in it now gets a verdict, so its CONSIDER warnings are withdrawn.

Decisions, all assumed, not ruled, 2026-10-09, each kept so that it can be reverted alone:

- M-A: the exact partition when it fits, keyed gaps first and then the row with the input's name (`charge 1 Basic` / `level Basic` / `level Premium`, over a `Tier` that also has `Gold`, lists `1 Gold` then `level Gold`), in its own commit ("check: list every gap of a clause group over numbers or text exactly"); reverting it leaves option (b), the coarse list alone, with no number or text in any suggested clause (the engine commit's tests pin that state: the same table lists `level Gold` alone).
- M-B: no redundancy analysis on main, so ruling M1's condition stands: `g 0` / `g 0` / `g n`, `h 1` / `h 1.0`, and a clause after `EXACTLY n` draw no warning here, where unstable reports each as never used.
- M-C: the warning text is unchanged when the coarse tier answers; the user documentation says that a gap inside the table is then not listed.
- M-D: ~~a hand-written `CONSIDER` over a number or a piece of text still gets no warning (`checkConsider`'s gates are untouched), and the user documentation says that the two spellings of one rule differ; waits on Meng's ruling.~~ Ruled by Meng, 2026-10-09 (06:15 UTC), and built: a `CONSIDER` with a number, a piece of text or an `EXACTLY` in any arm is analysed by the clauses' engine as a group of one column with the scrutinee as its input (`considerWithLiterals`); a missing case renders as `WHEN … THEN` or `OTHERWISE` (`prettyMissingBranchLhs`, keys as the arms spell them, on one line), and an arm is redundant when the arms above it match everything it matches (`coveredBy`, by specialisation), an arm that matches anything never.
  It also fixes the defect the comparison with unstable found: main's own analysis read a literal or `EXACTLY` arm as matching anything, so `WHEN EXACTLY Red` / `WHEN Green` / `OTHERWISE` called `Green` redundant (`pick Green` is 2), and a `CONSIDER` whose only arm was `WHEN EXACTLY Red` passed and failed at run time.
  ~~A `CONSIDER` with none of them keeps main's own analysis (`considerWithoutLiterals`), unchanged.~~
  Ruled by Meng, 2026-10-09 (15:12 UTC), and built 2026-10-10: a `CONSIDER` written by hand goes to the clauses' engine with or without a number in it, unless an arm names a constructor of a `MAYBE` or a `LIST` (`armsNameUnlisted`, at any depth in the arm: `JUST`, `NOTHING`, `FOLLOWED BY`, `EMPTY`), which keeps main's own analysis, because the clauses' engine stands down at a constructor it does not list, where main's own analysis lists part of what is missing.
  Refined, ruled by Meng, 2026-10-12: the first build decided this by the scrutinee's type (`holdsUnlistedType`: could a value of the type, an argument, or a field of a type declared in the module as the scrutinee's type fills in its parameters, at any depth, hold a `MAYBE` or a `LIST`), which kept `WHEN Row v1 v2` / `WHEN Row v1 Gold` over a record with a `MAYBE` field on main's own analysis, where it is told ``WHEN Row `_` Basic`` after the arm that matches everything; no arm names the `MAYBE`, so the clauses' engine reads it and finds nothing missing.
  `holdsUnlistedType` and the import test below are gone; the one test is `armsNameUnlisted`, over the arms and the clauses' engine's own constructor families.
  `EITHER` is in the exception too, assumed, not ruled: `LEFT` and `RIGHT` are not in those families, so an arm that names one stands the clauses' engine down (`WHEN LEFT Basic` over `EITHER Tier Tier` is told `WHEN LEFT Gold` by main's own analysis, and nothing by the clauses' engine).
  So is a constructor of a type declared in another module, assumed, not ruled: a record declared here, `Paint HAS c IS A Colour, t IS A Tier`, with `Colour` (`Red`, `Green`, `Blue`) imported from another file and `Tier` (`Basic`, `Gold`) declared here, and the one arm `WHEN Paint Red Basic`, is told `WHEN Paint Red Gold` by main's own analysis and nothing by the clauses' engine, whose constructor families are this module's declarations.
  Measured on this branch's binary on 2026-10-13: the two clauses `f (Paint Red Basic)` and `f (Paint Green Basic)` draw no warning, and the one clause `f (Paint Red Basic)` draws that `CONSIDER`'s warning at the clause, as a one-clause group does.
  The arm `WHEN Paint col Basic` names no imported constructor, and is read by the clauses' engine, which tells it ``WHEN Paint `_` Gold``.
  A `CONSIDER` generated from clauses keeps the routing by numbers, text and `EXACTLY`.
  Where the two spellings of one rule agree and where they do not, measured on this branch's binary on 2026-10-13 with a clause group and a `CONSIDER` of the same rule in one file (probe files not kept in the tree):
  over enumerations declared in the same file, numbers, text and `EXACTLY`, both name the same missing case (the clauses as a `DECIDE` line, the `CONSIDER` as `WHEN … THEN` or `OTHERWISE`);
  a repeated enumeration value, number or piece of text is reported as redundant by the `CONSIDER` only (M-B);
  over a `MAYBE Colour`, `JUST Red` with `NOTHING` draws no warning from the clauses and `WHEN JUST Green` and `WHEN JUST Blue` from the `CONSIDER`, and so does `LEFT Red` with `RIGHT Green` over an `EITHER Colour Colour`, which lists four branches;
  a record with a field of an enumeration declared in another file (`Row Basic TRUE` and `Row Plus TRUE`) is listed by the `CONSIDER` only (`Row Basic FALSE`, `Row Plus FALSE`);
  the other way round, a record with a `LIST` field (`Row TRUE EMPTY` and `Row TRUE ys`) is listed by the clauses only (``Row FALSE `_` ``);
  a bare `LIST` input, or a bare input whose enumeration is declared in another file, gets no warning in either spelling.
  When the clauses' engine gives up on a `CONSIDER` that the ruling of 2026-10-09 (15:12 UTC) sent to it (past 64 rows or 10000 steps), main's own analysis reads that `CONSIDER` instead, assumed, not ruled, 2026-10-10, after a refutation pass found it silent: `Rec HAS f0, f1, f2` over six values with three arms has 208 missing values, of which ceeeca095 lists 108 and the build before this fallback none; on 150 random incomplete tables of 2 to 5 such fields, ceeeca095 warned where that build was silent 32 times, and this one never.
  The fallback brings back main's own analysis's cost with its answers: where ceeeca095 runs past 15 s on a table (5 of those 150; 30 s and 137 s for the two timed alone), so does this build, where the build before was silent at once; of those two, one ends with no warning and the other lists 24576 rows.
  A generated `CONSIDER` keeps the silent cap, as a group of clauses does.
  Not fixed, measured 2026-10-10: a missing-case warning at every level of a nested `CONSIDER` costs time cubic in the depth, because each diagnostic's context is searched for a type to resolve (`contextChanges`, which keeps the context shared when it finds none), and the context of a warning at depth k holds k levels, each holding every level inside it.
  100, 200 and 300 levels take 0.34 s, 2.24 s and 6.64 s here, and 0.44 s, 3.15 s and 9.37 s on unstable, which has the same code (a refutation pass measured 33 s and 44 s at 500); base unstable takes 0.06 s to 0.09 s, warning at no level; residency stays at 1 to 6 MB.
  Searching each level once would need an identity for a level, or a new field in the context's type, which every diagnostic is built with, so it was left.
  Measured again on this branch's binary on 2026-10-13, nests with a `WHEN` at every level and no `OTHERWISE`: over numbers, 100, 300 and 500 levels take 0.5 s, 7 s and 37 s, and over an enumeration (`WHEN Red` at every level) 0.5 s, 11 s and 56 s; main takes 0.3 s over numbers at 500 levels, with no warning, and exceeds 4 GiB over an enumeration at 100 levels, where it was stopped after 6 s; with an `OTHERWISE` at every level, 500 levels over numbers take half a second.
  The user documentation states it as a limit (`doc/reference/functions/multi-clause-DECIDE.md`, "Limits").
  It fixes smucclaw/l4-ide#1030: main's own analysis read a constructor's fields as one set of constraints, so `WHEN fab` / `WHEN faz qux qux` was told six of the eight missing `faz` arms, and with those six added nothing, though `faz bar qux` and `faz baz qux` still failed at run time; the clauses' engine lists ``faz bar `_` ``, ``faz baz `_` ``, `faz qux bar` and `faz qux baz`, and then the two.
  Measured with a fuzzer that is not kept in the tree (seeds 91 to 94, 600 groups each): the clause form and the `CONSIDER` form of a group disagree on whether it warns 12 times on the build before that ruling, 3 times with the exception decided by the scrutinee's type, and once with it decided by the arms (`C-FALSE-INCOMPLETE` 11, 2, 0; `C-RESIDUE-SILENT` 373 on all three).
  The two it fixed were main's own analysis asking for cases after an arm that matches everything (`WHEN Row1 v1 v2` / `WHEN Row1 v1 TRUE` over a `LIST` and a `BOOLEAN` was told ``Row1 `_` FALSE``; `WHEN Row2 v1 v2` / `WHEN Row2 Gold v2` over a `Tier` and a `MAYBE` was told ``Row2 Basic `_` `` and ``Row2 Premium `_` ``), and no arm of either names a `MAYBE` or a `LIST`.
  The one left has the single arm `WHEN Row (JUST m) TRUE`, which names `JUST`, so main's own analysis reads it and lists ``WHEN Row (JUST `_`) FALSE`` and not the `NOTHING` cases, where a rule written as clauses stands down.
  A redundant arm prints as written (`prettyBranchAsWritten`): the generic printer wrote the redundant `WHEN 1.0` after `WHEN 1` as `WHEN 1`, naming the other arm.
- Beyond the design, in its own commit: an `EXACTLY` whose expression mentions the input itself, such as `EXACTLY (n PLUS 0)`, which matches every `n`, stands the group down on any input, because the design's argument for leaving such a clause out (it matches one value of the column per value of the other columns) does not hold for it; by the algorithm as designed, `f (EXACTLY (n PLUS 0))` / `f 0` would have suggested `f n`, a clause that would never be used.
  Unstable's first fix for the same hole stood the group down when the expression named any input, in any column; main's rule is the narrower one, and it holds (an expression naming only other inputs still matches one value of its column per value of theirs: `f a (EXACTLY a)` / `f 0 b` lists `a b`, and `f 1 2` has no clause).
  Unstable adopted it on 2026-10-09 (`b6f3b34cf`, on unstable), so both branches now use this rule.

Measured on this build, in `jl4-core/test/PatternClausesMissingSpec.hs` and in probe files that are not kept in the tree:

- The cap: 63 keys × `Basic` over `Tier` list the 63 keyed rows and `n t`; 64 keys would list 65, over the cap, so the coarse tier lists `n t` alone; the enumeration control (E1..E64 × `Basic`) still lists 64 rows and falls silent at 65.
- The fuel: a row of wildcards ends the recursion, so the nine-input `pick` table (each input tested for `Red` in one clause and for `Green` in another), which used to run out of steps, lists `Blue` nine times, and its twin over numbers lists `n1 … n9`; a cross table of 100 keys on each of two inputs lists `n k`.
  None of the tests reaches the 10000-step limit on this build; it is kept as a guard.
- Residues against unstable, all predicted by the design: `MAYBE` and `LIST` values are read here only as far as the analysis need not tell them apart (`show NOTHING` / `show (JUST 0)` is silent; `f (JUST 0)` alone suggests `f m`, where unstable lists `NOTHING` and ``(JUST `_`)``); the one-clause `f Red (JUST x)` keeps its CONSIDER warning (`WHEN Green THEN`, `WHEN Blue THEN`), where unstable lists three clauses; `@nonexhaustive` is a lexer error here.
  Not predicted, and cosmetic: unstable listed rows in another order (by how many numbers or texts they name, and in its engine's order among rows that name none: `E63 Premium` … `E1 Premium`, `Blue n` before `Red n`); since 2026-10-09 it lists them in main's order (`0cb94ec8e`, on unstable).
  Not a difference in the check: `§` followed by an indented `GIVEN n` is a section binder on unstable, an assumed value that is not the definition's input, and the definition's own `GIVEN` here, so the same clauses `f 0` / `f 1` under it list `f n` here and ``f `_` `` there, and `f 0 IS n PLUS 100` gives `100` here and asks for `n` there.

Fixed after the adversarial review of this build (2026-10-09), one commit each: a text key printed with the lexer token's Haskell-style escapes (`"S\227o Paulo"`); a number input declared under another name (`DECLARE Age IS A NUMBER`) stopped the group on an `EXACTLY` of a constant instead of counting it for nothing; the coarse tier re-ran the same rows for a group with no number or text; and the tests the review asked for: `EXACTLY n` beside an enumeration (`f 0 Red` / `f (EXACTLY n) Green` lists `0 Blue`, `n Red`, `n Blue`, and reads as `n c` alone without the own-name case), a `MAYBE` below a key that reaches the coarse tier (`f 0 (JUST x)` / `f 1 m` lists `n m`), the silence boundary for lists, `MAYBE` values and another file's enumeration, the nested `EXACTLY` under a record's field, a negative key, and keys written under `EXACTLY`.

Aligned with unstable after its own review (2026-10-09), one commit each: an `EXACTLY` of a constant at a number position inside a pattern counts for nothing, as at the top level, where it stood the group down because the re-check's substitution was dropped before the position's type was read (`f (Box (EXACTLY zero)) Premium` / `f (Box n) Basic` lists ``(Box `_`) Premium``; the test that pinned the silence now pins the warning); and a field declared under another name for a number is a number position, as an input already was.
And, after the refutation of unstable's `3369077b2` (on unstable) the same day: a group with a clause left out gets the coarse list alone, because the exact partition could list a keyed gap the left-out clause covers (`f 2 "b"` / `f (EXACTLY two) s` / `f 1 s` listed `2 s` and `n s`, and every `(2, s)` meets the second clause; `g (EXACTLY b) (EXACTLY a) Standard` / `g a "c" Plus` / `g "c" "a" p` / `g a "c" Gold` listed `"c" "c" Standard`); each coarse row still holds a value no clause matches, since a left-out clause matches one value of its position for each value of the others.

Tests for literal patterns, in `PatternClausesMissingSpec`, by group: numbers and text with and without a catch-all (`describe`, `code`, `sign`, `half`); `EXACTLY` of a number, of a value of the input's type, of a constant on an enumeration input, over another file's enumeration, over a `MAYBE` value, of the input's own name (alone and beside an enumeration), of a constant on a number input and under a record's field, and of an expression that mentions the input itself or another input; tables keyed by a number, by text, by a number beside an enumeration, by two numbers, and the gap under one key before the rest; one-clause groups over a number, with and without an enumeration beside it; a record with a number field; the silences for lists, `MAYBE` values and another file's enumeration and their boundary; the coarse tier for a `MAYBE` under every clause's number and below a key; a repeated number and `1` after `1.0`; a key's first spelling, every digit, the sign, `EXACTLY`'s spelling and a text key's characters; the cap at sixty-four rows against its enumeration control; the nine-input tables over enumerations and over numbers; a group without a `GIVEN`; a synonym of `NUMBER`, as an input and as a record's field; and the coarse list alone when a clause is left out, for an `EXACTLY` of a constant and for one that names only other inputs.

Tests for a `CONSIDER` written by hand, in the same file (`considerSpec`, eight cases; the ruling of 2026-10-09, 06:15 UTC): the arm after `WHEN EXACTLY Red` is reached and the `CONSIDER` whose only arm it is lists `Green` and `Blue` (the defect described above; both red on `7bbe2499f`); `OTHERWISE` for a number and for a text; a repeated number as a redundant arm; the gap under a key in a record, spelled as the arm spells it; `EXACTLY` of a constant over a number and over an enumeration; an `EXACTLY` that mentions the scrutinee; and the coarse list alone when an arm is left out.
And for one with none of them (`plainConsiderSpec`): a constructor no arm names is written with a `_` per field, and every missing combination of a constructor's fields is listed, before and after the asked-for arms are added (smucclaw/l4-ide#1030, the ruling of 2026-10-09, 15:12 UTC; red on `ceeeca095`); a `CONSIDER` over a type with a parameter; a record with a `MAYBE` field read by the clauses' engine when no arm names `JUST` or `NOTHING` (`WHEN Row v1 v2` / `WHEN Row v1 Gold` warns of no missing case, `WHEN Row m Basic` lists ``WHEN Row `_` Gold``; the ruling of 2026-10-12, red on `e195a903c`, which lists ``WHEN Row `_` Basic`` after the first); and the same record with the one arm `WHEN Row NOTHING Basic`, which keeps main's own analysis and lists `WHEN Row NOTHING Gold`.

Corpus: `ok/pattern-matching-literal-clauses.l4` is new, with its golden recording its `#EVAL`s and 14 missing-case warnings (main's golden harness prints warnings); `ok/pattern-matching-one-clause-fallback.l4`'s number example became the `MAYBE` one; `not-ok/tc/pattern-matching-export-without-given.l4`'s golden gains the warning for `discount 0`.

## Review round 5 (the pre-review of 2026-10-13, carried from #631)

The pre-review of this branch at `5f9409a37` found two ways a drafter's meaning was lost without a good message, and one thing nothing tested.
Each was fixed on unstable first, in legalese/l4-ide#631 (branch `fix/mixfix-clause-error`, merged into unstable as `f48a0ed75`; its commits are `c8c9955a4`, `b42fb4756` and `921a181f9`, on unstable), and carried here as three commits of their own.

A clause written in a mixfix rule's form.
A mixfix rule such as ``c `costs` n MEANS n`` is one definition, found by its word wherever it is called, and has no clauses.
A line written in its form for one case of it was read as a clause of a rule named after its first word.
Measured with the `l4` built from `a022af716` (before; `f5eb82e5f` differs from it in comments and in this spec only) and from the carry (after), `l4 check` on three files of this review:

- ``Red `costs` 0 MEANS 1`` under the rule: one warning, "This clause does not cover all cases", and ``Red `costs` 0`` gave `0`, not `1`. Now one error at the line's first token, 7:1-7:1: "This clause is written the way a rule with a word between its inputs is written, like this one:", the rule, and the two ways to write the cases.
- The same line after a blank line: one error, "There are multiple definitions for the identifier Red", and the warning. Now the same one error as above, at 8:1.
- ``c `costs` 0 MEANS 0`` and ``c `costs` n MEANS n`` as the only lines: 11 errors, two of them at 1:1-1:1, which is no location. Now one error at 6:1: "This clause begins with c, an input of the GIVEN, and then the word `costs`."
- ``Red `costs` n MEANS 1``, with a bare name for every input, so no literal to make it a clause: no diagnostic. Now one error at the line, "This definition is written the way the rule ... is written, but Red is not an input its GIVEN names".

Where it lives:

- `jl4-core/src/L4/Parser.hs`: `mixfixFormClause` (`:871`), `mixfixFormMessage` (`:901`) and `decideNotInMixfixForm` (`:929`); `decidePatternMatch` calls the first (`:817`) and `topdecl` the third (`:466`).
- `jl4-core/src/L4/Parser/MixfixRegistry.hs`: `mixfixRulesWrittenAs` (`:70`) and `showMixfixPattern` (`:85`).

The error is registered (`registerParseError`) and not raised, so the group still parses and the one error is the file's only error: a failure inside `decidePatternMatch` would be caught by the `try` in `topdecl` and the run read again as definitions.
Two signs show the form: the line is as long as the pattern of a mixfix rule in scope, imports included, with its words where the pattern has them; or the clause's head is one of the group's `GIVEN` inputs followed by a word that is none, which is already refused when written any way.
Two shapes are not recognised, and the error's page in `doc/reference/errors/README.md` says so: a rule whose every line begins with a constructor, ``Red `costs` 0`` and ``Green `costs` n`` with no ``c `costs` n`` anywhere, is accepted as clauses of rules named `Red` and `Green`; and a rule whose words come first, written as clauses, is still refused as having more patterns than the `GIVEN` names inputs.
Measured on the carried build: both, as that page says.
The range of the error is the point where the line starts (7:1-7:1), as every parse error on main has a point and no span (`parse-error4.golden` has `8:18-8:18`); on unstable it spans the first token, and the three `not-ok/tc` goldens were re-recorded here for that and for nothing else.
`l4 check` over the 478 `.l4` files tracked in this tree, with the binary before and the binary after: identical output and exit code for 473, and the four new fixtures differ as they should; the fifth, `jl4/experiments/carInsurance.l4`, differs only in the directory of the binary printed in an import-resolution line.
Tests: the three `not-ok/tc/pattern-matching-mixfix-form-*.l4` files (one error each; their goldens differ from the build before in the number of errors, and in the first file the build before reported a warning and no error), and `ok/pattern-matching-mixfix-neighbours.l4`, which pins what stays legal beside a mixfix rule: clauses with a name of their own first, a second definition of the same words with its own `GIVEN`, and the rule itself.
That file's `.golden` and `.ep.golden` record main's behaviour for a mixfix call: the call ``Red `costs` 0`` has a shorter range (`29:1-18`, where unstable has `29:1-20`) and is exact-printed head first (`` `costs` Red 0``), the exact-print mixfix bug that unstable fixed in legalese/l4-ide#124 (`558883a6f`, on unstable; smucclaw/l4-ide#918) and main does not have; `ok/tests/mixfix-basic.ep.golden` records the same order for `3 `plus` 5`.

A definition after a clause group, with another number of inputs.
`DECIDE f Red IS 1`, `DECIDE f c IS 2` and `DECIDE f Red Blue IS 3`: the parser gathers clauses by name and number of patterns, so the third is a rule of its own whose two inputs are called `Red` and `Blue`, and `f Green Red` gave `3`, with no diagnostic (measured with the build from `a022af716`).
It now draws one warning at the name of the third, 7:8-7:9: "This definition of `f` is not another clause of the clauses above it", with the counts and what to do.
`warnClauseArityChange` (`jl4-core/src/L4/TypeCheck.hs:234`, called from `checkProgram` at `:212`); the warning is `ClauseArityChanged` (`jl4-core/src/L4/TypeCheck/Types.hs:162`, message at `TypeCheck.hs:4641`).
A definition with a `GIVEN` of its own is not asked about, nor is a second group.
This was assumed, not ruled, upstream; it is a commit of its own here, so it can be reverted alone.
Test: `ok/pattern-matching-clause-arity-change.l4`, with its goldens.

Tests for the editor.
The outline and completion leave out the names a clause group is compiled with (see "Generated names, printing, editor and render"), and nothing tested it: the outline's filters were in the document-symbol handler in `jl4-lsp/app`, out of any test's reach.
They are now `outlineGivenParams` and `outlineLocals` in `jl4-lsp/src/LSP/L4/Actions.hs` (`:283`, `:290`), which the handler calls (`jl4-lsp/app/LSP/L4/Handlers.hs:506`, `:507` and `:622`); completion's filter was already there (`jl4-lsp/src/LSP/L4/Actions.hs:352`).
Main had no `jl4-lsp` test suite, so this adds the stanza (`test-suite jl4-lsp-test`, `jl4-lsp/jl4-lsp.cabal:156`), modelled on unstable's with `main-is: Spec.hs` under `hs-source-dirs: test`, and only the two modules the spec needs, `CheckSource` and `ClauseGeneratedNamesSpec`, with the packages they import (`-Wunused-packages` is an error).
`ClauseGeneratedNamesSpec` has ten examples: one that the module type-checks, four for the outline and four for completion over the three shapes that make the machinery name something (a group with a `GIVEN` whose input is named after a constructor, a group with no `GIVEN`, a one-clause group with a literal), and a control that a rule written without clauses keeps what was written.
Each case first finds a generated name in the unfiltered list, so that taking a filter out turns it red.
Measured on the carried build, with each filter taken out in turn and the suite rebuilt: without the outline's two filters, the four outline cases fail, listing `the result of clause 2`, `input 1`, `input 2`, `input 1` and `the result of clauses 2 to 3`; without completion's filter, the four completion cases fail; restored, ten pass.
The cases did not exist at `f5eb82e5f`, so there is no earlier build to run them on; the filters were in place there and tested by nothing.
The tests reach the filter functions (`outlineGivenParams`, `outlineLocals` and completion's filter), not the handler's calls to them: the handler is in the `jl4-lsp` executable (`jl4-lsp/app/LSP/L4/Handlers.hs:506`, `:507` and `:622`), and the test suite links the library only, so a change to a call there is not seen by it.
So a change to those calls cannot fail the suite: it does not build the executable.
What covers the handler is a run over stdio, not part of the suite: `jl4-lsp` (built from `30a0c55a2`) started on a file with a rule `price` written as three clauses under a `GIVEN` and a rule `pair` of two clauses with none, asked on 2026-10-13 for the outline and for completion in the body of `price`.
The outline lists `price` with its input `c` and `pair` with no child, with no `input 1` and no `the result of clause 2`, and completion there offers 209 names, none of them generated; the probe file is not kept in the tree.

Hand-ported to main, where it differs from unstable:

- `Parser.hs`: the three new functions go before `pmClause`, where main has `turnDownRun` and its neighbours after it; unstable's copies of those three are not carried.
- `MixfixRegistry.hs`: `Base.Text` is imported and `Data.List` is not, which main's registry does not use.
- `TypeCheck.hs`: main's `MkSection` takes four arguments, unstable's five.
- `TypeCheck/Types.hs`: the new warning's constructor and its `rangeOf` equation are added by hand.
- `Actions.hs`, `ClauseGeneratedNamesSpec.hs`: main's `OptionallyTypedName` has three fields, unstable's four; main's `MkSection` as above.
- `doc/reference/errors/README.md`: the two entries are carried without the curly-quote entry beside them, which is on unstable only.
- `doc/reference/functions/multi-clause-DECIDE.md` ("Limits", first paragraph) says the error instead of the silent reading.

## Review round 6 (the fourth review, carried from unstable's `fix/mixfix-input-word`)

The fourth review of this branch (at `a55036989`) asked for two things, both also true of unstable, so both were fixed there first (branch `fix/mixfix-input-word`, commits `3631fbfaf`, `7a0eeb61b` and `f178b3f9b`, on unstable) and carried here as three commits of their own.

A rule with an input named like a mixfix rule's word.
The check from "Review round 5" took the token where a mixfix rule has its word for the rule's word, even when the line's `GIVEN` names that token as one of its own inputs.
These were refused, and all run on main: `total plus y` with a `GIVEN` of `plus` and `y` beside ``a `plus` b``; a `decision` rule with an input called `` `is eligible` `` beside ``p `is eligible` ``; the same with the mixfix rule imported; and the clauses `DECIDE fee costs 0 IS 0` and `DECIDE fee costs n IS n` under a `GIVEN` of `costs` and `n`.
`mixfixRulesWrittenAs` (`jl4-core/src/L4/Parser/MixfixRegistry.hs:70`) now takes the names the definition has for its inputs as its first argument, and a token that is one of them no longer matches a keyword of the pattern.
`mixfixFormClause` (`Parser.hs:871`, the clause path) and `decideNotInMixfixForm` (`Parser.hs:929`, the definition path) pass their `GIVEN`'s inputs.
A definition with no `GIVEN`, or one whose `GIVEN` names other inputs but not the word, is refused as before.
Measured on unstable with the build before the fix: all four shapes were refused ("total is not an input its GIVEN names", or "This clause is written the way a rule with a word between its inputs is written"); with the fix they run, and `l4 check` over the 1,281 tracked `.l4` files of unstable, before and after, differs in the four fixtures and in no other file.
The reviewer's "area 2" file (`decision` / `` `is eligible` ``) was not available; the fixture was rebuilt from his description and the code.
Tests: `ok/mixfix-input-named-like-word.l4`, `-two-inputs.l4`, `-def.l4`, `-import.l4` and `ok/pattern-matching-mixfix-input-word.l4`, and, as a control, `not-ok/tc/pattern-matching-mixfix-form-definition-with-given.l4` (a `GIVEN` that names `n` but not the word still refuses ``Red `costs` n MEANS 1``, once).
On unstable, with the parser reverted to the base, the four fixtures that have an ordinary rule beside the mixfix rule fail all four of their examples, and the `-def.l4` file and the control pass on both.
The documentation says what is not refused (`doc/reference/errors/README.md`, under "A clause written like a rule with a word between its inputs"), and where that stops: a use of the word inside another rule's body is still read as a use of the mixfix rule, so `wrap plus y MEANS total plus y` fails to check with ``a `plus` b`` in the file and gives 12 without it, on main and on unstable (the reviewer of the fix found it; the page says to give the input another name, which gives 12 with the rule present).

The linear-time guard on Windows.
`getCPUTime` ticks every 15.625 ms there, and the 250-line sample of the first guard parses in less, so it read 0 and the 1 ms floor under the ratio turned it into nonsense.
`parsesInLinearTimeOn` (`jl4-core/test/PatternMatchParserSpec.hs`) takes the clock, parses the small file over and over in one timed stretch until the stretch spans ten steps of that clock (at most 4,096 parses), divides by the number of parses, and parses the large file once.
The verdict is a ratio of two non-zero times (`linearTimeRatioOn`).
The search for a measurable stretch stops after 2 s of wall time or 4,096 parses, and then the case is pending and not failed (assumed, not ruled), so a clock that never ticks goes pending within seconds.
Three cases are new: the first guard on a clock that reads in whole 15.625 ms steps (`steppedClock`); a control that a parse of made-up quadratic cost is still failed on it, which asserts the ratio and goes pending, and never passes, if the clock gave none; and that a clock that never ticks gives no ratio within seconds.
Measured on unstable: the old guard on a clock that reads in whole steps read one step on the 250 lines at 15.625 ms and passed, and at 62.5 ms, which stands in for a machine four times faster, its small sample read 0.0 ps and a linear parse failed with a ratio of 125 against the limit of 24; the new guard on that clock parses 8 times per stretch, gets a ratio of 12, and passes.

Hand-ported to main, where it differs from unstable:

- The fix applied to `Parser.hs` and `MixfixRegistry.hs` without change.
- `PatternMatchParserSpec.hs` on this branch has two timing guards, where unstable's has three (unstable's third times `@ref` citations, which main does not have); the new helper and the two cases were written into this file's version.
- The five `ok/` fixtures write their mixfix calls head first (``#EVAL `plus` 3 4``), where unstable's write them as the drafter would (``#EVAL 3 `plus` 4``): main exact-prints an infix mixfix call head first (smucclaw/l4-ide#918, fixed on unstable in legalese/l4-ide#124), and for ``#EVAL Alice `is eligible` `` it also dropped the `Alice`, which the `.ep.golden` would then have recorded. Each file says so in a comment. With the calls written head first the `.ep.golden` equals the source, and the results are the same as on unstable (7 and 12; `TRUE`, `"yes"` and `"no"`; 5, 0 and 7).
- The control's `.golden` and `.ep.golden` are re-recorded for main's parse errors, which are points (`13:1-13:1`) where unstable's span the first token (`13:1-13:4`).

## The ladder and /query-plan read a BOOLEAN clause group as its CONSIDER (from #651)

`/query-plan` (jl4-service) and the ladder answered "Can only visualize, as a ladder diagram, a DECIDE that returns a boolean." for a BOOLEAN rule written as clauses, a group of one clause included.
They now read it as the `CONSIDER` it stands for, as `unstable` does since legalese/l4-ide#651.
Two causes, and fixing the first alone turned the refusal into a misleading answer.

The type.
The generated CONSIDERs and the LET that binds the later clauses have no source range, and `setAnnResolvedType` (`jl4-core/src/L4/TypeCheck/Types.hs:779`) recorded a type only on a node with one.
A node with a `PmSynthetic` mark now has its type recorded on the node itself, with the substitution so far applied, and not in the position index, so hover, go-to-definition and every diagnostic are as they were.
`bindFallthrough` (`jl4-core/src/L4/Parser.hs:1311`) marks the LET with its binding's mark for this.

The shape.
With the type recorded, the ladder drew the generated LET as one leaf, and the plan asked nothing.
`translateDecide` in both ladders (`jl4-core/src/L4/Viz/Ladder.hs:300`, `jl4-lsp/src/LSP/L4/Viz/Ladder.hs:317`) now runs `L4.Transform.inlineLetsForViz` (`jl4-core/src/L4/Transform.hs:130`) first.
It substitutes the generated LETs into the CONSIDERs that use them (`inlineGeneratedLets`, `:67`); prunes each generated CONSIDER by what the branches around it settled, so a later clause does not ask again about an input an earlier one decided (`pruneGeneratedConsiders`, `:254`, which knows nullary constructors, literals and `EXACTLY` of a constructor the checker stamped, and reads a clause whose pattern is a new name as the `OTHERWISE`); and joins the generated CONSIDERs on one input (`joinGeneratedConsiders`, `:203`).
A LET the drafter wrote is never read through.

Pruning is what keeps the read-through small.
Measured on two tables of two enumerations, every pair of values a row, with `rule` the name of each: 16 rows of 4 values by 4, a checkerboard (`rule Ai Bj IS TRUE` where i + j is even and `FALSE` where it is odd, so 8 of each), and 25 rows of 5 by 5, whose results are those of `jl4/tests-cli/fixtures/verify-clause-table-large.l4` on `unstable` (that file is not on this branch):

| `rule`, read as                     | 16 rows                            | 25 rows                              |
| ----------------------------------- | ---------------------------------- | ------------------------------------ |
| written (the generated LETs)        | 125 nodes, 2,882 characters        | 197 nodes, 4,567 characters          |
| LETs substituted, not pruned        | 327,675 nodes                      | more than 5,000,000 nodes            |
| substituted and pruned              | 56 nodes, 2,054 characters         | 85 nodes, 3,808 characters           |
| pruned and joined: the box's label  | 26 nodes, 950 characters           | 37 nodes, 1,488 characters           |
| the nested CONSIDER written by hand | 26 nodes, 950 characters, the same | 37 nodes, 1,488 characters, the same |

With the type fixed and nothing read through, the box's label was the first row, the generated LETs, and the plan asked nothing.

Whether a rule was written as clauses is read off its `PmMatrix` mark (`writtenAsClauses`, `jl4-core/src/L4/Transform.hs:173`), and a rule that was not is drawn as it always was.
So is a group whose first clause names each of its inputs as the `GIVEN` does, or is `_`: the desugarer drops the clauses after that one (`PmUnreachable`), so the body holds no node it generated (`holdsGeneratedNodes`, `jl4-core/src/L4/Transform.hs:188`).
A first clause that matches every input through a new name is not that group: the desugarer generates a test of the input for it, with the clauses after it as the other answer, so the body holds a node and the group is read through (see "Bounds").
The limits under "Bounds" apply only where the body holds one (`readsThrough`, `jl4-core/src/L4/Viz/Ladder.hs:316`).

On this branch a CONSIDER is drawn as one box, labelled with the CONSIDER printed whole, and its atomId hashes that label (`generateAtomId`, `jl4-core/src/L4/Viz/Ladder.hs:512`).
So a clause group and its hand-written CONSIDER agree, in the ladder, the plan and their atomIds, when the read-through prints as the hand form: a table reads through to the nested CONSIDER a drafter writes for it, and a flatter CONSIDER that means the same (`WHEN Red THEN b` for a nested `CONSIDER b WHEN TRUE THEN TRUE ...`) is a different box.
The plan's atomIds and the ladder's differ here for every rule with inputs, a clause group or not: the plan renders an atom's inputs by their labels (`atomIdByUnique`, `jl4-query-plan/src/L4/Decision/QueryPlan.hs:187`) and the ladder by their numbers.
That is older than this work and is not changed here.

### Bounds

`letInliningNodeBudget` (`jl4-core/src/L4/Transform.hs:148`) is 20,000 nodes, counted on the pruned CONSIDERs before joining, as on `unstable`.
It bounds the size of what is read through, since pruning cannot settle every copy (behind a pattern that binds a name, say); the time follows that size since the change measured below.
Past it the ladder refuses a rule written as clauses that holds generated nodes with `ClauseGroupTooLong`: "These clauses are too long to draw: written out as the CONSIDER they stand for, they come to more than 20000 parts. Split the rule into smaller groups of clauses, or into named sub-rules."
Sixty rows on one NUMBER input, each comparing a sum of two hundred ones with zero, come to 24,301 nodes.
Deployed over HTTP to the test service at `e393b2e4c`, that group was ready after 3.6 s, and `/query-plan` refused it, with the message above, after 2.6 s.
Where the line falls is the total length, not the number of rows.
Measured at `6cb5225f9` through `/query-plan`, with rows that each compare a sum of some number of ones with zero (`longClausesJL4`): of a sum of 200 terms, 49 rows are planned and 50 are refused; of 100 terms, 97 are planned and 99 refused; of 20 terms, 440 planned and 450 refused; of one term, 2,000 planned and 3,000 refused.
The page for users gives the other way to reach it, in the words of the review of #656 and unchanged: a table over optional inputs whose clauses take values apart with JUST, each such clause written out again under every answer to the inputs after it, and it says that a table of eleven clauses over five MAYBE BOOLEAN inputs can reach it.
It gives no row counts; they were replaced by that text on 2026-10-15.

That example holds, but eleven is not where the line falls.
Measured on 2026-10-15 at `6b3af806c` through `/query-plan` on the test service, on a Linux host, with tables over MAYBE BOOLEAN inputs built like this: clause _i_ takes _j_ of the inputs apart with `(JUST x)`, starting at input _i_ and going round, gives the others new names, and returns the AND of the values it took apart; the last clause gives every input a new name and is `IS FALSE`.
Clauses that each take two inputs apart: twelve clauses over five inputs are planned and thirteen refused (the same over four).
Taking three apart: eight clauses over five inputs are planned and nine refused (the same over three; over four, nine to twelve are refused, and eight was not run).
Taking four apart: six clauses over five inputs are planned and seven refused (the same over four).
Taking all five apart: six are planned and seven refused.
So the line falls at a number of clauses that depends on how many inputs each takes apart, and the number of inputs matters only as the most a clause can take apart: eleven clauses over five inputs are refused when the first ten take three apart each, and planned when they take two.
The same eleven can fall either side by one clause: six clauses that take two apart, then three that take three, then the last, ten clauses in all, are planned; one more that takes three apart, eleven clauses, is refused.
Written with the others named as the `GIVEN` names them (and the last clause naming every input so), the tables I ran both ways are planned and refused at the same clause counts: two apart, twelve planned and thirteen refused over five inputs and over four; three apart, eight and nine over five; four apart, six and seven; all five apart, six and seven; and the ten-clause table planned and the eleven-clause one refused.

The tables written with new names for the inputs not taken apart were slow to read through, and the cause was not the size.
At `00bfa70fb`, with three inputs taken apart over five (the shape above), a refusal took, in CPU seconds on a Linux host: 22 for nine clauses, 30 for twelve, 62 for 24 and 129 for 48, in both ladders, the lens and `/query-plan` alike (the review measured 25 s and 58 s at 24 and 48 clauses); planning eight clauses took 10 to 18; thirteen clauses taking two apart ran past the test client's 30 s response timeout and took 37 s when it was lengthened.
Written with the others named as the `GIVEN` names them, the same tables fall at the same clause counts and took 0.06 to 1.44 s (32 tables), the refused ones 1.07 to 1.20.
`pruneGeneratedConsiders` put the input in for each name a clause bound to it with `substParams` over everything after that clause, and what follows a clause is the same later clauses reached by more than one way, so every new name rebuilt them once more, and the rebuilds stacked.
A step budget on pruning, as the review asked, was built first (a count of calls of pruning and of the expressions the substitution read, held in a `State`) and did not help: a step cost about 270 microseconds whatever the table, the count was far above the lazy original's (a five-clause table: 15,848 steps and 4.2 s, where the original made 886 calls and took 0.3 s), and a budget tight enough to refuse in about a second would have refused tables that plan today.
It was dropped for the cause.
Pruning now carries the renaming down and applies it where a name is read (`rn`, and `renamePattern` for an `EXACTLY x` inside a pattern), `f677a1182`.
It gives the same expression: the old and the new pruning, compared with `==` after joining, agree on 29 tables (new names and the `GIVEN`'s, three to eight clauses, rows of numbers, enumerations of five by five and ten by ten, a first clause with a new name, `EXACTLY` of an input and of a name bound above it).
So nothing flips between planned and refused, and the 20,000-node count is unchanged; what changed is how long it takes to reach it.
After it, through `/query-plan` at `098d6a89e` (the same code): the 33 new-name tables of the grid (two to five apart, over four and five inputs, with the ten- and eleven-clause pair, 24 and 48 clauses) fall where the ones run before did (planned 0.06 to 1.54 s, refused 1.03 to 1.49 s), 24 clauses are refused in 1.47 s and 48 in 1.49 s, and the 32 tables written with the `GIVEN`'s names took 0.06 to 1.43 s, the refused ones 0.94 to 1.06.
In the ladder tests the 24- and 48-clause tables were refused in 1.4 and 1.5 s by the editor's ladder, the core ladder simplified and the lens (the `GIVEN`-name table of 24 in 1.0 s), and eight clauses with new names were drawn in 1.0 s; a review had timed the lens on the tables written with the `GIVEN`'s names at about 1 s.
Counting from a clause group of this kind the time follows the size reached before the count of 20,000 nodes stops it, which is why the comment on `letInliningNodeBudget` says refusing takes about as long as drawing a group of that size.
`ClauseGroupLadderSpec` and `IntegrationSpec` have a test each for 24 clauses (and 48 in the ladders) refused within 8 s, each answer waited for on its own, and for eight clauses still drawn and planned; without the change the 24-clause answer does not come in 8 s and the eight-clause one does not either, so each fails (two of five in the ladder tests, two of three in the service).
The same four tables on `main` at `12d6773ad` are answered at once, with 400 "Can only visualize ...", in 0.001 s of CPU.
`unstable` at `bd887270e` has the text this branch had before the change (`inlineLetsForViz`, `pruneGeneratedConsiders`, `inlineGeneratedLets` and `joinGeneratedConsiders` the same), and its slowness: new-name tables 30.8 s (eight clauses, planned) and 22.1 s (nine, refused), the `GIVEN`-name ones 19.6 s and 1.3 s.
The change to `Transform.hs` is the function and its type only, so that it can be taken to `unstable` as it is: `git apply --check` of that commit's `Transform.hs` diff is clean on `origin/unstable` at `c05e15ca0`.

Nothing in the service caps the time of `/query-plan`, and a refusal is not remembered; after the change a refusal of such a table took 1.5 s at most in the grid above.
`queryPlanHandler'` builds the plan on the first request for a function and stores it only when the build succeeded (`jl4-service/src/DataPlane.hs:362-369`); a refusal is thrown from `buildDecisionQueryCacheFromCompiled` before anything is stored (`jl4-service/src/Backend/DecisionQueryPlan.hs:182`), so every request for a refused rule pays the whole cost again.
The deployment timeouts guard compiling (`tryCompileWithTimeout`) and evaluation (`timeoutAction`), not the plan.

`ClauseGroupTooLarge` and its message ("These clauses would draw a ladder of more than 300 boxes, too many to show. ...") are kept as on `unstable` (`clauseGroupLadderBudget`, `:167`).
A CONSIDER is one box here, so a group that reads through to a CONSIDER is one box, however many rows it has.
A group that reads through to something else is drawn as that, and can reach the limit: a first clause that gives an input a new name reads through to its result.
Measured with the ladder tests on this branch: 301 BOOLEAN inputs ANDed under a new name are refused in both ladders, simplified or not, and the lens reads "No decision graph: these clauses would draw more than 300 boxes", where the same rule under the `GIVEN`'s own name is drawn; six pairs ANDed and ORed under a new name are drawn as written, with the ordinary lens, and refused once simplified, which is what the service's plan does (449 boxes for six pairs with the first clause's own names; five pairs are drawn simplified too).
It is kept, for groups that hold generated nodes, as `unstable` has it, and for when a CONSIDER is drawn as rows (legalese/l4-ide#137).

A group whose first clause names each of its inputs as the `GIVEN` does, or is `_`, is not limited.
It had been: a disjunction of 6 two-input conjunctions as the first clause of a group whose second clause is never reached is 449 boxes in conjunctive normal form once the service simplifies it, and the service refused it, where the same rule written without the second clause was planned; a first clause of 22,000 parts was refused as too long to draw, and its lens read "No decision graph".
The review of #656 found it, and it was measured on 2026-10-15: `main` at `12d6773ad` answers both with a plan, this branch refused both until `546414108`, and `unstable` at `bd887270e` refuses both, with these two messages, so the same fix belongs there.
Tests: `ClauseGroupLadderSpec` draws both in both ladders, and `IntegrationSpec` plans both.
The boolean check runs first, so a long group that returns a number is told it is not boolean.

A first clause that matches every input through a new name is not that group, and is limited.
`patAlwaysMatchesAs` (`jl4-core/src/L4/Syntax.hs:116`) is true only of `_` and the input's own name, so for a new name `matchOne` (`jl4-core/src/L4/Parser.hs:1331`) generates a test of the input, with the clauses after it as the other answer, and `holdsGeneratedNodes` is true.
The first version of this section said "matches every input" where it meant the own-name or `_` case, and the guard's comments and the service README said the same; a second review of this branch found it and measured it, and this section, the comments, the README and the page now say which first clauses are exempt.
The code was right and did not change.
Measured on 2026-10-15 through `/query-plan` on a Linux host, with these six sources run unchanged on `main` at `12d6773ad`, on `unstable` at `bd887270e` and on this branch: a disjunction of 5 and of 6 two-input conjunctions as the first clause, and a first clause of 22,000 parts, each with the first clause's NUMBER input named as the `GIVEN` names it, and with a new name for it (`m` for `n`); the clause after it is never reached in the first three.

| first clause           | `main`                             | `unstable`                | this branch               |
| ---------------------- | ---------------------------------- | ------------------------- | ------------------------- |
| own name, 5 pairs      | 200                                | 200                       | 200                       |
| own name, 6 pairs      | 200                                | 400 "more than 300 boxes" | 200                       |
| own name, 22,000 parts | 200                                | 400 "too long to draw"    | 200                       |
| new name, 5 pairs      | 400 "Can only visualize" a boolean | 200                       | 200                       |
| new name, 6 pairs      | 400 "Can only visualize" a boolean | 400 "more than 300 boxes" | 400 "more than 300 boxes" |
| new name, 22,000 parts | 400 "Can only visualize" a boolean | 400 "too long to draw"    | 400 "too long to draw"    |

The own-name rows are the fix above; the new-name rows were the same on this branch before it (the three new-name service tests pass with the two Ladder files as at `368127487`).
`main` has no read-through, so it refuses every group that holds a generated node, with "Can only visualize, as a ladder diagram, a DECIDE that returns a boolean."
So a new-name first clause is where `unstable` is, and ahead of `main` at five pairs.
Exempting new names too, so that those groups were planned as the own-name ones are, would be a gain over `main` and not parity; it is not done, and whether to do it is for the maintainers.

`(EXACTLY n)` for the input's own name is not exempt either: `patAlwaysMatchesAs` is true only of the bare name and `_`, so the desugarer tests it, and `holdsGeneratedNodes` is true for such a first clause (the premise test in `ClauseGroupLadderSpec`).
The service plans six pairs of it (200) and refuses a first clause of 22,000 parts as too long (400); `IntegrationSpec` pins both.
I infer that it reads through to one CONSIDER, which is one box, and that this is why the 300-box limit is not reached at six pairs; I did not draw it.
The missing-case section of `doc/reference/errors/README.md` says that `EXACTLY` of the input's own name "matches every input"; that is true of the missing-case check, and the section on the decision graph in `doc/reference/functions/DECIDE.md` says that drawn or planned such a clause is read as a test, so the 20,000-part limit applies to it.

These are `unstable`'s bounds, applied to a group that reads through, and the only ones here.
They were checked on 111 generated tables, each run through `/query-plan` here and `/ladder` on `unstable` at `01557e40a`, on 2026-10-13: one NUMBER input of 50 to 1,200 rows; an enumeration by one BOOLEAN (24 to 200 values) and by as many BOOLEANs as values (10 to 150); two enumerations with every pair of values a row (5 by 5 to 30 by 30); rows over an enumeration whose results AND 3 or 6 number comparisons, or 10 or 20 BOOLEAN inputs; and random tables of 2 to 6 inputs, BOOLEAN or NUMBER, with results TRUE, FALSE or an input, some with a name in an earlier column before a test of a later one.
A review re-ran them against `unstable` at `0cfcf6960`, and the two agree, in verdict and box count, on all 109 tables on which both give a verdict.
`unstable` draws 81 of the 111 and refuses 28; for 2 (900 rows of two enumerations, 1,200 rows of one NUMBER) its deploy did not finish on 2026-10-13, and neither did it here.
That was before #666, which removed the `bundle.cbor` write that sat between the compile and the end of a deploy; the two tables were not run again after it.
This branch refuses none of the 81, and draws all 28: `unstable` refuses them because, drawn as rows, each would have more than 300 boxes, and here a CONSIDER is one box.
When drawing a CONSIDER as rows (legalese/l4-ide#137) reaches this branch, that limit will apply to them here too.

Their cost here is small since the SHA-1 that names each box from its label (`L4.Crypto.SHA1`, carried from `unstable`'s legalese/l4-ide#626) builds each block's message schedule once: the hash of a 38,617-character label took 2.2 s before and takes 1 ms now.
With it, the slowest of the 111 plans in 0.39 s (a label of 881,237 characters), and of the larger tables a review chose to find the limit (two enumerations of up to 27 values, enumerations of 330 values by a BOOLEAN, 400-value enumerations by as many BOOLEANs, and 120 rows each ANDing 30 BOOLEANs), the slowest planned in 1.02 s cold and 0.01 s warm, and the editor drew it in 0.8 s.
Without it, the same 881,237-character label planned in 102 s.

The editor's decision-graph lens moved into `LSP.L4.Actions.decisionGraphCodeLenses` (`jl4-lsp/src/LSP/L4/Actions.hs:468`), so that it can be tested, and keeps its lens for a refused group, titled "No decision graph: these clauses are too long to draw" (or "... would draw more than 300 boxes", which a first clause that gives an input a new name reaches when its result as drawn is that large); clicking it shows the whole message.
The lens never simplifies the ladder.

### Not carried, because it is not on this branch

- `l4 verify`, its reading of clause groups and its NOT ANALYSED and WHERE counts: there is no `l4 verify` here.
- Call panels and reading a called group through (`expansionBodyOf`, and the bound on callers of a too-long group): a call here is one box, and the expand gesture (`l4/inlineExprs`) unfolds only a rule with no inputs, which cannot be written as clauses.
- Term-keyed atomIds (R3): atomIds here hash the printed label.
- Drawing a CONSIDER as rows of boxes (`L4.Viz.GuardedRows`, legalese/l4-ide#137, `unstable` only), and with it the plan cost of twin atoms that `unstable` records. On this branch a CONSIDER written by hand is one box too, so a clause group drawn as the same one box is drawn alike.

After a `jl4-service` restart, a clause group is planned as it was at deploy.
Until legalese/l4-ide#666 a restart read `bundle.cbor`, which kept no part of an annotation but the desugarer's mark, so the rehydrated DECIDE had no resolved type and `/query-plan` answered "Can only visualize, as a ladder diagram, a DECIDE that returns a boolean." for every boolean rule, a clause group or one written by hand; `/evaluation` still answered.
#666 removed the cache, so a restart compiles the stored sources as a deploy does.
`IntegrationSpec` pins it ("restarted: is planned as it was before the restart", one case for each of the eight clause groups of the pairs below): each group is deployed, the service is restarted from its store, and `/query-plan` is asked before and after; the answer before must be a 200 with a body, and the answer after must equal it.
All eight pass at `e393b2e4c`.
With a mutation, not kept, that passes each restarted function's compiled module and DECIDE through the CBOR encoding the old cache used (`Serialise Anno`, still behind the flag), all eight fail, each with the old 400 "Can only visualize, as a ladder diagram, a DECIDE that returns a boolean." against the fresh 200.
With a mutation, not kept, that compiles `IS FALSE` as `IS TRUE`, the five groups whose source has `IS FALSE` fail on that comparison and the other three pass.

Pinned by `jl4-service/test/IntegrationSpec.hs` ("a BOOLEAN rule written as DECIDE clauses": eight pairs compared with their hand-written CONSIDER, whole plan and atomIds; the 20,000-part refusal; a group whose first clause names each input as the `GIVEN` does, planned at 193 and at 449 boxes simplified and at 22,000 parts, the 22,000-part plan equal to that of the rule written without the second clause; the same groups with a new name for the first clause, refused at six pairs and at 22,000 parts and planned at five; a first clause that writes the input `(EXACTLY n)`, planned at six pairs and refused at 22,000 parts; a table of 24 clauses of optional inputs taken apart with `JUST`, with new names for the others, refused within 8 s, and the same at eight clauses planned; the boolean check first; a drafter's LET kept as written; the eight groups planned as before after a restart) and `jl4-lsp/test/ClauseGroupLadderSpec.hs` (four pairs in both ladders, `EXACTLY` among them; the refusal in both; a group whose first clause names each input as the `GIVEN` does drawn in both, with its lens, and the premise that it holds no generated node, where a new-name first clause holds one; the new-name groups refused in both ladders, with their lens, at 22,000 parts and at 301 inputs, and drawn as written but refused simplified at six pairs; the premise that an `EXACTLY` first clause holds a generated node; that table at 24 and 48 clauses refused within 8 s in both ladders and the lens, and at eight clauses drawn; the lens).
