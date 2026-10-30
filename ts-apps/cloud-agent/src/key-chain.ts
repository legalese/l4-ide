import {
  isInvalidCredentialsBody,
  type AuthProvider,
  type Logger,
} from '@repo/legalese-agent'
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
  /** jl4-auth-proxy refused the renewal (vs. 5xx / network failures
   *  that outlasted the retries or the key). */
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
  /** Least time between two renewals ({@link MIN_RENEW_INTERVAL_MS}). */
  minRenewIntervalMs?: number
}

const DEFAULT_RETRY_DELAYS_MS = [2_000, 5_000, 10_000, 20_000, 30_000]

/**
 * Least time between two successful renewals: a key that comes back
 * short-lived (or with a bad expiry), or a server that keeps answering
 * 401, can't make the harness delete and mint WorkOS keys in a loop.
 * jl4-auth-proxy issues full 15-minute keys up to the chain's cap, so a
 * healthy chain renews every 10 minutes and never waits on this.
 */
export const MIN_RENEW_INTERVAL_MS = 60_000

/** jl4-auth-proxy deleted the old key, then couldn't mint its successor:
 *  final whatever the status, since a retry would present a dead key. */
const CHAIN_LOST = 'chain_lost'

/**
 * {@link AuthProvider} over an agent key chain (spec §6.2, §15.5).
 *
 * - The key from `AGENT_KEY` is renewed immediately at start, which
 *   deletes it (it was visible in the `RunTask` overrides).
 * - After that it renews when 5 minutes of the 15 are left, and when a
 *   request made with the current key comes back 401, or 403
 *   `invalid-credentials` from ai-proxy ({@link renewAfterUnauthorized}).
 *   Successful renewals are at least {@link MIN_RENEW_INTERVAL_MS}
 *   apart: a 401 sooner than that after one fails the request and
 *   renews once the interval is up.
 * - Any 4xx from renew ends the chain at once. `401 invalid_key`,
 *   `403 chain_expired` and `409 chain_forked` keep their reason; any
 *   other (`403 not_a_member`, `403 forbidden`, `chain_lost`, …) ends it
 *   as `invalid_key`. `chain_lost` (the old key was deleted, the
 *   successor couldn't be minted) is final even with a 5xx status.
 * - 5xx (`502 upstream_unavailable`), 429, network errors and a 200 that
 *   doesn't parse are retried with backoff (`retryDelaysMs`, five tries
 *   over about a minute by default), each only if it starts before the
 *   key expires. When the retries run out, or the key would expire
 *   first, the chain ends as `invalid_key` (not `fromServer`). If
 *   jl4-auth-proxy had already deleted the old key before WorkOS
 *   failed, the retry answers `401 invalid_key` and the chain ends
 *   there.
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
  /** Epoch ms of the last successful renewal. */
  private lastRenewedAt: number | null = null
  private readonly fetchImpl: typeof fetch
  private readonly now: () => number
  private readonly retryDelays: number[]
  private readonly minInterval: number

  constructor(private readonly opts: KeyChainOptions) {
    this.key = opts.initialKey
    // Captured now: main.ts later replaces the global fetch with
    // authRetryingFetch, and a renewal must never go through that (a 401
    // from the renew route would wait on its own renewal).
    this.fetchImpl = opts.fetch ?? globalThis.fetch.bind(globalThis)
    this.now = opts.now ?? Date.now
    this.expiresAt = this.now() + AGENT_KEY_LIFETIME_MS
    this.retryDelays = opts.retryDelaysMs ?? DEFAULT_RETRY_DELAYS_MS
    this.minInterval = opts.minRenewIntervalMs ?? MIN_RENEW_INTERVAL_MS
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
   * A request made with `usedAuthorization` came back 401 (or ai-proxy's
   * 403 `invalid-credentials`, see {@link authRetryingFetch}). Renew unless
   * a renewal already replaced that key; resolves true when a newer key
   * is available to retry with. Within the minimum interval of the last
   * renewal it resolves false and renews as soon as the interval is up,
   * so a key that really was revoked still ends the chain promptly.
   */
  async renewAfterUnauthorized(usedAuthorization: string): Promise<boolean> {
    if (this.ended) return false
    if (!this.isCurrent(usedAuthorization)) {
      if (this.renewing) await this.renewing
      return !this.ended
    }
    if (this.untilRenewAllowed() > 0) {
      this.schedule(true)
      return false
    }
    return this.renew('unauthorized')
  }

  /** `POST /auth/agent-token/end` (best effort) and stop renewing.
   *  Only the first call ends the key; once the chain ended (parked)
   *  there is none to end. */
  async end(): Promise<void> {
    if (this.stopped) return
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

  /** Renew when 5 minutes of the key are left, or (`soon`) as early as
   *  the minimum interval allows. */
  private schedule(soon = false): void {
    this.stopTimer()
    if (this.ended || this.stopped) return
    const earliest = Math.max(this.untilRenewAllowed(), 0)
    const due = soon
      ? earliest
      : Math.max(
          earliest,
          this.expiresAt - AGENT_KEY_RENEW_BEFORE_MS - this.now()
        )
    this.timer = setTimeout(() => {
      this.timer = null
      void this.renew(soon ? 'unauthorized' : 'scheduled').then(() =>
        this.schedule()
      )
    }, due)
    this.timer.unref()
  }

  /** Milliseconds until the minimum interval since the last renewal is
   *  up (≤ 0 when a renewal may run now). */
  private untilRenewAllowed(): number {
    return this.lastRenewedAt === null
      ? 0
      : this.lastRenewedAt + this.minInterval - this.now()
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
      this.lastRenewedAt = this.now()
      return 'ok'
    }
    if ((body as { error?: unknown } | null)?.error === CHAIN_LOST) {
      this.opts.logger.warn(
        `agent key renewal refused: ${res.status} ${CHAIN_LOST}`
      )
      return 'invalid_key'
    }
    if (res.status >= 500 || res.status === 429) {
      // 502 upstream_unavailable, other server errors, and rate limiting
      // (e.g. the firewall in front of legalese.cloud): retry.
      this.opts.logger.warn(`agent key renewal failed: ${res.status}`)
      return 'retry'
    }
    // Any other refusal is final: the chain is over.
    const failure = parseAgentKeyError(body) ?? 'invalid_key'
    this.opts.logger.warn(`agent key renewal refused: ${res.status} ${failure}`)
    return failure
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
 * with the new key (spec §5.4: renew "on 401"). ai-proxy answers a key
 * it no longer accepts with `403` and `Authentication failed:
 * invalid-credentials` instead, so that 403 counts as a 401; any other
 * 403 is a real refusal and is returned as is. Bodies are strings in
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
    if (res.status !== 401 && res.status !== 403) return res
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
    if (res.status === 403 && !(await saysInvalidCredentials(res))) return res
    const renewed = await auth.renewAfterUnauthorized(used)
    if (!renewed) return res
    const fresh = await auth.getAiAuthHeaders()
    if (!fresh.Authorization) return res
    headers.set('authorization', fresh.Authorization)
    await res.body?.cancel().catch(() => undefined)
    return base(input, { ...init, headers })
  }
}

/** Is `res` (a 403) ai-proxy refusing the key itself? Reads a clone, so
 *  `res` can still be returned to the caller unread. */
async function saysInvalidCredentials(res: Response): Promise<boolean> {
  try {
    return isInvalidCredentialsBody(await res.clone().text())
  } catch {
    return false
  }
}
