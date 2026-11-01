import * as path from 'node:path'
import type {
  CheckedDiagnostics,
  L4Language,
  ResolvedPath,
  Workspace,
  WorkspaceDirEntry,
} from '../ports.js'
import { positionAt } from '../text-positions.js'
import {
  describeFileState,
  formatChecked,
  formatL4Diagnostics,
  isWorse,
  l4FileState,
  type DiagnosticsLimit,
  type L4FileState,
} from './lsp.js'
import {
  renderDirectiveResults,
  type DirectiveSnapshotStore,
} from './directive-snapshot.js'

/** What the fs tools need from the host. */
export interface FsToolContext {
  workspace: Workspace
  l4: L4Language
  /** `fs__edit_file`'s private directive snapshot store. Keeping this
   *  separate from `l4__evaluate`'s store means an edit can report
   *  "what changed since the last edit" independently from "what
   *  changed since the last l4__evaluate call". Per conversation: see
   *  {@link BuiltinTools}. */
  editStore: DirectiveSnapshotStore
  /** Whether a failed edit may quote the file back. Unset means no: an
   *  edit must not become a way around a user who restricted `fs.read`. */
  mayQuoteFile?: boolean
}

/** How long to wait (ms) after an edit for the LSP to push fresh
 *  directive results before computing the diff. The LSP normally
 *  finishes a small file in under 100ms; we give it a bit more
 *  headroom but bail rather than block the tool turn. */
const DIRECTIVE_PUSH_WAIT_MS = 1000

/**
 * Built-in filesystem tools. All paths are workspace-relative; absolute
 * paths outside the workspace are rejected by {@link Workspace.resolvePath}.
 * Each tool returns a string (tool result). Errors throw — the
 * dispatcher wraps them into a tool-result `{ error: ... }`.
 */

export interface FsReadArgs {
  path: string
  /** 1-based inclusive start line in the target's text output.
   *  For files this is a source-line number; for directories it's
   *  the position in the sorted entry listing (1 = first entry).
   *  Default 1. Applied after `search_keywords` when both are set. */
  startLine?: number
  /** 1-based inclusive end line. Default: read to the end of the
   *  output, capped at `startLine + 499` (500-line ceiling). Naming one
   *  also raises the character cap, see EXPLICIT_RANGE_CHAR_LIMIT. */
  endLine?: number
  /** Optional keyword filter. One or more keywords separated by
   *  whitespace; a line is a hit if it matches ANY of them (OR).
   *  Each keyword is parsed as a case-insensitive regex, falling
   *  back to a literal substring when the regex doesn't compile.
   *  For files, matching lines are returned with 2 lines of
   *  surrounding context. For directories, the tree is walked
   *  recursively (skipping `.git`, `node_modules`, `.DS_Store`)
   *  and both entry *names* and file *contents* are searched — name
   *  hits come first as `<relative-path>`, then contents as
   *  `<relative-path>:<lineno>: <text>`, so the model can jump to
   *  the file with a follow-up `fs__read_file`. Use this to find
   *  a file, a symbol or a string anywhere under the workspace. */
  search_keywords?: string
}

/** Hard caps per response. Picked so a single call surfaces enough
 *  to read a typical function or section without letting a 30 kLOC
 *  file blow up the agent's context window. The model pages via
 *  `startLine`/`endLine` when a target is bigger. Applied uniformly
 *  to files and directories. */
const LINE_LIMIT = 500
const CHAR_LIMIT = 4000
/** Cap when the model names an `endLine`. Most capped reads never go on to
 *  the next page, so raising the default would grow those for nothing; a
 *  model that does want the rest can ask for it in one call. */
const EXPLICIT_RANGE_CHAR_LIMIT = 24_000
const PATTERN_CONTEXT_LINES = 2

/** Diagnostics appended to an edit stay in the conversation for every later
 *  round, so they're capped. `l4__evaluate` still returns the full list. */
const EDIT_DIAGNOSTICS_LIMIT: DiagnosticsLimit = {
  maxEntries: 8,
  maxChars: 1500,
}

function isL4Path(fsPath: string): boolean {
  return fsPath.toLowerCase().endsWith('.l4')
}

/**
 * For `.l4` files, append what the language server says about the file now,
 * so the model doesn't need a separate round-trip to confirm it compiles.
 * Runs after every write. Failures are swallowed: the primary tool result
 * is more important than the annotation.
 *
 * Errors gate everything: they come back as a capped diagnostics block,
 * since no directive-level diff means anything until they're fixed. A clean
 * compile gets a compact directive diff, plus any warnings. Warnings are
 * the only signal for code that compiles but likely isn't what was meant.
 */
async function reportL4File(
  ctx: FsToolContext,
  r: ResolvedPath,
  body: string,
  known?: CheckedDiagnostics
): Promise<{ text: string; state?: L4FileState }> {
  if (!isL4Path(r.fsPath)) return { text: body }
  try {
    const checked = known ?? (await ctx.l4.getCheckedDiagnostics(r.uri))
    const state = l4FileState(checked)
    if (checked.pending || state.errors > 0) {
      return {
        text: `${body}\n${formatChecked(checked, EDIT_DIAGNOSTICS_LIMIT)}`,
        state,
      }
    }
    const diffBlock = await computeEditDiff(ctx, r, checked)
    const warnings = checked.diagnostics.filter((d) => d.severity === 'warning')
    const warningBlock =
      warnings.length > 0
        ? `\n${formatL4Diagnostics(warnings, EDIT_DIAGNOSTICS_LIMIT)}`
        : ''
    return { text: `${body}\n${diffBlock}${warningBlock}`, state }
  } catch {
    return { text: body }
  }
}

/** Build the directive-diff tail attached to a successful edit. Uses
 *  the edit-tool's private snapshot store (NOT l4__evaluate's) so the
 *  two tools' "what changed since I last spoke" views stay
 *  independent. Always renders in `changed` mode — the edit's purpose
 *  is "did this write move any directive values?", which the full
 *  catalog would drown. When the server confirmed the check, directive
 *  results have already arrived; otherwise wait briefly for its push and
 *  fall back to whatever's in the cache on timeout. */
async function computeEditDiff(
  ctx: FsToolContext,
  r: ResolvedPath,
  checked: CheckedDiagnostics
): Promise<string> {
  const uriStr = r.uri
  if (!checked.confirmed) {
    await ctx.l4.awaitDirectiveResults(uriStr, DIRECTIVE_PUSH_WAIT_MS)
  }
  const results = ctx.l4.getDirectiveResults(uriStr) ?? []
  return renderDirectiveResults({
    results,
    store: ctx.editStore,
    uri: uriStr,
    mode: 'changed',
  })
}

