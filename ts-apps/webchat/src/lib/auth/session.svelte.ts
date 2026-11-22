// Auth is session-token only (no API key). Sign-in goes through the Legalese
// Cloud login with a PKCE challenge (pkce.ts), so it returns with a
// short-lived `?code=` — never the session token — which we exchange for the
// sealed session at POST /auth/exchange. We persist that bearer in
// localStorage and send it as `Authorization: Bearer …` on every request.
// Cross-domain cookies between chat.legalese.cloud and legalese.cloud are
// unreliable, so the bearer header is the only auth signal.

import { completeLogin, startLogin } from './pkce'

export const SERVICE_DOMAIN = 'legalese.cloud'
export const AUTH_API_URL = `https://${SERVICE_DOMAIN}`
// AI service: deployment-scoped chat lives at {AI_API_URL}/{org}/{deployment}/v1/…
export const AI_API_URL = 'https://ai.legalese.cloud'
// Deployment API host: GET {API_BASE}/{org}/{deployment} → { metadata: { description } }
export const API_BASE = 'https://api.legalese.cloud'
// Marketing-site console (org/billing/members management).
export const CONSOLE_URL = 'https://legalese.com/console'

export const SESSION_TOKEN_KEY = 'wos-session-token'

export interface SessionUser {
  id: string
  email: string
  firstName: string | null
  lastName: string | null
  profilePictureUrl: string | null
}

export interface SessionOrganization {
  id: string
  name: string
  slug: string
  createdAt: string
}

export interface ConsoleSession {
  authenticated: true
  user: SessionUser
  organizationId: string | null
  organization?: SessionOrganization
  domainVerified: boolean
  permissions: string[]
}

export type AuthPhase = 'loading' | 'authenticated' | 'unauthenticated'

function readToken(): string | null {
  if (typeof window === 'undefined') return null
  return localStorage.getItem(SESSION_TOKEN_KEY)
}

/** Bearer header for any authenticated fetch (AI service + legalese.cloud). */
export function authHeaders(): Record<string, string> {
  const token = readToken()
  return token ? { Authorization: `Bearer ${token}` } : {}
}

class AuthStore {
  phase = $state<AuthPhase>('loading')
  session = $state<ConsoleSession | null>(null)
  private started = false

  get user(): SessionUser | null {
    return this.session?.user ?? null
  }

  get organization(): SessionOrganization | null {
    return this.session?.organization ?? null
  }

  get orgSlug(): string | null {
    return this.session?.organization?.slug ?? null
  }

  hasPermission(perm: string): boolean {
    return this.session?.permissions?.includes(perm) ?? false
  }

  /** Finish a sign-in from the URL's `?code=`, then validate the session. */
  async init(): Promise<void> {
    if (this.started || typeof window === 'undefined') return
    this.started = true

    const url = new URL(window.location.href)
    const codeFromUrl = url.searchParams.get('code')
    // Sessions are never taken from the URL any more: a stray `?token=` (an
    // old link) is dropped, not used.
    if (codeFromUrl || url.searchParams.has('token')) {
      url.searchParams.delete('code')
      url.searchParams.delete('token')
      window.history.replaceState({}, '', url.pathname + url.search + url.hash)
    }
    let hasUrlToken = false
    if (codeFromUrl) {
      const token = await completeLogin(AUTH_API_URL, codeFromUrl)
      if (token) {
        localStorage.setItem(SESSION_TOKEN_KEY, token)
        hasUrlToken = true
      }
    }

    if (!readToken()) {
      this.phase = 'unauthenticated'
      return
    }

    try {
      const res = await fetch(`${AUTH_API_URL}/auth/session`, {
        credentials: 'include',
        headers: authHeaders(),
      })
      const data = res.ok ? await res.json() : null
      if (data?.authenticated) {
        this.session = data
        this.phase = 'authenticated'
      } else {
        // Server rejected the session. Clear the stale token unless we just
        // completed a sign-in (so a transient error can't wipe a new login).
        if (!hasUrlToken) localStorage.removeItem(SESSION_TOKEN_KEY)
        this.session = null
        this.phase = 'unauthenticated'
      }
    } catch {
      this.phase = 'unauthenticated'
    }
  }

  /** Redirect to the login page, returning to the current URL with a
   *  code afterwards (see init). */
  login(returnTo?: string): void {
    if (typeof window === 'undefined') return
    void startLogin(AUTH_API_URL, returnTo ?? window.location.href)
  }

  logout(): void {
    if (typeof window === 'undefined') return
    localStorage.removeItem(SESSION_TOKEN_KEY)
    window.location.href = `${AUTH_API_URL}/auth/logout`
  }

  /**
   * A 401 on an authenticated request means the bearer no longer speaks for
   * the user (logged out / switched account elsewhere). Drop it and reload so
   * the app re-initialises into the signed-out state.
   */
  private reloadScheduled = false
  handleUnauthorized(): void {
    if (typeof window === 'undefined' || this.reloadScheduled) return
    this.reloadScheduled = true
    localStorage.removeItem(SESSION_TOKEN_KEY)
    window.location.reload()
  }
}

export const auth = new AuthStore()
