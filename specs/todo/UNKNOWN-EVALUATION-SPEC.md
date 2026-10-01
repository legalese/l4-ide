# Specification: Evaluating with unknowns — connectives as an algebra, not as `IF`

**Status:** proposed, not built (2026-10-01).
Nothing in this document is in the tree.
Every statement about today's behaviour is a probe result or a `file:line` read on `unstable` at `f9a504b77`, and says which.
Probes ran on the installed `l4` (`~/.cabal/bin/l4`, a store build linked 2026-09-30; the only evaluator-path commit after 2026-09-26 is `8848df744`, `WHOSE`, which touches none of the code cited here).
Probe files are in the session scratchpad, not in the tree.

**Trigger:** SCHRODINGER, widened by Meng on 2026-10-01: _"continue your investigation of the evaluator lift with kand. It sounds like we'll need to redo the rewriting-to-IF in favour of something more algebraically principled."_

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

### 2.4 Two defects the probes found on the way

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

### 3.1 `DefBool` and the Kleene lift, user-level (`NEGATION-AS-FAILURE-SPEC.md`)

`DefBool` is `MAYBE BOOLEAN`, and `kand`, `kor`, `knot` are strong Kleene over it, written in L4 (`jl4/experiments/negation-as-failure-examples.l4:89-124`).
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
So the ladder already has the semantics this spec proposes, implemented a second time, in another language, over a different tree.

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

## 4. The design

### 4.1 Three candidates

**(a) Strong Kleene over a new `ValUnknown`.**
A third Boolean value with the K3 tables, `U ∧ F = F`, `U ∧ T = U`, `U ∨ T = T`, `¬U = U`.
The question it leaves open is _evaluation order_: the tables say what the answer is, not what gets evaluated, and an `AND` whose right operand errors or diverges needs an answer.

**(b) Left-sequential strong Kleene.**
Evaluate the left operand.
If it is `FALSE` (for `AND`), stop with `FALSE`, exactly as today; if `TRUE`, the answer is the right operand, exactly as today.
Only if it is **unknown** is the right operand evaluated, and then the K3 table applies: right `FALSE` gives `FALSE`, otherwise unknown.
This is the K3 table on the three values, with the order in which a fourth outcome, an error or non-termination, can occur kept left-to-right, which is McCarthy's sequential reading.
It does not need parallel evaluation: Plotkin's parallel-or, which would make `⊥ ∨ T = T`, is not proposed.

**(c) Residualisation.**
An undecided Boolean is not a bare `U` but a formula over the unknown atoms it depends on, an element of the free Boolean algebra on those atoms, with the `IMPLIES` seam kept as a node (§3.7).
K3 is the quotient that forgets the formula: a residual maps to `U` unless it is a tautology or a contradiction.
The residual carries strictly more: `x OR NOT x` is a residual the planner decides `TRUE` and K3 cannot; and it is exactly the shape the planner already consumes (§3.3) and the regulative side already returns (§3.5).

### 4.2 Recommendation: (b)'s evaluation order, (c)'s values

Evaluate connectives left-sequentially as (b) describes, and let an undecided Boolean be a residual as (c) describes.
(a) is not a separate choice, it is what (b) and (c) look like through the K3 quotient, and is the reading every consumer that only wants "known or not" takes.

So the value domain gains one constructor, for Boolean results only:

```haskell
-- proposed, not built
| ValResidual Residual          -- an undecided BOOLEAN

data Residual
  = RAtom   Atom                -- an unknown, with its provenance (§4.8)
  | RNot    Residual
  | RAnd    Residual Residual   -- operands already evaluated, at least one undecided
  | ROr     Residual Residual
  | RImplies Residual Residual  -- the seam, kept (§3.7)
  | RLit    Bool                -- only inside a larger residual
```

The tables, for `AND` (`OR` dual, `IMPLIES` as its own row so the seam survives):

