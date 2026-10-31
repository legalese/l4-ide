import type {
  AiProxyTool,
  Logger,
  PermissionPolicy,
  ToolCallContext,
  ToolProvider,
  UserInteraction,
} from './ports.js'
import {
  categoriesForCall,
  categoryForTool,
  strictestPermission,
  type PermissionCategory,
  type PermissionValue,
} from './permissions.js'
import {
  EditGuard,
  NEW_FILE,
  type FileSnapshot,
  type KnockOnFile,
} from './edit-guard.js'
import { BUILTIN_TOOLS } from './tool-registry.js'
import { metaAskUser } from './tools/ask-user.js'
import type { BuiltinTools, ToolSessionContext } from './tools/builtin-tools.js'
import type { FsCopyArgs, FsCreateArgs, FsEditArgs } from './tools/fs.js'
import { l4FileState } from './tools/lsp.js'
import type { L4RefactorArgs } from './tools/refactor.js'

/** Result returned to the proxy as the content of a `role:"tool"` message. */
export type ToolResult =
  | { ok: true; output: string }
  | { ok: false; error: string; code?: 'denied' | 'unknown_tool' | 'failed' }

export interface ToolCall {
  callId: string
  name: string
  argsJson: string
}

/**
 * Front door for every tool_call that comes back from the proxy. It
 *  1. picks the right permission category,
 *  2. consults the {@link PermissionPolicy},
 *  3. either runs the tool, refuses it, or requests explicit approval
 *     through {@link UserInteraction} — scoped to the conversation and
 *     turn in the {@link ToolCallContext},
 *  4. returns a `ToolResult` that the chat-service folds into the
 *     follow-up request to the proxy.
 *
 * 'alwaysAllow' is handled by the host (it bumps the policy through
 * {@link PermissionPolicy.setPermission}, then resolves the approval as
 * 'allow').
 */
export interface ToolDispatcherOptions {
  logger: Logger
  /** This session's built-in fs / L4 tools. */
  tools: BuiltinTools
  permissions: PermissionPolicy
  interaction: UserInteraction
  /** Prefixed tool sources (l4-rules MCP, the user's MCP servers),
   *  advertised after the built-ins in this order. */
  providers?: ToolProvider[]
}

/** Snapshot captured before a fs__edit_file / fs__create_file runs, so
 *  the applied-diff view can show an accurate "before" side once the
 *  write lands on disk. */
export interface AppliedEditSnapshot {
  callId: string
  /** Workspace URI of the edited file. */
  uri: string
  relativePath: string
  /** File contents before the tool ran. `''` for a created-new file. */
  before: string
}

export class ToolDispatcher {
  private readonly guard = new EditGuard()
  /** Pre-edit snapshots keyed by callId, populated for fs__edit_file
   *  and fs__create_file. Lives for the extension's lifetime — small
   *  values, turnover is low. Used by the register layer to resolve
   *  cmd+click on a tool row into a "before/after" diff. */
  private readonly edits = new Map<string, AppliedEditSnapshot>()
  private readonly providers: ToolProvider[]

  constructor(private readonly opts: ToolDispatcherOptions) {
    this.providers = opts.providers ?? []
  }

  /** Resolve a tool-call's target file to its current URI. Read /
   *  create / edit / delete take `{ path }`; copy targets `to`. */
  resolveFile(call: ToolCall): string | null {
    // A create can land on another name than the one it asked for.
    if (call.name === 'fs__create_file') {
      const uri = this.edits.get(call.callId)?.uri
      if (uri) return uri
    }
    try {
      const p = targetPath(call.name, JSON.parse(call.argsJson || '{}'))
      if (!p) return null
      return this.opts.tools.resolveFileUri(p)
    } catch {
      return null
    }
  }

  /** The permission that currently applies to a call (by its
   *  arguments, when known), or null for an unknown tool. Lets the chat
   *  service render a tool row in its real initial state
   *  (pending-approval vs running). */
  permissionFor(name: string, argsJson = ''): PermissionValue | null {
    const args = argsOrNull(argsJson)
    const permission = strictestPermission(
      this.opts.permissions,
      categoriesForCall(name, args)
    )?.permission
    if (!permission) return null
    return this.withWriteApproval(permission, name, args)
  }

  /** `ask` instead of `always` when the call writes a file the workspace
   *  wants confirmed. `never` stays `never`. */
  private withWriteApproval(
    permission: PermissionValue,
    name: string,
    args: unknown
  ): PermissionValue {
    if (permission !== 'always') return permission
    const workspace = this.opts.tools.workspace
    if (!workspace.requiresWriteApproval) return permission
    for (const p of writtenPaths(name, args)) {
      try {
        if (workspace.requiresWriteApproval(workspace.resolvePath(p))) {
          return 'ask'
        }
      } catch {
        // A path that doesn't resolve fails when the tool runs.
      }
    }
    return permission
  }

