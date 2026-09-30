import { afterEach, beforeEach, describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import { mkdir, readFile, symlink, writeFile } from 'node:fs/promises'
import * as path from 'node:path'
import { type AuthProvider } from '@repo/legalese-agent'
import type { CloudEvent } from '@repo/legalese-agent/protocol'
import { initSessionFolder, sendCommand } from '../src/dev.js'
import { NodeWorkspace } from '../src/node-workspace.js'
import { GitSync } from '../src/git-sync.js'
import {
  Runner,
  type ChainControl,
  type ExitReason,
  type RunnerPlugin,
} from '../src/runner.js'
import {
  FakeAiProxy,
  HOST_PATH,
  MemoryLogger,
  SID,
  StubL4,
  chunk,
  metadata,
  readEvents,
  tempDir,
  toolCall,
  waitUntil,
} from './helpers.js'

const auth: AuthProvider = {
  getAiAuthHeaders: async () => ({
    Authorization: 'Bearer sk_test_key_123',
    'X-Legalese-Session': SID,
  }),
  getEffectiveServiceUrl: () => undefined,
}

class FakeChain implements ChainControl {
  started = 0
  ended = 0
  ok = true
  async start(): Promise<boolean> {
    this.started++
    return this.ok
  }
  async end(): Promise<void> {
    this.ended++
  }
  stopTimer(): void {}
}

describe('Runner', () => {
  let root: string
  let sessionDir: string
  let stateDir: string
  let cleanup: () => Promise<void>
  let proxy: FakeAiProxy
  let proxyUrl: string
  let logger: MemoryLogger
  let chain: FakeChain
  let l4: StubL4

  beforeEach(async () => {
    ;({ dir: root, cleanup } = await tempDir())
    sessionDir = await initSessionFolder(root, SID, 1_000)
    stateDir = path.join(sessionDir, 'state')
    proxy = new FakeAiProxy()
    proxyUrl = await proxy.start()
    logger = new MemoryLogger()
    chain = new FakeChain()
    l4 = new StubL4()
  })

  afterEach(async () => {
    await proxy.stop()
    await cleanup()
  })

  function build(
    opts: {
      idleExitMs?: number
      plugins?: RunnerPlugin[]
    } = {}
  ): Runner {
    return new Runner({
      sessionId: SID,
      sessionDir,
      taskId: 'task-1',
      logger,
      auth,
      chain,
      workspace: new NodeWorkspace(path.join(sessionDir, 'repo')),
      l4,
      aiEndpoint: { url: proxyUrl, local: false },
      plugins: opts.plugins,
      extensionVersion: 'test',
      idleExitMs: opts.idleExitMs ?? 60_000,
      pollMs: 20,
    })
  }

  const session = async (): Promise<Record<string, unknown>> =>
    JSON.parse(await readFile(path.join(sessionDir, 'session.json'), 'utf8'))
  const lease = async (): Promise<Record<string, unknown>> =>
    JSON.parse(await readFile(path.join(stateDir, 'lease.json'), 'utf8'))
  const types = (events: CloudEvent[]): string[] =>
    events.map((e) =>
      e.type === 'session-state'
        ? `state:${(e as { state: string }).state}`
        : e.type
    )

  test('runs a turn with a tool call, then sleeps when idle', async () => {
    proxy.scripts.push(
      [
        metadata('conv1'),
        toolCall('call1', 'fs__create_file', { path: 'data/notes/a.l4' }),
        chunk({}, 'tool_calls'),
      ],
      [chunk({ content: 'Done.' }), chunk({}, 'stop')]
    )
    const afterTurns: string[] = []
    const exits: ExitReason[] = []
    const runner = build({
      idleExitMs: 400,
      plugins: [
        {
          name: 'probe',
          afterTurn: async (t) => {
            afterTurns.push(`${t.turnId}:${t.conversationId}:${t.prompt}`)
          },
          beforeExit: async (r) => {
            exits.push(r)
          },
        },
      ],
    })
    const done = runner.run()
    await sendCommand(root, SID, {
      type: 'message',
      turnId: 'turn1',
      text: 'Write a rule',
    })
    const reason = await done
    assert.equal(reason, 'idle')

    // The file landed in the repo (fs__create_file writes a stub).
    assert.ok(
      (
        await readFile(
          path.join(sessionDir, 'repo', 'data', 'notes', 'a.l4'),
          'utf8'
        )
      ).length > 0
    )
    // ai-proxy saw the session header and the agent key.
    const chats = proxy.chatRequests()
    assert.equal(chats.length, 2)
    assert.equal(chats[0]!.headers['x-legalese-session'], SID)
    assert.equal(chats[0]!.headers.authorization, 'Bearer sk_test_key_123')
    assert.equal(chats[1]!.body.conversationId, 'conv1')

    const events = await readEvents(stateDir)
    assert.deepEqual(
      events.map((e) => e.seq),
      events.map((_, i) => i + 1)
    )
    assert.deepEqual(types(events), [
      'state:running',
      'user-message',
      'state:busy',
      'started',
      'tool-call',
      'tool-call',
      'tool-call',
      'text-delta',
      'done',
      'state:running',
      'state:sleeping',
    ])
    const toolRows = events.filter((e) => e.type === 'tool-call') as Array<
      CloudEvent & { status: string; name: string }
    >
    assert.deepEqual(
      toolRows.map((e) => [e.name, e.status]),
      [
        ['fs__create_file', 'running'],
        ['fs__create_file', 'running'],
        ['fs__create_file', 'done'],
      ]
    )
    assert.deepEqual(afterTurns, ['turn1:conv1:Write a rule'])
    assert.deepEqual(exits, ['idle'])

    const s = await session()
    assert.equal(s.status, 'sleeping')
    assert.equal(s.conversationId, 'conv1')
    assert.equal(s.title, 'A title')
    assert.ok(((await lease()).expiresAt as number) <= Date.now())
    assert.equal(
      await readFile(path.join(stateDir, 'commands.done'), 'utf8'),
      '1\n'
    )
    assert.equal(chain.started, 1)
    assert.equal(chain.ended, 1)
    assert.equal(l4.disposed, true)
  })

  test('asks the user through events and continues on an answer command', async () => {
    proxy.scripts.push(
      [
        metadata('conv2'),
        toolCall('ask1', 'meta__ask_user', {
          question: 'Which year?',
          choices: ['2025', '2026'],
        }),
        chunk({}, 'tool_calls'),
      ],
      [chunk({ content: 'Using 2026.' }), chunk({}, 'stop')]
    )
    const runner = build()
    const done = runner.run()
    await sendCommand(root, SID, {
      type: 'message',
      turnId: 't1',
      text: 'Draft it',
    })
    await waitUntil(
      async () =>
        (await readEvents(stateDir)).some((e) => e.type === 'ask-user'),
      5_000,
      'ask-user'
    )
    assert.equal((await lease()).state, 'waiting')
    const ask = (await readEvents(stateDir)).find(
      (e) => e.type === 'ask-user'
    ) as CloudEvent & {
      callId: string
      turnId: string
      conversationId: string
    }
    assert.deepEqual(
      [ask.callId, ask.turnId, ask.conversationId],
      ['ask1', 't1', 'conv2']
    )
    await sendCommand(root, SID, {
      type: 'answer',
      callId: 'ask1',
      answer: '2026',
    })
    await waitUntil(
      async () => (await readEvents(stateDir)).some((e) => e.type === 'done'),
      5_000,
      'done'
    )
    const toolResult = proxy.chatRequests()[1]!.body.messages as Array<{
      role: string
      content: string
    }>
    assert.match(toolResult[0]!.content, /2026/)
    await sendCommand(root, SID, { type: 'stop' })
    assert.equal(await done, 'stop')
    const t = types(await readEvents(stateDir))
    assert.ok(t.includes('state:waiting'))
    assert.equal(t.at(-1), 'state:sleeping')
  })

  test('parks when the key chain ends, keeping queued commands for later', async () => {
    let release!: () => void
    proxy.hold = new Promise((r) => (release = r))
    proxy.scripts.push([
      metadata('conv3'),
      chunk({ content: 'hi' }),
      chunk({}, 'stop'),
    ])
    const runner = build()
    const done = runner.run()
    await sendCommand(root, SID, { type: 'message', turnId: 't1', text: 'one' })
    await sendCommand(root, SID, { type: 'message', turnId: 't2', text: 'two' })
    await waitUntil(() => proxy.requests.length > 0, 5_000, 'first request')
    runner.onChainEnded('chain_forked')
    release()
    assert.equal(await done, 'parked')
    const s = await session()
    assert.equal(s.status, 'parked')
    assert.equal(s.parkedReason, 'chain_forked')
    const events = await readEvents(stateDir)
    assert.ok(
      events.some(
        (e) =>
          e.type === 'auth-required' &&
          (e as { reason: string }).reason === 'chain_forked'
      )
    )
    assert.equal(types(events).at(-1), 'state:parked')
    // t1 started (handled); t2 never did and is redelivered next start.
    assert.equal(
      await readFile(path.join(stateDir, 'commands.done'), 'utf8'),
      '1\n'
    )
    assert.equal(chain.ended, 0)
  })

  test('an inactive refusal while idle just sleeps', async () => {
    const runner = build()
    const done = runner.run()
    await waitUntil(async () => (await readEvents(stateDir)).length > 0)
    runner.onChainEnded('inactive')
    assert.equal(await done, 'idle')
    assert.equal((await session()).status, 'sleeping')
  })

  test('SIGTERM aborts the running turn and exits', async () => {
    proxy.hold = new Promise(() => undefined) // never answers
    const runner = build()
    const done = runner.run()
    await sendCommand(root, SID, {
      type: 'message',
      turnId: 't1',
      text: 'long',
    })
    await waitUntil(() => proxy.requests.length > 0, 5_000, 'request')
    runner.terminate()
    assert.equal(await done, 'sigterm')
    const events = await readEvents(stateDir)
    const doneEvent = events.find((e) => e.type === 'done') as
      | { finishReason?: string }
      | undefined
    assert.equal(doneEvent?.finishReason, 'aborted')
    assert.equal((await session()).status, 'sleeping')
  })

  test('exits without touching anything when another task holds the lease', async () => {
    await writeFile(
      path.join(stateDir, 'lease.json'),
      JSON.stringify({
        taskId: 'other',
        state: 'running',
        expiresAt: Date.now() + 60_000,
      })
    )
    const runner = build()
    assert.equal(await runner.run(), null)
    assert.equal((await lease()).taskId, 'other')
    assert.equal(chain.started, 0)
    assert.deepEqual(await readEvents(stateDir), [])
  })

  test('parks at start when the first renewal fails', async () => {
    chain.ok = false
    const calls: string[] = []
    const runner = build({
      plugins: [
        {
          name: 'probe',
          start: async () => {
            calls.push('start')
          },
          beforeExit: async () => {
            calls.push('beforeExit')
          },
        },
      ],
    })
    const done = runner.run()
    // KeyChainAuth calls onEnded from inside start(); the fake doesn't.
    await waitUntil(() => chain.started === 1)
    runner.onChainEnded('invalid_key')
    assert.equal(await done, 'parked')
    assert.equal((await session()).status, 'parked')
    // Plugins that never started aren't asked to clean up.
    assert.deepEqual(calls, [])
  })

  test('hands commands it does not own to plugins, and skips unknown ones', async () => {
    const seen: string[] = []
    const runner = build({
      plugins: [
        {
          name: 'git',
          commands: ['rollback'],
          handleCommand: async (cmd) => {
            seen.push(`${cmd.type}:${cmd.id}`)
          },
        },
      ],
    })
    const done = runner.run()
    await sendCommand(root, SID, { type: 'rollback', turnId: 't0' })
    await sendCommand(root, SID, {
      type: 'mcp-credentials',
      sealed: `v1.${'A'.repeat(43)}.${'B'.repeat(16)}.CC.${'D'.repeat(22)}`,
    })
    await waitUntil(async () => {
      const t = await readFile(
        path.join(stateDir, 'commands.done'),
        'utf8'
      ).catch(() => '')
      return t === '2\n'
    })
    await sendCommand(root, SID, { type: 'stop' })
    assert.equal(await done, 'stop')
    assert.deepEqual(seen, ['rollback:1'])
    assert.ok(logger.has('warn', /mcp-credentials is not supported/))
  })

  test('aborts a queued turn before it starts', async () => {
    let release!: () => void
    proxy.hold = new Promise((r) => (release = r))
    proxy.scripts.push([
      metadata('conv4'),
      chunk({ content: 'one' }),
      chunk({}, 'stop'),
    ])
    const runner = build()
    const done = runner.run()
    await sendCommand(root, SID, { type: 'message', turnId: 't1', text: 'one' })
    await sendCommand(root, SID, { type: 'message', turnId: 't2', text: 'two' })
    await waitUntil(() => proxy.requests.length > 0)
    await sendCommand(root, SID, { type: 'abort', turnId: 't2' })
    await waitUntil(async () =>
      (await readEvents(stateDir)).some(
        (e) =>
          e.type === 'done' &&
          (e as { finishReason: string }).finishReason === 'aborted'
      )
    )
    release()
    await waitUntil(
      async () =>
        (await readFile(path.join(stateDir, 'commands.done'), 'utf8')) === '3\n'
    )
    await sendCommand(root, SID, { type: 'stop' })
    assert.equal(await done, 'stop')
    // Only t1 reached the model.
    assert.equal(proxy.chatRequests().length, 1)
    const users = (await readEvents(stateDir)).filter(
      (e) => e.type === 'user-message'
    )
    assert.deepEqual(
      users.map((e) => (e as { turnId: string }).turnId),
      ['t1']
    )
  })

  test('deletes run without approval; the model recovers from tmp/deleted and keeps notes in tmp', async () => {
    const repo = path.join(sessionDir, 'repo')
    await writeFile(path.join(repo, 'data', 'keep.l4'), 'precious\n')
    proxy.scripts.push(
      [
        metadata('conv8'),
        toolCall('d1', 'fs__delete_file', { path: 'data/keep.l4' }),
        chunk({}, 'tool_calls'),
      ],
      [
        toolCall('r1', 'fs__read_file', { path: 'tmp/deleted/t-t1/keep.l4' }),
        chunk({}, 'tool_calls'),
      ],
      [
        toolCall('n1', 'fs__create_file', { path: 'tmp/notes/ideas.md' }),
        chunk({}, 'tool_calls'),
      ],
      [chunk({ content: 'Done.' }), chunk({}, 'stop')]
    )
    const runner = build()
    const done = runner.run()
    await sendCommand(root, SID, {
      type: 'message',
      turnId: 't1',
      text: 'oops',
    })
    await waitUntil(async () =>
      (await readEvents(stateDir)).some((e) => e.type === 'done')
    )
    await sendCommand(root, SID, { type: 'stop' })
    assert.equal(await done, 'stop')
    // The standing note rides on the prompt.
    const first = proxy.chatRequests()[0]!.body.messages as Array<{
      role: string
      content: string
    }>
    assert.match(first.at(-1)!.content, /tmp\/deleted\/t-t1\//)
    assert.match(first.at(-1)!.content, /live in data\//)
    // The delete ran without asking, and was copied first.
    const read = proxy.chatRequests()[2]!.body.messages as Array<{
      content: string
    }>
    assert.match(read[0]!.content, /precious/)
    const events = await readEvents(stateDir)
    assert.ok(
      !events.some(
        (e) =>
          e.type === 'tool-call' &&
          (e as { status: string }).status === 'pending-approval'
      )
    )
    assert.ok(!types(events).includes('state:waiting'))
    assert.ok(
      (await readFile(path.join(repo, 'tmp', 'notes', 'ideas.md'))).length > 0
    )
  })

  /** Queue a command the way the Sessions API does, internal ones too. */
  async function queueInternal(
    payload: Record<string, unknown>
  ): Promise<void> {
    const seqFile = path.join(stateDir, 'commands.seq')
    const n =
      Number((await readFile(seqFile, 'utf8').catch(() => '0')).trim()) + 1
    await writeFile(
      path.join(stateDir, 'commands', `${n}.json`),
      JSON.stringify({ ...payload, id: n, ts: 1 })
    )
    await writeFile(seqFile, `${n}\n`)
  }

  test('add-files copies a batch into data/, reports it and removes the batch', async () => {
    const batch = '01J9Z3K4M5N6P7Q8R9S0T1V2W5'
    const batchDir = path.join(sessionDir, 'incoming', 'files', batch)
    await mkdir(path.join(batchDir, 'data', 'sub'), { recursive: true })
    await writeFile(path.join(batchDir, 'data', 'new.l4'), 'DECIDE x IS 1\n')
    await writeFile(path.join(batchDir, 'data', 'sub', 'notes.md'), 'notes')
    await writeFile(path.join(sessionDir, 'repo', 'data', 'old.l4'), 'old')
    await writeFile(path.join(batchDir, 'data', 'old.l4'), 'new version')
    await writeFile(path.join(root, 'secret.txt'), 'secret')
    await symlink(
      path.join(root, 'secret.txt'),
      path.join(batchDir, 'data', 'link.txt')
    )
    const runner = build()
    const done = runner.run()
    await queueInternal({
      type: 'add-files',
      batchId: batch,
      files: [
        { path: 'data/new.l4' },
        { path: 'data/sub/notes.md' },
        { path: 'data/old.l4' },
        { path: 'data/link.txt' },
        { path: 'data/missing.l4' },
      ],
    })
    await waitUntil(async () =>
      (await readEvents(stateDir)).some((e) => e.type === 'files-added')
    )
    await sendCommand(root, SID, { type: 'stop' })
    assert.equal(await done, 'stop')
    const repo = path.join(sessionDir, 'repo')
    assert.equal(
      await readFile(path.join(repo, 'data', 'new.l4'), 'utf8'),
      'DECIDE x IS 1\n'
    )
    assert.equal(
      await readFile(path.join(repo, 'data', 'sub', 'notes.md'), 'utf8'),
      'notes'
    )
    assert.equal(
      await readFile(path.join(repo, 'data', 'old.l4'), 'utf8'),
      'new version'
    )
    await assert.rejects(readFile(path.join(repo, 'data', 'link.txt')))
    const ev = (await readEvents(stateDir)).find(
      (e) => e.type === 'files-added'
    ) as {
      batchId: string
      files: Array<{ path: string }>
    }
    assert.equal(ev.batchId, batch)
    assert.deepEqual(
      ev.files.map((f) => f.path),
      ['data/new.l4', 'data/sub/notes.md', 'data/old.l4']
    )
    await assert.rejects(readFile(path.join(batchDir, 'data', 'new.l4')))
  })

  test('message context: the active file and mentions reach the model', async () => {
    proxy.scripts.push([
      metadata('conv9'),
      chunk({ content: 'ok' }),
      chunk({}, 'stop'),
    ])
    const runner = build()
    const done = runner.run()
    await sendCommand(root, SID, {
      type: 'message',
      turnId: 't1',
      text: 'look at @data/b.l4',
      context: { activeFile: 'data/a.l4', mentions: ['data/b.l4'] },
    })
    await waitUntil(async () =>
      (await readEvents(stateDir)).some((e) => e.type === 'done')
    )
    await sendCommand(root, SID, { type: 'stop' })
    assert.equal(await done, 'stop')
    const msgs = proxy.chatRequests()[0]!.body.messages as Array<{
      role: string
      content: string
    }>
    const system = msgs
      .filter((m) => m.role === 'system')
      .map((m) => m.content)
      .join('\n')
    assert.match(system, /<editor-context>[\s\S]*data\/a\.l4/)
    assert.match(system, /<mention-context>[\s\S]*data\/b\.l4/)
  })

  test('commits each turn and rolls it back through commands (git plugin)', async () => {
    proxy.scripts.push([
      metadata('conv5'),
      toolCall('c1', 'fs__create_file', { path: 'data/rule.l4' }),
      chunk({}, 'tool_calls'),
    ])
    proxy.scripts.push([chunk({ content: 'Created.' }), chunk({}, 'stop')])
    const runner = build({
      plugins: [new GitSync({ PATH: HOST_PATH })],
    })
    const done = runner.run()
    await sendCommand(root, SID, {
      type: 'message',
      turnId: 't1',
      text: 'Create a rule',
    })
    await waitUntil(
      async () =>
        (await readEvents(stateDir)).some((e) => e.type === 'git-committed'),
      10_000,
      'git-committed'
    )
    await sendCommand(root, SID, { type: 'rollback', turnId: 't1' })
    await waitUntil(
      async () =>
        (await readEvents(stateDir)).some((e) => e.type === 'rolled-back'),
      10_000,
      'rolled-back'
    )
    await sendCommand(root, SID, { type: 'stop' })
    assert.equal(await done, 'stop')
    const t = types(await readEvents(stateDir))
    assert.ok(t.indexOf('done') < t.indexOf('git-committed'))
    assert.ok(t.indexOf('git-committed') < t.indexOf('rolled-back'))
    await assert.rejects(
      readFile(path.join(sessionDir, 'repo', 'data', 'rule.l4'))
    )
    assert.ok(
      (await readFile(path.join(stateDir, 'git', 'main.bundle'))).length > 0
    )
  })
})
