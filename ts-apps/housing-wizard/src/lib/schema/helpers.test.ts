import { describe, it, expect } from 'vitest'
import liveSchema from './__fixtures__/live-schema.json'
import { cleanLabel, humanizeKey, fieldId } from './labels'
import { classifyWidget } from './classify'
import { orderedChildKeys, buildFieldTree } from './build-tree'
import { seed, validate, toArguments } from './form-logic'
import type { WireSchema, FieldNode } from './types'
import type { FormState } from '$lib/api/types'

// The captured live ExportedFunctionInfo, viewed as the faithful wire schema.
const params = liveSchema.parameters as unknown as WireSchema
const situation = params.properties!['situation']
const sitProps = situation.properties!

function leaf(partial: Partial<FieldNode>): FieldNode {
  return {
    key: 'k',
    label: '',
    help: '',
    widget: 'text',
    required: false,
    enumOptions: [],
    children: [],
    raw: {},
    ...partial,
  }
}

describe('cleanLabel', () => {
  it('strips the leading space + surrounding backticks the wire emits', () => {
    expect(cleanLabel(' `How often is your rent due?`')).toBe(
      'How often is your rent due?'
    )
  })
  it('leaves an already-clean description unchanged (idempotent)', () => {
    const clean = "The tenant's rent and payment situation"
    expect(cleanLabel(clean)).toBe(clean)
    expect(cleanLabel(cleanLabel(clean))).toBe(cleanLabel(clean))
  })
  it('is idempotent on a backtick-wrapped string', () => {
    const raw = ' `How often is your rent due?`'
    expect(cleanLabel(cleanLabel(raw))).toBe(cleanLabel(raw))
  })
  it('coalesces undefined to empty string', () => {
    expect(cleanLabel(undefined)).toBe('')
  })
  it('does not underflow on a lone backtick', () => {
    expect(cleanLabel('`')).toBe('`')
  })
})

describe('classifyWidget', () => {
  it('classifies the RentPeriod enum node as enum (length gate)', () => {
    expect(classifyWidget(sitProps['how often rent is due'])).toBe('enum')
  })
  it('classifies number / boolean leaves correctly', () => {
    expect(classifyWidget(sitProps['rent amount each time'])).toBe('number')
    expect(classifyWidget(sitProps['has persistently paid rent late'])).toBe(
      'boolean'
    )
  })
  it('classifies the situation record as object', () => {
    expect(classifyWidget(situation)).toBe('object')
  })
  it('treats a string node with an omitted/empty enum as text, not a broken select', () => {
    expect(classifyWidget({ type: 'string' })).toBe('text')
    expect(classifyWidget({ type: 'string', enum: [] })).toBe('text')
  })
  it('puts object first even with a stray enum', () => {
    expect(
      classifyWidget({ type: 'object', properties: {}, enum: ['x'] })
    ).toBe('object')
  })
  it('classifies arrays as unsupported', () => {
    expect(classifyWidget({ type: 'array', items: { type: 'string' } })).toBe(
      'unsupported'
    )
  })
})

describe('orderedChildKeys', () => {
  it('follows propertyOrder, not the alphabetical wire key order', () => {
    expect(orderedChildKeys(situation)).toEqual([
      'how often rent is due',
      'rent amount each time',
      'arrears when the notice was served',
      'arrears expected at the hearing',
      'has persistently paid rent late',
    ])
  })
  it('appends a key missing from propertyOrder rather than dropping it', () => {
    const node: WireSchema = {
      type: 'object',
      properties: { a: { type: 'string' }, b: { type: 'string' } },
      propertyOrder: ['b'],
    }
    expect(orderedChildKeys(node)).toEqual(['b', 'a'])
  })
  it('falls back to object key order when propertyOrder is absent', () => {
    const node: WireSchema = {
      type: 'object',
      properties: { a: { type: 'string' }, b: { type: 'string' } },
    }
    expect(orderedChildKeys(node)).toEqual(['a', 'b'])
  })
})

