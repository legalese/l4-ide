import { describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import {
  KeyChainAuth,
  authRetryingFetch,
  type ChainEnded,
} from '../src/key-chain.js'
import { SID, silent } from './helpers.js'

const KEY0 = 'sk_initial_key_000'
const key = (n: number): string =>
  `sk_renewed_key_${String(n).padStart(3, '0')}`

interface Call {
  url: string
  auth: string | null
}

/** A scripted jl4-auth-proxy. */
function authProxy(
  script: Array<{ status: number; body?: unknown } | 'network'>
): { fetch: typeof fetch; calls: Call[] } {
  const calls: Call[] = []
  const f = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input)
    calls.push({ url, auth: new Headers(init?.headers).get('authorization') })
    const next = script.shift()
    if (!next) throw new Error('unexpected request')
    if (next === 'network') throw new TypeError('fetch failed')
    return new Response(
      next.body === undefined ? null : JSON.stringify(next.body),
      {
        status: next.status,
      }
    )
  }) as typeof fetch
  return { fetch: f, calls }
}

function chain(
  f: typeof fetch,
  onEnded: (e: ChainEnded) => void = () => undefined,
  now = (): number => 1_000_000,
  minRenewIntervalMs = 10
): KeyChainAuth {
  return new KeyChainAuth({
    authUrl: 'https://legalese.cloud/',
    sessionId: SID,
    initialKey: KEY0,
    logger: silent,
    onEnded,
    fetch: f,
    now,
    retryDelaysMs: [1, 1, 1],
    minRenewIntervalMs,
  })
}

const sleep = (ms: number): Promise<void> =>
  new Promise((r) => setTimeout(r, ms))

