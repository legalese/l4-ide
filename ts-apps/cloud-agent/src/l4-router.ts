import { promises as fs } from 'node:fs'
import * as path from 'node:path'
import type {
  DirectiveResultRow,
  L4Diagnostic,
  L4Language,
  Logger,
  LspLocation,
  LspPosition,
  SemanticTokensSnapshot,
} from '@repo/legalese-agent'
import type { ExportedFunctionInfo } from 'jl4-client-rpc'
import type { Jl4Lsp } from './jl4-lsp.js'
import {
  DATA_DIR,
  TMP_DIR,
  uriForPath,
  type WorkspaceChangeListener,
} from './node-workspace.js'

type Instance = L4Language &
  WorkspaceChangeListener &
  Pick<Jl4Lsp, 'resync' | 'dispose'>

/**
 * Where `IMPORT` finds `data/` modules from the `tmp/` instance:
 * `<xdgHome>/jl4/libraries` is a symlink to `repo/data`, and the tmp
 * instance runs with `XDG_DATA_HOME=<xdgHome>`.
 */
export async function prepareTmpLibraryAlias(
  xdgHome: string,
  dataDir: string
): Promise<string> {
  const jl4 = path.join(xdgHome, 'jl4')
  await fs.mkdir(jl4, { recursive: true })
  const lib = path.join(jl4, 'libraries')
  await fs.rm(lib, { force: true })
  await fs.symlink(dataDir, lib)
  return lib
}

/**
 * {@link L4Language} over two `jl4-lsp` instances (spec §5.4, §11):
 *
 * - the **data** instance (`--cwd repo/data`, started at harness start)
 *   serves every L4 file except those under `tmp/`;
 * - the **tmp** instance (`--cwd repo/tmp`, started on first use) serves
 *   files under `tmp/`, so the model can try things there in isolation.
 *
 * `IMPORT name` in jl4-lsp looks at the project root, then next to the
 * importing file, then `$XDG_DATA_HOME/jl4/libraries`, then the bundled
 * and embedded libraries. The tmp instance's XDG library folder is a
 * symlink to `repo/data` ({@link prepareTmpLibraryAlias}), so for `tmp/`
 * files: `tmp/name.l4` first, then a sibling, then `data/name.l4`, then
 * the standard libraries. (`JL4_LIBRARY_PATH` would be searched before
 * the project root and disables the embedded libraries, so it isn't
 * used.)
 *
 * jl4-lsp doesn't re-read an imported module from disk, so a changed
 * `data/` file is also pushed to the tmp instance under its alias path.
 */
export class L4Router implements L4Language, WorkspaceChangeListener {
  private tmp: Instance | null = null
  private starting: Promise<Instance> | null = null
  private readonly tmpDir: string
  private readonly dataDir: string

  constructor(
    private readonly opts: {
      repoDir: string
      data: Instance
      startTmp: () => Promise<Instance>
      /** `<xdgHome>/jl4/libraries` (the symlink to `repo/data`). */
      tmpLibraryAlias: string
      logger: Logger
    }
  ) {
    this.tmpDir = path.join(path.resolve(opts.repoDir), TMP_DIR)
    this.dataDir = path.join(path.resolve(opts.repoDir), DATA_DIR)
  }

  /** The tmp instance, if it has been started. */
  get tmpInstance(): Instance | null {
    return this.tmp
  }

  private under(dir: string, uri: string): string | null {
    let fsPath: string
    try {
      fsPath =
        new URL(uri).protocol === 'file:'
          ? decodeURIComponent(new URL(uri).pathname)
          : ''
    } catch {
      return null
    }
    if (!fsPath) return null
    const rel = path.relative(dir, path.resolve(fsPath))
    return rel && !rel.startsWith('..') && !path.isAbsolute(rel) ? rel : null
  }

  private isTmp(uri: string): boolean {
    return this.under(this.tmpDir, uri) !== null
  }

  private async tmpLsp(): Promise<Instance> {
    if (this.tmp) return this.tmp
    if (!this.starting) {
      this.opts.logger.info('starting the tmp/ language server')
      this.starting = this.opts.startTmp().then(
        (lsp) => {
          this.tmp = lsp
          return lsp
        },
        (err: unknown) => {
          this.starting = null
          throw err
        }
      )
    }
    return this.starting
  }

  private route(uri: string): Promise<Instance> {
    return this.isTmp(uri) ? this.tmpLsp() : Promise.resolve(this.opts.data)
  }

  /** The alias URI of a `data/` file for the tmp instance. */
  private alias(uri: string): string | null {
    const rel = this.under(this.dataDir, uri)
    return rel ? uriForPath(path.join(this.opts.tmpLibraryAlias, rel)) : null
  }

  // ── L4Language ─────────────────────────────────────────────────────

  async openDocument(
    uri: string
  ): Promise<{ lineCount: number; version: number }> {
    return (await this.route(uri)).openDocument(uri)
  }

  async getDiagnostics(uri: string): Promise<L4Diagnostic[]> {
    return (await this.route(uri)).getDiagnostics(uri)
  }

  getDirectiveResults(uri: string): DirectiveResultRow[] | undefined {
    if (!this.isTmp(uri)) return this.opts.data.getDirectiveResults(uri)
    return this.tmp?.getDirectiveResults(uri)
  }

  async awaitDirectiveResults(uri: string, timeoutMs: number): Promise<void> {
    return (await this.route(uri)).awaitDirectiveResults(uri, timeoutMs)
  }

  async findReferences(
    uri: string,
    position: LspPosition
  ): Promise<LspLocation[]> {
    return (await this.route(uri)).findReferences(uri, position)
  }

  async getSemanticTokens(uri: string): Promise<SemanticTokensSnapshot | null> {
    return (await this.route(uri)).getSemanticTokens(uri)
  }

  async getExportedFunctions(doc: {
    uri: string
    version: number
  }): Promise<ExportedFunctionInfo[]> {
    return (await this.route(doc.uri)).getExportedFunctions(doc)
  }

  // ── WorkspaceChangeListener ────────────────────────────────────────

  onDidWrite(uri: string, text: string, created: boolean): void {
    if (this.isTmp(uri)) {
      // Not started yet: it reads the file from disk when it starts.
      this.tmp?.onDidWrite(uri, text, created)
      return
    }
    this.opts.data.onDidWrite(uri, text, created)
    const alias = this.alias(uri)
    if (alias) this.tmp?.onDidWrite(alias, text, created)
  }

  onDidDelete(uri: string): void {
    if (this.isTmp(uri)) {
      this.tmp?.onDidDelete(uri)
      return
    }
    this.opts.data.onDidDelete(uri)
    const alias = this.alias(uri)
    if (alias) this.tmp?.onDidDelete(alias)
  }

  /** Files changed behind the servers' backs (a merge or rollback). */
  async resync(uris: string[]): Promise<void> {
    await this.opts.data.resync(uris)
    if (this.tmp) {
      const aliases = uris
        .map((u) => this.alias(u))
        .filter((u): u is string => !!u)
      await this.tmp.resync([...uris, ...aliases])
    }
  }

  async dispose(): Promise<void> {
    const tmp =
      this.tmp ?? (this.starting ? await this.starting.catch(() => null) : null)
    await Promise.all([this.opts.data.dispose(), tmp?.dispose()])
  }
}
