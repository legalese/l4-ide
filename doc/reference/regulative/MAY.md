# MAY

Creates a permission for a party to perform an action. The party is allowed but not required to act.

## Syntax

```l4
PARTY partyName MAY action
PARTY partyName MAY action WITHIN deadline
PARTY partyName MAY DO action                 -- DO is optional, both forms are valid
PARTY partyName MAY DO action WITHIN deadline
```

## Purpose

MAY expresses a legal permission - something a party is allowed to do. Unlike obligations (MUST), permissions are optional.

## Examples

**Example file:** [may-example.l4](may-example.l4)

### Basic Permission

```l4
DECLARE Person IS ONE OF Alice, Bob
DECLARE Action IS ONE OF dance

GIVETH A DEONTIC Person Action
permissionRule MEANS
  PARTY Bob
  MAY dance
  WITHIN 60
```

### Permission as Remedy

```l4
DECLARE Person IS ONE OF Alice, Bob
DECLARE Action IS ONE OF pay, sue

GIVETH A DEONTIC Person Action
paymentWithRemedy MEANS
  PARTY Alice
  MUST pay
  WITHIN 30
  LEST PARTY Bob MAY sue WITHIN 60
```

## Permission Semantics

- Permission is **exercised** when the party performs the action
- Permission **expires** when the deadline passes without action
- Neither exercising nor not exercising a permission causes breach

## Performer Rule

When using the **value-actor encoding**, `PARTY p MAY a` requires that `p` is the **performer** of action `a`, just as with MUST. The check fires at compile time. See **[Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md)** for the full rules.

## Related Keywords

- **[PARTY](PARTY.md)** - Identifies who has the permission
- **[MUST](MUST.md)** - Obligation (required action)
- **[SHANT](SHANT.md)** - Prohibition (forbidden action)
- **[REGULATIVE](README.md)** - Full regulative rule reference
