# Module A3: Contracts in Depth

In this module, you'll learn advanced contract modeling including complex payment terms, recursive obligations, and penalty structures. Find the full working example at the bottom.

## Learning Objectives

By the end of this module, you will be able to:

- Model complex payment schedules
- Implement recursive payment obligations
- Create penalty and interest calculations
- Handle multi-party contracts

---

## Contract Modeling Principles

Well-modeled contracts in L4 follow these principles:

1. **Clear parties**: Who has obligations?
2. **Precise actions**: What must be done?
3. **Explicit conditions**: When do obligations apply?
4. **Complete paths**: Every scenario leads to FULFILLED or BREACH
5. **Testable**: Use #TRACE to verify behavior

---

## Case Study: Promissory Note

We'll build a complete promissory note with:

- Principal and interest
- Monthly installments
- Late payment penalties
- Default provisions

### Step 1: Define Types

```l4
-- Money type with currency
DECLARE Money
    HAS `the amount` IS A NUMBER
        `the currency` IS A STRING

-- Currency constructors
GIVEN n IS A NUMBER
GIVETH A Money
USD MEANS Money WITH `the amount` IS n, `the currency` IS "USD"

GIVEN n IS A NUMBER
GIVETH A Money
SGD MEANS Money WITH `the amount` IS n, `the currency` IS "SGD"

-- Party types
DECLARE Party IS ONE OF
    `the borrower party` HAS `the borrower` IS A Borrower
    `the lender party` HAS `the lender` IS A Lender

-- Borrower can be individual or company
DECLARE Borrower IS ONE OF
    `individual borrower` HAS `the person` IS A Person
    `corporate borrower` HAS `the company` IS A Company

DECLARE Lender IS ONE OF
    `individual lender` HAS `the person` IS A Person
    `institutional lender` HAS `the company` IS A Company

-- Payment record
DECLARE Payment
    HAS `the amount` IS A Money
        `the due date` IS A NUMBER  -- Days from commencement

-- Penalty terms
DECLARE `Penalty Terms`
    HAS `the penalty rate` IS A NUMBER
        `the grace period` IS A NUMBER  -- in days
```

### Step 2: Define Loan Terms

```l4
DECLARE `Loan Terms`
    HAS `the principal` IS A Money
        `the annual interest rate` IS A NUMBER
        `the number of installments` IS A NUMBER
        `the days until default` IS A NUMBER
        `the penalty terms` IS A `Penalty Terms`

-- Example loan
`the example loan` MEANS `Loan Terms` WITH
    `the principal`              IS USD 25000
    `the annual interest rate`   IS 0.15             -- 15% annual interest
    `the number of installments` IS 12               -- 12 monthly installments
    `the days until default`     IS 30               -- Default after 30 days late
    `the penalty terms`          IS `Penalty Terms` WITH
                                      `the penalty rate` IS 0.05   -- 5% penalty
                                      `the grace period` IS 10
```

### Step 3: Calculate Payment Schedule

```l4
-- Monthly interest rate
GIVEN terms IS A `Loan Terms`
GIVETH A NUMBER
`monthly rate` MEANS terms's `the annual interest rate` / 12

-- Power function for calculations
GIVEN base IS A NUMBER
      exp IS A NUMBER
GIVETH A NUMBER
`power` MEANS
    IF exp = 0
    THEN 1
    ELSE IF exp = 1
         THEN base
         ELSE base * `power` base (exp - 1)

-- Monthly payment using amortization formula
-- PMT = P × (r(1+r)^n) / ((1+r)^n - 1)
GIVEN terms IS A `Loan Terms`
GIVETH A Money
`monthly payment amount` MEANS
    Money WITH `the amount` IS payment, `the currency` IS terms's `the principal`'s `the currency`
    WHERE
        p MEANS terms's `the principal`'s `the amount`
        r MEANS `monthly rate` terms
        n MEANS terms's `the number of installments`
        `the compound factor` MEANS `power` (1 + r) n
        payment MEANS p * (r * `the compound factor`) / (`the compound factor` - 1)
```

---

## Recursive Payment Obligations

The key insight: **payment obligations are recursive**. After each payment, there's another payment (until paid off).

