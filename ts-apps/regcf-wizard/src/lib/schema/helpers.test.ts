import { describe, it, expect } from 'vitest'
import { cleanLabel, humanizeKey, fieldId } from './labels'
import { classifyWidget } from './classify'
import { buildFieldTree, orderedChildKeys } from './build-tree'
import { seed, validate, toArguments, isIsoDate } from './form-logic'
import type { WireSchema, FieldNode } from './types'

// Every fixture below is a transcription of a LIVE response from the deployed
// `regcf` bundle, not an invention. The two that matter most are the DATE node
// (which no housing-wizard fixture had) and the two-root parameter object.

const ruleDate: WireSchema = {
  description:
    'Apply the rules as they stood on this date — for example, the date the investment was actually made',
  format: 'date',
  type: 'string',
  'x-sanitized-name': 'rule-date',
}

const investorFacts: WireSchema = {
  description:
    'Your income, your net worth, and what you have already invested under Regulation Crowdfunding',
  type: 'object',
  'x-l4-type': 'InvestorFacts',
  properties: {
    'invested under Reg CF in the last 12 months': {
      description: 'How much have you already invested … in dollars?',
      type: 'number',
      'x-sanitized-name': 'invested-under-Reg-CF-in-the-last-12-months',
    },
    'is an accredited investor': {
      description: 'Are you an accredited investor …?',
      type: 'boolean',
      'x-sanitized-name': 'is-an-accredited-investor',
    },
    'your annual income': {
      description: 'Your annual income, in dollars',
      type: 'number',
      'x-sanitized-name': 'your-annual-income',
    },
    'your net worth': {
      description: 'Your net worth, in dollars',
      type: 'number',
      'x-sanitized-name': 'your-net-worth',
    },
  },
  propertyOrder: [
    'is an accredited investor',
    'your annual income',
    'your net worth',
    'invested under Reg CF in the last 12 months',
  ],
  required: [
    'is an accredited investor',
    'your annual income',
    'your net worth',
    'invested under Reg CF in the last 12 months',
  ],
}

/** The law-time export's root: TWO parameters, NO propertyOrder. */
const twoRootParams: WireSchema = {
  type: 'object',
  properties: { 'rule date': ruleDate, facts: investorFacts },
  required: ['rule date', 'facts'],
}

describe('cleanLabel', () => {
  it('strips the backticks jl4-service wraps DECLARE-field descriptions in', () => {
    expect(cleanLabel(' `Your annual income, in dollars`')).toBe(
      'Your annual income, in dollars'
    )
  })
  it('leaves a clean @desc alone and is null-safe', () => {
    expect(cleanLabel('Your net worth, in dollars')).toBe(
      'Your net worth, in dollars'
    )
    expect(cleanLabel(undefined)).toBe('')
  })
})

describe('humanizeKey / fieldId', () => {
  it('capitalises a spaced key', () => {
    expect(humanizeKey('rule date')).toBe('Rule date')
  })
  it('never emits an id containing a space, with or without x-sanitized-name', () => {
    const withSan = { key: 'rule date', sanitizedKey: 'rule-date' } as FieldNode
    const without = { key: 'rule date' } as FieldNode
    expect(fieldId(withSan)).toBe('f-rule-date')
    expect(fieldId(without)).toBe('f-rule-date')
  })
})

describe('classifyWidget', () => {
  it('classifies an L4 DATE as a date, not free text', () => {
    expect(classifyWidget(ruleDate)).toBe('date')
  })
  it('still classifies a plain string as text', () => {
    expect(classifyWidget({ type: 'string' })).toBe('text')
  })
  it('handles the wire shapes that omit `enum` entirely', () => {
    expect(classifyWidget({ type: 'number' })).toBe('number')
    expect(classifyWidget({ type: 'boolean' })).toBe('boolean')
  })
  it('prefers object even when a stray enum is present', () => {
    expect(
      classifyWidget({ type: 'object', properties: {}, enum: ['x'] })
    ).toBe('object')
  })
  it('treats arrays as unsupported', () => {
    expect(classifyWidget({ type: 'array', items: { type: 'string' } })).toBe(
      'unsupported'
    )
  })
})

