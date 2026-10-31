import * as fs from 'node:fs'
import * as os from 'node:os'
import * as path from 'node:path'
import { spawn, type ChildProcess } from 'node:child_process'
import * as vscode from 'vscode'
import type { AiLogger } from './logger.js'
import {
  userMcpToolName,
  type AiProxyTool,
  type ToolProvider,
} from '@repo/legalese-agent'
import type { McpOAuthManager } from './mcp-oauth.js'
import type { LocalMcpServer, McpServerSource } from '../cloud/mcp-transfer.js'
import { notificationText } from '../cloud/notification-text.js'

/**
 * MCP servers for the Legalese AI sidebar.
 *
 * The extension keeps its OWN server list (in globalState) and runs
 * every enabled server itself — http/sse over fetch, stdio via a
 * spawned child process, and OAuth-protected servers through our own
 * authorization client ({@link McpOAuthManager}). We never control or
 * depend on VS Code's MCP runtime.
 *
 * VS Code's `mcp.json` (user + workspace) is only an import catalog:
 * its servers are listed, toggled off, below our own. Turning one on
 * for the first time copies its config into our list — from then on
 * it's ours (connection, toggles, removal), and it disappears from the
 * catalog. Removing a server removes it from OUR list only; the
 * mcp.json entry is untouched.
 *
 * Lifecycle: enabled servers auto-connect once a usable Legalese AI
 * session exists (boot or login). Interactive actions (toggle-on,
 * Sign in, Reconnect, add, import) may kick off a browser sign-in for
 * OAuth servers; background auto-connects never do — they surface a
 * "sign-in required" state instead. One connect runs per server at a
 * time; a second one joins it.
 *
 * Problems are VS Code notifications, never text in the sidebar: a
 * connect the user asked for that fails, and a server that was signed
 * in and now needs a new sign-in. The settings UI shows states only,
 * pushed through {@link onDidChange}.
 *
 * The built-in "L4 Rules" proxy is excluded from the catalog — its
 * tools already reach the model via the `l4-rules__` path and it has
 * its own permission row.
 */

/** Wire-name prefix for MCP tools advertised to the ai-proxy,
 *  mirroring `l4-rules__` for the built-in server. Prefix-routing in
 *  the dispatcher and the permission gate key off it. */
export const VSCODE_MCP_PREFIX = 'vsmcp__'

/** Master switch: expose MCP servers to Legalese AI at all. */
const MCP_ENABLED_SETTING = 'legaleseAi.mcp.enabled'

/** Servers the user switched off (deny-list so new servers default to
 *  available; calls stay permission-gated). */
const DISABLED_SERVERS_SETTING = 'legaleseAi.mcp.disabledServers'

/** Individual tools the user switched off, as `serverId::toolName`. */
const DISABLED_TOOLS_SETTING = 'legaleseAi.mcp.disabledTools'

/** globalState key holding OUR server list. */
const OWN_SERVERS_MEMENTO_KEY = 'legaleseAi.mcp.ownServers'

/** mcp.json keys owned by our own local L4 proxy (see McpProxy). */
const BUILTIN_SERVER_KEYS = new Set(['L4 Rules', 'l4-rules', 'l4-tools'])

export type McpServerStatus =
  | 'connected'
  | 'connecting'
  | 'error'
  | 'stopped'
  /** OAuth server without stored tokens — needs an interactive
   *  sign-in (menu → Start). */
  | 'unauthorized'

export interface VsCodeMcpToolInfo {
  name: string
  description?: string
  enabled: boolean
}

export interface VsCodeMcpServerInfo {
  id: string
  name: string
  transport?: string
  /** URL or command line — whatever identifies the server to a human. */
  detail?: string
  enabled: boolean
  status: McpServerStatus
  tools: VsCodeMcpToolInfo[]
}

/** One mcp.json server offered for import (toggled off, not ours yet). */
export interface VsCodeMcpCandidateInfo {
  id: string
  name: string
  transport?: string
  detail?: string
}

export interface AddServerInput {
  name: string
  transport: 'http' | 'sse' | 'stdio'
  url?: string
  /** For stdio servers: full command line, split on whitespace. */
  command?: string
  /** Optional bearer token for http/sse servers — stored as an
   *  `Authorization: Bearer …` header on the entry. */
  bearerToken?: string
}

/** `connect`: (re)connect, with a browser sign-in when needed (the
 *  Sign in / retry badge and the menu's Reconnect). */
export type McpServerAction = 'connect' | 'remove'

/** Server config entry — same shape as VS Code's mcp.json entries so
 *  imports are verbatim copies. */
interface McpServerEntry {
  type?: string
  url?: string
  command?: string
  args?: string[]
  headers?: Record<string, string>
  [key: string]: unknown
}

interface McpToolDef {
  name: string
  description?: string
  inputSchema?: Record<string, unknown>
}

interface Connection {
  status: McpServerStatus
  error?: string
  tools: McpToolDef[]
  /** `Mcp-Session-Id` echoed back per the streamable-HTTP spec. */
  sessionId?: string
  /** OAuth access token in use (absent for static-header servers). */
  bearer?: string
  stdio?: StdioClient
}

/** JSON-RPC id counter, unique per process. */
let rpcIdCounter = 1

