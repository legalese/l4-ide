import { afterEach, beforeEach, describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import {
  mkdir,
  readFile,
  readdir,
  stat,
  symlink,
  writeFile,
} from 'node:fs/promises'
import * as path from 'node:path'
import { NodeWorkspace } from '../src/node-workspace.js'
import { MemoryLogger, tempDir } from './helpers.js'

describe('repo layout: data/ and tmp/', () => {
  let dir: string
  let repo: string
  let cleanup: () => Promise<void>

  beforeEach(async () => {
    ;({ dir, cleanup } = await tempDir())
    repo = path.join(dir, 'repo')
    await mkdir(path.join(repo, 'data', 'sub'), { recursive: true })
    await mkdir(path.join(repo, '.platform'))
    await writeFile(path.join(repo, 'data', 'a.l4'), 'original a\n')
    await writeFile(path.join(repo, 'data', 'sub', 'b.l4'), 'original b\n')
    await writeFile(path.join(repo, '.platform', 'meta.json'), '{}')
    await writeFile(path.join(repo, 'README.md'), 'readme')
  })
  afterEach(() => cleanup())

  function ws(): NodeWorkspace {
    return new NodeWorkspace(repo, undefined, new MemoryLogger())
  }

  const read = (rel: string): Promise<string> =>
    readFile(path.join(repo, rel), 'utf8')

  test('ensureLayout creates data/ and tmp/', async () => {
    const w = ws()
    await w.ensureLayout()
    assert.ok((await stat(path.join(repo, 'tmp'))).isDirectory())
  })

  test('delete → read the copy in tmp/deleted → write it back', async () => {
    const w = ws()
    w.setTurn('t1')
    await w.deleteFile(w.resolvePath('data/sub/b.l4'))
    await assert.rejects(stat(path.join(repo, 'data', 'sub', 'b.l4')))
    const copy = w.resolvePath('tmp/deleted/t-t1/sub/b.l4')
    const text = await w.readFile(copy.fsPath)
    assert.equal(text, 'original b\n')
    await w.createFile(w.resolvePath('data/sub/b.l4'), text)
    assert.equal(await read('data/sub/b.l4'), 'original b\n')
  })

  test('only deletes under data/ are copied; the first copy per turn wins', async () => {
    const w = ws()
    w.setTurn('t1')
    const a = w.resolvePath('data/a.l4')
    await w.applyEdits([
      { uri: a.uri, startOffset: 0, endOffset: 8, newText: 'edited' },
    ])
    await assert.rejects(stat(path.join(repo, 'tmp', 'deleted')))
    await w.deleteFile(a)
    await w.createFile(w.resolvePath('data/a.l4'), 'second')
    await w.deleteFile(w.resolvePath('data/a.l4'))
    assert.equal(await read('tmp/deleted/t-t1/a.l4'), 'edited a\n')
    // A new harness process (after a crash) keeps the first copy too.
    const again = ws()
    again.setTurn('t1')
    await again.createFile(again.resolvePath('data/a.l4'), 'third')
    await again.deleteFile(again.resolvePath('data/a.l4'))
    assert.equal(await read('tmp/deleted/t-t1/a.l4'), 'edited a\n')
    // Deleting in tmp/ copies nothing; outside a turn nothing is copied.
    await w.createFile(w.resolvePath('tmp/note.md'), 'n')
    await w.deleteFile(w.resolvePath('tmp/note.md'))
    w.setTurn(null)
    await w.deleteFile(w.resolvePath('data/sub/b.l4'))
    assert.deepEqual(await readdir(path.join(repo, 'tmp', 'deleted')), ['t-t1'])
  })

  test('tmp/ is freely editable', async () => {
    const w = ws()
    const note = w.resolvePath('tmp/notes/idea.md')
    await w.createFile(note, 'first idea')
    await w.applyEdits([
      { uri: note.uri, startOffset: 0, endOffset: 5, newText: 'second' },
    ])
    assert.equal(await read('tmp/notes/idea.md'), 'second idea')
    await w.deleteFile(note)
  })

  test('only data/ and tmp/ are writable; the rest is readable metadata', async () => {
    const w = ws()
    const meta = w.resolvePath('.platform/meta.json')
    assert.equal(await w.readFile(meta.fsPath), '{}')
    const readme = w.resolvePath('README.md')
    assert.equal(await w.readFile(readme.fsPath), 'readme')
    await assert.rejects(
      w.createFile(w.resolvePath('.platform/x'), 'x'),
      /only create, edit or delete files inside data\//
    )
    await assert.rejects(
      w.createFile(w.resolvePath('notes.md'), 'x'),
      /platform metadata/
    )
    await assert.rejects(
      w.applyEdits([
        { uri: readme.uri, startOffset: 0, endOffset: 1, newText: 'R' },
      ]),
      /platform metadata/
    )
    await assert.rejects(w.deleteFile(readme), /platform metadata/)
    await assert.rejects(w.deleteFile(meta), /platform metadata/)
    // `data` itself (not a file inside it) isn't writable either.
    await assert.rejects(
      w.deleteFile(w.resolvePath('data')),
      /platform metadata/
    )
    assert.equal(await read('README.md'), 'readme')
  })

  test('confinement: .., symlinks, and link-safe copies', async () => {
    const w = ws()
    w.setTurn('t1')
    await writeFile(path.join(dir, 'secret.txt'), 'secret')
    assert.throws(() => w.resolvePath('tmp/../../secret.txt'), /outside/)
    await symlink(
      path.join(dir, 'secret.txt'),
      path.join(repo, 'tmp', 'leak.txt')
    ).catch(async () => {
      await mkdir(path.join(repo, 'tmp'))
      await symlink(
        path.join(dir, 'secret.txt'),
        path.join(repo, 'tmp', 'leak.txt')
      )
    })
    assert.throws(() => w.resolvePath('tmp/leak.txt'), /link/)
    // A symlink in data/ is never copied.
    await symlink(
      path.join(repo, 'data', 'a.l4'),
      path.join(repo, 'data', 'alias.l4')
    )
    await w.deleteFile(w.resolvePath('data/alias.l4'))
    await assert.rejects(
      stat(path.join(repo, 'tmp', 'deleted', 't-t1', 'alias.l4'))
    )
    // A planted link at tmp/deleted can't redirect copies.
    const elsewhere = path.join(dir, 'elsewhere')
    await mkdir(elsewhere)
    await symlink(elsewhere, path.join(repo, 'tmp', 'deleted'))
    await w.deleteFile(w.resolvePath('data/a.l4'))
    assert.deepEqual(await readdir(elsewhere), [])
    // A turn id of `..` stays inside tmp/deleted.
    const w2 = ws()
    w2.setTurn('..')
    await w2.deleteFile(w2.resolvePath('data/sub/b.l4')).catch(() => undefined)
    await assert.rejects(stat(path.join(repo, 'tmp', 'sub')))
  })
})
