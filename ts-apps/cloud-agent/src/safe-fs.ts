/**
 * File helpers for the session folder (spec §4.2, §7.2, §8).
 *
 * - Files are opened by known names only; the harness never lists a
 *   state directory to discover files (NFS caches listings and "not
 *   found" results, §8).
 * - Opens use `O_NOFOLLOW` and require a regular file under a size cap.
 * - Files other processes read are replaced with a temp file + rename,
 *   so readers see the old or the new content, never a torn write.
 */
import { randomBytes } from 'node:crypto'
import { constants, promises as fs } from 'node:fs'
import * as path from 'node:path'

const { O_RDONLY, O_WRONLY, O_CREAT, O_EXCL, O_APPEND, O_NOFOLLOW } = constants

export class FileTooLargeError extends Error {
  constructor(file: string) {
    super(`file too large: ${path.basename(file)}`)
    this.name = 'FileTooLargeError'
  }
}

export function isErrno(err: unknown, code: string): boolean {
  return (err as NodeJS.ErrnoException | undefined)?.code === code
}

/**
 * Read a regular file (no symlink) of at most `maxBytes`. Returns
 * `null` when it doesn't exist.
 */
export async function readKnownFile(
  file: string,
  maxBytes: number
): Promise<Buffer | null> {
  let handle: fs.FileHandle
  try {
    handle = await fs.open(file, O_RDONLY | O_NOFOLLOW)
  } catch (err) {
    if (isErrno(err, 'ENOENT')) return null
    throw err
  }
  try {
    const st = await handle.stat()
    if (!st.isFile())
      throw new Error(`not a regular file: ${path.basename(file)}`)
    if (st.size > maxBytes) throw new FileTooLargeError(file)
    const buf = Buffer.alloc(st.size)
    let off = 0
    while (off < st.size) {
      const { bytesRead } = await handle.read(buf, off, st.size - off, off)
      if (bytesRead === 0) break
      off += bytesRead
    }
    return buf.subarray(0, off)
  } finally {
    await handle.close()
  }
}

export async function readKnownText(
  file: string,
  maxBytes: number
): Promise<string | null> {
  const buf = await readKnownFile(file, maxBytes)
  return buf === null ? null : buf.toString('utf8')
}

/** Replace `file` atomically: write a temp file next to it, then rename. */
export async function writeAtomic(
  file: string,
  data: string | Uint8Array
): Promise<void> {
  const tmp = path.join(
    path.dirname(file),
    `.${path.basename(file)}.${process.pid}.${randomBytes(4).toString('hex')}.tmp`
  )
  const handle = await fs.open(
    tmp,
    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
    0o600
  )
  try {
    await handle.writeFile(data)
    await handle.sync().catch(() => undefined)
  } finally {
    await handle.close()
  }
  try {
    await fs.rename(tmp, file)
  } catch (err) {
    await fs.rm(tmp, { force: true }).catch(() => undefined)
    throw err
  }
}

/** Create `file` with `data`; fails with `EEXIST` when it exists. */
export async function createExclusive(
  file: string,
  data: string | Uint8Array
): Promise<void> {
  const handle = await fs.open(
    file,
    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
    0o600
  )
  try {
    await handle.writeFile(data)
  } finally {
    await handle.close()
  }
}

/** Append `data` to `file` (created if missing), closing it afterwards. */
export async function appendToFile(
  file: string,
  data: string | Uint8Array
): Promise<void> {
  const handle = await fs.open(
    file,
    O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW,
    0o600
  )
  try {
    await handle.writeFile(data)
  } finally {
    await handle.close()
  }
}
