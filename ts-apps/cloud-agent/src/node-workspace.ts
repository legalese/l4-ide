import { constants, promises as fs, realpathSync } from 'node:fs'
import * as path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import type {
  ResolvedPath,
  Workspace,
  WorkspaceDirEntry,
  WorkspaceStat,
  WorkspaceTextEdit,
} from '@repo/legalese-agent'
import {
  REPO_DATA_DIR,
  REPO_DELETED_DIR,
  REPO_TMP_DIR,
  deletedCopyPath,
  isModelWritableRepoPath,
} from '@repo/legalese-agent/protocol'
import { ensureDirNoFollow, isErrno } from './safe-fs.js'

const { O_RDONLY, O_WRONLY, O_CREAT, O_EXCL, O_TRUNC, O_NOFOLLOW } = constants

/** What the language server needs to hear about after a write. */
export interface WorkspaceChangeListener {
  onDidWrite(uri: string, text: string, created: boolean): void
  onDidDelete(uri: string): void
}

/** Files larger than this aren't read into the model's context. */
const MAX_READ_BYTES = 10 * 1024 * 1024

/** `file://` URI for an absolute path (the form jl4-lsp is given). */
export function uriForPath(fsPath: string): string {
  return pathToFileURL(fsPath).href
}

/** Canonical form of a `file://` URI, so URIs from the language server
 *  and from {@link uriForPath} compare equal. */
export function normalizeFileUri(uri: string): string {
  try {
    return pathToFileURL(fileURLToPath(uri)).href
  } catch {
    return uri
  }
}

/** Repo layout (spec §4.2), from the protocol. */
export const DATA_DIR = REPO_DATA_DIR
export const TMP_DIR = REPO_TMP_DIR
export const DELETED_DIR = REPO_DELETED_DIR

/** Files the user adds mid-session are capped like attachments. */
const MAX_IMPORT_BYTES = 10 * 1024 * 1024
/** Deleted files larger than this aren't copied. */
const MAX_COPY_BYTES = 50 * 1024 * 1024
const TURN_ID_RE = /^[A-Za-z0-9_.:-]{1,128}$/

/**
 * {@link Workspace} port over Node's file system, confined to the
 * session's `repo/` (spec §4.2, §11). The repo root holds `data/` (the
 * session files; `jl4-lsp` runs there) and `tmp/` (the model's scratch
 * space, committed like everything else).
 *
 * - Paths resolve against the repo root; anything outside it is refused,
 *   including through symlinks (the nearest existing ancestor's real
 *   path must stay inside the root) and `..`.
 * - `.git` is off limits at any depth: the harness runs git in this
 *   repo, so the agent must not reach hooks or config.
 * - The model may write only inside `data/` and `tmp/`; anything else at
 *   the repo root is platform metadata: readable, not writable.
 * - Writes go straight to disk (there is no editor) with `O_NOFOLLOW`,
 *   and the {@link WorkspaceChangeListener} tells the language server.
 * - Deletes remove the file (`'deleted'`); there is no Trash. Before a
 *   file under `data/` is deleted during a turn, it is copied to
 *   `tmp/deleted/t-<turnId>/<path under data>` (regular files only,
 *   never through a symlink, directories created without following
 *   links; the first copy per path per turn wins). Nothing else is
 *   copied, and nothing is cleared by the harness.
 */
export class NodeWorkspace implements Workspace {
  readonly root: string
  private readonly realRoot: string
  private turn: string | null = null
  /** `<turnId>/<path>` copied this process. */
  private readonly copied = new Set<string>()

  constructor(
    root: string,
    private readonly listener?: WorkspaceChangeListener,
    private readonly logger?: { warn(message: string): void }
  ) {
    this.root = path.resolve(root)
    this.realRoot = realpathSync(this.root)
  }

  /** `data/` as an absolute path. */
  get dataDir(): string {
    return path.join(this.root, DATA_DIR)
  }

  /** Tool calls from now on belong to `turnId` (null between turns). */
  setTurn(turnId: string | null): void {
    this.turn = turnId && TURN_ID_RE.test(turnId) ? turnId : null
  }

  /** Create `data/` and `tmp/` if they are missing (without following
   *  links), so a fresh or cleared session has both. */
  async ensureLayout(): Promise<void> {
    await ensureDirNoFollow(this.root, this.dataDir)
    await ensureDirNoFollow(this.root, path.join(this.root, TMP_DIR))
  }

  resolvePath(p: string): ResolvedPath {
    if (!p || typeof p !== 'string') throw new Error('path is required')
    if (p.includes('\0')) throw new Error('invalid path')
    const absolute = path.isAbsolute(p)
      ? path.resolve(p)
      : path.resolve(this.root, p)
    const rel = path.relative(this.root, absolute)
    if (rel.startsWith('..') || path.isAbsolute(rel)) {
      throw new Error(
        `Path is outside the session workspace: ${p}. fs tools only operate on files inside the session's repository (${DATA_DIR}/, ${TMP_DIR}/).`
      )
    }
    if (rel.split(path.sep).some((part) => part.toLowerCase() === '.git')) {
      throw new Error(
        `Path is inside .git, which the agent may not touch: ${p}`
      )
    }
    this.assertRealPathInside(absolute, p)
    return {
      relative: rel || path.basename(absolute),
      uri: uriForPath(absolute),
      fsPath: absolute,
    }
  }

