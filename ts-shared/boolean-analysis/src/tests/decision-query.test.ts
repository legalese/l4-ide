import { describe, expect, it } from 'vitest'
import { compileDecisionQuery } from '../decision-query.js'
import type { IRExpr } from '@repo/viz-expr'

function uboolVar(id: number, unique: number, label: string): IRExpr {
  return {
    $type: 'UBoolVar',
    id: { id },
    name: { unique, label },
    value: 'UnknownV',
    canInline: false,
    atomId: `atom-${unique}`,
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
