import { promises as fs } from 'node:fs'
import * as path from 'node:path'
import {
  AiProxyClient,
  BuiltinTools,
  ChatService,
  PERMISSION_CATEGORIES,
  ToolDispatcher,
  fixedPermissionPolicy,
  type AiEndpoint,
  type AuthProvider,
  type L4Language,
  type Logger,
  type PermissionCategory,
  type PermissionValue,
  type ToolProvider,
  type Workspace,
} from '@repo/legalese-agent'
import {
  isRepoDataPath,
  sessionPaths,
  type AgentKeyFailure,
  type CloudCommand,
  type CloudEventPayload,
  type CommandType,
  type SessionState,
} from '@repo/legalese-agent/protocol'
import { loadAttachments } from './attachments.js'
import { CommandReader } from './command-reader.js'
import { SessionConversationStore } from './conversation-store.js'
import { EventLog } from './event-log.js'
import { CloudInteraction } from './interaction.js'
import { Lease, LeaseHeldError } from './lease.js'
import {
  DATA_DIR,
  DELETED_DIR,
  NodeWorkspace,
  TMP_DIR,
} from './node-workspace.js'
import { SessionJson } from './session-file.js'

/** Idle exit after this long with no running turn and no new command
 *  (spec §5.4). */
export const IDLE_EXIT_MS = 10 * 60 * 1000
/** `commands.seq` is polled this often (§8). */
export const COMMAND_POLL_MS = 1_000
/** SIGTERM gives 30 s before SIGKILL (§5.1); leave a margin. */
export const SHUTDOWN_BUDGET_MS = 25_000
/** How long a parked harness lets the current turn finish its step. */
export const PARK_TURN_GRACE_MS = 60_000

/**
 * Cloud tool policy (spec §11): cloud sessions never ask for tool
 * approval. Every category — file and L4 tools (confined to `repo/`),
 * the l4-rules MCP tools and the user's MCP servers passed at start —
 * runs without a prompt. File changes are backed up per turn and
 * committed, so a turn can be rolled back.
 */
export const CLOUD_PERMISSIONS: Record<PermissionCategory, PermissionValue> =
  Object.fromEntries(
    PERMISSION_CATEGORIES.map((c) => [c, 'always' as const])
  ) as Record<PermissionCategory, PermissionValue>

export type ExitReason = 'idle' | 'stop' | 'sigterm' | 'parked'

/** What plugins (git sync, MCP servers) get to work with. */
export interface RunnerContext {
  readonly sessionId: string
  /** `/workspace/sessions/<sid>` */
  readonly sessionDir: string
  readonly repoDir: string
  readonly stateDir: string
  readonly logger: Logger
  readonly l4: L4Language
  /** Append an event to the log. */
  emit(payload: CloudEventPayload): void
  /** Emit `session-state` for the current state (e.g. after a plugin
   *  changed {@link RunnerPlugin.sessionStateFields}). */
  announceState(): void
  /** Tool sources the dispatcher advertises; plugins may add to it. */
  readonly providers: ToolProvider[]
}

export interface TurnInfo {
  turnId: string
  /** The user's prompt as sent (the commit message summary). */
  prompt: string
  conversationId?: string
}

/**
 * Extension points for later items (git sync, MCP servers). All hooks
 * are optional; errors are logged and don't stop the harness, except in
 * `start`, where they do.
 */
