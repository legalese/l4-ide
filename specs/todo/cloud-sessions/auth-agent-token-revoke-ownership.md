# auth-agent-token-revoke-ownership — post-mortem

jl4-auth-proxy · branch `thomasgorissen/auth-agent-token-revoke-ownership` · base `main` · [PR #4](https://github.com/legalese/jl4-auth-proxy/pull/4) · 2026-09-28

## What was built

- `POST /auth/agent-token/revoke` checks ownership before deleting: it looks the
  id up in `GET /user_management/users/{userId}/api_keys?organization_id=<active org>`
  (new `findUserApiKey()` in `src/auth/agent-keys.ts`, 100 per page, up to 20
  pages) and re-checks the owner (user-scoped, same user, same org).
- Not the caller's key (other user, other org, org-owned, missing), or no active
  org → `404 { error: "Not found" }`, nothing deleted. Listing failure → `502`.
- README / ARCHITECTURE revocation notes updated.

## Spec sections covered, and deviations (with reasons)

§15.3 item 1 (gap from §2). No deviations. WorkOS has no single-key GET, so
listing under the user is the ownership check.

## Checks run

- `npm test`: 45 files → 46, all pass (new `src/auth/routes.test.ts`, 9 tests;
  real route handler over HTTP, WorkOS SDK mocked, raw WorkOS HTTP served from an
  in-memory key store).
- `tsc --noEmit` clean. `eslint` on touched files: only the pre-existing
  `routes.ts` unused `organizationId` error (7 pre-existing lint errors repo-wide;
  lint isn't run in CI). New files prettier-formatted; `routes.ts` wasn't
  prettier-clean on `main` and wasn't reformatted, to keep the diff reviewable.
- CI: the repo has no pull-request workflows (all four are `workflow_dispatch`
  deploy jobs; `deploy-proxy` runs `npm test` + `npm run build` before deploying).
  `gh.py checks` → "no checks yet".
- `validation/tests/` (live production) not run, as instructed.

## Problems and how they were solved

- WorkOS list response shape (`data`, `list_metadata.after`) and the user-key
  list endpoint taken from the public API reference; not verified live.

## Open questions and follow-ups for later items

- A user with more than 2 000 keys in one org would get a 404 for keys past page
  20 (logged). Unrealistic, but noted.

## Where a reviewer should start

`src/auth/agent-keys.ts` `findUserApiKey`, then `handleAgentTokenRevoke` in
`src/auth/routes.ts`, then `src/auth/routes.test.ts`.
