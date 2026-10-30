import { constants, promises as fs, lstatSync, realpathSync } from 'node:fs'
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
import type { WriteFence } from './lease.js'

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
 * - `.git` is off limits at any depth, by name and by real path (a
 *   pushed `data/g -> ../.git` must not reach it): the harness runs git
 *   in this repo, so the agent must not reach hooks or config.
 * - The model may write only inside `data/` and `tmp/`, checked on the
 *   path as given and on its real path; anything else at the repo root
 *   is platform metadata: readable, not writable.
 * - Writes and deletes never go through a symlink at any depth (an
 *   `lstat` walk; `O_NOFOLLOW` only guards the last component). Git
 *   checks symlinks out as plain files (`core.symlinks=false`), so none
 *   should exist; this covers any that do.
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
  /** Checked before every write and delete (§7.3); set by the runner. */
  private fence: WriteFence | undefined

  setFence(fence: WriteFence): void {
    this.fence = fence
  }

  setTurn(turnId: string | null): void {
    this.turn = turnId && TURN_ID_RE.test(turnId) ? turnId : null
  }

  /** Create `data/` and `tmp/` if they are missing (without following
   *  links), so a fresh or cleared session has both. */
  async ensureLayout(): Promise<void> {
    this.fence?.check('workspace')
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
    if (rel.split(path.sep).some(isGitDir)) {
      throw new Error(
        `Path is inside .git, which the agent may not touch: ${p}`
      )
    }
    this.realRelative(absolute, p)
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
      .filter((e) => !isGitDir(e.name))
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
    this.assertWritable(target.fsPath)
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
    // `unlink` removes a link itself, so the file may be one.
    this.assertWritable(target.fsPath, true)
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
      this.assertWritable(dest)
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
    this.assertWritable(dest)
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
    this.assertWritable(dest)
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

  /** Paths handed back by the core: inside the root and not in `.git`,
   *  lexically and by real path. Returns the real repo-relative path. */
  private assertInside(fsPath: string): string {
    const rel = path.relative(this.root, path.resolve(fsPath))
    if (
      rel.startsWith('..') ||
      path.isAbsolute(rel) ||
      rel.split(path.sep).some(isGitDir)
    ) {
      throw new Error('Path is outside the session workspace')
    }
    return this.realRelative(fsPath, rel || '.')
  }

  /** The model may write only inside `data/` and `tmp/`; everything
   *  else at the repo root is platform metadata. Checked on the path as
   *  given and where it really is, and never through a symlink
   *  (`linkAtEnd`: the file itself may be one). */
  private assertWritable(fsPath: string, linkAtEnd = false): void {
    this.fence?.check('workspace')
    const absolute = path.resolve(fsPath)
    const real = this.assertInside(absolute)
    const rel = path.relative(this.root, absolute).split(path.sep).join('/')
    this.assertNoLinks(
      linkAtEnd ? path.dirname(absolute) : absolute,
      rel || '.'
    )
    if (!isModelWritableRepoPath(rel) || !isModelWritableRepoPath(real)) {
      throw new Error(
        `${rel || '.'} can't be changed: you may only create, edit or delete files inside ${DATA_DIR}/ (the session files) and ${TMP_DIR}/ (your scratch space). Everything else in the repository is platform metadata.`
      )
    }
  }

  /** No component below the root, down to `absolute`, is a symlink. */
  private assertNoLinks(absolute: string, display: string): void {
    let cur = this.root
    for (const part of path
      .relative(this.root, absolute)
      .split(path.sep)
      .filter(Boolean)) {
      cur = path.join(cur, part)
      let isLink: boolean
      try {
        isLink = lstatSync(cur).isSymbolicLink()
      } catch (err) {
        if (isErrno(err, 'ENOENT') || isErrno(err, 'ENOTDIR')) return
        throw err
      }
      if (isLink) {
        throw new Error(
          `Path goes through a symbolic link, which the agent may not write through: ${display}`
        )
      }
    }
  }

  /**
   * Where `absolute` really is, relative to the real root and
   * `/`-separated: the real path of its nearest existing ancestor (the
   * file itself when it exists) plus the components that don't exist
   * yet. Throws when that leaves the root or lands in `.git`.
   */
  private realRelative(absolute: string, display: string): string {
    let probe = path.resolve(absolute)
    const missing: string[] = []
    for (;;) {
      let real: string
      try {
        real = realpathSync(probe)
      } catch (err) {
        if (isErrno(err, 'ENOENT') || isErrno(err, 'ENOTDIR')) {
          const parent = path.dirname(probe)
          if (parent === probe) break
          missing.unshift(path.basename(probe))
          probe = parent
          continue
        }
        throw err
      }
      const rel = path.relative(this.realRoot, path.join(real, ...missing))
      if (rel.startsWith('..') || path.isAbsolute(rel)) {
        throw new Error(
          `Path leaves the session workspace through a link: ${display}`
        )
      }
      const parts = rel.split(path.sep).filter(Boolean)
      if (parts.some(isGitDir)) {
        throw new Error(
          `Path is inside .git, which the agent may not touch: ${display}`
        )
      }
      return parts.join('/')
    }
    throw new Error(`Path is outside the session workspace: ${display}`)
  }
}

function isGitDir(part: string): boolean {
  return part.toLowerCase() === '.git'
}
