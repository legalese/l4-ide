# cloud-agent-runner — post-mortem

l4-ide · branch `thomasgorissen/cloud-agent-runner` · base `cloud-session-protocol` · [PR #513](https://github.com/legalese/l4-ide/pull/513) · 2026-09-28

## What was built

`ts-apps/cloud-agent` (esbuild → `dist/cloud-agent.cjs`): `runner.ts` (lease →
key chain → `session.json` running → `session-state`; 1 s command poll; queued
`message`/`rollback`/`apply-bundle`, immediate `inject`/`abort`/`approve`/
`answer`/`stop`/`mcp-credentials`; idle exit, `stop`, SIGTERM, parking;
`RunnerPlugin` hooks), `event-log.ts`, `command-reader.ts`, `lease.ts`,
`key-chain.ts` (+ 401 retry fetch wrapper), `node-workspace.ts`, `jl4-lsp.ts`,
`interaction.ts`, `conversation-store.ts`, `session-file.ts`, `config.ts`,
`main.ts` (`--dev`, `send`). 63 tests (fake LSP over in-process JSON-RPC, fake
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
- Logger drops `args=`/`text=`/`body=` tails (the core logs tool arguments)
  and caps messages at 500 chars.
- Park waits ≤ 60 s for the current turn; SIGTERM during that can overrun 30 s.

Coordinator checks (extension alignment): `started`/`git-committed`/
`rolled-back` use the `message` command's root `turnId` (ChatService emits
`started` once with it; sub-turns only `turn-spawn`) — confirmed. After an
`approval-request`, the dispatcher's status update emits `tool-call`
`running`/`error` once the decision lands — confirmed by a test. `message`
context (active file, mentions) not added: the protocol and the API mirror
strip unknown fields, so it needs a protocol + API change (follow-up).

## Checks run

`npm ci`, `npm run build`, `lint`, `format:check`, `check`, `test` — all pass
locally. No PR CI for stacked PRs (`pr-checks.yml` only targets `main`). No
Haskell changes. Bundle run end to end with a real `jl4-lsp` and a scripted
ai-proxy (message → `l4__evaluate` → `3 → 42` → `done` → `stop`, exit 0).

## Problems and how they were solved

- Shutdown hung when the turn finished between reading `this.working` and
  waiting on it (`waitFor(null)`); captured the promise first and made
  `shutdown` always resolve.
- Concurrent `session.json` and `commands.done` writes lost updates
  (conversation id vanished); both now serialise their writes.
- LSP change notifications raced (`didClose` before `didChange`); they go out
  through one queue and versions bump synchronously.

## Open questions and follow-ups for later items

- Sessions API: may treat `state/commands.done` as harness-owned and ignore
  it. Nothing else new is written.
- MCP item: `mcp-credentials` is an immediate command; replace credentials on
  every one (the extension re-sends per public key and per `auth-required`).
- Image item: entry point must pass `ECS_CONTAINER_METADATA_URI_V4` (validated
  as `http://169.254.170.2/v4/…`) for the lease task id; `jl4-lsp` at
  `/app/bin/jl4-lsp`.
- Cloud tool policy is fixed (defaults + `fs.delete: always`); the user's
  MCP permission settings aren't transferred.

## Where a reviewer should start

`src/runner.ts`, then `src/command-reader.ts` and `src/key-chain.ts`, then
`test/runner.test.ts`.
