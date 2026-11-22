import { describe, expect, test } from 'vitest'
import { omittedBlocks, type ShownBlock } from 'jl4-client-rpc'

const activity = (
  label: string,
  message: string,
  tool = 'search_l4_docs',
  status: 'running' | 'done' | 'error' = 'done'
): ShownBlock => ({
  kind: 'tool-activity',
  activity: { tool, status, label, message },
})

const LEGALESING = activity('Legalesing...', 'Legalesing...')
const blank: ShownBlock = { kind: 'text', text: '\n\n' }
const words: ShownBlock = { kind: 'text', text: 'Looking at that.' }
const thinking: ShownBlock = { kind: 'thinking', text: 'Hmm.' }
const webSearch: ShownBlock = {
  kind: 'tool-activity',
  activity: { tool: 'web_search', status: 'done', message: '5 sources' },
}
const toolCall: ShownBlock = { kind: 'tool-call' }

/** Indices the chat does show. */
function shown(blocks: ShownBlock[], showReasoning = false): number[] {
  const omitted = omittedBlocks(blocks, showReasoning)
  return blocks.map((_, i) => i).filter((i) => !omitted.has(i))
}

describe('the blocks the chat leaves out', () => {
  test('an activity row whose separators show nothing stays one row', () => {
    expect(
      shown([
        LEGALESING,
        blank,
        LEGALESING,
        thinking,
        LEGALESING,
        webSearch,
        LEGALESING,
      ])
    ).toEqual([0])
  })

  test('visible reasoning parts two rows', () => {
    expect(shown([LEGALESING, thinking, LEGALESING], true)).toEqual([0, 1, 2])
  })

  test('words or a tool call part two rows', () => {
    expect(shown([LEGALESING, words, LEGALESING])).toEqual([0, 1, 2])
    expect(shown([LEGALESING, toolCall, LEGALESING])).toEqual([0, 1, 2])
  })

  test('rows compare by what they show, not by their tool', () => {
    expect(
      shown([
        activity('Legalesing...', 'Legalesing...', 'search_l4_docs'),
        activity('Legalesing...', 'Legalesing...', 'another_tool'),
      ])
    ).toEqual([0])
    expect(
      shown([
        activity('L4 Deployments', 'first', 'same_tool'),
        activity('L4 Deployments', 'second', 'same_tool'),
      ])
    ).toEqual([0, 1])
  })

  test('a message equal to its label shows the same as no message', () => {
    expect(
      shown([
        activity('Legalesing...', 'Legalesing...'),
        activity('Legalesing...', ''),
      ])
    ).toEqual([0])
  })

  test('a running row and a finished one show the same', () => {
    expect(
      shown([
        activity('Legalesing...', 'Legalesing...', 'a', 'done'),
        activity('Legalesing...', 'Legalesing...', 'a', 'running'),
      ])
    ).toEqual([0])
  })

  test('a failed row shows differently, and so does the next one', () => {
    expect(
      shown([
        LEGALESING,
        activity('Legalesing...', 'Legalesing...', 'a', 'error'),
        LEGALESING,
      ])
    ).toEqual([0, 1, 2])
  })

  test('rule cards are never left out', () => {
    const rule: ShownBlock = {
      kind: 'tool-activity',
      activity: {
        tool: 'evaluate_rule',
        status: 'done',
        label: 'L4 Rule',
        message: 'rule "x"',
        ruleKey: 'evaluate_rule::x',
      },
    }
    expect(shown([rule, rule])).toEqual([0, 1])
  })

  test('blank text shows nothing, words do', () => {
    expect(shown([blank, words])).toEqual([1])
  })
})