```l4
-- Actions for the loan contract
DECLARE `Loan Action` IS ONE OF
    `pay installment` HAS `the recipient` IS A Lender
                          `the amount` IS A Money

-- Validate payment amount
GIVEN paid IS A Money
      expected IS A Money
GIVETH A BOOLEAN
`is valid payment` MEANS
    paid's `the currency` EQUALS expected's `the currency`
    AND paid's `the amount` >= (expected's `the amount` - 0.05)  -- Allow small rounding

-- The recursive payment obligation
GIVEN terms IS A `Loan Terms`
      debtor IS A Borrower
      creditor IS A Lender
      outstanding IS A Money  -- Remaining balance
GIVETH A DEONTIC Party `Loan Action`
`payment obligation` MEANS
    IF outstanding's `the amount` > 0
    THEN
        PARTY `the borrower party` debtor
        MUST `pay installment` EXACTLY creditor
                               `the amount paid` PROVIDED `the amount paid`'s `the amount` >= `the payment due`'s `the amount`
        WITHIN `the next due date`
        HENCE
            -- Recursive call with reduced balance
            `payment obligation` terms debtor creditor `the new outstanding balance`
        LEST
            -- Late: apply penalty
            `late payment handling` terms debtor creditor outstanding
    ELSE FULFILLED
    WHERE
        -- Calculate next payment
        `the payment due` MEANS `calculate next payment` terms outstanding
        `the next due date` MEANS `calculate due date` terms outstanding
        -- After payment, reduce outstanding (simplified)
        `the new outstanding balance` MEANS Money WITH
            `the amount`   IS outstanding's `the amount` - `the payment due`'s `the amount`
            `the currency` IS outstanding's `the currency`
```

### Late Payment with Penalty

```l4
GIVEN terms IS A `Loan Terms`
      debtor IS A Borrower
      creditor IS A Lender
      outstanding IS A Money
GIVETH A DEONTIC Party `Loan Action`
`late payment handling` MEANS
    -- Grace period with penalty interest
    PARTY `the borrower party` debtor
    MUST `pay installment` EXACTLY creditor
                           `the amount paid` PROVIDED `the amount paid`'s `the amount` >= `the payment with penalty`'s `the amount`
    WITHIN (`the next due date` + terms's `the penalty terms`'s `the grace period`)
    HENCE
        -- Continue with remaining payments
        `payment obligation` terms debtor creditor `the new outstanding balance`
    LEST
        -- Default: full balance due
        `default handling` terms debtor creditor outstanding
    WHERE
        `the base payment` MEANS `calculate next payment` terms outstanding
        `the penalty amount` MEANS `the base payment`'s `the amount` * terms's `the penalty terms`'s `the penalty rate`
        `the payment with penalty` MEANS Money WITH
            `the amount`   IS `the base payment`'s `the amount` + `the penalty amount`
            `the currency` IS `the base payment`'s `the currency`
        `the next due date` MEANS `calculate due date` terms outstanding
        `the new outstanding balance` MEANS Money WITH
            `the amount`   IS outstanding's `the amount` - `the payment with penalty`'s `the amount`
            `the currency` IS outstanding's `the currency`
```

### Default: Full Balance Due

```l4
GIVEN terms IS A `Loan Terms`
      debtor IS A Borrower
      creditor IS A Lender
      outstanding IS A Money
GIVETH A DEONTIC Party `Loan Action`
`default handling` MEANS
    PARTY `the borrower party` debtor
    MUST `pay installment` EXACTLY creditor
                           EXACTLY outstanding  -- Full balance required
    WITHIN terms's `the days until default`
    HENCE FULFILLED
    LEST BREACH BY (`the borrower party` debtor) BECAUSE "loan default"
```

---

## Testing with #TRACE

### Happy Path: All Payments On Time

```l4
-- Define test parties
`Alice the borrower` MEANS `individual borrower` (Person WITH `the name` IS "Alice")
`Bob the lender` MEANS `individual lender` (Person WITH `the name` IS "Bob")

#TRACE `payment obligation` `the example loan` `Alice the borrower` `Bob the lender` (USD 25000) AT 0 WITH
    PARTY (`the borrower party` `Alice the borrower`) DOES `pay installment` `Bob the lender` (USD 2256.46) AT 30
    PARTY (`the borrower party` `Alice the borrower`) DOES `pay installment` `Bob the lender` (USD 2256.46) AT 60
    PARTY (`the borrower party` `Alice the borrower`) DOES `pay installment` `Bob the lender` (USD 2256.46) AT 90
    -- ... continue for all 12 payments
```

