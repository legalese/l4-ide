# Proving an assertion: `l4 prove`

A test checks a rule at the inputs someone thought to try.
A proof checks it at every input there is.
`l4 prove` turns some of your `#ASSERT` lines from tests into proofs, and when one is false it hands you an input that shows it.

## Why you would want a proof, not a test

Suppose a rule says a refund is never more than the price paid, and you write that down as an `#ASSERT`.
If the assertion mentions a particular price, `l4 run` checks it at that price, and it tells you nothing about the other prices.
The insurance-payout mistakes that matter are the ones at an input nobody wrote down: a boundary, a zero, a combination of two conditions that each looked harmless.

So you can write the assertion about _any_ price instead, by making the price a section `GIVEN`:

```l4
§ `Refunds`
    GIVEN price IS A NUMBER

GIVEN p IS A NUMBER
GIVETH A NUMBER
`refund for` p MEANS p TIMES 0.9

#ASSERT `refund for` price AT MOST price
```

`l4 run` cannot decide that assertion, because it has no price to compute with: it reports "assertion could not be evaluated".
`l4 prove` can, because it does not compute with one price.
It asks a different kind of program whether _any_ price makes the assertion false.

That program is an **SMT solver** ("satisfiability modulo theories"): given a logical formula over numbers, true-or-false values and records, it either finds values that make the formula true, or establishes that none exist.
`l4 prove` writes down "the assertion is false" as such a formula and hands it to the solver.
If the solver finds no solution, the assertion holds everywhere, and the verdict is `proved`.
If it finds one, that solution is a counterexample, and the verdict is `refuted`.
(The assertion above is refuted, at `price = -1`: a negative price gets a refund larger than itself. Whether that matters is a question about the rule, which is exactly what the counterexample is for.)

