import { describe, it, expect } from 'vitest'
import { fromVizFunDecl } from '@repo/ladder-core'
import ladder420 from '../__fixtures__/live-ladder-420.json'
import ladderCheats from '../__fixtures__/live-ladder-cheats.json'
import schema420 from '../__fixtures__/live-schema-420.json'
import eval420 from '../__fixtures__/live-eval-420.json'
import { boundLeaves, elementPaths } from './valuation'
import { fillDefaults, factsSchema, stringFields } from './schema-fill'
import { LEWIS_CHRISTINE } from '../interview/preloads/lewis-christine'
import { asCharge } from '../api/validate'

/**
 * The machine half of the wire gate, against VERBATIM payloads the loopback
 * service returned on 2026-09-17 for the probe deployment (general + cheating).
 */
type Viz = Parameters<typeof fromVizFunDecl>[0]
const decode = (raw: unknown) =>
  fromVizFunDecl((raw as { funDecl: unknown }).funDecl as Viz)

describe('the live s 420 ladder', () => {
  it('is an AND whose first leaf CALLS `cheats`, printed as `cheats OF f`', () => {
    const { fn } = decode(ladder420)
    expect(fn.body.$type).toBe('And')
    const leaves = boundLeaves(fn, 'f')
    expect(leaves[0].label).toBe('cheats OF f')
    expect(leaves[0].binding).toEqual({ kind: 'call', fn: 'cheats' })
    // and it is a UBoolVar with its own unique, not an App
    expect(leaves[0].unique).toBeTypeOf('number')
  })
  it('reads the s 420 elements as facts-record paths', () => {
    const { fn } = decode(ladder420)
    expect(elementPaths(fn, 'f').map((p) => p.join('/'))).toEqual([
      'dishonestly',
      'deliver',
      'cause the delivery',
      'make, alter or destroy a valuable security',
    ])
  })
  it('the s 415 ladder has the seventeen elements of the section', () => {
    const { fn } = decode(ladderCheats)
    const paths = elementPaths(fn, 'f').map((p) => p.join('/'))
    expect(paths).toContain('deceived the victim')
    expect(paths).toContain('fraudulently')
    expect(paths).toContain('consent that any person shall retain any property')
    expect(paths).toContain('reputation')
    expect(paths).toHaveLength(17)
  })
})

describe('the live schema and the preload agree', () => {
  const info = schema420 as unknown as Parameters<typeof factsSchema>[0] & {
    parameters: { properties: Record<string, never> }
  }
  it('the Lewis Christine facts are already complete — filling changes nothing', () => {
    const schema = factsSchema(
      (schema420 as { parameters: Parameters<typeof factsSchema>[0] })
        .parameters,
      'f'
    )
    const facts = LEWIS_CHRISTINE.result.charges[0].facts
    expect(fillDefaults(schema, facts)).toEqual(facts)
    void info
  })
  it('the enum field is a string with three values', () => {
    const schema = factsSchema(
      (schema420 as { parameters: Parameters<typeof factsSchema>[0] })
        .parameters,
      'f'
    )
    const pronoun = stringFields(schema).find(
      (f) => f.path.join('/') === 'victim pronoun'
    )
    expect(pronoun?.enum).toEqual(['he', 'she', 'they'])
  })
})

describe('the live evaluation', () => {
  it('unwraps to a Charge that is made out, with the reported wording', () => {
    const raw = eval420 as {
      contents: { result: { value: { Charge: unknown } } }
    }
    const charge = asCharge(raw.contents.result.value.Charge)
    expect(charge['made out']).toBe(true)
    expect(charge.section).toBe('420')
    expect(charge.text).toMatch(
      /^You, Christine Lewis, are charged that you, on or about the 24th day of April 2000/
    )
    expect(charge.text).toMatch(
      /punishable under section 420 of the Penal Code 1871\.$/
    )
    expect(charge.refusal).toBe('')
  })
})
