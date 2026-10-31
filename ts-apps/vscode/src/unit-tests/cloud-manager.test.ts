import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import type { ChatServiceEvent } from '@repo/legalese-agent'
import {
  generateSealingKeyPair,
  mcpCredentialsContext,
  openSealed,
  type AddFilesRequest,
  type ClientCommandPayload,
  type CloudEvent,
  type CreateSessionRequest,
  type EventStreamRequest,
  type EventStreamResponse,
  type PresignedUpload,
  type SessionState,
} from '@repo/legalese-agent/protocol'
import {
  AUTO_RESUME_DELAYS_MS,
  CloudSessionManager,
  START_SETTLE_MS,
} from '../cloud/cloud-session-manager.js'
import type { LocalMcpServer, McpServerSource } from '../cloud/mcp-transfer.js'
import { SeedLimitError } from '../cloud/seed.js'
import { SessionsApiError, type SessionsApi } from '../cloud/sessions-api.js'
import { FakeClock, MemoryLogger, SID } from './cloud-fakes.js'

const KEY = 'sk_test_0123456789abcdef'
const enc = (s: string) => new TextEncoder().encode(s)

class FakeApi implements SessionsApi {
  log: string[] = []
  created: CreateSessionRequest[] = []
  commands: ClientCommandPayload[] = []
  uploads: Array<{ url: string; bytes: number }> = []
  state: SessionState = 'sleeping'
  commandState: SessionState = 'sleeping'
  pending: CloudEvent[] = []
  failInit = false
  conversationId: string | undefined
  /** `session.json` MCP servers. */
  mcpServers: Array<{ name: string; url: string }> = []
  seedBase: { workspaceFolder: string; path: string } | undefined

  async createSession(req: CreateSessionRequest) {
    this.log.push('create')
    this.created.push(req)
    this.seedBase = req.seedBase
    const put = (name: string): PresignedUpload => ({
      url: `https://bucket.example/${name}`,
      method: 'PUT',
      headers: {},
    })
    return {
      sessionId: SID,
      gitUrl: `https://sessions.example/git/${SID}.git`,
      uploads: {
        seed: put('seed'),
        attachments: (req.attachments ?? []).map((a) => ({
          name: a.name,
          ...put(a.name),
        })),
      },
    }
  }
  async upload(target: PresignedUpload, body: Uint8Array) {
    this.log.push('upload')
    this.uploads.push({ url: target.url, bytes: body.byteLength })
  }
  async initSession() {
    this.log.push('init')
    if (this.failInit) throw new SessionsApiError(400, 'invalid_seed')
    return 'sleeping' as const
  }
  async listSessions() {
    return { sessions: [] }
  }
  async getSession(sid: string) {
    this.log.push('get')
    return {
      sessionId: sid,
      gitUrl: `https://sessions.example/git/${sid}.git`,
      state: this.state,
      session: {
        sessionId: sid,
        ownerUserId: 'user_1',
        title: 't',
        created: 1,
        lastActivity: 1,
        status: 'sleeping' as const,
        mcpServers: this.mcpServers,
        ...(this.conversationId ? { conversationId: this.conversationId } : {}),
        ...(this.seedBase ? { seedBase: this.seedBase } : {}),
      },
    }
  }
  /** The old task is still stopping: `start` answers without starting
   *  a task, and state reads still say `sleeping`. */
  startNoop = false
  async startSession(_sid: string, agentKey: string) {
    this.log.push(`start:${agentKey}`)
    if (!this.startNoop) this.state = 'starting'
    return 'starting' as const
  }
  async postCommand(_sid: string, command: ClientCommandPayload) {
    this.log.push(`command:${command.type}`)
    this.commands.push(command)
    return { commandId: this.commands.length, state: this.commandState }
  }
  async stopSession() {
    return 'running' as const
  }
  batches: AddFilesRequest[] = []
  async addFiles(_sid: string, req: AddFilesRequest) {
    this.log.push('add-files')
    this.batches.push(req)
    return {
      batchId: '01K6B8Z6X9Q4M2N7P3R5T8B000',
      uploads: req.files.map((f) => ({
        path: f.path,
        url: `https://bucket.example/${f.path}`,
        method: 'PUT' as const,
        headers: {},
      })),
    }
  }
  async commitFiles() {
    this.log.push('commit-files')
    return { commandId: 99, state: this.commandState }
  }
  renamed: Array<{ sid: string; title: string }> = []
  async renameSession(sid: string, title: string) {
    this.renamed.push({ sid, title })
  }
  async deleteSession() {
    this.log.push('delete')
  }
  async getEvents(streams: EventStreamRequest[]) {
    this.log.push('events')
    const events = this.pending
    this.pending = []
    return {
      streams: streams.map(
        (s): EventStreamResponse => ({
          sessionId: s.sessionId,
          events,
          cursor: '1:100',
          state: this.state,
        })
      ),
    }
  }
}

