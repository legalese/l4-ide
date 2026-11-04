# Deadlines and consequences

A regulative rule says who must, may or must not act (see [PARTY, MUST, MAY, SHANT](PARTY.md)). This page covers the rest of the rule: the deadline (`WITHIN`), what follows (`HENCE`, `LEST`), how the action is matched (`PROVIDED`, `EXACTLY`), the end states (`FULFILLED`, `BREACH`), and rules that run side by side (`RAND`, `ROR`).

```text
PARTY party
MUST action PROVIDED condition
WITHIN deadline
HENCE rule-if-complied
LEST rule-if-not
```

**Example file:** [deontic-example.l4](deontic-example.l4)

## WITHIN

`WITHIN` gives the time the party has to act, as a NUMBER on the same timeline as the events in a `#TRACE`.
The timeline has no fixed unit: days, hours or business days all work, as long as the deadlines and the event times use the same one.

```l4
DECLARE Party IS ONE OF Buyer, Seller
DECLARE Action IS ONE OF `confirm order`, deliver

GIVETH A DEONTIC Party Action
`order and delivery` MEANS
  PARTY Buyer
  MUST `confirm order`
  WITHIN 30
  HENCE
    PARTY Seller
    MUST deliver
    WITHIN 5
    HENCE FULFILLED
    LEST BREACH BY Seller BECAUSE "late delivery"

#TRACE `order and delivery` AT 0 WITH
  PARTY Buyer DOES `confirm order` AT 10
  PARTY Seller DOES deliver AT 14
```

- A deadline counts from the moment its rule becomes active: from the start time for the first rule, from the event that completed the rule before it for a rule after `HENCE`, and from the moment the rule before it failed for a rule after `LEST`. Above, the buyer confirms at 10, so the seller must deliver by 15.
- A rule that failed by missing its deadline failed at that deadline, not at the later event that brought it to light. So with `MUST pay 1000 WITHIN 30 LEST (MUST pay 1100 WITHIN 14)`, the 14 days run from day 30 and close on day 44, whether the miss came to light on day 31 or day 5000. The same holds for a `MAY` whose deadline passed, and for the `HENCE` of a prohibition kept to the end of its window. A prohibition that was broken failed at the act that broke it, so its `LEST` counts from that act.
- Deadlines are relative. There is no absolute date such as "by 1 January 2026", and no `WITHIN 5 days OF event`: to count from an event, put the rule after the `HENCE` of the rule for that event, as above.
- As events are read, the time left shrinks: after an event at 12, what was `WITHIN 14` from 0 has 2 left.
- A rule without `WITHIN` has no deadline. It waits for its action however long it takes, and time alone never takes it to `LEST`.
- L4 finds that a deadline has passed when it reads an event, or a `WAITUNTIL` (see [EVENT](EVENT.md)), with a later time.
  An event exactly at the deadline is in time.
- The event that shows a deadline has passed is not used up by the rule that missed it. It is offered to the rule that follows, so a late payment that is the first thing recorded can still discharge the `LEST` reparation it was written for, if it falls inside that reparation's own window.
- When one event is past several windows in a chain, a first chance, a second, a third, it is offered to each in turn until it reaches the first whose window is still open, and that is the rule it performs or fails.
- A rule that names itself under `LEST` with a window that is never open, `WITHIN 0` or a negative `WITHIN`, cannot end this way: L4 stops with an error naming the chain after 1,000 hand-offs in a row.
- A rule whose `WITHIN` computes below zero was past its deadline when it became active. It fails at that moment, not before it existed, and the rule that follows counts from there.

## HENCE and LEST

`HENCE` names what follows when the rule is complied with, and `LEST` what follows when it is not.
Each can be `FULFILLED`, `BREACH`, or another rule, so rules chain into a contract.
A `LEST` that is another rule expresses a remedy, such as a penalty or a grace period:

```l4
DECLARE Party IS ONE OF Borrower
DECLARE Action IS ONE OF pay HAS amount IS A NUMBER

GIVETH A DEONTIC Party Action
`payment with penalty` MEANS
  PARTY Borrower
  MUST pay 1000
  WITHIN 30
  HENCE FULFILLED
  LEST
    PARTY Borrower
    MUST pay 1100
    WITHIN 15
    LEST BREACH
```

Which branch is taken, and what is used when it is left out, depends on the modal:

| Modal              | `HENCE` is taken when                  | `LEST` is taken when           | `HENCE` default | `LEST` default |
| ------------------ | -------------------------------------- | ------------------------------ | --------------- | -------------- |
| `MUST`             | the action is taken in time            | the deadline passes without it | `FULFILLED`     | `BREACH`       |
| `MAY`              | the action is taken in time            | the deadline passes without it | `FULFILLED`     | `FULFILLED`    |
| `SHANT / MUST NOT` | the deadline passes without the action | the action is taken            | `FULFILLED`     | `BREACH`       |
| `DO`               | the action is taken in time            | the deadline passes without it | `FULFILLED`     | `BREACH`       |

