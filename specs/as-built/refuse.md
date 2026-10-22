# REFUSE (as built)

As built on `main` by the REFUSE change (branch `carve/refuse`, on `carve/assert-raises-outcome`).
Source spec: none on `main`.
The design is `specs/todo/IMPLICIT-PROPS-DESIGN.md` §11.9 and `specs/todo/PROPS-REDTEAM-2026-09-03.md` §2.8 and §6, which are on `unstable` only.
The code comes from `unstable`: `75e08b55e` (2026-09-04), with `2cb313e51` (`success` is null) and `288d9bb97` (the DOT render) folded in, and two other carried pieces named under "What is not the same as unstable".
Line numbers are in this branch's tree at the commit before the one that added this page (the head of `carve/refuse` without it).
Measurements are dated 2026-10-14.
The ones that start a service, the WASM backend or a test suite ran on Linux (x86_64, GHC 9.10.3); the `l4` command-line ones ran on a second machine.

Scope: the expression `REFUSE "message"` and the outcomes every surface now distinguishes.
The directive that asserts a refusal, `#ASSERT REFUSED`, is not here.
`doc/reference/control-flow/REFUSE.md` tells users what it does.

## What it does

`REFUSE "message"` is an expression at any type that stops evaluation with the author's reason.
It is a determinate outcome of its own kind: not a value, not an evaluation error, and not a fact the caller could supply.

- `REFUSE` is a keyword and `Refuse Anno (Expr n)` an `Expr`; the word is now reserved (`Lexer.hs:175`, `:260`; `Syntax.hs:280`).
  A parse error at an expression position now lists `REFUSE` among the tokens it expected (the `l4 run` output of `jl4/experiments/jerseyCharities2-annual-returns.l4` differs in that list and nowhere in its first 30 lines, and that of `jl4/ok/inert/simple.l4` in that list and nowhere else); no existing golden changed.
  The message is a string literal: `REFUSE 42` is a type error and `REFUSE (1 PLUS 1)` does not parse (`Parser.hs:2438`, `TypeCheck.hs:2692`).
  A literal keeps the reason readable without running the program and keeps the payload out of the machine's frame stack.
- It is at any type, because `checkExpr` falls through to infer-then-expect and the fresh inference variable `Refuse` returns unifies with whatever the context expects (`TypeCheck.hs:2692-2704`).
  A 0-ary definition without `GIVEN a IS A TYPE` is monomorphic and takes the first type it is used at.
- Nothing in the language catches it.
  `tryEval` is the only `try` over an `EvalException`, it sits at the directive boundary, and `withEvalClauses` rethrows (`Machine.hs:277-289`, the comment above `refuseWith`).
  That is an invariant: anything that adds a second `try` breaks it.
- A refusal is `RefusalException Refusal`, a third top-level arm of `EvalException` (`Exceptions.hs:29`, `:45`).
  It is not another `UserEvalException`: a new constructor there would compile unchanged everywhere and render every refusal as an error, under the "please report this as a bug" banner.
- `EvalDirectiveValue` is `Assertion AssertionOutcome` (`Holds | Fails | Refused | Errored`) and `Reduction ReductionOutcome` (`Reduced | ReducedRefused | ReducedErrored`) (`EvaluateLazy.hs:228`, `:243`).
  That is what makes `-Werror` name every surface that must decide whether a refusal is an answer or a defect.
  `nfDirective` is the only place that builds them (`EvaluateLazy.hs:142`).
- Lazy `AND` and `OR` stay left to right: `FALSE AND <refusing>` answers FALSE and `<refusing> AND FALSE` refuses.
  `#ASSERT NOT e` where `e` refuses is refused in both polarities, because `NOT` forces its operand.

What each surface does with a refusal:

