import { describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import { ConfigError, parseCloudEnv, parseDevArgs } from '../src/config.js'
import { JsonLogger, redact } from '../src/logger.js'
import { main } from '../src/main.js'
import { SID } from './helpers.js'

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
