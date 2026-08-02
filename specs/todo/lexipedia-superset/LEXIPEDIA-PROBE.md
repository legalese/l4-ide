# Lexipedia probe — `reg_cf_exemptions` and the surrounding site

**Status: R2 probe, measured 2026-08-02; read-only; no contact was made.**

Every external claim below carries a URL, a fetch date, and a quote or a machine-derived count.
Every claim about *our* corpus is re-derived from this tree at the commit this file lands on, not
recalled. Anything that could not be fetched is marked **UNMEASURED** and is not guessed.

This is reconnaissance. It contains no sentence about what Lexipedia *should* do, and no plan for
contacting anyone: the pathway question — whether and how L4-derived artifacts might reach that
wiki — is **Meng's conversation with Anson**, gate HG2, and is out of scope here.

**Method.** All fetches were HTTP GET, 2026-08-02, from
`/Users/mengwong/src/legalese/l4wt/lexipedia-probe` on branch `docs/lexipedia-probe`. Where the
summarising fetch tool and a raw `curl` disagreed, the raw bytes govern — see the correction logged
in §1.4. No account was created, nothing was edited, no form was submitted, no message was sent.
`archive.org` fallback was **not needed**: every URL below returned HTTP 200 on first request.

---

## 1. What their page contains

Fetched 2026-08-02:

- rendered — `https://www.lexipedia.xyz/doku.php?id=reg_cf_exemptions` (HTTP 200, 56,991 bytes)
- raw wiki source — `https://www.lexipedia.xyz/doku.php?id=reg_cf_exemptions&do=export_raw`
  (HTTP 200, 15,240 bytes, 290 lines, `Content-Type: text/plain; charset=utf-8`)
- history — `https://www.lexipedia.xyz/doku.php?id=reg_cf_exemptions&do=revisions` (HTTP 200)

### 1.1 Structure

Three headings, and nothing else:

```
====== Regulation Crowdfunding (Reg CF) Exemptions ======
===== Overview =====
===== Detailed Reg CF Requirements =====
===== BPMN Model =====
```

The Overview is two sentences. "Detailed Reg CF Requirements" is a single nested ordered list of
**eight** numbered groups. The BPMN Model section is one `<bpmnio type="bpmn">` block containing
BPMN 2.0 XML inline. Of the 290 raw lines, **215 are the BPMN XML** — the prose is 75 lines.

The eight groups, in their order: Issuer Eligibility, Offering Limit, Investor Limits, Disclosure
Requirements, Use of Intermediaries, Advertising Restrictions, Ongoing Reporting, Resale
Restrictions. Our `regcf.l4` header already names this eight-group shape as the thing it mirrors
(`regcf.l4:16-27`), and the mirror is faithful — the groups and their order match one-for-one.

### 1.2 Coverage: which figures and citations actually appear

Every dollar figure on the page, quoted verbatim from the raw source:

> "Can raise up to $5 million in a 12-month period"
> "For investors with annual income or net worth less than $107,000:"
> "Greater of $2,200 or 5% of the lesser of annual income or net worth"
> "For investors with both annual income and net worth of $107,000 or more:"
> "10% of the lesser of annual income or net worth"
> "Information about officers, directors, and owners of 20% or more of the company"
> "Offerings up to $124,000: Financial statements and specific line items from income tax returns, certified by the principal executive officer"
> "Offerings between $124,000 and $618,000: Financial statements reviewed by an independent public accountant"
> "Offerings over $618,000:"
> "Make issuer information available for at least 21 days before any sale of securities"
> "Securities purchased in a Reg CF offering generally cannot be resold for one year"

**Citations.** The page carries **two** hyperlinks in the whole of its prose, both external, both in
the Overview:

> `[[https://www.sec.gov/education/smallbusiness/exemptofferings/regcrowdfunding|SEC Regulation Crowdfunding]]`
> `[[https://www.wikidata.org/wiki/Q348303|Wikidata: Crowdfunding]]`

The first is the SEC's small-business *education* landing page, not the regulation. There is **no
citation to 17 CFR Part 227 anywhere on the page** — no part number, no section number, no
paragraph. Two rules are named in running prose without numbers of their own hierarchy:
`"bad actor" rules (Rule 503 of Regulation Crowdfunding)` and `Rule 504 of Regulation D`; one statute
is named — `Exchange Act Section 13(a) or 15(d)`. Counting generously, that is **three** rule-level
references across eight requirement groups, and **zero** pin-cites to the operative paragraph of any
threshold on the page.

**Dates.** There are **no dates in the page body at all** — no effective date, no amendment date, no
"as in force on". The only date any reader can see is the DokuWiki footer's last-modified stamp.

### 1.3 Freshness — mixed, and the mixture is the finding

