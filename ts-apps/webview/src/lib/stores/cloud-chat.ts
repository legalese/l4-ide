/**
 * Cloud-conversation logic of the AI chat store (spec §9.4, §12), kept
 * free of Svelte runes so it can be unit-tested: history merging,
 * cloud-only events, adopting turns this webview didn't start, and
 * which turns offer a rollback.
 *
 * Functions mutate the conversation objects they're given; the store
 * passes its `$state` proxies, so the UI updates.
 */
import type {
  AiCloudEventPayload,
  AiCloudSessionState,
  AiCloudSessionSummary,
  AiConversationSummary,
} from 'jl4-client-rpc'

/** Cloud state of a conversation shown in the chat. */
export interface CloudConversationInfo {
  /** '' until "Run in cloud" has created the session. */
  sessionId: string
  state: AiCloudSessionState | 'gone'
  /** Start progress of "Run in cloud"; null once ready. */
  progress: 'uploading' | 'starting' | null
  /** Set by `auth-required` (the key chain or an MCP token failed);
   *  cleared when the session runs again. */
  authRequired: { reason: string; server?: string } | null
  /** Files of the last `local-merge-conflict`. */
  mergeConflict: string[] | null
  /** `turns.length` when each `local-merged` arrived: local changes
   *  merged after turn N sit at indices greater than N. */
  localMergesAt: number[]
  /** Last command error to show in the banner. */
  notice: string | null
}

/** The part of a rendered turn this module reads and writes. */
export interface CloudTurn {
  id: string
  role: 'user' | 'assistant'
  content: string
  turnId?: string
  streaming?: boolean
  blocks?: unknown[]
  chips?: Array<{ kind: string; name: string; path?: string }>
  /** User turns: the turn id the prompt was sent as. */
  cloudTurnId?: string
  /** Assistant turns: the commit the harness made for this turn. */
  cloudCommit?: { sha: string; parent: string }
  /** Assistant turns: its file changes were rolled back. */
  rolledBack?: boolean
}

export interface CloudConversation {
  turns: CloudTurn[]
  streaming: boolean
  activeTurnId: string | null
  cloud?: CloudConversationInfo
}

export function newCloudInfo(
  sessionId: string,
  state: CloudConversationInfo['state'] = 'sleeping'
): CloudConversationInfo {
  return {
    sessionId,
    state,
    progress: null,
    authRequired: null,
    mergeConflict: null,
    localMergesAt: [],
    notice: null,
  }
}

// ── History (§12.1) ───────────────────────────────────────────────────

export type HistoryEntry =
  | {
      kind: 'local'
      id: string
      title: string
      lastActivity: number
      deploymentId?: string
    }
  | {
      kind: 'cloud'
      /** `cloud:<sessionId>` */
      id: string
      sessionId: string
      title: string
      lastActivity: number
      state: AiCloudSessionState
    }

/** Local and cloud conversations, most recently active first. */
export function mergeHistory(
  local: AiConversationSummary[],
  cloud: AiCloudSessionSummary[]
): HistoryEntry[] {
  const entries: HistoryEntry[] = [
    ...local.map(
      (c): HistoryEntry => ({
        kind: 'local',
        id: c.id,
        title: c.title,
        lastActivity: Date.parse(c.lastActiveAt) || 0,
        ...(c.deploymentId ? { deploymentId: c.deploymentId } : {}),
      })
    ),
    ...cloud.map(
      (s): HistoryEntry => ({
        kind: 'cloud',
        id: `cloud:${s.sessionId}`,
        sessionId: s.sessionId,
        title: s.title || 'Cloud session',
        lastActivity: s.lastActivity,
        state: s.state,
      })
    ),
  ]
  return entries.sort((a, b) => b.lastActivity - a.lastActivity)
}

// ── Turns this webview didn't start ───────────────────────────────────

function newId(prefix: string): string {
  return `${prefix}:${Date.now()}:${Math.random().toString(36).slice(2, 8)}`
}

/**
 * Make sure a streaming assistant bubble exists for `turnId` (a turn
 * started elsewhere: another window, a replay, the cloud harness).
 * Returns true when one was added.
 */
export function adoptTurn(conv: CloudConversation, turnId: string): boolean {
  if (conv.turns.some((t) => t.role === 'assistant' && t.turnId === turnId)) {
    return false
  }
  for (const t of conv.turns) {
    if (t.role === 'assistant') t.streaming = false
  }
  conv.turns.push({
    id: newId('asst'),
    turnId,
    role: 'assistant',
    content: '',
    streaming: true,
    blocks: [],
  })
  conv.streaming = true
  conv.activeTurnId = turnId
  return true
}

/** The assistant turn of cloud turn `turnId`. */
function assistantOf(
  conv: CloudConversation,
  turnId: string
): CloudTurn | undefined {
  return conv.turns.find((t) => t.role === 'assistant' && t.turnId === turnId)
}

/**
 * Apply a cloud-only event to a conversation. Returns a question to
 * surface for `ask-user`.
 */
