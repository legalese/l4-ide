import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { render } from 'svelte/server'
import type { ExportedFunctionInfo } from 'jl4-client-rpc'
import ToolCard from './tool-card.svelte'

function html(func: ExportedFunctionInfo): string {
  return render(ToolCard, { props: { func, expanded: true } }).body
}

/** The card as a reader gets it: tags gone, each block on its own line. */
function text(func: ExportedFunctionInfo): string {
  return html(func)
    .replace(/<!--.*?-->/g, '')
    .replace(/<\/(div|summary|p|pre|details)>/g, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/[ \t]+/g, ' ')
    .replace(/ ?\n ?/g, '\n')
    .trim()
}

const fn = (
  parameters: unknown,
  rest: Partial<ExportedFunctionInfo> = {}
): ExportedFunctionInfo => ({
  name: 'the smaller of',
  description: '',
  isDefault: false,
  returnType: 'NUMBER',
  isDeontic: false,
  parameters: parameters as ExportedFunctionInfo['parameters'],
  ...rest,
})

const smaller = {
  type: 'object',
  properties: {
    a: { type: 'number' },
    b: { type: 'number', default: 0 },
  },
  required: ['a'],
}

describe('ToolCard: what each input needs', () => {
  it('says required, or optional with its default, on each input', () => {
    const t = text(fn(smaller))
    expect(t).toContain('a number required')
    expect(t).toContain('b number optional, typically 0')
  })

  it('says in plain words what a caller who leaves a defaulted input out gets', () => {
    expect(text(fn(smaller))).toContain(
      'If left out, 0 is used, and the answer lists b under presumed when it relies on that.'
    )
  })

  it('names a record field by its path, with the same words', () => {
    const t = text(
      fn({
        type: 'object',
        properties: {
          cfg: {
            type: 'object',
            required: ['name'],
            properties: {
              name: { type: 'string' },
              retries: { type: 'number', default: 3 },
              loud: { type: 'boolean', default: false },
              note: { type: 'string', default: null },
            },
          },
        },
        required: ['cfg'],
      })
    )
    expect(t).toContain('cfg.name string required')
    expect(t).toContain('cfg.retries number optional, typically 3')
    expect(t).toContain('lists cfg.retries under presumed')
    expect(t).toContain('cfg.loud boolean optional, typically false')
    expect(t).toContain('cfg.note string optional, typically nothing')
  })

  it('marks the default constructor of an enumerated input', () => {
    const out = html(
      fn({
        type: 'object',
        properties: {
          c: { type: 'string', enum: ['Green', 'Red'], default: 'Red' },
        },
        required: [],
      })
    )
    expect(out).toContain('optional, typically Red')
    expect(out).toMatch(/enum-tag[^>]*default[^>]*>Red</)
    expect(out).not.toMatch(/enum-tag[^>]*default[^>]*>Green</)
  })

  it('says optional, with no default, for an input that may be left out and has none', () => {
    const t = text(
      fn({
        type: 'object',
        properties: { m: { type: 'number' } },
        required: [],
      })
    )
    expect(t).toContain('m number optional')
    expect(t).not.toContain('typically')
  })

  it('shows an input the file gives an unpublished default, as neither required nor hidden', () => {
    const t = text(
      fn(
        {
          type: 'object',
          properties: { jurisdiction: { type: 'string' } },
          required: ['jurisdiction'],
        },
        { unpublishedDefaults: ['jurisdiction'] }
      )
    )
    expect(t).toContain('jurisdiction string typically (not published)')
    expect(t).not.toContain('jurisdiction string required')
    expect(t).toContain('Callers must still supply it.')
  })

  it('says nothing about defaults when a deployed schema carries none', () => {
    const t = text(
      fn({
        type: 'object',
        properties: { a: { type: 'number' } },
        required: ['a'],
      })
    )
    expect(t).toContain('a number required')
    expect(t).not.toContain('typically')
    expect(t).not.toContain('presumption')
  })
})

describe('ToolCard: the presumption switch', () => {
  it('is mentioned when some input has a default', () => {
    expect(text(fn(smaller))).toContain(
      'Callers can turn the defaults off with presumption: hard (HTTP, batch, MCP, WebMCP).'
    )
  })

  it('is mentioned once per card, however many defaults', () => {
    const t = text(
      fn({
        type: 'object',
        properties: {
          a: { type: 'number', default: 1 },
          b: { type: 'number', default: 2 },
        },
        required: [],
      })
    )
    expect(t.match(/presumption: hard/g)).toHaveLength(1)
  })

  it('is not mentioned when no input has a default', () => {
    expect(
      text(
        fn({
          type: 'object',
          properties: { a: { type: 'number' } },
          required: ['a'],
        })
      )
    ).not.toContain('presumption')
  })
})

describe('ToolCard: What callers see', () => {
  const published = (func: ExportedFunctionInfo) => {
    const out = html(func)
    const open = out.match(/<details[^>]*>/)![0]
    const pre = out.match(/<pre[^>]*>([\s\S]*?)<\/pre>/)![1]!
    const decoded = pre
      .replace(/&quot;/g, '"')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&')
    return { open, json: JSON.parse(decoded) }
  }

  it('is collapsed by default', () => {
    expect(published(fn(smaller)).open).not.toMatch(/\bopen\b/)
  })

  it('shows the schema the card was given, untouched', () => {
    expect(published(fn(smaller)).json).toEqual(smaller)
  })

  it('carries the default and the required list a client reads', () => {
    const { json } = published(fn(smaller))
    expect(json.properties.b).toEqual({ type: 'number', default: 0 })
    expect(json.required).toEqual(['a'])
  })

  it('says a DEONTIC rule also takes the simulation envelope', () => {
    const t = text(fn(smaller, { isDeontic: true }))
    expect(t).toContain('startTime')
    expect(t).toContain('events')
    expect(text(fn(smaller))).not.toContain('startTime')
  })
})

describe('ToolCard: What callers see, for a rule with a record, an enum and a spaced name', () => {
  // Recorded from a live service: see __fixtures__/starter-rule.json.
  const { starter } = JSON.parse(
    readFileSync(
      new URL('../__fixtures__/starter-rule.json', import.meta.url),
      'utf8'
    )
  )
  const func = fn(starter.metadataParameters, { name: 'describe' })
  const shown = () => {
    const pre = html(func).match(/<pre[^>]*>([\s\S]*?)<\/pre>/)![1]!
    return JSON.parse(
      pre
        .replace(/&quot;/g, '"')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&amp;/g, '&')
    )
  }

  it('shows exactly what the OpenAPI document publishes for the inputs', () => {
    expect(shown()).toEqual(starter.openApiArguments)
  })

  it('does not show the keys no client receives', () => {
    const raw = JSON.stringify(shown())
    for (const key of [
      'x-l4-type',
      'propertyOrder',
      'x-sanitized-name',
      'alias',
    ]) {
      expect(raw).not.toContain(key)
    }
  })

  it('says the schema is as the service describes it to callers, not that it is the OpenAPI document', () => {
    const t = text(func).replace(/\s+/g, ' ')
    expect(t).toContain('as the service describes them to callers')
    expect(t).not.toContain('OpenAPI document publishes')
  })

  it('says MCP and WebMCP spell input names without spaces', () => {
    expect(text(func).replace(/\s+/g, ' ')).toContain(
      'MCP and WebMCP spell input names without spaces (for example start year becomes start-year).'
    )
  })

  it('keeps the input names as the OpenAPI document spells them', () => {
    expect(JSON.stringify(shown())).toContain('"start year"')
  })
})
