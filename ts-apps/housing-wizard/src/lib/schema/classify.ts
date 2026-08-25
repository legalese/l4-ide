import type { WireSchema, WidgetKind } from './types'

/**
 * Decide a widget by SHAPE. Order is load-bearing:
 *
 * 1. object FIRST — a malformed node with both `properties` and a stray `enum`
 *    still renders as a fieldset, never a broken select.
 * 2. enum gated on LENGTH, not presence — the wire omits `enum` on non-enum
 *    nodes (it arrives as undefined, not []), so `(p.enum?.length ?? 0) > 0` is
 *    the only robust test.
 * 3..5. number / boolean / string leaves.
 * 6. arrays and anything else are 'unsupported' (no ArrayField — element
 *    reassignment is the most $state-reactivity-fragile pattern, and the live
 *    schema has none).
 *
 * Total over all shapes.
 */
export function classifyWidget(p: WireSchema): WidgetKind {
  if (p.type === 'object' && p.properties) return 'object'
  if ((p.enum?.length ?? 0) > 0) return 'enum'
  if (p.type === 'number' || p.type === 'integer') return 'number'
  if (p.type === 'boolean') return 'boolean'
  if (p.type === 'string') return 'text'
  if (p.type === 'array' || p.items) return 'unsupported'
  return 'unsupported'
}