class HttpStatusError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly wwwAuthenticate?: string
  ) {
    super(message)
  }
}

export class VsCodeMcpTools implements ToolProvider, McpServerSource {
  readonly prefix = VSCODE_MCP_PREFIX

  private connections = new Map<string, Connection>()
  /** Connects in progress: a second start joins the first. */
  private readonly connecting = new Map<
    string,
    Promise<{ ok: boolean; error?: string }>
  >()
  /** Servers already told the user they need a new sign-in (once per
   *  window until they are signed in again). */
  private readonly signInNoticeShown = new Set<string>()
  /** wire name → (server, tool). Rebuilt on every listTools(). */
  private wireMap = new Map<string, { serverId: string; toolName: string }>()
  private readonly changed = new vscode.EventEmitter<void>()
  /** Fires whenever {@link listServers} / {@link listCandidates} may
   *  have changed. */
  readonly onDidChange = this.changed.event
  private readonly configSub: vscode.Disposable

  constructor(
    /** VS Code per-user data dir containing `mcp.json` — the import
     *  catalog. Undefined when it couldn't be derived. */
    private readonly userDataPath: string | undefined,
    private readonly logger: AiLogger,
    /** Gate for auto-connecting: true when the user has a usable
     *  Legalese AI session (Cloud login or API key). */
    private readonly isAiUsable: () => boolean,
    /** Extension globalState — holds our server list. */
    private readonly memento: vscode.Memento,
    /** OAuth client for protected servers. */
    private readonly oauth?: McpOAuthManager
  ) {
    this.configSub = vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration('legaleseAi.mcp')) this.changed.fire()
    })
  }

  dispose(): void {
    for (const id of [...this.connections.keys()]) this.stop(id)
    this.configSub.dispose()
    this.changed.dispose()
  }

  // ── Our server list ───────────────────────────────────────────────

  private ownServers(): Record<string, McpServerEntry> {
    return (
      this.memento.get<Record<string, McpServerEntry>>(
        OWN_SERVERS_MEMENTO_KEY
      ) ?? {}
    )
  }

  private async saveOwnServers(
    next: Record<string, McpServerEntry>
  ): Promise<void> {
    await this.memento.update(OWN_SERVERS_MEMENTO_KEY, next)
  }

  // ── Master switch ─────────────────────────────────────────────────

  allEnabled(): boolean {
    // Off at any level is off: a workspace can restrict this, never relax it.
    const info = vscode.workspace
      .getConfiguration()
      .inspect<boolean>(MCP_ENABLED_SETTING)
    return (
      info?.globalValue !== false &&
      info?.workspaceValue !== false &&
      info?.workspaceFolderValue !== false
    )
  }

  /** Flip the master switch: off drops every connection, on reconnects
   *  the enabled servers (when auth allows). */
  async setAllEnabled(enabled: boolean): Promise<void> {
    await vscode.workspace
      .getConfiguration()
      .update(MCP_ENABLED_SETTING, enabled, vscode.ConfigurationTarget.Global)
    if (enabled) {
      void this.autoStart()
    } else {
      for (const id of [...this.connections.keys()]) this.stop(id)
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────

  /**
   * Connect every enabled server that isn't already connected. Called
   * on activation and whenever auth state changes; never triggers an
   * interactive OAuth sign-in.
   */
  async autoStart(): Promise<void> {
    if (!this.isAiUsable()) return
    if (!this.allEnabled()) return
    const disabled = getDisabledServers()
    const jobs: Promise<unknown>[] = []
    for (const name of Object.keys(this.ownServers())) {
      if (disabled.has(name)) continue
      const current = this.connections.get(name)
      if (current?.status === 'connected' || current?.status === 'connecting')
        continue
      jobs.push(this.start(name, { interactive: false }))
    }
    await Promise.allSettled(jobs)
  }

  /**
   * Connect one of our servers. `interactive` allows a browser OAuth
   * sign-in when the server demands it; background starts report
   * `unauthorized` instead.
   */
  async start(
    id: string,
    opts: { interactive: boolean }
  ): Promise<{ ok: boolean; error?: string }> {
    const running = this.connecting.get(id)
    if (running) {
      const res = await running
      // A background connect that hit a sign-in wall: the user asked
      // for this one, so run it with the sign-in.
      return opts.interactive &&
        this.connections.get(id)?.status === 'unauthorized'
        ? this.start(id, opts)
        : res
    }
    const job = this.connect(id, opts).finally(() => {
      this.connecting.delete(id)
      this.changed.fire()
    })
    this.connecting.set(id, job)
    return job
  }

  private async connect(
    id: string,
    opts: { interactive: boolean }
  ): Promise<{ ok: boolean; error?: string }> {
    const entry = this.ownServers()[id]
    if (!entry) return { ok: false, error: `Unknown server: ${id}` }
    this.stopStdio(id)
    const conn: Connection = { status: 'connecting', tools: [] }
    this.connections.set(id, conn)
    this.changed.fire()
    try {
      if (isHttpEntry(entry)) {
        await this.connectHttp(id, entry, conn, opts.interactive)
      } else if (typeof entry.command === 'string') {
        await this.connectStdio(id, entry, conn)
      } else {
        throw new Error('Entry has neither a url nor a command.')
      }
      conn.status = 'connected'
      conn.error = undefined
      this.signInNoticeShown.delete(id)
      this.logger.info(
        `vscode-mcp: connected to "${id}" (${conn.tools.length} tools)`
      )
      return { ok: true }
    } catch (err) {
      conn.tools = []
      this.stopStdio(id)
      if (err instanceof vscode.CancellationError) {
        conn.status = 'unauthorized'
        return { ok: false, error: 'Sign-in cancelled.' }
      }
      if (err instanceof SignInRequired) {
        conn.status = 'unauthorized'
        conn.error = 'Sign-in required.'
        if (err.signedInBefore) void this.notifySignInAgain(id)
        return { ok: false, error: conn.error }
      }
      const msg = err instanceof Error ? err.message : String(err)
      conn.status = 'error'
      conn.error = msg
      this.logger.warn(`vscode-mcp: connect "${id}" failed: ${msg}`)
      if (opts.interactive) void this.notifyFailure(id, msg)
      return { ok: false, error: msg }
    }
  }

  /** A connect the user asked for failed. */
  private async notifyFailure(id: string, message: string): Promise<void> {
    const retry = 'Retry'
    const log = 'Show log'
    const pick = await vscode.window.showErrorMessage(
      `Couldn't connect to the MCP server "${notificationText(id, 60)}": ${notificationText(message, 200)}`,
      retry,
      log
    )
    if (pick === retry) void this.start(id, { interactive: true })
    else if (pick === log) this.logger.show()
  }

  /** A server that was signed in needs a new sign-in (its token was
   *  refused and couldn't be refreshed). Once per window. */
  private async notifySignInAgain(id: string): Promise<void> {
    if (this.signInNoticeShown.has(id)) return
    this.signInNoticeShown.add(id)
    const signIn = 'Sign in'
    const pick = await vscode.window.showWarningMessage(
      `The MCP server "${notificationText(id, 60)}" needs you to sign in again.`,
      signIn
    )
    if (pick === signIn) void this.start(id, { interactive: true })
  }

  /** The browser sign-in, behind a cancellable progress notification. */
  private signInWithProgress(
    id: string,
    url: string,
    challenge: string | undefined
  ): Thenable<string> {
    return vscode.window.withProgress(
      {
        location: vscode.ProgressLocation.Notification,
        title: `Signing in to "${notificationText(id, 60)}" in your browser…`,
        cancellable: true,
      },
      (_progress, cancel) => this.oauth!.authorize(url, challenge, cancel)
    )
  }

  stop(id: string): void {
    this.stopStdio(id)
    this.connections.set(id, { status: 'stopped', tools: [] })
    this.changed.fire()
  }

  private stopStdio(id: string): void {
    this.connections.get(id)?.stdio?.kill()
  }

  /** An action from the settings UI. Its outcome shows as the server's
   *  state and, on failure, a notification. */
  async runAction(id: string, action: McpServerAction): Promise<void> {
    switch (action) {
      case 'connect':
        await this.start(id, { interactive: true })
        return
      case 'remove':
        await this.removeServer(id)
        return
    }
  }

  // ── HTTP transport (with OAuth) ───────────────────────────────────

  private async connectHttp(
    id: string,
    entry: McpServerEntry,
    conn: Connection,
    interactive: boolean
  ): Promise<void> {
    const url = entry.url as string
    const hasStaticAuth = Boolean(entry.headers?.['Authorization'])
    const signedIn =
      !hasStaticAuth && this.oauth ? await this.oauth.hasAuth(url) : false
    if (!hasStaticAuth && this.oauth) {
      conn.bearer = (await this.oauth.getAccessToken(url)) ?? undefined
    }
    try {
      await this.httpHandshake(url, entry, conn)
      return
    } catch (err) {
      const unauthorized =
        err instanceof HttpStatusError &&
        (err.status === 401 || err.status === 403)
      if (!unauthorized || hasStaticAuth || !this.oauth) throw err
      if (!interactive) throw new SignInRequired(signedIn)
      // Interactive path: run the full browser authorization, then
      // retry the handshake once with the fresh token.
      conn.bearer = await this.signInWithProgress(id, url, err.wwwAuthenticate)
      conn.sessionId = undefined
      await this.httpHandshake(url, entry, conn)
    }
  }

  private async httpHandshake(
    url: string,
    entry: McpServerEntry,
    conn: Connection
  ): Promise<void> {
    await this.rpc(url, entry, conn, 'initialize', {
      protocolVersion: '2025-03-26',
      capabilities: { tools: {} },
      clientInfo: { name: 'legalese-ai-chat', version: '1.6.0' },
    })
    void this.rpc(url, entry, conn, 'notifications/initialized', {}).catch(
      () => undefined
    )
    const listed = await this.rpc<{ tools?: McpToolDef[] }>(
      url,
      entry,
      conn,
      'tools/list',
      {}
    )
    conn.tools = listed?.tools ?? []
  }

  private async rpc<T>(
    url: string,
    entry: McpServerEntry,
    conn: Connection,
    method: string,
    params: Record<string, unknown>
  ): Promise<T | null> {
    const id = rpcIdCounter++
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json, text/event-stream',
        ...(conn.sessionId ? { 'Mcp-Session-Id': conn.sessionId } : {}),
        ...(conn.bearer ? { Authorization: `Bearer ${conn.bearer}` } : {}),
        ...(entry.headers ?? {}),
      },
      body: JSON.stringify({ jsonrpc: '2.0', id, method, params }),
      signal: AbortSignal.timeout(20_000),
    })
    const sessionId = res.headers.get('Mcp-Session-Id')
    if (sessionId) conn.sessionId = sessionId
    if (!res.ok) {
      const preview = await res.text().catch(() => '')
      throw new HttpStatusError(
        `${method} returned HTTP ${res.status}${preview ? `: ${preview.slice(0, 200)}` : ''}`,
        res.status,
        res.headers.get('WWW-Authenticate') ?? undefined
      )
    }
    const contentType = res.headers.get('Content-Type') ?? ''
    const text = await res.text()
    if (!text) return null
    const raw = contentType.includes('text/event-stream')
      ? extractSseJson(text, id)
      : text
    if (!raw) return null
    const payload = JSON.parse(raw) as {
      result?: T
      error?: { code?: number; message?: string }
    }
    if (payload.error) {
      throw new Error(payload.error.message ?? `${method} failed`)
    }
    return payload.result ?? null
  }

  // ── stdio transport ───────────────────────────────────────────────

  private async connectStdio(
    id: string,
    entry: McpServerEntry,
    conn: Connection
  ): Promise<void> {
    const client = new StdioClient(
      entry.command as string,
      Array.isArray(entry.args) ? entry.args.map(String) : [],
      this.logger,
      (reason) => {
        // Unexpected exit while we considered it connected.
        const current = this.connections.get(id)
        if (current === conn && conn.status === 'connected') {
          conn.status = 'error'
          conn.error = reason
          conn.tools = []
          this.changed.fire()
        }
      }
    )
    conn.stdio = client
    client.start()
    await client.request('initialize', {
      protocolVersion: '2025-03-26',
      capabilities: { tools: {} },
      clientInfo: { name: 'legalese-ai-chat', version: '1.6.0' },
    })
    client.notify('notifications/initialized', {})
    const listed = await client.request<{ tools?: McpToolDef[] }>(
      'tools/list',
      {}
    )
    conn.tools = listed?.tools ?? []
  }

  // ── Enablement ────────────────────────────────────────────────────

  /** Toggle a server. Enabling connects it right away (interactive —
   *  the user just asked for it); disabling drops the connection. */
  async setEnabled(id: string, enabled: boolean): Promise<void> {
    const disabled = getDisabledServers()
    if (enabled) disabled.delete(id)
    else disabled.add(id)
    await vscode.workspace
      .getConfiguration()
      .update(
        DISABLED_SERVERS_SETTING,
        [...disabled].sort(),
        vscode.ConfigurationTarget.Global
      )
    if (enabled) {
      if (this.isAiUsable()) void this.start(id, { interactive: true })
    } else {
      this.stop(id)
    }
  }

  async setToolEnabled(
    serverId: string,
    toolName: string,
    enabled: boolean
  ): Promise<void> {
    const key = toolKey(serverId, toolName)
    const disabled = getDisabledTools()
    if (enabled) disabled.delete(key)
    else disabled.add(key)
    await vscode.workspace
      .getConfiguration()
      .update(
        DISABLED_TOOLS_SETTING,
        [...disabled].sort(),
        vscode.ConfigurationTarget.Global
      )
  }

  // ── Listing for the settings UI ───────────────────────────────────

  listServers(): VsCodeMcpServerInfo[] {
    const disabledServers = getDisabledServers()
    const disabledTools = getDisabledTools()
    const out: VsCodeMcpServerInfo[] = []
    for (const [name, entry] of Object.entries(this.ownServers())) {
      const conn = this.connections.get(name)
      out.push({
        id: name,
        name,
        transport: entry.type ?? (entry.command ? 'stdio' : 'http'),
        detail: describeEntry(entry),
        enabled: !disabledServers.has(name),
        status: conn?.status ?? 'stopped',
        tools: (conn?.tools ?? []).map((t) => ({
          name: t.name,
          description: t.description,
          enabled: !disabledTools.has(toolKey(name, t.name)),
        })),
      })
    }
    return out
  }

  /**
   * mcp.json servers not (yet) in our list — the import catalog shown
   * below our own servers. A candidate disappears once a same-named or
   * same-target server exists in our list.
   */
  listCandidates(): VsCodeMcpCandidateInfo[] {
    const own = this.ownServers()
    const ownTargets = new Set(
      Object.values(own)
        .map((e) => e.url ?? e.command)
        .filter(Boolean)
    )
    const out: VsCodeMcpCandidateInfo[] = []
    for (const [key, entry] of Object.entries(this.readVsCodeMcpJson())) {
      if (BUILTIN_SERVER_KEYS.has(key)) continue
      if (own[key]) continue
      const target = entry.url ?? entry.command
      if (target && ownTargets.has(target)) continue
      out.push({
        id: key,
        name: key,
        transport: entry.type ?? (entry.command ? 'stdio' : 'http'),
        detail: describeEntry(entry),
      })
    }
    return out
  }

  /** Pick servers from VS Code's mcp.json and import them, one after
   *  the other (so at most one browser sign-in opens at a time). */
  async importFromVsCode(): Promise<void> {
    const candidates = this.listCandidates()
    if (candidates.length === 0) {
      void vscode.window.showInformationMessage(
        "VS Code's mcp.json has no MCP servers that Legalese AI doesn't use already."
      )
      return
    }
    const picked = await vscode.window.showQuickPick(
      candidates.map((c) => ({
        label: c.name,
        description: c.transport,
        detail: c.detail,
        id: c.id,
      })),
      {
        canPickMany: true,
        title: 'Import MCP servers from VS Code',
        placeHolder:
          "Legalese AI keeps its own copy; VS Code's mcp.json stays as it is",
      }
    )
    for (const p of picked ?? []) await this.importCandidate(p.id)
  }

  /** Copy an mcp.json server into our list and start it. The original
   *  entry is left untouched — from here on we run our own copy. */
  async importCandidate(id: string): Promise<{ ok: boolean; error?: string }> {
    const entry = this.readVsCodeMcpJson()[id]
    if (!entry) return { ok: false, error: `Unknown server: ${id}` }
    if (BUILTIN_SERVER_KEYS.has(id)) {
      return { ok: false, error: 'The built-in L4 server is always wired.' }
    }
    const own = this.ownServers()
    if (!own[id]) {
      await this.saveOwnServers({ ...own, [id]: entry })
      this.logger.info(`vscode-mcp: imported "${id}" from VS Code mcp.json`)
      this.changed.fire()
    }
    // The import gesture is an explicit enable.
    const disabled = getDisabledServers()
    if (disabled.has(id)) {
      disabled.delete(id)
      await vscode.workspace
        .getConfiguration()
        .update(
          DISABLED_SERVERS_SETTING,
          [...disabled].sort(),
          vscode.ConfigurationTarget.Global
        )
    }
    if (!this.isAiUsable()) return { ok: true }
    return this.start(id, { interactive: true })
  }

  // ── Cloud sessions (spec §6.4) ────────────────────────────────────

  /** Enabled servers, for passing to a cloud session. Tools the user
   *  switched off are left out of `enabledTools` (known only for
   *  servers that connected in this window; otherwise all tools). */
  enabledServers(): LocalMcpServer[] {
    if (!this.allEnabled()) return []
    const disabledServers = getDisabledServers()
    const disabledTools = getDisabledTools()
    const out: LocalMcpServer[] = []
    for (const [id, entry] of Object.entries(this.ownServers())) {
      if (disabledServers.has(id)) continue
      const transport: LocalMcpServer['transport'] = isHttpEntry(entry)
        ? entry.type === 'sse'
          ? 'sse'
          : 'http'
        : 'stdio'
      const tools = this.connections.get(id)?.tools ?? []
      const off = tools.filter((t) => disabledTools.has(toolKey(id, t.name)))
      out.push({
        id,
        url: typeof entry.url === 'string' ? entry.url : '',
        transport,
        ...(off.length > 0
          ? {
              enabledTools: tools
                .filter((t) => !disabledTools.has(toolKey(id, t.name)))
                .map((t) => t.name),
            }
          : {}),
      })
    }
    return out
  }

  /**
   * Headers a cloud session needs for one server, from what is stored
   * (not from this window's connection, which may not have run): the
   * entry's static headers, or its static headers plus a fresh OAuth
   * access token when there is a stored sign-in. `null` when a stored
   * sign-in no longer works (a new sign-in is needed). With nothing
   * stored, just the static headers: whether the server wants a
   * sign-in shows when the session reports it. `refresh` refreshes the
   * token even before it expires (the session turned it down).
   */
  async headersFor(
    id: string,
    opts: { refresh?: boolean } = {}
  ): Promise<Record<string, string> | null> {
    const entry = this.ownServers()[id]
    if (!entry || !isHttpEntry(entry)) return {}
    const headers = { ...(entry.headers ?? {}) }
    if (headers['Authorization'] || !this.oauth) return headers
    const url = entry.url as string
    if (!(await this.oauth.hasAuth(url))) return headers
    const token = opts.refresh
      ? await this.oauth.refreshNow(url)
      : await this.oauth.getAccessToken(url)
    if (!token) return null
    return { ...headers, Authorization: `Bearer ${token}` }
  }

  /** A cloud session's sign-in for one server: the same interactive
   *  start as the settings menu's Start. */
  signIn(id: string): Promise<{ ok: boolean; error?: string }> {
    return this.start(id, { interactive: true })
  }

  // ── Tool funnel for the chat loop ─────────────────────────────────

  /** Advertise the enabled servers' enabled tools in OpenAI
   *  function-tool shape. */
  listTools(): AiProxyTool[] {
    this.wireMap.clear()
    if (!this.allEnabled()) return []
    const disabledServers = getDisabledServers()
    const disabledTools = getDisabledTools()
    const out: AiProxyTool[] = []
    for (const [serverId, conn] of this.connections) {
      if (conn.status !== 'connected') continue
      if (disabledServers.has(serverId)) continue
      for (const t of conn.tools) {
        if (disabledTools.has(toolKey(serverId, t.name))) continue
        const wireName = directWireName(serverId, t.name)
        if (this.wireMap.has(wireName)) continue
        this.wireMap.set(wireName, { serverId, toolName: t.name })
        out.push({
          type: 'function',
          function: {
            name: wireName,
            description: t.description || `MCP tool ${t.name} (${serverId})`,
            parameters: shapeParameters(t.inputSchema),
          },
        })
      }
    }
    return out
  }

  /** Execute a `vsmcp__…` call against the owning connection. */
  async callTool(wireName: string, argsJson: string): Promise<string> {
    if (!wireName.startsWith(VSCODE_MCP_PREFIX)) {
      throw new Error(
        `vscode-mcp: tool name must start with ${VSCODE_MCP_PREFIX}: ${wireName}`
      )
    }
    let target = this.wireMap.get(wireName)
    if (!target) {
      // Map lost (e.g. extension host reload mid-conversation) —
      // rebuild from live state before giving up.
      this.listTools()
      target = this.wireMap.get(wireName)
    }
    if (!target) {
      throw new Error(
        `MCP tool ${wireName} is not available — its server may be stopped or disabled.`
      )
    }
    let parsed: unknown
    try {
      parsed = argsJson?.trim() ? JSON.parse(argsJson) : {}
    } catch (err) {
      throw new Error(
        `vscode-mcp: invalid JSON arguments for ${wireName}: ${err instanceof Error ? err.message : String(err)}`
      )
    }
    const args: Record<string, unknown> =
      parsed && typeof parsed === 'object'
        ? (parsed as Record<string, unknown>)
        : { value: parsed }

    const { serverId, toolName } = target
    const entry = this.ownServers()[serverId]
    const conn = this.connections.get(serverId)
    if (!entry || conn?.status !== 'connected') {
      throw new Error(
        `MCP server ${serverId} is not connected — toggle it on in the Legalese AI settings.`
      )
    }

    let res: {
      content?: Array<{ type: string; text?: string }>
      isError?: boolean
    } | null
    if (conn.stdio) {
      res = await conn.stdio.request('tools/call', {
        name: toolName,
        arguments: args,
      })
    } else {
      const url = entry.url as string
      try {
        res = await this.rpc(url, entry, conn, 'tools/call', {
          name: toolName,
          arguments: args,
        })
      } catch (err) {
        // Token may have expired mid-session: refresh silently once.
        if (
          err instanceof HttpStatusError &&
          err.status === 401 &&
          conn.bearer &&
          this.oauth
        ) {
          const fresh = await this.oauth.refreshNow(url)
          if (!fresh) {
            conn.status = 'unauthorized'
            conn.tools = []
            this.changed.fire()
            void this.notifySignInAgain(serverId)
            throw new Error(
              `Sign-in to ${serverId} expired; the user has been asked to sign in again.`
            )
          }
          conn.bearer = fresh
          res = await this.rpc(url, entry, conn, 'tools/call', {
            name: toolName,
            arguments: args,
          })
        } else {
          throw err
        }
      }
    }
    const text = (res?.content ?? [])
      .map((c) => (c.type === 'text' && c.text ? c.text : JSON.stringify(c)))
      .join('\n')
    if (res?.isError) {
      throw new Error(text || `${wireName} failed`)
    }
    return text || JSON.stringify(res ?? {})
  }

  // ── Add / remove ──────────────────────────────────────────────────

  /**
   * Add a server to OUR list and connect it in the background (its
   * outcome shows as its state, and a failure as a notification). A
   * name that exists already asks, in a dialog, whether to replace it.
   * Invalid input answers `ok: false` with an `error` for a
   * notification (the settings form doesn't submit invalid input).
   */
  async addServer(
    input: AddServerInput
  ): Promise<{ ok: boolean; error?: string; cancelled?: boolean }> {
    const name = input.name.trim()
    if (!name) return { ok: false, error: 'Server name is required.' }
    if (BUILTIN_SERVER_KEYS.has(name)) {
      return {
        ok: false,
        error: `"${name}" is reserved for the built-in L4 server.`,
      }
    }
    let entry: McpServerEntry
    if (input.transport === 'stdio') {
      const parts = (input.command ?? '').trim().split(/\s+/).filter(Boolean)
      if (parts.length === 0) {
        return { ok: false, error: 'A command is required for a stdio server.' }
      }
      entry = { type: 'stdio', command: parts[0], args: parts.slice(1) }
    } else {
      const url = (input.url ?? '').trim()
      if (!/^https?:\/\//.test(url)) {
        return { ok: false, error: 'A valid http(s) URL is required.' }
      }
      entry = { type: input.transport, url }
      const token = (input.bearerToken ?? '').trim()
      if (token) {
        entry.headers = { Authorization: `Bearer ${token}` }
      }
    }

    const own = this.ownServers()
    if (own[name]) {
      const replace = 'Replace'
      const pick = await vscode.window.showWarningMessage(
        `An MCP server named "${notificationText(name, 60)}" exists already. Replace it?`,
        { modal: true },
        replace
      )
      if (pick !== replace) return { ok: false, cancelled: true }
    }
    const replacing = Boolean(own[name])
    if (replacing) this.stop(name)
    await this.saveOwnServers({ ...own, [name]: entry })
    this.logger.info(
      `vscode-mcp: ${replacing ? 'replaced' : 'added'} server "${name}"`
    )
    this.changed.fire()
    if (this.isAiUsable()) void this.start(name, { interactive: true })
    return { ok: true }
  }

  /** Remove a server from OUR list (mcp.json is never touched), after
   *  asking, and forget its toggles and any OAuth tokens we hold. */
  private async removeServer(id: string): Promise<void> {
    const own = this.ownServers()
    const entry = own[id]
    if (!entry) return
    const remove = 'Remove'
    const pick = await vscode.window.showWarningMessage(
      `Remove the MCP server "${notificationText(id, 60)}"?`,
      {
        modal: true,
        detail: 'Legalese AI forgets it and its sign-in.',
      },
      remove
    )
    if (pick !== remove) return
    this.stopStdio(id)
    this.connections.delete(id)
    this.connecting.delete(id)
    const next = { ...own }
    delete next[id]
    await this.saveOwnServers(next)
    await removeFromSetting(DISABLED_SERVERS_SETTING, (s) => s === id)
    await removeFromSetting(DISABLED_TOOLS_SETTING, (s) =>
      s.startsWith(`${id}::`)
    )
    if (isHttpEntry(entry) && this.oauth) {
      await this.oauth.clearAuth(entry.url as string)
    }
    this.logger.info(`vscode-mcp: removed server "${id}"`)
    this.changed.fire()
  }

  // ── VS Code mcp.json (import catalog only) ────────────────────────

  private readVsCodeMcpJson(): Record<string, McpServerEntry> {
    const out: Record<string, McpServerEntry> = {}
    const addFrom = (filePath: string): void => {
      for (const [key, entry] of Object.entries(
        readMcpJsonServers(filePath, this.logger)
      )) {
        if (!(key in out)) out[key] = entry
      }
    }
    if (this.userDataPath) {
      addFrom(path.join(this.userDataPath, 'mcp.json'))
    }
    for (const folder of vscode.workspace.workspaceFolders ?? []) {
      addFrom(path.join(folder.uri.fsPath, '.vscode', 'mcp.json'))
    }
    return out
  }
}

