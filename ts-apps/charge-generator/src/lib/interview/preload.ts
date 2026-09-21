import type { CaseSnapshot } from '$lib/case/casefile.svelte'

/**
 * A preloaded sample conversation (Meng, 2026-09-17): the demo can be run
 * without the model. When the officer's submitted text matches a preload's
 * `prompt` EXACTLY, the interview replays the canned transcript behind a
 * fourth-wall-breaking "… some moments later …" spinner, and the case file is
 * set to the canned result. Anything else goes to the live route.
 */
export interface Preload {
  readonly id: string
  readonly title: string
  /** The reported case this replays, for the caption. */
  readonly citation: string
  /** The exact text the widget puts in the composer. */
  readonly prompt: string
  /** What the assistant "says", streamed in as if live. */
  readonly reply: string
  /** The tool calls the live route would have made, shown as rows. */
  readonly tools: readonly { name: string; args: unknown; result?: unknown }[]
  /** The resulting case file. */
  readonly result: CaseSnapshot
}

const normalise = (s: string): string => s.replace(/\s+/g, ' ').trim()

export function matchPreload(
  text: string,
  preloads: readonly Preload[]
): Preload | undefined {
  const t = normalise(text)
  return preloads.find((p) => normalise(p.prompt) === t)
}
