import { afterEach, beforeEach, describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { chmod, mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises'
import * as path from 'node:path'
import type { CloudEventPayload } from '@repo/legalese-agent/protocol'
import {
  GitSync,
  commitSubject,
  sanitizeSubject,
  summaryMessages,
} from '../src/git-sync.js'
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
  /** The fake summize pipeline; `null` = no summary (the default). */
  let summize: RunnerContext['summize']
  let summizeCalls: Array<{
    messages: Array<{ role: string; content: string }>
    signal?: AbortSignal
  }>

  beforeEach(async () => {
    summize = async () => null
    summizeCalls = []
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
      summize: (messages, o) => {
        summizeCalls.push({ messages, signal: o?.signal })
        return summize(messages, o)
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
    // No summary available: the prompt's first line is the subject.
    assert.deepEqual(events, [
      {
        type: 'git-committed',
        turnId: 'turn-1',
        sha,
        parent: seed,
        summary: 'Write a rule',
      },
    ])
    assert.equal(sh(repo, 'log', '-1', '--format=%s'), 'Write a rule')
    assert.equal(
      sh(repo, 'log', '-1', '--format=%B'),
      'Write a rule\n\nPrompt: Write a rule\n\nTurn-Id: turn-1'
    )
    assert.equal(
      sh(repo, 'log', '-1', '--format=%(trailers:key=Turn-Id,valueonly)'),
      'turn-1'
    )
    // The bundle follows.
    const client = cloneBundle()
    assert.equal(sh(client, 'rev-parse', 'HEAD'), sha)
    // No changes, no commit — and no summary is asked for.
    const asked = summizeCalls.length
    await g.afterTurn({ turnId: 'turn-2', prompt: 'nothing' })
    assert.equal(events.length, 1)
    assert.equal(summizeCalls.length, asked)
  })

  test('uses the summize summary as the subject, with the prompt in the body', async () => {
    const g = git()
    await write('data/old.l4', 'old\n')
    await write('data/gone.l4', 'gone\n')
    await g.start(ctx)
    const seed = sh(repo, 'rev-parse', 'HEAD')
    await write('data/new.l4', 'new\n')
    await write('data/old.l4', 'changed\n')
    await rm(path.join(repo, 'data', 'gone.l4'))
    // A chatty answer: quotes, a trailing period, a second line.
    summize = async () =>
      '  "Add a late fee rule to the tenancy contract."\n\nThis subject describes the change.'
    await g.afterTurn({
      turnId: 'turn-1',
      prompt: 'Please add a late fee of 5%\nand keep the rest as it is',
      reply: 'I added the late fee rule and removed the unused file.',
    })
    const sha = sh(repo, 'rev-parse', 'HEAD')
    const subject = 'Add a late fee rule to the tenancy contract'
    assert.equal(
      sh(repo, 'log', '-1', '--format=%B'),
      `${subject}\n\nPrompt: Please add a late fee of 5%\n\nTurn-Id: turn-1`
    )
    // Only Turn-Id is a trailer; the prompt line is body text.
    assert.equal(
      sh(repo, 'log', '-1', '--format=%(trailers:only,unfold)'),
      'Turn-Id: turn-1'
    )
    assert.deepEqual(events, [
      {
        type: 'git-committed',
        turnId: 'turn-1',
        sha,
        parent: seed,
        summary: subject,
      },
    ])
    // What the pipeline was given: prompt, reply, paths with status.
    assert.equal(summizeCalls.length, 1)
    const [system, user] = summizeCalls[0]!.messages
    assert.equal(system!.role, 'system')
    assert.match(system!.content, /imperative mood/)
    assert.match(system!.content, /at most 72 characters/)
    assert.match(
      user!.content,
      /Please add a late fee of 5%\nand keep the rest/
    )
    assert.match(user!.content, /I added the late fee rule/)
    assert.match(user!.content, /^A data\/new\.l4$/m)
    assert.match(user!.content, /^M data\/old\.l4$/m)
    assert.match(user!.content, /^D data\/gone\.l4$/m)
    assert.ok(summizeCalls[0]!.signal instanceof AbortSignal)
    // Rolling back names the summary.
    await g.handleCommand({ id: 1, ts: 1, type: 'rollback', turnId: 'turn-1' })
    assert.equal(sh(repo, 'log', '-1', '--format=%s'), `Roll back: ${subject}`)
    assert.equal(await read('data/gone.l4'), 'gone\n')
    // The summary never reaches the logs.
    assert.ok(!logger.lines.some((l) => l.message.includes('late fee')))
    assert.ok(logger.has('info', /commit summary generated/))
  })

  for (const [name, answer] of [
    ['an error', () => Promise.reject(new Error('boom'))],
    ['no answer', async () => null],
    ['an empty answer', async () => '   \n  '],
    ['an unusable answer', async () => '"."'],
  ] as Array<[string, RunnerContext['summize']]>) {
    test(`falls back to the prompt's first line on ${name}`, async () => {
      const g = git()
      await g.start(ctx)
      await write('a.l4', 'x\n')
      summize = answer
      await g.afterTurn({ turnId: 't1', prompt: 'Draft the clause\nmore' })
      assert.equal(
        sh(repo, 'log', '-1', '--format=%B'),
        'Draft the clause\n\nPrompt: Draft the clause\n\nTurn-Id: t1'
      )
      assert.equal(
        (events[0] as { summary?: string }).summary,
        'Draft the clause'
      )
      assert.ok(logger.has('info', /commit summary unavailable/))
    })
  }

  test('a summary that never arrives costs at most the timeout', async () => {
    const g = new GitSync({ PATH: HOST_PATH }, { summaryTimeoutMs: 80 })
    await g.start(ctx)
    await write('a.l4', 'x\n')
    // Ignores its signal and never settles.
    summize = () => new Promise<string | null>(() => undefined)
    const started = Date.now()
    await g.afterTurn({ turnId: 't1', prompt: 'Slow one' })
    assert.ok(Date.now() - started < 3_000)
    assert.equal(sh(repo, 'log', '-1', '--format=%s'), 'Slow one')
    assert.equal(events.length, 1)
    // The request was told to stop.
    await new Promise((r) => setTimeout(r, 60))
    assert.equal(summizeCalls[0]!.signal?.aborted, true)
  })

  test('an empty prompt still commits, without a Prompt line', async () => {
    const g = git()
    await g.start(ctx)
    await write('a.l4', 'x\n')
    await g.afterTurn({ turnId: 't9', prompt: '  \n ' })
    assert.equal(sh(repo, 'log', '-1', '--format=%B'), 'Turn t9\n\nTurn-Id: t9')
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

  test('commits a tmp/ cleared by the sweep at the next start, and nothing else', async () => {
    await write('data/rules.l4', 'x\n')
    await write('tmp/notes.md', 'n\n')
    await write('tmp/deleted/t-t0/old.l4', 'o\n')
    await git().start(ctx)
    // The sweep deletes repo/tmp/ while the session sleeps.
    await rm(path.join(repo, 'tmp'), { recursive: true, force: true })
    await write('data/rules.l4', 'crash leftover\n')
    await git().start(ctx)
    assert.equal(
      sh(repo, 'log', '-1', '--format=%s'),
      'Clear tmp of abandoned session'
    )
    assert.equal(sh(repo, 'ls-files', 'tmp'), '')
    // The unrelated leftover stays for the next turn's commit.
    assert.equal(sh(repo, 'status', '--porcelain'), 'M data/rules.l4')
    // A partial deletion under tmp/ is not committed at start.
    await write('tmp/a.md', 'a\n')
    await write('tmp/b.md', 'b\n')
    const g = git()
    await g.start(ctx)
    await g.afterTurn({ turnId: 't1', prompt: 'p' })
    await rm(path.join(repo, 'tmp', 'a.md'))
    const head = sh(repo, 'rev-parse', 'HEAD')
    await git().start(ctx)
    assert.equal(sh(repo, 'rev-parse', 'HEAD'), head)
  })

  test('commits added files on their own and reports blob ids', async () => {
    const g = git()
    await g.start(ctx)
    await write('data/work.l4', 'agent work in progress\n')
    await write('data/added.l4', 'from the user\n')
    const shas = await g.onFilesAdded(['data/added.l4'])
    assert.equal(
      sh(repo, 'log', '-1', '--format=%s'),
      'Add files from the user'
    )
    assert.equal(
      shas['data/added.l4'],
      sh(repo, 'rev-parse', 'HEAD:data/added.l4')
    )
    // The agent's uncommitted work isn't swept into it.
    assert.equal(sh(repo, 'status', '--porcelain'), '?? data/work.l4')
    // Adding the same content again commits nothing.
    const head = sh(repo, 'rev-parse', 'HEAD')
    await g.onFilesAdded(['data/added.l4'])
    assert.equal(sh(repo, 'rev-parse', 'HEAD'), head)
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
    assert.equal(commitSubject('tab\there\u0007 bell', 'x'), 'tab here bell')
  })
})

describe('sanitizeSubject', () => {
  test('one clean line: no quotes, labels, control characters or period', () => {
    for (const [raw, want] of [
      ['Add the late fee rule', 'Add the late fee rule'],
      ['  "Add the late fee rule."  ', 'Add the late fee rule'],
      ['`Add the late fee rule`.', 'Add the late fee rule'],
      ['“Fix the date check”', 'Fix the date check'],
      ['\n\nSubject: Fix the date check\nBody text', 'Fix the date check'],
      ['Commit message: "Fix the date check."', 'Fix the date check'],
      ['- Fix the date check', 'Fix the date check'],
      ['## Fix the date check', 'Fix the date check'],
      ['Fix\tthe\u0000 date\u001b[0m   check', 'Fix the date [0m check'],
      ['Fix the date check\r\nSecond line', 'Fix the date check'],
      ['Fix the date check\u2028Second line', 'Fix the date check'],
      // Quotes inside the line stay.
      ["Rename `x` to 'y'", "Rename `x` to 'y'"],
      ['Say "hello" in the greeting rule.', 'Say "hello" in the greeting rule'],
    ] as const) {
      assert.equal(sanitizeSubject(raw), want, JSON.stringify(raw))
    }
  })

  test('caps at 72 characters', () => {
    const long = sanitizeSubject('Add ' + 'very '.repeat(30) + 'long subject')
    assert.equal(long!.length <= 72, true)
    assert.match(long!, /…$/)
    assert.equal(sanitizeSubject('x'.repeat(72)), 'x'.repeat(72))
  })

  test('nothing usable gives null', () => {
    for (const raw of [
      '',
      '   ',
      '\n\n',
      '""',
      '.',
      '"."',
      '\u0000\u0001',
      'ok',
    ]) {
      assert.equal(sanitizeSubject(raw), null, JSON.stringify(raw))
    }
  })
})

describe('summaryMessages', () => {
  test('truncates the prompt and reply and caps the path list', () => {
    const changes = Array.from({ length: 45 }, (_, i) => ({
      status: i % 3 === 0 ? 'A' : i % 3 === 1 ? 'M' : 'D',
      path: `data/f${i}.l4`,
    }))
    const [, user] = summaryMessages(
      { prompt: 'p'.repeat(2_000), reply: 'r'.repeat(5_000) },
      changes
    )
    const text = user!.content
    assert.ok(text.includes('p'.repeat(500) + '…'))
    assert.ok(!text.includes('p'.repeat(501)))
    assert.ok(text.includes('r'.repeat(1_000) + '…'))
    assert.ok(!text.includes('r'.repeat(1_001)))
    assert.equal((text.match(/^[AMD] data\/f\d+\.l4$/gm) ?? []).length, 30)
    assert.match(text, /\(and 15 more\)/)
    // No reply (an aborted turn) is said so.
    const [, bare] = summaryMessages({ prompt: 'x' }, changes.slice(0, 1))
    assert.match(bare!.content, /final reply:\n\(none\)/)
  })
})
