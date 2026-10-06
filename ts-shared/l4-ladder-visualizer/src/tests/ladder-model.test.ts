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

/**
 * The Unique-space surface the Step-4 sidebar reuse needs. Tested here, in the model, rather
 * than through the shell: the sidebar assigns by `Unique` while a click on the picture
 * assigns by `NodeId`, and R2 ("a binding must fan out to every drawn position") is a claim
 * about what the MODEL does with a repeated atom, not about Svelte.
 */
describe('LadderModel — Unique-space bindings and labels (the sidebar surface)', () => {
  // `dry` appears TWICE: two NodeIds, one Unique. That is R2's whole shape.
  const repeatedFn: VizFunDecl = {
    $type: 'FunDecl',
    id: iid(300),
    name: nm('repeated', 30),
    params: [],
    body: and(31, [
      ubool(32, 70, 'dry'),
      and(33, [ubool(34, 70, 'dry'), ubool(35, 71, 'sunny')]),
    ]),
  }
  const mkRepeated = () => new LadderModel(repeatedFn, deps)

  it('getLabelForUnique returns the leaf label, and is stable for a repeated atom', () => {
    const m = mkRepeated()
    expect(m.getLabelForUnique(70)).toBe('dry')
    expect(m.getLabelForUnique(71)).toBe('sunny')
    // twice, to exercise the memo as well as the walk
    expect(m.getLabelForUnique(70)).toBe('dry')
  })

  it('getLabelForUnique falls back to #<unique> for an atom the drawn tree lacks', () => {
    expect(mkRepeated().getLabelForUnique(9999)).toBe('#9999')
  })

  it('setValueForUnique reaches EVERY drawn position of a repeated atom (R2)', async () => {
    const m = mkRepeated()
    m.setValueForUnique(70, 'TrueV')
    await m.recompute()
    const v = m.valuation
    expect(v.get(32)).toBe('TrueV')
    expect(v.get(34)).toBe('TrueV')
  })

  it('setValueForUnique on an unknown Unique is accepted and simply never read', async () => {
    const m = mkRepeated()
    expect(() => m.setValueForUnique(4242, 'FalseV')).not.toThrow()
    await m.recompute()
    expect(m.verdict).toBe('Undetermined')
  })

  it('the label index is built off the DRAWN tree, so an Implies seam is walked too', () => {
    const m = mk()
    expect(m.getLabelForUnique(40)).toBe('upper') // in the scope
    expect(m.getLabelForUnique(43)).toBe('shut') // in the requirement
  })
})

/**
 * One click, every copy: the IDE follows the playground's rule (ladder-core `spreadValue`).
 * Two boxes are the same proposition when they share an atomId, and a compound leaf's
 * Unique is per occurrence (WHERE-INLINING-SPEC §9.6), so keying a click by Unique alone
 * answered one copy and left its twin unknown.
 *
 * The fixture is the shape this branch's jl4-lsp sends for `may lend jointly` in
 * `ts-shared/ladder-svg/standalone/examples/joint-loan.l4` with no expansions asked for
 * (captured 2026-10-06): labels, Uniques and the shared atomId are as captured, and
 * `` `is creditworthy` OF a `` is drawn twice, as Uniques 157 and 166 with one atomId.
 */
