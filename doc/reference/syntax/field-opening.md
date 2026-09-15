# Field opening: reading a record's fields by name

Inside a rule whose input is a record, the record's fields can be read by
their **bare names**. `person's `bankrupt``still works;`bankrupt` on its own
now means the same thing.

A rule is told some facts about the case in front of it (its **"inputs"**, the
names listed after `GIVEN`). Often one of those inputs is a record — a
`Person`, an `Applicant`, an `Issuer` — and the rule is really about the
record's fields. Until now every read had to say whose field it was:

```l4
GIVEN person IS A Person
GIVETH A BOOLEAN
DECIDE `is eligible` IF
        person's `the age` >= 21
    AND NOT person's `bankrupt`
```

Because the rule has exactly one `Person`, the `person's` in front of every
field says nothing the reader did not already know. So it may be left off:

```l4
GIVEN person IS A Person
GIVETH A BOOLEAN
DECIDE `is eligible` IF
        `the age` >= 21
    AND NOT `bankrupt`
```

The two rules are the same rule. Behind the scenes the bare `bankrupt` is
turned into `person's `bankrupt`` before anything else looks at it, so every
check, every evaluation, every export and every generated document sees the
spelled-out form. Nothing downstream can tell which one you wrote.

The full example is [field-opening-example.l4](field-opening-example.l4).

## Which inputs open

Any input declared **with a record type** — in the rule's own `GIVEN`, or in a
[section `GIVEN`](section-given.md) that the rule sits under:

```l4
§ `Applicant checks`
    GIVEN applicant IS A Person

GIVETH A BOOLEAN
DECIDE `applicant is solvent` IF NOT `bankrupt`      -- applicant's `bankrupt`
```

A rule under that heading that reads `bankrupt` reads the section's
`applicant`, and takes `applicant` as an input exactly as if it had written
`applicant's `bankrupt``— the caller supplies it with`WITH applicant IS ...`
as usual.

Records declared in an imported module open too: a rule with
`GIVEN d IS A Dictionary NUMBER STRING` can read the prelude's `contents`
bare.

## Which inputs do not

- **An input written without a type** (`GIVEN x`, or a parameter that appears
  only in the head, `f p MEANS ...`) does not open. L4 works its type out later;
  field opening needs it up front. Write the type, or write `p's f`.
- **A synonym for a record** does not open. If `DECLARE Outline IS A RoseTree
OF Item`, an input `c IS AN Outline` does not put `RoseTree`'s fields in
  scope. Write `c's value`.
- **Inputs of a `FUNCTION ... YIELD` lambda** do not open. The lambda's
  parameters are ordinary names inside it, nothing more.
- **Lists, `MAYBE`s and other wrappers** do not open. `GIVEN ps IS A LIST OF
Person` puts no `Person` field in scope, because there is no one person to
  read it from.

## A rule never sees its caller's fields

Opening is **lexical**: it reaches exactly the body that declares the input —
including that body's `WHERE` and `LET` locals — and nothing it calls. A rule
called from `is eligible` does not inherit `person`; it declares its own
input, and opens that:

```l4
GIVEN p IS A Person
GIVETH A BOOLEAN
DECIDE `over 18` IF `the age` > 18          -- p's `the age`, never the caller's
```

## When two inputs share a field name

If a rule has two record inputs and both records have a field called `name`,
a bare `name` could mean either. That is an error, reported twice — at the
read, and at the second input that opened the name — and the fix is to say
which:

```
Two inputs of this rule have a field named

  `name`

so on its own the name could belong to either:

  buyer's name      (buyer IS A Buyer, declared at contract.l4:13:7-12)
  seller's name     (seller IS A Seller, declared at contract.l4:14:7-13)

Write the one you mean with its input in front, as shown.
```

Two inputs that merely _share_ a field name are fine. The prelude itself
declares `dict1 IS A Dictionary k v, dict2 IS A Dictionary k v` and reads
`dict1's contents`; nothing is reported until a body reads the shared name
bare. This is also why the same-typed pair — `GIVEN a IS A Vector, b IS A
Vector` — is not refused at the declaration: it is only the bare read that has
no answer.

## When a name is bound twice

A bare name is resolved **from the inside out**, and the first thing that
binds it wins:

1. a `WHERE` or `LET` local of the body;
2. the rule's own name and its own inputs, by name — so `GIVEN amount IS A
Money` reads `amount` as the input, and `amount's amount` as its field;
3. the fields opened from the rule's own record inputs;
4. the section's inputs, by name;
5. the fields opened from the section's record inputs;
6. everything else — top-level definitions, constructors, and the record
   selectors themselves.

Two of these are worth knowing, because they are **silent**: a field opened
from a rule's own input shadows a same-named section input and a same-named
top-level definition, with no diagnostic. The rule you are reading is the rule
that wins. Everything else about opening is loud: a collision is an error, and
a field read where its type does not fit is the ordinary type error, anchored
at the bare read.

Only a **bare** name is affected. A name applied to arguments — `f x`,
`f OF x`, `` `band width` applicant `` — is left exactly as it was, so a
function that happens to share a field's name is still called, not projected.
The label of a projection (`x's f`) and the field names in a `WITH`
construction (`Person WITH `the age` IS 30`) are likewise untouched.

## Computed fields use the same rule

A [computed field](../types/DECLARE.md) — `adult IS A BOOLEAN MEANS `the age`

> = 18`inside a`DECLARE` — has always read its sibling fields bare. It is the
> same mechanism: the computed field is a rule whose one input is the record,
> and that input opens.

## See also

- [GIVEN](../functions/GIVEN.md) — declaring a rule's inputs.
- [The section `GIVEN`](section-given.md) — one input for a whole section.
- [DECLARE](../types/DECLARE.md) — records, and computed fields.
- [`'s` (the genitive)](README.md) — the spelled-out form, `person's `bankrupt``.
