/**
 * cloud-agent — the Legalese AI harness, headless, for one cloud
 * session (spec §5.4, §11).
 *
 *   cloud: SESSION_ID, AGENT_KEY, AI_PROXY_URL, MCP_URL, AUTH_URL,
 *          LOG_LEVEL; the user's folder is mounted at /workspace.
 *   dev:   cloud-agent --dev --root <dir> --session <ulid> [...]
 */
import { stat } from 'node:fs/promises'
import * as os from 'node:os'
import * as path from 'node:path'
import { McpToolClient, type Logger } from '@repo/legalese-agent'
import {
  ConfigError,
  DEV_USAGE,
  parseCloudEnv,
  parseDevArgs,
  type HarnessConfig,
} from './config.js'
import { initSessionFolder, sendCommand } from './dev.js'
import { GitSync } from './git-sync.js'
import { McpServers } from './mcp-servers.js'
import { Jl4Lsp } from './jl4-lsp.js'
import { DevAuth, KeyChainAuth, authRetryingFetch } from './key-chain.js'
import { JsonLogger } from './logger.js'
import { DATA_DIR, NodeWorkspace, TMP_DIR } from './node-workspace.js'
import { ensureDirNoFollow } from './safe-fs.js'
import {
  CHAIN_END_WAIT_MS,
  Runner,
  SHUTDOWN_BUDGET_MS,
  waitFor,
  type RunnerPlugin,
} from './runner.js'

export const HARNESS_VERSION = '0.1.0'

/** The harness's plugins: git sync (§9) and the user's MCP servers (§6.4). */
export function defaultPlugins(env: NodeJS.ProcessEnv): RunnerPlugin[] {
  return [new GitSync(env), new McpServers()]
}

/** The child's whole environment: nothing from the harness's own. */
export function childEnv(env: NodeJS.ProcessEnv): NodeJS.ProcessEnv {
  const out: NodeJS.ProcessEnv = { LANG: 'C.UTF-8' }
  for (const k of ['PATH', 'HOME', 'TMPDIR']) {
    const v = env[k]
    if (v) out[k] = v
  }
  return out
}

/**
 * A rejection nothing handled, or a throw outside every try (Node would
 * otherwise exit at once, with the lease still live, session.json saying
 * running and the key chain open): log it and run the runner's normal
 * shutdown. If that hangs, exit anyway once its budget is over. Returns
 * whether it fired, and a function removing the handlers.
 */
export function installFatalHandlers(
  runner: Pick<Runner, 'fail'>,
  logger: Logger,
  proc: Pick<NodeJS.Process, 'on' | 'off' | 'exit'> = process,
  graceMs = SHUTDOWN_BUDGET_MS + 5_000
): { fired: () => boolean; remove: () => void } {
  let fired = false
  const onFatal = (err: unknown): void => {
    logger.error('unhandled error; shutting down', err)
    if (fired) return
    fired = true
    void runner.fail()
    setTimeout(() => proc.exit(1), graceMs).unref()
  }
  proc.on('unhandledRejection', onFatal)
  proc.on('uncaughtException', onFatal)
  return {
    fired: () => fired,
    remove: () => {
      proc.off('unhandledRejection', onFatal)
      proc.off('uncaughtException', onFatal)
    },
  }
}

async function taskIdFrom(cfg: HarnessConfig): Promise<string> {
  const fallback =
    `${cfg.mode}-${os.hostname().replace(/[^A-Za-z0-9_.-]/g, '')}-${process.pid}`.slice(
      0,
      120
    )
  if (!cfg.taskMetadataUri) return fallback
  try {
    const res = await fetch(`${cfg.taskMetadataUri}/task`, {
      signal: AbortSignal.timeout(3_000),
    })
    const body = (await res.json()) as { TaskARN?: unknown }
    const arn = typeof body.TaskARN === 'string' ? body.TaskARN : ''
    const id = arn.split('/').pop() ?? ''
    return /^[A-Za-z0-9_.-]{1,128}$/.test(id) ? id : fallback
  } catch {
    return fallback
  }
}

export async function runHarness(
  cfg: HarnessConfig,
  env: NodeJS.ProcessEnv,
  logger: Logger
): Promise<number> {
  const holder: { runner?: Runner } = {}
  const keyChain =
    cfg.mode === 'cloud'
      ? new KeyChainAuth({
          authUrl: cfg.authUrl!,
          sessionId: cfg.sessionId,
          initialKey: cfg.agentKey!,
          // The plain fetch, before runSession wraps the global one.
          fetch: globalThis.fetch.bind(globalThis),
          logger,
          onEnded: (e) => holder.runner?.onChainEnded(e.reason),
        })
      : undefined
  try {
    return await runSession(cfg, env, logger, keyChain, holder)
  } finally {
    // An early exit (no session folder, another task holds the lease, a
    // failed start) ends the chain too, so the key from AGENT_KEY doesn't
    // stay valid for 15 minutes. After a normal exit the runner already
    // ended it, and a parked chain has no key left: end() does nothing.
    if (keyChain) await waitFor(keyChain.end(), CHAIN_END_WAIT_MS)
  }
}

