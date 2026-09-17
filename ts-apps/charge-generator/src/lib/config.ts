// The single jl4-service coupling point. The CSP connect-src in
// svelte.config.js must include the SAME origin as SERVICE_BASE_URL, or the
// browser blocks the fetch with only a console error.

export const SERVICE_BASE_URL =
  import.meta.env.VITE_JL4_BASE_URL ?? 'http://127.0.0.1:18099'
export const DEPLOYMENT_ID =
  import.meta.env.VITE_JL4_DEPLOYMENT ?? 'sg-penal-code'

function fnBase(fn: string): string {
  return `${SERVICE_BASE_URL}/deployments/${DEPLOYMENT_ID}/functions/${encodeURIComponent(fn)}`
}

export const schemaUrl = (fn: string): string => fnBase(fn)
export const evalUrl = (fn: string): string => `${fnBase(fn)}/evaluation`
export const queryPlanUrl = (fn: string): string => `${fnBase(fn)}/query-plan`
export const ladderUrl = (fn: string): string => `${fnBase(fn)}/ladder`
