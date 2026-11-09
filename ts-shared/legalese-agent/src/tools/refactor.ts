import type {
  L4Language,
  LspPosition,
  SemanticTokensSnapshot,
  Workspace,
  WorkspaceTextEdit,
} from '../ports.js'
import { offsetAt, positionAt, textInRange } from '../text-positions.js'
import { resolveFileUri } from './fs.js'

/**
 * L4 refactor tool — single AI-facing entry point with an `action`
 * discriminator. Today we ship `rename`; more refactors (extract,
 * inline, …) plug in as additional cases without growing the tool
 * surface area or having the model learn new tool names.
 *
 * Currently supported actions:
 *  - `rename`: rename an identifier across the file AND every file
 *    that IMPORTs it. Drives the LSP's existing references provider
 *    (jl4-lsp/app/LSP/L4/Handlers.hs SMethod_TextDocumentReferences,
 *    which already unions matches across reverse-import deps) and
 *    applies the substitution to every returned Location as one
 *    workspace edit. Preserves backtick quoting per-occurrence; force-
 *    wraps when the new name contains characters outside [A-Za-z0-9_].
 *
 * No native LSP rename is implemented server-side — driving the
 * references provider gives us cross-file scope (including transitive
 * IMPORTers) without having to add a textDocument/rename handler to
 * jl4-lsp first.
 */

export type L4RefactorAction = 'rename'

export interface L4RefactorArgs {
  action: L4RefactorAction
  path: string
  // `rename` action parameters
  oldName?: string
  newName?: string
}

/** What `l4__refactor` needs from the host. */
export interface RefactorContext {
  workspace: Workspace
  l4: L4Language
}

interface L4RenameArgs {
  path: string
  oldName: string
  newName: string
}

/**
 * Dispatch a refactor action. Validates the action discriminator
 * up-front so an unknown action produces a clear error rather than a
 * silent miss on a missing parameter further down. Throws on failure;
 * the tool dispatcher wraps the throw into a `{ok: false}` tool
 * result for the model.
 */
export async function l4Refactor(
  ctx: RefactorContext,
  args: L4RefactorArgs
): Promise<string> {
  if (!args || typeof args !== 'object') {
    throw new Error('l4__refactor: arguments object is required')
  }
  if (typeof args.action !== 'string' || args.action.length === 0) {
    throw new Error(
      "l4__refactor: 'action' is required. Supported actions: rename."
    )
  }
  switch (args.action) {
    case 'rename':
      if (
        typeof args.oldName !== 'string' ||
        typeof args.newName !== 'string'
      ) {
        throw new Error(
          "l4__refactor: action='rename' requires 'oldName' and 'newName'."
        )
      }
      return l4Rename(ctx, {
        path: args.path,
        oldName: args.oldName,
        newName: args.newName,
      })
    default:
      throw new Error(
        `l4__refactor: unknown action "${args.action}". Supported actions: rename.`
      )
  }
}

export const BARE_IDENT_RE = /^[A-Za-z_][A-Za-z0-9_]*$/

/** Cheap, lexer-shape-independent validation: rejects inputs that can
 *  never be valid identifier text in L4 surface syntax regardless of
 *  the file they target — annotations (`@…`), directives (`#…`), line
 *  comments (`--…`), path/URL-shaped strings, multi-line input, and
 *  stray interior backticks. We deliberately DO NOT do a keyword check
 *  here: that's the lexer's call, and it depends on the file state, so
 *  it lives in `classifyAnchorToken` (uses the LSP's semantic tokens).
 *  Returns the bare name (backticks stripped); the caller re-wraps per
 *  occurrence. */
