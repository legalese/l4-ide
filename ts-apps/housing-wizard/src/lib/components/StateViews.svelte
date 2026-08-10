<script lang="ts">
  let {
    kind,
    message,
    errorKind,
    onRetry,
  }: {
    kind: 'loading' | 'schemaError' | 'evalError'
    message?: string
    errorKind?: 'network' | 'service'
    onRetry?: () => void
  } = $props()

  const lead = $derived(
    errorKind === 'network'
      ? 'Please check your internet connection and try again.'
      : (message ?? 'Something went wrong.')
  )
</script>

{#if kind === 'loading'}
  <div class="state" aria-live="polite">
    <div class="spinner" aria-hidden="true"></div>
    <p>Loading your questions from the legislation…</p>
  </div>
{:else if kind === 'schemaError'}
  <div class="state" role="alert">
    <h2>We couldn’t load the questions right now</h2>
    <p>{lead}</p>
    {#if onRetry}
      <button type="button" class="submit" onclick={onRetry}>Try again</button>
    {/if}
  </div>
{:else}
  <div class="state banner" role="alert">
    <p><strong>We couldn’t work out your answer just now.</strong></p>
    <p>{lead}</p>
    {#if onRetry}
      <button type="button" class="submit" onclick={onRetry}>
        Back to my answers
      </button>
    {/if}
  </div>
{/if}

<style>
  .state {
    padding: 1.5rem 0;
  }
  .state h2 {
    font-size: 1.2rem;
    margin: 0 0 0.5rem;
  }
  .banner {
    border: 2px solid var(--may-border);
    background: var(--may-bg);
    color: var(--may-fg);
    border-radius: 10px;
    padding: 1rem 1.2rem;
    margin-bottom: 1.5rem;
  }
  .spinner {
    width: 28px;
    height: 28px;
    border: 3px solid var(--hairline);
    border-top-color: var(--brand);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
    margin-bottom: 0.75rem;
  }
  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
