import { describe, expect, it } from 'vitest'
import type { LirContext } from '@repo/layout-ir'
import type { QueryPlanDecline, QueryPlanResponse } from 'jl4-client-rpc'
import { elicitationOverrideFromQueryPlan } from '../lib/eval/query-plan-override.js'

// The ladder's atoms: one atom per unique, found by its id.
const ladderGraph = {
  getUniquesForAtomId: (_context: LirContext, atomId: string) =>
    atomId === 'atom-adult' ? [1] : atomId === 'atom-resident' ? [2] : [],
  getUniquesForLabel: () => [],
}
const context = {} as LirContext

const declined: QueryPlanDecline = {
  error:
    'No query plan for covered: it may refuse to answer, with the reason "insurance is not modelled".',
  kind: 'declined',
  rule: 'covered',
  reasons: ['insurance is not modelled'],
}

const adult = { unique: 1, atomId: 'atom-adult', label: 'adult' }

const plan: QueryPlanResponse = {
  determined: null,
  stillNeeded: [adult],
  ranked: [adult],
  inputs: [],
  asks: [],
  impact: {},
  impactByAtomId: {},
  note: '',
}

describe('elicitationOverrideFromQueryPlan', () => {
  it('asks for nothing and carries the sentence, for a rule the planner declines', () => {
    const override = elicitationOverrideFromQueryPlan(
      context,
      ladderGraph,
      declined
    )
    expect(override.declined).toBe(declined.error)
    expect(override.ranked).toEqual([])
    expect(override.stillNeeded).toEqual([])
    expect(override.next).toEqual([])
    expect(override.askByUnique.size).toBe(0)
  })

  it('carries no decline, for a plan', () => {
    const override = elicitationOverrideFromQueryPlan(
      context,
      ladderGraph,
      plan
    )
    expect(override.declined).toBeUndefined()
    expect(override.stillNeeded).toEqual([1])
    expect(override.ranked).toEqual([1])
  })
})
