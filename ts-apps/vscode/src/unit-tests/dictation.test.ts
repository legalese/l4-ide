import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import { encodeWav } from '../ai/dictation.js'

describe('encodeWav', () => {
  test('writes a canonical 16-bit mono PCM header', () => {
    const wav = encodeWav(new Int16Array(16_000), 16_000)
    assert.equal(wav.length, 44 + 32_000)
    assert.equal(wav.toString('ascii', 0, 4), 'RIFF')
    assert.equal(wav.readUInt32LE(4), 36 + 32_000)
    assert.equal(wav.toString('ascii', 8, 16), 'WAVEfmt ')
    assert.equal(wav.readUInt16LE(20), 1) // PCM
    assert.equal(wav.readUInt16LE(22), 1) // mono
    assert.equal(wav.readUInt32LE(24), 16_000)
    assert.equal(wav.readUInt32LE(28), 32_000) // bytes per second
    assert.equal(wav.readUInt16LE(32), 2) // block align
    assert.equal(wav.readUInt16LE(34), 16) // bits per sample
    assert.equal(wav.toString('ascii', 36, 40), 'data')
    assert.equal(wav.readUInt32LE(40), 32_000)
  })

  test('stores samples little-endian, sign preserved', () => {
    const wav = encodeWav(new Int16Array([0, 1, -1, 32767, -32768]), 16_000)
    assert.deepEqual(
      [0, 1, 2, 3, 4].map((i) => wav.readInt16LE(44 + i * 2)),
      [0, 1, -1, 32767, -32768]
    )
  })
})
