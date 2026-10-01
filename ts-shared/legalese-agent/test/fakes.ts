/**
 * In-memory fakes for the agent-core ports, so the core runs in plain
 * Node without VS Code, a language server or a network.
 */
import * as path from 'node:path'
import type {
  ChatServiceEvent,
  DirectiveResultRow,
  L4Diagnostic,
  L4Language,
  Logger,
  LspLocation,
  ResolvedPath,
  SemanticTokensSnapshot,
  ToolCallContext,
  ToolCallStatus,
  UserInteraction,
  Workspace,
  WorkspaceDirEntry,
  WorkspaceStat,
  WorkspaceTextEdit,
} from '../src/index.js'
import { DirectiveResultsCache, PendingInteractions } from '../src/index.js'

export const ROOT = '/ws'

export function uriOf(fsPath: string): string {
  return `file://${fsPath}`
}

/** A workspace of in-memory files under {@link ROOT}. */
export class MemoryWorkspace implements Workspace {
  readonly files = new Map<string, string>()
  readonly created: string[] = []
  readonly deleted: string[] = []

  constructor(files: Record<string, string> = {}) {
    for (const [rel, text] of Object.entries(files)) {
      this.files.set(path.join(ROOT, rel), text)
    }
  }

  get(rel: string): string | undefined {
    return this.files.get(path.join(ROOT, rel))
  }

  resolvePath(p: string): ResolvedPath {
    if (!p) throw new Error('path is required')
    const abs = path.isAbsolute(p) ? p : path.resolve(ROOT, p)
    if (abs !== ROOT && !abs.startsWith(ROOT + '/')) {
      throw new Error(`Path is outside the workspace: ${p}`)
    }
    return {
      relative: path.relative(ROOT, abs) || path.basename(abs),
      uri: uriOf(abs),
      fsPath: abs,
    }
  }

  relativePath(uri: string): string {
    return path.relative(ROOT, this.pathForUri(uri))
  }

  pathForUri(uri: string): string {
    return uri.replace(/^file:\/\//, '')
  }

  private isDir(fsPath: string): boolean {
    if (fsPath === ROOT) return true
    for (const f of this.files.keys()) {
      if (f.startsWith(fsPath + '/')) return true
    }
    return false
  }

  async stat(fsPath: string): Promise<WorkspaceStat | null> {
    if (this.files.has(fsPath)) return { isDirectory: false, isFile: true }
    if (this.isDir(fsPath)) return { isDirectory: true, isFile: false }
    return null
  }

  async readDirectory(fsPath: string): Promise<WorkspaceDirEntry[]> {
    const names = new Map<string, boolean>()
    for (const f of this.files.keys()) {
      if (!f.startsWith(fsPath + '/')) continue
      const rest = f.slice(fsPath.length + 1)
      const [head, ...tail] = rest.split('/')
      names.set(head!, tail.length > 0 || names.get(head!) === true)
    }
    return [...names].map(([name, isDirectory]) => ({
      name,
      isDirectory,
      isFile: !isDirectory,
    }))
  }

  async readFile(fsPath: string): Promise<string> {
    const text = this.files.get(fsPath)
    if (text === undefined) throw new Error(`ENOENT: ${fsPath}`)
    return text
  }

  async readDocument(
    uri: string
  ): Promise<{ text: string; eol: '\n' | '\r\n' }> {
    const text = await this.readFile(this.pathForUri(uri))
    return { text, eol: text.includes('\r\n') ? '\r\n' : '\n' }
  }

  async createFile(target: ResolvedPath, content: string): Promise<void> {
    if (this.files.has(target.fsPath)) throw new Error('exists')
    this.files.set(target.fsPath, content)
    this.created.push(target.relative)
  }

  async applyEdits(edits: WorkspaceTextEdit[]): Promise<void> {
    const byUri = new Map<string, WorkspaceTextEdit[]>()
    for (const e of edits) {
      byUri.set(e.uri, [...(byUri.get(e.uri) ?? []), e])
    }
    for (const [uri, list] of byUri) {
      const fsPath = this.pathForUri(uri)
      let text = await this.readFile(fsPath)
      for (const e of [...list].sort((a, b) => b.startOffset - a.startOffset)) {
        text =
          text.slice(0, e.startOffset) + e.newText + text.slice(e.endOffset)
      }
      this.files.set(fsPath, text)
    }
  }

  async deleteFile(target: ResolvedPath): Promise<'trashed' | 'deleted'> {
    this.files.delete(target.fsPath)
    this.deleted.push(target.relative)
    return 'deleted'
  }
}

/** A scripted language server. */
export class FakeL4Language implements L4Language {
  readonly directives = new DirectiveResultsCache()
  diagnostics = new Map<string, L4Diagnostic[]>()
  references: LspLocation[] = []
  semanticTokens: SemanticTokensSnapshot | null = null
  exported: Array<{ name: string; returnType?: string }> = []
  opened: string[] = []

  constructor(private readonly workspace?: MemoryWorkspace) {}

  async openDocument(
    uri: string
  ): Promise<{ lineCount: number; version: number }> {
    this.opened.push(uri)
    const text = this.workspace
      ? await this.workspace.readFile(this.workspace.pathForUri(uri))
      : ''
    return { lineCount: text.split('\n').length, version: 1 }
  }

  async getDiagnostics(uri: string): Promise<L4Diagnostic[]> {
    return this.diagnostics.get(uri) ?? []
  }

  getDirectiveResults(uri: string): DirectiveResultRow[] | undefined {
    return this.directives.get(uri)
  }

  awaitDirectiveResults(uri: string, timeoutMs: number): Promise<void> {
    return this.directives.waitForNext(uri, Math.min(timeoutMs, 5))
  }

  async findReferences(): Promise<LspLocation[]> {
    return this.references
  }

  async getSemanticTokens(): Promise<SemanticTokensSnapshot | null> {
    return this.semanticTokens
  }

  async getExportedFunctions(): Promise<never[]> {
    return this.exported as never[]
  }
}

/** Records everything; approvals and answers are scripted. */
export class RecordingInteraction implements UserInteraction {
  readonly events: ChatServiceEvent[] = []
  readonly statuses: Array<{
    callId: string
    status: ToolCallStatus
    ctx: ToolCallContext
  }> = []
  readonly approvalRequests: Array<{ callId: string; ctx: ToolCallContext }> =
    []
  readonly pending = new PendingInteractions()
  /** When set, approvals resolve immediately with this decision. */
  autoDecision: 'allow' | 'deny' | undefined
  answerWith = ''

  emit(event: ChatServiceEvent): void {
    this.events.push(event)
  }

  requestApproval(
    call: { callId: string },
    ctx: ToolCallContext
  ): Promise<'allow' | 'deny'> {
    this.approvalRequests.push({ callId: call.callId, ctx })
    if (this.autoDecision) return Promise.resolve(this.autoDecision)
    return this.pending.requestApproval(call.callId, ctx)
  }

  async askUser(): Promise<string> {
    return this.answerWith
  }

  notifyToolStatus(
    callId: string,
    status: ToolCallStatus,
    _detail: unknown,
    ctx: ToolCallContext
  ): void {
    this.statuses.push({ callId, status, ctx })
  }
}

export const silentLogger: Logger = {
  info: () => undefined,
  warn: () => undefined,
  error: () => undefined,
  debug: () => undefined,
}

export function row(
  line: number,
  value: string,
  body = `#EVAL ${line}`
): DirectiveResultRow {
  return {
    directiveId: `${line}:1`,
    prettyText: value,
    success: true,
    body,
  }
}