/** Thrown internally when a background connect hits an OAuth wall.
 *  `signedInBefore`: there was a stored sign-in, now refused. */
class SignInRequired extends Error {
  constructor(readonly signedInBefore = false) {
    super('Sign-in required')
  }
}

// ── stdio client ──────────────────────────────────────────────────────

/**
 * Minimal MCP stdio transport: newline-delimited JSON-RPC over a
 * spawned child process's stdin/stdout. stderr is logged.
 */
class StdioClient {
  private proc: ChildProcess | null = null
  private buffer = ''
  private pending = new Map<
    number,
    {
      resolve: (v: unknown) => void
      reject: (e: Error) => void
      timer: NodeJS.Timeout
    }
  >()

  constructor(
    private readonly command: string,
    private readonly args: string[],
    private readonly logger: AiLogger,
    private readonly onUnexpectedExit: (reason: string) => void
  ) {}

  start(): void {
    const cwd =
      vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? os.homedir()
    this.proc = spawn(this.command, this.args, {
      cwd,
      env: process.env,
      stdio: ['pipe', 'pipe', 'pipe'],
      // Through a shell so PATH-resolved commands (`npx`, `uvx`, …)
      // behave the way they do in the user's terminal, incl. Windows.
      shell: true,
    })
    this.proc.stdout?.setEncoding('utf-8')
    this.proc.stdout?.on('data', (chunk: string) => this.onData(chunk))
    this.proc.stderr?.setEncoding('utf-8')
    this.proc.stderr?.on('data', (chunk: string) => {
      const line = chunk.trim()
      if (line) this.logger.info(`mcp-stdio[${this.command}]: ${line}`)
    })
    this.proc.on('exit', (code) => {
      const reason = `Server process exited (code ${code ?? 'unknown'}).`
      for (const [, p] of this.pending) {
        clearTimeout(p.timer)
        p.reject(new Error(reason))
      }
      this.pending.clear()
      this.onUnexpectedExit(reason)
    })
    this.proc.on('error', (err) => {
      const reason = `Failed to launch "${this.command}": ${err.message}`
      for (const [, p] of this.pending) {
        clearTimeout(p.timer)
        p.reject(new Error(reason))
      }
      this.pending.clear()
      this.onUnexpectedExit(reason)
    })
  }