function validateRefactorName(
  raw: unknown,
  role: 'oldName' | 'newName'
): string {
  if (typeof raw !== 'string' || raw.length === 0) {
    throw new Error(
      `l4__refactor (rename): ${role} is required (non-empty string)`
    )
  }
  const name = raw.replace(/^`+|`+$/g, '')
  if (name.length === 0) {
    throw new Error(
      `l4__refactor (rename): ${role} must contain at least one non-backtick character`
    )
  }
  // L4's lexer disallows backticks inside a quoted identifier (see
  // jl4-core/src/L4/Lexer.hs `quoted`). Reject before we emit text that
  // wouldn't lex.
  if (name.includes('`')) {
    throw new Error(
      `l4__refactor (rename): ${role} must not contain an interior backtick character.`
    )
  }
  if (/[\r\n]/.test(name)) {
    throw new Error(
      `l4__refactor (rename): ${role} must be a single line — got ${JSON.stringify(name)}.`
    )
  }
  // '@' prefixes L4 annotations: @ref, @ref-src, @ref-map, @nlg, @desc,
  // @export. These attach to declarations; they aren't identifiers
  // themselves. Reject so a model that pastes "@export" or a
  // markdown-style "@l4-ide/doc/.../foo.md" gets a clear error.
  if (name.startsWith('@')) {
    throw new Error(
      `l4__refactor (rename): ${role} ${JSON.stringify(name)} starts with '@' — that prefix marks an L4 annotation (@ref, @desc, @export, @nlg), not an identifier. Pass the identifier name as it appears in source.`
    )
  }
  // '#' prefixes L4 directives: #EVAL, #EVALTRACE, #CHECK, #TRACE, #ASSERT.
  if (name.startsWith('#')) {
    throw new Error(
      `l4__refactor (rename): ${role} ${JSON.stringify(name)} starts with '#' — that prefix marks an L4 directive (#EVAL, #CHECK, …), not an identifier.`
    )
  }
  // '--' opens a line comment.
  if (name.startsWith('--')) {
    throw new Error(
      `l4__refactor (rename): ${role} ${JSON.stringify(name)} starts with '--' — that's an L4 line comment, not an identifier.`
    )
  }
  // Path / URL shapes — the model occasionally lifts a doc filename
  // (e.g. "@l4-ide/doc/tutorials/exporting-rules.md") into this slot.
  if (name.includes('/') || name.includes('\\')) {
    throw new Error(
      `l4__refactor (rename): ${role} ${JSON.stringify(name)} contains a path separator ('/' or '\\'). Pass the identifier as it appears in the source file, not a file path or URL.`
    )
  }
  return name
}

/** LSP/VSCode semantic-token types that count as identifier-like — the
 *  things a rename can legitimately target. jl4-lsp emits `variable`
 *  for plain identifiers and refines to `function`/`class`/`enum`/
 *  `type`/`typeParameter`/`interface` in typed contexts (see
 *  jl4-lsp/src/LSP/L4/SemanticTokens.hs). Everything else — `keyword`,
 *  `comment`, `string`, `number`, `operator`, `macro` (directive),
 *  `decorator` (annotation) — is not a rename target. */
export const IDENTIFIER_TOKEN_TYPES: ReadonlySet<string> = new Set([
  'variable',
  'function',
  'class',
  'enum',
  'enumMember',
  'interface',
  'struct',
  'type',
  'typeParameter',
  'parameter',
  'property',
  'method',
  'namespace',
  'event',
  'label',
])

/** Friendlier names for the non-identifier categories jl4-lsp emits.
 *  Maps the LSP type name to "what the model probably gave us". */
const NON_IDENTIFIER_LABELS: Readonly<Record<string, string>> = {
  keyword: 'an L4 keyword',
  comment: 'inside a comment',
  string: 'inside a string literal',
  number: 'a numeric literal',
  operator: 'an operator',
  macro: 'an L4 directive (#EVAL/#CHECK/…)',
  decorator: 'an L4 annotation (@ref/@desc/@export/…)',
}

/** Walk the delta-encoded semantic tokens (5-tuples of [deltaLine,
 *  deltaStartChar, length, tokenTypeIdx, modifierMask]) to find the
 *  token whose interval contains `pos`, and return its type name via
 *  the legend. Returns `null` if no token covers the position. */
export function classifyTokenAt(
  tokens: SemanticTokensSnapshot,
  pos: LspPosition
): string | null {
  const data = tokens.data
  let line = 0
  let char = 0
  for (let i = 0; i + 4 < data.length; i += 5) {
    const deltaLine = data[i]!
    const deltaStart = data[i + 1]!
    const length = data[i + 2]!
    const typeIdx = data[i + 3]!
    if (deltaLine === 0) {
      char += deltaStart
    } else {
      line += deltaLine
      char = deltaStart
    }
    if (line === pos.line) {
      if (char <= pos.character && pos.character < char + length) {
        return tokens.tokenTypes[typeIdx] ?? null
      }
    } else if (line > pos.line) {
      break
    }
  }
  return null
}

/** Classify the token at `pos` using the language server's semantic
 *  tokens. Returns `null` when semantic tokens are unavailable (the
 *  file hasn't type-checked yet, the provider isn't ready) or no token
 *  covers the position — "no lexer-side check possible"; the
 *  downstream references provider then catches non-identifier anchors
 *  with its own error. */
export async function classifyAnchorToken(
  l4: L4Language,
  uri: string,
  pos: LspPosition
): Promise<string | null> {
  let tokens: SemanticTokensSnapshot | null
  try {
    tokens = await l4.getSemanticTokens(uri)
  } catch {
    return null
  }
  if (!tokens || tokens.data.length === 0) return null
  return classifyTokenAt(tokens, pos)
}

/** Escape a string for use inside a JS RegExp pattern. */
function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

