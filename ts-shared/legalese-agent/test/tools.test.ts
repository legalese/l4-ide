import { describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import {
  BuiltinTools,
  ToolDispatcher,
  fixedPermissionPolicy,
  FS_CREATE_FILE_SEED,
  formatL4Diagnostics,
  offsetAt,
  positionAt,
} from '../src/index.js'
import {
  FakeL4Language,
  MemoryWorkspace,
  RecordingInteraction,
  row,
  silentLogger,
  uriOf,
} from './fakes.js'

function session(files: Record<string, string>): {
  ws: MemoryWorkspace
  l4: FakeL4Language
  tools: BuiltinTools
} {
  const ws = new MemoryWorkspace(files)
  const l4 = new FakeL4Language(ws)
  return { ws, l4, tools: new BuiltinTools(ws, l4) }
}

describe('fs tools over the Workspace port', () => {
  test('read_file pages a file with the uniform header', async () => {
    const { tools } = session({ 'a.txt': 'one\ntwo\nthree' })
    assert.equal(
      await tools.readFile({ path: 'a.txt', startLine: 2 }),
      '[a.txt 2-3/3]\ntwo\nthree'
    )
  })

  test('read_file lists a directory, directories first', async () => {
    const { tools } = session({ 'b.txt': '', 'sub/c.l4': '', 'a.txt': '' })
    assert.equal(
      await tools.readFile({ path: '.' }),
      '[ws 1-3/3]\nsub/\na.txt\nb.txt'
    )
  })

  test('read_file greps a directory tree', async () => {
    const { tools } = session({
      'x/one.l4': 'DECIDE foo\nbar',
      'two.l4': 'nothing',
    })
    assert.equal(
      await tools.readFile({ path: '.', search_keywords: 'foo' }),
      '[ws/ keywords="foo" matches=1 files=1]\nws/x/one.l4:1: DECIDE foo'
    )
  })

  test('read_file rejects paths outside the workspace', async () => {
    const { tools } = session({})
    await assert.rejects(tools.readFile({ path: '/etc/passwd' }), /outside/)
  })

  test('create_file seeds the file and refuses to overwrite', async () => {
    const { ws, tools } = session({})
    const out = await tools.createFile({ path: 'dir/new.l4' })
    assert.match(out, /^Created dir\/new.l4 - seeded with/)
    assert.equal(ws.get('dir/new.l4'), FS_CREATE_FILE_SEED)
    await assert.rejects(tools.createFile({ path: 'dir/new.l4' }), /exists/)
  })

  test('edit_file keeps CRLF line endings and reports the edited range', async () => {
    const { ws, tools } = session({ 'a.txt': 'one\r\ntwo\r\nthree\r\n' })
    const out = await tools.editFile({
      path: 'a.txt',
      old: 'two\nthree',
      new: 'TWO\nTHREE\nFOUR',
    })
    assert.equal(ws.get('a.txt'), 'one\r\nTWO\r\nTHREE\r\nFOUR\r\n')
    assert.equal(out, '[a.txt 2-4] (Edited 2 → 3 lines)')
  })

  test('edit_file demands a unique anchor', async () => {
    const { tools } = session({ 'a.txt': 'x\nx\n' })
    await assert.rejects(
      tools.editFile({ path: 'a.txt', old: 'x', new: 'y' }),
      /appears 2 times/
    )
    const out = await tools.editFile({
      path: 'a.txt',
      old: 'x',
      new: 'y',
      startLine: 1,
    })
    assert.match(out, /^\[a.txt 2-2\]/)
  })

  test('edit_file on an .l4 file appends diagnostics when it fails to compile', async () => {
    const { l4, tools } = session({ 'a.l4': 'DECIDE x IS 1' })
    l4.diagnostics.set(uriOf('/ws/a.l4'), [
      { severity: 'error', line: 0, message: 'boom', source: 'jl4' },
    ])
    const out = await tools.editFile({ path: 'a.l4', old: '1', new: '2' })
    assert.match(out, /--- L4 diagnostics: 1 issue \(1 error\) ---/)
    assert.match(out, /error 1 → boom \[jl4\]/)
    assert.match(out, /search_l4_docs/)
  })

  test('delete_file reports what the workspace did', async () => {
    const { ws, tools } = session({ 'a.txt': '' })
    assert.equal(await tools.deleteFile({ path: 'a.txt' }), 'Deleted a.txt')
    assert.deepEqual(ws.deleted, ['a.txt'])
  })
})

describe('l4__evaluate', () => {
  test('returns diagnostics instead of results when the file has errors', async () => {
    const { l4, tools } = session({ 'a.l4': 'x' })
    l4.diagnostics.set(uriOf('/ws/a.l4'), [
      { severity: 'error', line: 2, message: 'bad' },
    ])
    assert.equal(
      await tools.evaluate({ path: 'a.l4' }),
      '--- L4 diagnostics: 1 issue (1 error) ---\nerror 3 → bad'
    )
  })

  test('snapshot stores are per session, not shared', async () => {
    const ws = new MemoryWorkspace({ 'a.l4': 'l1\nl2\nl3' })
    const l4 = new FakeL4Language(ws)
    const uri = uriOf('/ws/a.l4')
    l4.directives.record(uri, [row(1, '1'), row(2, '2')])
    const one = new BuiltinTools(ws, l4)
    const two = new BuiltinTools(ws, l4)

    // Session one establishes its baseline…
    assert.match(
      await one.evaluate({ path: 'a.l4', mode: 'changed' }),
      /2 changed/
    )
    assert.match(
      await one.evaluate({ path: 'a.l4', mode: 'changed' }),
      /2 unchanged/
    )
    // …which session two doesn't see: its first call still reports
    // everything as new.
    assert.match(
      await two.evaluate({ path: 'a.l4', mode: 'changed' }),
      /2 changed/
    )

    // A value change is reported once per session.
    l4.directives.record(uri, [row(1, '1'), row(2, '3')])
    assert.match(
      await one.evaluate({ path: 'a.l4', mode: 'changed' }),
      /--- L4 directives: 1 changed, 1 removed, 1 unchanged ---\n {2}2 → 3/
    )
    assert.match(
      await two.evaluate({ path: 'a.l4', mode: 'changed' }),
      /1 changed, 1 removed, 1 unchanged/
    )
  })

  test('snapshot stores are keyed by conversation as well as file', async () => {
    const ws = new MemoryWorkspace({ 'a.l4': 'l1\nl2\nl3' })
    const l4 = new FakeL4Language(ws)
    const uri = uriOf('/ws/a.l4')
    l4.directives.record(uri, [row(1, '1'), row(2, '2')])
    const tools = new BuiltinTools(ws, l4)
    const convA = { conversationId: 'conv-a' }
    const convB = { conversationId: 'conv-b' }
    const changed = { path: 'a.l4', mode: 'changed' as const }

    // First call in a conversation gets every directive.
    assert.match(
      await tools.evaluate(changed, convA),
      /--- L4 directives: 2 changed ---\n {2}1 → 1\n {2}2 → 2/
    )
    assert.match(await tools.evaluate(changed, convA), /2 unchanged/)

    // Conversation B on the same file starts from nothing…
    assert.match(
      await tools.evaluate(changed, convB),
      /--- L4 directives: 2 changed ---\n {2}1 → 1\n {2}2 → 2/
    )
    // …and calls without a conversation have their own baseline too.
    assert.match(await tools.evaluate(changed), /2 changed/)

    // A change only B has seen is still news to A.
    l4.directives.record(uri, [row(1, '1'), row(2, '3')])
    assert.match(await tools.evaluate(changed, convB), /1 changed, 1 removed/)
    assert.match(await tools.evaluate(changed, convB), /2 unchanged/)
    assert.match(
      await tools.evaluate(changed, convA),
      /1 changed, 1 removed, 1 unchanged ---\n {2}2 → 3/
    )
  })

  test('the dispatcher passes the conversation to the tools', async () => {
    const ws = new MemoryWorkspace({ 'a.l4': 'l1\nl2' })
    const l4 = new FakeL4Language(ws)
    l4.directives.record(uriOf('/ws/a.l4'), [row(1, 'x')])
    const tools = new BuiltinTools(ws, l4)
    const d = new ToolDispatcher({
      logger: silentLogger,
      tools,
      permissions: fixedPermissionPolicy(),
      interaction: new RecordingInteraction(),
    })
    const call = (conv: string, id: string) =>
      d.run(
        {
          callId: id,
          name: 'l4__evaluate',
          argsJson: '{"path":"a.l4","mode":"changed"}',
        },
        { conversationId: conv, turnId: 't' }
      )
    assert.match(JSON.stringify(await call('c1', 'k1')), /1 changed/)
    assert.match(JSON.stringify(await call('c1', 'k2')), /1 unchanged/)
    assert.match(JSON.stringify(await call('c2', 'k3')), /1 changed/)
    assert.ok(
      tools.storesFor('c1').evaluateStore.hasSnapshot(uriOf('/ws/a.l4'))
    )
  })

  test('full mode prints every directive with the file header', async () => {
    const { l4, tools } = session({ 'a.l4': 'l1\nl2\nl3' })
    l4.directives.record(uriOf('/ws/a.l4'), [row(1, 'TRUE'), row(3, 'FALSE')])
    assert.equal(
      await tools.evaluate({ path: 'a.l4' }),
      '[a.l4 1-3/3]\n--- L4 directives: 2 (full) ---\n  1 → TRUE\n  3 → FALSE'
    )
  })
})

describe('l4__refactor rename', () => {
  test('renames every reference, quoting names that need it', async () => {
    const { ws, l4, tools } = session({
      'a.l4': 'GIVETH foo\nfoo MEANS 1',
      'b.l4': 'IMPORT a\n#EVAL foo',
    })
    l4.references = [
      {
        uri: uriOf('/ws/a.l4'),
        range: {
          start: { line: 0, character: 7 },
          end: { line: 0, character: 10 },
        },
      },
      {
        uri: uriOf('/ws/a.l4'),
        range: {
          start: { line: 1, character: 0 },
          end: { line: 1, character: 3 },
        },
      },
      {
        uri: uriOf('/ws/b.l4'),
        range: {
          start: { line: 1, character: 6 },
          end: { line: 1, character: 9 },
        },
      },
    ]
    const out = await tools.refactor({
      action: 'rename',
      path: 'a.l4',
      oldName: 'foo',
      newName: 'the foo',
    })
    assert.equal(ws.get('a.l4'), 'GIVETH `the foo`\n`the foo` MEANS 1')
    assert.equal(ws.get('b.l4'), 'IMPORT a\n#EVAL `the foo`')
    assert.match(out, /3 occurrences across 2 files \(a.l4, b.l4\)/)
  })

  test('refuses anchors that are only comments', async () => {
    const { l4, tools } = session({ 'a.l4': '-- foo here' })
    l4.semanticTokens = { tokenTypes: ['comment'], data: [0, 0, 11, 0, 0] }
    await assert.rejects(
      tools.refactor({
        action: 'rename',
        path: 'a.l4',
        oldName: 'foo',
        newName: 'bar',
      }),
      /inside a comment/
    )
  })
})

describe('text positions', () => {
  test('round-trips offsets across LF, CRLF and CR line breaks', () => {
    const text = 'ab\r\ncd\nef\rgh'
    for (let i = 0; i <= text.length; i++) {
      const pos = positionAt(text, i)
      // Offsets inside a CRLF pair map to the end of the line.
      if (i === 3) {
        assert.deepEqual(pos, { line: 0, character: 2 })
        continue
      }
      assert.equal(offsetAt(text, pos), i, `offset ${i}`)
    }
    assert.deepEqual(positionAt(text, 10), { line: 3, character: 0 })
  })
})

describe('diagnostics formatting', () => {
  test('clean files collapse to one line', () => {
    assert.equal(formatL4Diagnostics([]), '--- L4 diagnostics: clean ---')
  })
})
