# Fix wording with @nlg

L4 never rewrites your words, so a rule can read badly in a rendered document.
This page shows the fix for each problem.

**Before you start:** [Make rules read like law](optimising-natural-language-generation.md).

**Examples:** [fix-wording-before.l4](fix-wording-before.l4) and [fix-wording-after.l4](fix-wording-after.l4). See each one with `l4 render fix-wording-before.l4 --format text`.

| You see                                                   | Fix                                                                   |
| --------------------------------------------------------- | --------------------------------------------------------------------- |
| `is authorised for the employee`                          | [Give the rule a subject](#give-the-rule-a-subject)                   |
| `it is not the case that both is one of sections 9 to 14` | [Give the rule a subject](#give-the-rule-a-subject)                   |
| `…, for the employee`                                     | [Write a field as a statement](#write-a-field-as-a-statement)         |
| `the employee's the start date`                           | [Drop the extra "the"](#drop-the-extra-the)                           |
| `is aged 16 or over with the employee`                    | [Make an assumed fact a field](#make-an-assumed-fact-a-field)         |
| `after the last, last [last], next [next]`                | [Write a sentence for the heading](#write-a-sentence-for-the-heading) |
| `it is not the case that the employee is on leave`        | [Write the negative yourself](#write-the-negative-yourself)           |

## Give the rule a subject

A rule with no sentence reads as its name, then its inputs:

```text
(a) is authorised for the employee;
(f) it is not the case that both is one of sections 9 to 14 for the employee's the section engaged and …
```

Write a sentence, with a slot for each input:

```l4
GIVEN `the employee` IS AN Employee
GIVETH A BOOLEAN
@nlg %`the employee`% is authorised
`is authorised` MEANS `the employee`'s `the start date` AT LEAST 1
```

```text
(a) the employee is authorised;
(f) it is not the case that both the employee's section engaged is one of sections 9 to 14 and …
```

## Write a field as a statement

A `BOOLEAN` field that doesn't start with _is_ or _has_ reads as its own words, then says whose it is:

```text
(c) it is not the case that I am or have been married, for the employee;
(d) it is not the case that a member of a pension scheme, for the employee;
```

Give the field a whole statement. It then reads alone:

```l4
`I am or have been married`    IS A BOOLEAN
  @nlg the employee is or has been married
`a member of a pension scheme` IS A BOOLEAN
  @nlg the employee is a member of a pension scheme
```

```text
(c) it is not the case that the employee is or has been married;
(d) it is not the case that the employee is a member of a pension scheme;
```

## Drop the extra "the"

Any other field reads after its owner, so a name that starts with "the" doubles up:

```text
the employee's the start date
```

Give the field the words that follow the owner:

```l4
`the start date` IS A NUMBER
  @nlg start date
```

```text
the employee's start date
```

## Make an assumed fact a field

An `ASSUME`d function has no named inputs, so a sentence has no slot to fill:

```l4
ASSUME `is aged 16 or over` IS A FUNCTION FROM Employee TO BOOLEAN
```

```text
(b) is aged 16 or over with the employee;
```

Make it a `BOOLEAN` field. A field that starts with _is_ or _has_ follows its owner, so it needs no `@nlg`:

```l4
DECLARE Employee
    HAS `is aged 16 or over` IS A BOOLEAN
```

```text
(b) the employee is aged 16 or over;
```

## Write a sentence for the heading

A mixfix rule reads as its pattern, with its inputs as blanks. Punctuation in the pattern reads as written:

```text
The change is at least 92 days after the last, last [last], next [next], employer agrees: [agrees] if:
```

Write a sentence, and name the inputs as nouns:

```l4
GIVEN `the last change` IS A DATE, `the next change` IS A DATE, `the employer agrees` IS A BOOLEAN
GIVETH A BOOLEAN
@nlg %`the next change`% is at least 92 days after %`the last change`%, or %`the employer agrees`%
```

```text
[the next change] is at least 92 days after [the last change], or [the employer agrees] if:
```

## Write the negative yourself

`NOT` stays outside the statement it denies:

```text
(e) it is not the case that the employee is on leave; and
```

For a negative wording, write a rule with a sentence, and call it:

```l4
GIVEN `the employee` IS AN Employee
GIVETH A BOOLEAN
@nlg %`the employee`% is not on leave
`is at work` MEANS NOT `the employee`'s `is on leave`
```

```text
(e) the employee is not on leave; and
```

## Check the sentence

`@nlg` changes the wording, not the logic, and L4 can't tell if a sentence is true.
Read each sentence against its rule, and try names first: a better name needs no sentence.

For the exact rules, see [@nlg](../../reference/syntax/nlg.md).
