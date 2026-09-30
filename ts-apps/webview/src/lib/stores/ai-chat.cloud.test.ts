import { describe, expect, test } from 'vitest'
import type { Messenger } from 'vscode-messenger-webview'
import { createAiChatStore } from './ai-chat.svelte'

const SID = '01K6B8Z6X9Q4M2N7P3R5T8V0WA'
const KEY = `cloud:${SID}`

interface Sent {
  method: string
  params: unknown
}

/** A messenger that records what the store sends and answers
 *  requests from `answers` (by method). */
function fakeMessenger(answers: Record<string, (params: never) => unknown>) {
  const sent: Sent[] = []
  const m = {
    sendNotification: (
      type: { method: string },
      _to: unknown,
      params: unknown
    ) => {
      sent.push({ method: type.method, params })
    },
    sendRequest: async (
      type: { method: string },
      _to: unknown,
      params: unknown
    ) => {
      sent.push({ method: type.method, params })
      const answer = answers[type.method]
      if (!answer) throw new Error(`no answer for ${type.method}`)
      return answer(params as never)
    },
  }
  return { messenger: m as unknown as Messenger, sent }
}

const flush = () => new Promise((r) => setTimeout(r, 0))

function setup(answers: Record<string, (params: never) => unknown> = {}) {
  const { messenger, sent } = fakeMessenger({
    aiCloudSessionList: () => ({ items: [] }),
    aiCloudOpen: () => ({ ok: true, state: 'busy', title: 'Lease review' }),
    aiCloudGitStatus: () => ({ kind: 'not-cloned' }),
    aiCloudCommand: () => ({ ok: true, state: 'busy' }),
    aiConversationList: () => ({ items: [] }),
    ...answers,
  })
  const store = createAiChatStore(() => messenger)
  store.onAuthStatus({ signedIn: true })
  store.onCloudConfig({ enabled: true })
  return { store, sent }
}

