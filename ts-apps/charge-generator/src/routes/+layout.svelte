<script lang="ts">
  import '../app.css'
  let { children } = $props()
</script>

<div class="top-bar">
  <div class="bar-inner">
    <span class="bar-title">Charge generator — Penal Code 1871</span>
    <span class="bar-trust"
      >Proof of concept. Every charge is framed by the encoded section, not by
      the assistant.</span
    >
  </div>
</div>

<main>
  {@render children()}
</main>

<style>
  .top-bar {
    border-bottom: 1px solid var(--hairline);
    background: var(--surface);
  }
  .bar-inner {
    max-width: 88rem;
    margin: 0 auto;
    padding: 0.7rem 1.1rem;
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
    max-width: 88rem;
    margin: 0 auto;
    padding: 1.2rem 1.1rem 2rem;
  }
</style>
