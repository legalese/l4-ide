/**
 * Messages between the VS Code extension and the sidebar webview for
 * cloud sessions (specs/todo/CLOUD-SESSIONS-SPEC.md §12). Everything
 * here is only used while `legaleseAi.cloudSessions.enabled` is on.
 *
 * Chat events of a cloud session reuse the ordinary `AiChat*`
 * notifications, with `conversationId` = {@link cloudConversationId}
 * (`cloud:<sessionId>`), so the webview renders them like local chats.
 * The shapes below mirror `@repo/legalese-agent/protocol` (which can't
 * be imported here: it depends on this package).
 */
import type { NotificationType, RequestType } from 'vscode-messenger-common'
import type { AiChatStartParams } from './vscode-and-webview-messages.js'

export const CLOUD_CONVERSATION_PREFIX = 'cloud:'

/** The webview's conversation id for a cloud session. */
export function cloudConversationId(sessionId: string): string {
  return `${CLOUD_CONVERSATION_PREFIX}${sessionId}`
}

/** The session id in a cloud conversation id, or null. */
export function cloudSessionIdOf(
  conversationId: string | null | undefined
): string | null {
  return conversationId?.startsWith(CLOUD_CONVERSATION_PREFIX)
    ? conversationId.slice(CLOUD_CONVERSATION_PREFIX.length)
    : null
}

export type AiCloudSessionState =
  | 'sleeping'
  | 'starting'
  | 'running'
  | 'busy'
  | 'waiting'
  | 'parked'

/** A row of the cloud part of the history (`GET /sessions`). */
export interface AiCloudSessionSummary {
  sessionId: string
  title: string
  /** Epoch ms. */
  created: number
  /** Epoch ms. */
  lastActivity: number
  state: AiCloudSessionState
}

/** Cloud-only events (the chat-service kinds arrive as `AiChat*`). */
export type AiCloudEventPayload =
  | {
      type: 'user-message'
      turnId: string
      text: string
      attachments: Array<{ name: string; contentType: string; size: number }>
    }
  | {
      type: 'ask-user'
      conversationId: string
      turnId: string
      callId: string
      question: string
      choices?: string[]
    }
  | { type: 'session-state'; state: AiCloudSessionState; publicKey?: string }
  | { type: 'git-committed'; turnId: string; sha: string; parent: string }
  | { type: 'rolled-back'; turnId: string; sha: string }
  | { type: 'local-merged'; sha: string }
  | { type: 'local-merge-conflict'; files: string[] }
  /** Files added mid-session landed in the repo (`data/…` paths). */
  | {
      type: 'files-added'
      batchId: string
      files: Array<{ path: string; sha?: string }>
    }
  | { type: 'auth-required'; reason: string; server?: string }

/** Extension → webview: whether cloud sessions are on. Sent when the
 *  webview is ready and whenever the settings change. */
export const AiCloudConfig: NotificationType<{ enabled: boolean }> = {
  method: 'aiCloudConfig',
}

/** Extension → webview: a cloud-only event of a session. */
export const AiCloudEvent: NotificationType<{
  /** `cloud:<sessionId>` */
  conversationId: string
  sessionId: string
  seq: number
  /** Already in the log when the session was opened (no alerts). */
  replay: boolean
  event: AiCloudEventPayload
}> = {
  method: 'aiCloudEvent',
}

/** Extension → webview: a session's state changed (`gone` = it can't
 *  be read any more, e.g. deleted on another machine). */
export const AiCloudState: NotificationType<{
  sessionId: string
  state: AiCloudSessionState | 'gone'
}> = {
  method: 'aiCloudState',
}

export type AiCloudStartPhase =
  | 'uploading'
  | 'starting'
  | 'ready'
  | 'error'
  /** Before a later prompt: new or changed files are being added. */
  | 'adding-files'

/** Extension → webview: progress of an {@link AiCloudRun}. */
export const AiCloudProgress: NotificationType<{
  turnId: string
  sessionId?: string
  phase: AiCloudStartPhase
  /** With the first `uploading`: MCP servers passed to the session;
   *  their tools run without approval in the cloud. */
  mcpServers?: string[]
  /** With `adding-files`: how many files. */
  fileCount?: number
  /** With `phase: 'error'`: what to tell the user. */
  error?: string
}> = {
  method: 'aiCloudProgress',
}

