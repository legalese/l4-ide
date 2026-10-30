import { promises as fs, constants } from 'node:fs'
import * as path from 'node:path'
import {
  EVENT_SEGMENT_MAX_BYTES,
  FIRST_EVENT_SEGMENT,
  ProtocolError,
  cloudEvent,
  formatEventLine,
  parseHeadFile,
  type CloudEvent,
  type CloudEventPayload,
  type HeadFile,
} from '@repo/legalese-agent/protocol'
import type { Logger } from '@repo/legalese-agent'
import {
  appendToFile,
  readKnownFile,
  readKnownText,
  writeAtomic,
} from './safe-fs.js'
import type { WriteFence } from './lease.js'

/** Deltas are coalesced for at least this long (§8). */
export const DELTA_COALESCE_MS = 250

/** After a failed write, the batch is tried again after these delays
 *  (the last repeats). */
export const WRITE_RETRY_DELAYS_MS: readonly number[] = [
  500, 1_000, 2_000, 5_000, 10_000,
]

/** Halvings of an oversized field before an event is given up on. */
const SHRINK_ATTEMPTS = 24

type DeltaPayload = Extract<
  CloudEventPayload,
  { type: 'text-delta' | 'thinking-delta' }
>

/**
 * The session's append-only event log (spec §8):
 * `state/events/<n>.jsonl` segments of JSON lines `{ seq, ts, type, … }`
 * plus `state/head.json { segment, length }`, rewritten (temp file +
 * rename) after each batch. Readers only read a segment up to the
 * length `head.json` gives, so a batch becomes visible atomically.
 *
 * - `seq` continues across restarts (recovered from the log's tail).
 * - Bytes past `head.length` (a batch written before a crash, never
 *   published) are truncated at open.
 * - A new segment starts when the current one would pass 1 MB.
 * - `text-delta` / `thinking-delta` events for the same conversation
 *   are merged and written at most every 250 ms; any other event
 *   flushes them first, so order is kept.
 * - Every event is validated against the protocol before it's written.
 *   A field over its limit (a huge tool result) is cut down until the
 *   event fits; an event invalid for another reason is logged and
 *   dropped rather than breaking readers.
 * - A failed write (an I/O error on the mount) publishes nothing: the
 *   batch stays queued, in order, and is written again after a delay;
 *   `seq` only moves once a batch is published, so it stays contiguous.
 *   Bytes the failed write may have appended are truncated first.
 */
export class EventLog {
  private head: HeadFile = { segment: FIRST_EVENT_SEGMENT, length: 0 }
  private seq = 0
  private pending: CloudEventPayload[] = []
  private delta: DeltaPayload | null = null
  private deltaTimer: NodeJS.Timeout | null = null
  private flushTimer: NodeJS.Timeout | null = null
  private retryTimer: NodeJS.Timeout | null = null
  private failures = 0
  /** A write failed after it may have appended: truncate before the next. */
  private unclean = false
  /** {@link close}d: nothing is written any more. */
  private closed = false
  private writing: Promise<void> = Promise.resolve()
  private readonly now: () => number
  private readonly fence: WriteFence | undefined
  private readonly retryDelays: readonly number[]
  private readonly append: typeof appendToFile

  constructor(
    private readonly stateDir: string,
    private readonly logger: Logger,
    opts: {
      now?: () => number
      retryDelaysMs?: readonly number[]
      /** Tests inject failures here. */
      append?: typeof appendToFile
      /** Checked before every write (§7.3). */
      fence?: WriteFence
    } = {}
  ) {
    this.fence = opts.fence
    this.now = opts.now ?? Date.now
    this.retryDelays = opts.retryDelaysMs ?? WRITE_RETRY_DELAYS_MS
    this.append = opts.append ?? appendToFile
  }

  private get headPath(): string {
    return path.join(this.stateDir, 'head.json')
  }

  private segmentPath(n: number): string {
    return path.join(this.stateDir, 'events', `${n}.jsonl`)
  }

  /** The last `seq` written. */
  get lastSeq(): number {
    return this.seq
  }

