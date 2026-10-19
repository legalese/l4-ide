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
| `BREACH BY LIST Seller, Carrier`    | several parties        |

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
  MUST `pay invoice` `the amount due`
  WITHIN 30
  HENCE FULFILLED
  LEST BREACH BY Buyer BECAUSE (CONCAT "failed to pay ", TOSTRING `the amount due`)

#TRACE `payment` AT 0 WITH
  (`WAIT UNTIL` 31)
```

The `#TRACE` result shows the breach with its party and reason: `BREACH BY Buyer BECAUSE "failed to pay 1000"`.

`BREACH … BECAUSE` usually follows `LEST`, but it can stand wherever a rule can, for example after `HENCE` or in a branch of an `IF`.
When a contract has several ways to fail, give each its own reason, and cite the clause or section it comes from, so a reader of the result knows which duty failed and why.

## Several parties

`BY` takes a `LIST` as well as a single party, for a breach that several parties carry together. The list can be written out or computed, and it is read when the breach happens. Every name in it becomes one line of the answer, in the order written, each carrying the `BECAUSE`; the same party named twice is named twice — nothing is collapsed, so a list that says a party is in breach two ways says so.

```l4
LEST BREACH BY LIST Seller, Carrier BECAUSE "goods lost in transit"
```

prints, when it fires:

```
DEONTIC BREACHED:
  BREACH
  BY Seller BECAUSE "goods lost in transit"
  BY Carrier BECAUSE "goods lost in transit"
```

A breach blames at least one party, so a list with nobody in it is refused, and which check catches it depends on how it was written: a literal — `BY EMPTY`, or `BY (LIST)` with nothing inside — is an error when the file is checked, before anything runs; a computed list that turns out to be empty when the breach happens is an error when the rule runs, naming the clause. To blame nobody, write no `BY` at all.

When the party type is itself a `LIST` (a group as one party, `DEONTIC (LIST OF STRING) Action`), `BY` followed by such a list names that one party, not its members; a list of such lists names several. The checker can only tell the two readings apart once it knows the party type, so a `BREACH BY LIST …` written where nothing has fixed it yet — a definition with no `GIVETH`, or the first operand of a `RAND`/`ROR` in a definition with none — is refused when the file is checked, at the `BREACH`, and the message names the two fixes: put `GIVETH A DEONTIC <party> <action>` on the definition, or write the `PARTY` operand first. A `BY` under a `LEST` or `HENCE` always knows the party type, because the `PARTY` line above it fixed it.

You do not have to write the list yourself when the language already knows who failed. When both sides of a `RAND` are lost, the breach names both sides' failures, each with its own reason or its own missed deadline; when several members of an `EVERY … ONCE ALL HAVE` group fail and the group has no `LEST`, the breach names every one of them, each with their own deadline. See [EVERY](EVERY.md#what-runs-today-and-what-does-not).

## Related pages

- [Deadlines and consequences: FULFILLED and BREACH](consequences.md#fulfilled-and-breach)
- [PARTY, MUST, MAY, SHANT](PARTY.md)
- [DEONTIC](DEONTIC.md)
