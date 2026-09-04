# TYPICALLY

Attaches a default value to a name. The default is a _rebuttable presumption_:
it records what should be presumed when nobody supplies a value, without
changing what the rules work out.

## Syntax

```l4
name IS A Type TYPICALLY literal
```

TYPICALLY may appear on:

A rule is told some facts about the case in front of it (its **"inputs"**, the
names listed after `GIVEN`). `TYPICALLY` may appear on:

1. **DECLARE fields** — default values for the fields of a record
2. **A rule's own `GIVEN`** (a **"rule `GIVEN`"**) — default values for that
   rule's inputs
3. **A `GIVEN` under a section heading** (a **"section `GIVEN`"**) — default
   values for a name declared once for every rule in the section
4. **ASSUME declarations** — default values for assumed names.
   `ASSUME` is deprecated for this job (ruled 2026-09-04) and still works;
   a fact supplied for each case belongs under its section's heading instead.
   See [the section `GIVEN`](../syntax/section-given.md).

## Purpose

In legal reasoning, many terms carry implicit assumptions: a contract party is
typically not under duress, a transaction is typically at arm's length.
TYPICALLY makes these rebuttable presumptions explicit, machine-readable, and
auditable.

The default value is **metadata only**:

- It is type-checked against the annotated type
  (`x IS A BOOLEAN TYPICALLY 42` is a type error).
- It must be a fixed value written out: a number, a piece of text, or a bare
  name such as `TRUE`, `FALSE` or `NOTHING` (`x IS A BOOLEAN TYPICALLY (a AND
b)` is an error).
- It requires an explicit type: the name must carry an `IS A Type` annotation so
  the default can be checked (`GIVEN x TYPICALLY 5` with no type is an error).
- It cannot appear on a name that stands for a **kind of thing** rather than a
  value: `ASSUME Foo IS A TYPE TYPICALLY 42` is an error.
- It does **not** change what a rule works out. Nothing is substituted when the
  rule is run; whatever reads the file afterwards (a form generator, a decision
  service, a question-ordering policy) decides how to use the stored default.
  The list of facts a published rule asks for carries it as the JavaScript
  Object Notation (JSON) Schema `default` keyword, and the defaulted name is
  still listed under `required`: whoever asks the question must still send a
  value for it.

_Proposed, not landed (2026-09-04): `TYPICALLY` as a real default. A defaulted
name may be left out when a case is supplied, the default is applied once at the
start of the calculation, it may be a piece of a rule that names another
`GIVEN`, and the published list of facts asks for it as optional rather than
required. This lands with the discharge pull request; today the default is
metadata only._

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

### In a rule's own GIVEN (that rule's inputs)

```l4
GIVEN
  age IS A NUMBER TYPICALLY 18
  married IS A BOOLEAN TYPICALLY FALSE
GIVETH A BOOLEAN
DECIDE `may purchase alcohol` IF age >= 18
```

### In a section GIVEN (one name for every rule in the section)

```l4
§ `Part 3 -- Capacity`
    GIVEN `governing law` IS A STRING TYPICALLY "Singapore"
          `person has capacity` IS A BOOLEAN TYPICALLY TRUE

DECIDE `contract is binding` IF
      `person has capacity`
  AND `governing law` EQUALS "Singapore"
```

Every rule in Part 3 reads those two names without re-declaring them. A
published rule that reads them asks for both, and carries `"Singapore"` and
`TRUE` as their JSON Schema defaults.

### In ASSUME (a name declared at the top of the file)

```l4
ASSUME `applicable law` IS A STRING TYPICALLY "Singapore"
ASSUME `person has capacity` IS A BOOLEAN TYPICALLY TRUE
```

`ASSUME` is deprecated (ruled 2026-09-04) and still works; the two spellings
carry the default in the same way.

## Behavior

- TYPICALLY only adds: a file without it behaves identically.
- The default must match the annotated type, or type checking fails.
- The default must be a fixed value written out, like `18` or `"yes"`.
- On a computed field (one with a MEANS clause), the MEANS definition governs
  and the TYPICALLY default does nothing.
- For anything a fixed value cannot express, write an ordinary definition
  instead.

## See Also

- [ASSUME](ASSUME.md) — declaring assumed values (deprecated, still works)
- [The section `GIVEN`](../syntax/section-given.md) — declaring a name once for a
  whole section
- [DECLARE](DECLARE.md) — declaring record types
- [GIVEN](../functions/GIVEN.md) — the inputs of one rule
- [Query Planning](../query-planning/README.md) — how a stored default becomes
  the per-atom prior `w_v` for the question-ordering wizard
- [Web Form Generation](../../courses/advanced/module-a4-production.md#web-form-generation)
  — using TYPICALLY defaults in an autogenerated wizard
