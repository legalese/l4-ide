# docassemble

## What docassemble is

[docassemble](https://docassemble.org) is a free, open-source platform for **guided interviews**.
It asks a person a series of questions, one screen at a time, works out which questions are
actually needed, and at the end produces an answer, a filled-in document, or both.

It is widely used in access-to-justice work — legal aid organisations, court self-help centres and
pro bono projects build docassemble interviews so that someone with no lawyer can find out where
they stand, and walk away with the letter or form they need. Interviews are written in YAML,
deployed on a server, and used through an ordinary web browser.

The part that matters for L4 is how docassemble decides what to ask. You do not write a
questionnaire in order. You declare what each fact _is_, and docassemble works backwards from the
answer it needs: to know the verdict it needs these facts, to get that fact it must ask this
question. Questions the answer does not depend on are never asked at all.

## Why compile L4 to it

That backwards search is the same thing L4's own query planner does — so an L4 decision is already
the shape docassemble wants. Compiling to it means:

- **A member of the public can use your rules.** They answer plain questions in a browser instead
  of reading a statute or an encoding of one.
- **Nobody is asked more than necessary.** Because docassemble backchains, an applicant who fails
  the first eligibility gate is never asked the twenty questions behind the second one.
- **The answer explains itself.** Where your L4 carries `@ref` citations, the verdict screen shows
  which rules produced the result, so the person is told _why_, not just _what_.
- **It can produce the document too.** docassemble does document assembly as well as questioning,
  so the same run that reaches a verdict can hand back the notice or letter that follows from it.

## The command

```
l4 docassemble FILE
```

Compiles the decision-rule subset of `FILE` to a docassemble interview in YAML, and prints it to
standard output.

| Flag                 | Effect                                                                                                   |
| -------------------- | -------------------------------------------------------------------------------------------------------- |
| `--output FILE`      | write the interview YAML to `FILE` instead of stdout                                                     |
| `--package DIR`      | write a complete installable docassemble package tree (PEP 420 layout) into `DIR`                        |
| `--fail-on SEVERITY` | exit non-zero on a fidelity note this severe or worse: `none` (default), `blocking`, `lossy`, `advisory` |

`--package` is the one to use for anything real: it produces the directory structure docassemble
expects to install, with the interview, a generated runtime module, and a byte-for-byte copy of
the L4 sources as provenance, so the server carries the evidence of what it was built from.

## What it consumes

The **decision-rule subset**: `@export`-annotated `DECIDE`/`MEANS` definitions and the records,
enumerations and helper definitions they depend on.

Datatypes map about as you would expect — booleans become yes/no questions, numbers a numeric
field, dates a date picker, and an enumeration of nullary constructors becomes a radio list whose
stored values are the L4 constructor names. Lists of records are gathered with docassemble's own
repeated-item machinery, and `MAYBE` values become a paired "is this known?" question.

A `TYPICALLY` default becomes a docassemble `default:` — the question is still asked, but arrives
pre-filled with the typical answer, which the user can change. Worth contrasting with
[Blawx](blawx.md), which deliberately **drops** `TYPICALLY` rather than seeding it, on the grounds
that pre-filling would answer the very question its interview exists to ask. The same annotation,
honoured by one interaction backend and dropped by the other, and both are right for what they are
for.

## What doesn't survive

Run with `--fail-on` or read the emitted fidelity report; the recurring items are:

- **Exact numbers become floats.** L4 `NUMBER` is an exact rational; docassemble computes in
  Python floats. This is the same class of divergence as OpenFisca's, and it is reported once per
  module rather than at every site. Note in particular that docassemble's `currency` datatype
  coerces through `float()`, so it is never emitted for money that must be exact.
- **Names get sanitised, and the sanitised name can collide.** docassemble variables live in a
  Python namespace that already contains builtins and a large utility library. The compiler
  reserves those names and refuses a collision rather than emitting a rule that would quietly
  read the wrong value.

## Where to look

- **Worked examples:** `jl4/examples/docassemble/` — every one is pinned by the test suite, and
  its `README.md` carries the transcript of them running against real docassemble.
- **Design and rulings:** `DOCASSEMBLE-EXPORT-SPEC.md` under `specs/`.
- **Evidence:** the examples have been executed against `docassemble.base` 1.10.7, driven from
  both the bare YAML and an installed `--package` tree, asserting the two agree.
