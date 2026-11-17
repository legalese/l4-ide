<script lang="ts">
  import type { DeployReport } from '$lib/deploy-compat'
  import DefaultNotices from './default-notices.svelte'

  // What the sidebar says about changed defaults after a deploy job has
  // finished: from the service's report, or, if the service sent none, from the
  // list the review held before the deploy (and then it says so). A rejected
  // update changed nothing; the list is what it would have changed. A deploy
  // whose result could not be read may or may not have been applied, and the
  // banner says that instead of claiming either.
  let { report, onDismiss }: { report: DeployReport; onDismiss: () => void } =
    $props()
</script>

<div class="notice-banner" role="status">
  <div class="notice-banner-head">
    <span>
      {#if report.outcome === 'applied'}
        Defaults changed in <strong>{report.deploymentId}</strong>
      {:else if report.outcome === 'rejected'}
        Update of <strong>{report.deploymentId}</strong> rejected
      {:else}
        Deploy of <strong>{report.deploymentId}</strong>: result not read
      {/if}
    </span>
    <button
      class="notice-banner-close"
      title="Dismiss"
      aria-label="Dismiss"
      onclick={onDismiss}>&times;</button
    >
  </div>
  <p class="notice-banner-desc">
    {#if report.outcome === 'unknown'}
      The deploy may have been applied.
    {/if}
    {#if report.source === 'review'}
      Reported before the deploy; the service did not report them.
    {:else if report.source === 'unread'}
      Reported before the deploy; the result of the deploy could not be read.
    {/if}
    {#if report.outcome === 'applied'}
      A caller who leaves one of these inputs out now gets the new value.
    {:else if report.outcome === 'rejected'}
      Nothing changed. The update would have changed these defaults:
    {/if}
  </p>
  <DefaultNotices
    items={report.notices}
    schemas={report.schemas}
    mood={report.outcome === 'applied'
      ? 'will'
      : report.outcome === 'rejected'
        ? 'would'
        : 'maybe'}
  />
</div>

<style>
  .notice-banner {
    flex-shrink: 0;
    margin-bottom: 12px;
    padding: 10px 12px;
    background: var(
      --vscode-textBlockQuote-background,
      rgba(127, 127, 127, 0.1)
    );
    border-radius: 4px;
    font-size: 0.9em;
    line-height: 1.45;
  }

  .notice-banner-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .notice-banner-close {
    background: none;
    border: none;
    padding: 0 2px;
    color: var(--vscode-descriptionForeground);
    cursor: pointer;
    font-size: 1.2em;
    line-height: 1;
  }

  .notice-banner-close:hover {
    color: var(--vscode-foreground);
  }

  .notice-banner-desc {
    margin: 4px 0 6px;
    color: var(--vscode-descriptionForeground);
  }
</style>
