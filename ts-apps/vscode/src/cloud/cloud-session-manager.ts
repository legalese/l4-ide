/**
 * Cloud sessions from the extension host (spec §8, §10, §12):
 *
 * - {@link CloudSessionManager.runInCloud} seeds and starts a new
 *   session with the user's first prompt (§10 steps 2–8);
 * - {@link CloudSessionManager.open} replays a session's event log from
 *   the start and keeps polling while it runs (§12.1);
 * - commands (message, inject, abort, approve, answer, rollback, stop)
 *   are queued through the Sessions API; a command to a sleeping
 *   session starts it with a fresh key chain;
 * - polled events are turned back into the chat-service events the
 *   webview already renders (`cloudEventToChatEvent`); cloud-only
 *   events go to a separate listener with the conversation they belong
 *   to;
 * - when a session reports `session-state: running` with a public key,
 *   the user's MCP credentials are sealed to it and sent (§6.4).
 *
 * No `vscode` import: the extension supplies the listener, the MCP
 * source and the seed (vscode-cloud.ts).
 */
import type { ChatServiceEvent, Logger } from '@repo/legalese-agent'
import {
  CURSOR_START,
  cloudEventToChatEvent,
  isSealingPublicKey,
  type AttachmentRef,
  type ClientCommandPayload,
  type CloudEvent,
  type EventStreamError,
  type EventStreamResponse,
  type GetSessionResponse,
  type ListSessionsResponse,
  type PostCommandResponse,
  type SessionState,
} from '@repo/legalese-agent/protocol'
import { EventPoller, type PollerDeps } from './event-poller.js'
import {
  cloudMcpServers,
  collectMcpCredentials,
  sealMcpCredentials,
  type McpServerSource,
} from './mcp-transfer.js'
import {
  attachmentNames,
  checkAttachmentSizes,
  checkSeedSize,
  createSeedTarGz,
  type SeedAttachment,
  type SeedFile,
} from './seed.js'
import type { SessionsApi } from './sessions-api.js'

/** Progress of {@link CloudSessionManager.runInCloud} (§12.2). */
export type CloudStartPhase = 'uploading' | 'starting' | 'ready'

export interface CloudSessionListener {
  /** A chat-service event for the webview — the same path local chats use. */
  chat(event: ChatServiceEvent): void
  /** A cloud-only event (`user-message`, `ask-user`, `approval-request`,
   *  `session-state`, `git-committed`, `rolled-back`, `local-merged`,
   *  `local-merge-conflict`, `auth-required`). `conversationId` is set
   *  once the session's first turn has one. */
  cloudEvent?(e: {
    sessionId: string
    conversationId?: string
    event: CloudEvent
    /** True for events that were already in the log when the session
     *  was opened (don't notify for those). */
    replay: boolean
  }): void
  /** The session's state changed (from a poll or a response). */
  state?(sessionId: string, state: SessionState): void
  /** The session can't be read any more (deleted elsewhere). */
  gone?(sessionId: string, error: string): void
  /** Start progress for a turn started with `runInCloud`. */
  progress?(e: {
    turnId: string
    sessionId?: string
    phase: CloudStartPhase
  }): void
}

export interface CloudSeed {
  /** Files for `repo/`, relative to the seed root. */
  files: SeedFile[]
  attachments: SeedAttachment[]
}

export interface CloudSessionManagerDeps {
  api: SessionsApi
  /** Mint the first key of a key chain for `sid` (jl4-auth-proxy). */
  mintAgentKey(sid: string): Promise<{ token: string }>
  mcp?: McpServerSource
  listener: CloudSessionListener
  logger: Logger
  /** Timer / clock overrides for the poller (tests). */
  poller?: Pick<PollerDeps, 'now' | 'setTimer' | 'clearTimer'>
}

const LIVE_STATES: ReadonlySet<SessionState> = new Set([
  'running',
  'busy',
  'waiting',
])

interface Tracked {
  conversationId?: string
  state?: SessionState
  /** Highest event `seq` delivered; older ones are dropped. */
  lastSeq: number
  /** Reading the log that existed when the session was opened (no
   *  notifications for those events). */
  replaying: boolean
  /** Sealing key from the latest `session-state: running`. */
  publicKey?: string
  /** Key the credentials were last sealed to. */
  credentialsSentTo?: string
  /** Latest `auth-required { reason: 'mcp' }` seq answered. */
  mcpAuthHandled: number
  /** MCP server names in `session.json`. */
  mcpNames?: string[]
}