  relativePath(uri: string): string {
    const fsPath = this.pathForUri(uri)
    const rel = path.relative(this.root, fsPath)
    return rel.startsWith('..') || path.isAbsolute(rel) ? fsPath : rel
  }

  pathForUri(uri: string): string {
    return uri.startsWith('file:') ? fileURLToPath(uri) : uri
  }

  async stat(fsPath: string): Promise<WorkspaceStat | null> {
    this.assertInside(fsPath)
    try {
      const st = await fs.lstat(fsPath)
      return { isDirectory: st.isDirectory(), isFile: st.isFile() }
    } catch (err) {
      if (isErrno(err, 'ENOENT')) return null
      throw err
    }
  }

  async readDirectory(fsPath: string): Promise<WorkspaceDirEntry[]> {
    this.assertInside(fsPath)
    const entries = await fs.readdir(fsPath, { withFileTypes: true })
    return entries
      .filter((e) => e.name.toLowerCase() !== '.git')
      .map((e) => ({
        name: e.name,
        isDirectory: e.isDirectory(),
        isFile: e.isFile(),
      }))
  }

  async readFile(fsPath: string): Promise<string> {
    this.assertInside(fsPath)
    const handle = await fs.open(fsPath, O_RDONLY | O_NOFOLLOW)
    try {
      const st = await handle.stat()
      if (!st.isFile())
        throw new Error(`Not a regular file: ${this.rel(fsPath)}`)
      if (st.size > MAX_READ_BYTES) {
        throw new Error(`File is too large to read: ${this.rel(fsPath)}`)
      }
      return await handle.readFile('utf8')
    } finally {
      await handle.close()
    }
  }

  async readDocument(
    uri: string
  ): Promise<{ text: string; eol: '\n' | '\r\n' }> {
    const text = await this.readFile(this.pathForUri(uri))
    return { text, eol: text.includes('\r\n') ? '\r\n' : '\n' }
  }

  async createFile(target: ResolvedPath, content: string): Promise<void> {
    this.assertWritable(target.fsPath)
    await ensureDirNoFollow(this.root, path.dirname(target.fsPath))
    this.assertRealPathInside(target.fsPath, target.relative)
    const handle = await fs.open(
      target.fsPath,
      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
      0o644
    )
    try {
      await handle.writeFile(content, 'utf8')
    } finally {
      await handle.close()
    }
    this.listener?.onDidWrite(target.uri, content, true)
  }

  async applyEdits(edits: WorkspaceTextEdit[]): Promise<void> {
    const byUri = new Map<string, WorkspaceTextEdit[]>()
    for (const e of edits) {
      const list = byUri.get(e.uri)
      if (list) list.push(e)
      else byUri.set(e.uri, [e])
    }
    // Compute every new text first, so a bad edit leaves nothing half
    // applied; then write.
    const results: Array<{ uri: string; fsPath: string; text: string }> = []
    for (const [uri, list] of byUri) {
      const fsPath = this.pathForUri(uri)
      this.assertWritable(fsPath)
      let text = await this.readFile(fsPath)
      const sorted = [...list].sort((a, b) => b.startOffset - a.startOffset)
      let limit = text.length
      for (const e of sorted) {
        if (
          e.startOffset < 0 ||
          e.endOffset < e.startOffset ||
          e.endOffset > limit
        ) {
          throw new Error(`Invalid or overlapping edit in ${this.rel(fsPath)}`)
        }
        text =
          text.slice(0, e.startOffset) + e.newText + text.slice(e.endOffset)
        limit = e.startOffset
      }
      results.push({ uri, fsPath, text })
    }
    for (const r of results) {
      const handle = await fs.open(r.fsPath, O_WRONLY | O_TRUNC | O_NOFOLLOW)
      try {
        await handle.writeFile(r.text, 'utf8')
      } finally {
        await handle.close()
      }
      this.listener?.onDidWrite(r.uri, r.text, false)
    }
  }

  async deleteFile(target: ResolvedPath): Promise<'trashed' | 'deleted'> {
    this.assertWritable(target.fsPath)
    const st = await fs.lstat(target.fsPath)
    if (st.isDirectory()) {
      throw new Error(`Refusing to delete a directory: ${target.relative}`)
    }
    await this.copyBeforeDelete(target.fsPath)
    await fs.unlink(target.fsPath)
    this.listener?.onDidDelete(target.uri)
    return 'deleted'
  }

