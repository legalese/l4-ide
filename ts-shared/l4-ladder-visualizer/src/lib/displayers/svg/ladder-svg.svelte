<!--
  LadderSvg — the second displayer (E1 Step 4), and deliberately a THIN one.

  Everything browser-facing lives in `@repo/ladder-svg`'s `LadderController`: the sink, the
  one delegated click, the FLIP, the viewBox pan/zoom. Everything about truth lives in
  `LadderModel`. What is left here is Svelte glue — mount, unmount, four pieces of `$state`,
  and a header. If this file ever grows a `requestAnimationFrame`, an `innerHTML`, or an
  `addEventListener`, the amendment of 2026-07-27 has been undone.

  Not in this step, by name: elicitation marks on the diagram (6a — `LadderModel` computes
  them but `ViewSpec` has no `marks` channel, and inventing one here is exactly the wrong
  place), the `+` unfold, tooltips and context menus (6b), the paths list (S11 — not ported),
  and any query-plan / `setElicitationOverride` wiring (Step 5).
-->
<script lang="ts">
  import { onDestroy, onMount, untrack } from 'svelte'
  import type { FunDecl as VizFunDecl } from '@repo/viz-expr'
  import type { Theme, Verdict } from '@repo/ladder-core'
  import { LadderController, paletteFor } from '@repo/ladder-svg'
  import type { Palette } from '@repo/ladder-svg'
  import { LadderModel } from '$lib/model/ladder-model.js'
  import type { LadderModelDeps } from '$lib/model/ladder-model.js'
  import type { PartialEvalAnalysis } from '$lib/eval/partial-eval.js'
  import PartialEvalSidebar from '$lib/displayers/partial-eval/partial-eval-sidebar.svelte'
  import { sidebarBindingsFor } from './sidebar-bridge.js'
  import PanelRight from 'lucide-svelte/icons/panel-right'

  interface LadderSvgProps {
    funDecl: VizFunDecl
    /** `{ l4Connection, verDocId }` — already LIR-free, so this component takes no
     *  `LadderEnv` and calls no `useLadderEnv()`. That is what makes it portable to
     *  Track E's custom element later; a call site builds it in one line from an env. */
    deps: LadderModelDeps
    /** Seam S8: a built-in look, or a host's own `Palette` (e.g. `DARK_PALETTE`). */
    palette?: Theme | Palette
    title?: string
  }

  let { funDecl, deps, palette = 'screen', title }: LadderSvgProps = $props()

  // One model per mount. Non-reactive on purpose: the model owns eval state, and making it
  // a rune would put the async recompute inside the reactive graph — the exact thing the
  // Step-4 amendment moved out of this file. `untrack` says that out loud (a new FunDecl
  // means a new mount, i.e. a `{#key}` at the call site) rather than leaving svelte-check to
  // warn that only the initial value is captured, which is exactly what is intended here.
  const model = untrack(() => new LadderModel(funDecl, deps))

  let host: HTMLDivElement
  let controller: LadderController | null = null

  let viewSpec = $state.raw(model.viewSpec)
  let verdict = $state<Verdict>(model.verdict)
  let analysis = $state<PartialEvalAnalysis | null>(null)
  let showSidebar = $state(false)

  /**
   * Serialised recompute. `model.recompute()` is async (App leaves round-trip to the
   * backend), so two fast clicks can resolve out of order and the older one would overwrite
   * the newer analysis. A sequence counter is not enough — a stale `recompute()` still
   * writes the model's own `#analysis` before the guard runs — so the runs are chained.
   */
  let queue: Promise<void> = Promise.resolve()
  let recomputeError = $state<string | null>(null)
  function schedule() {
    queue = queue
      .then(async () => {
        await model.recompute()
        recomputeError = null
        viewSpec = model.viewSpec
        verdict = model.verdict
        analysis = model.analysis
        controller?.render(viewSpec)
      })
      // The `.catch` is not decoration: `recompute()` round-trips to the language server and
      // can reject (`eval.ts` throws on a backend miss). Without it the FIRST rejection turns
      // `queue` into a rejected promise, every later `.then` skips its callback, and the
      // displayer freezes for good — clicks and sidebar assignments still mutate the model,
      // nothing ever repaints, and the only signal is an unhandled rejection in the console.
      // Catching on the ASSIGNED value is what matters: the next `schedule()` must start from
      // a settled promise, and serialisation (the reason for the chain) is unaffected.
      .catch((e: unknown) => {
        recomputeError = e instanceof Error ? e.message : String(e)
        console.error('ladder recompute failed', e)
      })
  }

  const bindings = sidebarBindingsFor(model, schedule)

  onMount(() => {
    controller = new LadderController(host, model.decoded.fn, {
      theme: palette,
      onAct: (act) => {
        if (act.t === 'value') model.cycleValue(act.id)
        else model.toggleFold(act.id)
        schedule()
      },
    })
    controller.render(viewSpec)
    controller.fit()
    // Run the analysis once up front so the sidebar has something to show before the user
    // has touched anything — "Still Needed" is most useful at the START.
    schedule()
  })

  onDestroy(() => {
    controller?.destroy()
    controller = null
  })

  /**
   * `palette` is a LIVE prop, not a mount-time bake. A host's theme can flip while the
   * diagram is on screen, and remounting to recolour would throw away the user's pan/zoom
   * and the FLIP baseline — so the change goes through `LadderController.setTheme`, which
   * re-emits the last Scene and moves nothing but the colours. Without this the dev route's
   * `dark palette (seam S8)` checkbox darkens only the card, leaving a white diagram on it:
   * the "foreign white rectangle" that seam S8 exists to fix, shipped as proof it is fixed.
   */
  let appliedPalette: Theme | Palette = palette
  $effect(() => {
    const next = palette
    if (controller && next !== appliedPalette) {
      appliedPalette = next
      controller.setTheme(next)
    }
  })

  /** The header's own colours come from the same palette as the diagram, so a dark mount
   *  does not keep a light-theme green. Only the two verdict colours are bound today — the
   *  rest of the chrome still rides the app's CSS variables (recorded in seam S8's row). */
  const chrome = $derived(paletteFor(palette))

  /**
   * The header says the VERDICT, not "evaluates to …" — that string is the §25f category
   * error this whole step exists to kill, and it is still live in `flow-base.svelte:192` on
   * purpose, so Step 5's side-by-side has something to point at.
   *
   * `verdictFor` is the PICTURE's verdict: sound, not complete (`ladder-model.ts` and
   * `ladder-core/src/layout.ts`'s contract). On a tautological subformula with an unknown
   * atom it says "Not yet determined" where the wizard's ROBDD would settle. That is
   * deliberate — the header must say what the ladder draws. Do not "fix" it to match the
   * sidebar.
   */
  const VERDICT_TEXT: Record<Verdict, string> = {
    Undetermined: 'Not yet determined',
    Holds: 'Holds',
    Fails: 'Does not hold',
    Complies: 'Complies',
    InBreach: 'In breach',
    NotApplicable: 'Not applicable',
  }
  const VERDICT_NOTE: Partial<Record<Verdict, string>> = {
    NotApplicable: 'the rule never reached this case',
  }
