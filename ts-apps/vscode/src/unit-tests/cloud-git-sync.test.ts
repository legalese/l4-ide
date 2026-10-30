import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import {
  CLONES_STORAGE_KEY,
  CloudGitSync,
  HISTORY_TOO_LARGE_MESSAGE,
  NOT_READY_MESSAGE,
  PUSH_TOO_LARGE_MESSAGE,
  GitSyncError,
  addGitEnvConfig,
  describeGitError,
  sessionGitUrl,
  sessionIdFromGitUrl,
  titleSlug,
  type CloudGitSyncDeps,
  type GitApi,
  type GitApiResult,
  type GitCredentialsProvider,
  type GitRemoteSourceProvider,
  type GitRepository,
  type GitUri,
} from '../cloud/git-sync.js'
import { SID } from './cloud-fakes.js'

const API = 'https://sessions.legalese.cloud/'

function uri(s: string): GitUri {
  const u = new URL(s)
  return {
    scheme: u.protocol.replace(':', ''),
    authority: u.host,
    path: u.pathname,
    fsPath: u.protocol === 'file:' ? decodeURIComponent(u.pathname) : '',
    toString: () => s,
  }
}
const fileUri = (p: string) => uri(`file://${p}`)

class FakeRepo implements GitRepository {
  config = new Map<string, string>()
  /** Every setConfig, in order. */
  sets: string[] = []
  /** A key whose first setConfig fails on the config lock. */
  lockOnce: string | undefined
  log: string[] = []
  pushError: Error | undefined
  head: { ahead: number; behind: number } = { ahead: 0, behind: 0 }
  constructor(
    readonly rootUri: GitUri,
    private readonly originUrl: string
  ) {}
  get state() {
    return {
      HEAD: { name: 'main', ...this.head },
      remotes: [{ name: 'origin', fetchUrl: this.originUrl }],
      onDidChange: () => ({ dispose() {} }),
    }
  }
  async getConfig(key: string) {
    const v = this.config.get(key)
    if (v === undefined) throw new Error('exit code 1')
    return v
  }
  async setConfig(key: string, value: string) {
    this.sets.push(key)
    if (key === this.lockOnce) {
      this.lockOnce = undefined
      throw Object.assign(new Error('Failed to execute git'), {
        stderr: 'error: could not lock config file .git/config: File exists',
      })
    }
    this.config.set(key, value)
    return ''
  }
  async pull() {
    this.log.push('pull')
    this.head = { ...this.head, behind: 0 }
  }
  async push() {
    this.log.push('push')
    if (this.pushError) throw this.pushError
  }
}