function setup(
  opts: {
    mcp?: McpServerSource
    pick?: (sid: string, name: string) => Promise<string | undefined>
    mint?: (sid: string) => Promise<{ token: string }>
    summarizeTitle?: (text: string) => Promise<string | null>
    titleTimeoutMs?: number
    onMcpSignIn?: (servers: string[]) => void
  } = {}
) {
  const api = new FakeApi()
  const clock = new FakeClock()
  const chat: ChatServiceEvent[] = []
  const cloud: Array<{
    conversationId?: string
    event: CloudEvent
    replay: boolean
  }> = []
  const progress: string[] = []
  const mcpListed: string[] = []
  const starting: Array<string | undefined> = []
  const logger = new MemoryLogger()
  const manager = new CloudSessionManager({
    api,
    mintAgentKey: opts.mint ?? (async () => ({ token: KEY })),
    mcp: opts.mcp,
    ...(opts.pick ? { pickLocalFolder: opts.pick } : {}),
    ...(opts.summarizeTitle ? { summarizeTitle: opts.summarizeTitle } : {}),
    ...(opts.titleTimeoutMs !== undefined
      ? { titleTimeoutMs: opts.titleTimeoutMs }
      : {}),
    logger,
    listener: {
      chat: (e) => chat.push(e),
      cloudEvent: (e) => cloud.push(e),
      ...(opts.onMcpSignIn
        ? { mcpSignIn: (_sid, servers) => opts.onMcpSignIn!(servers) }
        : {}),
      progress: (e) => {
        progress.push(e.phase)
        if (e.mcpServers) mcpListed.push(...e.mcpServers)
        if (e.phase === 'starting') starting.push(e.title)
      },
    },
    poller: {
      now: clock.now,
      setTimer: clock.setTimer,
      clearTimer: clock.clearTimer,
    },
  })
  return {
    api,
    clock,
    chat,
    cloud,
    progress,
    mcpListed,
    starting,
    manager,
    logger,
  }
}

let seq = 0
function ev<T extends Omit<CloudEvent, 'seq' | 'ts'>>(e: T): CloudEvent {
  return { seq: ++seq, ts: 1, ...e } as unknown as CloudEvent
}

describe('CloudSessionManager.runInCloud', () => {
  test('seeds, queues the prompt, then mints a key and starts (§10)', async () => {
    const { api, clock, manager, progress } = setup()
    const res = await manager.runInCloud({
      turnId: 'turn-1',
      text: 'Check clause 4\nplease',
      seed: {
        files: [{ path: 'rules/main.l4', bytes: enc('x') }],
        attachments: [
          {
            name: 'memo.pdf',
            contentType: 'application/pdf',
            bytes: enc('pdf'),
          },
        ],
      },
    })
    assert.equal(res.sessionId, SID)
    assert.deepEqual(api.log, [
      'create',
      'upload',
      'upload',
      'init',
      'command:message',
      `start:${KEY}`,
    ])
    const req = api.created[0]!
    assert.equal(req.title, 'Check clause 4')
    assert.ok(req.seedSize! > 0)
    assert.deepEqual(req.attachments, [
      { name: 'memo.pdf', contentType: 'application/pdf', size: 3 },
    ])
    assert.deepEqual(api.commands[0], {
      type: 'message',
      turnId: 'turn-1',
      text: 'Check clause 4\nplease',
      attachments: ['memo.pdf'],
    })
    assert.deepEqual(progress, ['uploading', 'uploading', 'starting'])
    assert.equal(manager.sessionForTurn('turn-1'), SID)
    assert.ok(manager.isWatching(SID))
    api.state = 'busy'
    await clock.advance(0)
    assert.deepEqual(progress, ['uploading', 'uploading', 'starting', 'ready'])
  })

  test('names the session with an AI title, else the first line', async () => {
    const run = async (opts: Parameters<typeof setup>[0]) => {
      const { api, manager, starting } = setup(opts)
      await manager.runInCloud({
        turnId: 'turn-1',
        text: 'Check clause 4\nplease',
        seed: { files: [], attachments: [] },
      })
      // The view learns it with the start.
      assert.deepEqual(starting, [api.created[0]!.title])
      return api.created[0]!.title
    }
    const asked: string[] = []
    assert.equal(
      await run({
        summarizeTitle: async (text) => {
          asked.push(text)
          return '  Clause 4 review  '
        },
      }),
      'Clause 4 review'
    )
    // The whole prompt, as for a local chat's title.
    assert.deepEqual(asked, ['Check clause 4\nplease'])
    assert.equal(
      await run({
        summarizeTitle: async () => {
          throw new Error('offline')
        },
      }),
      'Check clause 4'
    )
    assert.equal(
      await run({ summarizeTitle: async () => null }),
      'Check clause 4'
    )
    // A slow answer doesn't hold up the start.
    assert.equal(
      await run({
        summarizeTitle: () => new Promise(() => {}),
        titleTimeoutMs: 5,
      }),
      'Check clause 4'
    )
  })

  test('declines oversized attachments before creating anything', async () => {
    const { api, manager } = setup()
    await assert.rejects(
      manager.runInCloud({
        turnId: 't',
        text: 'x',
        seed: {
          files: [],
          attachments: [
            {
              name: 'big.pdf',
              contentType: 'application/pdf',
              bytes: new Uint8Array(10 * 1024 * 1024 + 1),
            },
          ],
        },
      }),
      SeedLimitError
    )
    assert.deepEqual(api.log, [])
  })

  test('deletes the session again when setting it up fails', async () => {
    const { api, manager } = setup()
    api.failInit = true
    await assert.rejects(
      manager.runInCloud({
        turnId: 't',
        text: 'x',
        seed: { files: [], attachments: [] },
      }),
      SessionsApiError
    )
    await new Promise((r) => setImmediate(r))
    assert.deepEqual(api.log, ['create', 'init', 'delete'])
    assert.equal(manager.sessionForTurn('t'), undefined)
  })
})

