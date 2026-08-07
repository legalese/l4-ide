// Write the L4 Rules MCP server into a local AI harness's own config file,
// and install the global gateway "skills marketplace" into a harness.
//
// Each harness keeps its MCP servers in a different file + schema:
//   claude-code     ~/.claude.json                         mcpServers{ {type:http,url} }
//   vscode          <user>/mcp.json                        servers{ {type:http,url} }
//   copilot-cli     ~/.copilot/mcp-config.json             mcpServers{ {type:http,url,tools} }
//   cursor          ~/.cursor/mcp.json                     mcpServers{ {url} }
//   windsurf        ~/.codeium/windsurf/mcp_config.json    mcpServers{ {serverUrl} }
//   cline           <user>/globalStorage/.../cline_mcp_settings.json  mcpServers{ {url,type:streamableHttp} }
//   claude-desktop  <platform>/Claude/claude_desktop_config.json  mcpServers{ stdio bridge via mcp-remote }
//
// Claude Code and the GitHub Copilot CLI additionally support the full plugin
// (skill + discovery MCP) through their own CLIs; the marketplace install
// tries that first and falls back to the bare MCP entry.
//
// Reads runtime-only environment variables (APPDATA on Windows, SHELL and
// COPILOT_HOME on Unix) that are resolved on the user's machine, not at
// build time.
/* eslint-disable turbo/no-undeclared-env-vars */

import * as fs from 'node:fs'
import * as os from 'node:os'
import * as path from 'node:path'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import * as vscode from 'vscode'
import { HARNESSES, type Harness } from 'jl4-client-rpc'
import { showTimedInformationMessage } from './notifications.js'

const execFileAsync = promisify(execFile)

/** Account-wide discovery MCP (org resolved from auth, no token baked in). */
export const DISCOVERY_MCP_URL = 'https://mcp.legalese.cloud'
// Our marketplace's plugin uses an absolute git source (not a relative path),
// so the plain `.json` URL adds cleanly — a `.git` repo is also served as a
// fallback for the relative-path limitation that doesn't apply here.
const MARKETPLACE_JSON = 'https://skills.legalese.cloud/marketplace.json'
const GATEWAY_PLUGIN = 'rules@legalese-cloud'
// `copilot plugin marketplace add` takes an OWNER/REPO on github.com, not a
// URL, so the Copilot path uses the public mirror of the same catalog.
const MARKETPLACE_REPO = 'legalese/cloud-rules'

/**
 * Harness display names, derived from the shared `HARNESSES` list the sidebar
 * dropdown renders. Deriving rather than restating keeps the toast ("Added the
 * L4 Rules to VS Code (Copilot)") worded exactly like the menu entry the user
 * just clicked — a second hand-maintained table drifts out of sync.
 */
const LABELS: Record<Harness, string> = Object.fromEntries(
  HARNESSES.map((h) => [h.id, h.label])
) as Record<Harness, string>

/** Per-harness hint shown after a successful write. */
const RELOAD_HINT: Record<Harness, string> = {
  'claude-code': 'Restart Claude Code to pick it up.',
  vscode: 'Reload the VS Code window to pick it up.',
  'copilot-cli': 'Restart Copilot CLI to pick it up.',
  cursor: 'Restart Cursor to pick it up.',
  windsurf: 'Restart Windsurf to pick it up.',
  cline: 'Reload the VS Code window to pick it up.',
  'claude-desktop': 'Restart Claude Desktop to pick it up.',
}

export interface HarnessCtx {
  /** VS Code user-data dir (contains `mcp.json` + `globalStorage/`). */
  userDataPath: string | undefined
  outputChannel: vscode.OutputChannel
}

