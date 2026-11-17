import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import type {
  ExportedFunctionInfo,
  FunctionParameters,
  RemoteFunctionSchema,
} from 'jl4-client-rpc'
import { changeToPlainText, detectBreakingChanges } from './deploy-compat'

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
