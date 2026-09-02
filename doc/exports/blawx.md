# Blawx

## What Blawx is

[Blawx](https://www.blawx.com) is a web-based, **visual** rules-as-code tool aimed at people who
know the law but do not write code. Instead of typing syntax you assemble rules from drag-and-drop
blocks in the browser, describe the concepts your rules talk about, and then ask questions of them.

Underneath the blocks is **s(CASP)**, a goal-directed answer-set programming system. That choice is
what gives Blawx its distinctive abilities, because s(CASP) does not merely return an answer — it
can explain how it got there, and it can reason about facts it has not been told.

In practice a Blawx project gives you four things:

- **A justification tree in natural language** for every answer — not a log, but a readable
  account of which rules fired and why.
- **A scenario explorer** that walks a user through the facts a question needs.
- **Hypothetical, or abductive, reasoning**: rather than only answering "given these facts, what
  follows?", it can answer "what would have to be true for this outcome to hold?"
- **A REST API** per rule.

## Why compile L4 to it

Blawx is the export that gives back the most L4 does not already have. The compiler's central move
is **relationalization**: an L4 decision that _returns_ a value becomes an s(CASP) relation where
the result is one of the arguments, and expression trees become conjunctions of goals. That is
what makes the logic-programming abilities above available to rules you wrote in L4.

- **Explanations you can hand to a claimant.** The justification tree is the thing most rules
  engines cannot produce and most legal users most want.
- **Ask the question backwards.** Abductive reasoning lets you ask what facts would change the
  outcome — a question a forward evaluator cannot answer.
- **A subject-matter expert can inspect _and edit_ the rules without reading L4.** The blocks view
  is legible to a domain expert — and an emitted project opens in the real Blawx editor and saves
  back **byte-identical**, so their edits are not fighting a generator that rewrites the file
  underneath them. That is what makes Blawx a genuine review-and-edit surface rather than a
  one-shot dump.
- **The explanation cites the statute.** Workspaces are anchored per `@export` decision with
  synthesized rule text, and the identifiers Blawx regenerates line up with the emitted workspace
  names — so the justification tree points back at the source provision, not just at a rule name.
- **Defeasibility has somewhere to live.** Blawx expresses rules that defeat other rules directly,
  which is the structure L4's `SUBJECT-TO`/`NOTWITHSTANDING` spec _proposes_ — **proposed, not
  implemented**. `UNLESS` is the shipped L4 operator today.

## The command

```
l4 blawx FILE
```

Compiles the decision-rule subset of `FILE` to a Blawx project and prints the `.blawx` YAML to
standard output. The s(CASP) program is written alongside it only when you pass `--output`.

| Flag            | Effect                                                                     |
| --------------- | -------------------------------------------------------------------------- |
| `--output FILE` | write the `.blawx` YAML to `FILE`, and the s(CASP) dump alongside it       |
| `--scasp`       | emit the concatenated s(CASP) program instead of the `.blawx` YAML         |
| `--import`      | **read** a `.blawx` project and lift it back to L4 — the reverse direction |
| `--parse-only`  | with `--import`: parse and report without lifting                          |
| `--reemit`      | with `--import`: re-emit the `.blawx` from what was parsed                 |
| `--roundtrip`   | self-check: emit, parse back, and assert the two agree                     |

`--scasp` is the one to reach for when debugging: it hands you the logic program itself, which you
can run against an s(CASP) system directly without going through the Blawx UI.

## The only two-way export

Blawx is the **one** backend that reads its own format back. `l4 blawx --import` parses a `.blawx`
project and lifts it to L4, and `--roundtrip` checks that emitting and re-importing round-trips
faithfully.

This matters if you have existing Blawx work: it is a migration path in, not only a projection
out. Every other export on these pages is one-way.

**How much it reads, as of 2026-09-02.** What comes back is measured rather than assumed. Three of
Blawx's own shipped examples live under `jl4/examples/blawx/imported/`: **bird** (the defeasibility
tutorial, where sections defeat one another), **beard_tax** (a number-valued attribute and the
comparisons on it) and **Rock Paper Scissors** (objects related by two- and three-place predicates,
a rule that quantifies over "the other player", and a test that declares its own objects). All
three lift to L4 that type-checks, and the tier-1 harness puts each of their queries to real
s(CASP) and to the L4 engine and compares the answers.

