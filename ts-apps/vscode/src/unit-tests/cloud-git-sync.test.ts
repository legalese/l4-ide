import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import {
  CLONES_STORAGE_KEY,
  CloudGitSync,
  NOT_READY_MESSAGE,
  GitSyncError,
  describeGitError,
  sessionIdFromGitUrl,
  type GitApi,
  type GitApiResult,
  type GitCredentialsProvider,
  type GitRemoteSourceProvider,
  type GitRepository,
  type GitUri,
} from '../cloud/git-sync.js'
import { SID } from './cloud-fakes.js'

const API = 'https://sessions.example/'

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
  repositories: FakeRepo[] = []
  credentials: GitCredentialsProvider | undefined
  sources: GitRemoteSourceProvider | undefined
  openListeners: Array<(r: GitRepository) => unknown> = []
  cloned: Array<{ url: string; parent?: string; action?: string }> = []
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
    const folder = fileUri(`${o?.parentPath?.fsPath}/${SID}`)
    this.repositories.push(new FakeRepo(folder, u.toString()))
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

function setup(result?: GitApiResult<GitUri>) {
  const git = new FakeGit()
  const store = new Map<string, unknown>()
  const sync = new CloudGitSync<GitUri>({
    getGitApi: async () => result ?? { api: git },
    apiUrl: () => API,
    listSessions: async () => [
      {
        sessionId: SID,
        title: 'Lease review',
        created: 1,
        lastActivity: 2,
        state: 'sleeping',
      },
    ],
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
      await git.credentials!.getCredentials(uri('https://sessions.example')),
      { username: 'legalese', password: 'jwt-fresh' }
    )
    assert.equal(
      await git.credentials!.getCredentials(uri('https://github.com')),
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
        url: `https://sessions.example/git/${SID}.git`,
      },
    ])
  })

  test('clones without opening, configures, and remembers the folder', async () => {
    const { git, sync, store } = setup()
    await sync.markCommitted(SID)
    const folder = await sync.clone(SID, fileUri('/home/u/src'))
    assert.equal(folder.fsPath, `/home/u/src/${SID}`)
    assert.deepEqual(git.cloned, [
      {
        url: `https://sessions.example/git/${SID}.git`,
        parent: '/home/u/src',
        action: 'none',
      },
    ])
    assert.deepEqual(Object.fromEntries(git.repositories[0]!.config), {
      'remote.origin.push': 'refs/heads/main:refs/heads/local',
      'credential.https://sessions.example.helper': '',
      'http.postBuffer': '5242880',
    })
    assert.deepEqual(store.get(CLONES_STORAGE_KEY), {
      [SID]: { folder: `/home/u/src/${SID}` },
    })
    assert.deepEqual(await sync.status(SID), {
      kind: 'cloned',
      folder: `/home/u/src/${SID}`,
      ahead: 0,
      behind: 0,
      pending: false,
    })
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
      folder: `/w/${SID}`,
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
    await assert.rejects(sync.sync(SID), /too large for a cloud session/)
  })

  test('configures clones made through Git: Clone', async () => {
    const { git, sync, store } = setup()
    await sync.register()
    const repo = new FakeRepo(
      fileUri('/x/lease'),
      `https://sessions.example/git/${SID}.git`
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
        uri(`https://sessions.example/git/${SID}.git`)
      ),
      undefined
    )
    assert.ok(
      await git.credentials!.getCredentials(uri('https://sessions.example'))
    )

    await sync.markCommitted(SID)
    assert.deepEqual(await sync.status(SID), { kind: 'not-cloned' })
    assert.ok(
      await git.credentials!.getCredentials(
        uri(`https://sessions.example/git/${SID}.git`)
      )
    )
  })
})

describe('git helpers', () => {
  test('session id from a git URL', () => {
    assert.equal(
      sessionIdFromGitUrl(`https://sessions.example/git/${SID}.git`, API),
      SID
    )
    assert.equal(
      sessionIdFromGitUrl(`https://other.example/git/${SID}.git`, API),
      undefined
    )
    assert.equal(
      sessionIdFromGitUrl('https://sessions.example/git/nope.git', API),
      undefined
    )
    assert.equal(
      sessionIdFromGitUrl(`https://sessions.example/git/${SID}.git`, ''),
      undefined
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
