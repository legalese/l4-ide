# Specification: Evaluating with unknowns — connectives as an algebra, not as `IF`

**Status:** proposed, not built (2026-10-01).
Nothing in this document is in the tree.
§4, which defines the evaluation once, was added on 2026-10-01 after the rulings of §9 were made; §5 to §8 were restated against it the same day.
Every statement about today's behaviour is a probe result or a `file:line` read on `unstable` at `f9a504b77`, and says which.
Probes for §2 ran on the installed `l4` (`~/.cabal/bin/l4`, a store build linked 2026-09-30; the only evaluator-path commit after 2026-09-26 is `8848df744`, `WHOSE`, which touches none of the code cited here); probes for §4.11 ran on a snapshot of the `unstable` binary built from `f9a504b77`.
Probe files are in the session scratchpad, not in the tree.

**Trigger:** SCHRODINGER, widened by Meng on 2026-10-01: _"continue your investigation of the evaluator lift with kand. It sounds like we'll need to redo the rewriting-to-IF in favour of something more algebraically principled."_
§4 was added under REVERSEGEAR, fired by Meng the same day on the observation _"We seem to be backing our way into symbolic evaluation by fits and starts."_

**Related:** `specs/done/NEGATION-AS-FAILURE-SPEC.md` (`DefBool`, `kand`/`kor`/`knot`), `specs/done/BOOLEAN-MINIMIZATION-SPEC.md` (whose Phase 1 proposed this and was never built, §3.2), `specs/todo/RUNTIME-INPUT-STATE-SPEC.md` (the four-cell input model), `specs/todo/ladder-diagrams-2026/DESIGN.md` §22, §23, §25f, `specs/todo/IMPLICIT-PROPS-DESIGN.md` §11.5 (R8, `TYPICALLY` at the root), `specs/todo/TYPICALLY-DEFAULTS-SPEC.md`.

---

## 1. The problem in one paragraph

An investigator, a caseworker or a wizard holds a case with most facts not yet established.
For them "not yet known" is a third answer, and a rule that reaches it should say _undetermined_, naming what it is waiting for, and never _no_.
L4 has that third answer in four places that do not share an implementation: a user-level library pattern, a TypeScript evaluator inside the ladder visualizer, a decision-diagram planner over the ladder's static expression tree, and a lifecycle algebra for regulative `RAND`/`ROR`.
The one place it does not have it is the evaluator that `l4 run`, `#EVAL`, `l4 batch` and the service all share.
There, an unknown fact is an exception that aborts the directive, and whether you reach it depends on which side of an `AND` the fact was written on.

---

## 2. What the tree does today

### 2.1 The connectives are not in the evaluator; `IF` is

The type checker turns every Boolean connective into a call to a built-in function (`desugarBinOpToFunction`, `jl4-core/src/L4/TypeCheck.hs:3743-3762`, read), and each built-in is a closure whose body is an `IfThenElse` (`boolBinOpClosure`, `andValClosure` and siblings, `jl4-core/src/L4/EvaluateLazy/Machine.hs:6636-6715`, allocated at `:5929-5932`, read):

| source        | evaluated as                |
| ------------- | --------------------------- |
| `a AND b`     | `IF a THEN b ELSE FALSE`    |
| `a OR b`      | `IF a THEN TRUE ELSE b`     |
| `a IMPLIES b` | `IF a THEN b ELSE TRUE`     |
| `NOT a`       | `IF a THEN FALSE ELSE TRUE` |

`forwardExpr` also has a direct rewrite of the surface connectives into `IfThenElse` (`Machine.hs:1198-1205`), but type-checked code never reaches it: the surface `And` "does not survive type checking" (`Machine.hs:2990-2995`).
`UNLESS` never reaches the evaluator as itself: the parser turns `l UNLESS r` into `l AND (NOT r)` (`Parser.hs:1885-1889`, read).
`BRANCH` becomes a chain of `IfThenElse` too (`desugarMultiWayIf`, `Machine.hs:1323-1327`, read).
The regulative `RAND` and `ROR` are the exception: they are their own value, `ValROp`, with their own frames (`Machine.hs:1196-1197`, `:2622-2753`, read), see §3.5.

### 2.2 An unknown is an exception, raised wherever it is first inspected

An input nobody supplied is the value `ValAssumed name` (`jl4-core/src/L4/Evaluate/ValueLazy.hs:98`).
Every site that inspects one raises `Stuck name` (`stuckOnAssumed`, `Machine.hs:835-836`):
`IF` (`:1634`), application of an assumed function (`:1593-1594`, carrying `-- TODO: we can do better here`), `expectNumber` / `expectString` / `expectDateValue` (`:4120`, `:4126`, `:4133`), every binary operator (`runBinOp`, `:5018-5019`), and equality (`runBinOpEquals`, `:5046`), for its left operand only.
An unknown on the right of `EQUALS` is misdiagnosed: `3 EQUALS n` reports "Trying to check equality on types that do not support it", while `n EQUALS 3` names `n` (probe, `f9a504b77`).

**No L4 construct can catch it.**
`raiseException` unwinds every frame and rethrows to the host (`Machine.hs:699-704`), and the comment at `:724-728` states the invariant in terms: _"Today every `EvalException` aborts its whole directive."_
This is the fact the conservativity argument of §4.3 rests on.

`l4 run` exits 1 when any directive ends in `Stuck` (`jl4/app/L4/Cli/Run.hs:88-94`, read), deliberately.

### 2.3 Probes: the answer depends on the side of the operator

Section `GIVEN x IS A BOOLEAN` and `n IS A NUMBER`, both unsupplied (probe `q1-section.l4`); the same result for an `ASSUME x` (probe `q2-assume.l4`).

| expression                   | today            | strong Kleene says            |
| ---------------------------- | ---------------- | ----------------------------- |
| `FALSE AND x`                | `FALSE`          | `FALSE`                       |
| `x AND FALSE`                | **stuck** on `x` | `FALSE`                       |
| `TRUE OR x`                  | `TRUE`           | `TRUE`                        |
| `x OR TRUE`                  | **stuck**        | `TRUE`                        |
| `NOT x`                      | stuck            | unknown                       |
| `x OR NOT x`                 | stuck            | unknown (classically `TRUE`)  |
| `IF x THEN 1 ELSE 1`         | stuck            | unknown (the arms agree: `1`) |
| `n GREATER THAN 3`           | stuck            | unknown                       |
| `FALSE AND n GREATER THAN 3` | `FALSE`          | `FALSE`                       |
| `FALSE UNLESS x`             | `FALSE`          | `FALSE`                       |
| `x UNLESS TRUE`              | **stuck**        | `FALSE`                       |
| `FALSE IMPLIES x`            | `TRUE`           | `TRUE`                        |
| `x IMPLIES TRUE`             | **stuck**        | `TRUE`                        |
| `x EQUALS x`                 | stuck            | unknown                       |
| `and (LIST TRUE, x, FALSE)`  | **stuck**        | `FALSE`                       |
| `and (LIST FALSE, x, TRUE)`  | `FALSE`          | `FALSE`                       |

The five bold rows are the asymmetry.
Each is a rule whose answer is fixed by what is known, and today's evaluator reports it as unanswerable because the unknown fact happens to be written first.
For an encoder this is a hazard that no reading of the source reveals: reordering the conjuncts of an `AND` is an edit nobody expects to change what the rule can answer.

### 2.4 Defects the probes found on the way

**`CONSIDER` on an unknown misreports it as a missing branch.**
`CONSIDER m WHEN NOTHING THEN 1, WHEN JUST y THEN 2`, with `m IS A MAYBE NUMBER` an unsupplied section `GIVEN` (probe `q4.l4`), returns:

```
The value
  m
reached a CONSIDER that has no branch for it.
Add a WHEN branch for this case, or a catch-all OTHERWISE branch.
```

The `CONSIDER` is exhaustive.
The value is unknown, and the message sends the reader to fix code that is not broken.
It fails loudly, so it does not return a wrong answer, but it misdirects.
It is a defect in two-valued mode, independent of everything below: the pattern matcher (`matchPattern`, `Machine.hs:4054` onwards) has no `ValAssumed` arm, so the value falls through to `patternMatchFailure`.

**The `IF` rewrite leaks into user-visible traces.**
`jl4/examples/ok/tests/lazytrace-exception.golden:15-16` shows the trace of `FALSE OR TRUE` as `IF a THEN TRUE ELSE b`, and `:56`, `:60`, `:65` and `:70` show `x AND (and OF xs)` as `IF a THEN b ELSE FALSE`.
`a` and `b` are the built-ins' own parameter names.
That is the only committed golden that carries one of the four shapes (`grep -rlF` over every `*.golden`), on about twenty lines once each `IF`'s child lines are counted.
The service's reasoning tree (`traceToReasoning`, `jl4-service/src/Backend/Jl4.hs`) carries the same sub-tree, and jl4-mlir reproduces it on purpose for trace parity with the service (`jl4-mlir/runtime/jl4-runtime.mjs:3512-3521`, `:3718-3745`; parity harness `jl4-mlir/test/Main.hs:476-500`).
A reader of that trace sees a conditional they never wrote, with variable names that are not theirs.

**A field read on an unknown record misreports the same way.**
`d's age`, with `d IS A Person` an unsupplied section `GIVEN`, returns the same no-branch message (probe `p05-record.l4`, on the `f9a504b77` snapshot), because the generated selector is a closure whose body is a one-branch `CONSIDER` on its argument (`Machine.hs:5727-5743`).
So every field path on an unknown record is misdiagnosed, not only a `CONSIDER` the author wrote, and `d's age AT LEAST 18` never reaches the comparison.

**A bare unknown as the result of an `#EVAL` is reported as a value.**
`#EVAL TRUE AND x`, `#EVAL TRUE IMPLIES x` and `#EVAL x` each print `x` as if it were a value, with JSON `"kind":"value"`, `"ok":true` and exit 0 (probes `p11-implies.l4`, `p17-bare.l4`).
`#ASSERT` on the same expression is reported as `Stuck`, because only the assertion arm handles a `ValAssumed` result (`EvaluateLazy.hs:306`).
This is the one path in two-valued mode where an unknown is silent, and it is the shape §2.5 finds again on the service.

### 2.5 The service: one silent path, and it is the investigator's

The direct path refuses a missing or `null` value for a non-`MAYBE` parameter (`jl4-service/src/Backend/Jl4.hs:447-450`, read).
`{}`, which the wire calls `FnUncertain` (`Backend/Api.hs:74`), cannot be expressed on that path, so it is sent to the generated-wrapper path (`Jl4.hs:527-535`).
There every boolean parameter is passed as `fromMaybe FALSE (args's x)` (`Backend/CodeGen.hs:239`, `:335`, `:603`).

Measured by the coordinating session on 2026-10-01 against a local `jl4-service` built from `f9a504b77`, with the rule `GIVEN has capacity IS A BOOLEAN TYPICALLY TRUE, is adult IS A BOOLEAN`:

