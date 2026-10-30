<script lang="ts">
  import type { AiCloudGitStatus } from 'jl4-client-rpc'
  import type { CloudConversationInfo } from '$lib/stores/ai-chat.svelte'
  import { CLONE_NOT_READY } from '$lib/stores/cloud-chat'
  import CloudStatusIcon from './cloud-status-icon.svelte'

  // Header of a cloud conversation (§12.2): the cloud (state and
  // progress, in its tooltip), the name, Clone / Sync and the session
  // menu (Stop). No text lines: what needs the user goes on the thing
  // to act on, failures and conflicts are VS Code notifications.
  let {
    cloud,
    title,
    git,
    gitReady,
    onStop,
    onGit,
  }: {
    cloud: CloudConversationInfo
    /** The session's name; "Cloud session" until it has one. */
    title: string | null
    /** Clone / Sync state of the session's files (§9.3). */
    git: AiCloudGitStatus | null
    /** The first turn is committed: there is something to clone. */
    gitReady: boolean
    onStop: () => void
    /** Clone, or pull then push. */
    onGit: () => Promise<void>
  } = $props()

  let gitBusy = $state(false)
  const gitLabel = $derived.by(() => {
    if (gitBusy) return git?.kind === 'cloned' ? 'Syncing…' : 'Cloning…'
    if (!git || git.kind !== 'cloned') return 'Clone'
    const counts = [
      git.ahead > 0 ? `↑${git.ahead}` : '',
      git.behind > 0 ? `↓${git.behind}` : '',
    ]
      .filter(Boolean)
      .join(' ')
    return counts ? `Sync ${counts}` : 'Sync'
  })
  const canGit = $derived(gitReady && git?.kind !== 'not-ready')
  const gitTitle = $derived.by(() => {
    if (!canGit) return CLONE_NOT_READY
    if (!git) return "Clone this cloud session's files with git"
    if (git.kind === 'unavailable' || git.kind === 'not-ready') {
      return git.message
    }
    if (git.kind === 'not-cloned') {
      return "Clone this cloud session's files with git"
    }
    if (git.pending && cloud.state === 'sleeping') {
      return `Pushed changes are pending until the session runs. Clone: ${git.folder}`
    }
    return `Pull, then push your commits. Clone: ${git.folder}`
  })

  async function gitAction(): Promise<void> {
    if (gitBusy) return
    gitBusy = true
    try {
      await onGit()
    } finally {
      gitBusy = false
    }
  }

  // The session menu (⋯): Stop today, more actions later.
  let menuOpen = $state(false)
  function stopSession(): void {
    menuOpen = false
    onStop()
  }

  const live = $derived(
    cloud.state === 'running' ||
      cloud.state === 'busy' ||
      cloud.state === 'waiting' ||
      cloud.state === 'starting'
  )
  // A new session is "starting" until it runs (its title comes with the
  // start); then its name.
  const heading = $derived(
    !cloud.sessionId ||
      cloud.progress === 'uploading' ||
      cloud.progress === 'starting'
      ? 'Cloud session starting…'
      : title || 'Cloud session'
  )

  // Files on their way: the cloud's tooltip.
  const progressText = $derived(
    cloud.progress === 'adding-files'
      ? `Adding ${cloud.addingFiles} ${cloud.addingFiles === 1 ? 'file' : 'files'} to the session…`
      : cloud.progress === 'uploading'
        ? 'Uploading files…'
        : null
  )
</script>

<svelte:window
  onclick={() => (menuOpen = false)}
  onkeydown={(e) => {
    if (e.key === 'Escape') menuOpen = false
  }}
/>