/** Skip these at any depth to keep listings useful — they're almost
 *  always noise the model doesn't want to reason about. */
const DIR_IGNORES = new Set(['.git', 'node_modules', '.DS_Store'])
/** What a folder search also passes over: build output, whose names and
 *  contents would bury the sources. A listing still shows these, and a
 *  search that starts inside one still works. */
const SEARCH_IGNORES = new Set([
  '.next',
  '.svelte-kit',
  '.turbo',
  '.venv',
  '__pycache__',
  'dist',
  'dist-newstyle',
])
/** Most of a line a folder search shows. The reply is capped in total, so
 *  one minified line would otherwise be all of it. */
const MAX_SEARCH_LINE_CHARS = 240
/** Beyond this a directory search goes by a file's name alone: what's
 *  this large is build output, and reading it is nearly all of what such
 *  a search costs. */
const MAX_SEARCHED_FILE_SIZE = 1_000_000
/** Entries {@link pathsNamed} looks at, and the paths it reports. */
const NAME_WALK_LIMIT = 20_000
const MAX_PATHS_NAMED = 5

/**
 * Read a file (one source line per output line) or list a directory
 * (one entry per output line, `name/` for subdirs, `name` for files,
 * dirs sorted first). Same shape for both so the model learns one
 * rule. Pagination via `startLine`/`endLine`, search via
 * `search_keywords`.
 *
 * Response: a compact header line describing what came back, then
 * the selected lines. Header examples:
 *   [<path> 1-40/40]                                   — full file/dir
 *   [<path> 1-500/2489]                                — paginated (more after line 500)
 *   [<path> keywords="..." matches=3 chunks=2/2]       — file grep
 *   [<path> keywords="..." matches=0]                  — no hits
 *   [<dir>/ keywords="..." names=1 matches=12 files=3] — recursive dir grep
 *     (` over1MB=N` when N files were too large to search inside)
 *
 * For file grep, matching lines are prefixed `>>>` and context
 * lines `   ` so the model can distinguish hits from surroundings;
 * non-contiguous chunks are separated by `---`. For directory grep
 * the tree is walked recursively (skipping `DIR_IGNORES` and
 * `SEARCH_IGNORES`): entries whose name matches are emitted as
 * `<relative-path>` rows (`/` on the end for a folder), then lines
 * that match as `<relative-path>:<lineno>: <text>` rows.
 */
export async function fsReadFile(
  ctx: Pick<FsToolContext, 'workspace'>,
  args: FsReadArgs
): Promise<string> {
  const r = ctx.workspace.resolvePath(args.path)
  const stat = await ctx.workspace.stat(r.fsPath)
  if (!stat) {
    const elsewhere = await pathsNamed(ctx.workspace, path.basename(r.fsPath))
    throw new Error(
      `No such file or directory: ${r.relative}` +
        (elsewhere.length > 0
          ? `. That name is at: ${elsewhere.join(', ')}`
          : '')
    )
  }

  const isDir = stat.isDirectory
  const hasKeywords =
    typeof args.search_keywords === 'string' &&
    args.search_keywords.trim().length > 0

  // Directory + keywords → recursive content grep across the whole
  // subtree. Different code path because we never want to materialise
  // the entire subtree as a flat `lines[]` (would defeat the cap and
  // burn memory on a big repo) — `grepDirRecursive` walks
  // file-by-file and keeps only what fits the cap.
  if (isDir && hasKeywords) {
    return grepDirRecursive(ctx.workspace, r, args.search_keywords!)
  }

  // Materialise the target as a list of lines regardless of kind.
  // Files: one source line per entry. Directories: one entry per
  // entry, with a trailing `/` for subdirs. Diagnostics are NOT
  // auto-appended for .l4 reads any more — earlier versions did
  // this and trained the model to over-read; use l4__evaluate
  // explicitly.
  let lines: string[]
  if (isDir) {
    const raw = await ctx.workspace.readDirectory(r.fsPath)
    const filtered = raw.filter((e) => !DIR_IGNORES.has(e.name))
    filtered.sort((a, b) => {
      const rank = (e: typeof a): number => (e.isDirectory ? 0 : 1)
      const d = rank(a) - rank(b)
      return d !== 0 ? d : a.name.localeCompare(b.name)
    })
    lines = filtered.map((e) => (e.isDirectory ? `${e.name}/` : e.name))
  } else {
    const buf = await ctx.workspace.readFile(r.fsPath)
    lines = buf.replace(/\r\n/g, '\n').split('\n')
  }

  // Keywords (grep mode) take precedence — once keywords are set
  // the output is keyword-focused and startLine/endLine narrow
  // WITHIN that focus.
  if (hasKeywords) {
    return grepLines(
      r,
      lines,
      args.search_keywords!,
      isDir,
      args.startLine,
      args.endLine
    )
  }
  return sliceLines(r, lines, args.startLine, args.endLine)
}

/**
 * Cap a line array to LINE_LIMIT / CHAR_LIMIT, optionally starting
 * at a specific 1-based line, and render with a compact header.
 * Used for the no-pattern path of fsReadFile (files AND directories).
 */
function sliceLines(
  r: ResolvedPath,
  lines: string[],
  startLineRaw: number | undefined,
  endLineRaw: number | undefined
): string {
  const total = lines.length
  const startLine = clampInt(startLineRaw ?? 1, 1, Math.max(1, total))
  const requestedEnd =
    endLineRaw !== undefined ? clampInt(endLineRaw, startLine, total) : total
  // Hard line cap even if the caller asks for more — prevents an
  // endLine: 99999 from smuggling the whole target back.
  const capByLines = Math.min(requestedEnd, startLine + LINE_LIMIT - 1, total)
  const charLimit =
    endLineRaw !== undefined ? EXPLICIT_RANGE_CHAR_LIMIT : CHAR_LIMIT
  let endLine = capByLines
  let body = lines.slice(startLine - 1, endLine).join('\n')
  while (body.length > charLimit && endLine > startLine) {
    endLine--
    body = lines.slice(startLine - 1, endLine).join('\n')
  }
  // Edge case: even a single line exceeds the char cap. Clip
  // mid-line; the model can retry with a narrower window if needed.
  if (body.length > charLimit) {
    body = body.slice(0, charLimit)
  }
  // Header is uniform: `[<path> <start>-<end>/<total>]`. The model
  // can compute the next call's `startLine` from `<end>` directly, so
  // a separate "next startLine=…" hint is wasted tokens.
  return `[${r.relative} ${startLine}-${endLine}/${total}]\n${body}`
}

