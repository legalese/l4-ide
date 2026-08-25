# Provable — AI Legal Skill Marketplace

Architecture spec for **Provable**, a marketplace where organisations publish
their deployed L4 rule bundles as installable AI agent skills, and others
browse, install, rate, and call them from ChatGPT / Claude / Gemini / their own
agents.

**Status:** approved. **Phase 0 + the `/marketplace/*` platform endpoints are
deployed and validated end-to-end** (`validation/tests/16-marketplace.test.ts`,
6/6 against prod); eight skills are live (7 public + 1 unlisted partner
share). The `return_to` fix (§5.8) is deployed.

**Architecture revision (2026-08-05): single system of record.** The
shipped v1 stores access state in EFS files (org `.marketplace` blocks + a
platform trust file) with Postgres as a mirror — which forces mirror columns,
a reconciler, and two-phase writes. Revised target: **one Postgres (Neon,
AWS us-west-2) holds ALL marketplace state** — access intent, trust,
suspensions, listings, social — and the proxies serve access decisions from
an **in-memory snapshot** of the (tiny) access tables, refreshed every
~15–30s. Zero I/O per request; a DB outage freezes updates, never serving.
EFS keeps what is org-billing/runtime-shaped (plan config incl.
`crossOrgDailyLimit`, deployment stores, JSONL logs). §4.2, §5.2–§5.3, §5.6,
§12 are written against the revised architecture; the v1 EFS implementation
is refactored to it in Phase 1a (§13). Datastore decision notes (why Neon,
not RDS/Redis): PROVABLE-SITE-SPEC.md §1.
**Refined implementation specs:** [PROVABLE-SITE-SPEC.md](PROVABLE-SITE-SPEC.md)
(the `provable` repo — pages, API routes, jobs) and
[VSCODE-PUBLISH-SPEC.md](VSCODE-PUBLISH-SPEC.md) (sidebar publish flow, RPC,
undeploy warning).
**Scope:** spans five repos — `jl4-auth-proxy`, `ai-proxy`, `l4-ide`
(extension + webview + shared RPC), a **new `provable` repo**, and
`legalese.github.io` (redirect only).
**Audience:** an implementer familiar with the Legalese Cloud request path
(WorkOS auth → auth proxy → per-org `jl4-service`) and with Next.js/Postgres.

**Background reading:** `jl4-auth-proxy/ARCHITECTURE.md` §"Auth & Permission
Model", §"URL Scheme", §"Per-Org Configuration", §"Billing";
`ai-proxy/ARCHITECTURE.md` §"Pipelines, not a single provider chain".

---

## 1. Problem statement

Legalese Cloud already generates, for every deployment, a complete installable
agent skill — `SKILL.md`, `references/schemas.json`, `.mcp.json` — deterministically
templated from the deployment's stored metadata, with OAuth-capable MCP
endpoints, an OpenAPI spec, and a git-cloneable plugin repo. All of it is
**invisible to anyone outside the owning organisation.**

Three gaps stand between that and a marketplace:

1. **Cross-org access is structurally forbidden.** Both proxies assert
   _caller's org == target org_. A user at org B cannot install, call, or chat
   with org A's skill. Today this is not a policy but an invariant of the auth
   path.
2. **There is no discovery surface.** The skills registry (`skills.legalese.cloud`)
   returns **404** without auth, deliberately — its own docs call public access
   "a later, cross-service concern". This is that later.
3. **There is no attribution.** Request logs are keyed by a single org. Without
   knowing _who called_ a _whose_ skill, per-install pricing and revenue share
   are not merely unbuilt — they are unbackfillable.

Provable closes all three. It is deliberately thin: the skill artifacts already
exist and are already correct. What is missing is an access mode, an
attribution field, and a website.

---

## 2. Current state (verified)

Facts established by reading the repos, with file references. Everything in
this section is **already true** — no work implied.

### 2.1 Skill artifacts

`jl4-auth-proxy/src/skill-bundle.ts` (997 lines) is a pure, deterministic
generator — **no LLM step**. Seeded by the deployment's operator-supplied
"Intended use" (`metadata.description`), which is load-bearing: empty
description → 422 at the route layer, and the deployment is excluded from
listing, search, and the well-known index.

| Function                                           | Produces                                                                   |
| -------------------------------------------------- | -------------------------------------------------------------------------- |
| `buildSkillFiles`                                  | flat skills.sh layout: `SKILL.md`, `references/schemas.json`, `.mcp.json`  |
| `buildPluginRepoFiles`                             | Claude Code plugin layout: `.claude-plugin/plugin.json`, `skills/{name}/…` |
| `buildSkillDetail`                                 | skills.sh detail response `{ id, source, slug, hash, files }`              |
| `buildWellKnownIndex`                              | agentskills.io 0.2.0 discovery index with sha256 digests                   |
| `buildMarketplaceJson` / `buildGatewayMarketplace` | Claude Code marketplace manifests                                          |
| `computeSkillHash`                                 | stable content hash; identical redeploy → same hash → same git SHA         |

Served on `skills.legalese.cloud` (registry + smart-HTTP git repos) and
`mcp.legalese.cloud/{slug}/{id}/.plugin` (zip, what the VS Code extension
downloads).

> **Note:** `plugin.legalese.cloud` does not exist. The hosts are
> `skills.` (registry/git), `mcp.` (MCP + `.plugin` zip), `api.` (REST +
> OpenAPI), `ai.` (chat).

### 2.2 Auth

WorkOS AuthKit via `legalese.cloud/auth/*`. Browser clients
(`legalese.com/console`, `chat.legalese.cloud`) all use the same pattern:
login redirect → `?token=` → sealed session in `localStorage['wos-session-token']`
→ `Authorization: Bearer` on every call. Cross-domain cookies between
`legalese.com` and `legalese.cloud` are unreliable, so Bearer is the only
signal. See `legalese.github.io/src/app/console/console-shell.tsx` and
`console-utils.tsx::authHeaders()`; `/compare` already reuses it against
`ai.legalese.cloud`.

Permissions: `l4:deploy`, `l4:evaluate`, `l4:rules`, `l4:read`, `l4:admin`.

### 2.3 Org config is read fresh, uncached, per request

`ConfigStore.getOrgConfig()` is `existsSync` + `readFileSync` + `JSON.parse`
on `/efs/config/orgs/{slug}.json` — **no cache, no SIGHUP required**
(`jl4-auth-proxy/src/config/store.ts:45-56`). A write to that file takes effect
fleet-wide immediately. This is what makes publish-as-a-config-write viable.

Warm-path reads on a normal deployment request (process already running):

