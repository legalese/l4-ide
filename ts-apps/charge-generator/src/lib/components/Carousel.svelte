<script lang="ts">
  import { casefile } from '$lib/case/casefile.svelte'
  import ChargeCard from './ChargeCard.svelte'

  /** The carousel of charges: one card per punishing section proposed. */
  const n = $derived(casefile.charges.length)
  const go = (d: number): void => {
    if (n === 0) return
    casefile.selected = (casefile.selected + d + n) % n
  }
</script>

{#if n === 0}
  <p class="empty">
    No charge yet. Describe what happened on the left, or load a sample
    conversation, and the charges the Penal Code supports will appear here.
  </p>
{:else}
  <nav class="nav" aria-label="Charges">
    <button
      type="button"
      class="linkish"
      onclick={() => go(-1)}
      disabled={n < 2}>‹ previous</button
    >
    <ol class="dots">
      {#each casefile.charges as c, i (c.id)}
        <li>
          <button
            type="button"
            class="dot"
            class:on={i === casefile.selected}
            aria-current={i === casefile.selected ? 'true' : undefined}
            onclick={() => (casefile.selected = i)}
          >
            s {c.offence.section}
          </button>
        </li>
      {/each}
    </ol>
    <button type="button" class="linkish" onclick={() => go(1)} disabled={n < 2}
      >next ›</button
    >
  </nav>
  {#key casefile.current?.id}
    {#if casefile.current}
      <ChargeCard pc={casefile.current} />
      <p class="withdraw">
        <button
          type="button"
          class="linkish"
          onclick={() => casefile.withdraw(casefile.current!.offence.section)}
        >
          withdraw this charge
        </button>
      </p>
    {/if}
  {/key}
{/if}

<style>
  .empty {
    color: var(--muted);
  }
  .nav {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.6rem;
    margin-bottom: 0.8rem;
  }
  .dots {
    display: flex;
    gap: 0.35rem;
    list-style: none;
    margin: 0;
    padding: 0;
    flex-wrap: wrap;
  }
  .dot {
    border: 2px solid var(--hairline);
    border-radius: 999px;
    background: var(--surface);
    color: inherit;
    font: inherit;
    font-size: 0.85rem;
    padding: 0.1rem 0.6rem;
    cursor: pointer;
  }
  .dot.on {
    border-color: var(--brand);
    background: color-mix(in srgb, var(--brand) 10%, var(--surface));
    font-weight: 700;
  }
  .withdraw {
    margin: 0.6rem 0 0;
    font-size: 0.85rem;
  }
</style>
