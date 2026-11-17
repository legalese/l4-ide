import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { render } from 'svelte/server'
import type {
  ExportedFunctionInfo,
  FunctionParameters,
  RemoteFunctionSchema,
} from 'jl4-client-rpc'
import DefaultNotices from './components/default-notices.svelte'
import ToolCard from './components/tool-card.svelte'
import { reviewDeploy } from './deploy-compat'

/**
 * One rule, `the smaller of`, with `b IS A NUMBER TYPICALLY 0`, checked from
 * three sides that must agree: what the sidebar's card says (optional, 0), what
 * the service published (the schema), and what the service did with a call that
 * left `b` out (used 0, listed `b` under `presumed`).
 *
 * `__fixtures__/the-smaller-of.json` records what a running jl4-service
 * published and answered for the source in it (see its `_about`). It is a
 * recording, so this test is a check of the sidebar against the service's
 * output as of that capture, not of the service itself: the Haskell side of the
 * call is asserted in jl4-service/test/IntegrationSpec.hs ("TYPICALLY defaults").
 */
type Fixture = {
  source: string
  functionEndpoint: {
    name: string
    description: string
    returnType: string
    isDeontic: boolean
    parameters: FunctionParameters
  }
  openApiArguments: unknown
  mcpInputSchema: unknown
  callWithBLeftOut: {
    request: { arguments: Record<string, number> }
    response: { contents: { presumed: string[]; result: { value: number } } }
  }
  callWithBGiven: {
    request: { arguments: Record<string, number> }
    response: { contents: { presumed: string[]; result: { value: number } } }
  }
}

const fixture: Fixture = JSON.parse(
  readFileSync(
    new URL('./__fixtures__/the-smaller-of.json', import.meta.url),
    'utf8'
  )
)

const card = (): ExportedFunctionInfo => ({
  name: fixture.functionEndpoint.name,
  description: fixture.functionEndpoint.description,
  isDefault: true,
  returnType: fixture.functionEndpoint.returnType,
  isDeontic: fixture.functionEndpoint.isDeontic,
  parameters: fixture.functionEndpoint.parameters,
})

const body = (func: ExportedFunctionInfo) =>
  render(ToolCard, { props: { func, expanded: true } }).body

const plain = (html: string) =>
  html
    .replace(/<!--.*?-->/g, '')
    .replace(/<\/(div|summary|p|pre|details)>/g, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/[ \t]+/g, ' ')
    .replace(/ ?\n ?/g, '\n')
    .trim()

describe('the smaller of: the preview, the published schema and a call agree', () => {
  it('the source declares b with TYPICALLY 0', () => {
    expect(fixture.source).toContain('b IS A NUMBER TYPICALLY 0')
  })

  it('the published schema: b is optional with default 0, a is required', () => {
    const p = fixture.functionEndpoint.parameters
    expect(p.required).toEqual(['a'])
    expect(p.properties['b']).toMatchObject({ type: 'number', default: 0 })
    expect('default' in p.properties['a']!).toBe(false)
  })

  it('the function endpoint, OpenAPI and MCP publish the same inputs schema', () => {
    expect(fixture.openApiArguments).toEqual(
      fixture.functionEndpoint.parameters
    )
    expect(fixture.mcpInputSchema).toEqual(fixture.functionEndpoint.parameters)
  })

  it('the preview says optional, typically 0, and says what that means', () => {
    const t = plain(body(card()))
    expect(t).toContain('a number required')
    expect(t).toContain('b number optional, typically 0')
    expect(t).toContain(
      'If left out, 0 is used, and the answer lists b under presumed when it relies on that.'
    )
  })

  it('"What callers see" is the published schema, exactly', () => {
    const pre = body(card()).match(/<pre[^>]*>([\s\S]*?)<\/pre>/)![1]!
    const json = JSON.parse(pre.replace(/&quot;/g, '"').replace(/&amp;/g, '&'))
    expect(json).toEqual(fixture.mcpInputSchema)
    expect(json.properties.b.default).toBe(0)
    expect(json.required).toEqual(['a'])
  })

  it('a call that leaves b out uses 0 and lists exactly the inputs the preview marks optional, typically', () => {
    const left = fixture.callWithBLeftOut
    expect(Object.keys(left.request.arguments)).toEqual(['a'])
    const defaults = Object.entries(
      fixture.functionEndpoint.parameters.properties
    )
      .filter(([, node]) => 'default' in node)
      .map(([name]) => name)
    expect(left.response.contents.presumed).toEqual(defaults)
    expect(left.response.contents.presumed).toEqual(['b'])
    const b = fixture.functionEndpoint.parameters.properties['b']!
      .default as number
    expect(left.response.contents.result.value).toBe(
      Math.min(left.request.arguments['a']!, b)
    )
    // The same words the preview used for each presumed input.
    const t = plain(body(card()))
    for (const name of left.response.contents.presumed) {
      expect(t).toMatch(new RegExp(`${name} number optional, typically`))
    }
  })

  it('a call that gives b lists nothing under presumed', () => {
    const given = fixture.callWithBGiven
    expect(given.response.contents.presumed).toEqual([])
    expect(given.response.contents.result.value).toBe(3)
  })
})

describe('the smaller of: a redeploy that changes the default from 0 to 1', () => {
  const rule = (dflt: number) => ({
    name: 'the smaller of',
    parameters: {
      ...fixture.functionEndpoint.parameters,
      properties: {
        ...fixture.functionEndpoint.parameters.properties,
        b: {
          ...fixture.functionEndpoint.parameters.properties['b']!,
          default: dflt,
        },
      },
    },
  })

  it('is reported before the deploy, does not block it, and does not break', () => {
    const local = { ...card(), parameters: rule(1).parameters }
    const deployed: RemoteFunctionSchema = {
      name: 'the smaller of',
      returnType: 'NUMBER',
      isDeontic: false,
      parameters: rule(0).parameters,
    }
    const review = reviewDeploy([local], [deployed])
    expect(review.step).toBe('default-review')
    expect(review.breaking).toEqual([])
    expect(review.notices).toEqual([
      {
        kind: 'default-changed',
        function: 'the smaller of',
        input: 'b',
        old: 0,
        new: 1,
      },
    ])
  })

  it('reads as the review says it', () => {
    const items = [
      {
        kind: 'default-changed' as const,
        function: 'the smaller of',
        input: 'b',
        old: 0,
        new: 1,
      },
    ]
    expect(plain(render(DefaultNotices, { props: { items } }).body)).toBe(
      'the smaller of · b · typically 0 → 1: callers who leave b out will get different answers.'
    )
  })
})
