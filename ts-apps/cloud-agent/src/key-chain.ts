import type { AuthProvider, Logger } from '@repo/legalese-agent'
import {
  AGENT_KEY_LIFETIME_MS,
  AGENT_KEY_RENEW_BEFORE_MS,
  SESSION_HEADER,
  parseAgentKeyError,
  renewAgentKeyResponse,
  tryParse,
  type AgentKeyFailure,
} from '@repo/legalese-agent/protocol'

/** Why a chain ended, as the harness reports it. */
export interface ChainEnded {
  reason: AgentKeyFailure
  /** The renew error said so (vs. transport / upstream failures that
   *  outlasted the key). */
  fromServer: boolean
}

export interface KeyChainOptions {
  /** jl4-auth-proxy base URL (`AUTH_URL`). */
  authUrl: string
  sessionId: string
  /** The key from `AGENT_KEY`. */
  initialKey: string
  logger: Logger
  /** Called once when the chain can't continue. */
  onEnded: (ended: ChainEnded) => void
  fetch?: typeof fetch
  now?: () => number
  /** Backoff between retries of a transient renew failure. */
  retryDelaysMs?: number[]
}

const DEFAULT_RETRY_DELAYS_MS = [2_000, 5_000, 10_000, 20_000, 30_000]

/**
 * {@link AuthProvider} over an agent key chain (spec §6.2, §15.5).
 *
 * - The key from `AGENT_KEY` is renewed immediately at start, which
 *   deletes it (it was visible in the `RunTask` overrides).
 * - After that it renews when 5 minutes of the 15 are left, and when a
 *   request made with the current key comes back 401
 *   ({@link renewAfterUnauthorized}).
 * - `401 invalid_key`, `403 chain_expired`, `403 inactive` and
 *   `409 chain_forked` end the chain. `502 upstream_unavailable` and
 *   network errors are retried with backoff while the key is still
 *   valid: if jl4-auth-proxy had already deleted the old key before
 *   WorkOS failed, the retry answers `invalid_key` and the chain ends
 *   there; if the key runs out first, the chain ends too.
 * - When the chain ends, headers become `{}` (requests fail fast as
 *   unauthenticated) and `onEnded` fires once; the runner parks.
 * - Every ai-proxy request carries `X-Legalese-Session: <sid>`.
 */
export class KeyChainAuth implements AuthProvider {
  private key: string
  /** Epoch ms; unknown for the initial key (renewed at once). */
  private expiresAt: number
  private ended: ChainEnded | null = null
  private renewing: Promise<boolean> | null = null
  private timer: NodeJS.Timeout | null = null
  private stopped = false
  private readonly fetchImpl: typeof fetch
  private readonly now: () => number
  private readonly retryDelays: number[]

  constructor(private readonly opts: KeyChainOptions) {
    this.key = opts.initialKey
    this.fetchImpl = opts.fetch ?? ((...a) => fetch(...a))
    this.now = opts.now ?? Date.now
    this.expiresAt = this.now() + AGENT_KEY_LIFETIME_MS
    this.retryDelays = opts.retryDelaysMs ?? DEFAULT_RETRY_DELAYS_MS
  }

  // ── AuthProvider ───────────────────────────────────────────────────

  async getAiAuthHeaders(): Promise<Record<string, string>> {
    if (this.renewing) await this.renewing
    if (this.ended) return {}
    return {
      Authorization: `Bearer ${this.key}`,
      [SESSION_HEADER]: this.opts.sessionId,
    }
  }

  getEffectiveServiceUrl(): string | undefined {
    return undefined
  }

  // ── Chain ──────────────────────────────────────────────────────────

  /** The chain ended (the runner parks). */
  get endedWith(): ChainEnded | null {
    return this.ended
  }

  get keyExpiresAt(): number {
    return this.expiresAt
  }

  /** Is `authorization` (a header value) the current key? */
  isCurrent(authorization: string | null | undefined): boolean {
    return !!authorization && authorization === `Bearer ${this.key}`
  }

  /** Renew now (at start), then keep renewing on schedule. Resolves
   *  false when the chain ended. */
  async start(): Promise<boolean> {
    const ok = await this.renew('start')
    this.schedule()
    return ok
  }

  /**
   * A request made with `usedAuthorization` came back 401. Renew unless
   * a renewal already replaced that key; resolves true when a newer key
   * is available to retry with.
   */
  async renewAfterUnauthorized(usedAuthorization: string): Promise<boolean> {
    if (this.ended) return false
    if (!this.isCurrent(usedAuthorization)) {
      if (this.renewing) await this.renewing
      return !this.ended
    }
    return this.renew('unauthorized')
  }

  /** `POST /auth/agent-token/end` (best effort) and stop renewing. */
  async end(): Promise<void> {
    this.stopTimer()
    this.stopped = true
    if (this.renewing) await this.renewing.catch(() => false)
    if (this.ended) return
    try {
      const res = await this.fetchImpl(this.url('/auth/agent-token/end'), {
        method: 'POST',
        headers: { Authorization: `Bearer ${this.key}` },
        signal: AbortSignal.timeout(10_000),
      })
      this.opts.logger.info(`agent key chain ended (status ${res.status})`)
    } catch (err) {
      this.opts.logger.warn(`agent key end failed: ${(err as Error).message}`)
    }
  }

