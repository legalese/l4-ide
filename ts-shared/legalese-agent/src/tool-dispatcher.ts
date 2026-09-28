import type {
  AiProxyTool,
  Logger,
  PermissionPolicy,
  ToolCallContext,
  ToolProvider,
  UserInteraction,
} from './ports.js'
import {
  categoryForTool,
  type PermissionCategory,
  type PermissionValue,
} from './permissions.js'
import { BUILTIN_TOOLS } from './tool-registry.js'
import { metaAskUser } from './tools/ask-user.js'
import type { BuiltinTools } from './tools/builtin-tools.js'
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
   *  create / edit / delete all take `{ path }`. */
  resolveFile(call: ToolCall): string | null {
    try {
      const args = JSON.parse(call.argsJson || '{}') as { path?: string }
      if (!args.path) return null
      return this.opts.tools.resolveFileUri(args.path)
    } catch {
      return null
    }
  }

  /** The permission that currently applies to a tool, or null for an
   *  unknown tool. Lets the chat service render a tool row in its real
   *  initial state (pending-approval vs running). */
  permissionFor(name: string): PermissionValue | null {
    const category = categoryForTool(name)
    return category ? this.opts.permissions.getPermission(category) : null
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

  /** `(deployId, fnName)` for a deployed-rule tool, for display. */
  getToolTarget(name: string): { deployId: string; fnName: string } | null {
    for (const provider of this.providers) {
      if (!name.startsWith(provider.prefix)) continue
      const target = provider.getToolTarget?.(name)
      if (target) return target
    }
    return null
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
    const permission = this.opts.permissions.getPermission(category)
    this.opts.logger.info(
      `tool/dispatch ${call.name} (category=${category}, permission=${permission}) args=${call.argsJson}`
    )
    if (permission === 'never') {
      notifyStatus('error', { error: 'Denied by user settings' })
      return {
        ok: false,
        code: 'denied',
        error: `User has disallowed the "${category}" category. Update the setting in the Legalese AI settings to enable it.`,
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
    if (call.name !== 'fs__edit_file' && call.name !== 'fs__create_file') {
      return
    }
    const { path: p } = args as { path?: string }
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
        return tools.createFile(args as { path: string })
      case 'fs__edit_file':
        return tools.editFile(
          args as { path: string; old: string; new: string }
        )
      case 'fs__delete_file':
        return tools.deleteFile(args as { path: string })
      case 'l4__evaluate':
        return tools.evaluate(
          args as {
            path: string
            timeoutMs?: number
            mode?: 'changed' | 'full'
          }
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
