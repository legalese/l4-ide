import type { FieldNode } from './types'

/**
 * Turn a raw schema `description` into a clean, human label.
 *
 * jl4-service emits DECLARE-field descriptions wrapped in backticks WITH a
 * leading space, e.g. " `How often is your rent due?`". The entry-parameter's
 * own description arrives clean (no backticks). This helper is the ONLY source
 * of every visible label/legend, and is idempotent + null-safe:
 *   - ' `How often is your rent due?`'        -> 'How often is your rent due?'
 *   - "The tenant's rent and payment situation" -> unchanged (only trims fire)
 *   - undefined                                -> ''
 */
export function cleanLabel(raw: string | undefined): string {
  const t = (raw ?? '').trim()
  const stripped =
    t.length >= 2 && t.startsWith('`') && t.endsWith('`')
      ? t.slice(1, -1).trim()
      : t
  return stripped
}

/** Fallback label when a node's description cleans to ''. Capitalises the first
 *  character of the spaced key, e.g. 'rent amount each time' -> 'Rent amount
 *  each time'. */
export function humanizeKey(key: string): string {
  return key.length ? key[0].toUpperCase() + key.slice(1) : key
}

/** A valid, unique, space-free DOM id for a field. x-sanitized-name is OPTIONAL,
 *  so the fallback slugifies the original spaced key — never 'undefined', never
 *  an id containing a space. */
export function fieldId(node: FieldNode): string {
  const base = node.sanitizedKey ?? node.key.replace(/[^a-z0-9]+/gi, '-')
  return 'f-' + base.toLowerCase()
}
