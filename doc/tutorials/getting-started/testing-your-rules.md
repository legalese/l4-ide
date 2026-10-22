# Test your rules

Check that your rules give the answers you expect, with `#EVAL` and `#ASSERT`, and simulate obligations over time with `#TRACE`.

**Before you start:** [Install L4 and write your first rule](first-l4-file.md).

You will build a small loan rulebook: an eligibility decision and a repayment obligation, with tests in the same file. When someone later edits a rule, the tests show at once whether the expected outcomes still hold.

**Complete example:** [loan-rules-example.l4](loan-rules-example.l4)

---

## The test directives

Directives start with `#` and sit at the top level of a file. VS Code runs them as you type; on the command line, `l4 run` runs them.

| Directive    | What it does                                                                 |
| ------------ | ---------------------------------------------------------------------------- |
| `#EVAL`      | Evaluates an expression and shows the result.                                |
| `#EVALTRACE` | Like `#EVAL`, and also shows each step of the evaluation.                    |
| `#ASSERT`    | Evaluates a boolean expression and reports whether it is `TRUE`.             |
| `#CHECK`     | Type-checks an expression and reports its type. It evaluates nothing.        |
| `#TRACE`     | Runs a regulative rule against a timeline of `PARTY ... DOES ... AT` events. |

The [syntax reference](../../reference/syntax/README.md#directives) has the exact form of each.

---

## Step 1: A rule and its test data

Create `loan-rules.l4`:

```l4
-- loan-rules.l4
-- An eligibility rule and a repayment obligation, with tests.

§ `Loan Rules`

DECLARE Applicant
    HAS `name`          IS A STRING
        `age`           IS A NUMBER
        `annual income` IS A NUMBER

GIVEN applicant IS AN Applicant
GIVETH A BOOLEAN
DECIDE `is eligible for a loan` IF
        applicant's `age` AT LEAST 21
    AND applicant's `annual income` AT LEAST 30000

§§ `Test data`

`Alice` MEANS Applicant WITH
    `name`          IS "Alice"
    `age`           IS 34
    `annual income` IS 55000

`Bob` MEANS Applicant WITH
    `name`          IS "Bob"
    `age`           IS 19
    `annual income` IS 42000
```

Alice should qualify. Bob is under 21 and should not.

---

## Step 2: See results with `#EVAL`

Add these lines to the end of the file and run it:

```l4
§§ `Tests`

#EVAL `is eligible for a loan` `Alice`
#EVAL `is eligible for a loan` `Bob`
```

```bash
l4 run loan-rules.l4
```

```
Evaluation[1] @ loan-rules.l4:31:1-39

Result:
  TRUE
...

Evaluation[2] @ loan-rules.l4:32:1-37

Result:
  FALSE
...
```

`#EVAL` shows what a rule decides, but not whether that is the right answer. For that, use `#ASSERT`.

---

## Step 3: Pin down outcomes with `#ASSERT`

An `#ASSERT` states the outcome you expect. It records the intended legal result and fails visibly when a later edit changes it:

```l4
#ASSERT `is eligible for a loan` `Alice`
#ASSERT NOT `is eligible for a loan` `Bob`
```

Each prints `assertion satisfied`. To compare a value instead of a boolean, use `EQUALS` or `=`. A failing assertion looks like this:

```l4
GIVEN x IS A NUMBER
GIVETH A NUMBER
DECIDE `twice` IS x TIMES 2

#ASSERT `twice` 21 EQUALS 40
```

```
Evaluation[1] @ failing-assert.l4:5:1-29

Result:
  assertion failed
```

### What an error looks like

An assertion whose expression _raises_ — a division by zero, a `CONSIDER` with no matching branch, a term that is only `ASSUME`d — is neither satisfied nor failed: the evaluator could not decide it. `#ASSERT P` and `#ASSERT NOT P` then both report the same thing, with the reason:

```l4
ASSUME x IS A NUMBER

#ASSERT x EQUALS 1
```

```
Evaluation[1] @ stuck-assert.l4:3:1-19

Result:
  assertion could not be evaluated:
  I could not continue evaluating, because I needed to know the value of
    x
  but it is an assumed term.
```

This is a crash, not a verdict: `l4 run` exits non-zero, and in `--json` the result keeps `"kind": "assertion"` with `"value": null` and the reason under `"error"`.

The same holds when you assert an `ASSUME`d `BOOLEAN` directly: `#ASSERT b` and `#ASSERT NOT b` both report `assertion could not be evaluated`, because `b` has no value to check.

### What a refusal looks like

A fourth outcome is neither a verdict nor a breakdown. A rule can be written to _decline_ a case with `REFUSE "..."`: this case is outside what the encoding covers, and here is the sentence saying so. A grant scheme that began in 2016 has nothing to say about 2015, so an encoding of its funding limit declines to:

```l4
GIVEN year IS A NUMBER
GIVETH A NUMBER
DECIDE `funding limit for` IS
    IF year AT LEAST 2016
    THEN 5000000
    ELSE REFUSE "the scheme began in 2016, so no funding limit exists before then"
```

Asked about 2015, a plain `#ASSERT` over it reports the refusal, which is neither `assertion satisfied` nor `assertion failed`:

```l4
#ASSERT `funding limit for` 2015 EQUALS 5000000
```

```
Evaluation[1] @ funding.l4:8:1-48

Result:
  assertion refused:
  The model refuses to answer:
    the scheme began in 2016, so no funding limit exists before then
```

`#ASSERT NOT` over the same expression reports the refusal too: `NOT` has to know the value, and there is none. A refusal is an answer of its own kind and not a crash, so `l4 run` exits `0`; in `--json` the result keeps `"kind": "assertion"` with `"value": null` and the reason under `"refused"`, not under `"error"`. [REFUSE](../../reference/control-flow/REFUSE.md) has the rest.

`l4 run` exits with a non-zero code for type errors and for directives that fail while evaluating, but **not** for a failed assertion or a refusal: the file is still valid L4, so the exit code is `0`. In CI, look for them explicitly: grep the output for `assertion failed` and `assertion refused`, or run `l4 run --json` and check that each result whose `"kind"` is `"assertion"` has `"value": true`. [Manage rules in git and CI](version-control-for-rules.md) has a ready-made workflow.

---

## Step 4: Type-check with `#CHECK`

`#CHECK` never evaluates anything. It only type-checks an expression and reports its type as an information message:

```l4
#CHECK `is eligible for a loan`
```

```
Message:  FUNCTION FROM Applicant TO BOOLEAN
```

Use it to pin down a rule's inputs and output. If a later edit changes what `` `is eligible for a loan` `` accepts, a `#CHECK` that applies it to an example becomes a type error, before anything runs. With the `twice` rule from Step 3:

```l4
GIVEN x IS A NUMBER
GIVETH A NUMBER
DECIDE `twice` IS x TIMES 2

#CHECK `twice` "twenty-one"
```

```
The first argument of function

  twice (defined at failing-check.l4:3:8-15)

is expected to be of type

  NUMBER

but is here of type

  STRING
```

Because `#CHECK` does not evaluate, it cannot tell you whether a rule gives the right answer. Use `#ASSERT` for that.

---

## Step 5: A regulative rule to simulate

Decisions are half of legal drafting; obligations are the other half. Add a repayment obligation to `loan-rules.l4`:

```l4
§§ `Repayment obligation`

DECLARE Actor IS ONE OF Borrower, Lender

DECLARE RepaymentAction IS ONE OF
    `repay loan` HAS amount IS A NUMBER

GIVEN `loan amount` IS A NUMBER
GIVETH A DEONTIC Actor RepaymentAction
DECIDE `repayment obligation` IS
    PARTY Borrower
    MUST `repay loan` `loan amount`
    WITHIN 30
    HENCE FULFILLED
    LEST BREACH BY Borrower BECAUSE "the loan was not repaid on time"
```

The borrower must repay the loan amount within 30 time units. Doing so fulfils the obligation; not doing so is a breach.

---

## Step 6: Simulate timelines with `#TRACE`

`#TRACE` runs a regulative rule against a sequence of events: `#TRACE rule AT start-time WITH` followed by one `PARTY ... DOES ... AT time` line per event.

**A compliant timeline:**

```l4
§§ `Behaviour tests`

-- The borrower repays on day 12: the obligation is fulfilled.
#TRACE `repayment obligation` 10000 AT 0 WITH
    PARTY Borrower DOES `repay loan` 10000 AT 12
```

```
Result:
  FULFILLED
```

**A breaching timeline.** An event discharges an obligation only if the right party does the right action in time. Here the lender acts, on day 45, after the 30-day deadline, so the `LEST` branch applies:

```l4
-- The wrong party, too late: the deadline passes and the LEST branch fires.
#TRACE `repayment obligation` 10000 AT 0 WITH
    PARTY Lender DOES `repay loan` 10000 AT 45
```

```
Result:
  DEONTIC BREACHED:
    BREACH
    BY Borrower
    BECAUSE "the loan was not repaid on time"
```

The `BECAUSE` text in the rule appears in the breach report, so write it for the person who will read it.

A trace can also end with neither result. If the events stop while an obligation is still open (the deadline has not passed and nothing discharged it), the result is the remaining obligation: what is still owed, by whom, and how long is left. That is not a failure; it means the timeline is incomplete.

---

## Keep tests next to the rules

Deployment publishes only the functions marked `@export`, so a `§§ Tests` section can stay in every rule file. A good minimum:

- one `#ASSERT` per legally meaningful outcome, positive and negative, and on both sides of each threshold;
- one `#TRACE` per obligation, for at least a compliant and a breaching timeline;
- `#EVAL` for values a reviewer will want to see.

Run the whole suite with `l4 run loan-rules.l4`.

---

## Next steps

- [Fix errors](debugging-type-errors.md): when the file does not type-check.
- [Manage rules in git and CI](version-control-for-rules.md): run these tests on every change.
- [Regulative rules](../../reference/regulative/README.md): `PARTY`, `MUST`, `MAY`, `SHANT` and `DEONTIC`.