describe('CloudSessionManager events', () => {
  test('maps chat events and routes cloud-only ones to the conversation', async () => {
    const { api, clock, chat, cloud, manager } = setup()
    api.state = 'busy'
    api.pending = [
      ev({
        type: 'user-message',
        turnId: 'turn-1',
        text: 'hi',
        attachments: [],
      }),
      ev({
        type: 'started',
        conversationId: 'conv-1',
        turnId: 'turn-1',
        model: 'm',
      }),
      ev({ type: 'text-delta', conversationId: 'conv-1', text: 'Hello' }),
      ev({
        type: 'ask-user',
        conversationId: 'conv-1',
        turnId: 'turn-1',
        callId: 'call-1',
        question: 'Which?',
      }),
    ]
    await manager.open(SID)
    await clock.advance(0)
    assert.deepEqual(
      chat.map((e) => e.kind),
      ['started', 'text-delta']
    )
    assert.deepEqual(chat[1], {
      kind: 'text-delta',
      conversationId: 'conv-1',
      text: 'Hello',
    })
    assert.deepEqual(
      cloud.map((c) => [c.event.type, c.conversationId, c.replay]),
      [
        ['user-message', undefined, true],
        ['ask-user', 'conv-1', true],
      ]
    )
    assert.equal(manager.sessionForConversation('conv-1'), SID)

    // Later events are live, and events already seen are dropped.
    const old = ev({
      type: 'text-delta',
      conversationId: 'conv-1',
      text: 'old',
    })
    api.pending = [
      ev({ type: 'text-delta', conversationId: 'conv-1', text: ' there' }),
    ]
    await clock.advance(1000)
    api.pending = [{ ...old, seq: 1 } as CloudEvent]
    await clock.advance(1000)
    assert.deepEqual(
      chat.map((e) => (e.kind === 'text-delta' ? e.text : e.kind)),
      ['started', 'Hello', ' there']
    )
  })

  test('a command to a sleeping or parked session starts it', async () => {
    const { api, manager } = setup()
    api.commandState = 'sleeping'
    await manager.sendMessage(SID, 'turn-2', 'next')
    assert.deepEqual(api.log, ['command:message', `start:${KEY}`])
    api.log = []
    api.commandState = 'parked'
    await manager.answer(SID, 'call-1', 'yes')
    assert.deepEqual(
      api.log,
      ['command:answer', `start:${KEY}`],
      'a parked one with a new key chain, no Resume'
    )
  })
})

