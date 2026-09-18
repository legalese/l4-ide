import { describe, it, expect } from 'vitest'
import type { FunctionParameter } from '$lib/api/types'
import { fillDefaults, stringFields } from './schema-fill'

const schema: FunctionParameter = {
  type: 'object',
  enum: [],
  description: 'facts',
  propertyOrder: ['particulars', 'victim', 'victim pronoun', 'deliver'],
  properties: {
    particulars: {
      type: 'object',
      enum: [],
      description: '',
      propertyOrder: ['accused', 'common intention'],
      properties: {
        accused: { type: 'string', enum: [], description: 'name' },
        'common intention': { type: 'boolean', enum: [], description: 's 34' },
      },
    },
    victim: { type: 'string', enum: [], description: 'the victim' },
    'victim pronoun': {
      type: 'string',
      enum: ['he', 'she', 'they'],
      description: 'pronoun',
    },
    deliver: { type: 'boolean', enum: [], description: 'delivered?' },
  },
}

describe('fillDefaults', () => {
  it('completes a partial record with type identities, in schema order', () => {
    const out = fillDefaults(schema, {
      victim: 'Wong',
      deliver: true,
    }) as Record<string, unknown>
    expect(Object.keys(out)).toEqual([
      'particulars',
      'victim',
      'victim pronoun',
      'deliver',
    ])
    expect(out.particulars).toEqual({ accused: '', 'common intention': false })
    expect(out['victim pronoun']).toBe('he')
    expect(out.deliver).toBe(true)
  })
  it('keeps a supplied false rather than treating it as missing', () => {
    const out = fillDefaults(schema, { deliver: false }) as Record<
      string,
      unknown
    >
    expect(out.deliver).toBe(false)
  })
})

describe('stringFields', () => {
  it('lists the string and enum fields with their paths', () => {
    expect(stringFields(schema).map((f) => f.path.join('/'))).toEqual([
      'particulars/accused',
      'victim',
      'victim pronoun',
    ])
    expect(stringFields(schema)[2].enum).toEqual(['he', 'she', 'they'])
  })
})
