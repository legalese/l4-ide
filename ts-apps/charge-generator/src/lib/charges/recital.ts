import { evaluate, fetchLadder, fetchSchema } from '$lib/api/client'
import { asCharge } from '$lib/api/validate'
import type { ExportedFunctionInfo } from '$lib/api/types'
import type { ProposedCharge } from '$lib/case/casefile.svelte'
import { fillDefaults, factsSchema } from './schema-fill'

/**
 * The recital round trip. L4 owns the sentence (decision 4 in the plan); the
 * client's job is to send the facts and show what comes back. Every click on a
 * ladder leaf schedules one evaluation, debounced so a run of clicks costs one
 * request, and a stale response never overwrites a fresher one.
 */
const DEBOUNCE_MS = 250

const schemaCache = new Map<string, Promise<ExportedFunctionInfo>>()
const ladderCache = new Map<string, Promise<unknown>>()

export function schemaOf(fn: string): Promise<ExportedFunctionInfo> {
  let p = schemaCache.get(fn)
  if (!p) {
    p = fetchSchema(fn)
    schemaCache.set(fn, p)
  }
  return p
}

export function ladderOf(fn: string): Promise<unknown> {
  let p = ladderCache.get(fn)
  if (!p) {
    p = fetchLadder(fn)
    ladderCache.set(fn, p)
  }
  return p
}

const timers = new Map<string, ReturnType<typeof setTimeout>>()
const seq = new Map<string, number>()

/** Complete the partial facts against the export's schema, ready for the wire. */
export async function wireFacts(
  pc: ProposedCharge
): Promise<Record<string, unknown>> {
  const info = await schemaOf(pc.offence.chargeFn)
  const schema = factsSchema(info.parameters, pc.offence.factsParam)
  return fillDefaults(schema, pc.facts) as Record<string, unknown>
}

export function scheduleRecital(pc: ProposedCharge): void {
  const t = timers.get(pc.id)
  if (t) clearTimeout(t)
  pc.pending = true
  timers.set(
    pc.id,
    setTimeout(() => void runRecital(pc), DEBOUNCE_MS)
  )
}

export async function runRecital(pc: ProposedCharge): Promise<void> {
  const mine = (seq.get(pc.id) ?? 0) + 1
  seq.set(pc.id, mine)
  pc.pending = true
  try {
    const facts = await wireFacts(pc)
    const raw = await evaluate(
      pc.offence.chargeFn,
      { [pc.offence.factsParam]: facts },
      'Charge'
    )
    if (seq.get(pc.id) !== mine) return // a later click superseded this one
    pc.charge = asCharge(raw)
    pc.error = null
  } catch (e) {
    if (seq.get(pc.id) !== mine) return
    pc.error = e instanceof Error ? e.message : String(e)
  } finally {
    if (seq.get(pc.id) === mine) pc.pending = false
  }
}
