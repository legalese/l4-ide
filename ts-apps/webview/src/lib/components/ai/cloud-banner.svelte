<script lang="ts">
  import type { CloudConversationInfo } from '$lib/stores/ai-chat.svelte'

  // Header of a cloud conversation (§12.2): state, start progress,
  // Resume for parked sessions / auth-required, Stop, and notices
  // (merge conflicts, command errors).
  let {
    cloud,
    onResume,
    onStop,
  }: {
    cloud: CloudConversationInfo
    onResume: () => void
    onStop: () => void
  } = $props()

  const live = $derived(
    cloud.state === 'running' ||
      cloud.state === 'busy' ||
      cloud.state === 'waiting' ||
      cloud.state === 'starting'
  )
  const needsResume = $derived(
    !!cloud.sessionId &&
      (cloud.state === 'parked' ||
        (!!cloud.authRequired && cloud.authRequired.reason !== 'mcp'))
  )
  const progressText = $derived(
    cloud.progress === 'adding-files'
      ? `Adding ${cloud.addingFiles} ${cloud.addingFiles === 1 ? 'file' : 'files'} to the session…`
      : cloud.progress === 'uploading'
        ? 'Uploading files…'
        : cloud.progress === 'starting' || cloud.state === 'starting'
          ? 'Starting cloud compute (this can take up to a minute)…'
          : null
  )
</script>

<div class="cloud-banner" role="status">
  <div class="line">
    <svg class="cloud-icon" viewBox="0 0 16 16" aria-hidden="true">
      <path
        d="M4.6 12.5a2.6 2.6 0 0 1-.3-5.2 3.4 3.4 0 0 1 6.6-1 2.7 2.7 0 0 1 .6 6.2z"
        stroke="currentColor"
        stroke-width="1.2"
        fill="none"
        stroke-linejoin="round"
      />
    </svg>
    <span class="label">Cloud session</span>
    {#if cloud.sessionId}
      <span class="state state-{cloud.state}">{cloud.state}</span>
    {/if}
    <span class="spacer"></span>
    {#if needsResume}
      <button class="btn primary" onclick={onResume}>Resume</button>
    {:else if live && cloud.sessionId}
      <button class="btn" onclick={onStop} title="Stop the cloud compute"
        >Stop</button
      >
    {/if}
  </div>
  {#if progressText}
    <div class="detail">{progressText}</div>
    {#if cloud.mcpServers.length > 0 && cloud.progress !== 'adding-files'}
      <div class="detail">
        MCP servers passed to this session: {cloud.mcpServers.join(', ')}. Their
        tools run without approval in the cloud.
      </div>
    {/if}
  {/if}
  {#if cloud.authRequired?.reason === 'mcp'}
    <div class="detail warn">
      MCP server {cloud.authRequired.server ?? ''} needs a sign-in in this window
      before the cloud session can use it.
    </div>
  {:else if needsResume}
    <div class="detail warn">
      The session paused because its credentials ran out. Resume starts it
      again.
    </div>
  {/if}
  {#if cloud.mergeConflict}
    <div class="detail warn">
      Your synced changes conflict with the session's and were not merged:
      {cloud.mergeConflict.join(', ')}. Resolve them in your clone and sync
      again.
    </div>
  {/if}
  {#if cloud.notice}
    <div class="detail error">{cloud.notice}</div>
  {/if}
</div>

<style>
  .cloud-banner {
    display: flex;
    flex-direction: column;
    gap: 3px;
    padding: 5px 10px;
    border-bottom: 1px solid
      var(--vscode-widget-border, rgba(128, 128, 128, 0.3));
    font-size: 11px;
    color: var(--vscode-descriptionForeground);
  }
  .line {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .cloud-icon {
    width: 14px;
    height: 14px;
  }
  .label {
    color: var(--vscode-foreground);
  }
  .state {
    font-size: 9px;
    padding: 1px 4px;
    border-radius: 3px;
    border: 1px solid var(--vscode-widget-border, rgba(128, 128, 128, 0.4));
  }
  .state-busy,
  .state-starting {
    color: #c8376a;
    border-color: #c8376a;
  }
  .state-parked,
  .state-waiting {
    color: var(--vscode-editorWarning-foreground, #cca700);
    border-color: var(--vscode-editorWarning-foreground, #cca700);
  }
  .spacer {
    flex: 1;
  }
  .btn {
    border: 1px solid var(--vscode-widget-border, rgba(128, 128, 128, 0.35));
    background: transparent;
    color: var(--vscode-foreground);
    padding: 1px 10px;
    font-size: 11px;
    border-radius: 3px;
    cursor: pointer;
  }
  .btn.primary {
    background: #c8376a;
    border-color: transparent;
    color: #fff;
  }
  .detail.warn {
    color: var(--vscode-editorWarning-foreground, #cca700);
  }
  .detail.error {
    color: var(--vscode-errorForeground, #d7263d);
  }
</style>
