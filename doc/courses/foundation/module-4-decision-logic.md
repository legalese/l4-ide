# Module 4: Decision logic

In this module, you'll learn how to encode **constitutive rules** - legal rules that determine facts, classifications, and eligibility.

## Learning Objectives

By the end of this module, you will be able to:

- Distinguish between constitutive rules (decision logic) and regulative rules (obligations)
- Express eligibility determinations using DECIDE
- Define computations and definitions using MEANS
- Write function signatures with GIVEN and GIVETH
- Break down complex calculations with WHERE
- Write decision logic that reads like legal text

---

## What is Decision Logic?

### Constitutive vs Regulative Rules

Legal systems contain two types of rules:

**Regulative rules** (Modules 1 and 6) specify what parties **must**, **may**, or **must not** do:

- "The applicant **must** submit documentation **within** 30 days"
- "The landlord **may** terminate the lease if rent is unpaid"
- "The seller **shall not** disclose confidential information"

**Constitutive rules** (this module) determine **facts**, **classifications**, and **eligibility**:

- "An applicant **is eligible** if they are a citizen and over 18"
- "The tax owed **is** 20% of gross income minus deductions"
- "A person **is a resident** if they have lived here for 183 days or more"

In L4, we express constitutive rules as **decision logic** using functions. [Definitions and duties](../../concepts/legal-modeling/constitutive-vs-regulative.md) explains why L4 keeps the two kinds apart.

---

### Every input is declared

