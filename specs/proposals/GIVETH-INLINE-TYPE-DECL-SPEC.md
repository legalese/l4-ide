# Inline Type Declarations in `GIVETH` Position

**Status:** Proposal — **not accepted**, written to be attacked
**Author:** drafted by Claude (session `lexipedia`), from suggestions by Meng Wong
**Date:** 2026-07-26
**Supersedes:** [GIVETH-MULTIPLE-RESULTS-SPEC.md](./GIVETH-MULTIPLE-RESULTS-SPEC.md) — **rejected
5/5** by adversarial review, four fatal defects
**Related:** [DMN-EXPORT-PROGRAM-MODEL-SPEC.md](../todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md)

---

## 0. Provenance, and what changed

The predecessor proposed an **anonymous** named-result list (`GIVETH rate IS A NUMBER, band IS A
STRING`). It was rejected unanimously, with four fatal findings; the decisive ones were that its
sole benefit (module-namespace relief) is **false twice over** — section-local `DECLARE` already
works and is already corpus practice at 57/70 declarations, and projection is module-scope
selector-function application so the field names land in that namespace regardless — and that the
synthetic type name would leak into a **deployed public API** via `FunctionSchema.hs`'s `x-l4-type`.

The review left exactly one revival path: a **named** inline form, where the author chooses the
name. This document specs that, generalised in two directions Meng raised immediately afterwards
and which the review never considered:

- **sum types** — `GIVETH A Verdict IS ONE OF …`, not just records;
- **type constructors** — the corpus's actual multi-result shape is `GIVETH A MAYBE Part6Penalty`.

Both generalisations make the proposal more interesting **and** expose a new problem the
predecessor did not have (§5). This document is again written to be rejected if it deserves it.

---

## 1. Verified ground (all executed, this session)

| #   | Fact                                                                                                                                                                                          | Evidence                                                |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| 1   | **One-line `DECLARE` already works, in both forms.** `DECLARE Rec HAS \`a\` IS A NUMBER, \`b\` IS A STRING`and`DECLARE Verdict IS ONE OF \`granted\`, \`refused\``both give`Check succeeded.` | `l4 check`, scratch probe                               |
| 2   | A `MAYBE`-wrapped user type as a result works and evaluates: `GIVETH A MAYBE Verdict`, `JUST \`granted\``→`JUST OF granted`                                                                   | `l4 run`                                                |
| 3   | One-line **record literals** parse and evaluate: `Rec WITH \`a\` IS 1, \`b\` IS "hi"`→`Rec OF 1, "hi"`                                                                                        | `l4 run`                                                |
| 4   | `TypeDecl` has exactly three forms: `RecordDecl` (`HAS`), `EnumDecl` (`IS ONE OF`), `SynonymDecl`                                                                                             | `Syntax.hs:190-193`                                     |
| 5   | Section-local `DECLARE` resolves across `§`s via `withQualified`; 57/70 Charities declarations are already `§`-scoped                                                                         | `TypeCheck.hs:2531-2561`; review, verified by execution |
| 6   | `WHERE`-local `DECLARE` does **not** exist — `LocalDecl` has only `LocalDecide`/`LocalAssume`                                                                                                 | `Syntax.hs:431-435`                                     |
| 7   | Per-field `@desc` annotations on a `DECLARE` feed the exported JSON schema                                                                                                                    | `housing-act-wizard.l4:55-60`; `FunctionSchema.hs`      |
| 8   | The corpus's real multi-result decisions are `GIVETH A MAYBE Part6Penalty` × 4, branches returning `JUST \<citation-named constant\>`                                                         | `part-6-use-of-terms.l4:548-573`                        |

**Fact 1 sets the size of the prize.** The ceremony this proposal removes is not a multi-line
block. It is the keyword `DECLARE` and one newline:

```l4
DECLARE Verdict IS ONE OF `granted`, `refused`      -- today, one line
GIVETH A Verdict IS ONE OF `granted`, `refused`     -- proposed, saves `DECLARE` + a newline
```

Any reviewer should weigh every cost below against exactly that.

---

## 2. The proposal

