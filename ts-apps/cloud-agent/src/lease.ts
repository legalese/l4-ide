import * as path from 'node:path'
import {
  LEASE_RENEW_MS,
  LEASE_TTL_MS,
  isLeaseLive,
  parseLeaseFile,
  type LeaseFile,
  type LeaseState,
} from '@repo/legalese-agent/protocol'
import type { Logger } from '@repo/legalese-agent'
import { readKnownText, writeAtomic } from './safe-fs.js'

export class LeaseHeldError extends Error {
  constructor(readonly holder: string) {
    super(`another harness holds the lease (${holder})`)
    this.name = 'LeaseHeldError'
  }
}

/**
 * The liveness lease, `state/lease.json { taskId, state, turnId?,
 * expiresAt }` (spec §7.3): rewritten every 30 s (temp file + rename)
 * with 90 s validity, and whenever the state changes. A harness that
 * finds another task's live lease at start refuses to run, which
 * handles duplicate starts.
 *
 * Releasing writes an already-expired lease rather than deleting the
 * file: the Sessions API reads it by name, and a deleted name would be
 * cached as missing by its NFS client when the next harness writes it.
 */
export class Lease {
  private state: LeaseState = 'running'
  private turnId: string | undefined
  private timer: NodeJS.Timeout | null = null
  private held = false
  private writing: Promise<void> = Promise.resolve()
  private readonly now: () => number

  constructor(
    private readonly stateDir: string,
    readonly taskId: string,
    private readonly logger: Logger,
    opts: { now?: () => number } = {}
  ) {
    this.now = opts.now ?? Date.now
  }

  private get file(): string {
    return path.join(this.stateDir, 'lease.json')
  }

  /** Take the lease, or throw {@link LeaseHeldError}. */
  async acquire(): Promise<void> {
    const text = await readKnownText(this.file, 16 * 1024)
    if (text !== null) {
      let existing: LeaseFile | null = null
      try {
        existing = parseLeaseFile(text)
      } catch {
        this.logger.warn('lease.json is invalid; taking over')
      }
      if (
        existing &&
        existing.taskId !== this.taskId &&
        isLeaseLive(existing, this.now())
      ) {
        throw new LeaseHeldError(existing.taskId)
      }
    }
    this.held = true
    await this.write()
    this.timer = setInterval(() => {
      this.write().catch((err) => this.logger.error('lease: renew failed', err))
    }, LEASE_RENEW_MS)
    this.timer.unref()
  }

  /** Update the state the lease advertises (`busy` while a turn runs,
   *  `waiting` while an ask_user question is pending). */
  async set(state: LeaseState, turnId?: string): Promise<void> {
    if (this.state === state && this.turnId === turnId) return
    this.state = state
    this.turnId = state === 'running' ? undefined : turnId
    if (this.held) await this.write()
  }

  get current(): { state: LeaseState; turnId?: string } {
    return { state: this.state, turnId: this.turnId }
  }

  /** Stop renewing and write an expired lease. */
  async release(): Promise<void> {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
    if (!this.held) return
    this.held = false
    await this.write(0)
  }

  private write(ttl = LEASE_TTL_MS): Promise<void> {
    const lease: LeaseFile = {
      taskId: this.taskId,
      state: this.state,
      ...(this.turnId ? { turnId: this.turnId } : {}),
      expiresAt: this.now() + ttl,
    }
    this.writing = this.writing
      .catch(() => undefined)
      .then(() => writeAtomic(this.file, JSON.stringify(lease) + '\n'))
    return this.writing
  }
}
