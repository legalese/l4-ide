/**
 * Cloud sessions from the extension host (spec §8, §10, §12):
 *
 * - {@link CloudSessionManager.runInCloud} seeds and starts a new
 *   session with the user's first prompt (§10 steps 2–8);
 * - {@link CloudSessionManager.open} replays a session's event log from
 *   the start and keeps polling while it runs (§12.1);
 * - commands (message, inject, abort, answer, rollback, stop); cloud
 *   sessions never ask for tool approval, so there is no `approve`
 *   are queued through the Sessions API; a command to a sleeping
 *   session starts it with a fresh key chain, and so does a session
 *   that goes to sleep before its harness picked up a sent message;
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
  type MessageContext,
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
  checkAddFilesSizes,
  checkAttachmentSizes,
  checkSeedSize,
  contentHash,
  contentTypeFor,
  createSeedTarGz,
  dataPathFor,
  relativeTo,
  seedBaseFor,
  seedBaseLocalPath,
  type SeedAttachment,
  type SeedBaseRef,
  type WorkspaceFolderRef,
  type SeedFile,
  type SeedSource,
} from './seed.js'
import type { SessionsApi } from './sessions-api.js'

/** Progress of {@link CloudSessionManager.runInCloud} (§12.2), and of
 *  adding files before a later prompt (`adding-files`). */
export type CloudStartPhase =
  | 'uploading'
  | 'starting'
  | 'ready'
  | 'adding-files'

export interface CloudSessionListener {
  /** A chat-service event for the webview — the same path local chats use. */
  chat(event: ChatServiceEvent): void
  /** A cloud-only event (`user-message`, `ask-user`,
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
    /** With the first `uploading`: the MCP servers passed to the
     *  session. Their tools run without approval in the cloud. */
    mcpServers?: string[]
    /** With `adding-files`: how many files are being added. */
    fileCount?: number
    /** With `starting`: the session's title (an AI title, §12). */
    title?: string
    turnId: string
    sessionId?: string
    phase: CloudStartPhase
  }): void
}

export interface CloudSeed {
  /** Files for `repo/data/`, relative to the seed root. */
  files: SeedFile[]
  attachments: SeedAttachment[]
  /** The seed root (absolute, `/`-separated): the common ancestor the
   *  seed paths are relative to. */
  root?: string
  /** Open workspace folders, to express the root as a `seedBase`. */
  workspaceFolders?: WorkspaceFolderRef[]
  /** Absolute paths of the active file and @-mentioned files, for the
   *  first message's `context`. */
  activeFile?: string
  mentions?: string[]
}

/** What this machine has sent to a session: a content hash per `data/`
 *  path, so a later prompt only uploads new or changed files; and, when
 *  the session's `seedBase` names a workspace folder that isn't open
 *  here, the local folder the user picked for it. */
export interface SessionFilesRecord {
  sent: Record<string, string>
  /** Absolute path of the local folder chosen for `seedBase.workspaceFolder`. */
  localFolder?: string
}

export interface SessionFilesStore {
  get(sid: string): SessionFilesRecord | undefined
  set(sid: string, record: SessionFilesRecord | undefined): unknown
}

/** Files referred to by a later prompt (§10): @-mentions and the active
 *  file, by absolute path, with their current bytes. */
export interface PromptFiles {
  sources: SeedSource[]
  activeFile?: string
  mentions?: string[]
  /** Open workspace folders: to find the session's seed base, and for
   *  files outside it (workspace-relative paths). */
  workspaceFolders: WorkspaceFolderRef[]
}

function memoryFilesStore(): SessionFilesStore {
  const m = new Map<string, SessionFilesRecord>()
  return {
    get: (sid) => m.get(sid),
    set: (sid, rec) => (rec ? m.set(sid, rec) : m.delete(sid)),
  }
}

export interface CloudSessionManagerDeps {
  api: SessionsApi
  /** Mint the first key of a key chain for `sid` (jl4-auth-proxy). */
  mintAgentKey(sid: string): Promise<{ token: string }>
  mcp?: McpServerSource
  /** Per-session sent-file hashes and folder choice (extension storage). */
  files?: SessionFilesStore
  /** Ask the user which local folder corresponds to a session's seed
   *  base workspace folder `name` (not open here). Undefined = cancelled. */
  pickLocalFolder?(sessionId: string, name: string): Promise<string | undefined>
  listener: CloudSessionListener
  logger: Logger
  /** Timer / clock overrides for the poller (tests). */
  poller?: Pick<PollerDeps, 'now' | 'setTimer' | 'clearTimer'>
  /** An AI title for a first prompt (ai-proxy's summize pipeline, as
   *  local chats get), or null. Without one a session is named after
   *  the prompt's first line. */
  summarizeTitle?(text: string): Promise<string | null>
  /** How long a new session waits for that title (tests). */
  titleTimeoutMs?: number
}

