import { AGENT_KEY_RE, RUN_RE, ULID_RE } from '@repo/legalese-agent/protocol'
import { LOCAL_AI_ENDPOINT } from '@repo/legalese-agent'
import { parseLogLevel, type LogLevel } from './logger.js'

/**
 * Where the image puts the language server.
 */
export const DEFAULT_LSP_COMMAND = '/app/bin/jl4-lsp'
/** The session task's mount. */
export const WORKSPACE_ROOT = '/workspace'

export interface HarnessConfig {
  mode: 'cloud' | 'dev'
  sessionId: string
  /** The run this harness is (`SESSION_RUN`). In `--dev` the
   *  harness claims the next run itself. */
  run?: number
  /** `AGENT_KEY`; absent in `--dev`. */
  agentKey?: string
  /** The user folder: `/workspace` in the cloud, `--root` in dev. */
  root: string
  aiUrl: string
  /** The AI service is a developer's local one (`Bearer dev-local`). */
  aiLocal: boolean
  /** l4-rules MCP endpoint; absent in dev unless `--mcp-url`. */
  mcpUrl?: string
  /** The Legalese Cloud API; absent in dev. */
  authUrl?: string
  logLevel: LogLevel
  lspCommand: string
  /** The task running this session, for its lease. */
  taskId?: string
}

export class ConfigError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'ConfigError'
  }
}

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

/** A task id that's safe in a lease and a log line. */
const TASK_ID_RE = /^[A-Za-z0-9_.-]{1,128}$/

/**
 * The environment the harness accepts: `AI_URL`, `MCP_URL`, `AUTH_URL` and
 * `LOG_LEVEL`, `SESSION_ID`, `SESSION_RUN` and `AGENT_KEY` for this run, and an
 * optional `TASK_ID`. Everything is validated by pattern; the image's entry
 * point already dropped everything else, and this re-checks so the harness
 * never trusts its caller.
 */
export function parseCloudEnv(env: NodeJS.ProcessEnv): HarnessConfig {
  const sessionId = env.SESSION_ID ?? ''
  if (!ULID_RE.test(sessionId))
    throw new ConfigError('SESSION_ID must be a ULID')
  const runText = env.SESSION_RUN ?? ''
  if (!RUN_RE.test(runText)) {
    throw new ConfigError('SESSION_RUN must be a run number (1, 2, …)')
  }
  const agentKey = env.AGENT_KEY ?? ''
  if (!AGENT_KEY_RE.test(agentKey)) {
    throw new ConfigError('AGENT_KEY must be an sk_ key')
  }
  const logLevel = parseLogLevel(env.LOG_LEVEL)
  if (!logLevel) throw new ConfigError('LOG_LEVEL is invalid')
  const taskId = env.TASK_ID
  return {
    mode: 'cloud',
    sessionId,
    run: Number(runText),
    agentKey,
    root: WORKSPACE_ROOT,
    aiUrl: checkHttpsUrl('AI_URL', env.AI_URL),
    aiLocal: false,
    mcpUrl: checkHttpsUrl('MCP_URL', env.MCP_URL),
    authUrl: checkHttpsUrl('AUTH_URL', env.AUTH_URL),
    logLevel,
    lspCommand: DEFAULT_LSP_COMMAND,
    ...(taskId && TASK_ID_RE.test(taskId) ? { taskId } : {}),
  }
}

export const DEV_USAGE = `Usage:
  cloud-agent                                   (cloud: configured by the environment)
  cloud-agent --dev --root <dir> --session <ulid> [--init]
              [--ai-url <url>] [--mcp-url <url>] [--lsp <path>] [--log-level <level>]
  cloud-agent send --root <dir> --session <ulid> '<command json>'

--dev runs one session folder <dir>/sessions/<ulid> against a local
AI server (default ${LOCAL_AI_ENDPOINT}, no key chain). --init creates the
folder if it's missing. "send" queues a command the way the Sessions API
does, e.g. '{"type":"message","turnId":"t1","text":"hello"}'.`

export interface DevArgs {
  root: string
  sessionId: string
  init: boolean
  aiUrl: string
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
    aiUrl: (flags.get('--ai-url') ?? LOCAL_AI_ENDPOINT).replace(/\/+$/, ''),
    mcpUrl: flags.get('--mcp-url'),
    lspCommand: flags.get('--lsp') ?? 'jl4-lsp',
    logLevel,
    rest,
  }
}