export interface RunnerPlugin {
  readonly name: string
  /** After the lease and before the first command. */
  start?(ctx: RunnerContext): Promise<void>
  /** Extra `session-state` fields (the sealing public key). */
  sessionStateFields?(): { publicKey?: string }
  /** Command types this plugin handles. Types in {@link QUEUED_COMMANDS}
   *  run in the serial work queue (between turns, "when idle"); the
   *  rest run as soon as they're read. */
  readonly commands?: readonly CommandType[]
  handleCommand?(cmd: CloudCommand, ctx: RunnerContext): Promise<void>
  /** Context to prepend to a prompt (e.g. which turns were rolled back). */
  beforeTurn?(turn: TurnInfo, ctx: RunnerContext): Promise<string | undefined>
  /** After a turn finished (commit its changes). */
  afterTurn?(turn: TurnInfo, ctx: RunnerContext): Promise<void>
  /** After an `add-files` batch was copied into `repo/` (commit it).
   *  May return git blob ids by path for the `files-added` event. */
  onFilesAdded?(
    paths: string[],
    ctx: RunnerContext
  ): Promise<Record<string, string> | void>
  /** Before the harness exits (final commit, gc). */
  beforeExit?(reason: ExitReason, ctx: RunnerContext): Promise<void>
}

/** Commands that wait for the agent to be idle. */
export const QUEUED_COMMANDS: ReadonlySet<CommandType> = new Set<CommandType>([
  'message',
  'rollback',
  'apply-bundle',
  'add-files',
])

/** Controls the key chain (absent in `--dev`). */
export interface ChainControl {
  start(): Promise<boolean>
  end(): Promise<void>
  stopTimer(): void
}

export interface RunnerOptions {
  sessionId: string
  sessionDir: string
  taskId: string
  logger: Logger
  auth: AuthProvider
  chain?: ChainControl
  workspace: Workspace
  l4: L4Language & { dispose?(): Promise<void> }
  aiEndpoint: AiEndpoint
  /** Built-in extra tool sources (the l4-rules MCP server). */
  providers?: ToolProvider[]
  plugins?: RunnerPlugin[]
  extensionVersion: string
  idleExitMs?: number
  pollMs?: number
  now?: () => number
}

type Phase = 'new' | 'running' | 'stopping' | 'stopped'

/**
 * The cloud harness main loop (spec §5.4, §8, §11): take the lease,
 * renew the key chain, read commands every second, run turns one at a
 * time through the shared {@link ChatService}, append events, and exit
 * after 10 idle minutes, on `stop`, on SIGTERM, or when the chain can't
 * be renewed (parking).
 */
export class Runner {
  readonly events: EventLog
  readonly commands: CommandReader
  readonly lease: Lease
  readonly session: SessionJson
  readonly interaction: CloudInteraction
  readonly providers: ToolProvider[]
  private readonly chat: ChatService
  private readonly plugins: RunnerPlugin[]
  private readonly started = new Set<RunnerPlugin>()
  private readonly ctx: RunnerContext
  private readonly now: () => number
  private readonly idleExitMs: number
  private readonly pollMs: number

  private phase: Phase = 'new'
  private queue: CloudCommand[] = []
  private working: Promise<void> | null = null
  private activeTurn: string | null = null
  private conversationId: string | undefined
  private lastActivity: number
  private pollTimer: NodeJS.Timeout | null = null
  private polling = false
  private exitReason: ExitReason | null = null
  private parkedReason: AgentKeyFailure | undefined
  private stopped!: Promise<ExitReason>
  private resolveStopped!: (r: ExitReason) => void

