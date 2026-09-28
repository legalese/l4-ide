/**
 * VS Code side of cloud sessions: settings, seed gathering from the
 * editor and the language server (§10), and the wiring that builds the
 * {@link CloudSessionManager} on top of the extension's auth, MCP
 * servers and chat-event path.
 *
 * Everything is behind `legaleseAi.cloudSessions.enabled` and a
 * non-empty `legaleseAi.cloudSessions.apiUrl` (§15.5).
 */
import * as vscode from 'vscode'
import { GetExportedFunctionsRequestType } from 'jl4-client-rpc'
import type { AiChatStartParams } from 'jl4-client-rpc'
import type { ChatServiceEvent, Logger } from '@repo/legalese-agent'
import { LEGALESE_CLOUD_DOMAIN, type AuthManager } from '../auth.js'
import type { VSCodeL4LanguageClient } from '../vscode-l4-language-client.js'
import {
  AccessTokenManager,
  mintAgentKey,
  type AuthProxyDeps,
} from './auth-proxy.js'
import {
  CloudSessionManager,
  type CloudSeed,
  type CloudSessionListener,
} from './cloud-session-manager.js'
import type { McpServerSource } from './mcp-transfer.js'
import { layoutSeed, type SeedSource } from './seed.js'
import { SessionsApiClient } from './sessions-api.js'

export const CLOUD_SESSIONS_ENABLED_SETTING = 'legaleseAi.cloudSessions.enabled'
export const CLOUD_SESSIONS_API_URL_SETTING = 'legaleseAi.cloudSessions.apiUrl'

export function cloudSessionsApiUrl(): string {
  return (
    vscode.workspace
      .getConfiguration()
      .get<string>(CLOUD_SESSIONS_API_URL_SETTING) ?? ''
  ).trim()
}

/** The feature flag: enabled and an API URL configured. */
export function isCloudSessionsEnabled(): boolean {
  return (
    vscode.workspace
      .getConfiguration()
      .get<boolean>(CLOUD_SESSIONS_ENABLED_SETTING) === true &&
    cloudSessionsApiUrl() !== ''
  )
}

// ── Seed gathering (§10) ──────────────────────────────────────────────

/** Resolve a chip / mention path (workspace-relative or absolute). */
async function resolveUserPath(p: string): Promise<vscode.Uri | undefined> {
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(p)) return vscode.Uri.parse(p)
  if (p.startsWith('/') || /^[A-Za-z]:[\\/]/.test(p)) return vscode.Uri.file(p)
  for (const folder of vscode.workspace.workspaceFolders ?? []) {
    const candidate = vscode.Uri.joinPath(folder.uri, p)
    try {
      const stat = await vscode.workspace.fs.stat(candidate)
      if (stat.type & vscode.FileType.File) return candidate
    } catch {
      // not in this folder
    }
  }
  return undefined
}

async function readUri(uri: vscode.Uri): Promise<Uint8Array> {
  const open = vscode.workspace.textDocuments.find(
    (d) => d.uri.toString() === uri.toString()
  )
  // Unsaved edits in the editor are what the user sees: send those.
  return open
    ? Buffer.from(open.getText(), 'utf8')
    : await vscode.workspace.fs.readFile(uri)
}

/**
 * The files for a new cloud session: the active file with its
 * transitive imports (from the language server), and @-mentioned
 * files, laid out relative to their common ancestor; plus the prompt
 * attachments. Files outside the workspace folders (and the active
 * file's own directory) are left out and logged.
 */