function titleFrom(text: string): string {
  const line = text.trim().split('\n')[0] ?? ''
  return line.length > 80 ? `${line.slice(0, 77)}...` : line
}

const CONTENT_TYPE_RE = /^[\w.+-]+\/[\w.+-]+$/

export class CloudSessionManager {
  private readonly sessions = new Map<string, Tracked>()
  private readonly byConversation = new Map<string, string>()
  private readonly byTurn = new Map<string, string>()
  private readonly poller: EventPoller
  private readonly credentialJobs = new Map<string, Promise<void>>()

  constructor(private readonly deps: CloudSessionManagerDeps) {
    this.poller = new EventPoller({
      getEvents: (streams) => deps.api.getEvents(streams),
      onStream: (s) => this.handleStream(s),
      onError: (err) =>
        deps.logger.warn(
          `cloud-sessions: poll failed: ${err instanceof Error ? err.message : String(err)}`
        ),
      ...deps.poller,
    })
  }

  dispose(): void {
    this.poller.dispose()
  }

  // ── Lookups ─────────────────────────────────────────────────────────

  sessionForConversation(conversationId: string): string | undefined {
    return this.byConversation.get(conversationId)
  }

  sessionForTurn(turnId: string): string | undefined {
    return this.byTurn.get(turnId)
  }

  conversationForSession(sid: string): string | undefined {
    return this.sessions.get(sid)?.conversationId
  }

  stateOf(sid: string): SessionState | undefined {
    return this.sessions.get(sid)?.state
  }

  isWatching(sid: string): boolean {
    return this.poller.isWatching(sid)
  }

  private track(sid: string): Tracked {
    let t = this.sessions.get(sid)
    if (!t) {
      t = { lastSeq: 0, replaying: false, mcpAuthHandled: 0 }
      this.sessions.set(sid, t)
    }
    return t
  }

  private setConversation(sid: string, conversationId: string): void {
    const t = this.track(sid)
    t.conversationId = conversationId
    this.byConversation.set(conversationId, sid)
  }

  private setState(sid: string, state: SessionState): void {
    const t = this.track(sid)
    if (t.state === state) return
    t.state = state
    this.deps.listener.state?.(sid, state)
  }

  // ── Starting ────────────────────────────────────────────────────────

  /**
   * Seed a new session and run `text` as its first turn (§10). Throws
   * `SeedLimitError` before anything is uploaded when a limit is hit,
   * and `SessionsApiError` / `NotSignedInError` / `AuthProxyError` on
   * failures; a session created before the failure is deleted again.
   */
  async runInCloud(input: {
    turnId: string
    text: string
    title?: string
    seed: CloudSeed
  }): Promise<{ sessionId: string }> {
    const { turnId, text, seed } = input
    checkAttachmentSizes(seed.attachments)
    const names = attachmentNames(seed.attachments.map((a) => a.name))
    const attachments = seed.attachments.map((a, i) => ({
      ...a,
      name: names[i]!,
      contentType: CONTENT_TYPE_RE.test(a.contentType)
        ? a.contentType
        : 'application/octet-stream',
    }))
    const gz = seed.files.length > 0 ? createSeedTarGz(seed.files) : undefined
    if (gz) checkSeedSize(gz, seed.files)

    const mcp = this.deps.mcp
      ? cloudMcpServers(this.deps.mcp.enabledServers())
      : undefined
    if (mcp && mcp.skipped.length > 0) {
      this.deps.logger.info(
        `cloud-sessions: not passing ${mcp.skipped.length} MCP server(s) (stdio or not https)`
      )
    }

    this.deps.listener.progress?.({ turnId, phase: 'uploading' })
    const created = await this.deps.api.createSession({
      title: (input.title ?? titleFrom(text)).slice(0, 200),
      mcpServers: mcp?.configs ?? [],
      ...(gz ? { seedSize: gz.byteLength } : {}),
      attachments: attachments.map(
        (a): AttachmentRef => ({
          name: a.name,
          contentType: a.contentType,
          size: a.bytes.byteLength,
        })
      ),
    })
    const sid = created.sessionId
    this.byTurn.set(turnId, sid)
    const t = this.track(sid)
    t.mcpNames = (mcp?.configs ?? []).map((c) => c.name)
    try {
      this.deps.listener.progress?.({
        turnId,
        sessionId: sid,
        phase: 'uploading',
      })
      const uploads: Promise<void>[] = []
      if (gz) uploads.push(this.deps.api.upload(created.uploads.seed, gz))
      for (const a of attachments) {
        const target = created.uploads.attachments.find(
          (u) => u.name === a.name
        )
        if (!target) throw new Error(`no upload URL for ${a.name}`)
        uploads.push(this.deps.api.upload(target, a.bytes))
      }
      await Promise.all(uploads)
      this.setState(sid, await this.deps.api.initSession(sid))
      await this.deps.api.postCommand(sid, {
        type: 'message',
        turnId,
        text,
        ...(attachments.length > 0
          ? { attachments: attachments.map((a) => a.name) }
          : {}),
      })
      this.deps.listener.progress?.({
        turnId,
        sessionId: sid,
        phase: 'starting',
      })
      await this.resume(sid)
    } catch (err) {
      this.byTurn.delete(turnId)
      this.sessions.delete(sid)
      this.poller.unwatch(sid)
      void this.deps.api.deleteSession(sid).catch(() => undefined)
      throw err
    }
    return { sessionId: sid }
  }

