import { describe, expect, test } from 'vitest'
import type { ExportedFunctionInfo, RemoteFunctionSchema } from 'jl4-client-rpc'
import { detectBreakingChanges, type SchemaNode } from './breaking-changes'

// The cases of jl4-service's CompatibilitySpec that the gate added for a
// oneOf, the tagged object's constructors and a self-named type's change of
// form, with schemas written as the service writes them, so that the panel
// and the gate are seen to agree (review of #779, 2026-11-20).

const prim = (type: string): SchemaNode => ({ type })
const enumP = (names: string[]): SchemaNode => ({
  type: 'string',
  enum: names,
})
const objP = (
  props: Record<string, SchemaNode>,
  required: string[]
): SchemaNode => ({ type: 'object', properties: props, required })
/** The tagged object: one key per constructor, none required. */
const taggedP = (tagged: Record<string, SchemaNode>): SchemaNode => ({
  type: 'object',
  properties: tagged,
})
/** A type with both kinds of constructor: a oneOf, with no type of its own. */
const mixedP = (
  names: string[],
  tagged: Record<string, SchemaNode>
): SchemaNode => ({ oneOf: [enumP(names), taggedP(tagged)] })

/** A function as both sides describe it, before it is cast to the two types. */
type Fn = {
  name: string
  parameters: SchemaNode
  returnType: string
  returnSchema?: SchemaNode
}

const input = (p: SchemaNode): Fn => ({
  name: 'decide',
  parameters: { type: 'object', properties: { o: p }, required: ['o'] },
  returnType: 'NUMBER',
})
const result = (p: SchemaNode): Fn => ({
  name: 'decide',
  parameters: { type: 'object', properties: {}, required: [] },
  returnType: 'Outcome',
  returnSchema: p,
})

/** The messages for a redeploy of `local` over `remote`, as plain text. */
function changes(remote: Fn, local: Fn): string[] {
  const localFn = {
    description: '',
    isDefault: false,
    isDeontic: false,
    ...local,
  } as unknown as ExportedFunctionInfo
  return detectBreakingChanges(
    [localFn],
    [remote as unknown as RemoteFunctionSchema]
  ).map((c) => c.map((s) => s.text).join(''))
}

const card = objP({ 'card fee': prim('number') }, ['card fee'])
const reason = objP({ reason: prim('string') }, ['reason'])
const court = objP({ court: prim('string') }, ['court'])
const amount = objP({ amount: prim('number') }, ['amount'])

describe('a oneOf of the names and the tagged constructors', () => {
  test('a form added to an input is not breaking', () => {
    expect(
      changes(input(enumP(['Cash'])), input(mixedP(['Cash'], { Card: card })))
    ).toEqual([])
  })
  test('a form added to a result is breaking (STOWAWAY)', () => {
    expect(
      changes(result(enumP(['Cash'])), result(mixedP(['Cash'], { Card: card })))
    ).toEqual(['decide return value may now return an object'])
    expect(
      changes(
        result(taggedP({ Card: card })),
        result(mixedP(['Cash'], { Card: card }))
      )
    ).toEqual(['decide return value may now return a string'])
  })
  test('a form removed is breaking', () => {
    const m = mixedP(['Cash'], { Card: card })
    expect(changes(input(m), input(enumP(['Cash'])))).toEqual([
      'decide parameter o no longer accepts an object',
    ])
    expect(changes(result(m), result(enumP(['Cash'])))).toEqual([
      'decide return value no longer returns an object',
    ])
  })
  test('a form on both sides is compared as any node', () => {
    expect(
      changes(
        input(mixedP(['Cash', 'Cheque'], { Card: card })),
        input(mixedP(['Cash'], { Card: card }))
      )
    ).toEqual(['decide parameter o no longer accepts Cheque'])
  })
})

describe('constructors within the tagged object', () => {
  test('a result that gains a second constructor may now return it', () => {
    expect(
      changes(
        result(taggedP({ Referred: reason })),
        result(taggedP({ Referred: reason, Appealed: court }))
      )
    ).toEqual(['decide return value may now return new values Appealed'])
  })
  test('a result that loses one is not breaking', () => {
    expect(
      changes(
        result(taggedP({ Referred: reason, Appealed: court })),
        result(taggedP({ Referred: reason }))
      )
    ).toEqual([])
  })
  test('an input that loses one no longer accepts it, and one that gains one is fine', () => {
    expect(
      changes(
        input(taggedP({ Referred: reason, Appealed: court })),
        input(taggedP({ Referred: reason }))
      )
    ).toEqual(['decide parameter o no longer accepts Appealed'])
    expect(
      changes(
        input(taggedP({ Referred: reason })),
        input(taggedP({ Referred: reason, Appealed: court }))
      )
    ).toEqual([])
  })
  test("a constructor on both sides has its fields compared as a record's", () => {
    expect(
      changes(
        result(taggedP({ Referred: reason })),
        result(taggedP({ Referred: objP({}, []) }))
      )
    ).toEqual(['decide return value Referred.reason no longer returned'])
  })
})

describe('a type whose only constructor is named like it, given a second', () => {
  const fieldsToKeyed =
    'form changed from an object of its fields (amount) to an object keyed by its constructor (Appealed, Outcome)'
  test("an input's form changed", () => {
    expect(
      changes(
        input(amount),
        input(taggedP({ Outcome: amount, Appealed: court }))
      )
    ).toEqual([`decide parameter o ${fieldsToKeyed}`])
  })
  test("a result's form changed, and the other way", () => {
    expect(
      changes(
        result(amount),
        result(taggedP({ Outcome: amount, Appealed: court }))
      )
    ).toEqual([`decide return value ${fieldsToKeyed}`])
    expect(
      changes(
        input(taggedP({ Outcome: amount, Appealed: court })),
        input(amount)
      )
    ).toEqual([
      'decide parameter o form changed from an object keyed by its constructor (Appealed, Outcome) to an object of its fields (amount)',
    ])
  })
})

describe('records are still compared by their fields', () => {
  test('a removed input field and a new optional result field', () => {
    expect(
      changes(
        input(objP({ a: prim('number'), b: prim('number') }, ['a'])),
        input(objP({ a: prim('number') }, ['a']))
      )
    ).toEqual(['decide parameter o.b removed'])
    expect(
      changes(
        result(objP({ a: prim('number') }, ['a'])),
        result(objP({ a: prim('number'), b: prim('number') }, ['a']))
      )
    ).toEqual([])
  })
})
