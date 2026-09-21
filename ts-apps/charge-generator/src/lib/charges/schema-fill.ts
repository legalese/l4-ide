import type { FunctionParameter } from '$lib/api/types'

/**
 * A facts record on the wire must be COMPLETE — jl4-service decodes the whole
 * record — while the officer's facts are partial until the interview is done.
 * Fill every missing field with the identity of its type: an unknown element is
 * FALSE (a charge asserts every element TRUE, so "unknown" cannot be charged),
 * an unknown particular is the empty string, an enum takes its first value.
 */
export function fillDefaults(
  schema: FunctionParameter | undefined,
  value: unknown
): unknown {
  if (!schema) return value
  if (schema.properties) {
    const src =
      typeof value === 'object' && value !== null
        ? (value as Record<string, unknown>)
        : {}
    const out: Record<string, unknown> = {}
    const order = schema.propertyOrder ?? Object.keys(schema.properties)
    for (const k of order) out[k] = fillDefaults(schema.properties[k], src[k])
    return out
  }
  if (value !== undefined && value !== null) return value
  if (schema.enum && schema.enum.length > 0) return schema.enum[0]
  switch (schema.type) {
    case 'boolean':
      return false
    case 'number':
    case 'integer':
      return 0
    case 'array':
      return []
    default:
      return ''
  }
}

export interface StringField {
  readonly path: readonly string[]
  readonly description: string
  readonly enum?: readonly string[]
}

/** Every string/enum field, depth-first in schema order — the particulars form. */
export function stringFields(
  schema: FunctionParameter | undefined,
  prefix: readonly string[] = []
): StringField[] {
  if (!schema) return []
  if (schema.properties) {
    const order = schema.propertyOrder ?? Object.keys(schema.properties)
    return order.flatMap((k) =>
      stringFields(schema.properties![k], [...prefix, k])
    )
  }
  if (schema.type === 'string' || (schema.enum && schema.enum.length > 0))
    return [
      {
        path: prefix,
        description: schema.description ?? '',
        enum: schema.enum && schema.enum.length > 0 ? schema.enum : undefined,
      },
    ]
  return []
}

/** The facts-record parameter of an export's schema. */
export function factsSchema(
  params: { properties: Record<string, FunctionParameter> } | undefined,
  param: string
): FunctionParameter | undefined {
  return params?.properties[param]
}
