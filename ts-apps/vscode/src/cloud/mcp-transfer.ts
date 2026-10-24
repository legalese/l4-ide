/**
 * The user's HTTP / SSE MCP servers in a cloud session (spec §6.4).
 *
 * - Configuration (names, URLs, enabled tools — no secrets) goes into
 *   `POST /sessions` and from there into `session.json`.
 * - Credentials (static headers, OAuth access tokens) are sealed to the
 *   running harness's public key and sent as an `mcp-credentials`
 *   command. Only ciphertext reaches the session folder.
 *
 * stdio servers are programs on this machine and are never transferred.
 * No `vscode` import: the extension supplies an {@link McpServerSource}.
 */
import {
  MCP_SERVER_NAME_RE,
  encodeSealed,
  mcpCredentials,
  mcpCredentialsContext,
  seal,
  type McpCredentials,
  type McpServerConfig,
} from '@repo/legalese-agent/protocol'

/** A server the user has enabled, as the extension knows it. */
export interface LocalMcpServer {
  /** The extension's own id (display name) for the server. */
  id: string
  url: string
  transport: 'http' | 'sse' | 'stdio'
  /** Tools the user left enabled; undefined = all. */
  enabledTools?: string[]
}

export interface McpServerSource {
  /** Enabled servers (the master switch and per-server toggles applied). */
  enabledServers(): LocalMcpServer[]
  /** Headers to authenticate to one server — static headers plus a
   *  fresh OAuth access token. `{}` when it needs none; `null` when it
   *  needs a sign-in first. */
  headersFor(id: string): Promise<Record<string, string> | null>
}

/** Map a server id to a protocol-safe name, unique within `used`. */
export function cloudServerName(id: string, used: Set<string>): string {
  let base = id.replace(/[^A-Za-z0-9_-]+/g, '_').replace(/^_+|_+$/g, '')
  if (!base) base = 'server'
  base = base.slice(0, 60)
  let name = base
  for (let i = 2; used.has(name) || !MCP_SERVER_NAME_RE.test(name); i++) {
    name = `${base}_${i}`
  }
  used.add(name)
  return name
}

/**
 * The servers to pass to a cloud session: HTTP/SSE over https only.
 * Returns the configs for `POST /sessions` and the name → local id map
 * used later for credentials. Deterministic for a given server list,
 * so a window that didn't create the session maps the names the same way.
 */
export function cloudMcpServers(servers: LocalMcpServer[]): {
  configs: McpServerConfig[]
  ids: Map<string, string>
  skipped: string[]
} {
  const used = new Set<string>()
  const configs: McpServerConfig[] = []
  const ids = new Map<string, string>()
  const skipped: string[] = []
  for (const s of [...servers].sort((a, b) => a.id.localeCompare(b.id))) {
    if (s.transport === 'stdio' || !/^https:\/\/[^\s]+$/.test(s.url)) {
      skipped.push(s.id)
      continue
    }
    if (configs.length >= 32) {
      skipped.push(s.id)
      continue
    }
    const name = cloudServerName(s.id, used)
    ids.set(name, s.id)
    configs.push({
      name,
      url: s.url,
      transport: s.transport,
      ...(s.enabledTools ? { enabledTools: s.enabledTools } : {}),
    })
  }
  return { configs, ids, skipped }
}

/**
 * Collect credentials for the session's servers (`names`, as in its
 * `session.json`). Servers that need no headers are left out; servers
 * needing a sign-in are reported in `unauthorized`.
 */
export async function collectMcpCredentials(
  source: McpServerSource,
  names: string[],
  only?: string
): Promise<{ credentials: McpCredentials; unauthorized: string[] }> {
  const { ids } = cloudMcpServers(source.enabledServers())
  const servers: McpCredentials['servers'] = []
  const unauthorized: string[] = []
  for (const name of names) {
    if (only !== undefined && name !== only) continue
    const id = ids.get(name)
    if (!id) continue
    const headers = await source.headersFor(id)
    if (headers === null) {
      unauthorized.push(name)
      continue
    }
    const entries = Object.entries(headers).slice(0, 16)
    if (entries.length === 0) continue
    servers.push({ name, headers: Object.fromEntries(entries) })
  }
  return {
    credentials: mcpCredentials({ servers }, 'credentials'),
    unauthorized,
  }
}

/** The `sealed` field of an `mcp-credentials` command. */
export function sealMcpCredentials(
  publicKey: string,
  sessionId: string,
  credentials: McpCredentials
): string {
  return encodeSealed(
    seal(
      publicKey,
      JSON.stringify(credentials),
      mcpCredentialsContext(sessionId)
    )
  )
}
