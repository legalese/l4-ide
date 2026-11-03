import { describe, expect, it } from 'vitest'
import type { LirContext } from '@repo/layout-ir'
import type { QueryPlanDecline, QueryPlanResponse } from 'jl4-client-rpc'
import type { PartialEvalAnalysis } from '../lib/eval/partial-eval.js'
import {
  elicitationOverrideFromQueryPlan,
  withElicitationOverride,
} from '../lib/eval/query-plan-override.js'

// The ladder's atoms: one atom per unique, found by its id.
const ladderGraph = {
  getUniquesForAtomId: (_context: LirContext, atomId: string) =>
    atomId === 'atom-adult' ? [1] : [],
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

// The ladder's own analysis, with an input it needs and one it does not.
const analysis = {
  next: [1],
  stillNeeded: [1],
  ranked: [1],
  dontCare: [2],
  askByUnique: new Map(),
} as unknown as PartialEvalAnalysis

describe('withElicitationOverride', () => {
  it('classes no input as needed or moot, and carries the sentence, for a rule the planner declines', () => {
    const shown = withElicitationOverride(
      analysis,
      elicitationOverrideFromQueryPlan(context, ladderGraph, declined)
    )
    expect(shown.declined).toBe(declined.error)
    expect(shown.stillNeeded).toEqual([])
    expect(shown.ranked).toEqual([])
    expect(shown.next).toEqual([])
    expect(shown.dontCare).toEqual([])
  })

  it("keeps the ladder's moot inputs and carries no decline, for a plan", () => {
    const shown = withElicitationOverride(
      analysis,
      elicitationOverrideFromQueryPlan(context, ladderGraph, plan)
    )
    expect(shown.declined).toBeUndefined()
    expect(shown.stillNeeded).toEqual([1])
    expect(shown.dontCare).toEqual([2])
  })
})
