# Multi-clause pattern-matching DECIDE (as built on main)

This describes branch `carve/multi-clause-decide` (PR #545, into `main`), re-measured on 2026-10-09.
Every `file:line` below is at the commit that last changed this file; every probe below was run on a binary built from it.
The branch carries work first merged into unstable, one PR at a time, and each section below names its unstable source.
The unstable commits named here are on unstable only: none of them is on this branch or on main.

This branch, oldest first: `d0905e1d8` (the clauses, from #49), `d6594578b` (exact-print, from #130), `17e944423` (the missing-case warning, adapted from #185), `1a67532c7` (clause hygiene, from #569), `f02f0a6b7` (a merge of main), `ee407387b` (ruling M1), `b7c54a6cb` (generated names, printing, editor and render, from #581), `f2d938863` (the missing-case check's limits in the user documentation; this file rewritten for main), `36c549226` (`l4 run --json` reports an evaluation error in the drafter's terms), `6d0146f27` (ruling M2, from legalese/l4-ide#587), the round-2 review's `c8907bf66`, `21df62c92`, `526f70396`, `d0f4c7afa` and `232e14b1b`, the commit that wrote that review into this file (`b1002d9af`), the round-3 fixes `8e4c920ca`, `05559e4ec` and `2113516a1`, and the commit that wrote those into this file.

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

- `topdecl` tries the group parser first: `try (decidePatternMatch sig) <|> decide sig` (`:466`).
- `PMClause`, a parser-internal clause record that never enters the AST (`:734`).
- `decidePatternMatch`, grouping and the commit test (`:757`); `pmClause`, one clause (`:827`).
- `givenTermNames` (`:954`) and `givenTermParams` (`:959`).
- `desugarPatternClauses`, which builds the fused `MkDecide` and records the clause matrix (`:971`).
- `generatedName` (`:1043`), `givenInputBinding` (`:1052`), `scrutineeRef` (`:1060`), `rawTokensAnno` (`:1073`).
- `matchClauses` (`:1101`), `clauseMatchesAnything` (`:1132`), `fallthroughName` (`:1139`), `clausesSrcAnno` (`:1160`), `bindFallthrough` (`:1169`), `generatedConsider` (`:1180`), `matchOne` (`:1186`), `matchLast` (`:1206`).

In `jl4-core/src/L4/Syntax.hs`: `isDistinguishablePat` (`:103`), `patAlwaysMatchesAs` (`:116`) and `isGeneratedName` (`:124`), shared by the parser, the checker, the printer and the editor.

The run-time error is `NonExhaustivePatterns` (`jl4-core/src/L4/EvaluateLazy/Exceptions.hs:46`), thrown at `EvaluateLazy/Machine.hs:1185`.

## Behaviour and rules

Grouping.
The first clause sets the column, the head name and the arity.
Further clauses must start at exactly that column (`withIndent EQ`, `Parser.hs:776`) and have the same raw head name and the same number of argument patterns.
Anything else ends the group, including an intervening `GIVEN`, so type-overloaded definitions, each with its own signature, are never merged.

Clause forms.
`DECIDE head pat… [AKA …] IS|IF body`, or `head pat… [AKA …] MEANS body`.
Argument patterns are atomic, so an applied constructor needs parentheses: `(JUST v)`, `(x FOLLOWED BY xs)`.
The first `AKA` found in any clause is used for the fused head; each clause also keeps its own (`PmMatrixClause`), which the printer writes back on that clause, and a run of overloads gives to its own definition (see "Review round 3" below).

When the group is taken (`isGroup`, `Parser.hs:801`).
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
It reads the input by the input's name respelled with `PreDef` (`scrutineeRef`), which the checker makes another name of the `GIVEN` input (`clauseInputSpellings`, `TypeCheck.hs:768`), so a pattern variable an earlier column binds under that name cannot capture the reference.
A bare name that is not the input's name is a `WHEN` pattern, and the checker decides whether it is a nullary constructor or a fresh variable: in `DECIDE premium other IS 0`, `other` binds the input.
Every non-final clause gets `OTHERWISE <the later clauses>`; the final clause gets no `OTHERWISE`, so a value no clause matches raises `NonExhaustivePatterns` at run time.
The later clauses are bound once per clause boundary, with `LET … IN`, to a nullary local named for what it holds, `the result of clauses 2 to 3` or `the result of clause 3` (`fallthroughName`), also spelled with `PreDef`, and referenced by name, so the tree is linear in clauses times columns.
Each such local `Decide` has its first clause's body as its source range (`clausesSrcAnno`), because the checker keys function signatures by `Decide` range; only the body, so that hover on a pattern between the bodies finds the pattern and not the binding.
The clauses after one in which every column matches without a test are bound too, marked `PmUnreachable`, so that they are checked (see clause hygiene below).

## Diagnostics

- At run time, a generated `CONSIDER` that runs out of branches says "No clause of `k` matches these inputs.", or "The only clause of `z` does not match these inputs." (`Exceptions.hs:110`); a `CONSIDER` the drafter wrote keeps "The value … reached a CONSIDER that has no branch for it." (`:100`).
- A `GIVEN` that does not name one input per pattern, a type-only `GIVEN` included, is one error at the first clause's head (`ClausePatternCountMismatch`, `jl4-core/src/L4/TypeCheck/Types.hs:77`; message at `TypeCheck.hs:3868`): "Each clause of `f` has 2 patterns, but its GIVEN names 1 input."
- A pattern of the wrong type is reported as an input of the group: "The first input of `f` is declared to be of type NUMBER but the pattern written for it here is of type STRING", at the pattern (`ExpectClauseInputContext`, `Types.hs:173`; message at `TypeCheck.hs:4151`).
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

- `jl4-core/src/L4/Syntax.hs`: `PmGroup` (`:541`) and `PmSynthetic` (`:555`: `PmConsider`, `PmFallthrough`, `PmUnreachable`), the `pmSynthetic` field of `Extension` (`:581`), `annPmSynthetic` (`:630`) and `setPmSynthetic` (`:633`); `PmMatrix` has `synthesizedScrutinees` (`:510`) and `catchAll` (`:515`).
- `jl4-core/src/L4/Parser.hs`: `matchClauses` (`:1101`) marks every generated CONSIDER (`generatedConsider`, `:1180`) and binding of later clauses (`bindFallthrough`, `:1169`), and binds the clauses after a clause that matches every input instead of dropping them (`PmUnreachable`); `clauseMatchesAnything` (`:1132`); `givenTermParams` (`:959`).
- `jl4-core/src/L4/TypeCheck.hs`: `settleOneClause` (`:647`), `decideErrorContext` (`:672`), `isClausesBinding` (`:680`), `checkClausesLet` (`:814`, dispatched from `checkExpr` at `:1782`), `speculatively` (`:851`), `warnUnreachableClauses` (`:1063`); `checkConsider` (`:1868`) reads the mark; the messages (`:4069`, `:4151`).
- `jl4-core/src/L4/TypeCheck/Types.hs`: `UnreachableClause` (`:120`), `PatternClauseUnreachable` (`:143`), `ExpectClauseInputContext` (`:173`).
- `jl4-core/src/L4/EvaluateLazy/Exceptions.hs:110` and `Machine.hs` (`consideredClauses`, `:358`): the run-time message in clause terms.

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
Main's own CONSIDER analysis is not reused either: `normalizeRefinement` merges every disjunct into one constraint set (`jl4-core/src/L4/TypeCheck.hs:2599-2606`, with the union at `:2584`), which loses the row structure a group of several columns needs: traced by hand on `f TRUE TRUE` / `f FALSE FALSE`, it reports nothing missing (not run, since a `CONSIDER` has one scrutinee).

Where it lives:

- `jl4-core/src/L4/Syntax.hs`: `PmMatrixClause` and `PmMatrix` (`:477`, `:508`), the `pmMatrix` field of `Extension` (`:580`), `annPmMatrix` and `setPmMatrix` (`:624-628`).
- `jl4-core/src/L4/Parser.hs:1019-1033`: `desugarPatternClauses` records the inputs and each clause's head range and patterns.
- `jl4-core/src/L4/TypeCheck.hs`: `inferDecide` calls `checkClauseMatrix` after checking the body (`:623`); `checkClauseMatrix` (`:878`), `quietly` (`:1095`), `coveragePattern` (`:1112`), `constructorFamilies` (`:1132`), `uncoveredRows` (`:1167`), `maxMissingClauses` (`:1212`), `clauseMatrixFuel` (`:1216`), `patternHasOpaque` (`:1222`); the message (`:4047`) and `prettyMissingClauseLhs` (`:4088`).
- `jl4-core/src/L4/TypeCheck/Types.hs:136`: the warning `PatternClausesMissing`, whose range (`:250`) is the hull of the clause heads.

Behaviour:

- Every group is checked, one clause or many.
- Each clause's patterns are checked again against the `GIVEN` types with every diagnostic discarded (`quietly`); a clause naming its column's `GIVEN` is read as matching anything before that, as the desugarer reads it (`patIsColumnWildcard`, `TypeCheck.hs:1046`, from unstable's `38f0f6fb7`).
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

- The names: `generatedName`, `givenInputBinding`, `scrutineeRef` and `fallthroughName` in `Parser.hs` (see "Where it lives" above); `isGeneratedName` (`Syntax.hs:124`); `clauseInputSpellings` (`TypeCheck.hs:768`), added to scope in `inferDecide` (`:615`).
- The count of inputs: `clauseInputsAgainstGiven` (`TypeCheck.hs:703`), `givenInputsInScope` (`:719`) and `givenMisnamesInputs` (`:728`), used by `scanFunSigDecide` (`:3507`) and `checkClauseMatrix` (`:885`).
- Hover: `recordInputPatterns` (`TypeCheck.hs:899`).
- Printing: the `Decide` printer (`jl4-core/src/L4/Print.hs:265`), `writtenClauses` (`:311`), `clauseHeadPattern` (`:335`), `unusedInputNames` (`:356`), `clauseBodies` (`:368`) and `writtenSignature` (`:391`).
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

- `jl4-core/src/L4/TypeCheck.hs`: `refuseExportedClausesWithoutGiven` (`:750`), called from `inferTopDecl` (`:572`); the message (`:3866`).
- `jl4-core/src/L4/TypeCheck/Types.hs:82`: the error `ExportedClausesWithoutGiven`, whose range (`:246`) is the `@export` annotation's.
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

## Review round 2 (items 1, 2, 3, 5 and 6)

The second review of #545 asked for six changes; item 4, literal patterns in the missing-case check, is being designed separately.
Items 1 to 3 were made for unstable first, on branch `fix/clause-group-round3` (`64e917f1d`, `cdd3e5515`, `cb1167363`), and item 5 is legalese/l4-ide#591 (`635507a96`); none of these commits is on this branch.

Item 1, overloads.
A run of bare-name clauses whose names differ is grouped by the parser, which cannot tell `TRUE` / `FALSE` from two overloads told apart by their types.
`separateOverloads` (`TypeCheck.hs:235`), called from `checkProgram` (`:195`) once the module's types and constructors are in scope and before the definitions' signatures are scanned, turns a group whose patterns are all bare names, none of them a constructor, back into the definitions it is made of: the first with the group's signature and annotation, the rest with no signature, each located from its clause's head to the end of its body (since round 3, each with its own clause's head, `AKA` and annotations).
A group with any constructor name stays a group, a misspelt one included.
Measured: the `show n` / `show b` file failed to check at `6d0146f27` and now gives `show 3` 4 and `show TRUE` TRUE, as main (`71ebf5ca1`) does; `ok/pattern-matching-overloads.l4` pins it.

Item 2, linear parsing.
Every clause of a run the group parser turned down was then parsed as a definition of its own, where the group parser read the rest of the run again, so a file of n lines `f x MEANS i` took time quadratic in n.
`decidePatternMatch` now records the positions of a run it turns down (`turnDownRun`, `Parser.hs:928`) and fails at once at any of them (`runTurnedDown`, `:934`); every suffix of a run turned down is turned down too.
The body of a clause is parsed once per position (`clauseBody`, `:855`; `memoClauseBody`, `:892`), so an ordinary definition replays the body the group parser read.
Both live in `ClauseMemo` (`:861`), a layer below megaparsec in `Parser` (`:68`) that backtracking does not undo, run by `runJl4Parser` (`:2683`).
On unstable the same replay is `memoGroup` (legalese/l4-ide#582), which also serves bracketed groups; main has no `memoGroup`, so `ClauseMemo` holds only these two tables, and main has no switch to turn the memo off for a comparison run.
Measured, `l4 check`: 1,000 lines took 29.5 s at `6d0146f27`; now 2,000 take 0.38 s and 4,000 take 0.73 s.
`PatternMatchParserSpec` required 1,000 lines to parse in less than 8 times the wall-clock time of 250; since round 3 it compares CPU time for 250 and 2,000 lines.

Item 3, the clause after a new name.
`checkClauseMatrix` resolves the patterns even where the missing-clause analysis stands down for a literal, and finds the first clause whose patterns all match anything because some are new names (`newNameCatchAll`, `TypeCheck.hs:983`).
`warnUnreachableClauses` (`:1063`) gives the clauses after it one warning, `AfterClauseBindingNewName` (`Types.hs:125`; message at `TypeCheck.hs:4054`): "This clause of `colour` is never used, because the clause above it with the new name `Gren` matches every input."
Main has no hint for a name close to a value, so there is no CONSIDER-worded hint to translate, as there was on unstable.
This keeps ruling M1's condition: main warns only about clauses after one that matches every input, and a new name does; a repeated clause still draws no warning.
Measured: Red / Gren / Blue checked clean at `6d0146f27` (`colour Blue` gives 2) and now warns; so does a group over numbers with `other`.

Item 5, the clause wording after a reload.
The evaluator words a value no clause matches from `pmSynthetic`, a mark on the annotations of the generated CONSIDERs, and jl4-service's `bundle.cbor` wrote every annotation as `()`.
`Serialise Anno` (`Syntax.hs:1053`) now keeps `pmSynthetic` and nothing else; main serves the CBOR module after every restart, so this is the whole fix here.
`SerialisationSpec` checks the module read back from the bundle and the service before and after a reload; both fail without the change.

Item 6: the `l4 render` test in `jl4/tests-cli` drops carriage returns before matching two lines, for Windows.

Also from the review: the user documentation says clause groups are top level only and cannot have a mixfix head; this spec's source, `PATTERN-MATCHING-SPEC.md`, moved to `specs/done/`; the bench links in the ruling lines are replaced by "ruled by Meng"; and the glossary has an entry for clauses.
Not done here, for later: literal patterns in `jl4-mlir`, which compile as "always matches"; semantic tokens and go-to-definition inside a clause group; and the release notes.

## Review round 3 (the refutation of round 2's fixes)

A refuter probed the round-2 fixes on unstable and found three defects that this branch had too; each was fixed on unstable first, on `fix/clause-group-round3` (`fd4209700`, `0c1844c22`, `182dff94e`), and carried here as `8e4c920ca`, `05559e4ec` and `2113516a1`.

S1 and L1, the overloads' own annotations.
`separateOverloads` gave the first definition the first `AKA` written on any clause, and the later definitions no `AKA`, no `@desc` or `@export`, and no `@nlg`.
Measured at `b1002d9af`: `DECIDE f n IS n + 1` / `DECIDE f m AKA g IS m > 3` gave `g 5` 6, the first overload's answer, with no diagnostic; with an `AKA` on each, the second was not found; with an `@export` above the second, `l4 batch` said "no @export functions found in module"; an `@nlg` above it was "Not attached to any valid syntax node".
Each clause now keeps its head as written, its `AKA` and the `@desc` or `@export` above it in the clause matrix (`PmMatrixClause`, `Syntax.hs:477`), and the annotation passes give a later clause of a run of bare names (`isRunOfBareNames`, `Syntax.hs:526`) the `@desc` or `@export` and the `@nlg` above it (`claimRunClauseDescs`, `claimRunClauseNlgs`, `jl4-core/src/L4/Parser/ResolveAnnotation.hs`).
`separateOverloads` gives each definition its own clause's head, `AKA` and annotations, and the printer writes each clause's own `AKA` (`writtenClauses`, `Print.hs:311`).
Main's printer prints no `@desc` and no `@nlg` for any definition, and `l4 batch` finds its `@export` on the checked module before printing it, so the printer change here is the `AKA` alone; on unstable the printer writes the `@desc` too.
Measured on this branch: `g 5` is TRUE under `l4 run`, `l4 batch` (through an exported rule that calls `g`) and the REPL; the two-`AKA` file gives 6 and TRUE; `l4 batch` finds the `@export` on the second overload and then fails to read a boolean for its untyped input, "Expected JSON number but got: Bool True", the known limit smucclaw/l4-ide#1024; the `@nlg` is attached.
In a group that stays a group, an annotation above a later clause is still used by nothing, as before, and one case became quiet: with `DECIDE k Red IS 1` / `@nlg the green value` / `DECIDE k Green IS 2`, the `@nlg` drew "Not attached to any valid syntax node" at `b1002d9af` and now draws nothing, because it is kept, unused, on the clause in the matrix.
An `@export` there drew no diagnostic before or after.
Test: `ok/pattern-matching-overloads-own-annotations.l4`, and the jl4-service case "publishes the overload whose @export is written above it".

L2, the parse error a turned-down run reports.
`decidePatternMatch` failed at once, with no error of its own, at a clause of a run it had turned down, so megaparsec reported a nearer error than reading the run again would have.
Measured at `b1002d9af`: `f x MEANS 1` / `f x MEANS 2` / `f (x) MEANS 3` / `f x MEANS 4` / `g y MEANS 5` gave its error at 3:3, and at 5:1 with the run memo turned off.
The attempt now records the error it failed with at every clause of the run (`recordRunFailure`, `Parser.hs:942`), and fails with it at any of them; `ClauseMemo` keeps an `IntMap` from position to that error.
Measured with a control binary built with `runTurnedDown` (`Parser.hs:934`) returning nothing, which is the parser without the run memo: on the refuter's 12 parse probes, its 21 fuzzed files on which the memo had changed the output, and the new fixture, `l4 check` gives byte-identical output and exit code with and without the memo; at `b1002d9af`, 23 of those 34 differed.
Main has no switch to turn the memo off and no test comparing the two, so this comparison was made by hand.
Test: `not-ok/tc/pattern-matching-run-parse-error.l4`.

L3, the linear-parsing guard.
It compared wall-clock time, and on a busy machine it failed (the refuter, on unstable: 12 failures in 60 runs with twelve jobs at once).
`PatternMatchParserSpec` now compares the process's CPU time for 250 and 2,000 lines, and fails at a ratio of 24 (linear is about 8, quadratic about 64).

Not carried, because main lacks what they changed: the wording of unstable's hint for a name close to a value (main has no such hint), and a sentence in `specs/done/PATTERN-MATCHING-SPEC.md` (main's copy has no sentence about overloads).
The user documentation's claim that the warning naming a new name "holds for every rule" is corrected: it is not given when a pattern of the rule does not fit its input's type, and not for a new name inside a larger pattern (`doc/reference/errors/README.md`).

A difference from main remains, by the rule round 2 asked for: a parameter spelled like a constructor keeps a run a group.
With `DECLARE Colour IS ONE OF Red, Green`, `DECIDE show Red IS Red + 1` / `DECIDE show b IS b AND TRUE` is a type error on this branch, where main reads two overloads (main's behaviour as the refuter measured it).