For a prohibition the polarity flips: the deadline passing quietly is the good outcome. `HENCE` always names the outcome the rule wants, and `LEST` the one it does not.

Not using a permission is not a breach unless you make it one: a `LEST BREACH` after a `MAY` breaches when the permission goes unused.

A rule written on the same line as its `HENCE` needs parentheses when a `LEST` follows on the next line: `HENCE (PARTY Seller MUST deliver WITHIN 5)`. Without them, that `LEST` is an indentation error. A rule on lines of its own, as above, needs none.

## FULFILLED and BREACH

`FULFILLED` and `BREACH` are the two end states. `FULFILLED` means nothing more is owed; `BREACH` means a party failed and nothing absorbed the failure.

```text
LEST BREACH
LEST BREACH BY party
LEST BREACH BECAUSE reason
LEST BREACH BY party BECAUSE reason
```

`BY` names the party in breach and [BECAUSE](BECAUSE.md) gives the reason, a STRING.
`FULFILLED` is also the natural result for a case where no duty arises: ``IF NOT `conditions are met` THEN FULFILLED ELSE PARTY …``.

## PROVIDED

`PROVIDED` adds a condition to the action. An event first has to match the action; then the condition is evaluated, with the names the action bound. If it is FALSE, the event does not count and the next one is tried.

```l4
DECLARE Party IS ONE OF Buyer
DECLARE Action IS ONE OF `pay invoice` HAS amount IS A NUMBER

GIVETH A DEONTIC Party Action
`minimum payment` MEANS
  PARTY Buyer
  MUST `pay invoice` amount PROVIDED amount >= 100
  WITHIN 30

#TRACE `minimum payment` AT 0 WITH
  PARTY Buyer DOES `pay invoice` 50 AT 5
  PARTY Buyer DOES `pay invoice` 150 AT 6
```

The payment of 50 does not count; the payment of 150 fulfils the rule. Without `PROVIDED`, the condition is TRUE.

## EXACTLY

The action after the modal is a pattern, as in a [CONSIDER](../control-flow/CONSIDER.md):

- a value, such as `pay 1000` or `deliver "goods"`, matches only that value;
- a name, such as `pay amount`, matches anything and binds the name for `PROVIDED` and for the rules after `HENCE` and `LEST`. This holds even when a name with that spelling is already defined: with `GIVEN price IS A NUMBER`, `MUST pay price` matches a payment of any amount.

`EXACTLY` turns an expression into a value to match. Use it to compare with an input or another defined value:

```l4
DECLARE Party IS ONE OF Buyer
DECLARE Action IS ONE OF payment HAS amount IS A NUMBER

GIVEN price IS A NUMBER
GIVETH A DEONTIC Party Action
`pay the price` price MEANS
  PARTY Buyer
  MUST payment (EXACTLY price)
  WITHIN 10
```

`EXACTLY` can also come before the whole action: `MUST EXACTLY payment price`.

When the action has several arguments, `EXACTLY` on one of them comes with two limits:

- Put it in parentheses. `EXACTLY` takes everything to its right, so `MUST transfer EXACTLY 100 recipient` reads as one expression and does not type-check; write `MUST transfer (EXACTLY 100) recipient`. An action with one argument needs no parentheses: `MUST pay EXACTLY 100`.
- Put it before any name the action binds. `MUST transfer amount (EXACTLY Bob)` stops with an internal error when the rule is evaluated, saying `Bob` is not in scope; `MUST transfer (EXACTLY 100) recipient`, which checks the amount and binds the recipient, works.

## RAND and ROR

`RAND` and `ROR` combine two rules that run at the same time, on the same events.

- `A RAND B` is fulfilled when both are fulfilled, and breached as soon as either is breached.
- `A ROR B` is fulfilled as soon as either is fulfilled, and breached only when both are breached.

When both sides are breached the result is one breach, dated at the event that revealed it.
If separate events revealed the two, `RAND` reports the earlier and `ROR` the later.
If one event revealed both, which is the usual case, they tie, and `RAND` reports its left side and `ROR` its right side, whichever deadline came first.
A `LEST BREACH` records no time, so a pair with one in it ties in the same way.

```l4
DECLARE Party IS ONE OF Seller
DECLARE Action IS ONE OF ship, `arrange pickup`

GIVETH A DEONTIC Party Action
`either way of delivering` MEANS
     (PARTY Seller MUST ship WITHIN 14 HENCE FULFILLED LEST BREACH)
  ROR
     (PARTY Seller MUST `arrange pickup` WITHIN 7 HENCE FULFILLED LEST BREACH)
```

`RAND` binds more tightly than `ROR`: `A ROR B RAND C` means `A ROR (B RAND C)`.
A combination can follow `HENCE` or `LEST`, so one event can start several duties.

## Related pages

- [Regulative rules](README.md): the parts of a rule and `#TRACE`
- [DEONTIC](DEONTIC.md): the type of rules, and how they are evaluated
- [How obligations unfold](../../concepts/legal-modeling/regulative-rules.md): the model behind deadlines and events
