import { describe, expect, it } from 'vitest'
import { ROBDD } from '../robdd.js'

describe('ROBDD.prob (model count in probability space)', () => {
  it('terminals are 0 and 1', () => {
    const b = new ROBDD()
    expect(b.prob(ROBDD.TRUE)).toBe(1)
    expect(b.prob(ROBDD.FALSE)).toBe(0)
  })

  it('a single variable is 0.5 prior-free, and honours weights', () => {
    const b = new ROBDD()
    const x = b.var(0)
    expect(b.prob(x)).toBeCloseTo(0.5)
    expect(b.prob(x, new Map([[0, 0.9]]))).toBeCloseTo(0.9)
    expect(b.prob(x, new Map([[0, 0]]))).toBeCloseTo(0)
  })

  it('and / or give the right model counts', () => {
    const b = new ROBDD()
    const x = b.var(0)
    const y = b.var(1)
    expect(b.prob(b.apply('and', x, y))).toBeCloseTo(0.25)
    expect(b.prob(b.apply('or', x, y))).toBeCloseTo(0.75)
  })

  it('is skip-safe: a variable absent from the function does not affect prob', () => {
    const b = new ROBDD()
    const x = b.var(0)
    // index 1 never appears in `x`; weighting it must not change the answer.
    expect(b.prob(x, new Map([[1, 0.9]]))).toBeCloseTo(0.5)
  })
})