describe('CloudSessionManager: a message sent while the task shuts down', () => {
  const starts = (api: FakeApi) =>
    api.log.filter((l) => l.startsWith('start:')).length

  /** A running session; `turn-2` is sent, then the task exits without
   *  picking it up. */
  async function sentThenAsleep(s: ReturnType<typeof setup>) {
    s.api.state = 'running'
    s.api.commandState = 'running'
    await s.manager.sendMessage(SID, 'turn-2', 'next')
    await s.clock.advance(0)
    assert.equal(starts(s.api), 0)
    s.api.state = 'sleeping'
    await s.clock.advance(5000)
  }

  test('starts the session again once it has gone to sleep', async () => {
    const s = setup()
    await sentThenAsleep(s)
    assert.equal(starts(s.api), 1)
    assert.deepEqual(s.api.commands, [
      { type: 'message', turnId: 'turn-2', text: 'next' },
    ])
    // The start took (a poll sees it); a session that goes to sleep
    // again without running the message is not started a second time.
    await s.clock.advance(1000)
    s.api.state = 'sleeping'
    await s.clock.advance(120_000)
    assert.equal(starts(s.api), 1)
  })

  test('nothing to do once an event acknowledged the message', async () => {
    const s = setup()
    s.api.state = 'running'
    s.api.commandState = 'running'
    await s.manager.sendMessage(SID, 'turn-2', 'next')
    s.api.pending = [
      ev({
        type: 'user-message',
        turnId: 'turn-2',
        text: 'next',
        attachments: [],
      }),
    ]
    await s.clock.advance(0)
    s.api.state = 'sleeping'
    await s.clock.advance(60_000)
    assert.equal(starts(s.api), 0)
  })

  test('nothing to do after Stop or Abort', async () => {
    const stopped = setup()
    stopped.api.state = 'running'
    stopped.api.commandState = 'running'
    await stopped.manager.sendMessage(SID, 'turn-2', 'next')
    await stopped.manager.stop(SID)
    stopped.api.state = 'sleeping'
    await stopped.clock.advance(60_000)
    assert.equal(starts(stopped.api), 0)

    const aborted = setup()
    aborted.api.state = 'running'
    aborted.api.commandState = 'running'
    await aborted.manager.sendMessage(SID, 'turn-2', 'next')
    await aborted.manager.abort(SID, 'turn-2')
    aborted.api.state = 'sleeping'
    await aborted.clock.advance(60_000)
    assert.equal(starts(aborted.api), 0)
  })

  test('a start answered while the old task still stops is retried, a bounded number of times', async () => {
    const s = setup()
    s.api.startNoop = true
    await sentThenAsleep(s)
    assert.equal(starts(s.api), 1)
    // Polls still say `sleeping`: not again before the delay.
    await s.clock.advance(AUTO_RESUME_DELAYS_MS[1]! - 2000)
    assert.equal(starts(s.api), 1)
    await s.clock.advance(2000)
    assert.equal(starts(s.api), 2)
    await s.clock.advance(10 * 60_000)
    assert.equal(starts(s.api), AUTO_RESUME_DELAYS_MS.length)
  })

  test('polls that still say sleeping just after a start leave it be', async () => {
    const s = setup()
    // Sending to a sleeping session starts it; the new task takes a
    // moment to show up in ECS, so the next polls still say sleeping.
    s.api.state = 'sleeping'
    s.api.commandState = 'sleeping'
    s.api.startNoop = true
    await s.manager.sendMessage(SID, 'turn-2', 'next')
    assert.equal(starts(s.api), 1)
    await s.clock.advance(START_SETTLE_MS - 2000)
    assert.equal(starts(s.api), 1)
    s.api.state = 'starting'
    await s.clock.advance(60_000)
    assert.equal(starts(s.api), 1)
  })

  test('a retried start that takes is the last', async () => {
    const s = setup()
    s.api.startNoop = true
    await sentThenAsleep(s)
    assert.equal(starts(s.api), 1)
    // The old task has stopped by the next try.
    s.api.startNoop = false
    await s.clock.advance(AUTO_RESUME_DELAYS_MS[1]!)
    assert.equal(starts(s.api), 2)
    await s.clock.advance(1000)
    s.api.state = 'sleeping'
    await s.clock.advance(10 * 60_000)
    assert.equal(starts(s.api), 2)
  })

  test('a failed start is reported in the conversation, and not retried', async () => {
    let mints = 0
    const s = setup({
      mint: async () => {
        mints++
        throw new Error('not signed in')
      },
    })
    s.api.conversationId = 'conv-1'
    s.api.state = 'running'
    await s.manager.open(SID)
    await sentThenAsleep(s)
    const errors = s.chat.filter((e) => e.kind === 'error')
    assert.equal(errors.length, 1)
    assert.equal(
      (errors[0] as { conversationId: string }).conversationId,
      'conv-1'
    )
    assert.match(
      (errors[0] as { message: string }).message,
      /starting it again failed: not signed in/
    )
    await s.clock.advance(10 * 60_000)
    assert.equal(mints, 1)
    assert.equal(s.chat.filter((e) => e.kind === 'error').length, 1)
  })
})