### Late Payment Scenario

```l4
-- First payment on time, second payment late (in grace period)
#TRACE `payment obligation` `the example loan` `Alice the borrower` `Bob the lender` (USD 25000) AT 0 WITH
    PARTY (`the borrower party` `Alice the borrower`) DOES `pay installment` `Bob the lender` (USD 2256.46) AT 30
    -- Second payment late with penalty
    PARTY (`the borrower party` `Alice the borrower`) DOES `pay installment` `Bob the lender` (USD 2369.28) AT 75
```

### Default Scenario

```l4
-- Borrower stops paying
#TRACE `payment obligation` `the example loan` `Alice the borrower` `Bob the lender` (USD 25000) AT 0 WITH
    PARTY (`the borrower party` `Alice the borrower`) DOES `pay installment` `Bob the lender` (USD 2256.46) AT 30
    -- No more payments... contract should reach BREACH
```

---

## Multi-Party Contracts

Some contracts involve more than two parties:

```l4
-- Escrow arrangement: Buyer, Seller, Escrow Agent
DECLARE `Escrow Party` IS ONE OF `the buyer`, `the seller`, `the escrow agent`

DECLARE `Escrow Action` IS ONE OF
    `deposit funds` HAS `the amount` IS A Money
    `deliver goods`
    `release funds to seller`
    `return funds to buyer`

GIVEN amount IS A Money
GIVETH A DEONTIC `Escrow Party` `Escrow Action`
`escrow arrangement` MEANS
    -- Buyer deposits funds
    PARTY `the buyer`
    MUST `deposit funds` amount
    WITHIN 7
    HENCE
        -- Seller delivers goods
        PARTY `the seller`
        MUST `deliver goods`
        WITHIN 14
        HENCE
            -- Escrow releases to seller
            PARTY `the escrow agent`
            MUST `release funds to seller`
            WITHIN 3
            HENCE FULFILLED
            LEST BREACH BY `the escrow agent` BECAUSE "escrow agent failed to release funds"
        LEST
            -- Seller didn't deliver, return funds
            PARTY `the escrow agent`
            MUST `return funds to buyer`
            WITHIN 3
            HENCE BREACH BY `the seller` BECAUSE "seller failed to deliver goods"
            LEST BREACH BY `the escrow agent` BECAUSE "escrow agent failed to return funds"
    LEST BREACH BY `the buyer` BECAUSE "buyer failed to deposit funds"
```

---

## Parallel Obligations with RAND

When multiple obligations must all be fulfilled:

```l4
-- Types for service contract examples
DECLARE `Service Party` IS ONE OF Provider, Client

DECLARE `Contract Action` IS ONE OF
    `deliver service`
    `provide documentation`
    `ship goods`
    `arrange pickup`
    `make payment`

-- Service contract: Provider must deliver service AND provide documentation
GIVETH A DEONTIC `Service Party` `Contract Action`
`service delivery` MEANS
    (PARTY Provider MUST `deliver service` WITHIN 30 HENCE FULFILLED LEST BREACH BY Provider BECAUSE "failed to deliver service")
    RAND
    (PARTY Provider MUST `provide documentation` WITHIN 30 HENCE FULFILLED LEST BREACH BY Provider BECAUSE "failed to provide documentation")
```

Both obligations must be fulfilled for the contract to be fulfilled.

---

## Alternative Obligations with ROR

When fulfilling any one obligation is sufficient:

```l4
-- Delivery options: Ship OR pickup
GIVETH A DEONTIC `Service Party` `Contract Action`
`delivery options` MEANS
    (PARTY Provider MUST `ship goods` WITHIN 14 HENCE FULFILLED LEST BREACH BY Provider BECAUSE "failed to ship")
    ROR
    (PARTY Provider MUST `arrange pickup` WITHIN 7 HENCE FULFILLED LEST BREACH BY Provider BECAUSE "failed to arrange pickup")
```

Either shipping or arranging pickup fulfills the delivery obligation.

---

## Practical Patterns

### Minimum Payment

