/**
 * The files a deploy uploads, and the zip entry name of each.
 *
 * A deploy zips the open L4 file and every module it imports. The service keeps
 * the folder structure of the zip (`rows/b/mod.l4` is stored as such), so two
 * files with one name in different folders stay two files, and a bare IMPORT is
 * looked up beside the importing file and at the top of the zip.
 *
 * Entry names are therefore each file's path relative to the common ancestor
 * directory of the main file and every import. When all of them share one
 * folder that is the plain file name, as before.
 *
 * Nothing is skipped, renamed or flattened to make a deploy go through: a file
 * that cannot be read, a file outside the project root, two files that
 * would land on one entry name, and a file in a folder whose name the service
 * cannot look into (see `unfindableFolder`) each stop the deploy with an error
 * that names the file. The one exception is the standard library `jl4-lsp`
 * carries inside its binary (see below).
 *
 * None of these stops existed in the deploy before this one (`collectL4Sources`
 * in `sidebar-provider.ts` at 977691b36): it put every file in the zip under its
 * plain file name, had no project root and no check of where a file lay or of
 * two files sharing a name, and logged and skipped a file it could not read. A
 * project that the old deploy accepted can be stopped by this one.
 *
 * What this deploy cannot check: that a bare `IMPORT` is found where the service
 * looks, beside its importer or at the top of the zip. `l4/getExportedFunctions`
 * returns the imported files and not the import lines, so there is no line to
 * judge. `l4 deploy` has the lines and does judge them
 * (`jl4/app/L4/Cli/DeployPlan.hs`, `UnreachableImport`). A library in a folder
 * that is neither its importer's nor the top is uploaded here, the service says
 * "ready", and a call that needs it fails. Judging it here would need the
 * language server to return the lines, which is a change to that protocol and
 * is not made.
 *
 * A service built before the commit that makes the bundle root the top of the
 * upload (`bundleRoot` in jl4-service's Backend/Jl4.hs) looks a bare IMPORT up
 * from the folder of the first file of the upload in alphabetical order, not at
 * the top, when it compiles the bundle and answers a call on the direct path (a
 * call on the wrapper path, a request with a `{}` in an input, looks from the
 * folder of the function's own file instead; see jl4-service's
 * test/BundleRootSpec.hs), so a main file in a folder with its library at the
 * top is uploaded here, such a service says "ready", and every call fails; this
 * deploy does not
 * check the version of the service, and whether the service has to be released
 * first is not decided.
 *
 * Lives in its own module with no `vscode` import so `node --test` can exercise
 * it (see `unit-tests/deploy-bundle.test.ts`). The zip writer that packs the
 * collected files is here too, for the same reason (`unit-tests/create-zip.test.ts`).
 */
import { isEmbeddedLibraryUri } from './embedded-library.js'

export interface BundleFile {
  name: string
  content: Uint8Array
}

/**
 * Whether the service looks into a folder named like this: only letters from A
 * to Z, digits, `.`, `-` and `_`, which is what it is known to find (it finds
 * `~` too).
 *
 * The service does not find a file beside its importer when the first folder of
 * the file's path in the bundle has a space, a letter outside A to Z, or one of
 * `# ' + ( ) % , = @ & ! $ ; [ ]` in its name: the candidate is a relative
 * path, which a `file:` URI cannot spell so that it reads back. This is a
 * residual of the fix for smucclaw/l4-ide#971, which is closed, and no issue
 * tracks it yet (measured 2026-10-26 on the service, where `a`,
 * `my-dir_2.x`, `v1.2` and `a~b` answer and `my dir`, `dossier é`, a Hebrew
 * name, `a#b` and `a'b` do not; `specs/as-built/import-resolution.md` lists
 * the other characters). Only the first folder of the path decides there:
 * `ok/my dir` and `ok/dossier é` answer.
 * The check is made on every folder of the path and on every character other
 * than the ones named above, so it also stops a few names the service finds,
 * for example `ok/my dir` and `a~b`.
 * The main file's folder is not judged: nothing looks the main file up, and a
 * file at the top of the bundle is found whatever its importer's folder is
 * called.
 */
const FOLDER_NAME = /^[A-Za-z0-9._-]+$/
function unfindableFolder(folder: string[]): boolean {
  return folder.some((segment) => !FOLDER_NAME.test(segment))
}

