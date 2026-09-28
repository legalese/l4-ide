import { AGENT_KEY_RE, ULID_RE } from '@repo/legalese-agent/protocol'
import { LOCAL_AI_ENDPOINT } from '@repo/legalese-agent'
import { parseLogLevel, type LogLevel } from './logger.js'

/** Where the image puts the language server (item `cloud-agent-image`). */
export const DEFAULT_LSP_COMMAND = '/app/bin/jl4-lsp'
/** The session task's mount (spec §5.1). */
export const WORKSPACE_ROOT = '/workspace'

export interface HarnessConfig {
  mode: 'cloud' | 'dev'
  sessionId: string
  /** `AGENT_KEY`; absent in `--dev`. */
  agentKey?: string
  /** The user folder: `/workspace` in the cloud, `--root` in dev. */
  root: string
  aiProxyUrl: string
  /** The ai-proxy is a developer's local one (`Bearer dev-local`). */
  aiLocal: boolean
  /** l4-rules MCP endpoint; absent in dev unless `--mcp-url`. */
  mcpUrl?: string
  /** jl4-auth-proxy; absent in dev. */
  authUrl?: string
  logLevel: LogLevel
  lspCommand: string
  /** Fargate task metadata endpoint, for the lease's task id. */
  taskMetadataUri?: string
}

export class ConfigError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'ConfigError'
  }
}

/**
 * The environment the harness accepts (spec §5.1): the static
 * task-definition variables plus `SESSION_ID` and `AGENT_KEY` from the
 * `RunTask` override. Everything is validated by pattern; the image's
 * entry point (item `cloud-agent-image`) already dropped everything
 * else, and this re-checks so the harness never trusts its caller.
 */
export const STATIC_ENV = [
  'AI_PROXY_URL',
  'MCP_URL',
  'AUTH_URL',
  'LOG_LEVEL',
] as const
export const OVERRIDE_ENV = ['SESSION_ID', 'AGENT_KEY'] as const

/** An `https://` URL without credentials, query or fragment. */
export function checkHttpsUrl(name: string, raw: string | undefined): string {
  if (!raw) throw new ConfigError(`${name} is required`)
  let url: URL
  try {
    url = new URL(raw)
  } catch {
    throw new ConfigError(`${name} is not a URL`)
  }
  if (url.protocol !== 'https:') throw new ConfigError(`${name} must be https`)
  if (url.username || url.password || url.search || url.hash) {
    throw new ConfigError(
      `${name} must not carry credentials, a query or a fragment`
    )
  }
  return url.href.replace(/\/+$/, '')
}

/** Only the Fargate task-metadata endpoint (link-local) is accepted. */
const TASK_METADATA_RE = /^http:\/\/169\.254\.170\.2\/v4\/[A-Za-z0-9-]+$/

export function parseCloudEnv(env: NodeJS.ProcessEnv): HarnessConfig {
  const sessionId = env.SESSION_ID ?? ''
  if (!ULID_RE.test(sessionId))
    throw new ConfigError('SESSION_ID must be a ULID')
  const agentKey = env.AGENT_KEY ?? ''
  if (!AGENT_KEY_RE.test(agentKey)) {
    throw new ConfigError('AGENT_KEY must be an sk_ key')
  }
  const logLevel = parseLogLevel(env.LOG_LEVEL)
  if (!logLevel) throw new ConfigError('LOG_LEVEL is invalid')
  const meta = env.ECS_CONTAINER_METADATA_URI_V4
  return {
    mode: 'cloud',
    sessionId,
    agentKey,
    root: WORKSPACE_ROOT,
    aiProxyUrl: checkHttpsUrl('AI_PROXY_URL', env.AI_PROXY_URL),
    aiLocal: false,
    mcpUrl: checkHttpsUrl('MCP_URL', env.MCP_URL),
    authUrl: checkHttpsUrl('AUTH_URL', env.AUTH_URL),
    logLevel,
    lspCommand: DEFAULT_LSP_COMMAND,
    ...(meta && TASK_METADATA_RE.test(meta) ? { taskMetadataUri: meta } : {}),
  }
}

export const DEV_USAGE = `Usage:
  cloud-agent                                   (cloud: configured by the environment)
  cloud-agent --dev --root <dir> --session <ulid> [--init]
              [--ai-proxy <url>] [--mcp-url <url>] [--lsp <path>] [--log-level <level>]
  cloud-agent send --root <dir> --session <ulid> '<command json>'

--dev runs one session folder <dir>/sessions/<ulid> against a local
ai-proxy (default ${LOCAL_AI_ENDPOINT}, no key chain). --init creates the
folder if it's missing. "send" queues a command the way the Sessions API
does, e.g. '{"type":"message","turnId":"t1","text":"hello"}'.`

export interface DevArgs {
  root: string
  sessionId: string
  init: boolean
  aiProxyUrl: string
  mcpUrl?: string
  lspCommand: string
  logLevel: LogLevel
  rest: string[]
}

export function parseDevArgs(argv: string[]): DevArgs {
  const flags = new Map<string, string>()
  const rest: string[] = []
  let init = false
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!
    if (a === '--dev') continue
    if (a === '--init') {
      init = true
      continue
    }
    if (a.startsWith('--')) {
      const v = argv[i + 1]
      if (v === undefined) throw new ConfigError(`${a} needs a value`)
      flags.set(a, v)
      i++
      continue
    }
    rest.push(a)
  }
  const root = flags.get('--root')
  if (!root) throw new ConfigError('--root is required')
  const sessionId = flags.get('--session') ?? ''
  if (!ULID_RE.test(sessionId))
    throw new ConfigError('--session must be a ULID')
  const logLevel = parseLogLevel(flags.get('--log-level'))
  if (!logLevel) throw new ConfigError('--log-level is invalid')
  return {
    root,
    sessionId,
    init,
    aiProxyUrl: (flags.get('--ai-proxy') ?? LOCAL_AI_ENDPOINT).replace(
      /\/+$/,
      ''
    ),
    mcpUrl: flags.get('--mcp-url'),
    lspCommand: flags.get('--lsp') ?? 'jl4-lsp',
    logLevel,
    rest,
  }
}
