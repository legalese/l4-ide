<!--
  The explainer template — the reader-facing sibling of report/template.md.

  THIS FILE CONTAINS NO MEASURED NUMBERS, BY RULE, AND render-explainer.mjs
  ENFORCES THAT with the same bare-digit-run check render-report.mjs applies to
  the audit report's template. Every run fact is a {{placeholder}} resolved from
  journal.ndjson; every figure about the law or the encoding lives in a
  checked-in narrative file, where it must be a placeholder or a citation whose
  source line this renderer re-reads and matches before printing it.

  The prose is NOT here. Narrative comes from etc/go/subjects/<id>/explainer/,
  is drafted, checked in and reviewed, and arrives as blocks. A template that
  carried the argument would put the argument out of reach of the provenance
  record, the review signature, and the drift check.
-->

# {{explainer.title}}

_{{run.subject_display}} — {{run.citation}}. This document has two jobs: to
explain the law, and to explain what happened when somebody tried to make it
executable. The two threads interleave, because the second is only interesting
where it lands on the first._

_`explainer.html` is the document; `explainer.md` is the record. Both carry the
same text, the same banners and the same citations. **Only the HTML carries the
pictures**: it inlines every figure, and the markdown names each figure's file
and draws nothing._

{{narrative.banner}}

|              |                                                                                            |
| ------------ | ------------------------------------------------------------------------------------------ |
| subject      | {{run.subject}} — {{run.citation}}                                                         |
| run id       | `{{run.id}}`                                                                               |
| milestone    | {{run.milestone_upper}}                                                                    |
| repo HEAD    | `{{run.repo_head}}` ({{run.tree_state}})                                                   |
| clock        | `{{run.fixed_now}}`                                                                        |
| journal      | `{{run.journal_path}}` — {{run.record_count}} records read here, chain {{run.chain_state}} |
| gates        | {{gates.summary}}                                                                          |
| run verdict  | {{run.verdict}}                                                                            |
| audit report | {{report.pointer}}                                                                         |

> This document may make no claim the audit report cannot support. Every run
> fact above and below resolves from the same journal, folded the same way. Where
> the two disagree, the audit report governs and this one has a defect.

---

## What this is, and who it binds

{{sections.orientation}}

---

## Use it

{{sections.cta}}

---

## Pictures

{{sections.pictures}}

---

## How this works, and what the words mean

{{sections.how_it_works}}

---

## The rules

{{sections.body}}

---

## Time

{{sections.time}}

---

## Where the law is unsettled

{{sections.forks}}

---

## Limits

{{sections.limits}}

---

## What was never searched

{{sections.sweep}}

---

## How to check this document

{{sections.provenance}}

{{footer.generated}}