  constructor(private readonly opts: RunnerOptions) {
    this.now = opts.now ?? Date.now
    this.idleExitMs = opts.idleExitMs ?? IDLE_EXIT_MS
    this.pollMs = opts.pollMs ?? COMMAND_POLL_MS
    this.lastActivity = this.now()
    const stateDir = path.join(opts.sessionDir, 'state')
    this.events = new EventLog(stateDir, opts.logger, { now: this.now })
    this.commands = new CommandReader(stateDir, opts.logger, { now: this.now })
    this.lease = new Lease(stateDir, opts.taskId, opts.logger, {
      now: this.now,
    })
    this.session = new SessionJson(opts.sessionDir)
    this.plugins = opts.plugins ?? []
    this.providers = [...(opts.providers ?? [])]
    this.interaction = new CloudInteraction(
      (p) => this.events.emit(p),
      (waiting) => this.onWaitingChange(waiting)
    )
    const store = new SessionConversationStore({
      onConversation: (id) => this.onConversation(id),
      onTitle: (_id, title) => this.onTitle(title),
    })
    const dispatcher = new ToolDispatcher({
      logger: opts.logger,
      tools: new BuiltinTools(opts.workspace, opts.l4),
      permissions: fixedPermissionPolicy(CLOUD_PERMISSIONS),
      interaction: this.interaction,
      providers: this.providers,
    })
    this.chat = new ChatService({
      auth: opts.auth,
      store,
      proxy: new AiProxyClient({
        auth: opts.auth,
        logger: opts.logger,
        endpoint: () => opts.aiEndpoint,
      }),
      logger: opts.logger,
      dispatcher,
      interaction: this.interaction,
      l4: opts.l4,
      // The file the user had open when they sent the prompt
      // (`message.context.activeFile`), as the `<editor-context>`.
      editor: {
        describe: (chip) => (chip ? { activeFile: { path: chip.path } } : null),
        activeL4Document: () => null,
      },
      extensionVersion: opts.extensionVersion,
    })
    this.ctx = {
      sessionId: opts.sessionId,
      sessionDir: opts.sessionDir,
      repoDir: path.join(opts.sessionDir, 'repo'),
      stateDir,
      logger: opts.logger,
      l4: opts.l4,
      emit: (p) => this.events.emit(p),
      announceState: () => this.announceState(),
      providers: this.providers,
    }
    this.stopped = new Promise((r) => (this.resolveStopped = r))
  }

  get context(): RunnerContext {
    return this.ctx
  }

  /**
   * Run until the harness should exit. Resolves with the exit reason, or
   * `null` when another harness holds the lease (nothing was touched).
   */
  async run(): Promise<ExitReason | null> {
    const { logger } = this.opts
    const st = await fs.stat(this.opts.sessionDir).catch(() => null)
    if (!st?.isDirectory()) {
      throw new Error('session folder does not exist')
    }
    try {
      await this.lease.acquire()
    } catch (err) {
      if (err instanceof LeaseHeldError) {
        logger.warn(err.message)
        return null
      }
      throw err
    }
    this.phase = 'running'
    try {
      await this.events.open()
      await this.commands.open()
      if (this.opts.workspace instanceof NodeWorkspace) {
        await this.opts.workspace.ensureLayout()
      }
      const session = await this.session.read()
      this.conversationId = session.conversationId
      if (this.opts.chain && !(await this.opts.chain.start())) {
        // The chain ended during the first renewal; onChainEnded parks.
        await this.stopped
        return this.exitReason
      }
      await this.session.update({
        status: 'running',
        parkedReason: null,
        lastActivity: this.now(),
      })
      for (const p of this.plugins) {
        if (p.start) await p.start(this.ctx)
        this.started.add(p)
      }
      this.announceState()
      await this.events.flush()
      logger.info(
        `harness running (commands handled ${this.commands.handled}, events ${this.events.lastSeq})`
      )
    } catch (err) {
      logger.error('harness start failed', err)
      await this.finish('stop').catch(() => undefined)
      throw err
    }
    this.pollTimer = setInterval(() => void this.tick(), this.pollMs)
    void this.tick()
    return this.stopped
  }

  /** SIGTERM: exit like an idle exit, within the stop timeout. */
  terminate(): void {
    void this.shutdown('sigterm')
  }

  /** The key chain ended (renew refused, or upstream failures outlasted
   *  the key). */
  onChainEnded(reason: AgentKeyFailure): void {
    if (this.phase === 'stopping' || this.phase === 'stopped') return
    if (reason === 'inactive' && !this.working && this.queue.length === 0) {
      // No real use for 10 minutes and nothing to do: just go to sleep.
      void this.shutdown('idle')
      return
    }
    this.parkedReason = reason
    this.events.emit({ type: 'auth-required', reason })
    void this.shutdown('parked')
  }

  // ── Main loop ──────────────────────────────────────────────────────

