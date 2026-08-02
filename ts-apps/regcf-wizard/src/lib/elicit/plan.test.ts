import { describe, it, expect } from 'vitest'
import {
  bindKey,
  humaniseAtom,
  isSettled,
  nextAsk,
  verdictHeadline,
  verdictTone,
} from './plan'
import type { PlanAtom, QueryPlanResponse, Verdict } from '$lib/api/types'

// Transcribed from live `POST …/can this company raise/query-plan` responses.
const eligible: PlanAtom = {
  atomId: 'a87d9b26-bfef-5b0b-9c22-d77d103f93a9',
  label: '`issuer is eligible` OF (`issuer profile from` OF plan)',
  unique: 4,
  inputRefs: [],
}
const withinLimit: PlanAtom = {
  atomId: '6cfcd833-b7a7-5ef0-949e-01ac8c679de2',
  label: '`offering is within the offering limit` OF (`offering from` OF plan)',
  unique: 6,
  inputRefs: [],
}

const plan = (
  verdict: Verdict,
  determined: boolean | null,
  stillNeeded: PlanAtom[]
): QueryPlanResponse => ({
  verdict,
  determined,
  ranked: [eligible, withinLimit],
  stillNeeded,
})

describe('isSettled — the rule that must not be got wrong', () => {
  // `Backend/DecisionQueryPlan.hs:224-226`: a UI that switches on `determined`
  // "will sooner or later tell someone they complied with a rule that never
  // reached them". These three cases are that comment, made executable.
  it('treats Holds and Fails as settled', () => {
    expect(isSettled('Holds')).toBe(true)
    expect(isSettled('Fails')).toBe(true)
  })
  it('treats Vacuous / Inconsistent / Tautology as settled even though `determined` is null', () => {
    for (const v of ['Vacuous', 'Inconsistent', 'Tautology'] as Verdict[]) {
      expect(isSettled(v)).toBe(true)
      // and the loop would NOT stop if it read `determined`:
      expect(plan(v, null, []).determined).toBeNull()
    }
  })
  it('treats Undetermined, and only Undetermined, as "keep asking"', () => {
    expect(isSettled('Undetermined')).toBe(false)
  })
})

describe('verdictTone', () => {
  it('never colours Vacuous or Inconsistent as a yes or a no', () => {
    expect(verdictTone('Vacuous')).toBe('neither')
    expect(verdictTone('Inconsistent')).toBe('neither')
    expect(verdictTone('Holds')).toBe('yes')
    expect(verdictTone('Fails')).toBe('no')
  })
  it('has a headline for every verdict', () => {
    for (const v of [
      'Holds',
      'Fails',
      'Undetermined',
      'Vacuous',
      'Inconsistent',
      'Tautology',
    ] as Verdict[]) {
      expect(verdictHeadline(v).length).toBeGreaterThan(0)
    }
  })
})

describe('nextAsk — progressive disclosure', () => {
  it('asks in the service’s ranked order, restricted to what is still needed', () => {
    expect(nextAsk(plan('Undetermined', null, [eligible, withinLimit]))).toBe(
      eligible
    )
    expect(nextAsk(plan('Undetermined', null, [withinLimit]))).toBe(withinLimit)
  })
  it('stops asking the moment the verdict settles — this is the early stop', () => {
    // The live service returns Fails with stillNeeded EMPTY once limb 1 is
    // false, so the second question is never put.
    expect(nextAsk(plan('Fails', false, []))).toBeNull()
    // And it must stop even if the service still lists outstanding atoms.
    expect(nextAsk(plan('Holds', true, [withinLimit]))).toBeNull()
  })
})

describe('humaniseAtom', () => {
  it('drops the projection chain and the L4 backticks', () => {
    expect(humaniseAtom(eligible.label)).toBe('Issuer is eligible')
    expect(humaniseAtom(withinLimit.label)).toBe(
      'Offering is within the offering limit'
    )
  })
  it('leaves a plain label alone but for capitalisation', () => {
    expect(humaniseAtom('`rent is overdue`')).toBe('Rent is overdue')
  })
})

describe('bindKey', () => {
  // The binding key is `unique` as a decimal string, NOT atomId: the ladder
  // payload and the query plan carry DIFFERENT atomIds for the same atom
  // (64e895d0-… vs a87d9b26-… for unique 4), and binding by the ladder's atomId
  // silently no-ops. Measured against the live service.
  it('is the unique, as a string', () => {
    expect(bindKey(eligible)).toBe('4')
    expect(bindKey(withinLimit)).toBe('6')
    expect(bindKey(eligible)).not.toBe(eligible.atomId)
  })
})
