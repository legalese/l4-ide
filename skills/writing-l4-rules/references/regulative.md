# Regulative Rules Reference

Deep dive on L4's regulative machinery: obligations, permissions, prohibitions, deadlines, consequences, and contract-trace simulation. This is L4's unique strength and the part most likely to trip a general-purpose large language model.

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
  - [What may go in the `WITH` block](#what-may-go-in-the-with-block)
- [Complete example](#complete-example)

---

## The five-keyword skeleton

```l4
PARTY   actor
MUST    action parameters      -- or MAY / SHANT / DO
WITHIN  deadline
HENCE   nextState              -- optional; consequence on success
LEST    penaltyState           -- optional; consequence on failure
```

Only `PARTY` + modal + action are required. `WITHIN`, `HENCE`, and `LEST` all have sensible defaults (see the tables below).

---

## Deontic modals: MUST, MAY, SHANT, DO

| Keyword | Meaning                   | Reference                                               |
| ------- | ------------------------- | ------------------------------------------------------- |
| `MUST`  | Obligation (required)     | <https://legalese.com/l4/reference/regulative/MUST.md>  |
| `MAY`   | Permission (allowed)      | <https://legalese.com/l4/reference/regulative/MAY.md>   |
| `SHANT` | Prohibition (forbidden)   | <https://legalese.com/l4/reference/regulative/SHANT.md> |
| `DO`    | Optionality / possibility |                                                         |

```l4
PARTY Alice MUST pay 100 WITHIN 30                      -- obligation
PARTY Bob   MAY  withdraw funds                         -- permission
PARTY Alice SHANT smoke WITHIN 30                       -- prohibition
```

`SHANT` is fully supported. If anything you have seen says "no MUST NOT in L4" it is out of date.

---

## HENCE and LEST — the success and failure paths

`HENCE` is the consequence on success; `LEST` is the consequence on failure. **What counts as "success" depends on the modal**, and this is the single most non-obvious thing about L4 regulative rules.

| Modal   | HENCE fires when                        | LEST fires when                        | HENCE default | LEST default |
| ------- | --------------------------------------- | -------------------------------------- | ------------- | ------------ |
| `DO`    | action is taken                         | deadline passes                        | _(required)_  | _(required)_ |
| `MUST`  | action is taken                         | deadline passes without action         | `FULFILLED`   | `BREACH`     |
| `MAY`   | action is taken                         | deadline passes (permission unused)    | `FULFILLED`   | `FULFILLED`  |
| `SHANT` | deadline passes (prohibition respected) | action is taken (prohibition violated) | `FULFILLED`   | `BREACH`     |

**`SHANT` flips the polarity**: for a prohibition, doing the action is the failure. This is why `SHANT … HENCE` fires when the deadline passes quietly — that is the good outcome.

`LEST` can chain another obligation for a reparation clause:

```l4
-- Pay-or-pay-more penalty clause
PARTY `The Borrower`
MUST  pay `outstanding amount`
WITHIN `due date`
HENCE FULFILLED
LEST (
    PARTY `The Borrower`
    MUST  pay `outstanding amount with 5% penalty`
    WITHIN `default deadline`
    -- no LEST: missing this deadline is a breach
)
```

Without a `LEST` clause on the inner obligation, missing that deadline is a terminal breach.

---

## BREACH, FULFILLED, and BECAUSE

Both are **keywords**, not just outcomes from the evaluator.

All four spellings parse:

```l4
HENCE FULFILLED
LEST  BREACH
LEST  BREACH BY Seller
LEST  BREACH BECAUSE "delivery deadline exceeded"
LEST  BREACH BY Seller BECAUSE "failed to deliver within 14 days"
```

**Write the last one.** `BECAUSE` attaches a reason to a breach and is reported verbatim in the trace output, under the `BY` line:

```
Result:
  DEONTIC BREACHED:
    BREACH
    BY Seller
    BECAUSE "the goods were not delivered within 3 days"
```

Breach reasons are the thing a legal reviewer or a downstream system actually reads, so every example in this file carries one. `SKILL.md` states the same rule under "Model obligations and deadlines".

Reference: <https://legalese.com/l4/reference/regulative/BECAUSE.md>

---

## PROVIDED and EXACTLY — action matching

### PROVIDED — guard condition

`PROVIDED` adds a boolean guard to an action. After an event matches the action pattern structurally, the guard is evaluated; if it returns `FALSE`, the match is rejected and the system tries the next event.

```l4
-- Conditional payment: only counts if >= 20
PARTY Bob
MUST payment price PROVIDED price AT LEAST 20
WITHIN 3

-- Guard on a transferred amount
PARTY borrower
MUST `Amount Transferred`
     PROVIDED `Amount Transferred` AT LEAST `Payment Due`
```

### EXACTLY — equality match

Without `EXACTLY`, the action is a **pattern** (matched structurally, with variable binding). With `EXACTLY`, the action is an **expression** that is evaluated and compared for equality.

```l4
-- Pattern: matches any pay-shaped event
PARTY buyer MUST pay

-- Expression equality: the event must equal the result of this expression
PARTY lender MUST EXACTLY send capital to borrower

-- Exact value
PARTY Alice MUST pay price EXACTLY 100 WITHIN 30
```

---

## WITHIN — deadlines

`WITHIN` takes a bare number. The unit is a convention of the file, not part of
the language: `WITHIN 30` means thirty of whatever the file's clock counts, so
record the unit once in a comment or in the name of the constant.

```l4
PARTY Alice  MUST pay 100 WITHIN 30          -- days, by this file's convention
```

Neither `WITHIN 5 days` nor ``WITHIN 5 days OF `order confirmation` `` parses
in this release (measured 2026-09-04: the first reads `days` as a function
applied to `5`; the second stops at `OF`). See
[source-patterns/04-dates-and-periods.md](source-patterns/04-dates-and-periods.md#e4-3),
entry 4.3, for the measured forms.

**There is no `BEFORE` for an absolute deadline in this release.** `MUST pay BEFORE 30` does not
read as a deadline at all — the parser takes it as applying the action to two arguments, and the
check fails with `You are giving 2 inputs to pay … but it is not a function, so it takes none`
(probe `g14-before-deadline.l4`, exit 1). Use `WITHIN`.

---

## Composition: RAND and ROR

`RAND` and `ROR` compose obligations in parallel.

- **`RAND`** — parallel AND. All components must be fulfilled; if any side breaches, the compound breaches.
- **`ROR`** — parallel OR. Fulfilling any one side fulfills the compound.
- **Precedence:** `RAND` binds tighter than `ROR`, so `A ROR B RAND C` means `A ROR (B RAND C)`.

```l4
-- Both parties must fulfill their halves
(PARTY seller MUST deliver WITHIN 14 HENCE FULFILLED
  LEST BREACH BY seller BECAUSE "goods not delivered within 14 days")
RAND
(PARTY buyer  MUST pay     WITHIN 30 HENCE FULFILLED
  LEST BREACH BY buyer  BECAUSE "price not paid within 30 days")

-- Seller has two ways to satisfy the obligation
(PARTY seller MUST ship             WITHIN 14 HENCE FULFILLED
  LEST BREACH BY seller BECAUSE "not shipped within 14 days")
ROR
(PARTY seller MUST `arrange pickup` WITHIN 7  HENCE FULFILLED
  LEST BREACH BY seller BECAUSE "no pickup arranged within 7 days")
```

`AND` and `OR` at the top level of a regulative rule are also accepted as composition forms in many programs; the authoritative semantics live at <https://legalese.com/l4/reference/regulative.md>.

---

## Recursive obligations

For recurring payments (loans, subscriptions, installments), define a function that emits the next period's obligation:

```l4
GIVEN remainingBalance IS A NUMBER
`monthly payments` remainingBalance MEANS
    IF remainingBalance GREATER THAN 0
    THEN PARTY `The Borrower`
         MUST pay `monthly installment`
         WITHIN `next due date`
         HENCE `monthly payments` (remainingBalance MINUS `monthly installment`)
         LEST  `monthly payments` (remainingBalance PLUS `late penalty`)
    ELSE FULFILLED
```

The `HENCE` branch reduces the balance; the `LEST` branch increases it with a penalty and re-emits the obligation. The recursion base is `FULFILLED`.

---

## #TRACE — simulating contract execution

`#TRACE` runs a contract against a sequence of timestamped events and reports either `FULFILLED`, a `BREACH`, or a **residual obligation** (what's still owed).

### Syntax

```l4
#TRACE contractName AT startTime WITH
    PARTY partyName DOES action AT eventTime
    PARTY partyName DOES action AT eventTime
    ...
```

Timestamps are numbers on a shared timeline. For date-based contracts, the canonical docs show a `Day (…)` form; use whatever form your rule uses for `WITHIN`.

### What may go in the `WITH` block

One event per line, in the order they happen. There are exactly **two** kinds and they mix freely
(probe `g11-trace-events.l4`, exit 0, no errors, six traces):

```l4
-- An act: PARTY … DOES … AT n
#TRACE `the payment duty` AT 0 WITH
    PARTY `the Company` DOES `pay the invoice` AT 12

-- A clock advance with no act: `WAIT UNTIL` n
#TRACE `the payment duty` AT 0 WITH
    (`WAIT UNTIL` 31)

-- Both kinds in one block, in authored order — the only way to show a LEST
-- chain expiring on its first rung and then discharging on its second.
#TRACE `the payment duty` AT 0 WITH
    (`WAIT UNTIL` 45)
    PARTY `the Company` DOES `pay the unpaid amount with interest` AT 50
```

- **`` `WAIT UNTIL` `` is built into the compiler, not a library name.** The probe above has no
  `IMPORT` line at all and every trace runs. The parentheses are the house form and what the corpus
  writes; a bare `` `WAIT UNTIL` 31 `` on its own line also parses and gives the same result
  (probes `g11b`, `g11c`).
- **The deadline is inclusive.** An act `AT 30` against `WITHIN 30` is timely; it takes
  ``(`WAIT UNTIL` 31)`` to expire it.
- **A rule that takes arguments is applied before `AT`, and more than one argument is fine.**
  ``#TRACE `cl 6 -- confidentiality` `the Contractor` (`disclose` "the world") AT 0 WITH`` runs and
  produces the breach. Parenthesise a constructed argument.
- **`#TRACE` is the one directive whose body wraps onto following lines.** Everything else is a
  one-line construct, `#ASSERT REFUSED … BECAUSE` excepted.

Entry 5.11 of the phrasebook,
[source-patterns/05-duties-powers-consequences.md](source-patterns/05-duties-powers-consequences.md#e5-11),
works the same ground from the drafting side.

### Happy-path example

```l4
#TRACE paymentObligation AT 0 WITH
    PARTY Alice DOES pay 100 AT 15
-- Result: FULFILLED
```

### Residual-obligation example

```l4
#TRACE paymentObligation AT 0 WITH
    -- no events within deadline
-- Result: the LEST branch — either BREACH, or the reparation obligation
-- if the rule has a LEST clause
```

A `WITH` block with no events is legal and is the way to ask "what is still
standing if nothing happens": the result is the obligation printed back, not a
breach, because with no events the clock does not advance. Dropping the `WITH`
altogether (`#TRACE c AT 0` and nothing after it) is a parse error.

The residual is the most useful output from a trace: it is the contract in its current state, as a machine-readable value, showing exactly what is still owed by whom.

Reference: <https://legalese.com/l4/reference/regulative.md>

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
        LEST BREACH BY Buyer BECAUSE "the price was not paid within 7 days of delivery"
    )
    LEST BREACH BY Seller BECAUSE "the goods were not delivered within 3 days"

#TRACE saleContract AT 0 WITH
    PARTY Seller DOES delivery AT 2
    PARTY Buyer  DOES payment 100 AT 5
-- Result: FULFILLED

#TRACE saleContract AT 0 WITH
    (`WAIT UNTIL` 4)
-- Result: DEONTIC BREACHED: BREACH BY Seller
--         BECAUSE "the goods were not delivered within 3 days"
```

---

## See also

- <https://legalese.com/l4/reference/regulative.md> — full keyword reference
- <https://legalese.com/l4/reference/regulative/MUST.md>
- <https://legalese.com/l4/reference/regulative/MAY.md>
- <https://legalese.com/l4/reference/regulative/SHANT.md>
- <https://legalese.com/l4/reference/regulative/PARTY.md>
- <https://legalese.com/l4/reference/regulative/BECAUSE.md>
- <https://legalese.com/l4/reference/regulative/DEONTIC.md>
- <https://legalese.com/l4/concepts/legal-modeling/regulative-rules.md> — conceptual overview
- <https://legalese.com/l4/courses/foundation/module-5-regulative.md> — foundation course module
