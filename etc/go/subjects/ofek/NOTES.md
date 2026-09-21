# `ofek` — subject notes

Read this before running. Nothing in the skill repeats what is here, and `subject.json`'s
`_comment` carries the measurements; this file carries the judgement calls.

The encoding's own write-up is in canon, on `mengwong/drafts`, and is far longer than this:

    subjects/il/ofek-hadash-2008/encodings/legalese/NOTES.md

**Corrections to a shared claim land there first.** This file deliberately restates no figure
from it except the two that are pinned in `subject.json`, so there is no second copy of a number
to go stale.

## The subject is not a statute, and the difference bites

Ofek Hadash (אופק חדש) is a **collective agreement** of 25 December 2008 between the State of
Israel and the Teachers' Union, layered with later collective agreements, decisions of a joint
bipartite follow-up committee (_vaadat maakav_) that the agreements make binding, and circulars of
the Ministry of Education and the Wage Commissioner. The one Act in the picture — the 2025 budget
law — sets no rate: it gives effect to an **approved collective agreement**, so even the statutory
layer routes back through the agreements.

Two consequences for anyone reading a run of it:

- **There is no consolidated text and no in-force banner.** A statute row's P1 fetch records "up
  to date with all changes known to be in force on or before ⟨date⟩"; there is no such line here,
  and what plays its part is the follow-up committee decision of 14 January 2025, whose corrected
  agorot appendices are authoritative for every number in the tables.
- **The amendment chain is by agreement, not by amending Act**, so the annotation-inventory
  machinery P1 and P2 join over has no marker set to dispose of. That is one reason this subject
  does not declare the deposit registers — see below.

## The source is a third party's corpus, and it has no licence

`source_url` is `morimovilimcatala.github.io/ofek-hadash-corpus/` — 282 documents in Akoma Ntoso,
published by someone other than the ministry. **Nothing was fetched from the Ministry of Education
or from Reshumot.** The repository behind that site has exactly one commit, by a bot, and **no
LICENSE or COPYING file of any kind** (measured 2026-09-08).

The encoding's `SOURCE-LICENSE.md` therefore carries **two** open questions rather than the usual
one, and they are open — not rhetorical. **Do not publish anything a run of this subject produces
without reading it.** That is also why `p10-publish` should not be reached here on a waiver: HG2
cannot be waived, and this is exactly the kind of subject HG2 exists for.

## What a run of this subject is NOT evidence about

`natlang_sources` and `comparison` are omitted, so `p1-ingest`, `p2-sweep`, `p4-forks` and
`p8-diff` are unreachable. The deposits exist — the encoding carries `source-bundle.json`, a
282-row `document-register.json`, and a `fork-register.json` with 13 forks — but they live in
canon and the mirror's allowlist does not carry `registers/`.

So: **a `COMPLETE` verdict here says nothing about the sweep or the fork register.** It is
completeness of accounting over the stages this subject declares, which are the measurement and
projection half. If the deposit half is wanted, widen the mirror allowlist first; declaring paths
this repository cannot hold would turn an honest silence into a permanent `SKIPPED` naming a file
nobody can deposit.

## HG1 has never been granted OR waived for this encoding

`encoding.json` records `not_reviewed.state: "not sought"`, which is weaker than a waiver: nobody
who knows Israeli teachers' pay has read the encoding against the agreements. Canon's NOTES.md §8
names the four things such a reader would have to settle, of which three change answers:

- **F1** — what a merged cell in a printed salary table means.
- **F3** — the section 38(g)/38(i) promotion deadlock.
- **F9** — which _Tosefet Ofek_ enters the section 39(b) base.

A waiver on this subject should say which of those it is waiving past. "This replays an
already-reviewed encoding" is the regcf waiver and **would be false here** — there is no prior
review to replay.

## Two toolchain facts worth knowing before you read a leg

- **The modules are blessed in the canon pin, as of 2026-09-19 — and the mirror is generated.**
  Canon `e29c69a3` supplied the 36 goldens whose absence had kept `il/ofek-hadash-2008` out of
  `etc/canon-pin.json`. Edit the encoding **in canon**; it reaches this repository through
  `sync-canon.mjs --bump`, and the `Canon Mirror` CI job fails when the two disagree. The one
  thing that did **not** follow from blessing is `p7-tnr` — see `subject.json`'s `_comment` for
  why the leg would be vacuous here even now that its goldens exist.

- **Those goldens were timed, not merely generated.** They come from `unstable` at `ec20584c1`,
  after four PRs that move golden bytes landed on 2026-09-18 — #419, #415, #418, #423. #419 is
  the one that bites: it fixed schema goldens double-encoding every non-ASCII character, and 524
  of this encoding's lines carry non-ASCII. Goldens blessed a day earlier would have been wrong
  in all nine schema files. If you re-bless, check what has landed since.
- **The Catala projection is real but runs outside this pipeline.** Six worked cases execute
  through `catala interpret` against `catala/ofek_hadash.catala_en` with no L4 in the loop, and
  every one reproduces the figure `ofek-cases.l4` asserts. Reproduce with the encoding's
  `source/run-catala.sh`. There is no `p7-catala` leg, so no receipt here attests it.
