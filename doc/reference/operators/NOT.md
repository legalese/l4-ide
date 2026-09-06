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

NOT does not simply flip the next word. It **reaches forward** and takes everything that follows it on the same line — not just the next word, but any AND, OR, IMPLIES, or comparison that comes after it. So a line like

```
NOT a AND b
```

would mean `NOT (a AND b)`: the whole of "a and b", negated. Read it aloud and most people hear _"not-a, and b"_, which is a different rule, and the two disagree whenever `a` is FALSE.

Because that misreading is so easy, **L4 refuses the spelling.** A NOT followed on the same line by an AND, OR or IMPLIES is an error, and the message spells out both readings so that you can say which one you meant:

```
On one line, NOT reaches to the end of the line, so this reads as

  NOT (a AND b)

If that is the meaning, write those brackets in. If only

  a

is negated, put the brackets around the NOT and that alone:

  (NOT a) AND b

or move the AND to a line of its own, starting in the same
column as the NOT or further left.
```

Say which you meant, and the error goes away:

```l4
-- the wide reading, spelled out: NOT applied to the whole of (a AND b)
GIVEN a IS A BOOLEAN, b IS A BOOLEAN
notBoth a b MEANS NOT (a AND b)

-- the narrow reading: only a is negated
GIVEN a IS A BOOLEAN, b IS A BOOLEAN
narrowedProperly a b MEANS (NOT a) AND b
```

#### What stops it: where the words sit

When a rule is spread over several lines, nothing is refused, and what decides is **the column each word starts in**. Compare these two, which differ only in how far the second line is indented:

```l4
-- AND starts to the RIGHT of NOT, so the NOT reaches over it.
-- This means: NOT (a AND b)
GIVEN a IS A BOOLEAN, b IS A BOOLEAN
swallowed a b MEANS
    NOT a
        AND b

-- AND starts in the SAME column as NOT, so the NOT stops before it.
-- This means: (NOT a) AND b
GIVEN a IS A BOOLEAN, b IS A BOOLEAN
stopped a b MEANS
    NOT a
    AND b
```

The rule, in full:

> A word like AND, OR or IMPLIES **stops** the NOT when it begins at the same column as the NOT, or further left. It is **swallowed** when it begins further right. On one line, everything after the NOT is further right, so everything would be swallowed — which is why the one-line spelling is refused and you are asked to write brackets.

Where the words sit on the page is what decides. There is no separate ranking that overrides it.

All of it in one place, with `a` and `b` both FALSE so that the two readings give different answers:

| what you write                       | what it means                                        | answer  |
| ------------------------------------ | ---------------------------------------------------- | ------- |
| `NOT a AND b` (one line)             | **refused** — say which reading you mean             | —       |
| `NOT (a) AND b` (one line)           | **refused** — the bracket closes around `a`, not NOT | —       |
| `NOT (a AND b)`                      | `NOT (a AND b)`                                      | `TRUE`  |
| `(NOT a) AND b`                      | `(NOT a) AND b`                                      | `FALSE` |
| `NOT a` / `AND b` further right      | `NOT (a AND b)`                                      | `TRUE`  |
| `NOT a` / `AND b` in the same column | `(NOT a) AND b`                                      | `FALSE` |
| `NOT a` / `AND b` further left       | `(NOT a) AND b`                                      | `FALSE` |

One space is enough. An AND indented a single character past the NOT is already swallowed; it has to line up with the NOT exactly, or start left of it, to stop the reach.

#### Brackets around what you are negating do not help

The obvious defence is to put brackets around the thing being negated. It does not work, and L4 refuses it for the same reason as the bare form: the closing bracket ends `a`, not the NOT's reach, so the NOT simply carries on past it.

```l4
-- refused, exactly like NOT a AND b: it would still mean NOT (a AND b)
--     looksCareful a b MEANS NOT (a) AND b

-- accepted: the bracket closes around the NOT itself
GIVEN a IS A BOOLEAN, b IS A BOOLEAN
actuallySafe a b MEANS (NOT a) AND b
```

**Put the bracket around the NOT, not around what it negates.** This is the single most useful thing on this page.

#### What is not refused

- **NOT at the end of a line.** `x AND NOT y` is fine on one line: the NOT is last, and there is nothing after it to reach over.
- **NOT over a bracketed group.** `NOT (a AND b)` is the wide reading spelled out, and it is accepted.
- **The multi-line forms.** Over several lines the columns are visibly doing the work, and both readings are accepted; the table above says which is which.
- **Comparisons.** `NOT n EQUALS 0` is accepted — see the next section.

### Negating Comparisons

NOT reaches over comparisons too, so these two say the same thing, and both are accepted:

```l4
GIVEN n IS A NUMBER
isNotZero      n MEANS NOT (n EQUALS 0)

GIVEN n IS A NUMBER
alsoIsNotZero  n MEANS NOT n EQUALS 0
```

A comparison is not refused because there is nothing to misread: `(NOT n) EQUALS 0` makes no sense for a number, so the wide reading is the only one anybody means. Write the brackets anyway. They cost nothing, and they tell the next reader what you meant rather than making them work out the reach.

## Pitfalls

- **NOT reaches further than it looks.** On one line it takes everything after it, so `NOT a AND b` would mean `NOT (a AND b)` — the whole conjunction — and **not** `(NOT a) AND b`. L4 refuses that spelling and asks you to write brackets. Over several lines nothing is refused, and it is the columns that decide: see [What stops it](#what-stops-it-where-the-words-sit).
- **Bracketing the operand does not fix it.** `NOT (a) AND b` is exactly as wide as `NOT a AND b`, and is refused too. Only `(NOT a) AND b` gives you the narrow reading.
- **`NOT` at the end of a line is always safe.** If nothing follows the NOT's operand, there is nothing for it to swallow. `x AND NOT y` on one line is fine, because the NOT is last.
- **Prefer UNLESS for exceptions.** `p AND NOT q` can be written `p UNLESS q`, which often reads closer to the legal source text — and sidesteps the reach question entirely.

The check runs wherever a file is checked: in the editor, in `l4 check`, and in every test. The repository also ships a text checker for the same-line form,

```
node etc/check-not-precedence.mjs --dir <directory>
```

which runs on every pull request over every `.l4` file in the repository, including files that no test ever type-checks. It reads one line at a time, so it sees the same-line form and nothing else. See [Troubleshooting](../errors/README.md#not-followed-by-and-or-or-implies-on-one-line) for the error as it appears and how to fix it.

## Related Keywords

- **[AND](AND.md)** - Logical conjunction
- **[OR](OR.md)** - Logical disjunction
- **[IMPLIES](IMPLIES.md)** - Logical implication
- **[UNLESS](UNLESS.md)** - Exception clause (`AND NOT`)

## See Also

- **[Logical Operators](../operators/README.md#logical-operators)** - All logical operators
