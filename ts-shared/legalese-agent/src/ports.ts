/**
 * Ports: everything platform-specific the agent core needs, as plain
 * interfaces. The core never imports `vscode` (or any other host API);
 * each host supplies adapters:
 *
 *   port               VS Code adapter (ts-apps/vscode/src/ai/)     cloud adapter (ts-apps/cloud-agent)
 *   AuthProvider       AuthManager (sealed session / API key)       agent key chain
 *   Workspace          VsCodeWorkspace (workspace fs + edits)       Node fs confined to repo/
 *   L4Language         VsCodeL4Language (language client)           jl4-lsp over stdio
 *   UserInteraction    WebviewUserInteraction (sidebar messenger)   events and commands
 *   PermissionPolicy   SettingsPermissionPolicy (VS Code settings)  fixed cloud policy
 *   ConversationStore  FileConversationStore (globalStorageUri)     session.json + server conversation
 *   Logger             AiLogger (OutputChannel)                     structured stdout, no content
 *   EditorContext      VsCodeEditorContext (active editor)          none (omit / NO_EDITOR_CONTEXT)
 *
 * Paths: the Workspace port speaks absolute file-system paths
 * (`fsPath`) for file operations and URI strings (`uri`) for anything
 * the language server keys on (diagnostics, directive results,
 * references). The adapter owns the conversion in both directions so
 * the URI format matches whatever its language client publishes.
 */
import type {
  AiChatMessage,
  AiConversation,
  AiConversationSummary,
  ExportedFunctionInfo,
} from 'jl4-client-rpc'
import type { ChatServiceEvent } from './events.js'
import type { PermissionCategory, PermissionValue } from './permissions.js'

// ── Logger ────────────────────────────────────────────────────────────

export interface Logger {
  info(message: string): void
  warn(message: string): void
  error(message: string, err?: unknown): void
  debug(message: string): void
}

// ── AuthProvider ──────────────────────────────────────────────────────

export interface AuthProvider {
  /** Headers attached to every ai-proxy request. Return `{}` when no
   *  credential is available; the client then fails fast with
   *  `unauthenticated` (or stamps a dev token in local mode). Extra
   *  headers (e.g. `X-Legalese-Session`) may ride along. */
  getAiAuthHeaders(): Promise<Record<string, string>>
  /** The user's jl4-service URL, surfaced to the model in the first-turn
   *  `<session-context>` message. Empty/undefined when not signed in. */
  getEffectiveServiceUrl(): string | undefined
}

// ── Workspace ─────────────────────────────────────────────────────────

/** A tool-supplied path resolved against the workspace. */
export interface ResolvedPath {
  /** Display path, relative to the preferred workspace root. */
  relative: string
  /** URI string for this file, in the format the language server uses. */
  uri: string
  /** Absolute file-system path. */
  fsPath: string
}

export interface WorkspaceStat {
  isDirectory: boolean
  isFile: boolean
}

export interface WorkspaceDirEntry {
  name: string
  isDirectory: boolean
  isFile: boolean
}

/** A text replacement expressed in offsets into the text returned by
 *  {@link Workspace.readDocument} for the same URI. */
export interface WorkspaceTextEdit {
  uri: string
  startOffset: number
  endOffset: number
  newText: string
}