  /** Recover the head and the last `seq` from a previous run. */
  async open(): Promise<void> {
    this.fence?.check('events')
    await fs.mkdir(path.join(this.stateDir, 'events'), { recursive: true })
    const text = await readKnownText(this.headPath, 4096)
    if (text === null) {
      // Nothing was ever published; drop a segment a crashed first
      // batch may have left.
      await fs.rm(this.segmentPath(FIRST_EVENT_SEGMENT), { force: true })
      return
    }
    let head: HeadFile
    try {
      head = parseHeadFile(text)
    } catch (err) {
      throw new Error(`head.json is invalid: ${(err as Error).message}`)
    }
    this.head = head
    const file = this.segmentPath(head.segment)
    const buf = await readKnownFile(file, EVENT_SEGMENT_MAX_BYTES * 64)
    if (buf === null && head.length === 0) {
      // A fresh head segment nothing was written to yet.
      this.seq = await this.lastSeqBefore(head.segment)
      return
    }
    if (buf === null || buf.length < head.length) {
      // head.json got ahead of its segment (the segment's bytes never
      // reached the disk): keep what is there and go on in a fresh
      // segment, so no reader's offset into this one is ever reused.
      this.logger.warn(
        `event-log: head segment ${buf === null ? 'is missing' : 'is shorter than head.json says'}; continuing in a new segment`
      )
      this.seq = buf ? lastSeqIn(buf) : 0
      if (this.seq === 0) this.seq = await this.lastSeqBefore(head.segment)
      this.head = { segment: head.segment + 1, length: 0 }
      await fs.rm(this.segmentPath(this.head.segment), { force: true })
      await writeAtomic(this.headPath, JSON.stringify(this.head) + '\n')
      return
    }
    if (buf.length > head.length) {
      // Written but never published: drop it.
      const h = await fs.open(file, constants.O_WRONLY | constants.O_NOFOLLOW)
      try {
        await h.truncate(head.length)
      } finally {
        await h.close()
      }
    }
    this.seq = lastSeqIn(buf.subarray(0, head.length))
    // An empty head segment right after a rollover: look back.
    if (this.seq === 0) this.seq = await this.lastSeqBefore(head.segment)
  }

  /** The last `seq` in the segments before `segment` (0 when none). */
  private async lastSeqBefore(segment: number): Promise<number> {
    for (let n = segment - 1; n >= FIRST_EVENT_SEGMENT; n--) {
      const prev = await readKnownFile(
        this.segmentPath(n),
        EVENT_SEGMENT_MAX_BYTES * 64
      )
      const seq = prev ? lastSeqIn(prev) : 0
      if (seq > 0) return seq
      // A segment can be empty only right after a rollover: one more.
      if (n < segment - 2) break
    }
    return 0
  }

  /**
   * Stop writing (at shutdown, before the lease is released): timers
   * are cancelled and nothing queued after this is written. A write
   * already running can't be called back.
   */
  close(): void {
    this.closed = true
    for (const t of [this.flushTimer, this.retryTimer, this.deltaTimer]) {
      if (t) clearTimeout(t)
    }
    this.flushTimer = this.retryTimer = this.deltaTimer = null
    const unwritten = this.pending.length + (this.delta ? 1 : 0)
    if (unwritten > 0) {
      this.logger.warn(`event-log: ${unwritten} event(s) not written at exit`)
    }
    this.pending = []
    this.delta = null
  }

  /** Queue an event. Returns once it's queued, not written. */
  emit(payload: CloudEventPayload): void {
    if (this.closed) return
    if (payload.type === 'text-delta' || payload.type === 'thinking-delta') {
      if (
        this.delta &&
        this.delta.type === payload.type &&
        this.delta.conversationId === payload.conversationId
      ) {
        this.delta = { ...this.delta, text: this.delta.text + payload.text }
      } else {
        if (this.delta) {
          this.takeDelta()
          this.scheduleFlush()
        }
        this.delta = { ...payload }
      }
      if (!this.deltaTimer) {
        this.deltaTimer = setTimeout(() => {
          this.deltaTimer = null
          this.takeDelta()
          this.scheduleFlush()
        }, DELTA_COALESCE_MS)
      }
      return
    }
    this.takeDelta()
    this.pending.push(payload)
    this.scheduleFlush()
  }

