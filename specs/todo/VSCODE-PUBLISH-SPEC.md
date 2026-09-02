# VS Code Sidebar — Marketplace Publish Implementation Spec

Implementation spec for the l4-ide changes that let a publisher take a cloud
deployment to the marketplace from the sidebar. Refines
[PROVABLE-MARKETPLACE-SPEC.md](PROVABLE-MARKETPLACE-SPEC.md) §8; companion to
[PROVABLE-SITE-SPEC.md](PROVABLE-SITE-SPEC.md).

**Ground truth as of 2026-08-04:** the platform endpoints are live
(`legalese.cloud/marketplace/publish|unpublish`, both `l4:deploy` with
`?org=`), so this UI can ship and work **before** the Provable site exists —
publish responses carry `live: true|false` ("live" vs "pending review"), and
published skills are immediately callable cross-org and listed on
`skills.legalese.cloud`. Listing metadata (`displayName`, tags, …) is
forwarded to the Provable API once it exists; until then the popover collects
it and the extension sends only what the platform endpoint accepts
(`deploymentId`, `mode`, `termsVersion`) plus stashes the listing fields in
the request for forward-compatibility.

Touched packages: `ts-apps/webview` (sidebar UI),
`ts-shared/jl4-client-rpc` (messages), `ts-apps/vscode` (extension side).

---

## 1. Deployment row (`ts-apps/webview/src/routes/sidebar/+page.svelte:2465-2549`)

Current row actions: `Chat` · `Integrate` · `⋯` (Download, Undeploy).

Changes:

1. **`Integrate` moves into the `⋯` menu** as the first item (above
   Download / Undeploy); `showMenu` becomes unconditional. The row stops
   growing wider per feature.
2. **`Publish` appears as the second text button** (cloud mode only — same
   guard as `Chat`: `integrateMode === 'cloud'` with a connected org):

   - Unpublished: `Publish` — `deployment-text-btn` at `opacity: 0.85`
     (brighter than the default 0.6; the crimson `#c8376a` stays reserved for
     primary CTAs). Opens the publish popover.
   - Published + live: `Published ✓` — same button style; opens the popover
     in _manage_ mode (shows state, mode, unpublish).
   - Published + pending review: `Pending review` at 0.6 opacity; popover in
     manage mode explains the review step.
   - State arrives WITH the deployment list: the sidebar's existing
     `GET /deployments?functions=full` (served by the proxy read-model on
     `api.legalese.cloud/{slug}`) gains a `marketplace` block per entry —
     no extra round trip, no separate status fetch (§4).

Row sketch (unpublished / published):

```
▸ dog-act-of-jersey        ready   Chat  Publish      ⋯
▸ parking-rules            ready   Chat  Published ✓  ⋯
                                        ┌─────────────┐
                                        │ Integrate   │
                                        │ Download    │
                                        │ Undeploy    │
                                        └─────────────┘
```

---

## 2. `deployment-publish-popover.svelte` (new, `ts-apps/webview/src/lib/components/`)

Same shell as `deployment-integrate-popover.svelte`: absolute backdrop inside
`.tab-content-frame`, `Esc` to close, `stopPropagation` on the dialog,
toggled by an `publishForId: string | null` state in `+page.svelte`
(mirroring `integrateForId`). Wizard with a step indicator, `Back` /
`Continue`, and a final `Publish` button.

### Step 1 — What becomes visible

Static copy with the deployment's own values inlined:

> Publishing makes the following visible to anyone who can access this skill:
>
> - the generated **SKILL.md** and your **Intended use** text,
> - function names, descriptions, and schemas (MCP tools + OpenAPI),
> - **the deployment's `.l4` source files** — auditable rules are part of the
>   product; anyone who can call the skill can read its rules.
>
> Not visible: execution traces, your org configuration, your other
> deployments.

Hard gate replicated client-side for good UX (the server enforces it with a
422): if `metadata.description` is empty, the step shows "Add an 'Intended
use' description and redeploy first" and `Continue` is disabled.

### Step 2 — Access mode

Radio, two options (unlisted is API-only until a partner asks):

- **Requires a Legalese Cloud account** _(default)_ — "Callers are billed for
  their own usage; you'll earn revenue share when that ships. On the free
  tier, cross-org calls are capped org-wide (`crossOrgDailyLimit`); any paid
  plan removes the cap."
- **Public — no account needed** — amber panel: "Anyone on the internet can
  call this. **Evaluations bill to your org** and count against your org's
  own daily request limit, exactly like your own traffic."

### Step 3 — Listing

Form, prefilled where possible:

| Field        | Prefill                        | Notes                                                           |
| ------------ | ------------------------------ | --------------------------------------------------------------- |
| Display name | deployment id, title-cased     | required                                                        |
| Summary      | first sentence of Intended use | required, ≤200 chars                                            |
| Category     | —                              | fixed list (tax, employment, housing, trade, compliance, other) |
| Tags         | suggested from function names  | chips, ≤5                                                       |
| License      | "All rights reserved"          | free text or SPDX                                               |
| Jurisdiction | —                              | free text ("Singapore", "Jersey", …)                            |
| Support URL  | —                              | optional                                                        |

Disclaimer preview (read-only): the mandatory listing disclaimer.

### Step 4 — Terms

Publisher agreement summary + link to `provable.legalese.com/terms/publisher`
(until the site exists: the same content shipped as a static page in the
popover), checkbox "I agree to the Publisher Agreement ({version})".
`Publish` enables only when checked.

### Result states

- `{ published: true, live: true }` → success panel: "Published — live now",
  listing URL (site) / `skills.legalese.cloud/{org}` (pre-site), and the
  row flips to `Published ✓`.
