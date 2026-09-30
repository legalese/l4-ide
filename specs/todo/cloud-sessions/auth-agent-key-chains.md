# auth-agent-key-chains — post-mortem

jl4-auth-proxy · branch `thomasgorissen/auth-agent-key-chains` · base `auth-access-token` · [PR #7](https://github.com/legalese/jl4-auth-proxy/pull/7) · 2026-09-28

## What was built

- Mint: `POST /auth/agent-token { purpose: "cloud-session", sessionId }` → key
  `cloud-session:<sid>:<chainStartEpochSeconds>`, 900 s, `{ai:chat, l4:rules,
l4:evaluate, l4:read}` ∩ held, `expiresAt` in ms. Non-ULID sid → `400
invalid_session_id`; other purpose → `400 unknown_purpose`. Legacy mints unchanged.
- Renew: `POST /auth/agent-token/renew` (Bearer key): validate (user-scoped +
  chain name, else `401 invalid_key`) → age ≤ 24 h or org `agentChainMaxAgeHours`
  (`403 chain_expired`) → activity ≤ 10 min (`403 inactive`) → delete presented
  key (already gone → `409 chain_forked`) → mint successor (same name, perms,
  org) → `{ token, id, expiresAt }`. WorkOS errors → `502 upstream_unavailable`.
- End: `POST /auth/agent-token/end` (Bearer key) → delete, `204`.
- Activity: `AGENT_ACTIVITY_SOURCE=efs|workos` (default `efs`), `EFS_ROOT`
  (default `/efs`); `src/auth/agent-activity.ts` reads
  `<EFS_ROOT>/agent-activity/<sid>.json`, requiring a matching `sessionId`.
- Per-org age: root-level `agentChainMaxAgeHours` in the org config file;
  org id → slug via WorkOS `externalId` (cached), wired in `src/index.ts`.
- Cache audit: main auth cache already skipped user-scoped keys; the
  **marketplace grant cache didn't** — fixed, with tests.
- README (env vars, routes, chain section) and ARCHITECTURE updated.

## Spec sections covered, and deviations (with reasons)

§6.2, §6.3, §15.5. Deviations:

- The chain start counts as activity. Otherwise the task's first renewal
  (seconds after start, before any model call) would always be `inactive`.
- A chain start > 5 min in the future → `401 invalid_key` (only a hand-named
  key could have one; it would stretch the 24 h cap).
- `502 { error: "upstream_unavailable" }` added for WorkOS failures.
- Legacy mints keep `expiresAt` in epoch seconds; all cloud-session responses use ms.

## Checks run

- `npm test`: 764 pass (new/extended: `routes.test.ts`, `agent-activity.test.ts`,
  `agent-keys.test.ts`, `middleware.marketplace.test.ts`; WorkOS mocked, temp
  dir as EFS). The marketplace no-cache test fails without the fix.
- `tsc --noEmit`, `npm run build` clean; no new lint errors. No PR CI in this
  repo; `gh.py checks` → no checks. `validation/tests/` not run.

## Problems and how they were solved

- The `workos` source can't read `last_used_at` _before_ validating: the key's
  user id is only known after validation, and listing needs it. It reads the
  listing after validation. **Unverifiable without live WorkOS (P6):** if
  validation bumps `last_used_at`, this source always says "active" and chains
  run to the 24 h cap. `efs` stays the default.
- Test ULIDs initially contained `U` (not Crockford) — the validator caught it.

## Open questions and follow-ups for later items

- Deploy step: `/efs/agent-activity/` must exist, writable by ai-proxy (see
  `ai-cloud-session-activity` post-mortem); this proxy only reads.
- ai-proxy's optional `AUTH_USER_KEY_CACHE_TTL_MS` (≤ 60 s) would let a deleted
  chain key keep working there that long; keep it off for chain keys.
- Renewal keeps the key's permissions and doesn't re-check org membership; a
  user removed from the org keeps a working chain until the 24 h cap unless
  WorkOS deletes their keys. Consider a membership check.
- If the successor mint fails after the delete, the chain is over (`502`); the
  task must park and ask for a new chain (`cloud-agent-runner`).

## Where a reviewer should start

`handleAgentTokenRenew` / `authenticateChainKey` in `src/auth/routes.ts`, then
the chain helpers in `src/auth/agent-keys.ts`, then the `routes.test.ts` chain tests.
