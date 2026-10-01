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

`BuiltinTools` owns the directive snapshot stores behind `l4__evaluate` and
`fs__edit_file`'s "what changed since I last reported" diffs, keyed by
conversation (the dispatcher passes `ToolCallContext.conversationId`) and by
file, so each conversation's model gets diffs relative to what it was last
told. Calls without a conversation use the instance's own stores.
