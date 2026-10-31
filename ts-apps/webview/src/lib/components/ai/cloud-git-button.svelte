<script lang="ts">
  import type { AiCloudGitStatus } from 'jl4-client-rpc'
  import {
    CLONE_NOT_READY,
    type CloudConversationInfo,
  } from '$lib/stores/cloud-chat'

  // Clone / Sync for a cloud session's files (§9.3): in its header and
  // on the "Files changed" box of each turn.
  let {
    state,
    git,
    ready,
    busy,
    onClick,
  }: {
    /** The session's state: pushed changes wait for it to run. */
    state: CloudConversationInfo['state']
    git: AiCloudGitStatus | null
    /** The first turn is committed: there is something to clone. */
    ready: boolean
    busy: boolean
    /** Clone, or pull then push. */
    onClick: () => void
  } = $props()

  const label = $derived.by(() => {
    if (busy) return git?.kind === 'cloned' ? 'Syncing…' : 'Cloning…'
    if (!git || git.kind !== 'cloned') return 'Clone'
    const counts = [
      git.ahead > 0 ? `↑${git.ahead}` : '',
      git.behind > 0 ? `↓${git.behind}` : '',
    ]
      .filter(Boolean)
      .join(' ')
    return counts ? `Sync ${counts}` : 'Sync'
  })
  const can = $derived(ready && git?.kind !== 'not-ready')
  const title = $derived.by(() => {
    if (!can) return CLONE_NOT_READY
    if (!git) return "Clone this cloud session's files with git"
    if (git.kind === 'unavailable' || git.kind === 'not-ready') {
      return git.message
    }
    if (git.kind === 'not-cloned') {
      return "Clone this cloud session's files with git"
    }
    if (git.pending && state === 'sleeping') {
      return `Pushed changes are pending until the session runs. Clone: ${git.folder}`
    }
    return `Pull, then push your commits. Clone: ${git.folder}`
  })
</script>

<button
  type="button"
  class="git-btn"
  onclick={onClick}
  disabled={busy || !can || git?.kind === 'unavailable'}
  {title}
>
  <svg viewBox="0 0 16 16" aria-hidden="true" fill="none">
    <circle cx="4.5" cy="4" r="1.6" stroke="currentColor" stroke-width="1.3" />
    <circle cx="4.5" cy="12" r="1.6" stroke="currentColor" stroke-width="1.3" />
    <circle cx="11.5" cy="6" r="1.6" stroke="currentColor" stroke-width="1.3" />
    <path
      d="M4.5 5.6v4.8M11.5 7.6c0 2.2-2.5 2.4-7 2.8"
      stroke="currentColor"
      stroke-width="1.3"
      stroke-linecap="round"
    />
  </svg>
  <span>{label}</span>
  {#if git?.kind === 'cloned' && git.pending && state === 'sleeping'}
    <span class="pending">pending</span>
  {/if}
</button>

<style>
  .git-btn {
    display: inline-flex;
    flex-shrink: 0;
    align-items: center;
    gap: 4px;
    border: 1px solid var(--vscode-widget-border, rgba(128, 128, 128, 0.35));
    background: transparent;
    color: var(--vscode-descriptionForeground);
    padding: 1px 6px;
    font-size: 11px;
    font-weight: normal;
    border-radius: 3px;
    cursor: pointer;
  }
  .git-btn svg {
    width: 13px;
    height: 13px;
  }
  .git-btn:hover:not(:disabled) {
    color: var(--vscode-foreground);
    border-color: var(--vscode-foreground);
  }
  .git-btn:disabled {
    opacity: 0.5;
    cursor: default;
  }
  .pending {
    font-size: 9px;
    color: var(--vscode-editorWarning-foreground, #cca700);
  }
</style>