describe('KeyChainAuth', () => {
  test('renews at start, replacing the key from the environment', async () => {
    const proxy = authProxy([
      { status: 200, body: { token: key(1), id: 'k1', expiresAt: 1_900_000 } },
    ])
    const auth = chain(proxy.fetch)
    assert.equal(await auth.start(), true)
    auth.stopTimer()
    assert.deepEqual(proxy.calls, [
      {
        url: 'https://legalese.cloud/auth/agent-token/renew',
        auth: `Bearer ${KEY0}`,
      },
    ])
    assert.deepEqual(await auth.getAiAuthHeaders(), {
      Authorization: `Bearer ${key(1)}`,
      'X-Legalese-Session': SID,
    })
    assert.equal(auth.keyExpiresAt, 1_900_000)
  })

  for (const [status, error] of [
    [401, 'invalid_key'],
    [403, 'chain_expired'],
    [409, 'chain_forked'],
  ] as const) {
    test(`${status} ${error} ends the chain`, async () => {
      const ended: ChainEnded[] = []
      const proxy = authProxy([{ status, body: { error } }])
      const auth = chain(proxy.fetch, (e) => ended.push(e))
      assert.equal(await auth.start(), false)
      assert.equal(proxy.calls.length, 1)
      assert.deepEqual(ended, [{ reason: error, fromServer: true }])
      assert.deepEqual(await auth.getAiAuthHeaders(), {})
    })
  }

  for (const [status, error] of [
    [403, 'not_a_member'],
    [403, 'forbidden'],
  ] as const) {
    test(`${status} ${error ?? '(no body)'} ends the chain as invalid_key, without retrying`, async () => {
      const ended: ChainEnded[] = []
      const proxy = authProxy([{ status, body: error ? { error } : undefined }])
      const auth = chain(proxy.fetch, (e) => ended.push(e))
      assert.equal(await auth.start(), false)
      assert.equal(proxy.calls.length, 1)
      assert.deepEqual(ended, [{ reason: 'invalid_key', fromServer: true }])
    })
  }

  // jl4-auth-proxy deleted the key and couldn't mint its successor: a
  // retry would only present the dead key.
  for (const status of [410, 502]) {
    test(`${status} chain_lost ends the chain at once`, async () => {
      const ended: ChainEnded[] = []
      const proxy = authProxy([{ status, body: { error: 'chain_lost' } }])
      const auth = chain(proxy.fetch, (e) => ended.push(e))
      assert.equal(await auth.start(), false)
      assert.equal(proxy.calls.length, 1)
      assert.deepEqual(ended, [{ reason: 'invalid_key', fromServer: true }])
    })
  }

  test('retries a 429 like a server error', async () => {
    const ended: ChainEnded[] = []
    const proxy = authProxy([
      { status: 429, body: undefined },
      { status: 401, body: { error: 'invalid_key' } },
    ])
    const auth = chain(proxy.fetch, (e) => ended.push(e))
    assert.equal(await auth.start(), false)
    assert.equal(proxy.calls.length, 2)
    assert.deepEqual(ended, [{ reason: 'invalid_key', fromServer: true }])
  })

  test('retries 502 upstream_unavailable; a deleted key then ends as invalid_key', async () => {
    const ended: ChainEnded[] = []
    const proxy = authProxy([
      { status: 502, body: { error: 'upstream_unavailable' } },
      { status: 401, body: { error: 'invalid_key' } },
    ])
    const auth = chain(proxy.fetch, (e) => ended.push(e))
    assert.equal(await auth.start(), false)
    assert.equal(proxy.calls.length, 2)
    assert.deepEqual(ended, [{ reason: 'invalid_key', fromServer: true }])
  })

  test('retries transient failures and recovers', async () => {
    const proxy = authProxy([
      'network',
      { status: 502, body: { error: 'upstream_unavailable' } },
      { status: 200, body: { token: key(2), id: 'k2', expiresAt: 1_900_000 } },
    ])
    const auth = chain(proxy.fetch)
    assert.equal(await auth.start(), true)
    auth.stopTimer()
    assert.equal(auth.isCurrent(`Bearer ${key(2)}`), true)
  })

  test('gives up when transient failures outlast the retries', async () => {
    const ended: ChainEnded[] = []
    const proxy = authProxy(['network', 'network', 'network', 'network'])
    const auth = chain(proxy.fetch, (e) => ended.push(e))
    assert.equal(await auth.start(), false)
    assert.deepEqual(ended, [{ reason: 'invalid_key', fromServer: false }])
  })

  test('renews on schedule when 5 minutes are left', async () => {
    let now = 1_000_000
    const proxy = authProxy([
      // start: the new key expires 5 min + 30 ms from now
      {
        status: 200,
        body: { token: key(1), id: 'k1', expiresAt: now + 300_030 },
      },
      {
        status: 200,
        body: { token: key(2), id: 'k2', expiresAt: now + 900_000 },
      },
    ])
    const auth = chain(proxy.fetch, undefined, () => now)
    await auth.start()
    // The timer is due in max(10 ms interval, 30 ms) = 30 ms.
    now += 1_000
    await new Promise((r) => setTimeout(r, 1_100))
    auth.stopTimer()
    assert.equal(proxy.calls.length, 2)
    assert.equal(proxy.calls[1]!.auth, `Bearer ${key(1)}`)
    assert.equal(auth.isCurrent(`Bearer ${key(2)}`), true)
  })

  test('leaves the minimum interval between renewals, even for a key that comes back expired', async () => {
    const proxy = authProxy([
      { status: 200, body: { token: key(1), id: 'k1', expiresAt: 1 } },
      { status: 200, body: { token: key(2), id: 'k2', expiresAt: 1_900_000 } },
    ])
    const auth = chain(proxy.fetch, undefined, undefined, 300)
    await auth.start()
    await sleep(100)
    assert.equal(proxy.calls.length, 1)
    await sleep(400)
    auth.stopTimer()
    assert.equal(proxy.calls.length, 2)
    assert.equal(auth.isCurrent(`Bearer ${key(2)}`), true)
  })

  test('a 401 right after a renewal fails the request, then renews once the interval is up', async () => {
    let now = 1_000_000
    const proxy = authProxy([
      { status: 200, body: { token: key(1), id: 'k1', expiresAt: 1_900_000 } },
      { status: 200, body: { token: key(2), id: 'k2', expiresAt: 1_900_000 } },
      { status: 200, body: { token: key(3), id: 'k3', expiresAt: 1_900_000 } },
    ])
    const auth = chain(proxy.fetch, undefined, () => now, 200)
    await auth.start()
    assert.equal(await auth.renewAfterUnauthorized(`Bearer ${key(1)}`), false)
    assert.equal(await auth.renewAfterUnauthorized(`Bearer ${key(1)}`), false)
    assert.equal(proxy.calls.length, 1)
    await sleep(400)
    assert.equal(proxy.calls.length, 2)
    assert.equal(auth.isCurrent(`Bearer ${key(2)}`), true)
    // Once the interval is up, a 401 renews at once.
    now += 200
    assert.equal(await auth.renewAfterUnauthorized(`Bearer ${key(2)}`), true)
    auth.stopTimer()
    assert.equal(proxy.calls.length, 3)
    assert.equal(auth.isCurrent(`Bearer ${key(3)}`), true)
  })

  test('concurrent renewals share one request', async () => {
    const proxy = authProxy([
      { status: 200, body: { token: key(1), id: 'k1', expiresAt: 1_900_000 } },
    ])
    const auth = chain(proxy.fetch)
    const [a, b] = await Promise.all([
      auth.renewAfterUnauthorized(`Bearer ${KEY0}`),
      auth.renewAfterUnauthorized(`Bearer ${KEY0}`),
    ])
    assert.deepEqual([a, b], [true, true])
    assert.equal(proxy.calls.length, 1)
  })

  test('end deletes the initial key when the chain never started, once', async () => {
    const proxy = authProxy([{ status: 204 }])
    const auth = chain(proxy.fetch)
    await auth.end()
    await auth.end()
    assert.deepEqual(proxy.calls, [
      {
        url: 'https://legalese.cloud/auth/agent-token/end',
        auth: `Bearer ${KEY0}`,
      },
    ])
  })

  test('end does nothing once the chain ended', async () => {
    const proxy = authProxy([{ status: 401, body: { error: 'invalid_key' } }])
    const auth = chain(proxy.fetch)
    assert.equal(await auth.start(), false)
    await auth.end()
    assert.equal(proxy.calls.length, 1)
  })

  test('end deletes the current key', async () => {
    const proxy = authProxy([
      { status: 200, body: { token: key(1), id: 'k1', expiresAt: 1_900_000 } },
      { status: 204 },
    ])
    const auth = chain(proxy.fetch)
    await auth.start()
    await auth.end()
    assert.deepEqual(proxy.calls[1], {
      url: 'https://legalese.cloud/auth/agent-token/end',
      auth: `Bearer ${key(1)}`,
    })
  })
})

