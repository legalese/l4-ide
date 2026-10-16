import * as path from 'node:path'
import type { AiChatAttachment } from 'jl4-client-rpc'
import {
  FILE_NAME_RE,
  MAX_ATTACHMENT_BYTES,
  type AttachmentRef,
} from '@repo/legalese-agent/protocol'
import { readKnownFile } from './safe-fs.js'

const MEDIA_TYPES: Record<string, string> = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.pdf': 'application/pdf',
  '.txt': 'text/plain',
  '.md': 'text/markdown',
  '.markdown': 'text/markdown',
  '.csv': 'text/csv',
  '.json': 'application/json',
  '.xml': 'application/xml',
  '.html': 'text/html',
  '.htm': 'text/html',
  '.l4': 'text/plain',
  '.yaml': 'application/yaml',
  '.yml': 'application/yaml',
}

export function mediaTypeFor(name: string): string {
  return (
    MEDIA_TYPES[path.extname(name).toLowerCase()] ?? 'application/octet-stream'
  )
}

export interface LoadedAttachment {
  ref: AttachmentRef
  attachment: AiChatAttachment
}

/**
 * Load prompt attachments named by a `message` command from the
 * session's `attachments/` folder (outside the repo, spec §4.2). Names
 * are validated plain file names; files are opened without following
 * links and capped at 10 MB. Missing or unreadable files are reported
 * in `missing` and left out.
 */
export async function loadAttachments(
  attachmentsDir: string,
  names: string[]
): Promise<{ loaded: LoadedAttachment[]; missing: string[] }> {
  const loaded: LoadedAttachment[] = []
  const missing: string[] = []
  for (const name of names) {
    if (!FILE_NAME_RE.test(name)) {
      missing.push(name)
      continue
    }
    let buf: Buffer | null
    try {
      buf = await readKnownFile(
        path.join(attachmentsDir, name),
        MAX_ATTACHMENT_BYTES
      )
    } catch {
      buf = null
    }
    if (buf === null) {
      missing.push(name)
      continue
    }
    const mediaType = mediaTypeFor(name)
    loaded.push({
      ref: { name, contentType: mediaType, size: buf.length },
      attachment: {
        kind: mediaType.startsWith('image/') ? 'image' : 'pdf',
        name,
        mediaType,
        dataBase64: buf.toString('base64'),
      },
    })
  }
  return { loaded, missing }
}
