/**
 * HTTP contracts: the Sessions API (spec §7.1, §15.5) and the
 * jl4-auth-proxy access-token and agent-key routes (§6.1, §6.2, §15.5).
 * `expiresAt` is epoch milliseconds everywhere.
 */
import {
  AGENT_KEY_RE,
  MAX_SEED_BYTES,
  attachmentRef,
  epochMs,
  mcpServerConfig,
  sessionId,
  sessionState,
  type AttachmentRef,
  type McpServerConfig,
  type SessionState,
} from './common.js'
import { cloudEvent, type CloudEvent } from './events.js'
import {
  SESSION_TITLE_MAX,
  formatCursor,
  parseCursor,
  sessionFile,
  type AgentKeyFailure,
  type EventCursor,
  type SessionFile,
} from './files.js'
import {
  ProtocolError,
  arr,
  bool,
  int,
  literal,
  obj,
  optional,
  str,
  stringMap,
  type Check,
} from './validate.js'

// ── Errors ────────────────────────────────────────────────────────────

/** The §15.5 Sessions API error codes; the body is `{ error: code }`. */
export type SessionsApiErrorCode =
  | 'bad_request'
  | 'unauthenticated'
  | 'forbidden'
  | 'not_found'
  | 'conflict'
  | 'too_large'

export const SESSIONS_API_ERROR_STATUS: Record<SessionsApiErrorCode, number> = {
  bad_request: 400,
  unauthenticated: 401,
  forbidden: 403,
  not_found: 404,
  conflict: 409,
  too_large: 413,
}

/** More specific codes the Sessions API also returns (jl4-auth-proxy
 *  `cloud-sessions-api`). Clients branch on the HTTP status and treat
 *  these as detail. */
export type SessionsApiDetailCode =
  | 'not_initialized'
  | 'already_initialized'
  | 'too_many_sessions'
  | 'invalid_seed'
  | 'stopping'
  | 'start_failed'
  | 'unavailable'
  | 'internal'

export interface ApiError {
  error: string
}

export const apiError: Check<ApiError> = obj({ error: str({ max: 128 }) })

// ── Sessions API ──────────────────────────────────────────────────────

const gitUrl: Check<string> = str({
  max: 2048,
  pattern: /^https?:\/\/[^\s]+\.git$/,
})

/** A pre-signed, size-bound upload into `inbox/<sid>/`. */
export interface PresignedUpload {
  url: string
  method: 'PUT'
  /** Headers the PUT must carry (content type / length conditions). */
  headers: Record<string, string>
  maxBytes?: number
}