  /** Write everything queued, including a pending delta. */
  async flush(): Promise<void> {
    this.takeDelta()
    await this.writePending()
  }

  /** Write queued events, leaving a delta that is still collecting.
   *  Rejects when the write fails; the events stay queued for a retry. */
  private async writePending(): Promise<void> {
    if (this.flushTimer) {
      clearTimeout(this.flushTimer)
      this.flushTimer = null
    }
    const run = this.writing
      .catch(() => undefined)
      .then(async () => {
        // Taken when it's this write's turn, so a retry also carries
        // whatever was queued meanwhile, in order.
        if (this.closed) return
        const batch = this.pending
        this.pending = []
        if (batch.length === 0) return
        try {
          await this.write(batch)
        } catch (err) {
          this.pending = [...batch, ...this.pending]
          this.unclean = true
          if (!this.closed) this.scheduleRetry()
          throw err
        }
        this.failures = 0
        if (this.retryTimer) {
          clearTimeout(this.retryTimer)
          this.retryTimer = null
        }
      })
    this.writing = run
    await run
  }

  private scheduleRetry(): void {
    if (this.retryTimer) return
    const delay =
      this.retryDelays[Math.min(this.failures, this.retryDelays.length - 1)] ??
      0
    this.failures++
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null
      this.writePending().catch((err) =>
        this.logger.error('event-log: write failed again', err)
      )
    }, delay)
  }

  private takeDelta(): void {
    if (this.deltaTimer) {
      clearTimeout(this.deltaTimer)
      this.deltaTimer = null
    }
    if (this.delta) {
      this.pending.push(this.delta)
      this.delta = null
    }
  }

  private scheduleFlush(): void {
    // Waiting out a failed write: the retry takes these along.
    if (this.flushTimer || this.retryTimer) return
    // Batch whatever arrives in the same tick.
    this.flushTimer = setTimeout(() => {
      this.flushTimer = null
      this.writePending().catch((err) =>
        this.logger.error('event-log: write failed', err)
      )
    }, 0)
  }

  /**
   * Number, append and publish a batch. Nothing in memory changes until
   * `head.json` is written, so a failure leaves `seq` and the head as
   * they were (the caller re-queues the batch).
   */
  private async write(batch: CloudEventPayload[]): Promise<void> {
    this.fence?.check('events')
    if (this.unclean) {
      // The failed write may have appended past the published length.
      await truncateTo(this.segmentPath(this.head.segment), this.head.length)
      this.unclean = false
    }
    let seq = this.seq
    const lines: string[] = []
    for (const payload of batch) {
      const event = this.validated(payload, seq + 1)
      if (!event) continue
      seq++
      lines.push(formatEventLine(event))
    }
    if (lines.length === 0) return
    let head = { ...this.head }
    let chunk = ''
    const commit = async (): Promise<void> => {
      if (!chunk) return
      this.fence?.check('events')
      await this.append(this.segmentPath(head.segment), chunk)
      head = {
        segment: head.segment,
        length: head.length + Buffer.byteLength(chunk),
      }
      chunk = ''
    }
    for (const line of lines) {
      const bytes = Buffer.byteLength(line)
      const used = head.length + Buffer.byteLength(chunk)
      if (used > 0 && used + bytes > EVENT_SEGMENT_MAX_BYTES) {
        await commit()
        head = { segment: head.segment + 1, length: 0 }
        // A crash or failed write after a previous rollover may have
        // left this segment behind, unpublished.
        await fs.rm(this.segmentPath(head.segment), { force: true })
      }
      chunk += line
    }
    await commit()
    this.fence?.check('head.json')
    await writeAtomic(this.headPath, JSON.stringify(head) + '\n')
    this.head = head
    this.seq = seq
  }

  /** The event as written, or null to drop it. An oversized field is cut
   *  down (halved, with a note of how much went) until the event fits. */
  private validated(
    payload: CloudEventPayload,
    seq: number
  ): CloudEvent | null {
    let candidate: Record<string, unknown> = { seq, ts: this.now(), ...payload }
    for (let attempt = 0; ; attempt++) {
      try {
        return cloudEvent(candidate, 'event')
      } catch (err) {
        if (!(err instanceof ProtocolError)) throw err
        const smaller =
          attempt < SHRINK_ATTEMPTS && SIZE_ERROR_RE.test(err.message)
            ? shrinkField(candidate, err.path)
            : null
        if (!smaller) {
          this.logger.error(
            `event-log: dropping invalid ${payload.type} event`,
            err
          )
          return null
        }
        candidate = smaller
      }
    }
  }
}