<div class="cloud-banner" role="status" aria-busy={cloud.loading}>
  <div class="line">
    <CloudStatusIcon
      state={cloud.state}
      loading={cloud.loading}
      detail={progressText}
    />
    <span class="label" title={heading}>{heading}</span>
    <span class="spacer"></span>
    {#if !cloud.loading && cloud.sessionId}
      <!-- Nothing until the session's state is known (while loading). -->
      <button
        type="button"
        class="btn git-btn"
        onclick={gitAction}
        disabled={gitBusy || !canGit || git?.kind === 'unavailable'}
        title={gitTitle}
      >
        <svg viewBox="0 0 16 16" aria-hidden="true" fill="none">
          <circle
            cx="4.5"
            cy="4"
            r="1.6"
            stroke="currentColor"
            stroke-width="1.3"
          />
          <circle
            cx="4.5"
            cy="12"
            r="1.6"
            stroke="currentColor"
            stroke-width="1.3"
          />
          <circle
            cx="11.5"
            cy="6"
            r="1.6"
            stroke="currentColor"
            stroke-width="1.3"
          />
          <path
            d="M4.5 5.6v4.8M11.5 7.6c0 2.2-2.5 2.4-7 2.8"
            stroke="currentColor"
            stroke-width="1.3"
            stroke-linecap="round"
          />
        </svg>
        <span>{gitLabel}</span>
        {#if git?.kind === 'cloned' && git.pending && cloud.state === 'sleeping'}
          <span class="git-pending">pending</span>
        {/if}
      </button>
      <div class="menu-anchor">
        <button
          type="button"
          class="dots"
          aria-label="Session actions"
          aria-haspopup="menu"
          aria-expanded={menuOpen}
          onclick={(e) => {
            e.stopPropagation()
            menuOpen = !menuOpen
          }}>⋯</button
        >
        {#if menuOpen}
          <div class="menu" role="menu">
            <button
              role="menuitem"
              disabled={!live}
              title={live
                ? 'Stop the cloud compute'
                : "The session isn't running"}
              onclick={stopSession}>Stop session</button
            >
          </div>
        {/if}
      </div>
    {/if}
  </div>
</div>

<style>
  .cloud-banner {
    padding: 5px 10px;
    font-size: 11px;
    color: var(--vscode-descriptionForeground);
  }
  .line {
    display: flex;
    align-items: center;
    gap: 6px;
    /* As tall as the row with its buttons (about 18px), so the cloud and
       the name don't move when Clone / Sync and the menu appear. */
    min-height: 20px;
  }
  .label {
    flex: 0 1 auto;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    color: var(--vscode-foreground);
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
  .git-btn {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    color: var(--vscode-descriptionForeground);
    padding: 1px 6px;
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
  .git-pending {
    font-size: 9px;
    color: var(--vscode-editorWarning-foreground, #cca700);
  }
  .menu-anchor {
    position: relative;
    display: flex;
    align-items: center;
  }
  .dots {
    background: transparent;
    border: none;
    color: var(--vscode-descriptionForeground);
    font-size: 14px;
    line-height: 1;
    padding: 2px 4px;
    border-radius: 3px;
    cursor: pointer;
  }
  .dots:hover,
  .dots[aria-expanded='true'] {
    color: var(--vscode-foreground);
    background: var(
      --vscode-toolbar-hoverBackground,
      rgba(128, 128, 128, 0.15)
    );
  }
  .menu {
    position: absolute;
    top: 100%;
    right: 0;
    z-index: 20;
    min-width: 130px;
    display: flex;
    flex-direction: column;
    background: var(--vscode-menu-background, var(--vscode-editor-background));
    border: 1px solid var(--vscode-widget-border, rgba(128, 128, 128, 0.35));
    border-radius: 4px;
    box-shadow: 0 4px 10px rgba(0, 0, 0, 0.25);
    padding: 3px;
  }
  .menu button {
    background: transparent;
    border: none;
    text-align: left;
    padding: 4px 8px;
    font-size: 12px;
    color: var(--vscode-menu-foreground, var(--vscode-foreground));
    border-radius: 3px;
    cursor: pointer;
    white-space: nowrap;
  }
  .menu button:hover:not(:disabled) {
    background: var(
      --vscode-menu-selectionBackground,
      var(--vscode-list-hoverBackground)
    );
    color: var(
      --vscode-menu-selectionForeground,
      var(--vscode-menu-foreground, var(--vscode-foreground))
    );
  }
  .menu button:disabled {
    opacity: 0.5;
    cursor: default;
  }
</style>
