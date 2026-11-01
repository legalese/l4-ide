// Cloudflare Turnstile shows the session service that a share comes from a
// person using this page; it rejects POSTs without a valid token. The script
// loads once someone heads for Share (the pointer reaches the button, or it
// gets focus), so editing alone never contacts Cloudflare.

const SCRIPT_URL =
  'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'

interface TurnstileApi {
  render(container: HTMLElement, options: Record<string, unknown>): string
  remove(widgetId: string): void
}

declare global {
  interface Window {
    turnstile?: TurnstileApi
  }
}

let scriptPromise: Promise<TurnstileApi> | undefined

function loadScript(): Promise<TurnstileApi> {
  scriptPromise ??= new Promise<TurnstileApi>((resolve, reject) => {
    const script = document.createElement('script')
    script.src = SCRIPT_URL
    script.async = true
    // Forget a failed load, so the next Share tries again
    const fail = (message: string) => {
      scriptPromise = undefined
      script.remove()
      reject(new Error(message))
    }
    script.onload = () =>
      window.turnstile
        ? resolve(window.turnstile)
        : fail('Turnstile did not initialise')
    script.onerror = () => fail('Could not load Turnstile')
    document.head.appendChild(script)
  })
  return scriptPromise
}

// A token fetched ahead of the click, so Share doesn't wait for the challenge.
// Tokens are single-use and Cloudflare accepts them for 300 s.
const TOKEN_MAX_AGE_MS = 240_000
let warmToken: { promise: Promise<string>; requestedAt: number } | undefined

/** Starts fetching the token the next share will use. */
export function warmUpTurnstileToken(siteKey: string): void {
  if (warmToken && Date.now() - warmToken.requestedAt < TOKEN_MAX_AGE_MS) {
    return
  }
  const promise = fetchToken(siteKey)
  promise.catch(() => {
    if (warmToken?.promise === promise) warmToken = undefined
  })
  warmToken = { promise, requestedAt: Date.now() }
}

/** A single-use token for one share: the warmed-up one if still fresh. */
export async function getTurnstileToken(siteKey: string): Promise<string> {
  const warm = warmToken
  warmToken = undefined
  if (warm && Date.now() - warm.requestedAt < TOKEN_MAX_AGE_MS) {
    try {
      return await warm.promise
    } catch {
      // Fetch a fresh one below
    }
  }
  return fetchToken(siteKey)
}

/**
 * The widget stays invisible unless Cloudflare wants an interaction, in which
 * case it shows bottom-right.
 */
async function fetchToken(siteKey: string): Promise<string> {
  const turnstile = await loadScript()
  const container = document.createElement('div')
  container.style.cssText =
    'position: fixed; right: 1rem; bottom: 1rem; z-index: 10000;'
  document.body.appendChild(container)

  let widgetId: string | undefined
  try {
    return await new Promise<string>((resolve, reject) => {
      widgetId = turnstile.render(container, {
        sitekey: siteKey,
        action: 'share',
        appearance: 'interaction-only',
        callback: (token: string) => resolve(token),
        'error-callback': () => reject(new Error('Turnstile check failed')),
        'timeout-callback': () =>
          reject(new Error('Turnstile check timed out')),
      })
    })
  } finally {
    if (widgetId !== undefined) turnstile.remove(widgetId)
    container.remove()
  }
}