| surface                          | a refusal is                                                                                                                                                                                                         | where                                              |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| `l4 run` text                    | `The model refuses to answer:` and the reason, or `assertion refused:` and the same for an `#ASSERT`; exit code 0                                                                                                    | `EvaluateLazy.hs:258-272`, `Run.hs:92`             |
| `l4 run --json`                  | `#EVAL`: `"kind": "refused"` and `"reason"`. `#ASSERT`: `"kind": "assertion"`, `"value": null`, reason under `"refused"` and not `"error"`                                                                           | `Run.hs:146`, `:155`                               |
| editor diagnostics               | Warning severity (`L4.Diagnostic.evalResultToDiagnostic` gives a refused `#ASSERT` a Warning and a refused `#EVAL` Information; nothing on `main` calls it)                                                          | `Rules.hs:779`, `Diagnostic.hs:127`                |
| Inspector, `l4/getDirectiveInfo` | `success` absent and `structuredValue` absent                                                                                                                                                                        | `Inspector.hs:152`, `:160`, `:293`                 |
| browser API, `L4.API`            | `success: null`                                                                                                                                                                                                      | `API.hs:318`, `:562`                               |
| decision service                 | `EvaluatorRefused`, wire tag `EvaluatorRefused`, HTTP 422 with the bare reason as `contents`; the text `The model refuses to answer:` and the reason is the batch `@error` and the MCP tool result (`isError: true`) | `Backend/Api.hs:253`, `:267`, `Backend/Jl4.hs:714` |
| trace                            | `↯ refused: <reason>`, in the text trace and in the DOT node label                                                                                                                                                   | `Trace.hs:299`, `GraphViz2.hs:539`                 |
| REPL, ladder `evalApp`           | `Refused: <reason>`; an error response carrying the reason                                                                                                                                                           | `jl4-repl/app/Main.hs`, `LSP/L4/Actions.hs`        |
| query plan                       | `"determined": null`, no question asked, and the reasons evaluation gives under `"refusal"`; a refusal the plan reads is never in `stillNeeded` or `asks`; one it cannot read is a 400                               | `Refusal.hs`, `BooleanDecisionQuery.hs`            |

An error keeps exit code 1 in `l4 run` (`Run.hs:92`).

Backends that exist on `main` and cannot carry a refusal:

- The WASM backend marks the function unsupported (`Lower.hs:1932`), which routes the request to the evaluator, and the evaluator raises the refusal.
  A helper's flag is lifted to every export that calls it (`recordCallEdge` `Lower.hs:276`, `propagateDiagnostics` `Lower.hs:521`, applied at `Lower.hs:499`).
- The document export prints a refusal as prose in a clause and bails out of formula mode, so it is not read as a quantity (`Export/Document.hs:1164`, `:1278`).
- Both ladder drawings draw it as a labelled leaf and do not treat a terminal as structure (`Viz/Ladder.hs:345`, `LSP/L4/Viz/Ladder.hs:377`).
- The desugarer and `setInertContext` descend into the message without turning it into an `Inert` node, so `TRUE AND REFUSE "x"` stays legal (`Desugar.hs:78`, `TypeCheck.hs:4244`).

## What is not the same as unstable

- `#ASSERT REFUSED [BECAUSE "…"]`, `TKRefused`, `AssertKind` and `FailsBecause` are not here.
  `nfDirective` takes the same `Bool` as before, and `AssertionOutcome` has four constructors where unstable's has five.
- Not carried because `main` has no such module: the Catala, DMN, docassemble, OpenFisca and relational lowerings, `l4 catala`, and the ledger specs that unstable updated.
- `l4 batch` gives a refusing row `"status": "refused"`, `"result": {"refused": {"reason": …}}` and the reason in `diagnostics`, and carries on with the next row; the command still exits 0.
  An erroring row is `"status": "error"` and stops the batch unless `--continue-on-error` is given.
  Unstable gives a refusing row the same status and diagnostics.
- The service's batch endpoint returns a refused case with `@error` (`The model refuses to answer: …`) and counts it in `casesIgnored`.
  Unstable returns `@refused` instead.
- A refusal is raised by `raiseException`, whose `unwindThunk` (`Machine.hs:261`, in the change under this one) is the blackhole part of unstable's `unwindFrame` and nothing else of it.
- The propagation of unsupported flags through the call graph is the first half of unstable's `410a1743f`.
  Its other half gives each lambda-lifted helper its own WASM symbol and refines the overload-collision check; `main` has neither.
