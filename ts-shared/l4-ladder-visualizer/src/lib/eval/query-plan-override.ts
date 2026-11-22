import type { QueryPlanDecline, QueryPlanResponse } from 'jl4-client-rpc'
import type { LirContext } from '@repo/layout-ir'
import type { Unique } from '@repo/viz-expr'
import type { ElicitationAsk, PartialEvalAnalysis } from './partial-eval.js'
import { UnknownVal } from './type.js'

type AtomLike = {
  atomId: string
  label: string
}

type LadderGraphAtomLookup = {
  getUniquesForAtomId(context: LirContext, atomId: string): Unique[]
  getUniquesForLabel(context: LirContext, label: string): Unique[]
}

export type ElicitationOverride = {
  ranked: Unique[]
  stillNeeded: Unique[]
  next: Unique[]
  askByUnique: PartialEvalAnalysis['askByUnique']
  /** The sentence that says why there is no plan, for a rule that may refuse. */
  declined?: string
}

/**
 * The analysis the ladder shows once the query planner has answered: the
 * planner's ranking and the inputs it still needs, in place of the ladder's
 * own. For a rule the planner declines, because it may refuse to answer, no
 * input is classed as moot either, the ladder gives no answer and no
 * simplified rule, and the sentence that says why is carried.
 */
export function withElicitationOverride(
  analysis: PartialEvalAnalysis,
  override: {
    ranked: Unique[]
    stillNeeded: Unique[]
    next?: Unique[]
    askByUnique?: PartialEvalAnalysis['askByUnique']
    declined?: string
  } | null
): PartialEvalAnalysis {
  if (!override) return analysis
  const declined = override.declined
  const shown = {
    ...analysis,
    next: override.next ?? analysis.next,
    ranked: override.ranked,
    stillNeeded: override.stillNeeded,
    askByUnique: override.askByUnique ?? analysis.askByUnique,
    declined,
  }
  if (declined === undefined) return shown
  return {
    ...shown,
    dontCare: [],
    irrelevantRootIds: new Set(),
    overallResult: new UnknownVal(),
    isDetermined: false,
    restrictedExprText: '',
  }
}

function uniquesForAtom(
  context: LirContext,
  ladderGraph: LadderGraphAtomLookup,
  atom: AtomLike
): Unique[] {
  const byAtomId = ladderGraph.getUniquesForAtomId(context, atom.atomId)
  return byAtomId.length > 0
    ? byAtomId
    : ladderGraph.getUniquesForLabel(context, atom.label)
}

function uniquesForAtoms(
  context: LirContext,
  ladderGraph: LadderGraphAtomLookup,
  atoms: AtomLike[]
): Unique[] {
  const out: Unique[] = []
  const seen = new Set<Unique>()
  for (const atom of atoms) {
    for (const u of uniquesForAtom(context, ladderGraph, atom)) {
      if (seen.has(u)) continue
      seen.add(u)
      out.push(u)
    }
  }
  return out
}

export function elicitationOverrideFromQueryPlan(
  context: LirContext,
  ladderGraph: LadderGraphAtomLookup,
  resp: QueryPlanResponse | QueryPlanDecline
): ElicitationOverride {
  // A rule that may refuse gets no plan: nothing is asked for, nothing is
  // ranked, and the sentence that says why is carried instead.
  if ('kind' in resp) {
    return {
      ranked: [],
      stillNeeded: [],
      next: [],
      askByUnique: new Map(),
      declined: resp.error,
    }
  }

  const askByUnique = new Map<Unique, ElicitationAsk[]>()
  const seenAskByUnique = new Map<Unique, Set<string>>()

  for (const ask of resp.asks) {
    for (const atom of ask.atoms) {
      for (const u of uniquesForAtom(context, ladderGraph, atom)) {
        const seen = seenAskByUnique.get(u) ?? new Set<string>()
        seenAskByUnique.set(u, seen)
        if (seen.has(ask.label)) continue
        seen.add(ask.label)

        const entry = askByUnique.get(u) ?? []
        askByUnique.set(u, entry)
        entry.push({
          container: ask.container,
          path: ask.path,
          label: ask.label,
          schemaSummary: null,
        })
      }
    }
  }

  const rankedAtoms =
    resp.asks.length > 0 ? resp.asks.flatMap((a) => a.atoms) : resp.ranked

  return {
    ranked: uniquesForAtoms(context, ladderGraph, rankedAtoms),
    stillNeeded: uniquesForAtoms(context, ladderGraph, resp.stillNeeded),
    next:
      resp.asks.length > 0
        ? uniquesForAtoms(context, ladderGraph, resp.asks[0]!.atoms)
        : [],
    askByUnique,
  }
}
