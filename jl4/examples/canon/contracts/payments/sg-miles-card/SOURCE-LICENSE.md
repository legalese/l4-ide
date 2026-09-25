# SOURCE-LICENSE — eight Singapore card issuers' reward-programme T&Cs

**Status: UNDETERMINED**, and — unlike the sibling `contracts/investment/yc-safe-premoney`
row this file's shape follows — the reason is not a dated absence of a licensing decision.
It is that this deposit's own retrieval never checked, and eight documents from five
different publishers each need their own answer.

## What is actually known

Measured 2026-09-21 over the ten `pdftotext -layout` extractions in `legalese/l4-ide` at
`jl4/examples/legal/miles-card/source/*.txt` (the authoritative copy; see `NOTES.md` §0 —
the PDFs and their extractions are not vendored into this repository): a case-insensitive
search for `copyright`, `©`, `all rights reserved` and `licen[cs]e` across all ten files
returns **one hit, and it is a false positive** — HSBC's MCC table row 28,
`7801 Government Licensed On-Line Casinos`. **No document carries a copyright notice, a
licence reference, or an attribution requirement anywhere in its extracted text.**

That is weaker evidence than it looks, for a reason `yc-safe-premoney`'s equivalent finding
is not subject to: these documents were captured as **PDFs with a "-layout" text
extraction**, not as `.docx` with inspectable header/footer XML parts. A notice could sit in
an image, a watermark, a PDF-level metadata field, or a footer `pdftotext -layout` renders
as a stray line this search's four terms did not match. **The absence found here is an
absence in the extraction, not independently confirmed as an absence in the document.**

## Why UNDETERMINED, not a grant

Absence of a notice is not absence of a right. Unlike the pre-1989 US regime `yc-safe-premoney`
implicitly benefits from (where a missing notice could forfeit copyright), Singapore and each
issuer's likely home jurisdiction are all Berne Convention members: copyright subsists on
creation, with no notice or registration required. Five different institutions — DBS Bank
Ltd, Citibank Singapore Ltd, HSBC Bank (Singapore) Ltd, United Overseas Bank Ltd, and
POSB/DBS again — each publish standard consumer terms as a routine part of running a card
programme, on their own domains, and every reasonable prior is that they hold copyright in
that text whether or not a given PDF happens to print a notice. **Do not read this file's
finding as permission to redistribute the source text.**

## Consequence for this deposit

The PDFs and their `pdftotext` extractions are **not vendored into this repository**. Each
document's `registers/source-bundle.json` entry carries its retrieval URL, retrieval date,
and a sha256 integrity digest, following `docs/directory-conventions.md` §6's pattern for
source text whose redistribution terms do not permit committing it. The encoding's own
`.l4` files — L4 source describing what the terms say, with clause citations and short
verbatim quotations for identification — are Legalese's own work product and carry the
`encoding.json` license (Apache-2.0) as normal; nothing above changes that.

If an issuer's terms of use are ever actually read (rather than searched for in the
extraction), record the finding here per-document, on the `yc-safe-postmoney` /
`yc-safe-premoney` model of a `DETERMINED` file with the actual notice quoted.
