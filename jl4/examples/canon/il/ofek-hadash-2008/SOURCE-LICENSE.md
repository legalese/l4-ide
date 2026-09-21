# SOURCE-LICENSE — Ofek Hadash (Israel)

**Status: OPEN — not determined, and open on two independent questions.** This file records
the questions, not answers. Do not read the absence of a restriction here as a grant.

## Two questions, not one

Every other subject in this repository has one source-terms question: what may be done with
the official text. This row has two, because the text was not fetched from an official
publisher. It was read from a **third-party corpus** that had itself gathered, transcribed
and re-encoded the instruments.

### Question 1 — the instruments themselves

The underlying documents are Israeli **collective agreements** between the State of Israel
and the Teachers' Union, decisions of a joint follow-up committee, circulars of the Ministry
of Education and of the Wage Commissioner at the Ministry of Finance, and one Act (the Budget
Objectives Act 5785-2025, published in *Reshumot*, the official gazette).

They are not uniform in character, and the answer may differ between them:

- The **Act** is primary legislation published in the official gazette. Israel's Copyright
  Act 5768-2007 s 6 excludes legislation, judgments and certain official texts from
  copyright. That points one way, but it has not been checked against this Act's publication
  terms and no finding is recorded here.
- The **collective agreements** are contracts between the State and a trade union, filed
  with the Registrar of collective agreements under the Collective Agreements Law
  5717-1957. Whether a filed collective agreement is an "official text" for s 6 purposes is
  precisely the sort of question that needs answering rather than assuming.
- The **circulars** are administrative instruments of a government ministry, and are a
  different case again.

**None of this has been checked.** It must be settled before this row moves off
`mengwong/drafts`.

### Question 2 — the corpus this encoding actually read

The encoding did not fetch anything from the Ministry of Education or from *Reshumot*. It
read <https://morimovilimcatala.github.io/ofek-hadash-corpus/>, a published corpus of 282
documents, at the commit recorded in `registers/source-bundle.json`. Its digests are over
**that corpus's HTML**, not over the ministry PDFs behind it.

That corpus is a work of authorship in its own right. It states that each document records
how its text was recovered — read from a word-processor file, transcribed by a reader from a
scan, extracted from a PDF, or taken from a hand-verified CSV — and a transcription is an
act of authorship whatever the status of the thing transcribed. **The corpus repository
carries no LICENSE file**, which means no permission has been granted and none should be
inferred. The site does carry a `robots.txt` and an `llms.txt`; neither is a licence.

**Provenance of that repository, measured 2026-09-08.** The repo behind the site,
`github.com/morimovilimcatala/ofek-hadash-corpus`, holds **one commit**: `f042ee5`, authored
by `ofek-hadash corpus bot <noreply@github.com>`, with the message *"corpus site, built from
b0556fefb418"*. So what this row read is a **published build artifact**, not the corpus's
working repository — the source repo that produced `b0556fefb418` is not this one, and is not
visible from here. Three consequences worth having written down.

- There is no `LICENSE` or `COPYING` file anywhere in the first three directory levels, and no
  licence, copyright or rights wording in `index.html` or `llms.txt` either. The absence is
  now checked rather than assumed.
- There is no human author to contact from the repository itself. The only identity it carries
  is a bot address, so "contact with the corpus's compiler" below has to start from the
  project's public presence, not from `git log`.
- A single-commit site repo is one that a rebuild most likely **replaces**. The commit
  `registers/source-bundle.json` records is today's `HEAD` (checked 2026-09-08, they match),
  but that SHA should not be relied on to resolve later. The per-document digests in
  `registers/document-register.json` are the durable link to what was actually read.

The corpus's own `llms.txt` also says something this file must repeat, because it bears on
citation and not only on copyright:

> The /akn/il/... identifiers are a repository convention. Israel has no official Akoma
> Ntoso namespace, and they are not citable outside this corpus.

Those identifiers appear throughout `registers/document-register.json`. They are recorded as
what they are — a convention of the corpus this row read — and not as citations.

## What this encoding actually reproduces

Less than the `sg/penal-code-1871` row, and the difference is worth stating precisely because
that row is the one where source terms bite hardest.

This encoding is **not** in inert style. It does not carry the statutory prose inline as
string literals. What it reproduces is:

1. **Numbers** — 648 salary-table cells (224 of them distinct), 36 Tosefet Ofek amounts, and
   the supplement percentages and shekel floors. A table of pay rates is close to the
   thin-authorship end of anything copyright protects, but this encoding reproduces two
   tables **in full**, which is a material fact for whatever assessment settles Question 1.
2. **Paraphrase in comments** — each rule carries an English summary of the article it
   encodes, in the encoding's own words. Short phrases are quoted where the exact wording is
   the point: § 31(b)'s "4.33 (weeks) × 36 (hours)", § 39(b)'s definition of the combined
   salary base, § 18's "as though they had been paid at their time and without the
   reduction". These run to a few words each.
3. **One Hebrew string** — `"חוק הת. כלכלית אופק"`, the name § 17 of the 2026 agreement
   requires on the payslip line. It is reproduced because it is the only part of that
   agreement a teacher actually sees.
4. **English titles and 2–4 sentence summaries of all 282 documents**, in
   `registers/document-register.json`. These are the encoding's own translations and
   descriptions, not reproductions — but they are derived from the corpus's text, which is
   Question 2's territory.

No `source/` bundle of any instrument is vendored under this subject. `source/` here holds
**parsers and a harness**, not text: `tables.py` reads the corpus at a path supplied through
`OFEK_CORPUS` and is useless without a separate checkout of it.

## Attribution

The entry in the repository [NOTICE](../../../../../NOTICE) records both questions and
records that no attribution has been established — not that none is required. If Question 2
resolves in favour of the corpus's compiler holding rights in the compilation, an attribution
to that corpus belongs in NOTICE and this row should not be redistributed until it is there.

## What would settle this

1. A finding on Israeli Copyright Act 5768-2007 s 6 as applied to (a) an Act published in
   *Reshumot*, (b) a collective agreement filed under the Collective Agreements Law
   5717-1957, and (c) a ministry circular.
2. Contact with the corpus's compiler to establish the terms on which its transcriptions and
   its Akoma Ntoso encoding may be used, or a re-fetch of the underlying ministry documents
   so that Question 2 falls away. Note that the published repository gives no way to reach a
   person — see the provenance measurement above — so this starts from the project's public
   presence. The re-fetch route has the advantage of not depending on an answer arriving.

Until (1) and (2) are answered, this row stays on `mengwong/drafts`.
