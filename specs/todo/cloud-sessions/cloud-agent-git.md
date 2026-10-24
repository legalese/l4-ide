# cloud-agent-git — post-mortem

l4-ide · branch `thomasgorissen/cloud-agent-git` · base `cloud-agent-runner` · [PR #514](https://github.com/legalese/l4-ide/pull/514) · 2026-09-28

## What was built

`ts-apps/cloud-agent/src/git-sync.ts` (a `RunnerPlugin`) and `git.ts` (a
hardened `git` runner). Start: init (dev only), abort a leftover merge, `Seed`
commit, `main.bundle`. Per turn: commit with `Turn-Id: <turnId>` trailer →
bundle (temp + rename) → `git-committed { turnId, sha, parent }`.
`apply-bundle`: fetch `+refs/heads/local:refs/incoming/<ulid>` → merge →
`local-merged`, or abort → `local-merge-conflict { files }`. `rollback`:
`git restore --source=<parent> --staged --worktree -- :/` → "Roll back: …" →
`rolled-back`; the next prompt gets a `<rollback-notice>`. Sleep: leftovers
commit + `git gc` (not on SIGTERM). The runner gained
`RunnerContext.filesChanged` so merges and rollbacks resync `jl4-lsp`.
11 new tests with real git in temp dirs (73 in the package).

## Spec sections covered, and deviations (with reasons)

§4.7, §5.4 (seed, end of turn, idle gc), §9.1, §9.4. Deviations:

- Commit subject = the prompt's first line (no separate "turn summary").
- Rollback of a turn without a commit is a no-op with no event.
- Uncommitted leftovers are committed ("Checkpoint before …") before a merge
  or rollback, so both start from a clean tree.
- Incoming bundles are left in place (the API owns `incoming/` and
  `git/local.json`); the harness only deletes its `refs/incoming/<ulid>`.
- git runs with hooks and fsmonitor disabled, no system config, a fixed
  identity and `safe.directory`, beyond the §4.7 `createObject`/`gc.auto`.

## Checks run

`npm ci`, `build`, `lint`, `format:check`, `check`, `test` — all pass locally
(first run failed lint: `process.env.PATH` in tests trips
`turbo/no-undeclared-env-vars`; now read through a helper). No PR CI for
stacked PRs. Bundle run end to end with real git and `jl4-lsp`: edit turn →
commit → rollback → file restored, `git log` as expected.

## Problems and how they were solved

- Rebasing onto the runner's follow-up commit conflicted in
  `runner.test.ts` (two appended tests); kept both.
- Finding a turn's commit with `--grep` would match `t1` in `t10`; it parses
  the `Turn-Id` trailer with `%(trailers:key=Turn-Id,valueonly)` instead.

## Open questions and follow-ups for later items

- Sessions API: incoming bundles must contain `refs/heads/local` (the harness
  fetches exactly that ref); `apply-bundle.file` is the file name in
  `incoming/`. Pending-push bookkeeping stays the API's.
- Extension: `git-committed` arrives after the turn's `done`; `rolled-back`
  uses the turn id from the `rollback` command. Conflicts leave the user's
  commits unmerged; the client resolves (pull, merge, push again).
- P3 measured `git gc` at 5.7 s; on SIGTERM it's skipped to stay in 30 s.

## Where a reviewer should start

`src/git-sync.ts` (`rollback`, `applyBundle`), `src/git.ts` (the `-c`
list), then `test/git-sync.test.ts`.

## Follow-up: repo layout (2026-09-30)

The earlier backup clearing and git-history restore are gone. `tmp/` and
`tmp/deleted/` are committed like everything else and never cleared by the
harness. At start, if every tracked file under `tmp/` is gone and nothing new
is there (the Sessions API sweep cleared an abandoned session), the harness
commits that alone: "Clear tmp of abandoned session". 1 test.
`add-files`: `onFilesAdded` commits only the added paths ("Add files from
the user") and returns blob ids for `files-added`. 1 test.
