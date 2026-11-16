/**
 * The query syntax of the agent's search tools.
 *
 * Pattern search (`fs__read_file` with `search_keywords`; jl4-service's
 * `search_text` follows the same rules):
 *
 * - Spaces separate patterns, and a line matches when any pattern does.
 *   Spaces inside `()`, `[]`, `{}`, backticks or double quotes don't
 *   separate, so `^(GIVEN|DECIDE).*(sum|`greater of`)` is one pattern.
 * - Double quotes around a pattern are dropped: `"the greater of"` is a
 *   phrase.
 * - Each pattern is a case-insensitive regular expression.
 * - A pattern that isn't a valid regular expression is matched as plain
 *   text, and the result says so.
 *
 * Word search (`search_rules`): the query's words, whatever else it holds.
 */

/** One pattern of a query, ready to test lines with. */
export interface SearchPattern {
  /** As written, without surrounding double quotes. */
  source: string
  test(line: string): boolean
  /** Set when `source` isn't a valid regular expression and is matched as
   *  plain text: why it isn't. */
  invalid?: string
}

/** The syntax, for tool descriptions and empty results. */
export const PATTERN_SYNTAX =
  'Each space-separated pattern is a case-insensitive regular expression ' +
  '(`^ $ . * + ? | ( ) [ ] {n,m}`, `\\s \\d \\w \\b`), and a line matches ' +
  'if any one does. Spaces inside `()`, `[]`, `{}`, backticks or double ' +
  'quotes stay in one pattern, and double quotes make a phrase: ' +
  '`"the greater of"`.'

/**
 * Split a query into patterns at the spaces outside `()`, `[]`, `{}`,
 * backticks and double quotes, and drop double quotes around a pattern.
 * A backslash escapes the next character; inside `[...]` only `]` closes.
 */
export function splitPatterns(query: string): string[] {
  const out: string[] = []
  let current = ''
  let depth = 0
  let inClass = false
  let inBacktick = false
  let inQuote = false
  const flush = () => {
    if (current) out.push(unquote(current))
    current = ''
  }
  for (let i = 0; i < query.length; i++) {
    const c = query[i]!
    if (c === '\\' && i + 1 < query.length) {
      current += c + query[++i]!
      continue
    }
    if (inClass) {
      if (c === ']') inClass = false
      current += c
      continue
    }
    if (/\s/.test(c) && depth === 0 && !inBacktick && !inQuote) {
      flush()
      continue
    }
    if (c === '`' && !inQuote) inBacktick = !inBacktick
    else if (c === '"' && !inBacktick) inQuote = !inQuote
    else if (!inBacktick && !inQuote) {
      if (c === '[') inClass = true
      else if (c === '(' || c === '{') depth++
      else if ((c === ')' || c === '}') && depth > 0) depth--
    }
    current += c
  }
  flush()
  return out
}

function unquote(s: string): string {
  return s.length >= 2 && s.startsWith('"') && s.endsWith('"')
    ? s.slice(1, -1)
    : s
}

/** The query's patterns, compiled. Empty for a blank query. */
export function compilePatterns(query: string): SearchPattern[] {
  return splitPatterns(query)
    .filter((source) => source.length > 0)
    .map((source): SearchPattern => {
      try {
        const re = new RegExp(source, 'i')
        return { source, test: (line) => re.test(line) }
      } catch (err) {
        const needle = source.toLowerCase()
        return {
          source,
          test: (line) => line.toLowerCase().includes(needle),
          invalid: regexError(err),
        }
      }
    })
}

/** The engine's reason, without its restatement of the pattern. */
function regexError(err: unknown): string {
  const msg = err instanceof Error ? err.message : String(err)
  return msg.replace(/^Invalid regular expression: \/.*\/[a-z]*: /s, '')
}

/** True when a line matches any pattern. */
export function matchesAny(
  patterns: readonly SearchPattern[]
): (line: string) => boolean {
  return (line) => patterns.some((p) => p.test(line))
}

/** One line per pattern matched as plain text, or `null` when none was. */
export function invalidPatternNote(
  patterns: readonly SearchPattern[]
): string | null {
  const notes = patterns
    .filter((p) => p.invalid !== undefined)
    .map(
      (p) =>
        `Note: ${JSON.stringify(p.source)} is not a valid regular expression ` +
        `(${p.invalid}), so it was matched as plain text.`
    )
  return notes.length > 0 ? notes.join('\n') : null
}

/** What to say when a pattern search found nothing. `scope` says where
 *  else to look, e.g. "search `.` to cover the whole workspace". */
export function noMatchHint(scope: string): string {
  return (
    `No matches. ${PATTERN_SYNTAX} To find more: use fewer or shorter ` +
    'patterns, alternatives such as `(total|sum)`, `\\s` for a space, ' +
    `or ${scope}.`
  )
}

/**
 * The words of a query for a word search: runs of letters and digits
 * (with `_`, `-` and `'` inside), lower-cased, at least two characters,
 * each once. Everything else, regex syntax included, separates words.
 */
export function searchWords(query: string): string[] {
  const words = query.toLowerCase().match(/[\p{L}\p{N}][\p{L}\p{N}_'-]*/gu)
  return [...new Set((words ?? []).filter((w) => w.length >= 2))]
}
