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
- A rule that names itself after `LEST`, or a prohibition that names itself after `HENCE`, with a window that is never open, `WITHIN 0` or a negative `WITHIN`, never reaches an open window.
  L4 stops it with an error that begins "A chain of HENCE or LEST continuations has stalled" and gives the time of the event, not the name of the rule.
- A rule whose `WITHIN` computes below zero was past its deadline when it became active. It fails at that moment, not before it existed, and the rule that follows counts from there.
  When nothing follows and the rule ends in a breach, the breach says so: after the deadline it missed, it prints `but was only entered at, and so failed at` and the moment the rule became active.

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
LEST BREACH BY LIST party, party BECAUSE reason
```

`BY` names the party in breach and [BECAUSE](BECAUSE.md) gives the reason, a STRING.
`BY` also takes a `LIST` of parties, for a breach several parties carry together; see [BECAUSE](BECAUSE.md#several-parties).
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

When the action has several arguments, put an `EXACTLY` on one of them in parentheses.
`EXACTLY` takes everything to its right, so `MUST transfer EXACTLY 100 recipient` reads as one expression and does not type-check; write `MUST transfer (EXACTLY 100) recipient`.
An action with one argument needs no parentheses: `MUST pay EXACTLY 100`.

## RAND and ROR

`RAND` and `ROR` combine two rules that run at the same time, on the same events.

- `A RAND B` is fulfilled when both are fulfilled, and breached as soon as either is breached. When both sides fail, the compound is breached at the **earlier** of the two failures, because the first failure already loses it, and the breach names both sides' failures, left first.
- `A ROR B` is fulfilled as soon as either is fulfilled, and breached only when both are breached. When both alternatives fail, the compound is breached at the **later** of the failures, when the last alternative missed its chance, and the breach names both alternatives' failures, left first.

In both, the order the operands are written in makes no difference to when, or to which failure decided it; see [When a breach happened](#when-a-breach-happened).
The same party failing on both sides is named twice, once for each thing it failed to do.
The same rule on both sides, written twice as in `x RAND x`, under a second name, or passed in twice, is one thing to do: it is checked once, and when it fails its failure is named once.

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

## When a breach happened

Every failure a breach names carries two instants.

- **When it took effect.** For a missed deadline, the deadline, or, for a rule that was already past its deadline when it became active, the moment it became active (see [WITHIN](#within)). For a broken prohibition, the act that broke it. For a `BREACH` written in a `HENCE` or `LEST`, the moment that rule counts from: the missed deadline under a `LEST`, the act (or a kept prohibition's deadline) under a `HENCE`.
- **When it came to light.** The time of the event that showed it. L4 only learns that a deadline has passed when a later event arrives, so a deadline of 5 that nothing shows until an event at 10 took effect at 5 and came to light at 10.

A combination is breached at the moment its parts' failures took effect, worked out the way the operators read: a `RAND` at the earliest, an `ROR` at the latest, and inside out when they are nested.
With `(P MUST x WITHIN 1 ROR Q MUST y WITHIN 10) RAND R MUST z WITHIN 5` and nobody acting, the `ROR` holds until Q's deadline at 10, so the `RAND` is lost at 5, by R: not at 1, because P's miss lost nothing while Q could still act.
The failures that fix that moment are the **decisive** ones.
The breach report prints the first of them in the usual words, then any others that failed at the same moment, then every failure in the order the rule is written:

```text
DEONTIC BREACHED:
  party
    NEVERMATCHESPARTY
  who did action
    NEVERMATCHESACT
  at
    10
  surpassed the deadline of party
    P
  who had to do obligatory action
    MUST x
  before their deadline, which was at
    5
  and at the same instant
    Q
      who had to do obligatory action
        MUST y
      before their deadline, which was at
        5
  and the breach names, in order
    P
      ...
    Q
      ...
```

That is `(PARTY P MUST x WITHIN 5) RAND (PARTY Q MUST y WITHIN 5)` with one `WAITUNTIL 10`.
Written the other way round, it reports the same moment and the same two decisive failures; only the order of the lists follows the rule, and the first line names Q.
The `at` is when the breach came to light; `NEVERMATCHESPARTY` and `NEVERMATCHESACT` are how a `WAITUNTIL` event prints.
When the decisive failures include a missed deadline, the report leads with one; a `BREACH` written in the rule leads only when every decisive failure is one.

`l4 batch` gives the same answer as data: each object in `failures` has `effective` and `observed`, and the breach has the combination's `effective` and `observed` and `decisive`, the positions in `failures` of the decisive ones.
`anchor` is the position of the one the other fields describe.
The decision service (`jl4-service`) reports `failures` and `anchor` too, but not `effective`, `observed` or `decisive`.

## Related pages

- [Regulative rules](README.md): the parts of a rule and `#TRACE`
- [DEONTIC](DEONTIC.md): the type of rules, and how they are evaluated
- [How obligations unfold](../../concepts/legal-modeling/regulative-rules.md): the model behind deadlines and events
