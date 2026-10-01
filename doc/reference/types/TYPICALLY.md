# TYPICALLY

Attaches a default value to a name. The default is a _rebuttable presumption_:
it records what should be presumed when nobody supplies a value.

**On a section `GIVEN` the default is used when nobody supplies a value.**
**At the boundary — `l4 batch` and the decision service — it is also used for a
rule's own `GIVEN` and for a record field, when a case leaves the fact out.**
Inside a file, everywhere else, it records what should be presumed without
changing what the rules work out. That split is new, and the parts are
described separately below.

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
4. **`ASSUME` declarations, in older files** — default values for assumed
   names. `ASSUME` is deprecated (ruled 2026-09-04) and still works; a fact
   supplied for each case belongs under its section's heading instead. See
   [the section `GIVEN`](../syntax/section-given.md) and
   [ASSUME (deprecated)](ASSUME.md).

## Purpose

In legal reasoning, many terms carry implicit assumptions: a contract party is
typically not under duress, a transaction is typically at arm's length.
TYPICALLY makes these rebuttable presumptions explicit, machine-readable, and
auditable.

## On a section `GIVEN`: a value, not metadata

A [section `GIVEN`](../syntax/section-given.md) declares an input for a whole
section, and every rule that reads it takes it as an input. If it carries a
`TYPICALLY`, nothing has to supply it:

```l4
§ `Rates`
    GIVEN `the rate` IS A NUMBER TYPICALLY 3

GIVETH A NUMBER
doubled MEANS `the rate` TIMES 2

#EVAL doubled                           -- 6, from the default
#EVAL doubled WITH `the rate` IS 5      -- 10, supplied
```

Three things follow from where the default is applied:

- **The default is filled in once per evaluation**, at the outermost point that
  needed it, so every rule that reads the name **without being given a value for
  it** works out the same value.
- **An explicit [`WITH`](../functions/WITH.md) wins**, for that call and
  everything under it. It is an override, not a second default. So a single
  calculation can genuinely see two values for one name: with `r TYPICALLY 3`,
  `outer MEANS inner PLUS (inner WITH r IS 100)` works out **103**, because the
  first `inner` took the default and the second was given 100.
- **A name with no default that nobody supplies is still an assumed fact**, and
  a rule that reads it says so at the point where it is needed.

This is a change in what `TYPICALLY` means, and it is confined to this one
place: a `TYPICALLY` on a `DECLARE` field, on a rule's own `GIVEN`, or on an
`ASSUME` behaves exactly as it did before, as the next section describes. A
rule's own defaulted `GIVEN` still cannot be omitted at a call.

## Everywhere else: metadata only

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
- **On a section `GIVEN` it changes what a rule works out**: a rule that reads
  the name, and is given no value for it, uses the default. Inside a file,
  everywhere else, it does not: a rule's own defaulted `GIVEN` still cannot be
  left out at a call, and a record cannot be built with a defaulted field left
  out.

## At the boundary: `l4 batch` and the decision service

A case sent to `l4 batch`, or a request sent to the decision service, may leave
out any fact that has a default, whether the `TYPICALLY` is on a section
`GIVEN`, on the exported rule's own `GIVEN`, or on a field of a record the rule
takes as an input. The default is filled in where the case arrives, and the
answer lists it under **`presumed`**, by name (or, for a field, by its path, such
as `config.timeout`) — but only if the answer actually used it. Three rules
govern what counts as leaving a fact out:

- **Leaving the name out** is leaving it out. So is an empty cell in a CSV file
  given to `l4 batch`. A `MAYBE` fact with no default, left out, is `NOTHING`,
  and is listed under `presumed` like a default.
- **`null` is not.** `null` means _not known_, and a fact that is not known never
  takes its default: the case is refused, naming the fact.
- **The presumption can be switched off.** `l4 batch --presumption hard`, or
  `"presumption": "hard"` in a service request, uses no defaults: a fact left
  out is missing, and the case is refused, naming it. The default is `soft`.

The list of facts a published rule asks for carries each default as the
JavaScript Object Notation (JSON) Schema `default` keyword, and a defaulted fact
is not listed under `required`. A `TYPICALLY` on an `ASSUME` is not used here
either, and is not published.

_Partly landed (2026-10-02). Of the four things proposed on 2026-09-04, two have
landed: a **section** `GIVEN` may be left out, and a rule that reads it then uses
the default; and the published list of facts asks for a defaulted fact as
optional, which the boundary then honours. The other two have not. A rule's own
`GIVEN` still cannot be left out at a call inside a file. The default still must
be a fixed value written out, so it cannot name another `GIVEN`._

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
published rule that reads them offers both as optional, carrying `"Singapore"`
and `TRUE` as their JSON Schema defaults.

### In older files: `ASSUME`

```l4
ASSUME `applicable law` IS A STRING TYPICALLY "Singapore"
ASSUME `person has capacity` IS A BOOLEAN TYPICALLY TRUE
```

`ASSUME` is deprecated (ruled 2026-09-04) and still works. On an `ASSUME` the
default stays metadata, as everywhere outside a section `GIVEN`; moving the
declaration under its section's heading, as the previous example does, is what
makes the default take effect for a rule given no value. The companion file no
longer carries this spelling.

## Behavior

- TYPICALLY only adds, except on a section `GIVEN`, where it decides what a rule
  that is given no value for the name works out, and at the boundary, where it
  decides what a case that leaves the fact out works out.
- The default must match the annotated type, or type checking fails.
- The default must be a fixed value written out, like `18` or `"yes"`.
- On a computed field (one with a MEANS clause), the MEANS definition governs
  and the TYPICALLY default does nothing.
- For anything a fixed value cannot express, write an ordinary definition
  instead.

## See Also

- [ASSUME](ASSUME.md) — declaring assumed values (deprecated, still works)
- [The section `GIVEN`](../syntax/section-given.md) — declaring a name once for a
  whole section, and the one place a default changes what a rule works out
- [WITH](../functions/WITH.md) — supplying, and overriding, an input by name
- [DECLARE](DECLARE.md) — declaring record types
- [GIVEN](../functions/GIVEN.md) — the inputs of one rule
- [Query Planning](../query-planning/README.md) — how a stored default becomes
  the per-atom prior `w_v` for the question-ordering wizard
- [Web Form Generation](../../courses/advanced/module-a4-production.md#web-form-generation)
  — using TYPICALLY defaults in an autogenerated wizard
