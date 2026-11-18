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

- A deadline counts from the moment its rule becomes active: from the start time for the first rule, and from the event that led to it for a rule after `HENCE` or `LEST`. Above, the buyer confirms at 10, so the seller must deliver by 15.
- Deadlines are relative. There is no absolute date such as "by 1 January 2026", and no `WITHIN 5 days OF event`: to count from an event, put the rule after the `HENCE` of the rule for that event, as above.
- As events are read, the time left shrinks: after an event at 12, what was `WITHIN 14` from 0 has 2 left.
- A rule without `WITHIN` has no deadline. It waits for its action however long it takes, and time alone never takes it to `LEST`.
- L4 finds that a deadline has passed when it reads an event, or a `WAITUNTIL` (see [EVENT](EVENT.md)), with a later time. The rule that follows starts at that event's time, and that event is not matched against it.

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

| Modal              | `HENCE` is taken when                                          | `LEST` is taken when           | `HENCE` default | `LEST` default |
| ------------------ | -------------------------------------------------------------- | ------------------------------ | --------------- | -------------- |
| `MUST`             | the action is taken in time                                    | the deadline passes without it | `FULFILLED`     | `BREACH`       |
| `MAY`              | the action is taken in time, or the deadline passes without it | never                          | `FULFILLED`     | not used       |
| `SHANT / MUST NOT` | the deadline passes without the action                         | the action is taken            | `FULFILLED`     | `BREACH`       |
| `DO`               | the action is taken in time                                    | the deadline passes without it | `FULFILLED`     | `BREACH`       |

For a prohibition the polarity flips: the deadline passing quietly is the good outcome. `HENCE` always names the outcome the rule wants, and `LEST` the one it does not.

### Which rule a HENCE or LEST belongs to

A rule has no closing word, so a rule written under another rule's `HENCE` or `LEST` is still open when the next `HENCE` or `LEST` comes.
The columns of the two rules' clauses decide which rule it belongs to.
A rule's clauses are its `MUST`, `WITHIN`, `HENCE`, `LEST` and the like, and its clause column is the column of the leftmost of them on a line below its `PARTY`.
A rule written on one line has its `PARTY`'s column as its clause column.
**A `HENCE` or `LEST` on a line of its own, written at the column of the outer rule's clauses and not at the nested rule's own, belongs to the outer rule and ends the rule nested inside it.**

```l4
DECLARE Party IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF
  deliver
  pay HAS amount IS A NUMBER

GIVETH A DEONTIC Party Action
`sale with a late fee` MEANS
  PARTY Seller
  MUST deliver
  WITHIN 3
  HENCE
    PARTY Buyer
    MUST pay 100
    WITHIN 7
    LEST
      PARTY Buyer
      MUST pay 120
      WITHIN 14
  LEST BREACH BY Seller
```

The last `LEST` lines up with the Seller's `MUST`, `WITHIN` and `HENCE`, so it is the Seller's: a Seller who does not deliver within 3 days is in breach.
The `LEST` indented under the Buyer's rule lines up with the Buyer's clauses, so it is the Buyer's: a Buyer who has not paid 100 within 7 days owes 120.

The same holds when the inner rule is written on its `HENCE`'s line:

```l4
DECLARE Party IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF
  deliver
  pay HAS amount IS A NUMBER

GIVETH A DEONTIC Party Action
`sale` MEANS
  PARTY Seller
  MUST deliver
  WITHIN 3
  HENCE PARTY Buyer MUST pay 100 WITHIN 7
  LEST BREACH BY Seller
```

The `LEST` on the last line lines up with the Seller's clauses, so it is the Seller's.
On one line, though, a later `LEST` belongs to the rule on that line: in `HENCE PARTY Buyer MUST pay 100 WITHIN 7 LEST BREACH BY Buyer`, the `LEST` is the Buyer's.

A rule's clauses can sit further right than its `PARTY`, and then a rule nested inside can be written further left than them:

```l4
DECLARE Party IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF
  deliver
  pay HAS amount IS A NUMBER

GIVETH A DEONTIC Party Action
`sale with clauses indented` MEANS
  PARTY Seller
      MUST deliver
      WITHIN 3
      HENCE
    PARTY Buyer
    MUST pay 100
    WITHIN 7
    LEST BREACH BY Buyer
      LEST BREACH BY Seller
```

The first `LEST` lines up with the Buyer's clauses, so it is the Buyer's, although it is left of the Seller's.
The second lines up with the Seller's clauses, so it is the Seller's.

The whole rule, for a `HENCE` or `LEST` on a line of its own after a nested rule, taken in this order:

1. At the column of the nested rule's own clauses, it is the nested rule's.
2. Otherwise, at the column of the outer rule's clauses, it is the outer rule's, and the nested rule ends.
3. Otherwise, if it is right of either rule's clauses, it is the nested rule's, even at a column that lines up with nothing.
4. Otherwise, left of both, it is the outer rule's.

With rules nested deeper, this is applied one level at a time, from the innermost rule out.
Rule 1 comes first, so when the nested rule's clauses are at the same column as the outer rule's, a `HENCE` or `LEST` at that column is the nested rule's.
To give it to the outer rule, put the nested rule in brackets.
Brackets end a rule outright, as in `HENCE (PARTY Buyer MUST pay 100 WITHIN 7)`, and a rule inside brackets competes only with the rules inside the same brackets.

**What is refused.** A `HENCE` or `LEST` that belongs to a rule by the steps above, when that rule already has one (a second `LEST`, a second `HENCE`, or a `HENCE` after the `LEST`), is refused with an error that names the rule, rather than given to another rule.
`HENCE` comes before `LEST`.

**What is not placed this way.** Only the clauses of the rule a nested rule is written under count, not those of rules further out.
In a layout where a rule two levels out has its clauses right of the rule one level out, a `HENCE` or `LEST` that lines up with the rule two levels out can stay with the innermost rule, with no error; brackets settle it.
A rule's `WITHIN` comes before its `HENCE`.
One written after a nested rule is read as the nested rule's, whatever its column, and nothing says so.
If the nested rule already has one, it is an error (`unexpected WITHIN`).
When rules are combined with `RAND` or `ROR` under a `HENCE` or `LEST`, put each one in brackets, as in [RAND and ROR](#rand-and-ror).

Earlier versions of L4 gave a `HENCE` or `LEST` written after a nested rule to the innermost rule still open that had that slot free, whatever the keyword's column, as long as the word after it sat further right than that rule's `PARTY` ([smucclaw/l4-ide#1068](https://github.com/smucclaw/l4-ide/issues/1068)).
So a `LEST` written at the outer rule's clauses could become the nested rule's, with no error, and a `HENCE` written there after the outer rule's `LEST` became the nested rule's `HENCE`.
A contract written that way now reads as its layout shows.
Some layouts that earlier versions accepted are now refused, by the paragraph above: a second `LEST` or `HENCE`, or a `HENCE` after a `LEST`, written where the column points at a rule that already has one.
Earlier versions gave such a keyword to another rule, with no error.

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

## RAND and ROR

`RAND` and `ROR` combine two rules that run at the same time, on the same events.

- `A RAND B` is fulfilled when both are fulfilled, and breached as soon as either is breached.
- `A ROR B` is fulfilled as soon as either is fulfilled, and breached only when both are breached.

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
