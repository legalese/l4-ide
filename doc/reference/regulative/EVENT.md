# EVENT

An event records that a party did an action at a time. A list of events is what a regulative rule is evaluated against: it decides which duties are fulfilled or breached.

## Syntax

```text
PARTY party DOES action AT time        -- in a #TRACE
EVENT party action time                -- as a value, for EVALTRACE
GIVEN e IS AN EVENT party action       -- as a type, for an input
```

| Part     | Type            | Meaning                      |
| -------- | --------------- | ---------------------------- |
| `party`  | the party type  | who acted                    |
| `action` | the action type | what they did                |
| `time`   | `NUMBER`        | when, on the rule's timeline |

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

-- Events in a #TRACE
#TRACE `sale contract` AT 0 WITH
  PARTY Seller DOES delivery AT 2
  PARTY Buyer DOES payment 100 AT 5

-- The same events as values, for EVALTRACE
#EVAL EVALTRACE `sale contract` 0 (LIST (EVENT Seller delivery 2), (EVENT Buyer (payment 100) 5))
```

`EVALTRACE` takes the rule, the start time and the list of events, and returns the rule's state after them; see [DEONTIC: Evaluation](DEONTIC.md#evaluation).

## How events are read

- Events are read in order, and each moves the clock to its time.
- An event by the rule's party whose action matches the rule fulfils it (or, for a prohibition, breaches it).
- An event by another party, or with another action, is skipped; only its time counts.
- An event after a deadline shows that the deadline has passed, and the rule moves on to `LEST` (or, for `MAY` and `SHANT`, `HENCE`); see [Deadlines and consequences](consequences.md#within).

## WAIT UNTIL

`` `WAIT UNTIL` time `` is an event that matches no party and no action. Use it to let time pass without anyone acting, so that a deadline runs out:

```l4
DECLARE Person IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF delivery

GIVETH A DEONTIC Person Action
`delivery duty` MEANS
  PARTY Seller
  MUST delivery
  WITHIN 3

#TRACE `delivery duty` AT 0 WITH
  (`WAIT UNTIL` 10)
```

This gives a breach: the deadline at 3 passed with no delivery.

## EVENT as a type

`EVENT` names the type of events as well as the function that makes one.
Written as a type it takes the type of the parties and the type of the actions, so a rule can take an event as an input and read it with `CONSIDER`, and another rule can build an event and hand it on.
The time of an event is always a `NUMBER`.

```l4
DECLARE Person IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF
  delivery
  payment HAS amount IS A NUMBER

GIVEN e IS AN EVENT Person Action
GIVETH A NUMBER
`when it happened` e MEANS
  CONSIDER e
  WHEN EVENT party action time THEN time

GIVEN who IS A Person
GIVETH A NUMBER
`when it was delivered` who MEANS `when it happened` (EVENT who delivery 2)

#EVAL `when it was delivered` Seller
```

This gives `2`.

A type of your own that is also called `EVENT` and takes two parameters is ambiguous with the built-in one wherever it is named; see [Several definitions with the same name](../errors/README.md#several-definitions-with-the-same-name).

## EVENT and @export

A rule published with `@export` cannot take an `EVENT` as an input or give one back as its result, because a request has no way to write one.
The same goes for a `LIST OF` events or a `MAYBE OF` an event.
`l4 check` reports an error at the `@export` line and the service will not deploy the file; see [An @export that takes or returns an EVENT](../errors/README.md#an-export-that-takes-or-returns-an-event).
An `EVENT` that the rule builds or reads inside its body is not affected.

## Related pages

- [DEONTIC](DEONTIC.md): the type of rules that events are matched against
- [PARTY, MUST, MAY, SHANT](PARTY.md)
- [Regulative rules](README.md): `#TRACE`
