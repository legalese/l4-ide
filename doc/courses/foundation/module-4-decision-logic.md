# Module 4: Decision Logic

**Prerequisites:** Modules 1–3

In this module, you'll learn how to encode **constitutive rules** - legal rules that determine facts, classifications, and eligibility.

## Learning Objectives

By the end of this module, you will be able to:

- Distinguish between constitutive rules (decision logic) and regulative rules (obligations)
- Express eligibility determinations using DECIDE
- Define computations and definitions using MEANS
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

In L4, we express constitutive rules as **decision logic** using functions.

---

## Why Functional Purity Matters for Legal Rules

L4 follows the **functional programming** principle that **every input needed to make a decision must be explicitly declared**. This is a feature, not a bug.

### Explicit Dependencies

When you write decision logic in L4, the `GIVEN` clause declares **exactly what information is needed**:

```l4
GIVEN `the applicant` IS A Person
      `today` IS A DATE
GIVETH A BOOLEAN
DECIDE `the application is timely` IF ...
```

This signature tells you immediately: "To determine if an application is timely, I need to know **who the applicant is** and **what today's date is**."

### No Hidden Dependencies

In natural language, legal rules often have implicit dependencies:

> "The applicant is eligible if they are a resident."

**Questions immediately arise:**

- What makes someone a resident?
- How long must they have resided?
- Where must they reside?

In L4, you **must** make these dependencies explicit:

```l4
GIVEN `the applicant` IS A Person
      `the jurisdiction` IS A STRING
GIVETH A BOOLEAN
DECIDE `the applicant is eligible` IF
    `the applicant is a resident of the jurisdiction`
    WHERE
        `the applicant is a resident of the jurisdiction` MEANS
            `the applicant`'s `country of residence` EQUALS `the jurisdiction`
            AND `the applicant`'s `years of residence` >= 5
```

Notice how the helper decision `is a resident of` **also** declares its dependencies. You can't hide information - if a decision needs something, you must pass it explicitly.

### "It Depends" - On What, Exactly?

This explicit dependency tracking has a **huge benefit for legal reasoning**:

**When someone says "it depends"** - L4 forces you to specify **what "it" depends ON**.

```l4
-- ❌ Unclear: What does eligibility depend on?
"The person is eligible"

-- ✅ Clear: Eligibility depends on these specific factors
GIVEN `the person` IS A Person
      `the application date` IS A DATE
      `the jurisdiction rules` IS A `Rule Set`
GIVETH A BOOLEAN
DECIDE `the person is eligible` IF ...
```

The function signature **documents the complete set of factors** that affect the decision. This makes legal rules:

- **Auditable**: You can trace exactly what information influenced a decision
- **Testable**: You know exactly what inputs to vary in your test scenarios
- **Maintainable**: When requirements change, you know what dependencies need updating
- **Explainable**: You can show stakeholders exactly what factors matter

### Parameter Threading

If a sub-decision needs information, you must "thread" it through the caller:

```l4
GIVEN `the applicant` IS A Person
      `today` IS A DATE        -- We need this
GIVETH A BOOLEAN
DECIDE `qualifies for benefit` IF
    `is eligible` `the applicant` `today`  -- Pass it through!
    AND ...
    WHERE
        GIVEN person IS A Person
              `the current date` IS A DATE  -- Sub-decision needs it too!
        GIVETH A BOOLEAN
        `is eligible` MEANS ...
```

This might seem verbose, but it's **transparency, not bureaucracy**. Every piece of information that influences the legal outcome is **visible and traceable**.

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

**Key points:**

- Use **DECIDE IF** for yes/no questions
- Use backticks for natural language identifiers
- Conditions follow IF, connected by AND/OR/NOT

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

