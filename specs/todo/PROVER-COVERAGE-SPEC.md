# Prover coverage: letting `l4 prove` check the rules a large encoding really uses

**Status (2026-11-15): proposed, not landed.**
Nothing in this document is built, and this change touches no code.
`l4 prove` on `origin/unstable` at `35aa3bd67` refuses everything listed in §1.
Each design section ends with **Landed when**, which names the tests and the documentation changes that would make its claims true in the present tense.
Until then, read every "would" as a plan.

**Related.**
[VERIFICATION-BACKEND-LOWERING-SPEC.md](../proposals/VERIFICATION-BACKEND-LOWERING-SPEC.md) owns the prover's fragment (R-V2, R-V5 to R-V8).
[`doc/concepts/reviewing/proving-assertions.md`](../../doc/concepts/reviewing/proving-assertions.md) is the user page whose "Limits" section this work changes.
This spec rules nothing: every choice marked _assumed, not ruled_ is a choice the first implementer makes and a reviewer can reverse alone.

**How each claim was established.**
Four evidence classes are used, and every measurement says which it is.

- **IN-TREE**: read from the source at the cited `file:line`, or quoted from a run of the shipped `l4 prove`.
- **PROBED**: the answer of `l4 run` on a small file. Every `l4 run`, `l4 prove` and `--emit-smt` run in this document used the same installed `l4`, whose version string is `dev`; every probe uses a built-in that predates this work.
- **SCRIPT-LEVEL**: the answer of z3 4.16.0 on a script that `l4 prove --emit-smt` wrote and that was then edited by hand. No implementation produced these scripts, the evaluator was not run against them (except where said), and an `unsat` here is **not** a `proved` verdict.
- **ARGUED**: reasoning that the measurements constrain but do not settle.

## 0. In one paragraph

A 51-module encoding of a federal tax credit and its official form, November 2026, could not have its top-level rules checked by `l4 prove`.
The prover refused them by name (`DATE`, `MAYBE`, `TRUNC`, `JUST`), so every property over every input was stated over a hand restatement of the arithmetic, and the restatement was tied to the encoding only by grids of ground assertions.
The properties that could be stated over the restatement then hit three further walls: a count that could be negative, amounts that could be fractions, and a step function (`CEILING`) on which z3 timed out at 10, 60 and 180 seconds.
This spec proposes, in order of cost: report every refusal at once (so the next step is measured, not guessed), lower `TRUNC`, change how `FLOOR` and `CEILING` of a quotient are encoded (a change that, at script level, turned four of the seven timeouts re-tried on the large encoding into answers, and a fifth once the inputs were declared whole), lower `DATE`, lower `MAYBE` and other parametric types, let inputs be declared whole and non-negative, and report honestly what a timeout tried.
It does not claim that these steps are enough to run the tax-credit properties on the encoding's own rules, because the logs show only the first refusal per assertion (§1.5).

## 1. What `l4 prove` did on the large encoding

Every row below is **IN-TREE**: a line from the run's own `l4 prove` logs, cut to the reason, or a count taken from them.
The run used a prerelease build of the same commit, `35aa3bd`.
Names of the encoding's rules, its inputs and its source are left out on purpose.

### 1.1 Refusals

| Where                                                     | Log (reason only)                                                                       | Coverage line                                   |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------- | ----------------------------------------------- |
| Statute side, a thin wrapper over the encoding's own rule | `out of fragment: DATE` on two assertions whose own inputs were only BOOLEAN and NUMBER | `3 obligations: 0 proved, 0 refuted, 3 unknown` |
| Statute side, same run                                    | ``out of fragment: the parametric type `MAYBE` `` on the third assertion                | (same line)                                     |
| Form side, the form encoding's own rules, called directly | ``out of fragment: a call to `TRUNC` ``                                                 | `3 obligations: 1 proved, 0 refuted, 2 unknown` |
| Form side, same run                                       | ``out of fragment: a call to `JUST` ``                                                  | (same line)                                     |

The one proved assertion on the form side compared an enumeration value, which is inside the fragment.
The two `DATE` refusals arrived through records the rules build internally, not through an input: the assertions' own inputs were BOOLEAN and NUMBER.
The `MAYBE` refusal is the result type of the rule the third assertion is about.
The encoding's fact records carry `DATE` and `MAYBE DATE` fields (dates of birth, period boundaries), and §2 shows why one such field makes the whole record unusable.

### 1.2 What the refusals cost

Every property over every input had to be stated over a hand restatement of the arithmetic, not over the encoding.
The restatement was tied to the encoding only by generated ground `#ASSERT`s, one per grid point.
Three bridge logs record that tie: 2,926, 9,660 and 18,720 ground assertions, and every `Result:` block in all three reads `assertion satisfied`.
A grid agrees at its points and proves nothing between them, so a property proved over the restatement is a property of the restatement.

### 1.3 Counts and amounts

The first obligation over the restated phase-out was refuted.
Its counterexample was a count input that was a negative fraction a little below zero, and the log says `the evaluator agrees: the assertion is FALSE there`.
That one value motivates two things at once: counts must not be negative, and counts must be whole.
With a premise `AT LEAST 0` for each count input stated by hand, the same claim was `proved (the evaluator agreed at 57 sample points)`.
A second obligation, the exact one-unit step at the threshold, was refuted at a count that was a small positive fraction: a fraction of a person.
The refuted rows of the five-input runs include models with thirds and halves of a currency unit, amounts the form's own whole-unit rounding would never be given.

### 1.4 Timeouts

| Run                                                       | Log (reason only)                                                                                           | Coverage line                                   |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| Restated phase-out, three monotonicity obligations, 10 s  | `timeout after 10s` on all three                                                                            | `8 obligations: 3 proved, 2 refuted, 3 unknown` |
| Same file, `--timeout 180`                                | `timeout after 180s` on the same three                                                                      | `8 obligations: 3 proved, 2 refuted, 3 unknown` |
| Same claims split by hand into three regions of the input | the two regions at or below the threshold `proved`; the region above it `timeout after 60s`, once per claim | `6 obligations: 4 proved, 0 refuted, 2 unknown` |
| Five numeric inputs over two restated rules, 60 s         | `timeout after 60s` on four of five                                                                         | `5 obligations: 0 proved, 1 refuted, 4 unknown` |
| Same, with `MIN` and `MAX` unfolded by hand, 300 s        | `timeout after 300s` on three of five                                                                       | `5 obligations: 0 proved, 2 refuted, 3 unknown` |

