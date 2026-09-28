# auth-access-token — post-mortem

jl4-auth-proxy · branch `thomasgorissen/auth-access-token` · base `auth-agent-token-revoke-ownership` · [PR #5](https://github.com/legalese/jl4-auth-proxy/pull/5) · 2026-09-28

## What was built

- `GET /auth/access-token` → `200 { accessToken, expiresAt }`, `expiresAt` = JWT
  `exp` in epoch ms, `Cache-Control: no-store` on every response.
- Sealed session only (Bearer or `wos-session` cookie). A Bearer `sk_…` key or a
  JWT gets `401 { error: "unauthenticated" }` before WorkOS is asked. No/invalid
  session → same 401.
- If the token has < 60 s left, the session is refreshed first.
  `resolveSession()` gained optional `{ minAccessTokenLifetimeSeconds }` and now
  returns `accessToken`; the middleware's calls are unchanged.
- A rotated sealed session is returned as `Set-Cookie: wos-session=…` (as the
  proxy does) and as `token` in the body (as `/auth/session` does).

## Spec sections covered, and deviations (with reasons)

§6.1, §15.5 row 1. Deviation: the body may carry an extra `token` (rotated
sealed session) so Bearer clients like the extension can store the rotation.

## Checks run

- `npm test`: all pass; new `src/auth/session.test.ts` (6) and 8 route tests.
- `tsc --noEmit`, `npm run build` clean; no new lint errors. No PR CI exists in
  this repo (see revoke post-mortem); `gh.py checks` → no checks.

## Problems and how they were solved

- `refresh()`'s result doesn't include `accessToken` at the top level; it's in
  `session.accessToken` (SDK 7.82). Read from there.
- Refreshing on every call would rotate the refresh token each time and race
  with the extension's other users of the same sealed session, so refresh only
  happens near expiry.

## Open questions and follow-ups for later items

- §6.1: which permission/role claims the WorkOS JWT carries (the Sessions API
  wants `ai:chat`). The existing middleware reads a `role` claim from a JWT
  template and maps it to permissions via the org role catalog; sealed-session
  JWTs also carry `permissions` per the SDK's `AccessToken` type. Confirm live.
- `cloud-sessions-client` must store `token` when present.

## Where a reviewer should start

`handleAccessToken` in `src/auth/routes.ts`, then `src/auth/session.ts`.
