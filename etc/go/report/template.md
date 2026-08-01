<!--
  The conversion report template.

  THIS FILE CONTAINS NO MEASURED NUMBERS, BY RULE, AND render-report.mjs
  ENFORCES THAT. Every figure is a {{placeholder}} resolved from journal.ndjson.
  Unresolved placeholders are a hard error, and a bare digit-run that is not on
  the small allowlist in render-report.mjs is a hard error too.

  The reason is on the record: PROJECTIONS.md carries "114 blocking, 46 lossy,
  18 advisory" while the exporter emits different counts, and two different
  stale line counts for one file. Those numbers were transcribed once and
  never re-measured. A claim with no journal row cannot be printed here.
-->

# {{run.milestone_upper}} conversion report — {{run.subject}}

|             |                                                                                  |
| ----------- | -------------------------------------------------------------------------------- |
| run id      | `{{run.id}}`                                                                     |
| milestone   | {{run.milestone_upper}} — {{run.milestone_gloss}}                                |
| subject     | {{run.subject}}                                                                  |
| repo HEAD   | `{{run.repo_head}}` ({{run.tree_state}})                                         |
| clock       | `{{run.fixed_now}}`                                                              |
| `l4` binary | `{{run.l4_binary}}`                                                              |
| journal     | `{{run.journal_path}}` — {{run.record_count}} records, chain {{run.chain_state}} |
| verdict     | **{{run.verdict}}**                                                              |

> {{run.verdict_gloss}}

---

## Gates

{{gates.table}}

---

## What the source said

{{sections.source}}

---

## What the external-modification sweep searched and surfaced

{{sections.sweep}}

---

## What the encoding decided

{{sections.encoding}}

---

## What each projection preserved and lost

{{projections.table}}

{{projections.detail}}

---

## Test results

{{sections.tests}}

---

## Where another system published its own representation of the same rule

{{sections.comparison}}

---

## Triage

{{sections.triage}}

---

## Every artifact this run put on disk

{{artifacts.table}}

---

## How to re-derive this report without trusting it

```
etc/go/go.sh verify --run-id {{run.id}} --gates
```

That re-reads `journal.ndjson`, re-hashes every artifact a receipt names, checks
that each granted gate was recorded before the first stage it gates began, and
recomputes the milestone verdict. It runs no build, calls no model, and makes no
network request. A second party can run it later against the same run directory
and does not have to believe anything this report says.

{{footer.generated}}
