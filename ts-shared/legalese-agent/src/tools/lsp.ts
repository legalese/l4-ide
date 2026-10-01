import type { L4Diagnostic, L4Language } from '../ports.js'

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
  return formatL4Diagnostics(await l4.getDiagnostics(uri))
}

/** Render diagnostics in the compact block format described above. */
export function formatL4Diagnostics(filtered: L4Diagnostic[]): string {
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
  const lines = filtered.map((d) => {
    const line = d.line + 1
    const source = d.source ?? ''
    const code = d.code ?? ''
    // `[source:code]` only when there's at least one of the two, to
    // avoid trailing brackets on diagnostics that carry neither.
    const tag =
      source || code ? ` [${[source, code].filter(Boolean).join(':')}]` : ''
    return `${d.severity} ${line} → ${d.message}${tag}`
  })
  return `${header}\n${lines.join('\n')}`
}
