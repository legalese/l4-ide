import {
  PendingInteractions,
  type ChatServiceEvent,
  type ToolCallContext,
  type ToolCallStatus,
  type UserInteraction,
} from '@repo/legalese-agent'
import {
  chatEventToPayload,
  type CloudEventPayload,
} from '@repo/legalese-agent/protocol'

/**
 * {@link UserInteraction} over the file relay (spec §8, §11):
 *
 * - chat-service events are appended to the event log;
 * - there are no tool approvals in cloud sessions (the policy allows
 *   every tool), so {@link requestApproval} allows without an event;
 *   `meta__ask_user` questions become `ask-user`
 *   events and wait for an `answer` command (both through
 *   {@link PendingInteractions}, scoped to conversation and turn);
 * - dispatcher status updates become `tool-call` events carrying the
 *   call's name and arguments (remembered from the chat-service's own
 *   `tool-call` event), like the VS Code sidebar does.
 *
 * `onWaitingChange` reports whether anything is waiting on the user,
 * for the lease state (`waiting` vs `busy`).
 */
export class CloudInteraction implements UserInteraction {
  readonly pending = new PendingInteractions()
  private readonly calls = new Map<
    string,
    { conversationId: string; name: string; argsJson: string }
  >()
  private readonly listeners: Array<(event: ChatServiceEvent) => void> = []

  constructor(
    private readonly sink: (payload: CloudEventPayload) => void,
    private readonly onWaitingChange: (waiting: boolean) => void = () =>
      undefined
  ) {}

  /** Observe chat-service events (the runner tracks `started` / `done`). */
  onEvent(listener: (event: ChatServiceEvent) => void): void {
    this.listeners.push(listener)
  }

  emit(event: ChatServiceEvent): void {
    if (event.kind === 'tool-call') {
      this.calls.set(event.callId, {
        conversationId: event.conversationId,
        name: event.name,
        argsJson: event.argsJson,
      })
    }
    this.sink(chatEventToPayload(event))
    for (const l of this.listeners) l(event)
  }

  /** Never reached with the cloud policy; allows without asking, since
   *  the protocol has no approval event or command. */
  async requestApproval(): Promise<'allow' | 'deny'> {
    return 'allow'
  }

  async askUser(
    question: { callId: string; question: string; choices?: string[] },
    ctx: ToolCallContext
  ): Promise<string> {
    const answer = this.pending.askUser(question.callId, ctx)
    this.sink({
      type: 'ask-user',
      conversationId: ctx.conversationId,
      turnId: ctx.turnId,
      callId: question.callId,
      question: question.question,
      ...(question.choices ? { choices: question.choices } : {}),
    })
    this.onWaitingChange(true)
    try {
      return await answer
    } finally {
      this.onWaitingChange(this.isWaiting())
    }
  }

  notifyToolStatus(
    callId: string,
    status: ToolCallStatus,
    detail: { result?: string; error?: string } | undefined,
    ctx: ToolCallContext
  ): void {
    const meta = this.calls.get(callId)
    this.sink({
      type: 'tool-call',
      conversationId: meta?.conversationId ?? ctx.conversationId,
      callId,
      name: meta?.name ?? '',
      argsJson: meta?.argsJson ?? '{}',
      status,
      ...(detail?.result !== undefined ? { result: detail.result } : {}),
      ...(detail?.error !== undefined ? { error: detail.error } : {}),
    })
    if (status === 'done' || status === 'error') this.calls.delete(callId)
  }

  /** `answer` command. */
  answer(callId: string, answer: string): boolean {
    return this.pending.answer(callId, answer)
  }

  isWaiting(): boolean {
    return this.pending.pendingQuestionCount() > 0
  }
}
