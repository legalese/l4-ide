# BECAUSE

`BECAUSE` gives the reason for a breach. It comes after `BREACH`, optionally with `BY` and the party in breach.

## Syntax

```text
BREACH BECAUSE reason
BREACH BY party BECAUSE reason
```

| Form                                | Records                |
| ----------------------------------- | ---------------------- |
| `BREACH`                            | that a breach happened |
| `BREACH BY Seller`                  | who is in breach       |
| `BREACH BECAUSE "reason"`           | why                    |
| `BREACH BY Seller BECAUSE "reason"` | who and why            |

The reason is a STRING, either text in quotes or an expression that gives text.

**Example file:** [because-example.l4](because-example.l4)

## Example

```l4
DECLARE Party IS ONE OF Buyer, Seller
DECLARE Action IS ONE OF `pay invoice` HAS amount IS A NUMBER

`the amount due` MEANS 1000

GIVETH A DEONTIC Party Action
`payment` MEANS
  PARTY Buyer
  MUST `pay invoice` (EXACTLY `the amount due`)
  WITHIN 30
  HENCE FULFILLED
  LEST BREACH BY Buyer BECAUSE (CONCAT "failed to pay ", TOSTRING `the amount due`)

#TRACE `payment` AT 0 WITH
  WAITUNTIL 31
```

The `#TRACE` result shows the breach with its party and reason: `BREACH BY Buyer BECAUSE "failed to pay 1000"`.

`BREACH … BECAUSE` usually follows `LEST`, but it can stand wherever a rule can, for example after `HENCE` or in a branch of an `IF`.
When a contract has several ways to fail, give each its own reason, and cite the clause or section it comes from, so a reader of the result knows which duty failed and why.

## Related pages

- [Deadlines and consequences: FULFILLED and BREACH](consequences.md#fulfilled-and-breach)
- [PARTY, MUST, MAY, SHANT](PARTY.md)
- [DEONTIC](DEONTIC.md)
