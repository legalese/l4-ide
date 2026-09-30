import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import {
  AccessTokenManager,
  NotSignedInError,
  mintAgentKey,
  type AuthProxyDeps,
} from '../cloud/auth-proxy.js'
import {
  NO_COMMITS_YET_MESSAGE,
  SessionsApiClient,
  SessionsApiError,
  describeSessionsApiError,
} from '../cloud/sessions-api.js'

const SID = '01K6B8Z6X9Q4M2N7P3R5T8V0WA'
const KEY = 'sk_test_0123456789abcdef'

interface Call {
  url: string
  init: RequestInit
}

function fakeFetch(
  handler: (url: string, init: RequestInit) => Response | Promise<Response>
): { fetch: typeof fetch; calls: Call[] } {
  const calls: Call[] = []
  const f = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input)
    calls.push({ url, init: init ?? {} })
    return handler(url, init ?? {})
  }) as typeof fetch
  return { fetch: f, calls }
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function header(init: RequestInit, name: string): string | undefined {
  return (init.headers as Record<string, string> | undefined)?.[name]
}

function authDeps(
  f: typeof fetch,
  opts: { session?: string; now?: () => number } = {}
): AuthProxyDeps & { stored: string[] } {
  const stored: string[] = []
  let session = opts.session ?? 'sealed-1'
  return {
    stored,
    authBaseUrl: () => 'https://auth.example/',
    getSessionToken: async () => session || undefined,
    storeSessionToken: async (t) => {
      stored.push(t)
      session = t
    },
    fetch: f,
    now: opts.now,
  }
}

describe('AccessTokenManager', () => {
  test('caches until a minute before expiry, then refreshes', async () => {
    let now = 1_000_000
    let n = 0
    const { fetch, calls } = fakeFetch(() =>
      json(200, { accessToken: `jwt-${++n}`, expiresAt: now + 300_000 })
    )
    const tokens = new AccessTokenManager(authDeps(fetch, { now: () => now }))
    assert.equal(await tokens.get(), 'jwt-1')
    assert.equal(await tokens.get(), 'jwt-1')
    assert.equal(calls.length, 1)
    assert.equal(calls[0]!.url, 'https://auth.example/auth/access-token')
    assert.equal(header(calls[0]!.init, 'Authorization'), 'Bearer sealed-1')
    now += 241_000 // 59 s left
    assert.equal(await tokens.get(), 'jwt-2')
    assert.equal(await tokens.get({ force: true }), 'jwt-3')
  })

  test('concurrent callers share one refresh', async () => {
    const { fetch, calls } = fakeFetch(
      () =>
        new Promise((r) =>
          setTimeout(
            () =>
              r(
                json(200, {
                  accessToken: 'jwt',
                  expiresAt: Date.now() + 300_000,
                })
              ),
            5
          )
        )
    )
    const tokens = new AccessTokenManager(authDeps(fetch))
    const all = await Promise.all([tokens.get(), tokens.get(), tokens.get()])
    assert.deepEqual(all, ['jwt', 'jwt', 'jwt'])
    assert.equal(calls.length, 1)
  })

  test('stores a rotated sealed session', async () => {
    const { fetch, calls } = fakeFetch(() =>
      json(200, {
        accessToken: 'jwt',
        expiresAt: Date.now() + 300_000,
        token: 'sealed-2',
      })
    )
    const deps = authDeps(fetch)
    const tokens = new AccessTokenManager(deps)
    await tokens.get()
    assert.deepEqual(deps.stored, ['sealed-2'])
    await tokens.get({ force: true })
    assert.equal(header(calls[1]!.init, 'Authorization'), 'Bearer sealed-2')
  })

  test('not signed in: no session or 401', async () => {
    const { fetch } = fakeFetch(() => json(401, { error: 'unauthenticated' }))
    await assert.rejects(
      new AccessTokenManager(authDeps(fetch)).get(),
      NotSignedInError
    )
    await assert.rejects(
      new AccessTokenManager(authDeps(fetch, { session: '' })).get(),
      NotSignedInError
    )
  })
})

describe('mintAgentKey', () => {
  test('posts purpose and session id with the sealed session', async () => {
    const { fetch, calls } = fakeFetch(() =>
      json(200, {
        token: KEY,
        id: 'key_1',
        expiresAt: Date.now() + 900_000,
        permissions: ['ai:chat'],
      })
    )
    const res = await mintAgentKey(authDeps(fetch), SID)
    assert.equal(res.token, KEY)
    assert.equal(calls[0]!.url, 'https://auth.example/auth/agent-token')
    assert.equal(calls[0]!.init.method, 'POST')
    assert.deepEqual(JSON.parse(String(calls[0]!.init.body)), {
      purpose: 'cloud-session',
      sessionId: SID,
    })
  })

  test('surfaces the error code', async () => {
    const { fetch } = fakeFetch(() =>
      json(400, { error: 'invalid_session_id' })
    )
    await assert.rejects(mintAgentKey(authDeps(fetch), SID), (err: Error) =>
      /invalid_session_id/.test(err.message)
    )
  })
})

