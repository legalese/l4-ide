<script lang="ts">
  import Outcome from './Outcome.svelte'
  import Disclosure from '../Disclosure.svelte'
  import { money } from '$lib/lawtime'
  import type { RaiseAssessment } from '$lib/api/types'

  let {
    answer,
    onRestart,
  }: { answer: RaiseAssessment; onRestart: () => void } = $props()

  const ok = $derived(answer['you can use Reg CF'])
</script>

<Outcome
  tone={ok ? 'yes' : 'no'}
  word={ok ? 'You qualify' : 'You do not qualify'}
  line={ok
    ? `On these answers the company is eligible and the raise is within the 12-month limit. The most you can raise now is ${money(answer['the most you can raise now'])}.`
    : `On these answers the raise cannot proceed under Regulation Crowdfunding as described. Your remaining 12-month headroom is ${money(answer['the most you can raise now'])}.`}
/>

{#if answer.blockers.length > 0}
  <section class="blockers">
    <h2>What stops you</h2>
    <ul>
      {#each answer.blockers as b (b)}
        <li>{b}</li>
      {/each}
    </ul>
  </section>
{/if}

<section class="finstat">
  <h2>Financial statements you must provide</h2>
  <p class="lead">{answer['financial statements you must provide']}</p>
  <p class="citation">{answer['why those financial statements']}</p>
</section>

<Disclosure
  summary="What you must still line up"
  count={answer['what you must still line up'].length}
>
  <ul>
    {#each answer['what you must still line up'] as item (item)}
      <li>{item}</li>
    {/each}
  </ul>
</Disclosure>

<Disclosure
  summary="What you owe once the offering closes"
  count={answer['after you raise you must'].length}
>
  <ul>
    {#each answer['after you raise you must'] as item (item)}
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

<!-- Ruling R8's disclosure for the founder surface. The engine states the date
     as at which it answered; the page repeats it verbatim rather than deriving
     one, because only the corpus knows which figures are dated. -->
<p class="as-at">{answer['law as in force']}</p>

<button type="button" class="linkish" onclick={onRestart}>
  Change my answers
</button>

<style>
  h2 {
    font-size: 1.05rem;
    margin: 0 0 0.5rem;
  }
  .blockers {
    margin-bottom: 1.4rem;
  }
  .finstat {
    margin-bottom: 1.2rem;
  }
  .lead {
    font-weight: 700;
    margin: 0 0 0.35rem;
  }
  .citation {
    font-size: 0.95rem;
    margin: 0;
  }
  .as-at {
    border-top: 1px solid var(--hairline);
    margin-top: 1.2rem;
    padding-top: 0.9rem;
    color: var(--muted);
    font-size: 0.9rem;
  }
</style>
