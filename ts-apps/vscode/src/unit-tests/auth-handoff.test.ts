import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import {
  buildLoginUrl,
  challengeFor,
  createPendingLogin,
  exchangeHandoffCode,
  isPendingLoginFresh,
  parseAuthCallback,
  parsePendingLogin,
  PENDING_LOGIN_TTL_MS,
} from '../auth-handoff.js'

describe('createPendingLogin', () => {
  test('pairs a fresh verifier with its S256 challenge', () => {
    const a = createPendingLogin(1000)
    const b = createPendingLogin(1000)
    assert.notEqual(a.pending.verifier, b.pending.verifier)
    assert.match(a.pending.verifier, /^[A-Za-z0-9_-]{43}$/)
    assert.equal(a.challenge, challengeFor(a.pending.verifier))
    assert.match(a.challenge, /^[A-Za-z0-9_-]{43}$/)
    assert.equal(a.pending.createdAt, 1000)
  })

  test('uses the RFC 7636 S256 transform', () => {
    // RFC 7636 appendix B example.
    assert.equal(
      challengeFor('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM'
    )
  })
})

describe('buildLoginUrl', () => {
  test('opens the console with the callback and the challenge', () => {
    const url = new URL(
      buildLoginUrl(
        'https://legalese.com/console',
        'vscode://legalese.l4-vscode/auth-callback',
        'abc'
      )
    )
    assert.equal(url.origin + url.pathname, 'https://legalese.com/console')
    assert.equal(
      url.searchParams.get('redirect_to'),
      'vscode://legalese.l4-vscode/auth-callback'
    )
    assert.equal(url.searchParams.get('code_challenge'), 'abc')
    assert.equal(url.searchParams.get('code_challenge_method'), 'S256')
  })
})

describe('parseAuthCallback', () => {
  test('reads a hand-off code, a legacy token, or nothing', () => {
    assert.deepEqual(parseAuthCallback('code=h1.x'), {
      kind: 'code',
      code: 'h1.x',
    })
    assert.deepEqual(parseAuthCallback('token=sealed'), {
      kind: 'token',
      token: 'sealed',
    })
    assert.deepEqual(parseAuthCallback(''), { kind: 'none' })
  })

  test('prefers the code when both are present', () => {
    assert.deepEqual(parseAuthCallback('token=sealed&code=h1.x'), {
      kind: 'code',
      code: 'h1.x',
    })
  })
})

describe('pending login', () => {
  test('parses what was stored and rejects junk', () => {
    const p = { verifier: 'v', createdAt: 5 }
    assert.deepEqual(parsePendingLogin(JSON.stringify(p)), p)
    assert.equal(parsePendingLogin(undefined), undefined)
    assert.equal(parsePendingLogin('not json'), undefined)
    assert.equal(parsePendingLogin('{"verifier":1}'), undefined)
  })

  test('is fresh only within the TTL', () => {
    const p = { verifier: 'v', createdAt: 10_000 }
    assert.equal(isPendingLoginFresh(p, 10_000), true)
    assert.equal(
      isPendingLoginFresh(p, 10_000 + PENDING_LOGIN_TTL_MS - 1),
      true
    )
    assert.equal(isPendingLoginFresh(p, 10_000 + PENDING_LOGIN_TTL_MS), false)
    assert.equal(isPendingLoginFresh(p, 9_000), false)
    assert.equal(isPendingLoginFresh(undefined), false)
  })
})

describe('exchangeHandoffCode', () => {
  test('posts code and verifier, returns the token', async () => {
    let seen: { url: string; body: string } | undefined
    const token = await exchangeHandoffCode(
      async (url, init) => {
        seen = { url, body: init.body }
        return {
          ok: true,
          status: 200,
          json: async () => ({ token: 'sealed' }),
        }
      },
      'legalese.cloud',
      'h1.code',
      'verifier'
    )
    assert.equal(token, 'sealed')
    assert.equal(seen?.url, 'https://legalese.cloud/auth/exchange')
    assert.deepEqual(JSON.parse(seen!.body), {
      code: 'h1.code',
      code_verifier: 'verifier',
    })
  })

  test('fails on a refused code or a body without a token', async () => {
    await assert.rejects(
      exchangeHandoffCode(
        async () => ({ ok: false, status: 400, json: async () => ({}) }),
        'legalese.cloud',
        'c',
        'v'
      ),
      /HTTP 400/
    )
    await assert.rejects(
      exchangeHandoffCode(
        async () => ({ ok: true, status: 200, json: async () => ({}) }),
        'legalese.cloud',
        'c',
        'v'
      ),
      /no token/
    )
  })
})
