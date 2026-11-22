import { describe, expect, test } from 'vitest'
import { omittedBlocks } from 'jl4-client-rpc'
import type { Messenger } from 'vscode-messenger-webview'
import { createAiChatStore } from './ai-chat.svelte'

const CONV = 'conv1'

/** A store with a local turn streaming in {@link CONV}. */
async function streamingTurn() {
  const sent: Array<{ method: string; params: unknown }> = []
  const record = (type: { method: string }, _to: unknown, params: unknown) => {
    sent.push({ method: type.method, params })
  }
  const messenger = {
    sendNotification: record,
    sendRequest: async (
      type: { method: string },
      to: unknown,
      params: unknown
    ) => {
      record(type, to, params)
      return { ok: true, items: [] }
    },
  } as unknown as Messenger
  const store = createAiChatStore(() => messenger)
  store.onAuthStatus({ signedIn: true })
  await store.send('What does rules.l4 say?')
  const start = sent.find((s) => s.method === 'aiChatStart')
  const { turnId } = start?.params as { turnId: string }
  store.onStarted({ conversationId: CONV, turnId, model: 'm' })
  return store
}

type Store = Awaited<ReturnType<typeof streamingTurn>>

function legalesing(store: Store, status: 'running' | 'done' | 'error') {
  store.onToolActivity({
    conversationId: CONV,
    tool: 'search_l4_docs',
    status,
    label: 'Legalesing...',
    message: 'Legalesing...',
  })
}

function blocks(store: Store) {
  const turn = store.current?.turns.at(-1)
  return turn?.role === 'assistant' ? (turn.blocks ?? []) : []
}

function activityStatuses(store: Store) {
  return blocks(store).flatMap((b) =>
    b.kind === 'tool-activity' ? [b.activity.status] : []
  )
}

describe('a local conversation in the chat store', () => {
  test('takes its generated title while the turn streams', async () => {
    const store = await streamingTurn()
    expect(store.currentTitle).toBe('New conversation')

    store.onTitle({ conversationId: CONV, title: 'A short title' })

    expect(store.currentTitle).toBe('A short title')
  })

  test('keeps a name the user gave it meanwhile', async () => {
    const store = await streamingTurn()
    await store.renameConversation(CONV, 'My own name')

    store.onTitle({ conversationId: CONV, title: 'A short title' })

    expect(store.currentTitle).toBe('My own name')
  })

  test('shows one row for doc searches with only blanks between', async () => {
    const store = await streamingTurn()
    for (let round = 0; round < 3; round++) {
      legalesing(store, 'running')
      legalesing(store, 'done')
      store.onThinkingDelta({ conversationId: CONV, text: 'Hmm.' })
      store.onTextDelta({ conversationId: CONV, text: '\n\n' })
    }

    const all = blocks(store)
    const omitted = omittedBlocks(all, false)
    const rows = all.filter(
      (b, i) => !omitted.has(i) && b.kind === 'tool-activity'
    )
    expect(rows).toHaveLength(1)
    expect(all.filter((b) => b.kind === 'text')).toHaveLength(3)
  })

  test('merges one call from running to done', async () => {
    const store = await streamingTurn()
    legalesing(store, 'running')
    legalesing(store, 'done')

    expect(activityStatuses(store)).toEqual(['done'])
  })

  test('keeps a failed row when the next attempt starts', async () => {
    const store = await streamingTurn()
    legalesing(store, 'running')
    legalesing(store, 'error')
    legalesing(store, 'running')

    expect(activityStatuses(store)).toEqual(['error', 'running'])
  })
})
