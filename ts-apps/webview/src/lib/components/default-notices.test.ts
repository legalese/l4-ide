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
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()

describe('DefaultNotices', () => {
  it('lists the rule, the input, the old value and the new one', () => {
    expect(text([n('the smaller of', 'b', 0, 1)])).toBe(
      'the smaller of b : 0 → 1'
    )
  })

  it('names a record field by its path and quotes text', () => {
    expect(
      text([
        n('run job', 'cfg.retries', 3, 5),
        n('pick colour', 'c', 'Green', 'Red'),
      ])
    ).toBe('run job cfg.retries : 3 → 5 pick colour c : "Green" → "Red"')
  })

  it('reads NOTHING as empty, and false and 0 as themselves', () => {
    expect(text([n('f', 'x', null, 0), n('f', 'y', false, true)])).toBe(
      'f x : empty → 0 f y : false → true'
    )
  })

  it('lists nothing for no notices', () => {
    expect(text([])).toBe('')
  })
})