The page is not uniformly stale. It carries *some* 2021 and 2022 changes and not others.

| Amendment | Carried on their page? | Evidence |
|---|---|---|
| 2021 offering limit → $5,000,000 (Rel. 33-10884) | **yes** | "up to $5 million in a 12-month period" |
| 2021 accredited-investor carve-out (Rel. 33-10884) | **yes** | "Accredited investors have no limits" |
| 2021 "lesser of" → **"greater of"** measure (Rel. 33-10884) | **no** | still "5% of **the lesser** of annual income or net worth", twice |
| 2022 financial-statement tiers → $124,000 / $618,000 (Rel. 33-11098) | **yes** | "up to $124,000", "between $124,000 and $618,000" |
| 2022 investor cut point → $124,000 (same release, instr. 2.a) | **no** | still "$107,000", twice |
| 2022 investor floor → $2,500 (same release, instr. 2.a) | **no** | still "$2,200" |

So the **same release**, on the **same day**, moved figures the page updated *and* figures it did
not. This is the internal inconsistency our `README.md` §3.3 already records: `$107,000` in their
group 3 sits beside `$124,000` in their group 4, and the two moved in lockstep by separate
amendatory instructions of Release 33-11098 (87 FR 57394, 57398).

The 2021 "greater of" reversal (README §3.1) is the one that is not a stale number at all — it is a
**policy position the Commission abandoned**, still being stated as current law. Our README works
the arithmetic: an investor with $60,000 income and $200,000 net worth is limited to $10,000 under
the rule in force, and to $3,000 under the rule as the page states it.

**Why the staleness is not explained by age.** From `do=revisions`, fetched 2026-08-02, the prose
section is *recent*:

> `2026/02/10 16:23 reg_cf_exemptions – Added structured metadata per Lexipedia BPMN Model Metadata Standard (Tier 1 required + select Tier 2/3/4 fields). Restructured page with Overview, Detailed Requirements, and BPMN Model sections. admin +1.4 KB`

The requirement prose carrying `$107,000` and `$2,200` was written on **2026-02-10** — about three
years and five months after those figures were superseded on 2022-09-20. This is not a page that
was written correctly and then aged.

### 1.4 Embedded artifacts — one BPMN, no DMN, and a correction

**Correction, logged deliberately.** The first tool-summarised fetch of this page reported "an
embedded Base64-encoded BPMN diagram". That is **wrong**, and the raw bytes disprove it: the BPMN
travels as **plain inline XML** inside a `<bpmnio type="bpmn">` block, not base64. The same
summarised fetch also missed that the rendered HTML contains a *second*, DMN-shaped XML blob. Raw
inspection resolves that too — see below. Both errors are recorded here rather than quietly fixed,
because they are exactly the failure mode this probe exists to avoid.

Machine-derived properties of their Reg CF BPMN (from the raw source, 2026-08-02):

| property | value |
|---|---|
| `<bpmnio>` blocks on the page | 1, `type="bpmn"` |
| `isExecutable` | `"false"` |
| `<businessRuleTask>` | **0** |
| `<conditionExpression>` | **0** |
| tasks / exclusive gateways / start / end | 9 / 3 / 1 / 1 |
| DMN on this page | **none** |

Three observations about the diagram itself, all from element names in the raw XML:

1. **No failure path exists.** `eligibilityCheck` is an `exclusiveGateway` with exactly **one**
   outgoing flow, labelled `name="Eligible"`. `offeringLimitCheck` likewise has one outgoing flow,
   `name="Within Limit"`. An ineligible issuer, or one over the limit, has nowhere to go.
2. **Two elements appear transposed.** The gateway `name="Check Investor Contribution Limits"`
   precedes tasks `"Apply 5% Limit"` / `"Apply 10% Limit"`, which flow into a gateway
   `name="Offering Limit Check"`, which flows into a task `name="Check Investor Limits"`. The
   offering limit was already checked upstream at `task1 name="Check Offering Limit"`.
3. **The branch labels carry the stale figure too.** The sequence flows are labelled
   `name="Income/Net Worth &#60; $107,000"` and `name="Income/Net Worth &#62;= $107,000"` — so
   `$107,000` appears on the page a **third** time, inside the diagram, where a reader correcting
   the prose would not think to look. The diagram and the prose are two hand-maintained copies of
   one number with nothing linking them.

**The DMN blob in the rendered HTML is not content.** The rendered page contains DMN XML with
`decision id="dish-decision"`, `"season"`, `"guestCount"` and rules returning `"Spareribs"`,
`"Light salad"`, `"Steak"`. That is the stock dmn-js demo model, shipped inside the editor
**toolbar's** "Add a DMN diagram" insert template — it appears in the `var toolbar = [...]`
JavaScript on *every* page of the wiki, including pages that do not exist. It is not on the Reg CF
page's content. Verified by `do=export_raw`, which contains no DMN.

