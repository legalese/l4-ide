# Testing Your Rules

Assert expected outcomes with `#EVAL`, `#ASSERT`, and `#CHECK`, and simulate obligations with `#TRACE`.

**Prerequisites:** [Your First L4 File](first-l4-file.md), [Using the l4 CLI](l4-cli.md)

---

## What You'll Build

A small loan rulebook with two kinds of rules — an eligibility decision and a repayment obligation — plus a test suite that lives in the same file as the rules. When the law changes and someone edits a rule, the tests say immediately whether the encoded outcomes still hold.

---

## The Testing Directives

L4 has five built-in directives. They start with `#`, appear at the top level of a file, and run every time the file is evaluated (in VS Code, on hover; on the command line, with `l4 run`):

| Directive    | What it does                                                                    |
| ------------ | ------------------------------------------------------------------------------- |
| `#EVAL`      | Evaluate an expression and show the result                                      |
| `#EVALTRACE` | Like `#EVAL`, but also show the full evaluation trace                           |
| `#ASSERT`    | Assert that a boolean expression is TRUE — your regression tests                |
| `#CHECK`     | Typecheck an expression without evaluating it, and report its inferred type     |
| `#TRACE`     | Simulate a regulative rule against a timeline of `PARTY ... DOES ... AT` events |

---

## Step 1: A Rule and Its Test Data

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

Alice should qualify; Bob is under 21 and should not.

---

## Step 2: Inspect with `#EVAL`

Add evaluation directives and run the file:

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


Evaluation[2] @ loan-rules.l4:32:1-37

Result:
  FALSE
```

`#EVAL` is exploratory: it shows you what a rule decides, but it does not say whether that is the _right_ answer. For that, use assertions.

---

## Step 3: Assert Expected Outcomes with `#ASSERT`

An `#ASSERT` records the outcome you expect. It documents the intended legal result and fails visibly when a later edit changes it:

```l4
#ASSERT `is eligible for a loan` `Alice`
#ASSERT NOT `is eligible for a loan` `Bob`
```

```
Evaluation[3] @ loan-rules.l4:34:1-41

Result:
  assertion satisfied


Evaluation[4] @ loan-rules.l4:35:1-43

Result:
  assertion satisfied
```

### What failure looks like

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

> **CI note:** `l4 run` exits non-zero for _type errors_ and for directives that _crash during evaluation_ (runtime errors), but not for failed assertions — a file with a failing `#ASSERT` still typechecks, so the exit code is `0`. In a CI pipeline, run with `--json` and check each result of `"kind": "assertion"` for `"value": false`, or simply grep the text output for `assertion failed`.

---

## Step 4: Typecheck Expressions with `#CHECK`

`#CHECK` never evaluates anything. It confirms that an expression is well-typed and reports the inferred type as an informational diagnostic:

```l4
#CHECK `is eligible for a loan`
```

```
File:     loan-rules.l4
  Range:    37:1-37:32
  Severity: DiagnosticSeverity_Information
  Message:  FUNCTION FROM Applicant TO BOOLEAN
```

This is useful for pinning down a rule's _interface_: if a refactor accidentally changes the argument types of `is eligible for a loan`, the `#CHECK` on a specific application fails with a type error even before anything runs:

```l4
#CHECK `twice` "twenty-one"
```

```
File:     failing-check.l4
  Severity: DiagnosticSeverity_Error
  Message:
    The first argument of function

      twice (defined at failing-check.l4:3:8-15)

    is expected to be of type

      NUMBER

    but is here of type

      STRING
```

---

## Step 5: A Regulative Rule to Simulate

Decisions are only half of legal drafting; the other half is obligations. Add a repayment obligation to `loan-rules.l4`:

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

This says: the borrower must repay the loan amount within 30 time units; doing so fulfills the contract, failing to do so is a breach.

---

## Step 6: Simulate Timelines with `#TRACE`

`#TRACE` runs a regulative rule against a hypothetical sequence of events. The general form is:

```l4
#TRACE deonticExpression AT startTime WITH
    PARTY partyName DOES action AT eventTime
    ...
```

### A compliant timeline

```l4
§§ `Behaviour tests`

-- The borrower repays on day 12: the obligation is fulfilled.
#TRACE `repayment obligation` 10000 AT 0 WITH
    PARTY Borrower DOES `repay loan` 10000 AT 12
```

```
Evaluation[5] @ loan-rules.l4:58:1-59:49

Result:
  FULFILLED
```

### A breaching timeline

An event only discharges an obligation if the right party does the right action in time. Here the _lender_ acts, and only on day 45 — past the 30-day deadline — so the `LEST` branch fires:

```l4
-- The wrong party, too late: the deadline passes and the LEST branch fires.
#TRACE `repayment obligation` 10000 AT 0 WITH
    PARTY Lender DOES `repay loan` 10000 AT 45
```

```
Evaluation[6] @ loan-rules.l4:62:1-63:47

Result:
  DEONTIC BREACHED:
    BREACH
    BY Borrower
    BECAUSE "the loan was not repaid on time"
```

The `BECAUSE` string you wrote in the rule is exactly what shows up in the breach report — write it for the auditor who will read it.

A `#TRACE` can also end in neither state: if the trace stops while an obligation is still open (deadline not yet reached, no discharging event), the result is the _residual_ obligation — a description of what is still owed and by whom. That is not a test failure; it tells you your timeline was incomplete.

---

## Step 7: Keep Tests Next to the Rules

Directives are ignored by deployment (`@export` publishes functions, not tests), so there is no cost to keeping a `§§ Tests` section in every rule file:

- one `#ASSERT` per legally meaningful outcome, positive and negative
- one `#TRACE` per obligation, for at least the compliant and the breaching timeline
- `#EVAL` for values a human reviewer will want to eyeball

Run the whole suite with `l4 run loan-rules.l4`; wire the same command into CI as described in [Version Control for Rules](version-control-for-rules.md).

---

## What You Learned

- `#EVAL` shows what a rule decides; `#ASSERT` pins down what it _should_ decide
- `#CHECK` typechecks an expression and reports its type without running it
- `#TRACE ... AT ... WITH PARTY ... DOES ... AT ...` simulates obligations over a timeline
- Fulfillment prints `FULFILLED`; breach prints `DEONTIC BREACHED` with your `BECAUSE` reason
- Failed assertions print `assertion failed` but do not change the exit code — check for them explicitly in CI

---

## Next Steps

- [Debugging Type Errors](debugging-type-errors.md) — when the file will not even typecheck
- [Directive reference](../../reference/syntax/README.md#directives) — full syntax of every directive
- [Regulative rules reference](../../reference/regulative/README.md) — `PARTY`, `MUST`, `MAY`, `SHANT`, `DEONTIC`
- [Version Control for Rules](version-control-for-rules.md) — running these tests on every change
