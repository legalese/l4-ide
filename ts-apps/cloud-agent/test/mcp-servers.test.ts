import { afterEach, beforeEach, describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import { readFile, writeFile } from 'node:fs/promises'
import * as path from 'node:path'
import {
  encodeSealed,
  generateSealingKeyPair,
  mcpCredentialsContext,
  seal,
  type CloudCommand,
  type CloudEventPayload,
  type McpCredentials,
} from '@repo/legalese-agent/protocol'
import type { ToolProvider } from '@repo/legalese-agent'
import { initSessionFolder } from '../src/dev.js'
import { McpServers, wireName } from '../src/mcp-servers.js'
import type { RunnerContext } from '../src/runner.js'
import { MemoryLogger, SID, StubL4, tempDir } from './helpers.js'

interface Seen {
  url: string
  method: string
  auth: string | null
  session: string | null
}

/** Two fake MCP servers behind a fake fetch. */
function mcpFetch(opts: { sse?: boolean; status?: () => number } = {}): {
  fetch: typeof fetch
  seen: Seen[]
} {
  const seen: Seen[] = []
  const f = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input)
    const headers = new Headers(init?.headers)
    const body = JSON.parse(String(init?.body)) as {
      id?: number
      method: string
      params?: { name?: string; arguments?: Record<string, unknown> }
    }
    seen.push({
      url,
      method: body.method,
      auth: headers.get('authorization'),
      session: headers.get('mcp-session-id'),
    })
    const status = opts.status?.() ?? 200
    if (status !== 200) return new Response('no', { status })
    let result: unknown = {}
    if (body.method === 'tools/list') {
      result = {
        tools: [
          {
            name: 'search docs',
            description: 'Search',
            inputSchema: {
              type: 'object',
              properties: { q: { type: 'string' } },
            },
          },
          { name: 'hidden', description: 'Not enabled' },
        ],
      }
    } else if (body.method === 'tools/call') {
      result = {
        content: [
          { type: 'text', text: `found ${String(body.params?.arguments?.q)}` },
        ],
      }
    }
    const payload = JSON.stringify({ jsonrpc: '2.0', id: body.id, result })
    const respHeaders: Record<string, string> = { 'Mcp-Session-Id': 'sess-1' }
    if (opts.sse) {
      respHeaders['Content-Type'] = 'text/event-stream'
      return new Response(`event: message\ndata: ${payload}\n\n`, {
        headers: respHeaders,
      })
    }
    respHeaders['Content-Type'] = 'application/json'
    return new Response(body.id === undefined ? null : payload, {
      status: body.id === undefined ? 202 : 200,
      headers: respHeaders,
    })
  }) as typeof fetch
  return { fetch: f, seen }
}

