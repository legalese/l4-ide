# MAY

Creates a permission for a party to perform an action. The party is allowed but not required to act.

## Syntax

```l4
PARTY partyName MAY action
PARTY partyName MAY action WITHIN deadline
PARTY partyName MAY action WITHIN deadline HENCE consequence
PARTY partyName MAY action WITHIN deadline HENCE consequence LEST alternative
```

(`MAY DO action` is also accepted; the `DO` is optional.)

## Purpose

MAY expresses a legal permission - something a party is allowed to do. Unlike obligations (MUST), permissions are optional: not exercising a MAY is never a breach.

Typical legal uses include early-termination rights, options to renew or extend, prepayment rights, conversion rights, and put/call options.

## Examples

**Example file:** [may-example.l4](may-example.l4)

### Basic Permission

```l4
DECLARE `Contract Party` IS ONE OF `The Lender`, `The Borrower`
DECLARE `Contract Action` IS ONE OF
  `prepay loan` HAS `prepayment amount` IS A NUMBER

-- The Borrower may prepay the loan within the first year
`prepayment option` MEANS
  PARTY `The Borrower`
  MAY `prepay loan` 100000
  WITHIN 365
```

### Permission Chained After an Obligation

```l4
`purchase with warranty` MEANS
  PARTY `The Buyer`
  MUST `make payment` 5000
  WITHIN 7
  HENCE
    PARTY `The Buyer`
    MAY `claim warranty benefit` "extended warranty coverage"
    WITHIN 365
```

### Permission That Triggers a New Obligation

If the buyer exercises the warranty claim, the seller becomes obliged to act:

```l4
`warranty claim process` MEANS
  PARTY `The Buyer`
  MAY `claim warranty benefit` "defect repair"
  WITHIN 730
  HENCE
    PARTY `The Seller`
    MUST `repair the defect`
    WITHIN 30
```

## Permission Semantics

- Permission is **exercised** when the party performs the action: the HENCE branch (default `FULFILLED`) continues the contract.
- Permission **expires** when the deadline passes without action: the LEST branch runs, and it defaults to `FULFILLED` (not `BREACH`).
- Neither exercising nor not exercising a permission causes breach by itself. A breach can only arise from obligations reached via HENCE/LEST.

## Testing

```l4
-- Exercised
#TRACE `prepayment option` AT 0 WITH
  PARTY `The Borrower` DOES `prepay loan` 100000 AT 180

-- Not exercised - still no breach
#TRACE `prepayment option` AT 0 WITH
```

## Pitfalls

- **Expecting breach on expiry.** An unexercised MAY silently fulfills (LEST defaults to `FULFILLED`). If inaction should have consequences, attach an explicit LEST branch.
- **Confusing MAY with DO.** `DO` expresses bare optionality and has no default HENCE/LEST branches; MAY defaults both to `FULFILLED`.
- **Forgetting the deadline.** A MAY without WITHIN never expires within the trace, which can keep a contract from reaching a terminal state.

## Related Keywords

- **[PARTY](PARTY.md)** - Identifies who has the permission
- **[MUST](MUST.md)** - Obligation (required action)
- **[SHANT](SHANT.md)** - Prohibition (forbidden action)
- **[DEONTIC](DEONTIC.md)** - The type of regulative rules
- **[REGULATIVE](README.md)** - Full regulative rule reference (HENCE, LEST, WITHIN defaults)
