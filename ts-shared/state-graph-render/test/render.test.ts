/** render.test.ts — the pictures the pane shows are Graphviz's, so these tests
 * assert the *vocabulary* the emitter relies on survives the trip through
 * viz.js: doublecircle terminals, dashed red LEST edges, the second text line
 * on an EVERY edge, diamond junctions, and a self-loop. Coordinates are not
 * asserted (they move between Graphviz releases); the Graphviz version is,
 * so that a bump is a visible diff. */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  graphvizVersion,
  renderStateGraphSvg,
  StateGraphRenderError,
} from '../src/index.js'

const HERE = dirname(fileURLToPath(import.meta.url))
const REPO = resolve(HERE, '../../..')

/** The doc figure: one EVERY edge with a join line, two LEST edges, two terminals. */
const everyBarrier = readFileSync(
  resolve(REPO, 'doc/reference/regulative/figures/every-barrier.dot'),
  'utf8'
)
/** A HENCE back to the rule's own name: `0 -> 0`. Written by `l4 state-graph`
 *  from `self-loop.l4` beside it. */
const selfLoop = readFileSync(resolve(HERE, 'fixtures/self-loop.dot'), 'utf8')

const count = (s: string, re: RegExp) => (s.match(re) ?? []).length

test('the Graphviz version is the one the memo measured', () => {
  assert.equal(graphvizVersion, '16.0.0')
})

test('the result is an inline-ready <svg> with no prologue and no background card', async () => {
  const svg = await renderStateGraphSvg(everyBarrier)
  assert.ok(svg.startsWith('<svg '), 'starts at the <svg> start tag')
  assert.ok(svg.trimEnd().endsWith('</svg>'))
  assert.ok(!svg.includes('<?xml'), 'XML declaration stripped')
  assert.ok(!svg.includes('<!DOCTYPE'), 'DOCTYPE stripped')
  assert.ok(
    !/<polygon fill="white" stroke="(?:none|transparent)"/.test(svg),
    'the canvas-sized white polygon is gone'
  )
  // and nothing else was: every other drawn element of every-barrier is present
  assert.equal(count(svg, /<g id="node\d+" class="node">/g), 4)
  assert.equal(count(svg, /<g id="edge\d+" class="edge">/g), 4)
})

test('transparentBackground: false keeps the white polygon', async () => {
  const svg = await renderStateGraphSvg(everyBarrier, {
    transparentBackground: false,
  })
  assert.ok(/<polygon fill="white" stroke="(?:none|transparent)"/.test(svg))
})

test('every-barrier: terminals are double-ringed, LEST is dashed red, EVERY carries its join line', async () => {
  const svg = await renderStateGraphSvg(everyBarrier)
  // 4 nodes, 2 of them doublecircle: 2 single ellipses + 2 x 2 = 6
  assert.equal(count(svg, /<ellipse /g), 6)
  assert.equal(count(svg, /<ellipse fill="#d4edda"/g), 1, 'Fulfilled inner')
  assert.equal(count(svg, /<ellipse fill="#f8d7da"/g), 1, 'Breach inner')
  // the two LEST edges: red, dashed
  assert.equal(count(svg, /stroke="#dc3545" stroke-dasharray="5,2"/g), 2)
  // the EVERY edge's label is two <text> lines, the second the join line
  const everyEdge = svg.match(/<g id="edge1" class="edge">[\s\S]*?<\/g>/)?.[0]
  assert.ok(everyEdge, 'edge1 present')
  const lines = everyEdge.match(/<text [^>]*>([^<]*)<\/text>/g) ?? []
  assert.equal(lines.length, 2)
  assert.match(lines[0], /EVERY Tenant t IN tenants MUST Sign/)
  assert.match(lines[1], />ONCE ALL HAVE</)
  // the title is the rule's name
  assert.match(svg, />the tenancy</)
})

test('a HENCE to the rule itself renders as a self-loop edge', async () => {
  const svg = await renderStateGraphSvg(selfLoop)
  assert.match(svg, /<title>0&#45;&gt;0<\/title>/, 'the 0 -> 0 edge is drawn')
  assert.equal(count(svg, /<g id="edge\d+" class="edge">/g), 4)
  assert.equal(count(svg, /<g id="node\d+" class="node">/g), 4)
  // its label is on the loop, in HENCE green
  const loop = svg.match(
    /<g id="edge\d+" class="edge">\n<title>0&#45;&gt;0<\/title>[\s\S]*?<\/g>/
  )?.[0]
  assert.ok(loop)
  assert.match(loop, /stroke="#28a745"/)
  assert.match(loop, /MUST pay the rent \[30\]/)
})

test('RAND and ROR junctions are diamonds with their caption on a second line', async () => {
  const dot = `digraph {
    0 [label="initial",style=filled,shape=ellipse,fillcolor="#e8f4fd"];
    1 [label="both\\nALL OF",style=filled,shape=diamond,fillcolor="#e6dcf5"];
    2 [label="either\\nONE OF",style=filled,shape=diamond,fillcolor="#fde8cc"];
    3 [label=Fulfilled,style=filled,shape=doublecircle,fillcolor="#d4edda"];
    0 -> 1 [label="a",color="#6f42c1",style=solid];
    0 -> 2 [label="b",color="#e8850c",style=dotted];
    1 -> 3; 2 -> 3;
  }`
  const svg = await renderStateGraphSvg(dot)
  assert.equal(count(svg, /<polygon fill="#e6dcf5"/g), 1, 'RAND diamond')
  assert.equal(count(svg, /<polygon fill="#fde8cc"/g), 1, 'ROR diamond')
  assert.match(svg, />ALL OF</)
  assert.match(svg, />ONE OF</)
  assert.match(
    svg,
    /stroke="#e8850c" stroke-dasharray="1,5"/,
    'dotted ROR exit'
  )
})

test('rule names are XML-escaped in the output, so it is safe to inline', async () => {
  const dot = `digraph { graph [label="<img src=x onerror=alert(1)> & \\"q\\""];
    0 [label="<script>evil()</script>"]; }`
  const svg = await renderStateGraphSvg(dot)
  assert.ok(!svg.includes('<img'), 'no img element')
  assert.ok(!svg.includes('<script'), 'no script element')
  assert.match(svg, /&lt;img src=x onerror=alert\(1\)&gt; &amp; &quot;q&quot;/)
  assert.match(svg, /&lt;script&gt;evil\(\)&lt;\/script&gt;/)
})

test('bad DOT rejects with StateGraphRenderError carrying Graphviz message', async () => {
  await assert.rejects(
    renderStateGraphSvg('digraph { 0 -> ; }'),
    (e: unknown) =>
      e instanceof StateGraphRenderError &&
      e.messages.length > 0 &&
      /syntax error/.test(e.messages[0])
  )
})
