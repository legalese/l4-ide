/**
 * LadderModel (E1 Step 3). The load-bearing claim: feeding the RAW wire FunDecl to the existing
 * Evaluator + PartialEvalAnalyzer keeps the IMPLIES seam alive to the verdict — the §25f fix,
 * end-to-end, WITHOUT `expandImplies`. So the sharp tests are the two the old header could not
 * express: a vacuous scope reads `NotApplicable` (not "TRUE"), and a met requirement under an
 * unknown scope stays `Undetermined` (not settled).
 *
 * Fixtures are App-free, so the backend is never consulted and the mock below is never called;
 * the model's async `recompute()` resolves without a live LSP.
 */
import { describe, expect, it } from 'vitest'
import type {
  FunDecl as VizFunDecl,
  IRExpr,
  VersionedDocId,
} from '@repo/viz-expr'
import { LadderModel } from '../lib/model/ladder-model.js'
import type { L4Connection } from '../lib/l4-connection.js'

const nm = (label: string, unique: number) => ({ label, unique })
const iid = (id: number) => ({ id })
const ubool = (id: number, unique: number, label: string): IRExpr => ({
  $type: 'UBoolVar',
  id: iid(id),
  name: nm(label, unique),
  value: 'UnknownV',
  canInline: false,
  atomId: `atom-${unique}`,
})
const and = (id: number, args: IRExpr[]): IRExpr => ({
  $type: 'And',
  id: iid(id),
  args,
})

// (upper AND side) IMPLIES (glazed AND shut) — the seam, in wire form.
const seamFn: VizFunDecl = {
  $type: 'FunDecl',
  id: iid(100),
  name: nm('compliant', 1),
  params: [],
  body: {
    $type: 'Implies',
    id: iid(2),
    scope: and(3, [ubool(4, 40, 'upper'), ubool(5, 41, 'side')]),
    requirement: and(6, [ubool(7, 42, 'glazed'), ubool(8, 43, 'shut')]),
    seam: 'IMPLIES',
  },
}

// never actually invoked (no App leaves); present only to satisfy the constructor.
const deps = {
  l4Connection: {
    evalApp: () => {
      throw new Error('evalApp must not be called for an App-free tree')
    },
  } as unknown as L4Connection,
  verDocId: {} as VersionedDocId,
}

const mk = () => new LadderModel(seamFn, deps)
// node ids of the two AND groups, to read their derived value
const SCOPE = 3
const REQUIREMENT = 6

describe('LadderModel — the seam survives to the verdict', () => {
  it('scope FALSE ⇒ NotApplicable, and the function value is a vacuous TRUE (§25f)', async () => {
    const m = mk()
    m.setValue(4, 'FalseV') // upper = false ⇒ scope AND is false
    await m.recompute()
    expect(m.verdict).toBe('NotApplicable')
    // the function itself is TRUE (vacuously) — the exact trap the header must not fall into
    expect(m.valuation.get(2)).toBe('TrueV')
    expect(m.valuation.get(SCOPE)).toBe('FalseV')
  })

  it('scope UNKNOWN, requirement MET ⇒ Undetermined, not settled (the short-circuit trap)', async () => {
    const m = mk()
    m.setValue(7, 'TrueV') // glazed
    m.setValue(8, 'TrueV') // shut ⇒ requirement met, function vacuously TRUE
    await m.recompute()
    expect(m.valuation.get(REQUIREMENT)).toBe('TrueV')
    expect(m.verdict).toBe('Undetermined') // NOT Complies: we do not know if the rule bit
  })

  it('scope TRUE + requirement TRUE ⇒ Complies', async () => {
    const m = mk()
    for (const id of [4, 5, 7, 8]) m.setValue(id, 'TrueV')
    await m.recompute()
    expect(m.verdict).toBe('Complies')
    expect(m.isDetermined).toBe(true)
  })

  it('scope TRUE + requirement FALSE ⇒ InBreach', async () => {
    const m = mk()
    m.setValue(4, 'TrueV')
    m.setValue(5, 'TrueV')
    m.setValue(7, 'FalseV') // glazed false ⇒ requirement false
    await m.recompute()
    expect(m.verdict).toBe('InBreach')
  })
})

describe('LadderModel — projection and elicitation', () => {
  it('valuation projects the eval result keyed by node id (IRId = NodeId)', async () => {
    const m = mk()
    m.setValue(4, 'TrueV')
    await m.recompute()
    // node 4's own value round-trips, and the scope group is still unknown (side unset)
    expect(m.valuation.get(4)).toBe('TrueV')
    expect(m.valuation.get(SCOPE)).toBe('UnknownV')
  })

  it('before recompute, valuation falls back to the lifted inline values', () => {
    const m = mk()
    // all UnknownV inline ⇒ empty valuation, and the verdict is Undetermined, not a crash
    expect(m.valuation.size).toBe(0)
    expect(m.verdict).toBe('Undetermined')
  })

  it('elicitation marks land on real node ids drawn from the analysis', async () => {
    const m = mk()
    await m.recompute()
    const marks = m.elicitationMarks
    // nothing is settled, so at least one atom is worth asking; every marked id is a real leaf
    expect(marks.size).toBeGreaterThan(0)
    const leafIds = new Set([4, 5, 7, 8])
    for (const id of marks.keys()) expect(leafIds.has(id)).toBe(true)
  })

  it('cycleValue on a non-atom (a group) is a no-op; on an atom it advances', () => {
    const m = mk()
    expect(m.cycleValue(SCOPE)).toBe(false) // an AND group has no Unique
    expect(m.cycleValue(4)).toBe(true) // a UBoolVar does
  })

  it('the viewSpec projects valuation, and eliminable states mirror the analysis 1:1', async () => {
    const m = mk()
    m.setValue(4, 'FalseV') // scope false ⇒ the function short-circuits
    await m.recompute()
    const vs = m.viewSpec
    expect(vs.valuation.get(SCOPE)).toBe('FalseV')

    // This is LadderModel's own contract: whatever the analysis calls irrelevant shows up as
    // `eliminable`, keyed by NodeId (IRId.id) — nothing more, nothing less. We assert the
    // PROJECTION is faithful, not what the analyzer chooses to mark (that is its own suite).
    const expected = new Set(
      [...(m.analysis?.irrelevantRootIds ?? [])].map((ir) => ir.id)
    )
    const eliminable = new Set(
      [...vs.states.entries()]
        .filter(([, s]) => s === 'eliminable')
        .map(([id]) => id)
    )
    expect(eliminable).toEqual(expected)
  })
})

describe('LadderModel — a plain (no-seam) function still works', () => {
  const plainFn: VizFunDecl = {
    $type: 'FunDecl',
    id: iid(200),
    name: nm('plain', 9),
    params: [],
    body: and(20, [ubool(21, 90, 'a'), ubool(22, 91, 'b')]),
  }
  it('reports Holds / Fails, not a compliance verdict', async () => {
    const m = new LadderModel(plainFn, deps)
    m.setValue(21, 'TrueV')
    m.setValue(22, 'TrueV')
    await m.recompute()
    expect(m.verdict).toBe('Holds')
  })
})
