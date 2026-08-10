import { describe, it, expect } from 'vitest'
import {
  applyLawTime,
  formatIso,
  isIso,
  lawTimeComparison,
  money,
  todayIso,
} from './lawtime'

describe('applyLawTime — ruling R8', () => {
  it('lets law-time track fact-time by default, and SAYS so', () => {
    const a = applyLawTime('2022-06-01', null)
    expect(a.ruleDate).toBe('2022-06-01')
    expect(a.source).toBe('fact')
    expect(a.because).toContain('1 June 2022')
    expect(a.because).toContain('that is when the investment was made')
  })

  it('lets an override pin law-time independently, and says THAT instead', () => {
    const a = applyLawTime('2026-08-02', '2016-06-01')
    expect(a.ruleDate).toBe('2016-06-01')
    expect(a.source).toBe('override')
    expect(a.because).toContain('you pinned that date')
    // The override sentence names the fact date only to DENY it — an auditor
    // reading a pinned answer must not be able to mistake it for a fact-date
    // answer.
    expect(a.because).toContain('not because of when the investment was made')
    expect(applyLawTime('2026-08-02', null).because).not.toContain('pinned')
  })

  it('ignores a malformed override rather than sending it to the engine', () => {
    expect(applyLawTime('2022-06-01', 'last June').ruleDate).toBe('2022-06-01')
    expect(applyLawTime('2022-06-01', '').ruleDate).toBe('2022-06-01')
  })
})

describe('formatIso / isIso / todayIso', () => {
  it('prints the day the user picked, anchored to UTC', () => {
    expect(formatIso('2022-06-01')).toBe('1 June 2022')
    expect(formatIso('2016-06-01')).toBe('1 June 2016')
  })
  it('passes a non-date through untouched rather than inventing one', () => {
    expect(formatIso('not a date')).toBe('not a date')
  })
  it('accepts real calendar days only', () => {
    expect(isIso('2023-01-01')).toBe(true)
    expect(isIso('2023-13-01')).toBe(false)
    expect(isIso('2023-02-29')).toBe(false)
  })
  it('renders today in the local calendar, zero-padded', () => {
    expect(todayIso(new Date(2026, 7, 2))).toBe('2026-08-02')
  })
})

describe('lawTimeComparison', () => {
  // The three numbers are live: the same investor (income 150000, net worth
  // 80000, invested 0, not accredited) gets 4000 under the rules in force on
  // 2016-06-01 and 2018-01-01, and 7500 under those in force on 2023-01-01.
  const applied = applyLawTime('2016-06-01', null)

  it('says so plainly when the two clocks give different answers', () => {
    const s = lawTimeComparison(4000, 7500, applied, '2 August 2026')
    expect(s).toContain('$4,000')
    expect(s).toContain('$7,500')
    expect(s).toContain('two rule dates, two answers')
  })

  it('does not manufacture a difference when there is none', () => {
    const s = lawTimeComparison(
      7500,
      7500,
      applyLawTime('2023-01-01', null),
      '2 August 2026'
    )
    expect(s).toContain('do not bite')
    expect(s).not.toContain('two rule dates, two answers')
  })

  it('handles the accredited investor, for whom today’s rules set no limit', () => {
    const s = lawTimeComparison(4000, null, applied, '2 August 2026')
    expect(s).toContain('no limit')
    expect(s).toContain('nothing to compare')
  })
})

describe('money', () => {
  it('renders whole dollars', () => {
    expect(money(7500)).toBe('$7,500')
    expect(money(5000000)).toBe('$5,000,000')
  })
})
