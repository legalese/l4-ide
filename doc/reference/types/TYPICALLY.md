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
name IS A Type TYPICALLY literal
```

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
in a file you `IMPORT`. A default declared in a file you `IMPORT` stays with
that file: if its `TYPICALLY` value is edited, a call here that leaves the input
out takes the new value. Writing the input at the call, as
`scaled WITH base IS 10, rate IS 3`, pins it. Two things it does not do:

- **It does not choose between rules of the same name.** A default is not
  allowed to decide which rule the author meant. When the call's own inputs do
  not settle which of two rules it means, a call that leaves out an input with a
  default is ambiguous, as it was before, and has to name every input of the
  one it means ([below](#two-rules-with-the-same-name)). A rule that shares its
  name with a record field is not in this case: a field takes no named inputs,
  so the call can only mean the rule.
- **It does not reach an `ASSUME`.** An `ASSUME` that takes inputs (`ASSUME` is
  deprecated) keeps its inputs' `TYPICALLY` as a note only, in the file that
  declares it and in a file that imports it alike.

### Two rules with the same name

Two rules may share a name when their inputs tell them apart.
A call that names its inputs and leaves one out takes the default only if the call cannot mean any other rule of that name.
A rule **could not take** the call when a value the call gives does not fit the type of that rule's input of that name.
Nothing else rules a rule out.
It does not have to be complete: one that is missing an input, and has no default for it, could still take the call.
A name the call gives that the rule does not have does not rule it out either, because a misspelt input would otherwise make the rule with the right spelling look like the only choice.

1. **If a rule can take the call as written, with every input given, that is the rule meant.**
   No other rule's default is used against it, and the call means what it meant before `TYPICALLY` existed.
2. **Otherwise, if only one rule could take the call, it takes its defaults** for what the call left out.
3. **Otherwise, two or more rules could take the call and none is complete as written. No default is taken**, and the call is ambiguous.
4. **If no rule could take the call**, because a value it gives does not fit the input of that name in any of them, the call is an error and none is chosen. The message is the same "multiple definitions" one, since nothing settled the choice.

The values the call gives are what tell the rules apart.
Here the second `scaled` takes a `STRING` for `base`, and the call gives a number, so only the first `scaled` could take it:

```l4
GIVEN rate IS A NUMBER TYPICALLY 3
      base IS A NUMBER
GIVETH A NUMBER
scaled MEANS rate TIMES base

GIVEN base IS A STRING
      factor IS A NUMBER
GIVETH A NUMBER
scaled MEANS factor

#EVAL scaled WITH base IS 10      -- 30: only the first `scaled` could take it
```

Here one rule takes the call as written, and the other would take it only by a default, so the first rule is not chosen on the strength of its default:

```l4
GIVEN a IS A NUMBER
      b IS A NUMBER TYPICALLY 1
GIVETH A NUMBER
f MEANS a PLUS b

GIVEN a IS A NUMBER
GIVETH A NUMBER
f MEANS a TIMES 100

#EVAL f WITH a IS 5               -- 500: the second `f` takes `a` as written
```

Here both rules take a number for `base`, and the second needs a `factor` that the call does not give.
A default of the first rule is not allowed to decide that the author meant the first:

```l4
GIVEN rate IS A NUMBER TYPICALLY 3
      base IS A NUMBER
GIVETH A NUMBER
scaled MEANS rate TIMES base

GIVEN base IS A NUMBER
      factor IS A NUMBER
GIVETH A NUMBER
scaled MEANS base PLUS factor

