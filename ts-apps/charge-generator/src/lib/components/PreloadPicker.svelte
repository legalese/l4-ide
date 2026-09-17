<script lang="ts">
  import type { Preload } from '$lib/interview/preload'

  /**
   * "Load a sample" — cycles through the canned conversations. Picking one
   * puts its prompt in the composer; the interview then recognises it and
   * replays without the model (Meng, 2026-09-17).
   */
  let {
    preloads,
    onPick,
  }: { preloads: readonly Preload[]; onPick: (p: Preload) => void } = $props()

  let i = $state(0)
  const current = $derived(preloads[i])

  function next(d: number): void {
    i = (i + d + preloads.length) % preloads.length
  }
</script>

{#if preloads.length > 0}
  <div class="picker">
    <button
      type="button"
      class="linkish"
      onclick={() => next(-1)}
      aria-label="Previous sample">‹</button
    >
    <button type="button" class="sample" onclick={() => onPick(current)}>
      <span class="title">Load sample: {current.title}</span>
      <span class="cite">{current.citation}</span>
    </button>
    <button
      type="button"
      class="linkish"
      onclick={() => next(1)}
      aria-label="Next sample">›</button
    >
  </div>
{/if}

<style>
  .picker {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }
  .sample {
    flex: 1;
    display: grid;
    text-align: left;
    border: 1px dashed var(--hairline);
    border-radius: 10px;
    background: var(--surface-sunk);
    color: inherit;
    font: inherit;
    padding: 0.45rem 0.7rem;
    cursor: pointer;
  }
  .sample:hover {
    border-color: var(--brand);
  }
  .title {
    font-size: 0.92rem;
    font-weight: 600;
  }
  .cite {
    font-size: 0.8rem;
    color: var(--muted);
  }
</style>
