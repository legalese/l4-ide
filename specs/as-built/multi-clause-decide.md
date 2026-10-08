# Multi-clause pattern-matching DECIDE (as built on main)

This describes branch `deadbolt/multi-clause-main` (PR #545, into `main`), re-measured on 2026-10-08.
Every `file:line` below is at the commit that last changed this file; every probe below was run on a binary built from it.
The branch carries work first merged into unstable, one PR at a time, and each section below names its unstable source.
The unstable commits named here are on unstable only: none of them is on this branch or on main.

This branch, oldest first: `d0905e1d8` (the clauses, from #49), `d6594578b` (exact-print, from #130), `17e944423` (the missing-case warning, adapted from #185), `1a67532c7` (clause hygiene, from #569), `f02f0a6b7` (a merge of main), `ee407387b` (ruling M1), `b7c54a6cb` (generated names, printing, editor and render, from #581), `f2d938863` (the missing-case check's limits in the user documentation; this file rewritten for main), `36c549226` (`l4 run --json` reports an evaluation error in the drafter's terms), and the commit that carried ruling M2 from legalese/l4-ide#587.

Source spec: `specs/todo/PATTERN-MATCHING-SPEC.md` (on unstable it is under `specs/done/`).
Differences from the source spec, each probed on this branch:

- `_` and `_name` are lexer errors (`DECIDE f _ IS 0`: "unexpected '\_'").
  An underscore written as a backtick-quoted name is lexed as a name, and matches without a test, as the desugarer reads `_` (`patAlwaysMatchesAs`, `jl4-core/src/L4/Syntax.hs:116`).
- Inside a group, a pattern variable whose name differs from its `GIVEN` is accepted and binds, where the source spec requires an error.
  With `GIVEN x … y …`, `DECIDE f 0 q IS q` / `DECIDE f p q IS p + q` checks, and `f 2 5` gives 7.
  A single clause with a mismatched name (`DECIDE double b IS a * 2`) is still an error, because it takes the ordinary path.
- The Phase 1 redundancy and overlap warnings are not built, except that the clauses after one that matches every input are reported as never used.
  `DECIDE f TRUE IS 1` / `DECIDE f other IS 2` / `DECIDE f FALSE IS 3` checks with no warning, and `f FALSE` gives 2.
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

- `topdecl` tries the group parser first: `try (decidePatternMatch sig) <|> decide sig` (`:460`).
- `PMClause`, a parser-internal clause record that never enters the AST (`:728`).
- `decidePatternMatch`, grouping and the commit test (`:750`); `pmClause`, one clause (`:808`).
- `givenTermNames` (`:833`) and `givenTermParams` (`:838`).
- `desugarPatternClauses`, which builds the fused `MkDecide` and records the clause matrix (`:850`).
- `generatedName` (`:919`), `givenInputBinding` (`:928`), `scrutineeRef` (`:936`), `rawTokensAnno` (`:949`).
- `matchClauses` (`:977`), `clauseMatchesAnything` (`:1008`), `fallthroughName` (`:1015`), `clausesSrcAnno` (`:1036`), `bindFallthrough` (`:1045`), `generatedConsider` (`:1056`), `matchOne` (`:1062`), `matchLast` (`:1082`).

In `jl4-core/src/L4/Syntax.hs`: `isDistinguishablePat` (`:103`), `patAlwaysMatchesAs` (`:116`) and `isGeneratedName` (`:124`), shared by the parser, the checker, the printer and the editor.

The run-time error is `NonExhaustivePatterns` (`jl4-core/src/L4/EvaluateLazy/Exceptions.hs:46`), thrown at `EvaluateLazy/Machine.hs:1185`.

## Behaviour and rules

Grouping.
The first clause sets the column, the head name and the arity.
Further clauses must start at exactly that column (`withIndent EQ`, `Parser.hs:764`) and have the same raw head name and the same number of argument patterns.
Anything else ends the group, including an intervening `GIVEN`, so type-overloaded definitions, each with its own signature, are never merged.

Clause forms.
`DECIDE head pat… [AKA …] IS|IF body`, or `head pat… [AKA …] MEANS body`.
Argument patterns are atomic, so an applied constructor needs parentheses: `(JUST v)`, `(x FOLLOWED BY xs)`.
The first `AKA` found in any clause is used for the fused head.

When the group is taken (`guard`, `Parser.hs:784`).
It is taken when some clause has a distinguishable pattern: a literal, a cons, an `EXACTLY` expression, or a constructor with arguments.
It is also taken when the group has at least two clauses, every argument is a bare name, and in some column the bare names differ (`TRUE`/`FALSE`, enum constants).
Otherwise the parser backtracks and the ordinary single-clause `decide` parser runs, so a lone bare-name clause is unchanged.

Inputs.
If the signature's term parameters (`GIVEN` names that are not `IS A TYPE`) number exactly the arity, and the arity is positive, they are the group's inputs, bound in the definition at the `GIVEN`'s own location with none of its tokens (`givenInputBinding`).
Otherwise the desugarer makes the inputs up: `input 1 … input n`, spelled with `PreDef` (`generatedName`), which no source can write; a backtick-quoted `` `input 1` `` is a `NormalName`, and so a different name.
A `GIVEN` that does not name one input per pattern, a type-only `GIVEN` included, is an error (see Diagnostics).

Desugaring.
For each column, a bare name equal to the input's name, or `_` written as a quoted name, matches without a test and binds nothing new.
Any other pattern becomes a generated `CONSIDER … WHEN <pattern>`, marked `PmConsider` (`generatedConsider`).
It reads the input by the input's name respelled with `PreDef` (`scrutineeRef`), which the checker makes another name of the `GIVEN` input (`clauseInputSpellings`, `TypeCheck.hs:681`), so a pattern variable an earlier column binds under that name cannot capture the reference.
A bare name that is not the input's name is a `WHEN` pattern, and the checker decides whether it is a nullary constructor or a fresh variable: in `DECIDE premium other IS 0`, `other` binds the input.
Every non-final clause gets `OTHERWISE <the later clauses>`; the final clause gets no `OTHERWISE`, so a value no clause matches raises `NonExhaustivePatterns` at run time.
The later clauses are bound once per clause boundary, with `LET … IN`, to a nullary local named for what it holds, `the result of clauses 2 to 3` or `the result of clause 3` (`fallthroughName`), also spelled with `PreDef`, and referenced by name, so the tree is linear in clauses times columns.
Each such local `Decide` has its first clause's body as its source range (`clausesSrcAnno`), because the checker keys function signatures by `Decide` range; only the body, so that hover on a pattern between the bodies finds the pattern and not the binding.
The clauses after one in which every column matches without a test are bound too, marked `PmUnreachable`, so that they are checked (see clause hygiene below).

## Diagnostics

- At run time, a generated `CONSIDER` that runs out of branches says "No clause of `k` matches these inputs.", or "The only clause of `z` does not match these inputs." (`Exceptions.hs:110`); a `CONSIDER` the drafter wrote keeps "The value … reached a CONSIDER that has no branch for it." (`:100`).
- A `GIVEN` that does not name one input per pattern, a type-only `GIVEN` included, is one error at the first clause's head (`ClausePatternCountMismatch`, `jl4-core/src/L4/TypeCheck/Types.hs:77`; message at `TypeCheck.hs:3739`): "Each clause of `f` has 2 patterns, but its GIVEN names 1 input."
- A pattern of the wrong type is reported as an input of the group: "The first input of `f` is declared to be of type NUMBER but the pattern written for it here is of type STRING", at the pattern (`ExpectClauseInputContext`, `Types.hs:168`; message at `TypeCheck.hs:4007`).
- The missing-case warning and the never-used warning are described below.
- Because the pattern parser is tried first, a malformed `DECIDE` head lists pattern tokens among the expected ones: `expecting (, AKA, EXACTLY, Float Literal, IF, IS, Numeric Literal, OF, String Literal, identifier, or space token` (`jl4/examples/not-ok/tc/tests/parse-error4.golden:14`).

## Tests and fixtures that pin it

- `jl4-core/test/PatternMatchParserSpec.hs` (in `jl4-core-test`), six cases: literal and variable clauses group into one `CONSIDER`-bodied `Decide`; `EMPTY`/`FOLLOWED BY` clauses group; a single literal clause desugars; a single variable clause is left alone; two different heads stay two `Decide`s; and a group's range stops at its own lines and the file exact-prints unchanged.
- `jl4-core/test/PatternClausesMissingSpec.hs`, 25 cases, and `jl4-core/test/MultiClausePrintSpec.hs`, both described below.
- `jl4/examples/ok/`: `pattern-matching.l4` (factorial, fib, list length, `from maybe`, a two-column decision table, nested `(JUST (JUST k))`), `pattern-matching-nullary.l4`, `pattern-matching-decision-table.l4`, `pattern-matching-clause-hygiene.l4`, `pattern-matching-one-clause-fallback.l4`, `pattern-matching-fallthrough-name.l4` and `pattern-matching-input-names.l4`, each with its four goldens under `tests/`.
- `jl4/examples/not-ok/tc/`: `pattern-matching-clause-type-errors.l4` and `pattern-matching-clause-inputs.l4`.
- `jl4/examples/lsp/hover/multi-clause-hover.l4`, with its positions in `jl4/tests/Hover.hs`.
- `jl4/tests-cli`: `l4 format` "reproduces multi-clause DECIDE and MEANS groups byte-for-byte" (fixture `multi-clause-format.l4`); `l4 check` "warns that a multi-clause DECIDE misses a case, and still succeeds" (`multi-clause-missing.l4`); "multi-clause groups: the names they are compiled to" (`multi-clause-render.l4`, through `l4 render` and `l4 trace`); and "l4 batch: re-prints a multi-clause group as its clauses" (the `batch-multi-clause*` fixtures).

Main's golden harness prints only infos after "Typechecking successful", so no golden under `ok/` shows a warning; the warnings are pinned in `PatternClausesMissingSpec`.

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

- `jl4-core/src/L4/Syntax.hs`: `PmGroup` (`:517`) and `PmSynthetic` (`:531`: `PmConsider`, `PmFallthrough`, `PmUnreachable`), the `pmSynthetic` field of `Extension` (`:553`), `annPmSynthetic` (`:602`) and `setPmSynthetic` (`:605`); `PmMatrix` has `synthesizedScrutinees` (`:497`) and `catchAll` (`:502`).
- `jl4-core/src/L4/Parser.hs`: `matchClauses` (`:977`) marks every generated CONSIDER (`generatedConsider`, `:1056`) and binding of later clauses (`bindFallthrough`, `:1045`), and binds the clauses after a clause that matches every input instead of dropping them (`PmUnreachable`); `clauseMatchesAnything` (`:1008`); `givenTermParams` (`:838`).
- `jl4-core/src/L4/TypeCheck.hs`: `settleOneClause` (`:560`), `decideErrorContext` (`:585`), `isClausesBinding` (`:593`), `checkClausesLet` (`:727`, dispatched from `checkExpr` at `:1657`), `speculatively` (`:764`), `warnUnreachableClauses` (`:943`); `checkConsider` (`:1743`) reads the mark; the messages (`:3925`, `:4007`).
- `jl4-core/src/L4/TypeCheck/Types.hs`: `UnreachableClause` (`:120`), `PatternClauseUnreachable` (`:138`), `ExpectClauseInputContext` (`:168`).
- `jl4-core/src/L4/EvaluateLazy/Exceptions.hs:110` and `Machine.hs` (`consideredClauses`, `:358`): the run-time message in clause terms.

Behaviour:

- No check reads a generated name; every generated node carries a `PmSynthetic` mark. A CONSIDER the drafter wrote in any clause's body is checked like any other, and so is a definition whose name only looks generated.
- The generated CONSIDERs of a group of two or more clauses report no missing branches (the group-level warning does) and no redundant ones (see the adaptations below).
- A group of one clause is checked as a clause too ("This clause does not cover all cases."). Where the check gives up (see its limits below), the warning for the CONSIDER it compiles to is kept, moved from no location to the clause.
- The clauses after one that matches every input (one whose every pattern is its input's own name or `_`) are bound, checked against the group's type outside the earlier clause's scope, with what they infer discarded (`speculatively`), and dropped from the checked tree. One warning goes at the first of them: "This clause of `g` is never used. The clause above it matches every input…".
- Clauses are checked from the top, so a type error is reported at the drafter's clause, as an input of the group, rather than about a generated scrutinee.
- At run time, a generated CONSIDER that runs out of branches speaks of clauses (see Diagnostics); a CONSIDER the drafter wrote keeps its wording.

Adapted for main:

- Not carried: #569's second "never used" form, for a clause that repeats one above it or follows a clause binding a new name. It needs the redundant rows of unstable's analysis, which `uncoveredRows` does not compute; `warnUnreachableClauses` and `UnreachableClause` mark the seam. The user documentation says these clauses are not flagged (`doc/reference/errors/README.md`, "Clause that is never used"; `doc/reference/functions/multi-clause-DECIDE.md`, "Limits").
- `checkClausesLet` checks the clause in scope of the binding that `withScanTypeAndSigEnvironment` makes; #569 adds it again with `extendKnownMany` to mark it a lexical local, which main has no notion of, and on main that second copy made every reference to the binding ambiguous.
- `checkConsider` also reports no redundant branch for a generated CONSIDER. Main's redundancy analysis flags the OTHERWISE after a clause whose pattern is a new name, at no location, naming the binding of the later clauses; unstable's analysis never flags an OTHERWISE.
- The renderer for a no-GIVEN group's open column reads `synthesizedScrutinees`.
- `NonExhaustivePatterns` keeps main's two cases (main has no `WHNFWhen`).

Tests: eight `PatternClausesMissingSpec` cases for the behaviour above (they failed on the commit before `1a67532c7`, measured when it was carried), and the fixtures `not-ok/tc/pattern-matching-clause-type-errors.l4`, `ok/pattern-matching-fallthrough-name.l4`, `ok/pattern-matching-clause-hygiene.l4` and `ok/pattern-matching-one-clause-fallback.l4`; where a behaviour depends on the check, their MAYBE patterns are patterns over enumerations it knows.

## The missing-case warning (adapted from #185)

Ruling M1, 2026-10-07 (bench "Multi-clause Main", https://claude.ai/artifact/152eFCmvtT18nVKr9KyTdn): option A, this engine is main's, with no end date; conditions: main's carry of #569 warns only about clauses after a catch-all, and the user documentation says so; the user documentation names the `EXACTLY` and step limits. Meng: "ok. M1 A as printed."

Both conditions are met in the user documentation on this branch: `doc/reference/errors/README.md` ("Multi-clause DECIDE does not cover all cases", its Note; "Clause that is never used") and `doc/reference/functions/multi-clause-DECIDE.md` ("Limits") name every limit listed below, with an example of each, and say that only the clauses after a catch-all are reported as never used.

Ruling M2: option A, "Refuse at check"; conditions: on unstable first, then carried to #545, plus one issue for inputs with no declared type published with the wrong schema type, filed as smucclaw/l4-ide#1024; Meng gave no note beyond choosing the option; 2026-10-08; bench https://claude.ai/artifact/152eFCmvtT18nVKr9KyTdn; carried from legalese/l4-ide#587

M2 is about publishing, not about missing cases; it is described under "Refusing an @export of clauses with no GIVEN" below.

On unstable, #185 (merge `9e684f9b8`) is seven commits: `97cc781c9` (the parser records the clause matrix), `4556d4419` (the checker), `38f0f6fb7` (the column-wildcard fix), fixtures and goldens (`683b20cb0`, `51b08333f`), a DMN test (`0cc42baf6`) and spec notes (`f0e224fd0`).
This branch carries the code of `97cc781c9` and `38f0f6fb7`, with comments adapted to main, and `4556d4419`'s outer structure; the analysis inside it is new, because #185's runs on the residual-set coverage oracle (`analyzeGuardRows` over `analyzeBranch`, `maxUncoveredNablas`, `constructorArity`, `constructorsInScopeFromEntityInfo`), which reached unstable before #185 and is not on main.
Main's own CONSIDER analysis is not reused either: `normalizeRefinement` merges every disjunct into one constraint set (`jl4-core/src/L4/TypeCheck.hs:2470-2477`, with the union at `:2455`), which loses the row structure a group of several columns needs: traced by hand on `f TRUE TRUE` / `f FALSE FALSE`, it reports nothing missing (not run, since a `CONSIDER` has one scrutinee).

Where it lives:

- `jl4-core/src/L4/Syntax.hs`: `PmMatrixClause` and `PmMatrix` (`:473`, `:495`), the `pmMatrix` field of `Extension` (`:552`), `annPmMatrix` and `setPmMatrix` (`:596-600`).
- `jl4-core/src/L4/Parser.hs:898-909`: `desugarPatternClauses` records the inputs and each clause's head range and patterns.
- `jl4-core/src/L4/TypeCheck.hs`: `inferDecide` calls `checkClauseMatrix` after checking the body (`:536`); `checkClauseMatrix` (`:791`), `quietly` (`:970`), `coveragePattern` (`:987`), `constructorFamilies` (`:1007`), `uncoveredRows` (`:1042`), `maxMissingClauses` (`:1087`), `clauseMatrixFuel` (`:1091`), `patternHasOpaque` (`:1097`); the message (`:3918`) and `prettyMissingClauseLhs` (`:3944`).
- `jl4-core/src/L4/TypeCheck/Types.hs:131`: the warning `PatternClausesMissing`, whose range (`:245`) is the hull of the clause heads.

Behaviour:

- Every group is checked, one clause or many.
- Each clause's patterns are checked again against the `GIVEN` types with every diagnostic discarded (`quietly`); a clause naming its column's `GIVEN` is read as matching anything before that, as the desugarer reads it (`patIsColumnWildcard`, `TypeCheck.hs:927`, from unstable's `38f0f6fb7`).
- The missing rows are computed by specialisation and the default matrix (Maranget, "Warnings for pattern matching", JFP 2007, §3.1 and §5), over the constructors main's `CONSIDER` analysis knows: `TRUE`/`FALSE` and the enumerations and records declared in the module (`constructorFamilies` reads the same declarations as `buildConstructorLookup`).
- In each suggested clause, an input that the missing case leaves open is written as its `GIVEN` name, or as `` `_` `` when the user wrote no `GIVEN` for it (#185's `renderColumnWildcard` wrote the parser's `_pm_arg_i` there, measured on unstable at `568817a6d`), and an applied constructor is parenthesised, so each suggested `DECIDE … IS` line can be pasted.
- The warning text is unstable's: "This multi-clause definition does not cover all cases. The following clauses are still needed:".

Limits.
Each is fail-open: the check gives up with no warning, and no diagnostic says that it gave up (assumed, not ruled, 2026-10-08: the user documentation names the limits instead).

- A group matching numbers, text, lists (`EMPTY`, `FOLLOWED BY`), or values of a type declared in another module (such as `MAYBE` from the prelude) is not checked: main's constructor lookup does not know those constructors.
- A number, a piece of text or an `EXACTLY` pattern anywhere in a group's patterns stops the check for the whole group, even where its other inputs are enumerations (`patternHasOpaque`).
- More than 64 rows at any level of the analysis (`maxMissingClauses`), or more than 10000 steps (`clauseMatrixFuel`).
- A pattern that does not re-check against its `GIVEN` type.
- There is no `@nonexhaustive`, so a group cannot be marked deliberately partial.
- #185's DMN channel (`siClauseMatrixRanges`) is not carried: main has no DMN export.

Tests: `jl4-core/test/PatternClausesMissingSpec.hs` (25 cases, matching warnings by severity and rendered text): 14 from `17e944423`, including the silences for numbers, lists, `MAYBE`, an enumeration from another file and the 64-row cap; eight for clause hygiene; and three pinning the examples the reference page gives for a number anywhere, an `EXACTLY` pattern and the step limit, each with its control that warns.
`jl4/tests-cli` "warns that a multi-clause DECIDE misses a case, and still succeeds" (fixture `tests-cli/fixtures/multi-clause-missing.l4`).

## Generated names, printing, editor and render (from #581)

Unstable PR #581 (branch `fix/multi-clause-names`, six commits ending at `796cc8eb1`, not merged into unstable when this was carried) is carried as one commit, `b7c54a6cb`, because each part needed adapting to main's printer, test harnesses and AST, and the parts depend on each other.

Where it lives:

- The names: `generatedName`, `givenInputBinding`, `scrutineeRef` and `fallthroughName` in `Parser.hs` (see "Where it lives" above); `isGeneratedName` (`Syntax.hs:124`); `clauseInputSpellings` (`TypeCheck.hs:681`), added to scope in `inferDecide` (`:528`).
- The count of inputs: `clauseInputsAgainstGiven` (`TypeCheck.hs:616`), `givenInputsInScope` (`:632`) and `givenMisnamesInputs` (`:641`), used by `scanFunSigDecide` (`:3378`) and `checkClauseMatrix` (`:798`).
- Hover: `recordInputPatterns` (`TypeCheck.hs:812`).
- Printing: the `Decide` printer (`jl4-core/src/L4/Print.hs:265`), `writtenClauses` (`:311`), `clauseHeadPattern` (`:332`), `unusedInputNames` (`:353`), `clauseBodies` (`:365`) and `writtenSignature` (`:388`).
- Render: `clauseLayout` (`jl4-core/src/L4/Export/Document.hs:812`).
- Editor: completion leaves out generated names (`jl4-lsp/src/LSP/L4/Actions.hs:332`), and so does the outline (`collectLocals` and `writtenParam`, `jl4-lsp/app/LSP/L4/Handlers.hs:635-641`).

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

- `jl4-core/src/L4/TypeCheck.hs`: `refuseExportedClausesWithoutGiven` (`:663`), called from `inferTopDecl` (`:485`); the message (`:3737`).
- `jl4-core/src/L4/TypeCheck/Types.hs:82`: the error `ExportedClausesWithoutGiven`, whose range (`:241`) is the `@export` annotation's.
- `jl4-core/src/L4/Export.hs:440`: `isExportedDecide`, now polymorphic in the pass, so the checker can ask it before resolution.

Behaviour:

- `l4 check` refuses an `@export` of a definition written as clauses with patterns, one clause or several, that has no `GIVEN`: "`size` is published with @export, but its inputs have no names: add a GIVEN that names and types each one.", at the `@export`.
  It fires when the definition has a `PmMatrix` with `synthesizedScrutinees` and no `GIVEN` at all; a `GIVEN` that names the wrong number of inputs gets `ClausePatternCountMismatch` only.
- It asks the question main's publication asks: `isExportedDecide` and `buildExportedFunction` (`Export.hs:171`) both read `parseDescText`'s `isExport` flag from the definition's `@desc`, so `@export`, `@export default`, and a `@desc` whose first word is `export` or `default` all count.
- Main has no `isExportPublicationRefusal`, and no Blawx or relational lowering, so unstable's assumption about those does not arise here.
- The error fails the check, so `l4 run`, the REPL and `l4 batch` refuse the file, and jl4-service rejects the deployment ("Update rejected: compilation failed: …", through `blockingErrs`, `jl4-service/src/Compiler.hs:155`).

Measured on this branch against `36c549226`:

- `size.l4` (three clauses, no `GIVEN`): at `36c549226`, `l4 run` and the REPL answered 5 for `size Green 4`, `l4 batch` failed inside its wrapper with a type error, and jl4-service published the inputs `input 1` and `input 2`, typed "object", and answered 422 "#EVAL produced function closure". Now run, batch (exit 1, "type checking failed") and the REPL refuse it, and the deployment is rejected.
- `one.l4` (`@export DECIDE discount 0 IS 1`): at `36c549226`, run and the REPL answered 1, `l4 batch` answered 1 for `{"input 1": 0}`, and jl4-service published `input 1` as "object" and answered 422. Now all four refuse it.
- The same three clauses with a `GIVEN`: 5 under run, batch and the REPL, before and after; jl4-service publishes `c` ("string") and `n` ("number") and answers 5.
- Every file under `jl4/examples`, `jl4/tests-cli`, `jl4/experiments` and `doc` that publishes something (43 with the two new corpus files) checks the same way on both binaries; the new error fires only in the new not-ok file.

Tests: `not-ok/tc/pattern-matching-export-without-given.l4` and `ok/pattern-matching-export-given.l4`, whose goldens equal unstable's except that main's schema writes `n` as `{"$ref": "#/$defs/NUMBER"}`; and the jl4-service cases "refuses a module that @exports a clause group with no GIVEN" and "publishes the same clause group with a GIVEN, under the names it gives".
User documentation: `doc/reference/errors/README.md` ("An @export of clauses with no GIVEN") and one sentence under "Syntax" in `doc/reference/functions/multi-clause-DECIDE.md`.
