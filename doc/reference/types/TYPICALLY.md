# TYPICALLY

Attaches a default value to a type annotation. The default is a _rebuttable
presumption_: it declares what value should be presumed when none is provided,
without changing how the program evaluates.

## Syntax

```l4
name IS A Type TYPICALLY literal
```

TYPICALLY may appear on:

1. **DECLARE fields** — default values for record type fields
2. **GIVEN parameters** — default values for function parameters
3. **ASSUME declarations** — default values for assumed external values

## Purpose

In legal reasoning, many terms carry implicit assumptions: a contract party is
typically not under duress, a transaction is typically at arm's length.
TYPICALLY makes these rebuttable presumptions explicit, machine-readable, and
auditable.

The default value is **metadata only**:

- It is type-checked against the annotated type
  (`x IS A BOOLEAN TYPICALLY 42` is a type error).
- It must be a literal: a number, a string, or a nullary constructor such as
  `TRUE`, `FALSE`, or `NOTHING` (`x IS A BOOLEAN TYPICALLY (a AND b)` is an
  error).
- It requires an explicit type: the binder must carry an `IS A Type` annotation
  so the default can be checked (`GIVEN x TYPICALLY 5` with no type is an error).
- It cannot appear on a **type** binder: a type variable or a `TYPE` assumption
  holds no value, so `ASSUME Foo IS A TYPE TYPICALLY 42` is an error.
- It does **not** change evaluation. Nothing is substituted at runtime;
  downstream consumers (form generators, decision services, question-ordering
  policies) decide how to use the stored default. Exported function schemas
  expose it as the JSON Schema `default` keyword.

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

### In GIVEN (function parameters)

```l4
GIVEN
  age IS A NUMBER TYPICALLY 18
  married IS A BOOLEAN TYPICALLY FALSE
GIVETH A BOOLEAN
DECIDE `may purchase alcohol` IF age >= 18
```

### In ASSUME (external declarations)

```l4
ASSUME `applicable law` IS A STRING TYPICALLY "Singapore"
ASSUME `person has capacity` IS A BOOLEAN TYPICALLY TRUE
```

## Behavior

- TYPICALLY is purely additive: code without it behaves identically.
- The default must match the annotated type, or type checking fails.
- The default must be a literal (a compile-time constant).
- On a computed field (one with a MEANS clause), the MEANS definition governs;
  the TYPICALLY default is inert metadata.
- For complex defaults, use ordinary definitions and logic instead.

## See Also

- [ASSUME](ASSUME.md) — declaring assumed values
- [DECLARE](DECLARE.md) — declaring record types
- [GIVEN](../functions/GIVEN.md) — function parameters
