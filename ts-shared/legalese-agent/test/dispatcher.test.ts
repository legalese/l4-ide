import { describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import {
  BUILTIN_TOOLS,
  BuiltinTools,
  PendingInteractions,
  ToolDispatcher,
  fixedPermissionPolicy,
  type ToolProvider,
} from '../src/index.js'
import {
  FakeL4Language,
  MemoryWorkspace,
  RecordingInteraction,
  silentLogger,
} from './fakes.js'

const ctxA = { conversationId: 'conv-a', turnId: 'turn-a' }
const ctxB = { conversationId: 'conv-b', turnId: 'turn-b' }

function dispatcher(
  opts: {
    files?: Record<string, string>
    permissions?: Parameters<typeof fixedPermissionPolicy>[0]
    providers?: ToolProvider[]
  } = {}
): {
  ws: MemoryWorkspace
  interaction: RecordingInteraction
  dispatcher: ToolDispatcher
} {
  const ws = new MemoryWorkspace(opts.files ?? {})
  const interaction = new RecordingInteraction()
  return {
    ws,
    interaction,
    dispatcher: new ToolDispatcher({
      logger: silentLogger,
      tools: new BuiltinTools(ws, new FakeL4Language(ws)),
      permissions: fixedPermissionPolicy(opts.permissions),
      interaction,
      providers: opts.providers,
    }),
  }
}

describe('ToolDispatcher', () => {
  test('runs an allowed tool and reports status with its context', async () => {
    const { dispatcher: d, interaction } = dispatcher({
      files: { 'a.txt': 'hello' },
    })
    const result = await d.run(
      { callId: 'c1', name: 'fs__read_file', argsJson: '{"path":"a.txt"}' },
      ctxA
    )
    assert.deepEqual(result, { ok: true, output: '[a.txt 1-1/1]\nhello' })
    assert.deepEqual(
      interaction.statuses.map((s) => [s.status, s.ctx.conversationId]),
      [
        ['running', 'conv-a'],
        ['done', 'conv-a'],
      ]
    )
  })

  test('refuses a category set to never', async () => {
    const { dispatcher: d } = dispatcher({
      permissions: { 'fs.read': 'never' },
    })
    const result = await d.run(
      { callId: 'c1', name: 'fs__read_file', argsJson: '{"path":"a"}' },
      ctxA
    )
    assert.equal(result.ok, false)
    assert.equal((result as { code?: string }).code, 'denied')
  })

  test('asks before deleting (the default) and honours a deny', async () => {
    const {
      ws,
      dispatcher: d,
      interaction,
    } = dispatcher({
      files: { 'a.txt': 'x' },
    })
    interaction.autoDecision = 'deny'
    const result = await d.run(
      { callId: 'c1', name: 'fs__delete_file', argsJson: '{"path":"a.txt"}' },
      ctxB
    )
    assert.equal(result.ok, false)
    assert.deepEqual(interaction.approvalRequests, [
      { callId: 'c1', ctx: ctxB },
    ])
    assert.equal(ws.get('a.txt'), 'x')
  })

  test('snapshots files before a mutating tool runs', async () => {
    const { dispatcher: d } = dispatcher({ files: { 'a.txt': 'before' } })
    await d.run(
      {
        callId: 'c1',
        name: 'fs__edit_file',
        argsJson: '{"path":"a.txt","old":"before","new":"after"}',
      },
      ctxA
    )
    assert.equal(d.snapshotFor('c1')?.before, 'before')
    assert.equal(d.snapshotFor('c1')?.relativePath, 'a.txt')
  })

  test('advertises provider tools after the built-ins and routes by prefix', async () => {
    const calls: string[] = []
    const provider: ToolProvider = {
      prefix: 'l4-rules__',
      listTools: async () => [
        {
          type: 'function',
          function: { name: 'l4-rules__tax', parameters: { type: 'object' } },
        },
      ],
      callTool: async (name, args) => {
        calls.push(`${name} ${args}`)
        return 'rule result'
      },
      getToolTarget: () => ({ deployId: 'dep', fnName: 'tax' }),
    }
    const broken: ToolProvider = {
      prefix: 'vsmcp__',
      listTools: () => {
        throw new Error('down')
      },
      callTool: async () => '',
    }
    const { dispatcher: d } = dispatcher({ providers: [provider, broken] })
    const tools = await d.listTools()
    assert.equal(tools.length, BUILTIN_TOOLS.length + 1)
    assert.equal(tools.at(-1)?.function.name, 'l4-rules__tax')
    assert.deepEqual(d.getToolTarget('l4-rules__tax'), {
      deployId: 'dep',
      fnName: 'tax',
    })
    const result = await d.run(
      { callId: 'c1', name: 'l4-rules__tax', argsJson: '{"x":1}' },
      ctxA
    )
    assert.deepEqual(result, { ok: true, output: 'rule result' })
    assert.deepEqual(calls, ['l4-rules__tax {"x":1}'])
  })

  test('unknown tools are refused', async () => {
    const { dispatcher: d } = dispatcher()
    const result = await d.run(
      { callId: 'c1', name: 'nope__x', argsJson: '{}' },
      ctxA
    )
    assert.equal((result as { code?: string }).code, 'unknown_tool')
  })
})

describe('PendingInteractions', () => {
  test('a new message in one conversation leaves the other conversation waiting', async () => {
    const p = new PendingInteractions()
    const a = p.requestApproval('call-a', ctxA)
    const b = p.requestApproval('call-b', ctxB)
    const q = p.askUser('q-a', ctxA)

    assert.equal(p.cancelConversation('conv-a'), 2)
    assert.equal(await a, 'deny')
    assert.equal(await q, '')
    assert.equal(p.pendingApprovalCount(), 1)

    assert.equal(p.decide('call-b', 'allow'), true)
    assert.equal(await b, 'allow')
  })

  test('stopping a turn only cancels that turn', async () => {
    const p = new PendingInteractions()
    const a = p.requestApproval('call-a', ctxA)
    p.requestApproval('call-b', ctxB)
    assert.equal(p.cancelTurn('turn-a'), 1)
    assert.equal(await a, 'deny')
    assert.equal(p.contextFor('call-b')?.turnId, 'turn-b')
  })

  test('early decisions are consumed by the later request', async () => {
    const p = new PendingInteractions()
    assert.equal(p.decide('call-a', 'allow', 'conv-a'), false)
    assert.equal(await p.requestApproval('call-a', ctxA), 'allow')
  })

  test('early decisions of a cancelled conversation are dropped', async () => {
    const p = new PendingInteractions()
    p.decide('call-a', 'allow', 'conv-a')
    p.decide('call-b', 'allow', 'conv-b')
    p.cancelConversation('conv-a')
    assert.equal(await p.requestApproval('call-b', ctxB), 'allow')
    const a = p.requestApproval('call-a', ctxA)
    assert.equal(p.pendingApprovalCount(), 1)
    p.decide('call-a', 'deny')
    assert.equal(await a, 'deny')
  })
})
