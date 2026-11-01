/**
 * The user's HTTP / SSE MCP servers in a cloud session.
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
  /** Headers to authenticate to one server, from what is stored here:
   *  static headers, plus a fresh OAuth access token when there is a
   *  stored sign-in. `{}` when nothing is stored (whether the server
   *  wants a sign-in shows when the session reports it); `null` when a
   *  stored sign-in no longer works. `refresh` refreshes the token even
   *  before it expires. */
  headersFor(
    id: string,
    opts?: { refresh?: boolean }
  ): Promise<Record<string, string> | null>
  /** The interactive sign-in (a browser OAuth consent) that the
   *  server's Sign in in the settings runs. It reports its own failures
   *  to the user. */
  signIn?(id: string): Promise<{ ok: boolean; error?: string }>
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
 * Collect credentials for the session's servers (name and URL, as in
 * its `session.json`). Only a local server with the same name and the
 * same URL gets its credentials sent: they are for that URL. Servers
 * whose stored sign-in no longer works are in `unauthorized`; servers
 * with nothing to send are in `withoutHeaders` (they need a sign-in if
 * the session reports them). `refresh`: servers whose token the session
 * turned down, refreshed before it expires.
 */
export async function collectMcpCredentials(
  source: McpServerSource,
  sessionServers: Array<{ name: string; url: string }>,
  opts: { refresh?: ReadonlySet<string> } = {}
): Promise<{
  credentials: McpCredentials
  unauthorized: string[]
  withoutHeaders: string[]
}> {
  const { configs, ids } = cloudMcpServers(source.enabledServers())
  const servers: McpCredentials['servers'] = []
  const unauthorized: string[] = []
  const withoutHeaders: string[] = []
  for (const { name, url } of sessionServers) {
    const id = ids.get(name)
    if (!id || configs.find((c) => c.name === name)?.url !== url) continue
    const headers = await source.headersFor(id, {
      refresh: opts.refresh?.has(name) ?? false,
    })
    if (headers === null) {
      unauthorized.push(name)
      continue
    }
    const entries = Object.entries(headers).slice(0, 16)
    if (entries.length === 0) {
      withoutHeaders.push(name)
      continue
    }
    servers.push({ name, headers: Object.fromEntries(entries) })
  }
  return {
    credentials: mcpCredentials({ servers }, 'credentials'),
    unauthorized,
    withoutHeaders,
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
