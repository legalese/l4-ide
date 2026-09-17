// The single jl4-service coupling point. The CSP connect-src in
// svelte.config.js must include the SAME origin as SERVICE_BASE_URL, or the
// browser blocks the fetch with only a console error.

// Default: the rules service on port 18099 of WHATEVER host served this page,
// so a phone that reached the demo as http://nye.local:5175/ talks to
// http://nye.local:18099 without a rebuild. VITE_JL4_BASE_URL still wins.
// (Server-side code — the interview route — has no `location`; it uses the
// loopback, which is where jl4-service runs beside it.)
const sameHostService = (): string =>
  typeof location !== 'undefined' && location.hostname
    ? `${location.protocol === 'https:' ? 'https' : 'http'}://${location.hostname}:18099`
    : 'http://127.0.0.1:18099'

export const SERVICE_BASE_URL =
  import.meta.env.VITE_JL4_BASE_URL ?? sameHostService()
export const DEPLOYMENT_ID =
  import.meta.env.VITE_JL4_DEPLOYMENT ?? 'sg-penal-code'

function fnBase(fn: string): string {
  return `${SERVICE_BASE_URL}/deployments/${DEPLOYMENT_ID}/functions/${encodeURIComponent(fn)}`
}

export const schemaUrl = (fn: string): string => fnBase(fn)
export const evalUrl = (fn: string): string => `${fnBase(fn)}/evaluation`
export const queryPlanUrl = (fn: string): string => `${fnBase(fn)}/query-plan`
export const ladderUrl = (fn: string): string => `${fnBase(fn)}/ladder`
