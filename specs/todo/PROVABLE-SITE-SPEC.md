# Provable — Site & Registry Implementation Spec

Implementation spec for the **new `provable` repo**: the marketplace website
(`provable.legalese.com`) and its registry API. Refines
[PROVABLE-MARKETPLACE-SPEC.md](PROVABLE-MARKETPLACE-SPEC.md) §4, §6, §7, §9,
§12 into route-by-route detail.

**Build status 2026-08-05 (second pass):** session management site-wide
(sign-in/up/out in the header, ?token= capture on any page, refresh-token
rotation via /api/session), catalog cards with facets/sort + both skill
kinds, skill detail per §9 (tools w/ parameter tables, markdown skill
guide, source viewer, install tabs w/ funnel recording, chat sidebar
iframe via chat.legalese.cloud/{org}/{dep}, reviews + report), uploads
(§3b) live incl. upload form, briefcase (§3c), /me dashboard,
/publishers/{org}, admin reports queue, registry-sync cron + tripwire,
publisher rows upserted at publish time (verified badge from the
publisher's own session), revalidation on publish/moderation.

**Ground truth as of 2026-08-05:** the platform layer is deployed and
validated end-to-end. `legalese.cloud/marketplace/{publish,unpublish}` and
`/marketplace/admin/{trust,suspend,state}` are live; cross-org and anonymous
access, metering, attribution, and the published-only catalog view on
`skills.legalese.cloud` all work (see `jl4-auth-proxy`
`validation/tests/16-marketplace.test.ts`); 8 skills are live. This site is a
_consumer_ of that layer: it never holds elevated credentials and is never in
the request path for rules evaluation.

**Architecture (revised 2026-08-05, main spec §4.2):** this site's Neon
database is **the one system of record for all marketplace state** — the
access tables (`marketplace_access`, `publisher_trust`, `suspensions`,
writable only via the auth-proxy endpoints; the site's DB role has no grant
on them) plus the listing/social tables this repo owns. The proxies serve
access decisions from an in-memory snapshot of the same tables, so the
catalog can never disagree with what is callable, and there are no mirror
columns and no reconciler. The shipped v1 EFS-file backing is migrated to
this in Phase 1a (main spec §13), which precedes this repo's build.

---

## 0. Positioning — what a RULES marketplace needs (researched 2026-08-05)

The 2026 skill-marketplace landscape is crowded (Claude Skills/skills.sh,
GPT Store, MCP hubs/Smithery, security-curated stores like Agensi, plus
enterprise MCP registries competing on governance). They compete on catalog
size, discovery, security scanning, and revshare — and they all share one
property: **a skill is prose**. A SKILL.md tells a model how to improvise;
nothing about its behaviour is verifiable, jurisdictional, or dated.

Legal/policy sharing inverts every one of those assumptions. Courts now
sanction unverified AI citations; professional-conduct rules are absorbing
AI-specific duties (California 2026); the EU AI Act's main obligations apply
from Aug 2026; and two decades of rules-as-code research says the hard
problems are mistranslation, point-in-time validity, and jurisdiction.
A lawyer or policy team consuming a skill has a _verification duty_ a
generic marketplace cannot help them meet.

**Provable's structural differentiators (already true by architecture):**

| Generic marketplaces                                | Provable                                                                                                     |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Skill = prompt prose; behaviour improvised per call | Skill = executable, type-checked L4; deterministic answers with derivation traces                            |
| Trust = stars + install counts (farmable)           | Reviews gated on **logged, metered usage**; "N orgs used this in 30 days"                                    |
| Publisher = a GitHub handle                         | Publisher = a WorkOS org with verified domains + one-time human review                                       |
| Source optional, often obfuscated                   | **Source-open by construction** — `l4:read` is in the marketplace grant; "Provable" means you can read _why_ |
| No usage accountability                             | Every call attributed (callerOrg/accessMode) — meterable, priceable, auditable                               |
| Content drift invisible                             | Content-hash versioning + hash-change tripwire on reported skills                                            |

**Rules-specific roadmap this positioning demands** (beyond generic-parity
features):

1. **Authority binding** _(Phase 2 — listing schema)_: every skill (ideally
   every function) links to the legal sources it encodes — statute, section,
   regulation, with URLs (`authorities` jsonb on `skills`). "Encodes s 33C
   Dog (Jersey) Law" is first-class metadata, filterable and shown beside
   the disclaimer. This is the metadata a consumer's verification duty needs.
2. **Temporal validity** _(Phase 2)_: `currentAsOf` / re-attestation date on
   the listing ("reviewed against sources on {date}"), surfaced as staleness
   badges — the point-in-time lesson from rules-as-code: law changes under
   the encoding.
3. **Amendment watch** _(Phase 4+)_: declared authorities make it possible
   to flag skills whose underlying instruments changed (initially a manual
   re-attestation cycle; later feeds/monitors). Generic stores cannot even
   express the question.
4. **Assurance ladder** _(Phase 3)_: tiered, displayed badges —
   source-open (everything) → verified publisher domain (§12.1) →
   **test-suite-backed** (L4 assertions shipped with the deployment, run
   deterministically, results on the listing — impossible for prompt
   skills) → professionally attested (named reviewer/firm attestation
   recorded like `terms_accept`).
5. **Verifiable answers as the consumer pitch**: evaluation traces cite the
   rules that fired; the listing shows the source those rules came from —
   the only marketplace whose answers help a professional DISCHARGE their
   verification duty rather than compound it.
6. **Uploaded generic skills (§3b) are the on-ramp, not the core**: catalog
   badges separate "Provable rules" (executable, source-open, attributed)
   from "skill bundles" (installable prose) — the upload tier meets
   publishers where they are; the rules tier is the moat.

## 1. Stack

| Piece           | Choice                                                               | Why                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| --------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Framework       | **Next.js 16.3+** (App Router) on Vercel                             | SSR skill pages for SEO; route handlers for the API; preview deploys. Turbopack + React Compiler are stable defaults                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Caching         | **Cache Components** (`"use cache"` + `cacheLife`/`cacheTag`)        | Next 16 made all dynamic code request-time by default; caching is opt-in per function — exactly right here (cache catalog/detail reads, never authed routes). No `unstable_cache`, no ISR-era `revalidate` idioms                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| DB              | Neon Postgres + Drizzle (`neon-http` driver)                         | first-party Vercel Marketplace integration; **every preview deploy gets its own DB branch** (auto-deleted on merge); rev-share reporting is relational. (Neon is Databricks-owned since 2025; storage dropped ~80% to $0.35/GB-mo)                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| — why not RDS   | decision, 2026-08                                                    | RDS wins on private networking, but Vercel can't reach in-VPC RDS without exposing it publicly (forfeiting that win), Secure Compute (enterprise), or an RPC layer in front (rebuilds the split-store problem). Neon adds preview branches, no RDS-Proxy connection management, scale-to-zero for a tiny DB. The snapshot-reader pattern neutralizes latency/HA arguments (proxy serves from memory; DB outage freezes updates, never serving). Revisit iff "no public DB endpoint" becomes a requirement or Vercel exits — plain Postgres + Drizzle makes that a dump/restore + connection string; the snapshot reader ports unchanged                                                          |
| — why not Redis | decision, 2026-08                                                    | Can't be the system of record: the listing/social/rev-share half is relational, so Redis would force Postgres back in and recreate the two-store sync. Cache-shaped persistence is wrong for audit-sensitive access/trust state, and placement hits the same dilemma (ElastiCache unreachable from Vercel; Upstash = public endpoint minus SQL). Redis's real fit is a LATER, narrow addition if requirements harden: fleet-exact counters (today per-instance + LiveCounterSync ≈ approximate caps, a pre-existing accepted trade) and sub-second revocation via pub/sub (vs ~15–30s snapshot refresh, also accepted). Slots in as a counter/invalidation layer without touching the data model |
| Compute         | Vercel **Fluid compute** (default)                                   | active-CPU billing: charges pause while a function waits on I/O — which is most of what this site's proxying routes do                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Auth            | Legalese Cloud AuthKit flow (`legalese.cloud/auth/login?return_to=`) | one identity across console/chat/provable; `provable.legalese.com` is already on the return_to allowlist mechanism (add to `ALLOWED_ORIGINS`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Styling         | match `legalese.com` marketing site                                  | Provable is the storefront brand                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |

Next 16 notes: if a request-level gate is ever needed it's `proxy.ts` (the
`middleware.ts` rename) — currently unneeded, the `/admin` check lives in the
route handlers. Cache invalidation on publish/moderation actions:
`cacheTag('skill:{org}/{dep}')` on cached reads, `revalidateTag` in the
mutating handlers.