- absent, or `null`: refused, "missing required parameter". Loud.
- `{}` on either input: `{"result":{"value":false}}`, a plain response with no diagnostic, the `TYPICALLY TRUE` ignored.
- `{}` on a section `GIVEN` boolean: fails loudly, the generated wrapper calls `fromMaybe` without importing the prelude ("could not find a definition for fromMaybe").
  The cause is **not established**: the coordinator inferred that `hasBooleans` counts only rule `GIVEN`s, but `CodeGen.hs:131-133` counts both kinds; there are three generators (`:132`, `:559`, `:603`) and the one this request reached was not traced.

So the wire's own word for "the user is not sure" becomes "no", silently.
That is the failure §1 describes, at the boundary most likely to meet a real case.

### 2.6 How much of the corpus gets stuck today

Measured 2026-10-01 with a snapshot copy of the installed binary, `JL4_LIBRARY_PATH` unset (embedded prelude), `--fixed-now 2026-10-01T00:00:00Z`, `l4 run --json` over every `.l4` under `jl4/examples/{ok,legal,canon}` and `doc/`:

| measure                                        | count |
| ---------------------------------------------- | ----- |
| files run (none failed to produce JSON)        | 514   |
| directive results                              | 7,211 |
| results that are a `Stuck` ("an assumed term") | 9     |
| files with at least one                        | 4     |

The four are `ok/assumes.l4` (3), `ok/assert-raises.l4` (4), `ok/section-given-discharge.l4` (1) and `ok/lazytrace-exception.l4` (1), each a file that exists to show the stuck behaviour; that they were found is the census's positive control.

**What this means.** The corpus's own directives almost always supply every input, because they are tests.
So the lift would move almost nothing in the corpus, which is good news for §6 and bad news for §7: the corpus cannot be where its cost is measured.
The unknowns this spec is about arrive at the boundary — the service, `l4 batch` rows, the wizard — and §7 measures there.

---

## 3. Prior art already in the tree

### 3.1 `DefBool`: truth-functional strong Kleene, user-level (`NEGATION-AS-FAILURE-SPEC.md`)

`DefBool` is `MAYBE BOOLEAN`, and `kand`, `kor`, `knot` are truth-functional strong Kleene over it, reading (a) of §4.1, written in L4 (`jl4/experiments/negation-as-failure-examples.l4:89-124`); U12b asks that it be labelled so wherever the word "lift" referred to it.
All 15 `#ASSERT`s in that file pass (probe on the installed binary, 15 of 15 `assertion satisfied`, each printed once as a message and once as a diagnostic).
The shipped library carries only the three eliminators `holds`, `naf`, `presumed` (`jl4-core/libraries/negation-as-failure.l4`), each of which collapses `NOTHING` to a constant.
The spec's open question 2, whether the lift ships, was never ruled.

**Why this is not the answer for canon.**
A rewrite of `BOOLEAN` to `DefBool` and `AND` to `kand` would turn every connective into an ordinary function call, and every consumer that recognises connectives would lose them: the ladder renders `kand` as an opaque box, and the planner's translation makes any function call one atom (`jl4-lsp/src/LSP/L4/Viz/QueryPlan.hs:164-166`, read).
It is also a second copy of every encoding, which drifts.
The pattern is the right _semantics_ in the wrong _layer_.

### 3.2 Three-valued evaluation was proposed in January and never built (`BOOLEAN-MINIMIZATION-SPEC.md`)

That spec's "Approach 1" is `TriBool` evaluation inside the evaluator, and its recommended "Hybrid" made it Phase 1 (`specs/done/BOOLEAN-MINIMIZATION-SPEC.md`, §"Implementation Approaches" and §"Implementation Plan").
Phases 2 and 3, the decision diagram and impact analysis, were built, as `jl4-query-plan`, over the ladder's static tree rather than over evaluation.
Phase 1 was not: no `.hs` file in the tree mentions `TriBool` or a partial-evaluation endpoint (`grep -rn "TriBool\|partial-evaluation\|partialEval" --include=*.hs`, zero hits outside `dist-newstyle`).
The spec sits under `specs/done/` with the status header "📋 Draft", so neither location nor header says this.

### 3.3 The planner (`jl4-query-plan`)

`BoolExpr` (`BooleanDecisionQuery.hs:27-45`) is `BTrue | BFalse | BVar | BNot | BAnd | BOr | BImplies`, compiled to a hash-consed decision diagram.
`QueryOutcome.determined :: Maybe Bool` and `Verdict = Undetermined | Holds | Fails | Complies | InBreach | NotApplicable` (`QueryPlan.hs:127-133`, `BooleanDecisionQuery.hs:210-224`).
Its input is the ladder's static tree, so it decides `x OR NOT x` correctly, which no truth-table semantics can, but it sees only what the ladder drew: a call such as `age >= 18`, or a call to a sub-rule, is one opaque atom keyed by `nm.unique` (`QueryPlan.hs:164-166`).
**Package direction:** `jl4-query-plan` depends on `jl4-core` (its `.cabal` `build-depends`), so the evaluator cannot use the diagram without moving it (ruling U3).

### 3.4 The ladder's own evaluator, in TypeScript

`ts-shared/l4-ladder-visualizer/src/lib/eval/eval.ts` is a second three-valued evaluator over the ladder tree.
`AND`/`OR` evaluate every child (`Promise.all`, `:165-167`, `:190-192`) and then apply strong Kleene (`evalAndChain` / `evalOrChain`, `:301-339`).
`NOT` keeps unknown unknown (`:292-297`).
A call with any unknown argument is unknown, with a console message saying that is a shortcut (`:220-224`).
So the ladder already has reading (a) of §4.1, implemented a second time, in another language, over a different tree; it evaluates every child before it consults the table, so it is not reading (b).

### 3.5 The regulative algebra is the precedent

`RAND` and `ROR` are not rewritten.
They are a value, `ValROp env op left right` (`ValueLazy.hs:75`), evaluated by frames `RBinOp1` / `RBinOp2` (`Machine.hs:2622-2753`) over the lifecycle values fulfilled, breached and pending:
`ROR` short-circuits on a fulfilled left operand (`:2622-2633`); both breached is breached, with the blame anchored by time (`:2650-2700`); both fulfilled is fulfilled; and when neither table row applies, the frame returns **the operator applied to the two evaluated operands** — `ValROp env op (Right rval1) (Right val)` (`:2749-2753`).

That last arm is residualisation.
The regulative side has had, since it was written, the design this spec proposes for the Boolean side: connectives as first-class frames over a lattice of outcomes, with an undecided result returned as a formula over the parts that are still pending.
The proposal is to give constitutive `AND`/`OR`/`NOT`/`IMPLIES` the same structure the regulative ones already have.

### 3.6 The four-cell input model (`RUNTIME-INPUT-STATE-SPEC.md`)

`WithDefault a = Either (Maybe a) (Maybe a)`: `Left Nothing` not asked and no default; `Left (Just v)` not asked, `TYPICALLY v`; `Right Nothing` asked, "I don't know"; `Right (Just v)` asked and answered (`RUNTIME-INPUT-STATE-SPEC.md:62-72`).
Its status header still reads "BLOCKED (December 2025) — depends on TYPICALLY"; `TYPICALLY` has since landed for section `GIVEN`s, so the header is stale.
The ladder adopted the model as a provenance axis (DESIGN §22) and keeps `Left` as its own map, `ViewSpec.defaults`, beneath `valuation`, with `respectDefaults` to withdraw presumptions (`ts-shared/ladder-core/src/types.ts:248-277`).

### 3.7 The ladder's seam constrains the algebra (DESIGN §25f)

§25f found that the classical short-circuit is valid for computing a truth _value_ but not a _verdict_: with the requirement met and the scope unknown, `NOT scope OR requirement` is `TRUE`, and a planner that stops there cannot tell "you comply" from "the rule never reached you".
The fix kept `IMPLIES` intact as `BImplies` with both sides as roots.
**Consequence here:** whatever the evaluator returns for an undecided `IMPLIES` must keep the scope and the requirement as separate parts.
Rewriting `IMPLIES` to `IF a THEN b ELSE TRUE`, as `Machine.hs:1203` does today, is a flattening of exactly the kind §25f had to undo in the planner.

---

## 4. Symbolic evaluation, defined once

This section is the definition the rulings of §9 were converging on, clause by clause.
It was written on 2026-10-01, after those rulings, and replaces the design section as it stood that morning.
Where this section and a ruling's own words pull apart, §4.12 lists it with the evidence and does not resolve it.
Nothing in it is built.

### 4.1 Three readings of an unknown, and the one chosen

Three readings have names here because the corpus, the rulings and the prior art each use one of them.

**(a) Truth-functional strong Kleene.**
A third Boolean value with the K3 tables, `U ∧ F = F`, `U ∧ T = U`, `U ∨ T = T`, `¬U = U`, applied after both operands are evaluated.
This is what `kand`, `kor` and `knot` compute over `DefBool` (§3.1), what the ladder visualizer's `evalAndChain` computes over its children (`eval.ts:301-339`), and what `BOOLEAN-MINIMIZATION-SPEC.md`'s `evalTriBool` was (§4.10).
It forgets which unknowns the answer depends on, so it cannot decide `x OR NOT x`, and it says nothing about an operand that errors.

**(b) Left-sequential evaluation.**
Evaluate the left operand first.
If it decides the connective (`FALSE` for `AND`, `TRUE` for `OR`, `FALSE` for `IMPLIES`), stop, as today.
If it is known and does not decide, the answer is the right operand, as today.
Only if it is unknown is the right operand evaluated and the K3 table applied.
This is McCarthy's sequential reading of the connectives; Plotkin's parallel-or, which would make `⊥ ∨ T = T`, is not proposed.

**(c) Residuals.**
An undecided result is not a bare `U` but the term it is waiting on: a formula over the atoms it depends on, with `IMPLIES` kept as its own node (§3.7).
(a) is the quotient of (c) that forgets the formula.

**Ruled (U1, U1b):** the evaluator uses (b)'s order and (c)'s values.
(a) remains the right description of the user-level library (U12b) and of what the K3 report prints (§4.7).

### 4.2 The term language

A value the evaluator cannot determine is a **term**.
A determined value is a weak-head normal form exactly as today; nothing below changes any determined value.

```
term  t ::= ?i                 an unsupplied input i, with its declared type (U6b) and its provenance (§4.8)
          | t 's f             a field of an unknown record: the selector f applied to t
          | v                  a determined value
          | g (a1, …, an)      an assumed function g applied to arguments, each a value or a term
          | op (a1, …, an)     a built-in operation (arithmetic, string, date, list) with at least one term operand
          | c ? t1 : t2        a join: a conditional whose condition c is a Boolean term and whose arms were both evaluated
          | gave-up [c]        the evaluation under the pending condition c ran out of steps (§4.5)

Boolean term (a residual)
      b ::= TRUE | FALSE
          | ?i                 an input atom, i a BOOLEAN input
          | t1 cmp t2          a comparison atom, keyed by its evaluated term (§4.6)
          | g (a1, …, an)      a Boolean call to an assumed function, keyed the same way
          | fresh              an atom for an unknown that carries no key (§4.6)
          | NOT b | b AND b | b OR b | b IMPLIES b
          | c ? b1 : b2        a Boolean join, which is (c AND b1) OR (NOT c AND b2) once built
          | error [c] e        a guarded error leaf: the error e, raised only if the path condition c is TRUE (U11, U11b)
          | gave-up [c]        a guarded give-up leaf, carried like an error leaf (§4.5)
```

