/**
 * Seeding a cloud session (spec §10): which files go in, where they
 * land in the session's `repo/data/`, the size limits, and the
 * `seed.tar.gz` itself.
 *
 * Paths are kept relative to the files' common ancestor, so an L4
 * `IMPORT` of `../shared/defs` still resolves in the cloud. (The
 * prototype flattened everything to file names, which broke imports
 * across directories.)
 *
 * Pure: works on `/`-separated paths (URI paths) and bytes. The
 * VS Code side (vscode-cloud.ts) reads the files.
 */
import { createHash } from 'node:crypto'
import { gzipSync } from 'node:zlib'
import {
  FILE_NAME_RE,
  MAX_ATTACHMENT_BYTES,
  MAX_SEED_BYTES,
} from '@repo/legalese-agent/protocol'

/** A file to seed, by absolute `/`-separated path (a URI path). */
export interface SeedSource {
  path: string
  bytes: Uint8Array
}

/** A file in the seed, by path relative to the seed root. */
export interface SeedFile {
  path: string
  bytes: Uint8Array
}

/** A prompt attachment for the session's `attachments/` folder. */
export interface SeedAttachment {
  name: string
  contentType: string
  bytes: Uint8Array
}

/** The limits declined a start; the message names the files. */
export class SeedLimitError extends Error {
  constructor(
    message: string,
    readonly files: string[]
  ) {
    super(message)
    this.name = 'SeedLimitError'
  }
}

/** Control characters (C0 and DEL), which the Sessions API rejects. */
function hasControlChar(s: string): boolean {
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i)
    if (c < 0x20 || c === 0x7f) return true
  }
  return false
}

function stripControlChars(s: string): string {
  let out = ''
  for (const ch of s) {
    const c = ch.charCodeAt(0)
    if (c >= 0x20 && c !== 0x7f) out += ch
  }
  return out
}

function splitPath(p: string): string[] {
  return p.split('/').filter((s) => s.length > 0)
}

/** The deepest directory containing every path (`/`-separated). */
export function commonAncestor(paths: string[]): string {
  if (paths.length === 0) return '/'
  const dirs = paths.map((p) => splitPath(p).slice(0, -1))
  const first = dirs[0]!
  let n = first.length
  for (const d of dirs.slice(1)) {
    let i = 0
    while (i < n && i < d.length && d[i] === first[i]) i++
    n = i
  }
  return '/' + first.slice(0, n).join('/')
}

/** Is `p` inside directory `root` (both absolute, `/`-separated)? */
export function isUnder(p: string, root: string): boolean {
  const a = splitPath(p)
  const r = splitPath(root)
  if (a.length <= r.length) return false
  return r.every((seg, i) => a[i] === seg)
}

/** Every path component must survive the Sessions API's tar checks. */
function safeComponent(c: string): boolean {
  return (
    c.length > 0 &&
    c !== '.' &&
    c !== '..' &&
    c.toLowerCase() !== '.git' &&
    Buffer.byteLength(c, 'utf8') <= 255 &&
    !c.includes('\\') &&
    !hasControlChar(c)
  )
}

/**
 * Place the sources under their common ancestor. Duplicates (same
 * path) keep the first. Files outside every `roots` entry are left
 * out and reported — the L4 libraries the language server resolves
 * from its own install are available in the cloud already, and
 * nothing from elsewhere on the machine should be uploaded by accident.
 */
export function layoutSeed(
  sources: SeedSource[],
  roots: string[]
): { files: SeedFile[]; root: string; skipped: string[] } {
  const seen = new Set<string>()
  const kept: SeedSource[] = []
  const skipped: string[] = []
  for (const s of sources) {
    if (seen.has(s.path)) continue
    seen.add(s.path)
    if (roots.length > 0 && !roots.some((r) => isUnder(s.path, r))) {
      skipped.push(s.path)
      continue
    }
    kept.push(s)
  }
  const root = commonAncestor(kept.map((s) => s.path))
  const rootParts = splitPath(root)
  const files: SeedFile[] = []
  for (const s of kept) {
    const rel = splitPath(s.path).slice(rootParts.length)
    if (rel.length === 0 || !rel.every(safeComponent)) {
      skipped.push(s.path)
      continue
    }
    files.push({ path: rel.join('/'), bytes: s.bytes })
  }
  return { files, root, skipped }
}

