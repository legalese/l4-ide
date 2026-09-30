/**
 * Events: what a cloud session's harness appends to
 * `state/events/<n>.jsonl`, one JSON object per line, and what
 * `GET /events` returns (spec §8).
 *
 * Every event is `{ seq, ts, type, … }`. The `type`s are the
 * {@link ChatServiceEvent} kinds (payload = the chat event minus `kind`)
 * plus the cloud-only ones below.
 *
 * Cloud sessions never ask for tool approval: every tool call runs
 * (file changes are committed per turn and can be rolled back; MCP
 * servers passed at start count as approved). So there is no
 * approval event or command, and `tool-call` events never carry
 * `status: 'pending-approval'`. Only `ask-user` questions wait.
 */
import type { ChatServiceEvent } from '../events.js'
import {
  attachmentRef,
  epochMs,
  opaqueId,
  sessionState,
  type AttachmentRef,
  type SessionState,
} from './common.js'
import type { AgentKeyFailure } from './files.js'
import {
  ProtocolError,
  arr,
  int,
  json,
  literal,
  obj,
  optional,
  str,
  union,
  type Check,
} from './validate.js'

/** Fields every event carries. */
export interface EventEnvelope {
  /** 1-based, strictly increasing within a session. */
  seq: number
  /** Epoch ms when the harness wrote it. */
  ts: number
}

type ToPayload<E> = E extends { kind: infer K }
  ? { type: K } & Omit<E, 'kind'>
  : never

/** A {@link ChatServiceEvent} as an event payload: `kind` → `type`. */
export type ChatEventPayload = ToPayload<ChatServiceEvent>

/** Git commit ids (SHA-1 or SHA-256). */
export const GIT_SHA_RE = /^[0-9a-f]{40}(?:[0-9a-f]{24})?$/

/** Cloud-only event payloads. */
export type CloudOnlyEventPayload =
  /** A user prompt the harness accepted — lets observers render turns
   *  they didn't start. */
  | {
      type: 'user-message'
      turnId: string
      text: string
      attachments: AttachmentRef[]
    }
  /** A `meta__ask_user` question waiting for an `answer` command. */
  | {
      type: 'ask-user'
      conversationId: string
      turnId: string
      callId: string
      question: string
      choices?: string[]
    }
  /** Lifecycle. While `running`, carries the sealing public key for
   *  `mcp-credentials` (§6.4). */
  | {
      type: 'session-state'
      state: SessionState
      /** Raw X25519 public key, base64url (see `sealed.ts`). */
      publicKey?: string
    }
  | { type: 'git-committed'; turnId: string; sha: string; parent: string }
  | { type: 'rolled-back'; turnId: string; sha: string }
  | { type: 'local-merged'; sha: string }
  | { type: 'local-merge-conflict'; files: string[] }
  /** The key chain failed (`reason` = the renew error), or an MCP
   *  server's token expired (`reason: 'mcp'`, with `server`). */
  | {
      type: 'auth-required'
      reason: AgentKeyFailure | 'mcp'
      server?: string
    }

export type CloudEventPayload = ChatEventPayload | CloudOnlyEventPayload
export type CloudEvent = EventEnvelope & CloudEventPayload
export type CloudEventType = CloudEvent['type']

// ── Validators ────────────────────────────────────────────────────────

const text: Check<string> = str({ max: 1_000_000 })
const conversationId = opaqueId
const sha: Check<string> = str({ pattern: GIT_SHA_RE })
const toolStatus = literal('running', 'done', 'error')

type Payload<T extends CloudEventType> = Extract<CloudEventPayload, { type: T }>