/**
 * Build a line matcher from a whitespace-separated keyword string.
 * Splits on runs of whitespace, compiles each keyword as a
 * case-insensitive regex (literal-substring fallback when it doesn't
 * compile), and returns a predicate that's true when a line matches
 * ANY keyword (OR semantics). An empty/blank string matches nothing.
 */
function buildKeywordMatcher(raw: string): (line: string) => boolean {
  const keywords = raw.trim().split(/\s+/).filter(Boolean)
  if (keywords.length === 0) return () => false
  const tests = keywords.map((kw): ((line: string) => boolean) => {
    try {
      const re = new RegExp(kw, 'i')
      return (line) => re.test(line)
    } catch {
      const needle = kw.toLowerCase()
      return (line) => line.toLowerCase().includes(needle)
    }
  })
  return (line) => tests.some((t) => t(line))
}

/**
 * Grep mode: filter `lines` down to those matching `keywords`,
 * then apply the same caps as `sliceLines`. For files, each match
 * carries PATTERN_CONTEXT_LINES of surrounding context (overlapping
 * chunks merged); for directories, matching entries are returned
 * verbatim (context is meaningless for a listing).
 *
 * When `startLine`/`endLine` are also set, they further narrow the
 * keyword match window to file lines inside that range — lets
 * the model search within a specific section.
 *
 * Output:
 *   [<path> keywords="…" matches=N chunks=K/total]
 *   >>> 42: matching line
 *       43: context
 *   ---
 *       86: context
 *   >>> 87: another match
 */
function grepLines(
  r: ResolvedPath,
  lines: string[],
  keywordsRaw: string,
  isDir: boolean,
  startLineRaw: number | undefined,
  endLineRaw: number | undefined
): string {
  const total = lines.length
  const rangeStart = clampInt(startLineRaw ?? 1, 1, Math.max(1, total)) - 1
  const rangeEnd =
    endLineRaw !== undefined
      ? clampInt(endLineRaw, rangeStart + 1, total)
      : total

  const matcher = buildKeywordMatcher(keywordsRaw)

  const matchIdx: number[] = []
  for (let i = rangeStart; i < rangeEnd; i++) {
    if (matcher(lines[i]!)) matchIdx.push(i)
  }
  const keywordsLabel = JSON.stringify(keywordsRaw)
  if (matchIdx.length === 0) {
    return `[${r.relative} keywords=${keywordsLabel} matches=0]`
  }

  // Directories have no "context" — just return the matching entries
  // as lines, applying the char/line caps.
  if (isDir) {
    const matchedLines = matchIdx.map((i) => `${i + 1}: ${lines[i]!}`)
    let body = matchedLines.slice(0, LINE_LIMIT).join('\n')
    while (body.length > CHAR_LIMIT && body.includes('\n')) {
      body = body.slice(0, body.lastIndexOf('\n'))
    }
    const shown = body ? body.split('\n').length : 0
    const truncated = shown < matchIdx.length
    const header =
      `[${r.relative} keywords=${keywordsLabel} matches=${matchIdx.length}` +
      (truncated ? `, shown=${shown}/${matchIdx.length}]` : `]`)
    return `${header}\n${body}`
  }

  // Files: expand each match to a [start, end] context window and
  // merge overlapping / adjacent windows so consecutive near-hits
  // produce one chunk instead of N.
  type Chunk = { start: number; end: number; hits: Set<number> }
  const chunks: Chunk[] = []
  for (const i of matchIdx) {
    const start = Math.max(0, i - PATTERN_CONTEXT_LINES)
    const end = Math.min(total - 1, i + PATTERN_CONTEXT_LINES)
    const tail = chunks[chunks.length - 1]
    if (tail && start <= tail.end + 1) {
      tail.end = Math.max(tail.end, end)
      tail.hits.add(i)
    } else {
      chunks.push({ start, end, hits: new Set([i]) })
    }
  }

  const rendered: string[] = []
  let renderedLineCount = 0
  let renderedCharCount = 0
  let chunksShown = 0
  let truncated = false
  for (const chunk of chunks) {
    const chunkLines: string[] = []
    for (let i = chunk.start; i <= chunk.end; i++) {
      const prefix = chunk.hits.has(i) ? '>>>' : '   '
      const line = `${prefix} ${i + 1}: ${lines[i]!}`
      const projectedLines = renderedLineCount + chunkLines.length + 1
      const projectedChars =
        renderedCharCount +
        chunkLines.reduce((a, l) => a + l.length + 1, 0) +
        line.length +
        1
      if (projectedLines > LINE_LIMIT || projectedChars > CHAR_LIMIT) {
        truncated = true
        break
      }
      chunkLines.push(line)
    }
    if (chunkLines.length === 0) {
      truncated = true
      break
    }
    rendered.push(chunkLines.join('\n'))
    renderedLineCount += chunkLines.length
    renderedCharCount += chunkLines.reduce((a, l) => a + l.length + 1, 0)
    chunksShown++
    if (truncated) break
  }

  const header =
    `[${r.relative} keywords=${keywordsLabel} matches=${matchIdx.length} ` +
    `chunks=${chunksShown}/${chunks.length}` +
    (truncated ? `, truncated]` : `]`)
  return `${header}\n${rendered.join('\n---\n')}`
}

function clampInt(n: number, lo: number, hi: number): number {
  if (!Number.isFinite(n)) return lo
  const rounded = Math.floor(n)
  if (rounded < lo) return lo
  if (rounded > hi) return hi
  return rounded
}

/**
 * Recursive content grep under a directory. Walks the tree
 * (depth-first, deterministic order), reads every file as utf-8 and
 * emits one row per matching line:
 *
 *   <relative-path>:<lineno>: <text>
 *
 * Skips `DIR_IGNORES` and `SEARCH_IGNORES` at every level and silently
 * skips files that fail to decode (binary blobs, broken symlinks). No surrounding
 * context — across many files the model wants `path:line` to navigate
 * to with a follow-up `fs__read_file`, not a chunk of code.
 *
 * Caps to LINE_LIMIT rows / CHAR_LIMIT chars, signalled in the header
 * as `shown=X/total`.
 */
