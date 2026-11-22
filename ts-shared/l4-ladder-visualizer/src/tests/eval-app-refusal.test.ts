import { describe, expect, it } from 'vitest'
import type { IRExpr } from '@repo/viz-expr'
import type { LadderBackendApi } from 'jl4-client-rpc'
import { L4Connection } from '../lib/l4-connection.js'
import { Evaluator, isRefusal } from '../lib/eval/eval.js'
import { Assignment } from '../lib/eval/assignment.js'
import { isUnknownVal } from '../lib/eval/type.js'

const verDocId = { uri: 'file:///covered.l4', version: 1 }

// `covered TRUE`, a call of a rule on a known input.
const call: IRExpr = {
  $type: 'App',
  id: { id: 2 },
  fnName: { unique: 10, label: 'covered' },
  args: [{ $type: 'TrueE', id: { id: 1 }, name: { unique: 0, label: 'TRUE' } }],
  atomId: 'atom-covered',
}

// A backend whose l4/evalApp fails as the given error.
function failingWith(err: unknown): L4Connection {
  const api: LadderBackendApi = {
    sendClientRequest: async () => {
      throw err
    },
    updateViz: async () => {},
  }
  return new L4Connection(api)
}

const refusalMessage =
  'The model refuses to answer:\n  insurance is not modelled\n'

describe('a call that the language server answers with a refusal', () => {
  it('is unknown, from the error data the web editor passes on', async () => {
    const conn = failingWith({
      code: -32803,
      message: refusalMessage,
      data: { kind: 'refused', reason: 'insurance is not modelled' },
    })
    const res = await Evaluator.eval(
      conn,
      verDocId,
      call as never,
      Assignment.fromEntries([])
    )
    expect(isUnknownVal(res.result)).toBe(true)
  })

  it('is unknown, from the message alone, as VS Code relays it', async () => {
    const conn = failingWith(new Error(refusalMessage))
    const res = await Evaluator.eval(
      conn,
      verDocId,
      call as never,
      Assignment.fromEntries([])
    )
    expect(isUnknownVal(res.result)).toBe(true)
  })

  it('is still an error when the call fails for another reason', async () => {
    const conn = failingWith(new Error('Division by zero'))
    await expect(
      Evaluator.eval(conn, verDocId, call as never, Assignment.fromEntries([]))
    ).rejects.toThrow('Division by zero')
  })

  it('tells a refusal from other errors', () => {
    expect(isRefusal({ data: { kind: 'refused', reason: 'r' } })).toBe(true)
    expect(isRefusal(new Error(refusalMessage))).toBe(true)
    expect(
      isRefusal(new Error('Evaluation exceeded maximum depth limit'))
    ).toBe(false)
    expect(isRefusal(null)).toBe(false)
  })
})