`GIVETH` may carry an inline `TypeDecl` body, with a name chosen by the author. All three
`TypeDecl` forms, for uniformity:

```l4
GIVETH AN Assessment HAS `rate` IS A NUMBER, `band` IS A STRING     -- RecordDecl
GIVETH A Verdict IS ONE OF `granted`, `refused`, `adjourned`        -- EnumDecl
GIVETH A Basis IS A NUMBER                                          -- SynonymDecl
```

Desugaring: lift the body to a `DECLARE` at the enclosing scope, keeping the author's name.

## 3. Why the two generalisations matter

### 3.1 Sum types are the better half of this proposal

The predecessor's fatal drafting objection was that a headless field list **destroys the
citation-bearing name**: the corpus writes `THEN JUST` `` `the penalty under Article 21(10) —
contravening (1), (3) or (5)` ``, and inline `rate IS 10, band IS "high"` cannot express that.

**That objection does not transfer to `IS ONE OF`,** because an enum's constructors _are_ names:

```l4
GIVETH A Part6Penalty IS ONE OF
  `the penalty under Article 21(10) — contravening (1), (3) or (5)`
  `the penalty under Article 21(9) — contravening (2), (4) or (6)`
```

The citation survives, in the position the corpus already puts it. So the record and enum forms
should be **judged separately**; a reviewer who rejects one has not thereby rejected the other.

### 3.2 The enum form is also the one DMN actually wants

An enum-typed result maps to a DMN `<outputValues>` list — the output **domain**, which is what
makes `P` (Priority) and `O` (Output Order) expressible at all, and which the exporter currently
throws away. One output column with a declared domain stays inside the analysable fragment. A
record result, by contrast, needs the whole multi-output lowering (a much larger change) to be
worth anything.

So the DMN payoff is **inverted** relative to the predecessor's framing: the sum form is cheap and
useful; the product form is expensive and its benefit is elsewhere.

## 4. What it buys

1. One keyword and one newline per inline type (§1, fact 1). State it plainly; it is the whole
   benefit column.
2. **Locality of reading** — the result type's definition sits where the reader meets it, rather
   than requiring a jump to a `DECLARE` elsewhere in the section.
3. Author-chosen names, so none of the predecessor's synthetic-name defects apply: no gensym, no
   collision policy, no unstable `x-l4-type` in a deployed schema, no unreadable hash.

## 5. The new problem: type constructors

**This is the question that decides the proposal, and it is Meng's.** The corpus's actual shape is
not `GIVETH A Part6Penalty` but:

```l4
GIVETH A MAYBE Part6Penalty
```

So where does an inline body attach under a type constructor? Three options, none obviously right:

- **(i) Attach to the innermost type name.**
  `GIVETH A MAYBE Penalty IS ONE OF \`fine\`, \`imprisonment\``declares`Penalty`and returns`MAYBE Penalty`. Compact, but the reader must know that `IS ONE OF`binds tighter than`MAYBE`,
and `GIVETH A LIST OF Assessment HAS …` reads worse still. Grammar impact unassessed.
- **(ii) Forbid inline under any constructor.** Only bare `GIVETH A <Name> …` may inline.
  **This is close to fatal**: the corpus's four real multi-result decisions are all `MAYBE`-wrapped,
  so the sugar would cover exactly the cases the corpus does not have.
- **(iii) Separate the declaration from the result type**, e.g. a `WHERE`-attached declaration.
  But that is just `LocalDeclare` — which does not exist (fact 6) and which is a different, more
  general feature. If (iii) is the right answer, **this proposal is the wrong vehicle** and §9-C is
  the real one.

## 6. The second problem: the type must be module-visible anyway

A caller consuming the result must name its parts — projecting `(assess c)'s rate`, or matching
`CONSIDER (v n) WHEN \`granted\` THEN …`. Both require the type's **fields or constructors to be in
scope at the call site**, which means the desugared `DECLARE` must land at module (or section)
scope, exactly where a hand-written one would.

So the inline form does not scope the type more tightly than `DECLARE` does. It only moves where
it is _written_. Combined with §1's measured benefit, the honest summary is: **this is a code-layout
preference, not a semantic feature.** A reviewer should decide whether L4 wants to spend a grammar
extension on a layout preference.

