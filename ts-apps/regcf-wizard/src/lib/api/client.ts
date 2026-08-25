import {
  schemaUrl,
  evalUrl,
  queryPlanUrl,
  ladderUrl,
  SERVICE_BASE_URL,
} from '$lib/config'
import type {
  ExportedFunctionInfo,
  FormState,
  QueryPlanResponse,
  PlanAtom,
  Verdict,
} from './types'

/** fetch threw / offline / CORS / network / timeout. */
export class NetworkError extends Error {}
/** Got a body, but it was an Error envelope or a shape we cannot read. */
export class ServiceError extends Error {}

// A stalled connection (accepted-but-never-answered) would otherwise leave the
// loading spinner hanging forever with no recovery. Cap every request so the
// abort surfaces as a NetworkError and the retry UI fires.
const REQUEST_TIMEOUT_MS = 8000

function isRecord(x: unknown): x is Record<string, unknown> {
  return typeof x === 'object' && x !== null
}

async function getJson(url: string, what: string): Promise<unknown> {
  let res: Response
  try {
    res = await fetch(url, { signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) })
  } catch {
    throw new NetworkError(
      `Could not reach the rules service at ${SERVICE_BASE_URL}`
    )
  }
  if (!res.ok)
    throw new ServiceError(`Could not load ${what} (HTTP ${res.status}).`)
  try {
    return await res.json()
  } catch {
    throw new ServiceError(
      'The rules service sent a response we could not read.'
    )
  }
}

async function postJson(url: string, body: unknown): Promise<unknown> {
  let res: Response
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
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
  try {
    return await res.json()
  } catch {
    throw new ServiceError(
      'The rules service sent a response we could not read.'
    )
  }
}

export async function fetchSchema(fn: string): Promise<ExportedFunctionInfo> {
  return (await getJson(schemaUrl(fn), 'the questions')) as ExportedFunctionInfo
}

/**
 * Evaluate an export and hand back the RAW return value — unwrapped from the
 * envelope but not yet shape-checked. Callers pass it to the matching validator
 * in `validate.ts`.
 *
 * Two unwrapping rules, both measured against the live service:
 *  - a RECORD return arrives wrapped under its return-type NAME
 *    (`{"value":{"RaiseAssessment":{…}}}`);
 *  - a SCALAR return does NOT (`{"value":7500}` for the NUMBER export).
 * Prefer `value[returnType]` (read from the schema, never hardcoded); else peel
 * a single-key wrapper; else take the value as-is.
 */
export async function evaluate(
  fn: string,
  args: FormState,
  returnType: string
): Promise<unknown> {
  const raw = await postJson(evalUrl(fn), { arguments: args })

  if (!isRecord(raw) || typeof raw.tag !== 'string')
    throw new ServiceError('Could not read the result.')

  if (raw.tag === 'Error') {
    const contents = isRecord(raw.contents) ? raw.contents : undefined
    const msg =
      contents && typeof contents.contents === 'string'
        ? contents.contents
        : 'The rules service reported an error.'
    throw new ServiceError(msg)
  }
  if (raw.tag !== 'SimpleResponse')
    throw new ServiceError('Could not read the result.')

  const contents = isRecord(raw.contents) ? raw.contents : undefined
  const result =
    contents && isRecord(contents.result) ? contents.result : undefined
  if (!result || !('value' in result))
    throw new ServiceError('Could not read the result.')

  const value = result.value
  if (!isRecord(value)) return value // scalar return (NUMBER, BOOLEAN, STRING)
  if (returnType in value) return value[returnType]
  const keys = Object.keys(value)
  return keys.length === 1 ? value[keys[0]] : value
}

/**
 * Run one turn of the elicitation loop.
 *
 * `bindings` are keyed by the atom's `unique` rendered as a DECIMAL STRING —
 * one of the three forms `Backend/DecisionQueryPlan.hs` accepts, and the only
 * one this client uses. Measured, and the reason is a real trap:
 *
 *   - binding by an atom's query-plan `atomId` works;
 *   - binding by the atomId carried in the LADDER payload silently NO-OPS,
 *     because the two are different UUIDv5s for the same atom (for
 *     `can this company raise` limb 1: ranked says
 *     `a87d9b26-bfef-5b0b-9c22-d77d103f93a9`, the ladder says
 *     `64e895d0-1863-5f26-bb2b-63ef440b85d3`);
 *   - `unique` agrees across both payloads (4 and 6 here).
 *
 * So `unique` is the join key between the ladder picture and the plan, and it
 * is the binding key. A client that joined on atomId would draw one diagram and
 * answer a different question.
 */
export async function queryPlan(
  fn: string,
  bindings: Record<string, boolean>
): Promise<QueryPlanResponse> {
  const raw = await postJson(queryPlanUrl(fn), { arguments: bindings })
  if (!isRecord(raw)) throw new ServiceError('Could not read the query plan.')
  if (raw.tag === 'Error') {
    const contents = isRecord(raw.contents) ? raw.contents : undefined
    throw new ServiceError(
      contents && typeof contents.contents === 'string'
        ? contents.contents
        : 'The rules service reported an error.'
    )
  }
  const verdict = raw.verdict
  if (typeof verdict !== 'string')
    throw new ServiceError('Could not read the query plan.')
  return {
    verdict: verdict as Verdict,
    determined: typeof raw.determined === 'boolean' ? raw.determined : null,
    ranked: asAtoms(raw.ranked),
    stillNeeded: asAtoms(raw.stillNeeded),
    ladder: raw.ladder,
    note: typeof raw.note === 'string' ? raw.note : undefined,
  }
}

function asAtoms(x: unknown): PlanAtom[] {
  if (!Array.isArray(x)) return []
  return x.flatMap((e): PlanAtom[] => {
    if (!isRecord(e)) return []
    const { atomId, label, unique } = e
    if (
      typeof atomId !== 'string' ||
      typeof label !== 'string' ||
      typeof unique !== 'number'
    )
      return []
    return [
      {
        atomId,
        label,
        unique,
        inputRefs: Array.isArray(e.inputRefs)
          ? e.inputRefs.filter((r): r is string => typeof r === 'string')
          : [],
      },
    ]
  })
}

/**
 * `GET …/{fn}/ladder` → `RenderAsLadderInfo`, i.e. `{funDecl, verDocId}`.
 *
 * Answers 200 only for an export that returns a BOOLEAN; the other five Reg CF
 * exports answer 400 with "Can only visualize, as a ladder diagram, a DECIDE
 * that returns a boolean." Callers treat a failure as "no picture", never as an
 * error worth showing.
 *
 * The `value` on each leaf is ALWAYS `UnknownV` here and stays `UnknownV` even
 * when the query-plan call carries bindings — the picture is static data and
 * the valuation is the client's (EMBEDDABLE.md EK5). We return only `funDecl`
 * to make that impossible to forget.
 */
export async function fetchLadder(fn: string): Promise<unknown> {
  const raw = await getJson(ladderUrl(fn), 'the diagram')
  if (!isRecord(raw) || !isRecord(raw.funDecl))
    throw new ServiceError('Could not read the diagram.')
  return raw.funDecl
}
