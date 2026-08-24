<script lang="ts">
  import type { AiChatStore } from '$lib/stores/ai-chat.svelte'
  import UsageLine from './usage-line.svelte'

  let {
    store,
    disabled = false,
    onNewChat,
    onOpenHistory,
  }: {
    store: AiChatStore
    disabled?: boolean
    /** Mobile-only: start a fresh chat (compose icon, bottom-left). */
    onNewChat?: () => void
    /** Mobile-only: open past conversations as a full-screen drawer. */
    onOpenHistory?: () => void
  } = $props()

  let text = $state('')
  let attachBusy = $state(false)
  let attachNote = $state<string | null>(null)
  let textarea = $state<HTMLTextAreaElement | null>(null)

  const streaming = $derived(store.current?.streaming ?? false)
  const canSend = $derived(!disabled && text.trim().length > 0 && !streaming)

  // Re-sync the textarea from the store's per-conversation draft whenever the
  // conversation changes or a seed is injected (e.g. an example prompt).
  let lastConvId: string | null | undefined
  let lastSeed = -1
  $effect(() => {
    const conv = store.currentId
    const seed = store.draftSeedVersion
    if (conv !== lastConvId || seed !== lastSeed) {
      lastConvId = conv
      lastSeed = seed
      text = store.getDraft()
      autosize()
    }
  })

  function autosize(): void {
    if (!textarea) return
    textarea.style.height = 'auto'
    textarea.style.height = `${Math.min(textarea.scrollHeight, 200)}px`
  }

  function onInput(): void {
    store.setDraft(text)
    autosize()
  }

  function submit(): void {
    const t = text.trim()
    if (!t || streaming || disabled) return
    void store.send(t)
    text = ''
    store.setDraft('')
    autosize()
  }

  function onKeydown(e: KeyboardEvent): void {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
      e.preventDefault()
      submit()
    }
  }

  async function pickAttachment(): Promise<void> {
    if (attachBusy) return
    attachBusy = true
    attachNote = null
    try {
      const res = await store.pickAttachment('any')
      if (res.note) attachNote = res.note
    } finally {
      attachBusy = false
    }
  }
</script>