  /** Category for a tool name, or null for an unknown tool. */
  categoryFor(name: string): PermissionCategory | null {
    return categoryForTool(name)
  }

  /**
   * Everything advertised to the model: the built-ins, then each
   * provider's tools. A provider that fails to list contributes nothing
   * for this round.
   */
  async listTools(): Promise<AiProxyTool[]> {
    const tools: AiProxyTool[] = [...BUILTIN_TOOLS]
    for (const provider of this.providers) {
      try {
        tools.push(...(await provider.listTools()))
      } catch (err) {
        this.opts.logger.warn(
          `chat-service: ${provider.prefix} tools/list failed: ${err instanceof Error ? err.message : String(err)}`
        )
      }
    }
    return tools
  }

  /** What each provider wants the model told on the first turn. */
  async promptIndexes(): Promise<string[]> {
    const out: string[] = []
    for (const provider of this.providers) {
      try {
        const index = await provider.promptIndex?.()
        if (index) out.push(index)
      } catch (err) {
        this.opts.logger.warn(
          `chat-service: ${provider.prefix} index failed: ${err instanceof Error ? err.message : String(err)}`
        )
      }
    }
    return out
  }

  /** `(deployId, fnName)` for a deployed-rule tool, for display. */
  getToolTarget(
    name: string,
    argsJson?: string
  ): { deployId: string; fnName: string } | null {
    for (const provider of this.providers) {
      if (!name.startsWith(provider.prefix)) continue
      const target = provider.getToolTarget?.(name, argsJson)
      if (target) return target
    }
    return null
  }

  /** Call before running the tool calls of one model response. */
  beginRound(turnId: string, calls: ToolCall[]): void {
    const uris: string[] = []
    for (const call of calls) {
      if (call.name !== 'fs__edit_file') continue
      const p = targetPath(call.name, argsOrNull(call.argsJson))
      const uri = p ? this.opts.tools.resolveFileUri(p) : null
      if (uri) uris.push(uri)
    }
    this.guard.beginRound(turnId, uris)
  }

  private async snapshot(uri: string): Promise<FileSnapshot | null> {
    const { l4 } = this.opts.tools
    try {
      const checked = await l4.getCheckedDiagnostics(uri)
      const rows = l4.getDirectiveResults(uri) ?? []
      return {
        state: l4FileState(checked),
        checks: rows
          .filter((r) => r.success !== null)
          .map(({ body, success }) => ({ body, success })),
      }
    } catch {
      return null
    }
  }

  /** Where the turn's edited files stand now; `null` for one that's gone. */
  private async currentFiles(
    turnId: string
  ): Promise<Map<string, FileSnapshot | null>> {
    const { workspace } = this.opts.tools
    const files = this.guard.trackedFiles(turnId)
    const snapshots = await Promise.all(
      files.map(async (f): Promise<[string, FileSnapshot | null]> => {
        const exists = await workspace
          .stat(workspace.pathForUri(f.uri))
          .catch(() => null)
        return [f.uri, exists ? await this.snapshot(f.uri) : null]
      })
    )
    return new Map(snapshots)
  }

  /** A message to continue the turn with, when it would otherwise end
   *  with compile errors of its own making. */
  async stopNudge(turnId: string): Promise<string | null> {
    return this.guard.stopNudge(
      turnId,
      await this.currentFiles(turnId),
      this.knockOnFiles(turnId)
    )
  }

  private knockOnFiles(turnId: string): KnockOnFile[] {
    const { l4, workspace } = this.opts.tools
    return this.guard.knockOnFiles(turnId, l4.fileErrorCounts?.(), (uri) =>
      workspace.relativePath(uri)
    )
  }

  /** Status of the files this turn edited, once. */
  async takeTurnStatus(turnId: string): Promise<string | null> {
    return this.guard.takeStatus(
      turnId,
      await this.currentFiles(turnId),
      this.knockOnFiles(turnId)
    )
  }

  endTurn(turnId: string): void {
    this.guard.endTurn(turnId)
  }

  /** Look up the pre-edit snapshot for a tool call. Returns null if
   *  the tool wasn't file-mutating or ran before we started tracking. */
  snapshotFor(callId: string): AppliedEditSnapshot | undefined {
    return this.edits.get(callId)
  }