async function grepDirRecursive(
  workspace: Workspace,
  r: ResolvedPath,
  keywordsRaw: string
): Promise<string> {
  const matcher = buildKeywordMatcher(keywordsRaw)

  const names: string[] = []
  const rows: string[] = []
  const filesWithMatches = new Set<string>()
  let totalNames = 0
  let totalMatches = 0
  let tooLarge = 0
  let renderedChars = 0
  let truncated = false

  const roots = r.relative === '.' ? workspaceRoots(workspace) : [r]
  for await (const entry of walkTree(workspace, roots)) {
    const rel = entry.rel
    if (matcher(entry.name)) {
      totalNames++
      if (names.length < LINE_LIMIT) {
        names.push(entry.isDirectory ? `${rel}/` : rel)
      }
    }
    if (!entry.isFile) continue
    let buf: string
    try {
      const size = (await workspace.stat(entry.full))?.size ?? 0
      if (size > MAX_SEARCHED_FILE_SIZE) {
        tooLarge++
        continue
      }
      buf = await workspace.readFile(entry.full)
    } catch {
      continue
    }
    const fileLines = buf.replace(/\r\n/g, '\n').split('\n')
    for (let i = 0; i < fileLines.length; i++) {
      if (!matcher(fileLines[i]!)) continue
      totalMatches++
      filesWithMatches.add(rel)
      if (truncated) continue
      const line = fileLines[i]!
      const shownLine =
        line.length > MAX_SEARCH_LINE_CHARS
          ? `${line.slice(0, MAX_SEARCH_LINE_CHARS)}…`
          : line
      const row = `${rel}:${i + 1}: ${shownLine}`
      if (
        rows.length + 1 > LINE_LIMIT ||
        renderedChars + row.length + 1 > CHAR_LIMIT
      ) {
        truncated = true
        continue
      }
      rows.push(row)
      renderedChars += row.length + 1
    }
  }

  // Name hits first: they're short, and likely what a search that has
  // them was after, so they aren't pushed out by a long list of lines.
  const shown: string[] = []
  let shownChars = 0
  for (const row of [...names, ...rows]) {
    if (
      shown.length + 1 > LINE_LIMIT ||
      shownChars + row.length + 1 > CHAR_LIMIT
    ) {
      break
    }
    shown.push(row)
    shownChars += row.length + 1
  }

  const total = totalNames + totalMatches
  const header =
    `[${r.relative}/ keywords=${JSON.stringify(keywordsRaw)} ` +
    `names=${totalNames} matches=${totalMatches}` +
    (totalMatches > 0 ? ` files=${filesWithMatches.size}` : '') +
    (tooLarge > 0 ? ` over1MB=${tooLarge}` : '') +
    (shown.length < total ? `, shown=${shown.length}/${total}]` : `]`)
  return [header, ...shown].join('\n')
}

/** What `.` covers: every folder the workspace has loaded. */
function workspaceRoots(workspace: Workspace): ResolvedPath[] {
  return workspace.searchRoots?.() ?? [workspace.resolvePath('.')]
}

/**
 * Every entry under `roots` a search looks at: a folder's entries,
 * directories first and each kind alphabetical, then what's in its
 * subfolders. A folder that can't be read is passed over. `rel` is relative
 * to the workspace, not to the root walked, so it can be passed straight
 * back to a tool.
 */
async function* walkTree(
  workspace: Workspace,
  roots: ResolvedPath[]
): AsyncGenerator<WorkspaceDirEntry & { full: string; rel: string }> {
  for (const root of roots) {
    // DFS via an explicit stack, so a caller can stop part way.
    const stack: string[] = [root.fsPath]
    while (stack.length > 0) {
      const dir = stack.pop()!
      let entries: WorkspaceDirEntry[]
      try {
        entries = await workspace.readDirectory(dir)
      } catch {
        continue
      }
      entries.sort((a, b) => {
        const rank = (e: typeof a): number => (e.isDirectory ? 0 : 1)
        const d = rank(a) - rank(b)
        return d !== 0 ? d : a.name.localeCompare(b.name)
      })
      // Push directories in reverse so the stack pops them in
      // alphabetical order, matching the per-directory sort above.
      const subdirs: string[] = []
      for (const e of entries) {
        if (DIR_IGNORES.has(e.name) || SEARCH_IGNORES.has(e.name)) continue
        const full = path.join(dir, e.name)
        if (workspace.hiddenFromSearch?.(full)) continue
        if (e.isDirectory) subdirs.push(full)
        const rel = path.join(root.relative, path.relative(root.fsPath, full))
        yield { ...e, full, rel }
      }
      for (let i = subdirs.length - 1; i >= 0; i--) stack.push(subdirs[i]!)
    }
  }
}

/** Where else the workspace has an entry called `name`, for the error
 *  on a path that doesn't exist: a moved file is usually still around.
 *  Names only, and it gives up after {@link NAME_WALK_LIMIT} entries,
 *  so a miss stays cheap in a big repo. */
async function pathsNamed(
  workspace: Workspace,
  name: string
): Promise<string[]> {
  const wanted = name.toLowerCase()
  const found: string[] = []
  let seen = 0
  for await (const entry of walkTree(workspace, workspaceRoots(workspace))) {
    if (++seen > NAME_WALK_LIMIT) break
    if (entry.name.toLowerCase() !== wanted) continue
    found.push(entry.rel)
    if (found.length === MAX_PATHS_NAMED) break
  }
  return found
}

export interface FsCreateArgs {
  path: string
  /** Initial text. Without it the file gets a seed line to edit. */
  content?: string
}

/** Highest `-N` a created file may get before create gives up. A model
 *  stuck in a loop gets no other brake, since each copy looks like success. */
export const MAX_NAME_SUFFIX = 20

/** What a create did. `uri` and `relative` name the file that holds the
 *  content, which isn't always the requested path. */
export interface FsCreateResult {
  output: string
  relative: string
  uri: string
  state?: L4FileState
}

/**
 * Sentinel content for newly-created files. Acts as the unique anchor
 * for the first follow-up `fs__edit_file` call — the model replaces
 * this exact line with real content. Required because `fs__edit_file`
 * needs a non-empty `old` snippet to anchor on; without the seed a
 * brand-new (empty) file would have nothing to find.
 */
export const FS_CREATE_FILE_SEED = '// new file in progress ...\n'

/**
 * Placeholder copy dropped into the body of a freshly-created HTML
 * file. Doubles as the unique anchor the first follow-up
 * `fs__edit_file` call replaces with real markup.
 */
export const FS_CREATE_HTML_SEED = `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>New document</title>
    <style>
      body {
        background-color: white;
        font-family: serif;
        font-size: 1rem;
        color: black;
        margin: 2rem;
      }
    </style>
  </head>
  <body>New document in progress ...</body>
</html>
`

