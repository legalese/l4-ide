<script lang="ts">
  import { onMount } from 'svelte'
  import {
    SURFACES,
    LADDER_FN,
    SERVICE_BASE_URL,
    DEPLOYMENT_ID,
  } from '$lib/config'
  import type { Surface } from '$lib/config'
  import { fetchLadder } from '$lib/api/client'
  import Ladder from '$lib/components/Ladder.svelte'
  import SurfacePanel from '$lib/components/SurfacePanel.svelte'
  import ElicitPanel from '$lib/components/ElicitPanel.svelte'

  /**
   * THE ENTRY PAGE (SPEC.md §7 G3, "ladders embedded in the entry").
   *
   * It is a hub, not a form: the Reg CF corpus exports five decision surfaces
   * for two different audiences, and a single linear questionnaire would ask a
   * founder about resale restrictions and an investor about audited financials.
   * The hub picks the surface; the surface owns its own form and answer card.
   *
   * The ladder sits ON the hub because that is where a reader arrives. It is the
   * corpus's one boolean decision surface — measured: `GET …/{fn}/ladder` is 200
   * for `can this company raise` and 400 for the other five, which is the
   * service telling us a ladder is only defined for a DECIDE returning BOOLEAN.
   * Here it is static (no listeners, no pan/zoom); the interactive copy lives
   * inside the step-by-step surface, wired to the elicitation loop.
   */
  let selected = $state<Surface | null>(null)
  let funDecl = $state<unknown>(null)

  onMount(async () => {
    try {
      funDecl = await fetchLadder(LADDER_FN)
    } catch {
      // No picture is a degraded entry page, not a broken one. Every surface
      // still works, so this must never become an error state.
      funDecl = null
    }
  })

  function open(s: Surface): void {
    selected = s
  }
  function back(): void {
    selected = null
  }
</script>

{#if selected}
  <nav class="crumb">
    <button type="button" class="linkish" onclick={back}>
      ← All Regulation Crowdfunding checks
    </button>
  </nav>
  <h1 class="surface-title">{selected.title}</h1>
  {#if selected.kind === 'elicit'}
    <ElicitPanel fn={selected.fn} />
  {:else}
    <SurfacePanel surface={selected} />
  {/if}
{:else}
  <div class="intro">
    <h1>Regulation Crowdfunding, answered from the rules themselves</h1>
    <p>
      Every answer below is computed by running 17 CFR Part 227 as executable
      code — the same source text, formalised once, asked many ways. Nothing on
      this page is a hand-written summary of the law, and nothing is a
      hand-written number.
    </p>
  </div>

  {#if funDecl}
    <Ladder
      {funDecl}
      caption="The eligibility rule, drawn from the deployed code: a company may raise when it is an eligible issuer AND the raise is within the 12-month offering limit. Open the step-by-step check to answer it limb by limb."
    />
  {/if}

  <section class="surfaces">
    <h2>Pick your question</h2>
    {#each SURFACES as s (s.fn)}
      <button type="button" class="surface-card" onclick={() => open(s)}>
        <span class="audience"
          >{s.audience === 'founder' ? 'Company' : 'Investor'}</span
        >
        <span class="title">{s.title}</span>
        <span class="blurb">{s.blurb}</span>
      </button>
    {/each}
  </section>

  <p class="provenance">
    Answers come from deployment <code>{DEPLOYMENT_ID}</code> on
    <code>{SERVICE_BASE_URL}</code>.
  </p>
{/if}

<style>
  .intro h1 {
    font-size: 1.7rem;
    line-height: 1.22;
    margin: 0 0 0.8rem;
  }
  .intro p {
    margin: 0 0 1.6rem;
  }
  .surface-title {
    font-size: 1.5rem;
    line-height: 1.25;
    margin: 0 0 1rem;
  }
  .crumb {
    margin-bottom: 0.8rem;
  }
  .surfaces h2 {
    font-size: 1.05rem;
    margin: 0 0 0.8rem;
  }
  .surface-card {
    display: grid;
    gap: 0.25rem;
    width: 100%;
    text-align: left;
    border: 2px solid var(--hairline);
    border-radius: 12px;
    background: var(--surface);
    color: inherit;
    font: inherit;
    padding: 0.95rem 1.1rem;
    margin-bottom: 0.7rem;
    cursor: pointer;
  }
  .surface-card:hover {
    border-color: var(--brand);
  }
  .audience {
    font-size: 0.72rem;
    font-weight: 800;
    letter-spacing: 0.09em;
    text-transform: uppercase;
    color: var(--muted);
  }
  .title {
    font-size: 1.1rem;
    font-weight: 700;
  }
  .blurb {
    color: var(--muted);
    font-size: 0.95rem;
  }
  .provenance {
    margin-top: 2rem;
    color: var(--muted);
    font-size: 0.85rem;
  }
</style>