- `doc/test-docs.sh` matches `assertion refused:` as unstable's `5ee1b7ef4` does, without its mention of `#ASSERT REFUSED`.
- The corpus fixtures are unstable's `4fad67ed2`, re-blessed on `main`, with each `#ASSERT REFUSED` rewritten as an `#EVAL` or a plain `#ASSERT`.
  One golden differs from unstable's text: the parse error of `not-ok/tc/refuse-computed-message.l4` reports its range as `11:28-11:28`, where unstable's says `11:28-11:29`.

## The query plan

The query plan carries unstable's change in legalese/l4-ide#693, ported by function (the files it touches differ heavily), in four parts.
`L4.Refusal.alwaysRefusing` finds the definitions of the module whose evaluation can only refuse: a body that is a `REFUSE`, or names such a definition with no arguments, under a `WHERE` or a `LET`, as the least fixed point.
Both ladders record, by leaf id with its reason, a `REFUSE` written as an operand and a bare reference to such a definition (`getRefusingAtoms`).
The service and the editor compile those leaves as `BRefuse` nodes, which are not variables of the diagram, and read an expression that holds one as evaluation does, left to right (`compileLazy`).
Both ladders also record each leaf that holds a refusal without being one: a `CONSIDER` arm, a comparison operand, a call (`getUnreadableRefusals`, from `Refusal.refusalWithin`).
The service and the browser's plan builder draw a rule that has either kind of leaf as written and not simplified, because simplifying distributes `OR` over `AND` and can change which refusal evaluation reaches first.
They spell out each `IMPLIES` and each Boolean `IF` in connective position as the `AND`, `OR` and `NOT` it stands for (`Transform.spellOutConnectives`), because drawn as written each is one leaf that names only the inputs directly under it, and the plan answers that leaf from the input it names.
`a IMPLIES b` and `NOT a OR b` evaluate alike, a refusal included (`Machine.hs:414` and `:416`): `a` first, and `b` only where `a` is `TRUE`.
`IF c THEN t ELSE e` and `(c AND t) OR (NOT c AND e)` evaluate alike for the same reason (`Machine.hs:480`): `c` first, `t` only where `c` is `TRUE`, `e` only where it is `FALSE`.
The condition is read twice, so one that is a call to a rule with inputs becomes two leaves and `stillNeeded` lists it twice; a condition made of names shares its variables.
That can only make the plan over-ask.
Both ladders do it in `translateDecide`, straight after `carameliseExpr`, because a call to the `IMPLIES` function is an `Implies` node only after `carameliseExpr`; it is a switch on the configuration (`spellingOut`, and `visualizeByNameSpelledOut` for `jl4-wasm`) that is off for every other caller.
After the redraw, a rule that holds a leaf of the second kind is not planned: the service answers 400 with `{"error": …}` and `jl4-wasm` returns the same sentence in its error object (`Refusal.unreadableRefusalError`).
The sentence names the first such part and its reason, and is cut at 100 characters.
A reference by name to a rule that refuses on only some paths, and a call with inputs to one, are not leaves of the second kind: they stay questions.

What differs from unstable, because `main` lacks what unstable's version stands on:

- The plan has no `verdict`, so a refusal is `"determined": null` with `"refusal"` set; unstable adds `"verdict": "Refused"`.
  The `refusal` object has the same two keys, `reasons` and `atoms`.
  Measured 2026-10-22 against a build of unstable after #693, the same requests give the same `determined`, the same labels in `stillNeeded` and `asks`, and the same `refusal.reasons` for each set of answers.
  The atom ids differ between the two builds for every atom, `adult` included, so they are not compared.
- `main`'s ladder has no `IMPLIES` seam, so `compileLazy` has no seam case.
  Where unstable plans an `IMPLIES` through its seam, the service and the browser spell the `IMPLIES` out and plan that.
  The editor's ladder is not redrawn, and the REPL's is the simplified one.
- `main` draws an `IF` or a `CONSIDER` as one leaf.
  Unstable reaches a refusal on an arm of either; here the service spells out a Boolean `IF` in connective position and reaches it, and answers 400 for a refusal in a `CONSIDER` arm.
- The plan's `note` carries the sentence about `refusal` only for a rule that has a refusing leaf; any other plan carries the note without that sentence.
  `jl4-repl`'s `:queryplan` prints `determined: Refused` and a `refusal:` line for each reason.
