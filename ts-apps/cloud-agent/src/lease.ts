import { promises as fs } from 'node:fs'
import * as path from 'node:path'
import {
  LEASE_RENEW_MS,
  LEASE_TTL_MS,
  ProtocolError,
  parseRunLeaseFile,
  parseRunRecordFile,
  type RunLeaseFile,
} from '@repo/legalese-agent/protocol'
import type { Logger } from '@repo/legalese-agent'
import { isErrno, readKnownText, writeAtomic } from './safe-fs.js'

/**
 * Run records. The Sessions API decides who runs a session:
 * its `start` exclusive-creates `state/runs/<n>.json` and writes run n's
 * lease as `starting`, then starts a task with `SESSION_RUN=<n>`. The
 * harness never decides; it only proves it is the current run, and stops
 * writing the moment it can't:
 *
 * - **Boot** ({@link checkRun}): `runs/<n>.json` exists, `runs/<n+1>.json`
 *   doesn't, and run n's lease is still valid with the margin.
 * - **Lease** ({@link RunLease}): `runs/<n>.lease.json`, rewritten (temp
 *   file + rename) at boot, every 30 s and on state change with 90 s
 *   validity; each renewal also checks that `runs/<n+1>.json` doesn't
 *   exist. Released as the last write of a shutdown.
 * - **Fence** ({@link Fence}): every write checks that the last lease
 *   written is valid by this clock for {@link FENCE_MARGIN_MS} more. A
 *   failed or late renewal stops all writes before the lease runs out,
 *   and the Sessions API only creates run n+1 once it has.
 */

/** Writes stop this long before the last written lease runs out. */
export const FENCE_MARGIN_MS = 15_000

/** This run may not (or no longer) write: a newer run exists, or its
 *  lease couldn't be kept valid. */
export class SupersededError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'SupersededError'
  }
}

/** What writers check before every write (see {@link Fence}). */
export interface WriteFence {
  /** Throws {@link SupersededError} when this run may not write. */
  check(what: string): void
}

/**
 * The run's permission to write. Armed with the lease the Sessions API
 * wrote when it created the run, then with each lease the harness writes;
 * closed for good after the final (expired) lease.
 */
export class Fence implements WriteFence {
  private validUntil = 0
  private closed = false
  private violated = false
  private readonly now: () => number
  private readonly marginMs: number
  /** Called once, at the first refused write that wasn't after
   *  {@link close} (the runner stops then). */
  onViolation: ((reason: string) => void) | undefined

  constructor(
    opts: {
      now?: () => number
      marginMs?: number
      onViolation?: (reason: string) => void
    } = {}
  ) {
    this.now = opts.now ?? Date.now
    this.marginMs = opts.marginMs ?? FENCE_MARGIN_MS
    this.onViolation = opts.onViolation
  }

  /** A lease valid until `expiresAt` was written (or found at boot). The
   *  latest write is what the Sessions API reads, even when it is shorter
   *  than the one before (the harness's 90 s replacing the 3 min
   *  `starting` lease). */
  renewed(expiresAt: number): void {
    if (!this.closed) this.validUntil = expiresAt
  }

  check(what: string): void {
    if (this.closed) throw new SupersededError(`${what}: the run has ended`)
    if (this.now() < this.validUntil - this.marginMs) return
    const reason = `${what}: the run's lease is no longer valid`
    if (!this.violated) {
      this.violated = true
      this.onViolation?.(reason)
    }
    throw new SupersededError(reason)
  }

  /** Superseded: no write is allowed any more (also not the final lease). */
  get isViolated(): boolean {
    return this.violated
  }

  /** After the final lease: nothing is written by this run again. */
  close(): void {
    this.closed = true
  }

  get isClosed(): boolean {
    return this.closed
  }
}

function runsDir(stateDir: string): string {
  return path.join(stateDir, 'runs')
}

function recordPath(stateDir: string, n: number): string {
  return path.join(runsDir(stateDir), `${n}.json`)
}

function leasePath(stateDir: string, n: number): string {
  return path.join(runsDir(stateDir), `${n}.lease.json`)
}

/** Whether a newer run than `run` has been created. */
export async function newerRunExists(
  stateDir: string,
  run: number
): Promise<boolean> {
  try {
    await fs.lstat(recordPath(stateDir, run + 1))
    return true
  } catch (err) {
    if (isErrno(err, 'ENOENT')) return false
    throw err
  }
}

/**
 * Whether this harness is run `run` and may start: its record
 * exists, no newer run's does, and the lease written for it (the Sessions
 * API's `starting` lease, or an earlier write) is still valid with the
 * margin. Writes nothing. Returns the lease's expiry to arm the fence
 * with, or the reason it may not run.
 */
