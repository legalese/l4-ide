# `etc/safe` — the YC Post-Money SAFE generator

Deal parameters in, one executable SAFE per investor out.

The Y Combinator SAFE is a standard form under CC BY-ND 4.0, and each form carries a
representation that the parties "have not modified the form, except to fill in blanks and
bracketed terms". That sentence is this tool's specification: the blanks are the parameter
set, everything else is invariant and must be reproduced verbatim, and the five cells YC
does not publish must be refused rather than synthesised.

The spec is `specs/todo/yc-safe/SPEC.md`; section numbers below refer to it. The forms,
their verbatim Markdown, the hole map and the L4 encoding live in a canon subject
directory, which is always a path argument — this tool never assumes a checkout location.

---

## Commands

```
node etc/safe/gen.mjs fill   --subject DIR --deal deal.json --out DIR [--pdf] [--docx] [--no-embed]
node etc/safe/gen.mjs round  --subject DIR --deal deal.json --out DIR
node etc/safe/gen.mjs liquidity --subject DIR --deal deal.json --out DIR --proceeds N \
                                [--indebtedness N] [--promised-options N]
node etc/safe/gen.mjs verify FILE.pdf [--subject DIR]
node etc/safe/make-templates.mjs  --subject DIR [--check]
node etc/safe/check-templates.mjs --subject DIR
node etc/safe/check-encoding.mjs  --subject DIR
```

| command               | what it does                                                                                                                                                                                                                   |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `gen.mjs fill`        | Validates the deal through the encoding, then writes one filled Markdown SAFE and one instance `.l4` per investor, a pro rata side letter for each Safe that asked for one, optional PDF and `.docx`, and `manifest.json`.     |
| `gen.mjs round`       | Runs the portfolio conversion and writes `conversion-schedule.md` (a readable document) and `conversion.json` (the decoded result, unrounded).                                                                                 |
| `gen.mjs verify`      | The second-party check. Reads the PDF's XMP packet and its file attachment, re-hashes the attachment against the payload, compares the encoding modules, and re-runs `l4 check` on the extracted instance. Needs no deal file. |
| `make-templates.mjs`  | Derives `templates/<jurisdiction>/<variant>.md.mustache` and `templates/side-letter/<jurisdiction>.md.mustache` from `source/md/` and `templates/holes.json`. `--check` reports a stale template instead of rewriting it.      |
| `check-templates.mjs` | The §5.3 round-trip proof: every template, rendered with each hole's original placeholder text, reproduces its source form byte for byte — and the template set is exactly the six published SAFEs plus the four side letters. |
| `check-encoding.mjs`  | Compares `encoding.json`'s `batch.record_fields` with the `DECLARE … HAS` blocks in the row's modules, and requires the map to name exactly the records the entrypoints can return.                                            |

Exit codes: `0` success, `1` failure, `2` a deal that cannot be filled onto the form it
names (`fill`) or a usage error.

## Subject layout (SPEC.md §4)

```
<subject>/source/md/<form>.md              verbatim `pandoc --to gfm --wrap=none`
<subject>/source/docx/<form>.docx          the YC originals
<subject>/source/footers.json              the running header/footer pandoc drops
<subject>/templates/holes.json             the positional bracket -> hole map
<subject>/templates/<juris>/<variant>.md.mustache
<subject>/templates/side-letter/<juris>.md.mustache
<subject>/encodings/<row>/encoding.json    entrypoints + batch.record_fields
<subject>/encodings/<row>/*.l4
```

`templates/holes.json` is read in either of two shapes: canon's measured one
(`brackets` + `blanks` arrays with `placeholder_case`) or a flat `holes` array. Both
normalise to the same positional map, in which the nth entry whose `literal` is L stands
for the nth occurrence of L in the document.

## Calling L4

`l4` is discovered the way `etc/go` discovers it and is **never built** (CLAUDE.md §2.1):
explicit `$L4` wins, then this worktree's own `dist-newstyle`, then the newest among
sibling worktrees. The call shapes, measured 2026-09-04:

```
JL4_LIBRARY_PATH=<row> l4 batch <row>/safe-form.l4      -e "validate deal" -i rows.json
JL4_LIBRARY_PATH=<row> l4 batch <row>/safe-portfolio.l4 -e convert         -i rows.json
JL4_LIBRARY_PATH=<row> l4 batch <row>/safe-portfolio.l4 -e liquidity       -i rows.json
JL4_LIBRARY_PATH=<row> l4 check  <out>/<safe-id>.l4
```

`rows.json` is `[{"deal": <the deal.json object>}]`, with one key per parameter — the
two-parameter `liquidity` takes
`[{"deal": {…}, "event": {"proceeds": 10000000, "indebtedness": 0, "promisedOptionsReceivingProceeds": 0}}]`,
named as `encoding.json`'s `entrypoints.<name>.params` says. `JL4_LIBRARY_PATH` must name the
encoding row or the modules' `IMPORT`s do not resolve. Output is NDJSON, one envelope per
row:

