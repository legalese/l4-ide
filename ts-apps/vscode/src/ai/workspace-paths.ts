import * as path from 'path'
import { realpathSync } from 'fs'
import { isSensitivePath } from '@repo/legalese-agent'

/** The real path of `p`, or of its nearest existing ancestor with the rest
 *  appended, for a path that doesn't exist yet. */
export function realPathOfNearest(p: string): string {
  let current = p
  const rest: string[] = []
  for (;;) {
    try {
      return path.join(realpathSync(current), ...rest)
    } catch {
      const parent = path.dirname(current)
      if (parent === current) return p
      rest.unshift(path.basename(current))
      current = parent
    }
  }
}

function relativeInside(file: string, root: string): string | undefined {
  return file === root || file.startsWith(root + path.sep)
    ? path.relative(root, file)
    : undefined
}

/** Whether `file` really lies outside every root once symbolic links are
 *  followed, whatever its path says. */
export function leavesRoots(file: string, roots: string[]): boolean {
  const real = realPathOfNearest(file)
  return !roots.some(
    (root) => relativeInside(real, realPathOfNearest(root)) !== undefined
  )
}

/** Whether a write to `file` needs the user's say-so, by the path it was
 *  given and by where that really leads. */
export function isWriteSensitive(file: string, roots: string[]): boolean {
  const real = realPathOfNearest(file)
  return roots.some((root) =>
    [
      relativeInside(file, root),
      relativeInside(real, realPathOfNearest(root)),
    ].some((p) => p !== undefined && isSensitivePath(p))
  )
}
