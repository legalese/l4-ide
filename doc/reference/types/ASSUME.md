# ASSUME

Declares a variable or function with a specified type, without providing a definition. Used for external values or assumptions about inputs.

> `ASSUME` is for a fact the boundary SUPPLIES — it becomes a required input in the export schema. If what you mean is that the model declines to answer, that is a refusal, and it is spelled [`REFUSE`](../control-flow/REFUSE.md). A refusal is not an input anyone can supply, and no rule can convert it into an answer.

## Syntax

```l4
ASSUME name IS A Type
ASSUME name IS A FUNCTION FROM Type1 TO Type2
```

## Purpose

ASSUME is used to:

1. Declare input variables for decision logic
2. Declare external functions whose implementation is provided elsewhere
3. State assumptions about values that will be provided at runtime

## Examples

**Example file:** [assume-example.l4](assume-example.l4)

### Basic Variable Assumptions

```l4
-- Assume a boolean input
ASSUME isEmployed IS A BOOLEAN

-- Assume a numeric value
ASSUME income IS A NUMBER

-- Assume a string
ASSUME applicantName IS A STRING
```

### Function Assumptions

```l4
-- Assume an external function
ASSUME calculateTax IS A FUNCTION FROM NUMBER TO NUMBER

-- Multi-parameter function (using AND)
ASSUME addNumbers IS A FUNCTION FROM NUMBER AND NUMBER TO NUMBER
```

### Using Assumed Values

```l4
ASSUME age IS A NUMBER
ASSUME income IS A NUMBER

DECIDE isEligible IS
  age >= 18 AND income > 50000
```

## Behavior

- Assumed values can be used in expressions but have no defined value
- Evaluating an expression that needs one stops: "I could not continue evaluating, because I
  needed to know the value of ... but it is an assumed term"
- No directive binds an assumed value inside a file. `WITH` supplies named arguments to a
  _function_, so `#CHECK isAdult WITH age IS 25` is a type error when `isAdult` takes no
  parameters. Values are supplied at deployment (next section); for in-file tests, declare
  the input as a `GIVEN` parameter instead (see [Binding Assumed Values](#binding-assumed-values))

## ASSUME and `@export`

When a module-level ASSUME is referenced by an `@export`-decorated DECIDE, it
is promoted to a parameter of the exported function and must be supplied by
the caller at request time (alongside the function's `GIVEN` parameters).
ASSUMEs not referenced by any exported function remain module-level
assumptions and are unaffected.

```l4
ASSUME age IS A NUMBER         -- promoted to a parameter of `isAdult`
ASSUME unused IS A BOOLEAN     -- stays assumed (no @export uses it)

@export Check if the subject is an adult
DECIDE isAdult IS age >= 18
```

### Function-typed inputs are not supported for `@export`

An `@export` function cannot accept a function-typed input, whether declared
as a `GIVEN` parameter or as a referenced ASSUME:

```l4
-- ✘ Rejected at typecheck / deploy time
ASSUME predicate IS A FUNCTION FROM NUMBER TO BOOLEAN
@export Apply the predicate
DECIDE `applies` IF predicate OF 42
```

Functions can't be passed over JSON (REST/MCP), and function-typed ASSUMEs
stay uninterpreted at runtime — so any call would fail with an "assumed
term" error rather than return a value. The typechecker emits
`Function type inputs are not supported for @export` and the service
refuses to deploy such bundles.

## Binding Assumed Values

There is no in-file binding form. The following is a type error, because `WITH` passes
named arguments to a function and `isAdult` is not one:

```l4
ASSUME age IS A NUMBER

DECIDE isAdult IS age >= 18

-- ✘ You are trying to apply isAdult ... of type BOOLEAN (which is not a function)
--   to (named) arguments
#CHECK isAdult WITH age IS 25
```

At deployment, `jl4-service` binds `age` from the request (see
[ASSUME and `@export`](#assume-and-export)). To exercise the rule in the file, make `age`
a `GIVEN` parameter; `WITH` then supplies it by name:

```l4
GIVEN age IS A NUMBER
DECIDE isAdult IF age >= 18

#EVAL isAdult WITH age IS 25     -- TRUE
#ASSERT isAdult WITH age IS 25
```

## A name for a whole section

For a name that is an input to every rule in a section rather than to one
definition, a `GIVEN` indented under the section's heading declares it once for
that section. It resolves, evaluates and exports exactly as a same-section
`ASSUME` term does. See [the section `GIVEN`](../syntax/section-given.md).

## Assuming a type: use `DECLARE` instead

`ASSUME TypeName IS A TYPE` declares a type rather than a value — a type that
is named but not described:

```l4
ASSUME Person IS A TYPE       -- works, but no longer the preferred spelling
```

A bodiless `DECLARE` says the same thing, and is now the spelling to reach for:

```l4
DECLARE Person
```

The two produce the same entity in the type checker, so a file can be migrated
one line at a time and nothing downstream changes. `DECLARE` is preferred
because it puts every type declaration under one keyword, and leaves `ASSUME`
for what its name suggests — assuming a _value_ you have not defined. See
[opaque types](DECLARE.md#opaque-types).

## Related Keywords

- **[DECIDE](../functions/DECIDE.md)** - Define a value or function with a body
- **[GIVEN](../functions/GIVEN.md)** - Introduce function parameters
- **[TYPE-KEYWORDS](keywords.md)** - Type syntax (IS, FUNCTION, etc.)

## See Also

- **[Types Reference](../types/README.md)** - Type syntax
