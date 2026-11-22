import { describe, expect, test } from 'vitest'
import {
  RenderMetaLoader,
  renderMetaQuery,
  type RenderMetaQuery,
} from 'jl4-client-rpc'

describe('renderMetaQuery', () => {
  test("a rule's own tool asks by its name", () => {
    expect(renderMetaQuery({ name: 'l4-rules__tax' })).toEqual({
      toolName: 'l4-rules__tax',
    })
  })

  test('a generic evaluate asks only once it names its rule', () => {
    expect(renderMetaQuery({ name: 'l4-rules__evaluate' })).toBeNull()
    expect(
      renderMetaQuery({ name: 'l4-rules__evaluate', ruleFnName: 'tax' })
    ).toBeNull()
    expect(
      renderMetaQuery({
        name: 'l4-rules__evaluate',
        deploymentId: 'ceo-award-2025',
        ruleFnName: 'Evaluate Award State',
      })
    ).toEqual({
      toolName: 'l4-rules__evaluate',
      deploymentId: 'ceo-award-2025',
      fnName: 'Evaluate Award State',
    })
  })
})

/** A host whose answers the test releases one at a time. */
function host() {
  const asked: RenderMetaQuery[] = []
  const pending: Array<(meta: string | null) => void> = []
  return {
    asked,
    fetch: (q: RenderMetaQuery) => {
      asked.push(q)
      return new Promise<string | null>((resolve) => pending.push(resolve))
    },
    answer: async (meta: string | null) => {
      pending.shift()!(meta)
      // Let the loader see the answer and, if it asks again, record it.
      for (let i = 0; i < 5; i++) await Promise.resolve()
    },
  }
}

describe('RenderMetaLoader', () => {
  test('asks again when the call names its rule while a request is out', async () => {
    // The race behind JSON in an evaluate row: the row asks before the
    // call names its rule, the call finishes meanwhile, and the answer
    // comes back without a schema.
    const call: { name: string; deploymentId?: string; ruleFnName?: string } = {
      name: 'l4-rules__tax',
    }
    const h = host()
    let loaded: string | null = null
    const loader = new RenderMetaLoader<string>({
      query: () => renderMetaQuery(call),
      fetch: h.fetch,
      onLoaded: (m) => (loaded = m),
    })

    void loader.load()
    call.deploymentId = 'acme'
    call.ruleFnName = 'tax'
    void loader.load() // the row's effect, while the first request is out
    expect(h.asked).toHaveLength(1)

    await h.answer(null)
    expect(h.asked).toEqual([
      { toolName: 'l4-rules__tax' },
      { toolName: 'l4-rules__tax', deploymentId: 'acme', fnName: 'tax' },
    ])
    await h.answer('schema')
    expect(loaded).toBe('schema')
  })

  test('a generic evaluate row waits for its rule, then loads', async () => {
    const call: { name: string; deploymentId?: string; ruleFnName?: string } = {
      name: 'l4-rules__evaluate',
    }
    const h = host()
    let loaded: string | null = null
    const loader = new RenderMetaLoader<string>({
      query: () => renderMetaQuery(call),
      fetch: h.fetch,
      onLoaded: (m) => (loaded = m),
    })

    await loader.load()
    expect(h.asked).toHaveLength(0)
    call.deploymentId = 'ceo-award-2025'
    call.ruleFnName = 'Evaluate Award State'
    void loader.load()
    await h.answer('schema')
    expect(loaded).toBe('schema')
    expect(h.asked).toHaveLength(1)
  })

  test('an answer without a schema for an unchanged query waits for the next load', async () => {
    const h = host()
    const loader = new RenderMetaLoader<string>({
      query: () => ({ toolName: 'l4-rules__tax' }),
      fetch: h.fetch,
      onLoaded: () => undefined,
    })
    void loader.load()
    await h.answer(null)
    expect(h.asked).toHaveLength(1)
    void loader.load()
    expect(h.asked).toHaveLength(2)
  })

  test('stops asking once it has the schema', async () => {
    const h = host()
    const loader = new RenderMetaLoader<string>({
      query: () => ({ toolName: 'l4-rules__tax' }),
      fetch: h.fetch,
      onLoaded: () => undefined,
    })
    void loader.load()
    await h.answer('schema')
    await loader.load()
    expect(h.asked).toHaveLength(1)
  })
})
