import { describe, it, expect } from 'vitest'
import { matchPreload } from './preload'
import { PRELOADS } from './preloads'

describe('preload matching', () => {
  it('matches the widget text exactly, modulo whitespace', () => {
    const p = PRELOADS[0]
    expect(matchPreload(p.prompt, PRELOADS)?.id).toBe(p.id)
    expect(
      matchPreload('  ' + p.prompt.replace(/\n/g, ' ') + '\n', PRELOADS)?.id
    ).toBe(p.id)
  })
  it('does not match an edited prompt', () => {
    expect(matchPreload(PRELOADS[0].prompt + ' also', PRELOADS)).toBeUndefined()
  })
  it('every preload proposes at least one charge with a facts record', () => {
    for (const p of PRELOADS) {
      expect(p.result.charges.length).toBeGreaterThan(0)
      for (const c of p.result.charges) expect(typeof c.facts).toBe('object')
    }
  })
})
