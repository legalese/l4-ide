/**
 * Polls `GET /events` for the cloud sessions this window watches
 * (spec §8, "Polling"):
 *
 * - every second while any watched session is `busy` (or `starting`,
 *   so a cold start shows up as soon as it's ready),
 * - every 5 s while the active ones are `running` or `waiting`,
 * - not at all for `sleeping` / `parked` sessions until the user acts
 *   ({@link EventPoller.poke}); after an action a session is polled for
 *   a grace period whatever its state, since a start takes a moment to
 *   show up in ECS,
 * - immediately again when a response says `more`.
 *
 * Up to 10 sessions share one request; more are split across requests.
 * No `vscode` import; timers are injectable for tests.
 */
import {
  MAX_EVENT_STREAMS,
  parseCursor,
  type EventCursor,
  type EventStreamError,
  type EventStreamRequest,
  type EventStreamResponse,
  type SessionState,
} from '@repo/legalese-agent/protocol'

export const POLL_BUSY_MS = 1_000
export const POLL_IDLE_MS = 5_000
/** How long after a user action a session is polled regardless of state. */
export const POLL_GRACE_MS = 90_000
const BACKOFF_MS = [2_000, 5_000, 10_000, 30_000]

export interface PollerDeps {
  getEvents(
    streams: EventStreamRequest[]
  ): Promise<{ streams: Array<EventStreamResponse | EventStreamError> }>
  /** Called once per session entry, in response order. Exceptions are
   *  logged and don't stop polling. */
  onStream(stream: EventStreamResponse | EventStreamError): void | Promise<void>
  onError?(err: unknown): void
  now?: () => number
  setTimer?: (fn: () => void, ms: number) => unknown
  clearTimer?: (handle: unknown) => void
}

interface Watched {
  cursor: EventCursor
  state: SessionState | undefined
  graceUntil: number
  /** Bumped when the cursor is reset, so a response to a request made
   *  with the old cursor is ignored. */
  gen: number
}

export class EventPoller {
  private readonly watched = new Map<string, Watched>()
  private timer: unknown
  private timerDue = Infinity
  private polling = false
  private again = false
  private failures = 0
  private disposed = false
  private readonly now: () => number
  private readonly setTimer: (fn: () => void, ms: number) => unknown
  private readonly clearTimer: (handle: unknown) => void

  constructor(private readonly deps: PollerDeps) {
    this.now = deps.now ?? Date.now
    this.setTimer = deps.setTimer ?? ((fn, ms) => setTimeout(fn, ms))
    this.clearTimer =
      deps.clearTimer ??
      ((h) => clearTimeout(h as ReturnType<typeof setTimeout>))
  }

  /** Start (or restart, e.g. from cursor 0 for a replay) watching. */
  watch(
    sid: string,
    opts: { cursor?: EventCursor; state?: SessionState } = {}
  ): void {
    const prev = this.watched.get(sid)
    this.watched.set(sid, {
      cursor: opts.cursor ?? prev?.cursor ?? { segment: 0, offset: 0 },
      state: opts.state ?? prev?.state,
      graceUntil: this.now() + POLL_GRACE_MS,
      gen: (prev?.gen ?? 0) + (opts.cursor ? 1 : 0),
    })
    this.schedule(0)
  }

  unwatch(sid: string): void {
    this.watched.delete(sid)
  }

  isWatching(sid: string): boolean {
    return this.watched.has(sid)
  }

  cursorOf(sid: string): EventCursor | undefined {
    return this.watched.get(sid)?.cursor
  }

  /** The user acted on a session (sent a command, started it): poll it
   *  now and for the grace period. */
  poke(sid: string, state?: SessionState): void {
    const w = this.watched.get(sid)
    if (!w) return this.watch(sid, { state })
    w.graceUntil = this.now() + POLL_GRACE_MS
    if (state) w.state = state
    this.schedule(0)
  }

  dispose(): void {
    this.disposed = true
    if (this.timer !== undefined) this.clearTimer(this.timer)
    this.timer = undefined
    this.watched.clear()
  }

  /** Delay until the next poll for one session; Infinity = don't. */
  private intervalFor(w: Watched, now: number): number {
    switch (w.state) {
      case 'busy':
      case 'starting':
        return POLL_BUSY_MS
      case 'running':
      case 'waiting':
        return POLL_IDLE_MS
      default:
        // sleeping / parked / unknown: only while in the grace period.
        return now < w.graceUntil ? POLL_BUSY_MS : Infinity
    }
  }

  private active(now: number): string[] {
    return [...this.watched.entries()]
      .filter(([, w]) => this.intervalFor(w, now) !== Infinity)
      .map(([sid]) => sid)
  }

  private nextDelay(): number {
    const now = this.now()
    let min = Infinity
    for (const w of this.watched.values()) {
      min = Math.min(min, this.intervalFor(w, now))
    }
    return min
  }

  private schedule(ms: number): void {
    if (this.disposed) return
    if (this.polling) {
      if (ms === 0) this.again = true
      return
    }
    if (ms === Infinity) return
    const due = this.now() + ms
    if (this.timer !== undefined) {
      if (due >= this.timerDue) return
      this.clearTimer(this.timer)
    }
    this.timerDue = due
    this.timer = this.setTimer(() => {
      this.timer = undefined
      this.timerDue = Infinity
      void this.poll()
    }, ms)
  }

  /** One round: every active session, in batches of 10. Exposed for tests. */
  async poll(): Promise<void> {
    if (this.polling || this.disposed) return
    this.polling = true
    this.again = false
    let more = false
    let failed = false
    try {
      const sids = this.active(this.now())
      const batches: string[][] = []
      for (let i = 0; i < sids.length; i += MAX_EVENT_STREAMS) {
        batches.push(sids.slice(i, i + MAX_EVENT_STREAMS))
      }
      const gens = new Map<string, number>()
      const results = await Promise.allSettled(
        batches.map((batch) =>
          this.deps.getEvents(
            batch.flatMap((sessionId) => {
              const w = this.watched.get(sessionId)
              if (!w) return []
              gens.set(sessionId, w.gen)
              return [{ sessionId, cursor: w.cursor }]
            })
          )
        )
      )
      for (const r of results) {
        if (r.status === 'rejected') {
          failed = true
          this.deps.onError?.(r.reason)
          continue
        }
        for (const stream of r.value.streams) {
          const w = this.watched.get(stream.sessionId)
          if (!w || gens.get(stream.sessionId) !== w.gen) continue
          if ('error' in stream) {
            // Gone (deleted elsewhere) or unreadable: stop watching.
            this.watched.delete(stream.sessionId)
          } else {
            const cursor = parseCursor(stream.cursor)
            if (cursor) w.cursor = cursor
            w.state = stream.state
            if (stream.more) more = true
          }
          try {
            await this.deps.onStream(stream)
          } catch (err) {
            this.deps.onError?.(err)
          }
        }
      }
    } finally {
      this.polling = false
    }
    if (failed) {
      const ms = BACKOFF_MS[Math.min(this.failures, BACKOFF_MS.length - 1)]!
      this.failures++
      this.schedule(this.watched.size > 0 ? ms : Infinity)
      return
    }
    this.failures = 0
    this.schedule(more || this.again ? 0 : this.nextDelay())
  }
}
