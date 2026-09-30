/**
 * Commands: what clients send with `POST /sessions/:sid/commands` and
 * the Sessions API stores as `state/commands/<n>.json` for the harness
 * to pick up (spec §8).
 */
import {
  FILE_NAME_RE,
  MCP_SERVER_NAME_RE,
  ULID_RE,
  epochMs,
  opaqueId,
} from './common.js'
import {
  isIncomingBundleName,
  isRepoDataPath,
  repoRelativePath,
} from './files.js'
import { sealedString } from './sealed.js'
import {
  ProtocolError,
  arr,
  int,
  literal,
  obj,
  optional,
  str,
  stringMap,
  union,
  type Check,
} from './validate.js'

/** At most this many files per `add-files` batch. */
export const MAX_BATCH_FILES = 500

/** A repo-relative path (validated like seed paths). */
export const repoPath: Check<string> = (v, path) => {
  if (typeof v !== 'string') throw new ProtocolError('expected a path', path)
  try {
    return repoRelativePath(v)
  } catch {
    throw new ProtocolError('invalid repo-relative path', path)
  }
}

/** A repo-relative path strictly inside `data/`. */
export const repoDataPath: Check<string> = (v, path) => {
  if (!isRepoDataPath(v)) {
    throw new ProtocolError('expected a path under data/', path)
  }
  return v
}

/** What the user referred to in a prompt: repo-relative paths (e.g.
 *  `data/rules/tax.l4`). Tells the model which files were meant. */
export interface MessageContext {
  /** The file open in the user's editor when they sent the prompt. */
  activeFile?: string
  /** @-mentioned files. */
  mentions?: string[]
}

export type CommandPayload =
  /** A new user prompt: starts turn `turnId`. `attachments` name files
   *  already in the session's `attachments/` folder. */
  | {
      type: 'message'
      turnId: string
      text: string
      attachments?: string[]
      context?: MessageContext
    }
  /** A message typed while turn `turnId` is running (see ChatService
   *  inject). `injectionId` is echoed in `queue-consumed`; the harness
   *  mints one when absent. */
  | { type: 'inject'; turnId: string; injectionId?: string; text: string }
  | { type: 'abort'; turnId: string }
  /** Answer to an `ask-user` event (`''` = skipped). */
  | { type: 'answer'; callId: string; answer: string }
  /** Restore the files to before turn `turnId` (§9.4). */
  | { type: 'rollback'; turnId: string }
  /** MCP credentials sealed to the running harness's key (§6.4), as
   *  `encodeSealed(seal(publicKey, JSON.stringify(creds),
   *  mcpCredentialsContext(sid)))`; the plaintext is {@link McpCredentials}. */
  | { type: 'mcp-credentials'; sealed: string }
  | { type: 'stop' }
  /** Merge `state/git/incoming/<file>` (§9.1). Issued by the Sessions
   *  API after an accepted push, never by clients. */
  | { type: 'apply-bundle'; file: string }
  /** Copy `incoming/files/<batchId>/<path>` into `repo/<path>` (§10).
   *  Issued by the Sessions API on `POST /sessions/:sid/files/:batchId/
   *  commit`, never by clients. */
  | { type: 'add-files'; batchId: string; files: Array<{ path: string }> }

export type CommandType = CommandPayload['type']

/** Fields the Sessions API adds when it stores a command. */
export interface CommandEnvelope {
  /** The command number `<n>` of `commands/<n>.json`, from 1. */
  id: number
  /** Epoch ms when the Sessions API stored it. */
  ts: number
}

export type CloudCommand = CommandEnvelope & CommandPayload

/** Plaintext of a sealed `mcp-credentials` command. */
export interface McpCredentials {
  servers: Array<{
    /** Matches a `session.json` `mcpServers[].name`. */
    name: string
    /** Headers to send, e.g. `{ Authorization: 'Bearer …' }`. */
    headers: Record<string, string>
    /** When the token expires (epoch ms), if known. */
    expiresAt?: number
  }>
}

// ── Validators ────────────────────────────────────────────────────────

const PROMPT_MAX = 200_000

type Payload<T extends CommandType> = Extract<CommandPayload, { type: T }>

const payloads: { [T in CommandType]: Check<Payload<T>> } = {
  message: obj({
    type: literal('message'),
    turnId: opaqueId,
    text: str({ max: PROMPT_MAX }),
    attachments: optional(arr(str({ pattern: FILE_NAME_RE }), { max: 50 })),
    context: optional(
      obj({
        activeFile: optional(repoPath),
        mentions: optional(arr(repoPath, { max: 200 })),
      })
    ),
  }),
  inject: obj({
    type: literal('inject'),
    turnId: opaqueId,
    injectionId: optional(opaqueId),
    text: str({ max: PROMPT_MAX }),
  }),
  abort: obj({ type: literal('abort'), turnId: opaqueId }),
  answer: obj({
    type: literal('answer'),
    callId: opaqueId,
    answer: str({ max: PROMPT_MAX }),
  }),
  rollback: obj({ type: literal('rollback'), turnId: opaqueId }),
  'mcp-credentials': obj({
    type: literal('mcp-credentials'),
    sealed: sealedString,
  }),
  stop: obj({ type: literal('stop') }),
  'apply-bundle': obj({
    type: literal('apply-bundle'),
    file: (v, path) => {
      if (!isIncomingBundleName(v)) {
        throw new ProtocolError('expected <ulid>.bundle', path)
      }
      return v
    },
  }),
  'add-files': obj({
    type: literal('add-files'),
    batchId: str({ pattern: ULID_RE }),
    files: arr(obj({ path: repoDataPath }), { max: MAX_BATCH_FILES }),
  }),
}

export const COMMAND_TYPES = Object.keys(payloads) as CommandType[]

/** Commands only the Sessions API issues. */
export const INTERNAL_COMMAND_TYPES: readonly CommandType[] = [
  'apply-bundle',
  'add-files',
]

/** Command types a client may send; `apply-bundle` and `add-files`
 *  are internal. */
export type ClientCommandPayload = Exclude<
  CommandPayload,
  { type: 'apply-bundle' | 'add-files' }
>

const commandPayload: Check<CommandPayload> = union(
  'type',
  payloads as Record<string, Check<CommandPayload>>
)

/** Validate a `POST /sessions/:sid/commands` body. */
export const clientCommand: Check<ClientCommandPayload> = (v, path) => {
  const c = commandPayload(v, path)
  if (c.type === 'apply-bundle' || c.type === 'add-files') {
    throw new ProtocolError(`${c.type} is not a client command`, path)
  }
  return c
}

const commandEnvelope: Check<CommandEnvelope> = obj({
  id: int({ min: 1 }),
  ts: epochMs,
})

/** Validate a stored command file. */
export const cloudCommand: Check<CloudCommand> = (v, path) => ({
  ...commandEnvelope(v, path),
  ...commandPayload(v, path),
})

export function parseCloudCommand(value: unknown): CloudCommand {
  return cloudCommand(value, 'command')
}

export const mcpCredentials: Check<McpCredentials> = obj({
  servers: arr(
    obj({
      name: str({ pattern: MCP_SERVER_NAME_RE }),
      headers: stringMap({ maxEntries: 16 }),
      expiresAt: optional(epochMs),
    }),
    { max: 32 }
  ),
})
