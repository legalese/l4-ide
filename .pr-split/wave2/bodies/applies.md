# docs(specs): SUBJECT-TO §9 — the APPLIES read side, answered and verified against the corpus

**2 files, +325/−9.** The specification record of the APPLIES read-side ruling: §9 of
`specs/todo/SUBJECT-TO-NOTWITHSTANDING-SPEC.md` answered (upstream #263), then hardened
with verbatim quotes from the corpus verification pass (#275), plus a status re-audit of
`specs/todo/HOMOICONICITY-SPEC.md` done in the same investigation.

## What this records

- **§9 (APPLIES read side)** moves from open to `ANSWERED`, in the spec's own house style:
  the ruling, the measurement that drove it, and a what-review-changed note — per
  CLAUDE.md §4: *a decision is recorded in its owning document or it is not decided.*
- **#275's follow-up** replaces paraphrases of the cited provisions with verbatim quotes,
  so the spec cites what the law says, not a summary of it.
- **The HOMOICONICITY spec** gets a dated status audit header (what landed — the `Deonton`
  type, surface `DEONTIC` — and what remains open).

## One rider, disclosed

This file also carries upstream #262's small edit to the SUBJECT-TO spec — the **third
SUBJECT-TO datapoint** from the LegalRuleML investigation. #262 is otherwise a
backends-docs PR; the datapoint lands here because a file lives in exactly one wave-2
slice, and this PR owns the spec. The backends-docs sibling discloses the same thing from
its side.

## Evidence

Documentation only; no build surface. Prettier-clean at the pinned 3.4.2.

## Independence

None in either direction (the rider above is a shared *file*, not a dependency).

## Provenance

Upstream `unstable` PRs folded in: #263, #275, plus one edit from #262 as disclosed.
