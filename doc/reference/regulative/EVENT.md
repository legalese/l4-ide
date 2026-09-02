# EVENT

The type of events that drive the execution of regulative rules. An event records **who** did **what**, and **when**.

## Syntax

```l4
-- As a type
EVENT partyType actionType

-- As a constructor
EVENT party action timestamp
```

## Purpose

A `DEONTIC party action` value describes obligations; a list of `EVENT party action` values describes what actually happened. Feeding events to a contract (via `#TRACE ... WITH ...` or the `EVALTRACE` function) advances the contract state and determines whether obligations are fulfilled or breached.

The EVENT constructor takes three arguments:

| Argument    | Type     | Meaning                          |
| ----------- | -------- | -------------------------------- |
| `party`     | `party`  | Who performed the action         |
| `action`    | `action` | What was done                    |
| `timestamp` | `NUMBER` | When it happened (contract time) |

## Examples

```l4
DECLARE Person IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF
  delivery
  payment HAS amount IS A NUMBER

-- Events in a #TRACE directive
#TRACE saleContract AT 0 WITH
  PARTY Seller DOES delivery AT 2
  PARTY Buyer DOES payment 100 AT 5

-- Events constructed explicitly for EVALTRACE
#EVAL EVALTRACE saleContract 0 (LIST (EVENT Seller delivery 2), (EVENT Buyer (payment 100) 5))
```

`EVALTRACE` has type `DEONTIC party action → NUMBER → LIST OF EVENT party action → DEONTIC party action`: it advances the contract from the given start time through the events and returns the residual contract state.

## WAIT UNTIL

`` `WAIT UNTIL` `` (a builtin, type `NUMBER → EVENT a b`) produces a synthetic event that matches no party and no action — it is only relevant for its timestamp. Use it to let time pass and trigger deadline expiry without any party acting:

```l4
#TRACE saleContract AT 0 WITH
  PARTY Seller DOES delivery AT 2
  (`WAIT UNTIL` 10)
```

## Notes

- EVENT is a builtin: the name serves both as the type (`EVENT party action`) and as its constructor. In current releases the constructor resolution takes precedence, so use EVENT to build values (and in `LIST OF EVENT ...` positions inside EVALTRACE calls) rather than as a standalone parameter type annotation.
- Events whose party or action matches nothing in the contract simply do not discharge any obligation; only their timestamps advance contract time (this is exactly how `` `WAIT UNTIL` `` works).

## Related Keywords

- **[DEONTIC](DEONTIC.md)** - The regulative rule type that events are matched against
- **[PARTY](PARTY.md)** - Declares who acts in a rule
- **[REGULATIVE](README.md)** - Full regulative rule reference, including `#TRACE`
