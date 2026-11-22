# DECLARE

`DECLARE` introduces a new type: a record, an enumeration, a synonym for another type, or an **opaque type**, a type that is named but not described.

## Syntax

```text
DECLARE Name HAS field1 IS A Type1, field2 IS A Type2
DECLARE Name IS ONE OF Value1, Value2, Value3
DECLARE Name IS A Type
DECLARE Name OF a, b HAS ...
DECLARE Name
```

**Example files:** [declare-example.l4](declare-example.l4), [record-example.l4](record-example.l4), [enum-example.l4](enum-example.l4), [opaque-example.l4](opaque-example.l4)

## Records

A record has named fields. Write them after `HAS`, one per line or separated by commas:

```l4
DECLARE Person
  HAS
    name IS A STRING
    age IS A NUMBER

DECLARE Point HAS x IS A NUMBER, y IS A NUMBER
```

A field can also be written `name: STRING` or `name: A STRING`.

**Making a record.** Give every field by name with `WITH`, or give the values in the order the fields are declared, with `OF` and commas or with spaces:

```l4
DECLARE Person HAS
  name IS A STRING
  age IS A NUMBER

`the buyer` MEANS Person WITH name IS "Kim", age IS 30
`the seller` MEANS Person OF "Lee", 45
`the agent` MEANS Person "Jo" 28

#EVAL `the buyer`'s age
```

**Reading a field.** Use the genitive `'s`: `` `the buyer`'s age ``. See [Syntax and directives: Genitive](../syntax/README.md#genitive).

## Computed fields

A field followed by `MEANS` is computed from the record's other fields. It is read with `'s` like any other field, and it is not given when the record is made.

```l4
DECLARE Employee HAS
    `name`          IS A STRING
    `year of birth` IS A NUMBER
    `current year`  IS A NUMBER
    `age`           IS A NUMBER
        MEANS `current year` - `year of birth`
    `adult`         IS A BOOLEAN
        MEANS `age` >= 18

`the employee` MEANS Employee WITH
    `name`          IS "Lim"
    `year of birth` IS 1990
    `current year`  IS 2026

#EVAL `the employee`'s `adult`
```

- The body can use the record's other fields by name, including other computed fields, and call functions defined elsewhere.
- It can use `WHERE` and `LET … IN`.
- It takes no inputs of its own: there is no `GIVEN` for a computed field. Its only input is the record.
- Computed fields that depend on each other in a cycle are an error ("Circular dependency detected between computed fields").

Putting the stored fields first and the computed fields after them makes a declaration easier to read.

**Example file:** [computed-fields-example.l4](computed-fields-example.l4)

## Enumerations

`IS ONE OF` lists the values a type can have:

```l4
DECLARE Colour IS ONE OF Red, Green, Blue
```

A value can carry fields of its own:

```l4
DECLARE Shape IS ONE OF
  Circle HAS radius IS A NUMBER
  Rectangle HAS width IS A NUMBER, height IS A NUMBER
  Point

`the plot` MEANS Rectangle WITH width IS 20, height IS 30
`the pond` MEANS Circle 4
```

Use [CONSIDER](../control-flow/CONSIDER.md) to tell the values apart.

## Type synonyms

`DECLARE Name IS Type` gives another name to an existing type. The two names are the same type.

```l4
DECLARE Age IS A NUMBER

GIVEN age IS AN Age
GIVETH A BOOLEAN
`is an adult` age MEANS age >= 18
```

- A synonym can take type parameters: `DECLARE Optional OF a IS A MAYBE a`.
- A synonym cannot refer to itself, directly or through other synonyms, because a type like that could never be written out in full. L4 reports it as a circular dependency between the synonyms, and sets aside what they stand for rather than following them round and round.
- L4 follows a chain of synonyms for at most 1000 steps. For a longer chain, declare the first synonym as the type the chain ends in.

```l4
-- Not allowed: each is defined as the other
DECLARE Ping IS A Pong
DECLARE Pong IS A Ping
```

The names a synonym is known by after `AKA` count as names for that synonym.
In `DECLARE W AKA B IS A B` the `B` has no arguments after it, so it is `W` itself and not some other synonym called `B` that takes one (`DECLARE B a IS A LIST OF a`); that declaration is circular too.
`B OF NUMBER` would be the one that takes an argument.
Two synonyms, or a synonym and a record, may share a name when they take different numbers of arguments, and a use is read as the one that takes as many as it is given.
A synonym that names itself by its section-qualified name (`` `One`.L1 `` inside `§ One`) is circular in the same way.

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

## Opaque types

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

### Where the values come from

An opaque type has no constructors, so no expression in your file can produce
one. Values arrive from outside: a fact declared in a
[section `GIVEN`](../syntax/section-given.md) while you are drafting, or a JSON
input at a service boundary once the rules are deployed. A rule that never
looks inside an opaque value still evaluates normally.

```l4
§ `Where the values come from`
    GIVEN `the applicant` IS AN Applicant
