# Module 5: Functions

[Module 4](module-4-decision-logic.md) showed how to write a rule with a signature (`GIVEN` and `GIVETH`) and break it into parts with `WHERE`. This module goes further: calling functions, functions that work for any type, functions that call themselves, and functions that take other functions.

## Learning Objectives

By the end of this module, you will be able to:

- Call functions with several arguments, in the right order
- Write functions that work for values of any type
- Write recursive functions
- Use higher-order functions such as `map`, `filter` and `foldl`, with lambdas

---

The complete working example to work along: [module-5-examples.l4](module-5-examples.l4)

## Function Parameters

### Multiple Parameters

List parameters with `GIVEN`, separated by newlines or commas:

```l4
GIVEN x IS A NUMBER
      y IS A NUMBER
GIVETH A NUMBER
`the difference of` MEANS x - y
```

The order of the parameters is the order in which callers supply arguments.

### Polymorphic Functions

Use `TYPE` for functions that work with any type:

```l4
GIVEN a IS A TYPE
      x IS AN a
      y IS AN a
GIVETH AN a
`the first of` MEANS x
```

### Later: the same GIVEN, written once for a whole section

Every `GIVEN` above sits directly on one rule and lists the facts that this one rule is told about the case in front of it (its **"inputs"**). Sometimes a whole run of rules is about the same thing — three rules under one heading that each open `GIVEN alex IS A Person` — and the line is then written three times to say one thing once. When that happens, the same `GIVEN` can be lifted out and written once, indented under the section heading; every rule in the section is then told that fact without naming it again. The ordinary form taught on this page is the **"rule GIVEN"**; the one written under a heading is the **"section GIVEN"**.

The section form also decides what a published rule asks the world for: the list of facts under the heading is the list of boxes on the web form and the list of fields a caller has to send. [What a Section Needs to Know](../../tutorials/section-given/what-a-section-needs-to-know.md) works this through on a real regulation.

---

## Calling Functions

### Simple Function Calls

```l4
-- Define a function
GIVEN n IS A NUMBER
GIVETH A NUMBER
`the square of` MEANS n * n

-- Call it
#EVAL `the square of` 5        -- Result: 25
#EVAL `the square of` (3 + 2)  -- Result: 25
```

### Multi-Argument Calls

Arguments are separated by spaces, in the order of the `GIVEN` lines:

```l4
GIVEN x IS A NUMBER
      y IS A NUMBER
GIVETH A NUMBER
`the sum of x and y` MEANS x + y

#EVAL `the sum of x and y` 3 5       -- Result: 8
```

An argument that is itself a function call goes in parentheses: `` `the square of` (`the sum of x and y` 1 2) `` is `9`. Without them, `` `the square of` `the sum of x and y` 1 2 `` would pass three separate arguments to `` `the square of` ``.

---

## Recursive Functions

L4 supports recursion—functions that call themselves:

### Simple Recursion

```l4
GIVEN n IS A NUMBER
GIVETH A NUMBER
`the factorial of` MEANS
    IF n <= 1
    THEN 1
    ELSE n * `the factorial of` (n - 1)

#EVAL `the factorial of` 5  -- Result: 120
```

### List Recursion

```l4
GIVEN numbers IS A LIST OF NUMBER
GIVETH A NUMBER
`the sum of the list` MEANS
    CONSIDER numbers
    WHEN EMPTY THEN 0
    WHEN x FOLLOWED BY rest THEN x + `the sum of the list` rest

#EVAL `the sum of the list` (LIST 1, 2, 3, 4, 5)  -- Result: 15
```

The `CONSIDER` walks the list: an empty list sums to 0; otherwise add the first element to the sum of the rest.

---

## Higher-Order Functions

Functions that take or return other functions.

**Note:** You must `IMPORT prelude` to use `map`, `filter`, `all`, `any`, etc.

### Anonymous Functions (Lambdas)

Use `GIVEN ... YIELD`:

```l4
IMPORT prelude

-- Double each number: LIST 2, 4, 6
#EVAL map (GIVEN n YIELD n * 2) (LIST 1, 2, 3)

-- Keep the positive numbers: LIST 2, 4
#EVAL filter (GIVEN n YIELD n > 0) (LIST -1, 2, -3, 4)
```

Multi-parameter lambdas separate their parameters with commas: `GIVEN acc, n YIELD acc + n`.

### Folding a List into One Value

`foldl` combines a whole list into a single result, starting from an initial value:

```l4
IMPORT prelude

GIVEN numbers IS A LIST OF NUMBER
GIVETH A NUMBER
`the total of` MEANS
    foldl (GIVEN acc, n YIELD acc + n) 0 numbers

#EVAL `the total of` (LIST 1, 2, 3, 4, 5)  -- Result: 15
```

Use `foldl` (fold from the left) or `foldr` (fold from the right) from the prelude.

---

## Exercises

### Exercise 1: Simple Function

Write a function that calculates the area of a rectangle.

<details>
<summary>Solution</summary>

```l4
GIVEN `the width` IS A NUMBER
      `the height` IS A NUMBER
GIVETH A NUMBER
`the area of the rectangle` MEANS
    `the width` * `the height`

#EVAL `the area of the rectangle` 4 5
```

</details>

### Exercise 2: Recursive Function

Write a recursive function that counts the items in a list of strings.

<details>
<summary>Solution</summary>

```l4
GIVEN items IS A LIST OF STRING
GIVETH A NUMBER
`the number of items in` MEANS
    CONSIDER items
    WHEN EMPTY THEN 0
    WHEN first FOLLOWED BY rest THEN 1 + `the number of items in` rest

#EVAL `the number of items in` (LIST "deed", "lease", "will")
```

An empty list has no items; any other list has one more item than the rest of it.

</details>

### Exercise 3: Higher-Order Function

Use `filter` to get all numbers greater than 10 from a list. (Remember to `IMPORT prelude`.)

<details>
<summary>Solution</summary>

```l4
IMPORT prelude

GIVEN numbers IS A LIST OF NUMBER
GIVETH A LIST OF NUMBER
`the numbers above ten` MEANS
    filter (GIVEN n YIELD n > 10) numbers

#EVAL `the numbers above ten` (LIST 5, 15, 8, 22, 10)
```

</details>

---

## Common Mistakes

### Wrong Argument Order in Calls

```l4
-- Definition
GIVEN x IS A NUMBER
      y IS A NUMBER
GIVETH A NUMBER
`the difference of` MEANS x - y

-- Wrong: Gets 3 - 10 = -7, not 10 - 3
#EVAL `the difference of` 3 10

-- Right: Match the order in GIVEN
#EVAL `the difference of` 10 3  -- Gets 10 - 3 = 7
```

---

## Summary

| Concept              | Syntax                                     |
| -------------------- | ------------------------------------------ |
| Function definition  | `GIVEN params GIVETH Type name MEANS expr` |
| Polymorphic function | `GIVEN a IS A TYPE` before the parameters  |
| Recursion            | Function calls itself in definition        |
| Lambda               | `GIVEN x YIELD expression`                 |
| Multi-param lambda   | `GIVEN acc, x YIELD expression`            |
| Fold                 | `foldl (GIVEN acc, x YIELD ...) start xs`  |
| Function application | `` `function name` arg1 arg2 ``            |

---

Next, [Module 6: Regulative rules](module-6-regulative.md) models obligations, permissions and prohibitions: the part of L4 with no equivalent in other programming languages.