export interface WriteResult {
  ok: boolean
  created?: boolean
  file?: string
  error?: string
  /** Extra caveat to append to the success toast (e.g. the mcp-remote bridge). */
  note?: string
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Json = any

interface ConfigPlan {
  file: string
  apply: (cfg: Json) => void
  /** Refuse to create the file when missing (harness not installed). */
  needsExisting?: boolean
  note?: string
}

/** Copilot CLI's config root. `COPILOT_HOME` overrides the `~/.copilot`
 *  default, and users who set it expect us to honour it. */
export function copilotHome(): string {
  return process.env.COPILOT_HOME || path.join(os.homedir(), '.copilot')
}

function claudeDesktopConfigPath(): string {
  const home = os.homedir()
  if (process.platform === 'win32') {
    return path.join(
      process.env.APPDATA ?? path.join(home, 'AppData', 'Roaming'),
      'Claude',
      'claude_desktop_config.json'
    )
  }
  if (process.platform === 'darwin') {
    return path.join(
      home,
      'Library',
      'Application Support',
      'Claude',
      'claude_desktop_config.json'
    )
  }
  return path.join(home, '.config', 'Claude', 'claude_desktop_config.json')
}

function planFor(
  harness: Harness,
  serverName: string,
  url: string,
  ctx: HarnessCtx
): ConfigPlan | { error: string } {
  const home = os.homedir()
  switch (harness) {
    case 'claude-code':
      return {
        file: path.join(home, '.claude.json'),
        needsExisting: true,
        apply: (c) => {
          c.mcpServers ??= {}
          c.mcpServers[serverName] = { type: 'http', url }
        },
      }
    case 'vscode':
      if (!ctx.userDataPath)
        return { error: "Couldn't locate VS Code's user folder (mcp.json)." }
      return {
        file: path.join(ctx.userDataPath, 'mcp.json'),
        apply: (c) => {
          c.servers ??= {}
          c.servers[serverName] = { type: 'http', url }
        },
      }
    case 'copilot-cli':
      return {
        file: path.join(copilotHome(), 'mcp-config.json'),
        apply: (c) => {
          c.mcpServers ??= {}
          // `tools` is not optional here the way it is elsewhere: Copilot CLI
          // enables no tools from a server until they are named, so an entry
          // without it connects but exposes nothing.
          c.mcpServers[serverName] = { type: 'http', url, tools: ['*'] }
        },
      }
    case 'cursor':
      return {
        file: path.join(home, '.cursor', 'mcp.json'),
        apply: (c) => {
          c.mcpServers ??= {}
          c.mcpServers[serverName] = { url }
        },
      }
    case 'windsurf':
      return {
        file: path.join(home, '.codeium', 'windsurf', 'mcp_config.json'),
        apply: (c) => {
          c.mcpServers ??= {}
          c.mcpServers[serverName] = { serverUrl: url }
        },
      }
    case 'cline':
      if (!ctx.userDataPath)
        return {
          error: "Couldn't locate VS Code's user folder (Cline settings).",
        }
      return {
        file: path.join(
          ctx.userDataPath,
          'globalStorage',
          'saoudrizwan.claude-dev',
          'settings',
          'cline_mcp_settings.json'
        ),
        apply: (c) => {
          c.mcpServers ??= {}
          c.mcpServers[serverName] = {
            url,
            type: 'streamableHttp',
            disabled: false,
          }
        },
      }
    case 'claude-desktop':
      return {
        file: claudeDesktopConfigPath(),
        note: 'Claude Desktop reaches remote servers via the mcp-remote bridge (needs Node/npx).',
        apply: (c) => {
          c.mcpServers ??= {}
          c.mcpServers[serverName] = {
            command: 'npx',
            args: ['-y', 'mcp-remote', url],
          }
        },
      }
  }
}

/** Merge an entry into a (possibly missing / empty) JSON config file. */
function mergeJsonFile(
  file: string,
  apply: (cfg: Json) => void
): { created: boolean } {
  let cfg: Json = {}
  let existed = false
  try {
    const raw = fs.readFileSync(file, 'utf-8')
    existed = true
    if (raw.trim()) cfg = JSON.parse(raw)
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code !== 'ENOENT') {
      throw new Error(
        `${path.basename(file)} is not valid JSON — add the server manually.`
      )
    }
    // ENOENT → create it below.
  }
  if (!cfg || typeof cfg !== 'object') cfg = {}
  apply(cfg)
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + '\n')
  return { created: !existed }
}

/**
 * Write (or refresh) an MCP server entry for `harness`. Returns a result;
 * the caller composes the user-facing toast.
 */
export function writeHarnessMcp(
  harness: Harness,
  serverName: string,
  url: string,
  ctx: HarnessCtx
): WriteResult {
  const plan = planFor(harness, serverName, url, ctx)
  if ('error' in plan) return { ok: false, error: plan.error }

  if (plan.needsExisting) {
    try {
      fs.accessSync(plan.file, fs.constants.R_OK)
    } catch {
      return {
        ok: false,
        error: `${LABELS[harness]} not found (${plan.file} is missing). Install ${LABELS[harness]} first, then try again.`,
      }
    }
  }

  try {
    const { created } = mergeJsonFile(plan.file, plan.apply)
    ctx.outputChannel.appendLine(
      `[harness] ${created ? 'Created' : 'Updated'} ${plan.file} (${serverName})`
    )
    return { ok: true, created, file: plan.file, note: plan.note }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    ctx.outputChannel.appendLine(
      `[harness] Failed to write ${plan.file}: ${msg}`
    )
    return { ok: false, error: msg }
  }
}