`l4 prove` uses [z3](https://github.com/Z3Prover/z3), a free solver from Microsoft Research.
Where z3 gives no answer, it also asks [cvc5](https://cvc5.github.io/), another free solver, if you have it installed.
No solver settles every question, and these two are good at different ones: each settles some that the other runs out of time on.

## Running it

Install z3 (`brew install z3`, `apt install z3`, or a release from the z3 repository), then:

```
l4 prove FILE.l4
```

`l4 prove` looks for the solver in `Z3_EXE` if you set it, and otherwise for `z3` on your `PATH`.
If it finds none, it stops and says so (`l4 prove: no SMT solver found: set Z3_EXE or put z3 on PATH`), and exits 1: it never reports success without having asked.

cvc5 is optional.
To use it, install it from [its releases page](https://github.com/cvc5/cvc5/releases), which publishes ready-built programs for Linux, macOS and Windows, and put it on your `PATH` or set `CVC5_EXE` to it.
Without it, `l4 prove` works as it does with z3 alone; [Two solvers](#two-solvers) says what changes when it is there.

This is the report for `assert-raises.l4`, a file in L4's own test corpus whose section takes `x IS A NUMBER` and `b IS A BOOLEAN`:

```
l4 prove: examples/ok/assert-raises.l4
  decided  assert-raises.l4:7:1-34  #ASSERT (1 DIVIDED BY 0) EQUALS 1
      not an obligation: the evaluator reports an error: Division by zero in the operation: DIVIDED BY
  ...
  refuted  assert-raises.l4:11:1-19  #ASSERT x EQUALS 1
      counterexample: x = 0
      the evaluator agrees: the assertion is FALSE there
  ...
  decided  assert-raises.l4:15:1-29  #ASSERT TRUE OR x EQUALS 1
      by evaluation: assertion satisfied
  refuted  assert-raises.l4:21:1-10  #ASSERT b
      counterexample: b = FALSE
      the evaluator agrees: the assertion is FALSE there
  ...
coverage: 9 #ASSERT: 5 decided by evaluation, not re-proved; 4 obligations: 0 proved, 4 refuted, 0 unknown
not attempted: well-definedness obligations generated without an #ASSERT (R-V2); #ASSERTs in imported files
solver: Z3 version 4.16.0 - 64 bit
```

## Reading the verdicts

Each `#ASSERT` gets one line.

- **`proved`**: no value of what the assertion reads makes it false, or makes it raise an error. The line also says at how many sample points the ordinary evaluator was asked and agreed (see below).
- **`refuted`**: here are values at which it is false, or at which evaluating it raises an error (a division by zero, say). A point where the assertion _raises_ counts against it: an assertion that crashes for some input does not hold for that input.
- **`unknown`**: no verdict, with the reason. Usually `out of fragment: …`, naming what `l4 prove` cannot reason about (see the limits below); sometimes a timeout, or the solver itself saying it does not know.
- **`decided`**: not sent to the solver at all, but still counted in the exit status: if the evaluator found the assertion FALSE, or it raised, the file fails as a refutation does. Either `l4 run` could already decide it (it reads no section `GIVEN`, or its answer does not depend on one, like `TRUE OR x EQUALS 1`), or evaluating it raised an error for a reason other than a missing input. These are counted, and not proved again.
- **`ENCODING DEFECT`**: the solver and the evaluator disagree. That is a bug in `l4 prove`, not a fact about your rules, and it is printed loudly so that nobody reads it as either.

The last lines say what was covered: how many assertions, how many the evaluator decided, and the count of each verdict; what was not attempted; and the version of each solver that was asked.

### Every answer is checked twice

`l4 prove` has to translate your rules into the solver's language, and a translation can be wrong.
So it does not take the solver's word for anything:

- A **counterexample** is run back through the ordinary L4 evaluator, the same one `l4 run` uses, with the solver's values filled in. It is reported as `refuted` only if the evaluator agrees the assertion fails there.
- A **proof** is spot-checked: the evaluator is run at up to 64 sample points (fractions first: a half, a third and a seventh either side of zero, a half either side of each number your rule mentions, and the midpoint between each two of those numbers; then zero and each number with one either side of it; both truth values; every option of a choice), so a rule that misbehaves only on numbers that are not whole is caught too, and must say TRUE at each.

Both checks apply to every answer, whichever solver gave it.

### Two solvers

z3 is asked first, about every assertion sent to a solver.
cvc5 is asked only about an assertion z3 gave no answer to: z3 ran out of time, or said itself that it does not know.
Where z3 answered, cvc5 is not asked, and the report is what it would have been without cvc5.

cvc5 is given exactly the script z3 was given, and the same time: `--timeout` is the time each solver gets for each assertion, so an assertion neither solver can settle takes up to twice that.
When cvc5 settles one, its line says so, and gives z3's reason.
This is the report for a claim that a grant, rounded to a whole number, never shrinks as the months it is paid for grow: z3 does not settle it in 10 seconds, and cvc5 proves it in a fraction of one.

```
  proved   floor-monotone.l4:16:1-38  #ASSERT `grant is monotone in months`  (the evaluator agreed at 35 sample points)
      proved by cvc5 after z3 gave no answer: timeout after 10s
coverage: 1 #ASSERT: 0 decided by evaluation, not re-proved; 1 obligation: 1 proved, 0 refuted, 0 unknown
not attempted: well-definedness obligations generated without an #ASSERT (R-V2); #ASSERTs in imported files
solver: Z3 version 4.16.0 - 64 bit
second solver: cvc5 1.4.2 [git 282d5e0 on branch HEAD], asked where z3 gave no answer: 1 obligation
```

When neither settles an assertion, the verdict is `unknown`, with z3's reason first and then cvc5's:

```
  unknown  rules.l4:12:1-60  #ASSERT …
      timeout after 10s
      cvc5, asked next, gave no answer either: timeout after 10s
```

Without cvc5 installed, an assertion z3 gave no answer to is `unknown` exactly as before, and one line at the end says how many were not retried, so you know that installing cvc5 might help.
If z3 answered everything, that line is not printed.

Output from cvc5 that `l4 prove` cannot read counts as no answer, so a cvc5 that prints something unexpected leaves an `unknown` as it was rather than turning it into a failure.
An answer from cvc5 that the evaluator disagrees with is still an `ENCODING DEFECT`, as one from z3 is.

`--solver` chooses the solvers and the order to ask them in:

| you write                   | what is asked                                               |
| --------------------------- | ----------------------------------------------------------- |
| nothing                     | z3, then cvc5 where z3 gave no answer, if cvc5 is installed |
| `--solver z3`               | z3 alone, as before there was a second solver               |
| `--solver cvc5`             | cvc5 alone; z3 need not be installed                        |
| `--solver cvc5 --solver z3` | cvc5 first, then z3 where cvc5 gave no answer               |

A solver you name with `--solver` must be found, or the run stops with exit status 1; only the cvc5 of the first row is optional.
Whichever solver is asked first is held to the strict reading: output from it that `l4 prove` cannot read is an `ENCODING DEFECT`.
Only the solver asked second gets the leniency above, so with `--solver cvc5` alone, cvc5 is read as strictly as z3 is by default.

### Exit status

| status | meaning                                                                                     |
| ------ | ------------------------------------------------------------------------------------------- |
| 0      | every assertion sent to the solver was proved, or none was sent                             |
| 1      | the file did not check, an option was wrong, or a solver it needed was not found            |
| 2      | at least one assertion was refuted, or the evaluator itself found one FALSE or saw it raise |
| 3      | at least one assertion is unknown, and none of the above                                    |
| 4      | an encoding defect (outranks the others)                                                    |

### Seeing what was sent to the solver

`l4 prove FILE --emit-smt DIR` writes the formula for each assertion to `DIR`, one `.smt2` file each, and stops without running a solver.
Each file is named after the source file and the assertion's line and column (`refunds-8-1.smt2`), starts with a comment naming the assertion's position, and is the same text, byte for byte, that `l4 prove` gives each solver when it does run one, so any other solver can be given exactly the same question.
The name carries only the file's base name, so give each source file its own `DIR`: a second run over another `refunds.l4` would overwrite the first run's files.
Within one run, two scripts that would land on one name stop the run with an error and write neither.
The files are standard SMT-LIB2, the solvers' common text format, so any SMT-LIB2 solver can read them; every name from your file is prefixed (`|l4_price|`), so none can collide with a name the solver reserves for itself, such as `pi`.

## Limits

These are stated here because you would otherwise find them out from a wrong conclusion.

- **What is in range.** True-or-false values, numbers (exactly, as fractions, never rounded), records and choices (`DECLARE … HAS` and `IS ONE OF`), `IF`, `BRANCH`, `CONSIDER`, the arithmetic and comparison operators, `MODULO`, `ROUND`, `FLOOR` and `CEILING` (all exact, with L4's own rounding: `ROUND` rounds a half to the even neighbour), local `WHERE` / `LET` names, and calls to other rules, in this file or one it imports, which are followed all the way down.
- **What is refused,** as `unknown (out of fragment: …)`: text (`STRING`), dates, lists, `MAYBE` and other types that take a parameter, rules that call themselves, functions passed as values, local definitions with parameters, `SQRT`, `LN` and the other functions with irrational results, and obligations, permissions and the rest of the regulative layer.
- **Only assertions.** It proves what you asserted. It does not, on its own, look for divisions that can divide by zero or `CONSIDER`s that miss a case anywhere else in the file.
- **Only this file's section `GIVEN`s.** An assertion that reads a section `GIVEN` declared in an imported file is `unknown`, because its counterexample could not be checked against the evaluator.
- **Only this file's assertions.** The `#ASSERT`s of imported files are not attempted, and neither are `#ASSERT REFUSED` lines.
- **Rules from other files are followed but not pre-checked.** A safety check that runs before the solver (for side effects, refusals and the like) sees only the file you named; when a proof relies on rules from an imported file, the report names them.
- **A counterexample that needs an irrational number** (for `x TIMES x EQUALS 2`, say) cannot be given as an L4 value, so the verdict is `unknown (model value not a rational: …)`, even though the assertion is refutable.
- **Arithmetic that multiplies two unknowns together** is harder for any solver; z3 often still decides it, cvc5 sometimes decides what z3 cannot, and when neither does the verdict is `unknown` with that reason.
- **cvc5 is a second chance, not a second opinion.** It is not asked to confirm what z3 proved or refuted; the evaluator's checks above are what stand behind every answer. And when z3 finds a counterexample that cannot be written as an L4 number (above), cvc5 is not asked for another.
- **Only `l4 prove` asks cvc5.** [`l4 coverage`](coverage.md) and `l4 export catala` use z3 alone.
- **A record built from a value that would raise, and then passed to another rule,** is treated as raising, even when that rule never reads the field. L4 itself is lazier than that. (A field read straight out of the record needs only that field to be defined, as in L4.) The replay catches the difference and reports it as an `ENCODING DEFECT` rather than a counterexample, so it can cost you a verdict but cannot give you a wrong one.
