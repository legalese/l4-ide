import { describe, expect, it } from 'vitest'
import { render } from 'svelte/server'
import type { ExportedFunctionInfo } from 'jl4-client-rpc'
import ToolCard from './tool-card.svelte'

// The ENTRY POINT badge has its own test file, so that the commit that renames
// the badge can be reverted alone: a revert removes this file and touches no
// other test.

function html(func: ExportedFunctionInfo): string {
  return render(ToolCard, { props: { func, expanded: true } }).body
}

const text = (func: ExportedFunctionInfo): string =>
  html(func)
    .replace(/<!--.*?-->/g, '')
    .replace(/<[^>]+>/g, '')
    .replace(/\s+/g, ' ')
    .trim()

const fn = (
  rest: Partial<ExportedFunctionInfo> = {}
): ExportedFunctionInfo => ({
  name: 'the smaller of',
  description: '',
  isDefault: false,
  returnType: 'NUMBER',
  isDeontic: false,
  parameters: {
    type: 'object',
    properties: { a: { type: 'number' } },
    required: ['a'],
  } as unknown as ExportedFunctionInfo['parameters'],
  ...rest,
})

describe('ToolCard: the entry-point badge', () => {
  it('calls the rule l4 batch runs when it is given no name an ENTRY POINT, and says so', () => {
    const t = text(fn({ isDefault: true }))
    expect(t).toContain('ENTRY POINT')
    expect(html(fn({ isDefault: true }))).toContain(
      'The rule l4 batch runs when you name none: the one marked @export default, or the first exported rule'
    )
  })

  it('does not claim the service has an entry point for a caller who names no rule', () => {
    const out = html(fn({ isDefault: true }))
    expect(out).not.toContain('callers reach')
  })

  it('does not use the word DEFAULT for it, which now reads as a default value', () => {
    expect(text(fn({ isDefault: true }))).not.toMatch(/\bDEFAULT\b/)
  })

  it('shows no badge on a rule that is not the entry point', () => {
    expect(text(fn())).not.toContain('ENTRY POINT')
  })
})
