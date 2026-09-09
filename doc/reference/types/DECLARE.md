# DECLARE

Declares a new type in L4. Types can be records (product types), enums (sum types), type synonyms, or **opaque types** — a type that is named but not described.

## Syntax

```l4
DECLARE TypeName IS ...
DECLARE TypeName HAS ...
DECLARE TypeName IS ONE OF ...
DECLARE TypeName
```

## Forms

### Record Types (Product Types)

Records are types with named fields:

```l4
DECLARE Person
  HAS
    name IS A STRING
    age IS A NUMBER
```

### Enum Types (Sum Types)

Enums define a type with multiple alternatives:

```l4
DECLARE Colour IS ONE OF red, green, blue
```

Enum constructors can have fields:

```l4
DECLARE Shape IS ONE OF
  Circle HAS radius IS A NUMBER
  Rectangle HAS width IS A NUMBER, height IS A NUMBER
```

#### A field on several constructors

When two or more constructors declare a field with the same name **and** the same type, that is one
field. It can be read with `'s` from a value built by any of those constructors, and like every
field it is an ordinary function:

```l4
DECLARE Actor IS ONE OF
    Landlord HAS addr IS A STRING, name IS A STRING
    Tenant   HAS name IS A STRING, rent IS A NUMBER

theLandlord MEANS Landlord OF "1 Main St", "Ms Ng"
alice       MEANS Tenant OF "Alice", 1500

#EVAL theLandlord's name   -- "Ms Ng"
#EVAL alice's name         -- "Alice"
```

The field's position does not matter: `name` is the second field of a `Landlord` and the first of a
`Tenant`.

One limit: the same name at **different** types on two constructors is an error at the declaration,
and the message names each constructor and the type it gives the field. Give the field one type, or
give it two names. The types have to be written the same way: a synonym (`DECLARE Money IS NUMBER`)
and the type it stands for count as different here.

**Example file:** [shared-field-example.l4](shared-field-example.l4)

#### A field on only some constructors

`rent` above is a `Tenant`'s alone. A `Landlord` has no `rent` — there is nothing for the question
to read — so L4 will not let you ask it unless it can see that the value is a `Tenant`:

```l4
GIVEN a IS AN Actor
GIVETH A NUMBER
`rent owed by` a MEANS a's rent   -- refused
```

> `rent` is a field of `Tenant` only.
> But `a` could also be `Landlord`, which has no `rent`.

This is a refusal at check time, not a surprise at run time. The same question used to be accepted
and then die halfway through a run, on whichever case first turned out to be a `Landlord`.

**How to narrow.** Four ways, all of which say the same thing — "here, this value is a `Tenant`":

```l4
-- 1. Take the value apart. The branch you are in tells the checker what `a` is,
--    so the read is legal inside that branch and nowhere else.
GIVEN a IS AN Actor
GIVETH A NUMBER
`rent owed by` a MEANS
    CONSIDER a
    WHEN Landlord addr name THEN 0
    WHEN Tenant name rent   THEN a's rent

-- 2. Read the payload straight out of the pattern, which is shorter and needs
--    no projection at all. Usually the one you want.
GIVEN a IS AN Actor
GIVETH A NUMBER
`rent owed by` a MEANS
    CONSIDER a
    WHEN Tenant name rent THEN rent
    OTHERWISE 0

-- 3. An OTHERWISE gets whatever the branches above it did not take. `Landlord`
--    is used up by the branch above, so only a `Tenant` can reach here.
GIVEN a IS AN Actor
GIVETH A NUMBER
`rent owed by` a MEANS
    CONSIDER a
    WHEN Landlord addr name THEN 0
    OTHERWISE a's rent

-- 4. In a quantified rule, name the constructor. `EVERY Tenant t` says the rule
--    ranges over tenants, so `t's rent` in the filter is safe.
GIVETH A DEONTIC Actor Action
`rich tenants sign` MEANS
    EVERY Tenant t IN everyone
        WHO    t's rent AT LEAST 1000
        MUST   Sign (EXACTLY t)
        WITHIN 14
