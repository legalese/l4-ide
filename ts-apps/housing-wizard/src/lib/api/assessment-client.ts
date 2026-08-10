import { schemaUrl, evalUrl, SERVICE_BASE_URL } from '$lib/config'
import type {
  ExportedFunctionInfo,
  PossessionAssessment,
  FormState,
} from './types'

/** fetch threw / offline / CORS / network / timeout. */
export class NetworkError extends Error {}
/** Got a body, but it was an Error envelope or a shape we cannot read. */
export class ServiceError extends Error {}

// A stalled connection (accepted-but-never-answered) would otherwise leave the
// loading spinner hanging forever with no recovery — the most likely way a live
// demo silently dies on flaky venue Wi-Fi. Cap both requests so the abort surfaces
// as a NetworkError and the existing retry UI fires.
const REQUEST_TIMEOUT_MS = 8000

function isRecord(x: unknown): x is Record<string, unknown> {
  return typeof x === 'object' && x !== null
}

export async function fetchSchema(): Promise<ExportedFunctionInfo> {
  let res: Response
  try {
    res = await fetch(schemaUrl(), {
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    })
  } catch {
    throw new NetworkError(
      `Could not reach the rules service at ${SERVICE_BASE_URL}`
    )
  }
  if (!res.ok) {
    throw new ServiceError(`Could not load the questions (HTTP ${res.status}).`)
  }
  return (await res.json()) as ExportedFunctionInfo
}

export async function evaluate(
  args: { situation: FormState },
  returnType: string
): Promise<PossessionAssessment> {
  let res: Response
  try {
    res = await fetch(evalUrl(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ arguments: args }),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    })
  } catch {
    throw new NetworkError(
      `Could not reach the rules service at ${SERVICE_BASE_URL}`
    )
  }

  // Parse the body UNCONDITIONALLY (never gate on res.ok): an eval failure is
  // delivered as a tag:'Error' envelope with a non-2xx status, and its message
  // is the most useful thing to show.
  let raw: unknown
  try {
    raw = await res.json()
  } catch {
    throw new ServiceError(
      'The rules service sent a response we could not read.'
    )
  }

  if (!isRecord(raw) || typeof raw.tag !== 'string') {
    throw new ServiceError('Could not read the result.')
  }

  if (raw.tag === 'Error') {
    const contents = isRecord(raw.contents) ? raw.contents : undefined
    const msg =
      contents && typeof contents.contents === 'string'
        ? contents.contents
        : 'The rules service reported an error.'
    throw new ServiceError(msg)
  }

  if (raw.tag !== 'SimpleResponse') {
    throw new ServiceError('Could not read the result.')
  }

  const contents = isRecord(raw.contents) ? raw.contents : undefined
  const result =
    contents && isRecord(contents.result) ? contents.result : undefined
  const value = result && isRecord(result.value) ? result.value : undefined
  if (!value) {
    throw new ServiceError('Could not read the result.')
  }

  return unwrapResult(value, returnType)
}

/**
 * The success value is wrapped under the return-type NAME
 * ({ PossessionAssessment: {...} }). Prefer value[returnType] (read from the
 * schema, never hardcoded); else peel a single-key wrapper (resilient to a
 * renamed return type, matching the reference render-l4-value behaviour). Then
 * VALIDATE the shape — a redeployed/edited schema (exactly the drafter-authored
 * workflow this demo showcases) could drop or rename a key; without this, a
 * missing `possession can be ordered` would coerce to a FALSE "all clear", and a
 * missing array would throw an uncaught TypeError at render. Validation routes
 * any drift to the graceful evalError view instead.
 */
function unwrapResult(
  wrapper: Record<string, unknown>,
  returnType: string
): PossessionAssessment {
  const keys = Object.keys(wrapper)
  const candidate =
    returnType in wrapper
      ? wrapper[returnType]
      : keys.length === 1
        ? wrapper[keys[0]]
        : undefined
  if (!isRecord(candidate)) {
    throw new ServiceError('Could not read the result.')
  }
  return validateAssessment(candidate)
}

function isStringArray(x: unknown): x is string[] {
  return Array.isArray(x) && x.every((e) => typeof e === 'string')
}

function validateAssessment(v: Record<string, unknown>): PossessionAssessment {
  const ok =
    typeof v['possession can be ordered'] === 'boolean' &&
    typeof v['it is mandatory'] === 'boolean' &&
    isStringArray(v['grounds made out']) &&
    isStringArray(v['reasons']) &&
    typeof v['what this means'] === 'string'
  if (!ok) {
    throw new ServiceError('The result was in an unexpected format.')
  }
  return v as unknown as PossessionAssessment
}