/** Extension → webview: show this cloud conversation (a notification's
 *  "Open" action). */
export const AiCloudReveal: NotificationType<{ sessionId: string }> = {
  method: 'aiCloudReveal',
}

/** Webview → extension: start a new cloud session with this prompt
 *  ("Run in cloud"). The extension gathers the seed (active file and
 *  its imports, @-mentions, attachments) and reports through
 *  {@link AiCloudProgress}. */
export const AiCloudRun: NotificationType<
  Pick<
    AiChatStartParams,
    | 'turnId'
    | 'text'
    | 'mentions'
    | 'attachments'
    | 'includeActiveFile'
    | 'activeFile'
  >
> = {
  method: 'aiCloudRun',
}

export interface AiCloudResult {
  ok: boolean
  error?: string
  state?: AiCloudSessionState
}

/** Webview → extension: open a cloud conversation; its event log is
 *  replayed from the start through the usual notifications. */
export const AiCloudOpen: RequestType<
  { sessionId: string },
  AiCloudResult & { title?: string }
> = {
  method: 'aiCloudOpen',
}

/** Commands a webview may send to a cloud session (§8). Cloud
 *  sessions never ask for tool approval, so there is no `approve`. */
/** What a prompt refers to, for adding files mid-session (§10): the
 *  extension uploads new or changed files before the message. */
export type AiCloudPromptRefs = Pick<
  AiChatStartParams,
  'mentions' | 'includeActiveFile' | 'activeFile'
>

export type AiCloudCommandPayload =
  | ({ type: 'message'; turnId: string; text: string } & AiCloudPromptRefs)
  | ({
      type: 'inject'
      turnId: string
      injectionId?: string
      text: string
    } & AiCloudPromptRefs)
  | { type: 'abort'; turnId: string }
  | { type: 'answer'; callId: string; answer: string }

export const AiCloudCommand: RequestType<
  { sessionId: string; command: AiCloudCommandPayload },
  AiCloudResult
> = {
  method: 'aiCloudCommand',
}

/** Webview → extension: restore the files to before `turnId` (§9.4).
 *  The extension confirms first when later turns (or merged local
 *  syncs) would be undone. */
export const AiCloudRollback: RequestType<
  {
    sessionId: string
    turnId: string
    /** Later turns would be undone too. */
    undoesLaterTurns: boolean
    /** Local changes synced in after this turn would be undone. */
    undoesLocalSync: boolean
  },
  AiCloudResult & { cancelled?: boolean }
> = {
  method: 'aiCloudRollback',
}

/** Webview → extension: mint a new key chain and start the session
 *  (Resume, for `parked` sessions and `auth-required`). */
export const AiCloudResume: RequestType<{ sessionId: string }, AiCloudResult> =
  {
    method: 'aiCloudResume',
  }

export const AiCloudStop: RequestType<{ sessionId: string }, AiCloudResult> = {
  method: 'aiCloudStop',
}

export const AiCloudDelete: RequestType<{ sessionId: string }, AiCloudResult> =
  {
    method: 'aiCloudDelete',
  }

/** Webview → extension: the cloud part of the history. `refresh:
 *  false` answers from the cache in extension storage right away. */
export const AiCloudSessionList: RequestType<
  { refresh: boolean },
  { items: AiCloudSessionSummary[]; error?: string }
> = {
  method: 'aiCloudSessionList',
}

/** Clone / Sync button state (§9.3). */
export type AiCloudGitStatus =
  | { kind: 'unavailable'; message: string }
  | { kind: 'not-cloned' }
  | {
      kind: 'cloned'
      folder: string
      ahead: number
      behind: number
      /** Pushed commits wait for the session to run. */
      pending: boolean
    }

export const AiCloudGitStatusRequest: RequestType<
  { sessionId: string },
  AiCloudGitStatus
> = {
  method: 'aiCloudGitStatus',
}

/** Clone (asks for the parent folder) or sync (pull, then push). */
export const AiCloudGitAction: RequestType<
  { sessionId: string; action: 'clone' | 'sync' },
  { status: AiCloudGitStatus; error?: string; cancelled?: boolean }
> = {
  method: 'aiCloudGitAction',
}