function formatSize(bytes: number): string {
  return bytes >= 1024 * 1024
    ? `${(bytes / (1024 * 1024)).toFixed(1)} MB`
    : `${Math.ceil(bytes / 1024)} KB`
}

/** Plain attachment names: no separators, no leading dot, unique. */
export function attachmentNames(names: string[]): string[] {
  const used = new Set<string>()
  return names.map((raw) => {
    let base = stripControlChars(raw.split(/[/\\]/).pop()!)
      .replace(/^\.+/, '')
      .trim()
    if (!base) base = 'attachment'
    while (Buffer.byteLength(base, 'utf8') > 200) base = base.slice(0, -1)
    let name = base
    for (let i = 2; used.has(name) || !FILE_NAME_RE.test(name); i++) {
      const dot = base.lastIndexOf('.')
      name =
        dot > 0
          ? `${base.slice(0, dot)}-${i}${base.slice(dot)}`
          : `${base}-${i}`
      if (i > 1000) throw new Error('could not name attachment')
    }
    used.add(name)
    return name
  })
}

/** Decline attachments over 10 MB before anything is uploaded. */
export function checkAttachmentSizes(attachments: SeedAttachment[]): void {
  const over = attachments.filter(
    (a) => a.bytes.byteLength > MAX_ATTACHMENT_BYTES
  )
  if (over.length === 0) return
  throw new SeedLimitError(
    `Attachments over ${formatSize(MAX_ATTACHMENT_BYTES)} can't go to a cloud session: ` +
      over
        .map((a) => `${a.name} (${formatSize(a.bytes.byteLength)})`)
        .join(', ') +
      '.',
    over.map((a) => a.name)
  )
}

/** Decline a compressed seed over 50 MB, naming the largest files. */
export function checkSeedSize(gz: Uint8Array, files: SeedFile[]): void {
  if (gz.byteLength <= MAX_SEED_BYTES) return
  const largest = [...files]
    .sort((a, b) => b.bytes.byteLength - a.bytes.byteLength)
    .slice(0, 5)
  throw new SeedLimitError(
    `The files for this cloud session come to ${formatSize(gz.byteLength)} compressed, over the ${formatSize(MAX_SEED_BYTES)} limit. Largest: ` +
      largest
        .map((f) => `${f.path} (${formatSize(f.bytes.byteLength)})`)
        .join(', ') +
      '.',
    largest.map((f) => f.path)
  )
}

// ── tar (ustar + pax) ─────────────────────────────────────────────────

const BLOCK = 512

function writeString(buf: Buffer, offset: number, len: number, s: string) {
  buf.write(s, offset, Math.min(len, Buffer.byteLength(s)), 'utf8')
}

function writeOctal(buf: Buffer, offset: number, len: number, n: number) {
  writeString(buf, offset, len, n.toString(8).padStart(len - 1, '0') + '\0')
}

function header(
  name: string,
  size: number,
  type: '0' | 'x',
  mtime: number
): Buffer {
  const h = Buffer.alloc(BLOCK)
  writeString(h, 0, 100, name)
  writeOctal(h, 100, 8, 0o644)
  writeOctal(h, 108, 8, 0)
  writeOctal(h, 116, 8, 0)
  writeOctal(h, 124, 12, size)
  writeOctal(h, 136, 12, mtime)
  h.fill(0x20, 148, 156) // checksum placeholder
  h.write(type, 156, 'ascii')
  h.write('ustar\0', 257, 'ascii')
  h.write('00', 263, 'ascii')
  let sum = 0
  for (const b of h) sum += b
  writeString(h, 148, 8, sum.toString(8).padStart(6, '0') + '\0 ')
  return h
}

function padded(data: Buffer): Buffer[] {
  const rem = data.length % BLOCK
  return rem === 0 ? [data] : [data, Buffer.alloc(BLOCK - rem)]
}

function paxRecord(key: string, value: string): string {
  const body = ` ${key}=${value}\n`
  let len = Buffer.byteLength(body) + 1
  while (Buffer.byteLength(String(len)) + Buffer.byteLength(body) !== len) {
    len = Buffer.byteLength(String(len)) + Buffer.byteLength(body)
  }
  return `${len}${body}`
}

