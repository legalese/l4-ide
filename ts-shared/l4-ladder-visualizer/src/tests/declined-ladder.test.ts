import { describe, expect, it } from 'vitest'
import { render } from 'svelte/server'
import { LirContext, LirRegistry } from '@repo/layout-ir'
import type { IRExpr } from '@repo/viz-expr'
import type { LadderBackendApi, QueryPlanDecline } from 'jl4-client-rpc'
import { LadderEnv } from '../lib/ladder-env.js'
import { LadderGraphLirSource } from '../lib/data/viz-expr-to-lir.js'
import { elicitationOverrideFromQueryPlan } from '../lib/eval/query-plan-override.js'
import { FalseVal } from '../lib/eval/type.js'
import { isUBoolVarLirNode } from '../lib/layout-ir/ladder-graph/ladder.svelte.js'
import PartialEvalSidebar from '../lib/displayers/partial-eval/partial-eval-sidebar.svelte'

const declined: QueryPlanDecline = {
  error:
    'No query plan for covered: it may refuse to answer, with the reason "insurance is not modelled".',
  kind: 'declined',
  rule: 'covered',
  reasons: ['insurance is not modelled'],
}

// A backend that answers no request.
const backend: LadderBackendApi = {
  sendClientRequest: async () => null,
  updateViz: async () => {},
}

function input(id: number, unique: number, label: string): IRExpr {
  return {
    $type: 'UBoolVar',
    id: { id },
    name: { unique, label },
    value: 'UnknownV',
    canInline: false,
    atomId: `atom-${label}`,
  }
}

// The ladder of `adult AND insured`, as it is drawn.
const adultAndInsured: IRExpr = {
  $type: 'And',
  id: { id: 3 },
  args: [input(1, 1, 'adult'), input(2, 2, 'insured')],
}

async function ladder(expr: IRExpr = adultAndInsured) {
  const context = new LirContext()
  const registry = new LirRegistry()
  const env = LadderEnv.make(
    registry,
    { uri: 'file:///covered.l4', version: 1 },
    backend,
    'VizFunDecl'
  )
  const ladderGraph = await LadderGraphLirSource.toLir(
    { context, registry },
    env,
    expr
  )
  return { context, ladderGraph }
}

// The same ladder, with the planner's decline set on it, as the VS Code
// webview and the web editor set it when the planner declines.
async function declinedLadder() {
  const { context, ladderGraph } = await ladder()
  ladderGraph.setElicitationOverride(
    context,
    elicitationOverrideFromQueryPlan(context, ladderGraph, declined)
  )
  return { context, ladderGraph }
}

// The ladder of `(adult OR resident) AND insured`, with insured answered
// FALSE, which settles it as FALSE and leaves adult and resident moot, as
// the ladder reads AND. For a rule whose first condition may refuse,
// evaluation reaches that condition first, and refuses.
async function answered(decline: boolean) {
  const { context, ladderGraph } = await ladder({
    $type: 'And',
    id: { id: 5 },
    args: [
      {
        $type: 'Or',
        id: { id: 3 },
        args: [input(1, 1, 'adult'), input(2, 2, 'resident')],
      },
      input(4, 3, 'insured'),
    ],
  })
  await ladderGraph.submitNewBinding(context, {
    unique: 3,
    value: new FalseVal(),
  })
  if (decline) {
    ladderGraph.setElicitationOverride(
      context,
      elicitationOverrideFromQueryPlan(context, ladderGraph, declined)
    )
  }
  return { context, ladderGraph }
}

// The inputs and the lines the ladder draws as moot.
function moot(
  context: LirContext,
  ladderGraph: Awaited<ReturnType<typeof ladder>>['ladderGraph']
) {
  return {
    inputs: ladderGraph
      .getVertices(context)
      .filter(isUBoolVarLirNode)
      .filter((node) => ladderGraph.nodeIsInIrrelevantSubgraph(context, node))
      .map((node) => node.getLabel(context)),
    lines: ladderGraph
      .getEdges(context)
      .filter((edge) => ladderGraph.edgeIsInIrrelevantSubgraph(context, edge))
      .length,
  }
}

function sidebar(
  context: LirContext,
  ladderGraph: Awaited<ReturnType<typeof ladder>>['ladderGraph']
) {
  return render(PartialEvalSidebar, {
    props: {
      context,
      ladderGraph,
      analysis: ladderGraph.getPartialEvalAnalysis(context),
      onClose: () => {},
    },
  }).body
}

describe('a ladder whose rule the planner declines', () => {
  it("carries the sentence in the ladder's analysis, and classes no input as needed or moot", async () => {
    const { context, ladderGraph } = await declinedLadder()
    const analysis = ladderGraph.getPartialEvalAnalysis(context)
    expect(analysis?.declined).toBe(declined.error)
    expect(analysis?.stillNeeded).toEqual([])
    expect(analysis?.ranked).toEqual([])
    expect(analysis?.dontCare).toEqual([])
  })

  it('shows the sentence in the inputs sidebar under "No query plan", in place of the inputs still needed and moot', async () => {
    const drawn = await ladder()
    const undeclined = sidebar(drawn.context, drawn.ladderGraph)
    expect(undeclined).toContain('Still Needed')
    expect(undeclined).toContain('Moot')
    expect(undeclined).not.toContain('No query plan')

    const { context, ladderGraph } = await declinedLadder()
    const body = sidebar(context, ladderGraph)
    expect(body).toContain('No query plan')
    expect(body).toContain('insurance is not modelled')
    expect(body).not.toContain('Still Needed')
    expect(body).not.toContain('Moot')
  })

  it('gives no answer and draws no input as moot, once an input is answered, where the ladder alone would say FALSE', async () => {
    const drawn = await answered(false)
    expect(drawn.ladderGraph.getResult(drawn.context).toPretty()).toBe('FALSE')
    expect(
      drawn.ladderGraph.getPartialEvalAnalysis(drawn.context)?.isDetermined
    ).toBe(true)
    const drawnMoot = moot(drawn.context, drawn.ladderGraph)
    expect(drawnMoot.inputs.sort()).toEqual(['adult', 'resident'])
    expect(drawnMoot.lines).toBeGreaterThan(0)
    const undeclined = sidebar(drawn.context, drawn.ladderGraph)
    expect(undeclined).toContain('Simplified')
    expect(undeclined).toMatch(/Result: <span[^>]*>FALSE</)

    const { context, ladderGraph } = await answered(true)
    expect(ladderGraph.getResult(context).toPretty()).toBe('UNKNOWN')
    const analysis = ladderGraph.getPartialEvalAnalysis(context)
    expect(analysis?.declined).toBe(declined.error)
    expect(analysis?.isDetermined).toBe(false)
    expect(analysis?.overallResult.toPretty()).toBe('UNKNOWN')
    expect(analysis?.restrictedExprText).toBe('')
    expect([...(analysis?.irrelevantRootIds ?? [])]).toEqual([])
    expect(moot(context, ladderGraph)).toEqual({ inputs: [], lines: 0 })
    const body = sidebar(context, ladderGraph)
    expect(body).toContain('No query plan')
    expect(body).not.toContain('Simplified')
    expect(body).not.toContain('Result:')
    expect(body).not.toContain('FALSE')
  })
})