export function applyCloudEvent(
  conv: CloudConversation,
  event: AiCloudEventPayload
): { question?: { callId: string; question: string; choices?: string[] } } {
  const info = (conv.cloud ??= newCloudInfo(''))
  switch (event.type) {
    case 'user-message': {
      // Prompts this webview sent carry their turn id already (a
      // message and any injects into the same turn share it).
      const sameTurn = conv.turns.filter(
        (t) => t.role === 'user' && t.cloudTurnId === event.turnId
      )
      if (sameTurn.some((t) => t.content === event.text)) return {}
      const user: CloudTurn = {
        id: `user:${event.turnId}`,
        role: 'user',
        content: event.text,
        cloudTurnId: event.turnId,
        ...(event.attachments.length > 0
          ? {
              chips: event.attachments.map((a) => ({
                kind: a.contentType === 'application/pdf' ? 'pdf' : 'image',
                name: a.name,
              })),
            }
          : {}),
      }
      // The turn's first prompt goes before its reply, which may be
      // there already (chat and cloud events can arrive out of order).
      const at =
        sameTurn.length === 0
          ? conv.turns.findIndex(
              (t) => t.role === 'assistant' && t.turnId === event.turnId
            )
          : -1
      if (at >= 0) conv.turns.splice(at, 0, user)
      else conv.turns.push(user)
      return {}
    }
    case 'ask-user':
      return {
        question: {
          callId: event.callId,
          question: event.question,
          ...(event.choices ? { choices: event.choices } : {}),
        },
      }
    case 'approval-request': {
      // Show the approve / deny buttons on the tool row.
      for (const t of conv.turns) {
        for (const b of (t.blocks ?? []) as Array<{
          kind: string
          call?: { callId: string; status: string }
        }>) {
          if (b.kind === 'tool-call' && b.call?.callId === event.callId) {
            b.call.status = 'pending-approval'
            return {}
          }
        }
      }
      const target =
        assistantOf(conv, event.turnId) ??
        [...conv.turns].reverse().find((t) => t.role === 'assistant')
      if (target) {
        ;(target.blocks ??= []).push({
          kind: 'tool-call',
          call: {
            callId: event.callId,
            name: event.name,
            argsJson: event.argsJson,
            status: 'pending-approval',
          },
        })
      }
      return {}
    }
    case 'session-state':
      info.state = event.state
      if (event.state === 'running' || event.state === 'busy') {
        info.authRequired = null
        info.progress = null
      }
      return {}
    case 'git-committed': {
      const turn = assistantOf(conv, event.turnId)
      if (turn) turn.cloudCommit = { sha: event.sha, parent: event.parent }
      return {}
    }
    case 'rolled-back': {
      // Restoring to before turn N undoes N and everything after it.
      const at = conv.turns.findIndex(
        (t) => t.role === 'assistant' && t.turnId === event.turnId
      )
      if (at < 0) return {}
      for (const t of conv.turns.slice(at)) {
        if (t.role === 'assistant' && t.cloudCommit) t.rolledBack = true
      }
      info.localMergesAt = info.localMergesAt.filter((i) => i <= at)
      return {}
    }
    case 'local-merged':
      info.localMergesAt.push(conv.turns.length)
      info.mergeConflict = null
      return {}
    case 'local-merge-conflict':
      info.mergeConflict = event.files
      return {}
    case 'auth-required':
      info.authRequired = {
        reason: event.reason,
        ...(event.server ? { server: event.server } : {}),
      }
      return {}
  }
}

// ── Rollback (§9.4) ───────────────────────────────────────────────────

export interface RollbackOffer {
  turnId: string
  /** "Roll back" on the latest turn; "Restore to before this turn"
   *  on earlier ones. */
  label: 'Roll back' | 'Restore to before this turn'
  undoesLaterTurns: boolean
  undoesLocalSync: boolean
}

/**
 * The rollback offer for the assistant turn at `index`, or null. A
 * completed turn that changed files (has a commit) and wasn't rolled
 * back qualifies. The most recent such turn gets "Roll back" until the
 * user sends the next prompt; earlier ones "Restore to before this turn".
 */
export function rollbackOffer(
  conv: CloudConversation,
  index: number
): RollbackOffer | null {
  if (!conv.cloud?.sessionId) return null
  const turn = conv.turns[index]
  if (
    !turn ||
    turn.role !== 'assistant' ||
    !turn.turnId ||
    !turn.cloudCommit ||
    turn.rolledBack ||
    turn.streaming
  ) {
    return null
  }
  const later = conv.turns.slice(index + 1)
  const promptSentSince = later.some((t) => t.role === 'user')
  const undoesLaterTurns = later.some(
    (t) => t.role === 'assistant' && t.cloudCommit && !t.rolledBack
  )
  return {
    turnId: turn.turnId,
    label: promptSentSince ? 'Restore to before this turn' : 'Roll back',
    undoesLaterTurns,
    undoesLocalSync: conv.cloud.localMergesAt.some((i) => i > index),
  }
}
