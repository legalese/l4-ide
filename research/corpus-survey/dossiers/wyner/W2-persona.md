# W2 — Wyner persona rehearsal (SYNTHETIC — preparation aid only)

> **⚠️ This is a synthetic, corpus-grounded model, NOT Adam Wyner.** It is inferred from his
> published work (see [W1](W1-interest-map.md)) to help *rehearse* the co-authored CNL paper before
> talking to the real him. **Nothing here is a quote, a position, or a commitment by Adam.** Do not
> attribute any of it to him, do not put it in his mouth in the paper, and do not treat it as his
> review. Its only job is to help us anticipate — the real Adam validates or overturns all of it,
> and he should be looped in early. Where this model guesses, it is flagged as a guess.

## What his corpus suggests he values (grounded priors)

From W1, a reviewer/collaborator shaped by this body of work would likely weight:

- **CNL rigor** — he co-authored the CNL taxonomy; "controlled natural language" is a *technical*
  claim (naturalness ↔ formality trade-off, defined constructs, round-trip), not a vibe.
- **Linguistic grounding over ad-hockery** — he explicitly frames his method as *linguistically
  oriented and rule-based, in contrast to machine learning*. Syntax choices should have a reason.
- **Argumentation & defeasibility as first-class** — his lifelong lens; he'll look for where
  argument structure / defeasible reasoning lives in a legal formalism.
- **Interoperability & standards** — LegalRuleML. He thinks about whether a representation *talks to*
  the rest of the ecosystem, not just whether it runs.
- **Empirical evaluation** — his NLP papers report inter-annotator agreement, precision/recall. He'll
  expect *evidence* for usability/readability claims, not assertion.
- **Situating in the field's history** — he curates AI&Law's memory; he'll want L4 placed accurately
  in the lineage (and will notice if a predecessor is mis-cited or missed).

## Rehearsal: likely probes on the L4 CNL paper (with prep, not answers)

*Premise of the paper (ours): L4 offers human-readable, round-trippable syntax for legal rules with
an executable, typed semantics — a "controlled natural language" for law.* Anticipated pushbacks a
Wyner-informed reader would raise, and how we'd want to be ready:

1. **"Is L4 actually a CNL, or a DSL with English-like keywords?"** — the sharpest probe, given his
   2010 taxonomy. *Prep:* state where L4 sits on the naturalness↔precision axis explicitly; show a
   real statute round-tripped both ways; don't overclaim "natural."
2. **"What's the linguistic basis for the surface syntax?"** *Prep:* justify constructs against
   actual legal-drafting language (deontic modals, conditionals, cross-references), not intuition.
3. **"Where is argumentation / defeasibility?"** *Prep:* connect L4's defeasible-deontic handling to
   ASPIC+/argumentation-schemes vocabulary he knows; be honest if L4 is inference-only, not
   argument-structured, and frame that as a scoping choice.
4. **"How does this interoperate — can it export to / align with LegalRuleML?"** *Prep:* have a
   concrete answer on the LegalRuleML relationship (mapping, subset, or deliberate divergence with
   reasons). This is likely his highest-value contribution area — invite him into it.
5. **"What's the evaluation? Who read it, and could they?"** *Prep:* even a small readability /
   comprehension / drafting-time study beats assertion; if we have none yet, name it as future work
   rather than let him find the gap.
6. **"How is this different from rule-extraction / isomorphic-formalization prior art (incl. his own
   2011)?"** *Prep:* crisp differentiation — typed executable core + verification + app-generation
   across the whole pipeline; credit the linguistically-oriented lineage he's part of.
7. **"Is the isomorphism claim defensible?"** — he'll know Bench-Capon & Gordon 2009 (isomorphic
   renderings aren't unique) and Witt et al. 2021 (coders diverge). *Prep:* claim traceability, not
   uniqueness; cite those honestly.

## Working-style notes (for the collaboration itself, guesses flagged)

- *Highly collaborative* (31 papers with Bench-Capon, 21 with Atkinson) — likely comfortable with
  co-drafting and iteration. **(guess)**
- *Standards/community-minded* — likely to want the paper to connect to LegalRuleML and the AI&Law
  venue conversation; JURIX / *Artificial Intelligence and Law* / a CNL venue are his home turf.
- *Interdisciplinary* — bridges linguistics, CS, law; framing that respects all three will land
  better than a pure-PL framing. **(guess)**
- *Historically careful* — get the citations and the lineage right; he wrote the field's retrospectives.

## How to use this

- Treat items 1–7 as a **pre-mortem checklist** for the draft: for each, either have the answer or
  mark it as an open question to raise *with Adam* — several (esp. #3, #4, #5) are exactly where his
  input is the point of co-authoring.
- Do **not** generate "Adam would say…" text for the paper. When we want his voice, we ask him.
- First real contact: share the CNL bibliography section (`bib/cnl.md`) + the paper premise + these
  open questions, and let his actual answers replace this model.
