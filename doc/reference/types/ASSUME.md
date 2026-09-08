# ASSUME (deprecated)

`ASSUME` declared a name and the kind of thing it stands for, without giving it
a value: something the rules could talk about before anyone had said what it
was. **It is deprecated.** L4 still accepts it, and every file written with it
still reads, checks, runs and publishes exactly as before; this page is kept so
that a reader of older code knows what the keyword did and what to write
instead.

- **Ruled 2026-09-04** (`specs/todo/IMPLICIT-PROPS-DESIGN.md` §11.1): one
  keyword was carrying three unrelated jobs, and each job now has a construct of
  its own.
- **The repository's own L4 was rewritten on 2026-09-06**: every `ASSUME` in
  the examples, the libraries and this documentation moved to the constructs
  below, except for the handful of files whose whole purpose is to test the
  deprecated keyword itself (each says so in a comment on its first line) and
  the Reg CF corpus's own refusal, which waits on a Decision Model and
  Notation (DMN) exporter limit recorded under
  [`REFUSE`](../control-flow/REFUSE.md#limits-as-they-stand-today).
- **The checker warns, since 2026-09-07.** Every author-written `ASSUME`
  draws a warning — never an error, so nothing that checked before stops
  checking — that reads the shape of the declaration and names the construct to
  use instead. See
  [ASSUME is being retired](../errors/README.md#assume-is-being-retired) for the
  text and the shapes it tells apart.

## What it did

A rule is told some facts about the case in front of it (its **"inputs"**) and
works out one answer from them. An `ASSUME`d name was one of those facts, left
open at the top of the file for somebody outside the file to supply:

```l4
ASSUME `applicant age` IS A NUMBER          -- a fact, to be supplied per case
ASSUME Applicant IS A TYPE                  -- a kind of thing, never described
ASSUME `no figure exists before 2016` IS A NUMBER   -- a case the model declines
```

Those three lines look alike and mean three different things, which is the
whole reason for the deprecation: a reader could not tell from the keyword
whether the author meant "ask for this", "this is a kind of thing", or "there is
no answer here".

## Where each job goes now

| The job the `ASSUME` was doing                                    | Where that job goes                                                                                                                                                          |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| a fact supplied afresh for each case (the applicant's age)        | a [`GIVEN` under the section heading](../syntax/section-given.md) whose rules read it — a **"section `GIVEN`"**                                                              |
| a rule defined elsewhere (`… IS A FUNCTION FROM …`)               | the same section `GIVEN`, with the same function type — the move is safe either way, but read "Function-typed inputs" below for what an `@export`ed rule may not read at all |
| a kind of thing the model treats as opaque (`ASSUME T IS A TYPE`) | [`DECLARE T`](DECLARE.md#opaque-types) — a name with no stated contents                                                                                                      |
| a case the encoding deliberately does not cover                   | one named definition whose body is [`REFUSE "..."`](../control-flow/REFUSE.md)                                                                                               |

### 1. A fact supplied per case: the section `GIVEN`

Move the declaration under the heading of the section whose rules read it, and
indent it past the `§`. The name, the type and every rule that reads the name
are unchanged.

Before:

```l4
§ `1. Issuer eligibility`

ASSUME issuer IS AN IssuerProfile

GIVETH A BOOLEAN
`is disqualified` MEANS issuer's `has a disqualifying event`
```

After:

```l4
§ `1. Issuer eligibility`
    GIVEN issuer IS AN IssuerProfile

GIVETH A BOOLEAN
`is disqualified` MEANS issuer's `has a disqualifying event`
```

The indentation is what makes a `GIVEN` the section's rather than one rule's: a
`GIVEN` at column 1 lists the inputs of the declaration below it, as it always
has. Both spellings behave as an open fact until something supplies it, and
both appear as inputs of any `@export`ed rule that reads them. What the section
`GIVEN` adds is that the fact has a stated home, and that a value can now be
supplied inside the file with `WITH`:

```l4
#EVAL `is disqualified` WITH issuer IS `Alex's company`
```

That last line is the one thing an `ASSUME` never had. Written against an
`ASSUME`d name it is a check error ("You are giving named inputs to … but it
is not a function"), because an `ASSUME` was never an input of anything in
particular. See [What a Section Needs to Know](../../tutorials/section-given/what-a-section-needs-to-know.md)
for the tutorial, and [the section `GIVEN`](../syntax/section-given.md) for the
column rule, the scoping rules and the check error that reports a mis-indented
one.

The migration is mechanical for this job, and the repository ships the script
that did it: `node etc/migrate-assume.mjs --write <files>` rewrites every term
`ASSUME` under its own heading (`--add-heading` synthesises one for a file with
none, `--hoist-root` places declarations that sat above the first heading, and
`--types` handles the next job too). It reports, by name and line, every
`ASSUME` it will not touch and why.

### 2. A kind of thing: `DECLARE T`

`ASSUME TypeName IS A TYPE` named a type without describing it. A bodiless
`DECLARE` says the same thing:

Before:

```l4
ASSUME Applicant IS A TYPE
```

After:

```l4
DECLARE Applicant
```

The two produce the same entity in the type checker, so a file can be migrated
one line at a time and nothing downstream changes. See
[opaque types](DECLARE.md#opaque-types).

### 3. A case the model does not cover: `REFUSE`

Some `ASSUME`s were never facts anyone could supply. They were placed where a
rule had nothing to say — a figure for a year before the regulation existed —
so that evaluation would stop there rather than invent a number. That is a
**refusal**, and it is spelled `REFUSE`, as one named definition per refusal so
that every arm reaching it reads as a citation:

Before:

```l4
ASSUME `no Regulation Crowdfunding figure exists before commencement on 2016-05-16` IS A NUMBER

GIVETH A NUMBER
`offering maximum` MEANS
    BRANCH IF `the rules in force include` `the 2021 amendments` THEN 5000000
           OTHERWISE `no Regulation Crowdfunding figure exists before commencement on 2016-05-16`
```

After:

```l4
GIVETH A NUMBER
`no Regulation Crowdfunding figure exists before commencement on 2016-05-16` MEANS
    REFUSE "no Regulation Crowdfunding figure exists before commencement on 2016-05-16"

GIVETH A NUMBER
`offering maximum` MEANS
    BRANCH IF `the rules in force include` `the 2021 amendments` THEN 5000000
           OTHERWISE `no Regulation Crowdfunding figure exists before commencement on 2016-05-16`
```

The rules that reach it do not change. What changes is what the reader and the
tools are told: a refusal is not an input, so it leaves the published list of
facts, and it stops evaluation with the author's reason rather than with "it is
an assumed term". (The example is drawn from the Reg CF corpus, whose own floor
still carries the older spelling for the exporter reason on the `REFUSE` page.) The field test for which of the two you are looking at, in an
older file: _could a person supply this value?_ If yes, it was a fact, and it
becomes a section `GIVEN`. If nobody could, it was a refusal. See
[When a Rule Cannot Answer](../../tutorials/refuse/when-a-rule-cannot-answer.md)
and [`REFUSE`](../control-flow/REFUSE.md).

## Function-typed inputs

`ASSUME f IS A FUNCTION FROM NUMBER TO BOOLEAN` declared a rule defined
elsewhere. The section `GIVEN` accepts the same type, and a rule that reads
such a name type-checks and runs exactly as it did:

```l4
§ `Helpers assumed to exist`
    GIVEN cat IS A FUNCTION FROM A STRING AND A STRING TO A STRING
          coerce IS A FUNCTION FROM A NUMBER TO A BOOLEAN
          coerce IS A FUNCTION FROM A BOOLEAN TO A NUMBER
```

One name may be declared at several types, as the second and third lines show;
each use resolves to whichever type its context needs.

**A rule that works for any kind of thing** (what programming language theory
calls **polymorphic**) has no section `GIVEN` form. Writing its type with
`FOR ALL` is accepted, but a use of the name is then rejected as "not a
function" — and the same is true of `ASSUME f IS FOR ALL …`, so this is not a
loss the migration causes. The one spelling that works is the older signature
form, a `GIVEN a IS A TYPE` and a `GIVETH` heading an `ASSUME f` with no type
of its own; `jl4/examples/ok/tbd.l4` keeps it for that reason. Write the rule
out instead of assuming it wherever you can.

**The limit is at the export boundary.** A published rule cannot accept an
input that is itself a rule, because a rule cannot be sent as JavaScript Object
Notation (JSON), which is what a request carries. A request carries **values** —
a number, a date, a yes or no, a record of those — and a rule is not a value.

That limit does not care how you spelled the rule. An assumed name that takes no
inputs of its own is a value, and a request can supply it. An assumed name that
takes one or more inputs is a rule, and a request cannot. Both of these declare
the same one-input rule, and since 2026-09-08 L4 refuses an `@export`ed rule that
reads either of them:

```
GIVEN p IS A Person
ASSUME `is eligible` p IS A BOOLEAN

ASSUME `is eligible` IS A FUNCTION FROM Person TO BOOLEAN
```

The message names the rule, the published rule that reads it, how many inputs it
takes, and what you can do about it:

```
The @export rule `may apply` reads `is eligible`, which is assumed and takes 1
input of its own.
A published rule's inputs travel as JSON, which can carry a value but not a
rule, so an assumed rule with inputs of its own can never be supplied — every
request would stop on it.
Give `is eligible` a definition (DECIDE or MEANS), or take what it is asked
about as an ordinary input of `may apply`, or remove the @export.
```

**Which means moving between the two spellings is safe.** It used to matter a
great deal — until 2026-09-08 the head-form spelling slipped past the check and
then failed on every request, so a file could look publishable and not be. Both
are refused now, at check time, so migrating one to the other cannot change
whether a rule exports.

**Two exporters still read the older shape, and still work.** The Blawx bridge
and the relational middle end turn a predicate written as
`GIVEN p IS A Person` / ``ASSUME `is authorised` p IS A BOOLEAN`` into an input
predicate — something a person answers in an interview rather than something a
request sends. They are not publishing a web API, so the refusal above does not
apply to them, and `l4 blawx` still compiles those files. What you cannot do is
publish one of them as a web API. The shipped Blawx seeds keep the `ASSUME`
form for that reason and say so in their headers; see
[L4 to Blawx](../../tutorials/blawx/l4-to-blawx.md).

## Reading older code

Everything below still holds for an `ASSUME` you meet in a file that has not
been migrated.

- An assumed name says what kind of thing it is, but carries no value. L4
  accepts a rule that reads one, and that rule can be quoted, published and
  reasoned about, but it cannot be run to an answer until the value is supplied.
- `#EVAL` on such a rule stops at the name and says so:

  ```
  I could not continue evaluating, because I needed to know the value of
    age
  but it is an assumed term.
  ```

  A section `GIVEN` that nothing has supplied reports in exactly the same
  words, so meeting them is not a sign that a `GIVEN` was treated as something
  else.

- Nothing inside the file supplies an `ASSUME`. The value comes from the
  boundary: `l4 batch rules.l4 --inputs cases.json`, a request to `jl4-service`,
  or the generated web form. When a module-level `ASSUME` is read by an
  `@export`ed rule it becomes an input of the published rule and must be
  supplied with the request; `ASSUME`s that no published rule reads stay
  module-level assumptions.
- `TYPICALLY` on an `ASSUME` records a default and applies it nowhere; on a
  section `GIVEN` a default is what a rule given no value works out. See
  [`TYPICALLY`](TYPICALLY.md).

**Example file:** [assume-example.l4](assume-example.l4) — the deprecated forms
above, kept runnable, with the migrated section `GIVEN` at the end of the file
for comparison.

## Related Keywords

- **[The section `GIVEN`](../syntax/section-given.md)** — where a term `ASSUME`
  goes now
- **[GIVEN](../functions/GIVEN.md)** — a rule's own inputs (a "rule `GIVEN`")
- **[DECLARE](DECLARE.md)** — records, enumerations and, with no body, opaque
  types
- **[REFUSE](../control-flow/REFUSE.md)** — a case the encoding declines
- **[TYPE-KEYWORDS](keywords.md)** — type syntax (IS, FUNCTION, and the rest)

## See Also

- **[Types Reference](../types/README.md)** — type syntax
