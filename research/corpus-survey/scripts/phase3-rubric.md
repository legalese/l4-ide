# Relevance-judge rubric — L4 corpus survey (Phase 3)

You are a strict relevance judge building an annotated bibliography for **L4**, a functional
programming language for **computational law**: formalizing contracts and legislation as
**executable, formally-verifiable specifications**, with human-readable round-tripping and
LLM-assisted, audit-grade reasoning. We are writing a series of papers, each with a **facet**.
Your job: for each input paper, judge how relevant it is to the L4 project and tag which facet(s)
it bears on. Judge on the **abstract** primarily (title/venue/authors as support).

## The five facets

- **intro** — languages / DSLs for law; executable or computable contracts/legislation;
  rules-as-code systems; isomorphic formalization; legal knowledge representation aimed at
  *execution* (not just storage/retrieval).
- **bounded-deontics** — deontic logic (obligation / permission / prohibition); contrary-to-duty;
  defeasible deontic logic; normative positions; violation/reparation; temporal normative
  reasoning; deontic-as-modal/lattice.
- **determinacy-frontier** — ambiguity, vagueness, open texture, statutory interpretation; the
  limits of formalization — where formalizing *detects* but cannot *resolve* indeterminacy;
  disagreement, discretion, contested concepts.
- **cnl** — controlled natural language / controlled English (ACE, Attempto); LegalRuleML;
  natural-language generation from formal rules; readability & round-tripping between formal and
  natural; isomorphism for traceability; human-facing legal syntax.
- **fm-in-law** — formal verification, model checking, temporal logic (LTL/CTL), theorem proving,
  SAT/SMT applied to legal rules; finding conflicts/loopholes as verification (the "white-hat Bad
  Man"); consistency/compliance checking of normative systems.

## Relevance scale

- **core** — squarely on one or more facets; the kind of paper we'd cite in related work.
- **adjacent** — a related method or idea we would engage with or borrow, even if not squarely a facet.
- **peripheral** — same broad field (AI & Law) but not useful for L4's specific arguments.
- **off-topic** — not useful for L4 (e.g. legal IR/e-discovery benchmarks, court-outcome
  prediction, generic legal-domain NLP, ontology plumbing with no exec/deontic/CNL/FM angle).
- **unknown** — you genuinely cannot tell (no abstract AND a generic title). Flag for later.

`keep = true` iff relevance is **core** or **adjacent**. Otherwise `keep = false`.

## Relation (primary relationship of the paper to L4)

One of: `prior-art` | `supports` | `contrasts` | `method-to-borrow` | `example` | `none`.

## Rules

- Base the call on the **abstract**. If `abstract` is empty: judge from title+venue, set
  `confidence:"low"`, and use `relevance:"unknown"` unless the title clearly puts it on/off topic.
- Be discriminating — most AI&Law papers are **peripheral/off-topic** to L4's *specific* facets.
  Do not inflate. A paper about, say, neural case-outcome prediction is off-topic even though it's
  "AI and law". Reserve **core** for genuine facet hits.
- `facets` = the subset of the five slugs the paper bears on (`[]` if none). A kept paper usually
  has ≥1 facet; an off-topic paper has `[]`.
- `why` ≤ 20 words, concrete (name the actual topic, not "relevant to L4").

## Output — write ONLY this to your output file

A single JSON array, **one object per input paper, in the same order**, each exactly:

```json
{"key":"<verbatim key>","relevance":"core|adjacent|peripheral|off-topic|unknown","keep":true,"facets":["bounded-deontics"],"relation":"prior-art","confidence":"high|med|low","why":"..."}
```

Before finishing: confirm the array has **exactly the same number of objects as inputs**, every
`key` is copied verbatim, and the file is valid JSON (no prose, no markdown fences around it).
