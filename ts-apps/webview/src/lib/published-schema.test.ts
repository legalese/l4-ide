import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { publishedInputSchema } from './published-schema'

type Published = {
  source: string
  metadataParameters: unknown
  openApiArguments: unknown
  mcpInputSchema: unknown
}
const fixture: { starter: Published; quirk: Published } = JSON.parse(
  readFileSync(
    new URL('./__fixtures__/starter-rule.json', import.meta.url),
    'utf8'
  )
)

/** MCP spells names without spaces; for this rule that is the one change. */
function mcpSpelling(node: unknown): unknown {
  if (node === null || typeof node !== 'object') return node
  if (Array.isArray(node)) return node.map(mcpSpelling)
  const out: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(node)) {
    if (k === 'properties') {
      out[k] = Object.fromEntries(
        Object.entries(v as object).map(([name, child]) => [
          name.replace(/ /g, '-'),
          mcpSpelling(child),
        ])
      )
    } else if (k === 'required') {
      out[k] = (v as string[]).map((n) => n.replace(/ /g, '-'))
    } else {
      out[k] = mcpSpelling(v)
    }
  }
  return out
}

describe('publishedInputSchema', () => {
  it('drops the keys the OpenAPI document drops, at every depth', () => {
    expect(
      publishedInputSchema({
        type: 'object',
        alias: 'x',
        propertyOrder: ['a'],
        'x-l4-type': 'T',
        'x-sanitized-name': 'a',
        properties: {
          a: {
            type: 'object',
            'x-l4-type': 'Person',
            propertyOrder: ['n'],
            properties: { n: { type: 'string', alias: 'name' } },
          },
          xs: {
            type: 'array',
            items: { type: 'object', 'x-l4-type': 'Item', properties: {} },
          },
        },
        required: ['a'],
      })
    ).toEqual({
      type: 'object',
      properties: {
        a: {
          type: 'object',
          properties: { n: { type: 'string' } },
        },
        xs: { type: 'array', items: { type: 'object', properties: {} } },
      },
      required: ['a'],
    })
  })

  it('keeps everything else, including defaults, enums and descriptions', () => {
    const node = {
      type: 'object',
      properties: {
        c: {
          type: 'string',
          enum: ['Red', 'Green'],
          default: 'Green',
          description: 'd',
          format: 'x',
        },
        n: { type: 'number', default: null },
      },
      required: [],
    }
    expect(publishedInputSchema(node)).toEqual(node)
  })

  it('does not change what it is given', () => {
    const node = { type: 'object', 'x-l4-type': 'T', properties: {} }
    publishedInputSchema(node)
    expect(node).toEqual({ type: 'object', 'x-l4-type': 'T', properties: {} })
  })

  it('leaves a value that is not a schema alone', () => {
    expect(publishedInputSchema(undefined)).toBeUndefined()
    expect(publishedInputSchema(null)).toBeNull()
  })
})

describe('a rule with a record, an enumerated input and a spaced name (recorded from a live service)', () => {
  const { starter } = fixture

  it('the deployed schema has the L4-only keys the OpenAPI document leaves out', () => {
    const raw = JSON.stringify(starter.metadataParameters)
    expect(raw).toContain('x-l4-type')
    expect(raw).toContain('propertyOrder')
    expect(JSON.stringify(starter.openApiArguments)).not.toContain('x-l4-type')
  })

  it('the disclosure equals the OpenAPI arguments schema', () => {
    expect(publishedInputSchema(starter.metadataParameters)).toEqual(
      starter.openApiArguments
    )
  })

  it('MCP differs from it only in spelling names without spaces', () => {
    expect(
      mcpSpelling(publishedInputSchema(starter.metadataParameters))
    ).toEqual(starter.mcpInputSchema)
    expect(JSON.stringify(starter.mcpInputSchema)).toContain('start-year')
    expect(JSON.stringify(starter.openApiArguments)).toContain('start year')
  })
})
