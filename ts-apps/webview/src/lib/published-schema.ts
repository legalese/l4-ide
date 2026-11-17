/**
 * The schema of a rule's inputs as a client is shown it.
 *
 * The language server and the service carry a few keys of their own on a schema
 * node: `alias`, `propertyOrder`, `x-l4-type` and `x-sanitized-name`. They serve
 * the sidebar and chat clients. The OpenAPI document deletes them
 * (jl4-service/src/OpenApiDoc.hs `stripNonOpenApiFields`) and so does the MCP
 * tool list (jl4-service/src/Shared.hs `sanitizeParameterValue`), so a card that
 * printed the schema untouched would show JSON no client receives.
 *
 * The keys come off each schema node: the root, every field under
 * `properties`, and the elements under `items`. The names of the properties
 * themselves are left alone (the OpenAPI document's own strip deletes by key at
 * every level, so it also drops an input that is itself named `alias`; MCP does
 * not, and this follows MCP there).
 *
 * MCP and WebMCP also spell input names without spaces; this keeps the names as
 * the OpenAPI document spells them, and the card says so.
 *
 * Pure, no Svelte and no DOM.
 */
const NON_CLIENT_KEYS = new Set([
  'alias',
  'propertyOrder',
  'x-l4-type',
  'x-sanitized-name',
])

export function publishedInputSchema(node: unknown): unknown {
  if (node === null || typeof node !== 'object' || Array.isArray(node)) {
    return node
  }
  const out: Record<string, unknown> = {}
  for (const [key, value] of Object.entries(node)) {
    if (NON_CLIENT_KEYS.has(key)) continue
    if (
      key === 'properties' &&
      value !== null &&
      typeof value === 'object' &&
      !Array.isArray(value)
    ) {
      out[key] = Object.fromEntries(
        Object.entries(value).map(([name, child]) => [
          name,
          publishedInputSchema(child),
        ])
      )
    } else if (key === 'items') {
      out[key] = publishedInputSchema(value)
    } else {
      out[key] = value
    }
  }
  return out
}