describe('authRetryingFetch', () => {
  test('renews and retries once on a 401 from ai-proxy', async () => {
    const renew = authProxy([
      { status: 200, body: { token: key(1), id: 'k1', expiresAt: 1_900_000 } },
    ])
    const auth = chain(renew.fetch)
    const seen: Array<string | null> = []
    const base = (async (
      _input: string | URL | Request,
      init?: RequestInit
    ) => {
      const a = new Headers(init?.headers).get('authorization')
      seen.push(a)
      return new Response('{}', { status: a === `Bearer ${KEY0}` ? 401 : 200 })
    }) as typeof fetch
    const wrapped = authRetryingFetch(base, auth, ['https://ai.legalese.cloud'])
    const res = await wrapped('https://ai.legalese.cloud/v1/chat/completions', {
      method: 'POST',
      headers: await auth.getAiAuthHeaders(),
      body: '{"x":1}',
    })
    assert.equal(res.status, 200)
    assert.deepEqual(seen, [`Bearer ${KEY0}`, `Bearer ${key(1)}`])
  })

  // ai-proxy answers a key it no longer accepts with 403, not 401.
  test('renews and retries once on a 403 invalid-credentials from ai-proxy', async () => {
    const renew = authProxy([
      { status: 200, body: { token: key(1), id: 'k1', expiresAt: 1_900_000 } },
    ])
    const auth = chain(renew.fetch)
    const seen: Array<string | null> = []
    const base = (async (
      _input: string | URL | Request,
      init?: RequestInit
    ) => {
      const a = new Headers(init?.headers).get('authorization')
      seen.push(a)
      return a === `Bearer ${KEY0}`
        ? Response.json(
            {
              error: { message: 'Authentication failed: invalid-credentials' },
            },
            { status: 403 }
          )
        : new Response('{}', { status: 200 })
    }) as typeof fetch
    const wrapped = authRetryingFetch(base, auth, ['https://ai.legalese.cloud'])
    const res = await wrapped('https://ai.legalese.cloud/v1/chat/completions', {
      method: 'POST',
      headers: await auth.getAiAuthHeaders(),
      body: '{"x":1}',
    })
    assert.equal(res.status, 200)
    assert.deepEqual(seen, [`Bearer ${KEY0}`, `Bearer ${key(1)}`])
    assert.equal(renew.calls.length, 1)
  })

  test('returns any other 403 unread, without renewing', async () => {
    const renew = authProxy([])
    const auth = chain(renew.fetch)
    let calls = 0
    const base = (async () => {
      calls++
      return Response.json(
        { error: { message: 'Origin not allowed' } },
        { status: 403 }
      )
    }) as typeof fetch
    const wrapped = authRetryingFetch(base, auth, ['https://ai.legalese.cloud'])
    const res = await wrapped('https://ai.legalese.cloud/v1/chat/completions', {
      method: 'POST',
      headers: await auth.getAiAuthHeaders(),
      body: '{"x":1}',
    })
    assert.equal(res.status, 403)
    assert.deepEqual(await res.json(), {
      error: { message: 'Origin not allowed' },
    })
    assert.equal(calls, 1)
    assert.equal(renew.calls.length, 0)
  })

  test('returns the 403 when the renewal ends the chain', async () => {
    const renew = authProxy([{ status: 401, body: { error: 'invalid_key' } }])
    const ended: ChainEnded[] = []
    const auth = chain(renew.fetch, (e) => ended.push(e))
    let calls = 0
    const base = (async () => {
      calls++
      return Response.json(
        { error: { message: 'Authentication failed: invalid-credentials' } },
        { status: 403 }
      )
    }) as typeof fetch
    const wrapped = authRetryingFetch(base, auth, ['https://ai.legalese.cloud'])
    const res = await wrapped('https://ai.legalese.cloud/v1/models', {
      headers: await auth.getAiAuthHeaders(),
    })
    assert.equal(res.status, 403)
    assert.match(await res.text(), /invalid-credentials/)
    assert.equal(calls, 1)
    assert.equal(ended.length, 1)
    assert.equal(ended[0]!.reason, 'invalid_key')
  })

  test('leaves other origins and other credentials alone', async () => {
    const renew = authProxy([])
    const auth = chain(renew.fetch)
    const base = (async () =>
      new Response('{}', { status: 401 })) as typeof fetch
    const wrapped = authRetryingFetch(base, auth, ['https://ai.legalese.cloud'])
    const other = await wrapped('https://mcp.example.com/mcp', {
      headers: { Authorization: `Bearer ${KEY0}` },
    })
    assert.equal(other.status, 401)
    const userToken = await wrapped('https://ai.legalese.cloud/x', {
      headers: { Authorization: 'Bearer user-oauth-token' },
    })
    assert.equal(userToken.status, 401)
    assert.equal(renew.calls.length, 0)
  })
})
