# Phase 4 — Acquisition findings

**Run date:** 2026-07-21 · Target: full text for the 327 tight-core. **Outputs:** `acquire-plan.csv`
(per-paper channel), `acquire-direct.json` (OpenAlex pdf_url), `green-oa.json` (Unpaywall), PDFs in
gitignored `pdfs/`.

## The reality: OA *availability* is high, automated *download* is low

| Signal | Count (of 327 tight-core) |
|--------|--------------------------:|
| Has an OA landing url (OpenAlex `oa_url`) | 179 |
| Confirmed `is_oa` by Unpaywall | **165** |
| Has a direct `pdf_url` (OpenAlex or Unpaywall) | ~110–99 |
| **Actually downloaded as a real PDF (curl)** | **~10** |

So ~half the tight-core is *legitimately open* — but the "pdf_url" a metadata API returns is
usually a **repository/publisher landing page**, not the file: it needs a browser click, or is
behind bot-protection that a plain `curl` can't pass (verified: 91 of 99 Unpaywall pdf_urls did
not yield `%PDF`). This is the architecture's "acquisition is the constraint" thesis, confirmed.

## Consequence — the strategy is on-demand, not bulk

- **The annotated bibliography (Phase 5) was built from abstracts**, which we hold for all 327.
  Abstracts carry contribution/method/claim — enough for related-work synthesis.
- **`green-oa.json` is the retrieval index**: for any paper we need to deep-read, it records
  whether it's OA and the best url. On-demand retrieval = open that url in the browser (one click)
  or, for the 148 non-OA, pull via licensed institutional access — sparingly, per §5.
- **Sci-Hub was declined** (user asked): it redistributes paywalled papers without authorization —
  outside the "with rights" line. The legit substitutes are green-OA (above) + licensed access.

## Paywalled residue (need licensed access, per-paper)

Unpaywall `is_oa=false` for **162** tight-core — concentrated in ICAIL (ACM) and DEON (Springer).
Not bulk-fetched by design. Pull specific ones on demand when a deep-read requires the full text.

**Bottom line:** full-text coverage is deliberately shallow (10 PDFs) and that's fine — Phase 5
runs on abstracts; `green-oa.json` makes any single full-text a one-click fetch when needed.
