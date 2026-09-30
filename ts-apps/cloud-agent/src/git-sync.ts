import { randomBytes } from 'node:crypto'
import { promises as fs } from 'node:fs'
import * as path from 'node:path'
import {
  GIT_SHA_RE,
  REPO_TMP_DIR,
  isIncomingBundleName,
  type CloudCommand,
} from '@repo/legalese-agent/protocol'
import { Git } from './git.js'
import type {
  ExitReason,
  RunnerContext,
  RunnerPlugin,
  TurnInfo,
} from './runner.js'

/** Incoming bundles are capped at 100 MB (§9.3). */
export const MAX_INCOMING_BUNDLE_BYTES = 100 * 1024 * 1024
export const TURN_ID_TRAILER = 'Turn-Id'
/** `git gc` gets at most this long on sleep. */
const GC_TIMEOUT_MS = 60_000

/** First line of a prompt, for a commit subject. */
export function commitSubject(text: string, fallback: string): string {
  const line =
    text
      .split('\n')
      .map((l) => l.trim())
      .find((l) => l.length > 0) ?? ''
  if (!line) return fallback
  return line.length > 72 ? line.slice(0, 71) + '…' : line
}

/**
 * Git sync for a cloud session (spec §4.7, §5.4, §9.1, §9.4). The
 * harness is the only process that runs git on `repo/`.
 *
 * - **Start.** `git init -b main` if there's no repository (dev mode;
 *   the Sessions API pre-creates it), a "Seed" commit if there are no
 *   commits, then `state/git/main.bundle`.
 * - **Per turn.** If the turn changed anything: `git add -A`, commit
 *   with the prompt's first line and a `Turn-Id: <turnId>` trailer,
 *   rewrite `main.bundle` (temp file + rename), emit
 *   `git-committed { turnId, sha, parent }`.
 * - **`apply-bundle { file }`** (queued, so it runs between turns):
 *   fetch `state/git/incoming/<file>` (a `local ^main` bundle) into
 *   `refs/incoming/<ulid>`, merge it into `main`, rewrite the bundle,
 *   emit `local-merged { sha }`; on a conflict abort the merge and emit
 *   `local-merge-conflict { files }`.
 * - **`rollback { turnId }`** (queued): restore index and working tree
 *   to the parent of that turn's commit
 *   (`git restore --source=<parent> --staged --worktree :/`), commit
 *   "Roll back: <subject>", rewrite the bundle, emit
 *   `rolled-back { turnId, sha }`. No history is rewritten. The next
 *   prompt tells the model which turns were undone.
 * - **Sleep.** A final commit of anything left over, the bundle, and
 *   `git gc` (not on SIGTERM, which has a 30 s budget).
 */
export class GitSync implements RunnerPlugin {
  readonly name = 'git'
  readonly commands = ['rollback', 'apply-bundle'] as const
  private git!: Git
  private ctx!: RunnerContext
  /** Turns rolled back since the last prompt. */
  private rolledBack: string[] = []

  constructor(private readonly baseEnv: NodeJS.ProcessEnv) {}

  private get bundlePath(): string {
    return path.join(this.ctx.stateDir, 'git', 'main.bundle')
  }

  async start(ctx: RunnerContext): Promise<void> {
    this.ctx = ctx
    this.git = new Git(ctx.repoDir, this.baseEnv)
    await fs.mkdir(path.join(ctx.stateDir, 'git'), { recursive: true })
    const hasRepo = await fs
      .lstat(path.join(ctx.repoDir, '.git'))
      .then((st) => st.isDirectory())
      .catch(() => false)
    if (!hasRepo) {
      await this.git.ok(['init', '-q', '-b', 'main'])
      ctx.logger.info('git: initialised the repository')
    }
    const branch = (
      await this.git.run(['symbolic-ref', '--short', 'HEAD'])
    ).stdout.trim()
    if (branch !== 'main') {
      throw new Error(
        `git: HEAD is on "${branch || 'a detached head'}", not main`
      )
    }
    // A merge interrupted by a crash would block every later commit.
    if (
      (await this.git.run(['rev-parse', '-q', '--verify', 'MERGE_HEAD']))
        .code === 0
    ) {
      await this.git.run(['merge', '--abort'])
      ctx.logger.warn('git: aborted a merge left over from a previous run')
    }
    if ((await this.git.head()) === null) {
      await this.git.ok(['add', '-A'])
      await this.git.ok(['commit', '-q', '--allow-empty', '-m', 'Seed'])
      ctx.logger.info('git: committed the seed')
    } else {
      await this.commitClearedTmp()
    }
    await this.writeBundle()
  }

