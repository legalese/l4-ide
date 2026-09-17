import { describe, it, expect } from 'vitest'
import { parseLeafLabel, readAt, writeAt, cycle } from './leaf-field'

describe('parseLeafLabel — the ladder→field join', () => {
  it('reads a bare projection', () => {
    expect(parseLeafLabel("f's deliver", 'f')).toEqual({
      kind: 'projection',
      path: ['deliver'],
    })
  })
  it('reads a backticked projection with spaces and commas', () => {
    expect(
      parseLeafLabel("f's `make, alter or destroy a valuable security`", 'f')
    ).toEqual({
      kind: 'projection',
      path: ['make, alter or destroy a valuable security'],
    })
  })
  it('reads a nested projection through a sub-record', () => {
    expect(parseLeafLabel("f's theft's `movable property`", 'f')).toEqual({
      kind: 'projection',
      path: ['theft', 'movable property'],
    })
  })
  it('does not split on an apostrophe-s inside backticks', () => {
    expect(parseLeafLabel("f's `without that person's consent`", 'f')).toEqual({
      kind: 'projection',
      path: ["without that person's consent"],
    })
  })
  it('recognises a call to another rule, bare or backticked', () => {
    expect(parseLeafLabel('cheats OF f', 'f')).toEqual({
      kind: 'call',
      fn: 'cheats',
    })
    expect(parseLeafLabel("`commits theft` OF f's theft", 'f')).toEqual({
      kind: 'call',
      fn: 'commits theft',
    })
  })
  it('leaves anything else opaque', () => {
    expect(parseLeafLabel('TRUE', 'f')).toEqual({
      kind: 'opaque',
      label: 'TRUE',
    })
  })
})

describe('readAt / writeAt / cycle', () => {
  const facts = { deliver: true, theft: { dishonestly: false }, victim: 'X' }
  it('reads booleans at depth and nothing else', () => {
    expect(readAt(facts, ['deliver'])).toBe(true)
    expect(readAt(facts, ['theft', 'dishonestly'])).toBe(false)
    expect(readAt(facts, ['victim'])).toBeUndefined()
    expect(readAt(facts, ['nope', 'x'])).toBeUndefined()
  })
  it('writes without mutating', () => {
    const out = writeAt(facts, ['theft', 'dishonestly'], true)
    expect(readAt(out, ['theft', 'dishonestly'])).toBe(true)
    expect(readAt(facts, ['theft', 'dishonestly'])).toBe(false)
    expect(out.victim).toBe('X')
  })
  it('cycles Unknown→True→False→True', () => {
    expect(cycle(undefined)).toBe(true)
    expect(cycle(true)).toBe(false)
    expect(cycle(false)).toBe(true)
  })
})
