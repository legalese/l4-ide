# cloud-agent

The Legalese AI harness, headless, for one cloud session. It runs the same
agent core as the VS Code extension (`@repo/legalese-agent`) against a mounted
session folder, with `jl4-lsp` over stdio as the language server.

Built with esbuild into one file, `dist/cloud-agent.cjs` (`npm run build`).

## What it does

| Module                  | Does                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `runner.ts`             | Main loop: run check and lease, key chain, command poll (1 s), one turn at a time, idle exit (10 min), `stop`, SIGTERM, parking; plugin hooks                                                                                                                                                                                                                                                                                  |
| `event-log.ts`          | `state/events/<n>.jsonl` + `state/head.json` (temp + rename), 1 MB segments, 250 ms delta coalescing, seq recovery after a restart                                                                                                                                                                                                                                                                                             |
| `command-reader.ts`     | `state/commands.seq` → `state/commands/<n>.json` by known names only; monotonic high-water mark; `state/commands.done` progress                                                                                                                                                                                                                                                                                                |
| `lease.ts`              | Run records: the boot check, run n's lease `state/runs/<n>.lease.json` (30 s / 90 s) and the write fence                                                                                                                                                                                                                                                                                                                       |
| `key-chain.ts`          | `AuthProvider` over the agent key chain: renew at start, at 5 min left and on 401 (or the AI service's 403 `invalid-credentials`), at least 60 s apart; `X-Legalese-Session`; any 4xx from renew except 429, and `chain_lost` with any status, ends the chain and the runner parks (5xx, 429 and network errors are retried); any other exit, an early one included, ends the chain (`POST /auth/agent-token/end`)             |
| `node-workspace.ts`     | `Workspace` port with the repo as root: `data/` (session files; `jl4-lsp` runs there), `tmp/` (the model's scratch space, committed); the model writes only there, the rest of the repo root is read-only metadata; no `..`, no `.git` (by name or real path), no symlink escapes, and no writes or deletes through a symlinked directory. Deleting a `data/` file during a turn first copies it to `tmp/deleted/t-<turnId>/…` |
| `jl4-lsp.ts`            | `L4Language` port over `jl4-lsp` (diagnostics cache, `l4/directiveResultsUpdated`, references, semantic tokens, exported functions) One instance (`--cwd repo/data`) serves `data/` and `tmp/`; written `.l4` files stay open and other open files are re-sent after a change, so importers see edited modules.                                                                                                                |
| `interaction.ts`        | `UserInteraction` port: events out, `answer` commands in; no tool approvals (every tool is allowed)                                                                                                                                                                                                                                                                                                                            |
| `conversation-store.ts` | Keeps no transcript (the event log is the transcript); records the conversation id and title in `session.json`                                                                                                                                                                                                                                                                                                                 |

Plugins (`RunnerPlugin` in `runner.ts`):

- `git-sync.ts`: a "Seed" commit at start if the repo has none;
  after each turn that changed files, a commit whose subject is a one-line
  summary of the turn from the AI service's summize model (hard 5 s limit; the
  prompt's first line on a timeout, error or unusable answer), with
  `Prompt: <first line>` as the body and a `Turn-Id: <turnId>` trailer, and
  `git-committed { turnId, sha, parent, summary }`; `state/git/main.bundle`
  rewritten (temp + rename) after every commit and at start; `apply-bundle`
  merges `state/git/incoming/<ulid>.bundle` (`local ^main`) into `main`
  (`local-merged` / `local-merge-conflict`, the merge aborted on conflict)
  and then deletes the bundle;
  `rollback` restores the parent of the turn's commit and commits "Roll back: …"
  (`rolled-back`); `git gc` on sleep. `tmp/` and its `tmp/deleted/` copies are
  committed like the rest. git runs with hooks and fsmonitor
  disabled, `core.symlinks=false` (a pushed symlink checks out as a plain
  file), `core.createObject=rename` and `gc.auto=0` (`git.ts`).
- `mcp-servers.ts`: an ephemeral X25519 key pair at start, whose public
  key rides on every running/busy/waiting `session-state` event;
  `mcp-credentials` is opened with `mcpCredentialsContext(sid)`, validated,
  and merged by server name (re-sent credentials replace the old ones). The
  HTTP servers from `session.json` connect once their credentials arrive
  (streamable HTTP, JSON or SSE responses) and appear as `vsmcp__<server>_<tool>`
  tools. A 401/403 or an expired token emits `auth-required { reason: "mcp",
server }` once per credential. stdio servers never reach a cloud session.

## Run records

The Sessions API decides who runs a session, and starts it with
`SESSION_RUN=<n>`. The harness only proves it is the current run:

- **At boot** `runs/<n>.json` must exist, `runs/<n+1>.json` must not, and
  run n's lease must have more than 15 s left; otherwise it exits 0 at once
  ("superseded"), writing nothing.
- **Its lease** is rewritten (temp file + rename) at boot, every 30 s and on
  state changes, with 90 s validity and its task id; each renewal also
  checks for `runs/<n+1>.json`.
- **Every write** (events, `head.json`, `commands.done`, `session.json`,
  git, workspace files, added files, the lease) goes through one fence:
  allowed only while the last lease written is valid by this clock for 15 s
  more. A failed or late renewal stops all writes before the lease runs out,
  and the API creates run n+1 only after it has. On a refused write, or a
  newer run found, the harness stops at once: no flush, no final lease, no
  git; it ends the key chain and exits 1 ("superseded").
- **A normal exit** writes the lease expired as its very last write, then
  closes the fence.

`--dev` plays the API: it claims the next run the same way and runs as it.

## Environment (cloud)

`SESSION_ID` (ULID), `SESSION_RUN` (the run, `^[1-9][0-9]{0,8}$`) and
`AGENT_KEY` (`sk_…`) for this run; `AI_URL`, `MCP_URL`, `AUTH_URL` (https) and
`LOG_LEVEL` for every run; and an optional `TASK_ID`, which names the task in
its lease. The user's folder is mounted at `/workspace`; the language server
is `/app/bin/jl4-lsp`. `AGENT_KEY` is removed from the environment before any
child process starts.

## Dev mode

Run a session folder against a local AI server (default
`http://127.0.0.1:3000`, which accepts `Bearer dev-local`) and a local
`jl4-lsp`:

```sh
npm run build
SID=01J9Z3K4M5N6P7Q8R9S0T1V2W3
# terminal 1: create the folder (once), claim the next run and run the harness
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

What the harness expects from its image: the language server at
`/app/bin/jl4-lsp`, the session mount at `/workspace`, and an environment
reduced to `SESSION_ID`, `SESSION_RUN`, `AGENT_KEY`, `AI_URL`, `MCP_URL`, `AUTH_URL`,
`LOG_LEVEL` and optionally `TASK_ID`.

## Tests

`npm test` (fake language server, fake AI server, temp dirs). Set
`JL4_LSP=/path/to/jl4-lsp` to also run the test against a real language
server.
