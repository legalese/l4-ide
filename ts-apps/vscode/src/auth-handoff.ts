/**
 * Legalese Cloud login hand-off.
 *
 * The extension opens the Legalese console with its callback and a PKCE
 * challenge. The console shows who is signing in, and to which org (with
 * Switch account), and on Continue starts the extension's own sign-in; the
 * server then returns a short-lived code instead of the session token, which
 * the extension exchanges with its verifier at `POST /auth/exchange`. The
 * token never travels in a URL (browser history, the console page, the
 * `vscode://` link), a code is useless to anyone without this login's
 * verifier, and the editor's session is its own (signing out of the console
 * doesn't sign it out).
 *
 * A server without hand-off support ignores the challenge and
 * answers with the legacy `?token=` callback, which is still accepted.
 *
 * Lives in its own zero-dependency module so `node --test` can exercise it
 * without dragging the vscode runtime through the import graph.
 */
import { createHash, randomBytes } from 'node:crypto'

/** A login started on this machine, waiting for its callback. */
export interface PendingLogin {
  verifier: string
  createdAt: number
}

/** How long a started login may take before its callback is refused. */
export const PENDING_LOGIN_TTL_MS = 15 * 60 * 1000

export function challengeFor(verifier: string): string {
  return createHash('sha256').update(verifier).digest('base64url')
}

export function createPendingLogin(now = Date.now()): {
  pending: PendingLogin
  challenge: string
} {
  const verifier = randomBytes(32).toString('base64url')
  return {
    pending: { verifier, createdAt: now },
    challenge: challengeFor(verifier),
  }
}

/** The console page that confirms the account and org, then signs the
 *  editor in (`redirect_to` + challenge). */
export function buildLoginUrl(
  consoleUrl: string,
  callbackUri: string,
  challenge: string
): string {
  const params = new URLSearchParams({
    redirect_to: callbackUri,
    code_challenge: challenge,
    code_challenge_method: 'S256',
  })
  return `${consoleUrl}?${params.toString()}`
}

export type AuthCallback =
  | { kind: 'code'; code: string }
  | { kind: 'token'; token: string }
  | { kind: 'none' }

/** Read the auth-callback query. A hand-off code wins over a legacy token. */
export function parseAuthCallback(query: string): AuthCallback {
  const params = new URLSearchParams(query)
  const code = params.get('code')
  if (code) return { kind: 'code', code }
  const token = params.get('token')
  if (token) return { kind: 'token', token }
  return { kind: 'none' }
}

export function parsePendingLogin(
  raw: string | undefined
): PendingLogin | undefined {
  if (!raw) return undefined
  try {
    const p = JSON.parse(raw) as PendingLogin
    return typeof p.verifier === 'string' && typeof p.createdAt === 'number'
      ? p
      : undefined
  } catch {
    return undefined
  }
}

export function isPendingLoginFresh(
  pending: PendingLogin | undefined,
  now = Date.now()
): pending is PendingLogin {
  return (
    !!pending &&
    now >= pending.createdAt &&
    now - pending.createdAt < PENDING_LOGIN_TTL_MS
  )
}

type FetchLike = (
  input: string,
  init: {
    method: string
    headers: Record<string, string>
    body: string
    signal?: AbortSignal
  }
) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>

/** Exchange a hand-off code and this login's verifier for the session token. */
export async function exchangeHandoffCode(
  fetchFn: FetchLike,
  domain: string,
  code: string,
  verifier: string
): Promise<string> {
  const resp = await fetchFn(`https://${domain}/auth/exchange`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code, code_verifier: verifier }),
    signal: AbortSignal.timeout(10000),
  })
  if (!resp.ok) {
    throw new Error(`exchange failed with HTTP ${resp.status}`)
  }
  const body = (await resp.json()) as { token?: unknown }
  if (typeof body.token !== 'string' || !body.token) {
    throw new Error('exchange response had no token')
  }
  return body.token
}
