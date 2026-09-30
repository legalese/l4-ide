import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import { gunzipSync } from 'node:zlib'
import {
  SeedLimitError,
  attachmentNames,
  checkAttachmentSizes,
  checkSeedSize,
  checkAddFilesSizes,
  commonAncestor,
  contentTypeFor,
  dataPathFor,
  seedBaseFor,
  seedBaseLocalPath,
  createSeedTarGz,
  createTar,
  layoutSeed,
} from '../cloud/seed.js'

const enc = (s: string) => new TextEncoder().encode(s)

/** Minimal reader following the Sessions API's parser (ustar + pax). */
function readTar(tar: Buffer): Array<{ path: string; data: string }> {
  const out: Array<{ path: string; data: string }> = []
  const cstr = (b: Buffer) => {
    const nul = b.indexOf(0)
    return (nul >= 0 ? b.subarray(0, nul) : b).toString('utf8')
  }
  let pos = 0
  let paxPath: string | undefined
  while (pos + 512 <= tar.length) {
    const h = tar.subarray(pos, pos + 512)
    if (h.every((b) => b === 0)) break
    let sum = 0
    for (let i = 0; i < 512; i++) sum += i >= 148 && i < 156 ? 0x20 : h[i]!
    assert.equal(
      sum,
      parseInt(cstr(h.subarray(148, 156)).trim(), 8),
      'checksum'
    )
    assert.equal(cstr(h.subarray(257, 263)), 'ustar')
    const size = parseInt(cstr(h.subarray(124, 136)).trim(), 8)
    const type = String.fromCharCode(h[156]!)
    const data = tar.subarray(pos + 512, pos + 512 + size)
    pos += 512 + Math.ceil(size / 512) * 512
    if (type === 'x') {
      const rec = data.toString('utf8')
      const m = /^(\d+) path=(.*)\n$/s.exec(rec)
      assert.ok(m, 'pax record')
      assert.equal(Number(m[1]), Buffer.byteLength(rec))
      paxPath = m[2]
      continue
    }
    assert.equal(type, '0')
    out.push({
      path: paxPath ?? cstr(h.subarray(0, 100)),
      data: data.toString('utf8'),
    })
    paxPath = undefined
  }
  return out
}

describe('seed layout', () => {
  test('common ancestor', () => {
    assert.equal(commonAncestor(['/a/b/c.l4']), '/a/b')
    assert.equal(commonAncestor(['/a/b/c.l4', '/a/d/e.l4']), '/a')
    assert.equal(commonAncestor(['/a/b/c.l4', '/x/e.l4']), '/')
  })

  test('keeps paths relative to the common ancestor (no flattening)', () => {
    const { files, root, skipped } = layoutSeed(
      [
        { path: '/ws/rules/main.l4', bytes: enc('IMPORT `../shared/defs`') },
        { path: '/ws/shared/defs.l4', bytes: enc('defs') },
        { path: '/ws/rules/main.l4', bytes: enc('dup') },
      ],
      ['/ws']
    )
    assert.equal(root, '/ws')
    assert.deepEqual(
      files.map((f) => f.path),
      ['rules/main.l4', 'shared/defs.l4']
    )
    assert.deepEqual(skipped, [])
  })

  test('leaves out files outside the roots and unsafe names', () => {
    const { files, skipped } = layoutSeed(
      [
        { path: '/ws/main.l4', bytes: enc('x') },
        {
          path: '/home/u/.local/share/jl4/libraries/prelude.l4',
          bytes: enc('p'),
        },
        { path: '/ws/.git/config', bytes: enc('c') },
      ],
      ['/ws']
    )
    assert.deepEqual(
      files.map((f) => f.path),
      ['main.l4']
    )
    assert.deepEqual(skipped, [
      '/home/u/.local/share/jl4/libraries/prelude.l4',
      '/ws/.git/config',
    ])
  })
})

describe('seed tarball', () => {
  test('round-trips short, long and non-ASCII paths', () => {
    const long = `${'d'.repeat(60)}/${'e'.repeat(60)}/file.l4`
    const files = [
      { path: 'main.l4', bytes: enc('hello') },
      { path: long, bytes: enc('long') },
      { path: 'Verträge/§ 1.l4', bytes: enc('umlaut') },
      { path: 'empty.l4', bytes: new Uint8Array(0) },
    ]
    assert.deepEqual(readTar(createTar(files)), [
      { path: 'main.l4', data: 'hello' },
      { path: long, data: 'long' },
      { path: 'Verträge/§ 1.l4', data: 'umlaut' },
      { path: 'empty.l4', data: '' },
    ])
    const gz = createSeedTarGz(files)
    assert.equal(readTar(gunzipSync(gz)).length, 4)
  })
})

