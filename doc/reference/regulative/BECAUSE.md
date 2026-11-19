# BECAUSE

`BECAUSE` gives the reason for a breach. It comes after `BREACH`, optionally with `BY` and the party in breach.

## Syntax

```text
BREACH BECAUSE reason
BREACH BY party BECAUSE reason
BREACH BY LIST party, party BECAUSE reason
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

## Several parties

`BY` takes a `LIST` as well as a single party, for a breach that several parties carry together.
The list can be written out or worked out, and it is read when the breach happens.
Every name in it becomes one line of the answer, in the order written, each carrying the `BECAUSE`; the same party named twice is named twice, so a list that says a party is in breach two ways says so.

```l4
DECLARE Party IS ONE OF Seller, Carrier
DECLARE Action IS ONE OF deliver

GIVETH A DEONTIC Party Action
`delivery` MEANS
  PARTY Seller
  MUST deliver
  WITHIN 10
  LEST BREACH BY LIST Seller, Carrier BECAUSE "goods lost in transit"

#TRACE `delivery` AT 0 WITH
  WAITUNTIL 20
```

prints:

```
DEONTIC BREACHED:
  BREACH
  BY Seller BECAUSE "goods lost in transit"
  BY Carrier BECAUSE "goods lost in transit"
```

A breach blames at least one party, so a list with nobody in it is refused, and which check catches it depends on how it was written.
A list written out empty, `BY EMPTY` or `BY (LIST)`, is an error when the file is checked, before anything runs.
A list worked out by the rule that turns out to be empty when the breach happens is an error when the rule runs, naming where it is written.
To blame nobody, write no `BY` at all.

When the party type is itself a `LIST` (a group as one party, as in `PARTY (LIST "a", "b") MUST deliver`), `BY` followed by such a list names that one party, not its members; a list of such lists names several.
One case of this is refused where it should not be: a `BREACH BY` such a list written as the first operand of a `RAND` or `ROR` is a type error, even under a `GIVETH`.
Write the `BREACH` as the second operand instead.

You do not have to write the list yourself when the language already knows who failed.
When both sides of a `RAND`, or both alternatives of an `ROR`, are lost, the breach names both sides' failures, each with its own reason or its own missed deadline (see [RAND and ROR](consequences.md#rand-and-ror)).

## Related pages

- [Deadlines and consequences: FULFILLED and BREACH](consequences.md#fulfilled-and-breach)
- [PARTY, MUST, MAY, SHANT](PARTY.md)
- [DEONTIC](DEONTIC.md)
