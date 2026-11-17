/** The parts of an assistant message's blocks that decide what the chat
 *  shows for them. */
export type ShownBlock =
  | { kind: 'text' | 'thinking'; text: string }
  | { kind: 'tool-call' }
  | {
      kind: 'tool-activity'
      activity: {
        tool: string
        status: 'running' | 'done' | 'error'
        label?: string
        message: string
        /** Set on L4-rule activities, which render as a tool-call card. */
        ruleKey?: string
      }
    }

/**
 * A turn's web search citations: `earlier` with `later`'s added, each URL
 * once, in the order first seen. A turn that pauses for client tools gets
 * one `web_search` activity per response, each with only that response's
 * citations, so a new list adds to the old one instead of replacing it.
 */
export function mergeSources<S extends { url: string }>(
  earlier: readonly S[] | undefined,
  later: readonly S[] | undefined
): S[] | undefined {
  if (!earlier && !later) return undefined
  const byUrl = new Map<string, S>()
  for (const s of [...(earlier ?? []), ...(later ?? [])]) {
    if (!byUrl.has(s.url)) byUrl.set(s.url, s)
  }
  return [...byUrl.values()]
}

/** A `web_search` activity's message for `n` citations, as the AI service
 *  words it. */
export function sourcesLabel(n: number): string {
  return n === 1 ? '1 source' : `${n} sources`
}

/** What a plain activity row puts on screen: a bold label, the message
 *  when it says something else, and whether its dot is red. */
export function activityRow(activity: {
  status: 'running' | 'done' | 'error'
  label?: string
  message: string
}): { label: string; detail: string; failed: boolean } {
  const label = activity.label ?? 'Activity'
  return {
    label,
    detail: activity.message === label ? '' : activity.message,
    failed: activity.status === 'error',
  }
}

function showsNothing(block: ShownBlock, showReasoning: boolean): boolean {
  switch (block.kind) {
    case 'text':
      return !block.text.trim()
    case 'thinking':
      return !showReasoning
    case 'tool-activity':
      // Web searches are listed under "Sources" in the turn's review
      // card. A row here would split the text around it, breaking any
      // markdown element it lands in, such as a table.
      return !block.activity.ruleKey && block.activity.tool === 'web_search'
    default:
      return false
  }
}

/**
 * The blocks of an assistant message that the chat leaves out, by
 * index: those that show nothing, and activity rows that would show
 * exactly what the row above them on screen shows. Going by what's on
 * screen is what makes it hold whatever sits between two rows, and
 * makes rows come back when something visible parts them.
 *
 * Tool-call and rule cards are never left out: each has its own
 * arguments and result behind it.
 */
export function omittedBlocks(
  blocks: readonly ShownBlock[],
  showReasoning: boolean
): ReadonlySet<number> {
  const omitted = new Set<number>()
  let rowAbove: string | undefined
  blocks.forEach((block, i) => {
    if (showsNothing(block, showReasoning)) {
      omitted.add(i)
      return
    }
    const row =
      block.kind === 'tool-activity' && !block.activity.ruleKey
        ? JSON.stringify(activityRow(block.activity))
        : undefined
    if (row !== undefined && row === rowAbove) omitted.add(i)
    rowAbove = row
  })
  return omitted
}