/** True for files we render in a browser preview rather than opening
 *  as a source text tab. */
export function isHtmlPath(fsPath: string): boolean {
  const ext = path.extname(fsPath).toLowerCase()
  return ext === '.html' || ext === '.htm'
}

/** `foo.l4` as `foo-3.l4`. The counter always goes on the requested name
 *  and never bumps a number already in it: `section-33.l4` becoming
 *  `section-34.l4` would read as a different section. */
function numberedPath(fsPath: string, n: number): string {
  const ext = path.extname(fsPath)
  const stem = path.basename(fsPath, ext)
  return path.join(path.dirname(fsPath), `${stem}-${n}${ext}`)
}

async function hasContent(
  ctx: Pick<FsToolContext, 'workspace'>,
  target: ResolvedPath,
  content: string
): Promise<boolean> {
  try {
    const { text } = await ctx.workspace.readDocument(target.uri)
    return text.replace(/\r\n/g, '\n') === content.replace(/\r\n/g, '\n')
  } catch {
    return false
  }
}

/**
 * Create a file. With `content` the text lands in one call: by then it has
 * been generated and paid for, so a name clash doesn't fail. The file goes
 * to the first free `-N` name instead and the result says so plainly. A
 * clash with identical text creates nothing, so a retried turn doesn't pile
 * up copies.
 *
 * Without `content` the file gets FS_CREATE_FILE_SEED for the model to fill
 * via `fs__edit_file`, and a name clash is still an error: nothing is lost,
 * and the model probably meant to edit what's there.
 */
export async function fsCreateFileDetailed(
  ctx: FsToolContext,
  args: FsCreateArgs
): Promise<FsCreateResult> {
  const r = ctx.workspace.resolvePath(args.path)
  if (args.content === undefined) {
    if (await ctx.workspace.stat(r.fsPath)) {
      throw new Error(`File already exists: ${r.relative}`)
    }
    // HTML files get a full (plain-white) document skeleton so a browser
    // preview renders a real page from the start; everything else gets
    // the one-line code seed. The workspace creates parent directories,
    // routes the write through the editor where there is one (so the
    // LSP sees the new file via didOpen and l4__evaluate isn't stale),
    // and may reveal it (VS Code opens a tab, or the HTML preview).
    const isHtml = isHtmlPath(r.fsPath)
    const seed = isHtml ? FS_CREATE_HTML_SEED : FS_CREATE_FILE_SEED
    await ctx.workspace.createFile(r, seed)
    // Skip the diagnostics tail — a freshly-created file has no real
    // content to type-check, and the Edit tool the model uses next will
    // run diagnostics naturally.
    const anchor = isHtml
      ? '\n```html\n' + FS_CREATE_HTML_SEED + '\n```'
      : '"' + FS_CREATE_FILE_SEED.trimEnd() + '"'
    return {
      output: `Created ${r.relative} - seeded with ${anchor}`,
      relative: r.relative,
      uri: r.uri,
    }
  }
  if (typeof args.content !== 'string') {
    throw new Error("fs__create_file: 'content' must be a string.")
  }
  if (args.content.includes('\u0000')) {
    throw new Error("fs__create_file: 'content' must be text.")
  }
  for (let n = 0; n <= MAX_NAME_SUFFIX; n++) {
    const target =
      n === 0 ? r : ctx.workspace.resolvePath(numberedPath(r.fsPath, n))
    const taken = await ctx.workspace.stat(target.fsPath)
    if (taken) {
      if (taken.isFile && (await hasContent(ctx, target, args.content))) {
        return {
          output: `No change: ${target.relative} already has this exact content.`,
          relative: target.relative,
          uri: target.uri,
        }
      }
      continue
    }
    try {
      await ctx.workspace.createFile(target, args.content)
    } catch (err) {
      // Lost a race for the name: try the next one.
      if (await ctx.workspace.stat(target.fsPath)) continue
      throw err
    }
    const lines = args.content.split('\n').length
    const body =
      n === 0
        ? `Created ${target.relative} (${lines} lines)`
        : `Created ${target.relative} (${lines} lines). ${r.relative} already existed and was not changed, and nothing refers to the new file yet. If this was meant to replace it, call fs__copy_file with from "${target.relative}", to "${r.relative}", overwrite and deleteSource instead of writing it again.`
    const { text, state } = await reportL4File(ctx, target, body)
    return {
      output: text,
      relative: target.relative,
      uri: target.uri,
      ...(state ? { state } : {}),
    }
  }
  throw new Error(
    `fs__create_file: ${r.relative} and its numbered copies up to -${MAX_NAME_SUFFIX} all exist. Delete the ones you no longer need, or pick another name.`
  )
}

export async function fsCreateFile(
  ctx: FsToolContext,
  args: FsCreateArgs
): Promise<string> {
  return (await fsCreateFileDetailed(ctx, args)).output
}

/** One replacement in a file. */
export interface FsEditItem {
  /** Exact text to replace. When `startLine` is omitted (or 0),
   *  must appear EXACTLY ONCE in the file. When `startLine` is set,
   *  the first occurrence strictly after that line is taken — no
   *  global uniqueness required. */
  old: string
  /** Replacement text. */
  new: string
  /** Optional 1-based line number to anchor the search. When set,
   *  the edit targets the first occurrence of `old` that starts on
   *  a line STRICTLY AFTER `startLine` (so earlier identical
   *  snippets are skipped). Default 0 = search the whole file.
   *  Leave generous slack (~5-10 lines) below the expected line —
   *  multi-round turns shift line numbers as prior edits land. */
  startLine?: number
}

export interface FsEditArgs extends Partial<FsEditItem> {
  path: string
  /** Several changes to this file, applied and checked one at a time. */
  edits?: FsEditItem[]
}

/** Most edits to one file in one model response. Models rarely write L4
 *  right the first time, and a mistake compounds under whatever follows. */
export const MAX_EDITS_PER_FILE = 5

/** Progress through one model response's edits to one file. */
export interface EditSequence {
  applied: number
  /** State before the next edit. `null` when it couldn't be determined;
   *  unset until the first edit reads it. */
  state?: L4FileState | null
  /** Why no further edit to this file may run in this response. */
  stopped?: string
}

export interface FsEditResult {
  output: string
  /** How many edits landed. */
  applied: number
  /** The file's state after the last applied edit, when known. */
  state?: L4FileState
}

/**
 * Text near a failed `old`, so the model can correct it without another
 * read. Only ever advice: it's never applied, because whitespace is
 * meaningful in L4 and a near match can change what a rule decides.
 */
