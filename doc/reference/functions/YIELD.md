# YIELD

`GIVEN … YIELD` makes a function without a name (a lambda). It is mostly used to pass a small function to another function, such as `all`, `any`, `map` or `filter` from the [prelude](../libraries/prelude.md).

## Syntax

```text
GIVEN name YIELD expression
GIVEN name1, name2 YIELD expression
GIVEN name IS A Type YIELD expression
GIVEN name1
      name2
YIELD expression
```

The types of the inputs can be left out when L4 can infer them.

**Example file:** [yield-example.l4](yield-example.l4)

## Examples

```l4
IMPORT prelude

GIVEN amounts IS A LIST OF NUMBER
GIVETH A BOOLEAN
`all positive` amounts MEANS all (GIVEN n YIELD n > 0) amounts

GIVEN amounts IS A LIST OF NUMBER
GIVETH A LIST OF NUMBER
`doubled` amounts MEANS map (GIVEN n YIELD n * 2) amounts
```

A lambda can also be the body of a named definition. These two define the same function:

```l4
GIVEN n IS A NUMBER
GIVETH A NUMBER
`double` n MEANS n * 2

DECIDE `double as a lambda` IS GIVEN n YIELD n * 2
```

## Parentheses

When a lambda is passed to a function, put it in parentheses.
An argument that uses `'s` needs parentheses too:

```l4
IMPORT prelude

DECLARE Person HAS
  name IS A STRING
  age IS A NUMBER
DECLARE Household HAS
  members IS A LIST OF Person

GIVEN household IS A Household
GIVETH A BOOLEAN
`all adults` household MEANS all (GIVEN p YIELD p's age >= 18) (household's members)
```

Without the parentheses, `all (GIVEN p YIELD p's age >= 18) household's members` is a syntax error.

## Related pages

- [GIVEN and GIVETH](GIVEN.md): inputs of a named function
- [MEANS](MEANS.md): named definitions
- [prelude](../libraries/prelude.md): `all`, `any`, `map`, `filter` and other functions that take a function
