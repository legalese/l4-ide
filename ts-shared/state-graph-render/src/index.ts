/**
 * `@repo/state-graph-render` — GraphViz DOT → SVG for the "Show state graph"
 * pane, in both hosts (the VS Code extension host and the jl4-web browser).
 *
 * The renderer is `@viz-js/viz`: Graphviz itself, compiled to WebAssembly
 * and embedded in one JavaScript file (no `.wasm` asset to serve, no worker,
 * no `fetch`). Because it *is* Graphviz, the picture is the one `dot -Tsvg`
 * draws from the same DOT — measured on every corpus graph before this
 * package was adopted (LTS-VISUALISER.md §4.8, "in-pane rendering").
 *
 * This module is the only place the renderer is named. Hosts call
 * {@link renderStateGraphSvg} and know nothing else, so swapping the engine
 * (for `@hpcc-js/wasm-graphviz`, or a TypeScript layout that owns its own
 * coordinates for the P2 scrubber) touches this file and no host.
 *
 * Licence note: viz.js is MIT; the Graphviz object code it embeds is EPL-1.0
 * and Expat is MIT. The banner at the top of `dist/viz.js` carries the
 * attribution and survives minification (`/*!`); the VS Code extension's
 * README repeats it in its third-party notices.
 */
import {
  instance,
  graphvizVersion as bundledGraphvizVersion,
  type Viz,
} from '@viz-js/viz'

/**
 * The Graphviz version compiled into the renderer. Pinned by a test so that
 * a dependency bump is a visible diff, not a silent relayout.
 */
export const graphvizVersion: string = bundledGraphvizVersion

/** Rendering failed: Graphviz rejected the DOT. `messages` are its own words. */
export class StateGraphRenderError extends Error {
  readonly messages: readonly string[]
  constructor(messages: readonly string[]) {
    super(
      messages.length > 0
        ? `Graphviz could not render the state graph: ${messages.join('; ')}`
        : 'Graphviz could not render the state graph'
    )
    this.name = 'StateGraphRenderError'
    this.messages = messages
  }
}

export interface RenderStateGraphOptions {
  /**
   * Drop the opaque white rectangle Graphviz paints behind every graph, so
   * the picture sits on whatever the host's theme paints. Default `true`;
   * pass `false` to keep Graphviz's output untouched.
   */
  transparentBackground?: boolean
}

let vizInstance: Promise<Viz> | undefined

/** One Graphviz instance per process; instantiation is the ~10-30 ms cost. */
function viz(): Promise<Viz> {
  vizInstance ??= instance()
  return vizInstance
}

/**
 * Render the DOT `L4.StateGraph.stateGraphToDot` emits into an inline-ready
 * `<svg>…</svg>` string: the XML prologue and DOCTYPE are removed, so the
 * result can be dropped straight into a document. Rejects with
 * {@link StateGraphRenderError} when Graphviz refuses the input.
 *
 * The text in the SVG is XML-escaped by Graphviz (a rule named `<b>` arrives
 * as `&lt;b&gt;`), so the result is safe to inject as markup; the only
 * elements it contains are the ones Graphviz draws (`g`, `polygon`, `ellipse`,
 * `path`, `text`, `title`), never `script`, `foreignObject` or `a`, because the
 * emitter's DOT dialect never asks for them.
 */
export async function renderStateGraphSvg(
  dot: string,
  options: RenderStateGraphOptions = {}
): Promise<string> {
  const v = await viz()
  const result = v.render(dot, { format: 'svg', engine: 'dot' })
  if (result.status !== 'success') {
    throw new StateGraphRenderError(
      result.errors
        .filter((e) => e.level !== 'warning')
        .map((e) => e.message.trim())
    )
  }
  let svg = stripPrologue(result.output)
  if (options.transparentBackground ?? true) {
    svg = stripBackground(svg)
  }
  return svg
}

/** Everything before the `<svg` start tag: XML declaration, DOCTYPE, comments. */
function stripPrologue(svg: string): string {
  const at = svg.indexOf('<svg')
  return at < 0 ? svg : svg.slice(at)
}

/**
 * Graphviz's first drawing element is a `<polygon fill="white" stroke="none" …>`
 * covering the whole canvas (`stroke="transparent"` in older versions). Remove
 * exactly that one element; nothing else in the output has that fill/stroke
 * pair because the emitter never fills a node white *and* strokes it none.
 */
function stripBackground(svg: string): string {
  return svg.replace(
    /<polygon fill="white" stroke="(?:none|transparent)" points="[^"]*"\/>\n?/,
    ''
  )
}