function describeNearestText(text: string, old: string): string | undefined {
  const squash = (t: string): string => t.replace(/\s+/g, ' ').trim()
  const wanted = squash(old)
  if (!wanted) return undefined
  const lines = text.split(/\r?\n/)
  const span = old.trim().split(/\r?\n/).length
  const clip = (t: string): string =>
    t.length > 600 ? `${t.slice(0, 600)}...` : t
  for (let i = 0; i + span <= lines.length; i++) {
    const window = lines.slice(i, i + span).join('\n')
    if (squash(window) === wanted) {
      return `The text at line ${i + 1} differs only in whitespace. Copy it exactly, because whitespace can change what the code means:\n${clip(window)}`
    }
  }
  const firstLine = squash(old.trim().split(/\r?\n/)[0] ?? '')
  if (!firstLine) return undefined
  const same = lines
    .map((line, i) => ({ line, i }))
    .filter(({ line }) => squash(line) === firstLine)
    .slice(0, 3)
  if (same.length === 0) return undefined
  const rows = same.map(({ line, i }) => `${i + 1}: ${clip(line)}`)
  return `The first line of 'old' appears at:\n${rows.join('\n')}`
}

interface AppliedEdit {
  startLine: number
  endLine: number
  oldLines: number
  newLines: number
}

/**
 * String-anchored find/replace. Fails loudly when `old` is missing or
 * ambiguous. Line numbers would be brittle across multi-round turns;
 * unique text anchors fail fast. Matches the pattern used by Cursor,
 * Claude Code, Aider.
 *
 * Routed through {@link Workspace.applyEdits}: in VS Code that is
 * `workspace.applyEdit` + save, so the L4 language server sees the
 * change via didChange (keeps l4__evaluate fresh), the edit joins the
 * undo stack, and disk-based readers (`fs__read_file`, other
 * extensions) see the new content immediately.
 */
async function applyOneEdit(
  ctx: FsToolContext,
  r: ResolvedPath,
  args: FsEditItem
): Promise<AppliedEdit> {
  if (typeof args.old !== 'string') {
    throw new Error(
      "fs__edit_file: 'old' must be a non-empty string identifying the snippet to replace."
    )
  }
  // Whole-file replace is intentionally not supported. A single
  // tool_use carrying the entire file body is the classic max_tokens
  // truncation trap — the provider cuts the args JSON mid-string,
  // toolCalls comes back empty, the edit silently never lands. For a
  // new file: pass `content` to fs__create_file; for an existing file:
  // replace surgical sections in multiple smaller edits.
  if (args.old.length === 0) {
    throw new Error(
      `fs__edit_file: 'old' must be a non-empty anchor snippet. Whole-file replacement is not supported — for a new file, pass \`content\` to fs__create_file; for a seeded file, replace the seed line "${FS_CREATE_FILE_SEED.trimEnd()}" first. For large rewrites, split into multiple smaller edits.`
    )
  }
  // Same defensive check we use in fs__create_file: fail fast when
  // the model omitted `new` before any LSP edit machinery spins up.
  // Empty-string replacements are valid (it's how we delete a
  // snippet), so the typeof check allows "" but rejects undefined.
  if (typeof args.new !== 'string') {
    throw new Error(
      "fs__edit_file: 'new' is required (as a string). Pass an empty string to delete the 'old' snippet."
    )
  }
  // Edit MUST NOT auto-create. If the path doesn't resolve to an
  // existing file, fail loudly with a message that points the model
  // at fs__create_file. openTextDocument can otherwise be coerced
  // (e.g. on `untitled:` schemes) into producing an in-memory buffer
  // that then races with the model's expectations.
  if (!(await ctx.workspace.stat(r.fsPath))) {
    throw new Error(
      `fs__edit_file: ${r.relative} does not exist. Use fs__create_file to create it first, then call fs__edit_file to add content.`
    )
  }
  const doc = await ctx.workspace.readDocument(r.uri)
  // Preserve the file's line-ending style across the edit. The model
  // always sends LF in `args.old` / `args.new`; if the document is
  // CRLF we normalize both to CRLF so (a) byte offsets computed from
  // the search match the live document text (offsets count the raw
  // buffer including \r), and (b) the inserted snippet stays
  // uniformly CRLF instead of dropping LF runs into a CRLF file.
  // Without this, a single edit to a CRLF file silently flattened
  // the whole file to LF — the LF-only `args.new` was spliced in
  // as-is and applyEdit + save preserved the result wholesale.
  // `replace(/\r?\n/g, …)` accepts whichever form the model sent.
  const docEol = doc.eol
  const oldNormalized = args.old.replace(/\r?\n/g, docEol)
  const newNormalized = args.new.replace(/\r?\n/g, docEol)
  // Search the raw document text (no LF normalization) so offsets
  // line up 1:1 with what the workspace applies below.
  const currentText = doc.text

  // When `startLine` is set, drop the lines at/before it from the
  // search window. The replace still applies to the real document
  // so we track the absolute offset that corresponds to the
  // window's start. Without startLine, the window is the whole
  // file and the `old` snippet must be unique in it; with startLine
  // set we just take the first match in the window (earlier
  // identical snippets are intentionally skipped).
  const anchorLine =
    typeof args.startLine === 'number' && Number.isFinite(args.startLine)
      ? Math.max(0, Math.floor(args.startLine))
      : 0
  let searchOffset = 0
  if (anchorLine > 0) {
    const allLines = currentText.split(docEol)
    if (anchorLine >= allLines.length) {
      throw new Error(
        `fs__edit_file: startLine=${args.startLine} is past the end of ${r.relative} (${allLines.length} lines).`
      )
    }
    // Offset of the line AFTER the anchor — `anchorLine` lines plus
    // that many line terminators (\n or \r\n depending on the file).
    searchOffset =
      allLines.slice(0, anchorLine).reduce((n, l) => n + l.length, 0) +
      anchorLine * docEol.length
  }
  const searchWindow = currentText.slice(searchOffset)
  const notFoundHint = (): string => {
    const nearest = ctx.mayQuoteFile
      ? describeNearestText(currentText, oldNormalized)
      : undefined
    return nearest ? `\n${nearest}` : ''
  }

  if (anchorLine === 0) {
    const occurrences = countOccurrences(searchWindow, oldNormalized)
    if (occurrences === 0) {
      throw new Error(
        `fs__edit_file: the 'old' snippet was not found in ${r.relative}${notFoundHint()}`
      )
    }
    if (occurrences > 1) {
      throw new Error(
        `fs__edit_file: the 'old' snippet appears ${occurrences} times in ${r.relative}. Include more surrounding lines to make it unique, or pass startLine=<line> to anchor.`
      )
    }
  }

  const hit = searchWindow.indexOf(oldNormalized)
  if (hit === -1) {
    throw new Error(
      anchorLine === 0
        ? `fs__edit_file: 'old' snippet not found in ${r.relative}${notFoundHint()}`
        : `fs__edit_file: 'old' snippet not found in ${r.relative} after line ${anchorLine}${notFoundHint()}`
    )
  }
  const startOffset = searchOffset + hit
  const endOffset = startOffset + oldNormalized.length
  try {
    await ctx.workspace.applyEdits([
      { uri: r.uri, startOffset, endOffset, newText: newNormalized },
    ])
  } catch (err) {
    throw new Error(
      `fs__edit_file: could not apply edit to ${r.relative} (file may be read-only): ${err instanceof Error ? err.message : String(err)}`
    )
  }
  const editStartLine = positionAt(currentText, startOffset).line + 1
  return {
    startLine: editStartLine,
    endLine: editStartLine + args.new.split('\n').length - 1,
    oldLines: args.old.split('\n').length,
    newLines: args.new.split('\n').length,
  }
}