describe('buildFieldTree', () => {
  const root = buildFieldTree(params, '__root__', new Set())
  const sitNode = root.children[0]

  it('reads required from the PARENT object node', () => {
    // situation itself is required (listed on params.required)
    expect(sitNode.required).toBe(true)
    // its children are required per situation.required
    expect(sitNode.children.every((c) => c.required)).toBe(true)
  })
  it('keeps the original spaced key, and carries the sanitized name', () => {
    const enumLeaf = sitNode.children[0]
    expect(enumLeaf.key).toBe('how often rent is due')
    expect(enumLeaf.sanitizedKey).toBe('how-often-rent-is-due')
  })
  it('orders children by propertyOrder', () => {
    expect(sitNode.children.map((c) => c.key)).toEqual(
      orderedChildKeys(situation)
    )
  })
})

describe('fieldId', () => {
  it('is always space-free, even when x-sanitized-name is absent', () => {
    const id = fieldId(leaf({ key: 'rent amount each time' }))
    expect(id).not.toContain(' ')
    expect(id).toBe('f-rent-amount-each-time')
  })
  it('prefers the sanitized name when present', () => {
    expect(fieldId(leaf({ key: 'a b', sanitizedKey: 'a-b' }))).toBe('f-a-b')
  })
})

describe('humanizeKey', () => {
  it('capitalises the first character', () => {
    expect(humanizeKey('rent amount each time')).toBe('Rent amount each time')
  })
})

describe('seed / validate / toArguments', () => {
  const root = buildFieldTree(params, '__root__', new Set())

  it('seeds unanswered sentinels (enum "", number null, boolean null)', () => {
    const m = seed(root)
    const sit = m.situation as FormState
    expect(sit['how often rent is due']).toBe('')
    expect(sit['rent amount each time']).toBeNull()
    expect(sit['has persistently paid rent late']).toBeNull()
  })

  it('flags every required leaf when the form is empty', () => {
    const errs = validate(root, seed(root))
    expect(Object.keys(errs)).toHaveLength(5)
  })

  it('blocks a non-finite amount (Infinity / NaN)', () => {
    const m = seed(root)
    const sit = m.situation as FormState
    sit['how often rent is due'] = 'weekly or fortnightly'
    sit['rent amount each time'] = Infinity
    sit['arrears when the notice was served'] = Number.NaN
    sit['arrears expected at the hearing'] = 0
    sit['has persistently paid rent late'] = false
    const errs = validate(root, m)
    expect(Object.values(errs)).toContain('Please enter a number, like 500')
  })

  it('blocks a negative amount', () => {
    const m = seed(root)
    const sit = m.situation as FormState
    sit['how often rent is due'] = 'weekly or fortnightly'
    sit['rent amount each time'] = -100
    sit['arrears when the notice was served'] = -50
    sit['arrears expected at the hearing'] = 0
    sit['has persistently paid rent late'] = false
    const errs = validate(root, m)
    expect(Object.values(errs)).toContain('Amount cannot be negative')
  })

  it('emits JS numbers and booleans (never stringified) in the eval payload', () => {
    const m = seed(root)
    const sit = m.situation as FormState
    sit['how often rent is due'] = 'weekly or fortnightly'
    sit['rent amount each time'] = 100
    sit['arrears when the notice was served'] = 1300
    sit['arrears expected at the hearing'] = 1400
    sit['has persistently paid rent late'] = false

    const args = toArguments(root, m)
    expect(args).toEqual({
      situation: {
        'how often rent is due': 'weekly or fortnightly',
        'rent amount each time': 100,
        'arrears when the notice was served': 1300,
        'arrears expected at the hearing': 1400,
        'has persistently paid rent late': false,
      },
    })
    expect(typeof args.situation['rent amount each time']).toBe('number')
    expect(typeof args.situation['has persistently paid rent late']).toBe(
      'boolean'
    )
  })
})
