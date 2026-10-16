# GIVEN and GIVETH

`GIVEN` declares the inputs of a function, each with a name and a type.
`GIVETH` declares the type of its result.
Both go on the lines above the definition.

## Syntax

```text
GIVEN name IS A Type
GIVEN name1 IS A Type1, name2 IS A Type2
GIVEN name1 IS A Type1
      name2 IS A Type2
GIVETH A Type
```

A function has one `GIVEN`. Further inputs go on the same line, separated by commas, or on the lines below, lined up under the first name.
A second `GIVEN` line directly below the first is a syntax error.

**Example files:** [given-example.l4](given-example.l4), [giveth-example.l4](giveth-example.l4)

## GIVEN

```l4
GIVEN amount IS A NUMBER
      `days overdue` IS A NUMBER
GIVETH A NUMBER
`late fee` amount `days overdue` MEANS
  IF `days overdue` > 30 THEN amount TIMES 0.05 ELSE 0
```

The names after the function name are the `GIVEN` inputs in order; they may be left out of the definition, but if they are written they must match.
`A` and `AN` are interchangeable (`IS AN Invoice`); see [DECLARE](../types/DECLARE.md#a-and-an).

### Calling with named inputs

A call gives the inputs in the order of the `GIVEN`, or by name with `WITH`:

```l4
GIVEN amount IS A NUMBER
      `days overdue` IS A NUMBER
GIVETH A NUMBER
`late fee` amount `days overdue` MEANS
  IF `days overdue` > 30 THEN amount TIMES 0.05 ELSE 0

#EVAL `late fee` 1000 45
#EVAL `late fee` WITH amount IS 1000, `days overdue` IS 45
#ASSERT (`late fee` WITH `days overdue` IS 10, amount IS 1000) EQUALS 0
```

With `WITH`, the inputs can be given in any order. Put the call in parentheses when an operator follows it, as in the `#ASSERT`. This works only for a function with a `GIVEN`; a value declared with [ASSUME](../types/ASSUME.md) cannot be given a value this way.

### Type parameters

An input of type `TYPE` makes the function work for any type:

```l4
GIVEN a IS A TYPE
      xs IS A LIST OF a
GIVETH A NUMBER
`number of items in` xs MEANS
  CONSIDER xs
  WHEN EMPTY THEN 0
  WHEN first FOLLOWED BY rest THEN 1 PLUS `number of items in` rest
```

A type parameter is not passed when the function is called: `` `number of items in` (LIST 1, 2, 3) `` gives `3`.
[FOR ALL](../types/for-all.md) writes the same kind of type for an `ASSUME`.

### Descriptions of inputs

`@desc` after an input describes it. The description is shown when the function is deployed with `@export`:

```l4
@export Calculate the late fee for an overdue invoice
GIVEN amount IS A NUMBER @desc The invoice amount
      `days overdue` IS A NUMBER @desc How many days past the due date
GIVETH A NUMBER
`late fee` amount `days overdue` MEANS
  IF `days overdue` > 30 THEN amount TIMES 0.05 ELSE 0
```

### Anonymous functions

`GIVEN … YIELD` makes a function without a name; see [YIELD](YIELD.md).

## GIVETH

`GIVETH` names the type of the result. `GIVES` is a synonym, and the article is optional (`GIVETH NUMBER`).

```l4
GIVEN xs IS A LIST OF NUMBER
GIVETH A MAYBE NUMBER
`the first of` xs MEANS
  CONSIDER xs
  WHEN EMPTY THEN NOTHING
  WHEN first FOLLOWED BY rest THEN JUST first
```

`GIVETH` is optional: without it, L4 infers the result type.
Writing it makes the rule easier to read and lets the type checker report a body that gives the wrong type.

A rule that returns obligations has the result type `DEONTIC Party Action`; see [DEONTIC](../regulative/DEONTIC.md).

## Related pages

- [DECIDE](DECIDE.md): the definition that follows `GIVEN` and `GIVETH`
- [Types and data](../types/README.md): the types an input or result can have
- [ASSUME](../types/ASSUME.md): a name with a type and no definition