  private async tick(): Promise<void> {
    if (this.polling || this.phase !== 'running') return
    this.polling = true
    try {
      const cmds = await this.commands.poll()
      for (const cmd of cmds) {
        if (this.phase !== 'running') break
        this.lastActivity = this.now()
        await this.dispatch(cmd)
      }
      if (
        this.phase === 'running' &&
        !this.working &&
        this.queue.length === 0 &&
        this.now() - this.lastActivity >= this.idleExitMs
      ) {
        this.opts.logger.info('idle; going to sleep')
        void this.shutdown('idle')
      }
    } catch (err) {
      this.opts.logger.error('command poll failed', err)
    } finally {
      this.polling = false
    }
  }

  private async dispatch(cmd: CloudCommand): Promise<void> {
    const { logger } = this.opts
    logger.info(`command ${cmd.id} ${cmd.type}`)
    if (QUEUED_COMMANDS.has(cmd.type)) {
      this.queue.push(cmd)
      this.drain()
      return
    }
    try {
      switch (cmd.type) {
        case 'inject':
          this.inject(cmd)
          break
        case 'abort':
          this.abort(cmd.turnId)
          break
        case 'answer':
          this.interaction.answer(cmd.callId, cmd.answer)
          break
        case 'stop':
          this.queue = []
          await this.commands.markHandledThrough(cmd.id)
          void this.shutdown('stop')
          return
        default:
          await this.runPluginCommand(cmd)
      }
    } catch (err) {
      logger.error(`command ${cmd.id} ${cmd.type} failed`, err)
    }
    await this.commands.markHandled(cmd.id)
  }

  private inject(cmd: Extract<CloudCommand, { type: 'inject' }>): void {
    const injectionId = cmd.injectionId ?? `inj-${cmd.id}`
    if (this.activeTurn === cmd.turnId) {
      this.events.emit({
        type: 'user-message',
        turnId: cmd.turnId,
        text: cmd.text,
        attachments: [],
      })
      this.chat.inject({
        turnId: cmd.turnId,
        injectionId,
        conversationId: this.conversationId ?? cmd.turnId,
        text: cmd.text,
        mentions: [],
        attachments: [],
        includeActiveFile: false,
      })
      return
    }
    // The turn already ended: run the message as a turn of its own.
    this.events.emit({
      type: 'queue-consumed',
      conversationId: this.conversationId ?? cmd.turnId,
      injectionIds: [injectionId],
    })
    this.queue.push({
      id: cmd.id,
      ts: cmd.ts,
      type: 'message',
      turnId: `${cmd.turnId}.${injectionId}`.slice(0, 128),
      text: cmd.text,
    })
    this.drain()
  }

  private abort(turnId: string): void {
    const queued = this.queue.findIndex(
      (c) => c.type === 'message' && c.turnId === turnId
    )
    if (queued >= 0) {
      const [cmd] = this.queue.splice(queued, 1)
      this.events.emit({
        type: 'done',
        conversationId: this.conversationId ?? turnId,
        finishReason: 'aborted',
      })
      if (cmd) void this.commands.markHandled(cmd.id)
      return
    }
    this.interaction.pending.cancelTurn(turnId)
    this.chat.abort(turnId)
  }

  /** Run queued commands one at a time. */
  private drain(): void {
    if (this.working) return
    const next = this.queue.shift()
    if (!next || this.phase !== 'running') return
    this.working = this.runQueued(next)
      .catch((err) =>
        this.opts.logger.error(`command ${next.id} ${next.type} failed`, err)
      )
      .finally(() => {
        this.working = null
        this.lastActivity = this.now()
        this.drain()
      })
  }

  private async runQueued(cmd: CloudCommand): Promise<void> {
    if (cmd.type === 'message') {
      await this.commands.markHandled(cmd.id)
      await this.runTurn(cmd)
      return
    }
    if (cmd.type === 'add-files') {
      try {
        await this.addFiles(cmd)
      } finally {
        await this.commands.markHandled(cmd.id)
      }
      return
    }
    try {
      await this.runPluginCommand(cmd)
    } finally {
      await this.commands.markHandled(cmd.id)
    }
  }

