# L4 → yscript export: `l4 yscript`

## Status: proposed, not landed (2026-09-21)

This spec is the scoping document for a new, narrow, **one-way** (L4 → yscript, no import) export backend targeting AustLII DataLex's `yscript` rule language.
Commissioned by Meng 2026-09-21, following up on the research memo [`DATALEX-YSCRIPT-RESEARCH.md`](../research/DATALEX-YSCRIPT-RESEARCH.md) (2026-09-08/09), which concluded the fragment is worth backlogging but built nothing.
This spec turns that backlog entry into a buildable scope.

Read the research memo first — this spec does not re-derive yscript's syntax, license, family placement, or the stratum-overlap table (§D there); it only rules on what a compiler for the verified fragment does.

## Why this is small on purpose

Per the memo's own verdict: yscript's executable fragment is **pure propositional logic** — no records, no `GIVEN`-parameterized predicates, no numbers/dates with a defined precision contract, no deontic layer, no recursion (disallowed by the language itself).
Meng's framing (2026-09-21): "not even predicates, so nothing really functional like we have `GIVEN`s."
So this backend does not attempt anything close to Docassemble's or Catala's breadth — it walks one narrow, verified slice of L4 and refuses everything else, loudly.

## R1 — The exportable fragment is the boolean closure of `@export`ed nullary Decides

An exported entry point is a `Decide` found by `L4.Export.collectExportedDecides` whose `GivenSig` is **empty** (arity 0) — a nullary boolean proposition, matching yscript's own fact/proposition model, in which nothing is parameterised.
`formula1 a b c d MEANS ...`-shaped combinators (`jl4/examples/ok/logic.l4`) demonstrate the `AND`/`OR`/`NOT` fragment but are **not** themselves exportable while they carry parameters — only a nullary Decide built by fully applying such a combinator to other nullary atoms is in scope.

