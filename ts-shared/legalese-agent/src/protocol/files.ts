/**
 * Files in a session folder (spec §4.2, §7.3, §8).
 *
 *   sessions/<sid>/
 *     session.json                  SessionFile          (Sessions API creates; harness updates)
 *     repo/                         git root: the model's workspace root
 *       data/                       the session files (seed lands here; jl4-lsp --cwd)
 *       tmp/                        the model's scratch space (committed like the rest)
 *         deleted/t-<turnId>/<path> copies of data/ files the agent deleted in a turn
 *       .legalese/                  reserved for metadata; the model may not write here
 *     attachments/<name>            prompt attachments
 *     state/lease.json              LeaseFile            (harness; temp file + rename)
 *     state/head.json               HeadFile             (harness; temp file + rename)
 *     state/events/<n>.jsonl        CloudEvent lines     (harness; append)
 *     state/commands.seq            decimal integer      (Sessions API)
 *     state/commands/<n>.json       CloudCommand         (Sessions API; exclusive create)
 *     state/git/main.bundle         bundle of main       (harness)
 *     state/git/incoming/<ulid>.bundle                   (Sessions API; exclusive create)
 *     state/init.json, state/stop-requested.json, state/git/local.json
 *                                   Sessions API bookkeeping; the harness ignores them
 *
 * Readers only open known names built from validated parts; they never
 * list directories (§7.2, §8).
 */
import {
  FILE_NAME_RE,
  OPAQUE_ID_RE,
  ULID_RE,
  epochMs,
  mcpServerConfig,
  opaqueId,
  sessionId,
  type McpServerConfig,
} from './common.js'
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

// ── session.json ──────────────────────────────────────────────────────

/**
 * What `session.json` says about the session's lifecycle. The state the
 * user sees is derived (§7.3); only `parked` here changes it.
 *
 * - `new`      — written by `POST /sessions`; no harness has run yet
 * - `running`  — a harness took the lease (written by the harness)
 * - `sleeping` — the harness exited after the idle timeout or a stop
 * - `parked`   — the key chain couldn't be renewed; needs a new chain
 */
export type SessionFileStatus = 'new' | 'running' | 'sleeping' | 'parked'

/** Why a session is parked or needs auth (renew errors, §15.5). */
export type AgentKeyFailure =
  | 'invalid_key'
  | 'chain_expired'
  | 'inactive'
  | 'chain_forked'

export const AGENT_KEY_FAILURES: readonly AgentKeyFailure[] = [
  'invalid_key',
  'chain_expired',
  'inactive',
  'chain_forked',
]

export interface SessionFile {
  sessionId: string
  /** WorkOS user id of the owner; lets break-glass recovery attribute
   *  a folder (§4.3). */
  ownerUserId: string
  /** WorkOS organisation of the owner at creation, when known
   *  (`null` in the file reads as absent). */
  orgId?: string
  title: string
  /** Epoch ms. */
  created: number
  /** Epoch ms of the last command or turn activity. */
  lastActivity: number
  /** ai-proxy conversation id, set once the first turn gets one. The
   *  Sessions API writes `null` until then, which reads as absent. */
  conversationId?: string
  status: SessionFileStatus
  /** Set with `status: 'parked'`. */
  parkedReason?: AgentKeyFailure
  /** The user's HTTP/SSE MCP servers — names and URLs only (§6.4). */
  mcpServers: McpServerConfig[]
}

export const SESSION_TITLE_MAX = 200

export const sessionFile: Check<SessionFile> = obj({
  sessionId,
  ownerUserId: str({ min: 1, max: 128 }),
  orgId: optional(str({ min: 1, max: 128 })),
  title: str({ max: SESSION_TITLE_MAX }),
  created: epochMs,
  lastActivity: epochMs,
  conversationId: optional(opaqueId),
  status: literal('new', 'running', 'sleeping', 'parked'),
  parkedReason: optional(
    literal('invalid_key', 'chain_expired', 'inactive', 'chain_forked')
  ),
  mcpServers: (v, path) => {
    const servers = arr(mcpServerConfig, { max: 32 })(v, path)
    const seen = new Set<string>()
    for (const s of servers) {
      if (seen.has(s.name)) {
        throw new ProtocolError(`duplicate MCP server name ${s.name}`, path)
      }
      seen.add(s.name)
    }
    return servers
  },
})

// ── state/lease.json ──────────────────────────────────────────────────