  /**
   * `add-files` (§10): copy `incoming/files/<batchId>/<path>` into
   * `repo/<path>` (under `data/`), let plugins commit it ("Add files from
   * the user"), emit `files-added`, then remove the batch.
   */
  private async addFiles(
    cmd: Extract<CloudCommand, { type: 'add-files' }>
  ): Promise<void> {
    const { logger } = this.opts
    const ws = this.opts.workspace
    // Validates the batch id; relative to the user folder.
    sessionPaths(this.opts.sessionId).incomingFilesBatch(cmd.batchId)
    const batchDir = path.join(
      this.opts.sessionDir,
      'incoming',
      'files',
      cmd.batchId
    )
    if (!(ws instanceof NodeWorkspace)) {
      logger.warn('add-files needs the Node workspace; skipped')
      return
    }
    const added: string[] = []
    for (const f of cmd.files) {
      if (!isRepoDataPath(f.path)) continue
      const source = path.join(batchDir, ...f.path.split('/'))
      // The batch folder is API-written but lives in the user's folder:
      // refuse anything reached through a link.
      const real = await fs.realpath(source).catch(() => null)
      const realBatch = await fs.realpath(batchDir).catch(() => null)
      if (
        !real ||
        !realBatch ||
        real !== path.join(realBatch, ...f.path.split('/'))
      ) {
        logger.warn(
          `add-files ${cmd.batchId}: a file is missing or a link; skipped`
        )
        continue
      }
      try {
        if (await ws.importFile(source, f.path)) added.push(f.path)
      } catch (err) {
        logger.warn(
          `add-files ${cmd.batchId}: copy failed: ${(err as Error).message}`
        )
      }
    }
    let shas: Record<string, string> = {}
    if (added.length > 0) {
      for (const plugin of this.plugins) {
        if (!plugin.onFilesAdded || !this.started.has(plugin)) continue
        try {
          shas = {
            ...shas,
            ...((await plugin.onFilesAdded(added, this.ctx)) ?? {}),
          }
        } catch (err) {
          logger.error(`plugin ${plugin.name} onFilesAdded failed`, err)
        }
      }
    }
    this.events.emit({
      type: 'files-added',
      batchId: cmd.batchId,
      files: added.map((path) =>
        shas[path] ? { path, sha: shas[path] } : { path }
      ),
    })
    await fs.rm(batchDir, { recursive: true, force: true })
    logger.info(
      `add-files ${cmd.batchId}: ${added.length}/${cmd.files.length} file(s) added`
    )
  }

  private async runPluginCommand(cmd: CloudCommand): Promise<void> {
    const plugin = this.plugins.find((p) => p.commands?.includes(cmd.type))
    if (!plugin?.handleCommand) {
      this.opts.logger.warn(
        `command ${cmd.id}: ${cmd.type} is not supported by this harness; skipped`
      )
      return
    }
    await plugin.handleCommand(cmd, this.ctx)
  }