```l4
-- Credit card style: Pay minimum or full balance
DECLARE `Card Party` IS ONE OF Cardholder, Bank

DECLARE `Card Action` IS ONE OF
    `pay` HAS `the payment amount` IS A NUMBER

GIVEN balance IS A Money
      `the minimum percentage` IS A NUMBER
GIVETH A DEONTIC `Card Party` `Card Action`
`credit payment` MEANS
    PARTY Cardholder
    MUST `pay` `the amount paid` PROVIDED `the amount paid` >= `the minimum payment`
    WITHIN 30
    HENCE
        IF `the amount paid` >= balance's `the amount`
        THEN FULFILLED  -- Paid in full
        ELSE `credit payment` `the new balance` `the minimum percentage`  -- Recurse with new balance
    LEST BREACH BY Cardholder BECAUSE "missed credit card payment"
    WHERE
        `the minimum payment` MEANS balance's `the amount` * `the minimum percentage`
        `the new balance` MEANS Money WITH `the amount` IS balance's `the amount` - `the minimum payment`, `the currency` IS balance's `the currency`
```

### Milestone-Based Payment

```l4
DECLARE Milestone IS ONE OF
    Design
    Development
    Testing
    Delivery

DECLARE `Milestone Action` IS ONE OF
    `complete milestone` HAS `the completed milestone` IS A Milestone
    `pay milestone` HAS `the paid milestone` IS A Milestone

GIVEN milestones IS A LIST OF Milestone
GIVETH A DEONTIC `Service Party` `Milestone Action`
`milestone payments` MEANS
    CONSIDER milestones
    WHEN EMPTY THEN FULFILLED
    WHEN m FOLLOWED BY rest THEN
        PARTY Provider
        MUST `complete milestone` m
        WITHIN 30
        HENCE
            PARTY Client
            MUST `pay milestone` m
            WITHIN 14
            HENCE `milestone payments` rest  -- Recurse
            LEST BREACH BY Client BECAUSE "client failed to pay milestone"
        LEST BREACH BY Provider BECAUSE "provider failed to complete milestone"
```

---

## Exercise: Model a Security Deposit

Encode this clause:

> **Security Deposit Return:** At the end of the lease, the landlord must either
> (a) refund the deposit in full within 14 days, or
> (b) send an itemized list of deductions within 7 days and refund the balance within 21 days.
> Failing both, the landlord is in breach.

Hint: two alternative obligation chains joined with ROR.

<details>
<summary>Solution</summary>

```l4
DECLARE `Tenancy Party` IS ONE OF
    `the landlord`
    `the tenant`

DECLARE `Tenancy Action` IS ONE OF
    `refund the deposit in full`
    `send an itemized list of deductions`
    `refund the balance`

GIVETH A DEONTIC `Tenancy Party` `Tenancy Action`
`deposit return obligation` MEANS
    (PARTY `the landlord`
     MUST `refund the deposit in full`
     WITHIN 14
     HENCE FULFILLED
     LEST BREACH BY `the landlord` BECAUSE "failed to refund the deposit")
    ROR
    (PARTY `the landlord`
     MUST `send an itemized list of deductions`
     WITHIN 7
     HENCE
        PARTY `the landlord`
        MUST `refund the balance`
        WITHIN 21
        HENCE FULFILLED
        LEST BREACH BY `the landlord` BECAUSE "failed to refund the balance"
     LEST BREACH BY `the landlord` BECAUSE "failed to account for deductions")

-- Full refund on time
#TRACE `deposit return obligation` AT 0 WITH
    PARTY `the landlord` DOES `refund the deposit in full` AT 10

-- Itemized deductions then balance refunded
#TRACE `deposit return obligation` AT 0 WITH
    PARTY `the landlord` DOES `send an itemized list of deductions` AT 5
    PARTY `the landlord` DOES `refund the balance` AT 20
```

</details>

---

### Full Example

[module-a3-contracts-examples.l4](module-a3-contracts-examples.l4)

---

## Summary

| Pattern                   | Use Case                            |
| ------------------------- | ----------------------------------- |
| **Recursive obligations** | Installment payments, subscriptions |
| **Penalty structures**    | Late fees, interest                 |
| **Default acceleration**  | Full balance on default             |
| **Multi-party**           | Escrow, three-way agreements        |
| **RAND**                  | Multiple parallel obligations       |
| **ROR**                   | Alternative ways to fulfill         |

Key insight: Complex contracts are **compositions of simpler patterns**, often with recursion for repeated obligations.

---

## What's Next?

In [Module A4: Production Patterns](module-a4-production.md), you'll learn patterns for organizing large codebases, testing strategies, and integration considerations.
