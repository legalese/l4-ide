// Sign-in without the session token in a URL.
//
// The login starts with a PKCE challenge (/auth/login?code_challenge=…), so
// the server returns a short-lived code (?code=h1.…) instead of the session
// token. The app exchanges code + verifier at POST /auth/exchange. The
// verifier stays in this tab's sessionStorage, so a code that leaks through
// history or a screenshot is useless.

const VERIFIER_KEY = 'legalese-login-verifier'
const VERIFIER_TTL_MS = 15 * 60 * 1000

function base64url(bytes: Uint8Array): string {
  let s = ''
  bytes.forEach((b) => (s += String.fromCharCode(b)))
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

async function s256(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(verifier)
  )
  return base64url(new Uint8Array(digest))
}

/** Start a sign-in at `authApiUrl` that returns to `returnTo` with a code. */
export async function startLogin(
  authApiUrl: string,
  returnTo: string
): Promise<void> {
  const bytes = new Uint8Array(32)
  crypto.getRandomValues(bytes)
  const verifier = base64url(bytes)
  sessionStorage.setItem(
    VERIFIER_KEY,
    JSON.stringify({ verifier, createdAt: Date.now() })
  )
  const params = new URLSearchParams({
    return_to: returnTo,
    code_challenge: await s256(verifier),
    code_challenge_method: 'S256',
  })
  window.location.href = `${authApiUrl}/auth/login?${params.toString()}`
}

/**
 * Exchange the code from the URL for the session token. Returns null when
 * this tab has no pending sign-in or the exchange is refused.
 */
export async function completeLogin(
  authApiUrl: string,
  code: string
): Promise<string | null> {
  const raw = sessionStorage.getItem(VERIFIER_KEY)
  sessionStorage.removeItem(VERIFIER_KEY)
  let pending: { verifier?: unknown; createdAt?: unknown } = {}
  try {
    pending = raw ? JSON.parse(raw) : {}
  } catch {
    return null
  }
  if (
    typeof pending.verifier !== 'string' ||
    typeof pending.createdAt !== 'number' ||
    Date.now() - pending.createdAt > VERIFIER_TTL_MS
  ) {
    return null
  }
  try {
    const res = await fetch(`${authApiUrl}/auth/exchange`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code, code_verifier: pending.verifier }),
    })
    if (!res.ok) return null
    const body = (await res.json()) as { token?: unknown }
    return typeof body.token === 'string' ? body.token : null
  } catch {
    return null
  }
}
