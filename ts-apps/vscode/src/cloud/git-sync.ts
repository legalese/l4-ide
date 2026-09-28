/**
 * Clone and sync a cloud session's files through VS Code's built-in Git
 * extension (spec §9.3). There is no git implementation here: the Git
 * extension runs the user's installed `git`, and this module only
 *
 * - answers the Git extension's credential requests for the Sessions API
 *   host with a fresh WorkOS access token (any username, the JWT as the
 *   password — §9.2);
 * - lists cloud sessions in VS Code's "Git: Clone" picker;
 * - clones with the Git API's `clone(url, { parentPath, postCloneAction:
 *   'none' })` and configures the clone: pushes go to `refs/heads/local`,
 *   no stored credential helper for the host, a 5 MB post buffer;
 * - syncs with `pull()` then `push()`, and reports ahead / behind.
 *
 * The Git API types are a structural subset of VS Code's `git.d.ts`
 * (API version 1), generic over the Uri type so this module has no
 * `vscode` import and can be unit-tested with fakes.
 */
import { ULID_RE, type SessionSummary } from '@repo/legalese-agent/protocol'

// ── Git extension API subset (git.d.ts, API version 1) ────────────────

export interface Disposable {
  dispose(): unknown
}

export type GitEvent<T> = (listener: (e: T) => unknown) => Disposable

export interface GitUri {
  readonly scheme: string
  readonly authority: string
  readonly path: string
  readonly fsPath: string
  toString(): string
}

export interface GitBranch {
  readonly name?: string
  readonly upstream?: { readonly remote: string; readonly name: string }
  readonly ahead?: number
  readonly behind?: number
}

export interface GitRemote {
  readonly name: string
  readonly fetchUrl?: string
  readonly pushUrl?: string
}

export interface GitRepository<U extends GitUri = GitUri> {
  readonly rootUri: U
  readonly state: {
    readonly HEAD: GitBranch | undefined
    readonly remotes: GitRemote[]
    readonly onDidChange: GitEvent<void>
  }
  getConfig(key: string): Promise<string>
  setConfig(key: string, value: string): Promise<string>
  pull(unshallow?: boolean): Promise<void>
  push(remoteName?: string, branchName?: string): Promise<void>
}

export interface GitCredentialsProvider<U extends GitUri = GitUri> {
  getCredentials(
    host: U
  ):
    | { username: string; password: string }
    | undefined
    | Promise<{ username: string; password: string } | undefined>
}

export interface GitRemoteSourceProvider {
  readonly name: string
  readonly icon?: string
  readonly supportsQuery?: boolean
  getRemoteSources(
    query?: string
  ): Promise<Array<{ name: string; description?: string; url: string }>>
}

export interface GitApi<U extends GitUri = GitUri> {
  readonly repositories: GitRepository<U>[]
  readonly onDidOpenRepository: GitEvent<GitRepository<U>>
  clone(
    uri: U,
    options?: { parentPath?: U; postCloneAction?: 'none' }
  ): Promise<U | null>
  openRepository(root: U): Promise<GitRepository<U> | null>
  registerCredentialsProvider(provider: GitCredentialsProvider<U>): Disposable
  registerRemoteSourceProvider(provider: GitRemoteSourceProvider): Disposable
}

/** The Git API, or why it can't be used. */
export type GitApiResult<U extends GitUri> =
  | { api: GitApi<U> }
  | { unavailable: string }

// ── Sync ──────────────────────────────────────────────────────────────

/** `http.postBuffer`: pushes go out as one request, not chunked (§9.3). */
export const GIT_POST_BUFFER = '5242880'
/** The push refspec: the user's `main` lands on the session's `local`. */
export const GIT_PUSH_REFSPEC = 'refs/heads/main:refs/heads/local'

export const CLONES_STORAGE_KEY = 'legaleseAi.cloudSessions.clones'

export interface CloneRecord {
  /** Absolute path of the clone. */
  folder: string
  /** A push succeeded; its commits wait in `local` until the harness
   *  merges them (pending while the session sleeps). */
  pushed?: boolean
}

export interface KeyValueStorage {
  get<T>(key: string): T | undefined
  update(key: string, value: unknown): PromiseLike<void>
}

export type SyncStatus =
  | { kind: 'unavailable'; message: string }
  | { kind: 'not-cloned' }
  | {
      kind: 'cloned'
      folder: string
      ahead: number
      behind: number
      /** Pushed commits not yet merged by the session (§9.3 "pending
       *  until the session runs" while it sleeps). */
      pending: boolean
    }

export class GitSyncError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'GitSyncError'
  }
}

