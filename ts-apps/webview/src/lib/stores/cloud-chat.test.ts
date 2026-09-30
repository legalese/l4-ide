import { describe, expect, test } from 'vitest'
import {
  adoptTurn,
  applyCloudEvent,
  mergeHistory,
  newCloudInfo,
  rollbackOffer,
  type CloudConversation,
} from './cloud-chat'

const SID = '01K6B8Z6X9Q4M2N7P3R5T8V0WA'
const SHA = 'a'.repeat(40)
const PARENT = 'b'.repeat(40)

function conv(): CloudConversation {
  return {
    turns: [],
    streaming: false,
    activeTurnId: null,
    cloud: newCloudInfo(SID),
  }
}

describe('mergeHistory', () => {
  test('merges local and cloud entries by last activity', () => {
    const entries = mergeHistory(
      [
        {
          id: 'conv-old',
          title: 'Old',
          model: 'm',
          createdAt: '2026-09-01T00:00:00Z',
          lastActiveAt: '2026-09-01T00:00:00Z',
          messageCount: 2,
        },
        {
          id: 'conv-new',
          title: 'New',
          model: 'm',
          createdAt: '2026-09-27T00:00:00Z',
          lastActiveAt: '2026-09-27T00:00:00Z',
          messageCount: 2,
        },
      ],
      [
        {
          sessionId: SID,
          title: '',
          created: Date.parse('2026-09-10T00:00:00Z'),
          lastActivity: Date.parse('2026-09-10T00:00:00Z'),
          state: 'sleeping',
        },
      ]
    )
    expect(entries.map((e) => e.id)).toEqual([
      'conv-new',
      `cloud:${SID}`,
      'conv-old',
    ])
    expect(entries[1]).toMatchObject({
      kind: 'cloud',
      title: 'Cloud session',
      state: 'sleeping',
    })
  })
})

describe('turns this webview did not start', () => {
  test('adoptTurn adds one streaming bubble per turn', () => {
    const c = conv()
    expect(adoptTurn(c, 't1')).toBe(true)
    expect(adoptTurn(c, 't1')).toBe(false)
    expect(c.turns).toHaveLength(1)
    expect(c.turns[0]).toMatchObject({
      role: 'assistant',
      turnId: 't1',
      streaming: true,
    })
    expect(c.streaming).toBe(true)
    expect(c.activeTurnId).toBe('t1')
  })

  test('user-message renders prompts from elsewhere, before their reply', () => {
    const c = conv()
    adoptTurn(c, 't1')
    applyCloudEvent(c, {
      type: 'user-message',
      turnId: 't1',
      text: 'Check clause 4',
      attachments: [
        { name: 'memo.pdf', contentType: 'application/pdf', size: 3 },
      ],
    })
    expect(c.turns.map((t) => t.role)).toEqual(['user', 'assistant'])
    expect(c.turns[0]).toMatchObject({
      content: 'Check clause 4',
      cloudTurnId: 't1',
      chips: [{ kind: 'pdf', name: 'memo.pdf' }],
    })
    // Its own prompts (and repeats) aren't duplicated; an inject into
    // the same turn is appended.
    applyCloudEvent(c, {
      type: 'user-message',
      turnId: 't1',
      text: 'Check clause 4',
      attachments: [],
    })
    applyCloudEvent(c, {
      type: 'user-message',
      turnId: 't1',
      text: 'and clause 5',
      attachments: [],
    })
    expect(c.turns.map((t) => t.content)).toEqual([
      'Check clause 4',
      '',
      'and clause 5',
    ])
  })

  test('ask-user returns the question', () => {
    expect(
      applyCloudEvent(conv(), {
        type: 'ask-user',
        conversationId: 'c',
        turnId: 't1',
        callId: 'call-2',
        question: 'Which?',
        choices: ['a', 'b'],
      })
    ).toEqual({
      question: { callId: 'call-2', question: 'Which?', choices: ['a', 'b'] },
    })
  })

  test('session state, auth and merge notices', () => {
    const c = conv()
    applyCloudEvent(c, { type: 'auth-required', reason: 'chain_expired' })
    expect(c.cloud!.authRequired).toEqual({ reason: 'chain_expired' })
    applyCloudEvent(c, { type: 'session-state', state: 'running' })
    expect(c.cloud!.state).toBe('running')
    expect(c.cloud!.authRequired).toBeNull()
    applyCloudEvent(c, { type: 'local-merge-conflict', files: ['a.l4'] })
    expect(c.cloud!.mergeConflict).toEqual(['a.l4'])
    applyCloudEvent(c, { type: 'local-merged', sha: SHA })
    expect(c.cloud!.mergeConflict).toBeNull()
  })
})

