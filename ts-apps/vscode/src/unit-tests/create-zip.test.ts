/** The zip writer a deploy uses. Entry names carry folders now, and a folder
 *  can be called anything, so the writer sets the zip format's UTF-8 flag on a
 *  name that is not ASCII. These tests read the zip it makes the way a reader
 *  does (the central directory, then each local header) and compare it with the
 *  writer as it was before the flag. */
import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import { crc32 as zlibCrc32 } from 'node:zlib'
import { createZip } from '../deploy-bundle.js'

const encoder = new TextEncoder()
const bytesOf = (text: string) => encoder.encode(text)

// ---------------------------------------------------------------------------
// The oracle: createZip as it was in sidebar-provider.ts (commit cbced76cb),
// copied here unchanged except for its name, before it learnt the UTF-8 flag.
// ---------------------------------------------------------------------------

const crcTable = new Uint32Array(256)
for (let i = 0; i < 256; i++) {
  let c = i
  for (let j = 0; j < 8; j++) {
    c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
  }
  crcTable[i] = c
}

function crc32(data: Uint8Array): number {
  let crc = 0xffffffff
  for (let i = 0; i < data.length; i++) {
    crc = crcTable[(crc ^ data[i]) & 0xff] ^ (crc >>> 8)
  }
  return (crc ^ 0xffffffff) >>> 0
}

