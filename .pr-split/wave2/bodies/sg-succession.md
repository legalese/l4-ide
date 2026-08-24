# corpus(sg-succession): Singapore succession law — Wills Act, Intestate Succession Act, Probate & Administration — the second subject, end to end

**57 files, +28,803 insertions, zero deletions.** This PR is the corpus half of upstream
#274: the second full legal subject through the L4 pipeline (Reg CF was the first), encoding
Singapore's succession-law cluster with cross-statute interaction.

## What this adds

Everything lives under `jl4/examples/legal/sg-succession/`:

- **Six L4 modules**: `sg-wills.l4`, `sg-isa.l4` (Intestate Succession Act), `sg-paa.l4`
  (Probate & Administration Act), plus `sg-succession-domain.l4` (shared ontology),
  `sg-succession-cases.l4` (worked cases) and `sg-succession-wizard.l4` (the citizen-wizard
  façade), with `sg-succession.l4` as the umbrella module.
- **28 golden files** under `tests/` — the full four-golden-per-module discipline
  (`.golden`, `.ep.golden`, `.nlg.golden`, `.schema.golden`), shipped in the same commit as
  the `.l4` files per this repo's own corpus rule (CLAUDE.md §3.1).
- **A citizen web app**: `app/` — `build-app.mjs`, `build-scenarios.mjs`, template,
  `outcomes.json`.
- **De novo provenance**: `denovo/` — `source-bundle.json`, `fork-register.json`,
  `external-modifications.json`, recording what was encoded from which source text.
- **Source texts**: the statutes as PDFs under `source/` (including AMLA 1966, since Muslim
  intestacy routes out of the ISA).

## What this PR deliberately does *not* carry

Upstream #274 was one PR with five stories. The other four ride in wave-2 siblings, cut by
reviewer competence:

- Its **pipeline repairs** (34 `etc/go/` files, the skill, CI wiring) → the `pipeline` PR.
- Its **stdlib fix** (NOT-precedence in `excel-date.l4`, with re-blessed goldens and the
  regcf DMN engine baseline) → the `repairs` PR.
- Its **jl4-service fix** (deployment-ID validation) → the `repairs` PR.

## Evidence

- Goldens are present for every module (the unfiltered `Corpus Goldens Present` CI check
  passes by construction — the files are taken verbatim from `unstable`).
- Every file here reached `unstable` through the sequential merge queue (required checks
  include the golden suite). The push-triggered run at `bf355e79` was still in progress
  when this PR was opened; this line will be updated when it completes.

## Independence

**One ordering note**: the corpus's date arithmetic runs through the stdlib's
`excel-date.l4`, whose NOT-precedence fix rides in the `repairs` sibling. The goldens here
were cut against the *fixed* stdlib. If this slice's CI runs the golden suite against the
base stdlib and any golden exercises the affected workday path, the run will say so —
that is a fact about slice ordering (`repairs` first), not about the corpus. The merge
vehicle (`unstable → main`) carries both together and is green.

## Provenance

Upstream `unstable` PR folded in: #274 (corpus files only; see above for where the rest of
#274 went). Upstream issues filed during this work: smucclaw/l4-ide#943, #944, #945.