/** A start waits at most this long for the AI title; the seed is
 *  packed meanwhile, and the compute start takes far longer. */
export const TITLE_TIMEOUT_MS = 4_000

/** How long {@link CloudSessionManager.replayed} waits at most. */
export const REPLAY_WAIT_MS = 10_000

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
  /** {@link CloudSessionManager.replayed} callers waiting for that. */
  replayWaiters: Array<() => void>
  /** Sealing key from the latest `session-state: running`. */
  publicKey?: string
  /** Key the credentials were last sealed to. */
  credentialsSentTo?: string
  /** Latest `auth-required { reason: 'mcp' }` seq answered. */
  mcpAuthHandled: number
  /** MCP server names in `session.json`. */
  mcpNames?: string[]
  /** Turn started with `runInCloud`, until the session is live. */
  startingTurn?: string
  /** `session.json` `seedBase`; `null` = known to be absent. */
  seedBase?: SeedBaseRef | null
  /** `message` commands sent from here that no event has acknowledged
   *  yet (`user-message` / `started` with their turn id), by turn id. */
  unanswered: Map<string, Unanswered>
  /** {@link CloudSessionManager.resume} calls in flight, and when the
   *  last one ended. */
  resuming: number
  lastStartAt: number
}

/** A sent message the harness hasn't picked up yet. */
interface Unanswered {
  /** `POST /commands` answered (until then a poll can't tell whether
   *  the harness could have seen it). */
  sent: boolean
  /** Starts made for it because the session went to sleep first. */
  autoResumes: number
  /** When the next one may be made. */
  nextAutoResumeAt: number
  /** A poll saw the session start after one of them, or one failed:
   *  none again. */
  spent: boolean
}

/**
 * When a session goes to sleep with a sent message no event has
 * acknowledged (it was sent while the task was shutting down), it is
 * started again for it: once, counting only a start a poll then sees
 * take (`starting` or live), or one that fails. The Sessions API
 * answers a start without starting a task while the old task is still
 * stopping (polls go on saying `sleeping`); such starts are retried,
 * each after the delay at its index (the first at once), and then
 * given up.
 */
export const AUTO_RESUME_DELAYS_MS: readonly number[] = [
  0, 10_000, 20_000, 30_000,
]

/** A started task takes a moment to show up in ECS: polls that still
 *  say `sleeping` this soon after a start don't count against it. */
export const START_SETTLE_MS = 10_000

function titleFrom(text: string): string {
  const line = text.trim().split('\n')[0] ?? ''
  return line.length > 80 ? `${line.slice(0, 77)}...` : line
}

const CONTENT_TYPE_RE = /^[\w.+-]+\/[\w.+-]+$/

/** `context` for a message; undefined when it would be empty. */
function messageContext(
  activeFile: string | undefined,
  mentions: Array<string | undefined>
): MessageContext | undefined {
  const m = [...new Set(mentions.filter((x): x is string => !!x))]
  if (!activeFile && m.length === 0) return undefined
  return {
    ...(activeFile ? { activeFile } : {}),
    ...(m.length > 0 ? { mentions: m } : {}),
  }
}

export class CloudSessionManager {
  private readonly sessions = new Map<string, Tracked>()
  private readonly byConversation = new Map<string, string>()
  private readonly byTurn = new Map<string, string>()
  private readonly poller: EventPoller
  private readonly credentialJobs = new Map<string, Promise<void>>()
  private readonly files: SessionFilesStore
  private readonly now: () => number

  constructor(private readonly deps: CloudSessionManagerDeps) {
    this.files = deps.files ?? memoryFilesStore()
    this.now = deps.poller?.now ?? Date.now
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
      t = {
        lastSeq: 0,
        replaying: false,
        replayWaiters: [],
        mcpAuthHandled: 0,
        unanswered: new Map(),
        resuming: 0,
        lastStartAt: -Infinity,
      }
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
    if (t.startingTurn && LIVE_STATES.has(state)) {
      this.deps.listener.progress?.({
        turnId: t.startingTurn,
        sessionId: sid,
        phase: 'ready',
      })
      t.startingTurn = undefined
    }
  }

  // ── Starting ────────────────────────────────────────────────────────