| left         | right         | result             |
| ------------ | ------------- | ------------------ |
| `FALSE`      | not evaluated | `FALSE` (as today) |
| `TRUE`       | `r`           | `r` (as today)     |
| residual `p` | `FALSE`       | `FALSE`            |
| residual `p` | `TRUE`        | `p`                |
| residual `p` | residual `q`  | `RAnd p q`         |
| residual `p` | error / ⊥     | error / ⊥ (U11)    |

`ValAssumed` stays the representation of an unsupplied input and becomes the source of an `RAtom` when it is inspected in a Boolean position, instead of `Stuck`.

### 4.3 Conservativity: what this cannot change

**Claim.** For every directive that does not end in `Stuck` today, the lifted evaluator returns the same value, raises the same error, or fails to terminate, exactly as today.

**Why.** The lift adds transitions only at the sites listed in §2.2, each of which today raises `Stuck`.
`Stuck` cannot be caught in L4 and aborts the whole directive (§2.2).
So a run that never reaches one of those sites takes exactly the same transitions under the lift, and a run that reaches one ended in `Stuck` today.
The left-to-right order of (b) is what makes this hold for `AND` and `OR` themselves: when the left operand is known, the lifted frame does what the `IF` did, including not evaluating the right operand when the left decides.

**Where it changes a stuck directive for the worse.**
A directive that today ends in `Stuck` on the left operand of an `AND` may, under the lift, go on to evaluate a right operand that errors or diverges.
Today that directive reports "needed to know `x`"; lifted, it reports the right operand's error, or does not terminate.
Both are loud, and the first is no less true than before, but "needed to know `x`" was more useful, which is what U11 asks.

**What the claim does not cover.** Anything that is not the evaluator: the printer, the traces, the exporters.
§4.4 is a change to traces in two-valued mode and is not covered by this claim, which is why it is a separate step with a golden to move.

### 4.4 Step 0, in two-valued mode: connectives become frames

Replace the `IfThenElse` bodies of the four built-ins (`Machine.hs:6636-6715`) with frames `AndFrame`, `OrFrame`, `ImpliesFrame`, `NotFrame`, built the way `RBinOp1`/`RBinOp2` are, and delete or replace the unreachable rewrite at `Machine.hs:1198-1205`.
The lift of §4.2 lives in the same frames; a lift written at `:1198` would never fire.
In two-valued mode they compute what the `IF` computed, in the same order.
What changes is what the trace can say: `FALSE OR TRUE` instead of `IF a THEN TRUE ELSE b`.
That moves the `IF` sub-trees out of `lazytrace-exception.golden` (§2.4), changes the service's reasoning tree, and changes the trace shape jl4-mlir mirrors, so jl4-mlir's runtime and parity harness change in the same step; nothing else should move, which the step must measure rather than assume.

This step is worth doing even if the lift is never switched on: the trace stops showing code the author never wrote, and it removes the `IMPLIES` flattening §3.7 objects to.
`BRANCH` can stay as an `IF` chain, because its guards are a first-match ordering, which `IF` expresses exactly; §4.5 decides how an unknown guard behaves there.

### 4.5 `IF`, `BRANCH` and `CONSIDER` on an unknown

**An unknown condition, Boolean-typed `IF`:** evaluate both arms; the result is `(c ∧ t) ∨ (¬c ∧ e)` as a residual, simplified when the arms agree (`IF x THEN TRUE ELSE TRUE` is `TRUE`).
**An unknown condition, any other type:** evaluate both arms; if they are equal (normal-form equality on the values `runBinOpEquals` already supports) the result is that value, otherwise the result is an unknown of that type whose atom set is the union of the condition's and both arms' (§4.6).
**`BRANCH`:** the chain of `IF`s inherits the above; a guard after an unknown one is reached and evaluated, which is the cost §6 measures.
**`CONSIDER` on an unknown scrutinee:** for a Boolean-typed `CONSIDER`, the residual is the disjunction over arms of _scrutinee matches this arm_ and _arm_; this needs atoms of the form `s = C` for an enumeration, which a decision diagram handles only with a constraint that exactly one of them holds (U4).
Until that is ruled, an unknown scrutinee gives an unknown result, with the scrutinee named, and **never** the "no branch" message §2.4 records.

