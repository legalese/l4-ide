# cloud-agent

The Legalese AI harness, headless, for one cloud session
([cloud-sessions spec](../../specs/todo/CLOUD-SESSIONS-SPEC.md) §5.4, §6.2,
§8, §11). It runs the same agent core as the VS Code extension
(`@repo/legalese-agent`) against a session folder on the S3 Files mount, with
`jl4-lsp` over stdio as the language server.

Built with esbuild into one file, `dist/cloud-agent.cjs` (`npm run build`).

## What it does

| Module                  | Does                                                                                                                                |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `runner.ts`             | Main loop: lease, key chain, command poll (1 s), one turn at a time, idle exit (10 min), `stop`, SIGTERM, parking; plugin hooks     |
| `event-log.ts`          | `state/events/<n>.jsonl` + `state/head.json` (temp + rename), 1 MB segments, 250 ms delta coalescing, seq recovery after a restart  |
| `command-reader.ts`     | `state/commands.seq` → `state/commands/<n>.json` by known names only; monotonic high-water mark; `state/commands.done` progress     |
| `lease.ts`              | `state/lease.json`, rewritten every 30 s with 90 s validity; refuses to run while another task's lease is live                      |
| `key-chain.ts`          | `AuthProvider` over the agent key chain: renew at start, at 5 min left and on 401; `X-Legalese-Session`; parks when the chain ends  |
| `node-workspace.ts`     | `Workspace` port confined to `repo/` (no `..`, no `.git`, no symlink escapes)                                                       |
| `jl4-lsp.ts`            | `L4Language` port over `jl4-lsp` (diagnostics cache, `l4/directiveResultsUpdated`, references, semantic tokens, exported functions) |
| `interaction.ts`        | `UserInteraction` port: events out, `approve` / `answer` commands in                                                                |
| `conversation-store.ts` | Keeps no transcript (the event log is the transcript); records the conversation id and title in `session.json`                      |

Later items add plugins (`RunnerPlugin` in `runner.ts`): git sync
(`cloud-agent-git`) and the user's MCP servers (`cloud-agent-mcp`).

## Environment (cloud)

`SESSION_ID` (ULID) and `AGENT_KEY` (`sk_…`) from the `RunTask` override;
`AI_PROXY_URL`, `MCP_URL`, `AUTH_URL` (https) and `LOG_LEVEL` from the task
definition. The user's folder is mounted at `/workspace`; the language server
is `/app/bin/jl4-lsp`. `AGENT_KEY` is removed from the environment before any
child process starts.

## Dev mode

Run a session folder against a local ai-proxy (default
`http://127.0.0.1:3000`, which accepts `Bearer dev-local`) and a local
`jl4-lsp`:

```sh
npm run build
SID=01J9Z3K4M5N6P7Q8R9S0T1V2W3
# terminal 1: create the folder (once) and run the harness
node dist/cloud-agent.cjs --dev --init --root /tmp/cs --session $SID --lsp "$(which jl4-lsp)"
# terminal 2: talk to it, and watch the events
node dist/cloud-agent.cjs send --root /tmp/cs --session $SID \
  '{"type":"message","turnId":"t1","text":"Write a rule for …"}'
tail -f /tmp/cs/sessions/$SID/state/events/1.jsonl
```

`send` queues any client command the way the Sessions API does (`answer`,
`approve`, `abort`, `stop`, …). Files the agent writes land in
`/tmp/cs/sessions/$SID/repo/`.

## Tests

`npm test` (fake language server, fake ai-proxy, temp dirs). Set
`JL4_LSP=/path/to/jl4-lsp` to also run the test against a real language
server.