```json
{
  "diagnostics": [],
  "input": {},
  "output": [{ "result": null, "trace": null }],
  "status": "success"
}
```

Records come back **positionally** — `{"Conversion": [v1, v2, …]}`, in `DECLARE` order,
with no field names on the wire — so `encoding.json`'s `batch.record_fields` is the
decoding key and `check-encoding.mjs` is what keeps it honest. Lists are JSON arrays;
strings and numbers are native; `MAYBE` fields may be `null` or absent on the way in. On
failure `status` is `"error"` and `output[0].result.error` carries the message, which
`lib/l4.mjs` re-raises verbatim.

`l4` has no `--version` (it exits 1 with ``Invalid option `--version'``), so the payload's
`generator.l4` reads `unknown`. That is a measured absence, not a failed probe.

## The edition comes from the form, not from the deal

The deposit measured the header stamp of every form. The US MFN SAFE is **Version 1.3**;
the US cap and discount SAFEs are 1.2; Singapore, Canada and Cayman are "⟨place⟩ Version
1.2"; the US side letter is 1.0 and the other three side letters carry no stamp at all.
So a deal that declares one edition for every US form is wrong about one of them.

`fill` therefore reads the edition off the stamp in `source/footers.json`, records that in
the XMP payload and in `manifest.json`, and **refuses (exit 2) a deal whose
`form.edition` names a different edition** than the form it selects. The check is against
the SAFE, because that is the form the deal names; each document's payload still records
its own form's edition, so an MFN SAFE reads 1.3 and its side letter reads 1.0. The
manifest keeps the stamp string beside the number, because the stamp is the evidence.

## The XMP payload (SPEC.md §5.4)

Two carriers, both written before any signature is applied — this tool does not sign.

1. **`XMP-pdfx:L4`**, the one tag `smucclaw/l4meta` defines. Its config is copied verbatim
   to `lib/l4meta-xmp.config`, so a 2021 `l4meta out.pdf` reads a 2026 SAFE.
2. **A PDF file attachment** of the instance `.l4` (`qpdf --add-attachment`), so a reader
   with any PDF viewer can save the contract's own program.

```json
{
  "l4meta": "1.0",
  "instrument": "yc-safe-postmoney",
  "form": { "edition": "1.2", "jurisdiction": "us", "variant": "cap" },
  "source_form_sha256": "<the YC .docx this document reproduces>",
  "template_sha256": "<the .mustache used>",
  "parameters": { "companyName": "ABC, Inc.", "purchaseAmount": "200,000" },
  "encoding": {
    "row": "legalese-2026-09",
    "modules": { "safe-form.l4": "sha256:…" }
  },
  "instance": {
    "path": "investor-a-llc.l4",
    "sha256": "…",
    "text": "<the module, inline>"
  },
  "generator": {
    "tool": "etc/safe/gen.mjs",
    "l4": "unknown",
    "commit": "<l4-ide sha>",
    "at": "<ISO>"
  }
}
```

`parameters` records the values **as filled**, including the markup the form's own
typography asked for (`**ABC, INC.**` in the signature block, `<u>…</u>` inside a
fill-in rule), because that is what went into the document.

Read it back with either tool:

```
exiftool -config etc/safe/lib/l4meta-xmp.config -XMP-pdfx:L4 -b out.pdf
qpdf --list-attachments out.pdf
node etc/safe/gen.mjs verify out.pdf --subject DIR
```

Without `--subject`, `verify` still checks the XMP packet and the attachment hash and
says that `l4 check` was skipped, because the instance `IMPORT`s the encoding row.

## What the licence requires, and what this tool does about it

The forms are © Y Combinator Management, LLC under CC BY-ND 4.0, and each `.docx` footer
adds: "You may modify this form so you can use it in transactions, but please do not
publicly disseminate a modified version of the form without asking us first."

- **The licence line and the version stamp are reproduced on every filled document.**
  pandoc drops headers and footers, so they live only in `source/footers.json`; a form
  whose licence line is missing there is an error, and no document is written.
- **Templates are derived, not authored.** `make-templates.mjs` touches only what
  `holes.json` names, and `check-templates.mjs` proves the result reproduces the
  publisher's text byte for byte. That proof is the evidence for the representation the
  form itself makes.
- **Unpublished cells are refused.** The matrix is {US} × {cap, discount, MFN} together
  with {SG, CA, KY} × {cap}. Asking for a Singapore discount SAFE exits 2 rather than
  synthesising one, because synthesising it would be exactly the modified version the
  footer asks people not to disseminate.
- **Nothing is republished.** The generator's output is a transaction document, which is
  what the licence and the instrument invite.

Whether an L4 formalisation is an "adaptation" under CC BY-ND is an open question the spec
records (§2, ruling R9) and does not resolve.

## A worked run

```
node etc/safe/gen.mjs fill  --subject $SUBJECT --deal $ROW/cases/deal.example.json --out out --pdf --docx
node etc/safe/gen.mjs round --subject $SUBJECT --deal $ROW/cases/deal.example.json --out out
node etc/safe/gen.mjs verify out/investor-a-llc.pdf --subject $SUBJECT
```

`deal.example.json` is the User Guide's Appendix II Example 1: ABC, Inc., two Post-Money
Safes ($200k at a $4m cap, $800k at an $8m cap, the second with a pro rata side letter),
and a $5m Series A at a $15m pre-money with a 10% target pool. It produces:

| file                                   |   bytes | what it is                                                           |
| -------------------------------------- | ------: | -------------------------------------------------------------------- |
| `investor-a-llc.md`                    |  23,743 | the US valuation-cap SAFE, filled                                    |
| `investor-a-llc.l4`                    |   3,776 | the same transaction as a program; passes `l4 check`                 |
| `investor-a-llc.pdf`                   | 158,857 | the document, with the module in XMP and attached                    |
| `investor-a-llc.docx`                  |  34,396 | the same, styled from the YC original                                |
| `investor-b-ventures-lp.md`            |  23,750 | Investor B's SAFE                                                    |
| `investor-b-ventures-lp.l4`            |   3,784 |                                                                      |
| `investor-b-ventures-lp.pdf`           | 158,907 |                                                                      |
| `investor-b-ventures-lp.docx`          |  34,405 |                                                                      |
| `investor-b-ventures-lp-pro-rata.md`   |   4,001 | the Pro Rata Side Letter, for the Safe that asked for one            |
| `investor-b-ventures-lp-pro-rata.pdf`  | 112,389 |                                                                      |
| `investor-b-ventures-lp-pro-rata.docx` |  17,703 |                                                                      |
| `manifest.json`                        |   2,995 | every output with its sha256, the row's module hashes, tool versions |
| `conversion-schedule.md`               |   3,589 | the readable schedule (`round`)                                      |
| `conversion.json`                      |   2,423 | the decoded `Conversion`, unrounded (`round`)                        |

The numbers it produces are the User Guide's own: Company Capitalization 11,764,705;
Investor A 588,235 shares and Investor B 1,176,470, both at their caps; a Series A price
of $1.1144 with a 1,694,570-share pool increase (the guide rounds that to 1,695,000); and
448,642 pro rata shares for Investor B.

`liquidity --proceeds 10000000` reproduces the guide's Q3 (both Safes convert, $0.8901
per as-converted share, Conversion Amounts 561,764 and 1,123,529) and
`--proceeds 3000000` its Q4 (neither converts; each takes its Cash-Out Amount).

Every Safe in the round is bound into every instance module, not just the one the document
is for: Company Capitalization includes all Converting Securities, so no Safe's share
count is computable from that Safe alone.

## Tests

```
node --test 'etc/safe/test/*.test.mjs'
```

The mustache tests are self-contained. The template and end-to-end tests need a subject
directory: they take `$SAFE_SUBJECT`, else a `legalese/canon` checkout beside this repo or
beside its `l4wt` parent, and skip with that message when there is none. They copy the
subject's inputs into a temp directory before running `make-templates`, so a canon working
tree is never written to. The PDF legs skip, naming the tool, when pandoc, exiftool or
qpdf is missing.

## Files

| file                    | what it is                                                                               |
| ----------------------- | ---------------------------------------------------------------------------------------- |
| `gen.mjs`               | `fill`, `round`, `verify`                                                                |
| `make-templates.mjs`    | source Markdown + `holes.json` → templates                                               |
| `check-templates.mjs`   | the round-trip proof                                                                     |
| `check-encoding.mjs`    | `record_fields` vs the `DECLARE`s                                                        |
| `lib/mustache.mjs`      | the mustache subset the templates need; no HTML escaping, because the output is Markdown |
| `lib/l4.mjs`            | binary discovery, `l4 batch`, `l4 check`, positional record decoding                     |
| `lib/subject.mjs`       | the subject layout, the published matrix, the two `holes.json`/`footers.json` shapes     |
| `lib/fill.mjs`          | hole values, the mustache view, the instance module                                      |
| `lib/schedule.mjs`      | the conversion schedule                                                                  |
| `lib/tools.mjs`         | pandoc, exiftool, qpdf                                                                   |
| `lib/diff.mjs`          | the unified diff `check-templates.mjs` prints on failure                                 |
| `lib/l4meta-xmp.config` | copied verbatim from `smucclaw/l4meta` (Apache-2.0)                                      |
| `lib/underline.lua`     | keeps `<u>` blanks visible in the PDF; pandoc 2.9's LaTeX writer drops raw HTML          |

No external dependencies, and nothing here touches `package.json` or the lockfile.
