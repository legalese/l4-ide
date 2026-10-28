# Common patterns

Recipes for structures that come up again and again in legal rules. Each block runs as written; copy it into a file and adapt it. For what each keyword means exactly, follow the links to the [reference](../../reference/README.md).

---

## Records and choices

A record groups facts about one thing; a list of choices names the cases something can be in. A choice can carry its own data.

```l4
DECLARE Address
    HAS `street` IS A STRING
        `city`   IS A STRING

DECLARE Person
    HAS `name`    IS A STRING
        `age`     IS A NUMBER
        `address` IS AN Address

DECLARE Status IS ONE OF
    Active
    Suspended
    Terminated

DECLARE `Payment Status` IS ONE OF
    Pending
    Paid     HAS `amount` IS A NUMBER
    Rejected HAS `reason` IS A STRING

DECLARE `Legal Entity` IS ONE OF
    Individual  HAS `person`       IS A Person
    Corporation HAS `company name` IS A STRING
```

To act on each case, use `CONSIDER`. A case that carries data binds it to a name:

```l4
DECLARE `Payment Status` IS ONE OF
    Pending
    Paid     HAS `amount` IS A NUMBER
    Rejected HAS `reason` IS A STRING

GIVEN payment IS A `Payment Status`
GIVETH A STRING
`payment description` MEANS
    CONSIDER payment
    WHEN Pending    THEN "Awaiting payment"
    WHEN Paid a     THEN CONCAT "Paid ", TOSTRING a
    WHEN Rejected r THEN CONCAT "Rejected: ", r

#EVAL `payment description` (Rejected "card declined")
```

See [DECLARE](../../reference/types/DECLARE.md) and [CONSIDER](../../reference/control-flow/CONSIDER.md).

---

## Decisions

### Requirements as a checklist

When a rule has several requirements, give each one a name in a `WHERE` block. The main condition then reads like the list in the source text, and each requirement can be traced and tested on its own.

```l4
DECLARE Applicant
    HAS `age`             IS A NUMBER
        `citizenship`     IS A STRING
        `annual income`   IS A NUMBER
        `is disqualified` IS A BOOLEAN

GIVEN `the applicant` IS AN Applicant
GIVETH A BOOLEAN
DECIDE `the applicant is eligible` IF
        `the age requirement is met`
    AND `the citizenship requirement is met`
    AND `the income requirement is met`
    AND NOT `the applicant`'s `is disqualified`
    WHERE
        `the age requirement is met` MEANS
                `the applicant`'s `age` AT LEAST 18
            AND `the applicant`'s `age` LESS THAN 65

        `the citizenship requirement is met` MEANS
                `the applicant`'s `citizenship` EQUALS "citizen"
            OR  `the applicant`'s `citizenship` EQUALS "permanent resident"

        `the income requirement is met` MEANS
            `the applicant`'s `annual income` LESS THAN 40000
```

### Exceptions with UNLESS

When the source says "unless" or "except where", use `UNLESS`. `p UNLESS q` means `p AND NOT q`, and `UNLESS` applies to everything before it.

```l4
GIVEN `meets the age requirement` IS A BOOLEAN
      `has valid ID`              IS A BOOLEAN
      `is disqualified`           IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `is eligible` IF
            `meets the age requirement`
        AND `has valid ID`
    UNLESS  `is disqualified`
```

See [UNLESS](../../reference/operators/UNLESS.md).

### One answer from several cases

For a value that depends on ranges or cases, `BRANCH` reads better than nested `IF ... ELSE IF`. The first condition that holds wins.

```l4
GIVEN score IS A NUMBER
GIVETH A STRING
`grade` MEANS
    BRANCH
        IF score >= 90 THEN "A"
        IF score >= 80 THEN "B"
        IF score >= 70 THEN "C"
        IF score >= 60 THEN "D"
        OTHERWISE "F"

#EVAL `grade` 85
```

See [IF and BRANCH](../../reference/control-flow/IF.md).

---

## Calculations

### Intermediate values

Name the steps of a formula in `WHERE`, so each step shows up in an evaluation trace:

```l4
DECLARE Loan
    HAS `principal`   IS A NUMBER
        `annual rate` IS A NUMBER
        `months`      IS A NUMBER

GIVEN loan IS A Loan
GIVETH A NUMBER
`monthly payment` MEANS
    p TIMES r TIMES factor DIVIDED BY (factor MINUS 1)
    WHERE
        p      MEANS loan's `principal`
        r      MEANS loan's `annual rate` DIVIDED BY 12
        n      MEANS loan's `months`
        factor MEANS EXPONENT (1 PLUS r) n

#EVAL `monthly payment` (Loan WITH `principal` IS 10000, `annual rate` IS 0.06, `months` IS 12)
```

### Progressive bands

For tax, fees or tiered pricing, where each part of a value is charged at its own rate: work out how much falls in each band, then add up. Each band takes only the part of the income inside its own range, so nothing is counted twice.

