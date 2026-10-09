import { spawn, type ChildProcess } from 'node:child_process'
import { promises as fs } from 'node:fs'
import rpc from 'vscode-jsonrpc/node.js'
import type { MessageConnection } from 'vscode-jsonrpc'
import {
  DirectiveResultsCache,
  type DiagnosticSeverity,
  type DirectiveResultRow,
  type L4Diagnostic,
  type L4Language,
  type Logger,
  type LspLocation,
  type LspPosition,
  type SemanticTokensSnapshot,
} from '@repo/legalese-agent'
import type { ExportedFunctionInfo } from 'jl4-client-rpc'
import {
  normalizeFileUri,
  uriForPath,
  type WorkspaceChangeListener,
} from './node-workspace.js'

/** How long to wait for the first diagnostics after a change. */
const DIAGNOSTICS_TIMEOUT_MS = 20_000
/** After the first publish, how long to wait for follow-up publishes
 *  (jl4-lsp may publish parse and type-check results separately). */
const DIAGNOSTICS_SETTLE_MS = 300
const REQUEST_TIMEOUT_MS = 60_000

interface LspDiagnostic {
  range: { start: LspPosition; end: LspPosition }
  severity?: number
  code?: string | number
  source?: string
  message: string
}

interface OpenDoc {
  version: number
  lineCount: number
  /** What the server has, to re-send when a dependency changes. */
  text: string
}

interface DiagnosticsEntry {
  diagnostics: LspDiagnostic[]
  /** Monotonic counter of publishes for this URI. */
  generation: number
}

/**
 * {@link L4Language} port over a `jl4-lsp` child process speaking LSP
 * over stdio (`vscode-jsonrpc/node`), spec §11.
 *
 * - Documents are opened with `didOpen` from disk; writes made through
 *   the workspace arrive via {@link WorkspaceChangeListener} and become
 *   `didChange` (open documents) plus `workspace/didChangeWatchedFiles`
 *   (so importers recompile).
 * - Diagnostics are cached from `textDocument/publishDiagnostics`.
 * - `l4/directiveResultsUpdated` feeds a {@link DirectiveResultsCache}.
 * - References, semantic tokens and `l4/getExportedFunctions` are plain
 *   requests; the semantic-token legend comes from `initialize`.
 * - Server-to-client requests (`client/registerCapability`,
 *   `workspace/configuration`, progress) get empty answers.
 */
export class Jl4Lsp implements L4Language, WorkspaceChangeListener {
  private readonly directives = new DirectiveResultsCache()
  private readonly open = new Map<string, OpenDoc>()
  private readonly diagnostics = new Map<string, DiagnosticsEntry>()
  private readonly diagnosticWaiters = new Map<string, Array<() => void>>()
  /** Publish generation at the time of the last change we sent. */
  private readonly changedAt = new Map<string, number>()
  private tokenTypes: string[] = []
  private exited = false
  private disposing = false
  /** Change notifications go out in order. */
  private notifying: Promise<void> = Promise.resolve()

  private constructor(
    private readonly connection: MessageConnection,
    private readonly logger: Logger,
    private readonly process?: ChildProcess
  ) {}

  /**
   * Spawn `command --cwd <root>` and initialise it. `env` is the child's
   * whole environment: pass a minimal one, never the harness's own
   * (which held `AGENT_KEY`).
   */
  static async spawn(opts: {
    command: string
    root: string
    logger: Logger
    env: NodeJS.ProcessEnv
    args?: string[]
  }): Promise<Jl4Lsp> {
    const child = spawn(
      opts.command,
      [...(opts.args ?? []), '--cwd', opts.root],
      {
        cwd: opts.root,
        env: opts.env,
        stdio: ['pipe', 'pipe', 'pipe'],
      }
    )
    const spawned = new Promise<void>((resolve, reject) => {
      child.once('spawn', () => resolve())
      child.once('error', reject)
    })
    await spawned
    child.stderr?.setEncoding('utf8')
    child.stderr?.on('data', (chunk: string) => {
      // jl4-lsp logs diagnostics about the user's files; keep it at
      // debug and short.
      opts.logger.debug(`jl4-lsp stderr: ${chunk.slice(0, 200).trim()}`)
    })
    const connection = rpc.createMessageConnection(
      new rpc.StreamMessageReader(child.stdout!),
      new rpc.StreamMessageWriter(child.stdin!)
    )
    const lsp = new Jl4Lsp(connection, opts.logger, child)
    child.once('exit', (code, signal) => {
      lsp.exited = true
      const msg = `jl4-lsp exited (code=${code}, signal=${signal})`
      if (lsp.disposing) opts.logger.info(msg)
      else opts.logger.warn(msg)
      connection.dispose()
    })
    await lsp.initialize(uriForPath(opts.root))
    return lsp
  }

