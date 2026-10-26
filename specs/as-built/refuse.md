# `REFUSE` and `#ASSERT REFUSED` (as built)

Scope: the expression `REFUSE "reason"`, the directive `#ASSERT REFUSED`, and what each surface does with a refusal.
The reference page, `doc/reference/control-flow/REFUSE.md`, tells users what they do; this record says where they live and what pins them.
The service's wire form of a refusal is described in `specs/as-built/service-wire-format.md`, and is summarised here only.
Code is cited by module and function, not by line.

## What it does

- `REFUSE "reason"` is an expression of any type that stops evaluation with the author's reason.
  A refusal is an outcome of its own: not a value, not an evaluation error, and not a fact a caller could supply.
- `#ASSERT REFUSED e` holds when `e` refuses, and `#ASSERT REFUSED e BECAUSE "reason"` when it refuses with exactly that reason.
- Core decides, for every directive, whether it answered, refused or stopped with an error, and every surface reports that outcome.
  A refusal is a warning, and neither a success nor a failure.
- Every query planner declines a rule that may refuse, with the reasons it may refuse with, in one sentence that core writes.

## Where it lives

- **Syntax.** `Refuse Anno (Expr n)` is an `Expr`, and `AssertRefused Anno (Expr n) (Maybe (Expr n))` a `Directive` (`L4.Syntax`).
  `REFUSE` is a keyword (`L4.Lexer`).
  The parser takes a string literal after `REFUSE` and after `BECAUSE`, and rejects a `BECAUSE` that starts a line not indented further than its `#ASSERT` (`L4.Parser`).
- **Types.** `L4.TypeCheck` checks the message against `STRING` and gives the `REFUSE` a fresh inference variable, which unifies with whatever type the context expects.
  The message and the `BECAUSE` each have a type error of their own that says a string literal is expected.
- **Evaluation.** A refusal is `RefusalException Refusal`, a top-level arm of `EvalException` (`L4.EvaluateLazy.Exceptions`), raised by `refuseWith` (`L4.EvaluateLazy.Machine`).
  `tryEval` is the only `try` over an `EvalException` in the machine, and it is used only at the directive boundary, so nothing in the language turns a refusal back into a value; the note on `refuseWith` states that as an invariant.
- **Outcomes.** `nfDirective` (`L4.EvaluateLazy`) builds each directive's `EvalDirectiveValue`: `Assertion AssertionOutcome`, which is `Holds`, `Fails`, `FailsBecause`, `Refused` or `Errored`, or `Reduction ReductionOutcome`, which is `Reduced`, `ReducedRefused` or `ReducedErrored`.
  `prettyRefusal` (`L4.EvaluateLazy.Exceptions`) writes "The model refuses to answer:" and the reason's lines, indented.
- **Severity and success.** `evalResultSeverity` and `evalResultSuccess` (`L4.Diagnostic`) give a refusal `DSWarning` and `Nothing`.
  The language server's diagnostics (`LSP.L4.Rules`), its Inspector (`LSP.L4.Inspector`) and the browser API (`L4.API`) take severity and success from them.
- **The marker.** `refusalMarker` and `parseRefusalMarker` (`L4.EvaluateLazy.Exceptions`) write and read `{"kind": "refused", "reason": …}`.
  jl4-service writes a refusal with it: `EvaluatorRefused` (`Backend.Api`) for `/evaluation` and the MCP tools, and `CaseRefused` as `@refused` (`Types`) for `/evaluation/batch`.
