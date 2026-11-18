# TYPICALLY

Attaches a default value to a name. The default is a _rebuttable presumption_:
it records what should be presumed when nobody supplies a value, and a rule that
is given no value uses it.

It is used wherever the name is left out:

- **on a section `GIVEN`**, by every rule that reads the name and is given no
  value for it;
- **on a rule's own `GIVEN`**, by a call that names its inputs with
  [`WITH`](../functions/WITH.md) and leaves this one out;
- **on a record field**, by a construction that leaves the field out (a
  **record** is a bundle of named facts, such as an invoice with an amount and a
  number of days overdue; see [`DECLARE`](DECLARE.md)); and
- **when a case reaches `l4 batch` or the decision service** and leaves the
  fact out.
  The **decision service** (`jl4-service`) is the program that publishes rules for applications and AI agents to call, on Legalese Cloud or on one you run yourself.
  [At the boundary](#at-the-boundary-l4-batch-and-the-decision-service) below says what counts as leaving a fact out.

Each is described below, with what a default does _not_ excuse.

## Words this page uses

The pages about `TYPICALLY` and `l4 batch` use several words for neighbouring things.
This table says which is which.

| Word                              | What it means here                                                                                                                                                                                                                                                                                                                                                                                       |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| default, usual value, presumption | The value written after `TYPICALLY`. "Usual value" is the same thing in plainer words. A default is a rebuttable presumption, a value taken to hold unless a case says otherwise, so "presumption" is also the name of the switch (`--presumption`, `"presumption"`) that turns defaults off.                                                                                                            |
| input                             | A name listed after `GIVEN`: something a rule is told.                                                                                                                                                                                                                                                                                                                                                   |
| fact                              | What the caller supplies for an input, or for a field of a record, in a case sent to `l4 batch` or a request sent to the decision service.                                                                                                                                                                                                                                                               |
| field                             | A named part of a record.                                                                                                                                                                                                                                                                                                                                                                                |
| case                              | One set of facts: a line or row of the file given to `l4 batch`, or one request (or one entry of a batch request) to the decision service.                                                                                                                                                                                                                                                               |
| `presumed`                        | The list in an answer of the defaults that answer used. A default the answer did not need is not listed.                                                                                                                                                                                                                                                                                                 |
| refused                           | A case or request turned away before the rules ran, with the reason named: the decision service answers with an error, `l4 batch` marks the line `status` `error`, and a batch case carries `@error`. The `refused` of `status` and `@refused` means something else: the rules themselves declined to answer (see [What each line says](../../tutorials/getting-started/l4-cli.md#what-each-line-says)). |
| `soft`, `hard`                    | The two settings of the `presumption` switch. `soft`, the default, lets a fact a case leaves out take its default. `hard` uses no default, so that fact is missing. See [At the boundary](#at-the-boundary-l4-batch-and-the-decision-service).                                                                                                                                                           |
| rule that describes obligations   | A regulative rule: one whose result is a contract (of type `DEONTIC`) saying who must, may or must not do what, and by when. The service pages also call it a rule that returns a contract. See [Regulative rules](../regulative/README.md).                                                                                                                                                             |
| event                             | A record that a party did an action at a time. A rule that describes obligations is run against a list of events. See [`EVENT`](../regulative/EVENT.md).                                                                                                                                                                                                                                                 |

## Syntax

```l4
name IS A Type TYPICALLY literal
```

A **literal** is a fixed value written out: a number, a piece of text, `TRUE`, `FALSE`, `NOTHING`, or a constructor of an enumeration.
An **enumeration** is a type that is a choice from a list of names, as in `DECLARE Colour IS ONE OF Red, Green`, and each name in the list (`Red`) is a **constructor** of it.
Nothing else is a default: see [What the default must be](#what-the-default-must-be).

A rule is told some facts about the case in front of it (its **"inputs"**, the
names listed after `GIVEN`). `TYPICALLY` may appear on:

1. **DECLARE fields** — default values for the fields of a record
2. **A rule's own `GIVEN`** (a **"rule `GIVEN`"**) — default values for that
   rule's inputs
3. **A `GIVEN` under a section heading** (a **"section `GIVEN`"**) — default
   values for a name declared once for every rule in the section
4. **`ASSUME` declarations, in older files** — default values for assumed
   names. `ASSUME` is deprecated and still works; a fact
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
  calculation can genuinely see two values for one name: with a section
  `GIVEN r IS A NUMBER TYPICALLY 3` and `inner MEANS r`,
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
  here it is given 1", and the message shows the call that names its inputs
  (`scaled WITH base IS <value>`). A position says which input a value is for
  only if every input before it has been given, so a gap cannot be left.
- **An input with no default is still asked for.** `scaled WITH rate IS 1` is
  told it has not supplied `base`, and a name the rule does not have is still an
  error, so a misspelling of `rate` is not read as a default taken. The one
  misspelling this cannot catch is a name that is itself something else the rule
  reads, a section `GIVEN` that the call may override (`ratee`, where the rule
  reads a section `GIVEN` of that name). That is a valid override, and `rate` then
  takes its default.
  Here the rule reads a section `GIVEN ratee IS A NUMBER TYPICALLY 100`, and `scaled MEANS rate TIMES base PLUS ratee`.
  An author who means `rate IS 2` and types `ratee IS 2` gets 32 and not 120, and `l4 check` says nothing:

  ```l4
  #EVAL scaled WITH base IS 10, rate IS 2     -- 120: what the author meant
  #EVAL scaled WITH base IS 10, ratee IS 2    -- 32: `ratee` is the section GIVEN, so `rate` takes its default, 3
  ```

- **The default is used only if the rule reads it.** A rule that never needs the
  input never forces its default, which is also what `presumed` (below) counts.

This works for a rule in the same file, a rule declared in a
[`WHERE`](../functions/LET.md#where) (a helper written under the rule that uses
it), and a rule in a file you [`IMPORT`](../libraries/README.md#import). A default declared in a file you `IMPORT` stays with
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

### A rule whose inputs all have a default

A call that names its inputs has to name at least one of them: `WITH` is followed by an input, never by nothing.
So a rule whose every input has a default cannot be called with all of them left to their defaults.
Writing the rule's name alone does not call it, and there is no [`WITHAL`](WITHAL.md) for a rule, which is only for a record (`WITHAL` builds a record from every field's default).
To get the answer the defaults give, name one input and give it the value its default already is.

```l4
GIVEN rate IS A NUMBER TYPICALLY 3
GIVETH A NUMBER
`flat fee` MEANS rate TIMES 100

#EVAL `flat fee` WITH rate IS 3     -- 300: the rate is written, and it is the default
#EVAL `flat fee`                    -- <function>: the rule itself, not a call of it
```

`` `flat fee` WITHAL `` is refused, and the error says why.
A rule with one input that has no default is not in this case: naming that input is enough, and the others take their defaults.

### Two rules with the same name

In one line: a default never decides which of two rules of the same name a call means; only the values the call gives do.
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
4. **If no rule could take the call**, because a value it gives does not fit the input of that name in any of them, the call is an error and none is chosen. The message is the same "multiple definitions" one, since nothing settled the choice, followed by the same second message as in the example below.

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

L4 reports this with two messages for the one call.
The first is `There are multiple definitions for the identifier scaled`, followed by a list of the two rules.
The second is `You are giving named inputs to scaled … but it is not a function, so it takes none`.
It is printed only together with the first: with `scaled WITH base IS 10, rate IS 3` neither is printed, and the answer is 30.

A name that only one rule has does not settle the choice either.
If the second `scaled` took `width` and `height` and had no `base`, the call `scaled WITH base IS 10` would still be ambiguous: it does not say which rule it means.

One more limit, which keeps the check fast.
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

A computed field, one with a `MEANS` clause, cannot carry a `TYPICALLY` at all: its value always comes from the `MEANS`, so a default could never be used.
That is a check error.

## On a field of an alternative that carries data

An alternative declared with `ONE OF` can carry data, as `Circle HAS radius IS A NUMBER` does.
It is built like a record, so its fields take a `TYPICALLY` in the same way:

```l4
DECLARE Shape IS ONE OF
  Circle HAS radius IS A NUMBER TYPICALLY 1
  Rect HAS width  IS A NUMBER TYPICALLY 2
           height IS A NUMBER
  Dot

GIVETH A Shape
`a tall rect` MEANS Rect WITH height IS 5

#EVAL `a tall rect`        -- Rect OF 2, 5
#EVAL Circle WITHAL        -- Circle OF 1
```

The same limits apply as for a record: a field with no default must still be given, and `Rect OF 2` (by position) must give every field.
`Circle WITHAL` takes the default of every field, and is an error naming each field that has none.
An alternative that carries nothing, such as `Dot`, has no fields to take a default for.

Two limits are particular to alternatives:

- **A field of an alternative cannot be computed.**
  A `MEANS` clause on one is a check error, because the fields of an alternative are given when it is built and the clause would never be used.
  Only the fields of a record can be computed.
- **A case cannot give an alternative that carries data, so a default on its field applies only where the rules build it, with `WITH`.**
  `l4 batch` and the decision service each say so in their own words.
  A case reaches both as JavaScript Object Notation (JSON) text, the plain-text format in which a case's facts are written, as in `{"is adult": true}`.
  Take a rule that reads a `Shape` (`Circle` carries a `radius`, `Dot` carries nothing):
  - `l4 batch` refuses `{"s": {"tag": "Circle"}}` and `{"s": {"tag": "Circle", "radius": 2}}` with `Could not decode … as Shape for field 's': expected a string naming one of: Dot. A constructor with fields (Circle, Rect) cannot be given as JSON input.`
    The bare string `"Circle"` is refused too, as `Circle has fields, and a constructor with fields cannot be given as JSON input`.
  - The decision service refuses the two `tag` forms with `Parameter 's': FnObject but expected type is not a known record`.
    It accepts the bare string `"Circle"`, and the value it reads is a `Circle` with no `radius`, which no `WHEN Circle r` branch takes: a `CONSIDER` with no `OTHERWISE` then stops with `reached a CONSIDER that has no branch for it`, and one with an `OTHERWISE` takes that.
  - The **schema** the service publishes for such an input (its list of the facts a rule asks for, with each one's type, whether it is required, and any default, written in JSON Schema, a standard way of describing the shape of JSON) lists the names only (`"enum": ["Circle", "Rect", "Dot"]`), so it advertises `"Circle"` as a valid value although a `Circle` needs its `radius`.

## In rendered text: `l4 nlg` and `l4 render`

Someone reading rendered text never sees the source.
`` `scaled` where `base` is 10 and `rate` is 3 `` would tell that reader that the author stipulated the 3, when the author wrote only `scaled WITH base IS 10` and the 3 is the default declared on `rate`.
So a value the checker added is marked as one:

- **In a sentence**, `l4 nlg` and `l4 render` print `` `rate` is 3 by default ``. A rule whose whole body is a call to another rule reads as a sentence.
  `l4 nlg` prints one for a directive such as `#ASSERT (scaled WITH base IS 10) EQUALS 30`.
  `l4 render` leaves a rule with no inputs out of its document when only a `#EVAL` or `#ASSERT` refers to it, so for such a rule add `--include-unused` to see the sentence.
- **In a list of fields**, `l4 render` prints `- colour — Red (by default)`, for a `colour` of the `Colour` enumeration above whose default is `Red`. A record construction prints this way.
- **In a table**, `l4 render` prints `Red (by default)` in each cell the checker filled in, and nothing in the cells the author wrote. A column that holds both is marked cell by cell.
- **In the document JSON** (`l4 render --format json`), the mark is part of the text of the value, `"3 (by default)"`. No key was added, so the shape of the document is the same.

A value you wrote is never marked, whatever it equals: `scaled WITH base IS 10, rate IS 3` prints `` `rate` is 3 ``.

What the mark does and does not tell you:

- **It covers a default added at a call that names its inputs, or at a construction.** Those are the two places where a call or a construction that the author wrote gets a value the author did not write.
- **It does not cover a default taken at the root of a section `GIVEN`.** With `surcharge TYPICALLY 2` on a section `GIVEN`, `` `tax on` WITH amount IS 10 `` prints as `` `tax on` where `amount` is 10 is equal to 12 ``, and the 2 is not in the text. Written at the call, `surcharge IS 7` is printed.
- **No mark does not mean that no default was used.** The defaults an answer used are listed under `presumed` when it comes from `l4 batch` or the decision service (see [At the boundary](#at-the-boundary-l4-batch-and-the-decision-service) below): a section `GIVEN` default the case left out, a field default in a record the rules decode with `JSONDECODE`, and, whether `presumption` is `soft` or `hard`, one added at a call or a construction inside the rules. The evaluation trace prints the value that was used (`scaled OF 3, 10`) and does not yet say it was a default.
- **The words are English in `l4 render`, whatever `--lang` says.** `l4 nlg --lang he` prints `כברירת מחדל` from a draft entry in its table of Hebrew phrases, which no Hebrew-speaking lawyer has reviewed, and `l4 render` does not use that table for these words ([the `@nlg` page](../syntax/nlg.md#a-value-the-checker-supplied) says so).

## What the default must be

A default is a **literal**, and it is checked when it is written:

- It is type-checked against the annotated type
  (`x IS A BOOLEAN TYPICALLY 42` is a type error).
- It must be a literal, a fixed value written out: a number, a piece of text, or
  a bare name such as `TRUE`, `FALSE`, `NOTHING` or a constructor of an
  enumeration (`colour IS A Colour TYPICALLY Red`). Anything else is an error:
  a calculation (`TYPICALLY (1 PLUS 2)`), a name of another input or of a
  definition, a call, `JUST 5` (`x IS A BOOLEAN TYPICALLY (a AND b)` is the
  same error). A default that names something that does not exist is reported
  once, as that.
- This is a decision, not a gap that a later version will fill. A default is a
  usual value; it is not the place to work something out. When the usual value
  depends on other facts, write it as the page shows in
  [When the usual value is worked out from other facts](#when-the-usual-value-is-worked-out-from-other-facts).
  The error says so: it ends by suggesting that the logic go inside a decision
  function's `OTHERWISE` branch, with a `MAYBE` input that is usually `NOTHING`.
  That advice shows for a default written in parentheses, such as
  `TYPICALLY (1 PLUS 2)`; without the parentheses, `TYPICALLY 1 PLUS 2` or
  `TYPICALLY Circle OF 3` stops earlier, in the parser ("unexpected PLUS",
  "unexpected OF"), and does not give it.
- It requires an explicit type: the name must carry an `IS A Type` annotation so
  the default can be checked (`GIVEN x TYPICALLY 5` with no type is an error).
- It cannot appear on a name that stands for a **kind of thing** rather than a
  value: `ASSUME Foo IS A TYPE TYPICALLY 42` is an error.
- **On an `ASSUME` it is still not used** ([`ASSUME`](ASSUME.md) is deprecated);
  move the declaration under its section's heading to make the default count.

## When the usual value is worked out from other facts

Sometimes the usual value of one input depends on another: a discount that is, unless someone says otherwise, a tenth of the list price.
`TYPICALLY` cannot say that, because a default is a literal.
Writing `discount IS A NUMBER TYPICALLY (`list price` DIVIDED BY 10)` is the error above.

Say it with two things that already exist.
Make the input that may be left out a `MAYBE` whose usual value is `NOTHING`, and let the rule that reads it choose between "a value was given" and "none was".
A `MAYBE NUMBER` is either `JUST` a number or `NOTHING` (see [Types](README.md#lists-optional-values-and-choices)).
`CONSIDER` chooses a branch by which of the two it is: `WHEN JUST d` is the branch for a value, which it calls `d`, and `OTHERWISE` matches anything the `WHEN` branches before it did not (see [`CONSIDER`](../control-flow/CONSIDER.md)).

```l4
§ `Pricing`
    GIVEN `list price` IS A NUMBER TYPICALLY 100
          discount IS A MAYBE NUMBER TYPICALLY NOTHING

GIVETH A NUMBER
`the discount` MEANS CONSIDER discount
                       WHEN JUST d THEN d
                       OTHERWISE `list price` DIVIDED BY 10

GIVETH A NUMBER
`final price` MEANS `list price` MINUS `the discount`
```

[typically-worked-out-example.l4](typically-worked-out-example.l4) is this file with its checks.

A case that gives a discount uses it, and a case that leaves it out gets a tenth of the list price.
With a list price of 1000, `final price` is 900 when no discount is given and 950 when the discount is 50.

- **The fallback is worked out where it is read.**
  A call written inside another rule that changes the list price changes the fallback with it:
  `` `final price` WITH `list price` IS 1000 `` is 900 wherever it is written, because the fallback discount is a tenth of the list price that call gives.
- **The boundary treats it like any other default.**
  A case sent to `l4 batch` or the decision service that leaves `discount` out takes `NOTHING` and lists `discount` under `presumed`.
  Under `--presumption hard` a case that leaves `discount` out is refused, naming it, as for any defaulted input.
- **Why not a bigger `TYPICALLY`?**
  A default that is a calculation asks the keyword to do the job of an `OTHERWISE` branch.
  The branch is already there, and it is where a reader looks for "what happens when nothing was given".

## At the boundary: `l4 batch` and the decision service

A case is written outside the rules: a line of a file for `l4 batch`, or a request to the decision service.
The boundary is where it reaches the rules.
A case sent to `l4 batch`, or a request sent to the decision service, may leave
out any fact that has a default, whether the `TYPICALLY` is on a section
`GIVEN`, on the exported rule's own `GIVEN`, or on a field of a record the rule
takes as an input. The default is filled in where the case arrives, and the
answer lists it under **`presumed`**, by name (or, for a field, by its path, such
as `config.timeout`) — but only if the answer actually used it.
The one exception is an event's party or action record in a request to the decision service for a rule that describes obligations: every field of it must be written, and a request that leaves one out is answered with an error (see [An event's party and action record](#an-events-party-and-action-record)).
`l4 batch` does not replay events, so it has no such exception.
These rules govern what counts as leaving a fact out:

- **Leaving the name out** is leaving it out. So is an empty cell in a comma-separated values (CSV)
  file given to `l4 batch`. A `MAYBE` fact with no default, left out, is `NOTHING`,
  and is listed under `presumed` like a default.
- **`null` is not.** `null` means _not known_, and a fact that is not known never
  takes its default: the case is refused, naming the fact. A `{}` given in place
  of a fact is not leaving it out either, but what it means depends on where it
  is sent: see [When a fact is given as an empty object](#when-a-fact-is-given-as-an-empty-object).
  The one exception is a `MAYBE` fact, which is allowed to
  have no value: `null` on it is `NOTHING`, a value, and nothing is presumed or
  refused. A service request is read this way whichever way it arrives: as a
  single evaluation, as a case of a batch, or as a call to the tool of the
  Model Context Protocol (MCP), the standard way an AI agent calls a rule (see
  [Connect an AI agent](../../tutorials/legalese-cloud/ai-agents.md)).
- **A `WITH` inside the rules still wins.** If a rule reads a section `GIVEN`
  and another rule overrides it for one calculation, as in
  `outer MEANS inner PLUS (inner WITH r IS 100)`, a case sent to `l4 batch`, and
  a request sent to the decision service, gets the answer `#EVAL` gives: the case's value, or the default, for the read that
  was not overridden, and the override for the one that was.
  A case that supplies a section fact which the rules
  never read, because every read of it is overridden, is accepted, and its value
  changes nothing.
- **A name that matches nothing is refused where a default is taken.** In a
  case that leaves out a fact with a default, a name that is not a fact is
  refused, naming the nearest one, since it may misspell the fact left out.
  Where no default is taken, it is ignored.
- **The presumption can be switched off.**
  `l4 batch --presumption hard`, or `"presumption": "hard"` in a service request, uses no default for a fact the case leaves out.
  That fact is missing, and the case is refused, naming it.
  This holds even for a fact the rules would never have read: for an ordinary rule, `l4 batch`, a request to `/evaluation` and a call over MCP all refuse it.
  The default is `soft`.
  An AI agent calling a rule through MCP, or through the WebMCP script (the script that gives the AI assistant in a visitor's browser these tools; see [Embed rules in a website](../../tutorials/legalese-cloud/webmcp-embed.md)), sets it the same way, with a `presumption` argument that is `"soft"` or `"hard"`.
  This service's MCP tools advertise `presumption` and read it; a hosted server placed in front of this service may not list it until that server is updated, so look at the tool list.
  [Connect an AI agent](../../tutorials/legalese-cloud/ai-agents.md#telling-a-rule-not-to-assume-anything) says where the argument goes for each kind of rule and what a server that does not know it does.
  The two values are accepted in any capitalisation, as in a service request; any other value is refused, naming it.
  Because the name is reserved, an ordinary rule with a fact called `presumption` cannot be offered as an MCP or WebMCP tool, and the server says so; the same rule still runs through a service request, where the facts are inside `arguments`.
  A rule that describes obligations is still offered, because its facts are inside `arguments` and the switch is beside them.
  The switch reaches only the facts a case can supply.
  A default that the rules take inside their own text, at a `WITH` call, at a construction or in a `JSONDECODE`, is not withdrawn, and the answer lists it under `presumed` whether `presumption` is `soft` or `hard`: see [What `presumed` lists](#what-presumed-lists).

One gap is known and not closed by this page's behaviour:

- **A default on a record field does not reach the question planner.** The
  planner that orders the questions a user is asked (see
  [Query Planning](../query-planning/README.md)) reads the defaults of a
  rule's inputs and of an `ASSUME`, and not those of a record's fields
  (tracked as [smucclaw/l4-ide#942](https://github.com/smucclaw/l4-ide/issues/942)).

The schema of a published rule carries each default as the JSON Schema `default` keyword, and a defaulted fact is not listed under `required`, the list of facts a caller must supply.
A `TYPICALLY` on an `ASSUME` is not used here either, and is not published, in the service's schema or in the query plan's.
The one record that does not follow this is an event's party or action, in a request to a rule that describes obligations.
That record is part of the request, so it never takes a default.
The schema lists each of its fields under `required` and gives none a `default`,
and a request that leaves a field out is refused.
A record inside it is written under its constructor's name.
The typed schema of an event is published in the function document (the document the service returns for one rule at `GET .../functions/{fn}`, with its description, inputs and result) and in `openapi.json` under each batch case's `events`.
The [service's own documentation](../../../jl4-service/README.md#an-events-party-and-action)
says how, and what the service cannot yet read there.

A default is a fixed value written out: it does not name another `GIVEN`, and that is a decision and not a gap (see [When the usual value is worked out from other facts](#when-the-usual-value-is-worked-out-from-other-facts)).

### What `presumed` lists

`presumed` is for whoever reads an answer, the sender or a reviewer.
It lists the usual values the answer rests on that nobody wrote into the case, so that a reader can tell what was assumed.
An entry has one of three shapes:

| The entry looks like                 | It says                                                                                                                                                                                                               | Taken under                                  |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| `has capacity`, `config.timeout`     | A fact the case left out took its default. A field is named by its path. A `MAYBE` fact with no default that was left out is listed too, because it is `NOTHING`.                                                     | `soft` only: `hard` refuses the case instead |
| `WITH Pricing.scaled: rate`          | A `WITH` call, or a record built with `WITH`, inside the rules left an input or a field out, and the rules took its default. No case could have supplied it.                                                          | `soft` and `hard`                            |
| `JSONDECODE Pricing.Settings: limit` | A record that the rules read out of JSON text with `JSONDECODE` took a default for a field the text left out. The text may be written in the rules or be text the case sent, so this can be a fact the case left out. | `soft` and `hard`                            |

A reader who wants only the facts a case left out can skip the entries that begin `WITH`.
The entries that begin `JSONDECODE` are not safe to skip.
An entry is listed only if the answer actually used the default.

Here is one rule that produces all three.
`has capacity` is a section `GIVEN` that the case leaves out, `scaled` is called with `WITH` and leaves out its `rate`, and `read settings` decodes the JSON text `{}` into a `Settings` whose `limit` is then its default:

```l4
§ `Pricing`
    GIVEN `has capacity` IS A BOOLEAN TYPICALLY TRUE

DECLARE Settings HAS limit IS A NUMBER TYPICALLY 10

GIVEN rate IS A NUMBER TYPICALLY 3
      base IS A NUMBER
GIVETH A NUMBER
scaled MEANS rate TIMES base

GIVEN text IS A STRING
GIVETH AN EITHER STRING Settings
`read settings` MEANS JSONDECODE text

GIVETH A NUMBER
`the limit` MEANS
  CONSIDER `read settings` "{}"
    WHEN RIGHT s THEN s's limit
    OTHERWISE 0

@export Price an order
GIVEN base IS A NUMBER
GIVETH A NUMBER
`price` MEANS IF `has capacity` THEN (scaled WITH base IS base) PLUS `the limit` ELSE 0
```

For the case `{"base": 10}`, `l4 batch` prints this line, where the answer 40 is 3 × 10 plus 10:

```
{"diagnostics":[],"input":{"base":10},"output":[{"result":40,"trace":null}],"presumed":["has capacity","WITH Pricing.scaled: rate","JSONDECODE Pricing.Settings: limit"],"status":"success"}
```

How an entry is written:

- The label of a `WITH` entry names the rule or record as its declaration writes it, behind the section it is declared in: `WITH Pricing.scaled: rate` is a rule in `§ Pricing`, `WITH Pricing.Config: timeout` is a field of a record there, and `WITH scaled: rate` is a rule at the top of the file, which has no section to name.
  Two rules of one name in different sections are two entries.
- The type of a `JSONDECODE` entry is named as it is declared, behind the section heading it is declared under (`JSONDECODE Pricing.Settings: limit`), whichever way the rule wrote the type at the decode.
  A record declared under a heading in an _imported_ file is the exception: it is named without the heading (``JSONDECODE `Paint Order`: coats``), though its `WITH` entry has it.
  A `MAYBE` field with no `TYPICALLY` that the decoded JSON leaves out is filled with `NOTHING` and listed the same way (`JSONDECODE Partial: note`).
- A part that L4 would write in backticks in source is written in backticks, with or without a section in front of it.
  That means any name with a space, a dot, a hyphen or an apostrophe in it, one that starts with a digit, and a reserved word (``WITH `Part 1. Fees`.scaled: rate``, ``WITH `two words`: rate`` for a rule at the top of the file).
  A backticked part can itself hold a dot or a colon, so read each one whole when you split an entry.
- Two declarations with the same name under the same sections give one entry, because the entry names the sections and not the file.
  That covers the same name in two imported files, and a rule declared in a `WHERE`, which is named bare and so also shares an entry with a top-level rule of that name.
  The entry names the rule and not which of two rules of that name took the default: two rules called `fee` in `§ Pricing`, each with its own default for `rate`, both list `WITH Pricing.fee: rate`, whatever value each took.

### When a fact is given as an empty object

A `{}` in place of a fact is neither left out nor a value.
What it means depends on where it is sent:

| A `{}` given as                                 | In `l4 batch`                                                                                                             | In the decision service                                                                                                                                                                                                        |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| A fact that is not a `MAYBE`, a record included | _Not known_: the line is an error naming the fact, `Field 'p' is {}, which means the value is not known: supply a value`. | _Uncertain_: the request is answered unless the answer depends on that fact, and then it is refused, naming it. A `null` in its place is refused at once, in both.                                                             |
| A fact that is a `MAYBE`                        | `NOTHING`, and the case succeeds.                                                                                         | `NOTHING`, as a `null` is, whether `presumption` is `soft` or `hard`, and nothing is listed under `presumed`. A `MAYBE` fact that is left out is different: it is `NOTHING` and listed under `soft`, and refused under `hard`. |
| JSON text that the rules read with `JSONDECODE` | It supplies nothing, so a field that has a default takes it.                                                              | The same: it supplies nothing, so a field that has a default takes it.                                                                                                                                                         |

The `JSONDECODE` row is the same in both because it happens inside the rules, after the case has been read.
The service column is described in the [service documentation](../../../jl4-service/README.md#missing-and-uncertain-inputs).

### An event's party and action record

An event (a record that a party did an action at a time) is part of a request to the decision service for a rule that describes obligations.
That request replays a list of events against the rule, and each event names a party, an action and a time.
The request also has a `startTime`, when the contract begins.
Both times are numbers on the rule's own timeline, which has no fixed unit: use the unit the rule's `WITHIN` numbers use (see [`WITHIN`](../regulative/consequences.md#within)).
A rule describes obligations when its result type is `DEONTIC`, and the Deploy tab and the function document list each rule's result type.
When the party or the action is a record, **every field of it has to be written, whether or not the field has a default**, and so does every field of a record nested inside it.
The record is part of the request, so it never takes a default, and the service answers one that leaves a field out with an error that names the field.
The answer is the same in `soft` and in `hard`.
The schema the service publishes says the same: it lists every field of an event's party and action as required, with no default, so a client that writes every field the schema lists does not meet this error.
The service cannot yet read every type of field that the schema describes, and the [service's own documentation](../../../jl4-service/README.md#an-events-party-and-action) says which.
The typed schema of an event is published in the function document (`GET .../functions/{fn}`) and in `openapi.json` under each batch case's `events`.

A file and the service differ here, on purpose.
In a file, a `#TRACE` event may leave a defaulted field out, and the event takes the default.
Here `Driver` has a `licence` that is `"full"` unless written, and the event of the driver Alice leaves it out:

```l4
DECLARE Driver HAS name IS A STRING
                   licence IS A STRING TYPICALLY "full"

DECLARE Act IS ONE OF `wear seatbelt`

`seatbelt rule` MEANS
  PARTY (Driver WITH name IS "Alice", licence IS "full")
  MUST `wear seatbelt`
  WITHIN 10
  HENCE FULFILLED
  LEST BREACH

#TRACE `seatbelt rule` AT 0 WITH
  PARTY (Driver WITH name IS "Alice") DOES `wear seatbelt` AT 0     -- FULFILLED
```

The rule says that the driver Alice must wear a seatbelt within 10; `HENCE FULFILLED` is what follows if she does, and `LEST BREACH` if she does not.
`#TRACE` runs the rule from time 0 against the events listed under it, here one: at time 0, Alice wears a seatbelt.
`l4 run` gives `FULFILLED`: the event is that of a driver whose licence is `"full"`, so it meets the obligation of `Driver WITH name IS "Alice", licence IS "full"` without a word about the default.
The decision service takes the same event from a request and answers with HTTP status 422, the same in `soft` and in `hard`.
The body is:

```json
{
  "contents": {
    "contents": "Missing required field 'events[0].party.licence' (Driver): an event's record is part of the request, so it never takes the field's TYPICALLY default. Give every field of it.",
    "tag": "InterpreterError"
  },
  "report": "default",
  "tag": "Error"
}
```

An event with every field written looks like this:

```json
{
  "party": { "name": "Alice", "licence": "full" },
  "action": "wear seatbelt",
  "at": 1
}
```

and this one leaves the licence out, so the service answers it with the error above (an event that writes every field is answered normally):

```json
{ "party": { "name": "Alice" }, "action": "wear seatbelt", "at": 1 }
```

Neither a file nor `l4 batch` shows this error, because a file takes the default and `l4 batch` does not replay events.
To see it before you deploy, send the request to a decision service you run yourself, as the [service documentation](../../../jl4-service/README.md) describes.
How a rule that describes obligations is written is taught under [Regulative rules](../regulative/README.md).

**The error can name a field that was written.**
A party or an action sent as `{"Driver": {"name": "Alice", "licence": "learner"}}`, keyed by its constructor, is the wrong shape at the top level.
The service looks for each field that has a default as a key of the party or action itself, and with the constructor name around the fields the only key it finds is `Driver`.
So a record that has a `TYPICALLY` gets the `Missing required field` message above, naming a field the request did write, and a record that has no `TYPICALLY` at all gets a type error.
When that message names a field you wrote, the cause is the shape, not a missing field: send the fields directly, as in the event above.
A record nested inside a party or an action is the other way round: it is keyed by its constructor (`{"Address": {...}}`), and the published schema describes it that way.

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

`ASSUME` is deprecated and still works. On an `ASSUME` the
default stays metadata, as does the default of an input of an `ASSUME` that takes
inputs; moving the declaration under its section's heading, as the previous
example does, is what makes the default take effect for a rule given no value.

## Behavior

- A default is used where the name is left out, and nowhere else: a value
  supplied always wins, and `null` (not known) is never an omission.
- The default must match the annotated type, or type checking fails.
- The default must be a literal, a fixed value written out, like `18` or `"yes"`.
- A rule's own defaulted input and a record's defaulted field may be left out
  only where they are named: a call or a construction that gives them by
  position gives all of them, and only `WITH` may leave one out (`WITHAL` leaves
  out every field of a record). A section `GIVEN` is different: it flows into
  the rule that reads it, and takes its default, at a positional call too
  (`scaled 10` gives 30 where `scaled` reads a section `rate` that is 3).
- On a computed field (one with a MEANS clause) a TYPICALLY is an error.
- For anything a fixed value cannot express, write an ordinary definition
  instead; for a usual value worked out from other facts, use a `MAYBE` input and
  a `CONSIDER` ([When the usual value is worked out from other facts](#when-the-usual-value-is-worked-out-from-other-facts)).

## See Also

- [ASSUME](ASSUME.md) — declaring assumed values (deprecated, still works)
- [The section `GIVEN`](../syntax/section-given.md) — declaring a name once for a
  whole section
- [WITH](../functions/WITH.md) — supplying, and overriding, an input by name
- [WITHAL](WITHAL.md) — a record built from every field's default
- [DECLARE](DECLARE.md) — declaring record types
- [GIVEN](../functions/GIVEN.md) — the inputs of one rule
- [Query Planning](../query-planning/README.md) — the planner that decides which question to ask next, and takes a `BOOLEAN` input on a rule's own `GIVEN`, or an `ASSUME`, as likely to have its usual value
- [Getting Ready to Deploy](../../courses/advanced/module-a4-production.md#getting-ready-to-deploy)
  — TYPICALLY in a published rule
