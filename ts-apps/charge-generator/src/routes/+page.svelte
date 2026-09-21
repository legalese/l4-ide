<script lang="ts">
  import { SERVICE_BASE_URL, DEPLOYMENT_ID } from '$lib/config'
  import Interview from '$lib/components/Interview.svelte'
  import Carousel from '$lib/components/Carousel.svelte'
</script>

<div class="panes">
  <section class="pane" aria-label="Interview">
    <div class="pane-head">
      <h2>Interview</h2>
      <span class="muted">the officer's account, and what it rests on</span>
    </div>
    <div class="pane-body">
      <Interview />
    </div>
  </section>

  <section class="pane" aria-label="Charges">
    <div class="pane-head">
      <h2>Charges</h2>
      <span class="muted"
        >each section drawn, each charge framed by the encoded law</span
      >
    </div>
    <div class="pane-body">
      <Carousel />
    </div>
  </section>
</div>

<p class="provenance">
  Charges are framed by deployment <code>{DEPLOYMENT_ID}</code> on
  <code>{SERVICE_BASE_URL}</code>, from the Penal Code 1871 encoded in L4.
</p>

<style>
  .muted {
    color: var(--muted);
    font-size: 0.85rem;
  }
  .provenance {
    color: var(--muted);
    font-size: 0.85rem;
    margin-top: 1rem;
  }
</style>
