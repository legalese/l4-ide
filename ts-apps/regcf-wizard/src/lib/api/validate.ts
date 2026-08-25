import type {
  RaiseAssessment,
  InvestmentLimitAnswer,
  ResaleAnswer,
  ReportingExitAnswer,
} from './types'

/**
 * Shape validators for the four record answers.
 *
 * These exist for one reason, and it is not tidiness: the whole point of the
 * façade pattern is that a drafter can edit `regcf-wizard.l4` and redeploy. A
 * renamed or dropped field would otherwise arrive as `undefined`, coerce to
 * `false` at the badge, and tell a founder they are eligible when the engine
 * never said so. Every failure routes to the graceful "we could not read the
 * result" view instead.
 *
 * Pure and dependency-free, so they are unit-testable in plain Node.
 */

export class ShapeError extends Error {}

function isRecord(x: unknown): x is Record<string, unknown> {
  return typeof x === 'object' && x !== null && !Array.isArray(x)
}
function isStringArray(x: unknown): x is string[] {
  return Array.isArray(x) && x.every((e) => typeof e === 'string')
}
/** A MAYBE NUMBER: a finite number, or `null` for absent. */
function isMaybeNumber(x: unknown): x is number | null {
  return x === null || (typeof x === 'number' && Number.isFinite(x))
}
function isNumber(x: unknown): x is number {
  return typeof x === 'number' && Number.isFinite(x)
}

function must(ok: boolean): void {
  if (!ok) throw new ShapeError('The result was in an unexpected format.')
}

export function asRaiseAssessment(v: unknown): RaiseAssessment {
  must(isRecord(v))
  const r = v as Record<string, unknown>
  must(
    typeof r['you can use Reg CF'] === 'boolean' &&
      isNumber(r['the most you can raise now']) &&
      isStringArray(r['blockers']) &&
      typeof r['financial statements you must provide'] === 'string' &&
      typeof r['why those financial statements'] === 'string' &&
      isStringArray(r['what you must still line up']) &&
      isStringArray(r['after you raise you must']) &&
      isStringArray(r['caveats']) &&
      typeof r['law as in force'] === 'string'
  )
  return r as unknown as RaiseAssessment
}

export function asInvestmentLimitAnswer(v: unknown): InvestmentLimitAnswer {
  must(isRecord(v))
  const r = v as Record<string, unknown>
  must(
    typeof r['you have no limit'] === 'boolean' &&
      isMaybeNumber(r['your 12 month limit']) &&
      isNumber(r['you have already used']) &&
      isMaybeNumber(r['you can still invest']) &&
      isNumber(r['we measured against']) &&
      typeof r['which limb applies'] === 'string' &&
      typeof r['how this is worked out'] === 'string' &&
      isStringArray(r['caveats'])
  )
  return r as unknown as InvestmentLimitAnswer
}

export function asResaleAnswer(v: unknown): ResaleAnswer {
  must(isRecord(v))
  const r = v as Record<string, unknown>
  must(
    typeof r['you may transfer'] === 'boolean' &&
      isNumber(r['days you must still wait']) &&
      typeof r['why'] === 'string' &&
      isStringArray(r['caveats'])
  )
  return r as unknown as ResaleAnswer
}

export function asReportingExitAnswer(v: unknown): ReportingExitAnswer {
  must(isRecord(v))
  const r = v as Record<string, unknown>
  must(
    typeof r['you may stop reporting'] === 'boolean' &&
      isStringArray(r['the conditions that let you stop']) &&
      isStringArray(r['while the duty runs you must']) &&
      isStringArray(r['caveats'])
  )
  return r as unknown as ReportingExitAnswer
}

/** A scalar NUMBER return. Measured: a NUMBER-returning export is NOT wrapped
 *  under its return-type name — the envelope carries `{"value": 7500}`, whereas
 *  a record carries `{"value":{"RaiseAssessment":{…}}}`. */
export function asNumber(v: unknown): number {
  must(isNumber(v))
  return v as number
}