Three choices in that grammar carry the design.

**A defined function never appears in a term.**
A call to a function the module defines is unfolded as today, by binding its arguments and evaluating its body, so `older 18` with `older k MEANS age GREATER THAN k` leaves no trace of `older`: it becomes the atom `age GREATER THAN 18`.
Only built-in operations and assumed functions appear applied, because only those have no body to unfold.

**A field read on an unknown record is a term, not an error.**
`d's age` is desugared to the selector `age` applied to `d` (`Machine.hs:1236-1237`), and the selector is a closure whose body is a one-branch `CONSIDER` on its argument (`Machine.hs:5727-5743`).
Applied to an unknown `d` today, that `CONSIDER` falls through to the no-branch message of §2.4 (probe `p05-record.l4`).
Under this definition the selector applied to a term returns the term `d's age`, the input plus its field path, which the planner can ask for (U5b).

**`IMPLIES` is a node, never `NOT a OR b`.**
That is the ladder's finding at DESIGN §25f: a met requirement under an unknown scope is `TRUE` as a value and undetermined as a verdict, and only the unflattened node lets a consumer read both.
So `b1 IMPLIES b2` is built whenever `b1` is a term, even when `b2` is a literal; the simplifications that apply to `AND` and `OR` in §4.3 do not apply to it.

### 4.3 The evaluation rule, and why it is conservative

**The rule.**
At every site that today raises `Stuck` (§2.2), and in the four built-in connectives, when every operand the site needs is determined, evaluate exactly as today.
When an operand is a term, build the term node for that site instead of raising:

| site today (§2.2)                                                                           | with a term operand                                                                |
| ------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `AND`, `OR`, `IMPLIES`, `NOT` (`Machine.hs:6636-6715`)                                      | the connective table below                                                         |
| `IF` (`:1634`), `BRANCH` (`:1323-1327`)                                                     | a join, §4.5                                                                       |
| `CONSIDER` on a term scrutinee (`matchPattern`, `:4054`)                                    | a `fresh` unknown of the result type, naming the scrutinee (U4); never "no branch" |
| a selector applied to a term (`:5727-5743`)                                                 | the field-path term                                                                |
| an assumed function applied (`:1593-1594`)                                                  | the application term; an atom if its result type is `BOOLEAN`                      |
| `expectNumber`, `expectString`, `expectDateValue` (`:4120-4133`), `runBinOp` (`:5018-5019`) | the operation term; a comparison atom if the operation is a comparison, §4.6       |
| `runBinOpEquals` (`:5046`)                                                                  | the identity rule, then a comparison atom, §4.6                                    |
| a term as the result of a directive (`EvaluateLazy.hs:306`)                                 | the report, §4.7                                                                   |

The connective table, for `AND`; `OR` is dual, and `IMPLIES` and `NOT` build their node whenever the operand is a term:

| left     | right         | result                                                                 |
| -------- | ------------- | ---------------------------------------------------------------------- |
| `FALSE`  | not evaluated | `FALSE` (as today)                                                     |
| `TRUE`   | `r`           | `r` (as today)                                                         |
| term `p` | `FALSE`       | `FALSE`, unless `p` contains a guarded leaf: then `p AND FALSE` (U11b) |
| term `p` | `TRUE`        | `p`                                                                    |
| term `p` | term `q`      | `p AND q`                                                              |
| term `p` | error `e`     | `p AND error [p] e`: the error becomes a leaf guarded by `p` (U11)     |
| term `p` | ⊥             | the step counter, §4.5                                                 |

Nothing inside the evaluator decides a residual beyond these tables, the identity rule of §4.6 and the agreeing-arms rule of §4.5.
In particular no tautology is recognised mid-evaluation (U3): `IF (x OR NOT x) THEN 1 ELSE 2` builds the join `(x OR NOT x) ? 1 : 2`.

**Every evaluation is lifted (U7b).**
There is no evaluation mode and no flag.
`l4 run`, `#EVAL`, `#ASSERT`, `l4 batch`, the service, the language server and the golden harness all run this rule; what differs between them is only the report of §4.7.

**Why it is conservative.**
For every directive that does not end in `Stuck` today, the lifted evaluator returns the same value, raises the same error, or fails to terminate, exactly as today.
The lift adds transitions only at the sites in the table above, each of which today raises `Stuck`, and `Stuck` cannot be caught in L4 and aborts the whole directive (`Machine.hs:699-704`, `:724-728`).
So a run that never reaches one of those sites with a term takes the same transitions as today, and a run that does reach one ended in `Stuck` today.
The left-to-right order is what makes this hold for the connectives themselves: when the left operand is known, the frame does what the `IF` did, including not evaluating the right operand when the left decides.
That is also why the connectives do not commute in the presence of errors, which was the answer to Meng's note on U1: `FALSE AND (1 DIVIDED BY 0 GREATER THAN 0)` is `FALSE` and `(1 DIVIDED BY 0 GREATER THAN 0) AND FALSE` raises, today and after (probe `p03-commute.l4`), and the symmetric answer would change a fully supplied directive.
The step counter of §4.5 starts at the first term built, which is the first point at which today's run would have ended, so no fully supplied directive can run out of steps.

Where the lift changes a stuck directive for the worse, it is loud: a directive stuck on the left of an `AND` may now evaluate a right operand that errors, and U11 keeps that error as a guarded leaf next to the unknown rather than in place of it.

What the claim does not cover is anything that is not the evaluator: the printer, the traces, the exporters.
§4.4 changes traces in two-valued mode and is a separate step with a golden to move.

### 4.4 Step 0, in two-valued mode: the connectives become frames (U2, U2b)

Replace the `IfThenElse` bodies of the four built-ins (`Machine.hs:6636-6715`) with frames of their own, through a new lazy value form modelled on `ValROp` so that an indirect call through a variable gets them too, and delete or replace the unreachable rewrite at `Machine.hs:1198-1205` (U2b).
In two-valued mode they compute what the `IF` computed, in the same order.
What changes is what the trace can say: `FALSE OR TRUE` instead of `IF a THEN TRUE ELSE b`.
That moves the `IF` sub-trees out of `lazytrace-exception.golden` (§2.4) and changes the service's reasoning tree.
jl4-mlir's by-name mirror (`synthesizeBoolDesugar`, `synthesizeNotDesugar`) is deleted rather than updated, its eager codegen keeps its short-circuit filter, and the same change adds an `IMPLIES` fixture to the parity corpus whose trace cell must be byte-identical, with a recorded run in which the trace sub-matrix was read (U2b).
No golden or trace output may name the built-ins' parameters `a` and `b`, and the indirect-call golden is read before it is blessed.
The lift of §4.3 lives in these frames; a lift written at `:1198` would never fire.
`BRANCH` stays an `IF` chain, because its guards are a first-match ordering, which `IF` expresses exactly.

### 4.5 Conditionals and the step counter (U4, U4b, U11)

**A join.**
`IF c THEN t ELSE e` with `c` a term evaluates both arms and builds the join `c ? t : e`.
If both arms are the same determined value, by the equality `runBinOpEquals` already supports, the result is that value: `IF x THEN 1 ELSE 1` is `1`.
If the arms are Boolean, the join is the residual `(c AND t) OR (NOT c AND e)`, so `IF x THEN TRUE ELSE TRUE` is `TRUE` and `IF x THEN y ELSE FALSE` is `x AND y`.
Otherwise the join is kept as a term, and a strict built-in that returns a `BOOLEAN` applied to it is pushed into each arm (U4b): `(IF x THEN 1 ELSE 2) GREATER THAN 1` is `x ? FALSE : TRUE`, which is `NOT x`.
At a result, in a field, or under any consumer that is not such an operation, the join is an opaque unknown whose atom set is the union of the condition's and both arms' (U3, U4b).
`BRANCH` is a chain of `IF`s and inherits all of this: a guard after an unknown one is reached and evaluated.
An error in one arm is an `error [c] e` leaf, one mechanism with the connective case (U4b, U11b): `IF x THEN 1 DIVIDED BY 0 ELSE 2` is `x ? error [x] : 2`, reported as "2 unless `x`; errors if `x`".

**`CONSIDER` on a term scrutinee stays unknown for now** (U4): the result is a `fresh` unknown of the result type, naming the scrutinee, and never the no-branch message of §2.4.
The disjunction over arms that an earlier draft proposed needs atoms of the form `s = C` under an exactly-one constraint, and is not ruled.

**The step counter.**
Evaluating both arms is the half of this design that can blow up: nested conditionals on one unknown evaluate a tree of arms, and a recursion whose guard reads an unknown never reaches a base case.
So every evaluation runs under a cumulative counter of machine steps, started when the first term is built (§4.3), with a limit set from the measurement of §7 step 3 (U4).
It counts steps, not depth: the existing cap is on frame depth only (`maximumFrameDepth`, `Exceptions.hs:159`, checked in `pushFrame`, `Machine.hs:857`), and arms run one after another, so depth cannot see a join's blow-up.
**Running out of steps returns `gave-up [c]`**, where `c` is the path condition the evaluator was working under: the conjunction of the term conditions whose unknownness caused the evaluation in progress, innermost last.
It is reported as "gave up; needed _i_" for the inputs in `c` (U11), and it is never a `StackOverflow`.
Recursion guarded by an `IF` over an unknown always runs out, and that is the ruled behaviour, not a defect: `countdown m` with `countdown n MEANS IF n GREATER THAN 0 THEN countdown (n MINUS 1) ELSE 0` gives up naming `m`.
A `gave-up` leaf is carried exactly as an error leaf is: it is never absorbed by `AND FALSE` or `OR TRUE`, because the evaluation it stands for might not terminate once the inputs are supplied, and a definite answer would promise what the two-valued run cannot keep.
That reading of U4's word "unknown" is listed in §4.12.

### 4.6 The membrane: comparisons, arithmetic, equality, and what an atom is (U5, U5b, U6, U6b)

The ladder's §23 drew the line: the circuit is Boolean, typed data lives inside a leaf, and a predicate is the membrane between them.
The evaluator draws it in the same place.
A comparison or a Boolean call over a term is an **atom** of the residual; arithmetic, string and date operations over a term are terms that are not atoms.

**An atom's key is its evaluated term**, never its source position: the operator, the normal forms of its determined operands, and its term operands as terms (U1, U5, U5b).
One source position is evaluated many times, in a helper called with different arguments, in an `IF` arm, in a prelude recursion, and keying by position would make `older 18 AND NOT older 65` the contradiction `A AND NOT A`, decided `FALSE` though age 30 makes it `TRUE`.
Keyed by term, `older 18 AND NOT older 65` is `age GREATER THAN 18 AND NOT age GREATER THAN 65`, two atoms, undetermined; and `older 18 AND NOT older 18` is one atom twice, `FALSE` at the boundary.
The soundness claim of §4.7 is conditional on this key.

