import { describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import { mkdtemp, rm } from 'node:fs/promises'
import * as os from 'node:os'
import * as path from 'node:path'
import { FileConversationStore } from '../src/index.js'
import { silentLogger } from './fakes.js'

describe('FileConversationStore.setTitle', () => {
  async function storeWith(title: string) {
    const dir = await mkdtemp(path.join(os.tmpdir(), 'conv-store-'))
    const store = new FileConversationStore(dir, silentLogger, () => 'user')
    await store.appendMessages('c1', 'org', 'user', 'model', title, [])
    return { store, done: () => rm(dir, { recursive: true, force: true }) }
  }

  test('a rename replaces the title', async () => {
    const { store, done } = await storeWith('first message')
    await store.setTitle('c1', 'Lease review')
    assert.equal((await store.load('c1'))?.title, 'Lease review')
    await done()
  })

  // The automatic title arrives seconds after the first message: it
  // replaces only the title it was made for, not one the user chose.
  test('an automatic title does not overwrite a rename', async () => {
    const { store, done } = await storeWith('first message')
    await store.setTitle('c1', 'Lease review')
    await store.setTitle('c1', 'Summary of lease', {
      replacing: 'first message',
    })
    assert.equal((await store.load('c1'))?.title, 'Lease review')
    await store.setTitle('c1', 'Better', { replacing: 'Lease review' })
    assert.equal((await store.load('c1'))?.title, 'Better')
    await done()
  })
})
