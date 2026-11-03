<script lang="ts" module>
  export type ShareStatus = 'closed' | 'working' | 'ready' | 'failed'
</script>

<script lang="ts">
  interface Props {
    status: ShareStatus
    /** Set in the `ready` state */
    link: string
    /** The human check needs a click, which happens in this panel */
    needsClick: boolean
    onClose: () => void
    onRetry: () => void
    /** The button the panel's arrow points at */
    anchor: HTMLElement | undefined
    /** Turnstile draws its widget here */
    turnstileElement: HTMLDivElement
  }
  let {
    status,
    link,
    needsClick,
    onClose,
    onRetry,
    anchor,
    turnstileElement = $bindable(),
  }: Props = $props()

  let panel: HTMLDivElement | undefined = $state(undefined)
  let linkInput: HTMLInputElement | undefined = $state(undefined)
  let copied = $state(false)
  let arrowRight = $state(0)

  const dismissable = $derived(status === 'ready' || status === 'failed')

  async function copy() {
    try {
      await navigator.clipboard.writeText(link)
      copied = true
    } catch {
      // Refused outside a click in some browsers. The link is selected, so
      // the keyboard shortcut still works.
      copied = false
      linkInput?.select()
    }
  }

  $effect(() => {
    if (status === 'closed' || !anchor || !panel) return
    const button = anchor.getBoundingClientRect()
    arrowRight =
      panel.getBoundingClientRect().right - button.right + button.width / 2
  })

  $effect(() => {
    if (status !== 'ready') return
    copied = false
    linkInput?.focus()
    linkInput?.select()
    // Selecting scrolls to the end; a narrow screen should show the start
    if (linkInput) linkInput.scrollLeft = 0
    copy()
  })

  function handleKeydown(event: KeyboardEvent) {
    if (event.key === 'Escape' && dismissable) onClose()
  }

  function handlePointerDown(event: PointerEvent) {
    if (dismissable && !panel?.contains(event.target as Node)) onClose()
  }
</script>

<svelte:window
  onkeydown={handleKeydown}
  onpointerdowncapture={handlePointerDown}
/>

<!-- Always mounted and never display: none, because the human check starts
     in here before the panel opens -->
<div
  bind:this={panel}
  class="share-panel"
  class:open={status !== 'closed'}
  role="dialog"
  aria-label="Share the current file"
  style:--arrow-right="{arrowRight}px"
>
  <div class="arrow"></div>
  {#if status === 'working'}
    <p aria-live="polite">
      {needsClick
        ? 'Please confirm you’re human to create the link.'
        : 'Creating the share link…'}
    </p>
  {:else if status === 'ready'}
    <div class="heading">
      <p>Anyone with this link can open this program.</p>
      <button class="close" onclick={onClose} aria-label="Close">×</button>
    </div>
    <div class="link-row">
      <input
        bind:this={linkInput}
        readonly
        value={link}
        aria-label="Share link"
        onfocus={(event) => event.currentTarget.select()}
      />
      <button class="action" onclick={copy}>{copied ? 'Copied' : 'Copy'}</button
      >
    </div>
  {:else if status === 'failed'}
    <div class="heading">
      <p aria-live="polite">Could not create a share link.</p>
      <button class="close" onclick={onClose} aria-label="Close">×</button>
    </div>
    <button class="action" onclick={onRetry}>Try again</button>
  {/if}
  <div
    bind:this={turnstileElement}
    class="turnstile"
    class:needs-click={needsClick}
  ></div>
</div>

<style>
  .share-panel {
    visibility: hidden;
    position: fixed;
    top: 46px;
    right: 1em;
    z-index: 400;
    box-sizing: border-box;
    /* Fits a whole share link */
    width: min(620px, calc(100vw - 2em));
    padding: 0.75em;
    font-size: 0.8rem;
    color: rgb(30, 29, 28);
    /* The top bar's colour, without its transparency */
    background: rgb(250, 250, 249);
    border: 1px solid rgba(30, 29, 28, 0.15);
    border-radius: 3px;
    box-shadow: 0 2px 8px rgba(30, 29, 28, 0.12);
  }
  .arrow {
    position: absolute;
    top: -6px;
    right: var(--arrow-right);
    width: 10px;
    height: 10px;
    margin-right: -5px;
    background: inherit;
    border-top: 1px solid rgba(30, 29, 28, 0.15);
    border-left: 1px solid rgba(30, 29, 28, 0.15);
    transform: rotate(45deg);
  }
  .share-panel.open {
    visibility: visible;
  }
  p {
    margin: 0;
  }
  .heading {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 0.5em;
    margin-bottom: 0.5em;
  }
  .close {
    border: none;
    background: none;
    padding: 0;
    font-size: 1.1rem;
    line-height: 1;
    cursor: pointer;
    color: rgba(30, 29, 28, 0.698);
  }
  .close:hover {
    color: rgb(30, 29, 28);
  }
  .link-row {
    display: flex;
    gap: 0.4em;
  }
  input {
    flex: 1;
    min-width: 0;
    padding: 0.3em 0.4em;
    font: inherit;
    font-family: monospace;
    color: inherit;
    background: white;
    border: 1px solid rgba(30, 29, 28, 0.2);
    border-radius: 2px;
  }
  .action {
    padding: 0.3em 0.7em;
    font: inherit;
    color: inherit;
    cursor: pointer;
    background: #f3f2f1;
    border: 1px solid rgba(30, 29, 28, 0.2);
    border-radius: 2px;
  }
  .action:hover {
    background: #e8e6e4;
  }
  .turnstile.needs-click {
    margin-top: 0.5em;
  }
</style>