</script>

<div
  class="ladder-svg-root"
  style="--ladder-verdict-good: {chrome.live}; --ladder-verdict-bad: {chrome.coilRed};"
>
  <header class="ladder-svg-header">
    <h1>{title ?? model.decoded.fn.name}</h1>
    <div class="verdict-row">
      <span class="verdict verdict-{verdict.toLowerCase()}"
        >{VERDICT_TEXT[verdict]}</span
      >
      {#if VERDICT_NOTE[verdict]}
        <span class="verdict-note">— {VERDICT_NOTE[verdict]}</span>
      {/if}
      {#if recomputeError}
        <span class="recompute-error" role="status"
          >— evaluation failed: {recomputeError}</span
        >
      {/if}
      <span class="spacer"></span>
      <!-- The controller draws no chrome of its own, so the view controls are the host's. -->
      <button
        class="icon-btn"
        type="button"
        title="Zoom out"
        aria-label="Zoom out"
        onclick={() => controller?.zoom(1 / 1.25)}>−</button
      >
      <button
        class="icon-btn"
        type="button"
        title="Zoom in"
        aria-label="Zoom in"
        onclick={() => controller?.zoom(1.25)}>+</button
      >
      <button
        class="icon-btn"
        type="button"
        title="Fit to view"
        aria-label="Fit to view"
        onclick={() => controller?.fit()}>fit</button
      >
      <button
        class="icon-btn"
        type="button"
        title="Inputs"
        aria-label="Toggle inputs panel"
        onclick={() => (showSidebar = !showSidebar)}
      >
        <PanelRight size={14} />
      </button>
    </div>
  </header>

  <div class="ladder-svg-row">
    <div class="ladder-host" bind:this={host} aria-label="Ladder diagram"></div>
    {#if showSidebar}
      <PartialEvalSidebar
        context={null}
        ladderGraph={bindings}
        {analysis}
        onClose={() => (showSidebar = false)}
      />
    {/if}
  </div>
</div>

<style>
  .ladder-svg-root {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
  }

  .ladder-svg-header h1 {
    font-size: 1.125rem;
    font-weight: 700;
  }

  .verdict-row {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.875rem;
    margin: 0.125rem 0 0.5rem;
  }

  .spacer {
    flex: 1;
  }

  .verdict {
    font-weight: 600;
  }
  /* Bound to the resolved `Palette` above rather than re-baked here — a hex literal in this
     block is the same seam-S8 mistake one level up, and the source scan in
     `ladder-svg/test/palette.test.ts` does not reach this file. */
  .verdict-complies,
  .verdict-holds {
    color: var(--ladder-verdict-good);
  }
  .verdict-inbreach,
  .verdict-fails {
    color: var(--ladder-verdict-bad);
  }
  .verdict-undetermined,
  .verdict-notapplicable {
    color: var(--color-muted-foreground, rgba(0, 0, 0, 0.55));
  }

  .verdict-note {
    font-style: italic;
    color: var(--color-muted-foreground, rgba(0, 0, 0, 0.55));
  }

  .recompute-error {
    font-style: italic;
    color: var(--ladder-verdict-bad);
  }

  .icon-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 1.5rem;
    height: 1.5rem;
    padding: 0 0.375rem;
    border-radius: 0.25rem;
    border: 1px solid var(--color-border, rgba(0, 0, 0, 0.15));
    background: var(--color-background, white);
    color: inherit;
    cursor: pointer;
    font-size: 0.75rem;
    line-height: 1;
  }
  .icon-btn:hover {
    background: var(--color-accent, rgba(0, 0, 0, 0.06));
  }

  .ladder-svg-row {
    display: flex;
    gap: 0.75rem;
    flex: 1;
    min-height: 0;
  }

  /* The pan/zoom host needs a definite height; the controller sets overflow itself. */
  .ladder-host {
    flex: 1;
    min-width: 0;
    height: 100%;
    min-height: 0;
  }

  /* `{@html}`-injected SVG is NOT scoped-styled, so these must be :global. */
  :global(.ladder-host .lad-clickable) {
    cursor: pointer;
  }
  :global(.ladder-host .lad-box.lad-clickable:hover) {
    filter: brightness(0.97);
  }
  .ladder-host:focus-visible {
    outline: 1px dotted var(--color-border, rgba(0, 0, 0, 0.25));
    outline-offset: -4px;
  }
</style>
