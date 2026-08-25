# Syntactic Affordances for Isomorphic Legal Formalisation

> **A facet of the paper series** (HCI + linguistics of L4's controlled-natural-language
> surface). **Co-author: Adam Wyner** (linguist; CNL + AI&Law). Drafted 2026-06-25.
> This facet _extracts and deepens_ the surface-syntax material already outlined in the
> ICAIL paper §5 (figures `fig:asyndeton`, `fig:mixfix`, the "two registers" paragraph,
> the COBOL/SQL low-code lineage, the Coode/Allen citations) into a standalone paper.
> Lives in the bounded-deontics worktree for continuity; may move to its own branch.

## Thesis

L4's surface provides a small set of **novel syntactic affordances** that let a formal,
executable artefact track the _source legal text_ near word-for-word (**isomorphic
formalisation**) while remaining type-checked and runnable. The HCI/linguistic claim:
these affordances shrink the notational gap between legal prose and formal code far
enough that **non-programmers (lawyers, business stakeholders) can read and sign off** on
L4 rulesets — the responsibility-transfer that the ICAIL paper identifies as the bridge
across the knowledge-acquisition bottleneck.

## The affordances (catalogue — what each one _affords_)

- **Ditto `^`** — vertical elision of a repeated term; mirrors tabular/columnar legal
  drafting where a phrase is "carried down."
- **Asyndeton + inert quoted strings** — `...` (3 dots) = infix AND (prec 3); `..`
  (2 dots) = infix OR (prec 2); an _inert_ quoted string in boolean position evaluates
  to the **identity of the surrounding operator** (TRUE under AND, FALSE under OR). This
  is the star feature: it lets verbatim source prose be quoted _inside_ the boolean
  structure without changing the truth value, enabling **word-for-word isomorphism**
  with the statute/contract. (Validated live in the ICAIL work.)
- **Mixfix phrase-identifiers** (backtick) — `` `the worker` `` `` `works for` ``
  `` `the firm` ``: predicates read as natural phrases, not `worksFor(w,f)`.
- **Indentation, not parentheses** — the boolean tree _is_ the layout; secondary
  notation (whitespace) promoted to primary structure.
- **Two registers** — UPPERCASE = language keywords vs `` `lowercase backtick` `` = law
  vocabulary; the keyword/identifier convention of COBOL and SQL, which is the low-code
  lineage L4 claims.
- **`GIVEN`/`GIVES`/`GIVETH` type signatures; low punctuation, words-not-sigils** —
  avoids English's lexical-ambiguity and punctuation own-goals.

## Two analytic lenses

1. **HCI — Cognitive Dimensions of Notations** (Green & Petre). The right vocabulary to
   evaluate a notation: _closeness of mapping_ (to legal prose — L4 maxes this via
   mixfix + asyndeton/inert), _role-expressiveness_, _secondary notation_ (indentation
   made primary), _viscosity_, _hidden dependencies_, _hard mental operations_,
   _error-proneness_ (low-punctuation removes sigil errors). A Cognitive-Dimensions
   walkthrough gives a principled, non-hand-wavy HCI evaluation.
2. **Linguistics / CNL design space** (Wyner's home turf). Position L4 against the
   controlled-natural-language tradition — Attempto/ACE, Ranta's Grammatical Framework,
   RuleCNL→SBVR, Wyner's own rule+exception CNLs — and the _naturalness vs precision_
   tension. The organising principle is **isomorphism** (Bench-Capon & Coenen: the
   formal representation should mirror the source for legibility + maintainability);
   L4's affordances are engineering in service of that principle.

## What's actually novel (vs the broad CNL literature)

Most CNLs aim at _authoring_ (write controlled English, get logic). L4's affordances aim
at _isomorphic quoting_ — making the formal artefact line up with **pre-existing** legal
text token-by-token (the asyndeton/inert trick is purpose-built for this). That
"track-the-source" goal, plus the two-register + mixfix + indentation combination as a
coherent design, is the contribution; the individual ideas have ancestors (COBOL/SQL
registers; Coode/Allen on legal-sentence structure; Ranta on grammars).

## Evaluation options

- **(analytical, lighter)** Cognitive-Dimensions analysis + a gallery of isomorphism
  alignments (statute paragraph ↔ L4, shown side-by-side) demonstrating word-for-word
  tracking. Plus the validated examples from the ICAIL work.
- **(empirical, heavier — optional / future)** a small study: lawyers / law students
  _read and verify_ a ruleset in L4 vs the source prose vs another formalism, measuring
  comprehension / error-spotting / confidence; or a structured write-up of the existing
  **stakeholder sign-off** finding. Flag as optional — decide scope with Wyner.

## Venue

- **Best fit: the CNL workshop** (Controlled Natural Language) — Wyner's community, the
  GF/ACE/SBVR crowd.
- Alternatives: a PL-HCI venue (**PLATEAU**, **PX/Programming Experience**) for the
  Cognitive-Dimensions angle; or a legal-design / legal-informatics venue.

## Risks / open questions

- **Naturalness vs ambiguity** — CNL's perennial tension; L4 resolves it by being a
  formal language _that reads_ naturally rather than parsing free English — make that
  explicit so reviewers don't expect NL parsing.
- The affordances are _designed_, not yet _user-tested_; analytical evaluation is honest,
  empirical is a bigger commitment.
- Scope: catalogue + Cognitive-Dimensions analysis (tight, shippable) vs + empirical
  study (stronger, slower). Decide with Wyner.

## Place in the series

- **Bounded Deontics → JURIX** — the formal-theory facet.
- **Determinacy frontier / detect≠resolve → Cambridge CLS** — the empirical facet.
- **This (CNL syntactic affordances, w/ Wyner) → CNL workshop** — the HCI/linguistics
  facet; extracts & deepens ICAIL §5.
- All three draw on the one L4 system; the ICAIL paper remains the broad introduction
  that each facet zooms into.
