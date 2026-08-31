# Provenance of `chubb-policy-restored.txt`

**This file is a reconstruction, not a source document.** It is the counterfactual fixture for the
repaired-benchmark arm: the policy as Kant et al.'s experiment would have received it had they not
deleted the operative benefits machinery from Goodenough & Carlson's original. Assembled 2026-09-01.

## Recipe

| part | provenance |
| --- | --- |
| header, §1 POLICY IN EFFECT AND CONDITIONS | `chubb-policy.txt` (the as-published arXiv variant), byte-identical |
| §2 BENEFITS (2.1–2.3) | Goodenough & Carlson 2024, PMC10894687, Appendix A, transcribed verbatim 2026-09-01 |
| §3 GENERAL EXCLUSIONS | `chubb-policy.txt` §2.1, renumbered 2.1→3.1; text and items otherwise byte-identical |
| §4 GENERAL CONDITIONS | `chubb-policy.txt` §3.x, renumbered 3.x→4.x; text otherwise byte-identical |
| §5 BENEFIT AND PREMIUM AMOUNTS (5.1–5.2) | PMC10894687 Appendix A, transcribed verbatim |
| §6 SIGNATURE | PMC10894687 Appendix A, transcribed; rendered as the heading, the one sentence, and a plain signature line |

The renumbering restores Goodenough & Carlson's original section layout, which is what makes the two
previously dangling cross-references resolve: §1.2's "the policy term described in Section 5 below"
and §4.5.1's "The premium described in Section 5 below" now point at a section that exists.

## Editorial decisions, all deliberate

1. **The age threshold stays 80** (the arXiv variant's value), not the original's 75. G&C describe
   the top permissible age as a designed "moving part"; more decisively, Q7's claimant is 75 years
   old, so reverting the threshold would flip Q7's gold and change a query's meaning. Keeping 80
   preserves every query's fact pattern relative to every threshold, so the §2/§5/§6 deletion is the
   **single** treatment difference between the two fixtures.
2. **Exclusion items keep the variant's numeric list (1–5)**, not the original's letters (a)–(e).
   Cosmetic; no query cites an item number; minimises the diff against the as-published fixture.
3. **The form feed is dropped.** `chubb-policy.txt` carries one `\f` (a PDF-pagination artifact)
   mid-§3.2.1. It is not policy content and its position is meaningless in a re-paginated document.
   This is the only byte of carried-over text that was not preserved.
4. **§2.1 reads "shown in §5 below"** — the section symbol where the rest of the document spells
   "Section". That inconsistency is in the original as printed; preserved.
5. **§2.1 says "Daily Hospital Income Benefit"; §5.1 says "Daily Hospital Benefit amount".** Also
   the original's own inconsistency; preserved.

## What this fixture is NOT

It is not the true G&C original (age 75, lettered exclusions, original pagination). Anyone wanting
the original should take it from PMC10894687 directly. This file answers a narrower question: *the
benchmark's own text, minus exactly the deletion.*

## Verification

`fixtures/` carries no checker, but the assembly was verified in-session on 2026-09-01:
- lines 1–21 (header + §1) byte-identical to `chubb-policy.txt`;
- §3 + §4 byte-identical to the as-published §2.1 + §3.x after stripping the form feed and
  normalising the clause numbers on both sides;
- §2, §5, §6 read back against the PMC transcription.

Licence: the restored sections originate in a CC BY 4.0 article; attribution is recorded in the
canon repository's NOTICE and in this study's SOURCE-LICENSE discussion. The as-published portions
follow `chubb-policy.txt`'s existing provenance note in `source-defects.md`.
