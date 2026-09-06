# ASSUME

Declares a name and the kind of thing it stands for, without giving it a value:
something the rules can talk about before anyone has said what it is.

A rule is told some facts about the case in front of it (its **"inputs"**) and
works out one answer from them. An `ASSUME`d name is one of those facts, left
open at the top of the file for somebody outside the file to supply.

**`ASSUME` is deprecated (ruled 2026-09-04), and it still works.**
L4 still accepts it, it still runs and it still exports exactly as it always
has; no warning is emitted, and nothing already written stops working. New
rules should use the constructs in the table below, because one keyword was
carrying four unrelated jobs.

| The job the `ASSUME` was doing                                    | Where that job goes                                                                                             |
| ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| a fact supplied afresh for each case (the applicant's age)        | a [`GIVEN` under the section heading](../syntax/section-given.md) whose rules read it — a **"section `GIVEN`"** |
| a kind of thing the model treats as opaque (`ASSUME T IS A TYPE`) | [`DECLARE T`](DECLARE.md#opaque-types) — a name with no stated contents                                         |
| a case the encoding deliberately does not cover                   | [`REFUSE "..."`](../control-flow/REFUSE.md)                                                                     |
| a rule defined elsewhere (`… IS A FUNCTION FROM …`)               | not yet ruled — keep the `ASSUME`, and see "Function-typed inputs" below                                        |

## Migrating a term `ASSUME`

Move the declaration under the heading of the section whose rules read it, and
indent it past the `§`:

Before:

```l4
§ `1. Issuer eligibility`

ASSUME issuer IS AN IssuerProfile
```

After:

```l4
§ `1. Issuer eligibility`
    GIVEN issuer IS AN IssuerProfile
```

Behaviour is identical in this release: both behave as assumed terms, and both
appear as inputs of any `@export`ed rule that reads them. The indentation is what
makes a GIVEN the section's rather than one rule's — a `GIVEN` at column 1 lists
the inputs of the declaration below it, as it has always done. See
[the section `GIVEN`](../syntax/section-given.md) for the column rule and the
check error that reports a mis-indented one. A runnable version of the section
form is at the end of [assume-example.l4](assume-example.l4).

> `ASSUME` is for a fact the boundary supplies — it becomes a required input of the published rule. If what you mean is that the model declines to answer, that is a refusal, and it is spelled [`REFUSE`](../control-flow/REFUSE.md). A refusal is not an input anyone can supply, and no rule can convert it into an answer.

## Syntax

```l4
ASSUME name IS A Type
ASSUME name IS A FUNCTION FROM Type1 TO Type2
```

## Examples

**Example file:** [assume-example.l4](assume-example.l4)

### Assuming a plain fact

```l4
-- Assume a boolean input
ASSUME isEmployed IS A BOOLEAN

-- Assume a numeric value
ASSUME income IS A NUMBER

-- Assume a string
ASSUME applicantName IS A STRING
```

### Assuming a rule defined elsewhere

```l4
-- Assume a rule defined elsewhere
ASSUME calculateTax IS A FUNCTION FROM NUMBER TO NUMBER

-- A rule with several inputs (joined with AND)
ASSUME addNumbers IS A FUNCTION FROM NUMBER AND NUMBER TO NUMBER
```

### Reading assumed names in a decision

```l4
ASSUME age IS A NUMBER
ASSUME income IS A NUMBER

DECIDE isEligible IS
  age >= 18 AND income > 50000
```

## Behavior

- An assumed name says what kind of thing it is, but carries no value.
- L4 accepts a rule that reads one, and that rule can be quoted, published and
  reasoned about — but it cannot be run to an answer until the value is
  supplied.
- `#EVAL` on such a rule stops at the name and says so:

  ```
  I could not continue evaluating, because I needed to know the value of
    age
  but it is an assumed term.
  ```

## How a value reaches an assumed name

Nothing inside the file supplies one. The value comes from the boundary — the
place that asked the question:

- `l4 batch rules.l4 --inputs cases.json` runs the file once for each case in
  that JavaScript Object Notation (JSON) file;
- a request to `jl4-service` carries the values as request inputs;
- the generated web form asks the person for exactly the names the exported rule
  reads.

Neither `#CHECK ... WITH ...` nor `#EVAL ... WITH ...` binds an assumed value
today, and the failure takes more than one shape. Where the name takes no
inputs of its own, both `#CHECK isAdult WITH age IS 25` and `#EVAL isAdult WITH
age IS 25` report the same check error: `You are giving named inputs to isAdult …
but it is not a function, so it takes none.` Where a value is written before
the `WITH`, as in
``#EVAL `tax on` 100 WITH rate IS 0.2``, the file does not parse at all:
`unexpected WITH`.

_Proposed, not landed (2026-09-04): supplying an ASSUMEd value inside the file,
as `#EVAL isAdult WITH age IS 25` where `age` is assumed. This lands with the
discharge pull request; until then supply values from outside the file (web
form, `l4 batch`, application programming interface)._

## ASSUME and `@export`

When a module-level ASSUME is read by an `@export`-decorated DECIDE, it becomes
an input of the published rule and must be supplied with the request (alongside
the rule's own `GIVEN` inputs). ASSUMEs that no published rule reads stay
module-level assumptions and are unaffected. A section `GIVEN` is promoted the
same way.

```l4
ASSUME age IS A NUMBER         -- becomes an input of `isAdult`
ASSUME unused IS A BOOLEAN     -- stays assumed (no @export reads it)

@export Check if the subject is an adult
DECIDE isAdult IS age >= 18
```

### Function-typed inputs are not supported for `@export`

A published rule cannot accept an input that is itself a rule, whether it is
declared as a `GIVEN` input or as an ASSUME the rule reads:

```l4
-- ✘ Rejected when the file is checked, and again at deploy time
ASSUME predicate IS A FUNCTION FROM NUMBER TO BOOLEAN
@export Apply the predicate
DECIDE `applies` IF predicate OF 42
```

A rule cannot be sent as JSON, which is what both request styles carry —
Representational State Transfer (REST) and the Model Context Protocol (MCP) —
and a function-typed ASSUME stays uninterpreted when the rule is run, so any
request would come back with an "assumed term" error rather than an answer. L4
reports `Function type inputs are not supported for @export`, and the service
refuses to deploy such bundles.

## Testing in the file: make the input a rule `GIVEN`

To exercise a rule inside the file, give the rule the input as its own
`GIVEN`; `WITH` then supplies it by name, and this does work today:

```l4
GIVEN age IS A NUMBER
DECIDE isAdult IF age >= 18

#EVAL isAdult WITH age IS 25     -- TRUE
#ASSERT isAdult WITH age IS 25
```

## A name for a whole section

For a name that is an input to every rule in a section rather than to one
definition, a `GIVEN` indented under the section's heading declares it once for
that section. It resolves, runs and exports exactly as a same-section
`ASSUME` term does. See [the section `GIVEN`](../syntax/section-given.md).

## Assuming a type: use `DECLARE` instead

`ASSUME TypeName IS A TYPE` declares a type rather than a value — a type that
is named but not described:

```l4
ASSUME Person IS A TYPE       -- works, but no longer the preferred spelling
```

A bodiless `DECLARE` says the same thing, and is now the spelling to reach for:

```l4
DECLARE Person
```

The two produce the same entity in the type checker, so a file can be migrated
one line at a time and nothing downstream changes. `DECLARE` is preferred
because it puts every type declaration under one keyword, and leaves `ASSUME`
for what its name suggests — assuming a _value_ you have not defined. See
[opaque types](DECLARE.md#opaque-types).

## Related Keywords

- **[GIVEN](../functions/GIVEN.md)** - List a rule's own inputs (a "rule `GIVEN`")
- **[The section `GIVEN`](../syntax/section-given.md)** - Declare a name once for
  a whole section: where a term `ASSUME` goes now
- **[DECIDE](../functions/DECIDE.md)** - Define a value or rule with a body
- **[TYPE-KEYWORDS](keywords.md)** - Type syntax (IS, FUNCTION, and the rest)

## See Also

- **[Types Reference](../types/README.md)** - Type syntax