  async request<T>(
    method: string,
    params: Record<string, unknown>,
    timeoutMs = 30_000
  ): Promise<T | null> {
    if (!this.proc?.stdin?.writable) {
      throw new Error('Server process is not running.')
    }
    const id = rpcIdCounter++
    const payload =
      JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n'
    return new Promise<T | null>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id)
        reject(new Error(`${method} timed out after ${timeoutMs / 1000}s`))
      }, timeoutMs)
      this.pending.set(id, {
        resolve: resolve as (v: unknown) => void,
        reject,
        timer,
      })
      this.proc!.stdin!.write(payload)
    })
  }

  notify(method: string, params: Record<string, unknown>): void {
    if (!this.proc?.stdin?.writable) return
    this.proc.stdin.write(
      JSON.stringify({ jsonrpc: '2.0', method, params }) + '\n'
    )
  }

  kill(): void {
    if (!this.proc) return
    try {
      this.proc.removeAllListeners('exit')
      this.proc.kill()
    } catch {
      // already gone
    }
    this.proc = null
    for (const [, p] of this.pending) {
      clearTimeout(p.timer)
      p.reject(new Error('Server stopped.'))
    }
    this.pending.clear()
  }

  private onData(chunk: string): void {
    this.buffer += chunk
    let idx: number
    while ((idx = this.buffer.indexOf('\n')) >= 0) {
      const line = this.buffer.slice(0, idx).trim()
      this.buffer = this.buffer.slice(idx + 1)
      if (!line) continue
      try {
        const msg = JSON.parse(line) as {
          id?: number
          result?: unknown
          error?: { message?: string }
        }
        if (typeof msg.id !== 'number') continue // server notification
        const p = this.pending.get(msg.id)
        if (!p) continue
        this.pending.delete(msg.id)
        clearTimeout(p.timer)
        if (msg.error) {
          p.reject(new Error(msg.error.message ?? 'MCP request failed'))
        } else {
          p.resolve(msg.result ?? null)
        }
      } catch {
        // Non-JSON noise on stdout (some servers print banners) — skip.
      }
    }
  }
}

