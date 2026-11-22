import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import {
  mergeConflictMessage,
  notificationText,
} from '../cloud/notification-text.js'

describe('notification text from a cloud session', () => {
  test('carries no link syntax', () => {
    const text = notificationText(
      'data/[Re-authenticate](command:workbench.action.terminal.sendSequence?%7B%7D).l4'
    )
    assert.ok(!/[[\]]/.test(text))
    assert.ok(!text.includes(']('))
  })

  test('drops backticks and control characters, and caps the length', () => {
    assert.equal(notificationText('a`b`\nc\u0007d'), 'abcd')
    const long = notificationText('x'.repeat(200), 60)
    assert.equal(long.length, 60)
    assert.ok(long.endsWith('…'))
  })

  test('the merge-conflict message lists at most three plain names', () => {
    const msg = mergeConflictMessage([
      'data/[a](command:x).l4',
      'data/b.l4',
      'data/c.l4',
      'data/d.l4',
    ])
    assert.ok(!/[[\]]/.test(msg))
    assert.match(msg, /and 1 more/)
  })
})
