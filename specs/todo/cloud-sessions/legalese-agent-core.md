# legalese-agent-core — post-mortem

l4-ide · branch `thomasgorissen/legalese-agent-core` · base `vscode-min-1-106` · [PR #508](https://github.com/legalese/l4-ide/pull/508) · 2026-09-28

## What was built

- New package `ts-shared/legalese-agent` (`@repo/legalese-agent`, ESM, tsc →
  `dist/`, `node --test`), no `vscode` import. Moved in with `git mv`:
  `chat-service`, `ai-proxy-client`, `tool-dispatcher`, `tool-registry`,
  `permissions`, `conversation-store` (→ `FileConversationStore`),
  `mcp-client` (`McpToolClient`), `tools/{fs,directive-snapshot,l4-evaluate,
lsp,refactor,ask-user}`. New: `ports.ts`, `events.ts`, `context-messages.ts`,
  `pending-interactions.ts`, `text-positions.ts`, `tools/builtin-tools.ts`.
- Ports: `AuthProvider`, `Workspace`, `L4Language`, `UserInteraction`,
  `PermissionPolicy`, `ConversationStore`, `Logger`, `EditorContext`, plus
  `ToolProvider` for prefixed MCP tool sources.
- VS Code adapters in `ts-apps/vscode/src/ai/`: `VsCodeWorkspace`,
  `VsCodeL4Language`, `VsCodeEditorContext`, `SettingsPermissionPolicy`,
  `WebviewUserInteraction`, `ai-endpoint.ts`, `rename-command.ts`; `AiLogger`
  and `VsCodeMcpTools` implement the ports. `extension.mts`, `register.ts`,
  `chat-participant.ts`, `lm-tools.ts` rewired.
- 28 core unit tests over fake ports (a full ChatService turn with a stubbed
  fetch, dispatcher, pending interactions, tools, positions).

## Spec sections covered, and deviations (with reasons)

§11 including both extension fixes:

- Approvals/questions are scoped: `AiChatStart` cancels only that
  conversation's pending interactions, `AiChatAbort` only that turn's
  (`PendingInteractions`).
- Directive snapshot stores belong to a `BuiltinTools` instance (sidebar
  dispatcher, `@legalese` participant, LM tool, rename command each have one);
  the directive-result cache belongs to the `L4Language` adapter.

Deviations: "per session" in VS Code = per consumer, not per conversation.
Refused-edit error texts changed slightly. `<session-context>` still says
`l4VscodeExtensionVersion`. `vscode-mcp.ts` stays in the extension.

## Checks run

`npm ci && npm run build && npm run lint && npm run format:check && npm run
check && npm test` — all pass locally. **No PR CI:** `pr-checks.yml` only runs
for PRs into `main`, so stacked PRs get none; the same commands were run
locally. No Haskell changes. The extension wasn't exercised in an Extension
Development Host (no GUI here) — see the manual test in the PR.

## Problems and how they were solved

- Tools used `vscode.Range`/`positionAt`; the core now works in offsets with
  its own `positionAt`/`offsetAt` (VS Code line-break rules), and the
  adapter converts back. Rename edits are offset edits sorted per file.

## Open questions and follow-ups for later items

- Runner: implement `Workspace` confined to `repo/` (apply `applyEdits`
  per file from the highest offset), `L4Language` over `jl4-lsp` stdio
  feeding a `DirectiveResultsCache`, `UserInteraction` over events/commands
  (reuse `PendingInteractions`), `fixedPermissionPolicy()`,
  `McpToolClient({ getLocalUrl: () => MCP_URL, getHeaders })`.
- Unverified in a live VS Code: approvals across two conversations.

## Where a reviewer should start

`ts-shared/legalese-agent/src/ports.ts`, then `extension.mts` wiring, then
`register.ts` (approval scoping), then the `tools/fs.ts` diff.
