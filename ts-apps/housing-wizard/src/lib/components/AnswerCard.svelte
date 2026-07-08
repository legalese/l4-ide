<script lang="ts">
  import { onMount } from 'svelte'
  import { DEPLOYMENT_ID, FUNCTION_NAME } from '$lib/config'
  import type { FieldNode } from '$lib/schema/types'
  import type {
    ExportedFunctionInfo,
    PossessionAssessment,
    FormState,
    FormValue,
  } from '$lib/api/types'

  let {
    assessment,
    info,
    facts,
    root,
    onRestart,
  }: {
    assessment: PossessionAssessment
    info: ExportedFunctionInfo
    facts: FormState
    root: FieldNode
    onRestart: () => void
  } = $props()

  // Outcome is derived PURELY from the engine's booleans — never parsed from the
  // rule text — so the card can never drift from the rules.
  const canOrder = $derived(assessment['possession can be ordered'])
  const mandatory = $derived(assessment['it is mandatory'])
  const mode = $derived(!canOrder ? 'clear' : mandatory ? 'must' : 'may')

  const headline = $derived(
    mode === 'clear'
      ? 'Good news — on the information you gave, the landlord has no rent-arrears ground to evict you.'
      : mode === 'must'
        ? 'This is serious — if your landlord proves this, the court would have to order possession.'
        : 'A court could order possession — but only if it decides that is reasonable.'
  )

  const grounds = $derived(assessment['grounds made out'])
  const reasons = $derived(
    assessment.reasons.filter((r) => r.trim().length > 0)
  )

  let cardEl: HTMLElement | null = $state(null)
  onMount(() => cardEl?.focus())

  function isState(v: FormValue): v is FormState {
    return typeof v === 'object' && v !== null && !Array.isArray(v)
  }

  function formatValue(node: FieldNode, v: FormValue): string {
    if (node.widget === 'boolean')
      return v === true ? 'Yes' : v === false ? 'No' : '—'
    if (node.widget === 'number')
      return v === null || v === undefined ? '—' : String(v)
    return v === '' || v === null || v === undefined ? '—' : String(v)
  }

  function collectFacts(
    node: FieldNode,
    slice: FormState
  ): { label: string; value: string }[] {
    const rows: { label: string; value: string }[] = []
    for (const child of node.children) {
      const v = slice[child.key]
      if (child.widget === 'object' && isState(v)) {
        rows.push(...collectFacts(child, v))
      } else {
        rows.push({ label: child.label, value: formatValue(child, v) })
      }
    }
    return rows
  }

  const factRows = $derived(collectFacts(root, facts))
</script>

<section
  class="card"
  class:outcome-clear={mode === 'clear'}
  class:outcome-must={mode === 'must'}
  class:outcome-may={mode === 'may'}
  aria-live="polite"
  tabindex="-1"
  bind:this={cardEl}