/** Enumerate every source-text occurrence of `oldName` in `doc` as a
 *  position picked STRICTLY INSIDE the name token (mid-character).
 *  Backticked occurrences come first, then bare-identifier occurrences,
 *  in the order they appear in the file.
 *
 *  Why mid-character: jl4-lsp's `lookupReference` does an interval
 *  search at the supplied SrcPos and returns refs for EVERY symbol
 *  whose interval contains that pos. If we point at the first or last
 *  character of the name, we sit on the boundary of any enclosing AST
 *  node that starts/ends there too — the LSP then unions in those
 *  outer nodes' references, which arrive as ranges that don't match
 *  the name we're renaming. Anchoring one column past the start (and,
 *  for backticked names, past the opening backtick) keeps us inside
 *  just the name's interval.
 *
 *  Multiple candidates matter because the textual scan happily hits
 *  occurrences inside `--`-comments or string literals before reaching
 *  the real declaration. The caller classifies each candidate via the
 *  LSP and stops on the first identifier-like hit. */
function findOccurrences(text: string, oldName: string): LspPosition[] {
  const esc = escapeRegExp(oldName)
  const positions: LspPosition[] = []
  // Backticked form first — handles names with spaces or punctuation.
  const backtickRe = new RegExp('`' + esc + '`', 'g')
  for (let m = backtickRe.exec(text); m !== null; m = backtickRe.exec(text)) {
    // Step past the opening backtick AND one char into the name so the
    // cursor isn't on the boundary of either the backtick token or the
    // identifier's first character.
    const offset = oldName.length >= 2 ? 2 : 1
    positions.push(positionAt(text, m.index + offset))
  }
  // Bare identifier — require word boundaries so a request to rename
  // `foo` doesn't accidentally start from `foobar`.
  if (BARE_IDENT_RE.test(oldName)) {
    const wordRe = new RegExp('\\b' + esc + '\\b', 'g')
    for (let m = wordRe.exec(text); m !== null; m = wordRe.exec(text)) {
      // +1 puts us one column inside the identifier; for a single-char
      // name fall back to the start (no interior to point at).
      const offset = oldName.length >= 2 ? 1 : 0
      positions.push(positionAt(text, m.index + offset))
    }
  }
  return positions
}

/** Decide the literal replacement for a single occurrence: preserve
 *  backtick quoting from the source, and add backticks when the new
 *  name itself can't survive bare (e.g. contains a space). */
function renderReplacement(
  existing: string,
  newName: string,
  newNameNeedsBackticks: boolean
): string {
  const wrapped = existing.startsWith('`') && existing.endsWith('`')
  if (wrapped || newNameNeedsBackticks) return '`' + newName + '`'
  return newName
}