export interface CloudGitSyncDeps<U extends GitUri> {
  getGitApi(): Promise<GitApiResult<U>>
  /** `legaleseAi.cloudSessions.apiUrl`; '' = off. */
  apiUrl(): string
  listSessions(): Promise<SessionSummary[]>
  getAccessToken(): Promise<string>
  storage: KeyValueStorage
  parseUri(url: string): U
  fileUri(fsPath: string): U
  logger: { info(m: string): void; warn(m: string): void }
}

/** The Sessions API host (`host[:port]`), or '' when unset/invalid. */
export function apiHost(apiUrl: string): string {
  try {
    return apiUrl.trim() ? new URL(apiUrl.trim()).host.toLowerCase() : ''
  } catch {
    return ''
  }
}

export function sessionGitUrl(apiUrl: string, sid: string): string {
  return `${apiUrl.trim().replace(/\/+$/, '')}/git/${sid}.git`
}

/** The session id in a Sessions API git URL, or undefined. */
export function sessionIdFromGitUrl(
  url: string | undefined,
  apiUrl: string
): string | undefined {
  if (!url) return undefined
  const prefix = `${apiUrl.trim().replace(/\/+$/, '')}/git/`
  if (!apiUrl.trim() || !url.startsWith(prefix)) return undefined
  const m = /^([0-9A-Z]{26})\.git\/?$/.exec(url.slice(prefix.length))
  return m && ULID_RE.test(m[1]!) ? m[1] : undefined
}

/** Turn a failed pull/push into a message a user can act on. */
export function describeGitError(err: unknown, op: 'pull' | 'push'): string {
  const text = err instanceof Error ? err.message : String(err)
  const detail = [
    text,
    (err as { stderr?: unknown })?.stderr,
    (err as { gitErrorCode?: unknown })?.gitErrorCode,
  ]
    .filter((x) => typeof x === 'string')
    .join('\n')
  if (
    /\b413\b|too_large|Request Entity Too Large|body.*too large/i.test(detail)
  ) {
    return 'This push is too large for a cloud session (about 4.5 MB per push). Push fewer or smaller changes at a time.'
  }
  if (/AuthenticationFailed|Authentication failed|\b401\b/i.test(detail)) {
    return 'Git could not authenticate to the cloud session. Sign in to Legalese Cloud and try again.'
  }
  if (/Conflict|CONFLICT|merge/i.test(detail) && op === 'pull') {
    return 'Pulling from the cloud session produced merge conflicts. Resolve them in the editor, commit, then sync again.'
  }
  return `Git ${op} failed: ${text}`
}

export class CloudGitSync<U extends GitUri> {
  private registrations: Disposable[] = []

  constructor(private readonly deps: CloudGitSyncDeps<U>) {}

  private clones(): Record<string, CloneRecord> {
    return (
      this.deps.storage.get<Record<string, CloneRecord>>(CLONES_STORAGE_KEY) ??
      {}
    )
  }

  private async saveClone(sid: string, rec: CloneRecord | undefined) {
    const next = { ...this.clones() }
    if (rec) next[sid] = rec
    else delete next[sid]
    await this.deps.storage.update(CLONES_STORAGE_KEY, next)
  }

  cloneOf(sid: string): CloneRecord | undefined {
    return this.clones()[sid]
  }

  /**
   * Register the credentials and remote-source providers, and configure
   * clones VS Code opens (also those made through "Git: Clone"). Returns
   * a message when the Git extension can't be used.
   */
  async register(): Promise<string | undefined> {
    this.unregister()
    const git = await this.deps.getGitApi()
    if ('unavailable' in git) return git.unavailable
    const { api } = git
    this.registrations.push(
      api.registerCredentialsProvider({
        getCredentials: async (host) => {
          const ours = apiHost(this.deps.apiUrl())
          if (!ours || host.authority.toLowerCase() !== ours) return undefined
          // Any username; the JWT is the password (§9.2). Fetched per
          // git operation, so an expired token is never reused.
          return {
            username: 'legalese',
            password: await this.deps.getAccessToken(),
          }
        },
      }),
      api.registerRemoteSourceProvider({
        name: 'Legalese Cloud sessions',
        icon: 'cloud',
        getRemoteSources: async () => {
          const apiUrl = this.deps.apiUrl()
          if (!apiUrl) return []
          const sessions = await this.deps.listSessions()
          return sessions.map((s) => ({
            name: s.title || s.sessionId,
            description: s.state,
            url: sessionGitUrl(apiUrl, s.sessionId),
          }))
        },
      }),
      api.onDidOpenRepository((repo) => {
        void this.adopt(repo).catch((err) =>
          this.deps.logger.warn(
            `cloud-sessions: could not configure clone: ${err instanceof Error ? err.message : String(err)}`
          )
        )
      })
    )
    for (const repo of api.repositories) void this.adopt(repo).catch(() => {})
    return undefined
  }

