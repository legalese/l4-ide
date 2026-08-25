import type { WireSchema, WidgetKind } from './types'

/**
 * Decide a widget by SHAPE. Order is load-bearing:
 *
 * 1. object FIRST — a malformed node with both `properties` and a stray `enum`
 *    still renders as a fieldset, never a broken select.
 * 2. enum gated on LENGTH, not presence — the wire omits `enum` on non-enum
 *    nodes (it arrives as undefined, not []), so `(p.enum?.length ?? 0) > 0` is
 *    the only robust test.
 * 3. number / boolean.
 * 4. `date` BEFORE plain string: an L4 `DATE` reaches the wire as
 *    `{"type":"string","format":"date"}`, and rendering it as free text would
 *    let a citizen type "last June" into a field the evaluator parses strictly.
 * 5. string leaves.
 * 6. arrays and anything else are 'unsupported' (no ArrayField — element
 *    reassignment is the most $state-reactivity-fragile pattern, and no Reg CF
 *    input parameter is an array).
 *
 * Total over all shapes.
 */
export function classifyWidget(p: WireSchema): WidgetKind {
  if (p.type === 'object' && p.properties) return 'object'
  if ((p.enum?.length ?? 0) > 0) return 'enum'
  if (p.type === 'number' || p.type === 'integer') return 'number'
  if (p.type === 'boolean') return 'boolean'
  if (p.type === 'string' && p.format === 'date') return 'date'
  if (p.type === 'string') return 'text'
  if (p.type === 'array' || p.items) return 'unsupported'
  return 'unsupported'
}