```

### Limits of opaque types

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
  `DECLARE Conduct IZ STRING` are the same shape (a name followed by more
  names), so nothing in the declaration itself can tell a parameterised opaque
  head from a typo for `IS`. The second one declares an opaque `Conduct` of
  arity two. You still find out, but one step later and under a different
  name: `GIVEN c IS A Conduct` then reports "This type is given the wrong
  number of inputs. I expected 2, but I found 0." The case that reports nothing
  at all is a misspelt declaration that nothing uses. If you meant a synonym,
  check that the keyword reads `IS`.

### In the editor

When you use a type name that nothing declares, the editor flags it with "I could not find a definition for the identifier".
Click the lightbulb on that error (or run the "Quick Fix" command) and choose "Declare `Widget` as a type".
It adds `DECLARE Widget` on its own line directly above the declaration that uses the name, which makes `Widget` an opaque type like the ones above.
The new line goes above any `@desc`, `@nlg` or other annotation on that declaration, so each annotation stays with the declaration it describes.
It also goes above any comment lines directly over the declaration or its annotations, since those read as part of it; a comment with a blank line under it stays where it is.
When the name is used in a section's own `GIVEN`, the line goes above the section's `§` heading instead, where the whole section can see it.
If the use gives the type arguments, as in `Box OF NUMBER`, the declaration gets one parameter for each: `DECLARE Box a`.
The fix declares an opaque type and nothing more; if you meant a record or a list of alternatives, add the `HAS` or `IS ONE OF` part yourself.

### The older spelling

`ASSUME TypeName IS A TYPE` declares the same thing and still works. The two
produce the same entity in the type checker, so you can migrate a file one
line at a time. `DECLARE` is the spelling to use: it puts type declarations
under one keyword, and `ASSUME` is deprecated in every one of its jobs. See
[ASSUME (deprecated)](ASSUME.md).

## Parameterised types

A type can take type parameters, so that the same declaration works for numbers, text or any other type.
Write the parameters after the name, with `OF` and commas, or declare them with `GIVEN … IS A TYPE` above the `DECLARE`:

```l4
DECLARE Box OF a HAS contents IS AN a

GIVEN a IS A TYPE
      b IS A TYPE
DECLARE `Pair of values` HAS first IS AN a, second IS A b

GIVETH A Box OF NUMBER
`a box of 42` MEANS Box WITH contents IS 42
```

The parameter can also follow the name without `OF` (`DECLARE Box a HAS …`).
A use of the type gives the parameters with `OF`: `Box OF NUMBER`, `` `Pair of values` OF NUMBER, STRING ``.

## A and AN

`A` and `AN` before a type are for readability only. They are interchangeable and can be left out: `IS A NUMBER`, `IS AN Account` and `IS NUMBER` mean the same.

```l4
DECLARE Account HAS balance IS A NUMBER

GIVEN account IS AN Account
GIVETH NUMBER
`balance of` account MEANS account's balance
```

The same articles read the same way on the facts a section takes in:

```l4
§ `Applicant`
    GIVEN age IS A NUMBER
          name IS A STRING
          account IS AN Account
```

A rule is told some facts about the case in front of it (its **"inputs"**).
A fact supplied afresh for each case goes in a [`GIVEN` under its section's heading](../syntax/section-given.md), a **"section `GIVEN`"**, where the articles read exactly the same way.
Older files spell the same declaration `ASSUME name IS A Type`; that keyword is deprecated (ruled 2026-09-04) and still works.

## Type expressions

Wherever a type is expected (after `IS A`, `GIVETH`, in a field):

| Type expression                          | Meaning                                    |
| ---------------------------------------- | ------------------------------------------ |
| `NUMBER`, `STRING`, `BOOLEAN`, `DATE`    | a built-in type ([Types](README.md))       |
| `LIST OF Type`                           | a list                                     |
| `MAYBE Type`                             | a value that may be missing                |
| `EITHER Type1 Type2`                     | one of two types                           |
| `Name OF Type1, Type2`                   | a parameterised type, given its parameters |
| `FUNCTION FROM Type1 AND Type2 TO Type3` | a function                                 |
| `TYPE`                                   | a type parameter                           |

The same spellings declare the inputs of a section:

```l4
§ `Facts about the case`
    GIVEN x IS A NUMBER
          f IS A FUNCTION FROM NUMBER TO NUMBER
          g IS A FUNCTION FROM NUMBER AND STRING TO BOOLEAN
```

## Related pages

- [Types](README.md): built-in types
- [ASSUME (deprecated)](ASSUME.md): the older spelling of an input or an opaque type, and what to write instead
- [FOR ALL](for-all.md): type variables in the type of a function the section takes in
- [AKA](../functions/AKA.md): other names for a type