export interface BundleOptions {
  /** The text of the document at `uri`: the open editor buffer if there is
   *  one, else the file on disk. Rejects when it cannot be read. */
  readText: (uri: string) => Promise<string>
  /** URI of the project root folder: the workspace folder that contains the
   *  main file. Without one, the main file's own directory is the root. */
  rootUri?: string
  /** One line per file collected (the Output channel). */
  log?: (line: string) => void
}

interface ParsedUri {
  uri: string
  /** Scheme and authority; two URIs are comparable only when these agree. */
  origin: string
  /** Decoded path segments, the file name last. */
  segments: string[]
  /** `segments` as compared: a Windows drive letter is case-insensitive. */
  keys: string[]
}

/** The path a user would recognise: the decoded path of a `file:` URI, else
 *  the URI itself. */
function labelOf(uri: string): string {
  try {
    const url = new URL(uri)
    if (url.protocol === 'file:') {
      const path = decodeURIComponent(url.pathname)
      return /^\/[a-zA-Z]:/.test(path) ? path.slice(1) : path
    }
  } catch {
    // not a URI we can decode: show it as it came
  }
  return uri
}

/** The folder a label sits in: everything before its last '/'. A file in the
 *  top folder (`/main.l4`, `c:/main.l4`) gives that folder, `/` or `c:/`. A
 *  label with no '/' (`untitled:Untitled-1`) has no folder to name, so it is
 *  shown whole. */
function directoryLabel(label: string): string {
  const slash = label.lastIndexOf('/')
  if (slash < 0) return label
  const dir = label.slice(0, slash)
  return dir === '' || /^[a-zA-Z]:$/.test(dir) ? `${dir}/` : dir
}

function parseUri(uri: string): ParsedUri {
  let url: URL
  try {
    url = new URL(uri)
  } catch {
    throw new Error(`Deploy stopped: ${uri} is not a valid URI.`)
  }
  const segments = url.pathname
    .split('/')
    .filter((s) => s.length > 0)
    .map((s) => {
      let decoded: string
      try {
        decoded = decodeURIComponent(s)
      } catch {
        throw new Error(
          `Deploy stopped: ${uri} contains a malformed %-escape ("${s}").`
        )
      }
      // A zip entry name is these joined with '/': a segment that holds one
      // (an escaped %2F) would name a different file than the one it came from.
      // '.' and '..' need no check here: for a hierarchical URI (file:,
      // vscode-remote:) the URL parser has already resolved them, even when
      // escaped (%2e%2e), and the root check confines the resolved path.
      if (decoded.includes('/')) {
        throw new Error(
          `Deploy stopped: ${uri} has the path segment "${decoded}", which cannot be part of a zip entry name.`
        )
      }
      return decoded
    })
  const keys = segments.map((s, i) =>
    i === 0 && /^[a-zA-Z]:$/.test(s) ? s.toLowerCase() : s
  )
  return { uri, origin: `${url.protocol}//${url.host}`, segments, keys }
}

/** Whether `file` is below the directory `root` (whole segments: `/a/b` does
 *  not contain `/a/bc/x.l4`). */
function isInside(file: ParsedUri, root: ParsedUri): boolean {
  return (
    file.origin === root.origin &&
    root.keys.length < file.keys.length &&
    root.keys.every((k, i) => file.keys[i] === k)
  )
}

/**
 * Collect the main L4 file and its transitive imports for a deploy.
 * Import URIs are provided by the LSP via l4/getExportedFunctions.
 * Returns the main file first, then the imports in the order given.
 */
