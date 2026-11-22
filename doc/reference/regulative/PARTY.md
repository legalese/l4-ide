# PARTY, MUST, MAY, SHANT

Every regulative rule starts with `PARTY`, the one the rule applies to, followed by a modal that says whether the action is required, allowed or forbidden.

## Syntax

```text
PARTY party MUST action
PARTY party MAY action
PARTY party SHANT action
PARTY party MUST NOT action
PARTY party DO action
```

After `MUST`, `MAY`, `SHANT` and `MUST NOT`, a `DO` may be added: `MUST DO action` means the same as `MUST action`.
The rest of the rule (`PROVIDED`, `AFTER`, `WITHIN`, `BEFORE`, `HENCE`, `LEST`) is described in [Deadlines and consequences](consequences.md) and [AFTER](AFTER.md); for one obligation per member of a group, see [EVERY](EVERY.md).

**Example files:** [party-example.l4](party-example.l4), [must-example.l4](must-example.l4), [may-example.l4](may-example.l4), [shant-example.l4](shant-example.l4)

## PARTY

`PARTY` names who the rule applies to: a value of the rule's party type, usually a value of an enumeration.
Only an event by that party can fulfil or breach the rule; an event by anyone else is skipped.

```l4
DECLARE Party IS ONE OF `The Borrower`, `The Lender`
DECLARE Action IS ONE OF
  `prepay loan`
  `make payment` HAS amount IS A NUMBER

GIVETH A DEONTIC Party Action
`payment obligation` MEANS
  PARTY `The Borrower`
  MUST `make payment` 5000
  WITHIN 30
```

The party and action types are the two parameters of the rule's type, `DEONTIC Party Action`; see [DEONTIC](DEONTIC.md).
The action is a value of the action type, matched as a pattern: `` `make payment` 5000 `` matches only a payment of 5000.
A name in the action that refers to nothing already defined matches any value: `` `make payment` amount `` matches a payment of any amount, and `amount` can be used afterwards in `PROVIDED`, `HENCE` and `LEST`.
A name that refers to something in scope, such as a `GIVEN price`, requires the event to equal it: `` `make payment` price `` matches only a payment of that price.
See [Action patterns](consequences.md#action-patterns-reference-or-wildcard).

## MUST

`MUST` is an obligation: the party is required to take the action before the deadline.

- Taken in time: the rule continues with `HENCE` (by default `FULFILLED`).
- Not taken when the deadline passes: the rule continues with `LEST` (by default `BREACH`).

```l4
DECLARE Party IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF `deliver goods`

GIVETH A DEONTIC Party Action
`delivery` MEANS
  PARTY Seller
  MUST `deliver goods`
  WITHIN 14
  HENCE FULFILLED
  LEST BREACH BY Seller

#TRACE `delivery` AT 0 WITH
  PARTY Seller DOES `deliver goods` AT 10
```

## MAY

`MAY` is a permission: the party is allowed, but not required, to take the action. Typical uses are rights to terminate early, renew, prepay or convert.

- Taken in time: the rule continues with `HENCE` (by default `FULFILLED`).
- Not taken when the deadline passes: the rule continues with `LEST` (by default `FULFILLED`). Not using a permission is not a breach unless you make it one: a `LEST BREACH` after a `MAY` breaches when the permission goes unused.

```l4
DECLARE Party IS ONE OF `The Borrower`
DECLARE Action IS ONE OF `prepay loan` HAS amount IS A NUMBER

GIVETH A DEONTIC Party Action
`prepayment option` MEANS
  PARTY `The Borrower`
  MAY `prepay loan` 100000
  WITHIN 365
```

A `MAY` is often the step after an obligation, under its `HENCE`, or leads to an obligation of another party under its own `HENCE`.
If not using the permission should have a consequence, give the `MAY` a `LEST`, or write the rule with `MUST` instead.

## SHANT and MUST NOT

`SHANT` is a prohibition: the party must not take the action during the period. `MUST NOT` means exactly the same; use whichever reads closer to the source text.

- Taken: the rule continues with `LEST` (by default `BREACH`).
- Not taken when the deadline passes: the rule continues with `HENCE` (by default `FULFILLED`).

```l4
DECLARE Party IS ONE OF `The Employee`
DECLARE Action IS ONE OF `disclose confidential information`

GIVETH A DEONTIC Party Action
`confidentiality` MEANS
  PARTY `The Employee`
  SHANT `disclose confidential information`
  WITHIN 730
  LEST BREACH BY `The Employee` BECAUSE "breach of confidentiality"

GIVETH A DEONTIC Party Action
`confidentiality, worded as MUST NOT` MEANS
  PARTY `The Employee`
  MUST NOT `disclose confidential information`
  WITHIN 730
```

## DO

`DO` is the bare form, with no modal word.
Measured on the current release, it behaves exactly as `MUST` does: the same defaults when `HENCE` or `LEST` is omitted (`FULFILLED` and `BREACH`), and the same outcomes when the action is taken and when the deadline passes.

## Performer rule

When using the **value-actor encoding** (actors as values of one type, actions as records carrying their actor), `PARTY p MUST a` requires that `p` is the **performer** of action `a`, the actor in the first positional field. The same holds for `MAY` and `SHANT`: `PARTY p MAY a` and `PARTY p SHANT a` require that `p` performs `a`, just as with `MUST`. The check fires at compile time, so a mismatch is caught before anything runs:

```l4
DECLARE Actor IS ONE OF Eater, Drinker
DECLARE Action HAS actor IS AN Actor, verb IS A STRING
eat   MEANS Action OF Eater,   "eat"
drink MEANS Action OF Drinker, "drink"

GIVETH DEONTIC Actor Action
good MEANS PARTY Eater   MUST eat   WITHIN 30   -- ✅ Eater performs eat
bad  MEANS PARTY Drinker MUST eat   WITHIN 30   -- ❌ `eat` is performed by `Eater`, not by `Drinker`
```

This check applies only when the action carries an actor field. The older flat-union style (`DECLARE Action IS ONE OF deliver, pay`) carries no actor and is unaffected.

See [Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md) for the full rules, duplex actions, parameterised actions, and procurement.

## Summary

| Modal              | Meaning     | Action taken in time      | Deadline passes without the action |
| ------------------ | ----------- | ------------------------- | ---------------------------------- |
| `MUST`             | obligation  | `HENCE`                   | `LEST` (default `BREACH`)          |
| `MAY`              | permission  | `HENCE`                   | `LEST` (default `FULFILLED`)       |
| `SHANT / MUST NOT` | prohibition | `LEST` (default `BREACH`) | `HENCE`                            |
| `DO`               | bare action | `HENCE`                   | `LEST` (default `BREACH`)          |

## Related pages

- [Regulative rules](README.md): the parts of a rule and how to test it
- [Deadlines and consequences](consequences.md): `WITHIN`, `HENCE`, `LEST`, `PROVIDED`, `EXACTLY`, `RAND`, `ROR`
- [BECAUSE](BECAUSE.md): reasons for a breach
- [Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md): who may perform which action
