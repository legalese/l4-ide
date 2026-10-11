# `WITHAL` — a record with all of its usual values

A **record** is a bundle of named facts: a paint order has a colour, a number of coats, and a flag for rush jobs.
Each field may carry a usual value, written with [`TYPICALLY`](TYPICALLY.md).
`WITHAL` ("with all") builds the record using **every** field's usual value, and writes none of them.

```l4
DECLARE Colour IS ONE OF Red, Green

DECLARE Paint
  HAS colour IS A Colour TYPICALLY Red
      coats  IS A NUMBER TYPICALLY 2
      rush   IS A BOOLEAN TYPICALLY FALSE

GIVETH A Paint
`stock paint` MEANS Paint WITHAL

#EVAL `stock paint`                           -- Paint OF Red, 2, FALSE
```

It means the same as writing every usual value out, and L4 treats it that way:

```l4
#ASSERT `stock paint` EQUALS (Paint WITH colour IS Red, coats IS 2, rush IS FALSE)
```

## Why a keyword, and not `Paint WITH` with nothing after it

[`WITH`](../functions/WITH.md) names the fields it gives.
A `WITH` that gave none would leave a keyword with nothing after it, and the reader would have to wonder whether something had been cut off.
`WITHAL` is one word that says what it does, and it has no list that has to be empty.

It also says what you intended, which L4 can check.
If someone later adds a field to `Paint` that has no usual value, `Paint WITHAL` stops working, and the error names the new field.
A bare `Paint` could not tell you that.
It is not a record: it is the function that makes a `Paint` from its fields, still waiting for them.

## One spelling for each thing

`WITHAL` stands alone: no field may follow it.
Setting a field after it is a parse error:

```l4
`glossy paint` MEANS Paint WITHAL coats IS 3     -- a parse error
```

A name after `WITHAL` is not read as a field being set.
It is read as a function applied to the record, so `Paint WITHAL coats` is the number of coats, 2, the same as `coats (Paint WITHAL)`.
That is why the example above fails at the `IS` and not at `coats`.

To change one field, name it with `WITH`.
The other fields still take their usual values:

```l4
`three coats` MEANS Paint WITH coats IS 3
```

So there is exactly one way to write each construction: `WITH` names the fields you give, and `WITHAL` gives none.

## When it is refused

- **A field has no usual value.**
  `WITHAL` takes the usual value of _every_ field, so a record with a field that has none cannot be built this way, and L4 names each such field:

  ```
  WITHAL takes the default of every field, but these fields of

    Order (defined at withal-example.l4:41:9-14)

  have none:

    item of type STRING
  ```

  Give the field a `TYPICALLY`, or build the record with `WITH` and name the fields that have no usual value (`Order WITH item IS "pen"`).

- **The name is not a record.**
  `WITHAL` builds records.
  A rule, a field, and an input of a rule are each refused, with one message: the name is not a record.
  An alternative declared with `ONE OF` gets a message of its own, one for an alternative that carries data and one for an alternative that carries nothing.
  An alternative that carries data, such as `Circle HAS radius IS A NUMBER`, still has to be given its fields, even a field that has a `TYPICALLY`.
  To call a rule and leave some of its inputs to their usual values, name the other inputs with `WITH`.

- **More than one definition has the name.**
  If a rule that takes inputs shares its name with a record, `WITHAL` names no field that could tell them apart, so L4 reports the name as ambiguous.
  Rename one of them.
  A rule with no inputs of its own, such as `Paint MEANS 3`, is not a rival: the record is chosen.

## What it does at the boundary

A usual value is a _presumption_, and the presumption can be switched off for a case: `l4 batch --presumption hard`, or `"presumption": "hard"` in a request to the decision service.
`WITHAL` is inside your rules, where no case could have supplied the value, so it takes the usual values in both modes.
In either mode the answer lists each one under **`presumed`** as `WITH Paint: coats`, exactly as it lists a `WITH` that left the field out.
A record declared under a section heading is named behind it: `WITH Pricing.Paint: coats`.

A rule can also read a record from JSON text.
When the text is an empty object, `{}`, it supplies nothing, and a field that has a usual value takes it.
So for a record in which **every** field has a usual value, reading `{}` gives the record `WITHAL` builds.
Both `l4 batch` and the decision service run this:

```l4
GIVEN text IS A STRING
GIVETH AN EITHER STRING Paint
`read paint` MEANS JSONDECODE text

#ASSERT `read paint` "{}" EQUALS RIGHT (Paint WITHAL)
```

That holds only when every field has a usual value.
A field declared `MAYBE` with no usual value is filled with `NOTHING` when the text is read, while `WITHAL` refuses to build the record and names the field.
`WITHAL` takes the usual values a record declares, and never works one out from a field's kind of thing.

An empty object written as the _value_ of a record input in a case is a different thing.
It means "not known".
An input that must have a value, sent `{}`, is refused, naming the input.
An input declared `MAYBE`, sent `{}`, is `NOTHING`, and the case succeeds.
Inside your rules, `WITHAL` is how you say "a record with every usual value".

## Limits

- **`WITHAL` is now a reserved word.**
  A name spelled exactly `WITHAL` has to be written in backticks.
  `withal` in lower case is still an ordinary name, because keywords are matched by their capitals.
- **Records only.**
  A rule that has a usual value for every input still has no keyword for calling it with all of them.
  Name an input with `WITH`.
- **A record with no fields** is accepted, and `WITHAL` on it is that record.
- **Not in a pattern.**
  `CONSIDER … WHEN Paint WITHAL` is not accepted, because a pattern lists the fields it matches.
- **The usual values must be fixed values** written out: a number, text, `TRUE`, `FALSE`, `NOTHING`, or a constructor of an enumeration.
  That is a limit of `TYPICALLY`, and `WITHAL` inherits it.

## Example

Every record on this page, in one file you can run:

[withal-example.l4](withal-example.l4)

## See also

- [`TYPICALLY`](TYPICALLY.md) — the usual value of a field, an input or a section `GIVEN`
- [`WITH`](../functions/WITH.md) — naming the fields of a record, or the inputs of a call
- [`DECLARE`](DECLARE.md) — declaring a record
