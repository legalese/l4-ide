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

/** Commit subjects are capped at this many characters. */
export const SUBJECT_MAX = 72
/** The commit summary gets at most this long (a hard limit). */
export const SUMMARY_TIMEOUT_MS = 5_000
/** How much of the turn the summary request carries. */
const SUMMARY_PROMPT_CHARS = 500
const SUMMARY_REPLY_CHARS = 1_000
const SUMMARY_MAX_PATHS = 30
/** The `Prompt:` line in a commit body is capped at this length. */
const PROMPT_LINE_MAX = 300

/** C0/C1 control characters (and DEL). */
const CONTROL_RE = /\p{Cc}/gu
const QUOTES = '"\'`“”‘’«»'

function firstLine(text: string): string {
  return (
    text
      .split(/\r?\n|[\u2028\u2029]/)
      .map((l) => l.replace(CONTROL_RE, ' ').replace(/\s+/g, ' ').trim())
      .find((l) => l.length > 0) ?? ''
  )
}

function cap(line: string, max: number): string {
  return line.length > max ? line.slice(0, max - 1).trimEnd() + '…' : line
}

/** First line of a prompt, for a commit subject (the fallback when no
 *  summary can be generated). */
export function commitSubject(text: string, fallback: string): string {
  const line = firstLine(text)
  return line ? cap(line, SUBJECT_MAX) : fallback
}

/**
 * Turn a model's answer into a commit subject: its first non-empty
 * line, control characters stripped, list markers / "Subject:" labels /
 * a wrapping pair of quotes / trailing periods removed, capped at
 * {@link SUBJECT_MAX}. `null` when nothing usable is left.
 */
