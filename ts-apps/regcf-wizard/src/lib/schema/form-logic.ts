import { fieldId } from './labels'
import type { FieldNode } from './types'
import type { FormState, FormValue } from '$lib/api/types'

/**
 * Pure form helpers — NO Svelte runes here, so they are unit-testable in plain
 * Node (the $state seed lives in form-state.svelte.ts and just wraps `seed`).
 */

/** Build the default value tree, keyed by ORIGINAL spaced keys. */
export function seed(node: FieldNode): FormState {
  const out: FormState = {}
  for (const child of node.children) {
    out[child.key] = seedValue(child)
  }
  return out
}

function seedValue(node: FieldNode): FormValue {
  switch (node.widget) {
    case 'object':
      return seed(node)
    case 'number':
      return null // empty = unanswered, distinct from a real 0
    case 'boolean':
      return null // UNANSWERED — never silently assert false
    case 'unsupported':
      return null
    case 'date':
    case 'enum':
    case 'text':
    default:
      return '' // sentinel = unanswered (placeholder selected)
  }
}

/** ISO calendar dates only. `<input type=date>` yields exactly this, but a
 *  keyboard-entered value in a browser without the native picker does not. */
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/

/** Is this an ISO date string naming a real calendar day? */
export function isIsoDate(v: string): boolean {
  if (!ISO_DATE.test(v)) return false
  const d = new Date(v + 'T00:00:00Z')
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === v
}

/**
 * Validate required leaves. Returns a map keyed by fieldId(node) for focus +
 * aria wiring. Blocks confidently-wrong inputs: a negative dollar amount
 * otherwise yields an answer the law never contemplated.
 */
export function validate(
  root: FieldNode,
  state: FormState
): Record<string, string> {
  const errors: Record<string, string> = {}
  walk(root, state, errors)
  return errors
}

function walk(
  node: FieldNode,
  slice: FormState,
  errors: Record<string, string>
): void {
  for (const child of node.children) {
    const v = slice[child.key]
    if (child.widget === 'object') {
      walk(child, isState(v) ? v : {}, errors)
      continue
    }
    if (!child.required) continue
    const msg = leafError(child, v)
    if (msg) errors[fieldId(child)] = msg
  }
}

function leafError(node: FieldNode, v: FormValue): string | null {
  switch (node.widget) {
    case 'enum':
      return v === '' || v === null ? 'Please choose an option' : null
    case 'text':
      return v === '' || v === null ? 'Please fill this in' : null
    case 'date':
      if (v === '' || v === null) return 'Please choose a date'
      if (typeof v !== 'string' || !isIsoDate(v))
        return 'Please give a date as YYYY-MM-DD'
      return null
    case 'number':
      if (v === null || v === undefined) return 'Please enter an amount'
      // Number.isFinite rejects both NaN and ±Infinity (e.g. "1e400" parses to
      // Infinity, which JSON-serialises to null on a typed numeric field → an
      // opaque 422 from the service).
      if (typeof v !== 'number' || !Number.isFinite(v))
        return 'Please enter a number, like 500'
      if (v < 0) return 'Amount cannot be negative'
      return null
    case 'boolean':
      return typeof v === 'boolean' ? null : 'Please choose Yes or No'
    default:
      return null
  }
}

/**
 * Build the exact eval `arguments` payload: an object keyed by the ORIGINAL
 * spaced keys, with JS numbers as numbers and JS booleans as booleans
 * (stringified numbers/booleans are a verified 422). Builds a FRESH output —
 * never spreads a $state branch (which would detach the proxy).
 *
 * The housing wizard cast this to `{situation: FormState}` because its one
 * export had a single record parameter. Reg CF's law-time export has TWO roots
 * (`rule date` and `facts`), so the return type is the general one: whatever
 * roots the schema declared. Callers that need a specific root read it by name.
 */
export function toArguments(root: FieldNode, state: FormState): FormState {
  return build(root, state)
}

function build(node: FieldNode, slice: FormState): FormState {
  const out: FormState = {}
  for (const child of node.children) {
    const v = slice[child.key]
    out[child.key] =
      child.widget === 'object' ? build(child, isState(v) ? v : {}) : v
  }
  return out
}

function isState(v: FormValue): v is FormState {
  return typeof v === 'object' && v !== null && !Array.isArray(v)
}
