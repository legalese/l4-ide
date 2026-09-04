# The section `GIVEN`

A `GIVEN` written under a section heading declares a name **once for the whole
section**, instead of repeating it in every rule's own `GIVEN`.

A rule is told some facts about the case in front of it (its **"inputs"**, the
names listed after `GIVEN`) and works out one answer from them. Where the
`GIVEN` is written decides who the inputs belong to. A `GIVEN` at column 1 lists
the inputs of the one declaration below it — a **"rule GIVEN"**. A `GIVEN`
indented under a section heading declares an input shared by every rule in that
section — a **"section GIVEN"**, which is what this page is about.

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

A `GIVEN` at column 1 lists the inputs of the next declaration, exactly as it
has always done:

```l4
§ `Rates`

GIVEN amount IS A NUMBER        -- column 1: this is `doubled`'s own input,
GIVETH A NUMBER                 -- not the section's
doubled MEANS amount TIMES 2
```

The heading-line form `§ `Rates` GIVEN amount IS A NUMBER` falls under the same
column rule and the parser accepts it, but it is not the house style: the
formatter and `prettyLayout` re-emit the indented form. A `GIVEN` written
_before_ an `AKA` on the heading line does not parse; put the `AKA` first.

## Which rules can see it

- A section `GIVEN` on a heading covers every definition in every section
  beneath it.
- **The same name declared by two sections declares two different things.** Two
  sections that each declare `foo` are talking about two separate names, each
  read by its own section and its descendants — exactly as two `ASSUME`s or two
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
  `reader two` MEANS foo          -- section 2's foo, a different name

  §§ `5`
  GIVETH A Fruit
  `reader five` MEANS foo         -- error: which foo?
  ```

- A child section that re-declares an ancestor's name takes precedence **inside
  its own subtree**; the ancestor's name is unchanged everywhere else.
- A section `GIVEN` is visible upward and sideways whenever it is the only
  candidate: one declared on `§§ 1` is readable from `§§ 2` if `§§ 2` declares
  none of its own.
- A rule that reaches two same-named section `GIVEN`s at once is an error, and
  the message names both candidates by their declaring section
  (``toplevel.`1`.foo``, ``toplevel.`2`.foo``). Two ways out today, each saying
  something different about the drafting: **hoist** the `GIVEN` to a common
  ancestor heading if it is one thing; **rename** one of them if they are two.

  _Proposed, not landed (2026-09-04): a third way out, **bridging at the point
  of use** — `g WITH foo IS foo`, meaning "for this use, this section's `foo` is
  the one the other section means". Supplying a name with `WITH` does not work
  today: written after a bare rule name, L4 reports a check error (it is trying
  to apply something that is not a function to named inputs), and written after
  a rule that already has its values it is a parse error at `WITH`. It lands
  with the discharge pull request; until then, hoist or rename._

## The dedent hazard

A paste or a hand-edit that pushes a section `GIVEN` back to column 1 turns it
into an input of the declaration below it, silently — L4 rewrites a
declaration head that takes no inputs so that it takes the `GIVEN`'s names
instead, which is what makes an ordinary rule signature work at all.

Where the declaration below makes **no use of the name at all** — and it is a
`DECLARE` or an `ASSUME`, which is where the mistake actually bites — that is a
check error. The message below is L4's own wording, quoted verbatim;
it says "binder" for what this page calls a section `GIVEN`:

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

The check does not extend to `DECIDE`, because a rule that does not use one of
its own inputs is a perfectly ordinary thing to write and is indistinguishable
from a dedented section `GIVEN`; five files in this repository do exactly that
today.

A `GIVEN` at column 1 followed by another `§` heading is a parse error.

The formatter never moves a `GIVEN` across the column boundary, so formatting
cannot introduce the hazard.

## What a section `GIVEN` does in this release

**In this release a section `GIVEN` behaves as an assumed term, exactly like
`ASSUME`.** A rule that reads one cannot be run to an answer until the name is
supplied; `#EVAL` on such a rule reports

```
I could not continue evaluating, because I needed to know the value of
  `applicable rate`
but it is an assumed term.
```

_Proposed, not landed (2026-09-04): supplying a section `GIVEN` at the point of
use, and the discharge that works out which names an entry point reads and asks
for exactly those. Both land with the discharge pull request; until then values
arrive from outside the file (web form, `l4 batch`, application programming
interface)._

What does work today:

- **The list of facts a published rule asks for.** A name that an `@export`ed
  rule reads — directly or through anything it relies on — becomes a required
  request input, carrying its `@desc` if it has one and its `TYPICALLY` value as
  the JavaScript Object Notation (JSON) Schema `default`. (A name with a
  `TYPICALLY` value is still listed under `required`; making it optional is
  separate, later work.)
- **`l4 batch` and `jl4-service`**, which supply the names a rule reads from the
  request the same way they supply a read `ASSUME`.
- **Every export backend** — Decision Model and Notation (DMN), Business Process
  Model and Notation (BPMN), docassemble, Catala, OpenFisca, Blawx and the
  Multi-Level Intermediate Representation (MLIR) — treats a section `GIVEN` as
  it treats an `ASSUME` term.
- **Diagnostics and hover**, which point at the `GIVEN` line under the heading
  (a "defined at" note names that line, and hovering the parameter shows its
  type). Go-to-definition and find-references have not been exercised on a
  section `GIVEN` in this release.

A name with no type (`GIVEN a`) is accepted and behaves as `ASSUME a` does. A
name declared `IS A TYPE` stands for a kind of thing the model treats as opaque,
declared for the section on the same visibility rules as any other section
`GIVEN`, exactly as `ASSUME a IS A TYPE` does at module level; prefer `DECLARE`
for that.

Whether a section `GIVEN` crosses an `IMPORT` is whatever `ASSUME` does today,
which this release does not change and does not assert.

## Example

[section-given-example.l4](section-given-example.l4)

## See also

- [`ASSUME`](../types/ASSUME.md) — the same idea for a single name, at module level
- [`GIVEN`](../functions/GIVEN.md) — the inputs of one rule
- [Section markers (§)](README.md#section-markers-)
- [Sections](sections.md) — the full visibility rule for nested and sibling sections, qualified names, and the ambiguity error