```l4
GIVEN income IS A NUMBER
GIVETH A NUMBER
`tax owed` MEANS
         `amount in band 1` TIMES 0.10
    PLUS `amount in band 2` TIMES 0.20
    PLUS `amount in band 3` TIMES 0.40
    WHERE
        `band 1 limit` MEANS 20000
        `band 2 limit` MEANS 50000

        `amount in band 1` MEANS
            IF income <= `band 1 limit` THEN income ELSE `band 1 limit`

        `amount in band 2` MEANS
            BRANCH
                IF income <= `band 1 limit` THEN 0
                IF income <= `band 2 limit` THEN income MINUS `band 1 limit`
                OTHERWISE `band 2 limit` MINUS `band 1 limit`

        `amount in band 3` MEANS
            IF income <= `band 2 limit` THEN 0 ELSE income MINUS `band 2 limit`

#EVAL `tax owed` 60000
```

The result is `12000`: 10% of 20,000, plus 20% of 30,000, plus 40% of 10,000. Add a band by adding a limit and an `amount in band` definition.

### Recursion

A definition can use itself, as long as it has a base case:

```l4
GIVEN n IS A NUMBER
GIVETH A NUMBER
factorial n MEANS
    IF n <= 1
    THEN 1
    ELSE n TIMES factorial (n MINUS 1)

#EVAL factorial 5
```

---

## Lists

The list functions (`all`, `any`, `filter`, `map`, `null`, `elem`, `count` and more) come from the prelude, so start with `IMPORT prelude`. `GIVEN x YIELD ...` is an unnamed function, used to say what to check or compute for each item.

```l4
IMPORT prelude

DECLARE Person
    HAS `name` IS A STRING
        `age`  IS A NUMBER

`the people` MEANS LIST
    Person "Alice" 34,
    Person "Bob" 15,
    Person "Carol" 52

GIVEN people IS A LIST OF Person
GIVETH A BOOLEAN
`everyone is an adult` MEANS all (GIVEN p YIELD p's `age` >= 18) people

GIVEN people IS A LIST OF Person
GIVETH A BOOLEAN
`someone is a minor` MEANS any (GIVEN p YIELD p's `age` < 18) people

GIVEN people IS A LIST OF Person
GIVETH A LIST OF Person
`only the adults` MEANS filter (GIVEN p YIELD p's `age` >= 18) people

GIVEN people IS A LIST OF Person
GIVETH A LIST OF STRING
`their names` MEANS map (GIVEN p YIELD p's `name`) people

GIVEN people IS A LIST OF Person
GIVETH A MAYBE Person
`the first person` MEANS
    CONSIDER people
    WHEN EMPTY                THEN NOTHING
    WHEN p FOLLOWED BY others THEN JUST p

#EVAL `their names` (`only the adults` `the people`)
#EVAL null `the people`
#EVAL elem 3 (LIST 1, 2, 3)
```

See [prelude](../../reference/libraries/prelude.md) and [YIELD](../../reference/functions/YIELD.md).

---

## Dates

Date functions come from the `daydate` library. `Date` takes day, month and year; subtracting two dates gives the number of days between them.

```l4
IMPORT daydate

`the start date`  MEANS Date 1 3 2025
`the expiry date` MEANS Date 31 12 2025

GIVEN `the first date`  IS A DATE
      `the second date` IS A DATE
GIVETH A NUMBER
`the number of days from` `the first date` `to` `the second date` MEANS
    `the second date` MINUS `the first date`

GIVEN `the date` IS A DATE
GIVETH A BOOLEAN
`has expired on` `the date` MEANS `the expiry date` `is before` `the date`

#EVAL `the number of days from` `the start date` `to` `the expiry date`
#EVAL `the start date` PLUS 30
#EVAL `has expired on` (Date 2 1 2026)
```

See [daydate](../../reference/libraries/daydate.md). For amounts of money in a currency, see the [currency library](../../reference/libraries/currency.md).

---

## Obligations

The blocks in this section share the declarations in the first one. Run them together.

### Obligation, permission, prohibition

```l4
DECLARE Party IS ONE OF Seller, Buyer, Employee

DECLARE Action IS ONE OF
    `deliver goods`
    `pay invoice`
    `inspect goods`
    `disclose confidential information`
    `ship goods`
    `arrange pickup`
    `provide documentation`
    pay HAS amount IS A NUMBER

GIVETH A DEONTIC Party Action
`delivery obligation` MEANS
    PARTY Seller
    MUST `deliver goods`
    WITHIN 14
    HENCE FULFILLED
    LEST BREACH BY Seller BECAUSE "the goods were not delivered within 14 days"

GIVETH A DEONTIC Party Action
`inspection right` MEANS
    PARTY Buyer
    MAY `inspect goods`
    WITHIN 7

GIVETH A DEONTIC Party Action
`confidentiality clause` MEANS
    PARTY Employee
    SHANT `disclose confidential information`
    WITHIN 365
```

When `HENCE` or `LEST` is left out, a sensible default applies: for `MUST`, `HENCE FULFILLED` and `LEST BREACH`. A permission that is not used, or a prohibition respected until the deadline, ends as fulfilled.

### One obligation after another