  /** The AI title for a first prompt, or its first line when there is
   *  none, it fails, or it takes longer than {@link TITLE_TIMEOUT_MS}. */
  private async titleFor(text: string): Promise<string> {
    const fallback = titleFrom(text)
    const generate = this.deps.summarizeTitle
    if (!generate) return fallback
    let timer: ReturnType<typeof setTimeout> | undefined
    const timeout = new Promise<null>((resolve) => {
      timer = setTimeout(
        () => resolve(null),
        this.deps.titleTimeoutMs ?? TITLE_TIMEOUT_MS
      )
    })
    try {
      const title = await Promise.race([
        generate.call(this.deps, text).catch(() => null),
        timeout,
      ])
      return title?.trim() || fallback
    } finally {
      clearTimeout(timer)
    }
  }

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
    // Asked first: the seed is packed while the title is generated.
    const title = input.title
      ? Promise.resolve(input.title)
      : this.titleFor(text)
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

    this.deps.listener.progress?.({
      turnId,
      phase: 'uploading',
      mcpServers: (mcp?.configs ?? []).map(
        (c) => mcp?.ids.get(c.name) ?? c.name
      ),
    })
    const seedBase =
      seed.root && seed.files.length > 0
        ? seedBaseFor(seed.root, seed.workspaceFolders ?? [])
        : undefined
    const sessionTitle = (await title).slice(0, 200)
    const created = await this.deps.api.createSession({
      title: sessionTitle,
      ...(seedBase ? { seedBase } : {}),
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
    const sent: Record<string, string> = {}
    for (const f of seed.files) sent[`data/${f.path}`] = contentHash(f.bytes)
    this.files.set(sid, { sent })
    const seeded = new Set(Object.keys(sent))
    const inSeed = (abs: string | undefined): string | undefined => {
      if (!abs || !seed.root) return undefined
      const rel = relativeTo(abs, seed.root)
      return rel !== null && seeded.has(`data/${rel}`)
        ? `data/${rel}`
        : undefined
    }
    const context = messageContext(
      inSeed(seed.activeFile),
      (seed.mentions ?? []).map(inSeed)
    )
    const t = this.track(sid)
    t.seedBase = seedBase ?? null
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
      await this.postMessage(sid, {
        type: 'message',
        turnId,
        text,
        ...(attachments.length > 0
          ? { attachments: attachments.map((a) => a.name) }
          : {}),
        ...(context ? { context } : {}),
      })
      this.deps.listener.progress?.({
        turnId,
        sessionId: sid,
        phase: 'starting',
        title: sessionTitle,
      })
      t.startingTurn = turnId
      await this.resume(sid)
    } catch (err) {
      this.byTurn.delete(turnId)
      this.files.set(sid, undefined)
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
    const t = this.track(sid)
    t.resuming++
    try {
      const key = await this.deps.mintAgentKey(sid)
      const state = await this.deps.api.startSession(sid, key.token)
      this.setState(sid, state)
      this.poller.poke(sid, state)
      return state
    } finally {
      t.resuming--
      t.lastStartAt = this.now()
    }
  }

  /**
   * After a poll that has caught up: a session that went to sleep with
   * a sent message no event has acknowledged is started again for it
   * (see {@link AUTO_RESUME_DELAYS_MS}). Not while a start runs or has
   * only just been made ({@link START_SETTLE_MS}).
   */
  private autoResume(sid: string, t: Tracked, state: SessionState): void {
    if (state !== 'sleeping') {
      // A start took (or the user must act, `parked`): don't start the
      // session again for these messages.
      for (const m of t.unanswered.values()) {
        if (m.autoResumes > 0 || state === 'parked') m.spent = true
      }
      return
    }
    const now = this.now()
    if (t.resuming > 0 || now < t.lastStartAt + START_SETTLE_MS) return
    const due = [...t.unanswered.values()].filter(
      (m) =>
        m.sent &&
        !m.spent &&
        m.autoResumes < AUTO_RESUME_DELAYS_MS.length &&
        now >= m.nextAutoResumeAt
    )
    if (due.length === 0) return
    for (const m of due) {
      m.autoResumes++
      m.nextAutoResumeAt =
        now + (AUTO_RESUME_DELAYS_MS[m.autoResumes] ?? Infinity)
    }
    this.deps.logger.info(
      `cloud-sessions: ${sid} went to sleep before running a sent message; starting it again`
    )
    this.resume(sid).catch((err) => {
      // Refused (not signed in, another organisation, …): no retry.
      for (const m of due) m.spent = true
      const message = err instanceof Error ? err.message : String(err)
      this.deps.logger.warn(
        `cloud-sessions: starting ${sid} again for a sent message failed: ${message}`
      )
      if (t.conversationId) {
        this.deps.listener.chat({
          kind: 'error',
          conversationId: t.conversationId,
          message: `The cloud session stopped before it ran your message, and starting it again failed: ${message}`,
        })
      }
    })
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
    t.seedBase = info.session.seedBase ?? null
    t.replaying = true
    t.lastSeq = 0
    this.setState(sid, info.state)
    this.poller.watch(sid, { cursor: CURSOR_START, state: info.state })
    return info
  }

  /**
   * Resolves once the log that existed when the session was opened has
   * been read, or after `timeoutMs`: a view that waits, then reads
   * {@link stateOf}, shows the session as it is, not the states its log
   * passes through.
   */
  replayed(sid: string, timeoutMs = REPLAY_WAIT_MS): Promise<void> {
    const t = this.sessions.get(sid)
    if (!t?.replaying) return Promise.resolve()
    return new Promise((resolve) => {
      const done = (): void => {
        clearTimeout(timer)
        resolve()
      }
      const timer = setTimeout(done, timeoutMs)
      t.replayWaiters.push(done)
    })
  }

  /** Stop following a session (the view closed it). */
  close(sid: string): void {
    this.poller.unwatch(sid)
    const t = this.sessions.get(sid)
    if (t) this.endReplay(t)
  }

  private endReplay(t: Tracked): void {
    t.replaying = false
    for (const done of t.replayWaiters.splice(0)) done()
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
      const t = this.sessions.get(sid)
      if (t) this.endReplay(t)
      return
    }
    const t = this.track(sid)
    for (const event of stream.events) {
      if (event.seq <= t.lastSeq) continue
      t.lastSeq = event.seq
      this.handleEvent(sid, t, event)
    }
    this.setState(sid, stream.state)
    // After the state: a waiting view reads it with stateOf.
    if (!stream.more && t.replaying) this.endReplay(t)
    if (!stream.more && t.unanswered.size > 0) {
      this.autoResume(sid, t, stream.state)
    }
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
        t.unanswered.delete(chat.turnId)
      } else if (!t.conversationId && 'conversationId' in chat) {
        this.setConversation(sid, chat.conversationId)
      }
      this.deps.listener.chat(chat)
      return
    }
    switch (event.type) {
      case 'user-message':
        this.byTurn.set(event.turnId, sid)
        t.unanswered.delete(event.turnId)
        break
      case 'ask-user':
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
    const t = this.track(sid)
    if (command.type === 'message') this.byTurn.set(command.turnId, sid)
    // The user asked for these to end: don't start the session for them.
    if (command.type === 'stop') t.unanswered.clear()
    if (command.type === 'abort') t.unanswered.delete(command.turnId)
    const res =
      command.type === 'message'
        ? await this.postMessage(sid, command)
        : await this.deps.api.postCommand(sid, command)
    this.setState(sid, res.state)
    this.poller.poke(sid, res.state)
    if (res.state === 'sleeping' && command.type !== 'stop') {
      await this.resume(sid)
    }
    return res
  }

  /** Queue a `message`, remembering it until an event acknowledges it
   *  (from before the request: the harness may pick it up before the
   *  response arrives). */
  private async postMessage(
    sid: string,
    command: Extract<ClientCommandPayload, { type: 'message' }>
  ): Promise<PostCommandResponse> {
    const t = this.track(sid)
    const m: Unanswered = {
      sent: false,
      autoResumes: 0,
      nextAutoResumeAt: 0,
      spent: false,
    }
    t.unanswered.set(command.turnId, m)
    try {
      const res = await this.deps.api.postCommand(sid, command)
      m.sent = true
      return res
    } catch (err) {
      if (t.unanswered.get(command.turnId) === m) {
        t.unanswered.delete(command.turnId)
      }
      throw err
    }
  }

  /**
   * A later prompt (§10): add the @-mentioned files and the active file
   * that are new or changed since they were last sent (a batch through
   * `POST /sessions/:sid/files`, pre-signed PUTs and a commit), then
   * send the message with `context` naming them by `data/` path.
   */
  async sendMessage(
    sid: string,
    turnId: string,
    text: string,
    files?: PromptFiles
  ): Promise<PostCommandResponse> {
    const context = files
      ? await this.addPromptFiles(sid, turnId, files)
      : undefined
    return this.send(sid, {
      type: 'message',
      turnId,
      text,
      ...(context ? { context } : {}),
    })
  }

  /** A prompt typed while turn `turnId` runs. Its files are added the
   *  same way; `inject` carries no context. */
  async inject(
    sid: string,
    turnId: string,
    text: string,
    injectionId?: string,
    files?: PromptFiles
  ): Promise<PostCommandResponse> {
    if (files) await this.addPromptFiles(sid, turnId, files)
    return this.send(sid, {
      type: 'inject',
      turnId,
      text,
      ...(injectionId ? { injectionId } : {}),
    })
  }

  /**
   * The absolute local path of the session's seed base, from its
   * `seedBase` (`session.json`, so any machine maps files the same
   * way): the open workspace folder with that name, else the local
   * folder the user picked for it before, else ask once and remember.
   * Undefined when there is no seed base (workspace-relative fallback).
   */
  private async localSeedBase(
    sid: string,
    rec: SessionFilesRecord,
    folders: WorkspaceFolderRef[]
  ): Promise<string | undefined> {
    const t = this.track(sid)
    if (t.seedBase === undefined) {
      t.seedBase =
        (await this.deps.api.getSession(sid)).session.seedBase ?? null
    }
    const base = t.seedBase
    if (!base) return undefined
    const open = folders.find((f) => f.name === base.workspaceFolder)
    if (open) return seedBaseLocalPath(base, open.path)
    if (rec.localFolder) return seedBaseLocalPath(base, rec.localFolder)
    const picked = await this.deps.pickLocalFolder?.(sid, base.workspaceFolder)
    if (!picked) return undefined
    this.files.set(sid, { ...rec, localFolder: picked })
    return seedBaseLocalPath(base, picked)
  }

  /** Upload what changed; returns the message context. Throws
   *  `SeedLimitError` before uploading when a limit is hit. */
  private async addPromptFiles(
    sid: string,
    turnId: string,
    files: PromptFiles
  ): Promise<MessageContext | undefined> {
    let rec = this.files.get(sid) ?? { sent: {} }
    const base = await this.localSeedBase(sid, rec, files.workspaceFolders)
    rec = this.files.get(sid) ?? rec
    const roots = files.workspaceFolders.map((f) => f.path)
    const toData = (abs: string): string | null => dataPathFor(abs, base, roots)
    const changed = new Map<string, SeedFile & { hash: string }>()
    const skipped: string[] = []
    for (const src of files.sources) {
      const path = toData(src.path)
      if (!path) {
        skipped.push(src.path)
        continue
      }
      const hash = contentHash(src.bytes)
      if (rec.sent[path] !== hash && !changed.has(path)) {
        changed.set(path, { path, bytes: src.bytes, hash })
      }
    }
    if (skipped.length > 0) {
      this.deps.logger.info(
        `cloud-sessions: not adding ${skipped.length} file(s) outside the workspace: ${skipped.join(', ')}`
      )
    }
    const batch = [...changed.values()]
    if (batch.length > 0) {
      checkAddFilesSizes(batch)
      this.deps.listener.progress?.({
        turnId,
        sessionId: sid,
        phase: 'adding-files',
        fileCount: batch.length,
      })
      const res = await this.deps.api.addFiles(sid, {
        files: batch.map((f) => ({
          path: f.path,
          size: f.bytes.byteLength,
          contentType: contentTypeFor(f.path),
        })),
      })
      await Promise.all(
        batch.map((f) => {
          const target = res.uploads.find((u) => u.path === f.path)
          if (!target) throw new Error(`no upload URL for ${f.path}`)
          return this.deps.api.upload(target, f.bytes)
        })
      )
      await this.deps.api.commitFiles(sid, res.batchId)
      const sent = { ...rec.sent }
      for (const f of batch) sent[f.path] = f.hash
      this.files.set(sid, { ...rec, sent })
      this.poller.poke(sid)
    }
    return messageContext(
      files.activeFile ? (toData(files.activeFile) ?? undefined) : undefined,
      (files.mentions ?? []).map((m) => toData(m) ?? undefined)
    )
  }

  abort(sid: string, turnId: string): Promise<PostCommandResponse> {
    return this.send(sid, { type: 'abort', turnId })
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
    this.track(sid).unanswered.clear()
    const state = await this.deps.api.stopSession(sid)
    this.setState(sid, state)
    this.poller.poke(sid, state)
    return state
  }

  /** Delete a session. The Sessions API answers 204 at once, also while
   *  the task still runs (it is gone from lists and cleaned up later). */
  async delete(sid: string): Promise<void> {
    await this.deps.api.deleteSession(sid)
    this.poller.unwatch(sid)
    const t = this.sessions.get(sid)
    if (t?.conversationId) this.byConversation.delete(t.conversationId)
    this.sessions.delete(sid)
    this.files.set(sid, undefined)
  }
}
