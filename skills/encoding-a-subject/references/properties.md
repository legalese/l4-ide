# Claims about every input: the detail behind step 6a

Step 6a of [`SKILL.md`](../SKILL.md) says what to write.
This page is the worked example with the real output of `l4 prove` on it, the other verdicts you will meet, the comparison of an official form with the statute, and what goes in `NOTES.md`.
`l4 prove` itself is described in [Proving an assertion](https://legalese.com/l4/concepts/reviewing/proving-assertions.md).

The output below was produced on 2026-11-15 by an `l4` built from a working tree at `35aa3bd67` (`unstable`; `l4 --version` prints `dev`, which does not say which compiler it is, so this is stated here), with z3 4.16.0.
The numbers in the example are invented.

## What you need

- **z3.**
  `brew install z3` or `apt install z3`.
  `l4 prove` looks for it in `Z3_EXE`, then on `PATH`, and stops with exit status 1 if it finds none.
- **An `unstable` `l4`.**
  Main build 110 (`1.6.110 (main, e51181d, 2026-11-11)`) lists no `prove` command in `l4 --help`, and `main` rejects a section `GIVEN` (`writing-l4-rules/references/dialects.md`): the claims module below fails there with `unexpected #ASSERT` at its first claim.
  So a claims module is read by `unstable` only, whatever the target of the encoding is.
  The modules it imports are the ones the target has to read, and they are unchanged.
- **The claims module beside the rules it imports.**
  Measured: a file in a subdirectory that imports a module from its parent directory finds nothing, so a claims module cannot live in a subdirectory.
  Name it `<something>-properties.l4`: that suffix is what `check.sh` looks for.

## The worked example

A rule with a threshold, a step and a floor at zero.
An allowance of 600 for each dependant, reduced by 35 for each 250, or fraction of 250, by which income exceeds 40,000, and never reduced below zero.

```l4
IMPORT prelude

-- Invented numbers, for illustration only.
-- An allowance of 600 for each dependant, reduced by 35 for each 250, or fraction of 250,
-- by which income exceeds 40,000, and never reduced below zero.

GIVEN dependants IS A NUMBER
GIVETH A NUMBER
`allowance before reduction` dependants MEANS 600 TIMES dependants

GIVEN income IS A NUMBER
GIVETH A NUMBER
`reduction` income MEANS
  IF income AT MOST 40000
  THEN 0
  ELSE 35 TIMES CEILING ((income MINUS 40000) DIVIDED BY 250)

GIVEN dependants IS A NUMBER
      income IS A NUMBER
GIVETH A NUMBER
`allowance` dependants income MEANS
  max 0 (`allowance before reduction` dependants MINUS `reduction` income)

#ASSERT `allowance` 2 40000 EQUALS 1200
#ASSERT `allowance` 2 40001 EQUALS 1165
#ASSERT `allowance` 2 40250 EQUALS 1165
#ASSERT `allowance` 2 40251 EQUALS 1130
```

Four concrete tests, one each side of the first step.
They check the four incomes somebody thought of.
The claims go in a second module, which imports the first:

```l4
IMPORT prelude
IMPORT allowance

§ `Claims about every input`
    GIVEN dependants IS A NUMBER
          income IS A NUMBER
          `higher income` IS A NUMBER

-- Bounds, the floor. No premise needed.
-- This is the weak claim: a rule that always returned 0 would satisfy it, so it is paired with the exact change below.
#ASSERT `allowance` dependants income AT LEAST 0

-- Bounds, the ceiling. Premise: a count of dependants is not below zero.
-- Without it, a negative count makes the amount before reduction negative, and the floor at zero lifts the allowance above it.
#ASSERT dependants AT LEAST 0 IMPLIES `allowance` dependants income AT MOST `allowance before reduction` dependants

-- The exact change at the threshold, the sharp claim.
-- The first unit over 40,000, and every income up to 40,250, costs one whole step of 35.
-- Premise: at least one dependant, because with none the allowance is 0 on both sides of the threshold.
#ASSERT dependants AT LEAST 1 AND income GREATER THAN 40000 AND income AT MOST 40250 IMPLIES `allowance` dependants income EQUALS `allowance before reduction` dependants MINUS 35

-- Direction: more income never raises the reduction. No premise.
-- One claim for each place the two incomes can sit relative to the threshold, and each premise says where BOTH sit.
#ASSERT income AT MOST `higher income` AND `higher income` AT MOST 40000 IMPLIES `reduction` income AT MOST `reduction` `higher income`
#ASSERT income AT MOST 40000 AND 40000 LESS THAN `higher income` IMPLIES `reduction` income AT MOST `reduction` `higher income`
#ASSERT 40000 LESS THAN income AND income AT MOST `higher income` AND 40000 LESS THAN `higher income` IMPLIES `reduction` income AT MOST `reduction` `higher income`
```

Every claim reads a section `GIVEN` of this module, so `l4 run` cannot decide it and `l4 prove` can.
Each claim says what it means to a reader, and each premise has a comment saying why it is there.
The first and third claims are a pair: the first holds for a rule that never pays anything, and the third holds only for a rule that reduces by exactly one step at the first unit over the threshold.

`l4 check` on the claims module:

```text
Check succeeded.
```

and `l4 prove` on it:

```text
l4 prove: allowance-properties.l4
  proved   allowance-properties.l4:11:1-49  #ASSERT (allowance OF dependants, income) AT LEAST 0  (the evaluator agreed at 45 sample points)
  proved   allowance-properties.l4:15:1-116  #ASSERT (dependants AT LEAST 0) IMPLIES ((allowance OF dependants, income) AT MOST (`allowance before reduction` OF dependants))  (the evaluator agreed at 45 sample points)
  proved   allowance-properties.l4:20:1-179  #ASSERT (dependants AT LEAST 1 AND income GREATER THAN 40000 AND income AT MOST 40250) IMPLIES ((allowance OF dependants, income) EQUALS ((`allowance before reduction` OF dependants) MINUS 35))  (the evaluator agreed at 62 sample points)
  proved   allowance-properties.l4:24:1-136  #ASSERT (income AT MOST `higher income` AND `higher income` AT MOST 40000) IMPLIES ((reduction OF income) AT MOST (reduction OF `higher income`))  (the evaluator agreed at 38 sample points)
  proved   allowance-properties.l4:25:1-128  #ASSERT (income AT MOST 40000 AND 40000 LESS THAN `higher income`) IMPLIES ((reduction OF income) AT MOST (reduction OF `higher income`))  (the evaluator agreed at 38 sample points)
  proved   allowance-properties.l4:26:1-165  #ASSERT (40000 LESS THAN income AND income AT MOST `higher income` AND 40000 LESS THAN `higher income`) IMPLIES ((reduction OF income) AT MOST (reduction OF `higher income`))  (the evaluator agreed at 38 sample points)
coverage: 6 #ASSERT: 0 decided by evaluation, not re-proved; 6 obligations: 6 proved, 0 refuted, 0 unknown
not attempted: well-definedness obligations generated without an #ASSERT (R-V2); #ASSERTs in imported files; safety analysis of the imported decisions unfolded (`allowance before reduction`, `reduction`, `allowance`, `max`)
solver: Z3 version 4.16.0 - 64 bit
```

`l4 prove` exits 0 when every claim is proved.
All six claims are proved, and each proof was also spot-checked by the ordinary evaluator, at 38 to 62 sample points.

What `check.sh` prints for the same directory (the main columns are for `allowance.l4`, the one module `main` can read; the claims module is checked with `l4 prove` only):

```text
target: main. Each module is run with your l4 and with the main build below; the main columns must match.
main build: 1.6.110 (main, e51181d, 2026-11-11)
module                                    errors satisfied  failed  refused  expected | errors satisfied  failed  refused  main
allowance.l4                                   0         4       0        0         0 |      0         4       0        0  same
TOTAL (1 modules)                              0         4       0        0           |      0         4       0        0
(a failed assertion is also an error; any other error, or any refused assertion, makes the run red)

claims, checked with l4 prove             proved  refuted  unknown  expected
allowance-properties.l4                        6        0        0         0
    solver: Z3 version 4.16.0 - 64 bit
(claims modules are not run with l4 run and not run on main: a section GIVEN is rejected by main, and main build 110 has no prove command. An unknown is not a pass; read the verdict lines yourself)
(target main: every module has the same four counts on the main build. That rules out a module main rejects and a difference an assertion shows; it does not see a different TRACE outcome, or any difference no assertion exercises)
```

## The other verdicts, from the same example

**`refuted`.**
Take the premise off the ceiling claim:

```l4
#ASSERT `allowance` dependants income AT MOST `allowance before reduction` dependants
```

```text
l4 prove: allowance-properties.l4
  ...
  refuted  allowance-properties.l4:15:1-86  #ASSERT (allowance OF dependants, income) AT MOST (`allowance before reduction` OF dependants)
      counterexample: dependants = -1, income = -250
      the evaluator agrees: the assertion is FALSE there
  ...
coverage: 6 #ASSERT: 0 decided by evaluation, not re-proved; 6 obligations: 5 proved, 1 refuted, 0 unknown
```

The counterexample is a negative number of dependants, which no real case has, and which is the reason the premise exists.
A `refuted` verdict is either a missing premise, as here, or a rule that is wrong.
Read the counterexample to decide which.

**`unknown`, from a timeout.**
The direction claim, written as one claim for the whole rule instead of one for each place the incomes can sit:

```l4
#ASSERT income AT MOST `higher income` IMPLIES `reduction` income AT MOST `reduction` `higher income`
```

```text
l4 prove: allowance-properties.l4
  ...
  unknown  allowance-properties.l4:24:1-102  #ASSERT (income AT MOST `higher income`) IMPLIES ((reduction OF income) AT MOST (reduction OF `higher income`))
      timeout after 10s
  ...
coverage: 4 #ASSERT: 0 decided by evaluation, not re-proved; 4 obligations: 3 proved, 0 refuted, 1 unknown
```

That is not a pass.
It says z3 4.16.0 did not decide the claim in 10 seconds (`--timeout SECONDS` raises that; the same claim was still `unknown` after 120).
In this example the three-claim form above is what the solver decides.
What made the difference is the premise that says where both incomes sit: with the last premise of the third claim (that the higher income is also over 40,000) taken out, the third claim times out as well.
The same claim written for the whole allowance, and not for the reduction alone, is `unknown` in the third place too, and so is the step bound (one more unit of income raises the reduction by at most 35) above the threshold.
Those two belong in `NOTES.md` as `unknown`, each with its claim and the timeout.
The concrete tests and the proved exact-change claim are what stands in for them, and the notes say so.

**`unknown`, from an input the prover refuses.**
`l4 prove` does not reason about dates, `MAYBE` values, text, lists, recursion, or the regulative layer:

```l4
IMPORT prelude
IMPORT daydate

§ `Dates`
    GIVEN born IS A DATE
          today IS A DATE

#ASSERT today AT LEAST born IMPLIES born AT MOST today
```

```text
l4 prove: date-properties.l4
  unknown  date-properties.l4:8:1-55  #ASSERT (today AT LEAST born) IMPLIES (born AT MOST today)
      out of fragment: DATE
coverage: 1 #ASSERT: 0 decided by evaluation, not re-proved; 1 obligation: 0 proved, 0 refuted, 1 unknown
not attempted: well-definedness obligations generated without an #ASSERT (R-V2); #ASSERTs in imported files
```

Write the claim over the date-free part instead.
If a rule reads a date only to look up a number (a year's threshold, an age in whole years), state the claim for the rule that takes the number, and say in `NOTES.md` which inputs were fixed and which rule was left unproved.
A claim that has been rewritten this way says less than the one you wanted, and the notes say so.

## An official form against the statute

Where an official form, worksheet or calculator implements the same rule and is also encoded, compare the two over every input, once in each direction.
A worksheet for the allowance, invented like the rest, whose line 2 divides by 250, drops the remainder and adds 1:

```l4
IMPORT prelude

-- Invented numbers, for illustration only. The worksheet that goes with the allowance:
-- line 1, income over 40,000; line 2, divide line 1 by 250, drop any remainder, then add 1;
-- line 3, multiply line 2 by 35; line 4, 600 times the number of dependants less line 3, or 0 if line 3 is larger.

GIVEN dependants IS A NUMBER
      income IS A NUMBER
GIVETH A NUMBER
`allowance by the worksheet` dependants income MEANS
  IF income AT MOST 40000
  THEN 600 TIMES dependants
  ELSE max 0 (600 TIMES dependants MINUS 35 TIMES (FLOOR ((income MINUS 40000) DIVIDED BY 250) PLUS 1))
```

```l4
IMPORT prelude
IMPORT allowance
IMPORT worksheet

§ `The worksheet against the allowance, for every input`
    GIVEN dependants IS A NUMBER
          income IS A NUMBER

-- Premise on both claims: the number of dependants is a whole number, not below zero.

-- The worksheet gives at least what the allowance gives.
#ASSERT dependants AT LEAST 0 AND dependants EQUALS FLOOR dependants IMPLIES `allowance by the worksheet` dependants income AT LEAST `allowance` dependants income

-- The worksheet gives at most what the allowance gives.
#ASSERT dependants AT LEAST 0 AND dependants EQUALS FLOOR dependants IMPLIES `allowance by the worksheet` dependants income AT MOST `allowance` dependants income
```

```text
l4 prove: worksheet-properties.l4
  refuted  worksheet-properties.l4:12:1-163  #ASSERT (dependants AT LEAST 0 AND dependants EQUALS (FLOOR OF dependants)) IMPLIES ((`allowance by the worksheet` OF dependants, income) AT LEAST (allowance OF dependants, income))
      counterexample: dependants = 2, income = 48500
      the evaluator agrees: the assertion is FALSE there
  unknown  worksheet-properties.l4:15:1-162  #ASSERT (dependants AT LEAST 0 AND dependants EQUALS (FLOOR OF dependants)) IMPLIES ((`allowance by the worksheet` OF dependants, income) AT MOST (allowance OF dependants, income))
      timeout after 10s
coverage: 2 #ASSERT: 0 decided by evaluation, not re-proved; 2 obligations: 0 proved, 1 refuted, 1 unknown
not attempted: well-definedness obligations generated without an #ASSERT (R-V2); #ASSERTs in imported files; safety analysis of the imported decisions unfolded (`allowance before reduction`, `allowance by the worksheet`, `reduction`, `allowance`, `max`)
solver: Z3 version 4.16.0 - 64 bit
```

The first claim is refuted, and the counterexample is a finding: at that income the worksheet gives less than the allowance does.
The income in it, 48,500, is exactly 34 steps of 250 over the threshold, where "a fraction of 250" counts 34 steps and "drop the remainder, then add 1" counts 35.
Record it in `NOTES.md` with the counterexample and the line of the worksheet it comes from, and leave both encodings as they are.
Neither is "fixed" here: the statute is the law and the worksheet is what people file, and which of them is wrong, or whether the difference is intended, is for the reviewer.
The second claim is `unknown`: z3 did not decide it in 10 seconds, so nothing has been shown about the other direction, and the notes say that and nothing more.
(Reading the two rules, the worksheet's number of steps is never below the allowance's, which would make the second claim true; that is a reading, not a verdict.)

## What goes in `NOTES.md`

One short section, **Claims about every input**, with:

- the build of `l4` and the version of z3 that produced the verdicts;
- the verdict lines, copied from `l4 prove` or from the rows `check.sh` prints, one for each claim: `proved`, `refuted` with its counterexample, `unknown` with its reason;
- for each `refuted`, whether it is a missing premise (then add the premise and say why) or a finding about the rule or the form (then leave it, and list it with the other findings);
- for each `unknown`, the claim, the reason, and what stands in for it;
- for each input the prover refuses, what was fixed to write the claim without it;
- which claims are weak and which are sharp, so a reviewer can see that a bound is not the only thing standing.

A claim that stays `refuted` or `unknown` stays in the module, because deleting it deletes the record, and `expected_open` in `check.sh` names how many of those a module keeps (zero unless you list it).
