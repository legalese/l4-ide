// The single L4 / jl4-service coupling point, plus the catalogue of decision
// surfaces the Reg CF façade exports.
//
// NOTE: the CSP connect-src in svelte.config.js must include the SAME origin as
// SERVICE_BASE_URL, or the browser blocks the fetch (a <meta>-tag CSP rejects a
// cross-origin fetch with only a console error — the spinner hangs).

export const SERVICE_BASE_URL =
  import.meta.env.VITE_JL4_BASE_URL ?? 'http://127.0.0.1:18099'
export const DEPLOYMENT_ID = import.meta.env.VITE_JL4_DEPLOYMENT ?? 'regcf'

/** How an answer is presented. One per `@export` return shape. */
export type SurfaceKind =
  | 'raise'
  | 'investmentLimit'
  | 'resale'
  | 'reportingExit'
  | 'elicit'

export interface Surface {
  /** The `@export`ed L4 name, verbatim — the URL segment (encoded at use). */
  readonly fn: string
  readonly kind: SurfaceKind
  /** Short label for the picker. */
  readonly title: string
  /** One line of why you would open it. */
  readonly blurb: string
  /** Who is asking. Reg CF has two audiences and they want opposite things. */
  readonly audience: 'founder' | 'investor'
}

/**
 * The six exports of `regcf-wizard.l4`, five of which get a surface here.
 *
 * `investment limit under the rules effective on` is deliberately NOT a surface
 * of its own: it is the law-time control BEHIND the investor surface, which is
 * what makes ruling R8 (fact date asked, rule date disclosed, override allowed)
 * expressible as one screen rather than two. See `components/answers/`.
 */
export const SURFACES: readonly Surface[] = [
  {
    fn: 'can this company raise',
    kind: 'elicit',
    title: 'Can this company raise? — step by step',
    blurb:
      'The eligibility question asked one limb at a time, with the ladder drawn as you answer. Stops as soon as the answer is settled.',
    audience: 'founder',
  },
  {
    fn: 'raise check',
    kind: 'raise',
    title: 'Full raise check',
    blurb:
      'Nine questions about your company and your target. Returns the headroom, the financial statements you owe, and everything you must still line up.',
    audience: 'founder',
  },
  {
    fn: 'investment limit check',
    kind: 'investmentLimit',
    title: 'How much may I invest?',
    blurb:
      'Your Rule 100(a)(2) 12-month limit, worked out in full — and the same question re-asked under the rules in force on the day you invested.',
    audience: 'investor',
  },
  {
    fn: 'resale check',
    kind: 'resale',
    title: 'May I sell these securities yet?',
    blurb:
      'The one-year Rule 501 restriction and its four exceptions, with the days left on the clock.',
    audience: 'investor',
  },
  {
    fn: 'reporting exit check',
    kind: 'reportingExit',
    title: 'May we stop filing annual reports?',
    blurb:
      'The five Rule 202(b) conditions, which of them you meet, and what you owe until one does.',
    audience: 'founder',
  },
]

/** The law-time control export. Not a surface; the investor surface calls it. */
export const LAW_TIME_FN = 'investment limit under the rules effective on'

/**
 * The one surface with a ladder. Measured, not assumed: `GET …/ladder` answers
 * 200 for `can this company raise` and 400 ("Can only visualize, as a ladder
 * diagram, a DECIDE that returns a boolean") for the other five.
 */
export const LADDER_FN = 'can this company raise'

function fnBase(fn: string): string {
  return `${SERVICE_BASE_URL}/deployments/${DEPLOYMENT_ID}/functions/${encodeURIComponent(fn)}`
}

export const schemaUrl = (fn: string): string => fnBase(fn)
export const evalUrl = (fn: string): string => `${fnBase(fn)}/evaluation`
export const queryPlanUrl = (fn: string): string => `${fnBase(fn)}/query-plan`
export const ladderUrl = (fn: string): string => `${fnBase(fn)}/ladder`