  /** Wrap an existing connection (tests). */
  static async connect(
    connection: MessageConnection,
    rootUri: string,
    logger: Logger
  ): Promise<Jl4Lsp> {
    const lsp = new Jl4Lsp(connection, logger)
    await lsp.initialize(rootUri)
    return lsp
  }

  get running(): boolean {
    return !this.exited
  }

  private async initialize(rootUri: string): Promise<void> {
    const c = this.connection
    c.onNotification(
      'textDocument/publishDiagnostics',
      (params: { uri: string; diagnostics: LspDiagnostic[] }) => {
        const uri = normalizeFileUri(params.uri)
        const prev = this.diagnostics.get(uri)
        this.diagnostics.set(uri, {
          diagnostics: params.diagnostics ?? [],
          generation: (prev?.generation ?? 0) + 1,
        })
        const waiters = this.diagnosticWaiters.get(uri)
        if (waiters) {
          this.diagnosticWaiters.delete(uri)
          for (const w of waiters) w()
        }
      }
    )
    c.onNotification(
      'l4/directiveResultsUpdated',
      (params: { uri: string; results: DirectiveResultRow[] }) => {
        if (!params || typeof params.uri !== 'string') return
        this.directives.record(
          normalizeFileUri(params.uri),
          Array.isArray(params.results) ? params.results : []
        )
      }
    )
    c.onNotification((method: string) => {
      this.logger.debug(`jl4-lsp notification ${method}`)
    })
    c.onRequest((method: string, params: unknown) => {
      if (method === 'workspace/configuration') {
        const items = (params as { items?: unknown[] } | undefined)?.items
        return Array.isArray(items) ? items.map(() => null) : []
      }
      return null
    })
    c.listen()
    const result = (await this.withTimeout(
      c.sendRequest('initialize', {
        processId: process.pid,
        clientInfo: { name: 'legalese-cloud-agent' },
        rootUri,
        workspaceFolders: [{ uri: rootUri, name: 'repo' }],
        capabilities: {
          textDocument: {
            synchronization: { didSave: false, dynamicRegistration: false },
            publishDiagnostics: { relatedInformation: false },
            references: {},
            semanticTokens: {
              requests: { full: true },
              tokenTypes: [],
              tokenModifiers: [],
              formats: ['relative'],
            },
          },
          workspace: {
            didChangeWatchedFiles: { dynamicRegistration: true },
            configuration: true,
            workspaceFolders: true,
          },
          window: { workDoneProgress: false },
        },
      }),
      'initialize'
    )) as {
      capabilities?: {
        semanticTokensProvider?: { legend?: { tokenTypes?: string[] } }
      }
    }
    this.tokenTypes =
      result?.capabilities?.semanticTokensProvider?.legend?.tokenTypes ?? []
    await c.sendNotification('initialized', {})
  }

  // ── L4Language ─────────────────────────────────────────────────────

  async openDocument(
    uri: string
  ): Promise<{ lineCount: number; version: number }> {
    const key = normalizeFileUri(uri)
    const existing = this.open.get(key)
    if (existing) {
      return { lineCount: existing.lineCount, version: existing.version }
    }
    this.assertRunning()
    const text = await fs.readFile(new URL(key), 'utf8')
    const doc = { version: 1, lineCount: lineCount(text), text }
    this.open.set(key, doc)
    this.changedAt.set(key, this.diagnostics.get(key)?.generation ?? 0)
    this.enqueue(
      () =>
        this.connection.sendNotification('textDocument/didOpen', {
          textDocument: { uri: key, languageId: 'l4', version: 1, text },
        }),
      'open'
    )
    await this.notifying
    return { lineCount: doc.lineCount, version: doc.version }
  }

