# Multi-clause pattern-matching DECIDE (as built on main)

This describes branch `carve/multi-clause-decide` (PR #545, into `main`), re-measured on 2026-10-09.
Every `file:line` below is at the commit that last changed this file; every probe below was run on a binary built from it.
The branch carries work first merged into unstable, one PR at a time, and each section below names its unstable source.
The unstable commits named here are on unstable only: none of them is on this branch or on main.

This branch, oldest first: `d0905e1d8` (the clauses, from #49), `d6594578b` (exact-print, from #130), `17e944423` (the missing-case warning, adapted from #185), `1a67532c7` (clause hygiene, from #569), `f02f0a6b7` (a merge of main), `ee407387b` (ruling M1), `b7c54a6cb` (generated names, printing, editor and render, from #581), `f2d938863` (the missing-case check's limits in the user documentation; this file rewritten for main), `36c549226` (`l4 run --json` reports an evaluation error in the drafter's terms), `6d0146f27` (ruling M2, from legalese/l4-ide#587), the round-2 review's `c8907bf66`, `21df62c92`, `526f70396`, `d0f4c7afa` and `232e14b1b`, and the commit that wrote that review into this file.

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

- `topdecl` tries the group parser first: `try (decidePatternMatch sig) <|> decide sig` (`:467`).
- `PMClause`, a parser-internal clause record that never enters the AST (`:735`).
- `decidePatternMatch`, grouping and the commit test (`:758`); `pmClause`, one clause (`:827`).
- `givenTermNames` (`:935`) and `givenTermParams` (`:940`).
- `desugarPatternClauses`, which builds the fused `MkDecide` and records the clause matrix (`:952`).
- `generatedName` (`:1021`), `givenInputBinding` (`:1030`), `scrutineeRef` (`:1038`), `rawTokensAnno` (`:1051`).
- `matchClauses` (`:1079`), `clauseMatchesAnything` (`:1110`), `fallthroughName` (`:1117`), `clausesSrcAnno` (`:1138`), `bindFallthrough` (`:1147`), `generatedConsider` (`:1158`), `matchOne` (`:1164`), `matchLast` (`:1184`).

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
The first `AKA` found in any clause is used for the fused head.

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
It reads the input by the input's name respelled with `PreDef` (`scrutineeRef`), which the checker makes another name of the `GIVEN` input (`clauseInputSpellings`, `TypeCheck.hs:765`), so a pattern variable an earlier column binds under that name cannot capture the reference.
A bare name that is not the input's name is a `WHEN` pattern, and the checker decides whether it is a nullary constructor or a fresh variable: in `DECIDE premium other IS 0`, `other` binds the input.
Every non-final clause gets `OTHERWISE <the later clauses>`; the final clause gets no `OTHERWISE`, so a value no clause matches raises `NonExhaustivePatterns` at run time.
The later clauses are bound once per clause boundary, with `LET … IN`, to a nullary local named for what it holds, `the result of clauses 2 to 3` or `the result of clause 3` (`fallthroughName`), also spelled with `PreDef`, and referenced by name, so the tree is linear in clauses times columns.
Each such local `Decide` has its first clause's body as its source range (`clausesSrcAnno`), because the checker keys function signatures by `Decide` range; only the body, so that hover on a pattern between the bodies finds the pattern and not the binding.
The clauses after one in which every column matches without a test are bound too, marked `PmUnreachable`, so that they are checked (see clause hygiene below).

## Diagnostics

- At run time, a generated `CONSIDER` that runs out of branches says "No clause of `k` matches these inputs.", or "The only clause of `z` does not match these inputs." (`Exceptions.hs:110`); a `CONSIDER` the drafter wrote keeps "The value … reached a CONSIDER that has no branch for it." (`:100`).
- A `GIVEN` that does not name one input per pattern, a type-only `GIVEN` included, is one error at the first clause's head (`ClausePatternCountMismatch`, `jl4-core/src/L4/TypeCheck/Types.hs:77`; message at `TypeCheck.hs:3991`): "Each clause of `f` has 2 patterns, but its GIVEN names 1 input."
- A pattern of the wrong type is reported as an input of the group: "The first input of `f` is declared to be of type NUMBER but the pattern written for it here is of type STRING", at the pattern (`ExpectClauseInputContext`, `Types.hs:173`; message at `TypeCheck.hs:4274`).
- The missing-case warning and the never-used warning are described below.
- Because the pattern parser is tried first, a malformed `DECIDE` head lists pattern tokens among the expected ones: `expecting (, AKA, EXACTLY, Float Literal, IF, IS, Numeric Literal, OF, String Literal, identifier, or space token` (`jl4/examples/not-ok/tc/tests/parse-error4.golden:14`).

## Tests and fixtures that pin it

- `jl4-core/test/PatternMatchParserSpec.hs` (in `jl4-core-test`), six cases: literal and variable clauses group into one `CONSIDER`-bodied `Decide`; `EMPTY`/`FOLLOWED BY` clauses group; a single literal clause desugars; a single variable clause is left alone; two different heads stay two `Decide`s; and a group's range stops at its own lines and the file exact-prints unchanged.
- `jl4-core/test/PatternClausesMissingSpec.hs`, 76 cases, and `jl4-core/test/MultiClausePrintSpec.hs`, both described below.
- `jl4/examples/ok/`: `pattern-matching.l4` (factorial, fib, list length, `from maybe`, a two-column decision table, nested `(JUST (JUST k))`), `pattern-matching-nullary.l4`, `pattern-matching-decision-table.l4`, `pattern-matching-clause-hygiene.l4`, `pattern-matching-one-clause-fallback.l4`, `pattern-matching-fallthrough-name.l4`, `pattern-matching-input-names.l4` and `pattern-matching-literal-clauses.l4`, each with its four goldens under `tests/`.
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

- `jl4-core/src/L4/Syntax.hs`: `PmGroup` (`:517`) and `PmSynthetic` (`:531`: `PmConsider`, `PmFallthrough`, `PmUnreachable`), the `pmSynthetic` field of `Extension` (`:557`), `annPmSynthetic` (`:606`) and `setPmSynthetic` (`:609`); `PmMatrix` has `synthesizedScrutinees` (`:497`) and `catchAll` (`:502`).
- `jl4-core/src/L4/Parser.hs`: `matchClauses` (`:1079`) marks every generated CONSIDER (`generatedConsider`, `:1158`) and binding of later clauses (`bindFallthrough`, `:1147`), and binds the clauses after a clause that matches every input instead of dropping them (`PmUnreachable`); `clauseMatchesAnything` (`:1110`); `givenTermParams` (`:940`).
- `jl4-core/src/L4/TypeCheck.hs`: `settleOneClause` (`:654`), `decideErrorContext` (`:679`), `isClausesBinding` (`:687`), `checkClausesLet` (`:821`, dispatched from `checkExpr` at `:1928`), `speculatively` (`:858`), `warnUnreachableClauses` (`:1076`); `checkConsider` (`:2071`) reads the mark; the messages (`:4200`, `:4322`).
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
Main's own CONSIDER analysis is not reused either: `normalizeRefinement` merges every disjunct into one constraint set (`jl4-core/src/L4/TypeCheck.hs:2722-2729`, with the union at `:2581`), which loses the row structure a group of several columns needs: traced by hand on `f TRUE TRUE` / `f FALSE FALSE`, it reports nothing missing (not run, since a `CONSIDER` has one scrutinee).

Where it lives:

- `jl4-core/src/L4/Syntax.hs`: `PmMatrixClause` and `PmMatrix` (`:473`, `:495`), the `pmMatrix` field of `Extension` (`:556`), `annPmMatrix` and `setPmMatrix` (`:600-604`).
- `jl4-core/src/L4/Parser.hs:1000-1011`: `desugarPatternClauses` records the inputs and each clause's head range and patterns.
- `jl4-core/src/L4/TypeCheck.hs`: `inferDecide` calls `checkClauseMatrix` after checking the body (`:626`); `checkClauseMatrix` (`:885`), `quietly` (`:1108`), `coverageRow` (`:1141`), `coveragePattern` (`:1181`), `constructorFamilies` (`:1244`), `uncoveredRows` (`:1308`), `maxMissingClauses` (`:1384`), `clauseMatrixFuel` (`:1422`); the message (`:4193`) and `prettyMissingClauseLhs` (`:4370`).
- `jl4-core/src/L4/TypeCheck/Types.hs:136`: the warning `PatternClausesMissing`, whose range (`:250`) is the hull of the clause heads.

Behaviour:

- Every group is checked, one clause or many.
- Each clause's patterns are checked again against the `GIVEN` types with every diagnostic discarded (`quietly`); a clause naming its column's `GIVEN` is read as matching anything before that, as the desugarer reads it (`patIsColumnWildcard`, `TypeCheck.hs:1059`, from unstable's `38f0f6fb7`).
- The missing rows are computed by specialisation and the default matrix (Maranget, "Warnings for pattern matching", JFP 2007, §3.1 and §5), over the constructors main's `CONSIDER` analysis knows: `TRUE`/`FALSE` and the enumerations and records declared in the module (`constructorFamilies` reads the same declarations as `buildConstructorLookup`).
- In each suggested clause, an input that the missing case leaves open is written as its `GIVEN` name, or as `` `_` `` when the user wrote no `GIVEN` for it (#185's `renderColumnWildcard` wrote the parser's `_pm_arg_i` there, measured on unstable at `568817a6d`), and an applied constructor is parenthesised, so each suggested `DECIDE … IS` line can be pasted.
- The warning text is unstable's: "This multi-clause definition does not cover all cases. The following clauses are still needed:".

Limits.
Each is fail-open: the check gives up with no warning, and no diagnostic says that it gave up (assumed, not ruled, 2026-10-08: the user documentation names the limits instead).

- A group matching lists (`EMPTY`, `FOLLOWED BY`), or values of a type declared in another module (such as `MAYBE` from the prelude), is checked only as far as the analysis need not tell those values apart: main's constructor lookup does not know those constructors, so the analysis gives up where it meets one as a column head, and answers where a row of wildcards or the other columns settle the question first (`t Red EMPTY` / `t Red xs` / `t Green xs` lists `Blue xs`; `f Red (JUST 0)` / `f Green m` lists `Red m` and `Blue m` through the coarse tier; `show NOTHING` / `show (JUST 0)` and `f (JUST 0)` / `f (JUST n)` are silent).
  A group whose every clause has a number or a piece of text in it is answered by the coarse tier below with the one all-names clause (`f (JUST 0)` alone suggests ``DECIDE `f` m IS``).
- An `EXACTLY` the analysis cannot read: on an enumeration or `BOOLEAN` input, any `EXACTLY` other than a value of the input's type or the input's own name; on any input, an `EXACTLY` whose expression mentions the input itself; inside a pattern, the same by the type of the position, read off the pattern's annotation after the re-check's substitution, and an `EXACTLY` of a value it cannot name where that type is still an inference variable.
  On a number, text or date input or field, or one declared under another name for one (`DECLARE Age IS A NUMBER`; synonyms are expanded for the analysis, `expandSynonymsIn`, `:1223`), an `EXACTLY` of a value the analysis cannot name (`EXACTLY someConstant`, at the top of a clause or inside a pattern, as in `f (Box (EXACTLY zero))` / `f (Box n)`) leaves its clause out instead of stopping the group, and the group then gets the coarse list alone; see "Literal patterns" below.
- More than 64 rows at any level of the analysis (`maxMissingClauses`), or more than 10000 steps (`clauseMatrixFuel`), in both tiers.
- A pattern that does not re-check against its `GIVEN` type.
- There is no `@nonexhaustive`, so a group cannot be marked deliberately partial.
- #185's DMN channel (`siClauseMatrixRanges`) is not carried: main has no DMN export.

Tests: `jl4-core/test/PatternClausesMissingSpec.hs` (76 cases, matching warnings by severity and rendered text): the 14 from `17e944423` less the number silence, including the silences for lists, `MAYBE`, an enumeration from another file and the 64-row cap; eight for clause hygiene; and the literal-pattern cases listed under "Literal patterns" below, which replaced the three that pinned the former silences for a number anywhere, an `EXACTLY` pattern and the nine-input step limit.
`jl4/tests-cli` "warns that a multi-clause DECIDE misses a case, and still succeeds" (fixture `tests-cli/fixtures/multi-clause-missing.l4`).

## Generated names, printing, editor and render (from #581)

Unstable PR #581 (branch `fix/multi-clause-names`, six commits ending at `796cc8eb1`, not merged into unstable when this was carried) is carried as one commit, `b7c54a6cb`, because each part needed adapting to main's printer, test harnesses and AST, and the parts depend on each other.

Where it lives:

- The names: `generatedName`, `givenInputBinding`, `scrutineeRef` and `fallthroughName` in `Parser.hs` (see "Where it lives" above); `isGeneratedName` (`Syntax.hs:124`); `clauseInputSpellings` (`TypeCheck.hs:765`), added to scope in `inferDecide` (`:612`).
- The count of inputs: `clauseInputsAgainstGiven` (`TypeCheck.hs:700`), `givenInputsInScope` (`:716`) and `givenMisnamesInputs` (`:725`), used by `scanFunSigDecide` (`:3504`) and `checkClauseMatrix` (`:882`).
- Hover: `recordInputPatterns` (`TypeCheck.hs:896`).
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

- `jl4-core/src/L4/TypeCheck.hs`: `refuseExportedClausesWithoutGiven` (`:747`), called from `inferTopDecl` (`:569`); the message (`:3863`).
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

The second review of #545 asked for six changes; item 4, literal patterns in the missing-case check, is under "Literal patterns (review round 2, item 4)" below.
Items 1 to 3 were made for unstable first, on branch `fix/clause-group-round3` (`64e917f1d`, `cdd3e5515`, `cb1167363`), and item 5 is legalese/l4-ide#591 (`635507a96`); none of these commits is on this branch.

Item 1, overloads.
A run of bare-name clauses whose names differ is grouped by the parser, which cannot tell `TRUE` / `FALSE` from two overloads told apart by their types.
`separateOverloads` (`TypeCheck.hs:234`), called from `checkProgram` (`:195`) once the module's types and constructors are in scope and before the definitions' signatures are scanned, turns a group whose patterns are all bare names, none of them a constructor, back into the definitions it is made of: the first with the group's signature and annotation, the rest with none, each located from its clause's head to the end of its body.
A group with any constructor name stays a group, a misspelt one included.
Measured: the `show n` / `show b` file failed to check at `6d0146f27` and now gives `show 3` 4 and `show TRUE` TRUE, as main (`71ebf5ca1`) does; `ok/pattern-matching-overloads.l4` pins it.

Item 2, linear parsing.
Every clause of a run the group parser turned down was then parsed as a definition of its own, where the group parser read the rest of the run again, so a file of n lines `f x MEANS i` took time quadratic in n.
`decidePatternMatch` now records the positions of a run it turns down (`turnDownRun`, `Parser.hs:922`) and fails at once at any of them (`runTurnedDown`, `:928`); every suffix of a run turned down is turned down too.
The body of a clause is parsed once per position (`clauseBody`, `:855`; `memoClauseBody`, `:891`), so an ordinary definition replays the body the group parser read.
Both live in `ClauseMemo` (`:861`), a layer below megaparsec in `Parser` (`:69`) that backtracking does not undo, run by `runJl4Parser` (`:2661`).
On unstable the same replay is `memoGroup` (legalese/l4-ide#582), which also serves bracketed groups; main has no `memoGroup`, so `ClauseMemo` holds only these two tables, and main has no switch to turn the memo off for a comparison run.
Measured, `l4 check`: 1,000 lines took 29.5 s at `6d0146f27`; now 2,000 take 0.38 s and 4,000 take 0.73 s.
`PatternMatchParserSpec` requires 1,000 lines to parse in less than 8 times the time of 250.

Item 3, the clause after a new name.
`checkClauseMatrix` resolves the patterns even where the missing-clause analysis stands down (a list, a `MAYBE` value, an `EXACTLY` it cannot read), and finds the first clause whose patterns all match anything because some are new names (`newNameCatchAll`, `TypeCheck.hs:996`).
`warnUnreachableClauses` (`:1076`) gives the clauses after it one warning, `AfterClauseBindingNewName` (`Types.hs:125`; message at `TypeCheck.hs:4326`): "This clause of `colour` is never used, because the clause above it with the new name `Gren` matches every input."
Main has no hint for a name close to a value, so there is no CONSIDER-worded hint to translate, as there was on unstable.
This keeps ruling M1's condition: main warns only about clauses after one that matches every input, and a new name does; a repeated clause still draws no warning.
Measured: Red / Gren / Blue checked clean at `6d0146f27` (`colour Blue` gives 2) and now warns; so does a group over numbers with `other`.

Item 5, the clause wording after a reload.
The evaluator words a value no clause matches from `pmSynthetic`, a mark on the annotations of the generated CONSIDERs, and jl4-service's `bundle.cbor` wrote every annotation as `()`.
`Serialise Anno` (`Syntax.hs:1029`) now keeps `pmSynthetic` and nothing else; main serves the CBOR module after every restart, so this is the whole fix here.
`SerialisationSpec` checks the module read back from the bundle and the service before and after a reload; both fail without the change.

Item 6: the `l4 render` test in `jl4/tests-cli` drops carriage returns before matching two lines, for Windows.

Also from the review: the user documentation says clause groups are top level only and cannot have a mixfix head; this spec's source, `PATTERN-MATCHING-SPEC.md`, moved to `specs/done/`; the bench links in the ruling lines are replaced by "ruled by Meng"; and the glossary has an entry for clauses.
Not done here, for later: literal patterns in `jl4-mlir`, which compile as "always matches"; semantic tokens and go-to-definition inside a clause group; and the release notes.

## Literal patterns (review round 2, item 4)

The reviewer's item 4: let the missing-case check cope with number and text patterns instead of giving up (`hasOpaque`).
Designed in the session's `scratchpad/clause-literals/wf-finalDesign.md`, critiqued adversarially there (`wf-soundness.md`, `wf-fit.md`), built on unstable first (branch `fix/clause-literals`, on unstable's guard model, not merged as of 2026-10-09) and then here on main's own engine (ruling M1), in two commits that can be reverted alone, plus one per fix after the review of this build (see below).

What changed, 2026-10-09:

- `coveragePattern` (`TypeCheck.hs:1181`) reads a number or a piece of text, bare or under `EXACTLY`, as one value of its column (`CovLit`, keyed by `LitKey`, `:1128`: `1` and `1.0` are one key, as the evaluator compares them); `EXACTLY` of a value of the column's type as that value; `EXACTLY` of the column's own input as a wildcard; any other `EXACTLY` as a clause that counts for nothing on a number, text or date input (`isPrimitiveType`, `:2538`, after synonym expansion, `expandSynonymsIn`, `:1223`), and as a bail on any other input, or on any input when its expression mentions the input itself.
  The top-level column is classified by its type after substitution and synonym expansion; a nested position by its annotation, which the re-check resolves through its substitution before that is dropped, and which is expanded through synonyms the same way, so an `EXACTLY` of a constant at a number position inside a pattern counts for nothing too (since 2026-10-09, in step with unstable); an inference variable still left there bails.
  `hasOpaque` and `patternHasOpaque` are gone.
- `uncoveredRows` (`:1308`) takes the column count, so that no rows at all yield the one all-wildcard row; a row of wildcards ends the recursion; a column of numbers or text recurses into each key the rows name, in the order the rows first name them, and then into the wildcard rows for the rest of the column, which renders as the input's name (`renderRow`).
  Two tiers: the exact partition, and when that bails (the cap, the fuel, or a constructor it cannot enumerate below a key) the same engine over the rows without a number or a piece of text, with fresh fuel; a group with no number or text in it has only the first tier, and a group with a clause left out only the second.
- `prettyMissingPattern` (`:4380`) prints a number as its clause spelled it, from the token on its annotation (`literalAsWritten`, `:4410`): `1.50` stays `1.50`, `-1` keeps its sign, and `0.1234567890123456789` keeps every digit, where `prettyRatio` rounds past sixteen.
  A piece of text prints through `L4.Print`'s own printer, every printable character as it is and `"` and `\` escaped, because the lexer keeps only the decoded text and the token's own display would write `"São Paulo"` as `"S\227o Paulo"`; a text with a character that does not print keeps that Haskell-style form, which L4 reads back.
- `settleOneClause` (`:654`): a one-clause group with a number in it now gets a verdict, so its CONSIDER warnings are withdrawn.

Decisions, all assumed, not ruled, 2026-10-09, each kept so that it can be reverted alone:

- M-A: the exact partition when it fits, keyed gaps first and then the row with the input's name (`charge 1 Basic` / `level Basic` / `level Premium`, over a `Tier` that also has `Gold`, lists `1 Gold` then `level Gold`), in its own commit ("check: list every gap of a clause group over numbers or text exactly"); reverting it leaves option (b), the coarse list alone, with no number or text in any suggested clause (the engine commit's tests pin that state: the same table lists `level Gold` alone).
- M-B: no redundancy analysis on main, so ruling M1's condition stands: `g 0` / `g 0` / `g n`, `h 1` / `h 1.0`, and a clause after `EXACTLY n` draw no warning here, where unstable reports each as never used.
- M-C: the warning text is unchanged when the coarse tier answers; the user documentation says that a gap inside the table is then not listed.
- M-D: ~~a hand-written `CONSIDER` over a number or a piece of text still gets no warning (`checkConsider`'s gates are untouched), and the user documentation says that the two spellings of one rule differ; waits on Meng's word GANDER.~~ Ruled GANDER, 2026-10-09T06:15Z, and built: a `CONSIDER` with a number, a piece of text or an `EXACTLY` in any arm is analysed by the clauses' engine as a group of one column with the scrutinee as its input (`considerWithLiterals`); a missing case renders as `WHEN … THEN` or `OTHERWISE` (`prettyMissingBranchLhs`, keys as the arms spell them, on one line), and an arm is redundant when the arms above it match everything it matches (`coveredBy`, by specialisation), an arm that matches anything never.
  It also fixes the defect the comparison with unstable found (v07): main's own analysis read a literal or `EXACTLY` arm as matching anything, so `WHEN EXACTLY Red` / `WHEN Green` / `OTHERWISE` called `Green` redundant (`pick Green` is 2), and a `CONSIDER` whose only arm was `WHEN EXACTLY Red` passed and failed at run time.
  ~~A `CONSIDER` with none of them keeps main's own analysis (`considerWithoutLiterals`), unchanged.~~
  Ruled HIGHLANDER, fired 2026-10-09T15:12Z, and built 2026-10-10: a `CONSIDER` written by hand goes to the clauses' engine with or without a number in it, unless a value of its scrutinee's type can hold a `MAYBE` or a `LIST` (`holdsUnlistedType`: the type itself, an argument, or a field of a type declared in the module as the scrutinee's type fills in its parameters, at any depth), which keeps main's own analysis, because the clauses' engine stands down there where main's own analysis lists part of what is missing.
  `EITHER` is in the exception too, assumed, not ruled: it stands down the same way (`WHEN LEFT Basic` over `EITHER Tier Tier` is told `WHEN LEFT Gold` by main's own analysis, and nothing by the clauses' engine).
  So is a type declared in another module, assumed, not ruled, in its own commit: a record declared here with a field of an imported enumeration, `Paint HAS c IS A Colour, t IS A Tier`, and the one arm `WHEN Paint Red Basic`, is told `WHEN Paint Red Gold` by main's own analysis and nothing by the clauses' engine, whose constructor families are this module's declarations.
  A `CONSIDER` generated from clauses keeps the routing by numbers, text and `EXACTLY`.
  When the clauses' engine gives up on a `CONSIDER` HIGHLANDER sent it (past 64 rows or 10000 steps), main's own analysis reads that `CONSIDER` instead, assumed, not ruled, 2026-10-10, after refute-gander found it silent: `Rec HAS f0, f1, f2` over six values with three arms has 208 missing values, of which ceeeca095 lists 108 and the build before this fallback none; on 150 random incomplete tables of 2 to 5 such fields, ceeeca095 warned where that build was silent 32 times, and this one never.
  The fallback brings back main's own analysis's cost with its answers: where ceeeca095 runs past 15 s on a table (5 of those 150; 30 s and 137 s for the two timed alone), so does this build, where the build before was silent at once; of those two, one ends with no warning and the other lists 24576 rows.
  A generated `CONSIDER` keeps the silent cap, as a group of clauses does.
  Not fixed, measured 2026-10-10: a missing-case warning at every level of a nested `CONSIDER` costs time cubic in the depth, because each diagnostic's context is searched for a type to resolve (`contextChanges`, which keeps the context shared when it finds none), and the context of a warning at depth k holds k levels, each holding every level inside it.
  100, 200 and 300 levels take 0.34 s, 2.24 s and 6.64 s here, and 0.44 s, 3.15 s and 9.37 s on unstable, which has the same code (refute-gander measured 33 s and 44 s at 500); base unstable takes 0.06 s to 0.09 s, warning at no level; residency stays at 1 to 6 MB.
  Searching each level once would need an identity for a level, or a new field in the context's type, which every diagnostic is built with, so it was left.
  It fixes smucclaw/l4-ide#1030: main's own analysis read a constructor's fields as one set of constraints, so `WHEN fab` / `WHEN faz qux qux` was told six of the eight missing `faz` arms, and with those six added nothing, though `faz bar qux` and `faz baz qux` still failed at run time; the clauses' engine lists ``faz bar `_` ``, ``faz baz `_` ``, `faz qux bar` and `faz qux baz`, and then the two.
  Measured with the session's fuzzer (`scratchpad/clause-literals/gander/fzm/fuzz5.py`, seeds 91 to 94, 600 groups each): the clause form and the `CONSIDER` form of a group disagree on whether it warns 12 times on the build before, 3 times after, all three over a record with a `MAYBE` or a `LIST` field, which the exception keeps on main's own analysis; two of the three are main's own analysis asking for cases after an arm that matches everything (`WHEN Row2 v1 v2` / `WHEN Row2 Gold v2` is told ``Row2 Basic `_` `` and ``Row2 Premium `_` ``).
  A redundant arm prints as written (`prettyBranchAsWritten`): the generic printer wrote the redundant `WHEN 1.0` after `WHEN 1` as `WHEN 1`, naming the other arm.
- Beyond the design, in its own commit: an `EXACTLY` whose expression mentions the input itself, such as `EXACTLY (n PLUS 0)`, which matches every `n`, stands the group down on any input, because the design's argument for leaving such a clause out (it matches one value of the column per value of the other columns) does not hold for it; by the algorithm as designed, `f (EXACTLY (n PLUS 0))` / `f 0` would have suggested `f n`, a clause that would never be used.
  Unstable's first fix for the same hole stood the group down when the expression named any input, in any column; main's rule is the narrower one, and it holds (an expression naming only other inputs still matches one value of its column per value of theirs: `f a (EXACTLY a)` / `f 0 b` lists `a b`, and `f 1 2` has no clause).
  Unstable adopted it on 2026-10-09 (`433bee2d9` on `fix/clause-literals`), so both branches now use this rule.

Measured on this build, in `jl4-core/test/PatternClausesMissingSpec.hs` and the probes under the session's `scratchpad/clause-literals/impl-main/`:

- The cap: 63 keys × `Basic` over `Tier` list the 63 keyed rows and `n t`; 64 keys would list 65, over the cap, so the coarse tier lists `n t` alone; the enumeration control (E1..E64 × `Basic`) still lists 64 rows and falls silent at 65.
- The fuel: a row of wildcards ends the recursion, so the nine-input `pick` table (each input tested for `Red` in one clause and for `Green` in another), which used to run out of steps, lists `Blue` nine times, and its twin over numbers lists `n1 … n9`; a cross table of 100 keys on each of two inputs lists `n k`.
  None of the tests reaches the 10000-step limit on this build; it is kept as a guard.
- Residues against unstable, all predicted by the design: `MAYBE` and `LIST` values are read here only as far as the analysis need not tell them apart (`show NOTHING` / `show (JUST 0)` is silent; `f (JUST 0)` alone suggests `f m`, where unstable lists `NOTHING` and ``(JUST `_`)``); the one-clause `f Red (JUST x)` keeps its CONSIDER warning (`WHEN Green THEN`, `WHEN Blue THEN`), where unstable lists three clauses; `@nonexhaustive` is a lexer error here.
  Not predicted, and cosmetic: unstable listed rows in another order (by how many numbers or texts they name, and in its engine's order among rows that name none: `E63 Premium` … `E1 Premium`, `Blue n` before `Red n`); since 2026-10-09 it lists them in main's order (`d07697484` on `fix/clause-literals`).
  Not a difference in the check: `§` followed by an indented `GIVEN n` is a section binder on unstable, an assumed value that is not the definition's input, and the definition's own `GIVEN` here, so the same clauses `f 0` / `f 1` under it list `f n` here and ``f `_` `` there, and `f 0 IS n PLUS 100` gives `100` here and asks for `n` there.

Fixed after the adversarial review of this build (2026-10-09), one commit each: a text key printed with the lexer token's Haskell-style escapes (`"S\227o Paulo"`); a number input declared under another name (`DECLARE Age IS A NUMBER`) stopped the group on an `EXACTLY` of a constant instead of counting it for nothing; the coarse tier re-ran the same rows for a group with no number or text; and the tests the review asked for: `EXACTLY n` beside an enumeration (`f 0 Red` / `f (EXACTLY n) Green` lists `0 Blue`, `n Red`, `n Blue`, and reads as `n c` alone without the own-name case), a `MAYBE` below a key that reaches the coarse tier (`f 0 (JUST x)` / `f 1 m` lists `n m`), the silence boundary for lists, `MAYBE` values and another file's enumeration, the nested `EXACTLY` under a record's field, a negative key, and keys written under `EXACTLY`.

Aligned with unstable after its own review (2026-10-09), one commit each: an `EXACTLY` of a constant at a number position inside a pattern counts for nothing, as at the top level, where it stood the group down because the re-check's substitution was dropped before the position's type was read (`f (Box (EXACTLY zero)) Premium` / `f (Box n) Basic` lists ``(Box `_`) Premium``; the test that pinned the silence now pins the warning); and a field declared under another name for a number is a number position, as an input already was.
And, after the refutation of unstable's `99b1936cf` the same day: a group with a clause left out gets the coarse list alone, because the exact partition could list a keyed gap the left-out clause covers (`f 2 "b"` / `f (EXACTLY two) s` / `f 1 s` listed `2 s` and `n s`, and every `(2, s)` meets the second clause; `g (EXACTLY b) (EXACTLY a) Standard` / `g a "c" Plus` / `g "c" "a" p` / `g a "c" Gold` listed `"c" "c" Standard`); each coarse row still holds a value no clause matches, since a left-out clause matches one value of its position for each value of the others.

Tests for literal patterns, in `PatternClausesMissingSpec`, by group: numbers and text with and without a catch-all (`describe`, `code`, `sign`, `half`); `EXACTLY` of a number, of a value of the input's type, of a constant on an enumeration input, over another file's enumeration, over a `MAYBE` value, of the input's own name (alone and beside an enumeration), of a constant on a number input and under a record's field, and of an expression that mentions the input itself or another input; tables keyed by a number, by text, by a number beside an enumeration, by two numbers, and the gap under one key before the rest; one-clause groups over a number, with and without an enumeration beside it; a record with a number field; the silences for lists, `MAYBE` values and another file's enumeration and their boundary; the coarse tier for a `MAYBE` under every clause's number and below a key; a repeated number and `1` after `1.0`; a key's first spelling, every digit, the sign, `EXACTLY`'s spelling and a text key's characters; the cap at sixty-four rows against its enumeration control; the nine-input tables over enumerations and over numbers; a group without a `GIVEN`; a synonym of `NUMBER`, as an input and as a record's field; and the coarse list alone when a clause is left out, for an `EXACTLY` of a constant and for one that names only other inputs.

Tests for a `CONSIDER` written by hand, in the same file (`considerSpec`, eight cases, GANDER): the arm after `WHEN EXACTLY Red` is reached and the `CONSIDER` whose only arm it is lists `Green` and `Blue` (v07, both red on `7bbe2499f`); `OTHERWISE` for a number and for a text; a repeated number as a redundant arm; the gap under a key in a record, spelled as the arm spells it; `EXACTLY` of a constant over a number and over an enumeration; an `EXACTLY` that mentions the scrutinee; and the coarse list alone when an arm is left out.
And for one with none of them (`plainConsiderSpec`): a constructor no arm names is written with a `_` per field, and every missing combination of a constructor's fields is listed, before and after the asked-for arms are added (smucclaw/l4-ide#1030, HIGHLANDER; red on `ceeeca095`).

Corpus: `ok/pattern-matching-literal-clauses.l4` is new, with this tree's goldens recording only its `#EVAL`s; `ok/pattern-matching-one-clause-fallback.l4`'s number example became the `MAYBE` one; `not-ok/tc/pattern-matching-export-without-given.l4`'s golden gains the warning for `discount 0`.
