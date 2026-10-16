import type { AiProxyTool, Logger, ToolProvider } from '@repo/legalese-agent'
import {
  generateSealingKeyPair,
  mcpCredentials,
  mcpCredentialsContext,
  openSealed,
  parseJsonText,
  type CloudCommand,
  type McpServerConfig,
  type SealingKeyPair,
} from '@repo/legalese-agent/protocol'
import type { RunnerContext, RunnerPlugin } from './runner.js'
import { SessionJson } from './session-file.js'

/** Same prefix as the extension's MCP tools, so the permission category
 *  (`mcp.vscode`) and the webview's rendering match. */
export const USER_MCP_PREFIX = 'vsmcp__'
const RPC_TIMEOUT_MS = 60_000
const PROTOCOL_VERSION = '2025-03-26'

class McpHttpError extends Error {
  constructor(
    message: string,
    readonly status: number
  ) {
    super(message)
    this.name = 'McpHttpError'
  }
}

interface McpToolDef {
  name: string
  description?: string
  inputSchema?: Record<string, unknown>
}

interface Server {
  config: McpServerConfig
  headers: Record<string, string>
  expiresAt?: number
  /** Bumped on every new credential, so stale failures don't re-report. */
  generation: number
  sessionId?: string
  initialized: boolean
  tools: McpToolDef[]
  /** `auth-required` already sent for this generation. */
  reported: boolean
  connecting: Promise<void> | null
  expiryTimer?: NodeJS.Timeout
}

let rpcId = 1

function sanitize(s: string): string {
  return s.replace(/[^a-zA-Z0-9_-]/g, '_')
}

/** `vsmcp__<server>_<tool>`, ≤ 64 characters, like the extension. */
export function wireName(server: string, tool: string): string {
  return `${USER_MCP_PREFIX}${sanitize(server).slice(0, 16)}_${sanitize(tool).slice(0, 40)}`.slice(
    0,
    64
  )
}

/**
 * The user's HTTP MCP servers in a cloud session (spec §6.4).
 *
 * - At start, an ephemeral X25519 key pair; the public key rides on
 *   every `session-state` event while running. The private key lives
 *   only in this process.
 * - `mcp-credentials { sealed }` is opened with
 *   `mcpCredentialsContext(sid)`, validated, and merged by server name:
 *   each server named in it gets its headers replaced (the extension
 *   re-sends on every new public key and every `auth-required`), so
 *   repeating a command is harmless. Plaintext never touches disk or
 *   logs.
 * - Servers come from `session.json` (names and https URLs only; stdio
 *   servers never get there) and connect once their credentials arrive,
 *   over streamable HTTP (JSON or SSE responses, `Mcp-Session-Id`).
 *   `transport: 'sse'` servers are spoken to the same way, as the
 *   extension does.
 * - A 401/403, or credentials past their `expiresAt`, emits
 *   `auth-required { reason: 'mcp', server }` once per credential and
 *   fails the call with a message the model can relay.
 * - Tools are advertised as `vsmcp__<server>_<tool>` (the `mcp.vscode`
 *   permission category), filtered by `enabledTools`.
 */
export class McpServers implements RunnerPlugin, ToolProvider {
  readonly name = 'mcp'
  readonly commands = ['mcp-credentials'] as const
  readonly prefix = USER_MCP_PREFIX
  private keyPair: SealingKeyPair | null = null
  private readonly servers = new Map<string, Server>()
  /** wire name → [server, tool] */
  private readonly wire = new Map<string, [string, string]>()
  private ctx!: RunnerContext
  private readonly now: () => number
  private readonly fetchImpl: typeof fetch

  constructor(opts: { now?: () => number; fetch?: typeof fetch } = {}) {
    this.now = opts.now ?? Date.now
    this.fetchImpl = opts.fetch ?? ((...a) => fetch(...a))
  }

  private get logger(): Logger {
    return this.ctx.logger
  }

  // ── RunnerPlugin ───────────────────────────────────────────────────

  async start(ctx: RunnerContext): Promise<void> {
    this.ctx = ctx
    this.keyPair = generateSealingKeyPair()
    const session = await new SessionJson(ctx.sessionDir).read()
    for (const config of session.mcpServers) {
      this.servers.set(config.name, {
        config,
        headers: {},
        generation: 0,
        initialized: false,
        tools: [],
        reported: false,
        connecting: null,
      })
    }
    if (this.servers.size > 0) ctx.providers.push(this)
    this.logger.info(`mcp: ${this.servers.size} server(s) configured`)
  }

