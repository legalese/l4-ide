import type { LspPosition } from './ports.js'

/**
 * Offset ↔ (line, character) conversion over a document's raw text,
 * with the same rules as VS Code's `TextDocument.positionAt/offsetAt`
 * and LSP positions: `\r\n`, `\n` and a lone `\r` each end a line, and
 * characters are UTF-16 code units.
 */

/** Start offset of every line in `text`. */
export function lineStarts(text: string): number[] {
  const starts = [0]
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i)
    if (c === 13) {
      if (text.charCodeAt(i + 1) === 10) i++
      starts.push(i + 1)
    } else if (c === 10) {
      starts.push(i + 1)
    }
  }
  return starts
}

/** Length of line `line` without its terminator. */
function lineEnd(text: string, starts: number[], line: number): number {
  const next = starts[line + 1]
  if (next === undefined) return text.length
  let end = next
  if (end > 0 && text.charCodeAt(end - 1) === 10) end--
  if (end > 0 && text.charCodeAt(end - 1) === 13) end--
  return end
}

export function positionAt(text: string, offset: number): LspPosition {
  const clamped = Math.max(0, Math.min(offset, text.length))
  const starts = lineStarts(text)
  let lo = 0
  let hi = starts.length - 1
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1
    if (starts[mid]! <= clamped) lo = mid
    else hi = mid - 1
  }
  const lineStart = starts[lo]!
  const end = lineEnd(text, starts, lo)
  return { line: lo, character: Math.min(clamped, end) - lineStart }
}

export function offsetAt(text: string, position: LspPosition): number {
  const starts = lineStarts(text)
  if (position.line < 0) return 0
  if (position.line >= starts.length) return text.length
  const lineStart = starts[position.line]!
  const end = lineEnd(text, starts, position.line)
  return Math.min(lineStart + Math.max(0, position.character), end)
}

/** The text between two positions. */
export function textInRange(
  text: string,
  range: { start: LspPosition; end: LspPosition }
): string {
  return text.slice(offsetAt(text, range.start), offsetAt(text, range.end))
}
