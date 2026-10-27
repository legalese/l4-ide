# ASSUME

`ASSUME` declares a name and its type without giving it a value or a definition.
Use it for facts that are supplied from outside, and for functions whose definition lives elsewhere.

## Syntax

```text
ASSUME name IS A Type
ASSUME name IS A FUNCTION FROM Type1 AND Type2 TO Type3
```

**Example file:** [assume-example.l4](assume-example.l4)

## Examples

```l4
ASSUME `the applicant's age` IS A NUMBER
ASSUME `the applicant is employed` IS A BOOLEAN
ASSUME `the tax on` IS A FUNCTION FROM NUMBER TO NUMBER

DECIDE `the applicant qualifies` IF
      `the applicant's age` >= 18
  AND `the applicant is employed`
```

An assumed name can be used anywhere its type fits, and the file type-checks.
Evaluating an expression that needs its value stops with "I could not continue evaluating, because I needed to know the value of … but it is an assumed term."
To try such a rule with values, give the facts as `GIVEN` inputs instead, or publish it with `@export` as below.

For a polymorphic assumed function, see [FOR ALL](for-all.md).

## ASSUME and `@export`

When a function marked `@export` uses a top-level `ASSUME`, the assumed name becomes an input of the exported function, and the caller supplies it with the `GIVEN` inputs.
An `ASSUME` that no exported function uses stays as it is.

```l4
ASSUME `the applicant's age` IS A NUMBER
ASSUME `an unused fact` IS A BOOLEAN

@export Check whether the applicant is an adult
DECIDE `the applicant is an adult` IF `the applicant's age` >= 18
```

Here `` `the applicant's age` `` is an input of `` `the applicant is an adult` ``; `` `an unused fact` `` is not.

A request can set an `ASSUME` only when it is declared as above: at the top level of the file that holds the exported function, with its type written after `IS A`.

### Inputs that an exported function cannot take

A request to an exported function is written in JSON, and JSON has no form for a function, an event or a duty.
So an exported function cannot take any of them as an input, whether it is a `GIVEN` input or an `ASSUME` it uses:

```text
ASSUME `the test` IS A FUNCTION FROM NUMBER TO BOOLEAN
@export Apply the test
DECIDE `passes` IF `the test` 42
```

`l4 check` refuses such a file, and the service refuses to deploy it, with one of three errors:

- "Function type inputs are not supported for @export", for a function, such as `the test` above.
- "EVENT inputs are not supported for @export", for an event. An event is a type too, written with the type of the parties and the type of the actions: `GIVEN e IS AN EVENT Person Action`.
- "DEONTIC inputs are not supported for @export", for a duty, a permission or a prohibition, written `DEONTIC Person Action`.

To publish `passes`, define `the test` with `MEANS` or `DECIDE` instead of assuming it.
For an event or a duty, take the plain facts as inputs and build the value inside the function; see [EVENT](../regulative/EVENT.md#an-exported-rule-cannot-take-an-event) and [DEONTIC](../regulative/DEONTIC.md#an-exported-rule-cannot-take-a-deontic-input).

L4 refuses a function input only on a `GIVEN` of the exported function, or on a top-level `ASSUME` of the same file that the exported function reads in its own body, and only where it finds a function type in the type written after `IS A`.
It looks in every part of that type, as in `LIST OF FUNCTION FROM NUMBER TO NUMBER`.
Where that type uses a [synonym](DECLARE.md#type-synonyms) that the same file declares, L4 looks in what the synonym stands for in the same way.
It does not look into a synonym that an imported file declares.
A function that the exported function gets in any other way passes `l4 check`, but no request can run it: for example a function in a field of a record, a synonym for a function type that an imported file declares, a `GIVEN` with no written type, an `ASSUME` written with its signature before it, or another rule that reads an assumed function.

## Related pages

- [GIVEN and GIVETH](../functions/GIVEN.md): inputs of a function
- [DECLARE](DECLARE.md): types and type expressions
- [Deploy your rules](../../tutorials/deploying-rules/exporting-rules-for-deployment.md): `@export` in practice
