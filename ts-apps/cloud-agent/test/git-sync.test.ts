import { afterEach, beforeEach, describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { chmod, mkdir, readFile, stat, writeFile } from 'node:fs/promises'
import * as path from 'node:path'
import type { CloudEventPayload } from '@repo/legalese-agent/protocol'
import { GitSync, commitSubject } from '../src/git-sync.js'
import type { RunnerContext } from '../src/runner.js'
import { HOST_PATH, MemoryLogger, SID, StubL4, tempDir } from './helpers.js'

const BUNDLE = '01J9Z3K4M5N6P7Q8R9S0T1V2W4.bundle'

function sh(cwd: string, ...args: string[]): string {
  return execFileSync('git', args, {
    cwd,
    encoding: 'utf8',
    env: {
      PATH: HOST_PATH,
      HOME: cwd,
      GIT_CONFIG_NOSYSTEM: '1',
      GIT_AUTHOR_NAME: 'User',
      GIT_AUTHOR_EMAIL: 'user@example.com',
      GIT_COMMITTER_NAME: 'User',
      GIT_COMMITTER_EMAIL: 'user@example.com',
    },
  }).trim()
}

describe('GitSync', () => {
  let dir: string
  let cleanup: () => Promise<void>
  let repo: string
  let stateDir: string
  let events: CloudEventPayload[]
  let changed: string[][]
  let ctx: RunnerContext
  let logger: MemoryLogger

  beforeEach(async () => {
    ;({ dir, cleanup } = await tempDir())
    const sessionDir = path.join(dir, 'sessions', SID)
    repo = path.join(sessionDir, 'repo')
    stateDir = path.join(sessionDir, 'state')
    await mkdir(repo, { recursive: true })
    await mkdir(path.join(stateDir, 'git', 'incoming'), { recursive: true })
    events = []
    changed = []
    logger = new MemoryLogger()
    ctx = {
      sessionId: SID,
      sessionDir,
      repoDir: repo,
      stateDir,
      logger,
      l4: new StubL4(),
      emit: (p) => events.push(p),
      announceState: () => undefined,
      providers: [],
      filesChanged: async (paths) => {
        changed.push(paths)
      },
    }
  })
  afterEach(() => cleanup())

  const git = (): GitSync => new GitSync({ PATH: HOST_PATH })
  const write = (rel: string, text: string): Promise<void> =>
    mkdir(path.dirname(path.join(repo, rel)), { recursive: true }).then(() =>
      writeFile(path.join(repo, rel), text)
    )
  const read = (rel: string): Promise<string> =>
    readFile(path.join(repo, rel), 'utf8')
  const bundlePath = (): string => path.join(stateDir, 'git', 'main.bundle')

  /** Clone main.bundle the way a client would get it. */
  function cloneBundle(): string {
    const client = path.join(dir, 'client')
    sh(dir, 'clone', '-q', '-b', 'main', bundlePath(), client)
    return client
  }

  test('initialises, commits the seed and writes main.bundle', async () => {
    await write('rules.l4', 'DECIDE x IS 1\n')
    const g = git()
    await g.start(ctx)
    assert.equal(sh(repo, 'log', '--format=%s'), 'Seed')
    assert.equal(sh(repo, 'ls-files'), 'rules.l4')
    assert.ok((await stat(bundlePath())).size > 0)
    const client = cloneBundle()
    assert.equal(
      await readFile(path.join(client, 'rules.l4'), 'utf8'),
      'DECIDE x IS 1\n'
    )
    // A second start doesn't commit again.
    await git().start(ctx)
    assert.equal(sh(repo, 'rev-list', '--count', 'HEAD'), '1')
  })

  test('commits each turn with a Turn-Id trailer and reports it', async () => {
    const g = git()
    await g.start(ctx)
    const seed = sh(repo, 'rev-parse', 'HEAD')
    await write('a.l4', 'one\n')
    await g.afterTurn({
      turnId: 'turn-1',
      prompt: '\n  Write a rule\nwith details',
    })
    const sha = sh(repo, 'rev-parse', 'HEAD')
    assert.deepEqual(events, [
      { type: 'git-committed', turnId: 'turn-1', sha, parent: seed },
    ])
    assert.equal(sh(repo, 'log', '-1', '--format=%s'), 'Write a rule')
    assert.equal(
      sh(repo, 'log', '-1', '--format=%(trailers:key=Turn-Id,valueonly)'),
      'turn-1'
    )
    // The bundle follows.
    const client = cloneBundle()
    assert.equal(sh(client, 'rev-parse', 'HEAD'), sha)
    // No changes, no commit.
    await g.afterTurn({ turnId: 'turn-2', prompt: 'nothing' })
    assert.equal(events.length, 1)
  })

  test('never runs repository hooks', async () => {
    const g = git()
    await g.start(ctx)
    const hook = path.join(repo, '.git', 'hooks', 'pre-commit')
    await mkdir(path.dirname(hook), { recursive: true })
    await writeFile(
      hook,
      `#!/bin/sh\ntouch "${path.join(dir, 'pwned')}"\nexit 1\n`
    )
    await chmod(hook, 0o755)
    await write('a.l4', 'x\n')
    await g.afterTurn({ turnId: 't1', prompt: 'p' })
    assert.equal(events.length, 1)
    await assert.rejects(stat(path.join(dir, 'pwned')))
  })

  test('rolls back the last turn and an earlier one without rewriting history', async () => {
    const g = git()
    await write('a.l4', 'v0\n')
    await g.start(ctx)
    await write('a.l4', 'v1\n')
    await g.afterTurn({ turnId: 't1', prompt: 'First' })
    await write('a.l4', 'v2\n')
    await write('b.l4', 'new in t2\n')
    await g.afterTurn({ turnId: 't2', prompt: 'Second' })
    const beforeRollback = sh(repo, 'rev-parse', 'HEAD')

    await g.handleCommand({ id: 1, ts: 1, type: 'rollback', turnId: 't2' })
    assert.equal(await read('a.l4'), 'v1\n')
    await assert.rejects(stat(path.join(repo, 'b.l4')))
    const rb = events.at(-1) as { type: string; turnId: string; sha: string }
    assert.equal(rb.type, 'rolled-back')
    assert.equal(rb.turnId, 't2')
    assert.equal(rb.sha, sh(repo, 'rev-parse', 'HEAD'))
    assert.equal(sh(repo, 'log', '-1', '--format=%s'), 'Roll back: Second')
    // History kept: the rolled-back commit is an ancestor.
    assert.equal(
      sh(repo, 'merge-base', '--is-ancestor', beforeRollback, 'HEAD'),
      ''
    )
    assert.ok(changed.at(-1)!.some((p) => p.endsWith('b.l4')))

    // The next prompt hears about it, once.
    assert.match((await g.beforeTurn()) ?? '', /"t2"/)
    assert.equal(await g.beforeTurn(), undefined)

    // Restore to before t1 undoes everything after it.
    await g.handleCommand({ id: 2, ts: 1, type: 'rollback', turnId: 't1' })
    assert.equal(await read('a.l4'), 'v0\n')
    assert.equal(sh(repo, 'status', '--porcelain'), '')

    // A turn without a commit: nothing happens.
    const n = events.length
    await g.handleCommand({ id: 3, ts: 1, type: 'rollback', turnId: 'nope' })
    assert.equal(events.length, n)
  })

  test('merges an incoming local bundle', async () => {
    const g = git()
    await write('a.l4', 'line 1\nline 2\n')
    await g.start(ctx)
    const client = cloneBundle()
    sh(client, 'checkout', '-q', '-b', 'local')
    await writeFile(path.join(client, 'c.l4'), 'from the user\n')
    sh(client, 'add', '-A')
    sh(client, 'commit', '-q', '-m', 'User change')
    sh(
      client,
      'bundle',
      'create',
      '-q',
      path.join(stateDir, 'git', 'incoming', BUNDLE),
      'local',
      '^main'
    )
    // Meanwhile the agent changed something else.
    await write('b.l4', 'agent\n')
    await g.afterTurn({ turnId: 't1', prompt: 'Agent work' })

    await g.handleCommand({ id: 1, ts: 1, type: 'apply-bundle', file: BUNDLE })
    assert.equal(await read('c.l4'), 'from the user\n')
    assert.equal(await read('b.l4'), 'agent\n')
    const merged = events.at(-1) as { type: string; sha: string }
    assert.equal(merged.type, 'local-merged')
    assert.equal(merged.sha, sh(repo, 'rev-parse', 'HEAD'))
    assert.equal(sh(repo, 'for-each-ref', 'refs/incoming'), '')
    // The client can pull it back.
    sh(client, 'fetch', '-q', bundlePath(), 'main:refs/remotes/origin/main')
    assert.equal(
      sh(client, 'rev-parse', 'refs/remotes/origin/main'),
      merged.sha
    )
  })

  test('aborts a conflicting merge and reports the files', async () => {
    const g = git()
    await write('a.l4', 'line 1\n')
    await g.start(ctx)
    const client = cloneBundle()
    sh(client, 'checkout', '-q', '-b', 'local')
    await writeFile(path.join(client, 'a.l4'), 'user version\n')
    sh(client, 'commit', '-q', '-am', 'User change')
    sh(
      client,
      'bundle',
      'create',
      '-q',
      path.join(stateDir, 'git', 'incoming', BUNDLE),
      'local',
      '^main'
    )
    await write('a.l4', 'agent version\n')
    await g.afterTurn({ turnId: 't1', prompt: 'Agent' })
    const head = sh(repo, 'rev-parse', 'HEAD')

    await g.handleCommand({ id: 1, ts: 1, type: 'apply-bundle', file: BUNDLE })
    assert.deepEqual(events.at(-1), {
      type: 'local-merge-conflict',
      files: ['a.l4'],
    })
    assert.equal(sh(repo, 'rev-parse', 'HEAD'), head)
    assert.equal(sh(repo, 'status', '--porcelain'), '')
    assert.equal(await read('a.l4'), 'agent version\n')
  })

  test('skips missing and bogus bundles', async () => {
    const g = git()
    await g.start(ctx)
    await g.handleCommand({ id: 1, ts: 1, type: 'apply-bundle', file: BUNDLE })
    await writeFile(
      path.join(stateDir, 'git', 'incoming', BUNDLE),
      'not a bundle'
    )
    await g.handleCommand({ id: 2, ts: 1, type: 'apply-bundle', file: BUNDLE })
    assert.deepEqual(events, [])
    assert.ok(logger.has('warn', /missing/))
    assert.ok(logger.has('warn', /fetching incoming bundle/))
  })

  test('commits leftovers and runs gc before sleeping', async () => {
    const g = git()
    await g.start(ctx)
    await write('late.l4', 'x\n')
    await g.beforeExit('idle')
    assert.equal(
      sh(repo, 'log', '-1', '--format=%s'),
      'Checkpoint before sleep'
    )
    assert.equal(sh(repo, 'status', '--porcelain'), '')
  })
})

describe('commitSubject', () => {
  test('uses the first non-empty line, capped at 72 characters', () => {
    assert.equal(commitSubject('\n\n  hi there \nmore', 'x'), 'hi there')
    assert.equal(commitSubject('   ', 'fallback'), 'fallback')
    assert.equal(commitSubject('a'.repeat(100), 'x').length, 72)
  })
})