/**
 * A tar archive of regular files. Paths that don't fit ustar's 100-byte
 * ASCII name field get a pax `path` record (the Sessions API reads
 * both). Directories are implied by the file paths.
 */
export function createTar(files: SeedFile[], mtimeSeconds = 0): Buffer {
  const parts: Buffer[] = []
  for (const f of files) {
    const data = Buffer.from(
      f.bytes.buffer,
      f.bytes.byteOffset,
      f.bytes.byteLength
    )
    const ascii = /^[\x20-\x7e]*$/.test(f.path)
    let name = f.path
    if (!ascii || Buffer.byteLength(f.path) > 99) {
      const pax = Buffer.from(paxRecord('path', f.path), 'utf8')
      parts.push(
        header('PaxHeader', pax.length, 'x', mtimeSeconds),
        ...padded(pax)
      )
      name = 'pax-entry'
    }
    parts.push(header(name, data.length, '0', mtimeSeconds), ...padded(data))
  }
  parts.push(Buffer.alloc(BLOCK * 2))
  return Buffer.concat(parts)
}

export function createSeedTarGz(files: SeedFile[]): Buffer {
  return gzipSync(createTar(files, Math.floor(Date.now() / 1000)))
}

// ── Files added mid-session (§10) ────────────────────────────────────

/** `p` relative to directory `root` (both absolute, `/`-separated), or
 *  null when it isn't inside it. */
export function relativeTo(p: string, root: string): string | null {
  if (!isUnder(p, root)) return null
  return splitPath(p).slice(splitPath(root).length).join('/')
}

/**
 * Where a local file lives in a session's repo: `data/<path relative to
 * the seed base>`, or — for files outside that base — `data/<path
 * relative to its workspace folder>`. Null when neither applies or the
 * path wouldn't pass the Sessions API's checks.
 */
export function dataPathFor(
  absPath: string,
  base: string | undefined,
  workspaceRoots: string[]
): string | null {
  const candidates = [
    ...(base ? [base] : []),
    ...workspaceRoots.filter((r) => r !== base),
  ]
  for (const root of candidates) {
    const rel = relativeTo(absPath, root)
    if (rel === null) continue
    const parts = rel.split('/')
    if (!parts.every(safeComponent)) return null
    const dataPath = `data/${rel}`
    return Buffer.byteLength(dataPath, 'utf8') <= 1024 ? dataPath : null
  }
  return null
}

/** Hex SHA-256 of a file's bytes, to skip files already sent. */
export function contentHash(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex')
}

const TEXT_EXTENSIONS = new Set([
  'l4',
  'md',
  'txt',
  'json',
  'yaml',
  'yml',
  'csv',
  'html',
  'xml',
])

/** Content type for an added file (by extension). */
export function contentTypeFor(path: string): string {
  const ext = path.split('.').pop()?.toLowerCase() ?? ''
  if (ext === 'pdf') return 'application/pdf'
  return TEXT_EXTENSIONS.has(ext) ? 'text/plain' : 'application/octet-stream'
}

/**
 * Same limits as seeding: each added file at most 10 MB, a batch at
 * most 50 MB. Declines before anything is uploaded, naming the files.
 */
export function checkAddFilesSizes(files: SeedFile[]): void {
  const over = files.filter((f) => f.bytes.byteLength > MAX_ATTACHMENT_BYTES)
  if (over.length > 0) {
    throw new SeedLimitError(
      `Files over ${formatSize(MAX_ATTACHMENT_BYTES)} can't be added to a cloud session: ` +
        over
          .map((f) => `${f.path} (${formatSize(f.bytes.byteLength)})`)
          .join(', ') +
        '.',
      over.map((f) => f.path)
    )
  }
  const total = files.reduce((n, f) => n + f.bytes.byteLength, 0)
  if (total > MAX_SEED_BYTES) {
    const largest = [...files]
      .sort((a, b) => b.bytes.byteLength - a.bytes.byteLength)
      .slice(0, 5)
    throw new SeedLimitError(
      `The files to add come to ${formatSize(total)}, over the ${formatSize(MAX_SEED_BYTES)} limit. Largest: ` +
        largest
          .map((f) => `${f.path} (${formatSize(f.bytes.byteLength)})`)
          .join(', ') +
        '.',
      largest.map((f) => f.path)
    )
  }
}