export async function collectBundle(
  mainUri: string,
  importUris: string[],
  options: BundleOptions
): Promise<BundleFile[]> {
  const { readText, rootUri, log } = options
  const main = parseUri(mainUri)
  const mainLabel = labelOf(mainUri)
  const root: ParsedUri =
    rootUri !== undefined
      ? parseUri(rootUri)
      : {
          ...main,
          segments: main.segments.slice(0, -1),
          keys: main.keys.slice(0, -1),
        }
  const rootLabel =
    rootUri !== undefined ? labelOf(rootUri) : directoryLabel(mainLabel)

  const encoder = new TextEncoder()
  const collected = new Map<string, { file: ParsedUri; content: Uint8Array }>()

  // Read a single file URI into the collection
  async function collectFile(uri: string) {
    if (collected.has(uri)) return
    const file = uri === mainUri ? main : parseUri(uri)
    if (file.segments.length === 0) {
      throw new Error(`Deploy stopped: ${uri} has no file name.`)
    }
    if (!isInside(file, root)) {
      throw new Error(
        `Deploy stopped: ${labelOf(uri)} lies outside the project root ${rootLabel}. ` +
          `A deployment can only include files inside the project root: open a workspace folder that contains it, or move it inside the root. ` +
          `If it is a library the language server found through JL4_LIBRARY_PATH or the per-user library folder, ` +
          `the deployment does not use that copy but the service's built-in standard library, ` +
          `so unset JL4_LIBRARY_PATH for the editor, or move the library into the project instead of copying it: ` +
          `the language server reads JL4_LIBRARY_PATH before the project, so while it is set a copy in the project is ignored.`
      )
    }
    let text: string
    try {
      text = await readText(uri)
    } catch (err) {
      const why = err instanceof Error ? err.message : String(err)
      throw new Error(`Deploy stopped: could not read ${labelOf(uri)}: ${why}`)
    }
    collected.set(uri, { file, content: encoder.encode(text) })
  }

  // Collect main file first, then all imports
  await collectFile(mainUri)
  for (const importUri of importUris) {
    // The stdlib jl4-lsp carries inside its binary. A deployment runs on the
    // service's own built-in stdlib unless the bundle ships a same-named file
    // (`bundleScope` in jl4-service's Backend/Jl4.hs), so zipping this
    // machine's would pin it over the service's. Ruled 2026-10-12: deployments
    // run on the service's built-in stdlib, and this skip stands; a later,
    // non-blocking change is to warn at deploy time when this machine's stdlib
    // differs from the service's.
    if (isEmbeddedLibraryUri(importUri)) continue
    await collectFile(importUri)
  }

  // Names: each path below the directories every file has in common.
  const entries = Array.from(collected.values())
  const dirs = entries.map((e) => e.file.keys.slice(0, -1))
  let shared = dirs[0].length
  for (const dir of dirs) {
    shared = Math.min(shared, dir.length)
    for (let i = 0; i < shared; i++) {
      if (dir[i] !== dirs[0][i]) {
        shared = i
        break
      }
    }
  }

  const named = new Map<string, string>()
  const files: BundleFile[] = []
  const unfindable: string[] = []
  for (const [index, { file, content }] of entries.entries()) {
    const name = file.segments.slice(shared).join('/')
    const other = named.get(name)
    if (other !== undefined) {
      throw new Error(
        `Deploy stopped: ${other} and ${file.uri} would both be stored as "${name}" in the bundle.`
      )
    }
    named.set(name, file.uri)
    // Every file but the main one was brought in by an import (the language
    // server returns the files, not the lines), so each is one that something
    // looks up. The folder is judged by the entry name, as the service sees it.
    const folder = file.segments.slice(shared, -1)
    if (index > 0 && unfindableFolder(folder)) {
      unfindable.push(
        `${name} (${labelOf(file.uri)}) is in the folder "${folder.join('/')}"`
      )
    }
    files.push({ name, content })
    log?.(`Collected: ${name}`)
  }
  if (unfindable.length > 0) {
    const one = unfindable.length === 1
    throw new Error(
      `Deploy stopped: the deployed service may not find ${one ? 'a file that is imported' : 'files that are imported'}, ` +
        `because of the ${one ? 'name of the folder it is' : 'names of the folders they are'} in: ${unfindable.join('; ')}. ` +
        `The deployed service does not find a file beside the file that imports it when the first folder of the file's path in the bundle has a space, a letter outside A to Z, or one of # ' + ( ) % , = @ & ! $ ; [ ] in its name. ` +
        `The deployment would say it is ready, and every call would then fail. ` +
        `The deploy stops at any character other than a letter from A to Z, a digit, '.', '-' or '_' in any folder of the path, not only the first, so it also stops a few names the service would find, for example ok/my dir and a~b. ` +
        `Rename the folder to use only letters, digits, '.', '-' and '_', and deploy again. ` +
        `A copy of a standard library module in such a folder stops the deploy too, even when it is exactly the copy built into the service, because this deploy cannot tell a built-in copy from any other file (l4 deploy leaves such a copy out). ` +
        `If the language server found that copy through JL4_LIBRARY_PATH, you can instead unset JL4_LIBRARY_PATH for the editor.`
    )
  }
  return files
}