### 1.5 Authorship signals

From `do=revisions`, fetched 2026-08-02: **every** revision of this page is attributed to `admin`,
except one `2026/01/05 20:27 … external edit 127.0.0.1`. Fifteen revisions are visible, from
`2024/11/12 17:36` to `2026/06/19 23:28`. Ten of them carry the summary `[Edit diagram]`, which is
the `bpmnio` WYSIWYG editor's automatic summary — i.e. most of the page's history is diagram
fiddling, not prose revision.

Footer, quoted from the rendered page:

> `reg_cf_exemptions.txt · Last modified: 2026/06/19 23:28 by admin`

No named author, no reviewer, no sourcing note, no "as in force" statement anywhere on the page.

---

## 2. Site mechanics

### 2.1 Platform

`<meta name="generator" content="DokuWiki"/>` — present on every page fetched. **The precise
DokuWiki release is UNMEASURED**: the generator tag carries no version, and `doku.php?do=check` is
admin-gated. Server header, from the response to the raw fetch, 2026-08-02:

> `Server: Apache/2.4.52 (Ubuntu)`

Also observed on every response: `X-Robots-Tag: noindex` on the raw export, and
`<meta name="robots" content="noindex,follow"/>` in page HTML.

### 2.2 Markup dialect

Standard DokuWiki markup, confirmed against their own `quick_start_guide`
(`https://www.lexipedia.xyz/doku.php?id=quick_start_guide&do=export_raw`, HTTP 200, 2026-08-02),
which documents it in their own words:

> "Lexipedia runs on [[https://www.dokuwiki.org|DokuWiki]], a lightweight, file-based wiki engine.
> Editing is done through simple text markup — no special software required."

Headings are `====== … ======` down to `== … ==`; tables are `^ header ^` / `| cell |`; lists are
two-space-indented `*` and `-`. Note the inversion their guide flags explicitly — *more* equals
signs means a *higher*-level heading, the opposite of MediaWiki.

### 2.3 Plugins in evidence

Detected from asset paths, `JSINFO` plugin config, and syntax actually used in raw page sources
(all 2026-08-02):

| plugin | evidence |
|---|---|
| **bpmnio** | `<bpmnio type="bpmn">` / `type="dmn"` syntax; assets `/lib/plugins/bpmnio/images/toolbar/{bpmn_add,dmn_add,picker}.png`; CSS classes `plugin-bpmnio`, `plugin-bpmnio icon-large` |
| **struct** | `JSINFO.plugins.struct = {"isPageEditor":false,…}`; `define` page uses `struct_schema "process"` and links `https://www.dokuwiki.org/plugin:struct` |
| **bureaucracy** (or equivalent `<form>` handler) | `define` page contains `<form> action template define_templates:process_stub …</form>` blocks |
| **vshare** | `JSINFO.plugins.vshare` with a youtube/vimeo/… regex table; `start` uses `{{youtube>2rnyY7xew7c?}}` |
| **mermaid** | `/lib/plugins/mermaid/mermaid.css`; page JS does `import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.esm.min.mjs'` |
| **move** | `JSINFO.move_renameokay`, `JSINFO.move_allowrename` |

The `bpmnio` toolbar templates disclose the embedded editor versions:

> `exporter="bpmn-js (https://demo.bpmn.io)" exporterVersion="18.3.1"`
> `exporter="dmn-js (https://demo.bpmn.io/dmn)" exporterVersion="17.0.2"`

and the DMN template declares `xmlns="https://www.omg.org/spec/DMN/20191111/MODEL/"` — **DMN 1.3**.

### 2.4 How an embedded BPMN or DMN would have to travel

This is a mechanical observation about the plugin, not a proposal.

The `bpmnio` plugin takes the **XML inline in the page source**, wrapped in
`<bpmnio type="bpmn">…</bpmnio>` or `<bpmnio type="dmn">…</bpmnio>`. There is no file attachment, no
`{{media}}` reference, and no external URL involved: the diagram *is* wiki text, versioned in the
page's own revision history, and editable both as markup and through the embedded bpmn-js/dmn-js
WYSIWYG canvas (which is what produces the `[Edit diagram]` revision summaries). Consequences that
follow directly:

- A diagram is bytes in a `.txt` page file, so any XML that round-trips through bpmn-js 18.3.1 /
  dmn-js 17.0.2 can be pasted in as-is; the DMN namespace the plugin's own template declares is
  the same DMN 1.3 our exporter emits.
- One page can hold more than one block, and blocks of both types (their charities pages, §2.5,
  put BPMN and DMN on separate pages and cross-link them by DokuWiki link).
