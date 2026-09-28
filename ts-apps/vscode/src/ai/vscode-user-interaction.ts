import {
  PendingInteractions,
  type ChatServiceEvent,
  type ToolCallContext,
  type ToolCallStatus,
  type UserInteraction,
} from '@repo/legalese-agent'

/**
 * {@link UserInteraction} port for the sidebar webview.
 *
 * The chat service and dispatcher are built before the sidebar
 * messenger exists, so the three outbound channels start as no-ops and
 * `registerAiChatHandlers` (register.ts) plugs in the real senders.
 * Waiting approvals and questions live in {@link pending}, scoped to
 * the conversation and turn that raised them; register.ts resolves them
 * from the webview's approve / answer messages and cancels them on a
 * new message or stop in the same conversation.
 */
export class WebviewUserInteraction implements UserInteraction {
  readonly pending = new PendingInteractions()

  /** Forwards chat-service events to the webview (visibility-buffered). */
  emitSink: (event: ChatServiceEvent) => void = () => undefined
  /** Pushes a meta__ask_user question card to the webview. */
  askSink: (callId: string, question: string, choices?: string[]) => void =
    () => undefined
  /** Pushes a dispatcher status update for a tool row. */
  statusSink: (
    callId: string,
    status: ToolCallStatus,
    detail?: { result?: string; error?: string }
  ) => void = () => undefined

  emit(event: ChatServiceEvent): void {
    this.emitSink(event)
  }

  requestApproval(
    call: { callId: string },
    ctx: ToolCallContext
  ): Promise<'allow' | 'deny'> {
    return this.pending.requestApproval(call.callId, ctx)
  }

  askUser(
    q: { callId: string; question: string; choices?: string[] },
    ctx: ToolCallContext
  ): Promise<string> {
    const answer = this.pending.askUser(q.callId, ctx)
    this.askSink(q.callId, q.question, q.choices)
    return answer
  }

  notifyToolStatus(
    callId: string,
    status: ToolCallStatus,
    detail: { result?: string; error?: string } | undefined
  ): void {
    this.statusSink(callId, status, detail)
  }
}