  sessionStateFields(): { publicKey?: string } {
    return this.keyPair ? { publicKey: this.keyPair.publicKey } : {}
  }

  async handleCommand(cmd: CloudCommand): Promise<void> {
    if (cmd.type !== 'mcp-credentials' || !this.keyPair) return
    let creds
    try {
      const plain = openSealed(
        this.keyPair,
        cmd.sealed,
        mcpCredentialsContext(this.ctx.sessionId)
      )
      creds = mcpCredentials(
        parseJsonText(plain.toString('utf8')),
        'credentials'
      )
    } catch {
      // Sealed to an earlier harness's key, tampered with, or malformed.
      this.logger.warn(
        `mcp: command ${cmd.id}: credentials could not be opened`
      )
      return
    }
    let updated = 0
    for (const entry of creds.servers) {
      const server = this.servers.get(entry.name)
      if (!server) continue
      server.headers = { ...entry.headers }
      server.expiresAt = entry.expiresAt
      server.generation++
      server.reported = false
      // New credentials: start a fresh MCP session.
      server.sessionId = undefined
      server.initialized = false
      updated++
      this.watchExpiry(server)
      void this.connect(server)
    }
    this.logger.info(`mcp: credentials for ${updated} server(s)`)
  }

  // ── ToolProvider ───────────────────────────────────────────────────

  async listTools(): Promise<AiProxyTool[]> {
    const out: AiProxyTool[] = []
    this.wire.clear()
    for (const server of this.servers.values()) {
      if (server.connecting) await server.connecting.catch(() => undefined)
      if (!server.initialized) continue
      const enabled = server.config.enabledTools
      for (const t of server.tools) {
        if (enabled && !enabled.includes(t.name)) continue
        let name = wireName(server.config.name, t.name)
        for (let i = 2; this.wire.has(name); i++) {
          name = `${wireName(server.config.name, t.name).slice(0, 60)}_${i}`
        }
        this.wire.set(name, [server.config.name, t.name])
        out.push({
          type: 'function',
          function: {
            name,
            description: `[${server.config.name}] ` + (t.description ?? t.name),
            parameters: shapeParameters(t.inputSchema),
          },
        })
      }
    }
    return out
  }

  async callTool(name: string, argsJson: string): Promise<string> {
    const target = this.wire.get(name)
    if (!target) throw new Error(`Unknown MCP tool: ${name}`)
    const [serverName, toolName] = target
    const server = this.servers.get(serverName)
    if (!server) throw new Error(`Unknown MCP server: ${serverName}`)
    if (this.expired(server)) {
      this.reportAuth(server)
      throw new Error(
        `The credentials for MCP server "${serverName}" have expired; the user needs to reconnect it.`
      )
    }
    let args: Record<string, unknown>
    try {
      args = argsJson?.trim()
        ? (JSON.parse(argsJson) as Record<string, unknown>)
        : {}
    } catch {
      throw new Error(`Invalid JSON arguments for ${name}`)
    }
    if (!server.initialized) await this.connect(server)
    if (!server.initialized) {
      throw new Error(`MCP server "${serverName}" is not connected`)
    }
    const res = await this.rpc<{
      content?: Array<{ type: string; text?: string }>
      isError?: boolean
    }>(server, 'tools/call', { name: toolName, arguments: args })
    const text = (res?.content ?? [])
      .map((c) => (c.type === 'text' && c.text ? c.text : JSON.stringify(c)))
      .join('\n')
    if (res?.isError) throw new Error(text || `${name} failed`)
    return text || JSON.stringify(res ?? {})
  }

  // ── Connection ─────────────────────────────────────────────────────