- **Everything is a copy.** The plugin gives a diagram no relationship to any prose on the same
  page, and no relationship to a diagram on another page. Their Reg CF page demonstrates the
  consequence: `$107,000` in the prose and `$107,000` in the sequence-flow labels are two
  independent strings.

Their own `documentation` page (`?id=documentation&do=export_raw`, HTTP 200, 2026-08-02) states the
authoring pipeline in their own words, under a header dated `**A P Updates 12/8/24**`:

> "Use [[https://github.com/jtlicardo/bpmn-assistant|bpmn-assistant]] to design models (I've tested
> claude and gpt with decent results, and the students have confirmed gemini is working)"
> "Embed the downloaded XML in the dokuwiki wiki (here) using the BPMN tool in the WYSIWYG editor"
> "Discuss as needed then port over to [[https://www.spiffworkflow.org/|Spiff Workflow]] where it
> can be used and reviewed and put in to containers"

### 2.5 Corpus breadth — and a namespace that mirrors our own case study

`https://www.lexipedia.xyz/doku.php?do=index` (HTTP 200, 67,473 bytes, 2026-08-02) yields **187
distinct top-level page ids** and these namespaces: `charlottesville`, `decisions`,
`define_templates`, `playground`, `process`, `wiki`, plus three spam namespaces
(`best_weight_loss_pills_italy`, `guide_to_crypto_casino_games`, `guide_to_online_crypto_casino`).

**A large share of the top-level ids are link-spam.** Sampling the index: `10_quick_tips_about_crypto_casino_games`,
`buy_driver_s_license_now_tools_to_ease_your_daily_life_buy_driver_s`,
`20_things_you_need_to_be_educated_about_ielts_certificate`,
`10_places_to_find_pain_relief_tablets_italy`, `bclub_tk`, `savastan0.tools`, `ultimateshop_ru`.
`?do=recent` (HTTP 200, 2026-08-02) shows this is **current and daily** — fifteen consecutive
entries dated `2026/07/30`, all `– created` by throwaway accounts (`ielts-exam-certificate4150`,
`buy-phentermine-italy0319`, `order-french-driving-license9135`, `crypto-online-casino8038`, …).
Genuine legal/civic content is a minority of the top-level namespace by page count.

The substantive corpus is concentrated in namespaces. `?idx=process:je:charities-2014&do=index`
(HTTP 200, 2026-08-02) lists **16 pages** under `process:je:charities-2014`:

```
start  charity-test  registration  deregistration  enforcement  appeal
name-check  governor-fitness  ongoing-compliance  restricted-section
dmn-charity-test  dmn-registration  dmn-governors  dmn-enforcement
dmn-appeal  dmn-terms
```

**This is the Charities (Jersey) Law 2014 — the same statute as our own case study at
`paper/case-studies/charities-jersey-2014/`.** Its `start` page reads:

> `====== Charities (Jersey) Law 2014 — process register ======`
> `//Business Process (BPMN 2.0) · Jurisdiction: Jersey (Channel Islands) · Statute: Charities (Jersey) Law 2014 (L.41/2014)//`

and `dmn-charity-test` reads:

> `//DMN 1.3 decision requirement diagram · Jurisdiction: Jersey · Statute: Charities (Jersey) Law 2014//`
> `Decision-requirement diagram for the charity test. \`PurposeClassification\` (Art 6) and \`PublicBenefit\` (Art 7) feed \`CharityTest\` (Art 5).`

The correspondence to our tree is close. Our `paper/case-studies/charities-jersey-2014/part-3-charity-test.l4`
header (lines 5-41) sets out the same three-tier shape and the same two carve-outs — Art 6(5)
political purposes and Art 5(2)-(3) government control — and their `charity-test` page's prose names
both:

> "with the political-purpose (Art 6(5)) and government-control (Art 5(2)–(3)) carve-outs. Purposes
> are classified individually and aggregated."

Machine-derived properties of these pages, unlike the Reg CF page:

| property | `process:je:charities-2014:charity-test` | `…:dmn-charity-test` |
|---|---|---|
| `<bpmnio>` blocks | 1, `type="bpmn"` | 1, `type="dmn"` |
| `isExecutable` | `"false"` | — |
| `<businessRuleTask>` | **6** | — |
| `<conditionExpression>` | 4 (`meetsCharityTest == True` / `== False`) | — |
| `<decisionTable>` / `<rule>` | — | 3 / 28 |
| `hitPolicy` | — | `FIRST` (all three) |
| `<inputData>` | — | **0** |

**Two precise qualifications, because they matter and are easy to overstate:**

