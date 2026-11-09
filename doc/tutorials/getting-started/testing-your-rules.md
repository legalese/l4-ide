# Test your rules

Check that your rules give the answers you expect, with `#EVAL` and `#ASSERT`, and simulate obligations over time with `#TRACE`.

**Before you start:** [Install L4 and write your first rule](first-l4-file.md).

You will build a small loan rulebook: an eligibility decision and a repayment obligation, with tests in the same file. When someone later edits a rule, the tests show at once whether the expected outcomes still hold.

**Complete example:** [loan-rules-example.l4](loan-rules-example.l4)

---

## The test directives

Directives start with `#` and sit at the top level of a file. VS Code runs them as you type; on the command line, `l4 run` runs them.

| Directive    | What it does                                                                                                                      |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| `#EVAL`      | Evaluates an expression and shows the result.                                                                                     |
| `#EVALTRACE` | Like `#EVAL`, and also shows each step of the evaluation.                                                                         |
| `#ASSERT`    | Evaluates a boolean expression and reports whether it is `TRUE`. `#ASSERT REFUSED` records instead that a rule declines the case. |
| `#CHECK`     | Type-checks an expression and reports its type. It evaluates nothing.                                                             |
| `#TRACE`     | Runs a regulative rule against a timeline of `PARTY ... DOES ... AT` events.                                                      |

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

`l4 run` exits with a non-zero code for type errors and for directives that fail while evaluating (including an `#ASSERT` that stops and says why, as described below), but **not** for a failed assertion: the file is still valid L4, so the exit code is `0`. In CI, look for failures explicitly: grep the output for `assertion failed`, or run `l4 run --json` and check each result whose `"kind"` is `"assertion"` for `"value": false`. [Manage rules in git and CI](version-control-for-rules.md) has a ready-made workflow.

### What an error looks like

An assertion whose expression _stops and says why_ — a division by zero, a `CONSIDER` with no matching branch, a fact named under a section heading that nothing has supplied — is neither satisfied nor failed: L4 could not decide it either way. `#ASSERT P` and `#ASSERT NOT P` then both report the same thing, with the reason:

```l4
§ `A fact nobody has supplied`
    GIVEN x IS A NUMBER

#ASSERT x EQUALS 1
```

```
Evaluation[1] @ stuck-assert.l4:4:1-19

Result:
  assertion could not be evaluated:
  I could not continue evaluating, because I needed to know the value of
    x
  but it is an assumed term.
```

This is a breakdown, not a verdict: `l4 run` exits non-zero, and with `--json` — the machine-readable output, written in JavaScript Object Notation (JSON) — the result keeps `"kind": "assertion"` with `"value": null` and the reason under `"error"`.
When the reason is a fact nobody supplied, as here, it is under `"undetermined"` instead, beside a `"needs"` list naming every fact the assertion is waiting for: here `["x"]`.

The same holds for a bare yes-or-no fact, left open the same way, asserted directly. `#ASSERT NOT b` has to know the value of `b`, and stops; `#ASSERT b` gets as far as `b` itself without stopping — but that is no verdict either, so it reports the same way rather than as `assertion failed`. (Older files leave such a fact open with `ASSUME b IS A BOOLEAN`; the report reads the same.)

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

No later rule can turn a refusal into an answer: no `IF`, `CONSIDER`, `AND` or `OR` anywhere else in the file can pick one up and put a default in its place. Only the boundary — the directive, the CLI, the application programming interface (API), the web form — ever sees it. Do not rely on the exit code to spot a refused assertion; read the output, as the paragraph above describes. See [REFUSE](../../reference/control-flow/REFUSE.md) for the whole story.

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
The first input of function

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