<div class="chat-input-box">
  {#if store.stagedAttachments.length > 0}
    <div class="attachment-strip">
      {#each store.stagedAttachments as att, i (att.name + i)}
        <span class="chip">
          <span class="chip-name">{att.name}</span>
          <button
            class="chip-x"
            title="Remove"
            onclick={() => store.removeAttachment(i)}>×</button
          >
        </span>
      {/each}
    </div>
  {/if}

  {#if attachNote}
    <div class="attachment-note">{attachNote}</div>
  {/if}

  <textarea
    bind:this={textarea}
    bind:value={text}
    class="chat-textarea"
    rows="1"
    placeholder="Ask anything about your rules…"
    {disabled}
    oninput={onInput}
    onkeydown={onKeydown}
  ></textarea>

  <UsageLine used={store.usedToday} limit={store.dailyLimit} />

  <div class="action-bar">
    <!-- On desktop new / history live in the sidebar, so the lower-left is
         empty. On mobile the sidebar is hidden and these two buttons take
         over — same glyphs the VSCode extension uses in its chat input. -->
    <div class="left-actions">
      <button
        class="icon-btn svg-btn mobile-only"
        title="New chat"
        aria-label="New chat"
        onclick={() => onNewChat?.()}
      >
        <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
          <path
            d="M10 4V4C8.13623 4 7.20435 4 6.46927 4.30448C5.48915 4.71046 4.71046 5.48915 4.30448 6.46927C4 7.20435 4 8.13623 4 10V13.6C4 15.8402 4 16.9603 4.43597 17.816C4.81947 18.5686 5.43139 19.1805 6.18404 19.564C7.03968 20 8.15979 20 10.4 20H14C15.8638 20 16.7956 20 17.5307 19.6955C18.5108 19.2895 19.2895 18.5108 19.6955 17.5307C20 16.7956 20 15.8638 20 14V14"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="square"
          />
          <path
            d="M12.4393 14.5607L19.5 7.5C20.3284 6.67157 20.3284 5.32843 19.5 4.5C18.6716 3.67157 17.3284 3.67157 16.5 4.5L9.43934 11.5607C9.15804 11.842 9 12.2235 9 12.6213V15H11.3787C11.7765 15 12.158 14.842 12.4393 14.5607Z"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="square"
          />
        </svg>
      </button>
      <button
        class="icon-btn svg-btn mobile-only"
        title="Chat history"
        aria-label="Chat history"
        onclick={() => onOpenHistory?.()}
      >
        <svg viewBox="0 0 16 16" aria-hidden="true">
          <circle
            cx="8"
            cy="8"
            r="5.5"
            stroke="currentColor"
            stroke-width="1.5"
            fill="none"
          />
          <path
            d="M8 5v3.2L10.1 10"
            stroke="currentColor"
            stroke-width="1.5"
            fill="none"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
      </button>
    </div>

    <div class="right-actions">
      <button
        class="icon-btn"
        title="Attach a file"
        onclick={pickAttachment}
        disabled={disabled || attachBusy}
        aria-label="Attach a file">📎</button
      >

      {#if streaming}
        <button
          class="submit-btn stop"
          title="Stop"
          onclick={() => store.abort()}
          aria-label="Stop">■</button
        >
      {:else}
        <button
          class="submit-btn"
          title="Send"
          onclick={submit}
          disabled={!canSend}
          aria-label="Send">↑</button
        >
      {/if}
    </div>
  </div>
</div>

<style>
  .chat-input-box {
    border: 1px solid var(--vscode-input-border, var(--vscode-widget-border));
    border-radius: 12px;
    background: var(--vscode-input-background);
    padding: 0.4rem;
    margin: 0 0.75rem 0.75rem;
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
    max-width: 800px;
    /* border-box + margin-compensated width: with the default content-box,
       100% + side margins + border overflowed the centered flex column on
       narrow viewports and produced horizontal scrolling. */
    box-sizing: border-box;
    width: calc(100% - 1.5rem);
    font-size: 0.85em;
    box-shadow: 0 0 10px 2px var(--sidebar-bg);
  }
  /* Outline while the textarea (or any control in the box) has focus —
     `:focus-within` tracks the inner textarea, which itself renders
     borderless (`outline: none`). Uses the input foreground tone (a soft
     off-white in dark mode, ~#e6e6e9) rather than pure #fff, which reads
     too harsh; theme-aware, so it stays visible in light mode too. */
  .chat-input-box:focus-within {
    border-color: var(--vscode-input-foreground);
  }

  .attachment-strip {
    display: flex;
    flex-wrap: wrap;
    gap: 0.3rem;
  }
  .chip {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
    padding: 0.1rem 0.4rem;
    border-radius: 6px;
    /* Light translucent gray fill — matches the attachment chip in the
       VSCode extension's prompt input (reads as a captured value rather
       than a solid hover-colored pill). */
    background: rgba(128, 128, 128, 0.14);
    font-size: 0.78rem;
  }
  .chip-x {
    border: none;
    background: transparent;
    cursor: pointer;
    color: var(--vscode-descriptionForeground);
    font-size: 0.95rem;
    line-height: 1;
  }
  .attachment-note {
    font-size: 0.75rem;
    color: var(--vscode-descriptionForeground);
  }

  .chat-textarea {
    width: 100%;
    border: none;
    outline: none;
    resize: none;
    background: transparent;
    color: var(--vscode-input-foreground);
    font: inherit;
    line-height: 1.4;
    max-height: 200px;
    overflow-y: auto;
    box-sizing: border-box;
    margin: 0.2rem;
  }
  .chat-textarea::placeholder {
    color: var(--vscode-descriptionForeground);
  }

  .action-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  .left-actions {
    min-height: 1px;
    display: flex;
    align-items: center;
    gap: 0.35rem;
  }
  .right-actions {
    display: flex;
    align-items: center;
    gap: 0.35rem;
  }

  .svg-btn {
    width: 28px;
    height: 28px;
    align-items: center;
    justify-content: center;
    padding: 0;
    color: var(--vscode-descriptionForeground);
  }
  .svg-btn svg {
    width: 16px;
    height: 16px;
    display: block;
  }
  .svg-btn:hover:not(:disabled) {
    color: var(--vscode-foreground);
  }
  /* New-chat / history buttons only appear when the sidebar is hidden. */
  .mobile-only {
    display: none;
  }
  @media (max-width: 768px) {
    .mobile-only {
      display: inline-flex;
    }
  }

  .icon-btn {
    border: none;
    background: transparent;
    cursor: pointer;
    font-size: 0.75rem;
    padding: 0.25rem;
    border-radius: 6px;
    opacity: 0.8;
  }
  .icon-btn:hover:not(:disabled) {
    background: var(--vscode-toolbar-hoverBackground);
    opacity: 1;
  }
  .icon-btn:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .submit-btn {
    width: 28px;
    height: 28px;
    display: grid;
    place-items: center;
    background: var(--brand);
    color: #fff;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-size: 1rem;
    transition: background-color 0.1s ease-out;
  }
  .submit-btn:hover:not(:disabled) {
    background: var(--brand-hover);
  }
  .submit-btn:disabled {
    opacity: 0.45;
    cursor: default;
  }
  .submit-btn.stop {
    background: var(--brand-dark);
    color: rgba(255, 255, 255, 0.7);
    font-size: 0.7rem;
  }
  .submit-btn.stop:hover {
    background: #7f1a3f;
    color: #fff;
  }
</style>
