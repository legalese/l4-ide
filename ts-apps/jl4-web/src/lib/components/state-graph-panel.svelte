<!--
  The pane the "Show state graph" code lens opens in the web IDE.

  The wasm shim (or the language server, over websocket) answers
  `l4.stateGraph` with the rule's state graph as GraphViz DOT source. The DOT
  is rendered to SVG in the browser by `@repo/state-graph-render` (Graphviz
  compiled to WebAssembly), loaded lazily on first use so it is its own chunk
  and costs nothing until a lens is pressed. The DOT source and a Copy DOT
  button stay under a fold beneath the picture.
  See doc/reference/regulative/STATE-GRAPH.md.
-->
<script lang="ts">
  import { toast } from '@zerodevx/svelte-toast'

  let {
    name,
    dot,
    stale = null,
  }: {
    name: string
    dot: string
    /** Set by the page when the rule the picture came from can no longer be
     *  found after an edit; the last picture stays up with this notice. */
    stale?: string | null
  } = $props()

  let svg = $state<string | null>(null)
  let error = $state<string | null>(null)

  // The renderer module, loaded once per page on first need.
  let renderer: Promise<typeof import('@repo/state-graph-render')> | null = null
  const loadRenderer = () => (renderer ??= import('@repo/state-graph-render'))

  $effect(() => {
    const thisDot = dot
    let cancelled = false
    loadRenderer()
      .then((m) => m.renderStateGraphSvg(thisDot))
      .then(
        (out) => {
          if (cancelled) return
          svg = out
          error = null
        },
        (e: unknown) => {
          if (cancelled) return
          error = e instanceof Error ? e.message : String(e)
        }
      )
    return () => {
      cancelled = true
    }
  })

  async function copy() {
    try {
      await navigator.clipboard.writeText(dot)
      toast.push('DOT copied to clipboard.', { duration: 3000 })
    } catch {
      toast.push('Could not copy to the clipboard; select the text instead.')
    }
  }
</script>

<div class="state-graph-panel">
  <h2>State graph: {name}</h2>
  <p class="note">
    The action plane of this rule: states, and the actions that move between
    them. It does not show who is obliged to do what at any moment. Redraws as
    you edit.
  </p>
  {#if stale}
    <p class="stale">{stale}</p>
  {/if}
  {#if error}
    <p class="error">{error}</p>
  {:else if svg}
    <!-- Graphviz XML-escapes every label, and the emitter's DOT never asks
         for <script>, <a> or <foreignObject>, so the markup is inert. -->
    <div class="picture">{@html svg}</div>
  {:else}
    <p class="note">Drawing…</p>
  {/if}
  <details>
    <summary>DOT source</summary>
    <button type="button" onclick={copy}>Copy DOT</button>
    <pre>{dot}</pre>
  </details>
</div>

<style>
  .state-graph-panel {
    height: 100%;
    overflow: auto;
    padding: 0 1em 1em;
    box-sizing: border-box;
  }
  h2 {
    font-size: 1.1em;
    font-weight: 600;
    margin: 1em 0 0.25em;
  }
  .note {
    margin: 0.25em 0 0.75em;
    opacity: 0.8;
    font-size: 0.9em;
  }
  .stale {
    margin: 0.25em 0 0.75em;
    font-size: 0.9em;
    color: #8a6d00;
  }
  .error {
    margin: 0.25em 0 0.75em;
    color: #b00020;
    white-space: pre-wrap;
  }
  .picture {
    overflow: auto;
  }
  .picture :global(svg) {
    max-width: 100%;
    height: auto;
  }
  details {
    margin-top: 1em;
  }
  summary {
    cursor: pointer;
    opacity: 0.8;
    font-size: 0.9em;
  }
  button {
    font: inherit;
    padding: 0.3em 0.8em;
    margin: 0.75em 0;
    border: 1px solid #999;
    border-radius: 3px;
    background: white;
    cursor: pointer;
  }
  button:hover {
    background: #eee;
  }
  pre {
    font-family: ui-monospace, Menlo, Consolas, monospace;
    font-size: 0.85em;
    background: #f5f5f5;
    padding: 0.75em;
    overflow: auto;
    white-space: pre;
    user-select: text;
  }
</style>
