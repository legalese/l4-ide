# The section `GIVEN`

A `GIVEN` written under a section heading declares a name **once for the whole
section**, instead of repeating it in every rule's own `GIVEN`.

That repetition is the normal state of an encoded statute. In the legal corpus
in this repository, roughly half of all `GIVEN` slots repeat a name and type
already used elsewhere in the same section — the rules of a section are usually
about one thing (an issuer, a will, an applicant), and each one has to say so
again.

```l4
§ `1. Issuer eligibility`
    GIVEN issuer IS AN IssuerProfile

GIVETH A BOOLEAN
`is an Exchange Act reporting company` MEANS
    issuer's `files reports under section 13 or 15(d)`

GIVETH A BOOLEAN
`is disqualified` MEANS
    issuer's `has a disqualifying event`
```

Both rules read `issuer`. Neither declares it.

## Where the `GIVEN` goes

**A `GIVEN` belongs to the section when its keyword starts at a column greater
than the section heading's `§`.** The taught spelling is the one above: on the
line after the heading, indented.

A `GIVEN` at column 1 is the next declaration's signature, exactly as it has
always been:

```l4
§ `Rates`

GIVEN amount IS A NUMBER        -- column 1: this is `doubled`'s parameter,
GIVETH A NUMBER                 -- not the section's binder
doubled MEANS amount TIMES 2
```

The heading-line form `§ `Rates` GIVEN amount IS A NUMBER` falls under the same
column rule and the parser accepts it, but it is not the house style: the
formatter and `prettyLayout` re-emit the indented form. A `GIVEN` written
_before_ an `AKA` on the heading line does not parse; put the `AKA` first.

## What it is visible to

- A binder on a heading covers every definition in every section beneath it.
- **Same-named binders in different sections are distinct binders.** Two
  sections that each declare `foo` declare two different things, each read by
  its own section and its descendants — exactly as two `ASSUME`s or two
  definitions would be. This is the drafting pattern "for the purposes of
  sections 1 and 2, `foo` means apple; for the purposes of sections 3 and 4,
  `foo` means banana":

  ```l4
  § toplevel

  DECLARE Fruit IS ONE OF Apple, Banana

  §§ `1`
      GIVEN foo IS A Fruit
  GIVETH A Fruit
  `reader one` MEANS foo          -- section 1's foo

  §§ `2`
      GIVEN foo IS A Fruit
  GIVETH A Fruit
  `reader two` MEANS foo          -- section 2's foo, a different binder

  §§ `5`
  GIVETH A Fruit
  `reader five` MEANS foo         -- error: which foo?
  ```

- A child that re-declares an ancestor's name shadows it **within the child's
  subtree**; the ancestor's binder is unchanged elsewhere.
- A binder is visible upward and sideways whenever it is the only candidate: a
  binder declared on `§§ 1` is readable from `§§ 2` if `§§ 2` declares none of
  its own.
- A reader that reaches two same-named binders at once is an error, and the
  diagnostic names the candidates by their declaring section
  (``toplevel.`1`.foo``, ``toplevel.`2`.foo``). Three ways out, each saying
  something different about the drafting: **hoist** the binder to a common
  ancestor heading if it is one thing; **rename** one if they are two; or
  **bridge at the call**, `g WITH foo IS foo`, if this section's `foo` is the
  other section's for that call.

## The dedent hazard

A paste or a hand-edit that pushes a section binder back to column 1 turns it
into the next declaration's parameter, silently — the compiler rewrites a
declaration head that takes no arguments so that it takes the `GIVEN`'s names
instead, which is what makes an ordinary function signature work at all.

Where the declaration below makes **no use of the name at all** — and it is a
`DECLARE` or an `ASSUME`, which is where the mistake actually bites — that is a
check error:

```
This GIVEN starts at column 1, so it is the signature of the declaration
below it -- and that declaration never uses

  `the rate`

If `the rate` was meant as a binder for the whole of

  § S

indent the GIVEN so that it starts past the § of the heading:

  § <heading>
      GIVEN `the rate` IS A <type>
```

The check does not extend to `DECIDE`, because a function that does not use one
of its parameters is a perfectly ordinary thing to write and is
indistinguishable from a dedented binder; five files in this repository do
exactly that today.

A `GIVEN` at column 1 followed by another `§` heading is a parse error.

The formatter never moves a `GIVEN` across the column boundary, so formatting
cannot introduce the hazard.

## What a section binder does in this release

**In this release a section binder evaluates as an assumed term, exactly like
`ASSUME`.** A rule that reads one cannot be evaluated to a value until the
binder is supplied; `#EVAL` on such a rule reports

```
I could not continue evaluating, because I needed to know the value of
  `applicable rate`
but it is an assumed term.
```

Supplying a section binder at a call site, and the read-set discharge that would
flow one automatically from an entry point, are **not in this release**.

What does work today:

- **The export schema.** A binder that an `@export`ed function reads — directly
  or through anything it calls — becomes a required request parameter, carrying
  its `@desc` if it has one and its `TYPICALLY` value as the JSON Schema
  `default`. (A `TYPICALLY` binder is still listed in `required`; making it
  optional is separate, later work.)
- **`l4 batch` and `jl4-service`**, which bind the read binders from the request
  the same way they bind a read `ASSUME`.
- **Every export backend** — DMN/BPMN, docassemble, Catala, OpenFisca, Blawx,
  MLIR — treats a section binder as it treats an `ASSUME` term.
- **Diagnostics and hover**, which point at the `GIVEN` line under the heading
  (a "defined at" note names that line, and hovering the parameter shows its
  type). Go-to-definition and find-references have not been exercised on a
  section `GIVEN` in this release.

A parameter with no type (`GIVEN a`) is accepted and behaves as `ASSUME a` does.
A parameter typed `IS A TYPE` declares a section-scoped opaque type, as
`ASSUME a IS A TYPE` does; prefer `DECLARE` for that.

Whether a section `GIVEN` crosses an `IMPORT` is whatever `ASSUME` does today,
which this release does not change and does not assert.

## Example

[section-given-example.l4](section-given-example.l4)

## See also

- [`ASSUME`](../types/ASSUME.md) — the same idea for a single name, at module level
- [`GIVEN`](../functions/GIVEN.md) — a signature for one definition
- [Section markers (§)](README.md#section-markers-)
