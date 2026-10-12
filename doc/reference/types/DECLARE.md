# DECLARE

Declares a new type in L4. Types can be records (product types), enums (sum types), or type synonyms.

## Syntax

```l4
DECLARE TypeName IS ...
DECLARE TypeName HAS ...
DECLARE TypeName IS ONE OF ...
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

**A synonym may not refer to itself**, either directly or through other synonyms, because a type like that could never be written out in full.
L4 reports it as a circular dependency between the synonyms, and sets aside what they stand for rather than following them round and round.

```l4
-- Not allowed: each is defined as the other
DECLARE Ping IS A Pong
DECLARE Pong IS A Ping
```

The names a synonym is known by after `AKA` count as names for that synonym.
In `DECLARE W AKA B IS A B` the `B` has no arguments after it, so it is `W` itself and not some other synonym called `B` that takes one (`DECLARE B a IS A LIST OF a`); that declaration is circular too.
`B OF NUMBER` would be the one that takes an argument.

**There is a limit to how long a chain can be.**
To compare two types, L4 replaces a synonym by the type it stands for, and then does the same to that type if it is a synonym, and so on.
It stops after 1000 replacements in a row.
A chain of 1200 synonyms, each defined as the one before, is longer than that, and the error names the synonym where L4 stopped:

```text
I stopped following type synonyms at `S200`.

To compare two types I replace a type synonym by the type it stands for,
and I give up after 1000 replacements in a row. Here a chain of synonyms,
each defined as the next, is longer than that.

The types were not found to differ. Declare the first synonym in the chain
as the type it finally stands for, to shorten the chain.
```

The message does not say the two types differ, because L4 has not found out whether they do.
Chains anywhere near that long are rare; the usual remedy is to declare the first synonym in the chain as the type the chain ends in.

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
