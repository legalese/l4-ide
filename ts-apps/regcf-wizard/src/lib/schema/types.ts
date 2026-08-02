import type { FunctionParameter, FunctionParameters } from '$lib/api/types'

/**
 * A faithful view of a JSON-Schema node as jl4-service ACTUALLY emits it on the
 * wire.
 *
 * IMPORTANT: the shared `FunctionParameter` type declares `enum: string[]` as
 * REQUIRED, but the service OMITS `enum` entirely on non-enum nodes (a
 * `number`/`boolean` node has no `enum` key at all). Reading `p.enum.length` on
 * such a node would throw. The renderer therefore walks this corrected,
 * all-optional view instead of the shared type.
 *
 * `format` is new here relative to the housing wizard: the Reg CF façade's
 * law-time export takes `rule date IS A DATE`, which reaches the wire as
 * `{"type":"string","format":"date"}` (measured). Without `format` a DATE would
 * classify as free text.
 */
export interface WireSchema {
  type?: string
  format?: string
  description?: string
  enum?: string[]
  properties?: Record<string, WireSchema>
  propertyOrder?: string[]
  required?: string[]
  items?: WireSchema
  'x-l4-type'?: string
  'x-sanitized-name'?: string
}

/** Reinterpret a shared FunctionParameter(s) as the faithful wire view. */
export function asWire(p: FunctionParameter | FunctionParameters): WireSchema {
  return p as unknown as WireSchema
}

export type WidgetKind =
  | 'enum'
  | 'number'
  | 'boolean'
  | 'date'
  | 'object'
  | 'text'
  | 'unsupported'

/** The renderer's normalised field-tree node — drives both display and dispatch. */
export interface FieldNode {
  /** ORIGINAL spaced key — the eval payload key. NEVER the sanitized form. */
  key: string
  /** x-sanitized-name, used for DOM ids / debugging ONLY. Optional on the wire. */
  sanitizedKey?: string
  /** Cleaned, never empty (falls back to a humanised key). */
  label: string
  /** Cleaned description when it differs from the label, else ''. */
  help: string
  widget: WidgetKind
  required: boolean
  enumOptions: string[]
  /** For object nodes. Leaves have []. */
  children: FieldNode[]
  raw: WireSchema
}
