import { afterEach, beforeEach, describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import { readFile, writeFile } from 'node:fs/promises'
import { EventEmitter } from 'node:events'
import * as path from 'node:path'
import {
  ConfigError,
  parseCloudEnv,
  parseDevArgs,
  type HarnessConfig,
} from '../src/config.js'
import { claimDevRun, initSessionFolder } from '../src/dev.js'
import { JsonLogger, redact } from '../src/logger.js'
import { Jl4Lsp } from '../src/jl4-lsp.js'
import {
  childEnv,
  installFatalHandlers,
  main,
  runHarness,
} from '../src/main.js'
import {
  HOST_PATH,
  MemoryLogger,
  SID,
  silent,
  tempDir,
  writeFakeLsp,
} from './helpers.js'

const good = {
  SESSION_ID: SID,
  SESSION_RUN: '7',
  AGENT_KEY: 'sk_live_abcdefgh12345',
  AI_URL: 'https://ai.legalese.cloud/',
  MCP_URL: 'https://mcp.legalese.cloud',
  AUTH_URL: 'https://legalese.cloud',
  LOG_LEVEL: 'info',
}

describe('parseCloudEnv', () => {
  test('accepts the documented environment', () => {
    const cfg = parseCloudEnv({
      ...good,
      TASK_ID: 'abc-123',
    })
    assert.equal(cfg.mode, 'cloud')
    assert.equal(cfg.run, 7)
    assert.equal(cfg.root, '/workspace')
    assert.equal(cfg.aiUrl, 'https://ai.legalese.cloud')
    assert.equal(cfg.taskId, 'abc-123')
  })

  for (const [name, value, re] of [
    ['SESSION_ID', 'not-a-ulid', /ULID/],
    ['SESSION_ID', '../../etc', /ULID/],
    ['SESSION_RUN', undefined, /SESSION_RUN/],
    ['SESSION_RUN', '0', /SESSION_RUN/],
    ['SESSION_RUN', '07', /SESSION_RUN/],
    ['SESSION_RUN', '1/../2', /SESSION_RUN/],
    ['SESSION_RUN', '1234567890', /SESSION_RUN/],
    ['AGENT_KEY', 'pk_nope', /sk_/],
    ['AI_URL', 'http://ai.legalese.cloud', /https/],
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

  test('ignores a TASK_ID that is not a plain id', () => {
    const cfg = parseCloudEnv({
      ...good,
      TASK_ID: '../x',
    })
    assert.equal(cfg.taskId, undefined)
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
    assert.equal(a.aiUrl, 'http://127.0.0.1:3000')
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
    // The server: end answers 204, renew refuses the key.
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

  const cfg = (lspCommand: string, run = 1): HarnessConfig => ({
    mode: 'cloud',
    sessionId: SID,
    run,
    agentKey: good.AGENT_KEY,
    root,
    aiUrl: 'https://ai.legalese.cloud',
    aiLocal: false,
    authUrl: 'https://legalese.cloud',
    logLevel: 'info',
    lspCommand,
  })

  test('when the session folder is missing', async () => {
    assert.equal(await runHarness(cfg('jl4-lsp'), {}, silent), 1)
    assert.deepEqual(calls, [END])
  })

  test('when a newer run exists, writing nothing', async () => {
    const sessionDir = await initSessionFolder(root, SID)
    await claimDevRun(root, SID)
    await claimDevRun(root, SID)
    const lease = path.join(sessionDir, 'state', 'runs', '1.lease.json')
    const before = await readFile(lease, 'utf8')
    assert.equal(await runHarness(cfg(await writeFakeLsp(root)), {}, silent), 0)
    assert.deepEqual(calls, [END])
    assert.equal(await readFile(lease, 'utf8'), before)
  })

  test('when the language server does not start', async () => {
    await initSessionFolder(root, SID)
    await claimDevRun(root, SID)
    await assert.rejects(
      runHarness(cfg(path.join(root, 'no-such-lsp')), {}, silent)
    )
    assert.deepEqual(calls, [END])
  })

  test('but not when the first renewal parks the session', async () => {
    const sessionDir = await initSessionFolder(root, SID)
    await claimDevRun(root, SID)
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

  test("drops a failed tool's error text and jl4-lsp's stderr, keeping an errno code", () => {
    assert.equal(
      redact(
        'tool/failed mcp__crm__lookup: MCP tool error: Record for Jane Doe, DOB 1980-01-02 not found'
      ),
      'tool/failed mcp__crm__lookup: [redacted]'
    )
    assert.equal(
      redact(
        "tool/failed fs__read_file: ENOENT: no such file or directory, open '/s/repo/data/Client X.l4'"
      ),
      'tool/failed fs__read_file: [redacted] (ENOENT)'
    )
    assert.equal(
      redact('jl4-lsp stderr: parse error in Client X.l4 near `the client`'),
      'jl4-lsp stderr: [redacted]'
    )
    assert.equal(redact('tool/unknown: fs__nope'), 'tool/unknown: fs__nope')
  })

  test('drops text= and body= tails', () => {
    assert.equal(
      redact('chat/request conv=c1 text=Draft the lease for Jane Doe'),
      'chat/request conv=c1 [redacted]'
    )
    assert.equal(
      redact('ai/error status=500 body={"error":"quote: Acme Ltd"}'),
      'ai/error status=500 [redacted]'
    )
  })
})

describe('--dev runs', () => {
  test('claims the next run as the Sessions API does', async () => {
    const { dir: root, cleanup } = await tempDir()
    try {
      const sessionDir = await initSessionFolder(root, SID)
      const runs = path.join(sessionDir, 'state', 'runs')
      assert.equal(
        await readFile(path.join(sessionDir, 'state', 'runs.seq'), 'utf8'),
        '0\n'
      )
      assert.equal(await claimDevRun(root, SID, 5_000), 1)
      assert.deepEqual(
        JSON.parse(await readFile(path.join(runs, '1.json'), 'utf8')),
        { run: 1, createdAt: 5_000 }
      )
      assert.deepEqual(
        JSON.parse(await readFile(path.join(runs, '1.lease.json'), 'utf8')),
        {
          run: 1,
          taskId: 'sessions-api',
          state: 'starting',
          expiresAt: 5_000 + 180_000,
        }
      )
      assert.equal(await claimDevRun(root, SID, 6_000), 2)
      assert.equal(
        await readFile(path.join(sessionDir, 'state', 'runs.seq'), 'utf8'),
        '2\n'
      )
    } finally {
      await cleanup()
    }
  })
})

describe('child processes', () => {
  const parent: NodeJS.ProcessEnv = {
    PATH: '/usr/bin',
    HOME: '/home/agent',
    TMPDIR: '/tmp/agent',
    AGENT_KEY: 'sk_live_abcdefgh12345',
    CLOUD_CREDENTIALS_URI: '/credentials/x',
    AI_URL: 'https://ai.legalese.cloud',
  }

  test('childEnv keeps only PATH, HOME, TMPDIR and a locale', () => {
    assert.deepEqual(childEnv(parent), {
      LANG: 'C.UTF-8',
      PATH: '/usr/bin',
      HOME: '/home/agent',
      TMPDIR: '/tmp/agent',
    })
  })

  test('the language server gets exactly that environment', async () => {
    const { dir, cleanup } = await tempDir()
    try {
      const out = path.join(dir, 'env.json')
      const fake = await writeFakeLsp(dir)
      // The fake records its environment first (into a fixed path: the
      // environment can't carry one).
      const script = await readFile(fake, 'utf8')
      const [shebang, ...rest] = script.split('\n')
      await writeFile(
        fake,
        [
          shebang,
          `require('node:fs').writeFileSync(${JSON.stringify(out)}, JSON.stringify(process.env))`,
          ...rest,
        ].join('\n')
      )
      const lsp = await Jl4Lsp.spawn({
        command: fake,
        root: dir,
        logger: silent,
        env: childEnv({ ...parent, PATH: HOST_PATH }),
      })
      await lsp.dispose(1_000)
      const env = JSON.parse(await readFile(out, 'utf8')) as Record<
        string,
        string
      >
      // macOS adds __CF_USER_TEXT_ENCODING to every process.
      delete env.__CF_USER_TEXT_ENCODING
      assert.deepEqual(Object.keys(env).sort(), [
        'HOME',
        'LANG',
        'PATH',
        'TMPDIR',
      ])
      assert.ok(!JSON.stringify(env).includes('sk_live'))
    } finally {
      await cleanup()
    }
  })
})

describe('installFatalHandlers', () => {
  test('an unhandled rejection runs the shutdown once, then exits non-zero', async () => {
    const proc = new EventEmitter() as EventEmitter & {
      exit: (c: number) => void
    }
    const exits: number[] = []
    proc.exit = (c) => exits.push(c)
    let failed = 0
    const logger = new MemoryLogger()
    const handlers = installFatalHandlers(
      { fail: async () => (failed++, 'error' as const) },
      logger,
      proc as unknown as Parameters<typeof installFatalHandlers>[2],
      10
    )
    proc.emit('unhandledRejection', new Error('EIO on commands.done'))
    proc.emit('uncaughtException', new Error('second'))
    assert.equal(failed, 1)
    assert.equal(handlers.fired(), true)
    assert.ok(logger.has('error', /unhandled error; shutting down/))
    await new Promise((r) => setTimeout(r, 30))
    assert.deepEqual(exits, [1])
    handlers.remove()
    assert.equal(proc.listenerCount('unhandledRejection'), 0)
    assert.equal(proc.listenerCount('uncaughtException'), 0)
  })
})