**Which terms carry a key.**
An input, an input's field path, a comparison over those, and a Boolean call to an assumed function over those are keyed, and the planner can ask for them: it matches an answer by the key (U5b).
A term that contains an arithmetic result, a join, a non-Boolean assumed call, a `CONSIDER` on a term, a `gave-up`, or an excluded-type equality (below) is `fresh`: no two occurrences share an atom, and the planner never asks about it, only for the inputs it reads (U5, U5b).
So `n PLUS 1 GREATER THAN 3 AND NOT (n PLUS 1 GREATER THAN 3)` is undetermined, and `n PLUS 1 EQUALS n PLUS 1` stays an atom (U6).
This is a loss of precision, not a wrong answer, and §4.12 C1 says what it costs.

**The residual is propositional**, so two atoms over one number are independent to it: `n GREATER THAN 3 AND n LESS THAN 2` is undetermined, not `FALSE`, and `age >= 18 OR age < 18` is undetermined, not `TRUE`.
With atoms keyed by term, that can say "undetermined" where the truth is "no", never the reverse.
Arithmetic reasoning over these atoms belongs to an SMT backend (§4.7, §4.10), which is why an atom keeps its term and not only its key.

**Equality.**
`runBinOpEquals` gains an identity rule before anything else (U6, U6b): the same unknown input on both sides is `TRUE` when the input's declared type has no function or `CONTRACT` component anywhere inside it; a type variable or an unsolved inference variable counts as excluded.
The unknown carries its declared type for this (`ValAssumed` gains the type `evalAssume` already has).
An excluded type stays unknown rather than becoming an error, except a bare function or `CONTRACT` type, which raises today's unsupported-equality error; so `elem g (LIST g)` with `g` an unknown function errors and never returns `TRUE`.
`typeHasFunctionComponent` is lifted out of the DMN exporter's `where` clause for this.
Over `BOOLEAN`, `b1 EQUALS b2` with a term operand is the biconditional `(b1 AND b2) OR (NOT b1 AND NOT b2)`, a connective rather than an atom, which is how `x EQUALS y AND x AND NOT y` reaches `FALSE` at the boundary.
Every other equality with a term operand is a comparison atom.
The right-operand misdiagnosis (`3 EQUALS n`, §2.2) is fixed in build step 1 (U6).

**Lists** of known spine need nothing of their own: `and`, `or`, `all`, `any` and `elem` are prelude recursions over `CONSIDER` and the connectives (`prelude.l4:223-257`, `:465-468`), so `and (LIST TRUE, x, FALSE)` is `FALSE` and `elem n (LIST 1, 2)` is `n EQUALS 1 OR n EQUALS 2`.
A list whose spine is itself a term meets `CONSIDER` on a term, above.
Regulative `EVERY` and `EACH` run over the regulative algebra (§3.5) and are out of scope.

### 4.7 What is decided where

Three places decide something about a residual, and a fourth only reports it.

**1. Inside the evaluator: the tables only.**
§4.3's connective table, §4.5's agreeing arms and §4.6's identity rule.
Nothing else; the decision diagram does not move into `jl4-core` (U3).

**2. At the root: propositional supervaluation of a Boolean residual.**
When a directive, a service call or a batch row ends in a Boolean residual, it is decided once: `TRUE` if it is `TRUE` under every assignment of its atoms, `FALSE` if `FALSE` under every assignment, otherwise undetermined.
This is what the planner's `determinedFromRoot` already does over its diagram (`BooleanDecisionQuery.hs:183-186`): a root that reduces to a terminal is decided.
The word is qualified on purpose.
It is supervaluation over the **atoms as independent propositions**, not over the inputs: the completions it ranges over include ones no input value realises, so `age >= 18 OR age < 18` has a completion with both atoms `FALSE` and stays undetermined (U1b, the first gap).
Because those extra completions can only prevent a decision and never force one, every value it does return holds under every real completion; that is the soundness this spec claims, and all it claims.
**Non-Boolean results are not settled** (U1b, the second gap): a join at the root is reported undetermined even when its condition is a tautology, so `IF (x OR NOT x) THEN 1 ELSE 2` reports "I needed to know `x`" and counts toward the trigger below.
**A guarded leaf is a hole, never a value**: a residual containing `error [c] e` or `gave-up [c]` is decided over the assignments in which no guard holds, and the report names the guards, as "FALSE unless `x`; errors if `x`" (U11b).
That outcome is its own, on the wire, in the K3 report and in every consumer listed under 4 below.

How it is computed: by truth table when every atom of the residual reads one finite-domain input (a `BOOLEAN` or an enumeration), and otherwise by the planner's diagram once it can be reached from the evaluator's side; until then only the finite-domain case is decided locally and the rest is reported undetermined (U3, U3b).
Three counts are kept from the first build, because they are the triggers (U3b): conditions whose residual is a tautology or a contradiction, reported as a lower bound; conditions whose atoms all read one finite-domain input, the trigger for the local truth table; and the same over numeric inputs, the trigger for the SMT backend.

**3. Later, an SMT backend for the arithmetic atoms.**
`age >= 18 OR age < 18` and `n GREATER THAN 3 AND n LESS THAN 2` are decided by a solver over the atoms' terms, not by this evaluator.
`specs/proposals/VERIFICATION-BACKEND-LOWERING-SPEC.md` has the shape: Z3 over SMT-LIB2 text by subprocess (R-V6, `:370`), exact encodings for rounding, modulo and dates (R-V7, `:393`), and three verdicts with every `unknown` naming its reason (R-V8, `:433`).
The terms of §4.2 are what that lowering consumes.

**4. The report, chosen at the root only (U7b).**
The computation is the same for every caller; the caller chooses only how an undetermined result is shown:

| report   | an undetermined result shows as                                                                                                                     | a decided residual shows as  |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------- |
| default  | today's "I could not continue evaluating, because I needed to know the value of …", naming **every** input in the residual's support, not the first | its value                    |
| K3       | `unknown`; an error-leaf residual shows its own outcome, never `unknown` (U11b)                                                                     | see §4.12 C2                 |
| residual | the residual, printed as L4 source (§4.9)                                                                                                           | its value, with the residual |

A `gave-up` is reported as "gave up; needed _i_" under every report.
The language server and the golden harness show the default report and have no setting (U7b).
On the service the report is its own route or a rejected unknown key, never a silently dropped field, and every response states which report it carries; on MCP it is a separate tool or a listed capability (U7b).
In `l4 batch` an undetermined row is a row status, not a failure, and never trips stop-on-error (`Batch.hs:247`, `:299`, `:319`) (U7b).
Exit codes: an undetermined `#ASSERT` exits 1, as a stuck one does today (U1b); an undetermined `#EVAL` under the default report keeps today's exit 1 (`Run.hs:139-152` counts a `ReducedErrored` as a crash).
Ranked against the 2026-08-01 ruling that a failed assertion exits 0, as U7b asks: a failed assertion is an answer the author did not want, and an undetermined directive is no answer at all, which is the distinction `l4 run` already draws between `Fails` and `Errored`.
Every consumer of an evaluation outcome gets an explicit arm for the residual outcome, with no wildcard arm: the API, diagnostics, the `l4 run` exit code, the LSP inspector and rules, and Catala (U1b).

### 4.8 Provenance: what an unknown remembers

An input atom carries what `ValAssumed` carries, the input's `Resolved` name, plus its declared type (U6b) and why it is unknown:

| kind         | origin                                                                                          | four-cell (§3.6) |
| ------------ | ----------------------------------------------------------------------------------------------- | ---------------- |
| `Unsupplied` | an input nobody supplied, no default; on the wire, absent with no `TYPICALLY` (T3)              | `Left Nothing`   |
| `Presumed v` | an input nobody supplied, whose `TYPICALLY v` the presumption switch withheld (§5, T4)          | `Left (Just v)`  |
| `Declined`   | an input the caller answered `null`, "don't know"; `{}` means the same until it is retired (T3) | `Right Nothing`  |

A term that is not an input, a field path, a comparison, a call, carries the provenance of the inputs it reads.
This is what lets the default report name what it is waiting for, the planner rank the questions, and the ladder draw a presumed atom differently from an unasked one.

### 4.9 Printing

`l4 batch` and the REPL evaluate the `prettyLayout` re-print of a module, not its source (`jl4/app/L4/Cli/Batch.hs:244`).
On the main-line extension build, `(p OR q) AND r` used to print as `p OR q AND r` and `l4 batch` answered `TRUE` where `l4 run` answered `FALSE`, exit 0; `unstable` has bracketed nested connectives since `58f53e6b2` (2026-08-03).
So any new connective form, and any printed residual, must round-trip through `prettyLayout` with its brackets intact, and the guard is the evaluation differential of `CLAUDE.md` §3.2.1, extended to residual results.
A residual is printed as L4 source over the input names, `x AND NOT y`, and a join as `IF c THEN t ELSE e`, so it can be pasted back as a rule; a guarded leaf is printed in the report's words, "errors if `x`", because L4 has no expression for it.

### 4.10 Prior art, and the words used for it

**In this tree.**

- `specs/done/BOOLEAN-MINIMIZATION-SPEC.md` proposed this in January and did not build it.
  Its "Approach 1: Symbolic Evaluation with Three-Valued Logic" (`:470-528`) is, despite the title, reading (a): `evalTriBool` evaluates both operands and then consults the table (`:496-510`).
  Its "Recommended Approach: Hybrid" (`:598-604`) made that Phase 1 (`:625-633`), with the decision diagram as Phase 2; Phases 2 and 3 were built as `jl4-query-plan` over the ladder's static tree and Phase 1 was not (§3.2).
  Its own edge case "3a: Tautology" (`:1000-1008`) expects `x OR NOT x` to answer `true`, which Phase 1's `TriBool` cannot give and only Phase 2's diagram can.
  This section is that Hybrid with the two halves in the right order: the evaluator builds the residual, and the diagram decides it.
- `specs/done/PARTIAL-EVAL-VISUALIZER-SPEC.md` is the argument for residuals over K3.
  Its critique (`:19-30`) is that comparing three-valued results "can label variables as irrelevant when they actually influence whether the result becomes determined later" (`:29`), and that "once non-boolean predicates appear (`age >= 21`), the cofactor approach needs a consistent 'atomic predicate' layer anyway" (`:30`); its answer is to compile once to a reduced diagram and read determination and support off the restricted diagram (`:34-43`).
  §4.6's atoms are that predicate layer, and §4.7.2 is that read-off.
- `specs/proposals/VERIFICATION-BACKEND-LOWERING-SPEC.md` owns what this evaluator declines to do, arithmetic over the atoms (§4.7.3).
- `specs/todo/ladder-diagrams-2026/DESIGN.md` §23 (`:927`) is the membrane and §25f (`:1489`) is the seam; `BooleanDecisionQuery.hs:27-43` and `layout.ts:209-266` are the two places that already keep `IMPLIES` as a node.
- `Machine.hs:2749-2753` is the precedent inside the evaluator itself: `RBinOp2` returns the operator applied to its evaluated operands when neither table row applies (§3.5).

