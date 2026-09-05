# NOT

Logical negation operator. Inverts a boolean value.

## Syntax

```l4
NOT expression
```

## Purpose

NOT turns TRUE into FALSE and vice versa. In legal rules it typically encodes negative requirements ("has no criminal record", "is not disqualified") and pairs with AND/OR to express exceptions.

## Truth Table

| A     | NOT A |
| ----- | ----- |
| TRUE  | FALSE |
| FALSE | TRUE  |

## Examples

**Example file:** [not-example.l4](not-example.l4)

### Basic Negation

```l4
§ `Basic negation`
    GIVEN hasCriminalRecord IS A BOOLEAN

DECIDE isClean IS NOT hasCriminalRecord
```

### Combined with AND

```l4
§ `Combined with AND`
    GIVEN personAge IS A NUMBER
          isBlocked IS A BOOLEAN

DECIDE canAccess IS personAge >= 18 AND NOT isBlocked
```

### How Far Does NOT Reach?

This is the one thing to know about NOT, and it catches almost everybody the first time.

NOT does not simply flip the next word. It **reaches forward** and takes everything that follows it on the same line — not just the next word, but any AND, OR, IMPLIES, or comparison that comes after it:

```l4
GIVEN a IS A BOOLEAN, b IS A BOOLEAN

-- These two say exactly the same thing.
-- Both of them mean: NOT applied to the whole of (a AND b).
reachesOver a b MEANS NOT a AND b
spelledOut  a b MEANS NOT (a AND b)
```

Read the first one aloud and most people hear _"not-a, and b"_. That is **not** what it says. The NOT swallowed the AND along with everything after it.

#### What stops it: where the words sit

On a single line, nothing stops it — it runs to the end.

When a rule is spread over several lines, what decides is **the column each word starts in**. Compare these two, which differ only in how far the second line is indented:

```l4
GIVEN a IS A BOOLEAN, b IS A BOOLEAN

-- AND starts to the RIGHT of NOT, so the NOT reaches over it.
-- This means: NOT (a AND b)
swallowed a b MEANS
    NOT a
        AND b

-- AND starts in the SAME column as NOT, so the NOT stops before it.
-- This means: (NOT a) AND b
stopped a b MEANS
    NOT a
    AND b
```

The rule, in full:

> A word like AND, OR or IMPLIES **stops** the NOT when it begins at the same column as the NOT, or further left. It is **swallowed** when it begins further right. On one line, everything after the NOT is further right, so everything is swallowed.

Where the words sit on the page is what decides. There is no separate ranking that overrides it.

All of it in one place, with `a` and `b` both FALSE so that the two readings give different answers:

| what you write                       | what it means   | answer  |
| ------------------------------------ | --------------- | ------- |
| `NOT a AND b` (one line)             | `NOT (a AND b)` | `TRUE`  |
| `NOT (a) AND b` (one line)           | `NOT (a AND b)` | `TRUE`  |
| `(NOT a) AND b`                      | `(NOT a) AND b` | `FALSE` |
| `NOT a` / `AND b` further right      | `NOT (a AND b)` | `TRUE`  |
| `NOT a` / `AND b` in the same column | `(NOT a) AND b` | `FALSE` |
| `NOT a` / `AND b` further left       | `(NOT a) AND b` | `FALSE` |

One space is enough. An AND indented a single character past the NOT is already swallowed; it has to line up with the NOT exactly, or start left of it, to stop the reach.

#### Brackets around what you are negating do not help

The obvious defence is to put brackets around the thing being negated. It does not work. The closing bracket is not what ends the NOT's reach, so the NOT simply carries on past it:

```l4
GIVEN a IS A BOOLEAN, b IS A BOOLEAN

-- STILL means NOT (a AND b), despite the brackets
looksCareful a b MEANS NOT (a) AND b

-- This is the form that works: the bracket closes around the NOT itself
actuallySafe a b MEANS (NOT a) AND b
```

**Put the bracket around the NOT, not around what it negates.** This is the single most useful thing on this page.

### Negating Comparisons

Because NOT reaches over comparisons too, these two say the same thing:

```l4
GIVEN n IS A NUMBER
isNotZero      n MEANS NOT (n EQUALS 0)
alsoIsNotZero  n MEANS NOT n EQUALS 0
```

Write the brackets anyway. They cost nothing, and they tell the next reader what you meant rather than making them work out the reach.

## Pitfalls

- **NOT reaches further than it looks.** On one line, `NOT a AND b` means `NOT (a AND b)` — the whole conjunction — and **not** `(NOT a) AND b`. See [How Far Does NOT Reach?](#how-far-does-not-reach) above. Nothing warns you: the rule still passes every check and simply returns the wrong answer.
- **Bracketing the operand does not fix it.** `NOT (a) AND b` is exactly as wide as `NOT a AND b`. Only `(NOT a) AND b` gives you the narrow reading.
- **`NOT` at the end of a line is always safe.** If nothing follows the NOT's operand, there is nothing for it to swallow. `x AND NOT y` on one line is fine, because the NOT is last.
- **Prefer UNLESS for exceptions.** `p AND NOT q` can be written `p UNLESS q`, which often reads closer to the legal source text — and sidesteps the reach question entirely.

The repository ships a checker for the same-line form:

```
node etc/check-not-precedence.mjs --dir <directory>
```

It runs on every pull request. It reads one line at a time, so a clean run is reassurance rather than proof — bracket the NOT anyway.

## Related Keywords

- **[AND](AND.md)** - Logical conjunction
- **[OR](OR.md)** - Logical disjunction
- **[IMPLIES](IMPLIES.md)** - Logical implication
- **[UNLESS](UNLESS.md)** - Exception clause (`AND NOT`)

## See Also

- **[Logical Operators](../operators/README.md#logical-operators)** - All logical operators
