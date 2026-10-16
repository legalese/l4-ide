# FOR ALL

`FOR ALL` introduces type variables in a type, so that an `ASSUME` can declare a value or function that works for any type.

## Syntax

```text
FOR ALL a
FOR ALL a AND b
FOR ALL a AND b AND c
```

`FOR ALL` comes first in the type, followed by the type that uses the variables.

**Example file:** [for-all-example.l4](for-all-example.l4)

## Examples

### One type variable

```l4
ASSUME identity IS
  FOR ALL a
  A FUNCTION FROM a TO a
```

`identity` takes a value of any type and returns a value of the same type.

### Several type variables

```l4
ASSUME map IS
  FOR ALL a AND b
  A FUNCTION
    FROM      FUNCTION FROM a TO b
          AND LIST OF a
    TO    LIST OF b
```

For all types `a` and `b`, `map` takes a function from `a` to `b` and a list of `a`, and returns a list of `b`.

### With a parameterised type

```l4
DECLARE Choice OF a, b
  IS ONE OF
    Left  HAS payload IS AN a
    Right HAS payload IS A  b

ASSUME choose IS
  FOR ALL a AND b AND c
  A FUNCTION
    FROM      FUNCTION FROM a TO c
          AND FUNCTION FROM b TO c
          AND Choice OF a, b
    TO    c
```

## FOR ALL and GIVEN

`FOR ALL` declares a polymorphic type with no definition, in an `ASSUME`.
A function that is defined gets its type variables from `GIVEN … IS A TYPE` instead:

```l4
GIVEN a IS A TYPE
      b IS A TYPE
      f IS A FUNCTION FROM a TO b
      list IS A LIST OF a
GIVETH A LIST OF b
`apply to each` f list MEANS
  CONSIDER list
  WHEN EMPTY THEN EMPTY
  WHEN x FOLLOWED BY xs THEN f x FOLLOWED BY `apply to each` f xs
```

Both give the function the same type.

## Type variables

- They are usually single lowercase letters (`a`, `b`, `c`), but any identifier works.
- They are in scope only in the type that follows.
- The names in one `FOR ALL` must be distinct: `FOR ALL a AND a` is an error.

## Not a quantifier over lists

`FOR ALL` works on types, not on values. To test every element of a list, or some element, use `all` or `any` from the [prelude](../libraries/prelude.md) with a [YIELD](../functions/YIELD.md) function:

```l4
IMPORT prelude

GIVEN amounts IS A LIST OF NUMBER
GIVETH A BOOLEAN
`every amount is positive` amounts MEANS all (GIVEN x YIELD x > 0) amounts
```

## In other languages

| L4                | Haskell       | TypeScript | Java     |
| ----------------- | ------------- | ---------- | -------- |
| `FOR ALL a`       | `forall a.`   | `<T>`      | `<T>`    |
| `FOR ALL a AND b` | `forall a b.` | `<T, U>`   | `<T, U>` |

## Related pages

- [GIVEN and GIVETH](../functions/GIVEN.md#type-parameters): type parameters of a defined function
- [ASSUME](ASSUME.md): declare a name without a definition
- [DECLARE: Type expressions](DECLARE.md#type-expressions): `FUNCTION FROM … TO …` and `TYPE`
- [prelude](../libraries/prelude.md): polymorphic standard functions
