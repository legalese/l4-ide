import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import type {
  ExportedFunctionInfo,
  FunctionParameters,
  RemoteFunctionSchema,
} from 'jl4-client-rpc'
import {
  changeToPlainText,
  detectBreakingChanges,
  detectDefaultChanges,
} from './deploy-compat'

/** The cases the service's compatibility check runs too (U2). */
type SharedCase = {
  name: string
  function: string
  old: unknown
  new: unknown
  expect: { breaking: string[]; notices: unknown[] }
}

const sharedCases: SharedCase[] = JSON.parse(
  readFileSync(
    new URL(
      '../../../../jl4-service/test/fixtures/default-change-cases.json',
      import.meta.url
    ),
    'utf8'
  )
).cases

function localFn(c: SharedCase): ExportedFunctionInfo {
  return {
    name: c.function,
    description: '',
    isDefault: false,
    returnType: 'NUMBER',
    isDeontic: false,
    parameters: c.new as FunctionParameters,
  }
}

function remoteFn(c: SharedCase): RemoteFunctionSchema {
  return {
    name: c.function,
    returnType: 'NUMBER',
    isDeontic: false,
    parameters: c.old as FunctionParameters,
  }
}

describe('shared default-change cases: breaking[]', () => {
  it('reads the eight shared cases', () => {
    expect(sharedCases).toHaveLength(8)
  })

  for (const c of sharedCases) {
    it(c.name, () => {
      const breaking = detectBreakingChanges([localFn(c)], [remoteFn(c)]).map(
        changeToPlainText
      )
      expect(breaking).toEqual(c.expect.breaking)
    })
  }
})

describe('detectBreakingChanges', () => {
  it('words a change the way the service words it, names undecorated', () => {
    const c = sharedCases.find((x) => x.name.startsWith('default removed'))!
    const [change] = detectBreakingChanges([localFn(c)], [remoteFn(c)])
    // The page sets a name with spaces in backticks; the plain text does not.
    expect(change![0]!.text).toBe('`the smaller of`')
    expect(changeToPlainText(change!)).toBe(
      'the smaller of parameter b is now required'
    )
  })

  it('reports a removed rule', () => {
    const c = sharedCases[0]!
    expect(
      detectBreakingChanges([], [remoteFn(c)]).map(changeToPlainText)
    ).toEqual(['rule the smaller of removed'])
  })
})

describe('shared default-change cases: notices[]', () => {
  for (const c of sharedCases) {
    it(c.name, () => {
      expect(detectDefaultChanges([localFn(c)], [remoteFn(c)])).toEqual(
        c.expect.notices
      )
    })
  }
})

describe('shared default-change cases: breaking[] and notices[] together', () => {
  // One upload, both checks, as the deploy review runs them: a notice never
  // changes what blocks, and what blocks never hides a notice.
  for (const c of sharedCases) {
    it(c.name, () => {
      const local = [localFn(c)]
      const remote = [remoteFn(c)]
      expect({
        breaking: detectBreakingChanges(local, remote).map(changeToPlainText),
        notices: detectDefaultChanges(local, remote),
      }).toEqual(c.expect)
    })
  }
})

describe('detectDefaultChanges', () => {
  const rule = (name: string, properties: Record<string, unknown>) => ({
    name,
    description: '',
    isDefault: false,
    returnType: 'NUMBER',
    isDeontic: false,
    parameters: {
      type: 'object' as const,
      properties,
      required: [],
    } as unknown as FunctionParameters,
  })
  const remote = (name: string, properties: Record<string, unknown>) => ({
    name,
    returnType: 'NUMBER',
    parameters: rule(name, properties).parameters,
  })

  it('treats a null default (the usual value NOTHING) as a default', () => {
    const num = { type: 'number', enum: [], description: '' }
    expect(
      detectDefaultChanges(
        [rule('f', { x: { ...num, default: 4 } })],
        [remote('f', { x: { ...num, default: null } })]
      )
    ).toEqual([
      { kind: 'default-changed', function: 'f', input: 'x', old: null, new: 4 },
    ])
    expect(
      detectDefaultChanges(
        [rule('f', { x: { ...num, default: null } })],
        [remote('f', { x: { ...num, default: null } })]
      )
    ).toEqual([])
  })

  it('compares a default only when both sides carry one', () => {
    const num = { type: 'number', enum: [], description: '' }
    expect(
      detectDefaultChanges(
        [rule('f', { x: { ...num, default: 1 } })],
        [remote('f', { x: num })]
      )
    ).toEqual([])
    expect(
      detectDefaultChanges(
        [rule('f', { x: num })],
        [remote('f', { x: { ...num, default: 1 } })]
      )
    ).toEqual([])
  })

  it('reports a default inside a list element by a path with []', () => {
    const num = { type: 'number', enum: [], description: '' }
    const list = (d: number) => ({
      type: 'array',
      enum: [],
      description: '',
      items: {
        type: 'object',
        enum: [],
        description: '',
        properties: { n: { ...num, default: d } },
      },
    })
    expect(
      detectDefaultChanges(
        [rule('f', { xs: list(2) })],
        [remote('f', { xs: list(1) })]
      )
    ).toEqual([
      {
        kind: 'default-changed',
        function: 'f',
        input: 'xs[].n',
        old: 1,
        new: 2,
      },
    ])
  })

  it('reports each changed default once, per rule, inputs in name order', () => {
    const num = (d: number) => ({
      type: 'number',
      enum: [],
      description: '',
      default: d,
    })
    expect(
      detectDefaultChanges(
        [rule('f', { b: num(2), a: num(2) }), rule('g', { z: num(9) })],
        [remote('f', { b: num(1), a: num(1) }), remote('g', { z: num(9) })]
      ).map((n) => `${n.function}.${n.input}`)
    ).toEqual(['f.a', 'f.b'])
  })

  it('ignores a rule that is new, or that was removed', () => {
    const num = { type: 'number', enum: [], description: '', default: 1 }
    expect(
      detectDefaultChanges(
        [rule('new', { x: num })],
        [remote('old', { x: num })]
      )
    ).toEqual([])
  })

  it('does not report the first deploy, when there is no deployed rule', () => {
    expect(detectDefaultChanges([rule('f', {})], [])).toEqual([])
  })
})