| #   | Call site                                            | When                                                       |
| --- | ---------------------------------------------------- | ---------------------------------------------------------- |
| 1   | `src/auth/middleware.ts:422` `isDeploymentPublic()`  | every request carrying a `deploymentId`                    |
| 2   | `src/billing/meter.ts:35` via `meterBillableRequest` | every billable request                                     |
| —   | `src/router.ts:60`                                   | **0** — `resolve()` early-returns when the process is warm |

Read #1 sits **above** `cacheGet`, so an auth-cache hit does not avoid it.
`ai-proxy` independently reads the same files fresh per request for its `.ai`
block.

Today most orgs have no override file, so both are a cheap `existsSync` miss
(a `stat`, usually served by NFS attribute cache, `acregmin` 3s). **Publishing
gives an org an override file**, moving it to read + parse — see §5.3.

### 2.4 `publicDeployments` is dead code

It has **no writer anywhere**: not in the console, not in the extension, not in
any API, not in the Stripe webhook. Readers only:

- `src/config/types.ts:34,76` — type + default
- `src/config/store.ts:20,119` — `JL4_RUNTIME_KEYS` + `isDeploymentPublic()`
- `src/auth/middleware.ts:419-434` — anonymous bypass for deployment-scoped
  data-plane routes (including MCP and OpenAPI)
- `src/admin/routes.ts:64` — pass-through in `/service/health`
- `runbooks/org-config.md:97` — a manual `jq` recipe

It is a historic artifact. **Delete it** (§5.1).

### 2.5 Metering

`meterBillableRequest(dailyCounter, config, orgId)` takes **one** org: it
increments that org's daily counter and blocks over the limit. Billable routes
are listed in `src/billing/billable.ts`. Request logs are JSONL at
`/efs/logs/{orgSlug}/{date}-{instance}.jsonl`, swept nightly by a Lambda that
classifies each entry into a billing **source** (`jl4-service`, `ai-chat`) and
reports metrics to Stripe meters.

### 2.6 AI chat

`ai.legalese.cloud/{orgSlug}/{deploymentId}/v1` forces the `legalese-comply-4`
comply pipeline, with tools built from that deployment's MCP `tools/list`
(`ai-proxy/src/tools/comply.ts`). `ai-proxy/src/auth.ts:216,273` rejects a
bearer whose org ≠ the URL slug.

### 2.7 VS Code deployment row

`ts-apps/webview/src/routes/sidebar/+page.svelte:2465-2549` renders
`Chat` · `Integrate` · `⋯` (Download, Undeploy). The Integrate pop-over is
`ts-apps/webview/src/lib/components/deployment-integrate-popover.svelte`.
RPC lives in `ts-shared/jl4-client-rpc/vscode-and-webview-messages.ts`.
Undeploy confirmation reuses the `.breaking-warning` full-tab view
(`+page.svelte:2321-2340`).

### 2.8 Deployment metadata has no marketplace fields

`DeploymentMetadata` (`jl4-service/src/Types.hs:98-121`) is exactly:
`functions`, `files`, `version` (source sha256), `createdAt`, `description`,
`serviceVersion`, `deploymentVersion`. No author, display name, category, tags,
license, jurisdiction, pricing, icon. Those belong in the registry database —
keeping `metadata-cache.json` deterministic is what makes skill hashes stable.

---

## 3. Access model

Two settings, expressed as **one field**. Presence in the map means published;
the value's `mode` is the access mode; absence means private.

| Mode                                              | Who can call                                       | Caller identity available | Listed on Provable |
| ------------------------------------------------- | -------------------------------------------------- | ------------------------- | ------------------ |
| **private** (absent — default, today's behaviour) | own org only                                       | yes (= publisher)         | no                 |
| **`account`**                                     | any authenticated Legalese Cloud identity, any org | **yes**                   | yes                |
| **`public`**                                      | anyone, no account                                 | **no**                    | yes                |

Plus **`unlisted`** — cross-org accessible, not listed. Authorisation-identical
to `account`, excluded from the Provable catalog query, with one optional
extra: an `allowedOrgs` list on the access object (§5.2) restricts callers to
named orgs — true partner sharing. Without the list, unlisted means only "not
in the catalog": any authenticated account that knows the URL can call it, and
deployment IDs are guessable slugs, so never describe list-less unlisted as
private. **Implement the mechanism in Phase 0** (the enum value and the
`allowedOrgs` check cost essentially nothing once the branch exists) and defer
the publish-dialog UI until a partner actually asks. Building it later would
mean touching the auth path again for no reason.

**This table says nothing about who pays.** Access mode is an authorisation
concept. Who is invoiced for a given request is an attribution _policy_, applied
after the fact by the billing cron (§5.5.3) and expected to change. The only
thing the access mode determines is whether a caller identity exists to
attribute _to_.

### 3.1 What a marketplace caller is granted

Every cross-org and anonymous call carries one **fixed grant**:

```ts
const MARKETPLACE_GRANT = ["l4:rules", "l4:evaluate", "l4:read"];
```

- **Never derived from the caller.** The caller's home-org permissions are
  consulted for _identity only_ (who is calling); the grant is a constant. A
  caller holding `l4:admin` at their own org gets exactly `MARKETPLACE_GRANT`
  at the publisher's — never `l4:deploy`, `l4:admin`, or anything org-scoped.
- **`l4:read` is included deliberately: published source is readable.** Anyone
  who can call a published skill can read its `.l4` files (the files route and
  the MCP file tools). Auditable rules are part of the product, and the
  publish dialog says so plainly (§8.2).
- **Deployment-scoped structurally.** Marketplace auth results carry
  `scope: { deploymentId }`; the router rejects any request whose
  `route.deploymentId` differs or is absent. Non-deployment routes (the
  deployments list, service logs, billing, admin) are unreachable by
  construction — the grant branch requires a published `deploymentId`, and
  the scope check enforces it independently.
- **Future configurability is shaped now, built later.** The decision function
  (§5.4) takes the grant table as a parameter defaulting to this constant.
  When per-deployment / per-audience rights ship, they are _authored_ in Neon
  (publisher edits audience → rights in the Provable UI) but _served_ from an
  optional `grants` key on the publisher's own EFS access object (§5.2),
  written by the publish endpoint — Postgres authors, EFS serves, and the
  request path never reads Neon (§4.2). That covers the whole spectrum:
  public → all accounts → specific orgs → private, where private stays what
  it is today: the org's own user/key permission configuration, no entry in
  the map at all.

### 3.2 Why the modes are shaped this way

- **Revenue share becomes possible at all.** `account`-mode calls carry a caller
  org identity through to the log, which is the precondition for attributing
  anything to anyone. `public` mode structurally cannot — there is no caller to
  identify — which is the real reason it is a distinct mode rather than a
  looser variant of `account`.
- **Quota-DoS is contained.** A stranger hammering an `account`-mode skill is
  visible as an identified caller and can be rate-limited as one (§5.5.2).
  `public` is different by choice: it is **not cross-org** — requests to a
  public deployment meter as the publisher's own traffic, against the
  publisher's own `dailyRequestLimit` (plus the WAF's per-IP limit), exactly
  like the old public path. Choosing public mode is choosing to spend your own
  quota on strangers.