#EVAL scaled WITH base IS 10      -- error: both `scaled` could take this call
```

A name that only one rule has does not settle the choice either.
If the second `scaled` took `width` and `height` and had no `base`, the call `scaled WITH base IS 10` would still be ambiguous: it does not say which rule it means.

One more limit, chosen to keep the check fast and not ruled on.
A value that itself contains a call that names its inputs is not compared with the other rule's types, and a record built with `WITH` is such a call.
So `scaled WITH base IS (double WITH x IS 5)` stays ambiguous, although the number it gives would settle the choice.
A value that is a positional call (`double 5`) is compared, and so is a name: give the value a name with `WHERE` first, and write that name in the call.
Without this limit the time to check calls inside calls grew several-fold with every level.

There are two ways to settle a call that is still ambiguous.
Write the input that has the default (`scaled WITH base IS 10, rate IS 3`): the call is then complete as written for the first rule and not for the second, so the first is the rule meant (rule 1 above).
Or, when the two rules sit under different section headings, name the one you mean: `` `Pricing`.scaled WITH base IS 10 ``.
When the rules sit in the same section, only the first way is open.

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

A construction that leaves out _every_ field is written `Paint WITHAL`, which takes each field's default and writes none; see [`WITHAL`](WITHAL.md).
It is an error when any field has no default, and the error names each one.

Two things are not offered, and each is an error or unchanged rather than a
quiet choice:

- **A field of an enum constructor that carries data**, an alternative under
  `ONE OF` such as `Circle HAS radius IS A NUMBER`, still has to be given, even
  when it carries a `TYPICALLY`.
- **A computed field**, one with a `MEANS` clause, cannot carry a `TYPICALLY`
  at all: its value always comes from the `MEANS`, so a default could never be
  used. That is a check error.

## In rendered text: `l4 nlg` and `l4 render`

Someone reading rendered text never sees the source.
`` `scaled` where `base` is 10 and `rate` is 3 `` would tell that reader that the author stipulated the 3, when the author wrote only `scaled WITH base IS 10` and the 3 is the default declared on `rate`.
So a value the checker added is marked as one:

- **In a sentence**, `l4 nlg` and `l4 render` print `` `rate` is 3 by default ``.
- **In a list of fields**, `l4 render` prints `- rate — 3 (by default)`. A rule whose whole body is the call, and a record construction, print this way.
- **In a table**, `l4 render` prints `red (by default)` in each cell the checker filled in, and nothing in the cells the author wrote. A column that holds both is marked cell by cell.
- **In the document JSON** (`l4 render --format json`), the mark is part of the text of the value, `"3 (by default)"`. No key was added, so the shape of the document is the same.

A value you wrote is never marked, whatever it equals: `scaled WITH base IS 10, rate IS 3` prints `` `rate` is 3 ``.

What the mark does and does not tell you:

- **It covers a default added at a call that names its inputs, or at a construction.** Those are the two places where a call or a construction that the author wrote gets a value the author did not write.
- **It does not cover a default taken at the root of a section `GIVEN`.** With `surcharge TYPICALLY 2` on a section `GIVEN`, `` `tax on` WITH amount IS 10 `` prints as `` `tax on` where `amount` is 10 is equal to 12 ``, and the 2 is not in the text. Written at the call, `surcharge IS 7` is printed.
- **No mark does not mean that no default was used.** The defaults an answer used are listed under `presumed` when it comes from `l4 batch` or the decision service (see [At the boundary](#at-the-boundary-l4-batch-and-the-decision-service) below): a section `GIVEN` default the case left out, a field default in a record the rules decode with `JSONDECODE`, and, in either mode, one added at a call or a construction inside the rules. The evaluation trace prints the value that was used (`scaled OF 3, 10`) and does not yet say it was a default.
- **The words are English in `l4 render`, whatever `--lang` says.** `l4 nlg --lang he` prints `כברירת מחדל` from a draft entry in its table of Hebrew phrases, which no Hebrew-speaking lawyer has reviewed, and `l4 render` does not use that table yet ([the syntax reference](../syntax/README.md) says so).

## What the default must be

A default is checked when it is written, and has to be a fixed value:

- It is type-checked against the annotated type
  (`x IS A BOOLEAN TYPICALLY 42` is a type error).
- It must be a fixed value written out: a number, a piece of text, or a bare
  name such as `TRUE`, `FALSE`, `NOTHING` or a constructor of an enumeration
  (`colour IS A Colour TYPICALLY Red`). `x IS A BOOLEAN TYPICALLY (a AND b)` is
  an error. A default that names something that does not exist is reported once,
  as that.
- It requires an explicit type: the name must carry an `IS A Type` annotation so
  the default can be checked (`GIVEN x TYPICALLY 5` with no type is an error).
- It cannot appear on a name that stands for a **kind of thing** rather than a
  value: `ASSUME Foo IS A TYPE TYPICALLY 42` is an error.
- **On an `ASSUME` it is still not used** ([`ASSUME`](ASSUME.md) is deprecated);
  move the declaration under its section's heading to make the default count.

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
  for a record too. The one exception is a `MAYBE` fact, which is allowed to
  have no value: `null` on it is `NOTHING`, a value, and nothing is presumed or
  refused.
- **A name that matches nothing is refused where a default is taken.** In a
  case that leaves out a fact with a default, a name that is not a fact is
  refused, naming the nearest one, since it may misspell the fact left out.
  Where no default is taken, it is ignored.
- **The presumption can be switched off.** `l4 batch --presumption hard`, or
  `"presumption": "hard"` in a service request, uses no default for a fact the
  case leaves out: that fact is missing, and the case is refused, naming it. The default is `soft`.
  The switch reaches only the facts a case can supply. A record the rules
  decode with `JSONDECODE` still takes its defaults, whether the JSON is
  written in the rules or is text the case sent, and in either mode the answer
  lists them under `presumed` as `JSONDECODE <type>: <field>`: the switch does
  not withdraw them. The type is named as it is declared, behind the section
  heading it is declared under (`JSONDECODE Pricing.Settings: limit`), whichever
  way the rule wrote the type at the decode. A record declared under a heading
  in an _imported_ file is the exception: it is named without the heading
  (``JSONDECODE `Paint Order`: coats``), though its `WITH` entry has it. A `MAYBE` field with no `TYPICALLY` that the decoded JSON
  leaves out is filled with `NOTHING` and listed the same way
  (`JSONDECODE Partial: note`), in both modes. The same is true of a default a `WITH` call or a construction _inside_
  the rules takes (see above): neither mode withdraws it, because no case could
  have supplied it. The answer lists it under `presumed` as
  `WITH <rule>: <input>`, naming the rule or record as its declaration writes
  it, behind the section it is declared in: `WITH Pricing.scaled: rate`, or
  `WITH Pricing.Config: timeout` for a field, for a rule and a record in
  `§ Pricing`, and `WITH scaled: rate` for a rule at the top of the file, which
  has no section to name. Two rules of one name in different sections are two
  entries. A part that L4 would write in backticks in source is written in
  backticks, with or without a section in front of it: any name with a space,
  a dot, a hyphen or an apostrophe in it, one that starts with a digit, and a
  reserved word (``WITH `Part 1. Fees`.scaled: rate``, ``WITH `two words`: rate``
  for a rule at the top of the file). A backticked part can itself hold a dot or
  a colon, so read each one whole when you split an entry. The answer lists it
  only if it actually used the default, under `soft` as well as under `hard`.
  Two declarations with the same name under the same sections give one entry,
  because the entry names the sections and not the file: the same name in two
  imported files, and a rule declared in a `WHERE`, which is named
  bare, so it also shares an entry with a top-level rule of that name.
  The entry names the rule and not which of two rules of that name took the
  default: two rules called `fee` in `§ Pricing`, each with its own default for
  `rate`, both list `WITH Pricing.fee: rate`, whatever value each took. So
  `presumed` has more than one shape: a fact's name
  or path (`has capacity`, `config.timeout`), `WITH <rule>: <input>`, and
  `JSONDECODE <type>: <field>`. An entry that starts `WITH ` is a usual value
  the rules took where a call or a construction inside them left it out, which
  no case could have supplied. One that starts `JSONDECODE ` is a usual value
  in a decode the rules made, which may be of text the case sent, so it can be
  a fact that text left out.
- **An event's record in the decision service is not a place a default can
  be left out.** When a request for a rule that describes obligations replays
  events, each event's party or action record has to give every field, whether
  or not a field has a default, and so does a record nested inside it: the
  record is part of the request, and the service refuses one that leaves a
  field out.

The list of facts a published rule asks for carries each default as the
JavaScript Object Notation (JSON) Schema `default` keyword, and a defaulted fact
is not listed under `required`. A `TYPICALLY` on an `ASSUME` is not used here
either, and is not published, in the service's schema or in the query plan's.

_Landed in stages (2026-10-02, 2026-10-03 and 2026-10-09). A **section** `GIVEN` may be left
out, and a rule that reads it then uses the default; the published list of facts
asks for a defaulted fact as optional, which the boundary then honours; a
**rule's own** `GIVEN` and a **record field** may be left out at a call that
names its inputs and at a construction; and `T WITHAL` leaves out every field of
a record. Still to come: a default may not yet name another `GIVEN` (it must be
a fixed value written out)._

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
- The default must be a fixed value written out, like `18` or `"yes"`.
- A call that gives its inputs by position, and a construction that gives its
  fields by position, give all of them: only `WITH` may leave one out, and
  `WITHAL` leaves out every field of a record.
- On a computed field (one with a MEANS clause) a TYPICALLY is an error.
- For anything a fixed value cannot express, write an ordinary definition
  instead.

## See Also

- [ASSUME](ASSUME.md) — declaring assumed values (deprecated, still works)
- [The section `GIVEN`](../syntax/section-given.md) — declaring a name once for a
  whole section
- [WITH](../functions/WITH.md) — supplying, and overriding, an input by name
- [WITHAL](WITHAL.md) — a record built from every field's default
- [DECLARE](DECLARE.md) — declaring record types
- [GIVEN](../functions/GIVEN.md) — the inputs of one rule
- [Query Planning](../query-planning/README.md) — how a stored default becomes
  the per-atom prior `w_v` for the question-ordering wizard
- [Web Form Generation](../../courses/advanced/module-a4-production.md#web-form-generation)
  — using TYPICALLY defaults in an autogenerated wizard
