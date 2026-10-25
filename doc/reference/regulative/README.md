# Regulative rules

Regulative rules say what a party must, may or must not do, by when, and what follows if they do or do not.
In L4 each such rule is a value of type [DEONTIC](DEONTIC.md). It decides nothing on its own: it is evaluated against a list of events, with `#TRACE`.

> **See also:** [Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md) — how L4 decides _who may perform which action_ (the performer/agreement rule, duplex actions, parameterised actions applied by a rule, and higher-order procurement), with worked ✅/❌ examples.

## Parts of a rule

```text
PARTY party                 -- who the rule applies to
MUST action                 -- or MAY, SHANT, MUST NOT, DO
PROVIDED condition          -- optional: a condition on the action
AFTER opening               -- optional: when the window opens
WITHIN deadline             -- optional: how long the party has (or BEFORE date)
HENCE rule-if-complied      -- optional: what follows when the rule is complied with
LEST rule-if-not            -- optional: what follows when it is not
```

| Keyword                | Meaning                                                  | Page                                                               |
| ---------------------- | -------------------------------------------------------- | ------------------------------------------------------------------ |
| `PARTY`                | who the rule applies to                                  | [PARTY, MUST, MAY, SHANT](PARTY.md)                                |
| `EVERY`                | one rule for every member of a group                     | [EVERY](EVERY.md)                                                  |
| `MUST`                 | obligation                                               | [PARTY, MUST, MAY, SHANT](PARTY.md#must)                           |
| `MAY`                  | permission                                               | [PARTY, MUST, MAY, SHANT](PARTY.md#may)                            |
| `SHANT / MUST NOT`     | prohibition                                              | [PARTY, MUST, MAY, SHANT](PARTY.md#shant-and-must-not)             |
| `DO`                   | bare form; behaves as `MUST`                             | [PARTY, MUST, MAY, SHANT](PARTY.md#do)                             |
| `PROVIDED`             | condition on the action                                  | [Deadlines and consequences](consequences.md#provided)             |
| `AFTER`                | when the window opens (a duration, or a date)            | [AFTER](AFTER.md)                                                  |
| `WITHIN`               | deadline: relative, or absolute with `OF`                | [Deadlines and consequences](consequences.md#within)               |
| `BEFORE`               | absolute deadline: the window closes on a date           | [Deadlines and consequences](consequences.md#before)               |
| `HENCE`, `LEST`        | what follows                                             | [Deadlines and consequences](consequences.md#hence-and-lest)       |
| `FULFILLED`, `BREACH`  | end states                                               | [Deadlines and consequences](consequences.md#fulfilled-and-breach) |
| `BECAUSE`              | reason for a breach                                      | [BECAUSE](BECAUSE.md)                                              |
| `RAND`, `ROR`          | rules that run side by side                              | [Deadlines and consequences](consequences.md#rand-and-ror)         |
| `EXACTLY` (deprecated) | a name in an action already refers to the thing it names | [Deadlines and consequences](consequences.md#exactly-deprecated)   |

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
`l4 run` prints what the contract has become after the events. To have that read out as a list — what is owed now, what would discharge it, what would put someone in breach, and the next deadline — run `l4 lts` on the same file; see [What is owed now: `l4 lts`](lts-list.md).
To keep a trace alive while the contract runs, with each new act checked against the history as it stands at that moment, see [The instance ledger](ledger.md).
See [DEONTIC: Evaluation](DEONTIC.md#evaluation) and [EVENT](EVENT.md).

## Pages

- [PARTY, MUST, MAY, SHANT](PARTY.md): the party and the modal
- [EVERY](EVERY.md): one obligation for every member of a group; the group is given as a list after `IN`, as `EVERY Tenant t IN tenants`
- [AFTER](AFTER.md): the window's opening edge; the two readings of a two-edged window
- [Deadlines and consequences](consequences.md): `WITHIN` and its anchors, `BEFORE`, `HENCE`, `LEST`, `PROVIDED`, action patterns and the deprecated `EXACTLY`, `FULFILLED`, `BREACH`, `RAND`, `ROR`, and when a breach happened
- [BECAUSE](BECAUSE.md): reasons for a breach
- [DEONTIC](DEONTIC.md): the type of rules, and `EVALTRACE`
- [EVENT](EVENT.md): events and `` `WAIT UNTIL` ``
- [What is owed now: `l4 lts`](lts-list.md): read a `#TRACE` out as a list of what is owed, what would discharge it and what would breach it
- [State graph and `--dominators`](STATE-GRAPH.md): the map of a rule's `HENCE`/`LEST` paths, as **Show state graph** in the editor and `l4 state-graph` on the command line
- [The instance ledger](ledger.md): run one contract as it happens, one proposed act at a time, each checked and recorded in a single step against the history as it stands at that instant

[How obligations unfold](../../concepts/legal-modeling/regulative-rules.md) explains the model, and [Foundation module 6](../../courses/foundation/module-6-regulative.md) teaches it step by step.
