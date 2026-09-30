# cloud-agent-runner — post-mortem

l4-ide · branch `thomasgorissen/cloud-agent-runner` · base `cloud-session-protocol` · [PR #513](https://github.com/legalese/l4-ide/pull/513) · 2026-09-28

## What was built

`ts-apps/cloud-agent` (esbuild → `dist/cloud-agent.cjs`): `runner.ts` (lease →
key chain → `session.json` running → `session-state`; 1 s command poll; queued
`message`/`rollback`/`apply-bundle`, immediate `inject`/`abort`/
`answer`/`stop`/`mcp-credentials`; idle exit, `stop`, SIGTERM, parking;
`RunnerPlugin` hooks), `event-log.ts`, `command-reader.ts`, `lease.ts`,
`key-chain.ts` (+ 401 retry fetch wrapper), `node-workspace.ts`, `jl4-lsp.ts`,
`interaction.ts`, `conversation-store.ts`, `session-file.ts`, `config.ts`,
`main.ts` (`--dev`, `send`). 71 tests (fake LSP over in-process JSON-RPC, fake
ai-proxy over HTTP, temp dirs) plus one opt-in test against a real `jl4-lsp`.

## Spec sections covered, and deviations (with reasons)

§5.4 (except git: next item), §6.2, §7.3 lease, §8, §11, §15.5. Deviations:

- New harness-owned `state/commands.done` (contiguous handled prefix) so a
  restart neither re-runs nor drops commands; a message still queued at park
  or SIGTERM is redelivered. `stop` discards queued commands.
- Harness creates `commands.seq` = `0` (exclusive create) if missing, so it
  never polls a missing name. Reader keeps its own high-water mark of
  `commands.seq` (the API notes it can go backwards) and opens a number only
  once `commands.seq` has reached it; unreadable/half-written → 15 s grace.
- Lease release writes an expired lease (no delete: NFS negative caching).
- `inactive` while idle → sleep, not park. Transient renew failures that
  outlast the key park as `invalid_key` (`parkedReason` has only the 4 codes).
  A 502 after the old key was deleted surfaces as `invalid_key` on retry.
- `inject` for a turn that already ended runs as its own turn
  (`<turnId>.<injectionId>`) and emits `queue-consumed`; `user-message` echoes
  of injects into a running turn carry the running turn's id.
- Logger drops `args=`/`text=`/`body=` tails and caps messages at 500 chars.
- Park waits ≤ 60 s for the current turn; SIGTERM during that can overrun 30 s.

Extension alignment: events use the root `turnId`. `message` context (active file,
mentions) needs a protocol + API change first (follow-up).

## Checks run

`npm ci`, `npm run build`, `lint`, `format:check`, `check`, `test` — all pass
locally. No PR CI for stacked PRs (`pr-checks.yml` only targets `main`). No
Haskell changes. Bundle run end to end with a real `jl4-lsp` and a scripted
ai-proxy (message → `l4__evaluate` → `3 → 42` → `done` → `stop`, exit 0).

## Problems and how they were solved

- Shutdown hung on `waitFor(null)` when a turn ended mid-shutdown; fixed.
- Concurrent `session.json` and `commands.done` writes lost updates
  (conversation id vanished); both now serialise their writes.
- LSP change notifications raced (`didClose` before `didChange`); they go out
  through one queue and versions bump synchronously.

## Open questions and follow-ups for later items

- Sessions API: may treat `state/commands.done` as harness-owned and ignore
  it. Nothing else new is written.
- Image item: entry point must pass `ECS_CONTAINER_METADATA_URI_V4` (validated
  as `http://169.254.170.2/v4/…`) for the lease task id; `jl4-lsp` at
  `/app/bin/jl4-lsp`.

## Where a reviewer should start

`src/runner.ts`, `src/command-reader.ts`, `src/key-chain.ts`, tests.

## Follow-up: repo layout and no approvals (2026-09-30)

Supersedes the earlier backup tools. Workspace root = `repo/`; the model
writes only in `data/` (session files, `jl4-lsp --cwd`) and `tmp/` (scratch,
committed), per `isModelWritableRepoPath` (#509); the rest is readable
metadata. Deleting a `data/` file in a turn first copies it to
`tmp/deleted/t-<turnId>/…` (regular files, link-safe dirs, first copy wins,
never cleared). A standing `<cloud-session-note>` rides on every prompt (no
core change). Rebased on #509 without approvals: every tool is allowed, no
`approval-request`/`pending-approval`/`approve`; `waiting` = `ask_user` only.
No git for the model: `.git` unreadable/unlistable/unsearchable (tested).
L4 on `data/` and `tmp/` alike: `--cwd repo/data` gives `IMPORT` data-first then
sibling lookup (verified with real `jl4-lsp`; `--cwd repo/` breaks tmp/→data/).