```

**What does not narrow.** These are the cases people meet by accident, so it is worth knowing them
before the error does:

- **A `GIVEN` parameter is not narrowed by anything.** `GIVEN a IS AN Actor` says `a` is an `Actor`,
  which is the whole type. Only the body can narrow it.
- **Only a plain name can be narrowed.** `p's birthPlace's val` is a projection, not a name, so
  there is no name for a branch to attach the fact to. Give it a name first
  (`CONSIDER v … WHERE v MEANS p's birthPlace`), or — usually better — match the payload:
  `CONSIDER p's birthPlace WHEN Just place THEN place's town`.
- **A branch only uses up its constructor if it matches every one of them.**
  `WHEN Tenant name rent` takes every `Tenant`, so nothing is left for a later `OTHERWISE`.
  `WHEN Tenant "Alice" 1500` takes only the tenant called Alice paying 1500, so a `Tenant` can still
  reach the `OTHERWISE` — and a read of a `Landlord`-only field there is refused. The message names
  the branch that did it, so you do not have to work out which one.
- **A name that stands for another name inherits its narrowing.** `WHERE b MEANS a` makes `b` as
  narrow as `a` is at that point, so naming a subexpression never changes whether the file checks.
  A name that stands for something else — `b MEANS f a`, `b MEANS w's inner` — narrows nothing.

**A field read with no value in sight.** A field is an ordinary function, so `map rent everyone` is
the same partial question written another way, and it is refused for the same reason. There is
nothing there to narrow, so the repair is to read the field through a name you have narrowed:
`map (GIVEN x YIELD CONSIDER x WHEN Tenant name rent THEN rent OTHERWISE 0) everyone`.

**Example file:** [partial-field-example.l4](partial-field-example.l4)

### Computed Fields (Methods)

Record fields can have a `MEANS` clause that defines a derived value — computed automatically from the record's other fields. These are analogous to **methods**, **calculated properties**, or **derived attributes** in other languages.

```l4
DECLARE Employee HAS
    -- stored fields (primary attributes)
    `name`             IS A STRING
    `date of birth`    IS A NUMBER
    `current year`     IS A NUMBER
    -- computed fields (derived attributes)
    `age`              IS A NUMBER
        MEANS `current year` - `date of birth`
    `adult`            IS A BOOLEAN
        MEANS `age` >= 18
```

**Key points:**

- Computed fields are accessed with `'s` just like stored fields: `employee's `age``
- Computed fields may depend on other computed fields (chaining)
- Computed fields may call external functions using OF syntax: `MEANS `f`OF`x`, `y``
- Computed fields may use WHERE and LET/IN for local bindings
- When constructing a record with WITH, only stored fields are supplied — computed fields are derived automatically

**Referential transparency:** Computed fields are _pure_ — they may only reference sibling fields of the same record. There is no way to add a GIVEN parameter to a MEANS clause inside a DECLARE; the only input is the record itself. This is a deliberate design choice rooted in functional programming: a computed field is a total function from the record's stored state to a derived value, with no hidden dependencies on external state or arguments. In the language of the lambda calculus, each computed field is a closed term over the record's own bindings. This purity guarantee means that computed fields are referentially transparent — evaluating `employee's \`age\`` will always yield the same result for the same record, regardless of when or where it is called. It also makes cycle detection decidable: the compiler builds a dependency graph over a finite set of sibling fields and rejects any strongly connected component, ensuring termination.

**Style guide:** Group stored fields first, then computed fields, so readers see the primary data before the derived logic. Depart from this convention when expository clarity calls for a different ordering — for instance, placing a computed field immediately after the stored fields it depends on.

**Example file:** [computed-fields-example.l4](computed-fields-example.l4)

### Type Synonyms

Create an alias for an existing type:

```l4
DECLARE Age IS NUMBER
DECLARE PersonName IS STRING
```

### Opaque Types

Leave the body off entirely and you get an **opaque type**: a type that has a
name and nothing else. It has no fields, no alternatives, and no synonym body,
so nothing in your file can say what one of its values looks like.

