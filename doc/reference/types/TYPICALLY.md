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
  `"presumption": "hard"` in a service request, uses no defaults: a fact left
  out is missing, and the case is refused, naming it. The default is `soft`.
  The switch reaches only the facts a case can supply. A record the rules
  decode from JSON of their own (`JSONDECODE`) still takes its defaults, and
  under `hard` the answer lists them under `presumed` as
  `JSONDECODE <type>: <field>`, because nothing the case says could replace
  them.

The list of facts a published rule asks for carries each default as the
JavaScript Object Notation (JSON) Schema `default` keyword, and a defaulted fact
is not listed under `required`. A `TYPICALLY` on an `ASSUME` is not used here
either, and is not published, in the service's schema or in the query plan's.

_Partly landed (2026-10-02). Of the four things proposed on 2026-09-04, two have
landed: a **section** `GIVEN` may be left out, and a rule that reads it then uses
the default; and the published list of facts asks for a defaulted fact as
optional, which the boundary then honours. The other two have not. A rule's own
`GIVEN` still cannot be left out at a call inside a file. The default still must
be a fixed value written out, so it cannot name another `GIVEN`._

## In a trace

A trace shows how an answer was worked out: `#EVALTRACE` in the editor, `l4 trace`, and `trace=full` on the decision service.
When a rule reads a name that took its default, the trace says so, at the place the rule needed it, with where the default was written and the value it gave:

```l4
§ `Rates`
    GIVEN `the rate` IS A NUMBER TYPICALLY 3

GIVETH A NUMBER
doubled MEANS `the rate` TIMES 2

#EVALTRACE doubled
#EVALTRACE doubled WITH `the rate` IS 5
```

```text
6
─────
┌ doubled OF `the rate`
│┌ doubled
│└ <function>
├ `the rate` TIMES 2
│┌ the rate took its default (declared at rates.l4:2:44-45)
│└ 3
└ 6

10
─────
┌ doubled OF 5
│┌ doubled
│└ <function>
├ `the rate` TIMES 2
└ 10
```

The second trace has no such line, because nothing was presumed: the value was given.
It shows as the argument it is, `doubled OF 5`.

The two lines have the shape of any step the rule took, what was worked out over the value it gave, and the words `took its default` are what tell them apart.

- **A default that nothing read is not shown.**
  The rule `FALSE AND` _the defaulted name_ is settled before the name is read, so its trace says nothing about it.
  This is the same test `presumed` applies at the boundary, and a trace has a line for each default that `presumed` lists.
- **A default is shown once**, where it was first read.
  A rule that reads the same name afterwards shows only its value, with no line of its own.
  To see every default an answer rests on, take the first line of each, or on the decision service read the answer's `presumed` list.
- **The place is a line and a column.**
  `rates.l4:2:44-45` is where the value `3` is written, on line 2, columns 44 to 45: the value itself, which is narrower than the whole line.
  A `MAYBE` field left out of a record takes `NOTHING` with no `TYPICALLY` behind it, and its line says so: `premium took its default (a MAYBE left out is NOTHING)`.
- **On the decision service**, the `reasoning` of a `trace=full` answer has a node for it, with the same sentence, then the value, as its `explanation`, and the name as its `exampleCode`.
  Its `explanation` has two entries, the sentence and then `Result: 3`, where the other nodes have only the result: the result is the last entry of every node's `explanation`.
  The name is the string the answer's `presumed` list uses for the same default, so the nodes can be matched to the list by comparing the two strings.
  The nodes come in the order of the tree, which is the order of the steps, and not always the order the defaults were read or the order of `presumed`, so match by name and not by position.
  The place is the author's own file and line, also when the request went through the service's wrapper.
  The graph from `l4 trace`, and the service's `graphviz` output, draws it as a pale yellow node.
- **A rule that runs only when the answer is written out** shows the default under the step that read it, as any rule does.
  Handing back `JUST` the rule, a list of what rules gave, or a deontic function's answer are the usual cases.
- **A default that no step of the trace can show** hangs under the last step of the whole expression.
  A function that hands back a record with a defaulted field it never looked at is one: nothing computed with the field, so there is no step to put the line under.
  A rule with no inputs of its own, which the trace does not open up, that decodes JSON and leaves a field out is the other.
  A third is a trace that was cut off: a trace stops at 10,000 steps and says `… trace truncated` where it stopped, and a default read after that point is shown under the last step, with its value, and not left out.
  The one exception is a trace that could not be put together at all, which is a single line saying so and has no step to hang anything under; a plain `#EVAL` says its defaults beside its answer (below), and a `#EVALTRACE` in that state says them there too.
- **A default filled in by a rule's own `JSONDECODE`** is shown too, though `presumed` leaves it out unless the case was run under `hard` presumption: it is a default the case could not have supplied.
- **A default written in a section of an imported file is not shown**, and `presumed` does not list it either.
  A rule that reads one through an `IMPORT` takes the default with no line in the trace.
  An `@export` that reaches a section input of an imported file is refused when the file is checked, so this arises in the editor and in `l4 trace` only.

## Beside an answer

A plain `#EVAL` or `#ASSERT` has no trace, so it says which defaults it took in a line after its answer, one line for each:

```text
6
NOTE: the rate took its default 3 (declared at rates.l4:2:44-45)
```

The line says what the trace says: the name, what it came to, and where its default was written.
The value is the one the default took.
A `MAYBE` left out has no `TYPICALLY` to point to, and says `premium took its default (a MAYBE left out is NOTHING)`.
A directive that supplies the value, such as `#EVAL doubled WITH `the rate` IS 5`, has no such line, and neither has one that never read the default.
A `#EVALTRACE` shows the default in its trace and does not say it twice.

Where you see the line:

- `l4 run` prints the lines in its `Notes:` block, and in the `notes` of `l4 run --json`.
- The editor shows them in the directive's diagnostic and in the inspector panel.
- The REPL shows them after the value.
  It re-prints the file before it evaluates an expression, so the place it names is in its own copy (`.repl_eval_0.l4`, with the columns of the re-printed text), and not in your file; the name and the value are the ones to read.
- `l4 batch` and the decision service say it in the answer's `presumed` list instead.
- The browser playground shows only the value of a directive, as it does for every other note.
  The JSON its engine returns carries the lines in `notes`, but the page does not display them.

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