1. The BPMN↔DMN link is **prose inside a `<documentation>` element, not a machine-readable
   attribute.** The raw XML carries `<bpmn:businessRuleTask id="r_class" name="Classify each purpose
   (Art 6) [multi-instance]">` whose `<bpmn:documentation>` text is the literal string
   `decisionRef: Decision_PurposeClassification`. There is **no `decisionRef` XML attribute** and no
   `camunda:` namespace on the page. A human can follow the reference; an engine cannot.
2. **Attribution and authorship are UNMEASURED.** The namespace contains **no** occurrence of
   `L4`, `legalese`, `jl4`, `smucclaw`, or any pointer to this repo (grepped across `start`,
   `charity-test`, `dmn-charity-test`, `registration`, 2026-08-02). Its revision history reads
   `process/je/charities-2014/dmn-charity-test.txt · Last modified: 2026/07/27 01:12 by 127.0.0.1`
   — a server-local edit with no logged-in user, which is what DokuWiki records for a filesystem or
   API write. **Who created these pages, and from what source, cannot be determined read-only.** It
   is equally consistent with an independent encoding of a publicly available statute. Do not assert
   otherwise on this evidence; see §6.

The `decisions` namespace holds one page, `decisions:boston-article80-threshold`.

---

## 3. Contribution routes visible without an account

Observations only. Whether any of these is used, and by whom, is Meng's conversation with Anson
(gate HG2) — not a question this probe answers or advances.

Everything in this section was **readable while logged out**.

- **Registration is open and self-service.** `?id=start&do=register` (HTTP 200, 2026-08-02) renders
  a working form — Username, Real name, E-Mail — with the text
  `"Fill in all the information below to create a new account in this wiki."` No invitation code and
  no approval step is mentioned on the form. *(The form was read, not submitted.)*
- **Their Quick Start Guide states editing requires an account**, in its own words:
  > "To edit pages on Lexipedia, you need a registered account. Click **Register** in the top-right
  > corner of any page, fill in the form, and you're ready to go."
- **Two named intake paths exist**, `define` and `refine`, both linked from the front page and both
  readable logged out:
  > "Lexipedia grows in three ways: **defining** new models, **refining** the ones already in
  > progress, and **exploring** what the community has built so far. Pick a path below — no
  > experience needed."
- **`define` offers structured intake backed by `struct` schemas**, and names three of them:
  > "Every process and case page is backed by a [[https://www.dokuwiki.org/plugin:struct|Struct]]
  > schema (**process**, **case**, or **law**) that defines the structured fields shown in each
  > page's Quick Facts table."
  Its two `<form>` blocks target `define_templates:process_stub` and a case stub. There is also a
  by-hand route: *"Prefer to build it by hand instead? Copy the [[sample_entry|Sample Entry]]
  template directly."*
- **`refine` lists work-in-progress pages by name**, including `[[reg_cf_exemptions|Reg CF
  Exemptions]]`, under the heading `What "Refining" Looks Like`, whose bullets include
  *"Add or finish a BPMN/DMN diagram"* and *"Add or fix citations and legal references"*.
- **`groups` (Community Guidelines)** is linked from the front page and self-describes as
  *"how we collaborate (a work in progress)"*.