- `main` ranks by the number of answers that settle the plan, not by information gain.
  An answer that leads to a refusal counts as settling it, in `ranked` and in the scores of `inputs` and `asks`.
- The unit guard that no boolean decision of `regcf-denovo.l4` has a refusing leaf is not carried: the file is not on `main`.

## Two defects on `main` that this change depends on fixing

Measured on `main`'s `l4` plus this branch's tests.

- **A thunk that raised cannot be used twice.**
  `raiseException` pops the stack and drops each `UpdateThunk` frame, which leaves the thunk's blackhole mark behind.
  `` `one over zero` MEANS 1 DIVIDED BY 0 `` with `#EVAL` on it twice prints `Division by zero` and then `Infinite loop detected while trying to evaluate`.
  For a refusal that is the house style (one named definition reached from many arms), so the second arm to reach it would have read as a defect.
  This is fixed in the change under this one (`unwindThunk`, `Machine.hs:261`), which also has the control: a genuine loop is still reported as a loop at every use.
- **A helper's unsupported flag never reached its export.**
  With `` `not modelled` MEANS REFUSE "not modelled" `` and an export that reaches it only through that name, the REFUSE arm flagged `not modelled`, and the export was still `"supported": true`, so the request would have run in a WASM module that cannot evaluate the refusal (only the flags were checked, not what that module answers).
  `propagateDiagnostics` lifts every diagnostic to all transitive callers, so the same is now true for an `EVENT`, a `FETCH`, a `POST`, an `ENV` or a lambda in a helper: the export is unsupported, where before it was flagged supported over an unsupported helper.
  That reaches the prelude: a review's differential found that prelude functions built on a lambda, such as `sort` and `nub`, make an export that calls them unsupported.
  A function with two refusals gives the reason once (`markUnsupported`).

## Measured

On this branch, with the service started on a one-file deployment: `fee y` refuses below 2000 through a named definition; `eligible adult` is `adult AND` a named definition that refuses; `direct adult` is `adult AND REFUSE "…"`:

| request                                                       | result                                                                                                         |
| ------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `/evaluation` of a rule that refuses, twice                   | 422, `EvaluatorRefused`, the same both times                                                                   |
| `/evaluation` of the same rule for an input it answers        | 200, `100`                                                                                                     |
| `/evaluation/batch` with one refusing and one answering case  | 200; `@error` on the first, `value: 100` on the second; `casesIgnored: 1`                                      |
| `GET …/functions/eligible` and `…/direct`                     | `parameters` lists `adult` only: the refusal is not a parameter, written in the body or reached through a name |
| MCP `tools/call` of the refusing rule                         | `isError: true`, text `The model refuses to answer: …`                                                         |
| `/query-plan` of a rule that reaches a refusal through a name | `adult` true: `determined: null`, no asks, the reason under `refusal`; the name is never an ask                |
| `/query-plan` of a rule with `REFUSE` in its body             | the same; with `adult` false, both give `determined: false`                                                    |
| `/query-plan` of `IF resident THEN TRUE ELSE` a refusal       | asks `resident`; `true` gives `determined: true`, `false` gives `determined: null` and the reason              |
| `/query-plan` of a rule with a refusal in a comparison        | 400, `{"error": …}` naming the part and the reason; no plan                                                    |

The `/query-plan` rows were measured on 2026-10-22, after the query plan change described above.

## Limits

- **The query plan reads a refusal only in a few places.**
  They are the whole rule, and an operand of `AND`, `OR`, `NOT` or `IMPLIES`, or a condition or arm of a Boolean `IF` in one of those places: a `REFUSE`, or a bare reference to a definition of no inputs that always refuses.
  A refusal in an arm of a `CONSIDER`, an operand of a comparison or of `EQUALS`, or a call to a definition that always refuses, is a 400.
  The `impact` of a branch that leads to a refusal shows `determined: null` and `support: []`, as a branch with nothing settled does; the plan's `refusal` for those answers is where it shows.