The "2 of 3" is per claim: each of the two claims had two of its three regions proved, and the region above the threshold, where the `CEILING` step applies, was the one that did not finish.
No unsplit 60 s log exists; the 60 s figures above are the split run's third region and the five-input run, and the 10 s and 180 s figures are the unsplit run.

### 1.5 What these logs cannot show

The lowering stops at the first refusal (`refuse` is `lift . Left`, `jl4-core/src/L4/Prove/Lower.hs:227-228`), so each `unknown` names one reason, not the list.
The logs therefore prove that `DATE`, `MAYBE`, `TRUNC` and `JUST` are each a blocker, and prove nothing about whether they are the only ones.
The encoding's inputs include lists and its records are large; `LIST` is refused by name (`Lower.hs:547`), and may well be next.
Step 0 of §5 exists to find out.

## 2. How the fragment is decided today

All **IN-TREE**, at `35aa3bd67`.

- `Sort` is `SBool | SReal | SData Unique` (`Lower.hs:146`). `NUMBER` is `Real`, which is faithful because an L4 number is an exact rational.
- `sortOf` refuses `STRING` (`Lower.hs:377`), `DATE` (`:378`), any type applied to arguments (`:382`), function types, polymorphic types and unsolved types (`:383-386`).
- `datatypeSort` registers a record or enumeration as an SMT datatype and sorts **every field when it registers the type** (`register`, `:399-412`; the field's sort is taken at `:408`), refusing a declared type parameter (`:393`), an opaque type (`:395`) and a computed field (`:406-407`).
  One field of a refused sort therefore makes the whole record unusable for every assertion that touches the record, whether or not the assertion reads that field.
- `builtin` lowers the arithmetic and comparison operators, `FLOOR`, `CEILING`, `ROUND`, `IS INTEGER` (`:699-713`); refuses the ten transcendental functions by name (`:714-715`, list at `:741-743`); and refuses **everything else** with one catch-all, ``out of fragment: a call to `X` `` (`:716`). `TRUNC` and `JUST` reach that line.
- The constructors `JUST` and `NOTHING` are built in, not declared with `DECLARE` (`TypeCheck/Environment.hs:1071-1073`), so they are not in the table of constructors the lowering reads (`peCtors`, `Lower.hs:81`), and a pattern `WHEN JUST x` is refused as an unknown pattern (`:635-636`).
- `FLOOR x` is `(to_real (to_int x))` and `CEILING x` is `(- (to_real (to_int (- x))))` (`:706-708`), whatever `x` is, a quotient included.
- Every script starts `(set-logic ALL)` (`:273`). The solver is a subprocess and the time limit is the driver's, not a z3 option (`jl4/app/L4/Cli/Prove.hs:180`, default 10 s at `:136`).
- A `sat` answer is replayed through the evaluator and reported `refuted` only if the evaluator agrees (`Prove.hs:388-407`); an `unsat` answer is spot-checked at up to 64 sample points, fractions first (`:410-415`, `proofSampleValues`, `Lower.hs:847`); a disagreement is `ENCODING DEFECT`, exit 4.
- `IS INTEGER` is a built-in predicate (`Environment.hs:1082`, [`doc/reference/builtins/README.md`](../../doc/reference/builtins/README.md) line 11), lowered as `is_int` (`Lower.hs:710`).
  Nothing else about integrality, ranges or refinement exists: no type, no annotation, no spec. The only hit for "refinement type" in `specs/` besides a passing mention is the line "Dependent types or refinement types" in the Non-Goals of [BIDIRECTIONAL-TYPE-CHECKING-SPEC.md](../done/BIDIRECTIONAL-TYPE-CHECKING-SPEC.md) (§12).

**A stale header, reported.**
At `35aa3bd67`, VERIFICATION-BACKEND-LOWERING-SPEC.md's header said `l4 prove` was on an unmerged branch and "does not exist in the tree", and that #784 builds "R-V7 except `STRING`".
Pull request #784 had merged on 2026-11-12 (`2818cc21e`), and R-V7 rules `DATE` an `Int` serial, optionals an option datatype and a bodiless `DECLARE` an uninterpreted sort, none of which the code lowers: it refuses them (`Lower.hs:378`, `:382`, `:395`).
A separate commit on this branch corrects those sentences and R-V7's epoch (§3.1); this spec's §3.1 and §3.2 are the discharge of what R-V7 already ruled, and a bodiless `DECLARE` as an uninterpreted sort is ruled and still unbuilt, which this spec does not take up.

## 3. Proposals

### 3.1 `DATE`

**Gap.**
`sortOf` refuses `DATE` (`Lower.hs:378`), and by §2 a `DATE` field poisons the record that holds it.

**Measurement.**
§1.1: two of three statute-side assertions refused with `out of fragment: DATE`, with only BOOLEAN and NUMBER inputs.

**Design.**
_R-V7 ruled this on 2026-09-07; this section is how._

1. A new sort `SDate`, written `Int` in SMT-LIB. The value is the evaluator's day serial.
   Take the serial's anchor from the evaluator, not from R-V7's text as it stood at `35aa3bd67`: `dayNumberFromDay day = diffDays day 0000-01-01 - 1` (`jl4-core/src/L4/EvaluateLazy/Machine.hs:8382-8387`).
   **PROBED:** `DATE_SERIAL (DATE_FROM_DMY 1 1 1)` is 365, `DATE_SERIAL (DATE_FROM_DMY 1 1 0)` is -1, and `DATE_SERIAL (DATE_FROM_DMY 1 1 2000)` is 730484.
   That text gave the epoch as `0001-01-01`, which these values contradict; the separate correction commit fixes that sentence.
2. `EQUALS` on two dates is integer equality. Ordering comes from the library, not the checker: the built-in comparison overloads cover NUMBER, STRING and BOOLEAN only (`Environment.hs:378-394`), and **PROBED**, `DATE_FROM_DMY 1 1 2000 AT LEAST DATE_FROM_DMY 1 1 1999` is a type error with only the prelude imported and `TRUE` with `IMPORT daydate` added. The overloads are ordinary rules in `daydate.l4:810-840` (`Day a AT LEAST Day b`, where `Day` is `DATE_SERIAL`, `:182`), non-recursive, so the prover unfolds them once `DATE` is a sort and nothing new needs lowering. The library's own `Date d m y` constructor is the lenient, rolling one and goes through the recursive helper (`:76-80`, `:381-388`), so it stays refused by the recursion guard; only `DATE_FROM_DMY` and the `DATE` alias of `date-compat.l4:26`, which is strict, are in reach.
3. `DATE_SERIAL d` lowers to `(to_real d)`. `DATE_FROM_SERIAL x` lowers to `(to_int x)`, because the evaluator floors: **PROBED**, `DATE_SERIAL (DATE_FROM_SERIAL 0.5)` is 0 and `DATE_SERIAL (DATE_FROM_SERIAL -0.5)` is -1; it is total and defined for every real, negative serials included.
4. `DATE_DAY`, `DATE_MONTH`, `DATE_YEAR` and `DATE_FROM_DMY` lower to exact integer calendar arithmetic: only `div` and `mod` by numerals, so the whole of it is linear integer arithmetic, with no recursion.
   The library's `Months since year start to days` is recursive (`jl4-core/libraries/daydate.l4:381-388`) and stays refused by the existing recursion guard; the six built-ins used here have been in the checker since 2025-12-08 (`git log -S` on `Environment.hs`) and the library's own `DATE` constructor is a wrapper over `DATE_FROM_DMY` (`date-compat.l4:26`).
   With `s` the serial, `z = s - 59` counts days from 0000-03-01 (**PROBED**, in the sweep below: serial 59 is 1 March of year 0, a leap year):

   ```
   era = div z 146097            doe = mod z 146097
   yoe = div (doe - div doe 1460 + div doe 36524 - div doe 146096) 365
   doy = doe - (365*yoe + div yoe 4 - div yoe 100)
   mp  = div (5*doy + 2) 153
   day = doy - div (153*mp + 2) 5 + 1
   month = if mp < 10 then mp + 3 else mp - 9
   year  = yoe + 400*era + (if month <= 2 then 1 else 0)
   ```

   and, for `DATE_FROM_DMY d m y`, with `y2 = y - (if m <= 2 then 1 else 0)`, `er = div y2 400`, `ye = y2 - 400*er`, `dy = div (153*(if m > 2 then m - 3 else m + 9) + 2) 5 + d - 1`:
   `serial = 146097*er + 365*ye + div ye 4 - div ye 100 + dy + 59`.
   **SCRIPT-LEVEL**, and narrower than a sweep: z3 evaluated the first set of formulas at 168 serials, namely 18 hand-picked ones (around the start of year 0, the start of year 1, and 1 January 2000, with a few negative ones) and 150 random ones in -900,000 to 3,000,000, and every one of the 168 triples equals the evaluator's `DATE_DAY`, `DATE_MONTH` and `DATE_YEAR`. For the second formula z3 only checked that it returns the serial from z3's own three values at all 168; the evaluator's `DATE_FROM_DMY` was run on 40 of the evaluator's triples and returned those serials, which shows the evaluator is self-consistent and does not test the second formula against it.
   That is evidence the formulas are right, not a proof; "Landed when" asks for a stronger test.

5. `DATE_FROM_DMY` is defined only for whole `d`, `m`, `y` forming a real date: **PROBED**, `DATE_FROM_DMY 31 2 2000` and `DATE_FROM_DMY 1.5 2 2000` both raise. Its definedness term is `is_int` on each, `1 <= m <= 12`, and `1 <= d <= days_in_month(m, y)`, where February's length uses the leap rule on `y` with `mod`.
6. `TODAY` and the other clock reads: with `--fixed-now T` (an option `l4 prove` already has, `Prove.hs:127`, and passes to the evaluator that replays), they lower to the constant for `T`; without it they stay refused by name. A verdict under `--fixed-now` is relative to that clock, and the coverage line must print it.
7. Replay: a model value `n` becomes `DATE_FROM_SERIAL n`. Samples: `proofSampleValues` gains date samples, namely the serial of each date literal the obligation reaches and its neighbours, 0, -1, 59, 60, and the last days of February in a leap and a non-leap year.

_Alternative rejected: uninterpreted `DATE_DAY`, `DATE_MONTH`, `DATE_YEAR`._
It is sound for `unsat`, because a property true for every interpretation holds for the calendar.
It is unsound for the answer a user sees on `sat`: a model may pick an interpretation the calendar forbids, replay disagrees, and today that prints `ENCODING DEFECT` and exits 4, which tells the user the prover is broken when it is only incomplete.
If an abstraction is ever used, the replay of a model that mentions an abstracted symbol must report `unknown (spurious under an abstraction of DATE_YEAR)` and exit 3.
The exact encoding is about a dozen lines and is the recommendation.

**Soundness.**

| Failure                                                      | Loud or silent | Caught by                                                                                               |
| ------------------------------------------------------------ | -------------- | ------------------------------------------------------------------------------------------------------- |
| A calendar not lowered (`DATE_FROM_DMY` with a variable)     | Loud           | `unknown (out of fragment: …)`, exit 3                                                                  |
| A model the calendar forbids (only if abstracted)            | Loud           | the new `unknown (spurious under an abstraction)`                                                       |
| A calendar formula wrong at some serial, in an `unsat` proof | **Silent**     | the 64-point sample check only if a sample lands there; hence the CI sweep below and date-aware samples |
| `--fixed-now` forgotten                                      | **Silent**     | the verdict is about one day; the coverage line prints the clock                                        |

**Landed when.**
`Lower.hs` lowers the six built-ins and the sort; a CI test has z3 evaluate the emitted `DATE_DAY`, `DATE_MONTH`, `DATE_YEAR` and `DATE_FROM_DMY` and the evaluator do the same over a sweep that includes every century boundary from year 0 to 2400, serial 0, -1, and negative years, and requires equality; `tests-cli` fixtures cover a proved claim, a claim refuted at a leap day, and the refusal of `TODAY` without `--fixed-now`; `proveBound` (`Prove.hs:83-117`) and the "Limits" section of the user page stop listing dates as refused; VERIFICATION-BACKEND-LOWERING-SPEC's header is true.

### 3.2 `MAYBE`, and parametric types in general

**Gap.**
`sortOf` refuses a type with arguments (`Lower.hs:382`) and `datatypeSort` refuses a declared type parameter (`:393`).
`JUST` and `NOTHING` are built-in constructors, not in `peCtors`, so `JUST OF x` falls to the catch-all and `WHEN JUST x` is an unknown pattern.

**Measurement.**
§1.1: ``the parametric type `MAYBE` `` on the statute side and ``a call to `JUST` `` on the form side.

**Design.**
_R-V7 ruled "optionals → an option datatype"; this is how._

1. **Monomorphise.** Each instantiation `MAYBE t`, with `t` a sort the lowering already has, becomes its own SMT datatype with two constructors, a nullary one for `NOTHING` and a one-field one for `JUST`. `EITHER a b` the same way. The datatype's name carries the instantiation (`l4T_MAYBE@Real`). _Assumed, not ruled:_ SMT-LIB's parametric datatypes (`par`) are standard and z3 and cvc5 both read them, but monomorphic datatypes keep every sort closed and keep the replay trivial (a model value is a constructor applied to model values, which `liftModelValue` already does).
2. The constructor and pattern tables (`peCtors`, `lowerPattern`) gain the built-in constructors, keyed to the instantiation, so `JUST OF e`, `NOTHING`, `CONSIDER … WHEN JUST x THEN … WHEN NOTHING THEN …` and `EQUALS` on options lower with the machinery records already have, including the per-field definedness (`fdefs`, `Lower.hs:205`), so that `JUST OF (1 DIVIDED BY 0)` does not raise until the payload is read, as in the evaluator.
3. The same change opens user-declared parametric records and enumerations (`datatypeSort` refuses `tparams`), at no extra design cost.
4. **What this does not open: polymorphic rules.** The prelude's generic helpers over options (`fromMaybe`, `orElse`, `isJust`, `isNothing`, `mapMaybe`: `prelude.l4:480-576`) are `Forall` definitions, which `defineDecide` refuses by name (`Lower.hs:759`). The monomorphic prelude rules over `MAYBE NUMBER` (`min`, `max` and the four comparison overloads, `prelude.l4:343-410` and `:779-825`) become reachable at once, and they are ordinary `CONSIDER`s the lowering unfolds faithfully (note that the comparison overloads return `FALSE` when either side is `NOTHING`, so `NOT (a AT LEAST b)` is not `a AT MOST b`; no special case is needed, only unfolding).
   Calling a polymorphic rule needs the instantiation the checker already computed (`Safety.siSubst = tc.substitution` is passed in `Prove.hs:352`); one `define-fun` per instantiation. That is a separate, second step (§5 step 6).

**Soundness.**

| Failure                                                             | Loud or silent | Caught by                                                                                     |
| ------------------------------------------------------------------- | -------------- | --------------------------------------------------------------------------------------------- |
| A polymorphic call (`fromMaybe`)                                    | Loud           | ``out of fragment: the polymorphic definition `fromMaybe` ``, exit 3                          |
| An option over a refused payload sort (`MAYBE STRING`)              | Loud           | the payload's own refusal                                                                     |
| A field read on the wrong constructor (`JUST` payload of `NOTHING`) | Loud           | already modelled: a read on the wrong constructor is a definedness failure (`:530`)           |
| Definedness of an unread payload over-approximated                  | Loud           | `ENCODING DEFECT`, not a wrong verdict (the existing caveat in the header of `Lower.hs`)      |
| The sample generator never draws `NOTHING`                          | **Silent**     | `samplesOver` already draws every constructor of a datatype; a test must pin that for options |

**Landed when.**
`Lower.hs` lowers monomorphic `MAYBE` and `EITHER`; a fixture proves and refutes a claim through `CONSIDER` on an option; the `JUST OF (1 DIVIDED BY 0)` laziness case has its own fixture; the user page's list of refused types drops `MAYBE`.

### 3.3 `TRUNC`, and the rest of the refusal list

**Gap.**
`TRUNC` is a checker built-in (`Environment.hs:1150`, in the checker since 2025-12-08) with no lowering, so it reaches the catch-all (`Lower.hs:716`).

**Measurement.**
§1.1: ``a call to `TRUNC` `` on the form side.

**Semantics, read from the evaluator and PROBED.**
`TRUNC value digits` (`Machine.hs:6567-6578`): `digits` is rounded half-to-even to an integer `k`; for `k >= 0` the result is `truncate (value * 10^k) / 10^k`, and for `k < 0` it is `truncate (value / 10^(-k)) * 10^(-k)`, where `truncate` rounds toward zero.
**PROBED:** `TRUNC 2.789 2` is 2.78, `TRUNC -2.789 2` is -2.78, `TRUNC 1234 -2` is 1200, and `TRUNC 2.789 1.5` is 2.78.

**Design.**
Lower `TRUNC v d` only when `d` lowers to a numeric literal (the lowering already recognises literals, `isConstant`, `Lower.hs:592-593`); otherwise refuse by name, `out of fragment: TRUNC with a digit count that is not a literal`.
Round `d` half-to-even at lowering time, with Haskell's `round`, exactly as the evaluator does, so there is no second rounding rule to keep in step.
For `k >= 0`, with `w = v * 10^k` (linear, the factor is a numeral): `trunc(w) = (ite (>= w 0) (to_int w) (- (to_int (- w))))`, and the result is `(/ (to_real trunc(w)) 10^k)`.
For `k < 0` the same with `w = v / 10^(-k)` and a final multiplication.
It is total, so its definedness is that of `v`.

**The rest of the refusal list**, from the checker's table of built-ins (`Environment.hs:1060-1169`) and the lowering's own structural refusals:

| Group                                                                                                                        | Today                                 | Proposal in this spec                                                                                                                                              |
| ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `TRUNC`                                                                                                                      | catch-all                             | lower for a literal digit count (above)                                                                                                                            |
| `DATE_SERIAL`, `DATE_FROM_SERIAL`, `DATE_FROM_DMY`, `DATE_DAY`, `DATE_MONTH`, `DATE_YEAR`                                    | catch-all                             | §3.1                                                                                                                                                               |
| `TODAY`, current time                                                                                                        | catch-all                             | a constant under `--fixed-now`, else refused (§3.1)                                                                                                                |
| `JUST`, `NOTHING`, `LEFT`, `RIGHT`                                                                                           | catch-all and pattern refusal         | §3.2                                                                                                                                                               |
| String functions (length, case, trim, contains, split, substring, replace, `TO STRING`, `TO NUMBER`, `TO DATE`)              | refused with `STRING` itself (`:377`) | **out of scope**: R-V7 rules `STRING` an uninterpreted sort with equality only; not built; a separate step that would also open `TO DATE`, which returns an option |
| `SQRT`, `LN`, `LOG10`, `SIN`, `COS`, `TAN`, `ASIN`, `ACOS`, `ATAN`, `EXPONENT`                                               | refused by name (`:714`)              | **stays refused**: not decidable, and the evaluator routes them through `Double`                                                                                   |
| `FETCH`, `ENV`, `POST`, JSON encode and decode                                                                               | refused by name (`:553-555`)          | **stays refused**: I/O                                                                                                                                             |
| `LIST`, `EMPTY`, `FOLLOWED BY`, list patterns, lambdas                                                                       | refused by name (`:546-547`, `:637`)  | **out of scope**: a bounded-length encoding is its own spec                                                                                                        |
| `TIME`, `DATETIME`, `TIMEZONE`, and the temporal built-ins (`WHEN LAST`, `VALUE AT`, …)                                      | catch-all                             | **out of scope**: `TIME` and `DATETIME` are `DATE` plus seconds and an offset, so they follow once `DATE` lands                                                    |
| Recursion, local definitions with parameters, opaque types, computed fields, a named application supplying a section `GIVEN` | refused by name                       | unchanged                                                                                                                                                          |

**Soundness.**

| Failure                                                   | Loud or silent | Caught by                                                                                                                                  |
| --------------------------------------------------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| A variable digit count                                    | Loud           | the named refusal above                                                                                                                    |
| Truncation toward zero confused with `FLOOR` on negatives | **Silent**     | sample points at `-1/3`, `-1/2` and `-1/7` are already in `proofSampleValues` (`:851-857`); a fixture with a negative argument must pin it |
| The digit count rounded differently from the evaluator    | **Silent**     | impossible by construction if the lowering calls Haskell `round`; a fixture with `1.5` and `2.5` digits pins it                            |

**Landed when.**
A fixture proves `TRUNC x 2 AT MOST x` for non-negative `x` and refutes it for a negative one, with the evaluator agreeing; `TRUNC` with a variable digit count is refused by name; the built-ins reference page and the prover page agree on what is lowered.

### 3.4 Whole-number and non-negative inputs

**Gap.**
Every `GIVEN x IS A NUMBER` is a `Real` with no bounds.
A count can be a small negative fraction, a number of people can be a fraction, and an amount of currency can be a third of a unit, which the form never sees.

**Measurement.**
§1.3.
Also **PROBED and SCRIPT-LEVEL**, on the public example in §7: `IS INTEGER` premises, which exist today, do not speed the proof up at all (`l4 prove --timeout 30` on obligation 2 with `IS INTEGER` stated for every input: `timeout after 30s`), and declaring the inputs `Int` in the script while keeping the `to_int` of a real quotient does not either (timeout, 30 s). The integrality is only useful in combination with §3.5's quotient encoding.

**What exists.**
`IS INTEGER` (§2), usable in a premise today; and `FLOOR n EQUALS n`, the form the run's own helper used.
No declared range, no integer type, no spec.
`JsonSchema.hs` already has an `SInteger` constructor (`:35`, `:87`) that it produces for a type whose lower-cased name is `int` or `integer` (`:198-199`), which no built-in type has; a built-in type with that name would already reach the service's JSON schema as `integer`.

**Two designs, and a ranking by meaning, not by ease.**

**A. Integrality lifting (no language change, sound by construction).**
When the goal is `P IMPLIES Q` and a conjunct of `P` is `IS INTEGER x` or `FLOOR x EQUALS x` on a free variable `x`, the lowering declares `x` as an `Int` (cast with `to_real` where it is used as a `NUMBER`) and keeps the conjunct in the formula.
For all reals `x`, `is_int(x) AND R(x) => Q(x)` is the same statement as for all integers `n`, `R(n) => Q(n)`, so the verdict means exactly what it meant, nothing is assumed beyond what the user wrote, and no runtime has to enforce anything.
Only the integrality conjuncts license the `Int` declaration. A bound such as `x AT LEAST 0` does not: declaring `x` an `Int` on the strength of a bound alone would make the verdict a statement about integers while reading as one about all reals. Bounds need no lifting, because they are already ordinary premises (§1.3: the non-negative claim was `proved` with them).
Its limit: only literal top-level conjuncts are recognised. The run packaged its premises in a helper rule (`a whole number not below zero`, called once per input), which the lifting does not see through without unfolding.

**B. A declaration on the input (a language change; needs a ruling).**
_Spelling assumed, not ruled:_ an annotation after the type, the same place `@desc` already goes (`DESC-ANNOTATION-SPEC.md`, inline form), for example `GIVEN units IS A NUMBER @whole @min 0`.
The type stays `NUMBER`, so arithmetic typing does not change.
What the checker would enforce: the annotations are accepted only on a section `GIVEN` or an `ASSUME` of type `NUMBER` (the prover's free variables, which have no call site), the bounds are numerals with `min <= max`, and an argument that is a literal violating the declaration is a type error.
What the runtime must enforce, and this is the cost: **every place that supplies a value for a section `GIVEN` must refuse one outside the declaration**, with a named error such as ``input `units` must be a whole number not below 0, got -1``.
`git grep rewriteModuleAssumes` finds the places that supply such a value: the service, which replaces the `ASSUME` with the request's value (`jl4-service/src/Backend/Jl4.hs:1115-1119`); `l4 batch`, which turns each `ASSUME` the exported rule reads into an input column (`jl4/app/L4/Cli/Batch.hs:322-330`); and the prover's own replay (`Prove.hs:435`).
The service's JSON schema for the input gains `"type": "integer"` and `"minimum"`, so a request is refused before evaluation.
What `l4 prove` does with it: the variable is declared `Int` (or `Real` with bounds), the bounds join the negated goal, `proofSampleValues` draws only in-range samples, and the coverage line prints `assuming declared inputs: units (whole, at least 0)` so that a reader sees the narrowing.

**Ranking.**
B is better on meaning: it states the input contract once, at the input; the service and the evaluator refuse bad inputs for everyone, not only the prover; schemas and forms learn it; the helper-packaged premise problem disappears.
B costs a language change, three enforcement points, and one silent failure that A cannot have.
A costs nothing in the language, is correct on day one, and does not help helper-packaged premises.
**Recommendation (assumed, not ruled):** build A first, because it is correct by construction and lets the integer encoding be measured on real obligations; put B on a bench, because it is user-visible, which is exactly the kind of decision only a ruling makes.

**Soundness.**

| Failure                                                                | Loud or silent | Caught by                                                                                                                                                                                                                                                          |
| ---------------------------------------------------------------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| (A) a conjunct not recognised                                          | Neither        | the input stays `Real`; the verdict is unchanged, only the speed                                                                                                                                                                                                   |
| (B) a literal outside the declaration                                  | Loud           | type error                                                                                                                                                                                                                                                         |
| (B) a runtime value outside the declaration                            | Loud           | the entry point's named error                                                                                                                                                                                                                                      |
| (B) **an entry point that does not check**: a new one, or a missed one | **Silent**     | `proved` then covers a smaller input space than the entry accepts. Mitigate with one shared checking function that all three sites call, a test that fails when `rewriteModuleAssumes` has a caller that does not pass through it, and the printed assumption line |
| (B) a sample point outside the declaration given to the evaluator      | Loud           | would print `ENCODING DEFECT`; the sampler must filter, and a test pins it                                                                                                                                                                                         |

**Landed when (A).**
A fixture where a leading `IS INTEGER` premise changes the emitted script's declaration to `Int`, and the verdict and the replayed counterexample are the ones the premise-free spelling gives; the user page says which premises are lifted and what shapes are recognised; a fixture where a bound alone does not change the declaration.
**Landed when (B).**
There is a ruling recorded in this spec; the checker, the evaluator, `l4 batch`, the service and the JSON schema each enforce it with a test; the coverage line prints the assumption.

### 3.5 Timeouts

**Gap.**
A property that a human reads as obvious, "one more unit of income never raises the amount", runs out of time in z3.

**What the measurements show.**

1. **The cause is the encoding of `CEILING` and `FLOOR` over a quotient, not the size of the input range.** `CEILING ((m MINUS t) DIVIDED BY 500)` is `-(to_real (to_int (-((m - t) / 500))))`, a `to_int` of a real quotient. **ARGUED:** z3's own reason for diverging was not inspected, and the guess is branch and bound over an unbounded integer; the measured fact is the contrast. **SCRIPT-LEVEL**, §7: on the public example the emitted script times out at 30 s; the same rule written by hand as pure integer arithmetic (`div` by the numeral) is `unsat` in under a second; so is the emitted script with each `to_int` of a quotient by a positive integer literal rewritten as `div (to_int ·) n`.
2. **Splitting does not help on its own.** On a hand-written real copy of the public example, restricting the input to the region above the threshold still times out at 30 s, and so do `smt.arith.solver` 1, 2 and 6 and a different random seed; on one private obligation `smt.arith.solver=2` timed out at 90 s. The region above the threshold is the hard one because it is where the `to_int` is, and the same region is `unsat` in under a second in the integer encoding. The run's own manual split agrees: it proved the regions at or below the threshold and not the one above (§1.4).
3. **The fix is an exact identity, not a heuristic.** For an integer `n >= 1` and any real `y`, `floor(y / n) = floor(floor(y) / n)`. z3 proves the instance `n = 500` over all reals (`unsat`), and the identity is standard; the CI test below asks z3 for each divisor that occurs. So `FLOOR (e DIVIDED BY n)` lowers to `(to_real (div (to_int e) n))`, and `CEILING (e DIVIDED BY n)` to `(- (to_real (div (to_int (- e)) n)))`, when `n` is a positive integer literal. `div` by a positive numeral is floor division in SMT-LIB. A non-integer or non-literal divisor keeps today's encoding.
4. **A second lemma is needed when two such terms are compared.** For "income plus an unknown non-negative amount", the rewritten script still timed out at 60 s. z3 needs to know `to_int` is monotone: `(a <= b) => (to_int a <= to_int b)`, a theorem of the theory. Asserting it, either as one quantified axiom with the pattern `(to_int a) (to_int b)` or as a ground instance, makes the obligation `unsat` in 0.0 s. The ground instance is quantifier-free, which suits R-V6's "portable text"; but the `to_int` terms sit inside the unfolded `define-fun`s, so a ground instance needs the call sites the lowering does not keep. _Assumed, not ruled:_ emit the quantified lemma, and only when the quotient rewrite fired; if a script with the lemma answers `unknown`, rerun it without. A lemma can only remove solutions that do not exist, so it cannot turn a `sat` into `unsat`; it can make a solver give up where it would have found a model, and the rerun covers that.

**SCRIPT-LEVEL results on the public example (§7), z3 4.16.0.**

| Script                                                            | Obligation 2: one more unit of income | Obligation 3: any non-negative increase |
| ----------------------------------------------------------------- | ------------------------------------- | --------------------------------------- |
| As emitted today                                                  | timeout, 30 s                         | timeout, 30 s                           |
| Inputs declared `Int`, `to_int` of the real quotient kept         | timeout, 30 s                         | not run                                 |
| Quotient rewrite                                                  | `unsat`, 0.0 s                        | timeout, 60 s                           |
| Quotient rewrite and the `to_int` monotonicity lemma (quantified) | not run                               | `unsat`, 0.0 s                          |
| Quotient rewrite and the lemma as a ground instance               | not run                               | `unsat`, 0.0 s                          |
| Inputs declared `Int` and the quotient rewrite                    | `unsat`, 0.0 s                        | not run                                 |

`l4 prove` itself on the same file: `timeout after 10s` and `timeout after 60s` on both of obligations 2 and 3 (obligation 1, the bound `0 <= amount <= full amount` under a non-negativity premise, is `proved`).
Adding `IS INTEGER` premises for the three inputs to obligation 2 changes nothing: `timeout after 30s`.

**SCRIPT-LEVEL results on the large encoding (hand-edited emitted scripts, 60 s limit).**

- The restated phase-out, eight obligations: the three that timed out in the run (§1.4) are all `unsat` in 0.0 s once the quotient rewrite and the lemma are applied. The five that were decided stay decided with the same answer (three `unsat`, two `sat`); for one `sat` the model is still produced.
- The five-input file over two restated rules, five obligations, of which the run had four timeouts and one refutation. After the quotient rewrite: one of the four becomes `sat` in 0.2 s, and the evaluator, run by hand at that model, agrees the assertion is FALSE there, so a timeout had been hiding a counterexample; three remain timeouts. Declaring the amounts whole as well: one of those three becomes `unsat` in 0.1 s; two remain timeouts at 60 s. These last two carry equality hypotheses and the `MIN` and `MAX` cascade, and nothing here has been shown to help them.

None of these is a `proved` verdict: no implementation produced the scripts and no sample check ran.
They say the encoding change is worth building and measuring, not that the answers are right.

**Design.**

1. **The quotient rewrite** in the `FLOOR` and `CEILING` cases of `builtin` (`Lower.hs:706-708`): recognise `(/ A n)` with `n` a positive integer literal in the lowered argument, as the lowering already recognises literals. `MODULO` by a literal divisor (`:486-491`) has the same shape and is the natural second client; unmeasured.
2. **The monotonicity lemma**, emitted when the rewrite fired, with the rerun-without fallback above.
3. **Integer lowering** from §3.4, which makes `div` run on `Int` terms and the problem pure linear integer arithmetic.
4. **Region splitting** is the last resort, and has not been shown to help on the one class it was tried on. When the three steps above leave a timeout, split on a guard of an `IF` or `BRANCH` that the assertion's own atoms mention (a threshold literal the obligation reaches is `obLiterals`), run the regions, and report the regions. This is **ARGUED**; the first measurement is the `MIN` and `MAX` cascade of §1.4.
5. **Report what was tried.** Today a timeout prints `timeout after 60s`. It should print `timeout after 60s (tried: quotient rewrite, floor monotonicity, whole-number inputs; regions: none)`, so the user does not rerun with a bigger number the prover has already learned does not help. That is a loud failure with its history attached.
6. Do not tune solver options. None of the options tried helped.

**Soundness.**

| Failure                                     | Loud or silent | Caught by                                                                                                                                                                                           |
| ------------------------------------------- | -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A timeout                                   | Loud           | `unknown (timeout after Ns …)`, exit 3                                                                                                                                                              |
| A rewrite wrong for some divisor            | **Silent**     | the identity is proved per divisor: a CI test asks z3 `not (= (to_int (/ x n)) (div (to_int x) n))` for each `n` the corpus uses and requires `unsat`; the sample check also runs on every `proved` |
| A wrong lemma over-constraining the problem | **Silent**     | the same: each lemma is itself an `unsat` obligation in CI. A lemma is a theorem or it is not shipped                                                                                               |
| A split that loses a region                 | **Silent**     | the regions' guards must be exhaustive by construction (`g`, `not g`), and the report lists them; test with a deliberately gappy split                                                              |
| A lemma that turns a `sat` into `unknown`   | Loud           | the rerun without the lemma                                                                                                                                                                         |

**Landed when.**
The quotient rewrite and the lemma are in `Lower.hs`; the public example's obligations 2 and 3 are `proved` by `l4 prove` itself with the sample check passing, and are golden fixtures; the z3 identity tests exist; the timeout message lists what was tried; the user page and `proveBound` say what a timeout now means.

### 3.6 Other backends

Any other backend meets the same input kinds as `l4 prove` does, whether or not it shares its code, because the kinds come from the language and from the encodings: dates, options, truncation to a number of decimals, counts and amounts with no declared bound.
A backend that lowers through `L4.Prove.Lower` shares the code as well: `l4 coverage` is one such command today (it imports `L4.Prove.Lower` at `jl4/app/L4/Cli/Coverage.hs:73` and calls `lowerAtoms`, `:206`), so it can analyse only what the lowering accepts, and every item above widens that too.
A backend with its own lowering shares nothing but the semantics, and §3.1 to §3.4 are written to serve it: each states the evaluator's behaviour (the serial anchor, the floor in `DATE_FROM_SERIAL`, truncation toward zero with a half-to-even digit count, which inputs are integers) with a probe, so that a second lowering can be checked against the same evaluator by the same two-oracle discipline rather than by reading this spec.
The consequence for the design is that the soundness machinery has to live where the semantics are pinned, the lowering and the replay, not in the `l4 prove` command alone: a new sort that is lowered but has no sample generator, or a new built-in that is lowered but not covered by the identity tests, would be wrong for every consumer of that lowering at once.
This section makes no claim about any particular other backend.

## 4. Loud against silent, consolidated

A failure that errors teaches; the ones that return a wrong answer with exit 0 are where the words go.

| Loud (exit non-zero, named)                       | Silent (exit 0, wrong or narrower than it reads)                                                                      |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `unknown (out of fragment: …)`, exit 3            | A calendar or truncation formula wrong at a point no sample hits, inside an `unsat` proof                             |
| `unknown (timeout after Ns …)`, exit 3            | A rewrite or lemma that is not a theorem, over-constraining                                                           |
| `ENCODING DEFECT`, exit 4                         | A declared input range that some entry point does not enforce, so `proved` covers fewer inputs than the service takes |
| A type error on a literal violating a declaration | `--fixed-now` forgotten: a verdict about one day                                                                      |
| A runtime refusal of an out-of-range input        | A region split with a gap                                                                                             |

The two-oracle discipline is the backstop for the left column, and it is a backstop only for what it samples.
Every item above therefore adds samples (dates, `NOTHING`, negative arguments of `TRUNC`, in-range values for declared inputs) and a CI test that proves each rewrite and lemma it ships, rather than asking the reviewer to read it.

## 5. Order of work

Smallest first.
Each step is a separate change that lands with its tests and its documentation, and none depends on the later ones except where said.

0. **Report every refusal an assertion reaches, not the first.**
   No semantics change: lower each reached `DECIDE` independently and print the set, ``out of fragment: DATE; also: the parametric type `MAYBE`, a call to `TRUNC`, LIST``, deduplicated, on the one `unknown` line.
   Goldens that quote the old single reason change.
   This is the step that makes the rest measurable: until it runs on the 51-module encoding, nobody knows whether `DATE`, `MAYBE`, `TRUNC` and `JUST` are the whole list or the first four.
1. **`TRUNC` for a literal digit count** (§3.3). The smallest semantic change.
2. **The quotient rewrite and the monotonicity lemma** (§3.5). Independent of everything else, measured at script level to decide four of the seven timeouts re-tried on the large encoding (a fifth with whole-number inputs) and both timeouts on the public example, and it needs no language change.
3. **`DATE`** (§3.1), with the calendar sweep test.
4. **`MAYBE`, `EITHER` and parametric records** (§3.2).
5. **Integrality lifting** (§3.4 A), and the `Int` lowering it enables, which lets step 2's `div` run on integers.
6. **Instantiating polymorphic rules** (§3.2, point 4): `fromMaybe`, `isJust` and the generic prelude helpers.
7. **Declared inputs** (§3.4 B): after a ruling.
8. **Region splitting and the "what was tried" report** (§3.5), once the `MIN` and `MAX` cascade has been measured against steps 1 to 5.

**The smallest first step that would let the tax-credit properties run on the encoding's own rules.**
It is step 0, then steps 1, 3 and 4, in that order, and only if step 0 shows no further blockers (the likely candidate is `LIST`, which this spec does not propose to lower).
Step 2 should come before the properties are re-run, not after, or the restated-rule timeouts of §1.4 will simply reappear on the encoding.
This spec does not promise that the properties will then run; it promises that the first refusal will no longer be a surprise, because step 0 reports all of them.

## 6. Questions this spec does not rule

Each is a choice the first implementer makes, labelled _assumed, not ruled_, in a change that can be reverted alone.

| Question                                                                | Assumed                                                                                                                    |
| ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Monomorphic datatypes or SMT-LIB `par` for `MAYBE` (§3.2)               | monomorphic                                                                                                                |
| The `to_int` lemma: quantified or ground instance (§3.5)                | quantified, with a rerun without it on `unknown`                                                                           |
| `TODAY` under `--fixed-now` lowers to a constant (§3.1)                 | yes                                                                                                                        |
| The spelling of declared inputs (§3.4 B)                                | `@whole`, `@min n`, `@max n` after the type; this is a user-visible choice, so it goes to a ruling, not to the implementer |
| Whether declared inputs are worth their three enforcement points at all | not decided; A first                                                                                                       |
| Whether `LIST` gets a bounded encoding                                  | not in this spec                                                                                                           |

Two things are owed by whoever lands a step, per this repository's rule that a diagnostic's owner owns every page that quotes it: the "What is refused" paragraph of the user page, and the `proveBound` text printed by `l4 prove --help` (`Prove.hs:83-117`).

## 7. Appendix: the public reproduction

This file type-checks under the installed `l4`; the numbers in §3.5 come from it.
Its constants are invented; its shape (a threshold that depends on a flag, a step function built with `CEILING`, a floor at zero with `max`) is the shape that timed out.
The hand-written integer and real copies, the solver options and the region restriction of §3.5 were measured on an earlier spelling of this example with other variable names and the same constants and structure; every other §3.5 figure for it comes from this file.

```l4
IMPORT prelude

§ `Taper`
    GIVEN shared IS A BOOLEAN
          income IS A NUMBER
          units IS A NUMBER
          extras IS A NUMBER
          more IS A NUMBER

GIVEN s IS A BOOLEAN
GIVETH A NUMBER
`threshold` s MEANS IF s THEN 300000 ELSE 150000

GIVEN u IS A NUMBER
      x IS A NUMBER
GIVETH A NUMBER
`full amount` u x MEANS 3000 TIMES u PLUS 700 TIMES x

GIVEN s IS A BOOLEAN
      m IS A NUMBER
GIVETH A NUMBER
`steps over` s m MEANS
  IF m GREATER THAN `threshold` s
  THEN CEILING ((m MINUS `threshold` s) DIVIDED BY 500)
  ELSE 0

GIVEN s IS A BOOLEAN
      m IS A NUMBER
      u IS A NUMBER
      x IS A NUMBER
GIVETH A NUMBER
`amount after taper` s m u x MEANS
  max 0 (`full amount` u x MINUS 40 TIMES `steps over` s m)

-- 1. never negative, never above the full amount (needs the counts not to be negative)
#ASSERT (units AT LEAST 0 AND extras AT LEAST 0) IMPLIES (`amount after taper` shared income units extras AT LEAST 0 AND `amount after taper` shared income units extras AT MOST `full amount` units extras)

-- 2. one more unit of income never raises the amount
#ASSERT `amount after taper` shared (income PLUS 1) units extras AT MOST `amount after taper` shared income units extras

-- 3. any non-negative increase of income never raises the amount
#ASSERT (more AT LEAST 0) IMPLIES (`amount after taper` shared (income PLUS more) units extras AT MOST `amount after taper` shared income units extras)
```

`l4 prove --timeout 10 FILE` and `--timeout 60` both give `1 proved, 0 refuted, 2 unknown`, with `timeout after Ns` on the second and third.
To redo the script-level rows: `l4 prove FILE --emit-smt DIR`, then replace each `(to_int (- (/ A n)))` with `(div (to_int (- A)) n)`, and `(to_int (/ A n))` with `(div (to_int A) n)`, for a positive integer literal `n`, and run `z3 -smt2 -T:60`.
The monotonicity lemma is `(assert (forall ((a Real) (b Real)) (! (=> (<= a b) (<= (to_int a) (to_int b))) :pattern ((to_int a) (to_int b)))))`, placed before the `(assert (not (and …)))` line.

The hand-written integer encoding of obligation 2 that is `unsat` in under a second under `z3 -smt2` (an earlier spelling used other variable names and the same constants):

```
(set-logic QF_LIA)
(declare-const shared Bool)
(declare-const income Int)
(declare-const units Int)
(declare-const extras Int)
(define-fun thr () Int (ite shared 300000 150000))
(define-fun steps ((m Int)) Int (ite (> m thr) (- (div (- (- m thr)) 500)) 0))
(define-fun full () Int (+ (* 3000 units) (* 700 extras)))
(define-fun amt ((m Int)) Int (let ((x (- full (* 40 (steps m))))) (ite (>= x 0) x 0)))
(assert (not (<= (amt (+ income 1)) (amt income))))
(check-sat)
```

And the identity of §3.5 for `n = 500`, which z3 answers `unsat` (so the two sides are equal for every real `x`):

```
(set-logic QF_LIRA)
(declare-const x Real)
(assert (not (= (to_int (/ x 500.0)) (div (to_int x) 500))))
(check-sat)
```