```l4
DECLARE Applicant
DECLARE Premises
```

That is more useful than it sounds. A licensing rule usually cares that an
applicant and a premises are different kinds of thing, and that a decision
about one is never accidentally applied to the other. It does not care what
either is made of. An opaque type says exactly that much and stops.

```l4
DECLARE Applicant
DECLARE Premises

GIVEN a IS AN Applicant
      p IS A Premises
GIVETH A BOOLEAN
DECIDE `may be licensed` a p IS TRUE
```

The two types are distinct, so writing the arguments in the wrong order is a
type error, caught before anything runs. An opaque type can also be a record
field, carry an `AKA` alias, or take type parameters:

```l4
DECLARE Applicant AKA Candidate

DECLARE Application
  HAS applicant IS AN Applicant
      premises  IS A Premises

DECLARE Bag x
```

**Example file:** [opaque-example.l4](opaque-example.l4)

#### Where the values come from

An opaque type has no constructors, so no expression in your file can produce
one. Values arrive from outside: a fact declared in a
[section `GIVEN`](../syntax/section-given.md) while you are drafting, or a JSON
input at a service boundary once the rules are deployed. A rule that never
looks inside an opaque value still evaluates normally.

```l4
§ `Where the values come from`
    GIVEN `the applicant` IS AN Applicant
```

#### Limits

- **You cannot write down a value.** There is no literal, no constructor, and
  no `WITH` form for an opaque type. A directive that has to inspect one stops
  with "I could not continue evaluating, because I needed to know the value
  of ... but it is an assumed term". Rules that only pass the value along, or
  that read a record's other fields, evaluate fine.
- **The exporters carry the name, not a shape.** In a JSON schema an opaque
  type publishes as an object with no declared properties; in Decision Model
  and Notation (DMN) it produces no item definition, and a parameter of that
  type is typed `Any`. Nothing is lost relative to the older
  `ASSUME TypeName IS A TYPE` spelling, which behaved the same way, but no
  structure is gained either. If a downstream system needs the fields, declare
  a record instead.
- **`TYPICALLY` does not apply.** A default value would have to be a value of
  the type, and there are none.
- **A misspelt body keyword becomes a type parameter.** `DECLARE Bag x` and
  `DECLARE Conduct IZ STRING` are the same shape — a name followed by more
  names — so nothing in the declaration itself can tell a parameterised opaque
  head from a typo for `IS`. The second one declares an opaque `Conduct` of
  arity two. You still find out, but one step later and under a different
  name: `GIVEN c IS A Conduct` then reports "This type is given the wrong
  number of inputs. I expected 2, but I found 0." The case that reports nothing
  at all is a misspelt declaration that nothing uses. If you meant a synonym,
  check that the keyword reads `IS`.

#### The older spelling

`ASSUME TypeName IS A TYPE` declares the same thing and still works. The two
produce the same entity in the type checker, so you can migrate a file one
line at a time. `DECLARE` is the spelling to use: it puts type declarations
under one keyword, and `ASSUME` is deprecated in every one of its jobs. See
[ASSUME (deprecated)](ASSUME.md).

## Examples

**Example file:** [declare-example.l4](declare-example.l4)

### Basic Record

```l4
DECLARE Customer
  HAS
    name IS A STRING
    email IS A STRING
    balance IS A NUMBER
```

### Parameterized Types

Types can have type parameters:

```l4
GIVEN a IS A TYPE
DECLARE Box
  HAS
    contents IS AN a
```

### Field Syntax Variations

L4 supports multiple syntaxes for fields:

```l4
-- Using IS A
DECLARE Person1 HAS name IS A STRING

-- Using colon
DECLARE Person2 HAS name: STRING

-- Using colon with article
DECLARE Person3 HAS name: A STRING
```

## Related Keywords

- **[TYPE-KEYWORDS](keywords.md)** - Type-related keywords (IS, HAS, ONE OF)

## See Also

- **[Types Reference](../types/README.md)** - Complete type system documentation
