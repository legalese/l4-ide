# TODO — the natural second target: Cardinal Care (Aetna)

**Status: backlog, written 2026-09-01. Nothing below has been started.** "The natural second
target" is the phrase from the _Cited Works_ reading companion: Kant et al.'s harder benchmark —
the **Advanced Reproductive Technology (ART)** and **Comprehensive Infertility (CI)** coverage
rules of the Stanford Cardinal Care Aetna Student Health Insurance Plan (Aetna Life Insurance,
2023), via the Stanford CodeX **Insurance Analyst** (their refs: CodeX 2025a = the Insurance
Analyst; CodeX 2025b = its Cardinal Care encoding, in Epilog). Their measured spread there:
o1 ART 0.95 / CI 0.87 against GPT-4o 0.56 / 0.37 — guidance did not rescue weak models on the
hard text, which is exactly why it is the discriminating instrument the Chubb policy is not.

Ordered; each item names its deliverable.

1. **Provenance and licensing.** Recover the two CodeX URLs (the paper's reference entries are
   "Accessed Feb 2, 2025" with the hyperlinks stripped by text extraction — take them from the
   PDF's link annotations or the CodeX site), locate the exact Aetna Cardinal Care plan document
   for the 2023 plan year, and hash-pin all three. Expect the Aetna document NOT to be openly
   licensed: the deposit may have to be pointer-plus-hash, not a copy — settle this before
   anything downstream. Deliverable: a `source-bundle.json` in the go-pipeline style.
2. **Fixture audit before anything else** — the Chubb lesson, now standing policy. Diff
   whatever text Kant et al. actually used against the source plan; diff the Epilog encoding's
   coverage of the plan against the plan. Deliverable: a `source-defects.md` for this subject,
   even if its finding is "clean."
3. **Recover their query set and answer key.** The Chubb queries were published (Appendix
   A.1/A.2); check whether the ART/CI claims and golds are published anywhere, else reconstruct
   from the Insurance Analyst's own test material or write to the authors (Megan Ma is the
   collaboration-adjacent co-author). Deliverable: `fixtures/` + a dual key.
4. **Scope ruling.** Whole plan vs the two tested coverage areas. Size the ART and CI rule text
   honestly (pages, defined terms, cross-references into the master plan document) before
   promising anything. Deliverable: a one-page sizing note with the ruling recorded.
5. **Dual-key discipline.** Key A = their golds verbatim, for comparability; Key B = per-item
   mechanical/interpretive classification with clause citations — written and committed before
   any trial runs (FOUNDATION.md R2 applies unchanged).
6. **Cell design ruling.** Their guided condition here is **Epilog**, not Prolog. Decide:
   replicate 2×3 with an Epilog arm (toolchain: an Epilog runner would need sourcing), a Prolog
   stand-in (weakens the replication claim — say so if chosen), or go-pipeline arms only per
   `bench/PREREGISTRATION-go.md`. Record the ruling and its why.
7. **Blindness plan + T9 sweep.** Forbidden lists naming every key-adjacent file from item 3
   onward; keys quarantined outside any staged path; memory-index lines for this project
   confirmed finding-free before the first encoder launch; the check recorded in PROVENANCE.md.
8. **Pre-registration.** Predictions with refutation conditions, expected escalation sets per
   item (Key B drives them), pilot k=2 gate before the full n — committed before data exist,
   frozen after, in the pattern of the two existing preregistrations.

Interaction with the go arm: if item 6 lands on "go-pipeline arms only," Cardinal Care becomes
the second subject of `PREREGISTRATION-go.md`'s protocol rather than a third bespoke harness —
prefer that unless the Epilog replication is judged worth its toolchain cost.