**Note:** `BRANCH` is clearer than nested `IF/THEN/ELSE` for classification decisions. It avoids indentation problems and reads more like a legal test with multiple conditions. See [Module 3: Control Flow](module-3-control-flow.md#multi-way-decisions-with-branch) for details.

### DECIDE IS vs DECIDE IF

Use whichever reads more naturally:

```l4
-- These are equivalent:
DECIDE `the person is an adult` IF age >= 18
DECIDE `the person is an adult` IS age >= 18

-- Use IF when it reads like a legal condition:
DECIDE `qualifies for exemption` IF
    `is a first-time buyer`
    AND `purchase price` < 500000

-- Use IS with BRANCH for multi-way classification:
DECIDE `the applicable rate` IS
    BRANCH
        IF `customer type` = "premium" THEN 0.05
        IF `customer type` = "standard" THEN 0.10
        OTHERWISE 0.15
```

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

### Simple Tax Calculation

```l4
GIVEN `the taxable income` IS A NUMBER
GIVETH A NUMBER
`the tax owed` MEANS
    `the taxable income` * `the tax rate`
```

### DECIDE vs MEANS

Both define things - use whichever reads better:

| Use DECIDE when...                | Use MEANS when...                 |
| --------------------------------- | --------------------------------- |
| Asking a yes/no question          | Defining a value or computation   |
| Determining classification/status | Stating what something equals     |
| Condition reads naturally with IF | Definition reads naturally with = |

**Examples:**

```l4
-- ✅ Good: DECIDE for questions
DECIDE `the person is eligible` IF age >= 18

-- ✅ Good: MEANS for definitions
`the person's status` MEANS
    IF age >= 18 THEN "adult" ELSE "minor"

-- Both work, but one reads better:
DECIDE `the person is an adult` IF age >= 18           -- More natural
`the person is an adult` MEANS age >= 18                -- Also valid

`the net income` MEANS `gross income` - `expenses`     -- More natural
DECIDE `the net income` IS `gross income` - `expenses` -- Also valid
```

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

**Notice:**

- Natural language identifiers with backticks
- WHERE breaks down the eligibility logic
- Each condition has a clear name
- Logic mirrors how legislation is written

### Example 2: Progressive Tax Calculation

```l4
GIVEN `the income` IS A NUMBER
GIVETH A NUMBER
`the income tax owed` MEANS
    `tax on first bracket` + `tax on second bracket` + `tax on third bracket`
    WHERE
        `tax on first bracket` MEANS
            `amount in first bracket` * 0.10

        `tax on second bracket` MEANS
            `amount in second bracket` * 0.20

        `tax on third bracket` MEANS
            `amount in third bracket` * 0.30

        `amount in first bracket` MEANS
            BRANCH
                IF `the income` <= 10000 THEN `the income`
                OTHERWISE 10000

        `amount in second bracket` MEANS
            BRANCH
                IF `the income` <= 10000 THEN 0
                IF `the income` <= 50000 THEN `the income` - 10000
                OTHERWISE 40000

        `amount in third bracket` MEANS
            BRANCH
                IF `the income` <= 50000 THEN 0
                OTHERWISE `the income` - 50000
```

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

## Function Signatures

Every decision or computation needs a **type signature** that declares:

1. **Inputs** (GIVEN): What information is needed
2. **Output** (GIVETH): What type of result is produced

### Common Patterns

**Boolean decisions** (yes/no questions):

```l4
GIVEN `the person` IS A Person
GIVETH A BOOLEAN
DECIDE `the person is eligible` IF ...
```

**Classification** (categorizing into types):

```l4
GIVEN `the entity` IS AN Entity
GIVETH A STRING
DECIDE `the entity type` IS ...
```

**Computation** (calculating a value):

```l4
GIVEN `the income` IS A NUMBER
GIVETH A NUMBER
`the tax owed` MEANS ...
```

**Multiple inputs**:

```l4
GIVEN `the applicant` IS A Person
      `the application date` IS A DATE
      `today` IS A DATE
GIVETH A BOOLEAN
DECIDE `the application is timely` IF ...
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

### Exercise 3: Tax Bracket Classification

Write a decision that classifies income into tax brackets:

- Income < $10,000: "exempt"
- Income $10,000-$50,000: "standard"
- Income > $50,000: "higher rate"

<details>
<summary>Solution</summary>

```l4
GIVEN `the income` IS A NUMBER
GIVETH A STRING
DECIDE `the tax bracket` IS
    BRANCH
        IF `the income` < 10000 THEN "exempt"
        IF `the income` <= 50000 THEN "standard"
        OTHERWISE "higher rate"

#EVAL `the tax bracket` 5000
#EVAL `the tax bracket` 30000
#EVAL `the tax bracket` 80000
```

</details>

### Exercise 4: Calculation with WHERE

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

### 1. Missing Type Signature

```l4
-- ❌ Wrong: No GIVETH
GIVEN `the person's age` IS A NUMBER
DECIDE `is adult` IF `the person's age` >= 18

-- ✅ Right: Include GIVETH
GIVEN `the person's age` IS A NUMBER
GIVETH A BOOLEAN
DECIDE `is adult` IF `the person's age` >= 18
```

### 2. Using Programmer Names

```l4
-- ❌ Wrong: Programmer style
GIVEN p IS A Person
GIVETH A BOOLEAN
isEligible p MEANS p.age >= 18 && !p.disqualified

-- ✅ Right: Natural language
GIVEN `the person` IS A Person
GIVETH A BOOLEAN
DECIDE `the person is eligible` IF
    `the person`'s age >= 18
    AND NOT `the person`'s disqualified
```

### 3. Complex Logic Without WHERE

```l4
-- ❌ Wrong: Everything inline, hard to read
`the result` MEANS
    (x * 0.1 + y * 0.2) / EXPONENT (1 + r) n

-- ✅ Right: Break down with WHERE
`the result` MEANS
    `the combined amount` / `the discount factor`
    WHERE
        `the combined amount` MEANS x * 0.1 + y * 0.2
        `the discount factor` MEANS EXPONENT (1 + r) n
```

### 4. Wrong DECIDE vs MEANS Choice

```l4
-- ❌ Awkward: MEANS for a yes/no question
`is eligible` MEANS age >= 18 AND income < 50000

-- ✅ Better: DECIDE IF for questions
DECIDE `is eligible` IF
    age >= 18
    AND income < 50000

-- ❌ Awkward: DECIDE for a simple definition
DECIDE `the net amount` IS gross - deductions

-- ✅ Better: MEANS for definitions
`the net amount` MEANS gross - deductions
```

### 5. Nested IF/THEN/ELSE Instead of BRANCH

```l4
-- ❌ Fragile: Nested IF/THEN/ELSE (indentation-sensitive)
`the category` MEANS
    IF score >= 90 THEN "excellent"
    ELSE IF score >= 70 THEN "good"
         ELSE IF score >= 50 THEN "pass"
              ELSE "fail"

-- ✅ Better: BRANCH (clear, flat structure)
`the category` MEANS
    BRANCH
        IF score >= 90 THEN "excellent"
        IF score >= 70 THEN "good"
        IF score >= 50 THEN "pass"
        OTHERWISE "fail"
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
| GIVEN ... GIVETH ... | Type signature (always required!) | `GIVEN inputs GIVETH OutputType name...`  |

**Key principles:**

- Write code that reads like legal text
- Use backticks liberally for natural language
- Use WHERE to make complex logic transparent
- Choose DECIDE vs MEANS based on readability

---

## What's Next?

In [Module 5: Functions](module-5-functions.md), you'll go deeper into the machinery behind decision logic: reusable functions, recursion, and higher-order functions like `map` and `filter` that let you apply decisions across whole lists of cases.

After that, [Module 6: Regulative Rules](module-6-regulative.md) shows how to combine constitutive rules (decision logic) with regulative rules (obligations, permissions, prohibitions) to model complete legal workflows.
