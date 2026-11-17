import { describe, expect, it } from 'vitest'
import { render } from 'svelte/server'
import type { DefaultChangeNotice } from 'jl4-client-rpc'
import DefaultNotices from './default-notices.svelte'

const n = (
  fn: string,
  input: string,
  old: unknown,
  next: unknown
): DefaultChangeNotice => ({
  kind: 'default-changed',
  function: fn,
  input,
  old,
  new: next,
})

// The text a reader gets, without the markup.
const text = (items: DefaultChangeNotice[]) =>
  render(DefaultNotices, { props: { items } })
    .body.replace(/<!--.*?-->/g, '')
    .replace(/<\/li>/g, ' ')
    .replace(/<[^>]+>/g, '')
    .replace(/\s+/g, ' ')
    .trim()

describe('DefaultNotices', () => {
  it('lists the rule, the input, the old value and the new one', () => {
    expect(text([n('the smaller of', 'b', 0, 1)])).toBe(
      'the smaller of · b · typically 0 → 1: callers who leave b out will get different answers.'
    )
  })

  it('names a record field by its path and quotes text', () => {
    expect(
      text([
        n('run job', 'cfg.retries', 3, 5),
        n('pick colour', 'c', 'Green', 'Red'),
      ])
    ).toBe(
      'run job · cfg.retries · typically 3 → 5: callers who leave cfg.retries out will get different answers. ' +
        'pick colour · c · typically "Green" → "Red": callers who leave c out will get different answers.'
    )
  })

  it('reads NOTHING as nothing, and false and 0 as themselves', () => {
    expect(text([n('f', 'x', null, 0), n('f', 'y', false, true)])).toBe(
      'f · x · typically nothing → 0: callers who leave x out will get different answers. ' +
        'f · y · typically false → true: callers who leave y out will get different answers.'
    )
  })

  it('lists nothing for no notices', () => {
    expect(text([])).toBe('')
  })
})
