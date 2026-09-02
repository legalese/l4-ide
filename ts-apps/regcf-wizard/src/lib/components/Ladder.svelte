<script lang="ts">
  import { onMount, untrack } from 'svelte'
  import { fromVizFunDecl, defaultViewSpec } from '@repo/ladder-core'
  import { LadderController } from '@repo/ladder-svg'
  import type { NodeId, UBoolValue } from '@repo/ladder-core'

  // The wire `FunDecl` is `@repo/viz-expr`'s, NOT ladder-core's (they differ:
  // the wire one is tagged and carries `Name`/`IRId` wrappers). Naming it off
  // the adapter's own signature keeps the two straight without taking a direct
  // dependency on viz-expr just for a type.
  type VizFunDecl = Parameters<typeof fromVizFunDecl>[0]

  /**
   * The ladder embed (SPEC.md §7 G3: "ladders embedded in the entry"; the
   * framework-free controller from PR #177 is the whole of the machinery).
   *
   * Three things this component does NOT do, each on purpose:
   *
   *  1. It does not evaluate. EMBEDDABLE.md EK5 — "the element's brain is
   *     `verdictFor` + a valuation map, not `LadderModel`" — and here even
   *     `verdictFor` stays unused: the verdict on the page comes from the
   *     service's query-plan, so the picture and the answer can never disagree.
   *  2. It does not read the wire's inline leaf `value`. Measured: `GET
   *     …/{fn}/ladder` returns `"value":"UnknownV"` on every leaf and KEEPS
   *     returning `UnknownV` even when a query-plan call binds that atom. The
   *     valuation is the client's, and it is passed in.
   *  3. It does not key anything on `atomId`. The ladder payload and the
   *     query-plan disagree about atomIds for the same atom (see
   *     `api/client.ts#queryPlan`); `unique` agrees, so `unique` is the join.
   */
  let {
    funDecl,
    valuationByUnique = new Map<number, UBoolValue>(),
    interactive = false,
    onToggle,
    caption,
  }: {
    /** The `funDecl` field of `RenderAsLadderInfo`, as fetched. */
    funDecl: unknown
    /** T/F for each ANSWERED atom, keyed by `unique`. Absent = unknown. */
    valuationByUnique?: Map<number, UBoolValue>
    interactive?: boolean
    /** Called with an atom's `unique` when its box is clicked. */
    onToggle?: (unique: number) => void
    caption?: string
  } = $props()

  let host = $state<HTMLDivElement | null>(null)
  let controller: LadderController | null = null
  let uniqueByNode = new Map<NodeId, number>()
  let nodesByUnique = new Map<number, NodeId[]>()

  /** unique-keyed valuation -> the positional (node-id-keyed) map layout wants. */
  function positional(
    byUnique: Map<number, UBoolValue>
  ): Map<NodeId, UBoolValue> {
    const out = new Map<NodeId, UBoolValue>()
    for (const [u, v] of byUnique) {
      for (const n of nodesByUnique.get(u) ?? []) out.set(n, v)
    }
    return out
  }

  function draw(byUnique: Map<number, UBoolValue>): void {
    if (!controller) return
    controller.render(
      defaultViewSpec({ valuation: positional(byUnique), showCurrent: true })
    )
  }

  onMount(() => {
    if (!host) return
    const decoded = fromVizFunDecl(funDecl as VizFunDecl)
    uniqueByNode = decoded.uniqueByNode
    nodesByUnique = decoded.nodesByUnique
    controller = new LadderController(host, decoded.fn, {
      interactive,
      // Pan/zoom needs a DEFINITE host height (the controller clips rather than
      // scrolls). The static embed has none, so it keeps the pre-Step-4 sizing:
      // max-width:100%, height:auto. Turning it on for the interactive panel is
      // what the .ladder-host height rule in app.css exists for.
      panZoom: interactive,
      onAct: (act) => {
        if (act.t !== 'value' || !onToggle) return
        const u = uniqueByNode.get(act.id)
        if (u !== undefined) onToggle(u)
      },
    })
    draw(valuationByUnique)
    return () => {
      controller?.destroy()
      controller = null
    }
  })

  // Re-draw when the valuation changes. The map is read HERE (so the effect
  // depends on it) and passed in; `untrack` then keeps `draw`'s own reads from
  // re-subscribing this effect to everything the controller touches.
  $effect(() => {
    const v = valuationByUnique
    untrack(() => draw(v))
  })
</script>

<figure class="ladder">
  <div class="ladder-host" class:interactive bind:this={host}></div>
  {#if caption}
    <figcaption>{caption}</figcaption>
  {/if}
</figure>

<style>
  .ladder {
    margin: 0 0 1.5rem;
  }
  figcaption {
    color: var(--muted);
    font-size: 0.88rem;
    margin-top: 0.5rem;
  }
</style>
