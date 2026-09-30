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
  type PromptFiles,
  type SessionFilesRecord,
  type SessionFilesStore,
} from './cloud-session-manager.js'
import { CloudGitSync, type GitApi, type GitApiResult } from './git-sync.js'
import type { McpServerSource } from './mcp-transfer.js'
import { layoutSeed, type SeedSource, type WorkspaceFolderRef } from './seed.js'
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

type PromptParams = Pick<
  AiChatStartParams,
  'activeFile' | 'includeActiveFile' | 'mentions' | 'attachments'
>

/**
 * The files a prompt refers to: the active file (when included) with
 * its transitive imports from the language server, and @-mentioned
 * files — read from the editor (unsaved edits included).
 */
async function collectPromptSources(
  params: PromptParams,
  client: VSCodeL4LanguageClient,
  logger: Logger
): Promise<{
  sources: SeedSource[]
  unreadable: string[]
  activeFile?: string
  mentions: string[]
}> {
  const uris: vscode.Uri[] = []
  let activeFile: string | undefined
  const mentions: string[] = []

  if (params.includeActiveFile !== false && params.activeFile?.path) {
    const active = await resolveUserPath(params.activeFile.path)
    if (active) {
      uris.push(active)
      activeFile = active.path
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
    if (uri) {
      uris.push(uri)
      mentions.push(uri.path)
    }
  }

  const sources: SeedSource[] = []
  const unreadable: string[] = []
  const seen = new Set<string>()
  for (const uri of uris) {
    if (uri.scheme !== 'file') {
      unreadable.push(uri.toString())
      continue
    }
    if (seen.has(uri.path)) continue
    seen.add(uri.path)
    try {
      sources.push({ path: uri.path, bytes: await readUri(uri) })
    } catch {
      unreadable.push(uri.toString())
    }
  }
  return {
    sources,
    unreadable,
    mentions,
    ...(activeFile ? { activeFile } : {}),
  }
}

function workspaceFolders(): WorkspaceFolderRef[] {
  return (vscode.workspace.workspaceFolders ?? [])
    .filter((f) => f.uri.scheme === 'file')
    .map((f) => ({ name: f.name, path: f.uri.path }))
}

/**
 * Ask once which local folder corresponds to a session's seed base
 * workspace folder `name` when no open workspace folder has that name
 * (the session was started on another machine or in another window).
 */
export async function pickLocalFolder(
  name: string
): Promise<string | undefined> {
  const browse = 'Choose a folder…'
  const open = workspaceFolders()
  const choice =
    open.length > 0
      ? await vscode.window.showQuickPick(
          [
            ...open.map((f) => ({ label: f.name, description: f.path })),
            { label: browse, description: '' },
          ],
          {
            title: `Which local folder is "${name}"?`,
            placeHolder: `This cloud session's files came from a workspace folder named "${name}". Pick the matching local folder so mentioned files land in the right place.`,
            ignoreFocusOut: true,
          }
        )
      : { label: browse, description: '' }
  if (!choice) return undefined
  if (choice.label !== browse) return choice.description
  const picked = await vscode.window.showOpenDialog({
    canSelectFolders: true,
    canSelectFiles: false,
    canSelectMany: false,
    openLabel: `Use as "${name}"`,
    title: `Which local folder is "${name}"?`,
  })
  return picked?.[0]?.path
}

/**
 * The files for a new cloud session: the active file with its
 * transitive imports (from the language server), and @-mentioned
 * files, laid out relative to their common ancestor; plus the prompt
 * attachments. Files outside the workspace folders (and the active
 * file's own directory) are left out and logged.
 */
export async function gatherCloudSeed(
  params: PromptParams,
  client: VSCodeL4LanguageClient,
  logger: Logger
): Promise<CloudSeed & { root: string; skipped: string[] }> {
  const { sources, unreadable, activeFile, mentions } =
    await collectPromptSources(params, client, logger)
  const folders = workspaceFolders()
  const roots = [
    ...folders.map((f) => f.path),
    ...(activeFile ? [activeFile.replace(/\/[^/]*$/, '')] : []),
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
    workspaceFolders: folders,
    skipped: allSkipped,
    ...(activeFile ? { activeFile } : {}),
    mentions,
    attachments: (params.attachments ?? []).map((a) => ({
      name: a.name,
      contentType: a.mediaType,
      bytes: Buffer.from(a.dataBase64, 'base64'),
    })),
  }
}

/** The files a later prompt in a cloud session refers to (§10). */
export async function gatherPromptFiles(
  params: PromptParams,
  client: VSCodeL4LanguageClient,
  logger: Logger
): Promise<PromptFiles> {
  const { sources, unreadable, activeFile, mentions } =
    await collectPromptSources(params, client, logger)
  if (unreadable.length > 0) {
    logger.info(
      `cloud-sessions: could not read ${unreadable.length} file(s): ${unreadable.join(', ')}`
    )
  }
  return {
    sources,
    ...(activeFile ? { activeFile } : {}),
    mentions,
    workspaceFolders: workspaceFolders(),
  }
}

/** Per-session sent-file hashes and local folder choice, in extension
 *  storage. */
export const SESSION_FILES_STORAGE_KEY = 'legaleseAi.cloudSessions.files'

export function mementoFilesStore(memento: vscode.Memento): SessionFilesStore {
  const all = (): Record<string, SessionFilesRecord> =>
    memento.get<Record<string, SessionFilesRecord>>(
      SESSION_FILES_STORAGE_KEY
    ) ?? {}
  return {
    get: (sid) => all()[sid],
    set: (sid, rec) => {
      const next = { ...all() }
      if (rec) next[sid] = rec
      else delete next[sid]
      return memento.update(SESSION_FILES_STORAGE_KEY, next)
    },
  }
}

// ── Git (§9.3) ────────────────────────────────────────────────────────

/** The subset of `vscode.git`'s exports this extension uses. */
interface GitExtensionExports {
  readonly enabled: boolean
  getAPI(version: 1): GitApi<vscode.Uri>
}

const GIT_UNAVAILABLE =
  "VS Code's Git support isn't available. Install git and make sure the built-in Git extension is enabled (setting `git.enabled`), then try again."

/** VS Code's built-in Git extension API, activating it if needed. */
export async function vscodeGitApi(): Promise<GitApiResult<vscode.Uri>> {
  const ext = vscode.extensions.getExtension<GitExtensionExports>('vscode.git')
  if (!ext) return { unavailable: GIT_UNAVAILABLE }
  try {
    const exports = ext.isActive ? ext.exports : await ext.activate()
    if (!exports?.enabled) return { unavailable: GIT_UNAVAILABLE }
    return { api: exports.getAPI(1) }
  } catch {
    return { unavailable: GIT_UNAVAILABLE }
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
  /** Files a later prompt refers to (§10). */
  gatherPromptFiles(
    params: Parameters<typeof gatherPromptFiles>[0]
  ): ReturnType<typeof gatherPromptFiles>
  /** Listeners for cloud-only events, state and progress (the webview
   *  UI plugs in here). */
  listener: Omit<CloudSessionListener, 'chat'>
  /** Clone and sync through VS Code's Git extension (§9.3). */
  git: CloudGitSync<vscode.Uri>
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
  /** Extension global state: per-session file hashes and the
   *  session → clone folder map. */
  storage: vscode.Memento
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
    files: mementoFilesStore(deps.storage),
    pickLocalFolder: (_sid, name) => pickLocalFolder(name),
    logger: deps.logger,
    listener: {
      chat: deps.emitChat,
      cloudEvent: (e) => {
        // Clone / Sync open up once the first turn is committed (§9.3);
        // replayed events count, so reopening a session works.
        if (e.event.type === 'git-committed') {
          void git.markCommitted(e.sessionId)
        }
        listener.cloudEvent?.(e)
      },
      state: (sid, s) => listener.state?.(sid, s),
      gone: (sid, err) => listener.gone?.(sid, err),
      progress: (e) => listener.progress?.(e),
    },
  })
  // A sign-out or account switch must not keep using the old token.
  const authSub = deps.auth.onDidChange(() => tokens.invalidate())

  const git = new CloudGitSync<vscode.Uri>({
    getGitApi: vscodeGitApi,
    apiUrl: () => (isCloudSessionsEnabled() ? cloudSessionsApiUrl() : ''),
    listSessions: async () => (await manager.list()).sessions,
    getAccessToken: () => tokens.get(),
    storage: deps.storage,
    parseUri: (url) => vscode.Uri.parse(url),
    fileUri: (fsPath) => vscode.Uri.file(fsPath),
    logger: deps.logger,
  })
  // The credentials and "Git: Clone" providers exist only while the
  // feature is on; they're (re)registered when the settings change.
  const syncGitRegistration = (): void => {
    if (!isCloudSessionsEnabled()) {
      git.unregister()
      return
    }
    void git.register().then((unavailable) => {
      if (unavailable) deps.logger.info(`cloud-sessions: ${unavailable}`)
    })
  }
  syncGitRegistration()
  const configSub = vscode.workspace.onDidChangeConfiguration((e) => {
    if (
      e.affectsConfiguration(CLOUD_SESSIONS_ENABLED_SETTING) ||
      e.affectsConfiguration(CLOUD_SESSIONS_API_URL_SETTING)
    ) {
      syncGitRegistration()
    }
  })

  return {
    manager,
    api,
    tokens,
    listener,
    git,
    isEnabled: isCloudSessionsEnabled,
    gatherSeed: (params) => gatherCloudSeed(params, deps.client, deps.logger),
    gatherPromptFiles: (params) =>
      gatherPromptFiles(params, deps.client, deps.logger),
    dispose: () => {
      authSub.dispose()
      configSub.dispose()
      git.unregister()
      manager.dispose()
    },
  }
}
