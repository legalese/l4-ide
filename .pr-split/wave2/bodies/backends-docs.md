# docs(backends): the backend-portfolio census, the Catala export spec, the logic-programming survey, and the LegalRuleML verdict

**4 files, +2,347 insertions, zero deletions.** The documentation record of the
backend-portfolio research arc: how many export backends L4 now has, what family each
belongs to, which invariants they share, and two investigations (Catala, LegalRuleML) that
reached opposite verdicts.

## What this adds

- **`specs/proposals/BACKEND-PORTFOLIO-SPEC.md`** (#262, extended by #271): the six-family
  census of L4's export backends, the shared invariants I1–I7, the seams S1–S5, and the
  one-file-one-editor convention that keeps backends from stepping on each other.
- **`specs/proposals/LOGIC-PROGRAMMING-BACKENDS-SPEC.md`** (#258): the survey of the
  logic-programming family specifically (PROLEG, s(CASP)/Blawx, and kin) — what they share
  and where each earns its place.
- **`specs/research/LEGALRULEML-RESEARCH.md`** (#262): the verdict that LegalRuleML is a
  **provenance artifact, not an interoperability bridge** — with the xmllint 30/30 gate
  that grounded it.
- **`specs/todo/CATALA-EXPORT-SPEC.md`** (#260): the Catala bridge specification, rulings
  R1–R11 answered.

> **A finding disclosed here rather than hidden**: the Catala *implementation* (upstream
> #266, 33 files — `L4.Catala.IR/Lower/Emit/Equivalence`, an `l4 catala` verb, examples and
> a validator) is **not in wave 2 and not on `unstable`**. #266 was stacked on #260's
> branch and merged into it on 2026-08-18 — but #260 had already merged into `unstable`
> before that, so the implementation is stranded on `mengwong/catala-bridge` with its PR
> closed. It needs a fresh PR into `unstable`; until then this spec describes a backend
> whose code exists only on a dead branch.

## One edit that rides elsewhere, disclosed

#262 also added the third SUBJECT-TO datapoint to
`specs/todo/SUBJECT-TO-NOTWITHSTANDING-SPEC.md`. That file is owned by the wave-2
`applies` PR, so the datapoint appears there; both bodies disclose it.

## Evidence

Documentation only; no build surface. Prettier-clean at the pinned 3.4.2.

## Independence

None in either direction.

## Provenance

Upstream `unstable` PRs folded in: #258, #260, #262 (less the SUBJECT-TO edit, disclosed
above), #271.