/** Lease validity and renewal cadence (§7.3). */
export const LEASE_TTL_MS = 90_000
export const LEASE_RENEW_MS = 30_000

export type LeaseState = 'running' | 'busy' | 'waiting'

/** Written by the running harness every 30 s (temp file + rename). */
export interface LeaseFile {
  /** ECS task id (or `dev-<pid>` in --dev mode). */
  taskId: string
  state: LeaseState
  /** The running turn, while `busy` or `waiting` (`waiting` = a
   *  pending `ask-user` question). */
  turnId?: string
  /** Epoch ms; the lease is dead after this. */
  expiresAt: number
}

export const leaseFile: Check<LeaseFile> = obj({
  taskId: str({ min: 1, max: 128, pattern: /^[A-Za-z0-9_.:/-]+$/ }),
  state: literal('running', 'busy', 'waiting'),
  turnId: optional(opaqueId),
  expiresAt: epochMs,
})

export function isLeaseLive(lease: LeaseFile, now = Date.now()): boolean {
  return lease.expiresAt > now
}

// ── state/head.json and events ────────────────────────────────────────

/** The harness starts a new event segment past this size (§8). */
export const EVENT_SEGMENT_MAX_BYTES = 1024 * 1024

/** Event segments are `state/events/<n>.jsonl`, numbered from 1. */
export const FIRST_EVENT_SEGMENT = 1

/** Where the event log ends: segment `n` has `length` bytes. Absent
 *  until the harness writes its first event. */
export interface HeadFile {
  segment: number
  length: number
}

export const headFile: Check<HeadFile> = obj({
  segment: int({ min: FIRST_EVENT_SEGMENT, max: 1_000_000 }),
  length: int({ min: 0, max: 64 * 1024 * 1024 }),
})

/**
 * An event cursor, `<segment>:<byteOffset>` (§8). `0` (segment 0,
 * before the first segment) reads from the start: `GET /events?s=<sid>:0`.
 */
export interface EventCursor {
  segment: number
  offset: number
}

export const CURSOR_START: EventCursor = { segment: 0, offset: 0 }

export function formatCursor(c: EventCursor): string {
  return c.segment === 0 && c.offset === 0 ? '0' : `${c.segment}:${c.offset}`
}

/** Parse a cursor; `null` when malformed. */
export function parseCursor(text: string): EventCursor | null {
  const m = /^(\d{1,7})(?::(\d{1,9}))?$/.exec(text)
  if (!m) return null
  return {
    segment: Number(m[1]),
    offset: m[2] === undefined ? 0 : Number(m[2]),
  }
}

// ── state/commands.seq ────────────────────────────────────────────────

/** `commands.seq` holds the highest command number issued, as a
 *  decimal integer and a newline. Commands are numbered from 1. */
export function formatCommandSeq(n: number): string {
  if (!Number.isSafeInteger(n) || n < 0) throw new Error('invalid sequence')
  return `${n}\n`
}

/** Parse `commands.seq`; `null` when malformed. A missing file means 0. */
export function parseCommandSeq(text: string): number | null {
  const m = /^\s*(\d{1,12})\s*$/.exec(text)
  return m ? Number(m[1]) : null
}

// ── Paths ─────────────────────────────────────────────────────────────

const BUNDLE_NAME_RE = new RegExp(`^${ULID_RE.source.slice(1, -1)}\\.bundle$`)

export function isIncomingBundleName(name: unknown): name is string {
  return typeof name === 'string' && BUNDLE_NAME_RE.test(name)
}

function nonNegInt(n: number, what: string): number {
  if (!Number.isSafeInteger(n) || n < 0) throw new Error(`invalid ${what}`)
  return n
}

/**
 * Paths of a session's files, relative to the user's folder (the
 * access-point root, `/workspace` in the task). Every part is validated,
 * so the result never escapes `sessions/<sid>/`.
 */
// ── Repository layout ────────────────────────────────────────────────

/** Directories at the root of `repo/`, relative to it (the model's
 *  workspace root). */
export const REPO_DATA_DIR = 'data'
export const REPO_TMP_DIR = 'tmp'
export const REPO_DELETED_DIR = 'tmp/deleted'
export const REPO_RESERVED_DIR = '.legalese'

/**
 * The Sessions API sweep clears `repo/tmp/` of sessions whose
 * `session.json` `lastActivity` is older than this many days (while no
 * task runs); the harness commits the deletion on its next start.
 */
export const ABANDONED_TMP_DAYS = 30
export const ABANDONED_TMP_MS = ABANDONED_TMP_DAYS * 24 * 60 * 60 * 1000

