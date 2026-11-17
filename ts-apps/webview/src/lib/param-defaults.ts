/**
 * The default of an input, as the Deploy tab shows it.
 *
 * An input a rule gives a default (`TYPICALLY`) may be left out of a request:
 * the rule then uses it, and the answer lists the input under `presumed`. The
 * language server publishes the value with the local rule's schema and
 * jl4-service with the deployed one, as the JSON Schema keyword `default`, on a
 * rule input and on a record field.
 *
 * A default is always a plain value (the type checker refuses anything else):
 * a number, a piece of text, TRUE or FALSE, a constructor of an enumerated
 * type, or NOTHING. One on an `ASSUME` is not published
 * (jl4-core/src/L4/Export.hs, `honouredDefault`); the language server names
 * those inputs separately (`unpublishedDefaults`), because the schema itself
 * only omits the key. This module can only show what it is given, so an input
 * with no `default` key says nothing, which is not the same as having no
 * default.
 *
 * Pure functions, no Svelte and no DOM, so that a test can import them.
 */

/** What these functions need of a schema node. `default` is the JSON value
 *  the service published; `null` is a real value (the default NOTHING). */
export interface HasDefault {
  default?: unknown
  enum?: string[]
}

/** A schema node with children, as far as `anyInputHasDefault` walks it. */
interface SchemaWithChildren extends HasDefault {
  properties?: Record<string, SchemaWithChildren>
  items?: unknown
}

/** Whether the node carries a default. Tests that the key is present, not
 *  that its value is truthy: 0, false, "" and null are all defaults. */
export function hasDefault(node: HasDefault | null | undefined): boolean {
  return (
    node != null &&
    Object.prototype.hasOwnProperty.call(node, 'default') &&
    node.default !== undefined
  )
}

/** The default itself, `undefined` when the node has none. */
export function defaultOf(node: HasDefault | null | undefined): unknown {
  return hasDefault(node) ? node!.default : undefined
}

/**
 * The default as text for the card, `undefined` when there is none. Numbers
 * and booleans are spelled as in the type column, text is quoted so that an
 * empty or padded value can be seen, a constructor of an enumerated input is
 * spelled by its bare name, as in the list of allowed values beside it, and
 * NOTHING reads "nothing".
 */
export function describeDefault(
  node: HasDefault | null | undefined
): string | undefined {
  if (!hasDefault(node)) return undefined
  const value = node!.default
  if (value === null) return 'nothing'
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
 *  a default to show. It does not look inside a list's elements, because the
 *  rule card does not list them, so a default there is not shown. */
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

/** Whether a default sits on a field inside a list's elements, anywhere in the
 *  rules' inputs. The service publishes it, but the rule card does not list
 *  those fields, so it is not shown. */
export function anyDefaultInsideLists(
  functions: ReadonlyArray<{
    parameters?: { properties?: Record<string, SchemaWithChildren> }
  }>
): boolean {
  const walk = (
    node: SchemaWithChildren | undefined,
    inList: boolean
  ): boolean => {
    if (!node) return false
    if (inList && hasDefault(node)) return true
    const items = node.items as SchemaWithChildren | undefined
    return (
      Object.values(node.properties ?? {}).some((c) => walk(c, inList)) ||
      walk(items, true)
    )
  }
  return functions.some((fn) =>
    Object.values(fn.parameters?.properties ?? {}).some((p) => walk(p, false))
  )
}

/** How one input reads on the card. */
export interface InputStatus {
  kind: 'required' | 'optional' | 'typically' | 'unpublished'
  /** "required", "optional", "optional, typically 0" or
   *  "typically (not published)". */
  label: string
  /** Plain words under the row, when there is something to explain. */
  hint?: string
}

/**
 * What the card says about one input: required, optional, or optional with a
 * default (which a caller who leaves the input out gets).
 *
 * @param path the input's name, or for a record field its path (`cfg.retries`)
 * @param required whether the schema lists the input as required
 * @param unpublished the file gives the input a default that the service does
 *   not publish (an `ASSUME`'s), so the schema has no `default` key for it
 */
export function inputStatus(
  path: string,
  node: HasDefault | null | undefined,
  required: boolean,
  unpublished = false
): InputStatus {
  if (hasDefault(node)) {
    const value = describeDefault(node)!
    return {
      kind: 'typically',
      label: `optional, typically ${value}`,
      hint: `If left out, ${value} is used, and the answer lists ${path} under presumed when it relies on that.`,
    }
  }
  if (unpublished) {
    return {
      kind: 'unpublished',
      label: 'typically (not published)',
      hint:
        'The file gives this input a typical value, but the service neither publishes nor uses it.' +
        (required ? ' Callers must still supply it.' : ''),
    }
  }
  return required
    ? { kind: 'required', label: 'required' }
    : { kind: 'optional', label: 'optional' }
}

/** Said under a rule's inputs when any of them has a default (the presumption
 *  switch is `"presumption": "hard"` over HTTP, `--presumption hard` in `l4
 *  batch`). */
export const PRESUMPTION_NOTE =
  'Callers can turn the defaults off with presumption: hard (HTTP, batch, MCP, WebMCP).'
