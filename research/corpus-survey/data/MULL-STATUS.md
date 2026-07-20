# MULL sub-corpus — status & harvest note (2026-07-20)

*Modern Uses of Logic in Law* — the historical genealogy target (Layman Allen's cohort; became
*Jurimetrics*). Metadata captured from the JSTOR journal page; **article-level TOC harvest is
blocked** (see "Blocker" below) so this is an **issue-level skeleton**, not a paper index yet.

## Journal identity (confirmed on JSTOR)

- **JSTOR slug:** `moduseloglaw` → `https://www.jstor.org/journal/moduseloglaw`
  (via NLB proxy: `www-jstor-org.proxy.lib.sg`).
- **ISSN:** 2163-9240 · **Publisher:** American Bar Association · **© ABA**.
- **JSTOR collection:** Arts & Sciences XII / JSTOR Archival Journal & Primary Source Collection.
- **Coverage:** 1959–1966, Vol. 1 No. 1 → Vol. 7 No. 2. **Moving wall:** 3 years (irrelevant — old).
- **Title lineage (JSTOR "Title History"):**
  - 1959–1966 — **MULL: Modern Uses of Logic in Law**  ← this target
  - 1966–1976 — *Jurimetrics Journal*  (slug `jurimetricsj`)
  - 1976–2022 — *Jurimetrics*  (slug `jurimetrics`)
  A single continuous JSTOR lineage — the genealogy thread runs MULL → Jurimetrics unbroken.

## Issue-level skeleton (from the journal "All Issues" panel, 1960s decade)

Quarterly (Mar / Jun / Sep / Dec). 24 issues visible for Vols 2–7; Vol. 1 (1959) sits under the
collapsed 1950s decade and was not captured (blocker hit before expansion completed).

| Vol | Year | Issues |
|----:|-----:|--------|
| 7 | 1966 | No.1 Mar, No.2 Jun |
| 6 | 1965 | No.1 Mar, No.2 Jun, No.3 Sep, No.4 Dec |
| 5 | 1964 | No.1 Mar, No.2 Jun, No.3 Sep, No.4 Dec |
| 4 | 1963 | No.1 Mar, No.2 Jun, No.3 Sep, No.4 Dec |
| 3 | 1962 | No.1 Mar, No.2 Jun, No.3 Sep, No.4 Dec |
| 2 | 1960 | No.1 Mar, No.2 Jun, No.3 Sep, No.4 Dec |
| 1 | 1959 | **pending** — ≥ No.1 (Sept 1959); front matter = JSTOR `stable/29760800` |

Est. total ~26 issues, ~120–180 items (many short notes / letters / bibliographies).

## Known articles (confirmed IDs — seeds for on-demand acquisition)

- **Layman E. Allen — "Propositional Calculi"** — MULL 1(1), 1959, pp. 4–44. *(foundational)*
- Patrick A. James — "Mechanization of a Tax Code" — MULL 1(1), 1959.
- "Bibliography" — MULL 1(1), 1959, pp. 17–24.
- (Prior session, likely later Jurimetrics-era) "Normalized Legal Drafting and the Query Method"
  — JSTOR `stable/42892477` (Allen & Engholm lineage).

## Acquired on-demand (2026-07-20, via user's authenticated JSTOR clicks)

Downloaded to `/Volumes/Downloads` (kept there — © ABA, not committed to git). Identities
confirmed from each PDF's own first-page citation block:

| Stable ID | Item | Cite | Note |
|-----------|------|------|------|
| 29760800 | Front Matter | MULL 1(1) 1959 | issue front matter |
| 29760801 | Mechanization of a Tax Code — Patricia A. James | MULL 1(1) 1959, pp.1–3 | |
| **29760802** | **Propositional Calculi — Layman E. Allen** | MULL 1(1) 1959, pp.4–14 | **foundational** |
| 29760804 | Bibliography | MULL 1(1) 1959, pp.17–24 | |
| 29760943 | Front Matter | MULL **4(3)** 1963 | cross-vol straggler |
| 29760860 | Readers' Letters… — Clore Warne & Reed C. Lawlor | MULL **2(4)** 1960, pp.150–157 | cross-vol straggler |

**Vol.1 No.1 is NOT complete:** the "Related" feed is a mixed recommendation list, not a TOC.
Missing from 1(1): `29760803` (≈ pp.15–16) and `29760805`+ (pp.25–52). But see the ID-sequence
unblock below.

## KEY UNBLOCK — stable IDs are sequential within an issue

The acquired IDs (…800 front / …801 pp.1–3 / …802 pp.4–14 / …804 pp.17–24) prove JSTOR assigns
**contiguous stable IDs per issue in reading order**. So the whole of MULL 1(1) is ≈
`29760800`–`2976081x`, and later issues continue contiguously. This means a complete MULL index
does **not** require the blocked SPA TOC: enumerate stable IDs, download each (user-authenticated),
and read the citation off each PDF's own first page (`Source:` line). The SPA read-redaction is
bypassed entirely because the metadata rides inside the PDF, not the page DOM.

## Blocker (why the *automated* article-level TOC scrape failed)

JSTOR serves this as a client-rendered SPA and lazy-loads each decade via a clean endpoint:
`GET /journal/moduseloglaw/decade/<b64 year-range token>` (1950s token observed:
`AXllYXI6WzE5NTAgVE8gMTk2MH0`, decodes ≈ `year:[1950 TO 1960}`). **But** the browser-automation
read layer scrubs any tool output containing cookie/query-string data to `{}` on this proxied
origin — so DOM anchors, shadow-DOM walks, citation meta, *and* in-tab `fetch()` of the decade
endpoint all return empty. This is a **read-side redaction**, not an auth or navigation problem;
a user click can't bypass it. Multiple distinct approaches were tried and all hit the same wall.

## Paths forward (pick when MULL rises in priority)

1. **On-demand, sparing** (recommended, matches §5 guardrail): grab the handful of genuinely
   load-bearing MULL papers by known stable ID (Allen's "Propositional Calculi" first), one at a
   time, as the genealogy thread needs them — not a bulk index.
2. **Cookie-exported curl**: export the NLB-proxy JSTOR session cookies from Chrome and harvest
   the decade endpoints + issue TOCs with `curl` outside the MCP redaction layer. Cleanest for a
   full index, but needs the user to export cookies (sensitive — handle carefully).
3. **HathiTrust / HeinOnline**: MULL may be indexed there with plain TOCs; check if NLB has Hein.

**Decision for now:** MULL stays a logged, issue-level skeleton. It is a *historical* sub-corpus,
lower priority than the 1,758-paper modern core (indexed + enriched). Revisit via path 1 on demand.
