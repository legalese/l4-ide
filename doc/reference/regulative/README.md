# Regulative rules

Regulative rules say what a party must, may or must not do, by when, and what follows if they do or do not.
In L4 each such rule is a value of type [DEONTIC](DEONTIC.md). It decides nothing on its own: it is evaluated against a list of events, with `#TRACE`.

## Parts of a rule

```text
PARTY party                 -- who the rule applies to
MUST action                 -- or MAY, SHANT, MUST NOT, DO
PROVIDED condition          -- optional: a condition on the action
WITHIN deadline             -- optional: how long the party has
HENCE rule-if-complied      -- optional: what follows when the rule is complied with
LEST rule-if-not            -- optional: what follows when it is not
```

| Keyword               | Meaning                          | Page                                                               |
| --------------------- | -------------------------------- | ------------------------------------------------------------------ |
| `PARTY`               | who the rule applies to          | [PARTY, MUST, MAY, SHANT](PARTY.md)                                |
| `MUST`                | obligation                       | [PARTY, MUST, MAY, SHANT](PARTY.md#must)                           |
| `MAY`                 | permission                       | [PARTY, MUST, MAY, SHANT](PARTY.md#may)                            |
| `SHANT / MUST NOT`    | prohibition                      | [PARTY, MUST, MAY, SHANT](PARTY.md#shant-and-must-not)             |
| `DO`                  | bare action                      | [PARTY, MUST, MAY, SHANT](PARTY.md#do)                             |
| `PROVIDED`            | condition on the action          | [Deadlines and consequences](consequences.md#provided)             |
| `EXACTLY`             | match the value of an expression | [Deadlines and consequences](consequences.md#exactly)              |
| `WITHIN`              | relative deadline                | [Deadlines and consequences](consequences.md#within)               |
| `HENCE`, `LEST`       | what follows                     | [Deadlines and consequences](consequences.md#hence-and-lest)       |
| `FULFILLED`, `BREACH` | end states                       | [Deadlines and consequences](consequences.md#fulfilled-and-breach) |
| `BECAUSE`             | reason for a breach              | [BECAUSE](BECAUSE.md)                                              |
| `RAND`, `ROR`         | rules that run side by side      | [Deadlines and consequences](consequences.md#rand-and-ror)         |

## Example

```l4
DECLARE Person IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF
  delivery
  payment HAS amount IS A NUMBER

GIVETH A DEONTIC Person Action
`sale contract` MEANS
  PARTY Seller
  MUST delivery
  WITHIN 3
  HENCE
    PARTY Buyer
    MUST payment 100
    WITHIN 7
    LEST BREACH BY Buyer BECAUSE "late payment"
  LEST BREACH BY Seller BECAUSE "late delivery"

#TRACE `sale contract` AT 0 WITH
  PARTY Seller DOES delivery AT 2
  PARTY Buyer DOES payment 100 AT 5
```

The seller delivers at 2, within 3; the buyer then has 7 from 2, and pays at 5. The result is `FULFILLED`.

## Testing with #TRACE

```text
#TRACE rule AT start-time WITH
  PARTY party DOES action AT time
  (`WAIT UNTIL` time)
```

`#TRACE` reads the events in order and gives `FULFILLED`, `BREACH`, or the rule still waiting for more events. A `` `WAIT UNTIL` `` event lets time pass without anyone acting.
`#EVAL` of a rule only shows the rule itself; see [#EVAL shows the rule instead of an outcome](../errors/README.md#eval-shows-the-rule-instead-of-an-outcome).
See [DEONTIC: Evaluation](DEONTIC.md#evaluation) and [EVENT](EVENT.md).

## Pages

- [PARTY, MUST, MAY, SHANT](PARTY.md): the party and the modal
- [Deadlines and consequences](consequences.md): `WITHIN`, `HENCE`, `LEST`, `PROVIDED`, `EXACTLY`, `FULFILLED`, `BREACH`, `RAND`, `ROR`
- [BECAUSE](BECAUSE.md): reasons for a breach
- [DEONTIC](DEONTIC.md): the type of rules, and `EVALTRACE`
- [EVENT](EVENT.md): events and `` `WAIT UNTIL` ``

[How obligations unfold](../../concepts/legal-modeling/regulative-rules.md) explains the model, and [Foundation module 6](../../courses/foundation/module-6-regulative.md) teaches it step by step.
