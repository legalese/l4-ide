# Testing Your Rules

Write down the answers you expect with `#EVAL`, `#ASSERT` and `#CHECK`, and play an obligation out over a timeline with `#TRACE`.

**Prerequisites:** [Your First L4 File](first-l4-file.md), [Using the l4 command-line interface (CLI)](l4-cli.md)

---

## What You'll Build

A small loan rulebook with two kinds of rules — an eligibility decision and a repayment obligation — plus a test suite that lives in the same file as the rules. When the law changes and someone edits a rule, the tests say immediately whether the encoded outcomes still hold.

---

## The five testing instructions

L4 has five built-in instructions you can write into a rule file to ask it something — each one is a **"directive"**. They start with `#`, stand on their own at the top level of a file, and run every time the file is run (in VS Code, on hover; on the command line, with `l4 run`):

| Directive    | What it does                                                                                                                                           |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `#EVAL`      | Work out one piece of a rule (an **"expression"**) and show the answer                                                                                 |
| `#EVALTRACE` | Like `#EVAL`, but also show every step it took to get there                                                                                            |
| `#ASSERT`    | Record that a yes-or-no expression should come out TRUE — your regression tests; `#ASSERT REFUSED` records instead that a rule should decline the case |
| `#CHECK`     | Confirm that an expression fits together, without working out an answer, and report what kind of thing it would give                                   |
| `#TRACE`     | Play an obligation out against a timeline of `PARTY ... DOES ... AT` events                                                                            |

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

Add two `#EVAL` directives and run the file:

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

`#EVAL` is for looking around: it shows you what a rule decides, but it does not say whether that is the _right_ answer. For that, use assertions.

---

## Step 3: Assert Expected Outcomes with `#ASSERT`

An `#ASSERT` records the outcome you expect. It writes down the intended legal result, and fails visibly when a later edit changes it:

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

### What an error looks like

An assertion whose expression _stops and says why_ — a division by zero, a `CONSIDER` with no matching branch, a name that is only `ASSUME`d — is neither satisfied nor failed: L4 could not decide it either way. `#ASSERT P` and `#ASSERT NOT P` then both report the same thing, with the reason:

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

This is a breakdown, not a verdict: `l4 run` exits non-zero, and with `--json` — the machine-readable output, written in JavaScript Object Notation (JSON) — the result keeps `"kind": "assertion"` with `"value": null` and the reason under `"error"`.

The same holds for a bare `ASSUME`d yes-or-no name asserted directly. `#ASSERT NOT b` has to know the value of `b`, and stops; `#ASSERT b` gets as far as `b` itself without stopping — but that is no verdict either, so it reports the same way rather than as `assertion failed`.

### What a refusal looks like

A fourth outcome is neither a verdict nor a breakdown. A rule can be written to _decline_ a case with `REFUSE "..."`: this case is outside what the encoding covers, and here is the sentence saying so. Regulation Crowdfunding took effect in 2016, so an encoding of it has no dollar figure to give for an earlier year, and refuses rather than inventing one:

```l4
GIVEN year IS A NUMBER
GIVETH A NUMBER
DECIDE `funding limit for` IS
    IF year AT LEAST 2016
    THEN 5000000
    ELSE REFUSE "no Regulation Crowdfunding figure exists before commencement in 2016"
```

A plain `#ASSERT` does not test that. Asked about 2015, it reports the refusal — which is neither `assertion satisfied` nor `assertion failed`:

```
Result:
  assertion refused:
  The model refuses to answer:
    no Regulation Crowdfunding figure exists before commencement in 2016
```

To pin down that a case refuses — and declining is often the legally meaningful outcome — use `#ASSERT REFUSED`. Add `BECAUSE` to require the message too, which says _which_ refusal you expected when a rule has more than one:

```l4
#ASSERT REFUSED `funding limit for` 2015
#ASSERT REFUSED `funding limit for` 2015 BECAUSE "no Regulation Crowdfunding figure exists before commencement in 2016"
```

