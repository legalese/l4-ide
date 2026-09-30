import { afterEach, beforeEach, describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import { mkdir, readFile, symlink, writeFile } from 'node:fs/promises'
import * as path from 'node:path'
import { PassThrough } from 'node:stream'
import rpc from 'vscode-jsonrpc/node.js'
import type { MessageConnection } from 'vscode-jsonrpc'
import { Jl4Lsp } from '../src/jl4-lsp.js'
import {
  NodeWorkspace,
  uriForPath,
  type WorkspaceChangeListener,
} from '../src/node-workspace.js'
import { silent, tempDir } from './helpers.js'

class RecordingListener implements WorkspaceChangeListener {
  readonly writes: Array<[string, string, boolean]> = []
  readonly deletes: string[] = []
  onDidWrite(uri: string, text: string, created: boolean): void {
    this.writes.push([uri, text, created])
  }
  onDidDelete(uri: string): void {
    this.deletes.push(uri)
  }
}

describe('NodeWorkspace', () => {
  let dir: string
  let repo: string
  let cleanup: () => Promise<void>
  beforeEach(async () => {
    ;({ dir, cleanup } = await tempDir())
    repo = path.join(dir, 'repo')
    await mkdir(path.join(repo, '.git'), { recursive: true })
    await mkdir(path.join(repo, 'data', 'sub'), { recursive: true })
    await writeFile(path.join(repo, 'data', 'a.l4'), 'one\ntwo\nthree\n')
    await writeFile(path.join(dir, 'secret.txt'), 'outside')
  })
  afterEach(() => cleanup())

  test('resolves paths inside the repo and refuses everything else', () => {
    const ws = new NodeWorkspace(repo)
    const r = ws.resolvePath('data/sub/../a.l4')
    assert.equal(r.relative, path.join('data', 'a.l4'))
    assert.equal(r.uri, uriForPath(path.join(repo, 'data', 'a.l4')))
    assert.equal(
      ws.resolvePath(path.join(repo, 'data', 'a.l4')).relative,
      path.join('data', 'a.l4')
    )
    assert.throws(() => ws.resolvePath('../secret.txt'), /outside/)
    assert.throws(() => ws.resolvePath(path.join(dir, 'secret.txt')), /outside/)
    assert.throws(() => ws.resolvePath('.git/config'), /\.git/)
    assert.throws(() => ws.resolvePath('sub/.GIT/hooks/pre-commit'), /\.git/)
    assert.throws(() => ws.resolvePath(''), /required/)
  })

  test('refuses paths that leave the repo through a symlink', async () => {
    await symlink(dir, path.join(repo, 'escape'))
    const ws = new NodeWorkspace(repo)
    assert.throws(() => ws.resolvePath('escape/secret.txt'), /link/)
    assert.throws(() => ws.resolvePath('escape/new-file.txt'), /link/)
    await symlink(path.join(dir, 'secret.txt'), path.join(repo, 'leak.txt'))
    assert.throws(() => ws.resolvePath('leak.txt'), /link/)
  })

  test('hides .git from listings', async () => {
    const ws = new NodeWorkspace(repo)
    const names = (await ws.readDirectory(repo)).map((e) => e.name).sort()
    assert.deepEqual(names, ['data'])
  })

  test('creates files exclusively and tells the listener', async () => {
    const l = new RecordingListener()
    const ws = new NodeWorkspace(repo, l)
    const target = ws.resolvePath('data/sub/deep/new.l4')
    await ws.createFile(target, 'hello')
    assert.equal(await readFile(target.fsPath, 'utf8'), 'hello')
    await assert.rejects(ws.createFile(target, 'again'), /EEXIST/)
    assert.deepEqual(l.writes, [[target.uri, 'hello', true]])
  })

  test('applies offset edits per file from the highest offset down', async () => {
    const l = new RecordingListener()
    const ws = new NodeWorkspace(repo, l)
    const a = ws.resolvePath('data/a.l4')
    await writeFile(path.join(repo, 'data', 'b.l4'), 'xyz')
    const b = ws.resolvePath('data/b.l4')
    await ws.applyEdits([
      { uri: a.uri, startOffset: 0, endOffset: 3, newText: 'ONE' },
      { uri: a.uri, startOffset: 8, endOffset: 13, newText: 'THREE' },
      { uri: b.uri, startOffset: 1, endOffset: 2, newText: 'Y' },
    ])
    assert.equal(await readFile(a.fsPath, 'utf8'), 'ONE\ntwo\nTHREE\n')
    assert.equal(await readFile(b.fsPath, 'utf8'), 'xYz')
    assert.equal(l.writes.length, 2)
  })

  test('rejects overlapping edits without writing anything', async () => {
    const ws = new NodeWorkspace(repo)
    const a = ws.resolvePath('data/a.l4')
    await assert.rejects(
      ws.applyEdits([
        { uri: a.uri, startOffset: 0, endOffset: 5, newText: 'x' },
        { uri: a.uri, startOffset: 3, endOffset: 6, newText: 'y' },
      ]),
      /overlapping/
    )
    assert.equal(await readFile(a.fsPath, 'utf8'), 'one\ntwo\nthree\n')
  })

  test('deletes files, not directories', async () => {
    const l = new RecordingListener()
    const ws = new NodeWorkspace(repo, l)
    const a = ws.resolvePath('data/a.l4')
    assert.equal(await ws.deleteFile(a), 'deleted')
    assert.equal(await ws.stat(a.fsPath), null)
    assert.deepEqual(l.deletes, [a.uri])
    await assert.rejects(ws.deleteFile(ws.resolvePath('data/sub')), /directory/)
  })
})

/** An in-process fake jl4-lsp. */
function fakeServer(): {
  client: MessageConnection
  server: MessageConnection
  received: Array<{ method: string; params: unknown }>
} {
  const c2s = new PassThrough()
  const s2c = new PassThrough()
  const client = rpc.createMessageConnection(
    new rpc.StreamMessageReader(s2c),
    new rpc.StreamMessageWriter(c2s)
  )
  const server = rpc.createMessageConnection(
    new rpc.StreamMessageReader(c2s),
    new rpc.StreamMessageWriter(s2c)
  )
  const received: Array<{ method: string; params: unknown }> = []
  server.onRequest('initialize', () => ({
    capabilities: {
      semanticTokensProvider: {
        legend: { tokenTypes: ['keyword', 'function'] },
      },
    },
  }))
  server.onNotification((method: string, params: unknown) => {
    received.push({ method, params })
  })
  server.listen()
  return { client, server, received }
}

describe('Jl4Lsp', () => {
  let dir: string
  let cleanup: () => Promise<void>
  beforeEach(async () => {
    ;({ dir, cleanup } = await tempDir())
    await writeFile(path.join(dir, 'a.l4'), 'DECIDE x IS 1\n#EVAL x\n')
  })
  afterEach(() => cleanup())

  test('opens documents, caches diagnostics and directive results', async () => {
    const { client, server, received } = fakeServer()
    const uri = uriForPath(path.join(dir, 'a.l4'))
    server.onNotification(
      'textDocument/didOpen',
      (p: { textDocument: { uri: string } }) => {
        received.push({ method: 'textDocument/didOpen', params: p })
        setTimeout(() => {
          void server.sendNotification('textDocument/publishDiagnostics', {
            uri: p.textDocument.uri,
            diagnostics: [
              {
                range: {
                  start: { line: 1, character: 0 },
                  end: { line: 1, character: 5 },
                },
                severity: 2,
                message: 'careful',
                source: 'jl4',
              },
            ],
          })
          void server.sendNotification('l4/directiveResultsUpdated', {
            uri: p.textDocument.uri,
            results: [
              {
                directiveId: '2:1',
                prettyText: '1',
                success: true,
                body: '#EVAL x',
              },
            ],
          })
        }, 20)
      }
    )
    // Server → client requests get answers.
    const lsp = await Jl4Lsp.connect(client, uriForPath(dir), silent)
    const config = await server.sendRequest('workspace/configuration', {
      items: [{ section: 'jl4' }, { section: 'other' }],
    })
    assert.deepEqual(config, [null, null])
    assert.equal(
      await server.sendRequest('client/registerCapability', {
        registrations: [],
      }),
      null
    )

    const opened = await lsp.openDocument(uri)
    assert.deepEqual(opened, { lineCount: 3, version: 1 })
    const waiting = lsp.awaitDirectiveResults(uri, 2_000)
    const diags = await lsp.getDiagnostics(uri)
    assert.deepEqual(diags, [
      {
        severity: 'warning',
        line: 1,
        message: 'careful',
        source: 'jl4',
        code: undefined,
      },
    ])
    await waiting
    assert.equal(lsp.getDirectiveResults(uri)?.[0]?.prettyText, '1')
    assert.equal(
      received.filter((r) => r.method === 'textDocument/didOpen').length,
      1
    )
    client.dispose()
    server.dispose()
  })

  test('sends didChange for open documents and watched-file events', async () => {
    const { client, server, received } = fakeServer()
    const lsp = await Jl4Lsp.connect(client, uriForPath(dir), silent)
    const uri = uriForPath(path.join(dir, 'a.l4'))
    await lsp.openDocument(uri)
    lsp.onDidWrite(uri, 'DECIDE x IS 2\n', false)
    lsp.onDidWrite(uriForPath(path.join(dir, 'b.l4')), 'new', true)
    lsp.onDidDelete(uri)
    await new Promise((r) => setTimeout(r, 50))
    const methods = received.map((r) => r.method)
    assert.deepEqual(methods, [
      'initialized',
      'textDocument/didOpen',
      'textDocument/didChange',
      'workspace/didChangeWatchedFiles',
      'workspace/didChangeWatchedFiles',
      'textDocument/didClose',
      'workspace/didChangeWatchedFiles',
    ])
    const change = received[2]!.params as {
      textDocument: { version: number }
      contentChanges: Array<{ text: string }>
    }
    assert.equal(change.textDocument.version, 2)
    assert.equal(change.contentChanges[0]!.text, 'DECIDE x IS 2\n')
    const created = received[4]!.params as { changes: Array<{ type: number }> }
    assert.equal(created.changes[0]!.type, 1)
    client.dispose()
    server.dispose()
  })

  test('forwards references, semantic tokens and exported functions', async () => {
    const { client, server } = fakeServer()
    const uri = uriForPath(path.join(dir, 'a.l4'))
    server.onRequest('textDocument/references', () => [
      {
        uri,
        range: {
          start: { line: 0, character: 7 },
          end: { line: 0, character: 8 },
        },
      },
    ])
    server.onRequest('textDocument/semanticTokens/full', () => ({
      data: [0, 0, 6, 0, 0],
    }))
    server.onRequest(
      'l4/getExportedFunctions',
      (p: { verDocId: { version: number } }) => ({
        functions: [
          {
            name: 'x',
            description: '',
            isDefault: true,
            returnType: 'NUMBER',
            isDeontic: false,
            parameters: { type: 'object', properties: {}, required: [] },
          },
        ],
        importedFiles: [],
        echoed: p.verDocId.version,
      })
    )
    const lsp = await Jl4Lsp.connect(client, uriForPath(dir), silent)
    const refs = await lsp.findReferences(uri, { line: 0, character: 7 })
    assert.equal(refs.length, 1)
    const tokens = await lsp.getSemanticTokens(uri)
    assert.deepEqual(tokens?.tokenTypes, ['keyword', 'function'])
    assert.deepEqual(Array.from(tokens?.data ?? []), [0, 0, 6, 0, 0])
    const fns = await lsp.getExportedFunctions({ uri, version: 1 })
    assert.equal(fns[0]?.name, 'x')
    client.dispose()
    server.dispose()
  })
})

// Optional: a real jl4-lsp (set JL4_LSP=/path/to/jl4-lsp).
const testEnv: NodeJS.ProcessEnv = process.env
const realLsp = testEnv['JL4_LSP']
describe('Jl4Lsp against a real jl4-lsp', { skip: !realLsp }, () => {
  test('type-checks and evaluates a file', async () => {
    const { dir, cleanup } = await tempDir()
    try {
      await writeFile(
        path.join(dir, 'a.l4'),
        'DECIDE `the answer` IS 41 PLUS 1\n\n#EVAL `the answer`\n'
      )
      const lsp = await Jl4Lsp.spawn({
        command: realLsp!,
        root: dir,
        logger: silent,
        env: {
          PATH: testEnv['PATH'] ?? '',
          HOME: testEnv['HOME'] ?? '',
        },
      })
      const uri = uriForPath(path.join(dir, 'a.l4'))
      const waiting = lsp.awaitDirectiveResults(uri, 60_000)
      const diags = await lsp.getDiagnostics(uri)
      assert.deepEqual(
        diags.filter((d) => d.severity === 'error'),
        []
      )
      // #EVAL results arrive as info diagnostics too.
      assert.ok(diags.some((d) => d.message === '42'))
      await waiting
      assert.equal(lsp.getDirectiveResults(uri)?.[0]?.prettyText, '42')
      const fns = await lsp.getExportedFunctions({ uri, version: 1 })
      assert.ok(Array.isArray(fns))
      await lsp.dispose()
    } finally {
      await cleanup()
    }
  })
})
