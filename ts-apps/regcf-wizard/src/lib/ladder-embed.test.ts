import { describe, it, expect } from 'vitest'
import {
  fromVizFunDecl,
  defaultViewSpec,
  layout,
  estimateMetrics,
  PIXEL_GEOMETRY,
} from '@repo/ladder-core'
import { sceneToSvg } from '@repo/ladder-svg'
import liveLadder from './__fixtures__/live-ladder.json'
import livePlan from './__fixtures__/live-query-plan.json'
import type { NodeId, UBoolValue } from '@repo/ladder-core'

/**
 * The machine half of the ladder-embed gate.
 *
 * `Ladder.svelte` is listener plumbing plus `LadderController`; the controller's
 * own header records why its DOM residue is checked by hand rather than by a
 * `jsdom` dependency (EMBEDDABLE.md §3.5 flags that dependency as a merge-queue
 * hazard). Everything BELOW the DOM, though — decode, join, valuation, layout,
 * emit — is pure, and this is where it is checked, against the VERBATIM payloads
 * the loopback service returned.
 *
 * The manual browser gate that covers the rest is in this app's README.
 */

function decode() {
  return fromVizFunDecl(
    (liveLadder as { funDecl: unknown }).funDecl as Parameters<
      typeof fromVizFunDecl
    >[0]
  )
}

function render(valuation: Map<NodeId, UBoolValue>): string {
  const { fn } = decode()
  const scene = layout(
    fn,
    defaultViewSpec({ valuation, showCurrent: true }),
    estimateMetrics,
    PIXEL_GEOMETRY
  )
  return sceneToSvg(scene)
}

describe('the live ladder payload decodes', () => {
  it('is an AND of the two limbs of `can this company raise`', () => {
    const { fn } = decode()
    expect(fn.name).toBe('`can this company raise`')
    expect(fn.body.$type).toBe('And')
  })

  it('carries no valuation of its own — every leaf is UnknownV on the wire', () => {
    // Measured, and load-bearing: the payload stays UnknownV even when the
    // query-plan call binds an atom, so the picture's valuation is the client's.
    const { valuation } = decode()
    expect([...valuation.values()].every((v) => v === 'UnknownV')).toBe(true)
  })
})

describe('the ladder/query-plan join key', () => {
  const { uniqueByNode, nodesByUnique } = decode()
  const plan = livePlan as { ranked: { atomId: string; unique: number }[] }

  it('joins on `unique`: every ranked atom has a box in the picture', () => {
    for (const atom of plan.ranked) {
      expect(nodesByUnique.get(atom.unique)?.length ?? 0).toBeGreaterThan(0)
    }
    expect([...uniqueByNode.values()].sort()).toEqual([4, 6])
  })

  it('does NOT join on `atomId` — the two payloads disagree about it', () => {
    // This is the trap `api/client.ts#queryPlan` documents. For unique 4 the
    // ladder says 64e895d0-… and the plan says a87d9b26-…; a client that keyed
    // on atomId would draw one diagram and answer a different question, and the
    // service would answer 200 the whole way.
    const { atomIdByNode } = decode()
    const ladderAtomIds = new Set(atomIdByNode.values())
    for (const atom of plan.ranked) {
      expect(ladderAtomIds.has(atom.atomId)).toBe(false)
    }
  })
})

describe('the emitted SVG', () => {
  it('renders both limbs by name', () => {
    const svg = render(new Map())
    expect(svg).toContain('issuer is eligible')
    expect(svg).toContain('offering is within the offering limit')
  })

  it('emits NO inline style attribute — which is what keeps style-src strict', () => {
    // The app's CSP is `style-src 'self'` with no 'unsafe-inline'. An embed that
    // emitted style="…" would be silently unstyled in the BUILT app while
    // looking fine in dev. `sceneToSvg` uses presentational SVG attributes only,
    // and `LadderController` writes styles through the CSSOM, which style-src
    // does not govern.
    for (const valuation of [
      new Map<NodeId, UBoolValue>(),
      new Map<NodeId, UBoolValue>([[3, 'TrueV']]),
    ]) {
      expect(render(valuation)).not.toMatch(/\sstyle\s*=/)
    }
  })

  it('changes when the client-side valuation changes', () => {
    const { nodesByUnique } = decode()
    const node = nodesByUnique.get(4)![0]
    const before = render(new Map())
    const after = render(new Map<NodeId, UBoolValue>([[node, 'TrueV']]))
    expect(after).not.toBe(before)
  })
})
