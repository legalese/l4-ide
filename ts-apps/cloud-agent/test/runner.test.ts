import { afterEach, beforeEach, describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import { readFile, writeFile } from 'node:fs/promises'
import * as path from 'node:path'
import {
  fixedPermissionPolicy,
  type AuthProvider,
  type PermissionPolicy,
} from '@repo/legalese-agent'
import type { CloudEvent } from '@repo/legalese-agent/protocol'
import { initSessionFolder, sendCommand } from '../src/dev.js'
import { NodeWorkspace } from '../src/node-workspace.js'
import {
  Runner,
  type ChainControl,
  type ExitReason,
  type RunnerPlugin,
} from '../src/runner.js'
import {
  FakeAiProxy,
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
      permissions?: PermissionPolicy
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
      permissions: opts.permissions,
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
        toolCall('call1', 'fs__create_file', { path: 'notes/a.l4' }),
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
      (await readFile(path.join(sessionDir, 'repo', 'notes', 'a.l4'), 'utf8'))
        .length > 0
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

  test('an approval waits for an approve command, then the tool row updates', async () => {
    proxy.scripts.push(
      [
        metadata('conv6'),
        toolCall('c1', 'fs__create_file', { path: 'x.l4' }),
        chunk({}, 'tool_calls'),
      ],
      [chunk({ content: 'ok' }), chunk({}, 'stop')]
    )
    const runner = build({
      permissions: fixedPermissionPolicy({ 'fs.create': 'ask' }),
    })
    const done = runner.run()
    await sendCommand(root, SID, { type: 'message', turnId: 't1', text: 'go' })
    await waitUntil(
      async () =>
        (await readEvents(stateDir)).some((e) => e.type === 'approval-request'),
      5_000,
      'approval-request'
    )
    assert.equal((await lease()).state, 'waiting')
    const req = (await readEvents(stateDir)).find(
      (e) => e.type === 'approval-request'
    ) as CloudEvent & { callId: string; name: string; turnId: string }
    assert.deepEqual(
      [req.callId, req.name, req.turnId],
      ['c1', 'fs__create_file', 't1']
    )
    await sendCommand(root, SID, {
      type: 'approve',
      callId: 'c1',
      decision: 'allow',
    })
    await waitUntil(async () =>
      (await readEvents(stateDir)).some((e) => e.type === 'done')
    )
    await sendCommand(root, SID, { type: 'stop' })
    assert.equal(await done, 'stop')
    const events = await readEvents(stateDir)
    const after = events.filter((e) => e.seq > req.seq)
    const statuses = after
      .filter((e) => e.type === 'tool-call')
      .map((e) => (e as { status: string }).status)
    // Every client clears its buttons from the status update after the
    // decision.
    assert.deepEqual(statuses, ['running', 'done'])
    const started = events.find((e) => e.type === 'started') as {
      turnId: string
    }
    assert.equal(started.turnId, 't1')
  })
})