**Session pattern** — identical to the console and webchat (`§2.2` of the main
spec): login redirect → `?token=` → `localStorage['wos-session-token']` →
`Authorization: Bearer` on every API call. No cross-domain cookies. Next
route handlers that need identity read the bearer from the request and
forward it — the site's API never mints or stores credentials.

**Environment:**

```
DATABASE_URL                Neon
LEGALESE_CLOUD_URL          https://legalese.cloud
SKILLS_REGISTRY_URL         https://skills.legalese.cloud
API_HOST_URL                https://api.legalese.cloud
AI_HOST_URL                 https://ai.legalese.cloud
```

No AWS keys, no WorkOS API key, no Stripe key until Phase 5.

---

## 2. Page routes (UI)

### `/` — catalog home _(Phase 2)_

- Hero: one sentence — "Auditable legal rules your AI can call." Search box.
- Category chips + featured/recent grids of **skill cards**: display name,
  publisher (+ verified badge §12.1), one-line summary, rating stars,
  "N orgs used this in the last 30 days", category.
- Data: `GET /api/catalog` (SSR; `"use cache"` + `cacheLife('minutes')`,
  tagged `catalog` and revalidated by publish/moderation handlers). Empty
  state pre-launch: "The first skills are being reviewed" + publisher CTA.