The exporter walks the call graph from every exported nullary Decide (the same transitive-closure shape as `L4.Export.decideBodiesFromModule` / the query planner's `inputRefsClosureByUnique`, `jl4-query-plan/src/L4/Decision/QueryPlan.hs:38-84`) and requires **every** `Decide`/`Assume` reached, not just the entry points, to also be arity-0.
A referenced Decide with a nonzero `GivenSig` is refused by name ("has parameters; yscript has no functional/predicate layer over them").

## R2 — Body fragment: `AND`, `OR`, literal references. No `NOT`, no `IMPLIES`/`EQUALS`

Confirmed against the memo's own verbatim worked examples (§C): `AND`/`OR` are directly attested.
**Negation is not.** None of the three verbatim figures the memo reproduced contain a `NOT`, and this session re-checked before writing this spec.
The "Coding in yscript" manual and the DataLex Developer's Manual are still 403'd (`austlii.community`), the O'Hanley blog post that describes `ONLY IF` in detail does not cover negation, and a newly-surfaced AustLII Robodebt submission (`austlii.edu.au/.../CompLRes/2023/1.html`, not checked by the original research session at all) also 403'd on this session's first attempt.

**Ruling: v1 refuses `NOT` rather than guess its spelling.** To be precise about what the original memo actually established versus what this spec adds: the memo's §D overlap table has no row for negation at all — it was never a targeted line of inquiry there, and "the three worked examples happen not to contain `NOT`" is weaker evidence than "we looked for `NOT` and couldn't confirm it."
This spec is the first attempt to actually settle it, and it ran the cheapest falsifying check available (this repo's own convention, user `CLAUDE.md` "keeping written claims true," rule 5) — three fetch attempts, all blocked, reported above.
That is enough to justify refusing rather than guessing, but not enough to claim the question was asked twice; it has been asked once, this session, and answered "still blocked."
Emitting `NOT` on a guessed keyword would be exactly the failure mode that convention exists to prevent: a wrong keyword in generated yscript is a silent miscompile, not a loud one, because nothing downstream re-checks generated yscript against a real interpreter (§ "No differential oracle exists" in the research memo's §F).
`IMPLIES`/`Equals` have no attested yscript counterpart at all (memo §D marks the concept itself **OUT**) and are refused unconditionally.

**Reopening this ruling** needs one thing: a successful fetch of either manual, or an institutional/browser session that can read `austlii.community`.
Retry there before touching the code — this is a research task, not an implementation one.

So the supported body grammar, precisely:

```
Body  ::= Atom | Body AND Body | Body OR Body
Atom  ::= reference to another in-fragment nullary Decide, or an ASSUME BOOLEAN
```

## R3 — `ASSUME BOOLEAN` is the leaf-fact construct; the "ASSUME is uninterpreted" caution does not apply here

`legalese/l4-ide/CLAUDE.md` §5 warns that `ASSUME` is uninterpreted and that idiomatic L4 threads a record as one `GIVEN` parameter instead — sound advice for L4 written to be _evaluated_.
This backend's target is different in kind: a yscript **fact** is, by design, an uninterpreted proposition until a live consultation elicits an answer for it.
That is not a gap in yscript, it is the entire mechanism (§B of the research memo: "there is no separate coding of what a codebase should 'do' … all interactions are generated automatically from the facts").
A nullary `ASSUME BOOLEAN` is therefore the correct, idiomatic-for-this-target L4 shape for a yscript leaf fact, and the exporter treats it as such: no `RULE` is emitted for it, it appears only as bare proposition text inside whichever `ONLY IF` clauses reference it, and yscript's own interpreter will ask the user about it because nothing `PROVIDES` it.

Consequence for anyone writing L4 meant to compile to yscript: author the leaf facts as `ASSUME <name> IS A BOOLEAN` and the derived conclusions as nullary `DECIDE`/`MEANS` over them.
This is worth a sentence on the `doc/` page (R8) because it inverts general L4 house style.

## R4 — Proposition and rule-label text comes from L4's own name, not a hand-built renderer

L4 mixfix names already read as natural English sentences with `_` slot markers (`_ is a "core foreign arrangement" under section _`), and this is the single biggest scope-reducer for this backend: authoring a Decide with a natural mixfix name (the established L4 house style for anything user-facing) produces yscript proposition text "for free," matching the worked examples' own style (`the arrangement is a "core foreign arrangement" under section 10(2)`).
Do not hand-write a name-to-English renderer.

**As landed, this reuses the same plain accessor every sibling backend already uses for identifier text** (`L4.Export`, `L4.Docassemble.Lower`, `L4.Catala.Lower`) — `resolvedToText = rawNameToText . rawName . getActual` in `L4.Yscript.Lower` — rather than the `L4.Print.restoreMixfixPatterns` + `prettyLayout` route this ruling originally proposed.
That earlier proposal turned out to be unnecessary machinery, not a wrong idea: `restoreMixfixPatterns` only stamps a surface pattern onto an `App`/`AppForm` node with a **non-empty** argument list, so it exists to re-fill a mixfix's `_` slots with its actual call-site arguments.
R1 forces every atom in this backend's fragment to be nullary — no atom ever has an argument to fill a slot with — so for exactly this fragment the two routes are provably equivalent, and the simpler accessor avoids two side effects `prettyLayout` carries for L4-source round-tripping that would otherwise have to be stripped back off: it wraps a name containing spaces/quotes in backticks (`quoteIfNeeded`), and it can append an `inlineNlgOf` `[nlg: ...]` debug-annotation bracket meant for value-interpolation templates, neither of which belongs in yscript prose.
`lowerModule`'s signature is therefore the plain `Module Resolved -> Either [LowerError] [YsRule]`, with no `TC.MixfixRegistry` to thread through it.

If this backend's fragment is ever widened to admit parameterised atoms (not currently planned — see "What this spec deliberately does not do"), this equivalence breaks and the mixfix-printer route becomes necessary, not merely available.

The `RULE` **label** (the line after `RULE`, before `PROVIDES`) is separate from the proposition text in every worked example (`RULE Section 10 - Core foreign arrangements PROVIDES ...`).
Derive it from the Decide's `@ref`/citation annotation when present (`REF-ANNOTATION-SPEC.md`), falling back to the bare definition name when it is not.
An absent citation is not a refusal — it just means a less informative label, which is worth an `Advisory`-shaded note even though this backend has no formal fidelity report (R6).

## R5 — Refusal is whole-run, not partial, and every offender is reported in one pass

**Ruling: if any Decide in the reachable export closure is out-of-fragment, the whole run refuses — no file is written.**
This is a correctness argument, not just a style preference: a yscript consultation whose rule graph is missing an edge (because the L4 side had a sub-rule this backend silently dropped) does not fail loudly — it just asks the user a raw, unexplained question where an explained conclusion should have appeared.
That is precisely the kind of silent-degradation failure the `doc/exports/README.md` house principle ("They would rather refuse than lie") exists to prevent, and it is sharper here than for Docassemble/DMN because DataLex's entire value proposition (per the memo) is the explanation apparatus built from that rule graph.

Reuse Catala's error-accumulating pattern (`L4.Catala.Lower`'s `newtype V a = V (Either [LowerError] a)` Applicative) so a single run reports **every** offending Decide, not just the first — cheaper for a drafter to fix in one pass than to discover one refusal at a time.

`LowerError` for this backend needs only a name and a reason string; no `FidelityReport` (`L4.Interchange.Fidelity`) — that type exists for backends that emit a _degraded but present_ artifact, which this backend, by R5, never does.

## R6 — The command

```
l4 yscript FILE [--output FILE]
```

No `--package` (yscript has no installable-package concept to mirror Docassemble's), no `--fail-on` (moot under R5's all-or-nothing refusal — there is no severity ladder to gate on).
Prints to stdout by default, matching every other export's default.
On refusal, print each `LowerError` prefixed `l4 yscript: cannot compile this module to yscript ...` (mirroring Docassemble's message shape) and exit non-zero; on success, exit 0.

## R7 — Testing

- `jl4/tests-cli/fixtures/yscript-*.l4` — shape-probe fixtures for each refusal case in R1/R2: a parameterised Decide in the closure, a `NOT`/`IMPLIES`/`Equals` use, a non-boolean `ASSUME`.
  Asserted inline in `jl4/tests-cli/Main.hs` (exit code + stderr content), the same style as the existing `docassemble-*.l4` probes there — not file-diffed goldens.
- `jl4/examples/yscript/` — 2-3 worked examples with `expected/*.ys` output, diffed by the CLI test suite.
  The natural first two are direct transcriptions of the Hairdressers Act s4(1) and Foreign Relations Act s10 examples already quoted verbatim in `specs/research/DATALEX-YSCRIPT-RESEARCH.md` §C — reusing them here means the export's output can be eyeballed against the same primary-source figures the research memo already cites, which is as close to a differential oracle as this backend gets (the memo's own §F already notes no scriptable yscript interpreter was found to invoke as a real oracle).
- Per `legalese/l4-ide/CLAUDE.md` §3.1, `jl4/examples/<backend>/` directories are outside every golden glob by directory name, so `jl4/examples/yscript/` inherits that exemption automatically — no `jl4-test` corpus goldens are needed for it, only this CLI suite's own `expected/` diff.

## R8 — Documentation

New `doc/exports/yscript.md`, same shape as `doc/exports/docassemble.md` (What yscript is / Why compile to it / The command / What it consumes / What doesn't survive / Where to look), plus:

- A new row in `doc/exports/README.md`'s comparison table and "which one do I want" list — candidate framing: "Hand a consultation to AustLII's decades-old Rules-as-Code explanation engine, for its `Why?`/`How?`/`What if?` apparatus" — and a new `doc/SUMMARY.md` entry.
- **State the limits explicitly** (CLAUDE.md §6): no records, no numbers, no dates, no deontic layer, no recursion, no negation (R2, and say why: unverified, not merely unimplemented), no import path back.
- Note the `ASSUME`-for-leaf-facts inversion from R3 plainly, since it cuts against general L4 house style and a reader who only knows the rest of the manual would reasonably not expect it.
- AGPL note: the yscript interpreter itself is AGPL-licensed (research memo §B).
  This backend only emits yscript **source text**; it does not vendor or invoke the interpreter, so this is informational for whoever runs the output through AustLII's tooling, not a constraint on this repository.
  Say so on the page rather than leaving a reader to wonder.

## What this spec deliberately does not do

No differential oracle, no round-trip, no `--package` layout, no fidelity-severity ladder, no attempt at `XOR` (L4 has no primitive for it either — memo §D — and nothing in the fragment needs it yet).
If a real use case ever needs more than this narrow slice, it gets a new ruling here, not a silent expansion of what "refuse loudly" quietly stops refusing.

## Sources

Everything not re-derived here is in [`DATALEX-YSCRIPT-RESEARCH.md`](../research/DATALEX-YSCRIPT-RESEARCH.md) §G.
This session's own additions, all new — none of these three URLs were fetched by the original research session: a retry of `austlii.community/foswiki/pub/DataLex/WebHome/ys-manual.pdf` (HTTP 403); a re-read of `wohanley.com/posts/visual-yscript/`, already cited in the memo but re-fetched here with a negation-specific question (fetched successfully; confirms `ONLY IF` composition but says nothing about negation); and a first attempt at AustLII's Robodebt Royal Commission submission, `www8.austlii.edu.au/cgi-bin/viewdoc/au/other/CompLRes/2023/1.html`, surfaced by this session's own search and not in the original memo's source list at all (HTTP 403).