A decision in L4 can only use what its `GIVEN` declares, so the signature lists every fact the decision depends on. When someone says "it depends", L4 makes them say on what. [Functional purity](../../concepts/language-design/principles.md#functional-purity) explains why this matters for legal rules.

---

## Working Examples

All examples in this module are in: [module-4-examples.l4](module-4-examples.l4)

---

## Basic Decisions with DECIDE

### Eligibility Determinations

The most common legal decision: "Does X qualify?"

```l4
GIVEN `the applicant` IS A Person
GIVETH A BOOLEAN
DECIDE `the applicant is eligible for benefits` IF
    `the applicant is a citizen`
    AND `the applicant's age` >= 18
    AND NOT `the applicant is disqualified`
```

Use **DECIDE IF** for yes/no questions, with the conditions after `IF` joined by `AND`, `OR` and `NOT`.

### Classification Rules

"What category does X fall into?"

Use `BRANCH` for multi-way classification decisions:

```l4
GIVEN `the income` IS A NUMBER
GIVETH A STRING
DECIDE `the tax bracket` IS
    BRANCH
        IF `the income` < 10000 THEN "low"
        IF `the income` < 50000 THEN "medium"
        OTHERWISE "high"
```

`BRANCH` reads like a legal test with several conditions, and avoids the indentation problems of nested `IF`s ([Module 3](module-3-control-flow.md#multi-way-decisions-with-branch)).

### DECIDE IS vs DECIDE IF

``DECIDE `the person is an adult` IF age >= 18`` and ``DECIDE `the person is an adult` IS age >= 18`` mean the same. Use `IF` when the rule reads like a legal condition, and `IS` with a `BRANCH` for a classification, as above.

---

## Computations with MEANS

### Defining Calculations

Use **MEANS** to define computed values and formulas:

```l4
GIVEN `the gross income` IS A NUMBER
      `the deductions` IS A NUMBER
GIVETH A NUMBER
`the taxable income` MEANS
    `the gross income` - `the deductions`
```

### DECIDE vs MEANS

Both define things. Use whichever reads better:

| Use DECIDE when...                | Use MEANS when...                 |
| --------------------------------- | --------------------------------- |
| Asking a yes/no question          | Defining a value or computation   |
| Determining classification/status | Stating what something equals     |
| Condition reads naturally with IF | Definition reads naturally with = |

``DECIDE `the person is an adult` IF age >= 18`` reads more naturally than `` `the person is an adult` MEANS age >= 18 ``, and `` `the net income` MEANS `gross income` - `expenses` `` more naturally than the same with `DECIDE … IS`. All four are valid.

---

## Function Signatures

Every decision or computation has a **signature** that declares:

1. **Inputs** (`GIVEN`): what information is needed, one name and type per input
2. **Output** (`GIVETH`): what type of result is produced

| The rule is a... | Typical signature                                                     |
| ---------------- | --------------------------------------------------------------------- |
| Yes/no decision  | ``GIVEN `the person` IS A Person`` and `GIVETH A BOOLEAN`             |
| Classification   | ``GIVEN `the entity` IS AN Entity`` and `GIVETH A STRING`, or an enum |
| Computation      | ``GIVEN `the income` IS A NUMBER`` and `GIVETH A NUMBER`              |

A rule can have several inputs. List each on its own line, aligned under the first:

```l4
GIVEN `the days since the decision` IS A NUMBER
      `the appeal period in days` IS A NUMBER
GIVETH A BOOLEAN
DECIDE `the appeal is in time` IF
    `the days since the decision` AT MOST `the appeal period in days`
```

Callers pass the arguments in the order of the `GIVEN` lines: `` `the appeal is in time` 10 21 `` is `TRUE`. Other result types include `GIVETH A Person` (a record), `GIVETH A LIST OF NUMBER` and `GIVETH A MAYBE NUMBER`.

L4 can usually work out the result type on its own, so `GIVETH` may be left out. Write it anyway: it documents the rule, and it gives clearer error messages when the body does not match.

---

## Breaking Down Complex Logic with WHERE

### Local Helper Calculations

Legal formulas often involve intermediate calculations. Use **WHERE** to break them down:

```l4
GIVEN `the principal` IS A NUMBER
      `the annual rate` IS A NUMBER
      `the years` IS A NUMBER
GIVETH A NUMBER
`the compound interest` MEANS
    `the principal` * EXPONENT `the growth factor` `the years`
    WHERE
        `the growth factor` MEANS 1 + `the annual rate`
```

(`EXPONENT base power` is L4's built-in exponentiation function.)

**Benefits:**

- Makes complex formulas readable
- Gives meaningful names to intermediate values
- Matches how legal documents explain calculations

### Multiple WHERE Definitions

```l4
GIVEN `the loan amount` IS A NUMBER
      `the annual rate` IS A NUMBER
      `the term in months` IS A NUMBER
GIVETH A NUMBER
`the monthly payment` MEANS
    `the loan amount` *
    (`the monthly rate` * `the compound factor`) /
    (`the compound factor` - 1)
    WHERE
        `the monthly rate` MEANS `the annual rate` / 12
        `the compound factor` MEANS EXPONENT (1 + `the monthly rate`) `the term in months`
```

---

## Realistic Legal Scenarios

### Example 1: Benefit Eligibility

From [module-4-examples.l4](module-4-examples.l4):

```l4
DECLARE Person HAS
    name IS A STRING
    age IS A NUMBER
    citizenship IS A STRING
    `annual income` IS A NUMBER
    `criminal record` IS A BOOLEAN

GIVEN `the applicant` IS A Person
GIVETH A BOOLEAN
DECIDE `the applicant is eligible for benefit` IF
    `the applicant is a qualifying resident`
    AND `the applicant is of age`
    AND `the applicant meets income threshold`
    AND NOT `the applicant is disqualified`
    WHERE
        `the applicant is a qualifying resident` MEANS
            `the applicant`'s citizenship = "citizen"

        `the applicant is of age` MEANS
            `the applicant`'s age >= 21
            AND `the applicant`'s age < 65

        `the applicant meets income threshold` MEANS
            `the applicant`'s `annual income` < 30000

        `the applicant is disqualified` MEANS
            `the applicant`'s `criminal record`
```

Each condition has a name, and `WHERE` spells out what each one means, much as legislation defines its terms.

### Example 2: Progressive Tax Calculation

`` `the income tax owed` `` in [module-4-examples.l4](module-4-examples.l4) taxes each income bracket at its own rate. Each bracket's amount and its tax are named helpers under one `WHERE`, so the formula at the top reads `` `tax on first bracket` + `tax on second bracket` + `tax on third bracket` ``, just as a statute's schedule would.

### Optional Values with MAYBE

Legal data is often incomplete: a contract may or may not have a termination date; notice may or may not have been given. L4 models "a value that might be absent" with the **MAYBE** type:

- `MAYBE DATE` means "a date, or nothing"
- `NOTHING` is the value when it's absent
- `JUST value` wraps a value when it's present

You inspect a MAYBE with `CONSIDER`, handling both cases:

```l4
CONSIDER `the contract`'s `the termination date`
WHEN NOTHING THEN TRUE                 -- no termination date: contract is open-ended
WHEN JUST `the end date` THEN ...      -- there is one: use `the end date`
```

The type system forces you to say what happens in **both** cases—no "null pointer" surprises, and no silently ignored edge case.

### Working with Dates

L4 has a built-in `DATE` type. With `IMPORT daydate`, you can construct dates as `Date day month year` (for example, `Date 15 4 2024`) and compare them directly with `<`, `>=`, and so on.

To count the days between two dates, convert them to serial day numbers with `DATE_SERIAL`:

```l4
GIVEN `the first date` IS A DATE
      `the second date` IS A DATE
GIVETH A NUMBER
`the days between` MEANS
    DATE_SERIAL `the second date` - DATE_SERIAL `the first date`
```

### Example 3: Contract Clause Interpretation

Putting MAYBE and dates together (from [module-4-examples.l4](module-4-examples.l4)):

```l4
DECLARE Contract HAS
    `the effective date` IS A DATE
    `the termination date` IS A MAYBE DATE
    `the notice period in days` IS A NUMBER

DECLARE `Contract Party` HAS
    `the party's name` IS A STRING
    `notice was given on` IS A MAYBE DATE

GIVEN `the contract` IS A Contract
      `the party` IS A `Contract Party`
      `today` IS A DATE
GIVETH A BOOLEAN
DECIDE `the party may terminate` IF
    `the contract is active`
    AND `the party has given sufficient notice`
    WHERE
        `the contract is active` MEANS
            `today` >= `the contract`'s `the effective date`
            AND CONSIDER `the contract`'s `the termination date`
                WHEN NOTHING THEN TRUE
                WHEN JUST `the end date` THEN `today` < `the end date`

        `the party has given sufficient notice` MEANS
            CONSIDER `the party`'s `notice was given on`
            WHEN NOTHING THEN FALSE
            WHEN JUST `the notice date` THEN
                `the days between` `the notice date` `today` >= `the contract`'s `the notice period in days`
```

Try it with the test data from the examples file:

```l4
`the open-ended contract` MEANS Contract (Date 1 1 2024) NOTHING 30
`the party with notice` MEANS `Contract Party` "Acme Ltd" (JUST (Date 1 3 2024))

#EVAL `the party may terminate` `the open-ended contract` `the party with notice` (Date 15 4 2024)
-- Result: TRUE
```

---

## Exercises

### Exercise 1: Simple Eligibility

Write a decision that determines if a person qualifies for a senior discount (age 65 or older):

```l4
GIVEN `the person's age` IS A NUMBER
GIVETH A BOOLEAN
DECIDE `qualifies for senior discount` IF
    -- Your code here
```

<details>
<summary>Solution</summary>

```l4
GIVEN `the person's age` IS A NUMBER
GIVETH A BOOLEAN
DECIDE `qualifies for senior discount` IF
    `the person's age` >= 65

#EVAL `qualifies for senior discount` 70
#EVAL `qualifies for senior discount` 50
```

</details>

### Exercise 2: Multi-Condition Eligibility

A person qualifies for a student loan if they:

- Are between 18 and 35 years old
- Are enrolled in an accredited institution
- Have no prior loan defaults

Write the decision logic.

<details>
<summary>Solution</summary>

```l4
GIVEN `the applicant's age` IS A NUMBER
      `the applicant is enrolled in an accredited institution` IS A BOOLEAN
      `the applicant has prior loan defaults` IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `the applicant qualifies for a student loan` IF
    `the applicant is of eligible age`
    AND `the applicant is enrolled in an accredited institution`
    AND NOT `the applicant has prior loan defaults`
    WHERE
        `the applicant is of eligible age` MEANS
            `the applicant's age` >= 18
            AND `the applicant's age` <= 35

#EVAL `the applicant qualifies for a student loan` 25 TRUE FALSE
#EVAL `the applicant qualifies for a student loan` 40 TRUE FALSE
#EVAL `the applicant qualifies for a student loan` 25 TRUE TRUE
```

</details>

### Exercise 3: Calculation with WHERE

Write a computation for net income that:

- Starts with gross income
- Subtracts standard deduction (calculated as 10% of gross, minimum $1000)
- Subtracts itemized deductions

Use WHERE to break down the calculation clearly.

<details>
<summary>Solution</summary>

```l4
GIVEN `the gross income` IS A NUMBER
      `the itemized deductions` IS A NUMBER
GIVETH A NUMBER
`the net income` MEANS
    `the gross income` - `the standard deduction` - `the itemized deductions`
    WHERE
        `the standard deduction` MEANS
            IF `the calculated deduction` >= 1000
            THEN `the calculated deduction`
            ELSE 1000

        `the calculated deduction` MEANS
            `the gross income` * 0.10

#EVAL `the net income` 100000 5000
#EVAL `the net income` 8000 500
```

</details>

---

## Common Mistakes

### Using Programmer Names

```l4
-- Wrong: Programmer style
GIVEN p IS A Person
GIVETH A BOOLEAN
isEligible p MEANS p.age >= 18 && !p.disqualified

-- Right: Natural language
GIVEN `the person` IS A Person
GIVETH A BOOLEAN
DECIDE `the person is eligible` IF
    `the person`'s age >= 18
    AND NOT `the person`'s disqualified
```

---

## Summary

| Concept              | Use for                           | Syntax                                    |
| -------------------- | --------------------------------- | ----------------------------------------- |
| DECIDE IF            | Yes/no questions, eligibility     | `DECIDE name IF condition`                |
| DECIDE IS            | Classification, value assignment  | `DECIDE name IS expression`               |
| MEANS                | Definitions, computations         | `name MEANS expression`                   |
| BRANCH               | Multi-way classification          | `BRANCH IF cond1 THEN val1 ... OTHERWISE` |
| WHERE                | Breaking down complex logic       | `expression WHERE helpers`                |
| GIVEN ... GIVETH ... | Signature: inputs and result type | `GIVEN inputs GIVETH OutputType name...`  |

---

Next, [Module 5: Functions](module-5-functions.md) goes deeper into the machinery behind decision logic: recursion, and higher-order functions such as `map` and `filter` that apply a decision across a whole list of cases.
