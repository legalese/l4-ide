import { describe, it, expect } from 'vitest'
import { EMPTY_GRAPH } from './types'
import { addFact, addSource, layoutDag, support } from './graph'
import { forceLayoutDag } from './force-layout'

let g = EMPTY_GRAPH
g = addSource(g, {
  id: 's1',
  kind: 'witness-statement-s22',
  title: 'Statement of A',
  maker: 'A',
})
g = addSource(g, { id: 's2', kind: 'exhibit', title: 'P1 — the tag' })
g = addFact(g, {
  id: 'f1',
  text: 'The tag read $5.25.',
  sourceIds: ['s1', 's2'],
})
g = addFact(g, {
  id: 'f2',
  text: 'She admitted swapping it.',
  sourceIds: ['s1'],
})
g = support(g, {
  section: '420',
  field: 'deceived the victim',
  factIds: ['f1'],
})
g = support(g, { section: '420', field: 'dishonestly', factIds: ['f2'] })
const dag = layoutDag(g, '420', 'cheating', [
  'deceived the victim',
  'dishonestly',
  'deliver',
])

describe('force layout', () => {
  const out = forceLayoutDag(dag)
  it('keeps every node in its rank column, left to right', () => {
    const xs = [0, 1, 2, 3].map(
      (c) => new Set(out.nodes.filter((n) => n.col === c).map((n) => n.x))
    )
    for (const s of xs) expect(s.size).toBe(1)
    const [a, b, c, d] = xs.map((s) => [...s][0])
    expect(a < b && b < c && c < d).toBe(true)
  })
  it('is deterministic and keeps nodes inside the drawing', () => {
    const again = forceLayoutDag(dag)
    expect(again.nodes.map((n) => [n.id, n.y])).toEqual(
      out.nodes.map((n) => [n.id, n.y])
    )
    for (const n of out.nodes) {
      expect(n.y - n.h / 2).toBeGreaterThanOrEqual(0)
      expect(n.y + n.h / 2).toBeLessThanOrEqual(out.height)
    }
  })
  it('separates nodes that share a column', () => {
    const els = out.nodes.filter((n) => n.col === 1).sort((p, q) => p.y - q.y)
    for (let i = 1; i < els.length; i++)
      expect(els[i].y - els[i - 1].y).toBeGreaterThan(els[i].h)
  })
  it('keeps every edge', () => {
    expect(out.edges).toHaveLength(dag.edges.length)
  })
})