## 7. Costs

1. **Grammar.** `GIVETH` currently takes a `Type'`. Accepting an optional `TypeDecl` body makes it
   a choice point, and §5's constructor question makes that choice non-local. Unassessed.
2. **Exactprint.** The desugaring must re-inflate to the source form byte-identically. Better than
   the predecessor's (the name is the author's, so nothing is synthesised) but not free.
3. **`@desc` parity.** The flagship exported decision annotates every field
   (`housing-act-wizard.l4:55-60`) and those annotations become the public JSON schema. A one-line
   inline form has no natural slot; without one, the sugar is unusable for exactly the decision
   that most wants a compound result.
4. **Two ways to say one thing**, permanently, for every future reader.
5. **The `§`-local `DECLARE` it competes with is already shipped and already idiomatic.**

## 8. The case for rejecting

- The benefit is **one keyword and one newline** (§1). Everything else in §4 is locality of
  reading, which `§`-local `DECLARE` already provides at statute granularity.
- The corpus's real shape is `MAYBE`-wrapped, so under §5(ii) the feature misses its own use case,
  and under §5(iii) it is the wrong vehicle for the right feature.
- The type is module-visible either way (§6), so nothing is encapsulated.
- `@desc` parity is unsolved (§7.3), and the one decision in any corpus that most wants this is the
  one that needs `@desc`.
- The predecessor was rejected 5/5. This proposal fixes the _naming_ objections but inherits the
  _benefit_ objections, which were the fatal ones.

## 9. Alternatives

| #   | Alternative                                            | Comment                                                                                                                  |
| --- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| A   | **Status quo** — one-line `DECLARE`, `§`-scoped        | Zero risk; already idiomatic; fact 1 shows it is one line.                                                               |
| B   | This proposal, both forms                              | Under review.                                                                                                            |
| B′  | **Enum form only** (`IS ONE OF`), record form rejected | The asymmetry in §3 is real: enums keep citation names and feed DMN `outputValues`. Possibly the only defensible subset. |
| C   | **`LocalDeclare` in `WHERE`/`LET`**                    | The thing that genuinely does not exist (fact 6). More general, and §5(iii) suggests it may be what is actually wanted.  |
| D   | Anonymous lists                                        | **Rejected 5/5.** Recorded so review need not re-derive it.                                                              |

## 10. Questions for review

1. **§5 is the decider.** Which of (i)/(ii)/(iii)? If (ii), does the proposal survive missing the
   corpus's only real use case? If (iii), should this document be withdrawn in favour of §9-C?
2. Should the **record and enum forms be judged separately** (§3)? Is B′ the right answer?
3. Is §6 right that the type must be module-visible? Trace an actual call site — projection and
   `CONSIDER` both — and check what scope the fields/constructors resolve in.
4. Is the §3.2 DMN claim correct — does an enum-typed result actually give the exporter its
   `<outputValues>` domain, and is that domain otherwise unavailable?
5. **`@desc`**: is there a syntax that carries per-field annotations inline without becoming
   unreadable? If not, is that disqualifying?
6. Grammar: is `GIVETH A MAYBE Penalty IS ONE OF …` parseable without ambiguity, and what is the
   error when a user writes it wrong?
7. Given fact 1, is the benefit large enough to justify **any** grammar change? Answer with a
   number of characters saved per occurrence, times occurrences in the corpora.
8. Does inline declaration interact with L4's **type-overloaded same-name definitions**
   (`Parser.hs:816-819`), which killed one naming scheme in the predecessor's review?
9. Prior art specifically on **inline/anonymous sum types** — OCaml polymorphic variants, TypeScript
   union literals, Rust's lack of them. Do any of them support declaring a nominal sum at use site?
10. Exactprint: does the desugar/re-inflate round-trip survive `l4 format`?

## 11. Non-goals

- Not required for the DMN exporter's multi-output work, which needs only nominal records.
- No change to `GIVEN`.
- No anonymous types anywhere — the author always names the type.