describe('seed limits', () => {
  test('declines attachments over 10 MB, naming them', () => {
    const big = new Uint8Array(10 * 1024 * 1024 + 1)
    assert.throws(
      () =>
        checkAttachmentSizes([
          { name: 'ok.pdf', contentType: 'application/pdf', bytes: enc('x') },
          { name: 'huge.pdf', contentType: 'application/pdf', bytes: big },
        ]),
      (err: unknown) => {
        assert.ok(err instanceof SeedLimitError)
        assert.deepEqual(err.files, ['huge.pdf'])
        assert.match(err.message, /huge\.pdf \(10\.0 MB\)/)
        return true
      }
    )
  })

  test('declines a seed over 50 MB, naming the largest files', () => {
    const gz = new Uint8Array(50 * 1024 * 1024 + 1)
    assert.throws(
      () =>
        checkSeedSize(gz, [
          { path: 'a.l4', bytes: new Uint8Array(10) },
          { path: 'data/big.csv', bytes: new Uint8Array(2 * 1024 * 1024) },
        ]),
      (err: unknown) => {
        assert.ok(err instanceof SeedLimitError)
        assert.deepEqual(err.files, ['data/big.csv', 'a.l4'])
        return true
      }
    )
    checkSeedSize(new Uint8Array(10), [])
  })

  test('attachment names are plain and unique', () => {
    assert.deepEqual(
      attachmentNames(['a.pdf', 'dir/a.pdf', '.hidden', '', 'x\n.png']),
      ['a.pdf', 'a-2.pdf', 'hidden', 'attachment', 'x.png']
    )
  })
})

describe('files added mid-session', () => {
  test('data paths: seed base first, then the workspace folder', () => {
    assert.equal(dataPathFor('/ws/a/b.l4', '/ws/a', ['/ws']), 'data/b.l4')
    assert.equal(dataPathFor('/ws/c/d.l4', '/ws/a', ['/ws']), 'data/c/d.l4')
    assert.equal(dataPathFor('/ws/c/d.l4', undefined, ['/ws']), 'data/c/d.l4')
    assert.equal(dataPathFor('/other/e.l4', '/ws/a', ['/ws']), null)
    assert.equal(dataPathFor('/ws/.git/config', '/ws', ['/ws']), null)
  })

  test('content types and limits', () => {
    assert.equal(contentTypeFor('data/a.l4'), 'text/plain')
    assert.equal(contentTypeFor('data/a.pdf'), 'application/pdf')
    assert.equal(contentTypeFor('data/a.bin'), 'application/octet-stream')
    const mb = 1024 * 1024
    assert.throws(
      () =>
        checkAddFilesSizes(
          Array.from({ length: 6 }, (_, i) => ({
            path: `data/f${i}.bin`,
            bytes: new Uint8Array(9 * mb),
          }))
        ),
      (err: unknown) =>
        err instanceof SeedLimitError &&
        /over the 50\.0 MB limit/.test(err.message)
    )
    checkAddFilesSizes([{ path: 'data/ok.l4', bytes: enc('x') }])
  })
})

describe('seed base', () => {
  const folders = [
    { name: 'ws', path: '/ws' },
    { name: 'inner', path: '/ws/pkg' },
  ]
  test('deepest workspace folder containing the root', () => {
    assert.deepEqual(seedBaseFor('/ws/a/b', folders), {
      workspaceFolder: 'ws',
      path: 'a/b',
    })
    assert.deepEqual(seedBaseFor('/ws/pkg/x', folders), {
      workspaceFolder: 'inner',
      path: 'x',
    })
    assert.deepEqual(seedBaseFor('/ws', folders), {
      workspaceFolder: 'ws',
      path: '',
    })
    assert.equal(seedBaseFor('/tmp/x', folders), undefined)
  })
  test('local path of a base', () => {
    assert.equal(
      seedBaseLocalPath({ workspaceFolder: 'ws', path: 'a/b' }, '/h/ws'),
      '/h/ws/a/b'
    )
    assert.equal(
      seedBaseLocalPath({ workspaceFolder: 'ws', path: '' }, '/h/ws'),
      '/h/ws'
    )
  })
})