- **Some refusals are questions.**
  A definition of no inputs that refuses on only some paths, because whether it refuses can turn on what the plan does not see; a call with inputs to a definition that refuses on only some paths, where the plan binds the call from the value of the input it names (``adult AND `some paths` applicant`` with `applicant` `FALSE` is `determined: false` where `/evaluation` refuses); and a name from another file.
  The end-to-end tests pin the first two as controls (`jl4-service/test/IntegrationSpec.hs`).
- **The editor and the REPL spell out neither an `IF` nor an `IMPLIES`, and answer no 400.**
  Measured 2026-10-22 on `(IF b THEN c ELSE r1) AND a`, with `a` `FALSE`: both say `determined: false` where `/evaluation` refuses, with simplification on or off.
  On ``adult AND (`the fee` GREATER THAN 3)`` both list the comparison in `stillNeeded` as a question.
- **The refusal set `Ref(f)` is not computed.**
  A function does not carry the list of reasons it can refuse for, so nothing warns before it is run, and `l4 verify`, which `main` does not have either, could not treat a refusal specially.
- **The message is a literal.**
  Interpolated or computed reasons are not supported.
- **Order-dependence** under lazy `AND` and `OR`, as above.
- **Other exporters are not covered because `main` does not have them.**
  A later carry of a DMN, Catala, docassemble, OpenFisca or relational export has to decide what a refusal becomes there, and must not lower it as something a caller could supply.
- **Not run**: the browser's plan builder (`jl4-wasm`), which is type-checked with `ghc -fno-code` and not built or run; the ladder drawings in an editor (the `/query-plan` response for `direct` carries the ladder, and it contains the `REFUSE` leaf and its message), and the Inspector's conversions (`jl4-lsp` has no test suite on `main`; `L4.API`'s `l4EvalDirective` has the same shape and is tested).

## Where it lives

- `jl4-core/src/L4/Syntax.hs`, `Lexer.hs`, `Parser.hs`, `TypeCheck.hs`, `TypeCheck/Types.hs`, `TypeCheck/Annotation.hs`, `Desugar.hs`, `Print.hs`, `Nlg.hs`, `Parser/ResolveAnnotation.hs`, `StateGraph.hs`, `Lint/AndOrDepth.hs`, `DirectiveFilter.hs`: the expression, from the lexer to the printers.
- `jl4-core/src/L4/EvaluateLazy/Exceptions.hs`, `Machine.hs`, `Trace.hs`, `GraphViz2.hs`, and `jl4-core/src/L4/EvaluateLazy.hs`: the exception, the outcomes, the renderings.
- `jl4-core/src/L4/API.hs`, `Diagnostic.hs`, `Export/Document.hs`, `Viz/Ladder.hs`; `jl4-lsp/src/LSP/L4/Rules.hs`, `Inspector.hs`, `Actions.hs`, `Viz/Ladder.hs`; `jl4-repl/app/Main.hs`; `jl4-service/src/Backend/Api.hs`, `Jl4.hs`; `jl4/app/L4/Cli/Run.hs`, `Common.hs`; `jl4-mlir/src/L4/MLIR/Lower.hs`, `Schema.hs`: the surfaces and backends.
- `jl4-core/src/L4/Refusal.hs`; `jl4-lsp/src/LSP/L4/Viz/QueryPlan.hs`; `jl4-query-plan/src/L4/Decision/BooleanDecisionQuery.hs`, `QueryPlan.hs`; `jl4-service/src/Backend/DecisionQueryPlan.hs`, `Schema.hs`; `jl4-wasm/app/QueryPlanWasm.hs`; `ts-shared/jl4-client-rpc/custom-protocol.ts`: the query plan.
- Tests: `jl4/examples/ok/refuse*.l4` and `jl4/examples/not-ok/tc/refuse-*.l4` with their goldens; `jl4/tests-cli/Main.hs` ("l4 run on REFUSE", "l4 run on a definition whose evaluation raised"); `jl4-service/test/IntegrationSpec.hs` ("query-plan and evaluation agree on refusals"), `SanitizationSpec.hs`, `BooleanDecisionQuerySpec.hs` and `QueryPlanSpec.hs`; `jl4-mlir/test/Main.hs`.
- Docs: `doc/reference/control-flow/REFUSE.md` and `refuse-example.l4`.