- **`public` is a genuinely different risk posture** — anonymous evaluation on
  your compute, with no attribution possible. It gets its own step and its own
  warning in the publish dialog, never a dropdown next to "category".

### 3.3 Revocation is a single row in the one record

A skill is callable cross-org iff **all four** hold, each failing closed:

```
intent row exists         (marketplace_access — written only via /marketplace/publish, §5.2)
∧ publisher trusted       (publisher_trust — platform scope, §12.2)
∧ skill not suspended     (suspensions — platform scope)
∧ org not billing-suspended  (org config on EFS — the one non-DB input, §5.3)
```

Because there is exactly one record, a takedown, suspension, or unpublish is
**one transaction** — delete the intent row, or flip the trust/suspension
row — and there is no second copy that can disagree, no cosmetic delist, no
reconciler. The catalog and the auth path read the same tables; "removed from
the marketplace" and "not callable" are the same fact.

**Propagation SLA:** revocation takes effect within **~60 seconds** worst
case — the proxies' snapshot refresh (~15–30s, §5.3) + the 30s marketplace
grant cache TTL (§5.4). Accepted for all moderation actions. Emergency
hard-stop for active abuse: SIGHUP forces an immediate snapshot refresh and
clears grant caches — runbook material, nothing to build.

---

## 4. Topology

| Component                     | Where                           | Owns                                                                                                                                                                 |
| ----------------------------- | ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`provable`** (new repo)     | Vercel, `provable.legalese.com` | Next.js App Router, SSR. Browse, skill pages, reviews, install flow, chat proxy. Registry API as route handlers.                                                     |
| **Neon Postgres** (us-west-2) | Vercel Marketplace integration  | **The one system of record**: access intent + trust + suspensions (§5.2) AND listings, reviews, installs, terms acceptances, reports, rev-share ledger               |
| **`jl4-auth-proxy`**          | existing EC2                    | **Enforces access control** — snapshot reader over the access tables (§5.3); cross-org auth; metering; the only writer of access state (`POST /marketplace/*`, §4.2) |
| **`ai-proxy`**                | existing Fargate                | Cross-org comply chat                                                                                                                                                |
| **`l4-ide`**                  | extension                       | Publish UI                                                                                                                                                           |
| **`legalese.github.io`**      | GitHub Pages                    | `legalese.com/provable` → redirect to `provable.legalese.com` (§4.4)                                                                                                 |

### 4.1 Why a separate origin, and why that is an upgrade

`localStorage` is per-origin, so `provable.legalese.com` does **not** inherit
the console's session token. With SSR that is a feature, not a workaround: do
the AuthKit round-trip
(`legalese.cloud/auth/login?return_to=https://provable.legalese.com/auth/callback`),
then set Provable's **own httpOnly, Secure, SameSite=Lax cookie** holding the
sealed session. Server components read it directly. No token in JS, no token in
a URL bar.

### 4.2 One system of record, write access split by endpoint scope

**One Postgres (Neon, AWS us-west-2) holds all marketplace state** — access
intent, publisher trust, suspensions, listings, social. What used to be a
file-ownership split becomes an **endpoint + DB-role split**; no writer ever
touches another owner's scope, and no state is ever mirrored:

| Writer                                   | Path                                                 | May write                                                                                                                                                                      |
| ---------------------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| the org itself (own bearer, `l4:deploy`) | `POST legalese.cloud/marketplace/publish\|unpublish` | its own `marketplace_access` rows (+ skeleton `skills` row, `terms_accept`, `skill_pricing_history`)                                                                           |
| the platform (legalese-org `l4:admin`)   | `POST legalese.cloud/marketplace/admin/*`            | `publisher_trust`, `suspensions`                                                                                                                                               |
| the Provable site (its own DB role)      | direct SQL                                           | listing-metadata columns on `skills`, social tables (`reviews`, `installs`, `reports`) — its role has **no grant** on `marketplace_access` / `publisher_trust` / `suspensions` |

`jl4-auth-proxy` never takes a per-request dependency on the database: the
request path reads an in-memory snapshot (§5.3). The write path (publish,
moderation) does depend on the DB — publishes pause during a DB outage,
serving does not.

Publish is **one transaction**, not two phases:

```
VS Code / website
   └─ POST provable.legalese.com/api/skills/{org}/{dep}/publish   (user's bearer)
        └─ forward bearer → POST legalese.cloud/marketplace/publish
             auth-proxy validates l4:deploy itself, then in ONE tx:
             upsert marketplace_access + skills skeleton,
             insert skill_pricing_history + terms_accept
```

Provable **never holds elevated credentials** — it forwards the user's own
token and auth-proxy does its own authorisation. There is **no special case
for first publish**: the intent row always lands, and an unreviewed org's
intent is inert until the platform trust row flips (§12.2) — `pending` is a
`WHERE`, not a workflow. No reconciler exists because there is nothing to
reconcile (§12.4).

### 4.3 CORS

Server-to-server calls from Vercel do not hit browser CORS. Proxy the chat SSE
stream through a Next route handler so the browser never sees a Legalese Cloud
token. `ALLOWED_ORIGINS` in auth-proxy needs `https://provable.legalese.com`
only for any cookie-authenticated browser call — prefer to have none.

### 4.4 `legalese.com/provable`

Keep the originally-intended URL alive as a redirect. Note it cannot be a true
301: `legalese.github.io` is `output: "export"` on GitHub Pages, which serves no
redirect rules, and Next's `redirects()` is unavailable in export mode. Ship a
static `src/app/provable/page.tsx` carrying
`<link rel="canonical" href="https://provable.legalese.com">`, a
`<meta http-equiv="refresh">`, and a `location.replace()` fallback.

If `legalese.com` ever moves behind CloudFront (a second origin alongside GitHub
Pages), promote this to a real 301 at the edge.

---

## 5. jl4-auth-proxy changes (Phase 0)

### 5.1 Remove `publicDeployments`

Delete `isDeploymentPublic()`, the `JL4_RUNTIME_KEYS` entry, the type + default,
the `/service/health` pass-through, the `middleware.ts:419-434` bypass block,
and the runbook recipe. Update `ARCHITECTURE.md` §"Public Access".

**Migration check before deleting the read path:** grep live
`/efs/config/orgs/*.json` for any hand-set `publicDeployments` values. Expected
result is none; if any exist, translate them to `mode: "public"` intents.
(Done 2026-08-04: live grep found none; only a stale empty default in
`defaults.json`.)

### 5.2 Access-control tables (and what stays in org config)

