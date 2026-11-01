import type { CheckedDiagnostics, L4Diagnostic, L4Language } from '../ports.js'

/**
 * LSP-backed diagnostics helper. Reads the current diagnostics the host
 * has for the target file (populated by jl4-lsp's publishDiagnostics)
 * through the {@link L4Language} port. Used by `l4__evaluate` (gates
 * evaluation on a clean type-check) and by the fs-tool auto-append
 * after edits.
 */

/**
 * Compact, glanceable diagnostics text block — one header line with
 * counts, then one line per diagnostic
 * (`severity line:col — message [source:code]`). Format keeps all
 * fields the old JSON exposed (line, column, severity, message,
 * source, code) — nothing is hidden, it's just ~5× fewer tokens than
 * the pretty-printed JSON for the same payload.
 */
export async function fetchL4Diagnostics(
  l4: L4Language,
  uri: string
): Promise<string> {
  return formatChecked(await l4.getCheckedDiagnostics(uri))
}

/** {@link formatL4Diagnostics}, saying so when the check hasn't finished. */
export function formatChecked(
  checked: CheckedDiagnostics,
  limit?: DiagnosticsLimit
): string {
  const block = formatL4Diagnostics(checked.diagnostics, limit)
  if (!checked.pending) return block
  return `--- L4 diagnostics: pending. The check has not finished, so this may be out of date ---\n${block}`
}

/** How much of a diagnostics block a tool result may carry. */
export interface DiagnosticsLimit {
  maxEntries: number
  maxChars: number
}

/**
 * How broken a file is, from the language server's own fields, so the
 * harness needs no knowledge of L4 syntax. A file that doesn't parse ranks
 * lowest and reports one error at a time, so fixing it can reveal more
 * errors while still being progress: compare with {@link isWorse}, never by
 * error count alone. A source this code doesn't know counts as a real error.
 */
export const FILE_LEVEL = {
  parseFailure: 0,
  errors: 1,
  failedChecks: 2,
  clean: 3,
} as const

export interface L4FileState {
  level: (typeof FILE_LEVEL)[keyof typeof FILE_LEVEL]
  errors: number
  warnings: number
  pending: boolean
  /** 0-based line of the first error, when there is one. */
  firstErrorLine?: number
}

export function l4FileState(checked: CheckedDiagnostics): L4FileState {
  const errors = checked.diagnostics.filter((d) => d.severity === 'error')
  const warnings = checked.diagnostics.filter(
    (d) => d.severity === 'warning'
  ).length
  let level: L4FileState['level'] = FILE_LEVEL.clean
  if (errors.some((d) => d.source === 'parser' || d.source === 'lexer')) {
    level = FILE_LEVEL.parseFailure
  } else if (errors.some((d) => d.source !== 'eval')) {
    level = FILE_LEVEL.errors
  } else if (errors.length > 0) {
    level = FILE_LEVEL.failedChecks
  }
  return {
    level,
    errors: errors.length,
    warnings,
    pending: checked.pending,
    ...(errors.length > 0
      ? { firstErrorLine: Math.min(...errors.map((d) => d.line)) }
      : {}),
  }
}

/** Whether `after` is further from clean than `before`. */
export function isWorse(before: L4FileState, after: L4FileState): boolean {
  if (after.level !== before.level) return after.level < before.level
  return after.errors > before.errors
}

/**
 * Whether `to` got closer to compiling than `from`. A file that doesn't
 * parse reports one error however many it has, so fixing them shows up as
 * the error moving down the file, not as a lower count.
 */
export function madeProgress(from: L4FileState, to: L4FileState): boolean {
  if (isWorse(to, from)) return true
  return (
    from.level === FILE_LEVEL.parseFailure &&
    to.level === FILE_LEVEL.parseFailure &&
    to.errors === from.errors &&
    (to.firstErrorLine ?? -1) > (from.firstErrorLine ?? -1)
  )
}

/** Short wording of a state for tool results and the turn status. */
export function describeFileState(state: L4FileState): string {
  const n = state.errors
  const errors = `${n} error${n === 1 ? '' : 's'}`
  switch (state.level) {
    case FILE_LEVEL.parseFailure:
      return `does not parse (${errors})`
    case FILE_LEVEL.errors:
      return `does not compile (${errors})`
    case FILE_LEVEL.failedChecks:
      return `compiles, with ${n} failed check${n === 1 ? '' : 's'}`
    default:
      return 'compiles'
  }
}

/**
 * Render diagnostics in the compact block format described above. With a
 * `limit` the header keeps the real counts and a last line says how many
 * were left out. Errors come first, whatever order the server listed them
 * in, so `#EVAL` results can't push out the thing to fix; failed checks lead,
 * so cascading errors can't hide one either.
 */
export function formatL4Diagnostics(
  filtered: L4Diagnostic[],
  limit?: DiagnosticsLimit
): string {
  if (filtered.length === 0) {
    return `--- L4 diagnostics: clean ---`
  }
  const counts = {
    error: filtered.filter((d) => d.severity === 'error').length,
    warning: filtered.filter((d) => d.severity === 'warning').length,
    info: filtered.filter((d) => d.severity === 'info').length,
    hint: filtered.filter((d) => d.severity === 'hint').length,
  }
  const summary = [
    counts.error ? `${counts.error} error${counts.error === 1 ? '' : 's'}` : '',
    counts.warning
      ? `${counts.warning} warning${counts.warning === 1 ? '' : 's'}`
      : '',
    counts.info ? `${counts.info} info` : '',
    counts.hint ? `${counts.hint} hint${counts.hint === 1 ? '' : 's'}` : '',
  ]
    .filter(Boolean)
    .join(', ')
  const header = `--- L4 diagnostics: ${filtered.length} issue${filtered.length === 1 ? '' : 's'} (${summary}) ---`
  const render = (d: L4Diagnostic): string => {
    const line = d.line + 1
    const source = d.source ?? ''
    const code = d.code ?? ''
    // `[source:code]` only when there's at least one of the two, to
    // avoid trailing brackets on diagnostics that carry neither.
    const tag =
      source || code ? ` [${[source, code].filter(Boolean).join(':')}]` : ''
    return `${d.severity} ${line} → ${d.message}${tag}`
  }
  if (!limit) return `${header}\n${filtered.map(render).join('\n')}`
  const rank = (d: L4Diagnostic): number => {
    if (d.severity === 'error') return d.source === 'eval' ? 0 : 1
    return d.severity === 'warning' ? 2 : d.severity === 'info' ? 3 : 4
  }
  const ordered = [...filtered].sort((a, b) => rank(a) - rank(b))
  const shown: string[] = []
  let chars = 0
  for (const d of ordered) {
    const text = render(d)
    if (shown.length >= limit.maxEntries) break
    // Always show one, however long: it's the one to fix.
    if (shown.length > 0 && chars + text.length > limit.maxChars) break
    shown.push(text)
    chars += text.length + 1
  }
  const hidden = ordered.length - shown.length
  const tail =
    hidden > 0
      ? `\n... and ${hidden} more. Fix the ones above first; l4__evaluate lists everything.`
      : ''
  return `${header}\n${shown.join('\n')}${tail}`
}
