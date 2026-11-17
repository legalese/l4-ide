import { readFileSync } from 'node:fs'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type {
  ExportedFunctionInfo,
  FunctionParameters,
  RemoteFunctionSchema,
} from 'jl4-client-rpc'
import {
  changeToPlainText,
  detectBreakingChanges,
  detectDefaultChanges,
  formatNoticeValue,
  clearReportFor,
  noticeEnum,
  noticeSummary,
  normalizeNotices,
  reportAfterDeploy,
  reviewDeploy,
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
  it('reads the nine shared cases', () => {
    expect(sharedCases).toHaveLength(9)
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

  it('treats a null default (the default NOTHING) as a default', () => {
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

describe('reviewDeploy: what the deploy review does with each shared case', () => {
  const expectedStep: Record<string, string> = {
    'default changed 0 to 1': 'default-review',
    'unchanged default': 'deploy',
    'default added (input becomes optional): compatible, no notice': 'deploy',
    'default removed (input becomes required): breaking by the existing rule, no notice':
      'breaking-warning',
    'old side carries no default key (cached metadata from an older service): unknown, no notice':
      'deploy',
    'record field default changed, reported by its path': 'default-review',
    'enum default changed (a constructor name)': 'default-review',
    'a default change and an unrelated breaking change in one upload: the default is reported, the break still blocks':
      'breaking-warning',
    'input retyped (number to string): breaking by the existing rule, its default is not compared':
      'breaking-warning',
  }

  for (const c of sharedCases) {
    it(c.name, () => {
      const review = reviewDeploy([localFn(c)], [remoteFn(c)])
      expect(review.step).toBe(expectedStep[c.name])
      expect(review.breaking.map(changeToPlainText)).toEqual(c.expect.breaking)
      expect(review.notices).toEqual(c.expect.notices)
    })
  }

  it('a changed default alone is never a breaking-changes prompt', () => {
    const c = sharedCases[0]!
    const review = reviewDeploy([localFn(c)], [remoteFn(c)])
    expect(review.breaking).toEqual([])
    expect(review.step).not.toBe('breaking-warning')
  })

  it('goes straight ahead on a first deploy, when no deployment exists', () => {
    const c = sharedCases[0]!
    expect(reviewDeploy([localFn(c)], null)).toEqual({
      step: 'deploy',
      breaking: [],
      notices: [],
    })
  })
})

describe('formatNoticeValue', () => {
  it('spells a value as the card spells a default', () => {
    expect(formatNoticeValue(0)).toBe('0')
    expect(formatNoticeValue(false)).toBe('false')
    expect(formatNoticeValue('Red')).toBe('"Red"')
    expect(formatNoticeValue(null)).toBe('nothing')
  })
})

describe('formatNoticeValue and an enumerated input', () => {
  it('spells a constructor bare when the input is an enumeration', () => {
    expect(formatNoticeValue('Green', ['Green', 'Red'])).toBe('Green')
  })

  it('still quotes text for an input that is not an enumeration', () => {
    expect(formatNoticeValue('Green', [])).toBe('"Green"')
    expect(formatNoticeValue('Green', undefined)).toBe('"Green"')
  })

  it('leaves numbers, booleans and nothing as they are', () => {
    expect(formatNoticeValue(3, ['A'])).toBe('3')
    expect(formatNoticeValue(null, ['A'])).toBe('nothing')
  })
})

describe('noticeEnum: the allowed values of the input a notice is about', () => {
  const schemas = [
    {
      name: 'pick colour',
      parameters: {
        properties: {
          c: { type: 'string', enum: ['Green', 'Red'] },
          cfg: {
            type: 'object',
            properties: { shade: { type: 'string', enum: ['Dark', 'Light'] } },
          },
          xs: {
            type: 'array',
            items: {
              type: 'object',
              properties: { tone: { type: 'string', enum: ['Hi', 'Lo'] } },
            },
          },
          n: { type: 'number' },
        },
      },
    },
  ]
  const at = (input: string, fn = 'pick colour') => ({
    kind: 'default-changed' as const,
    function: fn,
    input,
    old: 'x',
    new: 'y',
  })

  it('finds a rule input, a record field, and a field of a list element', () => {
    expect(noticeEnum(schemas, at('c'))).toEqual(['Green', 'Red'])
    expect(noticeEnum(schemas, at('cfg.shade'))).toEqual(['Dark', 'Light'])
    expect(noticeEnum(schemas, at('xs[].tone'))).toEqual(['Hi', 'Lo'])
  })

  it('finds nothing for an input that is not an enumeration, or is not there', () => {
    expect(noticeEnum(schemas, at('n'))).toBeUndefined()
    expect(noticeEnum(schemas, at('missing'))).toBeUndefined()
    expect(noticeEnum(schemas, at('c', 'other rule'))).toBeUndefined()
    expect(noticeEnum([], at('c'))).toBeUndefined()
  })

  it('does not read an inherited name as an input', () => {
    expect(noticeEnum(schemas, at('toString'))).toBeUndefined()
  })
})

describe('noticeSummary', () => {
  const n = (input: string) => ({
    kind: 'default-changed' as const,
    function: 'f',
    input,
    old: 0,
    new: 1,
  })
  it('counts the changes in words', () => {
    expect(noticeSummary([])).toBe('')
    expect(noticeSummary([n('a')])).toBe('1 default changed')
    expect(noticeSummary([n('a'), n('b')])).toBe('2 defaults changed')
  })

  it('says how many were reported before the deploy when the service did not report them', () => {
    expect(noticeSummary([n('a')], 'review')).toBe(
      '1 default change was reported before the deploy'
    )
    expect(noticeSummary([n('a'), n('b')], 'review')).toBe(
      '2 default changes were reported before the deploy'
    )
    expect(noticeSummary([], 'review')).toBe('')
  })
})

describe('normalizeNotices (the job result is read, not trusted)', () => {
  const good = {
    kind: 'default-changed',
    function: 'the smaller of',
    input: 'b',
    old: 0,
    new: 1,
  }

  it('keeps well-formed notices, including a null value', () => {
    expect(normalizeNotices([good, { ...good, old: null }])).toEqual([
      good,
      { ...good, old: null },
    ])
  })

  it('drops anything else, and returns [] for a missing or odd field', () => {
    expect(normalizeNotices(undefined)).toEqual([])
    expect(normalizeNotices('nope')).toEqual([])
    expect(normalizeNotices({})).toEqual([])
    expect(
      normalizeNotices([
        good,
        null,
        42,
        { ...good, kind: 'something-else' },
        { ...good, function: 7 },
        { kind: 'default-changed', function: 'f' },
      ])
    ).toEqual([good])
  })
})

describe('a retyped node: its default is not compared (as the service skips it)', () => {
  const rule = (properties: Record<string, unknown>) => ({
    name: 'f',
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
  const remote = (properties: Record<string, unknown>) => ({
    name: 'f',
    returnType: 'NUMBER',
    parameters: rule(properties).parameters,
  })

  it('reports no notice for an input whose type changed, and the break', () => {
    const local = [rule({ b: { type: 'string', default: '0' } })]
    const deployed = [remote({ b: { type: 'number', default: 0 } })]
    expect(detectDefaultChanges(local, deployed)).toEqual([])
    expect(
      detectBreakingChanges(local, deployed).map(changeToPlainText)
    ).toEqual(['f parameter b type changed from number to string'])
  })

  it('skips the fields under a retyped input too', () => {
    const local = [
      rule({
        x: {
          type: 'string',
          properties: { y: { type: 'number', default: 2 } },
        },
      }),
    ]
    const deployed = [
      remote({
        x: {
          type: 'object',
          properties: { y: { type: 'number', default: 1 } },
        },
      }),
    ]
    expect(detectDefaultChanges(local, deployed)).toEqual([])
  })

  it('still compares the fields of an input whose type did not change', () => {
    const local = [
      rule({
        x: {
          type: 'object',
          properties: { y: { type: 'number', default: 2 } },
        },
      }),
    ]
    const deployed = [
      remote({
        x: {
          type: 'object',
          properties: { y: { type: 'number', default: 1 } },
        },
      }),
    ]
    expect(detectDefaultChanges(local, deployed).map((n) => n.input)).toEqual([
      'x.y',
    ])
  })
})

describe('reviewDeploy: a failure in the default check cannot hide the breaking list', () => {
  const rule = (properties: Record<string, unknown>) => ({
    name: 'f',
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
  const remote = (properties: Record<string, unknown>) => ({
    name: 'f',
    returnType: 'NUMBER',
    parameters: rule(properties).parameters,
  })
  const boom = () => {
    throw new TypeError('boom')
  }
  // The failure is logged (and tested to be, below); keep the run quiet.
  beforeEach(() => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
  })
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('keeps the breaking list when the default check throws', () => {
    const review = reviewDeploy(
      [rule({ b: { type: 'string' } })],
      [remote({ b: { type: 'number' } })],
      boom
    )
    expect(review.step).toBe('breaking-warning')
    expect(review.breaking.map(changeToPlainText)).toEqual([
      'f parameter b type changed from number to string',
    ])
    expect(review.notices).toEqual([])
  })

  it('goes on to the deploy, with no notices, when it throws and nothing breaks', () => {
    const review = reviewDeploy([rule({})], [remote({})], boom)
    expect(review).toEqual({ step: 'deploy', breaking: [], notices: [] })
  })

  it('does not throw on a null property node under a retyped input', () => {
    const local = [rule({ x: { type: 'string', properties: { y: {} } } })]
    const deployed = [
      remote({ x: { type: 'number', properties: { y: null } } }),
    ]
    const review = reviewDeploy(local, deployed)
    expect(review.step).toBe('breaking-warning')
    expect(review.breaking.map(changeToPlainText)).toEqual([
      'f parameter x type changed from number to string',
    ])
  })

  it('does not throw in the default check on a null node under an unchanged type', () => {
    const local = [
      rule({ x: { type: 'object', properties: { y: { default: 1 } } } }),
    ]
    const deployed = [
      remote({ x: { type: 'object', properties: { y: null } } }),
    ]
    expect(detectDefaultChanges(local, deployed)).toEqual([])
  })
})

describe('an input named like something every object has', () => {
  const rule = (properties: Record<string, unknown>) => ({
    name: 'f',
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
  const remote = (properties: Record<string, unknown>) => ({
    name: 'f',
    returnType: 'NUMBER',
    parameters: rule(properties).parameters,
  })

  for (const name of ['toString', 'constructor', 'valueOf', 'hasOwnProperty']) {
    it(`reports a removed input named ${name}`, () => {
      expect(
        detectBreakingChanges(
          [rule({})],
          [remote({ [name]: { type: 'number' } })]
        ).map(changeToPlainText)
      ).toEqual([`f parameter ${name} removed`])
    })

    it(`does not read ${name} as an input the deployed version already had`, () => {
      // A new input named like that is new, not changed: no break, and no default compared.
      const local = [rule({ [name]: { type: 'number', default: 1 } })]
      expect(detectBreakingChanges(local, [remote({})])).toEqual([])
      expect(detectDefaultChanges(local, [remote({})])).toEqual([])
    })

    it(`compares the default of an input named ${name}`, () => {
      const local = [rule({ [name]: { type: 'number', default: 1 } })]
      const deployed = [remote({ [name]: { type: 'number', default: 0 } })]
      expect(detectDefaultChanges(local, deployed).map((n) => n.input)).toEqual(
        [name]
      )
    })
  }
})

describe('a failing default check is logged, names the rule, and loses nothing else', () => {
  const ok = (name: string, d: number) => ({
    name,
    description: '',
    isDefault: false,
    returnType: 'NUMBER',
    isDeontic: false,
    parameters: {
      type: 'object' as const,
      properties: { b: { type: 'number', default: d } },
      required: [],
    } as unknown as FunctionParameters,
  })
  const deployedOk = (name: string, d: number) => ({
    name,
    returnType: 'NUMBER',
    parameters: ok(name, d).parameters,
  })
  // A rule whose schema cannot be read: reading `properties` throws.
  const broken = (name: string) => ({
    ...ok(name, 1),
    parameters: {
      type: 'object',
      get properties(): never {
        throw new TypeError('cannot read properties')
      },
      required: [],
    } as unknown as FunctionParameters,
  })

  it('logs the failure naming the rule, and still reports the other rules', () => {
    const logged = vi.spyOn(console, 'error').mockImplementation(() => {})
    try {
      const notices = detectDefaultChanges(
        [broken('bad rule'), ok('good rule', 2)],
        [deployedOk('bad rule', 0), deployedOk('good rule', 1)]
      )
      expect(notices.map((n) => n.function)).toEqual(['good rule'])
      expect(logged).toHaveBeenCalledTimes(1)
      expect(String(logged.mock.calls[0]![0])).toContain('bad rule')
    } finally {
      logged.mockRestore()
    }
  })

  it('logs when the whole check fails, and the review keeps its breaking list', () => {
    const logged = vi.spyOn(console, 'error').mockImplementation(() => {})
    try {
      const review = reviewDeploy([ok('f', 1)], [deployedOk('g', 0)], () => {
        throw new Error('boom')
      })
      expect(review.breaking.map(changeToPlainText)).toEqual(['rule g removed'])
      expect(review.notices).toEqual([])
      expect(logged).toHaveBeenCalledTimes(1)
      expect(String(logged.mock.calls[0]![0])).toContain('default check')
    } finally {
      logged.mockRestore()
    }
  })
})

describe('reportAfterDeploy: what is said once the job has finished', () => {
  const notice = (input: string) => ({
    kind: 'default-changed' as const,
    function: 'f',
    input,
    old: 0,
    new: 1,
  })
  const reviewed = [notice('b')]

  it('reports what the service reported, for an applied job', () => {
    expect(
      reportAfterDeploy({ jobNotices: [notice('c')], reviewNotices: reviewed })
    ).toEqual({ source: 'service', notices: [notice('c')] })
  })

  it('reports what the service reported for a rejected job too', () => {
    // The service puts `notices` on a rejection as well; the caller passes the
    // job's field whatever the outcome was.
    expect(
      reportAfterDeploy({ jobNotices: [notice('c')], reviewNotices: [] })
    ).toEqual({ source: 'service', notices: [notice('c')] })
  })

  it('says nothing when the service reported an empty list', () => {
    expect(
      reportAfterDeploy({ jobNotices: [], reviewNotices: reviewed })
    ).toBeNull()
  })

  it('falls back to the list the review held when the job has no `notices`, and says so', () => {
    expect(
      reportAfterDeploy({ jobNotices: undefined, reviewNotices: reviewed })
    ).toEqual({ source: 'review', notices: reviewed })
  })

  it('says nothing when there is nothing reported and nothing reviewed', () => {
    expect(
      reportAfterDeploy({ jobNotices: undefined, reviewNotices: [] })
    ).toBeNull()
  })

  it('reads a malformed `notices` as absent, not as an empty report', () => {
    expect(
      reportAfterDeploy({ jobNotices: 'nope', reviewNotices: reviewed })
    ).toEqual({ source: 'review', notices: reviewed })
  })
})

describe('clearReportFor: an undeployed deployment leaves no report behind', () => {
  const report = {
    deploymentId: 'smaller',
    outcome: 'applied' as const,
    source: 'service' as const,
    notices: [],
    schemas: [],
  }

  it('clears the report of the deployment that was removed', () => {
    expect(clearReportFor(report, 'smaller')).toBeNull()
  })

  it('keeps the report of another deployment', () => {
    expect(clearReportFor(report, 'other')).toBe(report)
  })

  it('has nothing to clear when there is no report', () => {
    expect(clearReportFor(null, 'smaller')).toBeNull()
  })
})
