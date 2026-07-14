import type { IRExpr, Unique } from '@repo/viz-expr'
import { match } from 'ts-pattern'
import { ROBDD } from './robdd.js'

export type Determined = boolean | null

/**
 * What a wizard may TELL a user — as opposed to what the function evaluates to.
 *
 * The two are not the same thing, and that is the whole point. `determined` is the
 * function's truth value and stays exactly that; for a seam it CANNOT be turned into a
 * verdict, because a vacuous case and a compliant one both make `NOT scope OR
 * requirement` TRUE. Reporting that TRUE as "complies" is the N/A-vs-complies category
 * error the ladder fixes with two lamps (DESIGN §25.3) — and this type is those two
 * lamps, in the wizard.
 *
 * Mirror of `Verdict` in `BooleanDecisionQuery.hs`.
 */
export type Verdict =
  /** Not settled. There are still questions worth asking. */
  | 'Undetermined'
  /** No seam: the function is TRUE. */
  | 'Holds'
  /** No seam: the function is FALSE. */
  | 'Fails'
  /** The rule reached this case, and the requirement is met. */
  | 'Complies'
  /** The rule reached this case, and the requirement is not met. */
  | 'InBreach'
  /**
   * The rule never reached this case. Note the function is TRUE here, and saying so
   * ("yes, you're fine") is not the same as saying you complied: you were never asked
   * to. Vacuity is a STATE, not a way of passing.
   */
  | 'NotApplicable'

export interface QueryOutcome {
  /** The FUNCTION's truth value. Correct, and not a verdict — see {@link Verdict}. */
  determined: Determined
  /**
   * What may be shown to a user. Switch on THIS, not on `determined`: for a seam,
   * `Complies` and `NotApplicable` are both `determined === true`.
   */
  verdict: Verdict
  support: Unique[]
}

export interface VarImpact {
  ifTrue: QueryOutcome
  ifFalse: QueryOutcome
}

export interface DecisionQueryResult {
  /** The FUNCTION's truth value. Correct, and not a verdict — see {@link Verdict}. */
  determined: Determined
  /** What may be shown to a user. */
  verdict: Verdict
  /**
   * Atoms still worth asking about — computed against the VERDICT, so this can be
   * non-empty even when `determined` is already settled.
   */
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

/**
 * The roots the planner tracks: the function, and — when the body is a seam — its two
 * sides, `[scope, requirement]`, as roots in the same diagram.
 */
interface Roots {
  fn: number
  seam: [number, number] | null
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
        // Truth-functionally exact, and shape-destroying. To settle whether the rule
        // HOLDS, `NOT scope OR requirement` is exactly the proposition — so this is
        // right, as far as it goes. What it cannot do is say WHY it holds: a case the
        // rule never reached and a case that complies both make it TRUE. That is why
        // `roots` keeps the two sides whole alongside this (DESIGN §25.3).
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

  // The roots the planner tracks: the function itself, and — when the body IS a seam —
  // its two sides, compiled into the SAME diagram so they share variable indices and
  // hash-consing. Restricting all three under one set of bindings is what lets us
  // report a verdict instead of a bare truth value.
  //
  // Only a TOP-LEVEL seam has a verdict to report: it is the rule's own
  // scope/requirement split. A seam buried inside an `And` is just a subterm — and the
  // ladder's translator never emits one anyway, since it peels exactly the outermost
  // implication (DESIGN §25a).
  const roots: Roots = {
    fn: compile(expr),
    seam:
      expr.$type === 'Implies'
        ? [compile(expr.scope), compile(expr.requirement)]
        : null,
  }

  const restrictRoots = (
    rs: Roots,
    bindings: ReadonlyMap<number, boolean>
  ): Roots => ({
    fn: bdd.restrict(rs.fn, bindings),
    seam: rs.seam
      ? [bdd.restrict(rs.seam[0], bindings), bdd.restrict(rs.seam[1], bindings)]
      : null,
  })