The fragment is a **universe of objects** under predicates of any arity, plus **value-typed
attributes**: a `number` attribute becomes an optional field with two readers — "is it set?" and
"what is it?" — and a comparison on it becomes an ordinary L4 comparison, while a category-valued
attribute is a binary predicate over the universe. A section's **paragraph** canvases
(`sec_1__para_a_section`) fold into their numbered parent, which is warned about and keeps the
paragraph's own eId on the decision's `@ref` line — and an `overrules` the fold cannot carry across
unchanged is refused rather than folded, because Blawx keys defeat on the exact section.

What does not come back yet is a list, not a guess — the import refuses one construct at a time,
by name. Rules that _compute_ an attribute's value, arithmetic, and the date and event layers do
not lift. A test canvas asking for **hypothetical** reasoning (Blawx's `#abducible`) is dropped,
because abduction is not evaluation; the reason is written into the lifted file where that test's
`#EVAL` would have been, so you can see what you did not get without re-running anything.

## What it consumes

The **decision-rule subset**, relationalized. Because the target is a logic program rather than a
function, the shape changes more than in the other exports: a decision's result becomes an
argument position, and the body becomes a conjunction of goals to satisfy.

## What doesn't survive

Two different things happen, and it matters which one you are looking at.

**Blocking — the compiler refuses**, with a named diagnostic and nothing emitted. Each of these has
a fixture under `jl4/examples/blawx/not-ok/`:

- a `DATE`-sorted field or argument (v1)
- a `STRING` sort anywhere in a signature — field, parameter or result, and including a derived
  predicate small enough that Blawx never declares it. Blawx's attribute-type dropdown is a closed
  list — boolean, number, date, time, datetime, duration, list, and the categories you declared —
  so a string-typed field has no value type to be declared under. Write an enum
  (`DECLARE … IS ONE OF …`) if the values are a fixed vocabulary, or drop the field if the string
  was only carrying identity: a record is already a category, and Blawx tells objects apart by
  atom. String _literals_ in a rule body are fine, and survive as atoms you can compare for
  equality; so is a `LIST OF STRING`, which is declared under the untyped `list` type.
- more than ten arguments — a Blawx relationship block's ceiling
- fewer than three, unless the shape is attribute-like (one category-sorted parameter plus an
  optional result); Blawx relationships start at three
- a subjectless nullary input
- **unstratified negation** — a cycle through a negation. The shared middle-end admits it; the
  Blawx leg is where it is refused.
- **`EQUALS` (or a disequality) on two whole records** — including records inside a `LIST OF` or a
  `LIST OF MAYBE`. L4 compares records by value, Blawx compares objects by atom, and the test
  flattening gives each _occurrence_ of a record value its own object — so two structurally equal
  records reach the reasoner as two different atoms, and two structurally equal lists of them reach
  it as two lists of different atoms. Until the flattening shares one object per distinct value,
  this is refused rather than emitted, because the emitted version runs and quietly answers
  differently. Say the rule once per slot (which needs no identity at all), or compare an enum- or
  number-valued field of the two records. This does **not** apply to a category you introduced with
  `ASSUME T IS A TYPE`: it has no fields to compare structurally, its values are plain atoms on
  both sides, and `EQUALS` on two of them still compiles.

**Lossy — the compiler emits anyway and tells you what it dropped.** The one to know is
`TYPICALLY` on an `ASSUME`. The name becomes an input predicate and the default is deliberately
**not** seeded, because seeding it "would answer the question the target's interview exists to
ask". That is a design decision rather than a limitation: Blawx's whole value is asking the user,
so pre-filling their answer would defeat it.

Worth setting beside [docassemble](docassemble.md), which consumes `TYPICALLY` as a `default:`
prefill. The same L4 annotation is honoured by one interaction backend and deliberately dropped by
the other, and both are right for what they are for.

## Before you deploy on a stock Blawx instance

Two limits our encodings hit on an unmodified Blawx, both reported upstream. Neither is a defect in
your L4, and hitting one does not mean the export is broken:

- the interview endpoint's assumption-finding can crash on classical negation in the answer tree,
  which our negation-carrying encodings trigger; and
- abductive search gets impractically slow when input predicates are left unpinned — pinning a
  couple of pruning facts is the difference between seconds and minutes.

The test-editor `run/` path is unaffected, which is why demos drive it.

## Where to look

- **Worked examples:** `jl4/examples/blawx/`, including an `imported/` directory that exercises the
  reverse direction and a `not-ok/` directory of deliberate refusals.
- **Design and rulings:** `BLAWX-EXPORT-SPEC.md` under `specs/`, whose R1–R14 cover the mapping.
