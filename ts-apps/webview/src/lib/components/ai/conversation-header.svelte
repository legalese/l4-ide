<script lang="ts">
  import { tick, type Snippet } from 'svelte'
  import type { CloudConversationInfo } from '$lib/stores/ai-chat.svelte'
  import CloudStatusIcon from './cloud-status-icon.svelte'

  // Header of a conversation, local or cloud (§12.2): what it is (a
  // cloud session's cloud, with its state and progress in the tooltip;
  // a local chat's dot while it runs or waits for you), its name (click
  // to rename), Clone / Sync for a cloud session, and the ⋯ menu. No
  // text lines: what needs the user goes on the thing to act on,
  // failures and conflicts are VS Code notifications.
  let {
    cloud = null,
    title,
    running = false,
    waiting = false,
    action,
    onStop,
    onDelete,
    onRename,
  }: {
    /** Set for a cloud session. */
    cloud?: CloudConversationInfo | null
    /** The conversation's name. */
    title: string
    /** A local chat: a turn runs / it waits for an approval or answer. */
    running?: boolean
    waiting?: boolean
    /** To the left of the menu: a cloud session's Clone / Sync. */
    action?: Snippet
    onStop?: () => void
    onDelete: () => void
    /** Rename; without it the name can't be edited. */
    onRename?: (title: string) => void
  } = $props()

  // The ⋯ menu: Stop session (cloud), Delete conversation.
  let menuOpen = $state(false)
  function stopSession(): void {
    menuOpen = false
    onStop?.()
  }
  function deleteConversation(): void {
    menuOpen = false
    onDelete()
  }

  const live = $derived(
    cloud?.state === 'running' ||
      cloud?.state === 'busy' ||
      cloud?.state === 'waiting' ||
      cloud?.state === 'starting'
  )
  // A new cloud session is "starting" until it runs (its title comes
  // with the start); then its name.
  const heading = $derived(
    cloud &&
      (!cloud.sessionId ||
        cloud.progress === 'uploading' ||
        cloud.progress === 'starting')
      ? 'Cloud session starting…'
      : title || (cloud ? 'Cloud session' : 'New conversation')
  )
  // The menu waits until a cloud session is known (while loading).
  const ready = $derived(!cloud || (!cloud.loading && !!cloud.sessionId))

  // Files on their way: the cloud's tooltip.
  const progressText = $derived(
    cloud?.progress === 'adding-files'
      ? `Adding ${cloud.addingFiles} ${cloud.addingFiles === 1 ? 'file' : 'files'} to the session…`
      : cloud?.progress === 'uploading'
        ? 'Uploading files…'
        : null
  )

  // Renaming in place: the name becomes a field; Enter or leaving it
  // keeps the new name, Escape keeps the old one.
  let editing = $state(false)
  let draft = $state('')
  let input = $state<HTMLInputElement | null>(null)
  async function startRename(): Promise<void> {
    if (!onRename || !ready) return
    draft = title
    editing = true
    await tick()
    input?.focus()
    input?.select()
  }
  function finishRename(keep: boolean): void {
    if (!editing) return
    editing = false
    const next = draft.trim()
    if (keep && next && next !== title) onRename?.(next)
  }
</script>

<svelte:window
  onclick={() => (menuOpen = false)}
  onkeydown={(e) => {
    if (e.key === 'Escape') menuOpen = false
  }}
/>

<div
  class="conversation-header"
  role="status"
  aria-busy={cloud?.loading ?? false}
>
  <div class="line">
    {#if cloud}
      <CloudStatusIcon
        state={cloud.state}
        loading={cloud.loading}
        detail={progressText}
      />
    {:else if waiting}
      <span
        class="dot waiting"
        role="img"
        aria-label="Waiting for you"
        title="Waiting for you: an approval or a question"
      ></span>
    {:else if running}
      <span
        class="dot running"
        role="img"
        aria-label="Running"
        title="A turn is running"
      ></span>
    {/if}
    {#if editing}
      <input
        class="name-input"
        bind:this={input}
        bind:value={draft}
        maxlength="80"
        aria-label="Conversation name"
        onkeydown={(e) => {
          if (e.key === 'Enter') finishRename(true)
          else if (e.key === 'Escape') {
            e.stopPropagation()
            finishRename(false)
          }
        }}
        onblur={() => finishRename(true)}
      />
    {:else if onRename && ready}
      <button
        type="button"
        class="label name-btn"
        title={`${heading} (click to rename)`}
        onclick={() => void startRename()}>{heading}</button
      >
    {:else}
      <span class="label" title={heading}>{heading}</span>
    {/if}
    <span class="spacer"></span>
    {#if ready}
      {@render action?.()}
      <div class="menu-anchor">
        <button
          type="button"
          class="dots"
          aria-label="Conversation actions"
          aria-haspopup="menu"
          aria-expanded={menuOpen}
          onclick={(e) => {
            e.stopPropagation()
            menuOpen = !menuOpen
          }}>⋯</button
        >
        {#if menuOpen}
          <div class="menu" role="menu">
            {#if cloud}
              <button
                role="menuitem"
                disabled={!live}
                title={live
                  ? 'Stop the cloud compute'
                  : "The session isn't running"}
                onclick={stopSession}>Stop session</button
              >
            {/if}
            <button role="menuitem" class="danger" onclick={deleteConversation}
              >Delete conversation</button
            >
          </div>
        {/if}
      </div>
    {/if}
  </div>
</div>

<style>
  .conversation-header {
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
  /* The name, a button to rename it, and the field that replaces it:
     one box, with the settings inputs' padding and a border that only
     shows on the field, so nothing moves on a click. The margins keep
     the text where a plain name sits, and the line's height. */
  .name-btn,
  .name-input {
    box-sizing: border-box;
    margin: -2px 0 -2px -8px;
    padding: 4px 8px;
    border: 1px solid transparent;
    border-radius: 4px;
    font: inherit;
    line-height: 14px;
  }
  .name-btn {
    background: none;
    text-align: left;
    cursor: default;
  }
  .name-btn:hover {
    background: rgba(128, 128, 128, 0.12);
  }
  /* As the settings inputs; as wide as its text, growing as it does. */
  .name-input {
    flex: 0 1 auto;
    min-width: 40px;
    max-width: 100%;
    field-sizing: content;
    color: var(--vscode-input-foreground);
    background: var(--vscode-input-background);
    border-color: var(--vscode-widget-border, rgba(128, 128, 128, 0.35));
    outline: none;
  }
  .name-input:focus {
    border-color: var(--vscode-foreground, #ccc);
  }
  /* A local chat's dot, as in the history: crimson and pulsing while a
     turn runs, amber while it waits for you. */
  .dot {
    flex-shrink: 0;
    width: 7px;
    height: 7px;
    margin: 0 3px;
    border-radius: 50%;
  }
  .dot.running {
    background: #c8376a;
    animation: running-pulse 1.2s ease-in-out infinite;
  }
  .dot.waiting {
    background: var(--vscode-editorWarning-foreground, #cca700);
  }
  @media (prefers-reduced-motion: reduce) {
    .dot.running {
      animation: none;
    }
  }
  @keyframes running-pulse {
    0%,
    100% {
      opacity: 0.35;
    }
    50% {
      opacity: 1;
    }
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
  .menu button.danger {
    color: var(--vscode-errorForeground, #f14c4c);
  }
  .menu button:disabled {
    opacity: 0.5;
    cursor: default;
  }
</style>
