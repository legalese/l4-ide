import { describe, expect, it } from 'vitest'
import { compileDecisionQuery } from '../decision-query.js'
import { typicallyBridge } from '@repo/viz-expr'
import type { IRExpr } from '@repo/viz-expr'

function uboolVar(
  id: number,
  unique: number,
  label: string,
  typically?: boolean
): IRExpr {
  return {
    $type: 'UBoolVar',
    id: { id },
    name: { unique, label },
    value: 'UnknownV',
    canInline: false,
    atomId: `atom-${unique}`,
    ...(typically === undefined ? {} : { typically }),
  }
}

function and(id: number, args: IRExpr[]): IRExpr {
  return { $type: 'And', id: { id }, args }
}

function or(id: number, args: IRExpr[]): IRExpr {
  return { $type: 'Or', id: { id }, args }
}

function not(id: number, negand: IRExpr): IRExpr {
  return { $type: 'Not', id: { id }, negand }
}

describe('compileDecisionQuery', () => {
  it('computes support via reduction: x ∨ (x ∧ y) has support {x}', () => {
    const x = uboolVar(1, 1, 'x')
    const y = uboolVar(2, 2, 'y')
    const expr = or(3, [x, and(4, [x, y])])

    const compiled = compileDecisionQuery(expr, [1, 2])
    const res = compiled.query(new Map())

    expect(res.determined).toBeNull()
    expect(res.support).toEqual([1])
    expect(res.ranked).toEqual([1])
  })

  it('(x ∨ y) ranks earlier vars first when equal impact', () => {
    const x = uboolVar(1, 1, 'x')
    const y = uboolVar(2, 2, 'y')
    const expr = or(3, [x, y])

    const compiled = compileDecisionQuery(expr, [1, 2])
    const res = compiled.query(new Map())

    expect(res.support).toEqual([1, 2])
    expect(res.ranked).toEqual([1, 2])
    expect(res.impact.get(1)?.ifTrue.determined).toBe(true)
    expect(res.impact.get(1)?.ifFalse.determined).toBeNull()
  })

  it('restriction can determine result and empty support', () => {
    const x = uboolVar(1, 1, 'x')
    const y = uboolVar(2, 2, 'y')
    const expr = or(3, [x, y])

    const compiled = compileDecisionQuery(expr, [1, 2])
    const res = compiled.query(new Map([[1, true]]))

    expect(res.determined).toBe(true)
    expect(res.support).toEqual([])
    expect(res.ranked).toEqual([])
  })
})

describe('information-gain ordering', () => {
  it('prefers the most informative question even when it is last in var order', () => {
    // f = (p ∧ (q ∨ r ∨ s)) ∨ (¬p ∧ (q ∧ r ∧ s))
    // p splits the outcome hard (0.875 vs 0.125); q/r/s barely move it. No
    // single answer determines the result, so the OLD determinableCount
    // heuristic ties every variable at 0 and falls back to variable order.
    const p = uboolVar(1, 1, 'p')
    const q = uboolVar(2, 2, 'q')
    const r = uboolVar(3, 3, 'r')
    const s = uboolVar(4, 4, 's')
    const expr = or(10, [
      and(11, [p, or(12, [q, r, s])]),
      and(13, [not(14, p), and(15, [q, r, s])]),
    ])

    // Put p LAST in the variable order: a var-order tiebreak would rank it last.
    const compiled = compileDecisionQuery(expr, [2, 3, 4, 1])
    const res = compiled.query(new Map())

    // Old heuristic sees no determining answer for p (both branches undetermined).
    expect(res.impact.get(1)?.ifTrue.determined).toBeNull()
    expect(res.impact.get(1)?.ifFalse.determined).toBeNull()

    // Info-gain ranking surfaces the informative variable first regardless.
    expect(res.ranked[0]).toBe(1)
    expect(res.scores.get(1)!).toBeGreaterThan(res.scores.get(2)!)
  })

  it('a strong prior demotes a near-certain question', () => {
    // f = a ∧ b. If a is almost always true, asking b is far more informative.
    const a = uboolVar(1, 1, 'a')
    const b = uboolVar(2, 2, 'b')
    const expr = and(3, [a, b])
    const weights = new Map<number, number>([[1, 0.98]]) // atom a (unique 1)

    const compiled = compileDecisionQuery(expr, [1, 2], weights)
    const res = compiled.query(new Map())

    expect(res.ranked[0]).toBe(2) // ask b first; a is nearly certain
    expect(res.scores.get(2)!).toBeGreaterThan(res.scores.get(1)!)
  })
})

