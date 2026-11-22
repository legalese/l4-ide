<script lang="ts">
  import { onDestroy, tick } from 'svelte'
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
    if (e.key === 'Escape' && store.dictationPhase === 'recording') {
      e.preventDefault()
      cancelDictation()
      return
    }
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

  // Voice dictation — same behaviour as the VSCode extension's input:
  // tap the mic to start, tap again to stop and have the transcript
  // dropped in at the cursor (never auto-sent); Escape throws the
  // recording away. The whole affordance is absent where the page
  // can't record.
  let dictationElapsed = $state(0)
  let dictationTimer: ReturnType<typeof setInterval> | undefined

  // Dictation failures show as a small bubble above the mic, pointing
  // at it. It fades out by itself after a few seconds, or right away
  // when it — or the mic — is clicked.
  const DICTATION_ERROR_VISIBLE_MS = 6000
  // Keep in step with the `mic-error-out` animation below.
  const DICTATION_ERROR_FADE_MS = 250
  let dictationError = $state<string | null>(null)
  let dictationErrorLeaving = $state(false)
  let dictationErrorTimer: ReturnType<typeof setTimeout> | undefined

  function showDictationError(message: string): void {
    clearTimeout(dictationErrorTimer)
    dictationError = message
    dictationErrorLeaving = false
    dictationErrorTimer = setTimeout(
      dismissDictationError,
      DICTATION_ERROR_VISIBLE_MS
    )
  }

  function dismissDictationError(): void {
    if (dictationError === null || dictationErrorLeaving) return
    clearTimeout(dictationErrorTimer)
    dictationErrorLeaving = true
    dictationErrorTimer = setTimeout(() => {
      dictationError = null
      dictationErrorLeaving = false
    }, DICTATION_ERROR_FADE_MS)
  }

  function stopDictationTimer(): void {
    if (dictationTimer) clearInterval(dictationTimer)
    dictationTimer = undefined
  }

  async function toggleDictation(): Promise<void> {
    dismissDictationError()
    if (store.dictationPhase === 'recording') {
      await finishDictation()
      return
    }
    if (store.dictationPhase !== 'idle') return
    const res = await store.startDictation()
    if (!res.ok) {
      if (res.note) showDictationError(res.note)
      return
    }
    const startedAt = Date.now()
    dictationElapsed = 0
    dictationTimer = setInterval(() => {
      dictationElapsed = Math.floor((Date.now() - startedAt) / 1000)
      if (dictationElapsed >= store.dictationMaxSeconds) void finishDictation()
    }, 250)
  }

  async function finishDictation(): Promise<void> {
    stopDictationTimer()
    const res = await store.stopDictation()
    if (res.note) {
      showDictationError(res.note)
    } else if (res.text !== undefined) {
      const transcript = res.text.trim()
      if (transcript) insertAtCursor(transcript)
      else showDictationError('Didn’t catch that.')
    }
  }

  function cancelDictation(): void {
    stopDictationTimer()
    store.cancelDictation()
  }

  function formatElapsed(seconds: number): string {
    return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`
  }

  /** Splice `insert` into the draft at the caret (replacing any
   *  selection), padding with a space where it would otherwise butt up
   *  against a neighbouring word. */
  function insertAtCursor(insert: string): void {
    const start = textarea?.selectionStart ?? text.length
    const end = textarea?.selectionEnd ?? text.length
    const before = text.slice(0, start)
    const after = text.slice(end)
    const lead = before && !/\s$/.test(before) ? ' ' : ''
    const trail = after && !/^\s/.test(after) ? ' ' : ''
    text = `${before}${lead}${insert}${trail}${after}`
    store.setDraft(text)
    const cursor = before.length + lead.length + insert.length
    void tick().then(() => {
      if (!textarea) return
      textarea.focus()
      textarea.setSelectionRange(cursor, cursor)
      autosize()
    })
  }

  // The recording can also end from outside this component (the chat
  // being hidden, the store resetting) — don't leave the clock running.
  $effect(() => {
    if (store.dictationPhase !== 'recording') stopDictationTimer()
  })

  onDestroy(() => {
    cancelDictation()
    clearTimeout(dictationErrorTimer)
  })
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

  <div class="textarea-row">
    <textarea
      bind:this={textarea}
      bind:value={text}
      class="chat-textarea"
      class:has-mic={store.dictationAvailable}
      class:mic-recording={store.dictationPhase === 'recording'}
      rows="1"
      placeholder={store.dictationPhase === 'recording'
        ? 'Listening…'
        : store.dictationPhase === 'transcribing'
          ? 'Transcribing…'
          : 'Ask anything about your rules…'}
      {disabled}
      oninput={onInput}
      onkeydown={onKeydown}
    ></textarea>
    {#if store.dictationAvailable}
      <!-- Sits on the placeholder line, in the same column as the send
           button below it. -->
      <div class="mic-slot">
        {#if dictationError}
          <div class="mic-error-anchor" role="alert">
            <button
              type="button"
              class="mic-error"
              class:leaving={dictationErrorLeaving}
              title="Dismiss"
              onclick={dismissDictationError}>{dictationError}</button
            >
          </div>
        {/if}
        {#if store.dictationPhase === 'recording'}
          <span class="mic-elapsed" aria-hidden="true"
            >{formatElapsed(dictationElapsed)}</span
          >
        {/if}
        <button
          type="button"
          class="icon-btn svg-btn mic-btn"
          class:recording={store.dictationPhase === 'recording'}
          title={store.dictationPhase === 'recording'
            ? 'Stop and transcribe (Esc to cancel)'
            : store.dictationPhase === 'transcribing'
              ? 'Transcribing…'
              : 'Dictate'}
          aria-label={store.dictationPhase === 'recording'
            ? 'Stop dictation'
            : 'Dictate'}
          aria-pressed={store.dictationPhase === 'recording'}
          disabled={disabled ||
            store.dictationPhase === 'starting' ||
            store.dictationPhase === 'transcribing'}
          onclick={toggleDictation}
          onkeydown={onKeydown}
        >
          {#if store.dictationPhase === 'recording'}
            <svg viewBox="0 0 16 16" aria-hidden="true">
              <rect
                x="4.5"
                y="4.5"
                width="7"
                height="7"
                rx="1.5"
                fill="currentColor"
              />
            </svg>
          {:else if store.dictationPhase === 'transcribing'}
            <svg class="mic-spinner" viewBox="0 0 16 16" aria-hidden="true">
              <path
                d="M8 2.5a5.5 5.5 0 1 1-5.5 5.5"
                stroke="currentColor"
                stroke-width="1.5"
                fill="none"
                stroke-linecap="round"
              />
            </svg>
          {:else}
            <svg
              viewBox="0 0 16 16"
              aria-hidden="true"
              fill="none"
              stroke="currentColor"
              stroke-width="1.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <rect x="6" y="2" width="4" height="7.5" rx="2" />
              <path d="M3.5 7.5a4.5 4.5 0 0 0 9 0" />
              <path d="M8 12v2" />
            </svg>
          {/if}
        </button>
      </div>
    {/if}
  </div>

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
  /* iOS Safari auto-zooms the page when a focused input renders below
     16px, so on mobile the textarea must not inherit the box's 0.85em
     (~13.6px) scale. Desktop keeps the compact size. */
  @media (max-width: 768px) {
    .chat-textarea {
      font-size: 16px;
    }
  }

  /* Dictation: the mic sits at the right end of the textarea's first
     line, flush with the send button below. The row is at least as tall
     as the button so a one-line textarea doesn't let it overhang. */
  .textarea-row {
    position: relative;
    display: flex;
    align-items: flex-start;
    min-height: 28px;
  }
  /* Keep typed text clear of the mic (and, while recording, the
     elapsed-time readout beside it). The 0.2rem is the textarea's own
     margin, which percentage widths don't account for. */
  .chat-textarea.has-mic {
    width: calc(100% - 0.4rem - 32px);
  }
  .chat-textarea.has-mic.mic-recording {
    width: calc(100% - 0.4rem - 64px);
  }
  .mic-slot {
    position: absolute;
    top: 0;
    right: 0;
    display: flex;
    align-items: center;
    gap: 0.25rem;
  }
  .mic-elapsed {
    font-size: 0.75rem;
    font-variant-numeric: tabular-nums;
    color: var(--vscode-descriptionForeground);
  }
  /* Error bubble: floats above the mic, right edges aligned, with a
     tail pointing down at the button's centre. */
  .mic-error-anchor {
    position: absolute;
    right: 0;
    bottom: calc(100% + 9px);
    z-index: 10;
  }
  .mic-error {
    position: relative;
    display: block;
    width: max-content;
    max-width: min(260px, calc(100vw - 2.5rem));
    padding: 0.4rem 0.6rem;
    border: 1px solid var(--vscode-errorForeground, #d11149);
    border-radius: 8px;
    background: var(--vscode-input-background);
    color: var(--vscode-foreground);
    font: inherit;
    font-size: 0.8rem;
    line-height: 1.4;
    text-align: left;
    cursor: pointer;
    box-shadow: 0 2px 10px rgba(0, 0, 0, 0.18);
    animation: mic-error-in 0.15s ease-out;
  }
  /* The tail: a rotated square showing its bottom-right corner, 14px in
     from the right — the middle of the 28px mic button. */
  .mic-error::after {
    content: '';
    position: absolute;
    right: 10px;
    bottom: -5px;
    width: 8px;
    height: 8px;
    background: inherit;
    border: inherit;
    border-top: none;
    border-left: none;
    border-radius: 0 0 2px 0;
    transform: rotate(45deg);
  }
  .mic-error.leaving {
    animation: mic-error-out 0.25s ease-in forwards;
  }
  @keyframes mic-error-in {
    from {
      opacity: 0;
      transform: translateY(4px);
    }
  }
  @keyframes mic-error-out {
    to {
      opacity: 0;
      transform: translateY(4px);
    }
  }
  .mic-btn {
    display: inline-flex;
    opacity: 1;
  }
  /* The :hover variant keeps the stop glyph red under the pointer —
     otherwise .svg-btn's hover colour out-specifies it. */
  .mic-btn.recording,
  .mic-btn.recording:hover:not(:disabled) {
    color: var(--vscode-errorForeground, #f14c4c);
    animation: mic-pulse 1.6s ease-in-out infinite;
  }
  .mic-spinner {
    animation: mic-spin 0.9s linear infinite;
  }
  @keyframes mic-pulse {
    0%,
    100% {
      background: rgba(241, 76, 76, 0.12);
    }
    50% {
      background: rgba(241, 76, 76, 0.28);
    }
  }
  @keyframes mic-spin {
    to {
      transform: rotate(360deg);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .mic-btn.recording {
      animation: none;
      background: rgba(241, 76, 76, 0.2);
    }
    .mic-error,
    .mic-error.leaving {
      animation: none;
    }
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