  /**
   * The Sessions API sweep deletes `repo/tmp/` of abandoned sessions
   * (filesystem only, no git). If every tracked file under `tmp/` is gone
   * and nothing new is there, commit that deletion on its own ("Clear
   * tmp of abandoned session"). Anything else stays for the next turn's
   * commit.
   */
  private async commitClearedTmp(): Promise<void> {
    const list = async (flag?: string): Promise<string[]> =>
      (
        await this.git.ok([
          '--literal-pathspecs',
          'ls-files',
          '-z',
          ...(flag ? [flag] : []),
          '--',
          REPO_TMP_DIR,
        ])
      )
        .split('\0')
        .filter((f) => f.length > 0)
    const tracked = await list()
    if (tracked.length === 0) return
    const deleted = await list('--deleted')
    const untracked = await list('--others')
    if (deleted.length !== tracked.length || untracked.length > 0) return
    await this.git.ok(
      ['--literal-pathspecs', 'rm', '-q', '--cached', '-r', '--', REPO_TMP_DIR],
      {}
    )
    await this.git.ok(['commit', '-q', '-m', 'Clear tmp of abandoned session'])
    this.ctx.logger.info(
      `git: committed the cleared tmp/ (${tracked.length} files)`
    )
  }

  async beforeTurn(): Promise<string | undefined> {
    if (this.rolledBack.length === 0) return undefined
    const turns = this.rolledBack.map((t) => `"${t}"`).join(', ')
    this.rolledBack = []
    return (
      `<rollback-notice>The user rolled back the file changes of turn(s) ${turns}. ` +
      'The files in the repository are as they were before those turns; ' +
      're-read any file before relying on what those turns wrote.</rollback-notice>'
    )
  }

  async afterTurn(turn: TurnInfo): Promise<void> {
    const committed = await this.commitChanges(
      commitSubject(turn.prompt, `Turn ${turn.turnId}`),
      turn.turnId
    )
    if (!committed) return
    this.ctx.emit({
      type: 'git-committed',
      turnId: turn.turnId,
      sha: committed.sha,
      parent: committed.parent,
    })
  }

  /**
   * Commit files the user added mid-session on their own ("Add files
   * from the user"), leaving any uncommitted agent work for its turn's
   * commit. Returns each file's git blob id.
   */
  async onFilesAdded(paths: string[]): Promise<Record<string, string>> {
    await this.git.ok(['--literal-pathspecs', 'add', '--', ...paths])
    const staged = await this.git.run([
      '--literal-pathspecs',
      'diff',
      '--cached',
      '--quiet',
      '--',
      ...paths,
    ])
    if (staged.code !== 0) {
      await this.git.ok([
        '--literal-pathspecs',
        'commit',
        '-q',
        '-m',
        'Add files from the user',
        '--',
        ...paths,
      ])
      await this.writeBundle()
      this.ctx.logger.info(`git: committed ${paths.length} added file(s)`)
    }
    const shas: Record<string, string> = {}
    for (const p of paths) {
      const r = await this.git.run(['rev-parse', '-q', '--verify', `HEAD:${p}`])
      const sha = r.stdout.trim()
      if (r.code === 0 && GIT_SHA_RE.test(sha)) shas[p] = sha
    }
    return shas
  }

  async handleCommand(cmd: CloudCommand): Promise<void> {
    if (cmd.type === 'apply-bundle') await this.applyBundle(cmd.file)
    else if (cmd.type === 'rollback') await this.rollback(cmd.turnId)
  }

  async beforeExit(reason: ExitReason): Promise<void> {
    const committed = await this.commitChanges('Checkpoint before sleep')
    if (committed) {
      this.ctx.logger.info('git: committed leftover changes before exit')
    }
    if (reason === 'sigterm') return
    const r = await this.git.run(['gc', '--quiet'], {
      timeoutMs: GC_TIMEOUT_MS,
    })
    if (r.code !== 0) this.ctx.logger.warn(`git gc failed (${r.code})`)
    // gc repacks; the bundle's content doesn't change.
  }

  // ── Operations ─────────────────────────────────────────────────────

  /** Commit everything that changed; `null` when nothing did. */
  private async commitChanges(
    subject: string,
    turnId?: string
  ): Promise<{ sha: string; parent: string } | null> {
    await this.git.ok(['add', '-A'])
    const diff = await this.git.run(['diff', '--cached', '--quiet'])
    if (diff.code === 0) return null
    const parent = await this.git.head()
    const message = turnId
      ? `${subject}\n\n${TURN_ID_TRAILER}: ${turnId}\n`
      : `${subject}\n`
    await this.git.ok(['commit', '-q', '-F', '-'], { input: message })
    const sha = await this.git.head()
    if (!sha || !parent) throw new Error('git: commit produced no HEAD')
    await this.writeBundle()
    return { sha, parent }
  }

  /** `state/git/main.bundle`: a full bundle of main, temp file + rename. */
  async writeBundle(): Promise<void> {
    const tmp = path.join(
      path.dirname(this.bundlePath),
      `.main.bundle.${process.pid}.${randomBytes(4).toString('hex')}.tmp`
    )
    try {
      await this.git.ok(['bundle', 'create', '-q', tmp, 'main'])
      await fs.rename(tmp, this.bundlePath)
    } catch (err) {
      await fs.rm(tmp, { force: true }).catch(() => undefined)
      throw err
    }
  }

