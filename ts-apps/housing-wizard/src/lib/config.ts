// The single L4 / jl4-service coupling point.
//
// NOTE: the CSP connect-src in svelte.config.js must include the SAME origin as
// SERVICE_BASE_URL, or the browser blocks the fetch (a <meta>-tag CSP rejects a
// cross-origin fetch with only a console error — the spinner hangs). For a prod
// demo, set BOTH VITE_JL4_BASE_URL and the connect-src entry to the prod origin.
export const SERVICE_BASE_URL =
  import.meta.env.VITE_JL4_BASE_URL ?? 'http://localhost:8080'
export const DEPLOYMENT_ID =
  import.meta.env.VITE_JL4_DEPLOYMENT ?? 'housing-wizard'
export const FUNCTION_NAME =
  import.meta.env.VITE_JL4_FUNCTION ?? 'assess possession for rent arrears'

function fnBase(): string {
  return `${SERVICE_BASE_URL}/deployments/${DEPLOYMENT_ID}/functions/${encodeURIComponent(FUNCTION_NAME)}`
}

export const schemaUrl = (): string => fnBase()
export const evalUrl = (): string => `${fnBase()}/evaluation`
