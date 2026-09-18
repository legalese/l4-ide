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

  // The lightbox: a second, independent LadderController over the same `fn`,
  // mounted into a full-viewport host while open. It shares `draw` below, so a
  // click inside the lightbox (or outside it) keeps both views in sync.
  let zoomed = $state(false)
  let zoomHost = $state<HTMLDivElement | null>(null)
  let zoomController: LadderController | null = null
  let trigger = $state<HTMLButtonElement | null>(null)
  let closeBtn = $state<HTMLButtonElement | null>(null)

  function draw(v: Map<NodeId, UBoolValue>): void {
    const vs = defaultViewSpec({ valuation: v, showCurrent: true })
    controller?.render(vs)
    zoomController?.render(vs)
  }

  function onAct(id: NodeId): void {
    onClickNode?.(id)
  }

  onMount(() => {
    if (!host) return
    controller = new LadderController(host, fn, {
      interactive,
      panZoom: true,
      onAct: (act) => {
        if (act.t === 'value') onAct(act.id)
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

  // Mounts only while `zoomed` — a fresh controller per opening, fit to the
  // window it just filled, torn down on close so it never renders off-screen.
  $effect(() => {
    const open = zoomed
    const el = zoomHost
    if (!open || !el) return
    untrack(() => {
      const c = new LadderController(el, fn, {
        interactive,
        panZoom: true,
        onAct: (act) => {
          if (act.t === 'value') onAct(act.id)
        },
      })
      zoomController = c
      c.render(defaultViewSpec({ valuation, showCurrent: true }))
      c.fit()
    })
    return () => {
      zoomController?.destroy()
      zoomController = null
    }
  })

  $effect(() => {
    if (zoomed) closeBtn?.focus()
  })

  $effect(() => {
    if (!zoomed) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') closeZoom()
    }
    window.addEventListener('keydown', onKey)
    const priorOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      window.removeEventListener('keydown', onKey)
      document.body.style.overflow = priorOverflow
    }
  })

  function openZoom(): void {
    zoomed = true
  }
  function closeZoom(): void {
    zoomed = false
    trigger?.focus()
  }
</script>

<figure class="ladder">
  <div class="ladder-frame">
    <div
      class="ladder-host"
      class:card={variant === 'card'}
      class:stacked={variant === 'stacked'}
      class:interactive
      bind:this={host}
    ></div>
    <button
      type="button"
      class="expand-btn"
      bind:this={trigger}
      onclick={openZoom}
      aria-label="Expand ladder diagram to fill the window"
      title="Expand to fill window"
    >
      <svg
        viewBox="0 0 24 24"
        width="15"
        height="15"
        aria-hidden="true"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <path
          d="M8 3H5a2 2 0 0 0-2 2v3M16 3h3a2 2 0 0 1 2 2v3M8 21H5a2 2 0 0 1-2-2v-3M16 21h3a2 2 0 0 1 2-2v-3"
        />
      </svg>
    </button>
  </div>
  {#if caption}
    <figcaption>{caption}</figcaption>
  {/if}
</figure>

{#if zoomed}
  <div
    class="lightbox"
    role="dialog"
    aria-modal="true"
    aria-label={caption ?? 'Ladder diagram, expanded'}
    tabindex="-1"
    onclick={(e) => {
      if (e.target === e.currentTarget) closeZoom()
    }}
    onkeydown={(e) => {
      if (e.key === 'Escape') closeZoom()
    }}
  >
    <div class="lightbox-bar">
      <span class="lightbox-caption">{caption ?? 'Ladder diagram'}</span>
      <button
        type="button"
        class="lightbox-close"
        bind:this={closeBtn}
        onclick={closeZoom}
      >
        Close ✕
      </button>
    </div>
    <div class="lightbox-host" bind:this={zoomHost}></div>
  </div>
{/if}

<style>
  .ladder {
    margin: 0 0 0.8rem;
  }
  .ladder-frame {
    position: relative;
  }
  figcaption {
    color: var(--muted);
    font-size: 0.85rem;
    margin-top: 0.35rem;
  }
  .expand-btn {
    position: absolute;
    top: 0.5rem;
    right: 0.5rem;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 1.9rem;
    height: 1.9rem;
    border: 1px solid var(--hairline);
    border-radius: 6px;
    background: var(--surface);
    color: var(--ink);
    opacity: 0.6;
    cursor: pointer;
  }
  .expand-btn:hover,
  .expand-btn:focus-visible {
    opacity: 1;
  }
  .lightbox {
    position: fixed;
    inset: 0;
    z-index: 1000;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    padding: 0.8rem 1rem 1rem;
    background: var(--surface);
  }
  .lightbox-bar {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 0.8rem;
  }
  .lightbox-caption {
    color: var(--muted);
    font-size: 0.9rem;
  }
  .lightbox-close {
    border: 1px solid var(--hairline);
    border-radius: 8px;
    background: var(--surface);
    color: var(--ink);
    padding: 0.35rem 0.8rem;
    font: inherit;
    font-weight: 600;
    cursor: pointer;
    flex: none;
  }
  .lightbox-close:hover {
    background: var(--surface-sunk);
  }
  .lightbox-host {
    flex: 1 1 auto;
    min-height: 0;
    position: relative;
    overflow: hidden;
    border: 1px solid var(--hairline);
    border-radius: 12px;
  }
</style>
