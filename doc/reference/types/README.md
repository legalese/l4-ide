# Types

Every value in L4 has a type, and the type checker makes sure each rule is given and returns values of the right types.
L4 has a few built-in types, and `DECLARE` makes new ones: records, enumerations and synonyms.
Types are usually inferred, but writing them in `GIVEN` and `GIVETH` makes rules easier to read.

## Pages

- [DECLARE](DECLARE.md): records, enumerations, type synonyms, parameterised types, `A`/`AN` and type expressions
- [ASSUME](ASSUME.md): a name with a type and no definition
- [FOR ALL](for-all.md): type variables in the type of an `ASSUME`
- [Coercions](coercions.md): converting between types (`TOSTRING`, `TONUMBER`, `TODATE`, `AS STRING` and others)

## Built-in types

| Type       | Values                                                                                                       |
| ---------- | ------------------------------------------------------------------------------------------------------------ |
| `NUMBER`   | exact numbers, whole or fractional: `42`, `-17`, `3.14`, `5.4%` (= `0.054`), `100_000`                       |
| `STRING`   | text in double quotes: `"Hello"`; `\"`, `\\` and `\n` are escapes                                            |
| `BOOLEAN`  | `TRUE` and `FALSE`                                                                                           |
| `DATE`     | a calendar date, made with `Date 15 1 2025` from [daydate](../libraries/daydate.md), or parsed with `TODATE` |
| `TIME`     | a time of day, without a date or time zone; see [time](../libraries/time.md)                                 |
| `DATETIME` | a point in time with a time zone; see [datetime](../libraries/datetime.md)                                   |

- Arithmetic on `NUMBER` is exact: `10 / 4` is `2.5`, not a rounded value.
- In a number, underscores between digits are ignored: `100_000` is `100000`. A number must start with a digit and must not end with an underscore.
- `TRUE` and `FALSE` are written in capitals.

## Lists, optional values and choices

These built-in types take another type as a parameter.

| Type         | Values                                                        | Example file                           |
| ------------ | ------------------------------------------------------------- | -------------------------------------- |
| `LIST OF a`  | `LIST 1, 2, 3`, `EMPTY`, `1 FOLLOWED BY EMPTY`                | [list-example.l4](list-example.l4)     |
| `MAYBE a`    | `JUST 42` when there is a value, `NOTHING` when there is none | [maybe-example.l4](maybe-example.l4)   |
| `EITHER a b` | `LEFT "error"` or `RIGHT 42`                                  | [either-example.l4](either-example.l4) |

L4 has no null: a value that may be missing has a `MAYBE` type, and [CONSIDER](../control-flow/CONSIDER.md) handles both cases.
Functions on these types, and the `PAIR` and `Dictionary` types, are in the [prelude](../libraries/prelude.md).

## Events and regulative rules

These built-in types take the type of the parties and the type of the actions as their two parameters.

| Type                   | Values                                                                                                                           |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `DEONTIC party action` | a regulative rule: an obligation, permission or prohibition, or `FULFILLED` or `BREACH`; see [DEONTIC](../regulative/DEONTIC.md) |
| `EVENT party action`   | that a party did an action at a time (a `NUMBER`): `EVENT Seller delivery 2`; see [EVENT](../regulative/EVENT.md)                |

A rule marked `@export` cannot take either as an input; see [DEONTIC](../regulative/DEONTIC.md#an-exported-rule-cannot-take-a-deontic-input) and [EVENT](../regulative/EVENT.md#an-exported-rule-cannot-take-an-event).

## Records and enumerations

A record has named fields; an enumeration has a fixed list of values, each of which can carry fields. Both are made with [DECLARE](DECLARE.md).
Examples: [record-example.l4](record-example.l4), [enum-example.l4](enum-example.l4).

## Functions

A function is a value too. Its type is written `FUNCTION FROM Type1 AND Type2 TO Result`, so a function can be an input of another function.
Example: [function-type-example.l4](function-type-example.l4).

## Type parameters and inference

A function or a type can work for any type, with a type parameter (`GIVEN a IS A TYPE`; see [GIVEN and GIVETH](../functions/GIVEN.md#type-parameters)).
Example: [polymorphic-example.l4](polymorphic-example.l4).

When `GIVETH` or an input's type is left out, L4 infers it.
Example: [type-inference-example.l4](type-inference-example.l4).

## Comparison with other languages

| L4                    | Haskell              | Other languages           |
| --------------------- | -------------------- | ------------------------- |
| `DECLARE T HAS ...`   | `data T = T { ... }` | struct, class, record     |
| `DECLARE T IS ONE OF` | `data T = A \| B`    | enum, union, sealed class |
| `GIVEN … GIVETH`      | `a -> b`             | function signature        |
| `MAYBE T`             | `Maybe T`            | Optional, nullable        |
| `LIST OF T`           | `[T]`                | array, list               |
| `CONSIDER`            | `case … of`          | switch, match             |
| `BRANCH`              | guards               | if-else-if chain          |
| `WHERE`, `LET … IN`   | `where`, `let … in`  | local variables           |
| `'s`                  | record field         | `.field`                  |

How the type system works, formally: [Type theory](../../concepts/type-system/type-theory.md). Why types matter for legal rules: [Types as legal categories](../../concepts/type-system/algebraic-types.md).
