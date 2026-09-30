# cloud-sessions-git-sync — post-mortem

l4-ide · branch `thomasgorissen/cloud-sessions-git-sync` · base `cloud-sessions-client` · [PR #511](https://github.com/legalese/l4-ide/pull/511) · 2026-09-28

## What was built

`ts-apps/vscode/src/cloud/git-sync.ts` — `CloudGitSync` over a structural
subset of VS Code's `git.d.ts` (API 1), no `vscode` import: credentials
provider for the Sessions API host (username `legalese`, password = fresh
WorkOS JWT), remote-source provider for "Git: Clone", `clone(url, {
parentPath, postCloneAction: 'none' })` + `setConfig` of the three §9.3
options, adoption of clones VS Code opens elsewhere, `sync` = `pull()` then
`push()` when ahead, `status` (unavailable / not-cloned / cloned with
ahead, behind, pending). `vscodeGitApi()` and the settings-driven
(re)registration live in `vscode-cloud.ts`; the sid → folder map in global
state (`legaleseAi.cloudSessions.clones`).

## Spec sections covered, and deviations (with reasons)

§9.2 (Basic auth with the JWT), §9.3 (credentials, clone, the three options,
sync, button states, requirements message, 4.5 MB push message). Deviations:

- Clone folder is `<parent>/<sid>` (the Git API picks it from the URL).
- `pending` = a push succeeded and the branch is still ahead of
  `origin/main` (commits wait in `local`); the UI combines it with the
  session state to say "pending until the session runs".
- Push is skipped when nothing is ahead.

## Checks run

`npm ci`, `npm run build`, `lint`, `format:check`, `check`, `npm test` — pass
locally (20/20; extension unit tests 46). No PR CI (stacked). Not run in a
live VS Code; `git.d.ts` was checked against the copy in the scratchpad
(VS Code 1.106+ `CloneOptions.postCloneAction`).

## Problems and how they were solved

- Clones made through VS Code's own "Git: Clone" never pass through our
  code, so they'd lack the push refspec. Solved by adopting repositories on
  `onDidOpenRepository` whose origin matches `<apiUrl>/git/<ULID>.git`.

## Open questions and follow-ups for later items

- Sessions API: the push refspec writes `refs/heads/local`; the pre-receive
  hook must accept a first push that creates `local` and later
  non-fast-forward-free updates. A clone of a session whose harness never
  ran is empty (no `main` yet); pull then fails with "no tracking
  information" — the UI should offer Clone only once `main.bundle` exists
  (e.g. after the first `git-committed` event).
- P7: whether function URLs accept the single-request 5 MB push.

- Follow-up 2026-09-30: rebased on the updated client branch; clones show `data/` and `tmp/`, and Open Folder opens the clone root; sync unaffected. Checks re-run locally, all pass.

## Where a reviewer should start

`git-sync.ts` (`register`, `adopt`, `configure`, `sync`), then
`vscodeGitApi` in `vscode-cloud.ts`, then `cloud-git-sync.test.ts`.
