import type { Charge } from './types'

function isRecord(x: unknown): x is Record<string, unknown> {
  return typeof x === 'object' && x !== null
}

/** Shape-check a `Charge` record off the wire. Throws with the missing key. */
export function asCharge(x: unknown): Charge {
  if (!isRecord(x)) throw new Error('Charge: not an object')
  const need = (k: keyof Charge, t: 'string' | 'boolean') => {
    if (typeof x[k] !== t) throw new Error(`Charge: missing ${String(k)}`)
  }
  need('section', 'string')
  need('offence', 'string')
  need('made out', 'boolean')
  need('text', 'string')
  need('refusal', 'string')
  need('punishment', 'string')
  return x as unknown as Charge
}
