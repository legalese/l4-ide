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

## WAITUNTIL

`WAITUNTIL time` is an event that matches no party and no action. Use it to let time pass without anyone acting, so that a deadline runs out:

```l4
DECLARE Person IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF delivery

GIVETH A DEONTIC Person Action
`delivery duty` MEANS
  PARTY Seller
  MUST delivery
  WITHIN 3

#TRACE `delivery duty` AT 0 WITH
  WAITUNTIL 10
```

This gives a breach: the deadline at 3 passed with no delivery.

## EVENT as a type

`EVENT` is both the function that makes an event and the name of the events' type.
As a type it takes the party type and the action type, so a rule can take an event as an input and read it with `CONSIDER`, and another rule can make an event and pass it on.
The time of an event is always a `NUMBER`:

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

### An exported rule cannot take an event

A rule marked `@export` cannot take an event as an input, nor an input that holds one, such as a `LIST OF EVENT Person Action`.
An input with no written type, and an `ASSUME` that the rule reads, count as they do for a duty; see [What counts as an input](DEONTIC.md#what-counts-as-an-input).
A request to an exported rule is JSON, and JSON has no form for an event.
`l4 check` reports `EVENT inputs are not supported for @export` and names the input.
`l4 batch` and `jl4-schema` check the file first and stop with the same error, and `jl4-service` refuses to deploy it.
See [An @export that takes an EVENT or a DEONTIC](../errors/README.md#an-export-that-takes-an-event-or-a-deontic).

To publish such a rule, take the party, the action and the time as three inputs, and build the event inside the rule:

```l4
DECLARE Person IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF delivery, payment

@export The time of an event
GIVEN who IS A Person
      what IS AN Action
      `at time` IS A NUMBER
GIVETH A NUMBER
`when it happened` who what `at time` MEANS
  CONSIDER EVENT who what `at time`
  WHEN EVENT party action time THEN time

#EVAL `when it happened` Seller delivery 2
```

This gives `2`.
A request gives `who` and `what` by the name of the value, and `at time` as a number.
Each of the three inputs needs a type that a request can carry, such as an enumeration or a `NUMBER`.

A `DEONTIC` input is refused in the same way; see [An exported rule cannot take a DEONTIC input](DEONTIC.md#an-exported-rule-cannot-take-a-deontic-input).

## Related pages

- [DEONTIC](DEONTIC.md): the type of rules that events are matched against
- [PARTY, MUST, MAY, SHANT](PARTY.md)
- [Regulative rules](README.md): `#TRACE`
