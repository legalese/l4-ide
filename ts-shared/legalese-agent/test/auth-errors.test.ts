import { afterEach, describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import {
  AiProxyClient,
  AiProxyError,
  isInvalidCredentialsBody,
  type AuthProvider,
} from '../src/index.js'
import { silentLogger } from './fakes.js'

// What ai-proxy answers a key or session it no longer accepts with
// (src/index.ts: every reason but `no-credentials` is a 403).
const INVALID_CREDENTIALS = {
  error: { message: 'Authentication failed: invalid-credentials' },
}

describe('ai-proxy auth errors', () => {
  const realFetch = globalThis.fetch
  afterEach(() => {
    globalThis.fetch = realFetch
  })

  function client(): AiProxyClient {
    const auth: AuthProvider = {
      getAiAuthHeaders: async () => ({ Authorization: 'Bearer k' }),
      getEffectiveServiceUrl: () => undefined,
    }
    return new AiProxyClient({
      auth,
      logger: silentLogger,
      endpoint: () => ({ url: 'https://ai.test', local: false }),
    })
  }

  async function streamError(res: Response): Promise<AiProxyError> {
    globalThis.fetch = (async () => res) as typeof fetch
    const events = client().stream(
      { messages: [{ role: 'user', content: 'hi' }], stream: true },
      new AbortController().signal
    )
    let caught: unknown
    await events.next().catch((err: unknown) => {
      caught = err
    })
    assert.ok(caught instanceof AiProxyError, 'stream did not throw')
    return caught
  }

  test('a 403 invalid-credentials is unauthenticated, like a 401', async () => {
    const err = await streamError(
      Response.json(INVALID_CREDENTIALS, { status: 403 })
    )
    assert.equal(err.code, 'unauthenticated')
    assert.equal(err.status, 403)
    assert.equal(err.message, 'Authentication failed: invalid-credentials')
  })

  test('any other 403 stays forbidden', async () => {
    const err = await streamError(
      Response.json(
        { error: { message: 'Origin not allowed' } },
        { status: 403 }
      )
    )
    assert.equal(err.code, 'forbidden')
    assert.equal(err.status, 403)
  })

  test('a 401 is unauthenticated', async () => {
    const err = await streamError(
      Response.json(
        { error: { message: 'Authentication failed: no-credentials' } },
        { status: 401 }
      )
    )
    assert.equal(err.code, 'unauthenticated')
  })

  test('isInvalidCredentialsBody', () => {
    assert.equal(
      isInvalidCredentialsBody(JSON.stringify(INVALID_CREDENTIALS)),
      true
    )
    assert.equal(
      isInvalidCredentialsBody('{"error":{"message":"Origin not allowed"}}'),
      false
    )
    assert.equal(isInvalidCredentialsBody(''), false)
  })
})