/** The changes a call asks for, in order. */
function editItems(args: FsEditArgs): FsEditItem[] {
  if (args.edits === undefined) {
    return [
      {
        old: args.old as string,
        new: args.new as string,
        ...(args.startLine !== undefined ? { startLine: args.startLine } : {}),
      },
    ]
  }
  if (!Array.isArray(args.edits) || args.edits.length === 0) {
    throw new Error(
      "fs__edit_file: 'edits' must be a non-empty list of { old, new } changes."
    )
  }
  return args.edits
}

async function fileState(
  ctx: FsToolContext,
  r: ResolvedPath
): Promise<CheckedDiagnostics | null> {
  try {
    return await ctx.l4.getCheckedDiagnostics(r.uri)
  } catch {
    return null
  }
}

/**
 * Apply edits one at a time, checking the file after each, and stop at the
 * first one that fails or leaves the file worse: anything after a mistake
 * would land blind on a broken file. Earlier edits stay, and so does the
 * one that stopped the run, so the diagnostics match what's on disk. An
 * unknown result stops the run too, because continuing past it is exactly
 * how a broken file gets built on.
 */
async function applySequence(
  ctx: FsToolContext,
  r: ResolvedPath,
  items: FsEditItem[],
  run: EditSequence
): Promise<FsEditResult> {
  if (run.stopped) {
    throw new Error(`fs__edit_file: not applied. ${run.stopped}`)
  }
  const room = MAX_EDITS_PER_FILE - run.applied
  if (room <= 0) {
    throw new Error(
      `fs__edit_file: not applied. A file takes at most ${MAX_EDITS_PER_FILE} edits in one response; send the rest once you've seen the result.`
    )
  }
  const isL4 = isL4Path(r.fsPath)
  if (isL4 && run.state === undefined) {
    const before = await fileState(ctx, r)
    run.state = before && !before.pending ? l4FileState(before) : null
  }
  const batch = items.slice(0, room)
  const notes: string[] = []
  let first: number | undefined
  let last: number | undefined
  let checked: CheckedDiagnostics | undefined
  let done = 0
  let failed = false
  let stop: string | undefined
  for (const [i, item] of batch.entries()) {
    let edit: AppliedEdit
    try {
      edit = await applyOneEdit(ctx, r, item)
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      run.stopped = `An earlier edit to ${r.relative} in this response failed. Look at the file again first.`
      if (done === 0) throw err
      failed = true
      stop = message
      notes.push(`Edit ${i + 1}: not applied. ${message}`)
      break
    }
    run.applied++
    done++
    first = Math.min(first ?? edit.startLine, edit.startLine)
    last = Math.max(last ?? edit.endLine, edit.endLine)
    let note = `Edit ${i + 1}: lines ${edit.startLine}-${edit.endLine}`
    if (isL4) {
      const now = await fileState(ctx, r)
      checked = now ?? undefined
      const state = now && !now.pending ? l4FileState(now) : null
      if (!state) {
        stop = `the check did not finish, so the next edit would be blind`
      } else if (run.state && isWorse(run.state, state)) {
        stop = `the file went from "${describeFileState(run.state)}" to "${describeFileState(state)}"`
      }
      run.state = state
    }
    if (stop) {
      note += `. Stopped here: ${stop}`
      run.stopped = `An earlier edit to ${r.relative} in this response ${stop}. Fix that first.`
    }
    notes.push(note)
    if (stop) break
  }
  const left = items.length - done - (failed ? 1 : 0)
  if (left > 0) {
    const from = items.length - left + 1
    const which = left === 1 ? `Edit ${from}` : `Edits ${from}-${items.length}`
    notes.push(
      stop
        ? `${which}: not applied. Send what's still needed once the file is fixed.`
        : `${which}: not applied. A file takes at most ${MAX_EDITS_PER_FILE} edits in one response.`
    )
  }
  const header = `[${r.relative} ${first}-${last}] (Applied ${done} of ${items.length} edits)`
  const { text, state } = await reportL4File(
    ctx,
    r,
    `${header}\n${notes.join('\n')}`,
    checked
  )
  return { output: text, applied: done, ...(state ? { state } : {}) }
}

/**
 * Apply one edit, or a run of them when `edits` is given or `sequence` ties
 * this call to others in the same model response.
 */
export async function fsEditFileDetailed(
  ctx: FsToolContext,
  args: FsEditArgs,
  sequence?: EditSequence
): Promise<FsEditResult> {
  const r = ctx.workspace.resolvePath(args.path)
  const items = editItems(args)
  if (items.length > 1 || sequence) {
    return applySequence(ctx, r, items, sequence ?? { applied: 0 })
  }
  const edit = await applyOneEdit(ctx, r, items[0]!)
  // `[<path> <start>-<end>]` prefix carries the post-edit line range
  // so the chat row can render it as a muted "Lines 23-45" suffix
  // (matches fs__read_file's surfacing). No `/total` segment here —
  // total file-line count isn't useful for an edit row, and its
  // absence tells the webview parser this is an edit-anchor range
  // (always shown) rather than a read range (suppressed when it
  // covers the whole file).
  const { text, state } = await reportL4File(
    ctx,
    r,
    `[${r.relative} ${edit.startLine}-${edit.endLine}] (Edited ${edit.oldLines} → ${edit.newLines} lines)`
  )
  return { output: text, applied: 1, ...(state ? { state } : {}) }
}