  /** Stop the renewal timer (shutdown). */
  stopTimer(): void {
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
  }

  private schedule(): void {
    this.stopTimer()
    if (this.ended || this.stopped) return
    const due = Math.max(
      1_000,
      this.expiresAt - AGENT_KEY_RENEW_BEFORE_MS - this.now()
    )
    this.timer = setTimeout(() => {
      this.timer = null
      void this.renew('scheduled').then(() => this.schedule())
    }, due)
    this.timer.unref()
  }

  private renew(why: string): Promise<boolean> {
    if (this.ended) return Promise.resolve(false)
    if (!this.renewing) {
      this.renewing = this.renewOnce(why).finally(() => {
        this.renewing = null
      })
    }
    return this.renewing
  }

  private async renewOnce(why: string): Promise<boolean> {
    for (let attempt = 0; ; attempt++) {
      const outcome = await this.tryRenew()
      if (outcome === 'ok') {
        this.opts.logger.info(
          `agent key renewed (${why}); expires in ${Math.round((this.expiresAt - this.now()) / 1000)} s`
        )
        return true
      }
      if (outcome !== 'retry') {
        this.finish({ reason: outcome, fromServer: true })
        return false
      }
      const delay = this.retryDelays[attempt]
      if (delay === undefined || this.now() + delay >= this.expiresAt) {
        this.finish({ reason: 'invalid_key', fromServer: false })
        return false
      }
      this.opts.logger.warn(
        `agent key renewal failed transiently; retrying in ${delay} ms`
      )
      await new Promise((r) => setTimeout(r, delay))
      if (this.stopped) return false
    }
  }

  private async tryRenew(): Promise<'ok' | 'retry' | AgentKeyFailure> {
    let res: Response
    try {
      res = await this.fetchImpl(this.url('/auth/agent-token/renew'), {
        method: 'POST',
        headers: { Authorization: `Bearer ${this.key}` },
        signal: AbortSignal.timeout(20_000),
      })
    } catch (err) {
      this.opts.logger.warn(`agent key renewal: ${(err as Error).message}`)
      return 'retry'
    }
    let body: unknown = null
    try {
      body = await res.json()
    } catch {
      // not JSON
    }
    if (res.ok) {
      const parsed = tryParse(renewAgentKeyResponse, body)
      if (!parsed.ok) {
        this.opts.logger.warn(
          `agent key renewal: bad response (${parsed.error})`
        )
        return 'retry'
      }
      this.key = parsed.value.token
      this.expiresAt = parsed.value.expiresAt
      return 'ok'
    }
    const failure = parseAgentKeyError(body)
    this.opts.logger.warn(
      `agent key renewal refused: ${res.status} ${failure ?? 'unknown'}`
    )
    if (failure) return failure
    if (res.status === 401) return 'invalid_key'
    // 502 upstream_unavailable, 5xx, 429 and unknown errors: retry.
    return 'retry'
  }

  private finish(ended: ChainEnded): void {
    if (this.ended) return
    this.ended = ended
    this.stopTimer()
    this.opts.logger.warn(`agent key chain ended: ${ended.reason}`)
    this.opts.onEnded(ended)
  }

  private url(p: string): string {
    return this.opts.authUrl.replace(/\/+$/, '') + p
  }
}

/** `--dev`: no key chain; the local ai-proxy takes `Bearer dev-local`
 *  (stamped by the AiProxyClient in local mode). */
export class DevAuth implements AuthProvider {
  constructor(private readonly sessionId: string) {}

  async getAiAuthHeaders(): Promise<Record<string, string>> {
    return { [SESSION_HEADER]: this.sessionId }
  }

  getEffectiveServiceUrl(): string | undefined {
    return undefined
  }
}

/**
 * Wrap `fetch` so a 401 from one of `origins` for a request that
 * carried the chain's current key triggers a renewal and one retry
 * with the new key (spec §5.4: renew "on 401"). Bodies are strings in
 * both clients (ai-proxy, MCP), so the retry can resend them.
 */
export function authRetryingFetch(
  base: typeof fetch,
  auth: KeyChainAuth,
  origins: string[]
): typeof fetch {
  const allowed = new Set(origins.map((o) => new URL(o).origin))
  return async (input, init) => {
    const res = await base(input, init)
    if (res.status !== 401) return res
    const url =
      typeof input === 'string'
        ? input
        : input instanceof URL
          ? input.href
          : input.url
    let origin: string
    try {
      origin = new URL(url).origin
    } catch {
      return res
    }
    if (!allowed.has(origin)) return res
    const headers = new Headers(init?.headers)
    const used = headers.get('authorization')
    if (!used || !/^Bearer sk_/.test(used)) return res
    if (
      init?.body !== undefined &&
      init.body !== null &&
      typeof init.body !== 'string'
    ) {
      return res
    }
    const renewed = await auth.renewAfterUnauthorized(used)
    if (!renewed) return res
    const fresh = await auth.getAiAuthHeaders()
    if (!fresh.Authorization) return res
    headers.set('authorization', fresh.Authorization)
    await res.body?.cancel().catch(() => undefined)
    return base(input, { ...init, headers })
  }
}
