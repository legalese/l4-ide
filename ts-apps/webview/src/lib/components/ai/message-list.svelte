<script lang="ts">
  import UserMessage from './message-user.svelte'
  import AssistantMessage from './message-assistant.svelte'
  import SectionSpinner from './section-spinner.svelte'
  import AskUserCard from './ask-user-card.svelte'
  import type {
    RenderedTurn,
    RenderedToolCall,
    PendingQuestion,
    RollbackOffer,
  } from '$lib/stores/ai-chat.svelte'

  import type { Messenger } from 'vscode-messenger-webview'

  let {
    turns,
    streaming,
    pipelineActive,
    pendingApproval,
    pendingQuestion,
    messenger,
    onRetry,
    onApproveTool,
    onAnswerQuestion,
    onOpenFile,
    onOpenFileDiff,
    rollbackOfferAt,
    onRollback,
    cloud = false,
  }: {
    turns: RenderedTurn[]
    /** True while the current conversation has an open stream. Drives
     *  the bottom-of-chat § spinner. */
    streaming: boolean
    /** True until every queued user message has been folded into the
     *  pipeline. Forwarded to AssistantMessage to gate the per-turn
     *  usage badge and the "Files changed" review card so they only
     *  appear once nothing else is pending. */
    pipelineActive: boolean
    /** First tool call awaiting approval, if any. When present, the
     *  bottom action bar replaces the spinner with Accept / Reject. */
    pendingApproval: RenderedToolCall | null
    /** Active meta__ask_user question awaiting an answer, or null. */
    pendingQuestion: PendingQuestion | null
    /** Webview→extension messenger; threaded into AssistantMessage so
     *  tool-call cards can fetch render-meta on demand. */
    messenger: InstanceType<typeof Messenger> | null
    onRetry?: () => void
    onApproveTool: (
      callId: string,
      decision: 'allow' | 'deny' | 'alwaysAllow'
    ) => void
    onAnswerQuestion: (answer: string) => void
    onOpenFile: (callId: string) => void
    onOpenFileDiff: (callId: string) => void
    /** Cloud conversations (§9.4): the rollback offer for the turn at
     *  an index, and what to do when it's clicked. */
    rollbackOfferAt?: (index: number) => RollbackOffer | null
    onRollback?: (offer: RollbackOffer) => void
    /** A cloud conversation: "Always accept" doesn't apply (the cloud
     *  policy isn't the local settings). */
    cloud?: boolean
  } = $props()

  let scrollEl = $state<HTMLDivElement>()
  let stickToBottom = $state(true)
  let stickyUserIndex = $state<number>(-1)
  let userMessageOffsets: { index: number; offsetTop: number }[] = []

  function onScroll(): void {
    if (!scrollEl) return
    const near =
      scrollEl.scrollHeight - scrollEl.scrollTop - scrollEl.clientHeight < 40
    stickToBottom = near

    // Find the last user message whose offsetTop is less than
    // scrollTop. Only consumed bubbles are eligible for stickiness
    // — pending injections are filtered out at offset-collection
    // time below, so they never appear in this list and can never
    // become the sticky header.
    const scrollTop = scrollEl.scrollTop
    let lastUserAboveScroll = -1

    for (const { index, offsetTop } of userMessageOffsets) {
      if (offsetTop < scrollTop) {
        lastUserAboveScroll = index
      } else {
        break
      }
    }

    stickyUserIndex = lastUserAboveScroll
  }

  // Update offsets when turns change
  $effect(() => {
    if (!scrollEl) return
    // Trigger on turns change
    // eslint-disable-next-line @typescript-eslint/no-unused-expressions
    turns.length

    // Wait for DOM to update
    queueMicrotask(() => {
      if (!scrollEl) return
      const offsets: { index: number; offsetTop: number }[] = []
      const children = scrollEl.children

      for (let i = 0; i < children.length; i++) {
        const child = children[i] as HTMLElement
        if (!child.classList.contains('user-message-wrapper')) continue
        // Pending injections opt out of stickiness — they shouldn't
        // become the floating header until the extension has
        // actually consumed them.
        if (child.dataset.pending === 'true') continue

        const userIndex = parseInt(child.dataset.userIndex || '-1', 10)
        if (userIndex >= 0) {
          offsets.push({ index: userIndex, offsetTop: child.offsetTop })
        }
      }

      userMessageOffsets = offsets
    })
  })

  // When new tokens land, auto-scroll only if the user is near the
  // bottom. Otherwise leave them where they are.
  $effect(() => {
    // Track changes by reading every turn's content length.
    turns.map((t) => t.content.length)
    if (stickToBottom && scrollEl) {
      // Microtask so the DOM has grown before we measure.
      queueMicrotask(() => {
        if (scrollEl && stickToBottom) {
          scrollEl.scrollTop = scrollEl.scrollHeight
        }
      })
    }
  })

  // Submitting a new prompt always snaps the chat to the bottom,
  // even if the user had scrolled up to read older history. A fresh
  // user turn (incl. one queued via inject while a stream is in
  // flight) is the unambiguous "I want to see what happens next"
  // signal, so we override `stickToBottom` for that one event and
  // re-engage auto-stick going forward. Tracked by user-turn count
  // rather than total-turn count so an assistant reply or a
  // streamed-in tool block doesn't accidentally re-snap a user who
  // is deliberately reading earlier messages.
  let lastUserTurnCount = $state(0)
  $effect(() => {
    const userCount = turns.filter((t) => t.role === 'user').length
    if (userCount > lastUserTurnCount && scrollEl) {
      stickToBottom = true
      queueMicrotask(() => {
        if (scrollEl) scrollEl.scrollTop = scrollEl.scrollHeight
      })
    }
    lastUserTurnCount = userCount
  })
