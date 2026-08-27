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
- **A subject-matter expert can inspect the rules without reading L4.** The blocks view is
  legible to a domain expert, which makes Blawx useful as a _review_ surface even when it is not
  the deployment target.
- **Defeasibility has somewhere to live.** Blawx expresses rules that defeat other rules directly,
  which is the same structure L4's `SUBJECT-TO`/`NOTWITHSTANDING` work is about.

## The command

```
l4 blawx FILE
```

Compiles the decision-rule subset of `FILE` to a Blawx project — a `.blawx` YAML file, plus the
s(CASP) program it contains.

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

## What it consumes

The **decision-rule subset**, relationalized. Because the target is a logic program rather than a
function, the shape changes more than in the other exports: a decision's result becomes an
argument position, and the body becomes a conjunction of goals to satisfy.

## What doesn't survive

Blawx carries fidelity notes for the constructs s(CASP) cannot take directly. The general pattern
is that anything requiring genuinely functional evaluation — rather than relational satisfaction —
has to be re-expressed, and where that cannot be done faithfully the compiler reports it rather
than emitting a program that would answer a different question.

## Where to look

- **Worked examples:** `jl4/examples/blawx/`, including an `imported/` directory that exercises the
  reverse direction and a `not-ok/` directory of deliberate refusals.
- **Design and rulings:** `BLAWX-EXPORT-SPEC.md` under `specs/`, whose R1–R14 cover the mapping.