export function sanitizeSubject(raw: string): string | null {
  let line = firstLine(raw)
  line = line
    .replace(/^(?:[-*•]\s+|#+\s+)/, '')
    .replace(/^(?:commit\s+(?:subject|message)|subject)\s*:\s*/i, '')
  // Trailing periods and a wrapping pair of quotes, in whatever order
  // they nest. Quotes inside the line are left alone.
  for (let i = 0; i < 4; i++) {
    let next = line.replace(/[.。]+$/, '').trim()
    if (
      next.length >= 2 &&
      QUOTES.includes(next[0]!) &&
      QUOTES.includes(next[next.length - 1]!)
    ) {
      next = next.slice(1, -1).trim()
    }
    if (next === line) break
    line = next
  }
  if (line.length < 3) return null
  return cap(line, SUBJECT_MAX)
}

/** A staged change: `A` added, `M` modified, `D` deleted (others as git
 *  reports them). */
export interface ChangedPath {
  status: string
  path: string
}

/** The summize request for a turn's commit subject. */
export function summaryMessages(
  turn: { prompt: string; reply?: string },
  changes: ChangedPath[]
): Array<{ role: 'system' | 'user'; content: string }> {
  const clip = (text: string, max: number): string => {
    const t = text.trim()
    return t.length > max ? t.slice(0, max) + '…' : t
  }
  const lines = changes
    .slice(0, SUMMARY_MAX_PATHS)
    .map((c) => `${c.status} ${cap(c.path.replace(CONTROL_RE, ' '), 200)}`)
  if (changes.length > SUMMARY_MAX_PATHS) {
    lines.push(`(and ${changes.length - SUMMARY_MAX_PATHS} more)`)
  }
  return [
    {
      role: 'system',
      content:
        'You write git commit subject lines. You are given what a user asked ' +
        "an AI assistant, the assistant's final reply, and the files the " +
        'assistant changed. Answer with ONE line that says what changed: ' +
        `imperative mood (like "Add …" or "Fix …"), at most ${SUBJECT_MAX} ` +
        'characters, no quotes, no trailing period, no explanation.',
    },
    {
      role: 'user',
      content:
        `User request:\n${clip(turn.prompt, SUMMARY_PROMPT_CHARS) || '(empty)'}\n\n` +
        `Assistant's final reply:\n${clip(turn.reply ?? '', SUMMARY_REPLY_CHARS) || '(none)'}\n\n` +
        `Changed files (A added, M modified, D deleted):\n${lines.join('\n')}\n\n` +
        'Commit subject:',
    },
  ]
}

/**
 * Git sync for a cloud session (spec §4.7, §5.4, §9.1, §9.4). The
 * harness is the only process that runs git on `repo/`.
 *
 * - **Start.** `git init -b main` if there's no repository (dev mode;
 *   the Sessions API pre-creates it), a "Seed" commit if there are no
 *   commits, then `state/git/main.bundle`.
 * - **Per turn.** If the turn changed anything: `git add -A`, then a
 *   commit whose subject is a one-line summary of the turn from
 *   ai-proxy's summize pipeline (≤ 5 s; on a timeout, error or unusable
 *   answer: the prompt's first line), whose body is
 *   `Prompt: <first line of the prompt>`, with a `Turn-Id: <turnId>`
 *   trailer. Then rewrite `main.bundle` (temp file + rename) and emit
 *   `git-committed { turnId, sha, parent, summary }`.
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

  private readonly summaryTimeoutMs: number

  constructor(
    private readonly baseEnv: NodeJS.ProcessEnv,
    opts: { summaryTimeoutMs?: number } = {}
  ) {
    this.summaryTimeoutMs = opts.summaryTimeoutMs ?? SUMMARY_TIMEOUT_MS
  }

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
    const promptLine = cap(firstLine(turn.prompt), PROMPT_LINE_MAX)
    const committed = await this.commitChanges(
      (changes) => this.turnSubject(turn, changes),
      {
        turnId: turn.turnId,
        ...(promptLine ? { body: `Prompt: ${promptLine}` } : {}),
      }
    )
    if (!committed) return
    this.ctx.emit({
      type: 'git-committed',
      turnId: turn.turnId,
      sha: committed.sha,
      parent: committed.parent,
      summary: committed.subject,
    })
  }

  /**
   * The subject for a turn's commit: a one-line summary from summize,
   * or — on a timeout, an error or an unusable answer — the prompt's
   * first line. Never throws and never takes longer than the timeout.
   */
  private async turnSubject(
    turn: TurnInfo,
    changes: ChangedPath[]
  ): Promise<string> {
    const fallback = commitSubject(turn.prompt, `Turn ${turn.turnId}`)
    const started = Date.now()
    let timer: NodeJS.Timeout | undefined
    let subject: string | null = null
    try {
      const raw = await Promise.race([
        this.ctx.summize(summaryMessages(turn, changes), {
          signal: AbortSignal.timeout(this.summaryTimeoutMs),
        }),
        new Promise<null>((resolve) => {
          timer = setTimeout(() => resolve(null), this.summaryTimeoutMs)
        }),
      ])
      subject = raw ? sanitizeSubject(raw) : null
    } catch {
      subject = null
    } finally {
      if (timer) clearTimeout(timer)
    }
    // The summary is content: only how it went is logged.
    this.ctx.logger.info(
      `git: commit summary ${subject ? 'generated' : 'unavailable, using the prompt'} (${Date.now() - started} ms)`
    )
    return subject ?? fallback
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

  /**
   * Commit everything that changed; `null` when nothing did. `subject`
   * may be computed from the staged changes (it is only asked for when
   * there is something to commit). The message is the subject, then
   * `body`, then the `Turn-Id` trailer, each its own paragraph.
   */
  private async commitChanges(
    subject: string | ((changes: ChangedPath[]) => Promise<string>),
    opts: { turnId?: string; body?: string } = {}
  ): Promise<{ sha: string; parent: string; subject: string } | null> {
    await this.git.ok(['add', '-A'])
    const diff = await this.git.run(['diff', '--cached', '--quiet'])
    if (diff.code === 0) return null
    const parent = await this.git.head()
    const line =
      typeof subject === 'string'
        ? subject
        : await subject(await this.stagedChanges().catch(() => []))
    const message =
      [
        line,
        ...(opts.body ? [opts.body] : []),
        ...(opts.turnId ? [`${TURN_ID_TRAILER}: ${opts.turnId}`] : []),
      ].join('\n\n') + '\n'
    await this.git.ok(['commit', '-q', '-F', '-'], { input: message })
    const sha = await this.git.head()
    if (!sha || !parent) throw new Error('git: commit produced no HEAD')
    await this.writeBundle()
    return { sha, parent, subject: line }
  }

  /** What is staged, as `A`/`M`/`D` + path (renames shown as D + A). */
  private async stagedChanges(): Promise<ChangedPath[]> {
    const r = await this.git.run([
      'diff',
      '--cached',
      '--name-status',
      '--no-renames',
      '-z',
    ])
    if (r.code !== 0) return []
    const parts = r.stdout.split('\0')
    const out: ChangedPath[] = []
    for (let i = 0; i + 1 < parts.length; i += 2) {
      const status = parts[i]!.trim().charAt(0)
      const file = parts[i + 1]!
      if (status && file) out.push({ status, path: file })
    }
    return out
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
