# TYPICALLY

Attaches a default value to a name. The default is a _rebuttable presumption_:
it records what should be presumed when nobody supplies a value, and a rule that
is given no value uses it.

## One behaviour

`TYPICALLY d` on a name means one thing.
When nothing supplies a value for the name, at the point where a value has to come from outside the rule, the rule uses `d`.
That holds wherever the name is declared, and in every tool that runs rules: `#EVAL` and `l4 run`, `l4 batch`, and the decision service, except for the [limits at the boundary](#at-the-boundary-l4-batch-and-the-decision-service), where a tool differs from `#EVAL` and the section says how.
Three places accept a `TYPICALLY` and no run of the rules uses it: an `ASSUME`, which is deprecated ([below](#on-an-assume-checked-and-recorded-not-used)); a lambda's own `GIVEN`; and a field of an enum constructor that carries data ([below](#on-a-record-field-leaving-a-field-out-of-a-construction)).

Three things hold wherever a `TYPICALLY` is written:

- **A value that is supplied wins.** A default is never an override.
- **"Not known" is not "left out".** At the boundary, `null` says that the fact is not known, and a fact that is not known never takes its default.
- **Inside a file, a call or a construction by position gives every input and every field.** There is nothing left for a default to fill, so only a call or a construction that names its inputs with [`WITH`](../functions/WITH.md) may leave one out.

What differs from one place to the next is only how a name comes to be left out:

| `TYPICALLY` is written on | it is left out when                                                                                                       | for example              |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ------------------------ |
| a section `GIVEN`         | a rule reads the name and the call, or the case, gives it no value; at the boundary, the case does not mention it         | `doubled`                |
| a rule's own `GIVEN`      | a call that names the rule's inputs with `WITH` leaves it out; at the boundary, the case does not mention it              | `scaled WITH base IS 10` |
| a record field            | a construction that names the fields with `WITH` leaves the field out; at the boundary, the JSON object has no key for it | `Paint WITH coats IS 2`  |

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
   names, which are checked and recorded and not used (see
   [below](#on-an-assume-checked-and-recorded-not-used)). `ASSUME` is
   deprecated (ruled 2026-09-04) and still works; a fact supplied for each case
   belongs under its section's heading instead. See
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
  declares it and in a file that imports it alike (see
  [below](#on-an-assume-checked-and-recorded-not-used)).

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

## On an `ASSUME`: checked and recorded, not used

[`ASSUME`](ASSUME.md) is deprecated (ruled 2026-09-04) and is being retired.
A `TYPICALLY` on one is checked against the type, as anywhere else, and kept, and no run of the rules uses it:

```l4
ASSUME `person has capacity` IS A BOOLEAN TYPICALLY TRUE

GIVEN `is adult` IS A BOOLEAN
GIVETH A BOOLEAN
`may contract` MEANS `is adult` AND `person has capacity`

#EVAL `may contract` TRUE     -- `person has capacity`, the bare name: not TRUE
```

- **`#EVAL` and `l4 run`** get the name back, with the deprecation warning, where a section `GIVEN` would give `TRUE`.
- **`l4 batch` and the decision service** still ask for the fact.
  The published list of facts has it under `required`, with no `default`.
  `l4 batch` refuses a case that leaves it out (`Missing required field 'person has capacity' in JSON object`), and so does the service's direct path (`ASSUME 'person has capacity': missing required parameter`).
  The service's other path, for a request that sends `{}` for any input, treats the fact as an assumed term instead: the request is answered when the rules never read it, and stops, saying the fact is an assumed term, when they do.
- **An input of an `ASSUME` that takes inputs** is the same.
  A call that names the inputs and leaves out one that has a `TYPICALLY` is told it has not supplied it, in the file that declares the `ASSUME` and in a file that imports it.
- **The question wizard still reads it.**
  The ladder the service publishes carries a boolean default on an `ASSUME` as the fact's presumed value, and the query plan uses it as a prior, as it does for a section `GIVEN`.
  They order the questions and draw a tentative answer, and never answer for the rules, so for an `ASSUME` they presume a value that no evaluation uses.

To make the default count, move the declaration under its section's heading, as a section `GIVEN`.
The same rule then works out `TRUE`, `l4 batch` and the service take the default and list it under `presumed`, and the default may be an expression.
That changes the answer, so it is more than a respelling.
The `GIVEN` line the deprecation warning suggests carries the `TYPICALLY` across.

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
price is 180. Because the answer needs `list price` whenever it needs the
`discount`, a published rule asks for `list price` too (see below).

**Where a `WITH` reaches.** An evaluation is started at a _root_: a directive
(`#EVAL`, `#ASSERT`), or the call that `l4 batch` or the decision service makes. A
`WITH` at a root reaches a default, as above, even for a rule that reads
`discount` only through another rule. A `WITH` written _inside_ a rule does not:
it reaches only what the rule it calls reads in its own body, or through the rules
that one calls, because `discount`'s default is worked out at the root, from the
root's values. A `WITH` inside a rule that names `list price`, for a rule that
reaches it only through `discount`, is refused, as one that would do nothing.

A root is a matter of where a call is _written_, not of where it runs. Everything
written inside a directive is at the root, a lambda there included, and nothing
written inside a rule is. So ``#EVAL `final price` WITH `list price` IS 1000`` is
900, while the same call written as a rule,
`` `priced as if dearer` MEANS `final price` WITH `list price` IS 1000 ``, is 990,
which takes `discount` from the root's own `list price`, and an `#ASSERT` that
compares the two fails. Whether a root should be where an evaluation starts
instead is not settled.

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
- **It cannot name the rule's other inputs, or a record's other fields.** A
  default is worked out where those are not known, so `rate TYPICALLY (base PLUS 1)`
  is reported as naming something that does not exist. When the file also defines
  something called `base`, the name would quietly mean that, so it is a check error
  all the same, naming the name: rename one of the two, or write the name with its
  section (`` `Rates`.base ``), which says which it means.

A name in a default means what it means where the default is written: a section's
own definition outranks the file's of the same name, for a rule's input and for a
record's field alike.

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
- **On an `ASSUME` it is not used** (see
  [above](#on-an-assume-checked-and-recorded-not-used)), and must be a fixed
  value; a section `GIVEN` is where a default counts and may be an expression.

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
  takes its default. `l4 batch` and the service's direct path refuse the case,
  naming the fact. The service's other path, for a request that sends `{}` for any
  input, treats the fact as an assumed term, as it does one left out that has no
  default: the request is answered when the rules never read it, and stops, saying
  the fact is an assumed term, when they do. `{}` means the same as `null`, for a
  record too.
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

Limits on a default that is an expression, at the boundary:

- **Under `hard`, a fact that only a default reads is still asked for.** Nothing
  reads that default under `hard`, so the fact is never used, but the published
  list does not change with the mode, and a case that leaves it out is refused,
  naming it.
- **`l4 batch` writes each default into the module it generates as text**, and so
  does the decision service for a request that sends `{}` for any input (its other
  path works the default out from the checked expression and is not affected). The
  text is put after the last section and read again there, so a name in it must
  mean the same there. A name that is defined in a section and also defined at the
  top level, or in another section, would mean another definition there, with no
  message: with `phi` defined in `§ Rates` and again in a later `§ Other`,
  `rate TYPICALLY (phi PLUS 1)` on an exported rule in `§ Rates` would be 9 at
  `#EVAL` and 10 through `l4 batch`. So an exported rule's input may not take a
  default that names one, and neither may a section input that an export reads:
  the file is refused when it is checked, naming the name. Written with its
  section (`` `Rates`.phi ``), the name means the same on every path, and nothing
  is refused. The check does not look at types, so it also refuses a name that two
  sections define for different types, where the answers would agree, and one
  whose own section is the last; two definitions of one name in the same section
  are left alone.
- **A default is published in the spelling the checker prints**, not the
  author's: a name is unqualified and backticked where needed (one the author
  wrote with its section keeps it), and a call that names its inputs is written on
  one line, comma-separated. Two operators that share their leading words are
  printed by those words alone, so the text can name neither; `l4 batch` refuses
  such a default, loudly.
- **The query plan does not ask for a fact that only an expression default
  reads**, although the published list requires it. The plan orders the questions
  that decide the answer, and what a default reads is not among them, so a client
  that answers every question the plan asks can still be refused for a missing
  fact. Give the fact a default, or ask for it yourself.
- **A default that supplies an input the export also reads is not run
  everywhere.** A default such as
  `` `base doubled` TYPICALLY (`double it` WITH base IS 10) ``, in a file whose
  export also reads `base`, is fine at `#EVAL`. `l4 batch` refuses every row: it
  binds `base` to the row, and a `WITH` to a bound input is not a supply. The
  decision service answers a request that leaves `base` out, or that supplies
  `base doubled`, and stops with an internal error for one that supplies `base`
  and leaves `base doubled` out: "named application supplying an implicit input
  reached the evaluator undischarged ... This is a compiler bug". The `l4 batch`
  limit is older than expression defaults: any `WITH` on a section input, inside
  an exported rule's body, does the same.

The list of facts a published rule asks for carries each default as the
JavaScript Object Notation (JSON) Schema `default` keyword, and a defaulted fact
is not listed under `required`. A `TYPICALLY` on an `ASSUME` is not used here
either: the service's schema leaves it out, and the fact stays under `required`.

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
default is checked and recorded and no rule uses it, nor the default of an input
of an `ASSUME` that takes inputs; moving the declaration under its section's
heading, as the previous example does, is what makes the default take effect for
a rule given no value. The companion file does not use this spelling, because it
draws a deprecation warning.

## Behavior

- A default is used where the name is left out, and nowhere else: a value
  supplied always wins, and `null` (not known) is never an omission.
- The default must match the annotated type, or type checking fails.
- The default is a fixed value like `18` or `"yes"`, or an expression over what
  the file declares, which is worked out when something reads it. An `ASSUME`
  and a lambda's `GIVEN` take only a fixed value.
- A call that gives its inputs by position, and a construction that gives its
  fields by position, give all of them: only `WITH` may leave one out.
- On a computed field (one with a MEANS clause) a TYPICALLY is an error.
- A default that reads the input it stands in for, directly or through another
  default or a definition, is a check error.
- On an `ASSUME` a `TYPICALLY` is checked and recorded, and no run of the rules
  uses it.

## What changed

Earlier versions of L4 took a `TYPICALLY` only on a section `GIVEN`, and only inside a file.
On a rule's own `GIVEN` and on a record field it was a note that no evaluation used, so a call or a construction that left such a name out was an error.
A default had to be a fixed value wherever it was written.
A `TYPICALLY` on a computed field, which never did anything, is now a check error.
An `ASSUME` is as it was.

At the boundary, `l4 batch` refused a case that left out a fact with a default, a section `GIVEN`'s included (`Missing required field 'has capacity' in JSON object`), and the published list of facts asked for every defaulted fact under `required`.
A case may now leave it out.
The answer lists the default it took under `presumed`, the published list leaves the fact out of `required` and carries its `default`, and `l4 batch --presumption hard`, or `"presumption": "hard"` in a request, brings the refusal back (see [At the boundary](#at-the-boundary-l4-batch-and-the-decision-service)).
A client that relied on the refusal, or on `required`, will now get an answer, or a list that does not ask for the fact.

## See Also

- [ASSUME](ASSUME.md) — declaring assumed values (deprecated, still works)
- [The section `GIVEN`](../syntax/section-given.md) — declaring a name once for a
  whole section
- [WITH](../functions/WITH.md) — supplying, and overriding, an input by name
- [DECLARE](DECLARE.md) — declaring record types
- [GIVEN](../functions/GIVEN.md) — the inputs of one rule
- [Query Planning](../query-planning/README.md) — how a stored default becomes
  the per-atom prior `w_v` for the question-ordering wizard
- [Exports](../../exports/README.md) — the Catala, docassemble and Blawx pages
  say what each does with a default
- [Web Form Generation](../../courses/advanced/module-a4-production.md#web-form-generation)
  — using TYPICALLY defaults in an autogenerated wizard
