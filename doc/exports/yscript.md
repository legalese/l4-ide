# yscript

## What yscript is

[yscript](https://www.datalex.org) is the rule language of AustLII's DataLex applications-development environment.
AustLII (the Australasian Legal Information Institute) is a decades-old free-access-to-law institute — the Australasian sibling of Cornell's LII — and DataLex is its "Rules as Code" platform: legislation encoded as interactive **consultations** that a citizen or advisor runs against their own facts.
yscript itself predates the term "Rules as Code" by years; its `ysh`/`wysh` ancestors go back to the 1990s.

A yscript codebase is a sequence of blocks:

```
RULE Section 10 - Core foreign arrangements PROVIDES
the arrangement is a "core foreign arrangement" under section 10(2) ONLY IF
    the arrangement is a "foreign arrangement" under section 6 AND
    the Australian entity is a "core State/Territory entity" under section 10(3) AND
    the non-Australian entity is a "core foreign entity" under section 10(4)
```

one `RULE` per legislative provision, by convention — the language was deliberately designed without programming-language symbols so that a lawyer or legislative drafter without a computing background can write and audit it directly.
Running a yscript file produces a consultation: the interpreter asks the user for whichever facts a rule needs (backward-chaining), and as facts arrive it re-derives whatever can now be concluded.

What makes DataLex worth knowing about is not the rule language on its own — it is genuinely narrow, see below — but the **explanation apparatus** built on top of it.
Every consultation exposes, live, at every question: `Why?` (which rule needs this fact, for what conclusion), `How?` (which facts and which rule derived a conclusion), `What if?` (try a hypothetical answer without committing to it), `Forget` (retract an answer and get re-asked whatever depended on it), a verbose rule-firing trace, and an end-of-session natural-language Report.
None of this is separately authored — it is generated automatically from the rule structure itself, which is the same "counter hallucination with guardrailed, robust reasoning" pitch this project makes, built independently, decades ago, for a non-LLM rule engine.

## Why compile to it

Hand a consultation to AustLII's decades-old Rules-as-Code explanation engine, for its `Why?`/`How?`/`What if?` apparatus — for free, over whatever propositional logic your L4 module already expresses.
You are not writing a second copy of the rules to get that apparatus; `l4 export yscript` derives the `RULE`/`PROVIDES`/`ONLY IF` blocks from the same `DECIDE`/`MEANS` definitions and `@ref` citations you already wrote.

## The command

```
l4 export yscript FILE
```

Compiles the pure-propositional-logic subset of `FILE` to yscript source, printed to standard output.

| Flag            | Effect                                                         |
| --------------- | -------------------------------------------------------------- |
| `--output FILE` | write the generated yscript source to `FILE` instead of stdout |

There is no `--package` (yscript has no installable-package concept to mirror docassemble's) and no `--fail-on` (there is no fidelity-severity ladder to gate on — see below).
On success it exits `0`; on refusal it prints every reason, prefixed `l4 export yscript: cannot compile this module to yscript`, and exits non-zero.

## What it consumes

yscript's own executable fragment is **pure propositional logic** — no records, no `GIVEN`-parameterised predicates, no numbers or dates, no deontic layer, and no recursion (disallowed by the language itself).
So the exportable slice of L4 is narrower than any other backend in this family: the boolean closure of every `@export`-annotated **nullary** `DECIDE`/`MEANS` — a `Decide` whose `GIVEN` signature is empty — over `AND`, `OR`, and bare references to other in-fragment nullary `Decide`s or nullary `ASSUME BOOLEAN` facts.
Every `Decide`/`ASSUME` the closure reaches must also be nullary; a parameterised one anywhere in the closure is refused by name, not silently dropped or inlined.

| L4                                                                                            | yscript                                                                     |
| --------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| a nullary `@export`ed `DECIDE`/`MEANS`, and every nullary `Decide` it transitively references | one `RULE ... PROVIDES ... ONLY IF ...` block per `Decide`                  |
| a nullary `ASSUME BOOLEAN` fact                                                               | a bare proposition inside an `ONLY IF` clause — no `RULE` is emitted for it |
| `AND` / `OR`                                                                                  | `AND` / `OR`, directly                                                      |
| a `Decide`'s own (mixfix) name                                                                | the `PROVIDES` proposition text, verbatim                                   |
| a `Decide`'s `@ref` citation                                                                  | the `RULE` label (falls back to the bare L4 name when absent)               |

**The `ASSUME`-for-leaf-facts inversion.**
General L4 house style treats a module-level `ASSUME` as a caution: it stays uninterpreted at evaluation time, and idiomatic L4 threads a record as a `GIVEN` parameter instead.
That advice is for L4 meant to be _evaluated_.
yscript's target is different in kind: a yscript **fact** is, by design, uninterpreted until a live consultation elicits an answer for it — that is not a gap in yscript, it is the entire mechanism.
So for this one backend, a nullary `ASSUME <name> IS A BOOLEAN` is the _correct_, idiomatic-for-this-target shape for a leaf fact, and the derived conclusions are nullary `DECIDE`/`MEANS` over them.
If you are writing L4 specifically to compile to yscript, expect to reach for `ASSUME` more than general L4 style would otherwise recommend.
Expect, too, to see `l4 check` print its own retirement warning for each such top-level `ASSUME`, suggesting a `GIVEN` under a section heading instead — that warning is aimed at L4 meant to be evaluated, it does not block compilation, and for a module written for this backend it is expected and safe to leave as is.

## What doesn't survive

There is no fidelity report and no `--fail-on` severity ladder — unlike docassemble/DMN/BPMN, this backend never emits a degraded-but-present artifact.
Either your module is entirely inside the fragment above and the whole thing is compiled, or any single offender anywhere in the closure means **nothing is written at all**, and every offender is named in one run.
That is a deliberate correctness argument, not just a style preference: a yscript consultation whose rule graph is missing an edge does not fail loudly — it asks the user a raw, unexplained question where an explained conclusion should have appeared, which is exactly the silent-degradation failure this project's exports are built to avoid.

Refused outright, by construction:

- **Any parameterised `Decide`/`ASSUME` in the closure.**
  yscript has no functional/predicate layer to receive arguments.
- **`NOT`.**
  yscript's own negation keyword could not be confirmed against a primary source (both manuals this project could reach 403'd, and the worked examples available contain no negation), so this is refused rather than guessed — a wrong keyword in generated yscript would be a silent miscompile, not a loud one.
- **`IMPLIES` / `EQUALS`.**
  No attested yscript counterpart at all.
- **Records, numbers, dates, deontics, recursion, lists, ledger/effect constructs (`FETCH`/`RECORD`/`RECALL`/...).**
  Outside the propositional fragment entirely.

**No import path back.**
This backend is one-way: L4 → yscript only.
There is no `l4 import yscript`, and nothing reads generated yscript source back into L4.

**AGPL note.**
The yscript _interpreter_ itself is distributed under the GNU Affero GPL.
This backend only ever emits yscript **source text** — it does not vendor or invoke the interpreter — so the AGPL is informational for whoever runs the generated file through AustLII's own tooling, not a constraint on this repository.

## Where to look

- **Worked examples:** `jl4/examples/yscript/` — direct transcriptions of the two worked examples (Foreign Relations Act s10, Hairdressers Act s4(1)) quoted verbatim in the research memo below, so the output can be eyeballed against the same primary-source figures.
- **The research memo:** `specs/research/DATALEX-YSCRIPT-RESEARCH.md` — where yscript's syntax, license, and the stratum-by-stratum overlap with L4 were established.
- **The design spec:** `specs/todo/YSCRIPT-EXPORT-SPEC.md` — the R1-R8 rulings this backend implements.