**Names from the literature, used where they fit.**

- _Strong Kleene_ (Kleene 1952) names the tables of reading (a) and the known-value rows of §4.3's table.
- _McCarthy's sequential connectives_ name the left-to-right order of reading (b); the asymmetry under errors in §4.3 is theirs.
- _Online partial evaluation_ (Jones, Gomard and Sestoft 1993) names what §4.3 does to a directive: specialise it on the inputs that are known, deciding during evaluation on the actual values, and leave a residual for the rest.
  The residual here is an expression, not a program: there is no code generation and no specialisation of definitions, so the term is used for the shape of the computation and nothing more.
- _Symbolic execution_ (King 1976) is where the path condition comes from: the guard on an error or give-up leaf is the condition under which the two-valued run reaches it.
  Symbolic execution forks one path per branch; this evaluator joins the arms into one term (§4.5), so it borrows the guard and not the enumeration.
- _Supervaluation_ (van Fraassen 1966) names §4.7.2 and nothing else: a residual is supertrue when every classical completion makes it true.
  It is qualified as _propositional_ because the completions range over assignments to the atoms, not over values of the inputs, which is exactly the gap stated there.
  The word was overclaimed once on 2026-10-01, for the whole design, and a skeptic caught it; it is applied here to the boundary decision only.
- Not used: _abstract interpretation_, which this is not, since no abstract domain is joined at a fixpoint; and _three-valued logic_ as a description of the whole design, which describes only reading (a).

### 4.11 Tests, from the rulings

Each row names the ruling it comes from, gives the L4 input, says what the `unstable` binary at `f9a504b77` does today, and states the expected report under this section.
Unless a row says otherwise, `x` and `y` are section `GIVEN … IS A BOOLEAN`, `n` and `age` are `IS A NUMBER`, `d IS A Person` with `DECLARE Person HAS age IS A NUMBER`, and `g` is `ASSUME g IS A FUNCTION FROM NUMBER TO BOOLEAN`, all unsupplied.
"Today" is a probe result where a probe file is named (`reversegear/p01` to `p21` in the session scratchpad, run 2026-10-01); a row with no probe name says where its "today" comes from.
"Expected" is the default report unless the row names another; "undetermined naming _i_" means the default report's "I needed to know the value of _i_"; "unchanged" means §4.3's conservativity claim covers the row.

| #   | from          | input                                                                                         | today                                                                                                                         | expected                                                                                                                           |
| --- | ------------- | --------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| 1   | U1, §2.3      | `x AND FALSE`                                                                                 | stuck on `x` (p01)                                                                                                            | `FALSE`                                                                                                                            |
| 2   | U1            | `x OR TRUE`                                                                                   | stuck (p01)                                                                                                                   | `TRUE`                                                                                                                             |
| 3   | U1            | `x UNLESS TRUE`                                                                               | stuck (p01)                                                                                                                   | `FALSE`                                                                                                                            |
| 4   | U1, U10b      | `x IMPLIES TRUE`                                                                              | stuck (p01, p11)                                                                                                              | `TRUE`; the residual `x IMPLIES TRUE` keeps the seam, so a verdict read from it is `Undetermined` (§25f); see §4.12 C5             |
| 5   | U1, §4.6      | `and (LIST TRUE, x, FALSE)`                                                                   | stuck (p01)                                                                                                                   | `FALSE`                                                                                                                            |
| 6   | U1            | `NOT x`                                                                                       | stuck (p01)                                                                                                                   | undetermined naming `x`; residual `NOT x`                                                                                          |
| 7   | U1b, U3, U12b | `x OR NOT x`                                                                                  | stuck (p01)                                                                                                                   | `TRUE`                                                                                                                             |
| 8   | U1b, U3       | `x AND NOT x`                                                                                 | stuck (p01)                                                                                                                   | `FALSE`                                                                                                                            |
| 9   | §4.5          | `IF x THEN 1 ELSE 1`                                                                          | stuck (p01)                                                                                                                   | `1`                                                                                                                                |
| 10  | U6b           | `x EQUALS x`                                                                                  | stuck (p01)                                                                                                                   | `TRUE`                                                                                                                             |
| 11  | U5            | `n EQUALS 3`                                                                                  | stuck on `n` (p01)                                                                                                            | undetermined naming `n`; atom `n EQUALS 3`                                                                                         |
| 12  | U6            | `3 EQUALS n`                                                                                  | "equality on types that do not support it" (p01)                                                                              | as row 11                                                                                                                          |
| 13  | U1, U5        | `older 18 AND NOT older 65`, with `older k MEANS age GREATER THAN k`                          | stuck on `age` (p02)                                                                                                          | undetermined naming `age`; residual `age GREATER THAN 18 AND NOT age GREATER THAN 65`; never `FALSE`                               |
| 14  | U5            | `older 18 AND NOT older 18`                                                                   | stuck (p02)                                                                                                                   | `FALSE`                                                                                                                            |
| 15  | U1b, U3b      | `age >= 18 OR age < 18`                                                                       | stuck (p02)                                                                                                                   | undetermined naming `age`; the numeric count of §4.7.2 rises by one                                                                |
| 16  | U1b, U3       | `IF (x OR NOT x) THEN 1 ELSE 2`                                                               | stuck on `x` (p02)                                                                                                            | undetermined naming `x`; the tautology count of §4.7.2 rises by one                                                                |
| 17  | U1b           | `FALSE AND (1 DIVIDED BY 0 GREATER THAN 0)`                                                   | `FALSE` (p03)                                                                                                                 | `FALSE`, unchanged                                                                                                                 |
| 18  | U1b           | `(1 DIVIDED BY 0 GREATER THAN 0) AND FALSE`                                                   | division by zero (p03)                                                                                                        | division by zero, unchanged                                                                                                        |
| 19  | U11, U11b     | `x AND (1 DIVIDED BY 0 GREATER THAN 0)`                                                       | stuck on `x` (p03)                                                                                                            | "FALSE unless `x`; errors (division by zero) if `x`", its own outcome                                                              |
| 20  | U11b          | `f TRUE`, with `f b MEANS b AND (1 DIVIDED BY 0 GREATER THAN 0)`                              | division by zero (p03)                                                                                                        | division by zero, unchanged                                                                                                        |
| 21  | U11b          | `(x AND (1 DIVIDED BY 0 GREATER THAN 0)) AND FALSE`                                           | stuck (p21)                                                                                                                   | as row 19; never absorbed to `FALSE`                                                                                               |
| 22  | U11b          | `x OR (1 DIVIDED BY 0 GREATER THAN 0)`                                                        | stuck (p21)                                                                                                                   | "TRUE if `x`; errors if `NOT x`"                                                                                                   |
| 23  | U1b           | `#ASSERT x AND y`                                                                             | "assertion could not be evaluated", naming only `x`, exit 1 (p04)                                                             | undetermined naming `x` and `y`, exit 1                                                                                            |
| 24  | U1b           | `#ASSERT NOT (x AND y)`                                                                       | as row 23 (p04)                                                                                                               | as row 23                                                                                                                          |
| 25  | U1b, U3       | `#ASSERT x OR NOT x`                                                                          | could not be evaluated (p21)                                                                                                  | satisfied                                                                                                                          |
| 26  | U3            | `#ASSERT x AND NOT x`                                                                         | could not be evaluated (p21)                                                                                                  | failed, exit 0                                                                                                                     |
| 27  | U4            | `IF x THEN 1 ELSE 2`                                                                          | stuck (p07)                                                                                                                   | undetermined naming `x`                                                                                                            |
| 28  | U4b           | `(IF x THEN 1 ELSE 2) GREATER THAN 1`                                                         | stuck (p07)                                                                                                                   | residual `NOT x`; undetermined naming `x`                                                                                          |
| 29  | U4b, U11b     | `IF x THEN 1 DIVIDED BY 0 ELSE 2`                                                             | stuck (p07)                                                                                                                   | "2 unless `x`; errors if `x`"                                                                                                      |
| 30  | §4.3          | `IF TRUE THEN 1 ELSE 1 DIVIDED BY 0`                                                          | `1` (p07)                                                                                                                     | `1`, unchanged                                                                                                                     |
| 31  | §4.5          | `IF x THEN TRUE ELSE TRUE`                                                                    | stuck (p07)                                                                                                                   | `TRUE`                                                                                                                             |
| 32  | U4b, U5b      | `(IF x THEN 2 ELSE 3) PLUS 1 GREATER THAN 3`                                                  | stuck (p21)                                                                                                                   | undetermined naming `x`: `PLUS` is not pushed into the arms, so the comparison is over a `fresh` term; see §4.12 C1                |
| 33  | U4, U11       | `countdown m`, with `countdown n MEANS IF n GREATER THAN 0 THEN countdown (n MINUS 1) ELSE 0` | stuck on `m` (p08)                                                                                                            | "gave up; needed `m`"; `countdown 3` stays `0`                                                                                     |
| 34  | U4, §2.4      | `CONSIDER m WHEN NOTHING THEN 1 WHEN JUST y THEN 2`, with `m IS A MAYBE NUMBER`               | "reached a CONSIDER that has no branch for it" (p09)                                                                          | build step 1: stuck naming `m`; lifted: undetermined naming `m`                                                                    |
| 35  | U5b           | `d's age`                                                                                     | the no-branch message (p05)                                                                                                   | undetermined naming `d's age`                                                                                                      |
| 36  | U5b           | `d's age AT LEAST 18 AND NOT d's age AT LEAST 18`                                             | the no-branch message (p05)                                                                                                   | `FALSE`                                                                                                                            |
| 37  | U5b           | `d's age AT LEAST 18`                                                                         | the no-branch message (p05)                                                                                                   | undetermined; atom `d's age AT LEAST 18`, askable                                                                                  |
| 38  | U5b           | `g 3 AND NOT g 3`                                                                             | stuck on `g` (p12)                                                                                                            | `FALSE`                                                                                                                            |
| 39  | U5b           | `g 3 AND NOT g 4`                                                                             | stuck (p12)                                                                                                                   | undetermined naming `g`; two atoms                                                                                                 |
| 40  | §4.3          | `FALSE AND g 3`                                                                               | `FALSE` (p12)                                                                                                                 | `FALSE`, unchanged                                                                                                                 |
| 41  | U5, U5b       | `n PLUS 1 GREATER THAN 3 AND NOT (n PLUS 1 GREATER THAN 3)`                                   | stuck (p15)                                                                                                                   | undetermined naming `n`, two `fresh` atoms; see §4.12 C1                                                                           |
| 42  | U6            | `n PLUS 1 EQUALS n PLUS 1`                                                                    | stuck (p15)                                                                                                                   | undetermined naming `n`; see §4.12 C1                                                                                              |
| 43  | §4.6          | `n GREATER THAN 3 AND n LESS THAN 2`                                                          | stuck (p15)                                                                                                                   | undetermined naming `n`; the numeric count rises by one                                                                            |
| 44  | §4.7          | `n PLUS 1`                                                                                    | stuck (p15)                                                                                                                   | undetermined naming `n`                                                                                                            |
| 45  | U6b           | `elem g (LIST g)`                                                                             | stuck on `g` (p06)                                                                                                            | "equality on types that do not support it", exit 1; never `TRUE`                                                                   |
| 46  | §4.6          | `elem n (LIST 1, 2)`                                                                          | stuck (p06)                                                                                                                   | undetermined naming `n`; residual `n EQUALS 1 OR n EQUALS 2`                                                                       |
| 47  | §4.3          | `elem 3 (LIST 3, n)`                                                                          | `TRUE` (p06)                                                                                                                  | `TRUE`, unchanged                                                                                                                  |
| 48  | U6, §4.3      | `elem 3 (LIST n, 3)`                                                                          | "equality on types that do not support it" (p06)                                                                              | `TRUE`                                                                                                                             |
| 49  | U10           | `f x`, with `f b MEANS TRUE OR b`                                                             | `TRUE` (p10)                                                                                                                  | `TRUE`; a shared case for `eval.ts` and `nodeValue`                                                                                |
| 50  | U10           | `g x`, with `g b MEANS b OR TRUE`                                                             | stuck (p10)                                                                                                                   | `TRUE`                                                                                                                             |
| 51  | U2, U2b       | the trace of `FALSE OR TRUE`                                                                  | `lazytrace-exception.golden:15-16` shows `IF a THEN TRUE ELSE b`; `#EVALTRACE` on the binary prints "no trace captured" (p16) | the trace shows `FALSE OR TRUE`; no golden names `a` or `b`                                                                        |
| 52  | §2.4, U7b     | `#EVAL TRUE AND x`, `#EVAL TRUE IMPLIES x`, `#EVAL x`                                         | each prints `x` as a value, JSON `"kind":"value"`, `"ok":true`, exit 0 (p11, p17)                                             | undetermined naming `x`, exit 1                                                                                                    |
| 53  | U8, T4, T6    | `` `has capacity` AND `is adult` ``, with `` `has capacity` IS A BOOLEAN TYPICALLY TRUE ``    | stuck on `` `has capacity` `` when a directive reads it (p14, p18); `` `is adult` `` printed as a value through a rule (p19)  | undetermined naming `is adult`, with `presumed` listing `has capacity`; presumption off: residual over both                        |
| 54  | U9, T3        | service: `{}` for a boolean                                                                   | `{"result":{"value":false}}`, no diagnostic (§2.5, measured by the coordinating session)                                      | undetermined naming the input, the report stated; `null` the same; absent with `TYPICALLY` takes the default, listed in `presumed` |
| 55  | U7b           | an `l4 batch` row with an unsupplied input                                                    | refused, "Missing required field" (`TYPICALLY-ONE-BEHAVIOUR-SPEC.md` §2, p7)                                                  | row status undetermined; stop-on-error not tripped                                                                                 |
| 56  | U12, U12b     | ``NOTHING `kor` (knot NOTHING)``                                                              | `NOTHING`; `#ASSERT … EQUALS NOTHING` satisfied (p13)                                                                         | unchanged: the library is reading (a), and row 7 is the contrast U12b asks the comment to draw                                     |
| 57  | U11b, U7b     | row 19 under the K3 report                                                                    | not probed                                                                                                                    | "errors if `x`", never a bare `unknown`                                                                                            |
| 58  | §2.6, §4.3    | every corpus directive not stuck today (7,202 of 7,211)                                       | §2.6's census                                                                                                                 | unchanged value, error or non-termination, measured by §7's differential                                                           |

