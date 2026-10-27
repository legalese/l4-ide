# Regulative Rules Reference

Deep dive on L4's regulative machinery: obligations, permissions, prohibitions, deadlines, consequences, and contract-trace simulation. This is L4's unique strength and the part most likely to trip a general-purpose LLM.

**Canonical reference:** <https://legalese.com/l4/reference/regulative.md>

---

## Contents

- [The five-keyword skeleton](#the-five-keyword-skeleton)
- [Deontic modals: MUST, MAY, SHANT, DO](#deontic-modals-must-may-shant-do)
- [HENCE and LEST — the success and failure paths](#hence-and-lest--the-success-and-failure-paths)
- [BREACH, FULFILLED, and BECAUSE](#breach-fulfilled-and-because)
- [PROVIDED and EXACTLY — action matching](#provided-and-exactly--action-matching)
- [WITHIN — deadlines](#within--deadlines)
- [Composition: RAND and ROR](#composition-rand-and-ror)
- [Recursive obligations](#recursive-obligations)
- [#TRACE — simulating contract execution](#trace--simulating-contract-execution)
- [EVENT as a type, and `@export`](#event-as-a-type-and-export)
- [Complete example](#complete-example)

---

## The five-keyword skeleton

```text
PARTY   actor
MUST    action parameters      -- or MAY / SHANT / MUST NOT / DO
WITHIN  deadline               -- a NUMBER, counted from when the rule starts
HENCE   nextState              -- optional; consequence on success
LEST    penaltyState           -- optional; consequence on failure
```

Only `PARTY` + modal + action are required. `WITHIN`, `HENCE`, and `LEST` all have defaults (see the tables below).

A rule is a value of type `DEONTIC Party Action`. Declare the parties and the actions as enumerations first, and give the rule `GIVETH A DEONTIC Party Action`.

---

## Deontic modals: MUST, MAY, SHANT, DO

| Keyword              | Meaning                                                                    | Reference                                                                  |
| -------------------- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `MUST`               | Obligation (required)                                                      | <https://legalese.com/l4/reference/regulative/PARTY.md#must>               |
| `MAY`                | Permission (allowed)                                                       | <https://legalese.com/l4/reference/regulative/PARTY.md#may>                |
| `SHANT` / `MUST NOT` | Prohibition (forbidden); the two are synonyms                              | <https://legalese.com/l4/reference/regulative/PARTY.md#shant-and-must-not> |
| `DO`                 | Bare action, neither required nor forbidden; without HENCE/LEST it is MUST | <https://legalese.com/l4/reference/regulative/PARTY.md#do>                 |

```text
PARTY Alice MUST pay 100 WITHIN 30         -- obligation
PARTY Bob   MAY  withdraw 50               -- permission
PARTY Alice SHANT smoke WITHIN 30          -- prohibition
PARTY Alice MUST NOT smoke WITHIN 30       -- the same prohibition
```

---

## HENCE and LEST — the success and failure paths

`HENCE` is the consequence on success; `LEST` is the consequence on failure. **What counts as "success" depends on the modal**, and this is the single most non-obvious thing about L4 regulative rules.

| Modal                | HENCE is taken when                                        | LEST is taken when                     | HENCE default | LEST default |
| -------------------- | ---------------------------------------------------------- | -------------------------------------- | ------------- | ------------ |
| `MUST`               | action is taken in time                                    | deadline passes without the action     | `FULFILLED`   | `BREACH`     |
| `MAY`                | action is taken in time, **or** the deadline passes unused | never — a `LEST` after `MAY` is unused | `FULFILLED`   | not used     |
| `SHANT` / `MUST NOT` | deadline passes (prohibition respected)                    | action is taken (prohibition violated) | `FULFILLED`   | `BREACH`     |
| `DO`                 | action is taken in time                                    | deadline passes without the action     | `FULFILLED`   | `BREACH`     |

**`SHANT` flips the polarity**: for a prohibition, doing the action is the failure. This is why `SHANT … HENCE` fires when the deadline passes quietly — that is the good outcome.

**Not using a permission is never a breach.** A `LEST BREACH` written after `MAY` is accepted and silently ignored. If missing the deadline should have a consequence, write the rule with `MUST` or `DO` and a `LEST`.

`LEST` can chain another obligation for a reparation clause:

```l4
DECLARE Party IS ONE OF `The Borrower`, `The Lender`
DECLARE Action IS ONE OF
    pay HAS amount IS A NUMBER

-- Pay-or-pay-more penalty clause
GIVEN `outstanding amount` IS A NUMBER
GIVETH A DEONTIC Party Action
`repayment` `outstanding amount` MEANS
    PARTY  `The Borrower`
    MUST   pay (EXACTLY `outstanding amount`)
    WITHIN 30
    HENCE  FULFILLED
    LEST
        PARTY  `The Borrower`
        MUST   pay (EXACTLY (`outstanding amount` TIMES 105%))
        WITHIN 15
        -- no LEST: missing this deadline is a breach

#TRACE `repayment` 1000 AT 0 WITH
    WAITUNTIL 31
    PARTY `The Borrower` DOES pay 1050 AT 40
-- Result: FULFILLED
```

Without a `LEST` clause on the inner obligation, missing that deadline is a terminal breach. The `EXACTLY` matters: see [PROVIDED and EXACTLY](#provided-and-exactly--action-matching).

A rule written on the same line as its `HENCE` needs parentheses when a `LEST` follows on the next line: `HENCE (PARTY Seller MUST deliver WITHIN 5)`. Without them, the `LEST` is an indentation error. A rule on lines of its own, as above, needs none.

---

## BREACH, FULFILLED, and BECAUSE

Both are **keywords**, not just outcomes from the evaluator.

```text
HENCE FULFILLED
LEST  BREACH
LEST  BREACH BY Seller
LEST  BREACH BECAUSE "delivery deadline exceeded"
LEST  BREACH BY Seller BECAUSE "failed to deliver within 14 days"
```

`BECAUSE` attaches a reason to a breach and is reported in the trace output. Use it — breach reasons are the thing a legal reviewer or downstream system actually wants to read.

Reference: <https://legalese.com/l4/reference/regulative/BECAUSE.md>

---

## PROVIDED and EXACTLY — action matching

The action after the modal is a **pattern**, matched against each event like a `CONSIDER` branch:

- a value, such as `pay 100`, matches only that value;
- a plain name, such as `pay amount`, matches **anything** and binds the name for `PROVIDED` and for the rules under `HENCE` and `LEST`. This holds even when a constant or input with that name already exists: `` MUST pay `outstanding amount` `` is fulfilled by a payment of 1.

### PROVIDED — guard condition

`PROVIDED` adds a boolean guard, evaluated with the names the action bound. If it returns `FALSE`, the event does not count and the next one is tried.

```l4
DECLARE Party IS ONE OF Buyer
DECLARE Action IS ONE OF payment HAS amount IS A NUMBER

GIVETH A DEONTIC Party Action
`minimum payment` MEANS
    PARTY  Buyer
    MUST   payment amount PROVIDED amount AT LEAST 20
    WITHIN 3

#TRACE `minimum payment` AT 0 WITH
    PARTY Buyer DOES payment 10 AT 1
    PARTY Buyer DOES payment 25 AT 2
-- Result: FULFILLED (the payment of 10 does not count)
```

### EXACTLY — match the value of an expression

`EXACTLY` turns an expression into a value to compare with. Use it whenever the action should match an input or a defined value. It can wrap one argument, or come before the whole action:

```l4
DECLARE Party IS ONE OF Lender, Borrower
DECLARE Action IS ONE OF
    payment HAS amount IS A NUMBER
    send HAS amount IS A NUMBER, recipient IS A Party

capital MEANS 1000

GIVEN price IS A NUMBER
GIVETH A DEONTIC Party Action
`pay the price` price MEANS
    PARTY  Borrower
    MUST   payment (EXACTLY price)          -- this argument is compared by value
    WITHIN 10

GIVETH A DEONTIC Party Action
`advance the capital` MEANS
    PARTY  Lender
    MUST   EXACTLY send capital Borrower    -- the whole action is compared by value
    WITHIN 5

#TRACE `pay the price` 100 AT 0 WITH
    PARTY Borrower DOES payment 99 AT 1
    PARTY Borrower DOES payment 100 AT 2
-- Result: FULFILLED (the payment of 99 does not count)
```

Reference: <https://legalese.com/l4/reference/regulative/consequences.md>

---

## WITHIN — deadlines

`WITHIN` takes a NUMBER: how long the party has, on the same timeline as the event times in `#TRACE`. The unit is up to you (days, hours, business days), as long as the deadlines and the event times use the same one.

- A deadline counts from the moment its rule becomes active: from the start time for the first rule, and from the event that led to it for a rule under `HENCE` or `LEST`.
- There are no absolute deadlines and no `WITHIN 5 days OF event` (that is a parse error). To count from an event, put the rule under the `HENCE` of the rule for that event.
- A rule without `WITHIN` waits for its action indefinitely; time alone never takes it to `LEST`.
- L4 notices that a deadline has passed only when it reads a later event, or a `WAITUNTIL`. The rule that follows starts at that event's time, and that event is **not** matched against it.

```l4
DECLARE Party IS ONE OF Buyer, Seller
DECLARE Action IS ONE OF `confirm order`, deliver

GIVETH A DEONTIC Party Action
`order and delivery` MEANS
    PARTY  Buyer
    MUST   `confirm order`
    WITHIN 30
    HENCE
        PARTY  Seller
        MUST   deliver
        WITHIN 5            -- 5 from the confirmation, not from the start
        LEST   BREACH BY Seller BECAUSE "late delivery"

#TRACE `order and delivery` AT 0 WITH
    PARTY Buyer  DOES `confirm order` AT 10
    PARTY Seller DOES deliver AT 14
-- Result: FULFILLED
```

---

## Composition: RAND and ROR

`RAND` and `ROR` compose obligations in parallel.

- **`RAND`** — parallel AND. All components must be fulfilled; if any side breaches, the compound breaches.
- **`ROR`** — parallel OR. Fulfilling any one side fulfills the compound.
- **Precedence:** `RAND` binds tighter than `ROR`, so `A ROR B RAND C` means `A ROR (B RAND C)`.

```l4
DECLARE Party IS ONE OF seller, buyer
DECLARE Action IS ONE OF deliver, pay, ship, `arrange pickup`

-- Both parties must fulfil their halves
GIVETH A DEONTIC Party Action
`exchange` MEANS
     (PARTY seller MUST deliver WITHIN 14 HENCE FULFILLED LEST BREACH)
  RAND
     (PARTY buyer  MUST pay     WITHIN 30 HENCE FULFILLED LEST BREACH)

-- The seller has two ways to satisfy the obligation
GIVETH A DEONTIC Party Action
`either way of delivering` MEANS
     (PARTY seller MUST ship             WITHIN 14 HENCE FULFILLED LEST BREACH)
  ROR
     (PARTY seller MUST `arrange pickup` WITHIN 7  HENCE FULFILLED LEST BREACH)
```

`AND` and `OR` do not combine rules: between two `DEONTIC` values they are a type error. Use `RAND` and `ROR`.

---

## Recursive obligations

For recurring payments (loans, subscriptions, installments), define a function that emits the next period's obligation:

```l4
DECLARE Party IS ONE OF `The Borrower`
DECLARE Action IS ONE OF pay HAS amount IS A NUMBER

`monthly installment` MEANS 100
`late penalty` MEANS 10

GIVEN remainingBalance IS A NUMBER
GIVETH A DEONTIC Party Action
`monthly payments` remainingBalance MEANS
    IF remainingBalance GREATER THAN 0
    THEN PARTY `The Borrower`
         MUST pay (EXACTLY `monthly installment`)
         WITHIN 30
         HENCE `monthly payments` (remainingBalance MINUS `monthly installment`)
         LEST  `monthly payments` (remainingBalance PLUS `late penalty`)
    ELSE FULFILLED

#TRACE `monthly payments` 200 AT 0 WITH
    PARTY `The Borrower` DOES pay 100 AT 20
    PARTY `The Borrower` DOES pay 100 AT 45
-- Result: FULFILLED
```

The `HENCE` branch reduces the balance; the `LEST` branch increases it with a penalty and re-emits the obligation. The recursion base is `FULFILLED`. Without `EXACTLY`, `` pay `monthly installment` `` would bind a new name that shadows the constant, and the `HENCE` line would no longer type-check.

---

## #TRACE — simulating contract execution

`#TRACE` runs a contract against a sequence of timestamped events and reports either `FULFILLED`, a `BREACH`, or a **residual obligation** (what's still owed).

### Syntax

```text
#TRACE contractName AT startTime WITH
    PARTY partyName DOES action AT eventTime
    PARTY partyName DOES action AT eventTime
    WAITUNTIL time
```

Timestamps are numbers on a shared timeline. For date-based contracts, count in days: with `IMPORT daydate`, `Day (Date 10 2 2025)` is a day number, so a trace can start `AT Day (Date 1 2 2025)` and give each event `AT Day (…)`, with `WITHIN` in days.

`#EVAL` of a rule only prints the rule. To evaluate it as an expression, use `EVALTRACE rule startTime (LIST (EVENT party action time), …)`, which returns the same result as `#TRACE`.

### Happy-path example

Using `repayment` from [HENCE and LEST](#hence-and-lest--the-success-and-failure-paths):

```text
#TRACE `repayment` 1000 AT 0 WITH
    PARTY `The Borrower` DOES pay 1000 AT 15
-- Result: FULFILLED
```

### Residual-obligation example

With no events, or only events that settle nothing, the trace returns the rule still waiting — not `BREACH`. To let a deadline pass without anyone acting, add a `WAITUNTIL` event:

```text
#TRACE `repayment` 1000 AT 0 WITH
    WAITUNTIL 31
-- Result: the LEST obligation, still waiting: pay 1050 within 15

#TRACE `repayment` 1000 AT 0 WITH
    WAITUNTIL 31
    WAITUNTIL 50
-- Result: BREACH (the second deadline, at 46, passed too)
```

The residual is the most useful output from a trace: it is the contract in its current state, as a machine-readable value, showing exactly what is still owed by whom.

Reference: <https://legalese.com/l4/reference/regulative.md>

---

## EVENT as a type, and `@export`

`EVENT` is a type as well as a value: `GIVEN e IS AN EVENT Person Action` takes an event, with the type of the parties and the type of the actions, as `GIVEN duty IS A DEONTIC Person Action` takes a duty.

A rule marked `@export` cannot take an event, a duty or a function as an input, because a request is JSON and has no form for any of them.
`l4 check` refuses such a rule with `EVENT inputs are not supported for @export`, `DEONTIC inputs are not supported for @export` or `Function type inputs are not supported for @export`, and the error names the input.
Take the plain facts as inputs and build the event or the duty inside the rule; the full pattern is in [SKILL.md](../SKILL.md#inputs-no-request-can-supply-event-and-deontic).

---

## Complete example

From the canonical README — a two-party sale with delivery and payment:

```l4
DECLARE Person IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF
    delivery
    payment HAS amount IS A NUMBER

saleContract MEANS
    PARTY Seller
    MUST delivery
    WITHIN 3
    HENCE (
        PARTY Buyer
        MUST payment 100
        WITHIN 7
    )
    LEST BREACH

#TRACE saleContract AT 0 WITH
    PARTY Seller DOES delivery AT 2
    PARTY Buyer  DOES payment 100 AT 5
-- Result: FULFILLED
```

---

## See also

- <https://legalese.com/l4/reference/regulative.md> — full keyword reference
- <https://legalese.com/l4/reference/regulative/PARTY.md> — PARTY, MUST, MAY, SHANT, MUST NOT, DO
- <https://legalese.com/l4/reference/regulative/consequences.md> — WITHIN, HENCE, LEST, PROVIDED, EXACTLY, RAND, ROR
- <https://legalese.com/l4/reference/regulative/BECAUSE.md>
- <https://legalese.com/l4/reference/regulative/DEONTIC.md>
- <https://legalese.com/l4/reference/regulative/EVENT.md> — events and `WAITUNTIL`
- <https://legalese.com/l4/concepts/legal-modeling/regulative-rules.md> — conceptual overview
- <https://legalese.com/l4/courses/foundation/module-6-regulative.md> — foundation course module
