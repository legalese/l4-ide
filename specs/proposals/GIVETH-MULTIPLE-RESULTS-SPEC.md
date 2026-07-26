# GIVETH with Multiple Named Results

**Status:** Proposal — **not accepted**, written to be reviewed and possibly rejected
**Author:** drafted by Claude (session `lexipedia`), from a suggestion by Meng Wong
**Date:** 2026-07-26
**Related:** [DMN-EXPORT-PROGRAM-MODEL-SPEC.md](../todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md)

---

## 0. What this document is, and the standard it must meet

This proposes a **surface-syntax change to L4**: letting `GIVETH` name several results, the way
`GIVEN` already names several parameters.

It exists because the idea came up in conversation and sounded good, which is exactly the
condition under which a language change should be written down and attacked rather than built.
**The bar is not "is this nice"; it is "is this necessary, and is it the smallest thing that
works."** §7 argues the case against, and §8 lists the questions a reviewer should press on. A
reviewer who concludes "reject, use a `DECLARE`" has done the job correctly.

Everything in §1–§3 is verified against the codebase; §4 onward is design.

---

## 1. The motivating fact (verified)

L4 already lets a decision return a record. Record construction is `T WITH field IS value, …`,
used throughout the corpus:

```l4
`Jersey Heritage Ltd` MEANS Entity WITH
    name                         IS "Jersey Heritage Ltd"
    `(f) a company`              IS TRUE
```

(`paper/case-studies/charities-jersey-2014/part-1-interpretation.l4:308`.) It parses at
`jl4-core/src/L4/Parser.hs:2082` into `AppNamed Anno n [NamedExpr n]`, where
`NamedExpr = MkNamedExpr Anno n (Expr n)` — a list of name/expression pairs.

So **nothing prevents an L4 decision from returning several values today.** It returns one record.
The claim in `jl4-core/src/L4/Dmn/IR.hs` that "L4 decisions return one value, so there is exactly
one" is wrong and should be corrected independently of this proposal.

## 2. The asymmetry

```haskell
data GivenSig  n = MkGivenSig  Anno [OptionallyTypedName n]   -- a NAMED LIST
data GivethSig n = MkGivethSig Anno (Type' n)                 -- one type
```

`GIVEN` takes a named list. `GIVETH` takes a single type. The proposal is to make them symmetric.

## 3. The downstream pull (verified)

DMN decision tables may have multiple **output clauses**, and DMN 1.3 §8.1 requires each to be
named: _"A single output has no name, only a value. Two or more outputs are called output
components. Each output component SHALL be named."_ A record literal's `[NamedExpr]` is already
exactly a multi-output rule row — one named output entry per component.

Two further facts bear on urgency, both verified by execution:

- A record-returning decision **currently emits broken DMN**: the output entry is written as L4
  surface text (`Assessment WITH rate IS 40 band IS high`), which is XSD-valid but which
  Drools/KIE 8.44 refuses to compile. `MAYBE`-valued outputs fail identically (`JUST(...)` →
  `Unknown variable 'JUST'`) and **already occur in the shipped Charities corpus**.
- `dmnmd` already supports N output columns end-to-end, so the exporter is the constrained side.

**Note carefully:** neither of those requires this proposal. Both are fixed by teaching the
exporter to lower a _nominal_ record (`DECLARE` + `GIVETH A T`) to a multi-output table. This
proposal is only about **not having to write the `DECLARE`**. That distinction is the crux of §7.

## 4. The proposal

Let `GIVETH` accept the same `[OptionallyTypedName]` list that `GIVEN` accepts:

```l4
GIVEN  c      IS A CandidateCharity
GIVETH `rate` IS A NUMBER
       `band` IS A STRING
DECIDE `routing` c IS
  IF   … THEN rate IS 10, band IS "high"
  ELSE        rate IS 5,  band IS "low"
```

Desugaring, in outline: the `GIVETH` list induces a record type; each branch body is an
`AppNamed` over the same field names with the constructor elided.

Consumption is by projection on the result, using existing syntax:

```l4
(`routing` c)'s `rate`
```

## 5. What it buys

1. **No one-off `DECLARE` per multi-result decision.** A `DECLARE` introduces a _module-level
   name_ for something that may be purely local to one decision, and module-level names are the
   scarce resource in a legal corpus, where `DECLARE`d types mirror statutory entities.
2. **Names for DMN's output components come from the source** rather than being synthesised. A
   positional tuple would force the exporter to invent them; DMN requires them.
3. **Symmetry.** `GIVEN`/`GIVETH` reading the same way is a real learnability property in a
   language aimed at non-programmers.
4. **No new AST vocabulary** — reuses `OptionallyTypedName` and `NamedExpr`.

## 6. What it costs — the honest list

1. **It introduces an anonymous type.** L4's records are **nominal** (`DECLARE T HAS …`).
   A `GIVETH` list either (a) generates a nominal type behind the scenes, with a derived name and
   all the collision and error-message consequences that implies, or (b) introduces **structural
   records**, which is a type-system change of a completely different magnitude from a syntax
   sugar. **This proposal does not currently say which**, and that is its most serious defect.