- **The command line.** `L4.Cli.Run` writes `"kind": "refused"` for an `#EVAL`, and the reason under `"refused"` for an `#ASSERT`, in `l4 run --json`; `L4.Cli.Batch` gives a refusing row `"status": "refused"`.
- **Traces.** The text trace marks the step with `↯` and `refused:` and the reason (`printExceptionOrNF`, `printEvalExceptionShort` in `L4.EvaluateLazy.Trace`), and the DOT trace labels its node `↯ refused:` and the reason (`L4.EvaluateLazy.GraphViz2`).
- **The REPL.** `jl4-repl/app/Main.hs` prints `Refused:` and the reason.
- **Documents.** `L4.Nlg` writes a `REFUSE` as "the model refuses to answer:" and the reason in curly quotes; `L4.Nlg.Phrasebook` carries its Hebrew.
- **The query plan.** `L4.Refusal`: `refusalReasons` reads, from what is written and without evaluating, the reason of every `REFUSE` a definition may reach, following names through every module it is given; `planDecline` and `declineMessage` give a planner's decline and its sentence.
  The callers are jl4-service (`Backend.DecisionQueryPlan`), the language server (`LSP.L4.Actions`), the REPL, and the web editor's planner (`L4.Decision.EditorQueryPlan` in jl4-query-plan, which jl4-wasm's `QueryPlanWasm` exports to JavaScript); the web editor's ladder shows the decline it is given (`ts-shared/l4-ladder-visualizer/src/lib/eval/query-plan-override.ts`).
- **Depth.** A directive reads a value to a fixed depth; an `#ASSERT REFUSED` whose value goes deeper is "could not be evaluated", with the sentence in `L4.EvaluateLazy.Exceptions`.
  `answerInJust` (`EvalConfig`) makes a caller that asks for `JUST (f args)`, as `l4 batch` and the service's wrapper do, read as deep as a directive that asks for `f args`.
- **The WASM backend.** `jl4-mlir`'s `L4.MLIR.Schema` marks a function that may refuse, by `refusalReasons`, unsupported, with `refuseUnsupportedReason`.

## Behaviour and rules

- `AND`, `OR` and `IF` evaluate left to right and stop when the answer is known, so a refusal they do not reach does not refuse: `FALSE AND r` is `FALSE`, `r AND FALSE` refuses, `TRUE OR r` is `TRUE`.
- `NOT`, `CONSIDER` and `IF` force their operand, so each refuses on a refusal; a `LET` that is not read does not.
- In `REFUSE "a" APPEND "b"`, `REFUSE` takes `"a"`; `REFUSE ("a" APPEND "b")` is a parse error and `REFUSE 42` a type error.
- `l4 run` exits `0` for a refusal, as for an answer, and `1` for an evaluation that stops with an error.
- A plain `#ASSERT` of an expression that refuses reports `assertion refused:` and the reason, at warning severity; in `l4 run --json` it is `"kind": "assertion"`, `"value": null`, and the reason under `"refused"`.
  `doc/check-l4-run-output.sh` fails on a `Result:` followed by a line that holds only `assertion refused:`, so `doc/test-docs.sh` fails on a documentation example with such an `#ASSERT`.
- An `#ASSERT REFUSED` reports `assertion satisfied`; `assertion failed: expected a refusal, but the expression produced a value`; `assertion failed: expected the refusal "…", got "…"`; or `assertion could not be evaluated:` and the cause, an evaluation error or the depth sentence.
- `l4 batch` reports a refusing row and goes on to the next.
- jl4-service answers a refusal at `/evaluation` with `422` and `{"contents": {"kind": "refused", "reason": …}, "tag": "Error"}`; an MCP tool call with `isError: true` and that body as its text; `/evaluation/batch` with `@refused` for the case, counted in `casesProcessed`.
  An error's `contents` carries a `tag` of its own, and an MCP error's text is the message, so `kind` tells the two apart.
- A query planner declines a rule whose `refusalReasons` is not empty, whatever inputs it is given.
  The service answers `400` with `"kind": "declined"`, the `rule`, its `reasons` and `declineMessage`'s sentence, `No query plan for <rule>: it may refuse to answer, with the reason "…".`

## Tests and fixtures that pin it

