/**
 * The "Show state graph" lens, as both hosts see it.
 *
 * The lens command is `l4.stateGraph` (named in each host's own command
 * table); the language server answers it with
 * {@link StateGraphResponse}, and so does the wasm shim in the browser. The
 * LSP producer addresses its target by **source position** (the start of the
 * `DECIDE`, 1-indexed, matched exactly — `L4.StateGraph.Lens.stateGraphAtPos`),
 * so a host that wants to redraw the pane after an edit has to know where that
 * `DECIDE` went. {@link trackSrcPos} is that arithmetic; it lives here
 * because both hosts need it, and is tested from the VS Code extension's
 * `node --test` rig (`ts-apps/vscode/src/unit-tests/state-graph.test.ts`),
 * this package having none. See LTS-VISUALISER.md §4.8 ("Live refresh").
 */
import type { SrcPos } from './custom-protocol.js'

/** What `l4.stateGraph` answers: the rule's name and its graph as DOT. */
export interface StateGraphResponse {
  name: string
  dot: string
}

/** `x` is a well-formed reply to `l4.stateGraph`. */
export function isStateGraphResponse(x: unknown): x is StateGraphResponse {
  return (
    typeof x === 'object' &&
    x !== null &&
    typeof (x as { dot?: unknown }).dot === 'string' &&
    typeof (x as { name?: unknown }).name === 'string'
  )
}

/**
 * One incremental document change, as VS Code's `TextDocumentContentChangeEvent`
 * and Monaco's shim both report it: a 0-indexed `range` that `text` replaces.
 * Structural, so neither host has to import the other's API.
 */
export interface ContentChange {
  range: {
    start: { line: number; character: number }
    end: { line: number; character: number }
  }
  text: string
}

/**
 * Where a 1-indexed source position lands after `changes` are applied in
 * order (the LSP's incremental-sync semantics: each range is relative to the
 * document as the previous change left it).
 *
 * - A change that ends at or before the position moves it: by the net line
 *   count when it ends on an earlier line, and along the line as well when it
 *   ends on the position's own line. An insertion *at* the position counts as
 *   before it, so typing at the start of a `DECIDE` pushes the `DECIDE` along.
 * - A change that starts after the position leaves it alone.
 * - A change that covers the position deleted the thing it named: `null`,
 *   and the caller should stop refreshing until the lens is pressed again.
 */
export function trackSrcPos(
  pos: SrcPos,
  changes: readonly ContentChange[]
): SrcPos | null {
  let line = pos.line - 1
  let col = pos.column - 1
  for (const { range, text } of changes) {
    const { start, end } = range
    const endsBefore =
      end.line < line || (end.line === line && end.character <= col)
    const startsAfter =
      start.line > line || (start.line === line && start.character > col)
    if (startsAfter) continue
    if (!endsBefore) return null
    const lastNl = text.lastIndexOf('\n')
    const addedLines = lastNl < 0 ? 0 : text.split('\n').length - 1
    // Where the replacement text ends, in the new document
    const insEndLine = start.line + addedLines
    const insEndCol =
      addedLines === 0
        ? start.character + text.length
        : text.length - (lastNl + 1)
    if (end.line === line) {
      col = insEndCol + (col - end.character)
      line = insEndLine
    } else {
      line += insEndLine - end.line
    }
  }
  return { line: line + 1, column: col + 1 }
}