// ── helpers ───────────────────────────────────────────────────────────

function isHttpEntry(entry: McpServerEntry): boolean {
  return (
    typeof entry.url === 'string' &&
    (entry.type === 'http' || entry.type === 'sse' || entry.type === undefined)
  )
}

function toolKey(serverId: string, toolName: string): string {
  return `${serverId}::${toolName}`
}

function getDisabledServers(): Set<string> {
  return readStringSetSetting(DISABLED_SERVERS_SETTING)
}

function getDisabledTools(): Set<string> {
  return readStringSetSetting(DISABLED_TOOLS_SETTING)
}

/** Drop the entries `drop` matches from a string-list setting. */
async function removeFromSetting(
  setting: string,
  drop: (s: string) => boolean
): Promise<void> {
  const current = [...userStringSetting(setting)]
  const next = current.filter((s) => !drop(s))
  if (next.length === current.length) return
  await vscode.workspace
    .getConfiguration()
    .update(setting, next.sort(), vscode.ConfigurationTarget.Global)
}

/** A deny-list as the user set it: the part this extension can change. */
function userStringSetting(setting: string): Set<string> {
  const raw = vscode.workspace.getConfiguration().inspect<string[]>(setting)
  return strings(raw?.globalValue)
}

/** A deny-list in force: every level's entries together, so a workspace
 *  can add to it but not take anything off the user's. */
