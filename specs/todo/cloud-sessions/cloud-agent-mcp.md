# cloud-agent-mcp — post-mortem

l4-ide · branch `thomasgorissen/cloud-agent-mcp` · base `cloud-agent-git` · [PR #515](https://github.com/legalese/l4-ide/pull/515) · 2026-09-28

## What was built

`ts-apps/cloud-agent/src/mcp-servers.ts`: a `RunnerPlugin` + `ToolProvider`.
At start an ephemeral X25519 key pair (`generateSealingKeyPair`); the public
key rides on every running/busy/waiting `session-state` event.
`mcp-credentials` (immediate, not queued) → `openSealed(…,
mcpCredentialsContext(sid))` → `mcpCredentials` validation → merged by server
name. Servers from `session.json` connect once credentialed (streamable HTTP,
JSON or SSE responses, `Mcp-Session-Id`, no redirects) and appear as
`vsmcp__<server16>_<tool40>` tools, filtered by `enabledTools`. 401/403,
calls past `expiresAt`, and an expiry timer emit `auth-required { reason:
"mcp", server }` once per credential. 6 unit tests + 1 runner test (80 in the
package).

## Spec sections covered, and deviations (with reasons)

§6.4, §11 (cloud tool policy for MCP). Deviations:

- Credentials merge per server (each named server's headers replaced), so a
  refresh for one server keeps the others; repeats are harmless (the
  extension re-sends per public key and per `auth-required`).
- The legacy HTTP+SSE transport (GET stream + POST endpoint) isn't
  implemented; `transport: "sse"` servers are called over streamable HTTP,
  as the extension does.
- MCP calls follow the cloud policy (`mcp.vscode: always`); the user's local
  permission settings aren't transferred.
- Unopenable blobs (old key, other session, tampered) are logged and ignored,
  no event.

## Checks run

`npm ci`, `build`, `lint`, `format:check`, `check`, `test` — all pass
locally (80 tests). No PR CI for stacked PRs. No Haskell changes. No live
MCP server was contacted (fake fetch in tests; `session.json` requires
https URLs).

## Problems and how they were solved

- The runner called `beforeExit` on plugins whose `start` never ran (chain
  ended at the first renewal → git plugin threw); fixed in the runner
  (#513, "only plugins that started get beforeExit") and rebased up the stack.

## Open questions and follow-ups for later items

- Extension (`cloud-sessions-client`): seal the JSON
  `{ servers: [{ name, headers, expiresAt? }] }` with
  `seal(publicKey, …, mcpCredentialsContext(sid))` and send
  `encodeSealed(…)`; `name` must match
  `session.json` `mcpServers[].name`. Use the newest `publicKey` from any
  running/busy/waiting `session-state` event; a restarted harness has a new
  key and needs the credentials again.
- Tool names match the extension's `vsmcp__<server>_<tool>` wire names, so
  history rendering is shared.

## Where a reviewer should start

`src/mcp-servers.ts` (`handleCommand`, `rpc`, `reportAuth`), then
`test/mcp-servers.test.ts`.

## Follow-up (2026-09-30)

Rebased onto #509 without approvals and the runner's `data/`/`tmp/` layout; no
changes here beyond test merges.
