import { describe, it, expect } from 'vitest'
import { EMPTY_GRAPH } from './types'
import { addFact, addSource, factsFor, gaps, layoutDag, support } from './graph'

const g = support(
  addFact(
    addSource(EMPTY_GRAPH, {
      id: 's1',
      kind: 'witness-statement-s22',
      title: 'Statement of Wong Fei Hsia',
      maker: 'Wong Fei Hsia',
    }),
    { id: 'f1', text: 'The tag on the casing read $5.25.', sourceIds: ['s1'] }
  ),
  { section: '420', field: 'deceived the victim', factIds: ['f1'] }
)

describe('evidence graph', () => {
  it('finds the facts under an element and the gaps beside it', () => {
    expect(factsFor(g, '420', 'deceived the victim').map((f) => f.id)).toEqual([
      'f1',
    ])
    expect(gaps(g, '420', ['deceived the victim', 'dishonestly'])).toEqual([
      'dishonestly',
    ])
  })
  it('replaces rather than duplicates a support edge', () => {
    const g2 = support(g, {
      section: '420',
      field: 'deceived the victim',
      factIds: [],
    })
    expect(g2.support).toHaveLength(1)
    expect(factsFor(g2, '420', 'deceived the victim')).toEqual([])
  })
  it('lays out four columns with a gap marked on an unsupported element', () => {
    const dag = layoutDag(g, '420', 'cheating', [
      'deceived the victim',
      'dishonestly',
    ])
    const cols = new Set(dag.nodes.map((n) => n.col))
    expect([...cols].sort()).toEqual([0, 1, 2, 3])
    expect(dag.nodes.find((n) => n.id === 'el:dishonestly')?.gap).toBe(true)
    expect(dag.nodes.find((n) => n.id === 'el:deceived the victim')?.gap).toBe(
      false
    )
    expect(dag.edges).toContainEqual({ from: 'fact:f1', to: 'src:s1' })
    expect(dag.rows).toBe(2)
  })
})