describe('typicallyBridge extraction', () => {
  it('maps boolean TYPICALLY to soft weights + default provenance; leaves others alone', () => {
    const t = uboolVar(1, 1, 'presumed true', true)
    const f = uboolVar(2, 2, 'presumed false', false)
    const plain = uboolVar(3, 3, 'no default') // no typically
    const expr = and(10, [t, or(11, [f, plain])])

    const { weights, provenance } = typicallyBridge(expr)

    // weights only for boolean-typically atoms
    expect(weights.get(1)).toBe(0.9)
    expect(weights.get(2)).toBe(0.1)
    expect(weights.has(3)).toBe(false)

    // provenance 'default' (keyed by node id) only for presumed atoms; the
    // plain atom is implicitly 'given' (absent)
    expect(provenance.get(1)).toBe('default')
    expect(provenance.get(2)).toBe('default')
    expect(provenance.has(3)).toBe(false)
  })
})

describe('TYPICALLY priors — cross-runtime parity fixture', () => {
  // The SAME structure, var order, priors and expected scores are asserted in
  // the Haskell suite (jl4-service/test/BooleanDecisionQuerySpec.hs,
  // "TYPICALLY priors — cross-runtime parity fixture"). If the two hand-rolled
  // ROBDDs ever drift, one of these tests breaks (question-ordering spec §7).
  //
  // `may purchase alcohol` IF capacity AND (ofage OR parental OR spousal)
  const capacity = uboolVar(1, 1, 'person has capacity', true)
  const ofage = uboolVar(2, 2, 'of age', true)
  const parental = uboolVar(3, 3, 'has parental approval', false)
  const spousal = uboolVar(4, 4, 'has spousal approval', false)
  const expr = and(10, [capacity, or(11, [ofage, parental, spousal])])
  const order = [1, 2, 3, 4]
  const approx = (expected: number) => (actual: number | undefined) =>
    actual !== undefined && Math.abs(actual - expected) < 1e-3

  it('prior-free: OR siblings tie, capacity leads', () => {
    const res = compileDecisionQuery(expr, order).query(new Map())
    expect(res.ranked).toEqual([1, 2, 3, 4])
    expect(res.scores.get(1)).toSatisfy(approx(0.7169))
    expect(res.scores.get(2)).toSatisfy(approx(0.0115))
    expect(res.scores.get(3)).toSatisfy(approx(0.0115))
    expect(res.scores.get(4)).toSatisfy(approx(0.0115))
  })

  it('v2 priors from typicallyBridge: presumed-FALSE OR atoms sink to the end', () => {
    // The weights come from the shared bridge reading each UBoolVar.typically,
    // NOT a hand-built map — this exercises the real extraction path.
    const { weights } = typicallyBridge(expr)
    expect(weights.get(1)).toBe(0.9) // capacity TYPICALLY TRUE
    expect(weights.get(2)).toBe(0.9) // of age TYPICALLY TRUE
    expect(weights.get(3)).toBe(0.1) // parental TYPICALLY FALSE
    expect(weights.get(4)).toBe(0.1) // spousal TYPICALLY FALSE

    const res = compileDecisionQuery(expr, order, weights).query(new Map())
    expect(res.ranked).toEqual([1, 2, 3, 4])
    expect(res.scores.get(1)).toSatisfy(approx(0.2992))
    expect(res.scores.get(2)).toSatisfy(approx(0.1762))
    expect(res.scores.get(3)).toSatisfy(approx(0.0034))
    expect(res.scores.get(4)).toSatisfy(approx(0.0034))
    // the informative OR atom outranks its presumed-FALSE siblings
    expect(res.scores.get(2)!).toBeGreaterThan(res.scores.get(3)!)
  })
})