- **`?do=recent`** and **`?do=index`** are both readable logged out.
- **Governance/ownership**, from the front page: *"Built by the
  [[https://www.centerforcivic.org/|Center for Civic Innovation]]"*, with sponsors listed as
  Sartography & SpiffWorkflow, LexDAO, Center for Civic Innovation, and Naptha.AI.

**Not visible without an account (UNMEASURED):** whether editing is rate-limited or moderated; how
new pages are reviewed; whether an ACL restricts the `process:` namespace; whether the `struct`
`law` schema has fields for citation, effective date, or rule version; the content of the
`define_templates:` stubs; and any private-wiki policy on machine-generated contributions.

---

## 4. Licensing

**Confirmed: CC BY-SA 4.0.** The statement is in the **page footer of every page**, not on a
dedicated licence page. Quoted verbatim from the rendered `reg_cf_exemptions` page, 2026-08-02:

> "Except where otherwise noted, content on this wiki is licensed under the following license:
> CC Attribution-Share Alike 4.0 International"

The accompanying link resolves to `creativecommons.org/licenses/by-sa/4.0/deed.en`, and the footer
badge is `/lib/images/license/button/cc-by-sa.png`. The identical footer appears on
`?id=start`, `?do=register`, `?do=recent`, and the charities namespace pages — i.e. it is the
wiki-wide default, and the `"Except where otherwise noted"` clause means a page *could* in principle
carry a different licence. **No such per-page override was observed on any page fetched**, and none
appears on `reg_cf_exemptions`.

**Our side, re-derived from this tree:** `LICENSE` at the repo root is the **Apache License 2.0**,
`Copyright 2025 Singapore Management University`. `README.md:108` states: *"L4 is published under the
[Apache-2.0 License](LICENSE)."* Note this differs from the "our prose is CC-BY" framing the probe
brief used — measured, the whole repo including its prose is under Apache-2.0. That does not change
the direction of the constraint below, but the licence name should be stated correctly downstream.

### 4.1 The flow is one-way

- **Outbound (ours → theirs) is possible in principle, and is a rightsholder's decision, not a
  mechanical one.** The copyright holder of our material can license its own work under CC BY-SA 4.0
  for a wiki contribution regardless of what it also publishes under Apache-2.0. That decision
  belongs to SMU and to Meng, is not measurable here, and is **not** proposed by this document.
- **Inbound (theirs → ours) is blocked.** CC BY-SA 4.0 is a copyleft licence: a derivative or
  adaptation of their page must itself be offered under BY-SA (or a compatible licence). Our tree is
  Apache-2.0. Copying their prose into `regcf.l4`, `README.md`, or any file in this repo would put
  BY-SA-obligated text inside an Apache-2.0 distribution.
- **What this does not restrict.** US federal regulatory text is not subject to copyright, so every
  CFR passage quoted inline in `regcf.l4` is unencumbered and does not come from their page —
  `regcf.l4:39-42` already records that the quotations are taken from the eCFR at the 2026-07-23
  issue date and that *"Nothing here was taken from the mirrored wiki page"*. Facts and thresholds
  are likewise not copyrightable; **their expression of them is.**

### 4.2 Consequence for the G4 comparison note: own words, with quotation

The comparison note must be written **in our own words, quoting only what it contradicts**, and must
not reproduce their page in substance. Short, attributed quotation for criticism and comparison is
the standard basis, and it also happens to be the only form that keeps the note free of BY-SA
obligations — an own-words analysis that quotes `"5% of the lesser of annual income or net worth"`
in order to show the rule was amended is criticism; a restructured copy of their eight groups is an
adaptation.

`jl4/examples/legal/regcf/README.md` already carries the correct attribution paragraph and should
remain the model:

> "The mirrored page is © its authors under **CC BY-SA 4.0** (Center for Civic Innovation,
> Lexipedia). It is referenced here for criticism and comparison. Everything quoted inline in
> `regcf.l4` is US federal regulatory text, which is not subject to copyright."

One gap worth naming: the **BPMN XML on their page is also their copyrighted expression** under the
same footer licence, and it is easier to copy inadvertently than prose. Our BPMN goldens are cut
from `regcf.l4` by `l4 export` (README §6.2) and share no element ids with theirs — verified by
inspection: theirs uses `task1`…`task9`, `eligibilityCheck`, `investorLimitCheck`.

---

## 5. Coverage diff against our corpus

**Every OUR-side figure below is re-derived from this tree on 2026-08-02**, by reading the files
named, not from memory or from prose that might itself have drifted.

Re-derived counts, `jl4/examples/legal/regcf/regcf.l4`:

| measurement | command | value |
|---|---|---|
| lines | `wc -l regcf.l4` | **1236** |
| `#ASSERT` directives | `grep -c '^#ASSERT'` | **70** (0 inside comments) |
| `#TRACE` directives | `grep -c '^#TRACE'` | **7** |
| `#EVAL` directives | `grep -c '^#EVAL'` | **1** |
| `@ref` citations | `grep -c '@ref'` | **67** |
| DMN engine cases | `len(json['cases'])` in `jl4/examples/dmn/regcf-corpus.cases.json` | **16** |

> **Two drifts in our own documentation, found while re-deriving and not yet fixed.**
> `PROJECTIONS.md:3` calls `regcf.l4` "the 992-line formalisation"; it is **1236** lines.
> `README.md` §4 reports *"55 assertions, all satisfied"*; the file now carries **70** `#ASSERT`
> directives, and `regcf-corpus.cases.json`'s own note records a 2026-08-02 run of
> *"140/140 assertions satisfied"* on a copy with the relocated fixtures. Both figures are stale
> prose about a tree that moved. Recording here; the fix belongs in a PR that touches those files.
> (This probe is read-only as to lexipedia, not as to our own docs — but the fix is out of its
> scope, and asserting a corrected number without running `l4` would be guessing.)

### 5.1 The diff table

| Dimension | Lexipedia `reg_cf_exemptions` (fetched 2026-08-02) | Our `regcf.l4` corpus (re-derived 2026-08-02) |
|---|---|---|
| **Scope** | 8 requirement groups, prose | the **same** 8 groups, deliberately (`regcf.l4:16-27`) — scope is matched by construction, so scope is not the axis of difference |
| **Size** | 75 lines of prose + 215 lines of BPMN XML | 1236 lines |
| **Offering limit** | `$5 million` | `$5,000,000`, dated 2021-03-15, prior value `$1,070,000`, prior-prior `$1,000,000` (`regcf.l4:133-140`) |
| **Investor cut point** | `$107,000` (superseded 2022-09-20) | `$124,000` since 2022-09-20; `$107,000` 2017-04-12→2022-09-19; `$100,000` from 2016-05-16 (`regcf.l4:144-152`) |
| **Investor floor** | `$2,200` (superseded) | `$2,500` / `$2,200` / `$2,000`, each dated (`regcf.l4:156-161`) |
| **Per-investor cap** | not stated as a distinct parameter | `$124,000` / `$107,000` / `$100,000`, its own binding with its own `@ref` (`regcf.l4:165-171`) |
| **Measure (i)/(ii)** | "**the lesser** of annual income or net worth" — the pre-2021-03-15 rule | "the **greater** of" since 2021-03-15; the shape change is modelled, not just the numbers (README §3.1) |
| **Fin-stmt tiers** | `$124,000` / `$618,000`; third boundary absent | `$124,000` / `$618,000` / **`$1,235,000`**, all dated (`regcf.l4:175-201`); the first-time-issuer relief is bounded (README §3.4) |
| **Reporting exits** | 3 of 5 (reporting company, repurchase, liquidation) | all 5, incl. **300 holders** (b)(2) and **$10,000,000 assets** (b)(3), with boundary tests 299/300 and 10,000,000/10,000,001 (README §3.7) |
| **Eligibility limbs** | 5 of 6 conditions of Rule 100(b) | all 6, incl. **(b)(5) delinquent filer** with a dedicated fixture (README §3.6) |
| **Deadlines** | `21 days`, `one year` only | plus `120 days` (Form C-AR), `5 business days` ×2 (C-TR, C-U), each with a citation (README §2) |
| **Substantive errors** | Rule 504 aggregation stated backwards (README §3.5); advertising notice missing a permitted content item (README §3.8); accredited carve-out stated undated (README §3.9) | 9 divergences itemised with citation and arithmetic in README §3 |
| **Citations** | 2 hyperlinks (an SEC education page + Wikidata); 3 rules named in prose; **0 pin-cites to 17 CFR** | **67 `@ref`** citations; every threshold carries its CFR paragraph *and* its Federal Register amending instruction (README §2, 16 rows) |
| **Law-time / rule versions** | **none** — no effective date appears in the page body | 4 dated regimes on the rule-version axis — **2016-05-16, 2017-04-12, 2021-03-15, 2022-09-20** (`regcf.l4:47-64`), every constant answering under `EVAL UNDER RULES EFFECTIVE AT` for any date back to commencement; pre-commencement dates are a curated **refusal**, not an answer |
| **Deontics** | prose "must" / "may not"; no formal obligation | 3 regulative rules — `advertising restriction`, `ongoing reporting obligation`, `resale restriction` — with PARTY/MUST/WITHIN/HENCE/LEST, residuated by 7 `#TRACE`s (README §4, §6.2) |
| **Executability** | BPMN `isExecutable="false"`, 0 `businessRuleTask`, 0 `conditionExpression`, no DMN | 67 DMN decisions incl. 9 decision tables, 10 BKMs (3 more tables inside), 7 decisionServices, 15 inputData; **evaluates on two independent engines** over 16 cases — KIE 8.44.0.Final 1072/1072 decisions and values, Camunda 8.7.6 (zeebe-dmn) 1072/1072 (`PROJECTIONS.md` §1, CI-gated) |
| **Tests** | none | **70** `#ASSERT` + 7 `#TRACE` + 1 `#EVAL`; a case on each side of **every** numeric threshold (README §4 table) |
| **Single-sourcing** | `$107,000` appears **3×** — twice in prose, once in the diagram's flow labels — as three independent strings | every figure bound **once**; the DMN, dmnmd, BPMN, ladder figures and deployed API are all cut from the same file (`PROJECTIONS.md` §0) |
| **Known losses, declared** | none stated | 0 blocking / 21 lossy / 125 advisory fidelity findings, itemised by code (`PROJECTIONS.md` §1) — incl. `D-RULEDATE-UNBOUND` ×15, the scoped rule-dates a DRG cannot express |
| **Provenance** | 15 revisions, all `admin` or `127.0.0.1`; no sourcing note | sources pinned to eCFR at the 2026-07-23 issue date, cross-checked against amending releases (`regcf.l4:39-42`) |

### 5.2 The comparison that is not about coverage

On **coverage of the eight groups**, the gap is real but bounded — they state 5 of 6 eligibility
limbs and 3 of 5 reporting exits, and miss one tier boundary. A diligent editor could close that in
an afternoon of prose edits.

What no prose edit closes is the **third `$107,000`**. Their figure lives in the prose twice and in
the diagram's `sequenceFlow` labels once, as three unrelated strings; ours is one binding with one
citation and one set of dated arms, and the DMN, BPMN and wizard all read it. That is the claim
`PROJECTIONS.md` opens with, and this probe measured it rather than assuming it: their 2022 update
reached their group 4 and not their group 3 or their diagram, which is exactly the failure a
transcribed figure has and a projected figure does not.

---

## 6. What the G4 comparison note will need that this probe could not see

Stated honestly. Each item is account-gated, admin-gated, or simply not determinable read-only.

1. **Who authored `process:je:charities-2014`, and from what source.** The single most consequential
   unknown found. The pages mirror our Jersey case study's structure and carve-outs (§2.5) and
   carry **no attribution to L4 or this repo**, but their revision history shows only
   `127.0.0.1` — a server-local write with no username. Read-only access cannot distinguish a
   filesystem/API import from an independent encoding of a public statute. **G4 must not assert an
   origin on this evidence.** Resolving it needs either the wiki's own admin/user records or a
   direct answer — and any direct question is gate HG2's, not this probe's.
2. **The `struct` schema definitions.** `?do=index` exposes `define_templates:` as a namespace but
   the schema field lists live in the struct admin UI. Whether the `process`, `case` and `law`
   schemas have fields for citation, effective date, or rule version decides whether their platform
   can represent law-time at all — which is the sharpest column in §5.1's table and the one we
   currently characterise only from page content.
3. **The precise DokuWiki release and plugin versions.** `?do=check` is admin-gated; the generator
   tag is unversioned (§2.1). Only the embedded bpmn-js/dmn-js versions are known.
4. **Whether `?do=recent`'s spam is being cleaned, and by whom.** We measured creation
   (fifteen spam pages on 2026-07-30) but deletions do not appear in the default recent-changes
   view, so the *net* trend is UNMEASURED. Do not characterise the wiki as unmaintained on this
   evidence — the charities namespace was written three days earlier.
5. **Editorial policy.** Whether new pages are reviewed, whether machine-generated contributions are
   welcome or restricted, and whether `groups` (self-described as "a work in progress") states
   anything binding. Not answerable from the page.
6. **Whether their BPMN would round-trip.** We can see the plugin accepts inline XML from bpmn-js
   18.3.1 (§2.4), but whether *our* exporter's output survives that editor's normalisation is a
   thing to test locally against those versions — not something to claim from a fetch.
7. **Any non-public Reg CF material.** `?do=index` and `?do=recent` show only what is public; a
   draft or a restricted namespace would not appear.

---

## Appendix — every URL fetched, 2026-08-02

All returned HTTP 200. No archive.org fallback was required.

```
/doku.php?id=reg_cf_exemptions                                    56,991 B
/doku.php?id=reg_cf_exemptions&do=export_raw                      15,240 B  (290 lines)
/doku.php?id=reg_cf_exemptions&do=revisions
/doku.php?id=start                                                54,342 B
/doku.php?id=start&do=export_raw                                   6,385 B
/doku.php?id=start&do=register
/doku.php?do=index                                                67,473 B
/doku.php?do=recent
/doku.php?do=search&q=dmn
/doku.php?do=search&q=decisionTable
/doku.php?id=wiki:syntax&do=export_raw                            21,387 B
/doku.php?id=quick_start_guide&do=export_raw
/doku.php?id=define&do=export_raw
/doku.php?id=refine&do=export_raw
/doku.php?id=sample_entry&do=export_raw
/doku.php?id=documentation&do=export_raw
/doku.php?id=process:je:charities-2014:start&do=export_raw        13,853 B
/doku.php?id=process:je:charities-2014:charity-test&do=export_raw  7,177 B
/doku.php?id=process:je:charities-2014:dmn-charity-test&do=export_raw  22,273 B
/doku.php?id=process:je:charities-2014:dmn-charity-test&do=revisions
/doku.php?id=process:je:charities-2014&do=export_raw     (page does not exist — returns the
                                                          DokuWiki "notFound" HTML shell)
/doku.php?idx=process&do=index
/doku.php?idx=process:je&do=index
/doku.php?idx=process:je:charities-2014&do=index
/doku.php?idx=decisions&do=index
```

Local files read for the OUR-side column: `LICENSE`, `README.md`,
`jl4/examples/legal/regcf/{regcf.l4,README.md,PROJECTIONS.md}`,
`jl4/examples/dmn/regcf-corpus.cases.json`,
`paper/case-studies/charities-jersey-2014/part-3-charity-test.l4`.
