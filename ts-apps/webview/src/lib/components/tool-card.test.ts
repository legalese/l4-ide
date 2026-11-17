import { describe, expect, it } from 'vitest'
import { render } from 'svelte/server'
import type { ExportedFunctionInfo } from 'jl4-client-rpc'
import ToolCard from './tool-card.svelte'

function html(func: ExportedFunctionInfo): string {
  return render(ToolCard, { props: { func, expanded: true } }).body
}

const fn = (parameters: unknown): ExportedFunctionInfo => ({
  name: 'the smaller of',
  description: '',
  isDefault: false,
  returnType: 'NUMBER',
  isDeontic: false,
  parameters: parameters as ExportedFunctionInfo['parameters'],
})

describe('ToolCard: usual values', () => {
  it('shows a usual value beside an input that may be left out', () => {
    const out = html(
      fn({
        type: 'object',
        properties: {
          a: { type: 'number', enum: [], description: '' },
          b: { type: 'number', enum: [], description: '', default: 0 },
        },
        required: ['a'],
      })
    )
    expect(out).toContain('usually 0')
    expect(out).toContain('optional')
    // a has no usual value and is required: nothing is said about it
    expect(out.match(/usually/g)).toHaveLength(1)
  })

  it('shows a usual value on a record field, and one that is false or empty', () => {
    const out = html(
      fn({
        type: 'object',
        properties: {
          cfg: {
            type: 'object',
            enum: [],
            description: '',
            required: [],
            properties: {
              retries: {
                type: 'number',
                enum: [],
                description: '',
                default: 3,
              },
              loud: {
                type: 'boolean',
                enum: [],
                description: '',
                default: false,
              },
              note: {
                type: 'string',
                enum: [],
                description: '',
                default: null,
              },
            },
          },
        },
        required: ['cfg'],
      })
    )
    expect(out).toContain('usually 3')
    expect(out).toContain('usually false')
    expect(out).toContain('usually empty')
  })

  it('marks the usual constructor of an enumerated input', () => {
    const out = html(
      fn({
        type: 'object',
        properties: {
          c: {
            type: 'string',
            enum: ['Green', 'Red'],
            description: '',
            default: 'Red',
          },
        },
        required: [],
      })
    )
    expect(out).toContain('usually Red')
    expect(out).toMatch(/enum-tag[^>]*usual[^>]*>Red</)
    expect(out).not.toMatch(/enum-tag[^>]*usual[^>]*>Green</)
  })

  it('says nothing when a deployed schema carries no usual values', () => {
    const out = html(
      fn({
        type: 'object',
        properties: { a: { type: 'number', enum: [], description: '' } },
        required: ['a'],
      })
    )
    expect(out).not.toContain('usually')
  })
})
