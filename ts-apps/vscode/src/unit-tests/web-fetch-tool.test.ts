import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import {
  MAX_PAGE_CHARS,
  VSCODE_FETCH_TOOL,
  WEB_FETCH_TOOL_NAME,
  WebFetchTools,
  parseFetchArgs,
  type LmToolOutcome,
  type LmTools,
} from '../ai/web-fetch-tool.js'

/** A `vscode.lm` with or without VS Code's fetch tool, answering with
 *  `outcome` and recording what it was asked. */
function fakeLm(
  outcome: LmToolOutcome = { kind: 'ok', text: 'page' },
  hasFetch = true
): LmTools & { calls: Array<{ name: string; input: object }> } {
  const calls: Array<{ name: string; input: object }> = []
  return {
    calls,
    has: (name) => hasFetch && name === VSCODE_FETCH_TOOL,
    invoke: async (name, input) => {
      calls.push({ name, input })
      return outcome
    },
  }
}

const args = (url: unknown) => JSON.stringify({ url })

describe('web__fetch', () => {
  test('is advertised only while VS Code has its fetch tool', () => {
    assert.deepEqual(
      new WebFetchTools(fakeLm()).listTools().map((t) => t.function.name),
      [WEB_FETCH_TOOL_NAME]
    )
    assert.deepEqual(
      new WebFetchTools(fakeLm(undefined, false)).listTools(),
      []
    )
  })

  test("asks VS Code's tool for one URL and returns the page", async () => {
    const lm = fakeLm({ kind: 'ok', text: '# Statute\nSection 1' })
    const page = await new WebFetchTools(lm).callTool(
      WEB_FETCH_TOOL_NAME,
      args('https://example.com/law')
    )
    assert.equal(page, '# Statute\nSection 1')
    assert.deepEqual(lm.calls, [
      {
        name: VSCODE_FETCH_TOOL,
        input: { urls: ['https://example.com/law'] },
      },
    ])
  })

  test('fetches only http and https, never local files', async () => {
    for (const url of [
      'file:///etc/passwd',
      '/etc/passwd',
      'vscode-userdata:/settings.json',
      'ftp://example.com/x',
    ]) {
      const lm = fakeLm()
      await assert.rejects(
        new WebFetchTools(lm).callTool(WEB_FETCH_TOOL_NAME, args(url))
      )
      assert.equal(lm.calls.length, 0, url)
    }
    assert.ok(parseFetchArgs(args('http://example.com')) instanceof URL)
  })

  test('rejects missing or malformed arguments', () => {
    assert.ok(parseFetchArgs('not json') instanceof Error)
    assert.ok(parseFetchArgs(args(42)) instanceof Error)
    assert.ok(parseFetchArgs(args('  ')) instanceof Error)
    assert.ok(parseFetchArgs('{}') instanceof Error)
  })

  test("says so when the user turns down VS Code's dialog", async () => {
    await assert.rejects(
      new WebFetchTools(fakeLm({ kind: 'declined' })).callTool(
        WEB_FETCH_TOOL_NAME,
        args('https://example.com')
      ),
      /declined to fetch https:\/\/example\.com/
    )
  })

  test("turns VS Code's error and redirect texts into errors", async () => {
    await assert.rejects(
      new WebFetchTools(
        fakeLm({
          kind: 'ok',
          text: 'An error occurred retrieving the fetch result: HTTP 404',
        })
      ).callTool(WEB_FETCH_TOOL_NAME, args('https://example.com/gone')),
      /Could not fetch https:\/\/example\.com\/gone: HTTP 404/
    )
    await assert.rejects(
      new WebFetchTools(
        fakeLm({
          kind: 'ok',
          text: 'The webpage has redirected to "https://example.org/new". Use the vscode_fetchWebPage_internal again to get its contents.',
        })
      ).callTool(WEB_FETCH_TOOL_NAME, args('https://example.com/old')),
      /redirected to https:\/\/example\.org\/new\. Call web__fetch/
    )
  })

  test('caps a long page', async () => {
    const page = await new WebFetchTools(
      fakeLm({ kind: 'ok', text: 'x'.repeat(MAX_PAGE_CHARS + 10) })
    ).callTool(WEB_FETCH_TOOL_NAME, args('https://example.com'))
    assert.ok(page.startsWith('x'.repeat(MAX_PAGE_CHARS)))
    assert.match(page, /\[Truncated: 10 more characters/)
  })

  test('fails when VS Code no longer has its fetch tool', async () => {
    await assert.rejects(
      new WebFetchTools(fakeLm(undefined, false)).callTool(
        WEB_FETCH_TOOL_NAME,
        args('https://example.com')
      ),
      /not available/
    )
  })
})