  private connect(server: Server): Promise<void> {
    if (server.connecting) return server.connecting
    const generation = server.generation
    server.connecting = (async () => {
      try {
        await this.rpc(server, 'initialize', {
          protocolVersion: PROTOCOL_VERSION,
          capabilities: { tools: {} },
          clientInfo: { name: 'legalese-cloud-agent', version: '0.1.0' },
        })
        void this.rpc(server, 'notifications/initialized', {}, true).catch(
          () => undefined
        )
        const listed = await this.rpc<{ tools?: McpToolDef[] }>(
          server,
          'tools/list',
          {}
        )
        if (server.generation !== generation) return
        server.tools = Array.isArray(listed?.tools) ? listed.tools : []
        server.initialized = true
        this.logger.info(
          `mcp: ${server.config.name} connected (${server.tools.length} tools)`
        )
      } catch (err) {
        this.logger.warn(
          `mcp: ${server.config.name} failed to connect: ${err instanceof McpHttpError ? `HTTP ${err.status}` : (err as Error).name}`
        )
      } finally {
        server.connecting = null
      }
    })()
    return server.connecting
  }

  private async rpc<T>(
    server: Server,
    method: string,
    params: Record<string, unknown>,
    notification = false
  ): Promise<T | null> {
    const id = rpcId++
    const res = await this.fetchImpl(server.config.url, {
      method: 'POST',
      headers: {
        ...server.headers,
        'Content-Type': 'application/json',
        Accept: 'application/json, text/event-stream',
        'MCP-Protocol-Version': PROTOCOL_VERSION,
        ...(server.sessionId ? { 'Mcp-Session-Id': server.sessionId } : {}),
      },
      body: JSON.stringify(
        notification
          ? { jsonrpc: '2.0', method, params }
          : { jsonrpc: '2.0', id, method, params }
      ),
      signal: AbortSignal.timeout(RPC_TIMEOUT_MS),
      redirect: 'error',
    })
    const sid = res.headers.get('Mcp-Session-Id')
    if (sid) server.sessionId = sid
    if (res.status === 401 || res.status === 403) {
      await res.body?.cancel().catch(() => undefined)
      this.reportAuth(server)
      throw new McpHttpError(
        `MCP server "${server.config.name}" needs the user to reconnect it (HTTP ${res.status}).`,
        res.status
      )
    }
    if (!res.ok) {
      await res.body?.cancel().catch(() => undefined)
      throw new McpHttpError(
        `${method} returned HTTP ${res.status}`,
        res.status
      )
    }
    if (notification) {
      await res.body?.cancel().catch(() => undefined)
      return null
    }
    const text = await res.text()
    if (!text) return null
    const raw = (res.headers.get('Content-Type') ?? '').includes(
      'text/event-stream'
    )
      ? sseResult(text, id)
      : text
    if (!raw) return null
    const payload = JSON.parse(raw) as {
      result?: T
      error?: { message?: string }
    }
    if (payload.error)
      throw new Error(payload.error.message ?? `${method} failed`)
    return payload.result ?? null
  }

  /** Ask for a fresh token when this one runs out (§6.4). */
  private watchExpiry(server: Server): void {
    if (server.expiryTimer) clearTimeout(server.expiryTimer)
    server.expiryTimer = undefined
    if (server.expiresAt === undefined) return
    const generation = server.generation
    const delay = Math.max(0, server.expiresAt - this.now())
    server.expiryTimer = setTimeout(
      () => {
        if (server.generation === generation) this.reportAuth(server)
      },
      Math.min(delay, 2_147_000_000)
    )
    server.expiryTimer.unref()
  }

  private expired(server: Server): boolean {
    return server.expiresAt !== undefined && server.expiresAt <= this.now()
  }

  private reportAuth(server: Server): void {
    if (server.reported) return
    server.reported = true
    server.initialized = false
    this.ctx.emit({
      type: 'auth-required',
      reason: 'mcp',
      server: server.config.name,
    })
  }
}

/** The JSON-RPC response for `id` in an SSE body. */
function sseResult(text: string, id: number): string | null {
  let last: string | null = null
  for (const block of text.split(/\r?\n\r?\n/)) {
    const data = block
      .split(/\r?\n/)
      .filter((l) => l.startsWith('data:'))
      .map((l) => l.slice(5).trimStart())
      .join('\n')
    if (!data) continue
    try {
      const msg = JSON.parse(data) as { id?: unknown }
      if (msg.id === id) return data
      last = data
    } catch {
      // not JSON
    }
  }
  return last
}

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
    ...(Array.isArray((schema as { required?: unknown }).required)
      ? { required: (schema as { required: string[] }).required }
      : {}),
  }
}
