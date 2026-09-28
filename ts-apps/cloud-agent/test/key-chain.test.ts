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
  now = (): number => 1_000_000
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
  })
}

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
    [403, 'inactive'],
    [409, 'chain_forked'],
  ] as const) {
    test(`${status} ${error} ends the chain`, async () => {
      const ended: ChainEnded[] = []
      const proxy = authProxy([{ status, body: { error } }])
      const auth = chain(proxy.fetch, (e) => ended.push(e))
      assert.equal(await auth.start(), false)
      assert.deepEqual(ended, [{ reason: error, fromServer: true }])
      assert.deepEqual(await auth.getAiAuthHeaders(), {})
    })
  }

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
    // The timer is due in max(1 s, 30 ms) = 1 s.
    now += 1_000
    await new Promise((r) => setTimeout(r, 1_100))
    auth.stopTimer()
    assert.equal(proxy.calls.length, 2)
    assert.equal(proxy.calls[1]!.auth, `Bearer ${key(1)}`)
    assert.equal(auth.isCurrent(`Bearer ${key(2)}`), true)
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