### `/skills/{org}/{dep}` — skill detail _(Phase 2, chat/try-it Phase 4)_

SSR (public), the SEO surface. Sections top-to-bottom:

1. **Header** — display name; publisher + badge; `deploymentVersion` +
   "updated {date}"; rating; usage signal; category/tags; jurisdiction +
   license chips.
2. **Intended use** — `metadata.description` verbatim (the authored contract).
3. **Functions & MCP tools** — rendered from ONE fetch to
   `skills.legalese.cloud/{org}/{dep}` (`{ hash, files }` incl.
   `references/schemas.json`). Never re-derived. Collapsible per-function
   schema tables.
4. **Source** — file list + read-only viewer (files come from the same
   registry fetch; `l4:read` is in the marketplace grant — auditable rules
   are the product). Deep-linkable per file.
5. **Install** — per-harness tabs driven by the existing `HARNESSES` list:
   Claude Code (`/plugin marketplace add skills.legalese.cloud/marketplace.git`),
   ChatGPT / Gemini / Claude.ai (MCP connector URL
   `mcp.legalese.cloud/{org}/{dep}` — self-configures via RFC 9728 + `/auth.md`),
   REST (`api.legalese.cloud/{org}/{dep}/openapi.json`). Every copy/click
   POSTs `/api/skills/{org}/{dep}/install`.
6. **Try it** _(Phase 4)_ — OpenAPI-driven form; calls go browser →
   `api.legalese.cloud` with the viewer's own bearer (account mode) or
   anonymously (public mode). The site is not in the data path.
7. **Chat** _(Phase 4)_ — embedded `legalese-comply-4` chat via
   `POST /api/skills/{org}/{dep}/chat` (SSE proxy, `maxDuration: 300`).
8. **Reviews** — list + "write a review" (gated: signed in AND caller org has
   verified usage §6).
9. **Disclaimer** — mandatory, non-editable, every listing.
10. **Report** — low-key link → `/api/.../report`.