describe('McpServers', () => {
  let root: string
  let cleanup: () => Promise<void>
  let ctx: RunnerContext
  let events: CloudEventPayload[]
  let logger: MemoryLogger
  let providers: ToolProvider[]

  beforeEach(async () => {
    ;({ dir: root, cleanup } = await tempDir())
    const sessionDir = await initSessionFolder(root, SID)
    const file = path.join(sessionDir, 'session.json')
    const session = JSON.parse(await readFile(file, 'utf8'))
    session.mcpServers = [
      {
        name: 'docs',
        url: 'https://docs.example.test/mcp',
        enabledTools: ['search docs'],
      },
      { name: 'crm', url: 'https://crm.example.test/mcp' },
    ]
    await writeFile(file, JSON.stringify(session))
    events = []
    providers = []
    logger = new MemoryLogger()
    ctx = {
      sessionId: SID,
      sessionDir,
      repoDir: path.join(sessionDir, 'repo'),
      stateDir: path.join(sessionDir, 'state'),
      logger,
      l4: new StubL4(),
      emit: (p) => events.push(p),
      announceState: () => undefined,
      providers,
      filesChanged: async () => undefined,
      summize: async () => null,
    }
  })
  afterEach(() => cleanup())

  function sealed(
    publicKey: string,
    creds: McpCredentials,
    context = mcpCredentialsContext(SID)
  ): CloudCommand {
    return {
      id: 1,
      ts: 1,
      type: 'mcp-credentials',
      sealed: encodeSealed(seal(publicKey, JSON.stringify(creds), context)),
    }
  }

  test('publishes a public key and registers as a tool provider', async () => {
    const mcp = new McpServers({ fetch: mcpFetch().fetch })
    await mcp.start(ctx)
    const { publicKey } = mcp.sessionStateFields()
    assert.match(publicKey ?? '', /^[A-Za-z0-9_-]{43}$/)
    assert.deepEqual(providers, [mcp])
    // Nothing is advertised before credentials arrive.
    assert.deepEqual(await mcp.listTools(), [])
  })

  test('connects with sealed credentials and calls tools', async () => {
    const f = mcpFetch()
    const mcp = new McpServers({ fetch: f.fetch })
    await mcp.start(ctx)
    await mcp.handleCommand(
      sealed(mcp.sessionStateFields().publicKey!, {
        servers: [
          { name: 'docs', headers: { Authorization: 'Bearer tok-1' } },
          { name: 'unknown', headers: { Authorization: 'Bearer x' } },
        ],
      })
    )
    const tools = await mcp.listTools()
    assert.deepEqual(
      tools.map((t) => t.function.name),
      [wireName('docs', 'search docs')]
    )
    assert.equal(tools[0]!.function.name, 'vsmcp__docs_search_docs')
    const out = await mcp.callTool('vsmcp__docs_search_docs', '{"q":"leases"}')
    assert.equal(out, 'found leases')
    const docs = f.seen.filter((s) => s.url.startsWith('https://docs'))
    assert.deepEqual(
      docs.map((s) => s.method),
      ['initialize', 'notifications/initialized', 'tools/list', 'tools/call']
    )
    assert.ok(docs.every((s) => s.auth === 'Bearer tok-1'))
    assert.equal(docs.at(-1)!.session, 'sess-1')
    // crm got no credentials: never contacted.
    assert.ok(!f.seen.some((s) => s.url.startsWith('https://crm')))
    // Credentials never reach the logs.
    assert.ok(!logger.lines.some((l) => l.message.includes('tok-1')))
  })

  test('reads SSE responses', async () => {
    const mcp = new McpServers({ fetch: mcpFetch({ sse: true }).fetch })
    await mcp.start(ctx)
    await mcp.handleCommand(
      sealed(mcp.sessionStateFields().publicKey!, {
        servers: [{ name: 'crm', headers: {} }],
      })
    )
    const tools = await mcp.listTools()
    assert.equal(tools.length, 2)
    assert.equal(
      await mcp.callTool(wireName('crm', 'search docs'), '{"q":"x"}'),
      'found x'
    )
  })

  test('ignores credentials sealed for another session or key', async () => {
    const mcp = new McpServers({ fetch: mcpFetch().fetch })
    await mcp.start(ctx)
    const other = generateSealingKeyPair()
    await mcp.handleCommand(
      sealed(other.publicKey, { servers: [{ name: 'docs', headers: {} }] })
    )
    await mcp.handleCommand(
      sealed(
        mcp.sessionStateFields().publicKey!,
        { servers: [{ name: 'docs', headers: {} }] },
        mcpCredentialsContext('01J9Z3K4M5N6P7Q8R9S0T1V2W9')
      )
    )
    assert.deepEqual(await mcp.listTools(), [])
    assert.equal(
      logger.lines.filter((l) => /could not be opened/.test(l.message)).length,
      2
    )
  })

  test('asks for new credentials on 401, once, and recovers when they arrive', async () => {
    let status = 200
    const f = mcpFetch({ status: () => status })
    const mcp = new McpServers({ fetch: f.fetch })
    await mcp.start(ctx)
    const pub = mcp.sessionStateFields().publicKey!
    await mcp.handleCommand(
      sealed(pub, {
        servers: [{ name: 'docs', headers: { Authorization: 'Bearer old' } }],
      })
    )
    await mcp.listTools()
    status = 401
    await assert.rejects(
      mcp.callTool('vsmcp__docs_search_docs', '{}'),
      /reconnect/
    )
    await assert.rejects(mcp.callTool('vsmcp__docs_search_docs', '{}'))
    assert.deepEqual(events, [
      { type: 'auth-required', reason: 'mcp', server: 'docs' },
    ])
    status = 200
    // The same command again is harmless; new headers replace the old.
    await mcp.handleCommand(
      sealed(pub, {
        servers: [{ name: 'docs', headers: { Authorization: 'Bearer new' } }],
      })
    )
    await mcp.listTools()
    assert.equal(
      await mcp.callTool('vsmcp__docs_search_docs', '{"q":"again"}'),
      'found again'
    )
    assert.equal(f.seen.at(-1)!.auth, 'Bearer new')
  })

  test('reports expired credentials', async () => {
    let now = 1_000
    const mcp = new McpServers({ fetch: mcpFetch().fetch, now: () => now })
    await mcp.start(ctx)
    await mcp.handleCommand(
      sealed(mcp.sessionStateFields().publicKey!, {
        servers: [{ name: 'docs', headers: {}, expiresAt: 5_000 }],
      })
    )
    await mcp.listTools()
    now = 6_000
    await assert.rejects(
      mcp.callTool('vsmcp__docs_search_docs', '{}'),
      /expired/
    )
    assert.deepEqual(events, [
      { type: 'auth-required', reason: 'mcp', server: 'docs' },
    ])
  })
})