/** Toast the outcome of a write (success or the actionable error). */
export function announce(
  harness: Harness,
  subject: string,
  res: WriteResult
): void {
  if (!res.ok) {
    void vscode.window.showWarningMessage(
      res.error ?? `Could not add ${subject} to ${LABELS[harness]}.`
    )
    return
  }
  let msg = `Added ${subject} to ${LABELS[harness]}. ${RELOAD_HINT[harness]}`
  if (res.note) msg += ` ${res.note}`
  void vscode.window.showInformationMessage(msg, 'Okay')
}

// ---------------------------------------------------------------------------
// Plugin install (marketplace) via a harness's own CLI.
// ---------------------------------------------------------------------------

async function runHarnessCli(
  bin: string,
  args: string[],
  out: vscode.OutputChannel
): Promise<void> {
  if (process.platform === 'win32') {
    await execFileAsync(bin, args, { timeout: 90_000 })
    return
  }
  // Use the login shell so we see the same PATH the user's terminal does
  // (the extension host's PATH often omits ~/.local/bin etc.).
  const shell = process.env.SHELL || '/bin/sh'
  const cmd = [bin, ...args]
    .map((a) => `'${a.replace(/'/g, "'\\''")}'`)
    .join(' ')
  await execFileAsync(shell, ['-lic', cmd], { timeout: 90_000 })
  out.appendLine(`[harness] ran: ${bin} ${args.join(' ')}`)
}

/**
 * The two harnesses that can install the whole plugin — skill + discovery MCP
 * — through their own CLI, rather than us hand-writing an MCP entry.
 *
 * They differ in what `marketplace add` accepts: Claude Code takes the hosted
 * manifest URL, while `copilot plugin marketplace add` takes an OWNER/REPO on
 * github.com. Both then install the same `rules@legalese-cloud` plugin.
 */
const PLUGIN_CLI: Partial<
  Record<Harness, { bin: string; marketplace: string }>
> = {
  'claude-code': { bin: 'claude', marketplace: MARKETPLACE_JSON },
  'copilot-cli': { bin: 'copilot', marketplace: MARKETPLACE_REPO },
}

/**
 * Install the global gateway marketplace into `harness`.
 *  - Claude Code / GitHub Copilot CLI: add the marketplace + install the
 *    `rules@legalese-cloud` plugin (skill + discovery MCP) via that harness's
 *    CLI; if the CLI isn't available, fall back to registering the discovery
 *    MCP server directly.
 *  - Everything else: register the discovery MCP server.
 */
export async function installMarketplaceToHarness(
  harness: Harness,
  ctx: HarnessCtx
): Promise<void> {
  const cli = PLUGIN_CLI[harness]
  if (cli) {
    try {
      await runHarnessCli(
        cli.bin,
        ['plugin', 'marketplace', 'add', cli.marketplace],
        ctx.outputChannel
      )
      await runHarnessCli(
        cli.bin,
        ['plugin', 'install', GATEWAY_PLUGIN],
        ctx.outputChannel
      )
      void vscode.window.showInformationMessage(
        `Installed the L4 Rules plugin (${GATEWAY_PLUGIN}) into ${LABELS[harness]}. ${RELOAD_HINT[harness]}`,
        'Okay'
      )
      return
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      ctx.outputChannel.appendLine(
        `[harness] ${cli.bin} CLI plugin install failed (${msg}); falling back to MCP entry`
      )
      // Fall through to the direct MCP write below.
    }
  }

  const res = writeHarnessMcp(harness, 'legalese-rules', DISCOVERY_MCP_URL, ctx)
  if (cli && !res.ok) {
    // Make the fallback failure actionable: the CLI route is the norm.
    void vscode.window.showWarningMessage(
      `Could not install the L4 Rules plugin. Install the ${LABELS[harness]} CLI, or add the marketplace manually: ${cli.marketplace}`
    )
    return
  }
  announce(harness, 'the L4 Rules', res)
  // Quiet confirmation that nothing changed when re-running.
  if (res.ok && !res.created) {
    showTimedInformationMessage(`${LABELS[harness]} already had the L4 Rules.`)
  }
}
