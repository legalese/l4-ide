<script lang="ts">
  import { onMount } from 'svelte'
  import { queryPlan, fetchLadder, NetworkError } from '$lib/api/client'
  import { LADDER_FN } from '$lib/config'
  import {
    bindKey,
    humaniseAtom,
    isSettled,
    nextAsk,
    verdictHeadline,
    verdictTone,
  } from '$lib/elicit/plan'
  import Ladder from './Ladder.svelte'
  import StateViews from './StateViews.svelte'
  import type { PlanAtom, QueryPlanResponse } from '$lib/api/types'
  import type { UBoolValue } from '@repo/ladder-core'

  /**
   * Progressive disclosure, which CORPUS-TRACK.md §3.5 records as the one part of
   * the loop that "does not exist client-side at all — the backend loop is
   * finished and unexercised". This is the exercise.
   *
   * One question at a time, in the service's own ranked order, restricted to
   * what is still needed; the loop stops the moment the VERDICT settles, so the
   * remaining questions are never put. That early stop is the observable
   * difference from a form, and it is why the ranking is worth having.
   */
  let { fn }: { fn: string } = $props()

  type Phase = 'loading' | 'asking' | 'settled' | 'error'

  let phase = $state<Phase>('loading')
  let plan = $state<QueryPlanResponse | null>(null)
  let funDecl = $state<unknown>(null)
  let bindings = $state<Record<string, boolean>>({})
  let errorMsg = $state<string | null>(null)
  let errorKind = $state<'network' | 'service'>('service')
  let busy = $state(false)

  const ask = $derived(plan ? nextAsk(plan) : null)

  /** The picture's valuation, keyed by `unique` — derived from the bindings the
   *  client sent, never from the ladder payload's own leaf values (which stay
   *  `UnknownV` regardless of what is bound). */
  const valuationByUnique = $derived.by(() => {
    const m = new Map<number, UBoolValue>()
    for (const [k, v] of Object.entries(bindings)) {
      m.set(Number(k), v ? 'TrueV' : 'FalseV')
    }
    return m
  })

  /** Everything the plan has ever named, so answered atoms can be listed back. */
  const known = $derived.by(() => {
    const m = new Map<number, string>()
    for (const a of plan?.ranked ?? []) m.set(a.unique, humaniseAtom(a.label))
    for (const a of plan?.stillNeeded ?? [])
      m.set(a.unique, humaniseAtom(a.label))
    return m
  })

  const answered = $derived(
    Object.entries(bindings).map(([k, v]) => ({
      unique: Number(k),
      label: known.get(Number(k)) ?? `Atom ${k}`,
      value: v,
    }))
  )

  async function refresh(next: Record<string, boolean>): Promise<void> {
    busy = true
    try {
      const p = await queryPlan(fn, next)
      bindings = next
      plan = p
      phase = isSettled(p.verdict) ? 'settled' : 'asking'
    } catch (e) {
      errorMsg = e instanceof Error ? e.message : 'Something went wrong.'
      errorKind = e instanceof NetworkError ? 'network' : 'service'
      phase = 'error'
    } finally {
      busy = false
    }
  }

  onMount(async () => {
    // The diagram is optional garnish for the loop: if it fails we still ask the
    // questions. Only the plan is load-bearing.
    if (fn === LADDER_FN) {
      try {
        funDecl = await fetchLadder(fn)
      } catch {
        funDecl = null
      }
    }
    await refresh({})
  })

  function answer(atom: PlanAtom, v: boolean): void {
    void refresh({ ...bindings, [bindKey(atom)]: v })
  }

  /** Clicking a box on the diagram cycles that atom U -> T -> F -> U. This is the
   *  only way to UNDO an answer, and it is why the picture is interactive. */
  function cycle(unique: number): void {
    const k = String(unique)
    const next = { ...bindings }
    if (!(k in next)) next[k] = true
    else if (next[k]) next[k] = false
    else delete next[k]
    void refresh(next)
  }

  function restart(): void {
    void refresh({})
  }
