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
import { CloudSessionManager } from '../cloud/cloud-session-manager.js'
import type { McpServerSource } from '../cloud/mcp-transfer.js'
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
  mcpNames: string[] = []
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
        mcpServers: this.mcpNames.map((name) => ({
          name,
          url: `https://${name}.example/mcp`,
        })),
        ...(this.conversationId ? { conversationId: this.conversationId } : {}),
        ...(this.seedBase ? { seedBase: this.seedBase } : {}),
      },
    }
  }
  async startSession(_sid: string, agentKey: string) {
    this.log.push(`start:${agentKey}`)
    this.state = 'starting'
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
  const logger = new MemoryLogger()
  const manager = new CloudSessionManager({
    api,
    mintAgentKey: async () => ({ token: KEY }),
    mcp: opts.mcp,
    ...(opts.pick ? { pickLocalFolder: opts.pick } : {}),
    logger,
    listener: {
      chat: (e) => chat.push(e),
      cloudEvent: (e) => cloud.push(e),
      progress: (e) => {
        progress.push(e.phase)
        if (e.mcpServers) mcpListed.push(...e.mcpServers)
      },
    },
    poller: {
      now: clock.now,
      setTimer: clock.setTimer,
      clearTimer: clock.clearTimer,
    },
  })
  return { api, clock, chat, cloud, progress, mcpListed, manager, logger }
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

  test('a command to a sleeping session starts it', async () => {
    const { api, manager } = setup()
    api.commandState = 'sleeping'
    await manager.sendMessage(SID, 'turn-2', 'next')
    assert.deepEqual(api.log, ['command:message', `start:${KEY}`])
    api.log = []
    api.commandState = 'parked'
    await manager.answer(SID, 'call-1', 'yes')
    assert.deepEqual(
      api.log,
      ['command:answer'],
      'parked needs an explicit resume'
    )
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
      headersFor: async () => ({ Authorization: 'Bearer secret-token' }),
    }
    const { api, clock, manager } = setup({ mcp })
    api.mcpNames = ['Docs_Server']
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

    // Same key: nothing more. An MCP auth-required asks again.
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