Both report the same thing when the rule does refuse with that message:

```
Result:
  assertion satisfied
```

If the rule had produced a number instead, the first would report `assertion failed: expected a refusal, but the expression produced a value`; if it refused with different wording, the second would report `assertion failed: expected the refusal "…", got "…"`.

No later rule can turn a refusal into an answer: no `IF`, `CONSIDER`, `AND` or `OR` anywhere else in the file can pick one up and put a default in its place. Only the boundary — the directive, the CLI, the application programming interface (API), the web form — ever sees it. Do not rely on the exit code to spot a refused assertion; read the output, as the note below describes. See [REFUSE](../../reference/control-flow/REFUSE.md) for the whole story.

> **Note for continuous integration (CI), the automated build that re-runs your tests on every change:** `l4 run` exits non-zero for _type errors_ and for directives that stop part-way through (including an `#ASSERT` that stops and says why), but not for failed assertions — L4 still accepts a file with a failing `#ASSERT`, so the exit code is `0`. In a CI pipeline, run with `--json` and check each result of `"kind": "assertion"` for `"value": false`, or grep the text output for `assertion failed`.

---

## Step 4: Check that a rule fits together, with `#CHECK`

`#CHECK` never works anything out. It confirms that an expression fits together, and reports what kind of thing it would give, as an informational message:

```l4
#CHECK `is eligible for a loan`
```

```
File:     loan-rules.l4
  Range:    37:1-37:32
  Severity: DiagnosticSeverity_Information
  Message:  FUNCTION FROM Applicant TO BOOLEAN
```

This is useful for pinning down what a rule asks for and gives back: if a tidy-up accidentally changes the kinds of thing `is eligible for a loan` is told about, the `#CHECK` on a particular use fails with a type error before anything is run:

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

The `BECAUSE` text you wrote in the rule is exactly what shows up in the breach report — write it for the auditor who will read it.

A `#TRACE` can also end in neither state: if the trace stops while an obligation is still open (deadline not yet reached, no discharging event), the result is the _residual_ obligation — a description of what is still owed and by whom. That is not a test failure; it tells you your timeline was incomplete.

---

## Step 7: Keep Tests Next to the Rules

Directives are ignored when a file is deployed (`@export` publishes rules, not tests), so there is no cost to keeping a `§§ Tests` section in every rule file:

- one `#ASSERT` per legally meaningful outcome, positive and negative
- one `#TRACE` per obligation, for at least the compliant and the breaching timeline
- `#EVAL` for values a human reviewer will want to eyeball

Run the whole suite with `l4 run loan-rules.l4`; wire the same command into CI as described in [Version Control for Rules](version-control-for-rules.md).

---

## What You Learned

- `#EVAL` shows what a rule decides; `#ASSERT` pins down what it _should_ decide
- `#CHECK` confirms an expression fits together and reports what kind of thing it would give, without running it
- `#TRACE ... AT ... WITH PARTY ... DOES ... AT ...` plays an obligation out over a timeline
- Fulfillment prints `FULFILLED`; breach prints `DEONTIC BREACHED` with your `BECAUSE` reason
- Failed assertions print `assertion failed` but do not change the exit code — check for them explicitly in CI; an assertion that _stops and says why_ prints `assertion could not be evaluated` with the reason, and does fail the run
- An expression that _refuses_ is neither satisfied nor failed; test it with `#ASSERT REFUSED`, optionally `BECAUSE "the message"`

---

## Next Steps

- [Debugging Type Errors](debugging-type-errors.md) — when L4 will not even accept the file
- [Directive reference](../../reference/syntax/README.md#directives) — the full spelling of every directive
- [Regulative rules reference](../../reference/regulative/README.md) — `PARTY`, `MUST`, `MAY`, `SHANT`, `DEONTIC`
- [Version Control for Rules](version-control-for-rules.md) — running these tests on every change