Access-mode banner: `public` skills show "No account needed"; `account` skills
show "Requires a free Legalese Cloud account".

### `/search?q=` _(Phase 2)_

Full-text over display name, summary, function names/descriptions
(`tsvector`, §6 of the main spec). Same cards as home. Category & sort
facets (`relevance | rating | usage | recent`).

### `/publishers/{org}` _(Phase 2)_

Publisher profile: display name, badge, verified domains, published skills.

### `/publish` — publisher onboarding _(Phase 1, minimal)_

Not the publish flow itself (that lives in VS Code / the API) — a marketing +
docs page: what publishing means (what becomes visible, incl. source), access
modes, caps, review process, terms. Links to the VS Code flow.

### `/me` — dashboard _(Phase 2)_

Signed-in publisher view: their skills with state
(`live | pending review | suspended`), install/usage counts, review inbox.
Data: `GET /api/me/skills`.

### `/admin` — moderation _(Phase 1, staff only)_

Server-checked: the bearer must resolve to the `legalese` org with `l4:admin`
(the page just forwards it; `legalese.cloud/marketplace/admin/*` is the
enforcement). Three panels:

1. **Review queue** — orgs with `pending` intents (from
   `GET /marketplace/admin/state`): org, skills, links to detail-preview.
   Actions: **Trust org** / **Block org** → `POST /marketplace/admin/trust`.
2. **Suspensions** — suspend/unsuspend a single skill →
   `POST /marketplace/admin/suspend`.
3. **Reports** _(Phase 3)_ — open reports queue with resolve/suspend actions.

Every action forwards the staff member's own bearer per request — the site
holds nothing.

### `/terms/publisher` — publisher agreement _(Phase 1)_

Versioned static page; the version string is what `termsVersion` on publish
refers to and what `terms_accept` rows record.

---

## 3. API routes (Next route handlers)

Conventions: JSON; errors `{ error }`; `session` = forwarded bearer required;
paged responses `{ data, cursor }`. The site's DB is the **listing/social**
layer — EFS (via the platform endpoints) remains authoritative for access
(§4.2 of the main spec).

### Catalog & listings

| Route                                         | Auth   | Phase | Function                                                                                                                                                                 |
| --------------------------------------------- | ------ | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `GET /api/catalog?q=&category=&sort=&cursor=` | public | 2     | Browse/search `skills` joined with the access tables — approved ⇔ intent ∧ trusted ∧ ¬suspended, `mode ∈ (account, public)` (derived, never stored §12.2); returns cards |
| `GET /api/skills/{org}/{dep}`                 | public | 2     | Listing row + registry payload (`hash`, files) fetched server-side from `skills.legalese.cloud` with 60s cache; 404 unless approved                                      |
| `GET /api/skills/{org}/{dep}/reviews?cursor=` | public | 3     | Paged reviews                                                                                                                                                            |
| `GET /api/publishers/{org}`                   | public | 2     | Publisher profile + their approved skills                                                                                                                                |

### Publishing (single transaction at the platform, §4.2)

| Route                                    | Auth                           | Phase | Function                                                                                                                                                                                                                                                                                                                                                                                  |
| ---------------------------------------- | ------------------------------ | ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `POST /api/skills/{org}/{dep}/publish`   | session (`l4:deploy` at {org}) | 1     | forward bearer → `POST legalese.cloud/marketplace/publish?org={org}` — auth-proxy authorizes and writes ONE transaction (`marketplace_access` + `skills` skeleton + `skill_pricing_history` + `terms_accept`). This route then only UPDATEs the site-owned listing-metadata columns (display name, category, tags, …) from the body. No mirror, no second phase, nothing to fail half-way |
| `POST /api/skills/{org}/{dep}/unpublish` | session                        | 1     | forward → `/marketplace/unpublish` (deletes the intent row, stamps `unpublished_at`); listing 404s by derivation                                                                                                                                                                                                                                                                          |
| `GET /api/me/skills`                     | session                        | 2     | The caller's org's skills with derived state + counters                                                                                                                                                                                                                                                                                                                                   |