async function runSession(
  cfg: HarnessConfig,
  env: NodeJS.ProcessEnv,
  logger: Logger,
  keyChain: KeyChainAuth | undefined,
  holder: { runner?: Runner }
): Promise<number> {
  const sessionDir = path.join(cfg.root, 'sessions', cfg.sessionId)
  const repoDir = path.join(sessionDir, 'repo')
  const st = await stat(sessionDir).catch(() => null)
  if (!st?.isDirectory()) {
    logger.error('session folder does not exist; exiting')
    return 1
  }
  const taskId = await taskIdFrom(cfg)
  logger.info(
    `harness ${HARNESS_VERSION} starting (mode=${cfg.mode}, task=${taskId})`
  )

  // The concrete providers: their headers don't depend on the request's
  // URL (the key goes only to the configured origins, authRetryingFetch).
  let auth: KeyChainAuth | DevAuth
  if (keyChain) {
    // Renew and retry once when ai-proxy or MCP answer 401 (or ai-proxy
    // answers 403 invalid-credentials).
    globalThis.fetch = authRetryingFetch(
      globalThis.fetch.bind(globalThis),
      keyChain,
      [cfg.aiProxyUrl, ...(cfg.mcpUrl ? [cfg.mcpUrl] : [])]
    )
    auth = keyChain
  } else {
    auth = new DevAuth(cfg.sessionId)
  }

  // One jl4-lsp, project root repo/data (spec §5.4), for every .l4 file
  // in data/ and tmp/. `IMPORT name` looks in data/ first, then next to
  // the importing file: tmp/ drafts import data/ modules and their tmp/
  // siblings, but a tmp/ module can't shadow a data/ module of the same
  // name.
  const dataDir = path.join(repoDir, DATA_DIR)
  await ensureDirNoFollow(repoDir, dataDir)
  await ensureDirNoFollow(repoDir, path.join(repoDir, TMP_DIR))
  const lsp = await Jl4Lsp.spawn({
    command: cfg.lspCommand,
    root: dataDir,
    logger,
    env: childEnv(env),
  })
  const workspace = new NodeWorkspace(repoDir, lsp, logger)
  const mcpUrl = cfg.mcpUrl
  const providers = mcpUrl
    ? [
        new McpToolClient(
          {
            getLocalUrl: () => mcpUrl,
            getHeaders: () => auth.getAiAuthHeaders(),
          },
          logger
        ),
      ]
    : []

  const r = new Runner({
    sessionId: cfg.sessionId,
    sessionDir,
    taskId,
    logger,
    auth,
    chain: keyChain,
    workspace,
    l4: lsp,
    aiEndpoint: { url: cfg.aiProxyUrl, local: cfg.aiLocal },
    providers,
    plugins: defaultPlugins(childEnv(env)),
    extensionVersion: `cloud-agent/${HARNESS_VERSION}`,
  })
  holder.runner = r
  const onSignal = (sig: string): void => {
    logger.info(`${sig} received`)
    r.terminate()
  }
  process.once('SIGTERM', () => onSignal('SIGTERM'))
  process.once('SIGINT', () => onSignal('SIGINT'))
  const fatal = installFatalHandlers(r, logger)

  try {
    const reason = await r.run()
    if (reason === null) {
      await lsp.dispose()
      logger.info('another harness holds the lease; exiting')
    }
    return fatal.fired() ? 1 : 0
  } catch (err) {
    logger.error('harness failed', err)
    await lsp.dispose().catch(() => undefined)
    return 1
  } finally {
    fatal.remove()
  }
}

export async function main(
  argv: string[],
  env: NodeJS.ProcessEnv
): Promise<number> {
  try {
    if (argv[0] === 'send') {
      const args = parseDevArgs(argv.slice(1))
      const json = args.rest[0]
      if (!json) throw new ConfigError('send needs a command (JSON)')
      const n = await sendCommand(args.root, args.sessionId, JSON.parse(json))
      process.stdout.write(`queued command ${n}\n`)
      return 0
    }
    if (argv.includes('--help') || argv.includes('-h')) {
      process.stdout.write(DEV_USAGE + '\n')
      return 0
    }
    let cfg: HarnessConfig
    if (argv.includes('--dev')) {
      const args = parseDevArgs(argv)
      if (args.init) await initSessionFolder(args.root, args.sessionId)
      cfg = {
        mode: 'dev',
        sessionId: args.sessionId,
        root: path.resolve(args.root),
        aiProxyUrl: args.aiProxyUrl,
        aiLocal: true,
        mcpUrl: args.mcpUrl,
        logLevel: args.logLevel,
        lspCommand: args.lspCommand,
      }
    } else {
      cfg = parseCloudEnv(env)
      // Nothing started from here on (jl4-lsp, git) may inherit the key.
      delete env.AGENT_KEY
    }
    const logger = new JsonLogger(cfg.logLevel, { sid: cfg.sessionId })
    return await runHarness(cfg, env, logger)
  } catch (err) {
    if (err instanceof ConfigError || err instanceof SyntaxError) {
      process.stderr.write(`cloud-agent: ${err.message}\n\n${DEV_USAGE}\n`)
      return 2
    }
    process.stderr.write(`cloud-agent: ${(err as Error).message}\n`)
    return 1
  }
}

// Run when executed directly (the bundle, or `node out/src/main.js`).
const entry = process.argv[1] ?? ''
if (/(?:cloud-agent\.cjs|main\.js)$/.test(entry)) {
  void main(process.argv.slice(2), process.env).then((code) => {
    process.exitCode = code
    // Exit even if a stray handle (a socket, a timer) is still open.
    setTimeout(() => process.exit(code), 500).unref()
  })
}
