import type { IRExpr, Unique } from '@repo/viz-expr'
import { match } from 'ts-pattern'
import { ROBDD } from './robdd.js'

export type Determined = boolean | null

export interface QueryOutcome {
  determined: Determined
  support: Unique[]
}

export interface VarImpact {
  ifTrue: QueryOutcome
  ifFalse: QueryOutcome
}

export interface DecisionQueryResult {
  determined: Determined
  support: Unique[]
  ranked: Unique[]
  impact: Map<Unique, VarImpact>
  /** Information gain (bits) per support variable; higher = ask sooner. */
  scores: Map<Unique, number>
  stats: { nodes: number; support: number }
}

export interface CompiledDecisionQuery {
  /** Order used for BDD variable indices */
  readonly varOrder: Unique[]
  /** Query with known bindings. Absent vars are treated as unknown. */
  query(bindings: ReadonlyMap<Unique, boolean>): DecisionQueryResult
}

function collectVarOrder(expr: IRExpr): Unique[] {
  const seen = new Set<Unique>()
  const out: Unique[] = []
  const go = (e: IRExpr) => {
    match(e)
      .with({ $type: 'UBoolVar' }, (v) => {
        if (!seen.has(v.name.unique)) {
          seen.add(v.name.unique)
          out.push(v.name.unique)
        }
      })
      .with({ $type: 'Not' }, (n) => go(n.negand))
      // Scope before requirement — the source's own order, which is the initial
      // variable order the ROBDD is built in. It is also the sane one to ask in:
      // settle whether the rule bites you before asking what it demands.
      .with({ $type: 'Implies' }, (i) => {
        go(i.scope)
        go(i.requirement)
      })
      .with({ $type: 'And' }, (a) => a.args.forEach(go))
      .with({ $type: 'Or' }, (o) => o.args.forEach(go))
      .with({ $type: 'App' }, () => {
        throw new Error(
          'Cannot compile decision query: App nodes not supported'
        )
      })
      .otherwise(() => {})
  }
  go(expr)
  return out
}

function isDeterminedId(id: number): Determined {
  if (id === ROBDD.TRUE) return true
  if (id === ROBDD.FALSE) return false
  return null
}

function uniqSorted(nums: Iterable<number>): number[] {
  return Array.from(new Set(nums)).sort((a, b) => a - b)
}

/** Binary entropy in bits; 0 at the deterministic ends. */
function binaryEntropy(p: number): number {
  if (p <= 0 || p >= 1) return 0
  return -p * Math.log2(p) - (1 - p) * Math.log2(1 - p)
}

