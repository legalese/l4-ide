# cloud-sessions-api — post-mortem

jl4-auth-proxy · branch `thomasgorissen/cloud-sessions-api` · base `cloud-sessions-terraform` · [PR #8](https://github.com/legalese/jl4-auth-proxy/pull/8) · 2026-09-28

## What was built

`cloud-sessions/api/`: a TypeScript Lambda (function URL, payload 2.0) with
every §7.1 route, the scheduled sweep, a Dockerfile (Lambda `nodejs:24` +
`git-core`), a manual image workflow, and a CI job. Modules: `auth` (jose,
Bearer / Basic-on-git, configurable permission claim), `folder` (HMAC),
`provision` (§4.4 access point + §5.1 task definition, throttling backoff),
`sessions` (create/init/list/get/start/stop/delete), `relay` (commands,
events), `events` (batch), `git` (scratch repo + `git http-backend` + own
`pre-receive` hook), `seed` (own strict tar parser), `sweep`, `safe-fs`
(hostile-content layer), `protocol` (mirror of l4-ide's
`cloud-session-protocol`, with a comment saying so).

## Spec sections covered, and deviations (with reasons)

§7.1–§7.3, §8, §9.1–§9.2, §10 (server side), §4.4, §5.1 RunTask, §15.5.
Deviations:

- `stop` writes `state/stop-requested.json`; the sweep stops the task once
  60 s passed (a request can't wait 60 s) — effective delay 1–6 min.
- `DELETE` answers `409 stopping` while a task lives, deletes on retry.
- Pending pushes are tracked in the API-owned `state/git/local.json` instead
  of listing `incoming/` (keeps the no-listing rule).
- `POST /sessions` takes an optional `seedSize` to size-bind the seed URL.
- `wake` = hash of `head.json` + current minute (no stored counter).
- `MAX_LIVE_SESSIONS` (default 3) → `409 too_many_sessions`.
- 503 codes `start_failed` / `unavailable` and 403 `forbidden` in addition to
  the §15.5 list; tampered content → `409 conflict`.
- `repo/.git` skeleton is built by `git init` in `/tmp` and copied in, so git
  never runs inside a user folder.

**Aligned with protocol** (l4-ide PR #509, commit `cf1ab7f`): the command,
session.json, lease, cursor and `POST /sessions` validation now follow
`ts-shared/legalese-agent/src/protocol/`. Changes: `inject` requires
`turnId`, `injectionId` is optional; `answer` may be `""`; `mcp-credentials`
must be a sealed `v1.` string (body cap about 1 MB); MCP servers need a valid
name, an https URL and no duplicates; attachments need a content type; titles
over 200 characters are refused; `commands.seq` is `"<n>\n"`; a bare
`<segment>` cursor is accepted; upload targets carry `maxBytes`. Later
(protocol `afc6926c5`): `approve` and `approval-request` are gone (400).
**Layout** (`1d1ea8d1e`): `/init` makes `repo/data/`, `repo/tmp/` (no
`.legalese/`), seeds `repo/data/`; the sweep clears `repo/tmp/` hourly when
idle past `ABANDONED_TMP_DAYS` (fs only, no symlinks; §7.2 listing exception).
**Add files** (`351982201`): `POST …/files` + `…/files/:batchId/commit` stage
files in `incoming/files/<batchId>/`, queue `add-files`; `message.context`;
`seedBase` (`b6ec4779d`) validated, stored in session.json, returned by GETs.

## Checks run

`npm run format:check`, `lint`, `typecheck`, `test` (99 tests), `build` —
pass locally (macOS) and in CI (Linux, where the `/proc/self/fd` check is
exercised). Root `tsc`/vitest unaffected; root ESLint has 7 pre-existing
errors on `main`, unchanged. Docker image not built (no Docker locally);
image workflow not run.

## Problems and how they were solved

- A git test hung: `execFileSync` blocked the event loop that served the
  in-process HTTP bridge. Network git calls are now async with timeouts.
- A `[A-Za-z0-9._-]` name rule rejected real file names; replaced with a
  component validator (no separators, NUL, control chars, `.`/`..`).
- O_NOFOLLOW only protects the last component, so every directory on the way
  is `lstat`-checked and each opened descriptor is verified by path.

## Open questions and follow-ups for later items

- `protocol.ts` is a hand-kept mirror of l4-ide #509; re-check on changes.
- The harness ignores `init.json`, `stop-requested.json`, `git/local.json`,
  `incoming/files/<batchId>.json`; it may assume `repo/.git` exists.
- `commands.seq` can regress briefly under concurrent writers; P7 (function
  URL + chunked git pushes, 6 MB limits) still open.

## Where a reviewer should start

`src/safe-fs.ts`, `test/hostile.test.ts`, `src/git.ts`, `src/sessions.ts`.
