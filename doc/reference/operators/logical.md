# AND, OR, NOT, IMPLIES

The logical operators combine BOOLEAN values.

## Forms

| Operator  | Symbol | Asyndetic | Meaning                                |
| --------- | ------ | --------- | -------------------------------------- |
| `AND`     | `&&`   | `...`     | both are TRUE                          |
| `OR`      | `\|\|` | `..`      | at least one is TRUE                   |
| `NOT`     |        |           | the opposite                           |
| `IMPLIES` | `=>`   |           | if the first is TRUE, so is the second |

The word and the symbol mean the same and can be mixed. For `...` and `..`, see [Operators: Asyndetic AND and OR](README.md#asyndetic-and-and-or).
For exceptions ("… unless …"), see [UNLESS](UNLESS.md).

**Example files:** [and-example.l4](and-example.l4), [or-example.l4](or-example.l4), [not-example.l4](not-example.l4), [implies-example.l4](implies-example.l4)

## Truth table

| A     | B     | A AND B | A OR B | NOT A | A IMPLIES B |
| ----- | ----- | ------- | ------ | ----- | ----------- |
| TRUE  | TRUE  | TRUE    | TRUE   | FALSE | TRUE        |
| TRUE  | FALSE | FALSE   | TRUE   | FALSE | FALSE       |
| FALSE | TRUE  | FALSE   | TRUE   | TRUE  | TRUE        |
| FALSE | FALSE | FALSE   | FALSE  | TRUE  | TRUE        |

## AND

```l4
GIVEN age IS A NUMBER
      `has a licence` IS A BOOLEAN
GIVETH A BOOLEAN
`may drive` age `has a licence` MEANS age >= 16 AND `has a licence`
```

AND evaluates lazily: if the first operand is `FALSE`, the second is not evaluated.

In a trace (`#EVALTRACE`, or the reasoning a service returns), an AND appears as itself, with its first operand and that operand's value beneath it.
When the second operand was needed it follows: in `#EVALTRACE` it is the next step, at the AND's own level, and in a service's reasoning it is the AND's last child.
A second operand that was not needed does not appear.
If the first operand is written as plain `TRUE` or `FALSE`, the trace does not show it, because its value is already in the rule.
The [#EVALTRACE](../syntax/README.md#evaltrace) entry shows one such trace in full.

A rule that calls itself without end through the second operand, such as `loop n MEANS TRUE AND loop n`, runs until it is stopped, as one that calls itself through an `IF`'s branch does.

### When AND's first operand is not known

The first operand may depend on a fact nobody has supplied yet, such as a section `GIVEN` the case leaves out.
Then AND looks at the second operand too.
If the second is `FALSE`, the answer is `FALSE`, whatever the missing fact turns out to be: `x AND FALSE` is `FALSE`.
Otherwise the answer is not known yet, and asking for it stops and names every fact it is waiting for, here both `x` and `y`:

```
#EVAL x AND y
```

```
I could not continue evaluating, because I needed to know the values of
  x
  y
but they are assumed terms.
```

If the second operand stops with an error or a refusal, or takes more than the 250,000 steps evaluation allows over a missing fact, the answer is still reported as waiting for the first operand's facts, because those decide whether the second operand matters at all.
Nor does the second operand do anything outside the rule while the first is not known: a `RECORD`, a `FETCH` or `POST`, or a read of the environment with `ENV` there stops evaluation instead, and the answer is reported the same way.

## OR

```l4
GIVEN `is an employee` IS A BOOLEAN
      `is a contractor` IS A BOOLEAN
GIVETH A BOOLEAN
`may enter` `is an employee` `is a contractor` MEANS `is an employee` OR `is a contractor`
```

OR evaluates lazily: if the first operand is `TRUE`, the second is not evaluated.

In a trace (`#EVALTRACE`, or the reasoning a service returns), an OR appears as itself, with its first operand and that operand's value beneath it.
When the second operand was needed it follows: in `#EVALTRACE` it is the next step, at the OR's own level, and in a service's reasoning it is the OR's last child.
A second operand that was not needed does not appear.
If the first operand is written as plain `TRUE` or `FALSE`, the trace does not show it, because its value is already in the rule.

A rule that calls itself without end through the second operand, such as `loop n MEANS FALSE OR loop n`, runs until it is stopped, as one that calls itself through an `IF`'s branch does.

### When OR's first operand is not known

The first operand may depend on a fact nobody has supplied yet, such as a section `GIVEN` the case leaves out.
Then OR looks at the second operand too.
If the second is `TRUE`, the answer is `TRUE`, whatever the missing fact turns out to be: `x OR TRUE` is `TRUE`.
Otherwise the answer is not known yet, and asking for it stops and names every fact it is waiting for, as [AND](#when-ands-first-operand-is-not-known) does.
If the second operand stops with an error or a refusal, or takes more than the 250,000 steps evaluation allows over a missing fact, the answer is still reported as waiting for the first operand's facts.
Nor does the second operand do anything outside the rule while the first is not known, as with [AND](#when-ands-first-operand-is-not-known).

## NOT

`NOT` turns TRUE into FALSE and FALSE into TRUE.
In legal rules it typically encodes a negative requirement ("has no criminal record", "is not disqualified") and pairs with AND and OR to express exceptions.
For an exception to a whole condition, see also [UNLESS](UNLESS.md): `p AND NOT q` can be written `p UNLESS q`, which often reads closer to the legal source text and sidesteps the reach question below entirely.

In a trace (`#EVALTRACE`, or the reasoning a service returns), a NOT appears as itself, with its operand and that operand's value beneath it (unless the operand is written as plain `TRUE` or `FALSE`).

### How far does NOT reach?

This is the one thing to know about NOT, and it catches almost everybody the first time.

NOT does not simply flip the next word. It **reaches forward** and takes everything that follows it on the same line, not just the next word, but any AND, OR, IMPLIES, or comparison that comes after it. So a line like

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
`not both` a b MEANS NOT (a AND b)

-- the narrow reading: only a is negated
GIVEN a IS A BOOLEAN, b IS A BOOLEAN
`not a, and b` a b MEANS (NOT a) AND b
```

**Example file:** [not-example.l4](not-example.l4)

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

> A word like AND, OR or IMPLIES **stops** the NOT when it begins at the same column as the NOT, or further left. It is **swallowed** when it begins further right. On one line, everything after the NOT is further right, so everything would be swallowed, which is why the one-line spelling is refused and you are asked to write brackets.

Where the words sit on the page is what decides. There is no separate ranking that overrides it.

All of it in one place, with `a` and `b` both FALSE so that the two readings give different answers:

| what you write                       | what it means                                       | answer  |
| ------------------------------------ | --------------------------------------------------- | ------- |
| `NOT a AND b` (one line)             | **refused**: say which reading you mean             | n/a     |
| `NOT (a) AND b` (one line)           | **refused**: the bracket closes around `a`, not NOT | n/a     |
| `NOT (a AND b)`                      | `NOT (a AND b)`                                     | `TRUE`  |
| `(NOT a) AND b`                      | `(NOT a) AND b`                                     | `FALSE` |
| `NOT a` / `AND b` further right      | `NOT (a AND b)`                                     | `TRUE`  |
| `NOT a` / `AND b` in the same column | `(NOT a) AND b`                                     | `FALSE` |
| `NOT a` / `AND b` further left       | `(NOT a) AND b`                                     | `FALSE` |

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
- **Comparisons.** `NOT n EQUALS 0` is accepted; see the next section.

### Negating comparisons

NOT reaches over comparisons too, so these two say the same thing, and both are accepted:

```l4
GIVEN n IS A NUMBER
`is not zero`       n MEANS NOT (n EQUALS 0)

GIVEN n IS A NUMBER
`is also not zero`  n MEANS NOT n EQUALS 0
```

A comparison is not refused because there is nothing to misread: `(NOT n) EQUALS 0` makes no sense for a number, so the wide reading is the only one anybody means. Write the brackets anyway. They cost nothing, and they tell the next reader what you meant rather than making them work out the reach.

### Where the check runs

The check runs wherever a file is checked: in the editor, in `l4 check`, and in every test. The repository also ships a text checker for the same-line form,

```
node etc/check-not-precedence.mjs --dir <directory>
```

which runs on every pull request over every `.l4` file in the repository, including files that no test ever type-checks. It reads one line at a time, so it sees the same-line form and nothing else. See [Troubleshooting](../errors/README.md#not-followed-by-and-or-or-implies-on-one-line) for the error as it appears and how to fix it.

## IMPLIES

`A IMPLIES B` is FALSE only when `A` is TRUE and `B` is FALSE. It means the same as `(NOT A) OR B`: "if A, then B".

The brackets are doing real work there, and leaving them out changes the meaning. Written as `NOT A OR B`, the NOT would reach over the OR as well and you would get `NOT (A OR B)`, a different rule, which disagrees with IMPLIES on half its inputs. L4 refuses that spelling and asks for the brackets. See [How far does NOT reach?](#how-far-does-not-reach).

```l4
GIVEN age IS A NUMBER
      `has parental consent` IS A BOOLEAN
GIVETH A BOOLEAN
`consent rule is met` age `has parental consent` MEANS
  age < 18 IMPLIES `has parental consent`
```

`IMPLIES` groups to the right: `a IMPLIES b IMPLIES c` means `a IMPLIES (b IMPLIES c)`.

IMPLIES evaluates lazily: if A is FALSE, the rule does not apply, the answer is TRUE, and B is not evaluated.
In a trace (`#EVALTRACE`, or the reasoning a service returns), an IMPLIES appears as itself, with A and its value beneath it, unless A is written as plain `TRUE` or `FALSE`.
When B was needed it follows: in `#EVALTRACE` it is the next step, at the IMPLIES's own level, and in a service's reasoning it is the IMPLIES's last child.

If A depends on a fact nobody has supplied yet, the answer waits for that fact whatever B is: even `x IMPLIES TRUE` stops and names `x`, because whether the rule applies at all is still open.
Asking for the answer names every fact it is waiting for, from A and from B, as [AND](#when-ands-first-operand-is-not-known) does.

## Several lines

A long condition can be written one operand per line, with the operator at the start of each line:

```l4
GIVEN age IS A NUMBER
      income IS A NUMBER
      `has a criminal record` IS A BOOLEAN
GIVETH A BOOLEAN
`is eligible` age income `has a criminal record` MEANS
      age >= 18
  AND income > 30000
  AND NOT `has a criminal record`
```

When the operators are in one column, the usual [precedence](README.md#precedence) applies.
An operator written further left than the lines above it applies to all of them together:

```l4
GIVEN a IS A BOOLEAN
      b IS A BOOLEAN
      c IS A BOOLEAN
GIVETH A BOOLEAN
`grouped by layout` a b c MEANS
         a
      OR b
  AND    c
```

This means `(a OR b) AND c`; on one line, `a OR b AND c` means `a OR (b AND c)`.

## Evaluation order

The left operand is evaluated first, and the right one only when it is needed: `FALSE AND x` is FALSE, `TRUE OR x` is TRUE and `FALSE IMPLIES x` is TRUE without looking at `x`.

## Related pages

- [UNLESS](UNLESS.md): exceptions
- [Operators](README.md): precedence and asyndetic forms
- [IF](../control-flow/IF.md): use a condition to choose a value