// ---------------------------------------------------------------------------
// Minimal ZIP builder (store, no compression)
// ---------------------------------------------------------------------------

const crcTable = new Uint32Array(256)
for (let i = 0; i < 256; i++) {
  let c = i
  for (let j = 0; j < 8; j++) {
    c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
  }
  crcTable[i] = c
}

function crc32(data: Uint8Array): number {
  let crc = 0xffffffff
  for (let i = 0; i < data.length; i++) {
    crc = crcTable[(crc ^ data[i]) & 0xff] ^ (crc >>> 8)
  }
  return (crc ^ 0xffffffff) >>> 0
}

/** General-purpose flag bit 11 of a zip entry: its name is UTF-8. */
const UTF8_NAME_FLAG = 0x0800

/**
 * Pack files into a zip, stored (not compressed), in the order given.
 *
 * An entry name is written as UTF-8. A name with a byte above 0x7f (a folder
 * called `תיקייה`, now that the names carry folders) gets the zip format's
 * UTF-8 flag, bit 11 of the general-purpose flags, in both its local and its
 * central header, so that a reader decodes the name as UTF-8 and not as the
 * legacy code page it assumes without the flag. An all-ASCII name has no flag
 * set, so a zip of such names is byte for byte what this function wrote before
 * the flag existed.
 */
export function createZip(
  files: { name: string; content: Uint8Array }[]
): Uint8Array {
  const encoder = new TextEncoder()

  // Pre-compute sizes
  type Entry = {
    nameBytes: Uint8Array
    flags: number
    content: Uint8Array
    crc: number
    localOffset: number
  }
  const entries: Entry[] = []
  let localSize = 0
  for (const file of files) {
    const nameBytes = encoder.encode(file.name)
    const crc = crc32(file.content)
    entries.push({
      nameBytes,
      flags: nameBytes.some((b) => b > 0x7f) ? UTF8_NAME_FLAG : 0,
      content: file.content,
      crc,
      localOffset: localSize,
    })
    localSize += 30 + nameBytes.length + file.content.length
  }

  let centralSize = 0
  for (const e of entries) centralSize += 46 + e.nameBytes.length
  const endSize = 22
  const totalSize = localSize + centralSize + endSize

  const buf = new ArrayBuffer(totalSize)
  const view = new DataView(buf)
  const bytes = new Uint8Array(buf)
  let offset = 0

  // Local file headers + data
  for (const e of entries) {
    view.setUint32(offset, 0x04034b50, true)
    offset += 4
    view.setUint16(offset, 20, true)
    offset += 2
    view.setUint16(offset, e.flags, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint32(offset, e.crc, true)
    offset += 4
    view.setUint32(offset, e.content.length, true)
    offset += 4
    view.setUint32(offset, e.content.length, true)
    offset += 4
    view.setUint16(offset, e.nameBytes.length, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    bytes.set(e.nameBytes, offset)
    offset += e.nameBytes.length
    bytes.set(e.content, offset)
    offset += e.content.length
  }

  const centralOffset = offset

  // Central directory headers
  for (const e of entries) {
    view.setUint32(offset, 0x02014b50, true)
    offset += 4
    view.setUint16(offset, 20, true)
    offset += 2
    view.setUint16(offset, 20, true)
    offset += 2
    view.setUint16(offset, e.flags, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint32(offset, e.crc, true)
    offset += 4
    view.setUint32(offset, e.content.length, true)
    offset += 4
    view.setUint32(offset, e.content.length, true)
    offset += 4
    view.setUint16(offset, e.nameBytes.length, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint32(offset, 0, true)
    offset += 4
    view.setUint32(offset, e.localOffset, true)
    offset += 4
    bytes.set(e.nameBytes, offset)
    offset += e.nameBytes.length
  }

  // End of central directory
  view.setUint32(offset, 0x06054b50, true)
  offset += 4
  view.setUint16(offset, 0, true)
  offset += 2
  view.setUint16(offset, 0, true)
  offset += 2
  view.setUint16(offset, entries.length, true)
  offset += 2
  view.setUint16(offset, entries.length, true)
  offset += 2
  view.setUint32(offset, centralSize, true)
  offset += 4
  view.setUint32(offset, centralOffset, true)
  offset += 4
  view.setUint16(offset, 0, true)

  return new Uint8Array(buf)
}