describe('orderedChildKeys', () => {
  it('uses propertyOrder when present', () => {
    expect(orderedChildKeys(investorFacts)[0]).toBe('is an accredited investor')
  })
  it('falls back to `required` when propertyOrder is absent — so the rule date leads', () => {
    // Object.keys here is ['rule date','facts'] only by luck of insertion; the
    // service emits alphabetical properties, which would put facts first. The
    // required list is the only order the wire actually states.
    expect(orderedChildKeys(twoRootParams)).toEqual(['rule date', 'facts'])
  })
  it('never drops a key missing from the stated order', () => {
    const p: WireSchema = {
      type: 'object',
      properties: { a: { type: 'number' }, b: { type: 'number' } },
      propertyOrder: ['b'],
    }
    expect(orderedChildKeys(p)).toEqual(['b', 'a'])
  })
})

describe('buildFieldTree', () => {
  const root = buildFieldTree(twoRootParams, '__root__', new Set())

  it('marks both roots required from the PARENT node’s required list', () => {
    expect(root.children.map((c) => c.key)).toEqual(['rule date', 'facts'])
    expect(root.children.every((c) => c.required)).toBe(true)
  })
  it('recurses into the record parameter', () => {
    const facts = root.children[1]
    expect(facts.widget).toBe('object')
    expect(facts.children).toHaveLength(4)
    expect(facts.children[0].label).toBe('Are you an accredited investor …?')
  })
})

describe('seed / validate / toArguments', () => {
  const root = buildFieldTree(twoRootParams, '__root__', new Set())

  it('seeds booleans and numbers to null (unanswered), dates to the empty string', () => {
    const s = seed(root)
    expect(s['rule date']).toBe('')
    const facts = s['facts'] as Record<string, unknown>
    expect(facts['is an accredited investor']).toBeNull()
    expect(facts['your annual income']).toBeNull()
  })

  it('reports an unanswered boolean rather than silently asserting false', () => {
    const errs = validate(root, seed(root))
    expect(Object.values(errs)).toContain('Please choose Yes or No')
  })

  it('rejects a non-ISO date and a negative amount', () => {
    const s = seed(root)
    s['rule date'] = 'last June'
    const facts = s['facts'] as Record<string, unknown>
    facts['is an accredited investor'] = false
    facts['your annual income'] = -1
    facts['your net worth'] = 80000
    facts['invested under Reg CF in the last 12 months'] = 0
    const errs = validate(root, s)
    expect(errs['f-rule-date']).toBe('Please give a date as YYYY-MM-DD')
    expect(errs['f-your-annual-income']).toBe('Amount cannot be negative')
  })

  it('accepts a well-formed answer and builds a MULTI-ROOT payload', () => {
    const s = seed(root)
    s['rule date'] = '2022-06-01'
    const facts = s['facts'] as Record<string, unknown>
    facts['is an accredited investor'] = false
    facts['your annual income'] = 150000
    facts['your net worth'] = 80000
    facts['invested under Reg CF in the last 12 months'] = 0
    expect(validate(root, s)).toEqual({})
    // The housing wizard cast this to `{situation: …}`. Two roots, both present,
    // both keyed by their ORIGINAL spaced names — this is the exact body the
    // live `investment limit under the rules effective on` endpoint accepted.
    expect(toArguments(root, s)).toEqual({
      'rule date': '2022-06-01',
      facts: {
        'is an accredited investor': false,
        'your annual income': 150000,
        'your net worth': 80000,
        'invested under Reg CF in the last 12 months': 0,
      },
    })
  })
})

describe('isIsoDate', () => {
  it('accepts a real calendar day and rejects an impossible one', () => {
    expect(isIsoDate('2022-06-01')).toBe(true)
    expect(isIsoDate('2022-02-30')).toBe(false)
    expect(isIsoDate('01/06/2022')).toBe(false)
    expect(isIsoDate('')).toBe(false)
  })
})