  /**
   * Read the verdict off the seam's two sides — the same two lamps `lampsFor` lights in
   * `ladder-core`, and deliberately so: if the wizard and the picture disagreed about a
   * case, one of them would be lying to the same user.
   */
  const verdictOf = (rs: Roots): Verdict => {
    if (!rs.seam) {
      const d = isDeterminedId(rs.fn)
      return d === true ? 'Holds' : d === false ? 'Fails' : 'Undetermined'
    }
    const scope = isDeterminedId(rs.seam[0])
    if (scope === false) return 'NotApplicable'
    // An UNKNOWN scope is undetermined even when the requirement is already met and the
    // function is therefore settled TRUE. We would not know WHICH true it is, and "the
    // rule does not reach you" and "you comply" go on different pieces of paper.
    if (scope === null) return 'Undetermined'
    const req = isDeterminedId(rs.seam[1])
    return req === true
      ? 'Complies'
      : req === false
        ? 'InBreach'
        : 'Undetermined'
  }

  /**
   * The atoms still worth asking about.
   *
   * This is where the seam changes the planner's behaviour, and it is the sharp edge of
   * the whole fix. The classical short-circuit — requirement TRUE, so the function is
   * TRUE, so stop — is valid only if you are computing a truth VALUE. If you are
   * computing a VERDICT it is wrong: a met requirement does not tell you whether the
   * rule bit, and the scope still does. So we take the support of the SIDES, not of the
   * function, and the interview continues until the verdict itself is settled.
   *
   * It costs questions. That is the trade, made deliberately: a shorter interview that
   * ends in the wrong word is not a bargain.
   */
  const supportIdxOf = (rs: Roots): number[] => {
    if (!rs.seam) return Array.from(bdd.support(rs.fn))
    const [scopeRoot, reqRoot] = rs.seam
    const scopeSupport = Array.from(bdd.support(scopeRoot))
    // N/A is settled. A requirement you will never be measured against is not worth a
    // question, so the interview stops rather than asking after a rule already
    // established not to reach you.
    if (isDeterminedId(scopeRoot) === false) return scopeSupport
    return [...scopeSupport, ...bdd.support(reqRoot)]
  }

  const supportOf = (rs: Roots): Unique[] =>
    uniqSorted(
      supportIdxOf(rs)
        .map((i) => varOrder[i])
        .filter((u): u is Unique => u !== undefined)
    )

  /**
   * Uncertainty about the VERDICT, in bits.
   *
   * With no seam this is just the binary entropy of the function, exactly as before.
   * With a seam, the requirement's uncertainty counts only to the extent the scope
   * actually bites — a requirement you will never be asked about carries no information
   * about the verdict — which is what puts scope questions ahead of requirement
   * questions without anyone having to hand-tune a heuristic to say so.
   */
  const uncertainty = (rs: Roots): number => {
    if (!rs.seam) return binaryEntropy(bdd.prob(rs.fn, weightByIndex))
    const pScope = bdd.prob(rs.seam[0], weightByIndex)
    return (
      binaryEntropy(pScope) +
      pScope * binaryEntropy(bdd.prob(rs.seam[1], weightByIndex))
    )
  }

  const outcomeOf = (rs: Roots): QueryOutcome => ({
    determined: isDeterminedId(rs.fn),
    verdict: verdictOf(rs),
    support: supportOf(rs),
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

      const restricted = restrictRoots(roots, idxBindings)
      const support = supportOf(restricted)
      const determined = isDeterminedId(restricted.fn)

      // Current uncertainty about the VERDICT, in bits.
      const priorEntropy = uncertainty(restricted)

      const impact = new Map<Unique, VarImpact>()
      const scores = new Map<Unique, number>()
      for (const u of support) {
        const idx = uniqueToVarIndex.get(u)
        if (idx === undefined) continue
        const withTrue = restrictRoots(restricted, new Map([[idx, true]]))
        const withFalse = restrictRoots(restricted, new Map([[idx, false]]))
        impact.set(u, {
          ifTrue: outcomeOf(withTrue),
          ifFalse: outcomeOf(withFalse),
        })

        // Expected posterior entropy after asking this variable, weighted by
        // how likely each answer is; info gain = prior − expected posterior.
        const w = weightByIndex.get(idx) ?? 0.5
        const expectedPosterior =
          w * uncertainty(withTrue) + (1 - w) * uncertainty(withFalse)
        scores.set(u, priorEntropy - expectedPosterior)
      }

      return {
        determined,
        verdict: verdictOf(restricted),
        support,
        ranked: rank(support, scores),
        impact,
        scores,
        stats: { nodes: bdd.nodeCount(), support: support.length },
      }
    },
  }
}
