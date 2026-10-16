import { afterEach, describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import { AiProxyClient, type AuthProvider } from '../src/index.js'
import { silentLogger } from './fakes.js'

const chunk = (delta: unknown, finish?: string): string =>
  `data: ${JSON.stringify({
    choices: [{ delta, ...(finish ? { finish_reason: finish } : {}) }],
  })}`

function sse(frames: string[]): Response {
  return new Response(frames.map((f, i) => `id: ${i + 1}\n${f}\n\n`).join(''), {
    status: 200,
    headers: { 'content-type': 'text/event-stream' },
  })
}

function client(headers: Record<string, string>): AiProxyClient {
  const auth: AuthProvider = {
    getAiAuthHeaders: async () => ({ ...headers }),
    getEffectiveServiceUrl: () => undefined,
  }
  return new AiProxyClient({
    auth,
    logger: silentLogger,
    endpoint: () => ({ url: 'https://ai.test', local: false }),
  })
}

describe('AiProxyClient.summize', () => {
  const realFetch = globalThis.fetch
  afterEach(() => {
    globalThis.fetch = realFetch
  })

  test('one stateless summize call returns the trimmed text', async () => {
    const seen: Array<{ url: string; init: RequestInit }> = []
    globalThis.fetch = (async (url: string, init?: RequestInit) => {
      seen.push({ url, init: init ?? {} })
      return sse([
        chunk({ content: '  Add a late fee ' }),
        chunk({ content: 'rule\n' }, 'stop'),
      ])
    }) as typeof fetch
    const out = await client({
      Authorization: 'Bearer k',
      'X-Legalese-Session': 's1',
    }).summize([
      { role: 'system', content: 'rules' },
      { role: 'user', content: 'input' },
    ])
    assert.equal(out, 'Add a late fee rule')
    assert.equal(seen.length, 1)
    assert.equal(seen[0]!.url, 'https://ai.test/v1/chat/completions')
    const body = JSON.parse(String(seen[0]!.init.body)) as Record<
      string,
      unknown
    >
    // Stateless: the summize model, the messages, and nothing else.
    assert.deepEqual(body, {
      model: 'legalese-summize-4',
      messages: [
        { role: 'system', content: 'rules' },
        { role: 'user', content: 'input' },
      ],
    })
    const headers = new Headers(seen[0]!.init.headers)
    assert.equal(headers.get('authorization'), 'Bearer k')
    assert.equal(headers.get('x-legalese-session'), 's1')
  })

  test('null instead of throwing: HTTP error, empty answer, no credential', async () => {
    globalThis.fetch = (async () =>
      new Response('{"error":{"message":"nope"}}', {
        status: 500,
      })) as typeof fetch
    assert.equal(
      await client({ Authorization: 'Bearer k' }).summize([
        { role: 'user', content: 'x' },
      ]),
      null
    )
    globalThis.fetch = (async () =>
      sse([chunk({ content: '   ' }, 'stop')])) as typeof fetch
    assert.equal(
      await client({ Authorization: 'Bearer k' }).summize([
        { role: 'user', content: 'x' },
      ]),
      null
    )
    let called = 0
    globalThis.fetch = (async () => {
      called++
      return sse([chunk({ content: 'x' }, 'stop')])
    }) as typeof fetch
    assert.equal(
      await client({}).summize([{ role: 'user', content: 'x' }]),
      null
    )
    assert.equal(called, 0)
    globalThis.fetch = (async () => {
      throw new TypeError('fetch failed')
    }) as typeof fetch
    assert.equal(
      await client({ Authorization: 'Bearer k' }).summize([
        { role: 'user', content: 'x' },
      ]),
      null
    )
  })

  test('an aborted signal ends the call with null', async () => {
    globalThis.fetch = ((_url: string, init?: RequestInit) =>
      new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () =>
          reject(new DOMException('Aborted', 'AbortError'))
        )
      })) as typeof fetch
    const started = Date.now()
    const out = await client({ Authorization: 'Bearer k' }).summize(
      [{ role: 'user', content: 'x' }],
      { signal: AbortSignal.timeout(30) }
    )
    assert.equal(out, null)
    assert.ok(Date.now() - started < 2_000)
  })
})