>
  <h1 class="sr-only">Your rent-arrears eviction check result</h1>
  <h2 class="headline">{headline}</h2>

  {#if mode === 'must'}
    <p class="badge badge-must">
      <svg class="badge-icon" viewBox="0 0 24 24" aria-hidden="true">
        <path
          fill="currentColor"
          d="M12 2 2 7l10 5 10-5-10-5Zm0 7.2L5.5 6 12 3.8 18.5 6 12 9.2ZM4 9v6l8 4 8-4V9l-2 1v4l-6 3-6-3v-4L4 9Z"
        />
      </svg>
      <span class="badge-word">MUST</span>
      <span class="badge-gloss">
        Mandatory ground — if it is proved, the court must order possession
        (Ground 8).
      </span>
      <span class="sr-only">This is a mandatory ground for possession.</span>
    </p>
  {:else if mode === 'may'}
    <p class="badge badge-may">
      <svg class="badge-icon" viewBox="0 0 24 24" aria-hidden="true">
        <path
          fill="currentColor"
          d="M12 2a1 1 0 0 1 1 1v1.1l6 1.5.5 1.9-2 5a3 3 0 0 1-5.9 0l-1.4-3.6L9 13a3 3 0 0 1-5.9 0l-2-5 .5-1.9 6-1.5V3a1 1 0 0 1 1-1Zm6 4.6-1.7 4.3h3.4L18 6.6Zm-12 0L4.3 10.9h3.4L6 6.6ZM11 5.4v12.1H7v2h10v-2h-4V5.4Z"
        />
      </svg>
      <span class="badge-word">MAY</span>
      <span class="badge-gloss">
        Discretionary ground — the court may order possession only if it thinks
        it is reasonable.
      </span>
      <span class="sr-only">This is a discretionary ground for possession.</span
      >
    </p>
  {/if}

  <p class="summary-line">{assessment['what this means']}</p>

  {#if grounds.length > 0}
    <div class="grounds" aria-label="Grounds made out">
      {#each grounds as g (g)}
        <span class="chip">{g}</span>
      {/each}
    </div>
  {/if}

  {#if reasons.length > 0}
    <div class="reasons">
      <h3>Why</h3>
      <ul>
        {#each reasons as r (r)}
          <li>{r}</li>
        {/each}
      </ul>
    </div>
  {/if}

  <div class="next">
    {#if mode === 'must'}
      <h3>What to do now</h3>
      <p>
        Get advice <strong>today</strong> — a mandatory ground is serious, but an
        adviser can check the notice, the figures and the dates, which often matter.
      </p>
    {:else if mode === 'may'}
      <h3>You have options</h3>
      <p>
        Because this is discretionary, you can put your side to the court — for
        example a repayment offer, your circumstances, or errors in the claim.
      </p>
    {:else}
      <h3>Keep your evidence</h3>
      <p>
        Keep your rent records safe. This check only covers the rent-arrears
        grounds (8, 10 and 11) — a landlord could still rely on a different
        ground.
      </p>
    {/if}
  </div>

  <details class="provenance">
    <summary>How was this worked out?</summary>
    <p class="prov-intro">Your answers:</p>
    <dl>
      {#each factRows as row (row.label)}
        <div class="prov-row">
          <dt>{row.label}</dt>
          <dd>{row.value}</dd>
        </div>
      {/each}
    </dl>
    <p class="prov-source citation">
      Computed by the L4 rules deployment <code>{DEPLOYMENT_ID}</code>, function
      <code>{FUNCTION_NAME}</code>, returning <code>{info.returnType}</code> — the
      same encoding a drafter authors generated this form and this answer.
    </p>
  </details>

  <button type="button" class="restart" onclick={onRestart}
    >Change my answers</button
  >
</section>

<style>
  .card {
    border: 2px solid;
    border-radius: 14px;
    padding: 1.5rem 1.4rem;
    margin: 1rem 0 0;
  }
  .card:focus-visible {
    outline: 3px solid var(--focus);
    outline-offset: 3px;
  }
  .headline {
    font-size: 1.4rem;
    line-height: 1.3;
    margin: 0 0 1rem;
  }
  .badge {
    display: grid;
    grid-template-columns: auto auto;
    align-items: center;
    gap: 0.3rem 0.6rem;
    margin: 0 0 1rem;
  }
  .badge-icon {
    width: 1.8rem;
    height: 1.8rem;
    grid-row: span 2;
  }
  .badge-word {
    font-size: 1.5rem;
    font-weight: 800;
    letter-spacing: 0.04em;
  }
  .badge-gloss {
    grid-column: 2;
    font-size: 0.95rem;
    font-weight: 500;
  }
  .badge-must {
    color: var(--must-fg);
  }
  .badge-may {
    color: var(--may-fg);
  }
  .summary-line {
    font-size: 1.15rem;
    font-weight: 600;
    margin: 0 0 1.1rem;
  }
  .grounds {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    margin-bottom: 1.1rem;
  }
  .chip {
    border-radius: 999px;
    padding: 0.3rem 0.8rem;
    font-size: 0.9rem;
    font-weight: 600;
  }
  .reasons h3,
  .next h3 {
    font-size: 1.05rem;
    margin: 0 0 0.4rem;
  }
  .reasons ul {
    margin: 0 0 1.1rem;
    padding-left: 1.2rem;
  }
  .reasons li {
    margin-bottom: 0.6rem;
  }
  .next {
    margin-bottom: 1.2rem;
  }
  .provenance {
    border-top: 1px solid var(--hairline);
    padding-top: 0.8rem;
    margin-bottom: 1.2rem;
  }
  .provenance summary {
    cursor: pointer;
    font-weight: 600;
  }
  .prov-intro {
    margin: 0.6rem 0 0.3rem;
    font-weight: 600;
  }
  .prov-row {
    display: flex;
    justify-content: space-between;
    gap: 1rem;
    padding: 0.3rem 0;
    border-bottom: 1px solid var(--hairline);
  }
  .prov-row dt {
    color: var(--muted);
  }
  .prov-row dd {
    margin: 0;
    font-weight: 600;
    text-align: right;
  }
  .prov-source {
    font-size: 0.85rem;
    margin-top: 0.7rem;
  }
  .prov-source code {
    font-family: ui-monospace, monospace;
  }
  .restart {
    background: transparent;
    border: 2px solid currentColor;
    border-radius: 10px;
    padding: 0.6rem 1.1rem;
    font-weight: 700;
    cursor: pointer;
    color: inherit;
  }
  .sr-only {
    position: absolute;
    width: 1px;
    height: 1px;
    padding: 0;
    margin: -1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
    border: 0;
  }
</style>