  private async runTurn(
    cmd: Extract<CloudCommand, { type: 'message' }>
  ): Promise<void> {
    const { logger } = this.opts
    const turn: TurnInfo = {
      turnId: cmd.turnId,
      prompt: cmd.text,
      conversationId: this.conversationId,
    }
    const { loaded, missing } = await loadAttachments(
      path.join(this.opts.sessionDir, 'attachments'),
      cmd.attachments ?? []
    )
    if (missing.length > 0) {
      logger.warn(`turn ${cmd.turnId}: ${missing.length} attachment(s) missing`)
    }
    this.events.emit({
      type: 'user-message',
      turnId: cmd.turnId,
      text: cmd.text,
      attachments: loaded.map((a) => a.ref),
    })
    let prefix = ''
    for (const p of this.plugins) {
      if (!p.beforeTurn) continue
      try {
        const extra = await p.beforeTurn(turn, this.ctx)
        if (extra) prefix += extra + '\n\n'
      } catch (err) {
        logger.error(`plugin ${p.name} beforeTurn failed`, err)
      }
    }
    prefix += standingNote(cmd.turnId) + '\n\n'
    this.activeTurn = cmd.turnId
    if (this.opts.workspace instanceof NodeWorkspace) {
      this.opts.workspace.setTurn(cmd.turnId)
    }
    await this.setState('busy', cmd.turnId)
    await this.session
      .update({ lastActivity: this.now() })
      .catch((err) => logger.warn(`session.json update failed: ${String(err)}`))
    const started = this.now()
    try {
      await this.chat.start({
        conversationId: this.conversationId,
        turnId: cmd.turnId,
        text: prefix + cmd.text,
        mentions: (cmd.context?.mentions ?? []).map((label) => ({
          kind: 'file' as const,
          label,
        })),
        attachments: loaded.map((a) => a.attachment),
        includeActiveFile: !!cmd.context?.activeFile,
        ...(cmd.context?.activeFile
          ? {
              activeFile: {
                path: cmd.context.activeFile,
                name: path.posix.basename(cmd.context.activeFile),
              },
            }
          : {}),
      })
    } finally {
      this.activeTurn = null
      logger.info(`turn ${cmd.turnId} finished in ${this.now() - started} ms`)
    }
    turn.conversationId = this.conversationId
    for (const p of this.plugins) {
      if (!p.afterTurn) continue
      try {
        await p.afterTurn(turn, this.ctx)
      } catch (err) {
        logger.error(`plugin ${p.name} afterTurn failed`, err)
      }
    }
    if (this.opts.workspace instanceof NodeWorkspace) {
      this.opts.workspace.setTurn(null)
    }
    await this.session
      .update({ lastActivity: this.now() })
      .catch((err) => logger.warn(`session.json update failed: ${String(err)}`))
    if (this.phase === 'running') await this.setState('running')
    await this.events.flush()
  }

  // ── State ──────────────────────────────────────────────────────────

  private onConversation(id: string): void {
    if (this.conversationId === id) return
    this.conversationId = id
    this.session
      .update({ conversationId: id })
      .catch((err) =>
        this.opts.logger.warn(`session.json conversationId: ${String(err)}`)
      )
  }

  private onTitle(title: string): void {
    this.session
      .read()
      .then((s) => (s.title ? undefined : this.session.update({ title })))
      .catch((err) =>
        this.opts.logger.warn(`session.json title: ${String(err)}`)
      )
  }

  private onWaitingChange(waiting: boolean): void {
    if (!this.activeTurn || this.phase !== 'running') return
    void this.setState(waiting ? 'waiting' : 'busy', this.activeTurn)
  }

  private async setState(
    state: 'running' | 'busy' | 'waiting',
    turnId?: string
  ): Promise<void> {
    const before = this.lease.current
    await this.lease.set(state, turnId)
    if (before.state !== state) this.announceState()
  }

  private announceState(state?: SessionState): void {
    const s = state ?? this.lease.current.state
    let extra: { publicKey?: string } = {}
    if (s === 'running' || s === 'busy' || s === 'waiting') {
      for (const p of this.plugins) {
        extra = { ...extra, ...(p.sessionStateFields?.() ?? {}) }
      }
    }
    this.events.emit({ type: 'session-state', state: s, ...extra })
  }

  // ── Exit ───────────────────────────────────────────────────────────

  /** Begin an orderly exit (idempotent). */
  async shutdown(reason: ExitReason): Promise<ExitReason> {
    if (this.phase === 'stopping' || this.phase === 'stopped') {
      return this.stopped
    }
    const wasRunning = this.phase === 'running'
    this.phase = 'stopping'
    if (!wasRunning) {
      this.exitReason = reason
      this.resolveStopped(reason)
      return reason
    }
    await this.finish(reason).catch((err) => {
      this.opts.logger.error('shutdown failed', err)
      this.phase = 'stopped'
      this.resolveStopped(reason)
    })
    return this.stopped
  }

