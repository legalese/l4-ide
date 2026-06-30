# PARTY

Identifies the legal party (person or entity) who has an obligation, permission, or prohibition in a regulative rule.

## Syntax

```l4
PARTY partyName
PARTY partyName MUST ...
PARTY partyName MAY ...
PARTY partyName SHANT ...
```

## Purpose

PARTY is the starting point for regulative rules, specifying WHO is subject to the rule. It introduces:

- Obligations (MUST)
- Permissions (MAY)
- Prohibitions (SHANT)

## Examples

**Example file:** [party-example.l4](party-example.l4)

### Basic Obligation

```l4
DECLARE Person IS ONE OF Alice, Bob
DECLARE Action IS ONE OF sing

GIVETH A DEONTIC Person Action
myRule MEANS
  PARTY Alice
  MUST sing
  WITHIN 30
```

### Permission

```l4
DECLARE Person IS ONE OF Alice, Bob
DECLARE Action IS ONE OF dance

GIVETH A DEONTIC Person Action
permissionRule MEANS
  PARTY Bob
  MAY dance
  WITHIN 60
```

### Prohibition

```l4
DECLARE Person IS ONE OF Alice, Bob
DECLARE Action IS ONE OF smoke

GIVETH A DEONTIC Person Action
prohibitionRule MEANS
  PARTY Alice
  SHANT smoke
  WITHIN 30
```

### With Consequences

```l4
DECLARE Person IS ONE OF Alice, Bob
DECLARE Action IS ONE OF pay, sue

GIVETH A DEONTIC Person Action
ruleWithConsequence MEANS
  PARTY Alice
  MUST pay
  WITHIN 30
  LEST PARTY Bob MAY sue WITHIN 60
```

## Regulative Rule Structure

A complete regulative rule typically includes:

```l4
ruleName MEANS
  PARTY who          -- The party subject to the rule
  MUST/MAY/SHANT     -- The deontic modality
  action             -- What action is regulated
  WITHIN deadline    -- Time constraint
  HENCE consequent   -- What follows if rule is followed
  LEST alternative   -- What follows if rule is violated
```

## Performer Rule

When using the **value-actor encoding** (actors as values of one type, actions as records carrying their actor), `PARTY p MUST a` requires that `p` is the **performer** of action `a` — the actor in the first positional field. Mismatches are caught at compile time:

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

See **[Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md)** for the full rules, duplex actions, parameterised actions, and procurement.

## Related Keywords

- **[MUST](MUST.md)** - Obligation
- **[MAY](MAY.md)** - Permission
- **[SHANT](SHANT.md)** - Prohibition
- **[REGULATIVE](README.md)** - Full regulative rule reference

## See Also

- **[Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md)** - Who may perform which action
- **[Regulative Rules](../../concepts/legal-modeling/regulative-rules.md)** - Modeling obligations
