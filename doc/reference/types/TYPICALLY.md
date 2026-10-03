# TYPICALLY

Attaches a default value to a name. The default is a _rebuttable presumption_:
it records what should be presumed when nobody supplies a value, and a rule that
is given no value uses it.

It is used wherever the name is left out:

- **on a section `GIVEN`**, by every rule that reads the name and is given no
  value for it;
- **on a rule's own `GIVEN`**, by a call that names its inputs with
  [`WITH`](../functions/WITH.md) and leaves this one out;
- **on a record field**, by a construction that leaves the field out; and
- **at the boundary**, `l4 batch` and the decision service, by a case that
  leaves the fact out.

Each is described below, with what a default does _not_ excuse.

## Syntax

```l4
name IS A Type TYPICALLY default
```

The **`default`** is a number, a piece of text, a bare name (`TRUE`, `NOTHING`, a
constructor of an enumeration, or the name of a definition), or any other
expression in parentheses: `TYPICALLY (list price DIVIDED BY 10)`. See
[A default that is worked out](#a-default-that-is-worked-out).

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

## On a section `GIVEN`

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

## On a rule's own `GIVEN`: leaving an input out of a `WITH` call

A call that names its inputs with `WITH` may leave out an input that has a
default. The call takes the default:

```l4
GIVEN rate IS A NUMBER TYPICALLY 3
      base IS A NUMBER
GIVETH A NUMBER
scaled MEANS rate TIMES base

#EVAL scaled WITH base IS 10                 -- 30: `rate` takes its default, 3
#EVAL scaled WITH base IS 10, rate IS 2      -- 20: a value the call gives wins
```

- **Only a call that names its inputs.** `scaled 10`, which gives its inputs by
  position, still has to give all of them: it is told it "expects 2 inputs, but
  here it is given 1". A position says which input a value is for only if every
  input before it has been given, so a gap cannot be left.
- **An input with no default is still asked for.** `scaled WITH rate IS 1` is
  told it has not supplied `base`, and a name the rule does not have is still an
  error, so a misspelling of `rate` is not read as a default taken. The one
  misspelling this cannot catch is a name that is itself something else the rule
  reads, a section `GIVEN` that the call may override (`ratee`, where the rule
  reads a section input of that name). That is a valid override, and `rate` then
  takes its default.
- **The default is used only if the rule reads it.** A rule that never needs the
  input never forces its default, which is also what `presumed` (below) counts.

This works for a rule in the same file, a rule declared in a `WHERE`, and a rule
in a file you `IMPORT`. Two things it does not do:

- **It does not choose between rules of the same name.** When two rules share a
  name and each could take the call's inputs, a call that leaves out an input
  with a default is still ambiguous, as it was before, and has to name every
  input of the one it means. A default is not allowed to decide which rule the
  author meant. A rule that shares its name with a record field is not in this
  case: a field takes no named inputs, so the call can only mean the rule.
- **It does not reach an `ASSUME`.** An `ASSUME` that takes inputs (`ASSUME` is
  deprecated) keeps its inputs' `TYPICALLY` as a note only, in the file that
  declares it and in a file that imports it alike.

## On a record field: leaving a field out of a construction

A record is built with `WITH` too, and may leave out a field that has a default:

```l4
DECLARE Colour IS ONE OF Red, Green

DECLARE Paint
  HAS colour IS A Colour TYPICALLY Red
      coats  IS A NUMBER
      note   IS A MAYBE STRING TYPICALLY NOTHING

GIVETH A Paint
fresh MEANS Paint WITH coats IS 2

#EVAL fresh's colour        -- Red
#EVAL fresh's note          -- NOTHING
```

The same limits apply as for a rule's input: a field with no default must still
be given, and `Paint OF 2` (by position) must give every field. The record may
be declared after the rule that builds it, and in a file you `IMPORT`.

Three things are not offered, and each is an error or unchanged rather than a
quiet choice:

- **A construction that leaves out _every_ field.** There is no way to write it
  yet; how it should be spelled is an open question, so none is invented.
- **A field of an enum constructor that carries data**, an alternative under
  `ONE OF` such as `Circle HAS radius IS A NUMBER`, still has to be given, even
  when it carries a `TYPICALLY`.
- **A computed field**, one with a `MEANS` clause, cannot carry a `TYPICALLY`
  at all: its value always comes from the `MEANS`, so a default could never be
  used. That is a check error.

## A default that is worked out

A default does not have to be a fixed value. On a section `GIVEN` it can be any
expression over what the file declares: a definition, a constructor, or another
section `GIVEN`. On a rule's own `GIVEN` or a record field it can be one over
definitions and constructors (see below).

```l4
GIVETH A NUMBER
phi MEANS 8

§ `Pricing`
    GIVEN `list price` IS A NUMBER TYPICALLY 100
          discount IS A NUMBER TYPICALLY (`list price` DIVIDED BY 10)

GIVETH A NUMBER
`final price` MEANS `list price` MINUS discount

#EVAL `final price`                                          -- 90
#EVAL `final price` WITH `list price` IS 200                 -- 180
#EVAL `final price` WITH `list price` IS 200, discount IS 5  -- 195
```

A compound expression is written in parentheses, which is how every operand
after `TYPICALLY` is written; a literal or a bare name needs none.

**On a section `GIVEN`**, the default is worked out when something reads the
input, from the values the evaluation was started with, and once, like any other
default. In the second line above, `WITH `list price` IS 200` reaches
`discount` as well: the discount is a tenth of the 200 the call gave, so the
price is 180. A rule that reads `discount` only through another rule is still
told which inputs it needs, so a `WITH` that names `list price` for it is
accepted. Because the answer needs `list price` whenever it needs the
`discount`, a published rule asks for `list price` too (see below).

**A default may not depend on itself.** `a TYPICALLY (b PLUS 1)` with
`b TYPICALLY (a PLUS 1)` cannot be worked out, and neither can a default that
reads its own input directly, or through a definition it calls. That is a check
error that names the inputs on the circle. A default that _supplies_ the input
it would otherwise read, such as `` `base doubled` TYPICALLY (`double it` WITH
base IS 10) ``, reads nothing of it and is no circle.

**On a rule's own `GIVEN` and on a record field**, a default may be an expression
over the file's definitions and constructors, and it is worked out where the call
or the construction is, as if it were written there. With
`rate TYPICALLY (phi PLUS 1)`, the call `scaled WITH base IS 10` means
`scaled WITH base IS 10, rate IS (phi PLUS 1)`. Two limits:

- **It may not read a section `GIVEN`, directly or through a definition it
  calls.** That is a check error naming the input. A section `GIVEN`'s default is
  worked out once, from the values the whole evaluation was started with. A
  default on a rule's input or a record field is copied to each call that leaves
  it out, so what it read there would depend on the call: inside a `WITH` that
  gives the same input another value, at a `#EVAL` that gives it, or in a case
  sent to `l4 batch` or the service, and the one default could give different
  answers. Which of those should win is not settled, so none is chosen. Give the
  default to the section `GIVEN` instead, or write one that reads only
  definitions that read no section input. A default that _supplies_ the input it
  would read (`` `double it` WITH alpha IS 1 ``) reads nothing of it and is fine.
- **It cannot name the rule's other inputs.** `rate TYPICALLY (base PLUS 1)` is
  reported as naming something that does not exist, since a default is worked
  out where the rule's inputs are not yet known.

A default that calls the rule it belongs to, or builds the record it is a field
of, directly is a check error ("you have not supplied these inputs"). One that
does so through another rule is not checked: if the call forces the default again
it runs out of stack ("Recursion depth of 1000000 exceeded"), as any rule that
calls itself without an end does.

Two places never work a default out, and keep asking for a fixed value: an
`ASSUME` (deprecated; its default is not used) and a lambda's own `GIVEN`.

## What the default must be

A default is checked when it is written:

- It is type-checked against the annotated type
  (`x IS A BOOLEAN TYPICALLY 42` is a type error).
- It is a number, a piece of text, a bare name such as `TRUE`, `FALSE`,
  `NOTHING`, a constructor of an enumeration
  (`colour IS A Colour TYPICALLY Red`) or a definition, or an expression in
  parentheses (`x IS A BOOLEAN TYPICALLY (a AND b)`), on a section `GIVEN`, a
  rule's `GIVEN` or a record field; on the last two it may not read a section
  `GIVEN`. A default that names something that does not exist is reported once,
  as that.
- It requires an explicit type: the name must carry an `IS A Type` annotation so
  the default can be checked (`GIVEN x TYPICALLY 5` with no type is an error).
- It cannot appear on a name that stands for a **kind of thing** rather than a
  value: `ASSUME Foo IS A TYPE TYPICALLY 42` is an error.
- **On an `ASSUME` it is still not used** ([`ASSUME`](ASSUME.md) is deprecated),
  and must stay a fixed value; move the declaration under its section's heading
  to make the default count, and to be allowed an expression.

## At the boundary: `l4 batch` and the decision service

A case sent to `l4 batch`, or a request sent to the decision service, may leave
out any fact that has a default, whether the `TYPICALLY` is on a section
`GIVEN`, on the exported rule's own `GIVEN`, or on a field of a record the rule
takes as an input. The default is filled in where the case arrives, and the
answer lists it under **`presumed`**, by name (or, for a field, by its path, such
as `config.timeout`) — but only if the answer actually used it. These rules
govern what counts as leaving a fact out:

- **Leaving the name out** is leaving it out. So is an empty cell in a CSV file
  given to `l4 batch`. A `MAYBE` fact with no default, left out, is `NOTHING`,
  and is listed under `presumed` like a default.
- **`null` is not.** `null` means _not known_, and a fact that is not known never
  takes its default: the case is refused, naming the fact. `{}` means the same,
  for a record too.
- **A name that matches nothing is refused where a default is taken.** In a
  case that leaves out a fact with a default, a name that is not a fact is
  refused, naming the nearest one, since it may misspell the fact left out.
  Where no default is taken, it is ignored.
- **The presumption can be switched off.** `l4 batch --presumption hard`, or
  `"presumption": "hard"` in a service request, uses no defaults: a fact left
  out is missing, and the case is refused, naming it. The default is `soft`.
  The switch reaches only the facts a case can supply. A record the rules
  decode from JSON of their own (`JSONDECODE`) still takes its defaults, and
  under `hard` the answer lists them under `presumed` as
  `JSONDECODE <type>: <field>`, because nothing the case says could replace
  them. The same is true of a default a `WITH` call or a construction _inside_
  the rules takes (see above): neither mode withdraws it, because no case could
  have supplied it. Under `hard` the answer lists it under `presumed` as
  `WITH <rule>: <input>` (for example `WITH scaled: rate`, or
  `WITH Config: timeout` for a field), naming the rule or record as its
  declaration writes it, and only if the answer actually used it. Under `soft`
  `presumed` lists the facts a case could have left out, and none of these.
- **An event's record in the decision service is not a place a default can
  be left out.** When a request for a rule that describes obligations replays
  events, each event's party or action record has to give every field, whether
  or not a field has a default, and so does a record nested inside it: the
  record is part of the request, and the service refuses one that leaves a
  field out.

Three limits on a default that is an expression, at the boundary:

- **Under `hard`, a fact that only a default reads is still asked for.** Nothing
  reads that default under `hard`, so the fact is never used, but the published
  list does not change with the mode, and a case that leaves it out is refused,
  naming it.
- **`l4 batch` writes each default into the module it generates as text**, and so
  does the decision service for a request that sends `{}` for an input nothing
  reads. A name in a default that two sections both define is then ambiguous, and
  the rows or the request are refused, naming both. The service's other path
  works the default out from the checked expression and is not affected. Written
  with its section (`` `Rates`.phi ``), the name is not ambiguous, on either path.
- **A default is published in the spelling the checker prints**, not the
  author's: a name is unqualified and backticked where needed, and a call that
  names its inputs is written on one line, comma-separated.

The list of facts a published rule asks for carries each default as the
JavaScript Object Notation (JSON) Schema `default` keyword, and a defaulted fact
is not listed under `required`. A `TYPICALLY` on an `ASSUME` is not used here
either, and is not published, in the service's schema or in the query plan's.

**A default that is an expression is published as its source text**, a JSON
string, whatever the fact's type: `"default": "`list price` DIVIDED BY 10"` for a
number. It is there to be read, not to be sent. A client that fills a missing
fact from the `default` it finds in a schema must not do that for one of these,
and for a fact of type text cannot tell it from a fixed value, so a client that
needs the value should leave the fact out and read the answer's `presumed`. The
service works the expression out itself, from the other facts in the same
request. A section `GIVEN` that a default reads is a fact of the published rule
too, and is listed under `required` unless it has a default of its own, because
the service cannot know that a request will not need it.

_Landed in stages (2026-10-02 and 2026-10-03). A **section** `GIVEN` may be left
out, and a rule that reads it then uses the default; the published list of facts
asks for a defaulted fact as optional, which the boundary then honours; a
**rule's own** `GIVEN` and a **record field** may be left out at a call that
names its inputs and at a construction; and a default may be an expression.
Still to come: nothing yet says how to write a construction that leaves out
every field._

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

A call by name may leave either of them out: `` `may purchase alcohol` WITH
age IS 21 `` takes `married` as `FALSE`.

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
default stays metadata, as does the default of an input of an `ASSUME` that takes
inputs; moving the declaration under its section's heading, as the previous
example does, is what makes the default take effect for a rule given no value.
The companion file no longer carries this spelling.

## Behavior

- A default is used where the name is left out, and nowhere else: a value
  supplied always wins, and `null` (not known) is never an omission.
- The default must match the annotated type, or type checking fails.
- The default is a fixed value like `18` or `"yes"`, or an expression over what
  the file declares, which is worked out when something reads it.
- A call that gives its inputs by position, and a construction that gives its
  fields by position, give all of them: only `WITH` may leave one out.
- On a computed field (one with a MEANS clause) a TYPICALLY is an error.
- A default that reads the input it stands in for, directly or through another
  default or a definition, is a check error.

## See Also

- [ASSUME](ASSUME.md) — declaring assumed values (deprecated, still works)
- [The section `GIVEN`](../syntax/section-given.md) — declaring a name once for a
  whole section
- [WITH](../functions/WITH.md) — supplying, and overriding, an input by name
- [DECLARE](DECLARE.md) — declaring record types
- [GIVEN](../functions/GIVEN.md) — the inputs of one rule
- [Query Planning](../query-planning/README.md) — how a stored default becomes
  the per-atom prior `w_v` for the question-ordering wizard
- [Web Form Generation](../../courses/advanced/module-a4-production.md#web-form-generation)
  — using TYPICALLY defaults in an autogenerated wizard