- `{ published: true, live: false }` → "Submitted — pending first-publisher
  review. Your skill is not callable by others until approved." Row shows
  `Pending review`.
- Error → inline message, popover stays open (422 description rule, 403
  permissions, network).

### Manage mode (opened from `Published ✓` / `Pending review`)

Shows current mode + state, listing URL, and two actions:
**Change mode** (re-runs step 2 + publish — the endpoint upserts) and
**Unpublish** (confirm inline: "Removes it from the catalog and revokes all
cross-org access within ~1 minute. Reviews are retained; republishing does
not restore install counts.").

---

## 3. RPC (`ts-shared/jl4-client-rpc/vscode-and-webview-messages.ts`)

Alongside `RequestSidebarUndeploy` / `RequestSidebarDownloadDeployment`,
following the same `RequestType` + params-interface conventions:

```ts
export interface SidebarPublishParams {
  deploymentId: string;
  mode: "account" | "public";
  termsVersion: string;
  listing: {
    displayName: string;
    summary: string;
    category?: string;
    tags?: string[];
    license?: string;
    jurisdiction?: string;
    supportUrl?: string;
  };
}

export const RequestSidebarPublishDeployment: RequestType<
  SidebarPublishParams,
  { success: boolean; live?: boolean; url?: string; error?: string }
> = { method: "requestSidebarPublishDeployment" };

export const RequestSidebarUnpublishDeployment: RequestType<
  { deploymentId: string },
  { success: boolean; error?: string }
> = { method: "requestSidebarUnpublishDeployment" };
```

No status RPC: publish state rides the deployment-list payload the sidebar
already renders from (§4). The publish/unpublish responses update the
webview's local copy optimistically; the next list refresh reconciles.

---

## 4. Extension side (`ts-apps/vscode/src/deployment-publish.ts`, new)

Mirrors `deployment-install.ts`: registered in `sidebar-provider.ts`,
credentials from `AuthManager` (`auth.ts`), HTTP via the same fetch
conventions as `service-client.ts`.

- **Publish**: `POST {cloudUrl}/marketplace/publish?org={orgSlug}` with the
  session bearer and `{ deploymentId, mode, termsVersion }` (listing fields
  included in the body — the platform endpoint ignores unknown keys today;
  the Provable API will consume them via the same call once the extension
  switches its target to `provable.legalese.com/api/.../publish`, which
  forwards the bearer onward — one URL swap, no shape change).
- **Unpublish**: `POST {cloudUrl}/marketplace/unpublish?org={orgSlug}`.
- **Status**: none needed here. The auth-proxy read-model list
  (`buildDeploymentList` / `buildDeploymentStatus`, served on
  `api.legalese.cloud/{slug}` — exactly what the sidebar already calls via
  `ServiceClient`) gains a per-deployment block for OWNER callers (unscoped
  same-org results only; marketplace-scoped callers can't reach the list):

  ```jsonc
  "marketplace": {
    "published": true,
    "mode": "unlisted",
    "live": false,          // intent recorded, pending platform trust
    "publishedAt": "2026-08-04T…",
    "allowedOrgs": ["globex"]   // see visibility rule below
  }
  ```

  Omitted entirely when unpublished. One in-memory `MarketplaceStore`
  lookup (raw intent for `published`/`mode`, trust-checked view for `live`)
  per deployment — the same store the auth path reads (v1: mtime-cached EFS
  files; post-1a: the Postgres snapshot, main spec §5.3 — this spec is
  unaffected by that migration), so the sidebar can never disagree with what
  the marketplace actually serves.

  **Visibility rule for account-naming fields:** any field that names
  specific accounts — today `allowedOrgs`, the unlisted partner list — is
  included only when the caller holds `l4:deploy`. Everyone else (including
  read-scoped org credentials handed to third-party integrations) sees the
  block _without_ those fields: who an org shares its rules with is
  publisher-level information, not something every integration key should
  learn. `published`/`mode`/`live`/`publishedAt` stay visible to all owner
  callers. The sidebar is unaffected — publishing already requires
  `l4:deploy`, so any user who can open the publish popover sees the full
  block.

- Map failures: 422 → "add an Intended use description"; 403 → "your role
  can't publish (needs deploy rights)"; 404 → "deployment not found".

The read-model enrichment lands in `jl4-auth-proxy` in the same PR as this
extension change (it needs a `getDeploymentIntent` variant on
`MarketplaceStore` that returns the raw entry regardless of trust, so
"pending review" is representable).

---

## 5. Undeploy warning (`+page.svelte` `.breaking-warning`, ~2321-2340)

The existing full-tab confirm already lists the functions being deleted. Add
one conditional block (data from `GetSidebarPublishStatus`, already cached)
when the deployment is published:

> ⚠ **This skill is published on the marketplace.**
> Undeploying delists it and breaks it for everyone who installed it.
> Reviews are retained; the listing is not restored by redeploying.

- In `public` mode, append: "Anonymous traffic stops immediately."
- Once install/review counts exist (site Phase 3), interpolate "_N_ installs,
  _M_ reviews" (counts would extend the read-model `marketplace` block or
  come from the site API — decide then).
- Undeploy proceeds normally; the platform side already treats a vanished
  deployment as dead (metadata gone → 404), and the site's registry sync
  marks it unpublished.

---

## 6. Build order

1. RPC messages + `deployment-publish.ts` + read-model `marketplace` block
   (auth-proxy, tiny) — testable headless.
2. Row rework (`Integrate` → menu, `Publish` button + states).
3. Popover (steps 1–4 + manage mode + result states).
4. Undeploy warning block.
5. When the Provable site's publish API ships: switch the publish/unpublish
   target URLs; everything else is unchanged.