  /**
   * Dispatch a single tool call end-to-end. On return, the caller can
   * use `.output` (or `.error`) as the content for a `role:"tool"`
   * message in the follow-up chat request.
   */
  async run(call: ToolCall, ctx: ToolCallContext): Promise<ToolResult> {
    const notifyStatus = (
      status: Parameters<UserInteraction['notifyToolStatus']>[1],
      detail?: { result?: string; error?: string }
    ): void =>
      this.opts.interaction.notifyToolStatus(call.callId, status, detail, ctx)
    // Status updates render as plain assistant prose upstream — the
    // chat-service has already streamed the text into the message
    // bubble before this dispatcher runs. Skip the permission gate
    // and the notifyStatus side-channel so the webview never sees a
    // tool-call card synthesised from a phantom status event.
    if (call.name === 'meta__post_status_update') {
      return { ok: true, output: 'ok' }
    }
    const category = categoryForTool(call.name)
    if (!category) {
      this.opts.logger.warn(`tool/unknown: ${call.name}`)
      return {
        ok: false,
        code: 'unknown_tool',
        error: `Unknown tool: ${call.name}`,
      }
    }
    // The strictest of what the call needs (a move also deletes).
    const { category: deciding, permission: categoryPermission } =
      strictestPermission(
        this.opts.permissions,
        categoriesForCall(call.name, argsOrNull(call.argsJson))
      ) ?? {
        category,
        permission: this.opts.permissions.getPermission(category),
      }
    const permission = this.withWriteApproval(
      categoryPermission,
      call.name,
      argsOrNull(call.argsJson)
    )
    this.opts.logger.info(
      `tool/dispatch ${call.name} (category=${deciding}, permission=${permission}) args=${call.argsJson}`
    )
    if (permission === 'never') {
      notifyStatus('error', { error: 'Denied by user settings' })
      return {
        ok: false,
        code: 'denied',
        error: `User has disallowed the "${deciding}" category. Update the setting in the Legalese AI settings to enable it.`,
      }
    }
    if (permission === 'ask') {
      notifyStatus('pending-approval')
      const decision = await this.opts.interaction.requestApproval(call, ctx)
      if (decision === 'deny') {
        notifyStatus('error', { error: 'Denied' })
        return {
          ok: false,
          code: 'denied',
          error: 'The user denied this tool call.',
        }
      }
    }
    notifyStatus('running')
    try {
      const args = parseArgs(call.argsJson)
      // Snapshot the file BEFORE a mutating tool runs so the UI can
      // render the actual applied diff afterwards (not a "proposed"
      // preview that may never have been committed).
      await this.snapshotIfMutating(call, args)
      const output = await this.execute(
        call.callId,
        call.name,
        args,
        call.argsJson,
        ctx
      )
      notifyStatus('done', { result: output })
      return { ok: true, output }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.opts.logger.warn(`tool/failed ${call.name}: ${msg}`)
      notifyStatus('error', { error: msg })
      return { ok: false, code: 'failed', error: msg }
    }
  }

  private async snapshotIfMutating(
    call: ToolCall,
    args: unknown
  ): Promise<void> {
    if (
      call.name !== 'fs__edit_file' &&
      call.name !== 'fs__create_file' &&
      call.name !== 'fs__copy_file'
    ) {
      return
    }
    const p = targetPath(call.name, args)
    if (!p) return
    const tools = this.opts.tools
    const uri = tools.resolveFileUri(p)
    if (!uri) return
    try {
      const before = await tools.currentContents(p)
      this.edits.set(call.callId, {
        callId: call.callId,
        uri,
        relativePath: tools.workspace.relativePath(uri),
        before,
      })
    } catch {
      // Snapshot is best-effort; without it the diff view falls back
      // to an empty "before" side.
    }
  }

  private async execute(
    callId: string,
    name: string,
    args: unknown,
    argsJson: string,
    ctx: ToolCallContext
  ): Promise<string> {
    const provider = this.providers.find((p) => name.startsWith(p.prefix))
    if (provider) return provider.callTool(name, argsJson)
    const tools = this.opts.tools
    switch (name) {
      case 'fs__read_file':
        return tools.readFile(args as { path: string })
      case 'fs__create_file':
        return this.createFile(callId, args as FsCreateArgs, ctx)
      case 'fs__edit_file':
        return this.editFile(args as FsEditArgs, ctx)
      case 'fs__delete_file':
        return tools.deleteFile(args as { path: string })
      case 'fs__copy_file':
        return this.copyFile(args as FsCopyArgs, ctx)
      case 'l4__evaluate':
        return tools.evaluate(
          args as {
            path: string
            timeoutMs?: number
            mode?: 'changed' | 'full'
          },
          ctx
        )
      case 'l4__refactor':
        return tools.refactor(args as L4RefactorArgs)
      case 'meta__ask_user':
        return metaAskUser(
          callId,
          args as { question: string; choices?: string[] },
          (id, question, choices) =>
            this.opts.interaction.askUser(
              { callId: id, question, choices },
              ctx
            )
        )
      default:
        throw new Error(`No executor for tool: ${name}`)
    }
  }