describe('cloud conversations in the chat store', () => {
  test('opening replays a turn started elsewhere', async () => {
    const { store, sent } = setup()
    await store.loadConversation(KEY)
    expect(sent.some((s) => s.method === 'aiCloudOpen')).toBe(true)
    expect(store.currentId).toBe(KEY)
    expect(store.current?.title).toBe('Lease review')

    // The replayed log: a prompt from another window, then its reply.
    store.onCloudEvent({
      conversationId: KEY,
      sessionId: SID,
      replay: true,
      event: {
        type: 'user-message',
        turnId: 't1',
        text: 'Hi',
        attachments: [],
      },
    })
    store.onStarted({ conversationId: KEY, turnId: 't1', model: 'm' })
    store.onTextDelta({ conversationId: KEY, text: 'Hello' })
    store.onDone({ conversationId: KEY, finishReason: 'stop' })
    const turns = store.current!.turns
    expect(turns.map((t) => [t.role, t.content])).toEqual([
      ['user', 'Hi'],
      ['assistant', 'Hello'],
    ])
    expect(turns[1]!.streaming).toBe(false)
    expect(store.current!.streaming).toBe(false)
  })

  test('local chats also keep deltas of turns they did not create', async () => {
    const { store } = setup({
      aiConversationLoad: () => ({
        conversation: {
          id: 'conv-1',
          title: 't',
          messages: [],
          createdAt: '',
          updatedAt: '',
        },
      }),
    })
    await store.loadConversation('conv-1')
    store.onStarted({ conversationId: 'conv-1', turnId: 'x', model: 'm' })
    store.onTextDelta({ conversationId: 'conv-1', text: 'from elsewhere' })
    expect(store.current!.turns.map((t) => t.content)).toEqual([
      'from elsewhere',
    ])
  })

  test('prompts, answers and stop become cloud commands; no approvals', async () => {
    const { store, sent } = setup()
    await store.loadConversation(KEY)
    await store.send('Next step')
    const message = sent.find((s) => s.method === 'aiCloudCommand')!
    const turnId = (message.params as { command: { turnId: string } }).command
      .turnId
    expect(message.params).toEqual({
      sessionId: SID,
      command: { type: 'message', turnId, text: 'Next step' },
    })
    expect(sent.some((s) => s.method === 'aiChatStart')).toBe(false)
    // Its echo from the harness isn't shown twice.
    store.onCloudEvent({
      conversationId: KEY,
      sessionId: SID,
      replay: false,
      event: {
        type: 'user-message',
        turnId,
        text: 'Next step',
        attachments: [],
      },
    })
    expect(store.current!.turns.filter((t) => t.role === 'user')).toHaveLength(
      1
    )

    store.onCloudEvent({
      conversationId: KEY,
      sessionId: SID,
      replay: false,
      event: {
        type: 'ask-user',
        conversationId: 'c',
        turnId,
        callId: 'call-1',
        question: 'Which clause?',
      },
    })
    expect(store.pendingQuestion?.question).toBe('Which clause?')
    store.answerQuestion('4')

    // No approvals in cloud sessions: no approval bar even if a tool
    // row somehow says pending-approval.
    store.onToolCall({
      conversationId: KEY,
      callId: 'call-2',
      name: 'fs__edit_file',
      argsJson: '{}',
      status: 'pending-approval',
    })
    expect(store.pendingApproval).toBeNull()
    store.abort()
    await flush()
    const commands = sent
      .filter((s) => s.method === 'aiCloudCommand')
      .map((s) => (s.params as { command: { type: string } }).command)
    expect(commands.map((c) => c.type)).toEqual(['message', 'answer', 'abort'])
  })

  test('Run in cloud keys the conversation by its session once it exists', async () => {
    const { store, sent } = setup()
    expect(store.canRunInCloud).toBe(true)
    await store.sendCloud('Review my lease')
    const run = sent.find((s) => s.method === 'aiCloudRun')!
    const { turnId } = run.params as { turnId: string }
    expect(store.current?.cloud?.progress).toBe('uploading')
    expect(store.currentId).toBeNull()

    store.onCloudProgress({
      turnId,
      sessionId: SID,
      phase: 'uploading',
      mcpServers: ['Docs'],
    })
    expect(store.currentId).toBe(KEY)
    expect(store.current?.cloud?.mcpServers).toEqual(['Docs'])
    store.onCloudProgress({ turnId, sessionId: SID, phase: 'starting' })
    expect(store.current?.cloud?.state).toBe('starting')
    // The harness's events land on the same bubble.
    store.onStarted({ conversationId: KEY, turnId, model: 'm' })
    store.onTextDelta({ conversationId: KEY, text: 'Reading…' })
    expect(store.current!.turns.map((t) => [t.role, t.content])).toEqual([
      ['user', 'Review my lease'],
      ['assistant', 'Reading…'],
    ])
    store.onCloudProgress({ turnId, sessionId: SID, phase: 'ready' })
    expect(store.current?.cloud?.progress).toBeNull()
  })

  test('a failed start shows the reason on the reply', async () => {
    const { store, sent } = setup()
    await store.sendCloud('Big upload')
    const { turnId } = sent.find((s) => s.method === 'aiCloudRun')!.params as {
      turnId: string
    }
    store.onCloudProgress({
      turnId,
      phase: 'error',
      error: "Attachments over 10 MB can't go to a cloud session: big.pdf",
    })
    const reply = store.current!.turns[1]!
    expect(reply.error?.message).toMatch(/big\.pdf/)
    expect(store.current!.streaming).toBe(false)
  })

  test('history merges cloud sessions; rollback offers come from commits', async () => {
    const { store } = setup({
      aiCloudSessionList: () => ({
        items: [
          {
            sessionId: SID,
            title: 'Lease review',
            created: 1,
            lastActivity: Date.now(),
            state: 'sleeping',
          },
        ],
      }),
    })
    await store.refreshCloudHistory(true)
    expect(store.historyEntries.map((e) => e.id)).toEqual([KEY])
    store.onCloudConfig({ enabled: false })
    expect(store.historyEntries).toEqual([])
    store.onCloudConfig({ enabled: true })

    await store.loadConversation(KEY)
    store.onStarted({ conversationId: KEY, turnId: 't1', model: 'm' })
    store.onDone({ conversationId: KEY, finishReason: 'stop' })
    store.onCloudEvent({
      conversationId: KEY,
      sessionId: SID,
      replay: false,
      event: {
        type: 'git-committed',
        turnId: 't1',
        sha: 'a'.repeat(40),
        parent: 'b'.repeat(40),
      },
    })
    expect(store.rollbackOfferAt(0)?.label).toBe('Roll back')
  })
})