Of the 58 rows, 54 were probed today; rows 54, 55, 57 and 58 were not.

### 4.12 Conflicts for Meng

These are places where the definition above shows two recorded rulings pulling apart, or a ruling's word having lost its referent.
None is resolved here; each says what the definition does in the meantime.

**C1. Atom identity: by input, or by term.**
U5 ("an arithmetic unknown operand gets a fresh atom per evaluation"), U5b ("only unknowns that carry no term (arithmetic results, `IF` joins, non-Boolean assumed calls) get fresh atoms") and U6 ("derived unknowns (`n PLUS 1 EQUALS n PLUS 1`) stay comparison atoms") make an arithmetic result keyless.
§4.2 gives it a term anyway, because the SMT backend of §4.7.3 needs the term, and keying by that term would be sound for the same reason keying a comparison by term is: a built-in operation is a function of its operands, so two occurrences of one term denote one value.
Under the rulings as recorded, rows 41, 42 and 32 are undetermined; keyed by term they would be `FALSE`, `TRUE` and `NOT x`.
The same question reaches U6b's identity rule, which is stated for "the same unknown input on both sides": under it `d's age EQUALS d's age` is an atom, while row 36, `d's age AT LEAST 18 AND NOT d's age AT LEAST 18`, is `FALSE`, because the comparison is keyed by the field-path term and the equality is not.
The definition follows the rulings.
The recommendation is to key every atom by its full term, keep `fresh` for the genuinely keyless (a `CONSIDER` on a term, a `gave-up`, an excluded-type equality), and leave U5b's askability rule as it is, so the planner still asks only for inputs and field paths.

**C2. Whether the K3 report sees the boundary decision.**
U1b: "`--unknowns k3` is true strong Kleene: atoms only, no tautology settling, as #526 §8 step 3 already says."
U7b: "What the caller chooses is the report, never the computation", and "the caller chooses only how an undetermined result is reported".
The boundary decision of §4.7.2 is computation.
If it runs before the report is chosen, the K3 report shows `x OR NOT x` as `TRUE` and U1b's sentence is false of it; if the K3 report skips it, the caller is choosing computation, which U7b retired.
The definition leaves the K3 column of §4.7.4 open for a decided residual.
The recommendation is to read U1b's sentence as describing build step 3 of §8, the stage before a boundary decider exists, and to let every report show a decided residual as its value; the K3 report then differs from the default only in printing `unknown` instead of naming the inputs.

**C3. What running out of steps returns.**
U4: "Running out returns an unknown naming the pending condition".
U11: "Divergence on an unknown is caught by PETROL's step counter ('gave up; needed _x_')".
U11b: "A residual that contains an error leaf is never absorbed", because a definite `FALSE` would promise what a supplied run that errors cannot keep.
An ordinary unknown is absorbed by `AND FALSE`; so with `loop n MEANS IF n GREATER THAN 0 THEN loop n ELSE 0`, the lifted `(loop m GREATER THAN 0) AND FALSE` would be `FALSE` for unknown `m`, and the two-valued run with `m` set to 1 does not terminate.
That is U11b's objection in a different coat.
The definition treats `gave-up` as a guarded leaf, never absorbed (§4.5), and reads U4's "unknown" as that leaf.

**C4. The step counter's scope.**
U4: "a cumulative step counter, explore mode only".
U7b: "Every evaluation is lifted; there is no evaluation mode."
A counter that runs from the first step of every evaluation would turn a long but fully supplied computation into a `gave-up`, which breaks §4.3's conservativity.
The definition starts the counter at the first term built, which is the only reading of "explore mode only" left once there is no mode (§4.5), and asks for that reading to be confirmed.

**C5. A decided value with an undetermined verdict at the evaluator's root.**
Row 4, `x IMPLIES TRUE`, is `TRUE` by §4.7.2, and U10b records the pair "value `TRUE`, verdict `Undetermined`" as the expected answer.
The default report of §4.7.4 prints `TRUE` and names no input, because the result is decided; §25f's finding is that this is the one case where a met requirement must not end the interview.
The residual report carries the seam intact, so a verdict-aware consumer can still ask for the scope; the default report cannot.
Whether the default report should name the scope's inputs when the root is an `IMPLIES` with an undetermined scope is not ruled anywhere, and the definition does not do it.

---

## 5. `TYPICALLY`, R8, and the four cells

R8 fills a defaulted section `GIVEN` once at the root: discharge rewrites its elaboration from an `ASSUME` into a 0-ary definition whose body is the default (`jl4-core/src/L4/Discharge.hs:281-295`, `fillInDefault`).
So by the time the evaluator runs, a defaulted input is an ordinary value; the evaluator cannot tell it came from a default.

**Ruled (U8, T4, T4b):** one presumption switch applies to every evaluation, on by default, landing with the `TYPICALLY` work's W3/W4 and not with this spec.

- **On:** defaults apply as R8 says, and the response carries T6's `presumed` list of the defaults actually forced, with their declaration lines: "`TRUE`, presuming `has capacity`".
  This is the ladder's `respectDefaults: true` (§3.6), and the verdict is DESIGN §22's tentative box.
- **Off:** an absent input with a default is treated as absent with none, and becomes a `Presumed v` atom (§4.8) whose `v` is the planner's prior; only Boolean defaults become priors (T4).
  The switch withdraws a default only where a request can supply the value; elsewhere the result says "rests on presumed _x_" and does not go stuck (T4b).
  This is the investigator's reading: a presumption is a question not yet asked, not an answer.
- `null` never takes a default, under either setting (T3).

R8's "filled in once at the root" is unchanged by either setting: both decide at the same root, which is the only place an input can be absent.
What R8 does not reach, and the parallel `TYPICALLY` work (branch `spec/typically-unify`) owns, is that the service's wrapper ignores `TYPICALLY` altogether (§2.5, T3).
Two probe results from today that this spec does not explain are in §10.

---

## 6. Reports, and what does not move

**There is no switch (U7b).**
Every evaluation is lifted; the module does not decide, and neither does the caller.
The caller chooses the report of §4.7.4:

- `l4 run` and `l4 batch`: the default report, unless a flag names the K3 or the residual report; the flag names a report, not a mode.
- The service: the report is its own route, as `/query-plan` is, or an unknown key is rejected; every response states its report.
  A residual response is `{"determined": null, "residual": "<L4 source>", "needs": [...], "verdict": "Undetermined"}`, the planner's own vocabulary (§3.3).
- MCP: a separate tool or a listed capability, never a reserved argument.
- No new directive.
  A `#EXPLORE` would make the module decide, and it would be a directive every exporter has to learn to ignore.

**What does not move.**
Every committed golden except the trace golden Step 0 names (§4.4): the corpus has nine stuck directives (§2.6), and under the default report a single-input residual prints the text today's `Stuck` prints, so those nine change only where the residual names more than one input or decides.
Build step 1's bare-result fix (§8) also moves any golden that prints a bare assumed name as a value, which that step must count rather than assume.
That is U7's scoping of "nothing changes" to committed goldens.

**What the service's `fromMaybe FALSE` becomes.**
Removed at all three sites, `CodeGen.hs:239`, `:335`, `:603` (T3, T3b): an absent boolean on the wrapper path binds to a placeholder assumed term, lazy, stuck only if read and naming the input; `null` and `{}` bind the same way and never take a default; the direct path's eager refusal (`Jl4.hs:448`) stays, and its lazy binding is its own work item.
That is the `TYPICALLY` work's W1 and W2, listed here so the two specs do not each assume the other has it.