function createZipBeforeTheFlag(
  files: { name: string; content: Uint8Array }[]
): Uint8Array {
  const encoder = new TextEncoder()

  // Pre-compute sizes
  type Entry = {
    nameBytes: Uint8Array
    content: Uint8Array
    crc: number
    localOffset: number
  }
  const entries: Entry[] = []
  let localSize = 0
  for (const file of files) {
    const nameBytes = encoder.encode(file.name)
    const crc = crc32(file.content)
    entries.push({
      nameBytes,
      content: file.content,
      crc,
      localOffset: localSize,
    })
    localSize += 30 + nameBytes.length + file.content.length
  }

  let centralSize = 0
  for (const e of entries) centralSize += 46 + e.nameBytes.length
  const endSize = 22
  const totalSize = localSize + centralSize + endSize

  const buf = new ArrayBuffer(totalSize)
  const view = new DataView(buf)
  const bytes = new Uint8Array(buf)
  let offset = 0

  // Local file headers + data
  for (const e of entries) {
    view.setUint32(offset, 0x04034b50, true)
    offset += 4
    view.setUint16(offset, 20, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint32(offset, e.crc, true)
    offset += 4
    view.setUint32(offset, e.content.length, true)
    offset += 4
    view.setUint32(offset, e.content.length, true)
    offset += 4
    view.setUint16(offset, e.nameBytes.length, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    bytes.set(e.nameBytes, offset)
    offset += e.nameBytes.length
    bytes.set(e.content, offset)
    offset += e.content.length
  }

  const centralOffset = offset

  // Central directory headers
  for (const e of entries) {
    view.setUint32(offset, 0x02014b50, true)
    offset += 4
    view.setUint16(offset, 20, true)
    offset += 2
    view.setUint16(offset, 20, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint32(offset, e.crc, true)
    offset += 4
    view.setUint32(offset, e.content.length, true)
    offset += 4
    view.setUint32(offset, e.content.length, true)
    offset += 4
    view.setUint16(offset, e.nameBytes.length, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint16(offset, 0, true)
    offset += 2
    view.setUint32(offset, 0, true)
    offset += 4
    view.setUint32(offset, e.localOffset, true)
    offset += 4
    bytes.set(e.nameBytes, offset)
    offset += e.nameBytes.length
  }

  // End of central directory
  view.setUint32(offset, 0x06054b50, true)
  offset += 4
  view.setUint16(offset, 0, true)
  offset += 2
  view.setUint16(offset, 0, true)
  offset += 2
  view.setUint16(offset, entries.length, true)
  offset += 2
  view.setUint16(offset, entries.length, true)
  offset += 2
  view.setUint32(offset, centralSize, true)
  offset += 4
  view.setUint32(offset, centralOffset, true)
  offset += 4
  view.setUint16(offset, 0, true)

  return new Uint8Array(buf)
}

// ---------------------------------------------------------------------------
// A reader: the central directory, then each entry's local header and data
// ---------------------------------------------------------------------------

interface ReadEntry {
  /** The name's bytes, as stored. */
  nameBytes: Uint8Array
  /** The name, decoded as UTF-8 if the entry says it is, else as ASCII. */
  name: string
  localFlags: number
  centralFlags: number
  data: Uint8Array
}

const UTF8 = 0x0800

function readZip(zip: Uint8Array): ReadEntry[] {
  const view = new DataView(zip.buffer, zip.byteOffset, zip.byteLength)

  // End of central directory: the last 22 bytes (this writer writes no comment).
  const end = zip.length - 22
  assert.ok(end >= 0, 'a zip is at least 22 bytes')
  assert.equal(
    view.getUint32(end, true),
    0x06054b50,
    'end-of-directory signature'
  )
  const count = view.getUint16(end + 10, true)
  assert.equal(view.getUint16(end + 8, true), count, 'entries on this disk')
  const centralSize = view.getUint32(end + 12, true)
  const centralOffset = view.getUint32(end + 16, true)
  assert.equal(view.getUint16(end + 20, true), 0, 'no archive comment')
  assert.equal(
    centralOffset + centralSize,
    end,
    'the directory ends where the end record begins'
  )

  const entries: ReadEntry[] = []
  let c = centralOffset
  let expectedLocal = 0
  for (let n = 0; n < count; n++) {
    assert.equal(
      view.getUint32(c, true),
      0x02014b50,
      'central header signature'
    )
    const centralFlags = view.getUint16(c + 8, true)
    assert.equal(view.getUint16(c + 10, true), 0, 'stored, not compressed')
    const crc = view.getUint32(c + 16, true)
    const size = view.getUint32(c + 20, true)
    assert.equal(view.getUint32(c + 24, true), size, 'stored: both sizes agree')
    const nameLength = view.getUint16(c + 28, true)
    assert.equal(view.getUint16(c + 30, true), 0, 'no extra field')
    assert.equal(view.getUint16(c + 32, true), 0, 'no comment')
    const localOffset = view.getUint32(c + 42, true)
    const centralName = zip.slice(c + 46, c + 46 + nameLength)
    c += 46 + nameLength

    // The local header the directory points at.
    assert.equal(
      localOffset,
      expectedLocal,
      'entries are laid out one after another'
    )
    assert.equal(
      view.getUint32(localOffset, true),
      0x04034b50,
      'local header signature'
    )
    const localFlags = view.getUint16(localOffset + 6, true)
    assert.equal(
      view.getUint16(localOffset + 8, true),
      0,
      'stored, not compressed'
    )
    assert.equal(
      view.getUint32(localOffset + 14, true),
      crc,
      'local and central CRC agree'
    )
    assert.equal(view.getUint32(localOffset + 18, true), size, 'local size')
    assert.equal(
      view.getUint32(localOffset + 22, true),
      size,
      'local size, uncompressed'
    )
    assert.equal(
      view.getUint16(localOffset + 26, true),
      nameLength,
      'local name length'
    )
    assert.equal(
      view.getUint16(localOffset + 28, true),
      0,
      'no local extra field'
    )
    const localName = zip.slice(localOffset + 30, localOffset + 30 + nameLength)
    assert.deepEqual(localName, centralName, 'local and central names agree')
    const data = zip.slice(
      localOffset + 30 + nameLength,
      localOffset + 30 + nameLength + size
    )
    assert.equal(zlibCrc32(data), crc, 'the CRC is that of the data')
    expectedLocal = localOffset + 30 + nameLength + size

    // A name is decoded the way its flag says. Without the flag a reader takes
    // it for a legacy code page, so it must be plain ASCII to survive.
    const utf8 = (localFlags & UTF8) !== 0
    if (!utf8) {
      assert.ok(
        centralName.every((b) => b <= 0x7f),
        'a name that is not ASCII must carry the UTF-8 flag'
      )
    }
    const name = new TextDecoder(utf8 ? 'utf-8' : 'ascii', {
      fatal: true,
    }).decode(centralName)
    entries.push({
      nameBytes: centralName,
      name,
      localFlags,
      centralFlags,
      data,
    })
  }
  assert.equal(
    expectedLocal,
    centralOffset,
    'the directory follows the last entry'
  )
  return entries
}

const file = (name: string, text: string) => ({ name, content: bytesOf(text) })

describe('createZip: what a reader finds', () => {
  test('a flat name round-trips, with no flag', () => {
    const [e] = readZip(createZip([file('main.l4', 'IMPORT helper\n')]))
    assert.equal(e.name, 'main.l4')
    assert.equal(new TextDecoder().decode(e.data), 'IMPORT helper\n')
    assert.equal(e.localFlags, 0)
    assert.equal(e.centralFlags, 0)
  })

  test('a name with a folder round-trips, with no flag', () => {
    const [e] = readZip(createZip([file('a/helper.l4', 'x')]))
    assert.equal(e.name, 'a/helper.l4')
    assert.equal(e.localFlags, 0)
    assert.equal(e.centralFlags, 0)
  })

  test('a name with a space round-trips, with no flag', () => {
    const [e] = readZip(createZip([file('my rules/rate table.l4', 'x')]))
    assert.equal(e.name, 'my rules/rate table.l4')
    assert.equal(e.localFlags, 0)
    assert.equal(e.centralFlags, 0)
  })

  test('a Hebrew folder name round-trips, with the UTF-8 flag in both headers', () => {
    const [e] = readZip(createZip([file('תיקייה/main.l4', 'x')]))
    assert.equal(e.name, 'תיקייה/main.l4')
    assert.deepEqual(e.nameBytes, bytesOf('תיקייה/main.l4'))
    assert.equal(e.localFlags, UTF8)
    assert.equal(e.centralFlags, UTF8)
  })

  test('the flag is set per entry: an ASCII entry beside a Hebrew one has none', () => {
    const entries = readZip(
      createZip([
        file('main.l4', 'a'),
        file('תיקייה/כללים.l4', 'b'),
        file('lib/rates.l4', 'c'),
        file('café/menu.l4', 'd'),
      ])
    )
    assert.deepEqual(
      entries.map((e) => [e.name, e.localFlags, e.centralFlags]),
      [
        ['main.l4', 0, 0],
        ['תיקייה/כללים.l4', UTF8, UTF8],
        ['lib/rates.l4', 0, 0],
        ['café/menu.l4', UTF8, UTF8],
      ]
    )
    assert.deepEqual(
      entries.map((e) => new TextDecoder().decode(e.data)),
      ['a', 'b', 'c', 'd']
    )
  })

  test('the contents are stored whole, whatever they hold', () => {
    const binary = new Uint8Array(300).map((_, i) => (i * 7) % 256)
    const entries = readZip(
      createZip([
        file('empty.l4', ''),
        { name: 'bytes.l4', content: binary },
        file('עברית.l4', 'כלל אחד\n'),
      ])
    )
    assert.deepEqual(entries[0].data, new Uint8Array(0))
    assert.deepEqual(entries[1].data, binary)
    assert.equal(new TextDecoder().decode(entries[2].data), 'כלל אחד\n')
  })

  test('no files make an empty zip that reads as no entries', () => {
    assert.deepEqual(readZip(createZip([])), [])
  })
})

describe('createZip: against the writer before the flag', () => {
  const asciiProjects: Record<string, { name: string; content: Uint8Array }[]> =
    {
      'one flat file': [file('main.l4', 'IMPORT helper\n')],
      'a flat project': [
        file('main.l4', 'a'),
        file('helper.l4', 'b'),
        file('daydate.l4', 'c'),
      ],
      folders: [
        file('a/main.l4', 'a'),
        file('b/mod.l4', 'b'),
        file('defs.l4', 'c'),
      ],
      'names with spaces and punctuation': [
        file('my rules/rate table.l4', 'a'),
        file("v1.2 (draft)/it's.l4", 'b'),
      ],
      'empty and binary contents': [
        file('empty.l4', ''),
        {
          name: 'bytes.l4',
          content: new Uint8Array(1000).map((_, i) => (i * 31) % 256),
        },
      ],
      'contents that are not ASCII under ASCII names': [
        file('a/main.l4', 'כלל אחד\n'),
      ],
      'no files': [],
    }
  for (const [label, files] of Object.entries(asciiProjects)) {
    test(`ASCII names (${label}): the same bytes as before`, () => {
      assert.deepEqual(createZip(files), createZipBeforeTheFlag(files))
    })
  }

  test('a name that is not ASCII changes the flag bytes of its two headers and nothing else', () => {
    const files = [
      file('main.l4', 'abc'),
      file('תיקייה/main.l4', 'defgh'),
      file('lib/x.l4', 'i'),
    ]
    const now = createZip(files)
    const before = createZipBeforeTheFlag(files)
    assert.equal(now.length, before.length)
    const differing = [...now.keys()].filter((i) => now[i] !== before[i])

    // Local header of the second entry: after the first entry (30 + 7 + 3 bytes),
    // the flags are at +6 and the UTF-8 bit is in the high byte, at +7.
    const secondLocal = 30 + 'main.l4'.length + 3
    // Central header of the second entry: after the central directory's first
    // entry (46 + 7 bytes); its flags are at +8, the high byte at +9.
    const localEnd =
      secondLocal +
      30 +
      bytesOf('תיקייה/main.l4').length +
      5 +
      30 +
      'lib/x.l4'.length +
      1
    const secondCentral = localEnd + 46 + 'main.l4'.length
    assert.deepEqual(differing, [secondLocal + 7, secondCentral + 9])
    assert.equal(now[secondLocal + 7], 0x08)
    assert.equal(now[secondCentral + 9], 0x08)
  })
})
