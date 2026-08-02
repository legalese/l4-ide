import type { PlanAtom, QueryPlanResponse, Verdict } from '$lib/api/types'

/**
 * The elicitation loop's POLICY, kept pure so it can be tested without a DOM or
 * a service.
 *
 * The one rule that is not negotiable is `isSettled`. The code comment at
 * `jl4-lsp/.../Backend/DecisionQueryPlan.hs:224-226` says a UI that switches on
 * `determined` "will sooner or later tell someone they complied with a rule that
 * never reached them" — because `determined` is `null` for FOUR of the six
 * verdicts, and a falsy check reads three of them as "keep asking" and one
 * (`Vacuous`) as "no answer" when there is one. So: switch on `verdict`.
 */

/** Verdicts at which the loop stops asking. */
const SETTLED: ReadonlySet<Verdict> = new Set<Verdict>([
  'Holds',
  'Fails',
  'Vacuous',
  'Inconsistent',
  'Tautology',
])

export function isSettled(v: Verdict): boolean {
  return SETTLED.has(v)
}

/** What the citizen is told, per verdict. Never derived from `determined`. */
export function verdictHeadline(v: Verdict): string {
  switch (v) {
    case 'Holds':
      return 'Yes — on what you have told us, this company can raise under Regulation Crowdfunding.'
    case 'Fails':
      return 'No — on what you have told us, this company cannot raise under Regulation Crowdfunding.'
    case 'Tautology':
      return 'Yes, on every reading — the answer does not depend on your remaining answers.'
    case 'Inconsistent':
      return 'These answers contradict each other. No reading of the rules fits them all.'
    case 'Vacuous':
      return 'The rule does not reach this situation, so it neither permits nor forbids it.'
    case 'Undetermined':
      return 'Not settled yet — there is at least one more thing we need to know.'
  }
}

/** The outcome tone for the answer card. `Vacuous`/`Inconsistent` are NEITHER
 *  a yes nor a no, and must not be coloured as one. */
export function verdictTone(v: Verdict): 'yes' | 'no' | 'neither' | 'open' {
  switch (v) {
    case 'Holds':
    case 'Tautology':
      return 'yes'
    case 'Fails':
      return 'no'
    case 'Vacuous':
    case 'Inconsistent':
      return 'neither'
    case 'Undetermined':
      return 'open'
  }
}

/**
 * The next question to put, or `null` when the loop is over.
 *
 * `ranked` is the service's information-gain order and `stillNeeded` is the
 * outstanding set; asking in ranked order restricted to what is still needed is
 * the whole of progressive disclosure. When a binding settles the verdict, the
 * remaining atoms are never asked — which is the observable difference from a
 * form.
 */
export function nextAsk(plan: QueryPlanResponse): PlanAtom | null {
  if (isSettled(plan.verdict)) return null
  const needed = new Set(plan.stillNeeded.map((a) => a.unique))
  return (
    plan.ranked.find((a) => needed.has(a.unique)) ?? plan.stillNeeded[0] ?? null
  )
}

/**
 * Human text for an atom whose label is an L4 projection chain.
 *
 * Live example, verbatim:
 *   "`issuer is eligible` OF (`issuer profile from` OF plan)"  ->  "Issuer is eligible"
 *
 * The head of the chain is the predicate; the tail is the route to the record it
 * is applied to, which carries no information for a reader who has already been
 * told whose company it is. Backticks are L4's quoting of spaced identifiers and
 * are never part of the name.
 */
export function humaniseAtom(label: string): string {
  const head = label.split(/\s+OF\s+/)[0] ?? label
  const bare = head
    .replace(/^\(+|\)+$/g, '')
    .replace(/`/g, '')
    .trim()
  return bare.length ? bare[0].toUpperCase() + bare.slice(1) : label
}

/** How many of the plan's atoms have been answered, for the progress line. */
export function progress(
  plan: QueryPlanResponse,
  bindings: Record<string, boolean>
): { answered: number; total: number } {
  const total = new Set([
    ...plan.ranked.map((a) => a.unique),
    ...plan.stillNeeded.map((a) => a.unique),
    ...Object.keys(bindings).map(Number),
  ]).size
  return { answered: Object.keys(bindings).length, total }
}

/** The binding key for an atom: its `unique` as a decimal string. See
 *  `api/client.ts#queryPlan` for why this is NOT the atomId. */
export function bindKey(atom: PlanAtom): string {
  return String(atom.unique)
}