  private async createFile(
    callId: string,
    args: FsCreateArgs,
    ctx: ToolCallContext
  ): Promise<string> {
    const tools = this.opts.tools
    const blocked = (() => {
      const uri = tools.resolveFileUri(args.path)
      return uri ? this.guard.blocked(ctx.turnId, uri) : null
    })()
    if (blocked) throw new Error(blocked)
    const result = await tools.createFileDetailed(args, this.toolContext(ctx))
    // The snapshot was taken for the requested path. When the content went
    // to a numbered name, the file there is unrelated to this call.
    const snapshot = this.edits.get(callId)
    if (snapshot && snapshot.uri !== result.uri) {
      snapshot.uri = result.uri
      snapshot.relativePath = result.relative
      snapshot.before = ''
    }
    if (result.state) {
      this.guard.track(ctx.turnId, result.uri, result.relative, NEW_FILE)
      this.guard.recordState(ctx.turnId, result.uri, result.state)
    }
    return result.output
  }

  /** A copy can put a broken file in place of a good one, so it counts as
   *  an edit of its target. `fs__create_file` itself suggests this route. */
  private async copyFile(
    args: FsCopyArgs,
    ctx: ToolCallContext
  ): Promise<string> {
    const tools = this.opts.tools
    const to = tools.workspace.resolvePath(args.to)
    const blocked = this.guard.blocked(ctx.turnId, to.uri)
    if (blocked) throw new Error(blocked)
    if (
      to.fsPath.toLowerCase().endsWith('.l4') &&
      !this.guard.isTracked(ctx.turnId, to.uri)
    ) {
      this.guard.noteErrorsBefore(ctx.turnId, tools.l4.fileErrorCounts?.())
      const exists = await tools.workspace.stat(to.fsPath)
      const baseline = exists ? await this.snapshot(to.uri) : NEW_FILE
      this.guard.track(
        ctx.turnId,
        to.uri,
        to.relative,
        baseline ?? { state: null, checks: [] }
      )
    }
    const result = await tools.copyFileDetailed(args, this.toolContext(ctx))
    if (result.state) {
      this.guard.recordState(ctx.turnId, result.uri, result.state)
    }
    return result.output
  }

  private async editFile(
    args: FsEditArgs,
    ctx: ToolCallContext
  ): Promise<string> {
    const tools = this.opts.tools
    const r = tools.workspace.resolvePath(args.path)
    const blocked = this.guard.blocked(ctx.turnId, r.uri)
    if (blocked) throw new Error(blocked)
    const isL4 = r.fsPath.toLowerCase().endsWith('.l4')
    if (isL4 && !this.guard.isTracked(ctx.turnId, r.uri)) {
      this.guard.noteErrorsBefore(ctx.turnId, tools.l4.fileErrorCounts?.())
      const baseline = await this.snapshot(r.uri)
      this.guard.track(
        ctx.turnId,
        r.uri,
        r.relative,
        baseline ?? { state: null, checks: [] }
      )
    }
    const result = await tools.editFileDetailed(
      args,
      this.toolContext(ctx),
      this.guard.sequenceFor(ctx.turnId, r.uri)
    )
    if (result.state) {
      this.guard.recordState(ctx.turnId, r.uri, result.state, result.applied)
    }
    return result.output
  }

  private toolContext(ctx: ToolCallContext): ToolSessionContext {
    return {
      conversationId: ctx.conversationId,
      mayQuoteFile: this.opts.permissions.getPermission('fs.read') === 'always',
    }
  }
}

/** Every path a tool call writes to or removes. */
function writtenPaths(name: string, args: unknown): string[] {
  const a = (args ?? {}) as {
    path?: unknown
    to?: unknown
    from?: unknown
    deleteSource?: unknown
  }
  const paths: unknown[] = []
  if (
    name === 'fs__create_file' ||
    name === 'fs__edit_file' ||
    name === 'fs__delete_file'
  ) {
    paths.push(a.path)
  } else if (name === 'fs__copy_file') {
    paths.push(a.to)
    if (a.deleteSource) paths.push(a.from)
  }
  return paths.filter((p): p is string => typeof p === 'string' && p !== '')
}

/** The file a tool call writes or names: `to` for a copy, else `path`. */
function targetPath(name: string, args: unknown): string | undefined {
  const a = (args ?? {}) as { path?: unknown; to?: unknown }
  const p = name === 'fs__copy_file' ? a.to : a.path
  return typeof p === 'string' && p ? p : undefined
}

/** The call's arguments, or null when they don't parse (the call then
 *  fails when it runs). */
function argsOrNull(json: string): unknown {
  try {
    return parseArgs(json)
  } catch {
    return null
  }
}

function parseArgs(json: string): unknown {
  if (!json || !json.trim()) return {}
  try {
    return JSON.parse(json)
  } catch (err) {
    throw new Error(
      `Invalid tool arguments JSON: ${err instanceof Error ? err.message : String(err)}`
    )
  }
}

export type { PermissionValue }
