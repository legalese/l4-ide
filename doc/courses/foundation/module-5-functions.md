# Module 5: Functions

**Prerequisites:** Modules 1–4

In this module, you'll learn how to define reusable functions in L4.

## Learning Objectives

By the end of this module, you will be able to:

- Define functions with GIVEN and GIVETH
- Use DECIDE and MEANS appropriately
- Create local definitions with WHERE
- Write recursive functions
- Understand function application

---

## Function Basics

This is the complete working example to work along.

[module-5-examples.l4](module-5-examples.l4)

### The Structure of a Function

Every L4 function has these parts:

```l4
GIVEN x IS A NUMBER           -- Parameters (inputs)
      y IS A NUMBER
GIVETH A NUMBER               -- Return type (output)
`the sum of x and y` MEANS    -- Name and definition
    x + y
```

### DECIDE vs MEANS

Both define the same thing—use whichever reads better:

```l4
-- These are equivalent
DECIDE `the person is an adult` IF age >= 18
`the person is an adult` MEANS age >= 18
DECIDE `the person is an adult` IS age >= 18
```

| Syntax                | Best for                     |
| --------------------- | ---------------------------- |
| `DECIDE name IS expr` | Rules, decisions, conditions |
| `DECIDE name IF expr` | Boolean predicates           |
| `name MEANS expr`     | Definitions, computations    |

### Type Signatures

The `GIVETH` clause declares what type the function returns:

- `GIVETH A NUMBER` — Returns a number
- `GIVETH A STRING` — Returns a string
- `GIVETH A BOOLEAN` — Returns true/false
- `GIVETH A Person` — Returns a Person record
- `GIVETH A LIST OF NUMBER` — Returns a list of numbers
- `GIVETH A MAYBE NUMBER` — Returns a number or nothing

---

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

```l4
-- Arguments separated by spaces
#EVAL `the sum of x and y` 3 5       -- Result: 8
```

---

## Local Definitions with WHERE

Use `WHERE` to define helper values and functions. (`EXPONENT base power` is L4's built-in exponentiation function.)

```l4
GIVEN `the principal` IS A NUMBER
      `the annual rate` IS A NUMBER
      `the years` IS A NUMBER
GIVETH A NUMBER
`the compound interest` MEANS
    `the principal` * EXPONENT `the growth factor` `the years`
    WHERE
        `the growth factor` MEANS 1 + `the annual rate`
```

### Multiple Local Definitions

```l4
GIVEN `the loan amount` IS A NUMBER
      `the annual rate` IS A NUMBER
      `the term in months` IS A NUMBER
GIVETH A NUMBER
`the monthly payment` MEANS
    `the loan amount` *
    (`the monthly rate` * `the compound factor`) /
    (`the compound factor` - 1)
    WHERE
        `the monthly rate` MEANS `the annual rate` / 12
        `the compound factor` MEANS EXPONENT (1 + `the monthly rate`) `the term in months`
```

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
-- Double each number
map (GIVEN n YIELD n * 2) (LIST 1, 2, 3)
-- Result: LIST 2, 4, 6

-- Filter positive numbers
filter (GIVEN n YIELD n > 0) (LIST -1, 2, -3, 4)
-- Result: LIST 2, 4
```

Multi-parameter lambdas separate their parameters with commas: `GIVEN acc, n YIELD acc + n`.

### Folding a List into One Value

`foldl` combines a whole list into a single result, starting from an initial value:

```l4
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

### Exercise 2: Function with WHERE

Write a function that calculates the area of a circle using π ≈ 3.14159.

<details>
<summary>Solution</summary>

```l4
GIVEN `the radius` IS A NUMBER
GIVETH A NUMBER
`the area of the circle` MEANS
    pi * `the radius` * `the radius`
    WHERE
        pi MEANS 3.14159

#EVAL `the area of the circle` 10
```

</details>

### Exercise 3: Recursive Function

Write a recursive function to calculate the sum of a list of numbers.

<details>
<summary>Solution</summary>

```l4
GIVEN numbers IS A LIST OF NUMBER
GIVETH A NUMBER
`the sum of the list` MEANS
    CONSIDER numbers
    WHEN EMPTY THEN 0
    WHEN x FOLLOWED BY rest THEN x + `the sum of the list` rest

#EVAL `the sum of the list` (LIST 1, 2, 3, 4, 5)
```

</details>

### Exercise 4: Higher-Order Function

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

### 1. Missing Return Type

```l4
-- ❌ Wrong: No GIVETH
GIVEN n IS A NUMBER
`the square of` MEANS n * n

-- ✅ Right: Include GIVETH
GIVEN n IS A NUMBER
GIVETH A NUMBER
`the square of` MEANS n * n
```

### 2. Wrong Argument Order in Calls

```l4
-- Definition
GIVEN x IS A NUMBER
      y IS A NUMBER
GIVETH A NUMBER
`the difference of` MEANS x - y

-- ❌ Wrong: Gets 3 - 10 = -7, not 10 - 3
#EVAL `the difference of` 3 10

-- ✅ Right: Match the order in GIVEN
#EVAL `the difference of` 10 3  -- Gets 10 - 3 = 7
```

### 3. Missing Parentheses in Function Calls

```l4
-- ❌ Wrong: f applied to g, not to result of g x
f g x

-- ✅ Right: Apply g to x, then f to result
f (g x)
```

---

## Summary

| Concept              | Syntax                                     |
| -------------------- | ------------------------------------------ |
| Function definition  | `GIVEN params GIVETH Type name MEANS expr` |
| Decision function    | `DECIDE name IF condition`                 |
| Local definitions    | `expr WHERE helper MEANS value`            |
| Recursion            | Function calls itself in definition        |
| Lambda               | `GIVEN x YIELD expression`                 |
| Multi-param lambda   | `GIVEN acc, x YIELD expression`            |
| Fold                 | `foldl (GIVEN acc, x YIELD ...) start xs`  |
| Function application | `` `function name` arg1 arg2 ``            |

---

## What's Next?

In [Module 6: Regulative Rules](module-6-regulative.md), you'll learn how to model legal obligations, permissions, and prohibitions using L4's deontic constructs.