function readStringSetSetting(setting: string): Set<string> {
  const raw = vscode.workspace.getConfiguration().inspect<string[]>(setting)
  return new Set([
    ...strings(raw?.globalValue),
    ...strings(raw?.workspaceValue),
    ...strings(raw?.workspaceFolderValue),
  ])
}

function strings(value: unknown): Set<string> {
  return new Set(
    Array.isArray(value)
      ? value.filter((s): s is string => typeof s === 'string')
      : []
  )
}

function readMcpJsonServers(
  filePath: string,
  logger: AiLogger
): Record<string, McpServerEntry> {
  let raw: string
  try {
    raw = fs.readFileSync(filePath, 'utf-8')
  } catch {
    return {}
  }
  if (!raw.trim()) return {}
  try {
    const parsed = JSON.parse(raw) as {
      servers?: Record<string, McpServerEntry>
    }
    if (parsed && typeof parsed === 'object' && parsed.servers) {
      return parsed.servers
    }
  } catch (err) {
    // JSONC with comments — readable by VS Code, not by us. Skip
    // rather than mis-report.
    logger.warn(
      `vscode-mcp: could not parse ${filePath}: ${err instanceof Error ? err.message : String(err)}`
    )
  }
  return {}
}

function describeEntry(entry: McpServerEntry): string | undefined {
  if (typeof entry.url === 'string') return entry.url
  if (typeof entry.command === 'string') {
    return [
      entry.command,
      ...(Array.isArray(entry.args) ? entry.args : []),
    ].join(' ')
  }
  return undefined
}