export async function checkRun(
  stateDir: string,
  run: number,
  now = Date.now()
): Promise<{ ok: true; validUntil: number } | { ok: false; why: string }> {
  const record = await readKnownText(recordPath(stateDir, run), 4096)
  if (record === null) return { ok: false, why: `run ${run} has no record` }
  try {
    parseRunRecordFile(record, run)
  } catch (err) {
    if (err instanceof ProtocolError) {
      return { ok: false, why: `run ${run}'s record is invalid` }
    }
    throw err
  }
  if (await newerRunExists(stateDir, run)) {
    return { ok: false, why: `run ${run + 1} exists` }
  }
  const text = await readKnownText(leasePath(stateDir, run), 16 * 1024)
  let lease: RunLeaseFile | null = null
  try {
    lease = text === null ? null : parseRunLeaseFile(text, run)
  } catch (err) {
    if (!(err instanceof ProtocolError)) throw err
  }
  if (!lease) return { ok: false, why: `run ${run} has no valid lease` }
  if (now >= lease.expiresAt - FENCE_MARGIN_MS) {
    return {
      ok: false,
      why: `run ${run}'s lease ran out before the harness started`,
    }
  }
  return { ok: true, validUntil: lease.expiresAt }
}

export type HarnessLeaseState = Exclude<RunLeaseFile['state'], 'starting'>

/**
 * Run n's lease, `state/runs/<n>.lease.json { run, taskId, state,
 * turnId?, expiresAt }`. Every write goes through the fence and
 * re-arms it; a renewal first checks that no newer run exists and stops
 * the run (via `onSuperseded`) when one does. Releasing writes it expired
 * instead of deleting it, then closes the fence.
 */
export class RunLease {
  private state: HarnessLeaseState = 'running'
  private turnId: string | undefined
  private timer: NodeJS.Timeout | null = null
  private held = false
  private writing: Promise<void> = Promise.resolve()
  private readonly now: () => number
  private readonly ttlMs: number
  private readonly renewMs: number
  private readonly writeFile: typeof writeAtomic

  constructor(
    private readonly stateDir: string,
    readonly run: number,
    readonly taskId: string,
    private readonly fence: Fence,
    private readonly logger: Logger,
    private readonly opts: {
      now?: () => number
      ttlMs?: number
      renewMs?: number
      /** A newer run exists: stop at once (the runner). */
      onSuperseded?: (why: string) => void
      /** Tests inject failing writes here. */
      writeFile?: typeof writeAtomic
    } = {}
  ) {
    this.now = opts.now ?? Date.now
    this.ttlMs = opts.ttlMs ?? LEASE_TTL_MS
    this.renewMs = opts.renewMs ?? LEASE_RENEW_MS
    this.writeFile = opts.writeFile ?? writeAtomic
  }

  private get file(): string {
    return leasePath(this.stateDir, this.run)
  }

  /** Write the first lease (the fence was armed by {@link checkRun}) and
   *  renew it from now on. */
  async start(): Promise<void> {
    this.held = true
    await this.write()
    this.timer = setInterval(() => void this.renew(), this.renewMs)
    this.timer.unref()
  }

  /** Renew, unless a newer run exists (then stop). Failures are logged:
   *  the fence stops writes before the last good lease runs out. */
  async renew(): Promise<void> {
    if (!this.held) return
    try {
      if (await newerRunExists(this.stateDir, this.run)) {
        this.stop()
        this.opts.onSuperseded?.(`run ${this.run + 1} exists`)
        return
      }
      await this.write()
    } catch (err) {
      if (err instanceof SupersededError) return
      this.logger.error('lease: renew failed', err)
    }
  }

  /** Update the state the lease advertises (`busy` while a turn runs,
   *  `waiting` while an ask_user question is pending). */
  async set(state: HarnessLeaseState, turnId?: string): Promise<void> {
    if (this.state === state && this.turnId === turnId) return
    this.state = state
    this.turnId = state === 'running' ? undefined : turnId
    if (this.held) await this.write()
  }

  get current(): { state: HarnessLeaseState; turnId?: string } {
    return { state: this.state, turnId: this.turnId }
  }

  /** Stop renewing, without writing (superseded). */
  stop(): void {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
    this.held = false
  }

  /** Stop renewing, write the lease expired, and close the fence: the
   *  last write of this run. */
  async release(): Promise<void> {
    const held = this.held
    this.stop()
    try {
      if (held) await this.write(true)
    } finally {
      this.fence.close()
    }
  }

  private write(expired = false): Promise<void> {
    const run = async (): Promise<void> => {
      this.fence.check('lease')
      const expiresAt = this.now() + (expired ? 0 : this.ttlMs)
      const lease: RunLeaseFile = {
        run: this.run,
        taskId: this.taskId,
        state: this.state,
        ...(this.turnId ? { turnId: this.turnId } : {}),
        expiresAt,
      }
      await this.writeFile(this.file, JSON.stringify(lease) + '\n')
      if (!expired) this.fence.renewed(expiresAt)
    }
    this.writing = this.writing.catch(() => undefined).then(run)
    return this.writing
  }
}
