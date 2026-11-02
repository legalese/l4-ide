import { afterEach, beforeEach, describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import { AiClient, AiError, type AuthProvider } from '../src/index.js'
import { silentLogger } from './fakes.js'

describe('AiClient.transcribe', () => {
  const realFetch = globalThis.fetch
  let calls: Array<{ url: string; init: RequestInit }>
  let respond: () => Response | Promise<Response>

  beforeEach(() => {
    calls = []
    respond = () => Response.json({ text: 'hello world' })
    globalThis.fetch = (async (url: string, init?: RequestInit) => {
      calls.push({ url, init: init ?? {} })
      return respond()
    }) as typeof fetch
  })

  afterEach(() => {
    globalThis.fetch = realFetch
  })

  function client(
    opts: { signedIn?: boolean; local?: boolean } = {}
  ): AiClient {
    const auth: AuthProvider = {
      getAiAuthHeaders: async (): Promise<Record<string, string>> =>
        opts.signedIn === false ? {} : { Authorization: 'Bearer token' },
      getEffectiveServiceUrl: () => undefined,
    }
    return new AiClient({
      auth,
      logger: silentLogger,
      endpoint: () => ({ url: 'https://ai.test', local: opts.local ?? false }),
    })
  }

  const wav = new Uint8Array([82, 73, 70, 70, 1, 2, 3])

  test('posts the clip as base64 WAV to the listen pipeline', async () => {
    const text = await client().transcribe(wav)
    assert.equal(text, 'hello world')
    assert.equal(calls[0]!.url, 'https://ai.test/v1/audio/transcriptions')
    const headers = calls[0]!.init.headers as Record<string, string>
    assert.equal(headers.Authorization, 'Bearer token')
    assert.deepEqual(JSON.parse(calls[0]!.init.body as string), {
      model: 'legalese-listen-4',
      input_audio: {
        data: Buffer.from(wav).toString('base64'),
        format: 'wav',
      },
    })
  })

  test('routes a deployment-bound chat to its path on the same origin', async () => {
    await client().transcribe(wav, 'https://ai.test/acme/tenancy/')
    assert.equal(
      calls[0]!.url,
      'https://ai.test/acme/tenancy/v1/audio/transcriptions'
    )
  })

  // The recording and the bearer token must never follow a base URL
  // that isn't the configured AI endpoint.
  test('ignores a base URL on any other origin', async () => {
    for (const foreign of [
      'https://evil.example/acme/tenancy',
      'http://ai.test/acme/tenancy',
      'not a url',
    ]) {
      await client().transcribe(wav, foreign)
    }
    assert.deepEqual(
      calls.map((c) => c.url),
      Array(3).fill('https://ai.test/v1/audio/transcriptions')
    )
  })

  test('fails fast when signed out, without sending the clip', async () => {
    await assert.rejects(
      client({ signedIn: false }).transcribe(wav),
      (err: unknown) => err instanceof AiError && err.status === 401
    )
    assert.equal(calls.length, 0)
  })

  // The auth provider decides per destination (the extension sends its
  // credentials only to Legalese Cloud), so it is told where each
  // request goes.
  test('asks for headers for the URL the request goes to', async () => {
    const asked: string[] = []
    const ai = new AiClient({
      auth: {
        getAiAuthHeaders: async (url) => {
          asked.push(url)
          return { Authorization: 'Bearer token' }
        },
        getEffectiveServiceUrl: () => undefined,
      },
      logger: silentLogger,
      endpoint: () => ({ url: 'https://ai.test', local: false }),
    })
    await ai.transcribe(wav, 'https://ai.test/acme/tenancy')
    await ai.summarizeTitle('hello')
    assert.deepEqual(asked, [
      'https://ai.test/acme/tenancy',
      'https://ai.test/v1/chat/completions',
    ])
  })

  test('local mode stands in a dev token', async () => {
    await client({ signedIn: false, local: true }).transcribe(wav)
    const headers = calls[0]!.init.headers as Record<string, string>
    assert.equal(headers.Authorization, 'Bearer dev-local')
  })

  test('an unreachable service is a network_error', async () => {
    respond = () => {
      throw new TypeError('fetch failed')
    }
    await assert.rejects(
      client().transcribe(wav),
      (err: unknown) => err instanceof AiError && err.code === 'network_error'
    )
  })

  test('carries the status and code of an error response', async () => {
    respond = () =>
      Response.json(
        { error: { message: 'too long', code: 'audio_too_long' } },
        { status: 413 }
      )
    await assert.rejects(
      client().transcribe(wav),
      (err: unknown) =>
        err instanceof AiError &&
        err.status === 413 &&
        err.code === 'audio_too_long'
    )
  })

  test('a response without text is an empty transcript', async () => {
    respond = () => Response.json({})
    assert.equal(await client().transcribe(wav), '')
  })
})
