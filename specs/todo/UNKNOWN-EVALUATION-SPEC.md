# Specification: Evaluating with unknowns — connectives as an algebra, not as `IF`

**Status:** proposed (2026-10-01); build step 1 of §8 is built (2026-10-02), its two regulative sites under LOUDHAILER and the rest in the change that wrote this line; build step 2 is built (2026-10-03).
Nothing else in this document is in the tree.
§4, which defines the evaluation once, was added on 2026-10-01 after the rulings of §9 were made; §5 to §8 were restated against it the same day, and §4.11 (the correspondence with the established designs) and D1 were added later that day; the seven rulings of the bench "Symbolic Evaluation Conflicts" on §4.13 were recorded in §9 and applied to §4 the same evening.
Every statement about today's behaviour is a probe result or a `file:line` read on `unstable` at `f9a504b77`, and says which.
Probes for §2 ran on the installed `l4` (`~/.cabal/bin/l4`, a store build linked 2026-09-30; the only evaluator-path commit after 2026-09-26 is `8848df744`, `WHOSE`, which touches none of the code cited here); probes for §4.12 ran on a snapshot of the `unstable` binary built from `f9a504b77`.
Probe files are in the session scratchpad, not in the tree.
On 2026-10-02 the Track B audit, fifteen agents asking whether the recorded rulings suffice to build §8's seven steps, was applied under TIPPEX, and its one open semantic question, M1, was ruled as U13 under RAINCHECK (M2 to M4, outward actions and a `CLAUDE.md` edit, are left to Meng in §8) and amended the same day as U13b under YOYO.
The questions that three reviews of that work and a verification of the fixes raised for Meng, and the choices made overnight to keep build steps 1 to 3 buildable, are listed in §9's "Open for Meng (raised 2026-10-02)".
Citations added that day were read on `unstable` at `6ed297629`, where no file under `jl4-core/src`, `jl4/app`, `jl4-service/src`, `jl4-lsp/src` or `jl4-mlir` differs from `f9a504b77` (`git diff --stat`, empty); probes added that day (`t01` to `t27`, `vf/s1` to `s6`, and the TIPPEX fact-check's `c01` to `e04`, re-run) ran on a byte-identical snapshot of the installed `l4`, the store build `jl4-0.1-b69f17a4`, built 2026-09-28.

**Trigger:** SCHRODINGER, widened by Meng on 2026-10-01: _"continue your investigation of the evaluator lift with kand. It sounds like we'll need to redo the rewriting-to-IF in favour of something more algebraically principled."_
§4 was added under REVERSEGEAR, fired by Meng the same day on the observation _"We seem to be backing our way into symbolic evaluation by fits and starts."_

**Related:** `specs/done/NEGATION-AS-FAILURE-SPEC.md` (`DefBool`, `kand`/`kor`/`knot`), `specs/done/BOOLEAN-MINIMIZATION-SPEC.md` (whose Phase 1 proposed this and was never built, §3.2), `specs/todo/RUNTIME-INPUT-STATE-SPEC.md` (the four-cell input model), `specs/todo/ladder-diagrams-2026/DESIGN.md` §22, §23, §25f, `specs/todo/IMPLICIT-PROPS-DESIGN.md` §11.5 (R8, `TYPICALLY` at the root), `specs/todo/TYPICALLY-DEFAULTS-SPEC.md`.

---

## 1. The problem in one paragraph

An investigator, a caseworker or a wizard holds a case with most facts not yet established.
For them "not yet known" is a third answer, and a rule that reaches it should say _undetermined_, naming what it is waiting for, and never _no_.
L4 has that third answer in four places that do not share an implementation: a user-level library pattern, a TypeScript evaluator inside the ladder visualizer, a decision-diagram planner over the ladder's static expression tree, and a lifecycle algebra for regulative `RAND`/`ROR`.
The one place it does not have it is the evaluator that `l4 run`, `#EVAL`, `l4 batch` and the service all share.
There, an unknown fact is an exception that aborts the directive, except at a few sites that pass over it silently (§2.4), and whether you reach it depends on which side of an `AND` the fact was written on.

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
Most sites that inspect one raise `Stuck name` (`stuckOnAssumed`, `Machine.hs:835-836`):
`IF` (`:1634`), application of an assumed function (`:1593-1594`, carrying `-- TODO: we can do better here`), `expectNumber` / `expectString` / `expectDateValue` (`:4120`, `:4126`, `:4133`), every binary operator (`runBinOp`, `:5018-5019`), and equality (`runBinOpEquals`, `:5046`), for its left operand only.
Outside the regulative frames (§2.4), five sites do not.
An unknown on the right of `EQUALS` is misdiagnosed: `3 EQUALS n` reports "Trying to check equality on types that do not support it", while `n EQUALS 3` names `n` (probe, `f9a504b77`).
A `CONSIDER` has no arm for it, so the unknown fails the pattern and the match moves on to the next branch: an exhaustive `CONSIDER` misreports it as a missing branch, and a catch-all after a refutable pattern is taken silently (§2.4).
`AS STRING` and `TOSTRING` raise a user error that blames the value's type, "AS STRING/TOSTRING can only convert NUMBER, BOOLEAN, DATE, TIME, DATETIME, or STRING to STRING, but found: n" (`coerceToString`, `Machine.hs:4525-4555`, the error at `:4552-4554`; probe `t04`).
`JSONENCODE` reports an internal error, "Cannot encode value to JSON: n … Please report this as a bug" (its arm, `:4593`, reaches the catch-all of `encodeValueToJson`, `:4220`; probe `t05`).
The four temporal iterators, `EVER BETWEEN`, `ALWAYS BETWEEN`, `WHEN LAST` and `WHEN NEXT`, report "… expects predicate returning BOOLEAN" when the predicate returns an unknown (`:1771-1772`, `:1786-1787`, `:1803-1804`, `:1820-1821`; probes `c01`, `c02`).

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

**`CONSIDER` on an unknown misreports it as a missing branch, or takes a catch-all silently.**
`CONSIDER m WHEN NOTHING THEN 1, WHEN JUST y THEN 2`, with `m IS A MAYBE NUMBER` an unsupplied section `GIVEN` (probe `q4.l4`), returns:

```
The value
  m
reached a CONSIDER that has no branch for it.
Add a WHEN branch for this case, or a catch-all OTHERWISE branch.
```

The `CONSIDER` is exhaustive.
The value is unknown, and the message sends the reader to fix code that is not broken.
That case fails loudly, so it does not return a wrong answer, but it misdirects.
A `CONSIDER` with a catch-all does return a wrong answer.
`CONSIDER m WHEN JUST y THEN 2, OTHERWISE 1` prints `1`, and `CONSIDER x WHEN TRUE THEN 1, OTHERWISE 2` prints `2`, each as a value with exit 0 (probe by the coordinating session on 2026-10-02, on a snapshot of the installed `l4`, with `ASSUME m IS A MAYBE NUMBER` and `ASSUME x IS A BOOLEAN`; the first again with a section `GIVEN`, probe `t02`).
The unknown fails the first pattern and the catch-all accepts it, so the result is one the facts do not support.
It is a defect in two-valued mode, independent of everything below.
The fall-through is in the backward pattern frames `PatNil0`, `PatCons0` and `PatApp0` (`Machine.hs`, the `backward` arms of those names), which have no `ValAssumed` arm and call `patternMatchFailure`; `matchPattern` only pushes frames, these and the literal-pattern ones, and binds a variable pattern directly.
A literal pattern goes through `PatLit1` to `runBinOpEquals` with the scrutinee on the right, so it gets the right-operand misdiagnosis of §2.2 instead.
A sub-pattern fails the same way, so an unknown inside a known value reaches the next branch too: with `DECLARE Kind IS ONE OF Retail, Wholesale`, `DECLARE Claim HAS kind IS A Kind, amount IS A NUMBER` and `k` an unsupplied `Kind`, `CONSIDER Claim k 5 WHEN Claim Retail 0 THEN "first" WHEN Claim kk a THEN "second"` prints `"second"` (probe `t01`), which is right for every `k` only because `5` is not `0`.

**The `IF` rewrite leaks into user-visible traces.**
`jl4/examples/ok/tests/lazytrace-exception.golden:15-16` shows the trace of `FALSE OR TRUE` as `IF a THEN TRUE ELSE b`, and `:56`, `:60`, `:65` and `:70` show `x AND (and OF xs)` as `IF a THEN b ELSE FALSE`.
`a` and `b` are the built-ins' own parameter names.
That is the only committed golden that carries one of the four shapes (`grep -rlF` over every `*.golden`), on about twenty lines once each `IF`'s child lines are counted.
The service's reasoning tree (`traceToReasoning`, `jl4-service/src/Backend/Jl4.hs`) carries the same sub-tree, and jl4-mlir reproduces it on purpose for trace parity with the service (`jl4-mlir/runtime/jl4-runtime.mjs:3512-3521`, `:3718-3745`; parity harness `jl4-mlir/scripts/parity-harness.mjs`, whose trace sub-matrix is recorded at `:444-484` and printed, as "not a gate", at `:556-571`; the corpus CI runs it on is listed at `.github/workflows/pr-checks.yml:2083-2092`).
A reader of that trace sees a conditional they never wrote, with variable names that are not theirs.

**A field read on an unknown record misreports the same way.**
`d's age`, with `d IS A Person` an unsupplied section `GIVEN`, returns the same no-branch message (probe `p05-record.l4`, on the `f9a504b77` snapshot), because the generated selector is a closure whose body is a one-branch `CONSIDER` on its argument (`Machine.hs:5727-5743`).
So every field path on an unknown record is misdiagnosed, not only a `CONSIDER` the author wrote, and `d's age AT LEAST 18` never reaches the comparison.

**A bare unknown as the result of an `#EVAL` is reported as a value.**
`#EVAL TRUE AND x`, `#EVAL TRUE IMPLIES x` and `#EVAL x` each print `x` as if it were a value, with JSON `"kind":"value"`, `"ok":true` and exit 0 (probes `p11-implies.l4`, `p17-bare.l4`).
`#ASSERT` on the same expression is reported as `Stuck`, because only the assertion arm handles a `ValAssumed` result (`EvaluateLazy.hs:306`).
`#ASSERT REFUSED x` reports "assertion failed: expected a refusal, but the expression produced a value" (the arm's wildcard, `EvaluateLazy.hs:319`; probe `t03`), which `l4 run` does not count as a crash (`Run.hs:156`).
That verdict is right, because an input is a value in every completion and never refuses; only the wording "produced a value" could be better (decided by Claude overnight 2026-10-02, pending Meng's review; §8 step 1).
This, the catch-all `CONSIDER` above and the two regulative sites below are the paths found so far in two-valued mode where an unknown is silent; this one is the shape §2.5 finds again on the service.

**Residue in the regulative frames.**
`PROVIDED` and `EVERY`'s `WHO` filter take the value of a user expression and have no `ValAssumed` arm, so an unknown there is reported as an internal "expected BOOLEAN" error (`Machine.hs`, the wildcard arms of `Contract10` and `QuantFilter`; read, not probed).
Two regulative sites pass over an unknown silently.
`EVERY`'s cast test drops an unknown candidate, because it admits only a value built by the named constructor and reads anything else as `FALSE` (`QuantCast`): `EVERY Tenant t IN LIST alice, u`, with `u` an unsupplied `Actor` and `alice` signing, is `FULFILLED`, exit 0 (probe `d01`), where a known second tenant leaves that tenant's obligation pending (`d02`) and the same roll with no cast is `Stuck` on `u` (`d03`).
The action matcher shares the pattern frames above (its `continuePattern` in `Contract8`), so an event whose action holds an unknown fails the pattern and the matcher tries the next event (the `Contract11` arm of `patternMatchFailure`): `PARTY alice MUST Deliver Retail` with the event `PARTY alice DOES Deliver k`, `k` an unsupplied `Kind`, is left pending, exit 0 (`e03`), where `Deliver Retail` is `FULFILLED` (`e04`).
The matcher's party check calls `runBinOpEquals party val` with the event's party on the right (`Contract7`).
§4.6 puts the regulative algebra out of scope; §8 step 1 says what that step does and does not change here.

### 2.5 The service: one silent path, and it is the investigator's

This subsection is as measured at `f9a504b77`; W1 (#530, merged 2026-10-01) has since replaced `fromMaybe FALSE` with an assumed term (§6), and the `TYPICALLY` spec records the silent `FALSE` as fixed (`TYPICALLY-ONE-BEHAVIOUR-SPEC.md:95`).

The direct path refuses a missing or `null` value for a non-`MAYBE` parameter (`jl4-service/src/Backend/Jl4.hs:447-450`, read).
`{}`, which the wire calls `FnUncertain` (`Backend/Api.hs:74`), cannot be expressed on that path, so it is sent to the generated-wrapper path (`Jl4.hs:527-535`).
There every boolean parameter is passed as `fromMaybe FALSE (args's x)` (`Backend/CodeGen.hs:239`, `:335`, `:603`).

Measured by the coordinating session on 2026-10-01 against a local `jl4-service` built from `f9a504b77`, with the rule `GIVEN has capacity IS A BOOLEAN TYPICALLY TRUE, is adult IS A BOOLEAN`:

- absent, or `null`: refused, "missing required parameter". Loud.
  On `/evaluation` a JSON `null` is read as an absent argument, since `fnArguments` is a `Map Text (Maybe FnLiteral)` (`Backend/Api.hs:123`); only a `null` nested inside a value parses as `FnUnknown` (`:71`), which `requiresWrapperEvaluation` sends to the wrapper path (`Jl4.hs:527-535`).
- `{}` on either input: `{"result":{"value":false}}`, a plain response with no diagnostic, the `TYPICALLY TRUE` ignored.
- `{}` on a section `GIVEN` boolean: fails loudly, the generated wrapper calls `fromMaybe` without importing the prelude ("could not find a definition for fromMaybe").
  The `TYPICALLY` work traced the cause on 2026-10-01 (`TYPICALLY-ONE-BEHAVIOUR-SPEC.md` L6, `:109`, as merged with #530): the wrapper is appended after the source, so it lands inside the source's last `§` section, where an `IMPORT` does not resolve.
  W1 removes the import, and #530, which builds W1, merged on 2026-10-01 (`6d3a56f75`).

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

`DefBool` is `MAYBE BOOLEAN`, and `kand`, `kor`, `knot` are truth-functional strong Kleene over it, reading (a) of §4.1, written in L4 (`jl4/examples/ok/negation-as-failure-examples.l4:92-138`, moved from `jl4/experiments/` and labelled so by build step 1, as U12b asks).
All 16 `#ASSERT`s in that file pass, U12b's included (`l4 run --json` on build step 1's binary, 16 of 16 `"value":true`).
The shipped library carries only the three eliminators `holds`, `naf`, `presumed` (`jl4-core/libraries/negation-as-failure.l4`), each of which collapses `NOTHING` to a constant.
The spec's open question 2, whether the lift ships, is answered by U12 (§9).

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
For a call whose arguments are all `BOOLEAN`, which the ladder draws as an application, that `nm.unique` is a fresh ladder node id (`jl4-lsp/src/LSP/L4/Viz/Ladder.hs:425-432`, `uniq = vid.id`), and any other call, a comparison among them, is a leaf with a fresh id of its own (`leafFromExpr`, `:497-501`), so two calls to one function are two atoms either way.
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
Where this section and a ruling's own words pull apart, §4.13 lists it with the evidence and does not resolve it.
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
          | error [c] e        a guarded error leaf of any type, as in an IF arm (U4b, U11b)
          | refuses [c] r      a guarded refusal leaf of any type, as in YMD's else arm, which is a DATE (U13)
          | gave-up [c]        the evaluation under the pending condition c ran out of steps (§4.5)
          | t with l1, …, ln   a term or a determined value carrying guarded leaves, as an agreeing-arms result does (U13b, DU11)

Boolean term (a residual)
      b ::= TRUE | FALSE
          | ?i                 an input atom, i a BOOLEAN input
          | t1 cmp t2          a comparison atom, keyed by its evaluated term (§4.6)
          | g (a1, …, an)      a Boolean call to an assumed function, keyed the same way
          | fresh              an atom for an unknown that carries no key (§4.6)
          | IS INTEGER t       a built-in predicate over a term, keyed like a comparison; it spells MODULO's guard (C1, §4.6)
          | defined (t1 ^ t2)  the guard of TO THE POWER OF, which no comparison spells (C1, §4.6)
          | NOT b | b AND b | b OR b | b IMPLIES b
          | c ? b1 : b2        a Boolean join, which is (c AND b1) OR (NOT c AND b2) once built
          | error [c] e        a guarded error leaf: the error e, raised only if the path condition c is TRUE (U11, U11b)
          | refuses [c] r      a guarded refusal leaf: the REFUSE r, raised only if c is TRUE; distinct from an error leaf (U13)
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

**The term language is kept close to SMT-LIB2.**
That is the hedge D1 (§9) makes part of its ruling: the solver is bought for the planner and `l4 prove` (DU3b), and the lowering from this language to SMT-LIB2 is the one `l4 prove` already specified, so swapping z3 for cvc5 later, or adding a solver-aided tool, is a change to the lowering and not to the evaluator.
The correspondence, with R-V7's encodings (`VERIFICATION-BACKEND-LOWERING-SPEC.md:398-437`, as numbered on this branch):

| term                                         | SMT-LIB2                                                                                               |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `?i` of `BOOLEAN`, `NUMBER`, `DATE`          | `declare-const` of `Bool`, `Real` (L4 numbers are exact rationals), `Int` (the day serial)             |
| `?i` of a `STRING` or a bodiless `DECLARE T` | `declare-const` of an uninterpreted sort, equality only                                                |
| `?i` of an enumeration, record or `MAYBE`    | `declare-const` of the SMT datatype R-V7 gives the type                                                |
| `t 's f`                                     | the datatype selector applied to `t`                                                                   |
| `g (a1, …, an)`                              | a `declare-fun` of `g`'s declared type, applied                                                        |
| `op (a1, …, an)`                             | the theory operation, with R-V7's exact `ROUND` and `MODULO`; `LN`, `SQRT` and `^` are refused by name |
| `c ? t1 : t2`                                | `ite`                                                                                                  |
| `t1 cmp t2`, `b1 EQUALS b2`                  | the theory predicate                                                                                   |
| `NOT`, `AND`, `OR`, `IMPLIES`                | `not`, `and`, `or`, `=>`; `IMPLIES` has its own symbol, so the seam survives the lowering              |
| `fresh`                                      | a `declare-const` used once; after C1 only a `CONSIDER` on a term and an excluded-type equality (§4.6) |
| `IS INTEGER t`                               | `is_int` applied to `t`                                                                                |
| `defined (t1 ^ t2)`                          | out of fragment, as R-V7 refuses `^` by name                                                           |
| `error [c] e`, `gave-up [c]`                 | not a term: the guard `c` is a side condition, carried next to the residual (§4.7.3)                   |
| `refuses [c] r`                              | not a term either: its guard is a side condition in the same way (U13)                                 |
| a `CONSIDER` on a term                       | no node yet (U4), so `unknown (out of fragment)` in R-V8's words                                       |

### 4.3 The evaluation rule, and why it is conservative

**The rule.**
At every site that raises `Stuck` once build step 1 has landed (§2.2, §8), and in the four built-in connectives, when every operand the site needs is determined, evaluate exactly as today.
When an operand is a term, build the term node for that site instead of raising:

| site today (§2.2)                                                                           | with a term operand                                                                                                                              |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `AND`, `OR`, `IMPLIES`, `NOT` (`Machine.hs:6636-6715`)                                      | the connective table below                                                                                                                       |
| `IF` (`:1634`), `BRANCH` (`:1323-1327`)                                                     | a join, §4.5                                                                                                                                     |
| `CONSIDER` on a term scrutinee (the pattern frames `PatNil0`, `PatCons0`, `PatApp0`)        | a `fresh` unknown of the result type, naming the scrutinee (U4); never "no branch"                                                               |
| a selector applied to a term (`:5727-5743`)                                                 | the field-path term                                                                                                                              |
| an assumed function applied (`:1593-1594`)                                                  | the application term; an atom if its result type is `BOOLEAN`                                                                                    |
| `expectNumber`, `expectString`, `expectDateValue` (`:4120-4133`), `runBinOp` (`:5018-5019`) | the operation term; a comparison atom if the operation is a comparison; a partial built-in also emits its definedness guard as a leaf (C1), §4.6 |
| `runBinOpEquals` (`:5046`)                                                                  | the identity rule, then a comparison atom, §4.6                                                                                                  |
| `AS STRING`, `TOSTRING` (`coerceToString`, `:4525-4555`), `JSONENCODE` (`:4593`)            | no term node: `Stuck` naming the term's inputs (assumed, not ruled; §8 steps 1 and 3)                                                            |
| a term as the result of a directive (`EvaluateLazy.hs:306`)                                 | the report, §4.7                                                                                                                                 |

Until build step 5 builds joins and the rule for `CONSIDER` on a term, `IF`, `BRANCH` and `CONSIDER` on a term raise `Stuck` naming the term's inputs, as `AS STRING`, `TOSTRING` and `JSONENCODE` do at every step (step 3's interims, §8).

The connective table, for `AND`; `OR` is dual, and `IMPLIES` and `NOT` build their node whenever the operand is a term:

| left     | right         | result                                                                 |
| -------- | ------------- | ---------------------------------------------------------------------- |
| `FALSE`  | not evaluated | `FALSE` (as today)                                                     |
| `TRUE`   | `r`           | `r` (as today)                                                         |
| term `p` | `FALSE`       | `FALSE`, unless `p` contains a guarded leaf: then `p AND FALSE` (U11b) |
| term `p` | `TRUE`        | `p`                                                                    |
| term `p` | term `q`      | `p AND q`                                                              |
| term `p` | error `e`     | `p AND error [p] e`: the error becomes a leaf guarded by `p` (U11)     |
| term `p` | refusal `r`   | `p AND refuses [p] r`: a leaf guarded by `p` (U13)                     |
| term `p` | ⊥             | the step counter, §4.5                                                 |

The last three rows need the leaves of §4.5, which build step 5 builds; step 3 carries the counter, with a limit measured on its own branch (§7).
Until then, an error, a refusal or running out of steps in the right operand under a term on the left is re-raised as `Stuck` naming the left's inputs, which is today's answer for those directives except that it names every input of the left, as U7b's default report does, where today's names only the first it reaches (U13's interim for a refusal; assumed, not ruled, for the other two; §8 step 3).
`IMPLIES` with a term `p` on the left takes the same three rows, guarded by `p`, because the two-valued run reaches its right operand only where `p` holds; `OR`'s guard is `NOT p` (row 22).
Nothing inside the evaluator decides a residual beyond these tables, the identity rule of §4.6 and the agreeing-arms rule of §4.5.
In particular no tautology is recognised mid-evaluation (U3): `IF (x OR NOT x) THEN 1 ELSE 2` builds the join `(x OR NOT x) ? 1 : 2`.

**Boolean consumers outside the table.**
From build step 3 a residual can reach three frames that never see an unknown today, because they are fed only by `runBinOpEquals`, which has always raised first: structural equality (`EqConstructor3`, `Machine.hs:1720-1730`), a literal pattern (`PatLit2`, `:1707-1713`) and the regulative party check (`Contract8`, `:2261-2280`).
Three more take the value of a user expression, so a bare unknown reaches them today and is misreported (§2.2, §2.4), and a residual would reach them too: the four temporal iterators (`:1758-1821`), `PROVIDED` and `EVERY`'s `WHO` filter.
Without a rule of its own, each would answer a residual with an internal error, or with a message that blames the predicate's type.
§8 step 3 states what each does instead, as an assumption.

**Every evaluation is lifted (U7b).**
There is no evaluation mode and no flag.
`l4 run`, `#EVAL`, `#ASSERT`, `l4 batch`, the service, the language server and the golden harness all run this rule; what differs between them is only the report of §4.7.

**Why it is conservative, and against which tree.**
The claim is made against the tree as it stands after build step 1, not against today's.
Step 1 deliberately changes four kinds of directive that end today in a value, each into `Stuck`: a catch-all `CONSIDER` taken on an unknown (§2.4, row 70), `#EVAL x` printed as a value with exit 0 (row 52), `EVERY`'s cast test dropping an unknown candidate (row 86) and the action matcher passing over an event with an unknown in its action (row 87); the last two are decided by Claude overnight 2026-10-02, pending Meng's review (§8 step 1).
It also turns several misleading errors into `Stuck`, and those directives fail loudly before and after: the right-operand error of `EQUALS` (rows 12, 48), the no-branch message of an exhaustive `CONSIDER` and of a selector (rows 34, 35), the coercions `AS STRING`, `TOSTRING` and `JSONENCODE` (rows 83, 84), the temporal iterators' message (§2.2), and the regulative party check (§8 step 1).
Two cases it leaves as they are, both decided by Claude overnight 2026-10-02, pending Meng's review: `#ASSERT REFUSED x` stays "failed", exit 0 (row 72), and a sub-pattern match that is right by luck stays right, because the matcher checks already-evaluated or literal later positions for a definite mismatch before it raises (row 71; §8 step 1).
Against the tree after step 1: for every directive that does not end in `Stuck`, the lifted evaluator returns the same value, raises the same error, or fails to terminate, exactly as before.
The lift adds transitions only at the sites in the table above, each of which raises `Stuck` once step 1 has landed, and `Stuck` cannot be caught in L4 and aborts the whole directive (`Machine.hs:699-704`, `:724-728`).
So a run that never reaches one of those sites with a term takes the same transitions as before, and a run that does reach one ended in `Stuck`.
The left-to-right order is what makes this hold for the connectives themselves: when the left operand is known, the frame does what the `IF` did, including not evaluating the right operand when the left decides.
That is also why the connectives do not commute in the presence of errors, which was the answer to Meng's note on U1: `FALSE AND (1 DIVIDED BY 0 GREATER THAN 0)` is `FALSE` and `(1 DIVIDED BY 0 GREATER THAN 0) AND FALSE` raises, today and after (probe `p03-commute.l4`), and the symmetric answer would change a fully supplied directive.
The step counter of §4.5 starts the first time a site in that table receives a term operand, which is the first point at which the two-valued run after step 1 would have raised `Stuck`; an input that is only read or passed along does not start it, so `#EVAL LIST n, total` prints `LIST n, 6` as today and no directive that works after step 1 can run out of steps (C4, read against the tree after step 1; §9 U4).

Where the lift changes a stuck directive for the worse, it is loud: a directive stuck on the left of an `AND` may now evaluate a right operand that errors or refuses, and U11 and U13 keep that error or refusal as a guarded leaf next to the unknown rather than in place of it.

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
What the trace keeps: today a variable operand's value appears only as the `IF`'s `a` or `b` leaf (`lazytrace-exception.golden:57-58`, `:61-62`), so each connective node gets a child per operand labelled with the operand's own source text and its value, such as `x` then `TRUE` (decided by Claude overnight 2026-10-02, pending Meng's review).
An operand the connective skips is drawn as skipped, under its source text, where a renderer draws what was not evaluated, which is GraphViz with `showUnevaluated` on, and is left out of a text trace and of the service's reasoning, as the `IF`'s untaken arm was (decided by Claude overnight 2026-10-03, pending Meng's review).
U2b allows this: it bans naming the built-ins' parameters `a` and `b`, not showing the operands.
§8 step 2 states the other assumptions a builder needs: how the frames force their operands, the trace shape, and jl4-mlir's missing `IMPLIES` lowering.

### 4.5 Conditionals and the step counter (U4, U4b, U11)

**A join.**
`IF c THEN t ELSE e` with `c` a term evaluates both arms and builds the join `c ? t : e`.
If both arms are the same determined value, by the equality `runBinOpEquals` already supports, the result is that value: `IF x THEN 1 ELSE 1` is `1`, and `IF x THEN TRUE ELSE TRUE` is `TRUE`.
That value first carries the join's guarded leaves, the condition's and each arm's, error, refusal and give-up alike (U13b, C3), as DU11 has a `CONSIDER` carry its scrutinee's; the arms are compared by value with their leaves set aside, which is sound because every leaf is carried (assumed, not ruled): `IF (x AND TBD) THEN 1 ELSE 1` is "1 unless `x`; refuses (TBD: this rule has not been written yet) if `x`", exit 1 (row 78).
If the arms are Boolean, the join is the residual `(c AND t) OR (NOT c AND e)`, so `IF x THEN y ELSE FALSE` is `x AND y`.
Otherwise the join is kept as a term, and a strict built-in that returns a `BOOLEAN` applied to it is pushed into each arm (U4b): `(IF x THEN 1 ELSE 2) GREATER THAN 1` is `x ? FALSE : TRUE`, which is `NOT x`.
At a result, in a field, or under any consumer that is not such an operation, the join is an opaque unknown whose atom set is the union of the condition's and both arms' (U3, U4b).
`BRANCH` is a chain of `IF`s and inherits all of this: a guard after an unknown one is reached and evaluated.
An error in one arm is an `error [c] e` leaf, one mechanism with the connective case (U4b, U11b): `IF x THEN 1 DIVIDED BY 0 ELSE 2` is `x ? error [x] : 2`.
At a result that join is U4b's opaque unknown, so it is reported as undetermined naming `x`, with its guard, "errors if `x`", since U4b's guarded error "always appears in the response with its guard"; it is not "2 unless `x`", which would settle a non-Boolean result against U4b and §4.7.2 (row 29).
A `REFUSE` reached in an arm under a term condition is a guarded refusal leaf in the same way (U13): `IF x THEN TBD ELSE FALSE` is "`FALSE` unless `x`; refuses (TBD: this rule has not been written yet) if `x`" (row 74).

**`CONSIDER` on a term scrutinee stays unknown for now** (U4): the result is a `fresh` unknown of the result type, naming the scrutinee, and never the no-branch message of §2.4; it carries the scrutinee's guarded leaves into its result (DU11).
Its arms are not evaluated, so an arm that errors or refuses leaves no leaf, and whether `AND FALSE` or `OR TRUE` may then absorb that `fresh` atom is pending the open question in §9 (O6).
The disjunction over arms that an earlier draft proposed needs atoms of the form `s = C` under an exactly-one constraint, and is not ruled.

**The step counter.**
Evaluating both arms is the half of this design that can blow up: nested conditionals on one unknown evaluate a tree of arms, and a recursion whose guard reads an unknown never reaches a base case.
So every evaluation runs under a cumulative counter of machine steps, with a limit set from §7's item 3 (U4), measured on the branch of each step that brings or changes the counter, step 3 and then step 5, and set before that branch merges (§7).
It starts the first time a site in §4.3's table receives a term operand, which is a site that raises `Stuck` (after build step 1), and not when an input is read or passed along (C4): `#EVAL LIST n, total` builds a list holding an input, starts nothing, and prints `LIST n, 6` as today.
It resets per directive, per batch row and per service request (C4).
It counts steps, not depth: the existing cap is on frame depth only (`maximumFrameDepth`, `Exceptions.hs:159`, checked in `pushFrame`, `Machine.hs:857`), and arms run one after another, so depth cannot see a join's blow-up.
**Running out of steps** unwinds as today's exceptions do, restoring every thunk it passes (`restoreThunkOnUnwind`, `Machine.hs:818`), and becomes **`gave-up [c]`** at the join or connective that catches it, so no thunk ever caches a give-up (C4); `c` is the path condition that frame was working under: the conjunction of the term conditions whose unknownness caused the evaluation in progress, innermost last.
That mechanism alone does not give C4's "no thunk ever caches a give-up": a thunk whose body contains the catching join is still written back (`UpdateThunk`'s backward arm, `Machine.hs:1919`), and an imported module's thunks outlive the directive (its base environment is "allocated once", `EvaluateLazy.hs:816`), so `UpdateThunk` must also decline to write back a value that carries a `gave-up` (assumed, not ruled; §8 step 5).
Once the counter has run out nothing new is evaluated: every pending operand and arm becomes `gave-up` under its own path condition, and the values already computed combine with the leaves by the tables (C3).
Row 59 is reachable only if "nothing new" is read as "no closure body is entered": literals, constructors, already-evaluated thunks and built-in operations still compute; that reading is pending the open question in §9 (O3).
Read literally, it turns every operand of row 59 still pending into a leaf, so every assignment meets some guard and the report would be a bare "gave up" (traced by hand in the Track B audit, in either arm order).
A strict operation, a comparison, an arithmetic operation or a selector, applied to a `gave-up` returns the leaf with its guard, never a `fresh` atom (C3).
It is reported as "gave up; needed _i_" for the inputs in `c` (U11), and it is never a `StackOverflow`.
When no join or connective is there to catch it, the directive boundary does, as `gave-up [TRUE]`, naming every input that reached a §4.3 site in that directive (assumed, not ruled; §8 step 5).
Recursion guarded by an `IF` over an unknown always runs out, and that is the ruled behaviour, not a defect: `countdown m` with `countdown n MEANS IF n GREATER THAN 0 THEN countdown (n MINUS 1) ELSE 0` gives up naming `m`.
A `gave-up` leaf is carried exactly as an error leaf is: it is never absorbed by `AND FALSE` or `OR TRUE`, because the evaluation it stands for might not terminate once the inputs are supplied, and a definite answer would promise what the two-valued run cannot keep (C3).
So `(loop m GREATER THAN 0) AND FALSE`, with `loop n MEANS IF n GREATER THAN 0 THEN loop n ELSE 0`, is "`FALSE` unless `m GREATER THAN 0`; gave up if so", and never `FALSE`.
On §7's workload the limit must fire before the service's timeout and allocation cap (C4).

### 4.6 The membrane: comparisons, arithmetic, equality, and what an atom is (U5, U5b, U6, U6b)

The ladder's §23 drew the line: the circuit is Boolean, typed data lives inside a leaf, and a predicate is the membrane between them.
The evaluator draws it in the same place.
A comparison or a Boolean call over a term is an **atom** of the residual; arithmetic, string and date operations over a term are terms that are not atoms.

**An atom's key is its evaluated term**, never its source position: the operator, the normal forms of its determined operands, and its term operands as terms (U1, U5, U5b).
The key keeps operand order, so `3 EQUALS n` and `n EQUALS 3` are two atoms (assumed, not ruled): ordering the operands of a symmetric comparison would let the boundary decide more, and would be sound, but nothing needs it yet.
One source position is evaluated many times, in a helper called with different arguments, in an `IF` arm, in a prelude recursion, and keying by position would make `older 18 AND NOT older 65` the contradiction `A AND NOT A`, decided `FALSE` though age 30 makes it `TRUE`.
Keyed by term, `older 18 AND NOT older 65` is `age GREATER THAN 18 AND NOT age GREATER THAN 65`, two atoms, undetermined; and `older 18 AND NOT older 18` is one atom twice, `FALSE` at the boundary.
The soundness claim of §4.7 is conditional on this key.

**Which terms carry a key, and which are askable.**
Every term is keyed by its structure (C1, amending U5b, U6 and U6b): an input, a field path, a built-in operation over terms, a join, an assumed call, and a comparison over any of these.
Two occurrences of `n PLUS 1` are one unknown, so `n PLUS 1 GREATER THAN 3 AND NOT (n PLUS 1 GREATER THAN 3)` is `FALSE` at the boundary, and `n PLUS 1 EQUALS n PLUS 1` is `TRUE` by the identity rule below.
Sharing is sound, one term one value, only for total operations, so a partial built-in applied to a term emits its definedness guard as a U11b leaf before the term is shared or compared, as R-V2 does for `l4 prove` (C1): `DIVIDED BY` guards a zero divisor (`Machine.hs:4940-4943`), `MODULO` a non-whole operand or a zero divisor (`:4944-4949`, `expectInteger` `:4136-4140`), and `TO THE POWER OF` a non-finite result (`:4950-4954`).
C1 names three; `LN`, `LOG10`, `ASIN`, `ACOS` and `SQRT` also raise on part of their domain (`Machine.hs:4846-4875`), and are read as partial in the same sense (assumed, not ruled: C1's list read as examples of its principle).
Each guard is spelled as an atom (assumed, not ruled): a zero divisor as `d EQUALS 0`; `MODULO`'s non-whole operand as `NOT (IS INTEGER a)`; `LN` and `LOG10` as `a AT MOST 0`, `ASIN` and `ACOS` as `a LESS THAN -1 OR a GREATER THAN 1`, and `SQRT` as `a LESS THAN 0`, which are the conditions the machine raises on (`Machine.hs:4846-4875`); and `TO THE POWER OF`'s non-finite result, which no comparison spells, as `NOT defined (a ^ b)`, an atom keyed by its term (§4.2).
Until build step 5 can emit the guard, a partial built-in applied to a term stays `Stuck` and is never shared (§8 step 3).
So `(1 DIVIDED BY n) EQUALS (1 DIVIDED BY n)` is "`TRUE` unless `n EQUALS 0`; errors if `n EQUALS 0`".
Only two things are `fresh`, sharing with nothing: a `CONSIDER` on a term, and an excluded-type equality (below) (C1, C3).
Askability is its own rule (C1): an atom is askable, and the planner matches an answer to it by its key, if and only if its term contains no built-in operation, no join and no non-Boolean assumed call; for any other atom the planner asks for the inputs it reads.
So `d's age AT LEAST 18` is askable, and `n PLUS 1 GREATER THAN 3` is not: the planner asks for `n`.

**The residual is propositional**, so two atoms over one number are independent to it: `n GREATER THAN 3 AND n LESS THAN 2` is undetermined, not `FALSE`, and `age >= 18 OR age < 18` is undetermined, not `TRUE`.
With atoms keyed by term, that can say "undetermined" where the truth is "no", never the reverse.
Arithmetic reasoning over these atoms belongs to a solver (§4.7.3), which the planner and `l4 prove` have and an evaluation's own boundary does not (DU3b); that is why an atom keeps its term and not only its key.

**Equality.**
`runBinOpEquals` gains an identity rule before anything else (U6, U6b, extended by C1): the same keyed term on both sides is `TRUE` when the term's declared type has no function or `CONTRACT` component anywhere inside it, with a type variable or an unsolved inference variable counting as excluded, and with any partial built-in in the term having emitted its guard first; so `x EQUALS x`, `d's age EQUALS d's age` and `n PLUS 1 EQUALS n PLUS 1` are `TRUE`.
That `TRUE` first carries the term's guarded leaves, error and refusal alike (U13b), as row 65's "`TRUE` unless `n EQUALS 0`" already does for C1's guard.
The unknown carries its declared type for this (`ValAssumed` gains the type `evalAssume` already has).
An excluded type stays unknown rather than becoming an error, except a bare function or `CONTRACT` type, which raises today's unsupported-equality error; so `elem g (LIST g)` with `g` an unknown function errors and never returns `TRUE`.
`typeHasFunctionComponent` is lifted out of the DMN exporter's `where` clause for this.
Over `BOOLEAN`, `b1 EQUALS b2` with a term operand is the biconditional `(b1 AND b2) OR (NOT b1 AND NOT b2)`, a connective rather than an atom, which is how `x EQUALS y AND x AND NOT y` reaches `FALSE` at the boundary.
Every other equality with a term operand is a comparison atom.
An equality between two determined values that hold terms, such as two lists, is not one: it compares their components as today, each by these rules, and combines the results with §4.3's `AND` table (§8 step 3).
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
The residual's **support** is the set of inputs whose atoms can change its value under that decision, its semantic support; where the decider's budget runs out, and before step 4 builds the decider, the inputs the residual reads, its syntactic support, stand in for it, which can name more inputs and never fewer (§8 step 4).
**Non-Boolean results are not settled** (U1b, the second gap): a join at the root is reported undetermined even when its condition is a tautology, so `IF (x OR NOT x) THEN 1 ELSE 2` reports "I needed to know `x`" and counts toward the trigger below.
**A guarded leaf is a hole, never a value**: a residual containing `error [c] e`, `refuses [c] r` or `gave-up [c]` is decided over the assignments in which no guard holds, and the report names the guards, as "FALSE unless `x`; errors if `x`" (U11b, U13).
That outcome is its own, on the wire, in the K3 report and in every consumer listed under 4 below.
If no assignment of the atoms escapes every guard, no assignment is left to decide over and both tests above would pass vacuously, so the directive is never `TRUE` or `FALSE` (U13b).
When every leaf is a refusal with one reason, the outcome is that refusal, exit 0, as for `IF x THEN TBD ELSE TBD` as a `BOOLEAN` (row 80), and whether the same holds for a join of any other type is pending the open question in §9 (O2); otherwise it is undetermined, listing each leaf, exit 1, as for `IF x THEN (1 DIVIDED BY 0 GREATER THAN 0) ELSE (2 DIVIDED BY 0 GREATER THAN 0)`.

How it is computed: by truth table over the residual's atoms, which needs no solver and so runs the same on every host (DU3b); this is what decides rows 14, 36 and 38 `FALSE`.
When every atom is a `BOOLEAN` input, the answer is also complete over the inputs; otherwise it can miss a decision that only the inputs' values force, which is the first gap above.
An enumeration does not count: an equality with a constructor is a comparison atom (§4.6), the atoms are independent (DU3b) and no exactly-one constraint is ruled (§4.5), so `c EQUALS Red OR c EQUALS Green` over a two-constructor `c` stays undetermined.
The table's work is bounded: when its budget runs out the residual is reported undetermined, which the argument above shows is sound, and the decider never hangs (assumed, not ruled; DU3b sets no size limit, and C4's counter bounds evaluation, not deciding; §8 step 4).
Every evaluation's boundary decision stays propositional, over every atom and on every host, so an answer never depends on whether z3 is installed (DU3b); z3 decides only for the planner and `l4 prove` (§4.7.3), and that is where the first gap closes.
Three counts are kept from build step 4 (U3b, DU3b): conditions whose residual is a tautology or a contradiction, reported as a lower bound, which stays U3's trigger for moving the diagram; conditions whose atoms all read one finite-domain input; and the same over numeric inputs; the last two are measurements.
Beside them the same two measurements are kept over root residuals, the root finite-domain and root numeric measurements, which rows 15 and 43 exercise (§8 step 4).

**3. The solver boundary (D1).**
Build the evaluator, buy the solver: the symbolic evaluator is this section, native in `jl4-core`, and the solver is z3 as a subprocess driven by SMT-LIB2, as R-V6 already ruled for `l4 prove` (`specs/proposals/VERIFICATION-BACKEND-LOWERING-SPEC.md:370`), with R-V7's encodings (`:398`) and R-V8's verdicts (`:438`), as numbered on this branch.
One lowering, from the term language of §4.2 to SMT-LIB2, serves two consumers: the query planner's arithmetic atoms, and `l4 prove` / `l4 verify`.
z3 decides for those two consumers only; the boundary decision of every evaluation stays §4.7.2's propositional supervaluation, so an `#EVAL`, a golden, the language server and the browser build never depend on a solver being installed (DU3b).

_What lowers._
The Boolean residual at the root, with every atom's term; a `declare-const` for each input it reads, of the sort §4.2's table gives its declared type; a `declare-fun` for each assumed function; and the guard of every `error`, `refuses` and `gave-up` leaf as a separate named condition.
Nothing outside R-V7's fragment lowers; it is reported as `unknown (out of fragment)`.

_What z3 is asked._
Three questions, each a `check-sat` in its own `push`/`pop` scope: is `(not r)` unsatisfiable, in which case the residual is `TRUE`; is `r` unsatisfiable, in which case it is `FALSE`; and for each guard `c`, is `c` satisfiable, in which case the error, refusal or give-up behind it is reachable and the report must carry it.
The first two are asked with every guard assumed false, which is U11b's "FALSE unless `x`" read as a query.
Before them z3 is asked whether every guard can be false at once; if not, no assignment escapes every guard, and the residual is reported by U13b's rule (§4.7.2), never as both `TRUE` and `FALSE`.
A timeout or an `unknown` from the solver is reported as undetermined with its reason (R-V8), never as a value.

_How the planner uses the answer._
The planner plans over the residual an evaluation leaves, not over the ladder's static tree.
Its support is the residual's syntactic support (§4.7.2), the inputs it still reads; it ranks them as §25f measures, about the verdict; when the user answers one, the binding is added as an assertion and the three questions are asked again.
A stateless request carries every answer, so §8 step 6 assumes the planner re-evaluates with every supplied value instead, and adds as assertions only answers to askable atoms that are not inputs; the two ask different next questions once an answer resolves a join, a `CONSIDER` on a term or a `gave-up`.
Because the questions are put to the solver and not to a truth table over independent atoms, one answer for `age` settles both `age >= 18` and `age < 65` for the planner, which is the gap U1b and U3b record as a loss; an `#EVAL` of the same residual stays undetermined (row 15), by DU3b.
The verdict is still read off the seam's two sides (§25f), each lowered as its own root.

_What is not done._
Rosette is not a backend; §4.11 says why.
It is at most an optional cross-check oracle in testing, as `catala proof` is planned to be for `l4 prove`.

**4. The report, chosen at the root only (U7b).**
The computation is the same for every caller; the caller chooses only how an undetermined result is shown:

| report   | an undetermined result shows as                                                                                                                                                                                                                                                                                                                                          | a decided residual shows as                                                                                                                                                        |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| default  | today's "I could not continue evaluating, because I needed to know the value of …", naming **every** input in the residual's support, not the first; when the directive's expression, or the body of the function it calls, is a top-level `IMPLIES` whose scope is undetermined, the value and a named scope-pending field, "`TRUE`; whether it applies needs _x_" (C5) | its value if its only terms are bare inputs (C4, row 60), and otherwise undetermined (decided by Claude overnight 2026-10-02, pending Meng's review; §8 step 3)                    |
| K3       | the K3 quotient of the residual: every atom `unknown`, so `x OR NOT x` and `age >= 18 OR age < 18` show `unknown`, agreeing with FEEL and `nodeValue`; error, refusal and give-up guards are kept, "unknown; errors if _x_" (C2, U11b, U13)                                                                                                                              | the K3 quotient too: the K3 report reads the residual through the K3 tables, never the boundary's decision, so `x IMPLIES TRUE` shows `TRUE` and `x OR NOT x` shows `unknown` (C2) |
| residual | the residual, printed as L4 source (§4.9)                                                                                                                                                                                                                                                                                                                                | its value, with the residual                                                                                                                                                       |

So `#ASSERT x OR NOT x` is satisfied under the default report and undetermined, exit 1, under K3 (C2).
Under K3 a residual shows a value only where the K3 tables settle it: `x IMPLIES TRUE` is `TRUE` because U → T is T, as `nodeValue` gives (`layout.ts:241-254`), while `x OR NOT x` is settled only by the boundary; and K3 carries no scope-pending field, which C5 made a property of the default report.
Under the default report a determined value whose only terms are bare unknown inputs, the kind today's evaluator already prints, prints as that value, spelling them, with exit 0, whether or not the step counter has started, as `LIST n, 6` does (C4, row 60).
One that holds any other term, for example a field path, a comparison, a connective residual, an operation term, a join, a `fresh` atom, an assumed-function application or a value carrying guarded leaves, is undetermined, naming its inputs, exit 1, batch status "undetermined", because each of those was stuck before the lift, after step 1 (decided by Claude overnight 2026-10-02, pending Meng's review, §8 step 3).
The scope-pending field (C5) fires on the rule body's top-level `IMPLIES`, exactly where the planner reads its seam (`BooleanDecisionQuery.hs:193-199`), and not on the residual's root: `TRUE AND (x IMPLIES TRUE)` is `TRUE` with no field, because the expression's top-level connective is `AND`, even though §4.3's `TRUE AND r = r` leaves an `IMPLIES` at the residual's root.
The value stands: exit 0, and an `#ASSERT` on it is satisfied, as `l4 verify`'s vacuity note already does; a nested `IMPLIES` does not fire it.
A `gave-up` is reported as "gave up; needed _i_" under every report.
A guarded refusal is undetermined under every report: exit 1, batch status undetermined, the refusal's reason listed, and never a determinate refusal with exit 0 (U13).
The exception is U13b's case of §4.7.2, where no assignment escapes every guard and every leaf is a refusal with one reason: that is the refusal, exit 0, batch status "refused" (`Batch.hs:369-370`), and on the service today's refusal response, a 422 whose body is the tagged error, `{"tag":"Error","contents":{"tag":"EvaluatorRefused","contents":<reason>}}` (`DataPlane.hs:270`, `:698-701`; `Types.hs:350-354`; `Backend/Api.hs:251-262`), which MCP renders as "The model refuses to answer: …" (`Api.hs:267`, `McpServer.hs:587`).
That is the default report's outcome; what the K3 and residual reports show for it is pending the open question in §9 (O1).
A guarded error is its own outcome (U11b) and exits 1: U11b states no exit code, but U13b's error-leaf control does ("the same with `1 DIVIDED BY 0 GREATER THAN 0` for an error leaf", exit 1), as U13 (2) does for a guarded refusal.
`#ASSERT REFUSED e` (`EvaluateLazy.hs:308-319`) on a residual that holds a guarded refusal holds where the guard holds and fails where it does not, so it is undetermined, exit 1, as U13 (2) rules for a directive whose refusal is reached only under an undetermined guard (row 81).
`#ASSERT REFUSED e BECAUSE r` is undetermined too when `r` matches only some of several refusal leaves (row 82), as a consequence of U13b (2) and U1b (assumed, not ruled).
`#ASSERT REFUSED e` on a residual with no guarded leaf and no `fresh` atom fails, exit 0, since every completion produces a value, as `#ASSERT REFUSED x` does today (row 72; decided by Claude overnight 2026-10-02, pending Meng's review).
On any other residual it is undetermined, exit 1, because a `fresh` atom from a `CONSIDER` on a term can stand for an arm that refuses: with `` `r` MEANS CONSIDER m WHEN JUST z THEN TBD OTHERWISE FALSE ``, `` #ASSERT REFUSED `r` `` holds where `m` is `JUST 5` and fails where it is `NOTHING` (probes `vf/s1`, `vf/s2`).
The language server and the golden harness show the default report and have no setting (U7b).
On the service the report is its own route or a rejected unknown key, never a silently dropped field, and every response states which report it carries; on MCP it is a separate tool or a listed capability (U7b).
In `l4 batch` an undetermined row is a row status, not a failure, and never trips stop-on-error (`Batch.hs:247`, `:299`, `:319`) (U7b).
Lifting reaches `l4 batch` and the service at build step 3, because they run the same evaluator, so the row status and the stated report are owed from that step (§8 step 3).
From that step a `Stuck` that reaches the directive boundary is this undetermined outcome on every surface, which is how U7b's default report renders a result not yet known: JSON kind "undetermined" with `needs` filled from the names the `Stuck` carries, batch status "undetermined", which never trips stop-on-error, and exit 1.
`l4 batch` therefore runs every row and exits 1 at the end when any row is undetermined: its `finish` (`Batch.hs:265`), which today exits 1 only for an "error" row (`:378`), gains that condition.
Exit codes: an undetermined `#ASSERT` exits 1, as a stuck one does today (U1b).
A refusal reached under no undetermined guard is a determinate refusal, exit 0, as today (`Run.hs:143-146`; row 75), and so is U13b's single refusal under every assignment; one reached only under an undetermined guard is undetermined, exit 1 (U13).
An undetermined `#EVAL` under the default report exits 1: for one that is stuck today that is today's exit code (`Run.hs:139-152` counts a `ReducedErrored` as a crash), and for a bare unknown result, which exits 0 today (§2.4, row 52), it is a change.
The ranking U7b asks for, against the 2026-08-01 ruling: that ruling covers only the crash, and the comment recording it counts `Stuck` as one (`Run.hs:78-94`).
That a failed assertion exits 0 is not part of it; the same comment calls it a deliberate asymmetry and says "Only the crash was ruled on; widening this to assertions is a separate decision" (`:83-86`).
So the ranking rests on the distinction `l4 run` already draws between `Fails` and `Errored`: a failed assertion is an answer the author did not want, and an undetermined directive is no answer at all.
Every consumer of an evaluation outcome gets an explicit arm for the residual outcome and for the scope-pending outcome (C5), with no wildcard arm: the API, diagnostics, the `l4 run` exit code, the LSP inspector and rules, and Catala (U1b).
The tree has more consumers than U1b lists, and each needs the same arms, together with arms for the guarded-leaf outcomes (U11b, U13): `l4 batch` (`Batch.hs:383-388` and `:392-396`, whose two wildcards together would score an undetermined row "success"), the service (`Backend/Jl4.hs:697-698`, `:863-864`), the REPL (`jl4-repl/app/Main.hs:656-658`, `:770-772`), the ladder's `l4/evalApp` (`jl4-lsp/src/LSP/L4/Actions.hs:145-163`), the LTS what-if and list views (`jl4-core/src/L4/Lts/WhatIf.hs:728-734`, `Lts/List.hs:181-187`), and the assertion classifier's own wildcards (`EvaluateLazy.hs:307`, `:319`), which would score a residual "assertion failed", exit 0.

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
- `specs/todo/ladder-diagrams-2026/DESIGN.md` §23 (`:927`) is the membrane and §25f (`:1489`) is the seam; `BooleanDecisionQuery.hs:27-43` and `layout.ts:209-268` are the two places that already keep `IMPLIES` as a node.
- `Machine.hs:2749-2753` is the precedent inside the evaluator itself: `RBinOp2` returns the operator applied to its evaluated operands when neither table row applies (§3.5).

**Outside this tree.**
Symbolic evaluation is a solved problem, and this section names the design it is closest to rather than inventing one.

- **Rosette** (Torlak and Bodík, "Growing Solver-Aided Languages with Rosette", Onward! 2013; "A Lightweight Symbolic Virtual Machine for Solver-Aided Host Languages", PLDI 2014) is the closest: a host-language evaluator that runs every path, merges at control-flow joins, collects assertions against the path condition, and hands the result to a solver.
  Three of its definitions were read today in the Rosette Guide and are quoted in §4.11: a symbolic term is "either a symbolic constant, created via `define-symbolic[*]`, or a symbolic expression, produced by a lifted operator", strongly typed and always of a solvable type, while "symbolic values of all other (unsolvable) types take the form of symbolic unions" (§7.1); "a symbolic union is a set of two or more guarded values", whose guards "are disjoint: only one of them can ever be true" (§7.1); and the verification condition "accumulates all the assertions and assumptions issued on these paths", with "failures due to exceptions … treated as assertion violations" (§7.2.1).
  `define-symbolic` "binds the variable to the same (unique) constant every time it is evaluated", while `define-symbolic*` "creates a stream of (unique) constants" (Guide, Essentials).
  Everything else said about Rosette here, its term hash-consing, its `ite` merging for solvable types, z3 as its default solver, is recalled from the papers and not re-read today; the PLDI 2014 PDF was not reachable at the address tried.
- **Symbolic execution** (King, "Symbolic Execution and Program Testing", CACM 1976) is where the path condition comes from; **KLEE** (Cadar, Dunbar and Engler, OSDI 2008) is the path-per-path form with execution budgets, and **veritesting** (Avgerinos, Rebert, Cha and Brumley, ICSE 2014) is the finding that merging paths back together beats enumerating them; both recalled, neither re-read today.
- **Online partial evaluation** (Jones, Gomard and Sestoft, _Partial Evaluation and Automatic Program Generation_, 1993) is the lift itself.
- **Strong Kleene** (Kleene 1952) and **supervaluation** (van Fraassen 1966) name what the boundary decides and what it does not.

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

### 4.11 Correspondence with the established designs

Our construct, the established construct, and where we deliberately differ, with the reason.
Rosette rows cite the Guide where a quotation in §4.10 covers them and say "recalled" otherwise.

| ours                                                                  | established                                                                                                                                                                                                        | same, or differs and why                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| an input `?i`                                                         | Rosette `define-symbolic`: one constant per name, every evaluation (Guide)                                                                                                                                         | same                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `fresh`                                                               | Rosette `define-symbolic*`: a new constant each time the form is evaluated (Guide)                                                                                                                                 | same, after C1: used only where no term describes the value, a `CONSIDER` on a term and an excluded-type equality; §4.13 C1                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `op (…)`, `g (…)`, `t 's f`                                           | a Rosette symbolic expression "produced by a lifted operator", strongly typed, of a solvable type (Guide §7.1); hash-consed terms (recalled)                                                                       | same, after C1: every term is keyed by its structure, as hash-consing keys Rosette's; where Rosette records a failing assertion for a partial operation, we emit its definedness guard as a leaf; §4.13 C1                                                                                                                                                                                                                                                                                                                                               |
| a Boolean residual with `IMPLIES` as a node                           | a Rosette Boolean term; SMT-LIB `=>`                                                                                                                                                                               | same; the seam's two roots and the verdict are ours (§25f), and no established design has them                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| a join `c ? t : e` of a solvable type                                 | Rosette: a term of that type, `ite` (recalled); SMT-LIB `ite`                                                                                                                                                      | same; differs at evaluation time: U4b pushes a comparison into the arms, Rosette leaves `(> (ite c 1 2) 1)` to the solver; under D1 the push is a free simplification, not the mechanism                                                                                                                                                                                                                                                                                                                                                                 |
| a join of records, lists or enumerations; `CONSIDER` on a term        | a Rosette symbolic union: guarded values with disjoint guards, split by `match` and accessors (Guide §7.1); SMT datatypes with testers (R-V7)                                                                      | differs: U4 keeps `CONSIDER` on a term unknown for now; the union is the known answer, and R-V7's datatypes carry it to the solver; recommended when U4's "for now" is reopened                                                                                                                                                                                                                                                                                                                                                                          |
| `error [c] e` and `gave-up [c]` as leaves in the residual             | the Rosette verification condition: a store beside the value that "accumulates all the assertions and assumptions issued on these paths", with exception failures "treated as assertion violations" (Guide §7.2.1) | differs in placement, and the difference is kept (DU11): Rosette's store is safe because Racket is strict, while under call-by-need a thunk is written back once and re-served, so an entry recorded under one arm's path condition would not be recorded again when another arm reads it; the leaf travels with the value and a store would not                                                                                                                                                                                                         |
| left-to-right error order                                             | Rosette: on a symbolic left operand both sides run under their path conditions and a failure is recorded, never raised (Guide §7.2.1)                                                                              | differs on purpose: a known left operand behaves as in Rosette; an erroring left operand raises as today, because §4.3's conservativity is worth more than commutativity, which U1's note settled                                                                                                                                                                                                                                                                                                                                                        |
| the step counter, started when a §4.3 site first receives a term (C4) | Rosette: no budget, the programmer bounds recursion (recalled); KLEE: time, instruction and fork budgets (recalled); veritesting: merge paths statically                                                           | differs: ours merges at every join as Rosette does, and adds KLEE's kind of budget because L4 recursion is unbounded by the author; exhaustion is a guarded leaf, never absorbed (C3)                                                                                                                                                                                                                                                                                                                                                                    |
| propositional supervaluation at the root                              | Rosette: `solve` and `verify` always go to the solver (recalled)                                                                                                                                                   | differs by ruling (DU3b): every evaluation's boundary stays propositional on every host; z3 decides only for the planner and `l4 prove` (§4.7.3)                                                                                                                                                                                                                                                                                                                                                                                                         |
| the three reports                                                     | Rosette: a model or `unsat`; no undetermined report, no residual printed back                                                                                                                                      | ours: the residual report prints the term as L4 (§4.9), because the reader is a caseworker and not a verifier                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Rosette as a backend                                                  | lower L4 to Racket and run Rosette's symbolic VM                                                                                                                                                                   | not adopted (D1): it would re-implement laziness, left-to-right error order, the regulative and temporal machinery and `TYPICALLY` with its presumption switch in a second language, which is the drift this bench found between the ladder's evaluator and the Haskell one (§3.4), between `l4 batch` and `l4 run` (§4.9), and in OpenFisca's defaults (`TYPICALLY-ONE-BEHAVIOUR-SPEC.md` §2); a Racket runtime on the service hosts; and Rosette's own split is a symbolic VM plus z3, where the VM is the half that must carry L4's semantics exactly |

### 4.12 Tests, from the rulings

Each row names the ruling it comes from, gives the L4 input, says what the `unstable` binary at `f9a504b77` does today, and states the expected report under this section.
Unless a row says otherwise, `x` and `y` are section `GIVEN … IS A BOOLEAN`, `n` and `age` are `IS A NUMBER`, `d IS A Person` with `DECLARE Person HAS age IS A NUMBER`, and `g` is `ASSUME g IS A FUNCTION FROM NUMBER TO BOOLEAN`, all unsupplied.
"Today" is a probe result where a probe file is named (`reversegear/p01` to `p22` in the session scratchpad, run 2026-10-01 on the `f9a504b77` snapshot; `tippex/t01` to `t27`, several directives to a file and numbered in file order (`t01` to `t14` in `probes/t1.l4`, `t15` to `t20` in `t2.l4`, `t21` in `t3.l4`, `t22` to `t27` in `t4.l4`), `tippex/vf/s1` to `s6`, one directive each, and the TIPPEX fact-check's `d01` to `d03`, `e03` and `e04`, re-run as `tippex/rv/`, all run 2026-10-02 on a byte-identical snapshot of the installed `l4`, the store build `jl4-0.1-b69f17a4`, built 2026-09-28, with `DECLARE Kind IS ONE OF Retail, Wholesale` and `k IS A Kind` added to the section); a row with no probe name says where its "today" comes from.
"Expected" is the default report unless the row names another; "undetermined naming _i_" means the default report's "I needed to know the value of _i_"; "unchanged" means §4.3's conservativity claim, made against the tree after build step 1, covers the row.
§8 says which build step each row belongs to.

| #   | from          | input                                                                                           | today                                                                                                                         | expected                                                                                                                             |
| --- | ------------- | ----------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | U1, §2.3      | `x AND FALSE`                                                                                   | stuck on `x` (p01)                                                                                                            | `FALSE`                                                                                                                              |
| 2   | U1            | `x OR TRUE`                                                                                     | stuck (p01)                                                                                                                   | `TRUE`                                                                                                                               |
| 3   | U1            | `x UNLESS TRUE`                                                                                 | stuck (p01)                                                                                                                   | `FALSE`                                                                                                                              |
| 4   | U1, U10b      | `x IMPLIES TRUE`                                                                                | stuck (p01, p11)                                                                                                              | "`TRUE`; whether it applies needs `x`", exit 0 (C5); the residual keeps the seam, so a verdict read from it is `Undetermined` (§25f) |
| 5   | U1, §4.6      | `and (LIST TRUE, x, FALSE)`                                                                     | stuck (p01)                                                                                                                   | `FALSE`                                                                                                                              |
| 6   | U1            | `NOT x`                                                                                         | stuck (p01)                                                                                                                   | undetermined naming `x`; residual `NOT x`                                                                                            |
| 7   | U1b, U3, U12b | `x OR NOT x`                                                                                    | stuck (p01)                                                                                                                   | `TRUE`                                                                                                                               |
| 8   | U1b, U3       | `x AND NOT x`                                                                                   | stuck (p01)                                                                                                                   | `FALSE`                                                                                                                              |
| 9   | §4.5          | `IF x THEN 1 ELSE 1`                                                                            | stuck (p01)                                                                                                                   | `1`                                                                                                                                  |
| 10  | U6b           | `x EQUALS x`                                                                                    | stuck (p01)                                                                                                                   | `TRUE`                                                                                                                               |
| 11  | U5            | `n EQUALS 3`                                                                                    | stuck on `n` (p01)                                                                                                            | undetermined naming `n`; atom `n EQUALS 3`                                                                                           |
| 12  | U6            | `3 EQUALS n`                                                                                    | "equality on types that do not support it" (p01)                                                                              | build step 1 (built): stuck naming `n`; from step 3: undetermined naming `n`, atom `3 EQUALS n` (§4.6)                               |
| 13  | U1, U5        | `older 18 AND NOT older 65`, with `older k MEANS age GREATER THAN k`                            | stuck on `age` (p02)                                                                                                          | undetermined naming `age`; residual `age GREATER THAN 18 AND NOT age GREATER THAN 65`; never `FALSE`                                 |
| 14  | U5            | `older 18 AND NOT older 18`                                                                     | stuck (p02)                                                                                                                   | `FALSE`                                                                                                                              |
| 15  | U1b, U3b      | `age >= 18 OR age < 18`                                                                         | stuck (p02)                                                                                                                   | undetermined naming `age`; the root numeric measurement of §4.7.2 rises by one                                                       |
| 16  | U1b, U3       | `IF (x OR NOT x) THEN 1 ELSE 2`                                                                 | stuck on `x` (p02)                                                                                                            | undetermined naming `x`; the tautology count of §4.7.2 rises by one                                                                  |
| 17  | U1b           | `FALSE AND (1 DIVIDED BY 0 GREATER THAN 0)`                                                     | `FALSE` (p03)                                                                                                                 | `FALSE`, unchanged                                                                                                                   |
| 18  | U1b           | `(1 DIVIDED BY 0 GREATER THAN 0) AND FALSE`                                                     | division by zero (p03)                                                                                                        | division by zero, unchanged                                                                                                          |
| 19  | U11, U11b     | `x AND (1 DIVIDED BY 0 GREATER THAN 0)`                                                         | stuck on `x` (p03)                                                                                                            | "FALSE unless `x`; errors (division by zero) if `x`", its own outcome                                                                |
| 20  | U11b          | `f TRUE`, with `f b MEANS b AND (1 DIVIDED BY 0 GREATER THAN 0)`                                | division by zero (p03)                                                                                                        | division by zero, unchanged                                                                                                          |
| 21  | U11b          | `(x AND (1 DIVIDED BY 0 GREATER THAN 0)) AND FALSE`                                             | stuck (p21)                                                                                                                   | as row 19; never absorbed to `FALSE`                                                                                                 |
| 22  | U11b          | `x OR (1 DIVIDED BY 0 GREATER THAN 0)`                                                          | stuck (p21)                                                                                                                   | "TRUE if `x`; errors if `NOT x`"                                                                                                     |
| 23  | U1b           | `#ASSERT x AND y`                                                                               | "assertion could not be evaluated", naming only `x`, exit 1 (p04)                                                             | undetermined naming `x` and `y`, exit 1                                                                                              |
| 24  | U1b           | `#ASSERT NOT (x AND y)`                                                                         | as row 23 (p04)                                                                                                               | as row 23                                                                                                                            |
| 25  | U1b, U3       | `#ASSERT x OR NOT x`                                                                            | could not be evaluated (p21)                                                                                                  | satisfied                                                                                                                            |
| 26  | U3            | `#ASSERT x AND NOT x`                                                                           | could not be evaluated (p21)                                                                                                  | failed, exit 0                                                                                                                       |
| 27  | U4            | `IF x THEN 1 ELSE 2`                                                                            | stuck (p07)                                                                                                                   | undetermined naming `x`                                                                                                              |
| 28  | U4b           | `(IF x THEN 1 ELSE 2) GREATER THAN 1`                                                           | stuck (p07)                                                                                                                   | residual `NOT x`; undetermined naming `x`                                                                                            |
| 29  | U4b, U11b     | `IF x THEN 1 DIVIDED BY 0 ELSE 2`                                                               | stuck (p07)                                                                                                                   | undetermined naming `x`; errors if `x`: at a result the join is U4b's opaque unknown (§4.5)                                          |
| 30  | §4.3          | `IF TRUE THEN 1 ELSE 1 DIVIDED BY 0`                                                            | `1` (p07)                                                                                                                     | `1`, unchanged                                                                                                                       |
| 31  | §4.5          | `IF x THEN TRUE ELSE TRUE`                                                                      | stuck (p07)                                                                                                                   | `TRUE`                                                                                                                               |
| 32  | U4b, U5b      | `(IF x THEN 2 ELSE 3) PLUS 1 GREATER THAN 3`                                                    | stuck (p21)                                                                                                                   | undetermined naming `x`: one atom keyed by its term (C1), which only the planner's solver could settle (§4.7.3)                      |
| 33  | U4, U11       | `countdown m`, with `countdown n MEANS IF n GREATER THAN 0 THEN countdown (n MINUS 1) ELSE 0`   | stuck on `m` (p08)                                                                                                            | "gave up; needed `m`"; `countdown 3` stays `0`                                                                                       |
| 34  | U4, §2.4      | `CONSIDER m WHEN NOTHING THEN 1 WHEN JUST y THEN 2`, with `m IS A MAYBE NUMBER`                 | "reached a CONSIDER that has no branch for it" (p09)                                                                          | build step 1 (built): stuck naming `m`; from step 3: undetermined naming `m` (U7b), kept by step 5 (U4)                              |
| 35  | U5b           | `d's age`                                                                                       | the no-branch message (p05)                                                                                                   | build step 1 (built): stuck naming `d`; from step 3: undetermined naming `d's age`                                                   |
| 36  | U5b           | `d's age AT LEAST 18 AND NOT d's age AT LEAST 18`                                               | the no-branch message (p05)                                                                                                   | `FALSE`                                                                                                                              |
| 37  | U5b           | `d's age AT LEAST 18`                                                                           | the no-branch message (p05)                                                                                                   | undetermined; atom `d's age AT LEAST 18`, askable                                                                                    |
| 38  | U5b           | `g 3 AND NOT g 3`                                                                               | stuck on `g` (p12)                                                                                                            | `FALSE`                                                                                                                              |
| 39  | U5b           | `g 3 AND NOT g 4`                                                                               | stuck (p12)                                                                                                                   | undetermined naming `g`; two atoms                                                                                                   |
| 40  | §4.3          | `FALSE AND g 3`                                                                                 | `FALSE` (p12)                                                                                                                 | `FALSE`, unchanged                                                                                                                   |
| 41  | U5, U5b       | `n PLUS 1 GREATER THAN 3 AND NOT (n PLUS 1 GREATER THAN 3)`                                     | stuck (p15)                                                                                                                   | `FALSE`: one atom twice (C1)                                                                                                         |
| 42  | U6            | `n PLUS 1 EQUALS n PLUS 1`                                                                      | stuck (p15)                                                                                                                   | `TRUE`: the identity rule on a keyed term (C1)                                                                                       |
| 43  | §4.6          | `n GREATER THAN 3 AND n LESS THAN 2`                                                            | stuck (p15)                                                                                                                   | undetermined naming `n`; the root numeric measurement rises by one; the planner's solver decides it (DU3b)                           |
| 44  | §4.7          | `n PLUS 1`                                                                                      | stuck (p15)                                                                                                                   | undetermined naming `n`                                                                                                              |
| 45  | U6b           | `elem g (LIST g)`                                                                               | stuck on `g` (p06)                                                                                                            | "equality on types that do not support it", exit 1; never `TRUE`                                                                     |
| 46  | §4.6          | `elem n (LIST 1, 2)`                                                                            | stuck (p06)                                                                                                                   | undetermined naming `n`; residual `n EQUALS 1 OR n EQUALS 2`                                                                         |
| 47  | §4.3          | `elem 3 (LIST 3, n)`                                                                            | `TRUE` (p06)                                                                                                                  | `TRUE`, unchanged                                                                                                                    |
| 48  | U6, §4.3      | `elem 3 (LIST n, 3)`                                                                            | "equality on types that do not support it" (p06)                                                                              | `TRUE`                                                                                                                               |
| 49  | U10           | `f x`, with `f b MEANS TRUE OR b`                                                               | `TRUE` (p10)                                                                                                                  | `TRUE`; a shared case for `eval.ts` and `nodeValue`                                                                                  |
| 50  | U10           | `g x`, with `g b MEANS b OR TRUE`                                                               | stuck (p10)                                                                                                                   | `TRUE`                                                                                                                               |
| 51  | U2, U2b       | the trace of `FALSE OR TRUE`                                                                    | `lazytrace-exception.golden:15-16` shows `IF a THEN TRUE ELSE b`; `#EVALTRACE` on the binary prints "no trace captured" (p16) | built at step 2: the trace shows `FALSE OR TRUE`; no golden names `a` or `b`                                                         |
| 52  | §2.4, U7b     | `#EVAL TRUE AND x`, `#EVAL TRUE IMPLIES x`, `#EVAL x`                                           | each prints `x` as a value, JSON `"kind":"value"`, `"ok":true`, exit 0 (p11, p17)                                             | built at step 1: stuck naming `x`, exit 1; undetermined naming `x` from step 3                                                       |
| 53  | U8, T4, T6    | `` `has capacity` AND `is adult` ``, with `` `has capacity` IS A BOOLEAN TYPICALLY TRUE ``      | stuck on `` `has capacity` `` when a directive reads it (p14, p18); `` `is adult` `` printed as a value through a rule (p19)  | undetermined naming `is adult`, with `presumed` listing `has capacity`; presumption off: residual over both                          |
| 54  | U9, T3        | service: `{}` for a boolean                                                                     | `{"result":{"value":false}}`, no diagnostic (§2.5); at `f9a504b77`, fixed by W1 (#530)                                        | undetermined naming the input, the report stated; `null` the same; absent with `TYPICALLY` takes the default, listed in `presumed`   |
| 55  | U7b           | an `l4 batch` row with an unsupplied input                                                      | refused, "Missing required field" (probe p7 of `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` §2)                                          | row status undetermined; stop-on-error not tripped                                                                                   |
| 56  | U12, U12b     | ``NOTHING `kor` (knot NOTHING)``                                                                | `NOTHING`; `#ASSERT … EQUALS NOTHING` satisfied (p13)                                                                         | built at step 1; unchanged: the library is reading (a), and row 7 is the contrast U12b asks the comment to draw                      |
| 57  | U11b, U7b     | row 19 under the K3 report                                                                      | not probed                                                                                                                    | "errors if `x`", never a bare `unknown`                                                                                              |
| 58  | §2.6, §4.3    | every corpus directive not stuck after build step 1                                             | §2.6's census                                                                                                                 | unchanged value, error or non-termination from step 2, by §2.6's census rerun on each step's build (§8)                              |
| 59  | C3, C4        | `(loop m GREATER THAN 0) AND FALSE`, with `loop n MEANS IF n GREATER THAN 0 THEN loop n ELSE 0` | stuck on `m` (p22)                                                                                                            | "`FALSE` unless `m GREATER THAN 0`; gave up if so"; never `FALSE`                                                                    |
| 60  | C4            | `#EVAL LIST n, total`, with `DECIDE total IS 1 PLUS 2 PLUS 3`                                   | `LIST n, 6`, JSON `"kind":"value"`, exit 0 (p22)                                                                              | `LIST n, 6`, exit 0, unchanged: no §4.3 site receives a term, so the counter never starts                                            |
| 61  | C2            | `#ASSERT x OR NOT x` under the K3 report                                                        | not probed                                                                                                                    | undetermined, exit 1; row 25 is the same assertion under the default report                                                          |
| 62  | C5            | `TRUE AND (x IMPLIES TRUE)`                                                                     | stuck on `x` (p22)                                                                                                            | `TRUE`, no scope-pending field: the expression's top-level connective is `AND`                                                       |
| 63  | C5            | `(x IMPLIES TRUE) AND (y IMPLIES TRUE)`                                                         | stuck on `x` (p22)                                                                                                            | `TRUE`, no scope-pending field                                                                                                       |
| 64  | C1            | `n MODULO 2 EQUALS 0 AND NOT (n MODULO 2 EQUALS 0)`                                             | stuck on `n` (p22); `5 MODULO 2.5` raises "Expected an Integer" (p22)                                                         | "`FALSE` unless `n` is not whole; errors if so": one atom twice, under `MODULO`'s definedness guard                                  |
| 65  | C1            | `(1 DIVIDED BY n) EQUALS (1 DIVIDED BY n)`                                                      | stuck on `n` (p22)                                                                                                            | "`TRUE` unless `n EQUALS 0`; errors if `n EQUALS 0`"                                                                                 |
| 66  | C1            | `d's age EQUALS d's age`                                                                        | the no-branch message, naming `d` (t06)                                                                                       | `TRUE`: the identity rule on a keyed term                                                                                            |
| 67  | C4            | `#EVAL LIST n, big`, `big` a determined computation longer than the step limit                  | not probed with a long `big`; as row 60                                                                                       | `LIST n` and `big`'s value, exit 0, unchanged: the counter never starts; C4 (1)'s own control                                        |
| 68  | U11b          | `r WITH x IS TRUE`, with `r MEANS x AND (1 DIVIDED BY 0 GREATER THAN 0)`                        | division by zero (t12)                                                                                                        | division by zero, unchanged: with row 19, the two halves of U11b's positive control                                                  |
| 69  | U10           | `FALSE AND f TRUE`, with row 20's `f`                                                           | `FALSE` (t11)                                                                                                                 | `FALSE`, unchanged; U10's "`FALSE AND` a call that errors", a shared case for `eval.ts` and `nodeValue`                              |
| 70  | §2.4, U4      | `CONSIDER m WHEN JUST y THEN 2, OTHERWISE 1`, with `m IS A MAYBE NUMBER`                        | `1`, as a value, exit 0 (t02; the coordinating session's probe of 2026-10-02)                                                 | build step 1 (built): stuck naming `m`; from step 3: undetermined naming `m` (U7b), kept by step 5 (U4)                              |
| 71  | §2.4, U4      | `CONSIDER Claim k 5 WHEN Claim Retail 0 THEN "first" WHEN Claim kk a THEN "second"` (§2.4)      | `"second"` (t01), right for every `k`                                                                                         | `"second"`, exit 0, unchanged: `5` mismatches `0` (decided by Claude overnight 2026-10-02, pending Meng's review, §8 step 1)         |
| 72  | U1b           | `#ASSERT REFUSED x`                                                                             | "assertion failed: expected a refusal, but the expression produced a value", not a crash (t03)                                | failed, exit 0, unchanged: an input never refuses (decided by Claude overnight 2026-10-02, pending Meng's review, §8 step 1)         |
| 73  | U13           | `x AND TBD`                                                                                     | stuck on `x` (t07)                                                                                                            | "`FALSE` unless `x`; refuses (TBD's reason) if `x`", exit 1, batch status undetermined; before step 5, as row 77                     |
| 74  | U13, U4b      | `IF x THEN TBD ELSE FALSE`                                                                      | stuck on `x` (t08)                                                                                                            | as row 73                                                                                                                            |
| 75  | U13           | `TBD AND x`                                                                                     | refuses, "TBD: this rule has not been written yet" (t09), exit 0 (`Run.hs:143-146`)                                           | unchanged: a refusal under no undetermined guard stays a determinate refusal                                                         |
| 76  | U13           | `FALSE AND TBD`                                                                                 | `FALSE` (t10)                                                                                                                 | `FALSE`, unchanged: the refusal is never reached                                                                                     |
| 77  | U13           | `x AND TBD`, before build step 5                                                                | stuck on `x` (t07)                                                                                                            | undetermined naming `x`, exit 1, batch status undetermined, never "refuses": U13's interim (C), a step-3 control                     |
| 78  | U13b          | `IF (x AND TBD) THEN 1 ELSE 1`                                                                  | stuck on `x` (t15)                                                                                                            | "1 unless `x`; refuses (TBD's reason) if `x`", exit 1                                                                                |
| 79  | U13b          | `IF (x AND (1 DIVIDED BY 0 GREATER THAN 0)) THEN 1 ELSE 1`                                      | stuck on `x` (t16)                                                                                                            | "1 unless `x`; errors (division by zero) if `x`", exit 1                                                                             |
| 80  | U13b          | `IF x THEN TBD ELSE TBD`, as a `BOOLEAN`                                                        | stuck on `x` (t17)                                                                                                            | refuses (TBD's reason), exit 0: no assignment escapes every guard, and every leaf is one refusal                                     |
| 81  | U1b, U13      | `#ASSERT REFUSED (x AND TBD)`                                                                   | "assertion could not be evaluated", naming `x`, exit 1 (t18)                                                                  | undetermined, exit 1: holds if `x` and fails if not (U13 (2))                                                                        |
| 82  | U1b, U13b     | `#ASSERT REFUSED (IF x THEN TBD ELSE nope) BECAUSE` TBD's reason, `nope MEANS REFUSE "nope"`    | "assertion could not be evaluated", naming `x`, exit 1 (t19)                                                                  | undetermined, exit 1: the reason matches one of two leaves (assumed, not ruled)                                                      |
| 83  | §2.2          | `n AS STRING`                                                                                   | "AS STRING/TOSTRING can only convert …, but found: n" (t04)                                                                   | build step 1 (built): stuck naming `n`; from step 3: undetermined naming `n`                                                         |
| 84  | §2.2          | `JSONENCODE n`                                                                                  | "Internal error … Cannot encode value to JSON: n" (t05)                                                                       | build step 1 (built): stuck naming `n`; from step 3: undetermined naming `n`                                                         |
| 85  | §4.3          | `CONSIDER (x AND y) WHEN TRUE THEN 1, OTHERWISE 2`                                              | stuck on `x` (t21)                                                                                                            | from step 3: undetermined naming `x` and `y`, never `2`: step 3's interim, a step-3 control                                          |
| 86  | §2.4          | `EVERY Tenant t IN LIST alice, u … MUST Sign t`, `u` an unsupplied `Actor`, `alice` signing     | `FULFILLED`, exit 0 (d01)                                                                                                     | build step 1: stuck naming `u`, exit 1 (decided by Claude overnight 2026-10-02, pending Meng's review, §8 step 1)                    |
| 87  | §2.4          | `PARTY alice MUST Deliver Retail`, event `PARTY alice DOES Deliver k`, `k` an unsupplied `Kind` | left pending, exit 0 (e03)                                                                                                    | build step 1: stuck naming `k`, exit 1 (decided by Claude overnight 2026-10-02, pending Meng's review, §8 step 1)                    |
| 88  | §2.4          | row 86 with a known second tenant, `Tenant OF "Bob"`, in place of `u`                           | Bob's obligation left pending, exit 0 (d02)                                                                                   | unchanged                                                                                                                            |
| 89  | §2.4          | row 86 with no cast, `EVERY t IN LIST alice, u`                                                 | stuck on `u`, exit 1 (d03)                                                                                                    | unchanged                                                                                                                            |
| 90  | §2.4          | row 87 with the event `PARTY alice DOES Deliver Retail`                                         | `FULFILLED`, exit 0 (e04)                                                                                                     | unchanged                                                                                                                            |

Of the 90 rows, 84 were probed: rows 1 to 65 except 54, 55, 57, 58 and 61 on 2026-10-01, and rows 66 and 68 to 90 on 2026-10-02; rows 54, 55, 57, 58, 61 and 67 were not.

### 4.13 Conflicts for Meng

These are places where the definition shows two recorded rulings pulling apart, a ruling's word having lost its referent, or an established design answering a question better than the recorded ruling does.
All seven items were put on the bench "Symbolic Evaluation Conflicts" (claude.ai artifact `5vs1hzHCQN95oKj7WVYy7Y`, db collection `l4-symbolic-conflicts-1001`), each with its own skeptic, and Meng ruled on every one on 2026-10-01; the ruling line under each heading says how, §9 holds the record, and the text below each line is the item as it was put to the bench.
Items headed "Dissent" are places where this section thought a ruling pointed the wrong way; both were declined, the ruling stands as recorded, and the dissent sits beside it.
The bench's own skeptics found four near-collisions and the amendments reconciled them: U3b's order clause against U4's join (dropped), U4b's `c ? t : e` against U3's boundary promise (kept inside the evaluator), U11b's leaf against U4b's guarded error (one mechanism), and U5b's field-path key against U4's `CONSIDER` (the selector returns a term).
Reading the amendments together finds the five below and no sixth.

**C1. Atom identity: by input, or by term.**
**RULED 2026-10-01** (bench card C1, CARBONCOPY): accepted with three conditions, the definedness guard for partial built-ins, the identity rule on keyed terms, and a separate askability rule; see §9 U5b.
U5 ("an arithmetic unknown operand gets a fresh atom per evaluation"), U5b ("only unknowns that carry no term (arithmetic results, `IF` joins, non-Boolean assumed calls) get fresh atoms") and U6 ("derived unknowns (`n PLUS 1 EQUALS n PLUS 1`) stay comparison atoms") make an arithmetic result keyless.
§4.2 gives it a term anyway, because the solver needs the term, and keying by that term would be sound for the same reason keying a comparison by term is: a built-in operation is a function of its operands, so two occurrences of one term denote one value.
Under the rulings as recorded, rows 41, 42 and 32 are undetermined; keyed by term they would be `FALSE`, `TRUE` and `NOT x`.
[Note, 2026-10-02: keyed by term, row 32 is still undetermined, with one atom, because U4b pushes a comparison into a join only when it is applied to the join directly, and row 32 applies it through `PLUS`.]
The same question reaches U6b's identity rule, stated for "the same unknown input on both sides": under it `d's age EQUALS d's age` is an atom, while row 36 is `FALSE`, because the comparison is keyed by the field-path term and the equality is not.
Established answer: Rosette shares equal terms by construction (hash-consing, recalled), and a new constant per evaluation (`define-symbolic*`, Guide) is used only where the program itself asks for a new unknown; nothing in it corresponds to a fresh constant standing in for `n PLUS 1`.
Under D1 the solver sees the term either way, so the only question left is whether the propositional decider may use it.
The definition follows the rulings.
Recommendation: key every atom by its full term; keep `fresh` for the genuinely keyless (a `CONSIDER` on a term, a `gave-up`, an excluded-type equality); leave U5b's askability rule as it is, so the planner still asks only for inputs and field paths.

**C2. Whether the K3 report sees the boundary decision.**
**RULED 2026-10-01** (bench card C2, PEEKABOO): the recommendation below was overturned by its skeptic; option A, the K3 report prints the K3 quotient and U1b and U7b stand; see §9 U1b.
U1b: "`--unknowns k3` is true strong Kleene: atoms only, no tautology settling, as #526 §8 step 3 already says."
U7b: "What the caller chooses is the report, never the computation", and "the caller chooses only how an undetermined result is reported".
The boundary decision of §4.7.2 is computation.
If it runs before the report is chosen, the K3 report shows `x OR NOT x` as `TRUE` and U1b's sentence is false of it; if the K3 report skips it, the caller is choosing computation, which U7b retired.
No established design has a K3 report; Rosette answers with a model or `unsat`.
The definition leaves the K3 column of §4.7.4 open for a decided residual.
Recommendation: read U1b's sentence as describing build step 3 of §8, the stage before a boundary decider exists, and let every report show a decided residual as its value; the K3 report then differs from the default only in printing `unknown` instead of naming the inputs.

**C3. What running out of steps returns.**
**RULED 2026-10-01** (bench card C3, FUMES): accepted with two additions, a strict operation on a `gave-up` returns the leaf, and nothing new is evaluated once the counter runs out; see §9 U4.
U4: "Running out returns an unknown naming the pending condition".
U11: "Divergence on an unknown is caught by PETROL's step counter ('gave up; needed _x_')".
U11b: "A residual that contains an error leaf is never absorbed", because a definite `FALSE` would promise what a supplied run that errors cannot keep.
An ordinary unknown is absorbed by `AND FALSE`; so with `loop n MEANS IF n GREATER THAN 0 THEN loop n ELSE 0`, the lifted `(loop m GREATER THAN 0) AND FALSE` would be `FALSE` for unknown `m`, and the two-valued run with `m` set to 1 does not terminate.
That is U11b's objection in a different coat.
Established answer: in Rosette a failure on a path is an entry in the verification condition and not a value (Guide §7.2.1), so nothing can absorb it; KLEE's budgets end a path and report it (recalled).
The definition treats `gave-up` as a guarded leaf, never absorbed (§4.5), and reads U4's "unknown" as that leaf.
Recommendation: a `gave-up` is an entry in the store that Dissent U11 below proposes, keyed by its path condition; if the leaf design stands instead, it is a guarded leaf and never absorbed.

**C4. The step counter's scope.**
**RULED 2026-10-01** (bench card C4, STARTINGGUN): the start rule below was wrong, since `#EVAL LIST n, total` prints `LIST n, 6` today; the counter starts when a §4.3 site first receives a term operand, with three further conditions; see §9 U4.
U4: "a cumulative step counter, explore mode only".
U7b: "Every evaluation is lifted; there is no evaluation mode."
A counter that runs from the first step of every evaluation would turn a long but fully supplied computation into a `gave-up`, which breaks §4.3's conservativity.
Rosette has no counter and KLEE's budgets are per run (both recalled), so neither answers the question of where ours starts.
The definition starts the counter at the first term built, which is the only reading of "explore mode only" left once there is no mode (§4.5), and asks for that reading to be confirmed.

**C5. A decided value with an undetermined verdict at the evaluator's root.**
**RULED 2026-10-01** (bench card C5, HOTAIR): option A1, the default report gives the value and a scope-pending field, fired on the rule body's top-level `IMPLIES`; see §9 U7b.
Row 4, `x IMPLIES TRUE`, is `TRUE` by §4.7.2, and U10b records the pair "value `TRUE`, verdict `Undetermined`" as the expected answer.
The default report of §4.7.4 prints `TRUE` and names no input, because the result is decided; §25f's finding is that this is the one case where a met requirement must not end the interview.
The residual report carries the seam intact, so a verdict-aware consumer can still ask for the scope; the default report cannot.
No established design has the seam; the question is ours alone.
Whether the default report should name the scope's inputs when the root is an `IMPLIES` with an undetermined scope is not ruled anywhere, and the definition does not do it.

**Dissent: U11 and U11b, the error leaf's placement.**
**DECLINED 2026-10-01** (bench card DU11, KANGAROO, option B): under call-by-need a side store loses entries through thunk sharing; the leaf stays, and a `CONSIDER` on a term carries the scrutinee's leaves; see §9 U11b.
U11 ruled "add an error leaf to the residual", and U11b that a residual containing one is never absorbed, which §4.3's table implements with a special row and §4.7.2 with a hole rule.
Rosette keeps the same information in a different place: the value merges freely, and the failure is recorded in a store beside it, keyed by the path condition (Guide §7.2.1: the verification condition "accumulates all the assertions and assumptions issued on these paths"; "failures due to exceptions are treated as assertion violations").
With a store, `(x AND (1 DIVIDED BY 0 GREATER THAN 0)) AND FALSE` has value `FALSE` and store `{x: division by zero}`, and the report "FALSE unless `x`; errors if `x`" is read off the pair; absorption is impossible because there is nothing in the value to absorb.
The same store carries U4b's arm errors and C3's give-ups, so one mechanism covers three rulings; §4.3's table loses its special row; a residual prints as plain L4 with no leaf that L4 cannot spell (§4.9); and the store lowers to SMT-LIB2 as the list of guards §4.7.3 asks z3 about anyway.
The intent of U11 and U11b, loud and never absorbed, is kept exactly; only the data structure changes.
Recommendation: implement the leaf as a store entry, and let U11's words "error leaf" name the entry.

**Dissent: U3b's ordering, the truth table first and the solver on a trigger.**
**DECLINED 2026-10-01** (bench card DU3b, TOOLSHED, option B): z3 decides only for the planner and `l4 prove`; every evaluation's boundary stays propositional on every host; the three places `6c2096ff9` wrote this dissent into are reverted; see §9 U3b and D1.
U3b made the count of numeric-input conditions "the trigger for the SMT backend", with the local truth table first.
D1 bought the solver the same day, and R-V6 already specifies how a missing solver degrades.
Two deciders in sequence are two behaviours for one residual depending on build stage, and the truth table's answer on `age >= 18 OR age < 18`, undetermined, is exactly the one the solver reverses.
Recommendation: z3 is the boundary decider from build step 4; the truth table is the no-solver fallback for finite-domain atoms and nothing more; U3b's counts are measurements, not gates.
The cost is a `z3` on the service hosts from step 4, which D1 accepts.

**No dissent on D1.**
Build the evaluator, buy the solver is the right split; the one consequence worth stating, the solver on every host that runs the planner, is in §9 D1.

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
What R8 does not reach, and the parallel `TYPICALLY` work (`TYPICALLY-ONE-BEHAVIOUR-SPEC.md`, on `unstable` since #525) owns, is that the service's wrapper ignores `TYPICALLY` altogether (§2.5, T3).

**Joins force defaults no two-valued run reads.**
T6's `presumed` lists the defaults "actually forced during that evaluation", and a join evaluates both arms (§4.5), so a default read in only one arm is forced although a run with every input supplied would read it in at most one.
Assumed, not ruled: a default forced in any arm counts, since the residual may rest on it, and W8's event carries that arm's path condition (§8 step 5); whichever of build step 5 and W8 lands second meets this.
Two probe results from today that this spec does not explain are in §10.

---

## 6. Reports, and what does not move

**There is no switch (U7b).**
Every evaluation is lifted; the module does not decide, and neither does the caller.
The caller chooses the report of §4.7.4:

- `l4 run` and `l4 batch`: the default report, unless a flag names the K3 or the residual report; the flag names a report, not a mode.
- The service: the report is its own route, as `/query-plan` is, or an unknown key is rejected; every response states its report.
  A residual response is `{"determined": null, "residual": "<L4 source>", "needs": [...], "verdict": "Undetermined"}`.
  `determined` and `verdict` are the planner's vocabulary (§3.3); `needs` is new, since the planner's own field is `stillNeeded :: [QueryAtom]` (`jl4-query-plan/src/L4/Decision/QueryPlan.hs:191`).
- MCP: a separate tool or a listed capability, never a reserved argument.
- No new directive.
  A `#EXPLORE` would make the module decide, and it would be a directive every exporter has to learn to ignore.

**What does not move.**
Every committed golden except the trace golden Step 0 names (§4.4): the corpus has nine stuck directives (§2.6), and under the default report a single-input residual prints the text today's `Stuck` prints, so those nine change only where the residual names more than one input or decides.
One of them decides at build step 3: `lazytrace-exception.l4:11`, `#EVALTRACE and (LIST TRUE, FALSE OR TRUE, TRUE, something, FALSE)`, reduces to `something AND FALSE` and so to `FALSE`, so that golden moves at step 2 and again at step 3, and is read before each blessing.
Build step 1 moves directives that are not stuck today (§4.3), and they are counted, not assumed.
Its bare-result fix moves no corpus golden: the census of §2.6, rerun on 2026-10-02 on the snapshot of the installed `l4`, reproduces its counts (514 files, 7,211 results, 9 stuck) and finds a bare assumed input printed as a value only in four `doc/reference/syntax/` examples (`annotation-example.l4:9`, `comment-example.l4:14`, `directive-example.l4:11`, `identifier-example.l4:12`), each printed as a value with exit 0 today, and `doc/` is in no golden glob; the same census over `jl4-core/libraries`, `jl4/examples/not-ok/tc`, `jl4/examples/lsp/semantic-tokens` and `jl4/tests-cli/fixtures`, 200 more files, finds none.
`doc/test-docs.sh` fails a page whose `l4` run exits non-zero (`:371-386`), so step 1 repairs those four in the same PR.
Its `CONSIDER` fix moves every directive whose `CONSIDER` takes a catch-all on an unknown today; such a directive returns an ordinary value, so no census on today's binary can tell it from a correct one, and step 1 counts them by diffing result kinds on its own build.
That is U7's scoping of "nothing changes" to committed goldens.

**What the service's `fromMaybe FALSE` becomes.**
T3 and T3b rule it removed at all three sites, `CodeGen.hs:239`, `:335`, `:603`, which still read `fromMaybe FALSE` on `unstable` at `6ed297629`; the removal is W1, which #530 merged on 2026-10-01 (`6d3a56f75`), and `CodeGen.hs` on `unstable` now has no `fromMaybe FALSE` at all.
Under T3 an absent boolean on the wrapper path binds to a placeholder assumed term, lazy, stuck only if read and naming the input; `null` and `{}` bind the same way and never take a default; the direct path's eager refusal (`Jl4.hs:448`) stays, and its lazy binding is its own work item.
That is the `TYPICALLY` work's W1 and W2, listed here so the two specs do not each assume the other has it.

**Two gaps between W1 as built and this spec** (cited at #530's head, `659699e7d`, whose `CodeGen.hs` is the one `unstable` has since the merge).
The placeholder is a generated `ASSUME` named after the input with " (not supplied)" appended (`notSuppliedTerm`, `CodeGen.hs:84-85`), so the report names the placeholder, as in "I needed to know the value of `has criminal record (not supplied)`" (`TYPICALLY-ONE-BEHAVIOUR-SPEC.md` S1, as merged with #530), where row 54 expects the input itself; and one placeholder for absent and `null` alike loses §4.8's `Unsupplied` / `Declined` provenance.
Placeholders are also declared for `BOOLEAN` inputs only (`placeholderAssumes`, `:94-98`), while T3's table gives an assumed term to any absent or `null` input that is not a `MAYBE`; a missing non-`BOOLEAN` input there still ends in `WHEN NOTHING THEN NOTHING` (`:390-399`).
W1's own description gives the assumed term "for a non-`MAYBE` input", so the extension is W1's unbuilt half, while the direct path's lazy binding, "its own work item" under T3b, has no W number at all; §8 step 6 depends on both.

**The wrapper paths' root is a `MAYBE`.**
The service's generated wrapper and `l4 batch` both evaluate `CONSIDER decodeArgs inputJson WHEN RIGHT args THEN` the call wrapped in `JUST` (`jl4-service/src/Backend/CodeGen.hs:268` at `6ed297629`, `:340` since #530, and `:350-351`; `jl4/app/L4/Cli/Batch.hs:689-691`), so the root of the `#EVAL` is a `MAYBE`, not the exported function's result.
The boundary decision of §4.7.2 reads a Boolean root and C5 reads "the directive's expression, or the body of the function it calls", so on those paths neither fires: a residual the boundary would decide stays undetermined, and a scope-pending `TRUE` is never reported; on the service a single `{}` sends a request down that path (§2.5).
Because a determined result that holds any term but a bare input is undetermined from step 3 (§8 step 3), an `l4 batch` or service-wrapper row whose answer is a residual inside the `JUST` is undetermined from step 3, not "success"; step 6, which applies the report to the function's own result, makes that output more precise.
A function whose result reduces to a bare input, such as `x AND TRUE`, which §4.3's table returns as `x`, is `JUST x` on the wrapper and prints as that value, while the direct path reports it undetermined (step 1's bare-result arm, row 52), so the two paths disagree from step 3 until step 6.
That is loud today, since the service raises "#EVAL produced ASSUME" on it (`Backend/Jl4.hs:1161`), and step 6's unwrap applies the root bare-result rule to the function's own result.
§8 step 6 states how this is closed, as an assumption.

---

## 7. Cost, and how to measure it before deciding

The lift costs nothing on a directive that never hands a term to a site in §4.3's table: its transitions are the same ones, and the step counter has not started (C4).
On a directive that does, it costs exactly the evaluation today's `Stuck` skipped, which is the right operands of undecided connectives and both arms of undecided conditionals.
That is unbounded in principle, so it is measured, not guessed:

1. **Baseline.** Today's census (§2.6) shows the corpus directives are almost all fully supplied (9 stuck in 7,211), so the workload has to be made: for every `@export` function in the corpus, take each directive that calls it and generate its partial-input variants, dropping each input in turn and then every pair, which is what a wizard does mid-interview.
   An input is dropped by replacing the argument with an unsupplied section `GIVEN` of the same type, so both binaries run the same source, and each variant runs under a wall-clock cap, since rows 33 and 59 do not terminate without the step limit (assumed, not ruled).
2. **Coverage.** On those variants, the `f9a504b77` binary against the lifted one: how many end in a value, a decided residual, an undetermined residual, a guarded leaf, a `gave-up`, a different error, or a timeout.
3. **Blow-up.** Per directive, the total steps taken under §4.5's counter, the largest residual, the three counts of §4.7.2, and the number of conditionals evaluated on a term condition, each against the two-valued run of the same directive with every input supplied.
   The machine has no step counter today, only the depth cap (`maximumFrameDepth`), so the counter is part of this measurement, and its limit is set so that on this workload it fires before the service's timeout and allocation cap (C4).
   So items 2 and 3 run on the branch of each step that brings or changes the counter, before that branch merges: step 3, which brings it, and step 5, whose joins are most of what they measure.
   Each such step sets the limit from item 3, checks C4 (4) for that value, and merges no provisional value, because anything on `unstable` can reach users at the next prerelease cut (repo `CLAUDE.md` §1).
   The caps are a configuration read: the service defaults to 60 s and 256 MB per evaluation (`jl4-service/src/Options.hs:157`, `:143`), and the hosts pass `--eval-timeout 300` (`nix/jl4-service/configuration.nix:107`); if no limit fits under the host's cap, that is a question for Meng.
   On step 4's branch, before it merges, the same workload measures the decider's work per residual (atoms, expansion steps), which sets the decider's own budget (§4.7.2, §8 step 4).
4. **Wall clock.** `jl4-test` and the §3.2.1 differential must be unchanged within noise on fully supplied directives; that is the cost to everyone who never meets an unknown.
5. **Positive controls.** One directive constructed to evaluate both arms of a nested conditional on one unknown, depth 10, whose step count the measurement must show growing; and rows 13, 14, 15, 16, 19, 20 and 36 of §4.12, which must come out as the table says.
   A measurement that scores row 19 as a plain unknown has not seen the leaf, and one that scores row 13 as `FALSE` has keyed atoms by position.
   Two more from the bench (C3, C4): row 59, `(loop m GREATER THAN 0) AND FALSE`, must come out as "`FALSE` unless `m GREATER THAN 0`; gave up if so" and never `FALSE`; and row 60, `#EVAL LIST n, total`, must print `LIST n, 6`, exit 0, with the counter never started.
   Row 60 is too short to tell a counter started early from one started correctly, so C4 (1)'s own control is row 67, whose `big` takes more steps than the limit and must still print its value, exit 0.

U4's step limit is set from the distribution item 3 produces, not before.

---

## 8. Build sequence

Each step lands on its own branch, stacked on `spec/unknown-evaluation` until #526 merges, because each records its assumptions here in the same change (repo `CLAUDE.md` §4); opening those PRs is an outward action, and Meng's.
Trace-golden churn in steps 2 to 5 is coordinated with the `TYPICALLY` work's W8, which also edits `L4.EvaluateLazy.Trace`.
Each step names the §4.12 rows it must answer and, where the rulings leave a choice that a builder would otherwise have to invent, the choice it makes, marked _assumed, not ruled_; these come from the Track B audit of 2026-10-02.
An assumption is not a ruling: a builder who finds one wrong changes it here, in the same PR, and says why.
Row 58, every corpus directive not stuck after build step 1, holds from step 2 on; each step measures it by rerunning §2.6's census on its own build and comparing every directive's result kind and value with the tree after step 1, while §7's item 4 measures wall clock.

1. **Two-valued fixes, no lift.** A `ValAssumed` scrutinee of a `CONSIDER` raises `Stuck`, naming it (§2.4); the selector path raises the same (§2.4, probe `p05-record.l4`); the right-operand misdiagnosis of `runBinOpEquals` is fixed (U6); and a bare assumed term as the result of an `#EVAL` is reported as `Stuck`, as `#ASSERT` already does (`EvaluateLazy.hs:306`; §2.4, probe `p17-bare.l4`).
   The last is covered by the rulings: U7b makes the default report today's "I needed to know the value of …", row 52 expects exactly that with exit 1, and the 2026-08-01 ruling makes `Stuck` exit 1 (`Run.hs:78-94`); only its timing was open, and it lands here so that the silent exit-0 path closes first.
   Independent; small.
   Rows 12, 34, 35 and 70 (their step-1 halves), 52, 56, 83, 84, 86 and 87, with rows 71, 72 and 88 to 90 as controls that do not change.
   Four choices in this step are decided by Claude overnight 2026-10-02, pending Meng's review, and §9's "Open for Meng" lists them: the sub-pattern refinement and the two regulative sites below, and keeping `#ASSERT REFUSED x`'s verdict.
   This step changes directives that do not end in `Stuck` today (§4.3), so its PR reads every moved result before blessing (§6).
   It also carries the U12 and U12b work, which is independent and small: move `jl4/experiments/negation-as-failure-examples.l4` under a checked glob, shipping its four goldens if the glob is goldened (repo `CLAUDE.md` §3.1); relabel it, starting with its `:79` heading "The Kleene lift", as "truth-functional strong Kleene (#526 §4.1(a))"; add ``#ASSERT (NOTHING `kor` (knot NOTHING)) EQUALS NOTHING`` with the comment U12b asks for (row 56); turn the two doc links, `doc/reference/libraries/negation-as-failure.md:63` and `doc/reference/patterns/README.md:270`, which point at the experiments path on GitHub's `main`, into relative links to the new path; relabel the two passages that call the file a "Kleene three-valued lift", `negation-as-failure.md:61` and `patterns/README.md:269`, and rewrite `negation-as-failure.md:60-63` to say that the library is declined and that a data-borne `NOTHING` still needs `CONSIDER` (U12); and update the file's own line 2 and `specs/done/NEGATION-AS-FAILURE-SPEC.md` at `:3`, `:5`, `:23`, `:274` and `:285`, where its open question 2 still reads "Ship the Kleene lift".
   _Assumed, not ruled:_

   - The `CONSIDER` fix goes in the backward pattern frames, as `ValAssumed r -> stuckOnAssumed r` before the `patternMatchFailure` arm of `PatNil0`, `PatCons0` and `PatApp0`, and not in `matchPattern`, so it covers a user `CONSIDER`, a nested sub-pattern and the selector at once; a literal pattern is fixed by the right-operand fix, through `PatLit1` (§2.4).
   - Before it raises `Stuck` at the first unknown a sub-pattern inspects, the matcher checks the branch's later positions whose cells are already evaluated, or hold a literal not yet evaluated, for a definite mismatch, and forces nothing else, since forcing could raise or diverge where today's run does not; on a mismatch the branch fails as today and the next one is tried (decided by Claude overnight 2026-10-02, pending Meng's review).
     It takes those positions in matching order and stops at the first it cannot decide, since the match would force that one first (LOUDHAILER review, 2026-10-03: with `tbd MEANS REFUSE ...`, `Send3 k tbd Wholesale` against `MUST Send3 Retail 7 Retail` refuses when `k` is `Retail`, so it is `Stuck`, not skipped).
     A literal argument is allocated as an unevaluated thunk (`allocateRecursive`, `Machine.hs:1128-1134`), so "already evaluated" alone would not see row 71's `5`; reading a literal forces nothing that can raise or diverge.
     Row 71 so keeps `"second"`, exit 0, and the lift keeps it, since its scrutinee is a known constructor.
   - In the regulative action matcher, which shares those frames (its `continuePattern` in `Contract8`), an unknown raises `Stuck` naming it, as it does in a `CONSIDER`, rather than failing the pattern so that `Contract11` tries the next event; and `EVERY`'s cast test raises `Stuck` naming an unknown candidate rather than dropping it (`QuantCast`).
     Both are decided by Claude overnight 2026-10-02, pending Meng's review, loud over silent; they reach the regulative layer, which §4.6 otherwise leaves out of scope, so §9 lists them for Meng to reverse (rows 86 and 87, with controls 88 to 90).
     The ruled right-operand fix still changes the party check (`Contract7`) and a literal action argument, from one loud error to another; `PROVIDED` and `EVERY`'s `WHO` filter stay as §2.4's residue.
     Shipped early under LOUDHAILER (smucclaw/l4-ide#998): `QuantCast` raises `Stuck` on a `ValAssumed` candidate, and `QuantRoll` on an unknown roll or rest of one.
     Shipped early under LOUDHAILER (smucclaw/l4-ide#999): the three frames' `ValAssumed` arm, `patternMetUnknown`, is `Stuck` under `Contract11`, with the refinement above; the `CONSIDER` fix widened its `metUnknownHandled` to `ConsiderWhen1`.
   - A `ValAssumed` on the right of `EQUALS` raises `Stuck` only when the left value is of a type equality supports; a closure, a built-in, an unapplied constructor or an obligation on the left keeps `EqualityOnUnsupportedType` (`double EQUALS f` in `ok/unknown-inputs-two-valued.l4`), and that file also has a number, a string, a date and a constructor on the left, each `Stuck`.
   - `AS STRING`, `TOSTRING` and `JSONENCODE` raise `Stuck` on a `ValAssumed`, and so do the four temporal iterators on a predicate that returns one (§2.2); all of them error today, so only the text changes.
   - The bare-result fix is one arm in the shared `NotAnAssert` classification (`EvaluateLazy.hs:278-285`), `Right (MkNF (ValAssumed a)) -> ReducedErrored (UserEvalException (Stuck a))`, so that every consumer agrees, the ladder's `l4/evalApp` included.
     `AssertRefuses` (`:319`) keeps its wildcard, so `#ASSERT REFUSED x` stays "failed", exit 0, the right verdict, since an input never refuses (row 72; decided by Claude overnight 2026-10-02, pending Meng's review); only its wording, "produced a value", could improve.
     Its JSON kind moves from "value" to "error" now, and to "undetermined" at step 3; the four `doc/reference/syntax/` examples of §6 are repaired in the same PR.
   - The selector's `Stuck` names the record input `d`; the field path arrives with step 3.
   - Tests: one new `ok/` corpus file carrying these cases, with `#EVAL LIST n, total` as C4's control and its four goldens read before blessing, and a `tests-cli` test that `#EVAL x` exits 1.
   - The refinement also runs before a literal or expression pattern raises, so `CONSIDER Pair n "x" WHEN Pair 0 "y" …` fails that branch whatever `n` is (assumed, not ruled); it runs in `PatLit1`, once an expression pattern's own expression has been evaluated, because evaluating it can raise or refuse whatever `n` is (review finding F1, 2026-10-03).

   **Built** 2026-10-02: rows 12, 34, 35, 52, 56, 70, 83 and 84 and the iterators, in `jl4/examples/ok/unknown-inputs-two-valued.l4` and `jl4/tests-cli/fixtures/eval-assumed.l4`, with controls 60, 71 and 72 held; the four doc examples, which the bare-result arm turns red; the U12 and U12b work; rows 86 and 87 under LOUDHAILER, above.
   **What review changed** (step-1 review, 2026-10-03): an expression pattern's own expression is evaluated before a later clash can fail its branch (F1, above); the literal-position check takes the in-order scan (F2); `jl4-service` tests and README pin the `422` for a missing input read by `CONSIDER … OTHERWISE` on the wrapper and deontic paths (F3); docs and the skill stop saying `WITH` cannot supply a section `GIVEN` (F4) or that `OTHERWISE` never answers on a missing input (F5).

2. **Step 0** (§4.4, U2, U2b): the built-in connectives as frames, with the trace golden, the service reasoning tree and jl4-mlir's parity harness moved together, measured.
   Row 51.
   "Measured" means three things: `jl4-test` shows exactly one moved golden plus the new indirect-call goldens; its wall clock is within noise of the base (§7 item 4); and U2b's parity run, before and after, has its trace sub-matrix read by hand, since nothing gates on it (`parity-harness.mjs:556-571`; the full-parity CI job is `continue-on-error`, `pr-checks.yml:1980`).
   _Assumed, not ruled:_

   - The new value form forces every operand through `autoApplyDischargedImport` (`Machine.hs:3959`), never through a bare `continueRef`.
     Today's closure bodies reach their operands through `forwardExpr`'s `Var` arm, which applies a discharged imported reader, and a bare `continueRef` would hand back the reader's closure, so `#ASSERT TRUE AND <imported reader>` would report "assertion failed" with exit 0.
     Probe `s2skeptic/flagmain.l4`, which imports a module whose section `GIVEN` has a `TYPICALLY`, shows both sides today: `TRUE AND` the imported Boolean reader is `TRUE`, while the imported numeric reader `PLUS 1` is an internal error, because a binary built-in forces both operands by `continueRef` (`Machine.hs:1572-1573`, `:1515-1517`).
     A two-file positive control beside `ok/section-given-import-def.l4` and `ok/section-given-import-call.l4` puts a bare imported reader in each operand position.
   - When a known left operand does not decide, the right operand continues in tail position, with no new frame and no Boolean check, which keeps the prelude's `x AND and xs` (`prelude.l4:227`) flat and does not implement step 1's bare-result change by accident.
   - The frames emit no trace node of their own: the call site's application is the connective's node, with a child per operand labelled with its source text and value (§4.4, decided by Claude overnight 2026-10-02, pending Meng's review); in a text trace the right operand, which runs in tail position, is the connective's next step, and in the service's reasoning that makes it the node's last child; a skipped operand is left out of both and drawn only as GraphViz's stub (§4.4, decided by Claude overnight 2026-10-03, pending Meng's review); an exception from the left operand shows as the bare `• ↯` node the arithmetic built-ins already produce (`lazytrace-exception.golden:145`).
     GraphViz draws a stub for a skipped operand only when `showUnevaluated` is on, and `l4 trace` leaves it off: it renders with `defaultGraphVizOptions` (`jl4/app/L4/Cli/Trace.hs:105-109`; `GraphVizOptions.hs:25`), and the `showUnevaluated = True` at `jl4/app/L4/Cli/Common.hs:206` sits in a `TraceOptions` field that nothing reads.
     Where it is on, today's stub is labelled with the `IF`'s skipped arm, `b` (`GraphViz2.hs:332-353`), and the frames label it with the skipped operand's source text instead; the PR records one DOT before and after.
     The service's reasoning tree and jl4-mlir's runtime trace must emit the same operand children, since jl4-mlir reproduces the service's trace shape on purpose (§2.4), and U2b's `IMPLIES` parity fixture checks them.
   - The four rewrite arms of `forwardExpr` (`Machine.hs:1198-1205`) enter the same frames, so no `IF` rewrite is left anywhere.
   - jl4-mlir has no `__IMPLIES__` lowering (`jl4-mlir/src/L4/MLIR/Lower.hs:1936-1943` lowers `__AND__`, `__OR__` and `__NOT__` only), so this step adds one, short-circuiting on a `FALSE` left operand, and an `IMPLIES` schema special; the `NOT` special goes, its only consumer being the deleted synthesiser.
     What the fall-through does today, a compile failure or a refusal, is measured first: it is neither, it compiles and traps at run time with "unresolved runtime symbol `'__IMPLIES__'`", a wasm-error (step-1 build, 2026-10-03).
   - The `IMPLIES` parity fixture, `jl4-mlir/test/fixtures/implies-probe.l4`, has two functions with one body: one takes its operands as the rule's own inputs, and its trace cell is byte-identical; one reads them as section `GIVEN`s, and its trace cell cannot be, because jl4-service reports a rule that reads only section `GIVEN`s as one node with no children, whatever its body (measured 2026-10-03, on an arithmetic body too). It joins all three corpus lists: the always-enforced fixture loop (`pr-checks.yml:1928`), the harness invocation (`:2083-2092`) and the harness's own default list.
   - jl4-mlir's schema force-traces a connective's operands as jl4-core shows them, the left one when it is a variable (a `TRUE` or `FALSE` constructor is pruned there as trivial) and the right one always, since jl4-core evaluates it as a step of its own; without this a variable operand has no wasm frame, and the cell differs.
   - The indirect-call golden is a new `ok/connectives-indirect.l4`, the four connectives passed through a function parameter, with a short circuit over a division by zero as its control, and a test that no trace names `a` or `b`.

   **Built** 2026-10-03: row 51; `ValConnective` and its `ConnectiveLeft` frame, the indirect-call and two-file import controls, the GraphViz stub, and jl4-mlir's mirror and `IMPLIES` lowering.
   Measured: `jl4-test` moved one golden, `lazytrace-exception`, beside the new files' goldens; its wall clock was 963 s for 3,784 examples against 1,009 s for 3,764 on the step-1 tree, run back to back on a shared machine; parity before and after, its trace sub-matrix read cell by cell, changed no existing cell and adds four byte-identical `IMPLIES` cells.
   **What review changed** (step-2 review, 2026-10-03; across 413 `ok`, `legal` and `canon` files, 6,420 directives, results and exit codes were identical to step 1's):

   - jl4-mlir traced `NOT p` as `p` with the negated value, new in this step: the call `App __NOT__ [p]` shares its range with a named operand, and with `p AND q` in `NOT (p AND q)`, and the trace's range map tagged all of them "App"; `NOT (p AND q)` and `NOT (NOT p)` were already wrong in base. The connectives' calls now carry the surface forms' tags, a NOT's including its operand's, and `implies-probe` gains `NOT p`, `NOT (p AND q)`, `NOT (NOT p)` and `p UNLESS q`, every cell byte-identical in trace (F1).
   - The frames compute what the `IF` computed for programs that finish. A rule that calls itself without end through a right operand, `loop n MEANS TRUE AND loop n`, now runs until it is stopped, because the operand is in tail position, where step 1's `IF` closure overflowed the frame cap at about 2 s; `FALSE OR loop (n PLUS 1)` grows to 4.8 GB. A recursion through an `IF`'s branch already behaved so, and the service still stops it at its limits, with a 500. Build step 3's counter bounds this only once a term has started it, so a fully supplied program still runs until it is stopped (F2).
   - `implies-probe`'s `p IMPLIES (1 DIVIDED BY n GREATER THAN 0)` with `p` FALSE and `n` 0 pins WASM's short circuit: an eager lowering, built as a mutant, fails it (F3).
   - `GraphVizStubSpec` pins the stub with `showUnevaluated` on, which no shipped renderer turns on (F4).
   - The trace sentences in `doc/` are checked against real output (F5).

   Known differences between jl4-mlir's trace and jl4-service's, each present in base too, recorded rather than fixed (F6, F7): under a `WHERE` binding the service ends the body with a node for the binding's name, `r`, which WASM omits, and after a short circuit WASM labels the left operand with the binding's name, `r p`, where the service labels nothing; a rule that reads a section `GIVEN` shows its value in WASM's top label and not in the service's (`mixed OF TRUE, TRUE` against `mixed OF TRUE`); and a built-in connective passed through a parameter, `combine __IMPLIES__ p q`, is a WASM "unresolved runtime symbol".

3. **Atoms-only residuals, default report.** Input atoms, field paths, comparison atoms, Boolean assumed calls, operation terms over the total built-ins, the connective table of §4.3, the identity rule of §4.6, and the default report naming every input; no boundary decision yet.
   This is what U1b calls "true strong Kleene: atoms only".
   Rows 1, 2, 3, 5, 6, 10, 11, 12, 13, 15 (without its count clause), 17, 18, 23, 24, 35, 37, 39, 40, 42, 44, 45, 46, 47, 48, 49, 50, 66, 69, 75, 76, 77 and 85 of §4.12; the "from step 3" halves of rows 34, 70, 83 and 84; and rows 60 and 67, which hold at every step from this one.
   Of those, the "residual" and "atom" clauses of rows 6, 11, 12, 13 and 46 are read at this step from the trace, where terms print as L4 source, and from step 4 in the residual report; row 37's "askable" is the planner's, step 6.
   Rows 4, 62 and 63 need step 4's decider, because the evaluator keeps `x IMPLIES TRUE` as a node (§4.2): at this step they are undetermined, naming `x` (and `y`), and C5's scope-pending field, which fires only on a decided value, arrives with step 4.
   It builds on steps 1 and 2: the lift lives in step 2's frames (§4.4), and rows 12 and 48 need step 1's right-operand fix.
   **Interims this step carries**, because it builds §4.3's connective table while joins and the leaves are step 5's:

   - The step counter, with its limit set from §7's items 2 and 3 run on this step's branch before it merges and C4 (4) checked for that value, so that no provisional value is merged; step 5 measures it again.
     Without it, a right operand that diverges under a term on the left, `x AND (loop 1 GREATER THAN 0)`, would hang or overflow the frame cap where today it is `Stuck` at once, which U4 rules out.
   - An error, a refusal or running out of steps in the right operand of `AND`, `OR` or `IMPLIES` under a term on the left is re-raised as `Stuck` naming the left's inputs, and the right's too if it was itself `Stuck`.
     Running out anywhere else, once the counter has started, re-raises as `Stuck` naming every input that reached a §4.3 site in the directive, as §4.5 has the directive boundary do at step 5.
     That is today's answer for those directives, except that it names every input, as U7b's default report does, where today's names only the first it reaches (row 23).
     For a refusal this is U13's interim (C); for the other two it is assumed, not ruled.
     The rewrite must cover a refusal explicitly: without it, `x AND TBD` would reach the directive as `ReducedRefused` (`EvaluateLazy.hs:283`), which exits 0 (`Run.hs:146`) and gives a batch row the status "refused" (`Batch.hs:369-370`), U13's forbidden option B; row 77 is the control.
     It is done by rewriting the exception as it unwinds through the connective's frame, never by catching it and resuming.
     The comment at `Machine.hs:838-849` says nothing between a `Refuse` and its directive can observe it, "not a boolean connective", and this rewrite is the first frame that does, so this change makes U13's restatement, "a refusal is never turned into a value", which the rewrite keeps.
     It also checks here that the static refusal analysis the comment names, presumably the DMN exporter's, reported as `D-REFUSE` (`jl4-core/src/L4/Dmn/Lower.hs:610`, over `analyzeSafety`), stays sound.
   - `IF`, `BRANCH` and `CONSIDER` on a term, and `AS STRING`, `TOSTRING` and `JSONENCODE` on one, raise `Stuck` naming the term's inputs, which is today's answer, until the site's own rule lands: joins and `CONSIDER` on a term at step 5, and for the coercions never (§4.3).
     Terms are value forms of their own beside `ValAssumed`, not a widened `ValAssumed` (assumed, not ruled), so every site that step 1 makes raise on a `ValAssumed` needs the same arm for a term; otherwise a catch-all `CONSIDER` on `x AND y` would take its `OTHERWISE` silently, which is row 70's defect again.
     Row 85 is the control: `CONSIDER (x AND y) WHEN TRUE THEN 1, OTHERWISE 2` is undetermined naming `x` and `y`, never `2`.
   - From this step a `Stuck` that reaches the directive boundary is the undetermined outcome on every surface: JSON kind "undetermined" with `needs` filled from the names the `Stuck` carries, batch status "undetermined", which never trips stop-on-error, and exit 1 (§4.7.4).
     That is a consequence of U7b, whose default report renders a result not yet known as today's `Stuck` text and makes an undetermined batch row a status, not a failure; it changes only directives that are stuck after step 1.
     `l4 batch` runs every row, never stopping on an undetermined one, and exits 1 at the end when any row is undetermined, so `finish` (`Batch.hs:265`) gains that condition beside today's "error" rows (`:378`).
   - Every outcome consumer listed in §4.7.4 gets an explicit arm for the undetermined outcome, with no wildcard, and renders it exactly as today's `Stuck`, `l4 batch` excepted.
   - U7b's batch and service obligations apply from this step, since lifting reaches them here: `l4 batch` gives an undetermined row the status "undetermined", which is not an error and never trips stop-on-error, where today's two wildcards (`Batch.hs:388`, `:396`) would score a residual result "success"; and the service states its report on every response, as `"report": "default"` until step 6 adds the others.
     WASM-served responses state it too, from `wrapEvaluationEnvelope` in `jl4-mlir/runtime/jl4-runtime.mjs`, which `wasm-worker` serves, and from `jl4-mlir run`: they answer the same evaluation API, so a client sees one envelope whichever engine answered, and WASM evaluates only fully supplied inputs, so its report is always the default one (decided by Claude overnight 2026-10-04, pending Meng's review).
     That holds because the runtime refuses a required input that is missing or null, or a record input missing a required field, or a list input with a null element, with the service's own 422 and body, `Parameter 'y': missing required parameter`; before, it read one as 0, so `{"x": true}` to `x AND y` answered FALSE where the service refuses it (decided by Claude overnight 2026-10-04, pending Meng's review).
     For a field or element sent as null the service's message is its JSON decoder's, `Expected JSON boolean but got: Null`; the status is the same.

   _Assumed, not ruled:_

   - A determined result whose only terms are bare unknown inputs, the kind today's evaluator already prints (`LIST n, 6`, C4, row 60), prints as that value, spelling them, exit 0, whether or not the counter has started in that directive; one that holds any other term, for example a field path, a comparison, a connective residual, an operation term, a join, a `fresh` atom, an assumed-function application or a value carrying guarded leaves, is undetermined under the default report, naming its inputs, exit 1, batch status "undetermined" (decided by Claude overnight 2026-10-02, pending Meng's review).
     Each of those other terms was stuck before the lift, after step 1, so this keeps today's answer: `LIST n, (n PLUS 1)`, `LIST x, (n GREATER THAN 3)` and `JUST (x AND y)` are stuck today, and `LIST (d's age), 6` is after step 1, where today it gets the no-branch message (probes `t22` to `t25`, 2026-10-02, on the same snapshot).
     So `#EVAL LIST x, (y OR TRUE)` prints `LIST x, TRUE`, exit 0, though the `OR` received a term and started the counter and the directive is stuck on `y` today (`t27`), while `#EVAL LIST n, (n PLUS 1)` and `#EVAL JUST (x AND y)` are undetermined.
     "As today" differs by surface: the CLI prints `LIST n, 6`, while the service raises "#EVAL produced ASSUME" (`Backend/Jl4.hs:1161`).
   - Terms are built only for first-order pure built-ins, and only the total ones: arithmetic, string and date operations and the comparisons, which excludes `AS STRING`, `TOSTRING` and `JSONENCODE`.
     The temporal-context switches, the iterators and the regulative clock keep `Stuck`, and so does a partial built-in applied to a term (§4.6), until step 5 can emit its guard.
   - The Boolean consumers outside §4.3's table: structural equality (`EqConstructor3`) combines the component equalities with the `AND` table, left to right, so `(LIST n, 2) EQUALS (LIST 1, 3)` is `FALSE`; `PatLit2` follows the rule for a `CONSIDER` on a term, which at this step is the interim above; the temporal iterators, the party check, `PROVIDED` and `EVERY`'s `WHO` filter raise `Stuck` naming the residual's inputs, never an internal or misleading error.
     Each gets a probe.
   - Residuals and atom keys are strict trees built outside `nf`'s depth cutoff (`EvaluateLazy.hs:602-605`; `maximumStackSize = 200`, `Exceptions.hs:151-152`), so a long residual neither drops inputs from the report nor lets two operands that differ only below depth 200 share a key.
     A determined operand is normalised for its key under exception handling and a size bound; if normalising raises or passes the bound, the site raises `Stuck` naming the term's inputs, which is today's answer, and never makes the atom `fresh`, since a `fresh` atom under `AND FALSE` would absorb the error or give-up that a completion reaches (C1, C3 (1), U11b).
     A leaf in its place would claim an error the two-valued run may never reach, because an assumed function need not read its argument.
   - `ValAssumed`'s declared type: `Nothing`, a type variable and an unsolved inference variable count as excluded from the identity rule, and `typeHasFunctionComponent` is given the module's own component map, since reused as it stands it answers `False` for all three.
   - The default report keeps its single-input message byte-identical, so every page that quotes it stays true, and lists several names deduplicated, in evaluation order; `l4 run --json` gives the outcome a new kind, "undetermined", with a `needs` array.
   - A term in a trace prints as L4 source through `prettyLayout` from this step, and `↯ stuck` stays only at sites that still raise.
   - As built (assumed, not ruled, each found while building): terms are built for `PLUS`, `MINUS`, `TIMES`, `EQUALS` and the four comparisons only; every other built-in on a term keeps `Stuck`, today's answer.
     A determined operand is read for its key without forcing anything, from cells already evaluated, unevaluated literals and names bound to either, up to 1,000 nodes; one that cannot be read so leaves the site `Stuck`, so `g n` with `n` a computed argument is `Stuck` on `g`.
     An equality over a type the identity rule excludes is `Stuck`, not the `fresh` atom of §4.6, since `fresh` arrives with step 5.
     A record's generated selector is recognised by its own one-branch `CONSIDER` with no source position, which is how the field path is built without changing the trace of a known record's field.
     A `StackOverflow` in the right operand under a term is an error there, and is rewritten to `Stuck` like any other.
     A batch row with an error and an undetermined result is "error"; one with an undetermined result and a refusal is "undetermined".
     A term prints with every compound operand bracketed, and an undetermined result's JSON `needs` gives each name as plain text, a field path as `d's age`.
   - Decided by Claude overnight 2026-10-03, pending Meng's review, each in its own commit on the step-3 branch: several names print in the plural, "the values of … but they are assumed terms", the one-name message unchanged; and an undetermined `#ASSERT` keeps JSON kind "assertion", with its `needs` and message under `"undetermined"`, where this step's text above gives kind "undetermined" on every surface.
   - Decided by Claude overnight 2026-10-04, pending Meng's review, in the commit "service: an MCP evaluation error is the HTTP error body, report included", whose message does not carry the label: every evaluator error's MCP tool text is now the HTTP error body, `{"contents":{"contents":"…","tag":"InterpreterError"},"report":"default","tag":"Error"}`, where it was prose, so that an undetermined one states its report. The alternative: keep the prose, and append the report to it as a trailing line.

   **Built** 2026-10-03: rows 1, 2, 3, 5, 6, 10, 11, 12, 13, 15 (without its count clause), 17, 18, 23, 24, 35, 37, 39, 40, 42, 44, 45, 46, 47, 48, 49, 50, 66, 69, 75, 76, 77 and 85, the step-3 halves of rows 34, 70, 83 and 84, rows 60 and 67, and rows 4, 62 and 63 as undetermined, in `jl4/examples/ok/unknown-inputs-lifted.l4` and `jl4/tests-cli/fixtures/eval-undetermined.l4`; the interims, the undetermined outcome on every consumer, the batch status, the service's and WASM's `"report"`.
   Measured: §7's items 2 and 3 on this branch against step 2's build (`4dce73ca5`; the step-2 review's commits since change only comments under `jl4-core/src`), over 674 corpus, `doc` and library files and 148 partial-input variants of the exported calls in 28 of them (`gen.py` in the session scratchpad; most corpus directives call through a record or a multi-line `WITH` it does not parse, so the workload is small): no determined result moved and no exit code changed; 151 directives started the counter; the most steps any took was 59 and the largest term was 13 nodes; a machine step allocates about 290 bytes and runs at about 25 million a second.
   The limit is 250,000 steps, about 73 MB of allocation and 10 ms, under the service's default 256 MB per evaluation and 60 s (C4 (4)), and a thousand times the workload's largest; its positive control, `x OR (`count up from` 0 EQUALS 20000)`, takes 540,033 steps, is `TRUE` with no limit and `Stuck` naming `x` with it, and row 67's `LIST n, `count up from` 0` prints its value.
   Goldens moved: `lazytrace-exception` (decides `FALSE`, as §6 says) and `unknown-inputs-two-valued` (row 35's field path), beside the new file's.
   Row 58, by §2.6's census against step 2's build over 724 files: 7,441 results on each side, no exit code changed, and every result that differs was stuck before: 76 now undetermined with the same text, 12 decided and 12 naming a second input, a field path or the unsupported-equality error, all in this step's test files and step 1's field reads.
   The §3.2.1 differential: 436 of 437 printed files give the same results, the other being `ok/every/run-blame.l4`, whose message quotes its own source location, as at step 2.
   `jl4-test`'s wall clock: 1,007 s for 3,790 examples, against 988 s for 3,784 on step 2's build, back to back on a shared machine at a load of about 6 (§7 item 4).
   Parity over CI's nine files: 120 values byte-identical and, of the traces, 25 byte-identical and 95 differing, every cell as on step 2's final build (`f57d7732c`); without the WASM report, every value was only value-equal and every trace differed, from that one key.
   **What review changed** (step-3 review, 2026-10-04; tests in `jl4-core/test/UnknownInputsSpec.hs`, each run against a mutation it catches):

   - A field of an unknown was a field path whatever its type, so for `s IS A Shape`, `Shape IS ONE OF Circle HAS radius …, Square HAS side …`, `s's radius EQUALS s's radius` was satisfied, where every Square makes it an error. The path is now built only for a type with one constructor; otherwise the match is Stuck on `s`, as at step 2.
   - The identity rule read a type synonym as a type with no constructors, so `f EQUALS f` for `f IS A Fn`, `Fn IS FUNCTION FROM NUMBER TO NUMBER`, was satisfied, where every supplied `f` makes it the unsupported-equality error. Synonyms are now expanded, at the top and in every component.
   - An effect in a speculative right operand happened: `x AND (RECORD `wrote` IS FALSE)` answered FALSE with the write, and a FETCH or POST there was attempted. A ledger write, the HTTP request of a FETCH or POST, and ENV now raise Stuck on the speculative frame's left instead (`refuseEffectUnderUnknown`), and a built-in's `RuntimeTypeError` there is rewritten like any error; the machine's invariant failures still propagate, assumed, not ruled. The FETCH and POST guards are not exercised by a test, since one that reached them would make a request if they regressed.
   - WASM read a missing input as 0, and the service's MCP evaluation error, the batch schema and the errors page each lacked the report or misdescribed an undetermined case; see the line beside U7b above, and the commits.
   - The JSON of an undetermined result is one shape, `"undetermined": {"needs", "message"}`, in the core encoding `l4 batch` writes and in the API, whose "success" is null for it, as `l4 run --json` already had it; the core `#EVAL`'s object under its own key is assumed, not ruled. Each need is spelled as L4 source, so a path with spaces can be split (decided by Claude overnight 2026-10-04, pending Meng's review).
   - The diagnostics and the LSP rules name every outcome, with no wildcard.
   - The step rate above was questioned, at 5 to 8 million a second, and re-measured: fifty run-outs of 250,000 steps take 0.42 s more user time than fifty short calls at a load of 4.6, about 30 million a second; one run-out per file is within the 0.3 s start-up's noise, which is where the lower figure came from.

   Census after review, over the review's 809 corpus, `doc` and library files: against step 2's build (`4dce73ca5`, whose evaluation `f57d7732c` does not change), 7,686 results on each side, no exit code changed, and each of the 95 results that differ was stuck on step 2, 83 still undetermined and 12 decided; against step 3 before review, 2 differ, both a need now quoted.

   **Documentation in the same PR** (repo `CLAUDE.md` §6, §7): a paragraph on an unknown left operand in the reference pages for `AND`, `OR` and `IMPLIES`, since `doc/reference/operators/AND.md:76-78` describes only a known one; and every page that quotes the `Stuck` message whose example now names a second input or decides (`grep -rn 'it is an assumed term\|I needed to know the value of' doc skills` finds 28 lines in 14 files, four of the files in `skills/writing-l4-rules/references/source-patterns/`; it counts every line that quotes the message, and which of their examples change is for this step to find), with the `l4-plugin` bundle regenerated by `etc/build-plugin-bundle.mjs` when a skill changes (repo `CLAUDE.md` §1.0).

4. **The boundary decider and the residual report.** §4.7.2 by truth table over the residual's atoms on every host (DU3b), the three counts, the K3 and residual reports, residuals printed as source and round-tripped through `prettyLayout`, and the §3.2.1 differential extended to residual results; C5's scope-pending field arrives here, with the first decided `TRUE`.
   Rows 4, 7, 8, 14, 15's count clause, 25, 26, 36, 38, 41, 43, 61, 62 and 63.
   It builds U13b's decision for a residual no assignment of whose atoms escapes every guard (§4.7.2), for the default report, while the K3 and residual reports' rendering of it is pending the open question in §9 (O1); the row that exercises it, row 80, is in step 5, because it needs that step's join and leaves, as rows 64 and 65 need its definedness guards.
   **Documentation:** U1b's wording on the DMN limits page, `doc/exports/dmn-bpmn.md`, whose "Limits, stated plainly" block (`:367`) has none of it yet: "propositional supervaluation of a Boolean residual", its two gaps (atoms are independent; non-Boolean results are not settled), and `x OR NOT x`, `TRUE` at L4's boundary and `null` in FEEL; and a page for the `--unknowns` flag and its three reports.
   _Assumed, not ruled:_
   - The decider is Shannon expansion with constant folding, stopping once one `TRUE` and one `FALSE` completion are found.
     Its work is charged to a budget of its own, apart from C4's step counter, so that running out while deciding is never a `gave-up`; the budget is set from the decider's work measured on this step's branch before it merges (§7 item 3).
     When the budget runs out the decider reports undetermined with a named reason, naming the residual's syntactic support, and never hangs, which §4.7.2 shows is sound; otherwise the report names the semantic support (§4.7.2), so `(x OR NOT x) AND y` names only `y`.
     It decides from the residual itself, before `nf`.
   - The K3 report is the K3 quotient, as C2 ruled and §4.7.4 now says: `x IMPLIES TRUE` shows `TRUE`, `x OR NOT x` shows `unknown`, and no scope-pending field appears.
     The exit code follows the outcome as the chosen report shows it, so row 61 exits 1 under K3 while row 25 is satisfied under the default report, and a residual that only the boundary decides exits 0 under the default and residual reports and 1 under K3, while one the K3 tables settle, such as `x IMPLIES TRUE`, exits 0 under all three.
   - C5's trigger is the built-in `IMPLIES` at the top of the body, after peeling `WHERE`, through one level of call, counting a reference to a 0-ary `DECIDE` as a call; it fires only when the value is decided, and the scope is decided as its own root, so `(x OR NOT x) IMPLIES y` gets no field; in JSON it is `"scopePending": {"needs": [...]}`.
   - A residual is printed by rebuilding it as an `Expr Resolved` and printing that with `prettyLayout`, never with a printer of its own, so `x AND NOT y` prints as `x AND (NOT y)` (`L4/Print.hs` always brackets a negated conjunct) and §4.12's residual texts are illustrative.
     Known numbers print exactly, as a decimal when the denominator is a product of 2s and 5s and otherwise as `p DIVIDED BY q`, since today's value printer goes through `Double` (`prettyRatio`, `jl4-core/src/L4/Utils/Ratio.hs:14-16`).
     A Boolean `EQUALS` node is kept for printing, a subterm that occurs more than once prints once under `WHERE`, and each guard prints on its own line, in words.
     The round trip is tested by wrapping the residual as `GIVEN <inputs> DECIDE r IS <residual>`, re-evaluating it with the same unknowns, and comparing the atom keys and the boundary decision.
   - The tautology-and-contradiction count is over `IF` conditions only, which is U3's trigger; root residuals, as in rows 15 and 43, get §4.7.2's root measurements instead; every count stays internal until step 6, and until then tests read it through an evaluator API.
   - When the boundary decides, the trace gains one final step, such as "`TRUE` whatever `x` is", so that `l4 run --trace` and the service's reasoning tree agree with the printed value.
   - The flag is `--unknowns default|k3|residual`, U1b having spelt `--unknowns k3`.
   - The extended differential runs under each report from a script under `etc/`, which `etc/verify-branch.sh` names where it already prints the §3.2.1 reminder; a one-line pointer in repo `CLAUDE.md` §3.2.1 is a `CLAUDE.md` edit and needs Meng's word.
5. **Joins, the step counter and guarded leaves** (§4.5, U4, U4b, U11, U11b, U13, U13b).
   Rows 9, 16, 19 to 22, 27 to 34, 57, 59, 60, 64, 65, 67, 68, 73, 74, 78, 79, 80, 81 and 82, row 70, whose step-3 answer `CONSIDER` on a term keeps, and rows 86 and 87, which stay loud; row 80 exercises step 4's decision for a residual no assignment of whose atoms escapes every guard.
   It builds joins, and `CONSIDER` on a term as a `fresh` unknown that carries the scrutinee's guarded leaves (U4, DU11), which ends step 3's interim for `IF`, `BRANCH` and `CONSIDER`; whether that `fresh` atom may be absorbed is pending the open question in §9 (O6).
   The pattern frames' lifted rule applies only when the unwind's target is a `ConsiderWhen1`: under `Contract11`, and at `EVERY`'s cast test, step 1's `Stuck` stands, so the action matcher and the cast test stay loud (rows 86 and 87).
   It builds U13b's carrying of a term's guarded leaves through the agreeing-arms rule and the identity rule (§4.5, §4.6).
   How it reads C3 (2)'s "nothing new is evaluated" once the counter has run out, which row 59 depends on, is pending the open question in §9 (O3); row 59's expected text holds under the narrower reading, "no closure body is entered".
   This step's branch carries §7's measurement again: with the joins and the leaves built, §7's items 2, 3 and 5 run on that branch and set both the step limit and the decider's budget anew before the branch merges, since the joins are most of what the decider will meet.
   It builds U13's guarded refusal leaf, which ends U13's interim; the comment at `Machine.hs:838-849` already carries U13's restatement, from step 3.
   **Documentation:** the guarded-error, guarded-refusal and gave-up outcomes; and the DMN limits page records that FEEL takes the else arm on an `IF` over an unknown (U1b).
   _Assumed, not ruled:_
   - A non-Boolean join that holds a leaf is, at a result, U4b's opaque unknown, reported as undetermined with its guard (row 29, §4.5); row 33 holds as written.
     Where every leaf of such a join is one refusal, the outcome is pending the open question in §9 (O2).
   - A leaf inside a guard is read as not `TRUE` when deciding whether another leaf can be reached, so an arm that can never run drops its leaf.
   - Error leaves come from every `UserEvalException` except `Stuck` and `StackOverflow`, so the `Stuck` fallbacks of steps 3 and 5 always reach the directive boundary; an `InternalEvalException` propagates as today; a `RefusalException` becomes U13's leaf.
     Each guard is stored relative to the join or connective that encloses its leaf, and the full guard is composed at the root.
   - A step is one transition of the machine, `nf` included, counted per directive and reset where the directive starts; the limit is a constant beside `maximumFrameDepth`, with no flag or setting (U7b), and below the frame cap's headroom, so depth cannot overflow first; a `StackOverflow` after the counter has started counts as gave-up.
     Running out with no catching frame gives `gave-up [TRUE]` at the directive, and `UpdateThunk` never writes back a value that carries a `gave-up` (§4.5).
   - The then-arm is evaluated first, in source order.
     A ledger write, or a regulative or deontic frame, reached under a pending condition raises `Stuck` naming the guard's inputs, and so does a join or a leaf that reaches a site outside §4.3's table.
     A result holding a leaf or a `gave-up` exits 1 for `#EVAL` and `#ASSERT` and gets its own JSON kind (§4.7.4), except U13b's single refusal under every assignment, which is that refusal; a trace shows each arm as a child labelled with its path condition.
   - T6's `presumed` counts a default forced in any arm, with W8's event tagged by the arm's path condition (§5).
6. **Service and MCP report routes**, the batch row status, the planner reading residuals from evaluation instead of only from the static ladder tree, and the counts reported (U7b, U3b).
   The planner's questions go to the solver through the same lowering (§4.7.3, D1); every evaluation's own boundary stays propositional (DU3b).
   Rows 54 and 55; row 53 lands with the `TYPICALLY` work's W3, W4 and W8 rather than with a step here.
   **It depends on work outside this spec**, #530 (W1) having merged: W1's placeholders extended to every input that is not a `MAYBE`, and lazy binding on the direct path, neither of which has a W number (§6); the presumption switch, W3 and W4, before the residual planner, so that a default orders questions and never answers one; and W8, then T6, for `presumed`.
   Deploying z3 to the service hosts is an outward action, and Meng's: this step's PR adds z3 to `nix/jl4-service/configuration.nix` and to the runtime stage of `Dockerfile.jl4-service` (`debian:bookworm-slim`, `:34`), and the planner degrades by name where z3 is absent (D1).
   **Documentation:** a page under `doc/` for the report routes, the MCP tool and the batch status "undetermined", linked from `doc/SUMMARY.md`, stating the limits: the propositional boundary, z3 for the planner only, and what an empty CSV cell means.
   _Assumed, not ruled:_
   - On every path, direct, service wrapper, deontic wrapper and `l4 batch`, the boundary decision, the report and C5 apply to the exported function's own result and body, not to the wrapper's `JUST` (§6): either the `JUST` is unwrapped before reporting, or a decode failure raises so that the `#EVAL` is the bare call; either way the root bare-result rule of step 1 then applies to the function's own result (§6).
   - Routes `…/evaluation/residual` and `…/evaluation/k3`, with batch equivalents; `/evaluation` keeps the default report, and `FnArguments` stays lenient.
     A top-level `"report"` goes on every evaluation and batch response.
     What the batch request's OPA-shaped `knownOutcomeStyle` and `unknownOutcomeStyle` (`jl4-service/src/Types.hs:392-393`) do once reports exist is pending the open question in §9 (O4).
   - Under the default report an undetermined, guarded-leaf or gave-up result is a 422, with MCP's `isError`; the residual and K3 routes return 200; a scope-pending `TRUE` is 200.
     K3's unknown is a string tag, never JSON `null`, which the wire already uses for other things.
   - One three-way parse, absent, `null` or `{}`, or a value, is shared by `/evaluation`, batch and MCP, and an MCP argument that fails to parse is rejected with -32602, never read as absent.
     W1's placeholders map back to their input's name and §4.8 provenance in `needs` and in the printed residual.
     An empty CSV cell stays `null`, so it is Declined and never defaulted, while a column left out is absent and takes its default; the doc page says so.
   - MCP gets one extra tool per function for the residual report, with `required: []`, mirrored in WebMCP; `needs` gives both the L4 name and the wire key, and the residual prints unsanitised.
     `l4 batch --validate-only` warns on an absent or `null` input, without marking the row invalid.
     Whether a case that hits the resource limit stops failing the whole batch is not this step's to change; it is pending the open question in §9 (O5).
     Deontic functions are accepted, and their regulative sites stay `Stuck`.
   - The residual planner sits beside `/query-plan` on a route of its own, so the ladder's atom ids stay joinable with `GET /ladder`; the language server's and the browser's planners stay on the static tree.
     It re-evaluates with every supplied value, presumption off, and adds as assertions only answers to askable atoms that are not inputs (§4.7.3); it ranks by §25f's information gain with T4's priors, rolled up per input for atoms that cannot be asked.
   - z3: a pure SMT-LIB2 emitter in `jl4-core`, behind an interface narrow enough for an `sbv` implementation to replace it (R-V6), and one subprocess driver shared by the service and the CLI.
     At startup, `Z3_EXE` set but missing refuses to start, and z3 absent gives a named degradation in every planner response; the per-check timeout is set from a measurement of z3's latency per planner request against the evaluation timeout.
7. **The two TypeScript evaluators** (U10, U10b).
   The shared L4 cases run through the Haskell evaluator and the visualizer's `eval.ts` as each step makes their Haskell answer final: rows 49, 50 and 69 from step 3, rows 4 and 7 from step 4, and row 19 from step 5.
   Row 69 is U10's "`FALSE AND` a call that errors", which this list had dropped.
   `eval.ts` is replaced by a call after step 6, which keeps U10's ruled timing, but the call goes to the language server's `l4/evalApp` (`jl4-lsp/src/LSP/L4/Actions.hs:134`), and to the browser build's WASM shim, which does not handle `l4/evalApp` today (`ts-apps/jl4-web/src/lib/wasm/wasm-message-transports.ts`), not to step 6's routes; so building it waits on the outcomes of steps 3 to 5, not on step 6.
   `ladder-core`'s `nodeValue` (`layout.ts:209-268`) is kept permanently, held to the Haskell evaluator on the connective cases with each call's engine value fed in as a pin, with the tautology case (it stays `Undetermined`) and the error case (it has no error value) listed as known divergences; the `IMPLIES` case expects value `TRUE` and verdict `Undetermined` against `verdictFor` and both `verdictOf`s, extending `verdict.test.ts`, whose existing case at `:84-90` asserts the verdict only, on a hand-built tree.
   _Assumed, not ruled:_
   - The ladder users see is `LadderFlow`, mounted by the VS Code webview and jl4-web (`ts-apps/webview/src/routes/+page.svelte:22`, `ts-apps/jl4-web/src/routes/+page.svelte:43`), whose only evaluator is `eval.ts` (`ladder.svelte.ts:460`); it replaces `Evaluator.eval` with a value function exported from `ladder-core`, `nodeValue` over the ladder's tree, with engine pins on call nodes only.
     A compound leaf stays askable, so row 5, which the translator draws as one opaque leaf, is not a connective case; `LadderSvg` and `LadderModel` are left alone.
   - `l4/evalApp` already types its arguments and its value as `UBoolValue` on the Haskell side (`jl4-lsp/src/LSP/L4/Viz/CustomProtocol.hs:31`, `:39`); the TypeScript schema (`ts-shared/viz-expr/eval-on-backend.ts:12`, `:36`) and `toBoolExpr`'s `UnknownV -> error "impossible for now"` (`jl4-lsp/src/LSP/L4/Viz/Ladder.hs:598`) change, and the request returns a tagged outcome.
     Children are walked left to right, and no call is sent for a call node the short circuit skips; a failed call pins `UnknownV` with the error text and never aborts the recompute; answered section `GIVEN` leaves go on the call as `WITH` bindings.
   - A `jl4-test` spec emits each shared case's ladder tree, as JSON, with its Haskell outcomes, into one committed fixture, and fails when the committed copy differs; the `node:test` and `vitest` suites read that fixture.
     From step 4, `nodeValue` is compared with the K3 report on the connective cases, with row 7's divergence recorded against the default report only.
     `charge-generator` and `regcf-wizard`, which draw the service's ladders with `ladder-core`, are left as they are; their pins are not engine values.
     No shipped ladder, the webview's or jl4-web's, exposes `respectDefaults`, so the call carries no presumption toggle; the standalone playground does (`ts-shared/ladder-svg/standalone/playground.ts:78`, `:392`).

---

## 9. Open rulings

Each is a card on the bench "Unknowns and Defaults" (claude.ai artifact `XQk522h6PN2xv8YFPhogJc`, db collection `l4-unknowns-defaults-1001`), where an independent skeptic's objection and a revised recommendation sit beside it; U8 and U9 share cards with `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` T4 and T3.
A ruling is recorded here when it is made.
Line numbers quoted inside the cards of the bench "Symbolic Evaluation Conflicts", such as §4.5:380 or §7:752, are against this spec at `6c2096ff9`, the revision that bench was built from, and do not resolve against later revisions.

### U1 — Semantics: left-sequential strong Kleene with residual values

**The question.** Which of §4.1's candidates is the evaluator's semantics of an unknown?
**RULED 2026-10-01.** Meng marked `accept` on bench card U1 at 09:55:58Z, with the note _"Do we have commutativity?"_ The ruling, as printed on the card: Kleene tables on known values, left-to-right order as today, an undecided Boolean returned as a residual, implemented in the built-in connective functions. Condition: an atom is identified by its evaluated term (operator, known operand values, unknown inputs), never by source position, and `older 18 AND NOT older 65` is a §7 positive control. `x OR NOT x` is settled at the boundary, not inside the evaluator (U3).
**The answer to the note**, as printed on card U1b: on values over {TRUE, FALSE, unknown}, yes; the strong Kleene tables are symmetric. With errors and non-termination, no, by design: `FALSE AND (1/0 > 0)` is FALSE and `(1/0 > 0) AND FALSE` raises, because left-to-right order is what keeps every fully supplied directive's answer unchanged (§4.3). Residuals commute as Boolean functions; `IMPLIES` does not commute in any logic; FEEL's connectives commute even with errors, because FEEL turns an error into `null`.
**AMENDED 2026-10-01**, by bench card U1b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: Everything U1 ruled, plus the following. `--unknowns k3` is true strong Kleene: atoms only, no tautology settling, as #526 §8 step 3 already says. Deciding a residual at the boundary is named "propositional supervaluation of a Boolean residual", with its two gaps stated in §4.1–4.2 and on the DMN limits page: atoms are independent, and non-Boolean results are not settled. That page also records `x OR NOT x` (L4 TRUE at the boundary, FEEL `null`) and `IF` on an unknown condition (FEEL takes the else arm). Every consumer of an evaluation outcome gets an explicit residual arm, listed by site in the spec (API, diagnostics, `l4 run` exit code, LSP inspector and rules, Catala), with no wildcard arm over the new outcome. An undetermined assertion exits 1, as a stuck one does today. Positive controls: `older 18 AND NOT older 65`, `age >= 18 OR age < 18`, `IF (x OR NOT x) THEN 1 ELSE 2`, and `#ASSERT x AND y` / `#ASSERT NOT (x AND y)` both undetermined.
**ANSWERED 2026-10-01**, by bench card C2 (Symbolic Evaluation Conflicts), which an independent skeptic reviewed before Meng saw it. Meng marked `accept`, option A at 14:04:29Z, with no note. The answer, as the card printed it: **Option A.** The K3 report prints the K3 quotient of the residual: atoms are `unknown`, and error and give-up guards are kept as U11b says ("unknown; errors if _x_"). So `x OR NOT x` and `age >= 18 OR age < 18` show `unknown`, agreeing with FEEL and `nodeValue`. U1b and U7b both stand unamended. Fill §4.7.4's K3 cell with this, and state that `#ASSERT x OR NOT x` is satisfied under the default report and undetermined (exit 1) under K3. **Option B**, the card as first drafted: every report shows the boundary's decision. That reverses U1b's K3 clause, so the report needs another name, since it would no longer be strong Kleene, and the DMN limits page must say it disagrees with FEEL. I recommend A. Record it in #526 §9 as answering C2, with no amendment to U1b or U7b.
Note (Track B audit, 2026-10-02): U1b's list of outcome consumers, "listed by site in the spec", is longer in the tree than the card's list, which names the API, diagnostics, the `l4 run` exit code, the LSP inspector and rules, and Catala; §4.7.4 now lists every site found, and each gets the explicit arm U1b asks for.

### U2 — Step 0 ships in two-valued mode

**The question.** Replace the `IF` rewrite of `AND`/`OR`/`IMPLIES`/`NOT` with frames even if the lift is never switched on?
**RULED 2026-10-01.** Meng marked `accept` on bench card U2 at 09:56:10Z, with no note. The ruling, as printed on the card: Give the built-in connectives their own frames, flag off, and delete or replace the unreachable rewrite at `Machine.hs:1198-1205`. In the same change, update the service's reasoning tree and jl4-mlir's mirrored trace shape and parity harness. Success: the `IF` sub-trees disappear from the golden and jl4-mlir parity holds.
**AMENDED 2026-10-01**, by bench card U2b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: The frames live in the built-in values, through a new lazy value form modelled on `ValROp`, so indirect calls get them. jl4-mlir's by-name mirror (`synthesizeBoolDesugar`/`synthesizeNotDesugar`) is deleted, not updated; the eager codegen keeps its short-circuit filter. The same PR adds an `IMPLIES` fixture to the parity-harness corpus whose trace cell must be byte-identical, and records a run in which the trace sub-matrix was read, since it is not a gate. No golden or trace output may name the built-ins' parameters `a` and `b`, and the indirect-call golden is read before it is blessed.
Note (Track B audit, 2026-10-02): U2's "flag off" reads as "before the lift lands"; there is no evaluation mode and no flag (U7b), and C4's strike of "explore mode" from U6b, U8 and U10b did not reach this phrase.

### U3 — Where the decision diagram lives

**The question.** Move `BoolExpr` and the diagram from `jl4-query-plan` into `jl4-core` (or a package below both), so the evaluator can recognise a tautology mid-evaluation and take the right `IF` arm?
**RULED 2026-10-01.** Meng marked `accept` on bench card U3 at 09:56:22Z, with no note. The ruling, as printed on the card: Residuals are decided at the boundary, for Boolean results only; non-Boolean conditionals lose the condition, and the spec says so. Add a §7 count of conditions whose residual is a tautology or contradiction, and make that count the trigger to decide small residuals locally by truth table.
**AMENDED 2026-10-01**, by bench card U3b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: The §7 tautology/contradiction count is reported as a lower bound, and stays the trigger for moving the diagram. A count of conditions whose atoms all read one finite-domain input (BOOLEAN or enumeration) triggers deciding small residuals locally by truth table; the same count over numeric inputs is recorded separately as the trigger for the SMT backend (#526 §4.6). U3's clause that non-Boolean conditionals lose the condition, and that the spec says so, is kept for whatever U4b does not cover.
**ANSWERED 2026-10-01**, by bench card DU3b (Symbolic Evaluation Conflicts), which an independent skeptic reviewed before Meng saw it. Meng marked `accept`, option B at 14:09:03Z, with no note. The answer, as the card printed it: **Option B.** z3 decides only for D1's two consumers, the planner and `l4 prove`. Every evaluation's boundary decision stays U1b's propositional supervaluation, over every atom and on every host, so an answer never depends on whether z3 is installed. The tautology count stays U3's trigger for moving the diagram; the finite-domain and numeric counts become measurements. Revert the three places `6c2096ff9` wrote the dissent into (§4.7.2:440-443, §8 step 4, D1 "What it changes"). **Option A**, the dissent: z3 decides at every boundary. Then z3 is a declared dependency of every host that evaluates (CI, the extension's LSP, `l4`), the browser build's answer is ruled separately, and the golden harness pins one decider. I recommend B. Record it in #526 §9 as answering the dissent, under U3b and D1.

### U4 — Unknown conditions: evaluate the arms, and under what budget

**The question.** Does an `IF`/`BRANCH`/`CONSIDER` on an unknown evaluate its arms and join them (§4.5), and with what bound?
**RULED 2026-10-01.** Meng marked `accept`, option A on bench card U4 at 09:56:50Z, with no note. The ruling, as printed on the card: Join for `IF` and `BRANCH`. Add a cumulative step counter, explore mode only, set from §7's measurement of total steps (not depth). Running out returns an unknown naming the pending condition, never `StackOverflow`. Recursion guarded by an `IF` over an unknown always runs out, and the spec says so. `CONSIDER` on an unknown stays unknown for now.
**AMENDED 2026-10-01**, by bench card C3 (Symbolic Evaluation Conflicts), which an independent skeptic reviewed before Meng saw it. Meng marked `accept` at 14:04:48Z, with no note. The amendment, as the card printed it: **Accept, with two additions.** (1) A strict operation (comparison, arithmetic, selector) applied to `gave-up [c]` returns the leaf with its guard, never a `fresh` atom; strike "a `gave-up`" from §4.6:401. (2) Once the counter runs out, nothing new is evaluated: every pending operand and arm becomes `gave-up` under its own path condition, so values already computed still combine with the leaves. A `gave-up` is never absorbed: it is a guarded leaf as ruled (DU11 below recommends keeping the leaf). Add `(loop m GREATER THAN 0) AND FALSE` as a §4.12 row and a §7 positive control, expected "`FALSE` unless `m GREATER THAN 0`; gave up if so". Record as an amendment to U4 in #526 §9.
**AMENDED 2026-10-01**, by bench card C4 (Symbolic Evaluation Conflicts), which an independent skeptic reviewed before Meng saw it. Meng marked `accept` at 14:06:03Z, with no note. The amendment, as the card printed it: **Accept, with four conditions.** (1) The counter starts the first time a site in §4.3's table receives a term operand, meaning a site that raises `Stuck` today, and not when an input is read or passed along. Correct §4.3:346, §4.5:380, §7:752 and the §4.11 row to match, and add `#EVAL LIST n, <a long determined computation>` as a positive control that must print today's value. (2) It resets per directive, per batch row and per service request. (3) Running out unwinds as today's exceptions do, restoring every thunk it passes (`restoreThunkOnUnwind`), and becomes `gave-up [c]` only at the join or connective that catches it, so no thunk ever caches a give-up. (4) On §7's workload the limit fires before the service's timeout and allocation cap. Record as an amendment to U4, replacing "explore mode only" there and in U4b, and strike the stale "explore mode" in U6b, U8 and U10b.
**AMENDED 2026-10-01**, by bench card U4b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: Join for `IF` and `BRANCH` under the explore-only step counter, as ruled. Inside the evaluator, a non-Boolean join keeps `c ? t : e` and pushes a strict operation that returns a Boolean (a comparison) into each arm; at a result, a field or any non-strict consumer it falls back to the opaque unknown, so U3's boundary promise holds. An error in one arm joins as a guarded error, exactly as TRIPWIRE's error leaf does for `AND`/`OR`, and it always appears in the response with its guard.
C4 (above) replaces "explore-only" here as it does in U4: the counter starts when a site in §4.3's table first receives a term operand.
Note (2026-10-02): C4's "a site that raises `Stuck` today" is read against the tree after build step 1, which makes a `CONSIDER` on an unknown raise; §4.3's conservativity claim is made against the same tree.
Note (Track B audit, 2026-10-02): C3's own control, row 59, is reachable only if C3 (2)'s "nothing new is evaluated" is read as "no closure body is entered once the counter has run out", with literals, constructors, already-evaluated thunks and built-in operations still computing; it is not a ruling, and Meng is asked to confirm it ("Open for Meng", O3, below).

### U5 — Comparisons become atoms (the membrane)

**The question.** Is a comparison over an unknown a residual atom, identified by its evaluated term (§4.6)?
**RULED 2026-10-01.** Meng marked `accept` on bench card U5 at 10:13:28Z, with no note. The ruling, as printed on the card: A comparison over an unknown is an atom identified by its evaluated term: the operator, the normal forms of the known operands, and the unknown inputs. An arithmetic unknown operand gets a fresh atom per evaluation. The spec's soundness claim is made conditional on this, and a helper-called-twice test is added. The spec states how evaluator atoms map to planner questions.
**AMENDED 2026-10-01**, by bench card U5b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: A generated selector applied to an unknown record returns a term, the input plus its field path, not a fresh atom. A comparison over unknowns is an atom keyed by its evaluated term (operator, normal forms of the known operands, unknown operands as terms) and stays askable; the planner matches answers by that key. A Boolean call to an assumed function is an atom keyed by the function plus the normal forms of its arguments, and is askable too. Only unknowns that carry no term (arithmetic results, `IF` joins, non-Boolean assumed calls) get fresh atoms, and the planner never asks about those; it asks for the inputs they read. Tests: a helper called twice with different thresholds, and `d's age AT LEAST 18 AND NOT d's age AT LEAST 18` deciding FALSE at the boundary.
**AMENDED 2026-10-01**, by bench card C1 (Symbolic Evaluation Conflicts), which an independent skeptic reviewed before Meng saw it. Meng marked `accept` at 14:03:30Z, with no note. The amendment, as the card printed it: **Accept, with three conditions.** (1) A partial built-in (`DIVIDED BY`, `MODULO`, `TO THE POWER OF`) applied to a term emits its definedness guard as a U11b leaf before the term is shared or compared, as R-V2 does for `l4 prove`. (2) U6b's identity rule extends from "the same unknown input" to "the same keyed term", keeping U6b's type exclusion and the guard of (1). (3) Askability gets its own rule: an atom is askable if and only if its term contains no built-in operation, no join and no non-Boolean assumed call; for any other atom the planner asks for the inputs it reads. Keep `fresh` for a `CONSIDER` on a term and an excluded-type equality. Record as amendments to U5b, U6 and U6b in #526 §9, and settle §4.2:300 to match.

### U6 — An unknown equals itself

**The question.** Is `x EQUALS x` `TRUE` when `x` is unknown?
**RULED 2026-10-01.** Meng marked `accept` on bench card U6 at 10:14:10Z, with no note. The ruling, as printed on the card: An identity rule in `runBinOpEquals`: the same unknown input on both sides gives a literal `TRUE`, for numbers, strings, dates and times, lists and constructors. Functions and obligations keep today's error. Derived unknowns (`n PLUS 1 EQUALS n PLUS 1`) stay comparison atoms. Fix the right-operand misdiagnosis in build step 1.
C1 (bench card C1, Symbolic Evaluation Conflicts, 14:03:30Z, recorded in full under U5b) amends this: derived unknowns are keyed by their term, so `n PLUS 1 EQUALS n PLUS 1` is decided by the identity rule, with the partial built-ins' definedness guard emitted first.
**AMENDED 2026-10-01**, by bench card U6b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: The unknown carries its declared type (`ValAssumed` gains the type `evalAssume` already has), and `runBinOpEquals` applies the identity rule when the same unknown input is on both sides and that type has no function or `CONTRACT` component anywhere inside it. A type variable or unsolved inference variable counts as excluded. Excluded types stay unknown in explore mode rather than becoming a definite error. Only a bare function or `CONTRACT` type raises today's unsupported-equality error. `typeHasFunctionComponent` is lifted out of DMN's `where` clause, with its component-type map, for reuse. The right-operand misdiagnosis is fixed in build step 1.
C1 (recorded in full under U5b) amends this: the identity rule extends from "the same unknown input on both sides" to "the same keyed term on both sides", keeping the type exclusion and the guard of C1 (1).
Note (C4, 2026-10-01): "explore mode" here reads as the state in which the step counter has started, that is, after a site in §4.3's table has received a term operand; there is no evaluation mode (U7b), and C4 is recorded under U4.

### U7 — The switch is per evaluation

**The question.** CLI flag and service mode, no directive (§6)?
**RULED 2026-10-01.** Meng marked `accept` on bench card U7 at 10:16:06Z with the note _"This affects purity and feels tantamount to a dynamically chosen effect system. Footgun. Discuss."_ The ruling, as printed on the card: The caller decides, never the module: CLI flag, service request field (following `evalBackend`'s precedent), _and_ a language-server setting and a golden-harness option so explore mode can be tested. No new directive, because every exporter would have to learn it. "Nothing changes with the flag off" is scoped to committed goldens.
**AMENDED 2026-10-01**, by bench card U7b, which an independent skeptic reviewed, ruled by Meng in chat with its word LAMPSHADE. This answers his note: the lift changes only directives that are stuck today (§4.3), so every evaluation is lifted and there is no evaluation mode. What the caller chooses is the report, never the computation. The amendment, as the card printed it: Every evaluation is lifted; there is no evaluation mode. The caller chooses only how an undetermined result is reported: as today's "I needed to know the value of …" (the default, naming every input it waits on), as K3 "unknown", or as the residual itself. The language server and the golden harness show the default report and gain no evaluation setting. On the service the report choice cannot be dropped silently: its own route (as `/query-plan` has) or rejection of unknown keys, and every response states its report. On MCP it is a separate tool or a listed capability, never a reserved argument. In `l4 batch` an undetermined row is a row status, not a failure, so it never trips stop-on-error. The exit code for an undetermined directive is ranked explicitly against the 2026-08-01 ruling that a failed assertion exits 0.
**AMENDED 2026-10-01**, by bench card C5 (Symbolic Evaluation Conflicts), which an independent skeptic reviewed before Meng saw it. Meng marked `accept`, option A1 at 14:06:59Z, with no note. The amendment, as the card printed it: **Option A1.** When the directive's expression, or the body of the function it calls, is a top-level `IMPLIES` with an undetermined scope, the default report gives the value _and_ a named scope-pending field: "`TRUE`; whether it applies needs _x_". The value stands: exit 0, and an `#ASSERT` is satisfied, as `l4 verify`'s vacuity note already does. The trigger matches the planner's: a nested `IMPLIES` does not fire it. **Option A2.** The same trigger, but the result is undetermined (exit 1) until the scope is known. **Option B.** A bare `TRUE`; consumers that need the seam use the residual report. I recommend A1. Record it under U7b and in §4.7.4's table (it is a property of the default report, not of U10's evaluators), add the outcome to every consumer arm U1b lists, and add `TRUE AND (x IMPLIES TRUE)` and `(x IMPLIES TRUE) AND (y IMPLIES TRUE)` to §4.12.
C2 (recorded in full under U1b) answers which computation the K3 report shows: the K3 quotient of the residual, so U7b stands unamended.
Note (Track B audit, 2026-10-02): the card calls the 2026-08-01 ruling one "that a failed assertion exits 0", and the in-tree record of that ruling says otherwise: "Only the crash was ruled on; widening this to assertions is a separate decision" (`jl4/app/L4/Cli/Run.hs:83-86`).
The card is quoted as printed; §4.7.4 states the ranking against the ruling as recorded, and its outcome, exit 1 for an undetermined directive, is unchanged, because the ruling counts `Stuck` as a crash (`:88-94`).

### U8 — Presumptions in explore mode

Amended the same day by bench card TU-presume-b, recorded in full in `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` §5.

**The question.** When the lift is on, does an unsupplied `TYPICALLY` input take its default (marked as presumed) or stay an atom whose default is a prior (§5)?
**RULED 2026-10-01**, on bench card TU-presume, shared with `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` T4: Meng marked `accept` at 09:54:00Z, with no note. The ruling is recorded in full at T4. In short, one presumption switch applies to every evaluation, decide mode included. It is on by default and lands with that spec's W3/W4, not with explore mode. With it off, an absent input with a default is treated as absent with none: stuck in decide mode, unknown in explore mode. `null` never takes a default. The "presuming _x_" mark is the `presumed` list of T6. With presumption off, only boolean defaults become planner priors.
Note (C4, 2026-10-01): "explore mode" here reads as the state in which the step counter has started, that is, after a site in §4.3's table has received a term operand; there is no evaluation mode (U7b), and C4 is recorded under U4.

### U9 — The wire's three absences

Amended the same day by bench card TU-wire-b, recorded in full in `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` §5.

**The question.** The service distinguishes a missing field, `null` and `{}` (§2.5). What does each mean?
**RULED 2026-10-01**, on bench card TU-wire, shared with `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` T3: Meng marked `accept`, option B, at 09:53:17Z, with no note. The ruling is recorded in full at T3. Missing is `Left`: not asked, so a default applies. `null` is `Right Nothing`, "don't know", and never takes a default. `{}` means `null` until it is retired, which happens after the service is instrumented to show who sends it. The cause of today's silent FALSE, `fromMaybe FALSE` at `CodeGen.hs:239, 335, 603`, is removed.

### U10 — The ladder's TypeScript evaluator

**The question.** Keep §3.4's second evaluator, or make the ladder ask the Haskell one?
**RULED 2026-10-01.** Meng marked `accept` on bench card U10 at 10:16:33Z with the note _"Does this cure the objection?"_ The ruling, as printed on the card: When build step 3 lands, add shared L4 cases run through both TypeScript evaluators and the Haskell one, each with its expected value: a call with an unknown argument whose body decides anyway, `FALSE AND` a call that errors, and `x OR NOT x`. Follow `verdict.test.ts`'s pattern. Replace both with a call after service explore mode. Fix §8 step 7 to match.
**The answer to the note:** partly. It cures the first objection by testing L4 cases rather than a truth table, as the second-round skeptic confirmed. But `ladder-core`'s `nodeValue` cannot agree with the Haskell evaluator on every case, by design, which U10b settles.
**AMENDED 2026-10-01**, by bench card U10b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: When build step 3 lands, the shared cases run through the Haskell evaluator and the visualizer's `eval.ts`, which is then replaced by a call after service explore mode. `ladder-core`'s `nodeValue` is kept permanently and held to the Haskell evaluator on the connective cases, with each call's engine value fed in as a pin; the tautology case (it stays Undetermined, conservatively) and the error case (it has no error value) are listed as known divergences. The `IMPLIES` case expects value TRUE and verdict Undetermined, and runs against `verdictFor` and both `verdictOf`s, extending `verdict.test.ts`. #526 §8 step 7 is corrected to match.
Note (Track B audit, 2026-10-02): U10's case "`FALSE AND` a call that errors" had dropped out of §8 step 7 and is restored there as row 69; `eval.ts` runs behind the language server's `l4/evalApp` or the browser build's WASM shim, never the service, so the call that replaces it goes to `l4/evalApp`, and "after service explore mode" keeps only its timing (§8 step 7).
The shared cases are also staged rather than all added when step 3 lands, as U10 and U10b say: rows 4 and 7 join at step 4 and row 19 at step 5, because their Haskell answers are not final before those steps.
Note (C4, 2026-10-01): "explore mode" here reads as the state in which the step counter has started, that is, after a site in §4.3's table has received a term operand; there is no evaluation mode (U7b), and C4 is recorded under U4.

### U11 — An error on the right of an undecided left

**The question.** `x AND (1 DIVIDED BY 0 > 0)` with `x` unknown: the right operand's error (as (b) gives), or unknown?
**RULED 2026-10-01.** Meng marked `accept`, option C on bench card U11 at 10:16:42Z, with no note. The ruling, as printed on the card: Add an error leaf to the residual: shown in the result, raised only if its guard becomes TRUE. Divergence on an unknown is caught by PETROL's step counter ("gave up; needed _x_"). The same rule covers an error in an `IF` arm.
**AMENDED 2026-10-01**, by bench card U11b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: A residual that contains an error leaf is never absorbed: `p AND FALSE`, `p OR TRUE` and boundary deciding (U3) keep it as "FALSE unless _x_; errors if _x_". The known-or-not reading gives an error-leaf residual its own outcome, never a bare unknown, carried on the wire, in U10's shared cases, in U1b's list of outcome consumers, in the service's explore response and under `--unknowns k3`. A non-Boolean arm's error is U4b's guarded error, one mechanism, not a second marker. Positive control: the probe above gives that outcome for unknown `x`, and the error for `x` TRUE.
**ANSWERED 2026-10-01**, by bench card DU11 (Symbolic Evaluation Conflicts), which an independent skeptic reviewed before Meng saw it. Meng marked `accept`, option B at 14:08:10Z, with no note. The answer, as the card printed it: **Option B: decline the dissent.** Keep the error leaf in the residual as U11 and U11b ruled, and add the one rule the spec lacks: a `CONSIDER` on a term carries the scrutinee's guarded leaves into its result. **Option A: accept the store**, on two conditions. Entries are cached on the thunk and replayed on every serve, conjoined with the reader's path condition, the way `ctxReads`/`WHNFWhen` already work (`Machine.hs:239-243`, `:1919-1943`). And a non-empty store is its own outcome constructor, never a field beside a decided value. Add the shared-argument case and `#ASSERT NOT (x AND (1 DIVIDED BY 0 GREATER THAN 0))`, which must not report satisfied, as positive controls. I recommend B. Record it in #526 §9 as answering the dissent, under U11b.

### U12 — The ruling the negation-as-failure spec left open

**The question.** `NEGATION-AS-FAILURE-SPEC.md` open question 2, whether `kand`/`kor`/`knot` ship as a library.
**RULED 2026-10-01.** Meng marked `accept` on bench card U12 at 10:16:54Z, with no note. The ruling, as printed on the card: Decline the library if LIMBO and CLICKER are accepted. Record in `NEGATION-AS-FAILURE-SPEC.md` that this reverses its leaning, and that a data-borne `NOTHING` still needs `CONSIDER` (the library can be revisited if that demand appears). Update `negation-as-failure.md:60-63` in the same change, and move the experiment under a checked glob so it cannot rot.
Its condition is met: U1 and U7 are both accepted. The answer is recorded in `specs/done/NEGATION-AS-FAILURE-SPEC.md` as well. **AMENDED 2026-10-01**, by bench card U12b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: Label `jl4/experiments/negation-as-failure-examples.l4` and both doc pages as "truth-functional strong Kleene (#526 §4.1(a))", not as the lift, everywhere the word "lift" refers to it (file `:79-85`, NAF spec `:3`, `:5`, `:23`, #526 §3.1). Add `#ASSERT (NOTHING `kor` (knot NOTHING)) EQUALS NOTHING` with a comment that the residual evaluator decides `x OR NOT x` TRUE at the boundary. Move the file under a checked glob; turn both doc links into relative links to the new path, and update the citations (NAF spec `:5`, `:274`; #526 §3.1; the file's own line 2). The recorded condition now reads as met, U1 and U7 being accepted.

### U13 — A refusal reached only under an undetermined guard

**The question.** What does a `REFUSE`, the prelude's `TBD` included, report when it is reached only under an undetermined guard: the right operand of a connective whose left operand is a term, as in `x AND TBD`, or an arm of a join, as when `daydate`'s `YMD` is called with an unknown year?
**RULED 2026-10-02 (RAINCHECK, in chat).** Meng fired RAINCHECK on the Track B audit's item M1, choosing its option A.
The ruling, as fired:

```text
M1, option A: record in #526 §9 as new ruling U13: a REFUSE (TBD included) reached only under an undetermined guard becomes a guarded refusal leaf, distinct from U11's error leaf and never absorbed, printed "FALSE unless x; refuses (<reason>) if x"; the directive is undetermined (exit 1; batch status undetermined; the reason listed); never a determinate refusal with exit 0 (option B); interim (C), Stuck naming the guard's inputs, until step 5 builds the leaf; restate the Machine.hs:840-849 invariant as "a refusal is never turned into a value"; push to #526 with TIPPEX
```

Split into its clauses:

1. A `REFUSE` (`TBD` included) reached only under an undetermined guard becomes a guarded refusal leaf, distinct from U11's error leaf and never absorbed, printed `"FALSE unless x; refuses (<reason>) if x"`.
2. The directive is undetermined (exit 1; batch status undetermined; the reason listed).
3. Never a determinate refusal with exit 0 (option B).
4. Interim (C), `Stuck` naming the guard's inputs, until step 5 builds the leaf.
5. Restate the `Machine.hs:840-849` invariant as "a refusal is never turned into a value".

**What raised it.** The Track B audit of 2026-10-02 found that neither this spec nor any ruling said what a refusal does under an unknown guard.
Its evidence, each item re-read on `6ed297629` when this was recorded:

- Before this ruling the spec never addressed `REFUSE`: it contained neither "REFUSE" nor "TBD", and "refus" occurred only for the wire's and `l4 batch`'s refusal of a missing input and the lowering's refusal of `LN`, `SQRT` and `^`; U11 rules an error leaf only.
- A refusal is not an error: "A REFUSAL is not a crash … (Errors keep exit 1; the two must not be conflated, which is the whole point of REFUSE.)" (`jl4/app/L4/Cli/Run.hs:143-146`).
  A refusing `#EVAL` exits 0 with a JSON kind of its own (`:191-195`), and `l4 batch` gives a refused row a status of its own and does not stop (`jl4/app/L4/Cli/Batch.hs:364-370`).
- The invariant at `jl4-core/src/L4/EvaluateLazy/Machine.hs:838-849`: `tryEval` is the only `try` over an `EvalException`, so "nothing between a 'Refuse' and the directive that demanded it can observe the refusal or turn it into a value: not a CONSIDER arm, not a boolean connective", and "THIS IS AN INVARIANT, not an accident of the current code: a static refusal analysis is only sound while it holds".
- Beside the invariant, the docstring of `unwindFrame` that it says a second `try` "would also have to reckon with" (`:849`): its `RestoreCurrentParty` clause calls the unwind's restoring of the acting party "defense in depth" today, which "becomes load-bearing the moment anything catches an 'EvalException' and resumes evaluation mid-directive" (`:720-728`).
- R7 (`specs/todo/PROPS-REDTEAM-2026-09-03.md:492-502`) specifies a refusal as "a throw at force, never a value", and records that "Refusal is order-dependent under lazy `AND`/`OR`" and "well-defined only if the verifier models left-to-right demand".
- `TBD MEANS REFUSE "TBD: this rule has not been written yet"` (`jl4-core/libraries/prelude.l4:767`).
- `YMD` (`jl4-core/libraries/daydate.l4:135-142`) refuses in its else arm (`:140`), which a join evaluates whenever the year is unknown.
  The corpus calls it with a function's own input, `y` at `jl4/examples/ok/closing-the-loop/feiertage.l4:133`, whose `GIVEN` is at `:130`, so the year is whatever that function's caller supplies, and an unknown one reaches the refusing arm of a shipped library.
- Today both cases are `Stuck` on the guard: `x AND TBD` and `IF x THEN TBD ELSE FALSE` name `x`, while `TBD AND x` refuses and `FALSE AND TBD` is `FALSE` (rows 73 to 76, probes `t07` to `t10`).

**Options declined.** Option B, a determinate refusal with exit 0, answers "refuses" where the answer is `FALSE` whenever `x` is `FALSE`, and nothing would mark it as wrong.
Option C, undetermined naming the guard's inputs, is declined as the answer and kept as the interim until build step 5 builds the leaf; the audit's case against keeping it was that a deliberate `TBD` under an unknown condition would then report less than a division by zero does.
Option C is close to today's output but not the same: today's `Stuck` names only the first input it reaches (row 23, "naming only `x`"), and naming every input of the guard is U7b's default report.

**What it changes.** §4.2's grammar gains the leaf `refuses [c] r`, §4.3's connective table gains its row with the interim beside it, §4.5 covers the join case, §4.7.2's hole rule, §4.7.3's questions and §4.7.4's reports carry it, rows 73 to 77, 81 and 82 of §4.12 test it, §8 step 3 carries the interim and step 5 builds the leaf.
The restatement of the invariant is a ruling about the comment at `Machine.hs:838-849`, made in the first change that lets a frame observe a refusal, build step 3, whose interim rewrites one as it unwinds; recording it here edits no code.
On its wording, the restated invariant lets a frame between a `Refuse` and its directive observe the refusal, which the leaf and the interim both need, and forbids only turning it into a value; whether the static refusal analysis that the comment names stays sound under it is for step 3 to check (§10).

**AMENDED 2026-10-02 (YOYO, in chat).** Meng fired YOYO, amending U13 at its skeptic's recommendation (the skeptic's verdict: weakens).
The amendment, as stated when the word was fired:

> U13b, amending RAINCHECK's U13 per its skeptic (verdict weakens), recorded in #526 §9 beside U13 and pushed with TIPPEX: (1) any rule that returns a determined value from a term (§4.5's agreeing arms, §4.6's identity rule) first carries that term's guarded leaves, error and refusal alike, into its result, as DU11 does for CONSIDER; positive controls `IF (x AND TBD) THEN 1 ELSE 1` = "1 unless x; refuses (TBD …) if x", exit 1, and the same with `1 DIVIDED BY 0 GREATER THAN 0` for an error leaf; (2) if no assignment of a residual's atoms escapes every guard, the directive is never TRUE or FALSE: when every leaf is a refusal with one reason it is that refusal, exit 0; otherwise undetermined, listing each leaf; positive control `IF x THEN TBD ELSE TBD` refuses, exit 0; built in steps 4-5

**What U13b changes.** §4.5's agreeing arms and §4.6's identity rule carry the term's guarded leaves, §4.7.2 states the case in which no assignment escapes every guard, rows 78 to 80 of §4.12 are its positive controls and row 82 tests it, and §8 step 4 builds the decision while step 5 builds the leaves.
Clause (2) narrows U13's clauses 2 and 3 for the case in which no assignment escapes every guard: U13 covers a refusal reached only under an undetermined guard, and option B was declined because it answers "refuses" where the answer is `FALSE` whenever `x` is `FALSE`; when every assignment refuses with one reason, neither holds, and the refusal is the answer.

### D1 — Build the evaluator, buy the solver

**The question.** Meng had planned to call an external symbolic evaluator such as Rosette, as a backend under `l4 verify` or elsewhere, and expects the query planner to evolve on top of symbolic evaluation: buy or build?
**RULED 2026-10-01 (HOMEBREW, in chat, 11:42Z).** The ruling, as stated when the word was fired:

1. The symbolic evaluator is built natively in `jl4-core`; it is the lift §4 defines.
2. The solver is bought: z3 as a subprocess, driven by SMT-LIB2, as R-V6 already decided for `l4 prove` (`specs/proposals/VERIFICATION-BACKEND-LOWERING-SPEC.md:370`, "Emit SMT-LIB2 text; shell to a `z3` subprocess; no Haskell solver dependency").
3. One lowering, from the residual term language (§4.2) to SMT-LIB2, serves two consumers: the query planner's arithmetic atoms, and `l4 prove` / `l4 verify`.
4. Rosette is not a backend; it is at most an optional cross-check oracle in testing, as `catala proof` is planned to be for `l4 prove`.

**The hedge, part of the ruling:** keep the residual term language close to SMT-LIB (§4.2's table), so that swapping z3 for cvc5, or adding Rosette later for synthesis, is a change to the lowering and not a redesign.
**What decided it.** One semantics, not two: a Rosette backend lowers L4 into Racket, a second implementation of laziness, left-to-right error order, the regulative and temporal machinery, and `TYPICALLY` with its presumption switch, and this bench found that class of drift repeatedly, between the ladder's TypeScript evaluator and the Haskell one (§3.4), between `l4 batch` and `l4 run` (§4.9), in OpenFisca asserting a different default (`TYPICALLY-ONE-BEHAVIOUR-SPEC.md` §2) and in FEEL's `if` taking the else arm on `null` (U1b); the native lift is conservative by construction (§4.3). Rosette's own architecture is a symbolic VM plus z3, and the VM is the half that must carry L4's semantics exactly, so the solver is the semantics-neutral half worth buying. The consumers run in-process, per request in `jl4-service`: the planner, the wizard, the ladder, traces that cite source lines, residuals printed as L4; a Racket runtime would be a new dependency for the service and the NixOS hosts. The lowering shrinks from all of L4 to the term language of §4.2. The planner evolves from a diagram over the ladder's static tree to planning over what is still unknown after each answer, with the solver settling `age >= 18` and `age < 65` from one answer, which closes the independence gap U1b and U3b record. Rosette would win only for solver-aided programming beyond checking, synthesis of holes or angelic execution, none of which is on the roadmap. The Rosette claims in this entry are recalled; the three Guide quotations in §4.10 are the only ones verified today.
**What it changes.** The lowering of §4.2 to SMT-LIB2 lands with the planner (§8 step 6) and serves `l4 prove`; by DU3b it decides nothing for an evaluation's own boundary, which stays propositional (§4.7.2). U3b's tautology count stays the trigger for moving the diagram, and its finite-domain and numeric counts become measurements (DU3b). `VERIFICATION-BACKEND-LOWERING-SPEC.md` R-V6 gains a paragraph saying its input now includes the residual term language.
**What it costs.** A `z3` binary on every host that runs `jl4-service` with the planner, discovered as R-V6 says (`Z3_EXE`, then `PATH`), and a named degradation when it is absent.
DU3b (recorded in full under U3b, 14:09:03Z) confirms the scope: z3 decides for these two consumers only, and every evaluation's boundary stays propositional on every host.

### Open for Meng (raised 2026-10-02)

These came out of three adversarial reviews of the TIPPEX commits and a verification of the fixes, on 2026-10-02, while Meng was asleep.
Each question below is undecided: the steps it names are written so that they do not depend on the answer, or they point here.
The choices made overnight to keep steps 1 to 3 buildable follow the questions; each is labelled in the text "decided by Claude overnight 2026-10-02, pending Meng's review", and none is a ruling.

**O1. Which reports show U13b's all-guarded refusal?**
The question: under U13b (2), `IF x THEN TBD ELSE TBD` refuses, exit 0, which is a decision over every assignment; C2 has the K3 report read the residual "through the K3 tables, never the boundary's decision", and step 4's rule that the exit code follows the outcome as the chosen report shows it would then give exit 1 under K3.
Options: (a) every report shows the refusal, exit 0; (b) the default report shows the refusal, exit 0, K3 shows the K3 quotient per C2, "unknown; refuses if x; refuses if not x", exit 1, and the residual report prints the residual with the default report's outcome.
Recommendation: (b), which keeps C2 as ruled.
Blocks: build step 4 (§4.7.4, §8 step 4).

**O2. Does U13b (2) apply to a join of any type?**
The question: YOYO's control, `IF x THEN TBD ELSE TBD`, names no type, and `TBD` is polymorphic (`GIVEN a IS A TYPE GIVETH AN a`, `jl4-core/libraries/prelude.l4:764-767`); row 80 types it as a `BOOLEAN`, and at any other type the same structure is U4b's opaque join at a result, undetermined, exit 1.
Options: (a) Boolean results only; (b) any type whose every leaf is one refusal.
Recommendation: (b), since every two-valued completion refuses with that reason whatever the type.
Blocks: build step 5 (§4.7.2, §8 step 5).

**O3. Confirm C3 (2)'s reading.**
The question: C3 (2) says that once the counter runs out "nothing new is evaluated"; read literally, C3's own control, row 59, reports a bare "gave up", as the Track B audit traced by hand and the 2026-10-02 review re-traced.
Options: (a) confirm the narrower reading, "no closure body is entered", under which literals, constructors, already-evaluated thunks and built-in operations still compute; (b) keep the literal reading and change row 59's expected text, which amends C3's ruled control text, since row 59 is C3's card verbatim.
Recommendation: (a); the note under U4 already records the reading.
Blocks: build step 5 (§4.5, §8 step 5).

**O4. What does the service do with `knownOutcomeStyle` and `unknownOutcomeStyle` once reports exist?**
The question: the service batch request accepts both, each a `Maybe OutcomeStyle` over `ValueOnly`, `DecisionReport` and `BaseAttributes` (`jl4-service/src/Types.hs:387-401`), and nothing reads either; U7b says a report choice is never dropped silently, and a client that sets `unknownOutcomeStyle` is choosing one.
Options: (a) keep accepting and ignoring them, with the response's `"report"` saying which report was used; (b) map each onto a report where it corresponds, and reject any value that disagrees with the route's report or has no corresponding report, such as `BaseAttributes`, naming the route to use; (c) reject both with a 400.
Recommendation: (b), which keeps clients written to the OPA shape working where their choice can be honoured and refuses it where it cannot, rather than accepting and ignoring it, which U7b forbids ("the report choice cannot be dropped silently").
Blocks: build step 6 (§8 step 6).

**O5. Should a service batch case that hits the resource limit stop failing the whole batch?**
The question: today the first failing case fails the whole batch (`jl4-service/src/DataPlane.hs:305-308`), and the resource limit is a 500 (`:689`); a per-case status would change inputs with no unknowns at all, outside every ruling and outside §4.3's claim.
Options: (a) a per-case status "error" that does not abort the batch, built in step 6; (b) leave the batch as it is; (c) make it a service change of its own, separate from the lift.
Recommendation: (c).
Blocks: build step 6, which is written not to change it (§8 step 6).

**O6. May `AND FALSE` or `OR TRUE` absorb a `CONSIDER` on a term?**
The question: from step 5 a `CONSIDER` on a term is a `fresh` atom that carries only the scrutinee's guarded leaves (§4.5, DU11), because its arms are not evaluated, and §4.3's table absorbs a term with no leaf under `AND FALSE` and `OR TRUE`.
So with `` `r` MEANS CONSIDER m WHEN JUST z THEN TBD OTHERWISE FALSE ``, `` `r` OR TRUE `` would be `TRUE`, exit 0, while the two-valued run refuses where `m` is `JUST 5` and is `TRUE` where it is `NOTHING` (probes `vf/s4` to `vf/s6`); an erroring arm is absorbed the same way, which is what U11b's and U13's "never absorbed" exist to stop.
This was in the design before the TIPPEX commits; the review of 2026-10-02 found it.
Options: (a) a `CONSIDER` on a term evaluates its arms, as a join does, and carries their leaves, without deciding over them; (b) its `fresh` atom counts as holding a guarded leaf for §4.3's absorption rows, so `` `r` OR TRUE `` stays undetermined; (c) leave it absorbable.
Recommendation: (b), which is loud, needs no new semantics for the arms, and keeps U4's "stays unknown for now"; (a) is the fuller answer if U4's "for now" is reopened.
Blocks: build step 5 (§4.5, §8 step 5).

**Decided by Claude overnight 2026-10-02, pending Meng's review.**

- The two silent regulative sites, `EVERY`'s cast test and the action matcher, raise `Stuck` on an unknown from build step 1, loud over silent (§2.4, §8 step 1, rows 86 to 90).
  This reaches the regulative layer, which §4.6 otherwise leaves out of scope; the alternative, reversing it, keeps today's silent behaviour as §2.4's residue (step 1).
- Before it raises on an unknown, a sub-pattern match checks the branch's already-evaluated later positions, and its unevaluated literals, for a definite mismatch, so row 71 keeps `"second"` (§8 step 1).
  The alternative is to raise at the first unknown, losing row 71's answer (step 1).
- `#ASSERT REFUSED x` keeps today's verdict, failed, exit 0, and `#ASSERT REFUSED e` on a residual with no guarded leaf and no `fresh` atom fails the same way (§2.4, §4.7.4, row 72).
  The alternative is undetermined, exit 1, for every `#ASSERT REFUSED` on an unknown (step 1).
- A determined result whose only terms are bare inputs prints as that value, exit 0, whether or not the counter has started; one that holds any other term is undetermined, exit 1, which keeps today's answer, since each such term was stuck before the lift (§4.7.4, §8 step 3).
  So an `l4 batch` or service-wrapper row whose answer is a residual inside the wrapper's `JUST` is undetermined from step 3, and step 6 makes that output more precise (§6).
  The alternatives are every result that holds a term undetermined once the counter has started, or every term printed as a value, which would let such a batch row score "success" silently (step 3).
- Traces keep each connective operand as a child labelled with its source text and value, and show a skipped operand as skipped (§4.4, §8 step 2).
  The alternative is to drop operand values from the trace, which U2b also allows (step 2).

**Decided by Claude overnight 2026-10-03, pending Meng's review.**

- A skipped connective operand is left out of a text trace and of the service's reasoning, as the `IF`'s untaken arm was, and is drawn, under its source text, only as GraphViz's stub when `showUnevaluated` is on, which no shipped renderer turns on (§4.4, §8 step 2).
  The alternative is a child marked as not evaluated in every trace, which needs a trace node that has no value, and its jl4-mlir mirror (step 2).
- The default report names several inputs in the plural: "I could not continue evaluating, because I needed to know the values of", one name a line, "but they are assumed terms."; one input keeps today's message byte for byte (§8 step 3).
  The alternative keeps the one-input wording and lists the names under it (step 3).
- An undetermined `#ASSERT` keeps JSON kind "assertion" in `l4 run --json`, as a refused one does, with `"undetermined": {"needs": […], "message": …}`, so a consumer counting assertions still counts it; an undetermined `#EVAL` gets kind "undetermined" (§8 step 3).
  The alternative is kind "undetermined" for both, which is §8 step 3's own wording (step 3).

---

## 10. What this spec did not verify

- The service behaviour in §2.5 was measured by the coordinating session, not here; the cause of the section-`GIVEN` prelude failure is the `TYPICALLY` work's trace, read from its record, merged with #530, and not reproduced here.
- Trace output from the LSP was not checked when step 2 was built, beyond `jl4-lsp-test`.
- The `#EVALTRACE` probes printed "no trace captured" on the installed binary, so the trace shape in §2.4 is read from a committed golden, not reproduced.
- Nothing in §4–§8 has been built or timed.
- `TYPICALLY-ONE-BEHAVIOUR-SPEC.md`, which U8 and U9 cite for their full text, is on `unstable` since #525 (present at `6ed297629`) and not on this branch; whichever of the two specs merges second must carry the cross-reference.
  W1 as built, and the L6 cause cited in §2.5, are read from #530's head, `659699e7d`; #530 merged on 2026-10-01 (`6d3a56f75`), and `unstable`'s `CodeGen.hs`, `Backend/Jl4.hs` and `TYPICALLY` spec are identical to that head (`git diff --stat`, empty); #530 itself changed `Backend/Jl4.hs` relative to `6ed297629`, so this spec's `Jl4.hs` line numbers are those of `6ed297629`.
- Two `TYPICALLY` probe results are recorded in §4.12 row 53 and not explained here: a section `GIVEN … TYPICALLY TRUE` read directly by a `#EVAL` in its own section is stuck on the input (probes `p14-typically.l4`, `p18-typ-single.l4`), while the same input read through a rule in the section takes its default (probe `p19-typ-rule.l4`); the census in `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` §2 records the second case as "honoured". The cause was not traced.
- The literature attributions in §4.10 (Kleene 1952, McCarthy, King 1976, van Fraassen 1966, Jones, Gomard and Sestoft 1993) are from memory of the standard references and were not re-read today.
- Of the Rosette claims in §4.10, §4.11 and D1, only the passages quoted from the Rosette Guide (§7.1, §7.2.1 and the Essentials chapter, read 2026-10-01) are verified; term hash-consing, `ite` merging for solvable types and z3 as the default solver are recalled. The PLDI 2014 PDF returned 404 at `homes.cs.washington.edu/~emina/pubs/rosette.pldi14.pdf`, and `klee-se.org/docs/options/` did not show KLEE's budget options, so those are recalled too.
- The guard-idiom count: one line-level `grep` over the 809 `.l4` files under `jl4/examples`, `jl4-core/libraries` and `doc` found no `isJust`/`isNothing` guard and no `AND … DIVIDED` on one line, and five lines with a non-zero guard before an `AND`; a guard split across lines is invisible to it.
  Left-sequential evaluation (U1) preserves every such guard whether or not it was found, which is why the count is not load-bearing.
- What the Track B audit contributed and was not re-derived here: the hand trace by which C3 (2), read literally, leaves row 59 a bare "gave up" (§4.5), which the review of 2026-10-02 re-traced and confirmed; the reading of `UpdateThunk` behind §4.5's rule that a value carrying a `gave-up` is never written back; and that the batch request's `knownOutcomeStyle` and `unknownOutcomeStyle` follow Oracle Intelligent Advisor's Batch Assess shape (§8 step 6), which is the audit's reading of Oracle's documentation.
- Predictions about lifted behaviour that no probe can check before the lift exists: that a residual reaching `EqConstructor3` or a temporal iterator would raise an internal or misleading error (§4.3), that a right operand diverging under a term would hang without step 3's interim counter, that the wrapper's `JUST` keeps the boundary decision and C5 from firing (§6), and that `Batch.hs:388` and `:396`'s wildcards would score an undetermined row "success".
  The iterators' misreport of a bare unknown is not a prediction: it is probed today (`c01`, `c02`).
- The static refusal analysis the comment at `refuseWith` (`Machine.hs:838-849` when this was written) names is the DMN exporter's `D-REFUSE`, over `analyzeSafety` (`jl4-core/src/L4/Dmn/Lower.hs:610`): it certifies that no `REFUSE` is reachable, and step 3's interim only ever replaces a refusal with `Stuck`, so a decide it certifies still never refuses (read, not tested). Whether U13's leaf, at step 5, keeps it sound is not checked.
- Whether §2's probes of 2026-10-01 ran on the store build `jl4-0.1-b69f17a4`, as the probes of 2026-10-02 did, was not recorded; `~/.cabal/bin/l4` points at that build, and was relinked to it on 2026-10-02.