  /** Mint a new key chain and start the session (also "Resume" for
   *  parked sessions and `auth-required`). */
  async resume(sid: string): Promise<SessionState> {
    const key = await this.deps.mintAgentKey(sid)
    const state = await this.deps.api.startSession(sid, key.token)
    this.setState(sid, state)
    this.poller.poke(sid, state)
    return state
  }

  // ── Watching ────────────────────────────────────────────────────────

  /**
   * Open a session: read `session.json` and its state, then replay the
   * event log from the start. Polling continues while it runs.
   */
  async open(sid: string): Promise<GetSessionResponse> {
    const info = await this.deps.api.getSession(sid)
    const t = this.track(sid)
    if (info.session.conversationId) {
      this.setConversation(sid, info.session.conversationId)
    }
    t.mcpNames = info.session.mcpServers.map((s) => s.name)
    t.replaying = true
    t.lastSeq = 0
    this.setState(sid, info.state)
    this.poller.watch(sid, { cursor: CURSOR_START, state: info.state })
    return info
  }

  /** Stop following a session (the view closed it). */
  close(sid: string): void {
    this.poller.unwatch(sid)
  }

  async list(): Promise<ListSessionsResponse> {
    const res = await this.deps.api.listSessions()
    for (const s of res.sessions) {
      if (this.sessions.has(s.sessionId)) this.setState(s.sessionId, s.state)
    }
    return res
  }

  private async handleStream(
    stream: EventStreamResponse | EventStreamError
  ): Promise<void> {
    const sid = stream.sessionId
    if ('error' in stream) {
      this.deps.listener.gone?.(sid, stream.error)
      return
    }
    const t = this.track(sid)
    for (const event of stream.events) {
      if (event.seq <= t.lastSeq) continue
      t.lastSeq = event.seq
      this.handleEvent(sid, t, event)
    }
    if (!stream.more) t.replaying = false
    this.setState(sid, stream.state)
    if (LIVE_STATES.has(stream.state)) {
      await this.maybeSendCredentials(sid, t)
    }
  }

  private handleEvent(sid: string, t: Tracked, event: CloudEvent): void {
    const chat = cloudEventToChatEvent(event)
    if (chat) {
      if (chat.kind === 'started') {
        this.setConversation(sid, chat.conversationId)
        this.byTurn.set(chat.turnId, sid)
      } else if (!t.conversationId && 'conversationId' in chat) {
        this.setConversation(sid, chat.conversationId)
      }
      this.deps.listener.chat(chat)
      return
    }
    switch (event.type) {
      case 'user-message':
        this.byTurn.set(event.turnId, sid)
        break
      case 'ask-user':
      case 'approval-request':
        if (!t.conversationId) this.setConversation(sid, event.conversationId)
        break
      case 'session-state':
        t.publicKey =
          event.state === 'running' && isSealingPublicKey(event.publicKey)
            ? event.publicKey
            : LIVE_STATES.has(event.state)
              ? t.publicKey
              : undefined
        break
      case 'auth-required':
        if (event.reason === 'mcp' && event.seq > t.mcpAuthHandled) {
          // Answer with fresh credentials once the batch is processed.
          t.mcpAuthHandled = event.seq
          t.credentialsSentTo = undefined
        }
        break
    }
    this.deps.listener.cloudEvent?.({
      sessionId: sid,
      conversationId: t.conversationId,
      event,
      replay: t.replaying,
    })
  }