Evaluating both arms is the expensive half of the design and the half that can blow up: nested conditionals on the same unknown evaluate a tree of arms.
U4 asks whether to bound it by a budget, and §6 says how to measure it before deciding.

### 4.6 Comparisons and arithmetic: the membrane

The ladder's §23 already drew the line: the circuit is Boolean, typed data lives inside a leaf, and a predicate is the membrane between them.
The evaluator should draw it in the same place.

- **Arithmetic or string operations on an unknown** (`n PLUS 1`, `CONCAT`) give an unknown of the result type, carrying the set of atoms it depends on; there is no residual arithmetic.
- **A comparison** whose operands include an unknown (`n GREATER THAN 3`, `age AT LEAST 18`) gives a residual **atom**, and the atom is the comparison: its identity is the **evaluated term**: the operator, the normal forms of its known operands, and the unknown inputs it reads, never its source position.
  One source position is evaluated many times (a helper called with different known arguments, an `IF` arm, a prelude recursion), and keying by position would make `older 18 AND NOT older 65`, with `older k MEANS age > k`, the contradiction `A AND NOT A`, decided `FALSE` though age 30 makes it `TRUE`.
  An operand that is an arithmetic unknown carrying only its atom set (below) gets a fresh atom per evaluation.
  The planner can then ask "is `age AT LEAST 18`?" and the ladder can draw that atom with its value chip, as §23 describes.
- **A call to an assumed function** (`Machine.hs:1593-1594`, the `TODO`) gives an unknown of its result type, or an atom if the result is Boolean.

The consequence worth stating: the residual is propositional, so two atoms over the same number are independent to it.
`n > 3 AND n < 2` is a residual, not `FALSE`.
With atoms keyed by evaluated term, that is a loss of precision, not a wrong answer: it can say "undetermined" where the truth is "no", never the reverse.
Keyed any coarser, the guarantee does not hold.
Arithmetic reasoning over residuals belongs to an SMT backend (`specs/proposals/VERIFICATION-BACKEND-LOWERING-SPEC.md`), not to this evaluator.

### 4.7 Equality, lists and quantifiers

**Equality.** `x EQUALS x` is stuck today (§2.3).
Over Booleans it becomes the residual `x ↔ x`, which the planner decides `TRUE`.
Over other types, an atom compared with itself is equal, and any other comparison involving an unknown is an atom as in §4.6 (U6).
**Lists of known spine.** `and`, `or`, `all`, `any` are prelude recursions over `CONSIDER` and `AND`/`OR` (`prelude.l4:223-257`), so they inherit the connectives' behaviour with no change: `and (LIST TRUE, x, FALSE)` becomes `FALSE`.
**Lists of unknown spine** (the list itself unsupplied) meet `CONSIDER` on an unknown, §4.5.
**Regulative `EVERY` / `EACH`** run over the regulative algebra, already three-valued (§3.5), and are out of scope.

### 4.8 Provenance: what an unknown remembers

An `RAtom` carries what `ValAssumed` carries, the input's `Resolved` name, plus why it is unknown:

| kind         | origin                                                             | four-cell (§3.6) |
| ------------ | ------------------------------------------------------------------ | ---------------- |
| `Unsupplied` | an input nobody supplied, no default                               | `Left Nothing`   |
| `Presumed v` | an input nobody supplied, whose `TYPICALLY v` was not applied (§5) | `Left (Just v)`  |
| `Declined`   | an input the caller explicitly answered "don't know"               | `Right Nothing`  |
| `Derived`    | a comparison or call over unknowns (§4.6)                          | —                |

This is what lets the result name what it is waiting for, the planner rank the questions, and the ladder draw a presumed atom differently from an unasked one.

### 4.9 Printing