describe('SessionsApiClient', () => {
  function client(
    handler: (url: string, init: RequestInit) => Response | Promise<Response>
  ) {
    const { fetch, calls } = fakeFetch(handler)
    const forced: boolean[] = []
    const api = new SessionsApiClient({
      baseUrl: () => 'https://sessions.example/',
      getAccessToken: async (o) => {
        forced.push(Boolean(o?.force))
        return o?.force ? 'jwt-new' : 'jwt-old'
      },
      fetch,
    })
    return { api, calls, forced }
  }

  test('sends the bearer token and retries once after a 401', async () => {
    let n = 0
    const { api, calls, forced } = client(() =>
      ++n === 1
        ? json(401, { error: 'unauthenticated' })
        : json(200, { sessions: [] })
    )
    assert.deepEqual(await api.listSessions(), { sessions: [] })
    assert.deepEqual(forced, [false, true])
    assert.equal(calls[0]!.url, 'https://sessions.example/sessions')
    assert.equal(header(calls[1]!.init, 'Authorization'), 'Bearer jwt-new')
  })

  test('maps { error } bodies to SessionsApiError', async () => {
    const { api } = client(() => json(409, { error: 'too_many_sessions' }))
    await assert.rejects(api.startSession(SID, KEY), (err: unknown) => {
      assert.ok(err instanceof SessionsApiError)
      assert.equal(err.status, 409)
      assert.equal(err.code, 'too_many_sessions')
      assert.match(err.message, /Too many cloud sessions/)
      return true
    })
  })

  test('off while the API URL is empty', async () => {
    const api = new SessionsApiClient({
      baseUrl: () => '',
      getAccessToken: async () => 'jwt',
    })
    await assert.rejects(api.listSessions(), SessionsApiError)
  })

  test('validates commands before sending', async () => {
    const { api, calls } = client(() =>
      json(200, { commandId: 3, state: 'busy' })
    )
    assert.deepEqual(
      await api.postCommand(SID, { type: 'abort', turnId: 't1' }),
      { commandId: 3, state: 'busy' }
    )
    assert.equal(
      calls[0]!.url,
      `https://sessions.example/sessions/${SID}/commands`
    )
    await assert.rejects(
      api.postCommand(SID, { type: 'apply-bundle', file: 'x' } as never)
    )
    assert.equal(calls.length, 1)
  })

  test('uploads with the pre-signed headers', async () => {
    const { api, calls } = client(() => new Response(null, { status: 200 }))
    const body = new Uint8Array([1, 2, 3])
    await api.upload(
      {
        url: 'https://bucket.example/inbox/x',
        method: 'PUT',
        headers: { 'content-type': 'application/gzip', 'content-length': '3' },
      },
      body
    )
    assert.equal(calls[0]!.init.method, 'PUT')
    assert.equal(header(calls[0]!.init, 'content-type'), 'application/gzip')
    assert.equal(header(calls[0]!.init, 'Authorization'), undefined)
    await assert.rejects(
      api.upload(
        {
          url: 'https://bucket.example/x',
          method: 'PUT',
          headers: {},
          maxBytes: 2,
        },
        body
      ),
      SessionsApiError
    )
  })

  test('events: builds the query and drops invalid events', async () => {
    const { api, calls } = client(() =>
      json(200, {
        sessions: [
          {
            sessionId: SID,
            cursor: '1:120',
            state: 'busy',
            more: true,
            events: [
              {
                seq: 1,
                ts: 1,
                type: 'text-delta',
                conversationId: 'c1',
                text: 'hi',
              },
              { seq: 2, ts: 1, type: 'no-such-event' },
            ],
          },
          { sessionId: '01K6B8Z6X9Q4M2N7P3R5T8V0WB', error: 'not_found' },
        ],
      })
    )
    const res = await api.getEvents([
      { sessionId: SID, cursor: { segment: 0, offset: 0 } },
      {
        sessionId: '01K6B8Z6X9Q4M2N7P3R5T8V0WB',
        cursor: { segment: 2, offset: 5 },
      },
    ])
    assert.equal(
      calls[0]!.url,
      `https://sessions.example/events?s=${SID}%3A0&s=01K6B8Z6X9Q4M2N7P3R5T8V0WB%3A2%3A5`
    )
    const first = res.streams[0]!
    assert.ok(!('error' in first))
    assert.equal(first.events.length, 1)
    assert.equal(first.more, true)
    assert.deepEqual(res.streams[1], {
      sessionId: '01K6B8Z6X9Q4M2N7P3R5T8V0WB',
      error: 'not_found',
    })
  })
})

describe('describeSessionsApiError', () => {
  test('409 no_commits_yet reads as "Available after the first turn"', () => {
    assert.equal(
      describeSessionsApiError(409, 'no_commits_yet'),
      NO_COMMITS_YET_MESSAGE
    )
    assert.match(NO_COMMITS_YET_MESSAGE, /^Available after the first turn/)
  })
})
