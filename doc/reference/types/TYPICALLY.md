# TYPICALLY

`TYPICALLY` writes down a usual value beside a field, an input or an `ASSUME`.
A person is usually of full capacity, a deal is usually at arm's length, a resident is usually an adult.
Such a usual value is a _rebuttable presumption_: it holds unless something shows otherwise.

## What L4 does with it today

L4 reads the usual value, checks that it fits the type, keeps it with the declaration, and shows it to other tools (see [Who sees the value](#who-sees-the-value)).

L4 does **not** use it to answer anything.
The evaluator (`#EVAL`, `#ASSERT`, `#TRACE`), `l4 batch` and the deployed service all ignore it.
An input that has a `TYPICALLY` value and is left out is still missing, exactly as if the value had not been written.
**Supply every input, whether or not it has a usual value.**
A rule that carries `TYPICALLY` clauses gives, when it runs, the same answers as the same rule without them.

What each way of running a rule does with a left-out input is set out [below](#when-an-input-is-left-out).

## Syntax

```l4
name IS A Type TYPICALLY value
```

`TYPICALLY` may appear on:

1. **DECLARE fields**: the usual value of a field of a record.
2. **GIVEN inputs**: the usual value of an input of a rule.
3. **ASSUME declarations**: the usual value of a fact supplied from outside.

## What is checked

The usual value is checked when the file is checked:

- It has to fit the type: `x IS A BOOLEAN TYPICALLY 42` is a type error.
- It has to be a literal: a number, a string, or a constructor that takes no arguments, such as `TRUE`, `FALSE`, `NOTHING` or the name of one value of an enumeration.
  `x IS A BOOLEAN TYPICALLY (a AND b)` is an error.
  For anything more complex, write an ordinary definition.
- On a rule's `GIVEN`, the input needs a type, so the value can be checked: `GIVEN x TYPICALLY 5` is an error.
  An `ASSUME` without a type, and a `GIVEN` inside a function without a name, take their type from the value instead.
- A type variable cannot carry one: `ASSUME Foo IS A TYPE TYPICALLY 42` is an error, because a type holds no value.

## Examples

**Example file:** [typically-example.l4](typically-example.l4)

### In DECLARE (record fields)

```l4
DECLARE Person HAS
  name IS A STRING
  has_capacity IS A BOOLEAN TYPICALLY TRUE
  is_under_duress IS A BOOLEAN TYPICALLY FALSE
  jurisdiction IS A STRING TYPICALLY "Singapore"
```

A field whose type is an enumeration may use one of its values:

```l4
DECLARE Colour IS ONE OF Red, Green

DECLARE Paint HAS
  colour IS A Colour TYPICALLY Red
```

### In GIVEN (function inputs)

```l4
GIVEN
  age IS A NUMBER TYPICALLY 18
  married IS A BOOLEAN TYPICALLY FALSE
GIVETH A BOOLEAN
DECIDE `may purchase alcohol` IF age >= 18
```

### In ASSUME (facts supplied from outside)

```l4
ASSUME `applicable law` IS A STRING TYPICALLY "Singapore"
ASSUME `person has capacity` IS A BOOLEAN TYPICALLY TRUE
```

## When an input is left out

Measured on 2026-10-30, and checked again on 2026-11-01, with the `l4` and `jl4-service` built from this tree, for the rule above (`age` and `married`, both with a usual value):

| Where the rule runs                                             | What a left-out input does                                                                                                                                           |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `#EVAL` with too few arguments                                  | A check error: the function "expects 2 arguments, but you are applying it to 1 argument here"; with `WITH`, "you forgot to supply the following arguments: married". |
| `#EVAL` of the rule's name alone                                | The answer is the function itself, `<function>`, and no answer to the question.                                                                                      |
| A record built without the field                                | A check error: "you forgot to supply the following arguments: has_capacity".                                                                                         |
| `l4 batch`, a row without the input                             | The row fails: "Missing required field 'married' in JSON object". `--validate-only` says "Missing required field: 'married'".                                        |
| `jl4-service`, a request without the input                      | Refused with status 422: "Parameter 'age': missing required parameter".                                                                                              |
| `jl4-service`, a request with `{}` ("uncertain") anywhere in it | A left-out BOOLEAN costs nothing unless the rule reads it, and then evaluation stops and names it; a left-out input of any other type is refused as missing.         |
| An `ASSUME` that the rule needs, with a `TYPICALLY` value       | Evaluation stops: "I needed to know the value of `applicable law` but it is an assumed term."                                                                        |

A request with `{}` in it is evaluated through a generated wrapper, and there a left-out BOOLEAN is not read as `FALSE`.
If the rule reads it, the evaluation stops with a message such as "I needed to know the value of `married (not supplied)`".

## Who sees the value

- **The JSON Schema of an exported function** (what `jl4-schema` writes) shows a number, a string, `TRUE` or `FALSE` default as the JSON Schema `default` keyword, on an input and on a field of a record input.
  A `NOTHING` default and a default that is a value of an enumeration are kept but left out of the schema.
- **`jl4-service`** publishes a default only on the fields of a record input, as the same keyword, and not on a top-level input or `ASSUME`.
  Whatever the schema says about a default, the input stays in the schema's `required` list.
- **`l4 format`** keeps the clause where it was written.
- **The syntax tree** carries it for any tool that reads the tree.

## Limits

- **Nothing applies it.** Supply every input. Filling in a left-out input from its usual value is the design in `specs/todo/TYPICALLY-DEFAULTS-SPEC.md`; it is proposed, not built.
- **Literals only.** A number, a string, or a constructor that takes no arguments.
- **A computed field is not checked.** On a field with a `MEANS` clause, the `MEANS` definition governs. A `TYPICALLY` value written beside it is kept but not checked, so `t IS A NUMBER TYPICALLY "oops" MEANS price * 2` passes the check.
- **The error for a value that is not a literal points at the record's name,** not at the value, when the field belongs to a `DECLARE`.
- **An `@nlg` written after a default does not attach to the default.** It describes the field or the input, as it would without the default.
- **The query planner does not read it.** The planner that decides which question to ask next orders questions by the structure of the rule alone; using the usual values as odds is proposed, not built.

## See Also

- [ASSUME](ASSUME.md): declaring assumed values
- [DECLARE](DECLARE.md): declaring record types
- [GIVEN](../functions/GIVEN.md): function inputs