describe('CloudSessionManager: a session whose key chain ends', () => {
  const starts = (api: FakeApi) =>
    api.log.filter((l) => l.startsWith('start:')).length

  /** An open session in `state`; its chain then ends (`auth-required`)
   *  and it parks. */
  async function parks(s: ReturnType<typeof setup>, state: SessionState) {
    s.api.state = state
    await s.manager.open(SID)
    await s.clock.advance(0)
    s.api.pending = [ev({ type: 'auth-required', reason: 'chain_expired' })]
    await s.clock.advance(1000)
    s.api.state = 'parked'
    await s.clock.advance(5000)
  }

  test('mid-turn: started again with a new chain, so the turn goes on', async () => {
    const s = setup()
    await parks(s, 'busy')
    assert.equal(starts(s.api), 1)
    assert.ok(s.logger.lines.some((l) => /parked mid-turn/.test(l)))
    // It runs again, then parks mid-turn once more right away (a chain
    // refused after each start): not started again within the gap.
    s.api.state = 'busy'
    await s.clock.advance(2000)
    s.api.pending = [ev({ type: 'auth-required', reason: 'forbidden' })]
    await s.clock.advance(1000)
    s.api.state = 'parked'
    await s.clock.advance(5 * 60_000)
    assert.equal(starts(s.api), 1)
  })

  test('mid-turn, at most once per message: a turn that never ends waits for the user', async () => {
    const s = setup()
    await parks(s, 'busy')
    assert.equal(starts(s.api), 1)
    // Running again, and parked mid-turn again well after the gap.
    s.api.state = 'busy'
    await s.clock.advance(30 * 60_000)
    s.api.pending = [ev({ type: 'auth-required', reason: 'chain_expired' })]
    await s.clock.advance(1000)
    s.api.state = 'parked'
    await s.clock.advance(30 * 60_000)
    assert.equal(starts(s.api), 1)
    // The user's next message starts it.
    s.api.commandState = 'parked'
    await s.manager.sendMessage(SID, 'turn-2', 'go on')
    assert.equal(starts(s.api), 2)
  })

  test('mid-turn but not in view: it waits for the next message', async () => {
    const s = setup()
    s.api.state = 'busy'
    await s.manager.open(SID)
    await s.clock.advance(0)
    s.manager.setViewing(undefined)
    s.api.pending = [ev({ type: 'auth-required', reason: 'chain_expired' })]
    await s.clock.advance(1000)
    s.api.state = 'parked'
    await s.clock.advance(5000)
    assert.equal(starts(s.api), 0)
    // Parked and out of view: no longer watched.
    assert.equal(s.manager.isWatching(SID), false)
  })

  test('while idle: it waits for the next message, which starts it', async () => {
    const s = setup()
    await parks(s, 'running')
    await s.clock.advance(60_000)
    assert.equal(starts(s.api), 0)
    s.api.commandState = 'parked'
    await s.manager.sendMessage(SID, 'turn-2', 'next')
    assert.equal(starts(s.api), 1)
  })

  test('a park already in the log when the session is opened starts nothing', async () => {
    const s = setup()
    s.api.state = 'parked'
    s.api.pending = [ev({ type: 'auth-required', reason: 'chain_expired' })]
    await s.manager.open(SID)
    await s.clock.advance(60_000)
    assert.equal(starts(s.api), 0)
  })
})

describe('CloudSessionManager: sessions out of view', () => {
  test('a running one stays watched until it sleeps, then is let go', async () => {
    const s = setup()
    s.api.state = 'running'
    await s.manager.open(SID)
    await s.clock.advance(0)
    s.manager.setViewing(undefined)
    await s.clock.advance(5000)
    assert.equal(s.manager.isWatching(SID), true)
    s.api.state = 'sleeping'
    await s.clock.advance(5000)
    assert.equal(s.manager.isWatching(SID), false)
  })

  test('a sleeping one is let go when the view moves on', async () => {
    const s = setup()
    s.api.state = 'sleeping'
    await s.manager.open(SID)
    await s.clock.advance(0)
    assert.equal(s.manager.isWatching(SID), true)
    s.manager.setViewing(undefined)
    assert.equal(s.manager.isWatching(SID), false)
  })
})