  private async finish(reason: ExitReason): Promise<void> {
    const { logger } = this.opts
    this.phase = 'stopping'
    this.exitReason = reason
    logger.info(`shutting down (${reason})`)
    const deadline = this.now() + SHUTDOWN_BUDGET_MS
    if (this.pollTimer) clearInterval(this.pollTimer)
    this.pollTimer = null
    this.opts.chain?.stopTimer()
    // Nothing new starts; queued commands stay unhandled for the next
    // start (except after `stop`, which cleared them).
    this.queue = []
    const working = this.working
    if (working) {
      if (reason === 'parked') {
        // Let the current step finish: model calls fail fast now, so the
        // turn ends on its own; abort it if it doesn't.
        await waitFor(working, PARK_TURN_GRACE_MS)
      }
      if (this.activeTurn) {
        this.interaction.pending.cancelTurn(this.activeTurn)
        this.chat.abort(this.activeTurn)
      }
      await waitFor(working, Math.max(0, deadline - this.now() - 10_000))
    }
    this.interaction.pending.cancelAll()
    // Only plugins that started (the chain can end before they do).
    for (const p of this.plugins) {
      if (!p.beforeExit || !this.started.has(p)) continue
      try {
        await waitFor(
          p.beforeExit(reason, this.ctx),
          Math.max(1_000, deadline - this.now() - 5_000)
        )
      } catch (err) {
        logger.error(`plugin ${p.name} beforeExit failed`, err)
      }
    }
    if (reason !== 'parked' && this.opts.chain) {
      await waitFor(this.opts.chain.end(), 5_000)
    }
    const status = reason === 'parked' ? 'parked' : 'sleeping'
    await this.session
      .update({
        status,
        parkedReason:
          reason === 'parked' ? (this.parkedReason ?? 'invalid_key') : null,
        lastActivity: this.now(),
      })
      .catch((err) => logger.error('session.json status update failed', err))
    this.announceState(status)
    await this.events
      .flush()
      .catch((err) => logger.error('event flush failed', err))
    await this.lease
      .release()
      .catch((err) => logger.error('lease release failed', err))
    await waitFor(this.opts.l4.dispose?.() ?? Promise.resolve(), 3_000)
    this.phase = 'stopped'
    logger.info(`stopped (${reason})`)
    this.resolveStopped(reason)
  }
}

/** Wait for `p` at most `ms`; never rejects. */
function waitFor(p: Promise<unknown>, ms: number): Promise<void> {
  return new Promise((resolve) => {
    const t = setTimeout(resolve, ms)
    p.then(
      () => {
        clearTimeout(t)
        resolve()
      },
      () => {
        clearTimeout(t)
        resolve()
      }
    )
  })
}

/**
 * The standing note about the session layout, sent with every prompt
 * (the core package has no per-turn system-note hook, and the harness
 * doesn't change the core).
 */
export function standingNote(turnId: string): string {
  return (
    `<cloud-session-note>The session files live in ${DATA_DIR}/. ${TMP_DIR}/ is your scratch space for temporary work (notes, drafts, experiments) that shouldn't be in ${DATA_DIR}/; read, create, edit and delete there freely with the fs tools. ` +
    `The L4 tools work on files in both. \`IMPORT name\` finds ${DATA_DIR}/name.l4 first, then name.l4 next to the importing file, so a ${TMP_DIR}/ draft can import ${DATA_DIR}/ modules and its ${TMP_DIR}/ siblings — but a ${TMP_DIR}/ module can't shadow a ${DATA_DIR}/ module of the same name, so give experimental modules their own names. ` +
    `Files you delete from ${DATA_DIR}/ are first copied to ${DELETED_DIR}/t-${turnId}/<path> (this turn) — to restore one, read it there and write it back. ` +
    'Changes from earlier turns can also be undone by the user rolling back a turn.</cloud-session-note>'
  )
}