  async getDiagnostics(uri: string): Promise<L4Diagnostic[]> {
    const key = normalizeFileUri(uri)
    await this.openDocument(key)
    const since = this.changedAt.get(key) ?? 0
    if ((this.diagnostics.get(key)?.generation ?? 0) <= since) {
      await this.waitForDiagnostics(key, DIAGNOSTICS_TIMEOUT_MS)
    }
    // Let a follow-up publish (type check after parse) land.
    await this.waitForDiagnostics(key, DIAGNOSTICS_SETTLE_MS)
    return (this.diagnostics.get(key)?.diagnostics ?? []).map((d) => ({
      severity: severityName(d.severity),
      line: d.range?.start?.line ?? 0,
      message: d.message,
      source: d.source,
      code: d.code === undefined ? undefined : String(d.code),
    }))
  }

  getDirectiveResults(uri: string): DirectiveResultRow[] | undefined {
    return this.directives.get(normalizeFileUri(uri))
  }

  awaitDirectiveResults(uri: string, timeoutMs: number): Promise<void> {
    return this.directives.waitForNext(normalizeFileUri(uri), timeoutMs)
  }

  async findReferences(
    uri: string,
    position: LspPosition
  ): Promise<LspLocation[]> {
    const key = normalizeFileUri(uri)
    await this.openDocument(key)
    const res = (await this.withTimeout(
      this.connection.sendRequest('textDocument/references', {
        textDocument: { uri: key },
        position,
        context: { includeDeclaration: true },
      }),
      'references'
    )) as LspLocation[] | null
    return (res ?? []).map((l) => ({ uri: l.uri, range: l.range }))
  }

  async getSemanticTokens(uri: string): Promise<SemanticTokensSnapshot | null> {
    const key = normalizeFileUri(uri)
    await this.openDocument(key)
    if (this.tokenTypes.length === 0) return null
    const res = (await this.withTimeout(
      this.connection.sendRequest('textDocument/semanticTokens/full', {
        textDocument: { uri: key },
      }),
      'semanticTokens'
    )) as { data?: number[] } | null
    if (!res?.data) return null
    return { tokenTypes: this.tokenTypes, data: res.data }
  }

  async getExportedFunctions(doc: {
    uri: string
    version: number
  }): Promise<ExportedFunctionInfo[]> {
    const key = normalizeFileUri(doc.uri)
    await this.openDocument(key)
    const res = (await this.withTimeout(
      this.connection.sendRequest('l4/getExportedFunctions', {
        verDocId: { uri: key, version: doc.version },
      }),
      'getExportedFunctions'
    )) as { functions?: ExportedFunctionInfo[] } | null
    return res?.functions ?? []
  }

  // ── WorkspaceChangeListener ────────────────────────────────────────

  /**
   * A file changed on disk. Written `.l4` files are kept open in the
   * server's VFS (opened here if they weren't): jl4-lsp doesn't re-read
   * an imported module from disk on its own, so an importer would keep
   * seeing the old version otherwise.
   */
  onDidWrite(uri: string, text: string, created: boolean): void {
    if (this.exited) return
    const key = normalizeFileUri(uri)
    this.changedAt.set(key, this.diagnostics.get(key)?.generation ?? 0)
    const isL4 = key.toLowerCase().endsWith('.l4')
    let doc = this.open.get(key)
    let opened = false
    if (!doc && isL4) {
      doc = { version: 1, lineCount: lineCount(text), text }
      this.open.set(key, doc)
      opened = true
    } else if (doc) {
      doc.version++
      doc.lineCount = lineCount(text)
      doc.text = text
    }
    const version = doc?.version ?? 0
    const send = async (): Promise<void> => {
      if (opened) {
        await this.connection.sendNotification('textDocument/didOpen', {
          textDocument: { uri: key, languageId: 'l4', version, text },
        })
      } else if (doc) {
        await this.connection.sendNotification('textDocument/didChange', {
          textDocument: { uri: key, version },
          contentChanges: [{ text }],
        })
      }
      await this.connection.sendNotification(
        'workspace/didChangeWatchedFiles',
        { changes: [{ uri: key, type: created ? 1 : 2 }] }
      )
    }
    this.enqueue(send, 'change')
    if (isL4) this.refreshImporters(key)
  }