describe('CloudSessionManager MCP credentials (§6.4)', () => {
  test('seals credentials to the running harness key, once per key', async () => {
    const keyPair = generateSealingKeyPair()
    const mcp: McpServerSource = {
      enabledServers: () => [
        {
          id: 'Docs Server',
          url: 'https://docs.example/mcp',
          transport: 'http',
        },
        { id: 'local', url: '', transport: 'stdio' },
      ],
      headersFor: async () => ({
        Authorization: tokens++ === 0 ? 'Bearer secret-token' : 'Bearer next',
      }),
    }
    let tokens = 0
    const { api, clock, manager } = setup({ mcp })
    api.mcpServers = [{ name: 'Docs_Server', url: 'https://docs.example/mcp' }]
    api.state = 'running'
    api.pending = [
      ev({
        type: 'session-state',
        state: 'running',
        publicKey: keyPair.publicKey,
      }),
    ]
    await manager.open(SID)
    await clock.advance(0)
    const sent = api.commands.filter((c) => c.type === 'mcp-credentials')
    assert.equal(sent.length, 1)
    const cmd = sent[0] as { sealed: string }
    assert.ok(!cmd.sealed.includes('secret-token'))
    const plain = JSON.parse(
      openSealed(keyPair, cmd.sealed, mcpCredentialsContext(SID)).toString(
        'utf8'
      )
    )
    assert.deepEqual(plain, {
      servers: [
        {
          name: 'Docs_Server',
          headers: { Authorization: 'Bearer secret-token' },
        },
      ],
    })

    // Same key: nothing more. An MCP auth-required asks again (with a
    // refreshed token).
    await clock.advance(5000)
    assert.equal(
      api.commands.filter((c) => c.type === 'mcp-credentials').length,
      1
    )
    api.pending = [
      ev({ type: 'auth-required', reason: 'mcp', server: 'Docs_Server' }),
    ]
    await clock.advance(5000)
    assert.equal(
      api.commands.filter((c) => c.type === 'mcp-credentials').length,
      2
    )
  })

  /** A running session with the MCP server `Docs Server`; returns what
   *  the listener was told needs a sign-in, and the sends. */
  async function docsSession(mcp: McpServerSource) {
    const signIns: string[][] = []
    const s = setup({ mcp, onMcpSignIn: (servers) => signIns.push(servers) })
    s.api.mcpServers = [
      { name: 'Docs_Server', url: 'https://docs.example/mcp' },
    ]
    s.api.state = 'running'
    s.api.pending = [
      ev({
        type: 'session-state',
        state: 'running',
        publicKey: generateSealingKeyPair().publicKey,
      }),
    ]
    await s.manager.open(SID)
    await s.clock.advance(0)
    const sends = () =>
      s.api.commands.filter((c) => c.type === 'mcp-credentials').length
    return { ...s, signIns, sends }
  }
  const docs = [
    { id: 'Docs Server', url: 'https://docs.example/mcp', transport: 'http' },
  ] as const

  test('a server without a sign-in here is reported, and signing in sends it', async () => {
    let signedIn = false
    const mcp: McpServerSource = {
      enabledServers: () => [...docs],
      headersFor: async () =>
        signedIn ? { Authorization: 'Bearer fresh' } : null,
      signIn: async (id) => {
        assert.equal(id, 'Docs Server')
        signedIn = true
        return { ok: true }
      },
    }
    const s = await docsSession(mcp)
    assert.equal(s.sends(), 0)
    assert.deepEqual(s.signIns, [['Docs Server']])
    assert.deepEqual(s.manager.mcpSignInNeeded(SID), ['Docs Server'])
    await s.manager.signInMcp(SID, 'Docs Server')
    assert.equal(s.sends(), 1)
    assert.deepEqual(s.signIns, [['Docs Server'], []])
    assert.deepEqual(s.manager.mcpSignInNeeded(SID), [])
  })

  test('headers the harness turned down are not sent again: a sign-in instead', async () => {
    const mcp: McpServerSource = {
      enabledServers: () => [...docs],
      headersFor: async () => ({ Authorization: 'Bearer revoked' }),
      signIn: async () => ({ ok: false, error: 'consent denied' }),
    }
    const s = await docsSession(mcp)
    assert.equal(s.sends(), 1)
    s.api.pending = [
      ev({ type: 'auth-required', reason: 'mcp', server: 'Docs_Server' }),
    ]
    await s.clock.advance(5000)
    assert.equal(s.sends(), 1)
    assert.deepEqual(s.signIns, [['Docs Server']])
    // The failed sign-in was reported by the MCP layer; the chip stays.
    await s.manager.signInMcp(SID, 'Docs Server')
    assert.deepEqual(s.manager.mcpSignInNeeded(SID), ['Docs Server'])
  })

  // Nothing stored here for the server (this window never signed in to
  // it): nothing is sent, and once the session reports it, it needs a
  // sign-in — whether or not this window's own connection ran.
  test('a reported server with nothing stored here needs a sign-in', async () => {
    const mcp: McpServerSource = {
      enabledServers: () => [...docs],
      headersFor: async () => ({}),
    }
    const s = await docsSession(mcp)
    assert.equal(s.sends(), 0)
    assert.deepEqual(s.signIns, [])
    s.api.pending = [
      ev({ type: 'auth-required', reason: 'mcp', server: 'Docs_Server' }),
    ]
    await s.clock.advance(5000)
    assert.equal(s.sends(), 0)
    assert.deepEqual(s.signIns, [['Docs Server']])
  })

  test('a turned-down token is refreshed before asking for a sign-in', async () => {
    const refreshed: boolean[] = []
    const mcp: McpServerSource = {
      enabledServers: () => [...docs],
      headersFor: async (_id, opts) => {
        refreshed.push(opts?.refresh ?? false)
        return {
          Authorization: opts?.refresh ? 'Bearer fresh' : 'Bearer stale',
        }
      },
    }
    const s = await docsSession(mcp)
    assert.equal(s.sends(), 1)
    s.api.pending = [
      ev({ type: 'auth-required', reason: 'mcp', server: 'Docs_Server' }),
    ]
    await s.clock.advance(5000)
    assert.deepEqual(refreshed, [false, true])
    assert.equal(s.sends(), 2)
    assert.deepEqual(s.signIns, [])
  })

  // The credentials are for the local server's URL: a `session.json`
  // entry of the same name with another URL (edited by a task, or
  // another server of that name) gets nothing.
  test('only to a server whose name and URL both match', async () => {
    const mcp: McpServerSource = {
      enabledServers: () => [...docs],
      headersFor: async () => ({ Authorization: 'Bearer secret' }),
    }
    const s = setup({ mcp })
    s.api.mcpServers = [
      { name: 'Docs_Server', url: 'https://attacker.example/mcp' },
    ]
    s.api.state = 'running'
    s.api.pending = [
      ev({
        type: 'session-state',
        state: 'running',
        publicKey: generateSealingKeyPair().publicKey,
      }),
    ]
    await s.manager.open(SID)
    await s.clock.advance(0)
    assert.equal(
      s.api.commands.filter((c) => c.type === 'mcp-credentials').length,
      0
    )
  })

  test('not to servers added to session.json after the session was created', async () => {
    const keyPair = generateSealingKeyPair()
    const mail = {
      id: 'Mail',
      url: 'https://mail.example/mcp',
      transport: 'http',
    } as const
    let enabled: LocalMcpServer[] = [...docs]
    const mcp: McpServerSource = {
      enabledServers: () => enabled,
      headersFor: async (id) => ({ Authorization: `Bearer ${id}` }),
    }
    const s = setup({ mcp })
    // Created here while only Docs was enabled…
    await s.manager.runInCloud({
      turnId: 't',
      text: 'x',
      seed: { files: [], attachments: [] },
    })
    // …then Mail is enabled, and a task adds it to session.json.
    enabled = [...docs, mail]
    s.api.mcpServers = [
      { name: 'Docs_Server', url: 'https://docs.example/mcp' },
      { name: 'Mail', url: 'https://mail.example/mcp' },
    ]
    s.api.state = 'running'
    s.api.pending = [
      ev({
        type: 'session-state',
        state: 'running',
        publicKey: keyPair.publicKey,
      }),
    ]
    await s.manager.open(SID)
    await s.clock.advance(0)
    const sent = s.api.commands.filter((c) => c.type === 'mcp-credentials')
    assert.equal(sent.length, 1)
    const plain = JSON.parse(
      openSealed(
        keyPair,
        (sent[0] as { sealed: string }).sealed,
        mcpCredentialsContext(SID)
      ).toString('utf8')
    )
    assert.deepEqual(
      plain.servers.map((x: { name: string }) => x.name),
      ['Docs_Server']
    )
  })

  test('passes only https HTTP/SSE servers in POST /sessions', async () => {
    const mcp: McpServerSource = {
      enabledServers: () => [
        {
          id: 'b',
          url: 'https://b.example/mcp',
          transport: 'sse',
          enabledTools: ['x'],
        },
        { id: 'a', url: 'http://insecure.example/mcp', transport: 'http' },
        { id: 'c', url: '', transport: 'stdio' },
      ],
      headersFor: async () => ({}),
    }
    const { api, manager, mcpListed } = setup({ mcp })
    await manager.runInCloud({
      turnId: 't',
      text: 'x',
      seed: { files: [], attachments: [] },
    })
    assert.deepEqual(api.created[0]!.mcpServers, [
      {
        name: 'b',
        url: 'https://b.example/mcp',
        transport: 'sse',
        enabledTools: ['x'],
      },
    ])
    // Listed in the start progress: their tools run without approval.
    assert.deepEqual(mcpListed, ['b'])
  })
})

