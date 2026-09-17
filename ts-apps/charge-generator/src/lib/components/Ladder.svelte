<script lang="ts">
  import { onMount, untrack } from 'svelte'
  import { defaultViewSpec } from '@repo/ladder-core'
  import { LadderController } from '@repo/ladder-svg'
  import type { FunDecl, NodeId, UBoolValue } from '@repo/ladder-core'

  /**
   * The ladder embed, after regcf-wizard's, with one difference: the valuation
   * is POSITIONAL (keyed by node id) rather than by `unique`, because a leaf
   * that CALLS another rule (`cheats f`) carries no `unique` — it is an `App`
   * — and this app values it from the callee's ladder. Clicks report the node
   * id; the parent maps it to a facts-record field (`lib/charges/valuation.ts`).
   *
   * As in the wizard: this component does not evaluate, does not read the
   * wire's inline leaf values (always UnknownV), and never keys on `atomId`.
   */
  let {
    fn,
    valuation = new Map<NodeId, UBoolValue>(),
    interactive = false,
    onClickNode,
    caption,
    variant = 'card',
  }: {
    /** The decoded ladder tree (`fromVizFunDecl(...).fn`). */
    fn: FunDecl
    valuation?: Map<NodeId, UBoolValue>
    interactive?: boolean
    onClickNode?: (id: NodeId) => void
    caption?: string
    variant?: 'card' | 'stacked'
  } = $props()

  let host = $state<HTMLDivElement | null>(null)
  let controller: LadderController | null = null

  function draw(v: Map<NodeId, UBoolValue>): void {
    if (!controller) return
    controller.render(defaultViewSpec({ valuation: v, showCurrent: true }))
  }

  onMount(() => {
    if (!host) return
    controller = new LadderController(host, fn, {
      interactive,
      panZoom: true,
      onAct: (act) => {
        if (act.t !== 'value' || !onClickNode) return
        onClickNode(act.id)
      },
    })
    draw(valuation)
    return () => {
      controller?.destroy()
      controller = null
    }
  })

  $effect(() => {
    const v = valuation
    untrack(() => draw(v))
  })
</script>

<figure class="ladder">
  <div
    class="ladder-host"
    class:card={variant === 'card'}
    class:stacked={variant === 'stacked'}
    class:interactive
    bind:this={host}
  ></div>
  {#if caption}
    <figcaption>{caption}</figcaption>
  {/if}
</figure>

<style>
  .ladder {
    margin: 0 0 0.8rem;
  }
  figcaption {
    color: var(--muted);
    font-size: 0.85rem;
    margin-top: 0.35rem;
  }
</style>
