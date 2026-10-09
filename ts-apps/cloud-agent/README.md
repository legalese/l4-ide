# cloud-agent

The Legalese AI harness, headless, for one cloud session
([cloud-sessions spec](../../specs/todo/CLOUD-SESSIONS-SPEC.md) §5.4, §6.2,
§8, §11). It runs the same agent core as the VS Code extension
(`@repo/legalese-agent`) against a session folder on the S3 Files mount, with
`jl4-lsp` over stdio as the language server.

Built with esbuild into one file, `dist/cloud-agent.cjs` (`npm run build`).

## What it does

| Module                  | Does                                                                                                                                                                                                                                                                                                                                            |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `runner.ts`             | Main loop: lease, key chain, command poll (1 s), one turn at a time, idle exit (10 min), `stop`, SIGTERM, parking; plugin hooks                                                                                                                                                                                                                 |
| `event-log.ts`          | `state/events/<n>.jsonl` + `state/head.json` (temp + rename), 1 MB segments, 250 ms delta coalescing, seq recovery after a restart                                                                                                                                                                                                              |
| `command-reader.ts`     | `state/commands.seq` → `state/commands/<n>.json` by known names only; monotonic high-water mark; `state/commands.done` progress                                                                                                                                                                                                                 |
| `lease.ts`              | `state/lease.json`, rewritten every 30 s with 90 s validity; refuses to run while another task's lease is live                                                                                                                                                                                                                                  |
| `key-chain.ts`          | `AuthProvider` over the agent key chain: renew at start, at 5 min left and on 401; `X-Legalese-Session`; parks when the chain ends                                                                                                                                                                                                              |
| `node-workspace.ts`     | `Workspace` port with the repo as root: `data/` (session files; `jl4-lsp` runs there), `tmp/` (the model's scratch space, committed); the model writes only there, the rest of the repo root is read-only metadata; no `..`, no `.git`, no symlink escapes. Deleting a `data/` file during a turn first copies it to `tmp/deleted/t-<turnId>/…` |
| `jl4-lsp.ts`            | `L4Language` port over `jl4-lsp` (diagnostics cache, `l4/directiveResultsUpdated`, references, semantic tokens, exported functions) One instance (`--cwd repo/data`) serves `data/` and `tmp/`; written `.l4` files stay open and other open files are re-sent after a change, so importers see edited modules.                                 |
| `interaction.ts`        | `UserInteraction` port: events out, `answer` commands in; no tool approvals (every tool is allowed)                                                                                                                                                                                                                                             |
| `conversation-store.ts` | Keeps no transcript (the event log is the transcript); records the conversation id and title in `session.json`                                                                                                                                                                                                                                  |

Plugins (`RunnerPlugin` in `runner.ts`):

- `git-sync.ts` (§9.1, §9.4): a "Seed" commit at start if the repo has none;
  after each turn that changed files, a commit whose subject is a one-line
  summary of the turn from ai-proxy's summize pipeline (hard 5 s limit; the
  prompt's first line on a timeout, error or unusable answer), with
  `Prompt: <first line>` as the body and a `Turn-Id: <turnId>` trailer, and
  `git-committed { turnId, sha, parent, summary }`; `state/git/main.bundle`
  rewritten (temp + rename) after every commit and at start; `apply-bundle`
  merges `state/git/incoming/<ulid>.bundle` (`local ^main`) into `main`
  (`local-merged` / `local-merge-conflict`, the merge aborted on conflict);
  `rollback` restores the parent of the turn's commit and commits "Roll back: …"
  (`rolled-back`); `git gc` on sleep. `tmp/` and its `tmp/deleted/` copies are
  committed like the rest; if the Sessions API sweep cleared `tmp/` of an
  abandoned session, the next start commits that ("Clear tmp of abandoned
  session"). git runs with hooks and fsmonitor
  disabled, `core.createObject=rename` and `gc.auto=0` (`git.ts`).
- `mcp-servers.ts` (§6.4): an ephemeral X25519 key pair at start, whose public
  key rides on every running/busy/waiting `session-state` event;
  `mcp-credentials` is opened with `mcpCredentialsContext(sid)`, validated,
  and merged by server name (re-sent credentials replace the old ones). The
  HTTP servers from `session.json` connect once their credentials arrive
  (streamable HTTP, JSON or SSE responses) and appear as `vsmcp__<server>_<tool>`
  tools. A 401/403 or an expired token emits `auth-required { reason: "mcp",
server }` once per credential. stdio servers never reach a cloud session.

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
`abort`, `stop`, …). Files the agent writes land in
`/tmp/cs/sessions/$SID/repo/` (`data/`, `tmp/`).

## Release and image

This repository only publishes the harness. The release build
(`.github/workflows/main-tag.yml`) bundles and tests it and attaches
`cloud-agent.cjs` and `jl4-lsp-linux-arm64`, each with a `.sha256`, to the
`l4-ide-build-<n>` release.

The image (Dockerfile, entry point, smoke test) and its rollout live in
jl4-auth-proxy under `cloud-sessions/agent-image/`, next to the task
definition the Sessions API registers. Its `rollout-cloud-agent.yml` builds
`legalese-cloud-agent:<tag>` from a release tag and switches new sessions to
it; rolling back is a run with the previous tag. This repository has no AWS
access.

What the image guarantees the harness: the language server at
`/app/bin/jl4-lsp`, the bundle at `/app/cloud-agent.cjs`, user `1000:1000`,
`HOME=/home/agent`, the session mount at `/workspace`, and an environment
reduced to `SESSION_ID`, `AGENT_KEY`, `AI_PROXY_URL`, `MCP_URL`, `AUTH_URL`,
`LOG_LEVEL` (plus the Fargate `ECS_CONTAINER_METADATA_URI_V4`).

## Tests

`npm test` (fake language server, fake ai-proxy, temp dirs). Set
`JL4_LSP=/path/to/jl4-lsp` to also run the test against a real language
server.