  /**
   * jl4-lsp re-checks a document (and pushes its directive results) only
   * when that document changes, not when a module it imports does. After
   * an `.l4` file changes, re-send every other open document unchanged
   * so importers are checked against the new version.
   */
  private refreshImporters(changed: string): void {
    const others = [...this.open].filter(
      ([k]) => k !== changed && k.toLowerCase().endsWith('.l4')
    )
    for (const [k, doc] of others) {
      doc.version++
      this.changedAt.set(k, this.diagnostics.get(k)?.generation ?? 0)
      const { version, text } = doc
      this.enqueue(
        () =>
          this.connection.sendNotification('textDocument/didChange', {
            textDocument: { uri: k, version },
            contentChanges: [{ text }],
          }),
        'refresh'
      )
    }
  }

  onDidDelete(uri: string): void {
    if (this.exited) return
    const key = normalizeFileUri(uri)
    const wasOpen = this.open.delete(key)
    this.diagnostics.delete(key)
    const send = async (): Promise<void> => {
      if (wasOpen) {
        await this.connection.sendNotification('textDocument/didClose', {
          textDocument: { uri: key },
        })
      }
      await this.connection.sendNotification(
        'workspace/didChangeWatchedFiles',
        { changes: [{ uri: key, type: 3 }] }
      )
    }
    this.enqueue(send, 'delete')
    if (key.toLowerCase().endsWith('.l4')) this.refreshImporters(key)
  }

  /**
   * Files changed behind the server's back (a git merge or rollback):
   * push each changed file's current content (so importers see it; the
   * server doesn't re-read modules from disk), and close deleted ones.
   */
  async resync(changedUris: string[]): Promise<void> {
    if (this.exited) return
    for (const u of changedUris) {
      const key = normalizeFileUri(u)
      let text: string | null
      try {
        text = await fs.readFile(new URL(key), 'utf8')
      } catch {
        text = null
      }
      if (text === null) this.onDidDelete(key)
      else this.onDidWrite(key, text, false)
    }
    await this.notifying
  }

  /** `shutdown` + `exit`, then kill the process if it lingers. */
  async dispose(timeoutMs = 3_000): Promise<void> {
    this.disposing = true
    if (!this.exited) {
      try {
        await Promise.race([
          this.connection.sendRequest('shutdown'),
          new Promise((r) => setTimeout(r, timeoutMs)),
        ])
        await this.connection.sendNotification('exit')
      } catch {
        // already gone
      }
    }
    const child = this.process
    if (child && child.exitCode === null && child.signalCode === null) {
      await new Promise<void>((resolve) => {
        const t = setTimeout(() => {
          child.kill('SIGKILL')
          resolve()
        }, timeoutMs)
        child.once('exit', () => {
          clearTimeout(t)
          resolve()
        })
      })
    }
    this.connection.dispose()
  }

  private enqueue(send: () => Promise<void>, what: string): void {
    this.notifying = this.notifying
      .then(send)
      .catch((err) =>
        this.logger.warn(`jl4-lsp: ${what} notification failed: ${String(err)}`)
      )
  }

  private assertRunning(): void {
    if (this.exited) throw new Error('The L4 language server is not running')
  }

  private waitForDiagnostics(key: string, timeoutMs: number): Promise<void> {
    return new Promise((resolve) => {
      const list = this.diagnosticWaiters.get(key) ?? []
      const done = (): void => {
        clearTimeout(timer)
        resolve()
      }
      const timer = setTimeout(() => {
        const still = this.diagnosticWaiters.get(key)
        if (still)
          this.diagnosticWaiters.set(
            key,
            still.filter((f) => f !== done)
          )
        resolve()
      }, timeoutMs)
      list.push(done)
      this.diagnosticWaiters.set(key, list)
    })
  }

  private withTimeout<T>(p: Promise<T>, what: string): Promise<T> {
    this.assertRunning()
    return new Promise<T>((resolve, reject) => {
      const t = setTimeout(
        () => reject(new Error(`jl4-lsp ${what} timed out`)),
        REQUEST_TIMEOUT_MS
      )
      p.then(
        (v) => {
          clearTimeout(t)
          resolve(v)
        },
        (err: unknown) => {
          clearTimeout(t)
          reject(err instanceof Error ? err : new Error(String(err)))
        }
      )
    })
  }
}

function lineCount(text: string): number {
  let n = 1
  for (let i = 0; i < text.length; i++) if (text.charCodeAt(i) === 10) n++
  return n
}

function severityName(s: number | undefined): DiagnosticSeverity {
  switch (s) {
    case 1:
      return 'error'
    case 2:
      return 'warning'
    case 3:
      return 'info'
    case 4:
      return 'hint'
    default:
      return 'info'
  }
}