// The seam, in the planner (DESIGN §25.3, §25.7). The verdict table here is the SAME
// table `lampsFor` implements in ladder-core, and the same one asserted in
// BooleanDecisionQuerySpec.hs — deliberately, because a wizard and a diagram that
// disagreed about a case would be lying to the same user.
describe('Implies — verdict, not truth value', () => {
  const SCOPE = 1
  const REQ = 2
  const implies = (): IRExpr => ({
    $type: 'Implies',
    id: { id: 3 },
    scope: uboolVar(1, SCOPE, 'covered'),
    requirement: uboolVar(2, REQ, 'requirement met'),
    seam: 'IMPLIES',
  })
  const run = (bindings: [number, boolean][]) =>
    compileDecisionQuery(implies(), [SCOPE, REQ]).query(new Map(bindings))

  it('vacuous: the function is TRUE and the verdict is NotApplicable', () => {
    const res = run([[SCOPE, false]])
    // Both hold at once, and that is the entire problem in two lines: a caller reading
    // `determined` sees the same TRUE it sees for a compliant case.
    expect(res.determined).toBe(true)
    expect(res.verdict).toBe('NotApplicable')
    expect(res.support).toEqual([])
  })

  it('complies', () => {
    const res = run([
      [SCOPE, true],
      [REQ, true],
    ])
    expect(res.determined).toBe(true)
    expect(res.verdict).toBe('Complies')
  })

  it('in breach', () => {
    const res = run([
      [SCOPE, true],
      [REQ, false],
    ])
    expect(res.determined).toBe(false)
    expect(res.verdict).toBe('InBreach')
  })

  it('an unasked requirement is not a breach', () => {
    const res = run([[SCOPE, true]])
    expect(res.verdict).toBe('Undetermined')
    expect(res.support).toEqual([REQ])
  })

  it('requirement met, scope unknown: the value short-circuits and the VERDICT does not', () => {
    // The classical planner stops here: `NOT scope OR req` restricts to TRUE, support is
    // empty, nothing left to ask. But we still do not know whether the rule reached this
    // case — and N/A and compliance are different answers. So the interview goes on, and
    // it goes on about the SCOPE.
    const res = run([[REQ, true]])
    expect(res.determined).toBe(true)
    expect(res.verdict).toBe('Undetermined')
    expect(res.support).toEqual([SCOPE])
  })

  it('no seam, no vacuity: the same boolean function reports Holds', () => {
    // Truth-functionally identical to `implies()` — same BDD, same `determined` for
    // every binding. Only the SHAPE differs, and only the shape can say what the TRUE
    // means. This is `expandImplies`, and this test is what it costs.
    const flattened = or(3, [
      not(4, uboolVar(1, SCOPE, 'covered')),
      uboolVar(2, REQ, 'requirement met'),
    ])
    const res = compileDecisionQuery(flattened, [SCOPE, REQ]).query(
      new Map([[SCOPE, false]])
    )
    expect(res.determined).toBe(true)
    expect(res.verdict).toBe('Holds')
    expect(res.support).toEqual([])
  })

  it('impact previews carry verdicts too, so a preview cannot lie either', () => {
    const res = run([])
    const scopeImpact = res.impact.get(SCOPE)
    expect(scopeImpact?.ifFalse.verdict).toBe('NotApplicable')
    expect(scopeImpact?.ifFalse.determined).toBe(true)
    expect(scopeImpact?.ifTrue.verdict).toBe('Undetermined')
  })

  it('the scope is asked before the requirement: information about the verdict, not the value', () => {
    // Falls out of the verdict-entropy measure rather than a hand-tuned rule: a
    // requirement you may never be measured against carries less information about the
    // verdict than the scope that decides whether you are measured at all.
    const res = run([])
    expect(res.ranked[0]).toBe(SCOPE)
    expect(res.scores.get(SCOPE)!).toBeGreaterThan(res.scores.get(REQ)!)
  })
})