/** A validation error about a size limit (protocol/validate.ts). */
const SIZE_ERROR_RE = /: (?:longer|larger|more) than /

/** Marker appended where an event field was cut down to fit. */
export function truncationNote(dropped: number): string {
  return `…[truncated ${dropped} chars]`
}

/**
 * `event` with the top-level field a validation error points at
 * (`event.result`, `event.files[3]`) made smaller: a string halved, an
 * array halved, a JSON value replaced by a short preview. Null when the
 * error isn't about such a field.
 */
function shrinkField(
  event: Record<string, unknown>,
  errPath: string
): Record<string, unknown> | null {
  const m = /^event\.([A-Za-z]+)(?:\[(\d+)\])?/.exec(errPath)
  const field = m?.[1]
  if (!field || !(field in event) || field === 'type') return null
  const v = event[field]
  if (Array.isArray(v) && m?.[2] !== undefined) {
    // One item too long (a file name): cut that item.
    const i = Number(m[2])
    const item = v[i]
    if (typeof item !== 'string') return null
    const cut = shrinkField({ item }, 'event.item')?.item
    if (cut === undefined) return null
    return { ...event, [field]: v.map((x, k) => (k === i ? cut : x)) }
  }
  if (typeof v === 'string') {
    // Count what was dropped from the original, across repeated cuts.
    const original = originalLength(v)
    const kept = stripNote(v).slice(0, Math.floor(stripNote(v).length / 2))
    if (kept.length === stripNote(v).length) return null
    return { ...event, [field]: kept + truncationNote(original - kept.length) }
  }
  if (Array.isArray(v)) {
    if (v.length === 0) return null
    return { ...event, [field]: v.slice(0, Math.floor(v.length / 2)) }
  }
  if (v !== null && typeof v === 'object') {
    let text: string
    try {
      text = JSON.stringify(v)
    } catch {
      return null
    }
    if (text.length <= 10_000) return null
    return {
      ...event,
      [field]: {
        truncated: true,
        preview: text.slice(0, 10_000) + truncationNote(text.length - 10_000),
      },
    }
  }
  return null
}

const NOTE_RE = /…\[truncated (\d+) chars\]$/

function stripNote(s: string): string {
  return s.replace(NOTE_RE, '')
}

function originalLength(s: string): number {
  const m = NOTE_RE.exec(s)
  return m ? stripNote(s).length + Number(m[1]) : s.length
}

/** Cut `file` back to `length` bytes (a no-op when it's missing). */
async function truncateTo(file: string, length: number): Promise<void> {
  let h: fs.FileHandle
  try {
    h = await fs.open(file, constants.O_WRONLY | constants.O_NOFOLLOW)
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === 'ENOENT') return
    throw err
  }
  try {
    const st = await h.stat()
    if (st.size > length) await h.truncate(length)
  } finally {
    await h.close()
  }
}

/** The `seq` of the last complete line in a segment (0 when none). */
function lastSeqIn(buf: Buffer): number {
  const text = buf.toString('utf8')
  const lines = text.split('\n')
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i]!.trim()
    if (!line) continue
    try {
      const v = JSON.parse(line) as { seq?: unknown }
      if (typeof v.seq === 'number' && Number.isSafeInteger(v.seq)) return v.seq
    } catch {
      // a torn line; keep looking
    }
  }
  return 0
}