  unregister(): void {
    for (const d of this.registrations) d.dispose()
    this.registrations = []
  }

  /** A repository whose origin is a cloud session: configure it once
   *  and remember where it is. */
  private async adopt(repo: GitRepository<U>): Promise<void> {
    const origin = repo.state.remotes.find((r) => r.name === 'origin')
    const sid = sessionIdFromGitUrl(
      origin?.fetchUrl ?? origin?.pushUrl,
      this.deps.apiUrl()
    )
    if (!sid) return
    let push = ''
    try {
      push = await repo.getConfig('remote.origin.push')
    } catch {
      // unset: getConfig fails with exit code 1
    }
    if (push.trim() !== GIT_PUSH_REFSPEC) await this.configure(repo)
    const rec = this.cloneOf(sid)
    if (rec?.folder !== repo.rootUri.fsPath) {
      await this.saveClone(sid, { folder: repo.rootUri.fsPath })
    }
  }

  /** The three repository options of §9.3. */
  async configure(repo: GitRepository<U>): Promise<void> {
    const host = new URL(this.deps.apiUrl().trim())
    await repo.setConfig('remote.origin.push', GIT_PUSH_REFSPEC)
    // Empty helper list for this host: git asks VS Code every time
    // instead of reusing an expired token from the system keychain.
    await repo.setConfig(`credential.${host.protocol}//${host.host}.helper`, '')
    await repo.setConfig('http.postBuffer', GIT_POST_BUFFER)
  }

  private async api(): Promise<GitApi<U>> {
    const git = await this.deps.getGitApi()
    if ('unavailable' in git) throw new GitSyncError(git.unavailable)
    return git.api
  }

  private async repository(sid: string): Promise<GitRepository<U> | null> {
    const rec = this.cloneOf(sid)
    if (!rec) return null
    const api = await this.api()
    const uri = this.deps.fileUri(rec.folder)
    return (
      api.repositories.find((r) => r.rootUri.fsPath === rec.folder) ??
      (await api.openRepository(uri))
    )
  }

  /** Button state: Clone / Sync with ahead and behind (§9.3). */
  async status(sid: string): Promise<SyncStatus> {
    const git = await this.deps.getGitApi()
    if ('unavailable' in git) {
      return { kind: 'unavailable', message: git.unavailable }
    }
    const rec = this.cloneOf(sid)
    if (!rec) return { kind: 'not-cloned' }
    const repo = await this.repository(sid)
    if (!repo) {
      // The folder was deleted or moved: offer a fresh clone.
      await this.saveClone(sid, undefined)
      return { kind: 'not-cloned' }
    }
    const ahead = repo.state.HEAD?.ahead ?? 0
    const behind = repo.state.HEAD?.behind ?? 0
    return {
      kind: 'cloned',
      folder: rec.folder,
      ahead,
      behind,
      pending: Boolean(rec.pushed) && ahead > 0,
    }
  }

  /** Clone into `parentPath/<sid>` and configure it. Returns the folder. */
  async clone(sid: string, parentPath: U): Promise<U> {
    const apiUrl = this.deps.apiUrl()
    if (!apiUrl) throw new GitSyncError('Cloud sessions are not configured.')
    const api = await this.api()
    let folder: U | null
    try {
      folder = await api.clone(this.deps.parseUri(sessionGitUrl(apiUrl, sid)), {
        parentPath,
        postCloneAction: 'none',
      })
    } catch (err) {
      throw new GitSyncError(
        `Cloning the cloud session failed: ${err instanceof Error ? err.message : String(err)}`
      )
    }
    if (!folder)
      throw new GitSyncError('Cloning the cloud session was cancelled.')
    const repo = await api.openRepository(folder)
    if (!repo) {
      throw new GitSyncError('VS Code could not open the cloned repository.')
    }
    await this.configure(repo)
    await this.saveClone(sid, { folder: folder.fsPath })
    this.deps.logger.info(`cloud-sessions: cloned ${sid} to ${folder.fsPath}`)
    return folder
  }

  /** Pull, then push (§9.3). Conflicts are left for VS Code's merge editor. */
  async sync(sid: string): Promise<SyncStatus> {
    const repo = await this.repository(sid)
    if (!repo) throw new GitSyncError('Clone the cloud session first.')
    try {
      await repo.pull()
    } catch (err) {
      throw new GitSyncError(describeGitError(err, 'pull'))
    }
    if ((repo.state.HEAD?.ahead ?? 0) > 0) {
      try {
        await repo.push()
      } catch (err) {
        throw new GitSyncError(describeGitError(err, 'push'))
      }
      await this.saveClone(sid, { ...this.cloneOf(sid)!, pushed: true })
    }
    return this.status(sid)
  }
}