const payloads: { [T in CloudEventType]: Check<Payload<T>> } = {
  started: obj({
    type: literal('started'),
    conversationId,
    turnId: opaqueId,
    model: str({ max: 256 }),
  }),
  'text-delta': obj({ type: literal('text-delta'), conversationId, text }),
  'thinking-delta': obj({
    type: literal('thinking-delta'),
    conversationId,
    text,
  }),
  'tool-activity': obj({
    type: literal('tool-activity'),
    conversationId,
    tool: str({ max: 256 }),
    status: toolStatus,
    label: optional(str({ max: 256 })),
    message: text,
    input: optional(json()),
    output: optional(json()),
    ruleId: optional(str({ max: 512 })),
    deploymentId: optional(str({ max: 256 })),
    error: optional(text),
    sources: optional(
      arr(
        obj({ url: str({ max: 4096 }), title: optional(str({ max: 1024 })) }),
        { max: 200 }
      )
    ),
  }),
  'tool-call': obj({
    type: literal('tool-call'),
    conversationId,
    callId: opaqueId,
    name: str({ max: 256 }),
    argsJson: text,
    status: literal('pending-approval', 'running', 'done', 'error'),
    result: optional(text),
    error: optional(text),
    ruleFnName: optional(str({ max: 512 })),
    deploymentId: optional(str({ max: 256 })),
  }),
  done: obj({
    type: literal('done'),
    conversationId,
    finishReason: str({ max: 64 }),
    usage: optional(obj({ promptTokens: int(), completionTokens: int() })),
  }),
  error: obj({
    type: literal('error'),
    conversationId,
    message: text,
    code: optional(str({ max: 128 })),
  }),
  'turn-spawn': obj({
    type: literal('turn-spawn'),
    conversationId,
    subTurnId: opaqueId,
  }),
  'queue-consumed': obj({
    type: literal('queue-consumed'),
    conversationId,
    injectionIds: arr(opaqueId, { max: 1000 }),
  }),
  'user-message': obj({
    type: literal('user-message'),
    turnId: opaqueId,
    text,
    attachments: arr(attachmentRef, { max: 50 }),
  }),
  'ask-user': obj({
    type: literal('ask-user'),
    conversationId,
    turnId: opaqueId,
    callId: opaqueId,
    question: text,
    choices: optional(arr(str({ max: 4096 }), { max: 50 })),
  }),
  'session-state': obj({
    type: literal('session-state'),
    state: sessionState,
    publicKey: optional(str({ min: 43, max: 43, pattern: /^[A-Za-z0-9_-]+$/ })),
  }),
  'git-committed': obj({
    type: literal('git-committed'),
    turnId: opaqueId,
    sha,
    parent: sha,
  }),
  'rolled-back': obj({ type: literal('rolled-back'), turnId: opaqueId, sha }),
  'local-merged': obj({ type: literal('local-merged'), sha }),
  'local-merge-conflict': obj({
    type: literal('local-merge-conflict'),
    files: arr(str({ min: 1, max: 4096 }), { max: 1000 }),
  }),
  'auth-required': obj({
    type: literal('auth-required'),
    reason: literal(
      'invalid_key',
      'chain_expired',
      'inactive',
      'chain_forked',
      'mcp'
    ),
    server: optional(str({ max: 64 })),
  }),
}

export const CLOUD_EVENT_TYPES = Object.keys(payloads) as CloudEventType[]

const envelope: Check<EventEnvelope> = obj({
  seq: int({ min: 1 }),
  ts: epochMs,
})

const payload: Check<CloudEventPayload> = union(
  'type',
  payloads as Record<string, Check<CloudEventPayload>>
)

/** Validate one event (throws {@link ProtocolError}). */
export const cloudEvent: Check<CloudEvent> = (v, path) => ({
  ...envelope(v, path),
  ...payload(v, path),
})

export function parseCloudEvent(value: unknown): CloudEvent {
  return cloudEvent(value, 'event')
}

// ── Chat events ⇄ cloud events ────────────────────────────────────────

/** Turn a chat-service event into an event payload. */
export function chatEventToPayload(event: ChatServiceEvent): ChatEventPayload {
  const { kind, ...rest } = event
  return { type: kind, ...rest } as ChatEventPayload
}

const CHAT_KINDS: ReadonlySet<string> = new Set<ChatServiceEvent['kind']>([
  'started',
  'text-delta',
  'thinking-delta',
  'tool-activity',
  'tool-call',
  'done',
  'error',
  'turn-spawn',
  'queue-consumed',
])

/** The chat-service event inside a cloud event, or `null` for
 *  cloud-only types. */
export function cloudEventToChatEvent(
  event: CloudEvent
): ChatServiceEvent | null {
  if (!CHAT_KINDS.has(event.type)) return null
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  const { seq, ts, type, ...rest } = event
  return { kind: type, ...rest } as ChatServiceEvent
}

// ── JSONL ─────────────────────────────────────────────────────────────

/** One event as a JSONL line (with the trailing newline). */
export function formatEventLine(event: CloudEvent): string {
  return JSON.stringify(event) + '\n'
}

/**
 * Parse the complete lines at the start of `chunk` (bytes read from a
 * segment at some offset). Returns the events, how many bytes the
 * complete lines took (advance the cursor by this much), and how many
 * lines were skipped as invalid. A trailing partial line is left for
 * the next read.
 */
export function parseEventChunk(chunk: Uint8Array): {
  events: CloudEvent[]
  bytes: number
  invalid: number
} {
  const buf = Buffer.from(chunk.buffer, chunk.byteOffset, chunk.byteLength)
  const end = buf.lastIndexOf(0x0a)
  if (end < 0) return { events: [], bytes: 0, invalid: 0 }
  const events: CloudEvent[] = []
  let invalid = 0
  for (const line of buf.subarray(0, end).toString('utf8').split('\n')) {
    if (!line.trim()) continue
    try {
      events.push(parseCloudEvent(JSON.parse(line) as unknown))
    } catch (err) {
      if (!(err instanceof ProtocolError) && !(err instanceof SyntaxError)) {
        throw err
      }
      invalid++
    }
  }
  return { events, bytes: end + 1, invalid }
}