export interface Workspace {
  /**
   * Resolve a model-supplied path (absolute or relative) to a file
   * inside the workspace. Throws an Error with a model-readable message
   * when the path escapes the workspace or no workspace is open.
   */
  resolvePath(p: string): ResolvedPath
  /** Display path for a URI (workspace-relative when inside it). */
  relativePath(uri: string): string
  /** File-system path for a URI published by the language server. */
  pathForUri(uri: string): string
  /** `null` when nothing exists at `fsPath`. */
  stat(fsPath: string): Promise<WorkspaceStat | null>
  readDirectory(fsPath: string): Promise<WorkspaceDirEntry[]>
  /** Read a file from disk as UTF-8. Throws when it doesn't exist. */
  readFile(fsPath: string): Promise<string>
  /**
   * Current text of a document as the editor sees it (may include
   * unsaved changes), with its line-ending style. Offsets in
   * {@link WorkspaceTextEdit} refer to this text.
   */
  readDocument(uri: string): Promise<{ text: string; eol: '\n' | '\r\n' }>
  /**
   * Create a new file with `content`, creating parent directories.
   * Must fail when the file exists. The write must be visible to
   * {@link readFile} and the language server when this resolves.
   * Hosts with an editor may also reveal the new file (VS Code opens a
   * tab, or the HTML preview for `.html`); headless hosts just write.
   */
  createFile(target: ResolvedPath, content: string): Promise<void>
  /**
   * Apply text replacements (possibly across several files) as one
   * change and persist them to disk. Throws when the host refuses.
   */
  applyEdits(edits: WorkspaceTextEdit[]): Promise<void>
  /** Delete a file. VS Code moves it to the Trash (`'trashed'`); a
   *  headless host removes it (`'deleted'`). */
  deleteFile(target: ResolvedPath): Promise<'trashed' | 'deleted'>
}

// ── L4Language ────────────────────────────────────────────────────────

export type DiagnosticSeverity = 'error' | 'warning' | 'info' | 'hint'

export interface L4Diagnostic {
  severity: DiagnosticSeverity
  /** 0-based line. */
  line: number
  message: string
  source?: string
  code?: string
}

/** One row of the jl4-lsp `l4/directiveResultsUpdated` payload. */
export type DirectiveResultRow = {
  directiveId: string
  prettyText: string
  success: boolean | null
  /** Full directive body — the source-range slice joined by '\n'. */
  body: string
}

export interface LspPosition {
  /** 0-based. */
  line: number
  /** 0-based UTF-16 column. */
  character: number
}

export interface LspLocation {
  uri: string
  range: { start: LspPosition; end: LspPosition }
}

export interface SemanticTokensSnapshot {
  /** Legend token type names, indexed by the token-type slot. */
  tokenTypes: string[]
  /** Delta-encoded 5-tuples, as in LSP `SemanticTokens.data`. */
  data: ArrayLike<number>
}

export interface L4Language {
  /**
   * Make sure the language server has the document open (triggering a
   * compile when cold) and return its line count.
   */
  openDocument(uri: string): Promise<{ lineCount: number; version: number }>
  /** Current diagnostics for `uri`, after giving a fresh open a moment
   *  to settle. */
  getDiagnostics(uri: string): Promise<L4Diagnostic[]>
  /** Latest `l4/directiveResultsUpdated` rows for `uri`, if any. */
  getDirectiveResults(uri: string): DirectiveResultRow[] | undefined
  /** Resolve on the next directive push for `uri`, or after the timeout. */
  awaitDirectiveResults(uri: string, timeoutMs: number): Promise<void>
  /** Cross-file references (the jl4-lsp references handler unions the
   *  anchor module's imports and importers). */
  findReferences(uri: string, position: LspPosition): Promise<LspLocation[]>
  /** Semantic tokens with their legend; `null` when unavailable. */
  getSemanticTokens(uri: string): Promise<SemanticTokensSnapshot | null>
  /** `l4/getExportedFunctions` for a document version. */
  getExportedFunctions(doc: {
    uri: string
    version: number
  }): Promise<ExportedFunctionInfo[]>
}

// ── EditorContext ─────────────────────────────────────────────────────

/** What the user is looking at, already resolved by the host. */
export interface EditorContextInfo {
  activeFile?: {
    path: string
    /** Adds a note that fs tools can't reach this file. */
    outsideWorkspace?: boolean
    /** 1-based. */
    cursorLine?: number
    /** 1-based, inclusive. */
    selectionLines?: { start: number; end: number }
  }
  /** Other visible L4 files. Omitted when they belong to a different
   *  window than the chip snapshot. */
  openFiles?: string[]
}

