import * as path from 'node:path'
import {
  ProtocolError,
  formatCommandSeq,
  parseCloudCommand,
  parseCommandSeq,
  type CloudCommand,
} from '@repo/legalese-agent/protocol'
import type { Logger } from '@repo/legalese-agent'
import {
  createExclusive,
  isErrno,
  readKnownText,
  writeAtomic,
} from './safe-fs.js'

/** Command files are small; a sealed MCP credential blob is the largest. */
const MAX_COMMAND_BYTES = 1_100_000

/** How long a command number `commands.seq` announced may stay
 *  unreadable (not visible yet, or half written) before it's skipped. */
export const COMMAND_GRACE_MS = 15_000

/** Harness-owned progress marker: the highest command number handled. */
export const COMMANDS_DONE_FILE = 'commands.done'

/**
 * Reads the command queue by known names (spec §8):
 * `state/commands.seq` holds the highest number the Sessions API
 * issued; each command is `state/commands/<n>.json`. The directory is
 * never listed.
 *
 * - **Monotonic high-water mark.** The Sessions API rewrites
 *   `commands.seq` after an exclusive create; with concurrent writers
 *   the file can briefly go backwards (a slower writer rewrites a
 *   smaller number). The reader keeps the highest value it has seen
 *   and opens numbers up to that, so a regression never hides a
 *   command. It only opens a number once `commands.seq` has reached it
 *   at least once — never probing a name that may not exist yet, which
 *   the NFS client would cache as missing.
 * - **In order, once.** Commands are delivered in number order. The
 *   highest number handled is kept in `state/commands.done` (written by
 *   the harness only, temp file + rename), so a restarted harness picks
 *   up where the last one stopped — including commands queued while
 *   the session slept.
 * - **Grace.** A number `commands.seq` announced but whose file can't
 *   be opened or parsed yet (a writer between create and write) is
 *   retried for {@link COMMAND_GRACE_MS}, then skipped with a warning.
 *   An invalid command is skipped at once.
 * - At start, `commands.seq` is created as `0` with an exclusive create
 *   if it doesn't exist yet, so the harness never polls a missing name.
 */
export class CommandReader {
  private highWater = 0
  /** Persisted: every command up to here has been handled. */
  private done = 0
  /** In memory: every command up to here has been handed out. */
  private delivered = 0
  /** Handled numbers above {@link done} (handled out of order). */
  private readonly handledAbove = new Set<number>()
  private stuckSince: { n: number; at: number } | null = null
  private writing: Promise<void> = Promise.resolve()
  private readonly now: () => number

  constructor(
    private readonly stateDir: string,
    private readonly logger: Logger,
    opts: { now?: () => number } = {}
  ) {
    this.now = opts.now ?? Date.now
  }

  private get seqPath(): string {
    return path.join(this.stateDir, 'commands.seq')
  }

  private get donePath(): string {
    return path.join(this.stateDir, COMMANDS_DONE_FILE)
  }

  private commandPath(n: number): string {
    return path.join(this.stateDir, 'commands', `${n}.json`)
  }

  /** Every command up to this number has been handled. */
  get handled(): number {
    return this.done
  }

  /** The highest number `commands.seq` has shown. */
  get seen(): number {
    return this.highWater
  }

  async open(): Promise<void> {
    try {
      await createExclusive(this.seqPath, formatCommandSeq(0))
    } catch (err) {
      if (!isErrno(err, 'EEXIST')) throw err
    }
    const text = await readKnownText(this.donePath, 64)
    const n = text === null ? 0 : parseCommandSeq(text)
    if (n === null) {
      this.logger.warn('commands.done is invalid; starting from 0')
    }
    this.done = n ?? 0
    this.delivered = this.done
    this.highWater = this.done
  }

  /**
   * Read `commands.seq` and return the commands that became ready since
   * the last poll, in order. Report each with {@link markHandled} once
   * it has been dealt with (a queued message: once its turn starts).
   */
  async poll(): Promise<CloudCommand[]> {
    const text = await readKnownText(this.seqPath, 64)
    const seq = text === null ? 0 : parseCommandSeq(text)
    if (seq === null) {
      this.logger.warn('commands.seq is invalid; ignoring this poll')
    } else if (seq > this.highWater) {
      this.highWater = seq
    } else if (seq < this.highWater) {
      this.logger.debug(
        `commands.seq went back from ${this.highWater} to ${seq}; keeping ${this.highWater}`
      )
    }
    const out: CloudCommand[] = []
    while (this.delivered < this.highWater) {
      const n = this.delivered + 1
      const result = await this.read(n)
      if (result === 'wait') break
      this.delivered = n
      if (result === 'skip') await this.markHandled(n)
      else out.push(result)
    }
    return out
  }

  /** Record command `n` as handled. `commands.done` advances over the
   *  contiguous handled prefix, so a restart redelivers anything that
   *  was still waiting (e.g. a message queued behind a running turn). */
  async markHandled(n: number): Promise<void> {
    if (n <= this.done) return
    this.handledAbove.add(n)
    let next = this.done
    while (this.handledAbove.has(next + 1)) {
      next++
      this.handledAbove.delete(next)
    }
    await this.persist(next)
  }

  /** Record every command up to `n` as handled (after `stop`, which
   *  discards whatever was still queued). */
  async markHandledThrough(n: number): Promise<void> {
    for (const k of [...this.handledAbove])
      if (k <= n) this.handledAbove.delete(k)
    await this.persist(Math.max(this.done, Math.min(n, this.delivered)))
  }

  private async persist(next: number): Promise<void> {
    if (next <= this.done) return
    this.done = next
    // Writes go out one at a time, always with the latest value.
    this.writing = this.writing
      .catch(() => undefined)
      .then(() => writeAtomic(this.donePath, formatCommandSeq(this.done)))
    await this.writing
  }

  private async read(n: number): Promise<CloudCommand | 'wait' | 'skip'> {
    let text: string | null
    try {
      text = await readKnownText(this.commandPath(n), MAX_COMMAND_BYTES)
    } catch (err) {
      this.logger.warn(
        `command ${n} unreadable (${(err as Error).message}); skipping`
      )
      return 'skip'
    }
    if (text !== null) {
      let json: unknown = undefined
      let complete = true
      try {
        json = JSON.parse(text) as unknown
      } catch {
        complete = false
      }
      if (complete) {
        try {
          const cmd = parseCloudCommand(json)
          if (cmd.id !== n) {
            this.logger.warn(`command ${n} carries id ${cmd.id}; skipping`)
            return 'skip'
          }
          this.stuckSince = null
          return cmd
        } catch (err) {
          if (!(err instanceof ProtocolError)) throw err
          this.logger.warn(`command ${n} is invalid (${err.message}); skipping`)
          return 'skip'
        }
      }
    }
    // Not there yet, or half written: wait out the grace period.
    const now = this.now()
    if (!this.stuckSince || this.stuckSince.n !== n) {
      this.stuckSince = { n, at: now }
      return 'wait'
    }
    if (now - this.stuckSince.at < COMMAND_GRACE_MS) return 'wait'
    this.logger.warn(`command ${n} never became readable; skipping`)
    this.stuckSince = null
    return 'skip'
  }
}
