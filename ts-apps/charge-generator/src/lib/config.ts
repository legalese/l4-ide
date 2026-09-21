// The single jl4-service coupling point. The CSP connect-src in
// svelte.config.js must include the SAME origin as SERVICE_BASE_URL, or the
// browser blocks the fetch with only a console error.

// Default: the app's own `/service` proxy route (src/routes/service/[...path]),
// so the page works through any single hostname — LAN, a tunnel, a reverse
// proxy — under CSP connect-src 'self'. VITE_JL4_BASE_URL still wins when the
// browser should talk to a service directly (the regcf-wizard arrangement).
// Server-side code has no `location`; it never reads this at request time.
const sameOriginService = (): string =>
  typeof location !== 'undefined' && location.origin
    ? `${location.origin}/service`
    : 'http://127.0.0.1:18099'

export const SERVICE_BASE_URL =
  import.meta.env.VITE_JL4_BASE_URL ?? sameOriginService()
export const DEPLOYMENT_ID =
  import.meta.env.VITE_JL4_DEPLOYMENT ?? 'sg-penal-code'

function fnBase(fn: string): string {
  return `${SERVICE_BASE_URL}/deployments/${DEPLOYMENT_ID}/functions/${encodeURIComponent(fn)}`
}

export const schemaUrl = (fn: string): string => fnBase(fn)
export const evalUrl = (fn: string): string => `${fnBase(fn)}/evaluation`
export const queryPlanUrl = (fn: string): string => `${fnBase(fn)}/query-plan`
export const ladderUrl = (fn: string): string => `${fnBase(fn)}/ladder`
