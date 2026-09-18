/**
 * Server-side access to jl4-service — the same routes the browser uses, called
 * from the interview route so the model's tools can evaluate facts without the
 * browser in the loop. Reuses the browser client's unwrapping rules.
 */
import { evalUrl, ladderUrl, schemaUrl } from '$lib/config'
import { asCharge } from '$lib/api/validate'
import type {
  Charge,
  ExportedFunctionInfo,
  FunctionParameter,
} from '$lib/api/types'
import { fromVizFunDecl } from '@repo/ladder-core'
import { elementPaths } from '$lib/charges/valuation'
import {
  factsSchema,
  fillDefaults,
  stringFields,
} from '$lib/charges/schema-fill'
import type { Offence } from '$lib/catalogue'

const schemaCache = new Map<string, Promise<ExportedFunctionInfo>>()
const ladderCache = new Map<string, Promise<unknown>>()

export function schemaOf(fn: string): Promise<ExportedFunctionInfo> {
  let p = schemaCache.get(fn)
  if (!p) {
    p = fetch(schemaUrl(fn)).then(async (r) => {
      if (!r.ok) throw new Error(`schema ${fn}: HTTP ${r.status}`)
      return (await r.json()) as ExportedFunctionInfo
    })
    schemaCache.set(fn, p)
  }
  return p
}

export function ladderOf(fn: string): Promise<unknown> {
  let p = ladderCache.get(fn)
  if (!p) {
    p = fetch(ladderUrl(fn)).then(async (r) => {
      if (!r.ok) throw new Error(`ladder ${fn}: HTTP ${r.status}`)
      const raw = (await r.json()) as { funDecl: unknown }
      return raw.funDecl
    })
    ladderCache.set(fn, p)
  }
  return p
}

export interface FieldInfo {
  readonly path: string
  readonly type: 'boolean' | 'string' | 'enum' | 'other'
  readonly enum?: readonly string[]
  readonly description: string
}

/** Every field of an offence's facts record, flattened, with its question. */
export async function fieldsOf(o: Offence): Promise<FieldInfo[]> {
  const info = await schemaOf(o.chargeFn)
  const schema = factsSchema(info.parameters, o.factsParam)
  const out: FieldInfo[] = []
  const walk = (s: FunctionParameter | undefined, prefix: string[]): void => {
    if (!s) return
    if (s.properties) {
      const order = s.propertyOrder ?? Object.keys(s.properties)
      for (const k of order) walk(s.properties[k], [...prefix, k])
      return
    }
    out.push({
      path: prefix.join('/'),
      type:
        s.enum && s.enum.length > 0
          ? 'enum'
          : s.type === 'boolean'
            ? 'boolean'
            : s.type === 'string'
              ? 'string'
              : 'other',
      enum: s.enum && s.enum.length > 0 ? s.enum : undefined,
      description: s.description ?? '',
    })
  }
  walk(schema, [])
  return out
}

/** The elements (ladder leaves) of the offence and its defining rules. */
export async function elementsOf(o: Offence): Promise<string[]> {
  type Viz = Parameters<typeof fromVizFunDecl>[0]
  const decls = await Promise.all(
    [o.offenceFn, ...o.definitionFns].map((f) => ladderOf(f))
  )
  const seen = new Set<string>()
  for (const raw of decls) {
    const { fn } = fromVizFunDecl(raw as Viz)
    for (const p of elementPaths(fn, o.factsParam)) seen.add(p.join('/'))
  }
  return [...seen]
}

export async function completeFacts(
  o: Offence,
  facts: Record<string, unknown>
): Promise<Record<string, unknown>> {
  const info = await schemaOf(o.chargeFn)
  const schema = factsSchema(info.parameters, o.factsParam)
  return fillDefaults(schema, facts) as Record<string, unknown>
}

export async function evaluateCharge(
  o: Offence,
  facts: Record<string, unknown>
): Promise<Charge> {
  const full = await completeFacts(o, facts)
  const r = await fetch(evalUrl(o.chargeFn), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ arguments: { [o.factsParam]: full } }),
  })
  const raw = (await r.json()) as {
    tag?: string
    contents?: {
      result?: { value?: Record<string, unknown> }
      contents?: string
    }
  }
  if (raw.tag === 'Error')
    throw new Error(
      raw.contents?.contents ?? 'the rules service reported an error'
    )
  const value = raw.contents?.result?.value
  if (!value) throw new Error('could not read the evaluation result')
  return asCharge('Charge' in value ? value.Charge : value)
}

export { stringFields }