---

## 7. Cost, and how to measure it before deciding

The lift costs nothing on a directive that never meets an unknown: §4.3's transitions are the same ones, and the step counter has not started.
On a directive that does, it costs exactly the evaluation today's `Stuck` skipped, which is the right operands of undecided connectives and both arms of undecided conditionals.
That is unbounded in principle, so it is measured, not guessed:

1. **Baseline.** Today's census (§2.6) shows the corpus directives are almost all fully supplied (9 stuck in 7,211), so the workload has to be made: for every `@export` function in the corpus, take each directive that calls it and generate its partial-input variants, dropping each input in turn and then every pair, which is what a wizard does mid-interview.
2. **Coverage.** On those variants, the `f9a504b77` binary against the lifted one: how many end in a value, a decided residual, an undetermined residual, a guarded leaf, a `gave-up`, a different error, or a timeout.
3. **Blow-up.** Per directive, the total steps taken under §4.5's counter, the largest residual, the three counts of §4.7.2, and the number of conditionals evaluated on a term condition, each against the two-valued run of the same directive with every input supplied.
   The machine has no step counter today, only the depth cap (`maximumFrameDepth`), so the counter is part of this measurement.
4. **Wall clock.** `jl4-test` and the §3.2.1 differential must be unchanged within noise on fully supplied directives; that is the cost to everyone who never meets an unknown.
5. **Positive controls.** One directive constructed to evaluate both arms of a nested conditional on one unknown, depth 10, whose step count the measurement must show growing; and rows 13, 14, 15, 16, 19, 20 and 36 of §4.11, which must come out as the table says.
   A measurement that scores row 19 as a plain unknown has not seen the leaf, and one that scores row 13 as `FALSE` has keyed atoms by position.

U4's step limit is set from the distribution step 3 produces, not before.

---

## 8. Build sequence

1. **Two-valued fixes, no lift.** A `ValAssumed` scrutinee of a `CONSIDER` raises `Stuck`, naming it (§2.4); the selector path raises the same (§2.4, probe `p05-record.l4`); the right-operand misdiagnosis of `runBinOpEquals` is fixed (U6); and a bare assumed term as the result of an `#EVAL` is reported as `Stuck`, as `#ASSERT` already does (`EvaluateLazy.hs:306`; §2.4, probe `p17-bare.l4`), which is proposed here and not yet ruled.
   Independent; small.
2. **Step 0** (§4.4, U2, U2b): the built-in connectives as frames, with the trace golden, the service reasoning tree and jl4-mlir's parity harness moved together, measured.
3. **Atoms-only residuals, default report.** Input atoms, field paths, comparison atoms, Boolean assumed calls, the connective table of §4.3, the identity rule of §4.6, and the default report naming every input; no boundary decision yet.
   Rows 1 to 6, 11 to 15, 23, 24, 35, 37 and 52 of §4.11 answer correctly.
   This is what U1b calls "true strong Kleene: atoms only".
4. **The boundary decider and the residual report.** §4.7.2 by truth table over finite-domain atoms, the three counts, the K3 and residual reports, residuals printed as source and round-tripped through `prettyLayout`, and the §3.2.1 differential extended to residual results.
   Rows 7, 8, 10, 14, 25, 26, 36 and 38.
5. **Joins, the step counter and guarded leaves** (§4.5, U4, U4b, U11, U11b), after the measurement of §7.
   Rows 16, 19 to 22 and 27 to 34.
6. **Service and MCP report routes**, the batch row status, the planner reading residuals from evaluation instead of only from the static ladder tree, and the counts reported (U7b, U3b).
7. **The two TypeScript evaluators** (U10, U10b): when step 3 lands, shared L4 cases (rows 4, 7, 19, 49, 50) run through the Haskell evaluator and the visualizer's `eval.ts`, which is replaced by a call after step 6.
   `ladder-core`'s `nodeValue` (`layout.ts:209-266`) is kept permanently, held to the Haskell evaluator on the connective cases with each call's engine value fed in as a pin, with the tautology case (it stays `Undetermined`) and the error case (it has no error value) listed as known divergences; the `IMPLIES` case expects value `TRUE` and verdict `Undetermined` against `verdictFor` and both `verdictOf`s, extending `verdict.test.ts`.

---

## 9. Open rulings

Each is a card on the bench "Unknowns and Defaults" (claude.ai artifact `XQk522h6PN2xv8YFPhogJc`, db collection `l4-unknowns-defaults-1001`), where an independent skeptic's objection and a revised recommendation sit beside it; U8 and U9 share cards with `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` T4 and T3.
A ruling is recorded here when it is made.

### U1 — Semantics: left-sequential strong Kleene with residual values

**The question.** Which of §4.1's candidates is the evaluator's semantics of an unknown?
**RULED 2026-10-01.** Meng marked `accept` on bench card U1 at 09:55:58Z, with the note _"Do we have commutativity?"_ The ruling, as printed on the card: Kleene tables on known values, left-to-right order as today, an undecided Boolean returned as a residual, implemented in the built-in connective functions. Condition: an atom is identified by its evaluated term (operator, known operand values, unknown inputs), never by source position, and `older 18 AND NOT older 65` is a §7 positive control. `x OR NOT x` is settled at the boundary, not inside the evaluator (U3).
**The answer to the note**, as printed on card U1b: on values over {TRUE, FALSE, unknown}, yes; the strong Kleene tables are symmetric. With errors and non-termination, no, by design: `FALSE AND (1/0 > 0)` is FALSE and `(1/0 > 0) AND FALSE` raises, because left-to-right order is what keeps every fully supplied directive's answer unchanged (§4.3). Residuals commute as Boolean functions; `IMPLIES` does not commute in any logic; FEEL's connectives commute even with errors, because FEEL turns an error into `null`.
**AMENDED 2026-10-01**, by bench card U1b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: Everything U1 ruled, plus the following. `--unknowns k3` is true strong Kleene: atoms only, no tautology settling, as #526 §8 step 3 already says. Deciding a residual at the boundary is named "propositional supervaluation of a Boolean residual", with its two gaps stated in §4.1–4.2 and on the DMN limits page: atoms are independent, and non-Boolean results are not settled. That page also records `x OR NOT x` (L4 TRUE at the boundary, FEEL `null`) and `IF` on an unknown condition (FEEL takes the else arm). Every consumer of an evaluation outcome gets an explicit residual arm, listed by site in the spec (API, diagnostics, `l4 run` exit code, LSP inspector and rules, Catala), with no wildcard arm over the new outcome. An undetermined assertion exits 1, as a stuck one does today. Positive controls: `older 18 AND NOT older 65`, `age >= 18 OR age < 18`, `IF (x OR NOT x) THEN 1 ELSE 2`, and `#ASSERT x AND y` / `#ASSERT NOT (x AND y)` both undetermined.

### U2 — Step 0 ships in two-valued mode

**The question.** Replace the `IF` rewrite of `AND`/`OR`/`IMPLIES`/`NOT` with frames even if the lift is never switched on?
**RULED 2026-10-01.** Meng marked `accept` on bench card U2 at 09:56:10Z, with no note. The ruling, as printed on the card: Give the built-in connectives their own frames, flag off, and delete or replace the unreachable rewrite at `Machine.hs:1198-1205`. In the same change, update the service's reasoning tree and jl4-mlir's mirrored trace shape and parity harness. Success: the `IF` sub-trees disappear from the golden and jl4-mlir parity holds.
**AMENDED 2026-10-01**, by bench card U2b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: The frames live in the built-in values, through a new lazy value form modelled on `ValROp`, so indirect calls get them. jl4-mlir's by-name mirror (`synthesizeBoolDesugar`/`synthesizeNotDesugar`) is deleted, not updated; the eager codegen keeps its short-circuit filter. The same PR adds an `IMPLIES` fixture to the parity-harness corpus whose trace cell must be byte-identical, and records a run in which the trace sub-matrix was read, since it is not a gate. No golden or trace output may name the built-ins' parameters `a` and `b`, and the indirect-call golden is read before it is blessed.

### U3 — Where the decision diagram lives