- **jl4-core-test.** `RefuseSpec` ("REFUSE": the keyword, the grammar and the type rule); `MayRefuseSpec` ("the reasons a definition may refuse with", and "what a query planner answers for a rule that may refuse"); `RefusalReportSpec` ("reporting a refusal").
- **jl4-test.** The corpus files `ok/refuse.l4`, `ok/refuse-polymorphic.l4`, `ok/refuse-uncatchable.l4` and `ok/assert-refused-outcomes.l4`, the `not-ok/tc/` files `refuse-computed-message.l4`, `refuse-nonliteral.l4` and `assert-refused-*.l4`, with their goldens; `KeywordList` holds the editor highlighter's keyword list (`ts-shared/l4-highlight/src/tokens.ts`), `REFUSE` in it, to the lexer's.
- **l4-cli-test.** "l4 run on a directive that refuses", "l4 batch on a row that refuses", "the REPL on an expression that refuses", "the query planners on a rule that may refuse", "l4 run and l4 batch read a long list answer to the same depth", and the refusal cases of "l4 trace", over the fixtures `jl4/tests-cli/fixtures/refuse-*` and `assert-refused-*`.
- **l4-agreement-test.** "every surface gives core's verdict", "every query planner declines a rule as core does, or agrees with core", and "the registry of surfaces", over the agreement corpus.
  "the reference page for REFUSE" holds the page's table to the registry of surfaces: one table, one row for each surface and none for anything else, each row naming a refusal and its reason and no error, the text by which the test reads each text surface quoted in its row, and the query plan's row quoting `declineMessage`'s sentence for the rule `covered` of `doc/reference/control-flow/refuse-example.l4`.
- **jl4-service-test.** `IntegrationSpec` ("returns a case that refuses as refused and processed, and every door carries the same refusal", "a module whose #ASSERT REFUSED has its BECAUSE on a line of its own", and "a rule that may refuse" under the query plan); `QueryPlanSpec` ("a rule that may refuse"); `QueryPlanWasmDeclineSpec` ("the web editor's query planner, run natively": `L4.Decision.EditorQueryPlan`); `SchemaSpec` (a refused case read and written back).
- **jl4-mlir.** "REFUSE marks the export unsupported", and the deontic `REFUSE` cases beside it.
- **TypeScript.** `declined-ladder.test.ts`, `query-plan-override.test.ts` and `with-elicitation-override.test.ts` in `ts-shared/l4-ladder-visualizer`, and `tools.test.ts` in `ts-shared/legalese-agent`.
- **Documentation.** `doc/test-docs.sh` runs `doc/reference/control-flow/refuse-example.l4` and checks its output with `doc/check-l4-run-output.sh`.

## Limits

- The reason is a string literal: a computed reason, such as `REFUSE (1 PLUS 1)`, is a parse error, and `REFUSE 42` a type error.
- Under `IMPORT daydate`, `PLUS` has more than one meaning, and a refusal added to a number checks where its type is settled: by a `GIVETH A NUMBER` on a named refusal or on a rule whose answer is the sum, or by what the sum is used for, such as `TIMES` or a function whose input is a number; brackets do not settle it, and a refusal declared for any type does not either.
  Where nothing settles it, as in a rule with no `GIVETH` whose body is `1 PLUS REFUSE "…"` alone, or in `(1 PLUS REFUSE "…") EQUALS (1 PLUS REFUSE "…")` even in a rule with `GIVETH A NUMBER`, the type checker reports "There are multiple definitions for the identifier".
- The WASM backend does not run a function that may refuse; jl4-service evaluates it.
- An `#ASSERT REFUSED` of a value deeper than a directive reads cannot say whether it refuses below that depth, and reports that it could not be evaluated.
- `specs/as-built/service-wire-format.md` states where two of the service's doors read inputs differently, and so can answer where a batch case refuses.
- "the reference page for REFUSE" compares the page with the registry of surfaces and with the constants the agreement test reads output by; it does not compare the rows of the surfaces that answer in JSON, or the paragraph below the table, with any surface's output.
