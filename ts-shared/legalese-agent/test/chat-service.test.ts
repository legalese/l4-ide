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

  function build(
    files: Record<string, string>,
    options: { titleTimeoutMs?: number } = {}
  ): {
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
      ...options,
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

    const kinds = interaction.events
      .map((e) => e.kind)
      .filter((k) => k !== 'title')
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

  /** Replace fetch: the title request gets `title`, and a chat's stream
   *  stays open after its metadata frame until `release` is called. */
  function holdTurn(
    title: (signal?: AbortSignal | null) => Promise<Response>
  ): {
    release: () => void
  } {
    let release = () => {}
    const released = new Promise<void>((r) => (release = r))
    const encoder = new TextEncoder()
    globalThis.fetch = (async (_url: string, init?: RequestInit) => {
      const body = JSON.parse(String(init?.body ?? '{}')) as {
        model?: string
      }
      if (body.model === 'legalese-summize-4') return title(init?.signal)
      const stream = new ReadableStream<Uint8Array>({
        async start(controller) {
          const metadata = JSON.stringify({
            conversationId: 'conv1',
            model: 'm',
          })
          controller.enqueue(
            encoder.encode(`id: 1\nevent: metadata\ndata: ${metadata}\n\n`)
          )
          await released
          const reply = chunk({ content: 'Hello.' })
          const stop = chunk({}, 'stop')
          controller.enqueue(
            encoder.encode(`id: 2\n${reply}\n\nid: 3\n${stop}\n\n`)
          )
          controller.close()
        },
      })
      return new Response(stream, {
        status: 200,
        headers: { 'content-type': 'text/event-stream' },
      })
    }) as typeof fetch
    return { release: () => release() }
  }

  async function until(
    condition: () => boolean | Promise<boolean>
  ): Promise<void> {
    for (let i = 0; i < 200 && !(await condition()); i++) {
      await new Promise((r) => setTimeout(r, 5))
    }
    assert.ok(await condition(), 'timed out waiting')
  }

  const hasTitle = (interaction: RecordingInteraction) => () =>
    interaction.events.some((e) => e.kind === 'title')

  const firstTurn = {
    turnId: 'turn1',
    text: 'What does rules.l4 say?',
    mentions: [],
    attachments: [],
  }

  test('names a new conversation while its first turn runs', async () => {
    const { release } = holdTurn(async () =>
      sse([chunk({ content: 'A short title' }, 'stop')])
    )
    const { service, interaction, store } = build({})

    const turn = service.start(firstTurn)
    await until(hasTitle(interaction))

    assert.ok(!interaction.events.some((e) => e.kind === 'done'))
    assert.deepEqual(
      interaction.events.find((e) => e.kind === 'title'),
      { kind: 'title', conversationId: 'conv1', title: 'A short title' }
    )
    assert.equal((await store.load('conv1'))?.title, 'A short title')

    release()
    await turn
    // The title survives the turn being saved, and the other way around.
    const saved = await store.load('conv1')
    assert.equal(saved?.title, 'A short title')
    assert.equal(saved?.messages.length, 2)
  })

  test('names it from the first message when no title comes', async () => {
    const { release } = holdTurn(
      async () => new Response('nope', { status: 503 })
    )
    const { service, interaction } = build({})

    const turn = service.start(firstTurn)
    await until(hasTitle(interaction))

    assert.deepEqual(
      interaction.events.find((e) => e.kind === 'title'),
      {
        kind: 'title',
        conversationId: 'conv1',
        title: 'What does rules.l4 say?',
      }
    )
    release()
    await turn
  })

  test('names it from the first message when the title request stalls', async () => {
    const { release } = holdTurn(
      (signal) =>
        new Promise((_, reject) => {
          signal?.addEventListener('abort', () => reject(signal.reason))
        })
    )
    const { service, interaction } = build({}, { titleTimeoutMs: 5 })

    const turn = service.start(firstTurn)
    await until(hasTitle(interaction))

    assert.deepEqual(
      interaction.events.find((e) => e.kind === 'title'),
      {
        kind: 'title',
        conversationId: 'conv1',
        title: 'What does rules.l4 say?',
      }
    )
    release()
    await turn
  })

  test('does not write a title over a name the user chose', async () => {
    let respond: ((title: Response) => void) | undefined
    const { release } = holdTurn(
      () => new Promise<Response>((r) => (respond = r))
    )
    const { service, interaction, store } = build({})

    const turn = service.start(firstTurn)
    await until(async () => !!respond && !!(await store.load('conv1')))
    await store.setTitle('conv1', 'My own name')
    respond?.(sse([chunk({ content: 'A short title' }, 'stop')]))
    await until(hasTitle(interaction))

    assert.equal((await store.load('conv1'))?.title, 'My own name')
    release()
    await turn
  })

  test('asks for no title on a later turn', async () => {
    const { release } = holdTurn(async () => {
      throw new Error('a later turn should not ask for a title')
    })
    const { service, interaction } = build({})
    release()

    await service.start({ ...firstTurn, conversationId: 'conv1' })

    assert.ok(interaction.events.some((e) => e.kind === 'done'))
    assert.ok(!interaction.events.some((e) => e.kind === 'title'))
  })

  test('the store runs concurrent writes one at a time', async () => {
    const store = new FileConversationStore(storeDir, silentLogger, () => 'u1')
    await store.appendMessages('conv1', '', '', 'm', 'Seed', [])

    await Promise.all([
      ...Array.from({ length: 10 }, (_, i) =>
        store.update('conv1', (conv) => {
          conv.messages.push({ role: 'assistant', content: String(i) })
        })
      ),
      store.setTitle('conv1', 'A short title', { replacing: 'Seed' }),
    ])

    const saved = await store.load('conv1')
    assert.equal(saved?.title, 'A short title')
    assert.equal(saved?.messages.length, 10)
  })

  test('a delete waits for the writes ahead of it', async () => {
    const store = new FileConversationStore(storeDir, silentLogger, () => 'u1')
    await store.appendMessages('conv1', '', '', 'm', 'Seed', [])

    await Promise.all([
      ...Array.from({ length: 10 }, () =>
        store.update('conv1', (conv) => {
          conv.title = 'Changed'
        })
      ),
      store.delete('conv1'),
    ])

    assert.equal(await store.load('conv1'), null)
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