describe('LadderModel — a click binds every copy of the proposition (atomId)', () => {
  const call = (
    id: number,
    unique: number,
    label: string,
    atomId: string
  ): IRExpr => ({
    $type: 'UBoolVar',
    id: iid(id),
    name: nm(label, unique),
    value: 'UnknownV',
    canInline: true,
    atomId,
  })
  const or = (id: number, args: IRExpr[]): IRExpr => ({
    $type: 'Or',
    id: iid(id),
    args,
  })
  const A1 = 156
  const B = 158
  const COLL_A = 161
  const A2 = 165
  const jointFn: VizFunDecl = {
    $type: 'FunDecl',
    id: iid(150),
    name: nm('`may lend jointly`', 150),
    params: [],
    body: and(155, [
      call(A1, 157, '`is creditworthy` OF a', 'd1b523f8'),
      call(B, 159, '`is creditworthy` OF b', '5674d857'),
      or(160, [
        call(COLL_A, 162, "a's `has collateral`", '627b865d'),
        call(163, 164, "b's `has collateral`", '7928a2c2'),
        call(A2, 166, '`is creditworthy` OF a', 'd1b523f8'),
      ]),
    ]),
  }
  const mkJoint = () => new LadderModel(jointFn, deps)

  it('the fixture has the shape: two copies, two Uniques, one atomId', () => {
    const d = mkJoint().decoded
    expect(d.uniqueByNode.get(A1)).not.toBe(d.uniqueByNode.get(A2))
    expect([...(d.nodesByAtomId.get('d1b523f8') ?? [])].sort()).toEqual([
      A1,
      A2,
    ])
  })

  it('setValue on one copy answers its twin, and nothing else', async () => {
    const m = mkJoint()
    expect(m.setValue(A2, 'TrueV')).toBe(true)
    await m.recompute()
    const v = m.valuation
    expect(v.get(A1)).toBe('TrueV')
    expect(v.get(A2)).toBe('TrueV')
    expect(v.get(B)).toBe('UnknownV')
    expect(v.get(COLL_A)).toBe('UnknownV')
  })

  it('cycleValue advances every copy together, from the clicked copy’s value', async () => {
    const m = mkJoint()
    m.cycleValue(A1) // U -> T
    m.cycleValue(A1) // T -> F
    await m.recompute()
    expect(m.valuation.get(A1)).toBe('FalseV')
    expect(m.valuation.get(A2)).toBe('FalseV')
    // b's call is its own proposition
    m.cycleValue(B)
    await m.recompute()
    expect(m.valuation.get(B)).toBe('TrueV')
    expect(m.valuation.get(A1)).toBe('FalseV')
  })

  it('answering both copies settles the decision the way one answer should', async () => {
    // a TRUE, b TRUE: the AND needs the OR, which a's second copy now carries.
    const m = mkJoint()
    m.setValue(A1, 'TrueV')
    m.setValue(B, 'TrueV')
    await m.recompute()
    expect(m.valuation.get(155)).toBe('TrueV')
    expect(m.verdict).toBe('Holds')
  })
})

/**
 * The spread above is safe only while an atomId names ONE proposition. Two mixfix
 * operators sharing a head keyword used to print alike, so `gift stands` in
 * `jl4/tests-cli/fixtures/batch-mixfix-shared-head.l4` arrived with both calls labelled
 * `` `the will` OF w, 3 `` under one atomId, and one click answered both: `X AND NOT Y`
 * could never come out TRUE. jl4-lsp now prints a mixfix call's full surface form
 * (`Ladder.stampMixfixCalls`), so the two calls carry different labels and atomIds.
 *
 * The fixture is that file as this branch's jl4-lsp sends it with no expansions asked for
 * (captured 2026-10-06): ids, labels, Uniques and atomIds are as captured.
 */
describe('LadderModel — two mixfix calls sharing a head keyword stay two propositions', () => {
  const call = (
    id: number,
    unique: number,
    label: string,
    atomId: string
  ): IRExpr => ({
    $type: 'UBoolVar',
    id: iid(id),
    name: nm(label, unique),
    value: 'UnknownV',
    canInline: true,
    atomId,
  })
  const EXECUTED = 160
  const REVOKED = 163
  const giftFn: VizFunDecl = {
    $type: 'FunDecl',
    id: iid(158),
    name: nm('`gift stands`', 6),
    params: [nm('w', 7)],
    body: and(159, [
      call(
        EXECUTED,
        161,
        '`the will` w `is duly executed without` 3',
        '7b1e49f8-126c-50d2-add8-289a83454b9b'
      ),
      {
        $type: 'Not',
        id: iid(162),
        negand: call(
          REVOKED,
          164,
          '`the will` w `is revoked counting` 3',
          'c383101c-aed0-5da6-893a-bea009a02dd1'
        ),
      },
    ]),
  }

  it('answering one call leaves the other alone, so the gift can stand', async () => {
    const m = new LadderModel(giftFn, deps)
    m.setValue(EXECUTED, 'TrueV')
    await m.recompute()
    expect(m.valuation.get(REVOKED)).toBe('UnknownV')
    m.setValue(REVOKED, 'FalseV')
    await m.recompute()
    expect(m.valuation.get(EXECUTED)).toBe('TrueV')
    expect(m.valuation.get(159)).toBe('TrueV')
    expect(m.verdict).toBe('Holds')
  })
})