`HENCE` can lead to the next obligation, so fulfilling one starts the next:

```l4
GIVETH A DEONTIC Party Action
`sale contract` MEANS
    PARTY Seller
    MUST `deliver goods`
    WITHIN 14
    HENCE
        PARTY Buyer
        MUST `pay invoice`
        WITHIN 30
        HENCE FULFILLED
        LEST BREACH BY Buyer
    LEST BREACH BY Seller

#TRACE `sale contract` AT 0 WITH
    PARTY Seller DOES `deliver goods` AT 10
    PARTY Buyer DOES `pay invoice` AT 25
```

### A condition on the action

`PROVIDED` adds a condition the action must meet. Here only a payment of at least the price counts:

```l4
GIVEN `the price` IS A NUMBER
GIVETH A DEONTIC Party Action
`payment of at least the price` MEANS
    PARTY Buyer
    MUST pay amount PROVIDED amount >= `the price`
    WITHIN 30
    HENCE FULFILLED
    LEST BREACH BY Buyer

#TRACE `payment of at least the price` 100 AT 0 WITH
    PARTY Buyer DOES pay 80 AT 5
    PARTY Buyer DOES pay 120 AT 10
```

The payment of 80 does not count; the payment of 120 fulfils the obligation.

### Obligations in parallel, and alternatives

`RAND` requires all of its obligations; `ROR` is satisfied by any one of them:

```l4
GIVETH A DEONTIC Party Action
`delivery with documents` MEANS
        (PARTY Seller MUST `deliver goods` WITHIN 14 HENCE FULFILLED LEST BREACH BY Seller)
    RAND
        (PARTY Seller MUST `provide documentation` WITHIN 14 HENCE FULFILLED LEST BREACH BY Seller)

GIVETH A DEONTIC Party Action
`delivery options` MEANS
        (PARTY Seller MUST `ship goods` WITHIN 14 HENCE FULFILLED LEST BREACH BY Seller)
    ROR
        (PARTY Seller MUST `arrange pickup` WITHIN 7 HENCE FULFILLED LEST BREACH BY Seller)
```

See [PARTY, MUST, MAY, SHANT](../../reference/regulative/PARTY.md) and [Deadlines and consequences](../../reference/regulative/consequences.md).

---

## Mirroring a statute

To keep a rule readable side by side with the statute, `...` joins conditions with AND and `..` with OR, without repeating the keyword, and a quoted string inside the condition holds the statute's connecting words without changing the result:

```l4
GIVEN `intentionally`                   IS A BOOLEAN
      `recklessly`                      IS A BOOLEAN
      `damages property`                IS A BOOLEAN
      `the property belongs to another` IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `commits criminal damage` IF
        "a person who without lawful excuse"
    ... `damages property`
    ... "belonging to another,"
    ... `the property belongs to another`
    ... "and does so"
    ...     `intentionally`
        OR  `recklessly`
```

See [asyndetic AND and OR](../../reference/operators/README.md#asyndetic-and-and-or) for the operators, [Reading like the law](../../concepts/language-design/linguistic-syntax.md) for a full worked statute, and [ditto](../../reference/syntax/README.md#ditto) for `^`, which repeats the word above it in aligned conditions.

---

## Tests next to the rules

Test each threshold on both sides:

```l4
GIVEN age IS A NUMBER
GIVETH A BOOLEAN
DECIDE `is an adult` IF age AT LEAST 18

#ASSERT `is an adult` 18
#ASSERT NOT `is an adult` 17
#ASSERT `is an adult` 19
```

[Test your rules](testing-your-rules.md) covers `#ASSERT` and `#TRACE` in full.

---

## Avoid these mistakes

The [error message reference](../../reference/errors/README.md) lists these and more, with the messages they produce.

### Avoid: field access as an unbracketed argument

`` count charity's `governors` `` applies `count` to `charity` alone. Put the field access in parentheses:

```l4
IMPORT prelude

DECLARE Charity HAS `governors` IS A LIST OF STRING

GIVEN charity IS A Charity
GIVETH A BOOLEAN
`has governors` MEANS count (charity's `governors`) > 0
```

See [Field access as an argument](../../reference/errors/README.md#field-access-as-an-argument).

### Avoid: IF without ELSE

Every `IF` needs an `ELSE`, because the expression must have a value in every case: `IF condition THEN "yes" ELSE "no"`. With several cases, use `BRANCH ... OTHERWISE`. See [IF without ELSE](../../reference/errors/README.md#if-without-else).

### Avoid: misaligned fields

All fields of a record line up under the first one:

```l4
DECLARE Person
    HAS `name`  IS A STRING
        `age`   IS A NUMBER
        `email` IS A STRING
```

Indenting `` `age` `` less or more than `` `name` `` is a parse error.

---

## See also

- [Cheat sheet](../../reference/cheat-sheet.md): the syntax on one page.
- [Encode legislation](encoding-legislation.md): a provision from text to tested rule.
- [Make rules read like law](../natural-language-functions/optimising-natural-language-generation.md): infix and mixfix names, and rendered documents.
