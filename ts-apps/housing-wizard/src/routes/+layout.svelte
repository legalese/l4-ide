<script lang="ts">
  import '../app.css'
  import HelpFooter from '$lib/components/HelpFooter.svelte'

  let { children } = $props()
</script>

<div class="top-bar">
  <div class="bar-inner">
    <span class="bar-title">Rent-arrears eviction check</span>
    <span class="bar-trust">Free and private — nothing you type is saved</span>
  </div>
</div>

<main>
  {@render children()}
  <HelpFooter />
</main>

<style>
  .top-bar {
    border-bottom: 1px solid var(--hairline);
    background: var(--surface);
  }
  .bar-inner {
    max-width: 640px;
    margin: 0 auto;
    padding: 0.8rem 1.1rem;
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    justify-content: space-between;
    gap: 0.3rem 1rem;
  }
  .bar-title {
    font-weight: 700;
    color: var(--brand-dark);
  }
  .bar-trust {
    color: var(--muted);
    font-size: 0.85rem;
  }
  main {
    max-width: 640px;
    margin: 0 auto;
    padding: 1.5rem 1.1rem 0;
  }
</style>