</script>

<div class="message-list" bind:this={scrollEl} onscroll={onScroll}>
  {#each turns as turn, i (turn.id)}
    {#if turn.role === 'user'}
      {@const userIndex =
        turns.slice(0, i + 1).filter((t) => t.role === 'user').length - 1}
      {@const pending = !!turn.injectionId}
      <UserMessage
        content={turn.content}
        chips={turn.chips}
        shouldStick={!pending && stickyUserIndex === userIndex}
        {userIndex}
        {pending}
      />
    {:else}
      {@const offer = rollbackOfferAt?.(i) ?? null}
      <div class="assistant-turn" class:rolled-back={turn.rolledBack}>
        <AssistantMessage
          content={turn.content}
          streaming={!!turn.streaming}
          {pipelineActive}
          error={turn.error}
          blocks={turn.blocks}
          usage={turn.usage}
          {messenger}
          {onRetry}
          {onOpenFile}
          {onOpenFileDiff}
        />
        {#if turn.rolledBack}
          <div class="turn-note">
            File changes of this turn were rolled back.
          </div>
        {:else if offer}
          <div class="rollback-row">
            <button
              class="rollback-btn"
              title={offer.label === 'Roll back'
                ? "Undo this turn's file changes"
                : 'Restore the files to how they were before this turn (undoes later turns too)'}
              onclick={() => onRollback?.(offer)}>{offer.label}</button
            >
          </div>
        {/if}
      </div>
    {/if}
  {/each}
  <!-- Question card for an active meta__ask_user. Rendered above the
       spinner / approval bar so the user can't miss it. Dispatcher is
       blocked on their reply, so this is the only meaningful action
       they can take. -->
  {#if pendingQuestion}
    <AskUserCard question={pendingQuestion} onAnswer={onAnswerQuestion} />
  {/if}

  <!-- Bottom-of-chat status. Shows Accept/Reject for any pending
       tool-call approval; otherwise the § spinner while the stream
       is live; otherwise nothing. -->
  {#if pendingApproval}
    <div class="bottom-approve" role="group" aria-label="Approve tool call">
      <div class="bottom-approve-label">
        Allow <strong>{pendingApproval.name}</strong>?
      </div>
      <div class="bottom-approve-btns">
        <button
          class="approve-btn allow"
          onclick={() => onApproveTool(pendingApproval!.callId, 'allow')}
          >Accept</button
        >
        {#if !cloud}
          <button
            class="approve-btn always"
            title="Always allow this category of tool"
            onclick={() =>
              onApproveTool(pendingApproval!.callId, 'alwaysAllow')}
            >Always accept</button
          >
        {/if}
        <button
          class="approve-btn deny"
          onclick={() => onApproveTool(pendingApproval!.callId, 'deny')}
          >Reject</button
        >
      </div>
    </div>
  {:else if streaming && !pendingQuestion}
    <!-- Hide the section-sign spinner while a meta__ask_user is
         pending: the turn is technically still open but the stream
         is paused awaiting the user, so showing the running indicator
         would falsely imply the model is doing work. The question
         card above already signals the state. -->
    <div class="bottom-spinner">
      <SectionSpinner size={48} />
    </div>
  {/if}
</div>

<style>
  .message-list {
    position: relative;
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overflow-x: hidden;
    padding: 0 10px 16px;
    display: block;
    /* Establish a size container so non-sticky user bubbles can cap
       themselves at a fraction of the chat's visible height (via `cqh`)
       rather than the viewport, since the AI chat lives in a sidebar
       whose height is independent of `vh`. */
    container-type: size;
  }
  .assistant-turn.rolled-back {
    opacity: 0.55;
  }
  .turn-note {
    font-size: 11px;
    color: var(--vscode-descriptionForeground);
    margin: -4px 0 8px;
  }
  .rollback-row {
    display: flex;
    justify-content: flex-start;
    margin: -4px 0 10px;
  }
  .rollback-btn {
    border: 1px solid var(--vscode-widget-border, rgba(128, 128, 128, 0.35));
    background: transparent;
    color: var(--vscode-descriptionForeground);
    padding: 2px 10px;
    font-size: 11px;
    border-radius: 3px;
    cursor: pointer;
  }
  .rollback-btn:hover {
    color: var(--vscode-foreground);
    border-color: var(--vscode-foreground);
  }
  .bottom-spinner {
    display: flex;
    justify-content: center;
    align-items: center;
    padding: 4px 0 16px;
  }
  .bottom-approve {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    padding: 10px 0 16px;
  }
  .bottom-approve-label {
    font-size: 11px;
    color: var(--vscode-descriptionForeground);
    text-align: center;
  }
  .bottom-approve-label strong {
    color: var(--vscode-foreground);
    font-family: var(--vscode-editor-font-family, monospace);
    font-weight: normal;
  }
  .bottom-approve-btns {
    display: flex;
    gap: 6px;
  }
  .approve-btn {
    border: 1px solid var(--vscode-widget-border, rgba(128, 128, 128, 0.35));
    background: transparent;
    color: var(--vscode-foreground);
    padding: 3px 14px;
    font-size: 12px;
    border-radius: 3px;
    cursor: pointer;
  }
  .approve-btn:hover {
    border-color: var(--vscode-foreground);
  }
  .approve-btn.allow {
    background: #c8376a;
    border-color: transparent;
    color: #fff;
  }
  .approve-btn.allow:hover {
    background: #d94d7e;
    border-color: transparent;
  }
</style>