</script>

{#if phase === 'loading'}
  <StateViews kind="loading" />
{:else if phase === 'error'}
  <StateViews
    kind="schemaError"
    message={errorMsg ?? undefined}
    {errorKind}
    onRetry={restart}
  />
{:else if plan}
  {#if funDecl}
    <Ladder
      {funDecl}
      {valuationByUnique}
      interactive={true}
      onToggle={cycle}
      caption="Every box is a limb of the rule. Click one to change or clear your answer; the wire lights up as current reaches the end."
    />
  {/if}

  {#if phase === 'settled'}
    <div
      class="verdict"
      class:outcome-clear={verdictTone(plan.verdict) === 'yes'}
      class:outcome-must={verdictTone(plan.verdict) === 'no'}
      class:outcome-may={verdictTone(plan.verdict) === 'neither'}
      role="status"
    >
      <p class="verdict-word">{plan.verdict}</p>
      <p class="verdict-line">{verdictHeadline(plan.verdict)}</p>
      <p class="verdict-note">
        Settled after {answered.length}
        {answered.length === 1 ? 'question' : 'questions'}. We stopped asking
        because nothing still unanswered can change the answer.
      </p>
    </div>
  {:else if ask}
    <div class="ask">
      <p class="ask-kicker">Question {answered.length + 1}</p>
      <h2 class="ask-text">{humaniseAtom(ask.label)}?</h2>
      <div class="ask-buttons">
        <button
          type="button"
          class="submit"
          disabled={busy}
          onclick={() => answer(ask, true)}>Yes</button
        >
        <button
          type="button"
          class="submit secondary"
          disabled={busy}
          onclick={() => answer(ask, false)}>No</button
        >
      </div>
      <p class="help">
        Still to settle: {plan.stillNeeded.length}
        {plan.stillNeeded.length === 1 ? 'limb' : 'limbs'}.
      </p>
    </div>
  {:else}
    <p class="help">
      The rules service has no further question, and has not settled the answer
      either. Nothing here is safe to report as a result.
    </p>
  {/if}

  {#if answered.length > 0}
    <section class="answered">
      <h3>What you have told us</h3>
      <ul>
        {#each answered as a (a.unique)}
          <li>
            <span class="chip">{a.value ? 'Yes' : 'No'}</span>
            {a.label}
          </li>
        {/each}
      </ul>
      <button type="button" class="linkish" onclick={restart}>
        Start these questions again
      </button>
    </section>
  {/if}
{/if}

<style>
  .verdict {
    border: 2px solid var(--hairline);
    border-radius: 12px;
    padding: 1.1rem 1.3rem;
    margin-bottom: 1.5rem;
  }
  .verdict-word {
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-size: 0.8rem;
    font-weight: 700;
    margin: 0 0 0.4rem;
  }
  .verdict-line {
    font-size: 1.15rem;
    font-weight: 700;
    margin: 0 0 0.5rem;
  }
  .verdict-note {
    margin: 0;
    font-size: 0.95rem;
  }
  .ask {
    margin-bottom: 1.5rem;
  }
  .ask-kicker {
    color: var(--muted);
    font-size: 0.85rem;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    margin: 0 0 0.3rem;
  }
  .ask-text {
    font-size: 1.3rem;
    line-height: 1.3;
    margin: 0 0 1rem;
  }
  .ask-buttons {
    display: flex;
    gap: 0.7rem;
    margin-bottom: 0.7rem;
  }
  .answered {
    border-top: 1px solid var(--hairline);
    padding-top: 1rem;
  }
  .answered h3 {
    font-size: 1rem;
    margin: 0 0 0.6rem;
  }
  .answered ul {
    list-style: none;
    margin: 0 0 0.8rem;
    padding: 0;
  }
  .answered li {
    margin-bottom: 0.4rem;
  }
</style>
