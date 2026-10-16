# DECLARE

`DECLARE` introduces a new type: a record, an enumeration, or a synonym for another type.

## Syntax

```text
DECLARE Name HAS field1 IS A Type1, field2 IS A Type2
DECLARE Name IS ONE OF Value1, Value2, Value3
DECLARE Name IS A Type
DECLARE Name OF a, b HAS ...
```

**Example files:** [declare-example.l4](declare-example.l4), [record-example.l4](record-example.l4), [enum-example.l4](enum-example.l4)

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
- A synonym cannot refer to itself, directly or through other synonyms; L4 reports a circular dependency between them.
- L4 follows a chain of synonyms for at most 1000 steps. For a longer chain, declare the first synonym as the type the chain ends in.

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

## Related pages

- [Types](README.md): built-in types
- [ASSUME](ASSUME.md): a name with a type and no definition
- [FOR ALL](for-all.md): polymorphic types for `ASSUME`
- [AKA](../functions/AKA.md): other names for a type