  /** Seal the user's MCP credentials to the running harness (§6.4). */
  private maybeSendCredentials(sid: string, t: Tracked): Promise<void> {
    const key = t.publicKey
    if (!this.deps.mcp || !key || t.credentialsSentTo === key) {
      return Promise.resolve()
    }
    const running = this.credentialJobs.get(sid)
    if (running) return running
    const job = (async () => {
      t.credentialsSentTo = key
      try {
        let names = t.mcpNames
        if (!names) {
          const info = await this.deps.api.getSession(sid)
          names = t.mcpNames = info.session.mcpServers.map((s) => s.name)
        }
        if (names.length === 0) return
        const { credentials, unauthorized } = await collectMcpCredentials(
          this.deps.mcp!,
          names
        )
        if (unauthorized.length > 0) {
          this.deps.logger.warn(
            `cloud-sessions: MCP server(s) need a sign-in before the cloud session can use them: ${unauthorized.join(', ')}`
          )
        }
        if (credentials.servers.length === 0) return
        await this.deps.api.postCommand(sid, {
          type: 'mcp-credentials',
          sealed: sealMcpCredentials(key, sid, credentials),
        })
        this.deps.logger.info(
          `cloud-sessions: sent sealed credentials for ${credentials.servers.length} MCP server(s)`
        )
      } catch (err) {
        t.credentialsSentTo = undefined
        this.deps.logger.warn(
          `cloud-sessions: sending MCP credentials failed: ${err instanceof Error ? err.message : String(err)}`
        )
      }
    })().finally(() => this.credentialJobs.delete(sid))
    this.credentialJobs.set(sid, job)
    return job
  }

  // ── Commands ────────────────────────────────────────────────────────

  /**
   * Queue a command. Commands to a sleeping session start it (a fresh
   * key chain); a parked session needs {@link resume} (the UI asks).
   */
  async send(
    sid: string,
    command: ClientCommandPayload
  ): Promise<PostCommandResponse> {
    if (command.type === 'message') this.byTurn.set(command.turnId, sid)
    const res = await this.deps.api.postCommand(sid, command)
    this.setState(sid, res.state)
    this.poller.poke(sid, res.state)
    if (res.state === 'sleeping' && command.type !== 'stop') {
      await this.resume(sid)
    }
    return res
  }

  sendMessage(
    sid: string,
    turnId: string,
    text: string,
    attachments?: string[]
  ): Promise<PostCommandResponse> {
    return this.send(sid, {
      type: 'message',
      turnId,
      text,
      ...(attachments?.length ? { attachments } : {}),
    })
  }

  inject(
    sid: string,
    turnId: string,
    text: string,
    injectionId?: string
  ): Promise<PostCommandResponse> {
    return this.send(sid, {
      type: 'inject',
      turnId,
      text,
      ...(injectionId ? { injectionId } : {}),
    })
  }

  abort(sid: string, turnId: string): Promise<PostCommandResponse> {
    return this.send(sid, { type: 'abort', turnId })
  }

  approve(
    sid: string,
    callId: string,
    decision: 'allow' | 'deny'
  ): Promise<PostCommandResponse> {
    return this.send(sid, { type: 'approve', callId, decision })
  }

  answer(
    sid: string,
    callId: string,
    answer: string
  ): Promise<PostCommandResponse> {
    return this.send(sid, { type: 'answer', callId, answer })
  }

  rollback(sid: string, turnId: string): Promise<PostCommandResponse> {
    return this.send(sid, { type: 'rollback', turnId })
  }

  async stop(sid: string): Promise<SessionState> {
    const state = await this.deps.api.stopSession(sid)
    this.setState(sid, state)
    this.poller.poke(sid, state)
    return state
  }

  /** Delete a session. The Sessions API answers `409 stopping` while
   *  the task still runs; the caller retries later. */
  async delete(sid: string): Promise<void> {
    await this.deps.api.deleteSession(sid)
    this.poller.unwatch(sid)
    const t = this.sessions.get(sid)
    if (t?.conversationId) this.byConversation.delete(t.conversationId)
    this.sessions.delete(sid)
  }
}