export async function gatherCloudSeed(
  params: Pick<
    AiChatStartParams,
    'activeFile' | 'includeActiveFile' | 'mentions' | 'attachments'
  >,
  client: VSCodeL4LanguageClient,
  logger: Logger
): Promise<CloudSeed & { root: string; skipped: string[] }> {
  const uris: vscode.Uri[] = []
  let activeDir: string | undefined

  if (params.includeActiveFile !== false && params.activeFile?.path) {
    const active = await resolveUserPath(params.activeFile.path)
    if (active) {
      uris.push(active)
      activeDir = active.path.replace(/\/[^/]*$/, '')
      if (active.path.endsWith('.l4')) {
        try {
          const doc = await vscode.workspace.openTextDocument(active)
          const res = await client.sendRequest(
            GetExportedFunctionsRequestType,
            { verDocId: { uri: doc.uri.toString(), version: doc.version } }
          )
          for (const u of res?.importedFiles ?? [])
            uris.push(vscode.Uri.parse(u))
        } catch (err) {
          logger.warn(
            `cloud-sessions: could not resolve imports: ${err instanceof Error ? err.message : String(err)}`
          )
        }
      }
    }
  }
  for (const m of params.mentions ?? []) {
    if (m.kind !== 'file') continue
    const uri = await resolveUserPath(m.label.replace(/^@/, ''))
    if (uri) uris.push(uri)
  }

  const sources: SeedSource[] = []
  const unreadable: string[] = []
  for (const uri of uris) {
    if (uri.scheme !== 'file') {
      unreadable.push(uri.toString())
      continue
    }
    try {
      sources.push({ path: uri.path, bytes: await readUri(uri) })
    } catch {
      unreadable.push(uri.toString())
    }
  }
  const roots = [
    ...(vscode.workspace.workspaceFolders ?? []).map((f) => f.uri.path),
    ...(activeDir ? [activeDir] : []),
  ]
  const { files, root, skipped } = layoutSeed(sources, roots)
  const allSkipped = [...skipped, ...unreadable]
  if (allSkipped.length > 0) {
    logger.info(
      `cloud-sessions: left ${allSkipped.length} file(s) out of the seed (outside the workspace, unreadable or unsafe names): ${allSkipped.join(', ')}`
    )
  }
  return {
    files,
    root,
    skipped: allSkipped,
    attachments: (params.attachments ?? []).map((a) => ({
      name: a.name,
      contentType: a.mediaType,
      bytes: Buffer.from(a.dataBase64, 'base64'),
    })),
  }
}

// ── Wiring ────────────────────────────────────────────────────────────

export interface CloudSessions {
  manager: CloudSessionManager
  api: SessionsApiClient
  tokens: AccessTokenManager
  isEnabled(): boolean
  gatherSeed(
    params: Parameters<typeof gatherCloudSeed>[0]
  ): ReturnType<typeof gatherCloudSeed>
  /** Listeners for cloud-only events, state and progress (the webview
   *  UI plugs in here). */
  listener: Omit<CloudSessionListener, 'chat'>
}

/**
 * Build the cloud-session services. Chat events from cloud sessions go
 * through `emitChat` — the same visibility-buffered path the local chat
 * service uses, so the webview renders them the same way.
 */
export function createCloudSessions(deps: {
  auth: AuthManager
  client: VSCodeL4LanguageClient
  mcp?: McpServerSource
  emitChat: (event: ChatServiceEvent) => void
  logger: Logger
}): CloudSessions & vscode.Disposable {
  const authDeps: AuthProxyDeps = {
    authBaseUrl: () => `https://${LEGALESE_CLOUD_DOMAIN}`,
    getSessionToken: () => deps.auth.getSessionToken(),
    storeSessionToken: (token) => deps.auth.setSessionToken(token),
  }
  const tokens = new AccessTokenManager(authDeps)
  const api = new SessionsApiClient({
    baseUrl: cloudSessionsApiUrl,
    getAccessToken: (opts) => tokens.get(opts),
  })
  const listener: Omit<CloudSessionListener, 'chat'> = {}
  const manager = new CloudSessionManager({
    api,
    mintAgentKey: (sid) => mintAgentKey(authDeps, sid),
    mcp: deps.mcp,
    logger: deps.logger,
    listener: {
      chat: deps.emitChat,
      cloudEvent: (e) => listener.cloudEvent?.(e),
      state: (sid, s) => listener.state?.(sid, s),
      gone: (sid, err) => listener.gone?.(sid, err),
      progress: (e) => listener.progress?.(e),
    },
  })
  // A sign-out or account switch must not keep using the old token.
  const authSub = deps.auth.onDidChange(() => tokens.invalidate())
  return {
    manager,
    api,
    tokens,
    listener,
    isEnabled: isCloudSessionsEnabled,
    gatherSeed: (params) => gatherCloudSeed(params, deps.client, deps.logger),
    dispose: () => {
      authSub.dispose()
      manager.dispose()
    },
  }
}
