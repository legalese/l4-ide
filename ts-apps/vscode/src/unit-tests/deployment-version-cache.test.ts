import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import { DeploymentVersionCache } from '../ai/deployment-version-cache.js'

/** A cache over a fake service that counts its status requests, with a
 *  clock the test moves. */
function setup(versions: Record<string, string> = { acme: 'v1' }) {
  let clock = 0
  const asked: string[] = []
  const cache = new DeploymentVersionCache(
    async (id) => {
      asked.push(id)
      const v = versions[id]
      if (v === undefined) throw new Error(`no deployment ${id}`)
      return v
    },
    60_000,
    () => clock
  )
  return {
    cache,
    asked,
    versions,
    advance: (ms: number) => {
      clock += ms
    },
  }
}

describe('DeploymentVersionCache', () => {
  test('rows for one deployment share one check per minute', async () => {
    const s = setup()
    assert.equal(await s.cache.version('acme'), 'v1')
    s.advance(59_000)
    assert.equal(await s.cache.version('acme'), 'v1')
    assert.deepEqual(s.asked, ['acme'])
  })

  test('checks again after a minute, and sees a redeploy', async () => {
    const s = setup()
    await s.cache.version('acme')
    s.versions.acme = 'v2'
    s.advance(60_000)
    assert.equal(await s.cache.version('acme'), 'v2')
    assert.deepEqual(s.asked, ['acme', 'acme'])
  })

  test('concurrent rows share one request', async () => {
    const s = setup()
    const all = await Promise.all([
      s.cache.version('acme'),
      s.cache.version('acme'),
      s.cache.version('acme'),
    ])
    assert.deepEqual(all, ['v1', 'v1', 'v1'])
    assert.deepEqual(s.asked, ['acme'])
  })

  test('each deployment is checked on its own', async () => {
    const s = setup({ acme: 'v1', other: 'v9' })
    assert.equal(await s.cache.version('acme'), 'v1')
    assert.equal(await s.cache.version('other'), 'v9')
    assert.deepEqual(s.asked, ['acme', 'other'])
  })

  test('a failed check is not remembered', async () => {
    const s = setup({})
    await assert.rejects(s.cache.version('acme'))
    s.versions.acme = 'v1'
    assert.equal(await s.cache.version('acme'), 'v1')
    assert.deepEqual(s.asked, ['acme', 'acme'])
  })
})