describe('CloudSessionManager files in later prompts (§10)', () => {
  const ws = '/ws'
  const folders = [{ name: 'ws', path: ws }]
  const file = (p: string, text: string) => ({ path: p, bytes: enc(text) })

  test('first message names the seeded active file and mentions', async () => {
    const { api, manager } = setup()
    await manager.runInCloud({
      turnId: 't1',
      text: 'go',
      seed: {
        files: [
          { path: 'rules/main.l4', bytes: enc('m') },
          { path: 'shared/defs.l4', bytes: enc('d') },
        ],
        attachments: [],
        root: ws,
        activeFile: '/ws/rules/main.l4',
        mentions: ['/ws/shared/defs.l4', '/elsewhere/x.l4'],
      },
    })
    assert.deepEqual((api.commands[0] as { context?: unknown }).context, {
      activeFile: 'data/rules/main.l4',
      mentions: ['data/shared/defs.l4'],
    })
  })

  test('adds only new or changed files, relative to the seed base', async () => {
    const { api, manager, progress } = setup()
    await manager.runInCloud({
      turnId: 't1',
      text: 'go',
      seed: {
        files: [{ path: 'main.l4', bytes: enc('v1') }],
        attachments: [],
        root: '/ws/rules',
        workspaceFolders: folders,
      },
    })
    // The seed base is recorded in the session for every machine.
    assert.deepEqual(api.created[0]!.seedBase, {
      workspaceFolder: 'ws',
      path: 'rules',
    })
    api.log = []
    progress.length = 0
    api.commandState = 'busy'
    await manager.sendMessage(SID, 't2', 'look at defs', {
      sources: [
        file('/ws/rules/main.l4', 'v1'), // unchanged: not sent
        file('/ws/rules/lib/defs.l4', 'd'), // under the base
        file('/ws/other/notes.md', 'n'), // outside the base: workspace-relative
        file('/tmp/outside.l4', 'x'), // outside the workspace: skipped
      ],
      activeFile: '/ws/rules/main.l4',
      mentions: ['/ws/rules/lib/defs.l4', '/ws/other/notes.md'],
      workspaceFolders: folders,
    })
    assert.deepEqual(api.log, [
      'add-files',
      'upload',
      'upload',
      'commit-files',
      'command:message',
    ])
    assert.deepEqual(
      api.batches[0]!.files.map((f) => f.path),
      ['data/lib/defs.l4', 'data/other/notes.md']
    )
    assert.equal(progress[0], 'adding-files')
    assert.deepEqual(api.commands[api.commands.length - 1], {
      type: 'message',
      turnId: 't2',
      text: 'look at defs',
      context: {
        activeFile: 'data/main.l4',
        mentions: ['data/lib/defs.l4', 'data/other/notes.md'],
      },
    })

    // Same files again: nothing uploaded; an edit is.
    api.log = []
    await manager.sendMessage(SID, 't3', 'again', {
      sources: [
        file('/ws/rules/lib/defs.l4', 'd'),
        file('/ws/rules/main.l4', 'v2'),
      ],
      workspaceFolders: folders,
    })
    assert.deepEqual(api.log, [
      'add-files',
      'upload',
      'commit-files',
      'command:message',
    ])
    assert.deepEqual(
      api.batches[1]!.files.map((f) => f.path),
      ['data/main.l4']
    )
  })

  test('declines files over the limits before uploading', async () => {
    const { api, manager } = setup()
    await assert.rejects(
      manager.sendMessage(SID, 't', 'x', {
        sources: [
          { path: '/ws/big.pdf', bytes: new Uint8Array(10 * 1024 * 1024 + 1) },
        ],
        workspaceFolders: folders,
      }),
      (err: unknown) =>
        err instanceof SeedLimitError && /data\/big\.pdf/.test(err.message)
    )
    // Only the session lookup (for its seed base); nothing uploaded.
    assert.deepEqual(api.log, ['get'])
  })

  test('another machine maps files through the session seedBase', async () => {
    const { api, manager } = setup()
    api.seedBase = { workspaceFolder: 'ws', path: 'rules' }
    api.commandState = 'busy'
    await manager.sendMessage(SID, 't', 'x', {
      sources: [file('/home/me/code/ws/rules/lib/defs.l4', 'd')],
      mentions: ['/home/me/code/ws/rules/lib/defs.l4'],
      workspaceFolders: [{ name: 'ws', path: '/home/me/code/ws' }],
    })
    assert.deepEqual(
      api.batches[0]!.files.map((f) => f.path),
      ['data/lib/defs.l4']
    )
  })

  test('asks once for the local folder when none has the name', async () => {
    const asked: string[] = []
    const { api, manager } = setup({
      pick: async (_sid, name) => {
        asked.push(name)
        return '/home/me/elsewhere'
      },
    })
    api.seedBase = { workspaceFolder: 'ws', path: '' }
    api.commandState = 'busy'
    const other = [{ name: 'other', path: '/home/me/other' }]
    await manager.sendMessage(SID, 't1', 'x', {
      sources: [file('/home/me/elsewhere/a.l4', 'a')],
      workspaceFolders: other,
    })
    await manager.sendMessage(SID, 't2', 'y', {
      sources: [file('/home/me/elsewhere/b.l4', 'b')],
      workspaceFolders: other,
    })
    assert.deepEqual(asked, ['ws'])
    assert.deepEqual(
      api.batches.map((b) => b.files.map((f) => f.path)),
      [['data/a.l4'], ['data/b.l4']]
    )
  })

  test('without a seed base, files use workspace-relative paths', async () => {
    const { api, manager } = setup()
    api.commandState = 'busy'
    await manager.sendMessage(SID, 't', 'x', {
      sources: [file('/ws/rules/a.l4', 'a')],
      workspaceFolders: folders,
    })
    assert.deepEqual(
      api.batches[0]!.files.map((f) => f.path),
      ['data/rules/a.l4']
    )
  })
})

