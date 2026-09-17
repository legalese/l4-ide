/** The state-graph pane, minus VS Code: the document it shows, and the
 *  position arithmetic that keeps it pointed at the right DECIDE while the
 *  file is edited (jl4-client-rpc's `trackSrcPos`, tested here because this
 *  package has the `node --test` rig and that one does not). */
import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import {
  stateGraphTargetGone,
  trackSrcPos,
  type ContentChange,
} from 'jl4-client-rpc'
import {
  renderStateGraphHtml,
  stateGraphCsp,
  escapeHtml,
} from '../state-graph-html.js'

describe('renderStateGraphHtml', () => {
  const svg =
    '<svg width="1pt" height="1pt"><g class="graph"><text>the tenancy</text></g></svg>'

  test('the CSP is the one the DOT-only pane shipped with: nothing new is allowed', () => {
    const html = renderStateGraphHtml({ name: 'r', dot: 'digraph {}', svg })
    const csp = html.match(/Content-Security-Policy" content="([^"]*)"/)?.[1]
    assert.ok(csp)
    assert.match(
      csp,
      /^default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-[a-z0-9]+';$/
    )
    assert.equal(csp, stateGraphCsp(csp.match(/nonce-([a-z0-9]+)/)![1]))
    assert.ok(!csp.includes('wasm-unsafe-eval'))
    assert.ok(!csp.includes('img-src'))
  })

  test('the picture is inlined as markup and the DOT is folded under <details>', () => {
    const html = renderStateGraphHtml({ name: 'r', dot: 'digraph {}', svg })
    assert.ok(html.includes(`<div id="picture">${svg}</div>`))
    const details = html.match(/<details>[\s\S]*?<\/details>/)?.[0]
    assert.ok(details, 'a <details> fold')
    assert.ok(details.includes('<button id="copy">Copy DOT</button>'))
    assert.ok(details.includes('<pre id="dot"></pre>'))
  })

  test('the rule name is HTML-escaped in the heading and the payload is closing-tag safe', () => {
    const html = renderStateGraphHtml({
      name: '<b>"x"</b>',
      dot: 'digraph { 0 [label="</script><script>evil()</script>"] }',
      svg,
    })
    assert.ok(
      html.includes(
        '<h1 id="title">State graph: &lt;b&gt;&quot;x&quot;&lt;/b&gt;</h1>'
      )
    )
    const payload = html.match(
      /<script type="application\/json" id="payload">([\s\S]*?)<\/script>/
    )?.[1]
    assert.ok(payload)
    assert.ok(!payload.includes('</script>'), 'no closing tag inside the JSON')
    assert.deepEqual(
      JSON.parse(payload).dot,
      'digraph { 0 [label="</script><script>evil()</script>"] }'
    )
  })

  test('a render failure shows the message and no picture', () => {
    const html = renderStateGraphHtml({
      name: 'r',
      dot: 'digraph {',
      error:
        'Graphviz could not render the state graph: syntax error in line 1',
    })
    assert.ok(
      html.includes('<p class="error" id="error">Graphviz could not render')
    )
    assert.ok(html.includes('<div id="picture"></div>'))
  })

  test('an update that failed to render keeps the last picture, dimmed under the error', () => {
    // The webview script is not run here (no DOM); pin the two halves of the
    // behaviour it implements: a `.faded` rule exists, and the update branch
    // replaces the picture only when an svg arrived and toggles `faded` on
    // exactly the no-svg case.
    const html = renderStateGraphHtml({ name: 'r', dot: 'digraph {}', svg })
    assert.match(html, /#picture\.faded \{ opacity: 0\.35; \}/)
    const script = html.match(
      /<script nonce="[a-z0-9]+">([\s\S]*?)<\/script>/
    )?.[1]
    assert.ok(script)
    assert.ok(
      script.includes("if (msg.svg) { el('picture').innerHTML = msg.svg; }")
    )
    assert.ok(
      script.includes("el('picture').classList.toggle('faded', !msg.svg);")
    )
    // and the initial document never starts dimmed
    assert.ok(html.includes('<div id="picture">'))
    assert.ok(!html.includes('<div id="picture" class='))
  })

  test('escapeHtml covers the four characters that matter', () => {
    assert.equal(escapeHtml('a & <b> "c"'), 'a &amp; &lt;b&gt; &quot;c&quot;')
  })
})

describe('trackSrcPos', () => {
  // A DECIDE starting at line 10, column 1 (1-indexed), as the lens names it.
  const at = { line: 10, column: 1 }
  const change = (
    sl: number,
    sc: number,
    el: number,
    ec: number,
    text: string
  ): ContentChange => ({
    range: {
      start: { line: sl, character: sc },
      end: { line: el, character: ec },
    },
    text,
  })

  test('an edit below the rule leaves it alone', () => {
    assert.deepEqual(trackSrcPos(at, [change(12, 0, 12, 0, 'x\n')]), at)
    assert.deepEqual(trackSrcPos(at, [change(9, 5, 9, 5, 'x')]), at) // same line, after col 0
  })

  test('typing a line above moves the rule down; deleting one moves it up', () => {
    assert.deepEqual(trackSrcPos(at, [change(3, 0, 3, 0, '-- note\n')]), {
      line: 11,
      column: 1,
    })
    assert.deepEqual(trackSrcPos(at, [change(3, 0, 4, 0, '')]), {
      line: 9,
      column: 1,
    })
    // a multi-line paste replacing one line above: net +2
    assert.deepEqual(trackSrcPos(at, [change(2, 0, 3, 0, 'a\nb\nc\n')]), {
      line: 12,
      column: 1,
    })
  })

  test('Enter at the very start of the DECIDE pushes it down a line', () => {
    assert.deepEqual(trackSrcPos(at, [change(9, 0, 9, 0, '\n')]), {
      line: 11,
      column: 1,
    })
  })

  test('an insertion on the same line before the position moves the column', () => {
    const indented = { line: 10, column: 5 }
    assert.deepEqual(trackSrcPos(indented, [change(9, 0, 9, 0, '  ')]), {
      line: 10,
      column: 7,
    })
    // and a join of the previous line moves it up and along
    assert.deepEqual(trackSrcPos(indented, [change(8, 3, 9, 0, '')]), {
      line: 9,
      column: 8,
    })
  })

  test('an edit that covers the position loses it', () => {
    assert.equal(trackSrcPos(at, [change(9, 0, 9, 1, '')]), null)
    assert.equal(trackSrcPos(at, [change(5, 0, 12, 0, '')]), null)
  })

  test('changes apply in order, each against the document the last one left', () => {
    // insert a line above (rule -> 11), then delete two lines above it (-> 9)
    assert.deepEqual(
      trackSrcPos(at, [change(0, 0, 0, 0, 'x\n'), change(1, 0, 3, 0, '')]),
      { line: 9, column: 1 }
    )
  })
})

describe('stateGraphTargetGone', () => {
  // The two refusals `LSP.L4.Actions.stateGraphAtPos` can send back, as the
  // client's sendRequest throws them.
  test('the language server\'s "no regulative rule starts there" is gone for good', () => {
    assert.equal(
      stateGraphTargetGone(
        new Error(
          'No regulative rule starts at that position (the program may have changed between pressing the code lens and rendering it)'
        )
      ),
      true
    )
  })

  test('the language server\'s "Could not check" is transient: the file is mid-edit', () => {
    assert.equal(
      stateGraphTargetGone(new Error('Could not check file:///t.l4.')),
      false
    )
  })

  // The wasm shim's { error, notFound? } (`L4.API.l4StateGraphByName`).
  test("the wasm shim's notFound is gone; a bare error is a parse or check failure", () => {
    assert.equal(
      stateGraphTargetGone({ error: "Rule 'x' not found", notFound: true }),
      true
    )
    assert.equal(
      stateGraphTargetGone({
        error: 'unexpected end of input',
        notFound: false,
      }),
      false
    )
    assert.equal(
      stateGraphTargetGone({ error: 'unexpected end of input' }),
      false
    )
  })

  test('anything unrecognised is transient: keep asking rather than let go', () => {
    assert.equal(stateGraphTargetGone(new Error('socket closed')), false)
    assert.equal(stateGraphTargetGone(undefined), false)
  })
})