export async function fsEditFile(
  ctx: FsToolContext,
  args: FsEditArgs,
  sequence?: EditSequence
): Promise<string> {
  return (await fsEditFileDetailed(ctx, args, sequence)).output
}

/**
 * What a write call would do, as text for a user deciding whether to allow
 * it. Before the call runs there's no file to show, so without this an
 * approval would be a blind yes. `null` when there's nothing to preview.
 */
export function proposedChange(
  name: string,
  args: unknown
): { text: string; language: 'plaintext' | 'diff' } | null {
  const a = (args ?? {}) as Partial<FsCreateArgs & FsEditArgs>
  if (name === 'fs__create_file') {
    return typeof a.content === 'string'
      ? { text: a.content, language: 'plaintext' }
      : null
  }
  if (name !== 'fs__edit_file') return null
  const edits = Array.isArray(a.edits)
    ? a.edits
    : typeof a.old === 'string' && typeof a.new === 'string'
      ? [{ old: a.old, new: a.new }]
      : []
  if (edits.length === 0) return null
  const quote = (text: unknown, mark: string): string =>
    String(text ?? '')
      .split('\n')
      .map((line) => `${mark} ${line}`)
      .join('\n')
  const parts = edits.map(
    (e, i) =>
      `@@ Edit ${i + 1} of ${edits.length} @@\n${quote(e.old, '-')}\n${quote(e.new, '+')}`
  )
  return { text: parts.join('\n'), language: 'diff' }
}

export interface FsDeleteArgs {
  path: string
}

export async function fsDeleteFile(
  ctx: Pick<FsToolContext, 'workspace'>,
  args: FsDeleteArgs
): Promise<string> {
  const r = ctx.workspace.resolvePath(args.path)
  // VS Code moves the file to the Trash so the user can recover it; a
  // headless host deletes it (git keeps the history).
  const how = await ctx.workspace.deleteFile(r)
  return how === 'trashed'
    ? `Moved ${r.relative} to trash`
    : `Deleted ${r.relative}`
}

export interface FsCopyArgs {
  from: string
  to: string
  /** Replace `to` when it exists. Default: fail instead. */
  overwrite?: boolean
  /** Delete `from` afterwards, making the copy a move. */
  deleteSource?: boolean
}

/**
 * Copy a text file in one step, optionally over an existing file and
 * removing the source (a move), instead of rebuilding it with
 * `fs__create_file` and many `fs__edit_file` calls.
 *
 * The source is read as the editor sees it (unsaved changes included).
 * A new target goes through {@link Workspace.createFile}; an existing
 * one is replaced in one {@link Workspace.applyEdits} change, so in VS
 * Code it joins the undo stack and the language server sees it like
 * any edit. The source goes through {@link Workspace.deleteFile}, which
 * keeps it recoverable.
 */
export async function fsCopyFileDetailed(
  ctx: FsToolContext,
  args: FsCopyArgs
): Promise<FsCreateResult> {
  if (typeof args.from !== 'string' || typeof args.to !== 'string') {
    throw new Error("fs__copy_file: 'from' and 'to' are required paths.")
  }
  const from = ctx.workspace.resolvePath(args.from)
  const to = ctx.workspace.resolvePath(args.to)
  if (from.fsPath === to.fsPath) {
    throw new Error(`${from.relative} is both the source and the target.`)
  }
  const src = await ctx.workspace.stat(from.fsPath)
  if (!src) throw new Error(`File not found: ${from.relative}`)
  if (!src.isFile) throw new Error(`Not a file: ${from.relative}`)
  const { text } = await ctx.workspace.readDocument(from.uri)
  if (text.includes('\u0000')) {
    throw new Error(`${from.relative} is not a text file.`)
  }
  const dest = await ctx.workspace.stat(to.fsPath)
  if (dest && !dest.isFile) throw new Error(`Not a file: ${to.relative}`)
  // "Contract.l4" → "contract.l4" on macOS or Windows is one file:
  // replacing it and then deleting the source would delete it.
  if (dest && (await ctx.workspace.sameFile?.(from.fsPath, to.fsPath))) {
    throw new Error(
      `${from.relative} and ${to.relative} are the same file on disk (the file system ignores case, or a link joins them); fs__copy_file can't copy or move a file onto itself.`
    )
  }
  if (dest && !args.overwrite) {
    throw new Error(
      `File already exists: ${to.relative}. Set overwrite to replace it.`
    )
  }
  if (dest) {
    const current = await ctx.workspace.readDocument(to.uri)
    await ctx.workspace.applyEdits([
      {
        uri: to.uri,
        startOffset: 0,
        endOffset: current.text.length,
        newText: text,
      },
    ])
  } else {
    await ctx.workspace.createFile(to, text)
  }
  let body = `${args.deleteSource ? 'Moved' : 'Copied'} ${from.relative} to ${to.relative}${dest ? ' (replaced the existing file)' : ''}`
  if (args.deleteSource) {
    const how = await ctx.workspace.deleteFile(from)
    if (how === 'trashed') body += `; ${from.relative} is in the trash`
  }
  const { text: output, state } = await reportL4File(ctx, to, body)
  return {
    output,
    relative: to.relative,
    uri: to.uri,
    ...(state ? { state } : {}),
  }
}

export async function fsCopyFile(
  ctx: FsToolContext,
  args: FsCopyArgs
): Promise<string> {
  return (await fsCopyFileDetailed(ctx, args)).output
}

function countOccurrences(haystack: string, needle: string): number {
  if (!needle) return 0
  let count = 0
  let idx = 0
  while ((idx = haystack.indexOf(needle, idx)) !== -1) {
    count++
    idx += needle.length
  }
  return count
}

/**
 * Resolve a tool-call's `path` argument to its workspace URI, or null
 * when it can't be resolved (outside the workspace, no workspace).
 */
export function resolveFileUri(workspace: Workspace, p: string): string | null {
  try {
    return workspace.resolvePath(p).uri
  } catch {
    return null
  }
}

/**
 * Snapshot the current on-disk contents of a file referenced by a
 * tool-call argument. Returns `''` if the file does not exist yet.
 * The tool dispatcher calls this BEFORE running fs__create / fs__edit
 * so the "before" side of the applied-diff view has something to show.
 */
export async function resolveCurrentContents(
  workspace: Workspace,
  p: string
): Promise<string> {
  const r = workspace.resolvePath(p)
  if (!(await workspace.stat(r.fsPath))) return ''
  return (await workspace.readFile(r.fsPath)).replace(/\r\n/g, '\n')
}
