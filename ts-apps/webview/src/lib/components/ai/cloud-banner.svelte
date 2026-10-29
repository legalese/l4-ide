<script lang="ts">
  import type { AiCloudGitStatus } from 'jl4-client-rpc'
  import type { CloudConversationInfo } from '$lib/stores/ai-chat.svelte'

  // Header of a cloud conversation (§12.2): state, start progress,
  // Resume for parked sessions / auth-required, Clone / Sync, the
  // session menu (Stop) and notices (merge conflicts, command errors).
  let {
    cloud,
    git,
    gitReady,
    onResume,
    onStop,
    onGit,
  }: {
    cloud: CloudConversationInfo
    /** Clone / Sync state of the session's files (§9.3). */
    git: AiCloudGitStatus | null
    /** The first turn is committed: there is something to clone. */
    gitReady: boolean
    onResume: () => void
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
    if (!canGit) return 'Available after the first turn'
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
  const needsResume = $derived(
    !cloud.loading &&
      !!cloud.sessionId &&
      (cloud.state === 'parked' ||
        (!!cloud.authRequired && cloud.authRequired.reason !== 'mcp'))
  )
  // The cloud's outline shimmers while an opened session loads.
  const shimmerId = `cloud-shimmer-${Math.random().toString(36).slice(2)}`
  const reducedMotion =
    typeof window !== 'undefined' &&
    window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

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

<svelte:window
  onclick={() => (menuOpen = false)}
  onkeydown={(e) => {
    if (e.key === 'Escape') menuOpen = false
  }}
/>

<div class="cloud-banner" role="status" aria-busy={cloud.loading}>
  <div class="line">
    <svg
      class="cloud-icon"
      class:loading={cloud.loading}
      viewBox="0 0 16 16"
      aria-hidden="true"
    >
      {#if cloud.loading}
        <!-- A bright band sweeps along a dimmed outline. -->
        <defs>
          <linearGradient id={shimmerId} x1="0" y1="0" x2="1" y2="0">
            <stop offset="0" stop-color="currentColor" stop-opacity="0.3" />
            <stop offset="0.5" stop-color="currentColor" stop-opacity="1" />
            <stop offset="1" stop-color="currentColor" stop-opacity="0.3" />
            {#if !reducedMotion}
              <animateTransform
                attributeName="gradientTransform"
                type="translate"
                from="-1 0"
                to="1 0"
                dur="1.4s"
                repeatCount="indefinite"
              />
            {/if}
          </linearGradient>
        </defs>
      {/if}
      <path
        d="M4.6 12.5a2.6 2.6 0 0 1-.3-5.2 3.4 3.4 0 0 1 6.6-1 2.7 2.7 0 0 1 .6 6.2z"
        stroke={cloud.loading ? `url(#${shimmerId})` : 'currentColor'}
        stroke-width="1.2"
        fill="none"
        stroke-linejoin="round"
      />
    </svg>
    <span class="label">Cloud session</span>
    {#if cloud.loading}
      <span class="visually-hidden">Loading</span>
    {:else if cloud.sessionId}
      <span class="state state-{cloud.state}">{cloud.state}</span>
    {/if}
    <span class="spacer"></span>
    {#if !cloud.loading && cloud.sessionId}
      <!-- Nothing until the session's state is known (while loading). -->
      {#if needsResume}
        <button class="btn primary" onclick={onResume}>Resume</button>
      {/if}
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
  {#if progressText}
    <div class="detail">{progressText}</div>
    {#if cloud.mcpServers.length > 0 && cloud.progress !== 'adding-files'}
      <div class="detail">
        MCP servers passed to this session: {cloud.mcpServers.join(', ')}. Their
        tools run without approval in the cloud.
      </div>
    {/if}
  {/if}
  {#if cloud.loading}
    <!-- Replayed notices may be stale until the replay catches up. -->
  {:else if cloud.authRequired?.reason === 'mcp'}
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
  .cloud-icon.loading {
    color: var(--vscode-foreground);
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
  .visually-hidden {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip: rect(0 0 0 0);
    white-space: nowrap;
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
  .detail.warn {
    color: var(--vscode-editorWarning-foreground, #cca700);
  }
  .detail.error {
    color: var(--vscode-errorForeground, #d7263d);
  }
</style>
