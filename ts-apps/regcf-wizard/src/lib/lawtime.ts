/**
 * Ruling R8, made mechanical (CORPUS-TRACK.md §8, "R8 — Does the wizard ask for
 * the rule date, or fix it? — SETTLED: ask a fact date, _disclose_ the derived
 * rule date, and allow an override").
 *
 * Three pieces, and the middle one is the whole point:
 *   1. ask the FACT date — "when did you (or will you) invest?" — the only
 *      question a citizen can answer;
 *   2. DISCLOSE the derived rule date, and say why it is that date;
 *   3. allow an OVERRIDE that pins law-time independently of fact-time, for the
 *      auditor and the drafter of §5.0, whose questions cannot be put as a fact
 *      date at all.
 *
 * This module owns 1-3 as pure functions. It knows NOTHING about which figures
 * changed when: every number on the page comes back from the engine, under the
 * rule date this module computed. A client-side regime table would be a second
 * copy of the law, and the first one to go stale.
 */

/** Where the applied rule date came from. */
export type LawTimeSource = 'fact' | 'override'

export interface AppliedLawTime {
  /** ISO date actually sent to the law-time export. */
  readonly ruleDate: string
  readonly source: LawTimeSource
  /** The disclosure sentence. */
  readonly because: string
}

const ISO = /^\d{4}-\d{2}-\d{2}$/

export function isIso(v: string): boolean {
  if (!ISO.test(v)) return false
  const d = new Date(v + 'T00:00:00Z')
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === v
}

/** Today, in the browser's own calendar day, as ISO. Used only as a default for
 *  the fact-date control — never as a claim about which rules apply. */
export function todayIso(now: Date = new Date()): string {
  const y = now.getFullYear()
  const m = String(now.getMonth() + 1).padStart(2, '0')
  const d = String(now.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

/** "2022-06-01" -> "1 June 2022". Deliberately UTC-anchored so the printed day
 *  is the day the user picked, in every timezone. */
export function formatIso(iso: string): string {
  if (!isIso(iso)) return iso
  const d = new Date(iso + 'T00:00:00Z')
  return new Intl.DateTimeFormat('en-GB', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(d)
}

/**
 * Piece 1 + 2 + 3, resolved.
 *
 * `override` wins when it is a valid ISO date; otherwise law-time tracks
 * fact-time. The returned `because` is the sentence the answer card must show —
 * it is not optional garnish. Ruling R8's rebuttal of review finding F6 turns on
 * it: without the disclosure the page presents ONE slider, which collapses the
 * fact-time/law-time distinction the whole exhibit stakes its argument on.
 */
export function applyLawTime(
  factDate: string,
  override: string | null
): AppliedLawTime {
  if (override && isIso(override)) {
    return {
      ruleDate: override,
      source: 'override',
      because: `Applying the rules in force on ${formatIso(override)}, because you pinned that date — not because of when the investment was made.`,
    }
  }
  return {
    ruleDate: factDate,
    source: 'fact',
    because: `Applying the rules in force on ${formatIso(factDate)}, because that is when the investment was made.`,
  }
}

/**
 * What to say about two numbers computed under two clocks.
 *
 * The client compares; it does not explain. Any explanation of WHY they differ
 * comes from the engine's own prose (`how this is worked out`, `which limb
 * applies`, `caveats`), which carries the citations.
 */
export function lawTimeComparison(
  underRuleDate: number,
  underToday: number | null,
  applied: AppliedLawTime,
  todayLabel: string
): string {
  if (underToday === null) {
    return `Under the rules in force on ${formatIso(applied.ruleDate)}, the 12-month limit is ${money(underRuleDate)}. Today's rules set no limit for you at all, so there is nothing to compare it with.`
  }
  if (underRuleDate === underToday) {
    return `The limit is ${money(underRuleDate)} under the rules in force on ${formatIso(applied.ruleDate)}, and the same under the rules in force on ${todayLabel}. On these figures the amendments since then do not bite.`
  }
  return `The limit is ${money(underRuleDate)} under the rules in force on ${formatIso(applied.ruleDate)}, but ${money(underToday)} under the rules in force on ${todayLabel}. Same question, same figures, two rule dates, two answers.`
}

/** US dollars, no cents — every Reg CF figure in the corpus is a whole dollar. */
export function money(n: number): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0,
  }).format(n)
}
