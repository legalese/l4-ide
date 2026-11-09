import {
  ProtocolError,
  arr,
  int,
  literal,
  obj,
  optional,
  str,
  type Check,
} from './validate.js'

/** Session ids are ULIDs: 26 characters of Crockford base32 (§15.5);
 *  the first is 0–7 (48-bit timestamp). */
export const ULID_RE = /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/

export function isSessionId(value: unknown): value is string {
  return typeof value === 'string' && ULID_RE.test(value)
}

/** WorkOS user-scoped API keys as handed to a task in `AGENT_KEY`. */
export const AGENT_KEY_RE = /^sk_[A-Za-z0-9_-]{8,512}$/

/** Conversation / turn / call ids minted by clients, the proxy or the
 *  model: opaque, but bounded and path-safe. */
export const OPAQUE_ID_RE = /^[A-Za-z0-9_.:-]{1,128}$/

/** Plain file names (attachments): no separators, no leading dot. */
export const FILE_NAME_RE = /^(?!\.)[^/\\\0\r\n]{1,255}$/

export const sessionId: Check<string> = str({ pattern: ULID_RE })
export const opaqueId: Check<string> = str({ pattern: OPAQUE_ID_RE })
export const fileName: Check<string> = str({ pattern: FILE_NAME_RE })
/** Epoch milliseconds — every timestamp in the protocol (§15.5). */
export const epochMs: Check<number> = int({ min: 0 })

/**
 * Session states as the Sessions API derives them (§7.3). `running`,
 * `busy` and `waiting` need a live lease; `parked` comes from
 * `session.json`. `waiting` means a turn is blocked on an `ask-user`
 * question (there are no tool approvals in cloud sessions).
 */
export type SessionState =
  | 'sleeping'
  | 'starting'
  | 'running'
  | 'busy'
  | 'waiting'
  | 'parked'

export const SESSION_STATES: readonly SessionState[] = [
  'sleeping',
  'starting',
  'running',
  'busy',
  'waiting',
  'parked',
]

export const sessionState: Check<SessionState> = literal(...SESSION_STATES)

/** A user's HTTP / SSE MCP server as passed to a cloud session (§6.4).
 *  Names, URLs and enabled tools only — never secrets. */
export interface McpServerConfig {
  /** Unique within the session; tools appear as `vsmcp__<name>__<tool>`. */
  name: string
  url: string
  /** Default `http` (streamable HTTP). */
  transport?: 'http' | 'sse'
  /** Tools the user enabled; absent = all. */
  enabledTools?: string[]
}

export const MCP_SERVER_NAME_RE = /^[A-Za-z0-9_-]{1,64}$/

export const mcpServerConfig: Check<McpServerConfig> = obj({
  name: str({ pattern: MCP_SERVER_NAME_RE }),
  url: str({ max: 2048, pattern: /^https:\/\/[^\s]+$/ }),
  transport: optional(literal('http', 'sse')),
  enabledTools: optional(arr(str({ min: 1, max: 256 }), { max: 1000 })),
})

/** A prompt attachment, stored in the session's `attachments/` folder
 *  (outside the git repo). */
export interface AttachmentRef {
  name: string
  contentType: string
  /** Bytes. */
  size: number
}

/** Attachments are capped at 10 MB, the seed at 50 MB (§10). */
export const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024
export const MAX_SEED_BYTES = 50 * 1024 * 1024

export const attachmentRef: Check<AttachmentRef> = obj({
  name: str({ pattern: FILE_NAME_RE }),
  contentType: str({ min: 1, max: 255, pattern: /^[\w.+-]+\/[\w.+-]+$/ }),
  size: int({ min: 0, max: MAX_ATTACHMENT_BYTES }),
})

/**
 * Where the seed came from on the user's machine, so every machine maps
 * local files to the same `data/` paths: a local file at
 * `<workspace folder named workspaceFolder>/<path>/<rel>` is
 * `data/<rel>` in the session.
 */
export interface SeedBase {
  /** The VS Code workspace folder's NAME (not a path). */
  workspaceFolder: string
  /** The base, relative to that folder, `/`-separated; `''` for the
   *  folder root. */
  path: string
}

export const seedBase: Check<SeedBase> = (v, path) => {
  const out = obj({
    workspaceFolder: str({ min: 1, max: 255, pattern: /^[^\0\r\n/\\]+$/ }),
    path: str({ max: 1024 }),
  })(v, path)
  const p = out.path
  if (p !== '') {
    const parts = p.split('/')
    if (
      /^[A-Za-z]:/.test(p) ||
      parts.some(
        (x) =>
          x === '' ||
          x === '.' ||
          x === '..' ||
          x.length > 255 ||
          /[\0\r\n\\]/.test(x)
      )
    ) {
      throw new ProtocolError(
        'expected a relative /-separated path without . or ..',
        `${path}.path`
      )
    }
  }
  if (out.workspaceFolder === '.' || out.workspaceFolder === '..') {
    throw new ProtocolError(
      'invalid workspace folder name',
      `${path}.workspaceFolder`
    )
  }
  return out
}