/** Last `data:` payload of an SSE body that parses as the JSON-RPC
 *  response for `id` (falls back to the last data line). */
function extractSseJson(body: string, id: number): string | null {
  let last: string | null = null
  for (const line of body.split('\n')) {
    if (!line.startsWith('data:')) continue
    const data = line.slice('data:'.length).trim()
    if (!data) continue
    last = data
    try {
      const parsed = JSON.parse(data) as { id?: unknown }
      if (parsed && parsed.id === id) return data
    } catch {
      // keep scanning
    }
  }
  return last
}

/** Wire name for a server's tool. Uniqueness comes from the wireMap
 *  dedupe; the name only needs to be stable. */
function directWireName(serverId: string, toolName: string): string {
  return userMcpToolName(VSCODE_MCP_PREFIX, serverId, toolName)
}

/** OpenAI function tools require `parameters.type === 'object'`; some
 *  MCP tools ship no schema (or a non-object one). */
function shapeParameters(
  schema: Record<string, unknown> | undefined
): Record<string, unknown> {
  if (!schema || typeof schema !== 'object') {
    return { type: 'object', properties: {} }
  }
  return {
    type: 'object',
    properties:
      (schema as { properties?: Record<string, unknown> }).properties ?? {},
    ...(Array.isArray((schema as { required?: string[] }).required)
      ? { required: (schema as { required: string[] }).required }
      : {}),
    additionalProperties:
      (schema as { additionalProperties?: boolean }).additionalProperties ??
      false,
  }
}