async function l4Rename(
  ctx: RefactorContext,
  args: L4RenameArgs
): Promise<string> {
  if (!args || typeof args !== 'object') {
    throw new Error('l4__refactor (rename): arguments object is required')
  }
  // Validate both names against L4's lexical rules up front: rejects
  // annotations (@ref, @desc, @export), directives (#EVAL, #CHECK),
  // line comments (--…), path/URL-shaped inputs, reserved keywords,
  // and stray backticks — each with a specific error message instead
  // of a downstream "identifier not found".
  const oldName = validateRefactorName(args.oldName, 'oldName')
  const newName = validateRefactorName(args.newName, 'newName')
  if (oldName === newName) {
    return `l4__refactor (rename): oldName equals newName ("${oldName}") — nothing to do.`
  }
  const newNameNeedsBackticks = !BARE_IDENT_RE.test(newName)

  const { workspace, l4 } = ctx
  const uri = resolveFileUri(workspace, args.path)
  if (!uri) {
    throw new Error(`l4__refactor (rename): cannot resolve path: ${args.path}`)
  }
  const displayPath = workspace.relativePath(uri)
  let text: string
  try {
    text = (await workspace.readDocument(uri)).text
  } catch (err) {
    throw new Error(
      `l4__refactor (rename): cannot open ${displayPath}: ${err instanceof Error ? err.message : String(err)}`
    )
  }

  // The textual scan happily matches occurrences inside `--`-comments
  // and string literals before reaching the real declaration. Walk
  // every candidate and ask the LSP's semantic-tokens classifier per
  // position; keep the first one that classifies as an identifier (or
  // that the LSP can't classify yet — null falls through, so the
  // references provider still gets a shot when semantic tokens aren't
  // warm). Only error out when no candidate is identifier-shaped.
  const candidates = findOccurrences(text, oldName)
  if (candidates.length === 0) {
    throw new Error(
      `l4__refactor (rename): identifier "${oldName}" not found in ${displayPath}. Pass the identifier exactly as it appears in the source (without backticks).`
    )
  }
  let position: LspPosition | null = null
  let lastNonIdentLabel: string | null = null
  for (const candidate of candidates) {
    const tokenType = await classifyAnchorToken(l4, uri, candidate)
    if (tokenType === null || IDENTIFIER_TOKEN_TYPES.has(tokenType)) {
      position = candidate
      break
    }
    lastNonIdentLabel = NON_IDENTIFIER_LABELS[tokenType] ?? `'${tokenType}'`
  }
  if (!position) {
    const label = lastNonIdentLabel ?? 'not an identifier'
    throw new Error(
      `l4__refactor (rename): every textual occurrence of "${oldName}" in ${displayPath} is ${label} — no identifier-typed occurrence to anchor on. Pass the name of a value, type, or function defined in the file.`
    )
  }

  // The references provider is jl4-lsp's textDocument/references
  // handler, which already unions matches across all
  // reverse-dependency modules — so a rename anchored on a definition
  // in `domain.l4` finds occurrences in every file that `IMPORT`s it.
  let locations: Awaited<ReturnType<L4Language['findReferences']>>
  try {
    locations = await l4.findReferences(uri, position)
  } catch (err) {
    throw new Error(
      `l4__refactor (rename): references lookup failed: ${err instanceof Error ? err.message : String(err)}`
    )
  }
  if (!locations || locations.length === 0) {
    throw new Error(
      `l4__refactor (rename): no references for "${oldName}" — make sure the file type-checks (the references provider runs on the resolved module). Use l4__evaluate to check.`
    )
  }

  // Group locations by URI so we can sort each file's edits last-first
  // (offsets stay valid as we mutate from the bottom up) and so we
  // read each target doc exactly once for the existing-text lookup.
  const byUri = new Map<string, typeof locations>()
  for (const loc of locations) {
    let list = byUri.get(loc.uri)
    if (!list) {
      list = []
      byUri.set(loc.uri, list)
    }
    list.push(loc)
  }

  const edits: WorkspaceTextEdit[] = []
  const filesEdited: string[] = []

  for (const [targetUri, locs] of byUri) {
    const targetText = (await workspace.readDocument(targetUri)).text
    // Sort descending by (line, character) so later edits don't shift
    // earlier ones inside the same file before they apply.
    locs.sort((a, b) => {
      const lineDiff = b.range.start.line - a.range.start.line
      if (lineDiff !== 0) return lineDiff
      return b.range.start.character - a.range.start.character
    })
    let fileEdits = 0
    for (const loc of locs) {
      const existing = textInRange(targetText, loc.range)
      // Defensive: the references provider should only return ranges
      // whose text matches `oldName` (with or without backticks), but
      // skip anything that doesn't — better to under-rename than to
      // clobber an unrelated token if the LSP ever returns a stale
      // range.
      const trimmed = existing.replace(/^`+|`+$/g, '')
      if (trimmed !== oldName) continue
      edits.push({
        uri: targetUri,
        startOffset: offsetAt(targetText, loc.range.start),
        endOffset: offsetAt(targetText, loc.range.end),
        newText: renderReplacement(existing, newName, newNameNeedsBackticks),
      })
      fileEdits++
    }
    if (fileEdits > 0) filesEdited.push(workspace.relativePath(targetUri))
  }
  const totalEdits = edits.length

  if (totalEdits === 0) {
    throw new Error(
      `l4__refactor (rename): references provider returned ${locations.length} location(s) but none matched "${oldName}" verbatim — refusing to apply edits.`
    )
  }
  // One change across every file, persisted, so subsequent
  // type-checks and disk-based readers (fs__read_file, other
  // extensions) see the new names immediately.
  try {
    await workspace.applyEdits(edits)
  } catch (err) {
    throw new Error(
      `l4__refactor (rename): the workspace refused to apply the edits (file may be read-only): ${err instanceof Error ? err.message : String(err)}`
    )
  }

  filesEdited.sort()
  const fileSummary = filesEdited.join(', ')
  // L4's references provider walks the anchor file's DEPENDENCIES
  // (imports) and its reverse-deps (importers), not sibling importers.
  // If the rename only touched the anchor file, hint that anchoring on
  // the DEFINING file would cover all importers.
  const hint =
    filesEdited.length === 1
      ? ` If "${oldName}" is also used in files that don't import "${filesEdited[0]}", re-run with \`path\` set to the file where "${oldName}" is DEFINED — the rename then propagates to every importer.`
      : ''
  return `Renamed "${oldName}" → "${newName}" — ${totalEdits} occurrence${totalEdits === 1 ? '' : 's'} across ${filesEdited.length} file${filesEdited.length === 1 ? '' : 's'} (${fileSummary}).${hint}`
}