/** Validate a relative path (`/`-separated, no `.`/`..`/empty parts). */
function relativePath(p: string, what: string): string {
  const parts = p.split('/')
  if (
    p.length === 0 ||
    p.length > 4096 ||
    p.includes('\0') ||
    parts.some((x) => x === '' || x === '.' || x === '..')
  ) {
    throw new Error(`invalid ${what}`)
  }
  return p
}

/** Where a deleted `data/` file is copied, relative to `repo/`:
 *  `tmp/deleted/t-<turnId>/<path under data/>`. */
export function deletedCopyPath(turnId: string, pathUnderData: string): string {
  if (!OPAQUE_ID_RE.test(turnId)) throw new Error('invalid turn id')
  return `${REPO_DELETED_DIR}/t-${turnId}/${relativePath(pathUnderData, 'path under data/')}`
}

/** Is a path (relative to `repo/`) inside the reserved `.legalese/`? */
export function isReservedRepoPath(pathInRepo: string): boolean {
  const first = pathInRepo.replace(/^\.\/+/, '').split('/')[0]
  return first === REPO_RESERVED_DIR
}

export function sessionPaths(sid: string): {
  dir: string
  sessionJson: string
  /** Git root and the model's workspace root. */
  repo: string
  /** `repo/data/`: the session files (seed target, jl4-lsp `--cwd`). */
  repoData: string
  /** `repo/tmp/`: the model's scratch space. */
  repoTmp: string
  /** `repo/tmp/deleted/`: copies of deleted `data/` files. */
  repoDeleted: string
  /** `repo/tmp/deleted/t-<turnId>/<path under data/>`. */
  deletedCopy: (turnId: string, pathUnderData: string) => string
  /** `repo/.legalese/`: reserved. */
  repoReserved: string
  attachments: string
  attachment: (name: string) => string
  state: string
  lease: string
  head: string
  eventSegment: (n: number) => string
  commandSeq: string
  command: (n: number) => string
  mainBundle: string
  /** Sessions API-owned bookkeeping; the harness ignores these. */
  initMarker: string
  stopRequested: string
  gitLocal: string
  incomingBundle: (name: string) => string
} {
  if (!ULID_RE.test(sid)) throw new Error('invalid session id')
  const dir = `sessions/${sid}`
  const state = `${dir}/state`
  return {
    dir,
    sessionJson: `${dir}/session.json`,
    repo: `${dir}/repo`,
    repoData: `${dir}/repo/${REPO_DATA_DIR}`,
    repoTmp: `${dir}/repo/${REPO_TMP_DIR}`,
    repoDeleted: `${dir}/repo/${REPO_DELETED_DIR}`,
    deletedCopy: (turnId, pathUnderData) =>
      `${dir}/repo/${deletedCopyPath(turnId, pathUnderData)}`,
    repoReserved: `${dir}/repo/${REPO_RESERVED_DIR}`,
    attachments: `${dir}/attachments`,
    attachment: (name) => {
      if (!FILE_NAME_RE.test(name)) {
        throw new Error('invalid attachment name')
      }
      return `${dir}/attachments/${name}`
    },
    state,
    lease: `${state}/lease.json`,
    head: `${state}/head.json`,
    eventSegment: (n) => `${state}/events/${nonNegInt(n, 'segment')}.jsonl`,
    commandSeq: `${state}/commands.seq`,
    command: (n) => `${state}/commands/${nonNegInt(n, 'command number')}.json`,
    mainBundle: `${state}/git/main.bundle`,
    initMarker: `${state}/init.json`,
    stopRequested: `${state}/stop-requested.json`,
    gitLocal: `${state}/git/local.json`,
    incomingBundle: (name) => {
      if (!isIncomingBundleName(name)) throw new Error('invalid bundle name')
      return `${state}/git/incoming/${name}`
    },
  }
}

/** Parse `session.json` text (throws {@link ProtocolError}). */
export function parseSessionFile(text: string): SessionFile {
  return sessionFile(parseJsonText(text), 'session.json')
}

export function parseLeaseFile(text: string): LeaseFile {
  return leaseFile(parseJsonText(text), 'lease.json')
}

export function parseHeadFile(text: string): HeadFile {
  return headFile(parseJsonText(text), 'head.json')
}

export function parseJsonText(text: string): unknown {
  try {
    return JSON.parse(text) as unknown
  } catch {
    throw new ProtocolError('not valid JSON', '')
  }
}
