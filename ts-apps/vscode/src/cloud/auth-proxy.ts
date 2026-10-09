/**
 * jl4-auth-proxy calls a cloud session needs from the extension
 * (spec §6.1, §6.2, §15.5):
 *
 * - `GET /auth/access-token` — the short-lived WorkOS JWT the Sessions
 *   API and git accept. Cached until shortly before it expires; a
 *   rotated sealed session in the response (`token`) is stored in place
 *   of the old one.
 * - `POST /auth/agent-token { purpose: "cloud-session", sessionId }` —
 *   the first key of a session's key chain, handed to `/start`.
 *
 * Both authenticate with the sealed session (Legalese Cloud sign-in).
 * No `vscode` import: the extension passes the storage callbacks.
 */
import {
  AGENT_KEY_PURPOSE,
  ProtocolError,
  accessTokenResponse,
  mintAgentKeyResponse,
  type MintAgentKeyResponse,
} from '@repo/legalese-agent/protocol'

export type FetchFn = typeof fetch

/** The user isn't signed in to Legalese Cloud (no sealed session, or
 *  jl4-auth-proxy rejected it). */
export class NotSignedInError extends Error {
  constructor(message = 'Sign in to Legalese Cloud to use cloud sessions.') {
    super(message)
    this.name = 'NotSignedInError'
  }
}

/** A jl4-auth-proxy call failed with an HTTP error or a bad body. */
export class AuthProxyError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code?: string
  ) {
    super(message)
    this.name = 'AuthProxyError'
  }
}

export interface AuthProxyDeps {
  /** e.g. `https://legalese.cloud` */
  authBaseUrl: () => string
  /** The stored sealed session, if any. */
  getSessionToken: () => Promise<string | undefined>
  /** Store a rotated sealed session. */
  storeSessionToken: (token: string) => Promise<void>
  fetch?: FetchFn
  now?: () => number
}

/** Refresh when less than this much lifetime is left. */
export const ACCESS_TOKEN_REFRESH_MARGIN_MS = 60_000

const REQUEST_TIMEOUT_MS = 15_000

async function errorCode(res: Response): Promise<string | undefined> {
  try {
    const body = (await res.json()) as { error?: unknown }
    return typeof body?.error === 'string' ? body.error : undefined
  } catch {
    return undefined
  }
}

/**
 * Hands out the WorkOS access token for the Sessions API. Concurrent
 * callers share one refresh.
 */
export class AccessTokenManager {
  private cached: { token: string; expiresAt: number } | undefined
  private inflight: Promise<string> | undefined
  private readonly fetchFn: FetchFn
  private readonly now: () => number

  constructor(private readonly deps: AuthProxyDeps) {
    this.fetchFn = deps.fetch ?? fetch
    this.now = deps.now ?? Date.now
  }

  /** A token valid for at least a minute more. `force` skips the
   *  cache (after the Sessions API answered 401). */
  async get(opts: { force?: boolean } = {}): Promise<string> {
    if (
      !opts.force &&
      this.cached &&
      this.cached.expiresAt - this.now() > ACCESS_TOKEN_REFRESH_MARGIN_MS
    ) {
      return this.cached.token
    }
    if (opts.force) this.cached = undefined
    this.inflight ??= this.refresh().finally(() => {
      this.inflight = undefined
    })
    return this.inflight
  }

  /** Forget the cached token (sign-out, account switch). */
  invalidate(): void {
    this.cached = undefined
  }

  private async refresh(): Promise<string> {
    const session = await this.deps.getSessionToken()
    if (!session) throw new NotSignedInError()
    const base = this.deps.authBaseUrl().replace(/\/$/, '')
    const res = await this.fetchFn(`${base}/auth/access-token`, {
      headers: { Authorization: `Bearer ${session}` },
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    })
    if (res.status === 401) {
      throw new NotSignedInError(
        'Your Legalese Cloud session has expired. Sign in again to use cloud sessions.'
      )
    }
    if (!res.ok) {
      throw new AuthProxyError(
        `Could not get an access token (HTTP ${res.status}).`,
        res.status,
        await errorCode(res)
      )
    }
    let body
    try {
      body = accessTokenResponse(await res.json(), 'accessToken')
    } catch (err) {
      if (err instanceof ProtocolError || err instanceof SyntaxError) {
        throw new AuthProxyError('Malformed access-token response.', res.status)
      }
      throw err
    }
    if (body.token && body.token !== session) {
      // jl4-auth-proxy refreshed the WorkOS session: keep the rotation,
      // or the next refresh would present a spent refresh token.
      await this.deps.storeSessionToken(body.token)
    }
    this.cached = { token: body.accessToken, expiresAt: body.expiresAt }
    return body.accessToken
  }
}

/** Mint the first key of a session's key chain (§6.2). */
export async function mintAgentKey(
  deps: AuthProxyDeps,
  sessionId: string
): Promise<MintAgentKeyResponse> {
  const session = await deps.getSessionToken()
  if (!session) throw new NotSignedInError()
  const base = deps.authBaseUrl().replace(/\/$/, '')
  const res = await (deps.fetch ?? fetch)(`${base}/auth/agent-token`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${session}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ purpose: AGENT_KEY_PURPOSE, sessionId }),
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  })
  if (res.status === 401) throw new NotSignedInError()
  if (!res.ok) {
    const code = await errorCode(res)
    throw new AuthProxyError(
      res.status === 403
        ? 'Your account is not allowed to run cloud sessions.'
        : `Could not authorise the cloud session (HTTP ${res.status}${code ? `, ${code}` : ''}).`,
      res.status,
      code
    )
  }
  try {
    return mintAgentKeyResponse(await res.json(), 'agentKey')
  } catch (err) {
    if (err instanceof ProtocolError || err instanceof SyntaxError) {
      throw new AuthProxyError('Malformed agent-token response.', res.status)
    }
    throw err
  }
}
