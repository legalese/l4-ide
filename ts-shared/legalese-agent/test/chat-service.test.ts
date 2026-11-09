import { afterEach, beforeEach, describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import * as path from 'node:path'
import {
  AiProxyClient,
  BuiltinTools,
  ChatService,
  FileConversationStore,
  ToolDispatcher,
  fixedPermissionPolicy,
  type AuthProvider,
} from '../src/index.js'
import {
  FakeL4Language,
  MemoryWorkspace,
  RecordingInteraction,
  silentLogger,
} from './fakes.js'

/** One scripted ai-proxy response: SSE frames. */
type Script = string[]

function sse(frames: Script): Response {
  const body = frames.map((f, i) => `id: ${i + 1}\n${f}\n\n`).join('')
  return new Response(body, {
    status: 200,
    headers: { 'content-type': 'text/event-stream' },
  })
}

const chunk = (delta: unknown, finish?: string): string =>
  `data: ${JSON.stringify({
    choices: [{ delta, ...(finish ? { finish_reason: finish } : {}) }],
  })}`

const auth: AuthProvider = {
  getAiAuthHeaders: async () => ({ Authorization: 'Bearer test-key' }),
  getEffectiveServiceUrl: () => 'https://acme.legalese.cloud',
}

describe('ChatService with fake ports', () => {
  const realFetch = globalThis.fetch
  let requests: Array<{ url: string; body: Record<string, unknown> }>
  let responses: Script[]
  let storeDir: string

  beforeEach(async () => {
    requests = []
    responses = []
    storeDir = await mkdtemp(path.join(tmpdir(), 'legalese-agent-test-'))
    globalThis.fetch = (async (url: string, init?: RequestInit) => {
      const body = JSON.parse(String(init?.body ?? '{}')) as Record<
        string,
        unknown
      >
      requests.push({ url, body })
      if (body.model === 'legalese-summize-4') {
        return sse([chunk({ content: 'A short title' }, 'stop')])
      }
      const next = responses.shift()
      if (!next) throw new Error('unexpected request')
      return sse(next)
    }) as typeof fetch
  })

  afterEach(async () => {
    globalThis.fetch = realFetch
    await rm(storeDir, { recursive: true, force: true })
  })

  function build(files: Record<string, string>): {
    service: ChatService
    interaction: RecordingInteraction
    store: FileConversationStore
    ws: MemoryWorkspace
  } {
    const ws = new MemoryWorkspace(files)
    const l4 = new FakeL4Language(ws)
    const interaction = new RecordingInteraction()
    const store = new FileConversationStore(storeDir, silentLogger, () => 'u1')
    const proxy = new AiProxyClient({
      auth,
      logger: silentLogger,
      endpoint: () => ({ url: 'https://ai.test', local: false }),
    })
    const dispatcher = new ToolDispatcher({
      logger: silentLogger,
      tools: new BuiltinTools(ws, l4),
      permissions: fixedPermissionPolicy(),
      interaction,
    })
    const service = new ChatService({
      auth,
      store,
      proxy,
      logger: silentLogger,
      dispatcher,
      interaction,
      l4,
      extensionVersion: 'test',
    })
    return { service, interaction, store, ws }
  }

  test('runs a turn with a tool round and persists it', async () => {
    responses.push(
      [
        `event: metadata\ndata: ${JSON.stringify({ conversationId: 'conv1', model: 'm1' })}`,
        chunk({
          tool_calls: [
            {
              index: 0,
              id: 'call1',
              function: {
                name: 'fs__read_file',
                arguments: JSON.stringify({ path: 'rules.l4' }),
              },
            },
          ],
        }),
        chunk({}, 'tool_calls'),
      ],
      [chunk({ content: 'It says hi.' }), chunk({}, 'stop')]
    )
    const { service, interaction, store } = build({ 'rules.l4': 'hi' })

    await service.start({
      turnId: 'turn1',
      text: 'What does rules.l4 say?',
      mentions: [],
      attachments: [],
    })

    // Two model calls (plus the background title call).
    const chats = requests.filter((r) => r.body.model !== 'legalese-summize-4')
    assert.equal(chats.length, 2)
    assert.equal(chats[0]!.url, 'https://ai.test/v1/chat/completions')
    const firstMessages = chats[0]!.body.messages as Array<{
      role: string
      content: unknown
    }>
    // Headless: no editor context, but session context and workspace
    // exports on the first turn, then the user's message.
    assert.deepEqual(
      firstMessages.map((m) => m.role),
      ['system', 'system', 'user']
    )
    assert.match(
      String(firstMessages[0]!.content),
      /deploymentUrl: https:\/\/acme.legalese.cloud/
    )
    assert.match(String(firstMessages[1]!.content), /\(no L4 file open\)/)
    // The tool result goes back on the second request.
    const second = chats[1]!.body.messages as Array<{
      role: string
      content: string
      tool_call_id?: string
    }>
    assert.deepEqual(second, [
      {
        role: 'tool',
        content: '[rules.l4 1-1/1]\nhi',
        tool_call_id: 'call1',
        name: 'fs__read_file',
      },
    ])
    assert.equal(chats[1]!.body.conversationId, 'conv1')

    const kinds = interaction.events.map((e) => e.kind)
    assert.deepEqual(kinds, ['started', 'tool-call', 'text-delta', 'done'])
    assert.deepEqual(
      interaction.statuses.map((s) => [s.status, s.ctx]),
      [
        ['running', { conversationId: 'conv1', turnId: 'turn1' }],
        ['done', { conversationId: 'conv1', turnId: 'turn1' }],
      ]
    )

    const saved = await store.load('conv1')
    assert.ok(saved)
    assert.equal(saved.messages.length, 2)
    assert.equal(saved.messages[1]!.role, 'assistant')
    assert.equal(saved.messages[1]!.content, 'It says hi.')
    // Let the background title request settle before fetch is restored.
    await new Promise((r) => setTimeout(r, 20))
    assert.equal((await store.load('conv1'))?.title, 'A short title')
  })

  test('surfaces proxy errors as error events', async () => {
    globalThis.fetch = (async () =>
      new Response(
        JSON.stringify({ error: { message: 'slow down', code: 'rate' } }),
        { status: 429 }
      )) as typeof fetch
    const { service, interaction } = build({})
    await service.start({
      turnId: 't',
      text: 'hi',
      mentions: [],
      attachments: [],
    })
    assert.deepEqual(interaction.events, [
      {
        kind: 'error',
        conversationId: 't',
        message: 'slow down',
        code: 'rate',
      },
    ])
  })
})
