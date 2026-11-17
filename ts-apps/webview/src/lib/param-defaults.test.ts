import { describe, expect, it } from 'vitest'
import {
  anyInputHasDefault,
  defaultOf,
  describeDefault,
  hasDefault,
} from './param-defaults'

describe('hasDefault', () => {
  it('is true for a number, a string, a boolean, and zero, false and empty', () => {
    expect(hasDefault({ default: 3 })).toBe(true)
    expect(hasDefault({ default: 0 })).toBe(true)
    expect(hasDefault({ default: false })).toBe(true)
    expect(hasDefault({ default: '' })).toBe(true)
    expect(hasDefault({ default: 'Red' })).toBe(true)
  })

  it('counts a null default (TYPICALLY NOTHING) as a default', () => {
    expect(hasDefault({ default: null })).toBe(true)
  })

  it('is false when the key is absent', () => {
    expect(hasDefault({})).toBe(false)
    expect(hasDefault({ default: undefined })).toBe(false)
    expect(hasDefault(undefined)).toBe(false)
    expect(hasDefault(null)).toBe(false)
  })

  it('does not read a default through the prototype chain', () => {
    expect(hasDefault(Object.create({ default: 1 }))).toBe(false)
  })
})

describe('defaultOf', () => {
  it('returns the value, including null, and undefined when there is none', () => {
    expect(defaultOf({ default: 7 })).toBe(7)
    expect(defaultOf({ default: null })).toBeNull()
    expect(defaultOf({})).toBeUndefined()
  })
})

describe('describeDefault', () => {
  it('spells a number as it is', () => {
    expect(describeDefault({ default: 0 })).toBe('0')
    expect(describeDefault({ default: 3 })).toBe('3')
    expect(describeDefault({ default: 0.07 })).toBe('0.07')
    expect(describeDefault({ default: -2.5 })).toBe('-2.5')
  })

  it('spells a boolean as the type column does', () => {
    expect(describeDefault({ default: true })).toBe('true')
    expect(describeDefault({ default: false })).toBe('false')
  })

  it('quotes a string, so that an empty or padded one is visible', () => {
    expect(describeDefault({ default: 'N/A' })).toBe('"N/A"')
    expect(describeDefault({ default: '' })).toBe('""')
    expect(describeDefault({ default: ' x ' })).toBe('" x "')
  })

  it('spells a constructor of an enumerated input by its bare name', () => {
    expect(
      describeDefault({
        enum: ['Green', 'Red'],
        default: 'Red',
      })
    ).toBe('Red')
  })

  it('spells a null default as empty', () => {
    expect(describeDefault({ default: null })).toBe('empty')
  })

  it('has nothing to say when there is no default', () => {
    expect(describeDefault({})).toBeUndefined()
    expect(describeDefault({ enum: ['A'] })).toBeUndefined()
  })

  it('falls back to JSON for a shape the service does not publish today', () => {
    expect(describeDefault({ default: { a: 1 } })).toBe('{"a":1}')
    expect(describeDefault({ default: [1, 2] })).toBe('[1,2]')
  })
})

describe('anyInputHasDefault', () => {
  const params = (props: Record<string, unknown>) => ({
    type: 'object' as const,
    properties: props as Record<string, never>,
    required: [] as string[],
  })

  it('finds a default on a rule input', () => {
    expect(
      anyInputHasDefault([{ parameters: params({ a: {}, b: { default: 0 } }) }])
    ).toBe(true)
  })

  it('finds a default on a record field, at any depth', () => {
    expect(
      anyInputHasDefault([
        {
          parameters: params({
            cfg: {
              properties: { inner: { properties: { n: { default: 1 } } } },
            },
          }),
        },
      ])
    ).toBe(true)
  })

  it('does not look inside a list element, which the card does not list', () => {
    expect(
      anyInputHasDefault([
        {
          parameters: params({
            xs: { items: { properties: { n: { default: 1 } } } },
          }),
        },
      ])
    ).toBe(false)
  })

  it('is false when no input has one', () => {
    expect(
      anyInputHasDefault([{ parameters: params({ a: {}, b: { type: 'x' } }) }])
    ).toBe(false)
    expect(anyInputHasDefault([])).toBe(false)
  })
})
