<script lang="ts">
  import Outcome from './Outcome.svelte'
  import Disclosure from '../Disclosure.svelte'
  import type { ReportingExitAnswer } from '$lib/api/types'

  let {
    answer,
    onRestart,
  }: { answer: ReportingExitAnswer; onRestart: () => void } = $props()

  const ok = $derived(answer['you may stop reporting'])
  const met = $derived(answer['the conditions that let you stop'])
</script>

<Outcome
  tone={ok ? 'yes' : 'no'}
  word={ok ? 'The duty may end' : 'The duty still runs'}
  line={ok
    ? 'One of the five Rule 202(b) conditions has occurred. It does not end by itself — filing the Form C-TR is what ends it.'
    : 'None of the five Rule 202(b) conditions has occurred, so the annual reporting duty stands.'}
/>

{#if met.length > 0}
  <section>
    <h2>The conditions you meet</h2>
    <ul>
      {#each met as item (item)}
        <li>{item}</li>
      {/each}
    </ul>
  </section>
{/if}

<Disclosure
  summary="What you owe for as long as the duty stands"
  count={answer['while the duty runs you must'].length}
  open={!ok}
>
  <ul>
    {#each answer['while the duty runs you must'] as item (item)}
      <li>{item}</li>
    {/each}
  </ul>
</Disclosure>

<Disclosure
  summary="Where this model is thinner than the law"
  count={answer.caveats.length}
>
  <ul>
    {#each answer.caveats as item (item)}
      <li>{item}</li>
    {/each}
  </ul>
</Disclosure>

<button type="button" class="linkish" onclick={onRestart}>
  Change my answers
</button>

<style>
  h2 {
    font-size: 1.05rem;
    margin: 0 0 0.5rem;
  }
  section {
    margin-bottom: 1.2rem;
  }
</style>