`l4 batch` and the REPL evaluate the `prettyLayout` re-print of a module, not its source (`jl4/app/L4/Cli/Batch.hs:244`).
On the main-line extension build, `(p OR q) AND r` used to print as `p OR q AND r` and `l4 batch` answered `TRUE` where `l4 run` answered `FALSE`, exit 0; `unstable` has bracketed nested connectives since `58f53e6b2` (2026-08-03).
So any new connective form, and any printed residual, must round-trip through `prettyLayout` with its brackets intact, and the guard is the evaluation differential of `CLAUDE.md` §3.2.1, which today covers two-valued Booleans only.
A residual is printed as L4 source over the input names (`x AND NOT y`), so it can be pasted back as a rule.

---

## 5. `TYPICALLY`, R8, and the four cells

R8 fills a defaulted section binder once at the root: discharge rewrites its elaboration from an `ASSUME` into a 0-ary definition whose body is the default (`jl4-core/src/L4/Discharge.hs:281-295`, `fillInDefault`).
So by the time the evaluator runs, a defaulted binder is an ordinary value; the evaluator cannot tell it came from a default.
The lift has to coexist with that in two modes, which U8 asks Meng to name:

- **Presuming** (the default when the lift is on): defaults are applied as R8 says, but the root records which binders took one, and the result says so — "`TRUE`, presuming `has capacity`".
  This is the ladder's `respectDefaults: true` (§3.6), and the verdict is the ladder's tentative box and streamer-weight current (DESIGN §22).
- **Not presuming:** a defaulted binder nobody supplied is left as an `RAtom (Presumed v)` instead, and `v` becomes the planner's prior for it, which is what the planner already does with `TYPICALLY` (`VizExpr.hs`, `typicallyTrueWeight`).
  This is the investigator's mode: a presumption is a question not yet asked, not an answer.

R8's "filled in once at the root" is unchanged by either: both decide at the same root, which is the only place a binder can be absent.
What R8 does not reach, and the parallel `TYPICALLY` work (branch `spec/typically-unify`) owns, is that the service's wrapper ignores `TYPICALLY` altogether (§2.5).

---

## 6. Switching it on, and what does not move

**Opt-in, per evaluation, never per module.**
A module does not decide whether its readers have every fact; the caller does.
So the switch is on the evaluation request, not in the source:

- `l4 run --unknowns residual` (and `--unknowns k3` for the quotient), default `--unknowns stuck`, today's behaviour.
- `l4 batch` the same flag.
- The service: an evaluation mode on the request, say `"mode": "explore"`, whose response is `{"determined": null, "residual": "<L4 source>", "needs": [...], "verdict": "Undetermined"}`, the planner's own vocabulary (§3.3).
- No new directive.
  A `#EXPLORE` would make the module decide, which is the thing the bullet above rules out, and it would be a directive every exporter has to learn to ignore.

With the flag off, the only change any golden can see is Step 0's trace change (§4.4).

**What the service's `fromMaybe FALSE` becomes.**
In explore mode a missing, `null` or `{}` boolean is an `RAtom`, of kind `Unsupplied` or `Declined` by the wire mapping of U9.
In today's decide mode it should stop being `FALSE` everywhere on the wrapper path, which a single `{}` anywhere in a request reaches, making absent and `null` booleans `FALSE` too (`TYPICALLY-ONE-BEHAVIOUR-SPEC.md` §3 S1); `{}` never takes a default.
That second half is a defect fix in two-valued mode and belongs to the `TYPICALLY` work, not to this lift; it is listed here so the two specs do not each assume the other has it.

---

## 7. Cost, and how to measure it before deciding

The lift costs nothing on a directive that never meets an unknown: §4.3's transitions are the same ones.
On a directive that does, it costs exactly the evaluation that today's `Stuck` skipped, which is the right operands of undecided connectives and both arms of undecided conditionals.
That is unbounded in principle, so it is measured, not guessed:

