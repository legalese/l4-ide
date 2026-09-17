import { describe, it, expect } from 'vitest'
import type { FunDecl } from '@repo/ladder-core'
import { elementPaths, valuationFor, pathByNode } from './valuation'

// A hand-built ladder in ladder-core's IR: (f's a AND "and" AND cheats f) OR f's `b c`
const fn: FunDecl = {
  id: 0,
  name: '`offence under s 999`',
  params: ['f'],
  body: {
    $type: 'Or',
    id: 1,
    args: [
      {
        $type: 'And',
        id: 2,
        args: [
          { $type: 'UBoolVar', id: 3, label: "f's a", unique: 10 },
          { $type: 'InertE', id: 4, text: 'and', context: 'InertAnd' },
          { $type: 'UBoolVar', id: 5, label: 'cheats OF f', unique: 12 },
        ],
      },
      { $type: 'UBoolVar', id: 6, label: "f's `b c`", unique: 11 },
    ],
  },
}

describe('valuation from a facts record', () => {
  it('lists the element paths in ladder order, once each', () => {
    expect(elementPaths(fn, 'f')).toEqual([['a'], ['b c']])
  })
  it('values projections from facts and calls from the supplied verdicts', () => {
    const v = valuationFor(
      fn,
      'f',
      { a: true },
      new Map([['cheats', 'FalseV']])
    )
    expect(v.get(3)).toBe('TrueV')
    expect(v.get(5)).toBe('FalseV')
    expect(v.get(6)).toBe('UnknownV')
  })
  it('routes a node id back to its field', () => {
    expect(pathByNode(fn, 'f').get(6)).toEqual(['b c'])
    expect(pathByNode(fn, 'f').has(5)).toBe(false)
  })
})