const presignedUpload: Check<PresignedUpload> = obj({
  url: str({ max: 8192, pattern: /^https:\/\// }),
  method: literal('PUT'),
  headers: stringMap(),
  maxBytes: optional(int({ min: 0 })),
})

/** `POST /sessions`. */
export interface CreateSessionRequest {
  title?: string
  mcpServers?: McpServerConfig[]
  /** Bytes of the seed tarball (`seed.tar.gz`), so its upload URL can
   *  be size-bound. */
  seedSize?: number
  attachments?: AttachmentRef[]
}

export const createSessionRequest: Check<CreateSessionRequest> = obj({
  title: optional(str({ max: SESSION_TITLE_MAX })),
  mcpServers: optional(arr(mcpServerConfig, { max: 32 })),
  seedSize: optional(int({ min: 0, max: MAX_SEED_BYTES })),
  attachments: optional(arr(attachmentRef, { max: 50 })),
})

export interface CreateSessionResponse {
  sessionId: string
  /** `<apiUrl>/git/<sid>.git` */
  gitUrl: string
  uploads: {
    seed: PresignedUpload
    attachments: Array<{ name: string } & PresignedUpload>
  }
}

export const createSessionResponse: Check<CreateSessionResponse> = obj({
  sessionId,
  gitUrl,
  uploads: obj({
    seed: presignedUpload,
    attachments: arr(
      (v, path) => ({
        ...obj({ name: str({ max: 255 }) })(v, path),
        ...presignedUpload(v, path),
      }),
      { max: 50 }
    ),
  }),
})

/** `POST /sessions/:sid/init`, `/start` (202), `/stop`: the session's
 *  state. `DELETE /sessions/:sid` answers 204. */
export interface SessionStateResponse {
  state: SessionState
}

export const sessionStateResponse: Check<SessionStateResponse> = obj({
  state: sessionState,
})

/** A row of `GET /sessions` (the history view, §12.1). */
export interface SessionSummary {
  sessionId: string
  title: string
  created: number
  lastActivity: number
  state: SessionState
}

const sessionSummary: Check<SessionSummary> = obj({
  sessionId,
  title: str({ max: SESSION_TITLE_MAX }),
  created: epochMs,
  lastActivity: epochMs,
  state: sessionState,
})

export interface ListSessionsResponse {
  sessions: SessionSummary[]
}

export const listSessionsResponse: Check<ListSessionsResponse> = obj({
  sessions: arr(sessionSummary, { max: 10_000 }),
})

/** `GET /sessions/:sid`. */
export interface GetSessionResponse {
  sessionId: string
  session: SessionFile
  state: SessionState
  gitUrl: string
}

export const getSessionResponse: Check<GetSessionResponse> = obj({
  sessionId,
  session: sessionFile,
  state: sessionState,
  gitUrl,
})

/** `POST /sessions/:sid/start`. Responds `202 { state }`. */
export interface StartSessionRequest {
  agentKey: string
}

export const startSessionRequest: Check<StartSessionRequest> = obj({
  agentKey: str({ pattern: AGENT_KEY_RE }),
})

/** `POST /sessions/:sid/commands` — body is a client command
 *  (`clientCommand` in commands.ts). */
export interface PostCommandResponse {
  commandId: number
  state: SessionState
}

export const postCommandResponse: Check<PostCommandResponse> = obj({
  commandId: int({ min: 1 }),
  state: sessionState,
})

/** `GET /events` takes up to this many `s=<sid>:<cursor>` params. */
export const MAX_EVENT_STREAMS = 10

export interface EventStreamRequest {
  sessionId: string
  cursor: EventCursor
}

/** Build the `GET /events` query string (without `?`). */
export function formatEventsQuery(streams: EventStreamRequest[]): string {
  if (streams.length > MAX_EVENT_STREAMS) {
    throw new Error(`at most ${MAX_EVENT_STREAMS} sessions per call`)
  }
  return streams
    .map(
      (s) =>
        `s=${encodeURIComponent(`${s.sessionId}:${formatCursor(s.cursor)}`)}`
    )
    .join('&')
}

/** Parse the `s` values of a `GET /events` query (throws
 *  {@link ProtocolError}). Duplicate sessions are rejected. */
export function parseEventsQuery(values: string[]): EventStreamRequest[] {
  if (values.length === 0) throw new ProtocolError('missing s', 's')
  if (values.length > MAX_EVENT_STREAMS) {
    throw new ProtocolError(`more than ${MAX_EVENT_STREAMS} sessions`, 's')
  }
  const seen = new Set<string>()
  return values.map((v, i) => {
    const sep = v.indexOf(':')
    const sid = sep < 0 ? v : v.slice(0, sep)
    const cursor = parseCursor(sep < 0 ? '0' : v.slice(sep + 1))
    sessionId(sid, `s[${i}]`)
    if (!cursor) throw new ProtocolError('invalid cursor', `s[${i}]`)
    if (seen.has(sid)) throw new ProtocolError('duplicate session', `s[${i}]`)
    seen.add(sid)
    return { sessionId: sid, cursor }
  })
}

export interface EventStreamResponse {
  sessionId: string
  events: CloudEvent[]
  /** Cursor to send next time (`<segment>:<offset>`). */
  cursor: string
  state: SessionState
  /** More events are ready: poll again without waiting. */
  more?: boolean
}

/** A session the caller asked for that couldn't be read (e.g.
 *  `not_found`). */
export interface EventStreamError {
  sessionId: string
  error: string
}

export interface EventsResponse {
  sessions: Array<EventStreamResponse | EventStreamError>
}

const cursorString: Check<string> = (v, path) => {
  if (typeof v !== 'string' || !parseCursor(v)) {
    throw new ProtocolError('invalid cursor', path)
  }
  return v
}

const eventStreamResponse: Check<EventStreamResponse> = obj({
  sessionId,
  events: arr(cloudEvent, { max: 100_000 }),
  cursor: cursorString,
  state: sessionState,
  more: optional(bool()),
})

const eventStreamError: Check<EventStreamError> = obj({
  sessionId,
  error: str({ max: 128 }),
})

function isErrorEntry(v: unknown): boolean {
  return typeof v === 'object' && v !== null && 'error' in v
}

/** Strict: any invalid event fails the whole response. */
export const eventsResponse: Check<EventsResponse> = obj({
  sessions: arr(
    (v, path): EventStreamResponse | EventStreamError =>
      isErrorEntry(v)
        ? eventStreamError(v, path)
        : eventStreamResponse(v, path),
    { max: MAX_EVENT_STREAMS }
  ),
})

/**
 * Lenient: validate one session's entry, dropping (and counting)
 * invalid events instead of failing — the harness writes them, and one
 * bad line shouldn't stall a client.
 */
export function parseEventStream(value: unknown): {
  stream: EventStreamResponse | EventStreamError
  dropped: number
} {
  if (isErrorEntry(value)) {
    return { stream: eventStreamError(value, 'stream'), dropped: 0 }
  }
  const raw = (value ?? {}) as { events?: unknown }
  const events: CloudEvent[] = []
  let dropped = 0
  for (const e of Array.isArray(raw.events) ? raw.events : []) {
    try {
      events.push(cloudEvent(e, 'event'))
    } catch (err) {
      if (!(err instanceof ProtocolError)) throw err
      dropped++
    }
  }
  const stream = eventStreamResponse({ ...raw, events: [] }, 'stream')
  return { stream: { ...stream, events }, dropped }
}

// ── jl4-auth-proxy: access token and agent keys (§6.1, §6.2) ─────────

/** `GET /auth/access-token` (sealed session) → 200. */
export interface AccessTokenResponse {
  /** WorkOS access token (JWT, ~5 minutes). */
  accessToken: string
  expiresAt: number
  /** A rotated sealed session, when jl4-auth-proxy refreshed it; store
   *  it in place of the old one. */
  token?: string
}

export const accessTokenResponse: Check<AccessTokenResponse> = obj({
  accessToken: str({ min: 1, max: 16_384 }),
  expiresAt: epochMs,
  token: optional(str({ min: 1, max: 16_384 })),
})

export const AGENT_KEY_PURPOSE = 'cloud-session'
/** Agent keys live 15 minutes; a chain at most 24 hours (§6.2). */
export const AGENT_KEY_LIFETIME_MS = 900_000
export const AGENT_KEY_CHAIN_MAX_MS = 24 * 60 * 60 * 1000
/** Renew when this much lifetime is left (§5.4). */
export const AGENT_KEY_RENEW_BEFORE_MS = 5 * 60 * 1000
/** Requested permissions (intersected with the user's). */
export const AGENT_KEY_PERMISSIONS = [
  'ai:chat',
  'l4:rules',
  'l4:evaluate',
  'l4:read',
] as const
/** Header the harness sends to ai-proxy on every request (§15.5). */
export const SESSION_HEADER = 'X-Legalese-Session'

/** `POST /auth/agent-token` (sealed session). */
export interface MintAgentKeyRequest {
  purpose: typeof AGENT_KEY_PURPOSE
  sessionId: string
}

export const mintAgentKeyRequest: Check<MintAgentKeyRequest> = obj({
  purpose: literal(AGENT_KEY_PURPOSE),
  sessionId,
})

export interface MintAgentKeyResponse {
  token: string
  id: string
  expiresAt: number
  permissions: string[]
}

const agentKeyToken: Check<string> = str({ pattern: AGENT_KEY_RE })

export const mintAgentKeyResponse: Check<MintAgentKeyResponse> = obj({
  token: agentKeyToken,
  id: str({ min: 1, max: 128 }),
  expiresAt: epochMs,
  permissions: arr(str({ min: 1, max: 64 }), { max: 64 }),
})

/** `POST /auth/agent-token/renew` (`Authorization: Bearer <key>`). */
export interface RenewAgentKeyResponse {
  token: string
  id: string
  expiresAt: number
}

export const renewAgentKeyResponse: Check<RenewAgentKeyResponse> = obj({
  token: agentKeyToken,
  id: str({ min: 1, max: 128 }),
  expiresAt: epochMs,
})

/**
 * Renew / end errors and their statuses (§15.5); `end` answers 204.
 * jl4-auth-proxy also answers `502 { error: "upstream_unavailable" }`
 * when WorkOS fails (the chain may be gone: park), and
 * `400 invalid_session_id` / `unknown_purpose` on a bad mint.
 */
export const AGENT_KEY_ERROR_STATUS: Record<AgentKeyFailure, number> = {
  invalid_key: 401,
  chain_expired: 403,
  inactive: 403,
  chain_forked: 409,
}

/** Classify a renew failure body; `null` when it isn't one we know. */
export function parseAgentKeyError(body: unknown): AgentKeyFailure | null {
  if (typeof body !== 'object' || body === null) return null
  const e = (body as { error?: unknown }).error
  return typeof e === 'string' &&
    Object.prototype.hasOwnProperty.call(AGENT_KEY_ERROR_STATUS, e)
    ? (e as AgentKeyFailure)
    : null
}

/** Key name for a chain: `cloud-session:<sid>:<chainStartEpochSeconds>`. */
export function agentKeyName(
  sid: string,
  chainStartEpochSeconds: number
): string {
  sessionId(sid, 'sessionId')
  if (
    !Number.isSafeInteger(chainStartEpochSeconds) ||
    chainStartEpochSeconds < 0
  ) {
    throw new Error('invalid chain start')
  }
  return `${AGENT_KEY_PURPOSE}:${sid}:${chainStartEpochSeconds}`
}

/** Parse a chain key name; `null` when it isn't one. */
export function parseAgentKeyName(
  name: string
): { sessionId: string; chainStartEpochSeconds: number } | null {
  const m = /^cloud-session:([0-7][0-9A-HJKMNP-TV-Z]{25}):(\d{1,12})$/.exec(
    name
  )
  if (!m) return null
  return { sessionId: m[1]!, chainStartEpochSeconds: Number(m[2]) }
}
