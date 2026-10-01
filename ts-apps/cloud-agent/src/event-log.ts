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

/** Deltas are coalesced for at least this long (§8). */
export const DELTA_COALESCE_MS = 250

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
 * - Every event is validated against the protocol before it's written;
 *   an invalid one is logged and dropped rather than breaking readers.
 */
export class EventLog {
  private head: HeadFile = { segment: FIRST_EVENT_SEGMENT, length: 0 }
  private seq = 0
  private pending: CloudEventPayload[] = []
  private delta: DeltaPayload | null = null
  private deltaTimer: NodeJS.Timeout | null = null
  private flushTimer: NodeJS.Timeout | null = null
  private writing: Promise<void> = Promise.resolve()
  private readonly now: () => number

  constructor(
    private readonly stateDir: string,
    private readonly logger: Logger,
    opts: { now?: () => number } = {}
  ) {
    this.now = opts.now ?? Date.now
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
    if (buf === null) {
      if (head.length > 0) throw new Error('head segment is missing')
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
    } else if (buf.length < head.length) {
      throw new Error('head segment is shorter than head.json says')
    }
    this.seq = lastSeqIn(buf.subarray(0, head.length))
    if (this.seq === 0 && head.segment > FIRST_EVENT_SEGMENT) {
      // An empty head segment right after a rollover: look back one.
      const prev = await readKnownFile(
        this.segmentPath(head.segment - 1),
        EVENT_SEGMENT_MAX_BYTES * 64
      )
      if (prev) this.seq = lastSeqIn(prev)
    }
  }

  /** Queue an event. Returns once it's queued, not written. */
  emit(payload: CloudEventPayload): void {
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

  /** Write queued events, leaving a delta that is still collecting. */
  private async writePending(): Promise<void> {
    if (this.flushTimer) {
      clearTimeout(this.flushTimer)
      this.flushTimer = null
    }
    const batch = this.pending
    this.pending = []
    this.writing = this.writing.then(() => this.write(batch))
    await this.writing
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
    if (this.flushTimer) return
    // Batch whatever arrives in the same tick.
    this.flushTimer = setTimeout(() => {
      this.flushTimer = null
      this.writePending().catch((err) =>
        this.logger.error('event-log: write failed', err)
      )
    }, 0)
  }

  private async write(batch: CloudEventPayload[]): Promise<void> {
    if (batch.length === 0) return
    const lines: string[] = []
    for (const payload of batch) {
      const candidate = { seq: this.seq + 1, ts: this.now(), ...payload }
      let event: CloudEvent
      try {
        event = cloudEvent(candidate, 'event')
      } catch (err) {
        if (!(err instanceof ProtocolError)) throw err
        this.logger.error(
          `event-log: dropping invalid ${payload.type} event`,
          err
        )
        continue
      }
      this.seq++
      lines.push(formatEventLine(event))
    }
    let chunk = ''
    const commit = async (): Promise<void> => {
      if (!chunk) return
      await appendToFile(this.segmentPath(this.head.segment), chunk)
      this.head = {
        segment: this.head.segment,
        length: this.head.length + Buffer.byteLength(chunk),
      }
      chunk = ''
    }
    for (const line of lines) {
      const bytes = Buffer.byteLength(line)
      const used = this.head.length + Buffer.byteLength(chunk)
      if (used > 0 && used + bytes > EVENT_SEGMENT_MAX_BYTES) {
        await commit()
        this.head = { segment: this.head.segment + 1, length: 0 }
        // A crash after a previous rollover may have left this segment
        // behind, unpublished.
        await fs.rm(this.segmentPath(this.head.segment), { force: true })
      }
      chunk += line
    }
    await commit()
    await writeAtomic(this.headPath, JSON.stringify(this.head) + '\n')
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