export interface EditorContext {
  /**
   * Describe the editor for the per-turn `<editor-context>` message.
   * `chip` is the active-file snapshot the client captured at send time
   * and wins over the live active editor. Return `null` for "nothing to
   * say".
   */
  describe(chip?: { name: string; path: string }): EditorContextInfo | null
  /** The active L4 document, for the first-turn `<workspace-exports>`
   *  message; `null` when no L4 file is active. */
  activeL4Document(): { uri: string; version: number } | null
}

/** EditorContext for headless hosts: no editor, no active file. */
export const NO_EDITOR_CONTEXT: EditorContext = {
  describe: () => null,
  activeL4Document: () => null,
}

// ── PermissionPolicy ──────────────────────────────────────────────────

export interface PermissionPolicy {
  getPermission(category: PermissionCategory): PermissionValue
  /** Persist a new value (e.g. after "always allow"). Optional: fixed
   *  policies don't support it. */
  setPermission?(
    category: PermissionCategory,
    value: PermissionValue
  ): Promise<void>
}

// ── UserInteraction ───────────────────────────────────────────────────

/** Where a tool call came from: approvals and questions are scoped to
 *  the conversation and turn that issued them. */
export interface ToolCallContext {
  /** Server conversation id, or the turn id before one is assigned. */
  conversationId: string
  turnId: string
}

export type ToolCallStatus = 'pending-approval' | 'running' | 'done' | 'error'

export interface UserInteraction {
  /** Every ChatService event (streamed text, tool rows, done, …). */
  emit(event: ChatServiceEvent): void
  /** Ask the user to allow a tool call the policy marks `ask`. */
  requestApproval(
    call: { callId: string; name: string; argsJson: string },
    ctx: ToolCallContext
  ): Promise<'allow' | 'deny'>
  /** `meta__ask_user`: resolve with the answer, `''` when skipped. */
  askUser(
    question: { callId: string; question: string; choices?: string[] },
    ctx: ToolCallContext
  ): Promise<string>
  /** Status update for a dispatched tool call. */
  notifyToolStatus(
    callId: string,
    status: ToolCallStatus,
    detail: { result?: string; error?: string } | undefined,
    ctx: ToolCallContext
  ): void
}

// ── ConversationStore ─────────────────────────────────────────────────

export interface ConversationStore {
  list(): Promise<AiConversationSummary[]>
  load(id: string): Promise<AiConversation | null>
  save(conv: AiConversation): Promise<void>
  delete(id: string): Promise<boolean>
  appendMessages(
    id: string,
    orgId: string,
    userId: string,
    model: string,
    titleHint: string,
    messages: AiChatMessage[],
    extensionVersion?: string,
    deploymentId?: string,
    apiBaseUrl?: string
  ): Promise<AiConversation>
  setTitle(id: string, title: string): Promise<void>
}

// ── Extra tool sources (MCP) ──────────────────────────────────────────

/** A client-declared tool in the OpenAI function-tool shape. */
export interface AiProxyTool {
  type: 'function'
  function: {
    name: string
    description?: string
    parameters: Record<string, unknown>
  }
}

/**
 * A source of prefixed tools beyond the built-ins — the l4-rules MCP
 * server (`l4-rules__`) or the user's own MCP servers (`vsmcp__`).
 * Advertised after the built-ins, in provider order.
 */
export interface ToolProvider {
  /** Tool-name prefix routed to this provider, e.g. `l4-rules__`. */
  readonly prefix: string
  listTools(): Promise<AiProxyTool[]> | AiProxyTool[]
  callTool(name: string, argsJson: string): Promise<string>
  /** `(deployId, fnName)` for deployed-rule tools, for display. */
  getToolTarget?(name: string): { deployId: string; fnName: string } | null
}
