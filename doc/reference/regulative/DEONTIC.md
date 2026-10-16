# DEONTIC

`DEONTIC` is the type of regulative rules: obligations, permissions and prohibitions.
It takes two type parameters, the type of the parties and the type of the actions.

## Syntax

```text
GIVETH A DEONTIC PartyType ActionType
```

**Example file:** [deontic-example.l4](deontic-example.l4)

## Example

```l4
DECLARE Actor IS ONE OF Buyer, Seller
DECLARE Action IS ONE OF
  `deliver goods`
  `pay invoice` HAS amount IS A NUMBER

GIVETH A DEONTIC Actor Action
`delivery obligation` MEANS
    PARTY Seller
    MUST `deliver goods`
    WITHIN 14
    HENCE FULFILLED
    LEST BREACH
```

Every `PARTY` in the rule must be an `Actor`, and every action an `Action`.

## Values

A value of type `DEONTIC Party Action` is one of:

- a rule, `PARTY … MUST/MAY/SHANT …` (see [PARTY, MUST, MAY, SHANT](PARTY.md));
- `FULFILLED`: nothing more is owed;
- `BREACH`, optionally `BREACH BY party BECAUSE reason`: a party failed;
- two rules combined with `RAND` or `ROR` (see [Deadlines and consequences](consequences.md#rand-and-ror)).

Like any other value, a `DEONTIC` value can be the result of a function with `GIVEN` inputs, or of an `IF` or a `CONSIDER`:

```l4
DECLARE Actor IS ONE OF Buyer, Seller
DECLARE Action IS ONE OF `deliver goods`

GIVEN `is urgent` IS A BOOLEAN
GIVETH A DEONTIC Actor Action
`delivery` `is urgent` MEANS
    IF `is urgent`
    THEN PARTY Seller MUST `deliver goods` WITHIN 3
    ELSE PARTY Seller MUST `deliver goods` WITHIN 14
```

## Evaluation

A rule decides nothing on its own. It is evaluated from a start time against a list of events, each saying which party did what, and when (see [EVENT](EVENT.md)).
The result is a `DEONTIC` value again:

- `FULFILLED`, when every duty was discharged;
- `BREACH`, with who missed which deadline, when a duty failed and nothing absorbed the failure;
- the rule still waiting, when the events run out before either happens. This value can be given more events later.

`#TRACE` evaluates a rule in a file:

```text
#TRACE rule AT start-time WITH
  PARTY party DOES action AT time
  ...
```

`EVALTRACE` is the same evaluation as a function:

```text
EVALTRACE : DEONTIC party action → NUMBER → LIST OF EVENT party action → DEONTIC party action
```

```l4
DECLARE Actor IS ONE OF Buyer, Seller
DECLARE Action IS ONE OF `deliver goods`

GIVETH A DEONTIC Actor Action
`delivery obligation` MEANS
    PARTY Seller
    MUST `deliver goods`
    WITHIN 14

#TRACE `delivery obligation` AT 0 WITH
    PARTY Seller DOES `deliver goods` AT 10

#EVAL EVALTRACE `delivery obligation` 0 (LIST EVENT Seller `deliver goods` 10)
```

Both give `FULFILLED`. With no events at all, both give the rule still waiting, not `BREACH`: to let a deadline pass without anyone acting, add a `` `WAIT UNTIL` `` event.

`l4 state-graph` draws a rule's possible paths as a state diagram; see [Using the l4 CLI](../../tutorials/getting-started/l4-cli.md).

## Related pages

- [Regulative rules](README.md)
- [PARTY, MUST, MAY, SHANT](PARTY.md)
- [Deadlines and consequences](consequences.md)
- [EVENT](EVENT.md)
- [Foundation module 6: Regulative rules](../../courses/foundation/module-6-regulative.md): a step-by-step introduction
- [How obligations unfold](../../concepts/legal-modeling/regulative-rules.md): the model behind regulative rules
- [Tom Hvitved's PhD thesis](https://di.ku.dk/english/research/phd/phd-theses/2011/hvitved12phd.pdf): the theory L4's contract model is based on
