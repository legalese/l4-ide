# vscode-min-1-106 — post-mortem

l4-ide · branch `thomasgorissen/vscode-min-1-106` · base `main` · [PR #507](https://github.com/legalese/l4-ide/pull/507) · 2026-09-28

## What was built

- `ts-apps/vscode/package.json`: `engines.vscode` and `@types/vscode`
  `^1.95.0` → `^1.106.0`.
- `package-lock.json`: one hoisted `@types/vscode` **1.106.1** (was 1.99.1).
- Two comments that named the 1.95 floor (`lm-tools.ts`, `mcp-proxy.ts`)
  updated. No code changes.

## Spec sections covered, and deviations (with reasons)

§9.3, §15.1, R13. One choice beyond the spec: a plain `npm install` resolved
`^1.106.0` to `@types/vscode` 1.138, which would let code use APIs newer than
the engines floor without a type error. The lockfile pins the resolved copy
to 1.106.1 (the range stays `^1.106.0`), shared with `jl4-client-rpc`
(`^1.99.1`).

## Checks run

`npm ci`, `npm run build`, `npm test`, `npm run lint`, `npm run format` — all
pass locally. PR CI (TypeScript Checks, Nix Flake Check) green; Haskell/WASM
jobs skipped (no Haskell changes).

## Problems and how they were solved

Only the lockfile resolution above.

## Open questions and follow-ups for later items

- `mcp-proxy.ts` still carries structural stand-ins for the MCP server
  definition provider API (1.101+); they can now become the real
  `vscode.*` types. Left out to keep this PR to the bump.
- Runtime feature detection (`vscode.lm.registerTool`, MCP provider) is kept
  for forks.

## Where a reviewer should start

The two-line `package.json` diff and the `@types/vscode` entry in the lockfile.
