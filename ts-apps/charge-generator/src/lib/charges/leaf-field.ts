/**
 * The join between a ladder leaf and a facts-record field — the whole of the
 * "clicky-clicky" loop's data plumbing.
 *
 * A leaf on an offence ladder is one of:
 *
 *   - a PROJECTION of the facts record, `f's deliver` or
 *     `` f's `cause the delivery` `` or, through a nested record,
 *     `` r's theft's dishonestly `` — labelled by pretty-printing the expression
 *     (`leafFromExpr` in `jl4-lsp/src/LSP/L4/Viz/Ladder.hs`), so the label IS
 *     the access path and can be read back;
 *   - a CALL to another rule, `cheats f` — computed, not an input; its value is
 *     `verdictFor` on that rule's own ladder.
 *
 * Nothing here touches `atomId`; the join key between ladder and query-plan is
 * `unique` (see regcf-wizard's README §2), and the join between ladder and
 * facts record is the LABEL, parsed here.
 */

export type FieldPath = readonly string[]

export interface ProjectionLeaf {
  readonly kind: 'projection'
  readonly path: FieldPath
}
export interface CallLeaf {
  readonly kind: 'call'
  /** The called rule's name, backticks stripped: "cheats". */
  readonly fn: string
  /**
   * Where the callee's record lives inside the caller's: `cheats OF f` → [],
   * `` `commits theft` OF f's theft `` → ["theft"]. The callee's own leaves are
   * read and written UNDER this prefix.
   */
  readonly argPath: FieldPath
}
export interface OpaqueLeaf {
  readonly kind: 'opaque'
  readonly label: string
}
export type LeafBinding = ProjectionLeaf | CallLeaf | OpaqueLeaf

const strip = (s: string): string => s.trim().replace(/^`|`$/g, '')

/**
 * Parse a leaf label. `param` is the GIVEN name of the facts record ("f").
 *
 *   "f's deliver"                       → projection ["deliver"]
 *   "f's `cause the delivery`"          → projection ["cause the delivery"]
 *   "r's theft's dishonestly"           → projection ["theft", "dishonestly"]
 *   "cheats OF f"  /  "`commits theft` OF r's theft" → call "cheats" / "commits theft"
 */
export function parseLeafLabel(label: string, param: string): LeafBinding {
  const text = label.trim()
  const head = `${param}'s `
  if (text.startsWith(head)) {
    const rest = text.slice(head.length)
    // Split on the clitic between segments, respecting backticks.
    const segs: string[] = []
    let cur = ''
    let inTick = false
    for (let i = 0; i < rest.length; i++) {
      const c = rest[i]
      if (c === '`') {
        inTick = !inTick
        cur += c
        continue
      }
      if (!inTick && rest.startsWith("'s ", i)) {
        segs.push(cur)
        cur = ''
        i += 2
        continue
      }
      cur += c
    }
    segs.push(cur)
    return { kind: 'projection', path: segs.map(strip) }
  }
  // A call. MEASURED against the live service (2026-09-17): a call leaf is
  // printed with an explicit application keyword — `cheats OF f` — and arrives
  // as a UBoolVar with its own `unique`, not as an App. The rule name is the
  // leading backticked span or bare word before ` OF `.
  const call = /^(`[^`]+`|[A-Za-z][\w-]*)\s+OF\s+(.*)$/.exec(text)
  if (call) {
    const arg = call[2].trim().replace(/^\(|\)$/g, '')
    const inner = parseLeafLabel(arg, param)
    return {
      kind: 'call',
      fn: strip(call[1]),
      argPath: inner.kind === 'projection' ? inner.path : [],
    }
  }
  return { kind: 'opaque', label: text }
}

/** Read a boolean at a path in a facts record; undefined if absent/not boolean. */
export function readAt(
  facts: Record<string, unknown>,
  path: FieldPath
): boolean | undefined {
  let cur: unknown = facts
  for (const k of path) {
    if (typeof cur !== 'object' || cur === null) return undefined
    cur = (cur as Record<string, unknown>)[k]
  }
  return typeof cur === 'boolean' ? cur : undefined
}

/** Return a NEW facts record with the value at `path` set. Never mutates. */
export function writeAt(
  facts: Record<string, unknown>,
  path: FieldPath,
  value: unknown
): Record<string, unknown> {
  if (path.length === 0) return facts
  const [k, ...rest] = path
  const child = facts[k]
  if (rest.length === 0) return { ...facts, [k]: value }
  const inner =
    typeof child === 'object' && child !== null
      ? (child as Record<string, unknown>)
      : {}
  return { ...facts, [k]: writeAt(inner, rest, value) }
}

/** The three-state value a ladder leaf shows. */
export type Tri = 'TrueV' | 'FalseV' | 'UnknownV'

export const triOf = (b: boolean | undefined): Tri =>
  b === undefined ? 'UnknownV' : b ? 'TrueV' : 'FalseV'

/** One click: Unknown → True → False → True … (a fact, once asked, stays known). */
export const cycle = (b: boolean | undefined): boolean =>
  b === undefined ? true : !b