1. **Baseline.** Today's census (§2.6) shows the corpus directives are almost all fully supplied (5 stuck in 7,211), so the workload has to be made: for every `@export` function in the corpus, take each directive that calls it and generate its partial-input variants, dropping each input in turn and then every pair, which is what a wizard does mid-interview.
2. **Coverage.** On those variants, `--unknowns stuck` against `--unknowns residual`: how many end in a value, in a residual, in a different error, or time out.
3. **Blow-up.** Per directive, the total steps taken (the machine has no step counter today, only a stack-depth cap, `maximumFrameDepth`, `Exceptions.hs:159`, checked at `Machine.hs:857`, which cannot see a join's blow-up because the arms run one after the other; the counter is part of this measurement), the largest residual, the number of conditions whose residual is a tautology or contradiction, and the number of conditionals evaluated on an unknown condition, each against the two-valued run of the same directive with every input supplied.
4. **Wall clock.** `jl4-test` and the §3.2.1 differential, flag off, must be unchanged within noise; that is the cost to everyone who does not use the lift.
5. **Positive control.** One directive constructed to evaluate both arms of a nested conditional on one unknown, depth 10, whose frame count the measurement must show growing; a measurement that cannot see that cannot be trusted to have seen nothing elsewhere.

U4's budget is set from the distribution step 3 produces, not before.

---

## 8. Build sequence

1. **Fix the `CONSIDER` misdiagnosis** (§2.4) in two-valued mode: a `ValAssumed` scrutinee raises `Stuck`, naming it. Independent; small.
2. **Step 0** (§4.4): the built-in connectives as frames, flag off, with the trace golden, the service reasoning tree and jl4-mlir's trace parity moved together, measured.
3. **K3 behind the flag**: `ValResidual` with atoms only, quotiented to `U` everywhere, so the five asymmetric rows of §2.3 answer correctly.
4. **Residuals**: the full `Residual`, printed as source, round-tripped through `prettyLayout`, covered by an extension of the §3.2.1 differential to explore mode.
5. **Conditionals and the membrane** (§4.5, §4.6), after the measurement of §7.
6. **Service explore mode**, then the planner reading residuals from evaluation instead of only from the static ladder tree.
7. **Retire the duplicates**: once step 3 lands, shared L4 cases (a call with an unknown argument whose body decides anyway, `FALSE AND` a call that errors, `x OR NOT x`) run through both TypeScript evaluators, the ladder visualizer's (§3.4) and `ladder-core`'s `nodeValue` (`ts-shared/ladder-core/src/layout.ts:209`), and through the Haskell one, following `ladder-core/test/verdict.test.ts`; both TypeScript evaluators are replaced by a call after step 6 (U10).

---

## 9. Open rulings

Each is a card on the bench "Unknowns and Defaults" (claude.ai artifact `XQk522h6PN2xv8YFPhogJc`, db collection `l4-unknowns-defaults-1001`), where an independent skeptic's objection and a revised recommendation sit beside it; U8 and U9 share cards with `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` T4 and T3.
A ruling is recorded here when it is made.

### U1 — Semantics: left-sequential strong Kleene with residual values

**The question.** Which of §4.1's candidates is the evaluator's semantics of an unknown?
**Recommendation.** (b)'s order with (c)'s values, §4.2: the K3 table on known values, errors and non-termination left-to-right as today, an undecided Boolean returned as a residual formula.
**Cost of declining.** (a) alone answers the five rows of §2.3 but cannot decide `x OR NOT x` and gives the planner nothing to rank; a parallel evaluation order breaks §4.3's conservativity.

### U2 — Step 0 ships in two-valued mode

**The question.** Replace the `IF` rewrite of `AND`/`OR`/`IMPLIES`/`NOT` with frames even if the lift is never switched on?
**RULED 2026-10-01.** Meng marked `accept` on bench card U2 at 09:56:10Z, with no note. The ruling, as printed on the card: Give the built-in connectives their own frames, flag off, and delete or replace the unreachable rewrite at `Machine.hs:1198-1205`. In the same change, update the service's reasoning tree and jl4-mlir's mirrored trace shape and parity harness. Success: the `IF` sub-trees disappear from the golden and jl4-mlir parity holds.
An amendment (frames inside the built-in values; the parity harness run and read) is open as bench card U2b.

### U3 — Where the decision diagram lives

**The question.** Move `BoolExpr` and the diagram from `jl4-query-plan` into `jl4-core` (or a package below both), so the evaluator can recognise a tautology mid-evaluation and take the right `IF` arm?
**RULED 2026-10-01.** Meng marked `accept` on bench card U3 at 09:56:22Z, with no note. The ruling, as printed on the card: Residuals are decided at the boundary, for Boolean results only; non-Boolean conditionals lose the condition, and the spec says so. Add a §7 count of conditions whose residual is a tautology or contradiction, and make that count the trigger to decide small residuals locally by truth table.
An amendment (ruled only after U4; the trigger as a lower bound) is open as bench card U3b.

### U4 — Unknown conditions: evaluate the arms, and under what budget

**The question.** Does an `IF`/`BRANCH`/`CONSIDER` on an unknown evaluate its arms and join them (§4.5), and with what bound?
**RULED 2026-10-01.** Meng marked `accept`, option A on bench card U4 at 09:56:50Z, with no note. The ruling, as printed on the card: Join for `IF` and `BRANCH`. Add a cumulative step counter, explore mode only, set from §7's measurement of total steps (not depth). Running out returns an unknown naming the pending condition, never `StackOverflow`. Recursion guarded by an `IF` over an unknown always runs out, and the spec says so. `CONSIDER` on an unknown stays unknown for now.
Option A answers the sub-question: enumeration atoms come with `CONSIDER`, not now. An amendment (non-Boolean joins keep their arms; guarded errors) is open as bench card U4b.

### U5 — Comparisons become atoms (the membrane)

**The question.** Is a comparison over an unknown a residual atom, identified by its evaluated term (§4.6)?
**RULED 2026-10-01.** Meng marked `accept` on bench card U5 at 10:13:28Z, with no note. The ruling, as printed on the card: A comparison over an unknown is an atom identified by its evaluated term: the operator, the normal forms of the known operands, and the unknown inputs. An arithmetic unknown operand gets a fresh atom per evaluation. The spec's soundness claim is made conditional on this, and a helper-called-twice test is added. The spec states how evaluator atoms map to planner questions.
An amendment (the operand's field path in the key; fresh atoms the planner never asks about) is open as bench card U5b.

### U6 — An unknown equals itself

**The question.** Is `x EQUALS x` `TRUE` when `x` is unknown?
**RULED 2026-10-01.** Meng marked `accept` on bench card U6 at 10:14:10Z, with no note. The ruling, as printed on the card: An identity rule in `runBinOpEquals`: the same unknown input on both sides gives a literal `TRUE`, for numbers, strings, dates and times, lists and constructors. Functions and obligations keep today's error. Derived unknowns (`n PLUS 1 EQUALS n PLUS 1`) stay comparison atoms. Fix the right-operand misdiagnosis in build step 1.
An amendment (decide the rule from the operand's type) is open as bench card U6b.

### U7 — The switch is per evaluation

**The question.** CLI flag and service mode, no directive (§6)?
**HELD 2026-10-01.** Meng marked `accept` on bench card U7 at 10:16:06Z with the note: _"This affects purity and feels tantamount to a dynamically chosen effect system. Footgun. Discuss."_ Not recorded as a ruling until that discussion concludes. Amendment card U7b is held with it.

### U8 — Presumptions in explore mode

**The question.** When the lift is on, does an unsupplied `TYPICALLY` input take its default (marked as presumed) or stay an atom whose default is a prior (§5)?
**RULED 2026-10-01**, on bench card TU-presume, shared with `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` T4: Meng marked `accept` at 09:54:00Z, with no note. The ruling is recorded in full at T4. In short, one presumption switch applies to every evaluation, decide mode included. It is on by default and lands with that spec's W3/W4, not with explore mode. With it off, an absent input with a default is treated as absent with none: stuck in decide mode, unknown in explore mode. `null` never takes a default. The "presuming _x_" mark is the `presumed` list of T6. With presumption off, only boolean defaults become planner priors.

### U9 — The wire's three absences

**The question.** The service distinguishes a missing field, `null` and `{}` (§2.5). What does each mean?
**RULED 2026-10-01**, on bench card TU-wire, shared with `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` T3: Meng marked `accept`, option B, at 09:53:17Z, with no note. The ruling is recorded in full at T3. Missing is `Left`: not asked, so a default applies. `null` is `Right Nothing`, "don't know", and never takes a default. `{}` means `null` until it is retired, which happens after the service is instrumented to show who sends it. The cause of today's silent FALSE, `fromMaybe FALSE` at `CodeGen.hs:239, 335, 603`, is removed.

### U10 — The ladder's TypeScript evaluator

**The question.** Keep §3.4's second evaluator, or make the ladder ask the Haskell one?
**HELD 2026-10-01.** Meng marked `accept` on bench card U10 at 10:16:33Z with the note: _"Does this cure the objection?"_ Not recorded as a ruling until he has the answer. Amendment card U10b is open.

### U11 — An error on the right of an undecided left

**The question.** `x AND (1 DIVIDED BY 0 > 0)` with `x` unknown: the right operand's error (as (b) gives), or unknown?
**RULED 2026-10-01.** Meng marked `accept`, option C on bench card U11 at 10:16:42Z, with no note. The ruling, as printed on the card: Add an error leaf to the residual: shown in the result, raised only if its guard becomes TRUE. Divergence on an unknown is caught by PETROL's step counter ("gave up; needed _x_"). The same rule covers an error in an `IF` arm.
An amendment (typed unknowns carry the marker too; the error-leaf outcome survives the known-or-not reading) is open as bench card U11b.

### U12 — The ruling the negation-as-failure spec left open

**The question.** `NEGATION-AS-FAILURE-SPEC.md` open question 2, whether `kand`/`kor`/`knot` ship as a library.
**RULED 2026-10-01.** Meng marked `accept` on bench card U12 at 10:16:54Z, with no note. The ruling, as printed on the card: Decline the library if LIMBO and CLICKER are accepted. Record in `NEGATION-AS-FAILURE-SPEC.md` that this reverses its leaning, and that a data-borne `NOTHING` still needs `CONSIDER` (the library can be revisited if that demand appears). Update `negation-as-failure.md:60-63` in the same change, and move the experiment under a checked glob so it cannot rot.
Its condition is open: LIMBO (U1) and CLICKER (U7) are both held. The answer is recorded in `specs/done/NEGATION-AS-FAILURE-SPEC.md` as well. An amendment (label the file as K3) is open as bench card U12b.

---

## 10. What this spec did not verify

- The service behaviour in §2.5 was measured by the coordinating session, not here; the cause of the section-`GIVEN` prelude failure is unexplained.
- §4.4's claim that Step 0 moves only the trace golden, the service reasoning tree and jl4-mlir's trace parity is a prediction from `grep` and from reading the code; trace output from the LSP was not checked.
- The `#EVALTRACE` probes printed "no trace captured" on the installed binary, so the trace shape in §2.4 is read from a committed golden, not reproduced.
- §3.3's statement that two calls to one function share one planner atom follows from the atom being keyed by `nm.unique`; whether `nm` is the callee or the call was not checked, and it is outside this spec.
- Nothing in §4–§7 has been built or timed.
- The guard-idiom count: one line-level `grep` over the 809 `.l4` files under `jl4/examples`, `jl4-core/libraries` and `doc` found no `isJust`/`isNothing` guard and no `AND … DIVIDED` on one line, and five lines with a non-zero guard before an `AND`; a guard split across lines is invisible to it.
  Left-sequential evaluation (U1) preserves every such guard whether or not it was found, which is why the count is not load-bearing.