export function compileDecisionQuery(
  expr: IRExpr,
  varOrder: Unique[] = collectVarOrder(expr),
  weights?: ReadonlyMap<Unique, number>
): CompiledDecisionQuery {
  const bdd = new ROBDD()
  const uniqueToVarIndex = new Map<Unique, number>()
  varOrder.forEach((u, i) => uniqueToVarIndex.set(u, i))

  // Per-atom priors for the information-gain ordering, keyed by BDD index.
  // Absent weights default to 0.5 (prior-free v1). v2 populates this from
  // TYPICALLY defaults.
  const weightByIndex = new Map<number, number>()
  if (weights) {
    for (const [u, w] of weights.entries()) {
      const idx = uniqueToVarIndex.get(u)
      if (idx !== undefined) weightByIndex.set(idx, w)
    }
  }

  const compile = (e: IRExpr): number => {
    return (
      match(e)
        .with({ $type: 'TrueE' }, () => ROBDD.TRUE)
        .with({ $type: 'FalseE' }, () => ROBDD.FALSE)
        .with({ $type: 'UBoolVar' }, (v) => {
          const idx = uniqueToVarIndex.get(v.name.unique)
          if (idx === undefined) {
            throw new Error(
              `Internal error: missing var index for unique ${v.name.unique}`
            )
          }
          return bdd.var(idx)
        })
        .with({ $type: 'Not' }, (n) => bdd.neg(compile(n.negand)))
        // The planner is a consumer of the FUNCTION, not of the picture, so the
        // classical reading is not merely permitted here but correct: to settle
        // whether the rule holds, `NOT scope OR requirement` is exactly the
        // proposition, and it hands the planner its best short-circuit — show the
        // scope false and there is nothing left to ask.
        //
        // The care needed is downstream: the resulting TRUE must not be reported to a
        // user as "complies", because for a vacuous case it means "the rule never bit
        // you". That is the N/A-vs-complies category error the ladder fixes with two
        // lamps (DESIGN §25.3), and it lives in the wizard's PRESENTATION, not here.
        .with({ $type: 'Implies' }, (i) =>
          bdd.apply('or', bdd.neg(compile(i.scope)), compile(i.requirement))
        )
        .with({ $type: 'And' }, (a) =>
          a.args.reduce(
            (acc, x) => bdd.apply('and', acc, compile(x)),
            ROBDD.TRUE
          )
        )
        .with({ $type: 'Or' }, (o) =>
          o.args.reduce(
            (acc, x) => bdd.apply('or', acc, compile(x)),
            ROBDD.FALSE
          )
        )
        .with({ $type: 'App' }, (app) => {
          throw new Error(
            `Cannot compile decision query: App ${app.fnName.label} not supported`
          )
        })
        .with({ $type: 'InertE' }, (inert) =>
          // Inert elements evaluate to identity for their context: AND→True, OR→False
          inert.context === 'InertAnd' ? ROBDD.TRUE : ROBDD.FALSE
        )
        .exhaustive()
    )
  }

  const root = compile(expr)

  const supportFromRestricted = (restricted: number): Unique[] => {
    const idxs = bdd.support(restricted)
    return uniqSorted(
      Array.from(idxs)
        .map((i) => varOrder[i])
        .filter((u): u is Unique => u !== undefined)
    )
  }

  const outcomeFromRestricted = (restricted: number): QueryOutcome => ({
    determined: isDeterminedId(restricted),
    support: supportFromRestricted(restricted),
  })

  // Rank by information gain about the outcome (higher = ask sooner). This
  // subsumes the old "does answering it settle the result?" heuristic — a
  // variable that determines the outcome yields maximal gain — while also
  // crediting a variable that merely shrinks the remaining possibility space.
  // Ties break by variable order for determinism.
  const rank = (support: Unique[], scores: Map<Unique, number>): Unique[] => {
    return support.slice().sort((a, b) => {
      const sa = scores.get(a) ?? 0
      const sb = scores.get(b) ?? 0
      if (sb !== sa) return sb - sa
      const la = uniqueToVarIndex.get(a) ?? 1_000_000
      const lb = uniqueToVarIndex.get(b) ?? 1_000_000
      return la - lb
    })
  }

  return {
    varOrder,
    query(bindings: ReadonlyMap<Unique, boolean>): DecisionQueryResult {
      const idxBindings = new Map<number, boolean>()
      for (const [u, b] of bindings.entries()) {
        const idx = uniqueToVarIndex.get(u)
        if (idx !== undefined) idxBindings.set(idx, b)
      }

      const restricted = bdd.restrict(root, idxBindings)
      const support = supportFromRestricted(restricted)
      const determined = isDeterminedId(restricted)

      // Current uncertainty about the outcome, in bits.
      const priorEntropy = binaryEntropy(bdd.prob(restricted, weightByIndex))

      const impact = new Map<Unique, VarImpact>()
      const scores = new Map<Unique, number>()
      for (const u of support) {
        const idx = uniqueToVarIndex.get(u)
        if (idx === undefined) continue
        const withTrue = bdd.restrict(restricted, new Map([[idx, true]]))
        const withFalse = bdd.restrict(restricted, new Map([[idx, false]]))
        impact.set(u, {
          ifTrue: outcomeFromRestricted(withTrue),
          ifFalse: outcomeFromRestricted(withFalse),
        })

        // Expected posterior entropy after asking this variable, weighted by
        // how likely each answer is; info gain = prior − expected posterior.
        const w = weightByIndex.get(idx) ?? 0.5
        const expectedPosterior =
          w * binaryEntropy(bdd.prob(withTrue, weightByIndex)) +
          (1 - w) * binaryEntropy(bdd.prob(withFalse, weightByIndex))
        scores.set(u, priorEntropy - expectedPosterior)
      }

      return {
        determined,
        support,
        ranked: rank(support, scores),
        impact,
        scores,
        stats: { nodes: bdd.nodeCount(), support: support.length },
      }
    },
  }
}
