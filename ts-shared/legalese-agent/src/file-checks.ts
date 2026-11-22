/**
 * What `l4/fileChecked` has said per document, and who is waiting on it.
 * The notification carries its diagnostics, so it can't be overtaken by the
 * debounced publishDiagnostics. One copy of this logic, used by every host,
 * because getting it subtly wrong reports a broken file as clean.
 *
 * `D` is the host's diagnostic type. `key` is whatever the host identifies
 * a document by.
 */
export type CheckOutcome = 'checked' | 'pending' | 'unsupported'

export class FileCheckTracker<D> {
  private readonly checks = new Map<
    string,
    { version: number | null; diagnostics: D[] }
  >()
  private readonly waiters = new Map<string, Array<() => void>>()
  /** Set by the first check. */
  private seen = false
  /** Waited a full timeout without ever hearing from the server. */
  private gaveUp = false

  record(key: string, version: number | null, diagnostics: D[]): void {
    this.seen = true
    this.gaveUp = false
    this.checks.set(key, { version, diagnostics })
    this.wake(key)
  }

  /**
   * Whether the check covers `version` or later. Hosts must {@link forget}
   * a document when it closes: versions restart when it's opened again, so
   * an old entry would otherwise vouch for text it never saw.
   */
  isChecked(key: string, version: number): boolean {
    const check = this.checks.get(key)
    return !!check && (check.version === null || check.version >= version)
  }

  latest(key: string): D[] | undefined {
    return this.checks.get(key)?.diagnostics
  }

  /** Errors per file, counted by `isError`, for every file the server has
   *  reported on, including ones that import an edited file. A file with no
   *  entry hasn't been checked, which is not the same as having none. */
  errorCounts(isError: (diagnostic: D) => boolean): Map<string, number> {
    const counts = new Map<string, number>()
    for (const [key, check] of this.checks) {
      counts.set(key, check.diagnostics.filter(isError).length)
    }
    return counts
  }

  forget(key: string): void {
    this.checks.delete(key)
    this.wake(key)
  }

  /** Forget everything, for a server that went away. */
  clear(): void {
    this.checks.clear()
    for (const key of [...this.waiters.keys()]) this.wake(key)
  }

  /**
   * Wait for `version`'s check. Silence on a first call doesn't prove an
   * older server, because a fresh one can be slow to start, so that call
   * ends as `pending`: never as clean. Only after a full timeout with no
   * check at all does it assume a server without the signal, and answer
   * `unsupported` so the host falls back to its own way of waiting.
   */
  async settle(
    key: string,
    version: number,
    timeoutMs: number
  ): Promise<CheckOutcome> {
    if (this.gaveUp && !this.seen) return 'unsupported'
    if (await this.wait(key, version, timeoutMs)) return 'checked'
    if (!this.seen) this.gaveUp = true
    return 'pending'
  }

  /** Resolves `true` once `version` is checked; `false` after the timeout,
   *  or if the document was forgotten or the state cleared meanwhile. */
  wait(key: string, version: number, timeoutMs: number): Promise<boolean> {
    if (this.isChecked(key, version)) return Promise.resolve(true)
    return new Promise((resolve) => {
      const onChange = (): void => {
        if (this.isChecked(key, version) || !this.checks.has(key)) {
          clearTimeout(timer)
          resolve(this.isChecked(key, version))
          return
        }
        this.listen(key, onChange)
      }
      const timer = setTimeout(() => {
        const still = this.waiters.get(key)
        if (still) {
          this.waiters.set(
            key,
            still.filter((f) => f !== onChange)
          )
        }
        resolve(false)
      }, timeoutMs)
      this.listen(key, onChange)
    })
  }

  private listen(key: string, waiter: () => void): void {
    this.waiters.set(key, [...(this.waiters.get(key) ?? []), waiter])
  }

  private wake(key: string): void {
    const waiting = this.waiters.get(key)
    if (!waiting) return
    this.waiters.delete(key)
    for (const w of waiting) w()
  }
}