class FakeGit implements GitApi {
  git = { path: '/usr/bin/git' }
  repositories: FakeRepo[] = []
  /** As VS Code for a clone into an open workspace folder: the
   *  repository is opened later, on its own (`late`). */
  openLate = false
  late: FakeRepo | undefined
  /** `lockOnce` for the next clone's repository. */
  nextLock: string | undefined
  credentials: GitCredentialsProvider | undefined
  sources: GitRemoteSourceProvider | undefined
  openListeners: Array<(r: GitRepository) => unknown> = []
  cloned: Array<{ url: string; parent?: string; action?: string }> = []
  /** The environment git would run the clone with. */
  envAtClone: Record<string, string | undefined> | undefined
  env: Record<string, string | undefined> = {}
  cloneError: Error | undefined
  onDidOpenRepository = (l: (r: GitRepository) => unknown) => {
    this.openListeners.push(l)
    return { dispose: () => {} }
  }
  async clone(
    u: GitUri,
    o?: { parentPath?: GitUri; postCloneAction?: 'none' }
  ) {
    this.cloned.push({
      url: u.toString(),
      parent: o?.parentPath?.fsPath,
      action: o?.postCloneAction,
    })
    this.envAtClone = { ...this.env }
    if (this.cloneError) throw this.cloneError
    // As VS Code: the folder is named after the URL's last segment.
    const name = u
      .toString()
      .replace(/^.*\//, '')
      .replace(/\.git$/, '')
    const folder = fileUri(`${o?.parentPath?.fsPath}/${name}`)
    const repo = new FakeRepo(folder, u.toString())
    repo.lockOnce = this.nextLock
    if (this.openLate) this.late = repo
    else this.repositories.push(repo)
    return folder
  }
  async openRepository(root: GitUri) {
    return (
      this.repositories.find((r) => r.rootUri.fsPath === root.fsPath) ?? null
    )
  }
  registerCredentialsProvider(p: GitCredentialsProvider) {
    this.credentials = p
    return { dispose: () => (this.credentials = undefined) }
  }
  registerRemoteSourceProvider(p: GitRemoteSourceProvider) {
    this.sources = p
    return { dispose: () => (this.sources = undefined) }
  }
}

function setup(
  result?: GitApiResult<GitUri>,
  listSessions?: CloudGitSyncDeps<GitUri>['listSessions'],
  extra: Partial<CloudGitSyncDeps<GitUri>> = {}
) {
  const git = new FakeGit()
  const store = new Map<string, unknown>()
  const sync = new CloudGitSync<GitUri>({
    getGitApi: async () => result ?? { api: git },
    apiUrl: () => API,
    listSessions:
      listSessions ??
      (async () => [
        {
          sessionId: SID,
          title: 'Lease review',
          created: 1,
          lastActivity: 2,
          state: 'sleeping',
        },
      ]),
    getAccessToken: async () => 'jwt-fresh',
    storage: {
      get: <T>(k: string) => store.get(k) as T | undefined,
      update: async (k, v) => {
        store.set(k, v)
      },
    },
    parseUri: uri,
    fileUri,
    logger: { info() {}, warn() {} },
    gitEnv: git.env,
    ...extra,
  })
  return { git, sync, store }
}

describe('CloudGitSync', () => {
  test('says so when the Git extension is unavailable', async () => {
    const { sync } = setup({ unavailable: 'no git' })
    assert.equal(await sync.register(), 'no git')
    assert.deepEqual(await sync.status(SID), {
      kind: 'unavailable',
      message: 'no git',
    })
    await assert.rejects(sync.clone(SID, fileUri('/tmp')), GitSyncError)
  })

  test('answers credentials only for the Sessions API host', async () => {
    const { git, sync } = setup()
    await sync.register()
    assert.deepEqual(
      await git.credentials!.getCredentials(
        uri('https://sessions.legalese.cloud')
      ),
      { username: 'legalese', password: 'jwt-fresh' }
    )
    assert.equal(
      await git.credentials!.getCredentials(uri('https://github.com')),
      undefined
    )
    // Not in cleartext, even to the right host.
    assert.equal(
      await git.credentials!.getCredentials(
        uri('http://sessions.legalese.cloud')
      ),
      undefined
    )
    sync.unregister()
    assert.equal(git.credentials, undefined)
  })

  test('lists committed cloud sessions in the Git: Clone picker', async () => {
    const { git, sync } = setup()
    await sync.register()
    // Before the first turn is committed: not offered.
    assert.deepEqual(await git.sources!.getRemoteSources(), [])
    await sync.markCommitted(SID)
    assert.deepEqual(await git.sources!.getRemoteSources(), [
      {
        name: 'Lease review',
        description: 'sleeping',
        url: `https://sessions.legalese.cloud/git/${SID}/Lease-review.git`,
      },
    ])
  })

  test('clones without opening, configures, and remembers the folder', async () => {
    const { git, sync, store } = setup()
    await sync.markCommitted(SID)
    const folder = await sync.clone(SID, fileUri('/home/u/src'))
    // Named after the session title.
    assert.equal(folder.fsPath, '/home/u/src/Lease-review')
    assert.deepEqual(git.cloned, [
      {
        url: `https://sessions.legalese.cloud/git/${SID}/Lease-review.git`,
        parent: '/home/u/src',
        action: 'none',
      },
    ])
    assert.deepEqual(Object.fromEntries(git.repositories[0]!.config), {
      'remote.origin.push': 'refs/heads/main:refs/heads/local',
      'credential.https://sessions.legalese.cloud.helper': '',
      'http.proactiveAuth': 'basic',
      'http.postBuffer': '5242880',
    })
    assert.deepEqual(store.get(CLONES_STORAGE_KEY), {
      [SID]: { folder: '/home/u/src/Lease-review' },
    })
    assert.deepEqual(await sync.status(SID), {
      kind: 'cloned',
      folder: '/home/u/src/Lease-review',
      ahead: 0,
      behind: 0,
      pending: false,
    })
  })

  test('clones under the session id when its title is unknown', async () => {
    const { git, sync } = setup(undefined, async () => {
      throw new Error('offline')
    })
    await sync.markCommitted(SID)
    const folder = await sync.clone(SID, fileUri('/w'))
    assert.equal(folder.fsPath, `/w/${SID}`)
    assert.equal(
      git.cloned[0]!.url,
      `https://sessions.legalese.cloud/git/${SID}.git`
    )
  })

  test('waits for the Git extension to open a fresh clone itself', async () => {
    const { git, sync } = setup()
    git.openLate = true
    await sync.markCommitted(SID)
    const cloning = sync.clone(SID, fileUri('/w'))
    await new Promise((r) => setImmediate(r))
    // openRepository answered null; the Git extension opens it now.
    const repo = git.late!
    git.repositories.push(repo)
    for (const l of git.openListeners) l(repo)
    assert.equal((await cloning).fsPath, '/w/Lease-review')
    assert.equal(repo.config.get('http.proactiveAuth'), 'basic')
  })

  test('gives up when the clone never opens', async () => {
    const { git, sync } = setup(undefined, undefined, { openWaitMs: 5 })
    git.openLate = true
    await sync.markCommitted(SID)
    await assert.rejects(
      sync.clone(SID, fileUri('/w')),
      /could not open the cloned repository/
    )
  })

  test('configures a fresh clone once, also when VS Code opens it meanwhile', async () => {
    const { git, sync } = setup()
    await sync.register()
    git.openLate = true
    await sync.markCommitted(SID)
    const cloning = sync.clone(SID, fileUri('/w'))
    await new Promise((r) => setImmediate(r))
    const repo = git.late!
    git.repositories.push(repo)
    // Both our adopt() and the clone configure it.
    for (const l of git.openListeners) l(repo)
    await cloning
    await new Promise((r) => setImmediate(r))
    assert.deepEqual(repo.sets, [
      'remote.origin.push',
      'credential.https://sessions.legalese.cloud.helper',
      'http.proactiveAuth',
      'http.postBuffer',
    ])
  })

  test('writes the empty credential helper with git itself', async () => {
    const written: string[][] = []
    const { git, sync } = setup(undefined, undefined, {
      writeConfig: async (gitPath, folder, key, value) => {
        written.push([gitPath, folder, key, value])
      },
    })
    await sync.markCommitted(SID)
    await sync.clone(SID, fileUri('/w'))
    // The Git API's setConfig would drop the empty value.
    assert.deepEqual(written, [
      [
        '/usr/bin/git',
        '/w/Lease-review',
        'credential.https://sessions.legalese.cloud.helper',
        '',
      ],
    ])
    assert.ok(
      !git.repositories[0]!.sets.includes(
        'credential.https://sessions.legalese.cloud.helper'
      )
    )
  })

  test('waits out the config lock of the Git extension', async () => {
    const { git, sync } = setup()
    // Locked once while VS Code writes its own branch config.
    git.nextLock = 'http.postBuffer'
    await sync.markCommitted(SID)
    await sync.clone(SID, fileUri('/w'))
    const repo = git.repositories[0]!
    assert.equal(repo.config.get('http.postBuffer'), '5242880')
    assert.equal(repo.sets.filter((k) => k === 'http.postBuffer').length, 2)
  })

  test('sync pulls then pushes, and reports a pending push', async () => {
    const { git, sync } = setup()
    await sync.markCommitted(SID)
    await sync.clone(SID, fileUri('/w'))
    const repo = git.repositories[0]!
    repo.head = { ahead: 2, behind: 1 }
    const status = await sync.sync(SID)
    assert.deepEqual(repo.log, ['pull', 'push'])
    assert.deepEqual(status, {
      kind: 'cloned',
      folder: '/w/Lease-review',
      ahead: 2,
      behind: 0,
      pending: true,
    })
    // Nothing to push: pull only.
    repo.log = []
    repo.head = { ahead: 0, behind: 0 }
    await sync.sync(SID)
    assert.deepEqual(repo.log, ['pull'])
  })

  test('the first clone already keeps the token out of the keychain', async () => {
    const { git, sync } = setup()
    git.env.GIT_CONFIG_COUNT = '1'
    git.env.GIT_CONFIG_KEY_0 = 'user.name'
    git.env.GIT_CONFIG_VALUE_0 = 'Someone'
    await sync.markCommitted(SID)
    await sync.clone(SID, fileUri('/w'))
    // Set before git ran: the user's own entry kept, ours appended.
    assert.deepEqual(git.envAtClone, {
      GIT_CONFIG_COUNT: '3',
      GIT_CONFIG_KEY_0: 'user.name',
      GIT_CONFIG_VALUE_0: 'Someone',
      GIT_CONFIG_KEY_1: 'credential.https://sessions.legalese.cloud.helper',
      GIT_CONFIG_VALUE_1: '',
      GIT_CONFIG_KEY_2: 'http.https://sessions.legalese.cloud/.proactiveAuth',
      GIT_CONFIG_VALUE_2: 'basic',
    })
    // Once only, also across registrations (for Git: Clone).
    await sync.register()
    git.repositories = []
    await sync.clone(SID, fileUri('/v'))
    assert.equal(git.env.GIT_CONFIG_COUNT, '3')
  })

  test('registering sets it for clones made through Git: Clone', async () => {
    const { git, sync } = setup()
    await sync.register()
    assert.deepEqual(git.env, {
      GIT_CONFIG_COUNT: '2',
      GIT_CONFIG_KEY_0: 'credential.https://sessions.legalese.cloud.helper',
      GIT_CONFIG_VALUE_0: '',
      GIT_CONFIG_KEY_1: 'http.https://sessions.legalese.cloud/.proactiveAuth',
      GIT_CONFIG_VALUE_1: 'basic',
    })
  })

  test('a clone or pull over the response limit gets the beta limit', async () => {
    const tooLarge = () =>
      Object.assign(new Error('Failed to execute git'), {
        stderr:
          'error: RPC failed; HTTP 413 curl 22 The requested URL returned error: 413',
      })
    const { git, sync } = setup()
    await sync.markCommitted(SID)
    git.cloneError = tooLarge()
    await assert.rejects(
      sync.clone(SID, fileUri('/w')),
      (err: Error) => err.message === HISTORY_TOO_LARGE_MESSAGE
    )
    git.cloneError = undefined
    await sync.clone(SID, fileUri('/w'))
    const repo = git.repositories[0]!
    repo.pull = async () => {
      throw tooLarge()
    }
    await assert.rejects(
      sync.sync(SID),
      (err: Error) => err.message === HISTORY_TOO_LARGE_MESSAGE
    )
    assert.match(
      HISTORY_TOO_LARGE_MESSAGE,
      /history is too large to clone or pull during the beta/
    )
  })

  test('a push over the body limit gets a clear message', async () => {
    const { git, sync } = setup()
    await sync.markCommitted(SID)
    await sync.clone(SID, fileUri('/w'))
    const repo = git.repositories[0]!
    repo.head = { ahead: 1, behind: 0 }
    repo.pushError = Object.assign(new Error('Failed to execute git'), {
      stderr:
        'error: RPC failed; HTTP 413 curl 22 The requested URL returned error: 413',
    })
    await assert.rejects(
      sync.sync(SID),
      (err: Error) => err.message === PUSH_TOO_LARGE_MESSAGE
    )
  })

  test('configures clones made through Git: Clone', async () => {
    const { git, sync, store } = setup()
    await sync.register()
    const repo = new FakeRepo(
      fileUri('/x/lease'),
      `https://sessions.legalese.cloud/git/${SID}.git`
    )
    for (const l of git.openListeners) l(repo)
    await new Promise((r) => setImmediate(r))
    assert.equal(
      repo.config.get('remote.origin.push'),
      'refs/heads/main:refs/heads/local'
    )
    assert.deepEqual(store.get(CLONES_STORAGE_KEY), {
      [SID]: { folder: '/x/lease' },
    })
    // Other repositories are left alone.
    const other = new FakeRepo(fileUri('/y'), 'https://github.com/a/b.git')
    for (const l of git.openListeners) l(other)
    await new Promise((r) => setImmediate(r))
    assert.equal(other.config.size, 0)
  })
})

describe('Clone and Sync wait for the first commit (§9.3)', () => {
  test('status, clone, sync and credentials refuse before it', async () => {
    const { git, sync } = setup()
    await sync.register()
    assert.deepEqual(await sync.status(SID), {
      kind: 'not-ready',
      message: NOT_READY_MESSAGE,
    })
    await assert.rejects(sync.clone(SID, fileUri('/w')), (err: Error) =>
      err.message.startsWith('Available after the first turn')
    )
    await assert.rejects(sync.sync(SID), (err: Error) =>
      err.message.startsWith('Available after the first turn')
    )
    assert.deepEqual(git.cloned, [])
    // A credential request naming the session is refused; a bare host
    // (what VS Code usually passes) still gets a token.
    assert.equal(
      await git.credentials!.getCredentials(
        uri(`https://sessions.legalese.cloud/git/${SID}.git`)
      ),
      undefined
    )
    assert.ok(
      await git.credentials!.getCredentials(
        uri('https://sessions.legalese.cloud')
      )
    )

    await sync.markCommitted(SID)
    assert.deepEqual(await sync.status(SID), { kind: 'not-cloned' })
    assert.ok(
      await git.credentials!.getCredentials(
        uri(`https://sessions.legalese.cloud/git/${SID}.git`)
      )
    )
  })
})

describe('git helpers', () => {
  test('session id from a git URL', () => {
    assert.equal(
      sessionIdFromGitUrl(
        `https://sessions.legalese.cloud/git/${SID}.git`,
        API
      ),
      SID
    )
    assert.equal(
      sessionIdFromGitUrl(
        `https://sessions.legalese.cloud/git/${SID}/Lease-review.git`,
        API
      ),
      SID
    )
    assert.equal(
      sessionIdFromGitUrl(`https://other.example/git/${SID}.git`, API),
      undefined
    )
    assert.equal(
      sessionIdFromGitUrl('https://sessions.legalese.cloud/git/nope.git', API),
      undefined
    )
    assert.equal(
      sessionIdFromGitUrl(`https://sessions.legalese.cloud/git/${SID}.git`, ''),
      undefined
    )
  })

  test('a title names the clone folder through the git URL', () => {
    assert.equal(titleSlug('Lease review'), 'Lease-review')
    assert.equal(titleSlug('Révision du bail: §3 / §4'), 'Revision-du-bail-3-4')
    assert.equal(titleSlug('..hidden..'), 'hidden')
    assert.equal(titleSlug('漢字'), '')
    assert.equal(titleSlug(undefined), '')
    assert.equal(titleSlug('x'.repeat(80)).length, 60)
    // Long titles end at a word.
    assert.equal(
      titleSlug(
        'Update this L4 file to work the same but read a lot more like the act'
      ),
      'Update-this-L4-file-to-work-the-same-but-read-a-lot-more'
    )
    assert.equal(
      sessionGitUrl(API, SID, 'Lease review'),
      `https://sessions.legalese.cloud/git/${SID}/Lease-review.git`
    )
    assert.equal(
      sessionGitUrl(API, SID, '漢字'),
      `https://sessions.legalese.cloud/git/${SID}.git`
    )
  })

  test('409 no_commits_yet from the Sessions API reads as not ready', () => {
    for (const op of ['pull', 'push', 'clone'] as const) {
      assert.equal(
        describeGitError(
          Object.assign(new Error('Failed to execute git'), {
            stderr:
              'fatal: unable to access: The requested URL returned error: 409',
          }),
          op
        ),
        NOT_READY_MESSAGE
      )
    }
    assert.equal(
      describeGitError(new Error('remote: no_commits_yet'), 'clone'),
      NOT_READY_MESSAGE
    )
  })

  test('env config: appends, once, and leaves a malformed count alone', () => {
    const env: Record<string, string | undefined> = {}
    addGitEnvConfig(env, 'a.b', '')
    addGitEnvConfig(env, 'a.b', '')
    addGitEnvConfig(env, 'c.d', 'x')
    assert.deepEqual(env, {
      GIT_CONFIG_COUNT: '2',
      GIT_CONFIG_KEY_0: 'a.b',
      GIT_CONFIG_VALUE_0: '',
      GIT_CONFIG_KEY_1: 'c.d',
      GIT_CONFIG_VALUE_1: 'x',
    })
    const bogus: Record<string, string | undefined> = { GIT_CONFIG_COUNT: 'x' }
    addGitEnvConfig(bogus, 'a.b', '')
    assert.deepEqual(bogus, { GIT_CONFIG_COUNT: 'x' })
  })

  test('auth failures point at signing in', () => {
    assert.match(
      describeGitError(
        Object.assign(new Error('x'), { gitErrorCode: 'AuthenticationFailed' }),
        'pull'
      ),
      /Sign in to Legalese Cloud/
    )
  })
})