describe('CloudSessionManager.replayed', () => {
  test('waits for the opened log to be read; then the state is current', async () => {
    const { api, clock, manager } = setup()
    api.state = 'sleeping'
    // The log passes through busy; the session is asleep now.
    api.pending = [ev({ type: 'session-state', state: 'busy' })]
    await manager.open(SID)
    let done = false
    const waiting = manager.replayed(SID).then(() => (done = true))
    await Promise.resolve()
    assert.equal(done, false)
    await clock.advance(0)
    await waiting
    assert.equal(manager.stateOf(SID), 'sleeping')
    // Nothing left to wait for, nor for a session never opened.
    await manager.replayed(SID)
    await manager.replayed('01JZZZZZZZZZZZZZZZZZZZZZZZ')
  })

  test('gives up after its timeout', async () => {
    const { manager } = setup()
    await manager.open(SID)
    // No poll ran (the clock didn't move): the timeout ends the wait.
    await manager.replayed(SID, 5)
  })
})

describe('CloudSessionManager.mcpServerLabels', () => {
  test('maps stored server names back to the names here', () => {
    const mcp: McpServerSource = {
      enabledServers: () => [
        {
          id: 'Docs Server',
          url: 'https://docs.example/mcp',
          transport: 'http',
        },
      ],
      headersFor: async () => ({}),
    }
    const { manager } = setup({ mcp })
    assert.deepEqual(manager.mcpServerLabels(['Docs_Server', 'Gone_Server']), [
      'Docs Server',
      'Gone_Server',
    ])
  })
})
