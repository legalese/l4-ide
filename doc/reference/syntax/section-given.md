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
in this repository, roughly half of all `GIVEN` slots repeat a name and kind
of thing already used elsewhere in the same section — the rules of a section
are usually about one thing (an issuer, a will, an applicant), and each one
has to say so again.

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
column rule and L4 accepts it, but it is not the house style:
`prettyLayout` re-emits the indented form (`l4 format` leaves it as written). A
`GIVEN` written _before_ an `AKA` on the heading line is rejected; put the
`AKA` first.

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
  (``toplevel.`1`.foo``, ``toplevel.`2`.foo``). Three ways out today:
  **qualify** the use by naming its section (``toplevel.`1`.foo``); **hoist**
  the `GIVEN` to a common ancestor heading if it is one thing; **rename** one of
  them if they are two.

  _Proposed, not landed (2026-09-04): a fourth way out, **bridging at the point
  of use** — `g WITH foo IS foo`, meaning "for this use, this section's `foo` is
  the one the other section means". Supplying a name with `WITH` does not work
  today: written after a bare rule name, L4 reports a check error (it cannot
  apply a rule that takes no inputs to named ones), and written after
  a rule that already has its values it is rejected at `WITH`. It lands
  with the discharge pull request; until then, qualify, hoist or rename._

## One name, several types

A section `GIVEN` may bind the same name **more than once, at different types**.
Each occurrence then resolves to whichever of them its context demands — the
same type-directed name resolution that several module-level `ASSUME`s of one
name already get (`jl4/examples/ok/tdnr.l4`).

```l4
§ `Fees`
    GIVEN `late fee` IS A NUMBER
          `late fee` IS A STRING

GIVETH A NUMBER
`fee due` MEANS `late fee` TIMES 2      -- the NUMBER binder

GIVETH A STRING
`fee label` MEANS `late fee`            -- the STRING binder
```

This is a drafting idiom to reach for sparingly: a reader who cannot see the
types cannot see which binder a rule means, and a use site whose context settles
nothing is a "multiple definitions" error naming both candidates. It is
supported because the `ASSUME`s a section binder replaces support it, and a
migration that lost it would silently change which programs compile.

**Limit.** A section that binds a name on its heading and _also_ writes its own
`ASSUME` of that name in its body type-checks, but does not survive being
re-printed: the printer treats the hand-written `ASSUME` as the binder's own and
drops it, so `l4 batch` and the REPL rebuild a module that has lost it. Write
the second binding as another `GIVEN` parameter on the heading instead.

## The dedent hazard

A paste or a hand-edit that pushes a section `GIVEN` back to column 1 turns it
into an input of the declaration below it, silently — which is exactly how an
ordinary rule's inputs are written, so nothing looks wrong.

Where the section's **first** declaration makes **no use of the name** — and
it is a `DECLARE` or an `ASSUME`, where the mistake bites — that is a
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

The check does not extend to an ordinary rule (`MEANS`, `DECIDE`): a rule that
does not use one of its own inputs is an ordinary thing to write and is
indistinguishable from a dedented section `GIVEN`; five files here do exactly
that today.

A `GIVEN` at column 1 followed by another `§` heading is rejected outright. The
formatter never moves a `GIVEN` across the column boundary, so formatting
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
  (a "defined at" note names that line, and hovering the name shows the kind
  of thing it stands for). Go-to-definition and find-references have not been
  exercised on a section `GIVEN` in this release.

A name with no kind of thing after it (`GIVEN a`) is accepted and behaves as
`ASSUME a` does. A name declared `IS A TYPE` stands for a kind of thing the
model treats as opaque, declared for the section on the same visibility rules
as any other section `GIVEN`, exactly as `ASSUME a IS A TYPE` does at module
level; prefer `DECLARE` for that.

Whether a section `GIVEN` crosses an `IMPORT` is whatever `ASSUME` does today,
which this release does not change and does not assert.

## Example

[section-given-example.l4](section-given-example.l4)

## See also

- [`ASSUME`](../types/ASSUME.md) — the same idea for a single name, at module level
- [`GIVEN`](../functions/GIVEN.md) — the inputs of one rule
- [Section markers (§)](README.md#section-markers-)
- [Sections](sections.md) — the full visibility rule for nested and sibling sections, qualified names, and the ambiguity error
