import { cleanLabel, humanizeKey } from './labels'
import { classifyWidget } from './classify'
import type { WireSchema, FieldNode } from './types'

/**
 * The single source of child display order. propertyOrder first (filtered to
 * keys that actually exist), then any unlisted keys appended in object-key
 * order — so a key missing from propertyOrder is never dropped. If
 * propertyOrder is absent, fall back to `required` order and then Object.keys.
 *
 * The `required` fallback is not cosmetic. The Reg CF law-time export has TWO
 * root parameters and the service emits NO propertyOrder for the root node
 * (measured: `propertyOrder` absent, `required: ["rule date","facts"]`), while
 * `Object.keys` is alphabetical — which would put the four investor questions
 * ahead of the date they are to be judged against, inverting the very
 * derivation ruling R8 asks the page to display.
 */
export function orderedChildKeys(p: WireSchema): string[] {
  const props = p.properties ?? {}
  const all = Object.keys(props)
  const order =
    p.propertyOrder && p.propertyOrder.length > 0 ? p.propertyOrder : p.required
  if (!order || order.length === 0) return all
  const listed = order.filter((k) => k in props)
  const rest = all.filter((k) => !order.includes(k))
  return [...listed, ...rest]
}

/**
 * Pure recursion WireSchema -> FieldNode. Depth-agnostic.
 *
 * `requiredSet` is the PARENT object node's `required` list: per-child
 * `required` arrays do NOT exist in the wire data — required + propertyOrder
 * live only on the parent object node. node.key is ALWAYS the original spaced
 * key (the eval payload key).
 */
export function buildFieldTree(
  p: WireSchema,
  key: string,
  requiredSet: Set<string>
): FieldNode {
  const widget = classifyWidget(p)
  const cleaned = cleanLabel(p.description)
  const label = cleaned || humanizeKey(key)
  const help = cleaned && cleaned !== label ? cleaned : ''
  const enumOptions = p.enum && p.enum.length ? [...p.enum] : []

  let children: FieldNode[] = []
  if (widget === 'object' && p.properties) {
    const childReq = new Set(p.required ?? [])
    const props = p.properties
    children = orderedChildKeys(p).map((k) =>
      buildFieldTree(props[k], k, childReq)
    )
  }

  return {
    key,
    sanitizedKey: p['x-sanitized-name'],
    label,
    help,
    widget,
    required: requiredSet.has(key),
    enumOptions,
    children,
    raw: p,
  }
}