**The question.** Move `BoolExpr` and the diagram from `jl4-query-plan` into `jl4-core` (or a package below both), so the evaluator can recognise a tautology mid-evaluation and take the right `IF` arm?
**RULED 2026-10-01.** Meng marked `accept` on bench card U3 at 09:56:22Z, with no note. The ruling, as printed on the card: Residuals are decided at the boundary, for Boolean results only; non-Boolean conditionals lose the condition, and the spec says so. Add a §7 count of conditions whose residual is a tautology or contradiction, and make that count the trigger to decide small residuals locally by truth table.
**AMENDED 2026-10-01**, by bench card U3b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: The §7 tautology/contradiction count is reported as a lower bound, and stays the trigger for moving the diagram. A count of conditions whose atoms all read one finite-domain input (BOOLEAN or enumeration) triggers deciding small residuals locally by truth table; the same count over numeric inputs is recorded separately as the trigger for the SMT backend (#526 §4.6). U3's clause that non-Boolean conditionals lose the condition, and that the spec says so, is kept for whatever U4b does not cover.

### U4 — Unknown conditions: evaluate the arms, and under what budget

**The question.** Does an `IF`/`BRANCH`/`CONSIDER` on an unknown evaluate its arms and join them (§4.5), and with what bound?
**RULED 2026-10-01.** Meng marked `accept`, option A on bench card U4 at 09:56:50Z, with no note. The ruling, as printed on the card: Join for `IF` and `BRANCH`. Add a cumulative step counter, explore mode only, set from §7's measurement of total steps (not depth). Running out returns an unknown naming the pending condition, never `StackOverflow`. Recursion guarded by an `IF` over an unknown always runs out, and the spec says so. `CONSIDER` on an unknown stays unknown for now.
**AMENDED 2026-10-01**, by bench card U4b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: Join for `IF` and `BRANCH` under the explore-only step counter, as ruled. Inside the evaluator, a non-Boolean join keeps `c ? t : e` and pushes a strict operation that returns a Boolean (a comparison) into each arm; at a result, a field or any non-strict consumer it falls back to the opaque unknown, so U3's boundary promise holds. An error in one arm joins as a guarded error, exactly as TRIPWIRE's error leaf does for `AND`/`OR`, and it always appears in the response with its guard.

### U5 — Comparisons become atoms (the membrane)

**The question.** Is a comparison over an unknown a residual atom, identified by its evaluated term (§4.6)?
**RULED 2026-10-01.** Meng marked `accept` on bench card U5 at 10:13:28Z, with no note. The ruling, as printed on the card: A comparison over an unknown is an atom identified by its evaluated term: the operator, the normal forms of the known operands, and the unknown inputs. An arithmetic unknown operand gets a fresh atom per evaluation. The spec's soundness claim is made conditional on this, and a helper-called-twice test is added. The spec states how evaluator atoms map to planner questions.
**AMENDED 2026-10-01**, by bench card U5b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: A generated selector applied to an unknown record returns a term, the input plus its field path, not a fresh atom. A comparison over unknowns is an atom keyed by its evaluated term (operator, normal forms of the known operands, unknown operands as terms) and stays askable; the planner matches answers by that key. A Boolean call to an assumed function is an atom keyed by the function plus the normal forms of its arguments, and is askable too. Only unknowns that carry no term (arithmetic results, `IF` joins, non-Boolean assumed calls) get fresh atoms, and the planner never asks about those; it asks for the inputs they read. Tests: a helper called twice with different thresholds, and `d's age AT LEAST 18 AND NOT d's age AT LEAST 18` deciding FALSE at the boundary.

### U6 — An unknown equals itself

**The question.** Is `x EQUALS x` `TRUE` when `x` is unknown?
**RULED 2026-10-01.** Meng marked `accept` on bench card U6 at 10:14:10Z, with no note. The ruling, as printed on the card: An identity rule in `runBinOpEquals`: the same unknown input on both sides gives a literal `TRUE`, for numbers, strings, dates and times, lists and constructors. Functions and obligations keep today's error. Derived unknowns (`n PLUS 1 EQUALS n PLUS 1`) stay comparison atoms. Fix the right-operand misdiagnosis in build step 1.
**AMENDED 2026-10-01**, by bench card U6b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: The unknown carries its declared type (`ValAssumed` gains the type `evalAssume` already has), and `runBinOpEquals` applies the identity rule when the same unknown input is on both sides and that type has no function or `CONTRACT` component anywhere inside it. A type variable or unsolved inference variable counts as excluded. Excluded types stay unknown in explore mode rather than becoming a definite error. Only a bare function or `CONTRACT` type raises today's unsupported-equality error. `typeHasFunctionComponent` is lifted out of DMN's `where` clause, with its component-type map, for reuse. The right-operand misdiagnosis is fixed in build step 1.

### U7 — The switch is per evaluation

**The question.** CLI flag and service mode, no directive (§6)?
**RULED 2026-10-01.** Meng marked `accept` on bench card U7 at 10:16:06Z with the note _"This affects purity and feels tantamount to a dynamically chosen effect system. Footgun. Discuss."_ The ruling, as printed on the card: The caller decides, never the module: CLI flag, service request field (following `evalBackend`'s precedent), _and_ a language-server setting and a golden-harness option so explore mode can be tested. No new directive, because every exporter would have to learn it. "Nothing changes with the flag off" is scoped to committed goldens.
**AMENDED 2026-10-01**, by bench card U7b, which an independent skeptic reviewed, ruled by Meng in chat with its word LAMPSHADE. This answers his note: the lift changes only directives that are stuck today (§4.3), so every evaluation is lifted and there is no evaluation mode. What the caller chooses is the report, never the computation. The amendment, as the card printed it: Every evaluation is lifted; there is no evaluation mode. The caller chooses only how an undetermined result is reported: as today's "I needed to know the value of …" (the default, naming every input it waits on), as K3 "unknown", or as the residual itself. The language server and the golden harness show the default report and gain no evaluation setting. On the service the report choice cannot be dropped silently: its own route (as `/query-plan` has) or rejection of unknown keys, and every response states its report. On MCP it is a separate tool or a listed capability, never a reserved argument. In `l4 batch` an undetermined row is a row status, not a failure, so it never trips stop-on-error. The exit code for an undetermined directive is ranked explicitly against the 2026-08-01 ruling that a failed assertion exits 0.

### U8 — Presumptions in explore mode

Amended the same day by bench card TU-presume-b, recorded in full in `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` §5.

**The question.** When the lift is on, does an unsupplied `TYPICALLY` input take its default (marked as presumed) or stay an atom whose default is a prior (§5)?
**RULED 2026-10-01**, on bench card TU-presume, shared with `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` T4: Meng marked `accept` at 09:54:00Z, with no note. The ruling is recorded in full at T4. In short, one presumption switch applies to every evaluation, decide mode included. It is on by default and lands with that spec's W3/W4, not with explore mode. With it off, an absent input with a default is treated as absent with none: stuck in decide mode, unknown in explore mode. `null` never takes a default. The "presuming _x_" mark is the `presumed` list of T6. With presumption off, only boolean defaults become planner priors.

### U9 — The wire's three absences

Amended the same day by bench card TU-wire-b, recorded in full in `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` §5.

**The question.** The service distinguishes a missing field, `null` and `{}` (§2.5). What does each mean?
**RULED 2026-10-01**, on bench card TU-wire, shared with `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` T3: Meng marked `accept`, option B, at 09:53:17Z, with no note. The ruling is recorded in full at T3. Missing is `Left`: not asked, so a default applies. `null` is `Right Nothing`, "don't know", and never takes a default. `{}` means `null` until it is retired, which happens after the service is instrumented to show who sends it. The cause of today's silent FALSE, `fromMaybe FALSE` at `CodeGen.hs:239, 335, 603`, is removed.

### U10 — The ladder's TypeScript evaluator

**The question.** Keep §3.4's second evaluator, or make the ladder ask the Haskell one?
**RULED 2026-10-01.** Meng marked `accept` on bench card U10 at 10:16:33Z with the note _"Does this cure the objection?"_ The ruling, as printed on the card: When build step 3 lands, add shared L4 cases run through both TypeScript evaluators and the Haskell one, each with its expected value: a call with an unknown argument whose body decides anyway, `FALSE AND` a call that errors, and `x OR NOT x`. Follow `verdict.test.ts`'s pattern. Replace both with a call after service explore mode. Fix §8 step 7 to match.
**The answer to the note:** partly. It cures the first objection by testing L4 cases rather than a truth table, as the second-round skeptic confirmed. But `ladder-core`'s `nodeValue` cannot agree with the Haskell evaluator on every case, by design, which U10b settles.
**AMENDED 2026-10-01**, by bench card U10b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: When build step 3 lands, the shared cases run through the Haskell evaluator and the visualizer's `eval.ts`, which is then replaced by a call after service explore mode. `ladder-core`'s `nodeValue` is kept permanently and held to the Haskell evaluator on the connective cases, with each call's engine value fed in as a pin; the tautology case (it stays Undetermined, conservatively) and the error case (it has no error value) are listed as known divergences. The `IMPLIES` case expects value TRUE and verdict Undetermined, and runs against `verdictFor` and both `verdictOf`s, extending `verdict.test.ts`. #526 §8 step 7 is corrected to match.

### U11 — An error on the right of an undecided left

**The question.** `x AND (1 DIVIDED BY 0 > 0)` with `x` unknown: the right operand's error (as (b) gives), or unknown?
**RULED 2026-10-01.** Meng marked `accept`, option C on bench card U11 at 10:16:42Z, with no note. The ruling, as printed on the card: Add an error leaf to the residual: shown in the result, raised only if its guard becomes TRUE. Divergence on an unknown is caught by PETROL's step counter ("gave up; needed _x_"). The same rule covers an error in an `IF` arm.
**AMENDED 2026-10-01**, by bench card U11b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: A residual that contains an error leaf is never absorbed: `p AND FALSE`, `p OR TRUE` and boundary deciding (U3) keep it as "FALSE unless _x_; errors if _x_". The known-or-not reading gives an error-leaf residual its own outcome, never a bare unknown, carried on the wire, in U10's shared cases, in U1b's list of outcome consumers, in the service's explore response and under `--unknowns k3`. A non-Boolean arm's error is U4b's guarded error, one mechanism, not a second marker. Positive control: the probe above gives that outcome for unknown `x`, and the error for `x` TRUE.

### U12 — The ruling the negation-as-failure spec left open

**The question.** `NEGATION-AS-FAILURE-SPEC.md` open question 2, whether `kand`/`kor`/`knot` ship as a library.
**RULED 2026-10-01.** Meng marked `accept` on bench card U12 at 10:16:54Z, with no note. The ruling, as printed on the card: Decline the library if LIMBO and CLICKER are accepted. Record in `NEGATION-AS-FAILURE-SPEC.md` that this reverses its leaning, and that a data-borne `NOTHING` still needs `CONSIDER` (the library can be revisited if that demand appears). Update `negation-as-failure.md:60-63` in the same change, and move the experiment under a checked glob so it cannot rot.
Its condition is met: U1 and U7 are both accepted. The answer is recorded in `specs/done/NEGATION-AS-FAILURE-SPEC.md` as well. **AMENDED 2026-10-01**, by bench card U12b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: Label `jl4/experiments/negation-as-failure-examples.l4` and both doc pages as "truth-functional strong Kleene (#526 §4.1(a))", not as the lift, everywhere the word "lift" refers to it (file `:79-85`, NAF spec `:3`, `:5`, `:23`, #526 §3.1). Add `#ASSERT (NOTHING `kor` (knot NOTHING)) EQUALS NOTHING` with a comment that the residual evaluator decides `x OR NOT x` TRUE at the boundary. Move the file under a checked glob; turn both doc links into relative links to the new path, and update the citations (NAF spec `:5`, `:274`; #526 §3.1; the file's own line 2). The recorded condition now reads as met, U1 and U7 being accepted.

---

## 10. What this spec did not verify

- The service behaviour in §2.5 was measured by the coordinating session, not here; the cause of the section-`GIVEN` prelude failure is unexplained.
- §4.4's claim that Step 0 moves only the trace golden, the service reasoning tree and jl4-mlir's trace parity is a prediction from `grep` and from reading the code; trace output from the LSP was not checked.
- The `#EVALTRACE` probes printed "no trace captured" on the installed binary, so the trace shape in §2.4 is read from a committed golden, not reproduced.
- §3.3's statement that two calls to one function share one planner atom follows from the atom being keyed by `nm.unique`; whether `nm` is the callee or the call was not checked, and it is outside this spec.
- Nothing in §4–§8 has been built or timed.
- `TYPICALLY-ONE-BEHAVIOUR-SPEC.md`, which U8 and U9 cite for their full text, is on branch `spec/typically-unify` (worktree `l4wt/typically-unify`, read at `b10f65203`) and not on this branch or on `unstable`; whichever of the two specs merges second must carry the cross-reference.
- Two `TYPICALLY` probe results are recorded in §4.11 row 53 and not explained here: a section `GIVEN … TYPICALLY TRUE` read directly by a `#EVAL` in its own section is stuck on the input (probes `p14-typically.l4`, `p18-typ-single.l4`), while the same input read through a rule in the section takes its default (probe `p19-typ-rule.l4`); the census in `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` §2 records the second case as "honoured". The cause was not traced.
- The literature attributions in §4.10 (Kleene 1952, McCarthy, King 1976, van Fraassen 1966, Jones, Gomard and Sestoft 1993) are from memory of the standard references and were not re-read today.
- Whether `verdict.test.ts` already carries an `IMPLIES` case, which U10b extends, was not checked.
- The guard-idiom count: one line-level `grep` over the 809 `.l4` files under `jl4/examples`, `jl4-core/libraries` and `doc` found no `isJust`/`isNothing` guard and no `AND … DIVIDED` on one line, and five lines with a non-zero guard before an `AND`; a guard split across lines is invisible to it.
  Left-sequential evaluation (U1) preserves every such guard whether or not it was found, which is why the count is not load-bearing.
