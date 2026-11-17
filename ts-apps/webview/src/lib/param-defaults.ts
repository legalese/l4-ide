/**
 * The usual value of an input, as the Deploy tab shows it.
 *
 * An input a rule gives a usual value (`TYPICALLY`) may be left out of a
 * request: the rule then takes that value. The language server publishes the
 * value with the local rule's schema and jl4-service with the deployed one, as
 * the JSON Schema keyword `default`, on a rule input and on a record field.
 *
 * A usual value is always a plain one (the type checker refuses anything
 * else): a number, a piece of text, TRUE or FALSE, a constructor of an
 * enumerated type, or NOTHING. One on an `ASSUME` is not published
 * (jl4-core/src/L4/Export.hs, `honouredDefault`). This module can only show
 * what is published, so an input with no `default` key says nothing, which is
 * not the same as having no usual value.
 *
 * Pure functions, no Svelte and no DOM, so that a test can import them.
 */

/** What these functions need of a schema node. `default` is the JSON value
 *  the service published; `null` is a real value (the usual value NOTHING). */
export interface HasDefault {
  default?: unknown
  enum?: string[]
}

/** A schema node with children, as far as `anyInputHasDefault` walks it. */
interface SchemaWithChildren extends HasDefault {
  properties?: Record<string, SchemaWithChildren>
  items?: unknown
}

/** Whether the node carries a usual value. Tests that the key is present,
 *  not that its value is truthy: 0, false, "" and null are all usual values. */
export function hasDefault(node: HasDefault | null | undefined): boolean {
  return (
    node != null &&
    Object.prototype.hasOwnProperty.call(node, 'default') &&
    node.default !== undefined
  )
}

/** The usual value itself, `undefined` when the node has none. */
export function defaultOf(node: HasDefault | null | undefined): unknown {
  return hasDefault(node) ? node!.default : undefined
}

/**
 * The usual value as text for the card, `undefined` when there is none.
 * Numbers and booleans are spelled as in the type column, text is quoted so
 * that an empty or padded value can be seen, a constructor of an enumerated
 * input is spelled by its bare name, as in the list of allowed values beside
 * it, and NOTHING reads "empty".
 */
export function describeDefault(
  node: HasDefault | null | undefined
): string | undefined {
  if (!hasDefault(node)) return undefined
  const value = node!.default
  if (value === null) return 'empty'
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value)
  }
  if (typeof value === 'string') {
    return node!.enum && node!.enum.length > 0 ? value : JSON.stringify(value)
  }
  // Not a shape the service publishes today.
  return JSON.stringify(value)
}

/** Whether any input of any of the rules, at any depth of record fields, has
 *  a usual value to show. It does not look inside a list's elements, because
 *  the rule card does not list them, so a usual value there is not shown. */
export function anyInputHasDefault(
  functions: ReadonlyArray<{
    parameters?: { properties?: Record<string, SchemaWithChildren> }
  }>
): boolean {
  const walk = (node: SchemaWithChildren | undefined): boolean => {
    if (!node) return false
    if (hasDefault(node)) return true
    return Object.values(node.properties ?? {}).some(walk)
  }
  return functions.some((fn) =>
    Object.values(fn.parameters?.properties ?? {}).some(walk)
  )
}
