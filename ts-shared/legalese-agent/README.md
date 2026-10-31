# @repo/legalese-agent

The Legalese AI agent core, with no `vscode` import: the chat loop
(`ChatService`), the ai-proxy client, the tool dispatcher and registry, the
built-in fs / L4 tools, the permission categories, and a file-backed
conversation store. The VS Code extension runs it in the extension host; the
cloud harness (`ts-apps/cloud-agent`, cloud-sessions spec §11) runs the same
code headless.

ESM, built with `tsc` to `dist/`. Tests: `npm test` (plain `node --test`,
fake ports in `test/fakes.ts`).

## Ports

Everything platform-specific goes through the interfaces in `src/ports.ts`:

| Port                | Used for                                                                                       | VS Code adapter (`ts-apps/vscode/src/ai/`)                      |
| ------------------- | ---------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| `AuthProvider`      | ai-proxy auth headers; the deployment URL in `<session-context>`                               | `AuthManager` (`../auth.ts`)                                    |
| `Workspace`         | path resolution and confinement, reads, creates, multi-file edits, deletes                     | `VsCodeWorkspace` (`vscode-workspace.ts`)                       |
| `L4Language`        | open document, diagnostics, directive results, references, semantic tokens, exported functions | `VsCodeL4Language` (`vscode-l4-language.ts`)                    |
| `UserInteraction`   | chat events, tool approvals, `meta__ask_user`, tool status — all with a `ToolCallContext`      | `WebviewUserInteraction` (`vscode-user-interaction.ts`)         |
| `PermissionPolicy`  | `never` / `ask` / `always` per category                                                        | `SettingsPermissionPolicy` (`vscode-permissions.ts`)            |
| `ConversationStore` | local transcript mirror                                                                        | `FileConversationStore` (this package) under `globalStorageUri` |
| `Logger`            | logging                                                                                        | `AiLogger` (`logger.ts`)                                        |
| `EditorContext`     | `<editor-context>` and the active L4 document                                                  | `VsCodeEditorContext` (`editor-context.ts`)                     |
| `ToolProvider`      | prefixed tool sources: l4-rules MCP (`McpToolClient`, this package), the user's MCP servers    | `VsCodeMcpTools` (`vscode-mcp.ts`)                              |

Headless hosts pass no `EditorContext` (or `NO_EDITOR_CONTEXT`) and can use
`fixedPermissionPolicy()`, `PendingInteractions` (approval / question
book-keeping scoped to a conversation and turn) and `DirectiveResultsCache`
(for the `l4/directiveResultsUpdated` notification).

## Wiring

```ts
const tools = new BuiltinTools(workspace, l4) // one per session
const dispatcher = new ToolDispatcher({
  logger,
  tools,
  permissions,
  interaction,
  providers: [mcpRules], // advertised after the built-ins, in order
})
const service = new ChatService({
  auth,
  store,
  proxy: new AiProxyClient({ auth, logger, endpoint }),
  logger,
  dispatcher,
  interaction,
  l4,
  editor, // optional
  extensionVersion,
})
await service.start(params) // events arrive at interaction.emit
```

## When L4 goes wrong

Models rarely write good L4 first time, so the tools assume the next edit may
be a mistake. All of this works from the language server's fields (severity,
source, code) and knows no L4 syntax: advice about the language doesn't belong
here.

- **Checked diagnostics.** `L4Language.getCheckedDiagnostics` answers for the
  file's current text, or reports `pending`. A pending result is never read as
  clean.
- **File state** (`tools/lsp.ts`). Parse failure, type errors, failed checks and
  clean, in that order. Compare with `isWorse`, not by error count: the parser
  stops at the first error, so a good fix can reveal more.
- **Multi-edit.** `fs__edit_file` takes up to `MAX_EDITS_PER_FILE` changes in
  `edits`. Each is applied and checked in turn, and the run stops at the first
  that fails, leaves the file worse, or can't be checked. Separate calls to one
  file in one response count as one run.
- **`EditGuard`** (`edit-guard.ts`). Tracks a turn's files: it blocks a file
  after `MAX_BROKEN_EDITS` broken edits with no progress, nudges once when a turn
  would end with compile errors of its own making, and writes the status line
  added to the reply. Failed checks only ever go in that status line: pushing a
  model to turn them green invites it to weaken them.
- **Permissions.** `content` on `fs__create_file` needs `fs.edit` as well as
  `fs.create`. `Workspace.requiresWriteApproval` makes writes to configuration
  files (`isSensitivePath`) ask, whatever the category settings say.

`BuiltinTools` owns the directive snapshot stores behind `l4__evaluate` and
`fs__edit_file`'s "what changed since I last reported" diffs, keyed by
conversation (the dispatcher passes `ToolCallContext.conversationId`) and by
file, so each conversation's model gets diffs relative to what it was last
told. Calls without a conversation use the instance's own stores.

## Cloud-session protocol (`@repo/legalese-agent/protocol`)

The contracts between the cloud harness, the extension and the Sessions API
(cloud-sessions spec §4.2, §6, §7.1, §8, §15.5), as TypeScript types plus
hand-written runtime validators. A validator is a `Check<T>`
(`(value, path) => T`) that returns a clean copy holding only the declared
fields, or throws `ProtocolError`; `tryParse(check, value)` returns a result
instead.

| Module                 | Contents                                                                                                                                                                                                                                                                                |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `protocol/common.ts`   | ids (`ULID_RE`, `AGENT_KEY_RE`), `SessionState`, `McpServerConfig`, `AttachmentRef`, `SeedBase`, size limits                                                                                                                                                                            |
| `protocol/files.ts`    | `SessionFile` (`session.json`), `LeaseFile`, `HeadFile`, cursors, `commands.seq`, `sessionPaths(sid)`, repo layout (`REPO_DATA_DIR`, `REPO_TMP_DIR`, `REPO_DELETED_DIR`, `MODEL_WRITABLE_REPO_DIRS`, `deletedCopyPath`, `isModelWritableRepoPath`), `isRepoDataPath`, `incoming/files/` |
| `protocol/events.ts`   | `CloudEvent` (`{ seq, ts, type, … }`: chat-service kinds + cloud-only types), chat ⇄ cloud mapping, JSONL chunk parsing                                                                                                                                                                 |
| `protocol/commands.ts` | `CloudCommand` (`{ id, ts, type, … }`), `clientCommand` (rejects internal `apply-bundle` / `add-files`), `MessageContext`, `McpCredentials`                                                                                                                                             |
| `protocol/api.ts`      | Sessions API requests/responses (incl. `AddFilesRequest`/`AddFilesResponse`), `GET /events` query helpers, access-token and agent-key routes, key-name helpers, error codes                                                                                                             |
| `protocol/sealed.ts`   | sealed secrets: `generateSealingKeyPair`, `seal`, `openSealed`, `encodeSealed`/`decodeSealed` (`v1.<epk>.<iv>.<ct>.<tag>`), `SealedEnvelope` (X25519 + HKDF-SHA256 + AES-256-GCM, context-bound)                                                                                        |

The Sessions API (in the `cloud-sessions` repo) mirrors these shapes; this package is
the reference.