  /**
   * Copy a `data/` file about to be deleted to
   * `tmp/deleted/t-<turnId>/<path under data>`. Never throws: a failed
   * copy must not block the deletion, but it is logged.
   */
  private async copyBeforeDelete(fsPath: string): Promise<void> {
    const turnId = this.turn
    if (!turnId) return
    const rel = path.relative(this.dataDir, path.resolve(fsPath))
    if (!rel || rel.startsWith('..') || path.isAbsolute(rel)) return
    const key = `${turnId}/${rel}`
    if (this.copied.has(key)) return
    const dest = path.join(
      this.root,
      ...deletedCopyPath(turnId, rel.split(path.sep).join('/')).split('/')
    )
    try {
      const st = await fs.lstat(fsPath)
      if (!st.isFile() || st.size > MAX_COPY_BYTES) return
      const src = await fs.open(fsPath, O_RDONLY | O_NOFOLLOW)
      let bytes: Buffer
      try {
        bytes = await src.readFile()
      } finally {
        await src.close()
      }
      await ensureDirNoFollow(this.root, path.dirname(dest))
      this.assertRealPathInside(dest, rel)
      // A copy from an earlier run of the same turn wins too.
      const h = await fs.open(
        dest,
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
        0o644
      )
      try {
        await h.writeFile(bytes)
      } finally {
        await h.close()
      }
      this.copied.add(key)
    } catch (err) {
      if (isErrno(err, 'EEXIST')) {
        this.copied.add(key)
        return
      }
      this.logger?.warn(
        `workspace: could not copy a deleted file: ${(err as Error).message}`
      )
    }
  }

  /**
   * Copy a file the user added (`add-files`, §10) from outside the repo
   * to `repoRelPath` (under `data/`), overwriting what is there. The
   * source must be a regular file (no symlink, ≤ 10 MB); the destination
   * is confined like any write, its directories created without
   * following links. Returns false when the file was skipped.
   */
  async importFile(sourcePath: string, repoRelPath: string): Promise<boolean> {
    const dest = path.join(this.root, ...repoRelPath.split('/'))
    this.assertInside(dest)
    let bytes: Buffer
    const src = await fs
      .open(sourcePath, O_RDONLY | O_NOFOLLOW)
      .catch(() => null)
    if (!src) return false
    try {
      const st = await src.stat()
      if (!st.isFile() || st.size > MAX_IMPORT_BYTES) return false
      bytes = await src.readFile()
    } finally {
      await src.close()
    }
    const existing = await fs.lstat(dest).catch(() => null)
    if (existing && !existing.isFile()) return false
    await ensureDirNoFollow(this.root, path.dirname(dest))
    this.assertRealPathInside(dest, repoRelPath)
    const h = await fs.open(
      dest,
      O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW,
      0o644
    )
    try {
      await h.writeFile(bytes)
    } finally {
      await h.close()
    }
    this.listener?.onDidWrite(
      uriForPath(dest),
      bytes.toString('utf8'),
      !existing
    )
    return true
  }

  private rel(fsPath: string): string {
    return path.relative(this.root, fsPath) || path.basename(fsPath)
  }

  /** Lexical check for paths handed back by the core. */
  private assertInside(fsPath: string): void {
    const rel = path.relative(this.root, path.resolve(fsPath))
    if (
      rel.startsWith('..') ||
      path.isAbsolute(rel) ||
      rel.split(path.sep).some((part) => part.toLowerCase() === '.git')
    ) {
      throw new Error('Path is outside the session workspace')
    }
    this.assertRealPathInside(fsPath, rel || '.')
  }

  /** The model may write only inside `data/` and `tmp/`; everything
   *  else at the repo root is platform metadata. */
  private assertWritable(fsPath: string): void {
    this.assertInside(fsPath)
    const rel = path
      .relative(this.root, path.resolve(fsPath))
      .split(path.sep)
      .join('/')
    if (!isModelWritableRepoPath(rel)) {
      throw new Error(
        `${rel || '.'} can't be changed: you may only create, edit or delete files inside ${DATA_DIR}/ (the session files) and ${TMP_DIR}/ (your scratch space). Everything else in the repository is platform metadata.`
      )
    }
  }

  /** The nearest existing ancestor (or the file itself) must resolve,
   *  through symlinks, to a place inside the root. */
  private assertRealPathInside(absolute: string, display: string): void {
    let probe = path.resolve(absolute)
    for (;;) {
      let real: string
      try {
        real = realpathSync(probe)
      } catch (err) {
        const code = (err as NodeJS.ErrnoException).code
        if (code === 'ENOENT' || code === 'ENOTDIR') {
          const parent = path.dirname(probe)
          if (parent === probe) break
          probe = parent
          continue
        }
        throw err
      }
      const rel = path.relative(this.realRoot, real)
      if (rel.startsWith('..') || path.isAbsolute(rel)) {
        throw new Error(
          `Path leaves the session workspace through a link: ${display}`
        )
      }
      return
    }
    throw new Error(`Path is outside the session workspace: ${display}`)
  }
}
