# MUST

Creates an obligation for a party to perform an action. The party is required to do something.

## Syntax

```l4
PARTY partyName MUST action
PARTY partyName MUST action WITHIN deadline
PARTY partyName MUST DO action                 -- DO is optional, both forms are valid
PARTY partyName MUST DO action WITHIN deadline
PARTY partyName MUST NOT DO action             -- prohibition form; equivalent to SHANT
```

## Purpose

MUST expresses a legal obligation - something that a party is required to do. If not fulfilled within the deadline, consequences (LEST) may apply.

## Examples

**Example file:** [must-example.l4](must-example.l4)

### Basic Obligation

```l4
DECLARE Person IS ONE OF Alice, Bob
DECLARE Action IS ONE OF pay

GIVETH A DEONTIC Person Action
paymentObligation MEANS
  PARTY Alice
  MUST pay
  WITHIN 30
  HENCE FULFILLED
  LEST BREACH
```

### Obligation with Chained Consequence

```l4
DECLARE Person IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF deliver, pay

GIVETH A DEONTIC Person Action
saleContract MEANS
  PARTY Seller
  MUST deliver
  WITHIN 14
  HENCE (
    PARTY Buyer
    MUST pay
    WITHIN 30
    HENCE FULFILLED
    LEST BREACH
  )
  LEST BREACH
```

## Obligation Fulfillment

- Obligation is **fulfilled** when the party performs the action before the deadline
- Obligation is **breached** when the deadline passes without the action
- Consequences in LEST clause activate on breach

## Performer Rule

When using the **value-actor encoding**, `PARTY p MUST a` requires that `p` is the **performer** of action `a`. A Drinker cannot be obligated to an Eater's action — the compiler rejects the mismatch. See **[Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md)** for the full rules.

## Related Keywords

- **[PARTY](PARTY.md)** - Identifies who has the obligation
- **[MAY](MAY.md)** - Permission (optional action)
- **[SHANT](SHANT.md)** - Prohibition
- **[REGULATIVE](README.md)** - Full regulative rule reference