Access state lives in three small Postgres tables, written only through the
scoped endpoints (§4.2):

```sql
marketplace_access      -- publisher intent; writer: /marketplace/publish|unpublish
  org_slug, deployment_id  PK,
  mode            -- 'account' | 'public' | 'unlisted'
  allowed_orgs    text[] NULL,   -- partner restriction (§3); NULL = no restriction
  terms_version, published_at, updated_at
  -- future: grants jsonb (audience → permission list, §3.1)

publisher_trust         -- platform scope; writer: /marketplace/admin/trust
  org_slug PK, state    -- 'trusted' | 'blocked'; ABSENT ROW = unreviewed
  , updated_at

suspensions             -- platform scope; writer: /marketplace/admin/suspend
  org_slug, deployment_id PK, created_at
```

Every table carries `updated_at` so the proxies' snapshot refresh (§5.3) can
be an incremental `WHERE updated_at > $last` (deletes handled by a
row-version/tombstone or full reload — the tables are small enough that full
reload every cycle is also fine).

**Caps stay in org config on EFS.** `crossOrgDailyLimit` is org-billing
machinery, not marketplace state: the free-tier default lives in
`defaults.json`'s `.marketplace` block, org overrides in the org's own file,
and **every paid plan template's `configPatch` sets
`marketplace.crossOrgDailyLimit: 0` (unlimited)** — upgrading removes the cap
through the existing Stripe-webhook deep-merge, no new code path. Caps are
deliberately **org-level, not per-deployment**: one number a publisher can
reason about; a noisy public skill starving the org's other public skills is
the publisher's own portfolio to manage. The clean line: _who may call what =
Postgres; org resources and billing = EFS files._ (0 = unlimited follows
`dailyRequestLimit`'s existing convention.)

### 5.3 The snapshot reader

`MarketplaceStore` becomes a **replicated in-memory snapshot** of the three
access tables, not a per-request accessor:

- Load everything at boot (the dataset is one row per published skill + one
  per reviewed publisher — kilobytes now, megabytes at implausible scale);
  refresh on a ~15–30s timer with one cheap query; SIGHUP forces a refresh.
- `getDeploymentAccess(orgSlug, deploymentId)` evaluates the §3.3 predicate
  against the snapshot plus the one non-DB input, the org's billing
  `suspended` flag from `getOrgConfig()` (already EFS-read on the request
  path today). `getDeploymentIntent` reads the same snapshot without the
  trust check (publisher tooling, VSCODE-PUBLISH-SPEC.md §4).
- **Per-request marketplace auth costs zero I/O** — strictly cheaper than
  the v1 mtime-cached file reads, and cheaper than today's pre-marketplace
  `existsSync` probes. A database outage freezes snapshot updates but never
  serving: last-known-good keeps answering, unknown deployments fail closed,
  and same-org auth has no marketplace dependency at all.
- ai-proxy runs the same snapshot module (same verbatim-copy + shared-
  fixture discipline as `marketplace-access`); both proxies need a
  `DATABASE_URL` (read-only role).

### 5.4 Cross-org authorisation

The access _policy_ is a pure function, shared between the proxies so they
cannot drift (built: `jl4-auth-proxy/src/marketplace-access/`):

```ts
// marketplace-access — no I/O, no WorkOS, no fs, no repo-internal imports
decideAccess(input: {
  sameOrg: boolean;
  access: MarketplaceAccess | null;   // trust-checked, from getDeploymentAccess (§5.3)
  hasCredential: boolean;
  callerOrg: string | null;
}, grant = MARKETPLACE_GRANT)
  : { allow: false; reason: DenyReason } | { allow: true; grant: string[]; callerType: CallerType }
```

Each proxy keeps its own auth _plumbing_ (token validation, caching) and calls
this for the decision. Sharing mechanism: ai-proxy carries a **verbatim copy**
of `index.ts` plus the shared fixture table (`cases.json`, stamped with
`MARKETPLACE_ACCESS_VERSION`), and both CIs run every fixture — a policy
change that lands in one repo fails the other's build when fixtures sync.
(Chosen over an npm workspace package: both are single-package repos with
rsync'd deploys; the fixture table, not the module system, is what actually
prevents drift.) Policy details fixed by the fixtures: `allowedOrgs`
restricts every mode it appears on, an empty list admits nobody, and an
identified caller on a `public` deployment decides as `cross-org` while
metering stays publisher-side (§5.5.2).

`src/auth/middleware.ts` runs today's same-org path first — the publisher's
own traffic to its own deployments keeps full permissions, untouched. Only on
`org-mismatch` (valid credential, different org) or `no-credentials` does it
consult `getDeploymentAccess`:

- credentialed caller from another org **and** mode ∈ {`account`, `unlisted`}
  (and, when `allowedOrgs` is set, caller's org is in it) → allow with
  `MARKETPLACE_GRANT`, `authMethod: "cross-org"`, `callerOrg` recorded,
  `scope: { deploymentId }`.
- no credential **and** mode `public` → allow with `MARKETPLACE_GRANT`,
  `authMethod: "anonymous"`, `callerOrg = null`, same `scope`.

The caller's home-org permissions are **identity only** — the grant is always
the constant (§3.1), and the router rejects any scoped result whose
`route.deploymentId` differs.

**Caching:** marketplace grants get their own map — keyed by
`(authHeader, publisherOrg, deploymentId)`, same 30s TTL and pruning as
`authCache`, whose semantics are untouched. A grant minted for deployment A
can never be replayed against deployment B or against the publisher's private
deployments. Anonymous requests are not cached (no header to key on); they
cost only an in-memory snapshot lookup (§5.3).

Mirror the same flow in `ai-proxy/src/auth.ts:216,273` via the shared package;
ai-proxy runs the same snapshot reader. `skills.legalese.cloud`'s
`authResolveOrg` gate must consult the same predicate so listings and skill
files resolve for callers outside the publisher's org.

### 5.5 Access logging, quota enforcement, and attribution

Three separate concerns. Conflating them is the mistake to avoid: **the request
log records what happened, not who pays.**

#### 5.5.1 The log records facts, with no pricing opinion

Every billable request appends a JSONL entry describing the access:

```jsonc
{
  "publisherOrg": "acme", // org owning the deployment (resource used)
  "callerOrg": "globex", // null when anonymous
  "callerType": "session", // session | api-key | agent-key | anonymous
  "accessMode": "account", // private | account | public — AS OBSERVED
  "deploymentId": "parking-rules",
  "route": "evaluation",
  "source": "marketplace",
  // ...existing fields (status, timestamp, instance, allocBytes, …)
}
```

`accessMode` is logged **as it was at request time** and must never be
re-derived later. A publisher can flip a skill from `account` to `public`, or
unpublish it outright; historic requests have to be attributed under the regime
that actually applied when they were served.

There is deliberately **no `billedOrg` field**. Adding one would freeze a
pricing decision into an append-only log at the moment we understand the pricing
least.

New billing source key `marketplace`: add to `SourceKey` / `SOURCE_KEYS`
(`src/billing/types.ts:22,25`) and its metric names to `SOURCE_METRICS`
(`src/billing/sources.ts:30`) — the three-step recipe documented at the top of
`sources.ts`.

The classifier rule ships with the key, not later: an entry is source
`marketplace` iff `callerType === "anonymous"` **or** `callerOrg` is present and
≠ `publisherOrg`. Same-org traffic keeps its existing source (`jl4-service`,
`ai-chat`) regardless of the deployment's published state. The sweep-Lambda
classifier change lands in Phase 0 alongside the fields, with a fixture file
of sample entries → expected source. A reserved key with no classifier is a
name, not a capability.

> **This is the one irreversible item.** Adding these fields later is easy;
> retro-attributing months of traffic is impossible. Ship them in Phase 0 even
> though nothing reads them until Phase 5.

#### 5.5.2 Enforcement is real-time, and is not a billing verdict

Quota checks cannot be deferred to a cron — the request either proceeds or
429s now. But _which counter_ is an operational question about protecting
compute, not a pricing one. All counters are **org-keyed** (no per-deployment
counters — caps ride the org config and plan tiers, §5.2). Identified
cross-org traffic never touches the publisher's main daily counter, so
`account`-mode strangers cannot 429 the publisher's own production
integrations. `public` mode, by contrast, is **not cross-org**: it meters as
the publisher's own traffic, exactly as the old public path did — consistent
with "public → publisher pays" (§5.5.3):

| Traffic                                    | Counter key(s)                              | Limit                                                              | Protects                                                                            |
| ------------------------------------------ | ------------------------------------------- | ------------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| same-org (today's path)                    | `{org}`                                     | `dailyRequestLimit`                                                | unchanged                                                                           |
| cross-org (`account` / `unlisted`)         | `{callerOrg}` **and** `{publisherOrg}:xorg` | caller's own `dailyRequestLimit`; publisher's `crossOrgDailyLimit` | the caller's plan; the publisher's compute                                          |
| `public` mode (with or without credential) | `{publisherOrg}`                            | `dailyRequestLimit`                                                | the publisher's own quota, spent by their own choice; the WAF's per-IP limit on top |

```ts
// before
meterBillableRequest(dailyCounter, config, orgId)

// after — reports which limit, if any, was hit; never a "billed org"
meterBillableRequest(counters, config, {
  publisherOrg,
  callerOrg,            // null when anonymous
  access,               // null | "account" | "unlisted" | "public" — as observed
}): MeterResult & { limitHit?: "org-daily" | "caller-plan" | "cross-org-cap" }
```

Any hit 429s with a message naming which limit. `DailyRequestCounter` and
`LiveCounterSync` already key by arbitrary string — the composite key reuses
them unchanged, and `refundBillableRequest` refunds exactly the keys that were
incremented. One new cap, one new key, no rename of `dailyRequestLimit`.
`public`-mode requests are never counted as cross-org: whoever the caller is,
they meter under the publisher's own counter, and the log's `callerOrg` /
`callerType` keep the facts for attribution. `crossOrgDailyLimit: 0` means
**unlimited** — the same convention `meterBillableRequest` already applies to
`dailyRequestLimit` — which is what paid plan templates set (§5.2); the cap
exists to bound free-tier orgs, not paying ones.

#### 5.5.3 Attribution is the billing cron's job

The nightly Lambda reads the raw entries and applies the attribution policy in
force **for that date**, joined against the listing's pricing timeline in
Postgres. The starting policy is expected to be:

- `private` → publisher (who is also the caller)
- `account` → caller pays for consumption; publisher earns revenue share
- `public` → publisher pays

and to change as the product does. Because the log holds facts rather than
verdicts, changing it — or correcting a past period — is a change in one place
in the cron, not a schema migration or a backfill.

Mechanics that make this safe to re-run: the Lambda gets a **read-only Neon
role** (credential in AWS Secrets Manager, TLS to Neon's public endpoint — no
peering), joins the pricing timeline from `skill_pricing_history` (§6), and
**upserts** its output into `revshare_ledger` keyed
`UNIQUE (skill_id, caller_org, date)`. Inputs are immutable logs plus an
append-only pricing history, so a failed night, a policy change, or a
past-period correction is always "rerun the dates", never a backfill. If Neon
is unreachable, the sweep skips attribution that night and re-covers unswept
dates on the next run. The same pass upserts `skill_usage_daily`, which is
what gates reviews (§6).

#### 5.5.4 Log directory

Entries stay under `/efs/logs/{publisherOrg}/` — the org whose resource was
used, which is a fact, rather than the org that will be invoiced, which is a
policy output. This is also the no-change option: logs already land in the
directory of the org whose process served the request. The cron already walks
every org directory, so a per-caller rollup is a group-by, not a new scan.

### 5.6 Publish endpoint

```
POST   legalese.cloud/marketplace/publish      l4:deploy   { deploymentId, mode, allowedOrgs?, termsVersion }
POST   legalese.cloud/marketplace/unpublish    l4:deploy   { deploymentId }
```

Validates `metadata-cache.json` exists and `description` is non-empty (the
existing 422 rule), then runs **one transaction**: upsert the org's own
`marketplace_access` row, upsert the `skills` skeleton row, insert
`skill_pricing_history` and `terms_accept`. Postgres transactions replace the
v1 file locks and two-phase ordering. The write **always happens** —
first-publish review is enforced by the `publisher_trust` row, not by
withholding the write (§4.2, §12.2). The endpoint responds with
`{ published, live }` where `live` is the trust-checked view.

(The `withFileLock` helper built for v1 stays: org config files on EFS still
have multiple writer classes — the Stripe webhook and any future org-config
endpoints — and keep needing it. It simply no longer guards marketplace
state.)

### 5.7 Reserved name

Add `provable` to `SUBDOMAIN_NOORG` in `src/routing/parse.ts` so no customer can
claim it as a slug.

### 5.8 Security fix — ship immediately, before and independent of Phase 0

`?return_to=` on `/auth/login` is base64'd into `state` and redirected to
**unvalidated** at `/auth/callback` (`src/auth/routes.ts:424-467`) — **with the
sealed session token appended as a query parameter**. That is an open redirect
that leaks credentials to any attacker-chosen host. (`/auth/redirect` _is_
validated to `*.legalese.cloud`; `/auth/callback` is not.) This is a live
credential leak with no marketplace dependency — its own PR, now, not a
Phase 0 passenger.

The fix:

- One shared `validateReturnTo(url)` used by `/auth/callback`,
  `/auth/redirect`, and the console interstitial's inner `redirect_to`.
  **Exact-host allowlist from env** (`legalese.com`, `www.legalese.com`,
  `chat.legalese.cloud`, later `provable.legalese.com`) plus suffix-match for
  org subdomains of `.legalese.cloud` only, plus scheme-exact `vscode://`
  (which already routes through the console interstitial). **No
  `*.legalese.com` wildcard** — with Vercel in the picture, a dangling
  subdomain CNAME becomes a token sink.
- Sign `state`: `base64url(payload) + "." + HMAC-SHA256(payload,
workosCookiePassword)` where the payload carries `{return_to, nonce, iat}`;
  the callback verifies the signature and `iat` < 10 minutes. Kills the open
  redirect and login CSRF with a secret the process already holds.
- The token is appended **only after** validation passes; on failure, redirect
  to `afterLoginUrl` with no token (don't 400 mid-login users).

---

## 6. Database — Neon Postgres + Drizzle (the one system of record)

One database (Neon, **AWS us-west-2**, same region as the proxy fleet)
serves both consumers: the proxies read the access tables as an in-memory
snapshot (§5.3) over TCP in-region; the Vercel site reads/writes over the
HTTP serverless driver. Preview deploys get database branches. **Rev-share
reporting is genuinely relational** — joins across installs, invocations,
publishers, and billing periods — and that is the part that matters most for
monetisation. (Datastore decision notes — why not RDS or Redis — live in
PROVABLE-SITE-SPEC.md §1.)

Access-control tables (`marketplace_access`, `publisher_trust`,
`suspensions`) are defined in §5.2 and writable ONLY through the auth-proxy's
scoped endpoints — the site's DB role has no grant on them. The listing and
social layer:

```
publishers      org_slug PK, workos_org_id, display_name,
                verified_domains[], domains_checked_at,
                stripe_connect_id, created_at
                -- NO trust_state: trust is publisher_trust (§5.2), one copy

skills          id PK, org_slug FK, deployment_id,
                display_name, summary, category, tags[], license, jurisdiction,
                support_url, pricing jsonb,
                rating_avg, rating_count, install_count,
                published_at, unpublished_at
                UNIQUE (org_slug, deployment_id)
                -- NO access_mode / moderation_state columns: mode comes from
                -- marketplace_access; approved|pending|suspended is derived
                -- by joining publisher_trust + suspensions (§12.2)
                -- Phase 2 adds source_type ('legalese-cloud' | 'upload'):
                -- Provable also hosts directly-uploaded SKILL.md bundles
                -- (install-only, no access tables) — PROVABLE-SITE-SPEC §3b

skill_versions  skill_id FK, deployment_version, skill_hash, created_at

reviews         skill_id FK, user_id, org_slug, rating, body,
                version_reviewed, created_at
                UNIQUE (skill_id, user_id)

installs        skill_id FK, user_id, org_slug, harness, created_at

terms_accept    skill_id FK, user_id, org_slug, terms_version, ip, accepted_at

reports         skill_id FK, reporter_user_id, reason, state, created_at

skill_pricing_history   skill_id FK, effective_from, pricing jsonb,
                        created_by, created_at

skill_usage_daily       skill_id FK, caller_org, date, request_count
                        UNIQUE (skill_id, caller_org, date)   -- synced from logs by the cron

revshare_ledger         skill_id FK, caller_org, date, amounts jsonb, policy_version
                        UNIQUE (skill_id, caller_org, date)   -- cron upsert, re-runnable
```

- **Pricing:** `skills.pricing` is the denormalised _current_ value; every
  publish or price change inserts a `skill_pricing_history` row in the same
  transaction. The attribution cron (§5.5.3) joins
  `effective_from ≤ request_date < next effective_from`, so historic requests
  are priced under the regime that applied — no backfill risk. Created in
  Phase 1 even though nothing reads it until Phase 5.
- **Reviews are usage-verified, not install-gated.** `installs` is
  self-reported (`POST /install` is free to call), so it gates nothing. The
  review gate is: the reviewer's org has ≥1 logged request to the skill in
  `skill_usage_daily` — unfakeable without actually calling the skill, which
  is metered and capped. `installs` stays as the UX/funnel event; the trust
  signal displayed on listings is "N orgs used this in the last 30 days", not
  raw install count.
- **Ratings:** `rating_avg` / `rating_count` materialised on `skills`, updated
  in the same transaction as the review.
- **Search:** Postgres full-text over a `tsvector` of display name, summary, and
  function names/descriptions pulled from `metadata-cache.json`. Reuse
  `deploymentSearchText` / `scoreDeployment` / `queryKeywords` from
  `skill-bundle.ts` for keyword extraction. Good well past five figures of
  skills; revisit only if that changes.

---

## 7. Registry API (Next route handlers)

```
GET    /api/catalog?q=&category=&sort=&cursor=       public    browse
GET    /api/skills/{org}/{dep}                       public    listing + generated files
POST   /api/skills/{org}/{dep}/publish               session   two-phase publish (§4.2)
POST   /api/skills/{org}/{dep}/unpublish             session   delist + revoke
GET    /api/skills/{org}/{dep}/reviews               public    paged
PUT    /api/skills/{org}/{dep}/reviews/me            session   upsert; requires verified usage (§6)
POST   /api/skills/{org}/{dep}/install               session   record install → config snippets
POST   /api/skills/{org}/{dep}/report                session   moderation flag
GET    /api/me/skills                                session   publisher dashboard
POST   /api/skills/{org}/{dep}/chat                  session   SSE proxy → ai.legalese.cloud
```

---

## 8. VS Code extension changes

### 8.1 Deployment row

`ts-apps/webview/src/routes/sidebar/+page.svelte:2465-2549`:

- Move `Integrate` into the `⋯` dropdown as the **first** item (above Download /
  Undeploy). `showMenu` becomes unconditional.
- Add `Publish` as a `deployment-text-btn` at `opacity: 0.85` instead of the
  default `0.6` — brighter, but not the crimson `#c8376a` reserved for primary
  CTAs. Once published it renders `Published ✓` linking to the listing.
- Cloud-only, same guard as `Chat` (`integrateMode === 'cloud'` and
  `connectionStatus.orgSlug` present).

### 8.2 `deployment-publish-popover.svelte`

Same shell as `deployment-integrate-popover.svelte` — absolute backdrop inside
`.tab-content-frame`, Esc handler, `stopPropagation` on the dialog. Four steps:

1. **What becomes visible.** Generated `SKILL.md`, Intended use, function names
   and `@desc`, MCP tool schemas — **and the deployment's `.l4` source files**:
   `l4:read` is part of the marketplace grant (§3.1), so anyone who can call
   the skill can read its rules. Auditable rules are part of the product. What
   does not become visible: execution traces, org config, your other
   deployments.
2. **Access mode.**
   - _Requires a Legalese Cloud account_ (default) — "callers are billed for
     their own usage; you'll earn revenue share when that ships". On the free
     tier, identified cross-org traffic is capped by the org-level
     `crossOrgDailyLimit` (§5.2); upgrading to any paid plan removes the cap.
   - _Public — no account needed_ — "anyone can call this; **evaluations bill
     to your org and count against your org's own daily request limit**,
     exactly like your own traffic (§5.5.2)."
3. **Listing.** Display name, summary (prefilled from Intended use), category,
   tags (suggested from function names), license, jurisdiction, support URL,
   disclaimer preview.
4. **Terms.** Checkbox + version, links to the publisher agreement.

### 8.3 RPC

New in `ts-shared/jl4-client-rpc/vscode-and-webview-messages.ts`, alongside
`RequestInstallDeploymentSkill`:

```ts
RequestPublishDeployment: NotificationType<{
  deploymentId;
  listing;
  mode;
  termsVersion;
}>;
RequestUnpublishDeployment: NotificationType<{ deploymentId }>;
GetPublishStatus: RequestType<
  { deploymentId },
  { published: boolean; url?: string }
>;
```

Wire in `ts-apps/vscode/src/sidebar-provider.ts` → new
`ts-apps/vscode/src/deployment-publish.ts`, mirroring `deployment-install.ts`
(session token from `AuthManager`, calls through `ServiceClient`).

### 8.4 Undeploy warning

The existing `.breaking-warning` view (`+page.svelte:2321-2340`) already warns
that undeploying breaks integrations and lists the rules being deleted. Add one
conditional block when the deployment is published:

> **This skill is published on Provable.** It has _N_ installs and _M_ reviews.
> Undeploying delists it and breaks it for everyone who installed it. Reviews
> are retained; the listing is not restored by redeploying.

In `public` mode, additionally note that anonymous traffic stops immediately.

---

## 9. Skill detail page

- **Header** — display name, publisher org name + verified-domain badge,
  `deploymentVersion`, rating, "N orgs used this in the last 30 days" (§6),
  categories.
- **Intended use** — `metadata.description`, verbatim. It is the authored
  contract.
- **MCP tools** — one fetch to `skills.legalese.cloud/{org}/{dep}` returns
  `{ hash, files }` including `references/schemas.json`. Single source of truth;
  do not re-derive.
- **Install** — per-harness, driven by the existing `HARNESSES` list.
  Claude Code: `/plugin marketplace add skills.legalese.cloud/marketplace.git`.
  ChatGPT / Gemini: the MCP connector URL `mcp.legalese.cloud/{org}/{dep}`,
  which self-configures off the RFC 9728 Protected Resource Metadata and
  `/auth.md` already served there. Every path POSTs `/install`.
- **API** — OpenAPI spec from `api.legalese.cloud/{org}/{dep}/openapi.json`
  (rendered from EFS, works while the org is scaled to zero) with a try-it form.
- **Chat** — `legalese-comply-4` via `ai.legalese.cloud/{org}/{dep}/v1`, proxied
  through a Next route handler. Set an explicit `maxDuration` (300s) on the
  route and track function-duration cost from day one; if chat volume ever
  makes the proxy expensive, the designed escape hatch is a 5-minute
  single-purpose JWT minted by auth-proxy
  (`{callerOrg, publisherOrg, deploymentId, aud: "ai-proxy", grant: ["chat"]}`)
  letting the browser stream direct — a Phase 4+ option, built only when the
  cost data says so.
- **Reviews** — usage-verified (§6), one per user, version-stamped.
- **Disclaimer** — mandatory, non-editable, on every listing.

---

## 10. The endgame this unlocks

`skill-bundle.ts` already notes that the gateway plugin "sets up a future where
an account spans its own org plus public rules from others." That future becomes
buildable in Phase 4: **installing a Provable skill = adding it to your
account's discovery MCP surface** (`mcp.legalese.cloud/`, org resolved from
token), so an agent finds it through `search_rules` without one MCP server per
skill.

That is a materially better agent UX than N connectors, and it is the natural
place for per-install billing to hook in. Design the `installs` record with this
in mind even though Phase 2 only emits `.mcp.json` snippets.

---

## 11. Monetisation — decisions that must be made now

Cheap now, impossible or expensive later:

1. `publisherOrg` + `callerOrg` + `callerType` + `accessMode` on every JSONL
   entry (§5.5.1) — facts only, no `billedOrg`.
2. Reserve the `marketplace` billing source key.
3. `install` as a first-class recorded event — the skills registry currently
   omits `installs` deliberately. Both the extension and the website install
   paths must record it. (It is the funnel record, not the review gate —
   reviews gate on verified usage, §6.)
4. `pricing jsonb` on `skills` **plus `skill_pricing_history`** from day one,
   even if only `{"model":"free"}` is accepted — the cron prices historic
   requests from the history table (§5.5.3, §6).
5. **Stripe Connect** is not in the stack today (the current integration is
   one-directional metered billing). Publisher payouts need Connect accounts and
   KYC, which has lead time. Start the account setup well before Phase 5.
6. Legalese Cloud's own skills earning per MCP/API request is just the metered
   path with `publisherOrg === 'legalese'` — it falls out of (1) for free.

---

## 12. Publisher trust and moderation

### 12.1 Verified publisher badge

Populate from WorkOS. An organisation's `domains[]` carries a `state` from
`OrganizationDomainState`: `verified`, `legacy_verified` (`@deprecated`),
`pending`, `failed`.

**The badge requires `state === "verified"` only** — deliberately stricter than
`ai-proxy/src/org-domain-cache.ts:59-80`, which accepts `legacy_verified` too.
That difference is intentional and neither side should be "fixed" to match the
other:

- ai-proxy's predicate feeds **CORS**. Being permissive there only means an
  existing customer's browser calls keep working; tightening it locks people out
  for no security gain.
- Provable's predicate feeds a **public trust claim**. `legacy_verified` is
  WorkOS grandfathering domains trusted before DNS-based verification existed —
  the companion `verificationStrategy` field is often `manual`, i.e. asserted
  rather than proven. A "verified publisher" mark on a legal-reasoning
  marketplace should mean DNS-proven control, not grandfathered.

**Pre-flight check before shipping:** sweep `listOrganizations` and count
domains by state. If no org holds a `legacy_verified` domain, the strict
predicate costs nothing. If any do, they need a one-time DNS re-verification —
which moves them to `verified` and retires the value for good.

Page `listOrganizations` at `limit: 100` (org-domain-cache is the reference for
the pagination), but store per-publisher rather than flattening into a global
origin set.

Refresh on publish and on a daily job, writing `verified_domains[]` +
`domains_checked_at`. Render the badge in the skill-page header (§9) and on
catalog cards. It is a free trust signal built on verification the tenant has
already done — use it from day one.

### 12.2 Moderation: review an org's first publish, then auto-approve

Trust is the `publisher_trust` table (§5.2), keyed by org; `pending` is a
**derived** state — a `WHERE`, never a stored column:

| `publisher_trust` row | Effect on that org's intents                                                                        |
| --------------------- | --------------------------------------------------------------------------------------------------- |
| absent (_unreviewed_) | intent rows land but are **inert** — not listed, not callable cross-org; Provable derives `pending` |
| `trusted`             | all intents live immediately; subsequent publishes go live on write                                 |
| `blocked`             | nothing callable; the publish API rejects new intents; every existing skill is dead                 |

Approving an org's first skill is **one platform-scope row**
(`publisher_trust[org] = 'trusted'`), which flips every pending intent live
at once — the gate is paid once per organisation rather than once per skill,
falling out of the data model rather than procedure. This is the right trade
for legal-reasoning tooling: it catches the impersonation and obvious-abuse
cases at the only point where a human review is affordable, without putting a
queue in front of an active publisher's iteration loop. A skill awaiting first
review is not merely unlisted — it is not reachable cross-org at all (§3.3).
Anything weaker would make review cosmetic, since the MCP endpoint is the
actual product.

There is no `moderation_state` mirror column: the catalog derives
`approved | pending | suspended` by joining the same three tables the proxies
snapshot, so listing state and callability cannot diverge.

Moderation endpoints on auth-proxy write **platform scope only** — their SQL
touches `publisher_trust`/`suspensions` and nothing org-authored, so no
credential ever writes another org's scope:

```
POST legalese.cloud/marketplace/admin/trust     { orgSlug, state }          legalese-org l4:admin
POST legalese.cloud/marketplace/admin/suspend   { orgSlug, deploymentId }   legalese-org l4:admin
GET  legalese.cloud/marketplace/admin/state
```

Provable's moderation UI forwards the staff member's **own** bearer per
request — the same no-elevated-credentials pattern as publish (§4.2); the gate
is that the bearer resolves to the `legalese` org and holds `l4:admin`.

**Suspension is delist-and-revoke by construction** (§3.3): one `suspensions`
row both delists and revokes, because catalog and auth read the same table.
Reviews and install history are retained. `reports` feeds a queue that can
suspend an approved skill, or block a publisher — which kills every skill they
own with one row.

### 12.3 Content changes after approval

First-publish review does not cover later redeploys — a trusted publisher can
change a live skill's content silently under the same listing. Tripwire, not
queue:

- Provable's daily sync compares the registry's `computeSkillHash` against the
  latest `skill_versions` row; on change it inserts a new version row. The
  listing shows "v{deploymentVersion}, updated {date}" with a SKILL.md diff
  between versions — sunlight is most of the deterrent.
- **A hash change on a skill with ≥1 open report creates a moderation-queue
  item.** Clean skills iterate freely; anything a user has flagged gets human
  eyes on its next content change. Suspension remains the human action.
- Installer notifications on version change are a Phase 3+ nicety.

### 12.4 Reconciliation: eliminated by construction

The v1 EFS/Postgres split needed a nightly reconciler for orphans between
the two stores. With one system of record there is nothing to reconcile —
callability and the catalog are the same rows. What remains is §12.3's
registry-hash sync (content drift between EFS deployment stores and
`skill_versions`, which is a _tripwire_, not a consistency mechanism) and
ordinary DB backup/PITR, which Neon provides.

---

## 13. Phasing

| Phase                              | Content                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Repos                                    |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| **now**                            | `return_to` open-redirect fix + signed `state` (§5.8) — its own PR, no marketplace dependency                                                                                                                                                                                                                                                                                                                                                                                                                     | `jl4-auth-proxy`                         |
| **0**                              | Delete `publicDeployments`; org intent + platform trust config shapes with plan-tier cap defaults (§5.2); cached two-file accessor; `MARKETPLACE_GRANT` + `scope` on auth results; marketplace grant cache; `@legalese/marketplace-access` decision package + shared fixtures; org-keyed counters + new meter signature; fact-only access fields in JSONL + `marketplace` source classifier in the sweep Lambda; reserve `provable` subdomain                                                                     | `jl4-auth-proxy`, `ai-proxy`             |
| **1 — SHIPPED (v1, EFS)**          | `/marketplace/publish\|unpublish` + `admin/trust\|suspend\|state` endpoints, EFS-backed (`withFileLock`, org `.marketplace` blocks, platform trust file); read-model `marketplace` block for the sidebar; validated end-to-end, 8 skills live                                                                                                                                                                                                                                                                     | `jl4-auth-proxy`                         |
| **1a — SHIPPED 2026-08-05 (§4.2)** | Neon (us-west-2) provisioned; schema + roles (authproxy / provable_site / lambda_ro / aiproxy_ro) applied and privilege-verified; `MarketplaceStore` → snapshot reader in both proxies (jl4-auth-proxy `eb8307f`, ai-proxy `25724c3`); routes write transactions; 8 live intents + trust migrated with parity; EFS marketplace files retired (`*.pre-1a-backup` kept); validation 16 6/6 through the DB. Pending: ai-proxy terraform apply + deploy for its DATABASE_URL (until then cross-org chat fails closed) | `jl4-auth-proxy`, `ai-proxy`             |
| **1b**                             | New `provable` repo on Vercel + same Neon; publish/terms/admin pages + API forwarders; VS Code Publish pop-over, row rework, undeploy warning (VSCODE-PUBLISH-SPEC.md)                                                                                                                                                                                                                                                                                                                                            | `provable`, `l4-ide`                     |
| **2**                              | Browse + SSR skill pages + install guide; **verified publisher badge** (§12.1); registry-hash sync (§12.3) + `skill_usage_daily` sync                                                                                                                                                                                                                                                                                                                                                                             | `provable`, `jl4-auth-proxy`             |
| **3**                              | Usage-verified reviews, install tracking, reports queue → suspend / block; hash-change tripwire (§12.3)                                                                                                                                                                                                                                                                                                                                                                                                           | `provable`                               |
| **4**                              | In-page chat + OpenAPI try-it; cross-org skills in the account-wide discovery MCP; optional direct-stream chat token if proxy cost warrants (§9)                                                                                                                                                                                                                                                                                                                                                                  | `provable`, `ai-proxy`, `jl4-auth-proxy` |
| **5**                              | Stripe Connect, per-install and per-request revenue share from `revshare_ledger`                                                                                                                                                                                                                                                                                                                                                                                                                                  | `provable`, `jl4-auth-proxy`             |

Phase 0 is self-contained, touches only the two proxies, and unblocks
everything else.
