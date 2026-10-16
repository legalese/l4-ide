/** Test doubles for the cloud-session unit tests. */
import type { Logger } from '@repo/legalese-agent'

export const SID = '01K6B8Z6X9Q4M2N7P3R5T8V0WA'

/** Sequential ULID-shaped ids for tests. */
export function sid(n: number): string {
  return `01K6B8Z6X9Q4M2N7P3R5T8${String(n).padStart(4, '0')}`
}

export async function flush(): Promise<void> {
  for (let i = 0; i < 10; i++) await new Promise((r) => setImmediate(r))
}

/** Manual clock and timers. */
export class FakeClock {
  t = 0
  private timers: Array<{ at: number; fn: () => void; id: number }> = []
  private nextId = 1

  now = (): number => this.t

  setTimer = (fn: () => void, ms: number): unknown => {
    const id = this.nextId++
    this.timers.push({ at: this.t + ms, fn, id })
    return id
  }

  clearTimer = (h: unknown): void => {
    this.timers = this.timers.filter((x) => x.id !== h)
  }

  /** Delay of the earliest pending timer, or undefined. */
  pending(): number | undefined {
    if (this.timers.length === 0) return undefined
    return Math.min(...this.timers.map((x) => x.at)) - this.t
  }

  /** Advance, firing due timers (and letting their async work settle). */
  async advance(ms: number): Promise<void> {
    const end = this.t + ms
    for (;;) {
      await flush()
      const due = this.timers
        .filter((x) => x.at <= end)
        .sort((a, b) => a.at - b.at)[0]
      if (!due) break
      this.t = Math.max(this.t, due.at)
      this.timers = this.timers.filter((x) => x.id !== due.id)
      due.fn()
    }
    this.t = end
    await flush()
  }
}

export class MemoryLogger implements Logger {
  lines: string[] = []
  info(m: string): void {
    this.lines.push(`info ${m}`)
  }
  warn(m: string): void {
    this.lines.push(`warn ${m}`)
  }
  error(m: string): void {
    this.lines.push(`error ${m}`)
  }
  debug(): void {}
}
