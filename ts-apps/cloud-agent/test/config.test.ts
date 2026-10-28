import { afterEach, beforeEach, describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import { readFile, writeFile } from 'node:fs/promises'
import * as path from 'node:path'
import {
  ConfigError,
  parseCloudEnv,
  parseDevArgs,
  type HarnessConfig,
} from '../src/config.js'
import { initSessionFolder } from '../src/dev.js'
import { JsonLogger, redact } from '../src/logger.js'
import { main, runHarness } from '../src/main.js'
import { SID, silent, tempDir, writeFakeLsp } from './helpers.js'

const good = {
  SESSION_ID: SID,
  AGENT_KEY: 'sk_live_abcdefgh12345',
  AI_PROXY_URL: 'https://ai.legalese.cloud/',
  MCP_URL: 'https://mcp.legalese.cloud',
  AUTH_URL: 'https://legalese.cloud',
  LOG_LEVEL: 'info',
}

describe('parseCloudEnv', () => {
  test('accepts the documented environment', () => {
    const cfg = parseCloudEnv({
      ...good,
      ECS_CONTAINER_METADATA_URI_V4: 'http://169.254.170.2/v4/abc-123',
    })
    assert.equal(cfg.mode, 'cloud')
    assert.equal(cfg.root, '/workspace')
    assert.equal(cfg.aiProxyUrl, 'https://ai.legalese.cloud')
    assert.equal(cfg.taskMetadataUri, 'http://169.254.170.2/v4/abc-123')
  })

  for (const [name, value, re] of [
    ['SESSION_ID', 'not-a-ulid', /ULID/],
    ['SESSION_ID', '../../etc', /ULID/],
    ['AGENT_KEY', 'pk_nope', /sk_/],
    ['AI_PROXY_URL', 'http://ai.legalese.cloud', /https/],
    ['MCP_URL', 'https://user:pw@mcp.legalese.cloud', /credentials/],
    ['AUTH_URL', undefined, /required/],
    ['LOG_LEVEL', 'loud', /LOG_LEVEL/],
  ] as const) {
    test(`rejects ${name}=${value}`, () => {
      assert.throws(
        () => parseCloudEnv({ ...good, [name]: value }),
        (err: unknown) => err instanceof ConfigError && re.test(err.message)
      )
    })
  }

  test('ignores a task metadata URI that is not the Fargate endpoint', () => {
    const cfg = parseCloudEnv({
      ...good,
      ECS_CONTAINER_METADATA_URI_V4: 'http://evil.example/v4/x',
    })
    assert.equal(cfg.taskMetadataUri, undefined)
  })
})

describe('parseDevArgs', () => {
  test('parses flags', () => {
    const a = parseDevArgs([
      '--dev',
      '--root',
      '/tmp/x',
      '--session',
      SID,
      '--init',
    ])
    assert.equal(a.root, '/tmp/x')
    assert.equal(a.init, true)
    assert.equal(a.aiProxyUrl, 'http://127.0.0.1:3000')
    assert.equal(a.lspCommand, 'jl4-lsp')
  })
  test('requires a ULID session', () => {
    assert.throws(
      () => parseDevArgs(['--root', 'x', '--session', 'nope']),
      ConfigError
    )
  })
})

describe('main', () => {
  test('exits 2 on a bad environment without printing the key', async () => {
    const env: NodeJS.ProcessEnv = { ...good, SESSION_ID: 'bad' }
    const writes: string[] = []
    const orig = process.stderr.write.bind(process.stderr)
    process.stderr.write = ((s: string) => {
      writes.push(s)
      return true
    }) as typeof process.stderr.write
    try {
      assert.equal(await main([], env), 2)
    } finally {
      process.stderr.write = orig
    }
    assert.ok(!writes.join('').includes(good.AGENT_KEY))
  })
})

describe('runHarness ends the key chain on an early exit', () => {
  const RENEW = 'https://legalese.cloud/auth/agent-token/renew'
  const END = {
    url: 'https://legalese.cloud/auth/agent-token/end',
    auth: `Bearer ${good.AGENT_KEY}`,
  }
  const realFetch = globalThis.fetch
  let root: string
  let cleanup: () => Promise<void>
  let calls: Array<{ url: string; auth: string | null }>

  beforeEach(async () => {
    ;({ dir: root, cleanup } = await tempDir())
    calls = []
    // jl4-auth-proxy: end answers 204, renew refuses the key.
    globalThis.fetch = (async (input: string | URL | Request, init) => {
      const url = String(input)
      calls.push({ url, auth: new Headers(init?.headers).get('authorization') })
      return url === RENEW
        ? new Response(JSON.stringify({ error: 'invalid_key' }), {
            status: 401,
          })
        : new Response(null, { status: 204 })
    }) as typeof fetch
  })

  afterEach(async () => {
    globalThis.fetch = realFetch
    await cleanup()
  })

  const cfg = (lspCommand: string): HarnessConfig => ({
    mode: 'cloud',
    sessionId: SID,
    agentKey: good.AGENT_KEY,
    root,
    aiProxyUrl: 'https://ai.legalese.cloud',
    aiLocal: false,
    authUrl: 'https://legalese.cloud',
    logLevel: 'info',
    lspCommand,
  })

  test('when the session folder is missing', async () => {
    assert.equal(await runHarness(cfg('jl4-lsp'), {}, silent), 1)
    assert.deepEqual(calls, [END])
  })

  test('when another task holds the lease', async () => {
    const sessionDir = await initSessionFolder(root, SID)
    await writeFile(
      path.join(sessionDir, 'state', 'lease.json'),
      JSON.stringify({
        taskId: 'other',
        state: 'running',
        expiresAt: Date.now() + 60_000,
      })
    )
    assert.equal(await runHarness(cfg(await writeFakeLsp(root)), {}, silent), 0)
    assert.deepEqual(calls, [END])
  })

  test('when the language server does not start', async () => {
    await initSessionFolder(root, SID)
    await assert.rejects(
      runHarness(cfg(path.join(root, 'no-such-lsp')), {}, silent)
    )
    assert.deepEqual(calls, [END])
  })

  test('but not when the first renewal parks the session', async () => {
    const sessionDir = await initSessionFolder(root, SID)
    assert.equal(await runHarness(cfg(await writeFakeLsp(root)), {}, silent), 0)
    assert.deepEqual(
      calls.map((c) => c.url),
      [RENEW]
    )
    const session = JSON.parse(
      await readFile(path.join(sessionDir, 'session.json'), 'utf8')
    )
    assert.equal(session.status, 'parked')
  })
})

describe('JsonLogger', () => {
  test('writes JSON lines and redacts content', () => {
    const lines: string[] = []
    const log = new JsonLogger('info', { sid: SID }, (l) => lines.push(l))
    log.debug('hidden')
    log.info(
      'tool/dispatch fs__read_file (category=fs.read) args={"path":"secret"}'
    )
    log.error('boom', new Error('x'.repeat(2000)))
    assert.equal(lines.length, 2)
    const first = JSON.parse(lines[0]!)
    assert.equal(first.sid, SID)
    assert.equal(
      first.msg,
      'tool/dispatch fs__read_file (category=fs.read) [redacted]'
    )
    const second = JSON.parse(lines[1]!)
    assert.ok(second.err.length <= 501)
    assert.equal(redact('ok'), 'ok')
  })
})