describe('rollback offers (§9.4)', () => {
  function withTurns(): CloudConversation {
    const c = conv()
    for (const id of ['t1', 't2']) {
      applyCloudEvent(c, {
        type: 'user-message',
        turnId: id,
        text: id,
        attachments: [],
      })
      adoptTurn(c, id)
      c.turns[c.turns.length - 1]!.streaming = false
      applyCloudEvent(c, {
        type: 'git-committed',
        turnId: id,
        sha: SHA,
        parent: PARENT,
      })
    }
    return c
  }

  test('latest turn: Roll back; earlier: Restore to before this turn', () => {
    const c = withTurns()
    expect(rollbackOffer(c, 3)).toEqual({
      turnId: 't2',
      label: 'Roll back',
      undoesLaterTurns: false,
      undoesLocalSync: false,
    })
    expect(rollbackOffer(c, 1)).toEqual({
      turnId: 't1',
      label: 'Restore to before this turn',
      undoesLaterTurns: true,
      undoesLocalSync: false,
    })
    // A new prompt turns "Roll back" into "Restore …".
    c.turns.push({ id: 'u3', role: 'user', content: 'next' })
    expect(rollbackOffer(c, 3)?.label).toBe('Restore to before this turn')
  })

  test('turns without changes, streaming or rolled back offer nothing', () => {
    const c = withTurns()
    c.turns[3]!.streaming = true
    expect(rollbackOffer(c, 3)).toBeNull()
    expect(rollbackOffer(c, 0)).toBeNull()
    applyCloudEvent(c, { type: 'rolled-back', turnId: 't1', sha: SHA })
    expect(c.turns[1]!.rolledBack).toBe(true)
    expect(c.turns[3]!.rolledBack).toBe(true)
    expect(rollbackOffer(c, 1)).toBeNull()
  })

  test('warns when synced local changes would be undone', () => {
    const c = withTurns()
    applyCloudEvent(c, { type: 'local-merged', sha: SHA })
    expect(rollbackOffer(c, 1)?.undoesLocalSync).toBe(true)
    expect(rollbackOffer(c, 3)?.undoesLocalSync).toBe(true)
  })
})

describe('files added mid-session (§10)', () => {
  test('files-added shows under the latest prompt and ends the progress', () => {
    const c = conv()
    c.cloud!.progress = 'adding-files'
    c.cloud!.addingFiles = 2
    applyCloudEvent(c, {
      type: 'user-message',
      turnId: 't1',
      text: 'a',
      attachments: [],
    })
    applyCloudEvent(c, {
      type: 'user-message',
      turnId: 't2',
      text: 'b',
      attachments: [],
    })
    applyCloudEvent(c, {
      type: 'files-added',
      batchId: '01K6B8Z6X9Q4M2N7P3R5T8B000',
      files: [{ path: 'data/a.l4' }, { path: 'data/b/c.md' }],
    })
    expect(c.turns[0]!.filesAdded).toBeUndefined()
    expect(c.turns[1]!.filesAdded).toEqual(['data/a.l4', 'data/b/c.md'])
    expect(c.cloud!.progress).toBeNull()
  })
})
