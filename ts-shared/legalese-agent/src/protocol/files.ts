/**
 * Files in a session folder (spec §4.2, §7.3, §8).
 *
 *   sessions/<sid>/
 *     session.json                  SessionFile          (Sessions API creates; harness updates)
 *     repo/                         git working tree
 *     attachments/<name>            prompt attachments
 *     state/lease.json              LeaseFile            (harness; temp file + rename)
 *     state/head.json               HeadFile             (harness; temp file + rename)
 *     state/events/<n>.jsonl        CloudEvent lines     (harness; append)
 *     state/commands.seq            decimal integer      (Sessions API)
 *     state/commands/<n>.json       CloudCommand         (Sessions API; exclusive create)
 *     state/git/main.bundle         bundle of main       (harness)
 *     state/git/incoming/<ulid>.bundle                   (Sessions API; exclusive create)
 *
 * Readers only open known names built from validated parts; they never
 * list directories (§7.2, §8).
 */
import {
  FILE_NAME_RE,
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
 * - `created`  — `POST /sessions` made the folder; no seed yet
 * - `ready`    — `POST /sessions/:sid/init` extracted the seed
 * - `active`   — a harness took the lease and is running
 * - `sleeping` — the harness exited after the idle timeout or a stop
 * - `parked`   — the key chain couldn't be renewed; needs a new chain
 */
export type SessionFileStatus =
  | 'created'
  | 'ready'
  | 'active'
  | 'sleeping'
  | 'parked'

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
  version: 1
  sessionId: string
  /** WorkOS user id of the owner; lets break-glass recovery attribute
   *  a folder (§4.3). */
  ownerUserId: string
  /** WorkOS organisation of the owner at creation, when known. */
  orgId?: string
  title: string
  /** Epoch ms. */
  created: number
  /** Epoch ms of the last command or turn activity. */
  lastActivity: number
  /** ai-proxy conversation id, set once the first turn gets one. */
  conversationId?: string
  status: SessionFileStatus
  /** Set with `status: 'parked'`. */
  parkedReason?: AgentKeyFailure
  /** The user's HTTP/SSE MCP servers — names and URLs only (§6.4). */
  mcpServers: McpServerConfig[]
}

export const SESSION_TITLE_MAX = 200

export const sessionFile: Check<SessionFile> = obj({
  version: literal(1),
  sessionId,
  ownerUserId: str({ min: 1, max: 128 }),
  orgId: optional(str({ min: 1, max: 128 })),
  title: str({ max: SESSION_TITLE_MAX }),
  created: epochMs,
  lastActivity: epochMs,
  conversationId: optional(opaqueId),
  status: literal('created', 'ready', 'active', 'sleeping', 'parked'),
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
  /** The running turn, while `busy` or `waiting`. */
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

/** Where the event log ends: segment `n` has `length` bytes. */
export interface HeadFile {
  segment: number
  length: number
}

export const headFile: Check<HeadFile> = obj({
  segment: int({ min: 0, max: 1_000_000 }),
  length: int({ min: 0, max: 64 * 1024 * 1024 }),
})

/**
 * An event cursor, `<segment>:<byteOffset>` (§8). `0:0` (or just `0`,
 * as `GET /events?s=<sid>:0` sends it) reads from the start.
 */
export interface EventCursor {
  segment: number
  offset: number
}

export const CURSOR_START: EventCursor = { segment: 0, offset: 0 }

export function formatCursor(c: EventCursor): string {
  return `${c.segment}:${c.offset}`
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
export function sessionPaths(sid: string): {
  dir: string
  sessionJson: string
  repo: string
  attachments: string
  attachment: (name: string) => string
  state: string
  lease: string
  head: string
  eventSegment: (n: number) => string
  commandSeq: string
  command: (n: number) => string
  mainBundle: string
  incomingBundle: (name: string) => string
} {
  if (!ULID_RE.test(sid)) throw new Error('invalid session id')
  const dir = `sessions/${sid}`
  const state = `${dir}/state`
  return {
    dir,
    sessionJson: `${dir}/session.json`,
    repo: `${dir}/repo`,
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