  private async applyBundle(file: string): Promise<void> {
    const { logger } = this.ctx
    if (!isIncomingBundleName(file)) {
      logger.warn('git: apply-bundle with an invalid file name; skipped')
      return
    }
    const ulid = file.slice(0, -'.bundle'.length)
    const bundle = path.join(this.ctx.stateDir, 'git', 'incoming', file)
    const st = await fs.lstat(bundle).catch(() => null)
    if (!st?.isFile()) {
      logger.warn(`git: incoming bundle ${file} is missing; skipped`)
      return
    }
    if (st.size > MAX_INCOMING_BUNDLE_BYTES) {
      logger.warn(`git: incoming bundle ${file} is too large; skipped`)
      return
    }
    // Leftovers of an interrupted turn go in first, so the merge
    // starts from a clean tree.
    await this.commitChanges('Checkpoint before merging local changes')
    const ref = `refs/incoming/${ulid}`
    const fetched = await this.git.run([
      'fetch',
      '-q',
      '--no-tags',
      '--no-write-fetch-head',
      bundle,
      `+refs/heads/local:${ref}`,
    ])
    if (fetched.code !== 0) {
      logger.warn(
        `git: fetching incoming bundle ${file} failed (${fetched.code})`
      )
      return
    }
    const before = await this.git.head()
    const merged = await this.git.run([
      'merge',
      '-q',
      '--no-edit',
      '-m',
      'Merge local changes',
      ref,
    ])
    if (merged.code !== 0) {
      const conflicted = await this.git.run([
        'diff',
        '--name-only',
        '--diff-filter=U',
        '-z',
      ])
      const files = conflicted.stdout.split('\0').filter((f) => f.length > 0)
      await this.git.run(['merge', '--abort'])
      await this.git.run(['update-ref', '-d', ref])
      logger.warn(`git: merging ${file} conflicted in ${files.length} file(s)`)
      this.ctx.emit({
        type: 'local-merge-conflict',
        files: files.slice(0, 1000),
      })
      return
    }
    await this.git.run(['update-ref', '-d', ref])
    const sha = await this.git.head()
    if (!sha) throw new Error('git: merge produced no HEAD')
    await this.writeBundle()
    if (before && before !== sha) await this.filesChanged(before, sha)
    this.ctx.emit({ type: 'local-merged', sha })
    logger.info(`git: merged local changes from ${file}`)
  }

  private async rollback(turnId: string): Promise<void> {
    const { logger } = this.ctx
    const target = await this.findTurnCommit(turnId)
    if (!target) {
      logger.warn('git: rollback for a turn without a commit; nothing to do')
      return
    }
    const parent = (
      await this.git.run(['rev-parse', '-q', '--verify', `${target.sha}^1`])
    ).stdout.trim()
    if (!GIT_SHA_RE.test(parent)) {
      logger.warn('git: the turn commit has no parent; nothing to roll back to')
      return
    }
    await this.commitChanges('Checkpoint before roll back')
    const before = await this.git.head()
    await this.git.ok([
      'restore',
      `--source=${parent}`,
      '--staged',
      '--worktree',
      '--',
      ':/',
    ])
    const committed = await this.commitChanges(`Roll back: ${target.subject}`)
    const sha = committed?.sha ?? (await this.git.head())
    if (!sha) throw new Error('git: rollback left no HEAD')
    if (before && before !== sha) await this.filesChanged(before, sha)
    this.rolledBack.push(turnId)
    this.ctx.emit({ type: 'rolled-back', turnId, sha })
    logger.info(`git: rolled back turn ${turnId}`)
  }

  /** The newest commit whose `Turn-Id` trailer is exactly `turnId`. */
  private async findTurnCommit(
    turnId: string
  ): Promise<{ sha: string; subject: string } | null> {
    const out = await this.git.ok([
      'log',
      '--first-parent',
      `--format=%H%x00%s%x00%(trailers:key=${TURN_ID_TRAILER},valueonly,separator=%x01)%x1e`,
      'main',
    ])
    for (const rec of out.split('\x1e')) {
      const [sha, subject, trailers] = rec.replace(/^\n/, '').split('\0')
      if (!sha || !GIT_SHA_RE.test(sha.trim())) continue
      const ids = (trailers ?? '')
        .trim()
        .split('\x01')
        .map((s) => s.trim())
      if (ids.includes(turnId)) {
        return { sha: sha.trim(), subject: subject ?? '' }
      }
    }
    return null
  }

  /** Tell the language server which files changed behind its back. */
  private async filesChanged(from: string, to: string): Promise<void> {
    const out = await this.git.run(['diff', '--name-only', '-z', from, to])
    const files = out.stdout
      .split('\0')
      .filter((f) => f.length > 0)
      .map((f) => path.join(this.ctx.repoDir, f))
    await this.ctx
      .filesChanged(files)
      .catch((err: unknown) =>
        this.ctx.logger.warn(
          `git: language server resync failed: ${String(err)}`
        )
      )
  }
}