2. **Type identity is undefined.** Are two decisions that both write
   `GIVETH rate IS A NUMBER, band IS A STRING` returning the _same_ type? Under (a) no, under
   (b) yes. Every downstream question — assignability, `CONSIDER` over the result, `@export`
   schema generation — depends on this answer.
3. **A second way to say an existing thing.** Two spellings of "return a record" is a permanent
   comprehension cost paid by every future reader, in exchange for saving one line at the
   definition site.
4. **Error messages.** A type error mentioning a compiler-generated record name is materially
   worse than one mentioning `Assessment`.
5. **Exactprint.** L4's formatter must round-trip source exactly; a desugaring that erases the
   `GIVETH` list into a synthesised `DECLARE` has to be re-inflated on the way out. See the
   mixfix-format work for how sharp this edge is.
6. **`@export` boundary.** The JSON schema for an exported decision is generated from its type. An
   anonymous type needs a name in the schema, and that name becomes part of a **public API
   contract** — so "derived" is not a safe answer.

## 7. The case for rejecting this proposal

Stated as strongly as it deserves, because the reviewer should not have to construct it.

**The corpus does not want it.** Across all three legal corpora — Reg CF, Charities, Housing Act —
there are **zero** record constructions in any `THEN`/`ELSE`/`OTHERWISE` position (verified; a
positive control fires five hits on a synthetic probe). Not "few". None. The construct this sugar
sweetens is currently **unused in every corpus we have**.

**The DMN motivation does not need it.** Everything in §3 is fixed by lowering nominal records to
multi-output tables. This proposal adds nothing to that fix; it only removes a `DECLARE`.

**The ceremony being removed is small, and arguably load-bearing.** In legal drafting, naming the
thing you are computing is usually _good_ — `DECLARE Assessment HAS rate …; band …` documents that
these two values travel together and gives reviewers something to cite. A statute that computes a
rate and a band together almost certainly has a word for that pair.

**The cost is a type-system question, not a parser question.** §6.1 and §6.2 are the real content
here, and they are not sugar-shaped.

A reasonable outcome of review is therefore: **reject; require `DECLARE`; revisit only if a corpus
appears that writes multi-result decisions often enough for the ceremony to bite.**

## 8. Questions a reviewer should press on

1. **Nominal or structural?** If nominal-with-a-derived-name: what is the name, what happens on
   collision, and what does a type error print? If structural: what else in L4 becomes structural,
   and what does that do to inference and to `DECLARE`'s meaning?
2. **Is `GIVETH x IS A BOOLEAN` (one named result) the same as `GIVETH A BOOLEAN`?** If yes, the
   grammar is ambiguous; if no, there are two near-identical spellings with different types, which
   is worse.
3. **Interaction with `DECIDE … IF`,** which expects a Boolean. Is a multi-result `DECIDE … IF`
   legal? What would it mean?
4. **Branch bodies.** Is `rate IS 10, band IS "high"` a new expression form, or `AppNamed` with an
   elided head? If the latter, how does the parser disambiguate it from a comma-separated
   something-else, and what does the error look like when a field is omitted or misspelled?
5. **Exhaustiveness.** Must every branch bind every field? If a field may be omitted, is the result
   `MAYBE`-typed, and does that interact with the `NOTHING`-incomparability problem already known
   in the prelude?
6. **`CONSIDER` / pattern matching** over a multi-result decision's value.
7. **`@export`**: what name appears in the generated JSON schema, and is it stable across edits to
   an unrelated part of the module?
8. **Exactprint**: does `l4 format` round-trip a `GIVETH` list byte-identically?
9. **Is there a smaller change** that gets the same benefit — e.g. a local `DECLARE` scoped to a
   `§` or a `WHERE`, which would reduce module-level namespace pressure without introducing an
   anonymous type at all?
10. **Prior art.** What do comparable languages do — Haskell's anonymous records debate (and why it
    stayed unresolved for a decade), OCaml objects/rows, TypeScript structural types, Ada's `out`
    parameters, SQL's multi-column results? Which of those is L4 actually most like?

## 9. Alternatives

| #   | Alternative                                                | Comment                                                                                                                                        |
| --- | ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| A   | **Status quo**: require `DECLARE T HAS …` and `GIVETH A T` | Zero language risk; the exporter work proceeds unchanged. §7's recommendation.                                                                 |
| B   | This proposal (named `GIVETH` list)                        | Under discussion.                                                                                                                              |
| C   | **Section- or `WHERE`-local `DECLARE`**                    | Addresses the actual complaint (module-namespace pressure) without an anonymous type. Possibly the smallest thing that works — see Q9.         |
| D   | **Positional tuple** `GIVETH A NUMBER, A STRING`           | Rejected on sight: DMN requires named output components, and unnamed results are bad legal drafting. Recorded so review need not re-derive it. |

## 10. Explicit non-goals

- This is **not** required for the DMN multi-output work. That work depends only on lowering
  nominal records, and must not be sequenced behind this.
- No change to `GIVEN`.
- No change to how records are constructed (`T WITH …` stays).