Body of publish (from the VS Code flow or a future web flow):

```jsonc
{
  "mode": "account" | "public",          // "unlisted" accepted, never listed
  "termsVersion": "2026-08",
  "listing": {
    "displayName": "...", "summary": "...", "category": "...",
    "tags": ["..."], "license": "...", "jurisdiction": "...",
    "supportUrl": "https://..."
  }
}
```

### Social & funnel

| Route                                    | Auth    | Phase | Function                                                                                                                 |
| ---------------------------------------- | ------- | ----- | ------------------------------------------------------------------------------------------------------------------------ |
| `POST /api/skills/{org}/{dep}/install`   | session | 3     | Insert `installs` (idempotent per user+harness); returns config snippets. Funnel signal only — never gates anything      |
| `PUT /api/skills/{org}/{dep}/reviews/me` | session | 3     | Upsert review; gate: caller org has rows in `skill_usage_daily` for this skill; update `rating_avg/count` in the same tx |
| `POST /api/skills/{org}/{dep}/report`    | session | 3     | Insert `reports` row (`state='open'`)                                                                                    |

### Moderation (thin forwarders — enforcement is auth-proxy's)

| Route                     | Auth            | Phase | Function                                                                                                                                            |
| ------------------------- | --------------- | ----- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET /api/admin/state`    | session (staff) | 1     | forward → `GET /marketplace/admin/state`; merge with `reports` counts                                                                               |
| `POST /api/admin/trust`   | session (staff) | 1     | forward → `/marketplace/admin/trust` (writes `publisher_trust`; every derived state flips with it — nothing to mirror) + `revalidateTag('catalog')` |
| `POST /api/admin/suspend` | session (staff) | 1     | forward → `/marketplace/admin/suspend` (writes `suspensions`) + `revalidateTag`                                                                     |

### Chat proxy _(Phase 4)_

| Route                               | Auth    | Phase | Function                                                                                                                                                                                                                                                                                                                                                                                                           |
| ----------------------------------- | ------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `POST /api/skills/{org}/{dep}/chat` | session | 4     | SSE proxy → `ai.legalese.cloud/{org}/{dep}/v1/chat/completions` with the viewer's bearer; `maxDuration: 300` (Fluid allows 800s standard on Pro). **Cost note, revised 2026-08:** under Fluid's active-CPU billing, an SSE proxy is ~all I/O wait, so the proxy-cost concern that motivated the direct-stream JWT escape hatch (main spec §9) is largely moot — keep the hatch documented, expect never to need it |

---

## 3b. Uploaded skills (non-cloud) — requirement, Phase 2+

Provable is not only a storefront for Legalese Cloud deployments: it also
hosts **ordinary agent skills uploaded directly** (SKILL.md bundles, as on
other skill marketplaces). Design constraints, captured 2026-08-05:

- **Two skill kinds, one catalog.** `skills.source_type:
'legalese-cloud' | 'upload'` (Phase 2 migration). Cloud skills derive
  callability from the access tables as today; uploaded skills are
  install-only artifacts — no cross-org auth, no evaluation endpoints, no
  entry in `marketplace_access`. Their published state derives from the
  skills row + `publisher_trust` + `suspensions` (same review/trust/
  suspension model, same one-review-per-publisher gate).
- **Content storage:** uploaded bundle files in a `skill_files` table
  (path, content, sha256 per file; bundle-level content hash on the skills
  row for versioning/tripwire parity with `computeSkillHash`). Size-capped
  (e.g. 512 KB/bundle); SKILL.md required; no executables.
- **Upload flow lives on the site** (unlike cloud publishing, which starts
  in VS Code): a publisher dashboard form — upload, listing metadata, same
  publisher terms version. Same `terms_accept` recording.
- **Detail page** renders SKILL.md + file viewer; install tab offers the
  bundle download + per-harness instructions (no MCP/OpenAPI/chat sections).
- **Reviews/installs/reports** apply to both kinds; the usage-verified
  review gate applies only to cloud skills (uploads have no logged usage —
  their reviews gate on recorded installs instead, explicitly weaker).

## 3c. The Briefcase (added 2026-08-05)

Any signed-in account has a **briefcase** — the personal collection of
skills their AI agents should have:

- **Own-org skills are included implicitly** (all of them, even unlisted or
  pending — they're yours), each individually **muteable** via
  `briefcase_exclusions`. Other publishers' listed skills are added
  explicitly from their listings (`briefcase` table).
- `/briefcase` renders the collection and a **combined agent config**: one
  `.mcp.json` block covering every unmuted cloud skill (paste into Claude
  Code/Cursor; per-URL connectors for ChatGPT/Claude.ai/Gemini).
  Account-mode skills authenticate with the viewer's Legalese Cloud account
  on first use.
- **Platform follow-up (specced, not built): the personalised marketplace
  feed.** `skills.legalese.cloud/briefcase.git` — a per-user Claude Code
  marketplace repo built from the briefcase (authproxy already has SELECT on
  `briefcase`/`briefcase_exclusions`), gated by the same Basic→API-key
  smart-HTTP auth as skill repos. "Add the plugin marketplace once; your
  agents get exactly your briefcase."

All three jobs are daily, which fits every Vercel plan (since 2026-01: 100
cron jobs/project on all plans; Hobby's floor is once per day with
within-the-hour precision, UTC; Pro gives per-minute precision). Cron entries
live in `vercel.json` and ship with the deploy.

| Job           | Cadence | Phase | Function                                                                                                                                                                                                              |
| ------------- | ------- | ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Registry sync | daily   | 2     | For each approved skill: fetch `skills.legalese.cloud/{org}/{dep}`, compare `hash` vs latest `skill_versions`; on change insert a version row; **hash change + open report → moderation queue item** (§12.3 tripwire) |
| Usage sync    | nightly | 3     | Upsert `skill_usage_daily` from the billing Lambda's output (S3/shared location TBD with Phase 5's `revshare_ledger`)                                                                                                 |

(No reconciler: eliminated by the single-record architecture — main spec
§12.4. The registry sync above is a content-drift tripwire, not a
consistency mechanism.)

Cron credentials: with the reconciler gone, the jobs need **no Legalese Cloud
credential at all** — the registry sync fetches published skills' registry
payloads, which are readable without auth by definition of being published,
and the DB writes use the site's own `provable_site` role. (If the usage-sync
handoff ends up being S3, that job gets a narrowly-scoped AWS key then —
decide in Phase 3.)

---

## 5. Database

Schema exactly as main spec §5.2 (access tables) + §6 (listing/social);
Drizzle migrations live in this repo, but the access tables and DB roles are
provisioned in Phase 1a (auth-proxy side) before this repo exists — this
repo's first migration asserts them rather than creating them. Phase 1b adds
`publishers`, `skills` listing columns, `skill_versions`, `terms_accept`,
`skill_pricing_history`; Phase 3 adds `reviews`, `installs`, `reports`;
Phase 3+ `skill_usage_daily`; Phase 5 `revshare_ledger`.

Roles: `authproxy` (full on access tables + publish-touched tables),
`provable_site` (read everything; write only listing/social), `lambda_ro`
(read-only, attribution cron).

---

## 6. Build order inside this repo

1. **Scaffold** — Next + Drizzle + Neon; auth helper (`getBearer(req)`,
   `requireStaff(req)`); Phase 1 tables.
2. **Publish/unpublish + terms page** — unblocks the VS Code flow
   (VSCODE-PUBLISH-SPEC.md) end-to-end.
3. **`/admin`** — replaces the SSM bootstrap for trust/suspend with a real
   UI; validation of the admin endpoints follows.
4. **Catalog + detail + search + publisher pages** (Phase 2) — the storefront.
5. **Install/review/report** (Phase 3), **try-it/chat** (Phase 4).
