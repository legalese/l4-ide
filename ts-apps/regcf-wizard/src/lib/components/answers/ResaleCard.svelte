<script lang="ts">
  import Outcome from './Outcome.svelte'
  import Disclosure from '../Disclosure.svelte'
  import type { ResaleAnswer } from '$lib/api/types'

  let { answer, onRestart }: { answer: ResaleAnswer; onRestart: () => void } =
    $props()

  const ok = $derived(answer['you may transfer'])
  const days = $derived(answer['days you must still wait'])
</script>

<Outcome
  tone={ok ? 'yes' : 'no'}
  word={ok ? 'You may transfer' : 'Not yet'}
  line={ok
    ? 'On these answers the transfer is permitted.'
    : `On these answers the transfer is restricted for another ${days} ${days === 1 ? 'day' : 'days'}.`}
/>

<section>
  <h2>Why</h2>
  <p>{answer.why}</p>
</section>

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
